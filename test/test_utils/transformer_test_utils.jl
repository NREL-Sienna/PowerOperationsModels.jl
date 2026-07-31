# Hand-built transformer fixtures. No PowerSystemCaseBuilder system carries a
# `ThreeWindingTransformer`, a nonzero `magnetizing_shunt`, or a circuit `base_power`
# different from the system base, so every test needing one builds it here.

"""
Add a `ThreeWindingTransformer` to `sys`, wiring `primary_bus` (an existing bus) to two
fresh terminal buses through a fresh star bus.

Each circuit runs terminal -> star. `α_secondary` puts a phase shift on the secondary
winding; `rating_tertiary = nothing` (the default) exercises the unrated path, since PSS/E
`RATE = 0` parses to `nothing` and means genuinely unlimited.

Returns the transformer.
"""
function add_three_winding_transformer!(
    sys::PSY.System,
    primary_bus::PSY.ACBus;
    name::String = "T3W",
    α_secondary::Float64 = 0.0,
    tap_primary::Float64 = 1.0,
    rating_tertiary::Union{Nothing, Float64} = nothing,
    base_number::Int = 900,
)
    function _bus(number, bus_name)
        b = PSY.ACBus(;
            number = number,
            name = bus_name,
            available = true,
            bustype = PSY.ACBusTypes.PQ,
            angle = 0.0,
            magnitude = 1.0,
            voltage_limits = (min = 0.9, max = 1.1),
            base_voltage = PSY.get_base_voltage(primary_bus),
            area = PSY.get_area(primary_bus),
            load_zone = PSY.get_load_zone(primary_bus),
        )
        PSY.add_component!(sys, b)
        return b
    end

    star_bus = _bus(base_number, "$(name)_star")
    sec_bus = _bus(base_number + 1, "$(name)_sec")
    ter_bus = _bus(base_number + 2, "$(name)_ter")

    circuit(from, r, x; tap = 1.0, α = 0.0, rating = 1.0) = PSY.TransformerCircuit(;
        available = true,
        arc = PSY.Arc(; from = from, to = star_bus),
        tap = tap,
        α = α,
        r = r,
        x = x,
        rating = rating,
        base_power = PSY.get_base_power(sys, PSY.NU),
    )

    transformer = PSY.ThreeWindingTransformer(;
        name = name,
        primary_circuit = circuit(primary_bus, 0.01, 0.10; tap = tap_primary),
        secondary_circuit = circuit(sec_bus, 0.01, 0.12; α = α_secondary),
        tertiary_circuit = circuit(ter_bus, 0.01, 0.15; rating = rating_tertiary),
        star_bus = star_bus,
    )
    PSY.add_component!(sys, transformer)
    return transformer
end

"""
Per-winding element names PNM (and therefore every POM container axis) uses for `t`.
"""
three_winding_names(t::PSY.ThreeWindingTransformer) =
    ["$(PSY.get_name(t))_winding_$i" for i in 1:3]
