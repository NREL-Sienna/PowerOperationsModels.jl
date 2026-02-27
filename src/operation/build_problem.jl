function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    bus_reduction_map::Dict{Int64, Set{Int64}},
) where {T <: AbstractPowerModel}
    dc_bus_numbers = [
        PSY.get_number(b) for
        b in get_available_components(network_model, PSY.DCBus, system)
    ]
    make_system_expressions!(container, subnetworks, dc_bus_numbers, T, bus_reduction_map)
    return
end

function initialize_hvdc_system!(
    ::OptimizationContainer,
    network_model::NetworkModel{T},
    ::Nothing,
    system::PSY.System,
) where {T <: AbstractPowerModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    if !isempty(dc_buses)
        @warn "HVDC Network Model is set to 'Nothing' but DC Buses are present in the system. \
               Consider adding an HVDC Network Model or removing DC Buses from the system."
    end
    return
end

# Called `build_impl!(container, template, sys)` in PSI (lived in optimization_container.jl).
function build_problem!(
    container::OptimizationContainer,
    template::ProblemTemplate,
    sys::PSY.System,
)
    transmission = get_network_formulation(template)
    transmission_model = get_network_model(template)
    hvdc_model = get_hvdc_network_model(template)

    initialize_system_expressions!(
        container,
        get_network_model(template),
        transmission_model.subnetworks,
        sys,
        transmission_model.network_reduction.bus_reduction_map)

    initialize_hvdc_system!(
        container,
        transmission_model,
        hvdc_model,
        sys,
    )

    # Order is required
    for device_model in values(template.devices)
        @debug "Building Arguments for $(get_component_type(device_model)) with $(get_formulation(device_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(device_model))" begin
            if validate_available_devices(device_model, sys)
                construct_device!(
                    container,
                    sys,
                    ArgumentConstructStage(),
                    device_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Services" begin
        construct_services!(
            container,
            sys,
            ArgumentConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end

    for branch_model in values(template.branches)
        @debug "Building Arguments for $(get_component_type(branch_model)) with $(get_formulation(branch_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(branch_model))" begin
            if validate_available_devices(branch_model, sys)
                construct_device!(
                    container,
                    sys,
                    ArgumentConstructStage(),
                    branch_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end
    for device_model in values(template.devices)
        @debug "Building Model for $(get_component_type(device_model)) with $(get_formulation(device_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(device_model))" begin
            if validate_available_devices(device_model, sys)
                construct_device!(
                    container,
                    sys,
                    ModelConstructStage(),
                    device_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    # This function should be called after construct_device ModelConstructStage
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(transmission)" begin
        @debug "Building $(transmission) network formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        construct_network!(container, sys, transmission_model, template)
        construct_hvdc_network!(container, sys, transmission_model, hvdc_model, template)
        @debug "Problem size:" get_problem_size(container) _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
    end
    for branch_model in values(template.branches)
        @debug "Building Model for $(get_component_type(branch_model)) with $(get_formulation(branch_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(branch_model))" begin
            if validate_available_devices(branch_model, sys)
                construct_device!(
                    container,
                    sys,
                    ModelConstructStage(),
                    branch_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Services" begin
        construct_services!(
            container,
            sys,
            ModelConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Objective" begin
        @debug "Building Objective" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
        IOM.update_objective_function!(container)
    end
    @debug "Total operation count $(get_jump_model(container).operator_counter)" _group =
        LOG_GROUP_OPTIMIZATION_CONTAINER

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Power Flow Initialization" begin
        IOM.add_power_flow_data!(
            container,
            get_power_flow_evaluation(transmission_model),
            sys,
        )
    end
    IOM.check_optimization_container(container)
    return
end
