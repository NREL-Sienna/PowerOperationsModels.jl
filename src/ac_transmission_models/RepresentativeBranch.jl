#################################### RepresentativeBranch ##################################

const DIRECT_BRANCH_MAP = :direct_branch_map
const _NO_BUS_NAMES = Dict{Int, String}()

"""
One branch as the reduction-aware builders see it. Build with
[`_representative_branches`](@ref) (one per arc, for constraint rows) or
[`_all_branches`](@ref) (one per device name, for variables), and iterate with
[`_foreach_branch`](@ref).

`B` is either a PSY.Device, a PNM.AbstractReductionAggregate, or a
PNM.ThreeWindingTransformerCircuit.
"""
struct RepresentativeBranch{B}
    name::String
    arc::Tuple{Int, Int}
    reduction::Symbol
    branch::B
    nr::PNM.NetworkReductionData
    number_to_name::Dict{Int, String}
end

"""
Used for specializing the device loop per concrete RepresentativeBranch.
"""
function _foreach_branch(f::F, reps) where {F}
    for rep in reps
        f(rep)
    end
    return
end

# Concrete-typed for container axes
_branch_names(reps) = String[rep.name for rep in reps]

function _make_representative_branch(
    nr::PNM.NetworkReductionData,
    all_branch_maps_by_type::PNM.BranchMapsByType,
    arc_map,
    number_to_name::Dict{Int, String},
    ::Type{T},
    name::AbstractString,
) where {T <: PSY.ACTransmission}
    (arc, reduction) = arc_map[name]
    return RepresentativeBranch(
        name,
        arc,
        reduction,
        all_branch_maps_by_type[reduction][T][arc],
        nr,
        number_to_name,
    )
end

"""
One [`RepresentativeBranch`](@ref) per reduced arc of `T` not already claimed for the
constraint family `C`, in the axis order the constraint containers must be sized with.

Pass `number_to_name` (from `_retained_number_to_name`) whenever the builder reads endpoint
bus names; builders with no `sys` in scope may omit it.
"""
function _representative_branches(
    network_model::NetworkModel,
    ::Type{T},
    ::Type{C};
    number_to_name::Dict{Int, String} = _NO_BUS_NAMES,
) where {T <: PSY.ACTransmission, C <: ConstraintType}
    catalog = get_branch_catalog(network_model)
    nr = PNM.get_network_reduction_data(catalog)
    tracker = get_reduced_branch_tracker(network_model)
    arc_map = PNM.get_name_to_arc_map(catalog, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(catalog)
    return RepresentativeBranch[
        _make_representative_branch(
            nr, all_branch_maps_by_type, arc_map, number_to_name, T, name,
        )
        for name in get_branch_argument_constraint_axis(catalog, tracker, T, C)
    ]
end

"""
One entry per reduction catalog entry name. Arcs may appear multiple times.
"""
function _all_branches(
    network_model::NetworkModel,
    ::Type{T};
    number_to_name::Dict{Int, String} = _NO_BUS_NAMES,
) where {T <: PSY.ACTransmission}
    catalog = get_branch_catalog(network_model)
    nr = PNM.get_network_reduction_data(catalog)
    arc_map = PNM.get_name_to_arc_map(catalog, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(catalog)
    return RepresentativeBranch[
        _make_representative_branch(
            nr, all_branch_maps_by_type, arc_map, number_to_name, T, name,
        )
        for name in keys(arc_map)
    ]
end

"""
The [`RepresentativeBranch`](@ref) carrying component `name` of type `T`.
A component absorbed into a reduction is redirected to the entry that
represents it.
"""
function _representative_branch(
    network_model::NetworkModel,
    ::Type{T},
    name::AbstractString;
    number_to_name::Dict{Int, String} = _NO_BUS_NAMES,
) where {T <: PSY.ACTransmission}
    catalog = get_branch_catalog(network_model)
    nr = PNM.get_network_reduction_data(catalog)
    arc_map = PNM.get_name_to_arc_map(catalog, T)
    entry_name = if haskey(arc_map, name)
        name
    else
        redirects = get(
            PNM.get_component_to_reduction_name_map(catalog),
            T,
            Dict{String, String}(),
        )
        get(redirects, name, string())
    end
    isempty(entry_name) && error("$(T) \"$(name)\" does not exist in the reduction maps.")
    return _make_representative_branch(
        nr,
        PNM.get_all_branch_maps_by_type(catalog),
        arc_map,
        number_to_name,
        T,
        entry_name,
    )
end

################################## Topology ################################################

_from_number(rep::RepresentativeBranch) = rep.arc[1]
_to_number(rep::RepresentativeBranch) = rep.arc[2]

function _bus_name(rep::RepresentativeBranch, number::Int)
    name = get(rep.number_to_name, number, nothing)
    name === nothing && error(
        "RepresentativeBranch $(rep.name) carries no bus-name map; build it with \
         `number_to_name = _retained_number_to_name(sys, network_model)` to read \
         endpoint bus names.",
    )
    return name
end

_from_name(rep::RepresentativeBranch) = _bus_name(rep, _from_number(rep))
_to_name(rep::RepresentativeBranch) = _bus_name(rep, _to_number(rep))

################################## Electrical ##############################################

_admittance(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch, nr)
_admittance(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch)
_admittance(rep::RepresentativeBranch) = _admittance(rep.branch, rep.nr)

_dc_shift(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch, nr)
_dc_shift(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch)
_dc_shift(rep::RepresentativeBranch) = _dc_shift(rep.branch, rep.nr)

# DC susceptance `1/(tap*x)` — tap-divided, not the r-inclusive π-model susceptance.
_dc_susceptance(rep::RepresentativeBranch) =
    PNM.get_series_susceptance(rep.branch, PSY.SU)
_dc_resistance(rep::RepresentativeBranch) = PNM.arc_dc_resistance(rep.nr, rep.arc)
_dc_shift_injection(rep::RepresentativeBranch) =
    PNM.arc_dc_shift_injection(rep.nr, rep.arc)

################################## Transformer control #####################################

const _VOLTAGE_CONTROL = PSY.TransformerControlObjective.VOLTAGE
const _REACTIVE_CONTROL = PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
const _ACTIVE_CONTROL = PSY.TransformerControlObjective.ACTIVE_POWER_FLOW
const _UNDEFINED_CONTROL = PSY.TransformerControlObjective.UNDEFINED

const _TAP_CONTROLS = (_VOLTAGE_CONTROL, _REACTIVE_CONTROL)
const _PHASE_CONTROLS = (_ACTIVE_CONTROL,)

_supports_tap_control(::NetworkModel{<:NativeACNetworkModel}) = true
_supports_tap_control(::NetworkModel) = false

_supports_phase_control(
    ::NetworkModel{
        <:Union{DCPNetworkModel, AbstractDCPLLNetworkModel, AbstractPTDFNetworkModel},
    },
) = true
_supports_phase_control(::NetworkModel) = false

_get_circuit(t::PSY.TwoWindingTransformer) = PSY.get_circuit(t)
_get_circuit(t::PNM.ThreeWindingTransformerCircuit) = t.circuit
_get_circuit(::Union{PSY.ACTransmission, PNM.AbstractReductionAggregate}) = nothing

_control_objective(::Nothing, ::DeviceModel) = _UNDEFINED_CONTROL
_control_objective(c::PSY.TransformerCircuit, d::DeviceModel) =
    if PSY.get_available(c) && _control_enabled(d)
        PSY.get_control_objective(c)
    else
        PSY.TransformerControlObjective.UNDEFINED
    end
_control_objective(rep::RepresentativeBranch, d::DeviceModel) =
    _control_objective(_get_circuit(rep.branch), d)

function _tap_controlled(
    rep::RepresentativeBranch,
    d::DeviceModel,
    network_model::NetworkModel,
)
    return _supports_tap_control(network_model) &&
           _control_objective(rep, d) in _TAP_CONTROLS
end

function _phase_controlled(
    rep::RepresentativeBranch,
    d::DeviceModel,
    network_model::NetworkModel,
)
    return _supports_phase_control(network_model) &&
           _control_objective(rep, d) in _PHASE_CONTROLS
end

function _controlled_circuit_names(
    branch::Union{PSY.ACTransmission, PNM.ThreeWindingTransformerCircuit},
    device_model::DeviceModel,
    network_model::NetworkModel,
)
    objective = _control_objective(_get_circuit(branch), device_model)
    modeled =
        (objective in _TAP_CONTROLS && _supports_tap_control(network_model)) ||
        (objective in _PHASE_CONTROLS && _supports_phase_control(network_model))
    if modeled
        return [PNM.get_name(branch)]
    end
    return String[]
end
_controlled_circuit_names(
    entry::PNM.AbstractReductionAggregate,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = reduce(
    vcat,
    (
        _controlled_circuit_names(member, device_model, network_model) for
        member in entry
    );
    init = String[],
)
_controlled_circuit_names(
    rep::RepresentativeBranch,
    device_model::DeviceModel,
    network_model::NetworkModel,
) = _controlled_circuit_names(rep.branch, device_model, network_model)

_control_limits(::Nothing) = (min = -Inf, max = Inf)
_control_limits(c::PSY.TransformerCircuit) = PSY.get_control_limits(c)
_control_limits(rep::RepresentativeBranch) = _control_limits(_get_circuit(rep.branch))

_quantity_limits(::Nothing) = (min = -Inf, max = Inf)
_quantity_limits(c::PSY.TransformerCircuit) = PSY.get_controlled_quantity_limits(c)
_quantity_limits(rep::RepresentativeBranch) = _quantity_limits(_get_circuit(rep.branch))

_regulated_number(::Nothing) = -1
_regulated_number(c::PSY.TransformerCircuit) = PSY.get_regulated_bus_number(c)
_regulated_number(rep::RepresentativeBranch) = _regulated_number(_get_circuit(rep.branch))

################################## Ratings and limits ######################################

function _parallel_branches_rating(model::DeviceModel, bp::PNM.BranchesParallel)
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

_parallel_branches_rating(::DeviceModel, mbp::PNM.MixedBranchesParallel) =
    PNM.get_sum_of_max_rating(mbp)

_branch_rating(d::PSY.ACTransmission, ::DeviceModel) = PSY.get_rating(d, PSY.SU)
_branch_rating(t::PSY.TwoWindingTransformer, ::DeviceModel) =
    PSY.get_rating(PSY.get_circuit(t), PSY.SU)
_branch_rating(t::PNM.ThreeWindingTransformerCircuit, ::DeviceModel) =
    PSY.get_rating(t.circuit, PSY.SU)
_branch_rating(entry::PNM.BranchesSeries, ::DeviceModel) = PNM.get_equivalent_rating(entry)
_branch_rating(entry::PNM.AbstractBranchesParallel, model::DeviceModel) =
    _parallel_branches_rating(model, entry)
_branch_rating(rep::RepresentativeBranch, model::DeviceModel) =
    _branch_rating(rep.branch, model)

"""
`_branch_rating` with a zero guard, for the flow limits that would otherwise pin
the arc to zero flow.
"""
function _directional_flow_rating(rep::RepresentativeBranch, model::DeviceModel)
    rating = _branch_rating(rep, model)
    iszero(rating) && error(
        "Branch $(rep.name) has a zero rating; the flow limit would force zero flow. \
         Assign a non-zero thermal rating to it or its member branches, or use an \
         unbounded formulation.",
    )
    return rating
end

function _flow_limits(rep::RepresentativeBranch, model::DeviceModel)
    rating = _branch_rating(rep, model)
    return (min = -rating, max = rating)
end
function _flow_limits(rep::RepresentativeBranch{PSY.MonitoredLine}, model::DeviceModel)
    lims = PSY.get_flow_limits(rep.branch, PSY.SU)
    if lims.from_to != lims.to_from
        @warn "Flow limits in MonitoredLine $(rep.name) aren't equal; the minimum will be used."
    end
    limit = min(_branch_rating(rep, model), lims.from_to, lims.to_from)
    return (min = -limit, max = limit)
end

"""
Post-contingency (emergency) flow limits of the arc. `PNM.get_equivalent_emergency_rating`
covers raw devices, reduction aggregates and three-winding circuits alike — it returns
`rating_b` and falls back to `rating` where `rating_b` is undefined — and is already
system-base per-unit, so it takes no `PSY.SU`.
"""
function _emergency_flow_limits(branch::PSY.ACTransmission)
    rating = PNM.get_equivalent_emergency_rating(branch)
    return (min = -rating, max = rating)
end
_emergency_flow_limits(rep::RepresentativeBranch) = _emergency_flow_limits(rep.branch)

function _min_endpoint_voltage_limit(branch::PSY.ACTransmission)
    arc = PSY.get_arc(branch)
    # bus voltage limits are already per-unit
    vmin_fr = PSY.get_voltage_limits(PSY.get_from(arc)).min
    vmin_to = PSY.get_voltage_limits(PSY.get_to(arc)).min
    return min(vmin_fr, vmin_to)
end
_min_endpoint_voltage_limit(entry::PNM.AbstractReductionAggregate) =
    minimum(_min_endpoint_voltage_limit(member) for member in entry)

"""
Current rating of the arc: apparent-power rating over the lowest endpoint voltage it can
see, so the bound holds across the whole voltage band.
"""
function _current_rating(rep::RepresentativeBranch, model::DeviceModel)
    rate_a = _directional_flow_rating(rep, model)
    vmin = _min_endpoint_voltage_limit(rep.branch)
    vmin <= 0.0 &&
        error("IVR: $(rep.name) has a non-positive endpoint voltage minimum ($vmin)")
    return rate_a / vmin
end

_angle_limits(d::PSY.Line) = PSY.get_angle_limits(d)
_angle_limits(d::PSY.MonitoredLine) = PSY.get_angle_limits(d)
_angle_limits(::Union{PSY.ACTransmission, PNM.AbstractReductionAggregate}) =
    (min = -π / 2, max = π / 2)
_angle_limits(rep::RepresentativeBranch) = _angle_limits(rep.branch)

# A branch constrains the angle difference when it carries angle-limit data (only
# Line / MonitoredLine do) narrower than the PSY default ±π window.
_is_binding_angle_window(lims) = !(lims.min ≈ -π && lims.max ≈ π)
_constrains_angle_difference(::Union{PSY.ACTransmission, PNM.AbstractReductionAggregate}) =
    false
_constrains_angle_difference(d::PSY.Line) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_constrains_angle_difference(d::PSY.MonitoredLine) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_constrains_angle_difference(rep::RepresentativeBranch) =
    _constrains_angle_difference(rep.branch)

# Widest angle excursion the arc allows, the `vad_max` of the LPAC cosine relaxation.
function _max_angle_difference(rep::RepresentativeBranch)
    lims = _angle_limits(rep)
    return max(abs(lims.min), abs(lims.max))
end
