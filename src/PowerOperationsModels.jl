module PowerOperationsModels

#################################################################################
# Package imports
#################################################################################
import Dates
import InfrastructureSystems
import InfrastructureSystems: @assert_op, TableFormat
import JuMP
import JuMP.Containers: DenseAxisArray, SparseAxisArray
import Logging
import PowerNetworkMatrices
# Brought into namespace so the `export PTDF` / `export VirtualPTDF` below resolve (re-export to POM users)
import PowerNetworkMatrices: PTDF, VirtualPTDF
# Brought into namespace so `NetworkReductionSpec(RadialReduction())` resolves unqualified
# after `using PowerOperationsModels` (re-export to POM users)
import PowerNetworkMatrices:
    RadialReduction, DegreeTwoReduction, WardReduction, ZeroImpedanceBranchReduction
import PowerSystems
import PowerSystems: get_component
import PrettyTables
import ProgressMeter
import Serialization
import SparseArrays
import TimerOutputs
import InteractiveUtils: methodswith, subtypes

using DocStringExtensions
using JSON3

# Network-formulation abstract types: the two roots are IS-owned consts; the
# intermediates are POM-native. AbstractNetworkModel is brought in via the import
# block below.
import InfrastructureOptimizationModels: AbstractNetworkModel

# POM owns the network-formulation taxonomy; it roots at IOM's neutral AbstractNetworkModel.
abstract type AbstractActivePowerModel <: AbstractNetworkModel end
"""
Networks that carry a reactive power balance and an AC voltage representation: ACP, ACR,
IVR and LPACC. This is the exact complement of `AbstractActivePowerModel` among the
network models, and it is the set of networks the LCC converter and other reactive-aware
branch formulations require. Dispatch on it instead of enumerating the concrete networks;
a new reactive-capable network formulation should subtype it to inherit those methods.
"""
abstract type AbstractReactivePowerNetworkModel <: AbstractNetworkModel end
abstract type AbstractACPModel <: AbstractReactivePowerNetworkModel end
abstract type AbstractDCPNetworkModel <: AbstractActivePowerModel end
abstract type AbstractNFANetworkModel <: AbstractDCPNetworkModel end
abstract type AbstractDCPLLNetworkModel <: AbstractDCPNetworkModel end

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

#################################################################################
# Type Aliases
#################################################################################
const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization

const PSY = PowerSystems
const PNM = PowerNetworkMatrices

# Import abstract types from InfrastructureSystems.Optimization
import InfrastructureSystems.Optimization:
    VariableType,
    ConstraintType,
    AuxVariableType,
    ParameterType,
    ExpressionType,
    InitialConditionType,
    TimeSeriesParameter,
    RightHandSideParameter,
    ObjectiveFunctionParameter

# Import formulation abstract types from InfrastructureSystems.Optimization
# Note: AbstractPTDFNetworkModel is defined in this package (network_formulations.jl)
# as a subtype of AbstractDCPNetworkModel.
import InfrastructureSystems.Optimization:
    AbstractDeviceFormulation,
    AbstractThermalFormulation,
    AbstractLoadFormulation,
    AbstractRenewableFormulation,
    AbstractServiceFormulation,
    AbstractReservesFormulation,
    AbstractHVDCNetworkModel

#################################################################################
# Import InfrastructureOptimizationModels early for base functions
# These are needed before including core files that extend them
#################################################################################
import InfrastructureOptimizationModels
const IOM = InfrastructureOptimizationModels

# Import utility functions that core files will extend with new methods
import InfrastructureOptimizationModels:
    should_write_resulting_value,
    convert_output_to_natural_units,
    # Printing dispatch shared with IOM (POM adds the template method in utils/print.jl);
    # without this import POM would shadow IOM._show_method and break show(::DecisionModel).
    _show_method,
    # Network model compatibility checks (extended in core/network_formulations.jl)
    requires_all_branch_models,
    supports_branch_filtering,
    ignores_branch_filtering,
    branches_modeled

# Import functions that POM extends with device-specific implementations
import InfrastructureOptimizationModels:
    add_variables!,
    add_to_expression!,
    # Variable property functions (IOM has default stubs, POM adds device-specific methods)
    get_variable_binary,
    get_variable_lower_bound,
    get_variable_upper_bound,
    get_variable_warm_start_value,
    # Device/formulation attribute defaults (IOM has stubs, POM specializes)
    get_default_attributes,
    get_default_time_series_names,
    # proportional cost
    proportional_cost,
    is_time_variant_proportional,
    add_proportional_cost!,
    add_proportional_cost_maybe_time_variant!,
    skip_proportional_cost,
    # variable cost
    add_variable_cost!,
    # Network model instantiation (POM extends for concrete network formulations)
    instantiate_network_model!,
    # Parameter addition (POM provides concrete implementations)
    add_parameters!,
    # Cost/status functions (IOM has default stubs, POM adds device-specific methods)
    get_operation_cost,
    get_must_run,
    # Build-pipeline extension points (IOM declares stubs, POM extends)
    calculate_aux_variable_value!,
    is_from_evaluator,
    # External evaluation infrastructure (PowerFlows extension consumes these)
    EvaluationContainer,
    add_evaluator!,
    add_evaluation_data!,
    get_evaluations,
    get_evaluators,
    get_evaluation_data,
    get_inner_data,
    evaluate!,
    reset!,
    is_solved,
    reset_evaluations!,
    # Functions POM extends with new methods
    _onvar_cost,
    add_cost_to_expression!,
    add_linear_ramp_constraints!,
    add_service_variables!,
    add_proportional_cost_invariant!,
    requires_initialization,
    get_min_max_limits,
    start_up_cost,
    _get_initial_condition_type,
    set_ic_quantity!,
    update_container_parameter_values!

# Market bid cost: import IOM functions that POM extends with device-specific methods
import InfrastructureOptimizationModels:
    _consider_parameter,
    validate_occ_component,
    _include_min_gen_power_in_constraint,
    _include_constant_min_gen_power_in_constraint,
    add_variable_cost_to_objective!,
    _vom_offer_direction,
    add_pwl_constraint_delta!,
    add_pwl_term_delta!,
    # Internal utilities used by market bid overrides and proportional_cost
    is_time_variant,
    apply_maybe_across_time_series,
    _validate_eltype,
    objective_function_multiplier,
    get_piecewise_curve_per_system_unit,
    add_pwl_block_offer_constraints!,
    has_service_model,
    IncrementalOffer,
    DecrementalOffer,
    add_constraint_dual!,
    assign_dual_variable!,
    _calculate_dual_variable_value!,
    add_dual_container!,
    variable_cost,
    # Extend IOM interface functions so POM methods are added to the same functions
    get_device_models,
    get_branch_models,
    get_service_models,
    get_network_model,
    get_network_formulation,
    get_hvdc_network_model,
    get_component_types,
    get_model,
    set_network_model!,
    set_hvdc_network_model!,
    set_device_model!,
    set_service_model!,
    finalize_template!,
    validate_time_series!,
    validate_template,
    DecisionModel,
    EmulationModel,
    make_empty_jump_model_with_settings,
    set_model!

using InfrastructureOptimizationModels # TODO: use explicit imports.

# Cost expression types are imported explicitly so re-exports below are detected as
# defined bindings in POM (Aqua.test_undefined_exports requirement).
import InfrastructureOptimizationModels:
    ProductionCostExpression,
    FuelConsumptionExpression,
    ConstituentCostExpression,
    FuelCostExpression,
    StartUpCostExpression,
    ShutDownCostExpression,
    FixedCostExpression,
    VOMCostExpression,
    CurtailmentCostExpression

# Note: add_feedforward_arguments!, add_feedforward_constraints!,
# get_default_on_variable, get_default_off_variable are defined in POM, not IOM
# Note: ABSOLUTE_TOLERANCE is defined in POM's definitions.jl
# Note: TimeDurationOn and TimeDurationOff are defined in POM, not IOM

#################################################################################
# Include core type definitions
# These define concrete Variable, Expression, Constraint, and Parameter types
# and extend should_write_resulting_value/convert_output_to_natural_units
#################################################################################
include("core/definitions.jl")
include("core/problem_types.jl")
include("core/interfaces.jl")
include("core/default_interface_methods.jl")
include("core/physical_constant_definitions.jl")
include("core/reserve_traits.jl")
include("core/variables.jl")
include("core/expressions.jl")
include("core/constraints.jl")
include("core/auxiliary_variables.jl")
include("core/parameters.jl")
include("core/formulations.jl")
include("core/bilinear_configs.jl")
include("core/network_formulations.jl")
include("core/branch_slack_specs.jl")
include("core/problem_template.jl")
include("core/feedforward_interface.jl")
include("core/initial_conditions.jl")

# Common models - expression infrastructure
# Expression container creation (add_expressions!) and helpers
include("common_models/add_expressions.jl")
# Device-specific add_to_expression! implementations
include("common_models/add_to_expression.jl")
# Device-specific objective function helpers (curtailment cost, compact-form guards)
include("common_models/objective_function.jl")
# add_param_container.jl: moved into IOM
include("common_models/add_parameters.jl")
include("common_models/make_system_expressions.jl")
include("common_models/reserve_range_constraints.jl")
include("common_models/branch_rating_constraints.jl")
include("common_models/quadratic_converter_loss.jl")
include("common_models/network_conditional.jl")
include("common_models/regulated_voltage.jl")
include("common_models/converter_control.jl")

# Market bid cost plumbing (PSY orchestration moved out of IOM). Must be included
# before device-specific files that reference MBC_TYPES / IEC_TYPES.
include("common_models/market_bid_plumbing.jl")

# Initial Conditions
include("initial_conditions/add_initial_condition.jl")
include("initial_conditions/device_initial_conditions.jl")
include("initial_conditions/update_initial_conditions.jl")

# Device Models - Static Injectors
include("static_injector_models/thermal_generation.jl")
include("static_injector_models/thermalgeneration_constructor.jl")
include("static_injector_models/renewable_generation.jl")
include("static_injector_models/renewablegeneration_constructor.jl")
include("static_injector_models/electric_loads.jl")
include("static_injector_models/load_constructor.jl")
include("static_injector_models/source.jl")
include("static_injector_models/source_constructor.jl")
include("static_injector_models/reactivepower_device.jl")
include("static_injector_models/reactivepowerdevice_constructor.jl")
include("static_injector_models/shunt_models.jl")
include("static_injector_models/shunt_constructor.jl")
include("utils/psy_utils.jl")
include("static_injector_models/hydro_generation.jl")
include("static_injector_models/hydrogeneration_constructor.jl")

# Energy Storage Models
include("energy_storage_models/storage_models.jl")
include("energy_storage_models/storage_constructor.jl")

# POM market bid cost overrides (plumbing is included earlier, before device files)
include("common_models/market_bid_overrides.jl")

# AC Transmission Models
include("ac_transmission_models/RepresentativeBranch.jl")
include("ac_transmission_models/AC_branches.jl")
include("ac_transmission_models/security_constrained_branch.jl")
include("ac_transmission_models/branch_constructor.jl")
# psy6: disabled pending transformer refactor
# include("ac_transmission_models/voltage_control_tap_models.jl")
# include("ac_transmission_models/transformer_models.jl")

# Network Models
include("network_models/network_reductions.jl")
include("network_models/reduction_exceptions.jl")
include("network_models/network_sources.jl")
include("network_models/network_data.jl")
include("network_models/instantiate_network_model.jl")
include("network_models/network_slack_variables.jl")
include("network_models/copperplate_model.jl")
include("network_models/area_balance_model.jl")
include("network_models/dcp_model.jl")
include("network_models/dcpll_model.jl")
include("network_models/acp_model.jl")
include("network_models/acr_model.jl")
include("network_models/lpacc_model.jl")
include("network_models/network_constructor.jl")

# Services Models
include("services_models/service_slacks.jl")
include("services_models/reserves.jl")
include("services_models/reserve_offers.jl")
include("services_models/reserve_group.jl")
# include("services_models/agc.jl")  # TODO: needs _get_ace_error
include("services_models/transmission_interface.jl")
include("services_models/services_constructor.jl")

# Hybrid System Models (after services_models since they share reserve infrastructure)
include("hybrid_system_models/hybrid_systems.jl")
include("hybrid_system_models/hybridsystem_constructor.jl")

# Two-Terminal HVDC Models
include("twoterminal_hvdc_models/TwoTerminalDC_branches.jl")
include("twoterminal_hvdc_models/voltage_control_vsc_models.jl")

# Multi-Terminal HVDC Models
include("mt_hvdc_models/HVDCsystems.jl")
include("mt_hvdc_models/hvdcsystems_constructor.jl")
include("mt_hvdc_models/voltage_control_converter_models.jl")

# HVDC Network Models
include("network_models/hvdc_networks.jl")
include("network_models/hvdc_network_constructor.jl")

# Area interchange
include("area_interchange.jl")

# Operation lifecycle: build/solve/run
include("operation/build_problem.jl")
include("initial_conditions/initialization.jl")
include("operation/template_validation.jl")
include("operation/decision_model.jl")
include("operation/emulation_model.jl")

include("utils/generate_valid_formulations.jl")
include("utils/print.jl")

# Import private/internal helpers (use import to avoid undeclared warning)
import InfrastructureOptimizationModels: _get_ramp_constraint_devices
import InfrastructureOptimizationModels:
    get_param_eltype,
    CONTAINER_KEY_EMPTY_META

# Import high-frequency IOM internals used throughout operation lifecycle code.
# Note: BUILD_PROBLEMS_TIMER and RUN_OPERATION_MODEL_TIMER are defined in POM's
# definitions.jl, so they are NOT imported from IOM.
import InfrastructureOptimizationModels:
    LOG_GROUP_OPTIMIZATION_CONTAINER,
    get_store,
    set_status!,
    get_problem_size

# Functions defined in POM (core/interfaces.jl)
export construct_device!
export construct_service!
export add_to_objective_function!
export add_constraints!
export get_variable_multiplier
export get_expression_multiplier
export get_multiplier_value
export add_power_flow_data!
export power_flow_evaluations
export get_initial_conditions_device_model
export add_reserve_variables!

#################################################################################
# Exports - Base Models
#################################################################################
export DecisionModel
export EmulationModel
export PowerOperationsProblemTemplate
export InitialCondition
export AbstractPowerOperationProblem
export AbstractPowerDecisionProblem
export AbstractPowerEmulationProblem
export DefaultPowerDecisionProblem
export DefaultPowerEmulationProblem

# Network
export NetworkModel

# Model Container Types
export DeviceModel
export ServiceModel
export OptimizationContainer

# Initial Conditions Quantities
export DevicePower
export DeviceStatus
export InitialTimeDurationOn
export InitialTimeDurationOff
export InitialEnergyLevel

# Functions
export build!
export get_initial_conditions
export serialize_outputs
export serialize_optimization_model
export solve!
export run!
export set_device_model!
export set_service_model!
export set_network_model!
export get_network_formulation
export get_hvdc_network_model
export set_hvdc_network_model!
export validate_time_series!
export init_optimization_container!
export get_network_model
export get_value
export get_initial_conditions_data
export get_initial_condition_value
export get_objective_expression
export get_formulation
export TimeDurationOn
export TimeDurationOff

# Alias for InfrastructureSystems.Optimization needed by tests
export ISOPT

# Re-export TableFormat from InfrastructureSystems (via IOM)
export TableFormat

# Outputs interfaces
export get_variable_values
export get_dual_values
export get_parameter_values
export get_aux_variable_values
export get_expression_values
export get_timestamps
export get_system
export read_variable
export read_dual
export read_parameter
export read_aux_variable
export read_expression
export read_variables
export read_duals
export read_parameters
export read_aux_variables
export read_expressions
export get_problem_base_power
export get_objective_value
export read_optimizer_stats

# Utils
export OptimizationProblemOutputs
export OptimizationProblemOutputsExport
export OptimizerStats
export get_all_constraint_index
export get_all_variable_index
export get_constraint_index
export get_variable_index
export list_recorder_events
export jump_value
export ConstraintBounds
export VariableBounds

# Key Types
export VariableKey
export ConstraintKey
export ParameterKey
export ExpressionKey
export AuxVarKey

# Status Enums
export ModelBuildStatus
export RunStatus
export SimulationBuildStatus

# Problem Types
export GenericPowerDecisionProblem
export GenericPowerEmulationProblem

# Settings and Data Types
export Settings
export InitialConditionsData

# Constants
export COST_EPSILON
export INITIALIZATION_PROBLEM_HORIZON_COUNT

#################################################################################
# Exports - Variable Types (defined in core/variables.jl)
#################################################################################
# Power Variables
export ActivePowerVariable
export ActivePowerInVariable
export ActivePowerOutVariable
export ReactivePowerVariable
export PowerAboveMinimumVariable

# Status Variables
export OnVariable
export StartVariable
export StopVariable
export HotStartVariable
export WarmStartVariable
export ColdStartVariable

# Energy Variables
export EnergyVariable

# Reserve Variables
export ReservationVariable
export ActivePowerReserveVariable
export ServiceRequirementVariable

# Auxiliary Variables
export LiftVariable

# System Balance Variables
export SteadyStateFrequencyDeviation
export AreaMismatchVariable
export DeltaActivePowerUpVariable
export DeltaActivePowerDownVariable
export AdditionalDeltaActivePowerUpVariable
export AdditionalDeltaActivePowerDownVariable
export SmoothACE
export SystemBalanceSlackUp
export SystemBalanceSlackDown
export ReserveRequirementSlack

# Network Variables
export VoltageMagnitude
export RegulatedVoltageMagnitude
export VoltageAngle
export VoltageReal
export VoltageImaginary
export VoltageDeviation
export CosineApproximation
export BranchCurrentFromToReal
export BranchCurrentFromToImaginary
export BranchCurrentToFromReal
export BranchCurrentToFromImaginary
export BranchSeriesCurrentReal
export BranchSeriesCurrentImaginary
export FlowActivePowerVariable
export FlowActivePowerSlackUpperBound
export FlowActivePowerSlackLowerBound
export PostContingencyFlowActivePowerSlackUpperBound
export PostContingencyFlowActivePowerSlackLowerBound
export FlowActivePowerFromToVariable
export FlowActivePowerToFromVariable
export FlowReactivePowerFromToVariable
export FlowReactivePowerToFromVariable
export PhaseShifterAngle

# Feedforward Slack Variables
export UpperBoundFeedForwardSlack
export LowerBoundFeedForwardSlack
export InterfaceFlowSlackUp
export InterfaceFlowSlackDown

# Cost Variables
export PiecewiseLinearCostVariable

# Rate Constraint Slack Variables
export RateofChangeConstraintSlackUp
export RateofChangeConstraintSlackDown

# HVDC Variables
export DCVoltage
export DCLineCurrent
export ConverterCurrent
export CurrentAbsoluteValueVariable
export ConverterACCurrentVariable
export ConverterACCurrentFromVariable
export ConverterACCurrentToVariable
export HVDCFlowDirectionVariable
export HVDCLosses
export HVDCFromDCVoltage
export HVDCToDCVoltage
export HVDCReactivePowerFromVariable
export HVDCReactivePowerToVariable

# Load Variables
export ShiftUpActivePowerVariable
export ShiftDownActivePowerVariable

######## Hydro Formulations ########
export HydroDispatchRunOfRiver
export HydroCommitmentRunOfRiver
export HydroWaterFactorModel
export HydroWaterModelReservoir
export HydroTurbineBilinearDispatch
export HydroTurbineWaterLinearDispatch
export HydroTurbineWaterLinearCommitment
export HydroEnergyModelReservoir
export HydroTurbineEnergyDispatch
export HydroTurbineEnergyCommitment
export HydroPumpEnergyDispatch
export HydroPumpEnergyCommitment

######## Hydro Variables ########
export WaterSpillageVariable
export HydroEnergyShortageVariable
export HydroEnergySurplusVariable
export HydroWaterShortageVariable
export HydroWaterSurplusVariable
export HydroReservoirHeadVariable
export HydroReservoirVolumeVariable
export HydroTurbineFlowRateVariable
export HydroBalanceShortageVariable
export HydroBalanceSurplusVariable
export ActivePowerPumpVariable

######## Hydro Aux Variables ########
export HydroEnergyOutput

######## Hydro parameters #######
export EnergyTargetTimeSeriesParameter
export EnergyBudgetTimeSeriesParameter
export WaterTargetTimeSeriesParameter
export WaterBudgetTimeSeriesParameter
export InflowTimeSeriesParameter
export OutflowTimeSeriesParameter
export EnergyCapacityTimeSeriesParameter
export ReservoirTargetParameter
export ReservoirLimitParameter
export HydroUsageLimitParameter
export WaterLevelBudgetParameter

######## Hydro Initial Conditions #######
export InitialReservoirVolume

######## Hydro Constraints #######
export EnergyTargetConstraint
export WaterTargetConstraint
export ActivePowerPumpReservationConstraint
export ActivePowerPumpVariableLimitsConstraint
export EnergyCapacityTimeSeriesLimitsConstraint
export EnergyBudgetConstraint
export WaterBudgetConstraint
export ReservoirLevelLimitConstraint
export ReservoirLevelTargetConstraint
export TurbinePowerOutputConstraint
export ReservoirHeadToVolumeConstraint
export ReservoirInventoryConstraint
export FeedForwardWaterLevelBudgetConstraint

####### Hydro Expressions ########
export HydroServedReserveUpExpression
export HydroServedReserveDownExpression
export TotalHydroPowerReservoirIncoming
export TotalHydroPowerReservoirOutgoing
export TotalSpillagePowerReservoirIncoming
export TotalHydroFlowRateReservoirIncoming
export TotalHydroFlowRateReservoirOutgoing
export TotalSpillageFlowRateReservoirIncoming
export TotalHydroFlowRateTurbineOutgoing

######## Storage Formulations ########
export StorageDispatchWithReserves

# variables
export AncillaryServiceVariableDischarge
export AncillaryServiceVariableCharge
export StorageEnergyShortageVariable
export StorageEnergySurplusVariable
export StorageChargeCyclingSlackVariable
export StorageDischargeCyclingSlackVariable
export StorageRegularizationVariableCharge
export StorageRegularizationVariableDischarge

# aux variables
export StorageEnergyOutput

# constraints
export EnergyBalanceConstraint
export StateofChargeLimitsConstraint
export StateofChargeTargetConstraint
export HybridEnergyTargetConstraint
export StorageCyclingCharge
export StorageCyclingDischarge
export StorageRegularizationConstraintCharge
export StorageRegularizationConstraintDischarge
export ReserveCoverageConstraint
export ReserveCoverageConstraintEndOfPeriod
export ReserveCompleteCoverageConstraint
export ReserveCompleteCoverageConstraintEndOfPeriod
export StorageTotalReserveConstraint
export ReserveDischargeConstraint
export ReserveChargeConstraint

# expressions
export TotalReserveOffering

# parameters
export EnergyLimitParameter
export EnergyTargetParameter

######## Hybrid System Formulations ########
export AbstractHybridFormulation
export AbstractHybridFormulationWithReserves
export HybridDispatchWithReserves

# Reserve / constraint marker traits used to parametrize hybrid + storage families.
export ReserveScale, UnscaledReserve, DeployedReserve
export ReserveSide, DischargeSide, ChargeSide

# variables
export HybridEnergyShortageVariable
export HybridEnergySurplusVariable
export HybridRenewableActivePower
export HybridRenewableReserveVariable
export HybridStorageReservation
export HybridThermalActivePower
export HybridThermalReserveVariable

# expressions

# constraints
export HybridEnergyAssetBalanceConstraint
export HybridRenewableActivePowerLimitConstraint
export HybridRenewableReserveLimitConstraint
export HybridReserveAssignmentConstraint
export HybridReserveBalanceConstraint
export HybridStorageBalanceConstraint
export HybridThermalReserveLimitConstraint

# parameters
export HybridElectricLoadTimeSeriesParameter
export HybridRenewableActivePowerTimeSeriesParameter

#################################################################################
# Exports - Constraint Types (defined in core/constraints.jl)
#################################################################################
export FlowRateConstraint
export FlowRateConstraintFromTo
export FlowRateConstraintToFrom
export PostContingencyFlowRateConstraint
export FlowLimitConstraint
export FlowLimitFromToConstraint
export FlowLimitToFromConstraint
export ImportExportBudgetConstraint
export ActivePowerVariableLimitsConstraint
export InputActivePowerVariableLimitsConstraint
export ActivePowerVariableTimeSeriesLimitsConstraint
export ActivePowerOutVariableTimeSeriesLimitsConstraint
export ActivePowerInVariableTimeSeriesLimitsConstraint
export PiecewiseLinearBlockIncrementalOfferConstraint
export PiecewiseLinearBlockDecrementalOfferConstraint
export RampConstraint
export RampLimitConstraint
export CopperPlateBalanceConstraint
export ActiveRangeICConstraint
export NodalBalanceActiveConstraint
export ReferenceBusConstraint
export VoltageMagnitudeConstraint
export ReactivePowerFlowControlConstraint
export RegulatedVoltageMagnitudeConstraint
export CurrentLimitConstraint
export AngleDifferenceConstraint
export CosineRelaxationConstraint
export RequirementConstraint
export DurationConstraint
export CommitmentConstraint
export StartTypeConstraint
export StartupTimeLimitTemperatureConstraint
export ShiftedActivePowerBalanceConstraint
export ShiftUpActivePowerVariableLimitsConstraint
export ShiftDownActivePowerVariableLimitsConstraint
export RealizedShiftedLoadMinimumBoundConstraint
export NonAnticipativityConstraint
export HVDCDCControlConstraint

#################################################################################
# Exports - Expression Types (defined in core/expressions.jl)
#################################################################################
export SystemBalanceExpressions
export RangeConstraintLBExpressions
export RangeConstraintUBExpressions
export CostExpressions
export ActivePowerBalance
export ReactivePowerBalance
export EmergencyUp
export EmergencyDown
export RawACE
export ProductionCostExpression
export ConstituentCostExpression
export FuelCostExpression
export StartUpCostExpression
export ShutDownCostExpression
export FixedCostExpression
export VOMCostExpression
export CurtailmentCostExpression
export FuelConsumptionExpression
export ActivePowerRangeExpressionLB
export ActivePowerRangeExpressionUB
export PostContingencyBranchFlow
export NetActivePower
export DCCurrentBalance
export ComponentReserveUpBalanceExpression
export ComponentReserveDownBalanceExpression
export InterfaceTotalFlow
export PTDFBranchFlow
export BThetaBranchFlow

#################################################################################
# Exports - Parameter Types (defined in core/parameters.jl)
#################################################################################
export ActivePowerTimeSeriesParameter
export ActivePowerOutTimeSeriesParameter
export ActivePowerInTimeSeriesParameter
export ReactivePowerTimeSeriesParameter
export RequirementTimeSeriesParameter
export UpperBoundValueParameter
export LowerBoundValueParameter
export OnStatusParameter
# FixValueParameter: moved into IOM, re-exported via `using IOM`

#################################################################################
# Exports - Formulation Types (defined in core/formulations.jl)
#################################################################################
# Device Formulation Abstract Types
export AbstractDeviceFormulation
export AbstractThermalFormulation
export AbstractLoadFormulation
export AbstractRenewableFormulation
export AbstractBranchFormulation

# Thermal Formulations
export ThermalBasicUnitCommitment
export ThermalStandardUnitCommitment
export ThermalBasicDispatch
export ThermalStandardDispatch
export ThermalDispatchNoMin
export ThermalMultiStartUnitCommitment
export ThermalCompactUnitCommitment
export ThermalBasicCompactUnitCommitment
export ThermalCompactDispatch

# Load Formulations
export StaticPowerLoad
export PowerLoadInterruption
export PowerLoadDispatch
export PowerLoadShift

# Renewable Formulations
export RenewableFullDispatch
export RenewableConstantPowerFactor

# Source Formulations
export ImportExportSourceModel

# SynCons Formulations
export SynchronousCondenserBasicDispatch

# Shunt Formulations
export AbstractShuntFormulation
export ShuntSusceptanceDispatch
export FixedShuntAdmittance
export ShuntSusceptanceVariable
export ShuntReactivePowerConstraint

# Branch Formulations
export StaticBranch
export StaticBranchBounds
export StaticBranchUnbounded
export SecurityConstrainedStaticBranch
# psy6: disabled pending transformer refactor
# export PhaseAngleControl
# export TapControl
# export VoltageControlTap
export TapRatioVariable

# DC Branch Formulations
export HVDCTwoTerminalUnbounded
export HVDCTwoTerminalLossless
export HVDCTwoTerminalDispatch
export HVDCTwoTerminalPiecewiseLoss
export HVDCTwoTerminalLCC
export HVDCTwoTerminalVSC
export VoltageControlVSC

# Converter Formulations
export LosslessConverter
export LinearLossConverter
export AbstractQuadraticLossConverter
export QuadraticLossConverter
export VoltageControlConverter

# DC Line Formulations
export DCLossyLine
export LosslessLine

# HVDC Network Model Formulations
export AbstractHVDCNetworkModel
export TransportHVDCNetworkModel
export VoltageDispatchHVDCNetworkModel

# Service Formulations
export AbstractServiceFormulation
export AbstractReservesFormulation
export PIDSmoothACE
export GroupRangeReserve
export RangeReserve
export StepwiseCostReserve
export RampReserve
export NonSpinningReserve
export ConstantMaxInterfaceFlow
export VariableMaxInterfaceFlow

# Regulation Formulations
export ReserveLimitedRegulation
export DeviceLimitedRegulation

#################################################################################
# Exports - Network Formulation Types (defined in core/network_formulations.jl)
#################################################################################
# Power Model Abstract Type (from IS.Optimization)
export AbstractNetworkModel

# Concrete Network Formulations
export AbstractPTDFNetworkModel
export PTDFNetworkModel
export CopperPlateNetworkModel
export AreaBalanceNetworkModel
export AreaPTDFNetworkModel

# JuMP utilities
export optimizer_with_attributes

# Network formulation types (DCPNetworkModel/ACPNetworkModel/ACRNetworkModel/NFANetworkModel
# defined in core/network_formulations.jl; abstract roots come from IS.Optimization or POM)
export DCPNetworkModel
export ACPNetworkModel
export ACRNetworkModel
export LPACCNetworkModel
export IVRNetworkModel
export AbstractDCPNetworkModel
export AbstractACPModel
export AbstractACRNetworkModel
export AbstractLPACCNetworkModel
export AbstractIVRNetworkModel
export AbstractActivePowerModel
export AbstractReactivePowerNetworkModel
export NFANetworkModel
export DCPLLNetworkModel

# Network source declarations (network_models/network_sources.jl); the derived
# network-data containers stay unexported — they are build outputs, not user inputs.
export NetworkReductionSpec
export PrebuiltMatrixSource
export PrebuiltCoreSource

# PowerNetworkMatrices
export PTDF
export VirtualPTDF
export RadialReduction
export DegreeTwoReduction
export WardReduction
export ZeroImpedanceBranchReduction

# Other utilities
export get_name
export get_model_base_power
export get_optimizer_stats
export get_resolution

export BranchRatingTimeSeriesParameter
export PostContingencyBranchRatingTimeSeriesParameter

# Network model capability traits (IOM default + POM overrides in core/network_formulations.jl)
export branches_modeled

end
