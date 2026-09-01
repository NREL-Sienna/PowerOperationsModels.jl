const VOLTAGE_CONTROL = PSY.TransformerControlObjective.VOLTAGE
const Q_FLOW_CONTROL = PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
const TAP_CONTROLS = (VOLTAGE_CONTROL, Q_FLOW_CONTROL)

const AC_NETWORKS =
    (ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel)
const DC_NETWORKS = (DCPNetworkModel, DCPLLNetworkModel, PTDFNetworkModel)

const CONTROL_FORMULATIONS = (StaticBranch, StaticBranchBounds)

const TRANSFORMER_NAMES = ["Trans1", "Trans2", "Trans3", "Trans4"]

# A controlled-quantity band is objective-shaped: VOLTAGE bands are bus voltage magnitudes,
# REACTIVE_POWER_FLOW bands are terminal flows in per-unit and have to fit inside the
# circuit rating.
_default_quantity_limits(objective) =
    objective === Q_FLOW_CONTROL ? (min = -0.05, max = 0.05) : (min = 0.95, max = 1.05)

const T3W_NAME = "ThreeWindingTransformer_busD"
const T3W_WINDINGS = ["$(T3W_NAME)_winding_$i" for i in 1:3]
const T3W_TERMINALS = (101, 102)
const T3W_STAR_NUMBER = 103

################################### two-winding fixture ################################

function _controlled_sys14(
    objective;
    circuit_index = 1,
    regulated = 9,
    quantity_limits = _default_quantity_limits(objective),
    control_limits = (min = 0.9, max = 1.1),
)
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    name = TRANSFORMER_NAMES[circuit_index]
    transformer = PSY.get_component(PSY.TwoWindingTransformer, sys, name)
    circuit = PSY.get_circuit(transformer)
    PSY.set_control_objective!(circuit, objective)
    PSY.set_regulated_bus_number!(circuit, regulated)
    PSY.set_controlled_quantity_limits!(circuit, quantity_limits)
    PSY.set_control_limits!(circuit, control_limits)
    return (
        sys = sys,
        device = transformer,
        circuit = circuit,
        regulated_name = PSY.get_name(PSY.get_bus(sys, regulated)),
        axis_name = name,
    )
end

_first_three_bus_numbers(sys) =
    [PSY.get_number(b) for b in collect(PSY.get_components(PSY.ACBus, sys))[1:3]]

################################## three-winding fixture ###############################

"""
`c_sys5_ml` plus a three-winding transformer: two new terminal buses carrying a load and a
generator so every winding sees flow, a star bus, and `T3W_NAME` arcing each terminal into
the star. PSB ships no system with a `ThreeWindingTransformer`, so the device is built here;
the topology mirrors the fixture in `test_device_branch_constructors.jl`.

Every bus the transformer touches — the added ones and `nodeD` — gets a `(0.9, 1.1)` voltage
band: the VOLTAGE objective errors unless the bus limits bracket the control band, and the
control bands these tests use are derived from a free solve or from `c_sys14`'s wider
`(0.94, 1.06)`, both of which escape `c_sys5_ml`'s stock `(0.9, 1.05)`.

Both terminal buses carry a generator with a reactive range. Without one at `Bus3WT_1` the
load's reactive draw could only be served across winding 2, pinning that winding's terminal
reactive flow to the load value whatever the tap does — no reactive control objective on it
would be satisfiable.
"""
function _sys5_with_3w()
    sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
    busD = PSY.get_component(PSY.ACBus, sys, "nodeD")
    PSY.set_voltage_limits!(busD, (min = 0.9, max = 1.1))

    function _add_bus!(number, name)
        bus = PSY.ACBus(;
            number = number,
            name = name,
            available = true,
            bustype = PSY.ACBusTypes.PQ,
            angle = 0.0,
            magnitude = 1.0,
            voltage_limits = (min = 0.9, max = 1.1),
            base_voltage = 230.0,
            area = PSY.get_area(busD),
            load_zone = PSY.get_load_zone(busD),
        )
        PSY.add_component!(sys, bus)
        return bus
    end

    terminal_1 = _add_bus!(T3W_TERMINALS[1], "Bus3WT_1")
    terminal_2 = _add_bus!(T3W_TERMINALS[2], "Bus3WT_2")
    star_bus = _add_bus!(T3W_STAR_NUMBER, "Star_Bus_T3W")

    PSY.add_component!(
        sys,
        PSY.PowerLoad(;
            name = "Load_Bus3WT",
            available = true,
            bus = terminal_1,
            active_power = 0.5,
            reactive_power = 0.1,
            base_power = 100.0,
            max_active_power = 0.5,
            max_reactive_power = 0.1,
        ),
    )
    # `Bus3WT_1`'s generator stays small on active power so the load keeps drawing across
    # winding 2.
    function _add_gen!(bus, name, active_max)
        PSY.add_component!(
            sys,
            PSY.ThermalStandard(;
                name = name,
                available = true,
                status = true,
                bus = bus,
                active_power = 0.8 * active_max,
                reactive_power = 0.0,
                rating = 0.5,
                prime_mover_type = PSY.PrimeMovers.ST,
                fuel = PSY.ThermalFuels.COAL,
                active_power_limits = (min = 0.0, max = active_max),
                reactive_power_limits = (min = -0.3, max = 0.3),
                ramp_limits = (up = 0.5, down = 0.5),
                operation_cost = PSY.ThermalGenerationCost(;
                    variable_operation_cost = PSY.CostCurve(PSY.LinearCurve(0.0)),
                    start_up = 0.0,
                    shut_down = 0.0,
                    fixed = 0.0,
                ),
                base_power = 100.0,
                time_limits = nothing,
            ),
        )
    end

    _add_gen!(terminal_1, "Gen_Bus3WT_1", 0.1)
    _add_gen!(terminal_2, "Gen_Bus3WT", 0.5)

    _star_leg(from) = PSY.TransformerCircuit(;
        available = true,
        arc = PSY.Arc(; from = from, to = star_bus),
        r = 0.01,
        x = 0.1,
        rating = 1.0,
        base_power = 100.0,
    )
    PSY.add_component!(
        sys,
        PSY.ThreeWindingTransformer(;
            name = T3W_NAME,
            primary_circuit = _star_leg(busD),
            secondary_circuit = _star_leg(terminal_1),
            tertiary_circuit = _star_leg(terminal_2),
            star_bus = star_bus,
        ),
    )
    return sys
end

function _controlled_sys3w(
    objective;
    circuit_index = 1,
    regulated = nothing,
    quantity_limits = _default_quantity_limits(objective),
    control_limits = (min = 0.9, max = 1.1),
)
    sys = _sys5_with_3w()
    transformer = PSY.get_component(PSY.ThreeWindingTransformer, sys, T3W_NAME)
    circuit = PSY.get_circuits(transformer)[circuit_index]
    # Each winding arcs terminal -> star, so the from-bus is this winding's own terminal.
    number = if isnothing(regulated)
        PSY.get_number(PSY.get_from(PSY.get_arc(circuit)))
    else
        regulated
    end
    PSY.set_control_objective!(circuit, objective)
    PSY.set_regulated_bus_number!(circuit, number)
    PSY.set_controlled_quantity_limits!(circuit, quantity_limits)
    PSY.set_control_limits!(circuit, control_limits)
    return (
        sys = sys,
        device = transformer,
        circuit = circuit,
        regulated_name = PSY.get_name(PSY.get_bus(sys, number)),
        axis_name = T3W_WINDINGS[circuit_index],
    )
end

_t3w_adjacent_bus_numbers(_) = [T3W_TERMINALS..., T3W_STAR_NUMBER]

#################################### case descriptors ##################################

# One entry per transformer arity. Every testset below runs the whole tuple, so the two
# arities stay in lockstep; `circuit_indices` selects which circuit of the device carries
# the control objective (the transformer for two-winding, the winding for three-winding).
const TWO_WINDING_CASE = (
    device_type = PSY.TwoWindingTransformer,
    make = _controlled_sys14,
    plain = () -> PSB.build_system(PSITestSystems, "c_sys14"),
    circuit_indices = 1:length(TRANSFORMER_NAMES),
    axis_names = TRANSFORMER_NAMES,
    voltage_bus_numbers = _first_three_bus_numbers,
)

const THREE_WINDING_CASE = (
    device_type = PSY.ThreeWindingTransformer,
    make = _controlled_sys3w,
    plain = _sys5_with_3w,
    circuit_indices = 1:3,
    axis_names = T3W_WINDINGS,
    voltage_bus_numbers = _t3w_adjacent_bus_numbers,
)

const TRANSFORMER_CASES = (TWO_WINDING_CASE, THREE_WINDING_CASE)

function _controlled_template(
    network_formulation,
    device_type;
    enable = true,
    formulation = StaticBranch,
    kwargs...,
)
    template =
        get_thermal_dispatch_template_network(NetworkModel(network_formulation; kwargs...))
    set_device_model!(
        template,
        DeviceModel(
            device_type,
            formulation;
            attributes = Dict(
                POM.ENABLE_CONTROLS_KEY => enable,
            ),
        ),
    )
    return template
end

function _build_controlled(
    sys,
    network_formulation,
    device_type;
    enable = true,
    optimizer,
    formulation = StaticBranch,
    output_dir = mktempdir(; cleanup = true),
    kwargs...,
)
    template = _controlled_template(
        network_formulation, device_type;
        enable = enable, formulation = formulation, kwargs...,
    )
    model = DecisionModel(template, sys; optimizer = optimizer)
    status = build!(model; output_dir = output_dir)
    return model, status
end
