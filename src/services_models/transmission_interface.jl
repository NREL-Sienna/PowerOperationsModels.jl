#! format: off
get_variable_binary(::Type{<:VariableType}, ::Type{PSY.TransmissionInterface}, ::Type{ConstantMaxInterfaceFlow}) = false
get_variable_lower_bound(::Type{InterfaceFlowSlackUp}, ::PSY.TransmissionInterface, ::Type{ConstantMaxInterfaceFlow}) = 0.0
get_variable_lower_bound(::Type{InterfaceFlowSlackDown}, ::PSY.TransmissionInterface, ::Type{ConstantMaxInterfaceFlow}) = 0.0

get_variable_multiplier(::Type{InterfaceFlowSlackUp}, ::Type{PSY.TransmissionInterface}, ::Type{ConstantMaxInterfaceFlow}) = 1.0
get_variable_multiplier(::Type{InterfaceFlowSlackDown}, ::Type{PSY.TransmissionInterface}, ::Type{ConstantMaxInterfaceFlow}) = -1.0

get_variable_multiplier(::Type{InterfaceFlowSlackUp}, ::Type{PSY.TransmissionInterface}, ::Type{VariableMaxInterfaceFlow}) = 1.0
get_variable_multiplier(::Type{InterfaceFlowSlackDown}, ::Type{PSY.TransmissionInterface}, ::Type{VariableMaxInterfaceFlow}) = -1.0

get_multiplier_value(::Type{MinInterfaceFlowLimitParameter}, d::PSY.TransmissionInterface, ::Type{VariableMaxInterfaceFlow}) = PSY.get_min_active_power_flow_limit(d, PSY.SU)
get_multiplier_value(::Type{MaxInterfaceFlowLimitParameter}, d::PSY.TransmissionInterface, ::Type{VariableMaxInterfaceFlow}) = PSY.get_max_active_power_flow_limit(d, PSY.SU)

#! format: On
function get_default_time_series_names(
    ::Type{PSY.TransmissionInterface},
    ::Type{ConstantMaxInterfaceFlow},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_time_series_names(
    ::Type{PSY.TransmissionInterface},
    ::Type{VariableMaxInterfaceFlow},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        MinInterfaceFlowLimitParameter => "min_active_power_flow_limit",
        MaxInterfaceFlowLimitParameter => "max_active_power_flow_limit",
    )
end

function get_default_attributes(
    ::Type{<:PSY.TransmissionInterface},
    ::Type{ConstantMaxInterfaceFlow})
    return Dict{String, Any}()
end

function get_default_attributes(
    ::Type{<:PSY.TransmissionInterface},
    ::Type{VariableMaxInterfaceFlow})
    return Dict{String, Any}()
end

function get_initial_conditions_service_model(
    ::IOM.AbstractOptimizationModel,
    ::ServiceModel{T, D},
) where {T <: PSY.TransmissionInterface, D <: ConstantMaxInterfaceFlow}
    return ServiceModel(T, D)
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{InterfaceFlowLimit},
    interface::T,
    model::ServiceModel{T, ConstantMaxInterfaceFlow},
) where {T <: PSY.TransmissionInterface}
    expr = get_expression(container, InterfaceTotalFlow, T)
    interfaces, time_steps = axes(expr)
    constraint_container_ub = lazy_container_addition!(container, InterfaceFlowLimit,
        T,
        interfaces,
        time_steps;
        meta = "ub",
    )
    constraint_container_lb = lazy_container_addition!(container, InterfaceFlowLimit,
        T,
        interfaces,
        time_steps;
        meta = "lb",
    )
    int_name = PSY.get_name(interface)
    min_flow, max_flow = PSY.get_active_power_flow_limits(interface, PSY.SU)
    for t in time_steps
        constraint_container_ub[int_name, t] =
            JuMP.@constraint(get_jump_model(container), expr[int_name, t] <= max_flow)
        constraint_container_lb[int_name, t] =
            JuMP.@constraint(get_jump_model(container), expr[int_name, t] >= min_flow)
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{InterfaceFlowLimit},
    interface::T,
    model::ServiceModel{T, VariableMaxInterfaceFlow},
) where {T <: PSY.TransmissionInterface}
    expr = get_expression(container, InterfaceTotalFlow, T)
    interfaces, timesteps = axes(expr)
    constraint_container_ub = lazy_container_addition!(container, InterfaceFlowLimit,
        T,
        interfaces,
        timesteps;
        meta = "ub",
    )
    constraint_container_lb = lazy_container_addition!(container, InterfaceFlowLimit,
        T,
        interfaces,
        timesteps;
        meta = "lb",
    )
    int_name = PSY.get_name(interface)
    # DELETE-AFTER-REVIEW: reviewer context on the container change; remove once the PR is approved.
    # Merged per-type parameter containers keyed by interface name (empty meta); fetch the whole
    # container/multiplier array and index this interface's column/row (was a per-service
    # `meta = int_name` container).
    param_container_min =
        get_parameter(container, MinInterfaceFlowLimitParameter, PSY.TransmissionInterface)
    param_multiplier_min = get_parameter_multiplier_array(
        container,
        MinInterfaceFlowLimitParameter,
        PSY.TransmissionInterface,
    )
    param_container_max =
        get_parameter(container, MaxInterfaceFlowLimitParameter, PSY.TransmissionInterface)
    param_multiplier_max = get_parameter_multiplier_array(
        container,
        MaxInterfaceFlowLimitParameter,
        PSY.TransmissionInterface,
    )
    param_min = get_parameter_column_refs(param_container_min, int_name)
    param_max = get_parameter_column_refs(param_container_max, int_name)
    for t in timesteps
        constraint_container_ub[int_name, t] =
            JuMP.@constraint(get_jump_model(container), expr[int_name, t] <= param_multiplier_max[int_name, t] * param_max[t])
        constraint_container_lb[int_name, t] =
            JuMP.@constraint(get_jump_model(container), expr[int_name, t] >= param_multiplier_min[int_name, t] * param_min[t])
    end
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    service::T,
    model::ServiceModel{T, U},
) where {T <: PSY.TransmissionInterface, U <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    # At the moment the interfaces have no costs associated with them
    return
end
