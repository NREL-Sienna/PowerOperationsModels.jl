#################################################################################
# Variable types defined in POM
# Types used by IOM's infrastructure code (ActivePowerVariable, OnVariable, etc.)
# come from IOM via `using InfrastructureOptimizationModels`.
# Only POM-specific types are defined here.
#################################################################################

# POM-specific abstract types (matching PSI hierarchy)
abstract type MultiStartVariable <: VariableType end
abstract type AbstractACActivePowerFlow <: VariableType end
abstract type AbstractACReactivePowerFlow <: VariableType end
# AbstractPiecewiseLinearBlockOffer: moved into IOM

"""
Struct to dispatch the creation of Hot Start Variable for Thermal units with temperature considerations

Docs abbreviation: ``z^\\text{th}``
"""
struct HotStartVariable <: MultiStartVariable end

"""
Struct to dispatch the creation of Warm Start Variable for Thermal units with temperature considerations

Docs abbreviation: ``y^\\text{th}``
"""
struct WarmStartVariable <: MultiStartVariable end

"""
Struct to dispatch the creation of Cold Start Variable for Thermal units with temperature considerations

Docs abbreviation: ``x^\\text{th}``
"""
struct ColdStartVariable <: MultiStartVariable end

"""
Struct to dispatch the creation of a variable for energy storage level (state of charge)

Docs abbreviation: ``e``
"""
struct EnergyVariable <: VariableType end

struct LiftVariable <: VariableType end

"""
Struct to dispatch the creation of Reactive Power Variables

Docs abbreviation: ``q``
"""
struct ReactivePowerVariable <: VariableType end

"""
Continuous shunt susceptance ``b`` (pu on system MVA base) dispatched by
[`ShuntSusceptanceDispatch`](@ref) for `PSY.SwitchedAdmittance` and
`PSY.FACTSControlDevice`. Bounded by the device susceptance range: for
`SwitchedAdmittance`, the base susceptance plus the achievable block increment span
(continuous relaxation of discrete steps); for `FACTSControlDevice`, the per-unit
conversion of `max_shunt_current`. Enters [`ShuntReactivePowerConstraint`](@ref) as
``Q = b \\cdot V^2``. Only valid under AC network models.

Docs abbreviation: ``b``
"""
struct ShuntSusceptanceVariable <: VariableType end

"""
Continuous off-nominal turns ratio ``t \\in [t_{\\min}, t_{\\max}]`` (pu) for a
transformer circuit whose control objective is modeled. The variable enters the AC π-model
Ohm's law nonlinearly: self terms scale as ``1/t^2``, coupling terms scale as ``1/t``,
so the formulation reduces to `StaticBranch` when ``t = t_m`` (the nominal tap).
Warm-started at the transformer's current tap position. Both bounds must be finite and
positive (validated at construction time). Only valid under AC network models.

Docs abbreviation: ``t``
"""
struct TapRatioVariable <: VariableType end

# ReservationVariable: moved to IOM (used in range_constraint.jl)

"""
Struct to dispatch the creation of Active Power Reserve Variables

Docs abbreviation: ``r``
"""
struct ActivePowerReserveVariable <: VariableType end

struct SteadyStateFrequencyDeviation <: VariableType end

struct AreaMismatchVariable <: VariableType end

struct DeltaActivePowerUpVariable <: VariableType end

struct DeltaActivePowerDownVariable <: VariableType end

struct AdditionalDeltaActivePowerUpVariable <: VariableType end

struct AdditionalDeltaActivePowerDownVariable <: VariableType end

struct SmoothACE <: VariableType end

"""
Struct to dispatch the creation of System-wide slack up variables. Used when there is not enough generation.

Docs abbreviation: ``p^\\text{sl,up}``
"""
struct SystemBalanceSlackUp <: VariableType end

"""
Struct to dispatch the creation of System-wide slack down variables. Used when there is not enough load curtailment.

Docs abbreviation: ``p^\\text{sl,dn}``
"""
struct SystemBalanceSlackDown <: VariableType end

"""
Struct to dispatch the creation of Reserve requirement slack variables. Used when there is not reserves in the system to satisfy the requirement.

Docs abbreviation: ``r^\\text{sl}``
"""
struct ReserveRequirementSlack <: VariableType end

struct ServiceRequirementVariable <: VariableType end

"""
Struct to dispatch the creation of Voltage Magnitude Variables for AC formulations

Docs abbreviation: ``v``
"""
struct VoltageMagnitude <: VariableType end

"""
Struct to dispatch the creation of Voltage Angle Variables for AC/DC formulations

Docs abbreviation: ``\\theta``
"""
struct VoltageAngle <: VariableType end

"""
Component-owned auxiliary voltage-magnitude variable used to regulate a bus voltage
under rectangular AC formulations (ACR/IVR), which expose no scalar magnitude primitive.
Keyed by the regulating component name and scoped to that component's regulated bus, it is
bounded by the regulated bus's voltage limits and tied to the bus by
`RegulatedVoltageMagnitudeConstraint` (`vm_reg² == vr² + vi²`). Only created under ACR/IVR;
under ACP the network `VoltageMagnitude` is regulated directly.

Docs abbreviation: ``v^\\text{reg}``
"""
struct RegulatedVoltageMagnitude <: VariableType end

"""
Struct to dispatch the creation of Voltage Real-Component Variables for rectangular-coordinate AC formulations

Docs abbreviation: ``v_r``
"""
struct VoltageReal <: VariableType end

"""
Struct to dispatch the creation of Voltage Imaginary-Component Variables for rectangular-coordinate AC formulations

Docs abbreviation: ``v_i``
"""
struct VoltageImaginary <: VariableType end

"""
Struct to dispatch the creation of Voltage-Magnitude Deviation Variables (`phi = |V| - 1`)
for the LPAC formulation, indexed by bus.

Docs abbreviation: ``\\phi``
"""
struct VoltageDeviation <: VariableType end

"""
Struct to dispatch the creation of bus-pair Cosine Approximation Variables (`cs`) for the
LPAC formulation, indexed by branch.

Docs abbreviation: ``cs``
"""
struct CosineApproximation <: VariableType end

#########################################
####### IVR Branch Current Variables ####
#########################################

# Abstract parent for all six IVR branch current variable types; enables a single
# parametric add_variables! dispatch instead of six @eval-generated copies.
abstract type AbstractBranchCurrentVariable <: VariableType end

"""
Real component of the from-terminal branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_r^{fr}``
"""
struct BranchCurrentFromToReal <: AbstractBranchCurrentVariable end

"""
Imaginary component of the from-terminal branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_i^{fr}``
"""
struct BranchCurrentFromToImaginary <: AbstractBranchCurrentVariable end

"""
Real component of the to-terminal branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_r^{to}``
"""
struct BranchCurrentToFromReal <: AbstractBranchCurrentVariable end

"""
Imaginary component of the to-terminal branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_i^{to}``
"""
struct BranchCurrentToFromImaginary <: AbstractBranchCurrentVariable end

"""
Real component of the series (through-impedance) branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_{sr}``
"""
struct BranchSeriesCurrentReal <: AbstractBranchCurrentVariable end

"""
Imaginary component of the series (through-impedance) branch current in the IVR formulation,
indexed by (branch_name, t). Bounded ±(rate_a / vmin).

Docs abbreviation: ``c_{si}``
"""
struct BranchSeriesCurrentImaginary <: AbstractBranchCurrentVariable end

#########################################
###### Power Load Shift Variables #######
#########################################

"""
Struct to dispatch the creation of Shifted Up Active Power Variables
Docs abbreviation: ``p^\\text{shift,up}``
"""
struct ShiftUpActivePowerVariable <: VariableType end

"""
Struct to dispatch the creation of Shifted Down Active Power Variables
Docs abbreviation: ``p^\\text{shift,dn}``
"""
struct ShiftDownActivePowerVariable <: VariableType end

#########################################
####### DC Converter Variables ##########
#########################################

"""
Struct to dispatch the variable of DC Current Variables for DC Lines formulations
Docs abbreviation: ``i_l^{dc}``
"""
struct DCLineCurrent <: VariableType end

"""
Struct to dispatch the creation of DC Converter Current Variables for DC formulations
Docs abbreviation: ``i_c^{dc}``
"""
struct ConverterCurrent <: VariableType end

"""
Non-negative LP surrogate for the absolute value of a DC current variable
(`abs_i ≥ i`, `abs_i ≥ -i`, `abs_i ≥ 0`; tight at optimum because the loss
term `b · abs_i` is minimized via the generation-cost objective). Used by
both two-terminal HVDC links (cable current) and interconnecting converters.
Docs abbreviation: ``|i|^{dc}``
"""
struct CurrentAbsoluteValueVariable <: VariableType end

"""
Non-negative AC apparent current ``I_{ac} = \\sqrt{p^2 + q^2}/|V_{ac}|`` at the AC
terminal of an `InterconnectingConverter` under an AC network model. The converter
loss is parameterized on this current (instead of the DC cable current) so reactive
loading incurs loss. Defined by ``I_{ac}^2 \\, V_{ac}^2 = p^2 + q^2``.
Docs abbreviation: ``i_c^{ac}``
"""
struct ConverterACCurrentVariable <: VariableType end

"""
Non-negative AC apparent current at the from-terminal of a `TwoTerminalVSCLine`
under an AC network model: ``I_{ac,f}^2 \\, V_{ac,f}^2 = p_{ft}^2 + q_f^2``.
Docs abbreviation: ``i_f^{ac}``
"""
struct ConverterACCurrentFromVariable <: VariableType end

"""
Non-negative AC apparent current at the to-terminal of a `TwoTerminalVSCLine`
under an AC network model: ``I_{ac,t}^2 \\, V_{ac,t}^2 = p_{tf}^2 + q_t^2``.
Docs abbreviation: ``i_t^{ac}``
"""
struct ConverterACCurrentToVariable <: VariableType end

#########################################################
#########################################################

"""
Struct to dispatch the creation of bidirectional Active Power Flow Variables

Docs abbreviation: ``f``
"""
struct FlowActivePowerVariable <: AbstractACActivePowerFlow end

# This Variable Type doesn't make sense since there are no lossless NetworkModels with ReactivePower.
# struct FlowReactivePowerVariable <: VariableType end

"""
Struct to dispatch the creation of unidirectional Active Power Flow Variables

Docs abbreviation: ``f^\\text{from-to}``
"""
struct FlowActivePowerFromToVariable <: AbstractACActivePowerFlow end

"""
Struct to dispatch the creation of unidirectional Active Power Flow Variables

Docs abbreviation: ``f^\\text{to-from}``
"""
struct FlowActivePowerToFromVariable <: AbstractACActivePowerFlow end

"""
Struct to dispatch the creation of unidirectional Reactive Power Flow Variables

Docs abbreviation: ``f^\\text{q,from-to}``
"""
struct FlowReactivePowerFromToVariable <: AbstractACReactivePowerFlow end

"""
Struct to dispatch the creation of unidirectional Reactive Power Flow Variables

Docs abbreviation: ``f^\\text{q,to-from}``
"""
struct FlowReactivePowerToFromVariable <: AbstractACReactivePowerFlow end

"""
Struct to dispatch the creation of active power flow upper bound slack variables. Used when there is not enough flow through the branch in the forward direction.

Docs abbreviation: ``f^\\text{sl,up}``
"""
struct FlowActivePowerSlackUpperBound <: AbstractACActivePowerFlow end

"""
Struct to dispatch the creation of active power flow lower bound slack variables. Used when there is not enough flow through the branch in the reverse direction.

Docs abbreviation: ``f^\\text{sl,lo}``
"""
struct FlowActivePowerSlackLowerBound <: AbstractACActivePowerFlow end

"""
Struct to dispatch the creation of post-contingency active power flow upper bound slack variables. Relaxes the post-contingency (N-1) emergency-rate upper-bound constraint when `use_slacks = true`.

Docs abbreviation: ``f^\\text{sl,up,N-1}``
"""
struct PostContingencyFlowActivePowerSlackUpperBound <: VariableType end

"""
Struct to dispatch the creation of post-contingency active power flow lower bound slack variables. Relaxes the post-contingency (N-1) emergency-rate lower-bound constraint when `use_slacks = true`.

Docs abbreviation: ``f^\\text{sl,lo,N-1}``
"""
struct PostContingencyFlowActivePowerSlackLowerBound <: VariableType end

"""
Struct to dispatch the creation of Phase Shifters Variables

Docs abbreviation: ``\\theta^\\text{shift}``
"""
struct PhaseShifterAngle <: VariableType end

# Necessary as a work around for HVDCTwoTerminal models with losses
"""
Struct to dispatch the creation of HVDC Losses Auxiliary Variables

Docs abbreviation: ``\\ell``
"""
struct HVDCLosses <: VariableType end

"""
Struct to dispatch the creation of HVDC Flow Direction Auxiliary Variables

Docs abbreviation: ``u^\\text{dir}``
"""
struct HVDCFlowDirectionVariable <: VariableType end

"""
Struct to dispatch the creation of HVDC Received Flow at From Bus Variables for
[`HVDCTwoTerminalPiecewiseLoss`](@ref). Injection convention: enters the
from-bus `ActivePowerBalance` with +1.0 (an injection at its own terminal).

Docs abbreviation: ``x``
"""
struct HVDCActivePowerReceivedFromVariable <: VariableType end

"""
Struct to dispatch the creation of HVDC Received Flow at To Bus Variables for
[`HVDCTwoTerminalPiecewiseLoss`](@ref). Injection convention: enters the
to-bus `ActivePowerBalance` with +1.0 (an injection at its own terminal).

Docs abbreviation: ``y``
"""
struct HVDCActivePowerReceivedToVariable <: VariableType end

"""
Rectifier AC-side active power draw of a `TwoTerminalLCCLine` under
[`HVDCTwoTerminalLCC`](@ref), in p.u. (system base). Positive when the line
transfers power from -> to; enters the from-bus `ActivePowerBalance` with -1.0
(a withdrawal).
"""
struct HVDCRectifierActivePowerVariable <: VariableType end

"""
Inverter AC-side active power delivery of a `TwoTerminalLCCLine` under
[`HVDCTwoTerminalLCC`](@ref), in p.u. (system base). Positive when the line
transfers power from -> to; enters the to-bus `ActivePowerBalance` with +1.0
(an injection).
"""
struct HVDCInverterActivePowerVariable <: VariableType end

"""
Rectifier AC-side reactive power consumption of a `TwoTerminalLCCLine` under
[`HVDCTwoTerminalLCC`](@ref), in p.u. (system base). Consumed at the from bus
(-1.0 in `ReactivePowerBalance`).
"""
struct HVDCRectifierReactivePowerVariable <: VariableType end

"""
Inverter AC-side reactive power consumption of a `TwoTerminalLCCLine` under
[`HVDCTwoTerminalLCC`](@ref), in p.u. (system base). Consumed at the to bus
(-1.0 in `ReactivePowerBalance`).
"""
struct HVDCInverterReactivePowerVariable <: VariableType end

"""
Struct to define the creation of HVDC Rectifier Delay Angle Variable

Docs abbreviation: ``\\alpha^r``
"""
struct HVDCRectifierDelayAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC Inverter Extinction Angle Variable

Docs abbreviation: ``\\gamma^i``
"""
struct HVDCInverterExtinctionAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC Rectifier Power Factor Angle Variable

Docs abbreviation: ``\\phi^r``
"""
struct HVDCRectifierPowerFactorAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC Inverter Power Factor Angle Variable

Docs abbreviation: ``\\phi^i``
"""
struct HVDCInverterPowerFactorAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC Rectifier Overlap Angle Variable

Docs abbreviation: ``\\mu^r``
"""
struct HVDCRectifierOverlapAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC Inverter Overlap Angle Variable

Docs abbreviation: ``\\mu^i``
"""
struct HVDCInverterOverlapAngleVariable <: VariableType end

"""
Struct to define the creation of HVDC DC Line Voltage at Rectifier Side

Docs abbreviation: ``\\v_{d}^r``
"""
struct HVDCRectifierDCVoltageVariable <: VariableType end

"""
Struct to define the creation of HVDC DC Line Voltage at Inverter Side

Docs abbreviation: ``\\v_{d}^i``
"""
struct HVDCInverterDCVoltageVariable <: VariableType end

"""
Struct to define the creation of HVDC AC Line Current flowing into the AC side of Rectifier

Docs abbreviation: ``\\i_{ac}^r``
"""
struct HVDCRectifierACCurrentVariable <: VariableType end

"""
Struct to define the creation of HVDC AC Line Current flowing into the AC side of Inverter

Docs abbreviation: ``\\i_{ac}^i``
"""
struct HVDCInverterACCurrentVariable <: VariableType end

"""
Struct to define the creation of HVDC DC Line Current Flow

Docs abbreviation: ``\\i_{d}``
"""
struct DCLineCurrentFlowVariable <: VariableType end

"""
Struct to define the creation of HVDC Tap Setting at Rectifier Transformer

Docs abbreviation: ``\\t^r``
"""
struct HVDCRectifierTapSettingVariable <: VariableType end

"""
Struct to define the creation of HVDC Tap Setting at Inverter Transformer

Docs abbreviation: ``\\t^i``
"""
struct HVDCInverterTapSettingVariable <: VariableType end

"""
Block-offer delta variable for a per-device ancillary-service (reserve) OFFER. Sparse, keyed
`(service_name, device_name, segment, time)` - the 4D `(service, device, segment, time)` cost
structure on top of the 3D `(service, device, time)` reserve award `ActivePowerReserveVariable`.
"""
struct PiecewiseLinearBlockReserveOffer <: SparseVariableType end

# Widen the auto-created sparse container to the 4D reserve-offer key. The IOM default is the
# 3D device-offer shape `(device, segment, time)`; this adds the leading service axis.
IOM.sparse_variable_key_type(::Type{PiecewiseLinearBlockReserveOffer}) =
    Tuple{String, String, Int, Int}

"""
Struct to dispatch the creation of HVDC Piecewise Loss Variables

Docs abbreviation: ``h`` or ``w``
"""
struct HVDCPiecewiseLossVariable <: SparseVariableType end

"""
Struct to dispatch the creation of HVDC Piecewise Binary Loss Variables

Docs abbreviation: ``z``
"""
struct HVDCPiecewiseBinaryLossVariable <: SparseVariableType end

"""
DC-side voltage at the from-terminal of a two-terminal HVDC link.
Used by the `HVDCTwoTerminalVSC` formulation.
Docs abbreviation: ``v_f^{dc}``
"""
struct HVDCFromDCVoltage <: VariableType end

"""
DC-side voltage at the to-terminal of a two-terminal HVDC link.
Used by the `HVDCTwoTerminalVSC` formulation.
Docs abbreviation: ``v_t^{dc}``
"""
struct HVDCToDCVoltage <: VariableType end

"""
Reactive power injected at the from-terminal AC bus by a two-terminal HVDC link.
Added only when the formulation runs on an AC network model.
Docs abbreviation: ``q_f``
"""
struct HVDCReactivePowerFromVariable <: VariableType end

"""
Reactive power injected at the to-terminal AC bus by a two-terminal HVDC link.
Added only when the formulation runs on an AC network model.
Docs abbreviation: ``q_t``
"""
struct HVDCReactivePowerToVariable <: VariableType end

"""
Struct to dispatch the creation of Interface Flow Slack Up variables

Docs abbreviation: ``f^\\text{sl,up}``
"""
struct InterfaceFlowSlackUp <: VariableType end
"""
Struct to dispatch the creation of Interface Flow Slack Down variables

Docs abbreviation: ``f^\\text{sl,dn}``
"""
struct InterfaceFlowSlackDown <: VariableType end

"""
Struct to dispatch the creation of Slack variables that relax an `UpperBoundFeedforward`
constraint, penalized in the objective at `BALANCE_SLACK_COST`

Docs abbreviation: ``p^\\text{ff,ubsl}``
"""
struct UpperBoundFeedForwardSlack <: VariableType end
"""
Struct to dispatch the creation of Slack variables that relax a `LowerBoundFeedforward`
constraint, penalized in the objective at `BALANCE_SLACK_COST`

Docs abbreviation: ``p^\\text{ff,lbsl}``
"""
struct LowerBoundFeedForwardSlack <: VariableType end

#################################################################################
# Hydro Variables
#################################################################################

"""
Struct to dispatch the creation of energy (water) spillage variable representing energy released from a storage/reservoir not injected into the network

Docs abbreviation: ``s``
"""
struct WaterSpillageVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for energy storage levels < target storage levels

Docs abbreviation: ``e^\\text{shortage}``
"""
struct HydroEnergyShortageVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for energy storage levels > target storage levels

Docs abbreviation: ``e^\\text{surplus}``
"""
struct HydroEnergySurplusVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for shortage on balance constraints

Docs abbreviation: ``e^\\text{b,shortage}``
"""
struct HydroBalanceShortageVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for surplus on balance constraints

Docs abbreviation: ``e^\\text{b,surplus}``
"""
struct HydroBalanceSurplusVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for water storage levels < target storage levels

Docs abbreviation: ``l^\\text{shortage}``
"""
struct HydroWaterShortageVariable <: VariableType end

"""
Struct to dispatch the creation of a slack variable for water storage levels > target storage levels

Docs abbreviation: ``l^\\text{surplus}``
"""
struct HydroWaterSurplusVariable <: VariableType end

"""
Struct to dispatch the creation of a variable for turbined flow rate (in m3/s).
"""
struct HydroTurbineFlowRateVariable <: VariableType end

"""
Struct to dispatch the creation of a variable for volume stored in a hydro reservoir (in m3).
"""
struct HydroReservoirVolumeVariable <: VariableType end

"""
Aux variable which keeps track of water level (head) of hydro reservoirs (in m)
"""
struct HydroReservoirHeadVariable <: VariableType end

"""
Struct to dispatch the creation of a variable for pumped power in a hydro pump turbine (in MWh).
"""
struct ActivePowerPumpVariable <: VariableType end

"""
Auxiliary Variable for Hydro Models that solve for total energy output

Docs abbreviation: ``E^\\text{hy,out}``
"""
struct HydroEnergyOutput <: AuxVariableType end

#################################################################################
# Energy Storage Variables
#################################################################################

"""
Ancillary service fraction assigned to Storage Discharging to product p

Docs abbreviation: ``sb^{std}_{p,t}``
"""
struct AncillaryServiceVariableDischarge <: VariableType end

"""
Ancillary service fraction assigned to Storage Charging to product p

Docs abbreviation: ``sb^{stc}_{p,t}``
"""
struct AncillaryServiceVariableCharge <: VariableType end

"""
Slack variable for energy storage levels < target storage levels

Docs abbreviation: ``e^{st-}``
"""
struct StorageEnergyShortageVariable <: VariableType end

"""
Slack variable for energy storage levels > target storage levels

Docs abbreviation: ``e^{st+}``
"""
struct StorageEnergySurplusVariable <: VariableType end

"""
Slack variable for the cycling limits to allow for more charging usage than the allowed limited

Docs nomenclature: ``c^{ch-}``
"""
struct StorageChargeCyclingSlackVariable <: VariableType end

"""
Slack variable for the cycling limits to allow for more discharging usage than the allowed limited

Docs nomenclature: ``c^{ds-}``
"""
struct StorageDischargeCyclingSlackVariable <: VariableType end

"""
Abstract used for StorageRegularization variables
"""
abstract type StorageRegularizationVariable <: VariableType end

"""
Slack variable for energy storage levels > target storage levels

Docs nomenclature: ``z^{st, ch}``
"""
struct StorageRegularizationVariableCharge <: StorageRegularizationVariable end

"""
Slack variable for energy storage levels > target storage levels

Docs abbreviation: ``z^{st, ds}``
"""
struct StorageRegularizationVariableDischarge <: StorageRegularizationVariable end

"""
Auxiliary Variable for Storage Models that solve for total energy output
"""
struct StorageEnergyOutput <: AuxVariableType end

#################################################################################
# Hybrid System Variables
#
# Paired sibling variable types are parametric on `ReserveSide` (Discharge / Charge).
#################################################################################

"""
Abstract type for variables representing flows internal to a `PSY.HybridSystem`.
"""
abstract type AbstractHybridSubcomponentVariableType <: VariableType end

"Active power dispatched by the thermal subcomponent of a hybrid system."
struct HybridThermalActivePower <: AbstractHybridSubcomponentVariableType end

"Active power dispatched by the renewable subcomponent of a hybrid system."
struct HybridRenewableActivePower <: AbstractHybridSubcomponentVariableType end

"""
Active power on the storage subcomponent of a hybrid system. Parametric on
[`ReserveSide`](@ref).
"""
struct HybridStorageSubcomponentPower{Sd <: ReserveSide} <:
       AbstractHybridSubcomponentVariableType end

"Binary reservation variable for the storage subcomponent of a hybrid system."
struct HybridStorageReservation <: AbstractHybridSubcomponentVariableType end

"""
Non-negative slack variable bounding the absolute step change in charge or discharge
power between consecutive time steps. Carried into the objective with a small fixed
penalty when the hybrid `\"regularization\"` attribute is set.
"""
struct RegularizationVariable{Sd <: ReserveSide} <: AbstractHybridSubcomponentVariableType end

"""
Slack variable for the storage energy of a hybrid system being below its end-of-period
target. Added when the hybrid `\"energy_target\"` attribute is set and penalized in the
objective by the storage subcomponent's `energy_shortage_cost`.

Docs abbreviation: ``e^{st-}``
"""
struct HybridEnergyShortageVariable <: VariableType end

"""
Slack variable for the storage energy of a hybrid system being above its end-of-period
target. Added when the hybrid `\"energy_target\"` attribute is set and penalized in the
objective by the storage subcomponent's `energy_surplus_cost`.

Docs abbreviation: ``e^{st+}``
"""
struct HybridEnergySurplusVariable <: VariableType end

"""
Abstract type for hybrid reserve variables (both PCC-boundary and subcomponent).
"""
abstract type AbstractHybridReserveVariableType <: VariableType end

"""
Reserve quantity offered to the grid through one side of a hybrid PCC. Parametric on
[`ReserveSide`](@ref).
"""
struct HybridPCCReserveVariable{Sd <: ReserveSide} <: AbstractHybridReserveVariableType end

"""
Abstract type for per-subcomponent reserve allocations inside a hybrid system
that do not have a Discharge/Charge axis (thermal and renewable subcomponents).
"""
abstract type AbstractHybridSubcomponentInjectorReserveVariableType <:
              AbstractHybridReserveVariableType end

"Reserve allocated to the thermal subcomponent of a hybrid system."
struct HybridThermalReserveVariable <: AbstractHybridSubcomponentInjectorReserveVariableType end

"Reserve allocated to the renewable subcomponent of a hybrid system."
struct HybridRenewableReserveVariable <:
       AbstractHybridSubcomponentInjectorReserveVariableType end

"""
Reserve allocated to one side of a hybrid system's storage subcomponent. Parametric on
[`ReserveSide`](@ref).
"""
struct HybridStorageSubcomponentReserveVariable{Sd <: ReserveSide} <:
       AbstractHybridReserveVariableType end

const MULTI_START_VARIABLES = (HotStartVariable, WarmStartVariable, ColdStartVariable)

should_write_resulting_value(::Type{PiecewiseLinearCostVariable}) = false
should_write_resulting_value(::Type{PiecewiseLinearBlockIncrementalOffer}) = false
should_write_resulting_value(::Type{PiecewiseLinearBlockDecrementalOffer}) = false
should_write_resulting_value(::Type{PiecewiseLinearBlockReserveOffer}) = false
should_write_resulting_value(::Type{HVDCPiecewiseLossVariable}) = false
should_write_resulting_value(::Type{HVDCPiecewiseBinaryLossVariable}) = false
should_write_resulting_value(::Type{<:InterpolationVariableType}) = false
should_write_resulting_value(::Type{<:BinaryInterpolationVariableType}) = false
should_write_resulting_value(::Type{HydroTurbineFlowRateVariable}) = false

convert_output_to_natural_units(::Type{ActivePowerVariable}) = true
convert_output_to_natural_units(::Type{PowerAboveMinimumVariable}) = true
convert_output_to_natural_units(::Type{ActivePowerInVariable}) = true
convert_output_to_natural_units(::Type{ActivePowerOutVariable}) = true
convert_output_to_natural_units(::Type{EnergyVariable}) = true
convert_output_to_natural_units(::Type{ReactivePowerVariable}) = true
convert_output_to_natural_units(::Type{ActivePowerReserveVariable}) = true
convert_output_to_natural_units(::Type{ServiceRequirementVariable}) = true
convert_output_to_natural_units(::Type{RateofChangeConstraintSlackUp}) = true
convert_output_to_natural_units(::Type{RateofChangeConstraintSlackDown}) = true
convert_output_to_natural_units(::Type{AreaMismatchVariable}) = true
convert_output_to_natural_units(::Type{DeltaActivePowerUpVariable}) = true
convert_output_to_natural_units(::Type{DeltaActivePowerDownVariable}) = true
convert_output_to_natural_units(::Type{AdditionalDeltaActivePowerUpVariable}) = true
convert_output_to_natural_units(::Type{AdditionalDeltaActivePowerDownVariable}) = true
convert_output_to_natural_units(::Type{SmoothACE}) = true
convert_output_to_natural_units(::Type{SystemBalanceSlackUp}) = true
convert_output_to_natural_units(::Type{SystemBalanceSlackDown}) = true
convert_output_to_natural_units(::Type{ReserveRequirementSlack}) = true
convert_output_to_natural_units(::Type{FlowActivePowerVariable}) = true
convert_output_to_natural_units(::Type{FlowActivePowerFromToVariable}) = true
convert_output_to_natural_units(::Type{FlowActivePowerToFromVariable}) = true
convert_output_to_natural_units(::Type{FlowReactivePowerFromToVariable}) = true
convert_output_to_natural_units(::Type{FlowReactivePowerToFromVariable}) = true
convert_output_to_natural_units(::Type{HVDCLosses}) = true
convert_output_to_natural_units(::Type{InterfaceFlowSlackUp}) = true
convert_output_to_natural_units(::Type{InterfaceFlowSlackDown}) = true
convert_output_to_natural_units(::Type{ActivePowerPumpVariable}) = true
