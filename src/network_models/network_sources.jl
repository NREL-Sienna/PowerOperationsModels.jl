#=
The declaration of which network a NetworkModel is built on. `_build_ybus` is the
single place a Ybus is constructed during network model instantiation: one Ybus per
build means one reduction, so every matrix derived from it agrees by construction.
=#

"""
Build the network from the system, applying `reductions`, honoring the build's
reduction exceptions, and sparsifying the derived sensitivity matrices at `tolerance`.
The two are independent knobs on the same construction step.

`tolerance` is the per-row sparsification cutoff handed to `PNM.VirtualFactorCore`: a
`Float64` is an absolute cutoff, a `PNM.AutoTolerance` a relative, size-adaptive one.
It reaches every matrix wrapping that core — PTDF and MODF alike.

A zero-impedance branch reduction is always applied first. Include a
`ZeroImpedanceBranchReduction` to override its parameters; it replaces that step rather than
adding one, so its position in the vector is irrelevant. More than one errors.
"""
struct SystemNetworkSource <: IOM.AbstractNetworkSource
    reductions::Vector{PNM.NetworkReduction}
    tolerance::Union{Float64, PNM.AutoTolerance}
end

SystemNetworkSource(; tolerance = DEFAULT_PTDF_TOLERANCE) =
    SystemNetworkSource(PNM.NetworkReduction[], tolerance)

SystemNetworkSource(
    reductions::Vector{PNM.NetworkReduction};
    tolerance = DEFAULT_PTDF_TOLERANCE,
) = SystemNetworkSource(reductions, tolerance)

SystemNetworkSource(
    reduction::PNM.NetworkReduction,
    rest::PNM.NetworkReduction...;
    tolerance = DEFAULT_PTDF_TOLERANCE,
) = SystemNetworkSource(
    collect(PNM.NetworkReduction, (reduction, rest...)),
    tolerance,
)

"""
Reuse a `VirtualPTDF` the caller already built, including its populated row cache.
Its own reduction becomes the build's reduction; the reduction exceptions derived
from the template are not applied, because the matrix already exists.

Only a `VirtualPTDF` is accepted: it carries the factorization core, so a MODF
sharing its reduction can be derived from it. A dense `PNM.PTDF` carries no core and
is deliberately not a valid source.
"""
struct PrebuiltMatrixSource{M <: PNM.VirtualPTDF} <: IOM.AbstractNetworkSource
    matrix::M
end

"""
Reuse a factorization core the caller already built — the cheapest reuse, since the
PTDF and MODF wrappers are derived from it without re-factorizing the ABA matrix.
"""
struct PrebuiltCoreSource{C <: PNM.VirtualFactorCore} <: IOM.AbstractNetworkSource
    core::C
end

get_matrix(source::PrebuiltMatrixSource) = source.matrix
get_core(source::PrebuiltCoreSource) = source.core

_source_reductions(source::SystemNetworkSource) = source.reductions
_source_reductions(::IOM.DefaultNetworkSource) = PNM.NetworkReduction[]
_source_reductions(source::PrebuiltMatrixSource) =
    PNM.get_applied_reductions(PNM.get_network_reduction_data(get_matrix(source)))
_source_reductions(source::PrebuiltCoreSource) =
    PNM.get_applied_reductions(PNM.get_network_reduction_data(get_core(source)))

"The user-supplied irreducible bus set an already-applied reduction was built with."
_source_irreducible_buses(reduction::PNM.NetworkReductionData) =
    collect(Int, PNM.get_user_irreducible_buses(PNM.get_reductions(reduction)))

# The sparsification cutoff for a core this build factorizes itself. A prebuilt source
# carries a core whose cutoff the caller already fixed, so it falls back to the default:
# the value is consulted only on the paths that factorize a core of their own.
_source_tolerance(source::SystemNetworkSource) = source.tolerance
_source_tolerance(::IOM.AbstractNetworkSource) = DEFAULT_PTDF_TOLERANCE

_is_radial_reduction(::PNM.NetworkReduction) = false
_is_radial_reduction(::PNM.RadialReduction) = true

function _build_ybus(
    source::SystemNetworkSource,
    sys::PSY.System,
    exceptions::Vector{Int},
)
    return PNM.Ybus(
        sys;
        network_reductions = source.reductions,
        irreducible_buses = exceptions,
    )
end

function _build_ybus(
    ::IOM.DefaultNetworkSource,
    sys::PSY.System,
    exceptions::Vector{Int},
)
    return PNM.Ybus(sys; irreducible_buses = exceptions)
end
