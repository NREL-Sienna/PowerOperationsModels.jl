"""
Thin wrappers around `add_param_container_split_axes!` and `add_param_container_shared_axes!`.
Put here instead of back in `InfrastructureOptimizationModels.jl` because they require concrete
parameter types defined in `core/parameters.jl`.
"""
function add_param_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    ::Type{V},
    name::String,
    param_axs,
    multiplier_axs,
    additional_axs,
    time_steps::UnitRange{Int};
    sparse = false,
    meta = CONTAINER_KEY_EMPTY_META,
) where {
    T <: TimeSeriesParameter,
    U <: IS.InfrastructureSystemsComponent,
    V <: IS.TimeSeriesData,
}
    param_key = ParameterKey(T, U, meta)
    if isabstracttype(V)
        error("$V can't be abstract: $param_key")
    end
    attributes = TimeSeriesAttributes(V, name)
    return add_param_container_split_axes!(
        container,
        param_key,
        attributes,
        get_param_eltype(container),
        param_axs,
        multiplier_axs,
        additional_axs,
        time_steps;
        sparse = sparse,
    )
end

function add_param_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    variable_types::Tuple{Vararg{Type}},
    sos_variable::SOSStatusVariable = SOSStatusVariable.NO_VARIABLE,
    uses_compact_power::Bool = false,
    data_type::DataType = Float64,
    axs...;
    sparse = false,
    meta = CONTAINER_KEY_EMPTY_META,
) where {T <: ObjectiveFunctionParameter, U <: IS.InfrastructureSystemsComponent}
    param_key = ParameterKey(T, U, meta)
    attributes =
        CostFunctionAttributes{data_type}(variable_types, sos_variable, uses_compact_power)
    return add_param_container_shared_axes!(
        container,
        param_key,
        attributes,
        data_type,
        axs...;
        sparse = sparse,
    )
end

function add_param_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    source_key::V,
    axs...;
    sparse = false,
    meta = CONTAINER_KEY_EMPTY_META,
) where {
    T <: VariableValueParameter,
    U <: IS.InfrastructureSystemsComponent,
    V <: OptimizationContainerKey,
}
    param_key = ParameterKey(T, U, meta)
    attributes = VariableValueAttributes(source_key)
    return add_param_container_shared_axes!(
        container, param_key, attributes, get_param_eltype(container), axs...;
        sparse = sparse)
end

function add_param_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    ::Type{V},
    axs...;
    sparse = false,
    meta = CONTAINER_KEY_EMPTY_META,
) where {T <: EventParameter, U <: IS.InfrastructureSystemsComponent, V <: PSY.Contingency}
    param_key = ParameterKey(T, U, meta)
    attributes = EventParametersAttributes(V)
    return add_param_container_shared_axes!(
        container, param_key, attributes, get_param_eltype(container), axs...;
        sparse = sparse)
end

function add_param_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    source_key::V,
    axs...;
    sparse = false,
    meta = CONTAINER_KEY_EMPTY_META,
) where {
    T <: FixValueParameter,
    U <: IS.InfrastructureSystemsComponent,
    V <: OptimizationContainerKey,
}
    param_key = ParameterKey(T, U, meta)
    attributes = VariableValueAttributes(source_key)
    return add_param_container_shared_axes!(
        container, param_key, attributes, get_param_eltype(container), axs...;
        sparse = sparse)
end
