#################################################################################
# Feedforward type definitions
#
# A feedforward parameterizes a variable in one operation model using values
# produced by another. Construction is a two-stage operation:
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

function get_affected_values(ff::AbstractAffectFeedforward)
    return ff.affected_values
end

function get_component_type(ff::AbstractAffectFeedforward)
    return get_component_type(get_optimization_container_key(ff))
end

function get_feedforward_meta(ff::AbstractAffectFeedforward)
    return get_optimization_container_key(ff).meta
end

"""
Attach a feedforward to a `DeviceModel`. Attaching the same feedforward type with
the same source key twice is a no-op, so a template can be built up incrementally
without duplicating containers.
"""
function attach_feedforward!(
    model::DeviceModel,
    ff::T,
) where {T <: AbstractAffectFeedforward}
    if !isempty(model.feedforwards)
        ff_k = [get_optimization_container_key(v) for v in model.feedforwards if isa(v, T)]
        if get_optimization_container_key(ff) ∈ ff_k
            return
        end
    end
    push!(model.feedforwards, ff)
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

Constructs a parameterized upper bound constraint to implement feedforward from other models.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : Specify the VariableType, ParameterType or AuxVariableType as the source of values for the Feedforward
  - `affected_values::Vector{DataType}` : Specify the variable on which the upper bound will be applied using the source values
  - `add_slacks::Bool = false` : Add slacks variables to relax the upper bound constraint.
"""
struct UpperBoundFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector
    add_slacks::Bool
    function UpperBoundFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        values_vector = Vector(undef, length(affected_values))
        for (ix, v) in enumerate(affected_values)
            if v <: VariableType
                values_vector[ix] =
                    get_optimization_container_key(v, component_type, meta)
            else
                error(
                    "UpperBoundFeedforward is only compatible with VariableType affected values",
                )
            end
        end
        new(
            get_optimization_container_key(T, component_type, meta),
            values_vector,
            add_slacks,
        )
    end
end

get_default_parameter_type(::UpperBoundFeedforward, _) = UpperBoundValueParameter
get_optimization_container_key(ff::UpperBoundFeedforward) = ff.optimization_container_key
get_slacks(ff::UpperBoundFeedforward) = ff.add_slacks

"""
    LowerBoundFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        add_slacks::Bool = false,
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Constructs a parameterized lower bound constraint to implement feedforward from other models.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : Specify the VariableType, ParameterType or AuxVariableType as the source of values for the Feedforward
  - `affected_values::Vector{DataType}` : Specify the variable on which the lower bound will be applied using the source values
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
        values_vector = Vector{VariableKey}(undef, length(affected_values))
        for (ix, v) in enumerate(affected_values)
            if v <: VariableType
                values_vector[ix] =
                    get_optimization_container_key(v, component_type, meta)
            else
                error(
                    "LowerBoundFeedforward is only compatible with VariableType affected values",
                )
            end
        end
        new(
            get_optimization_container_key(T, component_type, meta),
            values_vector,
            add_slacks,
        )
    end
end

get_default_parameter_type(::LowerBoundFeedforward, _) = LowerBoundValueParameter
get_optimization_container_key(ff::LowerBoundFeedforward) = ff.optimization_container_key
get_slacks(ff::LowerBoundFeedforward) = ff.add_slacks

"""
    SemiContinuousFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

It allows to enable/disable bounds to 0.0 for a specified variable. Commonly used to limit the
`ActivePowerVariable` in an Economic Dispatch problem by the commitment decision taken in
an another problem (typically a Unit Commitment problem).

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : Specify the VariableType, ParameterType or AuxVariableType as the source of values for the Feedforward
  - `affected_values::Vector{DataType}` : Specify the variable on which the semicontinuous limit will be applied using the source values
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
        values_vector = Vector{VariableKey}(undef, length(affected_values))
        for (ix, v) in enumerate(affected_values)
            if v <: VariableType
                values_vector[ix] =
                    get_optimization_container_key(v, component_type, meta)
            else
                error(
                    "SemiContinuousFeedforward is only compatible with VariableType affected values",
                )
            end
        end
        new(get_optimization_container_key(T, component_type, meta), values_vector)
    end
end

get_default_parameter_type(::SemiContinuousFeedforward, _) = OnStatusParameter
get_optimization_container_key(f::SemiContinuousFeedforward) = f.optimization_container_key

"""
Whether `model` carries a `SemiContinuousFeedforward` whose affected values include `T`.

Device formulations use this to suppress their own range constraints: when the
commitment status arrives as a parameter from another model, the semicontinuous
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
    sc_feedforwards = [x for x in model.feedforwards if isa(x, SemiContinuousFeedforward)]
    if isempty(sc_feedforwards)
        return false
    end

    keys = get_affected_values(sc_feedforwards[1])

    return T ∈ get_entry_type.(keys)
end

function has_semicontinuous_feedforward(
    model::DeviceModel,
    ::Type{T},
)::Bool where {T <: Union{ActivePowerRangeExpressionUB, ActivePowerRangeExpressionLB}}
    return has_semicontinuous_feedforward(model, ActivePowerVariable)
end

"""
    FixValueFeedforward(
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = CONTAINER_KEY_EMPTY_META
    ) where {T}

Fixes a Variable or Parameter Value in the model from another problem. Is the only Feed Forward that can be used
with a Parameter or a Variable as the affected value.

# Arguments:

  - `component_type::Type{<:PSY.Component}` : Specify the type of component on which the Feedforward will be applied
  - `source::Type{T}` : Specify the VariableType, ParameterType or AuxVariableType as the source of values for the Feedforward
  - `affected_values::Vector{DataType}` : Specify the variable on which the fix value will be applied using the source values
"""
struct FixValueFeedforward <: AbstractAffectFeedforward
    optimization_container_key::OptimizationContainerKey
    affected_values::Vector
    function FixValueFeedforward(;
        component_type::Type{<:PSY.Component},
        source::Type{T},
        affected_values::Vector{DataType},
        meta = IOM.CONTAINER_KEY_EMPTY_META,
    ) where {T}
        values_vector = Vector(undef, length(affected_values))
        for (ix, v) in enumerate(affected_values)
            if v <: VariableType || v <: ParameterType
                values_vector[ix] =
                    get_optimization_container_key(v, component_type, meta)
            else
                error(
                    "FixValueFeedforward is only compatible with VariableType or ParameterType affected values",
                )
            end
        end
        new(get_optimization_container_key(T, component_type, meta), values_vector)
    end
end

get_default_parameter_type(::FixValueFeedforward, _) = FixValueParameter
get_optimization_container_key(ff::FixValueFeedforward) = ff.optimization_container_key
