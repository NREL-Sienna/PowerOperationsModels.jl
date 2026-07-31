"""
Formulation type to enable pg-lib commitment formulation with startup/shutdown profiles
"""
struct ThermalMultiStartUnitCommitment <: AbstractCompactUnitCommitment end

#! format: off
has_multistart_variables(::PSY.ThermalMultiStart, ::ThermalMultiStartUnitCommitment)=true
start_up_cost(cost, ::Type{<:PSY.ThermalMultiStart}, ::Type{T}, ::Type{ThermalMultiStartUnitCommitment} = ThermalMultiStartUnitCommitment) where {T <: MultiStartVariable} =
    start_up_cost(cost, T)
#! format: on

"""
Min and max active power limits for multi-start unit commitment formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalMultiStartUnitCommitment},
) #  -> Union{Nothing, NamedTuple{(:startup, :shutdown), Tuple{Float64, Float64}}}
    return (
        min = 0.0,
        max = PSY.get_active_power_limits(device, PSY.SU).max -
              PSY.get_active_power_limits(device, PSY.SU).min,
    )
end

"""
Startup and shutdown active power limits for Compact Unit Commitment
"""
function get_startup_shutdown_limits(
    device::PSY.ThermalMultiStart,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalMultiStartUnitCommitment},
)
    startup_shutdown = PSY.get_power_trajectory(device, PSY.SU)
    if isnothing(startup_shutdown)
        @warn(
            "Generator $(summary(device)) has a Nothing startup_shutdown property. Using active power limits."
        )
        return (
            startup = PSY.get_active_power_limits(device, PSY.SU).max,
            shutdown = PSY.get_active_power_limits(device, PSY.SU).max,
        )
    end
    return startup_shutdown
end

# FIXME: untested and possibly dead code. The ThermalMultiStart constructor
# (thermalgeneration_constructor.jl) calls add_constraints! for
# ActivePowerVariableLimitsConstraint with expression types
# (ActivePowerRangeExpressionLB/UB), not variable types.
"""
This function adds range constraint for the first time period. Constraint (10) from PGLIB formulation
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ActivePowerVariableLimitsConstraint},
    U::Type{<:VariableType},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalMultiStart,
    W <: ThermalMultiStartUnitCommitment,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    varp = get_variable(container, U, V)
    varstatus = get_variable(container, OnVariable, V)
    varon = get_variable(container, StartVariable, V)
    varoff = get_variable(container, StopVariable, V)

    names = [PSY.get_name(x) for x in devices]
    con_on = add_constraints_container!(
        container,
        T,
        V,
        names,
        time_steps;
        meta = "on",
    )
    con_off = add_constraints_container!(
        container,
        T,
        V,
        names,
        time_steps[1:(end - 1)];
        meta = "off",
    )
    con_lb = add_constraints_container!(
        container,
        T,
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for device in devices
        name = PSY.get_name(device)
        limits = get_min_max_limits(device, T, W) # depends on constraint type and formulation type
        startup_shutdown_limits = get_startup_shutdown_limits(device, T, W)

        if JuMP.has_lower_bound(varp[name, t])
            JuMP.set_lower_bound(varp[name, t], 0.0)
        end
        for t in time_steps
            con_on[name, t] = JuMP.@constraint(
                get_jump_model(container),
                varp[name, t] <=
                (limits.max - limits.min) * varstatus[name, t] -
                max(limits.max - startup_shutdown_limits.startup, 0.0) * varon[name, t]
            )

            con_lb[name, t] =
                JuMP.@constraint(get_jump_model(container), varp[name, t] >= 0.0)

            if t != length(time_steps)
                con_off[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    varp[name, t] <=
                    (limits.max - limits.min) * varstatus[name, t] -
                    max(limits.max - startup_shutdown_limits.shutdown, 0.0) *
                    varoff[name, t + 1]
                )
            end
        end
    end
    return
end

# multistart devices with commitment formulations: lower bound expression.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ActivePowerVariableLimitsConstraint},
    U::Type{ActivePowerRangeExpressionLB},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalMultiStart,
    W <: ThermalMultiStartUnitCommitment,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    component_type = V
    expression_products = get_expression(container, U, component_type)
    varp = get_variable(container, PowerAboveMinimumVariable, component_type)

    names = [PSY.get_name(x) for x in devices]
    con_lb = add_constraints_container!(
        container,
        T,
        component_type,
        names,
        time_steps;
        meta = "lb",
    )

    for device in devices
        name = PSY.get_name(device)
        for t in time_steps
            if JuMP.has_lower_bound(varp[name, t])
                JuMP.set_lower_bound(varp[name, t], 0.0)
            end
            con_lb[name, t] =
                JuMP.@constraint(
                    get_jump_model(container),
                    expression_products[name, t] >= 0
                )
        end
    end
    return
end

# multistart devices with commitment formulations: upper bound expression.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ActivePowerVariableLimitsConstraint},
    U::Type{ActivePowerRangeExpressionUB},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalMultiStart,
    W <: ThermalMultiStartUnitCommitment,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    component_type = V
    expression_products = get_expression(container, U, component_type)
    varstatus = get_variable(container, OnVariable, component_type)
    varon = get_variable(container, StartVariable, component_type)
    varoff = get_variable(container, StopVariable, component_type)
    varp = get_variable(container, PowerAboveMinimumVariable, component_type)

    names = [PSY.get_name(x) for x in devices]
    con_on = add_constraints_container!(
        container,
        T,
        component_type,
        names,
        time_steps;
        meta = "ubon",
    )
    con_off = add_constraints_container!(
        container,
        T,
        component_type,
        names,
        time_steps[1:(end - 1)];
        meta = "uboff",
    )

    for device in devices
        name = PSY.get_name(device)
        limits = get_min_max_limits(device, T, W) # depends on constraint type and formulation type
        startup_shutdown_limits = get_startup_shutdown_limits(device, T, W)
        @assert !isnothing(startup_shutdown_limits) "$(name)"
        for t in time_steps
            if JuMP.has_lower_bound(varp[name, t])
                JuMP.set_lower_bound(varp[name, t], 0.0)
            end
            con_on[name, t] = JuMP.@constraint(
                get_jump_model(container),
                expression_products[name, t] <=
                (limits.max - limits.min) * varstatus[name, t] -
                max(limits.max - startup_shutdown_limits.startup, 0) * varon[name, t]
            )
            if t != length(time_steps)
                con_off[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    expression_products[name, t] <=
                    (limits.max - limits.min) * varstatus[name, t] -
                    max(limits.max - startup_shutdown_limits.shutdown, 0) *
                    varoff[name, t + 1]
                )
            end
        end
    end
    return
end

# multi-start commitment ramping limits: linear with PowerAboveMinimumVariable.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{PSY.ThermalMultiStart},
    model::DeviceModel{PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment},
    ::NetworkModel{U},
) where {U <: AbstractNetworkModel}
    add_linear_ramp_constraints!(container, T, PowerAboveMinimumVariable, devices, model, U)
    return
end

@doc raw"""
Constructs contraints for different types of starts based on generator down-time

# Equations
for t in time_limits[s+1]:T

``` var_starts[name, s, t] <= sum( var_stop[name, t-i] for i in time_limits[s]:(time_limits[s+1]-1)  ```

# LaTeX

``  δ^{s}(t)  \leq \sum_{i=TS^{s}_{g}}^{TS^{s+1}_{g}} x^{stop}(t-i) ``
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{StartupTimeLimitTemperatureConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, ThermalMultiStartUnitCommitment},
    ::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalMultiStart}
    resolution = get_resolution(container)
    time_steps = get_time_steps(container)
    start_vars = [
        get_variable(container, HotStartVariable, T),
        get_variable(container, WarmStartVariable, T),
    ]
    varstop = get_variable(container, StopVariable, T)

    names = PSY.get_name.(devices)

    con = [
        add_constraints_container!(container, StartupTimeLimitTemperatureConstraint,
            T,
            names,
            time_steps;
            sparse = true,
            meta = "hot",
        ),
        add_constraints_container!(container, StartupTimeLimitTemperatureConstraint,
            T,
            names,
            time_steps;
            sparse = true,
            meta = "warm",
        ),
    ]

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        startup_types = PSY.get_start_types(d)
        time_limits = _convert_hours_to_timesteps(PSY.get_start_time_limits(d), resolution)
        for ix in 1:(startup_types - 1)
            if t >= time_limits[ix + 1]
                con[ix][name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    start_vars[ix][name, t] <= sum(
                        varstop[name, t - i] for i in UnitRange{Int}(
                            Int(time_limits[ix]),
                            Int(time_limits[ix + 1] - 1),
                        )
                    )
                )
            end
        end
    end
    for c in con
        # Workaround to remove invalid key combinations
        filter!(x -> x.second !== nothing, c.data)
    end
    return
end

@doc raw"""

Constructs contraints that restricts devices to one type of start at a time

# Equations

``` sum(var_starts[name, s, t] for s in starts) = var_start[name, t]  ```

# LaTeX

``  \sum^{S_g}_{s=1} δ^{s}(t)  \eq  x^{start}(t) ``

"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{StartTypeConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, ThermalMultiStartUnitCommitment},
    ::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalMultiStart}
    time_steps = get_time_steps(container)
    varstart = get_variable(container, StartVariable, T)
    start_vars = [
        get_variable(container, HotStartVariable, T),
        get_variable(container, WarmStartVariable, T),
        get_variable(container, ColdStartVariable, T),
    ]

    device_name_set = PSY.get_name.(devices)
    con = add_constraints_container!(container, StartTypeConstraint,
        T,
        device_name_set,
        time_steps,
    )

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        startup_types = PSY.get_start_types(d)
        con[name, t] = JuMP.@constraint(
            get_jump_model(container),
            varstart[name, t] == sum(start_vars[ix][name, t] for ix in 1:(startup_types))
        )
    end
    return
end

@doc raw"""
Constructs contraints that restricts devices to one type of start at a time

# Equations
ub:
``` (time_limits[st+1]-1)*δ^{s}(t) + (1 - δ^{s}(t)) * M_VALUE >= sum(1-varbin[name, i]) for i in 1:t) + initial_condition_offtime  ```
lb:
``` (time_limits[st]-1)*δ^{s}(t) =< sum(1-varbin[name, i]) for i in 1:t) + initial_condition_offtime  ```

# LaTeX

`` TS^{s+1}_{g} δ^{s}(t) + (1-δ^{s}(t)) M_VALUE   \geq  \sum^{t}_{i=1} x^{status}(i)  +  DT_{g}^{0}  \forall t in \{1, \ldots,  TS^{s+1}_{g}``

`` TS^{s}_{g} δ^{s}(t) \leq  \sum^{t}_{i=1} x^{status}(i)  +  DT_{g}^{0}  \forall t in \{1, \ldots,  TS^{s+1}_{g}``

"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{StartupInitialConditionConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, ThermalMultiStartUnitCommitment},
    ::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalMultiStart}
    resolution = get_resolution(container)
    initial_conditions_offtime =
        get_initial_condition(container, InitialTimeDurationOff(), PSY.ThermalMultiStart)

    time_steps = get_time_steps(container)
    device_name_set = [IOM.get_component_name(ic) for ic in initial_conditions_offtime]
    varbin = get_variable(container, OnVariable, T)
    varstarts = [
        get_variable(container, HotStartVariable, T),
        get_variable(container, WarmStartVariable, T),
    ]

    con_ub = add_constraints_container!(container, StartupInitialConditionConstraint,
        T,
        device_name_set,
        time_steps,
        1:(MAX_START_STAGES - 1);
        sparse = true,
        meta = "ub",
    )
    con_lb = add_constraints_container!(container, StartupInitialConditionConstraint,
        T,
        device_name_set,
        time_steps,
        1:(MAX_START_STAGES - 1);
        sparse = true,
        meta = "lb",
    )

    for t in time_steps, (ix, ic) in enumerate(initial_conditions_offtime)
        name = IOM.get_component_name(ic)
        startup_types = PSY.get_start_types(IOM.get_component(ic))
        time_limits = _convert_hours_to_timesteps(
            PSY.get_start_time_limits(IOM.get_component(ic)),
            resolution,
        )
        ic = initial_conditions_offtime[ix]
        for st in 1:(startup_types - 1)
            var = varstarts[st]
            if t < (time_limits[st + 1] - 1)
                con_ub[name, t, st] = JuMP.@constraint(
                    get_jump_model(container),
                    (time_limits[st + 1] - 1) * var[name, t] +
                    (1 - var[name, t]) * M_VALUE >=
                    sum((1 - varbin[name, i]) for i in 1:t) + get_value(ic)
                )
                con_lb[name, t, st] = JuMP.@constraint(
                    get_jump_model(container),
                    time_limits[st] * var[name, t] <=
                    sum((1 - varbin[name, i]) for i in 1:t) + get_value(ic)
                )
            end
        end
    end
    for c in [con_ub, con_lb]
        # Workaround to remove invalid key combinations
        filter!(x -> x.second !== nothing, c.data)
    end
    return
end

# multi-start unit commitment: time duration constraints
function add_constraints!(
    container::OptimizationContainer,
    ::Type{DurationConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, ThermalMultiStartUnitCommitment},
    ::NetworkModel{<:AbstractNetworkModel},
) where {U <: PSY.ThermalGen}
    parameters = built_for_recurrent_solves(container)
    resolution = get_resolution(container)
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
            device_duration_compact_retrospective!(
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

# multi-start commitment
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{PSY.ThermalMultiStart},
    device_model::DeviceModel{PSY.ThermalMultiStart, U},
    ::Type{<:AbstractNetworkModel},
) where {U <: ThermalMultiStartUnitCommitment}
    add_variable_cost!(container, PowerAboveMinimumVariable, devices, U)
    for var_type in MULTI_START_VARIABLES
        add_start_up_cost!(container, var_type, devices, U)
    end
    add_shut_down_cost!(container, StopVariable, devices, U)
    add_proportional_cost!(container, OnVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
    end
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(device_model, sys)

    add_variables!(
        container,
        PowerAboveMinimumVariable,
        devices,
        ThermalMultiStartUnitCommitment,
    )
    add_variables!(
        container,
        ReactivePowerVariable,
        devices,
        ThermalMultiStartUnitCommitment,
    )
    add_variables!(container, OnVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, StopVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, StartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, ColdStartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, WarmStartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, HotStartVariable, devices, ThermalMultiStartUnitCommitment)

    add_variables!(container, TimeDurationOn, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, TimeDurationOff, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, PowerOutput, devices, ThermalMultiStartUnitCommitment)

    initial_conditions!(container, devices, ThermalMultiStartUnitCommitment())

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        OnVariable,
        devices,
        device_model,
        network_model,
    )

    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        PowerAboveMinimumVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalMultiStartUnitCommitment,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalMultiStartUnitCommitment,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(device_model, sys)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        device_model,
        network_model,
    )

    add_constraints!(
        container,
        ReactivePowerVariableLimitsConstraint,
        ReactivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, CommitmentConstraint, devices, device_model, network_model)
    add_constraints!(container, RampConstraint, devices, device_model, network_model)
    add_constraints!(container, DurationConstraint, devices, device_model, network_model)
    add_constraints!(
        container,
        StartupTimeLimitTemperatureConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, StartTypeConstraint, devices, device_model, network_model)
    add_constraints!(
        container,
        StartupInitialConditionConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActiveRangeICConstraint,
        devices,
        device_model,
        network_model,
    )

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_constraints!(
            container,
            ActivePowerVariableTimeSeriesLimitsConstraint,
            ActivePowerRangeExpressionUB,
            devices,
            device_model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, device_model, devices)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    devices = get_available_components(device_model, sys)

    add_variables!(
        container,
        PowerAboveMinimumVariable,
        devices,
        ThermalMultiStartUnitCommitment,
    )
    add_variables!(container, OnVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, StopVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, StartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, ColdStartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, WarmStartVariable, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, HotStartVariable, devices, ThermalMultiStartUnitCommitment)

    add_variables!(container, TimeDurationOn, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, TimeDurationOff, devices, ThermalMultiStartUnitCommitment)
    add_variables!(container, PowerOutput, devices, ThermalMultiStartUnitCommitment)

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )

    add_to_expression!(
        container,
        ActivePowerBalance,
        OnVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        PowerAboveMinimumVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        PowerAboveMinimumVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(
            container,
            RateofChangeConstraintSlackUp,
            devices,
            ThermalMultiStartUnitCommitment,
        )
        add_variables!(
            container,
            RateofChangeConstraintSlackDown,
            devices,
            ThermalMultiStartUnitCommitment,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{PSY.ThermalMultiStart, ThermalMultiStartUnitCommitment},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    devices = get_available_components(device_model, sys)

    initial_conditions!(container, devices, ThermalMultiStartUnitCommitment())

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        device_model,
        network_model,
    )

    add_constraints!(container, CommitmentConstraint, devices, device_model, network_model)
    add_constraints!(container, RampConstraint, devices, device_model, network_model)
    add_constraints!(container, DurationConstraint, devices, device_model, network_model)
    add_constraints!(
        container,
        StartupTimeLimitTemperatureConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(container, StartTypeConstraint, devices, device_model, network_model)
    add_constraints!(
        container,
        StartupInitialConditionConstraint,
        devices,
        device_model,
        network_model,
    )
    add_constraints!(
        container,
        ActiveRangeICConstraint,
        devices,
        device_model,
        network_model,
    )

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_constraints!(
            container,
            ActivePowerVariableTimeSeriesLimitsConstraint,
            ActivePowerRangeExpressionUB,
            devices,
            device_model,
            network_model,
        )
    end

    add_feedforward_constraints!(container, device_model, devices)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )
    add_event_constraints!(container, devices, device_model, network_model)
    add_constraint_dual!(container, sys, device_model)
    return
end

_param_to_vars(::Type{StartupCostParameter}, ::Type{ThermalMultiStartUnitCommitment}) =
    MULTI_START_VARIABLES
