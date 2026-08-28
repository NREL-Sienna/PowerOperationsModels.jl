"""
Helpers for unit-testing MBC/IEC objective function construction.

Builds minimal PSY systems (one bus, one device) and OptimizationContainers with just the
variables each test needs. Mirrors the pattern in IOM's mock-based helpers, but uses real
PSY types because POM dispatches are keyed on them.

`_add_simple_*!` helpers follow the style in PowerFlows' `test/test_utils/common.jl`:
small single-purpose functions that return the added component, so they can be composed.
"""

function _add_simple_bus!(
    sys::PSY.System;
    number::Int = 1,
    name::String = "bus1",
    bustype = PSY.ACBusTypes.REF,
    base_voltage::Float64 = 230.0,
)
    bus = PSY.ACBus(;
        number = number,
        name = name,
        available = true,
        bustype = bustype,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (0.0, 2.0),
        base_voltage = base_voltage,
    )
    PSY.add_component!(sys, bus)
    return bus
end

function _add_simple_interruptible_load!(
    sys::PSY.System,
    bus::PSY.ACBus,
    cost::PSY.OperationalCost;
    name::String = "load1",
    max_active_power::Float64 = 1.0,
    base_power::Float64 = 100.0,
)
    load = PSY.InterruptiblePowerLoad(;
        name = name,
        available = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        max_active_power = max_active_power,
        max_reactive_power = 0.0,
        operation_cost = cost,
        base_power = base_power,
    )
    PSY.add_component!(sys, load)
    return load
end

"""One-bus system with a single `InterruptiblePowerLoad` carrying `cost`."""
function one_bus_one_interruptible_load(
    cost::PSY.OperationalCost;
    system_base_power::Float64 = 100.0,
    kwargs...,
)
    sys = PSY.System(system_base_power)
    bus = _add_simple_bus!(sys)
    _add_simple_interruptible_load!(sys, bus, cost; kwargs...)
    return sys
end

function _add_simple_source!(
    sys::PSY.System,
    bus::PSY.ACBus,
    cost::PSY.OperationalCost;
    name::String = "source1",
    active_power_limits = (min = -2.0, max = 2.0),
    reactive_power_limits = (min = -2.0, max = 2.0),
    base_power::Float64 = 100.0,
)
    source = PSY.Source(;
        name = name,
        available = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        active_power_limits = active_power_limits,
        reactive_power_limits = reactive_power_limits,
        R_th = 0.01,
        X_th = 0.02,
        internal_voltage = 1.0,
        internal_angle = 0.0,
        base_power = base_power,
    )
    PSY.set_operation_cost!(source, cost)
    PSY.add_component!(sys, source)
    return source
end

"""One-bus system with a single `Source` carrying `cost` (typically ImportExport*Cost)."""
function one_bus_one_source(
    cost::PSY.OperationalCost;
    system_base_power::Float64 = 100.0,
    kwargs...,
)
    sys = PSY.System(system_base_power)
    bus = _add_simple_bus!(sys)
    _add_simple_source!(sys, bus, cost; kwargs...)
    return sys
end

function _add_simple_thermal_standard!(
    sys::PSY.System,
    bus::PSY.ACBus,
    cost::PSY.OperationalCost;
    name::String = "thermal1",
    active_power_limits = (min = 0.1, max = 1.0),
    base_power::Float64 = 100.0,
)
    gen = PSY.ThermalStandard(;
        name = name,
        available = true,
        status = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        rating = 1.0,
        active_power_limits = active_power_limits,
        reactive_power_limits = (min = -1.0, max = 1.0),
        ramp_limits = nothing,
        time_limits = nothing,
        operation_cost = cost,
        base_power = base_power,
        prime_mover_type = PSY.PrimeMovers.OT,
        fuel = PSY.ThermalFuels.OTHER,
    )
    PSY.add_component!(sys, gen)
    return gen
end

"""One-bus system with a single `ThermalStandard` carrying `cost`."""
function one_bus_one_thermal(
    cost::PSY.OperationalCost;
    system_base_power::Float64 = 100.0,
    kwargs...,
)
    sys = PSY.System(system_base_power)
    bus = _add_simple_bus!(sys)
    _add_simple_thermal_standard!(sys, bus, cost; kwargs...)
    return sys
end

function _add_simple_thermal_multistart!(
    sys::PSY.System,
    bus::PSY.ACBus,
    cost::PSY.OperationalCost;
    name::String = "thermal_ms1",
    active_power_limits = (min = 0.1, max = 1.0),
    base_power::Float64 = 100.0,
)
    gen = PSY.ThermalMultiStart(;
        name = name,
        available = true,
        status = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        rating = 1.0,
        prime_mover_type = PSY.PrimeMovers.OT,
        fuel = PSY.ThermalFuels.OTHER,
        active_power_limits = active_power_limits,
        reactive_power_limits = (min = -1.0, max = 1.0),
        ramp_limits = (up = 1.0, down = 1.0),
        power_trajectory = (startup = 0.1, shutdown = 0.1),
        time_limits = (up = 1.0, down = 1.0),
        start_time_limits = (hot = 0.5, warm = 2.0, cold = 6.0),
        start_types = 3,
        operation_cost = cost,
        base_power = base_power,
    )
    PSY.add_component!(sys, gen)
    return gen
end

"""One-bus system with a single `ThermalMultiStart` carrying `cost`."""
function one_bus_one_thermal_multistart(
    cost::PSY.OperationalCost;
    system_base_power::Float64 = 100.0,
    kwargs...,
)
    sys = PSY.System(system_base_power)
    bus = _add_simple_bus!(sys)
    _add_simple_thermal_multistart!(sys, bus, cost; kwargs...)
    return sys
end

function _add_simple_storage!(
    sys::PSY.System,
    bus::PSY.ACBus,
    cost::PSY.OperationalCost;
    name::String = "storage1",
    input_active_power_limits = (min = 0.0, max = 1.0),
    output_active_power_limits = (min = 0.0, max = 1.0),
    base_power::Float64 = 100.0,
)
    storage = PSY.EnergyReservoirStorage(;
        name = name,
        available = true,
        bus = bus,
        prime_mover_type = PSY.PrimeMovers.BA,
        storage_technology_type = PSY.StorageTech.LIB,
        storage_capacity = 4.0,
        storage_level_limits = (min = 0.0, max = 1.0),
        initial_storage_capacity_level = 0.5,
        rating = 1.0,
        active_power = 0.0,
        input_active_power_limits = input_active_power_limits,
        output_active_power_limits = output_active_power_limits,
        efficiency = (in = 0.92, out = 0.92),
        reactive_power = 0.0,
        reactive_power_limits = nothing,
        operation_cost = cost,
        base_power = base_power,
    )
    PSY.add_component!(sys, storage)
    return storage
end

"""One-bus system with a single `EnergyReservoirStorage` carrying `cost`."""
function one_bus_one_storage(
    cost::PSY.OperationalCost;
    system_base_power::Float64 = 100.0,
    kwargs...,
)
    sys = PSY.System(system_base_power)
    bus = _add_simple_bus!(sys)
    _add_simple_storage!(sys, bus, cost; kwargs...)
    return sys
end

"""Build an `OptimizationContainer` wrapping `sys` with the given `time_steps`."""
function build_test_container(
    sys::PSY.System,
    time_steps::UnitRange{Int};
    resolution = Dates.Hour(1),
)
    settings = IOM.Settings(
        sys;
        horizon = Dates.Hour(length(time_steps)),
        resolution = resolution,
    )
    container = IOM.OptimizationContainer(
        sys,
        settings,
        JuMP.Model(),
        PSY.Deterministic,
    )
    IOM.set_time_steps!(container, time_steps)
    return container
end

"""
Allocate a JuMP variable at `(name, t)` in the `V`/`T` container (creating the container
if needed). Returns the new `VariableRef`.
"""
function add_jump_var!(
    container::IOM.OptimizationContainer,
    ::Type{V},
    ::Type{T},
    name::String,
    t::Int,
) where {V <: IOM.VariableType, T}
    if !IOM.has_container_key(container, V, T)
        IOM.add_variable_container!(
            container,
            V,
            T,
            [name],
            IOM.get_time_steps(container),
        )
    end
    var = JuMP.@variable(
        IOM.get_jump_model(container),
        base_name = "$(V)_$(name)_$(t)",
    )
    IOM.get_variable(container, V, T)[name, t] = var
    return var
end

#################################################################################
# Objective coefficient inspection helpers
#
# All return the coefficient of a specific variable in a specific term bucket of the
# container's objective expression. Missing variable ⇒ 0.0 (JuMP.coefficient default).
#################################################################################

"Coefficient of `get_variable(container, V, T)[name, t]` in the objective's invariant terms."
function obj_coef(
    container::IOM.OptimizationContainer,
    ::Type{V},
    ::Type{T},
    name::String,
    t::Int,
) where {V <: IOM.VariableType, T}
    inv = IOM.get_invariant_terms(IOM.get_objective_expression(container))
    return JuMP.coefficient(inv, IOM.get_variable(container, V, T)[name, t])
end

"Coefficient of `get_variable(container, V, T)[name, t]` in the objective's variant terms."
function obj_coef_variant(
    container::IOM.OptimizationContainer,
    ::Type{V},
    ::Type{T},
    name::String,
    t::Int,
) where {V <: IOM.VariableType, T}
    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    return JuMP.coefficient(variant, IOM.get_variable(container, V, T)[name, t])
end

"""
Invariant-term coefficients of the PWL block-offer δ variables for `name` at time `t`,
one per segment, in order.
"""
function pwl_delta_coefs(
    container::IOM.OptimizationContainer,
    dir::IOM.OfferDirection,
    ::Type{T},
    name::String,
    t::Int,
) where {T}
    V = IOM._block_offer_var(dir)
    pwl = IOM.get_variable(container, V, T)
    inv = IOM.get_invariant_terms(IOM.get_objective_expression(container))
    segs = sort!([k[2] for k in keys(pwl.data) if k[1] == name && k[3] == t])
    return [JuMP.coefficient(inv, pwl[(name, s, t)]) for s in segs]
end

#################################################################################
# Time-series cost helpers
#
# Fabricate `ForecastKey`s and build `MarketBidTimeSeriesCost` / TS offer curves without
# attaching real time series data to the system — the TS dispatch path reads from
# pre-populated parameter containers (via `setup_delta_pwl_parameters!` and friends), not
# from the time-series store. Mirrors IOM's pattern in test/test_ts_value_curve_objective.
#################################################################################

# The owner and association id are stubs like everything else here: these keys are
# never resolved against a store, so they only have to be well-formed. A single
# owner and a fixed association id keep two stubs distinguishable by `name` alone,
# which is what the callers below vary.
_stub_forecast_key(name::String) = IS.ForecastKey(;
    owner_id = 1,
    owner_category = IS.InfraStore.Component,
    association_id = 1,
    time_series_type = IS.Deterministic,
    name = name,
    initial_timestamp = Dates.DateTime("2020-01-01"),
    resolution = Dates.Hour(1),
    horizon = Dates.Hour(24),
    interval = Dates.Hour(24),
    count = 1,
    features = Dict{String, Any}(),
)

"""
Construct a `CostCurve{TimeSeriesPiecewiseIncrementalCurve}` with stub TS keys. Pass
`trivial = true` for the absent side of a one-sided participant (a load with no supply
offer, or a generator with no demand offer): it carries reserved empty-name keys, which
IOM's `is_nontrivial_offer` treats as the placeholder/absent side.
"""
function stub_ts_offer_curve(;
    curve_name::String = "variable_cost",
    initial_input_name::String = "initial_input",
    power_units = PSY.SU,
    trivial::Bool = false,
)
    vc = IS.TimeSeriesPiecewiseIncrementalCurve(
        _stub_forecast_key(trivial ? "" : curve_name),
        _stub_forecast_key(trivial ? "" : initial_input_name),
        nothing,
    )
    return PSY.CostCurve(vc, power_units)
end

"Construct a minimal `ImportExportTimeSeriesCost` backed by stub TS keys."
function stub_ts_import_export_cost(;
    power_units = PSY.SU,
)
    return PSY.ImportExportTimeSeriesCost(;
        import_offer_curves = stub_ts_offer_curve(;
            curve_name = "variable_cost import",
            initial_input_name = "initial_input import",
            power_units = power_units,
        ),
        export_offer_curves = stub_ts_offer_curve(;
            curve_name = "variable_cost export",
            initial_input_name = "initial_input export",
            power_units = power_units,
        ),
    )
end

"""
Construct a minimal `MarketBidTimeSeriesCost` backed by stub TS keys. By default both
offer sides are present (a two-sided participant). For a one-sided device pass
`incremental_trivial = true` (a load with no supply offer) or `decremental_trivial = true`
(a generator with no demand offer) so the unused side reads as the absent placeholder.
"""
function stub_ts_market_bid_cost(;
    power_units = PSY.SU,
    incremental_trivial::Bool = false,
    decremental_trivial::Bool = false,
)
    return PSY.MarketBidTimeSeriesCost(;
        minimum_energy_offer = PSY.TimeSeriesLinearCurve(_stub_forecast_key("no_load")),
        start_up = _stub_forecast_key("start_up"),
        shut_down = PSY.TimeSeriesLinearCurve(_stub_forecast_key("shut_down")),
        incremental_offer_curves = stub_ts_offer_curve(;
            curve_name = "variable_cost incremental",
            initial_input_name = "initial_input incremental",
            power_units = power_units,
            trivial = incremental_trivial,
        ),
        decremental_offer_curves = stub_ts_offer_curve(;
            curve_name = "variable_cost decremental",
            initial_input_name = "initial_input decremental",
            power_units = power_units,
            trivial = decremental_trivial,
        ),
    )
end

#################################################################################
# Parameter-container seeding helpers
#
# For TS MBC tests we skip `add_parameters!` (which would require real time series on
# the system) and populate the parameter containers directly with known Float64 values.
# Copied from IOM's `test/test_utils/objective_function_helpers.jl`.
#################################################################################

"""
Populate a 2-D parameter container of size `(names × time_steps)` with `values`. The cell
eltype is taken from `values`, so scalar (`Matrix{Float64}`) and tuple-valued
(`Matrix{NTuple{3, Float64}}`) parameter types both work.
"""
function add_test_parameter!(
    container::IOM.OptimizationContainer,
    ::Type{P},
    ::Type{C},
    names::Vector{String},
    time_steps::UnitRange{Int},
    values::AbstractMatrix,
) where {P <: IOM.ParameterType, C}
    T = eltype(values)
    param_key = IOM.ParameterKey(P, C)
    attributes = IOM.CostFunctionAttributes{T}(
        (), IOM.SOSStatusVariable.NO_VARIABLE, false)
    param_container = IOM.add_param_container_shared_axes!(
        container, param_key, attributes, T, names, time_steps)
    jump_model = IOM.get_jump_model(container)
    for (i, name) in enumerate(names), t in time_steps
        IOM.set_parameter!(param_container, jump_model, values[i, t], name, t)
        IOM.set_multiplier!(param_container, 1.0, name, t)
    end
    return param_container
end

"Populate a 3-D parameter container of size `(names × segments × time_steps)` with `values`."
function add_test_parameter!(
    container::IOM.OptimizationContainer,
    ::Type{P},
    ::Type{C},
    names::Vector{String},
    segments::UnitRange{Int},
    time_steps::UnitRange{Int},
    values::Array{Float64, 3},
) where {P <: IOM.ParameterType, C}
    param_key = IOM.ParameterKey(P, C)
    attributes = IOM.CostFunctionAttributes{Float64}(
        (), IOM.SOSStatusVariable.NO_VARIABLE, false)
    param_container = IOM.add_param_container_shared_axes!(
        container, param_key, attributes, Float64, names, segments, time_steps)
    jump_model = IOM.get_jump_model(container)
    for (i, name) in enumerate(names), (j, seg) in enumerate(segments), t in time_steps
        IOM.set_parameter!(param_container, jump_model, values[i, j, t], name, seg, t)
        IOM.set_multiplier!(param_container, 1.0, name, seg, t)
    end
    return param_container
end

"""
Populate `{Incremental,Decremental}PiecewiseLinear{Slope,Breakpoint}Parameter` containers
for the delta PWL path. Each of `slopes` and `breakpoints` is a `(n_devices × n_times)`
matrix of Vectors; each segment/point Vector's length must be the same across all entries.
"""
function setup_delta_pwl_parameters!(
    container::IOM.OptimizationContainer,
    ::Type{C},
    names::Vector{String},
    slopes::Matrix{Vector{Float64}},
    breakpoints::Matrix{Vector{Float64}},
    time_steps::UnitRange{Int};
    dir::IOM.OfferDirection = IOM.IncrementalOffer(),
) where {C}
    n_segments = length(first(slopes))
    n_points = n_segments + 1
    @assert all(length(s) == n_segments for s in slopes)
    @assert all(length(b) == n_points for b in breakpoints)

    slope_vals = zeros(Float64, length(names), n_segments, length(time_steps))
    bp_vals = zeros(Float64, length(names), n_points, length(time_steps))
    for i in axes(slopes, 1), (ti, t) in enumerate(time_steps)
        for k in 1:n_segments
            slope_vals[i, k, ti] = slopes[i, t][k]
        end
        for k in 1:n_points
            bp_vals[i, k, ti] = breakpoints[i, t][k]
        end
    end
    add_test_parameter!(
        container, IOM._slope_param(dir), C, names, 1:n_segments, time_steps, slope_vals)
    add_test_parameter!(
        container, IOM._breakpoint_param(dir), C, names, 1:n_points, time_steps, bp_vals)
    return
end

"""
Upper-bound widths encoded by the per-segment `δ_k ≤ breakpoints[k+1] - breakpoints[k]`
constraints that `add_pwl_block_offer_constraints!` emits as anonymous JuMP constraints.
Returns one value per segment, in order.
"""
function pwl_delta_widths(
    container::IOM.OptimizationContainer,
    dir::IOM.OfferDirection,
    ::Type{T},
    name::String,
    t::Int,
) where {T}
    V = IOM._block_offer_var(dir)
    pwl = IOM.get_variable(container, V, T)
    jmodel = IOM.get_jump_model(container)
    segs = sort!([k[2] for k in keys(pwl.data) if k[1] == name && k[3] == t])

    # The width constraints have ScalarAffineFunction(δ) ≤ width. Index by VariableRef.
    widths_by_var = Dict{JuMP.VariableRef, Float64}()
    for cref in JuMP.all_constraints(
        jmodel, JuMP.AffExpr, JuMP.MOI.LessThan{Float64})
        aff = JuMP.constraint_object(cref).func
        JuMP.constant(aff) == 0.0 || continue
        length(JuMP.linear_terms(aff)) == 1 || continue
        (c, v), = JuMP.linear_terms(aff)
        c == 1.0 || continue
        widths_by_var[v] = JuMP.constraint_object(cref).set.upper
    end
    return [widths_by_var[pwl[(name, s, t)]] for s in segs]
end
