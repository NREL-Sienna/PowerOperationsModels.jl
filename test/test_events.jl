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
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
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
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
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
    em4a = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
    em4b = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
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
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
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
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    outaged_device = first(
        d for d in PSY.get_components(PSY.ThermalStandard, sys) if
        PSY.get_name(d) == outaged_name
    )
    @test c1.set.upper ≈ PSY.get_max_active_power(outaged_device, PSY.SU)
end

@testset "Event constraints - renewable counts on ActivePowerVariable" begin
    device_model = DeviceModel(PSY.RenewableDispatch, RenewableFullDispatch)
    sys = PSB.build_system(PSITestSystems, "c_sys5_re")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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
    sys = PSB.build_system(
        PSITestSystems,
        "c_sys5_hydro_pump_energy";
        add_reserves = true,
        add_single_time_series = true,
    )
    transform_single_time_series!(sys, Hour(24), Hour(24))
    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
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

@testset "E2E: thermal UC with FixedForcedOutage event - $(net)" for net in
                                                                     (
    CopperPlateNetworkModel,
    PTDFNetworkModel,
    DCPNetworkModel,
)
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    template = get_thermal_dispatch_template_network(NetworkModel(net))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(model)
    # Event parameters are written to results (should_write_resulting_value = true)
    @test "AvailableStatusParameter__ThermalStandard" in list_parameter_names(res)
end

@testset "E2E: thermal UC with FixedForcedOutage event - ACPNetworkModel (reactive)" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container = IOM.get_optimization_container(model)
    # The quadratic reactive-power outage constraint (q^2 <= ub * status) is only
    # added under AbstractReactivePowerNetworkModel; confirm it was actually built.
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
    # system-level entry and the nodal (ACBus) entry -- unlike CopperPlate/DCP,
    # which only write one target. A load's FixedForcedOutage exercises this
    # because loads get an `ActivePowerOffsetParameter` injected directly into the
    # balance expression (see `_add_event_offset_arguments!`), unlike thermal units
    # which only touch the status/countdown parameters.
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    attach_fixed_forced_outage!(sys, load)
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, ActivePowerOffsetParameter, PSY.PowerLoad),
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "E2E: ACP network with a load event drives the reactive offset parameter into ReactivePowerBalance" begin
    # ACPNetworkModel <: AbstractReactivePowerNetworkModel, so the load
    # add_event_arguments! method with `with_reactive = true` runs, adding
    # ReactivePowerOffsetParameter and injecting it into ReactivePowerBalance.
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    attach_fixed_forced_outage!(sys, load)
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, ReactivePowerOffsetParameter, PSY.PowerLoad),
    )
    # ACPNetworkModel is a nodal (non-PTDF) network model, so the balance target is
    # the per-bus ACBus expression, not a system-wide one (see
    # `_balance_expression_targets`'s `<:AbstractNetworkModel` fallback method).
    # NOTE: existence of the parameter and existence of the expression container
    # together do not prove the offset term is actually wired INTO the balance --
    # `ReactivePowerBalance__ACBus` is allocated for every ACP build regardless of
    # events. The next testset verifies that linkage directly via a coefficient
    # check (this full E2E build can't do that itself: in a non-recurrent build,
    # event parameters are baked Float64 constants -- see `get_param_eltype` --
    # so their contribution is folded into the expression's constant and isn't
    # structurally inspectable).
    nodal_reactive_balance = IOM.get_expression(container, ReactivePowerBalance, PSY.ACBus)
    @test !isnothing(nodal_reactive_balance)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Event arguments for loads: reactive offset parameter has a nonzero coefficient in ReactivePowerBalance" begin
    # Recurrent-solve mode makes event parameters real JuMP variables (see
    # `get_param_eltype`), so we can check the offset's coefficient in the balance
    # expression directly with `JuMP.coefficient` -- a structural check that fails
    # if `add_to_expression!(container, ReactivePowerBalance,
    # ReactivePowerOffsetParameter, ...)` is ever removed from the reactive-load
    # `add_event_arguments!` method, unlike merely checking that the parameter and
    # the balance expression both exist (see the previous testset's note).
    device_model = DeviceModel(PSY.PowerLoad, StaticPowerLoad)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, sys)
    mock_construct_device!(
        model,
        device_model;
        add_event_model = true,
        built_for_recurrent_solves = true,
    )
    container = IOM.get_optimization_container(model)
    load = first(PSY.get_components(PSY.PowerLoad, sys))
    network_model = IOM.get_network_model(IOM.get_template(model))
    bus_no =
        PNM.get_mapped_bus_number(get_network_reduction(network_model), PSY.get_bus(load))
    t = first(IOM.get_time_steps(container))
    balance_row = IOM.get_expression(container, ReactivePowerBalance, PSY.ACBus)[bus_no, t]
    param_ref = IOM.get_parameter_array(
        container,
        ReactivePowerOffsetParameter(),
        PSY.PowerLoad,
    )[
        PSY.get_name(load),
        t,
    ]
    @test JuMP.coefficient(balance_row, param_ref) != 0.0
end

@testset "Forced outage drives device output to zero" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, sys)
    mock_construct_device!(
        model,
        device_model;
        add_event_model = true,
        built_for_recurrent_solves = true,
    )
    container = IOM.get_optimization_container(model)
    param_array = IOM.get_parameter_array(
        container,
        AvailableStatusParameter(),
        PSY.ThermalStandard,
    )
    outaged_name = axes(param_array)[1][1]
    for t in axes(param_array)[2]
        JuMP.fix(param_array[outaged_name, t], 0.0; force = true)
    end
    jm = IOM.get_jump_model(container)
    p = IOM.get_variable(container, ActivePowerVariable, PSY.ThermalStandard)
    # The mock model has no objective, so without an incentive to raise output,
    # the LP returns p = 0 by default even if ActivePowerOutageConstraint were
    # removed. Maximizing the outaged device's own output means the test only
    # passes if the constraint is actually forcing p to zero.
    JuMP.@objective(jm, Max, sum(p[outaged_name, t] for t in axes(p)[2]))
    JuMP.set_optimizer(jm, HiGHS.Optimizer)
    JuMP.set_silent(jm)
    JuMP.optimize!(jm)
    @test JuMP.termination_status(jm) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    @test all(
        abs(JuMP.value(p[outaged_name, t])) <= 1e-6 for t in axes(p)[2]
    )
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
    em_fixed = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(
            :outage_status => "outage_profile",
        ),
    )
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
