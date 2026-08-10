#########################################################################################
# `TapControl` coverage. Disabled in `runtests.jl` until
# `ac_transmission_models/transformer_models.jl` is included again and the `TapControl`
# formulation exists.
#
# The tap physics that DOES ship today — `StaticBranch` under DCP, whose susceptance is
# tap-divided (`b_dc = 1/(tap*x)`) — is covered by `test_native_transformer_tap.jl`, which
# runs. Do not duplicate it here.
#########################################################################################

@testset "TapControl models transformer tap ratio under DCP (c_sys14)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, PSY.TwoWindingTransformer, TapControl)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir()) == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    flow = read_variable(
        res, "FlowActivePowerVariable__TwoWindingTransformer";
        table_format = TableFormat.WIDE,
    )
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)

    tested_a_real_tap = false
    for tr in PSY.get_components(PSY.TwoWindingTransformer, sys)
        name = PSY.get_name(tr)
        @test name in names(flow)
        adm = PNM.branch_admittance(tr)
        x = -adm.b / (adm.g^2 + adm.b^2)
        fr = PSY.get_name(PSY.get_from(PSY.get_arc(tr)))
        to = PSY.get_name(PSY.get_to(PSY.get_arc(tr)))
        if !isapprox(adm.tap, 1.0; atol = 1e-6)
            tested_a_real_tap = true
        end
        for r in 1:nrow(flow)
            p_pu = flow[r, name] / base
            expected = (va[r, fr] - va[r, to] - adm.shift) / (x * adm.tap)
            @test isapprox(p_pu, expected; atol = 1e-5)
        end
    end
    # Guard: the test system must actually have a non-unit tap, else it proves nothing.
    @test tested_a_real_tap
end

@testset "TapControl differs from StaticBranch for non-unit-tap transformers (c_sys14)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys14")

    function _solve_obj(transformer_formulation)
        template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
        set_device_model!(template, PSY.TwoWindingTransformer, transformer_formulation)
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir()) == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        return JuMP.objective_value(IOM.get_jump_model(model))
    end

    static_obj = _solve_obj(StaticBranch)
    tap_obj = _solve_obj(TapControl)
    # `StaticBranch` under DCP now takes its susceptance from `PNM.get_series_susceptance`,
    # which is already tap-divided (`1/(tap*x)`), so a FIXED tap is modelled identically by
    # both formulations and the two optima must AGREE. This testset previously asserted the
    # opposite, from when the DC Ohm's law used the tap-free π susceptance and StaticBranch
    # ignored the tap entirely.
    #
    # Before re-enabling: decide whether `TapControl` still earns its place under DCP at
    # all, given StaticBranch subsumes the fixed-tap case. If it survives only to carry a
    # variable tap, this comparison should be replaced by a test that moves the tap.
    @test isapprox(static_obj, tap_obj; rtol = 1e-8)
end
