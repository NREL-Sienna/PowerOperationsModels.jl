# POM-specific expression types
# Base expression types (SystemBalanceExpressions, CostExpressions, etc.) are imported from IOM

# POM-specific concrete types
struct ComponentReserveUpBalanceExpression <: ExpressionType end
struct ComponentReserveDownBalanceExpression <: ExpressionType end
struct InterfaceTotalFlow <: ExpressionType end
struct PTDFBranchFlow <: ExpressionType end

"""
Branch active-power flow expression for the B-θ (DC) network model: `b·(θ_from - θ_to - shift)`,
with the DC susceptance `b = 1/(tap·x)` and the DC phase shift.
Under `DCPNetworkModel` with `StaticBranch` the flow is this expression (not a decision
variable); `FlowRateConstraint` rows are written directly on it. Reportable as an output,
mirroring `PTDFBranchFlow`.
"""
struct BThetaBranchFlow <: ExpressionType end
struct PostContingencyNodalActivePowerDeployment <: PostContingencyExpressions end
struct RealizedShiftedLoad <: ExpressionType end

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
# Energy Storage / Hybrid Reserve Aggregation Expressions
#
# A single parametric family covers both the hybrid PCC boundary aggregation
# (HybridPCCReserveExpression) and the storage-subcomponent balance aggregation
# (StorageReserveBalanceExpression). The three axes are:
#   D <: ReserveDirection : Up | Down
#   S <: ReserveScale     : UnscaledReserve (multiplier 1.0)
#                         | DeployedReserve (multiplier = get_deployed_fraction(s))
#   Sd <: ReserveSide     : DischargeSide   (PCC "Out" / storage "Discharge")
#                         | ChargeSide      (PCC "In"  / storage "Charge")
#################################################################################

"""
Per-device, per-service aggregation of the reserve quantity offered by a storage device
(or the storage subcomponent of a hybrid system). One container is created per service
participated in, and the per-component reserve variables (charging + discharging) are
summed into it. Consumed by [`HybridReserveBalanceConstraint`](@ref) and used as the
right-hand side of the system-level reserve balance.
"""
struct TotalReserveOffering <: ExpressionType end

abstract type ReserveAggregationExpression{
    D <: PSY.ReserveDirection,
    S <: ReserveScale,
    Sd <: ReserveSide,
} <: ExpressionType end

"""
Hybrid-boundary aggregation of reserve quantities offered through the discharge (out) and
charge (in) sides of a `PSY.HybridSystem`.
"""
struct HybridPCCReserveExpression{D, S, Sd} <:
       ReserveAggregationExpression{D, S, Sd} end

"""
Aggregation of reserve variables allocated to the storage subcomponent of a hybrid system
(or a standalone storage device).
"""
struct StorageReserveBalanceExpression{D, S, Sd} <:
       ReserveAggregationExpression{D, S, Sd} end

# Method extensions for output writing
should_write_resulting_value(::Type{InterfaceTotalFlow}) = true
should_write_resulting_value(::Type{PTDFBranchFlow}) = true
should_write_resulting_value(::Type{BThetaBranchFlow}) = true
should_write_resulting_value(::Type{RealizedShiftedLoad}) = true

should_write_resulting_value(::Type{HydroServedReserveUpExpression}) = true
should_write_resulting_value(::Type{HydroServedReserveDownExpression}) = true
should_write_resulting_value(::Type{TotalHydroFlowRateReservoirOutgoing}) = true
should_write_resulting_value(::Type{TotalHydroFlowRateTurbineOutgoing}) = true

should_write_resulting_value(::Type{<:StorageReserveBalanceExpression}) = true
should_write_resulting_value(
    ::Type{HybridPCCReserveExpression{D, DeployedReserve, Sd}},
) where {D <: PSY.ReserveDirection, Sd <: ReserveSide} = true

# Method extensions for unit conversion
convert_output_to_natural_units(::Type{InterfaceTotalFlow}) = true
convert_output_to_natural_units(::Type{PostContingencyBranchFlow}) = true
convert_output_to_natural_units(::Type{PTDFBranchFlow}) = true
convert_output_to_natural_units(::Type{BThetaBranchFlow}) = true
convert_output_to_natural_units(::Type{RealizedShiftedLoad}) = true
