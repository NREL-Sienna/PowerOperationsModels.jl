#################################################################################
# Two-stage construct_device! for HybridSystem with HybridDispatchWithReserves.
#
# Argument stage: variables, parameters, expression containers, expression
#                 accumulation, feedforward arguments.
# Model stage:    constraints, feedforward constraints, objective function,
#                 dual recording.
#
# Mirrors energy_storage_models/storage_constructor.jl in structure. We provide
# both AbstractNetworkModel (with reactive power) and AbstractActivePowerModel
# (without) variants.
#################################################################################

function _filter_hybrids(devices)
    devices_vec = collect(devices)
    return (
        all = devices_vec,
        with_thermal = [d for d in devices_vec if PSY.get_thermal_unit(d) !== nothing],
        with_renewable = [d for d in devices_vec if PSY.get_renewable_unit(d) !== nothing],
        with_storage = [d for d in devices_vec if PSY.get_storage(d) !== nothing],
        with_load = [d for d in devices_vec if PSY.get_electric_load(d) !== nothing],
    )
end

function _add_hybrid_reserve_arguments!(
    container::OptimizationContainer,
    devices,
    hybrids_with_storage,
    hybrids_with_thermal,
    hybrids_with_renewable,
    model::DeviceModel{T, D},
    network_model::NetworkModel{S},
) where {T <: PSY.HybridSystem, D <: HybridDispatchWithReserves, S <: AbstractNetworkModel}
    time_steps = get_time_steps(container)

    # Hybrid PCC reserve variables
    add_variables!(container, HybridPCCReserveVariable{DischargeSide}, devices, D)
    add_variables!(container, HybridPCCReserveVariable{ChargeSide}, devices, D)

    # Allocate hybrid-boundary aggregation expression containers
    for E in (
        HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
    )
        lazy_container_addition!(container, E, T, PSY.get_name.(devices), time_steps)
    end

    # Accumulate Out/In reserve variables into Total* and Served* expressions
    for E in (
        HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
    )
        add_to_expression!(
            container,
            E,
            HybridPCCReserveVariable{DischargeSide},
            devices,
            model,
            network_model,
        )
    end
    for E in (
        HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
        HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
    )
        add_to_expression!(
            container,
            E,
            HybridPCCReserveVariable{ChargeSide},
            devices,
            model,
            network_model,
        )
    end

    # Per-subcomponent reserve variables
    if !isempty(hybrids_with_thermal)
        add_variables!(container, HybridThermalReserveVariable, hybrids_with_thermal, D)
    end
    if !isempty(hybrids_with_renewable)
        add_variables!(container, HybridRenewableReserveVariable, hybrids_with_renewable, D)
    end
    if !isempty(hybrids_with_storage)
        add_variables!(
            container,
            HybridStorageSubcomponentReserveVariable{ChargeSide},
            hybrids_with_storage,
            D,
        )
        add_variables!(
            container,
            HybridStorageSubcomponentReserveVariable{DischargeSide},
            hybrids_with_storage,
            D,
        )

        # Storage-side reserve expression containers, keyed by HybridSystem
        for E in (
            StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide},
            StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide},
            StorageReserveBalanceExpression{
                PSY.ReserveDown,
                UnscaledReserve,
                DischargeSide,
            },
            StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide},
            StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
            StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
            StorageReserveBalanceExpression{
                PSY.ReserveDown,
                DeployedReserve,
                DischargeSide,
            },
            StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
        )
            lazy_container_addition!(
                container,
                E,
                T,
                PSY.get_name.(hybrids_with_storage),
                time_steps,
            )
        end

        # Wire HybridStorageSubcomponentReserveVariable{DischargeSide} into Discharge expressions
        for E in (
            StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide},
            StorageReserveBalanceExpression{
                PSY.ReserveDown,
                UnscaledReserve,
                DischargeSide,
            },
            StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
            StorageReserveBalanceExpression{
                PSY.ReserveDown,
                DeployedReserve,
                DischargeSide,
            },
        )
            add_to_expression!(
                container,
                E,
                HybridStorageSubcomponentReserveVariable{DischargeSide},
                hybrids_with_storage,
                model,
            )
        end
        for E in (
            StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide},
            StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide},
            StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
            StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
        )
            add_to_expression!(
                container,
                E,
                HybridStorageSubcomponentReserveVariable{ChargeSide},
                hybrids_with_storage,
                model,
            )
        end
    end

    # TotalReserveOffering aggregation per service, keyed by HybridSystem. Created for
    # EVERY hybrid that participates in a reserve service, storage-less hybrids included:
    # get_expression_type_for_reserve routes all hybrids' ActivePowerReserveVariable into
    # TotalReserveOffering, so the container must exist regardless of storage.
    services = Set{PSY.Service}()
    for d in devices
        union!(services, PSY.get_services(d))
    end
    for s in services
        lazy_container_addition!(container, TotalReserveOffering, T,
            PSY.get_name.(devices), time_steps;
            meta = _service_container_meta(s))
    end
    # Only storage hybrids have subcomponent reserve variables to aggregate into the
    # offering; storage-less hybrids feed it via the PCC reserve path instead.
    if !isempty(hybrids_with_storage)
        for v in (
            HybridStorageSubcomponentReserveVariable{ChargeSide},
            HybridStorageSubcomponentReserveVariable{DischargeSide},
        )
            add_to_expression!(
                container,
                TotalReserveOffering,
                v,
                hybrids_with_storage,
                model,
            )
        end
    end
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{T, D},
    network_model::NetworkModel{S},
) where {T <: PSY.HybridSystem, D <: HybridDispatchWithReserves, S <: AbstractNetworkModel}
    devices = get_available_components(model, sys)
    grouped = _filter_hybrids(devices)

    # PCC variables
    add_variables!(container, ActivePowerOutVariable, devices, D)
    add_variables!(container, ActivePowerInVariable, devices, D)
    _maybe_add_reactive_power_variable!(
        container,
        ReactivePowerVariable,
        devices,
        D,
        network_model,
    )
    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, D)
    end

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
    _maybe_add_reactive_power_balance!(
        container,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    # Subcomponent variables
    if !isempty(grouped.with_thermal)
        add_variables!(container, HybridThermalActivePower, grouped.with_thermal, D)
        add_variables!(container, OnVariable, grouped.with_thermal, D)
    end
    if !isempty(grouped.with_renewable)
        add_variables!(container, HybridRenewableActivePower, grouped.with_renewable, D)
        add_parameters!(
            container,
            HybridRenewableActivePowerTimeSeriesParameter,
            grouped.with_renewable,
            model,
        )
    end
    if !isempty(grouped.with_storage)
        add_variables!(
            container,
            HybridStorageSubcomponentPower{ChargeSide},
            grouped.with_storage,
            D,
        )
        add_variables!(
            container,
            HybridStorageSubcomponentPower{DischargeSide},
            grouped.with_storage,
            D,
        )
        add_variables!(container, EnergyVariable, grouped.with_storage, D)
        if get_attribute(model, "storage_reservation")
            add_variables!(container, HybridStorageReservation, grouped.with_storage, D)
        end
        if get_attribute(model, "regularization")
            add_variables!(
                container,
                RegularizationVariable{ChargeSide},
                grouped.with_storage,
                D,
            )
            add_variables!(
                container,
                RegularizationVariable{DischargeSide},
                grouped.with_storage,
                D,
            )
        end
        if get_attribute(model, "energy_target")
            add_variables!(container, HybridEnergySurplusVariable, grouped.with_storage, D)
            add_variables!(container, HybridEnergyShortageVariable, grouped.with_storage, D)
        end
        initial_conditions!(container, devices, D())
    end
    if !isempty(grouped.with_load)
        add_parameters!(
            container,
            HybridElectricLoadTimeSeriesParameter,
            grouped.with_load,
            model,
        )
    end

    if has_service_model(model)
        _add_hybrid_reserve_arguments!(container, devices,
            grouped.with_storage, grouped.with_thermal, grouped.with_renewable,
            model, network_model)
    end

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{T, D},
    network_model::NetworkModel{S},
) where {T <: PSY.HybridSystem, D <: HybridDispatchWithReserves, S <: AbstractNetworkModel}
    devices = get_available_components(model, sys)
    grouped = _filter_hybrids(devices)

    # PCC reactive-power limits (active-power limits handled via the asset balance + status constraints)
    _maybe_add_reactive_power_constraints!(
        container,
        devices,
        model,
        network_model,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
    )

    # PCC ↔ subcomponent plumbing. With reservation, mutual-exclusion via ReservationVariable;
    # without, simple range constraints on the PCC variables (no binary).
    if get_attribute(model, "reservation")
        add_constraints!(
            container,
            HybridStatusOnConstraint{DischargeSide},
            devices,
            model,
            network_model,
        )
        add_constraints!(
            container,
            HybridStatusOnConstraint{ChargeSide},
            devices,
            model,
            network_model,
        )
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
        HybridEnergyAssetBalanceConstraint,
        devices,
        model,
        network_model,
    )

    # Thermal subcomponent
    if !isempty(grouped.with_thermal)
        if has_service_model(model)
            add_constraints!(
                container,
                HybridThermalReserveLimitConstraint,
                grouped.with_thermal,
                model,
                network_model,
            )
        else
            add_constraints!(
                container,
                HybridThermalOnVariableConstraint{UpperBound},
                grouped.with_thermal,
                model,
                network_model,
            )
            add_constraints!(
                container,
                HybridThermalOnVariableConstraint{LowerBound},
                grouped.with_thermal,
                model,
                network_model,
            )
        end
    end

    # Renewable subcomponent
    if !isempty(grouped.with_renewable)
        add_constraints!(
            container,
            HybridRenewableActivePowerLimitConstraint,
            grouped.with_renewable,
            model,
            network_model,
        )
        if has_service_model(model)
            add_constraints!(
                container,
                HybridRenewableReserveLimitConstraint,
                grouped.with_renewable,
                model,
                network_model,
            )
        end
    end

    # Storage subcomponent
    if !isempty(grouped.with_storage)
        add_constraints!(
            container,
            HybridStorageBalanceConstraint,
            grouped.with_storage,
            model,
            network_model,
        )
        if get_attribute(model, "energy_target")
            add_constraints!(
                container,
                HybridEnergyTargetConstraint,
                grouped.with_storage,
                model,
                network_model,
            )
        end
        if has_service_model(model)
            add_constraints!(
                container,
                ReserveCoverageConstraint,
                grouped.with_storage,
                model,
                network_model,
            )
            add_constraints!(
                container,
                ReserveCoverageConstraintEndOfPeriod,
                grouped.with_storage,
                model,
                network_model,
            )
            add_constraints!(
                container,
                HybridStorageReservePowerLimitConstraint{ChargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
            add_constraints!(
                container,
                HybridStorageReservePowerLimitConstraint{DischargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
        elseif get_attribute(model, "storage_reservation")
            # No reserves attached: enforce mutual exclusion via HybridStorageReservation.
            # When `storage_reservation` is false, charge/discharge are bounded
            # independently by their variable upper bounds — no extra constraint needed.
            add_constraints!(
                container,
                HybridStorageStatusOnConstraint{ChargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
            add_constraints!(
                container,
                HybridStorageStatusOnConstraint{DischargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
        end
        if get_attribute(model, "regularization")
            add_constraints!(
                container,
                RegularizationConstraint{ChargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
            add_constraints!(
                container,
                RegularizationConstraint{DischargeSide},
                grouped.with_storage,
                model,
                network_model,
            )
        end
    end

    # Hybrid-boundary reserve coupling
    if has_service_model(model)
        add_constraints!(
            container,
            HybridReserveAssignmentConstraint,
            devices,
            model,
            network_model,
        )
        add_constraints!(
            container,
            HybridReserveBalanceConstraint,
            devices,
            model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, model, devices)
    add_event_constraints!(container, devices, model, network_model)
    objective_function!(container, devices, model, S)
    add_constraint_dual!(container, sys, model)
    return
end
