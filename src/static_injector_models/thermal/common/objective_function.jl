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
#! format: on

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
