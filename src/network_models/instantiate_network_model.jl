"""
Concrete implementations of `instantiate_network_model!` for specific network formulations.

These methods extend the generic dispatch from IOM's `operation_model_interface.jl`, which
calls `instantiate_network_model!(network_model, branch_models, number_of_steps, sys)`.
Each method here handles the formulation-specific setup: computing PTDF/MODF matrices,
discovering subnetworks, applying network reductions, etc.
"""

#################################################################################
# Helper functions (moved from IOM)
#################################################################################

function _make_subnetworks_from_subnetwork_axes(ptdf::PNM.PTDF)
    subnetworks = Dict{Int, Set{Int}}()
    for (ref_bus, ptdf_axes) in ptdf.subnetwork_axes
        subnetworks[ref_bus] = Set(ptdf_axes[1])
    end
    return subnetworks
end

function _make_subnetworks_from_subnetwork_axes(ptdf::PNM.VirtualPTDF)
    subnetworks = Dict{Int, Set{Int}}()
    for (ref_bus, ptdf_axes) in ptdf.subnetwork_axes
        subnetworks[ref_bus] = Set(ptdf_axes[2])
    end
    return subnetworks
end

function _make_subnetworks_from_subnetwork_axes(ybus::PNM.Ybus)
    subnetworks = Dict{Int, Set{Int}}()
    for (ref_bus, ybus_axes) in ybus.subnetwork_axes
        subnetworks[ref_bus] = Set(ybus_axes[1])
    end
    return subnetworks
end

function _assign_subnetworks_to_buses(
    model::NetworkModel{T},
    sys::PSY.System,
) where {T <: AbstractPTDFNetworkModel}
    subnetworks = model.subnetworks
    temp_bus_map = Dict{Int, Int}()
    network_reduction = get_network_reduction(model)
    for bus in get_available_components(model, PSY.ACBus, sys)
        bus_no = PSY.get_number(bus)
        mapped_bus_no = PNM.get_mapped_bus_number(network_reduction, bus)
        mapped_bus_no ∈ network_reduction.removed_buses && continue
        bus_mapped = false
        if haskey(temp_bus_map, bus_no)
            model.bus_area_map[bus] = temp_bus_map[bus_no]
            continue
        else
            for (subnet, bus_set) in subnetworks
                if mapped_bus_no ∈ bus_set
                    temp_bus_map[bus_no] = subnet
                    model.bus_area_map[bus] = subnet
                    bus_mapped = true
                    break
                end
            end
        end
        if !bus_mapped
            error(
                "Bus $(PSY.summary(bus)) not mapped to any reference bus: Mapped bus number: $(mapped_bus_no)",
            )
        end
    end
    return
end

_assign_subnetworks_to_buses(
    ::NetworkModel{T},
    ::PSY.System,
) where {T <: AbstractNetworkModel} = nothing

function _push_component_buses!(buses::Set{Int64}, branch::PSY.Branch)
    arc = PSY.get_arc(branch)
    push!(buses, PSY.get_number(PSY.get_from(arc)))
    push!(buses, PSY.get_number(PSY.get_to(arc)))
    return
end

function _push_component_buses!(buses::Set{Int64}, branch::PSY.ThreeWindingTransformer)
    for circuit in PSY.get_circuits(branch)
        arc = PSY.get_arc(circuit)
        push!(buses, PSY.get_number(PSY.get_from(arc)))
        push!(buses, PSY.get_number(PSY.get_to(arc)))
    end
    return
end

function _push_component_buses!(buses::Set{Int64}, device::PSY.StaticInjection)
    push!(buses, PSY.get_number(PSY.get_bus(device)))
    return
end

function _push_component_buses!(buses::Set{Int64}, bus::PSY.ACBus)
    PSY.get_available(bus) && push!(buses, PSY.get_number(bus))
    return
end

# AreaInterchange <: PSY.Branch but connects two Areas, not two buses; it has no
# arc, so the PSY.Branch method above would error on PSY.get_arc. Not reachable
# today (modeled_branch_types entries are filtered to <: PSY.ACTransmission
# before reaching _push_component_buses!, and AreaInterchange isn't one), but
# guard it explicitly so a future caller can't hit that MethodError.
function _push_component_buses!(::Set{Int64}, ::PSY.AreaInterchange)
    return
end

# Fallback for monitored/outaged component types with no bus-pinning rule. Reached
# from `_add_outage_monitored_irreducible_buses!`, which iterates the raw
# `PSY.get_monitored_components(outage)` UUIDs (unfiltered — unlike the
# template-validation path), so any non-{Branch, ThreeWindingTransformer,
# StaticInjection, ACBus} monitored type lands here. Warn and skip rather than
# MethodError so this PTDF-side protected set stays reconcilable with PNM's
# `VirtualMODF` collector (`_accumulate_protected_buses!(::PSY.Component)`, which also
# warn-skips). The consequence is real, hence the explicit message.
function _push_component_buses!(::Set{Int64}, c::PSY.Component)
    @warn "Outage-monitored component $(typeof(c)) ($(PSY.get_name(c))) has no \
           reduction-protection rule; its bus is not pinned and may be reduced away, \
           so the contingency it participates in will not be enforced. This mirrors \
           PNM's VirtualMODF _accumulate_protected_buses! warn-skip; if this type \
           should be protected, add a _push_component_buses! method for it." maxlog = 5
    return
end

# Outages registered on an outage-aware branch DeviceModel pin both their
# monitored and their outaged (associated) component buses so the network
# reduction can't collapse them: the MODF column for a contingency is keyed by
# the outaged arc's endpoints, and post-contingency flow constraints reference
# the monitored components' real bus numbers.
function _add_outage_monitored_irreducible_buses!(
    irreducible_buses::Set{Int64},
    sys::PSY.System,
    branch_models::BranchModelContainer,
)
    outage_uuids = Set{Base.UUID}()
    for m in values(branch_models)
        IOM.supports_outages(get_formulation(m)) || continue
        union!(outage_uuids, keys(get_outages(m)))
    end

    for outage_uuid in outage_uuids
        outage = PSY.get_supplemental_attribute(sys, outage_uuid)
        for uuid in PSY.get_monitored_components(outage)
            component = IS.get_component(sys, uuid)
            if isnothing(component)
                throw(
                    IS.ConflictingInputsError(
                        "Monitored component with UUID $(uuid) on outage $(IS.get_uuid(outage)) not found in system. Data requires correction",
                    ),
                )
            end
            _push_component_buses!(irreducible_buses, component)
        end
        for component in PSY.get_associated_components(sys, outage)
            _push_component_buses!(irreducible_buses, component)
        end
    end
    return
end

# Buses that must survive PNM network reductions because something monitored is
# pinned to them: branch endpoints carrying a `BranchRatingTimeSeriesParameter`
# (dynamic line ratings), and the monitored/outaged endpoints of outages
# registered on outage-aware (security-constrained) branch DeviceModels.
function _get_irreducible_buses_due_to_monitored_components(
    sys::PSY.System,
    network_model::NetworkModel,
    branch_models::BranchModelContainer,
)
    @debug "Identifying buses that are irreducible due to monitored components"
    irreducible_buses = Set{Int64}()
    for branch_type in network_model.modeled_branch_types
        branch_type <: PSY.ACTransmission || continue
        device_model = branch_models[nameof(branch_type)]
        if !haskey(
            get_time_series_names(device_model),
            BranchRatingTimeSeriesParameter,
        )
            continue
        end

        if branch_type == PSY.ThreeWindingTransformer
            @warn "Dynamic branch ratings for ThreeWindingTransformers are not implemented yet. Skipping it."
            continue
        end

        ts_name =
            get_time_series_names(device_model)[BranchRatingTimeSeriesParameter]
        ts_type = PSY.Deterministic #TODO workaround since we dont have the container

        branches = PSY.get_available_components(branch_type, sys)
        for branch in branches
            if !PSY.has_time_series(branch, ts_type, ts_name)
                continue
            end
            _push_component_buses!(irreducible_buses, branch)
        end
    end
    _add_outage_monitored_irreducible_buses!(irreducible_buses, sys, branch_models)
    # `model_all_branches` MonitoredLine models pin their lines so zero-impedance
    # ones survive the reduction instead of being merged away.
    _add_model_all_branches_irreducible_buses!(irreducible_buses, branch_models)
    return collect(irreducible_buses)
end

# Pin both endpoint buses of every branch a `model_all_branches` MonitoredLine model
# covers. Dispatch on the model type so it is a no-op for other branch types.
function _add_model_all_branches_irreducible_buses!(
    irreducible_buses::Set{Int64},
    branch_models::BranchModelContainer,
)
    for m in values(branch_models)
        _pin_model_all_branches!(irreducible_buses, m)
    end
    return
end

_pin_model_all_branches!(::Set{Int64}, ::DeviceModel) = nothing

function _pin_model_all_branches!(
    irreducible_buses::Set{Int64},
    m::DeviceModel{PSY.MonitoredLine},
)
    get_attribute(m, MODEL_ALL_BRANCHES_KEY) === true || return
    # The device cache is the modeled set (available + filter_function).
    for branch in get_device_cache(m)
        _push_component_buses!(irreducible_buses, branch)
    end
    return
end

# Drop (and warn about) any branch type whose components were all merged away by the
# reduction — e.g. a lone zero-impedance monitored line. Such a type has no surviving
# arc in `name_to_arc_maps`, so building its flow vars/constraints would fail. Absence
# from the map alone is not enough: types that never use it (e.g. HVDC) are also
# absent, so we prune only when an endpoint bus was actually removed by the reduction.
# Uncommon; `model_all_branches` keeps such lines instead.
function _prune_fully_reduced_branch_models!(
    network_model::NetworkModel,
    branch_models::BranchModelContainer,
)
    merged_buses = Set{Int64}()
    for removed in values(PNM.get_bus_reduction_map(network_model.network_reduction))
        union!(merged_buses, removed)
    end
    isempty(merged_buses) && return
    name_to_arc_maps = PNM.get_name_to_arc_maps(network_model.network_reduction)
    pruned = DataType[]
    for branch_type in network_model.modeled_branch_types
        branch_type <: PSY.ACTransmission || continue
        haskey(branch_models, nameof(branch_type)) || continue
        survived = get(name_to_arc_maps, branch_type, nothing)
        isnothing(survived) || isempty(survived) || continue
        buses = Set{Int64}()
        for component in get_device_cache(branch_models[nameof(branch_type)])
            _push_component_buses!(buses, component)
        end
        isdisjoint(buses, merged_buses) && continue
        push!(pruned, branch_type)
    end
    for branch_type in pruned
        hint = if branch_type === PSY.MonitoredLine
            " Use the `model_all_branches` attribute on the MonitoredLine DeviceModel to retain such lines through the reduction."
        else
            " Consider adjusting the network-reduction settings/tolerance to avoid merging all branches of this type."
        end
        @warn "All components of branch type $(branch_type) were merged away by the " *
              "network reduction (e.g. a zero-impedance branch merge). The " *
              "$(branch_type) DeviceModel is dropped from the template and will not " *
              "be modeled.$hint"
        delete!(branch_models, nameof(branch_type))
        filter!(!=(branch_type), network_model.modeled_branch_types)
    end
    return
end

# Warn about individual monitored lines the reduction merged away while their type
# still has surviving members. The whole-type prune above misses this partial case,
# so without a message the dropped line is silently unmodeled. Suggest
# `model_all_branches` to retain it.
function _warn_partially_reduced_monitored_lines!(
    network_model::NetworkModel,
    branch_models::BranchModelContainer,
)
    removed_arcs = PNM.get_removed_arcs(network_model.network_reduction)
    isempty(removed_arcs) && return
    for m in values(branch_models)
        _warn_reduced_monitored_lines!(removed_arcs, m)
    end
    return
end

_warn_reduced_monitored_lines!(removed_arcs::Set{Tuple{Int, Int}}, ::DeviceModel) = nothing

function _warn_reduced_monitored_lines!(
    removed_arcs::Set{Tuple{Int, Int}},
    m::DeviceModel{PSY.MonitoredLine},
)
    dropped = [
        PSY.get_name(ml) for ml in get_device_cache(m) if
        _branch_arc_removed(ml, removed_arcs)
    ]
    isempty(dropped) && return
    @warn "MonitoredLine(s) $(dropped) were merged away by the network reduction " *
          "(near-zero impedance) and will not be modeled or monitored, though other " *
          "MonitoredLines remain. Set the `model_all_branches` attribute on the " *
          "MonitoredLine DeviceModel to force all monitored lines to be modeled " *
          "through the reduction."
    return
end

function _branch_arc_removed(branch::PSY.Branch, removed_arcs)
    arc = PSY.get_arc(branch)
    from = PSY.get_number(PSY.get_from(arc))
    to = PSY.get_number(PSY.get_to(arc))
    return (from, to) in removed_arcs || (to, from) in removed_arcs
end

function _get_unmodeled_branch_types(
    branch_models::BranchModelContainer,
    sys::PSY.System,
)
    unmodeled = DataType[]
    for d in PSY.get_existing_device_types(sys)
        if d <: PSY.ACTransmission && !haskey(branch_models, nameof(d))
            push!(unmodeled, d)
        end
    end
    return unmodeled
end

function _validate_network_and_branches(
    model::NetworkModel,
    branch_models::BranchModelContainer,
    sys::PSY.System,
)
    unmodeled = _get_unmodeled_branch_types(branch_models, sys)
    IOM._check_branch_network_compatibility(model, unmodeled)
    return
end

#################################################################################
# Generic fallback for AbstractNetworkModel (Ybus-based models: ACP, ACR, etc.)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{T},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
) where {T <: AbstractNetworkModel}
    _validate_network_and_branches(model, branch_models, sys)
    irreducible_buses = _get_irreducible_buses_due_to_monitored_components(
        sys,
        model,
        branch_models,
    )
    _instantiate_ybus_network_reduction!(model, sys, irreducible_buses)
    _finalize_network_reduction!(model, branch_models, number_of_steps)
    return
end

# DCP additionally supports MODF security-constrained branches: build/reconcile
# the contingency matrix between the Ybus reduction and the finalize step, since
# reconciliation can replace `network_reduction` before the branch maps are
# populated.
function IOM.instantiate_network_model!(
    model::NetworkModel{DCPNetworkModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    _validate_network_and_branches(model, branch_models, sys)
    irreducible_buses = _get_irreducible_buses_due_to_monitored_components(
        sys,
        model,
        branch_models,
    )
    _instantiate_ybus_network_reduction!(model, sys, irreducible_buses)
    _maybe_build_dcp_modf_matrix!(model, branch_models, sys, irreducible_buses)
    _finalize_network_reduction!(model, branch_models, number_of_steps)
    return
end

# Ybus-derived reduction shared by every Ybus-based network model (ACP, ACR,
# DCP, NFA, ...): build the (possibly reduced) Ybus, derive the subnetworks, and
# install the reduction data on the model.
function _instantiate_ybus_network_reduction!(
    model::NetworkModel,
    sys::PSY.System,
    irreducible_buses::Vector{Int64},
)
    if model.reduce_radial_branches && model.reduce_degree_two_branches
        @info "Applying both radial and degree two reductions"
        ybus = PNM.Ybus(
            sys;
            network_reductions = PNM.NetworkReduction[
                PNM.RadialReduction(),
                PNM.DegreeTwoReduction(),
            ],
            irreducible_buses = irreducible_buses,
        )
    elseif model.reduce_radial_branches
        @info "Applying radial reduction"
        if !isempty(irreducible_buses)
            @warn "Irreducible buses identified due to DLRs. The reduction of any radial branch between 2 irreducible buses wil be ignored"
        end
        ybus =
            PNM.Ybus(
                sys;
                network_reductions = PNM.NetworkReduction[PNM.RadialReduction()],
                irreducible_buses = irreducible_buses,
            )
    elseif model.reduce_degree_two_branches
        @info "Applying degree two reduction"
        ybus = PNM.Ybus(
            sys;
            network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
            irreducible_buses = irreducible_buses,
        )
    else
        ybus = PNM.Ybus(sys)
    end
    # Reuse the Ybus built above (it carries the reduction-aware subnetwork
    # grouping in `subnetwork_axes`) instead of a throwaway PNM.find_subnetworks.
    if isempty(model.subnetworks)
        model.subnetworks = _make_subnetworks_from_subnetwork_axes(ybus)
    end
    model.network_reduction = deepcopy(PNM.get_network_reduction_data(ybus))
    #if !isempty(model.network_reductionget_net_reduction_data)
    # TODO: Network reimplement this when it becomes necessary. We don't have any
    # reductions that are incompatible right now.
    # check_network_reduction_compatibility(T)
    #end
    return
end

function _finalize_network_reduction!(
    model::NetworkModel,
    branch_models::BranchModelContainer,
    number_of_steps::Int,
)
    PNM.populate_branch_maps_by_type!(
        model.network_reduction,
        IOM._get_filters(branch_models),
    )
    # After the reduction is known and the branch maps populated, before the
    # device constructors run: drop branch types fully merged away (else their
    # flow vars/constraints would fail to build) and warn about partial drops.
    _prune_fully_reduced_branch_models!(model, branch_models)
    _warn_partially_reduced_monitored_lines!(model, branch_models)
    _reset_reduced_branch_tracker!(model, number_of_steps)
    return
end

#################################################################################
# AreaBalanceNetworkModel
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{AreaBalanceNetworkModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    _validate_network_and_branches(model, branch_models, sys)
    # `network_reduction` must be populated before `populate_branch_maps_by_type!` and
    # `build_problem!` consume it (AreaBalance applies no bus reduction -> identity map).
    if model.network_reduction === nothing
        model.network_reduction = deepcopy(PNM.get_network_reduction_data(PNM.Ybus(sys)))
    end
    PNM.populate_branch_maps_by_type!(model.network_reduction)
    _reset_reduced_branch_tracker!(model, number_of_steps)
    return
end

#################################################################################
# CopperPlateNetworkModel
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{CopperPlateNetworkModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    _validate_network_and_branches(model, branch_models, sys)
    if isempty(model.subnetworks)
        model.subnetworks = PNM.find_subnetworks(sys)
    end
    # `network_reduction` must always be populated: `build_problem!` reads
    # `network_reduction.bus_reduction_map` and device `add_to_expression!` maps every
    # bus through `get_mapped_bus_number(network_reduction, ...)`. CopperPlate applies no
    # reduction, so this is the identity map (each retained bus -> itself).
    model.network_reduction = deepcopy(PNM.get_network_reduction_data(PNM.Ybus(sys)))
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    _reset_reduced_branch_tracker!(model, number_of_steps)
    return
end

#################################################################################
# AbstractPTDFNetworkModel (PTDFNetworkModel, AreaPTDFNetworkModel)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{<:AbstractPTDFNetworkModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    irreducible_buses = _get_irreducible_buses_due_to_monitored_components(
        sys,
        model,
        branch_models,
    )
    _validate_network_and_branches(model, branch_models, sys)
    if IOM.get_network_matrix(model) === nothing || !isempty(irreducible_buses)
        if IOM.get_network_matrix(model) !== nothing
            @warn "Provided PTDF Matrix is being ignored since irreducible buses were identified because of DLRs. Recalculating PTDF Matrix with PowerNetworkMatrices.PTDF and the identified irreducible buses."
        else
            @info "No PTDF Matrix provided. Calculating using PowerNetworkMatrices.PTDF"
        end

        if model.reduce_radial_branches && model.reduce_degree_two_branches
            @info "Applying both radial and degree two reductions"
            ptdf = PNM.VirtualPTDF(
                sys;
                tol = PTDF_ZERO_TOL,
                network_reductions = PNM.NetworkReduction[
                    PNM.RadialReduction(),
                    PNM.DegreeTwoReduction(),
                ],
                irreducible_buses = irreducible_buses,
            )
        elseif model.reduce_radial_branches
            @info "Applying radial reduction"
            if !isempty(irreducible_buses)
                @warn "Irreducible buses identified due to DLRs. The reduction of any radial branch between 2 irreducible buses wil be ignored"
            end
            ptdf = PNM.VirtualPTDF(
                sys;
                tol = PTDF_ZERO_TOL,
                network_reductions = PNM.NetworkReduction[PNM.RadialReduction()],
                irreducible_buses = irreducible_buses,
            )
        elseif model.reduce_degree_two_branches
            @info "Applying degree two reduction"
            ptdf = PNM.VirtualPTDF(
                sys;
                tol = PTDF_ZERO_TOL,
                network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
                irreducible_buses = irreducible_buses,
            )
        else
            # No radial/degree-two reduction requested, but irreducible buses may
            # still be pinned (e.g. `model_all_branches` MonitoredLines, outages,
            # DLRs). Forward them so the base zero-impedance branch coalescing
            # cannot merge a pinned bus away.
            ptdf = PNM.VirtualPTDF(
                sys;
                tol = PTDF_ZERO_TOL,
                irreducible_buses = irreducible_buses,
            )
        end
        model.network_matrix = ptdf
        model.network_reduction = deepcopy(ptdf.network_reduction_data)
    else
        model.network_reduction = deepcopy(model.network_matrix.network_reduction_data)
    end

    if !model.reduce_radial_branches && PNM.has_radial_reduction(
        PNM.get_reductions(model.network_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided network matrix has reduced radial branches and mismatches the network \
                model specification reduce_radial_branches = false. Set the keyword argument \
                reduce_radial_branches = true in your network model"),
        )
    end
    if !model.reduce_degree_two_branches && PNM.has_degree_two_reduction(
        PNM.get_reductions(model.network_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided network matrix has reduced degree two branches and mismatches the network \
                model specification reduce_degree_two_branches = false. Set the keyword argument \
                reduce_degree_two_branches = true in your network model"),
        )
    end
    if model.reduce_radial_branches &&
       PNM.has_ward_reduction(
        PNM.get_reductions(model.network_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided network matrix has  a ward reduction specified and the keyword argument \
                reduce_radial_branches = true. Set the keyword argument reduce_radial_branches = false \
                or provide a modified network matrix without the Ward reduction."),
        )
    end

    if model.reduce_radial_branches
        @assert !isempty(model.network_matrix.network_reduction_data)
    end
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(model.network_matrix)
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    _maybe_build_modf_matrix!(model, branch_models, sys, irreducible_buses)
    PNM.populate_branch_maps_by_type!(
        model.network_reduction,
        IOM._get_filters(branch_models),
    )
    # After the reduction is known and the branch maps populated, before the
    # device constructors run: drop branch types fully merged away (else their
    # flow vars/constraints would fail to build) and warn about partial drops.
    _prune_fully_reduced_branch_models!(model, branch_models)
    _warn_partially_reduced_monitored_lines!(model, branch_models)
    _reset_reduced_branch_tracker!(model, number_of_steps)
    return
end

"""
Buses retained by `nrd` (reduction representatives — i.e. keys of the bus
reduction map). This is the matrix's bus dimension. PNM's invariant is that
irreducible buses are never eliminated, so they remain keys of the bus
reduction map; the `@assert` here makes that invariant load-bearing instead of
silently papered over with a `union`.
"""
function _retained_buses(nrd::PNM.NetworkReductionData)
    retained = Set(keys(PNM.get_bus_reduction_map(nrd)))
    @assert issubset(PNM.get_irreducible_buses(nrd), retained) "irreducible buses are not a subset of bus_reduction_map keys; PNM reduction invariant violated"
    return retained
end

# Network reductions requested by the model flags. The cohesive bus set is passed
# separately via the `irreducible_buses` kwarg of `VirtualPTDF`/`VirtualMODF`
# (PS6 PNM convention), so the reduction constructors take no arguments here.
function _model_network_reductions(model::NetworkModel)
    reductions = PNM.NetworkReduction[]
    if model.reduce_radial_branches
        push!(reductions, PNM.RadialReduction())
    end
    if model.reduce_degree_two_branches
        push!(reductions, PNM.DegreeTwoReduction())
    end
    return reductions
end

"""
Rebuild PTDF and MODF onto the union of their retained buses when they diverge.
Returns `true` if a rebuild happened; throws if one pass fails to converge them,
since mismatched reductions break the nodal-balance vs. MODF-column dimensions.
"""
function _reconcile_ptdf_modf_reduction!(
    model::NetworkModel{<:AbstractPTDFNetworkModel},
    sys::PSY.System,
)
    ptdf_nrd = PNM.get_network_reduction_data(model.network_matrix)
    modf_nrd = PNM.get_network_reduction_data(IOM.get_contingency_matrix(model))
    retained_ptdf = _retained_buses(ptdf_nrd)
    retained_modf = _retained_buses(modf_nrd)
    retained_ptdf == retained_modf && return false

    @warn "PTDF and MODF reduced to different bus sets \
           (|PTDF retained|=$(length(retained_ptdf)), \
           |MODF retained|=$(length(retained_modf))). Reconciling both onto \
           the cohesive union of retained buses so the nodal-balance and \
           post-contingency dimensions agree."
    cohesive = collect(union(retained_ptdf, retained_modf))
    reductions = _model_network_reductions(model)
    model.network_matrix = PNM.VirtualPTDF(
        sys;
        tol = PTDF_ZERO_TOL,
        network_reductions = reductions,
        irreducible_buses = cohesive,
    )
    model.contingency_matrix = PNM.VirtualMODF(
        sys;
        tol = PTDF_ZERO_TOL,
        network_reductions = reductions,
        irreducible_buses = cohesive,
    )

    if _retained_buses(PNM.get_network_reduction_data(model.network_matrix)) !=
       _retained_buses(PNM.get_network_reduction_data(IOM.get_contingency_matrix(model)))
        throw(
            IS.ConflictingInputsError(
                "PTDF and MODF reductions remain dimensionally inconsistent \
                after one reconciliation pass; aborting build.",
            ),
        )
    end
    return true
end

# Populate the contingency matrix when the template uses an outage-aware
# (security-constrained) branch formulation and one was not provided explicitly.
# The MODF reproduces the PTDF's network reduction (same reductions + irreducible
# buses) so the nodal-balance rows and the post-contingency MODF columns align.
# Then drop outages on SC DeviceModels that PNM couldn't register on the MODF so
# the post-contingency builder doesn't KeyError on them.
function _maybe_build_modf_matrix!(
    model::NetworkModel{<:AbstractPTDFNetworkModel},
    branch_models::BranchModelContainer,
    sys::PSY.System,
    irreducible_buses::Vector{Int64},
)
    IOM._template_has_outage_aware_branch(branch_models) || return
    if IOM.get_contingency_matrix(model) === nothing
        @info "MODF Matrix not provided. Calculating using PowerNetworkMatrices.VirtualMODF"
        reductions = PNM.NetworkReduction[]
        if model.reduce_radial_branches
            push!(reductions, PNM.RadialReduction())
        end
        if model.reduce_degree_two_branches
            push!(reductions, PNM.DegreeTwoReduction())
        end
        model.contingency_matrix = PNM.VirtualMODF(
            sys;
            tol = PTDF_ZERO_TOL,
            network_reductions = reductions,
            irreducible_buses = irreducible_buses,
        )
    end
    # Reconcile PTDF/MODF reductions before outage consolidation populates the
    # branch maps. If a rebuild happened, re-derive the model's network reduction
    # and subnetworks from the rebuilt PTDF so all downstream axes agree.
    if _reconcile_ptdf_modf_reduction!(model, sys)
        model.network_reduction =
            deepcopy(PNM.get_network_reduction_data(model.network_matrix))
        model.subnetworks = _make_subnetworks_from_subnetwork_axes(model.network_matrix)
        if length(model.subnetworks) > 1
            _assign_subnetworks_to_buses(model, sys)
        end
    end
    _consolidate_device_model_outages_with_modf!(
        branch_models,
        IOM.get_contingency_matrix(model),
    )
    return
end

# DCP counterpart of `_maybe_build_modf_matrix!`: populate the contingency
# matrix when the template uses an outage-aware (security-constrained) branch
# formulation, reconcile its reduction against the Ybus-derived one, and drop
# outages PNM could not register. Must run before
# `_finalize_network_reduction!` because reconciliation can replace
# `model.network_reduction`.
function _maybe_build_dcp_modf_matrix!(
    model::NetworkModel{DCPNetworkModel},
    branch_models::BranchModelContainer,
    sys::PSY.System,
    irreducible_buses::Vector{Int64},
)
    IOM._template_has_outage_aware_branch(branch_models) || return
    if IOM.get_contingency_matrix(model) === nothing
        @info "MODF Matrix not provided. Calculating using PowerNetworkMatrices.VirtualMODF"
        model.contingency_matrix = PNM.VirtualMODF(
            sys;
            tol = PTDF_ZERO_TOL,
            network_reductions = _model_network_reductions(model),
            irreducible_buses = irreducible_buses,
        )
    end
    _reconcile_ybus_modf_reduction!(model, sys)
    _consolidate_device_model_outages_with_modf!(
        branch_models,
        IOM.get_contingency_matrix(model),
    )
    return
end

"""
Rebuild the Ybus reduction and the MODF onto the union of their retained buses
when they diverge (the DCP analogue of `_reconcile_ptdf_modf_reduction!`).
Returns `true` if a rebuild happened; throws if one pass fails to converge them,
since mismatched reductions break the nodal-balance vs. MODF-column dimensions.
"""
function _reconcile_ybus_modf_reduction!(
    model::NetworkModel{DCPNetworkModel},
    sys::PSY.System,
)
    modf_nrd = PNM.get_network_reduction_data(IOM.get_contingency_matrix(model))
    retained_ybus = _retained_buses(model.network_reduction)
    retained_modf = _retained_buses(modf_nrd)
    retained_ybus == retained_modf && return false

    @warn "Ybus and MODF reduced to different bus sets \
           (|Ybus retained|=$(length(retained_ybus)), \
           |MODF retained|=$(length(retained_modf))). Reconciling both onto \
           the cohesive union of retained buses so the nodal-balance and \
           post-contingency dimensions agree."
    cohesive = collect(union(retained_ybus, retained_modf))
    reductions = _model_network_reductions(model)
    ybus = PNM.Ybus(
        sys;
        network_reductions = reductions,
        irreducible_buses = cohesive,
    )
    model.contingency_matrix = PNM.VirtualMODF(
        sys;
        tol = PTDF_ZERO_TOL,
        network_reductions = reductions,
        irreducible_buses = cohesive,
    )
    model.network_reduction = deepcopy(PNM.get_network_reduction_data(ybus))
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(ybus)

    if _retained_buses(model.network_reduction) != _retained_buses(
        PNM.get_network_reduction_data(IOM.get_contingency_matrix(model)),
    )
        throw(
            IS.ConflictingInputsError(
                "Ybus and MODF reductions remain dimensionally inconsistent \
                after one reconciliation pass; aborting build.",
            ),
        )
    end
    return true
end
