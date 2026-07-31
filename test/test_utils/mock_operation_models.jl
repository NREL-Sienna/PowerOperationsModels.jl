# NOTE: None of the models and function in this file are functional. All of these are used for testing purposes and do not represent valid examples either to develop custom
# models. Please refer to the documentation.

struct MockOperationProblem <: GenericPowerDecisionProblem end
struct MockEmulationProblem <: GenericPowerEmulationProblem end
struct EconomicDispatchProblem <: GenericPowerDecisionProblem end
struct UnitCommitmentProblem <: GenericPowerDecisionProblem end

function IOM.DecisionModel(
    ::Type{MockOperationProblem},
    ::Type{T},
    sys::PSY.System;
    name = nothing,
    kwargs...,
) where {T <: AbstractNetworkModel}
    settings = IOM.Settings(sys; kwargs...)
    available_resolutions = PSY.get_time_series_resolutions(sys)
    if length(available_resolutions) == 1
        IOM.set_resolution!(settings, first(available_resolutions))
    else
        error("System has multiple resolutions MockOperationProblem won't work")
    end
    return DecisionModel{MockOperationProblem}(
        PowerOperationsProblemTemplate(T),
        sys,
        settings,
        nothing;
        name = name,
    )
end

function make_mock_forecast(
    horizon::Dates.TimePeriod,
    resolution::Dates.TimePeriod,
    interval::Dates.TimePeriod,
    steps,
)
    init_time = DateTime("2024-01-01")
    timeseries_data = Dict{Dates.DateTime, Vector{Float64}}()
    horizon_count = horizon ÷ resolution
    for i in 1:steps
        forecast_timestamps = init_time + interval * i
        timeseries_data[forecast_timestamps] = rand(horizon_count)
    end
    return Deterministic(;
        name = "mock_forecast",
        data = timeseries_data,
        resolution = resolution,
    )
end

function make_mock_singletimeseries(horizon, resolution)
    init_time = DateTime("2024-01-01")
    horizon_count = horizon ÷ resolution
    tstamps = collect(range(init_time; length = horizon_count, step = resolution))
    timeseries_data = TimeArray(tstamps, rand(horizon_count))
    return SingleTimeSeries(; name = "mock_timeseries", data = timeseries_data)
end

function IOM.DecisionModel(::Type{MockOperationProblem}; name = nothing, kwargs...)
    sys = System(100.0)
    add_component!(sys, ACBus(nothing))
    l = PowerLoad(nothing)
    gen = ThermalStandard(nothing)
    set_bus!(l, get_component(Bus, sys, "init"))
    set_bus!(gen, get_component(Bus, sys, "init"))
    add_component!(sys, l)
    add_component!(sys, gen)
    forecast = make_mock_forecast(
        get(kwargs, :horizon, Hour(24)),
        get(kwargs, :resolution, Hour(1)),
        get(kwargs, :interval, Hour(1)),
        get(kwargs, :steps, 2),
    )
    add_time_series!(sys, l, forecast)
    settings = IOM.Settings(sys;
        horizon = get(kwargs, :horizon, Hour(24)),
        resolution = get(kwargs, :resolution, Hour(1)))
    return DecisionModel{MockOperationProblem}(
        PowerOperationsProblemTemplate(CopperPlateNetworkModel),
        sys,
        settings,
        nothing;
        name = name,
    )
end

function IOM.EmulationModel(::Type{MockEmulationProblem}; name = nothing, kwargs...)
    sys = System(100.0)
    add_component!(sys, ACBus(nothing))
    l = PowerLoad(nothing)
    gen = ThermalStandard(nothing)
    set_bus!(l, get_component(Bus, sys, "init"))
    set_bus!(gen, get_component(Bus, sys, "init"))
    add_component!(sys, l)
    add_component!(sys, gen)
    single_ts = make_mock_singletimeseries(
        get(kwargs, :horizon, Hour(24)),
        get(kwargs, :resolution, Hour(1)),
    )
    add_time_series!(sys, l, single_ts)

    settings = IOM.Settings(sys;
        horizon = get(kwargs, :resolution, Hour(1)),
        resolution = get(kwargs, :resolution, Hour(1)))
    return EmulationModel{MockEmulationProblem}(
        PowerOperationsProblemTemplate(CopperPlateNetworkModel),
        sys,
        settings,
        nothing;
        name = name,
    )
end

# Only used for testing
function mock_construct_device!(
    problem::IOM.DecisionModel{MockOperationProblem},
    model;
    built_for_recurrent_solves = false,
    add_event_model = false,
)
    if add_event_model
        sys = IOM.get_system(problem)
        device_type = IOM.get_component_type(model)
        event_device = first(PSY.get_components(device_type, sys))
        transition_data = PSY.FixedForcedOutage(; outage_status = 0.0)
        PSY.add_supplemental_attribute!(sys, event_device, transition_data)
        mock_event_key = EventKey(PSY.FixedForcedOutage, device_type)
        mock_event_model = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
        set_event_model!(model, mock_event_key, mock_event_model)
    end
    mock_construct_devices!(
        problem,
        (model,);
        built_for_recurrent_solves = built_for_recurrent_solves,
    )
    return
end

# Only used for testing. Unlike `mock_construct_device!`, this runs `ArgumentConstructStage`
# for every device model before any `ModelConstructStage`, matching how a real
# `build_problem!` sequences a template. Needed whenever two device models have a
# cross-reference (e.g. a turbine's constraint reads a reservoir's variable and
# vice versa): running each device's Argument+Model pair back to back, one device at a
# time, cannot satisfy that circular ordering.
function mock_construct_devices!(
    problem::IOM.DecisionModel{MockOperationProblem},
    models;
    built_for_recurrent_solves = false,
)
    for model in models
        set_device_model!(problem.template, model)
    end
    template = IOM.get_template(problem)
    IOM.finalize_template!(template, IOM.get_system(problem))
    IOM.validate_time_series!(problem)
    IOM.init_optimization_container!(
        IOM.get_optimization_container(problem),
        IOM.get_network_model(template),
        IOM.get_system(problem),
    )
    IOM.get_network_model(template).subnetworks =
        PNM.find_subnetworks(IOM.get_system(problem))
    # Mirror the real build (`build_problem!`): device `add_to_expression!` maps every
    # bus through `get_mapped_bus_number(network_reduction, ...)`, so the network model
    # must carry a reduction. The mock applies none, so use the identity reduction.
    mock_ybus = PNM.Ybus(IOM.get_system(problem))
    IOM.set_network_data!(
        IOM.get_network_model(template),
        POM.YbusNetworkData(
            mock_ybus,
            PNM.get_branch_catalog(mock_ybus),
        ),
    )
    IOM.get_optimization_container(problem).built_for_recurrent_solves =
        built_for_recurrent_solves
    POM.initialize_system_expressions!(
        IOM.get_optimization_container(problem),
        IOM.get_network_model(template),
        IOM.get_network_model(template).subnetworks,
        IOM.get_system(problem),
        Dict{Int64, Set{Int64}}(),
    )
    for model in models
        construct_device!(
            IOM.get_optimization_container(problem),
            IOM.get_system(problem),
            IOM.ArgumentConstructStage(),
            model,
            IOM.get_network_model(template),
        )
    end
    for model in models
        construct_device!(
            IOM.get_optimization_container(problem),
            IOM.get_system(problem),
            IOM.ModelConstructStage(),
            model,
            IOM.get_network_model(template),
        )
    end

    IOM.check_optimization_container(IOM.get_optimization_container(problem))

    JuMP.@objective(
        IOM.get_jump_model(problem),
        MOI.MIN_SENSE,
        IOM.get_objective_expression(
            IOM.get_optimization_container(problem).objective_function,
        )
    )
    return
end

function mock_construct_network!(problem::IOM.DecisionModel{MockOperationProblem}, model)
    IOM.set_network_model!(problem.template, model)
    IOM.construct_network!(
        IOM.get_optimization_container(problem),
        IOM.get_system(problem),
        model,
        problem.template.branches,
    )
    return
end

struct MockStagesStruct
    stages::Dict{Int, Int}
end

function Base.show(io::IO, struct_stages::MockStagesStruct)
    println(io, "mock problem")
    return
end

function setup_ic_model_container!(model::DecisionModel)
    # This function is only for testing purposes.
    if !IOM.isempty(model)
        POM.reset!(model)
    end

    IOM.init_optimization_container!(
        IOM.get_optimization_container(model),
        IOM.get_network_model(IOM.get_template(model)),
        IOM.get_system(model),
    )

    IOM.init_model_store_params!(model)

    @info "Make Initial Conditions Model"
    IOM.set_output_dir!(model, mktempdir(; cleanup = true))
    POM.build_initial_conditions!(model)
    POM.solve_and_write_initial_conditions!(model)
    return
end
