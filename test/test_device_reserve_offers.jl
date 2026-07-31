# Per-device ancillary-service (reserve) OFFERS.
#
# A device can submit a price/quantity OFFER curve for providing a reserve service, stored via
# the PSY `set_service_bid!` path: a `PiecewiseStepData` time series named after the service,
# attached to the device (whose operation cost must be an `OfferCurveCost`), plus service
# membership in `MarketBidCost.ancillary_service_offers`. Retrieval is `get_services_bid`.
#
# This is the (service, device, segment, time) 4D cost structure: one PWL offer per
# (device, service) per hour. The reserve AWARD (`ActivePowerReserveVariable`) is already keyed
# `(service, device, time)`; `add_reserve_offer_costs!` prices it by these per-device offers
# (instead of the flat `DEFAULT_RESERVE_COST`). These tests pin the DATA MODEL and assert the
# consumer builds the 4D block variable, the award-linking constraint, and the offer-slope cost.

# Give every contributing thermal device of `reserve` a MarketBidCost with an energy offer and a
# per-device reserve OFFER curve (PiecewiseStepData, NaturalUnit) named after the service.
function add_device_reserve_offers!(
    sys,
    reserve;
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")],
    horizon = 24,
    resolution = Hour(1),
)
    contributors =
        [d for d in get_components(ThermalStandard, sys) if reserve in PSY.get_services(d)]
    @assert !isempty(contributors) "reserve has no thermal contributors"
    offer_curve(price) = IS.PiecewiseStepData([0.0, 50.0, 100.0], [price, price * 1.5])
    # device name -> first-segment offer slope ($/MWh, natural units); segment 2 is 1.5x it.
    base_slope = Dict{String, Float64}()
    for (i, g) in enumerate(contributors)
        pmax = PSY.get_max_active_power(g, PSY.NU)
        # Keep the unit's own marginal energy cost: read the proportional (linear) term of its
        # existing variable cost before overwriting, and use it as the single-block energy offer.
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
        price = 8.0 + 2.0 * i
        base_slope[PSY.get_name(g)] = price
        data = Dict(it => [offer_curve(price) for _ in 1:horizon] for it in init_times)
        ts = Deterministic(PSY.get_name(reserve), data, resolution)
        PSY.set_service_bid!(sys, g, reserve, ts, IS.NaturalUnit())
    end
    return contributors, base_slope
end

@testset "Per-device reserve offers: data model" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    reserve = get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
    contributors, _ = add_device_reserve_offers!(sys, reserve)

    # Each contributor now bids into the service and exposes a per-(device, service) offer curve.
    for g in contributors
        cost = get_operation_cost(g)
        @test cost isa PSY.OfferCurveCost
        @test reserve in PSY.get_ancillary_service_offers(cost)
        bid = PSY.get_services_bid(g, cost, reserve; len = 1)
        # Per-timestep CostCurve{PiecewiseIncrementalCurve} - the PWL offer for this device.
        @test eltype(values(bid)) <: PSY.CostCurve
    end
    # The device axis of the 4D (service, device, segment, time): every contributor offers.
    @test length(contributors) ==
          count(g -> reserve in PSY.get_ancillary_service_offers(get_operation_cost(g)),
        get_components(ThermalStandard, sys))
end

@testset "Per-device reserve offers: builds, solves, and prices the offers" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    reserve = get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
    contributors, base_slope = add_device_reserve_offers!(sys, reserve)

    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # The reserve award exists, keyed by service type.
    @test IOM.has_container_key(
        container, ActivePowerReserveVariable, VariableReserve{ReserveUp})

    # The per-device reserve OFFER is now consumed: a 4D block variable keyed
    # (service, device, segment, time) exists for the contributing device type, plus the
    # linking constraint that ties each device's segments to its reserve award.
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    @test IOM.has_container_key(
        container, POM.ReserveOfferLinkingConstraint, ThermalStandard)
    blk = IOM.get_variable(container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    cons = IOM.get_constraint(container, POM.ReserveOfferLinkingConstraint, ThermalStandard)
    award =
        IOM.get_variable(container, ActivePowerReserveVariable, VariableReserve{ReserveUp})
    @test !isempty(blk)

    sname = PSY.get_name(reserve)
    obj = JuMP.objective_function(IOM.get_jump_model(container))
    base_p = IOM.get_model_base_power(container)
    dt = 1.0  # Hour(1) resolution -> 1 hour per step
    for g in contributors
        gname = PSY.get_name(g)
        # Both offer segments ([0,50,100] breakpoints -> 2 segments) are present at t = 1.
        seg1 = blk[(sname, gname, 1, 1)]
        seg2 = blk[(sname, gname, 2, 1)]
        # Independent magnitude check. The award delta is in system pu; the offer slope is in
        # natural units ($/MWh). Cost = slope * (delta_pu * base_p) * dt, so the objective
        # coefficient on delta_pu is slope * base_p * dt. Segment 2's slope is 1.5x segment 1's.
        slope1 = base_slope[gname]
        @test JuMP.coefficient(obj, seg1) ≈ slope1 * base_p * dt
        @test JuMP.coefficient(obj, seg2) ≈ 1.5 * slope1 * base_p * dt
        # Linking constraint sum(segments) == award: normalized to sum(delta) - award == 0.
        lc = cons[(sname, gname, 1)]
        @test JuMP.normalized_coefficient(lc, seg1) ≈ 1.0
        @test JuMP.normalized_coefficient(lc, seg2) ≈ 1.0
        @test JuMP.normalized_coefficient(lc, award[(sname, gname, 1)]) ≈ -1.0
    end
end

@testset "StepwiseCostReserve prices per-device reserve offers (demand curve + offer supply)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    ordc = first(get_components(PSY.ReserveDemandCurve, sys))
    # Ensure thermal devices contribute to the ORDC so they can carry per-device offers.
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    contributors, base_slope = add_device_reserve_offers!(sys, ordc)

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # Supply offers are now consumed UNDER StepwiseCostReserve: the 4D block variable and the
    # award-linking constraint exist for the contributing device type. Before this change they
    # do NOT (StepwiseCostReserve priced only the demand curve).
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    @test IOM.has_container_key(
        container, POM.ReserveOfferLinkingConstraint, ThermalStandard)
    blk = IOM.get_variable(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    @test !isempty(blk)

    # The device's offer slope is a POSITIVE supply-cost coefficient on its block variable
    # (the ORDC demand curve prices the ServiceRequirementVariable separately, as a benefit).
    sname = PSY.get_name(ordc)
    obj = JuMP.objective_function(IOM.get_jump_model(container))
    base_p = IOM.get_model_base_power(container)
    for g in contributors
        gname = PSY.get_name(g)
        seg1 = blk[(sname, gname, 1, 1)]
        @test JuMP.coefficient(obj, seg1) ≈ base_slope[gname] * base_p * 1.0
    end
end

# Attach to device `g` a per-hour offer: hour 1 is a real cheap curve; every other hour is the
# inert dummy (0.01 MW at a high price) that the parser uses for non-participating hours.
function add_per_hour_reserve_offer!(
    sys, reserve, g;
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")],
    horizon = 24, resolution = Hour(1),
)
    pmax = PSY.get_max_active_power(g, PSY.NU)
    energy_slope = PSY.get_proportional_term(
        PSY.get_value_curve(PSY.get_variable(get_operation_cost(g))))
    set_operation_cost!(
        g,
        MarketBidCost(;
            no_load_cost = LinearCurve(0.0),
            start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            incremental_offer_curves = make_market_bid_curve(
                [0.0, pmax], [energy_slope], 0.0; power_units = IS.NaturalUnit()),
        ),
    )
    real_curve = IS.PiecewiseStepData([0.0, 50.0], [5.0])       # hour 1: cheap, 50 MW at $5
    dummy_curve = IS.PiecewiseStepData([0.0, 0.01], [9000.0])   # else: 0.01 MW at high price
    per_hour = [h == 1 ? real_curve : dummy_curve for h in 1:horizon]
    ts = Deterministic(
        PSY.get_name(reserve),
        Dict(it => per_hour for it in init_times),
        resolution,
    )
    PSY.set_service_bid!(sys, g, reserve, ts, IS.NaturalUnit())
    return g
end

@testset "StepwiseCostReserve: per-hour offer participation (dummy hours not awarded)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    ordc = first(get_components(PSY.ReserveDemandCurve, sys))
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    # Attach the per-hour offer to ONE device only (avoids re-attaching a service-named time
    # series). The other contributors carry no offer, so only g1 gets the offer cap; g1's dummy
    # hours are capped at 0.01 MW regardless of what the other (free) devices do.
    g1 = first(get_components(ThermalStandard, sys))
    add_per_hour_reserve_offer!(sys, ordc, g1)

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__ReserveDemandCurve__ReserveUp";
        table_format = TableFormat.WIDE)
    # WIDE columns are "<service>__<device>"; values are per-hour reserve awards in MW.
    col = "$(PSY.get_name(ordc))__$(PSY.get_name(g1))"
    # The linking constraint caps g1's award at the offered MW each hour; in a dummy hour that cap
    # is 0.01 MW, so the award there is negligible regardless of the demand.
    for t in 2:24
        @test awards[t, col] <= 0.05
    end
end

@testset "StepwiseCostReserve: no device offers -> no offer containers (ORDC unchanged)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    ordc = first(get_components(PSY.ReserveDemandCurve, sys))
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    # No add_device_reserve_offers! call: no device carries an AS offer.

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # add_reserve_offer_costs! is a no-op with no offers: the block var / linking constraint are
    # never created, so supply stays free exactly as in the pre-change ORDC formulation.
    @test !IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    @test !IOM.has_container_key(
        container, POM.ReserveOfferLinkingConstraint, ThermalStandard)
end

@testset "StepwiseCostReserve: merit order (cheaper offer clears, pricier does not)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    ordc = first(get_components(PSY.ReserveDemandCurve, sys))
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    # Every contributor offers, priced cheap -> pricey by index; `base_slope` maps device name to
    # its first-segment offer price ($/MWh).
    _, base_slope = add_device_reserve_offers!(sys, ordc)

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__ReserveDemandCurve__ReserveUp";
        table_format = TableFormat.WIDE)
    sname = PSY.get_name(ordc)
    order = sort(collect(keys(base_slope)); by = n -> base_slope[n])
    cheapest, priciest = first(order), last(order)
    # WIDE columns are "<service>__<device>"; values are per-hour reserve awards in MW.
    a_cheap = awards[1, "$(sname)__$(cheapest)"]
    a_pricey = awards[1, "$(sname)__$(priciest)"]
    # The elastic demand is met by the cheapest offers first: the cheapest device clears a
    # meaningful reserve award (MW), while the priciest device clears nothing even though it is not
    # the smallest-capacity unit -- price, not capacity, sets the reserve merit order.
    @test a_cheap > 1.0
    @test a_pricey <= 1e-2
    @test a_cheap > a_pricey
end
