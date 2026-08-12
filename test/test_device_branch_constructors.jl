const DC_NETWORK_MODELS_FOR_TESTING = [PTDFNetworkModel, DCPNetworkModel]

@testset "DC Power Flow Models Monitored Line Flow Constraints and Static Unbounded" begin
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    limits = PSY.get_flow_limits(PSY.get_component(MonitoredLine, system, "1"), PSY.SU)
    for model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_thermal_dispatch_template_network(
            NetworkModel(model),
        )
        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test check_variable_bounded(model_m, FlowActivePowerVariable, MonitoredLine)

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            MonitoredLine,
            "1",
            limits.from_to,
        )
    end
end

@testset "AC Power Flow Monitored Line Flow Constraints" begin
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    limits = PSY.get_flow_limits(PSY.get_component(MonitoredLine, system, "1"), PSY.SU)
    template = get_thermal_dispatch_template_network(ACPNetworkModel)
    model_m = DecisionModel(template, system; optimizer = ipopt_optimizer)
    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    @test check_variable_bounded(model_m, FlowActivePowerFromToVariable, MonitoredLine)
    @test check_variable_bounded(model_m, FlowReactivePowerFromToVariable, MonitoredLine)

    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    @test check_flow_variable_values(
        model_m,
        FlowActivePowerFromToVariable,
        FlowReactivePowerFromToVariable,
        MonitoredLine,
        "1",
        0.0,
        limits.from_to,
    )
end

@testset "DC Power Flow Models Monitored Line Flow Constraints and Static with inequalities" begin
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    set_rating!(PSY.get_component(Line, system, "2"), 1.5 * PSY.SU)
    for model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_thermal_dispatch_template_network(
            NetworkModel(model),
        )
        set_device_model!(template, DeviceModel(Line, StaticBranch))
        set_device_model!(template, DeviceModel(MonitoredLine, StaticBranchUnbounded))
        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        @test check_flow_variable_values(model_m, FlowActivePowerVariable, Line, "2", 1.5)
    end
end

@testset "DC Power Flow Models Monitored Line Flow Constraints and Static with Bounds" begin
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    set_rating!(PSY.get_component(Line, system, "2"), 1.5 * PSY.SU)
    for model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_thermal_dispatch_template_network(NetworkModel(model))
        set_device_model!(template, DeviceModel(Line, StaticBranchBounds))
        set_device_model!(template, DeviceModel(MonitoredLine, StaticBranchUnbounded))
        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        @test check_variable_bounded(model_m, FlowActivePowerVariable, Line)

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        @test check_flow_variable_values(model_m, FlowActivePowerVariable, Line, "2", 1.5)
    end

    # Test the addition of slacks
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    set_device_model!(template, DeviceModel(Line, StaticBranchBounds; use_slacks = true))
    set_device_model!(
        template,
        DeviceModel(MonitoredLine, StaticBranchBounds; use_slacks = true),
    )
    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    @test check_variable_bounded(model_m, FlowActivePowerVariable, Line)
    @test check_variable_bounded(model_m, FlowActivePowerVariable, MonitoredLine)
    @test !check_variable_bounded(model_m, FlowActivePowerSlackLowerBound, Line)
    @test !check_variable_bounded(model_m, FlowActivePowerSlackUpperBound, Line)
    @test !check_variable_bounded(model_m, FlowActivePowerSlackLowerBound, MonitoredLine)
    @test !check_variable_bounded(model_m, FlowActivePowerSlackUpperBound, MonitoredLine)

    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "DC Power Flow Models for TwoTerminalGenericHVDCLine  with with Line Flow Constraints, TwoWindingTransformer Unbounded" begin
    ratelimit_constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, TwoWindingTransformer, "ub"),
        IOM.ConstraintKey(FlowRateConstraint, TwoWindingTransformer, "lb"),
    ]

    system = PSB.build_system(PSITestSystems, "c_sys14_dc")
    hvdc_line = PSY.get_component(TwoTerminalGenericHVDCLine, system, "DCLine3")
    limits_from = PSY.get_active_power_limits_from(hvdc_line, PSY.SU)
    limits_to = PSY.get_active_power_limits_to(hvdc_line, PSY.SU)
    limits_min = min(limits_from.min, limits_to.min)
    limits_max = min(limits_from.max, limits_to.max)

    tap_transformer = PSY.get_component(TwoWindingTransformer, system, "Trans3")
    rate_limit = POM._branch_rating(tap_transformer)

    transformer = PSY.get_component(TwoWindingTransformer, system, "Trans4")
    rate_limit2w = POM._branch_rating(transformer)

    for model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_template_dispatch_with_network(
            NetworkModel(model),
        )
        set_device_model!(template, TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless)
        set_device_model!(template, DeviceModel(TwoWindingTransformer, StaticBranch))
        model_m = DecisionModel(template, system; optimizer = ipopt_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        psi_constraint_test(model_m, ratelimit_constraint_keys)

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoTerminalGenericHVDCLine,
            "DCLine3",
            limits_min,
            limits_max,
        )
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoWindingTransformer,
            "Trans3",
            -rate_limit,
            rate_limit,
        )
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoWindingTransformer,
            "Trans4",
            -rate_limit2w,
            rate_limit2w,
        )
    end
end

@testset "DC Power Flow Models for Unbounded TwoTerminalGenericHVDCLine , and StaticBranchBounds for TwoWindingTransformer" begin
    system = PSB.build_system(PSITestSystems, "c_sys14_dc")
    hvdc_line = PSY.get_component(TwoTerminalGenericHVDCLine, system, "DCLine3")
    limits_from = PSY.get_active_power_limits_from(hvdc_line, PSY.SU)
    limits_to = PSY.get_active_power_limits_to(hvdc_line, PSY.SU)
    limits_min = min(limits_from.min, limits_to.min)
    limits_max = min(limits_from.max, limits_to.max)

    tap_transformer = PSY.get_component(TwoWindingTransformer, system, "Trans3")
    rate_limit = POM._branch_rating(tap_transformer)

    transformer = PSY.get_component(TwoWindingTransformer, system, "Trans4")
    rate_limit2w = POM._branch_rating(transformer)

    for model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_template_dispatch_with_network(
            NetworkModel(model),
        )
        set_device_model!(
            template,
            DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalUnbounded),
        )
        set_device_model!(template, DeviceModel(TwoWindingTransformer, StaticBranchBounds))
        model_m = DecisionModel(template, system; optimizer = ipopt_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        @test check_variable_unbounded(
            model_m,
            FlowActivePowerVariable,
            TwoTerminalGenericHVDCLine,
        )
        @test check_variable_bounded(
            model_m,
            FlowActivePowerVariable,
            TwoWindingTransformer,
        )

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoTerminalGenericHVDCLine,
            "DCLine3",
            limits_min,
            limits_max,
        )
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoWindingTransformer,
            "Trans3",
            -rate_limit,
            rate_limit,
        )
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            TwoWindingTransformer,
            "Trans4",
            -rate_limit2w,
            rate_limit2w,
        )
    end
end

@testset "HVDCTwoTerminalLossless values check between network models" begin
    # Test to compare lossless models with lossless formulation
    sys_5 = build_system(PSITestSystems, "c_sys5_uc")

    line = get_component(Line, sys_5, "1")
    remove_component!(sys_5, line)

    hvdc = TwoTerminalGenericHVDCLine(;
        name = get_name(line),
        available = true,
        active_power_flow = 0.0,
        # Force the flow in the opposite direction for testing purposes
        active_power_limits_from = (min = -0.5, max = -0.5),
        active_power_limits_to = (min = -3.0, max = 2.0),
        reactive_power_limits_from = (min = -1.0, max = 1.0),
        reactive_power_limits_to = (min = -1.0, max = 1.0),
        arc = get_arc(line),
        loss = LinearCurve(0.0),
    )

    add_component!(sys_5, hvdc)

    template_uc = PowerOperationsProblemTemplate(
        NetworkModel(PTDFNetworkModel),
    )

    set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, FixedOutput)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, DeviceModel(Line, StaticBranch))
    set_device_model!(
        template_uc,
        DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless),
    )

    model = DecisionModel(
        template_uc,
        sys_5;
        name = "UC",
        optimizer = HiGHS_optimizer,
    )
    build!(model; output_dir = mktempdir())

    solve!(model)

    ptdf_vars =
        read_variables(OptimizationProblemOutputs(model); table_format = TableFormat.WIDE)
    ptdf_values = ptdf_vars["FlowActivePowerVariable__TwoTerminalGenericHVDCLine"]
    ptdf_objective = IOM.get_optimization_container(model).optimizer_stats.objective_value

    set_network_model!(template_uc, NetworkModel(DCPNetworkModel))
    model = DecisionModel(
        template_uc,
        sys_5;
        name = "UC",
        optimizer = HiGHS_optimizer,
    )
    solve!(model; output_dir = mktempdir())
    dcp_vars =
        read_variables(OptimizationProblemOutputs(model); table_format = TableFormat.WIDE)
    dcp_values = dcp_vars["FlowActivePowerVariable__TwoTerminalGenericHVDCLine"]
    dcp_objective =
        IOM.get_optimization_container(model).optimizer_stats.objective_value
    @test isapprox(dcp_objective, ptdf_objective; atol = 0.1)
    # Resulting solution is in the 4e5 order of magnitude
    @test all(isapprox.(ptdf_values[!, "1"], dcp_values[!, "1"]; atol = 10))
end

@testset "HVDCDispatch Model Tests" begin
    # Test to compare lossless models with lossless formulation
    sys_5 = build_system(PSITestSystems, "c_sys5_uc")
    # Revert to previous rating before data change to prevent different optimal solutions for the lossless model and lossless formulation:
    PSY.set_rating!(PSY.get_component(PSY.Line, sys_5, "6"), 2.0 * PSY.SU)

    line = get_component(Line, sys_5, "1")
    remove_component!(sys_5, line)

    hvdc = TwoTerminalGenericHVDCLine(;
        name = get_name(line),
        available = true,
        active_power_flow = 0.0,
        # Force the flow in the opposite direction for testing purposes
        active_power_limits_from = (min = -2.0, max = 2.0),
        active_power_limits_to = (min = -2.0, max = 2.0),
        reactive_power_limits_from = (min = -1.0, max = 1.0),
        reactive_power_limits_to = (min = -1.0, max = 1.0),
        arc = get_arc(line),
        loss = LinearCurve(0.0),
    )

    add_component!(sys_5, hvdc)
    for net_model in DC_NETWORK_MODELS_FOR_TESTING
        @testset "$net_model" begin
            PSY.set_loss!(hvdc, PSY.LinearCurve(0.0))
            template_uc = PowerOperationsProblemTemplate(
                NetworkModel(net_model; use_slacks = true),
            )

            set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
            set_device_model!(template_uc, RenewableDispatch, FixedOutput)
            set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
            set_device_model!(template_uc, DeviceModel(Line, StaticBranchBounds))
            set_device_model!(
                template_uc,
                DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless),
            )

            model_ref = DecisionModel(
                template_uc,
                sys_5;
                name = "UC",
                optimizer = HiGHS_optimizer,
                store_variable_names = true,
            )

            solve!(model_ref; output_dir = mktempdir())
            ref_vars = read_variables(
                OptimizationProblemOutputs(model_ref);
                table_format = TableFormat.WIDE,
            )
            ref_values = ref_vars["FlowActivePowerVariable__Line"]
            hvdc_ref_values =
                ref_vars["FlowActivePowerVariable__TwoTerminalGenericHVDCLine"]
            ref_objective = model_ref.internal.container.optimizer_stats.objective_value
            ref_total_gen = sum(
                sum.(
                    eachrow(
                        DataFrames.select(
                            ref_vars["ActivePowerVariable__ThermalStandard"],
                            Not(:DateTime),
                        ),
                    )
                ),
            )
            set_device_model!(
                template_uc,
                DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalDispatch),
            )

            model = DecisionModel(
                template_uc,
                sys_5;
                name = "UC",
                optimizer = HiGHS_optimizer,
            )

            solve!(model; output_dir = mktempdir())
            no_loss_vars = read_variables(
                OptimizationProblemOutputs(model);
                table_format = TableFormat.WIDE,
            )
            no_loss_values = no_loss_vars["FlowActivePowerVariable__Line"]
            hvdc_ft_no_loss_values =
                no_loss_vars["FlowActivePowerFromToVariable__TwoTerminalGenericHVDCLine"]
            hvdc_tf_no_loss_values =
                no_loss_vars["FlowActivePowerToFromVariable__TwoTerminalGenericHVDCLine"]
            no_loss_objective =
                IOM.get_optimization_container(model).optimizer_stats.objective_value
            no_loss_total_gen = sum(
                sum.(
                    eachrow(
                        DataFrames.select(
                            no_loss_vars["ActivePowerVariable__ThermalStandard"],
                            Not(:DateTime),
                        ),
                    ),
                ),
            )

            @test isapprox(no_loss_objective, ref_objective; atol = 0.1)

            for col in names(ref_values)
                if typeof(ref_values[1, col]) == DateTime
                    continue
                end
                test_result =
                    all(isapprox.(ref_values[!, col], no_loss_values[!, col]; atol = 0.1))
                @test test_result
                test_result || break
            end

            @test all(
                isapprox.(
                    hvdc_ft_no_loss_values[!, "1"],
                    -hvdc_tf_no_loss_values[!, "1"];
                    atol = 1e-3,
                ),
            )

            @test isapprox(no_loss_total_gen, ref_total_gen; atol = 0.1)

            PSY.set_loss!(hvdc, PSY.LinearCurve(0.005, 0.1))

            model_wl = DecisionModel(
                template_uc,
                sys_5;
                name = "UC",
                optimizer = HiGHS_optimizer,
            )

            solve!(model_wl; output_dir = mktempdir())
            dispatch_vars = read_variables(
                OptimizationProblemOutputs(model_wl);
                table_format = TableFormat.WIDE,
            )
            dispatch_values_ft =
                dispatch_vars["FlowActivePowerFromToVariable__TwoTerminalGenericHVDCLine"]
            dispatch_values_tf =
                dispatch_vars["FlowActivePowerToFromVariable__TwoTerminalGenericHVDCLine"]
            wl_total_gen = sum(
                sum.(
                    eachrow(
                        DataFrames.select(
                            dispatch_vars["ActivePowerVariable__ThermalStandard"],
                            Not(:DateTime),
                        ),
                    ),
                ),
            )
            dispatch_objective = model_wl.internal.container.optimizer_stats.objective_value

            # Note: for this test data the system does better by allowing more losses so
            # the total cost is lower.
            @test wl_total_gen > no_loss_total_gen

            for col in names(dispatch_values_tf)
                test_result = all(dispatch_values_tf[!, col] .<= dispatch_values_ft[!, col])
                @test test_result
                test_result || break
            end
        end
    end
end

@testset "DC Power Flow Models for TwoTerminalGenericHVDCLine  Dispatch and TwoWindingTransformer Unbounded" begin
    ratelimit_constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, Line, "ub"),
        IOM.ConstraintKey(FlowRateConstraint, Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, TwoWindingTransformer, "ub"),
        IOM.ConstraintKey(FlowRateConstraint, TwoWindingTransformer, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, TwoTerminalGenericHVDCLine, "ub"),
        IOM.ConstraintKey(FlowRateConstraint, TwoTerminalGenericHVDCLine, "lb"),
    ]

    system = PSB.build_system(PSITestSystems, "c_sys14_dc")

    hvdc_line = PSY.get_component(TwoTerminalGenericHVDCLine, system, "DCLine3")
    limits_from = PSY.get_active_power_limits_from(hvdc_line, PSY.SU)
    limits_to = PSY.get_active_power_limits_to(hvdc_line, PSY.SU)
    limits_min = min(limits_from.min, limits_to.min)
    limits_max = min(limits_from.max, limits_to.max)

    tap_transformer = PSY.get_component(TwoWindingTransformer, system, "Trans3")
    rate_limit = POM._branch_rating(tap_transformer)

    transformer = PSY.get_component(TwoWindingTransformer, system, "Trans4")
    rate_limit2w = POM._branch_rating(transformer)

    template = get_template_dispatch_with_network(
        NetworkModel(PTDFNetworkModel),
    )
    set_device_model!(template, DeviceModel(TwoWindingTransformer, StaticBranch))
    set_device_model!(
        template,
        DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless),
    )
    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    psi_constraint_test(model_m, ratelimit_constraint_keys)

    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    @test check_flow_variable_values(
        model_m,
        FlowActivePowerVariable,
        TwoTerminalGenericHVDCLine,
        "DCLine3",
        limits_max,
    )
    @test check_flow_variable_values(
        model_m,
        FlowActivePowerVariable,
        TwoWindingTransformer,
        "Trans3",
        rate_limit,
    )
    @test check_flow_variable_values(
        model_m,
        FlowActivePowerVariable,
        TwoWindingTransformer,
        "Trans4",
        rate_limit2w,
    )
end

@testset "DC Power Flow Models for phase-shifting TwoWindingTransformer and Line" begin
    #     system = build_system(PSITestSystems, "c_sys5_uc")
    #
    #     line = get_component(Line, system, "1")
    #
    #     ps = TwoWindingTransformer(;
    #         name = get_name(line),
    #         available = true,
    #         active_power_flow = 0.0,
    #         reactive_power_flow = 0.0,
    #         r = get_r(line, PSY.SU),
    #         x = get_r(line, PSY.SU),
    #         primary_shunt = 0.0,
    #         tap = 1.0,
    #         α = 0.0,
    #         rating = get_rating(line, PSY.SU),
    #         arc = get_arc(line),
    #         base_power = get_base_power(system, PSY.NU),
    #     )
    #
    #     add_component!(system, ps)
    #     remove_component!(system, line)
    #
    #     template = get_template_dispatch_with_network(
    #         NetworkModel(PTDFNetworkModel),
    #     )
    #     set_device_model!(template, DeviceModel(TwoWindingTransformer, PhaseAngleControl))
    #     model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
    #     @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
    #           IOM.ModelBuildStatus.BUILT
    #
    #     @test check_variable_unbounded(
    #         model_m,
    #         FlowActivePowerVariable,
    #         TwoWindingTransformer,
    #     )
    #
    #     @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    #
    #     @test check_flow_variable_values(
    #         model_m,
    #         FlowActivePowerVariable,
    #         TwoWindingTransformer,
    #         "1",
    #         get_rating(ps, PSY.SU),
    #     )
    #
    #     @test check_flow_variable_values(
    #         model_m,
    #         PhaseShifterAngle,
    #         TwoWindingTransformer,
    #         "1",
    #         -π / 2,
    #         π / 2,
    #     )
end

@testset "AC Power Flow Models for TwoTerminalGenericHVDCLine  Flow Constraints and TwoWindingTransformer Unbounded" begin
    ratelimit_constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraintFromTo, TwoWindingTransformer),
        IOM.ConstraintKey(FlowRateConstraintToFrom, TwoWindingTransformer),
        IOM.ConstraintKey(FlowRateConstraint, TwoTerminalGenericHVDCLine, "ub"),
        IOM.ConstraintKey(FlowRateConstraint, TwoTerminalGenericHVDCLine, "lb"),
    ]

    system = PSB.build_system(PSITestSystems, "c_sys14_dc")

    hvdc_line = PSY.get_component(TwoTerminalGenericHVDCLine, system, "DCLine3")
    limits_from = PSY.get_active_power_limits_from(hvdc_line, PSY.SU)
    limits_to = PSY.get_active_power_limits_to(hvdc_line, PSY.SU)
    limits_min = min(limits_from.min, limits_to.min)
    limits_max = min(limits_from.max, limits_to.max)

    tap_transformer = PSY.get_component(TwoWindingTransformer, system, "Trans3")
    rate_limit = POM._branch_rating(tap_transformer)

    transformer = PSY.get_component(TwoWindingTransformer, system, "Trans4")
    rate_limit2w = POM._branch_rating(transformer)

    template = get_template_dispatch_with_network(ACPNetworkModel)
    set_device_model!(template, TwoWindingTransformer, StaticBranchBounds)
    set_device_model!(
        template,
        DeviceModel(TwoTerminalGenericHVDCLine, HVDCTwoTerminalLossless),
    )
    model_m = DecisionModel(template, system; optimizer = ipopt_optimizer)
    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test check_variable_bounded(
        model_m,
        FlowActivePowerFromToVariable,
        TwoWindingTransformer,
    )
    @test check_variable_bounded(
        model_m,
        FlowReactivePowerFromToVariable,
        TwoWindingTransformer,
    )
    @test check_variable_bounded(
        model_m,
        FlowActivePowerToFromVariable,
        TwoWindingTransformer,
    )
    @test check_variable_bounded(
        model_m,
        FlowReactivePowerToFromVariable,
        TwoWindingTransformer,
    )

    psi_constraint_test(model_m, ratelimit_constraint_keys)

    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    @test check_flow_variable_values(
        model_m,
        FlowActivePowerVariable,
        FlowReactivePowerToFromVariable,
        TwoTerminalGenericHVDCLine,
        "DCLine3",
        limits_max,
    )
    @test check_flow_variable_values(
        model_m,
        FlowActivePowerFromToVariable,
        FlowReactivePowerFromToVariable,
        TwoWindingTransformer,
        "Trans3",
        rate_limit,
    )
    @test check_flow_variable_values(
        model_m,
        FlowActivePowerToFromVariable,
        FlowReactivePowerToFromVariable,
        TwoWindingTransformer,
        "Trans4",
        rate_limit2w,
    )
end

@testset "Test Line and Monitored Line models with slacks" begin
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    # This rating (0.247479) was previously inferred in PSY.check_component after setting the rating to 0.0 in the tests
    set_rating!(PSY.get_component(Line, system, "2"), 0.247479 * PSY.SU)
    for (model, optimizer) in NETWORKS_FOR_TESTING
        # CopperPlate no-ops branch construction, so slack variables won't exist
        model == CopperPlateNetworkModel && continue
        template = get_thermal_dispatch_template_network(
            NetworkModel(model; use_slacks = true),
        )
        set_device_model!(template, DeviceModel(Line, StaticBranch; use_slacks = true))
        set_device_model!(
            template,
            DeviceModel(MonitoredLine, StaticBranch; use_slacks = true),
        )
        model_m = DecisionModel(template, system; optimizer = optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        outputs = OptimizationProblemOutputs(model_m)
        vars = read_variable(
            outputs,
            "FlowActivePowerSlackUpperBound__Line";
            table_format = TableFormat.WIDE,
        )
        # some relaxations will find a solution with 0.0 slack
        @test sum(vars[!, "2"]) >= -1e-6
    end

    template = get_thermal_dispatch_template_network(
        NetworkModel(PTDFNetworkModel; use_slacks = true),
    )
    set_device_model!(template, DeviceModel(Line, StaticBranchBounds; use_slacks = true))
    set_device_model!(
        template,
        DeviceModel(MonitoredLine, StaticBranchBounds; use_slacks = true),
    )
    model_m = DecisionModel(template, system; optimizer = fast_ipopt_optimizer)
    @test build!(
        model_m;
        console_level = Logging.AboveMaxLevel,
        output_dir = mktempdir(; cleanup = true),
    ) == IOM.ModelBuildStatus.BUILT

    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    outputs = OptimizationProblemOutputs(model_m)
    vars = read_variable(
        outputs,
        "FlowActivePowerSlackUpperBound__Line";
        table_format = TableFormat.WIDE,
    )
    # some relaxations will find a solution with 0.0 slack
    @test sum(vars[!, "2"]) >= -1e-6

    template = get_thermal_dispatch_template_network(
        NetworkModel(PTDFNetworkModel; use_slacks = true),
    )
    set_device_model!(template, DeviceModel(Line, StaticBranch; use_slacks = true))
    set_device_model!(
        template,
        DeviceModel(MonitoredLine, StaticBranch; use_slacks = true),
    )
    model_m = DecisionModel(template, system; optimizer = fast_ipopt_optimizer)
    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    outputs = OptimizationProblemOutputs(model_m)
    vars = read_variable(
        outputs,
        "FlowActivePowerSlackUpperBound__Line";
        table_format = TableFormat.WIDE,
    )
    # some relaxations will find a solution with 0.0 slack
    @test sum(vars[!, "2"]) >= -1e-6
end

@testset "Three Winding Transformer Test - Basic Setup and Model" begin
    # Start with the base system
    system = PSB.build_system(PSITestSystems, "c_sys5_ml")
    busD = PSY.get_component(ACBus, system, "nodeD")
    # Create a new bus for the tertiary winding (connected via transformer to Bus 4)
    new_bus1 = ACBus(;
        number = 101,
        name = "Bus3WT_1",
        available = true,
        bustype = ACBusTypes.PQ,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = 0.95, max = 1.05),
        base_voltage = 230.0,
        area = PSY.get_area(busD),
        load_zone = PSY.get_load_zone(busD),
    )
    PSY.add_component!(system, new_bus1)

    new_bus2 = ACBus(;
        number = 102,
        name = "Bus3WT_2",
        available = true,
        bustype = ACBusTypes.PQ,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = 0.95, max = 1.05),
        base_voltage = 230.0,
        area = PSY.get_area(busD),
        load_zone = PSY.get_load_zone(busD),
    )
    PSY.add_component!(system, new_bus2)

    # Add a new load at the new bus
    new_load = PowerLoad(;
        name = "Load_Bus3WT",
        available = true,
        bus = new_bus1,
        active_power = 0.5,
        reactive_power = 0.1,
        base_power = 100.0,
        max_active_power = 0.5,
        max_reactive_power = 0.1,
    )
    PSY.add_component!(system, new_load)

    # Add a new generator at the new bus to provide power
    new_gen = ThermalStandard(;
        name = "Gen_Bus100",
        available = true,
        status = true,
        bus = new_bus2,
        active_power = 0.4,
        reactive_power = 0.0,
        rating = 0.5,
        prime_mover_type = PrimeMovers.ST,
        fuel = ThermalFuels.COAL,
        active_power_limits = (min = 0.0, max = 0.5),
        reactive_power_limits = (min = -0.3, max = 0.3),
        ramp_limits = (up = 0.5, down = 0.5),
        operation_cost = ThermalGenerationCost(;
            variable = CostCurve(LinearCurve(0.0)),
            start_up = 0.0,
            shut_down = 0.0,
            fixed = 0.0,
        ),
        base_power = 100.0,
        time_limits = nothing,
    )
    PSY.add_component!(system, new_gen)

    # Create a star bus for the ThreeWindingTransformer
    star_bus = ACBus(;
        number = 103,
        name = "Star_Bus_T3W",
        available = true,
        bustype = ACBusTypes.PQ,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = 0.95, max = 1.05),
        base_voltage = 230.0,
        area = PSY.get_area(busD),
        load_zone = PSY.get_load_zone(busD),
    )
    PSY.add_component!(system, star_bus)

    # Each circuit carries its own terminal-to-star arc, star-leg impedance and rating.
    transformer3w = PSY.ThreeWindingTransformer(;
        name = "ThreeWindingTransformer_busD",
        primary_circuit = PSY.TransformerCircuit(;
            available = true,
            arc = Arc(; from = busD, to = star_bus),
            r = 0.01,
            x = 0.1,
            rating = 1.0,
            base_power = 100.0,
        ),
        secondary_circuit = PSY.TransformerCircuit(;
            available = true,
            arc = Arc(; from = new_bus1, to = star_bus),
            r = 0.01,
            x = 0.1,
            rating = 1.0,
            base_power = 100.0,
        ),
        tertiary_circuit = PSY.TransformerCircuit(;
            available = true,
            arc = Arc(; from = new_bus2, to = star_bus),
            r = 0.01,
            x = 0.1,
            rating = 0.5,
            base_power = 100.0,
        ),
        star_bus = star_bus,
    )
    PSY.add_component!(system, transformer3w)

    # Add ThreeWindingTransformer device model when available
    # Test with DC Power Flow Model
    for net_model in DC_NETWORK_MODELS_FOR_TESTING
        template = get_template_dispatch_with_network(
            NetworkModel(net_model),
        )
        # Set device model for ThreeWindingTransformer
        set_device_model!(template, DeviceModel(ThreeWindingTransformer, StaticBranch))
        set_device_model!(template, MonitoredLine, StaticBranch)

        model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
        @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        # Test flow constraints
        transformer = PSY.get_component(
            ThreeWindingTransformer,
            system,
            "ThreeWindingTransformer_busD",
        )
        @test check_flow_variable_values(
            model_m,
            FlowActivePowerVariable,
            ThreeWindingTransformer,
            "ThreeWindingTransformer_busD_winding_3",
            PSY.get_rating(PSY.get_tertiary_circuit(transformer), PSY.SU),
        )
    end

    template_ac = get_thermal_dispatch_template_network(ACPNetworkModel)
    set_device_model!(template_ac, DeviceModel(ThreeWindingTransformer, StaticBranch))
    model_ac = DecisionModel(template_ac, system; optimizer = ipopt_optimizer)
    @test build!(model_ac; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_ac) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

# A bus is "merged away" by the reduction when it appears in a value set of the bus
# reduction map (coalesced into a representative key). The retained representatives
# are the keys; `get_removed_buses` is unrelated to zero-impedance coalescing here.
_bus_merged_away(nrd, b) = any(b in s for s in values(PNM.get_bus_reduction_map(nrd)))

# A zero-impedance `MonitoredLine` is merged away by the reduction. With
# `model_all_branches = true` its buses are pinned so it survives and is modeled;
# with the default `false` it is reduced away and its (sole-of-type) DeviceModel is
# pruned. Both build; only the flow-rate constraint differs.
@testset "MonitoredLine model_all_branches retains zero-impedance branch" begin
    function _build_zib_monitored_line(model_all_branches)
        sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
        # Force MonitoredLine "1" to be zero-impedance: r == 0 and a tiny reactance
        # push it above the zero-impedance threshold, so the reduction merges its
        # endpoints unless they are pinned irreducible.
        ml = PSY.get_component(MonitoredLine, sys, "1")
        PSY.set_r!(ml, 0.0 * PSY.SU)
        PSY.set_x!(ml, 1e-5 * PSY.SU)
        # The default network source builds a VirtualPTDF, so the reduction runs.
        template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
        set_device_model!(
            template,
            DeviceModel(
                MonitoredLine,
                StaticBranch;
                attributes = Dict{String, Any}(
                    "model_all_branches" => model_all_branches,
                ),
            ),
        )
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        status = build!(model; output_dir = mktempdir(; cleanup = true))
        return model, ml, status
    end

    # The attribute defaults to false.
    default_model = DeviceModel(MonitoredLine, StaticBranch)
    @test POM.get_attribute(default_model, "model_all_branches") == false

    # true: line retained, build succeeds, buses not merged, line modeled.
    model, ml, status = _build_zib_monitored_line(true)
    @test status == IOM.ModelBuildStatus.BUILT
    arc = PSY.get_arc(ml)
    from_bus = PSY.get_number(PSY.get_from(arc))
    to_bus = PSY.get_number(PSY.get_to(arc))
    nm = IOM.get_network_model(IOM.get_template(model))
    nrd = IOM.get_network_matrix(nm).network_reduction_data
    @test !_bus_merged_away(nrd, from_bus)
    @test !_bus_merged_away(nrd, to_bus)
    @test haskey(IOM.get_branch_models(IOM.get_template(model)), :MonitoredLine)
    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(container, FlowRateConstraint, MonitoredLine, "ub")

    # false (default): line reduced away, its sole-of-type DeviceModel pruned,
    # build succeeds with no MonitoredLine flow-rate constraint.
    model_default, ml_default, status_default = _build_zib_monitored_line(false)
    @test status_default == IOM.ModelBuildStatus.BUILT
    nm_d = IOM.get_network_model(IOM.get_template(model_default))
    nrd_d = IOM.get_network_matrix(nm_d).network_reduction_data
    @test _bus_merged_away(nrd_d, PSY.get_number(PSY.get_to(PSY.get_arc(ml_default))))
    @test !haskey(IOM.get_branch_models(IOM.get_template(model_default)), :MonitoredLine)
    container_default = IOM.get_optimization_container(model_default)
    @test !IOM.has_container_key(
        container_default,
        FlowRateConstraint,
        MonitoredLine,
        "ub",
    )
end

# Partial reduction: with multiple monitored lines and `model_all_branches = false`,
# a single near-zero-impedance monitored line is merged away while the type survives.
# Whereas a fully-reduced type is pruned, here the reduced line is silently unmodeled,
# so the build must still succeed and emit an actionable warning that names the line
# and points the user at `model_all_branches`.
@testset "MonitoredLine partial reduction warns and drops only the reduced line" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
    # MonitoredLine "1" forced near-zero impedance so the reduction merges it away.
    ml = PSY.get_component(MonitoredLine, sys, "1")
    PSY.set_r!(ml, 0.0 * PSY.SU)
    PSY.set_x!(ml, 1e-5 * PSY.SU)
    # A second MonitoredLine (converted from a healthy Line) keeps the type non-empty.
    line = first(PSY.get_components(Line, sys))
    survivor = PSY.get_name(line)
    PSY.convert_component!(
        sys,
        line,
        MonitoredLine;
        flow_limits = (from_to = 1.0, to_from = 1.0),
    )

    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    set_device_model!(template, DeviceModel(MonitoredLine, StaticBranch))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT

    # The surviving monitored line is modeled; the merged-away one is dropped.
    container = IOM.get_optimization_container(model)
    constraint_names = axes(
        IOM.get_constraints(container)[IOM.ConstraintKey(
            FlowRateConstraint, MonitoredLine, "ub",
        )],
    )[1]
    @test survivor in constraint_names
    @test !("1" in constraint_names)

    # The drop is reported with an actionable warning naming the line.
    log_contents = read(joinpath(output_dir, "operation_problem.log"), String)
    @test occursin("MonitoredLine(s) [\"1\"]", log_contents)
    @test occursin("model_all_branches", log_contents)
end

# Guards the system-base assumption behind `branch_rating`/`min_max_flow_limits`
# (AC_branches.jl): POM consumes the PNM rating aggregators as system-base values, while
# `PNM.get_equivalent_rating` reads the device-base (`PSY.DU`) rating leaf. For AC branches
# device base equals system base, so the two agree; this locks that invariant so a future
# PSY change introducing a per-branch base surfaces here instead of silently mis-bounding
# branch flows against the system-base `FlowActivePowerVariable` bounds.
@testset "PNM rating aggregators are system base (branch_rating invariant)" begin
    for sysname in ("c_sys5", "c_sys14")
        system = PSB.build_system(PSITestSystems, sysname)
        for branch in PSY.get_components(PSY.ACTransmission, system)
            @test PNM.get_equivalent_rating(branch) == POM._branch_rating(branch)
        end
    end
end

# Ground-truth for the extracted apparent-power rate-limit RHS math
# (`POM._rate_rhs_squared`). This is the shipped-bug guard: an apparent-power
# constraint `p² + q² ≤ RHS` needs `RHS = rating²`, not a bare `rating`. Locking the
# pure math plus a built-model sample (static and time-series paths) ties every routed
# `@constraint` site to the same hand-checked exponent.
@testset "Apparent-power rate-limit RHS builder (_rate_rhs_squared)" begin
    # --- Pure math: hand-computed ---
    @test POM._rate_rhs_squared(2.0) == 4.0
    @test POM._rate_rhs_squared(0.0) == 0.0
    @test POM._rate_rhs_squared(1.5) == 2.25
    # Time-series path RHS = (param_value * multiplier)²; a product squared.
    param_value = 1.2
    mult = 0.9
    @test POM._rate_rhs_squared(param_value * mult) == (param_value * mult)^2
    @test POM._rate_rhs_squared(param_value * mult) ≈ 1.1664

    # --- Built model, STATIC path: sampled FromTo/ToFrom RHS == builder output ---
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    ac_ft = IOM.get_constraint(container, IOM.ConstraintKey(FlowRateConstraintFromTo, Line))
    ac_tf = IOM.get_constraint(container, IOM.ConstraintKey(FlowRateConstraintToFrom, Line))
    for name in axes(ac_ft, 1)
        line = get_component(Line, sys, name)
        expected = POM._rate_rhs_squared(PSY.get_rating(line, PSY.SU))
        for t in axes(ac_ft, 2)
            @test isapprox(JuMP.normalized_rhs(ac_ft[name, t]), expected; rtol = 1e-8)
            @test isapprox(JuMP.normalized_rhs(ac_tf[name, t]), expected; rtol = 1e-8)
        end
    end

    # --- Built model, TIME-SERIES path: sampled RHS == builder(param * mult) ---
    sys_ts = PSB.build_system(PSITestSystems, "c_sys5")
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    add_branch_rating_time_series_to_system!(
        sys_ts,
        branches_with_rating_ts,
        2,
        rating_factors;
        initial_date = "2024-01-01",
    )
    template_ts = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(
        template_ts,
        DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(BranchRatingTimeSeriesParameter => "branch_rating"),
        ),
    )
    model_ts = DecisionModel(template_ts, sys_ts; optimizer = ipopt_optimizer)
    @test build!(model_ts; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container_ts = IOM.get_optimization_container(model_ts)
    @test IOM.has_container_key(container_ts, BranchRatingTimeSeriesParameter, Line)
    ac_ft_ts =
        IOM.get_constraint(container_ts, IOM.ConstraintKey(FlowRateConstraintFromTo, Line))
    # TS RHS = builder(rating * rating_factor[t]); `param * mult` = static_rating *
    # rating_factor, so the builder output must equal the sampled squared RHS.
    n_rating = length(rating_factors)
    for name in branches_with_rating_ts
        static_rating = PSY.get_rating(get_component(Line, sys_ts, name), PSY.SU)
        for (i, t) in enumerate(axes(ac_ft_ts, 2))
            rating_t = static_rating * rating_factors[mod1(i, n_rating)]
            expected = POM._rate_rhs_squared(rating_t)
            @test isapprox(JuMP.normalized_rhs(ac_ft_ts[name, t]), expected; rtol = 1e-6)
        end
    end
    # RHS must actually vary with the time series (factors cross a boundary at t=7).
    @test !isapprox(
        JuMP.normalized_rhs(ac_ft_ts[first(branches_with_rating_ts), 1]),
        JuMP.normalized_rhs(ac_ft_ts[first(branches_with_rating_ts), 7]);
        atol = 1e-6,
    )
end
