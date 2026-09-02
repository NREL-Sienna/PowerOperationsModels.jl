############################## Network Model Formulations ##################################
# AbstractPTDFNetworkModel must subtype AbstractDCPNetworkModel so that dispatch on
# AbstractDCPNetworkModel (e.g. _flow_variable_types) catches PTDF models.
# This can't live in IS because IS is domain-agnostic and doesn't know about power-system networks.
abstract type AbstractPTDFNetworkModel <: AbstractDCPNetworkModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://sienna-platform.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix.
"""
struct PTDFNetworkModel <: AbstractPTDFNetworkModel end

"""
Infinite capacity approximation of network flow to represent entire system with a single node.
"""
struct CopperPlateNetworkModel <: AbstractActivePowerModel end

"""
Approximation to represent inter-area flow with each area represented as a single node.
"""
struct AreaBalanceNetworkModel <: AbstractActivePowerModel end

"""
Linear active power approximation using the power transfer distribution factor [PTDF](https://sienna-platform.github.io/PowerNetworkMatrices.jl/stable/tutorials/tutorial_PTDF_matrix/) matrix. Balancing areas as well as synchrounous regions.
"""
struct AreaPTDFNetworkModel <: AbstractPTDFNetworkModel end

#################################################################################
# Network Model Capabilities
# These functions define capabilities for different network formulations
#################################################################################

# Defaults are in IOM; POM only provides overrides for specific formulations
supports_branch_filtering(::Type{<:AbstractPTDFNetworkModel}) = true

ignores_branch_filtering(::Type{CopperPlateNetworkModel}) = true
ignores_branch_filtering(::Type{AreaBalanceNetworkModel}) = true

requires_all_branch_models(::Type{<:AbstractPTDFNetworkModel}) = false
requires_all_branch_models(::Type{CopperPlateNetworkModel}) = false
requires_all_branch_models(::Type{AreaBalanceNetworkModel}) = false

branches_modeled(::Type{CopperPlateNetworkModel}) = false
branches_modeled(::Type{AreaBalanceNetworkModel}) = false

# Aggregated formulations resolve injections by area name or subnetwork reference bus, never
# through the reduction's bus map, so a reduction handed to one is computed and then ignored.
# `_validate_network_source` rejects a non-default source rather than discarding it silently.
honors_network_reduction(::Type{<:AbstractNetworkModel}) = true
honors_network_reduction(::Type{CopperPlateNetworkModel}) = false
honors_network_reduction(::Type{AreaBalanceNetworkModel}) = false

# `network_has_reactive_power` is derived from the `reactive_power_support` trait below.

# POM DCP — concrete construct_network! in network_constructor.jl.
# IS doesn't know about power-system network formulations; POM owns all dispatch.
struct DCPNetworkModel <: AbstractDCPNetworkModel end

# POM ACP — concrete construct_network! in network_constructor.jl.
struct ACPNetworkModel <: AbstractACPModel end

# POM NFA (network-flow / transportation approximation). No voltage angle
# variables, no reference bus, no Ohm's law — only rating-bounded branch flows and
# nodal active-power balance. Concrete-type construct_network! beats the bridge
# fallback, same as DCP/ACP.
struct NFANetworkModel <: AbstractNFANetworkModel end

branches_modeled(::Type{NFANetworkModel}) = true
requires_all_branch_models(::Type{NFANetworkModel}) = true

# POM DCPLL (DC power flow with quadratic line losses). Same angle/balance structure
# as DCP, but branch flow is modeled with two directional active variables coupled by a
# quadratic loss constraint, making the problem a convex QCP (Ipopt).
struct DCPLLNetworkModel <: AbstractDCPLLNetworkModel end

branches_modeled(::Type{DCPLLNetworkModel}) = true
requires_all_branch_models(::Type{DCPLLNetworkModel}) = false

abstract type AbstractACRNetworkModel <: AbstractReactivePowerNetworkModel end

"""
Full AC power flow in rectangular voltage coordinates (vr, vi). Physics-equivalent to
ACPNetworkModel; on the same system both solve the identical nonlinear program and therefore
reach the same optimal objective value.
"""
struct ACRNetworkModel <: AbstractACRNetworkModel end

abstract type AbstractLPACCNetworkModel <: AbstractReactivePowerNetworkModel end

"""
Linear-programming AC, cold-start (LPAC) convex approximation of the full AC power flow.
Models voltage-magnitude deviation `phi = |V| - 1` (per bus), the bus-pair cosine variable
`cs` (per branch) with a convex cosine relaxation, and the LPAC-linearized branch power
flows. Tractable (convex QCP) and approximate — faster than full AC while modeling reactive
power.
"""
struct LPACCNetworkModel <: AbstractLPACCNetworkModel end

abstract type AbstractIVRNetworkModel <: AbstractReactivePowerNetworkModel end

"""
Full AC power flow in current-voltage rectangular (IVR) coordinates. Uses branch current
variables (terminal and series) with a linear Ohm's law and bilinear branch power that is
wired into `ActivePowerBalance`/`ReactivePowerBalance`. Exact AC (same optimum as
`ACPNetworkModel` and `ACRNetworkModel`); advantage is that the Ohm's law is linear in the
decision variables, which can improve solver performance on some instances.

Devices inject P/Q unchanged (same as ACP/ACR); only the branch representation differs.
`construct_network!` is shared with `ACRNetworkModel` via Union dispatch in `network_constructor.jl`.
"""
struct IVRNetworkModel <: AbstractIVRNetworkModel end

# Nodal formulations that build per-branch flow variables wired into the per-bus
# balance expressions. Under an active network reduction these share one set of branch
# variables/constraints per reduced arc (see network_models/network_reductions.jl).
const NativeNodalNetworkModel = Union{
    DCPNetworkModel,
    DCPLLNetworkModel,
    NFANetworkModel,
    ACPNetworkModel,
    ACRNetworkModel,
    LPACCNetworkModel,
    IVRNetworkModel,
}

# The subset of native nodal formulations that carry a reactive-power balance.
const NativeACNetworkModel = Union{
    ACPNetworkModel,
    ACRNetworkModel,
    LPACCNetworkModel,
    IVRNetworkModel,
}

#################################################################################
# Network-formulation capability traits (Holy traits)
#
# Capabilities overlap without nesting (e.g. reactive-power and angle-variable sets
# share {ACP,LPACC} but neither contains the other) and `AbstractACPModel` is
# IS-owned, so single inheritance can't express them — each is its own trait axis,
# dispatched on in place of hand-enumerated Unions.
#################################################################################

# --- How the active nodal power balance is indexed ---
abstract type NodalActiveBalanceStyle end
struct NamedBusActiveBalance <: NodalActiveBalanceStyle end
struct AggregatedActiveBalance <: NodalActiveBalanceStyle end

nodal_active_balance_style(::Type{<:AbstractNetworkModel}) = AggregatedActiveBalance()
nodal_active_balance_style(::Type{DCPNetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{NFANetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{DCPLLNetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{ACPNetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{ACRNetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{LPACCNetworkModel}) = NamedBusActiveBalance()
nodal_active_balance_style(::Type{IVRNetworkModel}) = NamedBusActiveBalance()

# --- Whether the network carries a reactive power balance ---
abstract type ReactivePowerSupport end
struct HasReactivePower <: ReactivePowerSupport end
struct NoReactivePower <: ReactivePowerSupport end

"""
    reactive_power_support(::Type{<:AbstractNetworkModel}) -> ReactivePowerSupport

Whether a network formulation allocates a `ReactivePowerBalance` expression, and therefore
whether devices may inject reactive power under it.

Single source of truth for the axis: `make_system_expressions!` allocates from it, the
`network_has_reactive_power` predicate derives from it, and the
`_maybe_add_reactive_power_*` constructor helpers dispatch on it. Extend the table here —
never with a `Union` alias enumerating formulations, and never by overriding
`network_has_reactive_power` separately.
"""
reactive_power_support(::Type{<:AbstractNetworkModel}) = HasReactivePower()
reactive_power_support(::Type{<:AbstractActivePowerModel}) = NoReactivePower()

_has_reactive_balance(::HasReactivePower) = true
_has_reactive_balance(::NoReactivePower) = false

"""
    network_has_reactive_power(::Type{<:AbstractNetworkModel}) -> Bool

Whether the network carries a reactive-power balance. Predicate form of
[`reactive_power_support`](@ref) for the `if`-based validation call sites in
`operation/template_validation.jl`; derived from it so the two cannot disagree. Extend
`reactive_power_support`, not this.
"""
network_has_reactive_power(::Type{N}) where {N <: AbstractNetworkModel} =
    _has_reactive_balance(reactive_power_support(N))

# --- Whether the network carries a bus VoltageAngle variable ---
abstract type VoltageForm end
struct AngleBasedVoltage <: VoltageForm end
struct NonAngleVoltage <: VoltageForm end

voltage_form(::Type{<:AbstractNetworkModel}) = NonAngleVoltage()
voltage_form(::Type{DCPNetworkModel}) = AngleBasedVoltage()
voltage_form(::Type{DCPLLNetworkModel}) = AngleBasedVoltage()
voltage_form(::Type{ACPNetworkModel}) = AngleBasedVoltage()
voltage_form(::Type{LPACCNetworkModel}) = AngleBasedVoltage()

# --- How the AC voltage state is represented ---
# `Union{ACRNetworkModel, IVRNetworkModel}` was spelled out at 17 call sites across 8 files
# before this axis existed. The two share rectangular (vr, vi) coordinates but sit in
# sibling branches of the network tree, so no supertype names the pair.
abstract type VoltageCoordinates end

"Bus voltage carried as magnitude and angle (`ACPNetworkModel`, `LPACCNetworkModel`)."
struct PolarVoltage <: VoltageCoordinates end

"Bus voltage carried as real/imaginary components (`ACRNetworkModel`, `IVRNetworkModel`)."
struct RectangularVoltage <: VoltageCoordinates end

"No AC voltage state — the active-power-only and aggregated formulations."
struct NoVoltageCoordinates <: VoltageCoordinates end

"""
    voltage_coordinates(::Type{<:AbstractNetworkModel}) -> VoltageCoordinates

The coordinate system a network formulation carries its AC bus voltage in. Dispatch on this
instead of enumerating network formulations in a `Union`.

Distinct from [`voltage_form`](@ref), which asks only whether a bus `VoltageAngle` variable
exists: `DCPNetworkModel` is `AngleBasedVoltage()` but has no AC voltage state at all.
"""
voltage_coordinates(::Type{<:AbstractNetworkModel}) = NoVoltageCoordinates()
voltage_coordinates(::Type{ACPNetworkModel}) = PolarVoltage()
voltage_coordinates(::Type{LPACCNetworkModel}) = PolarVoltage()
voltage_coordinates(::Type{ACRNetworkModel}) = RectangularVoltage()
voltage_coordinates(::Type{IVRNetworkModel}) = RectangularVoltage()
