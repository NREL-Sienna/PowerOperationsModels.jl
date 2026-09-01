#################################################################################
# Feedforward type definitions
#
# A feedforward binds a model's variables to the recorded state of the system: the
# source names a quantity in that state, never the model that last wrote it.
# Construction is a two-stage operation:
#
#   1. ArgumentConstructStage -- `add_feedforward_arguments!` allocates the
#      `VariableValueParameter` container (and any slack variables) that will
#      carry the source model's values.  See `feedforward_arguments.jl`.
#   2. ModelConstructStage -- `add_feedforward_constraints!` builds the JuMP
#      constraints tying the affected variables to that parameter.  See
#      `feedforward_constraints.jl`.
#
# Populating the parameter between model executions is a separate concern that
# lives in PowerSimulations (it needs `SimulationState`); POM only builds the
# containers and the constraints that read them.
#
# NOTE: service-side feedforwards are deliberately NOT implemented here. PR #206
# replaced the one-`ServiceModel`-per-service design (which carried a
# `service_name` field) with per-type service models whose reserve variables are
# sparse and keyed `(service_name, device_name, time)`. The feedforward parameter
# path is still keyed `(device_name, time)`, so the two are dimensionally
# inconsistent. See the TODO at `common_models/add_parameters.jl` for the fix.
#################################################################################

function get_optimization_container_key(ff::AbstractAffectFeedforward)
    return ff.optimization_container_key
end

function get_affected_values(ff::AbstractAffectFeedforward)
    return ff.affected_values
end

function get_component_type(ff::AbstractAffectFeedforward)
    return get_component_type(get_optimization_container_key(ff))
end

function get_feedforward_meta(ff::AbstractAffectFeedforward)
    return get_optimization_container_key(ff).meta
end

# Whether a feedforward is of concrete type `FF`, as dispatch rather than an `isa`/`<:`
# check -- shared by `has_semicontinuous_feedforward` and `has_waterbudget_feedforward`
# instead of each keeping its own "default false, true for my type" trait pair.
_is_feedforward_type(
    ::AbstractAffectFeedforward,
    ::Type{<:AbstractAffectFeedforward},
)::Bool = false
_is_feedforward_type(::FF, ::Type{FF}) where {FF <: AbstractAffectFeedforward} = true

# Which affected-value types a feedforward accepts is dispatch on the feedforward type,
# not a runtime `<:`/`isa` branch. `FixValueFeedforward` adds a `ParameterType` method
# next to its struct definition below.
_valid_affected_type(::Type{<:AbstractAffectFeedforward}, ::Type{<:VariableType}) = true
_valid_affected_type(::Type{<:AbstractAffectFeedforward}, ::Type) = false
_affected_type_description(::Type{<:AbstractAffectFeedforward}) = "VariableType"

function _affected_values_vector(
    ::Type{FF},
    affected_values::Vector{DataType},
    component_type::Type{<:PSY.Component},
    meta,
) where {FF <: AbstractAffectFeedforward}
    values_vector = Vector{OptimizationContainerKey}(undef, length(affected_values))
    for (ix, v) in enumerate(affected_values)
        if !_valid_affected_type(FF, v)
            error(
                "$FF is only compatible with $(_affected_type_description(FF)) affected " *
                "values; got $v",
            )
        end
        values_vector[ix] = get_optimization_container_key(v, component_type, meta)
    end
    return values_vector
end

# Every feedforward's inner constructor pairs `_affected_values_vector` (validates and
# builds the affected-values vector) with `get_optimization_container_key` (builds the
# source key) -- shared here so each struct constructor below is a single call instead of
# repeating the pairing.
function _feedforward_key_and_values(
    ::Type{FF},
    ::Type{T},
    component_type::Type{<:PSY.Component},
    affected_values::Vector{DataType},
    meta,
) where {FF <: AbstractAffectFeedforward, T}
    values_vector = _affected_values_vector(FF, affected_values, component_type, meta)
    return get_optimization_container_key(T, component_type, meta), values_vector
end

# Shared by `feedforward_arguments.jl` and `feedforward_constraints.jl`: every
# feedforward-affected-variable container is asserted to share the device fleet's names
# and the container's time steps before it is used. Returns the variable's own name axis,
# which subsequent loops index by (its order need not match `devices_names`).
function _check_device_time_axes(variable, devices_names, time_steps)
    device_name_set, set_time = JuMP.axes(variable)
    @assert issetequal(device_name_set, devices_names)
    IS.@assert_op set_time == time_steps
    return device_name_set
end

"""
Attach a feedforward to a `DeviceModel`. Attaching a field-for-field identical feedforward
twice is a no-op, so a template can be built up incrementally without duplicating
containers. Attaching a second feedforward that shares a source key with an attached one but
differs in any other field errors, naming the conflicting fields. Attaching a second,
differing `SemiContinuousFeedforward` for the same component type also errors: only one can
supply the `OnStatusParameter` container. Likewise, only one `UpperBoundFeedforward` and one
`LowerBoundFeedforward` per device model are supported today (see `_check_bound_conflict`).
"""
function attach_feedforward!(
    model::DeviceModel,
    ff::AbstractAffectFeedforward,
)
    for attached in model.feedforwards
        _duplicate_feedforward(attached, ff) && return
        _check_semicontinuous_conflict(attached, ff)
        _check_bound_conflict(attached, ff)
    end
    push!(model.feedforwards, ff)
    return
end

# Fields that differ between two feedforwards of the same concrete type, compared
# generically so no per-type field list needs maintaining as new feedforward types appear.
function _differing_fieldnames(a::T, b::T) where {T <: AbstractAffectFeedforward}
    return [f for f in fieldnames(T) if getfield(a, f) != getfield(b, f)]
end

# Same concrete type and same source key means the same container would otherwise be built
# twice. A field-for-field identical attachment is a silent no-op; one that shares the
# source key but differs elsewhere (e.g. `affected_values`, `add_slacks`) would silently
# drop the difference if treated as a no-op, so it errors instead.
function _duplicate_feedforward(
    a::T,
    b::T,
)::Bool where {T <: AbstractAffectFeedforward}
    if get_optimization_container_key(a) != get_optimization_container_key(b)
        return false
    end
    conflicting_fields = _differing_fieldnames(a, b)
    if isempty(conflicting_fields)
        return true
    end
    throw(
        ArgumentError(
            "Cannot attach $T for component type $(get_component_type(b)): a feedforward " *
            "with the same source key ($(get_optimization_container_key(b))) is already " *
            "attached, but field(s) $(conflicting_fields) differ. Detach the existing " *
            "feedforward first, or make the two definitions identical.",
        ),
    )
end

function _duplicate_feedforward(
    ::AbstractAffectFeedforward,
    ::AbstractAffectFeedforward,
)::Bool
    return false
end

# Forward-declared: `SemiContinuousFeedforward` isn't defined until further down this
# file, but `attach_feedforward!` above needs to dispatch on it. The fallback method is
# added here; the concrete-type method is added next to `SemiContinuousFeedforward`.
function _check_semicontinuous_conflict(
    ::AbstractAffectFeedforward,
    ::AbstractAffectFeedforward,
)
    return
end

# Forward-declared for the same reason as `_check_semicontinuous_conflict` above:
# `UpperBoundFeedforward`/`LowerBoundFeedforward` aren't defined until further down this
# file. The concrete-type method is added below `_bound_direction`.
function _check_bound_conflict(
    ::AbstractAffectFeedforward,
    ::AbstractAffectFeedforward,
)
    return
end

function attach_feedforward!(::ServiceModel, ::T) where {T <: AbstractAffectFeedforward}
    error(
        "Service feedforwards are not supported yet. The per-type `ServiceModel` \
         introduced in POM #206 keys its reserve variables by `(service_name, \
         device_name, time)`, but the feedforward parameter path is keyed \
         `(device_name, time)`. Re-key the service `VariableValueParameter` path by \
         `(service, device)` before attaching feedforwards to a `ServiceModel`.",
    )
end

"""
    UpperBoundFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Constructs a parameterized upper bound constraint from a quantity in the system state.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : The VariableType or AuxVariableType naming the quantity in the system state that the Feedforward reads
  - `affected_values::Vector{DataType}` : Specify the variable on which the upper bound will be applied from the state values
  - `add_slacks::Bool = false` : Add slacks variables to relax the upper bound constraint.
"""
struct UpperBoundFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector{<:OptimizationContainerKey}
    add_slacks::Bool
    function UpperBoundFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        key, values_vector = _feedforward_key_and_values(
            UpperBoundFeedforward,
            T,
            component_type,
            affected_values,
            meta,
        )
        new(key, values_vector, add_slacks)
    end
end

get_default_parameter_type(::UpperBoundFeedforward, _) = UpperBoundValueParameter

"""
    LowerBoundFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Constructs a parameterized lower bound constraint from a quantity in the system state.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : The VariableType or AuxVariableType naming the quantity in the system state that the Feedforward reads
  - `affected_values::Vector{DataType}` : Specify the variable on which the lower bound will be applied from the state values
  - `add_slacks::Bool = false` : Add slacks variables to relax the lower bound constraint.
"""
struct LowerBoundFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector{<:OptimizationContainerKey}
    add_slacks::Bool
    function LowerBoundFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        key, values_vector = _feedforward_key_and_values(
            LowerBoundFeedforward,
            T,
            component_type,
            affected_values,
            meta,
        )
        new(key, values_vector, add_slacks)
    end
end

get_default_parameter_type(::LowerBoundFeedforward, _) = LowerBoundValueParameter
get_slacks(ff::Union{UpperBoundFeedforward, LowerBoundFeedforward}) = ff.add_slacks

# Bridges the feedforward type to `IOM.BoundDirection` so `_add_feedforward_slack_variables!`
# can key off `feedforward_constraints.jl`'s single `_feedforward_slack_type` table instead
# of keeping a second, separately-maintained one.
_bound_direction(::Type{UpperBoundFeedforward}) = IOM.UpperBound()
_bound_direction(::Type{LowerBoundFeedforward}) = IOM.LowerBound()

# `UpperBoundValueParameter`/`LowerBoundValueParameter` containers are keyed only by
# parameter type and component type (see `common_models/add_parameters.jl`), not by source,
# so two differing-source feedforwards of the same concrete bound type would collide on one
# container deep inside argument construction. Reject the second one here instead. An
# identical second attachment is caught by `_duplicate_feedforward` before this ever runs.
function _check_bound_conflict(
    a::T,
    b::T,
) where {T <: Union{UpperBoundFeedforward, LowerBoundFeedforward}}
    throw(
        ArgumentError(
            "Cannot attach a second $T for component type $(get_component_type(b)): " *
            "$(get_optimization_container_key(a)) is already attached; " *
            "$(get_optimization_container_key(b)) would conflict. Only one $T per device " *
            "model is supported today.",
        ),
    )
end

"""
    SemiContinuousFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Bounds a variable to zero or to the device's operating range according to a commitment
status recorded in the system state. Commonly used to hold the `ActivePowerVariable` of an
Economic Dispatch to the units the system state reports as online. A `DeviceModel` can carry
at most one `SemiContinuousFeedforward` per component type; `attach_feedforward!` rejects a
second.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : The VariableType or AuxVariableType naming the quantity in the system state that the Feedforward reads
  - `affected_values::Vector{DataType}` : Specify the variable on which the semicontinuous limit will be applied from the state values
"""
struct SemiContinuousFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector{<:OptimizationContainerKey}
    function SemiContinuousFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        key, values_vector = _feedforward_key_and_values(
            SemiContinuousFeedforward,
            T,
            component_type,
            affected_values,
            meta,
        )
        new(key, values_vector)
    end
end

get_default_parameter_type(::SemiContinuousFeedforward, _) = OnStatusParameter

# The commitment status arrives through a single `OnStatusParameter` container keyed only
# by parameter and component type, so a device model can carry at most one semicontinuous
# source per component type. Catching a second, differing one here turns an obscure
# "is already stored" failure deep inside argument construction into an immediate,
# actionable error. An exact duplicate is handled by `_duplicate_feedforward` and never
# reaches this check.
function _check_semicontinuous_conflict(
    a::SemiContinuousFeedforward,
    b::SemiContinuousFeedforward,
)
    if get_component_type(a) == get_component_type(b)
        error(
            "Cannot attach a second SemiContinuousFeedforward for component type " *
            "$(get_component_type(b)): $(get_optimization_container_key(a)) is already " *
            "attached; $(get_optimization_container_key(b)) would conflict. A device " *
            "model may carry at most one semicontinuous feedforward per component type.",
        )
    end
    return
end

"""
Whether `model` carries a `SemiContinuousFeedforward` whose affected values include `T`.

Device formulations use this to suppress their own range constraints: when the
commitment status arrives as a parameter read from the system state, the semicontinuous
feedforward constraints replace the formulation's native bounds. Adding both would
double-constrain the variable.
"""
function has_semicontinuous_feedforward(
    model::DeviceModel,
    ::Type{T},
)::Bool where {T <: Union{VariableType, ExpressionType}}
    if isempty(model.feedforwards)
        return false
    end
    # A device model carries at most one SemiContinuousFeedforward but may carry other
    # feedforward types alongside it, so filter across the whole list rather than assume
    # position.
    return any(
        _is_feedforward_type(ff, SemiContinuousFeedforward) &&
        T ∈ get_entry_type.(get_affected_values(ff)) for ff in model.feedforwards
    )
end

"""
Whether `model` carries any `SemiContinuousFeedforward` at all, regardless of which
variables it affects. The commitment status then arrives as a variable-valued parameter,
so formulations must not also build a float-valued `OnStatusParameter` for it.
"""
function has_semicontinuous_feedforward(model::DeviceModel)::Bool
    return any(
        ff -> _is_feedforward_type(ff, SemiContinuousFeedforward),
        model.feedforwards,
    )
end

"""
The variable a device formulation schedules power through. Most formulations schedule
`ActivePowerVariable` directly; compact formulations schedule `PowerAboveMinimumVariable`
instead, so a `SemiContinuousFeedforward` attached to one of those must be checked against
`PowerAboveMinimumVariable`, not the default.
"""
_scheduled_power_variable(::Type{<:AbstractDeviceFormulation}) = ActivePowerVariable

function has_semicontinuous_feedforward(
    model::DeviceModel,
    ::Type{T},
)::Bool where {T <: Union{ActivePowerRangeExpressionUB, ActivePowerRangeExpressionLB}}
    return has_semicontinuous_feedforward(
        model,
        _scheduled_power_variable(get_formulation(model)),
    )
end

"""
    FixValueFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Fixes a Variable or Parameter Value in the model to a quantity read from the system state.
Is the only Feed Forward that can be used with a Parameter or a Variable as the affected
value.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : The VariableType or AuxVariableType naming the quantity in the system state that the Feedforward reads
  - `affected_values::Vector{DataType}` : Specify the variable on which the fix value will be applied from the state values
"""
struct FixValueFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    # Both `VariableKey` and `ParameterKey` land here -- this is the only feedforward that
    # takes a parameter as an affected value -- so the element type is their supertype.
    affected_values::Vector{<:OptimizationContainerKey}
    function FixValueFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        key, values_vector = _feedforward_key_and_values(
            FixValueFeedforward,
            T,
            component_type,
            affected_values,
            meta,
        )
        new(key, values_vector)
    end
end

get_default_parameter_type(::FixValueFeedforward, _) = FixValueParameter
_valid_affected_type(::Type{FixValueFeedforward}, ::Type{<:ParameterType}) = true
_affected_type_description(::Type{FixValueFeedforward}) = "VariableType or ParameterType"

"""
    WaterLevelBudgetFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Bounds a reservoir's cumulative outgoing water flow, summed over the full model horizon, to
a water usage budget read from the system state.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : The VariableType, ParameterType, or ExpressionType naming the quantity in the system state that the Feedforward reads
  - `affected_values::Vector{DataType}` : Specify the parameter on which the water budget will be applied from the state values
"""
struct WaterLevelBudgetFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector{<:OptimizationContainerKey}
    function WaterLevelBudgetFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        key, values_vector = _feedforward_key_and_values(
            WaterLevelBudgetFeedforward,
            T,
            component_type,
            affected_values,
            meta,
        )
        new(key, values_vector)
    end
end

get_default_parameter_type(::WaterLevelBudgetFeedforward, _) = WaterLevelBudgetParameter
# Overrides the generic `VariableType`-accepting default above: this feedforward only
# ever builds a `WaterLevelBudgetParameter` container, so a `VariableType` affected value
# would silently reach `get_variable` inside `add_feedforward_constraints!` instead of
# erroring here at construction.
_valid_affected_type(::Type{WaterLevelBudgetFeedforward}, ::Type{<:VariableType}) = false
_valid_affected_type(::Type{WaterLevelBudgetFeedforward}, ::Type{<:ParameterType}) = true
_affected_type_description(::Type{WaterLevelBudgetFeedforward}) = "ParameterType"

"""
Whether `model` carries a `WaterLevelBudgetFeedforward`.
"""
function has_waterbudget_feedforward(model::DeviceModel)::Bool
    return any(
        ff -> _is_feedforward_type(ff, WaterLevelBudgetFeedforward),
        model.feedforwards,
    )
end
