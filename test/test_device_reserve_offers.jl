# Per-device ancillary-service (reserve) OFFERS.
#
# A device can submit a price/quantity OFFER curve for providing a reserve service, stored via
# the PSY `set_service_bid!` path: a `PiecewiseStepData` time series named after the service,
# attached to the device (whose operation cost must be an `OfferCurveCost`), plus service
# membership in `MarketBidCost.ancillary_service_offers`. Retrieval is `get_services_bid`.
#
# This is the (service, device, segment, time) 4D cost structure: one PWL offer per
# (device, service) per hour. The reserve AWARD (`ActivePowerReserveVariable`) is already keyed
# `(service, device, time)`; pricing it by these per-device offers (instead of the flat
# `DEFAULT_RESERVE_COST`) is the piece not yet built. These tests pin the DATA MODEL and a
# buildable fixture so that consumer can be developed against them.

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
    for (i, g) in enumerate(contributors)
        pmax = PSY.get_max_active_power(g, PSY.NU)
        set_operation_cost!(
            g,
            MarketBidCost(;
                no_load_cost = LinearCurve(0.0),
                start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = make_market_bid_curve(
                    [0.0, pmax], [20.0], 0.0; power_units = IS.NaturalUnit(),
                ),
            ),
        )
        price = 8.0 + 2.0 * i
        data = Dict(it => [offer_curve(price) for _ in 1:horizon] for it in init_times)
        ts = Deterministic(PSY.get_name(reserve), data, resolution)
        PSY.set_service_bid!(sys, g, reserve, ts, IS.NaturalUnit())
    end
    return contributors
end

@testset "Per-device reserve offers: data model" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    reserve = get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
    contributors = add_device_reserve_offers!(sys, reserve)

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

@testset "Per-device reserve offers: fixture builds and solves (offers not yet priced)" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    reserve = get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
    add_device_reserve_offers!(sys, reserve)

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
    # TODO(per-device reserve offers): no reserve-offer cost term is built yet - the device
    # reserve offer curves are not consumed, the reserve is priced at the flat DEFAULT_RESERVE_COST.
    # The only block-offer variable present is the ENERGY offer, not a reserve offer.
    reserve_offer_vars = [
        k for k in keys(container.variables)
        if occursin("Reserve", string(IOM.get_entry_type(k))) &&
        occursin("Offer", string(IOM.get_entry_type(k)))
    ]
    @test isempty(reserve_offer_vars)
end
