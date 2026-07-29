#################################################################################
# Branch flow-slack specifications
#
# Single source of truth for which slack machinery a (branch formulation, network
# formulation) pair builds. The `slack_spec` method table below DESCRIBES what the
# `construct_device!` methods create; the `supports_flow_slacks` validation gate and
# the objective pricing (`_price_slack_spec!` in AC_branches.jl) both derive from it,
# so "the gate says yes" and "the constructors build something" cannot drift apart.
#################################################################################

# Container metas of the StaticBranchBounds flow-definition slack pairs (one pair per
# directional Ohm's-law equality) and the IVR terminal current-definition slack pairs.
const FLOW_DEFINITION_SLACK_METAS = ("p_ft", "p_tf", "q_ft", "q_tf")
const CURRENT_DEFINITION_SLACK_METAS = ("cr_fr", "ci_fr", "cr_to", "ci_to")

"""
Trait axis describing the flow-slack machinery a branch formulation builds under a given
network formulation. Concrete specs carry the container metas the machinery uses, so
consumers (validation gate, objective pricing, tests) read the same declaration the
constructors build from. Declared per (formulation, network) pair via [`slack_spec`](@ref).
"""
abstract type BranchSlackSpec end

"The pair builds no flow-slack machinery; `use_slacks = true` is rejected at validation."
struct NoBranchSlacks <: BranchSlackSpec end

"""
One meta-less upper/lower slack pair per branch relaxing the network's rating rows
(`FlowRateConstraint` lb/ub) or, on PTDF-family networks with `StaticBranchBounds`, the
`PTDFBranchFlow == FlowActivePowerVariable` flow-definition equality.
"""
struct RowPairSlacks <: BranchSlackSpec end

"""
One metaed upper/lower slack pair per flow/current definition equality row, one pair per
meta (`StaticBranchBounds` on the AC natives: the Ohm's-law rows; IVR adds the terminal
current-definition rows).
"""
struct EqualityPairSlacks{N} <: BranchSlackSpec
    metas::NTuple{N, String}
end

get_pair_metas(spec::EqualityPairSlacks) = spec.metas

"""
One one-sided upper slack per meta relaxing a quadratic limit row (`StaticBranch` on the
AC natives: the meta-less apparent-power limit; IVR adds the `"c_from"`/`"c_to"` terminal
current-magnitude limits).
"""
struct QuadraticUpperSlacks{N} <: BranchSlackSpec
    metas::NTuple{N, String}
end

get_upper_metas(spec::QuadraticUpperSlacks) = spec.metas

# The (variable type, meta) containers a slacked build creates for the spec — the
# contract the trait-vs-reality test iterates.
slack_variable_entries(::NoBranchSlacks) = ()

function slack_variable_entries(::RowPairSlacks)
    return (
        (FlowActivePowerSlackUpperBound, IOM.CONTAINER_KEY_EMPTY_META),
        (FlowActivePowerSlackLowerBound, IOM.CONTAINER_KEY_EMPTY_META),
    )
end

function slack_variable_entries(spec::EqualityPairSlacks)
    up = map(meta -> (FlowActivePowerSlackUpperBound, meta), get_pair_metas(spec))
    lo = map(meta -> (FlowActivePowerSlackLowerBound, meta), get_pair_metas(spec))
    return (up..., lo...)
end

function slack_variable_entries(spec::QuadraticUpperSlacks)
    return map(meta -> (FlowActivePowerSlackUpperBound, meta), get_upper_metas(spec))
end

"""
    slack_spec(::Type{<:AbstractDeviceFormulation}, ::Type{<:AbstractNetworkModel}) -> BranchSlackSpec

The flow-slack machinery a branch formulation builds under a network formulation. Defaults
to [`NoBranchSlacks`](@ref): a pair with no declared machinery rejects `use_slacks = true`
at template validation. One method per (formulation, network family) pair that genuinely
builds slacks — extend the table the same way `network_support` is extended, never with a
`Union` alias enumerating formulations.
"""
slack_spec(::Type{<:AbstractDeviceFormulation}, ::Type{<:AbstractNetworkModel}) =
    NoBranchSlacks()

# StaticBranch relaxes the rating rows on the linear-active networks and the quadratic
# apparent-power (plus IVR terminal-current) limits on the AC natives.
slack_spec(::Type{StaticBranch}, ::Type{DCPNetworkModel}) = RowPairSlacks()
slack_spec(::Type{StaticBranch}, ::Type{NFANetworkModel}) = RowPairSlacks()
slack_spec(::Type{StaticBranch}, ::Type{DCPLLNetworkModel}) = RowPairSlacks()
slack_spec(::Type{StaticBranch}, ::Type{<:AbstractPTDFNetworkModel}) = RowPairSlacks()
slack_spec(
    ::Type{StaticBranch},
    ::Type{<:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel}},
) = QuadraticUpperSlacks((IOM.CONTAINER_KEY_EMPTY_META,))
slack_spec(::Type{StaticBranch}, ::Type{IVRNetworkModel}) =
    QuadraticUpperSlacks((IOM.CONTAINER_KEY_EMPTY_META, "c_from", "c_to"))

# StaticBranchBounds keeps its rating as hard variable bounds and relaxes the
# flow-definition equalities instead (per-direction pairs on the AC natives, plus the
# terminal current definitions on IVR, the PTDF tie / rating rows on the linear networks).
# NFA has neither an equality nor a rating row, so the default `NoBranchSlacks` applies.
slack_spec(::Type{StaticBranchBounds}, ::Type{DCPNetworkModel}) = RowPairSlacks()
slack_spec(::Type{StaticBranchBounds}, ::Type{DCPLLNetworkModel}) = RowPairSlacks()
slack_spec(::Type{StaticBranchBounds}, ::Type{<:AbstractPTDFNetworkModel}) =
    RowPairSlacks()
slack_spec(
    ::Type{StaticBranchBounds},
    ::Type{<:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel}},
) = EqualityPairSlacks(FLOW_DEFINITION_SLACK_METAS)
slack_spec(::Type{StaticBranchBounds}, ::Type{IVRNetworkModel}) =
    EqualityPairSlacks((FLOW_DEFINITION_SLACK_METAS..., CURRENT_DEFINITION_SLACK_METAS...))

# psy6: disabled pending transformer refactor
# TapControl shares the DCP StaticBranch rating-row machinery (tap-aware Ohm's law, same
# slacked FlowRateConstraint rows and pricing).
# slack_spec(::Type{TapControl}, ::Type{DCPNetworkModel}) = RowPairSlacks()

# Security-constrained branches build the pre-contingency meta-less pair on their
# supported networks; the post-contingency slacks are separate machinery gated by the
# same `use_slacks` inside the MODF constructors.
slack_spec(
    ::Type{<:AbstractSecurityConstrainedStaticBranch},
    ::Type{<:AbstractPTDFNetworkModel},
) = RowPairSlacks()
slack_spec(::Type{<:AbstractSecurityConstrainedStaticBranch}, ::Type{DCPNetworkModel}) =
    RowPairSlacks()

_slack_machinery_exists(::NoBranchSlacks) = false
_slack_machinery_exists(::BranchSlackSpec) = true

"""
    supports_flow_slacks(::Type{<:AbstractDeviceFormulation}, ::Type{<:AbstractNetworkModel}) -> Bool

Whether a branch formulation's flow slacks have something to attach to under this network
model: a flow-defining equality (Ohm's law / DC angle relation), a rating constraint row,
or a quadratic limit the slack can relax. Derived from [`slack_spec`](@ref) — a pair
supports slacks exactly when its spec declares machinery, so the gate cannot drift from
what the constructors build. Extend by declaring a `slack_spec` method, not by overriding
this function.
"""
function supports_flow_slacks(
    ::Type{F},
    ::Type{N},
) where {F <: AbstractDeviceFormulation, N <: AbstractNetworkModel}
    return _slack_machinery_exists(slack_spec(F, N))
end
