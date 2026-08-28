"""
Unit tests for POM's MarketBidCost objective-function construction.

One testset per (device × formulation × cost-type) combo, each built on a single fixture
with multiple dials set to distinct values. Assertions address one observable at a time.
Scaling-sensitive behavior (dt, power-unit conversion, base_power mismatches) lives in
separate "scaling" testsets — that's where dials actually interact.

Underlying PWL math is covered by IOM — here we only verify POM's translations: that the
numbers put on a cost curve reach the container's objective coefficients as expected.
"""

const _LOAD_NAME = "load1"
const _THERMAL_NAME = "thermal1"

# A zero offer curve in SYSTEM_BASE. Used as the "absent" side when only one of the
# incremental/decremental curves is meaningful: PSY requires both offer curves to share
# a unit system, and the default `ZERO_OFFER_CURVE` is NATURAL_UNITS, so we can't leave
# the other side defaulted when the meaningful side is SYSTEM_BASE. A zero value curve is
# still treated as "absent" by the offer-side checks (which inspect slopes, not units).
const _ZERO_OFFER_SB = PSY.CostCurve(
    PSY.PiecewiseIncrementalCurve(0.0, [0.0, 0.0], [0.0]),
    PSY.SU,
)

# A static MBC with a decremental offer curve only (incremental is the zero offer curve,
# which the load-side supply check treats as "absent").
_decr_mbc(initial_input::Float64, xs::Vector{Float64}, slopes::Vector{Float64}) =
    PSY.MarketBidCost(;
        incremental_offer_curves = _ZERO_OFFER_SB,
        decremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(initial_input, xs, slopes),
            PSY.SU,
        ),
    )

@testset "InterruptiblePowerLoad + PowerLoadDispatch + static MBC" begin
    # Pick distinct slope values so any swap between segments is visible.
    cost = _decr_mbc(0.0, [0.0, 0.5, 1.0], [3.0, 7.0])
    sys = one_bus_one_interruptible_load(cost)
    load = PSY.get_component(PSY.InterruptiblePowerLoad, sys, _LOAD_NAME)

    container = build_test_container(sys, 1:1)
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerVariable, load, cost, POM.PowerLoadDispatch)

    # Decremental sign = -1, dt = 1 hr, SYSTEM_BASE ⇒ coefficient == -slope.
    @test pwl_delta_coefs(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ [-3.0, -7.0]
end

@testset "InterruptiblePowerLoad + PowerLoadDispatch: dt and unit conversion" begin
    # NATURAL_UNITS + 15-minute resolution.
    # slope: 3 $/MWh x 100 MW/p.u. x 0.25 hr/period = 75 $/(p.u. period)
    # x breakpoint: 200 MW x 1 p.u./100 MW = 2.0
    cost = PSY.MarketBidCost(;
        decremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 200.0], [3.0]),
            PSY.NU,
        ),
    )
    sys = one_bus_one_interruptible_load(cost; system_base_power = 100.0)
    load = PSY.get_component(PSY.InterruptiblePowerLoad, sys, _LOAD_NAME)

    container = build_test_container(sys, 1:1; resolution = Dates.Minute(15))
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerVariable, load, cost, POM.PowerLoadDispatch)

    @test pwl_delta_coefs(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ [-75.0]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ [2.0]
end

@testset "InterruptiblePowerLoad + PowerLoadDispatch + TS MBC" begin
    # TS MBC dispatches through the parameter-container path. We skip `add_parameters!`
    # (which would require real time series on the system) and populate the Decremental
    # slope/breakpoint parameters directly with distinct-per-timestep values.
    # A load has no supply (incremental) offer, so that side is the absent placeholder.
    cost = stub_ts_market_bid_cost(; incremental_trivial = true)
    sys = one_bus_one_interruptible_load(cost)
    load = PSY.get_component(PSY.InterruptiblePowerLoad, sys, _LOAD_NAME)

    container = build_test_container(sys, 1:2)
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 2)

    # Slopes and breakpoints vary over time so a wiring that reads the wrong t is visible.
    slopes_mat = reshape([[3.0, 7.0], [13.0, 17.0]], 1, 2)
    breakpoints_mat = reshape([[0.0, 0.5, 1.0], [0.0, 0.2, 0.7]], 1, 2)
    setup_delta_pwl_parameters!(
        container, PSY.InterruptiblePowerLoad, [_LOAD_NAME],
        slopes_mat, breakpoints_mat, 1:2;
        dir = IOM.DecrementalOffer())

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerVariable, load, cost, POM.PowerLoadDispatch)

    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    pwl = IOM.get_variable(
        container, IOM.PiecewiseLinearBlockDecrementalOffer,
        PSY.InterruptiblePowerLoad)
    @test [JuMP.coefficient(variant, pwl[(_LOAD_NAME, s, 1)]) for s in 1:2] ≈ [-3.0, -7.0]
    @test [JuMP.coefficient(variant, pwl[(_LOAD_NAME, s, 2)]) for s in 1:2] ≈ [-13.0, -17.0]

    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ [0.5, 0.5]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 2,
    ) ≈ [0.2, 0.5]
end

@testset "InterruptiblePowerLoad + PowerLoadInterruption + static MBC" begin
    # initial_input = 2 (OnVariable coef dial), plus distinct slopes for PWL.
    cost = _decr_mbc(2.0, [0.0, 0.5, 1.0], [3.0, 7.0])
    sys = one_bus_one_interruptible_load(cost)
    devs = PSY.get_components(PSY.InterruptiblePowerLoad, sys)

    container = build_test_container(sys, 1:1)
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)
    add_jump_var!(
        container, IOM.OnVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)

    IOM.add_variable_cost!(
        container, IOM.ActivePowerVariable, devs, POM.PowerLoadInterruption)
    POM.add_proportional_cost!(
        container, IOM.OnVariable, devs, POM.PowerLoadInterruption)

    # OnVariable: coefficient = initial_input × OBJECTIVE_FUNCTION_NEGATIVE = -2.0.
    @test obj_coef(
        container, IOM.OnVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ -2.0

    # PWL decremental: slope × sign × dt = -slope (dt=1, SYSTEM_BASE).
    @test pwl_delta_coefs(
        container, IOM.DecrementalOffer(), PSY.InterruptiblePowerLoad, _LOAD_NAME, 1,
    ) ≈ [-3.0, -7.0]
end

@testset "InterruptiblePowerLoad + PowerLoadInterruption + TS MBC" begin
    # A load has no supply (incremental) offer, so that side is the absent placeholder.
    cost = stub_ts_market_bid_cost(; incremental_trivial = true)
    sys = one_bus_one_interruptible_load(cost)
    devs = PSY.get_components(PSY.InterruptiblePowerLoad, sys)

    container = build_test_container(sys, 1:2)
    for t in 1:2
        add_jump_var!(
            container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, t)
        add_jump_var!(
            container, IOM.OnVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, t)
    end

    # Params vary over t so reading-wrong-t bugs are visible.
    setup_delta_pwl_parameters!(
        container, PSY.InterruptiblePowerLoad, [_LOAD_NAME],
        reshape([[3.0, 7.0], [13.0, 17.0]], 1, 2),
        reshape([[0.0, 0.5, 1.0], [0.0, 0.2, 0.7]], 1, 2),
        1:2;
        dir = IOM.DecrementalOffer())
    add_test_parameter!(
        container, IOM.DecrementalCostAtMinParameter, PSY.InterruptiblePowerLoad,
        [_LOAD_NAME], 1:2, reshape([2.5, 4.5], 1, 2))

    IOM.add_variable_cost!(
        container, IOM.ActivePowerVariable, devs, POM.PowerLoadInterruption)
    POM.add_proportional_cost!(
        container, IOM.OnVariable, devs, POM.PowerLoadInterruption)

    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    on_var = IOM.get_variable(container, IOM.OnVariable, PSY.InterruptiblePowerLoad)
    pwl = IOM.get_variable(
        container, IOM.PiecewiseLinearBlockDecrementalOffer,
        PSY.InterruptiblePowerLoad)

    # OnVariable: param × OBJECTIVE_FUNCTION_NEGATIVE.
    @test JuMP.coefficient(variant, on_var[_LOAD_NAME, 1]) ≈ -2.5
    @test JuMP.coefficient(variant, on_var[_LOAD_NAME, 2]) ≈ -4.5

    # PWL slopes in variant terms, one set per time step.
    @test [JuMP.coefficient(variant, pwl[(_LOAD_NAME, s, 1)]) for s in 1:2] ≈ [-3.0, -7.0]
    @test [JuMP.coefficient(variant, pwl[(_LOAD_NAME, s, 2)]) for s in 1:2] ≈ [-13.0, -17.0]
end

@testset "InterruptiblePowerLoad + PowerLoadDispatch: supply-side rejection" begin
    # Non-trivial incremental curve on a load should throw.
    cost = PSY.MarketBidCost(;
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [5.0]),
            PSY.SU,
        ),
        decremental_offer_curves = _ZERO_OFFER_SB,
    )
    sys = one_bus_one_interruptible_load(cost)
    load = PSY.get_component(PSY.InterruptiblePowerLoad, sys, _LOAD_NAME)

    container = build_test_container(sys, 1:1)
    add_jump_var!(
        container, IOM.ActivePowerVariable, PSY.InterruptiblePowerLoad, _LOAD_NAME, 1)

    @test_throws ArgumentError POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerVariable, load, cost, POM.PowerLoadDispatch)
end

@testset "ThermalStandard + ThermalBasicUnitCommitment + static MBC" begin
    # Distinct values on every dial so a wiring swap is visible.
    mbc = PSY.MarketBidCost(;
        minimum_energy_offer = PSY.LinearCurve(10.0),  # unused by thermal objective; kept as a
        # canary for accidental wiring into obj.
        start_up = (hot = 50.0, warm = 80.0, cold = 100.0),
        shut_down = PSY.LinearCurve(30.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(2.5, [0.1, 0.5, 1.0], [3.0, 7.0]),
            PSY.SU,
        ),
        decremental_offer_curves = _ZERO_OFFER_SB,
    )
    sys = one_bus_one_thermal(mbc; name = _THERMAL_NAME)
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = build_test_container(sys, 1:1)
    for V in (IOM.ActivePowerVariable, IOM.OnVariable, IOM.StartVariable, IOM.StopVariable)
        add_jump_var!(container, V, PSY.ThermalStandard, _THERMAL_NAME, 1)
    end

    IOM.add_variable_cost!(
        container, IOM.ActivePowerVariable, devs, POM.ThermalBasicUnitCommitment)
    IOM.add_start_up_cost!(
        container, IOM.StartVariable, devs, POM.ThermalBasicUnitCommitment)
    IOM.add_shut_down_cost!(
        container, IOM.StopVariable, devs, POM.ThermalBasicUnitCommitment)
    POM.add_proportional_cost!(
        container, IOM.OnVariable, devs, POM.ThermalBasicUnitCommitment)

    # StartVariable takes the max over StartUpStages for basic UC formulations.
    @test obj_coef(
        container, IOM.StartVariable, PSY.ThermalStandard, _THERMAL_NAME, 1,
    ) ≈ 100.0
    # StopVariable gets the LinearCurve shut_down's proportional term.
    @test obj_coef(
        container, IOM.StopVariable, PSY.ThermalStandard, _THERMAL_NAME, 1,
    ) ≈ 30.0
    # OnVariable picks up the incremental curve's initial_input (cost-at-min-gen).
    @test obj_coef(
        container, IOM.OnVariable, PSY.ThermalStandard, _THERMAL_NAME, 1,
    ) ≈ 2.5
    # Incremental PWL slopes (positive sign for supply, dt=1, SYSTEM_BASE).
    @test pwl_delta_coefs(
        container, IOM.IncrementalOffer(), PSY.ThermalStandard, _THERMAL_NAME, 1,
    ) ≈ [3.0, 7.0]
end

@testset "ThermalStandard + ThermalBasicUnitCommitment + TS MBC" begin
    # A generator has no demand (decremental) offer, so that side is the absent placeholder.
    cost = stub_ts_market_bid_cost(; decremental_trivial = true)
    sys = one_bus_one_thermal(cost; name = _THERMAL_NAME)
    devs = PSY.get_components(PSY.ThermalStandard, sys)

    container = build_test_container(sys, 1:2)
    for V in (IOM.ActivePowerVariable, IOM.OnVariable, IOM.StartVariable, IOM.StopVariable),
        t in 1:2

        add_jump_var!(container, V, PSY.ThermalStandard, _THERMAL_NAME, t)
    end

    # All param values differ between t=1 and t=2 to catch off-by-t wiring.
    setup_delta_pwl_parameters!(
        container, PSY.ThermalStandard, [_THERMAL_NAME],
        reshape([[3.0, 7.0], [13.0, 17.0]], 1, 2),
        reshape([[0.1, 0.5, 1.0], [0.1, 0.3, 0.9]], 1, 2),
        1:2;
        dir = IOM.IncrementalOffer())
    add_test_parameter!(
        container, IOM.IncrementalCostAtMinParameter, PSY.ThermalStandard,
        [_THERMAL_NAME], 1:2, reshape([2.5, 4.5], 1, 2))
    # Scalar Float64 startup — covers the basic path. A separate testset below covers
    # the Tuple-valued path used by multi-start formulations.
    add_test_parameter!(
        container, IOM.StartupCostParameter, PSY.ThermalStandard,
        [_THERMAL_NAME], 1:2, reshape([100.0, 110.0], 1, 2))
    add_test_parameter!(
        container, IOM.ShutdownCostParameter, PSY.ThermalStandard,
        [_THERMAL_NAME], 1:2, reshape([30.0, 45.0], 1, 2))

    IOM.add_variable_cost!(
        container, IOM.ActivePowerVariable, devs, POM.ThermalBasicUnitCommitment)
    IOM.add_start_up_cost!(
        container, IOM.StartVariable, devs, POM.ThermalBasicUnitCommitment)
    IOM.add_shut_down_cost!(
        container, IOM.StopVariable, devs, POM.ThermalBasicUnitCommitment)
    POM.add_proportional_cost!(
        container, IOM.OnVariable, devs, POM.ThermalBasicUnitCommitment)

    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    for (V, expected_t1, expected_t2) in (
        (IOM.StartVariable, 100.0, 110.0),
        (IOM.StopVariable, 30.0, 45.0),
        (IOM.OnVariable, 2.5, 4.5),
    )
        var = IOM.get_variable(container, V, PSY.ThermalStandard)
        @test JuMP.coefficient(variant, var[_THERMAL_NAME, 1]) ≈ expected_t1
        @test JuMP.coefficient(variant, var[_THERMAL_NAME, 2]) ≈ expected_t2
    end
    pwl = IOM.get_variable(
        container, IOM.PiecewiseLinearBlockIncrementalOffer, PSY.ThermalStandard)
    @test [JuMP.coefficient(variant, pwl[(_THERMAL_NAME, s, 1)]) for s in 1:2] ≈ [3.0, 7.0]
    @test [JuMP.coefficient(variant, pwl[(_THERMAL_NAME, s, 2)]) for s in 1:2] ≈
          [13.0, 17.0]
end

@testset "ThermalMultiStart + ThermalMultiStartUnitCommitment + TS MBC (Tuple startup)" begin
    # Multi-start UC splits the startup cost across three variables (hot/warm/cold),
    # each reading one field of the Tuple-valued `StartupCostParameter`. This exercises
    # `param .* mult` with a Tuple cell, plus the per-stage dispatch in `start_up_cost`.
    cost = stub_ts_market_bid_cost()
    ms_name = "thermal_ms1"
    sys = one_bus_one_thermal_multistart(cost; name = ms_name)
    devs = PSY.get_components(PSY.ThermalMultiStart, sys)

    container = build_test_container(sys, 1:1)
    for V in (POM.HotStartVariable, POM.WarmStartVariable, POM.ColdStartVariable)
        add_jump_var!(container, V, PSY.ThermalMultiStart, ms_name, 1)
    end

    # (hot, warm, cold) = (50, 100, 150). Each stage's variable should see its own field.
    add_test_parameter!(
        container, IOM.StartupCostParameter, PSY.ThermalMultiStart,
        [ms_name], 1:1, reshape([(50.0, 100.0, 150.0)], 1, 1))

    for V in (POM.HotStartVariable, POM.WarmStartVariable, POM.ColdStartVariable)
        IOM.add_start_up_cost!(
            container, V, devs, POM.ThermalMultiStartUnitCommitment)
    end

    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    for (V, expected) in (
        (POM.HotStartVariable, 50.0),
        (POM.WarmStartVariable, 100.0),
        (POM.ColdStartVariable, 150.0),
    )
        var = IOM.get_variable(container, V, PSY.ThermalMultiStart)
        @test JuMP.coefficient(variant, var[ms_name, 1]) ≈ expected
    end
end
