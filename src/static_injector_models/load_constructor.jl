# AbstractNetworkModel + ControllableLoad device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, D},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    L <: PSY.ControllableLoad,
    D <: AbstractControllablePowerLoadFormulation,
}
    devices =
        get_available_components(model,
            sys,
        )

    add_variables!(container, ActivePowerVariable, devices, D)
    add_variables!(container, ReactivePowerVariable, devices, D)

    process_market_bid_parameters!(container, devices, model, false, true)

    # Add Variables to expressions
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

    # With a reserve service, build the range expressions (= P) so an up-/down-reserve award can
    # adjust the load's shed/consume headroom (mirrors RenewableDispatch). Gated so the pure-energy
    # path is unchanged.
    if has_service_model(model)
        add_to_expression!(
            container, ActivePowerRangeExpressionLB, ActivePowerVariable,
            devices, model, network_model)
        add_to_expression!(
            container, ActivePowerRangeExpressionUB, ActivePowerVariable,
            devices, model, network_model)
    end

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    # With reserves, bind the range expressions (LB = P - Σr_up >= 0, UB = P + Σr_down <= forecast);
    # without, bind the raw variable exactly as before (mirrors RenewableDispatch).
    if has_service_model(model)
        add_constraints!(
            container, ActivePowerVariableLimitsConstraint, ActivePowerRangeExpressionLB,
            devices, model, network_model)
        add_constraints!(
            container, ActivePowerVariableLimitsConstraint, ActivePowerRangeExpressionUB,
            devices, model, network_model)
    else
        add_constraints!(
            container,
            ActivePowerVariableLimitsConstraint,
            ActivePowerVariable,
            devices,
            model,
            network_model,
        )
    end
    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_constraints!(container, model, devices)

    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

# AbstractActivePowerModel + ControllableLoad device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, D},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    L <: PSY.ControllableLoad,
    D <: AbstractControllablePowerLoadFormulation,
}
    devices =
        get_available_components(model,
            sys,
        )

    add_variables!(container, ActivePowerVariable, devices, D)

    # Add Variables to expressions
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    # With a reserve service, build the range expressions (= P) so an up-/down-reserve award can
    # adjust the load's shed/consume headroom (mirrors RenewableDispatch). Gated so the pure-energy
    # path is unchanged.
    if has_service_model(model)
        add_to_expression!(
            container, ActivePowerRangeExpressionLB, ActivePowerVariable,
            devices, model, network_model)
        add_to_expression!(
            container, ActivePowerRangeExpressionUB, ActivePowerVariable,
            devices, model, network_model)
    end

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end

    process_market_bid_parameters!(container, devices, model, false, true)

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    # With reserves, bind the range expressions (LB = P - Σr_up >= 0, UB = P + Σr_down <= forecast);
    # without, bind the raw variable exactly as before (mirrors RenewableDispatch).
    if has_service_model(model)
        add_constraints!(
            container, ActivePowerVariableLimitsConstraint, ActivePowerRangeExpressionLB,
            devices, model, network_model)
        add_constraints!(
            container, ActivePowerVariableLimitsConstraint, ActivePowerRangeExpressionUB,
            devices, model, network_model)
    else
        add_constraints!(
            container,
            ActivePowerVariableLimitsConstraint,
            ActivePowerVariable,
            devices,
            model,
            network_model,
        )
    end
    add_feedforward_constraints!(container, model, devices)

    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

# AbstractNetworkModel + PowerLoadInterruption device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, PowerLoadInterruption},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    add_variables!(container, ActivePowerVariable, devices, PowerLoadInterruption)
    add_variables!(container, ReactivePowerVariable, devices, PowerLoadInterruption)
    add_variables!(container, OnVariable, devices, PowerLoadInterruption)

    # Add Variables to expressions
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

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end

    process_market_bid_parameters!(container, devices, model, false, true)

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{L, PowerLoadInterruption},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        OnVariable,
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

    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

# AbstractActivePowerModel + PowerLoadInterruption device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, PowerLoadInterruption},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    add_variables!(container, ActivePowerVariable, devices, PowerLoadInterruption)
    add_variables!(container, OnVariable, devices, PowerLoadInterruption)

    process_market_bid_parameters!(container, devices, model, false, true)
    # Add Variables to expressions
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{L, PowerLoadInterruption},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {L <: PSY.ControllableLoad}
    devices =
        get_available_components(model,
            sys,
        )

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        OnVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_constraints!(container, model, devices)

    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

# AbstractNetworkModel + StaticPowerLoad device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, StaticPowerLoad},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.ElectricLoad}
    devices =
        get_available_components(model,
            sys,
        )

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ReactivePowerTimeSeriesParameter)
        add_parameters!(container, ReactivePowerTimeSeriesParameter, devices, model)
    end

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

# AbstractActivePowerModel + StaticPowerLoad device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, StaticPowerLoad},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {L <: PSY.ElectricLoad}
    devices =
        get_available_components(model,
            sys,
        )

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end

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

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{<:PSY.ElectricLoad, StaticPowerLoad},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    # Static PowerLoad doesn't add any constraints to the model. This function covers
    # AbstractNetworkModel and AbtractActivePowerModel
    return
end

# AbstractNetworkModel + StaticLoad, but with non-StaticPowerLoad device models
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.StaticLoad}
    devices =
        get_available_components(model,
            sys,
        )

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ReactivePowerTimeSeriesParameter)
        add_parameters!(container, ReactivePowerTimeSeriesParameter, devices, model)
    end

    process_market_bid_parameters!(container, devices, model, false, true)
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

# AbstractActivePowerModel + StaticLoad, but with non-StaticPowerLoad device models
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {L <: PSY.StaticLoad}
    devices =
        get_available_components(model,
            sys,
        )

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        network_model,
    )

    process_market_bid_parameters!(container, devices, model, false, true)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ccs::ModelConstructStage,
    model::DeviceModel{L, D},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    L <: PSY.StaticLoad,
    D <: AbstractControllablePowerLoadFormulation,
}
    if D != StaticPowerLoad
        @warn(
            "The Formulation $(D) only applies to FormulationControllable Loads, \n Consider Changing the Device Formulation to StaticPowerLoad"
        )
    end

    # Makes a new model with the correct formulation of the type. Needs to recover all the other fields
    # slacks, services and duals are not applicable to StaticPowerLoad so those are ignored
    new_model = DeviceModel(
        L,
        StaticPowerLoad;
        feedforwards = model.feedforwards,
        time_series_names = model.time_series_names,
        attributes = model.attributes,
    )
    construct_device!(container, sys, ccs, new_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.ShiftablePowerLoad, PowerLoadShift},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(model, sys)

    add_variables!(container, ShiftUpActivePowerVariable, devices, PowerLoadShift)
    add_variables!(container, ShiftDownActivePowerVariable, devices, PowerLoadShift)
    add_variables!(container, ReactivePowerVariable, devices, PowerLoadShift)

    process_market_bid_parameters!(container, devices, model, false, true)

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ShiftUpActivePowerTimeSeriesParameter)
        add_parameters!(container, ShiftUpActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ShiftDownActivePowerTimeSeriesParameter)
        add_parameters!(container, ShiftDownActivePowerTimeSeriesParameter, devices, model)
    end

    # Add realized load expression
    add_expressions!(container, RealizedShiftedLoad, devices, model)

    # Add Parameters to expressions
    add_to_expression!(
        container,
        ActivePowerBalance,
        RealizedShiftedLoad,
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

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.ShiftablePowerLoad, PowerLoadShift},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices =
        get_available_components(model,
            sys,
        )

    add_constraints!(
        container,
        ShiftedActivePowerBalanceConstraint,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        RealizedShiftedLoadMinimumBoundConstraint,
        RealizedShiftedLoad,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ShiftUpActivePowerVariableLimitsConstraint,
        ShiftUpActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ShiftDownActivePowerVariableLimitsConstraint,
        ShiftDownActivePowerVariable,
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
    add_constraints!(
        container,
        NonAnticipativityConstraint,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, get_network_formulation(network_model))
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end

# AbstractActivePowerModel + PowerLoadShift device model
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.ShiftablePowerLoad, PowerLoadShift},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    devices = get_available_components(model, sys)

    add_variables!(container, ShiftUpActivePowerVariable, devices, PowerLoadShift)
    add_variables!(container, ShiftDownActivePowerVariable, devices, PowerLoadShift)

    process_market_bid_parameters!(container, devices, model, false, true)

    if haskey(get_time_series_names(model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ShiftUpActivePowerTimeSeriesParameter)
        add_parameters!(container, ShiftUpActivePowerTimeSeriesParameter, devices, model)
    end
    if haskey(get_time_series_names(model), ShiftDownActivePowerTimeSeriesParameter)
        add_parameters!(container, ShiftDownActivePowerTimeSeriesParameter, devices, model)
    end

    # Add realized load expression
    add_expressions!(container, RealizedShiftedLoad, devices, model)

    # Add Parameters to expressions
    add_to_expression!(
        container,
        ActivePowerBalance,
        RealizedShiftedLoad,
        devices,
        model,
        network_model,
    )

    add_cost_expressions!(container, devices, model)
    add_event_arguments!(container, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.ShiftablePowerLoad, PowerLoadShift},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    devices =
        get_available_components(model,
            sys,
        )

    add_constraints!(
        container,
        ShiftedActivePowerBalanceConstraint,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        RealizedShiftedLoadMinimumBoundConstraint,
        RealizedShiftedLoad,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ShiftUpActivePowerVariableLimitsConstraint,
        ShiftUpActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        ShiftDownActivePowerVariableLimitsConstraint,
        ShiftDownActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_constraints!(
        container,
        NonAnticipativityConstraint,
        devices,
        model,
        network_model,
    )

    add_feedforward_constraints!(container, model, devices)

    objective_function!(container, devices, model, get_network_formulation(network_model))
    add_event_constraints!(container, devices, model, network_model)
    add_constraint_dual!(container, sys, model)
    return
end
