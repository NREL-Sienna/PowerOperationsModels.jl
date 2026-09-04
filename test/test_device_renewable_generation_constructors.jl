@testset "Renewable DCPLossless FullDispatch" begin
    device_model = DeviceModel(RenewableDispatch, RenewableFullDispatch)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re)
    mock_construct_device!(model, device_model)
    moi_tests(model, 72, 0, 72, 0, 0, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 72, 0, 96, 0, 0, false)
end

@testset "Renewable ACPPower Full Dispatch" begin
    device_model = DeviceModel(RenewableDispatch, RenewableFullDispatch)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model)
    moi_tests(model, 144, 0, 144, 72, 0, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 144, 0, 168, 72, 0, false, 24)
end

@testset "Renewable DCPLossless Constantpower_factor" begin
    device_model = DeviceModel(RenewableDispatch, RenewableConstantPowerFactor)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re)
    mock_construct_device!(model, device_model)
    moi_tests(model, 72, 0, 72, 0, 0, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 72, 0, 96, 0, 0, false)
end

@testset "Renewable ACPPower Constantpower_factor" begin
    device_model = DeviceModel(RenewableDispatch, RenewableConstantPowerFactor)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model)
    moi_tests(model, 144, 0, 72, 0, 72, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 144, 0, 96, 0, 72, false, 24)
end

@testset "Renewable DCPLossless FixedOutput" begin
    device_model = DeviceModel(RenewableDispatch, FixedOutput)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model)
    moi_tests(model, 0, 0, 0, 0, 0, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 0, 0, 0, 0, 0, false)
end

@testset "Renewable ACPNetworkModel FixedOutput" begin
    device_model = DeviceModel(RenewableDispatch, FixedOutput)
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model)
    moi_tests(model, 0, 0, 0, 0, 0, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_re;)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 0, 0, 0, 0, 0, false)
end

@testset "Test Renewable CurtailmentCostExpression nonnegativity" begin
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, ThermalStandard, ThermalStandardDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_re;
        name = "RE_curtailment_cost",
        optimizer = HiGHS_optimizer,
        optimizer_solve_log_print = true,
    )

    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)
    expr_curt = read_expression(
        outputs,
        "CurtailmentCostExpression__RenewableDispatch";
        table_format = TableFormat.WIDE,
    )

    tol = 1e-8
    for unit in names(expr_curt)[2:end]
        @test all(expr_curt[!, unit] .>= -tol)
    end
end

@testset "Renewable curtailment cost with mixed time-series availability" begin
    # Regression: `_renewable_offer_max` must not KeyError when the
    # ActivePowerTimeSeriesParameter container exists for the renewable type but a
    # particular device has no time-series entry. That device should fall back to its
    # static max_active_power rather than indexing into a missing parameter row.
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")

    no_ts_re = get_component(RenewableDispatch, c_sys5_re, "WindBusA")
    base_cost = get_operation_cost(no_ts_re)
    set_operation_cost!(
        no_ts_re,
        RenewableGenerationCost(;
            variable_operation_cost = base_cost.variable_operation_cost,
            curtailment_cost = CostCurve(LinearCurve(10.0)),
            fixed = base_cost.fixed,
        ),
    )
    # Drop this device's time series while the other renewables keep theirs, so the
    # type-level parameter container is built (from WindBusB/WindBusC) but WindBusA is
    # absent from it.
    remove_time_series!(c_sys5_re, Deterministic, no_ts_re, "max_active_power")

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, ThermalStandard, ThermalStandardDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_re;
        name = "RE_mixed_ts_curtailment",
        optimizer = HiGHS_optimizer,
    )

    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Renewable with quadratic variable cost builds objective (issue #9)" begin
    # Regression test: a RenewableDispatch with a quadratic cost curve used to call
    # `PSY.get_active_power_limits`, but renewables only have a max active power field,
    # not active power limits.
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")

    quad_re = get_component(RenewableDispatch, c_sys5_re, "WindBusA")
    base_cost = get_operation_cost(quad_re)
    # Renewable ActivePowerVariable costs use OBJECTIVE_FUNCTION_NEGATIVE, so the negated
    # objective term `-cost(p)` is convex (and free of the non-monotonicity warning) when
    # the raw curve is concave, i.e. negative coefficients.
    set_operation_cost!(
        quad_re,
        RenewableGenerationCost(;
            variable_operation_cost = CostCurve(QuadraticCurve(-2.0, -1.0, 0.0)),
            curtailment_cost = base_cost.curtailment_cost,
            fixed = base_cost.fixed,
        ),
    )

    device_model = DeviceModel(RenewableDispatch, RenewableFullDispatch)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_re)
    # Before the fix this threw `ArgumentError: get_active_power_limits not implemented
    # for RenewableDispatch`; now it constructs a quadratic objective.
    mock_construct_device!(model, device_model)
    psi_checkobjfun_test(model, GQEVF)

    # Direct check of the bridge that the issue is about.
    @test IOM.get_active_power_limits(quad_re) ==
          (min = 0.0, max = PSY.get_max_active_power(quad_re, PSY.SU))
end
