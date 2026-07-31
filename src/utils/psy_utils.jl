_to_is_interval(interval::Dates.Millisecond) =
    interval == UNSET_INTERVAL ? nothing : interval

_to_is_resolution(resolution::Dates.Millisecond) =
    resolution == UNSET_RESOLUTION ? nothing : resolution

function get_available_reservoirs(sys::PSY.System)
    return PSY.get_components(
        x -> (PSY.get_available(x)),
        PSY.HydroReservoir,
        sys,
    )
end

function get_available_turbines(
    d::PSY.HydroReservoir,
    ::Type{U},
) where {U <: Union{TotalHydroPowerReservoirIncoming, TotalHydroFlowRateReservoirIncoming}}
    return filter(
        x -> PSY.get_available(x) && isa(x, PSY.HydroTurbine),
        PSY.get_upstream_turbines(d),
    )
end

function get_available_turbines(
    d::PSY.HydroReservoir,
    ::Type{U},
) where {U <: Union{TotalHydroPowerReservoirOutgoing, TotalHydroFlowRateReservoirOutgoing}}
    return filter(
        x -> PSY.get_available(x) && isa(x, PSY.HydroTurbine),
        PSY.get_downstream_turbines(d),
    )
end

# psy6: a transformer's arc and ratings live on its TransformerCircuit(s), not on the
# parent device — PSY defines no parent-level `get_rating` for either arity.
#
# The modeled arcs of a branch device: the device itself for every one-arc branch, one PNM
# winding wrapper per AVAILABLE circuit for a three-winding transformer. Wrappers, not bare
# `PSY.TransformerCircuit`s, because `PNM.branch_admittance` has no method for the latter —
# and their names ("X_winding_i") are the keys PNM's reduction maps use. Per-circuit
# availability matters: `get_available(t)` is `any` over circuits, so a partly de-energized
# transformer still reaches here, and PNM gives its dead circuits no arc.
_branch_elements(d::PSY.ACTransmission) = (d,)
_branch_elements(d::PSY.ThreeWindingTransformer) = Iterators.filter(
    PSY.get_available,
    ntuple(i -> PNM.ThreeWindingTransformerCircuit(d, i), Val(3)),
)

_element_name(d::PSY.ACTransmission) = PSY.get_name(d)
_element_name(w::PNM.ThreeWindingTransformerCircuit) = PNM.get_name(w)

_branch_rating_b(d::PSY.ACTransmission) = PSY.get_rating_b(d, PSY.SU)
_branch_rating_b(d::PSY.TwoWindingTransformer) =
    PSY.get_rating_b(PSY.get_circuit(d), PSY.SU)
_branch_rating_b(w::PNM.ThreeWindingTransformerCircuit) =
    PSY.get_rating_b(PSY.get_circuit(w), PSY.SU)
