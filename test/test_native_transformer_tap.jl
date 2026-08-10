#########################################################################################
# Off-nominal transformer tap under the native network models.
#
# These testsets cover only code that ships in the current module: the DC susceptance
# `b_dc = 1/(tap*x)` used by `BThetaBranchFlow`/`NetworkFlowConstraint`, and the tap-free
# π coefficients in `_tap_flow_coefficients` (both in `ac_transmission_models/
# AC_branches.jl`). They deliberately do NOT touch `TapControl` / `VoltageControlTap`,
# whose formulation files are not yet included — those live in
# `test_native_tapcontrol.jl` / `test_voltage_control_tap_models.jl` and stay disabled
# until the formulations are re-enabled.
#########################################################################################

@testset "StaticBranch models transformer off-nominal tap under DCP (c_sys14)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, PSY.TwoWindingTransformer, StaticBranch)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    # StaticBranch under DCP has no FlowActivePowerVariable: the flow IS the
    # BThetaBranchFlow expression, reported in natural units (MW). VoltageAngle is
    # unitless (radians, no conversion), so compare in per-unit.
    pflow = read_expression(
        res,
        "BThetaBranchFlow__TwoWindingTransformer";
        table_format = TableFormat.WIDE,
    )
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)

    tested_a_real_tap = false
    for tr in PSY.get_components(PSY.TwoWindingTransformer, sys)
        name = PSY.get_name(tr)
        @test name in names(pflow)

        # Recover the series reactance independently, from the π-model admittance, so the
        # oracle does not simply re-call the susceptance helper the source uses.
        adm = PNM.branch_admittance(tr)
        x = -adm.b / (adm.g^2 + adm.b^2)
        # The DC susceptance is tap-divided: b_dc == 1/(tap*x). Pin the equivalence of the
        # independent recovery and PNM's DC entry point.
        @test 1 / (x * adm.tap) ≈ PNM.get_series_susceptance(tr, PSY.SU)

        arc = PSY.get_arc(PSY.get_circuit(tr))
        fr = PSY.get_name(PSY.get_from(arc))
        to = PSY.get_name(PSY.get_to(arc))
        shift = PNM.get_series_phase_shift(tr)
        if !isapprox(adm.tap, 1.0; atol = 1e-6)
            tested_a_real_tap = true
        end
        for r in 1:nrow(pflow)
            p_pu = pflow[r, name] / base
            expected = (va[r, fr] - va[r, to] - shift) / (x * adm.tap)
            @test isapprox(p_pu, expected; atol = 1e-5)
        end
    end
    # Guard: the test system must actually carry a non-unit tap, else this proves nothing.
    @test tested_a_real_tap
end

@testset "_tap_flow_coefficients ground truth (hand-computed)" begin
    # No shift: cs=1, sn=0. Hand-computed π terms and coupling coefficients.
    c0 = POM._tap_flow_coefficients(1.0, -2.0, 0.1, 0.3, 0.2, 0.4, 0.0)
    @test c0.cs == 1.0
    @test c0.sn == 0.0
    # From side is returned UNFOLDED (series and shunt separate) because the two get
    # different tap treatment at the constraint site; see the composition asserts below.
    @test c0.g == 1.0
    @test c0.b == -2.0
    @test c0.g_fr == 0.1
    @test c0.b_fr == 0.3
    # To side stays folded: neither half is tap-referred, matching PNM's `Y22 = Y_l + y_to`.
    @test c0.gg_to == 1.2
    @test c0.bb_to == -1.6
    @test c0.a_cos == -1.0   # -g*cs + b*sn
    @test c0.a_sin == 2.0    # -b*cs - g*sn
    @test c0.c_cos == -1.0   # -g*cs - b*sn
    @test c0.d_sin == -2.0   # b*cs - g*sn

    # From-side composition exactly as the ACP/ACR constraint bodies build it:
    #     g/tm^2 + g_fr      (the series is tap-referred; the magnetizing shunt is NOT)
    # This mirrors PNM's Ybus stamp `Y11 = Y_series/abs2(tap) + y_shunt_from`. The folded
    # convention `(g + g_fr)/tm^2` would give 0.704 / -1.088 instead, which is what made
    # POM's AC solutions disagree with PowerFlows for off-nominal taps.
    tm = 1.25                      # tm^2 == 1.5625, so 1/tm^2 == 0.64 exactly
    @test c0.g / tm^2 + c0.g_fr ≈ 0.74     #  0.64 + 0.1
    @test c0.b / tm^2 + c0.b_fr ≈ -0.98    # -1.28 + 0.3
    # Continuity: at nominal tap the split form reproduces the folded value, so the
    # convention only bites for off-nominal taps.
    @test c0.g / 1.0^2 + c0.g_fr == 1.1
    @test c0.b / 1.0^2 + c0.b_fr == -1.7

    # Nonzero shift = π/6: cs=√3/2, sn=1/2 exercises the trig.
    cs = cos(pi / 6)
    sn = sin(pi / 6)
    cS = POM._tap_flow_coefficients(1.0, -2.0, 0.1, 0.3, 0.2, 0.4, pi / 6)
    @test cS.cs ≈ cs
    @test cS.sn ≈ sn
    @test cS.g == 1.0
    @test cS.b == -2.0
    @test cS.g_fr == 0.1
    @test cS.b_fr == 0.3
    @test cS.gg_to == 1.2
    @test cS.bb_to == -1.6
    @test cS.a_cos ≈ -1.0 * cs + (-2.0) * sn
    @test cS.a_sin ≈ -(-2.0) * cs - 1.0 * sn
    @test cS.c_cos ≈ -1.0 * cs - (-2.0) * sn
    @test cS.d_sin ≈ (-2.0) * cs - 1.0 * sn
    # ACR's e_sin sign relationship the constraint body relies on.
    @test -cS.d_sin ≈ -(-2.0) * cs + 1.0 * sn
end
