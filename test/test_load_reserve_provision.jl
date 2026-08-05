# Load reserve provision (POC): an `InterruptiblePowerLoad` modeled with `PowerLoadDispatch`
# provides UPWARD reserve by shedding consumption (P - r_up >= 0) and DOWNWARD reserve by consuming
# more (P + r_down <= forecast). The reserve sign is the inverse of a generator and matches the
# charge side of StorageDispatchWithReserves; the implementation mirrors RenewableDispatch with the
# direction map flipped. See .claude/plans/load-reserve-provision-poc.md.
#
# Up and down are exercised in SEPARATE scenarios: with c_sys5_il's weak LoadCost, co-modeling both
# lets the single load's consumption swing freely (the documented pricing caveat - a high,
# VOLL-level consumption value pins it), which would muddy the per-direction assertions.

@testset "load reserve direction map + folding methods" begin
    # ReserveUp routes to the LOWER-bound expression (shed room), ReserveDown to the UPPER-bound
    # (extra consumption) - the inverse of a generator.
    @test POM.get_expression_type_for_reserve(
        ActivePowerReserveVariable, PSY.InterruptiblePowerLoad,
        VariableReserve{ReserveUp}) == POM.ActivePowerRangeExpressionLB
    @test POM.get_expression_type_for_reserve(
        ActivePowerReserveVariable, PSY.InterruptiblePowerLoad,
        VariableReserve{ReserveDown}) == POM.ActivePowerRangeExpressionUB
    SMu = ServiceModel{VariableReserve{ReserveUp}, RangeReserve}
    SMd = ServiceModel{VariableReserve{ReserveDown}, RangeReserve}
    @test hasmethod(
        POM.add_to_expression!,
        Tuple{
            POM.OptimizationContainer, Type{POM.ActivePowerRangeExpressionLB},
            Type{ActivePowerReserveVariable}, VariableReserve{ReserveUp},
            Vector{PSY.InterruptiblePowerLoad}, SMu},
    )
    @test hasmethod(
        POM.add_to_expression!,
        Tuple{
            POM.OptimizationContainer, Type{POM.ActivePowerRangeExpressionUB},
            Type{ActivePowerReserveVariable}, VariableReserve{ReserveDown},
            Vector{PSY.InterruptiblePowerLoad}, SMd},
    )
end

# Economic-dispatch template (no unit commitment, so no initial-conditions solve) with the
# interruptible load as `PowerLoadDispatch`. `direction` selects which reserve to model; slacks keep
# the problem feasible (c_sys5_il's reserve requirement exceeds its small fleet) while the load
# still provides its physical headroom.
function _load_reserve_template(direction::Symbol)
    template = get_thermal_dispatch_template_network()
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    direction === :up && set_service_model!(template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))
    direction === :down && set_service_model!(template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve; use_slacks = true))
    return template
end

@testset "PowerLoadDispatch load provides UP-reserve, award capped by consumption" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    model = DecisionModel(_load_reserve_template(:up), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    @test IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionLB, PSY.InterruptiblePowerLoad)
    @test IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionUB, PSY.InterruptiblePowerLoad)

    res = IOM.OptimizationProblemOutputs(model)
    up = read_variable(res, "ActivePowerReserveVariable__VariableReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    p = read_variable(res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE)
    il = get_name(first(get_components(PSY.InterruptiblePowerLoad, sys)))
    # WIDE columns are "<service>__<device>"; sum this load's up-reserve over every ReserveUp it
    # contributes to. Values convert to natural units (MW) on read.
    upcols = [c for c in names(up) if endswith(c, "__$(il)")]
    @test !isempty(upcols)
    total_award = 0.0
    for t in 1:size(p, 1)
        awarded = sum(up[t, c] for c in upcols)
        @test awarded <= p[t, il] + 1e-4          # cannot shed more than it consumes
        @test p[t, il] - awarded >= -1e-4          # lower-headroom expression holds (LB >= 0)
        total_award += awarded
    end
    # The load's own demand is the sole provider of Reserve7, so it sheds its full consumption -
    # the shed cap binds, not vacuous.
    @test total_award > 1.0
end

@testset "PowerLoadDispatch load provides DOWN-reserve, award within consumption headroom" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    model = DecisionModel(_load_reserve_template(:down), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    @test IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionUB, PSY.InterruptiblePowerLoad)

    res = IOM.OptimizationProblemOutputs(model)
    dn = read_variable(res, "ActivePowerReserveVariable__VariableReserve__ReserveDown";
        table_format = TableFormat.WIDE)
    p = read_variable(res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE)
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))
    iln = get_name(il)
    pmax = PSY.get_max_active_power(il, PSY.NU)   # consumption rating (MW)
    dncols = [c for c in names(dn) if endswith(c, "__$(iln)")]
    @test !isempty(dncols)
    total_award = 0.0
    for t in 1:size(p, 1)
        awarded = sum(dn[t, c] for c in dncols)
        @test awarded >= -1e-4                        # nonnegative down-reserve
        @test p[t, iln] + awarded <= pmax + 1e-3      # consumption + down room stays within rating
        total_award += awarded
    end
    # The load provides downward reserve (extra-consumption headroom from below its forecast).
    @test total_award > 1.0
end

@testset "VOLL-priced load: pinned at HSL, full RegUp, zero RegDown" begin
    # Economics of pinning a must-serve load with a VOLL consumption value while it can provide BOTH
    # reserve directions. Up-reserve (shed) is free - the load consumes at HSL and commits to shed,
    # no consumption sacrifice - so it offers its full consumption. Down-reserve (consume more)
    # requires curtailing below HSL first, sacrificing VOLL, so it is never provided: a VOLL-pinned
    # must-serve load supplies up-direction reserve only.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))
    set_operation_cost!(il,
        PSY.LoadCost(PSY.CostCurve(PSY.LinearCurve(5000.0, 0.0), IS.NaturalUnit()), 24.0))

    template = get_thermal_dispatch_template_network()
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    set_service_model!(template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))
    set_service_model!(template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve; use_slacks = true))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    iln = get_name(il)
    p = read_variable(res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE)
    up = read_variable(res, "ActivePowerReserveVariable__VariableReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    dn = read_variable(res, "ActivePowerReserveVariable__VariableReserve__ReserveDown";
        table_format = TableFormat.WIDE)
    # HSL = the load's per-hour forecast (ActivePowerTimeSeriesParameter, keyed by device name).
    hsl = read_parameter(res, "ActivePowerTimeSeriesParameter__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE)
    upcols = [c for c in names(up) if endswith(c, "__$(iln)")]
    dncols = [c for c in names(dn) if endswith(c, "__$(iln)")]
    reg_up_total = 0.0
    for t in 1:size(p, 1)
        reg_up = sum(up[t, c] for c in upcols)
        reg_dn = sum(dn[t, c] for c in dncols)
        @test isapprox(p[t, iln], hsl[t, iln]; atol = 1e-1)       # dispatched at HSL
        @test isapprox(reg_up, p[t, iln]; atol = 1e-1)            # full RegUp = consumption
        @test reg_dn <= 1e-2                                       # zero RegDown (not convenient)
        reg_up_total += reg_up
    end
    @test reg_up_total > 1.0
end

@testset "no-reserve regression: PowerLoadDispatch without a reserve service" begin
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = false))
    model =
        DecisionModel(_load_reserve_template(:none), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    # With no reserve service on the load, the has_service_model gate skips the range expressions,
    # so the pure-energy PowerLoadDispatch formulation is byte-for-byte unchanged.
    @test !IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionLB, PSY.InterruptiblePowerLoad)
    @test !IOM.has_container_key(
        container, POM.ActivePowerRangeExpressionUB, PSY.InterruptiblePowerLoad)
end

@testset "service-carrying PowerLoadDispatch load with a zero energy value fails loudly" begin
    # A reserve-providing load with the default zero-value `LoadCost(nothing)` leaves its dispatch
    # unpinned (P free under P - Σr_up >= 0). The add_to_objective_function! guard rejects it, so
    # build! (which catches the ConflictingInputsError) returns FAILED instead of solving an
    # ill-posed model. This is the invariant a builder that forgets to attach a VOLL value hits.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))
    set_operation_cost!(il, PSY.LoadCost(nothing))   # zero value curve
    model = DecisionModel(_load_reserve_template(:up), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "PowerLoadDispatch load co-provides two up-services from one shared headroom" begin
    # c_sys5_il gives the load BOTH Reserve7 (VariableReserve{ReserveUp}) and ORDC1
    # (ReserveDemandCurve{ReserveUp}). Modeling both, a VOLL-pinned load's combined up-award across
    # the two services must never exceed its consumption: the two DIFFERENT up-services fold into ONE
    # shed-headroom expression (P - Σr_up >= 0). A per-service headroom bug would allow up to 2*P.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))
    set_operation_cost!(il,
        PSY.LoadCost(PSY.CostCurve(PSY.LinearCurve(5000.0, 0.0), IS.NaturalUnit()), 24.0))

    template = get_thermal_dispatch_template_network()
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    set_service_model!(template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))
    set_service_model!(template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    iln = get_name(il)
    p = read_variable(res, "ActivePowerVariable__InterruptiblePowerLoad";
        table_format = TableFormat.WIDE)
    vr = read_variable(res, "ActivePowerReserveVariable__VariableReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    ordc = read_variable(res, "ActivePowerReserveVariable__ReserveDemandCurve__ReserveUp";
        table_format = TableFormat.WIDE)
    vrcols = [c for c in names(vr) if endswith(c, "__$(iln)")]
    ordccols = [c for c in names(ordc) if endswith(c, "__$(iln)")]
    @test !isempty(vrcols) && !isempty(ordccols)
    combined = 0.0
    for t in 1:size(p, 1)
        a = sum(vr[t, c] for c in vrcols) + sum(ordc[t, c] for c in ordccols)
        @test a <= p[t, iln] + 1e-3        # ONE shared shed headroom across both up-services
        combined += a
    end
    @test combined > 1.0                    # non-vacuous: the load does co-provide
end

@testset "PowerLoadDispatch load offers into a flat StepwiseCostReserve, award bounded by offer" begin
    # A load contributing to a flat ReserveDemandCurve (ORDC1) with a MarketBidCost carrying a $0
    # price-taker AS offer - the ERCOT RRS-UFR pattern (loads clear at ~$0). The device-agnostic
    # per-resource offer machinery must price the LOAD in a StepwiseCostReserve and cap its award at
    # the OFFERED quantity, not its consumption.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_il"; add_reserves = true))
    il = first(get_components(PSY.InterruptiblePowerLoad, sys))
    ordc1 = first(get_components(ReserveDemandCurve{ReserveUp}, sys))
    pmax = PSY.get_max_active_power(il, PSY.NU)
    offer_mw = 10.0
    set_operation_cost!(il,
        MarketBidCost(; no_load_cost = LinearCurve(0.0),
            start_up = (hot = 0.0, warm = 0.0, cold = 0.0), shut_down = LinearCurve(0.0),
            decremental_offer_curves = make_market_bid_curve([0.0, pmax], [5000.0], 0.0;
                power_units = IS.NaturalUnit())))
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]
    offer_ts = Deterministic(PSY.get_name(ordc1),
        Dict(
            it => [IS.PiecewiseStepData([0.0, offer_mw], [0.0]) for _ in 1:24]
            for it in init_times
        ), Hour(1))
    PSY.set_service_bid!(sys, il, ordc1, offer_ts, IS.NaturalUnit())

    template = get_thermal_dispatch_template_network()
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    set_service_model!(template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    @test IOM.has_container_key(
        container, POM.PiecewiseLinearBlockReserveOffer, PSY.InterruptiblePowerLoad)

    res = IOM.OptimizationProblemOutputs(model)
    iln = get_name(il)
    aw = read_variable(res, "ActivePowerReserveVariable__ReserveDemandCurve__ReserveUp";
        table_format = TableFormat.WIDE)
    awcols = [c for c in names(aw) if endswith(c, "__$(iln)")]
    @test !isempty(awcols)
    total = 0.0
    for t in 1:size(aw, 1)
        a = sum(aw[t, c] for c in awcols)
        @test a <= offer_mw + 1e-3         # bounded by the OFFERED quantity, not consumption
        total += a
    end
    @test total > 1.0                       # the $0 price-taker block clears
end
