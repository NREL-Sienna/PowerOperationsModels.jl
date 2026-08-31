"""
Unit tests for `is_time_variant_proportional` — the trait used by
`IOM.add_proportional_cost_maybe_time_variant!` to decide whether the *specific
proportional cost term* for a given (variable × cost object) combination belongs on
the variant or invariant objective expression.

Not to be confused with `IOM.is_time_variant`, which asks whether *any* field on
the cost object is time-varying. `is_time_variant_proportional` is narrower: it asks
about the one field that feeds into this particular term.

For `ThermalGenerationCost`, the OnVariable proportional term rate is
`onvar_cost + vom_constant + fixed`. The part that can be time-varying in current
POM is `onvar_cost`, which for Linear/Quadratic FuelCurves equals
`constant_term × fuel_cost` — so it varies if the value curve is TS-backed
(constant_term varies) OR if `fuel_cost::TimeSeriesKey` (price varies).

The non-obvious case this test guards: `FuelCurve.fuel_cost::Union{Float64,
TimeSeriesKey}` is type-invariant but *instance*-dependent, so the trait must
look at the value, not just the type parameters.
"""

# Fabricated keys: this file only exercises the trait, never a store read, and each
# field's key type is pinned by the curve it goes into.
const _FUEL_PRICE_KEY = IS.TimeSeriesKey{IS.Deterministic{Float64}}(1)
const _LINEAR_CURVE_KEY = IS.TimeSeriesKey{IS.Deterministic{IS.LinearFunctionData}}(2)
const _QUADRATIC_CURVE_KEY =
    IS.TimeSeriesKey{IS.Deterministic{IS.QuadraticFunctionData}}(3)

_linear_vc() = PSY.LinearCurve(2.0, 3.0)
_quadratic_vc() = PSY.QuadraticCurve(1.0, 2.0, 3.0)
_pwl_vc() = PSY.PiecewisePointCurve([(x = 0.0, y = 0.0), (x = 1.0, y = 2.0)])
_ts_linear_vc() = PSY.TimeSeriesLinearCurve(_LINEAR_CURVE_KEY)
_ts_quadratic_vc() = PSY.TimeSeriesQuadraticCurve(_QUADRATIC_CURVE_KEY)

_tgc(variable) = PSY.ThermalGenerationCost(;
    variable = variable,
    fixed = 0.0,
    start_up = 0.0,
    shut_down = 0.0,
)

@testset "is_time_variant_proportional: ThermalGenerationCost" begin
    # CostCurve has no `_onvar_cost` overload — the OnVariable term never depends on
    # its value curve, so the trait is false regardless.
    @test POM.is_time_variant_proportional(_tgc(PSY.CostCurve(_linear_vc()))) == false

    # FuelCurve{PWL}: `_onvar_cost ≡ 0` regardless of fuel_cost — term is static.
    @test POM.is_time_variant_proportional(_tgc(PSY.FuelCurve(_pwl_vc(), 4.0))) == false
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_pwl_vc(), _FUEL_PRICE_KEY)),
    ) ==
          false

    # FuelCurve{Linear/Quadratic}: `_onvar_cost = constant_term * fuel_cost_at_t`,
    # so the term varies if either the value curve is TS-backed (constant_term
    # varies) or fuel_cost is a TimeSeriesKey (price varies). 2x2 for each shape:
    # static vs TS value curve × Float64 vs TimeSeriesKey fuel_cost.

    # LinearCurve
    @test POM.is_time_variant_proportional(_tgc(PSY.FuelCurve(_linear_vc(), 4.0))) == false
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_linear_vc(), _FUEL_PRICE_KEY)),
    ) == true
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_ts_linear_vc(), 4.0)),
    ) == true
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_ts_linear_vc(), _FUEL_PRICE_KEY)),
    ) == true

    # QuadraticCurve
    @test POM.is_time_variant_proportional(_tgc(PSY.FuelCurve(_quadratic_vc(), 4.0))) ==
          false
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_quadratic_vc(), _FUEL_PRICE_KEY)),
    ) == true
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_ts_quadratic_vc(), 4.0)),
    ) == true
    @test POM.is_time_variant_proportional(
        _tgc(PSY.FuelCurve(_ts_quadratic_vc(), _FUEL_PRICE_KEY)),
    ) == true
end

@testset "is_time_variant_proportional: MarketBidCost / ImportExportCost static vs TS" begin
    # Offer-curve cost types are cleanly split static vs TS by type — so the trait
    # is decided purely by type dispatch, no instance lookup needed.
    @test POM.is_time_variant_proportional(PSY.MarketBidCost()) == false
    @test POM.is_time_variant_proportional(stub_ts_market_bid_cost()) == true
    @test POM.is_time_variant_proportional(PSY.ImportExportCost()) == false
    @test POM.is_time_variant_proportional(stub_ts_import_export_cost()) == true
end
