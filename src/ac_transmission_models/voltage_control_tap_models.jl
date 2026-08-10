#################################################################################
# Voltage-controlling tap transformer (Family B).
#
# `VoltageControlTap` models the off-nominal tap ratio of a `PSY.TwoWindingTransformer`
# as a bounded continuous decision variable `t ∈ [t_min, t_max]`
# (`TapRatioVariable`) that enters the AC π-model Ohm's law nonlinearly (the fixed
# tap `tm` of the StaticBranch law is replaced by the variable `t`, so the self
# terms scale as `1/t²` and the coupling terms as `1/t`). The control objective is
# applied count-invariantly with a single `JuMP.fix` on an already-created variable:
#   VOLTAGE             → fix the regulated-bus VoltageMagnitude to voltage_setpoint
#   REACTIVE_POWER_FLOW → fix the from-to reactive flow to reactive_power_flow
#   ACTIVE_POWER_FLOW   → fix the from-to active flow to active_power_flow
# No per-mode constraint is ever added — the variable/constraint containers are the
# same in every mode (a `FixRef` lives at the variable level).
#
# Voltage-objective regulation: under ACP, the scalar VoltageMagnitude is pinned
# directly; under ACR/IVR, a per-device RegulatedVoltageMagnitude aux variable is
# tied to the rectangular components via RegulatedVoltageMagnitudeConstraint and then
# fixed. Reactive/active-flow objectives share a common path across ACP and ACR.
# The formulation is dropped from DC templates via `models_reactive_power`.
#################################################################################

# Finite tap-ratio bounds (pu turns ratio) for the control variable `t`. A
# non-finite limit is a data error (Principle 0 / IPOPT).
function _tap_ratio_limits(d::PSY.TwoWindingTransformer)
    lims = PSY.get_tap_limits(d)
    lo = lims.min
    hi = lims.max
    if !(isfinite(lo) && isfinite(hi))
        error(
            "TwoWindingTransformer $(PSY.get_name(d)) has non-finite tap_limits ",
            "($(lo), $(hi)); cannot bound TapRatioVariable",
        )
    end
    if lo <= 0.0
        error(
            "TwoWindingTransformer $(PSY.get_name(d)) has a non-positive tap lower limit ",
            "($(lo)); the variable-tap Ohm's law divides by t and requires t > 0",
        )
    end
    if hi < lo
        error(
            "TwoWindingTransformer $(PSY.get_name(d)) has tap_limits.max < tap_limits.min ",
            "($(hi) < $(lo))",
        )
    end
    return (min = lo, max = hi)
end

#################################################################################
# TapRatioVariable traits
#################################################################################

get_variable_binary(
    ::Type{TapRatioVariable},
    ::Type{<:PSY.TwoWindingTransformer},
    ::Type{VoltageControlTap},
) = false

get_variable_multiplier(
    ::Type{TapRatioVariable},
    ::Type{<:PSY.TwoWindingTransformer},
    ::Type{VoltageControlTap},
) = 1.0

function get_variable_lower_bound(
    ::Type{TapRatioVariable},
    d::PSY.TwoWindingTransformer,
    ::Type{VoltageControlTap},
)
    return _tap_ratio_limits(d).min
end

function get_variable_upper_bound(
    ::Type{TapRatioVariable},
    d::PSY.TwoWindingTransformer,
    ::Type{VoltageControlTap},
)
    return _tap_ratio_limits(d).max
end

# Warm-start the tap at its current position so IPOPT begins inside the bounds.
function get_variable_warm_start_value(
    ::Type{TapRatioVariable},
    d::PSY.TwoWindingTransformer,
    ::Type{VoltageControlTap},
)
    return PSY.get_tap(d)
end

requires_initialization(::VoltageControlTap) = false

function get_default_attributes(
    ::Type{<:PSY.TwoWindingTransformer},
    ::Type{VoltageControlTap},
)
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
    )
end

function get_default_time_series_names(
    ::Type{<:PSY.TwoWindingTransformer},
    ::Type{VoltageControlTap},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

#################################################################################
# Variable-tap AC π-model Ohm's law constraints.
#
# The ACP/ACR variable-tap Ohm's law shares its π-model coefficients and constraint
# builders with the fixed-tap StaticBranch path in AC_branches.jl
# (`_tap_flow_coefficients`, `_add_tap_acp_flow!`, `_add_tap_acr_flow!`), passing
# `TapRatioVariable[name, t]` as the tap in place of the constant `tm`, so each constraint
# reduces to its StaticBranch counterpart when `t == tm`. IVR keeps its own form below.
#################################################################################

# ACP (polar) variable-tap Ohm's law.
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.TwoWindingTransformer}
    time_steps = get_time_steps(container)

    va = get_variable(container, VoltageAngle, PSY.ACBus)
    vm = get_variable(container, VoltageMagnitude, PSY.ACBus)
    tap = get_variable(container, TapRatioVariable, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, branch_names)
    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)

    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        coef = _tap_flow_coefficients(
            adm.g, adm.b, adm.g_fr, adm.b_fr, adm.g_to, adm.b_to, adm.shift,
        )
        for t in time_steps
            θ = va[from_bus, t] - va[to_bus, t]
            vmf = vm[from_bus, t]
            vmt = vm[to_bus, t]
            _add_tap_acp_flow!(
                jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
                name, t, vmf, vmt, θ, coef, tap[name, t],
                _slack_term(slacks.p_ft, name, t),
                _slack_term(slacks.q_ft, name, t),
                _slack_term(slacks.p_tf, name, t),
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

# ACR (rectangular) variable-tap Ohm's law.
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{ACRNetworkModel},
) where {T <: PSY.TwoWindingTransformer}
    time_steps = get_time_steps(container)

    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    tap = get_variable(container, TapRatioVariable, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, branch_names)
    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)

    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        coef = _tap_flow_coefficients(
            adm.g, adm.b, adm.g_fr, adm.b_fr, adm.g_to, adm.b_to, adm.shift,
        )
        for t in time_steps
            vr_fr = vr[from_bus, t]
            vr_to = vr[to_bus, t]
            vi_fr = vi[from_bus, t]
            vi_to = vi[to_bus, t]
            vv_fr = vr_fr^2 + vi_fr^2
            vv_to = vr_to^2 + vi_to^2
            cosprod = vr_fr * vr_to + vi_fr * vi_to
            sinprod = vi_fr * vr_to - vr_fr * vi_to
            _add_tap_acr_flow!(
                jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
                name, t, vv_fr, vv_to, cosprod, sinprod, coef, tap[name, t],
                _slack_term(slacks.p_ft, name, t),
                _slack_term(slacks.q_ft, name, t),
                _slack_term(slacks.p_tf, name, t),
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

# IVR (current-injection, rectangular) variable-tap Ohm's law.
#
# Mirrors the fixed-tap IVR branch constraints in AC_branches.jl term-by-term, with
# the constant tap `tm` (and the derived `tr = tm·cos(shift)`, `ti = tm·sin(shift)`,
# `tm² = tm^2`) replaced by the variable tap `t = TapRatioVariable[name, ts]`:
#   tr → t·cs,   ti → t·sn,   tm² → t²   (cs = cos(shift), sn = sin(shift)).
# The series impedance Z = r + jx is tap-independent (unchanged). Ten constraints
# per branch per time step (the same ten as the fixed-tap IVR branch). Because
# every `tm`-bearing term carries the live `t` symbol, each constraint reduces
# EXACTLY to its fixed-tap counterpart when `t == tap_nominal` (= PSY.get_tap(d) =
# adm.tap). The multiplied-through form (LHS·t²) keeps the equations polynomial
# (no division) and makes the reduction term-identical; t > 0 (TapRatioVariable
# bounds) guarantees equivalence with the divided form.
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.TwoWindingTransformer}
    time_steps = get_time_steps(container)

    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    tap = get_variable(container, TapRatioVariable, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)
    cr_fr = get_variable(container, BranchCurrentFromToReal, T)
    ci_fr = get_variable(container, BranchCurrentFromToImaginary, T)
    cr_to = get_variable(container, BranchCurrentToFromReal, T)
    ci_to = get_variable(container, BranchCurrentToFromImaginary, T)
    csr = get_variable(container, BranchSeriesCurrentReal, T)
    csi = get_variable(container, BranchSeriesCurrentImaginary, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]

    cons_pft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_ft",
    )
    cons_qft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_ft",
    )
    cons_ptf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_tf",
    )
    cons_qtf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_tf",
    )
    cons_cr_fr = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "cr_fr",
    )
    cons_ci_fr = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "ci_fr",
    )
    cons_cr_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "cr_to",
    )
    cons_ci_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "ci_to",
    )
    cons_vr_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "vr_to",
    )
    cons_vi_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "vi_to",
    )

    jump_model = get_jump_model(container)
    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        g = adm.g
        b = adm.b
        g_fr = adm.g_fr
        b_fr = adm.b_fr
        g_to = adm.g_to
        b_to = adm.b_to
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        cs = cos(adm.shift)
        sn = sin(adm.shift)

        # Series impedance Z = r + jx = conj(y)/|y|² (tap-independent).
        ymag2 = g^2 + b^2
        r = g / ymag2
        x = -b / ymag2

        for t in time_steps
            vr_f = vr[from_bus, t]
            vi_f = vi[from_bus, t]
            vr_t = vr[to_bus, t]
            vi_t = vi[to_bus, t]
            tt = tap[name, t]
            tt2 = tt^2
            tr = tt * cs
            ti = tt * sn
            csr_b = csr[name, t]
            csi_b = csi[name, t]
            cr_f = cr_fr[name, t]
            ci_f = ci_fr[name, t]
            cr_t = cr_to[name, t]
            ci_t = ci_to[name, t]

            # Bilinear power-current linking (tap-independent)
            cons_pft[name, t] = JuMP.@constraint(
                jump_model, pft[name, t] == vr_f * cr_f + vi_f * ci_f,
            )
            cons_qft[name, t] = JuMP.@constraint(
                jump_model, qft[name, t] == vi_f * cr_f - vr_f * ci_f,
            )
            cons_ptf[name, t] = JuMP.@constraint(
                jump_model, ptf[name, t] == vr_t * cr_t + vi_t * ci_t,
            )
            cons_qtf[name, t] = JuMP.@constraint(
                jump_model, qtf[name, t] == vi_t * cr_t - vr_t * ci_t,
            )

            # KCL at from terminal (tm → t)
            cons_cr_fr[name, t] = JuMP.@constraint(
                jump_model,
                cr_f * tt2 ==
                tr * csr_b - ti * csi_b + (g_fr * vr_f - b_fr * vi_f) * tt2,
            )
            cons_ci_fr[name, t] = JuMP.@constraint(
                jump_model,
                ci_f * tt2 ==
                tr * csi_b + ti * csr_b + (g_fr * vi_f + b_fr * vr_f) * tt2,
            )

            # KCL at to terminal (no tap)
            cons_cr_to[name, t] = JuMP.@constraint(
                jump_model, cr_t == -csr_b + g_to * vr_t - b_to * vi_t,
            )
            cons_ci_to[name, t] = JuMP.@constraint(
                jump_model, ci_t == -csi_b + g_to * vi_t + b_to * vr_t,
            )

            # Ohm's law across series impedance (tm → t)
            cons_vr_to[name, t] = JuMP.@constraint(
                jump_model,
                vr_t * tt2 ==
                vr_f * tr + vi_f * ti - r * csr_b * tt2 + x * csi_b * tt2,
            )
            cons_vi_to[name, t] = JuMP.@constraint(
                jump_model,
                vi_t * tt2 ==
                vi_f * tr - vr_f * ti - r * csi_b * tt2 - x * csr_b * tt2,
            )
        end
    end
    return
end

#################################################################################
# Control-objective application — count-invariant JuMP.fix on existing variables.
# Branch on the enum value (data, not type).
#################################################################################

# Shared handler for REACTIVE_POWER_FLOW and ACTIVE_POWER_FLOW objectives — identical
# between ACP and ACR. VOLTAGE regulation is handled per-network (ACP: direct vm fix;
# ACR/IVR: fix via RegulatedVoltageMagnitude aux variable).
function _fix_tap_flow_objective!(
    d::PSY.TwoWindingTransformer,
    name::String,
    qft,
    pft,
    objective,
    time_steps,
)
    if objective == PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
        target = PSY.get_reactive_power_flow(d, PSY.SU)
        for t in time_steps
            JuMP.fix(qft[name, t], target; force = true)
        end
    elseif objective == PSY.TransformerControlObjective.ACTIVE_POWER_FLOW
        target = PSY.get_active_power_flow(d, PSY.SU)
        for t in time_steps
            JuMP.fix(pft[name, t], target; force = true)
        end
    end
    return
end

# Resolve the regulated-bus name for a transformer: `regulated_bus_number == 0`
# means the arc's to-bus (local control).
function _tap_regulated_bus_name(d::PSY.TwoWindingTransformer, geom, number_to_name)
    reg = PSY.get_regulated_bus_number(d)
    if iszero(reg)
        return geom.to_name
    end
    if !haskey(number_to_name, reg)
        error(
            "TwoWindingTransformer $(PSY.get_name(d)) regulates bus number $(reg), which is \
             not a retained bus — it does not exist or was absorbed by a network \
             reduction. Fix the regulated_bus_number or exclude the bus from the \
             reduction with a PNM reduction filter.",
        )
    end
    return number_to_name[reg]
end

# Resolve the regulated ACBus for a transformer (used to bound and tie the ACR/IVR
# RegulatedVoltageMagnitude aux variable). `regulated_bus_number == 0` means the
# arc's to-bus (local control); otherwise the ACBus carrying that number.
function _tap_regulated_bus(d::PSY.TwoWindingTransformer, bus_by_number)
    reg = PSY.get_regulated_bus_number(d)
    if iszero(reg)
        return PSY.get_to(PSY.get_arc(d))
    end
    if !haskey(bus_by_number, reg)
        error(
            "TwoWindingTransformer $(PSY.get_name(d)) regulates bus number $(reg), which does \
             not exist in the system. Fix the regulated_bus_number.",
        )
    end
    return bus_by_number[reg]
end

_regulated_buses(d::PSY.TwoWindingTransformer, bus_by_number) =
    [("1", _tap_regulated_bus(d, bus_by_number))]

# Dispatch entry: the VOLTAGE objective is pinned differently depending on how the
# network expresses a regulated bus voltage magnitude (polar scalar vs rectangular aux).
function _apply_tap_control_objective!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    network_model::NetworkModel{N},
) where {T <: PSY.TwoWindingTransformer, N}
    return _apply_tap_control_objective!(
        regulated_voltage_form(N),
        container,
        sys,
        devices,
        network_model,
    )
end

# Polar (ACP): VOLTAGE pins the regulated-bus VoltageMagnitude directly;
# REACTIVE/ACTIVE_POWER_FLOW pin the from-to terminal flow. Other objectives
# (UNDEFINED / disabled) free-float.
function _apply_tap_control_objective!(
    ::PolarRegulatedVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    network_model::NetworkModel,
) where {T <: PSY.TwoWindingTransformer}
    time_steps = get_time_steps(container)
    vm = get_variable(container, VoltageMagnitude, PSY.ACBus)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    number_to_name = _retained_number_to_name(sys, network_model)
    # Control objectives act on the device's own terminals; the reduction guard in the
    # ArgumentConstructStage ensures every device here is a direct (un-aggregated) entry.
    for d in devices
        geom = _branch_geometry(d)
        name = geom.name
        objective = PSY.get_control_objective(d)
        if objective == PSY.TransformerControlObjective.VOLTAGE
            reg_name = _tap_regulated_bus_name(d, geom, number_to_name)
            setpoint = PSY.get_voltage_setpoint(d)
            for t in time_steps
                JuMP.fix(vm[reg_name, t], setpoint; force = true)
            end
        else
            _fix_tap_flow_objective!(d, name, qft, pft, objective, time_steps)
        end
    end
    return
end

# Rectangular (ACR/IVR): VOLTAGE pins the regulated-bus magnitude via the component-owned
# (component, "1") RegulatedVoltageMagnitude aux variable (see fix_regulated_voltage!);
# reactive/active-flow objectives pin the from-to terminal flow. The aux variable/
# constraint are added unconditionally in the construction stages, so only the fix is
# objective-conditional (count-invariance). Under IVR the from-to power variables
# (pft/qft) are bilinear-linked to the branch currents in the IVR Ohm's law, so the
# flow objectives are well-defined in current space — identical control logic to ACR.
function _apply_tap_control_objective!(
    ::RectangularRegulatedVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    network_model::NetworkModel,
) where {T <: PSY.TwoWindingTransformer}
    time_steps = get_time_steps(container)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    bus_by_number = _bus_by_number(sys)
    for d in devices
        name = PSY.get_name(d)
        objective = PSY.get_control_objective(d)
        if objective == PSY.TransformerControlObjective.VOLTAGE
            reg_bus = _tap_regulated_bus(d, bus_by_number)
            fix_regulated_voltage!(
                container, d, "1", reg_bus, PSY.get_voltage_setpoint(d), network_model,
            )
        else
            _fix_tap_flow_objective!(d, name, qft, pft, objective, time_steps)
        end
    end
    return
end

#################################################################################
# construct_device! — two-stage. ACP/ACR build the branch in power only;
# IVR adds explicit branch current variables and a CurrentLimitConstraint. The
# `tap_branch_current_form` trait selects between the two construction paths.
#################################################################################

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ArgumentConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{N},
) where {
    T <: PSY.TwoWindingTransformer,
    N <: Union{ACPNetworkModel, ACRNetworkModel, IVRNetworkModel},
}
    return construct_device!(
        tap_branch_current_form(N),
        container,
        sys,
        stage,
        device_model,
        network_model,
    )
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ModelConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{N},
) where {
    T <: PSY.TwoWindingTransformer,
    N <: Union{ACPNetworkModel, ACRNetworkModel, IVRNetworkModel},
}
    return construct_device!(
        tap_branch_current_form(N),
        container,
        sys,
        stage,
        device_model,
        network_model,
    )
end

# Power-only branch construction (ACP/ACR), mirrors StaticBranch.
function construct_device!(
    ::PowerOnlyTapBranch,
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel,
) where {T <: PSY.TwoWindingTransformer}
    @debug "construct_device VoltageControlTap (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _validate_controlled_branch_not_reduced(network_model, devices, "VoltageControlTap")
    add_variables!(container, TapRatioVariable, devices, VoltageControlTap)
    add_variables!(container, FlowActivePowerFromToVariable, devices, VoltageControlTap)
    add_variables!(container, FlowActivePowerToFromVariable, devices, VoltageControlTap)
    add_variables!(container, FlowReactivePowerFromToVariable, devices, VoltageControlTap)
    add_variables!(container, FlowReactivePowerToFromVariable, devices, VoltageControlTap)
    add_regulated_voltage_magnitude!(
        container, devices, sys, network_model,
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
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    ::PowerOnlyTapBranch,
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{N},
) where {T <: PSY.TwoWindingTransformer, N}
    @debug "construct_device VoltageControlTap (ModelConstructStage)" _group =
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
    add_regulated_voltage_magnitude_constraints!(
        container, devices, sys, network_model,
    )
    _apply_tap_control_objective!(container, sys, devices, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, N)
    add_constraint_dual!(container, sys, device_model)
    return
end

#################################################################################
# construct_device! — IVR (current-injection) variable-tap branch.
# Mirrors StaticBranch under IVRNetworkModel (branch_constructor.jl) plus the
# TapRatioVariable and the RegulatedVoltageMagnitude aux variable / constraint.
#################################################################################

function construct_device!(
    ::CurrentInjectionTapBranch,
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel,
) where {T <: PSY.TwoWindingTransformer}
    @debug "construct_device IVR VoltageControlTap (ArgumentConstructStage)" _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    devices = get_available_components(device_model, sys)
    _validate_controlled_branch_not_reduced(network_model, devices, "VoltageControlTap")
    add_variables!(container, TapRatioVariable, devices, VoltageControlTap)
    add_variables!(container, FlowActivePowerFromToVariable, devices, VoltageControlTap)
    add_variables!(container, FlowActivePowerToFromVariable, devices, VoltageControlTap)
    add_variables!(container, FlowReactivePowerFromToVariable, devices, VoltageControlTap)
    add_variables!(container, FlowReactivePowerToFromVariable, devices, VoltageControlTap)
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
    add_regulated_voltage_magnitude!(
        container, devices, sys, network_model,
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
    add_feedforward_arguments!(container, device_model, devices)
    return
end

function construct_device!(
    ::CurrentInjectionTapBranch,
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, VoltageControlTap},
    network_model::NetworkModel{N},
) where {T <: PSY.TwoWindingTransformer, N}
    @debug "construct_device IVR VoltageControlTap (ModelConstructStage)" _group =
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
    add_regulated_voltage_magnitude_constraints!(
        container, devices, sys, network_model,
    )
    _apply_tap_control_objective!(container, sys, devices, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, N)
    add_constraint_dual!(container, sys, device_model)
    return
end

# Defensive no-ops for active-power-only networks. template_validation drops the
# reactive VoltageControlTap formulation before construction, so these are only
# reached if template validation is bypassed.
function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{T, VoltageControlTap},
    ::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.TwoWindingTransformer}
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{T, VoltageControlTap},
    ::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.TwoWindingTransformer}
    return
end
