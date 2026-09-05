#################################################################################
# The runtime interface: the functions a simulation calls between solves.
#
# These are pure functions of values, so most of the file needs no system and no
# JuMP model. The two that read PowerSystems data (occurrence and duration) are
# exercised against an attribute carrying a real outage profile.
#################################################################################

@testset "Countdown arithmetic" begin
    # A new outage starts the clock; an outage already running loses a step; an
    # available device stays available.
    @test advance_countdown(0.0, true, 3) == 3.0
    @test advance_countdown(3.0, false, 0) == 2.0
    @test advance_countdown(1.0, false, 0) == 0.0
    @test advance_countdown(0.0, false, 0) == 0.0
    # An outage firing on an already-outaged device does not extend it.
    @test advance_countdown(2.0, true, 5) == 1.0

    # Projection into a decision model's horizon.
    @test countdown_trajectory(3, 5) == [3.0, 2.0, 1.0, 0.0, 0.0]
    @test countdown_trajectory(0, 3) == [0.0, 0.0, 0.0]
    @test availability_trajectory(3, 5) == [0.0, 0.0, 0.0, 1.0, 1.0]

    # Availability is derived, never stored, so the two cannot disagree.
    @test availability_from_countdown(0.0) == 1.0
    @test availability_from_countdown(0.5) == 0.0
    @test availability_from_countdown(4.0) == 0.0
end

@testset "Countdown steps reject partial steps" begin
    @test countdown_steps(Hour(4), Hour(1)) == 4
    @test countdown_steps(Hour(1), Minute(15)) == 4
    @test countdown_steps(Minute(90), Minute(30)) == 3
    # A duration that does not divide the resolution rounds up, loudly: an outage
    # cannot end partway through a step, and ending it early would understate it.
    @test countdown_steps(Minute(90), Hour(1)) == 2
    @test_logs (:warn, r"not a whole number") countdown_steps(Minute(90), Hour(1))
end

@testset "Offsets cancel the injection only while the device is out" begin
    @test outage_power_offset(2.0, 1.5) == -1.5
    @test outage_power_offset(0.0, 1.5) == 0.0
    # Sign is carried by the injection, so the same function serves a withdrawal.
    @test outage_power_offset(1.0, -0.8) == 0.8
end

@testset "Fixed forced outage occurrence and duration come from the profile" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    # Available for two steps, out for three, then available again.
    profile = [0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
    outage = attach_fixed_forced_outage!(sys, thermal; outage_profile = profile)
    em = fixed_outage_event()
    resolution = first(PSY.get_time_series_resolutions(sys))
    t0 = PSY.get_forecast_initial_timestamp(sys)

    # The value read is the step *after* current_time: at t0 the next step is still
    # available, at t0 + one step the outage begins.
    @test !outage_occurred(outage, em, t0)
    @test outage_occurred(outage, em, t0 + resolution)
    # Mid-outage the profile still reads as out.
    @test outage_occurred(outage, em, t0 + 2 * resolution)
    # Once the profile returns to available, so does the answer.
    @test !outage_occurred(outage, em, t0 + 5 * resolution)

    # Three out steps starting at t0 + resolution.
    @test time_to_recover(outage, em, t0 + resolution) == 3 * resolution
    @test countdown_steps(time_to_recover(outage, em, t0 + resolution), resolution) == 3
    # Reading from inside the outage counts only what is left of it.
    @test time_to_recover(outage, em, t0 + 2 * resolution) == 2 * resolution
end

@testset "An outage profile that never recovers is out for the rest of the series" begin
    # The series is the only evidence there is, so the duration is truncated to what it
    # shows rather than extrapolated. The countdown itself survives in the runtime's
    # state, so a longer outage continues into the next projection.
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    horizon =
        Int(PSY.get_forecast_horizon(sys) / first(PSY.get_time_series_resolutions(sys)))
    profile = zeros(horizon)
    profile[2:end] .= 1.0  # out from the second step to the end
    outage = attach_fixed_forced_outage!(sys, thermal; outage_profile = profile)
    em = fixed_outage_event()
    resolution = first(PSY.get_time_series_resolutions(sys))
    t0 = PSY.get_forecast_initial_timestamp(sys)

    # Reading at t0: values[1] is now, values[2:end] are all out -> horizon - 1 steps.
    @test outage_occurred(outage, em, t0)
    @test time_to_recover(outage, em, t0) == (horizon - 1) * resolution
    # One step from the end of the series there is a single out step left.
    @test time_to_recover(outage, em, t0 + (horizon - 2) * resolution) == resolution
end

@testset "Geometric outage occurrence is a Bernoulli draw on the rng" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    t0 = PSY.get_forecast_initial_timestamp(sys)
    em = EventModel(PSY.GeometricDistributionForcedOutage, ContinuousCondition())

    never = PSY.GeometricDistributionForcedOutage(;
        mean_time_to_recovery = 120.0,
        outage_transition_probability = 0.0,
    )
    always = PSY.GeometricDistributionForcedOutage(;
        mean_time_to_recovery = 120.0,
        outage_transition_probability = 1.0,
    )
    PSY.add_supplemental_attribute!(sys, thermal, never)
    rng = Random.MersenneTwister(1234)
    @test !any(outage_occurred(never, em, t0; rng = rng) for _ in 1:50)
    @test all(outage_occurred(always, em, t0; rng = rng) for _ in 1:50)
    # The draw has to come from the passed rng, or a simulation cannot reproduce itself.
    coin = PSY.GeometricDistributionForcedOutage(;
        mean_time_to_recovery = 120.0,
        outage_transition_probability = 0.5,
    )
    draws(seed) = [
        outage_occurred(coin, em, t0; rng = Random.MersenneTwister(seed)) for _ in 1:20
    ]
    @test draws(1) == draws(1)
    @test draws(1) != draws(2)
    # A stochastic event with no rng is an error, not a silent default.
    @test_throws ErrorException outage_occurred(coin, em, t0)

    # `mean_time_to_recovery` is documented in minutes by PowerSystems and read as hours
    # by PSI; the units are the caller's to state.
    @test time_to_recover(coin, em, t0) == Minute(120)
    @test time_to_recover(coin, em, t0; mttr_units = Hour) == Hour(120)
end

@testset "A runtime step reports countdown, availability and offsets together" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    profile = [0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    outage = attach_fixed_forced_outage!(sys, thermal; outage_profile = profile)
    em = fixed_outage_event()
    resolution = first(PSY.get_time_series_resolutions(sys))
    t0 = PSY.get_forecast_initial_timestamp(sys)

    # Step where the outage fires: two steps of downtime, device unavailable, an
    # injection of 1.2 cancelled out of the balance.
    now = event_step_values(
        outage,
        em,
        t0,
        0.0;
        resolution = resolution,
        active_power_injection = 1.2,
    )
    @test now.occurred
    @test now.countdown == 2.0
    @test now.availability == 0.0
    @test now.active_power_offset == -1.2
    @test now.reactive_power_offset == 0.0

    # The following step decrements without re-reading the profile, and the last one
    # returns the device to service.
    next = event_step_values(outage, em, t0 + resolution, now.countdown;
        resolution = resolution)
    @test !next.occurred
    @test next.countdown == 1.0
    @test next.availability == 0.0
    last = event_step_values(outage, em, t0 + 2 * resolution, next.countdown;
        resolution = resolution)
    @test last.countdown == 0.0
    # A condition that does not hold blocks a new outage but never freezes a running one:
    # the countdown decays either way, so a runtime calls this every step.
    blocked = event_step_values(
        outage,
        em,
        t0,
        0.0;
        resolution = resolution,
        may_start = false,
    )
    @test !blocked.occurred
    @test blocked.countdown == 0.0
    still_decaying = event_step_values(
        outage,
        em,
        t0,
        3.0;
        resolution = resolution,
        may_start = false,
    )
    @test still_decaying.countdown == 2.0
    @test last.availability == 1.0
    @test last.active_power_offset == 0.0
end

@testset "Event parameter keys are ordered and restricted to what was built" begin
    # A thermal unit carries no offsets; a load under an AC network carries both. A
    # runtime asks rather than assuming, and writes in the order returned: the
    # countdown carries the outage's memory, availability is derived from it.
    container, _ = mock_event_container(
        DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment),
        DCPNetworkModel,
        "c_sys5_uc",
    )
    @test event_parameter_keys(container, PSY.ThermalStandard) == [
        IOM.ParameterKey(AvailableStatusChangeCountdownParameter, PSY.ThermalStandard),
        IOM.ParameterKey(AvailableStatusParameter, PSY.ThermalStandard),
    ]

    load_container, _ = mock_event_container(
        DeviceModel(PSY.PowerLoad, StaticPowerLoad),
        ACPNetworkModel,
        "c_sys5_uc",
    )
    @test event_parameter_keys(load_container, PSY.PowerLoad) == [
        IOM.ParameterKey(AvailableStatusChangeCountdownParameter, PSY.PowerLoad),
        IOM.ParameterKey(ActivePowerOffsetParameter, PSY.PowerLoad),
        IOM.ParameterKey(ReactivePowerOffsetParameter, PSY.PowerLoad),
        IOM.ParameterKey(AvailableStatusParameter, PSY.PowerLoad),
    ]
end

@testset "Conditions declare only the inputs they need" begin
    t = Dates.DateTime("2024-01-01T05:00:00")
    # Nothing carries what it does not use: the clock-only conditions declare nothing.
    @test required_inputs(ContinuousCondition()) == ()
    @test required_inputs(PresetTimeCondition([t])) == ()

    svc = StateVariableValueCondition(OnVariable(), PSY.ThermalStandard, "unit", 0.0)
    input = only(required_inputs(svc))
    @test input isa StateValueInput
    @test POM.get_variable_type(input) isa OnVariable
    @test POM.get_device_type(input) == PSY.ThermalStandard
    @test POM.get_device_name(input) == "unit"

    # The escape hatch is the only thing that asks for the runtime's state, and it
    # asks explicitly.
    @test only(required_inputs(DiscreteEventCondition(s -> true))) isa RuntimeStateInput
end

@testset "Conditions evaluate on the clock and their own resolved inputs" begin
    t = Dates.DateTime("2024-01-01T05:00:00")
    @test is_triggered(ContinuousCondition(), t)
    @test is_triggered(PresetTimeCondition([t]), t)
    @test !is_triggered(PresetTimeCondition([t + Hour(1)]), t)

    svc = StateVariableValueCondition(OnVariable(), PSY.ThermalStandard, "unit", 0.0)
    @test is_triggered(svc, t, (0.0,))
    @test !is_triggered(svc, t, (1.0,))

    # The runtime state reaches user code untouched.
    dec = DiscreteEventCondition(state -> state == :outaged)
    @test is_triggered(dec, t, (:outaged,))
    @test !is_triggered(dec, t, (:nominal,))
end

@testset "A runtime resolves declared inputs generically" begin
    # What a runtime's loop looks like: one `resolve` per input type, no per-condition
    # branching, and POM never sees the state object except through the escape hatch.
    t = Dates.DateTime("2024-01-01T05:00:00")
    mock_state = Dict(("unit", :on) => 0.0)
    resolve(i::StateValueInput, state) = state[(POM.get_device_name(i), :on)]
    resolve(::RuntimeStateInput, state) = state
    fires(condition, state) = is_triggered(
        condition,
        t,
        map(i -> resolve(i, state), required_inputs(condition)),
    )

    @test fires(ContinuousCondition(), mock_state)
    @test fires(
        StateVariableValueCondition(OnVariable(), PSY.ThermalStandard, "unit", 0.0),
        mock_state,
    )
    @test !fires(
        StateVariableValueCondition(OnVariable(), PSY.ThermalStandard, "unit", 1.0),
        mock_state,
    )
    @test fires(DiscreteEventCondition(s -> haskey(s, ("unit", :on))), mock_state)
end
