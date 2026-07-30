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
