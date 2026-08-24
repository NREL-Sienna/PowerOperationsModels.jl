import PowerNetworkMatrices as PNM

@testset "native LPACCNetworkModel builds and solves (c_sys5)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(LPACCNetworkModel))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # --- LPAC voltage-deviation physics check ---
    # phi = |V| - 1 must stay within the bus voltage-deviation bounds [vmin-1, vmax-1].
    res = IOM.OptimizationProblemOutputs(model)
    phi_sol =
        read_variable(res, "VoltageDeviation__ACBus"; table_format = TableFormat.WIDE)
    for bus in PSY.get_components(PSY.ACBus, sys)
        lim = PSY.get_voltage_limits(bus)
        bname = PSY.get_name(bus)
        phi = phi_sol[1, bname]
        @test (lim.min - 1.0) - 1e-4 <= phi <= (lim.max - 1.0) + 1e-4
    end
end

@testset "LPACCNetworkModel objective ≈ ACPNetworkModel objective (c_sys5)" begin
    # LPAC cold-start is a convex linear-AC approximation of the full AC program. On the
    # same system its optimum should land close to (but need not equal) the ACP optimum.
    sys = PSB.build_system(PSITestSystems, "c_sys5")

    template_acp = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model_acp = DecisionModel(template_acp, sys; optimizer = ipopt_optimizer)
    @test build!(model_acp; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_acp) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    acp_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_acp))

    template_lpacc = get_thermal_dispatch_template_network(NetworkModel(LPACCNetworkModel))
    model_lpacc = DecisionModel(template_lpacc, sys; optimizer = ipopt_optimizer)
    @test build!(model_lpacc; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_lpacc) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    lpacc_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_lpacc))

    @test isapprox(lpacc_obj, acp_obj; rtol = 0.05)
end

@testset "LPACCNetworkModel rejects reactive control devices at validation" begin
    # LPACC is reactive-capable at the network level (network_has_reactive_power is true),
    # but ShuntSusceptanceDispatch has no LPACC construct path. The validation gate must
    # reject the pairing with a ConflictingInputsError. (build! swallows build/validation
    # exceptions into a FAILED status, so assert against validate_template directly — same
    # pattern as test_network_constructors_with_branch_rating_time_series.jl.)
    sys_shunt = PSB.build_system(PSITestSystems, "c_sys5")
    bus = PSY.get_component(PSY.ACBus, sys_shunt, "nodeA")
    PSY.add_component!(
        sys_shunt,
        PSY.SwitchedAdmittance(;
            name = "shunt_lpacc_gate",
            available = true,
            bus = bus,
            Y = 0.0 + 0.1im,
            number_of_steps = [2],
            Y_increase = [0.0 + 0.1im],
        ),
    )
    template_shunt =
        get_thermal_dispatch_template_network(NetworkModel(LPACCNetworkModel))
    set_device_model!(template_shunt, PSY.SwitchedAdmittance, ShuntSusceptanceDispatch)
    model_shunt = DecisionModel(template_shunt, sys_shunt; optimizer = ipopt_optimizer)
    @test_throws IS.ConflictingInputsError POM.validate_template(model_shunt)
end
