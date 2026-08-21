######################################## helpers #######################################

_has_tap_variable(container) =
    any(k -> occursin("TapRatioVariable", string(k)), keys(IOM.get_variables(container)))

_control_constraint(mode) =
    mode === VOLTAGE_CONTROL ? VoltageControlConstraint : ReactivePowerFlowControlConstraint

_has_control_constraints(container) = any(
    k -> any(
        c -> occursin(string(nameof(c)), string(k)),
        (VoltageControlConstraint, ReactivePowerFlowControlConstraint),
    ),
    keys(IOM.get_constraints(container)),
)

function _control_constraints(container, constraint, device_type)
    key = IOM.ConstraintKey(constraint, device_type)
    haskey(IOM.get_constraints(container), key) || return nothing
    return IOM.get_constraint(container, key)
end

_variable_key(variable, device_type) = "$(nameof(variable))__$(nameof(device_type))"

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

@testset "a controlled circuit builds no tap variable or control constraint while enable_controls is off" begin
    for case in TRANSFORMER_CASES,
        network_formulation in AC_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        mode in TAP_CONTROLS

        fixture = case.make(mode)
        model, status = _build_controlled(
            fixture.sys, network_formulation, case.device_type;
            enable = false, optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        @test !_has_tap_variable(container)
        @test !_has_control_constraints(container)
    end
end

@testset "TapRatioVariable and the control constraint are created only for controlled circuits" begin
    limits = (min = 0.95, max = 1.05)
    for case in TRANSFORMER_CASES,
        network_formulation in AC_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        mode in TAP_CONTROLS

        # Deliberately not circuit 1: the untouched circuits are left UNDEFINED, so only
        # the controlled one may appear on the axis.
        controlled = last(case.circuit_indices)
        fixture = case.make(mode; circuit_index = controlled, control_limits = limits)
        model, status = _build_controlled(
            fixture.sys, network_formulation, case.device_type;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        tap = IOM.get_variable(container, TapRatioVariable, case.device_type)
        @test axes(tap)[1] == [fixture.axis_name]

        band = PSY.get_control_limits(fixture.circuit)
        for t in get_time_steps(container)
            var = tap[fixture.axis_name, t]
            @test JuMP.has_lower_bound(var)
            @test JuMP.has_upper_bound(var)
            @test JuMP.lower_bound(var) ≈ band.min
            @test JuMP.upper_bound(var) ≈ band.max
        end

        cons = _control_constraints(container, _control_constraint(mode), case.device_type)
        @test cons !== nothing
        if cons !== nothing
            @test unique(first(k) for k in keys(cons.data)) == [fixture.axis_name]
            for side in 1:2, t in get_time_steps(container)
                @test haskey(cons.data, (fixture.axis_name, side, t))
            end
        end
    end
end

@testset "a tap control scheme builds no tap variable on a DC network" begin
    for case in TRANSFORMER_CASES,
        network_formulation in DC_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        mode in TAP_CONTROLS

        fixture = case.make(mode)
        output_dir = mktempdir(; cleanup = true)
        model, status = _build_controlled(
            fixture.sys, network_formulation, case.device_type;
            optimizer = ipopt_optimizer, output_dir = output_dir,
            formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        @test !_has_tap_variable(container)
        @test !_has_control_constraints(container)

        log = read(joinpath(output_dir, "operation_problem.log"), String)
        @test occursin("DC networks do not support variable-tap", log)
    end
end

################################### VOLTAGE objective ##################################

# Solve system with no controls to get bus voltage reference to make sure our
# control constraint tests are doing something.
function _uncontrolled_voltage(case, bus_name, network_formulation, branch_formulation)
    model, status = _build_controlled(
        case.plain(), network_formulation, case.device_type;
        enable = false, optimizer = ipopt_optimizer, formulation = branch_formulation,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    return first(_voltage_magnitudes(res, bus_name, network_formulation))
end

@testset "VOLTAGE control holds the regulated bus inside its limits" begin
    for case in TRANSFORMER_CASES, branch_formulation in CONTROL_FORMULATIONS
        rawsys = case.plain()
        numbers = case.voltage_bus_numbers(rawsys)
        for network_formulation in VOLTAGE_NETWORKS, number in numbers
            bus_name = PSY.get_name(PSY.get_bus(rawsys, number))
            free_vm = _uncontrolled_voltage(case, bus_name, network_formulation, branch_formulation)
            limits = (min = free_vm - 0.02, max = free_vm - 0.01)

            fixture =
                case.make(VOLTAGE_CONTROL; regulated = number, quantity_limits = limits)
            model, status = _build_controlled(
                fixture.sys, network_formulation, case.device_type;
                optimizer = ipopt_optimizer, formulation = branch_formulation,
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
    limits = (min = -0.03, max = 0.05)

    for case in TRANSFORMER_CASES,
        network_formulation in AC_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        index in case.circuit_indices

        fixture =
            case.make(Q_FLOW_CONTROL; circuit_index = index, quantity_limits = limits)
        model, status = _build_controlled(
            fixture.sys, network_formulation, case.device_type;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
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

    for case in TRANSFORMER_CASES,
        network_formulation in AC_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        index in case.circuit_indices

        fixed = case.make(
            VOLTAGE_CONTROL; circuit_index = index, quantity_limits = limits,
        )
        model_fixed, status_fixed = _build_controlled(
            fixed.sys, network_formulation, case.device_type;
            enable = false, optimizer = ipopt_optimizer, formulation = branch_formulation,
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
            optimizer = ipopt_optimizer, formulation = branch_formulation,
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
    for case in TRANSFORMER_CASES
        rawsys = case.plain()
        numbers = [PSY.get_number(b) for b in PSY.get_components(PSY.ACBus, rawsys)]
        for index in case.circuit_indices, number in numbers
            fixture = case.make(
                VOLTAGE_CONTROL;
                circuit_index = index,
                regulated = number,
                quantity_limits = PSY.get_voltage_limits(PSY.get_bus(rawsys, number)),
            )
            model, status = _build_controlled(
                fixture.sys, ACPNetworkModel, case.device_type;
                optimizer = ipopt_optimizer,
                network_source = NetworkReductionSpec([
                    PNM.RadialReduction(),
                    PNM.DegreeTwoReduction(),
                ]),
            )
            @test status == IOM.ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)
            tap = IOM.get_variable(container, TapRatioVariable, case.device_type)
            @test fixture.axis_name in axes(tap)[1]

            vm = IOM.get_variable(container, VoltageMagnitude, PSY.ACBus)
            @test fixture.regulated_name in axes(vm)[1]
        end
    end
end

################################ static tap ############################################

function _solved_dcp_model(sys, device_type, branch_formulation)
    template = get_thermal_dispatch_template_network(
        NetworkModel(DCPNetworkModel; evaluations = power_flow_evaluations(DCPowerFlow())),
    )
    set_device_model!(template, device_type, branch_formulation)
    # Ipopt rather than HiGHS: HiGHS errors out on this QP (issue #230).
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    return IOM.get_optimization_container(model)
end

_dc_flows(container, ::Type{StaticBranch}, device_type) =
    IOM.get_expression(container, BThetaBranchFlow, device_type)
_dc_flows(container, ::Type{StaticBranchBounds}, device_type) =
    IOM.get_variable(container, FlowActivePowerVariable, device_type)

@testset "off-nominal two-winding taps agree with a PowerFlows DC solve (c_sys14)" begin
    for branch_formulation in CONTROL_FORMULATIONS
        sys = PSB.build_system(PSITestSystems, "c_sys14")
        # Guard: the test system must actually carry a non-unit tap, else this proves
        # nothing.
        @test any(
            tr -> !isapprox(PSY.get_tap(PSY.get_circuit(tr)), 1.0; atol = 1e-6),
            PSY.get_components(PSY.TwoWindingTransformer, sys),
        )

        container = _solved_dcp_model(sys, PSY.TwoWindingTransformer, branch_formulation)
        flows = _dc_flows(container, branch_formulation, PSY.TwoWindingTransformer)
        pf_flows = lookup_value(
            container,
            AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, PSY.TwoWindingTransformer),
        )
        for name in axes(flows)[1], t in get_time_steps(container)
            @test isapprox(JuMP.value(flows[name, t]), pf_flows[name, t]; atol = 1e-6)
        end

        va = IOM.get_variable(container, VoltageAngle, PSY.ACBus)
        pf_va = lookup_value(container, AuxVarKey(POM.PowerFlowVoltageAngle, PSY.ACBus))
        for name in axes(va)[1], t in get_time_steps(container)
            number = PSY.get_number(PSY.get_component(PSY.ACBus, sys, name))
            @test isapprox(JuMP.value(va[name, t]), pf_va[number, t]; atol = 1e-6)
        end
    end
end
