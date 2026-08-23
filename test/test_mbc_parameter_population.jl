"""
Tests for the parameter-population half of the MBC TS pipeline.

The MBC objective-construction tests in `test_market_bid_cost.jl` call
`add_test_parameter!` / `setup_delta_pwl_parameters!` to poke known values directly into
parameter containers, then verify the downstream objective. That leaves the *other* half
untested: the `add_parameters!` path that pulls values out of real PSY time series and
deposits them into those same containers.

These tests attach real Deterministic time series to a minimal PSY system, call
`add_parameters!` directly, and assert the resulting parameter arrays contain the
expected per-timestep values.
"""

# Minimal System with a ThermalStandard carrying a MarketBidTimeSeriesCost, every field
# backed by a real Deterministic time series sharing the same forecast metadata. `*_incr`
# dials drive per-period drift so an off-by-t wiring is visible.
function _build_mbtsc_thermal_system(;
    name::String = "thermal1",
    init_time::DateTime = DateTime("2020-01-01"),
    horizon::Period = Hour(3),
    interval::Period = Hour(3),
    count::Int = 1,
    resolution::Period = Hour(1),
    start_up_base::NTuple{3, Float64} = (100.0, 150.0, 200.0),
    start_up_incr::Number = 10.0,
    shut_down_base::Float64 = 50.0,
    shut_down_incr::Number = 5.0,
    no_load_base::Float64 = 5.0,
    incr_init_base::Float64 = 10.0,
    incr_init_incr::Number = 2.0,
    decr_init_base::Float64 = 8.0,
    decr_init_incr::Number = 1.0,
    incr_pwl_base::PiecewiseStepData = PiecewiseStepData([0.0, 50.0, 100.0], [25.0, 30.0]),
    decr_pwl_base::PiecewiseStepData = PiecewiseStepData([0.0, 50.0, 100.0], [30.0, 25.0]),
)
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)
    # Placeholder static MBC; replaced once TS are attached.
    static_mbc = PSY.MarketBidCost(;
        no_load_cost = PSY.LinearCurve(0.0),
        start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
        shut_down = PSY.LinearCurve(0.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1.0])),
        decremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1.0])),
    )
    gen = _add_simple_thermal_standard!(sys, bus, static_mbc; name = name)

    common = (init_time, horizon, interval, count, resolution)
    startup_ts =
        make_deterministic_ts("start_up", start_up_base, start_up_incr, 0.0, common...)
    shutdown_ts =
        make_deterministic_ts("shut_down", shut_down_base, shut_down_incr, 0.0, common...)
    noload_ts = make_deterministic_ts("no_load", no_load_base, 0.0, 0.0, common...)
    incr_init_ts = make_deterministic_ts(
        "initial_input incremental", incr_init_base, incr_init_incr, 0.0, common...)
    decr_init_ts = make_deterministic_ts(
        "initial_input decremental", decr_init_base, decr_init_incr, 0.0, common...)
    incr_pwl_ts = make_deterministic_ts(
        "variable_cost incremental", incr_pwl_base,
        (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), common...)
    decr_pwl_ts = make_deterministic_ts(
        "variable_cost decremental", decr_pwl_base,
        (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), common...)

    su_key = add_time_series!(sys, gen, startup_ts)
    sd_key = add_time_series!(sys, gen, shutdown_ts)
    nl_key = add_time_series!(sys, gen, noload_ts)
    ii_incr_key = add_time_series!(sys, gen, incr_init_ts)
    ii_decr_key = add_time_series!(sys, gen, decr_init_ts)
    pwl_incr_key = add_time_series!(sys, gen, incr_pwl_ts)
    pwl_decr_key = add_time_series!(sys, gen, decr_pwl_ts)

    new_cost = PSY.MarketBidTimeSeriesCost(;
        no_load_cost = PSY.TimeSeriesLinearCurve(nl_key),
        start_up = su_key,
        shut_down = PSY.TimeSeriesLinearCurve(sd_key),
        incremental_offer_curves = PSY.make_market_bid_ts_curve(pwl_incr_key, ii_incr_key),
        decremental_offer_curves = PSY.make_market_bid_ts_curve(pwl_decr_key, ii_decr_key),
    )
    PSY.set_operation_cost!(gen, new_cost)
    return sys, gen
end

const _PP_THERMAL_NAME = "thermal1"
const _PP_INITIAL_TIME = DateTime("2020-01-01")
const _PP_MODEL =
    IOM.DeviceModel(PSY.ThermalStandard, POM.ThermalBasicUnitCommitment)

# `build_test_container` leaves `initial_time` at its sentinel default; the TS we attach
# start at 2020-01-01, so align the container's initial_time before reading values.
function _pp_build_container(sys::PSY.System, time_steps::UnitRange{Int})
    container = build_test_container(sys, time_steps)
    IOM.set_initial_time!(IOM.get_settings(container), _PP_INITIAL_TIME)
    return container
end

@testset "StartupCostParameter populated from tuple-valued time series" begin
    # Drift by 10 per hour so each timestep is distinct: (100,150,200), (110,160,210), ...
    sys, gen = _build_mbtsc_thermal_system(;
        name = _PP_THERMAL_NAME,
        start_up_base = (100.0, 150.0, 200.0),
        start_up_incr = 10.0,
        horizon = Hour(3),
    )
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = _pp_build_container(sys, 1:3)
    POM.add_parameters!(container, IOM.StartupCostParameter, devs, _PP_MODEL)

    param_arr = IOM.get_parameter_array(
        container, IOM.StartupCostParameter, PSY.ThermalStandard)
    @test param_arr[_PP_THERMAL_NAME, 1] == (100.0, 150.0, 200.0)
    @test param_arr[_PP_THERMAL_NAME, 2] == (110.0, 160.0, 210.0)
    @test param_arr[_PP_THERMAL_NAME, 3] == (120.0, 170.0, 220.0)
end

@testset "ShutdownCostParameter populated from TimeSeriesLinearCurve" begin
    sys, gen = _build_mbtsc_thermal_system(;
        name = _PP_THERMAL_NAME,
        shut_down_base = 50.0,
        shut_down_incr = 5.0,
        horizon = Hour(3),
    )
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = _pp_build_container(sys, 1:3)
    POM.add_parameters!(container, IOM.ShutdownCostParameter, devs, _PP_MODEL)

    param_arr = IOM.get_parameter_array(
        container, IOM.ShutdownCostParameter, PSY.ThermalStandard)
    @test param_arr[_PP_THERMAL_NAME, 1] ≈ 50.0
    @test param_arr[_PP_THERMAL_NAME, 2] ≈ 55.0
    @test param_arr[_PP_THERMAL_NAME, 3] ≈ 60.0
end

@testset "IncrementalCostAtMinParameter populated from initial_input TS" begin
    sys, gen = _build_mbtsc_thermal_system(;
        name = _PP_THERMAL_NAME,
        incr_init_base = 10.0,
        incr_init_incr = 2.0,
        horizon = Hour(3),
    )
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = _pp_build_container(sys, 1:3)
    POM.add_parameters!(container, IOM.IncrementalCostAtMinParameter, devs, _PP_MODEL)

    param_arr = IOM.get_parameter_array(
        container, IOM.IncrementalCostAtMinParameter, PSY.ThermalStandard)
    @test param_arr[_PP_THERMAL_NAME, 1] ≈ 10.0
    @test param_arr[_PP_THERMAL_NAME, 2] ≈ 12.0
    @test param_arr[_PP_THERMAL_NAME, 3] ≈ 14.0
end

@testset "DecrementalCostAtMinParameter populated from initial_input TS" begin
    sys, gen = _build_mbtsc_thermal_system(;
        name = _PP_THERMAL_NAME,
        decr_init_base = 8.0,
        decr_init_incr = 1.0,
        horizon = Hour(3),
    )
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = _pp_build_container(sys, 1:3)
    POM.add_parameters!(container, IOM.DecrementalCostAtMinParameter, devs, _PP_MODEL)

    param_arr = IOM.get_parameter_array(
        container, IOM.DecrementalCostAtMinParameter, PSY.ThermalStandard)
    @test param_arr[_PP_THERMAL_NAME, 1] ≈ 8.0
    @test param_arr[_PP_THERMAL_NAME, 2] ≈ 9.0
    @test param_arr[_PP_THERMAL_NAME, 3] ≈ 10.0
end

@testset "PWL slope/breakpoint params populated from MBC offer-curve TS" begin
    # Exercises the device-side `_get_time_series_name` / `calc_additional_axes` overloads
    # for time-varying offer curves: incremental params read the incremental curve,
    # decremental the decremental curve; slope params size to the tranche count and
    # breakpoint params to tranches + 1. The helper attaches incremental [25, 30] and
    # decremental [30, 25] slopes over breakpoints [0, 50, 100], so a swapped accessor or
    # mis-sized axis is visible.
    sys, _ = _build_mbtsc_thermal_system(; name = _PP_THERMAL_NAME, horizon = Hour(3))
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    cases = (
        (IOM.IncrementalPiecewiseLinearSlopeParameter,
            ["tranche_1", "tranche_2"], [25.0, 30.0]),
        (IOM.IncrementalPiecewiseLinearBreakpointParameter,
            ["tranche_1", "tranche_2", "tranche_3"], [0.0, 50.0, 100.0]),
        (IOM.DecrementalPiecewiseLinearSlopeParameter,
            ["tranche_1", "tranche_2"], [30.0, 25.0]),
        (IOM.DecrementalPiecewiseLinearBreakpointParameter,
            ["tranche_1", "tranche_2", "tranche_3"], [0.0, 50.0, 100.0]),
    )
    for (P, tranche_axis, vals) in cases
        container = _pp_build_container(sys, 1:3)
        POM.add_parameters!(container, P, devs, _PP_MODEL)
        param_arr = IOM.get_parameter_array(container, P, PSY.ThermalStandard)
        @test axes(param_arr)[1] == [_PP_THERMAL_NAME]
        @test axes(param_arr)[2] == tranche_axis
        @test axes(param_arr)[3] == 1:3
        for t in 1:3, (i, tr) in enumerate(tranche_axis)
            @test param_arr[_PP_THERMAL_NAME, tr, t] ≈ vals[i]
        end
    end
end

@testset "process_market_bid_parameters! filters static-cost devices" begin
    # Two thermals on the same system: one with TS MBC (values driven by time series),
    # one with static MBC (scalar cost object). The orchestrator is expected to add
    # parameter entries only for the TS device; the static device should be filtered
    # out by IOM's `_has_parameter_time_series` gate without firing the OCC assertion.
    #
    # Scope limited to `incremental = false, decremental = false` so only the scalar
    # Startup/Shutdown params run: PWL slope/breakpoint population isn't wired up in
    # POM yet (`_unwrap_for_param` / `calc_additional_axes` overloads live in PSI).
    sys, gen_ts = _build_mbtsc_thermal_system(; name = "thermal_ts")
    bus2 = _add_simple_bus!(sys; number = 2, name = "bus2",
        bustype = PSY.ACBusTypes.PQ)
    static_mbc = PSY.MarketBidCost(;
        no_load_cost = PSY.LinearCurve(0.0),
        start_up = (hot = 999.0, warm = 999.0, cold = 999.0),
        shut_down = PSY.LinearCurve(999.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1.0])),
        decremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1.0])),
    )
    _add_simple_thermal_standard!(sys, bus2, static_mbc; name = "thermal_static")

    devs = PSY.get_components(PSY.ThermalStandard, sys)
    container = _pp_build_container(sys, 1:3)
    # `_consider_parameter` needs StartVariable for StartupCostParameter and StopVariable
    # for ShutdownCostParameter; register both devices so neither gets short-circuited
    # at the trait level (the `_has_parameter_time_series` filter is what should drop
    # the static device). Add both names to each container up front so per-device
    # indexing doesn't clash with the single-name axis `add_jump_var!` creates.
    names = ["thermal_ts", "thermal_static"]
    for V in (IOM.StartVariable, IOM.StopVariable)
        IOM.add_variable_container!(container, V, PSY.ThermalStandard, names, 1:3)
        for name in names, t in 1:3
            IOM.get_variable(container, V, PSY.ThermalStandard)[name, t] =
                JuMP.@variable(IOM.get_jump_model(container),
                    base_name = "$(V)_$(name)_$(t)")
        end
    end

    POM.process_market_bid_parameters!(container, devs, _PP_MODEL, false, false)

    for P in (IOM.StartupCostParameter, IOM.ShutdownCostParameter)
        param_arr = IOM.get_parameter_array(container, P, PSY.ThermalStandard)
        device_axis = axes(param_arr)[1]
        @test "thermal_ts" in device_axis
        @test "thermal_static" ∉ device_axis
    end
end

@testset "IEC PWL slope params populated from import/export offer-curve TS" begin
    # The device-side overloads must resolve the offer curve by direction through the
    # unified `get_output_offer_curves` / `get_input_offer_curves` accessors: incremental
    # reads the IMPORT curve, decremental the EXPORT curve. The MarketBid-specific
    # `PSY.get_incremental_offer_curves` is undefined for `ImportExportTimeSeriesCost`, so
    # before the unified-accessor fix this path raised a MethodError.
    init_time = DateTime("2020-01-01")
    horizon, interval, count, resolution = Hour(3), Hour(3), 1, Hour(1)

    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)
    source = _add_simple_source!(sys, bus,
        PSY.ImportExportCost(;  # placeholder; replaced after we have real TS keys
            import_offer_curves = PSY.make_import_curve([0.0, 1.0], [1.0]),
            export_offer_curves = PSY.make_export_curve([0.0, 1.0], [1.0]),
        );
        name = "source1",
    )

    import_pwl_ts = make_deterministic_ts(
        "variable_cost_import", PiecewiseStepData([0.0, 50.0, 100.0], [5.0, 10.0]),
        (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
        init_time, horizon, interval, count, resolution)
    export_pwl_ts = make_deterministic_ts(
        "variable_cost_export", PiecewiseStepData([0.0, 50.0, 100.0], [10.0, 5.0]),
        (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
        init_time, horizon, interval, count, resolution)
    im_key = add_time_series!(sys, source, import_pwl_ts)
    ex_key = add_time_series!(sys, source, export_pwl_ts)

    PSY.set_operation_cost!(
        source,
        PSY.ImportExportTimeSeriesCost(;
            import_offer_curves = PSY.make_import_export_ts_curve(im_key),
            export_offer_curves = PSY.make_import_export_ts_curve(ex_key),
        ),
    )

    devs = PSY.get_components(PSY.Source, sys)
    iec_model = IOM.DeviceModel(PSY.Source, POM.ImportExportSourceModel)

    # incremental → import slopes [5, 10]
    cont_incr = _pp_build_container(sys, 1:3)
    POM.add_parameters!(
        cont_incr, IOM.IncrementalPiecewiseLinearSlopeParameter, devs, iec_model)
    incr_arr = IOM.get_parameter_array(
        cont_incr, IOM.IncrementalPiecewiseLinearSlopeParameter, PSY.Source)
    @test axes(incr_arr)[2] == ["tranche_1", "tranche_2"]
    for t in 1:3
        @test incr_arr["source1", "tranche_1", t] ≈ 5.0
        @test incr_arr["source1", "tranche_2", t] ≈ 10.0
    end

    # decremental → export slopes [10, 5]
    cont_decr = _pp_build_container(sys, 1:3)
    POM.add_parameters!(
        cont_decr, IOM.DecrementalPiecewiseLinearSlopeParameter, devs, iec_model)
    decr_arr = IOM.get_parameter_array(
        cont_decr, IOM.DecrementalPiecewiseLinearSlopeParameter, PSY.Source)
    for t in 1:3
        @test decr_arr["source1", "tranche_1", t] ≈ 10.0
        @test decr_arr["source1", "tranche_2", t] ≈ 5.0
    end
end

@testset "_get_time_series_name asserts on static-cost devices" begin
    # Each OCC `_get_time_series_name` method asserts `op_cost isa TS_OFFER_CURVE_COST_TYPES`.
    # IOM's filter keeps the precondition true in production; the guards are here to
    # catch any future caller that bypasses the filter. This test confirms they actually
    # fire instead of error-ing later with a confusing MethodError in a PSY accessor.
    static_mbc = PSY.MarketBidCost(;
        no_load_cost = PSY.LinearCurve(0.0),
        start_up = (hot = 100.0, warm = 150.0, cold = 200.0),
        shut_down = PSY.LinearCurve(50.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(5.0, [0.0, 100.0], [25.0])),
        decremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(5.0, [0.0, 100.0], [25.0])),
    )
    sys = one_bus_one_thermal(static_mbc; name = _PP_THERMAL_NAME)
    gen = PSY.get_component(PSY.ThermalStandard, sys, _PP_THERMAL_NAME)

    for P in (
        IOM.StartupCostParameter,
        IOM.ShutdownCostParameter,
        IOM.IncrementalCostAtMinParameter,
        IOM.DecrementalCostAtMinParameter,
    )
        @test_throws AssertionError POM._get_time_series_name(P, gen, _PP_MODEL)
    end
end
