#################################################################################
# Runtime interface
#
# POM builds the event parameters; a simulation runtime (PSI) owns the state
# arrays, the clock and the RNG, and decides where values land. These functions
# are the domain half of that split: given an outage attribute, its event model,
# a time, and the countdown carried over from the previous step, they say what
# the event parameters should hold. They touch no state type, so a runtime can
# call them with whatever containers it keeps, and they are testable here without
# a simulation.
#
# The division of labor per runtime step is:
#
#   1. POM:     `required_inputs` says what the event model's condition needs;
#               the runtime resolves those, then `is_triggered` decides whether an
#               outage may begin this step
#   2. runtime: read the countdown the previous step left behind
#   3. POM:     `event_step_values` -> countdown, availability, offset for now
#   4. POM:     `countdown_trajectory` / `availability_trajectory` to project the
#               outage forward across the horizon the next decision model sees
#   5. runtime: write those into state, in `event_parameter_keys` order, at its
#               own resolution
#
# Step 1 gates only whether an outage *begins*. Steps 3-5 run for a device with a
# live countdown whatever the condition says, so an outage always recovers.
#################################################################################

"""
Ordered event parameter types a runtime must update for a device under an outage
event. The order is load-bearing: the countdown carries the outage's memory, so it
is written first and the availability derived from it is written last, with the
balance offsets in between.
"""
const EVENT_PARAMETER_UPDATE_ORDER = (
    AvailableStatusChangeCountdownParameter,
    ActivePowerOffsetParameter,
    ReactivePowerOffsetParameter,
    AvailableStatusParameter,
)

"""
    event_parameter_keys(container, ::Type{D})

The event parameter keys a runtime must update for device type `D`, in the order they
must be written, restricted to those the built model actually has. Which offsets exist
depends on the device family and the network model (a load under an AC network gets
both offsets; a thermal unit gets neither), so a runtime should ask rather than assume.
"""
function event_parameter_keys(container::OptimizationContainer, ::Type{D}) where {D}
    return [
        IOM.ParameterKey(T, D) for T in EVENT_PARAMETER_UPDATE_ORDER if
        IOM.has_container_key(container, T, D)
    ]
end

#################################################################################
# Occurrence and duration: the only per-contingency-type behavior
#################################################################################

function _timeseries_name(event_model::EventModel, key::Symbol)
    mapping = event_model.timeseries_mapping
    return haskey(mapping, key) ? mapping[key] : nothing
end

"""
    outage_occurred(event, event_model, current_time; rng)

Whether an outage begins at `current_time`.

  - `PSY.FixedForcedOutage`: deterministic, read from the `:outage_status` series
    attached to the attribute. The value read is the one *following* `current_time`,
    matching PSI: the runtime decides at the end of a step what the next step looks
    like. A series with no following value reads as no outage.
  - `PSY.GeometricDistributionForcedOutage`: a Bernoulli draw from `rng` with the
    attribute's `outage_transition_probability`, or the value of the time series named
    by `:outage_transition_probability` when the event model maps one.

`rng` is required for the stochastic types and ignored by the deterministic ones, so a
runtime can call this uniformly.
"""
function outage_occurred(
    event::PSY.FixedForcedOutage,
    event_model::EventModel,
    current_time::Dates.DateTime;
    rng::Union{Nothing, Random.AbstractRNG} = nothing,
)
    name = _timeseries_name(event_model, :outage_status)
    isnothing(name) && error(
        "The event model for $(typeof(event)) has no :outage_status time series mapping",
    )
    values = IS.get_time_series_values(
        IS.SingleTimeSeries,
        event,
        name;
        start_time = current_time,
        len = 2,
    )
    length(values) < 2 && return false
    return values[2] != 0.0
end

function outage_occurred(
    event::PSY.GeometricDistributionForcedOutage,
    event_model::EventModel,
    current_time::Dates.DateTime;
    rng::Union{Nothing, Random.AbstractRNG} = nothing,
)
    isnothing(rng) &&
        error("$(typeof(event)) is stochastic: pass the simulation's rng")
    name = _timeseries_name(event_model, :outage_transition_probability)
    λ = if isnothing(name)
        PSY.get_outage_transition_probability(event)
    else
        only(
            IS.get_time_series_values(
                IS.SingleTimeSeries,
                event,
                name;
                start_time = current_time,
                len = 1,
            ),
        )
    end
    return rand(rng) < λ
end

"""
    time_to_recover(event, event_model, current_time; mttr_units = Dates.Minute)

How long the outage beginning at `current_time` lasts, as a `Dates.Period`.

  - `PSY.FixedForcedOutage`: the distance to the next available step in the
    `:outage_status` series. A series that never returns to available counts as out for
    its full remaining length.
  - `PSY.GeometricDistributionForcedOutage`: `mean_time_to_recovery` from the attribute,
    or from the series named by `:mean_time_to_recovery` when the event model maps one.

!!! warning
    `mttr_units` exists because the unit of `mean_time_to_recovery` is not settled
    upstream: PowerSystems documents it as minutes, while PSI's runtime reads it as
    hours (`mttr_hr`, with an hourly `mttr_resolution`). The default follows the
    PowerSystems docstring. Pass `Dates.Hour` to reproduce PSI's behavior.
"""
function time_to_recover(
    event::PSY.FixedForcedOutage,
    event_model::EventModel,
    current_time::Dates.DateTime;
    mttr_units = Dates.Minute,
)
    name = _timeseries_name(event_model, :outage_status)
    ts = PSY.get_time_series(IS.SingleTimeSeries, event, name; start_time = current_time)
    values = IS.get_time_series_values(
        IS.SingleTimeSeries,
        event,
        name;
        start_time = current_time,
    )
    resolution = IS.get_resolution(ts)
    # `values[1]` is the step at `current_time` and `values[2]` is where the outage
    # begins, so a first available step at `values[2 + j]` means the outage ran for `j`
    # steps. A profile that never returns to available is out for the rest of its own
    # length; the series is the only evidence available, so the answer is truncated to
    # it. (PSI returns `length(values)` there, one step more than the profile shows.)
    available = findfirst(isequal(0.0), @view values[3:end])
    steps = isnothing(available) ? max(length(values) - 1, 0) : available
    return resolution * steps
end

function time_to_recover(
    event::PSY.GeometricDistributionForcedOutage,
    event_model::EventModel,
    current_time::Dates.DateTime;
    mttr_units = Dates.Minute,
)
    name = _timeseries_name(event_model, :mean_time_to_recovery)
    mttr = if isnothing(name)
        PSY.get_mean_time_to_recovery(event)
    else
        only(
            IS.get_time_series_values(
                IS.SingleTimeSeries,
                event,
                name;
                start_time = current_time,
                len = 1,
            ),
        )
    end
    return mttr_units(round(Int, mttr))
end

#################################################################################
# Countdown, availability and offsets: shared by every contingency type
#################################################################################

"""
    countdown_steps(duration, resolution)

`duration` expressed as a whole number of steps of length `resolution`, rounded up with
a warning when it does not divide evenly. An outage cannot end partway through a step,
so the choice is between ending it early and ending it late; rounding up keeps the
device out for at least as long as the data says.

# TODO(events): rounding up matches PSI, which has always tolerated durations that do
# not divide the state resolution. Erroring instead would surface those fixtures, at the
# cost of breaking runs that work today. Revisit once the MTTR units question below is
# settled, since the two interact: an MTTR read in the wrong unit is exactly what
# produces a duration that does not divide evenly.
"""
function countdown_steps(duration::Dates.Period, resolution::Dates.Period)
    steps = Dates.Millisecond(duration) / Dates.Millisecond(resolution)
    if !isinteger(steps)
        @warn "Outage duration $duration is not a whole number of $resolution steps; \
               rounding up to $(Int(ceil(steps))) steps" _group =
            IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    end
    return Int(ceil(steps))
end

"""
    advance_countdown(previous, occurred, duration_steps)

The countdown after one step: a new outage starts the clock at `duration_steps`, an
outage already running loses a step, and an available device stays at zero. An outage
that fires while the device is already out does not extend it, matching PSI, where only
an available device can transition.
"""
function advance_countdown(previous::Real, occurred::Bool, duration_steps::Int)
    previous > 0 && return max(previous - 1, 0)
    return occurred ? Float64(duration_steps) : 0.0
end

"""
    countdown_trajectory(remaining, n_steps)

The countdown projected across `n_steps` steps, starting from `remaining` now. This is
what carries an in-progress outage into the horizon of the next decision model: the
model is built once, so the whole trajectory has to be written up front rather than
discovered step by step.
"""
countdown_trajectory(remaining::Real, n_steps::Int) =
    [max(Float64(remaining) - (i - 1), 0.0) for i in 1:n_steps]

"""
    availability_from_countdown(countdown)

Availability implied by a countdown: 0 while the outage still has steps to run, 1
otherwise. Availability is always derived, never stored independently, so the two can
never disagree.
"""
availability_from_countdown(countdown::Real) = countdown > 0 ? 0.0 : 1.0

"""
    availability_trajectory(remaining, n_steps)

`availability_from_countdown` applied to [`countdown_trajectory`](@ref).
"""
availability_trajectory(remaining::Real, n_steps::Int) =
    availability_from_countdown.(countdown_trajectory(remaining, n_steps))

"""
    outage_power_offset(countdown, injection)

The balance offset for a device with no dispatch variable: the negated injection while
the device is out, zero otherwise. Added to the balance expression alongside the
device's own time series term, it cancels that term for the duration of the outage.

`injection` is the value the device's time-series parameter contributes to the balance,
so the same function serves the active and reactive offsets.

# TODO(events): PSI writes the offset only on the step an outage begins
# (`status == 1 && countdown == 1` in `simulation_state.jl`), not for its whole duration.
# That reads as an artifact of advancing one step at a time rather than an intended
# window, and cancelling the injection for as long as the device is out is what an
# outage means, but it is a behavior change from PSI and should be confirmed against a
# simulation before PSI is rewired to this.
"""
outage_power_offset(countdown::Real, injection::Real) =
    countdown > 0 ? -Float64(injection) : 0.0

"""
    event_step_values(event, event_model, current_time, previous_countdown; kwargs...)

Everything one runtime step needs for one device, as a named tuple of `occurred`,
`countdown`, `availability`, `active_power_offset` and `reactive_power_offset`.

`resolution` is the runtime's state resolution, which sets what a countdown step means.
`active_power_injection` / `reactive_power_injection` are the device's own time-series
contributions to the balance, needed only for devices that carry offset parameters;
they default to zero, which is what a device bounded by an outage constraint wants.
"""
function event_step_values(
    event::PSY.Contingency,
    event_model::EventModel,
    current_time::Dates.DateTime,
    previous_countdown::Real;
    resolution::Dates.Period,
    rng::Union{Nothing, Random.AbstractRNG} = nothing,
    mttr_units = Dates.Minute,
    active_power_injection::Real = 0.0,
    reactive_power_injection::Real = 0.0,
)
    occurred = false
    duration_steps = 0
    if previous_countdown <= 0
        occurred = outage_occurred(event, event_model, current_time; rng = rng)
        if occurred
            duration_steps = countdown_steps(
                time_to_recover(
                    event,
                    event_model,
                    current_time;
                    mttr_units = mttr_units,
                ),
                resolution,
            )
        end
    end
    countdown = advance_countdown(previous_countdown, occurred, duration_steps)
    return (
        occurred = occurred,
        countdown = countdown,
        availability = availability_from_countdown(countdown),
        active_power_offset = outage_power_offset(countdown, active_power_injection),
        reactive_power_offset = outage_power_offset(countdown, reactive_power_injection),
    )
end

#################################################################################
# Conditions
#
# A condition declares the inputs it needs; the runtime resolves those into plain
# values; the condition is then evaluated as a function of its own inputs and
# nothing else. `ContinuousCondition` is handed nothing, and only
# `DiscreteEventCondition` — the escape hatch for arbitrary user predicates —
# asks for the runtime's state object, which POM never inspects.
#
# A runtime evaluates one condition with:
#
#     inputs = map(i -> resolve_input(i, its_state), required_inputs(condition))
#     is_triggered(condition, current_time, inputs)
#
# where `resolve_input` is the runtime's, with one method per input type.
#################################################################################

"""
Abstract type for a value an [`AbstractEventCondition`](@ref) needs from a runtime.
POM declares what is needed; the runtime resolves it.
"""
abstract type AbstractConditionInput end

"""
    StateValueInput(variable_type, device_type, device_name)

Request for the runtime's current value of one optimization variable, for one device.
"""
struct StateValueInput <: AbstractConditionInput
    variable_type::VariableType
    device_type::Type{<:PSY.Device}
    device_name::String
end

get_variable_type(i::StateValueInput) = i.variable_type
get_device_type(i::StateValueInput) = i.device_type
get_device_name(i::StateValueInput) = i.device_name

"""
    RuntimeStateInput()

Request for the runtime's state object itself, passed through to user code untouched.
Declared only by [`DiscreteEventCondition`](@ref), whose whole purpose is a predicate
POM cannot anticipate; every other condition is a function of declared values.
"""
struct RuntimeStateInput <: AbstractConditionInput end

"""
    required_inputs(condition)

The inputs `condition` needs from a runtime, as a tuple of [`AbstractConditionInput`](@ref).
Empty for conditions that depend on nothing but the clock, which is passed to
[`is_triggered`](@ref) directly.
"""
required_inputs(::AbstractEventCondition) = ()

required_inputs(c::StateVariableValueCondition) =
    (StateValueInput(get_variable_type(c), get_device_type(c), get_device_name(c)),)

required_inputs(::DiscreteEventCondition) = (RuntimeStateInput(),)

"""
    is_triggered(condition, current_time, inputs = ())

Whether an event model's condition fires. `inputs` are the resolved values of
[`required_inputs`](@ref), in the same order.

A runtime evaluates this once per event model, before applying any outage values; a
condition that does not fire leaves the event parameters alone. It gates whether an
outage *begins* — an outage already running keeps counting down regardless, or a
condition that fires once could never recover.
"""
is_triggered(::ContinuousCondition, ::Dates.DateTime, ::Tuple = ()) = true

is_triggered(c::PresetTimeCondition, current_time::Dates.DateTime, ::Tuple = ()) =
    current_time in get_time_stamps(c)

function is_triggered(
    c::StateVariableValueCondition,
    ::Dates.DateTime,
    inputs::Tuple,
)
    return isapprox(only(inputs), IOM.get_value(c); atol = IOM.ABSOLUTE_TOLERANCE)
end

is_triggered(c::DiscreteEventCondition, ::Dates.DateTime, inputs::Tuple) =
    get_condition_function(c)(only(inputs))::Bool
