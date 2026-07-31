#! format: off
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
#! format: on

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
