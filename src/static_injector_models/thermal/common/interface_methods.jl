#! format: off
requires_initialization(::AbstractThermalFormulation) = false
requires_initialization(::AbstractThermalUnitCommitment) = true

get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveUp}}) = ActivePowerRangeExpressionUB
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ThermalGen}, ::Type{<:PSY.Reserve{PSY.ReserveDown}}) = ActivePowerRangeExpressionLB
#! format: on

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

# TODO: Security constrained models implement the correct functions for the model
function has_security_arguments(device_model::DeviceModel)::Bool
    return true
end

# TODO: Security constrained models implement the correct functions for the model
function has_security_model(device_model::DeviceModel)::Bool
    return true
end
