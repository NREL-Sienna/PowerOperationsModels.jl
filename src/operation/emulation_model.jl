# FIXME untested. Moved to accommodate a few methods dispatching on EmulationModelStore,
# but not run in the tests and not yet refactored for IOM-POM split.
function build_pre_step!(model::EmulationModel)
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Build pre-step" begin
        IOM.validate_template(model)
        if !isempty(model)
            @info "EmulationProblem status not ModelBuildStatus.EMPTY. Resetting"
            reset!(model)
        end
        container = get_optimization_container(model)
        container.built_for_recurrent_solves = true

        @info "Initializing Optimization Container For an EmulationModel"
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

# Called `build_impl!(model)` in PSI (lived in emulation_model.jl).
function build_model!(model::EmulationModel{<:EmulationProblem})
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
Implementation of build for any EmulationProblem
"""
function build!(
    model::EmulationModel{<:EmulationProblem};
    executions = 1,
    output_dir::String,
    recorders = [],
    console_level = Logging.Error,
    file_level = Logging.Info,
    disable_timer_outputs = false,
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
    logger = IS.configure_logging(
        get_internal(model),
        IOM.PROBLEM_LOG_FILENAME,
        file_mode,
    )
    try
        Logging.with_logger(logger) do
            try
                IOM.set_executions!(model, executions)
                TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Problem $(get_name(model))" begin
                    build_model!(model)
                end
                set_status!(model, ModelBuildStatus.BUILT)
                @info "\n$(BUILD_PROBLEMS_TIMER)\n"
            catch e
                set_status!(model, ModelBuildStatus.FAILED)
                bt = catch_backtrace()
                @error "EmulationModel Build Failed" exception = e, bt
            end
        end
    finally
        IOM.unregister_recorders!(model)
        close(logger)
    end
    return IOM.get_status(model)
end

function reset!(model::EmulationModel{<:EmulationProblem})
    if built_for_recurrent_solves(model)
        IOM.set_execution_count!(model, 0)
    end
    IOM.set_container!(
        get_internal(model),
        OptimizationContainer(
            get_system(model),
            get_settings(model),
            nothing,
            PSY.SingleTimeSeries,
        ),
    )
    IOM.set_initial_conditions_model_container!(get_internal(model), nothing)
    IOM.empty_time_series_cache!(model)
    empty!(get_store(model))
    set_status!(model, ModelBuildStatus.EMPTY)
    return
end

function _progress_meter_enabled()
    return isa(stderr, Base.TTY) &&
           (get(ENV, "CI", nothing) != "true") &&
           (get(ENV, "RUNNING_SIENNA_TESTS", nothing) != "true")
end

# Called `run_impl!` in PSI (lived in emulation_model.jl).
function execute_emulation!(
    model::EmulationModel;
    optimizer = nothing,
    enable_progress_bar = _progress_meter_enabled(),
    kwargs...,
)
    IOM._pre_solve_model_checks(model, optimizer)
    internal = get_internal(model)
    executions = IOM.get_executions(internal)
    # Temporary check. Needs better way to manage re-runs of the same model
    if internal.execution_count > 0
        error("Call build! again")
    end
    prog_bar = ProgressMeter.Progress(executions; enabled = enable_progress_bar)
    initial_time = get_initial_time(model)
    for execution in 1:executions
        TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Run execution" begin
            # NOTE: PSI's run_impl! calls update_model!(model) here to update parameters
            # and initial conditions between executions. That logic lives in IOM's
            # emulation_model.jl and is invoked by PSI during simulation. Standalone
            # emulation in POM does not update between steps.
            IOM.solve_model!(model)
            current_time = initial_time + (execution - 1) * get_resolution(model)
            write_outputs!(get_store(model), model, execution, current_time)
            IOM.write_optimizer_stats!(
                get_store(model),
                get_optimizer_stats(model),
                execution,
            )
            IOM.advance_execution_count!(model)
            ProgressMeter.update!(
                prog_bar,
                IOM.get_execution_count(model);
                showvalues = [(:Execution, execution)],
            )
        end
    end
    return
end

"""
Default run method for problems that conform to the requirements of
EmulationModel{<: EmulationProblem}

This will call `build!` on the model if it is not already built. It will forward all
keyword arguments to that function.

# Arguments

  - `model::EmulationModel = model`: Emulation model
  - `optimizer::MOI.OptimizerWithAttributes`: The optimizer that is used to solve the model
  - `executions::Int`: Number of executions for the emulator run
  - `export_problem_outputs::Bool`: If true, export OptimizationProblemOutputs DataFrames to CSV files.
  - `output_dir::String`: Required if the model is not already built, otherwise ignored
  - `enable_progress_bar::Bool`: Enables/Disable progress bar printing
  - `export_optimization_model::Bool`: If true, serialize the model to a file to allow re-execution later.

# Examples

```julia
status = run!(model; optimizer = HiGHS.Optimizer, executions = 10)
status = run!(model; output_dir = ./model_output, optimizer = HiGHS.Optimizer, executions = 10)
```
"""
function run!(
    model::EmulationModel{<:EmulationProblem};
    export_problem_outputs = false,
    console_level = Logging.Error,
    file_level = Logging.Info,
    disable_timer_outputs = false,
    export_optimization_model = true,
    enable_progress_bar = _progress_meter_enabled(),
    kwargs...,
)
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
    try
        Logging.with_logger(logger) do
            try
                IOM.initialize_storage!(
                    get_store(model),
                    get_optimization_container(model),
                    IOM.get_store_params(model),
                )
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Run" begin
                    execute_emulation!(
                        model;
                        enable_progress_bar = enable_progress_bar,
                        kwargs...,
                    )
                    IOM.set_run_status!(model, RunStatus.SUCCESSFULLY_FINALIZED)
                end
                if export_optimization_model
                    TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Serialize" begin
                        optimizer = get(kwargs, :optimizer, nothing)
                        serialize_problem(model; optimizer = optimizer)
                        serialize_optimization_model(model)
                    end
                end
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Outputs processing" begin
                    outputs = OptimizationProblemOutputs(model)
                    serialize_outputs(outputs, IOM.get_output_dir(model))
                    export_problem_outputs && export_outputs(outputs)
                end
                @info "\n$(RUN_OPERATION_MODEL_TIMER)\n"
            catch e
                @error "Emulation Problem Run failed" exception = (e, catch_backtrace())
                IOM.set_run_status!(model, RunStatus.FAILED)
            end
        end
    finally
        IOM.unregister_recorders!(model)
        close(logger)
    end
    return IOM.get_run_status(model)
end

function handle_initial_conditions!(model::EmulationModel{<:EmulationProblem})
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
