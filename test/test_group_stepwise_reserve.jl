# GroupStepwiseReserveCurve: a group Ancillary Service Demand Curve (ASDC) whose single elastic
# demand is met by the awards of several contributing sub-services. This is the ERCOT RTC+B
# pattern where one product (e.g. RRS) has one demand curve but several sub-types (PFR, FFR, UFR)
# that each carry their own per-resource offers and per-resource caps.
#
# The group (`PSY.ReserveDemandCurveGroup`, `<: Service`) adds ONE `ServiceRequirementVariable`
# priced by the group ASDC (a decremental benefit), and ONE `RequirementConstraint` binding the
# sum of the contributing sub-services' `ActivePowerReserveVariable` awards to that demand. The
# sub-services themselves are ordinary `RangeReserve` reserves with no own demand (requirement 0)
# whose awards are priced by their per-resource offers. So supply merit order lives on the
# sub-services and the single clearing (one MCPC) lives on the group.

# Add both RRS sub-services to every thermal, then give each thermal a MarketBidCost (keeping its
# own energy offer) plus a flat per-hour reserve offer into each sub-service: PFR cheap, FFR
# pricey. Reading the energy slope from the ORIGINAL cost before overwriting keeps a single cost
# overwrite per device.
function _setup_group_reserve_offers!(
    sys,
    pfr,
    ffr;
    pfr_price = 5.0,
    ffr_price = 9.0e5,
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")],
    horizon = 24,
    resolution = Hour(1),
)
    flat_offer(price) = IS.PiecewiseStepData([0.0, 100.0], [price])
    flat_ts(reserve, price) = Deterministic(
        PSY.get_name(reserve),
        Dict(it => [flat_offer(price) for _ in 1:horizon] for it in init_times),
        resolution,
    )
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
        PSY.set_service_bid!(sys, g, pfr, flat_ts(pfr, pfr_price), IS.NaturalUnit())
        PSY.set_service_bid!(sys, g, ffr, flat_ts(ffr, ffr_price), IS.NaturalUnit())
    end
    return
end

# Build a self-contained system: c_sys5_uc thermals + two RRS sub-services (ConstantReserve, no
# own demand) offered by every thermal, plus one group ASDC over both. PFR is cheap ($5/MWh) and
# FFR is prohibitively pricey, so the elastic group demand clears through PFR, not FFR.
function build_group_reserve_system(; pfr_price = 5.0, ffr_price = 9.0e5)
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    thermals = collect(get_components(ThermalStandard, sys))
    # ConstantReserve{ReserveUp}(name, available, time_frame, requirement): requirement 0 -> the
    # sub-service imposes no demand; procurement is driven only by the group.
    pfr = ConstantReserve{ReserveUp}("RRS_PFR", true, 3600.0, 0.0)
    ffr = ConstantReserve{ReserveUp}("RRS_FFR", true, 3600.0, 0.0)
    add_service!(sys, pfr, thermals)
    add_service!(sys, ffr, thermals)
    _setup_group_reserve_offers!(
        sys,
        pfr,
        ffr;
        pfr_price = pfr_price,
        ffr_price = ffr_price,
    )
    # ASDC: first 40 MW valued $80/MWh, next 40 MW $10/MWh; both above the cheap PFR offer, so the
    # group procures reserve where the ASDC price meets the marginal (PFR) supply.
    asdc = make_market_bid_curve(
        [0.0, 40.0, 80.0], [80.0, 10.0], 0.0; power_units = IS.NaturalUnit(),
    )
    group = ReserveDemandCurveGroup{ReserveUp}(;
        variable = asdc,
        name = "RRS",
        available = true,
        time_frame = 5.0,
    )
    add_service!(sys, group, Service[pfr, ffr])
    return sys, pfr, ffr, group
end

function _group_reserve_template(; include_group = true)
    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(ConstantReserve{ReserveUp}, RangeReserve))
    if include_group
        set_service_model!(
            template,
            ServiceModel(ReserveDemandCurveGroup{ReserveUp}, GroupStepwiseReserveCurve),
        )
    end
    return template
end

_sub_cols(df, prefix) = [c for c in names(df) if startswith(c, prefix)]

@testset "GroupStepwiseReserveCurve: builds, solves, single group clearing constraint" begin
    sys, pfr, ffr, group = build_group_reserve_system()
    model = DecisionModel(_group_reserve_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # The group owns exactly one endogenous demand variable and one clearing constraint (the
    # single MCPC-bearing balance), keyed by the concrete group service type.
    @test IOM.has_container_key(container, ServiceRequirementVariable, typeof(group))
    @test IOM.has_container_key(container, POM.RequirementConstraint, typeof(group))

    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__ReserveDemandCurveGroup__ReserveUp";
        table_format = TableFormat.WIDE)
    # One group -> one demand column ("RRS"); the sub-services carry no demand variable of their own.
    @test setdiff(names(demand), ["DateTime"]) == ["RRS"]
end

@testset "GroupStepwiseReserveCurve: aggregation binds sub-service awards to group demand" begin
    sys, pfr, ffr, group = build_group_reserve_system()
    model = DecisionModel(_group_reserve_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__ConstantReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    demand = read_variable(
        res, "ServiceRequirementVariable__ReserveDemandCurveGroup__ReserveUp";
        table_format = TableFormat.WIDE)
    # WIDE columns are "<service>__<device>"; values are per-hour awards in MW (both variables
    # convert to natural units on read, so the balance holds in MW).
    sub_cols = [_sub_cols(awards, "RRS_PFR__"); _sub_cols(awards, "RRS_FFR__")]
    @test !isempty(sub_cols)
    for t in 1:24
        subtotal = sum(awards[t, c] for c in sub_cols)
        @test subtotal ≈ demand[t, "RRS"] atol = 1e-3
    end
end

@testset "GroupStepwiseReserveCurve: sub-service merit order (cheap PFR clears, pricey FFR does not)" begin
    sys, pfr, ffr, group = build_group_reserve_system()
    model = DecisionModel(_group_reserve_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__ConstantReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    pfr_cols = _sub_cols(awards, "RRS_PFR__")
    ffr_cols = _sub_cols(awards, "RRS_FFR__")
    pfr_total = sum(awards[1, c] for c in pfr_cols)
    ffr_total = sum(awards[1, c] for c in ffr_cols)
    # The group demand is met by the cheap sub-service; the prohibitively priced sub-service
    # clears essentially nothing even though both sub-services share the same devices and caps.
    @test pfr_total > 1.0
    @test ffr_total <= 1e-2
    @test pfr_total > ffr_total
end

@testset "GroupStepwiseReserveCurve: no group -> no procurement (group is the demand driver)" begin
    # Same system, but the group is left OUT of the template. The sub-services have requirement 0
    # and costly offers, so with no group demand the model procures no reserve at all - confirming
    # the group ASDC is what drives sub-service procurement.
    sys, pfr, ffr, group = build_group_reserve_system()
    model = DecisionModel(
        _group_reserve_template(; include_group = false), sys;
        optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__ConstantReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    sub_cols = [_sub_cols(awards, "RRS_PFR__"); _sub_cols(awards, "RRS_FFR__")]
    for t in 1:24, c in sub_cols
        @test awards[t, c] <= 1e-2
    end
end
