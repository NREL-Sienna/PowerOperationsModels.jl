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
import PowerSystems: get_component
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
# Note: AbstractPTDFModel and AbstractSecurityConstrainedPTDFModel are defined
# in this package (network_formulations.jl) as subtypes of PM.AbstractDCPModel.
import InfrastructureSystems.Optimization:
    AbstractDeviceFormulation,
    AbstractThermalFormulation,
    AbstractLoadFormulation,
    AbstractRenewableFormulation,
    AbstractServiceFormulation,
    AbstractReservesFormulation,
    AbstractPowerModel,
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
    convert_result_to_natural_units,
    # Network model compatibility checks (extended in core/network_formulations.jl)
    requires_all_branch_models,
    supports_branch_filtering,
    ignores_branch_filtering

# Import functions that POM extends with device-specific implementations
# These are the main extension points where POM provides concrete implementations
import InfrastructureOptimizationModels:
    construct_device!,
    construct_service!,
    add_variables!,
    add_constraints!,
    add_to_expression!,
    add_to_objective_function!,
    initial_condition_variable,
    initial_condition_default,
    get_initial_conditions_value,
    update_initial_conditions!,
    add_initial_condition!,
    get_initial_conditions_device_model,
    # Variable/expression multiplier functions (have stubs in IOM)
    get_variable_multiplier,
    get_expression_multiplier,
    get_multiplier_value,
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
    is_time_variant_term,
    add_proportional_cost!,
    add_proportional_cost_maybe_time_variant!,
    skip_proportional_cost,
    # System expression initialization (POM extends for concrete network models)
    initialize_system_expressions!,
    make_system_expressions!,
    # Network model instantiation (POM extends for concrete network formulations)
    instantiate_network_model!,
    # Parameter addition (POM provides concrete implementations)
    add_parameters!,
    # Cost/status functions (IOM has default stubs, POM adds device-specific methods)
    sos_status,
    get_operation_cost,
    get_must_run,
    # Build-pipeline extension points (IOM calls these in build_impl!, POM provides implementations)
    construct_services!,
    construct_network!,
    construct_hvdc_network!,
    add_power_flow_data!,
    calculate_aux_variable_value!,
    write_results!,
    is_from_power_flow,
    # Bulk-added via systematic search of POM→IOM references:
    # Functions POM extends with new methods
    _onvar_cost,
    add_cost_to_expression!,
    add_linear_ramp_constraints!,
    add_variable!,
    requires_initialization,
    get_min_max_limits,
    variable_cost,
    start_up_cost,
    _get_initial_condition_type,
    initialize_hvdc_system!

# Market bid cost: import IOM functions that POM extends with device-specific methods
import InfrastructureOptimizationModels:
    _has_market_bid_cost,
    _consider_parameter,
    validate_occ_component,
    _include_min_gen_power_in_constraint,
    _include_constant_min_gen_power_in_constraint,
    add_variable_cost_to_objective!,
    _vom_offer_direction,
    _add_pwl_constraint!,
    add_pwl_term!,
    get_output_offer_curves,
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
    get_input_offer_curves,
    add_constraint_dual!,
    assign_dual_variable!,
    _calculate_dual_variable_value!,
    add_dual_container!

using InfrastructureOptimizationModels

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
include("core/feedforward_interface.jl")

# Common models - expression infrastructure
# Expression container creation (add_expressions!) and helpers
include("common_models/add_expressions.jl")
# Device-specific add_to_expression! implementations
include("common_models/add_to_expression.jl")
# add_param_container.jl: moved into IOM
include("common_models/add_parameters.jl")
include("common_models/make_system_expressions.jl")
include("common_models/reserve_range_constraints.jl")

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

# Market bid cost: device-specific overloads for IOM's generic market_bid.jl
include("common_models/market_bid_overrides.jl")

# AC Transmission Models
include("ac_transmission_models/AC_branches.jl")
include("ac_transmission_models/branch_constructor.jl")

# Network Models
include("network_models/instantiate_network_model.jl")
include("network_models/network_slack_variables.jl")
include("network_models/copperplate_model.jl")
include("network_models/area_balance_model.jl")
include("network_models/powermodels_interface.jl")
include("network_models/pm_translator.jl")
include("network_models/network_constructor.jl")

# Services Models
include("services_models/service_slacks.jl")
include("services_models/reserves.jl")
include("services_models/reserve_group.jl")
# include("services_models/agc.jl")  # TODO: needs _get_ace_error
include("services_models/transmission_interface.jl")
include("services_models/services_constructor.jl")

# Two-Terminal HVDC Models
# NOTE: AC_branches.jl and branch_constructor.jl in twoterminal_hvdc_models/ are
# identical copies of the files in ac_transmission_models/ — do NOT include them.
include("twoterminal_hvdc_models/TwoTerminalDC_branches.jl")

# Multi-Terminal HVDC Models
include("mt_hvdc_models/HVDCsystems.jl")
include("mt_hvdc_models/hvdcsystems_constructor.jl")

# HVDC Network Models
include("network_models/hvdc_networks.jl")
include("network_models/hvdc_network_constructor.jl")

# Operation problem templates removed per design review.

# TODO: Add more model includes as they are ready
# include("static_injector_models/static_injection_security_constrained_models.jl")
# include("network_models/security_constrained_models.jl")

# Import private/internal helpers (use import to avoid undeclared warning)
import InfrastructureOptimizationModels: _get_ramp_constraint_devices
import InfrastructureOptimizationModels:
    get_param_eltype,
    CONTAINER_KEY_EMPTY_META

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
export ActivePowerVariableTimeSeriesLimitsConstraint
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
export StartupTimeLimitTemperatureConstraint

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
