function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    bus_reduction_map::Dict{Int64, Set{Int64}},
) where {T <: AbstractNetworkModel}
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
) where {T <: AbstractNetworkModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    if !isempty(dc_buses)
        @warn "HVDC Network Model is set to 'Nothing' but DC Buses are present in the system. \
               Consider adding an HVDC Network Model or removing DC Buses from the system."
    end
    return
end

_is_solver_sos_set(fs::Tuple) = _is_solver_sos_set(fs[2])
_is_solver_sos_set(::Type{<:JuMP.MOI.AbstractSet}) = false
_is_solver_sos_set(::Type{<:JuMP.MOI.SOS1}) = true
_is_solver_sos_set(::Type{<:JuMP.MOI.SOS2}) = true

function _validate_dual_sos_compatibility(container::OptimizationContainer)
    duals = get_duals(container)
    isempty(duals) && return
    jump_model = get_jump_model(container)
    if any(_is_solver_sos_set, JuMP.list_of_constraint_types(jump_model))
        dual_key_names = join(IOM.encode_key_as_string.(keys(duals)), ", ")
        throw(
            IS.ConflictingInputsError(
                "Duals were requested for [$dual_key_names] but the model contains " *
                "solver SOS1/SOS2 constraint(s). MILP dual " *
                "computation (JuMP.fix_discrete_variables) relaxes only binary/integer " *
                "variables, not SOS constraints, so the resulting dual values would be " *
                "NaN. Remove `duals = ...` from the affected DeviceModel/NetworkModel, " *
                "use a convex cost representation to avoid the solver-native SOS2 " *
                "piecewise-linear path, or configure a manual binary-based SOS2 " *
                "approximation (e.g. `ManualSOS2QuadConfig`) instead.",
            ),
        )
    end
    return
end

# Guards each construct_device! call site below: under a subsystem-partitioned
# network model, the same template's DeviceModels are reused across builds
# scoped to different subsystems, and a DeviceModel whose component type has no
# available components in the current subsystem/system must be skipped rather
# than constructed.
function validate_available_devices(
    model::DeviceModel{T, <:AbstractDeviceFormulation},
    system::PSY.System,
) where {T <: PSY.Device}
    devices = get_available_components(model, system)
    if isempty(devices)
        @debug "No available components of type $(T); skipping construction of its $(get_formulation(model)) DeviceModel" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        return false
    end
    return true
end

# Called `build_impl!(container, template, sys)` in PSI (lived in optimization_container.jl).
function build_problem!(
    container::OptimizationContainer,
    template::PowerOperationsProblemTemplate,
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
    # Voltage variables must exist before device ModelConstructStage so that
    # voltage-coupled devices (e.g. ShuntSusceptanceDispatch) can reference them.
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(transmission)" begin
        @debug "Building $(transmission) network voltage variables" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        construct_network!(
            container,
            sys,
            transmission_model,
            template,
            ArgumentConstructStage(),
        )
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

    # Balance/reference constraints close after device ModelConstructStage so that
    # device injection expressions are fully populated before the nodal balance.
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(transmission)" begin
        @debug "Building $(transmission) network formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        construct_network!(
            container,
            sys,
            transmission_model,
            template,
            ModelConstructStage(),
        )
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
        add_power_flow_data!(container, transmission_model, sys)
    end
    IOM.check_optimization_container(container)
    _validate_dual_sos_compatibility(container)
    return
end
