#! format: off
get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = 1.0
# Per-device P_min multiplier computed inline at add_to_expression! call sites.
get_variable_multiplier(::Type{OnVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:Union{AbstractCompactUnitCommitment, ThermalCompactDispatch}}) = 1.0

############## ActivePowerVariable, ThermalGen ####################
get_variable_binary(::Type{ActivePowerVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_warm_start_value(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power(d, PSY.SU)
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_must_run(d) ? PSY.get_active_power_limits(d, PSY.SU).min : 0.0
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max

############## PowerAboveMinimumVariable, ThermalGen ####################
get_variable_binary(::Type{PowerAboveMinimumVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_warm_start_value(::Type{PowerAboveMinimumVariable}, d::PSY.ThermalGen, ::Type{<:AbstractCompactUnitCommitment}) = max(0.0, PSY.get_active_power(d, PSY.SU) - PSY.get_active_power_limits(d, PSY.SU).min)
get_variable_lower_bound(::Type{PowerAboveMinimumVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 0.0
get_variable_upper_bound(::Type{PowerAboveMinimumVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max - PSY.get_active_power_limits(d, PSY.SU).min

############## ReactivePowerVariable, ThermalGen ####################
get_variable_binary(::Type{ReactivePowerVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_warm_start_value(::Type{ReactivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_reactive_power(d, PSY.SU)
get_variable_lower_bound(::Type{ReactivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).min
get_variable_upper_bound(::Type{ReactivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).max

############## OnVariable, ThermalGen ####################
get_variable_binary(::Type{OnVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = true
get_variable_warm_start_value(::Type{OnVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_status(d) ? 1.0 : 0.0
get_variable_lower_bound(::Type{OnVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalUnitCommitment}) = PSY.get_must_run(d) ? 1.0 : 0.0

############## StopVariable, ThermalGen ####################
get_variable_binary(::Type{StopVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = true
get_variable_lower_bound(::Type{StopVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 0.0
get_variable_upper_bound(::Type{StopVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 1.0

############## StartVariable, ThermalGen ####################
get_variable_binary(::Type{StartVariable}, d::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = true
get_variable_lower_bound(::Type{StartVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 0.0
get_variable_upper_bound(::Type{StartVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 1.0

############## ColdStartVariable, WarmStartVariable, HotStartVariable ############
get_variable_binary(::Type{<:Union{ColdStartVariable, WarmStartVariable, HotStartVariable}}, ::Type{PSY.ThermalMultiStart}, ::Type{<:AbstractThermalFormulation}) = true

############## SlackVariables, ThermalGen ####################
# LB Slack #
get_variable_binary(::Type{RateofChangeConstraintSlackDown}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_lower_bound(::Type{RateofChangeConstraintSlackDown}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 0.0
# UB Slack #
get_variable_binary(::Type{RateofChangeConstraintSlackUp}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_lower_bound(::Type{RateofChangeConstraintSlackUp}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 0.0
#! format: on

"""
Adds a variable to the optimization model for the OnVariable of Thermal Units
"""
function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    ::Type{F},
) where {
    T <: Union{OnVariable, StartVariable, StopVariable},
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    F <: AbstractThermalFormulation,
} where {D <: PSY.ThermalGen}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    settings = get_settings(container)
    binary = get_variable_binary(T, D, F)

    variable = add_variable_container!(
        container,
        T,
        D,
        [PSY.get_name(d) for d in devices if !PSY.get_must_run(d)],
        time_steps,
    )

    for d in devices
        if PSY.get_must_run(d)
            continue
        end
        name = PSY.get_name(d)
        for t in time_steps
            variable[name, t] = JuMP.@variable(
                get_jump_model(container),
                base_name = "$(T)_$(D)_{$(name), $(t)}",
                binary = binary
            )
            if get_warm_start(settings)
                init = get_variable_warm_start_value(T, d, F)
                init !== nothing && JuMP.set_start_value(variable[name, t], init)
            end
        end
    end

    return
end
