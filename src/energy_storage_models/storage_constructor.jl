function _add_ancillary_services!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::ArgumentConstructStage,
    model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {T <: PSY.Storage, U <: StorageDispatchWithReserves, V <: PM.AbstractPowerModel}
    add_variables!(container, AncillaryServiceVariableDischarge, devices, U())
    add_variables!(container, AncillaryServiceVariableCharge, devices, U())
    time_steps = get_time_steps(container)
    for exp in [
        ReserveAssignmentBalanceUpDischarge,
        ReserveAssignmentBalanceUpCharge,
        ReserveAssignmentBalanceDownDischarge,
        ReserveAssignmentBalanceDownCharge,
        ReserveDeploymentBalanceUpDischarge,
        ReserveDeploymentBalanceUpCharge,
        ReserveDeploymentBalanceDownDischarge,
        ReserveDeploymentBalanceDownCharge,
    ]
        lazy_container_addition!(
            container,
            exp(),
            T,
            PSY.get_name.(devices),
            time_steps,
        )
    end
    for exp in [
        ReserveAssignmentBalanceUpDischarge,
        ReserveAssignmentBalanceDownDischarge,
        ReserveDeploymentBalanceUpDischarge,
        ReserveDeploymentBalanceDownDischarge,
    ]
        add_to_expression!(
            container,
            exp,
            AncillaryServiceVariableDischarge,
            devices,
            model,
        )
    end
    for exp in [
        ReserveAssignmentBalanceUpCharge,
        ReserveAssignmentBalanceDownCharge,
        ReserveDeploymentBalanceUpCharge,
        ReserveDeploymentBalanceDownCharge,
    ]
        add_to_expression!(container, exp, AncillaryServiceVariableCharge, devices, model)
    end

    services = Set()
    for d in devices
        union!(services, PSY.get_services(d))
    end
    for s in services
        lazy_container_addition!(
            container,
            TotalReserveOffering(),
            T,
            PSY.get_name.(devices),
            time_steps;
            meta = "$(typeof(s))_$(PSY.get_name(s))",
        )
    end

    for v in [AncillaryServiceVariableCharge, AncillaryServiceVariableDischarge]
        add_to_expression!(container, TotalReserveOffering, v, devices, model)
    end
    return
end

function _add_ancillary_services!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::ModelConstructStage,
    model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {T <: PSY.Storage, U <: StorageDispatchWithReserves, V <: PM.AbstractPowerModel}
    add_constraints!(
        container,
        ReserveCoverageConstraint,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReserveCoverageConstraintEndOfPeriod,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReserveDischargeConstraint,
        devices,
        model,
        network_model,
    )

    add_constraints!(container, ReserveChargeConstraint, devices, model, network_model)

    add_constraints!(
        container,
        StorageTotalReserveConstraint,
        devices,
        model,
        network_model,
    )

    return
end

function _active_power_variables_and_expressions(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    network_model::NetworkModel,
) where {T <: PSY.Storage, U <: StorageDispatchWithReserves}
    add_variables!(container, ActivePowerInVariable, devices, U())
    add_variables!(container, ActivePowerOutVariable, devices, U())
    add_variables!(container, EnergyVariable, devices, U())
    add_variables!(container, StorageEnergyOutput, devices, U())

    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, U())
    end

    if get_attribute(model, "energy_target")
        add_variables!(container, StorageEnergyShortageVariable, devices, U())
        add_variables!(container, StorageEnergySurplusVariable, devices, U())
    end

    if get_attribute(model, "cycling_limits")
        add_variables!(container, StorageChargeCyclingSlackVariable, devices, U())
        add_variables!(container, StorageDischargeCyclingSlackVariable, devices, U())
    end

    initial_conditions!(container, devices, U())

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerInVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerOutVariable,
        devices,
        model,
        network_model,
    )
    return
end

function _active_power_and_energy_bounds(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    network_model::NetworkModel,
) where {T <: PSY.Storage, U <: StorageDispatchWithReserves}
    if has_service_model(model)
        if get_attribute(model, "reservation")
            add_reserve_range_constraint_with_deployment!(
                container,
                OutputActivePowerVariableLimitsConstraint,
                ActivePowerOutVariable,
                devices,
                model,
                network_model,
            )
            add_reserve_range_constraint_with_deployment!(
                container,
                InputActivePowerVariableLimitsConstraint,
                ActivePowerInVariable,
                devices,
                model,
                network_model,
            )
        else
            add_reserve_range_constraint_with_deployment_no_reservation!(
                container,
                OutputActivePowerVariableLimitsConstraint,
                ActivePowerOutVariable,
                devices,
                model,
                network_model,
            )
            add_reserve_range_constraint_with_deployment_no_reservation!(
                container,
                InputActivePowerVariableLimitsConstraint,
                ActivePowerInVariable,
                devices,
                model,
                network_model,
            )
        end
    else
        add_constraints!(
            container,
            OutputActivePowerVariableLimitsConstraint,
            ActivePowerOutVariable,
            devices,
            model,
            network_model,
        )
        add_constraints!(
            container,
            InputActivePowerVariableLimitsConstraint,
            ActivePowerInVariable,
            devices,
            model,
            network_model,
        )
    end
    add_constraints!(
        container,
        StateofChargeLimitsConstraint,
        EnergyVariable,
        devices,
        model,
        network_model,
    )
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ArgumentConstructStage,
    model::DeviceModel{St, D},
    network_model::NetworkModel{S},
) where {St <: PSY.Storage, D <: StorageDispatchWithReserves, S <: PM.AbstractPowerModel}
    devices = get_available_components(model, sys)
    _active_power_variables_and_expressions(container, devices, model, network_model)
    add_variables!(container, ReactivePowerVariable, devices, D())

    if get_attribute(model, "regularization")
        add_variables!(container, StorageRegularizationVariableCharge, devices, D())
        add_variables!(container, StorageRegularizationVariableDischarge, devices, D())
    end

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    if has_service_model(model)
        _add_ancillary_services!(container, devices, stage, model, network_model)
    end
    process_market_bid_parameters!(container, devices, model, true, true)

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{St, D},
    network_model::NetworkModel{S},
) where {St <: PSY.Storage, D <: StorageDispatchWithReserves, S <: PM.AbstractPowerModel}
    devices = get_available_components(model, sys)
    _active_power_and_energy_bounds(container, devices, model, network_model)

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    # Energy Balance limits
    add_constraints!(
        container,
        EnergyBalanceConstraint,
        devices,
        model,
        network_model,
    )

    if has_service_model(model)
        _add_ancillary_services!(container, devices, stage, model, network_model)
    end

    if get_attribute(model, "energy_target")
        add_constraints!(
            container,
            StateofChargeTargetConstraint,
            devices,
            model,
            network_model,
        )
    end

    if get_attribute(model, "cycling_limits")
        add_constraints!(container, StorageCyclingCharge, devices, model, network_model)
        add_constraints!(
            container,
            StorageCyclingDischarge,
            devices,
            model,
            network_model,
        )
    end

    if get_attribute(model, "regularization")
        add_constraints!(container, StorageRegularizationConstraints, devices, D())
    end

    add_constraint_dual!(container, sys, model)
    add_event_constraints!(container, devices, model, network_model)
    objective_function!(container, devices, model, S)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ArgumentConstructStage,
    model::DeviceModel{St, D},
    network_model::NetworkModel{S},
) where {
    St <: PSY.Storage,
    D <: StorageDispatchWithReserves,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)
    _active_power_variables_and_expressions(container, devices, model, network_model)

    if get_attribute(model, "regularization")
        add_variables!(container, StorageRegularizationVariableCharge, devices, D())
        add_variables!(container, StorageRegularizationVariableDischarge, devices, D())
    end

    if has_service_model(model)
        _add_ancillary_services!(container, devices, stage, model, network_model)
    end

    process_market_bid_parameters!(container, devices, model, true, true)

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ModelConstructStage,
    model::DeviceModel{St, D},
    network_model::NetworkModel{S},
) where {
    St <: PSY.Storage,
    D <: StorageDispatchWithReserves,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)
    _active_power_and_energy_bounds(container, devices, model, network_model)

    # Energy Balanace limits
    add_constraints!(
        container,
        EnergyBalanceConstraint,
        devices,
        model,
        network_model,
    )

    if has_service_model(model)
        _add_ancillary_services!(container, devices, stage, model, network_model)
    end

    if get_attribute(model, "energy_target")
        add_constraints!(
            container,
            StateofChargeTargetConstraint,
            devices,
            model,
            network_model,
        )
    end

    if get_attribute(model, "cycling_limits")
        add_constraints!(container, StorageCyclingCharge, devices, model, network_model)
        add_constraints!(
            container,
            StorageCyclingDischarge,
            devices,
            model,
            network_model,
        )
    end

    if has_service_model(model)
        if get_attribute(model, "complete_coverage")
            add_constraints!(
                container,
                ReserveCompleteCoverageConstraint,
                devices,
                model,
                network_model,
            )
            add_constraints!(
                container,
                ReserveCompleteCoverageConstraintEndOfPeriod,
                devices,
                model,
                network_model,
            )
        end
    end

    if get_attribute(model, "regularization")
        add_constraints!(
            container,
            StorageRegularizationConstraintCharge,
            devices,
            model,
            network_model,
        )
        add_constraints!(
            container,
            StorageRegularizationConstraintDischarge,
            devices,
            model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, model, devices)

    # TODO issue with time varying MBC.
    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end
