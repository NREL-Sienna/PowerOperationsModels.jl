#################################### RepresentativeBranch ##################################

const DIRECT_BRANCH_MAP = "direct_branch_map"

# Stand-in bus-name map for builders whose `add_constraints!` signature carries no `sys`
# (the rating/limit families, which never need endpoint names). `_bus_name` errors rather
# than return a wrong name if such a branch is asked for one.
const _NO_BUS_NAMES = Dict{Int, String}()

"""
One branch as the reduction-aware builders see it. Build with
[`_representative_branches`](@ref) (one per arc, for constraint rows) or
[`_all_branches`](@ref) (one per device name, for variables), and iterate with
[`_for_each_branch`](@ref).

`branch` is the direct PSY device or the PNM series/parallel equivalent standing in for the
arc; the surrounding fields carry the arc context (`nr`, `arc`, `reduction`,
`number_to_name`) that the accessors below need and cannot recover from `branch` alone.

Quantities are read through the accessors rather than stored, so a DC build never pays to
compute AC admittances. The `B` parameter is what keeps those accessors inferred: one arc
map can mix direct devices with series/parallel equivalents, so a vector of these is not
concretely typed and must be walked through [`_for_each_branch`](@ref).
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
Apply `f` to each representative branch, specializing it on the entry type.

The vector `reps` is not concretely typed whenever an arc map mixes direct devices with
reduction equivalents, so iterating it inline would read `rep.branch` as `Any` and leave
every accessor — and the JuMP expressions built from them — uninferred. Dispatching through
`f` pays one dynamic dispatch per arc and specializes the whole body, nested time-step loop
included.

    _for_each_branch(reps) do rep
        b = _dc_susceptance(rep)    # inferred
        ...
    end
"""
function _for_each_branch(f::F, reps) where {F}
    for rep in reps
        f(rep)
    end
    return
end

function _make_representative_branch(
    nr::PNM.NetworkReductionData,
    all_branch_maps_by_type::Dict,
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

Every member of a reduced arc shares one set of flow variables, so the arc's physics must
be constrained exactly once; the claim is recorded in the network model's branch tracker so
the guarantee holds across separate `construct_device!` calls. Use [`_all_branches`](@ref)
for variable creation and bound tightening, which visit every device name and claim
nothing.

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
    return [
        _make_representative_branch(
            nr, all_branch_maps_by_type, arc_map, number_to_name, T, name,
        )
        for name in get_branch_argument_constraint_axis(nr, tracker, T, C)
    ]
end

"""
One entry per branch *name* of `T` — every device, including each member of a merged arc,
so no device drops out of the model. Several entries may therefore share an arc and alias
the same underlying JuMP variables.

For variable creation and variable-bound tightening, which must register every device name
and tolerate repeated visits to an arc. Claims no constraint axis: use
[`_representative_branches`](@ref) for constraint rows, which must cover each arc exactly
once.
"""
function _all_branches(
    network_model::NetworkModel,
    ::Type{T};
    number_to_name::Dict{Int, String} = _NO_BUS_NAMES,
) where {T <: PSY.ACTransmission}
    nr = get_network_reduction(network_model)
    arc_map = get_name_to_arc_map_entries(nr, T)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(nr)
    return [
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

"""
Whether this arc is a PNM series/parallel equivalent rather than a single device.
Aggregates carry no per-device data (angle limits, control circuits), so the accessors for
those fall back to defaults.
"""
_is_aggregate(rep::RepresentativeBranch) = _is_aggregate(rep.branch)

# A merged arc keeps the name of one member but is no longer that member alone.
_is_direct(rep::RepresentativeBranch) = rep.reduction == DIRECT_BRANCH_MAP

################################## Electrical ##############################################

_branch_admittance(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch, nr)
_branch_admittance(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.branch_admittance(branch)

_dc_phase_shift(branch::PNM.AbstractReductionAggregate, nr::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch, nr)
_dc_phase_shift(branch::PSY.ACTransmission, ::PNM.NetworkReductionData) =
    PNM.get_series_phase_shift(branch)

"""
Full π-model admittance `(g, b, g_fr, b_fr, g_to, b_to, tap, shift)` for the arc.
"""
_admittance(rep::RepresentativeBranch) = _branch_admittance(rep.branch, rep.nr)

# DC susceptance `1/(tap*x)` — tap-divided, not the r-inclusive π-model susceptance.
_dc_susceptance(rep::RepresentativeBranch) =
    PNM.get_series_susceptance(rep.branch, PSY.SU)
_dc_shift(rep::RepresentativeBranch) = _dc_phase_shift(rep.branch, rep.nr)
_dc_resistance(rep::RepresentativeBranch) = PNM.arc_dc_resistance(rep.nr, rep.arc)

################################## Transformer control #####################################

_get_circuit(t::PSY.TwoWindingTransformer) = PSY.get_circuit(t)
_get_circuit(t::PNM.ThreeWindingTransformerCircuit) = t.circuit
_get_circuit(_) = nothing

_control_objective(::Nothing) = PSY.TransformerControlObjective.UNDEFINED
_control_objective(c::PSY.TransformerCircuit) =
    if PSY.get_available(c)
        PSY.get_control_objective(c)
    else
        PSY.TransformerControlObjective.UNDEFINED
    end

"""
Control objective of the arc's transformer circuit, or `UNDEFINED` for anything that is not
an available controlled transformer.
"""
_control_objective(rep::RepresentativeBranch) = _control_objective(_get_circuit(rep.branch))

_quantity_limits(::Nothing) = (min = -Inf, max = Inf)
_quantity_limits(c::PSY.TransformerCircuit) = PSY.get_controlled_quantity_limits(c)
_quantity_limits(rep::RepresentativeBranch) = _quantity_limits(_get_circuit(rep.branch))

_regulated_number(::Nothing) = -1
_regulated_number(c::PSY.TransformerCircuit) = PSY.get_regulated_bus_number(c)
_regulated_number(rep::RepresentativeBranch) = _regulated_number(_get_circuit(rep.branch))

_tap_controlled(rep::RepresentativeBranch) = _tap_controlled(_control_objective(rep))
_voltage_controlled(rep::RepresentativeBranch) = _voltage_controlled(_control_objective(rep))
_reactive_controlled(rep::RepresentativeBranch) =
    _reactive_controlled(_control_objective(rep))

################################## Ratings and limits ######################################

# Resolve the per-DeviceModel attribute to one of the explicit PNM rating functions.
# `MixedBranchesParallel` ignores the attribute and always uses the plain sum, since the
# constituent branches may carry different DeviceModel preferences and there is no
# defensible way to pick one. The PNM aggregators return system-base values.
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

# System base throughout, matching the per-unit flow variables. The PNM aggregators already
# return system base; a direct device must be read with `PSY.SU` explicitly, since
# `PNM.get_equivalent_rating` on a bare device reads its *device* base (`PSY.DU`).
_branch_rating(d::PSY.ACTransmission, ::DeviceModel) = PSY.get_rating(d, PSY.SU)
_branch_rating(entry::PNM.BranchesSeries, ::DeviceModel) = PNM.get_equivalent_rating(entry)
_branch_rating(entry::PNM.AbstractBranchesParallel, model::DeviceModel) =
    _parallel_branches_rating(model, entry)

"""
Thermal rating of the arc in system base: the device's own rating for a direct branch, the
PNM equivalent for a series arc, and the [`PARALLEL_BRANCH_MAX_RATING_KEY`](@ref)
aggregation for a parallel group.
"""
_branch_rating(rep::RepresentativeBranch, model::DeviceModel) =
    _branch_rating(rep.branch, model)

"""
[`_branch_rating`](@ref) with a zero guard, for the flow limits that would otherwise pin
the arc to zero flow.

Zero is a data error rather than "unlimited" as in MATPOWER-style data: `p² + q² ≤ 0` would
silently delete the branch from the network.
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

function _min_max_flow_limits(entry, model::DeviceModel)
    rating = _branch_rating(entry, model)
    return (min = -rating, max = rating)
end

# `MonitoredLine` carries explicit, possibly asymmetric `flow_limits`; defer to its own
# `get_min_max_limits` instead of the symmetric rating.
_min_max_flow_limits(device::PSY.MonitoredLine, ::DeviceModel) =
    get_min_max_limits(device, FlowRateConstraint, AbstractBranchFormulation)

"""
Symmetric `(min, max)` flow limits from [`_branch_rating`](@ref), except for
`MonitoredLine`, which carries its own possibly asymmetric monitoring limits.
"""
min_max_flow_limits(rep::RepresentativeBranch, model::DeviceModel) =
    _min_max_flow_limits(rep.branch, model)

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

"""
Angle-difference bounds for the arc. Reduction equivalents carry no angle-limit data and
take the same finite ±π/2 default `_angle_limits` uses for devices without the
angle-limits API.
"""
_angle_limits(rep::RepresentativeBranch) =
    _is_aggregate(rep) ? (min = -π / 2, max = π / 2) : _angle_limits(rep.branch)

_constrains_angle_difference(rep::RepresentativeBranch) =
    !_is_aggregate(rep) && _constrains_angle_difference(rep.branch)

# Widest angle excursion the arc allows, the `vad_max` of the LPAC cosine relaxation.
function _max_angle_difference(rep::RepresentativeBranch)
    lims = _angle_limits(rep)
    return max(abs(lims.min), abs(lims.max))
end
