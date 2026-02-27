
using PowerOperationsModels
using InfrastructureOptimizationModels
using PowerSystems
using PowerSystemCaseBuilder
using InfrastructureSystems
import InfrastructureSystems: TableFormat
using PowerNetworkMatrices
import PowerSystemCaseBuilder: PSITestSystems
using PowerFlows
using DataFramesMeta

# Test Packages
using Test
using Logging

# Dependencies for testing
using DataFrames
using DataFramesMeta
using Dates
using JuMP
import JuMP.Containers: DenseAxisArray, SparseAxisArray
import JuMP.MOI as MOI
import MathOptInterface.Utilities as MOIU
using TimeSeries
using CSV
import JSON3
using DataStructures
import UUIDs
using Random
import Serialization
import LinearAlgebra

const PSY = PowerSystems
const POM = PowerOperationsModels
const IOM = InfrastructureOptimizationModels
const PFS = PowerFlows
const PSB = PowerSystemCaseBuilder
const PNM = PowerNetworkMatrices
const ISOPT = InfrastructureSystems.Optimization
const PM = PowerOperationsModels.PowerModels

const IS = InfrastructureSystems
const BASE_DIR = string(dirname(dirname(pathof(InfrastructureOptimizationModels))))
const DATA_DIR = joinpath(BASE_DIR, "test/test_data")

include("test_utils/common_operation_model.jl")
include("test_utils/model_checks.jl")
include("test_utils/mock_operation_models.jl")
include("test_utils/solver_definitions.jl")
include("test_utils/operations_problem_templates.jl")
include("test_utils/run_simulation.jl")
include("test_utils/add_market_bid_cost.jl")
include("test_utils/mbc_system_utils.jl")
include("test_utils/iec_test_systems.jl")
include("test_utils/hydro_testing_utils.jl")

ENV["RUNNING_SIENNA_TESTS"] = "true"
ENV["SIENNA_RANDOM_SEED"] = 1234  # Set a fixed seed for reproducibility in tests
