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

    # Construct with a stub TS curve so the component can be added; the real forecast is
    # attached and set below.
    stub = stub_ts_offer_curve(; power_units = power_units)
    # Keyword form: `variable` sits fifth positionally on `OnlineReserve`, so name the fields.
    ordc_ts = OnlineReserve{ReserveUp}(;
        name = name,
        available = true,
        time_frame = PSY.get_time_frame(static_ordc),
        variable = stub,
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
    @test IS.get_time_series_uuid(PSY.Deterministic, r1, "requirement") ==
          IS.get_time_series_uuid(PSY.Deterministic, r11, "requirement")

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
    log_contents = read(joinpath(output_dir, "operation_problem.log"), String)
    @test occursin("No matching metadata", log_contents)
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
        Hour(1);
        scaling_factor_multiplier = PSY.get_min_active_power_flow_limit,
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
        Hour(1);
        scaling_factor_multiplier = PSY.get_max_active_power_flow_limit,
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
    for (ts_name, sfm) in (
        ("min_active_power_flow_limit", PSY.get_min_active_power_flow_limit),
        ("max_active_power_flow_limit", PSY.get_max_active_power_flow_limit),
    )
        data = Dict(
            DateTime("2024-01-01T00:00:00") => fill(0.5, 24),
            DateTime("2024-01-02T00:00:00") => fill(0.5, 24),
        )
        add_time_series!(
            sys,
            interface,
            Deterministic(ts_name, data, Hour(1); scaling_factor_multiplier = sfm),
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
        @test param !== nothing
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
    # Order matters: compute the ptdf before adding the service so the interface lines
    # are reduced (to test the bad-data checking).
    ptdf = PTDF(sys_rts_da; network_reductions = NetworkReduction[DegreeTwoReduction()])
    add_service!(sys_rts_da, interface_series_chain, [series_chain_1, series_chain_2])
    template = PowerOperationsProblemTemplate(
        NetworkModel(
            AreaPTDFNetworkModel;
            network_matrix = ptdf,
            reduce_degree_two_branches = true,
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
    ps_model = DecisionModel(
        template,
        sys_rts_da;
        resolution = Hour(1),
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    # Bad direction data for interface on series chain:
    PSY.set_direction_mapping!(interface_series_chain, Dict("CA-1" => 1, "C35" => -1))
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

    # Only including part of a series chain in an interface:
    push!(PSY.get_services(double_circuit_1), interface_double_circuit)
    pop!(PSY.get_services(series_chain_1))
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
#   (b) `get_max_tranches` must handle the `DeterministicSingleTimeSeries` produced by transform
#       (which has no `get_data`).

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
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    it = first(PSY.get_forecast_initial_times(sys))
    res = first(PSY.get_time_series_resolutions(sys))
    n = IS.get_horizon_count(PSY.get_forecast_horizon(sys), res)
    times = collect(range(it; step = res, length = n))

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
    key = IS.ForecastKey(; time_series_type = IS.Deterministic, name = "variable_cost",
        initial_timestamp = it, resolution = res,
        horizon = PSY.get_forecast_horizon(sys),
        interval = PSY.get_forecast_interval(sys),
        count = PSY.get_forecast_window_count(sys),
        features = Dict{String, Any}())
    PSY.set_variable!(ordc_ts,
        PSY.make_market_bid_ts_curve(key, nothing, IS.NaturalUnit()))

    transform_single_time_series!(sys, PSY.get_forecast_horizon(sys),
        PSY.get_forecast_interval(sys); delete_existing = false)

    resolved =
        PSY.get_time_series(ordc_ts, IS.get_time_series_key(PSY.get_variable(ordc_ts)))
    @test resolved isa IS.DeterministicSingleTimeSeries      # the case that broke get_data
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
