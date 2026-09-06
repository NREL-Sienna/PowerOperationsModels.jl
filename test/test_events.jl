@testset "EventKey and EventModel construction" begin
    key = EventKey(PSY.FixedForcedOutage, PSY.ThermalStandard)
    @test IOM.get_entry_type(key) == PSY.FixedForcedOutage
    @test IOM.get_component_type(key) == PSY.ThermalStandard
    # Abstract component types are rejected
    @test_throws ErrorException EventKey(PSY.FixedForcedOutage, PSY.ThermalGen)

    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    @test get_event_type(em) == PSY.FixedForcedOutage
    @test get_event_condition(em) isa ContinuousCondition
    @test em.timeseries_mapping ==
          Dict{Symbol, Union{String, Nothing}}(:outage_status => nothing)
    @test isempty(get_attribute_device_map(em))

    em_geo = EventModel(PSY.GeometricDistributionForcedOutage, ContinuousCondition())
    @test Set(keys(em_geo.timeseries_mapping)) ==
          Set([:mean_time_to_recovery, :outage_transition_probability])

    pc = PresetTimeCondition([Dates.DateTime("2024-01-01T05:00:00")])
    @test get_time_stamps(pc) == [Dates.DateTime("2024-01-01T05:00:00")]
end

@testset "Event condition types: accessors" begin
    svc = StateVariableValueCondition(ActivePowerVariable(), PSY.ThermalStandard, "x", 0.0)
    @test POM.get_variable_type(svc) isa ActivePowerVariable
    @test POM.get_device_type(svc) == PSY.ThermalStandard
    @test POM.get_device_name(svc) == "x"
    @test IOM.get_value(svc) == 0.0

    dec = DiscreteEventCondition(x -> true)
    @test POM.get_condition_function(dec)(1) == true
end

@testset "Event traits" begin
    @test POM.supports_events(PSY.ThermalStandard)
    @test POM.supports_events(PSY.RenewableDispatch)
    @test POM.supports_events(PSY.PowerLoad)
    @test POM.supports_events(PSY.HydroDispatch)
    @test POM.supports_events(PSY.EnergyReservoirStorage)
    @test !POM.supports_events(PSY.Source)

    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    d = PSY.ThermalStandard(nothing)
    @test POM.get_initial_parameter_value(AvailableStatusParameter(), d, em) == 1.0
    @test POM.get_initial_parameter_value(
        AvailableStatusChangeCountdownParameter(),
        d,
        em,
    ) == 0.0
    @test POM.get_initial_parameter_value(ActivePowerOffsetParameter(), d, em) == 0.0
    @test POM.get_initial_parameter_value(ReactivePowerOffsetParameter(), d, em) == 0.0
    @test POM.get_parameter_multiplier(AvailableStatusParameter(), d, em) == 1.0
end

@testset "Template-level event attachment" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    @test isempty(get_event_models(template))
    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    set_event_model!(template, em)
    @test length(get_event_models(template)) == 1
    @test get_event_models(template)[1] === em
    # Same event model instance can't be attached twice
    @test_throws ErrorException set_event_model!(template, em)
end

@testset "Event discovery and validation at build" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    outage = attach_fixed_forced_outage!(sys, thermal)

    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em = fixed_outage_event()
    set_event_model!(template, em)

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    # Discovery populated the map: attribute id -> device type -> names
    map_ = get_attribute_device_map(em)
    attribute_id = IS.get_id(outage)
    @test haskey(map_, attribute_id)
    @test map_[attribute_id][PSY.ThermalStandard] == Set([PSY.get_name(thermal)])

    # The caller's template DeviceModels were not mutated (build-copy isolation)
    caller_dm = get_model(template, PSY.ThermalStandard)
    @test isempty(IOM.get_events(caller_dm))
end

@testset "Event validation errors" begin
    sys_clean = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em = fixed_outage_event()
    set_event_model!(template, em)
    model = DecisionModel(template, sys_clean; optimizer = HiGHS_optimizer)
    # No supplemental attributes in the system -> loud build failure
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED

    # Unknown mapping key rejected
    sys2 = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal2 = first(PSY.get_components(PSY.ThermalStandard, sys2))
    attach_fixed_forced_outage!(sys2, thermal2)
    template2 = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em_bad = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :not_a_parameter => "outage_profile",
        ),
    )
    set_event_model!(template2, em_bad)
    model2 = DecisionModel(template2, sys2; optimizer = HiGHS_optimizer)
    @test build!(model2; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED

    # FixedForcedOutage requires :outage_status mapping
    sys3 = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal3 = first(PSY.get_components(PSY.ThermalStandard, sys3))
    attach_fixed_forced_outage!(sys3, thermal3)
    template3 = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em_nomapping = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    set_event_model!(template3, em_nomapping)
    model3 = DecisionModel(template3, sys3; optimizer = HiGHS_optimizer)
    @test build!(model3; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED

    # Two distinct event models of the same contingency type both discovering the same
    # device type is a conflict: a DeviceModel has one events slot per (contingency
    # type, device type) key, so the second registration can't be silently dropped.
    sys4 = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal4 = first(PSY.get_components(PSY.ThermalStandard, sys4))
    attach_fixed_forced_outage!(sys4, thermal4)
    template4 = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em4a = fixed_outage_event()
    em4b = fixed_outage_event()
    set_event_model!(template4, em4a)
    set_event_model!(template4, em4b)
    model4 = DecisionModel(template4, sys4; optimizer = HiGHS_optimizer)
    @test build!(model4; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "Events excluded from initialization problem" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    template = get_thermal_standard_uc_template()
    em = fixed_outage_event()
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    # `build!` discards the initial-conditions container once it is solved and
    # serialized (see `handle_initial_conditions!`), so inspect it directly by
    # replicating the pre-solve portion of the build pipeline instead of going
    # through the full `build!`/`solve!` round trip.
    POM.build_pre_step!(model)
    IOM.instantiate_network_model!(model)
    POM.build_initial_conditions!(model)
    ic_container = IOM.get_initial_conditions_model_container(IOM.get_internal(model))
    @test ic_container !== nothing
    ic_keys = IOM.get_parameter_keys(ic_container)
    @test !any(k -> IOM.get_entry_type(k) <: EventParameter, ic_keys)

    # Continue the build pipeline into the main container (the next step after
    # initial conditions in `build_model!`) to confirm event parameters land there,
    # in contrast to their absence from the IC container asserted above.
    POM.build_problem!(
        IOM.get_optimization_container(model),
        IOM.get_template(model),
        IOM.get_system(model),
    )
    main_keys = IOM.get_parameter_keys(IOM.get_optimization_container(model))
    @test any(k -> IOM.get_entry_type(k) <: EventParameter, main_keys)
end

@testset "Event parameters via mock construct - ThermalStandard UC" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    @test !isnothing(
        IOM.get_parameter(container, AvailableStatusParameter, PSY.ThermalStandard),
    )
    @test !isnothing(
        IOM.get_parameter(
            container,
            AvailableStatusChangeCountdownParameter,
            PSY.ThermalStandard,
        ),
    )
    param_array =
        IOM.get_parameter_array(container, AvailableStatusParameter(), PSY.ThermalStandard)
    # Initial availability is 1.0 for every (device, t)
    @test all(IOM.jump_value.(param_array.data) .== 1.0)
end

@testset "Event arguments for loads add offset parameters" begin
    device_model = DeviceModel(PSY.PowerLoad, StaticPowerLoad)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    container, _ = mock_event_container(
        device_model,
        CopperPlateNetworkModel;
        sys = sys,
    )
    @test !isnothing(
        IOM.get_parameter(container, ActivePowerOffsetParameter, PSY.PowerLoad),
    )
    # AvailableStatus/Countdown params exist too.
    @test !isnothing(
        IOM.get_parameter(container, AvailableStatusParameter, PSY.PowerLoad),
    )
    @test !isnothing(
        IOM.get_parameter(
            container,
            AvailableStatusChangeCountdownParameter,
            PSY.PowerLoad,
        ),
    )
    # CopperPlate mock network -> the offset parameter's term lands in the system-level
    # active power balance expression (single target: the reference-bus row).
    system_balance = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    @test !isnothing(system_balance)
end

@testset "Event arguments for FixedOutput take the offset path, not the constraint path" begin
    # FixedOutput has no dispatch variable, so events reach it the same way they
    # reach loads: status/countdown parameters plus an ActivePowerOffsetParameter
    # wired into the balance, and no outage constraint at all (`construct_device!`'s
    # ModelConstructStage for `DeviceModel{<:PSY.ThermalGen, FixedOutput}` is a no-op).
    device_model = DeviceModel(PSY.ThermalStandard, FixedOutput)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    # FixedOutput is driven by a `max_active_power` time series; c_sys5_uc's thermal
    # units carry none, so borrow the load's forecast shape (matches the pattern in
    # test_device_thermal_generation_constructors.jl's FixedOutput testset).
    forecast = PSY.get_time_series(
        Deterministic,
        first(PSY.get_components(PSY.PowerLoad, sys)),
        "max_active_power",
    )
    for device in PSY.get_components(PSY.ThermalStandard, sys)
        PSY.add_time_series!(sys, device, forecast)
    end
    container, _ = mock_event_container(
        device_model,
        CopperPlateNetworkModel;
        sys = sys,
    )
    @test !isnothing(
        IOM.get_parameter(container, AvailableStatusParameter, PSY.ThermalStandard),
    )
    @test !isnothing(
        IOM.get_parameter(
            container,
            AvailableStatusChangeCountdownParameter,
            PSY.ThermalStandard,
        ),
    )
    @test !isnothing(
        IOM.get_parameter(container, ActivePowerOffsetParameter, PSY.ThermalStandard),
    )
    @test_throws IS.InvalidValue IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.ThermalStandard,
        "ub",
    )
end

@testset "Event constraints - thermal UC counts and coefficients" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    # add_parameterized_upper_bound_range_constraints stores its constraint under
    # meta = "ub" (constraint_meta(UpperBound())).
    cons = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.ThermalStandard,
        "ub",
    )
    n_thermal_with_event = 1  # mock attaches the outage to exactly one device
    time_steps = IOM.get_time_steps(container)
    @test size(cons)[1] == n_thermal_with_event
    @test size(cons)[2] == length(time_steps)
    # Coefficient check: constraint is expr(p) - ub * status <= 0 with status = 1.0
    # (params are plain Float64 in a non-recurrent build, so the RHS is baked in).
    outaged_name = axes(cons)[1][1]
    c1 = JuMP.constraint_object(cons[outaged_name, 1])
    @test c1.set isa MOI.LessThan{Float64}
    # Value-level check on the baked RHS: guards the IOM
    # `_bound_range_with_parameter!` EventParameter specialization together with
    # `IOM.get_max_active_power`. At build time status = 1.0 and the LHS
    # expression (ActivePowerRangeExpressionUB) carries no constant term here, so
    # the normalized upper bound must equal the device's rated max active power.
    outaged_device = PSY.get_component(PSY.ThermalStandard, sys, outaged_name)
    @test c1.set.upper ≈ PSY.get_max_active_power(outaged_device, PSY.SU)
end

@testset "Event constraints - renewable counts on ActivePowerVariable" begin
    device_model = DeviceModel(PSY.RenewableDispatch, RenewableFullDispatch)
    sys = PSB.build_system(PSITestSystems, "c_sys5_re")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    # No service model attached -> lhs_type falls back to ActivePowerVariable.
    cons = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.RenewableDispatch,
        "ub",
    )
    n_renewable_with_event = 1  # mock attaches the outage to exactly one device
    time_steps = IOM.get_time_steps(container)
    @test size(cons)[1] == n_renewable_with_event
    @test size(cons)[2] == length(time_steps)
    c1 = JuMP.constraint_object(cons[axes(cons)[1][1], 1])
    @test c1.set isa MOI.LessThan{Float64}
end

@testset "Event constraints - load counts on ActivePowerVariable" begin
    # PowerLoadDispatch is a controllable-load formulation: applying it to a plain
    # PSY.PowerLoad silently swaps to StaticPowerLoad (no ActivePowerVariable), so
    # use InterruptiblePowerLoad + c_sys5_il, matching the constructor test fixture.
    device_model = DeviceModel(PSY.InterruptiblePowerLoad, PowerLoadDispatch)
    sys = PSB.build_system(PSITestSystems, "c_sys5_il")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    cons = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.InterruptiblePowerLoad,
        "ub",
    )
    n_load_with_event = 1  # mock attaches the outage to exactly one device
    time_steps = IOM.get_time_steps(container)
    @test size(cons)[1] == n_load_with_event
    @test size(cons)[2] == length(time_steps)
    c1 = JuMP.constraint_object(cons[axes(cons)[1][1], 1])
    @test c1.set isa MOI.LessThan{Float64}
end

@testset "Event constraints - hydro" begin
    device_model = DeviceModel(PSY.HydroDispatch, HydroDispatchRunOfRiver)
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    # add_parameterized_upper_bound_range_constraints stores its constraint under
    # meta = "ub" (constraint_meta(UpperBound())), matching the thermal/renewable pattern.
    @test !isnothing(
        IOM.get_constraint(
            container,
            ActivePowerOutageConstraint(),
            PSY.HydroDispatch,
            "ub",
        ),
    )
end

@testset "Event constraints - storage" begin
    device_model = DeviceModel(EnergyReservoirStorage, StorageDispatchWithReserves)
    sys = PSB.build_system(PSITestSystems, "c_sys5_bat")
    container, _ = mock_event_container(
        device_model,
        DCPNetworkModel;
        sys = sys,
    )
    cons_in = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        EnergyReservoirStorage,
        "input",
    )
    cons_out = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        EnergyReservoirStorage,
        "output",
    )
    @test !isnothing(cons_in)
    @test !isnothing(cons_out)
end

@testset "Event constraints - hydro pump turbine" begin
    device_model = DeviceModel(
        HydroPumpTurbine,
        HydroPumpEnergyDispatch;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "energy_target" => true,
        ),
    )
    sys = hydro_pump_energy_system()
    container, _ = mock_event_container(
        device_model,
        CopperPlateNetworkModel;
        sys = sys,
    )
    @test !isnothing(
        IOM.get_constraint(container, ActivePowerOutageConstraint(), HydroPumpTurbine),
    )
    @test !isnothing(
        IOM.get_constraint(
            container,
            ActivePowerPumpOutageConstraint(),
            HydroPumpTurbine,
        ),
    )
end

@testset "E2E: thermal outage builds and solves - $(net)" for net in (
    CopperPlateNetworkModel,
    PTDFNetworkModel,
    DCPNetworkModel,
)
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    model, status, _ = build_outage_model(sys, thermal; network = net)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    # Event parameters are written to results (should_write_resulting_value = true)
    res = OptimizationProblemOutputs(model)
    @test "AvailableStatusParameter__ThermalStandard" in list_parameter_names(res)
end

@testset "E2E: thermal outage under AC builds the quadratic reactive constraint" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    model, status, _ = build_outage_model(
        sys,
        thermal;
        network = ACPNetworkModel,
        optimizer = ipopt_optimizer,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    # `q^2 <= ub * status` is only added under AbstractReactivePowerNetworkModel.
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_constraint(
            container,
            ReactivePowerOutageConstraint(),
            PSY.ThermalStandard,
            "ub",
        ),
    )
end

@testset "E2E: PTDF network with a load event exercises the 2-target balance offset" begin
    # PTDF's `_balance_expression_targets` writes an offset term to both the
    # system-level entry and the nodal (ACBus) entry, unlike CopperPlate/DCP which
    # write one target. Loads exercise it because they get an
    # `ActivePowerOffsetParameter` injected directly into the balance expression.
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    model, status, _ = build_outage_model(sys, load; network = PTDFNetworkModel)
    @test status == IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, ActivePowerOffsetParameter, PSY.PowerLoad),
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "E2E: ACP network with a load event adds the reactive offset parameter" begin
    # ACPNetworkModel <: AbstractReactivePowerNetworkModel, so the load
    # `add_event_arguments!` method with `with_reactive = true` runs.
    # Existence of the parameter is all a full build can show here: in a
    # non-recurrent build event parameters are baked Float64 constants (see
    # `get_param_eltype`), so their contribution to the balance is folded into the
    # expression's constant. The coefficient check lives in the recurrent-mode
    # testset below.
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    model, status, _ = build_outage_model(
        sys,
        load;
        network = ACPNetworkModel,
        optimizer = ipopt_optimizer,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, ReactivePowerOffsetParameter, PSY.PowerLoad),
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Outage zeroes $(case.name) output" for case in outage_zero_output_cases()
    # Maximizing exactly what the outage should suppress means the result is zero
    # only if the outage constraints actually bind; a mock model has no objective,
    # so an unconstrained build would otherwise return zero anyway.
    container, _ = mock_event_container(
        case.device_model,
        case.network;
        sys = case.build_sys(),
        recurrent = true,
    )
    status, values = maximize_under_outage(container, case.dtype, case.vars)
    @test status in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    @test all(all(abs.(v) .<= 1e-6) for v in values)
end

@testset "Two event models of different contingency types on one device type fail loudly" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    geo_outage = PSY.GeometricDistributionForcedOutage(;
        mean_time_to_recovery = 2.0,
        outage_transition_probability = 0.1,
    )
    PSY.add_supplemental_attribute!(sys, thermal, geo_outage)

    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em_fixed = fixed_outage_event()
    em_geo = EventModel(PSY.GeometricDistributionForcedOutage, ContinuousCondition())
    set_event_model!(template, em_fixed)
    set_event_model!(template, em_geo)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    # Discovery must reject the second event model with a clear error instead of letting
    # the two models' parameter containers collide inside the optimization container.
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "Event constraints stub errors when events are attached, no-ops when empty" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    container = IOM.get_optimization_container(model)
    network_model = NetworkModel(CopperPlateNetworkModel)

    # Empty events dict: the fallback stays a silent no-op (constructors call it
    # unconditionally for every device model).
    clean_model = DeviceModel(PSY.Source, FixedOutput)
    @test isnothing(
        POM.add_event_constraints!(container, PSY.Source[], clean_model, network_model),
    )

    # Events attached to a device model with no constraint implementation: availability
    # parameters would be enforced by nothing, so the fallback must error.
    event_model = DeviceModel(PSY.Source, FixedOutput)
    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    set_event_model!(event_model, EventKey(PSY.FixedForcedOutage, PSY.Source), em)
    @test_throws ErrorException POM.add_event_constraints!(
        container,
        PSY.Source[],
        event_model,
        network_model,
    )
end

#################################################################################
# Semantic checks beyond constraint counts.
#
# The shared path (`add_parameterized_upper_bound_range_constraints` ->
# IOM `_bound_range_with_parameter!` -> `IOM.get_max_active_power`, whose single
# POM method passes `PSY.SU`) is component-neutral, so the thermal RHS check
# above covers units for thermal/renewable/load/hydro alike. What is *not*
# shared, and is checked here:
#
#   - which variable each constraint bounds (a swapped LHS is invisible to counts),
#   - the three hand-written builders that compute their own right-hand sides
#     (reactive, hydro pump, storage input/output),
#   - that an outage actually forces output to zero, which is the intended
#     behavior rather than a restatement of the builder.
#################################################################################

@testset "Outage constraint bounds the intended variable - $(dtype)" for (
    dtype,
    formulation,
    sysname,
) in (
    (PSY.ThermalStandard, ThermalBasicUnitCommitment, "c_sys5_uc"),
    (PSY.RenewableDispatch, RenewableFullDispatch, "c_sys5_re"),
    (PSY.InterruptiblePowerLoad, PowerLoadDispatch, "c_sys5_il"),
    (PSY.HydroDispatch, HydroDispatchRunOfRiver, "c_sys5_hy"),
)
    # A wrong LHS array passes every count and set-type assertion. For thermal and
    # hydro the LHS is an expression wrapping the active power variable, which
    # carries the same coefficient, so one assertion covers both shapes.
    container, _ =
        mock_event_container(DeviceModel(dtype, formulation), DCPNetworkModel, sysname)
    cons = IOM.get_constraint(container, ActivePowerOutageConstraint(), dtype, "ub")
    var = IOM.get_variable(container, ActivePowerVariable, dtype)
    name = outaged_name(container, dtype)
    t = first(IOM.get_time_steps(container))
    c = JuMP.constraint_object(cons[name, t])
    @test JuMP.coefficient(c.func, var[name, t]) ≈ 1.0
end

@testset "Storage outage constraints are not swapped between charge and discharge" begin
    container, sys = mock_event_container(
        DeviceModel(EnergyReservoirStorage, StorageDispatchWithReserves),
        DCPNetworkModel,
        "c_sys5_bat",
    )
    p_in = IOM.get_variable(container, ActivePowerInVariable, EnergyReservoirStorage)
    p_out = IOM.get_variable(container, ActivePowerOutVariable, EnergyReservoirStorage)
    name = outaged_name(container, EnergyReservoirStorage)
    device = outaged_device(container, EnergyReservoirStorage, sys)
    t = first(IOM.get_time_steps(container))
    c_in = JuMP.constraint_object(
        IOM.get_constraint(
            container,
            ActivePowerOutageConstraint(),
            EnergyReservoirStorage,
            "input",
        )[
            name,
            t,
        ],
    )
    c_out = JuMP.constraint_object(
        IOM.get_constraint(
            container,
            ActivePowerOutageConstraint(),
            EnergyReservoirStorage,
            "output",
        )[
            name,
            t,
        ],
    )
    @test JuMP.coefficient(c_in.func, p_in[name, t]) ≈ 1.0
    @test JuMP.coefficient(c_in.func, p_out[name, t]) ≈ 0.0
    @test JuMP.coefficient(c_out.func, p_out[name, t]) ≈ 1.0
    @test JuMP.coefficient(c_out.func, p_in[name, t]) ≈ 0.0
    # Bounds recomputed from the fixture in system base, not read back from
    # whatever the builder read.
    @test c_in.set.upper ≈ PSY.get_input_active_power_limits(device, PSY.SU).max
    @test c_out.set.upper ≈ PSY.get_output_active_power_limits(device, PSY.SU).max
end

@testset "Reactive outage constraint bounds q^2 by the squared reactive limit" begin
    # `q^2 <= ub * status` with a pre-squared `ub`. A missing or doubled square
    # survives every count assertion, so check the quadratic form directly: tight
    # exactly at the reactive limit, symmetric in sign, satisfied inside it and
    # violated outside.
    container, sys = mock_event_container(
        DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment),
        ACPNetworkModel,
        "c_sys5_uc",
    )
    q = IOM.get_variable(container, ReactivePowerVariable, PSY.ThermalStandard)
    name = outaged_name(container, PSY.ThermalStandard)
    device = outaged_device(container, PSY.ThermalStandard, sys)
    t = first(IOM.get_time_steps(container))
    c = JuMP.constraint_object(
        IOM.get_constraint(
            container,
            ReactivePowerOutageConstraint(),
            PSY.ThermalStandard,
            "ub",
        )[
            name,
            t,
        ],
    )
    limits = PSY.get_reactive_power_limits(device, PSY.SU)
    q_limit = max(abs(limits.max), abs(limits.min))

    @test JuMP.coefficient(c.func, q[name, t], q[name, t]) ≈ 1.0
    @test JuMP.coefficient(c.func, q[name, t]) ≈ 0.0
    at(val) = JuMP.value(v -> (v == q[name, t] ? val : 0.0), c.func)
    @test at(q_limit) ≈ c.set.upper
    @test at(-q_limit) ≈ c.set.upper
    @test at(0.5 * q_limit) < c.set.upper
    @test at(1.5 * q_limit) > c.set.upper
end

@testset "Load outage offsets enter the balance with the event-parameter multiplier" begin
    # The offset is a load's only outage mechanism (there is no variable to bound),
    # so the build must get one thing right: the parameter reaches the balance row
    # with multiplier 1.0, which is what makes the runtime's
    # `offset = -1 * <time series value>` cancel the injection rather than rescale
    # it. Zero means `add_to_expression!` never ran. The cancellation itself is a
    # runtime property POM never exercises, so PSI owns that test.
    container, sys, model = mock_event_container(
        DeviceModel(PSY.PowerLoad, StaticPowerLoad),
        ACPNetworkModel,
        "c_sys5_uc";
        recurrent = true,
    )
    name = outaged_name(container, PSY.PowerLoad)
    load = outaged_device(container, PSY.PowerLoad, sys)
    network_model = IOM.get_network_model(IOM.get_template(model))
    bus_no =
        PNM.get_mapped_bus_number(get_network_reduction(network_model), PSY.get_bus(load))
    t = first(IOM.get_time_steps(container))
    for (balance, offset_type) in (
        (ActivePowerBalance, ActivePowerOffsetParameter),
        (ReactivePowerBalance, ReactivePowerOffsetParameter),
    )
        row = IOM.get_expression(container, balance, PSY.ACBus)[bus_no, t]
        offset_ref =
            IOM.get_parameter_array(container, offset_type(), PSY.PowerLoad)[name, t]
        @test JuMP.coefficient(row, offset_ref) ≈ 1.0
    end
end

@testset "A thermal outage costs the same as forcing the unit off" begin
    # Independent formulation of the same physics: driving the availability
    # parameter to zero must leave the copperplate unit-commitment problem with
    # exactly the optimal cost of a system where the same unit is held off by
    # fixing its commitment variable. That checks the constraint's effect on the
    # optimum, not its structure -- a bound that is too loose, too tight, or
    # attached to the wrong device all change the cost.
    #
    # A commitment template is required, not a dispatch one: the outage bounds
    # active power from above only, so under a formulation that also enforces
    # `p >= p_min` with no on/off variable the outaged unit makes the model
    # infeasible. (That is what PSI's `has_outage` feedforward override exists to
    # relax, and it is a real constraint on where events can be used.)
    function _solve_uc(sys; outaged = nothing, force_off = nothing)
        template = get_thermal_standard_uc_template()
        if !isnothing(outaged)
            attach_fixed_forced_outage!(sys, outaged)
            set_event_model!(
                template,
                fixed_outage_event(),
            )
        end
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        # Event parameters are only JuMP parameters -- and so only fixable to an
        # outage value -- in recurrent-solve mode; see `get_param_eltype`.
        IOM.get_optimization_container(model).built_for_recurrent_solves = true
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        container = IOM.get_optimization_container(model)
        if !isnothing(outaged)
            status = IOM.get_parameter_array(
                container,
                AvailableStatusParameter(),
                PSY.ThermalStandard,
            )
            for idx in eachindex(status)
                JuMP.fix(status[idx], 0.0; force = true)
            end
        end
        if !isnothing(force_off)
            on = IOM.get_variable(container, OnVariable, PSY.ThermalStandard)
            for t in axes(on)[2]
                JuMP.fix(on[force_off, t], 0.0; force = true)
            end
        end
        jm = IOM.get_jump_model(container)
        JuMP.set_optimizer(jm, HiGHS.Optimizer)
        JuMP.set_silent(jm)
        JuMP.optimize!(jm)
        @test JuMP.termination_status(jm) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
        return JuMP.objective_value(jm)
    end

    sys_event = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    unit_name = PSY.get_name(first(PSY.get_components(PSY.ThermalStandard, sys_event)))
    cost_with_outage = _solve_uc(
        sys_event;
        outaged = PSY.get_component(PSY.ThermalStandard, sys_event, unit_name),
    )

    sys_forced_off = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    cost_forced_off = _solve_uc(sys_forced_off; force_off = unit_name)

    @test cost_with_outage ≈ cost_forced_off rtol = 1e-6
    # Guard against a degenerate fixture where the unit never ran anyway: losing it
    # has to actually cost something relative to the intact system.
    sys_intact = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    @test cost_with_outage > _solve_uc(sys_intact)
end
