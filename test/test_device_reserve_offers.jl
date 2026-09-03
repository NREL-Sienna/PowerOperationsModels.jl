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
            PSY.get_value_curve(PSY.get_variable_operation_cost(get_operation_cost(g))),
        )
        set_operation_cost!(
            g,
            MarketBidCost(;
                minimum_energy_offer = LinearCurve(0.0),
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
    reserve = get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
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
    reserve = get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    contributors, base_slope = add_device_reserve_offers!(sys, reserve)

    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # The reserve award exists, keyed by service type.
    @test IOM.has_container_key(
        container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})

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
        IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
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
    ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys))
    # Ensure thermal devices contribute to the operating reserve demand curve (ORDC) so they
    # can carry per-device offers.
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    contributors, base_slope = add_device_reserve_offers!(sys, ordc)

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve))
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
        PSY.get_value_curve(PSY.get_variable_operation_cost(get_operation_cost(g))))
    set_operation_cost!(
        g,
        MarketBidCost(;
            minimum_energy_offer = LinearCurve(0.0),
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
    ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys))
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
        template, ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
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
    ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys))
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    # No add_device_reserve_offers! call: no device carries an AS offer.

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve))
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
    ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys))
    for g in get_components(ThermalStandard, sys)
        ordc in PSY.get_services(g) || PSY.add_service!(g, ordc, sys)
    end
    # Every contributor offers, priced cheap -> pricey by index; `base_slope` maps device name to
    # its first-segment offer price ($/MWh).
    _, base_slope = add_device_reserve_offers!(sys, ordc)

    template = get_thermal_standard_uc_template()
    set_service_model!(
        template, ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
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

@testset "Reserve-offer predicate excludes ImportExport costs (no get_services_bid MethodError)" begin
    # `_cost_offers_reserve` decides whether a contributing device offers into a reserve. It must
    # gate on the MarketBidCost types that `get_services_bid` supports, NOT the abstract
    # OfferCurveCost: ImportExportCost is also an OfferCurveCost with an `ancillary_service_offers`
    # field but is not handled by `get_services_bid`, so an ImportExport-cost device (e.g. a Source)
    # carrying a reserve offer must NOT enter the offering branch - which would MethodError.
    # Regression for the previously over-broad OfferCurveCost dispatch.
    reserve = PSY.OnlineReserve{ReserveUp}("iec_regression", true, 10.0, 1.0)

    iec = PSY.ImportExportCost(nothing)
    @test POM._cost_offers_reserve(iec, reserve) == false
    # An ImportExport cost resolves to the `OperationalCost` false fallback, not a path that would
    # reach get_services_bid.
    @test which(POM._cost_offers_reserve, Tuple{typeof(iec), typeof(reserve)}) ===
          which(POM._cost_offers_reserve, Tuple{PSY.OperationalCost, typeof(reserve)})

    # A MarketBidCost carrying the reserve in its offers is still recognized as offering.
    mbc = MarketBidCost(;
        minimum_energy_offer = LinearCurve(0.0),
        start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
        shut_down = LinearCurve(0.0),
    )
    push!(PSY.get_ancillary_service_offers(mbc), reserve)
    @test POM._cost_offers_reserve(mbc, reserve) == true
end

#################################################################################
# End-to-end energy + reserve co-clearing: an elastic reserve (demand curve under
# StepwiseCostReserve), an elastic group (GroupStepwiseCostReserve) over two supply-only
# sub-services, and per-resource offers from both generators and a controllable load. The
# load's cheap block into GROUP_SUB_A is deliberately the cheapest in the stack, so it must
# clear in full and stay bounded by its offered quantity, not its consumption.
#################################################################################

const _MKT_INIT_TIMES =
    [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]
const _MKT_LOAD = "IloadBus4"

_mkt_offer_ts(svc, mw, price) = Deterministic(
    PSY.get_name(svc),
    Dict(
        it => [IS.PiecewiseStepData([0.0, mw], [price]) for _ in 1:24] for
        it in _MKT_INIT_TIMES
    ),
    Hour(1),
)

_mkt_curve(x, y) = make_market_bid_curve(x, y, 0.0; power_units = IS.NaturalUnit())

function build_reserve_market_system(; load_offer_mw = 10.0, load_offer_price = 4.0)
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = false))
    thermals = collect(get_components(ThermalStandard, sys))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _MKT_LOAD)

    elastic = OnlineReserve{ReserveUp}(;
        name = "ELASTIC_UP",
        available = true,
        time_frame = 5.0,
        variable = _mkt_curve([0.0, 200.0, 400.0], [80.0, 15.0]),
    )
    add_service!(sys, elastic, thermals)

    sub_a = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_A", available = true, time_frame = 3600.0, requirement = 0.0)
    sub_b = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_B", available = true, time_frame = 3600.0, requirement = 0.0)
    add_service!(sys, sub_a, vcat(PSY.Device[thermals...], il))
    add_service!(sys, sub_b, thermals)

    group = GroupReserve{ReserveUp}(;
        name = "UP_GROUP",
        available = true,
        requirement = 0.0,
        variable = _mkt_curve([0.0, 150.0, 300.0], [70.0, 12.0]),
        contributing_services = Service[sub_a, sub_b],
    )
    add_service!(sys, group)

    # Generators: energy at each unit's own marginal cost, flat AS offers into all three
    # up-products with per-unit prices.
    for (i, g) in enumerate(thermals)
        pmax = PSY.get_max_active_power(g, PSY.NU)
        energy_slope = PSY.get_proportional_term(
            PSY.get_value_curve(PSY.get_variable_operation_cost(get_operation_cost(g))),
        )
        set_operation_cost!(
            g,
            MarketBidCost(;
                minimum_energy_offer = LinearCurve(0.0),
                start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = _mkt_curve([0.0, pmax], [energy_slope]),
            ),
        )
        for (svc, mw, price) in (
            (elastic, 30.0, 8.0 + i),
            (sub_a, 25.0, 5.0 + i),
            (sub_b, 20.0, 6.0 + i),
        )
            PSY.set_service_bid!(
                sys,
                g,
                svc,
                _mkt_offer_ts(svc, mw, price),
                IS.NaturalUnit(),
            )
        end
    end

    # Load: consumption valued at VOLL (consumes at forecast), plus one cheap block into
    # GROUP_SUB_A - the cheapest offer in the whole stack.
    pmax_il = PSY.get_max_active_power(il, PSY.NU)
    set_operation_cost!(
        il,
        MarketBidCost(;
            minimum_energy_offer = LinearCurve(0.0),
            start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            decremental_offer_curves = _mkt_curve([0.0, pmax_il], [5000.0]),
        ),
    )
    PSY.set_service_bid!(
        sys, il, sub_a, _mkt_offer_ts(sub_a, load_offer_mw, load_offer_price),
        IS.NaturalUnit(),
    )
    return sys
end

function _reserve_market_template()
    template = get_thermal_standard_uc_template()
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    # ONE up-reserve model: the elastic service carries its curve; the curve-less,
    # zero-requirement sub-services fall through to supply-only under the skip-gate.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupStepwiseCostReserve),
    )
    return template
end

@testset "Combined clearing: elastic reserve + elastic group + gen/load offers" begin
    sys = build_reserve_market_system()
    model = DecisionModel(
        _reserve_market_template(), sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    # Per-resource offer machinery fired for both device classes.
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard,
    )
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, PSY.InterruptiblePowerLoad,
    )

    res = IOM.OptimizationProblemOutputs(model)
    elastic_dem = read_variable(
        res, "ServiceRequirementVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    group_dem = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_cols = [c for c in names(awards) if startswith(c, "GROUP_SUB_")]
    load_col = "GROUP_SUB_A__$(_MKT_LOAD)"
    @test load_col in names(awards)

    load_offer = 10.0
    for t in 1:24
        # Both elastic demands clear.
        @test elastic_dem[t, "ELASTIC_UP"] > 1.0
        @test group_dem[t, "UP_GROUP"] > 1.0
        # Group aggregation: member awards cover the group demand.
        @test sum(awards[t, c] for c in sub_cols) ≈ group_dem[t, "UP_GROUP"] atol = 1e-3
        # The load's award is bounded by its offered quantity, not its ~100 MW consumption,
        # and the cheapest block clears in full.
        @test awards[t, load_col] <= load_offer + 1e-3
        @test awards[t, load_col] >= load_offer - 1e-2
    end
end

@testset "OfflineReserve as ORDC: load and generator supply" begin
    sys = build_reserve_market_system()
    thermals = collect(get_components(ThermalStandard, sys))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _MKT_LOAD)
    nspin = OfflineReserve(;
        name = "NSPIN",
        available = true,
        time_frame = 30.0,
        variable = _mkt_curve([0.0, 100.0, 200.0], [65.0, 11.0]),
    )
    add_service!(sys, nspin, vcat(PSY.Device[thermals...], il))
    # Every participant carries an offer: an un-offered contributor supplies for free and
    # would crowd out the load's priced block.
    for (i, g) in enumerate(thermals)
        PSY.set_service_bid!(
            sys, g, nspin, _mkt_offer_ts(nspin, 30.0, 6.0 + i), IS.NaturalUnit(),
        )
    end
    nspin_offer = 8.0
    PSY.set_service_bid!(
        sys, il, nspin, _mkt_offer_ts(nspin, nspin_offer, 3.0), IS.NaturalUnit(),
    )

    template = _reserve_market_template()
    set_service_model!(template, ServiceModel(OfflineReserve, StepwiseCostReserve))
    model = DecisionModel(
        template, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__OfflineReserve";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OfflineReserve";
        table_format = TableFormat.WIDE,
    )
    load_col = "NSPIN__$(_MKT_LOAD)"
    @test load_col in names(awards)
    for t in 1:24
        @test demand[t, "NSPIN"] > 1.0
        # The load's cheapest-in-stack block clears in full and stays offer-bounded: its
        # non-spin award rides the same shed-headroom (LB) routing as any up reserve.
        @test awards[t, load_col] <= nspin_offer + 1e-3
        @test awards[t, load_col] >= nspin_offer - 1e-2
    end
end

# `c_sys5_uc` promoted to MarketBidCost with an OfflineReserve ORDC ("NSPIN") and an
# OnlineReserve ("SPIN"). The returned `offunit` is priced out of the energy stack -
# prohibitive slope and startup - so the UC leaves it OFF while its cheap offline offer
# still clears. Shared by the standard-UC and compact-UC offline-capability testsets.
function _offline_ordc_uc_system()
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"))
    thermals = collect(get_components(ThermalStandard, sys))
    # Make one unit uneconomical for energy so the UC leaves it OFF; its cheap offline
    # offer must clear regardless.
    offunit = first(sort(thermals; by = PSY.get_name))
    # Service bids require an OfferCurveCost: convert every thermal to a MarketBidCost that
    # keeps its energy slope; the off-unit gets a prohibitive slope + startup so the UC
    # never commits it for energy.
    for g in thermals
        pmax_g = PSY.get_max_active_power(g, PSY.NU)
        slope = if g === offunit
            1.0e4
        else
            PSY.get_proportional_term(
                PSY.get_value_curve(PSY.get_variable_operation_cost(get_operation_cost(g))),
            )
        end
        PSY.set_operation_cost!(
            g,
            MarketBidCost(;
                minimum_energy_offer = LinearCurve(0.0),
                start_up = (
                    hot = g === offunit ? 1.0e5 : 0.0,
                    warm = g === offunit ? 1.0e5 : 0.0,
                    cold = g === offunit ? 1.0e5 : 0.0,
                ),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = make_market_bid_curve(
                    [0.0, pmax_g], [slope], 0.0; power_units = IS.NaturalUnit(),
                ),
            ),
        )
    end
    nspin = OfflineReserve(;
        name = "NSPIN",
        available = true,
        time_frame = 30.0,
        variable = _mkt_curve([0.0, 100.0, 200.0], [65.0, 11.0]),
    )
    spin = OnlineReserve{ReserveUp}(;
        name = "SPIN", available = true, time_frame = 10.0, requirement = 0.0,
        variable = _mkt_curve([0.0, 50.0], [40.0]),
    )
    add_service!(sys, nspin, PSY.Device[thermals...])
    add_service!(sys, spin, PSY.Device[thermals...])
    for (i, g) in enumerate(thermals)
        price = g === offunit ? 0.01 : 6.0 + i
        PSY.set_service_bid!(
            sys,
            g,
            nspin,
            _mkt_offer_ts(nspin, 80.0, price),
            IS.NaturalUnit(),
        )
        PSY.set_service_bid!(
            sys,
            g,
            spin,
            _mkt_offer_ts(spin, 30.0, price),
            IS.NaturalUnit(),
        )
    end
    return sys, offunit
end

"""
Assert the offline band row exists for every contributing device and carries the
formulation's gating. The row is built as
`expression + Σ offline <= q_limit - (q_limit - gated) * u`; JuMP normalizes the `u`
term onto the LHS, so the row reads `normalized_rhs == pmax` with coefficient
`pmax - gated` on `u`. `expected_u_coefficient(limits)` is the independent
reference: `0.0` for standard UC (RHS collapses to `pmax` regardless of `u`) and
`limits.min` for compact UC (RHS becomes `pmax - pmin * u`). A must-run device has no
`OnVariable`, so its row is the gated capacity outright.
"""
function _check_offline_band(
    container, sys, device_type, expected_u_coefficient, service_name,
)
    con = IOM.get_constraint(container, POM.OfflineReserveBandConstraint, device_type)
    varbin = IOM.get_variable(container, POM.OnVariable, device_type)
    awards = IOM.get_variable(container, POM.ActivePowerReserveVariable, OfflineReserve)
    checked = 0
    for (idx, c) in con.data
        name, t = idx
        d = get_component(device_type, sys, name)
        limits = PSY.get_active_power_limits(d, PSY.SU)
        u_coefficient = expected_u_coefficient(limits)
        if PSY.get_must_run(d)
            @test JuMP.normalized_rhs(c) ≈ limits.max - u_coefficient
        else
            @test JuMP.normalized_rhs(c) ≈ limits.max
            @test JuMP.normalized_coefficient(c, varbin[name, t]) ≈ u_coefficient
        end
        # The offline award enters the row with a +1 coefficient; without it the row
        # would be the plain semicontinuous band and prove nothing.
        @test JuMP.normalized_coefficient(c, awards[(service_name, name, t)]) ≈ 1.0
        checked += 1
    end
    @test checked > 0
    return
end

@testset "OfflineReserve as ORDC: OFF unit provides offline capability (UC)" begin
    # Single-award-variable offline design: the UB expression keeps p + online
    # commitment-gated (offline_reserve_in_range_ub = false for every thermal UC); the
    # band row adds the offline awards back, against q_limit = pmax for standard UC, so
    # an OFF unit's offline capability survives.
    sys, offunit = _offline_ordc_uc_system()

    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(OfflineReserve, StepwiseCostReserve))
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    model = DecisionModel(
        template, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    on = read_variable(res, OnVariable, ThermalStandard; table_format = TableFormat.WIDE)
    nspin_awards = read_variable(
        res, "ActivePowerReserveVariable__OfflineReserve";
        table_format = TableFormat.WIDE,
    )
    spin_awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    # Standard UC: the band row is `p + online + offline <= pmax` for every t, so the
    # coefficient on `u` is exactly zero. This gates the row's existence and its RHS -
    # the surviving solve assertions below do not, since each award is separately capped
    # by its own variable bound.
    _check_offline_band(
        IOM.get_optimization_container(model),
        sys,
        ThermalStandard,
        limits -> 0.0,
        "NSPIN",
    )

    off_name = PSY.get_name(offunit)
    total_off_award = 0.0
    for t in 1:24
        @test on[t, off_name] < 0.5                        # stays uncommitted
        @test spin_awards[t, "SPIN__$(off_name)"] <= 1e-3   # online award dead when OFF
        total_off_award += nspin_awards[t, "NSPIN__$(off_name)"]
    end
    # The cheapest offline offer in the stack clears from the OFF unit: the trait exclusion
    # kept the offline award out of the commitment-gated UB expression.
    @test total_off_award > 1.0

    # Zero-footprint: without an OfflineReserve service model, none of the offline
    # machinery exists - no online-only expression, no band constraint.
    template2 = get_thermal_standard_uc_template()
    set_service_model!(
        template2,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    model2 = DecisionModel(
        template2, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model2; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container2 = IOM.get_optimization_container(model2)
    @test all(
        k -> IOM.get_entry_type(k) != POM.OfflineReserveBandConstraint,
        keys(IOM.get_constraints(container2)),
    )
end

@testset "OfflineReserve as ORDC: compact UC gates the band on pmin" begin
    # Compact UC dispatches PowerAboveMinimumVariable, a delta above pmin, so the band row
    # must gate on the formulation's own capacity rather than on pmax:
    # `p + online + offline <= (pmax - pmin) * u + pmax * (1 - u)`.
    # Committed that is `pmax - pmin` - total output pmin + p + awards stays inside pmax.
    # OFF, the semicontinuous row zeroes p and the online awards, leaving `offline <= pmax`,
    # so the unit keeps its offline capability. Reusing standard UC's flat pmax RHS here
    # would let a committed unit award pmin beyond its own capability.
    for formulation in (ThermalCompactUnitCommitment, ThermalBasicCompactUnitCommitment)
        sys, offunit = _offline_ordc_uc_system()
        # The pmin gating term is only observable if some unit actually has a nonzero pmin.
        @test any(
            d -> PSY.get_active_power_limits(d, PSY.SU).min > 0.0,
            get_components(ThermalStandard, sys),
        )

        template = get_thermal_standard_uc_template()
        set_device_model!(template, ThermalStandard, formulation)
        set_service_model!(template, ServiceModel(OfflineReserve, StepwiseCostReserve))
        set_service_model!(
            template,
            ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
        )
        model = DecisionModel(
            template, sys;
            optimizer = HiGHS_optimizer, store_variable_names = true,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        _check_offline_band(
            IOM.get_optimization_container(model),
            sys,
            ThermalStandard,
            limits -> limits.min,
            "NSPIN",
        )
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res = IOM.OptimizationProblemOutputs(model)
        on = read_variable(
            res, OnVariable, ThermalStandard; table_format = TableFormat.WIDE,
        )
        # Compact UC dispatches the delta above pmin, not total power.
        power = read_variable(
            res, PowerAboveMinimumVariable, ThermalStandard;
            table_format = TableFormat.WIDE,
        )
        nspin_awards = read_variable(
            res, "ActivePowerReserveVariable__OfflineReserve";
            table_format = TableFormat.WIDE,
        )
        spin_awards = read_variable(
            res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
            table_format = TableFormat.WIDE,
        )

        off_name = PSY.get_name(offunit)
        total_off_award = 0.0
        for t in 1:24
            @test on[t, off_name] < 0.5
            total_off_award += nspin_awards[t, "NSPIN__$(off_name)"]
        end
        # The OFF unit's offline capability survives under compact UC as well.
        @test total_off_award > 1.0

        # Solved solution honours the compact band on every committed unit: the delta power
        # plus all awards stay inside pmax - pmin.
        committed = 0
        for d in get_components(ThermalStandard, sys)
            name = PSY.get_name(d)
            name in names(on) || continue
            limits = PSY.get_active_power_limits(d, PSY.NU)
            for t in 1:24
                on[t, name] > 0.5 || continue
                committed += 1
                @test power[t, name] +
                      nspin_awards[t, "NSPIN__$(name)"] +
                      spin_awards[t, "SPIN__$(name)"] <=
                      limits.max - limits.min + 1e-3
            end
        end
        @test committed > 0
    end
end

@testset "OfflineReserve band: ThermalMultiStart under multistart UC" begin
    # `ThermalMultiStartUnitCommitment` is an AbstractCompactUnitCommitment, so its band
    # gates on pmin like the other compact formulations - but it reaches the row through
    # its own construct_device! pair and its own device type, which nothing else covers.
    #
    # The offline service must use StepwiseCostReserve, not NonSpinningReserve: the latter
    # routes awards through ReservePowerConstraint and deliberately does not register
    # itself on device models (`_modify_device_model!` no-op), so it builds no band row.
    #
    # `c_sys5_pglib` carries the two ThermalMultiStart units and no services of its own,
    # so the ORDC below is the only offline product in the model.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_pglib"))
    multistarts = collect(get_components(PSY.ThermalMultiStart, sys))
    @test !isempty(multistarts)
    # pmin must be nonzero for the compact gating term to be observable at all.
    @test all(d -> PSY.get_active_power_limits(d, PSY.SU).min > 0.0, multistarts)

    gens = vcat(collect(get_components(ThermalStandard, sys)), multistarts)
    # Service bids require an OfferCurveCost on every contributor.
    for g in gens
        pmax = PSY.get_active_power_limits(g, PSY.NU).max
        PSY.set_operation_cost!(
            g,
            MarketBidCost(;
                minimum_energy_offer = LinearCurve(0.0),
                start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = _mkt_curve([0.0, pmax], [25.0]),
            ),
        )
    end
    nspin = OfflineReserve(;
        name = "NSPIN",
        available = true,
        time_frame = 30.0,
        variable = _mkt_curve([0.0, 100.0, 200.0], [65.0, 11.0]),
    )
    add_service!(sys, nspin, PSY.Device[gens...])
    for (i, g) in enumerate(gens)
        pmax = PSY.get_active_power_limits(g, PSY.NU).max
        PSY.set_service_bid!(
            sys, g, nspin, _mkt_offer_ts(nspin, pmax, 5.0 + i), IS.NaturalUnit(),
        )
    end

    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(
        template,
        DeviceModel(PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment),
    )
    set_service_model!(template, ServiceModel(OfflineReserve, StepwiseCostReserve))
    model = DecisionModel(
        template, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    # pmin is the compact gating term for the multistart device type too.
    _check_offline_band(
        IOM.get_optimization_container(model),
        sys,
        PSY.ThermalMultiStart,
        limits -> limits.min,
        "NSPIN",
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    on = read_variable(
        res, OnVariable, PSY.ThermalMultiStart; table_format = TableFormat.WIDE,
    )
    power = read_variable(
        res, PowerAboveMinimumVariable, PSY.ThermalMultiStart;
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OfflineReserve";
        table_format = TableFormat.WIDE,
    )
    # Committed multistart units honour the compact band in the solved solution.
    committed = 0
    for d in multistarts
        name = PSY.get_name(d)
        name in names(on) || continue
        col = "NSPIN__$(name)"
        col in names(awards) || continue
        limits = PSY.get_active_power_limits(d, PSY.NU)
        for t in 1:24
            on[t, name] > 0.5 || continue
            committed += 1
            @test power[t, name] + awards[t, col] <= limits.max - limits.min + 1e-3
        end
    end
    @test committed > 0
end

#################################################################################
# Load reserve provision (PowerLoadDispatch)
#################################################################################

# Load reserve provision (`PowerLoadDispatch`): a controllable load provides UPWARD reserve
# by shedding (`P - r_up >= 0`, awards capped by consumption) and DOWNWARD reserve by
# consuming more (`P + r_down <= forecast`). `c_sys5_il`'s single interruptible load
# `IloadBus4` is the sole contributor to Reserve7 (up), Reserve8 (down) and ORDC1 (up,
# demand curve); the requirements exceed the load, so requirement models use slacks.

const _IL_NAME = "IloadBus4"

function _load_reserve_template(direction::Symbol)
    template = get_thermal_dispatch_template_network()
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    direction === :up && set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve; use_slacks = true),
    )
    direction === :down && set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve; use_slacks = true),
    )
    return template
end

function _solve_load_model(template, sys)
    model = DecisionModel(
        template, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    return model
end

_il_cols(df) = [c for c in names(df) if endswith(c, "__$(_IL_NAME)")]

@testset "Load reserve direction map + folding methods" begin
    @test POM.get_expression_type_for_reserve(
        ActivePowerReserveVariable, PSY.InterruptiblePowerLoad, OnlineReserve{ReserveUp},
    ) == POM.ActivePowerRangeExpressionLB
    @test POM.get_expression_type_for_reserve(
        ActivePowerReserveVariable, PSY.InterruptiblePowerLoad, OnlineReserve{ReserveDown},
    ) == POM.ActivePowerRangeExpressionUB
end

@testset "UP-reserve: award capped by consumption (shed headroom)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    model = _solve_load_model(_load_reserve_template(:up), sys)
    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionLB, PSY.InterruptiblePowerLoad,
    )
    res = IOM.OptimizationProblemOutputs(model)
    p = read_variable(
        res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    total_award = 0.0
    for t in 1:24
        awarded = sum(awards[t, c] for c in _il_cols(awards))
        @test awarded <= p[t, _IL_NAME] + 1e-4
        @test p[t, _IL_NAME] - awarded >= -1e-4
        total_award += awarded
    end
    @test total_award > 1.0
end

@testset "DOWN-reserve: award within forecast headroom" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    pmax = PSY.get_max_active_power(il, PSY.NU)
    model = _solve_load_model(_load_reserve_template(:down), sys)
    res = IOM.OptimizationProblemOutputs(model)
    p = read_variable(
        res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveDown";
        table_format = TableFormat.WIDE,
    )
    hsl = read_parameter(
        res, "ActivePowerTimeSeriesParameter__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    total_award = 0.0
    for t in 1:24
        awarded = sum(awards[t, c] for c in _il_cols(awards))
        @test awarded >= -1e-4
        @test p[t, _IL_NAME] + awarded <= hsl[t, _IL_NAME] + 1e-3
        @test p[t, _IL_NAME] + awarded <= pmax + 1e-3
        total_award += awarded
    end
    @test total_award > 1.0
end

@testset "VOLL-priced load: pinned at forecast, full up-shed, zero down" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    set_operation_cost!(
        il,
        PSY.LoadCost(PSY.CostCurve(PSY.LinearCurve(5000.0, 0.0), IS.NaturalUnit()), 24.0),
    )
    template = _load_reserve_template(:up)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve; use_slacks = true),
    )
    model = _solve_load_model(template, sys)
    res = IOM.OptimizationProblemOutputs(model)
    p = read_variable(
        res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    up = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    dn = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveDown";
        table_format = TableFormat.WIDE,
    )
    hsl = read_parameter(
        res, "ActivePowerTimeSeriesParameter__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    up_total = 0.0
    for t in 1:24
        @test isapprox(p[t, _IL_NAME], hsl[t, _IL_NAME]; atol = 1e-1)
        up_t = sum(up[t, c] for c in _il_cols(up))
        @test isapprox(up_t, p[t, _IL_NAME]; atol = 1e-1)
        @test sum(dn[t, c] for c in _il_cols(dn)) <= 1e-2
        up_total += up_t
    end
    @test up_total > 1.0
end

@testset "No-reserve regression: pure-energy path unchanged" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = false))
    model = _solve_load_model(_load_reserve_template(:none), sys)
    container = IOM.get_optimization_container(model)
    @test !IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionLB, PSY.InterruptiblePowerLoad,
    )
    @test !IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionUB, PSY.InterruptiblePowerLoad,
    )
end

# An unoffered (costless) load is not in the energy market: its dispatch is pinned at zero
# and its limits set the up-reserve range (the ERCOT AS-only interruptible load).
function _assert_unoffered_load_pinned(sys)
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    model = DecisionModel(
        _load_reserve_template(:up), sys;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    p = IOM.get_variable(container, ActivePowerVariable, PSY.InterruptiblePowerLoad)
    lb = IOM.get_expression(
        container, POM.ActivePowerRangeExpressionLB, PSY.InterruptiblePowerLoad,
    )
    for t in get_time_steps(container)
        @test JuMP.upper_bound(p[_IL_NAME, t]) == 0.0
        @test JuMP.coefficient(lb[_IL_NAME, t], p[_IL_NAME, t]) == 0.0
        @test JuMP.constant(lb[_IL_NAME, t]) == PSY.get_max_active_power(il, PSY.SU)
    end
    return
end

@testset "Costless load offering reserves is pinned at zero with its limits as reserve range" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    set_operation_cost!(il, PSY.LoadCost(nothing))
    _assert_unoffered_load_pinned(sys)
end

@testset "Costless market-bid load offering reserves is pinned at zero" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    set_operation_cost!(il, MarketBidCost())
    _assert_unoffered_load_pinned(sys)
end

@testset "Co-provision: two up-services share one shed headroom" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    set_operation_cost!(
        il,
        PSY.LoadCost(PSY.CostCurve(PSY.LinearCurve(5000.0, 0.0), IS.NaturalUnit()), 24.0),
    )
    # A second requirement reserve on the same load; both clear under ONE per-type model.
    second = OnlineReserve{ReserveUp}("Reserve7B", true, 30.0, 100.0)
    add_service!(sys, second, [il])
    model = _solve_load_model(_load_reserve_template(:up), sys)
    res = IOM.OptimizationProblemOutputs(model)
    p = read_variable(
        res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    combined_total = 0.0
    for t in 1:24
        # One shared LB expression: a per-service headroom bug would allow up to 2*P.
        combined = awards[t, "Reserve7__$(_IL_NAME)"] + awards[t, "Reserve7B__$(_IL_NAME)"]
        @test combined <= p[t, _IL_NAME] + 1e-3
        combined_total += combined
    end
    @test combined_total > 1.0
end

@testset "Load offers into an elastic reserve: award bounded by the offer" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = get_component(PSY.InterruptiblePowerLoad, sys, _IL_NAME)
    pmax = PSY.get_max_active_power(il, PSY.NU)
    ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys))
    offer_mw = 10.0
    set_operation_cost!(
        il,
        MarketBidCost(;
            minimum_energy_offer = LinearCurve(0.0),
            start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            decremental_offer_curves = make_market_bid_curve(
                [0.0, pmax], [5000.0], 0.0; power_units = IS.NaturalUnit(),
            ),
        ),
    )
    offer_ts = Deterministic(
        PSY.get_name(ordc),
        Dict(
            it => [IS.PiecewiseStepData([0.0, offer_mw], [0.0]) for _ in 1:24] for
            it in [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]
        ),
        Hour(1),
    )
    PSY.set_service_bid!(sys, il, ordc, offer_ts, IS.NaturalUnit())

    template = get_thermal_dispatch_template_network()
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    model = _solve_load_model(template, sys)
    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, PSY.InterruptiblePowerLoad,
    )
    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    col = "$(PSY.get_name(ordc))__$(_IL_NAME)"
    total = 0.0
    for t in 1:24
        @test awards[t, col] <= offer_mw + 1e-3
        total += awards[t, col]
    end
    # The zero-priced block clears against the elastic demand.
    @test total > 1.0
end
