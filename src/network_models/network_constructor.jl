#################################################################################
# ArgumentConstructStage — ALL network variables (voltage + balance slacks) and
# their balance-expression wiring. These run BEFORE device ModelConstructStage so
# voltage-coupled devices (e.g. ShuntSusceptanceDispatch) can reference voltage
# variables in their Model stage, and so every network variable is created in the
# argument stage like the rest of POM.
#################################################################################

# Balance slack variables + their nodal-balance wiring. Added in ArgumentConstructStage
# so the slacks are wired into the balance expressions before the Model-stage nodal
# balance constraints snapshot them — otherwise the in-place add_to_expression! mutation
# never reaches the already-built MOI constraints and use_slacks is a silent no-op.
function _add_balance_slack_variables!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel,
    market_model::Union{Nothing, IOM.MarketModel};
    reactive::Bool,
)
    if _uses_balance_slacks(model, market_model)
        add_variables!(container, SystemBalanceSlackUp, sys, model)
        add_variables!(container, SystemBalanceSlackDown, sys, model)
        add_to_expression!(container, ActivePowerBalance, SystemBalanceSlackUp, sys, model)
        add_to_expression!(
            container, ActivePowerBalance, SystemBalanceSlackDown, sys, model,
        )
        if reactive
            add_to_expression!(
                container, ReactivePowerBalance, SystemBalanceSlackUp, sys, model,
            )
            add_to_expression!(
                container, ReactivePowerBalance, SystemBalanceSlackDown, sys, model,
            )
        end
    end
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{ACPNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    add_variables!(container, VoltageAngle, sys, model)
    add_variables!(container, VoltageMagnitude, sys, model)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = true,
    )
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:Union{ACRNetworkModel, IVRNetworkModel}},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    add_variables!(container, VoltageReal, sys, model)
    add_variables!(container, VoltageImaginary, sys, model)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = true,
    )
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{LPACCNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    add_variables!(container, VoltageAngle, sys, model)
    add_variables!(container, VoltageDeviation, sys, model)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = true,
    )
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{DCPLLNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    add_variables!(container, VoltageAngle, sys, model)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    return
end

# No-op fallback: only a StaticBranch-formulated ACTransmission branch model builds the
# BThetaBranchFlow expression here (see the specific method below). Every other branch
# formulation (StaticBranchBounds, StaticBranchUnbounded, HVDC, ...) is unaffected.
_add_static_branch_btheta_expression!(
    ::OptimizationContainer,
    ::PSY.System,
    ::DeviceModel,
    ::NetworkModel{DCPNetworkModel},
) = nothing

# StaticBranch under DCP carries its flow as the BThetaBranchFlow expression
# (`b * (va_fr - va_to - shift)`), so it must be built here — in the network's own
# ArgumentConstructStage, right after `VoltageAngle` is created — rather than from the
# branch's own ArgumentConstructStage, which build_problem.jl runs BEFORE this one (branch
# arguments, then network arguments, then device Model stage, then network Model stage
# that closes the nodal balance). This is the only point in the build order where
# `VoltageAngle` exists AND the nodal balance is still open for writes.
# TODO: Maybe we build all argument stages first, including networks?
function _add_static_branch_btheta_expression!(
    container::OptimizationContainer,
    sys::PSY.System,
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    devices = get_available_components(device_model, sys)
    isempty(devices) && return
    add_expressions!(container, BThetaBranchFlow, sys, devices, device_model, network_model)
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{DCPNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    add_variables!(container, VoltageAngle, sys, model)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    for branch_model in values(get_branch_models(template))
        _add_static_branch_btheta_expression!(container, sys, branch_model, model)
    end
    return
end

# Generic active-power-only Argument stage: CopperPlate, AreaBalance, NFA
# No voltage variables; only the (active) balance slacks.
function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:AbstractNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    return
end

# Arcs whose DC shift comes from a `PhaseShifterAngle` variable instead of the stored
# constant. `_branches_for_var` rejects a controlled circuit that a reduction merged into a
# composite entry, so a controlled arc carries exactly one circuit and the variable term
# replaces that arc's whole injection.
function _add_controlled_shift_injections!(
    container::OptimizationContainer,
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
    branch_model::DeviceModel{T},
    controlled_arcs::Set{Tuple{Int, Int}},
) where {T <: PSY.ACTransmission}
    has_container_key(container, PhaseShifterAngle, T) || return
    phase_var = get_variable(container, PhaseShifterAngle, T)
    nodal_expr = get_expression(container, ActivePowerBalance, PSY.ACBus)
    time_steps = get_time_steps(container)
    _foreach_branch(_all_branches(network_model, T)) do rep
        _phase_controlled(rep, branch_model, network_model) || return
        push!(controlled_arcs, rep.arc)
        b = _dc_susceptance(rep)
        from_no, to_no = rep.arc
        for t in time_steps
            angle = phase_var[rep.name, t]
            JuMP.add_to_expression!(nodal_expr[from_no, t], b, angle)
            JuMP.add_to_expression!(nodal_expr[to_no, t], -b, angle)
        end
    end
    return
end

# no-op on HVDC and any other non-AC branch model
_add_controlled_shift_injections!(
    ::OptimizationContainer,
    ::NetworkModel,
    ::DeviceModel,
    ::Set{Tuple{Int, Int}},
) = nothing

function _add_shift_injections!(
    container::OptimizationContainer,
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
    template::PowerOperationsProblemTemplate,
)
    controlled_arcs = Set{Tuple{Int, Int}}()
    for branch_model in values(get_branch_models(template))
        _add_controlled_shift_injections!(
            container,
            network_model,
            branch_model,
            controlled_arcs,
        )
    end
    # Every other arc keeps its stored constant. This sweeps the reduced arc axis rather
    # than the template's branch models because `requires_all_branch_models` is false for
    # PTDF networks: a shifted arc whose branch type has no DeviceModel is still in the
    # PTDF, so iterating only modeled types would silently drop its injection.
    nodal_expr = get_expression(container, ActivePowerBalance, PSY.ACBus)
    time_steps = get_time_steps(container)
    network_reduction = get_network_reduction(network_model)
    for arc in PNM.get_arc_axis(network_reduction)
        arc in controlled_arcs && continue
        injection = PNM.arc_dc_shift_injection(network_reduction, arc)
        iszero(injection) && continue
        from_no, to_no = arc
        for t in time_steps
            JuMP.add_to_expression!(nodal_expr[from_no, t], injection)
            JuMP.add_to_expression!(nodal_expr[to_no, t], -injection)
        end
    end
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:AbstractPTDFNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ArgumentConstructStage,
)
    _add_balance_slack_variables!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    _add_shift_injections!(container, model, template)
    return
end

#################################################################################
# ModelConstructStage — slack objective, balance/reference constraints, duals.
# All network variables were already added in ArgumentConstructStage above.
#################################################################################

function _construct_copper_plate_model!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel,
    market_model::Union{Nothing, IOM.MarketModel},
)
    if _uses_balance_slacks(model, market_model)
        add_to_objective_function!(container, sys, model, market_model)
    end
    add_constraints!(container, CopperPlateBalanceConstraint, sys, model)
    add_constraint_dual!(container, sys, model)
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{CopperPlateNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_copper_plate_model!(container, sys, model, get_market_model(template))
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{AreaBalanceNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_copper_plate_model!(container, sys, model, get_market_model(template))
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:AbstractPTDFNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_copper_plate_model!(container, sys, model, get_market_model(template))
    return
end

# Shared skeleton for the native voltage-angle network formulations (DCP and ACP).
# Both add the reference-bus pin, the active nodal balance, the optional slack
# objective, and the constraint dual. ACP additionally carries the reactive nodal
# balance via `reactive = true`. Network variables (voltage + slacks) are added in
# ArgumentConstructStage; this Model-stage helper only adds objective/constraints.
function _construct_voltage_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:Union{DCPNetworkModel, ACPNetworkModel, DCPLLNetworkModel}},
    market_model::Union{Nothing, IOM.MarketModel};
    reactive::Bool,
)
    if _uses_balance_slacks(model, market_model)
        add_to_objective_function!(container, sys, model, market_model)
    end
    add_constraints!(container, ReferenceBusConstraint, sys, model)
    add_constraints!(container, NodalBalanceActiveConstraint, sys, model)
    if reactive
        add_constraints!(container, NodalBalanceReactiveConstraint, sys, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{DCPNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_voltage_network!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{NFANetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    market_model = get_market_model(template)
    if _uses_balance_slacks(model, market_model)
        add_to_objective_function!(container, sys, model, market_model)
    end
    add_constraints!(container, NodalBalanceActiveConstraint, sys, model)
    add_constraint_dual!(container, sys, model)
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{ACPNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_voltage_network!(
        container, sys, model, get_market_model(template); reactive = true,
    )
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{<:Union{ACRNetworkModel, IVRNetworkModel}},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    market_model = get_market_model(template)
    if _uses_balance_slacks(model, market_model)
        add_to_objective_function!(container, sys, model, market_model)
    end
    add_constraints!(container, ReferenceBusConstraint, sys, model)
    add_constraints!(container, VoltageMagnitudeConstraint, sys, model)
    add_constraints!(container, NodalBalanceActiveConstraint, sys, model)
    add_constraints!(container, NodalBalanceReactiveConstraint, sys, model)
    add_constraint_dual!(container, sys, model)
    return
end

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{LPACCNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    market_model = get_market_model(template)
    if _uses_balance_slacks(model, market_model)
        add_to_objective_function!(container, sys, model, market_model)
    end
    add_constraints!(container, ReferenceBusConstraint, sys, model)
    add_constraints!(container, NodalBalanceActiveConstraint, sys, model)
    add_constraints!(container, NodalBalanceReactiveConstraint, sys, model)
    add_constraint_dual!(container, sys, model)
    return
end

function construct_network!(
    ::OptimizationContainer,
    ::PSY.System,
    ::NetworkModel{T},
    ::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
) where {T <: AbstractNetworkModel}
    error(
        "Network formulation $(T) is not supported. Supported formulations: \
        CopperPlateNetworkModel, AreaBalanceNetworkModel, PTDFNetworkModel, AreaPTDFNetworkModel, \
        DCPNetworkModel, NFANetworkModel, DCPLLNetworkModel, ACPNetworkModel, ACRNetworkModel, \
        LPACCNetworkModel, IVRNetworkModel.",
    )
end
