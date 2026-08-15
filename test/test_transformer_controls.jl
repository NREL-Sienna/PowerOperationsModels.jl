#########################################################################################
# Transformer tap controls: every `TransformerControlObjective` other than FIXED /
# UNDEFINED. Control is opted into per `DeviceModel` with the `enable_controls` attribute;
# when it is on, each `TransformerCircuit`'s `control_objective` decides what is built.
# A controlled circuit gets a `TapRatioVariable` bounded by `control_limits`, and the
# controlled quantity is held inside `controlled_quantity_limits`.
#
# Fixed / off-nominal tap physics (tap as a constant component property) lives in
# `test_transformer_fixed_tap.jl` — do not duplicate it here.
#########################################################################################

const VOLTAGE_CONTROL = PSY.TransformerControlObjective.VOLTAGE
const Q_FLOW_CONTROL = PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
const P_FLOW_CONTROL = PSY.TransformerControlObjective.ACTIVE_POWER_FLOW

_control_attributes(enable::Bool) =
    Dict{String, Any}(POM.ENABLE_CONTROLS_KEY => enable)

"""
`c_sys14` with one transformer circuit put under `objective`. `regulated` picks which end
of the circuit's arc is regulated (the bus number, not a sentinel — the API takes the
number of either the from or the to bus). Returns the system, the transformer, its
circuit, and the regulated bus name.
"""
function _controlled_sys14(
    objective;
    name = "Trans1",
    regulated = :to,
    # c_sys14 buses carry (0.94, 1.06) voltage limits; a VOLTAGE band has to sit inside
    # the regulated bus's own limits.
    quantity_limits = (min = 0.95, max = 1.05),
    control_limits = (min = 0.9, max = 1.1),
)
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    transformer = PSY.get_component(PSY.TwoWindingTransformer, sys, name)
    circuit = PSY.get_circuit(transformer)
    arc = PSY.get_arc(circuit)
    bus = regulated == :from ? PSY.get_from(arc) : PSY.get_to(arc)
    PSY.set_control_objective!(circuit, objective)
    PSY.set_regulated_bus_number!(circuit, PSY.get_number(bus))
    PSY.set_controlled_quantity_limits!(circuit, quantity_limits)
    PSY.set_control_limits!(circuit, control_limits)
    return sys, transformer, circuit, PSY.get_name(bus)
end

function _controlled_template(
    network_formulation;
    enable = true,
    formulation = StaticBranch,
    kwargs...,
)
    template =
        get_thermal_dispatch_template_network(NetworkModel(network_formulation; kwargs...))
    set_device_model!(
        template,
        DeviceModel(
            PSY.TwoWindingTransformer,
            formulation;
            attributes = _control_attributes(enable),
        ),
    )
    return template
end

function _build_controlled(
    sys,
    network_formulation;
    enable = true,
    optimizer,
    formulation = StaticBranch,
    kwargs...,
)
    template = _controlled_template(
        network_formulation; enable = enable, formulation = formulation, kwargs...,
    )
    model = DecisionModel(template, sys; optimizer = optimizer)
    status = build!(model; output_dir = mktempdir(; cleanup = true))
    return model, status
end

_has_tap_variable(container) =
    any(k -> occursin("TapRatioVariable", string(k)), keys(IOM.get_variables(container)))

################################### attribute plumbing #################################

@testset "enable_controls is a transformer-only attribute defaulting to false" begin
    for T in (PSY.TwoWindingTransformer, PSY.ThreeWindingTransformer)
        attributes = POM.get_default_attributes(T, StaticBranch)
        @test haskey(attributes, POM.ENABLE_CONTROLS_KEY)
        @test attributes[POM.ENABLE_CONTROLS_KEY] === false
    end
    # Non-transformer branches carry no control switch at all.
    @test !haskey(
        POM.get_default_attributes(PSY.Line, StaticBranch),
        POM.ENABLE_CONTROLS_KEY,
    )

    # The attribute survives onto the DeviceModel and merges with the other defaults.
    device_model = DeviceModel(
        PSY.TwoWindingTransformer,
        StaticBranch;
        attributes = _control_attributes(true),
    )
    @test IOM.get_attribute(device_model, POM.ENABLE_CONTROLS_KEY) === true
    @test IOM.get_attribute(device_model, POM.PARALLEL_BRANCH_MAX_RATING_KEY) ==
          "single_element_contingency"
end

@testset "a controlled circuit builds no tap variable while enable_controls is off" begin
    sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL)
    model, status =
        _build_controlled(sys, ACPNetworkModel; enable = false, optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test !_has_tap_variable(IOM.get_optimization_container(model))
end

@testset "TapRatioVariable is created only for controlled circuits, bounded by control_limits" begin
    limits = (min = 0.95, max = 1.05)
    sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; control_limits = limits)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
    # Trans2 / Trans3 are left UNDEFINED, so only the controlled circuit gets a variable.
    @test axes(tap)[1] == ["Trans1"]
    @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
    for v in tap
        @test JuMP.lower_bound(v) == limits.min
        @test JuMP.upper_bound(v) == limits.max
    end
end

@testset "REACTIVE_POWER_FLOW control also creates a tap variable" begin
    sys, _, _, _ = _controlled_sys14(Q_FLOW_CONTROL)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test axes(IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer))[1] ==
          ["Trans1"]
end

@testset "ACTIVE_POWER_FLOW is a phase-shift objective, not a tap control" begin
    # The tap controls cover the voltage / reactive-power objectives; an active-power
    # (phase-shifting) circuit must not silently acquire a tap variable.
    sys, _, _, _ = _controlled_sys14(P_FLOW_CONTROL)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test !_has_tap_variable(IOM.get_optimization_container(model))
end

@testset "a DISABLED objective builds no control" begin
    sys, _, _, _ =
        _controlled_sys14(PSY.TransformerControlObjective.VOLTAGE_DISABLED)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test !_has_tap_variable(IOM.get_optimization_container(model))
end

################################### VOLTAGE objective ##################################

# Solve `c_sys14` once with the transformer uncontrolled and report the regulated bus
# voltage, so each control test can aim its band away from the free-running solution and
# prove the constraint actually bites.
function _uncontrolled_voltage(bus_name; network_formulation = ACPNetworkModel)
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    model, status =
        _build_controlled(
            sys,
            network_formulation;
            enable = false,
            optimizer = ipopt_optimizer,
        )
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
    return vm[1, bus_name]
end

@testset "VOLTAGE control holds the regulated bus inside its band (ACP, to-side)" begin
    _, _, _, bus_name = _controlled_sys14(VOLTAGE_CONTROL)
    free_vm = _uncontrolled_voltage(bus_name)
    # A band the free-running solution violates, so holding it requires the tap to move.
    # It sits below `free_vm`: the free-running voltage rides near the bus's 1.06 upper
    # limit, and the band may not reach outside the bus's own limits.
    band = (min = free_vm - 0.02, max = free_vm - 0.01)

    sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; quantity_limits = band)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
    @test bus_name in names(vm)
    for r in 1:nrow(vm)
        @test vm[r, bus_name] >= band.min - 1e-6
        @test vm[r, bus_name] <= band.max + 1e-6
    end
    # The band is on the voltage itself, not on its square.
    @test !(free_vm >= band.min - 1e-6 && free_vm <= band.max + 1e-6)

    tap = read_variable(
        res, "TapRatioVariable__TwoWindingTransformer"; table_format = TableFormat.WIDE,
    )
    for r in 1:nrow(tap)
        @test tap[r, "Trans1"] >= 0.9 - 1e-6
        @test tap[r, "Trans1"] <= 1.1 + 1e-6
    end
end

@testset "VOLTAGE control regulates the from-side bus when its number is given" begin
    _, _, _, bus_name = _controlled_sys14(VOLTAGE_CONTROL; regulated = :from)
    free_vm = _uncontrolled_voltage(bus_name)
    band = (min = free_vm - 0.02, max = free_vm - 0.01)

    sys, _, _, _ =
        _controlled_sys14(VOLTAGE_CONTROL; regulated = :from, quantity_limits = band)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
    for r in 1:nrow(vm)
        @test vm[r, bus_name] >= band.min - 1e-6
        @test vm[r, bus_name] <= band.max + 1e-6
    end
end

############################ REACTIVE_POWER_FLOW objective #############################

@testset "REACTIVE_POWER_FLOW control holds the terminal flow inside its band (ACP)" begin
    # `controlled_quantity_limits` reaches the constraint builder unconverted, so it is
    # read as system-base pu here; the reported flow is MVAR and divided back down.
    band = (min = -0.05, max = 0.05)
    sys, _, _, _ = _controlled_sys14(Q_FLOW_CONTROL; quantity_limits = band)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    for key in (
        "FlowReactivePowerFromToVariable__TwoWindingTransformer",
        "FlowReactivePowerToFromVariable__TwoWindingTransformer",
    )
        flow = read_variable(res, key; table_format = TableFormat.WIDE)
        for r in 1:nrow(flow)
            @test flow[r, "Trans1"] / base >= band.min - 1e-6
            @test flow[r, "Trans1"] / base <= band.max + 1e-6
        end
    end
end

################################### model invariants ###################################

@testset "a tap pinned at nominal reproduces the uncontrolled model" begin
    # White-box reduction gate: with the tap variable fixed at the circuit's nominal
    # ratio and a band too wide to bind, the controlled Ohm's law is term-by-term the
    # fixed-tap one, so both models must reach the same optimum and terminal flows.
    # The band is the regulated bus's own (0.94, 1.06) limits — the widest a VOLTAGE band
    # may be — so the control constrains nothing the bus does not already.
    #
    # IVR is the sharpest case: its law is multiplied through by the ratio, so every
    # tm-bearing term has to reduce exactly for the flows to match.
    band = (min = 0.94, max = 1.06)
    tap_range = (min = 0.5, max = 1.5)

    for network_formulation in (
        ACPNetworkModel,
        ACRNetworkModel,
        LPACCNetworkModel,
        IVRNetworkModel,
    )
        sys_fixed, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; quantity_limits = band)
        model_fixed, status_fixed = _build_controlled(
            sys_fixed, network_formulation; enable = false,
            optimizer = ipopt_optimizer,
        )
        @test status_fixed == IOM.ModelBuildStatus.BUILT
        @test solve!(model_fixed) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        sys_var, transformer, circuit, _ = _controlled_sys14(
            VOLTAGE_CONTROL; quantity_limits = band, control_limits = tap_range,
        )
        model_var, status_var = _build_controlled(
            sys_var, network_formulation; optimizer = ipopt_optimizer,
        )
        @test status_var == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model_var)
        tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
        for t in axes(tap, 2)
            JuMP.fix(
                tap[PSY.get_name(transformer), t], PSY.get_tap(circuit); force = true,
            )
        end
        @test solve!(model_var) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res_fixed = IOM.OptimizationProblemOutputs(model_fixed)
        res_var = IOM.OptimizationProblemOutputs(model_var)
        @test isapprox(
            IOM.get_objective_value(res_var),
            IOM.get_objective_value(res_fixed);
            rtol = 1e-3,
        )
        for key in (
            "FlowActivePowerFromToVariable__TwoWindingTransformer",
            "FlowReactivePowerFromToVariable__TwoWindingTransformer",
        )
            flow_fixed = read_variable(res_fixed, key; table_format = TableFormat.WIDE)
            flow_var = read_variable(res_var, key; table_format = TableFormat.WIDE)
            for d in PSY.get_components(PSY.TwoWindingTransformer, sys_var)
                name = PSY.get_name(d)
                @test isapprox(flow_var[1, name], flow_fixed[1, name]; atol = 1e-3)
            end
        end
    end
end

@testset "NetworkFlowConstraint carries the live tap variable (ACP coefficients)" begin
    # Ground truth: the built from-to flow constraint must use exactly the
    # `_tapped_admittance` terms evaluated at the tap VARIABLE. Evaluate
    # `constraint_object(con).func` at an arbitrary point and compare against the
    # hand-assembled right-hand side.
    sys, transformer, _, _ = _controlled_sys14(VOLTAGE_CONTROL)
    model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(
        container,
        FlowActivePowerFromToVariable,
        PSY.TwoWindingTransformer,
    )
    vm = IOM.get_variable(container, VoltageMagnitude, PSY.ACBus)
    va = IOM.get_variable(container, VoltageAngle, PSY.ACBus)
    tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
    con_pft = IOM.get_constraint(
        container, POM.NetworkFlowConstraint, PSY.TwoWindingTransformer, "p_ft",
    )

    t = 1
    name = PSY.get_name(transformer)
    arc = PSY.get_arc(PSY.get_circuit(transformer))
    fr = PSY.get_name(PSY.get_from(arc))
    to = PSY.get_name(PSY.get_to(arc))
    adm = PNM.branch_admittance(transformer)

    vals = Dict{JuMP.VariableRef, Float64}(
        vm[fr, t] => 1.02, vm[to, t] => 0.98,
        va[fr, t] => 0.05, va[to, t] => -0.03,
        tap[name, t] => 1.05,
        pft[name, t] => 0.7,
    )
    lookup = z -> vals[z]

    y = POM._tapped_admittance(get_jump_model(container), adm, vals[tap[name, t]])
    vmf = vals[vm[fr, t]]
    vmt = vals[vm[to, t]]
    θ = vals[va[fr, t]] - vals[va[to, t]]
    rhs = y.g11 * vmf^2 + y.g12 * vmf * vmt * cos(θ) + y.b12 * vmf * vmt * sin(θ)
    # `func` is stored as (lhs - rhs).
    @test isapprox(
        JuMP.value(lookup, JuMP.constraint_object(con_pft[name, t]).func),
        vals[pft[name, t]] - rhs;
        atol = 1e-10,
    )
end

################################### network coverage ###################################

@testset "VOLTAGE control is wired on every voltage-carrying AC network" begin
    for network_formulation in (ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)
        _, _, _, bus_name = _controlled_sys14(VOLTAGE_CONTROL)
        band = (min = 1.00, max = 1.02)
        sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; quantity_limits = band)
        model, status =
            _build_controlled(sys, network_formulation; optimizer = ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        @test _has_tap_variable(IOM.get_optimization_container(model))
        @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res = IOM.OptimizationProblemOutputs(model)
        if network_formulation == LPACCNetworkModel
            phi = read_variable(
                res, "VoltageDeviation__ACBus"; table_format = TableFormat.WIDE,
            )
            magnitude = 1.0 + phi[1, bus_name]
        else
            vr = read_variable(
                res,
                "VoltageReal__ACBus";
                table_format = TableFormat.WIDE,
            )
            vi = read_variable(
                res, "VoltageImaginary__ACBus"; table_format = TableFormat.WIDE,
            )
            magnitude = sqrt(vr[1, bus_name]^2 + vi[1, bus_name]^2)
        end
        @test magnitude >= band.min - 1e-4
        @test magnitude <= band.max + 1e-4

        # The band is written on the network's own voltage variables, so no per-device
        # RegulatedVoltageMagnitude aux is introduced on any of these networks.
        container = IOM.get_optimization_container(model)
        @test !IOM.has_container_key(
            container, RegulatedVoltageMagnitude, PSY.TwoWindingTransformer,
        )
        # One controlled circuit, two rows (lower/upper) per time step.
        @test length(
            IOM.get_constraint(
                container, VoltageMagnitudeConstraint, PSY.TwoWindingTransformer,
            ),
        ) == 2 * length(IOM.get_time_steps(container))
    end
end

@testset "REACTIVE_POWER_FLOW control holds the terminal flow inside its band (IVR)" begin
    # IVR builds its own current-based flow constraints, so the band has to be applied
    # there too and not only on the shared pi-model path.
    band = (min = -0.05, max = 0.05)
    sys, _, _, _ = _controlled_sys14(Q_FLOW_CONTROL; quantity_limits = band)
    model, status = _build_controlled(sys, IVRNetworkModel; optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    for key in (
        "FlowReactivePowerFromToVariable__TwoWindingTransformer",
        "FlowReactivePowerToFromVariable__TwoWindingTransformer",
    )
        flow = read_variable(res, key; table_format = TableFormat.WIDE)
        for r in 1:nrow(flow)
            @test flow[r, "Trans1"] / base >= band.min - 1e-6
            @test flow[r, "Trans1"] / base <= band.max + 1e-6
        end
    end
end

################################### DC networks ########################################

@testset "DC networks build a variable tap under StaticBranchBounds" begin
    tap_range = (min = 0.9, max = 1.1)
    for network_formulation in (DCPNetworkModel, DCPLLNetworkModel)
        sys, _, _, _ =
            _controlled_sys14(VOLTAGE_CONTROL; control_limits = tap_range)
        model, status = _build_controlled(
            sys,
            network_formulation;
            formulation = StaticBranchBounds,
            optimizer = ipopt_optimizer,
        )
        @test status == IOM.ModelBuildStatus.BUILT
        container = IOM.get_optimization_container(model)
        tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
        @test axes(tap)[1] == ["Trans1"]
        @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
        # Neither quantity exists on a DC network, so no band is built either way.
        @test !IOM.has_container_key(
            container, VoltageMagnitudeConstraint, PSY.TwoWindingTransformer,
        )
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    end
end

@testset "the DC tap law reduces to the fixed-tap law at the nominal ratio" begin
    # The bilinear DC law is multiplied through by the ratio, so evaluating the built row at
    # the nominal ratio must reproduce `nominal * (p - b_dc * (va_fr - va_to - shift))`.
    # Checked on the constraint itself rather than by comparing two solves: c_sys14's
    # transformer ratings make a fixed-tap StaticBranchBounds DCP model infeasible (that
    # formulation enforces the rating as hard variable bounds), so there is no fixed-tap
    # reference solution to compare against on this system.
    sys, transformer, circuit, _ = _controlled_sys14(VOLTAGE_CONTROL)
    model, status = _build_controlled(
        sys, DCPNetworkModel;
        formulation = StaticBranchBounds, optimizer = ipopt_optimizer,
    )
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    p = IOM.get_variable(container, FlowActivePowerVariable, PSY.TwoWindingTransformer)
    va = IOM.get_variable(container, VoltageAngle, PSY.ACBus)
    tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
    cons =
        IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.TwoWindingTransformer)

    t = 1
    name = PSY.get_name(transformer)
    arc = PSY.get_arc(circuit)
    fr = PSY.get_name(PSY.get_from(arc))
    to = PSY.get_name(PSY.get_to(arc))
    nominal = PNM.branch_admittance(transformer).tap
    b_dc = PNM.get_series_susceptance(transformer, PSY.SU)
    shift = PNM.get_series_phase_shift(transformer)
    @test !isapprox(nominal, 1.0; atol = 1e-6)

    vals = Dict{JuMP.VariableRef, Float64}(
        va[fr, t] => 0.05, va[to, t] => -0.03,
        tap[name, t] => nominal,
        p[name, t] => 0.7,
    )
    lookup = z -> vals[z]

    angle = vals[va[fr, t]] - vals[va[to, t]] - shift
    @test isapprox(
        JuMP.value(lookup, JuMP.constraint_object(cons[name, t]).func),
        nominal * (vals[p[name, t]] - b_dc * angle);
        atol = 1e-10,
    )
end

################################ reductions and conflicts ##############################

@testset "a controlled circuit survives the network reduction" begin
    # Controlled transformers pin their endpoint buses irreducible, so the circuit keeps
    # its own arc (and therefore its own tap variable) even with reductions requested.
    sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL)
    model, status = _build_controlled(
        sys,
        ACPNetworkModel;
        optimizer = ipopt_optimizer,
        reduce_radial_branches = true,
        reduce_degree_two_branches = true,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test axes(IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer))[1] ==
          ["Trans1"]
end

@testset "a controlled circuit merged with a parallel branch fails with a clear error" begin
    # PNM collapses parallel branches onto one equivalent arc before POM sees them, which
    # would leave the control acting on a flow that is not the transformer's own.
    # Trans1's arc spans a voltage change, so the parallel branch has to be another
    # transformer: PSY rejects a Line whose endpoints differ in base voltage.
    sys, transformer, circuit, _ = _controlled_sys14(VOLTAGE_CONTROL)
    arc = PSY.get_arc(circuit)
    PSY.add_component!(
        sys,
        PSY.TwoWindingTransformer(;
            name = "parallel_to_Trans1",
            circuit = PSY.TransformerCircuit(;
                available = true,
                arc = arc,
                r = PSY.get_r(circuit, PSY.SU),
                x = PSY.get_x(circuit, PSY.SU),
                tap = 1.0,
                α = 0.0,
                rating = PSY.get_rating(circuit, PSY.SU),
                base_power = PSY.get_base_power(sys, PSY.NU),
            ),
            magnetizing_shunt = 0.0 + 0.0im,
            shunt_location = PSY.TwoWindingTransformerShuntLocation.PRIMARY,
        ),
    )
    template = _controlled_template(ACPNetworkModel)
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out, console_level = Logging.Error) ==
          IOM.ModelBuildStatus.FAILED
    log = read(joinpath(out, "operation_problem.log"), String)
    @test occursin("Controlled transformer circuit", log)
    @test occursin(PSY.get_name(transformer), log)
end

# `case11_network_reductions` is the purpose-built reducible system (c_sys14 reduces
# nothing); it carries no forecast, which a DecisionModel build requires.
function _case11_with_forecast()
    sys = PSB.build_system(PSITestSystems, "case11_network_reductions")
    dummy_data = Dict(
        DateTime("2020-01-01T08:00:00") => [5.0, 6, 7, 7, 7],
        DateTime("2020-01-01T08:30:00") => [9.0, 9, 9, 9, 8],
        DateTime("2020-01-01T09:00:00") => [6.0, 6, 5, 5, 4],
    )
    dummy_forecast = Deterministic("max_active_power", dummy_data, Dates.Minute(5))
    load = first(PSY.get_components(PSY.StandardLoad, sys))
    PSY.add_time_series!(sys, load, dummy_forecast)
    return sys
end

#########################################################################################
# Phase control (the ACTIVE_POWER_FLOW / ASYMMETRIC_ACTIVE_POWER_FLOW objectives, where the
# phase shift α rather than the tap ratio is the decision variable) is NOT supported yet.
# The testsets below are the coverage that existed for the old `PhaseAngleControl`
# formulation, kept commented until the objective is implemented. They still name
# `PhaseAngleControl` / `PhaseShiftingTransformer`; port them onto the control-objective
# framework when phase control lands.
#########################################################################################

# @testset "PhaseAngleControl branch absorbed by a network reduction fails with a clear error" begin
#    # "1-6-i_1" is one segment of the (1,2) series chain, so under reduction it has no
#    # direct-branch entry of its own — the same _validate_controlled_branch_not_reduced
#    # gate exercised above for tap control also covers PhaseAngleControl.
#    sys = _case11_with_forecast()
#    line = PSY.get_component(Line, sys, "1-6-i_1")
#    arc = PSY.get_arc(line)
#
#    # TODO: phase_angle_limits?
#    ps = PSY.TwoWindingTransformer(;
#        name = PSY.get_name(line),
#        circuit = PSY.TransformerCircuit(;
#            available = true,
#            active_power_flow = 0.0,
#            reactive_power_flow = 0.0,
#            r = PSY.get_r(line, PSY.SU),
#            x = PSY.get_x(line, PSY.SU),
#            tap = 1.0,
#            α = 0.0,
#            rating = PSY.get_rating(line, PSY.SU),
#            arc = arc,
#            base_power = PSY.get_base_power(sys, PSY.NU)
#        ),
#        magnetizing_shunt = 0.0 + 0.0im,
#        shunt_location = TwoWindingTransformerShuntLocation.PRIMARY
#    )
#    PSY.add_component!(sys, ps)
#    PSY.remove_component!(sys, line)
#
#    net = NetworkModel(
#        DCPNetworkModel;
#        reduce_radial_branches = true,
#        reduce_degree_two_branches = true,
#    )
#    template = get_thermal_dispatch_template_network(net)
#    set_device_model!(
#        template, DeviceModel(PSY.TwoWindingTransformer, PhaseAngleControl),
#    )
#    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
#    out = mktempdir(; cleanup = true)
#    @test build!(model; output_dir = out, console_level = Logging.Error) ==
#          IOM.ModelBuildStatus.FAILED
#    log = read(joinpath(out, "operation_problem.log"), String)
#    @test occursin("absorbed by a network reduction", log)
# end

# @testset "DC Power Flow Models for phase-shifting TwoWindingTransformer and Line" begin
#     system = build_system(PSITestSystems, "c_sys5_uc")
#
#     line = get_component(Line, system, "1")
#
#     ps = TwoWindingTransformer(;
#         name = get_name(line),
#         available = true,
#         active_power_flow = 0.0,
#         reactive_power_flow = 0.0,
#         r = get_r(line, PSY.SU),
#         x = get_r(line, PSY.SU),
#         primary_shunt = 0.0,
#         tap = 1.0,
#         α = 0.0,
#         rating = get_rating(line, PSY.SU),
#         arc = get_arc(line),
#         base_power = get_base_power(system, PSY.NU),
#     )
#
#     add_component!(system, ps)
#     remove_component!(system, line)
#
#     template = get_template_dispatch_with_network(
#         NetworkModel(PTDFNetworkModel; network_matrix = PTDF(system)),
#     )
#     set_device_model!(template, DeviceModel(TwoWindingTransformer, PhaseAngleControl))
#     model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#     @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#           IOM.ModelBuildStatus.BUILT
#
#     @test check_variable_unbounded(
#         model_m,
#         FlowActivePowerVariable,
#         TwoWindingTransformer,
#     )
#
#     @test solve!(model_m) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
#
#     @test check_flow_variable_values(
#         model_m,
#         FlowActivePowerVariable,
#         TwoWindingTransformer,
#         "1",
#         get_rating(ps, PSY.SU),
#     )
#
#     @test check_flow_variable_values(
#         model_m,
#         PhaseShifterAngle,
#         TwoWindingTransformer,
#         "1",
#         -π / 2,
#         π / 2,
#     )
# end

# @testset "AC Power Flow in the loop for PhaseShiftingTransformer" begin
#    system = buid_system(PSITestSystems, "c_sys5_uc")
#
#    line = get_component(Line, system, "1")
#    arc = get_arc(line)
#
#    ps = PhaseShiftingTransformer(;
#        name = get_name(line),
#        available = true,
#        active_power_flow = 0.0,
#        reactive_power_flow = 0.0,
#        r = get_r(line, PSY.SU),
#        x = get_x(line, PSY.SU),
#        primary_shunt = 0.0,
#        tap = 1.0,
#        α = 0.0,
#        rating = get_rating(line, PSY.SU),
#        arc = arc,
#        base_power = get_base_power(system, PSY.NU),
#    )
#    add_component!(system, ps)
#    remove_component!(system, line)
#
#    template = get_template_dispatch_with_network(
#        NetworkModel(
#            PTDFNetworkModel;
#            network_matrix = PTDF(system),
#            evaluations = power_flow_evaluations(ACPowerFlow()),
#        ),
#    )
#    set_device_model!(template, DeviceModel(PhaseShiftingTransformer, PhaseAngleControl))
#    model_m = DecisionModel(template, system; optimizer = HiGHS_optimizer)
#    @test build!(model_m; output_dir = mktempdir(; cleanup = true)) ==
#          ModelBuildStatus.BUILT
#    @test solve!(model_m) == RunStatus.SUCCESSFULLY_FINALIZED
#
#    container = get_optimization_container(model_m)
#    pf_e_data = only(values(get_evaluation_data(get_evaluations(container))))
#    data = get_inner_data(pf_e_data)
#    bus_lookup = PFS.get_bus_lookup(data)
#
#    flow_key = VariableKey(FlowActivePowerVariable, PhaseShiftingTransformer)
#    flow_values = lookup_value(container, flow_key)
#    line_name = get_name(line)
#    line_flows =
#        [JuMP.value(flow_values[line_name, t]) for t in 1:length(get_time_steps(container))]
#
#    # The PhaseShiftingTransformer flow contributes to the "to"-bus active power injection.
#    # Both sides are in per-unit; lookup_value returns raw JuMP values in the model unit
#    # system rather than the natural-unit conversion that `read_variables(...; WIDE)`
#    # performs in PSI.
#    @test isapprox(
#        data.bus_active_power_injections[bus_lookup[get_number(get_to(arc))], :],
#        line_flows;
#        atol = 1e-9,
#        rtol = 0,
#    )
# end
