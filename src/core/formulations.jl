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
abstract type AbstractSecurityConstrainedUnitCommitment <: AbstractThermalUnitCommitment end

"""
Formulation type to enable basic unit commitment representation without any intertemporal (ramp, min on/off time) constraints
"""
struct ThermalBasicUnitCommitment <: AbstractStandardUnitCommitment end
"""
Formulation type to enable standard unit commitment with intertemporal constraints and simplified startup profiles
"""
struct ThermalStandardUnitCommitment <: AbstractStandardUnitCommitment end

"""
Formulation type to enable Security-Constrained (G-1) standard unit commitment with intertemporal constraints and simplified startup profiles
"""
struct ThermalSecurityConstrainedStandardUnitCommitment <:
       AbstractSecurityConstrainedUnitCommitment end

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

############################ Regulation Device Formulations ################################
abstract type AbstractRegulationFormulation <: AbstractDeviceFormulation end
struct ReserveLimitedRegulation <: AbstractRegulationFormulation end
struct DeviceLimitedRegulation <: AbstractRegulationFormulation end

########################### Renewable Generation Formulations ##############################
# AbstractRenewableFormulation is imported from IS.Optimization via IOM
abstract type AbstractRenewableDispatchFormulation <: AbstractRenewableFormulation end
abstract type AbstractSecurityConstrainedRenewableDispatchFormulation <:
              AbstractRenewableDispatchFormulation end

"""
Formulation type to add injection variables constrained by a maximum injection time series for `RenewableGen`
"""
struct RenewableFullDispatch <: AbstractRenewableDispatchFormulation end

"""
Formulation type to enable Renewable Security-Constrained (G-1) and add injection variables constrained by a maximum injection time series for `RenewableGen`
"""
struct RenewableSecurityConstrainedFullDispatch <:
       AbstractSecurityConstrainedRenewableDispatchFormulation end

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

########################### Reactive Power Device Formulations ##############################
abstract type AbstractReactivePowerDeviceFormulation <: AbstractDeviceFormulation end

"""
Formulation type to add reactive power dispatch variables for `SynchronousCondenser`
"""
struct SynchronousCondenserBasicDispatch <: AbstractReactivePowerDeviceFormulation end

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
"""
Branch formulation for PhaseShiftingTransformer flow control
"""
struct PhaseAngleControl <: AbstractBranchFormulation end

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

# Not Implemented
# struct VoltageSourceDC <: AbstractTwoTerminalDCLineFormulation end

############################### AC/DC Converter Formulations #####################################
abstract type AbstractConverterFormulation <: AbstractDeviceFormulation end

"""
Lossless InterconnectingConverter Model
"""
struct LosslessConverter <: AbstractConverterFormulation end

"""
Linear Loss InterconnectingConverter Model
"""
struct LinearLossConverter <: AbstractConverterFormulation end

"""
Quadratic Loss InterconnectingConverter Model
"""
struct QuadraticLossConverter <: AbstractConverterFormulation end

############################## HVDC Lines Formulations ##################################
abstract type AbstractDCLineFormulation <: AbstractBranchFormulation end

"""
Lossless Line Abstract Model
"""
struct DCLosslessLine <: AbstractDCLineFormulation end

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

abstract type AbstractSecurityConstrainedReservesFormulation <: AbstractReservesFormulation end

abstract type AbstractAGCFormulation <: AbstractServiceFormulation end

struct PIDSmoothACE <: AbstractAGCFormulation end

"""
Struct to add reserves to be larger than a specified requirement for an aggregated collection of services
"""
struct GroupReserve <: AbstractReservesFormulation end

"""
Struct for to add reserves to be larger than a specified requirement
"""
struct RangeReserve <: AbstractReservesFormulation end

"""
Struct for to add reserves to be larger than a specified requirement and map how those should be allocated and deployed considering generators outages
"""
struct RangeReserveWithDeliverabilityConstraints <:
       AbstractSecurityConstrainedReservesFormulation end

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
Formulation type to add injection variables constrained by a maximum injection time series for [`PowerSystems.HydroGen`](@extref)
"""
struct HydroDispatchRunOfRiver <: AbstractHydroDispatchFormulation end

"""
Formulation type to add injection variables constrained by a maximum injection time series for [`PowerSystems.HydroGen`](@extref) and a budget
"""
struct HydroDispatchRunOfRiverBudget <: AbstractHydroDispatchFormulation end

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
Formulation type to add injection variables for a HydroTurbine connected to reservoirs using a bilinear model (with water flow variables) [`PowerSystems.HydroGen`](@extref)
"""
struct HydroTurbineBilinearDispatch <: AbstractHydroDispatchFormulation end

"""
Formulation type to add injection variables for a HydroTurbine connected to reservoirs using a linear model [`PowerSystems.HydroGen`](@extref).
The model assumes a shallow reservoir. The head for the conversion between water flow and power can be approximated as a linear function of the water flow on which the head elevation is always the intake elevation.
"""
struct HydroTurbineWaterLinearDispatch <: AbstractHydroDispatchFormulation end

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

    Setting the energy target attribute in combination with [`EnergyTargetFeedforward`](@ref)
    or [`EnergyLimitFeedforward`](@ref) is not permitted and `StorageSystemsSimulations.jl`
    will throw an exception.

See the [`StorageDispatchWithReserves` Mathematical Model](@ref) for the full mathematical description.
"""
struct StorageDispatchWithReserves <: AbstractStorageFormulation end
