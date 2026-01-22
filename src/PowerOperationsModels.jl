module PowerOperationsModels

#################################################################################
# Package imports
#################################################################################
import Dates
import InfrastructureSystems
import JuMP
import PowerSystems
import TimerOutputs

using DocStringExtensions

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

#################################################################################
# Include core type definitions
# These define concrete Variable, Expression, Constraint, and Parameter types
# and extend should_write_resulting_value/convert_result_to_natural_units
#################################################################################
include("core/variables.jl")
include("core/expressions.jl")
include("core/constraints.jl")
include("core/auxiliary_variables.jl")
include("core/formulations.jl")
include("core/network_formulations.jl")

#################################################################################
# Import and re-export from InfrastructureOptimizationModels
# Infrastructure types and functions that are not type definitions
#################################################################################

using InfrastructureOptimizationModels:
    # Base Models
    DecisionModel,
    EmulationModel,
    ProblemTemplate,
    InitialCondition,
    OperationModel,
    # Network
    NetworkModel,
    # Model Container Types
    DeviceModel,
    ServiceModel,
    # Optimization Container
    OptimizationContainer,
    # Initial Conditions Quantities
    DevicePower,
    DeviceStatus,
    InitialTimeDurationOn,
    InitialTimeDurationOff,
    InitialEnergyLevel,
    # Functions
    build!,
    get_initial_conditions,
    serialize_problem,
    serialize_results,
    serialize_optimization_model,
    solve!,
    run!,
    set_device_model!,
    set_service_model!,
    set_network_model!,
    get_network_formulation,
    get_hvdc_network_model,
    set_hvdc_network_model!,
    get_available_components,
    get_attribute,
    get_time_steps,
    get_resolution,
    get_variable,
    get_jump_model,
    add_variable_cost!,
    add_variables!,
    add_constraints!,
    add_constraints_container!,
    # Results interfaces
    get_variable_values,
    get_dual_values,
    get_parameter_values,
    get_aux_variable_values,
    get_expression_values,
    get_timestamps,
    get_system,
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
    get_problem_base_power,
    get_objective_value,
    read_optimizer_stats,
    # Utils
    OptimizationProblemResults,
    OptimizationProblemResultsExport,
    OptimizerStats,
    get_all_constraint_index,
    get_all_variable_index,
    get_constraint_index,
    get_variable_index,
    list_recorder_events,
    # Status Enums
    ModelBuildStatus,
    RunStatus,
    # Construction stages
    ArgumentConstructStage,
    ModelConstructStage,
    # JuMP utilities
    optimizer_with_attributes,
    # PowerNetworkMatrices types
    PTDF,
    VirtualPTDF,
    LODF,
    VirtualLODF,
    # Other utilities
    get_name,
    get_model_base_power,
    get_optimizer_stats,
    # Constants
    HOURS_IN_WEEK,
    # Key types (defined in IOM, not IS.Optimization)
    VariableKey,
    ConstraintKey,
    ParameterKey,
    ExpressionKey,
    AuxVarKey,
    OptimizationContainerKey

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

# Key Types
export VariableKey
export ConstraintKey
export ParameterKey
export ExpressionKey
export AuxVarKey

# Status Enums
export ModelBuildStatus
export RunStatus

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
