# Time-varying ORDC. Adapted from PowerSimulations.jl PR #1629 to the psy6 data model,
# where a time-varying ORDC is a `ReserveDemandTimeSeriesCurve` whose `variable` is a
# `CostCurve{TimeSeriesPiecewiseIncrementalCurve}` (rather than a `ReserveDemandCurve`
# carrying a bare `TimeSeriesKey`). The multi-step Simulation scenario from that PR is
# omitted: the Simulation framework is not yet available in the IOM/POM split.

# Build a time-varying ORDC (`ReserveDemandTimeSeriesCurve`) from the system's existing
# static ORDC baseline curve, backing it with a deterministic cost-curve forecast.
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
    ordc_ts = ReserveDemandTimeSeriesCurve{ReserveUp}(
        stub,
        name,
        true,
        PSY.get_time_frame(static_ordc),
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
    static_ordc = first(get_components(PSY.ReserveDemandCurve, c_sys5_uc))
    _add_ts_ordc!(c_sys5_uc, "ORDC_TS", static_ordc)

    template = get_thermal_standard_uc_template()
    # One per-type model now covers both VariableReserve{ReserveUp} services
    # (Reserve1 and Reserve11).
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandTimeSeriesCurve{ReserveUp}, StepwiseCostReserve),
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
    # 2D container over the type's service-name axis and the time-step axis. This path
    # previously had zero test coverage in the whole suite. See POM issue #178 /
    # developer guidelines.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_standard_uc_template()
    set_service_model!(
        template,
        ServiceModel(
            VariableReserve{ReserveUp},
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
    # DELETE-AFTER-REVIEW: reviewer context on the container change; remove once the PR is approved.
    # ReserveRequirementSlack is now one dense container per service type keyed
    # `[service_name, time]` (empty meta), built once over all the type's services.
    slack_var = IOM.get_variable(
        container,
        ReserveRequirementSlack,
        VariableReserve{ReserveUp},
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

@testset "Merged reserve container isolates services of the same type" begin
    # Two VariableReserve{ReserveUp} services share one merged
    # `(service, device, time)` ActivePowerReserveVariable container. Verify (a) each
    # service's requirement constraint sums only its own device variables (no
    # cross-service leakage) and (b) the proportional reserve cost prices each variable
    # exactly once (no double counting across the per-type objective pass).
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    # One per-type model covers both VariableReserve{ReserveUp} services.
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, VariableReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        VariableReserve{ReserveUp},
    )
    # Exactly one merged container spans both services.
    @test Set(k[1] for k in keys(rv.data)) == Set(["Reserve1", "Reserve11"])

    # (a) Reserve1's requirement constraint at t=1 has coefficient 1 for Reserve1's
    # variables and 0 for Reserve11's.
    c1 = con["Reserve1", 1]
    for (key, var) in rv.data
        key[3] == 1 || continue
        expected = key[1] == "Reserve1" ? 1.0 : 0.0
        @test JuMP.normalized_coefficient(c1, var) == expected
    end

    # (b) Each reserve variable is priced exactly once at DEFAULT_RESERVE_COST / base.
    obj = JuMP.objective_function(get_jump_model(model))
    base_p = get_model_base_power(container)
    expected_cost = POM.DEFAULT_RESERVE_COST / base_p
    for (_, var) in rv.data
        @test JuMP.coefficient(obj, var) == expected_cost
    end
end

@testset "Per-type populate errors when one service of the type has no contributing devices" begin
    # Under the per-type ServiceModel, one model covers every VariableReserve{ReserveUp}
    # service. A modeled reserve with no available contributing device can never meet its
    # requirement, so `_populate_contributing_devices!` (run in the DecisionModel
    # constructor) must error and name the offending service - not silently drop it.
    # `deepcopy` so the added service does not leak into the PSB-cached system.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    # A second service of the same type, added with no contributing devices.
    empty_reserve = VariableReserve{ReserveUp}("ReserveNoDevices", true, 5.0, 0.1)
    PSY.add_service!(sys, empty_reserve, PSY.Device[])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))
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
    reserve = PSY.get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
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
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))
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
            VariableReserve{ReserveUp},
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
        VariableReserve{ReserveUp},
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
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    model_noslack =
        DecisionModel(template_noslack, c_sys5_uc_noslack; optimizer = HiGHS_optimizer)
    @test build!(model_noslack; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container_noslack = get_optimization_container(model_noslack)
    @test !IOM.has_container_key(
        container_noslack,
        ReserveRequirementSlack,
        VariableReserve{ReserveUp},
    )
end

@testset "Merged reserve container isolates services with mixed device counts (solve)" begin
    # Extends "Merged reserve container isolates services of the same type" (build-only,
    # isolation at t=1) to a full solve, and checks isolation at every requirement row, not
    # just Reserve1's. NOTE: in this fixture, Reserve1 and Reserve11 both contribute from
    # all five thermal units (Alta, Brighton, Park City, Solitude, Sundance) - there is no
    # differing-device-count case here - so this also stands as the regression case for
    # same-device-set same-type services solving correctly end-to-end.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, VariableReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        VariableReserve{ReserveUp},
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
    # The service dual path mirrors the merged (dense) RequirementConstraint container: one
    # dual per service type keyed `(service_name, time)`, populated after solve. Uses an LP
    # dispatch template (no binaries) so the solver returns duals.
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(
            VariableReserve{ReserveUp},
            RangeReserve;
            duals = [RequirementConstraint],
        ),
    )
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(model)
    dual_key = IOM.ConstraintKey(RequirementConstraint, VariableReserve{ReserveUp})
    # One merged dual container per service type, dense (mirrors the merged constraint).
    @test dual_key in keys(IOM.get_duals(container))
    @test IOM.get_duals(container)[dual_key] isa
          JuMP.Containers.DenseAxisArray{Float64, 2}

    res = OptimizationProblemOutputs(model)
    df = read_dual(res, "RequirementConstraint__VariableReserve__ReserveUp")
    # LONG format `(DateTime, name, value)`; the name column covers ALL services of the type.
    @test Set(df.name) == Set(["Reserve1", "Reserve11"])
    # Reserve is priced only at DEFAULT_RESERVE_COST and the requirement binds, so the
    # shadow price equals DEFAULT_RESERVE_COST / base_power for every service/time.
    expected_price = POM.DEFAULT_RESERVE_COST / get_model_base_power(container)
    @test all(isapprox(v, expected_price; atol = 1e-6) for v in df.value)
end

@testset "Test ORDC time series (build & solve)" begin
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    static_ordc = first(get_components(PSY.ReserveDemandCurve, c_sys5_uc))
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
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    # One per-type model covers both time-varying ORDCs (ORDC_TS1 and ORDC_TS2).
    set_service_model!(
        template,
        ServiceModel(ReserveDemandTimeSeriesCurve{ReserveUp}, StepwiseCostReserve),
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
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 3
end

@testset "Test Ramp Reserves from Thermal Dispatch" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RampReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RampReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test Reserves from Thermal Standard UC" begin
    template = get_thermal_standard_uc_template()
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
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
    @test _count_reserve_var_containers(model) == 3
end

@testset "Test Reserves from Thermal Standard UC with NonSpinningReserve" begin
    template = get_thermal_standard_uc_template()
    set_device_model!(
        template,
        DeviceModel(ThermalMultiStart, ThermalStandardUnitCommitment),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserveNonSpinning, NonSpinningReserve),
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
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
    )

    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re"; add_reserves = true)
    model = DecisionModel(template, c_sys5_re; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 2
end

@testset "Test Reserves with slack variables" begin
    template = get_thermal_dispatch_template_network(
        NetworkModel(CopperPlateNetworkModel; use_slacks = true),
    )
    set_service_model!(
        template,
        ServiceModel(
            VariableReserve{ReserveUp},
            RangeReserve;
            use_slacks = true,
        ),
    )
    set_service_model!(
        template,
        ServiceModel(
            VariableReserve{ReserveDown},
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

@testset "Test ConstantReserve" begin
    template = get_thermal_dispatch_template_network()
    set_service_model!(
        template,
        ServiceModel(ConstantReserve{ReserveUp}, RangeReserve),
    )

    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_uc")
    static_reserve = ConstantReserve{ReserveUp}(;
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
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
    )

    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test _count_reserve_var_containers(model) == 3

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

@testset "Interface slacks are one merged container per type (use_slacks)" begin
    # `use_slacks = true` on the interface ServiceModel builds InterfaceFlowSlackUp/Down as one
    # dense container per (variable type, TransmissionInterface) keyed by interface name (empty
    # meta), each wired to the interface's violation penalty. `deepcopy` so the added interface
    # does not leak into the PSB cache.
    # DELETE-AFTER-REVIEW: reviewer context on the container change; remove once the PR is approved.
    # Ports the previously-blocked ServiceModel use_slacks case (the old per-name + meta build had
    # no working container-builder method).
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
        # 3-arg fetch (no meta) proves the merged, empty-meta container.
        slack = IOM.get_variable(container, V, TransmissionInterface)
        @test axes(slack) == (["west_east"], time_steps)
        @test all(JuMP.lower_bound(slack["west_east", t]) == 0.0 for t in time_steps)
    end
    # Slacks are wired into the objective at the interface's violation penalty.
    obj = JuMP.objective_function(get_jump_model(model))
    slack_up = IOM.get_variable(container, POM.InterfaceFlowSlackUp, TransmissionInterface)
    @test all(JuMP.coefficient(obj, slack_up["west_east", t]) == 1e5 for t in time_steps)
end

@testset "Interface flow-limit params are one merged container per type" begin
    # VariableMaxInterfaceFlow builds Min/MaxInterfaceFlowLimitParameter as one container per type
    # over all interface names (empty meta).
    # DELETE-AFTER-REVIEW: reviewer context on the container change; remove once the PR is approved.
    # The 3-arg fetch below would throw if the container were still per-service `meta = name`.
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
        # 3-arg fetch (no meta) succeeds only if the container is merged per type.
        param = IOM.get_parameter(container, P, TransmissionInterface)
        @test param !== nothing
    end
    # The flow-limit constraint (which reads the merged params) built for the interface.
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
    # A ConstantReserveGroup's RequirementConstraint must sum the ActivePowerReserveVariable of
    # every contributing service (and only those) across the merged (service, device, time)
    # container. Exercises reserve_group.jl `add_constraints!` and its `_accumulate_group_reserve!`
    # function barrier. This path was previously unbuildable (the old
    # `_populate_contributing_devices!` errored on a ConstantReserveGroup); it is now reachable
    # because the no-contributing-devices error is scoped to `PSY.Reserve` only.
    # `deepcopy` so the added group does not leak into the PSB-cached system.
    sys = deepcopy(PSB.build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true))
    r1 = PSY.get_component(VariableReserve{ReserveUp}, sys, "Reserve1")
    # Group contains ONLY Reserve1, so the constraint must include Reserve1's device variables and
    # exclude Reserve11's — verifying the barrier's per-service `key[1] == r_name` filtering.
    group = ConstantReserveGroup{ReserveUp}(;
        name = "group_up",
        available = true,
        requirement = 0.0,
    )
    add_service!(sys, group, Service[r1])

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))
    set_service_model!(
        template,
        ServiceModel(ConstantReserveGroup{ReserveUp}, GroupReserve),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    rv = IOM.get_variable(container, ActivePowerReserveVariable, VariableReserve{ReserveUp})
    con = IOM.get_constraint(
        container,
        RequirementConstraint,
        ConstantReserveGroup{ReserveUp},
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

# NOT PORTED — blocked by POM source gaps (these PSI testsets need src changes, out of
# scope for a test-only port):
#  - "Test Reserves with Feedforwards": the concrete feedforward types
#    (`LowerBoundFeedforward`, `FixValueFeedforward`, …) are not defined in POM or IOM —
#    only the feedforward constraint types and the abstract construct hooks exist.
# Also not ported (feature/framework not in POM): AGC (no `template_agc_reserve_deployment`),
# Hydro reserves (`HydroTurbineEnergyDispatch` absent), the old bare-`TimeSeriesKey` ORDC
# tests (psy6 uses `ReserveDemandTimeSeriesCurve`; covered by the two ORDC testsets above),
# and all Simulation-orchestration testsets (Simulation framework absent in the IOM/POM split).
