#=
The type-organized views of one build's network reduction. In `core/` rather than
`network_models/` because `common_models/` and the device models name it in method
signatures, so it must exist before those files are included.

PNM's `NetworkReductionData` is a pure function of (system, reduction spec) and is shared by
reference across every matrix derived from it (Ybus, factorization core, MODF, PTDF). The
per-component-type views are NOT: which branches participate depends on this template's
per-`DeviceModel` filter functions, so one reduction backs as many valid view sets as there
are templates over it. They therefore live here, keyed to the build, wrapping the reduction
rather than mutating it.

`get_reduction_data(index)` is the very object the matrices hold — read the reduction off
either one, they are identical.
=#
struct ReductionIndex
    reduction::PNM.NetworkReductionData
    branch_maps::PNM.BranchMapsByType
    name_to_arc::PNM.NameToArcMap
    component_to_reduction_name::PNM.ComponentToReductionNameMap
    filters::Dict{DataType, Function}
end

function ReductionIndex(
    reduction::PNM.NetworkReductionData,
    filters::Dict{DataType, Function} = Dict{DataType, Function}(),
)
    branch_maps, name_to_arc, component_to_reduction_name =
        PNM.build_branch_maps_by_type(reduction, filters)
    return ReductionIndex(
        reduction,
        branch_maps,
        name_to_arc,
        component_to_reduction_name,
        filters,
    )
end

get_reduction_data(index::ReductionIndex) = index.reduction
get_branch_maps(index::ReductionIndex) = index.branch_maps
get_name_to_arc_maps(index::ReductionIndex) = index.name_to_arc
get_component_to_reduction_names(index::ReductionIndex) = index.component_to_reduction_name
get_reduction_filters(index::ReductionIndex) = index.filters

"""
The reduction entry of branch type `T` carrying `arc`, found in the reduction map named
`reduction_map` (as recorded by `get_name_to_arc_map_entries`).

Collapses the three-level `branch_maps[reduction_map][type][arc]` lookup into one call and
routes the type through `PNM.branch_map_key`, so a `ThreeWindingTransformerCircuit` lookup
resolves to the parent transformer bucket the maps are actually keyed by.
"""
function get_reduction_entry(
    index::ReductionIndex,
    ::Type{T},
    arc::Tuple{Int, Int},
    reduction_map::String,
) where {T <: IS.InfrastructureSystemsComponent}
    return get_reduction_entries(index, T, reduction_map)[arc]
end

"""
Every reduction entry of branch type `T` in the reduction map named `reduction_map`, keyed by
arc. Use when a caller iterates or holds the whole bucket; `get_reduction_entry` resolves a
single arc out of it.
"""
function get_reduction_entries(
    index::ReductionIndex,
    ::Type{T},
    reduction_map::String,
) where {T <: IS.InfrastructureSystemsComponent}
    return get_branch_maps(index)[reduction_map][PNM.branch_map_key(T)]
end

# The reduction is unchanged by the views over it, so `isempty` keeps meaning "is there a
# reduction", not "are there any views".
Base.isempty(index::ReductionIndex) = isempty(get_reduction_data(index))
