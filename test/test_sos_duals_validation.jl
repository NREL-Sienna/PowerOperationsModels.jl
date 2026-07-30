@testset "Duals + solver SOS2 constraints error at build time" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_pwl_ed_nonconvex")
    template = PowerOperationsProblemTemplate(
        NetworkModel(CopperPlateNetworkModel; duals = [CopperPlateBalanceConstraint]),
    )
    set_device_model!(template, ThermalStandard, ThermalStandardDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED

    log_text = read(joinpath(output_dir, IOM.PROBLEM_LOG_FILENAME), String)
    @test occursin("solver SOS1/SOS2 constraint", log_text)
    @test occursin("CopperPlateBalanceConstraint", log_text)
end

@testset "Duals + solver SOS2 constraints non-vacuity: SOS2 is actually present without duals" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_pwl_ed_nonconvex")
    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalStandardDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    jump_model = IOM.get_jump_model(IOM.get_optimization_container(model))
    sos2_constraint_count = 0
    for (F, S) in JuMP.list_of_constraint_types(jump_model)
        POM._is_solver_sos_set(S) || continue
        sos2_constraint_count += JuMP.num_constraints(jump_model, F, S)
    end
    @test sos2_constraint_count > 0
end

@testset "Duals on a binary MILP without SOS constraints still builds" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    template = PowerOperationsProblemTemplate(
        NetworkModel(CopperPlateNetworkModel; duals = [CopperPlateBalanceConstraint]),
    )
    set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        horizon = _SHORT_HORIZON,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "Duals retrievable with manual binary SOS2 bilinear approximation" begin
    sys = PSB.build_system(PSISystems, "sys10_pjm_ac_dc")
    for ipc in get_components(InterconnectingConverter, sys)
        set_loss_function!(ipc, QuadraticCurve(0.01, 0.01, 0.0))
        set_max_dc_current!(ipc, 2.0 * PSY.SU)
    end

    template = PowerOperationsProblemTemplate(
        NetworkModel(
            PTDFNetworkModel;
            network_matrix = PTDF(sys),
            duals = [CopperPlateBalanceConstraint],
        ),
    )
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, TModelHVDCLine, DCLossyLine)
    set_device_model!(
        template,
        DeviceModel(
            InterconnectingConverter, QuadraticLossConverter;
            attributes = Dict(
                "bilinear_approximation" => "bin2",
                "bilinear_quadratic_method" => "manual_sos2",
                "bilinear_relative_tolerance" => 0.35,
            ),
        ),
    )
    set_hvdc_network_model!(template, VoltageDispatchHVDCNetworkModel)
    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        horizon = _SHORT_HORIZON,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    jump_model = IOM.get_jump_model(IOM.get_optimization_container(model))
    @test JuMP.num_constraints(jump_model, JuMP.VariableRef, JuMP.MOI.ZeroOne) > 0
    sos2_constraint_count = 0
    for (F, S) in JuMP.list_of_constraint_types(jump_model)
        POM._is_solver_sos_set(S) || continue
        sos2_constraint_count += JuMP.num_constraints(jump_model, F, S)
    end
    @test sos2_constraint_count == 0

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    constraint_key = IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System)
    dual_outputs = IOM.read_duals(container)[constraint_key]
    dual_values = Matrix(dual_outputs)
    @test all(isfinite, dual_values)
end
