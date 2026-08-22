"""
Unit tests for POM's ImportExportCost objective-function construction.

Same conventions as `test_market_bid_cost.jl`: system base == device base == 100, curves
in `SYSTEM_BASE` power units, hourly resolution, one time step — so translated slopes
arrive at the objective unchanged. Scaling is covered by its own testset.

Sign convention for a Source with `ImportExportSourceModel`:
- Import (`ActivePowerOutVariable`, `IncrementalOffer`) → `OBJECTIVE_FUNCTION_POSITIVE`.
- Export (`ActivePowerInVariable`, `DecrementalOffer`) → `OBJECTIVE_FUNCTION_NEGATIVE`.
"""

const _SOURCE_NAME = "source1"

_static_iec(import_xs, import_ys, export_xs, export_ys) = PSY.ImportExportCost(;
    import_offer_curves = PSY.CostCurve(
        PSY.PiecewiseIncrementalCurve(0.0, import_xs, import_ys),
        PSY.SU,
    ),
    export_offer_curves = PSY.CostCurve(
        PSY.PiecewiseIncrementalCurve(0.0, export_xs, export_ys),
        PSY.SU,
    ),
)

@testset "Source + ImportExportSourceModel + static IEC" begin
    # Distinct slopes for import vs export so a swap is visible.
    cost = _static_iec(
        [0.0, 0.25, 1.0], [2.0, 5.0],      # import side
        [0.0, 0.40, 0.9], [4.0, 8.0],      # export side — distinct breakpoints & slopes
    )
    sys = one_bus_one_source(cost; name = _SOURCE_NAME)
    source = PSY.get_component(PSY.Source, sys, _SOURCE_NAME)

    container = build_test_container(sys, 1:1)
    add_jump_var!(container, IOM.ActivePowerOutVariable, PSY.Source, _SOURCE_NAME, 1)
    add_jump_var!(container, IOM.ActivePowerInVariable, PSY.Source, _SOURCE_NAME, 1)

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerOutVariable, source, cost, POM.ImportExportSourceModel,
    )
    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerInVariable, source, cost, POM.ImportExportSourceModel,
    )

    # Import side: IncrementalOffer sign = +1.
    @test pwl_delta_coefs(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [2.0, 5.0]
    @test pwl_delta_widths(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [0.25, 0.75]
    # Export side: DecrementalOffer sign = -1, distinct breakpoints.
    @test pwl_delta_coefs(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [-4.0, -8.0]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [0.4, 0.5]
end

@testset "Source + ImportExportSourceModel: dt and unit conversion" begin
    # NATURAL_UNITS + 15-minute resolution. Slope scaling: y × sys_base × dt.
    # Break scaling: x / sys_base.
    cost = PSY.ImportExportCost(;
        import_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 200.0], [6.0]),
            PSY.NU,
        ),
        export_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 200.0], [9.0]),
            PSY.NU,
        ),
    )
    sys = one_bus_one_source(cost; name = _SOURCE_NAME)
    source = PSY.get_component(PSY.Source, sys, _SOURCE_NAME)

    container = build_test_container(sys, 1:1; resolution = Dates.Minute(15))
    add_jump_var!(container, IOM.ActivePowerOutVariable, PSY.Source, _SOURCE_NAME, 1)
    add_jump_var!(container, IOM.ActivePowerInVariable, PSY.Source, _SOURCE_NAME, 1)

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerOutVariable, source, cost, POM.ImportExportSourceModel,
    )
    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerInVariable, source, cost, POM.ImportExportSourceModel,
    )

    # Import slope coefficient = +(6 × 100) × 0.25 = +150.
    @test pwl_delta_coefs(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [150.0]
    # Export slope coefficient = -(9 × 100) × 0.25 = -225.
    @test pwl_delta_coefs(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [-225.0]
    # Breakpoint widths = 200 / 100 = 2.0 for both directions.
    @test pwl_delta_widths(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [2.0]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [2.0]
end

@testset "Source + ImportExportSourceModel: an unoffered side adds no terms" begin
    # A one-directional import source: PSY leaves the export side as `ZERO_OFFER_CURVE`,
    # which must not become a block of PWL variables priced at zero.
    cost = PSY.ImportExportCost(;
        import_offer_curves = PSY.make_import_curve([0.0, 25.0, 100.0], [2.0, 5.0]),
    )
    sys = one_bus_one_source(cost; name = _SOURCE_NAME)
    source = PSY.get_component(PSY.Source, sys, _SOURCE_NAME)

    container = build_test_container(sys, 1:1)
    add_jump_var!(container, IOM.ActivePowerOutVariable, PSY.Source, _SOURCE_NAME, 1)
    add_jump_var!(container, IOM.ActivePowerInVariable, PSY.Source, _SOURCE_NAME, 1)

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerOutVariable, source, cost, POM.ImportExportSourceModel,
    )
    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerInVariable, source, cost, POM.ImportExportSourceModel,
    )

    @test IOM.has_container_key(
        container, IOM.PiecewiseLinearBlockIncrementalOffer, PSY.Source,
    )
    @test !IOM.has_container_key(
        container, IOM.PiecewiseLinearBlockDecrementalOffer, PSY.Source,
    )
end

@testset "ImportExportBudgetConstraint: sub-hourly resolution" begin
    cost = _static_iec([0.0, 0.25, 1.0], [2.0, 5.0], [0.0, 0.40, 0.9], [4.0, 8.0])
    PSY.set_energy_import_weekly_limit!(cost, 168.0)
    PSY.set_energy_export_weekly_limit!(cost, 336.0)
    sys = one_bus_one_source(cost; name = _SOURCE_NAME)

    time_steps = 1:12
    container = build_test_container(sys, time_steps; resolution = Dates.Minute(5))
    for t in time_steps
        add_jump_var!(container, IOM.ActivePowerOutVariable, PSY.Source, _SOURCE_NAME, t)
        add_jump_var!(container, IOM.ActivePowerInVariable, PSY.Source, _SOURCE_NAME, t)
    end

    POM.add_constraints!(
        container,
        POM.ImportExportBudgetConstraint,
        PSY.get_components(PSY.Source, sys),
        IOM.DeviceModel(PSY.Source, POM.ImportExportSourceModel),
        IOM.NetworkModel(POM.CopperPlateNetworkModel),
    )

    # 12 × 5 min is one hour of horizon, so each weekly limit prorates by 1/168.
    import_con =
        IOM.get_constraint(
            container,
            POM.ImportExportBudgetConstraint,
            PSY.Source,
            "import",
        )
    export_con =
        IOM.get_constraint(
            container,
            POM.ImportExportBudgetConstraint,
            PSY.Source,
            "export",
        )
    @test JuMP.normalized_rhs(import_con[_SOURCE_NAME, "horizon"]) ≈ 1.0
    @test JuMP.normalized_rhs(export_con[_SOURCE_NAME, "horizon"]) ≈ 2.0
    # Each 5-minute step contributes an hour twelfth of energy.
    p_out = IOM.get_variable(container, IOM.ActivePowerOutVariable, PSY.Source)
    @test JuMP.normalized_coefficient(
        import_con[_SOURCE_NAME, "horizon"], p_out[_SOURCE_NAME, 1],
    ) ≈ 1 / 12
end

@testset "Source + ImportExportSourceModel + TS IEC" begin
    cost = stub_ts_import_export_cost()
    sys = one_bus_one_source(cost; name = _SOURCE_NAME)
    source = PSY.get_component(PSY.Source, sys, _SOURCE_NAME)

    container = build_test_container(sys, 1:2)
    for t in 1:2
        add_jump_var!(container, IOM.ActivePowerOutVariable, PSY.Source, _SOURCE_NAME, t)
        add_jump_var!(container, IOM.ActivePowerInVariable, PSY.Source, _SOURCE_NAME, t)
    end

    # Distinct values per direction AND per time step.
    setup_delta_pwl_parameters!(
        container, PSY.Source, [_SOURCE_NAME],
        reshape([[2.0, 5.0], [11.0, 15.0]], 1, 2),
        reshape([[0.0, 0.25, 1.0], [0.0, 0.35, 0.8]], 1, 2),
        1:2;
        dir = IOM.IncrementalOffer())
    setup_delta_pwl_parameters!(
        container, PSY.Source, [_SOURCE_NAME],
        reshape([[4.0, 8.0], [14.0, 18.0]], 1, 2),
        reshape([[0.0, 0.40, 0.9], [0.0, 0.50, 0.8]], 1, 2),
        1:2;
        dir = IOM.DecrementalOffer())

    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerOutVariable, source, cost, POM.ImportExportSourceModel,
    )
    POM.add_variable_cost_to_objective!(
        container, IOM.ActivePowerInVariable, source, cost, POM.ImportExportSourceModel,
    )

    variant = IOM.get_variant_terms(IOM.get_objective_expression(container))
    incr_pwl = IOM.get_variable(
        container, IOM.PiecewiseLinearBlockIncrementalOffer, PSY.Source)
    decr_pwl = IOM.get_variable(
        container, IOM.PiecewiseLinearBlockDecrementalOffer, PSY.Source)

    @test [JuMP.coefficient(variant, incr_pwl[(_SOURCE_NAME, s, 1)]) for s in 1:2] ≈
          [2.0, 5.0]
    @test [JuMP.coefficient(variant, incr_pwl[(_SOURCE_NAME, s, 2)]) for s in 1:2] ≈
          [11.0, 15.0]
    @test [JuMP.coefficient(variant, decr_pwl[(_SOURCE_NAME, s, 1)]) for s in 1:2] ≈
          [-4.0, -8.0]
    @test [JuMP.coefficient(variant, decr_pwl[(_SOURCE_NAME, s, 2)]) for s in 1:2] ≈
          [-14.0, -18.0]

    @test pwl_delta_widths(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [0.25, 0.75]
    @test pwl_delta_widths(
        container, IOM.IncrementalOffer(), PSY.Source, _SOURCE_NAME, 2,
    ) ≈ [0.35, 0.45]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 1,
    ) ≈ [0.4, 0.5]
    @test pwl_delta_widths(
        container, IOM.DecrementalOffer(), PSY.Source, _SOURCE_NAME, 2,
    ) ≈ [0.5, 0.3]
end
