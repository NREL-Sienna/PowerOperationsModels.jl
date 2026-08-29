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


get_initial_conditions_device_model(::IOM.AbstractOptimizationModel, ::DeviceModel{T, U}) where {T <: PSY.ACTransmission, U <: AbstractBranchFormulation} = DeviceModel(T, U)

#### Properties of slack variables
get_variable_binary(::Type{FlowActivePowerSlackUpperBound}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{FlowActivePowerSlackLowerBound}, ::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_upper_bound(::Type{FlowActivePowerSlackUpperBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerSlackUpperBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 0.0
get_variable_upper_bound(::Type{FlowActivePowerSlackLowerBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = nothing
get_variable_lower_bound(::Type{FlowActivePowerSlackLowerBound}, ::PSY.ACTransmission, ::Type{<:AbstractBranchFormulation}) = 0.0

get_variable_upper_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = PSY.get_flow_limits(d, PSY.SU).from_to
get_variable_lower_bound(::Type{FlowActivePowerFromToVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = -1 * PSY.get_flow_limits(d, PSY.SU).from_to
get_variable_upper_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = PSY.get_flow_limits(d, PSY.SU).to_from
get_variable_lower_bound(::Type{FlowActivePowerToFromVariable}, d::PSY.MonitoredLine, ::Type{<:AbstractBranchFormulation}) = -1 * PSY.get_flow_limits(d, PSY.SU).to_from

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

_control_attribute(::Type{<:_TRANSFORMERS}, ::Type{<:_CONTROL_FORMULATIONS}) =
    (ENABLE_CONTROLS_KEY => false,)
_control_attribute(::Type{<:PSY.ACTransmission}, ::Type{<:AbstractBranchFormulation}) = ()

_control_enabled(m::DeviceModel{<:_TRANSFORMERS, <:_CONTROL_FORMULATIONS}) =
    get_attribute(m, ENABLE_CONTROLS_KEY) === true
_control_enabled(::DeviceModel) = false

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
        _control_attribute(U, V)...,
    )
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ACTransmission, V <: AbstractSecurityConstrainedStaticBranch}
    return Dict{String, Any}(
        PARALLEL_BRANCH_MAX_RATING_KEY => "single_element_contingency",
        "include_planned_outages" => false,
        _control_attribute(U, V)...,
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

#################################### Flow Variable Bounds ##################################################

const _CONTROL_VARS = Union{Type{TapRatioVariable}, Type{PhaseShifterAngle}}

# If this a control variable, controls must be enabled (early stop).
_control_var_enabled(::_CONTROL_VARS, d::DeviceModel) = _control_enabled(d)
_control_var_enabled(::Type{<:VariableType}, ::DeviceModel) = true

# Does this branch use this control variable?
_branch_uses_control(
    ::Type{TapRatioVariable},
    branch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _tap_controlled(branch, device_model, network_model)
_branch_uses_control(
    ::Type{PhaseShifterAngle},
    branch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _phase_controlled(branch, device_model, network_model)

_warn_tap_nonconvex(::Type{TapRatioVariable}, ::NetworkModel{LPACCNetworkModel}, branches) =
    isempty(branches) ||
    @warn "Tap control makes LPAC network models non-convex. Use Ipopt or change circuit controls."
_warn_tap_nonconvex(::Type{<:VariableType}, ::NetworkModel, _) = nothing

# If this is a control variable, only get branches with that control active.
function _branches_for_var(
    V::_CONTROL_VARS,
    device_model::DeviceModel{T},
    network_model::NetworkModel,
) where {T}
    members = RepresentativeBranch[]
    _foreach_branch(_all_branches(network_model, T)) do branch
        if branch.reduction !== DIRECT_BRANCH_MAP
            names = _controlled_circuit_names(branch, device_model)
            isempty(names) && return
            error(
                "Controlled transformer circuit $(join(names, ", ")) was merged into the \
                 reduced arc $(branch.name) ($(branch.reduction)). Either remove the parallel \
                 branch or disable control for this circuit.",
            )
        end
        _branch_uses_control(V, branch, device_model, network_model) || return
        push!(members, branch)
    end
    _warn_tap_nonconvex(V, network_model, members)
    return members
end
_branches_for_var(
    ::Type{<:VariableType},
    ::DeviceModel{T},
    network_model::NetworkModel,
) where {T} = _all_branches(network_model, T)

_branch_variable_bounds(
    ::Type{V},
    rep::RepresentativeBranch,
    ::DeviceModel{D, F},
    ::NetworkModel,
) where {V, D <: PSY.ACTransmission, F <: AbstractBranchFormulation} =
    (
        get_variable_lower_bound(V, rep.branch, F),
        get_variable_upper_bound(V, rep.branch, F),
    )

function _branch_variable_bounds(
    ::Type{CosineApproximation},
    rep::RepresentativeBranch,
    ::DeviceModel{<:PSY.ACTransmission, <:AbstractBranchFormulation},
    ::NetworkModel,
)
    lims = _angle_limits(rep)
    if lims.min >= 0
        return (cos(lims.max), cos(lims.min))
    elseif lims.max <= 0
        return (cos(lims.min), cos(lims.max))
    else
        return (min(cos(lims.min), cos(lims.max)), 1.0)
    end
end

_branch_variable_bounds(
    ::_CONTROL_VARS,
    rep::RepresentativeBranch,
    ::DeviceModel{<:PSY.ACTransmission, <:AbstractBranchFormulation},
    ::NetworkModel,
) = _control_limits(rep)

function _branch_variable_bounds(
    ::Type{<:AbstractBranchCurrentVariable},
    rep::RepresentativeBranch,
    device_model::DeviceModel{<:PSY.ACTransmission, <:AbstractBranchFormulation},
    ::NetworkModel,
)
    rating = _current_rating(rep, device_model)
    return (-rating, rating)
end

_static_branch_rate_limits(
    ::Type{<:AbstractACActivePowerFlow},
    rep::RepresentativeBranch,
    device_model::DeviceModel,
) =
    _flow_limits(rep, device_model)

function _static_branch_rate_limits(
    ::Type{<:AbstractACReactivePowerFlow},
    rep::RepresentativeBranch,
    device_model::DeviceModel,
)
    rating = _branch_rating(rep, device_model)
    return (min = -rating, max = rating)
end

_is_slack(
    ::Union{Type{FlowActivePowerSlackLowerBound}, Type{FlowActivePowerSlackUpperBound}},
) = true
_is_slack(::Type{<:VariableType}) = false

function _branch_variable_bounds(
    ::Type{V},
    rep::RepresentativeBranch,
    device_model::DeviceModel{D, StaticBranchBounds},
    ::NetworkModel,
) where {
    V <: Union{AbstractACActivePowerFlow, AbstractACReactivePowerFlow},
    D <: PSY.ACTransmission,
}
    _is_slack(V) && return (0.0, nothing)
    limits = _static_branch_rate_limits(V, rep, device_model)
    @assert limits.min <= limits.max "Infeasible rate limits for branch $(rep.name)"
    return (
        something(get_variable_lower_bound(V, rep.branch, StaticBranchBounds), limits.min),
        something(get_variable_upper_bound(V, rep.branch, StaticBranchBounds), limits.max),
    )
end

# DCPLL rates its directional pair with `FlowRateConstraint` rows against the loss-coupled
# flows, so the rating must not also land on the variables.
_branch_variable_bounds(
    ::Type{V},
    rep::RepresentativeBranch,
    ::DeviceModel{D, StaticBranchBounds},
    ::NetworkModel{DCPLLNetworkModel},
) where {V <: AbstractACActivePowerFlow, D <: PSY.ACTransmission} = (
    get_variable_lower_bound(V, rep.branch, StaticBranchBounds),
    get_variable_upper_bound(V, rep.branch, StaticBranchBounds),
)

_branch_variable_start(::Type{CosineApproximation}) = 1.0
_branch_variable_start(::Type{TapRatioVariable}) = 1.0
_branch_variable_start(::Type{PhaseShifterAngle}) = 0.0
_branch_variable_start(::Type{<:VariableType}) = nothing

"""
Branch variables for reduction-aware networks. Every entry of a reduced arc
aliases the same underlying JuMP variable.
"""
function add_variables!(
    container::OptimizationContainer,
    ::Type{V},
    ::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, F},
    network_model::NetworkModel{
        <:Union{AbstractPTDFNetworkModel, NativeNodalNetworkModel},
    },
) where {V <: VariableType, T <: PSY.ACTransmission, F <: AbstractBranchFormulation}
    _control_var_enabled(V, device_model) || return
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    start = _branch_variable_start(V)

    branches = _branches_for_var(V, device_model, network_model)
    variable_container = add_variable_container!(
        container,
        V,
        T,
        _branch_names(branches),
        time_steps,
    )

    _foreach_branch(branches) do branch
        has_entry, tracker_container = search_for_reduced_branch_variable!(
            reduced_branch_tracker,
            branch.arc,
            V,
        )
        if !has_entry
            (lb, ub) = _branch_variable_bounds(V, branch, device_model, network_model)
            for t in time_steps
                var = JuMP.@variable(
                    jump_model,
                    base_name = "$(nameof(V))_$(nameof(T))_$(branch.reduction)_{$(branch.name), $(t)}",
                )
                lb !== nothing && JuMP.set_lower_bound(var, lb)
                ub !== nothing && JuMP.set_upper_bound(var, ub)
                start !== nothing && JuMP.set_start_value(var, start)
                tracker_container[t] = var
            end
        end
        for t in time_steps
            variable_container[branch.name, t] = tracker_container[t]
        end
    end
    return
end

_add_transformer_control_variables!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel{<:_TAP_NETWORKS}
) where {T <: _TRANSFORMERS} = add_variables!(container, TapRatioVariable, devices, device_model, network_model)

_add_transformer_control_variables!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel{<:_PHASE_NETWORKS}
) where {T <: _TRANSFORMERS} = add_variables!(container, PhaseShifterAngle, devices, device_model, network_model)

_add_transformer_control_variables!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper,
    ::DeviceModel,
    ::NetworkModel,
) = nothing

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

################################## Rate Limits constraint_infos ############################

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
           `$PARALLEL_BRANCH_MAX_RATING_KEY` attribute." maxlog = 5
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

function _add_flow_rate_constraint!(
    container::OptimizationContainer,
    rep::RepresentativeBranch,
    use_slacks::Bool,
    con_lb::DenseAxisArray,
    con_ub::DenseAxisArray,
    var::DenseAxisArray,
    device_model::DeviceModel{T},
) where {T <: PSY.ACTransmission}
    name = rep.name
    time_steps = get_time_steps(container)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)[name, :]
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)[name, :]
    end
    limits = _flow_limits(rep, device_model)
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
    reps = _representative_branches(network_model, T, cons_type)
    branch_names = _branch_names(reps)

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
    _foreach_branch(reps) do rep
        _add_flow_rate_constraint!(
            container,
            rep,
            use_slacks,
            con_lb,
            con_ub,
            array,
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
    reps = _representative_branches(network_model, T, cons_type)
    branch_names = _branch_names(reps)

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
    _foreach_branch(reps) do rep
        _add_flow_rate_constraint!(
            container,
            rep,
            use_slacks,
            con_lb,
            con_ub,
            array,
            device_model,
        )
    end
    return
end

function _add_flow_rate_constraint_with_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    use_slacks::Bool,
    con_lb::DenseAxisArray,
    con_ub::DenseAxisArray,
    var::DenseAxisArray,
    name::String,
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
    reps = _representative_branches(network_model, T, cons_type)
    branch_names = _branch_names(reps)

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
    _foreach_branch(reps) do rep
        if PNM.has_time_series(rep.branch, ts_type, ts_name)
            _add_flow_rate_constraint_with_parameters!(
                container,
                T,
                use_slacks,
                con_lb,
                con_ub,
                var_array,
                rep.name,
            )
        else
            _add_flow_rate_constraint!(
                container,
                rep,
                use_slacks,
                con_lb,
                con_ub,
                var_array,
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

function _nz_entries(ptdf_col::Vector{Float64})
    idx = [i for i in eachindex(ptdf_col) if abs(ptdf_col[i]) > PTDF_ZERO_TOL]
    return idx, ptdf_col[idx]
end
_nz_entries(ptdf_col::SparseArrays.SparseVector{Float64, Int}) =
    (SparseArrays.nonzeroinds(ptdf_col), SparseArrays.nonzeros(ptdf_col))

function _ptdf_branch_flow(
    rep::RepresentativeBranch,
    time_steps::UnitRange{Int},
    ptdf_col,
    nodal_balance_expressions::Matrix{JuMP.AffExpr},
    phase_var::Union{DenseAxisArray, Nothing},
    phase_controlled::Bool,
)
    @debug "Making Flow Expression on thread $(Threads.threadid()) for branch $(rep.name)"
    _assert_flow_expression_dimensions(rep.name, length(ptdf_col), nodal_balance_expressions)
    nz_idx, nz_val = _nz_entries(ptdf_col)
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
        if phase_controlled
            JuMP.add_to_expression!(acc, -_dc_susceptance(rep), phase_var[rep.name, t])
        else
            JuMP.add_to_expression!(acc, -_dc_shift_injection(rep))
        end
        expressions[t] = acc
    end
    return rep.name, expressions
end

function add_expressions!(
    container::OptimizationContainer,
    ::Type{PTDFBranchFlow},
    devices::IS.FlattenIteratorWrapper{B},
    device_model::DeviceModel{B, <:AbstractBranchFormulation},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {B <: PSY.ACTransmission}
    branches = _all_branches(network_model, B)
    time_steps = get_time_steps(container)
    flow_expr = add_expression_container!(
        container,
        PTDFBranchFlow,
        B,
        _branch_names(branches),
        time_steps,
    )

    ptdf = get_network_matrix(network_model)
    nodal_balance_expressions = get_expression(container, ActivePowerBalance, PSY.ACBus)
    phase_var =
        if has_container_key(container, PhaseShifterAngle, B)
            get_variable(container, PhaseShifterAngle, B)
        else
            nothing
        end
    tasks = map(branches) do rep
        # ptdf[arc, :] is a KLU solve; libklu is not concurrency safe, so this
        # happens in the main thread.
        ptdf_col = ptdf[rep.arc, :]
        Threads.@spawn try
            _ptdf_branch_flow(
                rep,
                time_steps,
                ptdf_col,
                nodal_balance_expressions.data,
                phase_var,
                _phase_controlled(rep, device_model, network_model)
            )
        catch e
            @error "PTDF flow-expression task failed" name = rep.name arc = rep.arc exception =
                (e, catch_backtrace())
            rethrow()
        end
    end
    for task in tasks
        name, expressions = fetch(task)
        flow_expr[name, :] .= expressions
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
<<<<<<< HEAD
    branch_flow_expr = get_expression(container, PTDFBranchFlow, T)
    flow_variables = get_variable(container, FlowActivePowerVariable, T)
=======
    flow_expr = get_expression(container, PTDFBranchFlow, T)
    flow_var = get_variable(container, FlowActivePowerVariable, T)
    net_reduction_data = get_network_reduction(network_model)
>>>>>>> b440124 (var phase for ptdf)
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    branches = get_branch_argument_constraint_axis(
        get_branch_catalog(network_model),
        reduced_branch_tracker,
        devices,
        cons_type,
    )
    branch_flow = add_constraints_container!(container, NetworkFlowConstraint, T, branches, time_steps,)
    jump_model = get_jump_model(container)

    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end

    for name in branches
        for t in time_steps
            flow =
                if use_slacks
                    JuMP.@expression(jump_model, flow_expr[name, t] - slack_ub[name, t] + slack_lb[name, t])
                else
                    flow_expr[name, t]
                end
            branch_flow[name, t] = JuMP.@constraint(
                jump_model,
                flow_var[name, t] == flow
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
    reps = _representative_branches(network_model, T, ConsKey)
    cons = add_constraints_container!(
        container, ConsKey, T, _branch_names(reps), time_steps,
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

    _foreach_branch(reps) do rep
        name = rep.name
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
            rating = _directional_flow_rating(rep, device_model)
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
)
    jump_model = get_jump_model(container)
    vm = get_variable(container, VoltageMagnitude, PSY.ACBus)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    vmf, vmt = vm[from_bus, :], vm[to_bus, :]
    vaf, vat = va[from_bus, :], va[to_bus, :]
    T = length(get_time_steps(container))
    return (
        v2_fr = JuMP.@expression(jump_model, [t = 1:T], vmf[t]^2),
        v2_to = JuMP.@expression(jump_model, [t = 1:T], vmt[t]^2),
        vv_cos = JuMP.@expression(
            jump_model,
            [t = 1:T],
            vmf[t] * vmt[t] * cos(vaf[t] - vat[t])
        ),
        vv_sin = JuMP.@expression(
            jump_model,
            [t = 1:T],
            vmf[t] * vmt[t] * sin(vaf[t] - vat[t])
        ),
    )
end

function _voltage_products(
    container::OptimizationContainer,
    ::NetworkModel{ACRNetworkModel},
    ::Type{<:PSY.ACTransmission},
    ::String,
    from_bus::String,
    to_bus::String,
)
    jump_model = get_jump_model(container)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    vr_fr, vr_to = vr[from_bus, :], vr[to_bus, :]
    vi_fr, vi_to = vi[from_bus, :], vi[to_bus, :]
    T = length(get_time_steps(container))
    return (
        v2_fr = JuMP.@expression(jump_model, [t = 1:T], vr_fr[t]^2 + vi_fr[t]^2),
        v2_to = JuMP.@expression(jump_model, [t = 1:T], vr_to[t]^2 + vi_to[t]^2),
        vv_cos = JuMP.@expression(
            jump_model,
            [t = 1:T],
            vr_fr[t] * vr_to[t] + vi_fr[t] * vi_to[t]
        ),
        vv_sin = JuMP.@expression(
            jump_model,
            [t = 1:T],
            vi_fr[t] * vr_to[t] - vr_fr[t] * vi_to[t]
        ),
    )
end

function _voltage_products(
    container::OptimizationContainer,
    ::NetworkModel{LPACCNetworkModel},
    ::Type{D},
    name::String,
    from_bus::String,
    to_bus::String,
) where {D <: PSY.ACTransmission}
    jump_model = get_jump_model(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    phi = get_variable(container, VoltageDeviation, PSY.ACBus)
    cs = get_variable(container, CosineApproximation, D)
    phi_fr, phi_to = phi[from_bus, :], phi[to_bus, :]
    T = length(get_time_steps(container))
    return (
        v2_fr = JuMP.@expression(jump_model, [t = 1:T], 1.0 + 2.0 * phi_fr[t]),
        v2_to = JuMP.@expression(jump_model, [t = 1:T], 1.0 + 2.0 * phi_to[t]),
        vv_cos = JuMP.@expression(
            jump_model,
            [t = 1:T],
            cs[name, t] + phi_fr[t] + phi_to[t]
        ),
        vv_sin = JuMP.@expression(jump_model, [t = 1:T], va[from_bus, t] - va[to_bus, t]),
    )
end

# PNM.ybus_branch_entries-adjacent: supports variable tap, separates
# condutance and susceptance.
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

    reps = _representative_branches(
        network_model, T, NetworkFlowConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    cons_pft, cons_qft, cons_ptf, cons_qtf =
        _add_flow_constraint_containers!(container, T, _branch_names(reps))
    jump_model = get_jump_model(container)
    slacks = _flow_equality_slacks(container, device_model, T)
    tap_var =
        if has_container_key(container, TapRatioVariable, T)
            get_variable(container, TapRatioVariable, T)
        else
            nothing
        end

    _foreach_branch(reps) do rep
        name = rep.name
        adm = _admittance(rep)
        from_bus = _from_name(rep)
        to_bus = _to_name(rep)

        vp = _voltage_products(container, network_model, T, name, from_bus, to_bus)
        tap_controlled = _tap_controlled(rep, device_model, network_model)
        for t in time_steps
            tap = tap_controlled ? tap_var[name, t] : adm.tap
            y = _tapped_admittance(jump_model, adm, tap)

            cons_pft[name, t] = JuMP.@constraint(
                jump_model,
                pft[name, t] ==
                y.g11 * vp.v2_fr[t] + y.g12 * vp.vv_cos[t] + y.b12 * vp.vv_sin[t] +
                _slack_term(slacks.p_ft, name, t)
            )
            cons_ptf[name, t] = JuMP.@constraint(
                jump_model,
                ptf[name, t] ==
                y.g22 * vp.v2_to[t] + y.g21 * vp.vv_cos[t] - y.b21 * vp.vv_sin[t] +
                _slack_term(slacks.p_tf, name, t),
            )
            cons_qft[name, t] = JuMP.@constraint(
                jump_model,
                qft[name, t] ==
                -y.b11 * vp.v2_fr[t] - y.b12 * vp.vv_cos[t] + y.g12 * vp.vv_sin[t] +
                _slack_term(slacks.q_ft, name, t),
            )
            cons_qtf[name, t] = JuMP.@constraint(
                jump_model,
                qtf[name, t] ==
                -y.b22 * vp.v2_to[t] - y.b21 * vp.vv_cos[t] - y.g21 * vp.vv_sin[t] +
                _slack_term(slacks.q_tf, name, t),
            )
        end
    end
    return
end

_branch_uses_control(
    ::Type{VoltageControlConstraint},
    branch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _voltage_controlled(branch, device_model, network_model)
_branch_uses_control(
    ::Type{ReactivePowerFlowControlConstraint},
    branch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _reactive_controlled(branch, device_model, network_model)
_branch_uses_control(
    ::Type{ActivePowerFlowControlConstraint},
    branch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _active_controlled(branch, device_model, network_model)

function _branches_for_cons(
    C::Union{
        Type{VoltageControlConstraint},
        Type{ReactivePowerFlowControlConstraint},
        Type{ActivePowerFlowControlConstraint},
    },
    device_model::DeviceModel{T},
    network_model::NetworkModel,
) where {T}
    members = RepresentativeBranch[]
    _foreach_branch(_representative_branches(network_model, T, C)) do branch
        _branch_uses_control(C, branch, device_model, network_model) &&
            push!(members, branch)
    end
    return members
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
        [t = 1:length(get_time_steps(container))],
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
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel{<:_TAP_NETWORKS},
) where {T <: _TRANSFORMERS}
    _control_enabled(device_model) || return

    branches = _branches_for_cons(VoltageControlConstraint, device_model, network_model)
    time_steps = get_time_steps(container)
    cons = add_constraints_container!(
        container,
        VoltageControlConstraint,
        T,
        _branch_names(branches),
        1:2,
        time_steps,
    )

    jump_model = get_jump_model(container)
    _foreach_branch(branches) do rep
        cont_lims = _quantity_limits(rep)
        bus = PSY.get_bus(sys, _regulated_number(rep))
        bus_name = PSY.get_name(bus)
        bus_lims = PSY.get_voltage_limits(bus)
        (bus_lims.min <= cont_lims.min <= cont_lims.max <= bus_lims.max) || error(
            "Bus voltage limits for $bus_name disagree with control limits for circuit $(rep.name).",
        )

        lims = _voltage_limits(cont_lims, network_model)
        vm = _voltage_magnitude(container, bus_name, network_model)
        for t in time_steps
            cons[rep.name, 1, t] = JuMP.@constraint(jump_model, vm[t] >= lims.min)
            cons[rep.name, 2, t] = JuMP.@constraint(jump_model, vm[t] <= lims.max)
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
) where {T <: PSY.ACTransmission} = nothing

_flow_array(
    container::OptimizationContainer,
    ::Type{ReactivePowerFlowControlConstraint},
    ::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    ::NetworkModel{<:_TAP_NETWORKS}
) where {T <: _TRANSFORMERS} = get_variable(container, FlowReactivePowerFromToVariable, T)
_flow_array(
    container::OptimizationContainer,
    ::Type{ActivePowerFlowControlConstraint},
    ::DeviceModel{T, StaticBranch},
    ::NetworkModel{DCPNetworkModel},
) where {T <: _TRANSFORMERS} = get_expression(container, BThetaBranchFlow, T)
_flow_array(
    container::OptimizationContainer,
    ::Type{ActivePowerFlowControlConstraint},
    ::DeviceModel{T, StaticBranchBounds},
    ::NetworkModel{DCPNetworkModel},
) where {T <: _TRANSFORMERS} = get_variable(container, FlowActivePowerVariable, T)
_flow_array(
    container::OptimizationContainer,
    ::Type{ActivePowerFlowControlConstraint},
    ::DeviceModel{T, <:Union{StaticBranch, StaticBranchBounds}},
    ::NetworkModel{DCPLLNetworkModel},
) where {T <: _TRANSFORMERS} =
    get_variable(container, FlowActivePowerFromToVariable, T)
_flow_array(
    container::OptimizationContainer,
    ::Type{ActivePowerFlowControlConstraint},
    ::DeviceModel{T, StaticBranch},
    ::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: _TRANSFORMERS} = get_expression(container, PTDFBranchFlow, T)
_flow_array(
    container::OptimizationContainer,
    ::Type{ActivePowerFlowControlConstraint},
    ::DeviceModel{T, StaticBranchBounds},
    ::NetworkModel{<:AbstractPTDFNetworkModel},
) where {T <: _TRANSFORMERS} = get_variable(container, FlowActivePowerVariable, T)

function _add_flow_control_constraints!(
    container::OptimizationContainer,
    ::Type{C},
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel,
) where {C <: Union{ReactivePowerFlowControlConstraint, ActivePowerFlowControlConstraint}, T <: _TRANSFORMERS}
    _control_enabled(device_model) || return

    branches = _branches_for_cons(C, device_model, network_model)
    time_steps = get_time_steps(container)
    cons = add_constraints_container!(
        container,
        C,
        T,
        _branch_names(branches),
        1:2,
        time_steps,
    )
    flow = _flow_array(container, C, device_model, network_model)

    jump_model = get_jump_model(container)
    _foreach_branch(branches) do rep
        cont_lims = _quantity_limits(rep)
        line_lims = _flow_limits(rep, device_model)

        (line_lims.min <= cont_lims.min <= cont_lims.max <= line_lims.max) ||
            error("Control limits and line rating for circuit $(rep.name) disagree.")

        for t in time_steps
            cons[rep.name, 1, t] =
                JuMP.@constraint(jump_model, flow[rep.name, t] >= cont_lims.min)
            cons[rep.name, 2, t] =
                JuMP.@constraint(jump_model, flow[rep.name, t] <= cont_lims.max)
        end
    end
    return
end

_add_flow_control_constraints!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T},
    ::NetworkModel,
) where {T <: PSY.ACTransmission} = nothing

function _add_transformer_control_constraints!(
    container::OptimizationContainer,
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel{<:_TAP_NETWORKS},
) where {T <: _TRANSFORMERS}
    _control_enabled(device_model) || return
    _add_voltage_control_constraints!(container, sys, devices, device_model, network_model)
    _add_flow_control_constraints!(container, ReactivePowerFlowControlConstraint, devices, device_model, network_model)
    return
end

function _add_transformer_control_constraints!(
    container::OptimizationContainer,
    ::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel{<:_PHASE_NETWORKS},
) where {T <: _TRANSFORMERS}
    _control_enabled(device_model) || return
    _add_flow_control_constraints!(container, ActivePowerFlowControlConstraint, devices, device_model, network_model)
    return
end

_add_transformer_control_constraints!(
    ::OptimizationContainer,
    ::PSY.System,
    ::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T},
    ::NetworkModel,
) where {T <: PSY.ACTransmission} = nothing

################################## LPACCNetworkModel branch constraints ###############

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

    reps = _representative_branches(
        network_model, T, CosineRelaxationConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    # Zero-width angle limits produce no constraint, so the container is sized on the
    # constrained subset only.
    constrained =
        filter(rep -> !iszero(_max_angle_difference(rep)), reps)
    cons = add_constraints_container!(
        container, CosineRelaxationConstraint, T, _branch_names(constrained),
        time_steps,
    )

    _foreach_branch(constrained) do rep
        vad_max = _max_angle_difference(rep)
        k = (1.0 - cos(vad_max)) / vad_max^2
        from_name = _from_name(rep)
        to_name = _to_name(rep)
        for t in time_steps
            cons[rep.name, t] = JuMP.@constraint(
                get_jump_model(container),
                cs[rep.name, t] <=
                1.0 - k * (va[from_name, t] - va[to_name, t])^2,
            )
        end
    end
    return
end

################################## IVRNetworkModel branch constraints ##################

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

    reps = _representative_branches(
        network_model, T, NetworkFlowConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    branch_names = _branch_names(reps)

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
    _foreach_branch(reps) do rep
        name = rep.name
        adm = _admittance(rep)
        g = adm.g
        b = adm.b
        g_fr = adm.g_fr
        b_fr = adm.b_fr
        g_to = adm.g_to
        b_to = adm.b_to
        from_bus = _from_name(rep)
        to_bus = _to_name(rep)

        # Series impedance Z = r + jx = conj(y)/|y|²
        ymag2 = g^2 + b^2
        r = g / ymag2
        x = -b / ymag2

        tap_controlled = _tap_controlled(rep, device_model, network_model)
        for t in time_steps
            tm = tap_controlled ? tap_var[name, t] : adm.tap
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
    rating2 = [
        rep.name => _rate_rhs_squared(_current_rating(rep, device_model)) for
        rep in _representative_branches(network_model, T, CurrentLimitConstraint)
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

    # One lb/ub pair per reduced arc — the flow variables are shared per arc — with the
    # rating from the arc's equivalent parameters. The TS parameter axes are already
    # reduction-entry names.
    reps = _representative_branches(network_model, T, FlowRateConstraint)
    branch_names = _branch_names(reps)
    con_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
    )
    con_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
    )
    _foreach_branch(reps) do rep
        name = rep.name
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
            limits = _flow_limits(rep, device_model)
            for t in time_steps
                if use_slacks
                    ub_lhs = flow_vars[name, t] - slack_ub[name, t]
                    lb_lhs = flow_vars[name, t] + slack_lb[name, t]
                else
                    ub_lhs = flow_vars[name, t]
                    lb_lhs = flow_vars[name, t]
                end
                con_ub[name, t] = JuMP.@constraint(jump_model, ub_lhs <= limits.max)
                con_lb[name, t] = JuMP.@constraint(jump_model, lb_lhs >= limits.min)
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

    reps = _representative_branches(
        network_model, T, NetworkFlowConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    branch_names = _branch_names(reps)
    cons = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps,
    )

    use_slacks = get_use_slacks(device_model)
    if use_slacks
        slack_ub = get_variable(container, FlowActivePowerSlackUpperBound, T)
        slack_lb = get_variable(container, FlowActivePowerSlackLowerBound, T)
    end
    phase_var =
        if has_container_key(container, PhaseShifterAngle, T)
            get_variable(container, PhaseShifterAngle, T)
        else
            nothing
        end

    jump_model = get_jump_model(container)
    _foreach_branch(reps) do rep
        name = rep.name
        b = _dc_susceptance(rep)
        dc_shift = _dc_shift(rep)
        from_name = _from_name(rep)
        to_name = _to_name(rep)
        phase_controlled = _phase_controlled(rep, device_model, network_model)
        for t in time_steps
            flow =
                if use_slacks
                    JuMP.@expression(
                        jump_model,
                        p[name, t] - slack_ub[name, t] + slack_lb[name, t]
                    )
                else
                    p[name, t]
                end
            shift = phase_controlled ? phase_var[rep.name, t] : dc_shift
            cons[name, t] = JuMP.@constraint(
                jump_model,
                flow == b * (va[from_name, t] - va[to_name, t] - shift)
            )
        end
    end
    return
end

"""
Add the B-θ branch-flow expression for ACBranch StaticBranch under DCPNetworkModel:

    BThetaBranchFlow = b * (va_fr - va_to - shift)

with the DC `b`/`shift` pair described on the `NetworkFlowConstraint` builder above, so the
`b·shift` offset matches PNM's `arc_dc_shift_injection`.
"""
function add_expressions!(
    container::OptimizationContainer,
    ::Type{BThetaBranchFlow},
    sys::PSY.System,
    devices::IS.FlattenIteratorWrapper{T},
    device_model::DeviceModel{T, StaticBranch},
    network_model::NetworkModel{DCPNetworkModel},
) where {T <: PSY.ACTransmission}
    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)

    reps = _representative_branches(
        network_model, T, NetworkFlowConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    branch_names = _branch_names(reps)

    bfe =
        add_expression_container!(container, BThetaBranchFlow, T, branch_names, time_steps)
    nodal_expr = get_expression(container, ActivePowerBalance, PSY.ACBus)
    phase_var =
        if has_container_key(container, PhaseShifterAngle, T)
            get_variable(container, PhaseShifterAngle, T)
        else
            nothing
        end
    jump_model = get_jump_model(container)

    _foreach_branch(reps) do rep
        b = _dc_susceptance(rep)
        dc_shift = _dc_shift(rep)
        from_name = _from_name(rep)
        to_name = _to_name(rep)
        from_no = _from_number(rep)
        to_no = _to_number(rep)
        tap = _admittance(rep).tap

        phase_controlled = _phase_controlled(rep, device_model, network_model)
        for t in time_steps
            shift = phase_controlled ? phase_var[rep.name, t] : dc_shift
            flow = JuMP.@expression(
                jump_model,
                b * (va[from_name, t] - va[to_name, t] - shift)
            )
            bfe[rep.name, t] = flow
            add_proportional_to_jump_expression!(nodal_expr[from_no, t], flow, -1.0)
            add_proportional_to_jump_expression!(nodal_expr[to_no, t], flow, 1.0)
        end
    end
    return
end

"""
Add branch flow rate (rating) inequalities for ACBranch StaticBranch under
DCPNetworkModel, directly on the `BThetaBranchFlow` expression (no defining
equality/variable to bound instead). Walks one representative per reduced arc and reuses
the shared static/parameterized-rating row builders, mirroring the variable-based
`FlowRateConstraint` DCP builder above but targeting the expression container.
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

    reps = _representative_branches(network_model, T, FlowRateConstraint)
    branch_names = _branch_names(reps)
    con_lb = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "lb",
    )
    con_ub = add_constraints_container!(
        container, FlowRateConstraint, T, branch_names, time_steps; meta = "ub",
    )

    _foreach_branch(reps) do rep
        name = rep.name
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
            limits = _flow_limits(rep, device_model)
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
    any(_constrains_angle_difference, devices) || return

    time_steps = get_time_steps(container)
    va = get_variable(container, VoltageAngle, PSY.ACBus)
    # Angle limits are per-device data, so only direct entries carrying non-default
    # limits receive a constraint; series/parallel equivalents have none.
    constrained = filter(
        _constrains_angle_difference,
        _representative_branches(
            network_model, T, AngleDifferenceConstraint;
            number_to_name = _retained_number_to_name(sys, network_model),
        ),
    )
    isempty(constrained) && return

    branch_names = _branch_names(constrained)
    cons = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps,
    )

    _foreach_branch(constrained) do rep
        # angle limits are in radians — no per-unit conversion
        lims = _angle_limits(rep)
        from_name = _from_name(rep)
        to_name = _to_name(rep)
        for t in time_steps
            cons[rep.name, t] = JuMP.@constraint(
                get_jump_model(container),
                lims.min <= va[from_name, t] - va[to_name, t] <= lims.max,
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
    any(_constrains_angle_difference, devices) || return

    time_steps = get_time_steps(container)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    # Angle limits are per-device data, so only direct entries carrying non-default
    # limits receive a constraint; series/parallel equivalents have none.
    constrained = filter(
        _constrains_angle_difference,
        _representative_branches(
            network_model, T, AngleDifferenceConstraint;
            number_to_name = _retained_number_to_name(sys, network_model),
        ),
    )
    isempty(constrained) && return

    branch_names = _branch_names(constrained)
    cons_ub = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps; meta = "ub",
    )
    cons_lb = add_constraints_container!(
        container, AngleDifferenceConstraint, T, branch_names, time_steps; meta = "lb",
    )

    jump_model = get_jump_model(container)
    _foreach_branch(constrained) do rep
        # angle limits are in radians — no per-unit conversion
        lims = _angle_limits(rep)
        fr = _from_name(rep)
        to = _to_name(rep)
        for t in time_steps
            vvr = vr[fr, t] * vr[to, t] + vi[fr, t] * vi[to, t]
            vvi = vi[fr, t] * vr[to, t] - vr[fr, t] * vi[to, t]
            cons_ub[rep.name, t] = JuMP.@constraint(jump_model, vvi <= tan(lims.max) * vvr)
            cons_lb[rep.name, t] = JuMP.@constraint(jump_model, vvi >= tan(lims.min) * vvr)
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
# variable tightening (not one-per-arc constraints), so this runs over every branch name
# without claiming constraint-axis arcs; aliased per-arc variables tolerate the repeated
# tightening (all members carry the same equivalent).
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
    _foreach_branch(_all_branches(network_model, T)) do rep
        rate = _directional_flow_rating(rep, device_model)
        for t in time_steps
            _tighten_flow_bound!(pft[rep.name, t], rate)
            _tighten_flow_bound!(ptf[rep.name, t], rate)
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

    reps = _representative_branches(network_model, T, FlowRateConstraint)
    branch_names = _branch_names(reps)
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

    _foreach_branch(reps) do rep
        name = rep.name
        limits = _flow_limits(rep, device_model)
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

    reps = _representative_branches(
        network_model, T, NetworkFlowConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    branch_names = _branch_names(reps)
    cons = add_constraints_container!(
        container, NetworkFlowConstraint, T, branch_names, time_steps,
    )
    phase_var =
        if has_container_key(container, PhaseShifterAngle, T)
            get_variable(container, PhaseShifterAngle, T)
        else
            nothing
        end

    jump_model = get_jump_model(container)
    _foreach_branch(reps) do rep
        b = _dc_susceptance(rep)
        dc_shift = _dc_shift(rep)
        from_name = _from_name(rep)
        to_name = _to_name(rep)
        tap = _admittance(rep).tap
        phase_controlled = _phase_controlled(rep, device_model, network_model)
        for t in time_steps
            shift = phase_controlled ? phase_var[rep.name, t] : dc_shift
            cons[rep.name, t] = JuMP.@constraint(
                jump_model,
                pft[rep.name, t] == b * (va[from_name, t] - va[to_name, t] - shift),
            )
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

    reps = _representative_branches(
        network_model, T, NetworkLossConstraint;
        number_to_name = _retained_number_to_name(sys, network_model),
    )
    branch_names = _branch_names(reps)
    cons = add_constraints_container!(
        container, NetworkLossConstraint, T, branch_names, time_steps,
    )

    jump_model = get_jump_model(container)
    _foreach_branch(reps) do rep
        r = _dc_resistance(rep)
        for t in time_steps
            cons[rep.name, t] = JuMP.@constraint(
                jump_model,
                pft[rep.name, t] + ptf[rep.name, t] >= r * pft[rep.name, t]^2,
            )
        end
    end
    return
end
