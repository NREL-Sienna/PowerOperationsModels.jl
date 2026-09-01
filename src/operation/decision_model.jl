# Template-first constructors default the problem type to `DefaultPowerDecisionProblem`.
# IOM only ships the `DecisionModel{M}` / `DecisionModel(::Type{M}, ...)` variants
# (`M` is the domain-neutral `AbstractOptimizationProblem`); the default problem
# type is a POM concept, so the defaulting constructors live here.
function DecisionModel(
    template::IOM.AbstractProblemTemplate,
    sys::IS.InfrastructureSystemsContainer,
    jump_model::Union{Nothing, JuMP.Model} = nothing;
    kwargs...,
)
    return DecisionModel{DefaultPowerDecisionProblem}(template, sys, jump_model; kwargs...)
end

# Generic (template-driven) decision problems require an AbstractProblemTemplate
# subtype, so the bare-system constructor (no template) is an error.
function DecisionModel{M}(
    sys::IS.InfrastructureSystemsContainer,
    jump_model::Union{Nothing, JuMP.Model} = nothing;
    kwargs...,
) where {M <: GenericPowerDecisionProblem}
    throw(
        IS.ArgumentError(
            "GenericPowerDecisionProblem subtypes require a template. Use DecisionModel subtyping instead.",
        ),
    )
end

function build_pre_step!(model::DecisionModel{<:AbstractPowerDecisionProblem})
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Build pre-step" begin
        validate_template(model)
        if !isempty(model)
            @info "OptimizationProblem status not ModelBuildStatus.EMPTY. Resetting"
            reset!(model)
        end
        @info "Initializing Optimization Container For a DecisionModel"
        init_optimization_container!(
            get_optimization_container(model),
            get_network_model(get_template(model)),
            get_system(model),
        )
        @info "Initializing ModelStoreParams"
        IOM.init_model_store_params!(model)
        set_status!(model, ModelBuildStatus.IN_PROGRESS)
    end
    return
end

# Called `build_impl!(model)` in PSI (lived in decision_model.jl).
function build_model!(model::DecisionModel{<:AbstractPowerDecisionProblem})
    build_pre_step!(model)
    @info "Instantiating Network Model"
    IOM.instantiate_network_model!(model)
    handle_initial_conditions!(model)
    build_problem!(
        get_optimization_container(model),
        get_template(model),
        get_system(model),
    )
    IOM.serialize_metadata!(get_optimization_container(model), IOM.get_output_dir(model))
    log_values(get_settings(model))
    return
end

"""
Build the Decision Model based on the specified AbstractPowerDecisionProblem.

# Arguments

  - `model::DecisionModel{<:AbstractPowerDecisionProblem}`: DecisionModel object
  - `output_dir::String`: Output directory for outputs
  - `recorders::Vector{Symbol} = []`: recorder names to register
  - `console_level = Logging.Error`:
  - `file_level = Logging.Info`:
  - `disable_timer_outputs = false` : Enable/Disable timing outputs
  - `store_system_in_results::Bool = true`: If true, stores the system as JSON in the results HDF5 file.
"""
function build!(
    model::DecisionModel{<:AbstractPowerDecisionProblem};
    output_dir::String,
    recorders = [],
    console_level = Logging.Error,
    file_level = Logging.Info,
    disable_timer_outputs = false,
    store_system_in_results = true,
)
    mkpath(output_dir)
    IOM.set_output_dir!(model, output_dir)
    IOM.set_console_level!(model, console_level)
    IOM.set_file_level!(model, file_level)
    TimerOutputs.reset_timer!(BUILD_PROBLEMS_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(BUILD_PROBLEMS_TIMER)
    file_mode = "w"
    IOM.add_recorders!(model, recorders)
    IOM.register_recorders!(model, file_mode)
    logger = IS.configure_logging(get_internal(model), IOM.PROBLEM_LOG_FILENAME, file_mode)
    if store_system_in_results
        @warn "store_system_in_results is set to true. This will do nothing unless a Simulation is being built."
    end
    try
        Logging.with_logger(logger) do
            try
                TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Problem $(get_name(model))" begin
                    build_model!(model)
                end
                set_status!(model, ModelBuildStatus.BUILT)
                @info "\n$(BUILD_PROBLEMS_TIMER)\n"
            catch e
                set_status!(model, ModelBuildStatus.FAILED)
                bt = catch_backtrace()
                @error "DecisionModel Build Failed" exception = e, bt
            end
        end
    finally
        IOM.unregister_recorders!(model)
        close(logger)
    end
    return IOM.get_status(model)
end

function reset!(model::DecisionModel{<:GenericPowerDecisionProblem})
    was_built_for_recurrent_solves = built_for_recurrent_solves(model)
    if was_built_for_recurrent_solves
        IOM.set_execution_count!(model, 0)
    end
    sys = get_system(model)
    ts_type = IOM.get_deterministic_time_series_type(sys)
    IOM.set_container!(
        get_internal(model),
        OptimizationContainer(
            get_system(model),
            get_settings(model),
            nothing,
            ts_type,
        ),
    )
    get_optimization_container(model).built_for_recurrent_solves =
        was_built_for_recurrent_solves
    internal = get_internal(model)
    IOM.set_initial_conditions_model_container!(internal, nothing)
    IOM.empty_time_series_cache!(model)
    empty!(get_store(model))
    set_status!(model, ModelBuildStatus.EMPTY)
    return
end

"""
Default solve method for models that conform to the requirements of
DecisionModel{<: AbstractPowerDecisionProblem}.

This will call `build!` on the model if it is not already built. It will forward all
keyword arguments to that function.

# Arguments

  - `model::IOM.AbstractOptimizationModel = model`: operation model
  - `export_problem_outputs::Bool = false`: If true, export OptimizationProblemOutputs DataFrames to CSV files.
  - `console_level = Logging.Error`:
  - `file_level = Logging.Info`:
  - `disable_timer_outputs = false` : Enable/Disable timing outputs
  - `export_optimization_problem::Bool = true`: If true, serialize the model to a file to allow re-execution later.
  - `store_system_in_results::Bool = true`: If true, stores the system as JSON in the results HDF5 file.

# Examples

```julia
outputs = solve!(OpModel)
outputs = solve!(OpModel, export_problem_outputs = true)
```
"""
function solve!(
    model::DecisionModel{<:AbstractPowerDecisionProblem};
    export_problem_outputs = false,
    console_level = Logging.Error,
    file_level = Logging.Info,
    disable_timer_outputs = false,
    export_optimization_problem = true,
    store_system_in_results = true,
    kwargs...,
)
    if store_system_in_results
        @warn "store_system_in_results is set to true. This will do nothing unless a Simulation is being built."
    end
    build_if_not_already_built!(
        model;
        console_level = console_level,
        file_level = file_level,
        disable_timer_outputs = disable_timer_outputs,
        kwargs...,
    )
    IOM.set_console_level!(model, console_level)
    IOM.set_file_level!(model, file_level)
    TimerOutputs.reset_timer!(RUN_OPERATION_MODEL_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(RUN_OPERATION_MODEL_TIMER)
    file_mode = "a"
    IOM.register_recorders!(model, file_mode)
    logger = IS.configure_logging(
        get_internal(model),
        IOM.PROBLEM_LOG_FILENAME,
        file_mode,
    )
    optimizer = get(kwargs, :optimizer, nothing)
    try
        Logging.with_logger(logger) do
            try
                IOM.initialize_storage!(
                    get_store(model),
                    get_optimization_container(model),
                    IOM.get_store_params(model),
                )
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Solve" begin
                    IOM._pre_solve_model_checks(model, optimizer)
                    IOM.solve_model!(model)
                    current_time = get_initial_time(model)
                    write_outputs!(get_store(model), model, current_time, current_time)
                    IOM.write_optimizer_stats!(
                        get_store(model),
                        get_optimizer_stats(model),
                        current_time,
                    )
                end
                if export_optimization_problem
                    TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Serialize" begin
                        serialize_optimization_model(model)
                    end
                end
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Outputs processing" begin
                    outputs = OptimizationProblemOutputs(model)
                    serialize_outputs(outputs, IOM.get_output_dir(model))
                    export_problem_outputs && export_outputs(outputs)
                    if IOM.get_system_to_file(IOM.get_settings(model))
                        sys = IOM.get_system(model)
                        sys_dir = joinpath(
                            IOM.get_output_dir(model),
                            IOM.make_system_dirname(sys),
                        )
                        # Re-solving into an existing directory must not rewrite the system and its time series.
                        # `power_units = :component_base` is what PSY stores internally, so the
                        # write needs no unit conversion and no round-trip ledger — a model's
                        # system carries one only when it was built from a document.
                        !ispath(sys_dir) &&
                            PSY.to_file(sys, sys_dir; power_units = :component_base)
                    end
                end
                @info "\n$(RUN_OPERATION_MODEL_TIMER)\n"
            catch e
                @error "Decision Problem solve failed" exception = (e, catch_backtrace())
                IOM.set_run_status!(model, RunStatus.FAILED)
            end
        end
    finally
        IOM.wait_for_serialization!(model)
        IOM.unregister_recorders!(model)
        close(logger)
    end

    return IOM.get_run_status(model)
end

function handle_initial_conditions!(model::DecisionModel{<:AbstractPowerDecisionProblem})
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Model Initialization" begin
        if isempty(get_template(model))
            return
        end
        settings = get_settings(model)
        initialize_model = get_initialize_model(settings)
        deserialize_initial_conditions = get_deserialize_initial_conditions(settings)
        serialized_initial_conditions_file = IOM.get_initial_conditions_file(model)
        custom_init_file = get_initialization_file(settings)

        if !initialize_model && deserialize_initial_conditions
            throw(
                IS.ConflictingInputsError(
                    "!initialize_model && deserialize_initial_conditions",
                ),
            )
        elseif !initialize_model && !isempty(custom_init_file)
            throw(IS.ConflictingInputsError("!initialize_model && initialization_file"))
        end

        if !initialize_model
            @info "Skip build of initial conditions"
            return
        end

        if !isempty(custom_init_file)
            if !isfile(custom_init_file)
                error("initialization_file = $custom_init_file does not exist")
            end
            if abspath(custom_init_file) != abspath(serialized_initial_conditions_file)
                cp(custom_init_file, serialized_initial_conditions_file; force = true)
            end
        end

        if deserialize_initial_conditions && isfile(serialized_initial_conditions_file)
            IOM.set_initial_conditions_data!(
                get_optimization_container(model),
                Serialization.deserialize(serialized_initial_conditions_file),
            )
            @info "Deserialized initial_conditions_data"
        else
            @info "Make Initial Conditions Model"
            build_initial_conditions!(model)
            solve_and_write_initial_conditions!(model)
        end
        IOM.set_initial_conditions_model_container!(
            get_internal(model),
            nothing,
        )
    end
    return
end

function build_if_not_already_built!(model::IOM.AbstractOptimizationModel; kwargs...)
    status = IOM.get_status(model)
    if status == ModelBuildStatus.EMPTY
        if !haskey(kwargs, :output_dir)
            error(
                "'output_dir' must be provided as a kwarg if the model build status is $status",
            )
        else
            new_kwargs = Dict(k => v for (k, v) in kwargs if k != :optimizer)
            status = build!(model; new_kwargs...)
        end
    end
    if status != ModelBuildStatus.BUILT
        error("build! of the $(typeof(model)) $(get_name(model)) failed: $status")
    end
    return
end

function validate_template(::DecisionModel{M}) where {M <: AbstractPowerDecisionProblem}
    error("validate_template is not implemented for DecisionModel{$M}")
end

function validate_template(model::DecisionModel{<:GenericPowerDecisionProblem})
    validate_template_impl!(model)
    return
end

# IOM declares `validate_time_series!` as a pure extension-point stub (no methods);
# POM provides the concrete check for its template-driven problem types. It reconciles
# the model's resolution/interval/horizon settings against the forecast data in the
# system and errors when the system has no forecast data.
function validate_time_series!(model::DecisionModel{<:GenericPowerDecisionProblem})
    sys = get_system(model)
    settings = get_settings(model)
    _reconcile_resolution!(settings, sys)

    model_interval = IOM.get_interval(settings)
    available_intervals = IOM.get_forecast_intervals(sys)
    if model_interval == IOM.UNSET_INTERVAL && length(available_intervals) > 1
        throw(
            IS.ConflictingInputsError(
                "The system contains multiple forecast intervals $(available_intervals). " *
                "The `interval` keyword argument must be provided to the DecisionModel constructor " *
                "to select which interval to use.",
            ),
        )
    elseif model_interval != IOM.UNSET_INTERVAL && !isempty(available_intervals)
        if model_interval ∉ available_intervals
            throw(
                IS.ConflictingInputsError(
                    "Interval $(Dates.canonicalize(model_interval)) is not available in the system data. " *
                    "Available forecast intervals: $(available_intervals)",
                ),
            )
        end
    end
    if get_horizon(settings) == IOM.UNSET_HORIZON
        IOM.set_horizon!(
            settings,
            IOM.get_forecast_horizon(sys; interval = IOM._to_is_interval(model_interval)),
        )
    end

    counts = IOM.get_time_series_counts(sys)
    if counts.forecast_count < 1
        error(
            "The system does not contain forecast data. A DecisionModel can't be built.",
        )
    end
    return
end

function _make_device_cache(
    filter_function::Function,
    devices::IS.FlattenIteratorWrapper{T},
    check_components::Bool,
    sys::PSY.System,
) where {T <: PSY.Device}
    device_cache = sizehint!(Vector{T}(), length(devices))
    for device in devices
        if PSY.get_available(device) && filter_function(device)
            check_components && PSY.check_component(sys, device)
            push!(device_cache, device)
        end
    end
    return device_cache
end

function _make_device_cache(
    ::Nothing,
    devices::IS.FlattenIteratorWrapper{T},
    check_components::Bool,
    sys::PSY.System,
) where {T <: PSY.Device}
    device_cache = sizehint!(Vector{T}(), length(devices))
    for device in devices
        if PSY.get_available(device)
            check_components && PSY.check_component(sys, device)
            push!(device_cache, device)
        end
    end
    return device_cache
end

function make_device_cache!(
    model::DeviceModel{T, <:AbstractDeviceFormulation},
    system::PSY.System,
    check_components::Bool,
) where {T <: PSY.Device}
    subsystem = get_subsystem(model)
    !PSY.has_components(system, T) && return false
    devices = PSY.get_components(T, system; subsystem_name = subsystem)
    filt_func = get_attribute(model, "filter_function")
    model.device_cache =
        _make_device_cache(filt_func, devices, check_components, system)
    return
end
