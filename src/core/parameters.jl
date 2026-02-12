#################################################################################
# Parameter Type Definitions
# Following the pattern of variables.jl, expressions.jl, constraints.jl:
# - Abstract types
# - Concrete singleton structs
# - 1-line method extensions
#################################################################################

#################################################################################
# Time Series Parameters
#################################################################################

"""
Parameter to define active power time series
"""
struct ActivePowerTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define reactive power time series
"""
struct ReactivePowerTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define active power out time series
"""
struct ActivePowerOutTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define active power in time series
"""
struct ActivePowerInTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define requirement time series
"""
struct RequirementTimeSeriesParameter <: TimeSeriesParameter end

"""
Abstract type for dynamic ratings of AC branches
"""
abstract type AbstractDynamicBranchRatingTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define the dynamic rating time series of a branch
"""
struct DynamicBranchRatingTimeSeriesParameter <:
       AbstractDynamicBranchRatingTimeSeriesParameter end

"""
Parameter to define the dynamic ratings time series of an AC branch for post-contingency condition
"""
struct PostContingencyDynamicBranchRatingTimeSeriesParameter <:
       AbstractDynamicBranchRatingTimeSeriesParameter end

"""
Parameter to define Flow From_To limit time series
"""
struct FromToFlowLimitParameter <: TimeSeriesParameter end

"""
Parameter to define Flow To_From limit time series
"""
struct ToFromFlowLimitParameter <: TimeSeriesParameter end

"""
Parameter to define Max Flow limit for interface time series
"""
struct MaxInterfaceFlowLimitParameter <: TimeSeriesParameter end

"""
Parameter to define Min Flow limit for interface time series
"""
struct MinInterfaceFlowLimitParameter <: TimeSeriesParameter end

#################################################################################
# Variable Value Parameters
#################################################################################

# VariableValueParameter: moved into IOM.

"""
Parameter to define variable upper bound
"""
struct UpperBoundValueParameter <: VariableValueParameter end

"""
Parameter to define variable lower bound
"""
struct LowerBoundValueParameter <: VariableValueParameter end

# OnStatusParameter: moved into IOM.

# FixValueParameter: moved into IOM.

#################################################################################
# Objective Function Parameters
#################################################################################

"""
Parameter to define cost function coefficient
"""
struct CostFunctionParameter <: ObjectiveFunctionParameter end

# startup, shutdown, fuel cost parameters: in IOM
# Offer curve parameter types (CostAtMin, PiecewiseLinearSlope, PiecewiseLinearBreakpoint): moved into IOM

#################################################################################
# Auxiliary Variable Value Parameters
#################################################################################

abstract type AuxVariableValueParameter <: RightHandSideParameter end

#################################################################################
# Event Parameters
#################################################################################

# EventParameter: moved into IOM.

"""
Parameter to define component availability status updated from the system state
"""
struct AvailableStatusParameter <: EventParameter end

"""
Parameter to define active power offset during an event.
"""
struct ActivePowerOffsetParameter <: EventParameter end

"""
Parameter to define reactive power offset during an event.
"""
struct ReactivePowerOffsetParameter <: EventParameter end

"""
Parameter to record that the component changed in the availability status
"""
struct AvailableStatusChangeCountdownParameter <: EventParameter end

#################################################################################
# Method extensions for should_write_resulting_value
#################################################################################

should_write_resulting_value(::Type{<:RightHandSideParameter}) = true
should_write_resulting_value(::Type{<:EventParameter}) = true

should_write_resulting_value(::Type{<:FuelCostParameter}) = true
should_write_resulting_value(::Type{<:ShutdownCostParameter}) = true
should_write_resulting_value(::Type{<:AbstractCostAtMinParameter}) = true
should_write_resulting_value(::Type{<:AbstractPiecewiseLinearSlopeParameter}) = true
should_write_resulting_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}) = true

#################################################################################
# Method extensions for convert_result_to_natural_units
#################################################################################

convert_result_to_natural_units(::Type{DynamicBranchRatingTimeSeriesParameter}) = true
convert_result_to_natural_units(
    ::Type{PostContingencyDynamicBranchRatingTimeSeriesParameter},
) = true
convert_result_to_natural_units(::Type{ActivePowerTimeSeriesParameter}) = true
convert_result_to_natural_units(::Type{ReactivePowerTimeSeriesParameter}) = true
convert_result_to_natural_units(::Type{RequirementTimeSeriesParameter}) = true
convert_result_to_natural_units(::Type{UpperBoundValueParameter}) = true
convert_result_to_natural_units(::Type{LowerBoundValueParameter}) = true
