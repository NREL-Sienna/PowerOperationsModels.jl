############################## Network Model Formulations ##################################
# Network formulations using abstract types from InfrastructureSystems.Optimization
# Concrete PowerModels types (ACPPowerModel, DCPPowerModel, etc.) are provided
# by the PowerModels submodule.

"""
Abstract type for PTDF-based power flow formulations.
"""
abstract type AbstractPTDFModel <: AbstractPowerModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix and line outage distribution factors [LODF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_LODF_matrix/) for branches outages.
"""
abstract type AbstractSecurityConstrainedPTDFModel <: AbstractPTDFModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix.
"""
struct PTDFPowerModel <: AbstractPTDFModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix and line outage distribution factors [LODF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_LODF_matrix/) for branches outages. If exists, the rating b is considered as the branch power limit for post-contingency flows, otherwise the standard rating is considered.
"""
struct SecurityConstrainedPTDFPowerModel <: AbstractSecurityConstrainedPTDFModel end

"""
Infinite capacity approximation of network flow to represent entire system with a single node.
"""
struct CopperPlatePowerModel <: AbstractPowerModel end

"""
Approximation to represent inter-area flow with each area represented as a single node.
"""
struct AreaBalancePowerModel <: AbstractPowerModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix. Balancing areas as well as synchrounous regions.
"""
struct AreaPTDFPowerModel <: AbstractPTDFModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix and [LODF](https://nrel-sienna.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_LODF_matrix/) for branches outages. Balancing areas as well as synchrounous regions.
"""
struct SecurityConstrainedAreaPTDFPowerModel <: AbstractSecurityConstrainedPTDFModel end

#################################################################################
# Network Model Capabilities
# These functions define capabilities for different network formulations
#################################################################################

supports_branch_filtering(::Type{<:AbstractPowerModel}) = false
supports_branch_filtering(::Type{<:AbstractPTDFModel}) = true
supports_branch_filtering(::Type{<:AbstractSecurityConstrainedPTDFModel}) = true

ignores_branch_filtering(::Type{<:AbstractPowerModel}) = false
ignores_branch_filtering(::Type{CopperPlatePowerModel}) = true
ignores_branch_filtering(::Type{AreaBalancePowerModel}) = true

requires_all_branch_models(::Type{<:AbstractPowerModel}) = true
requires_all_branch_models(::Type{<:AbstractPTDFModel}) = false
requires_all_branch_models(::Type{CopperPlatePowerModel}) = false
requires_all_branch_models(::Type{AreaBalancePowerModel}) = false
