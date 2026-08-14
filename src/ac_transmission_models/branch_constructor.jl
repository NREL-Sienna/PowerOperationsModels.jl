################################# Generic AC Branch  Models ################################
# Kept as concrete-formulation no-op pairs (StaticBranch, StaticBranchBounds) rather than one
# {<:AbstractBranchFormulation} method: widening to that bound is ambiguous with the real
# StaticBranchUnbounded (NetworkModel{<:AbstractNetworkModel}), VoltageControlTap and
# AbstractSecurityConstrainedStaticBranch methods that also match CopperPlate/AreaBalance.
function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{T, StaticBranch},
    ::Union{
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission}
    @debug "No argument construction needed for CopperPlateNetworkModel or AreaBalanceNetworkModel and DeviceModel{$T, StaticBranch}" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{T, StaticBranch},
    ::Union{
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission}
    @debug "No model construction needed for CopperPlateNetworkModel or AreaBalanceNetworkModel and DeviceModel{$T, StaticBranch}" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{T, StaticBranchBounds},
    ::Union{
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission}
    @debug "No argument construction needed for CopperPlateNetworkModel or AreaBalanceNetworkModel and DeviceModel{$T, StaticBranchBounds}" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{T, StaticBranchBounds},
    ::Union{
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission}
    @debug "No model construction needed for CopperPlateNetworkModel or AreaBalanceNetworkModel and DeviceModel{$T, StaticBranchBounds}" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end

construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{<:PSY.ACTransmission, StaticBranchUnbounded},
    ::NetworkModel{<:AbstractNetworkModel},
) = nothing

construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{<:PSY.ACTransmission, StaticBranchUnbounded},
    ::NetworkModel{<:AbstractNetworkModel},
) = nothing

# For DC Power only. Implements constraints
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranch)
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

# For DC Power only. Implements constraints
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{U},
) where {T <: PSY.ACTransmission, U <: AbstractActivePowerModel}
    @debug "construct_device" _group = LOG_GROUP_BRANCH_CONSTRUCTIONS

    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, U)
    add_constraint_dual!(container, sys, device_model)
    return
end

################################## ACPNetworkModel branch constructors #################

# Shared directional flow-variable block for the StaticBranch family: the dominant
# add_variables! form across the raw call sites passes network_model (reduction-aware
# dispatch), so it is threaded through rather than dropped.
function _add_static_branch_flow_variables!(
    container::OptimizationContainer,
    devices,
    network_model::NetworkModel,
    ::Type{F},
) where {F <: AbstractBranchFormulation}
    add_variables!(container, FlowActivePowerFromToVariable, network_model, devices, F)
    add_variables!(container, FlowActivePowerToFromVariable, network_model, devices, F)
    add_variables!(container, FlowReactivePowerFromToVariable, network_model, devices, F)
    add_variables!(container, FlowReactivePowerToFromVariable, network_model, devices, F)
    return
end

# Shared StaticBranch ArgumentConstructStage steps for the AC network models
# (ACP/ACR/LPACC). LPACC inserts its CosineApproximation variable between the two calls.
function _add_static_branch_flow_variables!(
    container::OptimizationContainer,
    devices,
    network_model::NetworkModel,
)
    _add_static_branch_flow_variables!(container, devices, network_model, StaticBranch)
    return
end

# Shared balance wiring for the StaticBranch family: registers each directional flow
# variable's contribution to the per-bus ActivePowerBalance/ReactivePowerBalance.
function _wire_static_branch_flow_to_balance!(
    container::OptimizationContainer,
    devices,
    device_model::DeviceModel,
    network_model::NetworkModel,
)
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerFromToVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerToFromVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ReactivePowerBalance, FlowReactivePowerFromToVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ReactivePowerBalance, FlowReactivePowerToFromVariable,
        devices, device_model, network_model,
    )
    return
end

# Shared paired flow-slack block: upper then lower, both via the network_model-aware
# add_variables! form used at every paired call site.
function _add_flow_slacks!(
    container::OptimizationContainer,
    devices,
    network_model::NetworkModel,
    ::Type{F},
) where {F}
    add_variables!(container, FlowActivePowerSlackUpperBound, network_model, devices, F)
    add_variables!(container, FlowActivePowerSlackLowerBound, network_model, devices, F)
    return
end

# Metaed upper/lower flow-definition slack pairs, one pair per meta. StaticBranchBounds
# on the AC networks creates the "p_ft"/"p_tf"/"q_ft"/"q_tf" pairs that relax the Ohm's-law
# equalities (one pair per row so the anti-symmetric p_ft/p_tf rows do not self-cancel);
# IVR adds the terminal current-definition pairs. No-op unless slacks are requested.
function _add_flow_definition_slacks!(
    container::OptimizationContainer,
    device_model::DeviceModel{U, <:AbstractBranchFormulation},
    devices::IS.FlattenIteratorWrapper{U},
    network_model::NetworkModel,
    metas,
) where {U <: PSY.ACTransmission}
    if !get_use_slacks(device_model)
        return
    end
    time_steps = get_time_steps(container)
    # Key on the constraint axis (one representative per reduced arc), not the variable
    # axis (all reduced-arc member names): the NetworkFlowConstraint equalities that
    # consume these slacks are written once per arc, so a slack on a non-representative
    # member would be priced but never enter a row.
    branch_names = get_branch_argument_constraint_axis(
        get_network_reduction(network_model),
        get_reduced_branch_tracker(network_model),
        devices,
        NetworkFlowConstraint,
    )
    jump_model = get_jump_model(container)
    for meta in metas
        _add_meta_flow_slack!(
            container, FlowActivePowerSlackUpperBound, U, meta,
            branch_names, time_steps, jump_model,
        )
        _add_meta_flow_slack!(
            container, FlowActivePowerSlackLowerBound, U, meta,
            branch_names, time_steps, jump_model,
        )
    end
    return
end

# One-sided metaed terminal current-magnitude slacks for StaticBranch under IVR
# ("c_from"/"c_to"); each relaxes the CurrentLimitConstraint quadratic at one terminal.
function _add_current_magnitude_slacks!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{U},
    network_model::NetworkModel,
) where {U <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    # Constraint axis (one representative per reduced arc): these one-sided slacks relax the
    # per-arc CurrentLimitConstraint rows, so a slack on a non-representative member name
    # would be priced but never enter a constraint.
    branch_names = get_branch_argument_constraint_axis(
        get_network_reduction(network_model),
        get_reduced_branch_tracker(network_model),
        devices,
        CurrentLimitConstraint,
    )
    jump_model = get_jump_model(container)
    for meta in ("c_from", "c_to")
        _add_meta_flow_slack!(
            container, FlowActivePowerSlackUpperBound, U, meta,
            branch_names, time_steps, jump_model,
        )
    end
    return
end

function _add_static_branch_balance_arguments!(
    container::OptimizationContainer,
    device_model::DeviceModel{T, StaticBranch},
    devices,
    network_model::NetworkModel,
) where {T <: PSY.ACTransmission}
    if get_use_slacks(device_model)
        add_variables!(
            container, FlowActivePowerSlackUpperBound, network_model, devices, StaticBranch,
        )
    end
    _wire_static_branch_flow_to_balance!(container, devices, device_model, network_model)
    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container, BranchRatingTimeSeriesParameter, devices, device_model, network_model,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ArgumentConstructStage for StaticBranch under ACPNetworkModel.

Creates the four directional flow variables (active and reactive, from-to and to-from),
optional slack variables, and registers each flow variable's contribution to the
per-bus ActivePowerBalance and ReactivePowerBalance expressions.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device ACP StaticBranch (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(container, devices, network_model)
    _add_static_branch_balance_arguments!(container, device_model, devices, network_model)
    _add_transformer_control_variables!(container, device_model, devices, network_model)
    return
end

"""
ModelConstructStage for StaticBranch under ACPNetworkModel.

Applies the apparent-power rate limits (from-to and to-from), the π-model AC Ohm's law
constraints, and (when applicable) the branch angle-difference limits.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device ACP StaticBranch (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, ACPNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under ACPNetworkModel and ACRNetworkModel.

Creates the four directional flow variables and registers their contributions to the
per-bus balance expressions. Both network models take the same argument-stage variable
set; only their NetworkFlowConstraint builders differ.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{U},
) where {T <: PSY.ACTransmission, U <: Union{ACPNetworkModel, ACRNetworkModel}}
    @debug "construct_device $U StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(
        container,
        devices,
        network_model,
        StaticBranchBounds,
    )
    _add_flow_definition_slacks!(
        container, device_model, devices, network_model,
        get_pair_metas(slack_spec(StaticBranchBounds, U)),
    )
    _wire_static_branch_flow_to_balance!(container, devices, device_model, network_model)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranchBounds under ACPNetworkModel and ACRNetworkModel.

Applies the apparent-power rate limits (from-to and to-from), the π-model AC Ohm's law
constraints, and (when applicable) the branch angle-difference limits.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{U},
) where {T <: PSY.ACTransmission, U <: Union{ACPNetworkModel, ACRNetworkModel}}
    @debug "construct_device $U StaticBranchBounds (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    branch_rate_bounds!(container, device_model, network_model)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, U)
    add_constraint_dual!(container, sys, device_model)
    return
end

################################## ACRNetworkModel branch constructors #################

"""
ArgumentConstructStage for StaticBranch under ACRNetworkModel.

Creates the four directional flow variables (active and reactive, from-to and to-from),
optional slack variables, and registers each flow variable's contribution to the
per-bus ActivePowerBalance and ReactivePowerBalance expressions.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{ACRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device ACR StaticBranch (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(container, devices, network_model)
    _add_static_branch_balance_arguments!(container, device_model, devices, network_model)
    return
end

"""
ModelConstructStage for StaticBranch under ACRNetworkModel.

Applies the apparent-power rate limits (from-to and to-from), the π-model rectangular
AC Ohm's law constraints, and cross-product angle-difference limits for branches with
non-default (non-±π) angle bounds.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{ACRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device ACR StaticBranch (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, ACRNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

# ACR/LPACC/IVR HVDC ArgumentConstructStage: active scalar + directional reactive flow
# variables (from-to and to-from), wired into ActivePowerBalance and ReactivePowerBalance.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{
        <:Union{ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _warn_no_hvdc_reactive_capability(devices)
    add_variables!(container, FlowActivePowerVariable, devices, HVDCTwoTerminalLossless)
    add_variables!(
        container, FlowReactivePowerFromToVariable, devices, HVDCTwoTerminalLossless,
    )
    add_variables!(
        container, FlowReactivePowerToFromVariable, devices, HVDCTwoTerminalLossless,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

################################## LPACCNetworkModel branch constructors ###############

"""
ArgumentConstructStage for StaticBranch under LPACCNetworkModel.

Creates the four directional flow variables, the bus-pair cosine variable (cs), optional
slacks, and registers each flow's contribution to the per-bus ActivePowerBalance and
ReactivePowerBalance expressions.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device LPACC StaticBranch (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(container, devices, network_model)
    add_variables!(container, CosineApproximation, devices, network_model)
    _add_static_branch_balance_arguments!(container, device_model, devices, network_model)
    return
end

"""
ModelConstructStage for StaticBranch under LPACCNetworkModel.

Applies the apparent-power rate limits, the LPAC-linearized AC Ohm's law constraints, the
convex cosine relaxation, and (when applicable) the branch angle-difference limits.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device LPACC StaticBranch (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, CosineRelaxationConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, LPACCNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under LPACCNetworkModel.

Creates the four directional flow variables and the bus-pair cosine variable, and registers
each flow's contribution to the per-bus ActivePowerBalance and ReactivePowerBalance.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device LPACC StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(
        container,
        devices,
        network_model,
        StaticBranchBounds,
    )
    _add_flow_definition_slacks!(
        container, device_model, devices, network_model,
        get_pair_metas(slack_spec(StaticBranchBounds, LPACCNetworkModel)),
    )
    add_variables!(container, CosineApproximation, devices, network_model)
    _wire_static_branch_flow_to_balance!(container, devices, device_model, network_model)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranchBounds under LPACCNetworkModel.

Applies the apparent-power rate limits, the LPAC-linearized AC Ohm's law constraints, the
convex cosine relaxation, and (when applicable) the branch angle-difference limits.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device LPACC StaticBranchBounds (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    branch_rate_bounds!(container, device_model, network_model)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, CosineRelaxationConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, LPACCNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

################################## IVRNetworkModel branch constructors ################

"""
ArgumentConstructStage for StaticBranch under IVRNetworkModel.

Creates the four directional power flow variables (active and reactive, from-to and to-from)
and the six branch current variables (cr_fr, ci_fr, cr_to, ci_to, csr, csi) bounded ±c_rating_a.
Registers flow contributions to the per-bus ActivePowerBalance and ReactivePowerBalance.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device IVR StaticBranch (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _add_static_branch_flow_variables!(container, devices, network_model, StaticBranch)
    add_variables!(container, BranchCurrentFromToReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchCurrentFromToImaginary,
        devices,
        device_model,
        network_model,
    )
    add_variables!(container, BranchCurrentToFromReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchCurrentToFromImaginary,
        devices,
        device_model,
        network_model,
    )
    add_variables!(container, BranchSeriesCurrentReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchSeriesCurrentImaginary,
        devices,
        device_model,
        network_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            FlowActivePowerSlackUpperBound,
            network_model,
            devices,
            StaticBranch,
        )
        _add_current_magnitude_slacks!(container, devices, network_model)
    end
    _wire_static_branch_flow_to_balance!(container, devices, device_model, network_model)
    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranch under IVRNetworkModel.

Applies apparent-power rate limits (from-to and to-from), the IVR π-model constraints
(bilinear power-current linking, KCL at each terminal, Ohm's law across series impedance),
the terminal current-magnitude quadratic limits, and cross-product angle-difference limits
for branches with non-default (non-±π) angle bounds.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device IVR StaticBranch (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, CurrentLimitConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, IVRNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under IVRNetworkModel.

Identical to StaticBranch but uses the StaticBranchBounds formulation tag (variable-level
bounds on the power flows). With `use_slacks`, adds the metaed "p"/"q" flow-definition
slack pairs that relax the bilinear power-current equalities.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device IVR StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_variables!(
        container, FlowActivePowerFromToVariable, devices, StaticBranchBounds,
    )
    add_variables!(
        container, FlowActivePowerToFromVariable, devices, StaticBranchBounds,
    )
    add_variables!(
        container, FlowReactivePowerFromToVariable, devices, StaticBranchBounds,
    )
    add_variables!(
        container, FlowReactivePowerToFromVariable, devices, StaticBranchBounds,
    )
    _add_flow_definition_slacks!(
        container, device_model, devices, network_model,
        get_pair_metas(slack_spec(StaticBranchBounds, IVRNetworkModel)),
    )
    add_variables!(container, BranchCurrentFromToReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchCurrentFromToImaginary,
        devices,
        device_model,
        network_model,
    )
    add_variables!(container, BranchCurrentToFromReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchCurrentToFromImaginary,
        devices,
        device_model,
        network_model,
    )
    add_variables!(container, BranchSeriesCurrentReal, devices, device_model, network_model)
    add_variables!(
        container,
        BranchSeriesCurrentImaginary,
        devices,
        device_model,
        network_model,
    )
    _wire_static_branch_flow_to_balance!(container, devices, device_model, network_model)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranchBounds under IVRNetworkModel.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device IVR StaticBranchBounds (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    branch_rate_bounds!(container, device_model, network_model)
    add_constraints!(
        container, FlowRateConstraintFromTo, devices, device_model, network_model,
    )
    add_constraints!(
        container, FlowRateConstraintToFrom, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, CurrentLimitConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, IVRNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

################################## DCPNetworkModel branch constructors #################

# StaticBranch under DCP has no FlowActivePowerVariable: its flow is the BThetaBranchFlow
# expression, built in `construct_network!` (network_constructor.jl) once VoltageAngle exists.

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCP (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranch)
    end
    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranch under DCPNetworkModel.

Applies the branch flow rate limits directly on `BThetaBranchFlow` (no variable to
bound instead) and, when applicable, the branch angle-difference limits. There is no
separate Ohm's-law equality to add — the expression already carries the DC power-flow
value.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCP (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, DCPNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

################################## NFANetworkModel branch constructors #################

"""
ArgumentConstructStage for StaticBranch under NFANetworkModel.

Creates the FlowActivePowerVariable (unbounded; the rating is enforced by the
FlowRateConstraint rows) and optional slacks, and registers its contribution to the
per-bus ActivePowerBalance expression. No Ohm's law / angles.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{NFANetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device NFA (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_variables!(container, FlowActivePowerVariable, network_model, devices, StaticBranch)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranch)
    end
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranch under NFANetworkModel.

Applies only the branch flow rate limit — the transportation model has no Ohm's law
or angle-difference constraint.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{NFANetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device NFA (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, NFANetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under NFANetworkModel.

Creates the FlowActivePowerVariable and registers its contribution to the per-bus
ActivePowerBalance expression. The rating is enforced as variable bounds by the
`AbstractActivePowerModel` ModelConstructStage, so slacks cannot be priced and are rejected.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{NFANetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device NFA StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    _check_flow_slack_support(device_model, network_model)
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerVariable,
        network_model,
        devices,
        StaticBranchBounds,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

################################## DCPLLNetworkModel branch constructors ##############

"""
ArgumentConstructStage for StaticBranch under DCPLLNetworkModel.

Creates two directional flow variables (from-to and to-from), applies rating bounds via
`_set_dcpll_flow_bounds!`, and registers each flow's contribution to ActivePowerBalance.
No FlowActivePowerVariable — DCPLL uses the directional pair like ACP (active only).
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCPLL (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerFromToVariable,
        network_model,
        devices,
        StaticBranch,
    )
    add_variables!(
        container,
        FlowActivePowerToFromVariable,
        network_model,
        devices,
        StaticBranch,
    )
    # Slacks turn the rating into a soft limit, so the two enforcement styles are
    # mutually exclusive: hard variable bounds without slacks (tighter QCP), slacked
    # FlowRateConstraint pairs (ModelConstructStage) with them.
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranch)
    else
        _set_dcpll_flow_bounds!(container, sys, devices, device_model, network_model)
    end
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerFromToVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerToFromVariable,
        devices, device_model, network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranch under DCPLLNetworkModel.

Applies the DC Ohm's law on p_fr (NetworkFlowConstraint), the quadratic line-loss
coupling p_fr + p_to >= r * p_fr^2 (NetworkLossConstraint), and angle-difference limits.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCPLL (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkLossConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, DCPLLNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under DCPLLNetworkModel.

Creates the two directional flow variables and applies the rating as variable bounds. As
with StaticBranch, slacks and hard bounds are mutually exclusive enforcement styles.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCPLL StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerFromToVariable,
        network_model,
        devices,
        StaticBranchBounds,
    )
    add_variables!(
        container,
        FlowActivePowerToFromVariable,
        network_model,
        devices,
        StaticBranchBounds,
    )
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranchBounds)
    else
        _set_dcpll_flow_bounds!(container, sys, devices, device_model, network_model)
    end
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerFromToVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerToFromVariable,
        devices, device_model, network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranchBounds under DCPLLNetworkModel.

Applies the DC Ohm's law on p_fr (NetworkFlowConstraint), the quadratic line-loss
coupling (NetworkLossConstraint), and angle-difference limits. A DCPLL-specific method is
required: the AbstractActivePowerModel fallback bounds a FlowActivePowerVariable that DCPLL
never creates.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCPLL StaticBranchBounds (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, NetworkLossConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, DCPLLNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

"""
ArgumentConstructStage for StaticBranchBounds under DCPNetworkModel.

Creates the FlowActivePowerVariable (with variable-level bounds set) and registers the
branch flow contribution to the per-bus ActivePowerBalance expression.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCP StaticBranchBounds (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerVariable,
        network_model,
        devices,
        StaticBranchBounds,
    )
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranchBounds)
    end
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

"""
ModelConstructStage for StaticBranchBounds under DCPNetworkModel.
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    @debug "construct_device DCP StaticBranchBounds (ModelConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    # SBB rates the flow with variable bounds, not inequality rows. A time-varying (DLR)
    # rating cannot be a static bound, so only that case adds FlowRateConstraint rows.
    if has_container_key(container, BranchRatingTimeSeriesParameter, T)
        add_constraints!(
            container,
            FlowRateConstraint,
            devices,
            device_model,
            network_model,
        )
    else
        branch_rate_bounds!(container, device_model, network_model)
    end
    # The Ohm's-law equality defines the flow, and any slack enters here: the flow
    # variable is bounded to the rating, so the slack lets the angle-implied flow exceed it.
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, DCPNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

# For DC Power only
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranch)
    end

    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end

    if haskey(
        get_time_series_names(device_model),
        PostContingencyBranchRatingTimeSeriesParameter,
    )
        add_branch_parameters!(
            container,
            PostContingencyBranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)

    # The order of these methods is important. The add_expressions! must be before the constraints
    add_expressions!(
        container,
        PTDFBranchFlow,
        devices,
        device_model,
        network_model,
    )

    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_flow_rate_constraint_with_parameters!(
            container,
            FlowRateConstraint,
            devices,
            device_model,
            network_model,
        )
    else
        add_constraints!(
            container,
            FlowRateConstraint,
            devices,
            device_model,
            network_model,
        )
    end
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, PTDFNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)

    add_variables!(
        container,
        FlowActivePowerVariable,
        network_model,
        devices,
        StaticBranchBounds,
    )

    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, StaticBranchBounds)
    end

    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    # The order of these methods is important. The add_expressions! must be before the constraints
    add_expressions!(
        container,
        PTDFBranchFlow,
        devices,
        device_model,
        network_model,
    )

    branch_rate_bounds!(container, device_model, network_model)
    add_constraints!(container, NetworkFlowConstraint, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, PTDFNetworkModel)
    add_constraint_dual!(container, sys, device_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranchUnbounded},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchUnbounded},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    # The order of these methods is important. The add_expressions! must be before the constraints
    add_expressions!(
        container,
        PTDFBranchFlow,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_constraints!(container, NetworkFlowConstraint, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    return
end

# For AC Power only. Implements Bounds on the active power and rating constraints on the aparent power
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)

    if get_use_slacks(device_model)
        # Only one slack is needed for this formulations in AC
        add_variables!(
            container,
            FlowActivePowerSlackUpperBound,
            devices,
            StaticBranch,
        )
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    add_feedforward_constraints!(container, device_model, devices)
    add_constraints!(
        container,
        FlowRateConstraintFromTo,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        FlowRateConstraintToFrom,
        devices,
        device_model,
        network_model,
    )
    add_constraint_dual!(container, sys, device_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    branch_rate_bounds!(container, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

################################### TwoTerminal HVDC Line Models ###################################

function _add_hvdc_active_flow_arguments!(
    container::OptimizationContainer,
    devices,
    device_model::DeviceModel,
    network_model::NetworkModel,
    ::Type{F},
) where {F}
    add_variables!(container, FlowActivePowerVariable, devices, F)
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    if has_subnetworks(network_model)
        devices = get_available_components(device_model, sys)
        add_variables!(
            container,
            FlowActivePowerVariable,
            network_model,
            devices,
            HVDCTwoTerminalLossless,
        )
        add_to_expression!(
            container,
            ActivePowerBalance,
            FlowActivePowerVariable,
            devices,
            device_model,
            network_model,
        )
        add_feedforward_arguments!(container, device_model, devices)
    end
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    if has_subnetworks(network_model)
        devices =
            get_available_components(device_model, sys)
        add_constraints!(
            container,
            FlowRateConstraint,
            devices,
            device_model,
            network_model,
        )
        add_constraint_dual!(container, sys, device_model)
        add_feedforward_constraints!(container, device_model, devices)
    end
    return
end

# DCP/NFA/DCPLL HVDC ArgumentConstructStage: unbounded active scalar wired into
# ActivePowerBalance at both terminals. Mirrors HVDCTwoTerminalLossless; the difference
# is the ModelConstructStage, which adds no FlowRateConstraint.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{
        <:Union{DCPNetworkModel, NFANetworkModel, DCPLLNetworkModel},
    },
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _add_hvdc_active_flow_arguments!(
        container,
        devices,
        device_model,
        network_model,
        HVDCTwoTerminalUnbounded,
    )
    return
end

# ACPNetworkModel HVDC ArgumentConstructStage: unbounded active scalar plus directional
# reactive flow variables, wired into ActivePowerBalance and ReactivePowerBalance.
# Mirrors HVDCTwoTerminalLossless; only the (absent) rate constraints differ.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_variables!(container, FlowActivePowerVariable, devices, HVDCTwoTerminalUnbounded)
    add_variables!(
        container, FlowReactivePowerFromToVariable, devices, HVDCTwoTerminalUnbounded,
    )
    add_variables!(
        container, FlowReactivePowerToFromVariable, devices, HVDCTwoTerminalUnbounded,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

# ACR/LPACC/IVR HVDC ArgumentConstructStage: same variable set and wiring as ACP.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{
        <:Union{ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_variables!(container, FlowActivePowerVariable, devices, HVDCTwoTerminalUnbounded)
    add_variables!(
        container, FlowReactivePowerFromToVariable, devices, HVDCTwoTerminalUnbounded,
    )
    add_variables!(
        container, FlowReactivePowerToFromVariable, devices, HVDCTwoTerminalUnbounded,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{<:PSY.TwoTerminalHVDC, HVDCTwoTerminalUnbounded},
    ::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(device_model, sys)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _add_hvdc_active_flow_arguments!(
        container,
        devices,
        device_model,
        network_model,
        HVDCTwoTerminalUnbounded,
    )
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{<:PSY.TwoTerminalHVDC, HVDCTwoTerminalUnbounded},
    ::NetworkModel{CopperPlateNetworkModel},
)
    devices = get_available_components(device_model, sys)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Arguments not built"
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Model not built"
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded, HVDCTwoTerminalLossless and HVDCTwoTerminalDispatch
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Arguments not built"
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Model not built"
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded, HVDCTwoTerminalLossless and HVDCTwoTerminalDispatch
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Arguments not built"
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    ::NetworkModel{AreaBalanceNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for $T. Model not built"
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded and HVDCTwoTerminalLossless
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _add_hvdc_active_flow_arguments!(
        container,
        devices,
        device_model,
        network_model,
        HVDCTwoTerminalUnbounded,
    )
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded and HVDCTwoTerminalLossless
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{<:PSY.TwoTerminalHVDC, HVDCTwoTerminalUnbounded},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
)
    devices = get_available_components(device_model, sys)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded and HVDCTwoTerminalLossless
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _add_hvdc_active_flow_arguments!(
        container,
        devices,
        device_model,
        network_model,
        HVDCTwoTerminalLossless,
    )
    return
end

# DCP/NFA/DCPLL HVDC ArgumentConstructStage: lossless HVDC is a single controllable
# bounded active-power flow into ActivePowerBalance with no angle or Ohm's-law coupling.
# DCP, NFA, and DCPLL are handled identically — no reactive power enters the model.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{
        <:Union{DCPNetworkModel, NFANetworkModel, DCPLLNetworkModel},
    },
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _add_hvdc_active_flow_arguments!(
        container,
        devices,
        device_model,
        network_model,
        HVDCTwoTerminalLossless,
    )
    return
end

# ACPNetworkModel HVDC ArgumentConstructStage: active-power scalar plus directional reactive
# flow variables (from-to and to-from), wired into ActivePowerBalance and ReactivePowerBalance.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    _warn_no_hvdc_reactive_capability(devices)
    add_variables!(container, FlowActivePowerVariable, devices, HVDCTwoTerminalLossless)
    add_variables!(
        container, FlowReactivePowerFromToVariable, devices, HVDCTwoTerminalLossless,
    )
    add_variables!(
        container, FlowReactivePowerToFromVariable, devices, HVDCTwoTerminalLossless,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        FlowReactivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

# Repeated method to avoid ambiguity between HVDCTwoTerminalUnbounded and HVDCTwoTerminalLossless
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLossless},
    network_model::NetworkModel{PTDFNetworkModel},
) where {
    T <: PSY.TwoTerminalHVDC,
}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerToFromVariable,
        devices,
        HVDCTwoTerminalDispatch,
    )
    add_variables!(
        container,
        FlowActivePowerFromToVariable,
        devices,
        HVDCTwoTerminalDispatch,
    )
    add_variables!(container, HVDCLosses, devices, HVDCTwoTerminalDispatch)
    add_variables!(container, HVDCFlowDirectionVariable, devices, HVDCTwoTerminalDispatch)
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        HVDCLosses,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container,
        FlowRateConstraintFromTo,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        FlowRateConstraintToFrom,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, HVDCPowerBalance, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

# The AC natives take the same path as the DC natives: the HVDC link is an
# active-power-only injector (no reactive offer), so only the directional active
# flow variables are created and wired.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{<:Union{AbstractActivePowerModel, NativeACNetworkModel}},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        FlowActivePowerToFromVariable,
        devices,
        HVDCTwoTerminalDispatch,
    )
    add_variables!(
        container,
        FlowActivePowerFromToVariable,
        devices,
        HVDCTwoTerminalDispatch,
    )
    add_variables!(container, HVDCFlowDirectionVariable, devices, HVDCTwoTerminalDispatch)
    add_variables!(container, HVDCLosses, devices, HVDCTwoTerminalDispatch)
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    @warn "CopperPlateNetworkModel models with HVDC ignores inter-area losses"
    add_constraints!(
        container,
        FlowRateConstraintFromTo,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        FlowRateConstraintToFrom,
        devices,
        device_model,
        network_model,
    )
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

# Shared by the PTDF path, every native nodal network model (AC and DC), and the
# aggregated CopperPlate/AreaBalance balances: the received-power variables and PWL loss
# segments are identical across all of them; only the add_to_expression! wiring differs
# by network. Under the AC/DC natives the link is an active-power-only injector (no
# reactive offer). On CopperPlate both terminals share one balance row, so the line's
# net contribution is -(losses); on AreaBalance each terminal enters its own area row.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: PSY.TwoTerminalHVDC,
    U <: HVDCTwoTerminalPiecewiseLoss,
}
    devices = get_available_components(device_model, sys)
    add_variables!(
        container,
        HVDCActivePowerReceivedFromVariable,
        devices,
        HVDCTwoTerminalPiecewiseLoss,
    )
    add_variables!(
        container,
        HVDCActivePowerReceivedToVariable,
        devices,
        HVDCTwoTerminalPiecewiseLoss,
    )
    _add_sparse_pwl_loss_variables!(container, devices, device_model)
    add_to_expression!(
        container,
        ActivePowerBalance,
        HVDCActivePowerReceivedFromVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        HVDCActivePowerReceivedToVariable,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: PSY.TwoTerminalHVDC,
    U <: HVDCTwoTerminalPiecewiseLoss,
}
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container,
        FlowRateConstraintFromTo,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        FlowRateConstraintToFrom,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCFlowCalculationConstraint,
        devices,
        device_model,
        network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{<:Union{AbstractActivePowerModel, NativeACNetworkModel}},
) where {T <: PSY.TwoTerminalHVDC}
    devices = get_available_components(device_model, sys)
    add_constraints!(
        container,
        FlowRateConstraintFromTo,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        FlowRateConstraintToFrom,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, HVDCPowerBalance, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

############################# NEW LCC HVDC NON-LINEAR MODEL #############################

# LPACC twin of the `_lcc_terminal_voltage` methods in TwoTerminalDC_branches.jl:
# the LPACC voltage magnitude is 1 + phi with phi the bus VoltageDeviation.
function _lcc_terminal_voltage(
    container::OptimizationContainer,
    d::T,
    tag::String,
    ::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.TwoTerminalLCCLine}
    phi = get_variable(container, VoltageDeviation, PSY.ACBus)
    arc = PSY.get_arc(d)
    if tag == "from"
        bus_name = PSY.get_name(PSY.get_from(arc))
    else
        bus_name = PSY.get_name(PSY.get_to(arc))
    end
    return [1.0 + phi[bus_name, t] for t in get_time_steps(container)]
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLCC},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {T <: PSY.TwoTerminalLCCLine}
    devices = get_available_components(device_model, sys)
    # Per-terminal voltage-magnitude aux for the converter equations under ACR/IVR
    # (tags "from"/"to"); no-op under ACP and LPACC, where the network voltage
    # variables are used directly.
    add_regulated_voltage_magnitude!(container, devices, sys, network_model)

    # Variables
    add_variables!(
        container,
        HVDCRectifierActivePowerVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterActivePowerVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierReactivePowerVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterReactivePowerVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierDelayAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterExtinctionAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierPowerFactorAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterPowerFactorAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierOverlapAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterOverlapAngleVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierDCVoltageVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterDCVoltageVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierACCurrentVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterACCurrentVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        DCLineCurrentFlowVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCRectifierTapSettingVariable,
        devices,
        HVDCTwoTerminalLCC,
    )
    add_variables!(
        container,
        HVDCInverterTapSettingVariable,
        devices,
        HVDCTwoTerminalLCC,
    )

    # Expressions
    add_to_expression!(
        container,
        ActivePowerBalance,
        HVDCRectifierActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        HVDCInverterActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        HVDCRectifierReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        HVDCInverterReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, HVDCTwoTerminalLCC},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {T <: PSY.TwoTerminalLCCLine}
    devices = get_available_components(device_model, sys)
    add_regulated_voltage_magnitude_constraints!(container, devices, sys, network_model)
    add_constraints!(
        container,
        HVDCRectifierDCLineVoltageConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCInverterDCLineVoltageConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCRectifierOverlapAngleConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCInverterOverlapAngleConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCRectifierPowerFactorAngleConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCInverterPowerFactorAngleConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCRectifierACCurrentFlowConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCInverterACCurrentFlowConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCRectifierPowerCalculationConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCInverterPowerCalculationConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        HVDCTransmissionDCLineConstraint,
        devices,
        device_model,
        network_model,
    )
    return
end

################################# AreaInterchange Models ################################
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, U},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {U <: Union{StaticBranchUnbounded, StaticBranch}}
    devices = get_available_components(device_model, sys)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranchUnbounded},
    network_model::NetworkModel{T},
) where {T <: AbstractActivePowerModel}
    devices = get_available_components(device_model, sys)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, T},
    network_model::NetworkModel{U},
) where {
    T <: Union{StaticBranchUnbounded, StaticBranch},
    U <: AbstractNetworkModel,
}
    devices = get_available_components(device_model, sys)
    has_ts = PSY.has_time_series.(devices)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, network_model, T)
    end
    if any(has_ts) && !all(has_ts)
        error(
            "Not all AreaInterchange devices have time series. Check data to complete (or remove) time series.",
        )
    end
    add_variables!(
        container,
        FlowActivePowerVariable,
        network_model,
        devices,
        T,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    if all(has_ts)
        for device in devices
            name = PSY.get_name(device)
            num_ts = length(unique(PSY.get_name.(PSY.get_time_series_keys(device))))
            if num_ts < 2
                error(
                    "AreaInterchange $name has less than two time series. It is required to add both from_to and to_from time series.",
                )
            end
        end
        add_parameters!(container, FromToFlowLimitParameter, devices, device_model)
        add_parameters!(container, ToFromFlowLimitParameter, devices, device_model)
    end
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranch},
    network_model::NetworkModel{T},
) where {T <: AbstractActivePowerModel}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowLimitConstraint, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function _get_branch_map(network_model::NetworkModel)
    @assert !isempty(network_model.modeled_branch_types)
    net_reduction_data = get_network_reduction(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)
    inter_area_branch_map =
    # This method uses ACBranch to support HVDC
        Dict{Tuple{String, String}, Dict{DataType, Vector{String}}}()
    name_to_arc_maps = PNM.get_name_to_arc_maps(net_reduction_data)
    for br_type in network_model.modeled_branch_types
        !haskey(name_to_arc_maps, br_type) && continue
        name_to_arc_map = PNM.get_name_to_arc_map(net_reduction_data, br_type)
        for (name, (arc, reduction)) in name_to_arc_map
            reduction_entry = all_branch_maps_by_type[reduction][br_type][arc]
            area_from, area_to = _get_area_from_to(reduction_entry)
            if area_from != area_to
                branch_typed_dict = get!(
                    Dict{DataType, Vector{String}},
                    inter_area_branch_map,
                    (PSY.get_name(area_from), PSY.get_name(area_to)),
                )
                _add_to_branch_map!(branch_typed_dict, reduction_entry, name)
            end
        end
    end
    return inter_area_branch_map
end

function _add_to_branch_map!(
    branch_typed_dict::Dict{DataType, Vector{String}},
    ::T,
    name::String,
) where {T <: PSY.ACBranch}
    if !haskey(branch_typed_dict, T)
        branch_typed_dict[T] = [name]
    else
        push!(branch_typed_dict[T], name)
    end
end

function _add_to_branch_map!(
    branch_typed_dict::Dict{DataType, Vector{String}},
    reduction_entry::Union{PNM.BranchesParallel, PNM.BranchesSeries},
    name::String,
)
    _add_to_branch_map!(branch_typed_dict, first(reduction_entry), name)
end

# This method uses ACBranch to support 2T - HVDC
function _get_area_from_to(reduction_entry::PSY.ACBranch)
    area_from = PSY.get_area(PSY.get_from(PSY.get_arc(reduction_entry)))
    area_to = PSY.get_area(PSY.get_to(PSY.get_arc(reduction_entry)))
    return area_from, area_to
end

function _get_area_from_to(reduction_entry::PNM.ThreeWindingTransformerCircuit)
    tfw = PNM.get_transformer(reduction_entry)
    winding_int = PNM.get_winding_number(reduction_entry)
    if winding_int == 1
        area_from = PSY.get_area(PSY.get_primary_star_arc(tfw).from)
        area_to = PSY.get_area(PSY.get_primary_star_arc(tfw).to)
    elseif winding_int == 2
        area_from = PSY.get_area(PSY.get_secondary_star_arc(tfw).from)
        area_to = PSY.get_area(PSY.get_secondary_star_arc(tfw).to)
    elseif winding_int == 3
        area_from = PSY.get_area(PSY.get_tertiary_star_arc(tfw).from)
        area_to = PSY.get_area(PSY.get_tertiary_star_arc(tfw).to)
    else
        @assert false "Winding number $winding_int is not valid for three-winding transformer"
    end
    return area_from, area_to
end

function _get_area_from_to(reduction_entry::PNM.BranchesParallel)
    return _get_area_from_to(first(reduction_entry))
end

function _get_area_from_to(reduction_entry::PNM.BranchesSeries)
    area_froms = [_get_area_from_to(x)[1] for x in reduction_entry]
    area_tos = [_get_area_from_to(x)[2] for x in reduction_entry]
    all_areas = vcat(area_froms, area_tos)
    if length(unique(all_areas)) > 1
        error(
            "Inter-area line found as part of a degree two chain reduction; this feature is not supported",
        )
    end
    return first(all_areas), first(all_areas)
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranch},
    network_model::NetworkModel{T},
) where {T <: AbstractPTDFNetworkModel}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowLimitConstraint, devices, device_model, network_model)
    _add_inter_area_flow_bound_constraints!(
        container, sys, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranch},
    network_model::NetworkModel{T},
) where {T <: AbstractReactivePowerNetworkModel}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, FlowLimitConstraint, devices, device_model, network_model)
    _add_inter_area_flow_bound_constraints!(
        container, sys, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranchUnbounded},
    network_model::NetworkModel{T},
) where {T <: AbstractReactivePowerNetworkModel}
    devices = get_available_components(device_model, sys)
    _add_inter_area_flow_bound_constraints!(
        container, sys, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    return
end

# PNM's reduction maps cover only PSY.ACTransmission, so _get_branch_map never sees the
# HVDC tie lines; they are also never reduced, so collecting them from the system
# directly is safe.
function _add_hvdc_inter_area_branches!(
    inter_area_branch_map::Dict{Tuple{String, String}, Dict{DataType, Vector{String}}},
    sys::PSY.System,
    network_model::NetworkModel,
)
    for br_type in network_model.modeled_branch_types
        _add_hvdc_inter_area_branches_of_type!(inter_area_branch_map, br_type, sys)
    end
    return
end

function _add_hvdc_inter_area_branches_of_type!(
    ::Dict{Tuple{String, String}, Dict{DataType, Vector{String}}},
    ::Type{<:PSY.Branch},
    ::PSY.System,
)
    return
end

function _add_hvdc_inter_area_branches_of_type!(
    inter_area_branch_map::Dict{Tuple{String, String}, Dict{DataType, Vector{String}}},
    ::Type{T},
    sys::PSY.System,
) where {T <: PSY.TwoTerminalHVDC}
    for device in PSY.get_available_components(T, sys)
        area_from, area_to = _get_area_from_to(device)
        if area_from != area_to
            branch_typed_dict = get!(
                Dict{DataType, Vector{String}},
                inter_area_branch_map,
                (PSY.get_name(area_from), PSY.get_name(area_to)),
            )
            _add_to_branch_map!(branch_typed_dict, device, PSY.get_name(device))
        end
    end
    return
end

# Not ideal to do this here, but it is a not terrible workaround
# The area interchanges are like a services/device mix.
# Doesn't include the possibility of Multi-terminal HVDC
function _add_inter_area_flow_bound_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    device_model::DeviceModel{PSY.AreaInterchange, <:AbstractBranchFormulation},
    network_model::NetworkModel,
)
    inter_area_branch_map = _get_branch_map(network_model)
    _add_hvdc_inter_area_branches!(inter_area_branch_map, sys, network_model)
    add_constraints!(
        container,
        LineFlowBoundConstraint,
        devices,
        device_model,
        network_model,
        inter_area_branch_map,
    )
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranchUnbounded},
    network_model::NetworkModel{AreaBalanceNetworkModel},
)
    devices = get_available_components(device_model, sys)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

#TODO Check if for SCUC AreaPTDF needs something else
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.AreaInterchange, StaticBranchUnbounded},
    network_model::NetworkModel{AreaPTDFNetworkModel},
)
    devices = get_available_components(device_model, sys)
    _add_inter_area_flow_bound_constraints!(
        container, sys, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{PSY.TwoTerminalVSCLine, F},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {F <: AbstractTwoTerminalVSCFormulation}
    devices = get_available_components(device_model, sys)

    add_variables!(container, FlowActivePowerFromToVariable, devices, F)
    add_variables!(container, FlowActivePowerToFromVariable, devices, F)
    add_variables!(container, DCLineCurrentFlowVariable, devices, F)
    add_variables!(container, HVDCFromDCVoltage, devices, F)
    add_variables!(container, HVDCToDCVoltage, devices, F)

    _maybe_add_reactive_power_variables!(
        container, devices, device_model, network_model,
        (HVDCReactivePowerFromVariable, HVDCReactivePowerToVariable),
    )

    _add_vsc_regulated_voltage!(container, devices, sys, device_model, network_model)

    _add_vsc_loss_current_variables!(container, devices, device_model, network_model)

    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerFromToVariable,
        devices, device_model, network_model,
    )
    add_to_expression!(
        container, ActivePowerBalance, FlowActivePowerToFromVariable,
        devices, device_model, network_model,
    )

    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.TwoTerminalVSCLine, F},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {F <: AbstractTwoTerminalVSCFormulation}
    devices = get_available_components(device_model, sys)
    time_steps = get_time_steps(container)
    line_names = [PSY.get_name(d) for d in devices]

    v_f_var = get_variable(container, HVDCFromDCVoltage, PSY.TwoTerminalVSCLine)
    v_t_var = get_variable(container, HVDCToDCVoltage, PSY.TwoTerminalVSCLine)
    i_var = get_variable(container, DCLineCurrentFlowVariable, PSY.TwoTerminalVSCLine)

    v_f_bounds = PSY.get_voltage_limits_from.(devices)
    v_t_bounds = PSY.get_voltage_limits_to.(devices)
    i_bounds = [
        (min = -_vsc_cable_i_max(d), max = _vsc_cable_i_max(d)) for d in devices
    ]

    quad_cfg, bilin_cfg =
        _build_converter_configs(F, device_model, vcat(v_f_bounds, v_t_bounds), i_bounds)

    # The converter loss terms read `i_sq`; build it once and reuse it for both
    # terminal bilinears.
    i_sq_expr = IOM._add_quadratic_approx!(
        quad_cfg, container, PSY.TwoTerminalVSCLine,
        line_names, time_steps, i_var, i_bounds, "i_sq",
    )

    _add_converter_bilinear!(
        bilin_cfg, quad_cfg, container, PSY.TwoTerminalVSCLine,
        line_names, time_steps,
        v_f_var, i_var, i_sq_expr,
        v_f_bounds, i_bounds, "vi_ft",
    )
    _add_converter_bilinear!(
        bilin_cfg, quad_cfg, container, PSY.TwoTerminalVSCLine,
        line_names, time_steps,
        v_t_var, i_var, i_sq_expr,
        v_t_bounds, i_bounds, "vi_tf",
    )

    _register_vsc_apparent_power_squares!(
        bilin_cfg, container, devices, line_names, time_steps, device_model,
        network_model,
    )

    _add_vsc_loss_current_constraints!(
        container, devices, device_model, network_model,
    )

    add_constraints!(
        container, HVDCCableOhmsLawConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, HVDCVSCConverterPowerConstraint, devices, device_model, network_model,
    )
    _add_vsc_apparent_power_limit!(
        bilin_cfg,
        container,
        devices,
        device_model,
        network_model,
    )

    _add_vsc_regulated_voltage_constraints!(
        container, devices, sys, device_model, network_model,
    )
    _apply_vsc_control_objective!(container, devices, device_model, network_model)

    add_constraint_dual!(container, sys, device_model)
    add_feedforward_constraints!(container, device_model, devices)
    return
end

# AreaBalanceNetworkModel warning (consistent with other two-terminal formulations).
function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{PSY.TwoTerminalVSCLine, <:AbstractTwoTerminalVSCFormulation},
    ::NetworkModel{AreaBalanceNetworkModel},
)
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for PSY.TwoTerminalVSCLine. Arguments not built"
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{PSY.TwoTerminalVSCLine, <:AbstractTwoTerminalVSCFormulation},
    ::NetworkModel{AreaBalanceNetworkModel},
)
    @warn "AreaBalanceNetworkModel doesn't model individual line flows for PSY.TwoTerminalVSCLine. Model not built"
    return
end
