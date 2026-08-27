#################################################################################
# Feedforward arguments (ArgumentConstructStage)
#
# Allocates the `VariableValueParameter` container that carries the source
# model's values, plus any slack variables the feedforward relaxes its
# constraint with. The constraints themselves are built in the
# ModelConstructStage; see `feedforward_constraints.jl`.
#################################################################################

function add_feedforward_arguments!(
    container::OptimizationContainer,
    model::DeviceModel,
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    for ff in get_feedforwards(model)
        @debug "arguments" ff V _group = IOM.LOG_GROUP_FEEDFORWARDS_CONSTRUCTION
        _add_feedforward_arguments!(container, model, devices, ff)
    end
    return
end

function add_feedforward_arguments!(
    ::OptimizationContainer,
    model::ServiceModel,
    ::PSY.Service,
)
    ffs = get_feedforwards(model)
    if !isempty(ffs)
        throw(
            ArgumentError(
                "Service feedforwards are not supported yet; see `attach_feedforward!`.",
            ),
        )
    end
    return
end

function _add_feedforward_arguments!(
    container::OptimizationContainer,
    model::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::AbstractAffectFeedforward,
) where {T <: PSY.Device, U <: AbstractDeviceFormulation}
    parameter_type = get_default_parameter_type(ff, T)
    add_parameters!(container, parameter_type, ff, model, devices)
    return
end

# Penalized at `BALANCE_SLACK_COST`; PSI leaves the device-path slacks free, which makes
# the relaxed bound never bind.
function _add_feedforward_slack_variables!(
    container::OptimizationContainer,
    ::Type{T},
    ff::Union{LowerBoundFeedforward, UpperBoundFeedforward},
    ::DeviceModel{U, V},
    devices::Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
) where {
    T <: Union{LowerBoundFeedForwardSlack, UpperBoundFeedForwardSlack},
    U <: PSY.Device,
    V <: AbstractDeviceFormulation,
}
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    for var in get_affected_values(ff)
        affected_variable = get_variable(container, var)
        device_name_set, set_time = JuMP.axes(affected_variable)
        devices_names = PSY.get_name.(devices)
        @assert issetequal(device_name_set, devices_names)
        IS.@assert_op set_time == time_steps

        var_type = get_entry_type(var)
        variable = add_variable_container!(
            container,
            T,
            U,
            devices_names,
            time_steps;
            meta = "$(var_type)",
        )

        for t in time_steps, name in device_name_set
            variable[name, t] = JuMP.@variable(
                jump_model,
                base_name = "$(T)_$(U)_{$(name), $(t)}",
                lower_bound = 0.0
            )
            add_to_objective_invariant_expression!(
                container,
                variable[name, t] * BALANCE_SLACK_COST,
            )
        end
    end
    return
end

_slack_for_feedforward(::Type{UpperBoundFeedforward}) = UpperBoundFeedForwardSlack
_slack_for_feedforward(::Type{LowerBoundFeedforward}) = LowerBoundFeedForwardSlack

function _add_feedforward_arguments!(
    container::OptimizationContainer,
    model::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::FF,
) where {
    T <: PSY.Device,
    U <: AbstractDeviceFormulation,
    FF <: Union{UpperBoundFeedforward, LowerBoundFeedforward},
}
    parameter_type = get_default_parameter_type(ff, T)
    add_parameters!(container, parameter_type, ff, model, devices)
    if get_slacks(ff)
        _add_feedforward_slack_variables!(
            container,
            _slack_for_feedforward(FF),
            ff,
            model,
            devices,
        )
    end
    return
end

function _add_feedforward_arguments!(
    container::OptimizationContainer,
    model::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::SemiContinuousFeedforward,
) where {T <: PSY.Device, U <: AbstractDeviceFormulation}
    parameter_type = get_default_parameter_type(ff, T)
    add_parameters!(container, parameter_type, ff, model, devices)
    # The commitment status arrives as a parameter rather than a variable, so it enters
    # the range expressions here; the formulation's own range constraints are suppressed
    # by `has_semicontinuous_feedforward`.
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        parameter_type(),
        devices,
        model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        parameter_type(),
        devices,
        model,
    )
    return
end
