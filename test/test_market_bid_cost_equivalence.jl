"""
Black-box MarketBidCost tests: build a real `DecisionModel`, solve it, and compare solved
objective values between two systems.

Complements `test_market_bid_cost.jl`, which is white-box (hand-built container, manually
poked parameters, no solve). The property asserted here is that a system carrying no cost
time series and a system carrying a CONSTANT-valued cost time series must solve to the
same objective — the invariant that keeps the time-series cost path honest end to end.

Ported from PowerSimulations' `test_market_bid_cost.jl` as part of the PSI to IOM+POM
excision: PSI keeps only the tests that require a multi-step `Simulation`.
"""

@testset "MarketBidCost incremental ThermalStandard, no time series versus constant time series" begin
    sys_no_ts = load_sys_incr()
    set_name!(sys_no_ts, "thermal_no_ts")
    sys_constant_ts = build_sys_incr(false, false, false)
    set_name!(sys_constant_ts, "thermal_constant_ts")
    test_generic_mbc_equivalence(sys_no_ts, sys_constant_ts)
end

@testset "MarketBidCost incremental RenewableDispatch, no time series versus constant time series" begin
    sys_no_ts = load_sys_incr()
    sys_constant_ts = build_sys_incr(false, false, false)
    for sys in (sys_no_ts, sys_constant_ts)
        unit1 = get_component(SEL_INCR, sys)
        replace_with_renewable!(sys, unit1; magnitude = 1.0, random_variation = 0.1)
    end
    test_generic_mbc_equivalence(sys_no_ts, sys_constant_ts)
end

@testset "MarketBidCost decremental PowerLoadInterruption, no time series vs constant time series" begin
    sys_no_ts = load_sys_decr2()
    sys_constant_ts = build_sys_decr2(false, false, false)
    test_generic_mbc_equivalence(sys_no_ts, sys_constant_ts)
end

# TODO error if there's nonzero decremental initial input for PowerLoadDispatch.
@testset "MarketBidCost decremental PowerLoadDispatch, no time series vs constant time series" begin
    device_to_formulation = FormulationDict(PSY.InterruptiblePowerLoad => PowerLoadDispatch)
    sys_no_ts = load_sys_decr2()
    sys_constant_ts = build_sys_decr2(false, false, false)
    test_generic_mbc_equivalence(
        sys_no_ts,
        sys_constant_ts;
        device_to_formulation = device_to_formulation,
    )
end

@testset "MarketBidCost incremental with heterogeneous time series names" begin
    # `_is_mbc` matches both MarketBidCost and MarketBidTimeSeriesCost: `build_sys_incr` (via
    # `extend_mbc!`) converts every selected component's cost to `MarketBidTimeSeriesCost`, so
    # a selector re-evaluated against `baseline` below (a `ComponentSelector` predicate is
    # live, not frozen at construction) must still match the post-conversion type.
    sel = make_selector(x -> _is_mbc(get_operation_cost(x)), ThermalStandard)
    baseline = build_sys_incr(true, true, true; active_components = sel)
    @assert length(get_components(sel, baseline)) == 2

    # Should succeed for varying initial input time series names:
    variable_ii_names = build_sys_incr(
        true,
        true,
        true;
        active_components = sel,
        initial_input_names_vary = true,
    )
    test_generic_mbc_equivalence(baseline, variable_ii_names)

    # A heterogeneous variable-cost time series name is expected to error informatively at
    # build time (PSI's equivalent used `build_impl!`; POM has no such hook to call directly
    # here). Not asserted, matching PSI's own tracking comment for this case.
    variable_vc_names = build_sys_incr(
        true,
        true,
        true;
        active_components = sel,
        variable_cost_names_vary = true,
    )
    build_generic_mbc_model(variable_vc_names; multistart = false)
end

for decremental in (false, true)
    adj = decremental ? "decremental" : "incremental"
    build_func = decremental ? build_sys_decr2 : build_sys_incr
    comp_type = decremental ? InterruptiblePowerLoad : ThermalStandard
    device_models = if decremental
        [PowerLoadInterruption, PowerLoadDispatch]
    else
        [ThermalBasicUnitCommitment]
    end
    @testset for device_model in device_models
        device_to_formulation = FormulationDict(comp_type => device_model)
        init_input_bool = !decremental || device_model != PowerLoadDispatch

        @testset "MarketBidCost $(adj) with variable number of tranches" begin
            baseline = build_func(init_input_bool, true, true)
            set_name!(baseline, "baseline")
            variable_tranches =
                build_func(init_input_bool, true, true; create_extra_tranches = true)
            set_name!(variable_tranches, "variable")
            test_generic_mbc_equivalence(
                baseline,
                variable_tranches;
                is_decremental = decremental,
                device_to_formulation = device_to_formulation,
            )
        end
    end
end
