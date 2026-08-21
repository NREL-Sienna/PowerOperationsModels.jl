######################################## helpers #######################################

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
    kwargs...,
)
    template = _controlled_template(
        network_formulation, device_type;
        enable = enable, formulation = formulation, kwargs...,
    )
    model = DecisionModel(template, sys; optimizer = optimizer)
    status = build!(model; output_dir = mktempdir(; cleanup = true))
    return model, status
end

_has_tap_variable(container) =
    any(k -> occursin("TapRatioVariable", string(k)), keys(IOM.get_variables(container)))

_variable_key(variable, device_type) = "$(nameof(variable))__$(nameof(device_type))"

# The regulated quantity each AC formulation actually constrains, converted back to a bus
# voltage magnitude so every formulation can be checked against the same per-unit band.
# Mirrors `_voltage_magnitude`/`_voltage_limits` in `AC_branches.jl`.
function _voltage_magnitudes(res, bus_name, ::Type{ACPNetworkModel})
    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
    return vm[!, bus_name]
end

function _voltage_magnitudes(
    res,
    bus_name,
    ::Type{<:Union{ACRNetworkModel, IVRNetworkModel}},
)
    vr = read_variable(res, "VoltageReal__ACBus"; table_format = TableFormat.WIDE)
    vi = read_variable(res, "VoltageImaginary__ACBus"; table_format = TableFormat.WIDE)
    return sqrt.(vr[!, bus_name] .^ 2 .+ vi[!, bus_name] .^ 2)
end

function _voltage_magnitudes(res, bus_name, ::Type{LPACCNetworkModel})
    phi = read_variable(res, "VoltageDeviation__ACBus"; table_format = TableFormat.WIDE)
    return 1.0 .+ phi[!, bus_name]
end

################################### attribute plumbing #################################

@testset "a controlled circuit builds no tap variable while enable_controls is off" begin
    for case in TRANSFORMER_CASES
        fixture = case.make(VOLTAGE_CONTROL)
        model, status = _build_controlled(
            fixture.sys, ACPNetworkModel, case.device_type;
            enable = false, optimizer = ipopt_optimizer,
        )
        @test status == IOM.ModelBuildStatus.BUILT
        @test !_has_tap_variable(IOM.get_optimization_container(model))
    end
end

@testset "TapRatioVariable is created only for controlled circuits, bounded by control_limits" begin
    limits = (min = 0.95, max = 1.05)
    for case in TRANSFORMER_CASES, mode in TAP_CONTROLS
        # Deliberately not circuit 1: the untouched circuits are left UNDEFINED, so only
        # the controlled one may appear on the axis.
        controlled = last(case.circuit_indices)
        fixture = case.make(mode; circuit_index = controlled, control_limits = limits)
        model, status = _build_controlled(
            fixture.sys, ACPNetworkModel, case.device_type; optimizer = ipopt_optimizer,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        tap = IOM.get_variable(container, TapRatioVariable, case.device_type)
        @test axes(tap)[1] == [fixture.axis_name]

        # `control_limits` is the tap band itself, so it must land on the variable as hard
        # bounds rather than merely being present as data.
        band = PSY.get_control_limits(fixture.circuit)
        for t in get_time_steps(container)
            var = tap[fixture.axis_name, t]
            @test JuMP.has_lower_bound(var)
            @test JuMP.has_upper_bound(var)
            @test JuMP.lower_bound(var) ≈ band.min
            @test JuMP.upper_bound(var) ≈ band.max
        end
    end
end

@testset "one three-winding device carries independent per-winding objectives" begin
    sys = _sys5_with_3w()
    transformer = PSY.get_component(PSY.ThreeWindingTransformer, sys, T3W_NAME)
    circuits = PSY.get_circuits(transformer)

    PSY.set_control_objective!(circuits[1], VOLTAGE_CONTROL)
    PSY.set_regulated_bus_number!(circuits[1], T3W_STAR_NUMBER)
    PSY.set_controlled_quantity_limits!(circuits[1], (min = 0.95, max = 1.05))

    PSY.set_control_objective!(circuits[3], Q_FLOW_CONTROL)
    PSY.set_controlled_quantity_limits!(circuits[3], (min = -0.05, max = 0.05))

    model, status = _build_controlled(
        sys, ACPNetworkModel, PSY.ThreeWindingTransformer; optimizer = ipopt_optimizer,
    )
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    tap = IOM.get_variable(container, TapRatioVariable, PSY.ThreeWindingTransformer)
    # Winding 2 is left UNDEFINED, so it gets no tap of its own.
    @test sort(axes(tap)[1]) == [T3W_WINDINGS[1], T3W_WINDINGS[3]]

    _constrained_names(cons) = Set(k[1] for k in keys(cons.data))
    @test _constrained_names(
        IOM.get_constraint(
            container, VoltageControlConstraint, PSY.ThreeWindingTransformer,
        ),
    ) == Set([T3W_WINDINGS[1]])
    @test _constrained_names(
        IOM.get_constraint(
            container, ReactivePowerFlowControlConstraint, PSY.ThreeWindingTransformer,
        ),
    ) == Set([T3W_WINDINGS[3]])

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

################################### VOLTAGE objective ##################################

# Solve system with no controls to get bus voltage reference to make sure our
# control constraint tests are doing something.
function _uncontrolled_voltage(case, bus_name, network_formulation)
    model, status = _build_controlled(
        case.plain(), network_formulation, case.device_type;
        enable = false, optimizer = ipopt_optimizer,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    return first(_voltage_magnitudes(res, bus_name, network_formulation))
end

@testset "VOLTAGE control holds the regulated bus inside its limits" begin
    for case in TRANSFORMER_CASES
        rawsys = case.plain()
        numbers = case.voltage_bus_numbers(rawsys)
        for network_formulation in VOLTAGE_NETWORKS, number in numbers
            bus_name = PSY.get_name(PSY.get_bus(rawsys, number))
            free_vm = _uncontrolled_voltage(case, bus_name, network_formulation)
            limits = (min = free_vm - 0.02, max = free_vm - 0.01)

            fixture =
                case.make(VOLTAGE_CONTROL; regulated = number, quantity_limits = limits)
            model, status = _build_controlled(
                fixture.sys, network_formulation, case.device_type;
                optimizer = ipopt_optimizer,
            )
            @test status == IOM.ModelBuildStatus.BUILT
            @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

            res = IOM.OptimizationProblemOutputs(model)
            for v in _voltage_magnitudes(res, bus_name, network_formulation)
                @test v >= limits.min - 1e-6
                @test v <= limits.max + 1e-6
            end
        end
    end
end

############################ REACTIVE_POWER_FLOW objective #############################

@testset "REACTIVE_POWER_FLOW control holds the terminal flow inside its limits" begin
    limits = (min = -0.05, max = 0.05)

    for case in TRANSFORMER_CASES,
        network_formulation in AC_NETWORKS,
        index in case.circuit_indices

        fixture =
            case.make(Q_FLOW_CONTROL; circuit_index = index, quantity_limits = limits)
        model, status = _build_controlled(
            fixture.sys, network_formulation, case.device_type;
            optimizer = ipopt_optimizer,
        )
        @test status == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res = IOM.OptimizationProblemOutputs(model)
        base = IOM.get_model_base_power(res)
        flow = read_variable(
            res, _variable_key(FlowReactivePowerFromToVariable, case.device_type);
            table_format = TableFormat.WIDE,
        )
        for r in 1:nrow(flow)
            @test flow[r, fixture.axis_name] / base >= limits.min - 1e-6
            @test flow[r, fixture.axis_name] / base <= limits.max + 1e-6
        end
    end
end

################################### model invariants ###################################

@testset "a tap pinned at nominal reproduces the uncontrolled model" begin
    limits = (min = 0.94, max = 1.06)
    tap_range = (min = 0.5, max = 1.5)

    flow_variables(_) =

    for case in TRANSFORMER_CASES,
        network_formulation in ALL_NETWORKS,
        index in case.circuit_indices

        fixed = case.make(
            VOLTAGE_CONTROL; circuit_index = index, quantity_limits = limits,
        )
        model_fixed, status_fixed = _build_controlled(
            fixed.sys, network_formulation, case.device_type;
            enable = false, optimizer = ipopt_optimizer,
        )
        @test status_fixed == IOM.ModelBuildStatus.BUILT
        @test solve!(model_fixed) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        varying = case.make(
            VOLTAGE_CONTROL;
            circuit_index = index,
            quantity_limits = limits,
            control_limits = tap_range,
        )
        model_var, status_var = _build_controlled(
            varying.sys, network_formulation, case.device_type;
            optimizer = ipopt_optimizer, formulation = formulation,
        )
        @test status_var == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model_var)
        tap = IOM.get_variable(container, TapRatioVariable, case.device_type)
        for t in get_time_steps(container)
            JuMP.fix(
                tap[varying.axis_name, t], PSY.get_tap(varying.circuit); force = true,
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

        for variable in (
            FlowActivePowerFromToVariable,
            FlowActivePowerToFromVariable,
            FlowReactivePowerFromToVariable,
            FlowReactivePowerToFromVariable,
        )
            key = _variable_key(variable, case.device_type)
            flow_fixed = read_variable(res_fixed, key; table_format = TableFormat.WIDE)
            flow_var = read_variable(res_var, key; table_format = TableFormat.WIDE)
            @test isapprox(
                flow_var[1, varying.axis_name],
                flow_fixed[1, varying.axis_name];
                atol = 1e-3,
            )
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

    # A three-winding transformer reaches the builders as one `ThreeWindingTransformerCircuit`
    # per star leg, each with its own tap and phase shift.
    sys3w = _sys5_with_3w()
    tr3w = PSY.get_component(PSY.ThreeWindingTransformer, sys3w, T3W_NAME)
    for (index, star_leg) in enumerate(PSY.get_circuits(tr3w))
        winding = PNM.ThreeWindingTransformerCircuit(tr3w, index)
        adm = PNM.branch_admittance(winding)
        check_terms(
            POM._tapped_admittance(model, adm, adm.tap),
            PNM.ybus_branch_entries(winding),
        )

        for shift in (-pi / 5, 0.0, pi / 6)
            PSY.set_α!(star_leg, shift)
            PSY.set_tap!(star_leg, 1.0)
            adm = PNM.branch_admittance(winding)
            for tap in (0.9, 1.0, 1.1, 1.25)
                PSY.set_tap!(star_leg, tap)
                check_terms(
                    POM._tapped_admittance(model, adm, tap),
                    PNM.ybus_branch_entries(winding),
                )
            end
        end
        PSY.set_α!(star_leg, 0.0)
        PSY.set_tap!(star_leg, 1.0)
    end
end

@testset "a voltage-controlled circuit and its regulated bus survive a network reduction" begin
    # Without the bus-pinning rule the controlled circuit is merged into a reduced arc and
    # `_validate_controlled_branch_not_reduced` rejects the build.
    for case in TRANSFORMER_CASES
        index = last(case.circuit_indices)
        fixture = case.make(VOLTAGE_CONTROL; circuit_index = index)
        model, status = _build_controlled(
            fixture.sys, ACPNetworkModel, case.device_type;
            optimizer = ipopt_optimizer, network_source = NetworkReductionSpec([PNM.RadialReduction(), PNM.DegreeTwoReduction()]),
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        tap = IOM.get_variable(container, TapRatioVariable, case.device_type)
        @test fixture.axis_name in axes(tap)[1]

        # The regulated bus must be retained too, else the voltage constraint has nothing
        # to bind against.
        vm = IOM.get_variable(container, VoltageMagnitude, PSY.ACBus)
        @test fixture.regulated_name in axes(vm)[1]
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

@testset "StaticBranch models three-winding off-nominal taps under DCP" begin
    sys = _sys5_with_3w()
    transformer = PSY.get_component(PSY.ThreeWindingTransformer, sys, T3W_NAME)
    # The fixture is built at nominal, so an off-nominal tap has to be set here for the
    # tap-divided susceptance to be doing any work.
    PSY.set_tap!(PSY.get_secondary_circuit(transformer), 1.05)
    PSY.set_tap!(PSY.get_tertiary_circuit(transformer), 0.95)

    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, PSY.ThreeWindingTransformer, StaticBranch)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = IOM.OptimizationProblemOutputs(model)
    base = IOM.get_model_base_power(res)
    pflow = read_expression(
        res,
        "BThetaBranchFlow__ThreeWindingTransformer";
        table_format = TableFormat.WIDE,
    )
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)

    for (index, star_leg) in enumerate(PSY.get_circuits(transformer))
        name = T3W_WINDINGS[index]
        @test name in names(pflow)

        winding = PNM.ThreeWindingTransformerCircuit(transformer, index)
        adm = PNM.branch_admittance(winding)
        x = -adm.b / (adm.g^2 + adm.b^2)
        @test 1 / (x * adm.tap) ≈ PNM.get_series_susceptance(winding, PSY.SU)

        arc = PSY.get_arc(star_leg)
        fr = PSY.get_name(PSY.get_from(arc))
        to = PSY.get_name(PSY.get_to(arc))
        shift = PNM.get_series_phase_shift(winding)
        for r in 1:nrow(pflow)
            p_pu = pflow[r, name] / base
            expected = (va[r, fr] - va[r, to] - shift) / (x * adm.tap)
            @test isapprox(p_pu, expected; atol = 1e-5)
        end
    end
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
