# See also test_import_export_cost.jl

const BASIC_SOURCE_CONSTRAINT_KEYS = [
    ConstraintKey(ImportExportBudgetConstraint, PSY.Source, "import"),
    ConstraintKey(ImportExportBudgetConstraint, PSY.Source, "export"),
    ConstraintKey(ActivePowerVariableLimitsConstraint, PSY.Source, "ub"),
    ConstraintKey(ActivePowerVariableLimitsConstraint, PSY.Source, "lb"),
    ConstraintKey(InputActivePowerVariableLimitsConstraint, PSY.Source, "ub"),
    ConstraintKey(InputActivePowerVariableLimitsConstraint, PSY.Source, "lb"),
    ConstraintKey(PiecewiseLinearBlockIncrementalOfferConstraint, PSY.Source),
    ConstraintKey(PiecewiseLinearBlockDecrementalOfferConstraint, PSY.Source),
]

const TS_SOURCE_CONSTRAINT_KEYS = [
    BASIC_SOURCE_CONSTRAINT_KEYS...,
    ConstraintKey(ActivePowerOutVariableTimeSeriesLimitsConstraint, PSY.Source, "ub"),
    ConstraintKey(ActivePowerInVariableTimeSeriesLimitsConstraint, PSY.Source, "ub"),
]

@testset "ImportExportSource Source With CopperPlate" begin
    sys = make_5_bus_with_import_export(; add_single_time_series = false)

    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => false),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 240, 0, 242, 48, 48, false)
    psi_constraint_test(model, BASIC_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)

    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => true),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 264, 0, 242, 48, 48, true)
    psi_constraint_test(model, BASIC_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "ImportExportSource Source With ACPNetworkModel" begin
    sys = make_5_bus_with_import_export(; add_single_time_series = false)

    model = DecisionModel(MockOperationProblem, ACPNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => false),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 264, 0, 266, 72, 48, false)
    psi_constraint_test(model, BASIC_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)

    model = DecisionModel(MockOperationProblem, ACPNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => true),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 288, 0, 266, 72, 48, true)
    psi_constraint_test(model, BASIC_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "ImportExportSource Source With CopperPlate and TimeSeries" begin
    sys = make_5_bus_with_import_export(; add_single_time_series = true)
    source = get_component(Source, sys, "source")

    load = first(get_components(PowerLoad, sys))
    tstamp =
        TimeSeries.timestamp(
            get_time_series_array(SingleTimeSeries, load, "max_active_power"),
        )

    day_data = [
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
    ]

    ts_data = repeat(day_data, 2)
    ts_out = SingleTimeSeries(
        "max_active_power_out",
        TimeArray(tstamp, ts_data),
    )
    ts_in = SingleTimeSeries(
        "max_active_power_in",
        TimeArray(tstamp, ts_data),
    )
    add_time_series!(sys, source, ts_out)
    add_time_series!(sys, source, ts_in)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    source_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => false),
        time_series_names = Dict{Any, String}(
            ActivePowerInTimeSeriesParameter => "max_active_power_in",
            ActivePowerOutTimeSeriesParameter => "max_active_power_out",
        ),
    )
    set_device_model!(template, source_model)

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = false,
    )

    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemOutputs(model)
    p_out = read_variable(
        res,
        "ActivePowerOutVariable__Source";
        table_format = TableFormat.WIDE,
    )[
        !,
        2,
    ]
    p_in =
        read_variable(res, "ActivePowerInVariable__Source"; table_format = TableFormat.WIDE)[
            !,
            2,
        ]

    # Test that is zero when the time series is zero
    @test p_out[5] == 0.0
    @test p_in[5] == 0.0
    @test p_out[6] == 0.0
    @test p_in[6] == 0.0
end

@testset "FixedOutput Source With CopperPlate and TimeSeries" begin
    # FixedOutput Source adds ActivePowerIn/OutTimeSeriesParameter and no variables
    # (PSI #1573 ported to POM). The parameter values follow the in/out time series.
    sys = make_5_bus_with_import_export(; add_single_time_series = true)
    source = get_component(Source, sys, "source")

    load = first(get_components(PowerLoad, sys))
    tstamp =
        TimeSeries.timestamp(
            get_time_series_array(SingleTimeSeries, load, "max_active_power"),
        )

    day_data = [
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
    ]
    ts_data = repeat(day_data, 2)
    ts_out = SingleTimeSeries(
        "max_active_power_out",
        TimeArray(tstamp, ts_data),
    )
    ts_in = SingleTimeSeries(
        "max_active_power_in",
        TimeArray(tstamp, ts_data),
    )
    add_time_series!(sys, source, ts_out)
    add_time_series!(sys, source, ts_in)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, DeviceModel(Source, FixedOutput))

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = false,
    )

    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemOutputs(model)
    p_out = read_parameter(
        res,
        "ActivePowerOutTimeSeriesParameter__Source";
        table_format = TableFormat.WIDE,
    )[
        !,
        2,
    ]
    p_in = read_parameter(
        res,
        "ActivePowerInTimeSeriesParameter__Source";
        table_format = TableFormat.WIDE,
    )[
        !,
        2,
    ]

    # FixedOutput adds no In/Out variables
    @test !has_container_key(
        get_optimization_container(model),
        ActivePowerOutVariable,
        Source,
    )
    # Parameter is zero where the time series is zero
    @test p_out[5] == 0.0
    @test p_in[5] == 0.0
    @test p_out[6] == 0.0
    @test p_in[6] == 0.0
end

@testset "ImportExportSource Source With CopperPlate and TimeSeries" begin
    sys = make_5_bus_with_import_export(; add_single_time_series = true)
    source = get_component(Source, sys, "source")

    load = first(get_components(PowerLoad, sys))
    tstamp =
        TimeSeries.timestamp(
            get_time_series_array(SingleTimeSeries, load, "max_active_power"),
        )

    day_data = [
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
    ]

    ts_data = repeat(day_data, 2)
    ts_out = SingleTimeSeries(
        "max_active_power_out",
        TimeArray(tstamp, ts_data),
    )
    ts_in = SingleTimeSeries(
        "max_active_power_in",
        TimeArray(tstamp, ts_data),
    )
    add_time_series!(sys, source, ts_out)
    add_time_series!(sys, source, ts_in)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    model = DecisionModel(MockOperationProblem, ACPNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => false),
        time_series_names = Dict{Any, String}(
            ActivePowerInTimeSeriesParameter => "max_active_power_in",
            ActivePowerOutTimeSeriesParameter => "max_active_power_out",
        ),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 264, 0, 314, 72, 48, false)
    psi_constraint_test(model, TS_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)

    model = DecisionModel(MockOperationProblem, ACPNetworkModel, sys)
    device_model = DeviceModel(
        Source,
        ImportExportSourceModel;
        attributes = Dict("reservation" => true),
        time_series_names = Dict{Any, String}(
            ActivePowerInTimeSeriesParameter => "max_active_power_in",
            ActivePowerOutTimeSeriesParameter => "max_active_power_out",
        ),
    )
    mock_construct_device!(model, device_model)
    moi_tests(model, 288, 0, 314, 72, 48, true)
    psi_constraint_test(model, TS_SOURCE_CONSTRAINT_KEYS)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "ImportExportSource populates NetActivePower on every network" begin
    for network_formulation in (CopperPlateNetworkModel, ACPNetworkModel)
        sys = make_5_bus_with_import_export(; add_single_time_series = false)
        model = DecisionModel(MockOperationProblem, network_formulation, sys)
        device_model = DeviceModel(
            Source,
            ImportExportSourceModel;
            attributes = Dict("reservation" => false),
        )
        mock_construct_device!(model, device_model)

        container = IOM.get_optimization_container(model)
        p_out = IOM.get_variable(container, ActivePowerOutVariable, PSY.Source)
        p_in = IOM.get_variable(container, ActivePowerInVariable, PSY.Source)
        net = IOM.get_expression(container, POM.NetActivePower, PSY.Source)
        t1 = first(IOM.get_time_steps(container))

        # net injection = out - in for every source, on AC networks too
        for source in PSY.get_components(PSY.Source, sys)
            name = PSY.get_name(source)
            @test JuMP.coefficient(net[name, t1], p_out[name, t1]) == 1.0
            @test JuMP.coefficient(net[name, t1], p_in[name, t1]) == -1.0
        end
    end
end
