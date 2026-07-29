import PowerNetworkMatrices as PNM

@testset "native IVRNetworkModel builds and solves (c_sys5)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # --- IVR voltage-magnitude physics check ---
    # Same as ACR: rectangular voltage bounds enforce vmin² ≤ vr² + vi² ≤ vmax².
    res = IOM.OptimizationProblemOutputs(model)
    vr_sol = read_variable(res, "VoltageReal__ACBus"; table_format = TableFormat.WIDE)
    vi_sol = read_variable(res, "VoltageImaginary__ACBus"; table_format = TableFormat.WIDE)
    for bus in PSY.get_components(PSY.ACBus, sys)
        lim = PSY.get_voltage_limits(bus)
        bname = PSY.get_name(bus)
        vm2 = vr_sol[1, bname]^2 + vi_sol[1, bname]^2
        @test lim.min^2 - 1e-4 <= vm2 <= lim.max^2 + 1e-4
    end

    # --- IVR branch current bounds check ---
    # Every terminal current variable must stay within ±c_rating_a = rate_a / vmin.
    cr_fr_sol = read_variable(
        res, "BranchCurrentFromToReal__Line"; table_format = TableFormat.WIDE,
    )
    ci_fr_sol = read_variable(
        res, "BranchCurrentFromToImaginary__Line"; table_format = TableFormat.WIDE,
    )
    for line in PSY.get_components(PSY.Line, sys)
        arc = PSY.get_arc(line)
        rate_a = branch_rating_su(line)
        vmin = min(
            PSY.get_voltage_limits(PSY.get_from(arc)).min,
            PSY.get_voltage_limits(PSY.get_to(arc)).min,
        )
        c_rating = rate_a / vmin
        lname = PSY.get_name(line)
        @test abs(cr_fr_sol[1, lname]) <= c_rating + 1e-4
        @test abs(ci_fr_sol[1, lname]) <= c_rating + 1e-4
    end
end

@testset "IVRNetworkModel objective ≈ ACPNetworkModel objective (c_sys5)" begin
    # IVR and ACP are the same nonlinear AC optimal power flow (exact AC physics,
    # different variable space); on the same system they must converge to the same
    # optimal value.
    sys = PSB.build_system(PSITestSystems, "c_sys5")

    template_acp = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model_acp = DecisionModel(template_acp, sys; optimizer = ipopt_optimizer)
    @test build!(model_acp; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_acp) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    acp_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_acp))

    template_ivr = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    model_ivr = DecisionModel(template_ivr, sys; optimizer = ipopt_optimizer)
    @test build!(model_ivr; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_ivr) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    ivr_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_ivr))

    @test isapprox(ivr_obj, acp_obj; rtol = 1e-3)
end

@testset "IVR StaticBranch + use_slacks relaxes the current-magnitude limits" begin
    # StaticBranch relaxes cr²+ci² ≤ c_rating² to cr²+ci² − s_c ≤ c_rating² per terminal
    # with a one-sided current slack ("c_from"/"c_to"). The apparent-power quadratic keeps
    # its existing meta-less slack, and both current slacks are priced.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranch; use_slacks = true))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    c_from = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "c_from")
    c_to = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "c_to")
    con_from = IOM.get_constraint(container, CurrentLimitConstraint, PSY.Line, "from")
    con_to = IOM.get_constraint(container, CurrentLimitConstraint, PSY.Line, "to")
    objective = JuMP.objective_function(IOM.get_jump_model(container))
    time_steps = IOM.get_time_steps(container)

    # The apparent-power quadratic keeps its meta-less slack.
    @test !isempty(IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line))

    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        for t in time_steps
            # cr²+ci² − s_c ≤ c_rating² ⇒ residual coefficient −1 on the terminal's slack,
            # 0 on the other terminal's slack.
            @test slack_residual_coefficient(con_from[name, t], c_from[name, t]) == -1.0
            @test slack_residual_coefficient(con_from[name, t], c_to[name, t]) == 0.0
            @test slack_residual_coefficient(con_to[name, t], c_to[name, t]) == -1.0
            @test slack_residual_coefficient(con_to[name, t], c_from[name, t]) == 0.0

            # Both current slacks are priced.
            @test JuMP.coefficient(objective, c_from[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
            @test JuMP.coefficient(objective, c_to[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
        end
    end
end

@testset "IVR StaticBranchBounds + use_slacks relaxes the terminal current definitions" begin
    # StaticBranchBounds relaxes the four terminal current-definition equalities (cr_fr,
    # ci_fr, cr_to, ci_to) with independent metaed slack pairs, while the CurrentLimit
    # quadratic stays hard and the directional flow variables keep their ±rating box bounds.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    set_device_model!(
        template, DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
    qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
    qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.Line)
    up(meta) = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, meta)
    lo(meta) = IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line, meta)
    cons(meta) = IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line, meta)
    con_curr_from = IOM.get_constraint(container, CurrentLimitConstraint, PSY.Line, "from")
    con_curr_to = IOM.get_constraint(container, CurrentLimitConstraint, PSY.Line, "to")
    objective = JuMP.objective_function(IOM.get_jump_model(container))
    time_steps = IOM.get_time_steps(container)
    current_metas = ("cr_fr", "ci_fr", "cr_to", "ci_to")

    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = branch_rating_su(line)
        for t in time_steps
            # Directional flow variables keep hard ±rating box bounds.
            for var in (pft, ptf, qft, qtf)
                @test JuMP.has_upper_bound(var[name, t])
                @test JuMP.has_lower_bound(var[name, t])
                @test JuMP.upper_bound(var[name, t]) == rate
                @test JuMP.lower_bound(var[name, t]) == -rate
            end

            # Each terminal current definition `c == physics + s⁺ − s⁻` ⇒ residual
            # coefficient −1 on s⁺, +1 on s⁻ in its own row and 0 in the others.
            for meta in current_metas
                @test slack_residual_coefficient(cons(meta)[name, t], up(meta)[name, t]) ==
                      -1.0
                @test slack_residual_coefficient(cons(meta)[name, t], lo(meta)[name, t]) ==
                      1.0
                for other in current_metas
                    other == meta && continue
                    @test slack_residual_coefficient(
                        cons(meta)[name, t], up(other)[name, t],
                    ) == 0.0
                end
                # The current-magnitude limit stays hard: no slack column.
                @test slack_residual_coefficient(
                    con_curr_from[name, t],
                    up(meta)[name, t],
                ) ==
                      0.0
                @test slack_residual_coefficient(con_curr_to[name, t], up(meta)[name, t]) ==
                      0.0
                # All current slack columns are priced.
                @test JuMP.coefficient(objective, up(meta)[name, t]) ==
                      POM.CONSTRAINT_VIOLATION_SLACK_COST
                @test JuMP.coefficient(objective, lo(meta)[name, t]) ==
                      POM.CONSTRAINT_VIOLATION_SLACK_COST
            end
        end
    end
end

@testset "IVRNetworkModel objective ≈ ACPNetworkModel objective (c_sys14, non-unit taps)" begin
    # c_sys14 has TapTransformers with tap ratios ~0.93–0.98, exercising the /tm²
    # shunt path. IVR and ACP must converge to the same optimal value.
    sys = PSB.build_system(PSITestSystems, "c_sys14")

    template_acp = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model_acp = DecisionModel(template_acp, sys; optimizer = ipopt_optimizer)
    @test build!(model_acp; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_acp) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    acp_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_acp))

    template_ivr = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    model_ivr = DecisionModel(template_ivr, sys; optimizer = ipopt_optimizer)
    @test build!(model_ivr; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_ivr) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    ivr_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_ivr))

    @test isapprox(ivr_obj, acp_obj; rtol = 1e-3)
end

@testset "IVR StaticBranch + use_slacks relaxes the apparent-power quadratic at the optimum" begin
    # Reliably binding the IVR current-magnitude limit on c_sys5 is numerically brittle: any
    # rating cut tight enough to force a current slack drives Ipopt to a locally-infeasible
    # point, while looser cuts leave every current slack at zero. So this exercises the
    # flow-layer instead (the sanctioned fallback): cutting line "1" to 0.98 pu binds the
    # apparent-power FlowRateConstraint, activating its meta-less squared-domain slack while
    # the current-limit slacks stay ≈ 0 and the solve finalizes.
    # Ipopt converges for cuts in ~[0.97, 0.99] on this fixture; 0.95 is locally
    # infeasible. If an Ipopt_jll bump breaks this solve, widen the cut toward 0.99.
    cut = 0.98
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    PSY.set_rating!(PSY.get_component(PSY.Line, sys, "1"), cut * PSY.SU)
    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranch; use_slacks = true))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    flow_quadratic_slack =
        IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line)
    current_slack_from =
        IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "c_from")
    current_slack_to =
        IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "c_to")

    @test maximum(JuMP.value.(flow_quadratic_slack)) > 1e-6
    @test maximum(JuMP.value.(current_slack_from)) <= 1e-4
    @test maximum(JuMP.value.(current_slack_to)) <= 1e-4
end

@testset "IVR StaticBranchBounds + use_slacks solves with the current-definition relaxation available" begin
    # SBB on IVR relaxes both the four terminal current-definition equalities (metas
    # cr_fr/ci_fr/cr_to/ci_to) and the four per-direction flow-definition equalities
    # (p_ft/p_tf/q_ft/q_tf). Cutting line "1" to 0.5 pu makes its ±rating box too tight for
    # any voltage/current profile, so the model is feasible only by relaxing. Both slack
    # layers relax genuine equalities and are priced identically, so the optimizer distributes
    # the required relaxation across them — no single layer is guaranteed zero. This confirms
    # the relaxed model still solves, some slack is genuinely active, and the directional flow
    # variables keep their hard ±rating box bounds.
    cut = 0.5
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    PSY.set_rating!(PSY.get_component(PSY.Line, sys, "1"), cut * PSY.SU)
    template = get_thermal_dispatch_template_network(NetworkModel(IVRNetworkModel))
    set_device_model!(
        template, DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    # The relaxation is genuinely exercised: across the current-definition and per-direction
    # flow-definition slack layers, some slack is active (the over-tight box is otherwise
    # infeasible).
    total_slack = 0.0
    for meta in ("cr_fr", "ci_fr", "cr_to", "ci_to", "p_ft", "p_tf", "q_ft", "q_tf")
        for V in (FlowActivePowerSlackUpperBound, FlowActivePowerSlackLowerBound)
            total_slack +=
                sum(
                    max(JuMP.value(s), 0.0) for
                    s in IOM.get_variable(container, V, PSY.Line, meta)
                )
        end
    end
    @test total_slack > 1e-4

    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = branch_rating_su(line)
        for t in IOM.get_time_steps(container)
            @test abs(JuMP.value(pft[name, t])) <= rate + 1e-6
        end
    end
end
