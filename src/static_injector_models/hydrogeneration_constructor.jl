####################################################################################################
##################################### FixedOutput ##################################################
####################################################################################################

"""
Construct model for [`PowerSystems.HydroGen``](@extref) with [`PowerSimulations.FixedOutput`](@extref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, FixedOutput},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroGen, S <: PM.AbstractPowerModel}
    devices = get_available_components(model, sys)

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    add_parameters!(container, ReactivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    # Expression
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerTimeSeriesParameter,
        devices,
        model,
        network_model,
    )
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{H, FixedOutput},
    ::NetworkModel{S},
) where {H <: PSY.HydroGen, S <: PM.AbstractPowerModel}
    # FixedOutput doesn't add any constraints to the model. This function covers
    # AbstractPowerModel and AbstractActivePowerModel
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, FixedOutput},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroGen, S <: PM.AbstractActivePowerModel}
    devices = get_available_components(model, sys)

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    # Expression
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        network_model,
    )
    add_event_arguments!(container, devices, model, network_model)
    return
end

####################################################################################################
############################### HydroDispatchRunOfRiver ############################################
####################################################################################################

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroDispatchRunOfRiver`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: AbstractHydroDispatchFormulation,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    add_expressions!(container, ProductionCostExpression, devices, model)

    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: AbstractHydroDispatchFormulation,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroDispatchRunOfRiver`](@ref) Formulation
with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: AbstractHydroDispatchFormulation,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: AbstractHydroDispatchFormulation,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

####################################################################################################
############################ HydroDispatchRunOfRiverBudget #########################################
####################################################################################################

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroDispatchRunOfRiverBudget`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroDispatchRunOfRiverBudget,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    add_parameters!(container, EnergyBudgetTimeSeriesParameter, devices, model)
    if get_use_slacks(model)
        add_variables!(
            container,
            HydroEnergyShortageVariable,
            devices,
            D(),
        )
    end
    process_market_bid_parameters!(container, devices, model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroDispatchRunOfRiverBudget,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(container, EnergyBudgetConstraint, devices, model, network_model)

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroDispatchRunOfRiverBudget`](@ref) Formulation
with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroDispatchRunOfRiverBudget,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    add_parameters!(container, EnergyBudgetTimeSeriesParameter, devices, model)
    if get_use_slacks(model)
        add_variables!(
            container,
            HydroEnergyShortageVariable,
            devices,
            D(),
        )
    end
    process_market_bid_parameters!(container, devices, model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroDispatchRunOfRiverBudget,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )
    add_constraints!(container, EnergyBudgetConstraint, devices, model, network_model)

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

################################################################################################
############################ HydroCommitmentRunOfRiver #########################################
################################################################################################

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroCommitmentRunOfRiver`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroGen, D <: HydroCommitmentRunOfRiver, S <: PM.AbstractPowerModel}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, OnVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

"""
Construct model for [`PowerSystems.HydroGen`](@extref) with [`HydroCommitmentRunOfRiver`](@ref) Formulation
with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroCommitmentRunOfRiver,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, OnVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    process_market_bid_parameters!(container, devices, model)

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroGen,
    D <: HydroCommitmentRunOfRiver,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    # this is erroring when there's a market bid cost.
    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

################################################################################################
############################ HydroEnergyModelReservoir #########################################
################################################################################################

"""
Construct model for [`PowerSystems.HydroReservoir`](@extref) with [`HydroEnergyModelReservoir`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroReservoir,
    D <: HydroEnergyModelReservoir,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_reservoirs(sys)
    T = HydroEnergyModelReservoir
    add_variables!(
        container,
        EnergyVariable,
        devices,
        T(),
    )
    add_variables!(
        container,
        WaterSpillageVariable,
        devices,
        T(),
    )
    add_variables!(
        container,
        HydroEnergyShortageVariable,
        devices,
        T(),
    )
    add_variables!(
        container,
        HydroEnergySurplusVariable,
        devices,
        T(),
    )

    add_parameters!(container, InflowTimeSeriesParameter, devices, model)
    if get_attribute(model, "energy_target")
        add_parameters!(container, EnergyTargetTimeSeriesParameter, devices, model)
    end
    if get_attribute(model, "hydro_budget")
        add_parameters!(container, EnergyBudgetTimeSeriesParameter, devices, model)
    end

    if get_use_slacks(model)
        add_variables!(
            container,
            HydroBalanceSurplusVariable,
            devices,
            T(),
        )
        add_variables!(
            container,
            HydroBalanceShortageVariable,
            devices,
            T(),
        )
    end

    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroReservoir,
    D <: HydroEnergyModelReservoir,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_reservoirs(sys)

    add_initial_condition!(
        container,
        devices,
        HydroEnergyModelReservoir(),
        InitialEnergyLevel(),
    )
    # Update expressions that depend on turbine variables
    add_expressions!(
        container,
        TotalHydroPowerReservoirIncoming,
        devices,
        model,
    )

    add_expressions!(
        container,
        TotalHydroPowerReservoirOutgoing,
        devices,
        model,
    )

    add_expressions!(
        container,
        TotalSpillagePowerReservoirIncoming,
        devices,
        model,
    )

    # Energy Balance Constraint
    add_constraints!(
        container,
        sys,
        EnergyBalanceConstraint,
        devices,
        model,
        network_model,
    )
    if get_attribute(model, "energy_target")
        add_constraints!(
            container,
            EnergyTargetConstraint,
            devices,
            model,
            network_model,
        )
    end

    if get_attribute(model, "hydro_budget")
        add_constraints!(
            container,
            sys,
            EnergyBudgetConstraint,
            devices,
            model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_constraint_dual!(container, sys, model)
    return
end

########################################################################################
########################### HydroTurbineEnergyDispatch #################################
########################################################################################

"""
Construct model for [`PowerSystems.HydroTurbine`](@extref) with [`HydroTurbineEnergyDispatch`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyDispatch,
    S <: PM.AbstractPowerModel,
}
    # why is there no add_parameters here?
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    process_market_bid_parameters!(container, devices, model)

    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyDispatch,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

"""
Construct model for [`PowerSystems.HydroTurbine`](@extref) with [`HydroTurbineEnergyDispatch`](@ref) Formulation with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyDispatch,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    process_market_bid_parameters!(container, devices, model)

    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyDispatch,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

##########################################################################################
############################ HydroTurbineEnergyCommitment ################################
##########################################################################################

"""
Construct model for [`PowerSystems.HydroTurbine`](@extref) with [`HydroTurbineEnergyCommitment`](@ref) Formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyCommitment,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, OnVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    process_market_bid_parameters!(container, devices, model)

    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyCommitment,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

"""
Construct model for [`PowerSystems.HydroTurbine`](@extref) with [`HydroTurbineEnergyCommitment`](@ref) Formulation with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyCommitment,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_variables!(container, OnVariable, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_expressions!(container, ProductionCostExpression, devices, model)
    process_market_bid_parameters!(container, devices, model)

    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroTurbineEnergyCommitment,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

################################################################################################
########################### New Hydro Block Optimization Model #################################
################################################################################################
# HydroReservoir
"""
Construct model for [`PowerSystems.HydroReservoir`](@extref) with [`HydroWaterFactorModel`](@ref) Formulation
with only Active Power
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, HydroWaterFactorModel},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroReservoir, S <: PM.AbstractPowerModel}
    devices = get_available_reservoirs(sys)

    add_variables!(
        container,
        WaterSpillageVariable,
        devices,
        HydroWaterFactorModel(),
    )
    add_variables!(
        container,
        HydroReservoirVolumeVariable,
        devices,
        HydroWaterFactorModel(),
    )

    add_parameters!(container, InflowTimeSeriesParameter, devices, model)
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, HydroWaterFactorModel},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroReservoir, S <: PM.AbstractPowerModel}
    devices = get_available_reservoirs(sys)

    add_initial_condition!(
        container,
        devices,
        HydroWaterFactorModel(),
        InitialReservoirVolume(),
    )

    add_constraints!(
        container,
        sys,
        ReservoirInventoryConstraint,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReservoirLevelTargetConstraint,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)
    return
end

"""
Construct model for [`PowerSystems.HydroTurbine`](@extref) with [`HydroWaterFactorModel`](@ref) Formulation
with only Active Power.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroWaterFactorModel,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_variables!(
        container,
        HydroTurbineFlowRateVariable,
        devices,
        HydroWaterFactorModel(),
    )

    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, HydroEnergyOutput, devices, D())
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    process_market_bid_parameters!(container, devices, model)

    add_expressions!(container, ProductionCostExpression, devices, model)
    if has_service_model(model)
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: HydroWaterFactorModel,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    if has_service_model(model)
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        sys,
        HydroPowerConstraint,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

################################################################################################
############################## New Hydro Bilinear Model ########################################
################################################################################################

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, R},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroReservoir, R <: HydroWaterModelReservoir, S <: PM.AbstractPowerModel}
    devices = get_available_reservoirs(sys)

    add_variables!(
        container,
        HydroReservoirHeadVariable,
        devices,
        R(),
    )
    add_variables!(
        container,
        HydroReservoirVolumeVariable,
        devices,
        R(),
    )
    add_variables!(
        container,
        WaterSpillageVariable,
        devices,
        R(),
    )
    add_variables!(
        container,
        HydroWaterShortageVariable,
        devices,
        R(),
    )
    add_variables!(
        container,
        HydroWaterSurplusVariable,
        devices,
        R(),
    )

    add_parameters!(container, InflowTimeSeriesParameter, devices, model)
    add_parameters!(container, OutflowTimeSeriesParameter, devices, model)
    if get_attribute(model, "hydro_target")
        add_parameters!(container, WaterTargetTimeSeriesParameter, devices, model)
    end
    if get_attribute(model, "hydro_budget")
        add_parameters!(container, WaterBudgetTimeSeriesParameter, devices, model)
    end
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, R},
    network_model::NetworkModel{S},
) where {H <: PSY.HydroReservoir, R <: HydroWaterModelReservoir, S <: PM.AbstractPowerModel}
    devices = get_available_reservoirs(sys)

    add_expressions!(
        container,
        TotalHydroFlowRateReservoirOutgoing,
        devices,
        model,
    )

    add_expressions!(
        container,
        TotalHydroFlowRateReservoirIncoming,
        devices,
        model,
    )

    add_expressions!(
        container,
        TotalSpillageFlowRateReservoirIncoming,
        devices,
        model,
    )

    add_initial_condition!(
        container,
        devices,
        R(),
        InitialReservoirVolume(),
    )

    add_constraints!(
        container,
        ReservoirInventoryConstraint,
        HydroReservoirVolumeVariable,
        devices,
        model,
        network_model,
    )

    """
    if !has_waterbudget_feedforward(model)
        add_constraints!(
            container,
            ReservoirLevelTargetConstraint,
            devices,
            model,
            network_model,
        )
    end
    """

    add_constraints!(
        container,
        ReservoirLevelLimitConstraint,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        ReservoirHeadToVolumeConstraint,
        devices,
        model,
        network_model,
    )

    if get_attribute(model, "hydro_target")
        add_constraints!(
            container,
            WaterTargetConstraint,
            devices,
            model,
            network_model,
        )
    end

    if get_attribute(model, "hydro_budget")
        add_constraints!(
            container,
            sys,
            WaterBudgetConstraint,
            devices,
            model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, model, devices)
    objective_function!(container, devices, model, S)

    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: Union{HydroTurbineBilinearDispatch, HydroTurbineWaterLinearDispatch},
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)
    reservoirs = get_available_reservoirs(sys)

    add_variables!(
        container,
        HydroTurbineFlowRateVariable,
        devices,
        reservoirs,
        D(),
    )

    add_variables!(container, ActivePowerVariable, devices, D())

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    process_market_bid_parameters!(container, devices, model)
    if has_service_model(model)
        error("$D does not support service models yet")
        add_expressions!(container, HydroServedReserveUpExpression, devices, model)
        add_expressions!(container, HydroServedReserveDownExpression, devices, model)
    end

    add_expressions!(container, ProductionCostExpression, devices, model)

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroTurbine,
    D <: Union{HydroTurbineBilinearDispatch, HydroTurbineWaterLinearDispatch},
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_expressions!(
        container,
        sys,
        TotalHydroFlowRateTurbineOutgoing,
        devices,
        model,
    )

    if has_service_model(model)
        error("$D does not support service models yet")
        add_to_expression!(
            container,
            HydroServedReserveUpExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
        add_to_expression!(
            container,
            HydroServedReserveDownExpression,
            ActivePowerReserveVariable,
            devices,
            model,
            network_model,
        )
    end

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        sys,
        TurbinePowerOutputConstraint,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

##########################################################
########### Hydro Pump Turbine Models ####################
##########################################################

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyDispatch,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ActivePowerPumpVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())

    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, D())
    end

    process_market_bid_parameters!(container, devices, model)
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerPumpVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyDispatch,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ActivePowerPumpVariable, devices, D())

    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, D())
    end

    process_market_bid_parameters!(container, devices, model)
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerPumpVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyDispatch,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    if get_attribute(model, "reservation")
        add_constraints!(
            container,
            ActivePowerPumpReservationConstraint,
            devices,
            model,
            network_model,
        )
    end

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end

#############################################################
########### Hydro Pump Turbine Commitment Models ############
#############################################################
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyCommitment,
    S <: PM.AbstractPowerModel,
}
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ActivePowerPumpVariable, devices, D())
    add_variables!(container, ReactivePowerVariable, devices, D())
    add_variables!(container, OnVariable, devices, D())

    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, D())
    end

    process_market_bid_parameters!(container, devices, model)
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerPumpVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyCommitment,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, D())
    add_variables!(container, ActivePowerPumpVariable, devices, D())
    add_variables!(container, OnVariable, devices, D())

    if get_attribute(model, "reservation")
        add_variables!(container, ReservationVariable, devices, D())
    end

    process_market_bid_parameters!(container, devices, model)
    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerPumpVariable,
        devices,
        model,
        network_model,
    )

    add_feedforward_arguments!(container, model, devices)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{H, D},
    network_model::NetworkModel{S},
) where {
    H <: PSY.HydroPumpTurbine,
    D <: HydroPumpEnergyCommitment,
    S <: PM.AbstractActivePowerModel,
}
    devices = get_available_components(model, sys)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        network_model,
    )

    add_constraints!(
        container,
        InputActivePowerVariableLimitsConstraint,
        ActivePowerPumpVariable,
        devices,
        model,
        network_model,
    )

    if get_attribute(model, "reservation")
        add_constraints!(
            container,
            ActivePowerPumpReservationConstraint,
            devices,
            model,
            network_model,
        )
    end

    objective_function!(container, devices, model, S)
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)

    return
end
