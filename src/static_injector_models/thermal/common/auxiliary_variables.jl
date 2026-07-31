############################ Auxiliary Variables Calculation ################################
function calculate_aux_variable_value!(
    container::OptimizationContainer,
    ::AuxVarKey{TimeDurationOn, T},
    ::PSY.System,
) where {T <: PSY.ThermalGen}
    on_variable_output = get_variable(container, OnVariable, T)
    aux_variable_container = get_aux_variable(container, TimeDurationOn, T)
    ini_cond = get_initial_condition(container, InitialTimeDurationOn(), T)

    time_steps = get_time_steps(container)

    for ix in eachindex(JuMP.axes(aux_variable_container)[1])
        # if its nothing it means the thermal unit was on must run
        # so there is nothing to do but to add the total number of time steps
        # to the count
        if isnothing(get_value(ini_cond[ix]))
            sum_on_var = time_steps[end]
        else
            on_var_name = IOM.get_component_name(ini_cond[ix])
            ini_cond_value = get_condition(ini_cond[ix])
            # On Var doesn't exist for a unit that has must_run = true
            on_var = jump_value.(on_variable_output[on_var_name, :])
            aux_variable_container.data[ix, :] .= ini_cond_value
            sum_on_var = sum(on_var)
        end
        if sum_on_var == time_steps[end] # Unit was always on
            aux_variable_container.data[ix, :] += time_steps
        elseif sum_on_var == 0.0 # Unit was always off
            aux_variable_container.data[ix, :] .= 0.0
        else
            previous_condition = ini_cond_value
            for (t, v) in enumerate(on_var)
                if v < 0.99 # Unit turn off
                    time_value = 0.0
                elseif isapprox(v, 1.0; atol = ABSOLUTE_TOLERANCE) # Unit is on
                    time_value = previous_condition + 1.0
                else
                    error("Binary condition returned $v")
                end
                previous_condition = aux_variable_container.data[ix, t] = time_value
            end
        end
    end

    return
end

function calculate_aux_variable_value!(
    container::OptimizationContainer,
    ::AuxVarKey{TimeDurationOff, T},
    ::PSY.System,
) where {T <: PSY.ThermalGen}
    on_variable_output = get_variable(container, OnVariable, T)
    aux_variable_container = get_aux_variable(container, TimeDurationOff, T)
    ini_cond = get_initial_condition(container, InitialTimeDurationOff(), T)

    time_steps = get_time_steps(container)
    for ix in eachindex(JuMP.axes(aux_variable_container)[1])
        # if its nothing it means the thermal unit was on must_run = true
        # so there is nothing to do but continue
        if isnothing(get_value(ini_cond[ix]))
            sum_on_var = 0.0
        else
            on_var_name = IOM.get_component_name(ini_cond[ix])
            # On Var doesn't exist for a unit that has must run
            on_var = jump_value.(on_variable_output[on_var_name, :])
            ini_cond_value = get_condition(ini_cond[ix])
            aux_variable_container.data[ix, :] .= ini_cond_value
            sum_on_var = sum(on_var)
        end
        if sum_on_var == time_steps[end] # Unit was always on
            aux_variable_container.data[ix, :] .= 0.0
        elseif sum_on_var == 0.0 # Unit was always off
            aux_variable_container.data[ix, :] += time_steps
        else
            previous_condition = ini_cond_value
            for (t, v) in enumerate(on_var)
                if v < 0.99 # Unit turn off
                    time_value = previous_condition + 1.0
                elseif isapprox(v, 1.0; atol = ABSOLUTE_TOLERANCE) # Unit is on
                    time_value = 0.0
                else
                    error("Binary condition returned $v")
                end
                previous_condition = aux_variable_container.data[ix, t] = time_value
            end
        end
    end

    return
end

function calculate_aux_variable_value!(
    container::OptimizationContainer,
    ::AuxVarKey{PowerOutput, T},
    system::PSY.System,
) where {T <: PSY.ThermalGen}
    time_steps = get_time_steps(container)
    if has_container_key(container, OnVariable, T)
        on_variable_output = get_variable(container, OnVariable, T)
    elseif has_container_key(container, OnStatusParameter, T)
        on_variable_output = get_parameter_array(container, OnStatusParameter, T)
    else
        error(
            "$T formulation is NOT supported without a Feedforward for CommitmentDecisions,
      please consider changing your simulation setup or adding a SemiContinuousFeedforward.",
        )
    end
    p_variable_output = get_variable(container, PowerAboveMinimumVariable, T)
    device_name = axes(p_variable_output, 1)
    aux_variable_container = get_aux_variable(container, PowerOutput, T)
    for d_name in device_name
        d = PSY.get_component(T, system, d_name)
        name = PSY.get_name(d)
        min = PSY.get_active_power_limits(d, PSY.SU).min
        for t in time_steps
            aux_variable_container[name, t] =
                jump_value(on_variable_output[name, t]) * min +
                jump_value(p_variable_output[name, t])
        end
    end

    return
end
