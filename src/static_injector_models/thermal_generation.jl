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
    # Keyword form: the fixed and time-series fuel cost are separate, mutually
    # exclusive fields, so carry both through unchanged.
    return PSY.FuelCurve(;
        value_curve = PSY.PiecewisePointCurve(new_data),
        power_units = PSY.SU,
        fuel_cost = PSY.get_fuel_cost(original_cost_function),
        fuel_cost_time_series = IS.get_fuel_cost_time_series(original_cost_function),
        startup_fuel_offtake = IS.LinearCurve(0.0),  # default of 0
        vom_cost = PSY.get_vom_cost(original_cost_function),
    )
end

#! format: off

requires_initialization(::AbstractThermalFormulation) = false
requires_initialization(::AbstractThermalUnitCommitment) = true
requires_initialization(::ThermalStandardDispatch) = true
requires_initialization(::ThermalBasicCompactUnitCommitment) = false
requires_initialization(::ThermalBasicUnitCommitment) = false

get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = 1.0
# Per-device P_min multiplier computed inline at add_to_expression! call sites.
get_variable_multiplier(::Type{OnVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:Union{AbstractCompactUnitCommitment, ThermalCompactDispatch}}) = 1.0
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveUp}}) = ActivePowerRangeExpressionUB
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveDown}}) = ActivePowerRangeExpressionLB
# OfflineReserve (non-spin) is upward-only, so it reduces upward headroom like a ReserveUp product.
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.OfflineReserve}) = ActivePowerRangeExpressionUB
# Thermal UC formulations keep their UB expression gated on commitment only: offline awards
# enter through the static OfflineReserveBandConstraint instead of consuming that headroom.
offline_reserve_in_range_ub(::Type{<:AbstractThermalUnitCommitment}) = false

############## ActivePowerVariable, ThermalGen ####################
get_variable_binary(::Type{ActivePowerVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:AbstractThermalFormulation}) = false
get_variable_warm_start_value(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power(d, PSY.SU)
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_must_run(d) ? PSY.get_active_power_limits(d, PSY.SU).min : 0.0
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{ThermalDispatchNoMin}) = 0.0

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
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionUB}, d::PSY.ThermalGen, ::Type{ThermalCompactDispatch}) = PSY.get_active_power_limits(d, PSY.SU).max - PSY.get_active_power_limits(d, PSY.SU).min
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerRangeExpressionLB}, d::PSY.ThermalGen, ::Type{ThermalCompactDispatch}) = 0.0
get_expression_multiplier(::Type{OnStatusParameter}, ::Type{ActivePowerBalance}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}) = PSY.get_active_power_limits(d, PSY.SU).min

#################### Initial Conditions for models ###############
initial_condition_default(::DeviceStatus, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_status(d) ? 1.0 : 0.0
initial_condition_variable(::DeviceStatus, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()
initial_condition_default(::DevicePower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_active_power(d, PSY.SU)
initial_condition_variable(::DevicePower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = ActivePowerVariable()
initial_condition_default(::DeviceAboveMinPower, d::PSY.ThermalGen, ::AbstractThermalFormulation) = max(0.0, PSY.get_active_power(d, PSY.SU) - PSY.get_active_power_limits(d, PSY.SU).min)
initial_condition_variable(::DeviceAboveMinPower, d::PSY.ThermalGen, ::AbstractCompactUnitCommitment) = PowerAboveMinimumVariable()
initial_condition_variable(::DeviceAboveMinPower, d::PSY.ThermalGen, ::ThermalCompactDispatch) = PowerAboveMinimumVariable()
initial_condition_default(::InitialTimeDurationOn, d::PSY.ThermalGen, ::AbstractThermalFormulation) = PSY.get_status(d) ? PSY.get_time_at_status(d) : 0.0
initial_condition_variable(::InitialTimeDurationOn, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()
initial_condition_default(::InitialTimeDurationOff, d::PSY.ThermalGen, ::AbstractThermalFormulation) = !PSY.get_status(d) ? PSY.get_time_at_status(d) : 0.0
initial_condition_variable(::InitialTimeDurationOff, d::PSY.ThermalGen, ::AbstractThermalFormulation) = OnVariable()

########################Objective Function##################################################
# TODO: Decide what is the cost for OnVariable, if fixed or constant term in variable
function proportional_cost(container::OptimizationContainer, cost::PSY.ThermalGenerationCost, S::Type{OnVariable}, T::PSY.ThermalGen, U::Type{<:AbstractThermalFormulation}, t::Int)
    return onvar_cost(container, cost, S, T, U, t) + PSY.get_constant_term(PSY.get_vom_cost(PSY.get_variable_operation_cost(cost))) + PSY.get_fixed(cost)
end
# Is the OnVariable proportional term's *rate* time-varying? For ThermalGenerationCost
# that rate is `onvar_cost + vom_constant + fixed`; only `onvar_cost` can vary, and
# only for FuelCurve{Linear/Quadratic} (static or TS), where it equals
# `constant_term * fuel_cost_at_t`. PWL FuelCurves have `onvar_cost ≡ 0`, and
# CostCurves have no `_onvar_cost` overload — both statically invariant here.
IOM.is_time_variant_proportional(cost::PSY.ThermalGenerationCost) =
    _onvar_is_time_variant(PSY.get_variable_operation_cost(cost))

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
has_multistart_variables(::PSY.ThermalMultiStart, ::ThermalMultiStartUnitCommitment)=true

objective_function_multiplier(::Type{<:VariableType}, ::Type{<:AbstractThermalFormulation})=OBJECTIVE_FUNCTION_POSITIVE

# Startup cost interpretations!
# Validators: check that the types match (formulation is optional) and redirect to the simpler methods
start_up_cost(cost, ::Type{<:PSY.ThermalGen}, ::Type{T}, ::Type{<:Union{AbstractThermalFormulation, Nothing}} = Nothing) where {T <: StartVariable} =
    start_up_cost(cost, T)
start_up_cost(cost, ::Type{<:PSY.ThermalMultiStart}, ::Type{T}, ::Type{ThermalMultiStartUnitCommitment} = ThermalMultiStartUnitCommitment) where {T <: MultiStartVariable} =
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
uses_compact_power(::PSY.ThermalGen, ::ThermalCompactDispatch)=true

"""
Theoretical Cost at power output zero. Mathematically is the intercept with the y-axis
"""
function onvar_cost(container::OptimizationContainer, cost::PSY.ThermalGenerationCost, ::Type{OnVariable}, d::PSY.ThermalGen, ::Type{<:AbstractThermalFormulation}, t::Int)
    return _onvar_cost(container, PSY.get_variable_operation_cost(cost), d, t)
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
    if IS.is_time_series_backed(cost_function)
        parameter_array = get_parameter_array(container, FuelCostParameter, T)
        parameter_multiplier =
            get_parameter_multiplier_array(container, FuelCostParameter, T)
        name = PSY.get_name(d)
        return constant_term * parameter_array[name, t] * parameter_multiplier[name, t]
    else
        return constant_term * PSY.get_fuel_cost(cost_function)
    end
end

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
) where {T <: PSY.ThermalGen, D <: ThermalDispatchNoMin}
    return DeviceModel(T, ThermalDispatchNoMin)
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
Min and max active power limits of generators for thermal dispatch compact formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalCompactDispatch},
)
    return (
        min = 0.0,
        max = PSY.get_active_power_limits(device, PSY.SU).max -
              PSY.get_active_power_limits(device, PSY.SU).min,
    )
end

"""
Min and max active power limits of generators for thermal dispatch no minimum formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalDispatchNoMin},
)
    return (min = 0.0, max = PSY.get_active_power_limits(device, PSY.SU).max)
end

"""
Compact formulations schedule `PowerAboveMinimumVariable` rather than
`ActivePowerVariable`, so `has_semicontinuous_feedforward` must check a `SemiContinuousFeedforward`
against that variable instead of the default.
"""
_scheduled_power_variable(::Type{<:ThermalCompactDispatch}) = PowerAboveMinimumVariable
_scheduled_power_variable(::Type{<:AbstractCompactUnitCommitment}) =
    PowerAboveMinimumVariable

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
                !isnothing(init) && JuMP.set_start_value(variable[name, t], init)
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
    if !has_semicontinuous_feedforward(model, U)
        add_semicontinuous_range_constraints!(container, T, U, devices, model, X)
    end
    return
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
        # A must-run unit is in none of the On/Start/Stop containers: On is identically 1
        # and Start and Stop identically 0, so both start-up and shut-down ramp terms drop
        # out and the ceiling is the plain range.
        if PSY.get_must_run(device)
            for t in time_steps
                if JuMP.has_lower_bound(varp[name, t])
                    JuMP.set_lower_bound(varp[name, t], 0.0)
                end
                con_on[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    expression_products[name, t] <= limits.max - limits.min
                )
                if t != length(time_steps)
                    con_off[name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        expression_products[name, t] <= limits.max - limits.min
                    )
                end
            end
            continue
        end
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

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::ThermalCompactDispatch,
) where {T <: PSY.ThermalGen}
    add_initial_condition!(container, devices, formulation, DeviceAboveMinPower())
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
        # A must-run unit appears in neither the OnVariable container nor the
        # OnStatusParameter array — both are built from the non-must-run devices — while
        # the power axis above carries every device. Its commitment is fixed at 1.
        if PSY.get_must_run(d)
            for t in time_steps
                aux_variable_container[name, t] =
                    min + jump_value(p_variable_output[name, t])
            end
        else
            for t in time_steps
                aux_variable_container[name, t] =
                    jump_value(on_variable_output[name, t]) * min +
                    jump_value(p_variable_output[name, t])
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
_get_initial_condition_type(
    ::Type{RampConstraint},
    ::Type{<:PSY.ThermalGen},
    ::Type{ThermalCompactDispatch},
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

# compact dispatch ramping limits: linear with PowerAboveMinimumVariable.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, ThermalCompactDispatch},
    ::NetworkModel{V},
) where {U <: PSY.ThermalGen, V <: AbstractNetworkModel}
    add_linear_ramp_constraints!(container, T, PowerAboveMinimumVariable, devices, model, V)
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
        filter!(x -> !isnothing(x.second), c.data)
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
        filter!(x -> !isnothing(x.second), c.data)
    end
    return
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
        # A must-run unit never starts or stops, so its up/down durations are vacuous —
        # and it is in none of the On/Start/Stop containers the duration constraints
        # index, so including it here is a KeyError, not a redundant constraint.
        if PSY.get_must_run(g)
            @debug "Generator $(name) is must-run. Duration constraints skipped"
            continue
        end
        if !isnothing(time_limits)
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

# compact dispatch
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ThermalGen, U <: ThermalCompactDispatch}
    add_variable_cost!(container, PowerAboveMinimumVariable, devices, U)
    if get_use_slacks(device_model)
        add_proportional_cost!(container, RateofChangeConstraintSlackUp, devices, U)
        add_proportional_cost!(container, RateofChangeConstraintSlackDown, devices, U)
    end
    return
end

# can't have multi-start with ThermalDispatchNoMin.
function add_to_objective_function!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{PSY.ThermalMultiStart},
    ::DeviceModel{PSY.ThermalMultiStart, ThermalDispatchNoMin},
    ::Type{<:AbstractNetworkModel},
)
    throw(
        IS.ConflictingInputsError(
            "ThermalDispatchNoMin cost function is not compatible with ThermalMultiStart Devices.",
        ),
    )
end

"""
Add PWL cost terms for ThermalDispatchNoMin formulation.
Rejects non-convex or negative-slope PWL data since ThermalDispatchNoMin
cannot use SOS-2 formulations.
"""
function IOM.add_pwl_term_lambda!(
    container::IOM.OptimizationContainer,
    component::T,
    cost_function::Union{
        PSY.CostCurve{PSY.PiecewisePointCurve},
        PSY.FuelCurve{PSY.PiecewisePointCurve},
    },
    ::Type{U},
    ::Type{V},
) where {T <: PSY.ThermalGen, U <: IOM.VariableType, V <: ThermalDispatchNoMin}
    name = PSY.get_name(component)
    value_curve = PSY.get_value_curve(cost_function)
    cost_component = PSY.get_function_data(value_curve)
    base_power = IOM.get_model_base_power(container)
    device_base_power = PSY.get_base_power(component, PSY.NU)
    power_units = PSY.get_power_units(cost_function)

    # Normalize data
    data = IOM.get_piecewise_pointcurve_per_system_unit(
        cost_component,
        power_units,
        base_power,
        device_base_power,
    )
    @debug "PWL cost function detected for device $(name) using $V"
    slopes = PSY.get_slopes(data)
    if any(slopes .< 0) || !PSY.is_convex(data)
        throw(
            IS.InvalidValue(
                "The PWL cost data provided for generator $(name) is not compatible with $U.",
            ),
        )
    end

    # Compact PWL data does not exist anymore
    x_coords = PSY.get_x_coords(data)
    if x_coords[1] != 0.0
        y_coords = PSY.get_y_coords(data)
        x_first = round(x_coords[1]; digits = 3)
        y_first = round(y_coords[1]; digits = 3)
        slope_first = round(slopes[1]; digits = 3)
        guess_y_zero = y_coords[1] - slopes[1] * x_coords[1]
        @warn(
            "PWL has no 0.0 intercept for generator $(name). First point is given at (x = $(x_first), y = $(y_first)). Adding a first intercept at (x = 0.0, y = $(round(guess_y_zero, digits = 3)) to have equal initial slope $(slope_first)"
        )
        if guess_y_zero < 0.0
            error(
                "Added zero intercept has negative cost for generator $(name). Consider using other formulation or improve data.",
            )
        end
        intercept_point = (x = 0.0, y = guess_y_zero + IOM.COST_EPSILON)
        data = PSY.PiecewiseLinearData(vcat(intercept_point, PSY.get_points(data)))
        @assert PSY.is_convex(data)
    end

    time_steps = IOM.get_time_steps(container)
    pwl_cost_expressions = Vector{JuMP.AffExpr}(undef, time_steps[end])
    break_points = PSY.get_x_coords(data)
    sos_val = IOM._get_sos_value(container, V, component)
    temp_cost_function =
        create_temporary_cost_function_in_system_per_unit(cost_function, data)
    for t in time_steps
        IOM.add_pwl_variables_lambda!(container, T, name, t, data)
        power_var = IOM.get_variable(container, U, T)[name, t]
        IOM._add_pwl_constraint_standard!(
            container,
            component,
            break_points,
            sos_val,
            t,
            power_var,
        )
        pwl_cost =
            IOM.get_pwl_cost_expression_lambda(
                container,
                component,
                t,
                temp_cost_function,
                U,
                V,
            )
        pwl_cost_expressions[t] = pwl_cost
    end
    return pwl_cost_expressions
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

"""
Offline-capability band row for thermal-UC devices contributing to an `OfflineReserve`.
The commitment-gated UB expression excludes the offline awards
([`offline_reserve_in_range_ub`](@ref)); this row adds them back against the
formulation's gated capacity when committed, or the static `q_limit = pmax` when not:

`p + online + offline <= q_limit - (q_limit - gated) * u`

where `gated = get_min_max_limits(d, ActivePowerVariableLimitsConstraint, W).max` is the
same headroom the semicontinuous range row gates on: `pmax` for standard UC (the reduction
term vanishes, leaving `pmax`) and `pmax - pmin` for compact UC (giving `pmax - pmin * u`).
A must-run device is always committed, so its band is `gated` outright.

Committed: offline competes with the online products for the gated band. Off: the
semi-continuous UB row zeroes `p` and the online awards, leaving `offline <= pmax`.
Devices contributing to no offline service get no row.
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{OfflineReserveBandConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ThermalGen,
    W <: AbstractThermalUnitCommitment,
    X <: AbstractNetworkModel,
}
    # (service name, award variable, contributing member names) per offline service attached
    # to the device model; the ServiceModel's contributing map carries both.
    offline = Tuple{String, IOM.JuMPArray, Set{String}}[]
    for sm in get_services(model)
        _is_offline_reserve(get_component_type(sm)) || continue
        variable =
            get_variable(container, ActivePowerReserveVariable, get_component_type(sm))
        for (service_name, dev_map) in get_contributing_devices_map(sm)
            members = get(dev_map, V, nothing)
            isnothing(members) && continue
            push!(offline, (service_name, variable, Set(PSY.get_name.(members))))
        end
    end
    isempty(offline) && return
    time_steps = get_time_steps(container)
    expression = get_expression(container, ActivePowerRangeExpressionUB, V)
    jump_model = get_jump_model(container)
    varbin = get_variable(container, OnVariable, V)
    names = [PSY.get_name(d) for d in devices]
    constraint =
        add_constraints_container!(container, T, V, names, time_steps; sparse = true)
    for d in devices
        name = PSY.get_name(d)
        awards = [(sname, v) for (sname, v, members) in offline if name in members]
        isempty(awards) && continue
        q_limit = PSY.get_active_power_limits(d, PSY.SU).max
        gated = IOM.get_min_max_limits(d, ActivePowerVariableLimitsConstraint, W).max
        if PSY.get_must_run(d)
            for t in time_steps
                constraint[(name, t)] = JuMP.@constraint(
                    jump_model,
                    expression[name, t] +
                    sum(v[(sname, name, t)] for (sname, v) in awards) <= gated
                )
            end
        else
            for t in time_steps
                u = varbin[name, t]
                constraint[(name, t)] = JuMP.@constraint(
                    jump_model,
                    expression[name, t] +
                    sum(v[(sname, name, t)] for (sname, v) in awards) <=
                    q_limit - (q_limit - gated) * u
                )
            end
        end
    end
    return
end
