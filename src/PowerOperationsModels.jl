module PowerOperationsModels

#################################################################################
# Package imports
#################################################################################
import Dates
import InfrastructureSystems
import InfrastructureSystems: @assert_op
import JuMP
import Memento
import JuMP.Containers: DenseAxisArray, SparseAxisArray
import PowerNetworkMatrices
import PowerSystems
import TimerOutputs

using DocStringExtensions

#################################################################################
# Embedded submodules (adapted from InfrastructureModels.jl and PowerModels.jl)
#################################################################################
include("InfrastructureModels/InfrastructureModels.jl")
include("PowerModels/PowerModels.jl")

const PM = PowerModels

# Import PM types into module namespace for re-export
using .PowerModels:
    DCPPowerModel,
    ACPPowerModel,
    AbstractDCPModel,
    AbstractACPModel,
    AbstractActivePowerModel,
    NFAPowerModel

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
import InfrastructureSystems.Optimization:
    AbstractDeviceFormulation,
    AbstractPowerModel,
    AbstractHVDCNetworkModel

#################################################################################
# Import InfrastructureOptimizationModels early for base functions
# These are needed before including core files that extend them
#################################################################################
import InfrastructureOptimizationModels
const POM = InfrastructureOptimizationModels

# Import utility functions that core files will extend with new methods
import InfrastructureOptimizationModels:
    should_write_resulting_value,
    convert_result_to_natural_units

# Import functions that POM extends with device-specific implementations
# These are the main extension points where POM provides concrete implementations
import InfrastructureOptimizationModels:
    construct_device!,
    construct_service!,
    add_variables!,
    add_constraints!,
    add_to_expression!,
    add_expressions!,
    objective_function!,
    initial_condition_variable,
    initial_condition_default,
    get_initial_conditions_value,
    update_initial_conditions!,
    add_initial_condition!,
    # Variable/expression multiplier functions (have stubs in IOM)
    get_variable_multiplier,
    get_expression_multiplier,
    get_multiplier_value

# Import types needed by device model files
using InfrastructureOptimizationModels:
    # Core types
    FixedOutput,
    OptimizationContainer,
    DeviceModel,
    ServiceModel,
    NetworkModel,
    OperationModel,
    ProblemTemplate,
    DecisionModel,
    EmulationModel,
    InitialCondition,
    # Construction stages
    ArgumentConstructStage,
    ModelConstructStage,
    # Key types
    AuxVarKey,
    VariableKey,
    ConstraintKey,
    ParameterKey,
    ExpressionKey,
    OptimizationContainerKey,
    # Container types
    ParameterContainer,
    EmulationModelStore,
    # Branch model types
    BranchModelContainer,
    DeviceModelForBranches,
    # Initial condition types
    DeviceStatus,
    DevicePower,
    DeviceAboveMinPower,
    InitialTimeDurationOn,
    InitialTimeDurationOff,
    InitialEnergyLevel,
    # Cost types
    StartUpStages,
    # Expression types (abstract and concrete)
    SystemBalanceExpressions,
    RangeConstraintLBExpressions,
    RangeConstraintUBExpressions,
    CostExpressions,
    PostContingencyExpressions,
    ActivePowerBalance,
    ReactivePowerBalance,
    EmergencyUp,
    EmergencyDown,
    RawACE,
    ProductionCostExpression,
    FuelConsumptionExpression,
    ActivePowerRangeExpressionLB,
    ActivePowerRangeExpressionUB,
    PostContingencyBranchFlow,
    PostContingencyActivePowerGeneration,
    NetActivePower,
    DCCurrentBalance,
    # Note: HVDCPowerBalance is NOT imported - POM defines its own HVDCPowerBalance <: ConstraintType
    # while IOM has HVDCPowerBalance <: ExpressionType. These are different types.
    # Status enums
    ModelBuildStatus,
    RunStatus,
    SimulationBuildStatus,
    # Settings and data types
    Settings,
    InitialConditionsData,
    # Problem types
    DefaultDecisionProblem,
    DefaultEmulationProblem,
    # Result types
    OptimizationProblemResults,
    OptimizationProblemResultsExport,
    OptimizerStats,
    ConstraintBounds,
    VariableBounds,
    # Constants
    # Note: COST_EPSILON, INITIALIZATION_PROBLEM_HORIZON_COUNT, HOURS_IN_WEEK
    # are defined in POM's definitions.jl, not imported from IOM
    LOG_GROUP_BUILD_INITIAL_CONDITIONS,
    # PowerNetworkMatrices types (re-exported by IOM)
    PTDF,
    VirtualPTDF,
    LODF,
    VirtualLODF,
    # JuMP utilities
    optimizer_with_attributes,
    # Expression infrastructure (generic functions from IOM)
    add_constant_to_jump_expression!,
    add_proportional_to_jump_expression!,
    add_linear_to_jump_expression!,
    # Core model functions
    get_available_components,
    get_attribute,
    get_time_steps,
    get_resolution,
    get_time_series_names,
    get_initial_condition,
    get_initial_conditions,
    get_initial_conditions_data,
    get_initial_condition_value,
    get_initial_conditions_value,
    # Container access functions
    get_expression,
    get_variable,
    get_parameter,
    get_parameter_array,
    get_multiplier_array,
    get_parameter_column_refs,
    has_container_key,
    get_constraints,
    get_constraint,
    get_aux_variables,
    get_optimization_container,
    get_internal,
    # Model building functions
    add_to_expression!,
    add_variables!,
    add_constraints!,
    add_parameters!,
    add_constraints_container!,
    add_expression_container!,
    add_variable_cost!,
    objective_function!,
    # Initial condition functions
    add_initial_condition!,
    add_initial_condition_container!,
    has_initial_condition_value,
    update_initial_conditions!,
    set_ic_quantity!,
    get_last_recorded_value,
    get_component_type,
    get_component_name,
    add_jump_parameter,
    # Network/template functions
    get_network_model,
    get_network_reduction,
    get_service_name,
    get_default_time_series_type,
    get_reference_bus,
    get_template,
    get_model,
    get_formulation,
    get_network_formulation,
    get_hvdc_network_model,
    set_device_model!,
    set_service_model!,
    set_network_model!,
    set_hvdc_network_model!,
    set_resolution!,
    finalize_template!,
    # Model operations
    build!,
    solve!,
    run!,
    serialize_problem,
    serialize_results,
    serialize_optimization_model,
    validate_time_series!,
    init_optimization_container!,
    process_market_bid_parameters!,
    # JuMP access
    get_jump_model,
    jump_value,
    # Settings access
    get_settings,
    get_rebuild_model,
    get_value,
    get_objective_expression,
    # Results functions
    get_variable_values,
    get_dual_values,
    get_parameter_values,
    get_aux_variable_values,
    get_expression_values,
    get_timestamps,
    get_system,
    get_problem_base_power,
    get_objective_value,
    read_variable,
    read_dual,
    read_parameter,
    read_aux_variable,
    read_expression,
    read_variables,
    read_duals,
    read_parameters,
    read_aux_variables,
    read_expressions,
    read_optimizer_stats,
    # Index utilities
    get_all_constraint_index,
    get_all_variable_index,
    get_constraint_index,
    get_variable_index,
    list_recorder_events,
    # Other utilities
    get_name,
    get_model_base_power,
    get_optimizer_stats,
    # Result writing/conversion methods to extend
    should_write_resulting_value,
    convert_result_to_natural_units
    # Note: add_feedforward_arguments!, add_feedforward_constraints!,
    # get_default_on_variable, get_default_off_variable are defined in POM, not IOM
    # Note: ABSOLUTE_TOLERANCE is defined in POM's definitions.jl
    # Note: TimeDurationOn and TimeDurationOff are defined in POM, not IOM

#################################################################################
# Include core type definitions
# These define concrete Variable, Expression, Constraint, and Parameter types
# and extend should_write_resulting_value/convert_result_to_natural_units
#################################################################################
include("core/definitions.jl")
include("core/variables.jl")
include("core/expressions.jl")
include("core/constraints.jl")
include("core/auxiliary_variables.jl")
include("core/parameters.jl")
include("core/formulations.jl")
include("core/network_formulations.jl")

# Common models - expression infrastructure
# Device-specific add_to_expression! implementations
include("common_models/add_to_expression.jl")

# Initial Conditions - Device-specific implementations
# These extend the generic infrastructure from IOM
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

# AC Transmission Models
include("ac_transmission_models/AC_branches.jl")
include("ac_transmission_models/branch_constructor.jl")

# Network Models
include("network_models/network_slack_variables.jl")
include("network_models/copperplate_model.jl")
include("network_models/area_balance_model.jl")
include("network_models/powermodels_interface.jl")
include("network_models/pm_translator.jl")
include("network_models/network_constructor.jl")

# TODO: Add more model includes as they are ready
# include("static_injector_models/static_injection_security_constrained_models.jl")
# include("network_models/hvdc_networks.jl")
# include("network_models/hvdc_network_constructor.jl")
# include("network_models/security_constrained_models.jl")
# include("twoterminal_hvdc_models/...")
# include("mt_hvdc_models/...")
# include("services_models/...")

# Import private/internal helpers (use import to avoid undeclared warning)
import InfrastructureOptimizationModels: _get_ramp_constraint_devices

#################################################################################
# Exports - Base Models
#################################################################################
export DecisionModel
export EmulationModel
export ProblemTemplate
export InitialCondition
export OperationModel

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
export serialize_problem
export serialize_results
export serialize_optimization_model
export solve!
export run!
export set_device_model!
export set_service_model!
export set_network_model!
export get_network_formulation
export get_hvdc_network_model
export set_hvdc_network_model!
export process_market_bid_parameters!
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

# Results interfaces
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
export OptimizationProblemResults
export OptimizationProblemResultsExport
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
export DefaultDecisionProblem
export DefaultEmulationProblem

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
export VoltageAngle
export FlowActivePowerVariable
export FlowActivePowerSlackUpperBound
export FlowActivePowerSlackLowerBound
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

# Contingency Variables
export PostContingencyActivePowerChangeVariable
export PostContingencyActivePowerReserveDeploymentVariable

# HVDC Variables
export DCVoltage
export DCLineCurrent
export ConverterPowerDirection
export ConverterCurrent
export SquaredConverterCurrent
export InterpolationSquaredCurrentVariable
export InterpolationBinarySquaredCurrentVariable
export ConverterPositiveCurrent
export ConverterNegativeCurrent
export SquaredDCVoltage
export InterpolationSquaredVoltageVariable
export InterpolationBinarySquaredVoltageVariable
export AuxBilinearConverterVariable
export AuxBilinearSquaredConverterVariable
export InterpolationSquaredBilinearVariable
export InterpolationBinarySquaredBilinearVariable
export HVDCFlowDirectionVariable
export HVDCLosses
export ConverterDCPower
export ConverterCurrentDirection

#################################################################################
# Exports - Constraint Types (defined in core/constraints.jl)
#################################################################################
export FlowRateConstraint
export FlowRateConstraintFromTo
export FlowRateConstraintToFrom
export FlowLimitConstraint
export FlowLimitFromToConstraint
export FlowLimitToFromConstraint
export ImportExportBudgetConstraint
export ActivePowerVariableLimitsConstraint
export InputActivePowerVariableLimitsConstraint
export ActivePowerOutVariableTimeSeriesLimitsConstraint
export ActivePowerInVariableTimeSeriesLimitsConstraint
export PiecewiseLinearBlockIncrementalOfferConstraint
export PiecewiseLinearBlockDecrementalOfferConstraint
export RateLimitConstraint
export RateLimitConstraintFromTo
export RateLimitConstraintToFrom
export RampConstraint
export RampLimitConstraint
export CopperPlateBalanceConstraint
export ActiveRangeICConstraint
export NodalBalanceActiveConstraint
export RequirementConstraint
export DurationConstraint
export CommitmentConstraint
export StartTypeConstraint

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
export FuelConsumptionExpression
export ActivePowerRangeExpressionLB
export ActivePowerRangeExpressionUB
export PostContingencyBranchFlow
export PostContingencyActivePowerGeneration
export PostContingencyActivePowerBalance
export NetActivePower
export DCCurrentBalance
export ComponentReserveUpBalanceExpression
export ComponentReserveDownBalanceExpression
export InterfaceTotalFlow
export PTDFBranchFlow

#################################################################################
# Exports - Parameter Types (defined in core/parameters.jl)
#################################################################################
export ActivePowerTimeSeriesParameter
export ReactivePowerTimeSeriesParameter
export RequirementTimeSeriesParameter
export UpperBoundValueParameter
export LowerBoundValueParameter
export OnStatusParameter
export FixValueParameter

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
export ThermalSecurityConstrainedStandardUnitCommitment

# Load Formulations
export StaticPowerLoad
export PowerLoadInterruption
export PowerLoadDispatch

# Renewable Formulations
export RenewableFullDispatch
export RenewableConstantPowerFactor
export RenewableSecurityConstrainedFullDispatch

# Source Formulations
export ImportExportSourceModel

# Branch Formulations
export StaticBranch
export StaticBranchBounds
export StaticBranchUnbounded
export PhaseAngleControl

# DC Branch Formulations
export HVDCTwoTerminalUnbounded
export HVDCTwoTerminalLossless
export HVDCTwoTerminalDispatch
export HVDCTwoTerminalPiecewiseLoss
export HVDCTwoTerminalLCC

# Converter Formulations
export LosslessConverter
export LinearLossConverter
export QuadraticLossConverter

# DC Line Formulations
export DCLosslessLine
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
export GroupReserve
export RangeReserve
export RangeReserveWithDeliverabilityConstraints
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
export AbstractPowerModel

# Concrete Network Formulations
export AbstractPTDFModel
export PTDFPowerModel
export CopperPlatePowerModel
export AreaBalancePowerModel
export AreaPTDFPowerModel

# JuMP utilities
export optimizer_with_attributes

# PowerModels types (from embedded PM submodule)
export DCPPowerModel
export ACPPowerModel
export AbstractDCPModel
export AbstractACPModel
export AbstractActivePowerModel
export NFAPowerModel

# PowerNetworkMatrices
export PTDF
export VirtualPTDF
export LODF
export VirtualLODF

# Other utilities
export get_name
export get_model_base_power
export get_optimizer_stats
export get_resolution

end
