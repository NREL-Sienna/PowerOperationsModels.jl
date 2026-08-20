#=
Branch-reduction tracking and network-reduction axis helpers, dispatching on the
concrete PowerNetworkMatrices types. Moved here from IOM so that IOM stays
independent of power-network modeling; IOM's `NetworkModel` carries the tracker
behind `IOM.AbstractBranchReductionTracker` and the reduction data behind
`IS.InfrastructureMatrices.AbstractInfrastructureNetworkReductionData`.
=#

mutable struct BranchReductionOptimizationTracker <: IOM.AbstractBranchReductionTracker
    variable_dict::Dict{
        Type{<:VariableType},
        Dict{Tuple{Int, Int}, Vector{JuMP.VariableRef}},
    }
    parameter_dict::Dict{
        Type{<:ParameterType},
        Dict{Tuple{Int, Int}, Vector{Union{Float64, JuMP.VariableRef}}},
    }
    constraint_dict::Dict{Type{<:ConstraintType}, Set{Tuple{Int, Int}}}
    # Arcs already wired into a balance expression, keyed by (expression type, variable
    # type): reduced-arc variables are shared across every member entry (and across
    # branch types), so each arc's variable must enter a given balance exactly once.
    expression_dict::Dict{Tuple{DataType, DataType}, Set{Tuple{Int, Int}}}
    constraint_map_by_type::Dict{
        Type{<:ConstraintType},
        Dict{
            Type{<:IS.InfrastructureSystemsComponent},
            IOM.SortedDict{String, Tuple{Tuple{Int, Int}, String}},
        },
    }
    number_of_steps::Int
    # Build-scoped memo of the retained (bus name, bus number) pairs, filled lazily by
    # `_bus_name_number_pairs` so the per-bus name resolution (an O(n_buses) component
    # scan) runs once per build rather than once per network variable/constraint type.
    # Empty means "not yet computed" — a network always has ≥1 bus. Not part of
    # `isempty`/`empty!`'s reduction semantics, but cleared on rebuild.
    bus_name_number_pairs::Vector{Tuple{String, Int}}
end

get_variable_dict(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.variable_dict
get_parameter_dict(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.parameter_dict
get_constraint_dict(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.constraint_dict
get_expression_dict(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.expression_dict
get_constraint_map_by_type(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.constraint_map_by_type

get_number_of_steps(reduction_tracker::BranchReductionOptimizationTracker) =
    reduction_tracker.number_of_steps
set_number_of_steps!(reduction_tracker, number_of_steps) =
    reduction_tracker.number_of_steps = number_of_steps

Base.isempty(
    reduction_tracker::BranchReductionOptimizationTracker,
) =
    isempty(reduction_tracker.variable_dict) &&
    isempty(reduction_tracker.parameter_dict) &&
    isempty(reduction_tracker.constraint_dict) &&
    isempty(reduction_tracker.constraint_map_by_type) &&
    isempty(reduction_tracker.expression_dict)

Base.empty!(
    reduction_tracker::BranchReductionOptimizationTracker,
) = begin
    empty!(reduction_tracker.variable_dict)
    empty!(reduction_tracker.parameter_dict)
    empty!(reduction_tracker.constraint_dict)
    empty!(reduction_tracker.expression_dict)
    empty!(reduction_tracker.constraint_map_by_type)
    empty!(reduction_tracker.bus_name_number_pairs)
end

function BranchReductionOptimizationTracker()
    return BranchReductionOptimizationTracker(
        Dict(), Dict(), Dict(), Dict(), Dict(), 0, Tuple{String, Int}[],
    )
end

function _make_empty_variable_tracker_dict(
    arc_tuple::Tuple{Int, Int},
    num_steps::Int,
)
    return Dict{Tuple{Int, Int}, Vector{JuMP.VariableRef}}(
        arc_tuple => Vector{JuMP.VariableRef}(undef, num_steps),
    )
end

function _make_empty_parameter_tracker_dict(
    arc_tuple::Tuple{Int, Int},
    num_steps::Int,
)
    return Dict{Tuple{Int, Int}, Vector{Union{Float64, JuMP.VariableRef}}}(
        arc_tuple => Vector{Union{Float64, JuMP.VariableRef}}(undef, num_steps),
    )
end

"""Look up (or register) the tracker entry for `arc_tuple` and `VariableType` T.
Returns `(has_entry, tracker_vector)` where `has_entry` is `true` when the arc
was already registered by a previous call (i.e. a parallel/reduced branch of a
different device type already created the variable)."""
function search_for_reduced_branch_variable!(
    tracker::BranchReductionOptimizationTracker,
    arc_tuple::Tuple{Int, Int},
    ::Type{T},
) where {T <: VariableType}
    variable_dict = tracker.variable_dict
    time_steps = get_number_of_steps(tracker)
    if !haskey(variable_dict, T)
        variable_dict[T] = _make_empty_variable_tracker_dict(arc_tuple, time_steps)
        return (false, variable_dict[T][arc_tuple])
    else
        if haskey(variable_dict[T], arc_tuple)
            return (true, variable_dict[T][arc_tuple])
        else
            variable_dict[T][arc_tuple] = Vector{JuMP.VariableRef}(undef, time_steps)
            return (false, variable_dict[T][arc_tuple])
        end
    end
end

"""Look up (or register) the tracker entry for `arc_tuple` and `ParameterType` T.
Stores `Float64` values when `built_for_recurrent_solves` is `false`, or
`JuMP.VariableRef` objects (JuMP parameters) when `true`, so that shared arcs
across different branch types reuse the same underlying parameter object.
Returns `(has_entry, tracker_vector)`."""
function search_for_reduced_branch_parameter!(
    tracker::BranchReductionOptimizationTracker,
    arc_tuple::Tuple{Int, Int},
    ::Type{T},
) where {T <: ParameterType}
    parameter_dict = tracker.parameter_dict
    time_steps = get_number_of_steps(tracker)
    if !haskey(parameter_dict, T)
        parameter_dict[T] = _make_empty_parameter_tracker_dict(arc_tuple, time_steps)
        return (false, parameter_dict[T][arc_tuple])
    else
        if haskey(parameter_dict[T], arc_tuple)
            return (true, parameter_dict[T][arc_tuple])
        else
            parameter_dict[T][arc_tuple] =
                Vector{Union{Float64, JuMP.VariableRef}}(undef, time_steps)
            return (false, parameter_dict[T][arc_tuple])
        end
    end
end

"""Register the wiring of `arc_tuple`'s shared variable of type `U` into the balance
expression of type `T`. Returns `true` when the arc was already wired by a previous
entry (same or different branch type) — the caller must skip it to avoid double-counting
the shared variable in the balance."""
function search_for_reduced_branch_expression!(
    tracker::BranchReductionOptimizationTracker,
    arc_tuple::Tuple{Int, Int},
    ::Type{T},
    ::Type{U},
) where {T <: ExpressionType, U <: VariableType}
    wired_arcs = get!(Set{Tuple{Int, Int}}, tracker.expression_dict, (T, U))
    already_wired = arc_tuple in wired_arcs
    if !already_wired
        push!(wired_arcs, arc_tuple)
    end
    return already_wired
end

# Backwards-compatible dispatcher: routes to the correctly typed dict based on T.
function search_for_reduced_branch_argument!(
    tracker::BranchReductionOptimizationTracker,
    arc_tuple::Tuple{Int, Int},
    ::Type{T},
) where {T <: VariableType}
    return search_for_reduced_branch_variable!(tracker, arc_tuple, T)
end

function search_for_reduced_branch_argument!(
    tracker::BranchReductionOptimizationTracker,
    arc_tuple::Tuple{Int, Int},
    ::Type{T},
) where {T <: ParameterType}
    return search_for_reduced_branch_parameter!(tracker, arc_tuple, T)
end

function get_branch_argument_parameter_axes(
    net_reduction_data::ReductionIndex,
    ::IS.FlattenIteratorWrapper{T},
    ::Type{V},
    ts_name::String;
    interval::Dates.Millisecond = IOM.UNSET_INTERVAL,
    resolution::Dates.Millisecond = IOM.UNSET_RESOLUTION,
) where {T <: IS.InfrastructureSystemsComponent, V <: IS.TimeSeriesData}
    return get_branch_argument_parameter_axes(
        net_reduction_data,
        T,
        V,
        ts_name;
        interval = interval,
        resolution = resolution,
    )
end

"""
Find the first device within a reduction entry that has the given time series.
Delegates to PNM, which handles BranchesParallel, BranchesSeries,
ThreeWindingTransformerCircuit, and plain ACTransmission entries.
"""
function get_branch_with_time_series(
    branch::IS.InfrastructureSystemsComponent,
    ::Type{V},
    ts_name::String,
) where {V <: IS.TimeSeriesData}
    return PNM.get_device_with_time_series(branch, V, ts_name)
end

function get_branch_argument_parameter_axes(
    net_reduction_data::ReductionIndex,
    ::Type{T},
    ::Type{V},
    ts_name::String;
    interval::Dates.Millisecond = IOM.UNSET_INTERVAL,
    resolution::Dates.Millisecond = IOM.UNSET_RESOLUTION,
) where {T <: IS.InfrastructureSystemsComponent, V <: IS.TimeSeriesData}
    is_interval = IOM._to_is_interval(interval)
    is_resolution = IOM._to_is_resolution(resolution)
    name_axis = Vector{String}()
    ts_uuid_axis = Vector{String}()
    arc_map = get_name_to_arc_map_entries(net_reduction_data, T)
    for (name, (arc, reduction)) in arc_map
        reduction_entry = get_reduction_entry(net_reduction_data, T, arc, reduction)
        device_with_time_series =
            get_branch_with_time_series(reduction_entry, V, ts_name)
        if !isnothing(device_with_time_series)
            push!(name_axis, name)
            push!(
                ts_uuid_axis,
                string(
                    IS.get_time_series_uuid(
                        V,
                        device_with_time_series,
                        ts_name;
                        resolution = is_resolution,
                        interval = is_interval,
                    ),
                ),
            )
        end
    end
    return name_axis, ts_uuid_axis
end

function get_branch_argument_variable_axis(
    net_reduction_data::ReductionIndex,
    ::IS.FlattenIteratorWrapper{T},
) where {T <: IS.InfrastructureSystemsComponent}
    return get_branch_argument_variable_axis(net_reduction_data, T)
end

function get_branch_argument_variable_axis(
    net_reduction_data::ReductionIndex,
    ::Type{T},
) where {T <: IS.InfrastructureSystemsComponent}
    name_axis = get_name_to_arc_map_entries(net_reduction_data, T)
    return collect(keys(name_axis))
end

"""
Reduction entries (`entry name => ((from_no, to_no), reduction map name)`) for branch type
`T`. Absence of `T` yields an empty map rather than a `KeyError`: a type is missing from
the maps when every branch of that type was absorbed by a radial reduction (absorbed
branches carry no reduction entry at all), or when this template's filters excluded all of
them. Both are legitimate, so every read of the maps goes through this.
"""
function get_name_to_arc_map_entries(
    net_reduction_data::ReductionIndex,
    ::Type{T},
) where {T <: IS.InfrastructureSystemsComponent}
    maps = get_name_to_arc_maps(net_reduction_data)
    key = PNM.branch_map_key(T)
    if haskey(maps, key)
        return maps[key]
    end
    return IOM.SortedDict{String, Tuple{Tuple{Int, Int}, String}}()
end

"""
Representative branch-name axis for a constraint family `U` over components of type `T`
under an active network reduction.

Every member of a reduced arc (series segments, parallel groups, across branch types)
shares one set of flow variables, so the arc's physics must be constrained exactly once.
This returns one branch name per reduced arc of `T` not already claimed for `U`, recording
the claim in `reduced_branch_tracker` so the guarantee holds across separate
`construct_device!` calls. Constraint containers must be sized with the returned names.
"""
function get_branch_argument_constraint_axis(
    net_reduction_data::ReductionIndex,
    reduced_branch_tracker::BranchReductionOptimizationTracker,
    ::IS.FlattenIteratorWrapper{T},
    ::Type{U},
) where {T <: IS.InfrastructureSystemsComponent, U <: ConstraintType}
    return get_branch_argument_constraint_axis(
        net_reduction_data,
        reduced_branch_tracker,
        T,
        U,
    )
end

function get_branch_argument_constraint_axis(
    net_reduction_data::ReductionIndex,
    reduced_branch_tracker::BranchReductionOptimizationTracker,
    ::Type{T},
    ::Type{U},
) where {T <: IS.InfrastructureSystemsComponent, U <: ConstraintType}
    constraint_tracker = get_constraint_dict(reduced_branch_tracker)
    constraint_map_by_type = get_constraint_map_by_type(reduced_branch_tracker)
    name_axis = get_name_to_arc_map_entries(net_reduction_data, T)
    arc_tuples_with_constraints =
        get!(Set{Tuple{Int, Int}}, constraint_tracker, U)
    constraint_map = get!(
        Dict{
            Type{<:IS.InfrastructureSystemsComponent},
            IOM.SortedDict{String, Tuple{Tuple{Int, Int}, String}},
        },
        constraint_map_by_type,
        U,
    )
    constraint_submap =
        get!(IOM.SortedDict{String, Tuple{Tuple{Int, Int}, String}}, constraint_map, T)
    for (branch_name, name_axis_tuple) in name_axis
        arc_tuple = name_axis_tuple[1]
        if !(arc_tuple in arc_tuples_with_constraints)
            constraint_submap[branch_name] = name_axis_tuple
            push!(arc_tuples_with_constraints, arc_tuple)
        end
    end
    return collect(keys(constraint_submap))
end

"""
Drop outages from each outage-aware-branch `DeviceModel` whose UUID isn't
registered on `modf_matrix`; without this they'd `KeyError` downstream in
post-contingency expression construction. PNM's `_register_outages!` silently
skips outages it can't convert to a `NetworkModification`, so the model-side
view of `m.outages` can be a strict superset of what's actually usable.
"""
function _consolidate_device_model_outages_with_modf!(
    branch_models::BranchModelContainer,
    modf_matrix::PNM.VirtualMODF,
)
    registered = PNM.get_registered_contingencies(modf_matrix)
    for m in values(branch_models)
        supports_outages(get_formulation(m)) || continue
        for uuid in setdiff(keys(m.outages), keys(registered))
            @warn "Outage $(uuid) (DeviceModel{$(get_component_type(m)), \
                   $(get_formulation(m))}) is not registered on the MODF \
                   matrix and will not contribute any post-contingency \
                   constraints." _group = IOM.LOG_GROUP_MODELS_VALIDATION
            delete!(m.outages, uuid)
        end
    end
    return
end

"""
Install a fresh branch-reduction tracker on `model` sized for `number_of_steps`.
The tracker lives behind `IOM.AbstractBranchReductionTracker` and is `nothing`
until network model instantiation reaches this point.
"""
function _reset_reduced_branch_tracker!(model::NetworkModel, number_of_steps::Int)
    tracker = BranchReductionOptimizationTracker()
    set_number_of_steps!(tracker, number_of_steps)
    IOM.set_reduced_branch_tracker!(model, tracker)
    return
end
