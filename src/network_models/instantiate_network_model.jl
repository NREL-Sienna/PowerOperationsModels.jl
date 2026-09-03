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
    for removed in values(
        PNM.get_bus_reduction_map(get_network_reduction(network_model)),
    )
        union!(merged_buses, removed)
    end
    isempty(merged_buses) && return
    name_to_arc_maps = PNM.get_name_to_arc_maps(get_branch_catalog(network_model))
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
    removed_arcs = PNM.get_removed_arcs(get_network_reduction(network_model))
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

_is_default_source(::IOM.DefaultNetworkSource) = true
_is_default_source(::IOM.AbstractNetworkSource) = false

# A formulation that never consults the reduction would compute the requested one and then
# ignore it, so accepting a source silently discards the caller's input. Erroring restores
# the guarantee the dedicated CopperPlate/AreaBalance methods used to give by construction.
function _validate_network_source(
    ::Type{T},
    source::IOM.AbstractNetworkSource,
) where {T <: AbstractNetworkModel}
    honors_network_reduction(T) && return
    _is_default_source(source) && return
    throw(
        IS.ConflictingInputsError(
            "$(T) aggregates the power balance and resolves injections by area or reference \
            bus, so it never consults a network reduction. The supplied \
            $(nameof(typeof(source))) would be computed and then ignored. Drop \
            `network_source` from the NetworkModel, or pick a formulation that models \
            individual buses.",
        ),
    )
end

function _validate_network_and_branches(
    model::NetworkModel{T},
    branch_models::BranchModelContainer,
    sys::PSY.System,
) where {T <: AbstractNetworkModel}
    unmodeled = _get_unmodeled_branch_types(branch_models, sys)
    IOM._check_branch_network_compatibility(model, unmodeled)
    _validate_network_source(T, get_network_source(model))
    return
end

#################################################################################
# Shared derivation steps
#################################################################################

# The single reduction decision for the whole build. Subnetworks always fall out of
# the Ybus, so they are assigned unconditionally — nothing can have set them.
function _reduced_ybus!(
    model::NetworkModel,
    sys::PSY.System,
    exceptions::Vector{Int},
)
    ybus = _source_ybus(get_network_source(model), sys, exceptions)
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(ybus)
    return ybus
end

# Every PTDF-family matrix wraps one of these, so the tolerance and uuid are set once.
_factor_core(
    ybus::PNM.Ybus,
    sys::PSY.System,
    tolerance::Union{Float64, PNM.AutoTolerance},
) =
    PNM.VirtualFactorCore(ybus; tol = tolerance, system_uuid = PSY.get_system_uuid(sys))

_model_factor_core(ybus::PNM.Ybus, model::NetworkModel, sys::PSY.System) =
    _factor_core(ybus, sys, _source_tolerance(get_network_source(model)))

#=
The one source-aware Ybus resolution, dispatched on the source so every formulation
family gets it. A source that derives the network from the system applies the build's
reduction exceptions; a prebuilt source already fixed its reduction before the template
was known, so its Ybus is reproduced from that reduction and the exceptions are validated
against it instead. Families that cannot consume a prebuilt sensitivity matrix still
honour the reduction it carries.
=#
function _source_ybus(
    source::IOM.AbstractNetworkSource,
    sys::PSY.System,
    exceptions::Vector{Int},
)
    _warn_ignored_radial_exceptions(source, exceptions)
    return _build_ybus(source, sys, exceptions)
end

_prebuilt_reduction(source::PrebuiltMatrixSource) =
    PNM.get_network_reduction_data(PNM.get_core(get_matrix(source)))
_prebuilt_reduction(source::PrebuiltCoreSource) =
    PNM.get_network_reduction_data(get_core(source))

function _source_ybus(
    source::Union{PrebuiltMatrixSource, PrebuiltCoreSource},
    sys::PSY.System,
    exceptions::Vector{Int},
)
    reduction = _prebuilt_reduction(source)
    _validate_prebuilt_exceptions(reduction, exceptions)
    return _prebuilt_ybus(source, reduction, sys)
end

function _warn_ignored_radial_exceptions(
    source::IOM.AbstractNetworkSource,
    exceptions::Vector{Int},
)
    isempty(exceptions) && return
    any(_is_radial_reduction, _source_reductions(source)) || return
    @warn "Irreducible buses identified. The reduction of any radial branch between 2 irreducible buses will be ignored"
    return
end

# A prebuilt source fixes the reduction before the template is known, so the buses the
# template pins cannot be honored. Erroring here rather than warning: a pinned bus that
# was already eliminated makes every contingency and time-varying rating on it silently
# unenforceable.
function _validate_prebuilt_exceptions(
    reduction::PNM.NetworkReductionData,
    exceptions::Vector{Int},
)
    isempty(exceptions) && return
    dropped = setdiff(exceptions, keys(PNM.get_bus_reduction_map(reduction)))
    isempty(dropped) && return
    throw(
        IS.ConflictingInputsError(
            "The prebuilt network source eliminated buses $(sort!(collect(dropped))), which \
            the template pins as reduction exceptions (outage-monitored components or \
            time-varying branch ratings). Rebuild the matrix with these buses passed as \
            `irreducible_buses`, or pass a `SystemNetworkSource` so the build derives the \
            reduction itself.",
        ),
    )
end

# A prebuilt source fixed the reduction before the build, so its Ybus is reproduced from
# the source's own reduction rather than from the model. The result is checked against
# that reduction: anything the spec cannot reproduce must fail loudly rather than hand
# downstream code a Ybus describing a different network than the matrices do.
function _prebuilt_ybus(
    source::IOM.AbstractNetworkSource,
    reduction::PNM.NetworkReductionData,
    sys::PSY.System,
)
    ybus = _build_ybus(
        SystemNetworkSource(_source_reductions(source)),
        sys,
        _source_irreducible_buses(reduction),
    )
    reproduced = PNM.get_network_reduction_data(ybus)
    if PNM.get_bus_reduction_map(reproduced) != PNM.get_bus_reduction_map(reduction)
        throw(
            IS.ConflictingInputsError(
                "The Ybus rebuilt from the prebuilt network source's reduction retained a \
                different bus set than the source itself ($(length(PNM.get_bus_reduction_map(reproduced))) \
                vs $(length(PNM.get_bus_reduction_map(reduction))) buses). The source's \
                reduction is not reproducible from its recorded reduction spec; build the \
                matrices from a `SystemNetworkSource` instead.",
            ),
        )
    end
    return ybus
end

# Derive the MODF only when the template uses an outage-aware branch formulation.
# Registration is template-scoped to match the reduction exceptions: a contingency
# whose buses were not pinned must not be registered, or it would resolve to no arc
# modifications and silently return the unmodified base row.
function _derive_contingency_matrix(
    core::PNM.VirtualFactorCore,
    sys::PSY.System,
    branch_models::BranchModelContainer,
)
    modf = PNM.VirtualMODF(
        core,
        sys;
        automatically_register_outages = false,
    )
    registered = PNM.get_registered_contingencies(modf)
    for m in values(branch_models)
        IOM.supports_outages(get_formulation(m)) || continue
        for outage_id in keys(get_outages(m))
            # The same outage can be attached to several branch DeviceModels.
            haskey(registered, outage_id) && continue
            PNM._register_outage!(
                modf,
                sys,
                PSY.get_supplemental_attribute(sys, outage_id),
            )
        end
    end
    _consolidate_device_model_outages_with_modf!(branch_models, modf)
    return modf
end

"""
This build's branch index. The template's branch filters restrict which branches get flow
variables -- an optimization concern, so it lives in the build's catalog rather than in the
reduction, which stays exactly as the matrix produced it.

An unfiltered template reuses the matrix's own catalog; there is nothing to restrict.
"""
function _build_catalog(matrix, branch_models::BranchModelContainer)
    base = PNM.get_branch_catalog(matrix)
    filters = IOM._get_filters(branch_models)
    isempty(filters) && return base
    # `IOM._get_filters` hands back a `Dict{DataType, Function}`, so the call through it cannot
    # be inferred. Pinning the result to `Bool` keeps that `Any` from leaking into
    # `_entry_matches`, which PNM folds over every branch while building the catalog.
    function _passes_filter(T, component)
        if haskey(filters, T)
            return filters[T](component)::Bool
        else
            return true
        end
    end
    return PNM.BranchCatalog(
        PNM.get_network_reduction_data(base),
        _passes_filter,
    )
end

function _finalize_network_reduction!(
    model::NetworkModel,
    branch_models::BranchModelContainer,
    number_of_steps::Int,
)
    # After the network data is set, before the
    # device constructors run: drop branch types fully merged away (else their
    # flow vars/constraints would fail to build) and warn about partial drops.
    _prune_fully_reduced_branch_models!(model, branch_models)
    _warn_partially_reduced_monitored_lines!(model, branch_models)
    _reset_reduced_branch_tracker!(model, number_of_steps)
    return
end

#################################################################################
# Ybus-only families (ACP, ACR, IVR, LPACC, NFA, CopperPlate, AreaBalance, ...)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{T},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
) where {T <: AbstractNetworkModel}
    _validate_network_and_branches(model, branch_models, sys)
    exceptions = _collect_reduction_exceptions(sys, model, branch_models)
    ybus = _reduced_ybus!(model, sys, exceptions)
    IOM.set_network_data!(
        model,
        YbusNetworkData(ybus, _build_catalog(ybus, branch_models)),
    )
    _finalize_network_reduction!(model, branch_models, number_of_steps)
    return
end

#################################################################################
# DCPNetworkModel — Ybus plus an optional MODF over the Ybus's own factorization
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{DCPNetworkModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    _validate_network_and_branches(model, branch_models, sys)
    exceptions = _collect_reduction_exceptions(sys, model, branch_models)
    ybus = _reduced_ybus!(model, sys, exceptions)
    catalog = _build_catalog(ybus, branch_models)
    if IOM._template_has_outage_aware_branch(branch_models)
        core = _model_factor_core(ybus, model, sys)
        IOM.set_network_data!(
            model,
            DCPNetworkData(
                ybus,
                _derive_contingency_matrix(core, sys, branch_models),
                catalog,
            ),
        )
    else
        IOM.set_network_data!(model, DCPNetworkData(ybus, catalog))
    end
    _finalize_network_reduction!(model, branch_models, number_of_steps)
    return
end

#################################################################################
# AbstractPTDFNetworkModel (PTDFNetworkModel, AreaPTDFNetworkModel)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{T},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
) where {T <: AbstractPTDFNetworkModel}
    _validate_network_and_branches(model, branch_models, sys)
    exceptions = _collect_reduction_exceptions(sys, model, branch_models)
    IOM.set_network_data!(
        model,
        _ptdf_network_data(
            get_network_source(model),
            model,
            sys,
            branch_models,
            exceptions,
        ),
    )
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    _finalize_network_reduction!(model, branch_models, number_of_steps)
    return
end

# Sources that derive the network from the system: PTDF and MODF wrap the same core, so
# their reductions cannot diverge.
function _ptdf_network_data(
    ::IOM.AbstractNetworkSource,
    model::NetworkModel,
    sys::PSY.System,
    branch_models::BranchModelContainer,
    exceptions::Vector{Int},
)
    ybus = _reduced_ybus!(model, sys, exceptions)
    core = _model_factor_core(ybus, model, sys)
    return _assemble_ptdf_data(core, PNM.VirtualPTDF(core), sys, branch_models)
end

function _ptdf_network_data(
    source::PrebuiltCoreSource,
    model::NetworkModel,
    sys::PSY.System,
    branch_models::BranchModelContainer,
    exceptions::Vector{Int},
)
    core = get_core(source)
    _reduced_ybus!(model, sys, exceptions)
    return _assemble_ptdf_data(core, PNM.VirtualPTDF(core), sys, branch_models)
end

# A prebuilt VirtualPTDF supplies both the core and its populated row cache, so it is
# reused as the PTDF wrapper rather than a fresh VirtualPTDF(core).
function _ptdf_network_data(
    source::PrebuiltMatrixSource,
    model::NetworkModel,
    sys::PSY.System,
    branch_models::BranchModelContainer,
    exceptions::Vector{Int},
)
    matrix = get_matrix(source)
    core = PNM.get_core(matrix)
    # Called for its reproducibility validation against the source's reduction; the
    # Ybus itself is not stored (nothing downstream reads it for this family).
    _source_ybus(source, sys, exceptions)
    # Subnetworks come from the matrix, not the Ybus, because the matrix's own axes are
    # what the PTDF rows are indexed on.
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(matrix)
    return _assemble_ptdf_data(core, matrix, sys, branch_models)
end

function _assemble_ptdf_data(
    core::PNM.VirtualFactorCore,
    ptdf,
    sys::PSY.System,
    branch_models::BranchModelContainer,
)
    catalog = _build_catalog(core, branch_models)
    if IOM._template_has_outage_aware_branch(branch_models)
        return PTDFNetworkData(
            ptdf,
            _derive_contingency_matrix(core, sys, branch_models),
            catalog,
        )
    end
    return PTDFNetworkData(ptdf, catalog)
end
