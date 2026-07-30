#! format: off
requires_initialization(::ThermalStandardDispatch) = true
#! format: on

"""
This function creates the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, ThermalStandardDispatch},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, ThermalStandardDispatch)
    add_variables!(container, ReactivePowerVariable, devices, ThermalStandardDispatch)

    initial_conditions!(container, devices, ThermalStandardDispatch())

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalStandardDispatch,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalStandardDispatch,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

"""
This function creates the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalStandardDispatch},
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

"""
This function creates the arguments for the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, ThermalStandardDispatch},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, ThermalStandardDispatch)

    initial_conditions!(container, devices, ThermalStandardDispatch())

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalStandardDispatch,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalStandardDispatch,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

"""
This function creates the constraints for the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalStandardDispatch},
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
