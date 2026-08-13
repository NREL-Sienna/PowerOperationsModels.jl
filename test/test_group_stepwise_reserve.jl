# Elastic group ORDC (`GroupStepwiseCostReserve`): one demand curve on a `PSY.GroupReserve`
# is cleared by the summed awards of its contributing services. Members are supply-only
# `OnlineReserve`s (zero requirement, no curve); offers and caps live on the members.

# Per-thermal MarketBidCost keeping the unit's own marginal energy cost, plus flat AS offers
# into `sub_a` and `sub_b` (cheap A, prohibitively priced B by default).
function _setup_group_reserve_offers!(
    sys,
    sub_a,
    sub_b;
    sub_a_price = 5.0,
    sub_b_price = 9.0e5,
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")],
    horizon = 24,
    resolution = Hour(1),
)
    offer_curve(price) = IS.PiecewiseStepData([0.0, 100.0], [price])
    for g in get_components(ThermalStandard, sys)
        pmax = PSY.get_max_active_power(g, PSY.NU)
        energy_slope = PSY.get_proportional_term(
            PSY.get_value_curve(PSY.get_variable(get_operation_cost(g))),
        )
        set_operation_cost!(
            g,
            MarketBidCost(;
                no_load_cost = LinearCurve(0.0),
                start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = make_market_bid_curve(
                    [0.0, pmax], [energy_slope], 0.0; power_units = IS.NaturalUnit(),
                ),
            ),
        )
        for (svc, price) in ((sub_a, sub_a_price), (sub_b, sub_b_price))
            data = Dict(it => [offer_curve(price) for _ in 1:horizon] for it in init_times)
            ts = Deterministic(PSY.get_name(svc), data, resolution)
            PSY.set_service_bid!(sys, g, svc, ts, IS.NaturalUnit())
        end
    end
    return
end

function build_group_reserve_system(;
    sub_a_price = 5.0,
    sub_b_price = 9.0e5,
    group_curve = true,
)
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    thermals = collect(get_components(ThermalStandard, sys))
    sub_a = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_A", available = true, time_frame = 3600.0, requirement = 0.0)
    sub_b = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_B", available = true, time_frame = 3600.0, requirement = 0.0)
    add_service!(sys, sub_a, thermals)
    add_service!(sys, sub_b, thermals)
    group = if group_curve
        GroupReserve{ReserveUp}(;
            name = "UP_GROUP",
            available = true,
            requirement = 0.0,
            variable = make_market_bid_curve(
                [0.0, 40.0, 80.0], [80.0, 10.0], 0.0; power_units = IS.NaturalUnit(),
            ),
            contributing_services = Service[sub_a, sub_b],
        )
    else
        # `variable` defaults to the zero-offer sentinel: no demand curve.
        GroupReserve{ReserveUp}(;
            name = "UP_GROUP",
            available = true,
            requirement = 0.0,
            contributing_services = Service[sub_a, sub_b],
        )
    end
    add_service!(sys, group)
    _setup_group_reserve_offers!(
        sys,
        sub_a,
        sub_b;
        sub_a_price = sub_a_price,
        sub_b_price = sub_b_price,
    )
    return sys, group
end

function _group_reserve_template(; include_group = true)
    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    include_group && set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupStepwiseCostReserve),
    )
    return template
end

_sub_cols(df, prefix) = [c for c in names(df) if startswith(c, prefix)]

function _solve_group_model(sys; include_group = true)
    model = DecisionModel(
        _group_reserve_template(; include_group = include_group),
        sys;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    return model
end

@testset "GroupStepwiseCostReserve: builds, solves, single group clearing constraint" begin
    sys, group = build_group_reserve_system()
    model = _solve_group_model(sys)
    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(container, ServiceRequirementVariable, typeof(group))
    @test IOM.has_container_key(container, POM.RequirementConstraint, typeof(group))
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    @test setdiff(names(demand), ["DateTime"]) == ["UP_GROUP"]
end

@testset "GroupStepwiseCostReserve: aggregation binds member awards to group demand" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_cols = _sub_cols(awards, "GROUP_SUB_")
    @test !isempty(sub_cols)
    for t in 1:24
        @test sum(awards[t, c] for c in sub_cols) ≈ demand[t, "UP_GROUP"] atol = 1e-3
    end
end

@testset "GroupStepwiseCostReserve: sub-service merit order" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_a_total = sum(awards[1, c] for c in _sub_cols(awards, "GROUP_SUB_A"))
    sub_b_total = sum(awards[1, c] for c in _sub_cols(awards, "GROUP_SUB_B"))
    @test sub_a_total > 1.0
    @test sub_b_total <= 1e-2
    @test sub_a_total > sub_b_total
end

@testset "GroupStepwiseCostReserve: no group model -> no procurement" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys; include_group = false)
    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    for t in 1:24, c in _sub_cols(awards, "GROUP_SUB_")
        @test awards[t, c] <= 1e-2
    end
end

@testset "Group formulation pairing fails at ServiceModel declaration" begin
    # A GroupReserve accepts only group formulations, and group formulations accept only
    # GroupReserve; mis-pairs must fail at declaration, not at build.
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveUp}, RangeReserve)
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveDown}, StepwiseCostReserve)
    @test_throws ArgumentError ServiceModel(OnlineReserve{ReserveUp}, GroupRangeReserve)
    @test_throws ArgumentError ServiceModel(
        OnlineReserve{ReserveUp},
        GroupStepwiseCostReserve,
    )
    @test_throws ArgumentError ServiceModel(OfflineReserve, GroupStepwiseCostReserve)
    # The valid pairs still construct.
    @test ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve) isa ServiceModel
    @test ServiceModel(GroupReserve{ReserveUp}, GroupStepwiseCostReserve) isa ServiceModel
end

@testset "GroupStepwiseCostReserve: curve-less group is skipped as degenerate demand" begin
    sys, group = build_group_reserve_system(; group_curve = false)
    model = _solve_group_model(sys)
    container = IOM.get_optimization_container(model)
    @test !IOM.has_container_key(container, ServiceRequirementVariable, typeof(group))
    @test !IOM.has_container_key(container, POM.RequirementConstraint, typeof(group))
end

@testset "GroupStepwiseCostReserve: time-series group curve builds, solves and clears" begin
    sys, group = build_group_reserve_system()
    baseline_curve = PSY.get_variable(group)
    power_units = PSY.get_power_units(baseline_curve)
    fd = PSY.get_function_data(PSY.get_value_curve(baseline_curve))
    pwl_ts = make_deterministic_ts(
        sys,
        "variable_cost",
        fd,
        (0.0, 0.0, 0.0),
        (0.0, 0.0, 0.0);
        override_min_x = 0.0,
        override_max_x = last(get_x_coords(fd)),
    )
    pwl_key = add_time_series!(sys, group, pwl_ts)
    PSY.set_variable!(group, PSY.make_market_bid_ts_curve(pwl_key, nothing, power_units))

    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_cols = _sub_cols(awards, "GROUP_SUB_")
    for t in 1:24
        @test demand[t, "UP_GROUP"] > 1.0
        @test sum(awards[t, c] for c in sub_cols) ≈ demand[t, "UP_GROUP"] atol = 1e-3
    end
end
