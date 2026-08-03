# Combined ancillary-service clearing: exercises the full reserve stack together in ONE model -
# an elastic flat demand curve (`ReserveDemandCurve` + `StepwiseCostReserve`), an elastic GROUP
# demand over per-sub-type services (`ReserveDemandCurveGroup` + `GroupStepwiseReserveCurve`), all
# cleared against per-resource AS offers from BOTH thermal generators and a dispatchable load
# (`PowerLoadDispatch`). This mirrors a co-optimized energy+AS market where generators and load
# resources bid limited, priced AS quantities into elastic demand curves.
#
# Key property under test: a load valued at VOLL consumes at its forecast (HSL) but its reserve
# award is bounded by its OFFERED quantity (not its consumption), so a priced AS offer - not free
# shed room - determines how much reserve a load provides.

const _MKT_INIT_TIMES = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]

_mkt_asdc(bp, slopes) =
    make_market_bid_curve(bp, slopes, 0.0; power_units = IS.NaturalUnit())

# One flat AS offer curve (a single `mw`-wide block at `price`) as an hourly time series named after
# the service - the form `set_service_bid!` consumes.
function _mkt_offer_ts(svc, mw, price; horizon = 24)
    offer = IS.PiecewiseStepData([0.0, mw], [price])
    return Deterministic(PSY.get_name(svc),
        Dict(it => [offer for _ in 1:horizon] for it in _MKT_INIT_TIMES), Hour(1))
end

# Give a thermal generator a MarketBidCost (its own marginal energy offer) plus a flat AS offer into
# each service in `service_prices` (service => (mw, price)).
function _mkt_set_gen_offers!(sys, g, service_prices)
    pmax = PSY.get_max_active_power(g, PSY.NU)
    es = PSY.get_proportional_term(
        PSY.get_value_curve(PSY.get_variable(get_operation_cost(g))),
    )
    set_operation_cost!(
        g,
        MarketBidCost(;
            no_load_cost = LinearCurve(0.0), start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            incremental_offer_curves = make_market_bid_curve([0.0, pmax], [es], 0.0;
                power_units = IS.NaturalUnit())),
    )
    for (svc, (mw, price)) in service_prices
        PSY.set_service_bid!(sys, g, svc, _mkt_offer_ts(svc, mw, price), IS.NaturalUnit())
    end
end

# Give a controllable load a VOLL demand bid (so it consumes at HSL) plus a flat AS offer into each
# service. The demand bid is the DECREMENTAL (willingness-to-pay) side of the MarketBidCost.
function _mkt_set_load_offers!(sys, il, service_prices; voll = 5000.0)
    pmax = PSY.get_max_active_power(il, PSY.NU)
    set_operation_cost!(
        il,
        MarketBidCost(;
            no_load_cost = LinearCurve(0.0), start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            decremental_offer_curves = make_market_bid_curve([0.0, pmax], [voll], 0.0;
                power_units = IS.NaturalUnit())),
    )
    for (svc, (mw, price)) in service_prices
        PSY.set_service_bid!(sys, il, svc, _mkt_offer_ts(svc, mw, price), IS.NaturalUnit())
    end
end

# Build the combined market system: a flat REGUP demand curve (gen offers), and an RRS group demand
# over PFR/FFR sub-services (gen offers into both, and one cheap bounded load offer into PFR).
function build_reserve_market_system(; load_pfr_offer_mw = 10.0)
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = false))
    thermals = collect(get_components(ThermalStandard, sys))
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))

    regup = ReserveDemandCurve{ReserveUp}(;
        variable = _mkt_asdc([0.0, 200.0, 400.0], [80.0, 15.0]),
        name = "REGUP", available = true, time_frame = 5.0)
    pfr = ConstantReserve{ReserveUp}("RRS_PFR", true, 3600.0, 0.0)  # requirement 0: group drives it
    ffr = ConstantReserve{ReserveUp}("RRS_FFR", true, 3600.0, 0.0)
    add_service!(sys, regup, thermals)
    add_service!(sys, pfr, [thermals; il])   # the load contributes to PFR
    add_service!(sys, ffr, thermals)
    rrs = ReserveDemandCurveGroup{ReserveUp}(;
        variable = _mkt_asdc([0.0, 150.0, 300.0], [70.0, 12.0]),
        name = "RRS", available = true, time_frame = 5.0)
    add_service!(sys, rrs, PSY.Service[pfr, ffr])

    for (i, g) in enumerate(thermals)
        _mkt_set_gen_offers!(sys, g,
            Dict(regup => (30.0, 8.0 + i), pfr => (25.0, 5.0 + i), ffr => (20.0, 6.0 + i)))
    end
    # cheap, bounded load offer into PFR - the cheapest PFR block in the stack
    _mkt_set_load_offers!(sys, il, Dict(pfr => (load_pfr_offer_mw, 4.0)))
    return sys, regup, rrs, pfr, ffr, il, thermals
end

function _reserve_market_template()
    template = get_thermal_standard_uc_template()
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
    )
    set_service_model!(template, ServiceModel(ConstantReserve{ReserveUp}, RangeReserve))
    set_service_model!(template,
        ServiceModel(ReserveDemandCurveGroup{ReserveUp}, GroupStepwiseReserveCurve))
    return template
end

@testset "combined AS clearing: flat demand curve + group over sub-services + gen/load offers" begin
    load_offer = 10.0
    sys, regup, rrs, pfr, ffr, il, thermals =
        build_reserve_market_system(; load_pfr_offer_mw = load_offer)
    model = DecisionModel(_reserve_market_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # The per-resource AS offer machinery fired for BOTH generators and the load.
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, ThermalStandard)
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, PSY.InterruptiblePowerLoad)

    res = IOM.OptimizationProblemOutputs(model)
    iln = get_name(il)
    subaw = read_variable(res, "ActivePowerReserveVariable__ConstantReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    rrs_dem = read_variable(res,
        "ServiceRequirementVariable__ReserveDemandCurveGroup__ReserveUp";
        table_format = TableFormat.WIDE)
    regup_dem = read_variable(res,
        "ServiceRequirementVariable__ReserveDemandCurve__ReserveUp";
        table_format = TableFormat.WIDE)
    pfrcols = [c for c in names(subaw) if startswith(c, "RRS_PFR__")]
    ffrcols = [c for c in names(subaw) if startswith(c, "RRS_FFR__")]
    load_pfr = "RRS_PFR__$(iln)"

    for t in 1:size(regup_dem, 1)
        # both elastic demands clear a positive quantity against the offers
        @test regup_dem[t, "REGUP"] > 1.0
        @test rrs_dem[t, "RRS"] > 1.0
        # group aggregation: the sub-service awards sum to the group's elastic demand
        @test isapprox(sum(subaw[t, c] for c in [pfrcols; ffrcols]), rrs_dem[t, "RRS"];
            atol = 1e-3)
        # the load's RRS-PFR award is bounded by its 10 MW OFFER, not its ~87 MW consumption
        @test subaw[t, load_pfr] <= load_offer + 1e-3
    end
    # merit order: the load's cheap $4/MW PFR block is the cheapest in the stack, so it clears in full.
    @test all(subaw[t, load_pfr] >= load_offer - 1e-2 for t in 1:size(regup_dem, 1))
end
