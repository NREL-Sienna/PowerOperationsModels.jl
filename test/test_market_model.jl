# build! routes log records emitted inside build_model! to the model's internal file
# logger (operation_problem.log), so they are NOT visible to @test_logs at the call site.
function _market_model_log_contains(output_dir, needle)
    logf = joinpath(output_dir, "operation_problem.log")
    isfile(logf) || return false
    return occursin(needle, read(logf, String))
end

@testset "Empty market-component container is a validation-time ArgumentError" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")

    template = get_thermal_standard_uc_template()
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )

    # Direct unit check: no market_component_models -> ArgumentError, template contents
    # named in the message.
    err = nothing
    try
        POM._check_market_model!(template)
    catch e
        err = e
    end
    @test err isa ArgumentError
    @test occursin("no market component models", err.msg)

    # End-to-end: build! catches it and reports FAILED (never a degenerate BUILT model
    # with an unconstrained physical balance and no settlement equality).
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    @test _market_model_log_contains(output_dir, "no market component models")

    # Regression: an identical template WITHOUT a market model still builds fine and has
    # no settlement key and no physical balance slacks (use_slacks = false, the default,
    # must still mean no slacks).
    plain_template = get_thermal_standard_uc_template()
    plain_model = DecisionModel(plain_template, sys; optimizer = HiGHS_optimizer)
    @test build!(plain_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    plain_container = get_optimization_container(plain_model)
    @test !IOM.has_container_key(plain_container, IOM.SettlementBalance, PSY.System)
    @test !IOM.has_container_key(plain_container, SystemBalanceSlackUp, PSY.System)
    @test !IOM.has_container_key(plain_container, SystemBalanceSlackDown, PSY.System)
end

@testset "use_slacks = true on the network model conflicts with a market model" begin
    template = PowerOperationsProblemTemplate(
        NetworkModel(CopperPlateNetworkModel; use_slacks = true),
    )
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)

    err = nothing
    try
        POM._check_market_model!(template)
    catch e
        err = e
    end
    @test err isa ArgumentError
    @test occursin("use_slacks", err.msg)
end

@testset "Physical bids: thermal ActivePowerVariable in both balances at +1.0; load parameter physical-only" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")

    template = get_thermal_standard_uc_template()
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    # A market model needs >= 1 component model; PSY.VirtualParticipant has zero available
    # components in this fixture, so this is a no-op for the test's own point.
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    physical_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    thermal_var = IOM.get_variable(container, ActivePowerVariable, ThermalStandard)
    time_steps = axes(thermal_var)[2]

    # CopperPlate with one subnetwork: the physical row axis is a single reference bus.
    @test length(axes(physical_expr)[1]) == 1
    phys_row = only(axes(physical_expr)[1])

    # The thermal ActivePowerVariable is in BOTH the physical row and the settlement
    # row with coefficient +1.0.
    for name in axes(thermal_var)[1], t in time_steps
        v = thermal_var[name, t]
        @test JuMP.coefficient(physical_expr[phys_row, t], v) == 1.0
        @test JuMP.coefficient(settlement_expr[1, t], v) == 1.0
    end

    # The StaticPowerLoad ActivePowerTimeSeriesParameter is a fixed forecast value, not a
    # JuMP variable, so it enters a balance expression as a constant term (never a
    # coefficient on a variable). It must land in the physical row's constant and never in
    # the settlement row's constant.
    for t in time_steps
        @test !iszero(JuMP.constant(physical_expr[phys_row, t]))
        @test JuMP.constant(settlement_expr[1, t]) == 0.0
    end
end

# A compact-thermal formulation dispatches via `PowerAboveMinimumVariable` (never
# `ActivePowerVariable`) plus a pmin-scaled `OnVariable` term
# (`_add_pmin_scaled_on_to_balance!`); the settlement sweep must mirror BOTH into
# `SettlementBalance` at the same coefficients the physical `ActivePowerBalance` row carries.
function get_thermal_compact_uc_market_template()
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, ThermalStandard, ThermalCompactUnitCommitment)
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    # A market model needs at least one component model; a trivially-priced VP satisfies
    # that without being the point of this test.
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)
    return template
end

@testset "Settlement sweep covers compact-UC PowerAboveMinimumVariable + pmin-scaled OnVariable" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    vp = PSY.VirtualParticipant(;
        name = "vp1",
        available = true,
        max_supply = 1.0,
        max_demand = 0.0,
        operation_cost = PSY.MarketBidCost(;
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1000.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp)

    template = get_thermal_compact_uc_market_template()
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    physical_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    phys_row = only(axes(physical_expr)[1])

    # PowerAboveMinimumVariable: same +1.0 coefficient in both rows, every device/period.
    p_above = IOM.get_variable(container, PowerAboveMinimumVariable, ThermalStandard)
    for name in axes(p_above)[1], t in axes(p_above)[2]
        v = p_above[name, t]
        phys_coef = JuMP.coefficient(physical_expr[phys_row, t], v)
        @test JuMP.coefficient(settlement_expr[1, t], v) == phys_coef
        @test phys_coef == 1.0
    end

    # Pmin-scaled OnVariable: the settlement coefficient must equal the physical row's
    # coefficient exactly (device-specific pmin scaling), and at least one device has a
    # nonzero pmin so this is a nontrivial check, not a 0 == 0 tautology.
    on = IOM.get_variable(container, OnVariable, ThermalStandard)
    found_nonzero = false
    for name in axes(on)[1], t in axes(on)[2]
        v = on[name, t]
        phys_coef = JuMP.coefficient(physical_expr[phys_row, t], v)
        @test JuMP.coefficient(settlement_expr[1, t], v) == phys_coef
        found_nonzero |= !iszero(phys_coef)
    end
    @test found_nonzero
end

# Storage is the two-sided physical-bid case: `ActivePowerOutVariable` (discharge) and
# `ActivePowerInVariable` (charge) both enter `ActivePowerBalance`, at
# `get_variable_multiplier` = +1.0 and -1.0 respectively, so the settlement sweep must
# mirror BOTH at those same signs. A one-bus system keeps the coefficients unambiguous.
function _storage_market_test_system()
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)
    thermal = _add_simple_thermal_standard!(
        sys,
        bus,
        PSY.ThermalGenerationCost(;
            variable = PSY.CostCurve(PSY.LinearCurve(20.0)),
            fixed = 0.0,
            start_up = 0.0,
            shut_down = 0.0,
        );
        name = "thermal1",
        active_power_limits = (min = 0.0, max = 100.0),
    )
    PSY.add_time_series!(
        sys,
        thermal,
        PSY.SingleTimeSeries(
            "max_active_power",
            TimeSeries.TimeArray(
                [
                    Dates.DateTime("2020-01-01T00:00:00"),
                    Dates.DateTime("2020-01-01T01:00:00"),
                ],
                [1.0, 1.0],
            ),
        ),
    )
    _add_simple_storage!(
        sys,
        bus,
        PSY.StorageCost(;
            charge_variable_cost = PSY.CostCurve(PSY.LinearCurve(5.0)),
            discharge_variable_cost = PSY.CostCurve(PSY.LinearCurve(15.0)),
            fixed = 0.0,
            start_up = 0.0,
            shut_down = 0.0,
            energy_shortage_cost = 0.0,
            energy_surplus_cost = 0.0,
        );
        name = "storage1",
    )
    PSY.transform_single_time_series!(sys, Dates.Hour(1), Dates.Hour(1))

    # A market model needs >= 1 component model; a trivially-priced VP satisfies that
    # without being the point of this test.
    PSY.add_component!(
        sys,
        PSY.VirtualParticipant(;
            name = "vp1",
            available = true,
            settlement_point = bus,
            max_supply = 1.0,
            max_demand = 0.0,
            operation_cost = PSY.MarketBidCost(;
                incremental_offer_curves = PSY.CostCurve(
                    PSY.PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [1000.0]),
                    PSY.NU,
                ),
            ),
        ),
    )
    return sys
end

@testset "Settlement sweep mirrors storage charge/discharge at their balance signs" begin
    sys = _storage_market_test_system()

    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(
        template,
        DeviceModel(
            PSY.EnergyReservoirStorage,
            StorageDispatchWithReserves;
            attributes = Dict{String, Any}(
                "reservation" => false,
                "cycling_limits" => false,
                "energy_target" => false,
                "complete_coverage" => false,
                "regularization" => false,
            ),
        ),
    )
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    physical_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    phys_row = only(axes(physical_expr)[1])

    # Discharge at +1.0, charge at -1.0 -- the same `get_variable_multiplier` values the
    # physical row uses, so an exactly-once mirror makes the two coefficients equal.
    for (U, expected_sign) in
        ((ActivePowerOutVariable, 1.0), (ActivePowerInVariable, -1.0))
        @test get_variable_multiplier(
            U,
            PSY.EnergyReservoirStorage,
            StorageDispatchWithReserves,
        ) == expected_sign
        variable = IOM.get_variable(container, U, PSY.EnergyReservoirStorage)
        @test "storage1" in axes(variable)[1]
        for name in axes(variable)[1], t in axes(variable)[2]
            v = variable[name, t]
            @test JuMP.coefficient(physical_expr[phys_row, t], v) == expected_sign
            @test JuMP.coefficient(settlement_expr[1, t], v) == expected_sign
        end
    end
end

# One-bus fixture: a MarketBidCost thermal (increasing-slope PWL: $20/$50/$80 per MWh on
# [0,30]/[30,60]/[60,100] MW) is the only physical resource; a demand-side
# VirtualParticipant (`vp_demand`, max_demand = 70, decremental value $200/MWh) is the
# settlement's only negative (demand) contributor, always clearing to its cap since $200
# exceeds every supply option. `vp_supply` (max_supply = 50, incremental price $10/MWh)
# undercuts the thermal unit's own cheapest segment ($20), so it is included/excluded to
# compare the settlement price (lambda) with vs. without the cheap VP present. No physical
# load is needed: the physical copper-plate row is neutralized by the zero-cost slack, so it
# never constrains the settlement-driven dispatch.
function _vp_test_system(; include_vp_supply::Bool)
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)

    thermal_cost = PSY.MarketBidCost(;
        minimum_energy_offer = PSY.LinearCurve(0.0),
        start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
        shut_down = PSY.LinearCurve(0.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(
                0.0,
                [0.0, 30.0, 60.0, 100.0],
                [20.0, 50.0, 80.0],
            ),
            PSY.NU,
        ),
    )
    thermal = _add_simple_thermal_standard!(
        sys, bus, thermal_cost;
        name = "thermal1",
        active_power_limits = (min = 0.0, max = 100.0),
    )

    # DecisionModel requires the system to carry at least one forecast; nothing here
    # actually consumes it (ThermalStandardUnitCommitment dispatches off static bounds
    # and a free commitment decision, not a capacity forecast).
    PSY.add_time_series!(
        sys,
        thermal,
        PSY.SingleTimeSeries(
            "max_active_power",
            TimeSeries.TimeArray(
                [
                    Dates.DateTime("2020-01-01T00:00:00"),
                    Dates.DateTime("2020-01-01T01:00:00"),
                ],
                [1.0, 1.0],
            ),
        ),
    )
    PSY.transform_single_time_series!(sys, Dates.Hour(1), Dates.Hour(1))

    vp_demand = PSY.VirtualParticipant(;
        name = "vp_demand",
        available = true,
        settlement_point = bus,
        max_supply = 0.0,
        max_demand = 70.0,
        operation_cost = PSY.MarketBidCost(;
            decremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 70.0], [200.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp_demand)

    if include_vp_supply
        vp_supply = PSY.VirtualParticipant(;
            name = "vp_supply",
            available = true,
            settlement_point = bus,
            max_supply = 50.0,
            max_demand = 0.0,
            operation_cost = PSY.MarketBidCost(;
                incremental_offer_curves = PSY.CostCurve(
                    PSY.PiecewiseIncrementalCurve(0.0, [0.0, 50.0], [10.0]),
                    PSY.NU,
                ),
            ),
        )
        PSY.add_component!(sys, vp_supply)
    end
    return sys
end

function _vp_test_template()
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    # ThermalBasicDispatch has no OnVariable, but POM's generic
    # `_include_min_gen_power_in_constraint(::Type{<:PSY.Generator}, ActivePowerVariable, ...)
    # = true` unconditionally requires one for the PWL min-gen offset (pre-existing gap) —
    # use ThermalStandardUnitCommitment instead.
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_market_model!(
        template,
        IOM.MarketModel(
            SettlementMarket;
            settlement_domain = PSY.System,
            duals = [SettlementBalanceConstraint],
        ),
    )
    set_market_component_model!(template, PSY.VirtualParticipant, VirtualBidDispatch)
    return template
end

@testset "SettlementBalance writes its resulting value like its ActivePowerBalance/ReactivePowerBalance siblings" begin
    @test IOM.should_write_resulting_value(IOM.SettlementBalance)

    sys = _vp_test_system(; include_vp_supply = true)
    model = DecisionModel(_vp_test_template(), sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(model)
    settlement_values = read_expression(
        res,
        "SettlementBalance__System";
        table_format = TableFormat.WIDE,
    )
    @test !isempty(settlement_values)
end

@testset "VirtualBidDispatch: cheap supply VP clears at its cap and moves settlement lambda" begin
    base = PSY.get_base_power(_vp_test_system(; include_vp_supply = false))

    sys_with = _vp_test_system(; include_vp_supply = true)
    model_with = DecisionModel(
        _vp_test_template(), sys_with;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model_with; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    # Build-time (solve-independent) checks: bounds and coefficients.
    container_with = get_optimization_container(model_with)
    p_out = IOM.get_variable(container_with, ActivePowerOutVariable, PSY.VirtualParticipant)

    # (4) bounds equal max_supply / PSY.get_base_power(sys).
    @test JuMP.upper_bound(p_out["vp_supply", 1]) ≈ 50.0 / base
    @test JuMP.lower_bound(p_out["vp_supply", 1]) == 0.0

    # (3) coefficient-level: vp_supply's out variable appears in the settlement row at
    # +1.0 and in NO physical ActivePowerBalance row.
    settlement_expr =
        IOM.get_expression(container_with, IOM.SettlementBalance, PSY.System)
    @test JuMP.coefficient(settlement_expr[1, 1], p_out["vp_supply", 1]) == 1.0
    physical_expr = IOM.get_expression(container_with, ActivePowerBalance, PSY.System)
    @test JuMP.coefficient(physical_expr[1, 1], p_out["vp_supply", 1]) == 0.0
    @test !IOM.has_container_key(
        container_with,
        ActivePowerBalance,
        PSY.VirtualParticipant,
    )

    # Solve-dependent checks go through the results API (raw JuMP.value/JuMP.dual are
    # unusable here: solving the second model below leaves the first model's JuMP model
    # reporting OptimizeNotCalled() when queried directly).
    @test solve!(model_with) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res_with = OptimizationProblemOutputs(model_with)
    vp_out_with = read_variable(
        res_with,
        "ActivePowerOutVariable__VirtualParticipant";
        table_format = TableFormat.WIDE,
    )
    vp_supply_value = vp_out_with[1, "vp_supply"]
    lambda_with = read_dual(
        res_with,
        IOM.ConstraintKey(SettlementBalanceConstraint, PSY.System);
        table_format = TableFormat.WIDE,
    )[
        1,
        2,
    ]

    sys_without = _vp_test_system(; include_vp_supply = false)
    model_without =
        DecisionModel(_vp_test_template(), sys_without; optimizer = HiGHS_optimizer)
    @test build!(model_without; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model_without) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res_without = OptimizationProblemOutputs(model_without)
    lambda_without = read_dual(
        res_without,
        IOM.ConstraintKey(SettlementBalanceConstraint, PSY.System);
        table_format = TableFormat.WIDE,
    )[
        1,
        2,
    ]

    # (1) vp_supply's out variable clears at its full cap (max_supply, natural-units MW —
    # `read_variable` converts output back to MW).
    @test vp_supply_value ≈ 50.0

    # (2) lambda (the settlement balance dual) moves vs. the identical no-vp_supply solve:
    # without the cheap VP, the thermal unit alone must clear all 70 MW of demand (its
    # $80/MWh top segment sets the price); with it, the thermal unit only needs to clear
    # the residual 20 MW (its $20/MWh bottom segment sets the price). Duals are reported
    # per-unit (scaled by `base`), unlike variable values.
    @test abs(lambda_with) ≈ 20.0 * base atol = 1e-4
    @test abs(lambda_without) ≈ 80.0 * base atol = 1e-4
    @test lambda_with != lambda_without
end

# Three-period extension of `_vp_test_system` covering block bids (`curve_style`). Same
# thermal ($20/$50/$80 segments, cap 100) and vp_demand (70 MW, $200/MWh) as
# `_vp_test_system`; every period is identical (no forecast on vp_demand's own MW), so `vp_supply`'s
# in-merit/out-of-merit decision is driven purely by its own price/curve vs. thermal's
# $80/MWh top segment (thermal always serves at least 60 of the 70 MW demand, landing in
# that segment) -- not by any period-varying scarcity.
function _block_bid_test_system(; vp_supply_curve, vp_supply_style)
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)

    thermal_cost = PSY.MarketBidCost(;
        minimum_energy_offer = PSY.LinearCurve(0.0),
        start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
        shut_down = PSY.LinearCurve(0.0),
        incremental_offer_curves = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(
                0.0,
                [0.0, 30.0, 60.0, 100.0],
                [20.0, 50.0, 80.0],
            ),
            PSY.NU,
        ),
    )
    thermal = _add_simple_thermal_standard!(
        sys, bus, thermal_cost;
        name = "thermal1",
        active_power_limits = (min = 0.0, max = 100.0),
    )
    PSY.add_time_series!(
        sys,
        thermal,
        PSY.SingleTimeSeries(
            "max_active_power",
            TimeSeries.TimeArray(
                [
                    Dates.DateTime("2020-01-01T00:00:00"),
                    Dates.DateTime("2020-01-01T01:00:00"),
                    Dates.DateTime("2020-01-01T02:00:00"),
                    Dates.DateTime("2020-01-01T03:00:00"),
                ],
                [1.0, 1.0, 1.0, 1.0],
            ),
        ),
    )
    PSY.transform_single_time_series!(sys, Dates.Hour(3), Dates.Hour(3))

    vp_demand = PSY.VirtualParticipant(;
        name = "vp_demand",
        available = true,
        settlement_point = bus,
        max_supply = 0.0,
        max_demand = 70.0,
        operation_cost = PSY.MarketBidCost(;
            decremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 70.0], [200.0]),
                PSY.NU,
            ),
        ),
    )
    PSY.add_component!(sys, vp_demand)

    vp_supply = PSY.VirtualParticipant(;
        name = "vp_supply",
        available = true,
        settlement_point = bus,
        max_supply = 10.0,
        max_demand = 0.0,
        operation_cost = PSY.MarketBidCost(;
            curve_style = vp_supply_style,
            incremental_offer_curves = vp_supply_curve,
        ),
    )
    PSY.add_component!(sys, vp_supply)
    return sys
end

_single_segment_curve(price) =
    PSY.CostCurve(PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [price]), PSY.NU)

# A kink at half the block: the first 5 MW at $10/MWh always undercuts thermal's cheapest
# relevant segment; the next 5 MW at $250/MWh never does. Gives a curve-driven (not
# scarcity-driven) fractional optimum independent of thermal capacity.
_kinked_curve() =
    PSY.CostCurve(
        PSY.PiecewiseIncrementalCurve(0.0, [0.0, 5.0, 10.0], [10.0, 250.0]),
        PSY.NU,
    )

@testset "Block bids: FIXED clears identically in every period or not at all (price straddle)" begin
    for (price, expect_commit) in ((50.0, true), (95.0, false))
        sys = _block_bid_test_system(;
            vp_supply_curve = _single_segment_curve(price),
            vp_supply_style = PSY.CurveStyles.FIXED,
        )
        model = DecisionModel(
            _vp_test_template(), sys;
            optimizer = HiGHS_optimizer, store_variable_names = true,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        container = get_optimization_container(model)
        z = IOM.get_variable(
            container, BlockBidCommitmentVariable, PSY.VirtualParticipant, "Out")
        settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
        base = PSY.get_base_power(sys)

        # Coefficient check: the FIXED variable is the SAME shared JuMP variable, entered
        # into all three periods' settlement rows at coefficient max_supply/base.
        @test z["vp_supply", 1] === z["vp_supply", 2] === z["vp_supply", 3]
        for t in 1:3
            @test JuMP.coefficient(settlement_expr[1, t], z["vp_supply", t]) ≈ 10.0 / base
        end

        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        res = OptimizationProblemOutputs(model)
        z_values = read_variable(
            res, "BlockBidCommitmentVariable__VirtualParticipant__Out";
            table_format = TableFormat.WIDE,
        )
        cleared = 0.0
        if expect_commit
            cleared = 1.0
        end
        for t in 1:3
            @test z_values[t, "vp_supply"] ≈ cleared atol = 1e-6
        end
    end
end

@testset "Block bids: VARIABLE clears one shared fraction; CURVE clears each period independently" begin
    sys_variable = _block_bid_test_system(;
        vp_supply_curve = _kinked_curve(),
        vp_supply_style = PSY.CurveStyles.VARIABLE,
    )
    model_variable = DecisionModel(
        _vp_test_template(), sys_variable;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model_variable; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container_variable = get_optimization_container(model_variable)
    p_out_variable =
        IOM.get_variable(container_variable, ActivePowerOutVariable, PSY.VirtualParticipant)
    # VARIABLE reuses the SAME JuMP variable at every period: a single shared fraction of
    # the block, cleared identically at every period.
    @test p_out_variable["vp_supply", 1] === p_out_variable["vp_supply", 2] ===
          p_out_variable["vp_supply", 3]

    @test solve!(model_variable) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res_variable = OptimizationProblemOutputs(model_variable)
    variable_values = read_variable(
        res_variable, "ActivePowerOutVariable__VirtualParticipant";
        table_format = TableFormat.WIDE,
    )
    # Only the cheap ($10) 5 MW half-segment is in merit against thermal's $80/MWh top
    # segment; the $250 half never is -> exactly half the block clears, every period.
    for t in 1:3
        @test variable_values[t, "vp_supply"] ≈ 5.0 atol = 1e-6
    end

    sys_curve = _block_bid_test_system(;
        vp_supply_curve = _kinked_curve(),
        vp_supply_style = PSY.CurveStyles.CURVE,
    )
    model_curve = DecisionModel(
        _vp_test_template(), sys_curve;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model_curve; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container_curve = get_optimization_container(model_curve)
    p_out_curve =
        IOM.get_variable(container_curve, ActivePowerOutVariable, PSY.VirtualParticipant)
    # CURVE: a distinct JuMP variable per period, unlike VARIABLE's/FIXED's single shared
    # decision.
    @test p_out_curve["vp_supply", 1] !== p_out_curve["vp_supply", 2]
    @test p_out_curve["vp_supply", 2] !== p_out_curve["vp_supply", 3]

    @test solve!(model_curve) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res_curve = OptimizationProblemOutputs(model_curve)
    curve_values = read_variable(
        res_curve, "ActivePowerOutVariable__VirtualParticipant";
        table_format = TableFormat.WIDE,
    )
    for t in 1:3
        @test curve_values[t, "vp_supply"] ≈ 5.0 atol = 1e-6
    end
end

@testset "Block bids: nonzero VOM on a FIXED/VARIABLE device is rejected loudly" begin
    _vom_test_vp(name, style) = PSY.VirtualParticipant(;
        name = name,
        available = true,
        max_supply = 10.0,
        max_demand = 0.0,
        operation_cost = PSY.MarketBidCost(;
            curve_style = style,
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [50.0]),
                PSY.NU,
                PSY.LinearCurve(5.0),
            ),
        ),
    )

    # FIXED: rejected, with device name / curve style / VOM value in the message.
    vp_fixed = _vom_test_vp("vp_fixed", PSY.CurveStyles.FIXED)
    err_fixed = nothing
    try
        POM._validate_block_bid_vom!(vp_fixed, PSY.CurveStyles.FIXED)
    catch e
        err_fixed = e
    end
    @test err_fixed isa ErrorException
    @test occursin("vp_fixed", err_fixed.msg)
    @test occursin("FIXED", err_fixed.msg)
    @test occursin("5.0", err_fixed.msg)

    # VARIABLE: rejected the same way.
    vp_variable = _vom_test_vp("vp_variable", PSY.CurveStyles.VARIABLE)
    err_variable = nothing
    try
        POM._validate_block_bid_vom!(vp_variable, PSY.CurveStyles.VARIABLE)
    catch e
        err_variable = e
    end
    @test err_variable isa ErrorException
    @test occursin("vp_variable", err_variable.msg)
    @test occursin("VARIABLE", err_variable.msg)
    @test occursin("5.0", err_variable.msg)

    # CURVE: the same nonzero VOM is untouched -- CURVE devices route through the
    # standard `add_variable_cost!` path, which handles VOM correctly.
    vp_curve = _vom_test_vp("vp_curve", PSY.CurveStyles.CURVE)
    POM._validate_block_bid_vom!(vp_curve, PSY.CurveStyles.CURVE)

    # Zero VOM (the default) never throws, regardless of style.
    vp_zero_vom = PSY.VirtualParticipant(;
        name = "vp_zero_vom",
        available = true,
        max_supply = 10.0,
        max_demand = 0.0,
        operation_cost = PSY.MarketBidCost(;
            curve_style = PSY.CurveStyles.FIXED,
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [50.0]), PSY.NU,
            ),
        ),
    )
    POM._validate_block_bid_vom!(vp_zero_vom, PSY.CurveStyles.FIXED)

    # End-to-end: a FIXED VP with nonzero VOM fails the full build.
    sys = _block_bid_test_system(;
        vp_supply_curve = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 10.0], [50.0]),
            PSY.NU,
            PSY.LinearCurve(5.0),
        ),
        vp_supply_style = PSY.CurveStyles.FIXED,
    )
    model = DecisionModel(
        _vp_test_template(), sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    @test _market_model_log_contains(output_dir, "VOM cost")
end

@testset "CURVE VP's VOM is per-variable direction (own curve's VOM, not the formulation default)" begin
    # Unit-level: the dispatch table itself.
    @test IOM._vom_offer_direction(ActivePowerOutVariable, VirtualBidDispatch) ==
          IOM.IncrementalOffer()
    @test IOM._vom_offer_direction(ActivePowerInVariable, VirtualBidDispatch) ==
          IOM.DecrementalOffer()

    # End-to-end, coefficient-level: a two-sided CURVE VP with DISTINCT nonzero VOM on
    # each side. Resolving the direction from the formulation alone would make In's VOM read
    # Out's ($2) curve instead of its own ($7). VOM is the ONLY way either variable
    # enters the objective directly (the PWL delta machinery links p = Σδ_k via a
    # CONSTRAINT, never adding p itself to the objective), so the coefficient on p_out/p_in
    # in the objective isolates the VOM contribution exactly; their ratio must be 7.0/2.0.
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)
    vp = PSY.VirtualParticipant(;
        name = "vp_two_sided",
        available = true,
        settlement_point = bus,
        max_supply = 50.0,
        max_demand = 50.0,
        operation_cost = PSY.MarketBidCost(;
            curve_style = PSY.CurveStyles.CURVE,
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 50.0], [10.0]),
                PSY.NU,
                PSY.LinearCurve(2.0),
            ),
            decremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, 50.0], [20.0]),
                PSY.NU,
                PSY.LinearCurve(7.0),
            ),
        ),
    )
    PSY.add_component!(sys, vp)

    thermal_cost = PSY.ThermalGenerationCost(;
        variable = PSY.CostCurve(PSY.LinearCurve(20.0)),
        fixed = 0.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    thermal = _add_simple_thermal_standard!(
        sys, bus, thermal_cost;
        name = "thermal1",
        active_power_limits = (min = 0.0, max = 100.0),
    )
    times = TimeSeries.TimeArray(
        [Dates.DateTime("2020-01-01T00:00:00"), Dates.DateTime("2020-01-01T01:00:00")],
        [1.0, 1.0],
    )
    PSY.add_time_series!(sys, thermal, PSY.SingleTimeSeries("max_active_power", times))
    PSY.transform_single_time_series!(sys, Dates.Hour(1), Dates.Hour(1))

    template = _vp_test_template()
    model = DecisionModel(
        template, sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    p_out = IOM.get_variable(container, ActivePowerOutVariable, PSY.VirtualParticipant)
    p_in = IOM.get_variable(container, ActivePowerInVariable, PSY.VirtualParticipant)
    obj = JuMP.objective_function(get_jump_model(container))
    for t in axes(p_out)[2]
        coef_out = JuMP.coefficient(obj, p_out["vp_two_sided", t])
        coef_in = JuMP.coefficient(obj, p_in["vp_two_sided", t])
        @test !iszero(coef_out)
        @test !iszero(coef_in)
        @test coef_in / coef_out ≈ 7.0 / 2.0 atol = 1e-8
    end
end

@testset "FIXED/VARIABLE offer curve span must match its envelope (max_supply/max_demand)" begin
    _span_test_vp(name, style, max_supply, curve_span) = PSY.VirtualParticipant(;
        name = name,
        available = true,
        max_supply = max_supply,
        max_demand = 0.0,
        operation_cost = PSY.MarketBidCost(;
            curve_style = style,
            incremental_offer_curves = PSY.CostCurve(
                PSY.PiecewiseIncrementalCurve(0.0, [0.0, curve_span], [50.0]),
                PSY.NU,
            ),
        ),
    )

    # Mismatch: curve spans [0, 5] but max_supply = 10 -> rejected, both values named.
    vp_mismatch = _span_test_vp("vp_mismatch", PSY.CurveStyles.FIXED, 10.0, 5.0)
    err = nothing
    try
        POM._validate_block_bid_span!(vp_mismatch, PSY.CurveStyles.FIXED)
    catch e
        err = e
    end
    @test err isa ErrorException
    @test occursin("vp_mismatch", err.msg)
    @test occursin("10.0", err.msg)
    @test occursin("5.0", err.msg)

    # Match: curve spans [0, 10] and max_supply = 10 -> no error.
    vp_match = _span_test_vp("vp_match", PSY.CurveStyles.FIXED, 10.0, 10.0)
    @test POM._validate_block_bid_span!(vp_match, PSY.CurveStyles.FIXED) === nothing

    # VARIABLE: same rule applies.
    vp_variable_mismatch =
        _span_test_vp("vp_variable_mismatch", PSY.CurveStyles.VARIABLE, 10.0, 5.0)
    err_var = nothing
    try
        POM._validate_block_bid_span!(vp_variable_mismatch, PSY.CurveStyles.VARIABLE)
    catch e
        err_var = e
    end
    @test err_var isa ErrorException

    # CURVE is exempt (its own per-period variable is bounded directly by the curve, no
    # separate envelope to mismatch).
    vp_curve_mismatch = _span_test_vp("vp_curve_mismatch", PSY.CurveStyles.CURVE, 10.0, 5.0)
    @test POM._validate_block_bid_span!(vp_curve_mismatch, PSY.CurveStyles.CURVE) ===
          nothing

    # End-to-end: a FIXED VP with a mismatched span fails the full build.
    sys_mismatch = _block_bid_test_system(;
        vp_supply_curve = PSY.CostCurve(
            PSY.PiecewiseIncrementalCurve(0.0, [0.0, 5.0], [50.0]),
            PSY.NU,
        ),
        vp_supply_style = PSY.CurveStyles.FIXED,
    )
    model_mismatch = DecisionModel(
        _vp_test_template(), sys_mismatch;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(model_mismatch; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    @test _market_model_log_contains(output_dir, "envelope")

    # A matching-span build still succeeds (regression: `_block_bid_test_system`'s
    # `_single_segment_curve` fixtures span [0, 10], matching its hardcoded max_supply = 10).
    sys_match = _block_bid_test_system(;
        vp_supply_curve = _single_segment_curve(50.0),
        vp_supply_style = PSY.CurveStyles.FIXED,
    )
    model_match = DecisionModel(
        _vp_test_template(), sys_match;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model_match; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

# One-bus MarketLoadBid fixture: a cheap thermal (`ThermalStandardUnitCommitment`,
# $20/MWh), a plain physical `PowerLoad` (20 MW), and an `InterruptiblePowerLoad` (`il1`,
# max_active_power = 30 MW) registered TWICE -- once in `template.devices` as a
# `StaticPowerLoad` twin (carries `il1`'s physical forecast, and is what lets the reserve
# service machinery find `InterruptiblePowerLoad` as a contributing type -- see the
# `MarketLoadBid` docstring), and once in the market container as `MarketLoadBid` (the AS-only
# zero-cost energy bid). `il1`'s default `MarketBidCost()` has no decremental offer curve, so
# `_is_costless_offer` is true and its market energy variable is fixed to zero.
#
# `il1` is the sole contributor to `Reserve1` (`OnlineReserve{ReserveUp}`, requirement 10 MW).
# Because the market energy variable is fixed at zero, the settlement balance (thermal's award
# is its only other term) forces the thermal unit to clear zero energy too -- so the physical
# balance's entire 50 MW (20 MW static load + 30 MW il1 forecast) is served by the market
# model's zero-cost `SystemBalanceSlackUp`, deterministically (not merely cost-optimal).
function _market_load_test_system()
    sys = PSY.System(100.0)
    bus = _add_simple_bus!(sys)
    times = TimeSeries.TimeArray(
        [Dates.DateTime("2020-01-01T00:00:00"), Dates.DateTime("2020-01-01T01:00:00")],
        [1.0, 1.0],
    )

    # A plain (non-PWL) cost: a MarketBidCost's delta-PWL segment bound is mis-scaled in the
    # `DecisionModel`'s auto-generated initial-conditions sub-problem (a pre-existing gap; it
    # surfaces only when a hard physical demand forces the PWL-costed unit to a nonzero
    # dispatch there, which none of the other market-model tests in this file do). A plain
    # cost sidesteps it; thermal is forced to clear zero in the MAIN model's
    # settlement balance regardless (see the testset docstring below), so its cost curve choice
    # does not affect this test's assertions.
    thermal_cost = PSY.ThermalGenerationCost(;
        variable = PSY.CostCurve(PSY.LinearCurve(20.0)),
        fixed = 0.0,
        start_up = 0.0,
        shut_down = 0.0,
    )
    thermal = _add_simple_thermal_standard!(
        sys, bus, thermal_cost;
        name = "thermal1",
        active_power_limits = (min = 0.0, max = 100.0),
    )
    PSY.add_time_series!(sys, thermal, PSY.SingleTimeSeries("max_active_power", times))

    static_load = PSY.PowerLoad(;
        name = "load1",
        available = true,
        bus = bus,
        active_power = 20.0,
        reactive_power = 0.0,
        base_power = 100.0,
        max_active_power = 20.0,
        max_reactive_power = 0.0,
    )
    PSY.add_component!(sys, static_load)
    PSY.add_time_series!(sys, static_load, PSY.SingleTimeSeries("max_active_power", times))

    il = PSY.InterruptiblePowerLoad(;
        name = "il1",
        available = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        max_active_power = 30.0,
        max_reactive_power = 0.0,
        operation_cost = PSY.MarketBidCost(),
        base_power = 100.0,
    )
    PSY.add_component!(sys, il)
    PSY.add_time_series!(sys, il, PSY.SingleTimeSeries("max_active_power", times))

    PSY.transform_single_time_series!(sys, Dates.Hour(1), Dates.Hour(1))

    reserve = PSY.OnlineReserve{PSY.ReserveUp}("Reserve1", true, 60.0, 10.0)
    PSY.add_service!(sys, reserve, [il])
    return sys
end

function _market_load_test_template()
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, PSY.PowerLoad, StaticPowerLoad)
    # The physical twin: carries il1's forecast on the physical balance, and its mere
    # presence in `template.devices` is what makes `InterruptiblePowerLoad` a contributing
    # type for reserve-service construction (see the `MarketLoadBid` docstring).
    set_device_model!(template, PSY.InterruptiblePowerLoad, StaticPowerLoad)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(template, PSY.InterruptiblePowerLoad, MarketLoadBid)
    return template
end

@testset "MarketLoadBid: zero-cost load clears zero energy while providing up-reserve" begin
    sys = _market_load_test_system()
    model = DecisionModel(
        _market_load_test_template(), sys;
        optimizer = HiGHS_optimizer, store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    p = IOM.get_variable(container, ActivePowerVariable, PSY.InterruptiblePowerLoad)
    settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
    physical_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    time_steps = axes(p)[2]

    # Build-time: the costless market bid fixes the energy variable to zero every period.
    for t in time_steps
        @test JuMP.is_fixed(p["il1", t])
        @test JuMP.fix_value(p["il1", t]) == 0.0
    end

    # Exactly-once settlement coefficient (no double count with the physical-bid sweep,
    # which never sees this variable since it only sweeps `template.devices`): -1.0, like a
    # decremental VirtualParticipant.
    for t in time_steps
        @test JuMP.coefficient(settlement_expr[1, t], p["il1", t]) == -1.0
    end

    # il1's market variable never enters the physical balance; its StaticPowerLoad twin
    # contributes il1's forecast there as a constant, together with the plain static load.
    for t in time_steps
        @test JuMP.coefficient(physical_expr[1, t], p["il1", t]) == 0.0
        @test !iszero(JuMP.constant(physical_expr[1, t]))
    end

    # Reserve range: 0 <= max_active_power - r_up <= max_active_power (anchored on the
    # parameter, not the zero-fixed variable) -- exists and is finite even before solving.
    @test IOM.has_container_key(
        container,
        ActivePowerRangeExpressionLB,
        PSY.InterruptiblePowerLoad,
    )
    @test IOM.has_container_key(
        container,
        ActivePowerRangeExpressionUB,
        PSY.InterruptiblePowerLoad,
    )

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    reserve = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    requirement_pu = PSY.get_requirement(reserve, PSY.SU)
    award =
        IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    for t in time_steps
        # (2) The reserve award meets the requirement exactly (il1 is the sole contributor,
        # bounded above by its participation-factor cap at the same value).
        @test JuMP.value(award[("Reserve1", "il1", t)]) ≈ requirement_pu atol = 1e-6
        @test JuMP.value(award[("Reserve1", "il1", t)]) > 0.0

        # (1) P == 0 post-solve too.
        @test JuMP.value(p["il1", t]) ≈ 0.0 atol = 1e-8
    end

    # The zero-cost physical slack's NET value (up - down) equals the forecast minus
    # cleared physical injections, computed from PSY getters rather than a literal.
    # The up/down SPLIT is not unique under a market model (both are free and
    # unpenalized, so any (s_up, s_dn) = (a + k, k) is optimal) -- only the net is a
    # well-defined unserved-load measure, so that is what's asserted here, never s_up
    # alone. With il1's market energy pinned at zero, the settlement balance forces the
    # thermal unit's award to zero too, so the injection term is 0 every period and the
    # net slack must equal the total forecast (20 MW static load + 30 MW il1) exactly.
    static_load = PSY.get_component(PSY.PowerLoad, sys, "load1")
    il1 = PSY.get_component(PSY.InterruptiblePowerLoad, sys, "il1")
    forecast_total =
        PSY.get_max_active_power(static_load, PSY.SU) +
        PSY.get_max_active_power(il1, PSY.SU)
    thermal_p = IOM.get_variable(container, ActivePowerVariable, ThermalStandard)
    slack_up = IOM.get_variable(container, SystemBalanceSlackUp, PSY.System)
    slack_dn = IOM.get_variable(container, SystemBalanceSlackDown, PSY.System)
    obj = JuMP.objective_function(get_jump_model(container))
    for t in time_steps
        @test JuMP.coefficient(obj, slack_up[1, t]) == 0.0
        @test JuMP.coefficient(obj, slack_dn[1, t]) == 0.0
        cleared_injection = JuMP.value(thermal_p["thermal1", t])
        @test cleared_injection ≈ 0.0 atol = 1e-8
        net_slack = JuMP.value(slack_up[1, t]) - JuMP.value(slack_dn[1, t])
        @test net_slack ≈ forecast_total - cleared_injection atol = 1e-6
    end
end

@testset "VP and MarketLoadBid costs register in ProductionCostExpression like device costs" begin
    sys_vp = _vp_test_system(; include_vp_supply = true)
    model_vp = DecisionModel(_vp_test_template(), sys_vp; optimizer = HiGHS_optimizer)
    @test build!(model_vp; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container_vp = get_optimization_container(model_vp)
    @test IOM.has_container_key(
        container_vp,
        ProductionCostExpression,
        PSY.VirtualParticipant,
    )
    vp_expr =
        IOM.get_expression(container_vp, ProductionCostExpression, PSY.VirtualParticipant)
    @test "vp_supply" in axes(vp_expr)[1]

    sys_load = _market_load_test_system()
    model_load = DecisionModel(
        _market_load_test_template(), sys_load;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model_load; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container_load = get_optimization_container(model_load)
    @test IOM.has_container_key(
        container_load,
        ProductionCostExpression,
        PSY.InterruptiblePowerLoad,
    )
    load_expr =
        IOM.get_expression(
            container_load,
            ProductionCostExpression,
            PSY.InterruptiblePowerLoad,
        )
    @test "il1" in axes(load_expr)[1]
end

@testset "MarketLoadBid contributing to a ReserveDown service is a loud, named error" begin
    sys = _market_load_test_system()
    il1 = PSY.get_component(PSY.InterruptiblePowerLoad, sys, "il1")
    reserve_down = PSY.OnlineReserve{PSY.ReserveDown}("ReserveDown1", true, 60.0, 5.0)
    PSY.add_service!(sys, reserve_down, [il1])

    # Unit-level.
    err = nothing
    try
        POM._validate_no_reserve_down!(il1)
    catch e
        err = e
    end
    @test err isa ErrorException
    @test occursin("il1", err.msg)
    @test occursin("ReserveDown1", err.msg)

    # End-to-end: build fails with the same device/service names in the log.
    template = _market_load_test_template()
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveDown}, RangeReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    @test _market_model_log_contains(output_dir, "il1")
    @test _market_model_log_contains(output_dir, "ReserveDown1")
end

# ---------------------------------------------------------------------------------------
# End-to-end acceptance: one thin testset per market-model guarantee, each standing alone
# as that guarantee's evidence. Where a guarantee is already proven in full above, only the
# minimum non-duplicated check is repeated here -- a build-time fact where one suffices,
# rather than re-running a solve already paid for.
# ---------------------------------------------------------------------------------------
@testset "Market model acceptance" begin
    @testset "VP supply award moves settlement lambda vs the no-VP solve" begin
        sys_with = _vp_test_system(; include_vp_supply = true)
        model_with =
            DecisionModel(_vp_test_template(), sys_with; optimizer = HiGHS_optimizer)
        @test build!(model_with; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model_with) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        lambda_with = read_dual(
            OptimizationProblemOutputs(model_with),
            IOM.ConstraintKey(SettlementBalanceConstraint, PSY.System);
            table_format = TableFormat.WIDE,
        )[
            1,
            2,
        ]

        sys_without = _vp_test_system(; include_vp_supply = false)
        model_without =
            DecisionModel(_vp_test_template(), sys_without; optimizer = HiGHS_optimizer)
        @test build!(model_without; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model_without) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        lambda_without = read_dual(
            OptimizationProblemOutputs(model_without),
            IOM.ConstraintKey(SettlementBalanceConstraint, PSY.System);
            table_format = TableFormat.WIDE,
        )[
            1,
            2,
        ]

        @test lambda_with != lambda_without
    end

    @testset "Gen dispatch variable in both balances at matched coefficients" begin
        # Storage's two-sided coverage of the same guarantee is asserted separately in
        # "Settlement sweep mirrors storage charge/discharge at their balance signs".
        sys = _vp_test_system(; include_vp_supply = true)
        model = DecisionModel(_vp_test_template(), sys; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        container = get_optimization_container(model)
        physical_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
        settlement_expr = IOM.get_expression(container, IOM.SettlementBalance, PSY.System)
        thermal_var = IOM.get_variable(container, ActivePowerVariable, ThermalStandard)
        for t in axes(thermal_var)[2]
            v = thermal_var["thermal1", t]
            @test JuMP.coefficient(physical_expr[1, t], v) == 1.0
            @test JuMP.coefficient(settlement_expr[1, t], v) == 1.0
        end
    end

    @testset "Block-bid identity: FIXED shared var / VARIABLE shared var / CURVE per-period" begin
        sys_fixed = _block_bid_test_system(;
            vp_supply_curve = _single_segment_curve(50.0),
            vp_supply_style = PSY.CurveStyles.FIXED,
        )
        model_fixed =
            DecisionModel(_vp_test_template(), sys_fixed; optimizer = HiGHS_optimizer)
        @test build!(model_fixed; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        z = IOM.get_variable(
            get_optimization_container(model_fixed),
            BlockBidCommitmentVariable,
            PSY.VirtualParticipant,
            "Out",
        )
        @test z["vp_supply", 1] === z["vp_supply", 2] === z["vp_supply", 3]

        sys_variable = _block_bid_test_system(;
            vp_supply_curve = _kinked_curve(),
            vp_supply_style = PSY.CurveStyles.VARIABLE,
        )
        model_variable =
            DecisionModel(_vp_test_template(), sys_variable; optimizer = HiGHS_optimizer)
        @test build!(model_variable; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        p_out_variable = IOM.get_variable(
            get_optimization_container(model_variable),
            ActivePowerOutVariable,
            PSY.VirtualParticipant,
        )
        @test p_out_variable["vp_supply", 1] === p_out_variable["vp_supply", 2] ===
              p_out_variable["vp_supply", 3]

        sys_curve = _block_bid_test_system(;
            vp_supply_curve = _kinked_curve(),
            vp_supply_style = PSY.CurveStyles.CURVE,
        )
        model_curve =
            DecisionModel(_vp_test_template(), sys_curve; optimizer = HiGHS_optimizer)
        @test build!(model_curve; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        p_out_curve = IOM.get_variable(
            get_optimization_container(model_curve),
            ActivePowerOutVariable,
            PSY.VirtualParticipant,
        )
        @test p_out_curve["vp_supply", 1] !== p_out_curve["vp_supply", 2] !==
              p_out_curve["vp_supply", 3]
    end

    @testset "Zero-cost load's market energy variable is fixed to zero at build time" begin
        sys = _market_load_test_system()
        model = DecisionModel(
            _market_load_test_template(), sys;
            optimizer = HiGHS_optimizer,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        p = IOM.get_variable(
            get_optimization_container(model), ActivePowerVariable,
            PSY.InterruptiblePowerLoad)
        for t in axes(p)[2]
            @test JuMP.is_fixed(p["il1", t])
            @test JuMP.fix_value(p["il1", t]) == 0.0
        end
    end

    @testset "Physical balance slack is zero-cost at build time" begin
        sys = _market_load_test_system()
        model = DecisionModel(
            _market_load_test_template(), sys;
            optimizer = HiGHS_optimizer,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        container = get_optimization_container(model)
        slack_up = IOM.get_variable(container, SystemBalanceSlackUp, PSY.System)
        obj = JuMP.objective_function(get_jump_model(container))
        for t in axes(slack_up)[2], k in axes(slack_up)[1]
            @test JuMP.coefficient(obj, slack_up[k, t]) == 0.0
        end
    end

    @testset "market_model = nothing leaves the template and build untouched" begin
        sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
        template = get_thermal_standard_uc_template()
        @test get_market_model(template) === nothing
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        container = get_optimization_container(model)
        @test !IOM.has_container_key(container, IOM.SettlementBalance, PSY.System)
        @test !IOM.has_container_key(container, SystemBalanceSlackUp, PSY.System)
        @test !IOM.has_container_key(container, SystemBalanceSlackDown, PSY.System)
    end
end
