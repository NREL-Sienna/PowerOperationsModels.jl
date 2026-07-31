"""
Formulation type to enable thermal compact commitment without intertemporal (ramp, min on/off time) constraints
"""
struct ThermalBasicCompactUnitCommitment <: AbstractCompactUnitCommitment end

#! format: off
requires_initialization(::ThermalBasicCompactUnitCommitment) = false
#! format: on

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, ThermalBasicCompactUnitCommitment},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(
        container,
        PowerAboveMinimumVariable,
        devices,
        ThermalBasicCompactUnitCommitment,
    )
    add_variables!(
        container,
        ReactivePowerVariable,
        devices,
        ThermalBasicCompactUnitCommitment,
    )
    add_variables!(container, OnVariable, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, StartVariable, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, StopVariable, devices, ThermalBasicCompactUnitCommitment)

    add_variables!(container, PowerOutput, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, TimeDurationOn, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, TimeDurationOff, devices, ThermalBasicCompactUnitCommitment)

    initial_conditions!(container, devices, ThermalBasicCompactUnitCommitment())

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

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
        OnVariable,
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
            ThermalBasicCompactUnitCommitment,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalBasicCompactUnitCommitment,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalBasicCompactUnitCommitment},
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
    add_constraints!(container, CommitmentConstraint, devices, device_model, network_model)
    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_constraints!(
            container,
            ActivePowerVariableTimeSeriesLimitsConstraint,
            ActivePowerRangeExpressionUB,
            devices,
            device_model,
            network_model,
        )
    end

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
    device_model::DeviceModel{T, ThermalBasicCompactUnitCommitment},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)

    add_variables!(
        container,
        PowerAboveMinimumVariable,
        devices,
        ThermalBasicCompactUnitCommitment,
    )
    add_variables!(container, OnVariable, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, StartVariable, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, StopVariable, devices, ThermalBasicCompactUnitCommitment)

    add_variables!(container, PowerOutput, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, TimeDurationOn, devices, ThermalBasicCompactUnitCommitment)
    add_variables!(container, TimeDurationOff, devices, ThermalBasicCompactUnitCommitment)
    initial_conditions!(container, devices, ThermalBasicCompactUnitCommitment())

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

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
        OnVariable,
        devices,
        device_model,
        network_model,
    )

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
            ThermalBasicCompactUnitCommitment,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalBasicCompactUnitCommitment,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, ThermalBasicCompactUnitCommitment},
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

    add_constraints!(container, CommitmentConstraint, devices, device_model, network_model)
    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_constraints!(
            container,
            ActivePowerVariableTimeSeriesLimitsConstraint,
            ActivePowerRangeExpressionUB,
            devices,
            device_model,
            network_model,
        )
    end

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
