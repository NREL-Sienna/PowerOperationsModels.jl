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
Parameter to define active power in time series
"""
struct ShiftUpActivePowerTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define active power in time series
"""
struct ShiftDownActivePowerTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define requirement time series
"""
struct RequirementTimeSeriesParameter <: TimeSeriesParameter end

"""
Abstract type for dynamic ratings of AC branches
"""
abstract type AbstractBranchRatingTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define the dynamic rating time series of a branch
"""
struct BranchRatingTimeSeriesParameter <:
       AbstractBranchRatingTimeSeriesParameter end

"""
Parameter to define the dynamic ratings time series of an AC branch for post-contingency condition
"""
struct PostContingencyBranchRatingTimeSeriesParameter <:
       AbstractBranchRatingTimeSeriesParameter end

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
# Hydro Parameters
#################################################################################

"""
Parameter to define energy storage target level time series for hydro generators
"""
struct EnergyTargetTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define energy budget time series for hydro generators
"""
struct EnergyBudgetTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define water storage target level time series for hydro reservoirs.
It will depend on the ReservoirDataType specified for the reservoir, and can be head in meters or volume in cubic meters.
"""
struct WaterTargetTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define water budget time series for hydro reservoirs.
The timeseries must be specified in average water flow in cubic meters per second.
"""
struct WaterBudgetTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define energy inflow to storage or reservoir time series
"""
struct InflowTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define energy outflow from storage or reservoir time series
"""
struct OutflowTimeSeriesParameter <: TimeSeriesParameter end

"""
Parameter to define energy capacity limits for hydro pump-turbine time series
"""
struct EnergyCapacityTimeSeriesParameter <: TimeSeriesParameter end

const DISTRIBUTION_FACTOR_TS_NAME = "distribution_factor"

"""
Per-bus distribution factors of a settlement location: the location owns one
`distribution_factor` time series per member bus, feature-keyed by `"bus" => bus number`.
Values are consumed as `Float64` constraint coefficients — never as JuMP parameters —
because they multiply cleared-quantity variables.
"""
struct DistributionFactorParameter <: TimeSeriesParameter end

"""
Reservoir energy target read from the system state
"""
struct ReservoirTargetParameter <: VariableValueParameter end
"""
Reservoir energy limit read from the system state
"""
struct ReservoirLimitParameter <: VariableValueParameter end

"""
Hydro energy usage limit read from the system state
"""
struct HydroUsageLimitParameter <: VariableValueParameter end

"""
Reservoir water usage budget read from the system state
"""
struct WaterLevelBudgetParameter <: VariableValueParameter end

"""
Reservoir level target read from the system state
"""
struct LevelTargetParameter <: VariableValueParameter end

#################################################################################
# Energy Storage Parameters
#################################################################################

"""
Parameter to define energy limit
"""
struct EnergyLimitParameter <: VariableValueParameter end
# TODO: Check if EnergyTargetParameter and EnergyLimitParameter should be removed
# This affects feedforwards that can break if not defined
struct EnergyTargetParameter <: VariableValueParameter end

convert_output_to_natural_units(::Type{EnergyLimitParameter}) = true
convert_output_to_natural_units(::Type{EnergyTargetParameter}) = true

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
# Hybrid System Parameters
#################################################################################

"Time-series parameter for the maximum active power available from a hybrid system's
renewable subcomponent, normalized by the renewable unit's `max_active_power` rating."
struct HybridRenewableActivePowerTimeSeriesParameter <: TimeSeriesParameter end

"Time-series parameter for a hybrid system's electric-load subcomponent demand,
normalized by the load's `max_active_power`."
struct HybridElectricLoadTimeSeriesParameter <: TimeSeriesParameter end

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
# Method extensions for convert_output_to_natural_units
#################################################################################

convert_output_to_natural_units(::Type{BranchRatingTimeSeriesParameter}) = true
convert_output_to_natural_units(
    ::Type{PostContingencyBranchRatingTimeSeriesParameter},
) = true
convert_output_to_natural_units(::Type{ActivePowerTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{ActivePowerOutTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{ActivePowerInTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{ReactivePowerTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{RequirementTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{UpperBoundValueParameter}) = true
convert_output_to_natural_units(::Type{LowerBoundValueParameter}) = true
convert_output_to_natural_units(::Type{ShiftUpActivePowerTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{ShiftDownActivePowerTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{ReservoirLimitParameter}) = true
convert_output_to_natural_units(::Type{ReservoirTargetParameter}) = true
convert_output_to_natural_units(::Type{EnergyTargetTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{EnergyBudgetTimeSeriesParameter}) = true
convert_output_to_natural_units(::Type{InflowTimeSeriesParameter}) = false
convert_output_to_natural_units(::Type{OutflowTimeSeriesParameter}) = false
convert_output_to_natural_units(::Type{HybridRenewableActivePowerTimeSeriesParameter}) =
    true
convert_output_to_natural_units(::Type{HybridElectricLoadTimeSeriesParameter}) = true
