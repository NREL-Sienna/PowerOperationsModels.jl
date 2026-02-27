# POM-specific expression types
# Base expression types (SystemBalanceExpressions, CostExpressions, etc.) are imported from IOM

# POM-specific abstract type for post-contingency system balance expressions
abstract type PostContingencySystemBalanceExpressions <: SystemBalanceExpressions end

# POM-specific concrete types
struct PostContingencyActivePowerBalance <: PostContingencySystemBalanceExpressions end
struct ComponentReserveUpBalanceExpression <: ExpressionType end
struct ComponentReserveDownBalanceExpression <: ExpressionType end
struct InterfaceTotalFlow <: ExpressionType end
struct PTDFBranchFlow <: ExpressionType end
struct PostContingencyNodalActivePowerDeployment <: PostContingencyExpressions end

#################################################################################
# Hydro Expressions
#################################################################################

"""
Expression for [`PowerSystems.HydroGen`](@extref) that keep track
of served reserve up for energy calculations
"""
struct HydroServedReserveUpExpression <: ExpressionType end

"""
Expression for [`PowerSystems.HydroGen`](@extref) that keep track
of served reserve down for energy calculations
"""
struct HydroServedReserveDownExpression <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir](@extref) that keep track
of total power into a reservoir, from all the upstream turbines connected to it
"""
struct TotalHydroPowerReservoirIncoming <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir](@extref) that keep track
of total power out of a reservoir, from all the downstream turbines connected to it
"""
struct TotalHydroPowerReservoirOutgoing <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir](@extref) that keep track
of total spillage power into a reservoir, from all the upstream reservoirs connected to it
"""
struct TotalSpillagePowerReservoirIncoming <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir`](@extref) that keep track
of total water flow turbined into a reservoir, from all the upstream turbines connected to it
"""
struct TotalHydroFlowRateReservoirIncoming <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir`](@extref) that keep track
of total water turbined for a reservoir, from all the downstream turbines connected to it
"""
struct TotalHydroFlowRateReservoirOutgoing <: ExpressionType end

"""
Expression for [`PowerSystems.HydroReservoir](@extref) that keep track
of total spillage water flow rate into a reservoir, from all the upstream reservoirs connected to it
"""
struct TotalSpillageFlowRateReservoirIncoming <: ExpressionType end

"""
Expression for [`PowerSystems.HydroGen`](@extref) that keep track
of total water turbined for a turbine, coming from multiple reservoirs
"""
struct TotalHydroFlowRateTurbineOutgoing <: ExpressionType end

"""
Expression for [`PowerSystems.System`](@extref) that keep track
of the energy balance for the system in medium term planning
"""
struct EnergyBalanceExpression <: ExpressionType end

#################################################################################
# Energy Storage Expressions
#################################################################################

struct TotalReserveOffering <: ExpressionType end

abstract type StorageReserveDischargeExpression <: ExpressionType end
abstract type StorageReserveChargeExpression <: ExpressionType end

# Used for the Power Limits constraints
struct ReserveAssignmentBalanceUpDischarge <: StorageReserveDischargeExpression end
struct ReserveAssignmentBalanceUpCharge <: StorageReserveChargeExpression end
struct ReserveAssignmentBalanceDownDischarge <: StorageReserveDischargeExpression end
struct ReserveAssignmentBalanceDownCharge <: StorageReserveChargeExpression end

# Used for the SoC estimates
struct ReserveDeploymentBalanceUpDischarge <: StorageReserveDischargeExpression end
struct ReserveDeploymentBalanceUpCharge <: StorageReserveChargeExpression end
struct ReserveDeploymentBalanceDownDischarge <: StorageReserveDischargeExpression end
struct ReserveDeploymentBalanceDownCharge <: StorageReserveChargeExpression end

# Method extensions for result writing
should_write_resulting_value(::Type{InterfaceTotalFlow}) = true
should_write_resulting_value(::Type{PTDFBranchFlow}) = true

should_write_resulting_value(::Type{HydroServedReserveUpExpression}) = true
should_write_resulting_value(::Type{HydroServedReserveDownExpression}) = true
should_write_resulting_value(::Type{TotalHydroFlowRateReservoirOutgoing}) = true
should_write_resulting_value(::Type{TotalHydroFlowRateTurbineOutgoing}) = true

should_write_resulting_value(::Type{StorageReserveDischargeExpression}) = true
should_write_resulting_value(::Type{StorageReserveChargeExpression}) = true

# Method extensions for unit conversion
convert_result_to_natural_units(::Type{InterfaceTotalFlow}) = true
convert_result_to_natural_units(::Type{PostContingencyBranchFlow}) = true
convert_result_to_natural_units(::Type{PostContingencyActivePowerGeneration}) = true
convert_result_to_natural_units(::Type{PTDFBranchFlow}) = true
