######################################## helpers #######################################

# The active-flow object the ACTIVE_POWER_FLOW band is written against, one per
# network x formulation pair — the test-side mirror of `POM._active_flow_array`.
_phase_flows(container, ::Type{StaticBranch}, ::Type{DCPNetworkModel}, device_type) =
    IOM.get_expression(container, BThetaBranchFlow, device_type)
_phase_flows(
    container,
    ::Type{StaticBranch},
    ::Type{<:AbstractPTDFNetworkModel},
    device_type,
) = IOM.get_expression(container, PTDFBranchFlow, device_type)
_phase_flows(
    container,
    ::Type{<:Union{StaticBranch, StaticBranchBounds}},
    ::Type{DCPLLNetworkModel},
    device_type,
) = IOM.get_variable(container, FlowActivePowerFromToVariable, device_type)
_phase_flows(
    container,
    ::Type{StaticBranchBounds},
    ::Type{<:Union{DCPNetworkModel, AbstractPTDFNetworkModel}},
    device_type,
) = IOM.get_variable(container, FlowActivePowerVariable, device_type)

_has_phase_variable(container) = any(
    k -> occursin("PhaseShifterAngle", string(k)),
    keys(IOM.get_variables(container)),
)

_has_phase_constraints(container) = any(
    k -> occursin("ActivePowerFlowControlConstraint", string(k)),
    keys(IOM.get_constraints(container)),
)

function _phase_constraints(container, device_type)
    key = IOM.ConstraintKey(ActivePowerFlowControlConstraint, device_type)
    haskey(IOM.get_constraints(container), key) || return nothing
    return IOM.get_constraint(container, key)
end

# Free (uncontrolled) value of the circuit flow, the reference the efficacy bands are cut
# from — without it a band that happens to contain the free solution would prove nothing.
function _free_flow(network_formulation, branch_formulation, axis_name)
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    model, status = _build_controlled(
        sys, network_formulation, PSY.TwoWindingTransformer;
        enable = false, optimizer = ipopt_optimizer, formulation = branch_formulation,
    )
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container = IOM.get_optimization_container(model)
    flows = _phase_flows(
        container, branch_formulation, network_formulation, PSY.TwoWindingTransformer,
    )
    return JuMP.value(flows[axis_name, first(get_time_steps(container))])
end

_meshed_fixture(; kwargs...) =
    _controlled_sys14(P_FLOW_CONTROL; circuit_index = MESHED_TRANSFORMER_INDEX, kwargs...)

################################### attribute plumbing #################################

@testset "a phase-controlled circuit builds nothing while enable_controls is off" begin
    for network_formulation in PHASE_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS

        fixture = _meshed_fixture()
        model, status = _build_controlled(
            fixture.sys, network_formulation, PSY.TwoWindingTransformer;
            enable = false, optimizer = ipopt_optimizer,
            formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        @test !_has_phase_variable(container)
        @test !_has_phase_constraints(container)
    end
end

@testset "PhaseShifterAngle and its constraint are created only for controlled circuits" begin
    band = (min = -0.25, max = 0.2)
    for network_formulation in PHASE_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS

        # Deliberately not circuit 1: the untouched circuits are left UNDEFINED, so only
        # the controlled one may appear on the axis.
        fixture = _controlled_sys14(
            P_FLOW_CONTROL;
            circuit_index = length(TRANSFORMER_NAMES),
            control_limits = band,
        )
        model, status = _build_controlled(
            fixture.sys, network_formulation, PSY.TwoWindingTransformer;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        alpha =
            IOM.get_variable(container, PhaseShifterAngle, PSY.TwoWindingTransformer)
        @test axes(alpha)[1] == [fixture.axis_name]

        for t in get_time_steps(container)
            var = alpha[fixture.axis_name, t]
            @test JuMP.has_lower_bound(var)
            @test JuMP.has_upper_bound(var)
            @test JuMP.lower_bound(var) ≈ band.min
            @test JuMP.upper_bound(var) ≈ band.max
            @test JuMP.start_value(var) ≈ 0.0
        end

        cons = _phase_constraints(container, PSY.TwoWindingTransformer)
        @test cons !== nothing
        if cons !== nothing
            @test axes(cons)[1] == [fixture.axis_name]
            @test size(cons) == (1, 2, length(get_time_steps(container)))
            @test all(isassigned(cons.data, i) for i in eachindex(cons.data))
        end
    end
end

@testset "a three-winding circuit carries the phase variable and constraint too" begin
    for branch_formulation in CONTROL_FORMULATIONS, index in 1:3
        fixture = _controlled_sys3w(P_FLOW_CONTROL; circuit_index = index)
        model, status = _build_controlled(
            fixture.sys, DCPNetworkModel, PSY.ThreeWindingTransformer;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        alpha =
            IOM.get_variable(container, PhaseShifterAngle, PSY.ThreeWindingTransformer)
        @test axes(alpha)[1] == [fixture.axis_name]

        cons = _phase_constraints(container, PSY.ThreeWindingTransformer)
        @test cons !== nothing
        cons === nothing || @test axes(cons)[1] == [fixture.axis_name]
    end
end

@testset "a phase control scheme builds nothing on an AC or NFA network" begin
    for network_formulation in (AC_NETWORKS..., NFANetworkModel),
        branch_formulation in CONTROL_FORMULATIONS

        fixture = _meshed_fixture()
        output_dir = mktempdir(; cleanup = true)
        model, status = _build_controlled(
            fixture.sys, network_formulation, PSY.TwoWindingTransformer;
            optimizer = ipopt_optimizer, output_dir = output_dir,
            formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        @test !_has_phase_variable(container)
        @test !_has_phase_constraints(container)

        # Build warnings go to the build's own log, not to the caller's logger.
        log = read(joinpath(output_dir, "operation_problem.log"), String)
        @test occursin("phase control is only supported on", log)
    end
end

################################### model invariants ###################################

@testset "an angle pinned at the stored shift reproduces the uncontrolled model" begin
    # The sign test. PNM's convention is `f = b·(θ_f − θ_t − α)`; under the opposite sign
    # (legacy PSI's `+α`) a non-zero stored shift would give a different solution here.
    for network_formulation in PHASE_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS,
        stored in (0.0, 0.12)

        fixed = _meshed_fixture(; alpha = stored)
        model_fixed, status_fixed = _build_controlled(
            fixed.sys, network_formulation, PSY.TwoWindingTransformer;
            enable = false, optimizer = ipopt_optimizer,
            formulation = branch_formulation,
        )
        @test status_fixed == IOM.ModelBuildStatus.BUILT
        @test solve!(model_fixed) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        varying = _meshed_fixture(; alpha = stored)
        model_var, status_var = _build_controlled(
            varying.sys, network_formulation, PSY.TwoWindingTransformer;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status_var == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model_var)
        alpha =
            IOM.get_variable(container, PhaseShifterAngle, PSY.TwoWindingTransformer)
        for t in get_time_steps(container)
            JuMP.fix(alpha[varying.axis_name, t], stored; force = true)
        end
        @test solve!(model_var) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        res_fixed = IOM.OptimizationProblemOutputs(model_fixed)
        res_var = IOM.OptimizationProblemOutputs(model_var)
        @test isapprox(
            IOM.get_objective_value(res_var),
            IOM.get_objective_value(res_fixed);
            rtol = 1e-4,
        )

        flows_fixed = _phase_flows(
            IOM.get_optimization_container(model_fixed),
            branch_formulation,
            network_formulation,
            PSY.TwoWindingTransformer,
        )
        flows_var = _phase_flows(
            container, branch_formulation, network_formulation,
            PSY.TwoWindingTransformer,
        )
        for name in axes(flows_var)[1], t in get_time_steps(container)
            @test isapprox(
                JuMP.value(flows_var[name, t]),
                JuMP.value(flows_fixed[name, t]);
                atol = 1e-4,
            )
        end
    end
end

@testset "ACTIVE_POWER_FLOW control holds the circuit flow inside its limits" begin
    axis_name = TRANSFORMER_NAMES[MESHED_TRANSFORMER_INDEX]
    for network_formulation in PHASE_NETWORKS,
        branch_formulation in CONTROL_FORMULATIONS

        free = _free_flow(network_formulation, branch_formulation, axis_name)
        # Strictly inside the free solution, so the band can only be met by moving α.
        band = (min = free - 0.10, max = free - 0.05)

        fixture = _meshed_fixture(; quantity_limits = band)
        model, status = _build_controlled(
            fixture.sys, network_formulation, PSY.TwoWindingTransformer;
            optimizer = ipopt_optimizer, formulation = branch_formulation,
        )
        @test status == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        container = IOM.get_optimization_container(model)
        flows = _phase_flows(
            container, branch_formulation, network_formulation,
            PSY.TwoWindingTransformer,
        )
        for t in get_time_steps(container)
            value = JuMP.value(flows[axis_name, t])
            @test value >= band.min - 1e-5
            @test value <= band.max + 1e-5
        end
    end
end

@testset "DCP and PTDF agree on every flow at the same phase angle" begin
    # Independent of the DCP angle path: pins the PTDF nodal-injection pair (`±b·α`) and
    # the `-b·α` flow offset against the B-theta Ohm's law.
    for branch_formulation in CONTROL_FORMULATIONS, pinned in (0.0, 0.12, -0.2)
        flows_by_network = Dict{DataType, Dict{String, Float64}}()
        for network_formulation in (DCPNetworkModel, PTDFNetworkModel)
            fixture = _meshed_fixture()
            model, status = _build_controlled(
                fixture.sys, network_formulation, PSY.TwoWindingTransformer;
                optimizer = ipopt_optimizer, formulation = branch_formulation,
            )
            @test status == IOM.ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)
            alpha =
                IOM.get_variable(container, PhaseShifterAngle, PSY.TwoWindingTransformer)
            for t in get_time_steps(container)
                JuMP.fix(alpha[fixture.axis_name, t], pinned; force = true)
            end
            @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

            flows = _phase_flows(
                container, branch_formulation, network_formulation,
                PSY.TwoWindingTransformer,
            )
            t1 = first(get_time_steps(container))
            flows_by_network[network_formulation] =
                Dict(name => JuMP.value(flows[name, t1]) for name in axes(flows)[1])
        end
        for (name, value) in flows_by_network[DCPNetworkModel]
            @test isapprox(value, flows_by_network[PTDFNetworkModel][name]; atol = 1e-5)
        end
    end
end

################################ static phase shift ####################################

@testset "a non-zero static phase shift agrees with a PowerFlows DC solve (c_sys14)" begin
    # Guards `_dc_shift`'s sign against an independent DC solve. Static only: a variable α
    # is not pushed to the power-flow evaluator.
    for branch_formulation in CONTROL_FORMULATIONS
        sys = PSB.build_system(PSITestSystems, "c_sys14")
        transformer =
            PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
        PSY.set_α!(PSY.get_circuit(transformer), 0.15)

        template = get_thermal_dispatch_template_network(
            NetworkModel(
                DCPNetworkModel;
                evaluations = power_flow_evaluations(DCPowerFlow()),
            ),
        )
        set_device_model!(template, PSY.TwoWindingTransformer, branch_formulation)
        # Ipopt rather than HiGHS: HiGHS errors out on this QP (issue #230).
        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        container = IOM.get_optimization_container(model)
        flows = _phase_flows(
            container, branch_formulation, DCPNetworkModel, PSY.TwoWindingTransformer,
        )
        pf_flows = lookup_value(
            container,
            AuxVarKey(POM.PowerFlowBranchActivePowerFromTo, PSY.TwoWindingTransformer),
        )
        for name in axes(flows)[1], t in get_time_steps(container)
            @test isapprox(JuMP.value(flows[name, t]), pf_flows[name, t]; atol = 1e-6)
        end
    end
end

################################## network reduction ###################################

@testset "a phase-controlled circuit and its arc survive a network reduction" begin
    for index in 1:length(TRANSFORMER_NAMES)
        fixture = _controlled_sys14(P_FLOW_CONTROL; circuit_index = index)
        model, status = _build_controlled(
            fixture.sys, DCPNetworkModel, PSY.TwoWindingTransformer;
            optimizer = ipopt_optimizer,
            network_source = NetworkReductionSpec([
                PNM.RadialReduction(),
                PNM.DegreeTwoReduction(),
            ]),
        )
        @test status == IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)
        alpha =
            IOM.get_variable(container, PhaseShifterAngle, PSY.TwoWindingTransformer)
        @test axes(alpha)[1] == [fixture.axis_name]
    end
end

@testset "a phase-controlled circuit merged with a parallel branch fails with a clear error" begin
    # Pinning the endpoint buses keeps the circuit off the radial/degree-two paths, but a
    # parallel branch on the same arc is merged regardless, which would silently drop the
    # control.
    fixture = _meshed_fixture()
    circuit = fixture.circuit
    PSY.add_component!(
        fixture.sys,
        PSY.TwoWindingTransformer(;
            name = "parallel_to_$(fixture.axis_name)",
            circuit = PSY.TransformerCircuit(;
                available = true,
                arc = PSY.get_arc(circuit),
                r = PSY.get_r(circuit, PSY.SU),
                x = PSY.get_x(circuit, PSY.SU),
                tap = 1.0,
                α = 0.0,
                rating = PSY.get_rating(circuit, PSY.SU),
                base_power = PSY.get_base_power(fixture.sys, PSY.NU),
            ),
            magnetizing_shunt = 0.0 + 0.0im,
            shunt_location = PSY.TwoWindingTransformerShuntLocation.PRIMARY,
        ),
    )
    template = _controlled_template(DCPNetworkModel, PSY.TwoWindingTransformer)
    model = DecisionModel(template, fixture.sys; optimizer = ipopt_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out, console_level = Logging.Error) ==
          IOM.ModelBuildStatus.FAILED
    log = read(joinpath(out, "operation_problem.log"), String)
    @test occursin("Controlled transformer circuit", log)
    @test occursin(fixture.axis_name, log)
end
