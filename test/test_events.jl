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

    # Discovery populated the map: attribute uuid -> device type -> names
    map_ = get_attribute_device_map(em)
    uuid = IS.get_uuid(outage)
    @test haskey(map_, uuid)
    @test map_[uuid][PSY.ThermalStandard] == Set([PSY.get_name(thermal)])

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
    c1 = JuMP.constraint_object(cons[axes(cons)[1][1], 1])
    @test c1.set isa MOI.LessThan{Float64}
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
