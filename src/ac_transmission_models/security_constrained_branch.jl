# MODF security-constrained branch formulation. PC flow is p.u. on system base.

_post_contingency_match(c::SparseAxisArray, target::Tuple) = haskey(c.data, target)
_post_contingency_match(::AbstractArray, ::Tuple) = false

# A container is a reusable shared post-contingency source iff it has entry type
# `T`, belongs to a component type *other* than the outaged `V` (a same-`V`
# container is the one currently being built, not a source), and is keyed by
# `target`.
function _is_shared_post_contingency_source(
    key::OptimizationContainerKey,
    c,
    target::Tuple,
    ::Type{T},
    ::Type{V},
) where {T, V <: PSY.ACTransmission}
    return get_entry_type(key) === T &&
           get_component_type(key) !== V &&
           _post_contingency_match(c, target)
end

# Names of components of type `D` monitored by at least one outage on this
# device model.
function _monitored_component_names(device_model::DeviceModel, ::Type{D}) where {D}
    names = Set{String}()
    for (_, per_type) in get_outages(device_model)
        for (mon_type, mon_names) in per_type
            mon_type <: D || continue
            union!(names, mon_names)
        end
    end
    return names
end

# True when a `PostContingencyBranchRatingTimeSeriesParameter` column exists for
# `name` under `entry_type`.
function _has_post_contingency_rate(
    container::OptimizationContainer,
    entry_type::DataType,
    name::String,
)
    has_container_key(
        container,
        PostContingencyBranchRatingTimeSeriesParameter,
        entry_type,
    ) || return false
    param_container = get_parameter(
        container,
        PostContingencyBranchRatingTimeSeriesParameter,
        entry_type,
    )
    return name in axes(get_multiplier_array(param_container))[1]
end

# The `(parameter column refs, multiplier slice)` for `name`'s post-contingency
# rate limit. Valid only when `_has_post_contingency_rate` is true.
function _post_contingency_rate_columns(
    container::OptimizationContainer,
    entry_type::DataType,
    name::String,
)
    param_container = get_parameter(
        container,
        PostContingencyBranchRatingTimeSeriesParameter,
        entry_type,
    )
    return get_parameter_column_refs(param_container, name),
    get_multiplier_array(param_container)[name, :]
end

# Reactivated post-contingency branch-rating time series parameter, scoped to
# the monitored components only.
function _add_post_contingency_branch_rating_parameter!(
    container::OptimizationContainer,
    device_model::DeviceModel{T},
    devices,
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.ACTransmission}
    monitored = _monitored_component_names(device_model, T)
    monitored_devices = [d for d in devices if PSY.get_name(d) in monitored]
    isempty(monitored_devices) && return
    add_branch_parameters!(
        container,
        PostContingencyBranchRatingTimeSeriesParameter,
        monitored_devices,
        device_model,
        network_model,
    )
    return
end

function _find_shared_post_contingency_expression_source(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    outage_id::String,
    name::String,
    t::Int,
) where {T <: PostContingencyExpressions, V <: PSY.ACTransmission}
    target = (outage_id, name, t)
    for (key, ec) in IOM.get_expressions(container)
        _is_shared_post_contingency_source(key, ec, target, T, V) && return ec
    end
    return
end

"""
Constraint counterpart to `_find_shared_post_contingency_expression_source`.
Returns `(lb_source, ub_source)` SparseAxisArrays in one scan; either slot is
`nothing` when no shared container of that meta exists.
"""
function _find_shared_post_contingency_constraint_sources(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    outage_id::String,
    name::String,
    t::Int,
) where {T <: PostContingencyConstraintType, V <: PSY.ACTransmission}
    target = (outage_id, name, t)
    src_lb = nothing
    src_ub = nothing
    for (key, cc) in get_constraints(container)
        _is_shared_post_contingency_source(key, cc, target, T, V) || continue
        if key.meta == "lb"
            src_lb = cc
        elseif key.meta == "ub"
            src_ub = cc
        end
        !isnothing(src_lb) && !isnothing(src_ub) && break
    end
    return src_lb, src_ub
end

"""
Locate the post-contingency slack variable containers that a shared constraint for
`(outage_id, name, t)` already references, registered by the source DeviceModel under
a component type other than `V`. Returns `(ub_source, lb_source)`; either slot is
`nothing` when the shared constraint was built without that slack (the source model
had `use_slacks = false`). Lets a reusing model alias those refs into its own slack
container so `get_variable`/`has_container_key` stay consistent with the constraints
it reuses, regardless of branch-model build order.
"""
function _find_shared_post_contingency_slack_sources(
    container::OptimizationContainer,
    ::Type{V},
    outage_id::String,
    name::String,
    t::Int,
) where {V <: PSY.ACTransmission}
    target = (outage_id, name, t)
    src_ub = nothing
    src_lb = nothing
    for (key, vc) in IOM.get_variables(container)
        get_component_type(key) === V && continue
        entry = get_entry_type(key)
        if entry === PostContingencyFlowActivePowerSlackUpperBound &&
           haskey(vc.data, target)
            src_ub = vc
        elseif entry === PostContingencyFlowActivePowerSlackLowerBound &&
               haskey(vc.data, target)
            src_lb = vc
        end
        !isnothing(src_ub) && !isnothing(src_lb) && break
    end
    return src_ub, src_lb
end

"""
Fast-path precheck: returns `true` iff any container of entry type `T` exists
under a component type other than `V`.
"""
function _has_other_v_container(
    container_dict,
    ::Type{T},
    ::Type{V},
) where {T, V <: PSY.ACTransmission}
    for key in keys(container_dict)
        get_entry_type(key) === T || continue
        get_component_type(key) === V && continue
        return true
    end
    return false
end

"""
Pre-allocate a `SparseAxisArray` keyed by
`(outage_id::String, monitored_name::String, t::Int)` holding `JuMP.AffExpr`
zeros for every entry produced by `_resolve_monitored_branches`. The pre-fill is
required so the parallel PTDF expression build below cannot race on Dict resize.
"""
function _add_post_contingency_sparse_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    resolved::Vector{Pair{Base.UUID, Vector{RepresentativeBranch}}},
    time_steps::UnitRange{Int},
) where {T <: PostContingencyExpressions, V <: PSY.ACTransmission}
    contents = Dict{Tuple{String, String, Int}, JuMP.AffExpr}()
    for (uuid, reps) in resolved
        outage_id = string(uuid)
        for rep in reps, t in time_steps
            contents[(outage_id, rep.name, t)] = zero(JuMP.AffExpr)
        end
    end
    expr_container = SparseAxisArray(contents)
    IOM._assign_container!(container.expressions, ExpressionKey(T, V), expr_container)
    return expr_container
end

"""
Register an empty `SparseAxisArray` keyed by
`(outage_id::String, monitored_name::String, t::Int)` for the given constraint
type and meta tag.
"""
function _add_post_contingency_sparse_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V};
    meta::String,
) where {T <: ConstraintType, V <: PSY.ACTransmission}
    cons_container =
        SparseAxisArray(Dict{Tuple{String, String, Int}, JuMP.ConstraintRef}())
    IOM._assign_container!(container.constraints, ConstraintKey(T, V, meta), cons_container)
    return cons_container
end

"""
For each outage in `device_model.outages`, resolve every monitored component
(across every monitored type) to the [`RepresentativeBranch`](@ref) of its arc in
the active reduction graph. Duplicate arcs within an outage are collapsed
per-type. Outages sorted by UUID for deterministic axes.
"""
function _resolve_monitored_branches(
    device_model::DeviceModel,
    network_model::NetworkModel,
)
    resolved = Pair{Base.UUID, Vector{RepresentativeBranch}}[]
    for (uuid, per_type) in get_outages(device_model)
        kept = RepresentativeBranch[]
        for (T, names) in per_type
            seen = Set{Tuple{Int, Int}}()
            for name in sort!(collect(names))
                rep = _representative_branch(network_model, T, name)
                isnothing(rep) && error(
                    "Monitored component \"$name\" (type $T) for outage $uuid is " *
                    "absent from both the network-reduction name-to-arc map and the " *
                    "component-to-reduction map. Verify the component exists in the " *
                    "system and is modeled with a security-constrained branch formulation.",
                )
                rep.arc in seen && continue
                push!(seen, rep.arc)
                push!(kept, rep)
            end
        end
        push!(resolved, uuid => kept)
    end
    sort!(resolved; by = first)
    return resolved
end

# Create a single post-contingency relaxation slack for `(outage_id, name, t)`,
# lower-bounded at zero, and penalize it inline at build time. This runs in the
# ModelConstructStage AFTER the branch objective (`add_to_objective_function!`)
# has already executed, so the penalty is registered directly on the invariant
# objective expression here rather than deferred to `objective_function!`. The
# slack inherits the inequality's units (per-unit on the system base).
function _make_post_contingency_slack!(
    container::OptimizationContainer,
    jump_model::JuMP.Model,
    slack_container::SparseAxisArray,
    ::Type{S},
    ::Type{V},
    outage_id::String,
    name::String,
    t::Int,
) where {S <: VariableType, V <: PSY.ACTransmission}
    slack = JuMP.@variable(
        jump_model,
        lower_bound = 0.0,
        base_name = "$(S)_$(V)_{$(outage_id), $(name), $(t)}",
    )
    slack_container[outage_id, name, t] = slack
    add_to_objective_invariant_expression!(
        container,
        slack * CONSTRAINT_VIOLATION_SLACK_COST,
    )
    return slack
end

"""
Add branch post-contingency rate limit constraints for ACBranch considering MODF and Security Constraints
"""
function add_constraints!(
    container::OptimizationContainer,
    cons_type::Type{T},
    device_model::DeviceModel{V, U},
    network_model::NetworkModel{X},
) where {
    T <: PostContingencyFlowRateConstraint,
    V <: PSY.ACTransmission,
    U <: AbstractSecurityConstrainedStaticBranch,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)

    resolved = _resolve_monitored_branches(device_model, network_model)

    con_lb = _add_post_contingency_sparse_constraints!(container, T, V; meta = "lb")
    con_ub = _add_post_contingency_sparse_constraints!(container, T, V; meta = "ub")

    use_slacks = get_use_slacks(device_model)
    # Local relaxation-slack containers keyed by `(outage_id, name, t)`. Built
    # here (not via `add_variables!`) because the post-contingency axes are only
    # known after `_resolve_monitored_branches`; registered after the loop iff used.
    slack_ub = SparseAxisArray(Dict{Tuple{String, String, Int}, JuMP.VariableRef}())
    slack_lb = SparseAxisArray(Dict{Tuple{String, String, Int}, JuMP.VariableRef}())

    expressions = get_expression(container, PostContingencyBranchFlow, V)
    jump_model = get_jump_model(container)

    has_other_v = _has_other_v_container(get_constraints(container), T, V)
    has_pc_rating = haskey(
        get_time_series_names(device_model),
        PostContingencyBranchRatingTimeSeriesParameter,
    )
    for (uuid, reps) in resolved
        outage_id = string(uuid)
        for rep in reps
            name = rep.name
            entry_type = rep.component_type
            if has_other_v
                src_lb, src_ub = _find_shared_post_contingency_constraint_sources(
                    container, T, V, outage_id, name, first(time_steps),
                )
                if !isnothing(src_lb) && !isnothing(src_ub)
                    src_slack_ub, src_slack_lb =
                        _find_shared_post_contingency_slack_sources(
                            container, V, outage_id, name, first(time_steps),
                        )
                    source_has_slacks =
                        !isnothing(src_slack_ub) || !isnothing(src_slack_lb)
                    if source_has_slacks != use_slacks
                        error(
                            "Inconsistent `use_slacks` among security-constrained " *
                            "branch models that share post-contingency constraints " *
                            "for outage $outage_id, monitored component \"$name\": " *
                            "the shared constraints were built " *
                            (source_has_slacks ? "with" : "without") *
                            " slacks, but the `$V` branch model sets " *
                            "`use_slacks = $use_slacks`. Configure `use_slacks` " *
                            "identically across all security-constrained branch " *
                            "`DeviceModel`s whose outage/monitored sets overlap.",
                        )
                    end
                    for t in time_steps
                        con_ub[outage_id, name, t] =
                            src_ub.data[(outage_id, name, t)]
                        con_lb[outage_id, name, t] =
                            src_lb.data[(outage_id, name, t)]
                        isnothing(src_slack_ub) || (
                            slack_ub[outage_id, name, t] =
                                src_slack_ub.data[(outage_id, name, t)]
                        )
                        isnothing(src_slack_lb) || (
                            slack_lb[outage_id, name, t] =
                                src_slack_lb.data[(outage_id, name, t)]
                        )
                    end
                    continue
                end
            end
            if has_pc_rating && _has_post_contingency_rate(container, entry_type, name)
                param, multiplier =
                    _post_contingency_rate_columns(container, entry_type, name)
                for t in time_steps
                    sub = if use_slacks
                        _make_post_contingency_slack!(
                            container, jump_model, slack_ub,
                            PostContingencyFlowActivePowerSlackUpperBound, V,
                            outage_id, name, t,
                        )
                    else
                        0.0
                    end
                    slb = if use_slacks
                        _make_post_contingency_slack!(
                            container, jump_model, slack_lb,
                            PostContingencyFlowActivePowerSlackLowerBound, V,
                            outage_id, name, t,
                        )
                    else
                        0.0
                    end
                    con_ub[outage_id, name, t] = JuMP.@constraint(
                        jump_model,
                        expressions[outage_id, name, t] - sub <=
                        param[t] * multiplier[t],
                    )
                    con_lb[outage_id, name, t] = JuMP.@constraint(
                        jump_model,
                        expressions[outage_id, name, t] + slb >=
                        -1.0 * param[t] * multiplier[t],
                    )
                end
            else
                limits = _emergency_flow_limits(rep)
                for t in time_steps
                    sub = if use_slacks
                        _make_post_contingency_slack!(
                            container, jump_model, slack_ub,
                            PostContingencyFlowActivePowerSlackUpperBound, V,
                            outage_id, name, t,
                        )
                    else
                        0.0
                    end
                    slb = if use_slacks
                        _make_post_contingency_slack!(
                            container, jump_model, slack_lb,
                            PostContingencyFlowActivePowerSlackLowerBound, V,
                            outage_id, name, t,
                        )
                    else
                        0.0
                    end
                    con_ub[outage_id, name, t] = JuMP.@constraint(
                        jump_model,
                        expressions[outage_id, name, t] - sub <= limits.max,
                    )
                    con_lb[outage_id, name, t] = JuMP.@constraint(
                        jump_model,
                        expressions[outage_id, name, t] + slb >= limits.min,
                    )
                end
            end
        end
    end

    if !isempty(slack_ub.data)
        IOM._assign_container!(
            container.variables,
            VariableKey(PostContingencyFlowActivePowerSlackUpperBound, V),
            slack_ub,
        )
    end
    if !isempty(slack_lb.data)
        IOM._assign_container!(
            container.variables,
            VariableKey(PostContingencyFlowActivePowerSlackLowerBound, V),
            slack_lb,
        )
    end
    return
end

function _build_post_contingency_flow_expressions_for_outage(
    time_steps::UnitRange{Int},
    outage_id::String,
    modf_cols::Dict{Tuple{String, Tuple{Int64, Int64}}, Vector{Float64}},
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
    reps::Vector{RepresentativeBranch},
)
    results = Vector{Tuple{String, Vector{JuMP.AffExpr}}}(undef, length(reps))
    for (i, rep) in enumerate(reps)
        _, expressions = _make_flow_expressions!(
            rep.name,
            time_steps,
            modf_cols[(outage_id, rep.arc)],
            nodal_balance_expressions,
            -_dc_shift_injection(rep),
        )
        results[i] = (rep.name, expressions)
    end
    return results
end

"""
Shared MODF post-contingency expression builder: for every monitored arc `m`
and registered outage `k`,

    expr[m, k, t] = Σ_bus MODF[m, k][bus] * nodal_injection_expressions[bus, t]

`nodal_injection_expressions` must hold the per-bus ACTIVE-POWER INJECTIONS in
the same bus order as the MODF columns. On PTDF networks the `ActivePowerBalance`
expression IS the injection vector (flows are not variables there); on DCP it is
recovered from the balance's branch-flow terms (see
[`_dcp_nodal_injection_expressions`](@ref)).
"""
function _add_modf_post_contingency_flow_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    model::DeviceModel{V, F},
    network_model::NetworkModel,
    nodal_injection_expressions::Matrix{JuMP.AffExpr},
) where {
    T <: PostContingencyBranchFlow,
    V <: PSY.ACTransmission,
    F <: AbstractSecurityConstrainedStaticBranch,
}
    time_steps = get_time_steps(container)
    modf_matrix = get_contingency_matrix(network_model)
    registered_contingencies = PNM.get_registered_contingencies(modf_matrix)

    resolved = _resolve_monitored_branches(model, network_model)

    expression_container = _add_post_contingency_sparse_expression!(
        container, T, V, resolved, time_steps,
    )

    fresh_resolved = _copy_existing_post_contingency_expressions!(
        container, T, V, expression_container, resolved, time_steps,
    )
    isempty(fresh_resolved) && return

    # Serial libklu pass: concurrent libklu calls are unsafe (PNM `_LIBKLU_LOCK`).
    # Each (outage, arc) pair is solved at most once.
    modf_cols = Dict{Tuple{String, Tuple{Int64, Int64}}, Vector{Float64}}()
    for (uuid, reps) in fresh_resolved
        outage_spec = registered_contingencies[uuid]
        outage_id = string(uuid)
        for rep in reps
            key = (outage_id, rep.arc)
            haskey(modf_cols, key) && continue
            modf_cols[key] = modf_matrix[rep.arc, outage_spec]
        end
    end

    # Parallel JuMP `AffExpr` build (no libklu): tasks return results, the main
    # thread does the serial writes. The try/catch surfaces the inner exception.
    tasks = map(fresh_resolved) do (uuid, reps)
        outage_id = string(uuid)
        Threads.@spawn try
            _build_post_contingency_flow_expressions_for_outage(
                time_steps,
                outage_id,
                modf_cols,
                nodal_injection_expressions,
                reps,
            )
        catch e
            @error "Post-contingency flow-expression task failed" outage_id =
                outage_id exception = (e, catch_backtrace())
            rethrow()
        end
    end
    for (i, task) in enumerate(tasks)
        (uuid, _) = fresh_resolved[i]
        outage_id = string(uuid)
        for (name, expressions) in fetch(task)
            for t in time_steps
                expression_container[outage_id, name, t] = expressions[t]
            end
        end
    end
    return
end

# On a PTDF network the nodal balance expression holds injections and nothing
# else (branch flows are not variables), so it feeds the MODF product directly.
function add_post_contingency_flow_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    model::DeviceModel{V, F},
    network_model::NetworkModel{N},
) where {
    T <: PostContingencyBranchFlow,
    V <: PSY.ACTransmission,
    F <: AbstractSecurityConstrainedStaticBranch,
    N <: AbstractPTDFNetworkModel,
}
    nodal_injection_expressions =
        get_expression(container, ActivePowerBalance, PSY.ACBus).data
    _add_modf_post_contingency_flow_expressions!(
        container, T, model, network_model, nodal_injection_expressions,
    )
    return
end

# On DCP the balance also carries the branch-flow variables, so the injections
# must be recovered (see `_dcp_nodal_injection_expressions`).
function add_post_contingency_flow_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    model::DeviceModel{V, F},
    network_model::NetworkModel{DCPNetworkModel},
) where {
    T <: PostContingencyBranchFlow,
    V <: PSY.ACTransmission,
    F <: AbstractSecurityConstrainedStaticBranch,
}
    modf_matrix = get_contingency_matrix(network_model)
    nodal_injection_expressions =
        _dcp_nodal_injection_expressions(container, PNM.get_bus_axis(modf_matrix))
    _add_modf_post_contingency_flow_expressions!(
        container, T, model, network_model, nodal_injection_expressions,
    )
    return
end

# Every JuMP variable of every `FlowActivePowerVariable` container registered
# for an AC transmission type. These are exactly the branch-flow terms of the
# DCP nodal balance; every other balance term (device variables, parameters,
# constants, HVDC flows, system slacks) is a nodal injection.
function _collect_ac_branch_flow_variables!(
    ::Set{JuMP.VariableRef},
    ::OptimizationContainerKey,
    ::Any,
)
    return
end

function _collect_ac_branch_flow_variables!(
    flow_variables::Set{JuMP.VariableRef},
    ::VariableKey{FlowActivePowerVariable, <:PSY.ACTransmission},
    variable_container,
)
    for variable in variable_container
        push!(flow_variables, variable)
    end
    return
end

function _ac_branch_flow_variables(container::OptimizationContainer)
    flow_variables = Set{JuMP.VariableRef}()
    for (key, variable_container) in IOM.get_variables(container)
        _collect_ac_branch_flow_variables!(flow_variables, key, variable_container)
    end
    return flow_variables
end

# The branch-flow terms of one balance expression, negated.
function _negated_flow_terms(
    balance_expression::JuMP.AffExpr,
    flow_variables::Set{JuMP.VariableRef},
)
    injection = zero(JuMP.AffExpr)
    for (coefficient, variable) in JuMP.linear_terms(balance_expression)
        variable in flow_variables || continue
        JuMP.add_to_expression!(injection, -coefficient, variable)
    end
    return injection
end

"""
Nodal active-power injection expressions on a DCP network, with rows ordered by
`bus_axis` (the MODF bus axis) so that row `i` multiplies MODF column entry `i`.

The DCP `ActivePowerBalance` cannot be used directly in the MODF product: it
holds the injections PLUS the branch-flow variables and is constrained to zero,
so its MODF-weighted sum is identically vacuous. The nodal balance constraint
enforces `injections[bus] = -flow_terms[bus]` exactly, so the injection is
recovered by keeping only the balance terms whose variables are AC branch
`FlowActivePowerVariable`s and negating them.

The DCP balance bus axis comes from Dict-ordered reduction-map keys, so rows are
resolved through the container's axis lookup by bus number instead of assuming
positional agreement with the MODF axis.
"""
function _dcp_nodal_injection_expressions(
    container::OptimizationContainer,
    bus_axis::Vector{Int},
)
    balance = get_expression(container, ActivePowerBalance, PSY.ACBus)
    n_balance_buses = size(balance.data, 1)
    if length(bus_axis) != n_balance_buses
        error(
            "MODF bus axis has $(length(bus_axis)) buses but the nodal balance " *
            "expression has $(n_balance_buses). The contingency matrix and the " *
            "optimization container were built with different network reductions.",
        )
    end
    flow_variables = _ac_branch_flow_variables(container)
    if isempty(flow_variables)
        error(
            "No `FlowActivePowerVariable` container exists for any AC " *
            "transmission type; the DCP nodal injections cannot be recovered " *
            "from the balance expression. The security-constrained branch " *
            "ArgumentConstructStage must create the flow variables before the " *
            "post-contingency expressions are built.",
        )
    end
    time_steps = get_time_steps(container)
    injections = Matrix{JuMP.AffExpr}(undef, length(bus_axis), length(time_steps))
    for (i, bus_no) in enumerate(bus_axis)
        for t in time_steps
            injections[i, t] = _negated_flow_terms(balance[bus_no, t], flow_variables)
        end
    end
    return injections
end

"""
Pre-pass for the multi-component outage dedup: copy already-built entries into
`expression_container` and return the residual `resolved` shape that still needs
fresh computation. Returns `resolved` unchanged when no other-V container exists.
"""
function _copy_existing_post_contingency_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    expression_container::SparseAxisArray,
    resolved::Vector{Pair{Base.UUID, Vector{RepresentativeBranch}}},
    time_steps::UnitRange{Int},
) where {T <: PostContingencyExpressions, V <: PSY.ACTransmission}
    _has_other_v_container(IOM.get_expressions(container), T, V) || return resolved

    fresh = Pair{Base.UUID, Vector{RepresentativeBranch}}[]
    for (uuid, reps) in resolved
        outage_id = string(uuid)
        unresolved = RepresentativeBranch[]
        for rep in reps
            src_ec = _find_shared_post_contingency_expression_source(
                container, T, V, outage_id, rep.name, first(time_steps),
            )
            if isnothing(src_ec)
                push!(unresolved, rep)
            else
                for t in time_steps
                    expression_container[outage_id, rep.name, t] =
                        src_ec.data[(outage_id, rep.name, t)]
                end
            end
        end
        isempty(unresolved) || push!(fresh, uuid => unresolved)
    end
    return fresh
end

# -----------------------------------------------------
# ------------ construct_device! METHODS --------------
# -----------------------------------------------------

# For DC Power only
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, F},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: PSY.ACTransmission, F <: AbstractSecurityConstrainedStaticBranch}
    devices = get_available_components(device_model, sys)
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, device_model, network_model)
    end

    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end

    if haskey(
        get_time_series_names(device_model),
        PostContingencyBranchRatingTimeSeriesParameter,
    )
        _add_post_contingency_branch_rating_parameter!(
            container,
            device_model,
            devices,
            network_model,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)

    add_expressions!(
        container,
        PTDFBranchFlow,
        devices,
        device_model,
        network_model,
    )

    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{V, F},
    network_model::NetworkModel{X},
) where {
    V <: PSY.ACTransmission,
    F <: AbstractSecurityConstrainedStaticBranch,
    X <: AbstractPTDFNetworkModel,
}
    devices = get_available_components(device_model, sys)

    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, X)

    add_post_contingency_flow_expressions!(
        container,
        PostContingencyBranchFlow,
        device_model,
        network_model,
    )

    add_constraints!(
        container,
        PostContingencyFlowRateConstraint,
        device_model,
        network_model,
    )

    # Must run after the post-contingency constraints are built so their
    # SparseAxisArray dual containers are registered alongside FlowRateConstraint.
    add_constraint_dual!(container, sys, device_model)

    return
end

# DCP mirrors the StaticBranch DCP ArgumentConstructStage (flow variable wired to
# the nodal balance, rating parameters) plus the post-contingency rating
# parameter. No PTDFBranchFlow expression: on DCP the base-case flow is the
# variable itself.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, F},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission, F <: AbstractSecurityConstrainedStaticBranch}
    devices = get_available_components(device_model, sys)
    add_variables!(
        container, FlowActivePowerVariable, devices, device_model, network_model,
    )
    if get_use_slacks(device_model)
        _add_flow_slacks!(container, devices, device_model, network_model)
    end
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        device_model,
        network_model,
    )

    if haskey(get_time_series_names(device_model), BranchRatingTimeSeriesParameter)
        add_branch_parameters!(
            container,
            BranchRatingTimeSeriesParameter,
            devices,
            device_model,
            network_model,
        )
    end

    if haskey(
        get_time_series_names(device_model),
        PostContingencyBranchRatingTimeSeriesParameter,
    )
        _add_post_contingency_branch_rating_parameter!(
            container,
            device_model,
            devices,
            network_model,
        )
    end

    add_feedforward_arguments!(container, device_model, devices)
    return
end

# DCP mirrors the StaticBranch DCP ModelConstructStage (flow limits, DC Ohm's
# law, angle-difference limits) plus the MODF post-contingency machinery.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{V, F},
    network_model::NetworkModel{DCPNetworkModel},
) where {V <: PSY.ACTransmission, F <: AbstractSecurityConstrainedStaticBranch}
    devices = get_available_components(device_model, sys)

    add_constraints!(container, FlowRateConstraint, devices, device_model, network_model)
    add_constraints!(
        container, sys, NetworkFlowConstraint, devices, device_model, network_model,
    )
    add_constraints!(
        container, sys, AngleDifferenceConstraint, devices, device_model, network_model,
    )
    add_feedforward_constraints!(container, device_model, devices)
    add_to_objective_function!(container, devices, device_model, DCPNetworkModel)

    add_post_contingency_flow_expressions!(
        container,
        PostContingencyBranchFlow,
        device_model,
        network_model,
    )

    add_constraints!(
        container,
        PostContingencyFlowRateConstraint,
        device_model,
        network_model,
    )

    # Must run after the post-contingency constraints are built so their
    # SparseAxisArray dual containers are registered alongside FlowRateConstraint.
    add_constraint_dual!(container, sys, device_model)

    return
end

# `SecurityConstrainedStaticBranch` is intentionally inert under network models
# that carry no branch-flow representation: NFA, CopperPlate and AreaBalance
# build nothing rather than erroring (mirrors the StaticBranch no-ops). Defined
# on concrete network types to avoid ambiguity with the PTDF/DCP methods.
# The warning must be user-visible: the user asked for N-1 limits and is
# silently getting none.
function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ArgumentConstructStage,
    ::DeviceModel{T, F},
    ::Union{
        NetworkModel{NFANetworkModel},
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission, F <: AbstractSecurityConstrainedStaticBranch}
    @warn "No argument construction for $F under NFA/CopperPlate/AreaBalance; \
           security-constrained branch limits are inert for these network \
           models and NO post-contingency constraints will be created. Use a \
           PTDF, AreaPTDF or DCP network model to enforce N-1 limits." _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end

function construct_device!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{T, F},
    ::Union{
        NetworkModel{NFANetworkModel},
        NetworkModel{CopperPlateNetworkModel},
        NetworkModel{AreaBalanceNetworkModel},
    },
) where {T <: PSY.ACTransmission, F <: AbstractSecurityConstrainedStaticBranch}
    @warn "No model construction for $F under NFA/CopperPlate/AreaBalance; \
           security-constrained branch limits are inert for these network \
           models and NO post-contingency constraints will be created. Use a \
           PTDF, AreaPTDF or DCP network model to enforce N-1 limits." _group =
        LOG_GROUP_BRANCH_CONSTRUCTIONS
    return
end
