######## THERMAL GENERATION CONSTRAINTS ############

# active power limits of generators when there are no CommitmentVariables
"""
Min and max active power limits of generators for thermal dispatch formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractThermalDispatchFormulation},
)
    return PSY.get_active_power_limits(device, PSY.SU)
end

# active power limits of generators when there are CommitmentVariables
"""
Min and max active power limits of generators for thermal unit commitment formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractThermalUnitCommitment},
)
    return PSY.get_active_power_limits(device, PSY.SU)
end

"""
Semicontinuous range constraints for thermal dispatch formulations
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:PowerVariableLimitsConstraint},
    U::Type{<:Union{VariableType, ExpressionType}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalGen,
    W <: AbstractThermalDispatchFormulation,
    X <: AbstractNetworkModel,
}
    if !has_semicontinuous_feedforward(model, U)
        add_range_constraints!(container, T, U, devices, model, X)
    end
    return
end

"""
Semicontinuous range constraints for unit commitment formulations
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:PowerVariableLimitsConstraint},
    U::Type{<:Union{VariableType, ExpressionType}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalGen,
    W <: AbstractThermalUnitCommitment,
    X <: AbstractNetworkModel,
}
    add_semicontinuous_range_constraints!(container, T, U, devices, model, X)
    return
end

"""
Min and Max active power limits for Compact Unit Commitment
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractCompactUnitCommitment},
) #  -> Union{Nothing, NamedTuple{(:min, :max), Tuple{Float64, Float64}}}
    return (
        min = 0,
        max = PSY.get_active_power_limits(device, PSY.SU).max -
              PSY.get_active_power_limits(device, PSY.SU).min,
    )
end

"""
Startup shutdown limits for Compact Unit Commitment
"""
function get_startup_shutdown_limits(
    device,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractCompactUnitCommitment},
)
    return (
        startup = PSY.get_active_power_limits(device, PSY.SU).max,
        shutdown = PSY.get_active_power_limits(device, PSY.SU).max,
    )
end

function _get_data_for_range_ic(
    initial_conditions_power::Vector{<:InitialCondition},
    initial_conditions_status::Vector{<:InitialCondition},
)
    lenght_devices_power = length(initial_conditions_power)
    lenght_devices_status = length(initial_conditions_status)
    IS.@assert_op lenght_devices_power == lenght_devices_status
    ini_conds = Matrix{InitialCondition}(undef, lenght_devices_power, 2)
    idx = 0
    for (ix, ic) in enumerate(initial_conditions_power)
        g = IOM.get_component(ic)
        IS.@assert_op g == IOM.get_component(initial_conditions_status[ix])
        idx += 1
        ini_conds[idx, 1] = ic
        ini_conds[idx, 2] = initial_conditions_status[ix]
    end
    return ini_conds
end

# commitment formulations: time series upper bounds.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActivePowerVariableTimeSeriesLimitsConstraint},
    U::Type{<:Union{ActivePowerVariable, ActivePowerRangeExpressionUB}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalGen,
    W <: AbstractThermalUnitCommitment,
    X <: AbstractNetworkModel,
}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

# compact commitment: IC constraints.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActiveRangeICConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, S},
    network_model::NetworkModel{X},
) where {
    T <: PSY.ThermalGen,
    S <: AbstractCompactUnitCommitment,
    X <: AbstractNetworkModel,
}
    initial_conditions_power = get_initial_condition(container, DeviceAboveMinPower(), T)
    initial_conditions_status = get_initial_condition(container, DeviceStatus(), T)
    ini_conds = _get_data_for_range_ic(initial_conditions_power, initial_conditions_status)

    if !isempty(ini_conds)
        varstop = get_variable(container, StopVariable, T)
        device_name_set = PSY.get_name.(devices)
        con = add_constraints_container!(container, ActiveRangeICConstraint,
            T,
            device_name_set,
            [1],
        )

        for (ix, ic) in enumerate(ini_conds[:, 1])
            name = IOM.get_component_name(ic)
            device = IOM.get_component(ic)
            limits = PSY.get_active_power_limits(device, PSY.SU)
            lag_ramp_limits = PSY.get_power_trajectory(device, PSY.SU)
            val = max(limits.max - lag_ramp_limits.shutdown, 0)
            con[name, 1] = JuMP.@constraint(
                get_jump_model(container),
                val * varstop[name, 1] <=
                ini_conds[ix, 2].value * (limits.max - limits.min) - get_value(ic)
            )
        end
    else
        @warn "Data doesn't contain generators with ramp limits, consider adjusting your formulation"
    end
    return
end

"""
Reactive power limits of generators for all dispatch formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractThermalDispatchFormulation},
)
    return PSY.get_reactive_power_limits(device, PSY.SU)
end

"""
Reactive power limits of generators when there CommitmentVariables
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractThermalUnitCommitment},
)
    return PSY.get_reactive_power_limits(device, PSY.SU)
end

# commitment formulations: commitment constraints (on/off logic)
function add_constraints!(
    container::OptimizationContainer,
    T::Type{CommitmentConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    network_model::NetworkModel{X},
) where {
    U <: PSY.ThermalGen,
    V <: AbstractThermalUnitCommitment,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    varstart = get_variable(container, StartVariable, U)
    varstop = get_variable(container, StopVariable, U)
    varon = get_variable(container, OnVariable, U)
    names = axes(varstart, 1)
    initial_conditions = get_initial_condition(container, DeviceStatus(), U)
    constraint =
        add_constraints_container!(container, CommitmentConstraint, U, names, time_steps)
    aux_constraint = add_constraints_container!(container, CommitmentConstraint,
        U,
        names,
        time_steps;
        meta = "aux",
    )

    for ic in initial_conditions
        name = IOM.get_component_name(ic)
        if !PSY.get_must_run(IOM.get_component(ic))
            constraint[name, 1] = JuMP.@constraint(
                get_jump_model(container),
                varon[name, 1] == get_value(ic) + varstart[name, 1] - varstop[name, 1]
            )
            aux_constraint[name, 1] = JuMP.@constraint(
                get_jump_model(container),
                varstart[name, 1] + varstop[name, 1] <= 1.0
            )
        end
    end

    for ic in initial_conditions
        if PSY.get_must_run(IOM.get_component(ic))
            continue
        else
            name = IOM.get_component_name(ic)
            for t in time_steps[2:end]
                constraint[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    varon[name, t] ==
                    varon[name, t - 1] + varstart[name, t] - varstop[name, t]
                )
                aux_constraint[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    varstart[name, t] + varstop[name, t] <= 1.0
                )
            end
        end
    end
    return
end

########################### Ramp/Rate of Change Constraints ################################
"""
This function gets the data for the generators for ramping constraints of thermal generators
"""
_get_initial_condition_type(
    ::Type{RampConstraint},
    ::Type{<:PSY.ThermalGen},
    ::Type{<:AbstractThermalFormulation},
) = DevicePower
_get_initial_condition_type(
    ::Type{RampConstraint},
    ::Type{<:PSY.ThermalGen},
    ::Type{<:AbstractCompactUnitCommitment},
) = DeviceAboveMinPower

# plain commitment ramping limits: semicontinuous with ActivePowerVariable.
"""
This function adds the ramping limits of generators when there are CommitmentVariables
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    ::NetworkModel{W},
) where {
    U <: PSY.ThermalGen,
    V <: AbstractThermalUnitCommitment,
    W <: AbstractNetworkModel,
}
    add_semicontinuous_ramp_constraints!(
        container,
        T,
        ActivePowerVariable,
        devices,
        model,
        W,
    )
    return
end

# compact commitment ramping limits: semicontinuous with PowerAboveMinimumVariable.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    ::NetworkModel{W},
) where {
    U <: PSY.ThermalGen,
    V <: AbstractCompactUnitCommitment,
    W <: AbstractNetworkModel,
}
    add_semicontinuous_ramp_constraints!(
        container,
        T,
        PowerAboveMinimumVariable,
        devices,
        model,
        W,
    )
    return
end

# non-compact dispatch ramping limits: linear with ActivePowerVariable.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    ::NetworkModel{W},
) where {
    U <: PSY.ThermalGen,
    V <: AbstractThermalDispatchFormulation,
    W <: AbstractNetworkModel,
}
    add_linear_ramp_constraints!(container, T, ActivePowerVariable, devices, model, W)
    return
end

########################### start up trajectory constraints ######################################

function _convert_hours_to_timesteps(
    start_times_hr::PSY.StartUpStages,
    resolution::Dates.TimePeriod,
)
    _start_times_ts = (
        round((hr * MINUTES_IN_HOUR) / Dates.value(Dates.Minute(resolution)), RoundUp) for
        hr in start_times_hr
    )
    start_times_ts = PSY.StartUpStages(_start_times_ts)
    return start_times_ts
end

########################### time duration constraints ######################################
"""
If the fraction of hours that a generator has a duration constraint is less than
the fraction of hours that a single time_step represents then it is not binding.
"""
function _get_data_for_tdc(
    initial_conditions_on::Vector{T},
    initial_conditions_off::Vector{U},
    resolution::Dates.TimePeriod,
) where {T <: InitialCondition, U <: InitialCondition}
    steps_per_hour = 60 / Dates.value(Dates.Minute(resolution))
    fraction_of_hour = 1 / steps_per_hour
    lenght_devices_on = length(initial_conditions_on)
    lenght_devices_off = length(initial_conditions_off)
    IS.@assert_op lenght_devices_off == lenght_devices_on
    time_params = Vector{UpDown}(undef, lenght_devices_on)
    ini_conds = Matrix{InitialCondition}(undef, lenght_devices_on, 2)
    idx = 0
    for (ix, ic) in enumerate(initial_conditions_on)
        g = IOM.get_component(ic)
        IS.@assert_op g == IOM.get_component(initial_conditions_off[ix])
        time_limits = PSY.get_time_limits(g)
        name = PSY.get_name(g)
        if time_limits !== nothing
            if (time_limits.up <= fraction_of_hour) & (time_limits.down <= fraction_of_hour)
                @debug "Generator $(name) has a nonbinding time limits. Constraints Skipped"
                continue
            else
                idx += 1
            end
            ini_conds[idx, 1] = ic
            ini_conds[idx, 2] = initial_conditions_off[ix]
            up_val = round(Float64, time_limits.up * steps_per_hour, RoundUp)
            down_val = round(Float64, time_limits.down * steps_per_hour, RoundUp)
            time_params[idx] = (up = up_val, down = down_val)
        end
    end
    if idx < lenght_devices_on
        ini_conds = ini_conds[1:idx, :]
        deleteat!(time_params, (idx + 1):lenght_devices_on)
    end
    return ini_conds, time_params
end

# non-multistart commitment formulations: time duration constraints
function add_constraints!(
    container::OptimizationContainer,
    ::Type{DurationConstraint},
    ::IS.FlattenIteratorWrapper{U},
    ::DeviceModel{U, V},
    ::NetworkModel{<:AbstractNetworkModel},
) where {U <: PSY.ThermalGen, V <: AbstractThermalUnitCommitment}
    parameters = built_for_recurrent_solves(container)
    resolution = get_resolution(container)
    # Use getter functions that don't require creating the keys here
    initial_conditions_on = get_initial_condition(container, InitialTimeDurationOn(), U)
    initial_conditions_off = get_initial_condition(container, InitialTimeDurationOff(), U)
    ini_conds, time_params =
        _get_data_for_tdc(initial_conditions_on, initial_conditions_off, resolution)
    if !(isempty(ini_conds))
        if parameters
            device_duration_parameters!(
                container,
                time_params,
                ini_conds,
                DurationConstraint,
                U,
            )
        else
            device_duration_retrospective!(
                container,
                time_params,
                ini_conds,
                DurationConstraint,
                U,
            )
        end
    else
        @warn "Data doesn't contain generators with time-up/down limits, consider adjusting your formulation"
    end
    return
end

# ThermalGen range-constraint specialization: checks must_run to decide whether to use binary variable.
# Overrides the generic IS.InfrastructureSystemsComponent version in IOM.
function IOM._add_semicontinuous_bound_range_constraints_impl!(
    container::OptimizationContainer,
    ::Type{T},
    dir::IOM.BoundDirection,
    array,
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel{V, W};
    meta_suffix::String = "",
) where {T <: ConstraintType, V <: PSY.ThermalGen, W <: AbstractDeviceFormulation}
    time_steps = IOM.get_time_steps(container)
    names = IS.get_name.(devices)
    jump_model = IOM.get_jump_model(container)
    con = IOM.add_constraints_container!(
        container, T, V, names, time_steps;
        meta = IOM.constraint_meta(dir) * meta_suffix)
    varbin = IOM.get_variable(container, OnVariable, V)

    for device in devices
        ci_name = IS.get_name(device)
        limits = IOM.get_min_max_limits(device, T, W)
        for t in time_steps
            bin = PSY.get_must_run(device) ? 1.0 : varbin[ci_name, t]
            IOM.add_range_bound_constraint!(
                dir, jump_model, con, ci_name, t,
                array[ci_name, t], IOM.get_bound(dir, limits), bin)
        end
    end
    return
end
