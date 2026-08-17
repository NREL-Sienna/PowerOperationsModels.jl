#########################################################################################
# Off-nominal transformer tap under the native network models.
#
# These testsets cover only code that ships in the current module: the DC susceptance
# `b_dc = 1/(tap*x)` used by `BThetaBranchFlow`/`NetworkFlowConstraint`, and the Ybus
# two-port terms in `_tapped_admittance` (both in `ac_transmission_models/
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

@testset "_tapped_admittance round-trips PNM.ybus_branch_entries" begin
    function check_terms(y, ybus)
        Y11, Y12, Y21, Y22 = ybus
        @test isapprox(complex(y.g11, y.b11), Y11; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g12, y.b12), Y12; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g21, y.b21), Y21; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g22, y.b22), Y22; rtol = 1e-10, atol = 1e-12)
    end

    sys = PSB.build_system(PSITestSystems, "c_sys14")
    for br in Iterators.flatten((
        PSY.get_components(PSY.Line, sys),
        PSY.get_components(PSY.TwoWindingTransformer, sys),
    ))
        adm = PNM.branch_admittance(br)
        check_terms(POM._pi_flow_terms(adm, adm.tap), PNM.ybus_branch_entries(br))
    end

    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
    circuit = PSY.get_circuit(tr)
    for shift in (-pi / 5, 0.0, pi / 6)
        PSY.set_α!(circuit, shift)
        PSY.set_tap!(circuit, 1.0)
        adm = PNM.branch_admittance(tr)
        for tap in (0.9, 1.0, 1.1, 1.25)
            PSY.set_tap!(circuit, tap)
            check_terms(POM._pi_flow_terms(adm, tap), PNM.ybus_branch_entries(tr))
        end
    end
end
