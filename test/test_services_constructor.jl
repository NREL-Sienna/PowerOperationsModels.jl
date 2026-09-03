# Time-varying operating reserve demand curve (ORDC): an `OnlineReserve` whose `variable` is a
# `CostCurve{TimeSeriesPiecewiseIncrementalCurve}`. Multi-step Simulation scenarios are omitted:
# the Simulation framework is not available in the IOM/POM split.

# Build a time-varying ORDC from the system's existing static ORDC baseline curve, backing it
# with a deterministic cost-curve forecast.
function _add_ts_ordc!(
    sys,
    name::String,
    static_ordc;
    incrs_x = (0.0, 0.0, 0.0),
    incrs_y = (0.0, 0.0, 0.0),
    create_extra_tranches = false,
)
    baseline_curve = PSY.get_variable(static_ordc)
    power_units = PSY.get_power_units(baseline_curve)
    fd = PSY.get_function_data(PSY.get_value_curve(baseline_curve))

    # Construct with the default `variable` (the ZERO_OFFER_CURVE "no curve" placeholder);
    # the real forecast is attached and set below — its key exists only after attachment.
    ordc_ts = OnlineReserve{ReserveUp}(;
        name = name,
        available = true,
        time_frame = PSY.get_time_frame(static_ordc),
    )
    add_service!(sys, ordc_ts, get_components(ThermalStandard, sys))

    pwl_ts = make_deterministic_ts(
        sys,
        "variable_cost",
        fd,
        incrs_x,
        incrs_y;
        override_min_x = 0.0,
        override_max_x = last(get_x_coords(fd)),
        create_extra_tranches = create_extra_tranches,
    )
    pwl_key = add_time_series!(sys, ordc_ts, pwl_ts)
    PSY.set_variable!(ordc_ts, PSY.make_market_bid_ts_curve(pwl_key, nothing, power_units))
    return ordc_ts
end

@testset "Test ORDC time series (build)" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    static_ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, c_sys5_uc))
    _add_ts_ordc!(c_sys5_uc, "ORDC_TS", static_ordc)

    template = get_thermal_standard_uc_template()
    # One per-type model covers both OnlineReserve{ReserveUp} services
    # (Reserve1 and Reserve11).
    # OnlineReserve{ReserveUp} carries the ORDC, so it uses StepwiseCostReserve; the curve-less
    # requirement reserves of that direction are supply-only under the degenerate-demand skip.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    model = DecisionModel(
        template,
        c_sys5_uc;
        store_variable_names = true,
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "Test Reserve Requirement Slack Variables" begin
    # `use_slacks = true` on a reserve ServiceModel triggers `add_reserve_slacks!`
    # (services_models/service_slacks.jl), which builds ReserveRequirementSlack as a dense
    # 2D container over the type's service-name axis and the time-step axis.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_standard_uc_template()
    set_service_model!(
        template,
        ServiceModel(
            OnlineReserve{ReserveUp},
            RangeReserve;
            use_slacks = true,
        ),
    )
    model = DecisionModel(
        template,
        c_sys5_uc;
        store_variable_names = true,
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    # ReserveRequirementSlack is one dense container per service type keyed
    # `[service_name, time]`, built once over all the type's services.
    slack_var = IOM.get_variable(
        container,
        ReserveRequirementSlack,
        OnlineReserve{ReserveUp},
    )
    time_steps = get_time_steps(container)
    @test all(JuMP.lower_bound(slack_var["Reserve1", t]) == 0.0 for t in time_steps)

    # Confirm the slack is actually wired into the requirement constraint (not just
    # created and left dangling): its objective coefficient should be the penalty cost.
    obj = JuMP.objective_function(get_jump_model(model))
    @test all(
        JuMP.coefficient(obj, slack_var["Reserve1", t]) == POM.SERVICES_SLACK_COST for
        t in time_steps
    )
end

@testset "Per-type reserve container isolates services of the same type" begin
    # Two OnlineReserve{ReserveUp} services share one
    # `(service, device, time)` ActivePowerReserveVariable container. Verify (a) each
    # service's requirement constraint sums only its own device variables (no
    # cross-service leakage) and (b) the proportional reserve cost prices each variable
    # exactly once (no double counting across the per-type objective pass).
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    # One per-type model covers both OnlineReserve{ReserveUp} services.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        OnlineReserve{ReserveUp},
    )
    # One container spans every OnlineReserve{ReserveUp} in the system. ORDC1 is one of them: it
    # carries a demand curve but no requirement, so under RangeReserve its demand-side model is
    # skipped and it is supply-only - it keeps award variables but gets no requirement rows.
    @test Set(k[1] for k in keys(rv.data)) == Set(["Reserve1", "Reserve11", "ORDC1"])
    @test Set(axes(con)[1]) == Set(["Reserve1", "Reserve11"])

    # (a) Reserve1's requirement constraint at t=1 has coefficient 1 for Reserve1's
    # variables and 0 for Reserve11's.
    c1 = con["Reserve1", 1]
    for (key, var) in rv.data
        key[3] == 1 || continue
        expected = key[1] == "Reserve1" ? 1.0 : 0.0
        @test JuMP.normalized_coefficient(c1, var) == expected
    end

    # (b) Each reserve variable of a demand-imposing service is priced exactly once at
    # DEFAULT_RESERVE_COST / base. A skipped (supply-only) service gets no flat cost: its awards
    # are driven by a group or by its own offers, not by this fallback.
    obj = JuMP.objective_function(get_jump_model(model))
    base_p = get_model_base_power(container)
    expected_cost = POM.DEFAULT_RESERVE_COST / base_p
    for (key, var) in rv.data
        expected = key[1] == "ORDC1" ? 0.0 : expected_cost
        @test JuMP.coefficient(obj, var) == expected
    end
end

@testset "Services sharing one requirement forecast share a parameter row" begin
    # Bulk `add_time_series!` stores one array for both services, so both resolve to the same
    # UUID. The UUID parameter axis must dedupe or JuMP rejects the repeated axis element.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    r11 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve11")
    PSY.set_requirement!(r11, 2 * PSY.get_requirement(r1, PSY.SU) * PSY.SU)
    forecast = PSY.get_time_series(PSY.Deterministic, r1, "requirement")
    PSY.remove_time_series!(sys, PSY.Deterministic, r1, "requirement")
    PSY.remove_time_series!(sys, PSY.Deterministic, r11, "requirement")
    PSY.add_time_series!(sys, [r1, r11], forecast)
    requirement_hashes =
        IS.get_time_series_hashes((r1, r11), PSY.Deterministic, "requirement")
    @test requirement_hashes[IS.get_id(r1)] == requirement_hashes[IS.get_id(r11)]

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    param_container = IOM.get_parameter(
        container,
        RequirementTimeSeriesParameter,
        OnlineReserve{ReserveUp},
    )
    # One parameter row for the shared series; still one multiplier row per service.
    @test length(axes(IOM.get_parameter_array(param_container))[1]) == 1
    @test Set(axes(IOM.get_multiplier_array(param_container))[1]) ==
          Set(["Reserve1", "Reserve11"])

    # Both services resolve to that single row through the name -> uuid map.
    vals1 = jump_value.(IOM.get_parameter_column_refs(param_container, "Reserve1"))
    vals11 = jump_value.(IOM.get_parameter_column_refs(param_container, "Reserve11"))
    @test vals1 == vals11

    # Sharing the profile does not merge the services: each keeps its own requirement scale.
    multipliers = IOM.get_multiplier_array(param_container)
    @test multipliers["Reserve11", 1] == 2 * multipliers["Reserve1", 1]
end

@testset "Service requirement time series must match the model resolution" begin
    # `ReserveFast` carries a 5-minute requirement while the model runs hourly. That series
    # must be rejected rather than silently read at the wrong resolution. The explicit
    # `resolution` kwarg is required: `_reconcile_resolution!` errors first without it.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    fast = OnlineReserve{ReserveUp}("ReserveFast", true, 60.0, 0.05)
    PSY.add_service!(sys, fast, get_components(ThermalStandard, sys))
    initial_time = DateTime("2024-01-01T00:00:00")
    five_min_values = collect(range(0.01, 0.05; length = 288))
    PSY.add_time_series!(
        sys,
        fast,
        PSY.Deterministic(;
            name = "requirement",
            data = Dict(
                initial_time => five_min_values,
                initial_time + Day(1) => five_min_values,
            ),
            resolution = Minute(5),
        ),
    )
    @test length(IOM.get_time_series_resolutions(sys)) == 2

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        resolution = Hour(1),
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    # The build wraps its logging, so assert on the log rather than at the call site.
    # The rejection is POM's add_parameters guard; the key-addressed store no longer errors first.
    log_contents = read(joinpath(output_dir, "operation_problem.log"), String)
    @test occursin("Deterministic:requirement", log_contents)
    @test occursin("does not match interval=", log_contents)
end

@testset "Per-type populate errors when one service of the type has no contributing devices" begin
    # Under the per-type ServiceModel, one model covers every OnlineReserve{ReserveUp}
    # service. A modeled reserve with no available contributing device can never meet its
    # requirement, so `_populate_contributing_devices!` (run in the DecisionModel
    # constructor) must error and name the offending service - not silently drop it.
    # `deepcopy` so the added service does not leak into the PSB-cached system.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    # A second service of the same type, added with no contributing devices.
    empty_reserve = OnlineReserve{ReserveUp}("ReserveNoDevices", true, 5.0, 0.1)
    PSY.add_service!(sys, empty_reserve, PSY.Device[])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    @test_throws "ReserveNoDevices" DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
    )
end

@testset "Per-type populate errors when all contributing devices are unavailable" begin
    # A reserve can have contributing devices assigned in the data yet still have none
    # *available*. `_add_contributing_device_by_type!` records only available devices, so
    # the per-service map ends up empty and the constructor must error - the reserve has no
    # usable provider. `deepcopy` so the availability edits do not leak into the cache.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    reserve = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    n_disabled = 0
    for d in PSY.get_components(PSY.Device, sys)
        PSY.supports_services(d) || continue
        if any(s -> s === reserve, PSY.get_services(d))
            PSY.set_available!(d, false)
            n_disabled += 1
        end
    end
    # Premise check: the reserve really did have contributing devices before we disabled
    # them, so this exercises the all-unavailable path, not the no-devices-assigned path.
    @test n_disabled > 0

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    @test_throws "no available contributing devices" DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
    )
end

@testset "Test use_slacks is per type" begin
    # `use_slacks` is set on the per-type `ServiceModel`, not per-service. Confirm both
    # directions: when true, the dense ReserveRequirementSlack container spans ALL
    # services of the type (Reserve1 and Reserve11), each wired to the penalty cost; when
    # false (or omitted), no ReserveRequirementSlack container exists for the type at all.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(
            OnlineReserve{ReserveUp},
            RangeReserve;
            use_slacks = true,
        ),
    )
    model = DecisionModel(
        template,
        c_sys5_uc;
        store_variable_names = true,
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    slack_var = IOM.get_variable(
        container,
        ReserveRequirementSlack,
        OnlineReserve{ReserveUp},
    )
    time_steps = get_time_steps(container)
    reserve_names = ["Reserve1", "Reserve11"]
    @test Set(axes(slack_var, 1)) == Set(reserve_names)

    obj = JuMP.objective_function(get_jump_model(model))
    for name in reserve_names
        @test all(JuMP.lower_bound(slack_var[name, t]) == 0.0 for t in time_steps)
        @test all(
            JuMP.coefficient(obj, slack_var[name, t]) == POM.SERVICES_SLACK_COST for
            t in time_steps
        )
    end

    c_sys5_uc_noslack = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template_noslack = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template_noslack,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    model_noslack =
        DecisionModel(template_noslack, c_sys5_uc_noslack; optimizer = HiGHS_optimizer)
    @test build!(model_noslack; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container_noslack = get_optimization_container(model_noslack)
    @test !IOM.has_container_key(
        container_noslack,
        ReserveRequirementSlack,
        OnlineReserve{ReserveUp},
    )
end

@testset "Per-type reserve container isolates services with mixed device counts (solve)" begin
    # Extends "Per-type reserve container isolates services of the same type" (build-only,
    # isolation at t=1) to a full solve, and checks isolation at every requirement row, not
    # just Reserve1's. NOTE: in this fixture, Reserve1 and Reserve11 both contribute from
    # all five thermal units (Alta, Brighton, Park City, Solitude, Sundance) - there is no
    # differing-device-count case here - so this also stands as the regression case for
    # same-device-set same-type services solving correctly end-to-end.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        OnlineReserve{ReserveUp},
    )
    reserve_names = ["Reserve1", "Reserve11"]
    @test Set(k[1] for k in keys(rv.data)) >= Set(reserve_names)

    for name in reserve_names
        c = con[name, 1]
        for (key, var) in rv.data
            key[3] == 1 || continue
            expected = key[1] == name ? 1.0 : 0.0
            @test JuMP.normalized_coefficient(c, var) == expected
        end
    end
end

@testset "RequirementConstraint dual is assigned and readable per service" begin
    # The service dual path mirrors the dense RequirementConstraint container: one
    # dual per service type keyed `(service_name, time)`, populated after solve. Uses an LP
    # dispatch template (no binaries) so the solver returns duals.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(
            OnlineReserve{ReserveUp},
            RangeReserve;
            duals = [RequirementConstraint],
        ),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    dual_key = IOM.ConstraintKey(RequirementConstraint, OnlineReserve{ReserveUp})
    # One dual container per service type, dense (mirrors the constraint container).
    @test dual_key in keys(IOM.get_duals(container))
    @test IOM.get_duals(container)[dual_key] isa
          JuMP.Containers.DenseAxisArray{Float64, 2}

    res = OptimizationProblemOutputs(model)
    df = read_dual(res, "RequirementConstraint__OnlineReserve__ReserveUp")
    # LONG format `(DateTime, name, value)`; the name column covers ALL services of the type.
    @test Set(df.name) == Set(["Reserve1", "Reserve11"])
    # Reserve is priced only at DEFAULT_RESERVE_COST and the requirement binds, so the
    # shadow price equals DEFAULT_RESERVE_COST / base_power for every service/time.
    expected_price = POM.DEFAULT_RESERVE_COST / get_model_base_power(container)
    @test all(isapprox(v, expected_price; atol = 1e-6) for v in df.value)
end

@testset "Test ORDC time series (build & solve)" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    static_ordc = first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, c_sys5_uc))
    # Two time-varying ORDCs with different per-timestep tranche counts to exercise the
    # tranche-axis padding and per-service (meta-keyed) parameter containers.
    _add_ts_ordc!(
        c_sys5_uc,
        "ORDC_TS1",
        static_ordc;
        incrs_x = (0.03, 0.13, 0.07),
        incrs_y = (0.03, 0.13, 0.07),
        create_extra_tranches = true,
    )
    _add_ts_ordc!(
        c_sys5_uc,
        "ORDC_TS2",
        static_ordc;
        incrs_x = (0.03, 0.13, 0.07),
        incrs_y = (0.02, 0.14, 0.08),
        create_extra_tranches = true,
    )

    template = PowerOperationsProblemTemplate(
        NetworkModel(CopperPlateNetworkModel; use_slacks = true),
    )
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    # One per-type model covers both time-varying ORDCs (ORDC_TS1 and ORDC_TS2).
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    model = DecisionModel(
        template,
        c_sys5_uc;
        name = "UC",
        store_variable_names = true,
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # C1: the ORDC slope/breakpoint PWL cost params are ONE container per service type
    # (names axis + batch-wide tranche axis). A 3-arg fetch succeeds only for a per-type
    # container; the two ORDCs above have different tranche counts, so the successful build+solve
    # also exercises the batch-wide tranche padding.
    container = get_optimization_container(model)
    dir = POM._reserve_offer_direction(
        first(get_components(PSY.has_demand_curve, PSY.OnlineReserve, c_sys5_uc)),
    )
    for P in (IOM._slope_param(dir), IOM._breakpoint_param(dir))
        @test IOM.get_parameter(container, P, OnlineReserve{ReserveUp}) !==
              nothing
    end
end

# Ported from PSI test_services_constructor.jl. Exact `moi_tests` variable/constraint
# counts are PSI formulation fingerprints that differ in POM, so these ports assert
# build/solve success plus stable structural/behavioral properties instead.

# Count reserve variable containers (by entry type) and assert nonnegativity bounds.
function _count_reserve_var_containers(model)
    found = 0
    for (k, var_array) in IOM.get_optimization_container(model).variables
        if IOM.get_entry_type(k) == ActivePowerReserveVariable
            for var in var_array
                @test JuMP.has_lower_bound(var)
                @test JuMP.lower_bound(var) == 0.0
            end
            found += 1
        end
    end
    return found
end

@testset "Test Reserves from Thermal Dispatch" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    # OnlineReserve{ReserveUp} carries the ORDC, so it uses StepwiseCostReserve; the curve-less
    # requirement reserves of that direction are supply-only under the degenerate-demand skip.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test Ramp Reserves from Thermal Dispatch" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RampReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RampReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test Reserves from Thermal Standard UC" begin
    template = get_thermal_standard_uc_template()
    # OnlineReserve{ReserveUp} carries the ORDC, so it uses StepwiseCostReserve; the curve-less
    # requirement reserves of that direction are supply-only under the degenerate-demand skip.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(
        template,
        c_sys5_uc;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test Reserves from Thermal Standard UC with NonSpinningReserve" begin
    template = get_thermal_standard_uc_template()
    set_device_model!(
        template,
        DeviceModel(ThermalMultiStart, ThermalStandardUnitCommitment),
    )
    set_service_model!(
        template,
        ServiceModel(OfflineReserve, NonSpinningReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc_non_spin"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "Test Upwards Reserves from Renewable Dispatch" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    # OnlineReserve{ReserveUp} carries the ORDC, so it uses StepwiseCostReserve; the curve-less
    # requirement reserves of that direction are supply-only under the degenerate-demand skip.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )

    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re"; add_reserves = true)
    model = DecisionModel(template, c_sys5_re; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 1
end

@testset "Test Reserves with slack variables" begin
    template = get_thermal_dispatch_template_network(
        NetworkModel(CopperPlateNetworkModel; use_slacks = true),
    )
    set_service_model!(
        template,
        ServiceModel(
            OnlineReserve{ReserveUp},
            RangeReserve;
            use_slacks = true,
        ),
    )
    set_service_model!(
        template,
        ServiceModel(
            OnlineReserve{ReserveDown},
            RangeReserve;
            use_slacks = true,
        ),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test OnlineReserve" begin
    template = get_thermal_dispatch_template_network()
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc")
    static_reserve = OnlineReserve{ReserveUp}(;
        name = "Reserve3",
        available = true,
        time_frame = 100.0,
        requirement = 30.0,
    )
    add_service!(c_sys5_uc, static_reserve, get_components(ThermalGen, c_sys5_uc))
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test model isa DecisionModel
end

@testset "Test Reserves with Participation factor limits" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    for service in get_components(Reserve, c_sys5_uc)
        PSY.set_max_participation_factor!(service, 0.8)
    end

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    # OnlineReserve{ReserveUp} carries the ORDC, so it uses StepwiseCostReserve; the curve-less
    # requirement reserves of that direction are supply-only under the degenerate-demand skip.
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, StepwiseCostReserve),
    )

    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2

    found_constraints = 0
    for (k, _) in IOM.get_optimization_container(model).constraints
        if IOM.get_entry_type(k) == POM.ParticipationFractionConstraint
            found_constraints += 1
        end
    end
    @test found_constraints >= 1
end

@testset "2 Areas AreaBalance With Transmission Interface" begin
    c_sys = PSB.build_system(PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(c_sys, Hour(24), Hour(1))
    template = get_thermal_dispatch_template_network(NetworkModel(AreaBalanceNetworkModel))
    set_device_model!(template, AreaInterchange, StaticBranch)
    ps_model =
        DecisionModel(template, c_sys; resolution = Hour(1), optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(ps_model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    opt_container = IOM.get_optimization_container(ps_model)
    copper_plate_constraints =
        IOM.get_constraint(opt_container, CopperPlateBalanceConstraint, PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    results = OptimizationProblemOutputs(ps_model)
    interarea_flow = read_variable(
        results,
        "FlowActivePowerVariable__AreaInterchange";
        table_format = TableFormat.WIDE,
    )
    @test all(interarea_flow[!, "1_2"] .<= 150 + POM.ABSOLUTE_TOLERANCE)
    @test all(interarea_flow[!, "1_2"] .>= -150 - POM.ABSOLUTE_TOLERANCE)
end

# NOTE: `use_slacks = true` on the interface ServiceModel is omitted here — the interface
# slack path is a POM src gap (`add_variable_container!(..., InterfaceFlowSlackUp,
# TransmissionInterface, ::String, ::UnitRange)` has no method), so building a slack-enabled
# interface returns FAILED. The non-slack path exercises the InterfaceFlowLimit construction.
@testset "Test Transmission Interface" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
    )
    interface_lines = [
        get_component(Line, c_sys5_uc, "1"),
        get_component(Line, c_sys5_uc, "2"),
        get_component(Line, c_sys5_uc, "6"),
    ]
    add_service!(c_sys5_uc, interface, interface_lines)

    for net in (DCPNetworkModel, PTDFNetworkModel)
        template = get_thermal_dispatch_template_network(net)
        set_service_model!(
            template,
            ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
        )
        model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        opt_container = IOM.get_optimization_container(model)
        @test size(
            IOM.get_constraint(
                opt_container,
                POM.InterfaceFlowLimit,
                TransmissionInterface,
                "ub",
            ),
        ) == (1, 24)
    end
end

@testset "Test Transmission Interface with TimeSeries" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
    )
    interface_lines = [
        get_component(Line, c_sys5_uc, "1"),
        get_component(Line, c_sys5_uc, "2"),
        get_component(Line, c_sys5_uc, "6"),
    ]
    add_service!(c_sys5_uc, interface, interface_lines)

    data_minflow = Dict(
        DateTime("2024-01-01T00:00:00") => zeros(24),
        DateTime("2024-01-02T00:00:00") => zeros(24),
    )
    forecast_minflow = Deterministic(
        "min_active_power_flow_limit",
        data_minflow,
        Hour(1),
    )
    maxflow_day = [
        0.9, 0.85, 0.95, 0.2, 0.15, 0.2,
        0.9, 0.85, 0.95, 0.2, 0.15, 0.2,
        0.9, 0.85, 0.95, 0.2, 0.5, 0.5,
        0.9, 0.85, 0.95, 0.2, 0.6, 0.6,
    ]
    data_maxflow = Dict(
        DateTime("2024-01-01T00:00:00") => maxflow_day,
        DateTime("2024-01-02T00:00:00") => maxflow_day,
    )
    forecast_maxflow = Deterministic(
        "max_active_power_flow_limit",
        data_maxflow,
        Hour(1),
    )
    add_time_series!(c_sys5_uc, interface, forecast_minflow)
    add_time_series!(c_sys5_uc, interface, forecast_maxflow)

    for net in (DCPNetworkModel, PTDFNetworkModel)
        template = get_thermal_dispatch_template_network(net)
        set_service_model!(
            template,
            ServiceModel(TransmissionInterface, VariableMaxInterfaceFlow),
        )
        model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
    end
end

@testset "Interface slacks are one container per type (use_slacks)" begin
    # `use_slacks = true` on the interface ServiceModel builds InterfaceFlowSlackUp/Down as one
    # dense container per (variable type, TransmissionInterface) keyed by interface name, each
    # wired to the interface's violation penalty. `deepcopy` so the added interface does not leak
    # into the PSB cache.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
        violation_penalty = 1e5,
    )
    add_service!(sys, interface, [get_component(Line, sys, l) for l in ("1", "2", "6")])

    template = get_thermal_dispatch_template_network(DCPNetworkModel)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    time_steps = get_time_steps(container)
    for V in (POM.InterfaceFlowSlackUp, POM.InterfaceFlowSlackDown)
        # 3-arg fetch proves the per-type container.
        slack = IOM.get_variable(container, V, TransmissionInterface)
        @test axes(slack) == (["west_east"], time_steps)
        @test all(JuMP.lower_bound(slack["west_east", t]) == 0.0 for t in time_steps)
    end
    # Slacks are wired into the objective at the interface's violation penalty.
    obj = JuMP.objective_function(get_jump_model(model))
    slack_up = IOM.get_variable(container, POM.InterfaceFlowSlackUp, TransmissionInterface)
    @test all(JuMP.coefficient(obj, slack_up["west_east", t]) == 1e5 for t in time_steps)
end

@testset "Interface flow-limit params are one container per type" begin
    # VariableMaxInterfaceFlow builds Min/MaxInterfaceFlowLimitParameter as one container per type
    # over all interface names; the 3-arg fetch below proves the per-type container.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
    )
    add_service!(sys, interface, [get_component(Line, sys, l) for l in ("1", "2", "6")])
    for ts_name in ("min_active_power_flow_limit", "max_active_power_flow_limit")
        data = Dict(
            DateTime("2024-01-01T00:00:00") => fill(0.5, 24),
            DateTime("2024-01-02T00:00:00") => fill(0.5, 24),
        )
        add_time_series!(
            sys,
            interface,
            Deterministic(ts_name, data, Hour(1)),
        )
    end

    template = get_thermal_dispatch_template_network(DCPNetworkModel)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, VariableMaxInterfaceFlow),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    for P in (POM.MinInterfaceFlowLimitParameter, POM.MaxInterfaceFlowLimitParameter)
        # 3-arg fetch (no meta) succeeds only for a single container per type.
        param = IOM.get_parameter(container, P, TransmissionInterface)
        @test !isnothing(param)
    end
    # The flow-limit constraint (which reads those params) built for the interface.
    @test size(
        IOM.get_constraint(container, POM.InterfaceFlowLimit, TransmissionInterface, "ub"),
    ) == (1, 24)
end

@testset "Interface with no available contributing branches errors" begin
    # A3: an interface whose contributing branches are all unavailable has an empty contributing
    # map, so `_populate_contributing_devices!` (in the DecisionModel constructor) must error and
    # name it rather than silently building a meaningless flow limit.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
    )
    interface_lines = [get_component(Line, sys, l) for l in ("1", "2", "6")]
    add_service!(sys, interface, interface_lines)
    for l in interface_lines
        PSY.set_available!(l, false)
    end

    template = get_thermal_dispatch_template_network(DCPNetworkModel)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    @test_throws "no available contributing devices/branches" DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
    )
end

@testset "Test Interfaces on Interchanges with AreaBalance" begin
    sys_rts_da = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
    transform_single_time_series!(sys_rts_da, Hour(24), Hour(1))
    interchange1 = AreaInterchange(;
        name = "interchange1_2",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "1"),
        to_area = get_component(Area, sys_rts_da, "2"),
    )
    interchange2 = AreaInterchange(;
        name = "interchange1_3",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "1"),
        to_area = get_component(Area, sys_rts_da, "3"),
    )
    interchange3 = AreaInterchange(;
        name = "interchange3_2",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "3"),
        to_area = get_component(Area, sys_rts_da, "2"),
    )
    add_components!(sys_rts_da, [interchange1, interchange2, interchange3])
    interface = TransmissionInterface(;
        name = "interface1_2_3",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 1.0),
        violation_penalty = 1000.0,
        direction_mapping = Dict("interchange1_2" => 1, "interchange1_3" => -1),
    )
    add_service!(sys_rts_da, interface, [interchange1, interchange2])
    template = PowerOperationsProblemTemplate(NetworkModel(AreaBalanceNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableNonDispatch, FixedOutput)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template, AreaInterchange, StaticBranch)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(ps_model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    opt_container = IOM.get_optimization_container(ps_model)
    copper_plate_constraints =
        IOM.get_constraint(opt_container, CopperPlateBalanceConstraint, PSY.Area)
    @test size(copper_plate_constraints) == (3, 24)

    interchange_constraints_ub =
        IOM.get_constraint(
            opt_container,
            POM.InterfaceFlowLimit,
            TransmissionInterface,
            "ub",
        )
    interchange_constraints_lb =
        IOM.get_constraint(
            opt_container,
            POM.InterfaceFlowLimit,
            TransmissionInterface,
            "lb",
        )
    @test size(interchange_constraints_ub) == (1, 24)
    @test size(interchange_constraints_lb) == (1, 24)

    results = OptimizationProblemOutputs(ps_model)
    interface_results = read_expression(
        results,
        "InterfaceTotalFlow__TransmissionInterface";
        table_format = TableFormat.WIDE,
    )
    for i in 1:24
        @test interface_results[!, "interface1_2_3"][i] <= 100.0 + POM.ABSOLUTE_TOLERANCE
    end
end

@testset "Test Interfaces on Interchanges and Double Circuits with AreaPTDFNetworkModel" begin
    sys_rts_da = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
    transform_single_time_series!(sys_rts_da, Hour(24), Hour(1))
    interchange1 = AreaInterchange(;
        name = "interchange1_2",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "1"),
        to_area = get_component(Area, sys_rts_da, "2"),
    )
    interchange2 = AreaInterchange(;
        name = "interchange1_3",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "1"),
        to_area = get_component(Area, sys_rts_da, "3"),
    )
    interchange3 = AreaInterchange(;
        name = "interchange3_2",
        available = true,
        active_power_flow = 100.0,
        flow_limits = (from_to = 1.0, to_from = 1.0),
        from_area = get_component(Area, sys_rts_da, "3"),
        to_area = get_component(Area, sys_rts_da, "2"),
    )
    add_components!(sys_rts_da, [interchange1, interchange2, interchange3])
    interface1 = TransmissionInterface(;
        name = "interface1_2_3",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 1.0),
        violation_penalty = 1000.0,
        direction_mapping = Dict("interchange1_2" => 1, "interchange1_3" => -1),
    )
    add_service!(sys_rts_da, interface1, [interchange1, interchange2])

    double_circuit_1 = get_component(Line, sys_rts_da, "A33-1")
    double_circuit_2 = get_component(Line, sys_rts_da, "A33-2")
    interface2 = TransmissionInterface(;
        name = "interface_double_circuit",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 1.0),
        violation_penalty = 1000.0,
        direction_mapping = Dict("A33-1" => 1, "A33-2" => 1),
    )
    add_service!(sys_rts_da, interface2, [double_circuit_1, double_circuit_2])

    template =
        PowerOperationsProblemTemplate(
            NetworkModel(AreaPTDFNetworkModel; use_slacks = true),
        )
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableNonDispatch, FixedOutput)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template, Line, StaticBranchUnbounded)
    set_device_model!(
        template,
        DeviceModel(AreaInterchange, StaticBranchUnbounded; use_slacks = false),
    )
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(ps_model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    opt_container = IOM.get_optimization_container(ps_model)
    copper_plate_constraints =
        IOM.get_constraint(opt_container, CopperPlateBalanceConstraint, PSY.Area)
    @test size(copper_plate_constraints) == (3, 24)

    interchange_constraints_ub =
        IOM.get_constraint(
            opt_container,
            POM.InterfaceFlowLimit,
            TransmissionInterface,
            "ub",
        )
    interchange_constraints_lb =
        IOM.get_constraint(
            opt_container,
            POM.InterfaceFlowLimit,
            TransmissionInterface,
            "lb",
        )
    @test size(interchange_constraints_ub) == (2, 24)
    @test size(interchange_constraints_lb) == (2, 24)

    results = OptimizationProblemOutputs(ps_model)
    interface_results = read_expression(
        results,
        "InterfaceTotalFlow__TransmissionInterface";
        table_format = TableFormat.WIDE,
    )
    for i in 1:24
        @test interface_results[!, "interface1_2_3"][i] <= 100.0 + POM.ABSOLUTE_TOLERANCE
    end
end

# Which kind of reduction entry a branch resolved to. Dispatched rather than type-checked
# so a new PNM entry kind is a missing method instead of a silently wrong branch.
_reduced_entry_kind(::PSY.ACTransmission) = :single
_reduced_entry_kind(::PNM.BranchesSeries) = :series
_reduced_entry_kind(::PNM.BranchesParallel) = :parallel

@testset "Test bad data for interfaces with reductions" begin
    sys_rts_da = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
    transform_single_time_series!(sys_rts_da, Hour(24), Hour(1))

    double_circuit_1 = get_component(Line, sys_rts_da, "A33-1")
    double_circuit_2 = get_component(Line, sys_rts_da, "A33-2")
    interface_double_circuit = TransmissionInterface(;
        name = "interface_double_circuit",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 1.0),
        violation_penalty = 1000.0,
        direction_mapping = Dict("A33-1" => 1, "A33-2" => 1),
    )
    add_service!(sys_rts_da, interface_double_circuit, [double_circuit_1, double_circuit_2])

    series_chain_1 = get_component(Line, sys_rts_da, "CA-1")
    series_chain_2 = get_component(Line, sys_rts_da, "C35")
    interface_series_chain = TransmissionInterface(;
        name = "interface_series_chain",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 1.0),
        violation_penalty = 1000.0,
        direction_mapping = Dict("CA-1" => -1, "C35" => -1),
    )
    #=
    Built before the series interface exists, so its degree-two reduction merges "CA-1"
    and "C35" into one BranchesSeries entry. That merged-chain-inside-an-interface state
    is what makes conflicting per-segment direction data ambiguous, and it is the ONLY
    state the series-chain direction validations can fire from.

    A build-time reduction can no longer produce it: PNM's DegreeTwoReduction protects the
    arc buses of every TransmissionInterface contributing device, so the bus the chain
    would eliminate is pinned and both lines stay separate direct entries. Two independent
    contributors with opposite signs is valid data, so there is nothing left to reject.
    The state is only reachable from a reduction that predates the interface, which is
    what this matrix is kept for — and that route is rejected by the source's own
    reduction-reproducibility guard. Do not "restore" a `build!`-returns-FAILED assertion
    on the spec source below without first removing that PNM protection.
    =#
    pre_service_ptdf = PNM.VirtualPTDF(
        sys_rts_da;
        tol = POM.PTDF_ZERO_TOL,
        network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
    )
    add_service!(sys_rts_da, interface_series_chain, [series_chain_1, series_chain_2])
    template = PowerOperationsProblemTemplate(
        NetworkModel(
            AreaPTDFNetworkModel;
            network_source = NetworkReductionSpec(PNM.DegreeTwoReduction()),
            use_slacks = true,
        ),
    )
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableNonDispatch, FixedOutput)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template, Line, StaticBranchUnbounded)
    set_device_model!(
        template,
        DeviceModel(AreaInterchange, StaticBranchUnbounded; use_slacks = false),
    )
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    spec_network_model = get_network_model(template)
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    # Bad direction data for interface on series chain: only reachable from a reduction
    # that predates the interface, and that reduction is now rejected outright because it
    # describes a network the system no longer has.
    PSY.set_direction_mapping!(interface_series_chain, Dict("CA-1" => 1, "C35" => -1))
    stale_source = PrebuiltMatrixSource(pre_service_ptdf)
    @test_throws IS.ConflictingInputsError POM._source_ybus(
        stale_source,
        sys_rts_da,
        Int[],
    )
    set_network_model!(
        template,
        NetworkModel(
            AreaPTDFNetworkModel;
            network_source = stale_source,
            use_slacks = true,
        ),
    )
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(
        ps_model;
        console_level = Logging.AboveMaxLevel,
        output_dir = mktempdir(; cleanup = true),
    ) == IOM.ModelBuildStatus.FAILED
    set_network_model!(template, spec_network_model)

    # Bad direction data for interface on double circuit:
    PSY.set_direction_mapping!(interface_series_chain, Dict("CA-1" => 1, "C35" => 1))
    PSY.set_direction_mapping!(interface_double_circuit, Dict("A33-1" => 1, "A33-2" => -1))
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(
        ps_model;
        console_level = Logging.AboveMaxLevel,
        output_dir = mktempdir(; cleanup = true),
    ) == IOM.ModelBuildStatus.FAILED
    PSY.set_direction_mapping!(interface_double_circuit, Dict("A33-1" => 1, "A33-2" => 1))

    # Only including part of a double circuit in an interface:
    pop!(PSY.get_services(double_circuit_1))
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(
        ps_model;
        console_level = Logging.AboveMaxLevel,
        output_dir = mktempdir(; cleanup = true),
    ) == IOM.ModelBuildStatus.FAILED

    # Only including part of a series chain in an interface: there is no merged chain to
    # partially specify, because the remaining contributor's endpoints pin the bus the
    # merge would eliminate. Asserting that structural fact — rather than a rejection that
    # can no longer fire — is what keeps the requirement covered.
    push!(PSY.get_services(double_circuit_1), interface_double_circuit)
    pop!(PSY.get_services(series_chain_1))
    partial_catalog = PNM.get_branch_catalog(
        PNM.Ybus(
            sys_rts_da;
            network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
        ),
    )
    partial_name_to_arc = PNM.get_name_to_arc_maps(partial_catalog)[Line]
    partial_maps = PNM.get_all_branch_maps_by_type(partial_catalog)
    for name in ("CA-1", "C35")
        arc, bucket = partial_name_to_arc[name]
        @test bucket === :direct_branch_map
        @test _reduced_entry_kind(partial_maps[bucket][Line][arc]) == :single
    end
end

@testset "GroupReserve requirement sums only its contributing services" begin
    # A GroupReserve's RequirementConstraint must sum the ActivePowerReserveVariable of
    # every contributing service (and only those) across the (service, device, time)
    # container. Exercises reserve_group.jl `add_constraints!` and `_group_member_variables`.
    # Reachable only because the no-contributing-devices error in
    # `_populate_contributing_devices!` is scoped to `PSY.Reserve`, exempting groups.
    # `deepcopy` so the added group does not leak into the PSB-cached system.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    # Group contains ONLY Reserve1, so the constraint must include Reserve1's device variables and
    # exclude Reserve11's — verifying the barrier's per-service `key[1] == r_name` filtering.
    group = GroupReserve{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r1])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        GroupReserve{ReserveUp},
    )

    # Dense group-indexed requirement container keyed [group_name, time].
    @test "group_up" in axes(con)[1]

    # At t=1 every Reserve1 device variable appears with coefficient 1; every Reserve11 device
    # variable has coefficient 0 (Reserve11 is not in the group). Confirms the group sums exactly
    # its contributing service's slice.
    c1 = con["group_up", 1]
    checked_reserve1 = 0
    for (key, var) in rv.data
        key[3] == 1 || continue
        expected = key[1] == "Reserve1" ? 1.0 : 0.0
        @test JuMP.normalized_coefficient(c1, var) == expected
        key[1] == "Reserve1" && (checked_reserve1 += 1)
    end
    @test checked_reserve1 > 0   # Reserve1 actually contributed variables

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "GroupReserve sums across multiple contributing services" begin
    # A group over two reserves must sum BOTH services' slices of the shared
    # `(service, device, time)` container - the multi-service case the single-service test above
    # does not exercise.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    r11 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve11")
    group = GroupReserve{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r1, r11])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        GroupReserve{ReserveUp},
    )
    c1 = con["group_up", 1]
    # Both members' device variables enter the group sum with coefficient 1 at t=1, and only
    # theirs: the container is shared by every OnlineReserve{ReserveUp}, so the non-member ORDC1
    # is present but must not enter the group's constraint.
    members = Set(["Reserve1", "Reserve11"])
    seen_r1 = 0
    seen_r11 = 0
    for (key, var) in rv.data
        key[3] == 1 || continue
        expected = key[1] in members ? 1.0 : 0.0
        @test JuMP.normalized_coefficient(c1, var) == expected
        key[1] == "Reserve1" && (seen_r1 += 1)
        key[1] == "Reserve11" && (seen_r11 += 1)
    end
    @test seen_r1 > 0 && seen_r11 > 0
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "GroupReserve builds and solves for ReserveDown" begin
    # Direction parity: a GroupReserve{ReserveDown} over a down reserve.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r2 = PSY.get_component(OnlineReserve{ReserveDown}, sys, "Reserve2")
    group = GroupReserve{ReserveDown}(;
        name = "group_dn",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r2])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveDown}, RangeReserve))
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveDown}, GroupRangeReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = get_optimization_container(model)
    @test IOM.has_container_key(
        container, RequirementConstraint, GroupReserve{ReserveDown})
    con = IOM.get_constraint(
        container, RequirementConstraint, GroupReserve{ReserveDown})
    @test "group_dn" in axes(con)[1]
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "GroupReserve requirement is enforced in the solution" begin
    # A positive group requirement is a real lower bound on the summed provision of its
    # contributing services. Solve and confirm the sum meets the requirement at every step.
    req = 0.5
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    group = GroupReserve{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = req,
    )
    add_service!(sys, group, Service[r1])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, OnlineReserve{ReserveUp})
    for t in IOM.get_time_steps(container)
        provided =
            sum(
                JuMP.value(var) for
                (key, var) in rv.data if key[1] == "Reserve1" && key[3] == t
            )
        @test provided >= req - 1e-4
    end
end

@testset "GroupReserve build fails when a contributing service is not modeled" begin
    # `check_activeservice_variables` (ArgumentConstructStage) requires each contributing service
    # to be modeled first. With no ServiceModel for the member reserve, its
    # ActivePowerReserveVariable is never created, so the build fails.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    group = GroupReserve{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r1])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    # Deliberately omit `ServiceModel(OnlineReserve{ReserveUp}, RangeReserve)`.
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "GroupReserve is constructed last regardless of template order" begin
    # The group's ServiceModel is added before its member's; construction still defers the group
    # to last (so the member's ActivePowerReserveVariable exists when the group reads it).
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(OnlineReserve{ReserveUp}, sys, "Reserve1")
    group = GroupReserve{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r1])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve),
    )
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

# NOT PORTED — blocked by POM source gaps (these PSI testsets need src changes, out of
# scope for a test-only port):
#  - "Test Reserves with Feedforwards": the concrete feedforward types
#    (`LowerBoundFeedforward`, `FixValueFeedforward`, …) are not defined in POM or IOM —
#    only the feedforward constraint types and the abstract construct hooks exist.
# Also not ported (feature/framework not in POM): AGC (no `template_agc_reserve_deployment`),
# Hydro reserves (`HydroTurbineEnergyDispatch` absent), the bare-`TimeSeriesKey` ORDC tests
# (superseded by the two ORDC testsets above), and all Simulation-orchestration testsets
# (Simulation framework absent in the IOM/POM split).

# Time-varying ORDC support when the curve is attached as a `SingleTimeSeries` and materialized by
# `transform_single_time_series!` (the ORDC testsets above attach a direct `Deterministic` with
# thermal contributors, so neither path below is otherwise covered):
#   (a) `StorageDispatchWithReserves` reserve bounds must accept a time-series ORDC and give it
#       the full-range bound.
#   (b) `get_max_tranches` must read the transform product (the store materializes it as a
#       full `Deterministic` on read; the `get_data`-less wrapper no longer surfaces).

@testset "StorageDispatchWithReserves reserve bound accepts a time-series ORDC" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat")
    storage = first(get_components(PSY.EnergyReservoirStorage, sys))
    ordc_ts = OnlineReserve{ReserveUp}(;
        name = "ORDC_TS", available = true, time_frame = 1.0,
        variable = stub_ts_offer_curve(; power_units = PSY.SU))
    # Full input/output range, exactly as for a static ORDC (demand curves have no
    # `get_max_output_fraction`).
    @test POM.get_variable_upper_bound(
        POM.AncillaryServiceVariableDischarge, ordc_ts, storage,
        POM.StorageDispatchWithReserves) ==
          PSY.get_output_active_power_limits(storage, PSY.SU).max
    @test POM.get_variable_upper_bound(
        POM.AncillaryServiceVariableCharge, ordc_ts, storage,
        POM.StorageDispatchWithReserves) ==
          PSY.get_input_active_power_limits(storage, PSY.SU).max
end

@testset "get_max_tranches handles the transform product (DeterministicSingleTimeSeries)" begin
    # Uniform-STS paradigm (users do not mix time-series types): one STS grid, one
    # transform, and the post-transform forecast params describe the ORDC's own product.
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat";
        add_forecasts = false, add_single_time_series = true, add_reserves = true)
    res = first(PSY.get_time_series_resolutions(sys))
    grid = first(
        md for
        md in IS.list_time_series_metadata(first(get_components(PowerLoad, sys)))
        if IS.get_time_series_type(md) <: IS.SingleTimeSeries
    )
    n = IS.get_length(grid)
    times = collect(range(IS.get_initial_timestamp(grid); step = res, length = n))

    # Per-hour demand curves with alternating tranche counts (2 and 3); max tranches = 3.
    two = IS.PiecewiseStepData([0.0, 100.0, 200.0], [50.0, 30.0])
    three = IS.PiecewiseStepData([0.0, 100.0, 200.0, 300.0], [50.0, 30.0, 10.0])
    curves = [isodd(k) ? three : two for k in 1:n]

    ordc_ts = OnlineReserve{ReserveUp}(;
        name = "ORDC_TS", available = true, time_frame = 1.0,
        variable = stub_ts_offer_curve(; power_units = IS.NaturalUnit()))
    add_service!(sys, ordc_ts, get_components(PSY.EnergyReservoirStorage, sys))
    add_time_series!(sys, ordc_ts,
        IS.SingleTimeSeries(;
            name = "variable_cost",
            data = IS.TimeSeries.TimeArray(times, curves),
        ))
    # STS-only systems have no forecast params until the transform defines them, so
    # transform first and take the key of the forecast row the transform minted.
    transform_single_time_series!(sys, Hour(24), Hour(24); delete_existing = false)
    key = IS.get_time_series_key(
        first(
            md for md in IS.list_time_series_metadata(ordc_ts)
            if IS.get_time_series_type(md) <: IS.Forecast
        ),
    )
    PSY.set_variable!(ordc_ts,
        PSY.make_market_bid_ts_curve(key, nothing, IS.NaturalUnit()))

    resolved =
        PSY.get_time_series(ordc_ts, IS.get_time_series_key(PSY.get_variable(ordc_ts)))
    # The store MATERIALIZES the transform product on read: a full Deterministic comes
    # back, never the get_data-less DeterministicSingleTimeSeries wrapper.
    @test resolved isa IS.Deterministic
    @test POM.get_max_tranches(
        ordc_ts,
        IS.get_time_series_key(PSY.get_variable(ordc_ts)),
    ) == 3
end

@testset "GroupReserve guards: formulation pairing and offer costs" begin
    # Mis-pairs fail at ServiceModel declaration with an actionable error.
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveUp}, RangeReserve)
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveDown}, StepwiseCostReserve)
    @test_throws ArgumentError ServiceModel(OnlineReserve{ReserveUp}, GroupRangeReserve)
    @test_throws ArgumentError ServiceModel(OfflineReserve, GroupRangeReserve)
    # Bare group type: the direction must be applied.
    @test_throws ArgumentError ServiceModel(GroupReserve, GroupRangeReserve)
    # The valid pair still constructs.
    @test ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve) isa ServiceModel

    # A group carries no per-device offers; the guard keeps the structural guarantee the
    # `GroupReserve <: AbstractReserve` move would otherwise relax.
    sys = System(100.0)
    container = build_test_container(sys, 1:2)
    group = GroupReserve{ReserveUp}(nothing)
    model = ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve)
    @test_throws IS.ConflictingInputsError POM.add_reserve_offer_costs!(
        container, group, model,
    )
end

# Elastic group ORDC (`GroupStepwiseCostReserve`): one demand curve on a `PSY.GroupReserve`
# is cleared by the summed awards of its contributing services. Members are supply-only
# `OnlineReserve`s (zero requirement, no curve); offers and caps live on the members.

# Per-thermal MarketBidCost keeping the unit's own marginal energy cost, plus flat AS offers
# into `sub_a` and `sub_b` (cheap A, prohibitively priced B by default).
function _setup_group_reserve_offers!(
    sys,
    sub_a,
    sub_b;
    sub_a_price = 5.0,
    sub_b_price = 9.0e5,
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")],
    horizon = 24,
    resolution = Hour(1),
)
    offer_curve(price) = IS.PiecewiseStepData([0.0, 100.0], [price])
    for g in get_components(ThermalStandard, sys)
        pmax = PSY.get_max_active_power(g, PSY.NU)
        energy_slope = PSY.get_proportional_term(
            PSY.get_value_curve(PSY.get_variable_operation_cost(get_operation_cost(g))),
        )
        set_operation_cost!(
            g,
            MarketBidCost(;
                minimum_energy_offer = LinearCurve(0.0),
                start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                shut_down = LinearCurve(0.0),
                incremental_offer_curves = make_market_bid_curve(
                    [0.0, pmax], [energy_slope], 0.0; power_units = IS.NaturalUnit(),
                ),
            ),
        )
        for (svc, price) in ((sub_a, sub_a_price), (sub_b, sub_b_price))
            data = Dict(it => [offer_curve(price) for _ in 1:horizon] for it in init_times)
            ts = Deterministic(PSY.get_name(svc), data, resolution)
            PSY.set_service_bid!(sys, g, svc, ts, IS.NaturalUnit())
        end
    end
    return
end

function build_group_reserve_system(;
    sub_a_price = 5.0,
    sub_b_price = 9.0e5,
    group_curve = true,
)
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    thermals = collect(get_components(ThermalStandard, sys))
    sub_a = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_A", available = true, time_frame = 3600.0, requirement = 0.0)
    sub_b = OnlineReserve{ReserveUp}(;
        name = "GROUP_SUB_B", available = true, time_frame = 3600.0, requirement = 0.0)
    add_service!(sys, sub_a, thermals)
    add_service!(sys, sub_b, thermals)
    group = if group_curve
        GroupReserve{ReserveUp}(;
            name = "UP_GROUP",
            available = true,
            requirement = 0.0,
            variable = make_market_bid_curve(
                [0.0, 40.0, 80.0], [80.0, 10.0], 0.0; power_units = IS.NaturalUnit(),
            ),
            contributing_services = Service[sub_a, sub_b],
        )
    else
        # `variable` defaults to the zero-offer sentinel: no demand curve.
        GroupReserve{ReserveUp}(;
            name = "UP_GROUP",
            available = true,
            requirement = 0.0,
            contributing_services = Service[sub_a, sub_b],
        )
    end
    add_service!(sys, group)
    _setup_group_reserve_offers!(
        sys,
        sub_a,
        sub_b;
        sub_a_price = sub_a_price,
        sub_b_price = sub_b_price,
    )
    return sys, group
end

function _group_reserve_template(; include_group = true)
    template = get_thermal_standard_uc_template()
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    include_group && set_service_model!(
        template,
        ServiceModel(GroupReserve{ReserveUp}, GroupStepwiseCostReserve),
    )
    return template
end

_sub_cols(df, prefix) = [c for c in names(df) if startswith(c, prefix)]

function _solve_group_model(sys; include_group = true)
    model = DecisionModel(
        _group_reserve_template(; include_group = include_group),
        sys;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    return model
end

@testset "GroupStepwiseCostReserve: builds, solves, single group clearing constraint" begin
    sys, group = build_group_reserve_system()
    model = _solve_group_model(sys)
    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(container, ServiceRequirementVariable, typeof(group))
    @test IOM.has_container_key(container, POM.RequirementConstraint, typeof(group))
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    @test setdiff(names(demand), ["DateTime"]) == ["UP_GROUP"]
end

@testset "GroupStepwiseCostReserve: aggregation binds member awards to group demand" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_cols = _sub_cols(awards, "GROUP_SUB_")
    @test !isempty(sub_cols)
    for t in 1:24
        @test sum(awards[t, c] for c in sub_cols) ≈ demand[t, "UP_GROUP"] atol = 1e-3
    end
end

@testset "GroupStepwiseCostReserve: sub-service merit order" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_a_total = sum(awards[1, c] for c in _sub_cols(awards, "GROUP_SUB_A"))
    sub_b_total = sum(awards[1, c] for c in _sub_cols(awards, "GROUP_SUB_B"))
    @test sub_a_total > 1.0
    @test sub_b_total <= 1e-2
    @test sub_a_total > sub_b_total
end

@testset "GroupStepwiseCostReserve: time-series group demand curve clears per hour" begin
    # The group ORDC can be time-series-backed (`CostCurve{TimeSeriesPiecewiseIncrementalCurve}`,
    # same Union as the single reserves); the parameter machinery
    # (`process_stepwise_cost_reserve_parameters!`) must feed hour-varying blocks into the
    # clearing. Demand cap alternates 40/80 MW by hour at a price far above both the member
    # offer and any commitment cost, so the cleared group demand must track the alternation
    # exactly - a static curve cannot. (A moderate price lets commitment economics under-buy;
    # the point here is the hourly caps, so make the value decisive.)
    sys, group = build_group_reserve_system(; group_curve = false)
    init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]
    horizon = 24
    curves =
        [IS.PiecewiseStepData([0.0, isodd(h) ? 40.0 : 80.0], [9.0e4]) for h in 1:horizon]
    data = Dict(it => copy(curves) for it in init_times)
    key = PSY.add_time_series!(
        sys,
        group,
        Deterministic("variable_cost", data, Hour(1)),
    )
    PSY.set_variable!(group, PSY.make_market_bid_ts_curve(key, nothing, IS.NaturalUnit()))
    @test PSY.has_demand_curve(group)

    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE)
    for t in 1:horizon
        @test demand[t, "UP_GROUP"] ≈ (isodd(t) ? 40.0 : 80.0) atol = 1e-4
    end
end

@testset "GroupStepwiseCostReserve: no group model -> no procurement" begin
    sys, _ = build_group_reserve_system()
    model = _solve_group_model(sys; include_group = false)
    res = IOM.OptimizationProblemOutputs(model)
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    for t in 1:24, c in _sub_cols(awards, "GROUP_SUB_")
        @test awards[t, c] <= 1e-2
    end
end

@testset "Group formulation pairing fails at ServiceModel declaration" begin
    # A GroupReserve accepts only group formulations, and group formulations accept only
    # GroupReserve; mis-pairs must fail at declaration, not at build.
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveUp}, RangeReserve)
    @test_throws ArgumentError ServiceModel(GroupReserve{ReserveDown}, StepwiseCostReserve)
    @test_throws ArgumentError ServiceModel(OnlineReserve{ReserveUp}, GroupRangeReserve)
    @test_throws ArgumentError ServiceModel(
        OnlineReserve{ReserveUp},
        GroupStepwiseCostReserve,
    )
    @test_throws ArgumentError ServiceModel(OfflineReserve, GroupStepwiseCostReserve)
    # The valid pairs still construct.
    @test ServiceModel(GroupReserve{ReserveUp}, GroupRangeReserve) isa ServiceModel
    @test ServiceModel(GroupReserve{ReserveUp}, GroupStepwiseCostReserve) isa ServiceModel
end

@testset "GroupStepwiseCostReserve: curve-less group is skipped as degenerate demand" begin
    sys, group = build_group_reserve_system(; group_curve = false)
    model = _solve_group_model(sys)
    container = IOM.get_optimization_container(model)
    @test !IOM.has_container_key(container, ServiceRequirementVariable, typeof(group))
    @test !IOM.has_container_key(container, POM.RequirementConstraint, typeof(group))
end

@testset "GroupStepwiseCostReserve: time-series group curve builds, solves and clears" begin
    sys, group = build_group_reserve_system()
    baseline_curve = PSY.get_variable(group)
    power_units = PSY.get_power_units(baseline_curve)
    fd = PSY.get_function_data(PSY.get_value_curve(baseline_curve))
    pwl_ts = make_deterministic_ts(
        sys,
        "variable_cost",
        fd,
        (0.0, 0.0, 0.0),
        (0.0, 0.0, 0.0);
        override_min_x = 0.0,
        override_max_x = last(get_x_coords(fd)),
    )
    pwl_key = add_time_series!(sys, group, pwl_ts)
    PSY.set_variable!(group, PSY.make_market_bid_ts_curve(pwl_key, nothing, power_units))

    model = _solve_group_model(sys)
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__GroupReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    awards = read_variable(
        res, "ActivePowerReserveVariable__OnlineReserve__ReserveUp";
        table_format = TableFormat.WIDE,
    )
    sub_cols = _sub_cols(awards, "GROUP_SUB_")
    for t in 1:24
        @test demand[t, "UP_GROUP"] > 1.0
        @test sum(awards[t, c] for c in sub_cols) ≈ demand[t, "UP_GROUP"] atol = 1e-3
    end
end

# The interface spans lines "1", "2" and "6", but the branch filter admits only line "1".
# Every branch in a modeled service must be modeled regardless of the filter, so that the
# interface flow is the sum over all three lines rather than over the one that passed.
@testset "Interface branches survive a branch filter" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc")
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = 0.0, max = 400.0),
    )
    interface_line_names = ["1", "2", "6"]
    interface_lines =
        [get_component(Line, c_sys5_uc, n) for n in interface_line_names]
    add_service!(c_sys5_uc, interface, interface_lines)

    raw_filter = x -> PSY.get_name(x) == "1"
    template = get_thermal_dispatch_template_network(PTDFNetworkModel)
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            attributes = Dict("filter_function" => raw_filter),
        ),
    )
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )

    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    branch_flow = IOM.get_expression(container, POM.PTDFBranchFlow, Line)
    # The filter admits only line "1"; the interface must pull "2" and "6" back in.
    for name in interface_line_names
        @test name in axes(branch_flow)[1]
    end

    # The device cache and the network catalog read the same widened filter, so a forced
    # branch must appear in the rate constraints too, not only in the flow expression.
    rate_constraint = IOM.get_constraint(container, FlowRateConstraint, Line, "ub")
    for name in interface_line_names
        @test name in axes(rate_constraint)[1]
    end

    interface_flow =
        IOM.get_expression(container, POM.InterfaceTotalFlow, TransmissionInterface)
    for t in axes(interface_flow)[2]
        expected = sum(
            JuMP.value(branch_flow[name, t]) for name in interface_line_names
        )
        @test isapprox(
            JuMP.value(interface_flow["west_east", t]),
            expected;
            atol = POM.ABSOLUTE_TOLERANCE,
        )
    end

    # Rebuilding the same model (build! -> reset! -> build!, as production code does) must
    # not nest the widened filter one layer deeper on every pass: re-validating an
    # already-widened template has to unwrap the previous widening before rewrapping it.
    POM.reset!(model)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    rebuilt_container = IOM.get_optimization_container(model)
    rebuilt_branch_flow = IOM.get_expression(rebuilt_container, POM.PTDFBranchFlow, Line)
    rebuilt_interface_flow = IOM.get_expression(
        rebuilt_container,
        POM.InterfaceTotalFlow,
        TransmissionInterface,
    )
    for t in axes(rebuilt_interface_flow)[2]
        expected = sum(
            JuMP.value(rebuilt_branch_flow[name, t]) for name in interface_line_names
        )
        @test isapprox(
            JuMP.value(rebuilt_interface_flow["west_east", t]),
            expected;
            atol = POM.ABSOLUTE_TOLERANCE,
        )
    end

    # The rebuild must widen the user's own filter afresh rather than widening the
    # already-widened one from the first build, so the stored filter's `.original` has to
    # still be the exact raw predicate the template was built with, not another wrapper.
    rebuilt_line_model = IOM.get_model(IOM.get_template(model), Line)
    rebuilt_stored_filter = POM.get_attribute(rebuilt_line_model, "filter_function")
    @test POM._unwiden_branch_filter(rebuilt_stored_filter) === raw_filter
end

@testset "Collect branch names required by service models" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc")
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = -400.0, max = 400.0),
    )
    add_service!(
        c_sys5_uc,
        interface,
        [get_component(Line, c_sys5_uc, n) for n in ("1", "2", "6")],
    )

    template = get_thermal_dispatch_template_network(PTDFNetworkModel)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    IOM.finalize_template!(template, c_sys5_uc)

    forced = POM._collect_service_branch_names(template, c_sys5_uc)
    @test haskey(forced, Line)
    @test forced[Line].branch_names == Set(["1", "2", "6"])
    @test forced[Line].service_names == Set(["west_east"])

    # A network model that does not model branch flows has nothing to force in.
    copper_template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        copper_template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    IOM.finalize_template!(copper_template, c_sys5_uc)
    @test isempty(POM._collect_service_branch_names(copper_template, c_sys5_uc))
end

# A transformer in the interface with no TwoWindingTransformer branch model cannot be forced
# in: there is no formulation to build its flow. The interface would silently omit it, so the
# template is rejected instead.
@testset "Interface branch with no branch model is rejected" begin
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    line = get_component(Line, c_sys14, "Line1")
    transformer = first(PSY.get_components(TwoWindingTransformer, c_sys14))
    interface = TransmissionInterface(;
        name = "mixed_types",
        available = true,
        active_power_flow_limits = (min = -400.0, max = 400.0),
    )
    add_service!(c_sys14, interface, [line, transformer])

    template = PowerOperationsProblemTemplate(PTDFNetworkModel)
    set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, Line, StaticBranch)
    set_service_model!(
        template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )

    model = DecisionModel(template, c_sys14; optimizer = HiGHS_optimizer)
    # Assert on `validate_template` directly: `build!` may catch and return FAILED rather than
    # propagating, which would make the assertion depend on build's error handling.
    # This is the pattern used at test/test_ac_transmission_security_constrained_models.jl:840.
    # Pin the message to the offending branch type, branch name and service name so this test
    # can only pass if the new service-branch-model check is what threw, not
    # `_check_branch_network_compatibility` or `_formulation_supports_network`.
    err = try
        POM.validate_template(model)
        nothing
    catch e
        e
    end
    @test !isnothing(err)
    @test typeof(err) == IS.ConflictingInputsError
    message = sprint(showerror, err)
    @test occursin("TwoWindingTransformer", message)
    @test occursin(PSY.get_name(transformer), message)
    @test occursin("mixed_types", message)

    # Adding the missing branch model resolves it.
    set_device_model!(template, TwoWindingTransformer, StaticBranch)
    ok_model = DecisionModel(template, c_sys14; optimizer = HiGHS_optimizer)
    @test build!(ok_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "Service branch forcing is skipped where branch flows are not modeled" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc")
    interface = TransmissionInterface(;
        name = "west_east",
        available = true,
        active_power_flow_limits = (min = -400.0, max = 400.0),
    )
    add_service!(
        c_sys5_uc,
        interface,
        [get_component(Line, c_sys5_uc, n) for n in ("1", "2", "6")],
    )

    # AreaPTDF resolves interfaces over AreaInterchange components and ignores the lines that
    # cross them, so it must not pull filtered lines back into the model.
    area_template = get_thermal_dispatch_template_network(AreaPTDFNetworkModel)
    set_service_model!(
        area_template,
        ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow),
    )
    IOM.finalize_template!(area_template, c_sys5_uc)
    @test isempty(POM._collect_service_branch_names(area_template, c_sys5_uc))
end
