#################################### RepresentativeBranch ##################################

const DIRECT_BRANCH_MAP = "direct_branch_map"
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
    reduction::String
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
    nr = get_network_reduction(network_model)
    tracker = get_reduced_branch_tracker(network_model)
    arc_map = get_name_to_arc_map_entries(nr, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(nr)
    return RepresentativeBranch[
        _make_representative_branch(
            nr, all_branch_maps_by_type, arc_map, number_to_name, T, name,
        )
        for name in get_branch_argument_constraint_axis(nr, tracker, T, C)
    ]
end

"""
One entry per device regardless of reduction. Use for variable container axes.
"""
function _all_branches(
    network_model::NetworkModel,
    ::Type{T};
    number_to_name::Dict{Int, String} = _NO_BUS_NAMES,
) where {T <: PSY.ACTransmission}
    nr = get_network_reduction(network_model)
    arc_map = get_name_to_arc_map_entries(nr, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(nr)
    return RepresentativeBranch[
        _make_representative_branch(
            nr, all_branch_maps_by_type, arc_map, number_to_name, T, name,
        )
        for name in keys(arc_map)
    ]
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

_is_aggregate(::PNM.AbstractReductionAggregate) = true
_is_aggregate(::PSY.ACTransmission) = false
_is_aggregate(rep::RepresentativeBranch) = _is_aggregate(rep.branch)

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

################################## Transformer control #####################################

_implemented_controls(::NetworkModel{<:_TAP_NETWORKS}) = _TAP_CONTROLS
_implemented_controls(::NetworkModel{<:_PHASE_NETWORKS}) = _PHASE_CONTROLS
_implemented_controls(::NetworkModel) = ()

_get_circuit(t::PSY.TwoWindingTransformer) = PSY.get_circuit(t)
_get_circuit(t::PNM.ThreeWindingTransformerCircuit) = t.circuit
_get_circuit(::Union{PSY.ACTransmission, PNM.AbstractReductionAggregate}) = nothing

const _UNDEFINED_CONTROL = PSY.TransformerControlObjective.UNDEFINED

_control_objective(::Nothing, ::DeviceModel) = _UNDEFINED_CONTROL
_control_objective(c::PSY.TransformerCircuit, d::DeviceModel, n::NetworkModel) =
    if PSY.get_available(c) && _control_enabled(d)
        obj = PSY.get_control_objective(c)
        obj in _implemented_controls(n) ? obj : _UNDEFINED_CONTROL
    else
        _UNDEFINED_CONTROL
    end
_control_objective(rep::RepresentativeBranch, d::DeviceModel, n::NetworkModel) =
    _control_objective(_get_circuit(rep.branch), d, n)

const _VOLTAGE_CONTROL = PSY.TransformerControlObjective.VOLTAGE
const _REACTIVE_CONTROL = PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
const _ACTIVE_CONTROL = PSY.TransformerControlObjective.ACTIVE_POWER_FLOW
const _TAP_CONTROLS = (_VOLTAGE_CONTROL, _REACTIVE_CONTROL)
const _PHASE_CONTROLS = (_ACTIVE_CONTROL,)

const _TAP_NETWORKS = NativeACNetworkModel
const _PHASE_NETWORKS = Union{DCPNetworkModel, DCPLLNetworkModel, AbstractPTDFNetworkModel}

_voltage_controlled(rep::RepresentativeBranch, d::DeviceModel) =
    _control_objective(rep, d) === _VOLTAGE_CONTROL
_reactive_controlled(rep::RepresentativeBranch, d::DeviceModel) =
    _control_objective(rep, d) === _REACTIVE_CONTROL
_active_controlled(rep::RepresentativeBranch, d::DeviceModel) =
    _control_objective(rep, d) === _ACTIVE_CONTROL

_tap_controlled(
    rep::RepresentativeBranch,
    d::DeviceModel,
    ::NetworkModel{<:_TAP_NETWORKS},
) = _control_objective(rep, d) in _TAP_CONTROLS
_tap_controlled(::RepresentativeBranch, ::DeviceModel, ::NetworkModel) = false

_phase_controlled(
    rep::RepresentativeBranch,
    d::DeviceModel,
    ::NetworkModel{<:_PHASE_NETWORKS},
) = _control_objective(rep, d) in _PHASE_CONTROLS
_phase_controlled(::RepresentativeBranch, ::DeviceModel, ::NetworkModel) = false

_controlled_circuit_names(
    branch::Union{PSY.ACTransmission, PNM.ThreeWindingTransformerCircuit},
    device_model::DeviceModel,
    network_model::NetworkModel,
) =
    if _control_objective(_get_circuit(branch), device_model) in
       _implemented_controls(network_model)
        [PNM.get_name(branch)]
    else
        String[]
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

# TODO: SC branches don't use the RepBranch API but they need rating_b, so
# move this or change SC to use this API.
_branch_rating_b(d::PSY.ACTransmission) = PSY.get_rating(d, PSY.SU)
_branch_rating_b(t::PSY.TwoWindingTransformer) = PSY.get_rating(PSY.get_circuit(t), PSY.SU)
_branch_rating_b(t::PNM.ThreeWindingTransformerCircuit) = PSY.get_rating(t.circuit, PSY.SU)

"""
[`_branch_rating`](@ref) with a zero guard, for the flow limits that would otherwise pin
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
_angle_limits(::PSY.ACTransmission) = (min = -π / 2, max = π / 2)
_angle_limits(rep::RepresentativeBranch) =
    _is_aggregate(rep) ? (min = -π / 2, max = π / 2) : _angle_limits(rep.branch)

# A branch constrains the angle difference when it carries angle-limit data (only
# Line / MonitoredLine do) narrower than the PSY default ±π window.
_constrains_angle_difference(::PSY.ACTransmission) = false
_constrains_angle_difference(d::PSY.Line) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_constrains_angle_difference(d::PSY.MonitoredLine) =
    _is_binding_angle_window(PSY.get_angle_limits(d))
_is_binding_angle_window(lims) = !(lims.min ≈ -π && lims.max ≈ π)

_constrains_angle_difference(rep::RepresentativeBranch) =
    !_is_aggregate(rep) && _constrains_angle_difference(rep.branch)

# Widest angle excursion the arc allows, the `vad_max` of the LPAC cosine relaxation.
function _max_angle_difference(rep::RepresentativeBranch)
    lims = _angle_limits(rep)
    return max(abs(lims.min), abs(lims.max))
end
