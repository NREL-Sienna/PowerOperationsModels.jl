function create_temporary_cost_function_in_system_per_unit(
    original_cost_function::PSY.CostCurve,
    new_data::PSY.PiecewiseLinearData,
)
    return PSY.CostCurve(
        PSY.PiecewisePointCurve(new_data),
        PSY.SU,
        PSY.get_vom_cost(original_cost_function),
    )
end

function create_temporary_cost_function_in_system_per_unit(
    original_cost_function::PSY.FuelCurve,
    new_data::PSY.PiecewiseLinearData,
)
    return PSY.FuelCurve(
        PSY.PiecewisePointCurve(new_data),
        PSY.SU,
        PSY.get_fuel_cost(original_cost_function),
        IS.LinearCurve(0.0),  # setting fuel offtake cost to default value of 0
        PSY.get_vom_cost(original_cost_function),
    )
end
#! format: off

requires_initialization(::AbstractThermalFormulation) = false
requires_initialization(::AbstractThermalUnitCommitment) = true

get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = 1.0
# Per-device P_min multiplier computed inline at add_to_expression! call sites.
get_variable_multiplier(::Type{OnVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:Union{AbstractCompactUnitCommitment, ThermalCompactDispatch}}) = 1.0
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveUp}}) = ActivePowerRangeExpressionUB
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveDown}}) = ActivePowerRangeExpressionLB

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

########################### Parameter related set functions ################################
get_multiplier_value(::Type{ActivePowerTimeSeriesParameter}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_max_active_power(d, PSY.SU)
get_multiplier_value(::Type{<:TimeSeriesParameter}, d::PSY.ThermalGen, ::Type{FixedOutput}) = PSY.get_max_active_power(d, PSY.SU)
get_multiplier_value(::Type{FuelCostParameter}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 1.0
get_parameter_multiplier(::Type{<:VariableValueParameter}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 1.0
get_initial_parameter_value(::Type{<:VariableValueParameter}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = 1.0
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionUB}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionLB}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).min
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionUB}, d::PSY.ThermalGen, ::Type{<:AbstractCompactUnitCommitment}) = PSY.get_active_power_limits(d, PSY.SU).max - PSY.get_active_power_limits(d, PSY.SU).min
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionLB}, d::PSY.ThermalGen, ::Type{<:AbstractCompactUnitCommitment}) = 0.0
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerBalance}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).min

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

########################Objective Function##################################################
# TODO: Decide what is the cost for OnVariable, if fixed or constant term in variable
function proportional_cost(container::OptimizationContainer, cost::PSY.ThermalGenerationCost, S::Type{OnVariable}, T::PSY.ThermalGen, U::Type{<:AbstractThermalFormulation}, t::Int)
    return onvar_cost(container, cost, S, T, U, t) + PSY.get_constant_term(PSY.get_vom_cost(PSY.get_variable(cost))) + PSY.get_fixed(cost)
end
# Is the OnVariable proportional term's *rate* time-varying? For ThermalGenerationCost
# that rate is `onvar_cost + vom_constant + fixed`; only `onvar_cost` can vary, and
# only for FuelCurve{Linear/Quadratic} (static or TS), where it equals
# `constant_term * fuel_cost_at_t`. PWL FuelCurves have `onvar_cost ≡ 0`, and
# CostCurves have no `_onvar_cost` overload — both statically invariant here.
IOM.is_time_variant_proportional(cost::PSY.ThermalGenerationCost) =
    _onvar_is_time_variant(PSY.get_variable(cost))

_onvar_is_time_variant(::PSY.ProductionVariableCostCurve) = false
_onvar_is_time_variant(
    curve::PSY.FuelCurve{<:Union{
        PSY.LinearCurve, PSY.QuadraticCurve,
        PSY.TimeSeriesLinearCurve, PSY.TimeSeriesQuadraticCurve,
    }},
) = IS.is_time_series_backed(curve)

IOM.uses_commitment_variables(::Type{<:PSY.ThermalGen}) = true

# MarketBidCost (static + time-series) proportional_cost/is_time_variant_proportional are generic —
# see common_models/market_bid_overrides.jl.

proportional_cost(::Union{MBC_TYPES, PSY.ThermalGenerationCost}, ::Type{<:Union{RateofChangeConstraintSlackUp, RateofChangeConstraintSlackDown}}, ::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = CONSTRAINT_VIOLATION_SLACK_COST

has_multistart_variables(::PSY.ThermalGen, ::AbstractThermalFormulation)=false

objective_function_multiplier(::Type{<:VariableType}, ::Type{<:AbstractThermalFormulation})=OBJECTIVE_FUNCTION_POSITIVE

# Startup cost interpretations!
# Validators: check that the types match (formulation is optional) and redirect to the simpler methods
start_up_cost(cost, ::Type{<:PSY.ThermalGen}, ::Type{T}, ::Type{<:Union{AbstractThermalFormulation, Nothing}} = Nothing) where {T <: StartVariable} =
    start_up_cost(cost, T)

# Implementations: given a single number, tuple, or PSY.StartUpStages and a variable, do the right thing
# Single number to anything
start_up_cost(cost::Float64, ::Type{StartVariable}) = cost
# TODO in the case where we have a single number startup cost and we're modeling a multi-start, do we set all the values to that number?
start_up_cost(cost::Float64, ::Type{T}) where {T <: MultiStartVariable} =
    start_up_cost((hot = cost, warm = cost, cold = cost), T)

# 3-tuple to anything
start_up_cost(cost::NTuple{3, Float64}, ::Type{T}) where {T <: VariableType} =
    start_up_cost(PSY.StartUpStages(cost), T)

# `PSY.StartUpStages` to anything
start_up_cost(cost::PSY.StartUpStages, ::Type{ColdStartVariable}) = cost.cold
start_up_cost(cost::PSY.StartUpStages, ::Type{WarmStartVariable}) = cost.warm
start_up_cost(cost::PSY.StartUpStages, ::Type{HotStartVariable}) = cost.hot
# TODO in the opposite case, do we want to get the maximum or the hot?
start_up_cost(cost::PSY.StartUpStages, ::Type{StartVariable}) = maximum(cost)

uses_compact_power(::PSY.ThermalGen, ::AbstractThermalFormulation)=false
uses_compact_power(::PSY.ThermalGen, ::AbstractCompactUnitCommitment )=true

"""
Theoretical Cost at power output zero. Mathematically is the intercept with the y-axis
"""
function onvar_cost(container::OptimizationContainer, cost::PSY.ThermalGenerationCost, ::Type{OnVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}, t::Int)
    return _onvar_cost(container, PSY.get_variable(cost), d, t)
end

function _onvar_cost(::OptimizationContainer, cost_function::PSY.FuelCurve{PSY.PiecewisePointCurve}, d::PSY.ThermalGen, ::Int)
    # OnVariableCost is included in the Point itself for PiecewisePointCurve
    return 0.0
end

function _onvar_cost(::OptimizationContainer, cost_function::PSY.FuelCurve{PSY.PiecewiseIncrementalCurve}, d::PSY.ThermalGen, ::Int)
    # Input at min is used to transform to InputOutputCurve
    return 0.0
end

# this one implementation is thermal-specific, and requires the component.
# (well, really just the name of the component.)
function _onvar_cost(container::OptimizationContainer, cost_function::Union{PSY.FuelCurve{PSY.LinearCurve}, PSY.FuelCurve{PSY.QuadraticCurve}}, d::T, t::Int) where {T <: PSY.ThermalGen}
    value_curve = PSY.get_value_curve(cost_function)
    cost_component = PSY.get_function_data(value_curve)
    # In Unit/h
    constant_term = PSY.get_constant_term(cost_component)
    fuel_cost = PSY.get_fuel_cost(cost_function)
    if typeof(fuel_cost) <: Float64
        return constant_term * fuel_cost
    else
        parameter_array = get_parameter_array(container, FuelCostParameter, T)
        parameter_multiplier =
            get_parameter_multiplier_array(container, FuelCostParameter, T)
        name = PSY.get_name(d)
        return constant_term * parameter_array[name, t] * parameter_multiplier[name, t]
    end
end

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
#! format: on

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

function get_default_time_series_names(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ThermalGen, V <: Union{FixedOutput, AbstractThermalFormulation}}
    return Dict{Type{<:ParameterType}, String}(
        FuelCostParameter => "fuel_cost",
    )
end

# FixedOutput has no dispatch decision, so its output is driven entirely by time series
# rather than by the fuel cost the dispatchable formulations above consume.
function get_default_time_series_names(
    ::Type{<:PSY.ThermalGen},
    ::Type{FixedOutput},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        ActivePowerTimeSeriesParameter => "max_active_power",
        ReactivePowerTimeSeriesParameter => "max_active_power",
    )
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ThermalGen, V <: Union{FixedOutput, AbstractThermalFormulation}}
    return Dict{String, Any}()
end

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

# proportional cost: connects to common implementation in IOM
# The OnVariable `add_proportional_cost!` forwarder (thermal + hydro) lives in
# common_models/objective_function.jl.
skip_proportional_cost(d::PSY.ThermalGen) = get_must_run(d)

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

# regular commitment
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen, U <: AbstractThermalUnitCommitment}
    add_variable_cost!(container, ActivePowerVariable, devices, U)
    add_start_up_cost!(container, StartVariable, devices, U)
    add_shut_down_cost!(container, StopVariable, devices, U)
    add_proportional_cost!(container, OnVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
    end
    return
end

# compact commitment
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen, U <: AbstractCompactUnitCommitment}
    add_variable_cost!(container, PowerAboveMinimumVariable, devices, U)
    add_start_up_cost!(container, StartVariable, devices, U)
    add_shut_down_cost!(container, StopVariable, devices, U)
    add_proportional_cost!(container, OnVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
    end
    return
end

# regular dispatch
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen, U <: AbstractThermalDispatchFormulation}
    add_variable_cost!(container, ActivePowerVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
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
# TODO: Security constrained models implement the correct functions for the model
function has_security_arguments(device_model::DeviceModel)::Bool
    return true
end

# TODO: Security constrained models implement the correct functions for the model
function has_security_model(device_model::DeviceModel)::Bool
    return true
end

@inline function _handle_common_thermal_parameters!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T},
) where {T <: PSY.ThermalGen}
    if haskey(get_time_series_names(model), FuelCostParameter)
        add_parameters!(container, FuelCostParameter, devices, model)
    end

    process_market_bid_parameters!(container, devices, model)
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, FixedOutput},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)
    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerTimeSeriesParameter,
        devices,
        device_model,
        network_model,
    )
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, FixedOutput},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
    devices = get_available_components(device_model, sys)
    add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    add_parameters!(container, ReactivePowerTimeSeriesParameter, devices, device_model)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerTimeSeriesParameter,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ReactivePowerBalance,
        ReactivePowerTimeSeriesParameter,
        devices,
        device_model,
        network_model,
    )
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{<:PSY.ThermalGen, FixedOutput},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    # FixedOutput doesn't add any constraints to the model. This function covers
    # AbstractNetworkModel and AbtractActivePowerModel
    return
end

"""
This function creates the arguments for the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, D},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: PSY.ThermalGen,
    D <: AbstractStandardUnitCommitment,
}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, D)
    add_variables!(container, ReactivePowerVariable, devices, D)
    add_variables!(container, OnVariable, devices, D)
    add_variables!(container, StartVariable, devices, D)
    add_variables!(container, StopVariable, devices, D)

    add_variables!(container, TimeDurationOn, devices, D)
    add_variables!(container, TimeDurationOff, devices, D)

    initial_conditions!(container, devices, D())

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
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
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(container, RateofChangeConstraintSlackUp, devices, D)
        add_variables!(container, RateofChangeConstraintSlackDown, devices, D)
    end
    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

"""
This function creates the constraints for the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: PSY.ThermalGen,
    U <: AbstractStandardUnitCommitment,
}
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
    add_event_constraints!(container, devices, device_model, network_model)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )

    if has_security_arguments(device_model)
        # TODO: SecurityConstrainedModels Implemenation of G-1
        #add_constraints!(
        #    container,
        #    SecurityConstraint,
        #    devices,
        #    device_model,
        #    network_model,
        #)
    end

    add_constraint_dual!(container, sys, device_model)
    return
end

"""
This function creates the arguments model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, D},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen, D <: AbstractStandardUnitCommitment}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, D)
    add_variables!(container, OnVariable, devices, D)
    add_variables!(container, StartVariable, devices, D)
    add_variables!(container, StopVariable, devices, D)

    add_variables!(container, TimeDurationOn, devices, D)
    add_variables!(container, TimeDurationOff, devices, D)

    initial_conditions!(container, devices, D())

    if haskey(get_time_series_names(device_model), ActivePowerTimeSeriesParameter)
        add_parameters!(container, ActivePowerTimeSeriesParameter, devices, device_model)
    end

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(container, RateofChangeConstraintSlackUp, devices, D)
        add_variables!(container, RateofChangeConstraintSlackDown, devices, D)
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

"""
This function creates the constraints for the model for a full thermal dispatch formulation depending on combination of devices, device_formulation and system_formulation
"""
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, <:AbstractStandardUnitCommitment},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
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

    add_constraints!(container, CommitmentConstraint, devices, device_model, network_model)
    add_constraints!(container, RampConstraint, devices, device_model, network_model)
    add_constraints!(container, DurationConstraint, devices, device_model, network_model)
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
    device_model::DeviceModel{T, D},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: PSY.ThermalGen,
    D <: AbstractThermalDispatchFormulation,
}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, D)
    add_variables!(container, ReactivePowerVariable, devices, D)

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
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
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(container, RateofChangeConstraintSlackUp, devices, D)
        add_variables!(container, RateofChangeConstraintSlackDown, devices, D)
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, <:AbstractThermalDispatchFormulation},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen}
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
    device_model::DeviceModel{T, D},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    T <: PSY.ThermalGen,
    D <: AbstractThermalDispatchFormulation,
}
    devices = get_available_components(device_model, sys)

    add_variables!(container, ActivePowerVariable, devices, D)

    _handle_common_thermal_parameters!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    add_cost_expressions!(container, devices, device_model)

    add_to_expression!(
        container,
        ActivePowerRangeExpressionLB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        ActivePowerRangeExpressionUB,
        ActivePowerVariable,
        devices,
        device_model,
        network_model,
    )
    add_to_expression!(
        container,
        FuelConsumptionExpression,
        ActivePowerVariable,
        devices,
        device_model,
    )
    if get_use_slacks(device_model)
        add_variables!(container, RateofChangeConstraintSlackUp, devices, D)
        add_variables!(container, RateofChangeConstraintSlackDown, devices, D)
    end

    add_feedforward_arguments!(container, device_model, devices)
    add_event_arguments!(container, devices, device_model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, <:AbstractThermalDispatchFormulation},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {T <: PSY.ThermalGen}
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

    add_feedforward_constraints!(container, device_model, devices)
    add_event_constraints!(container, devices, device_model, network_model)

    add_to_objective_function!(
        container,
        devices,
        device_model,
        get_network_formulation(network_model),
    )
    return
end

"""
Thermal generators get the full constituent decomposition. Constituent expressions
auto-propagate into `ProductionCostExpression` (see IOM `_propagate_to_production_cost!`),
so we register the aggregate as well as the parts. `FuelConsumptionExpression` is added
only when at least one device has a `FuelCurve`, mirroring the existing FuelConsumption
specialization.
"""
function add_cost_expressions!(
    container::OptimizationContainer,
    devices::U,
    model::DeviceModel{D, W},
) where {
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractThermalFormulation,
} where {D <: PSY.ThermalGen}
    time_steps = get_time_steps(container)
    n = length(devices)
    all_names = Vector{String}(undef, n)
    fuel_names = sizehint!(String[], n)
    has_quad_fuel = false
    for (i, d) in enumerate(devices)
        name = PSY.get_name(d)
        all_names[i] = name
        fuel_curve = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(fuel_curve) || continue
        push!(fuel_names, name)
        if !has_quad_fuel
            has_quad_fuel = _value_curve_is_quadratic(PSY.get_value_curve(fuel_curve))
        end
    end
    if !isempty(fuel_names)
        expr_type = has_quad_fuel ? JuMP.QuadExpr : GAE
        add_expression_container!(
            container, FuelConsumptionExpression, D, fuel_names, time_steps;
            expr_type = expr_type,
        )
    end
    add_expression_container!(container, ProductionCostExpression, D, all_names, time_steps)
    add_expression_container!(container, FuelCostExpression, D, all_names, time_steps)
    add_expression_container!(container, StartUpCostExpression, D, all_names, time_steps)
    add_expression_container!(container, ShutDownCostExpression, D, all_names, time_steps)
    add_expression_container!(container, FixedCostExpression, D, all_names, time_steps)
    add_expression_container!(container, VOMCostExpression, D, all_names, time_steps)
    return
end

_param_to_vars(::Type{StartupCostParameter}, ::Type{<:AbstractThermalFormulation}) =
    (StartVariable,)

_param_to_vars(::Type{ShutdownCostParameter}, ::Type{<:AbstractThermalFormulation}) =
    (StopVariable,)

#################################################################################
# _add_parameters! for OnStatusParameter (ThermalGen-specific)
#################################################################################
function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    key::VariableKey{U, D},
    model::DeviceModel{D, W},
    devices::V,
) where {
    T <: OnStatusParameter,
    U <: OnVariable,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractThermalFormulation,
} where {D <: PSY.ThermalGen}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices if !PSY.get_must_run(device)]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(container, T, D, key, names, time_steps)
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    # Iterate the same filtered view used to construct `names` so enumeration index
    # `i` lines up with the parameter container's first axis.
    for (i, d) in enumerate(Iterators.filter(d -> !PSY.get_must_run(d), devices))
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        if get_variable_warm_start_value(U, d, W) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U, d, W)
        end
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, inital_parameter_value, i, t)
        end
    end
    return
end

"""
Add a compact unit-commitment `OnVariable` scaled by per-device `p_min`, with no must-run
branch (matches PSI; the `On` variable carries the `p_min` scale). Used by the CopperPlate
and PTDF compact-UC methods.
"""
function _add_pmin_scaled_on_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnVariable, V <: PSY.ThermalGen, W}
    variable = get_variable(container, U, V)
    base_multiplier = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = PSY.get_active_power_limits(d, PSY.SU).min * base_multiplier
        for t in time_steps
            _apply_term_to_targets!(targets, variable[name, t], multiplier, t)
        end
    end
    return
end

"""
Add a compact unit-commitment `OnVariable` to a balance expression. Must-run units
have `On ≡ 1`, so their `p_min` contribution enters as a constant; all others
contribute `p_min * get_variable_multiplier(U, V, W) * On[name, t]`. Targets come from
[`_balance_expression_targets`](@ref), so this is correct for every network model
(nodal, area, system, PTDF).
"""
function _add_compact_on_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnVariable, V <: PSY.ThermalGen, W}
    variable = get_variable(container, U, V)
    base_multiplier = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = PSY.get_active_power_limits(d, PSY.SU).min * base_multiplier
        if PSY.get_must_run(d)
            # On ≡ 1 for must-run units, so the term is the constant p_min * mult.
            for t in time_steps
                _apply_term_to_targets!(targets, 1.0, multiplier, t)
            end
        else
            for t in time_steps
                _apply_term_to_targets!(targets, variable[name, t], multiplier, t)
            end
        end
    end
    return
end

"""
Add a thermal `OnStatusParameter` to a balance expression with the device-specific
`get_expression_multiplier(U, T, d, W)`, targets from
[`_balance_expression_targets`](@ref).
"""
function _add_onstatus_parameter_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnStatusParameter, V <: PSY.ThermalGen, W}
    parameter = get_parameter_array(container, U, V)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = get_expression_multiplier(U, T, d, W)
        for t in time_steps
            _apply_term_to_targets!(targets, parameter[name, t], multiplier, t)
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    _add_onstatus_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
}
    _add_compact_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
    X <: AbstractNetworkModel,
}
    _add_compact_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: Union{AbstractCompactUnitCommitment, ThermalCompactDispatch},
}
    _add_compact_on_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    _add_onstatus_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
}
    # No must-run branch here (matches PSI); the On variable carries the P_min scale.
    _add_pmin_scaled_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
    X <: AbstractPTDFNetworkModel,
}
    parameter = get_parameter_array(container, U, V)
    sys_expr = get_expression(container, T, PSY.System)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_ = PSY.get_number(PSY.get_bus(d))
        bus_no = PNM.get_mapped_bus_number(network_reduction, bus_no_)
        mult = get_expression_multiplier(U, T, d, W)
        device_bus = PSY.get_bus(d)
        ref_index = _ref_index(network_model, device_bus)
        for t in time_steps
            add_proportional_to_jump_expression!(
                sys_expr[ref_index, t],
                parameter[name, t],
                mult,
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                parameter[name, t],
                mult,
            )
        end
    end
    return
end

# The on variables are included in the system balance expressions becuase they
# are multiplied by the Pmin and the active power is not the total active power
# but the power above minimum.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
    X <: PTDFNetworkModel,
}
    # No must-run branch here (matches PSI); the On variable carries the P_min scale.
    _add_pmin_scaled_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::U,
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: Union{ActivePowerRangeExpressionUB, ActivePowerRangeExpressionLB},
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractThermalDispatchFormulation,
}
    parameter_array = get_parameter_array(container, U, V)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices
        if PSY.get_must_run(d)
            continue
        end
        name = PSY.get_name(d)
        mult = get_expression_multiplier(U, T, d, W)
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[name, t],
                parameter_array[name, t],
                -mult,
            )
        end
    end
    return
end

# Per-device fuel consumption term builders, dispatched on the value-curve type so the
# decision of how to translate the curve into JuMP terms is a method-resolution problem
# rather than a runtime branch.

# LinearCurve fuel: linear in the dispatch variable. Routes through the IOM helper
# so the propagation rules (FuelConsumptionExpression is non-ConstituentCost, so the
# objective hook is skipped here) live in one place.
function _add_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{C},
    variable,
    name::String,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.LinearCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {C <: PSY.ThermalGen}
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    rate = prop_term_per_unit * dt
    for t in time_steps
        IOM.add_cost_term_to_expression!(
            container, variable[name, t], rate,
            FuelConsumptionExpression, C, name, t,
        )
    end
    return
end

# QuadraticCurve fuel: quadratic in the dispatch variable. The shape doesn't fit the
# `quantity * rate` form, so the cost is built locally and added with `JuMP.add_to_expression!`.
function _add_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{C},
    variable,
    name::String,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.QuadraticCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {C <: PSY.ThermalGen}
    expression = get_expression(container, FuelConsumptionExpression, C)
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    quadratic_term = PSY.get_quadratic_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    quad_term_per_unit = get_quadratic_cost_per_system_unit(
        quadratic_term, power_units, base_power, device_base_power)
    for t in time_steps
        fuel_expr =
            (
                variable[name, t] .^ 2 * quad_term_per_unit +
                variable[name, t] * prop_term_per_unit
            ) * dt
        JuMP.add_to_expression!(expression[name, t], fuel_expr)
    end
    return
end

# Piecewise/incremental/average-rate value curves are populated through their own
# objective paths; no contribution to FuelConsumptionExpression here.
_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.PiecewisePointCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.IncrementalCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.AverageRateCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: FuelConsumptionExpression,
    U <: ActivePowerVariable,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U, V)
    time_steps = get_time_steps(container)
    base_power = get_model_base_power(container)
    resolution = get_resolution(container)
    dt = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    for d in devices
        var_cost = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(var_cost) || continue
        name = PSY.get_name(d)
        device_base_power = PSY.get_base_power(d, PSY.NU)
        value_curve = PSY.get_value_curve(var_cost)
        _add_fuel_consumption_term!(
            container, V, variable, name, var_cost, value_curve,
            base_power, device_base_power, dt, time_steps,
        )
    end
end

# Compact formulation: dispatch variable is "above-minimum"; constant P_min term is
# added per-time-step, gated by the SOS status (no_variable / parameter / variable).
function _add_compact_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{W},
    expression,
    variable,
    d::V,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.LinearCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {V <: PSY.ThermalGen, W <: AbstractDeviceFormulation}
    name = PSY.get_name(d)
    P_min = PSY.get_active_power_limits(d, PSY.SU).min
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    on_var_type = typeof(get_default_on_variable(d))
    for t in time_steps
        sos_status = _get_sos_value(container, W, d)
        bin = IOM._determine_bin_lhs(
            container, sos_status, V, name, t; on_var_type = on_var_type,
        )
        JuMP.add_to_expression!(
            expression[name, t], P_min * prop_term_per_unit * dt, bin)
        JuMP.add_to_expression!(
            expression[name, t], prop_term_per_unit * dt, variable[name, t])
    end
    return
end

# Compact formulation does not accept QuadraticCurve fuel — the SOS gating breaks down
# for quadratic terms.
_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{W}, _, _, ::PSY.ThermalGen, ::PSY.FuelCurve,
    ::PSY.QuadraticCurve, ::Float64, ::Float64, ::Float64, _,
) where {W <: AbstractDeviceFormulation} =
    error("Quadratic Curves are not accepted with Compact Formulation: $W")

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.PiecewisePointCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.IncrementalCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.AverageRateCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: FuelConsumptionExpression,
    U <: PowerAboveMinimumVariable,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U, V)
    time_steps = get_time_steps(container)
    base_power = get_model_base_power(container)
    resolution = get_resolution(container)
    dt = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    for d in devices
        var_cost = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(var_cost) || continue
        expression = get_expression(container, T, V)
        device_base_power = PSY.get_base_power(d, PSY.NU)
        value_curve = PSY.get_value_curve(var_cost)
        _add_compact_fuel_consumption_term!(
            container, W, expression, variable, d, var_cost, value_curve,
            base_power, device_base_power, dt, time_steps,
        )
    end
end

function add_variable_cost_to_objective!(
    ::OptimizationContainer,
    ::T,
    component::PSY.Component,
    cost_function::PSY.CostCurve{IS.QuadraticCurve},
    ::U,
) where {
    T <: PowerAboveMinimumVariable,
    U <: Union{AbstractCompactUnitCommitment, ThermalCompactDispatch},
}
    throw(
        IS.ConflictingInputsError(
            "Quadratic Cost Curves are not compatible with Compact formulations",
        ),
    )
    return
end

#################################################################################
# Section 2: _consider_parameter — compact commitment startup
# Compact/multi-start formulations have HotStart/WarmStart/ColdStart variables
# in addition to the normal StartVariable.
#################################################################################
_consider_parameter(
    ::Type{StartupCostParameter},
    container::OptimizationContainer,
    ::DeviceModel{T, D},
) where {T, D <: AbstractCompactUnitCommitment} =
    any(has_container_key.([container], [StartVariable, MULTI_START_VARIABLES...], [T]))

#################################################################################
# Section 3: Device-specific validate_occ_component
#################################################################################

# ThermalMultiStart: accept NTuple{3, Float64} and PSY.StartUpStages without warning
function IOM.validate_occ_component(
    ::Type{StartupCostParameter},
    device::PSY.ThermalMultiStart,
)
    startup = PSY.get_start_up(PSY.get_operation_cost(device))
    # TupleTimeSeries{PSY.StartUpStages} guarantees NTuple{3, Float64} values at construction
    startup isa IS.TupleTimeSeries && return
    _validate_eltype(
        Union{Float64, NTuple{3, Float64}, PSY.StartUpStages},
        device,
        startup,
        " startup cost",
    )
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
