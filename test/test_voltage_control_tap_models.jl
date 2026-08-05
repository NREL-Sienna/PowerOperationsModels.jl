@testset "VoltageControlTap tap bounds are finite (Principle 0)" begin
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    for tr in PSY.get_components(PSY.TwoWindingTransformer, sys)
#        lim = POM._tap_ratio_limits(tr)
#        @test isfinite(lim.min)
#        @test isfinite(lim.max)
#        @test lim.min > 0.0
#        @test lim.max >= lim.min
#    end
end

@testset "VoltageControlTap VOLTAGE objective pins regulated bus voltage (c_sys14)" begin
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    # Regulate the to-bus of Trans1 (Bus 9) to 1.0 pu via a local (regbus 0) tap.
#    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#    PSY.set_control_objective!(tr, PSY.TransformerControlObjective.VOLTAGE)
#    PSY.set_regulated_bus_number!(tr, 0)
#    PSY.set_voltage_setpoint!(tr, 1.0)
#    regulated_bus = PSY.get_name(PSY.get_to(PSY.get_arc(tr)))
#    setpoint = PSY.get_voltage_setpoint(tr)
#
#    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#    res = IOM.OptimizationProblemOutputs(model)
#    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
#    @test regulated_bus in names(vm)
#    for r in 1:nrow(vm)
#        @test isapprox(vm[r, regulated_bus], setpoint; atol = 1e-6)
#    end
#
#    # The tap floats within its bounds to hold the setpoint.
#    @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
end

@testset "VoltageControlTap is count-invariant across control objectives (c_sys14)" begin
#    function _container_for_objective(objective)
#        sys = PSB.build_system(PSITestSystems, "c_sys14")
#        tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#        PSY.set_control_objective!(tr, objective)
#        PSY.set_regulated_bus_number!(tr, 0)
#        PSY.set_voltage_setpoint!(tr, 1.0)
#        template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
#        set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#              IOM.ModelBuildStatus.BUILT
#        return IOM.get_optimization_container(model)
#    end
#
#    cv = _container_for_objective(PSY.TransformerControlObjective.VOLTAGE)
#    cq = _container_for_objective(PSY.TransformerControlObjective.REACTIVE_POWER_FLOW)
#
#    var_v = IOM.get_variables(cv)
#    var_q = IOM.get_variables(cq)
#    @test Set(keys(var_v)) == Set(keys(var_q))
#    for k in keys(var_v)
#        @test size(var_v[k]) == size(var_q[k])
#    end
#
#    con_v = IOM.get_constraints(cv)
#    con_q = IOM.get_constraints(cq)
#    @test Set(keys(con_v)) == Set(keys(con_q))
#    for k in keys(con_v)
#        @test size(con_v[k]) == size(con_q[k])
#    end
end

@testset "VoltageControlTap VOLTAGE objective pins regulated bus (ACR, c_sys14)" begin
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#    PSY.set_control_objective!(tr, PSY.TransformerControlObjective.VOLTAGE)
#    PSY.set_regulated_bus_number!(tr, 0)
#    PSY.set_voltage_setpoint!(tr, 1.0)
#    regulated_bus = PSY.get_name(PSY.get_to(PSY.get_arc(tr)))
#    setpoint = PSY.get_voltage_setpoint(tr)
#
#    template = get_thermal_dispatch_template_network(NetworkModel(ACRNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#    res = IOM.OptimizationProblemOutputs(model)
#    vr = read_variable(res, "VoltageReal__ACBus"; table_format = TableFormat.WIDE)
#    vi = read_variable(res, "VoltageImaginary__ACBus"; table_format = TableFormat.WIDE)
#    @test regulated_bus in names(vr)
#    for r in 1:nrow(vr)
#        mag = sqrt(vr[r, regulated_bus]^2 + vi[r, regulated_bus]^2)
#        @test isapprox(mag, setpoint; atol = 1e-4)
#    end
#
#    @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
end

@testset "VoltageControlTap is count-invariant across control objectives (ACR, c_sys14)" begin
#    function _acr_container_for_objective(objective)
#        sys = PSB.build_system(PSITestSystems, "c_sys14")
#        tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#        PSY.set_control_objective!(tr, objective)
#        PSY.set_regulated_bus_number!(tr, 0)
#        PSY.set_voltage_setpoint!(tr, 1.0)
#        template = get_thermal_dispatch_template_network(NetworkModel(ACRNetworkModel))
#        set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#              IOM.ModelBuildStatus.BUILT
#        return IOM.get_optimization_container(model)
#    end
#
#    cv = _acr_container_for_objective(PSY.TransformerControlObjective.VOLTAGE)
#    cq = _acr_container_for_objective(PSY.TransformerControlObjective.REACTIVE_POWER_FLOW)
#
#    var_v = IOM.get_variables(cv)
#    var_q = IOM.get_variables(cq)
#    @test any(k -> occursin("RegulatedVoltageMagnitude", string(k)), keys(var_v))
#    @test Set(keys(var_v)) == Set(keys(var_q))
#    for k in keys(var_v)
#        @test size(var_v[k]) == size(var_q[k])
#    end
#
#    con_v = IOM.get_constraints(cv)
#    con_q = IOM.get_constraints(cq)
#    @test any(k -> occursin("RegulatedVoltageMagnitudeConstraint", string(k)), keys(con_v))
#    @test Set(keys(con_v)) == Set(keys(con_q))
#    for k in keys(con_v)
#        @test size(con_v[k]) == size(con_q[k])
#    end
end

@testset "VoltageControlTap VOLTAGE objective pins regulated bus (IVR, c_sys14)" begin
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#    PSY.set_control_objective!(tr, PSY.TransformerControlObjective.VOLTAGE)
#    PSY.set_regulated_bus_number!(tr, 0)
#    PSY.set_voltage_setpoint!(tr, 1.0)
#    regulated_bus = PSY.get_name(PSY.get_to(PSY.get_arc(tr)))
#    setpoint = PSY.get_voltage_setpoint(tr)
#
#    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#    res = IOM.OptimizationProblemOutputs(model)
#    vr = read_variable(res, "VoltageReal__ACBus"; table_format = TableFormat.WIDE)
#    vi = read_variable(res, "VoltageImaginary__ACBus"; table_format = TableFormat.WIDE)
#    @test regulated_bus in names(vr)
#    for r in 1:nrow(vr)
#        mag = sqrt(vr[r, regulated_bus]^2 + vi[r, regulated_bus]^2)
#        @test isapprox(mag, setpoint; atol = 1e-4)
#    end
#
#    @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
end

@testset "VoltageControlTap IVR currents reduce to fixed-tap at t==tap_nominal" begin
#    # White-box reduction gate: with the tap variable pinned at its nominal value
#    # (PSY.get_tap), the variable-tap IVR Ohm's law is term-by-term identical to the
#    # fixed-tap (StaticBranch) IVR branch, so the two models must converge to the same
#    # optimum and the same physical (gauge-invariant) terminal power flows.
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#
#    template_fixed = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
#    model_fixed = DecisionModel(template_fixed, sys; optimizer = ipopt_optimizer)
#    @test build!(model_fixed; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#    @test solve!(model_fixed) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#    template_var = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
#    set_device_model!(template_var, PSY.TwoWindingTransformer, VoltageControlTap)
#    model_var = DecisionModel(template_var, sys; optimizer = ipopt_optimizer)
#    @test build!(model_var; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#
#    # Pin every tap variable at its nominal ratio before solving.
#    container = IOM.get_optimization_container(model_var)
#    tapvar = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
#    for d in PSY.get_components(PSY.TwoWindingTransformer, sys)
#        name = PSY.get_name(d)
#        for t in axes(tapvar, 2)
#            JuMP.fix(tapvar[name, t], PSY.get_tap(d); force = true)
#        end
#    end
#    @test solve!(model_var) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#    obj_fixed = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_fixed))
#    obj_var = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_var))
#    @test isapprox(obj_var, obj_fixed; rtol = 1e-3)
#
#    # Compare physical terminal flows on the TwoWindingTransformers (reference-invariant).
#    res_fixed = IOM.OptimizationProblemOutputs(model_fixed)
#    res_var = IOM.OptimizationProblemOutputs(model_var)
#    pft_fixed = read_variable(
#        res_fixed, "FlowActivePowerFromToVariable__TwoWindingTransformer";
#        table_format = TableFormat.WIDE,
#    )
#    pft_var = read_variable(
#        res_var, "FlowActivePowerFromToVariable__TwoWindingTransformer";
#        table_format = TableFormat.WIDE,
#    )
#    qft_fixed = read_variable(
#        res_fixed, "FlowReactivePowerFromToVariable__TwoWindingTransformer";
#        table_format = TableFormat.WIDE,
#    )
#    qft_var = read_variable(
#        res_var, "FlowReactivePowerFromToVariable__TwoWindingTransformer";
#        table_format = TableFormat.WIDE,
#    )
#    for d in PSY.get_components(PSY.TwoWindingTransformer, sys)
#        name = PSY.get_name(d)
#        @test isapprox(pft_var[1, name], pft_fixed[1, name]; atol = 1e-3)
#        @test isapprox(qft_var[1, name], qft_fixed[1, name]; atol = 1e-3)
#    end
end

@testset "VoltageControlTap is count-invariant across control objectives (IVR, c_sys14)" begin
#    function _ivr_container_for_objective(objective)
#        sys = PSB.build_system(PSITestSystems, "c_sys14")
#        tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
#        PSY.set_control_objective!(tr, objective)
#        PSY.set_regulated_bus_number!(tr, 0)
#        PSY.set_voltage_setpoint!(tr, 1.0)
#        template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
#        set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#              IOM.ModelBuildStatus.BUILT
#        return IOM.get_optimization_container(model)
#    end
#
#    cv = _ivr_container_for_objective(PSY.TransformerControlObjective.VOLTAGE)
#    cq = _ivr_container_for_objective(PSY.TransformerControlObjective.REACTIVE_POWER_FLOW)
#    cp = _ivr_container_for_objective(PSY.TransformerControlObjective.ACTIVE_POWER_FLOW)
#
#    var_v = IOM.get_variables(cv)
#    var_q = IOM.get_variables(cq)
#    var_p = IOM.get_variables(cp)
#    @test any(k -> occursin("RegulatedVoltageMagnitude", string(k)), keys(var_v))
#    @test Set(keys(var_v)) == Set(keys(var_q)) == Set(keys(var_p))
#    for k in keys(var_v)
#        @test size(var_v[k]) == size(var_q[k]) == size(var_p[k])
#    end
#
#    con_v = IOM.get_constraints(cv)
#    con_q = IOM.get_constraints(cq)
#    con_p = IOM.get_constraints(cp)
#    @test any(k -> occursin("RegulatedVoltageMagnitudeConstraint", string(k)), keys(con_v))
#    @test Set(keys(con_v)) == Set(keys(con_q)) == Set(keys(con_p))
#    for k in keys(con_v)
#        @test size(con_v[k]) == size(con_q[k]) == size(con_p[k])
#    end
end

@testset "VoltageControlTap @info-drop under DCPNetworkModel (c_sys14)" begin
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#
#    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
#    # The voltage-controlling tap formulation is reactive-only, so it is dropped
#    # with an @info from the (active-power-only) DC template during validation.
#    # A TwoWindingTransformer is a branch the DC network still requires to be modeled, so
#    # the build then fails on the now-unmodeled branch (unlike a droppable shunt
#    # injection). Both facts are asserted: the drop happened, and the build failed.
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.FAILED
#    @test !haskey(get_branch_models(get_template(model)), :TwoWindingTransformer)
end

@testset "ACP rejects two voltage regulators on one bus" begin
#    # Two TwoWindingTransformers both set to VOLTAGE control regulating bus 9. Under ACP each
#    # pins the shared network VoltageMagnitude via JuMP.fix(force=true), so the second
#    # silently overrides the first. validate_template! must reject this. (build!
#    # swallows the throw into FAILED, so assert against validate_template directly.)
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    for nm in ("Trans1", "Trans2")
#        tr = PSY.get_component(PSY.TwoWindingTransformer, sys, nm)
#        PSY.set_control_objective!(tr, PSY.TransformerControlObjective.VOLTAGE)
#        PSY.set_regulated_bus_number!(tr, 9)
#        PSY.set_voltage_setpoint!(tr, 1.0)
#    end
#    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test_throws IS.ConflictingInputsError POM.validate_template(model)
end

@testset "ACR does not validation-reject two regulators on one bus" begin
#    # Under ACR each regulator owns a (component, tag) RegulatedVoltageMagnitude aux
#    # variable tied by vm_reg^2 == vr^2 + vi^2, so the conflict is solver-infeasibility,
#    # not a validation error. validate_template must NOT throw.
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    for nm in ("Trans1", "Trans2")
#        tr = PSY.get_component(PSY.TwoWindingTransformer, sys, nm)
#        PSY.set_control_objective!(tr, PSY.TransformerControlObjective.VOLTAGE)
#        PSY.set_regulated_bus_number!(tr, 9)
#        PSY.set_voltage_setpoint!(tr, 1.0)
#    end
#    template = get_thermal_dispatch_template_network(NetworkModel(ACRNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test POM.validate_template(model) === nothing
end

@testset "_tap_flow_coefficients ground truth (hand-computed)" begin
#    # No shift: cs=1, sn=0. Hand-computed shunt sums and coupling coefficients.
#    c0 = POM._tap_flow_coefficients(1.0, -2.0, 0.1, 0.3, 0.2, 0.4, 0.0)
#    @test c0.cs == 1.0
#    @test c0.sn == 0.0
#    @test c0.gg_fr == 1.1
#    @test c0.bb_fr == -1.7
#    @test c0.gg_to == 1.2
#    @test c0.bb_to == -1.6
#    @test c0.a_cos == -1.0   # -g*cs + b*sn
#    @test c0.a_sin == 2.0    # -b*cs - g*sn
#    @test c0.c_cos == -1.0   # -g*cs - b*sn
#    @test c0.d_sin == -2.0   # b*cs - g*sn
#
#    # Nonzero shift = π/6: cs=√3/2, sn=1/2 exercises the trig.
#    cs = cos(pi / 6)
#    sn = sin(pi / 6)
#    cS = POM._tap_flow_coefficients(1.0, -2.0, 0.1, 0.3, 0.2, 0.4, pi / 6)
#    @test cS.cs ≈ cs
#    @test cS.sn ≈ sn
#    @test cS.gg_fr == 1.1
#    @test cS.bb_fr == -1.7
#    @test cS.gg_to == 1.2
#    @test cS.bb_to == -1.6
#    @test cS.a_cos ≈ -1.0 * cs + (-2.0) * sn
#    @test cS.a_sin ≈ -(-2.0) * cs - 1.0 * sn
#    @test cS.c_cos ≈ -1.0 * cs - (-2.0) * sn
#    @test cS.d_sin ≈ (-2.0) * cs - 1.0 * sn
#    # ACR's e_sin sign relationship the constraint body relies on.
#    @test -cS.d_sin ≈ -(-2.0) * cs + 1.0 * sn
end

@testset "ACR NetworkFlowConstraint coefficients equal _tap_flow_coefficients" begin
#    # Ground-truth: the built ACR to-from flow constraint (ptf/qtf) must use exactly the
#    # pure-function coefficients. Evaluate constraint_object(con).func at chosen variable
#    # values and compare to the hand RHS assembled from _tap_flow_coefficients.
#    sys = PSB.build_system(PSITestSystems, "c_sys14")
#    template = get_thermal_dispatch_template_network(NetworkModel(ACRNetworkModel))
#    set_device_model!(template, PSY.TwoWindingTransformer, VoltageControlTap)
#    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          IOM.ModelBuildStatus.BUILT
#
#    container = IOM.get_optimization_container(model)
#    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.TwoWindingTransformer)
#    qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.TwoWindingTransformer)
#    vr = IOM.get_variable(container, VoltageReal, PSY.ACBus)
#    vi = IOM.get_variable(container, VoltageImaginary, PSY.ACBus)
#    tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
#    con_ptf =
#        IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.TwoWindingTransformer, "p_tf")
#    con_qft =
#        IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.TwoWindingTransformer, "q_ft")
#
#    t = 1
#    for d in Iterators.take(PSY.get_components(PSY.TwoWindingTransformer, sys), 3)
#        name = PSY.get_name(d)
#        geom = POM._branch_geometry(d)
#        adm = geom.adm
#        coef = POM._tap_flow_coefficients(
#            adm.g, adm.b, adm.g_fr, adm.b_fr, adm.g_to, adm.b_to, adm.shift,
#        )
#        e_sin = -coef.d_sin
#        fr = geom.from_name
#        to = geom.to_name
#
#        # Arbitrary evaluation point for the (nonlinear) constraint functions.
#        vals = Dict{JuMP.VariableRef, Float64}(
#            vr[fr, t] => 1.02, vi[fr, t] => 0.05,
#            vr[to, t] => 0.98, vi[to, t] => -0.03,
#            tap[name, t] => 1.05,
#            ptf[name, t] => 0.7, qft[name, t] => -0.2,
#        )
#        lookup = z -> vals[z]
#
#        vv_to = vals[vr[to, t]]^2 + vals[vi[to, t]]^2
#        cosprod = vals[vr[fr, t]] * vals[vr[to, t]] + vals[vi[fr, t]] * vals[vi[to, t]]
#        sinprod = vals[vi[fr, t]] * vals[vr[to, t]] - vals[vr[fr, t]] * vals[vi[to, t]]
#        tt = vals[tap[name, t]]
#
#        # func is stored as (lhs - rhs); assert it matches the hand-assembled (lhs - rhs).
#        rhs_ptf =
#            coef.gg_to * vv_to + coef.c_cos / tt * cosprod + e_sin / tt * (-sinprod)
#        want_ptf = vals[ptf[name, t]] - rhs_ptf
#        got_ptf = JuMP.value(lookup, JuMP.constraint_object(con_ptf[name, t]).func)
#        @test isapprox(got_ptf, want_ptf; atol = 1e-10)
#
#        vv_fr = vals[vr[fr, t]]^2 + vals[vi[fr, t]]^2
#        rhs_qft =
#            -coef.bb_fr / tt^2 * vv_fr + (-coef.a_sin) / tt * cosprod +
#            coef.a_cos / tt * sinprod
#        want_qft = vals[qft[name, t]] - rhs_qft
#        got_qft = JuMP.value(lookup, JuMP.constraint_object(con_qft[name, t]).func)
#        @test isapprox(got_qft, want_qft; atol = 1e-10)
#    end
end
