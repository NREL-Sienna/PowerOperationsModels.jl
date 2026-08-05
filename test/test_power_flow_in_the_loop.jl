@testset "AC Power Flow in the loop with headroom-proportional slack" begin
#    system = build_system(PSITestSystems, "c_sys5_uc")
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(
#                ACPowerFlow(;
#                    distribute_slack_proportional_to_headroom = true,
#                    correct_bustypes = true,
#                ),
#            ),
#        ),
#    )
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    pf_e_data = only(values(get_evaluation_data(get_evaluations(container))))
#    data = get_inner_data(pf_e_data)
#
#    computed_gspf = PFS.get_computed_gspf(data)
#    n_time_steps = length(get_time_steps(container))
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    # Headroom factors should be populated for every time step
#    @test length(computed_gspf) == n_time_steps
#    @test all(!isempty(d) for d in computed_gspf)
#    @test all(all(v > 0.0 for v in values(d)) for d in computed_gspf)
#
#    # bus_active_power_range should equal the sum of generator headroom per bus per time step
#    for t in 1:n_time_steps
#        bus_headroom_check = zeros(size(data.bus_active_power_range, 1))
#        for ((comp_type, comp_name), headroom) in computed_gspf[t]
#            comp = get_component(comp_type, system, comp_name)
#            bus_number = get_number(get_bus(comp))
#            bus_ix = bus_lookup[bus_number]
#            bus_headroom_check[bus_ix] += headroom
#        end
#        @test isapprox(
#            data.bus_active_power_range[:, t],
#            bus_headroom_check;
#            atol = 1e-10,
#        )
#    end
#
#    # bus_slack_participation_factors should match bus_active_power_range at participating buses
#    bus_slack_pf = PFS.get_bus_slack_participation_factors(data)
#    for t in 1:n_time_steps
#        for bus_ix in axes(data.bus_active_power_range, 1)
#            R_k = data.bus_active_power_range[bus_ix, t]
#            if R_k > 0.0
#                @test bus_slack_pf[bus_ix, t] == R_k
#            end
#        end
#    end
#
#    # Independently recompute expected headroom from optimization results and system
#    # limits, then verify it matches computed_gspf exactly. NOTE: c_sys5_uc thermals
#    # have fixed active power limits (no ActivePowerTimeSeriesParameter), so this
#    # exercises the static P_max path. The time-varying P_max path is exercised in
#    # the third testset below.
#    for t in 1:n_time_steps
#        for ((comp_type, comp_name), headroom) in computed_gspf[t]
#            comp = get_component(comp_type, system, comp_name)
#            p_max_sys = PFS.get_active_power_limits_for_power_flow(comp).max
#
#            var_key = VariableKey(ActivePowerVariable, comp_type)
#            result_data = lookup_value(container, var_key)
#            p_setpoint = JuMP.value(result_data[comp_name, t])
#
#            expected_headroom = p_max_sys - p_setpoint
#            @test expected_headroom > 0.0
#            @test isapprox(headroom, expected_headroom; atol = 1e-10)
#        end
#    end
end

@testset "Headroom proportional slack excludes FixedOutput generators" begin
#    # c_sys5_uc_re has renewables at PV/REF buses, so they would normally participate
#    # in headroom slack. Setting them to FixedOutput should exclude them.
#    system = build_system(PSITestSystems, "c_sys5_uc_re")
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            use_slacks = true,
#            evaluations = power_flow_evaluations(
#                ACPowerFlow(;
#                    distribute_slack_proportional_to_headroom = true,
#                    correct_bustypes = true,
#                ),
#            ),
#        ),
#    )
#    set_device_model!(template, RenewableDispatch, FixedOutput)
#
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    pf_e_data = only(values(get_evaluation_data(get_evaluations(container))))
#    data = get_inner_data(pf_e_data)
#    computed_gspf = PFS.get_computed_gspf(data)
#
#    # The renewable is at a PV bus but uses FixedOutput, so it must not appear in the
#    # headroom factors — only ThermalStandard generators should participate.
#    for t in 1:length(get_time_steps(container))
#        for ((comp_type, _), _) in computed_gspf[t]
#            @test comp_type <: ThermalStandard
#        end
#    end
end

@testset "Headroom proportional slack with time-varying active power limits" begin
#    # c_sys5_uc_re has renewables at PV/REF buses with time series data.
#    system = build_system(PSITestSystems, "c_sys5_uc_re")
#    re_gen = first(get_components(RenewableDispatch, system))
#    re_name = get_name(re_gen)
#    # Force device_base != system_base so the unit-handling path is exercised. If
#    # headroom ever silently re-introduces a `* device_base / system_base` factor,
#    # the recomputed expected_headroom below will mismatch by 0.5×, failing the
#    # assertion.
#    PSY.set_base_power!(re_gen, get_base_power(re_gen, PSY.NU) / 2)
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            use_slacks = true,
#            evaluations = power_flow_evaluations(
#                ACPowerFlow(;
#                    distribute_slack_proportional_to_headroom = true,
#                    correct_bustypes = true,
#                ),
#            ),
#        ),
#    )
#    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
#
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    pf_e_data = only(values(get_evaluation_data(get_evaluations(container))))
#    data = get_inner_data(pf_e_data)
#    computed_gspf = PFS.get_computed_gspf(data)
#    n_time_steps = length(get_time_steps(container))
#
#    # Verify the renewable's headroom uses min(static_limit, ts_param) at each time step
#    re_type = typeof(re_gen)
#    p_max_static = PFS.get_active_power_limits_for_power_flow(re_gen).max
#
#    var_key = VariableKey(ActivePowerVariable, re_type)
#    var_values = lookup_value(container, var_key)
#    ts_key = ParameterKey(ActivePowerTimeSeriesParameter, re_type)
#    ts_values = lookup_value(container, ts_key)
#
#    for t in 1:n_time_steps
#        p_setpoint = JuMP.value(var_values[re_name, t])
#        p_max_ts = ts_values[re_name, t]
#        p_max_t = min(p_max_static, p_max_ts)
#        expected_headroom = p_max_t - p_setpoint
#
#        entry = get(computed_gspf[t], (re_type, re_name), nothing)
#        if expected_headroom > 0.0
#            @test entry !== nothing
#            @test isapprox(entry, expected_headroom; atol = 1e-10)
#        else
#            @test entry === nothing
#        end
#    end
#
#    # The time series should cause P_max to vary, producing different headroom across steps
#    re_ts_vals = [ts_values[re_name, t] for t in 1:n_time_steps]
#    @test !all(isapprox.(re_ts_vals, re_ts_vals[1]; atol = 1e-10))
end

# -----------------------------------------------------------------------------
# Baseline PFitL coverage (ported from PowerSimulations.jl test file lines 1-548).
# These exercise the regular non-headroom paths through the migrated code:
#   - PhaseShiftingTransformer in PFitL
#   - Parallel-line aggregation
#   - Breaker-switch (DiscreteControlledACBranch)
#   - HVDCs with DC PowerFlow
#   - Line active power loss aux variable
# -----------------------------------------------------------------------------

@testset "AC Power Flow in the loop for PhaseShiftingTransformer" begin
#    system = build_system(PSITestSystems, "c_sys5_uc")
#
#    line = get_component(Line, system, "1")
#    arc = get_arc(line)
#
#    ps = PhaseShiftingTransformer(;
#        name = get_name(line),
#        available = true,
#        active_power_flow = 0.0,
#        reactive_power_flow = 0.0,
#        r = get_r(line, PSY.SU),
#        x = get_x(line, PSY.SU),
#        primary_shunt = 0.0,
#        tap = 1.0,
#        α = 0.0,
#        rating = get_rating(line, PSY.SU),
#        arc = arc,
#        base_power = get_base_power(system, PSY.NU),
#    )
#    add_component!(system, ps)
#    remove_component!(system, line)
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    set_device_model!(template, DeviceModel(PhaseShiftingTransformer, PhaseAngleControl))
#    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model_m)
#    pf_e_data = only(values(get_evaluation_data(get_evaluations(container))))
#    data = get_inner_data(pf_e_data)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    flow_key = VariableKey(FlowActivePowerVariable, PhaseShiftingTransformer)
#    flow_values = lookup_value(container, flow_key)
#    line_name = get_name(line)
#    line_flows =
#        [JuMP.value(flow_values[line_name, t]) for t in 1:length(get_time_steps(container))]
#
#    # The PhaseShiftingTransformer flow contributes to the "to"-bus active power injection.
#    # Both sides are in per-unit; lookup_value returns raw JuMP values in the model unit
#    # system rather than the natural-unit conversion that `read_variables(...; WIDE)`
#    # performs in PSI.
#    @test isapprox(
#        data.bus_active_power_injections[bus_lookup[get_number(get_to(arc))], :],
#        line_flows;
#        atol = 1e-9,
#        rtol = 0,
#    )
end

@testset "AC Power Flow in the loop with parallel lines" begin
#    original_line_flow, parallel_line_flow = zero(ComplexF64), zero(ComplexF64)
#    for replace_line in (true, false)
#        system = build_system(PSITestSystems, "c_sys5_uc")
#        line = get_component(Line, system, "1")
#        if replace_line
#            original_impedance = get_r(line, PSY.SU) + im * get_x(line, PSY.SU)
#            original_shunt = get_b(line, PSY.SU)
#            split_impedance = original_impedance * 2
#            split_shunt = (from = 0.5 * original_shunt.from, to = 0.5 * original_shunt.to)
#            for i in 1:2
#                l = Line(;
#                    name = get_name(line) * "_$i",
#                    available = true,
#                    active_power_flow = 0.0,
#                    reactive_power_flow = 0.0,
#                    arc = get_arc(line),
#                    r = real(split_impedance),
#                    x = imag(split_impedance),
#                    b = split_shunt,
#                    angle_limits = get_angle_limits(line),
#                    rating = get_rating(line, PSY.SU),
#                )
#                add_component!(system, l)
#            end
#            remove_component!(system, line)
#        end
#
#        template = get_template_dispatch_with_network(
#            NetworkModel(
#                PTDFNetworkModel;
#                network_matrix = PTDF(system),
#                evaluations = power_flow_evaluations(ACPowerFlow()),
#            ),
#        )
#        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#              ModelBuildStatus.BUILT
#        @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
#
#        container = get_optimization_container(model_m)
#        ft_key = AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, Line)
#        rt_key = AuxVarKey(POM.PowerFlowBranchReactivePowerFromTo, Line)
#        active_ft = lookup_value(container, ft_key)
#        reactive_ft = lookup_value(container, rt_key)
#
#        name = replace_line ? "$(get_name(line))_1" : get_name(line)
#        flow = active_ft[name, 1] + im * reactive_ft[name, 1]
#        if replace_line
#            parallel_line_flow = flow
#        else
#            original_line_flow = flow
#        end
#    end
#
#    # Two parallel lines with double the impedance each should each carry half of the
#    # original line's flow.
#    @test isapprox(2 * parallel_line_flow, original_line_flow; atol = 1e-3)
end

@testset "AC Power Flow in the loop with a breaker-switch" begin
#    system = build_system(PSITestSystems, "c_sys5_uc")
#    line = get_component(Line, system, "2")
#    bs = PSY.DiscreteControlledACBranch(;
#        name = get_name(line),
#        available = true,
#        active_power_flow = 0.0,
#        reactive_power_flow = 0.0,
#        arc = get_arc(line),
#        r = 0.0,
#        x = 0.0,
#        rating = get_rating(line, PSY.SU),
#        discrete_branch_type = PSY.DiscreteControlledBranchType.BREAKER,
#        branch_status = PSY.DiscreteControlledBranchStatus.CLOSED,
#    )
#    add_component!(system, bs)
#    remove_component!(system, line)
#    # Set lines 3 and 6 to identical impedance so they're truly parallel
#    line3 = get_component(Line, system, "3")
#    line6 = get_component(Line, system, "6")
#    PSY.set_r!(line3, PSY.get_r(line6, PSY.SU) * PSY.SU)
#    PSY.set_x!(line3, PSY.get_x(line6, PSY.SU) * PSY.SU)
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "HVDCs with DC PF in the loop" begin
#    for hvdc_type in (TwoTerminalGenericHVDCLine,)
#        sys = build_system(PSISystems, "2Area 5 Bus System")
#
#        template_uc = PowerOperationsProblemTemplate(
#            NetworkModel(
#                PTDFNetworkModel;
#                evaluations = power_flow_evaluations(DCPowerFlow()),
#            ),
#        )
#        set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
#        set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
#        set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
#        set_device_model!(template_uc, DeviceModel(Line, StaticBranch))
#        set_device_model!(template_uc, DeviceModel(hvdc_type, HVDCTwoTerminalDispatch))
#
#        model = DecisionModel(template_uc, sys; name = "UC", optimizer = HiGHS_optimizer)
#        @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
#        @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#    end
end

@testset "AC Power Flow line active power loss auxiliary variable" begin
#    system = build_system(PSITestSystems, "c_sys5_uc")
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model_m)
#    ft_key = AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, Line)
#    tf_key = AuxVarKey(POM.PowerFlowBranchActivePowerToFrom, Line)
#    loss_key = AuxVarKey(POM.PowerFlowBranchActivePowerLoss, Line)
#    active_ft = lookup_value(container, ft_key)
#    active_tf = lookup_value(container, tf_key)
#    active_loss = lookup_value(container, loss_key)
#
#    n_time_steps = length(get_time_steps(container))
#    for line_name in axes(active_loss, 1)
#        ft_vals = [active_ft[line_name, t] for t in 1:n_time_steps]
#        tf_vals = [active_tf[line_name, t] for t in 1:n_time_steps]
#        loss_vals = [active_loss[line_name, t] for t in 1:n_time_steps]
#        @test isapprox(loss_vals, ft_vals .+ tf_vals; atol = 1e-9)
#    end
end

@testset "PowerFlowAuxVariable dispatch guards on key entry-type" begin
#    system = build_system(PSITestSystems, "c_sys5_uc")
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#
#    # IOM.get_entry_type extracts the type parameter from an AuxVarKey.
#    supported_key = AuxVarKey(POM.PowerFlowBranchActivePowerLoss, Line)
#    @test IOM.get_entry_type(supported_key) === POM.PowerFlowBranchActivePowerLoss
#
#    # Default ACPowerFlow() has `calculate_loss_factors = false`, so
#    # `PowerFlowLossFactors` is NOT in `bus_aux_vars(pf_data)`. The aux-var
#    # guard at pf_solve_and_aux.jl:152 must early-return on the entry-type
#    # mismatch rather than calling the 4-arg dispatch — which would fail
#    # because the container has no `PowerFlowLossFactors` aux var.
#    unsupported_key = AuxVarKey(POM.PowerFlowLossFactors, PSY.ACBus)
#    @test_nowarn IOM.calculate_aux_variable_value!(container, unsupported_key, system)
end

# Regression for issue #1623 ("PowerFlow in the loop mismatch with Sources"), ported from
# PowerSimulations.jl PR #1631. Parameters store the ALREADY-SIGNED nodal contribution
# (`param_array .* multiplier_array`), identical to what `add_to_expression!` adds to the
# system balance. The PF-in-the-loop injection writer must NOT re-apply the category sign
# (which would double-flip imports). When that happens the PF injection at the affected bus
# is wrong, so `PowerFlowBranchActivePowerFromTo` disagrees with the optimization's
# `PTDFBranchFlow`. These two testsets drive a `FixedOutput` device — whose
# `ActivePowerTimeSeriesParameter` is fed into the PF data through the pre-signed
# (`ParameterKey`) path — and assert the two branch-flow quantities agree.
@testset "PF in the loop matches optimization with FixedOutput parameter path (DC, issue #1623)" begin
#    system = build_system(PSITestSystems, "c_sys5_uc_re")
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            use_slacks = true,
#            evaluations = power_flow_evaluations(DCPowerFlow()),
#        ),
#    )
#    # FixedOutput renewables emit `ActivePowerTimeSeriesParameter`, exercising the
#    # pre-signed `ParameterKey` injection path in the PF-in-the-loop writer.
#    set_device_model!(template, RenewableDispatch, FixedOutput)
#
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    ptdf_flow = IOM.get_expression(container, POM.PTDFBranchFlow, Line)
#    ft_aux = lookup_value(container, AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, Line))
#
#    n_time_steps = length(get_time_steps(container))
#    for line_name in axes(ptdf_flow, 1)
#        for t in 1:n_time_steps
#            @test isapprox(
#                JuMP.value(ptdf_flow[line_name, t]),
#                ft_aux[line_name, t];
#                atol = 1e-3,
#            )
#        end
#    end
end

@testset "PF in the loop matches optimization with FixedOutput parameter path (AC, issue #1623)" begin
#    system = build_system(PSITestSystems, "c_sys5_uc_re")
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            use_slacks = true,
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    set_device_model!(template, RenewableDispatch, FixedOutput)
#
#    model = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    ptdf_flow = IOM.get_expression(container, POM.PTDFBranchFlow, Line)
#    ft_aux = lookup_value(container, AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, Line))
#
#    # The DC PTDFBranchFlow is lossless while the AC PowerFlowBranchActivePowerFromTo carries
#    # AC losses (and the optimization's slacks may be placed differently than the AC power
#    # flow redistributes them), so on this PU-scale system the two agree only to within a few
#    # MW. A double-counted parameter sign at nodeC would instead shift the affected flows by
#    # ~0.6 PU (≈60 MW) — far above this band — so an absolute tolerance of 0.05 PU confirms
#    # agreement while still catching the bug.
#    n_time_steps = length(get_time_steps(container))
#    for line_name in axes(ptdf_flow, 1)
#        for t in 1:n_time_steps
#            @test isapprox(
#                JuMP.value(ptdf_flow[line_name, t]),
#                ft_aux[line_name, t];
#                atol = 0.05,
#            )
#        end
#    end
end

# `lookup_value` returns raw JuMP values in the model (system-base, PU) unit system, and
# `bus_hvdc_net_power` is likewise PU, so the HVDC comparisons below are PU-vs-PU (no base
# conversion). HVDC injections live in PowerFlows' dedicated `bus_hvdc_net_power` channel,
# not the generic `bus_active_power_injections`.
_pf_hvdc_data(container) =
    get_inner_data(only(values(get_evaluation_data(get_evaluations(container)))))
function _hvdc_flow(container, V, name)
    vals = lookup_value(container, VariableKey(V, TwoTerminalGenericHVDCLine))
    return [JuMP.value(vals[name, t]) for t in 1:length(get_time_steps(container))]
end

@testset "DC PF in the loop uses optimized HVDC flow, not the stale system seed" begin
#    # PowerFlows seeds bus_hvdc_net_power from the stored flow and the DC solve never
#    # repopulates it, so PSI must send the optimized flow in for DC. Seed a stale flow, then
#    # assert the channel tracks the per-timestep optimized flow (from = -flow, to = +flow,
#    # lossless).
#    sys = build_system(PSISystems, "2Area 5 Bus System")
#    hvdc = only(get_components(TwoTerminalGenericHVDCLine, sys))
#    from = get_from(get_arc(hvdc))
#    to = get_to(get_arc(hvdc))
#    set_loss!(hvdc, LinearCurve(0.0))
#    set_active_power_flow!(hvdc, 0.5 * PSY.SU)   # a stale system seed the optimization won't reproduce
#
#    template = PowerOperationsProblemTemplate(
#        NetworkModel(PTDFNetworkModel; evaluations = power_flow_evaluations(DCPowerFlow())),
#    )
#    set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
#    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
#    set_device_model!(template, PowerLoad, StaticPowerLoad)
#    set_device_model!(template, DeviceModel(Line, StaticBranch))
#    set_device_model!(
#        template,
#        DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless),
#    )
#    model = DecisionModel(template, sys; name = "UC", optimizer = HiGHS_optimizer)
#    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    flow = _hvdc_flow(container, FlowActivePowerVariable, get_name(hvdc))
#    data = _pf_hvdc_data(container)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(to)], :],
#        flow;
#        atol = 1e-6,
#        rtol = 0,
#    )
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(from)], :],
#        -1 .* flow;
#        atol = 1e-6,
#        rtol = 0,
#    )
#    # sanity: the optimized flow actually populates the channel (the fix does something)
#    @test any(abs.(flow) .> 1e-4)
end

# Shared RTS setup for the AC-PF-in-the-loop HVDC tests: isolate the HVDC line buses (remove
# their injectors, retype the surrounding buses) and build a PTDF UC with an AC power-flow
# evaluation. `loss`/`stored_flow`, when given, overwrite the HVDC line's loss curve / stored
# flow. RTS is used because AC PF needs a single connected AC network containing the HVDC line
# (the small "2Area 5 Bus System" is two AC islands joined only by the DC line).
# TODO replace RTS with something smaller, so these test cases don't take so long.
function _build_rts_hvdc_acpf_model(hvdc_formulation; loss = nothing, stored_flow = nothing)
    sys = build_system(PSISystems, "RTS_GMLC_DA_sys")
    hvdc = only(get_components(TwoTerminalGenericHVDCLine, sys))
    from = get_from(get_arc(hvdc))
    to = get_to(get_arc(hvdc))
    isnothing(loss) || set_loss!(hvdc, loss)
    isnothing(stored_flow) || set_active_power_flow!(hvdc, stored_flow * PSY.SU)
    # remove components that impact total bus power at the HVDC line buses.
    injectors = collect(
        get_components(
            x -> get_number(get_bus(x)) ∈ (get_number(from), get_number(to)),
            StaticInjection,
            sys,
        ),
    )
    foreach(x -> remove_component!(sys, x), injectors)
    for bus_name in ("Chifa", "Arne")
        set_bustype!(get_component(PSY.ACBus, sys, bus_name), PSY.ACBusTypes.PQ)
    end
    set_bustype!(get_component(ACBus, sys, "Arthur"), ACBusTypes.REF)
    template = PowerOperationsProblemTemplate(
        NetworkModel(PTDFNetworkModel; evaluations = power_flow_evaluations(ACPowerFlow())),
    )
    set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(
        template,
        DeviceModel(TwoTerminalGenericHVDCLine, hvdc_formulation),
    )
    model = DecisionModel(template, sys; name = "UC", optimizer = HiGHS_optimizer)
    return (; model, sys, hvdc, from, to)
end

@testset "generic HVDC with AC PF in the loop" begin
#    (; model, sys, hvdc, from, to) = _build_rts_hvdc_acpf_model(HVDCTwoTerminalDispatch)
#    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    name = get_name(hvdc)
#    from_to = _hvdc_flow(container, FlowActivePowerFromToVariable, name)
#    to_from = _hvdc_flow(container, FlowActivePowerToFromVariable, name)
#    data = _pf_hvdc_data(container)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(from)], :],
#        -1 .* from_to;
#        atol = 1e-9,
#        rtol = 0,
#    )
#    @test all(data.bus_active_power_injections[bus_lookup[get_number(from)], :] .== 0.0)
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(to)], :],
#        -1 .* to_from;
#        atol = 1e-9,
#        rtol = 0,
#    )
#    @test all(data.bus_active_power_injections[bus_lookup[get_number(to)], :] .== 0.0)
end

@testset "lossless HVDC with AC PF in the loop" begin
#    # HVDCTwoTerminalLossless exposes a single FlowActivePowerVariable (positive from->to); the
#    # PF input-map falls back to it for both injection categories, so the to-bus must be +flow.
#    # Regression for #1631 (was -flow, the directional FlowActivePowerToFromVariable convention).
#    (; model, sys, hvdc, from, to) = _build_rts_hvdc_acpf_model(HVDCTwoTerminalLossless)
#    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    flow = _hvdc_flow(container, FlowActivePowerVariable, get_name(hvdc))
#    data = _pf_hvdc_data(container)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(from)], :],
#        -1 .* flow;
#        atol = 1e-9,
#        rtol = 0,
#    )
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(to)], :],
#        flow;
#        atol = 1e-9,
#        rtol = 0,
#    )
#    @test all(data.bus_active_power_injections[bus_lookup[get_number(from)], :] .== 0.0)
#    @test all(data.bus_active_power_injections[bus_lookup[get_number(to)], :] .== 0.0)
end

@testset "HVDC bus_hvdc_net_power is not double-counted (issue #1635)" begin
#    # PSI must zero the construction-time HVDC seed before writing the optimized flow, else the
#    # stale value stacks on top. Set an unreproducible stored flow (a deliberately large 0.5 pu
#    # that would be obvious if it leaked), assert the channel holds only the optimized flow.
#    (; model, sys, hvdc, from, to) = _build_rts_hvdc_acpf_model(
#        HVDCTwoTerminalLossless; loss = LinearCurve(0.0), stored_flow = 0.5)
#    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
#    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model)
#    flow = _hvdc_flow(container, FlowActivePowerVariable, get_name(hvdc))
#    data = _pf_hvdc_data(container)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    # bus_hvdc_net_power must equal ONLY the optimized flow (the stale seed was cleared).
#    @test isapprox(
#        data.bus_hvdc_net_power[bus_lookup[get_number(to)], :],
#        flow;
#        atol = 1e-9,
#        rtol = 0,
#    )
end

@testset "AC Power Flow in the loop: Fast Decoupled (FDNR) matches Newton-Raphson" begin
#    pf_data_for(pf_eval) = begin
#        system = build_system(PSITestSystems, "c_sys5_uc")
#        template = get_template_dispatch_with_network(
#            NetworkModel(
#                PTDFNetworkModel;
#                network_matrix = PTDF(system),
#                evaluations = power_flow_evaluations(pf_eval),
#            ),
#        )
#        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#              ModelBuildStatus.BUILT
#        @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
#        container = get_optimization_container(model_m)
#        return get_inner_data(only(values(get_evaluation_data(get_evaluations(container)))))
#    end
#
#    # Newton-Raphson reference (default `ACPolarPowerFlow` solver).
#    nr_data = pf_data_for(ACPolarPowerFlow())
#    @test all(PFS.get_converged(nr_data))
#    # The FD solver tag does not change the container type: read-back uses the identical path.
#    @test nr_data isa PFS.ACPowerFlowData
#
#    # label => evaluator. Each must converge through the loop and match the NR reference.
#    fd_evaluators = [
#        "FDNR default (FDDecoupled/XB)" =>
#            ACPolarPowerFlow{PFS.FastDecoupledACPowerFlow}(),
#        "FDDecoupled/BX scheme" =>
#            ACPolarPowerFlow{
#                PFS.FastDecoupledACPowerFlow{PFS.FDDecoupled, PFS.FDSchemeBX},
#            }(),
#        "FDFixedJacobian (polar)" =>
#            ACPolarPowerFlow{PFS.FastDecoupledFixed}(),
#        "FastDecoupledXB alias" =>
#            ACPolarPowerFlow{PFS.FastDecoupledXB}(),
#        "FDNR handoff -> NewtonRaphson" =>
#            ACPolarPowerFlow{PFS.FastDecoupledACPowerFlow}(;
#                solver_settings = Dict{Symbol, Any}(
#                    :handoff_solver => PFS.NewtonRaphsonACPowerFlow,
#                    :handoff_tol => 1e-3,
#                ),
#            ),
#    ]
#
#    for (label, pf_eval) in fd_evaluators
#        @testset "$label" begin
#            fd_data = pf_data_for(pf_eval)
#            @test all(PFS.get_converged(fd_data))
#            @test isapprox(fd_data.bus_magnitude, nr_data.bus_magnitude;
#                atol = 1e-6, rtol = 0)
#            @test isapprox(fd_data.bus_angles, nr_data.bus_angles;
#                atol = 1e-6, rtol = 0)
#            @test isapprox(
#                fd_data.bus_active_power_injections,
#                nr_data.bus_active_power_injections;
#                atol = 1e-6, rtol = 0,
#            )
#            @test isapprox(
#                fd_data.bus_reactive_power_injections,
#                nr_data.bus_reactive_power_injections;
#                atol = 1e-6, rtol = 0,
#            )
#        end
#    end
#
#    # `FDFixedJacobian` is formulation-agnostic: it must also work on the rectangular
#    # formulation and recover the same physical state as the polar Newton-Raphson reference.
#    @testset "FDFixedJacobian on rectangular formulation" begin
#        rect_fd_data = pf_data_for(ACRectangularPowerFlow{PFS.FastDecoupledFixed}())
#        @test all(PFS.get_converged(rect_fd_data))
#        @test isapprox(rect_fd_data.bus_magnitude, nr_data.bus_magnitude;
#            atol = 1e-6, rtol = 0)
#        @test isapprox(rect_fd_data.bus_angles, nr_data.bus_angles;
#            atol = 1e-6, rtol = 0)
#    end
#
#    # The classic `FDDecoupled` variant (B′/B″ half-iterations) is polar-only; PowerFlows
#    # rejects it on the rectangular formulation at construction.
#    @testset "FDDecoupled rejected on rectangular formulation" begin
#        @test_throws ArgumentError ACRectangularPowerFlow{PFS.FastDecoupledXB}()
#    end
end
