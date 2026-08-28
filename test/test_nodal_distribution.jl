@testset "Nodal distribution core types" begin
    @test AggregateClearedInjection <: IOM.ExpressionType
    @test ClearedPositionVariable <: IOM.VariableType
    @test ClearedTransferVariable <: IOM.VariableType
    @test ClearedPositionConstraint <: IOM.ConstraintType
    @test DistributionFactorParameter <: IOM.TimeSeriesParameter
    @test NodalRedistribution <: IOM.AbstractDeviceFormulation
    @test AggregateBalance <: IOM.AbstractDeviceFormulation
    @test SpreadBid <: IOM.AbstractDeviceFormulation
    @test POM.DISTRIBUTION_FACTOR_TS_NAME == "distribution_factor"
end

@testset "Market construction threads the network model" begin
    for m in methods(construct_market_component!)
        params = Base.unwrap_unionall(m.sig).parameters
        @test length(params) == 7
        @test params[end] <: NetworkModel
    end
end

# c_sys5_uc with a two-bus load zone "LZ1" carrying constant 0.6/0.4 distribution factors
# (one series per member bus, owned by the zone), built from the load forecasts' own
# timestamps/resolution so the forecast parameters stay consistent system-wide.
function _build_zone_system()
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    zone = PSY.LoadZone(; name = "LZ1", peak_active_power = 10.0, peak_reactive_power = 3.0)
    PSY.add_component!(sys, zone)
    buses = sort!(collect(PSY.get_components(PSY.ACBus, sys)); by = PSY.get_number)
    zone_buses = buses[1:2]
    for b in zone_buses
        PSY.set_load_zone!(b, zone)
    end
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    existing = PSY.get_time_series(PSY.Deterministic, load, "max_active_power")
    resolution = PSY.get_resolution(existing)
    timestamps = collect(keys(PSY.get_data(existing)))
    horizon = length(first(values(PSY.get_data(existing))))
    for (b, f) in zip(zone_buses, (0.6, 0.4))
        data = SortedDict(ts => fill(f, horizon) for ts in timestamps)
        ts = PSY.Deterministic(;
            name = POM.DISTRIBUTION_FACTOR_TS_NAME, data = data, resolution = resolution,
        )
        PSY.add_time_series!(sys, zone, ts; features = Dict("bus" => PSY.get_number(b)))
    end
    return sys, zone, zone_buses
end

function _ptdf_market_template()
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    return template
end

@testset "get_distribution_factors" begin
    sys, zone, zone_buses = _build_zone_system()
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    network_model = get_network_model(IOM.get_template(model))
    time_steps = get_time_steps(container)
    t1 = first(time_steps)
    n1 = PSY.get_number(zone_buses[1])
    n2 = PSY.get_number(zone_buses[2])

    # LoadZone: series values land on the right retained buses, every timestep.
    factors = get_distribution_factors(container, sys, zone, network_model)
    @test sort(collect(axes(factors)[1])) == sort([n1, n2])
    @test all(factors[n1, t] == 0.6 for t in time_steps)
    @test all(factors[n2, t] == 0.4 for t in time_steps)

    # ACBus: one-entry identity.
    bf = get_distribution_factors(container, sys, zone_buses[1], network_model)
    @test collect(axes(bf)[1]) == [n1]
    @test all(bf[n1, t] == 1.0 for t in time_steps)

    # TradingHub with no series: uniform 1/N (D9).
    hub = PSY.TradingHub(; name = "HUB1", buses = collect(zone_buses))
    PSY.add_component!(sys, hub)
    hf = get_distribution_factors(container, sys, hub, network_model)
    @test hf[n1, t1] == 0.5
    @test hf[n2, t1] == 0.5

    # LoadZone member bus with no series contributes 0.0, no error (D13), as long as some
    # member bus carries a series.
    zone2 = PSY.LoadZone(; name = "LZ2", peak_active_power = 5.0, peak_reactive_power = 1.0)
    PSY.add_component!(sys, zone2)
    buses = sort!(collect(PSY.get_components(PSY.ACBus, sys)); by = PSY.get_number)
    b3, b4 = buses[3], buses[4]
    PSY.set_load_zone!(b3, zone2)
    PSY.set_load_zone!(b4, zone2)
    existing = PSY.get_time_series(
        PSY.Deterministic, zone, POM.DISTRIBUTION_FACTOR_TS_NAME;
        features = Dict("bus" => n1),
    )
    data = SortedDict(
        ts => fill(1.0, length(v)) for (ts, v) in PSY.get_data(existing)
    )
    PSY.add_time_series!(
        sys, zone2,
        PSY.Deterministic(;
            name = POM.DISTRIBUTION_FACTOR_TS_NAME, data = data,
            resolution = PSY.get_resolution(existing),
        );
        features = Dict("bus" => PSY.get_number(b4)),
    )
    zf = get_distribution_factors(container, sys, zone2, network_model)
    @test zf[PSY.get_number(b3), t1] == 0.0
    @test zf[PSY.get_number(b4), t1] == 1.0

    # A LoadZone with no series on any member bus is a loud error, not a silent zero.
    zone3 = PSY.LoadZone(; name = "LZ3", peak_active_power = 5.0, peak_reactive_power = 1.0)
    PSY.add_component!(sys, zone3)
    PSY.set_load_zone!(buses[5], zone3)
    @test_throws ErrorException get_distribution_factors(
        container,
        sys,
        zone3,
        network_model,
    )

    @test POM.assert_numeric_distribution_factors(container) === nothing
end

@testset "NodalRedistribution builds position machinery for a LoadZone" begin
    sys, zone, zone_buses = _build_zone_system()
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)

    @test IOM.has_container_key(container, AggregateClearedInjection, PSY.LoadZone)
    @test IOM.has_container_key(container, ClearedPositionVariable, PSY.LoadZone)
    @test IOM.has_container_key(container, ClearedPositionConstraint, PSY.LoadZone)

    # Fan-out is inline: the position variable appears in each member bus's balance
    # with its factor as the coefficient, and in no other bus's.
    position = IOM.get_variable(container, ClearedPositionVariable, PSY.LoadZone)
    nodal = IOM.get_expression(container, ActivePowerBalance, PSY.ACBus)
    t1 = first(get_time_steps(container))
    n1 = PSY.get_number(zone_buses[1])
    n2 = PSY.get_number(zone_buses[2])
    @test JuMP.coefficient(nodal[n1, t1], position["LZ1", t1]) == 0.6
    @test JuMP.coefficient(nodal[n2, t1], position["LZ1", t1]) == 0.4
    for n in axes(nodal)[1]
        n in (n1, n2) && continue
        @test JuMP.coefficient(nodal[n, t1], position["LZ1", t1]) == 0.0
    end
    # One constraint per location per timestep ties the variable to the expression, and
    # the position never enters the settlement row.
    constraint = IOM.get_constraint(container, ClearedPositionConstraint, PSY.LoadZone)
    @test size(constraint) == (1, length(get_time_steps(container)))
    sexpr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    @test JuMP.coefficient(sexpr[1, t1], position["LZ1", t1]) == 0.0
end

@testset "Market model without NodalRedistribution still requires CopperPlate" begin
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)
    @test_throws ArgumentError POM._check_market_model!(template)
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    @test POM._check_market_model!(template) === nothing
end

function _add_hub_and_p2p!(sys, zone)
    buses = sort!(collect(PSY.get_components(PSY.ACBus, sys)); by = PSY.get_number)
    hub = PSY.TradingHub(; name = "HUB1", buses = buses[3:4])
    PSY.add_component!(sys, hub)
    bid = PSY.PointToPointBid(;
        name = "P2P1", available = true, from = zone, to = hub,
        max_active_power = 50.0, price_limits = (min = -100.0, max = 100.0),
    )
    PSY.add_component!(sys, bid)
    return hub, bid
end

@testset "SpreadBid: two signed writes, nets to zero across all buses" begin
    sys, zone, zone_buses = _build_zone_system()
    hub, bid = _add_hub_and_p2p!(sys, zone)
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    set_market_component_model!(template, DeviceModel(PSY.TradingHub, NodalRedistribution))
    set_market_component_model!(template, DeviceModel(PSY.PointToPointBid, SpreadBid))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    time_steps = get_time_steps(container)
    t1 = first(time_steps)

    q = IOM.get_variable(container, ClearedTransferVariable, PSY.PointToPointBid)
    @test JuMP.lower_bound(q["P2P1", t1]) == 0.0
    @test JuMP.upper_bound(q["P2P1", t1]) == 50.0 / PSY.get_base_power(sys)
    # -q at from (zone expression), +q at to (hub expression).
    zexpr = IOM.get_expression(container, AggregateClearedInjection, PSY.LoadZone)
    hexpr = IOM.get_expression(container, AggregateClearedInjection, PSY.TradingHub)
    @test JuMP.coefficient(zexpr["LZ1", t1], q["P2P1", t1]) == -1.0
    @test JuMP.coefficient(hexpr["HUB1", t1], q["P2P1", t1]) == 1.0

    # D11: excluded from the settlement row outright.
    sexpr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    @test JuMP.coefficient(sexpr[1, t1], q["P2P1", t1]) == 0.0

    # The invariant that catches factor bugs end-to-end: each position's distributed
    # coefficients sum to one across ALL buses at every timestep, so -q via the zone and
    # +q via the hub cancel system-wide and the bid acts only through the nodal pattern.
    zpos = IOM.get_variable(container, ClearedPositionVariable, PSY.LoadZone)
    hpos = IOM.get_variable(container, ClearedPositionVariable, PSY.TradingHub)
    nodal = IOM.get_expression(container, ActivePowerBalance, PSY.ACBus)
    for t in time_steps
        zsum = sum(JuMP.coefficient(nodal[n, t], zpos["LZ1", t]) for n in axes(nodal)[1])
        hsum = sum(JuMP.coefficient(nodal[n, t], hpos["HUB1", t]) for n in axes(nodal)[1])
        @test isapprox(zsum, 1.0; atol = 1e-9)
        @test isapprox(hsum, 1.0; atol = 1e-9)
    end
    # Hub with no series: uniform across its two member buses.
    hub_numbers = PSY.get_number.(PSY.get_buses(hub))
    for n in hub_numbers
        @test JuMP.coefficient(nodal[n, t1], hpos["HUB1", t1]) == 0.5
    end
end

@testset "SpreadBid with an ACBus terminal takes the identity path" begin
    sys, zone, zone_buses = _build_zone_system()
    buses = sort!(collect(PSY.get_components(PSY.ACBus, sys)); by = PSY.get_number)
    bus_terminal = buses[5]
    bid = PSY.PointToPointBid(;
        name = "P2P_BUS", available = true, from = zone, to = bus_terminal,
        max_active_power = 20.0, price_limits = (min = -100.0, max = 100.0),
    )
    PSY.add_component!(sys, bid)
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    set_market_component_model!(template, DeviceModel(PSY.ACBus, NodalRedistribution))
    set_market_component_model!(template, DeviceModel(PSY.PointToPointBid, SpreadBid))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    t1 = first(get_time_steps(container))
    bpos = IOM.get_variable(container, ClearedPositionVariable, PSY.ACBus)
    nodal = IOM.get_expression(container, ActivePowerBalance, PSY.ACBus)
    bname = PSY.get_name(bus_terminal)
    n5 = PSY.get_number(bus_terminal)
    # Lands entirely on its own bus.
    for n in axes(nodal)[1]
        expected = 0.0
        if n == n5
            expected = 1.0
        end
        @test JuMP.coefficient(nodal[n, t1], bpos[bname, t1]) == expected
    end
    q = IOM.get_variable(container, ClearedTransferVariable, PSY.PointToPointBid)
    bexpr = IOM.get_expression(container, AggregateClearedInjection, PSY.ACBus)
    @test JuMP.coefficient(bexpr[bname, t1], q["P2P_BUS", t1]) == 1.0
end

@testset "SpreadBid terminal without a location model fails loudly" begin
    sys, zone, zone_buses = _build_zone_system()
    hub, bid = _add_hub_and_p2p!(sys, zone)
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    set_market_component_model!(template, DeviceModel(PSY.PointToPointBid, SpreadBid))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "VirtualBidDispatch writes into its settlement location" begin
    sys, zone, zone_buses = _build_zone_system()
    vp = PSY.VirtualParticipant(;
        name = "V1", available = true, max_supply = 10.0, max_demand = 10.0,
        settlement_point = zone,
        operation_cost = PSY.MarketBidCost(;
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [1000.0]),
                PSY.NU,
            ),
            decremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [5.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp)
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    set_market_component_model!(
        template, DeviceModel(PSY.VirtualParticipant, VirtualBidDispatch),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    t1 = first(get_time_steps(container))
    p_out = IOM.get_variable(container, ActivePowerOutVariable, PSY.VirtualParticipant)
    p_in = IOM.get_variable(container, ActivePowerInVariable, PSY.VirtualParticipant)
    zexpr = IOM.get_expression(container, AggregateClearedInjection, PSY.LoadZone)
    @test JuMP.coefficient(zexpr["LZ1", t1], p_out["V1", t1]) == 1.0
    @test JuMP.coefficient(zexpr["LZ1", t1], p_in["V1", t1]) == -1.0
    # The settlement writes are unchanged: still +out/-in on the System row.
    sexpr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    @test JuMP.coefficient(sexpr[1, t1], p_out["V1", t1]) == 1.0
    @test JuMP.coefficient(sexpr[1, t1], p_in["V1", t1]) == -1.0
    # And the virtual never touches the nodal balance directly: only through the position.
    nodal = IOM.get_expression(container, ActivePowerBalance, PSY.ACBus)
    for n in axes(nodal)[1]
        @test JuMP.coefficient(nodal[n, t1], p_out["V1", t1]) == 0.0
        @test JuMP.coefficient(nodal[n, t1], p_in["V1", t1]) == 0.0
    end
end

@testset "VirtualBidDispatch at a single trading hub writes into the hub" begin
    sys, zone, zone_buses = _build_zone_system()
    buses = sort!(collect(PSY.get_components(PSY.ACBus, sys)); by = PSY.get_number)
    hub = PSY.TradingHub(; name = "HUB1", buses = buses[3:4])
    PSY.add_component!(sys, hub)
    vp = PSY.VirtualParticipant(;
        name = "VH", available = true, max_supply = 10.0, max_demand = 0.0,
        trading_hubs = [hub],
        operation_cost = PSY.MarketBidCost(;
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [1000.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp)
    template = _ptdf_market_template()
    set_market_component_model!(template, DeviceModel(PSY.TradingHub, NodalRedistribution))
    set_market_component_model!(
        template, DeviceModel(PSY.VirtualParticipant, VirtualBidDispatch),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    t1 = first(get_time_steps(container))
    p_out = IOM.get_variable(container, ActivePowerOutVariable, PSY.VirtualParticipant)
    hexpr = IOM.get_expression(container, AggregateClearedInjection, PSY.TradingHub)
    @test JuMP.coefficient(hexpr["HUB1", t1], p_out["VH", t1]) == 1.0
end

# Demand enters only as the distributed cleared bid: a forecast `StaticPowerLoad` would sit
# in the physical balance but never in the settlement row, and the system-level slack that
# reconciles the two is not nodal, so the PTDF flows would be built from unbalanced
# injections.
function _congestion_template()
    template = PowerOperationsProblemTemplate(NetworkModel(PTDFNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(template, DeviceModel(PSY.LoadZone, NodalRedistribution))
    set_market_component_model!(
        template, DeviceModel(PSY.VirtualParticipant, VirtualBidDispatch),
    )
    set_device_model!(
        template, DeviceModel(PSY.Line, StaticBranch; duals = [FlowRateConstraint]),
    )
    return template
end

function _solve_congestion_model(sys)
    model = DecisionModel(_congestion_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    return model
end

@testset "Distributed demand congests: PTDF · injections matches, binding line has a dual" begin
    sys, zone, zone_buses = _build_zone_system()
    # A demand-side virtual at the zone forces a distributed withdrawal, valued highly so
    # it clears at a positive quantity, and sized above the fleet's summed minimum power
    # so the settlement row (generation == cleared demand) is feasible.
    vp = PSY.VirtualParticipant(;
        name = "VD", available = true, max_supply = 0.0, max_demand = 1000.0,
        settlement_point = zone,
        operation_cost = PSY.MarketBidCost(;
            decremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1000.0], [1000.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp)

    # Unconstrained pass: find the most loaded line, then rate it just below that flow so
    # the distributed withdrawal binds it.
    model = _solve_congestion_model(sys)
    container = get_optimization_container(model)
    t1 = first(get_time_steps(container))
    flows = IOM.get_expression(container, PTDFBranchFlow, PSY.Line)
    line_names = collect(axes(flows)[1])
    loaded = argmax(l -> abs(JuMP.value(flows[l, t1])), line_names)
    rating = 0.9 * abs(JuMP.value(flows[loaded, t1]))
    PSY.set_rating!(PSY.get_component(PSY.Line, sys, loaded), rating * PSY.SU)

    model = _solve_congestion_model(sys)
    container = get_optimization_container(model)
    network_model = get_network_model(IOM.get_template(model))
    position = IOM.get_variable(container, ClearedPositionVariable, PSY.LoadZone)
    pos_val = JuMP.value(position["LZ1", t1])
    @test pos_val < 0.0  # net withdrawal cleared

    # Independent reference: PTDF times the realized nodal injections (generation, load
    # parameters, and df ⊙ position) must reproduce every branch flow.
    factors = get_distribution_factors(container, sys, zone, network_model)
    ptdf = PNM.PTDF(sys)
    flows = IOM.get_expression(container, PTDFBranchFlow, PSY.Line)
    nodal = IOM.get_expression(container, ActivePowerBalance, PSY.ACBus)
    bus_numbers = collect(axes(nodal)[1])
    injections = [JuMP.value(nodal[n, t1]) for n in bus_numbers]
    distributed = sum(factors[n, t1] * pos_val for n in axes(factors)[1])
    @test isapprox(distributed, pos_val; atol = 1e-9)
    for lname in line_names
        expected = sum(ptdf[lname, n] * injections[i] for (i, n) in enumerate(bus_numbers))
        @test isapprox(JuMP.value(flows[lname, t1]), expected; atol = 1e-6)
    end

    # Congestion: the tightened line sits at its rating and carries a non-zero dual.
    @test isapprox(abs(JuMP.value(flows[loaded, t1])), rating; atol = 1e-6)
    duals = IOM.get_duals(container)
    dual_value = sum(
        abs(duals[IOM.ConstraintKey(FlowRateConstraint, PSY.Line, meta)][loaded, t1])
        for meta in ("lb", "ub")
    )
    @test dual_value > 1e-6
end
