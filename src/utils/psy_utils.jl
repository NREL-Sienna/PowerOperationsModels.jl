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

_branch_rating(d::PSY.ACTransmission) = PSY.get_rating(d, PSY.SU)
_branch_rating(d::PSY.TwoWindingTransformer) =
    PSY.get_rating(PSY.get_circuit(d), PSY.SU)
_branch_rating(d::PNM.ThreeWindingTransformerCircuit) =
    PSY.get_rating(d.circuit, PSY.SU)

_branch_rating_b(d::PSY.ACTransmission) = PSY.get_rating_b(d, PSY.SU)
_branch_rating_b(d::PSY.TwoWindingTransformer) =
    PSY.get_rating_b(PSY.get_circuit(d), PSY.SU)

_negated_rating(rating::Float64) = -rating
_negated_rating(::Nothing) = nothing
