const VOLTAGE_CONTROL = PSY.TransformerControlObjective.VOLTAGE
const Q_FLOW_CONTROL = PSY.TransformerControlObjective.REACTIVE_POWER_FLOW
const TAP_CONTROLS = (VOLTAGE_CONTROL, Q_FLOW_CONTROL)

const VOLTAGE_NETWORKS = (ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel)
const AC_NETWORKS = (VOLTAGE_NETWORKS..., IVRNetworkModel)
const DC_NETWORKS = (DCPNetworkModel, DCPLLNetworkModel)
const ALL_NETWORKS = (AC_NETWORKS..., DC_NETWORKS...)

const TRANFORMER_NAMES = ["Trans1", "Trans2", "Trans3", "Trans4"]

function _controlled_sys14(
    objective;
    name = "Trans1",
    regulated = 9,
    quantity_limits = (min = 0.95, max = 1.05),
    control_limits = (min = 0.9, max = 1.1),
)
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    transformer = PSY.get_component(PSY.TwoWindingTransformer, sys, name)
    circuit = PSY.get_circuit(transformer)
    PSY.set_control_objective!(circuit, objective)
    PSY.set_regulated_bus_number!(circuit, regulated)
    PSY.set_controlled_quantity_limits!(circuit, quantity_limits)
    PSY.set_control_limits!(circuit, control_limits)
    return sys, transformer, circuit, PSY.get_name(PSY.get_bus(sys, regulated))
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
            attributes = Dict(
                POM.ENABLE_CONTROLS_KEY => enable
            )
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

@testset "a controlled circuit builds no tap variable while enable_controls is off" begin
    sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL)
    model, status =
        _build_controlled(sys, ACPNetworkModel; enable = false, optimizer = ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test !_has_tap_variable(IOM.get_optimization_container(model))
end

@testset "TapRatioVariable is created only for controlled circuits, bounded by control_limits" begin
    limits = (min = 0.95, max = 1.05)
    for mode in TAP_CONTROLS
        sys, _, _, _ = _controlled_sys14(mode; control_limits = limits)
        model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
        # Trans2 / Trans3 are left UNDEFINED, so only the controlled circuit gets a variable.
        @test axes(tap)[1] == ["Trans1"]
        @test check_variable_bounded(model, TapRatioVariable, PSY.TwoWindingTransformer)
    end
end

################################### VOLTAGE objective ##################################

# Solve system with no controls to get bus voltage reference to make sure our
# control constraint tests are doing something.
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

@testset "VOLTAGE control holds the regulated bus inside its limits" begin
    rawsys = PSB.build_system(PSITestSystems, "c_sys14")
    buses = PSY.get_components(PSY.ACBus, rawsys)
    for network_formulation in VOLTAGE_NETWORKS, bus in buses
        bus_name = PSY.get_name(bus)
        free_vm = _uncontrolled_voltage(bus_name)
        limits = (min = free_vm - 0.02, max = free_vm - 0.01)

        sys, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; regulated = PSY.get_number(bus), quantity_limits = limits)
        model, status = _build_controlled(sys, ACPNetworkModel; optimizer = ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res = IOM.OptimizationProblemOutputs(model)
        vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
        @test bus_name in names(vm)
        for r in 1:nrow(vm)
            @test vm[r, bus_name] >= limits.min - 1e-6
            @test vm[r, bus_name] <= limits.max + 1e-6
        end
    end
end

############################ REACTIVE_POWER_FLOW objective #############################

@testset "REACTIVE_POWER_FLOW control holds the terminal flow inside its limits" begin
    limits = (min = -0.05, max = 0.05)

    # TODO: Is this excessive to be looping all networks and transformers? (I also do this later)
    for network_formulation in AC_NETWORKS, name in TRANFORMER_NAMES
        sys, _, _, _ = _controlled_sys14(Q_FLOW_CONTROL; quantity_limits = limits, name = name)
        model, status = _build_controlled(sys, network; optimizer = ipopt_optimizer)
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
                @test flow[r, name] >= limits.min - 1e-6
                @test flow[r, name] <= limits.max + 1e-6
            end
        end
    end
end

################################### model invariants ###################################

@testset "a tap pinned at nominal reproduces the uncontrolled model" begin
    limits = (min = 0.94, max = 1.06)
    tap_range = (min = 0.5, max = 1.5)

    branch_formulation(::Union{DCPNetworkModel, DCPLLNetworkModel}) = StaticBranchBounds
    branch_formulation(_) = StaticBranch

    for network_formulation in ALL_NETWORKS, name in TRANFORMER_NAMES
        sys_fixed, _, _, _ = _controlled_sys14(VOLTAGE_CONTROL; quantity_limits = limits, name = name)
        model_fixed, status_fixed = _build_controlled(
            sys_fixed, network_formulation; enable = false,
            optimizer = ipopt_optimizer, formulation = branch_formulation(network_formulation)
        )
        @test status_fixed == IOM.ModelBuildStatus.BUILT
        @test solve!(model_fixed) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        sys_var, transformer, circuit, _ = _controlled_sys14(
            VOLTAGE_CONTROL; quantity_limits = limits, control_limits = tap_range, name = name
        )
        model_var, status_var = _build_controlled(sys_var, network_formulation; optimizer = ipopt_optimizer, formulation = branch_formulation(network_formulation))
        @test status_var == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model_var)
        tap = IOM.get_variable(container, TapRatioVariable, PSY.TwoWindingTransformer)
        for t in get_time_steps(container)
            JuMP.fix(
                tap[name, t], PSY.get_tap(circuit); force = true,
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
            @test isapprox(flow_var[1, name], flow_fixed[1, name]; atol = 1e-3)
        end
    end
end

@testset "_tapped_admittance round-trips PNM.ybus_branch_entries" begin
    function check_terms(y, ybus)
        Y11, Y12, Y21, Y22 = ybus
        @test isapprox(complex(y.g11, y.b11), Y11; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g12, y.b12), Y12; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g21, y.b21), Y21; rtol = 1e-10, atol = 1e-12)
        @test isapprox(complex(y.g22, y.b22), Y22; rtol = 1e-10, atol = 1e-12)
    end

    model = JuMP.Model()
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    for br in Iterators.flatten((
        PSY.get_components(PSY.Line, sys),
        PSY.get_components(PSY.TwoWindingTransformer, sys),
    ))
        adm = PNM.branch_admittance(br)
        check_terms(
            POM._tapped_admittance(model, adm, adm.tap),
            PNM.ybus_branch_entries(br),
        )
    end

    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
    circuit = PSY.get_circuit(tr)
    for shift in (-pi / 5, 0.0, pi / 6)
        PSY.set_α!(circuit, shift)
        PSY.set_tap!(circuit, 1.0)
        adm = PNM.branch_admittance(tr)
        for tap in (0.9, 1.0, 1.1, 1.25)
            PSY.set_tap!(circuit, tap)
            check_terms(
                POM._tapped_admittance(model, adm, tap),
                PNM.ybus_branch_entries(tr),
            )
        end
    end
end

################################ static tap ############################################

@testset "StaticBranch models transformer off-nominal tap under DCP (c_sys14)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, PSY.TwoWindingTransformer, StaticBranch)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    # StaticBranch under DCP has no FlowActivePowerVariable: the flow IS the
    # BThetaBranchFlow expression, reported in natural units (MW). VoltageAngle is
    # unitless (radians, no conversion), so compare in per-unit.
    pflow = read_expression(
        res,
        "BThetaBranchFlow__TwoWindingTransformer";
        table_format = TableFormat.WIDE,
    )
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)

    tested_a_real_tap = false
    for tr in PSY.get_components(PSY.TwoWindingTransformer, sys)
        name = PSY.get_name(tr)
        @test name in names(pflow)

        # Recover the series reactance independently, from the π-model admittance, so the
        # oracle does not simply re-call the susceptance helper the source uses.
        adm = PNM.branch_admittance(tr)
        x = -adm.b / (adm.g^2 + adm.b^2)
        # The DC susceptance is tap-divided: b_dc == 1/(tap*x). Pin the equivalence of the
        # independent recovery and PNM's DC entry point.
        @test 1 / (x * adm.tap) ≈ PNM.get_series_susceptance(tr, PSY.SU)

        arc = PSY.get_arc(PSY.get_circuit(tr))
        fr = PSY.get_name(PSY.get_from(arc))
        to = PSY.get_name(PSY.get_to(arc))
        shift = PNM.get_series_phase_shift(tr)
        if !isapprox(adm.tap, 1.0; atol = 1e-6)
            tested_a_real_tap = true
        end
        for r in 1:nrow(pflow)
            p_pu = pflow[r, name] / base
            expected = (va[r, fr] - va[r, to] - shift) / (x * adm.tap)
            @test isapprox(p_pu, expected; atol = 1e-5)
        end
    end
    # Guard: the test system must actually carry a non-unit tap, else this proves nothing.
    @test tested_a_real_tap
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
