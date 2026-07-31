
# Note: Any future concrete formulation requires the definition of

# construct_device!(
#     ::OptimizationContainer,
#     ::PSY.System,
#     ::DeviceModel{<:PSY.ACTransmission, MyNewFormulation},
#     ::Union{Type{CopperPlateNetworkModel}, Type{AreaBalanceNetworkModel}},
# ) = nothing

#

#################################### Branch Variables ##################################################
# Branch flow variables are created by POM's per-formulation `construct_device!` methods.
# The AC formulations (ACP/ACR/LPACC/IVR) each add directional from-to and to-from
# variables; DC formulations (DCP/NFA/DCPLL) add a single active-power scalar per branch.

#! format: off
get_variable_binary(::Type{FlowActivePowerVariable}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowActivePowerFromToVariable}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowActivePowerToFromVariable}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowReactivePowerFromToVariable}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowReactivePowerToFromVariable}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_parameter_multiplier(::Type{FixValueParameter}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 1.0
get_parameter_multiplier(::Type{LowerBoundValueParameter}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 1.0
get_parameter_multiplier(::Type{UpperBoundValueParameter}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 1.0

get_multiplier_value(::Type{<:AbstractBranchRatingTimeSeriesParameter}, d::PSY.ACTransmission, ::Type{StaticBranch}) = _branch_rating(d)


get_initial_conditions_device_model(::IOM.AbstractOptimizationModel, ::DeviceModel{T, U}) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation} = DeviceModel(T, U)

#### Properties of slack variables
get_variable_binary(::Type{FlowActivePowerSlackUpperBound}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowActivePowerSlackLowerBound}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
# These two methods are defined to avoid ambiguities
get_variable_upper_bound(::Type{FlowActivePowerSlackUpperBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerSlackUpperBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 0.0
get_variable_upper_bound(::Type{FlowActivePowerSlackLowerBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerSlackLowerBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 0.0
get_variable_upper_bound(::Type{FlowActivePowerVariable}, ::PNM.BranchesSeries, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerVariable}, ::PNM.BranchesSeries, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_upper_bound(::Type{FlowActivePowerVariable}, ::PNM.BranchesParallel, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerVariable}, ::PNM.BranchesParallel, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_upper_bound(::Type{FlowActivePowerVariable}, ::PNM.ThreeWindingTransformerCircuit, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerVariable}, ::PNM.ThreeWindingTransformerCircuit, ::Type{<:AbstractBranchFormulation}) = nothing

# Active-flow variable creation bounds: matches the bridge convention so
# `check_variable_bounded(...)` in test_device_branch_constructors.jl finds box bounds on
# directional flow variables. Reactive-flow variables have no creation default; under
# StaticBranchBounds they are bounded later by `branch_rate_bounds!`.
get_variable_upper_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = PSY.get_flow_limits(d, PSY.SU).from_to
get_variable_lower_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = -1 * PSY.get_flow_limits(d, PSY.SU).from_to
get_variable_upper_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = PSY.get_flow_limits(d, PSY.SU).to_from
get_variable_lower_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = -1 * PSY.get_flow_limits(d, PSY.SU).to_from
get_variable_upper_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.TwoWindingTransformer, ::Type{<:AbstractBranchFormulation}) = _branch_rating(d)
get_variable_lower_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.TwoWindingTransformer, ::Type{<:AbstractBranchFormulation}) = _negated_rating(_branch_rating(d))
get_variable_upper_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.TwoWindingTransformer, ::Type{<:AbstractBranchFormulation}) = _branch_rating(d)
get_variable_lower_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.TwoWindingTransformer, ::Type{<:AbstractBranchFormulation}) = _negated_rating(_branch_rating(d))

#! format: on
function get_default_time_series_names(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ACTransmission, V <: AbstractBranchFormulation}
    # Branch rating time series are opt-in: the user must explicitly set the
    # `BranchRatingTimeSeriesParameter` name on the `DeviceModel`. An empty
    # default routes every branch through the static-rating path.
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

"""
DeviceModel attribute key selecting which `PowerNetworkMatrices` function aggregates
the individual circuit ratings of a `PNM.BranchesParallel` into a single maximum flow
limit. Valid values: `"single_element_contingency"` (default; N-1, post-trip surviving
capacity), `"sum_of_max"` (plain Σ Sᵢ), `"impedance_averaged"` (susceptance-weighted
average). `PNM.MixedBranchesParallel` groups always use `sum_of_max`.
"""
const PARALLEL_BRANCH_MAX_RATING_KEY = "parallel_branch_max_rating_method"

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ACTransmission, V <: AbstractBranchFormulation}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
    )
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ACTransmission, V <: AbstractSecurityConstrainedStaticBranch}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
        "include_planned_outages" => false,
    )
end

"""
`MonitoredLine` DeviceModel attribute. When `true`, both endpoint buses of every
monitored line are pinned irreducible so zero-impedance lines survive the network
reduction. Defaults to `false` (such lines are reduced away and not modeled). For
the "base case flowgate" use case.
"""
const MODEL_ALL_BRANCHES_KEY = "model_all_branches"

# Specialize the generic `ACTransmission` defaults for `MonitoredLine` to add
# `MODEL_ALL_BRANCHES_KEY` (default `false`) alongside the inherited keys.
function get_default_attributes(
    ::Type{PSY.MonitoredLine},
    ::Type{V},
) where {V <: AbstractBranchFormulation}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
        MODEL_ALL_BRANCHES_KEY => false,
    )
end

function get_default_attributes(
    ::Type{PSY.MonitoredLine},
    ::Type{V},
) where {V <: AbstractSecurityConstrainedStaticBranch}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
        "include_planned_outages" => false,
        MODEL_ALL_BRANCHES_KEY => false,
    )
end

# Resolve the per-DeviceModel attribute to one of the explicit PNM rating functions.
# `MixedBranchesParallel` ignores the attribute and always uses the plain sum, since
# the constituent branches may carry different DeviceModel preferences and there is
# no defensible way to pick one. The PNM aggregators return system-base values
# (no `PSY.SU`).
function _get_parallel_branch_max_rating(model::DeviceModel, bp::PNM.BranchesParallel)
    method = get_attribute(model, PARALLEL_BRANCH_MAX_RATING_KEY)
    if method == "single_element_contingency"
        return PNM.get_single_element_contingency_rating(bp)
    elseif method == "sum_of_max"
        return PNM.get_sum_of_max_rating(bp)
    elseif method == "impedance_averaged"
        return PNM.get_impedance_averaged_rating(bp)
    else
        error(
            "Unknown $PARALLEL_BRANCH_MAX_RATING_KEY value: $(repr(method)). " *
            "Valid: \"single_element_contingency\", \"sum_of_max\", \"impedance_averaged\".",
        )
    end
end

function _get_parallel_branch_max_rating(::DeviceModel, mbp::PNM.MixedBranchesParallel)
    return PNM.get_sum_of_max_rating(mbp)
end
#################################### Flow Variable Bounds ##################################################

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{F},
) where {
    T <: AbstractACActivePowerFlow,
    U <: PSY.ACTransmission,
    F <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    net_reduction_data = network_model.network_reduction
    branch_names = get_branch_argument_variable_axis(net_reduction_data, devices)
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)

    variable_container = add_variable_container!(
        container,
        T,
        U,
        branch_names,
        time_steps,
    )

    for (name, (arc, reduction)) in PNM.get_name_to_arc_map(net_reduction_data, U)
        # TODO: entry is not type stable here, it can return any type ACTransmission.
        # It might have performance implications. Possibly separate this into other functions
        reduction_entry = all_branch_maps_by_type[reduction][U][arc]
        has_entry, tracker_container = search_for_reduced_branch_argument!(
            reduced_branch_tracker,
            arc,
            T,
        )
        if has_entry
            @assert !isempty(tracker_container) name arc reduction
        end
        ub = get_variable_upper_bound(T, reduction_entry, F)
        lb = get_variable_lower_bound(T, reduction_entry, F)
        for t in time_steps
            if !has_entry
                tracker_container[t] = JuMP.@variable(
                    get_jump_model(container),
                    base_name = "$(T)_$(U)_$(reduction)_{$(name), $(t)}",
                )
                ub !== nothing && JuMP.set_upper_bound(tracker_container[t], ub)
                lb !== nothing && JuMP.set_lower_bound(tracker_container[t], lb)
            end
            variable_container[name, t] = tracker_container[t]
        end
    end
    return
end

"""
Branch flow (and flow-slack) variables for the native nodal network models.

Without an active network reduction this delegates to the generic per-device
`add_variables!`. Under a reduction it mirrors the PTDF tracker pattern: the container
axis is the reduction-entry names (`PNM` `name_to_arc_map`), and every entry of a reduced
arc — series segments, parallel equivalents, across branch types — aliases the SAME
underlying JuMP variable, registered once per arc on the branch-reduction tracker. The
matching balance wiring and constraint builders then treat each arc exactly once.
"""
function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{<:NativeNodalNetworkModel},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{F},
) where {
    T <: Union{AbstractACActivePowerFlow, AbstractACReactivePowerFlow},
    U <: PSY.ACTransmission,
    F <: AbstractBranchFormulation,
}
    net_reduction_data = get_network_reduction(network_model)
    if isempty(net_reduction_data)
        add_variables!(container, T, devices, F)
        return
    end
    time_steps = get_time_steps(container)
    branch_names = get_branch_argument_variable_axis(net_reduction_data, devices)
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)
    jump_model = get_jump_model(container)

    variable_container = add_variable_container!(
        container,
        T,
        U,
        branch_names,
        time_steps,
    )

    for (name, (arc, reduction)) in get_name_to_arc_map_entries(net_reduction_data, U)
        reduction_entry = all_branch_maps_by_type[reduction][U][arc]
        has_entry, tracker_container = search_for_reduced_branch_variable!(
            reduced_branch_tracker,
            arc,
            T,
        )
        ub = get_variable_upper_bound(T, reduction_entry, F)
        lb = get_variable_lower_bound(T, reduction_entry, F)
        for t in time_steps
            if !has_entry
                tracker_container[t] = JuMP.@variable(
                    jump_model,
                    base_name = "$(T)_$(U)_$(reduction)_{$(name), $(t)}",
                )
                ub !== nothing && JuMP.set_upper_bound(tracker_container[t], ub)
                lb !== nothing && JuMP.set_lower_bound(tracker_container[t], lb)
            end
            variable_container[name, t] = tracker_container[t]
        end
    end
    return
end

# Non-negative flow-definition slack container carrying a container META. StaticBranchBounds
# distinguishes its per-direction slack pairs ("p_ft"/"p_tf"/"q_ft"/"q_tf") by meta on the
# shared FlowActivePowerSlack{Upper,Lower}Bound types; `add_variables!` threads no meta, so
# build the container directly. One slack per representative arc — the equality is written
# once per arc. Axes are precomputed by the caller (shared across all metas of one device
# model).
function _add_meta_flow_slack!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta::String,
    branch_names,
    time_steps,
    jump_model,
) where {T <: AbstractACActivePowerFlow, U <: PSY.ACTransmission}
    variable = add_variable_container!(container, T, U, meta, branch_names, time_steps)
    for name in branch_names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            base_name = "$(T)_$(U)_$(meta)_{$(name), $(t)}",
            lower_bound = 0.0,
        )
    end
    return
end

# Directional flow variable types bounded by `branch_rate_bounds!`. DC/PTDF networks carry a
# single scalar active variable; the AC networks (ACP/ACR/LPACC/IVR) carry the four
# directional from/to variables.
_flow_variable_types(::NetworkModel{<:AbstractDCPNetworkModel}) = (FlowActivePowerVariable,)
_flow_variable_types(::NetworkModel{<:AbstractNetworkModel}) = (
    FlowActivePowerFromToVariable,
    FlowActivePowerToFromVariable,
    FlowReactivePowerFromToVariable,
    FlowReactivePowerToFromVariable,
)

# Bound family for each directional flow variable, selected from the two per-branch limit
# families precomputed in `branch_rate_bounds!`. Active variables use the (possibly
# asymmetric, monitoring-based) `min_max_flow_limits`; reactive variables use the symmetric
# thermal rating. For a `MonitoredLine`, `min_max_flow_limits` collapses to an active-flow
# monitoring limit tighter than the rating, which must not clamp reactive flow — PM parity
# bounds q by the thermal rating, and it keeps StaticBranchBounds ≡ StaticBranch (whose
# quadratic apparent-power limit bounds |q| by the rating alone). For a plain `Line` the two
# families coincide, so only `MonitoredLine` reactive widens. An unclassified variable type
# fails with a loud MethodError instead of inheriting the active collapse.
function _directional_flow_limits(
    ::Type{<:AbstractACActivePowerFlow},
    flow_limits::MinMax,
    ::MinMax,
)
    return flow_limits
end

function _directional_flow_limits(
    ::Type{<:AbstractACReactivePowerFlow},
    ::MinMax,
    rating_limits::MinMax,
)
    return rating_limits
end

function branch_rate_bounds!(
    container::OptimizationContainer,
    device_model::DeviceModel{B, T},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {B <: PSY.ACTransmission, T <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    net_reduction_data = get_network_reduction(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)
    variable_types = _flow_variable_types(network_model)
    variables = map(V -> get_variable(container, V, B), variable_types)
    for (name, (arc, reduction)) in PNM.get_name_to_arc_map(net_reduction_data, B)
        # TODO: entry is not type stable here, it can return any type ACTransmission.
        # It might have performance implications. Possibly separate this into other functions
        reduction_entry = all_branch_maps_by_type[reduction][B][arc]
        flow_limits = min_max_flow_limits(reduction_entry, device_model)
        rating = branch_rating(reduction_entry, device_model)
        # An unrated branch (PSS/E RATE=0) is unlimited: leave its flow variables free.
        isnothing(rating) && continue
        rating_limits = (min = -rating, max = rating)
        for (V, var) in zip(variable_types, variables)
            limits = _directional_flow_limits(V, flow_limits, rating_limits)
            @assert limits.min <= limits.max "Infeasible rate limits for branch $(name)"
            for t in time_steps
                # Variable-creation defaults (MonitoredLine asymmetric limits,
                # TwoWindingTransformer circuit ratings) are authoritative — never
                # clobber an existing bound.
                if !JuMP.has_upper_bound(var[name, t])
                    JuMP.set_upper_bound(var[name, t], limits.max)
                end
                if !JuMP.has_lower_bound(var[name, t])
                    JuMP.set_lower_bound(var[name, t], limits.min)
                end
            end
        end
    end
    return
end

################################## Rate Limits constraint_infos ############################

"""
Scalar branch rating for a reduction entry — the single source of truth for
branch flow ratings. Parallel groups use the `PARALLEL_BRANCH_MAX_RATING_KEY`
attribute; every other entry uses `PNM.get_equivalent_rating`. Extend that (not
this) for new types.

Returns `nothing` when the entry has no rating: a transformer circuit's rating is
`Union{Nothing, Float64}` and PSS/E `RATE = 0` parses to `nothing`, meaning genuinely
unlimited. Callers must handle it — a rate constraint is skipped, a bounds formulation
errors. A concrete `0.0` is a data error and stays loud.

Units: PNM's aggregators read `PSY.get_rating(x, PSY.DU)`. That is a no-op for
`Line`/`MonitoredLine`, whose device base is the system base, but wrong for a transformer
circuit, which carries its own `base_power` — so the transformer entries below read
`PSY.SU` off the circuit instead. Aggregates (series chains, parallel groups) still combine
member ratings on device base inside PNM and cannot be corrected from here.
"""
function branch_rating(double_circuit::PNM.AbstractBranchesParallel, model::DeviceModel)
    return _get_parallel_branch_max_rating(model, double_circuit)
end

function branch_rating(entry, ::DeviceModel)
    return PNM.get_equivalent_rating(entry)
end

branch_rating(t::PSY.TwoWindingTransformer, ::DeviceModel) = _branch_rating(t)
branch_rating(w::PNM.ThreeWindingTransformerCircuit, ::DeviceModel) = _branch_rating(w)

"""
Symmetric `(min, max)` flow limits from [`branch_rating`](@ref), or `nothing` for an
unrated entry. Prefer this over the formulation-only `get_min_max_limits` when the
`DeviceModel` is in scope.
"""
_symmetric_limits(rating::Float64) = (min = -rating, max = rating)
_symmetric_limits(::Nothing) = nothing

min_max_flow_limits(entry, model::DeviceModel) =
    _symmetric_limits(branch_rating(entry, model))

# Rating-constraint rows, resolved and filtered once so containers are sized on the subset
# that actually gets rows. An entry whose limits are `nothing` is unrated (a transformer
# circuit with no rating; PSS/E RATE=0) and is genuinely unlimited, so it contributes no
# rows. A time-series-rated branch always gets rows — its limit comes from the parameter,
# not the static rating.
const _RateRow = @NamedTuple{name::String, entry::Any, limits::Any}

function _rate_rows(entries, device_model::DeviceModel, ts_branch_names)
    rows = _RateRow[]
    for (name, entry) in entries
        limits = min_max_flow_limits(entry, device_model)
        if (name in ts_branch_names) || !isnothing(limits)
            push!(rows, (name = name, entry = entry, limits = limits))
        end
    end
    return rows
end

# `MonitoredLine` has explicit, possibly asymmetric `flow_limits`; defer to its
# own `get_min_max_limits` instead of the symmetric `branch_rating` path.
function min_max_flow_limits(device::PSY.MonitoredLine, ::DeviceModel)
    return get_min_max_limits(device, FlowRateConstraint, AbstractBranchFormulation)
end

# Branch-rating time-series multiplier at build time. Non-parallel entries use
# the same aggregation as the static `branch_rating` path. Parallel groups are
# the exception: a series on one member can't be split across the group, so the
# summed (emergency) rating is used regardless of the attribute. Every PNM
# reduction wrapper is `<: PSY.ACTransmission`; the parallel methods are more
# specific (`<: AbstractBranchesParallel`), so they win for groups.
_resolve_branch_multiplier(p, d, f, ::DeviceModel) = get_multiplier_value(p, d, f)

function _resolve_branch_multiplier(
    ::Type{BranchRatingTimeSeriesParameter},
    d::PNM.AbstractBranchesParallel,
    ::Type{<:Union{StaticBranch, AbstractSecurityConstrainedStaticBranch}},
    ::DeviceModel,
)
    @warn "Parallel reduction $(PNM.get_name(d)) has a member with a branch rating \
           time series; using sum_of_max as the multiplier, regardless of the \
           `$PARALLEL_BRANCH_MAX_RATING_KEY` attribute."
    return PNM.get_sum_of_max_rating(d)
end

function _resolve_branch_multiplier(
    ::Type{PostContingencyBranchRatingTimeSeriesParameter},
    d::PNM.AbstractBranchesParallel,
    ::Type{<:Union{StaticBranch, AbstractSecurityConstrainedStaticBranch}},
    ::DeviceModel,
)
    @warn "Parallel reduction $(PNM.get_name(d)) has a member with a \
           post-contingency branch rating time series; using the summed emergency \
           rating as the multiplier, regardless of the \
           `$PARALLEL_BRANCH_MAX_RATING_KEY` attribute."
    return PNM.get_equivalent_emergency_rating(d)
end

function _resolve_branch_multiplier(
    ::Type{BranchRatingTimeSeriesParameter},
    entry::PSY.ACTransmission,
    ::Type{<:Union{StaticBranch, AbstractSecurityConstrainedStaticBranch}},
    ::DeviceModel,
)
    return PNM.get_equivalent_rating(entry)
end

function _resolve_branch_multiplier(
    ::Type{PostContingencyBranchRatingTimeSeriesParameter},
    entry::PSY.ACTransmission,
    ::Type{<:Union{StaticBranch, AbstractSecurityConstrainedStaticBranch}},
    ::DeviceModel,
)
    return PNM.get_equivalent_emergency_rating(entry)
end

# Formulation-typed adapter used by the range-constraint framework (e.g. a branch under
# `FlowLimitConstraint`) and the DCP rate-limit path. `MonitoredLine` overrides this below.
function get_min_max_limits(
    device::PSY.ACTransmission,
    ::Type{<:ConstraintType},
    ::Type{<:AbstractBranchFormulation},
) #  -> Union{Nothing, NamedTuple{(:min, :max), Tuple{Float64, Float64}}}
    rating = PNM.get_equivalent_rating(device)
    return (min = -rating, max = rating)
end

function _add_flow_rate_constraint!(
    container::OptimizationContainer,
    arc::Tuple{Int, Int},
    use_slacks::Bool,
    con_lb::DenseAxisArray,
    con_ub::DenseAxisArray,
    var::DenseAxisArray,
    branch_maps_by_type::Dict,
    name::String,
    device_model::DeviceModel{T},
) where {T <: PSY.ACTransmission}
    reduction_entry = branch_maps_by_type[arc]
    time_steps = get_time_steps(container)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)[name, :]
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)[name, :]
    end
    limits = min_max_flow_limits(reduction_entry, device_model)
    for t in time_steps
        if use_slacks
            ub_lhs = var[name, t] - slack_ub[t]
            lb_lhs = var[name, t] + slack_lb[t]
        else
            ub_lhs = var[name, t]
            lb_lhs = var[name, t]
        end
        con_ub[name, t] =
            JuMP.@constraint(get_jump_model(container), ub_lhs <= limits.max)
        con_lb[name, t] =
            JuMP.@constraint(get_jump_model(container), lb_lhs >= limits.min)
    end
    return
end

"""
Add branch rate limit constraints for ACBranch with AbstractActivePowerModel
"""
function add_constraints!(
    container::OptimizationContainer,
    cons_type::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {
    T <: PSY.ACTransmission,
    U <: AbstractBranchFormulation,
    V <: AbstractActivePowerModel,
}
    time_steps = get_time_steps(container)
    net_reduction_data = network_model.network_reduction
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    branch_names = get_branch_argument_constraint_axis(
        net_reduction_data,
        reduced_branch_tracker,
        devices,
        cons_type,
    )
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)

    con_lb =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "lb",
        )
    con_ub =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "ub",
        )

    array = get_variable(container, FlowActivePowerVariable, T)

    use_slacks = get_use_slacks(device_model)
    for (name, (arc, reduction)) in
        get_constraint_map_by_type(reduced_branch_tracker)[FlowRateConstraint][T]
        _add_flow_rate_constraint!(
            container,
            arc,
            use_slacks,
            con_lb,
            con_ub,
            array,
            all_branch_maps_by_type[reduction][T],
            name,
            device_model,
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    cons_type::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {
    T <: PSY.ACTransmission,
    U <: AbstractBranchFormulation,
    V <: AbstractPTDFNetworkModel,
}
    time_steps = get_time_steps(container)
    net_reduction_data = network_model.network_reduction
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    branch_names = get_branch_argument_constraint_axis(
        net_reduction_data,
        reduced_branch_tracker,
        devices,
        cons_type,
    )
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)

    con_lb =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "lb",
        )
    con_ub =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "ub",
        )

    array = get_expression(container, PTDFBranchFlow, T)

    use_slacks = get_use_slacks(device_model)
    for (name, (arc, reduction)) in
        get_constraint_map_by_type(reduced_branch_tracker)[FlowRateConstraint][T]
        _add_flow_rate_constraint!(
            container,
            arc,
            use_slacks,
            con_lb,
            con_ub,
            array,
            all_branch_maps_by_type[reduction][T],
            name,
            device_model,
        )
    end
    return
end

function _add_flow_rate_constraint_with_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    arc::Tuple{Int, Int},
    use_slacks::Bool,
    con_lb::DenseAxisArray,
    con_ub::DenseAxisArray,
    var::DenseAxisArray,
    branch_maps_by_type::Dict,
    name::String,
    ts_name::String,
) where {T <: PSY.ACTransmission}
    param_container =
        get_parameter(container, BranchRatingTimeSeriesParameter, T)
    param = get_parameter_column_refs(param_container, name)
    mult = get_multiplier_array(param_container)
    if use_slacks
        add_parameterized_rating_constraints!(
            container, con_ub, con_lb, var, name, param, mult,
            get_variable(container, FlowActivePowerSlackUpperBound, T),
            get_variable(container, FlowActivePowerSlackLowerBound, T),
        )
    else
        add_parameterized_rating_constraints!(
            container, con_ub, con_lb, var, name, param, mult,
        )
    end
    return
end

function add_flow_rate_constraint_with_parameters!(
    container::OptimizationContainer,
    cons_type::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {
    T <: PSY.ACTransmission,
    U <: StaticBranch,
    V <: AbstractPTDFNetworkModel,
}
    time_steps = get_time_steps(container)
    net_reduction_data = network_model.network_reduction
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)

    # POM's `get_branch_argument_constraint_axis` already performs per-arc claim
    # dedup as a side effect (populating the tracker's constraint_dict), so the
    # iteration below over `get_constraint_map_by_type` walks the already-deduped
    # arc set. There is no need for the upstream PSI manual `name_to_arc_map`
    # walk + arc-claim push here.
    branch_names = get_branch_argument_constraint_axis(
        net_reduction_data,
        reduced_branch_tracker,
        devices,
        cons_type,
    )

    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)

    con_lb =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "lb",
        )
    con_ub =
        add_constraints_container!(
            container,
            cons_type,
            T,
            branch_names,
            time_steps;
            meta = "ub",
        )

    var_array = get_expression(container, PTDFBranchFlow, T)

    ts_name = get_time_series_names(device_model)[BranchRatingTimeSeriesParameter]
    ts_type = get_default_time_series_type(container)
    use_slacks = get_use_slacks(device_model)
    for (name, (arc, reduction)) in
        get_constraint_map_by_type(reduced_branch_tracker)[FlowRateConstraint][T]
        branch_map_T = all_branch_maps_by_type[reduction][T]
        if PNM.has_time_series(branch_map_T[arc], ts_type, ts_name)
            _add_flow_rate_constraint_with_parameters!(
                container,
                T,
                arc,
                use_slacks,
                con_lb,
                con_ub,
                var_array,
                branch_map_T,
                name,
                ts_name,
            )
        else
            _add_flow_rate_constraint!(
                container,
                arc,
                use_slacks,
                con_lb,
                con_ub,
                var_array,
                branch_map_T,
                name,
                device_model,
            )
        end
    end
    return
end

"""
Error if a PTDF/MODF column length differs from the nodal-balance bus
dimension. Prevents a downstream `@inbounds` out-of-bounds read; a mismatch
means the matrix and container used different network reductions.
"""
function _assert_flow_expression_dimensions(
    name::AbstractString,
    n_col::Int,
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
)
    n_bus = size(nodal_balance_expressions, 1)
    if n_col != n_bus
        error(
            "Flow-expression dimension mismatch for branch/arc '$name': " *
            "PTDF/MODF column has $n_col entries but the nodal-balance " *
            "expression has $n_bus buses. PTDF and MODF must be built with " *
            "the same network reduction as the optimization container.",
        )
    end
    return
end

function _make_flow_expressions!(
    name::String,
    time_steps::UnitRange{Int},
    ptdf_col::Vector{Float64},
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
)
    @debug "Making Flow Expression on thread $(Threads.threadid()) for branch $name"
    _assert_flow_expression_dimensions(name, length(ptdf_col), nodal_balance_expressions)
    nz_idx = [i for i in eachindex(ptdf_col) if abs(ptdf_col[i]) > PTDF_ZERO_TOL]
    hint = length(nz_idx)
    expressions = Vector{JuMP.AffExpr}(undef, length(time_steps))
    for t in time_steps
        acc = IOM.get_hinted_aff_expr(hint)
        @inbounds for i in nz_idx
            JuMP.add_to_expression!(acc, ptdf_col[i], nodal_balance_expressions[i, t])
        end
        expressions[t] = acc
    end
    return name, expressions
end

function _make_flow_expressions!(
    name::String,
    time_steps::UnitRange{Int},
    ptdf_col::SparseArrays.SparseVector{Float64, Int},
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
)
    @debug "Making Flow Expression on thread $(Threads.threadid()) for branch $name"
    _assert_flow_expression_dimensions(name, length(ptdf_col), nodal_balance_expressions)
    nz_idx = SparseArrays.nonzeroinds(ptdf_col)
    nz_val = SparseArrays.nonzeros(ptdf_col)
    hint = length(nz_idx)
    expressions = Vector{JuMP.AffExpr}(undef, length(time_steps))
    for t in time_steps
        acc = IOM.get_hinted_aff_expr(hint)
        @inbounds for k in eachindex(nz_idx)
            JuMP.add_to_expression!(
                acc,
                nz_val[k],
                nodal_balance_expressions[nz_idx[k], t],
            )
        end
        expressions[t] = acc
    end
    return name, expressions
end

function add_expressions!(
    container::OptimizationContainer,
    ::Type{PTDFBranchFlow},
    devices::IS.FlattenIteratorWrapper{B},
    model::DeviceModel{B, <:AbstractBranchFormulation},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {B <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    ptdf = get_network_matrix(network_model)
    net_reduction_data = network_model.network_reduction
    branch_names = get_branch_argument_variable_axis(net_reduction_data, devices)
    # `collect` to a Vector so the spawn loop below can index it for multi-threading.
    name_to_arc_map = collect(PNM.get_name_to_arc_map(net_reduction_data, B))
    nodal_balance_expressions = get_expression(container, ActivePowerBalance,
        PSY.ACBus,
    )

    branch_flow_expr = add_expression_container!(container, PTDFBranchFlow,
        B,
        branch_names,
        time_steps,
    )

    # `ptdf[arc, :]` is a KLU solve; libklu is not concurrency-safe, so the
    # solves run serially on the dispatcher and only the JuMP `AffExpr` build is
    # parallelized via `Threads.@spawn`. The try/catch surfaces the inner
    # exception — the default error handler shows only the wrapping
    # `TaskFailedException`, which makes spawn-task failures undebuggable.
    tasks = map(name_to_arc_map) do pair
        (name, (arc, _)) = pair
        ptdf_col = ptdf[arc, :]
        Threads.@spawn try
            _make_flow_expressions!(
                name,
                time_steps,
                ptdf_col,
                nodal_balance_expressions.data,
            )
        catch e
            @error "PTDF flow-expression task failed" name = name arc = arc exception =
                (e, catch_backtrace())
            rethrow()
        end
    end
    for task in tasks
        name, expressions = fetch(task)
        branch_flow_expr[name, :] .= expressions
    end
    return
end

"""
Add network flow constraints for ACBranch and NetworkModel with <: AbstractPTDFNetworkModel
"""
function add_constraints!(
    container::OptimizationContainer,
    cons_type::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, StaticBranchBounds},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    branch_flow_expr = get_expression(container, PTDFBranchFlow, T)
    flow_variables = get_variable(container, FlowActivePowerVariable, T)
    net_reduction_data = network_model.network_reduction
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    branches = get_branch_argument_constraint_axis(
        net_reduction_data,
        reduced_branch_tracker,
        devices,
        cons_type,
    )
    branch_flow = add_constraints_container!(container, NetworkFlowConstraint,
        T,
        branches,
        time_steps,
    )
    jump_model = get_jump_model(container)

    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end

    for name in branches
        for t in time_steps
            if use_slacks
                rhs = slack_ub[name, t] - slack_lb[name, t]
            else
                rhs = 0.0
            end
            branch_flow[name, t] = JuMP.@constraint(
                jump_model,
                branch_flow_expr[name, t] - flow_variables[name, t] == rhs
            )
        end
    end
    return
end

function add_constraints!(
    ::OptimizationContainer,
    cons_type::Type{NetworkFlowConstraint},
    ::IS.FlattenIteratorWrapper{B},
    ::DeviceModel{B, T},
    ::NetworkModel{<:AbstractPTDFNetworkModel},
) where {B <: PSY.ACTransmission, T <: Union{StaticBranchUnbounded, StaticBranch}}
    @debug "PTDF Branch Flows with $T do not require network flow constraints $cons_type. Flow values are given by PTDFBranchFlow."
    return
end

# `MonitoredLine.flow_limits` may be asymmetric; the symmetric/min-based
# `get_min_max_limits` methods below collapse it to one value and warn once.
# The device, not a formulation type, is passed in (the old `$T` interpolation
# referenced an out-of-scope name — a latent bug).
function _warn_unequal_monitored_flow_limits(device::PSY.MonitoredLine)
    flow_limits = PSY.get_flow_limits(device, PSY.SU)
    if flow_limits.to_from != flow_limits.from_to
        @warn "Flow limits in Line $(PSY.get_name(device)) aren't equal; the \
               minimum will be used."
    end
    return
end

"""
Min and max limits for monitored line
"""
function get_min_max_limits(
    device::PSY.MonitoredLine,
    ::Type{<:ConstraintType},
    ::Type{<:AbstractBranchFormulation},
)
    _warn_unequal_monitored_flow_limits(device)
    limit = min(
        PNM.get_equivalent_rating(device),
        PSY.get_flow_limits(device, PSY.SU).to_from,
        PSY.get_flow_limits(device, PSY.SU).from_to,
    )
    minmax = (min = -1 * limit, max = limit)
    return minmax
end

############################## Flow Limits Constraints #####################################
"""
Add branch flow constraints for monitored lines with DC Power Model
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowLimitConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    ::NetworkModel{V},
) where {
    T <: PSY.MonitoredLine,
    U <: AbstractBranchFormulation,
    V <: AbstractDCPNetworkModel,
}
    add_range_constraints!(
        container,
        FlowLimitConstraint,
        FlowActivePowerVariable,
        devices,
        model,
        V,
    )
    return
end

"""
Don't add branch flow constraints for monitored lines if formulation is StaticBranchUnbounded
"""
function add_constraints!(
    ::OptimizationContainer,
    ::Type{FlowRateConstraintFromTo},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    ::NetworkModel{V},
) where {
    T <: PSY.MonitoredLine,
    U <: StaticBranchUnbounded,
    V <: AbstractActivePowerModel,
}
    return
end

# Branch slack pricing derives from the pair's `slack_spec` declaration
# (core/branch_slack_specs.jl): every slack container the spec names is priced at the
# violation cost, so pricing cannot drift from what the constructors build. There is
# deliberately no `NoBranchSlacks` method — validation and the construct-time backstop
# reject slacked no-machinery pairs, so reaching pricing with one is a bug that must
# surface as a MethodError.
function add_to_objective_function!(
    container::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, F},
    ::Type{N},
) where {T <: PSY.ACTransmission, F <: AbstractBranchFormulation, N <: AbstractNetworkModel}
    if get_use_slacks(device_model)
        _price_slack_spec!(container, T, slack_spec(F, N))
    end
    return
end

function _price_slack_spec!(
    container::OptimizationContainer,
    ::Type{T},
    ::RowPairSlacks,
) where {T <: PSY.ACTransmission}
    _price_slack_pair!(container, T)
    return
end

function _price_slack_spec!(
    container::OptimizationContainer,
    ::Type{T},
    spec::EqualityPairSlacks,
) where {T <: PSY.ACTransmission}
    for meta in get_pair_metas(spec)
        _price_slack_pair!(container, T, meta)
    end
    return
end

function _price_slack_spec!(
    container::OptimizationContainer,
    ::Type{T},
    spec::QuadraticUpperSlacks,
) where {T <: PSY.ACTransmission}
    for meta in get_upper_metas(spec)
        _price_slack_upper!(container, T, meta)
    end
    return
end

# Price an upper/lower slack pair (equality relaxation) at the violation cost. Iterates
# container names because there might be a network reduction.
function _price_slack_pair!(
    container::OptimizationContainer,
    ::Type{T},
    meta::String = IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: PSY.ACTransmission}
    variable_up = get_variable(container, FlowActivePowerSlackUpperBound, T, meta)
    variable_dn = get_variable(container, FlowActivePowerSlackLowerBound, T, meta)
    for name in axes(variable_up, 1)
        for t in get_time_steps(container)
            add_to_objective_invariant_expression!(
                container,
                (variable_dn[name, t] + variable_up[name, t]) *
                CONSTRAINT_VIOLATION_SLACK_COST,
            )
        end
    end
    return
end

# Price a one-sided upper slack (quadratic-limit relaxation) at the violation cost.
function _price_slack_upper!(
    container::OptimizationContainer,
    ::Type{T},
    meta::String = IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: PSY.ACTransmission}
    variable_up = get_variable(container, FlowActivePowerSlackUpperBound, T, meta)
    for name in axes(variable_up, 1)
        for t in get_time_steps(container)
            add_to_objective_invariant_expression!(
                container,
                variable_up[name, t] * CONSTRAINT_VIOLATION_SLACK_COST,
            )
        end
    end
    return
end

# Concrete element type for `_branch_geometries` so constraint builders stay type-stable
# and empty axes still yield `String` name comprehensions (an axis can be empty when the
# other branch type's constructor claimed every shared reduced arc first).
#
# `adm` is the full π-model used by the AC families. `b_dc`/`alpha` are the DC-model pair:
# the susceptance and equivalent phase shift the DC builders (DCP Ohm's law,
# BThetaBranchFlow, DCPLL) use. They are separate fields because a transformer's tap divides
# the DC susceptance while the AC π-model applies it per-term, and because a reduced arc's
# equivalent shift is not always recoverable from `adm.shift`.
const BranchGeometry = @NamedTuple{
    name::String,
    from_name::String,
    to_name::String,
    from_number::Int,
    to_number::Int,
    adm::NamedTuple{
        (:g, :b, :g_fr, :b_fr, :g_to, :b_to, :tap, :shift),
        NTuple{8, Float64},
    },
    b_dc::Float64,
    alpha::Float64,
    direct::Bool,
}

# Geometry of one modeled arc, un-reduced case. Takes an ELEMENT from `_branch_elements`
# (the device itself, or a PNM winding wrapper for a three-winding transformer), not a
# device — a 3W transformer contributes three arcs. Split per-element so the caller's
# comprehension yields a concretely-typed vector.
function _branch_geometry(e)
    arc = PSY.get_arc(e)
    from_bus = PSY.get_from(arc)
    to_bus = PSY.get_to(arc)
    adm = PNM.branch_admittance(e)
    return (
        name = _element_name(e),
        from_name = PSY.get_name(from_bus),
        to_name = PSY.get_name(to_bus),
        from_number = PSY.get_number(from_bus),
        to_number = PSY.get_number(to_bus),
        adm = adm,
        b_dc = _dc_susceptance(adm),
        alpha = adm.shift,
        direct = true,
    )
end

# DC susceptance of a branch, from its π-model. The tap divides it: PNM's Ybus places the
# ideal ratio on the from side, so the DC linearization is `p = -(b/tap)·(Δθ - α)`. A line
# has `tap == 1`, and a reduced arc reports `tap == 1` with the tap already folded into `b`,
# so the division is safe everywhere.
_dc_susceptance(adm) = -adm.b / adm.tap

# A direct entry is the physical branch itself; series/parallel entries are PNM's
# equivalent wrappers. Drives per-device data lookups (angle limits, monitored-line
# flow limits) that only exist on physical branches.
_is_direct_entry(::PNM.BranchesSeries) = false
_is_direct_entry(::PNM.AbstractBranchesParallel) = false
_is_direct_entry(::PSY.ACTransmission) = true

# π-parameters of a reduction entry: the branch's own admittance for a direct arc, PNM's
# merged equivalent for a series/parallel arc. Both are oriented to the entry's stored
# reduced arc, which is exactly the arc `name_to_arc_map` reports for the entry.
_entry_admittance(entry::PNM.BranchesSeries, nr::PNM.NetworkReductionData) =
    PNM.branch_admittance(entry, nr)
_entry_admittance(entry::PNM.AbstractBranchesParallel, nr::PNM.NetworkReductionData) =
    PNM.branch_admittance(entry, nr)
_entry_admittance(entry::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.branch_admittance(entry)

# Geometry of one reduction entry (`name_to_arc_map` row). The reduced arc's endpoints
# are always retained buses, so `number_to_name` (retained-only) covers them.
function _entry_geometry(
    nr::PNM.NetworkReductionData,
    number_to_name::Dict{Int, String},
    name::String,
    arc_tuple::Tuple{Int, Int},
    entry,
)
    from_no = arc_tuple[1]
    to_no = arc_tuple[2]
    adm = _entry_admittance(entry, nr)
    return (
        name = name,
        from_name = number_to_name[from_no],
        to_name = number_to_name[to_no],
        from_number = from_no,
        to_number = to_no,
        adm = adm,
        b_dc = _dc_susceptance(adm),
        # Orientation-aware and total across every reduction map, unlike `adm.shift`,
        # which a merged equivalent recovers only when a single π exists.
        alpha = PNM.arc_dc_phase_shift(nr, arc_tuple),
        direct = _is_direct_entry(entry),
    )
end

# (name, rating-entry) pairs for a rating/limit constraint family: one pair per device
# when no reduction is active (the entry IS the device), or one pair per reduced arc of
# `T` not yet claimed for `C` (the entry is the direct branch or PNM's series/parallel
# equivalent). Rating constraints bind the arc's shared flow variables, so like the
# Ohm's-law builders they must cover each reduced arc exactly once.
function _branch_rating_entries(
    network_model::NetworkModel,
    devices::IS.FlattenIteratorWrapper{T},
    ::Type{T},
    ::Type{C},
) where {T <: PSY.ACTransmission, C <: ConstraintType}
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        return Tuple{String, Any}[
            (_element_name(e), e) for d in devices for e in _branch_elements(d)
        ]
    end
    tracker = get_reduced_branch_tracker(network_model)
    representative_names =
        get_branch_argument_constraint_axis(network_reduction, tracker, T, C)
    arc_map = get_name_to_arc_map_entries(network_reduction, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(network_reduction)
    return Tuple{String, Any}[
        (name, all_branch_maps_by_type[arc_map[name][2]][T][arc_map[name][1]]) for
        name in representative_names
    ]
end

"""
Per-branch network geometry for the native nodal constraint builders.

Un-reduced case: one geometry per modeled arc — the device itself for a one-arc branch,
three for a three-winding transformer (own endpoints, own π-parameters). Under an
active network reduction: one geometry per reduced arc of `T` not yet claimed for the
constraint family `C` — the representative axis from
[`get_branch_argument_constraint_axis`](@ref) — with PNM's reduction-aware equivalent
admittance. Every member of a reduced arc (series segments, parallel groups, across
branch types) shares one set of flow variables, so each arc's physics must be built
exactly once; the tracker-backed axis guarantees that across `construct_device!` calls.
Constraint containers must be sized with the returned geometry names.
"""
function _branch_geometries(
    number_to_name::Dict{Int, String},
    network_model,
    devices,
    ::Type{T},
    ::Type{C},
) where {T <: PSY.ACTransmission, C <: ConstraintType}
    nr = get_network_reduction(network_model)
    if isempty(nr)
        return BranchGeometry[
            _branch_geometry(e) for d in devices for e in _branch_elements(d)
        ]
    end
    tracker = get_reduced_branch_tracker(network_model)
    representative_names = get_branch_argument_constraint_axis(nr, tracker, T, C)
    arc_map = get_name_to_arc_map_entries(nr, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(nr)
    geoms = BranchGeometry[
        _entry_geometry(
            nr,
            number_to_name,
            name,
            arc_map[name][1],
            all_branch_maps_by_type[arc_map[name][2]][T][arc_map[name][1]],
        ) for name in representative_names
    ]
    return geoms
end

################################## ACP apparent-power rate constraints ######################

"""
Shared builder for directional apparent-power rate limit constraints under
ACPNetworkModel.

Constrains `pflow^2 + qflow^2 ≤ rating^2` for the directional active/reactive flow variable
pair (`PVar`/`QVar`) and stores the result under the constraint key `ConsKey`. Under an
active network reduction it covers each reduced arc exactly once (the flow variables are
shared per arc), with the rating from the reduction entry's equivalent parameters.
"""
function _add_directional_flow_rate_limits!(
    container::OptimizationContainer,
    ::Type{ConsKey},
    ::Type{PVar},
    ::Type{QVar},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel,
) where {
    ConsKey <: ConstraintType,
    PVar <: VariableType,
    QVar <: VariableType,
    T <: PSY.ACTransmission,
    U <: AbstractBranchFormulation,
}
    time_steps = get_time_steps(container)
    pflow = get_variable(container, PVar, T)
    qflow = get_variable(container, QVar, T)
    quad_slacks = _quadratic_rate_slacks(container, device_model, T)
    entries = _branch_rating_entries(network_model, devices, T, ConsKey)
    jump_model = get_jump_model(container)

    # Parameter array is keyed by time-series UUID, multiplier array by branch name,
    # so the per-branch column is resolved via `get_parameter_column_refs`. Empty
    # `ts_branch_names` routes every branch through the static path.
    ts_branch_names = String[]
    local param_container, mult
    if has_container_key(container, BranchRatingTimeSeriesParameter, T)
        param_container =
            get_parameter(container, BranchRatingTimeSeriesParameter, T)
        mult = get_multiplier_array(param_container)
        ts_branch_names = Set(axes(mult, 1))
    end

    # Resolve ratings before sizing: an unrated entry is unlimited and gets no rows, so the
    # container axis is the rated subset. Time-series-rated branches always get rows.
    rated = [
        (name, entry, _directional_flow_rating(entry, device_model)) for
        (name, entry) in entries
    ]
    filter!(x -> (x[1] in ts_branch_names) || !isnothing(x[3]), rated)
    cons = add_constraints_container!(
        container, ConsKey, T, [name for (name, _, _) in rated], time_steps,
    )

    for (name, entry, rating) in rated
        if name in ts_branch_names
            param = get_parameter_column_refs(param_container, name)
            for t in time_steps
                lhs =
                    pflow[name, t]^2 + qflow[name, t]^2 -
                    _upper_slack_term(quad_slacks, name, t)
                cons[name, t] = JuMP.@constraint(
                    jump_model,
                    lhs <= _rate_rhs_squared(param[t] * mult[name, t]),
                )
            end
        else
            for t in time_steps
                lhs =
                    pflow[name, t]^2 + qflow[name, t]^2 -
                    _upper_slack_term(quad_slacks, name, t)
                cons[name, t] = JuMP.@constraint(
                    jump_model,
                    lhs <= _rate_rhs_squared(rating),
                )
            end
        end
    end
    return
end

# Apparent-power rating for a rating entry, in system base (PSY.SU) so rating^2 matches
# the per-unit flow variables. Direct entries keep the device's own rating; reduction
# equivalents use PNM's aggregation (min over a series chain; the device-model attribute
# rule for parallel groups).
#
# `nothing` (a transformer circuit with no rating; PSS/E RATE=0) means genuinely unlimited
# and is returned for the caller to skip. A concrete zero is still a loud data error
# (matching the IVR current-rating behavior): `p² + q² ≤ 0` would silently pin the branch to
# zero flow, deleting it from the network — MATPOWER-style data uses rating 0 to mean
# "unlimited", which must be resolved in the data, not by the model.
function _directional_flow_rating(d::PSY.ACTransmission, ::DeviceModel)
    rating = _branch_rating(d)
    _error_on_zero_rating(rating, _element_name(d))
    return rating
end

function _directional_flow_rating(
    entry::Union{PNM.BranchesSeries, PNM.AbstractBranchesParallel},
    device_model::DeviceModel,
)
    rating = branch_rating(entry, device_model)
    _error_on_zero_rating(rating, "reduced arc $(PNM.get_name(entry))")
    return rating
end

_error_on_zero_rating(::Nothing, ::AbstractString) = nothing
function _error_on_zero_rating(rating::Float64, name::AbstractString)
    iszero(rating) && error(
        "Branch $(name) has a zero rating; the flow limit would force zero flow. \
         Assign a non-zero thermal rating or use an unbounded formulation.",
    )
    return nothing
end

################################## AC-reactive family rate-limit constraints ##################

"""
Add from-to apparent-power rate limit for ACBranch under native ACP/ACR/LPACC/IVR.

Constrains pft² + qft² ≤ rating².
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowRateConstraintFromTo},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{
        <:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    _add_directional_flow_rate_limits!(
        container,
        FlowRateConstraintFromTo,
        FlowActivePowerFromToVariable,
        FlowReactivePowerFromToVariable,
        devices,
        device_model,
        network_model,
    )
    return
end

"""
Add to-from apparent-power rate limit for ACBranch under native ACP/ACR/LPACC/IVR.

Constrains ptf² + qtf² ≤ rating².
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowRateConstraintToFrom},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{
        <:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    _add_directional_flow_rate_limits!(
        container,
        FlowRateConstraintToFrom,
        FlowActivePowerToFromVariable,
        FlowReactivePowerToFromVariable,
        devices,
        device_model,
        network_model,
    )
    return
end

"""
Create the four directional `NetworkFlowConstraint` containers shared by every AC
branch-flow formulation, fixed- and variable-tap alike: active and reactive power in
the from→to and to→from directions, keyed by branch name and time step. Thin factory
over `add_constraints_container!`; returns them in (p_ft, q_ft, p_tf, q_tf) order so a
caller can write `cons_pft, cons_qft, cons_ptf, cons_qtf = ...`. Keeping this in one
place lets each formulation's method show only the Ohm's-law math that actually differs.
"""
function _add_flow_constraint_containers!(
    container::OptimizationContainer,
    ::Type{T},
    branch_names::Vector{String},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    cons_pft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_ft",
    )
    cons_qft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_ft",
    )
    cons_ptf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_tf",
    )
    cons_qtf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_tf",
    )
    return cons_pft, cons_qft, cons_ptf, cons_qtf
end

# π-model coefficients for a fixed tap `tm` and phase shift, shared by the polar (ACP) and
# rectangular (ACR) Ohm's law. Tap is folded in here so nothing divides inside the time loop.
#
# The to-side carries no tap, and the coupling terms scale as 1/tm.
# ACR uses `e_sin = -d_sin`.
function _pi_flow_coefficients(g, b, g_fr, b_fr, g_to, b_to, tm, shift)
    cs = cos(shift)
    sn = sin(shift)
    tm2 = tm^2
    return (
        cs = cs,
        sn = sn,
        gg_fr = (g + g_fr) / tm2,
        bb_fr = (b + b_fr) / tm2,
        gg_to = g + g_to,
        bb_to = b + b_to,
        a_cos = (-g * cs + b * sn) / tm,
        a_sin = (-b * cs - g * sn) / tm,
        c_cos = (-g * cs - b * sn) / tm,
        d_sin = (b * cs - g * sn) / tm,
    )
end

# Slack holders for the equality/limit rows. `_SlackPair` carries a metaed upper/lower pair
# (equality relaxation, term `up - lo`); `_UpperSlack` carries a one-sided upper slack
# (quadratic-limit relaxation, term `up`). The no-slack twins contribute a constant 0.0 so
# constraint builders stay branch-free.
struct _NoSlackPair end

struct _SlackPair{A}
    up::A
    lo::A
end

_slack_term(::_NoSlackPair, ::String, ::Int) = 0.0
_slack_term(s::_SlackPair, name::String, t::Int) = s.up[name, t] - s.lo[name, t]

struct _NoUpperSlack end

struct _UpperSlack{A}
    up::A
end

_upper_slack_term(::_NoUpperSlack, ::String, ::Int) = 0.0
_upper_slack_term(s::_UpperSlack, name::String, t::Int) = s.up[name, t]

function _slack_pair(
    container::OptimizationContainer,
    ::Type{T},
    meta::String,
) where {T <: PSY.ACTransmission}
    return _SlackPair(
        get_variable(container, FlowActivePowerSlackUpperBound, T, meta),
        get_variable(container, FlowActivePowerSlackLowerBound, T, meta),
    )
end

# NamedTuple keys derived from the meta consts so container metas and holder fields
# cannot drift apart.
const _FLOW_SLACK_KEYS = Symbol.(FLOW_DEFINITION_SLACK_METAS)
const _CURRENT_SLACK_KEYS = Symbol.(CURRENT_DEFINITION_SLACK_METAS)

# StaticBranchBounds relaxes each of the four flow-definition equalities with its OWN metaed
# slack pair ("p_ft"/"p_tf"/"q_ft"/"q_tf"). A single pair shared between p_ft and p_tf would
# self-cancel: the two Ohm's-law expressions are anti-symmetric (`f_tf ≈ -f_ft + losses`), so
# a shared term drops out of their difference and caps the physical relaxation at losses/2 —
# exactly zero on a lossless line. Per-direction metas keep each balance row independently
# relaxable, mirroring the IVR current layer's per-terminal metas. Every other formulation
# keeps its equalities exact and carries `_NoSlackPair`s.
function _flow_equality_slacks(
    ::OptimizationContainer,
    ::DeviceModel{T, F},
    ::Type{T},
) where {T <: PSY.ACTransmission, F <: AbstractBranchFormulation}
    return NamedTuple{_FLOW_SLACK_KEYS}(map(_ -> _NoSlackPair(), _FLOW_SLACK_KEYS))
end

function _flow_equality_slacks(
    container::OptimizationContainer,
    device_model::DeviceModel{T, StaticBranchBounds},
    ::Type{T},
) where {T <: PSY.ACTransmission}
    if !get_use_slacks(device_model)
        return NamedTuple{_FLOW_SLACK_KEYS}(map(_ -> _NoSlackPair(), _FLOW_SLACK_KEYS))
    end
    return NamedTuple{_FLOW_SLACK_KEYS}(
        map(meta -> _slack_pair(container, T, meta), FLOW_DEFINITION_SLACK_METAS),
    )
end

# Quadratic apparent-power-limit slack. Only StaticBranch subtracts a slack from `p²+q²`
# (its meta-less FlowActivePowerSlackUpperBound); StaticBranchBounds relaxes at the
# flow-definition equalities instead, so its quadratic stays exact.
function _quadratic_rate_slacks(
    ::OptimizationContainer,
    ::DeviceModel{T, F},
    ::Type{T},
) where {T <: PSY.ACTransmission, F <: AbstractBranchFormulation}
    return _NoUpperSlack()
end

function _quadratic_rate_slacks(
    container::OptimizationContainer,
    device_model::DeviceModel{T, StaticBranch},
    ::Type{T},
) where {T <: PSY.ACTransmission}
    if !get_use_slacks(device_model)
        return _NoUpperSlack()
    end
    return _UpperSlack(get_variable(container, FlowActivePowerSlackUpperBound, T))
end

# IVR terminal-current defining equalities relaxed by StaticBranchBounds: each of the four
# KCL current definitions (cr_fr, ci_fr, cr_to, ci_to) carries its own metaed slack pair.
# The from-terminal rows scale the current by tm² on the LHS while the to-terminal rows do
# not, so a shared cr/ci pair would relax the two ends unequally under off-nominal taps;
# per-terminal metas keep each definition row independently relaxable.
function _current_equality_slacks(
    ::OptimizationContainer,
    ::DeviceModel{T, F},
    ::Type{T},
) where {T <: PSY.ACTransmission, F <: AbstractBranchFormulation}
    return NamedTuple{_CURRENT_SLACK_KEYS}(map(_ -> _NoSlackPair(), _CURRENT_SLACK_KEYS))
end

function _current_equality_slacks(
    container::OptimizationContainer,
    device_model::DeviceModel{T, StaticBranchBounds},
    ::Type{T},
) where {T <: PSY.ACTransmission}
    if !get_use_slacks(device_model)
        return NamedTuple{_CURRENT_SLACK_KEYS}(
            map(_ -> _NoSlackPair(), _CURRENT_SLACK_KEYS),
        )
    end
    return NamedTuple{_CURRENT_SLACK_KEYS}(
        map(meta -> _slack_pair(container, T, meta), CURRENT_DEFINITION_SLACK_METAS),
    )
end

# One-sided current-magnitude limit slack. Only StaticBranch relaxes cr²+ci² ≤ c_rating² to
# cr²+ci² − s_c ≤ c_rating² per terminal (metas "c_from"/"c_to"); every other formulation
# keeps the terminal current limit hard.
function _current_magnitude_slacks(
    ::OptimizationContainer,
    ::DeviceModel{T, F},
    ::Type{T},
    ::String,
) where {T <: PSY.ACTransmission, F <: AbstractBranchFormulation}
    return _NoUpperSlack()
end

function _current_magnitude_slacks(
    container::OptimizationContainer,
    device_model::DeviceModel{T, StaticBranch},
    ::Type{T},
    meta::String,
) where {T <: PSY.ACTransmission}
    if !get_use_slacks(device_model)
        return _NoUpperSlack()
    end
    return _UpperSlack(get_variable(container, FlowActivePowerSlackUpperBound, T, meta))
end

# Polar (ACP) π-model Ohm's law for one branch, one time step. `coef` from
# `_pi_flow_coefficients`, which has already folded the fixed tap into every term.
function _add_acp_flow!(
    jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
    name, t, vmf, vmt, θ, coef, p_ft_slack, q_ft_slack, p_tf_slack, q_tf_slack,
)
    cons_pft[name, t] = JuMP.@constraint(
        jump_model,
        pft[name, t] ==
        coef.gg_fr * vmf^2 +
        coef.a_cos * vmf * vmt * cos(θ) +
        coef.a_sin * vmf * vmt * sin(θ) + p_ft_slack,
    )
    cons_qft[name, t] = JuMP.@constraint(
        jump_model,
        qft[name, t] ==
        -coef.bb_fr * vmf^2 +
        (-coef.a_sin) * vmf * vmt * cos(θ) +
        coef.a_cos * vmf * vmt * sin(θ) + q_ft_slack,
    )
    cons_ptf[name, t] = JuMP.@constraint(
        jump_model,
        ptf[name, t] ==
        coef.gg_to * vmt^2 +
        coef.c_cos * vmt * vmf * cos(θ) +
        coef.d_sin * vmt * vmf * sin(θ) + p_tf_slack,
    )
    cons_qtf[name, t] = JuMP.@constraint(
        jump_model,
        qtf[name, t] ==
        -coef.bb_to * vmt^2 +
        coef.d_sin * vmt * vmf * cos(θ) +
        (-coef.c_cos) * vmt * vmf * sin(θ) + q_tf_slack,
    )
    return
end

# Rectangular (ACR) π-model Ohm's law for one branch, one time step. Same coefficients as
# ACP; the rectangular substitution replaces vmf²/vmf·vmt·cos/vmf·vmt·sin with the
# pre-built bilinears `vsq_fr`/`vv_cos`/`vv_sin`. `e_sin = -d_sin` (rectangular sin sign).
function _add_acr_flow!(
    jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
    name, t, vsq_fr, vsq_to, vv_cos, vv_sin, coef,
    p_ft_slack, q_ft_slack, p_tf_slack, q_tf_slack,
)
    e_sin = -coef.d_sin
    cons_pft[name, t] = JuMP.@constraint(
        jump_model,
        pft[name, t] ==
        coef.gg_fr * vsq_fr +
        coef.a_cos * vv_cos +
        coef.a_sin * vv_sin + p_ft_slack,
    )
    cons_qft[name, t] = JuMP.@constraint(
        jump_model,
        qft[name, t] ==
        -coef.bb_fr * vsq_fr +
        (-coef.a_sin) * vv_cos +
        coef.a_cos * vv_sin + q_ft_slack,
    )
    cons_ptf[name, t] = JuMP.@constraint(
        jump_model,
        ptf[name, t] ==
        coef.gg_to * vsq_to +
        coef.c_cos * vv_cos -
        e_sin * vv_sin + p_tf_slack,
    )
    cons_qtf[name, t] = JuMP.@constraint(
        jump_model,
        qtf[name, t] ==
        -coef.bb_to * vsq_to -
        e_sin * vv_cos -
        coef.c_cos * vv_sin + q_tf_slack,
    )
    return
end

"""
Add full π-model rectangular AC Ohm's law constraints for ACBranch under ACRNetworkModel.

Four constraints per branch per time step (p_ft, q_ft, p_tf, q_tf) relate the four
directional flow variables to rectangular voltage components (vr, vi) via the
π-equivalent circuit. Rectangular identity applied to the ACP polar expressions:
  vmf^2            → vr_fr^2 + vi_fr^2
  vmf*vmt*cos(θ)  → vr_fr*vr_to + vi_fr*vi_to
  vmf*vmt*sin(θ)  → vi_fr*vr_to - vr_fr*vi_to
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{ACRNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)

    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, branch_names)
    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)

    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        coef = _pi_flow_coefficients(
            adm.g, adm.b, adm.g_fr, adm.b_fr, adm.g_to, adm.b_to, adm.tap, adm.shift,
        )

        for t in time_steps
            vr_fr = vr[from_bus, t]
            vr_to = vr[to_bus, t]
            vi_fr = vi[from_bus, t]
            vi_to = vi[to_bus, t]
            vsq_fr = vr_fr^2 + vi_fr^2
            vsq_to = vr_to^2 + vi_to^2
            vv_cos = vr_fr * vr_to + vi_fr * vi_to
            vv_sin = vi_fr * vr_to - vr_fr * vi_to
            _add_acr_flow!(
                jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
                name, t, vsq_fr, vsq_to, vv_cos, vv_sin, coef,
                _slack_term(slacks.p_ft, name, t),
                _slack_term(slacks.q_ft, name, t),
                _slack_term(slacks.p_tf, name, t),
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

################################## LPACCNetworkModel branch constraints ###############

# Branch voltage-angle-difference bounds (angmin, angmax). Only Line / MonitoredLine
# carry angle-limit data; other branch types get a finite ±π/2 default so the LPAC
# cosine variable and its relaxation stay bounded (Principle 0).
# angle limits are in radians — no per-unit conversion
_lpacc_branch_angle_limits(d::PSY.Line) = PSY.get_angle_limits(d)
_lpacc_branch_angle_limits(d::PSY.MonitoredLine) = PSY.get_angle_limits(d)
_lpacc_branch_angle_limits(::PSY.ACTransmission) = (min = -π / 2, max = π / 2)

# Finite cosine-variable bounds (cos_min, cos_max) from the branch angle limits, following
# the PowerModels `variable_buspair_cosine` convention.
function _lpacc_cosine_bounds(d::PSY.ACTransmission)
    lims = _lpacc_branch_angle_limits(d)
    angmin = lims.min
    angmax = lims.max
    if angmin >= 0
        return (cos(angmax), cos(angmin))
    elseif angmax <= 0
        return (cos(angmin), cos(angmax))
    else
        return (min(cos(angmin), cos(angmax)), 1.0)
    end
end

"""
Create the bus-pair cosine variable (`cs`) for ACBranch under LPACCNetworkModel,
indexed by branch name. Bounded by the cosine of the branch angle limits (Principle 0),
start 1.0.
"""
function add_variables!(
    container::OptimizationContainer,
    ::Type{CosineApproximation},
    devices::IS.FlattenIteratorWrapper{T},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        elements = [e for d in devices for e in _branch_elements(d)]
        names = [_element_name(e) for e in elements]
        var = add_variable_container!(container, CosineApproximation, T, names, time_steps)
        for d in elements
            name = _element_name(d)
            (cmin, cmax) = _lpacc_cosine_bounds(d)
            for t in time_steps
                var[name, t] = JuMP.@variable(
                    jump_model,
                    base_name = "CosineApproximation_$(T)_{$(name), $(t)}",
                    lower_bound = cmin,
                    upper_bound = cmax,
                    start = 1.0,
                )
            end
        end
        return
    end
    # Reduced case: `cs` approximates cos(θ_fr - θ_to) of the reduced arc, so all entries
    # of an arc (across branch types) alias one tracker-registered variable, mirroring the
    # flow variables. Equivalent entries have no angle-limit data and use the ±π/2 default.
    names = get_branch_argument_variable_axis(network_reduction, devices)
    tracker = get_reduced_branch_tracker(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(network_reduction)
    var = add_variable_container!(container, CosineApproximation, T, names, time_steps)
    for (name, (arc, reduction)) in get_name_to_arc_map_entries(network_reduction, T)
        entry = all_branch_maps_by_type[reduction][T][arc]
        has_entry, tracker_container = search_for_reduced_branch_variable!(
            tracker, arc, CosineApproximation,
        )
        (cmin, cmax) = _lpacc_cosine_bounds(entry)
        for t in time_steps
            if !has_entry
                tracker_container[t] = JuMP.@variable(
                    jump_model,
                    base_name = "CosineApproximation_$(T)_$(reduction)_{$(name), $(t)}",
                    lower_bound = cmin,
                    upper_bound = cmax,
                    start = 1.0,
                )
            end
            var[name, t] = tracker_container[t]
        end
    end
    return
end

"""
Add the LPAC convex cosine relaxation for ACBranch under LPACCNetworkModel:

    cs ≤ 1 - (1 - cos(vad_max))/vad_max² · (va_fr - va_to)²

with `vad_max = max(|angmin|, |angmax|)`. The right-hand side is concave in the angle
difference, so the constraint is convex (a quadratic cut bounding `cs` from above).
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{CosineRelaxationConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    cs = get_variable(container, CosineApproximation, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms = _branch_geometries(
        number_to_name, network_model, devices, T, CosineRelaxationConstraint,
    )
    # Keyed by element name, not device name: a three-winding transformer's geometries are
    # named "X_winding_i" and would miss a device-keyed lookup.
    element_by_name =
        Dict(_element_name(e) => e for d in devices for e in _branch_elements(d))
    # Angle limits are per-device data: a direct entry reads its own device; a PNM
    # series/parallel equivalent has none and uses the same ±π/2 default as devices
    # without the angle-limits API. Zero-width limits produce no constraint, so the
    # container is sized on the constrained subset only.
    constrained = [(g, _entry_angle_limits(g, element_by_name)) for g in geoms]
    filter!(x -> !iszero(max(abs(x[2].min), abs(x[2].max))), constrained)
    branch_names = [g.name for (g, _) in constrained]
    cons = add_constraints_container!(
        container, CosineRelaxationConstraint, T, branch_names, time_steps,
    )

    for (g, lims) in constrained
        vad_max = max(abs(lims.min), abs(lims.max))
        k = (1.0 - cos(vad_max)) / vad_max^2
        for t in time_steps
            cons[g.name, t] = JuMP.@constraint(
                get_jump_model(container),
                cs[g.name, t] <=
                1.0 - k * (va[g.from_name, t] - va[g.to_name, t])^2,
            )
        end
    end
    return
end

# Angle-difference bounds for one geometry entry: direct entries defer to the device's
# `_lpacc_branch_angle_limits`; reduction equivalents carry no angle-limit data and use
# the same finite ±π/2 default as devices without the angle-limits API.
function _entry_angle_limits(geometry, element_by_name::Dict{String, <:PSY.ACTransmission})
    if geometry.direct
        return _lpacc_branch_angle_limits(element_by_name[geometry.name])
    end
    return (min = -π / 2, max = π / 2)
end

"""
Add the LPAC-linearized π-model AC Ohm's law constraints for ACBranch under
LPACCNetworkModel.

Four constraints per branch per time step (p_ft, q_ft, p_tf, q_tf) relate the directional
flow variables to the voltage-magnitude deviations (phi), the bus-pair cosine variable (cs),
and the voltage-angle difference (va_fr - va_to). Transcribed from PowerModels `lpac.jl`
`constraint_ohms_yt_from/to` for `AbstractLPACCNetworkModel`, with `tr = tm·cos(shift)`,
`ti = tm·sin(shift)`.
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{LPACCNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)

    va = get_variable(container, VoltageAngle, PSY.ACBus)
    phi = get_variable(container, VoltageDeviation, PSY.ACBus)
    cs = get_variable(container, CosineApproximation, T)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, branch_names)

    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)
    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        g = adm.g
        b = adm.b
        g_fr = adm.g_fr
        b_fr = adm.b_fr
        g_to = adm.g_to
        b_to = adm.b_to
        tm = adm.tap
        nominal_shift = adm.shift
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        tr = tm * cos(nominal_shift)
        ti = tm * sin(nominal_shift)
        # Coupling coefficients (identical to ACP / PowerModels lpac.jl).
        c_cos_fr = (-g * tr + b * ti) / tm^2
        c_sin_fr = (-b * tr - g * ti) / tm^2
        c_cos_to = (-g * tr - b * ti) / tm^2
        c_sin_to = (-b * tr + g * ti) / tm^2
        gg_fr = (g + g_fr) / tm^2
        bb_fr = (b + b_fr) / tm^2

        for t in time_steps
            phi_fr = phi[from_bus, t]
            phi_to = phi[to_bus, t]
            vad = va[from_bus, t] - va[to_bus, t]
            cs_b = cs[name, t]

            # Shared affine terms reused across the four flow constraints:
            #   cs_sum = cs + phi_fr + phi_to,  dev_* = 1 + 2·phi_*
            cs_sum = cs_b + phi_fr + phi_to
            dev_fr = 1.0 + 2.0 * phi_fr
            dev_to = 1.0 + 2.0 * phi_to

            cons_pft[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] ==
                gg_fr * dev_fr + c_cos_fr * cs_sum + c_sin_fr * vad +
                _slack_term(slacks.p_ft, name, t),
            )
            cons_qft[name, t] = JuMP.@constraint(
                jump_model,
                qft[name, t] ==
                -bb_fr * dev_fr - c_sin_fr * cs_sum + c_cos_fr * vad +
                _slack_term(slacks.q_ft, name, t),
            )
            cons_ptf[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] ==
                (g + g_to) * dev_to + c_cos_to * cs_sum + c_sin_to * (-vad) +
                _slack_term(slacks.p_tf, name, t),
            )
            cons_qtf[name, t] = JuMP.@constraint(
                jump_model,
                qtf[name, t] ==
                -(b + b_to) * dev_to - c_sin_to * cs_sum + c_cos_to * (-vad) +
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

################################## IVRNetworkModel branch constraints ##################

# Compute the per-unit current rating bound for an IVR branch variable.
# c_rating_a = rate_a / vmin  (system-base power / per-unit voltage → per-unit current).
# `nothing` for an unrated branch (PSS/E RATE=0): the current variable stays unbounded.
function _ivr_current_rating(branch::PSY.ACTransmission)
    rate_a = _branch_rating(branch)
    name = _element_name(branch)
    _error_on_zero_rating(rate_a, "IVR: branch $(name)")
    isnothing(rate_a) && return nothing
    vmin = _min_endpoint_voltage_limit(branch)
    vmin <= 0.0 && error(
        "IVR: branch $(name) has non-positive endpoint voltage minimum ($vmin)",
    )
    return rate_a / vmin
end

_ivr_current_rating(branch::PSY.ACTransmission, ::DeviceModel, ::String) =
    _ivr_current_rating(branch)

# Symmetric ±rating box on a freshly created variable. An unrated branch (PSS/E RATE=0) is
# unlimited, so the variable is simply left free.
_set_symmetric_bounds!(::JuMP.VariableRef, ::Nothing) = nothing
function _set_symmetric_bounds!(v::JuMP.VariableRef, rating::Float64)
    JuMP.set_lower_bound(v, -rating)
    JuMP.set_upper_bound(v, rating)
    return nothing
end

# Reduced-arc twin: equivalent rating from PNM (min over a series chain; the
# device-model attribute rule for parallel groups) over the minimum voltage bound
# across every member terminal — the corridor current traverses all of them.
function _ivr_current_rating(
    entry::Union{PNM.BranchesSeries, PNM.AbstractBranchesParallel},
    device_model::DeviceModel,
    entry_name::String,
)
    rate_a = branch_rating(entry, device_model)
    _error_on_zero_rating(rate_a, "IVR: reduced arc $(entry_name)")
    isnothing(rate_a) && return nothing
    vmin = _min_endpoint_voltage_limit(entry)
    vmin <= 0.0 && error(
        "IVR: reduced arc $(entry_name) has a non-positive member voltage minimum ($vmin)",
    )
    return rate_a / vmin
end

function _min_endpoint_voltage_limit(branch::PSY.ACTransmission)
    arc = PSY.get_arc(branch)
    # bus voltage limits are already per-unit
    vmin_fr = PSY.get_voltage_limits(PSY.get_from(arc)).min
    vmin_to = PSY.get_voltage_limits(PSY.get_to(arc)).min
    return min(vmin_fr, vmin_to)
end

# Series segments may themselves be parallel groups; recursion bottoms out at devices.
function _min_endpoint_voltage_limit(
    entry::Union{PNM.BranchesSeries, PNM.AbstractBranchesParallel},
)
    return minimum(_min_endpoint_voltage_limit(member) for member in entry)
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{V},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel,
    network_model::NetworkModel{IVRNetworkModel},
) where {V <: AbstractBranchCurrentVariable, T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    network_reduction = get_network_reduction(network_model)
    # base-name prefix built once (unqualified via nameof) instead of per (name, t)
    var_prefix = "$(nameof(V))_$(nameof(T))"
    if isempty(network_reduction)
        elements = [e for d in devices for e in _branch_elements(d)]
        names = [_element_name(e) for e in elements]
        var = add_variable_container!(container, V, T, names, time_steps)
        for d in elements
            c_rating = _ivr_current_rating(d)
            name = _element_name(d)
            for t in time_steps
                v = JuMP.@variable(
                    jump_model,
                    base_name = "$(var_prefix)_{$(name), $(t)}",
                )
                _set_symmetric_bounds!(v, c_rating)
                var[name, t] = v
            end
        end
        return
    end
    # Reduced case: branch currents are per-reduced-arc quantities like the flows, so all
    # entries of an arc (across branch types) alias one tracker-registered variable, with
    # the current rating derived from the reduction entry's equivalent parameters.
    names = get_branch_argument_variable_axis(network_reduction, devices)
    tracker = get_reduced_branch_tracker(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(network_reduction)
    var = add_variable_container!(container, V, T, names, time_steps)
    for (name, (arc, reduction)) in get_name_to_arc_map_entries(network_reduction, T)
        entry = all_branch_maps_by_type[reduction][T][arc]
        has_entry, tracker_container = search_for_reduced_branch_variable!(tracker, arc, V)
        c_rating = _ivr_current_rating(entry, device_model, name)
        for t in time_steps
            if !has_entry
                v = JuMP.@variable(
                    jump_model,
                    base_name = "$(var_prefix)_$(reduction)_{$(name), $(t)}",
                )
                _set_symmetric_bounds!(v, c_rating)
                tracker_container[t] = v
            end
            var[name, t] = tracker_container[t]
        end
    end
    return
end

"""
Add IVR branch constraints for ACBranch under IVRNetworkModel.

Ten constraints per branch per time step:
  (1-4)  Bilinear power-current linking:
           pft = vr_fr·cr_fr + vi_fr·ci_fr,  qft = vi_fr·cr_fr - vr_fr·ci_fr
           ptf = vr_to·cr_to + vi_to·ci_to,  qtf = vi_to·cr_to - vr_to·ci_to
  (5-6)  KCL at from terminal (linear in cr_fr, ci_fr, csr, csi, vr_fr, vi_fr).
         The from-side shunt terms carry no tm² (PowerModels constraint_current_from
         multiplied through by tm²; only the series/tap terms scale with tm²):
           cr_fr·tm² = tr·csr - ti·csi + g_fr·vr_fr - b_fr·vi_fr
           ci_fr·tm² = tr·csi + ti·csr + g_fr·vi_fr + b_fr·vr_fr
  (7-8)  KCL at to terminal (linear):
           cr_to = -csr + g_to·vr_to - b_to·vi_to
           ci_to = -csi + g_to·vi_to + b_to·vr_to
  (9-10) Ohm's law across series impedance Z = r + jx = 1/(g + jb) (linear):
           vr_to·tm² = vr_fr·tr + vi_fr·ti - r·csr·tm² + x·csi·tm²
           vi_to·tm² = vi_fr·tr - vr_fr·ti - r·csi·tm² - x·csr·tm²
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)

    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)
    cr_fr = get_variable(container, BranchCurrentFromToReal, T)
    ci_fr = get_variable(container, BranchCurrentFromToImaginary, T)
    cr_to = get_variable(container, BranchCurrentToFromReal, T)
    ci_to = get_variable(container, BranchCurrentToFromImaginary, T)
    csr = get_variable(container, BranchSeriesCurrentReal, T)
    csi = get_variable(container, BranchSeriesCurrentImaginary, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]

    cons_pft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_ft",
    )
    cons_qft = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_ft",
    )
    cons_ptf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "p_tf",
    )
    cons_qtf = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "q_tf",
    )
    cons_cr_fr = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "cr_fr",
    )
    cons_ci_fr = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "ci_fr",
    )
    cons_cr_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "cr_to",
    )
    cons_ci_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "ci_to",
    )
    cons_vr_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "vr_to",
    )
    cons_vi_to = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps; meta = "vi_to",
    )

    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)
    cslacks = _current_equality_slacks(container, device_model, T)
    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        g = adm.g
        b = adm.b
        g_fr = adm.g_fr
        b_fr = adm.b_fr
        g_to = adm.g_to
        b_to = adm.b_to
        tm = adm.tap
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name

        tr = tm * cos(adm.shift)
        ti = tm * sin(adm.shift)
        tm2 = tm^2

        # Series impedance Z = r + jx = conj(y)/|y|²
        ymag2 = g^2 + b^2
        r = g / ymag2
        x = -b / ymag2

        for t in time_steps
            vr_f = vr[from_bus, t]
            vi_f = vi[from_bus, t]
            vr_t = vr[to_bus, t]
            vi_t = vi[to_bus, t]
            csr_b = csr[name, t]
            csi_b = csi[name, t]
            cr_f = cr_fr[name, t]
            ci_f = ci_fr[name, t]
            cr_t = cr_to[name, t]
            ci_t = ci_to[name, t]

            # Bilinear power-current linking
            cons_pft[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] ==
                vr_f * cr_f + vi_f * ci_f + _slack_term(slacks.p_ft, name, t),
            )
            cons_qft[name, t] = JuMP.@constraint(
                jump_model,
                qft[name, t] ==
                vi_f * cr_f - vr_f * ci_f + _slack_term(slacks.q_ft, name, t),
            )
            cons_ptf[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] ==
                vr_t * cr_t + vi_t * ci_t + _slack_term(slacks.p_tf, name, t),
            )
            cons_qtf[name, t] = JuMP.@constraint(
                jump_model,
                qtf[name, t] ==
                vi_t * cr_t - vr_t * ci_t + _slack_term(slacks.q_tf, name, t),
            )

            # KCL at from terminal (StaticBranchBounds relaxes each definition with its own
            # metaed ± slack; every other formulation carries a zero term). The shunt terms
            # carry `tm2` because the from-shunt sits OUTSIDE the ideal transformer in PNM's
            # Ybus (`Y11 = y/tm^2 + y_fr`) — see `_pi_flow_coefficients`. In this
            # multiplied-through form that means `y_fr` is scaled by tm², not divided by it.
            cons_cr_fr[name, t] = JuMP.@constraint(
                jump_model,
                cr_f * tm2 ==
                tr * csr_b - ti * csi_b + g_fr * vr_f - b_fr * vi_f +
                _slack_term(cslacks.cr_fr, name, t),
            )
            cons_ci_fr[name, t] = JuMP.@constraint(
                jump_model,
                ci_f * tm2 ==
                tr * csi_b + ti * csr_b + g_fr * vi_f + b_fr * vr_f +
                _slack_term(cslacks.ci_fr, name, t),
            )

            # KCL at to terminal
            cons_cr_to[name, t] = JuMP.@constraint(
                jump_model,
                cr_t ==
                -csr_b + g_to * vr_t - b_to * vi_t +
                _slack_term(cslacks.cr_to, name, t),
            )
            cons_ci_to[name, t] = JuMP.@constraint(
                jump_model,
                ci_t ==
                -csi_b + g_to * vi_t + b_to * vr_t +
                _slack_term(cslacks.ci_to, name, t),
            )

            # Ohm's law across series impedance
            cons_vr_to[name, t] = JuMP.@constraint(
                jump_model,
                vr_t * tm2 ==
                vr_f * tr + vi_f * ti - r * csr_b * tm2 + x * csi_b * tm2,
            )
            cons_vi_to[name, t] = JuMP.@constraint(
                jump_model,
                vi_t * tm2 ==
                vi_f * tr - vr_f * ti - r * csi_b * tm2 - x * csr_b * tm2,
            )
        end
    end
    return
end

"""
Add terminal current-magnitude limit for ACBranch under IVRNetworkModel.

Constrains cr² + ci² ≤ c_rating² for both from- and to-terminal currents, where
c_rating = rate_a / vmin. An unrated branch (PSS/E RATE=0) is unlimited and gets no rows.
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{CurrentLimitConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{IVRNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    entries = _branch_rating_entries(network_model, devices, T, CurrentLimitConstraint)
    ratings = [
        name => _ivr_current_rating(entry, device_model, name)
        for (name, entry) in entries
    ]
    filter!(p -> !isnothing(p.second), ratings)
    rating2 = [name => _rate_rhs_squared(r) for (name, r) in ratings]
    _add_current_magnitude_limits!(
        container, T, rating2, "from",
        get_variable(container, BranchCurrentFromToReal, T),
        get_variable(container, BranchCurrentFromToImaginary, T),
        _current_magnitude_slacks(container, device_model, T, "c_from"),
    )
    _add_current_magnitude_limits!(
        container, T, rating2, "to",
        get_variable(container, BranchCurrentToFromReal, T),
        get_variable(container, BranchCurrentToFromImaginary, T),
        _current_magnitude_slacks(container, device_model, T, "c_to"),
    )
    return
end

"""
Add the `real² + imag² ≤ rating²` current-magnitude limit for one terminal (`meta`),
one constraint per `(name, t)`. `rating2` pairs each branch name to its squared rating.
"""
function _add_current_magnitude_limits!(
    container::OptimizationContainer,
    ::Type{T},
    rating2::AbstractVector,
    meta::String,
    real_var,
    imag_var,
    slack,
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    names = first.(rating2)
    cons = add_constraints_container!(
        container, CurrentLimitConstraint, T, names, time_steps; meta = meta,
    )
    for (name, r2) in rating2
        for t in time_steps
            cons[name, t] = JuMP.@constraint(
                jump_model,
                real_var[name, t]^2 + imag_var[name, t]^2 -
                _upper_slack_term(slack, name, t) <= r2,
            )
        end
    end
    return
end

################################## DCP branch constraints ###################################

"""
Add branch flow rate (rating) constraints for ACBranch under DCPNetworkModel.

This is a simple lb/ub pair on the FlowActivePowerVariable that does not depend on the
PTDF / network-reduction infrastructure used by the AbstractActivePowerModel dispatch.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    flow_vars = get_variable(container, FlowActivePowerVariable, T)
    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end
    jump_model = get_jump_model(container)

    # Gate on the parameter container existing (not just the TS name being set):
    # if the name is configured but no branch of this type carries the series, the
    # container is never created, and an empty `ts_branch_names` then routes every
    # branch through the static-rating path below.
    ts_branch_names = Set{String}()
    local param_container, mult
    if has_container_key(container, BranchRatingTimeSeriesParameter, T)
        param_container =
            get_parameter(container, BranchRatingTimeSeriesParameter, T)
        mult = get_multiplier_array(param_container)
        ts_branch_names = Set(axes(mult, 1))
    end

    network_reduction = get_network_reduction(network_model)
    if !isempty(network_reduction)
        # Reduced case: one lb/ub pair per reduced arc (the flow variables are shared per
        # arc), with the rating from the reduction entry's equivalent parameters. The TS
        # parameter axes are already reduction-entry names.
        entries = _branch_rating_entries(network_model, devices, T, FlowRateConstraint)
        rows = _rate_rows(entries, device_model, ts_branch_names)
        branch_names = [r.name for r in rows]
        con_lb = add_constraints_container!(
            container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
        )
        con_ub = add_constraints_container!(
            container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
        )
        for (name, entry, limits) in rows
            if name in ts_branch_names
                param = get_parameter_column_refs(param_container, name)
                if use_slacks
                    add_parameterized_rating_constraints!(
                        container, con_ub, con_lb, flow_vars, name, param, mult,
                        slack_ub, slack_lb,
                    )
                else
                    add_parameterized_rating_constraints!(
                        container, con_ub, con_lb, flow_vars, name, param, mult,
                    )
                end
            else
                for t in time_steps
                    if use_slacks
                        ub_lhs = flow_vars[name, t] - slack_ub[name, t]
                        lb_lhs = flow_vars[name, t] + slack_lb[name, t]
                    else
                        ub_lhs = flow_vars[name, t]
                        lb_lhs = flow_vars[name, t]
                    end
                    con_ub[name, t] =
                        JuMP.@constraint(jump_model, ub_lhs <= limits.max)
                    con_lb[name, t] =
                        JuMP.@constraint(jump_model, lb_lhs >= limits.min)
                end
            end
        end
        return
    end

    branch_names = [PSY.get_name(d) for d in devices]
    static_devices = [d for d in devices if !(PSY.get_name(d) in ts_branch_names)]
    ts_devices = [d for d in devices if PSY.get_name(d) in ts_branch_names]

    # STATIC rating path: a plain `limits.min <= flow <= limits.max` (slack subtracted on
    # UB, added on LB). Delegated to the generic slack-aware IOM range helper since it is
    # the same lb/ub logic shared across devices. The "lb"/"ub" containers are created over
    # ALL `branch_names` (via `constraint_names`) so the TS path below can fill its share of
    # the same containers; only `static_devices` are constrained here.
    if use_slacks
        add_slacked_range_constraints!(
            container,
            FlowRateConstraint,
            flow_vars,
            static_devices,
            device_model,
            slack_ub,
            slack_lb;
            constraint_names = branch_names,
        )
    else
        add_slacked_range_constraints!(
            container,
            FlowRateConstraint,
            flow_vars,
            static_devices,
            device_model,
            nothing,
            nothing;
            constraint_names = branch_names,
        )
    end

    # TIME-SERIES rating path: the RHS is a parameterized rating (rating_factor * rating)
    # that varies per time step, so it is not covered by the scalar-limit range helper.
    # The static path above already created the "lb"/"ub" containers; fill the TS
    # branches' entries via the shared parameterized-rating builder.
    if !isempty(ts_devices)
        con_lb = get_constraint(container, FlowRateConstraint, T, "lb")
        con_ub = get_constraint(container, FlowRateConstraint, T, "ub")
        for d in ts_devices
            name = PSY.get_name(d)
            param = get_parameter_column_refs(param_container, name)
            if use_slacks
                add_parameterized_rating_constraints!(
                    container, con_ub, con_lb, flow_vars, name, param, mult,
                    slack_ub, slack_lb,
                )
            else
                add_parameterized_rating_constraints!(
                    container, con_ub, con_lb, flow_vars, name, param, mult,
                )
            end
        end
    end
    return
end

"""
Add branch Ohm's law (DC power flow) constraint for ACBranch under DCPNetworkModel:

    p_fr == b_dc * (va_fr - va_to - α)

`b_dc` is the tap-divided DC susceptance (see `_dc_susceptance`) and `α` the equivalent
phase-shift angle (0 for non-shifting branches).
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    p = get_variable(container, FlowActivePowerVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps,
    )

    # StaticBranchBounds relaxes the rating by slacking this defining equality: the bounded
    # decision flow `p` stays within rating while the physical angle-implied flow may deviate
    # by the signed slack. StaticBranch never reaches this method (it carries flow as the
    # BThetaBranchFlow expression); only SBB does, so the slacks exist iff use_slacks.
    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end

    for g in geoms
        b_dc = g.b_dc
        α = g.alpha
        for t in time_steps
            rhs = b_dc * (va[g.from_name, t] - va[g.to_name, t] - α)
            if use_slacks
                rhs += slack_ub[g.name, t] - slack_lb[g.name, t]
            end
            cons[g.name, t] =
                JuMP.@constraint(get_jump_model(container), p[g.name, t] == rhs)
        end
    end
    return
end

"""
Add the B-θ branch-flow expression for ACBranch StaticBranch under DCPNetworkModel:

    BThetaBranchFlow = b_dc * (va_fr - va_to - α)

using the same DC susceptance/shift pair as the variable-based builder above.
Angles are the only decision variables for StaticBranch under DCP — there is no
`FlowActivePowerVariable` and no defining Ohm's-law equality; the flow is carried
directly as this expression. Uses the same `geoms = _branch_geometries(...)` walk
(one geometry per reduced arc, claimed against the `NetworkFlowConstraint` family so
it interoperates with other branch types/formulations sharing an arc) as the
variable-based Ohm's-law builder above. Also wires the expression into the two
terminal `ActivePowerBalance` entries (-1.0 from, +1.0 to), matching the sign
convention `_add_both_terminals_to_nodal!` uses for the flow variable.
"""
function add_expressions!(
    container::OptimizationContainer,
    ::Type{BThetaBranchFlow},
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]

    bfe =
        add_expression_container!(container, BThetaBranchFlow, T, branch_names, time_steps)
    nodal_expr = get_expression(container, ActivePowerBalance, PSY.ACBus)
    jump_model = get_jump_model(container)

    for g in geoms
        b_dc = g.b_dc
        α = g.alpha
        from_name = g.from_name
        to_name = g.to_name
        from_no = g.from_number
        to_no = g.to_number
        for t in time_steps
            flow = JuMP.@expression(
                jump_model,
                b_dc * (va[from_name, t] - va[to_name, t] - α)
            )
            bfe[g.name, t] = flow
            add_proportional_to_jump_expression!(nodal_expr[from_no, t], flow, -1.0)
            add_proportional_to_jump_expression!(nodal_expr[to_no, t], flow, 1.0)
        end
    end
    return
end

"""
Add branch flow rate (rating) inequalities for ACBranch StaticBranch under
DCPNetworkModel, directly on the `BThetaBranchFlow` expression (no defining
equality/variable to bound instead). Unifies the reduced/unreduced axis via
`_branch_rating_entries` (one entry per device when unreduced, one per not-yet-claimed
reduced arc otherwise) and reuses the shared static/parameterized-rating row builders,
mirroring the variable-based `FlowRateConstraint` DCP builder above but targeting the
expression container.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    bfe = get_expression(container, BThetaBranchFlow, T)
    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end
    jump_model = get_jump_model(container)

    ts_branch_names = Set{String}()
    local param_container, mult
    if has_container_key(container, BranchRatingTimeSeriesParameter, T)
        param_container = get_parameter(container, BranchRatingTimeSeriesParameter, T)
        mult = get_multiplier_array(param_container)
        ts_branch_names = Set(axes(mult, 1))
    end

    entries = _branch_rating_entries(network_model, devices, T, FlowRateConstraint)
    rows = _rate_rows(entries, device_model, ts_branch_names)
    branch_names = [r.name for r in rows]
    con_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
    )
    con_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
    )

    for (name, entry, limits) in rows
        if name in ts_branch_names
            param = get_parameter_column_refs(param_container, name)
            if use_slacks
                add_parameterized_rating_constraints!(
                    container, con_ub, con_lb, bfe, name, param, mult, slack_ub, slack_lb,
                )
            else
                add_parameterized_rating_constraints!(
                    container, con_ub, con_lb, bfe, name, param, mult,
                )
            end
        else
            for t in time_steps
                if use_slacks
                    ub_lhs = bfe[name, t] - slack_ub[name, t]
                    lb_lhs = bfe[name, t] + slack_lb[name, t]
                else
                    ub_lhs = bfe[name, t]
                    lb_lhs = bfe[name, t]
                end
                con_ub[name, t] = JuMP.@constraint(jump_model, ub_lhs <= limits.max)
                con_lb[name, t] = JuMP.@constraint(jump_model, lb_lhs >= limits.min)
            end
        end
    end
    return
end

# A branch constrains the angle difference when it carries angle-limit data (only
# Line / MonitoredLine do) narrower than the PSY default ±π window.
_constrains_angle_difference(::PSY.ACTransmission) = false
# angle limits are in radians — no per-unit conversion
_constrains_angle_difference(d::PSY.Line) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_constrains_angle_difference(d::PSY.MonitoredLine) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_is_binding_angle_window(lims) = !(lims.min ≈ -π && lims.max ≈ π)

"""
Add branch angle-difference limit constraints for ACBranch under DCP/ACP/DCPLL/LPACC
network models.

Only branches for which `PSY.get_angle_limits` is defined (currently `PSY.Line` and
`PSY.MonitoredLine`) and that carry non-trivial limits (i.e. not the ±π defaults) receive
a constraint.  Branches where the method is not defined are silently skipped.
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{AngleDifferenceConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    network_model::NetworkModel{
        <:Union{DCPNetworkModel, ACPNetworkModel, DCPLLNetworkModel, LPACCNetworkModel},
    },
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    limited = [d for d in devices if _constrains_angle_difference(d)]
    isempty(limited) && return

    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    number_to_name = _retained_number_to_name(sys, network_model)
    # Angle limits are per-device data, so only direct entries whose device passed the
    # filter receive a constraint; series/parallel equivalents carry no angle limits.
    geoms = _branch_geometries(
        number_to_name, network_model, devices, T, AngleDifferenceConstraint,
    )
    limited_by_name = Dict(PSY.get_name(d) => d for d in limited)
    constrained = [g for g in geoms if g.direct && haskey(limited_by_name, g.name)]

    branch_names = [g.name for g in constrained]
    cons = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps,
    )

    for g in constrained
        # angle limits are in radians — no per-unit conversion
        lims = PSY.get_angle_limits(limited_by_name[g.name])
        for t in time_steps
            cons[g.name, t] = JuMP.@constraint(
                get_jump_model(container),
                lims.min <= va[g.from_name, t] - va[g.to_name, t] <= lims.max,
            )
        end
    end
    return
end

"""
Add branch angle-difference limit constraints for ACBranch under the ACR/IVR
rectangular coordinate formulations.

Uses the cross-product form: for each limited branch with angle limits (angmin, angmax),
  tan(angmin)·vvr ≤ vvi ≤ tan(angmax)·vvr
where vvr = vr_fr·vr_to + vi_fr·vi_to  (≈ vm_fr·vm_to·cos(Δθ))
      vvi = vi_fr·vr_to − vr_fr·vi_to  (≈ vm_fr·vm_to·sin(Δθ))

Matches PowerModels `constraint_voltage_angle_difference` for AbstractIVRModel.
Only branches with non-default, non-±π limits receive a constraint (same filter as the
polar form).
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{AngleDifferenceConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    network_model::NetworkModel{<:Union{ACRNetworkModel, IVRNetworkModel}},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    limited = [d for d in devices if _constrains_angle_difference(d)]
    isempty(limited) && return

    time_steps = get_time_steps(container)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    number_to_name = _retained_number_to_name(sys, network_model)
    # Angle limits are per-device data, so only direct entries whose device passed the
    # filter receive a constraint; series/parallel equivalents carry no angle limits.
    geoms = _branch_geometries(
        number_to_name, network_model, devices, T, AngleDifferenceConstraint,
    )
    limited_by_name = Dict(PSY.get_name(d) => d for d in limited)
    constrained = [g for g in geoms if g.direct && haskey(limited_by_name, g.name)]

    branch_names = [g.name for g in constrained]
    cons_ub = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps; meta = "ub",
    )
    cons_lb = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps; meta = "lb",
    )

    jump_model = get_jump_model(container)
    for g in constrained
        # angle limits are in radians — no per-unit conversion
        lims = PSY.get_angle_limits(limited_by_name[g.name])
        fr = g.from_name
        to = g.to_name
        for t in time_steps
            vvr = vr[fr, t] * vr[to, t] + vi[fr, t] * vi[to, t]
            vvi = vi[fr, t] * vr[to, t] - vr[fr, t] * vi[to, t]
            cons_ub[g.name, t] = JuMP.@constraint(jump_model, vvi <= tan(lims.max) * vvr)
            cons_lb[g.name, t] = JuMP.@constraint(jump_model, vvi >= tan(lims.min) * vvr)
        end
    end
    return
end

"""
Add full π-model AC Ohm's law constraints for ACBranch under ACPNetworkModel.

Four constraints per branch per time step (p_ft, q_ft, p_tf, q_tf) relate the four
directional flow variables to voltage magnitudes and angles via the π-equivalent circuit.
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{ACPNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)

    va = get_variable(container, VoltageAngle, PSY.ACBus)
    vm = get_variable(container, VoltageMagnitude, PSY.ACBus)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, branch_names)
    slacks = _flow_equality_slacks(container, device_model, T)

    jump_model = get_jump_model(container)
    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name
        coef = _pi_flow_coefficients(
            adm.g, adm.b, adm.g_fr, adm.b_fr, adm.g_to, adm.b_to, adm.tap, adm.shift,
        )

        for t in time_steps
            θ = va[from_bus, t] - va[to_bus, t]
            vmf = vm[from_bus, t]
            vmt = vm[to_bus, t]
            _add_acp_flow!(
                jump_model, cons_pft, cons_qft, cons_ptf, cons_qtf, pft, qft, ptf, qtf,
                name, t, vmf, vmt, θ, coef,
                _slack_term(slacks.p_ft, name, t),
                _slack_term(slacks.q_ft, name, t),
                _slack_term(slacks.p_tf, name, t),
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

################################## DCPLLNetworkModel branch constraints #################

# Tighten a flow variable to ±rate without loosening any bound it already carries (a
# MonitoredLine's directional flow vars keep their tighter flow_limits).
function _tighten_flow_bound!(v, rate)
    if JuMP.has_upper_bound(v)
        JuMP.set_upper_bound(v, min(JuMP.upper_bound(v), rate))
    else
        JuMP.set_upper_bound(v, rate)
    end
    if JuMP.has_lower_bound(v)
        JuMP.set_lower_bound(v, max(JuMP.lower_bound(v), -rate))
    else
        JuMP.set_lower_bound(v, -rate)
    end
    return
end

# Bound DCPLL directional active flows by the branch rating (system base). Finite bounds are
# mandatory for QCP performance (Principle 0). A zero rating is a data error. Bounds are
# variable tightening (not one-per-arc constraints), so under an active reduction this
# runs over every reduction entry without claiming constraint-axis arcs; aliased per-arc
# variables tolerate the repeated tightening (all members carry the same equivalent).
function _set_dcpll_flow_bounds!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel,
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        for d in devices, e in _branch_elements(d)
            name = _element_name(e)
            rate = _branch_rating(e)
            _error_on_zero_rating(rate, name)
            # Unrated (PSS/E RATE=0) is unlimited: leave the flow variables unbounded.
            isnothing(rate) && continue
            for t in time_steps
                _tighten_flow_bound!(pft[name, t], rate)
                _tighten_flow_bound!(ptf[name, t], rate)
            end
        end
        return
    end
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(network_reduction)
    for (name, (arc, reduction)) in get_name_to_arc_map_entries(network_reduction, T)
        entry = all_branch_maps_by_type[reduction][T][arc]
        rate = _directional_flow_rating(entry, device_model)
        isnothing(rate) && continue
        for t in time_steps
            _tighten_flow_bound!(pft[name, t], rate)
            _tighten_flow_bound!(ptf[name, t], rate)
        end
    end
    return
end

"""
Slacked flow rate limits for the DCPLL directional active-flow pair.

Built only when `use_slacks = true`: without slacks the rating is enforced as hard
variable bounds (see `_set_dcpll_flow_bounds!`), which keeps the QCP tighter. Both
directions share the branch's slack pair, so exceeding the rating in either direction
is priced once.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowRateConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    if !get_use_slacks(device_model)
        return
    end
    time_steps = get_time_steps(container)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)
    slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
    slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    jump_model = get_jump_model(container)

    entries = _branch_rating_entries(network_model, devices, T, FlowRateConstraint)
    rows = _rate_rows(entries, device_model, String[])
    branch_names = [r.name for r in rows]
    con_ft_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ft_ub",
    )
    con_ft_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ft_lb",
    )
    con_tf_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "tf_ub",
    )
    con_tf_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "tf_lb",
    )

    for (name, _, limits) in rows
        for t in time_steps
            con_ft_ub[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] - slack_ub[name, t] <= limits.max,
            )
            con_ft_lb[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] + slack_lb[name, t] >= limits.min,
            )
            con_tf_ub[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] - slack_ub[name, t] <= limits.max,
            )
            con_tf_lb[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] + slack_lb[name, t] >= limits.min,
            )
        end
    end
    return
end

"""
Add the DC Ohm's law for the from-to directional flow under DCPLLNetworkModel:

    p_fr == -b * (va_fr - va_to - shift)

identical to the DCP law; the to-from flow is determined by the quadratic loss constraint.
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkFlowConstraint)
    branch_names = [g.name for g in geoms]
    cons = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps,
    )

    jump_model = get_jump_model(container)
    for g in geoms
        b_dc = g.b_dc
        α = g.alpha
        for t in time_steps
            cons[g.name, t] = JuMP.@constraint(
                jump_model,
                pft[g.name, t] == b_dc * (va[g.from_name, t] - va[g.to_name, t] - α),
            )
        end
    end
    return
end

"""
Add the DCPLL quadratic line-loss constraint:

    p_fr + p_to >= r * p_fr^2,   r = g / (g^2 + b^2)

The sum of the two directional flows must cover the resistive loss. At the cost-minimizing
optimum this binds, so the to-bus receives p_fr minus the loss. Convex (Ipopt).
"""
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkLossConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{DCPLLNetworkModel},
) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation}
    time_steps = get_time_steps(container)
    pft = get_variable(container, FlowActivePowerFromToVariable, T)
    ptf = get_variable(container, FlowActivePowerToFromVariable, T)

    number_to_name = _retained_number_to_name(sys, network_model)
    geoms =
        _branch_geometries(number_to_name, network_model, devices, T, NetworkLossConstraint)
    branch_names = [g.name for g in geoms]
    cons = add_constraints_container!(
        container, NetworkLossConstraint, T, branch_names, time_steps,
    )

    jump_model = get_jump_model(container)
    for g in geoms
        r = g.adm.g / (g.adm.g^2 + g.adm.b^2)
        for t in time_steps
            cons[g.name, t] = JuMP.@constraint(
                jump_model,
                pft[g.name, t] + ptf[g.name, t] >= r * pft[g.name, t]^2,
            )
        end
    end
    return
end
