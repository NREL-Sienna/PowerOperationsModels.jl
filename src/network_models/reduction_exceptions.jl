#=
Buses that must survive PNM network reductions because something the template models
is pinned to them. One rule per method, dispatched on the DeviceModel, so a new rule
is a new method rather than another branch in a growing loop.

This set is the sole authority on reduction exceptions: the buses the caller pinned on the
`NetworkModel` plus the buses these rules derive. PNM's own `_collect_protected_buses`
protects every system Outage; this protects only what the template actually models, so a
contingency the model never enforces cannot block a reduction.
=#

function _push_component_buses!(buses::Set{Int}, branch::PSY.Branch)
    arc = PSY.get_arc(branch)
    push!(buses, PSY.get_number(PSY.get_from(arc)))
    push!(buses, PSY.get_number(PSY.get_to(arc)))
    return
end

function _push_component_buses!(buses::Set{Int}, branch::PSY.ThreeWindingTransformer)
    for arc in (
        PSY.get_primary_star_arc(branch),
        PSY.get_secondary_star_arc(branch),
        PSY.get_tertiary_star_arc(branch),
    )
        push!(buses, PSY.get_number(PSY.get_from(arc)))
        push!(buses, PSY.get_number(PSY.get_to(arc)))
    end
    return
end

function _push_component_buses!(buses::Set{Int}, device::PSY.StaticInjection)
    push!(buses, PSY.get_number(PSY.get_bus(device)))
    return
end

function _push_component_buses!(buses::Set{Int}, bus::PSY.ACBus)
    PSY.get_available(bus) && push!(buses, PSY.get_number(bus))
    return
end

# AreaInterchange <: PSY.Branch but connects Areas, so it has no arc and the PSY.Branch
# method above would error on PSY.get_arc. Reachable: `_pin_outage_buses!` iterates
# `get_associated_components` unfiltered.
function _push_component_buses!(::Set{Int}, ::PSY.AreaInterchange)
    return
end

# Warn-skip instead of MethodError so this set stays reconcilable with PNM's
# `_accumulate_protected_buses!(::PSY.Component)`, which also warn-skips.
function _push_component_buses!(::Set{Int}, c::PSY.Component)
    @warn "Outage-monitored component $(typeof(c)) ($(PSY.get_name(c))) has no \
           reduction-protection rule; its bus is not pinned and may be reduced away, so \
           its contingency will not be enforced. Add a _push_component_buses! method \
           for this type if it should be protected." maxlog = 5
    return
end

function _collect_reduction_exceptions(
    sys::PSY.System,
    model::NetworkModel,
    branch_models::BranchModelContainer,
)
    @debug "Collecting reduction exceptions" _group =
        IOM.LOG_GROUP_NETWORK_CONSTRUCTION
    # Seeded with the caller's own exceptions; the template's rules add to them.
    buses = Set{Int}(get_reduction_exceptions(model))
    _pin_dc_converter_buses!(buses, sys)
    for m in values(branch_models)
        _pin_irreducible_buses!(buses, m, sys)
    end
    return collect(buses)
end

# Rule 0: a converter's AC terminal must survive the reduction. Merging one away drops the
# converter from the model without a word, so this is keyed on the system rather than on a
# DeviceModel — the exposure exists whether or not the template happens to model the
# converter's type. Unconditional, unlike PowerFlows' matching set, which skips `g == 0`
# VSC lines because it treats an open DC link as unmodelable; POM builds device models for
# whatever the template declares and has no such exclusion.
function _pin_dc_converter_buses!(buses::Set{Int}, sys::PSY.System)
    for line in PSY.get_available_components(PSY.TwoTerminalVSCLine, sys)
        _push_component_buses!(buses, line)
    end
    for converter in PSY.get_available_components(PSY.InterconnectingConverter, sys)
        _push_component_buses!(buses, converter)
    end
    return
end

_pin_irreducible_buses!(::Set{Int}, ::DeviceModel, ::PSY.System) = nothing

function _pin_irreducible_buses!(
    buses::Set{Int},
    m::DeviceModel{T},
    sys::PSY.System,
) where {T <: PSY.ACTransmission}
    _pin_time_series_branch_buses!(buses, m, sys)
    _pin_outage_buses!(buses, m, sys)
    return
end

function _pin_irreducible_buses!(
    buses::Set{Int},
    m::DeviceModel{PSY.MonitoredLine},
    sys::PSY.System,
)
    _pin_time_series_branch_buses!(buses, m, sys)
    _pin_outage_buses!(buses, m, sys)
    _pin_model_all_branches!(buses, m)
    return
end

# Rule 1: a branch carrying a rating time series pins both its endpoints, so the
# reduction cannot merge away the bus a time-varying limit is applied at.
function _pin_time_series_branch_buses!(
    ::Set{Int},
    m::DeviceModel{PSY.ThreeWindingTransformer},
    ::PSY.System,
)
    haskey(get_time_series_names(m), BranchRatingTimeSeriesParameter) ||
        return
    _warn_three_winding_rating_unsupported()
    return
end

function _pin_time_series_branch_buses!(
    buses::Set{Int},
    m::DeviceModel{T},
    sys::PSY.System,
) where {T <: PSY.ACTransmission}
    ts_names = get_time_series_names(m)
    haskey(ts_names, BranchRatingTimeSeriesParameter) || return
    ts_name = ts_names[BranchRatingTimeSeriesParameter]
    # TODO workaround since we dont have the container
    ts_type = PSY.Deterministic
    for branch in PSY.get_available_components(T, sys)
        PSY.has_time_series(branch, ts_type, ts_name) || continue
        _push_component_buses!(buses, branch)
    end
    return
end

function _warn_three_winding_rating_unsupported()
    @warn "Dynamic branch ratings for ThreeWindingTransformers are not implemented yet. Skipping it."
    return
end

# Rule 2: an outage registered on an outage-aware branch model pins both its
# monitored and its outaged endpoints. The MODF column for a contingency is keyed by
# the outaged arc's endpoints, and post-contingency flow constraints reference the
# monitored components' real bus numbers.
function _pin_outage_buses!(buses::Set{Int}, m::DeviceModel, sys::PSY.System)
    IOM.supports_outages(get_formulation(m)) || return
    for outage_uuid in keys(get_outages(m))
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
            _push_component_buses!(buses, component)
        end
        for component in PSY.get_associated_components(sys, outage)
            _push_component_buses!(buses, component)
        end
    end
    return
end

# Rule 3: a `model_all_branches` MonitoredLine model pins its lines so zero-impedance
# ones survive the reduction instead of being merged away.
function _pin_model_all_branches!(
    buses::Set{Int},
    m::DeviceModel{PSY.MonitoredLine},
)
    get_attribute(m, MODEL_ALL_BRANCHES_KEY) === true || return
    for branch in get_device_cache(m)
        _push_component_buses!(buses, branch)
    end
    return
end
