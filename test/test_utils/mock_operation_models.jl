# NOTE: None of the models and function in this file are functional. All of these are used for testing purposes and do not represent valid examples either to develop custom
# models. Please refer to the documentation.

struct MockOperationProblem <: POM.DefaultDecisionProblem end
struct MockEmulationProblem <: POM.DefaultEmulationProblem end

function POM.DecisionModel(
    ::Type{MockOperationProblem},
    ::Type{T},
    sys::PSY.System;
    name = nothing,
    kwargs...,
) where {T <: AbstractPowerModel}
    settings = POM.Settings(sys; kwargs...)
    available_resolutions = PSY.get_time_series_resolutions(sys)
    if length(available_resolutions) == 1
        POM.set_resolution!(settings, first(available_resolutions))
    else
        error("System has multiple resolutions MockOperationProblem won't work")
    end
    return DecisionModel{MockOperationProblem}(
        ProblemTemplate(T),
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

function POM.DecisionModel(::Type{MockOperationProblem}; name = nothing, kwargs...)
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
    settings = POM.Settings(sys;
        horizon = get(kwargs, :horizon, Hour(24)),
        resolution = get(kwargs, :resolution, Hour(1)))
    return DecisionModel{MockOperationProblem}(
        ProblemTemplate(CopperPlatePowerModel),
        sys,
        settings,
        nothing;
        name = name,
    )
end

function POM.EmulationModel(::Type{MockEmulationProblem}; name = nothing, kwargs...)
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

    settings = POM.Settings(sys;
        horizon = get(kwargs, :resolution, Hour(1)),
        resolution = get(kwargs, :resolution, Hour(1)))
    return EmulationModel{MockEmulationProblem}(
        ProblemTemplate(CopperPlatePowerModel),
        sys,
        settings,
        nothing;
        name = name,
    )
end

# Only used for testing
function mock_construct_device!(
    problem::POM.DecisionModel{MockOperationProblem},
    model;
    built_for_recurrent_solves = false,
    add_event_model = false,
)
    if add_event_model
        error(
            "Event models are not supported in InfrastructureOptimizationModels. Use PowerSimulations for event modeling.",
        )
    end
    set_device_model!(problem.template, model)
    template = POM.get_template(problem)
    POM.finalize_template!(template, POM.get_system(problem))
    POM.validate_time_series!(problem)
    POM.init_optimization_container!(
        POM.get_optimization_container(problem),
        POM.get_network_model(template),
        POM.get_system(problem),
    )
    POM.get_network_model(template).subnetworks =
        PNM.find_subnetworks(POM.get_system(problem))
    POM.get_optimization_container(problem).built_for_recurrent_solves =
        built_for_recurrent_solves
    POM.initialize_system_expressions!(
        POM.get_optimization_container(problem),
        POM.get_network_model(template),
        POM.get_network_model(template).subnetworks,
        POM.get_system(problem),
        Dict{Int64, Set{Int64}}(),
    )
    if POM.validate_available_devices(model, POM.get_system(problem))
        POM.construct_device!(
            POM.get_optimization_container(problem),
            POM.get_system(problem),
            POM.ArgumentConstructStage(),
            model,
            POM.get_network_model(template),
        )
        POM.construct_device!(
            POM.get_optimization_container(problem),
            POM.get_system(problem),
            POM.ModelConstructStage(),
            model,
            POM.get_network_model(template),
        )
    end

    POM.check_optimization_container(POM.get_optimization_container(problem))

    JuMP.@objective(
        POM.get_jump_model(problem),
        MOI.MIN_SENSE,
        POM.get_objective_expression(
            POM.get_optimization_container(problem).objective_function,
        )
    )
    return
end

function mock_construct_network!(problem::POM.DecisionModel{MockOperationProblem}, model)
    POM.set_network_model!(problem.template, model)
    POM.construct_network!(
        POM.get_optimization_container(problem),
        POM.get_system(problem),
        model,
        problem.template.branches,
    )
    return
end

function mock_uc_ed_simulation_problems(uc_horizon, ed_horizon)
    return SimulationModels([
        DecisionModel(MockOperationProblem; horizon = uc_horizon, name = "UC"),
        DecisionModel(
            MockOperationProblem;
            horizon = ed_horizon,
            resolution = Minute(5),
            name = "ED",
        ),
    ])
end

function create_simulation_build_test_problems(
    template_uc = get_template_standard_uc_simulation(),
    template_ed = get_template_nomin_ed_simulation(),
    sys_uc = PSB.build_system(PSITestSystems, "c_sys5_uc"),
    sys_ed = PSB.build_system(PSITestSystems, "c_sys5_ed"),
)
    return SimulationModels(;
        decision_models = [
            DecisionModel(template_uc, sys_uc; name = "UC", optimizer = HiGHS_optimizer),
            DecisionModel(template_ed, sys_ed; name = "ED", optimizer = HiGHS_optimizer),
        ],
    )
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
    if !POM.isempty(model)
        POM.reset!(model)
    end

    POM.init_optimization_container!(
        POM.get_optimization_container(model),
        POM.get_network_model(POM.get_template(model)),
        POM.get_system(model),
    )

    POM.init_model_store_params!(model)

    @info "Make Initial Conditions Model"
    POM.set_output_dir!(model, mktempdir(; cleanup = true))
    POM.build_initial_conditions!(model)
    POM.initialize!(model)
    return
end
