#! format: off
#################### Initial Conditions for models ###############
initial_condition_default(::DeviceStatus, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_status(d) ? 1.0 : 0.0
initial_condition_variable(::DeviceStatus, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()
initial_condition_default(::DevicePower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_active_power(d, PSY.SU)
initial_condition_variable(::DevicePower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = ActivePowerVariable()
initial_condition_default(::DeviceAboveMinPower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = max(0.0, PSY.get_active_power(d, PSY.SU) - PSY.get_active_power_limits(d, PSY.SU).min)
initial_condition_variable(::DeviceAboveMinPower, d::PSY.ThermalGen, ::AbstractCompactUnitCommitment) = PowerAboveMinimumVariable()
initial_condition_default(::InitialTimeDurationOn, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_status(d) ? PSY.get_time_at_status(d) : 0.0
initial_condition_variable(::InitialTimeDurationOn, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()
initial_condition_default(::InitialTimeDurationOff, d::PSY.ThermalGen, ::AbstractThermalFormulation) = !PSY.get_status(d) ? PSY.get_time_at_status(d) : 0.0
initial_condition_variable(::InitialTimeDurationOff, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()
#! format: on

function get_initial_conditions_device_model(
    model::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, D},
) where {T <: PSY.ThermalGen, D <: AbstractThermalDispatchFormulation}
    if supports_milp(get_optimization_container(model))
        return DeviceModel(T, ThermalBasicUnitCommitment)
    else
        return DeviceModel(T, ThermalBasicDispatch)
    end
end

function get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, D},
) where {T <: PSY.ThermalGen, D <: AbstractThermalUnitCommitment}
    return DeviceModel(T, ThermalBasicUnitCommitment)
end

function get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, D},
) where {T <: PSY.ThermalGen, D <: AbstractCompactUnitCommitment}
    return DeviceModel(T, ThermalBasicCompactUnitCommitment)
end

########################## Make initial Conditions for a Model #############################
function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::AbstractThermalUnitCommitment,
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DeviceStatus())
    add_initial_condition!(container, devices, formulation, DevicePower())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOn())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOff())

    return
end

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::AbstractCompactUnitCommitment,
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DeviceStatus())
    add_initial_condition!(container, devices, formulation, DeviceAboveMinPower())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOn())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOff())

    return
end

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::Union{ThermalBasicUnitCommitment, ThermalBasicCompactUnitCommitment},
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DeviceStatus())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOn())
    add_initial_condition!(container, devices, formulation, InitialTimeDurationOff())
    return
end

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::AbstractThermalDispatchFormulation,
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DevicePower())
    return
end

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
    has_ic = has_initial_condition_value(ic_data, var_type, W)
    if !has_ic
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
    has_ic = has_initial_condition_value(ic_data, var_type, W)
    if !has_ic
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
