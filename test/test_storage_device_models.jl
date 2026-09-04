# Deactivate demand-curve reserves (ORDC1 in `c_sys5_bat`) so a template registering
# `ServiceModel(OnlineReserve{Dir}, RangeReserve)` models only the requirement reserves
# (Reserve3 up, Reserve4 down); one `ServiceModel` covers every service of its type, so an
# available ORDC would be swept into the same model and widen the tests' scope.
function _deactivate_unmodeled_ordc!(sys)
    for r in PSY.get_components(PSY.has_demand_curve, PSY.OnlineReserve, sys)
        PSY.set_available!(r, false)
    end
    return sys
end

@testset "Storage Basic Storage With DC - PF" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 72, 0, 72, 72, 24, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 72, 0, 120, 72, 24, false)
end

@testset "Storage Basic Storage With AC - PF" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 96, 0, 96, 96, 24, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 96, 0, 144, 96, 24, false)
    # Outage constraint for reactive power is quadratic:
    @test JuMP.num_constraints(get_jump_model(model), GQEVF, MOI.LessThan{Float64}) ==
          24
end

@testset "Storage with Reservation  & DC - PF" begin
    device_model = DeviceModel(EnergyReservoirStorage, StorageDispatchWithReserves)
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 96, 0, 72, 72, 24, true)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 96, 0, 120, 72, 24, true)
end

@testset "Storage with Reservation  & AC - PF" begin
    device_model = DeviceModel(EnergyReservoirStorage, StorageDispatchWithReserves)
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 120, 0, 96, 96, 24, true)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 120, 0, 144, 96, 24, true)
    # Outage constraint for reactive power is quadratic:
    @test JuMP.num_constraints(get_jump_model(model), GQEVF, MOI.LessThan{Float64}) ==
          24
end

@testset "EnergyReservoirStorage with EnergyTarget with DC - PF" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat_ems")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 98, 0, 72, 72, 25, true)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 98, 0, 120, 72, 25, true)

    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 74, 0, 72, 72, 25, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 74, 0, 120, 72, 25, false)
end

@testset "EnergyReservoirStorage with EnergyTarget With AC - PF" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat_ems")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 122, 0, 96, 96, 25, true)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 122, 0, 144, 96, 25, true)

    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat_ems")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 98, 0, 96, 96, 25, false)
    psi_checkobjfun_test(model, GAEVF)
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model; add_event_model = true)
    moi_tests(model, 98, 0, 144, 96, 25, false)
    # Outage constraint for reactive power is quadratic:
    @test JuMP.num_constraints(get_jump_model(model), GQEVF, MOI.LessThan{Float64}) ==
          24
end

### Feedforward Test ###
# TODO: blocked on the StorageSystemsSimulations feedforward port, not on events:
# `EnergyTargetFeedforward` does not exist in POM yet. The event assertions inside are
# ported from SSS and should be re-enabled with the rest of the block.
#=
@testset "Test EnergyTargetFeedforward to EnergyReservoirStorage with StorageDispatch model" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )

    ff_et = EnergyTargetFeedforward(;
        component_type = EnergyReservoirStorage,
        source = EnergyVariable,
        affected_values = [EnergyVariable],
        target_period = 24,
        penalty_cost = 1e5,
    )

    attach_feedforward!(device_model, ff_et)
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)
    moi_tests(model, 122, 0, 72, 73, 24, true)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(
        model,
        device_model;
        built_for_recurrent_solves = true,
        add_event_model = true,
    )
    moi_tests(model, 170, 0, 120, 73, 24, true)
end

@testset "Test EnergyTargetFeedforward to EnergyReservoirStorage with StorageDispatch model" begin
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )

    ff_et = EnergyTargetFeedforward(;
        component_type = EnergyReservoirStorage,
        source = EnergyVariable,
        affected_values = [EnergyVariable],
        target_period = 24,
        penalty_cost = 1e5,
    )

    attach_feedforward!(device_model, ff_et)
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat_ems")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)
    moi_tests(model, 122, 0, 72, 73, 24, true)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(
        model,
        device_model;
        built_for_recurrent_solves = true,
        add_event_model = true,
    )
    moi_tests(model, 170, 0, 120, 73, 24, true)
end
=#

@testset "Test Reserves from Storage" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => true,
            "regularization" => true,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )

    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    _deactivate_unmodeled_ordc!(c_sys5_bat)
    model = DecisionModel(template, c_sys5_bat)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT
    # Complete-coverage constraints are built once per unique service type and side (each
    # sums every same-direction service), so the battery's two up-reserves share a single
    # 24-row container per coverage family.
    moi_tests(model, 458, 0, 526, 286, 125, true)

    # Silent-failure guard: each storage total-reserve balance row must hold exactly three
    # terms (charge + discharge - award). If the service-device wiring is skipped, the award
    # term vanishes while every constraint count still matches, letting storage "provide"
    # reserves with no physical backing.
    constraints = IOM.get_constraints(model)
    for (service_type, s_name) in (
        (OnlineReserve{ReserveUp}, "Reserve3"),
        (OnlineReserve{ReserveDown}, "Reserve4"),
    )
        key = IOM.ConstraintKey(
            StorageTotalReserveConstraint,
            service_type,
            "$(s_name)_$EnergyReservoirStorage",
        )
        con = constraints[key]
        @test all(
            length(JuMP.constraint_object(con[n, t]).func.terms) == 3
            for n in axes(con)[1], t in axes(con)[2]
        )
    end

    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => true,
            "regularization" => true,
        ),
    )
    set_device_model!(template, device_model)
    model = DecisionModel(template, c_sys5_bat)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT
    moi_tests(model, 434, 0, 526, 286, 125, false)
end

@testset "OfflineReserve (non-spin) as ORDC supplied by storage" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = false)
    nspin = OfflineReserve(;
        name = "NSPIN",
        available = true,
        time_frame = 30.0,
        sustained_time = 3600.0,
        variable = make_market_bid_curve(
            [0.0, 20.0, 40.0], [60.0, 10.0], 0.0; power_units = IS.NaturalUnit(),
        ),
    )
    bat = get_component(EnergyReservoirStorage, sys, "Bat")
    thermals = collect(get_components(ThermalStandard, sys))
    add_service!(sys, nspin, vcat(PSY.Device[thermals...], bat))

    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    set_device_model!(
        template,
        DeviceModel(
            EnergyReservoirStorage,
            StorageDispatchWithReserves;
            attributes = Dict{String, Any}(
                "reservation" => true,
                "cycling_limits" => false,
                "energy_target" => false,
                "complete_coverage" => true,
                "regularization" => false,
            ),
        ),
    )
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(template, ServiceModel(OfflineReserve, StepwiseCostReserve))

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    # The up-side SOC coverage rows must exist for the non-spin product (it routes as an
    # upward reserve), including the complete-coverage family.
    container = IOM.get_optimization_container(model)
    meta = POM._service_container_meta(nspin)
    @test IOM.has_container_key(
        container, ReserveCoverageConstraint, EnergyReservoirStorage,
        "$(meta)_discharge",
    )
    @test IOM.has_container_key(
        container, POM.ReserveCompleteCoverageConstraint, EnergyReservoirStorage,
        "$(OfflineReserve{IS.NaturalUnit})_discharge",
    )

    # Balance rows carry charge + discharge - award: the award term is wired, not skipped.
    con = IOM.get_constraints(model)[IOM.ConstraintKey(
        StorageTotalReserveConstraint, OfflineReserve, "NSPIN_$EnergyReservoirStorage",
    )]
    @test all(
        length(JuMP.constraint_object(con[n, t]).func.terms) == 3
        for n in axes(con)[1], t in axes(con)[2]
    )

    @test solve!(model) == RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    demand = read_variable(
        res, "ServiceRequirementVariable__OfflineReserve";
        table_format = TableFormat.WIDE,
    )
    @test all(demand[t, "NSPIN"] > 1.0 for t in 1:24)
end

@testset "Energy/AS decoupling: reserve_coverage = false" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => false,
            "reserve_coverage" => false,
            # Deliberately true: the decoupling must suppress it (with a warning).
            "complete_coverage" => true,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveUp}, RangeReserve))
    set_service_model!(template, ServiceModel(OnlineReserve{ReserveDown}, RangeReserve))
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    _deactivate_unmodeled_ordc!(c_sys5_bat)
    model = DecisionModel(template, c_sys5_bat)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    constraints = IOM.get_constraints(model)
    # No SOC coverage of any flavor: individual, end-of-period, or complete (the
    # complete_coverage = true above must be suppressed by the decoupling).
    coverage_types = (
        ReserveCoverageConstraint,
        ReserveCoverageConstraintEndOfPeriod,
        ReserveCompleteCoverageConstraint,
        ReserveCompleteCoverageConstraintEndOfPeriod,
    )
    @test all(k -> IOM.get_entry_type(k) ∉ coverage_types, keys(constraints))

    # The reservation binary still exists: energy charge/discharge exclusivity is kept.
    variables = IOM.get_variables(model)
    resv_key = IOM.VariableKey(ReservationVariable, EnergyReservoirStorage)
    @test haskey(variables, resv_key)

    # ...but the reserve band is decoupled from it: no deployment power-limit row may
    # reference the binary (the no-reservation bound builders are used instead).
    ss_vars = Set(vec(variables[resv_key].data))
    for ckey in keys(constraints)
        IOM.get_entry_type(ckey) in (
            POM.OutputActivePowerVariableLimitsConstraint,
            POM.InputActivePowerVariableLimitsConstraint,
        ) || continue
        arr = constraints[ckey]
        data = arr isa JuMP.Containers.DenseAxisArray ? arr.data : arr
        for i in eachindex(data)
            isassigned(data, i) || continue
            func = JuMP.constraint_object(data[i]).func
            func isa JuMP.GenericAffExpr || continue
            @test isempty(intersect(Set(keys(func.terms)), ss_vars))
        end
    end
end

@testset "Test Storage Energy Target Constraint" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)

    c_sys5_bat_ems = PSB.build_system(PSITestSystems, "c_sys5_bat_ems")
    model = DecisionModel(template, c_sys5_bat_ems)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    target_con =
        get_constraint(container, StateofChargeTargetConstraint, EnergyReservoirStorage)
    time_steps = get_time_steps(container)
    @test axes(target_con) == (["Bat2"], [time_steps[end]])

    d = only(get_components(EnergyReservoirStorage, c_sys5_bat_ems))
    target = PSY.get_storage_target(d)
    con = target_con["Bat2", time_steps[end]]
    @test JuMP.normalized_rhs(con) == target
    energy_var = IOM.get_variable(container, EnergyVariable, EnergyReservoirStorage)
    surplus_var =
        IOM.get_variable(container, StorageEnergySurplusVariable, EnergyReservoirStorage)
    shortfall_var =
        IOM.get_variable(container, StorageEnergyShortageVariable, EnergyReservoirStorage)
    @test JuMP.normalized_coefficient(con, energy_var["Bat2", time_steps[end]]) == 1.0
    @test JuMP.normalized_coefficient(con, surplus_var["Bat2", time_steps[end]]) == -1.0
    @test JuMP.normalized_coefficient(con, shortfall_var["Bat2", time_steps[end]]) == 1.0
end

@testset "Test Storage Cycling Limits without Reserves" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => true,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)

    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(template, c_sys5_bat)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    charge_con = get_constraint(container, StorageCyclingCharge, EnergyReservoirStorage)
    discharge_con =
        get_constraint(container, StorageCyclingDischarge, EnergyReservoirStorage)
    time_steps = get_time_steps(container)
    @test axes(charge_con) == (["Bat"], [time_steps[end]])
    @test axes(discharge_con) == (["Bat"], [time_steps[end]])
end

@testset "Test Storage Cycling Limits with Reserves" begin
    template = get_thermal_dispatch_template_network(CopperPlateNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => true,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )

    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    _deactivate_unmodeled_ordc!(c_sys5_bat)
    model = DecisionModel(template, c_sys5_bat)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    container = get_optimization_container(model)
    charge_con = get_constraint(container, StorageCyclingCharge, EnergyReservoirStorage)
    discharge_con =
        get_constraint(container, StorageCyclingDischarge, EnergyReservoirStorage)
    time_steps = get_time_steps(container)
    @test axes(charge_con) == (["Bat"], [time_steps[end]])
    @test axes(discharge_con) == (["Bat"], [time_steps[end]])
end

@testset "Storage with regularization and ACPNetworkModel" begin
    template = get_thermal_dispatch_template_network(ACPNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => false,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => true,
        ),
    )
    set_device_model!(template, device_model)
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(template, c_sys5_bat; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    constraint_types = IOM.get_entry_type.(IOM.get_constraint_keys(container))
    @test StorageRegularizationConstraintCharge in constraint_types
    @test StorageRegularizationConstraintDischarge in constraint_types
end

@testset "Storage with service model and ACPNetworkModel" begin
    template = get_thermal_dispatch_template_network(ACPNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )

    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    _deactivate_unmodeled_ordc!(c_sys5_bat)
    model = DecisionModel(template, c_sys5_bat; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT
end

@testset "Storage with complete coverage, service model and ACPNetworkModel" begin
    template = get_thermal_dispatch_template_network(ACPNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => true,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, FixedOutput)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )

    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat"; add_reserves = true)
    _deactivate_unmodeled_ordc!(c_sys5_bat)
    model = DecisionModel(template, c_sys5_bat; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    constraint_types = IOM.get_entry_type.(IOM.get_constraint_keys(container))
    @test ReserveCompleteCoverageConstraint in constraint_types
end

@testset "Test AreaPTDF System Balance" begin
    sys = build_system(PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(sys, Hour(2), Hour(2))
    bat = EnergyReservoirStorage(;
        name = "bat",
        available = true,
        bus = get_bus(sys, 11),
        prime_mover_type = PrimeMovers.BA,
        storage_technology_type = StorageTech.OTHER_CHEM,
        storage_capacity = 4.0,
        storage_level_limits = (min = 0.0, max = 1.0),
        initial_storage_capacity_level = 0.5,
        rating = 4.0,
        active_power = 4.0,
        input_active_power_limits = (min = 0.0, max = 2.0),
        output_active_power_limits = (min = 0.0, max = 2.0),
        efficiency = (in = 0.9, out = 0.9),
        reactive_power = 0.0,
        reactive_power_limits = (min = -2.0, max = 2.0),
        base_power = 100.0,
    )
    add_component!(sys, bat)

    template = get_thermal_dispatch_template_network(AreaPTDFNetworkModel)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => true,
        ),
    )
    set_device_model!(template, device_model)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)

    model = DecisionModel(template, sys)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT
    moi_tests(model, 40, 0, 56, 52, 13, true)
end

#=
@testset "Test EnergyLimitFeedforward to EnergyReservoirStorage with BookKeeping model" begin
    device_model = DeviceModel(EnergyReservoirStorage, BookKeeping)

    ff_il = EnergyLimitFeedforward(;
        component_type=EnergyReservoirStorage,
        source=ActivePowerOutVariable,
        affected_values=[ActivePowerOutVariable],
        number_of_periods=12,
    )

    attach_feedforward!(device_model, ff_il)
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; built_for_recurrent_solves=true)
    moi_tests(model, 121, 0, 74, 72, 24, true)
end

@testset "Test EnergyLimitFeedforward to EnergyReservoirStorage with BatteryAncillaryServices model" begin
    device_model = DeviceModel(EnergyReservoirStorage, BatteryAncillaryServices)

    ff_il = EnergyLimitFeedforward(;
        component_type=EnergyReservoirStorage,
        source=ActivePowerOutVariable,
        affected_values=[ActivePowerOutVariable],
        number_of_periods=12,
    )

    attach_feedforward!(device_model, ff_il)
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; built_for_recurrent_solves=true)
    moi_tests(model, 121, 0, 74, 72, 24, true)
end
=#
