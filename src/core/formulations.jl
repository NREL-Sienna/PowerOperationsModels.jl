"""
Abstract type for Device Formulations (a.k.a Models)

# Example

```julia
import PowerOperationsModels
const POM = PowerOperationsModels
struct MyCustomDeviceFormulation <: IOM.AbstractDeviceFormulation end
```
"""

########################### Thermal Generation Formulations ################################
# AbstractThermalFormulation: in IS
# AbstractThermalDispatchFormuation, UnitCommentment: in IOM

abstract type AbstractStandardUnitCommitment <: AbstractThermalUnitCommitment end
abstract type AbstractCompactUnitCommitment <: AbstractThermalUnitCommitment end

"""
Formulation type to enable basic unit commitment representation without any intertemporal (ramp, min on/off time) constraints
"""
struct ThermalBasicUnitCommitment <: AbstractStandardUnitCommitment end
"""
Formulation type to enable standard unit commitment with intertemporal constraints and simplified startup profiles
"""
struct ThermalStandardUnitCommitment <: AbstractStandardUnitCommitment end

"""
Formulation type to enable basic dispatch without any intertemporal (ramp) constraints
"""
struct ThermalBasicDispatch <: AbstractThermalDispatchFormulation end
"""
Formulation type to enable standard dispatch with a range and enforce intertemporal ramp constraints
"""
struct ThermalStandardDispatch <: AbstractThermalDispatchFormulation end
"""
Formulation type to enable basic dispatch without any intertemporal constraints and relaxed minimum generation. *May not work with non-convex PWL cost definitions*
"""
struct ThermalDispatchNoMin <: AbstractThermalDispatchFormulation end
"""
Formulation type to enable pg-lib commitment formulation with startup/shutdown profiles
"""
struct ThermalMultiStartUnitCommitment <: AbstractCompactUnitCommitment end
"""
Formulation type to enable thermal compact commitment
"""
struct ThermalCompactUnitCommitment <: AbstractCompactUnitCommitment end
"""
Formulation type to enable thermal compact commitment without intertemporal (ramp, min on/off time) constraints
"""
struct ThermalBasicCompactUnitCommitment <: AbstractCompactUnitCommitment end
"""
Formulation type to enable thermal compact dispatch
"""
struct ThermalCompactDispatch <: AbstractThermalDispatchFormulation end

############################# Electric Load Formulations ###################################
# AbstractLoadFormulation is imported from IS.Optimization via IOM
abstract type AbstractControllablePowerLoadFormulation <: AbstractLoadFormulation end

"""
Formulation type to add a time series parameter for non-dispatchable `ElectricLoad` withdrawals to power balance constraints
"""
struct StaticPowerLoad <: AbstractLoadFormulation end

"""
Formulation type to enable (binary) load interruptions
"""
struct PowerLoadInterruption <: AbstractControllablePowerLoadFormulation end

"""
Formulation type to enable (continuous) load interruption dispatch
"""
struct PowerLoadDispatch <: AbstractControllablePowerLoadFormulation end

"""
Formulation type to enable load shifting
"""
struct PowerLoadShift <: AbstractControllablePowerLoadFormulation end

############################ Regulation Device Formulations ################################
abstract type AbstractRegulationFormulation <: AbstractDeviceFormulation end
struct ReserveLimitedRegulation <: AbstractRegulationFormulation end
struct DeviceLimitedRegulation <: AbstractRegulationFormulation end

########################### Renewable Generation Formulations ##############################
# AbstractRenewableFormulation is imported from IS.Optimization via IOM
abstract type AbstractRenewableDispatchFormulation <: AbstractRenewableFormulation end

"""
Formulation type to add injection variables constrained by a maximum injection time series for `RenewableGen`
"""
struct RenewableFullDispatch <: AbstractRenewableDispatchFormulation end

"""
Formulation type to add real and reactive injection variables with constant power factor with maximum real power injections constrained by a time series for `RenewableGen`
"""
struct RenewableConstantPowerFactor <: AbstractRenewableDispatchFormulation end

########################### Source Formulations ##############################
abstract type AbstractSourceFormulation <: AbstractDeviceFormulation end

"""
Formulation type to add import and export model for `Source`
"""
struct ImportExportSourceModel <: AbstractSourceFormulation end

# Does this device formulation contribute to ReactivePowerBalance? Reactive-only
# formulations are dropped from a template under an active-power-only network (no Q balance).
models_reactive_power(::Type{<:AbstractDeviceFormulation}) = false

########################### Reactive Power Device Formulations ##############################
abstract type AbstractReactivePowerDeviceFormulation <: AbstractDeviceFormulation end

# The whole family is reactive-only by definition; declaring the trait on the abstract
# keeps future subtypes gated (matches the AbstractShuntFormulation declaration below).
models_reactive_power(::Type{<:AbstractReactivePowerDeviceFormulation}) = true

"""
Formulation type to add reactive power dispatch variables for `SynchronousCondenser`.
A condenser supplies only reactive power, so it is only meaningful under network models
with a reactive power balance; dropped from DC templates automatically via
`models_reactive_power`.
"""
struct SynchronousCondenserBasicDispatch <: AbstractReactivePowerDeviceFormulation end

########################### Controllable Shunt Formulations ################################
"""
Abstract supertype for controllable shunt formulations. All subtypes model reactive
compensation devices (`PSY.SwitchedAdmittance`, `PSY.FACTSControlDevice`) that dispatch
a continuous susceptance ``b \\in [b_{\\min}, b_{\\max}]`` and inject
``Q = b \\cdot V^2`` into the reactive nodal balance. Only valid under AC network models;
dropped from DC templates automatically via `models_reactive_power`.
"""
abstract type AbstractShuntFormulation <: AbstractDeviceFormulation end

"""
Continuous controllable shunt susceptance `b ∈ [b_min, b_max]` injecting `Q = b·V²` into
the reactive nodal balance, for `SwitchedAdmittance` (continuous relaxation of the switched
blocks) and `FACTSControlDevice` (SVC/STATCOM). Under a voltage control objective the
regulated bus voltage is fixed to its setpoint. Only valid under AC network models; dropped
from DC templates automatically via `models_reactive_power`.
"""
struct ShuntSusceptanceDispatch <: AbstractShuntFormulation end

"""
Fixed-susceptance shunt injecting `Q = b_nominal·V²` into the reactive nodal balance with a
non-dispatched `b_nominal` (`SwitchedAdmittance`: `imag(get_Y)`; `FACTSControlDevice`: the
reactive-power setpoint on system base). The susceptance is not a decision variable and
there is no voltage-control objective. This is the only shunt formulation valid under
`LPACCNetworkModel`, where `V²` linearizes to `1 + 2φ`; it also builds on ACP/ACR/IVR.
Dropped from DC templates automatically via `models_reactive_power`.
"""
struct FixedShuntAdmittance <: AbstractShuntFormulation end

models_reactive_power(::Type{<:AbstractShuntFormulation}) = true

"""
Abstract type for Branch Formulations (a.k.a Models)

# Example

```julia
import PowerOperationsModels
const POM = PowerOperationsModels
struct MyCustomBranchFormulation <: IOM.AbstractBranchFormulation end
```
"""
abstract type AbstractBranchFormulation <: AbstractDeviceFormulation end

############################### AC/DC Branch Formulations #####################################
"""
Branch type to add unbounded flow variables and use flow constraints
"""
struct StaticBranch <: AbstractBranchFormulation end

"""
Branch type to add bounded flow variables and use flow constraints
"""
struct StaticBranchBounds <: AbstractBranchFormulation end
"""
Branch type to avoid flow constraints
"""
struct StaticBranchUnbounded <: AbstractBranchFormulation end

abstract type AbstractSecurityConstrainedStaticBranch <: AbstractBranchFormulation end

"""
Security-constrained branch formulation that enforces post-contingency
emergency flow limits as inequality constraints on ACTransmission branches
under N-k contingency scenarios. The set of contingencies modeled is the
union of `outages` configured on each `DeviceModel{<:ACTransmission, <:AbstractSecurityConstrainedStaticBranch}`
in the template.

Concretely, for every monitored ACTransmission branch and every claimed
outage, this formulation adds:

```
-rate_emergency ≤ post_contingency_flow ≤ rate_emergency
```

where `post_contingency_flow` is derived from the modification factors
(MODF) provided by `PowerNetworkMatrices` and `rate_emergency` comes from
the branch's `rating_b` (falling back to `rating` only when `rating_b` is
unset), and becomes time-varying when a
`PostContingencyBranchRatingTimeSeriesParameter` is attached.

Outage modeling notes:
- An outage UUID is "claimed" by `DeviceModel{D, SC}` iff `D` is among the
  types of the outaged (associated) components on that outage. A
  multi-component outage is therefore claimed by every SC `DeviceModel`
  whose component type appears in its outaged set; the post-contingency
  build deduplicates by referencing the first claimer. The OUTAGED
  component's type — not the monitored components — must be covered by an
  SC `DeviceModel` for the outage to contribute any constraints.
- The monitored set is whatever each outage explicitly lists in its
  `monitored_components`. There is no implicit "monitor everything" default:
  an outage with empty `monitored_components` monitors nothing (a warning is
  emitted) and contributes no post-contingency constraints. This is
  deliberate — defaulting to monitoring every branch under every outage would
  silently produce an N-1-everything-by-everything problem that is
  intractable for realistic systems; the user must opt in to each monitored
  branch.
- A monitored component whose type is not a modeled `PSY.ACTransmission`
  branch type (either absent from the template, or modeled but not a branch)
  is skipped (warned once per type at template validation; no
  post-contingency constraints are built for it).
- `PSY.PlannedOutage` instances are excluded by default; set
  `attributes = Dict("include_planned_outages" => true)` on the
  `DeviceModel` to include them.
- Both the monitored AND the outaged component endpoints are pinned in the
  network reduction (added to `irreducible_buses`). This prevents radial /
  degree-two reductions from collapsing the contingency arc out of the
  reduced topology, which would otherwise leave PNM's MODF column without a
  matching arc to apply.
"""
struct SecurityConstrainedStaticBranch <: AbstractSecurityConstrainedStaticBranch end

IOM.supports_outages(::Type{<:AbstractSecurityConstrainedStaticBranch}) = true

# psy6: disabled pending transformer refactor
# """
# Branch formulation for PhaseShiftingTransformer flow control
# """
# struct PhaseAngleControl <: AbstractBranchFormulation end

############################### DC Branch Formulations #####################################
abstract type AbstractTwoTerminalDCLineFormulation <: AbstractBranchFormulation end
"""
Branch type to avoid flow constraints
"""
struct HVDCTwoTerminalUnbounded <: AbstractTwoTerminalDCLineFormulation end
"""
Branch type to represent lossless power flow on DC lines
"""
struct HVDCTwoTerminalLossless <: AbstractTwoTerminalDCLineFormulation end
"""
Branch type to represent lossy power flow on DC lines
"""
struct HVDCTwoTerminalDispatch <: AbstractTwoTerminalDCLineFormulation end
"""
Branch type to represent piecewise lossy power flow on two terminal DC lines
"""
struct HVDCTwoTerminalPiecewiseLoss <: AbstractTwoTerminalDCLineFormulation end

"""
Branch type to represent non-linear LCC (line commutated converter) model on two-terminal DC lines
"""
struct HVDCTwoTerminalLCC <: AbstractTwoTerminalDCLineFormulation end

"""
Abstract supertype for two-terminal voltage-source converter (VSC) HVDC formulations.
Models per-terminal converters with quadratic / two-term losses
(``a I^2 + b |I| + c``), a shared signed cable current, an explicit DC-side
cable resistance (``v_f - v_t = (1/g) \\cdot I``), and (on AC networks) independent
reactive-power control bounded by per-terminal PQ capability.
"""
abstract type AbstractTwoTerminalVSCFormulation <: AbstractTwoTerminalDCLineFormulation end

"""
Two-terminal VSC formulation: the per-terminal ``v \\cdot I`` / ``I^2`` losses are
bridged to IOM's approximation API and the apparent-power limit
``p^2 + q^2 \\le \\text{rating}^2`` is enforced as the exact disk (default `"none"`,
NLP) or, under a linearizing scheme, a linear outer-approximation — a box, plus an
octagon when the `"use_octagon"` attribute (default `true`) is on. See
[`BILINEAR_APPROX_DEFAULT_ATTRIBUTES`](@ref) for the approximation attributes; here
`"bilinear_quadratic_method"` also sizes the standalone `I²` loss term for *every*
scheme.
"""
struct HVDCTwoTerminalVSC <: AbstractTwoTerminalVSCFormulation end

"""
Two-terminal VSC formulation with reactive / voltage control (Family C). Builds the exact same
NLP physics as [`HVDCTwoTerminalVSC`](@ref) — per-terminal converter losses, a shared signed
cable current, the DC cable Ohm's law, bounded per-terminal reactive injection into
`ReactivePowerBalance`, and the apparent-power capability disk ``p^2 + q^2 \\le \\text{rating}^2``
— and adds a count-invariant control layer driven by the converter's `ac_control_*` /
`dc_control_*` modes. AC control pins one already-created variable per terminal with a single
`JuMP.fix` (`force = true`): `AC_VOLTAGE` → the regulated AC-bus voltage (the `VoltageMagnitude`
under ACP, the `VoltageDeviation` `phi = |V| - 1` under LPACC, a per-terminal
`RegulatedVoltageMagnitude` aux variable under ACR/IVR), `AC_REACTIVE_POWER` → the terminal
reactive injection. DC control adds one always-present `HVDCDCControlConstraint` per terminal
per time step (`DC_VOLTAGE` / `DC_POWER` / `DC_VOLTAGE_DROOP`), so the variable/constraint
containers are identical across all control modes. Only valid under AC network models
(ACP/ACR/IVR/LPACC); dropped from DC templates automatically via `models_reactive_power`.
"""
struct VoltageControlVSC <: AbstractTwoTerminalVSCFormulation end

models_reactive_power(::Type{VoltageControlVSC}) = true

############################### AC/DC Converter Formulations #####################################
abstract type AbstractConverterFormulation <: AbstractDeviceFormulation end

"""
Lossless InterconnectingConverter Model
"""
struct LosslessConverter <: AbstractConverterFormulation end

"""
Linear-loss `InterconnectingConverter` formulation. Same transport-style AC/DC
transfer as [`LosslessConverter`](@ref) (the `ActivePowerVariable` enters the AC-bus
`ActivePowerBalance` with `+1` and the DC-bus `ActivePowerBalance` with `-1`, so it
requires a `TransportHVDCNetworkModel`), plus a linear loss `b·|I| + c` withdrawn at
the DC bus, where `b`/`c` are the proportional/constant terms of the converter's
`loss_function` and `|I|` is approximated by `|P|` at nominal DC voltage (1 pu) via a
non-negative `CurrentAbsoluteValueVariable` surrogate bounded below by `±P` and pinned
to `|P|` by cost minimization. A `loss_function` with a non-zero quadratic term is
rejected — use [`QuadraticLossConverter`](@ref) for current-dependent quadratic losses.
On AC network models the converter also gets a bounded `ReactivePowerVariable` injected
into `ReactivePowerBalance` and the apparent-power capability disk
``p^2 + q^2 \\le \\text{rating}^2``.
"""
struct LinearLossConverter <: AbstractConverterFormulation end

"""
Abstract supertype for InterconnectingConverter formulations with quadratic losses.
"""
abstract type AbstractQuadraticLossConverter <: AbstractConverterFormulation end

"""
Quadratic Loss InterconnectingConverter: the `v·I` / `I²` loss terms are bridged
to IOM's approximation API — exact by default (`"none"`, an NLP) or replaced with
tolerance-driven linear surrogates under a linearizing scheme. See
[`BILINEAR_APPROX_DEFAULT_ATTRIBUTES`](@ref) for the approximation attributes; here
`"bilinear_quadratic_method"` also sizes the standalone `I²` loss term for *every*
scheme.
"""
struct QuadraticLossConverter <: AbstractQuadraticLossConverter end

"""
AC/DC `InterconnectingConverter` formulation for AC network models (ACP/ACR/IVR/LPACC).
Builds the same DC-side physics as [`QuadraticLossConverter`](@ref) — the `ActivePowerVariable`,
`ConverterCurrent`/`CurrentAbsoluteValueVariable`, the per-`DCBus` `DCVoltage`, the
`DCCurrentBalance` wiring and the quadratic `ConverterLossConstraint` — and adds the AC-side
representation: a bounded `ReactivePowerVariable` injected into `ReactivePowerBalance` at the
converter's AC bus, the apparent-power capability disk ``p^2 + q^2 \\le \\text{rating}^2``, and a
count-invariant control layer driven by the converter's `ac_control` / `dc_control` modes.

AC control: `AC_VOLTAGE` regulates the AC bus voltage to `ac_setpoint` (under ACP by fixing the
network `VoltageMagnitude`; under LPACC by fixing the `VoltageDeviation` `phi = |V| - 1` to
`ac_setpoint - 1`; under ACR/IVR via a component-owned `RegulatedVoltageMagnitude` aux
variable); `AC_REACTIVE_POWER` fixes the reactive injection to `ac_setpoint`. DC control adds one
always-present `HVDCDCControlConstraint` per converter per time step: `DC_VOLTAGE` →
`vdc = dc_setpoint`, `DC_POWER` → `p = dc_setpoint`, `DC_VOLTAGE_DROOP` →
`vdc + dc_voltage_droop * p = dc_setpoint`. The aux voltage variable + its constraint and the
`HVDCDCControlConstraint` are created regardless of mode, so variable/constraint containers are
identical across all control modes (only per-mode coefficients / `JuMP.fix` differ). Only valid
under AC network models; dropped from DC templates automatically via `models_reactive_power`.
Requires a `VoltageDispatchHVDCNetworkModel` HVDC network model (for the `DCVoltage` /
`DCCurrentBalance` DC-side) and finite `reactive_power_limits` on each converter.
"""
struct VoltageControlConverter <: AbstractQuadraticLossConverter end

models_reactive_power(::Type{VoltageControlConverter}) = true

############################## HVDC Lines Formulations ##################################
abstract type AbstractDCLineFormulation <: AbstractBranchFormulation end

"""
Lossy Line Abstract Model
"""
struct DCLossyLine <: AbstractDCLineFormulation end

"""
Lossless Line struct formulation
"""
struct LosslessLine <: AbstractDCLineFormulation end

############################## HVDC Network Model Formulations ##################################

"""
Transport Lossless HVDC network model. No DC voltage variables are added and DC lines are modeled as lossless power transport elements
"""
struct TransportHVDCNetworkModel <: AbstractHVDCNetworkModel end
"""
DC Voltage HVDC network model, where currents are solved based on DC voltage difference between DC buses
"""
struct VoltageDispatchHVDCNetworkModel <: AbstractHVDCNetworkModel end

########################### Service Formulations ###########################################
# AbstractServiceFormulation and AbstractReservesFormulation are imported from IS.Optimization via IOM

abstract type AbstractAGCFormulation <: AbstractServiceFormulation end

struct PIDSmoothACE <: AbstractAGCFormulation end

"""
Group analogue of [`RangeReserve`](@ref): the awards of a `PSY.GroupReserve`'s contributing services
must together meet the group's specified requirement. Not named `GroupReserve` to avoid clashing
with the `PSY.GroupReserve` component type.
"""
struct GroupRangeReserve <: AbstractReservesFormulation end

"""
Struct for to add reserves to be larger than a specified requirement
"""
struct RangeReserve <: AbstractReservesFormulation end

"""
Struct for to add reserves to be larger than a variable requirement depending of costs
"""
struct StepwiseCostReserve <: AbstractReservesFormulation end
"""
Struct to add reserves to be larger than a specified requirement, with ramp constraints
"""
struct RampReserve <: AbstractReservesFormulation end
"""
Struct to add non spinning reserve requirements larger than specified requirement
"""
struct NonSpinningReserve <: AbstractReservesFormulation end
"""
Struct to add a constant maximum transmission flow for specified interface
"""
struct ConstantMaxInterfaceFlow <: AbstractServiceFormulation end
"""
Struct to add a variable maximum transmission flow for specified interface
"""
struct VariableMaxInterfaceFlow <: AbstractServiceFormulation end

############################ Hydro Generation Formulations #################################
# Defined in PSI copied here for reference
# abstract type AbstractHydroFormulation <: AbstractDeviceFormulation end
# abstract type AbstractHydroDispatchFormulation <: AbstractHydroFormulation end
# abstract type AbstractHydroUnitCommitment <: AbstractHydroFormulation end

abstract type AbstractHydroFormulation <: AbstractDeviceFormulation end
abstract type AbstractHydroDispatchFormulation <: AbstractHydroFormulation end
abstract type AbstractHydroReservoirFormulation <: AbstractHydroDispatchFormulation end
abstract type AbstractHydroUnitCommitment <: AbstractHydroFormulation end

"""
Formulation type to add injection variables constrained by a maximum injection time series for [`PowerSystems.HydroGen`](@extref). Set the `"hydro_budget"` device-model attribute to `true` to additionally enforce an energy budget over the horizon.
"""
struct HydroDispatchRunOfRiver <: AbstractHydroDispatchFormulation end

"""
Formulation type to constrain hydropower production with an energy block optimization representation of the energy storage capacity and water inflow time series of a reservoir for [`PowerSystems.HydroGen`](@extref)
"""
struct HydroWaterFactorModel <: AbstractHydroReservoirFormulation end

"""
Formulation type to add commitment and injection variables constrained by a maximum injection time series for [`PowerSystems.HydroGen`](@extref)
"""
struct HydroCommitmentRunOfRiver <: AbstractHydroUnitCommitment end

"""
Formulation type to add reservoir methods with hydro turbines using water flow variables for [`PowerSystems.HydroReservoir`](@extref)
"""
struct HydroWaterModelReservoir <: AbstractHydroReservoirFormulation end

"""
Formulation type to add reservoir methods with hydro turbines using only energy inflow/outflow variables (no water flow variables) for [`PowerSystems.HydroReservoir`](@extref)
"""
struct HydroEnergyModelReservoir <: AbstractHydroReservoirFormulation end

"""
Formulation type to add injection variables for a [`PowerSystems.HydroGen`](@extref)
HydroTurbine connected to reservoirs using water flow variables, with the flow×head
product bridged to IOM's approximation API — exact by default (`"none"`, an NLP) or
a tolerance-driven MILP approximation under a linearizing scheme. See
[`BILINEAR_APPROX_DEFAULT_ATTRIBUTES`](@ref) for the approximation attributes.
"""
struct HydroTurbineBilinearDispatch <: AbstractHydroDispatchFormulation end

"""
Formulation type to add injection variables for a HydroTurbine connected to reservoirs using a linear model [`PowerSystems.HydroGen`](@extref).
The model assumes a shallow reservoir. The head for the conversion between water flow and power can be approximated as a linear function of the water flow on which the head elevation is always the intake elevation.
"""
struct HydroTurbineWaterLinearDispatch <: AbstractHydroDispatchFormulation end

"""
Formulation type to add injection and commitment variables for a [`PowerSystems.HydroTurbine`](@extref) connected to reservoirs using a linear model with a binary [`PowerSimulations.OnVariable`](@extref) to decide if the turbine is on or not.
The model assumes a shallow reservoir. The head for the conversion between water flow and power can be approximated as a linear function of the water flow on which the head elevation is always the intake elevation.
"""
struct HydroTurbineWaterLinearCommitment <: AbstractHydroUnitCommitment end

"""
Formulation type to add injection variables for a [`PowerSystems.HydroTurbine`](@extref) only using energy variables (no water flow variables)
"""
struct HydroTurbineEnergyDispatch <: AbstractHydroDispatchFormulation end

"""
Formulation type to add injection variables for a [`PowerSystems.HydroTurbine`](@extref) only using energy variables (no water flow variables) and commitment variables
"""
struct HydroTurbineEnergyCommitment <: AbstractHydroUnitCommitment end

abstract type AbstractHydroPumpFormulation <: AbstractHydroFormulation end
"""
Formulation type to add injection variables for a HydroPumpTurbine only using energy variables (no water flow variables)
"""
struct HydroPumpEnergyDispatch <: AbstractHydroPumpFormulation end

"""
Formulation type to add injection variables for a HydroPumpTurbine only using energy variables (no water flow variables) and commitment variables
"""
struct HydroPumpEnergyCommitment <: AbstractHydroPumpFormulation end

"""
These types share constructors.
"""
const HydroTurbineWaterFormulation = Union{
    HydroTurbineBilinearDispatch,
    HydroTurbineWaterLinearDispatch,
    HydroTurbineWaterLinearCommitment,
}

############################ Storage Generation Formulations ###############################
abstract type AbstractStorageFormulation <: IOM.AbstractDeviceFormulation end

"""
Formulation type to add storage formulation than can provide ancillary services. If a
storage unit does not contribute to any service, then the variables and constraints related to
services are ignored.

# Example

```julia
DeviceModel(
    StorageType, # E.g. EnergyReservoirStorage or GenericStorage
    StorageDispatchWithReserves;
    attributes=Dict(
        "reservation" => true,
        "cycling_limits" => false,
        "energy_target" => false,
        "complete_coverage" => false,
        "regularization" => true,
    ),
    use_slacks=false,
)
```

The formulation supports the following attributes when used in a [`PowerSimulations.DeviceModel`](@extref):

# Attributes

  - `"reservation"`: Forces the storage to operate exclusively on charge or discharge mode through the entire operation interval. We recommend setting this to `false` for models with relatively longer time resolutions (e.g., 1-Hr) since the storage can take simultaneous charge or discharge positions on average over the period.
  - `"cycling_limits"`: This limits the storage's energy cycling. A single charging (discharging) cycle is fully charging (discharging) the storage once. The calculation uses the total energy charge/discharge and the number of cycles. Currently, the formulation only supports a fixed value per operation period. Additional variables for [`StorageChargeCyclingSlackVariable`](@ref) and [`StorageDischargeCyclingSlackVariable`](@ref) are included in the model if `use_slacks` is set to `true`.
  - `"energy_target"`: Set a target at the end of the model horizon for the storage's state of charge. Currently, the formulation only supports a fixed value per operation period. Additional variables for [`StorageEnergyShortageVariable`](@ref) and [`StorageEnergySurplusVariable`](@ref) are included in the model if `use_slacks` is set to `true`.

!!! warning

    Combining cycle limits and energy target attributes is not recommended. Both
    attributes impose constraints on energy. There is no guarantee that the constraints can be satisfied simultaneously.

  - `"complete_coverage"`: This attribute implements constraints that require the battery to cover the sum of all the ancillary services it participates in simultaneously. It is equivalent to holding energy in case all the services get deployed simultaneously. This constraint is added to the constraints that cover each service independently and corresponds to a more conservative operation regime.
  - `"regularization"`: This attribute smooths the charge/discharge profiles to avoid bang-bang solutions via a penalty on the absolute value of the intra-temporal variations of the charge and discharge power. Solving for optimal storage dispatch can stall in models with large amounts of curtailment or long periods with negative or zero prices due to numerical degeneracy. The regularization term is scaled by the storage device's power limits to normalize the term and avoid additional penalties to larger storage units.

!!! danger

    Setting the energy target attribute in combination with `EnergyTargetFeedforward`
    or `EnergyLimitFeedforward` is not permitted and `StorageSystemsSimulations.jl`
    will throw an exception.

See the [Formulation Library](@ref storage_math_model) for the full mathematical description.
"""
struct StorageDispatchWithReserves <: AbstractStorageFormulation end

############################ Hybrid System Formulations ###################################
abstract type AbstractHybridFormulation <: IOM.AbstractDeviceFormulation end
abstract type AbstractHybridFormulationWithReserves <: AbstractHybridFormulation end

"""
    HybridDispatchWithReserves

Device formulation for a hybrid system (single point of common coupling (PCC) with
renewable, thermal, and storage subcomponents) that participates in both energy and
ancillary services markets. Implements a centralized production cost model where the
hybrid plant's net power at the PCC is constrained by ``P_{\\max,\\text{pcc}}`` and
ancillary service allocations (``sb^{\\text{out}}_{p,t}``, ``sb^{\\text{in}}_{p,t}``) are
assigned to internal assets (thermal, renewable, charge, discharge) per the
four-quadrant ancillary service model. Reserve participation is enabled by attaching a
service model to the hybrid (`set_service_model!` + `add_service!`); when no service is
attached the formulation collapses to an energy-only hybrid dispatch.

Use with a hybrid system in a `DeviceModel` for unit commitment or economic
dispatch.

**Variables:**

  - `ActivePowerOutVariable`:

      + Domain: [0.0, ``P_{\\max,\\text{pcc}}``]
      + Symbol: ``p^{\\text{out}}_t``

  - `ActivePowerInVariable`:

      + Domain: [0.0, ``P_{\\max,\\text{pcc}}``]
      + Symbol: ``p^{\\text{in}}_t``

  - `ReservationVariable` (only when `"reservation" => true`):

      + Domain: {0, 1}
      + Symbol: ``u^{\\text{st}}_t`` (1 = discharge mode, 0 = charge mode)

  - [`HybridThermalActivePower`](@ref):

      + Domain: [0.0, ``P_{\\max,\\text{th}}``] when on
      + Symbol: ``p^{\\text{th}}_t``

  - `OnVariable`:

      + Domain: {0, 1}
      + Symbol: ``u^{\\text{th}}_t``

  - [`HybridRenewableActivePower`](@ref):

      + Domain: [0.0, ``P^{*,\\text{re}}_t``]
      + Symbol: ``p^{\\text{re}}_t``

  - [`HybridStorageSubcomponentPower{ChargeSide}`](@ref):

      + Domain: [0.0, ``P_{\\max,\\text{ch}}``]
      + Symbol: ``p^{\\text{ch}}_t``

  - [`HybridStorageSubcomponentPower{DischargeSide}`](@ref):

      + Domain: [0.0, ``P_{\\max,\\text{ds}}``]
      + Symbol: ``p^{\\text{ds}}_t``

  - [`EnergyVariable`](@ref):

      + Domain: [0.0, ``E_{\\max,\\text{st}}``]
      + Symbol: ``e^{\\text{st}}_t``

  - [`HybridStorageReservation`](@ref) (only when `"storage_reservation" => true`):

      + Domain: {0, 1}
      + Symbol: ``ss^{\\text{st}}_t`` (0 = charge, 1 = discharge)

  - [`HybridPCCReserveVariable{DischargeSide}`](@ref) (only when services are attached):

      + Domain: [0.0, ]
      + Symbol: ``sb^{\\text{out}}_t``

  - [`HybridPCCReserveVariable{ChargeSide}`](@ref) (only when services are attached):

      + Domain: [0.0, ]
      + Symbol: ``sb^{\\text{in}}_t``

  - [`RegularizationVariable{ChargeSide}`](@ref), [`RegularizationVariable{DischargeSide}`](@ref)
    (only when `"regularization" => true`): non-negative slacks bounding step changes in
    charge/discharge between consecutive time steps.

**Time Series Parameters:**

| Parameter | Default Time Series Name |
| :--- | :--- |
| `HybridRenewableActivePowerTimeSeriesParameter` | `"RenewableDispatch__max_active_power"` |
| `HybridElectricLoadTimeSeriesParameter` | `"PowerLoad__max_active_power"` |

**Data requirements:**

  - **Device:** A `PSY.HybridSystem` with at least one of: thermal unit
    (`PSY.get_thermal_unit`), renewable unit (`PSY.get_renewable_unit`), storage
    (`PSY.get_storage`), and optionally electric load (`PSY.get_electric_load`).
  - **Time series:** Forecast time series must be attached to the `PSY.HybridSystem`
    itself (not its subcomponents) under the default names above (or custom names passed
    when adding parameters). The subcomponent-namespaced default names
    (`"RenewableDispatch__max_active_power"`, `"PowerLoad__max_active_power"`) reflect
    which subcomponent each forecast describes; the subcomponent is consulted only for the
    rating used to scale the parameter.

**Static Parameters:**

  - ``P_{\\max,\\text{pcc}}`` = `PSY.get_output_active_power_limits(device).max`
  - ``P_{\\max,\\text{th}}`` = `PSY.get_active_power_limits(thermal_unit).max`
  - ``P_{\\min,\\text{th}}`` = `PSY.get_active_power_limits(thermal_unit).min`
  - ``P_{\\max,\\text{ch}}`` = `PSY.get_input_active_power_limits(storage).max`
  - ``P_{\\max,\\text{ds}}`` = `PSY.get_output_active_power_limits(storage).max`
  - ``\\eta_{\\text{ch}}`` = `PSY.get_efficiency(storage).in`
  - ``\\eta_{\\text{ds}}`` = `PSY.get_efficiency(storage).out`
  - ``E_{\\max,\\text{st}}`` = `PSY.get_storage_level_limits(storage).max * PSY.get_storage_capacity(storage, PSY.SU) * PSY.get_conversion_factor(storage)``
  - ``E^{\\text{st}}_0`` = initial storage energy
  - ``R^{*}_{p,t}`` = ancillary service deployment forecast for service ``p`` at time ``t``
  - ``F_p`` = fraction of ``P_{\\max,\\text{pcc}}`` allowed for service ``p``
  - ``N_p`` = number of periods of compliance for service ``p``

**Expressions:**

Adds ``p^{\\text{out}}_t`` and ``p^{\\text{in}}_t`` to `ActivePowerBalance` for use in
network balance constraints. When services are attached, also accumulates reserve
expressions (`HybridPCCReserveExpression`) with unscaled and deployed-reserve scalings
across all four combinations of direction (up/down) and side (in/out).

**Constraints:**

Let ``\\mathcal{T} = \\{1, \\dots, T\\}`` denote the set of time steps.

PCC and status. When `"reservation" => true`:
[`HybridStatusOnConstraint{DischargeSide}`](@ref), [`HybridStatusOnConstraint{ChargeSide}`](@ref). When
`"reservation" => false`: [`OutputActivePowerVariableLimitsConstraint`](@ref) and
[`InputActivePowerVariableLimitsConstraint`](@ref) (no mutual-exclusion binary).

```math
\\begin{align*}
&  0 \\leq p^{\\text{in}}_t \\leq P_{\\max,\\text{pcc}}, \\quad 0 \\leq p^{\\text{out}}_t \\leq P_{\\max,\\text{pcc}}, \\quad \\forall t \\in \\mathcal{T} \\\\
&  u^{\\text{st}}_t \\in \\{0,1\\} \\quad \\text{(when reservation is enabled)}
\\end{align*}
```

Energy asset balance ([`HybridEnergyAssetBalanceConstraint`](@ref)). When services are
present, served-reserve expressions enter the balance with sign pattern
``+\\bar{r}^{\\text{out,up}} - \\bar{r}^{\\text{in,up}} - \\bar{r}^{\\text{out,dn}} + \\bar{r}^{\\text{in,dn}}``.

```math
p^{\\text{th}}_t + p^{\\text{re}}_t + p^{\\text{ds}}_t - p^{\\text{ch}}_t - P^{\\text{ld}}_t = p^{\\text{out}}_t - p^{\\text{in}}_t, \\quad \\forall t \\in \\mathcal{T}
```

Thermal limits when no services are attached
([`HybridThermalOnVariableConstraint{UpperBound}`](@ref),
[`HybridThermalOnVariableConstraint{LowerBound}`](@ref)):

```math
u^{\\text{th}}_t P_{\\min,\\text{th}} \\leq p^{\\text{th}}_t \\leq u^{\\text{th}}_t P_{\\max,\\text{th}}, \\quad u^{\\text{th}}_t \\in \\{0,1\\}, \\quad \\forall t \\in \\mathcal{T}
```

Renewable limit ([`HybridRenewableActivePowerLimitConstraint`](@ref)):

```math
0 \\leq p^{\\text{re}}_t \\leq P^{*,\\text{re}}_t, \\quad \\forall t \\in \\mathcal{T}
```

Storage charge/discharge mutual exclusion when `"storage_reservation" => true`
([`HybridStorageStatusOnConstraint{ChargeSide}`](@ref),
[`HybridStorageStatusOnConstraint{DischargeSide}`](@ref)):

```math
\\begin{align*}
&  p^{\\text{ch}}_t \\leq (1 - ss^{\\text{st}}_t) P_{\\max,\\text{ch}}, \\quad p^{\\text{ds}}_t \\leq ss^{\\text{st}}_t P_{\\max,\\text{ds}}, \\quad \\forall t \\in \\mathcal{T} \\\\
&  ss^{\\text{st}}_t \\in \\{0,1\\}
\\end{align*}
```

Storage energy balance ([`HybridStorageBalanceConstraint`](@ref)):

```math
e^{\\text{st}}_t = e^{\\text{st}}_{t-1} + \\Delta t \\left( \\eta_{\\text{ch}} p^{\\text{ch}}_t - \\frac{p^{\\text{ds}}_t}{\\eta_{\\text{ds}}} \\right), \\quad \\forall t \\in \\mathcal{T}, \\quad e^{\\text{st}}_0 = E^{\\text{st}}_0
```

When ancillary services are attached: [`HybridThermalReserveLimitConstraint`](@ref),
[`HybridRenewableReserveLimitConstraint`](@ref),
[`HybridStorageReservePowerLimitConstraint{ChargeSide}`](@ref),
[`HybridStorageReservePowerLimitConstraint{DischargeSide}`](@ref),
[`ReserveCoverageConstraint`](@ref), [`ReserveCoverageConstraintEndOfPeriod`](@ref),
[`HybridReserveAssignmentConstraint`](@ref), [`HybridReserveBalanceConstraint`](@ref).

End-of-horizon energy target (if `"energy_target" => true`),
[`HybridEnergyTargetConstraint`](@ref):

```math
e^{\\text{st}}_T - e^{\\text{st+}} + e^{\\text{st-}} = E^{\\text{st}}_T
```

Charge/discharge regularization (if `"regularization" => true`),
[`RegularizationConstraint{ChargeSide}`](@ref),
[`RegularizationConstraint{DischargeSide}`](@ref): bound ``|p^{\\text{ch}}_t -
p^{\\text{ch}}_{t-1}|`` and ``|p^{\\text{ds}}_t - p^{\\text{ds}}_{t-1}|`` by a
non-negative slack carried into the objective.

# Example

```julia
DeviceModel(
    PSY.HybridSystem,
    HybridDispatchWithReserves;
    attributes = Dict(
        "reservation"         => true,
        "storage_reservation" => true,
        "energy_target"       => false,
        "regularization"      => false,
    ),
)
```

# Attributes

  - `"reservation"` (default `true`): if `true`, adds `ReservationVariable` and uses
    `HybridStatus{Out,In}OnConstraint` to mutually exclude PCC charge and discharge.
    If `false`, both PCC variables are bounded by simple range constraints.
  - `"storage_reservation"` (default `true`): if `true`, adds `HybridStorageReservation`
    and uses the `ss`-multiplied form of the storage power-limit constraints. If
    `false`, charge and discharge variables are bounded independently.
  - `"energy_target"` (default `false`): adds `HybridEnergyTargetConstraint` at the
    storage subcomponent.
  - `"regularization"` (default `false`): adds `RegularizationVariable{ChargeSide}` and
    `RegularizationVariable{DischargeSide}` plus the matching constraints, and a small
    objective penalty on each, to suppress charge/discharge oscillation.

**Objective:**

Adds variable cost on `HybridThermalActivePower`, `HybridRenewableActivePower`,
`HybridStorageSubcomponentPower{ChargeSide}`, and `HybridStorageSubcomponentPower{DischargeSide}` from each subcomponent's
`PSY.get_operation_cost`, plus the proportional `OnVariable` cost (delegated to POM's
standard `proportional_cost` for `ThermalGenerationCost`, so a hybrid-embedded thermal
unit and a standalone copy produce identical objective coefficients). When
`"regularization" => true`, also adds a small per-time-step penalty on the
regularization slacks.
"""
struct HybridDispatchWithReserves <: AbstractHybridFormulationWithReserves end
