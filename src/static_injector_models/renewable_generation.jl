#! format: off
get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.RenewableGen}, ::Type{<:AbstractRenewableFormulation}) = 1.0
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.RenewableGen}, ::Type{<:PSY.Reserve{PSY.ReserveUp}}) = ActivePowerRangeExpressionUB
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.RenewableGen}, ::Type{<:PSY.Reserve{PSY.ReserveDown}}) = ActivePowerRangeExpressionLB
# OfflineReserve (non-spin) is upward-only, so it reduces upward headroom like a ReserveUp product.
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.RenewableGen}, ::Type{<:PSY.OfflineReserve}) = ActivePowerRangeExpressionUB
########################### Parameter related set functions ################################
get_parameter_multiplier(::Type{<:VariableValueParameter}, d::PSY.RenewableGen, ::Type{<:AbstractRenewableFormulation}) = 1.0
########################### ActivePowerVariable, RenewableGen #################################

get_variable_binary(::Type{ActivePowerVariable}, ::Type{<:PSY.RenewableGen}, ::Type{<:AbstractRenewableFormulation}) = false
get_min_max_limits(d::PSY.RenewableGen, ::Type{ActivePowerVariableLimitsConstraint}, ::Type{<:AbstractRenewableFormulation}) = (min = 0.0, max = PSY.get_max_active_power(d, PSY.SU))
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.RenewableGen, ::Type{<:AbstractRenewableFormulation}) = 0.0
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.RenewableGen, ::Type{<:AbstractRenewableFormulation}) = PSY.get_max_active_power(d, PSY.SU)

########################### ReactivePowerVariable, RenewableGen #################################

get_variable_binary(::Type{ReactivePowerVariable}, ::Type{<:PSY.RenewableGen}, ::Type{<:AbstractRenewableFormulation}) = false

get_multiplier_value(::Type{<:TimeSeriesParameter}, d::PSY.RenewableGen, ::Type{FixedOutput}) = PSY.get_max_active_power(d, PSY.SU)
get_multiplier_value(::Type{<:TimeSeriesParameter}, d::PSY.RenewableGen, ::Type{<:AbstractRenewableFormulation}) = PSY.get_max_active_power(d, PSY.SU)

# To avoid ambiguity with default_interface_methods.jl:
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.RenewableGen, ::Type{FixedOutput}) = 1.0
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.RenewableGen, ::Type{<:AbstractRenewableFormulation}) = 1.0

########################Objective Function##################################################
objective_function_multiplier(::Type{ActivePowerVariable}, ::Type{<:AbstractRenewableDispatchFormulation})=OBJECTIVE_FUNCTION_NEGATIVE
#! format: on

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, <:AbstractRenewableFormulation},
) where {T <: PSY.RenewableGen} = DeviceModel(T, RenewableFullDispatch)

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, FixedOutput},
) where {T <: PSY.RenewableGen} = DeviceModel(T, FixedOutput)

function get_min_max_limits(
    device::PSY.RenewableGen,
    ::Type{ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractRenewableFormulation},
)
    return PSY.get_reactive_power_limits(device, PSY.SU)
end

function get_default_time_series_names(
    ::Type{<:PSY.RenewableGen},
    ::Type{<:Union{FixedOutput, AbstractRenewableFormulation}},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        ActivePowerTimeSeriesParameter => "max_active_power",
        ReactivePowerTimeSeriesParameter => "max_active_power",
    )
end

function get_default_attributes(
    ::Type{<:PSY.RenewableGen},
    ::Type{<:Union{FixedOutput, AbstractRenewableFormulation}},
)
    return Dict{String, Any}()
end

####################################### Reactive Power constraint_infos #########################

function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ReactivePowerVariableLimitsConstraint},
    U::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.RenewableGen, W <: AbstractDeviceFormulation, X <: AbstractNetworkModel}
    add_range_constraints!(container, T, U, devices, model, X)
    return
end

"""
Reactive Power Constraints on Renewable Gen Constant power_factor
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{<:ReactivePowerVariableLimitsConstraint},
    ::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.RenewableGen,
    W <: RenewableConstantPowerFactor,
    X <: AbstractNetworkModel,
}
    names = PSY.get_name.(devices)
    time_steps = get_time_steps(container)
    p_var = get_variable(container, ActivePowerVariable, V)
    q_var = get_variable(container, ReactivePowerVariable, V)
    jump_model = get_jump_model(container)
    constraint =
        add_constraints_container!(container, EqualityConstraint, V, names, time_steps)
    for t in time_steps, d in devices
        name = PSY.get_name(d)
        pf = sin(acos(PSY.get_power_factor(d)))
        constraint[name, t] =
            JuMP.@constraint(jump_model, q_var[name, t] == p_var[name, t] * pf)
    end
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActivePowerVariableLimitsConstraint},
    U::Type{<:Union{VariableType, ActivePowerRangeExpressionUB}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.RenewableGen,
    W <: AbstractRenewableDispatchFormulation,
    X <: AbstractNetworkModel,
}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ActivePowerVariableLimitsConstraint},
    U::Type{ActivePowerRangeExpressionLB},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.RenewableGen,
    W <: AbstractRenewableDispatchFormulation,
    X <: AbstractNetworkModel,
}
    add_range_constraints!(
        container,
        T,
        U,
        devices,
        model,
        X,
    )
    return
end

##################################### renewable generation cost ############################
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.RenewableGen, U <: AbstractRenewableDispatchFormulation}
    add_variable_cost!(container, ActivePowerVariable, devices, U)
    add_curtailment_cost!(container, ActivePowerVariable, devices, U)
    return
end
