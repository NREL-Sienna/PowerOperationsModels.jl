#=
The network artifacts one build derives from its source. One container type per
formulation family, so "does this build have a contingency matrix" is answered by
dispatch instead of an isnothing check, and a family cannot accidentally read a
matrix it never derived.

The reduction data is a deepcopy: POM extends it with `populate_branch_maps_by_type!`
and must never write into a core that the caller may have supplied or shared. That
function only ever accumulates — it never clears — so sharing it would leak one
template's branch maps into the next build off the same core. The copy may only ever be
EXTENDED: its bus and arc mapping must stay identical to the core's, because the MODF is
indexed with arcs resolved through this copy.

Consequence: `PNM.get_network_reduction_data(matrix)` and `get_reduction(network_data)`
are the same reduction but not the same object, and only the latter carries the branch
maps. Read the reduction off the container, never off the matrix.
=#

"""Ybus-only families: no factorization, no sensitivity matrices."""
struct YbusNetworkData <: IOM.AbstractNetworkData
    ybus::PNM.Ybus
    reduction::PNM.NetworkReductionData
end

"""DCP: a Ybus, plus a MODF derived from that same Ybus when the template is security constrained."""
struct DCPNetworkData{M} <: IOM.AbstractNetworkData
    ybus::PNM.Ybus
    contingency_matrix::M
    reduction::PNM.NetworkReductionData
end

"""PTDF families: a PTDF, plus an optional MODF, both wrapping one factorization core."""
struct PTDFNetworkData{P, M} <: IOM.AbstractNetworkData
    matrix::P
    contingency_matrix::M
    reduction::PNM.NetworkReductionData
end

# The no-contingency constructors omit the argument, storing this singleton in
# `contingency_matrix`. It is the type parameter, not the field's presence, that
# `has_contingency_matrix` dispatches on. A named sentinel rather than `nothing` because
# `nothing` already means "not instantiated yet" on IOM's `network_data` field.
struct NoContingencyMatrix end

DCPNetworkData(ybus::PNM.Ybus, reduction::PNM.NetworkReductionData) =
    DCPNetworkData(ybus, NoContingencyMatrix(), reduction)

PTDFNetworkData(matrix, reduction::PNM.NetworkReductionData) =
    PTDFNetworkData(matrix, NoContingencyMatrix(), reduction)

get_reduction(nd::YbusNetworkData) = nd.reduction
get_reduction(nd::DCPNetworkData) = nd.reduction
get_reduction(nd::PTDFNetworkData) = nd.reduction

# Ybus-only and DCP families have no sensitivity matrix, so the Ybus is the meaningful
# answer for get_network_matrix. Kept so the public IOM getter doesn't throw for these
# families; no caller reaches it today — the only get_network_matrix read sites
# (AC_branches.jl, transformer_models.jl) are NetworkModel{<:AbstractPTDFNetworkModel}.
get_matrix(nd::YbusNetworkData) = nd.ybus
get_matrix(nd::DCPNetworkData) = nd.ybus
get_matrix(nd::PTDFNetworkData) = nd.matrix

has_contingency_matrix(::IOM.AbstractNetworkData) = false
has_contingency_matrix(::DCPNetworkData{NoContingencyMatrix}) = false
has_contingency_matrix(::DCPNetworkData) = true
has_contingency_matrix(::PTDFNetworkData{P, NoContingencyMatrix}) where {P} = false
has_contingency_matrix(::PTDFNetworkData) = true

# Named distinctly from IOM's `get_contingency_matrix(m::NetworkModel)` (exported and
# brought into this module's scope via `using InfrastructureOptimizationModels`):
# reusing that name here would silently define a POM-local method table that shadows
# the NetworkModel method for every unqualified call in this package.
get_network_data_contingency_matrix(::DCPNetworkData{NoContingencyMatrix}) = error(
    "DCPNetworkData has no contingency matrix. Check `has_contingency_matrix` before \
    calling this getter.",
)
get_network_data_contingency_matrix(nd::DCPNetworkData) = nd.contingency_matrix
get_network_data_contingency_matrix(
    ::PTDFNetworkData{P, NoContingencyMatrix},
) where {P} = error(
    "PTDFNetworkData has no contingency matrix. Check `has_contingency_matrix` before \
    calling this getter.",
)
get_network_data_contingency_matrix(nd::PTDFNetworkData) = nd.contingency_matrix

# The consumer-facing getters keep their IOM names and forward into the derived
# container, so the PTDF and MODF read sites in the device models are unchanged.
IOM.get_network_matrix(m::NetworkModel) = get_matrix(get_network_data(m))
IOM.get_contingency_matrix(m::NetworkModel) =
    get_network_data_contingency_matrix(get_network_data(m))
IOM.get_network_reduction(m::NetworkModel) = get_reduction(get_network_data(m))
