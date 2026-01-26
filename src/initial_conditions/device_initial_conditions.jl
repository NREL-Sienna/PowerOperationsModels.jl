#################################################################################
# Device-specific initial condition value methods
# These extend the generic get_initial_conditions_value from IOM
#################################################################################

# InitialTimeDurationOff for thermal devices (Float64 version)
function get_initial_conditions_value(
    ::Vector{Union{InitialCondition{U, Float64}, InitialCondition{U, Nothing}}},
    component::W,
    ::U,
    ::V,
    container::OptimizationContainer,
) where {
    V <: AbstractThermalFormulation,
    W <: PSY.Component,
} where {U <: InitialTimeDurationOff}
    ic_data = get_initial_conditions_data(container)
    var_type = initial_condition_variable(U(), component, V())
    if !has_initial_condition_value(ic_data, var_type, W)
        val = initial_condition_default(U(), component, V())
    else
        var = get_initial_condition_value(ic_data, var_type, W)[PSY.get_name(component), 1]
        val = 0.0
        if !PSY.get_status(component) && !(var > ABSOLUTE_TOLERANCE)
            val = PSY.get_time_at_status(component)
        end
    end
    @debug "Device $(PSY.get_name(component)) initialized $U as $val" _group =
        LOG_GROUP_BUILD_INITIAL_CONDITIONS
    return InitialCondition{U, Float64}(component, val)
end

# InitialTimeDurationOff for thermal generators (JuMP.VariableRef version)
function get_initial_conditions_value(
    ::Vector{Union{InitialCondition{U, JuMP.VariableRef}, InitialCondition{U, Nothing}}},
    component::W,
    ::U,
    ::V,
    container::OptimizationContainer,
) where {
    V <: AbstractThermalFormulation,
    W <: PSY.ThermalGen,
} where {U <: InitialTimeDurationOff}
    ic_data = get_initial_conditions_data(container)
    var_type = initial_condition_variable(U(), component, V())
    if !has_initial_condition_value(ic_data, var_type, W)
        val = initial_condition_default(U(), component, V())
    else
        var = get_initial_condition_value(ic_data, var_type, W)[PSY.get_name(component), 1]
        val = 0.0
        if !PSY.get_status(component) && !(var > ABSOLUTE_TOLERANCE)
            val = PSY.get_time_at_status(component)
        end
    end
    @debug "Device $(PSY.get_name(component)) initialized $U as $val" _group =
        LOG_GROUP_BUILD_INITIAL_CONDITIONS
    return InitialCondition{U, JuMP.VariableRef}(
        component,
        add_jump_parameter(get_jump_model(container), val),
    )
end

# InitialTimeDurationOn for thermal generators (Float64 version)
function get_initial_conditions_value(
    ::Vector{Union{InitialCondition{U, Float64}, InitialCondition{U, Nothing}}},
    component::W,
    ::U,
    ::V,
    container::OptimizationContainer,
) where {
    V <: AbstractThermalFormulation,
    W <: PSY.ThermalGen,
} where {U <: InitialTimeDurationOn}
    ic_data = get_initial_conditions_data(container)
    var_type = initial_condition_variable(U(), component, V())
    if !has_initial_condition_value(ic_data, var_type, W)
        val = initial_condition_default(U(), component, V())
    else
        var = get_initial_condition_value(ic_data, var_type, W)[PSY.get_name(component), 1]
        val = 0.0
        if PSY.get_status(component) && (var > ABSOLUTE_TOLERANCE)
            val = PSY.get_time_at_status(component)
        end
    end
    @debug "Device $(PSY.get_name(component)) initialized $U as $val" _group =
        LOG_GROUP_BUILD_INITIAL_CONDITIONS
    return InitialCondition{U, Float64}(component, val)
end

# InitialTimeDurationOn for thermal generators (JuMP.VariableRef version)
function get_initial_conditions_value(
    ::Vector{Union{InitialCondition{U, JuMP.VariableRef}, InitialCondition{U, Nothing}}},
    component::W,
    ::U,
    ::V,
    container::OptimizationContainer,
) where {
    V <: AbstractThermalFormulation,
    W <: PSY.ThermalGen,
} where {U <: InitialTimeDurationOn}
    ic_data = get_initial_conditions_data(container)
    var_type = initial_condition_variable(U(), component, V())
    if !has_initial_condition_value(ic_data, var_type, W)
        val = initial_condition_default(U(), component, V())
    else
        var = get_initial_condition_value(ic_data, var_type, W)[PSY.get_name(component), 1]
        val = 0.0
        if PSY.get_status(component) && (var > ABSOLUTE_TOLERANCE)
            val = PSY.get_time_at_status(component)
        end
    end
    @debug "Device $(PSY.get_name(component)) initialized $U as $val" _group =
        LOG_GROUP_BUILD_INITIAL_CONDITIONS
    return InitialCondition{U, JuMP.VariableRef}(
        component,
        add_jump_parameter(get_jump_model(container), val),
    )
end

#################################################################################
# Device-specific add_initial_condition! methods
#################################################################################

# Thermal generators with must_run handling
function add_initial_condition!(
    container::OptimizationContainer,
    components::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::U,
    ::D,
) where {
    T <: PSY.ThermalGen,
    U <: AbstractThermalFormulation,
    D <: Union{InitialTimeDurationOff, InitialTimeDurationOn, DeviceStatus},
}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, D, T)
        return
    end

    ini_cond_vector = add_initial_condition_container!(container, D(), T, components)
    for (ix, component) in enumerate(components)
        if PSY.get_must_run(component)
            ini_cond_vector[ix] = InitialCondition{D, Nothing}(component, nothing)
        else
            ini_cond_vector[ix] =
                get_initial_conditions_value(
                    ini_cond_vector,
                    component,
                    D(),
                    U(),
                    container,
                )
        end
    end
    return
end
