
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

const ENABLE_CONTROLS_KEY = "enable_controls"

_control_attribute(
    ::Union{Type{PSY.TwoWindingTransformer}, Type{PSY.ThreeWindingTransformer}},
) = (ENABLE_CONTROLS_KEY => false,)
_control_attribute(_) = ()

_TRANSFORMERS = Union{PSY.TwoWindingTransformer, PSY.ThreeWindingTransformer}

_control_enabled(m::DeviceModel{<:_TRANSFORMERS}) =
    get_attribute(m, ENABLE_CONTROLS_KEY) === true
_control_enabled(c::PSY.TransformerCircuit) =
    PSY.get_available(c) && !(
        PSY.get_control_objective(c) in
        (PSY.TransformerControlObjective.UNDEFINED, PSY.TransformerControlObjective.FIXED)
    )
_control_enabled(_) = false

_tap_controlled(c::PSY.TransformerControlObjective) = c in (
    PSY.TransformerControlObjective.VOLTAGE,
    PSY.TransformerControlObjective.REACTIVE_POWER_FLOW,
)
_tap_controlled(c::PSY.TransformerCircuit) =
    PSY.get_available(c) && _tap_controlled(PSY.get_control_objective(c))

_voltage_controlled(c::PSY.TransformerControlObjective) =
    c === PSY.TransformerControlObjective.VOLTAGE
_voltage_controlled(c::PSY.TransformerCircuit) =
    PSY.get_available(c) && _voltage_controlled(PSY.get_control_objective(c))

_reactive_controlled(c::PSY.TransformerControlObjective) =
    c === PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
_reactive_controlled(c::PSY.TransformerCircuit) =
    PSY.get_available(c) && _reactive_controlled(PSY.get_control_objective(c))

_tap_controlled(m::DeviceModel, d) = _control_enabled(m) && _tap_controlled(d)
_voltage_controlled(m::DeviceModel, d) = _control_enabled(m) && _voltage_controlled(d)
_reactive_controlled(m::DeviceModel, d) = _control_enabled(m) && _reactive_controlled(d)

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
        _control_attribute(U)...,
    )
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ACTransmission, V <: AbstractSecurityConstrainedStaticBranch}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
        "include_planned_outages" => false,
        _control_attribute(U)...,
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
    net_reduction_data = get_network_reduction(network_model)
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

# Matches the names returned by _branch_geometries
_circuit_arc_name(d::PSY.TwoWindingTransformer, ::PSY.TransformerCircuit, ::Int) =
    PSY.get_name(d)
_circuit_arc_name(d::PSY.ThreeWindingTransformer, c::PSY.TransformerCircuit, i::Int) =
    PNM.get_name(PNM.ThreeWindingTransformerCircuit(d, c, i))

_add_tap_control_variables!(
    ::OptimizationContainer,
    ::DeviceModel,
    ::IS.FlattenIteratorWrapper,
    ::NetworkModel,
) = nothing

_warn_tap_control_nonconvexity(
    ::NetworkModel{N},
) where {N <: Union{LPACCNetworkModel, DCPNetworkModel, DCPLLNetworkModel}} =
    @warn "Tap control makes $N network models non-convex. Use Ipopt or change circuit controls."
_warn_tap_control_nonconvexity(_) = nothing

function _add_tap_control_variables!(
    container::OptimizationContainer,
    model::DeviceModel{U, F},
    devices::IS.FlattenIteratorWrapper{U},
    network_model::NetworkModel,
) where {
    U <: _TRANSFORMERS,
    F <: AbstractBranchFormulation,
}
    get_attribute(model, ENABLE_CONTROLS_KEY) === true || return
    _warn_tap_control_nonconvexity(network_model)

    names = String[]
    circuits = PSY.TransformerCircuit[]
    for d in devices, (i, c) in enumerate(PSY.get_circuits(d))
        _tap_controlled(c) || continue
        push!(names, _circuit_arc_name(d, c, i))
        push!(circuits, c)
    end
    isempty(names) && return
    _validate_controlled_branch_not_reduced(network_model, U, names)

    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    tap_var = add_variable_container!(container, TapRatioVariable, U, names, time_steps)
    for (i, name) in enumerate(names), t in time_steps
        bounds = PSY.get_control_limits(circuits[i])
        tap_var[name, t] = JuMP.@variable(
            jump_model,
            base_name = "TapRatioVariable_$(U)_{$(name), $(t)}",
            lower_bound = bounds.min,
            upper_bound = bounds.max
        )
    end
    return
end

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
        rating_limits = (min = -rating, max = rating)
        for (V, var) in zip(variable_types, variables)
            limits = _directional_flow_limits(V, flow_limits, rating_limits)
            @assert limits.min <= limits.max "Infeasible rate limits for branch $(name)"
            for t in time_steps
                # Variable-creation defaults (MonitoredLine asymmetric limits,
                # TwoWindingTransformer ratings) are authoritative — never clobber
                # an existing bound.
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
this) for new types. The PNM aggregators are system-base (no `PSY.SU`).
"""
function branch_rating(double_circuit::PNM.AbstractBranchesParallel, model::DeviceModel)
    return _get_parallel_branch_max_rating(model, double_circuit)
end

function branch_rating(entry, ::DeviceModel)
    return PNM.get_equivalent_rating(entry)
end

"""
Symmetric `(min, max)` flow limits from [`branch_rating`](@ref). Prefer this
over the formulation-only `get_min_max_limits` when the `DeviceModel` is in
scope.
"""
function min_max_flow_limits(entry, model::DeviceModel)
    rating = branch_rating(entry, model)
    return (min = -rating, max = rating)
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

# Formulation-typed adapter used by the range-constraint framework (e.g.
# `PhaseShiftingTransformer` under `FlowLimitConstraint`) and the
# DCP rate-limit path. `MonitoredLine` overrides this below.
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
    net_reduction_data = get_network_reduction(network_model)
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
    net_reduction_data = get_network_reduction(network_model)
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
    net_reduction_data = get_network_reduction(network_model)
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
    shift_offset::Float64,
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
        JuMP.add_to_expression!(acc, shift_offset)
        expressions[t] = acc
    end
    return name, expressions
end

function _make_flow_expressions!(
    name::String,
    time_steps::UnitRange{Int},
    ptdf_col::SparseArrays.SparseVector{Float64, Int},
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
    shift_offset::Float64,
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
        JuMP.add_to_expression!(acc, shift_offset)
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
    net_reduction_data = get_network_reduction(network_model)
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
                -PNM.arc_dc_shift_injection(net_reduction_data, arc),
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
    net_reduction_data = get_network_reduction(network_model)
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
        return Tuple{String, Any}[(PSY.get_name(d), d) for d in devices]
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

function _validate_controlled_branch_not_reduced(
    network_model::NetworkModel,
    ::Type{T},
    controlled_names,
) where {T <: PSY.ACTransmission}
    network_reduction = get_network_reduction(network_model)
    isempty(network_reduction) && return
    arc_map = get_name_to_arc_map_entries(network_reduction, T)
    for name in controlled_names
        entry = get(arc_map, name, nothing)
        if entry === nothing || entry[2] != "direct_branch_map"
            error(
                "Controlled transformer circuit $(name) was merged with a parallel branch. Either remove the parallel branch or disable control for this circuit.",
            )
        end
    end
    return
end

_is_aggregate(::PNM.AbstractReductionAggregate) = true
_is_aggregate(::PSY.ACTransmission) = false

_branch_admittance(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch, nr)
_branch_admittance(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch)

_dc_phase_shift(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch, nr)
_dc_phase_shift(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch)

_get_circuit(b::_TRANSFORMERS) = PSY.get_circuit(b)
_get_circuit(_) = nothing

_control_objective(branch) = _control_objective(_get_circuit(branch))
_control_objective(::Nothing) = PSY.TransformerControlObjective.UNDEFINED
_control_objective(c::PSY.TransformerCircuit) =
    if PSY.get_available(c)
        PSY.get_control_objective(c)
    else
        PSY.TransformerControlObjective.UNDEFINED
    end

_quantity_limits(branch) = _quantity_limits(_get_circuit(branch))
_quantity_limits(::Nothing) = (min = -Inf, max = Inf)
_quantity_limits(c::PSY.TransformerCircuit) = PSY.get_controlled_quantity_limits(c)

_regulated_number(branch) = _regulated_number(_get_circuit(branch))
_regulated_number(::Nothing) = -1
_regulated_number(c::PSY.TransformerCircuit) = PSY.get_regulated_bus_number(c)

Base.@kwdef struct BranchGeometry
    name::String
    from_name::String
    to_name::String
    from_number::Int
    to_number::Int
    adm::NamedTuple{
        (:g, :b, :g_fr, :b_fr, :g_to, :b_to, :tap, :shift),
        NTuple{8, Float64},
    }
    b_dc::Float64
    shift_dc::Float64
    r_dc::Float64
    direct::Bool
    control::PSY.TransformerControlObjective
    quantity_limits::MinMax
    regulated_number::Int
end

function BranchGeometry(
    nr::PNM.NetworkReductionData,
    number_to_name::Dict{Int, String},
    name::String,
    arc_tuple::Tuple{Int, Int},
    branch,
)
    from_no = arc_tuple[1]
    to_no = arc_tuple[2]
    return BranchGeometry(;
        name = name,
        from_name = number_to_name[from_no],
        to_name = number_to_name[to_no],
        from_number = from_no,
        to_number = to_no,
        adm = _branch_admittance(branch, nr),
        b_dc = PNM.get_series_susceptance(branch, PSY.SU),
        shift_dc = _dc_phase_shift(branch, nr),
        r_dc = PNM.arc_dc_resistance(nr, arc_tuple),
        direct = !_is_aggregate(branch),
        control = _control_objective(branch),
        quantity_limits = _quantity_limits(branch),
        regulated_number = _regulated_number(branch),
    )
end
_tap_controlled(g::BranchGeometry) = _tap_controlled(g.control)
_voltage_controlled(g::BranchGeometry) = _voltage_controlled(g.control)
_reactive_controlled(g::BranchGeometry) = _reactive_controlled(g.control)

"""
One [`BranchGeometry`](@ref) per arc of `T` not yet claimed for the constraint family `C` —
the representative axis from [`get_branch_argument_constraint_axis`](@ref) — with PNM's
reduction-aware equivalent admittance.

Every member of a reduced arc (series segments, parallel groups, across branch types)
shares one set of flow variables, so each arc's physics must be built exactly once;
the tracker-backed axis guarantees that across `construct_device!` calls. Constraint
containers must be sized with the returned geometry names.
"""
function _branch_geometries(
    number_to_name::Dict{Int, String},
    network_model,
    devices,
    ::Type{T},
    ::Type{C},
) where {T <: PSY.ACTransmission, C <: ConstraintType}
    nr = get_network_reduction(network_model)
    tracker = get_reduced_branch_tracker(network_model)
    representative_names = get_branch_argument_constraint_axis(nr, tracker, T, C)
    arc_map = get_name_to_arc_map_entries(nr, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(nr)
    geoms = BranchGeometry[
        BranchGeometry(
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
# Apparent-power rating in system base (PSY.SU) so `rating^2` matches the per-unit flow
# variables. Zero is a data error rather than "unlimited" as in MATPOWER-style data: `p² +
# q² ≤ 0` would silently pin the branch to zero flow, deleting it from the network.
function _directional_flow_rating(d::PSY.ACTransmission, ::DeviceModel)
    rating = _branch_rating(d)
    iszero(rating) && error(
        "Branch $(PSY.get_name(d)) has a zero rating; the flow limit would force zero \
         flow. Assign a non-zero thermal rating or use an unbounded formulation.",
    )
    return rating
end

function _directional_flow_rating(
    entry::PNM.AbstractReductionAggregate,
    device_model::DeviceModel,
)
    rating = branch_rating(entry, device_model)
    iszero(rating) && error(
        "A reduced arc has a zero equivalent rating; the flow limit would force zero \
         flow. Assign non-zero thermal ratings to its member branches.",
    )
    return rating
end

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
    branch_names = [name for (name, _) in entries]
    cons = add_constraints_container!(
        container, ConsKey, T, branch_names, time_steps,
    )
    jump_model = get_jump_model(container)

    ts_branch_names = String[]
    local param_container, mult
    if has_container_key(container, BranchRatingTimeSeriesParameter, T)
        param_container =
            get_parameter(container, BranchRatingTimeSeriesParameter, T)
        mult = get_multiplier_array(param_container)
        ts_branch_names = Set(axes(mult, 1))
    end

    for (name, entry) in entries
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
            rating = _directional_flow_rating(entry, device_model)
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

function _voltage_products(
    container::OptimizationContainer,
    ::NetworkModel{ACPNetworkModel},
    ::Type{<:PSY.ACTransmission},
    ::String,
    from_bus::String,
    to_bus::String,
    t::Int,
)
    jump_model = get_jump_model(container)
    vm = get_variable(container, VoltageMagnitude, PSY.ACBus)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    vmf, vmt = vm[from_bus, t], vm[to_bus, t]
    vaf, vat = va[from_bus, t], va[to_bus, t]
    return (
        v2_fr = JuMP.@expression(jump_model, vmf^2),
        v2_to = JuMP.@expression(jump_model, vmt^2),
        vv_cos = JuMP.@expression(jump_model, vmf * vmt * cos(vaf - vat)),
        vv_sin = JuMP.@expression(jump_model, vmf * vmt * sin(vaf - vat)),
    )
end

function _voltage_products(
    container::OptimizationContainer,
    ::NetworkModel{ACRNetworkModel},
    ::Type{<:PSY.ACTransmission},
    ::String,
    from_bus::String,
    to_bus::String,
    t::Int,
)
    jump_model = get_jump_model(container)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    vr_fr, vr_to = vr[from_bus, t], vr[to_bus, t]
    vi_fr, vi_to = vi[from_bus, t], vi[to_bus, t]
    return (
        v2_fr = JuMP.@expression(jump_model, vr_fr^2 + vi_fr^2),
        v2_to = JuMP.@expression(jump_model, vr_to^2 + vi_to^2),
        vv_cos = JuMP.@expression(jump_model, vr_fr * vr_to + vi_fr * vi_to),
        vv_sin = JuMP.@expression(jump_model, vi_fr * vr_to - vr_fr * vi_to),
    )
end

function _voltage_products(
    container::OptimizationContainer,
    ::NetworkModel{LPACCNetworkModel},
    ::Type{T},
    name::String,
    from_bus::String,
    to_bus::String,
    t::Int,
) where {T <: PSY.ACTransmission}
    jump_model = get_jump_model(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    phi = get_variable(container, VoltageDeviation, PSY.ACBus)
    cs = get_variable(container, CosineApproximation, T)
    phi_fr, phi_to = phi[from_bus, t], phi[to_bus, t]
    return (
        v2_fr = JuMP.@expression(jump_model, 1.0 + 2.0 * phi_fr),
        v2_to = JuMP.@expression(jump_model, 1.0 + 2.0 * phi_to),
        vv_cos = JuMP.@expression(jump_model, cs[name, t] + phi_fr + phi_to),
        vv_sin = JuMP.@expression(jump_model, va[from_bus, t] - va[to_bus, t]),
    )
end

# Ybus terms, supporting Float64 and VariableRef taps. PNM's ybus functions
# use imaginary numbers which VariableRef doesn't support.
function _tapped_admittance(jump_model, adm, tap)
    g_cos, g_sin = adm.g * cos(adm.shift), adm.g * sin(adm.shift)
    b_cos, b_sin = adm.b * cos(adm.shift), adm.b * sin(adm.shift)
    return (
        g11 = JuMP.@expression(jump_model, adm.g / tap^2 + adm.g_fr),
        b11 = JuMP.@expression(jump_model, adm.b / tap^2 + adm.b_fr),
        g12 = JuMP.@expression(jump_model, (-g_cos + b_sin) / tap),
        b12 = JuMP.@expression(jump_model, (-b_cos - g_sin) / tap),
        g21 = JuMP.@expression(jump_model, (-g_cos - b_sin) / tap),
        b21 = JuMP.@expression(jump_model, (g_sin - b_cos) / tap),
        g22 = adm.g + adm.g_to,
        b22 = adm.b + adm.b_to,
    )
end

# Voltage-only AC networks.
function add_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::Type{NetworkFlowConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, U},
    network_model::NetworkModel{N},
) where {
    T <: PSY.ACTransmission,
    U <: AbstractBranchFormulation,
    N <: Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel},
}
    time_steps = get_time_steps(container)

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

        for t in time_steps
            vp = _voltage_products(container, network_model, T, name, from_bus, to_bus, t)
            tap = if _tap_controlled(device_model, g_geom)
                get_variable(container, TapRatioVariable, T)[name, t]
            else
                adm.tap
            end
            y = _tapped_admittance(jump_model, adm, tap)

            cons_pft[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] ==
                y.g11 * vp.v2_fr + y.g12 * vp.vv_cos + y.b12 * vp.vv_sin +
                _slack_term(slacks.p_ft, name, t)
            )
            cons_ptf[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] ==
                y.g22 * vp.v2_to + y.g21 * vp.vv_cos - y.b21 * vp.vv_sin +
                _slack_term(slacks.p_tf, name, t),
            )
            cons_qft[name, t] = JuMP.@constraint(
                jump_model,
                qft[name, t] ==
                -y.b11 * vp.v2_fr - y.b12 * vp.vv_cos + y.g12 * vp.vv_sin +
                _slack_term(slacks.q_ft, name, t),
            )
            cons_qtf[name, t] = JuMP.@constraint(
                jump_model,
                qtf[name, t] ==
                -y.b22 * vp.v2_to - y.b21 * vp.vv_cos - y.g21 * vp.vv_sin +
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

_voltage_magnitude(container, name, ::NetworkModel{ACPNetworkModel}) =
    get_variable(container, VoltageMagnitude, PSY.ACBus)[name, :]
_voltage_magnitude(
    container,
    name,
    ::NetworkModel{<:Union{ACRNetworkModel, IVRNetworkModel}},
) =
    JuMP.@expression(
        get_jump_model(container),
        [t in get_time_steps(container)],
        get_variable(container, VoltageReal, PSY.ACBus)[name, t]^2 +
        get_variable(container, VoltageImaginary, PSY.ACBus)[name, t]^2
    )
_voltage_magnitude(container, name, ::NetworkModel{LPACCNetworkModel}) =
    get_variable(container, VoltageDeviation, PSY.ACBus)[name, :]

_voltage_limits(limits, ::NetworkModel{ACPNetworkModel}) = limits
_voltage_limits(limits, ::NetworkModel{<:Union{ACRNetworkModel, IVRNetworkModel}}) =
    (min = limits.min^2, max = limits.max^2)
_voltage_limits(limits, ::NetworkModel{LPACCNetworkModel}) =
    (min = limits.min - 1, max = limits.max - 1)

function _add_voltage_control_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T},
    network_model::NetworkModel{<:NativeACNetworkModel},
) where {T <: _TRANSFORMERS}
    _control_enabled(device_model) || return

    cons = add_constraints_container!(
        container,
        VoltageMagnitudeConstraint,
        T,
        String[],
        Int[],
        Int[];
        sparse = true,
    )

    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    for d in devices
        for (i, circuit) in enumerate(PSY.get_circuits(d))
            _voltage_controlled(device_model, circuit) || continue

            bus = PSY.get_bus(sys, PSY.get_regulated_bus_number(circuit))
            bus_name = PSY.get_name(bus)
            bus_limits = PSY.get_voltage_limits(bus)
            ctl_limits = PSY.get_controlled_quantity_limits(circuit)
            # TODO: temporary pending PSY#1755
            circuit_name = _circuit_arc_name(d, circuit, i)
            (bus_limits.min <= ctl_limits.min <= ctl_limits.max <= bus_limits.max) || error(
                "Bus limits for $bus_name disagree with control limits for circuit $circuit_name.",
            )

            lims = _voltage_limits(ctl_limits, network_model)
            vm = _voltage_magnitude(container, bus_name, network_model)
            for t in time_steps
                cons[circuit_name, 1, t] = JuMP.@constraint(jump_model, vm[t] >= lims.min)
                cons[circuit_name, 2, t] = JuMP.@constraint(jump_model, vm[t] <= lims.max)
            end
        end
    end
    return
end

_add_voltage_control_constraints!(
    ::OptimizationContainer,
    ::PSY.System,
    ::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T},
    ::NetworkModel,
) where {T} = nothing

function _add_reactive_control_constraints!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T},
    ::NetworkModel{<:NativeACNetworkModel},
) where {T <: _TRANSFORMERS}
    _control_enabled(device_model) || return

    cons = add_constraints_container!(
        container,
        ReactivePowerFlowControlConstraint,
        T,
        String[],
        Int[],
        Int[];
        sparse = true,
    )
    qft = get_variable(container, FlowReactivePowerFromToVariable, T)
    qtf = get_variable(container, FlowReactivePowerToFromVariable, T)

    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    for d in devices
        for (i, circuit) in enumerate(PSY.get_circuits(d))
            _reactive_controlled(device_model, circuit) || continue
            name = _circuit_arc_name(d, circuit, i)
            lims = PSY.get_controlled_quantity_limits(circuit)

            for t in time_steps
                cons[name, 1, t] =
                    JuMP.@constraint(jump_model, qft[name, t] >= lims.min)
                cons[name, 2, t] =
                    JuMP.@constraint(jump_model, qft[name, t] <= lims.max)
                cons[name, 3, t] =
                    JuMP.@constraint(jump_model, qtf[name, t] >= lims.min)
                cons[name, 4, t] =
                    JuMP.@constraint(jump_model, qtf[name, t] <= lims.max)
            end
        end
    end
    return
end

_add_reactive_control_constraints!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T},
    ::NetworkModel,
) where {T} = nothing

function _add_transformer_control_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T},
    network_model::NetworkModel,
) where {T <: PSY.ACTransmission}
    _add_voltage_control_constraints!(container, sys, devices, device_model, network_model)
    _add_reactive_control_constraints!(container, devices, device_model, network_model)
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
        names = [PSY.get_name(d) for d in devices]
        var = add_variable_container!(container, CosineApproximation, T, names, time_steps)
        for d in devices
            name = PSY.get_name(d)
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
    device_by_name = Dict(PSY.get_name(d) => d for d in devices)
    # Angle limits are per-device data: a direct entry reads its own device; a PNM
    # series/parallel equivalent has none and uses the same ±π/2 default as devices
    # without the angle-limits API. Zero-width limits produce no constraint, so the
    # container is sized on the constrained subset only.
    constrained = [(g, _entry_angle_limits(g, device_by_name)) for g in geoms]
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
function _entry_angle_limits(geometry, device_by_name::Dict{String, <:PSY.ACTransmission})
    if geometry.direct
        return _lpacc_branch_angle_limits(device_by_name[geometry.name])
    end
    return (min = -π / 2, max = π / 2)
end

################################## IVRNetworkModel branch constraints ##################

_branch_arc(d::PSY.ACTransmission) = PSY.get_arc(d)
_branch_arc(d::PSY.TwoWindingTransformer) = PSY.get_arc(PSY.get_circuit(d))

function _min_endpoint_voltage_limit(branch::PSY.ACTransmission)
    arc = _branch_arc(branch)
    # bus voltage limits are already per-unit
    vmin_fr = PSY.get_voltage_limits(PSY.get_from(arc)).min
    vmin_to = PSY.get_voltage_limits(PSY.get_to(arc)).min
    return min(vmin_fr, vmin_to)
end

# Series segments may themselves be parallel groups; recursion bottoms out at devices.
function _min_endpoint_voltage_limit(entry::PNM.AbstractReductionAggregate)
    return minimum(_min_endpoint_voltage_limit(member) for member in entry)
end

# Compute the per-unit current rating bound for an IVR branch variable.
# c_rating_a = rate_a / vmin  (system-base power / per-unit voltage → per-unit current).
function _ivr_current_rating(branch::PSY.ACTransmission)
    rate_a = _branch_rating(branch)
    iszero(rate_a) && error(
        "IVR: branch $(PSY.get_name(branch)) has zero rating — assign a non-zero thermal rating",
    )
    vmin = _min_endpoint_voltage_limit(branch)
    vmin <= 0.0 && error(
        "IVR: branch $(PSY.get_name(branch)) has non-positive endpoint voltage minimum ($vmin)",
    )
    return rate_a / vmin
end

_ivr_current_rating(branch::PSY.ACTransmission, ::DeviceModel, ::String) =
    _ivr_current_rating(branch)

# Reduced-arc twin: equivalent rating from PNM (min over a series chain; the
# device-model attribute rule for parallel groups) over the minimum voltage bound
# across every member terminal — the corridor current traverses all of them.
function _ivr_current_rating(
    entry::Union{PNM.BranchesSeries, PNM.AbstractBranchesParallel},
    device_model::DeviceModel,
    entry_name::String,
)
    rate_a = branch_rating(entry, device_model)
    iszero(rate_a) && error(
        "IVR: reduced arc $(entry_name) has zero equivalent rating — assign non-zero \
         thermal ratings to its member branches",
    )
    vmin = _min_endpoint_voltage_limit(entry)
    vmin <= 0.0 && error(
        "IVR: reduced arc $(entry_name) has a non-positive member voltage minimum ($vmin)",
    )
    return rate_a / vmin
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
        names = [PSY.get_name(d) for d in devices]
        var = add_variable_container!(container, V, T, names, time_steps)
        for d in devices
            c_rating = _ivr_current_rating(d)
            name = PSY.get_name(d)
            for t in time_steps
                var[name, t] = JuMP.@variable(
                    jump_model,
                    base_name = "$(var_prefix)_{$(name), $(t)}",
                    lower_bound = -c_rating,
                    upper_bound = c_rating,
                )
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
                tracker_container[t] = JuMP.@variable(
                    jump_model,
                    base_name = "$(var_prefix)_$(reduction)_{$(name), $(t)}",
                    lower_bound = -c_rating,
                    upper_bound = c_rating,
                )
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
         Multiplied through by tm² to stay polynomial. The magnetizing shunt hangs off
         the bus side of the ideal transformer, so it is not referred through the turns
         ratio and keeps its tm² factor here:
           cr_fr·tm² = tr·csr - ti·csi + (g_fr·vr_fr - b_fr·vi_fr)·tm²
           ci_fr·tm² = tr·csi + ti·csr + (g_fr·vi_fr + b_fr·vr_fr)·tm²
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
    tap_var =
        if has_container_key(container, TapRatioVariable, T)
            get_variable(container, TapRatioVariable, T)
        else
            nothing
        end
    for g_geom in geoms
        name = g_geom.name
        adm = g_geom.adm
        g = adm.g
        b = adm.b
        g_fr = adm.g_fr
        b_fr = adm.b_fr
        g_to = adm.g_to
        b_to = adm.b_to
        from_bus = g_geom.from_name
        to_bus = g_geom.to_name

        # Series impedance Z = r + jx = conj(y)/|y|²
        ymag2 = g^2 + b^2
        r = g / ymag2
        x = -b / ymag2

        for t in time_steps
            tm = _tap_controlled(device_model, g_geom) ? tap_var[name, t] : adm.tap
            tr = tm * cos(adm.shift)
            ti = tm * sin(adm.shift)
            tm2 = tm^2

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
            # metaed ± slack; every other formulation carries a zero term)
            cons_cr_fr[name, t] = JuMP.@constraint(
                jump_model,
                cr_f * tm2 ==
                tr * csr_b - ti * csi_b + (g_fr * vr_f - b_fr * vi_f) * tm2 +
                _slack_term(cslacks.cr_fr, name, t),
            )
            cons_ci_fr[name, t] = JuMP.@constraint(
                jump_model,
                ci_f * tm2 ==
                tr * csi_b + ti * csr_b + (g_fr * vi_f + b_fr * vr_f) * tm2 +
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
c_rating = rate_a / vmin (Principle 0: always finite).
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
    rating2 = [
        name => _rate_rhs_squared(_ivr_current_rating(entry, device_model, name)) for
        (name, entry) in entries
    ]
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
        branch_names = [name for (name, _) in entries]
        con_lb = add_constraints_container!(
            container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
        )
        con_ub = add_constraints_container!(
            container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
        )
        for (name, entry) in entries
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
                limits = min_max_flow_limits(entry, device_model)
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

    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end

    jump_model = get_jump_model(container)
    tap_var =
        if has_container_key(container, TapRatioVariable, T)
            get_variable(container, TapRatioVariable, T)
        else
            nothing
        end

    for g in geoms, t in time_steps
        angle = va[g.from_name, t] - va[g.to_name, t] - g.shift_dc
        flow =
            if use_slacks
                JuMP.@expression(
                    jump_model,
                    p[g.name, t] - slack_ub[g.name, t] + slack_lb[g.name, t]
                )
            else
                p[g.name, t]
            end
        cons[g.name, t] =
            if _tap_controlled(device_model, g)
                JuMP.@constraint(
                    jump_model,
                    flow * tap_var[g.name, t] == g.b_dc * g.adm.tap * angle
                )
            else
                JuMP.@constraint(jump_model, flow == g.b_dc * angle)
            end
    end
    return
end

"""
Add the B-θ branch-flow expression for ACBranch StaticBranch under DCPNetworkModel:

    BThetaBranchFlow = b * (va_fr - va_to - shift)

with the DC `b`/`shift` pair described on the `NetworkFlowConstraint` builder above, so the
`b·shift` offset matches PNM's `arc_dc_shift_injection`.

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
        b = g.b_dc
        shift = g.shift_dc
        from_name = g.from_name
        to_name = g.to_name
        from_no = g.from_number
        to_no = g.to_number
        for t in time_steps
            flow = JuMP.@expression(
                jump_model,
                b * (va[from_name, t] - va[to_name, t] - shift)
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
    branch_names = [name for (name, _) in entries]
    con_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
    )
    con_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
    )

    for (name, entry) in entries
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
            limits = min_max_flow_limits(entry, device_model)
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
        for d in devices
            name = PSY.get_name(d)
            rate = _branch_rating(d)
            iszero(rate) &&
                error("Branch $name has a zero rating; cannot bound DCPLL flows.")
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
    branch_names = [name for (name, _) in entries]
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

    for (name, entry) in entries
        limits = min_max_flow_limits(entry, device_model)
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
    tap_var =
        if has_container_key(container, TapRatioVariable, T)
            get_variable(container, TapRatioVariable, T)
        else
            nothing
        end

    for g in geoms, t in time_steps
        angle = va[g.from_name, t] - va[g.to_name, t] - g.shift_dc
        cons[g.name, t] =
            if _tap_controlled(device_model, g)
                JuMP.@constraint(
                    jump_model,
                    pft[g.name, t] * tap_var[g.name, t] == g.b_dc * g.adm.tap * angle
                )
            else
                JuMP.@constraint(jump_model, pft[g.name, t] == g.b_dc * angle)
            end
    end
    return
end

"""
Add the DCPLL quadratic line-loss constraint:

    p_fr + p_to >= r * p_fr^2

The sum of the two directional flows must cover the resistive loss. At the cost-minimizing
optimum this binds, so the to-bus receives p_fr minus the loss. Convex (Ipopt). `r` is the
DC equivalent series resistance from `PNM.arc_dc_resistance`.
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
        r = g.r_dc
        for t in time_steps
            cons[g.name, t] = JuMP.@constraint(
                jump_model,
                pft[g.name, t] + ptf[g.name, t] >= r * pft[g.name, t]^2,
            )
        end
    end
    return
end
