"""
Formulation type to enable thermal compact dispatch
"""
struct ThermalCompactDispatch <: AbstractThermalDispatchFormulation end

#! format: off
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionUB}, d::PSY.ThermalGen, ::Type{ThermalCompactDispatch}) = PSY.get_active_power_limits(d, PSY.SU).max - PSY.get_active_power_limits(d, PSY.SU).min
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionLB}, d::PSY.ThermalGen, ::Type{ThermalCompactDispatch}) = 0.0
initial_condition_variable(::DeviceAboveMinPower, d::PSY.ThermalGen, ::ThermalCompactDispatch) = PowerAboveMinimumVariable()
uses_compact_power(::PSY.ThermalGen, ::ThermalCompactDispatch)=true
#! format: on

"""
Min and max active power limits of generators for thermal dispatch compact formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalCompactDispatch},
)
    return (
        min = 0.0,
        max = PSY.get_active_power_limits(device, PSY.SU).max -
              PSY.get_active_power_limits(device, PSY.SU).min,
    )
end

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::ThermalCompactDispatch,
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DeviceAboveMinPower())
    return
end
_get_initial_condition_type(
    ::Type{RampConstraint},
    ::Type{<:PSY.ThermalGen},
    ::Type{ThermalCompactDispatch},
) = DeviceAboveMinPower

# compact dispatch ramping limits: linear with PowerAboveMinimumVariable.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, ThermalCompactDispatch},
    ::NetworkModel{V},
) where {U <: PSY.ThermalGen, V <: AbstractNetworkModel}
    add_linear_ramp_constraints!(container, T, PowerAboveMinimumVariable, devices, model, V)
    return
end

# compact dispatch
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen, U <: ThermalCompactDispatch}
    add_variable_cost!(container, PowerAboveMinimumVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
    end
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, ThermalCompactDispatch},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(container, PowerAboveMinimumVariable, devices, ThermalCompactDispatch)
    add_variables!(container, ReactivePowerVariable, devices, ThermalCompactDispatch)

    add_variables!(container, PowerOutput, devices, ThermalCompactDispatch)

    add_parameters!(container, OnStatusParameter, devices, device_model)

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_feedforward_arguments!(container, device_model, devices)

    initial_conditions!(container, devices, ThermalCompactDispatch())

    add_to_expression!(
        container,
        ActivePowerBalance,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        OnStatusParameter,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        PowerAboveMinimumVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalCompactDispatch,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalCompactDispatch,
        )
    end
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalCompactDispatch},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        device_model,
        network_model,
    )

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, RampConstraint, devices, device_model, network_model)

    add_feedforward_constraints!(container, device_model, devices)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, ThermalCompactDispatch},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(container, PowerAboveMinimumVariable, devices, ThermalCompactDispatch)

    add_variables!(container, PowerOutput, devices, ThermalCompactDispatch)

    add_parameters!(container, OnStatusParameter, devices, device_model)

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_feedforward_arguments!(container, device_model, devices)

    add_to_expression!(
        container,
        ActivePowerBalance,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        OnStatusParameter,
        devices,
        device_model,
        network_model,
    )

    initial_conditions!(container, devices, ThermalCompactDispatch())

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        PowerAboveMinimumVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalCompactDispatch,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalCompactDispatch,
        )
    end
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalCompactDispatch},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        device_model,
        network_model,
    )

    add_constraints!(container, RampConstraint, devices, device_model, network_model)

    add_feedforward_constraints!(container, device_model, devices)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )

    add_event_constraints!(container, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    return
end
