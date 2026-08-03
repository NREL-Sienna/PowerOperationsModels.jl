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
