import PowerNetworkMatrices as PNM

# build! routes log records emitted inside build_model! to the model's internal
# file logger (operation_problem.log), so they are NOT visible to @test_logs at
# the call site. To assert (or rule out) the REF-less pin warning we read it.
function _build_log_contains(output_dir, needle)
    logf = joinpath(output_dir, "operation_problem.log")
    isfile(logf) || return false
    return occursin(needle, read(logf, String))
end

@testset "native DCPNetworkModel builds and solves (c_sys5)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out) == IOM.ModelBuildStatus.BUILT
    # Real REF present (nodeD): pinned silently, no spurious REF-less warning.
    @test !_build_log_contains(out, "no ACBusTypes.REF bus")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # --- DC ohm-law physics check ---
    # StaticBranch under DCP carries the flow as the BThetaBranchFlow expression (in
    # per-unit):
    #   p_pu == b_dc * (va_from - va_to - alpha)
    # where `b_dc = PNM.get_series_susceptance(line, PSY.SU)` is the r-free `(1/x)/tap`
    # that BA/PTDF also use, so native DCP and PTDF agree. There is no
    # FlowActivePowerVariable/defining equality on this path.
    # read_expression returns BThetaBranchFlow in natural units (MW);
    # VoltageAngle is unitless (radians, no conversion). Divide flow by base_power.
    res = IOM.OptimizationProblemOutputs(model)
    base_power = IOM.get_model_base_power(res)
    pflow =
        read_expression(res, "BThetaBranchFlow__Line"; table_format = TableFormat.WIDE)
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)
    line = first(PSY.get_components(PSY.Line, sys))
    b_dc = PNM.get_series_susceptance(line, PSY.SU)
    fr = PSY.get_name(PSY.get_from(PSY.get_arc(line)))
    to = PSY.get_name(PSY.get_to(PSY.get_arc(line)))
    lname = PSY.get_name(line)
    # Row 1 = first time step; columns are component names.
    # Compare both sides in per-unit: divide MW output by base_power.
    @test isapprox(
        pflow[1, lname] / base_power,
        b_dc * (va[1, fr] - va[1, to]);
        atol = 1e-6,
    )
end

@testset "native ACPNetworkModel builds and solves (c_sys5)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # --- ACP voltage-magnitude physics check ---
    # The native ACP model enforces bus voltage magnitude within PSY.get_voltage_limits(bus)
    # bounds (per-unit, unitless). Assert the solved vm stays in bounds for every bus.
    res = IOM.OptimizationProblemOutputs(model)
    vm = read_variable(res, "VoltageMagnitude__ACBus"; table_format = TableFormat.WIDE)
    for bus in PSY.get_components(PSY.ACBus, sys)
        lim = PSY.get_voltage_limits(bus)
        bname = PSY.get_name(bus)
        v = vm[1, bname]
        @test lim.min - 1e-6 <= v <= lim.max + 1e-6
    end
end

@testset "native DCPNetworkModel solves under network reduction (c_sys14)" begin
    # KNOWN BROKEN, tracked separately: the model builds but is rate-limit infeasible
    # under radial + degree-two reduction. Diagnosed to be independent of the transformer
    # port -- it fails identically with the pre-port susceptance convention
    # (`x/(r^2+x^2)`), and inflating every rating to 100 pu makes it solve. Unreduced
    # c_sys14 solves, and ACP under the same reduction solves, so the fault is in the
    # reduced DCP rating path, not the DC law. Restore both asserts once fixed.
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    net = NetworkModel(
        DCPNetworkModel;
        reduce_radial_branches = true,
        reduce_degree_two_branches = true,
    )
    template = get_thermal_dispatch_template_network(net)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test_broken solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "native ACPNetworkModel solves under network reduction (c_sys14)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys14")
    net = NetworkModel(
        ACPNetworkModel;
        reduce_radial_branches = true,
        reduce_degree_two_branches = true,
    )
    template = get_thermal_dispatch_template_network(net)
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "native DCP pins PNM's reference for a REF-less system (no warn, non-degenerate)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    for b in PSY.get_components(PSY.ACBus, sys)
        if PSY.get_bustype(b) == PSY.ACBusTypes.REF
            PSY.set_bustype!(b, PSY.ACBusTypes.PV)
        end
    end
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out) == IOM.ModelBuildStatus.BUILT
    # No ACBusTypes.REF bus exists, yet PNM still assigns each subnetwork a
    # reference (the subnetwork_axes key). The model pins THAT bus directly — no
    # re-derivation by bustype, no arbitrary-slack fallback, no warning.
    @test !_build_log_contains(out, "no ACBusTypes.REF bus")
    container = IOM.get_optimization_container(model)
    ref_cons =
        IOM.get_constraint(container, IOM.ConstraintKey(ReferenceBusConstraint, PSY.ACBus))
    @test !isempty(ref_cons)  # a reference WAS pinned (island not skipped)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    # The pinned reference (PNM's subnetwork key) has angle 0 -> unique, non-degenerate.
    res = IOM.OptimizationProblemOutputs(model)
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)
    num_to_name =
        Dict(
            PSY.get_number(b) => PSY.get_name(b) for b in PSY.get_components(PSY.ACBus, sys)
        )
    for k in axes(ref_cons, 1)
        @test isapprox(va[1, num_to_name[k]], 0.0; atol = 1e-8)
    end
end

@testset "native ACP pins PNM's reference for a REF-less system (no warn, vm+va)" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    for b in PSY.get_components(PSY.ACBus, sys)
        if PSY.get_bustype(b) == PSY.ACBusTypes.REF
            PSY.set_bustype!(b, PSY.ACBusTypes.PV)
        end
    end
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out) == IOM.ModelBuildStatus.BUILT
    @test !_build_log_contains(out, "no ACBusTypes.REF bus")
    container = IOM.get_optimization_container(model)
    ref_cons = IOM.get_constraint(
        container,
        IOM.ConstraintKey(ReferenceBusConstraint, PSY.ACBus, "va"),
    )
    @test !isempty(ref_cons)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    va = read_variable(res, "VoltageAngle__ACBus"; table_format = TableFormat.WIDE)
    num_to_name =
        Dict(
            PSY.get_number(b) => PSY.get_name(b) for b in PSY.get_components(PSY.ACBus, sys)
        )
    for k in axes(ref_cons, 1)
        @test isapprox(va[1, num_to_name[k]], 0.0; atol = 1e-8)
    end
end

@testset "reduced arc admittance uses PNM series equivalent, not original branch" begin
    # `case11_network_reductions` is purpose-built to produce series arcs under the
    # radial + degree-two reduction (c_sys5/c_sys14 yield no reducible chains).
    # The reduction data is built exactly as POM's `instantiate_network_model!` does
    # (PNM.Ybus with RadialReduction + DegreeTwoReduction), so the same
    # NetworkReductionData the build path stores on the network model is exercised
    # directly here without depending on time-series/forecast data.
    sys = PSB.build_system(PSITestSystems, "case11_network_reductions")
    ybus = PNM.Ybus(
        sys;
        network_reductions = PNM.NetworkReduction[
            PNM.RadialReduction(),
            PNM.DegreeTwoReduction(),
        ],
    )
    nr = deepcopy(PNM.get_network_reduction_data(ybus))
    @test !isempty(nr)

    series_map = PNM.get_series_branch_map(nr)
    @test !isempty(series_map)  # degree-2 reduction produces series arcs

    (from_no, to_no), chain = first(series_map)
    resolved = PNM.reduced_arc_admittance(nr, from_no, to_no)
    @test resolved !== nothing
    expected = PNM.branch_admittance(chain, nr)
    @test isapprox(resolved.b, expected.b; atol = 1e-9)

    # Non-triviality: the series equivalent is the MERGED admittance of the chain, so
    # it must differ from any single constituent branch's own admittance. This is the
    # whole point of leveraging PNM — the old native path used a single branch's value
    # for the reduced arc, which is wrong.
    members = collect(chain)
    @test length(members) >= 2
    member_b = PNM.branch_admittance(members[1]).b
    @test !isapprox(resolved.b, member_b; rtol = 1e-3)

    # Reversed-orientation arc exercises the `_reverse_admittance` path: series b is
    # symmetric, from/to shunts swap, and any phase shift negates.
    if !haskey(series_map, (to_no, from_no))
        reversed = PNM.reduced_arc_admittance(nr, to_no, from_no)
        @test reversed !== nothing
        @test isapprox(reversed.b, resolved.b; atol = 1e-9)
        @test isapprox(reversed.b_fr, resolved.b_to; atol = 1e-9)
        @test isapprox(reversed.shift, -resolved.shift; atol = 1e-12)
    end

    # A direct (un-reduced) arc resolves to `nothing` — the caller falls back to the
    # branch's own admittance.
    @test PNM.reduced_arc_admittance(nr, -1, -2) === nothing
end

@testset "ThreeWindingTransformer decomposes into three star arcs" begin
    # psy6: a 3W transformer is three `TransformerCircuit`s, each a terminal->star arc.
    # POM emits one BranchGeometry per circuit, so the generic builders cover 3W with no
    # three-winding-specific code; the axes must be PNM's "<name>_winding_i" keys.
    sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
    busD = PSY.get_component(PSY.ACBus, sys, "nodeD")
    t3w = add_three_winding_transformer!(sys, busD; α_secondary = 0.05)
    names = three_winding_names(t3w)

    # PNM's winding wrapper is the admittance-bearing element; POM reads it through the
    # same `branch_admittance` used for lines and 2W transformers.
    for (i, circuit) in enumerate(PSY.get_circuits(t3w))
        w = PNM.ThreeWindingTransformerCircuit(t3w, i)
        @test PNM.get_name(w) == names[i]
        adm = PNM.branch_admittance(w)
        y = inv(complex(PSY.get_r(circuit, PSY.SU), PSY.get_x(circuit, PSY.SU)))
        @test isapprox(adm.g, real(y); atol = 1e-12)
        @test isapprox(adm.b, imag(y); atol = 1e-12)
        @test adm.tap == PSY.get_tap(circuit)
        @test adm.shift == PSY.get_α(circuit)
    end

    # The geometry walk yields one entry per available circuit, named per PNM.
    geoms = [POM._branch_geometry(e) for e in POM._branch_elements(t3w)]
    @test [g.name for g in geoms] == names
    @test all(g.to_name == PSY.get_name(PSY.get_star_bus(t3w)) for g in geoms)

    # DCP end to end: flow keys are the winding names and each satisfies the DC law
    # against the star bus angle, including the shifted secondary.
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, DeviceModel(PSY.ThreeWindingTransformer, StaticBranch))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir()) == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    bfe = IOM.get_expression(container, POM.BThetaBranchFlow, PSY.ThreeWindingTransformer)
    @test sort(collect(axes(bfe, 1))) == sort(names)

    va = IOM.get_variable(container, POM.VoltageAngle, PSY.ACBus)
    star_name = PSY.get_name(PSY.get_star_bus(t3w))
    for (i, circuit) in enumerate(PSY.get_circuits(t3w))
        b_dc =
            PNM.get_series_susceptance(PNM.ThreeWindingTransformerCircuit(t3w, i), PSY.SU)
        term_name = PSY.get_name(PSY.get_from(PSY.get_arc(circuit)))
        expected =
            b_dc * (
                JuMP.value(va[term_name, 1]) - JuMP.value(va[star_name, 1]) -
                PSY.get_α(circuit)
            )
        @test isapprox(JuMP.value(bfe[names[i], 1]), expected; atol = 1e-6)
    end

    # The unrated tertiary (PSS/E RATE=0 -> `nothing`) is unlimited: no rate row.
    rate_keys = [
        k for k in keys(IOM.get_constraints(container)) if
        IOM.get_entry_type(k) === POM.FlowRateConstraint &&
        IOM.get_component_type(k) === PSY.ThreeWindingTransformer
    ]
    for k in rate_keys
        @test !(names[3] in axes(IOM.get_constraints(container)[k], 1))
        @test names[1] in axes(IOM.get_constraints(container)[k], 1)
    end
end

@testset "native AC rate limits reject a zero-rating branch at build" begin
    # MATPOWER's rateA = 0 means "unlimited"; p² + q² ≤ 0 would silently pin the branch
    # to zero flow (deleting it from the network). Reject it loudly, matching the IVR
    # current-rating behavior.
    for network_formulation in (ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel)
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        PSY.set_rating!(PSY.get_component(Line, sys, "1"), 0.0 * PSY.SU)
        template = get_thermal_dispatch_template_network(NetworkModel(network_formulation))
        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        out = mktempdir(; cleanup = true)
        @test build!(model; output_dir = out, console_level = Logging.Error) ==
              IOM.ModelBuildStatus.FAILED
        log = read(joinpath(out, "operation_problem.log"), String)
        @test occursin("zero rating", log)
    end
end

# The NetworkFlowConstraint containers each network model must build for StaticBranchBounds.
# The AC laws are split by meta (one container per directional flow); the DC laws are a
# single unmetaed container. NFA is the flow approximation: it has no Ohm's law at all.
_ohms_law_metas(::Type{<:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel}}) =
    ["p_ft", "q_ft", "p_tf", "q_tf"]
_ohms_law_metas(::Type{IVRNetworkModel}) =
    ["p_ft", "q_ft", "p_tf", "q_tf", "cr_fr", "ci_fr", "cr_to", "ci_to", "vr_to", "vi_to"]
_ohms_law_metas(::Type{<:Union{DCPNetworkModel, DCPLLNetworkModel, PTDFNetworkModel}}) =
    [IOM.CONTAINER_KEY_EMPTY_META]
_ohms_law_metas(::Type{NFANetworkModel}) = String[]

@testset "StaticBranchBounds builds and solves on every native network model" begin
    for (network_formulation, optimizer) in (
        (DCPNetworkModel, HiGHS_optimizer),
        (NFANetworkModel, HiGHS_optimizer),
        (PTDFNetworkModel, HiGHS_optimizer),
        (DCPLLNetworkModel, ipopt_optimizer),
        (ACPNetworkModel, ipopt_optimizer),
        (ACRNetworkModel, ipopt_optimizer),
        (LPACCNetworkModel, ipopt_optimizer),
        (IVRNetworkModel, ipopt_optimizer),
    )
        @testset "$network_formulation" begin
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            template =
                get_thermal_dispatch_template_network(NetworkModel(network_formulation))
            set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
            model = DecisionModel(template, sys; optimizer = optimizer)
            @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT
            @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

            # Bounding the flow variables is not the model: without the Ohm's law tying the
            # flows to the bus voltages (or, on PTDF, to PTDFBranchFlow), the build and the
            # solve both still succeed on a strict relaxation.
            container = IOM.get_optimization_container(model)
            for meta in _ohms_law_metas(network_formulation)
                @test IOM.has_container_key(
                    container, POM.NetworkFlowConstraint, PSY.Line, meta,
                )
                @test !isempty(
                    IOM.get_constraint(
                        container, POM.NetworkFlowConstraint, PSY.Line, meta,
                    ),
                )
            end
        end
    end
end

@testset "NFANetworkModel + StaticBranchBounds has no Ohm's law" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(NFANetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    @test !IOM.has_container_key(container, POM.NetworkFlowConstraint, PSY.Line)
end

@testset "StaticBranchBounds creates its network model's flow variables" begin
    function _line_variable_keys(network_formulation, optimizer)
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        template = get_thermal_dispatch_template_network(NetworkModel(network_formulation))
        set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
        model = DecisionModel(template, sys; optimizer = optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        return keys(IOM.get_variables(IOM.get_optimization_container(model)))
    end

    directional_ac = [
        FlowActivePowerFromToVariable,
        FlowActivePowerToFromVariable,
        FlowReactivePowerFromToVariable,
        FlowReactivePowerToFromVariable,
    ]
    for network_formulation in (ACRNetworkModel, LPACCNetworkModel)
        @testset "$network_formulation" begin
            var_keys = _line_variable_keys(network_formulation, ipopt_optimizer)
            for variable_type in directional_ac
                @test IOM.VariableKey(variable_type, PSY.Line) in var_keys
            end
        end
    end

    @testset "DCPLLNetworkModel" begin
        var_keys = _line_variable_keys(DCPLLNetworkModel, ipopt_optimizer)
        @test IOM.VariableKey(FlowActivePowerFromToVariable, PSY.Line) in var_keys
        @test IOM.VariableKey(FlowActivePowerToFromVariable, PSY.Line) in var_keys
        # DCPLL rates the directional pair; a scalar FlowActivePowerVariable is never created.
        @test !(IOM.VariableKey(FlowActivePowerVariable, PSY.Line) in var_keys)
    end

    @testset "NFANetworkModel" begin
        var_keys = _line_variable_keys(NFANetworkModel, HiGHS_optimizer)
        @test IOM.VariableKey(FlowActivePowerVariable, PSY.Line) in var_keys
    end
end

@testset "DCPLLNetworkModel + StaticBranchBounds enforces the rating as hard flow bounds" begin
    # Without slacks, DCPLLNetworkModel's FlowRateConstraint builder is a no-op (see
    # add_constraints! for FlowRateConstraint under NetworkModel{DCPLLNetworkModel}), so
    # _set_dcpll_flow_bounds! setting the JuMP variable bounds is the only rating
    # enforcement on this path.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPLLNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_lower_bound(pft[name, t])
            @test JuMP.has_upper_bound(pft[name, t])
            @test JuMP.lower_bound(pft[name, t]) == -rate
            @test JuMP.upper_bound(pft[name, t]) == rate
            @test JuMP.has_lower_bound(ptf[name, t])
            @test JuMP.has_upper_bound(ptf[name, t])
            @test JuMP.lower_bound(ptf[name, t]) == -rate
            @test JuMP.upper_bound(ptf[name, t]) == rate
        end
    end
end

@testset "NFANetworkModel + StaticBranchBounds rejects use_slacks" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, NFANetworkModel, sys)
    device_model = DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true)
    @test_throws ArgumentError mock_construct_device!(model, device_model)
end

@testset "NFANetworkModel + StaticBranchBounds + use_slacks fails template validation" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(NFANetworkModel))
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test_throws IS.ConflictingInputsError POM.validate_template(model)
end

@testset "use_slacks on a no-machinery formulation fails template validation" begin
    # slack_spec defaults to NoBranchSlacks, so every pair whose constructors build no
    # slack containers now rejects the request instead of silently ignoring it.
    # StaticBranchUnbounded builds nothing at all.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    for network_formulation in (DCPNetworkModel, ACPNetworkModel)
        template =
            get_thermal_dispatch_template_network(NetworkModel(network_formulation))
        set_device_model!(
            template,
            DeviceModel(PSY.Line, StaticBranchUnbounded; use_slacks = true),
        )
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test_throws IS.ConflictingInputsError POM.validate_template(model)
    end
end

@testset "CopperPlateNetworkModel accepts use_slacks as inert with a validation warning" begin
    # The aggregated networks build no branch containers at all, so the request cannot be
    # honored but erroring would break template reuse; validation warns and the build
    # proceeds as the usual no-op.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template =
        get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranch; use_slacks = true))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test_logs (:warn, r"use_slacks = true on branch model .* has no effect") match_mode =
        :any POM.validate_template(
        model,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "ACP/ACR/LPACC/IVR + StaticBranchBounds with use_slacks wires the flow-definition slacks" begin
    # On the AC networks NetworkFlowConstraint is the Ohm's-law equality `flow == physics`.
    # With slacks it becomes `flow == physics + s⁺ − s⁻`, and each of the four directional rows
    # (p_ft, p_tf, q_ft, q_tf) carries its OWN slack pair so the anti-symmetric p_ft/p_tf rows
    # do not self-cancel. Each pair appears in EXACTLY its own row (coefficient −1 on s⁺, +1 on
    # s⁻) and with coefficient 0 in the other three — the cross-row zero asserts are the
    # regression guard against a shared self-cancelling pair. The variable box bounds stay hard
    # (the relaxation is on the equality, not the bound), and the apparent-power
    # FlowRateConstraint stays exact.
    for network_formulation in
        (ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel)
        @testset "$network_formulation" begin
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            template =
                get_thermal_dispatch_template_network(NetworkModel(network_formulation))
            set_device_model!(
                template,
                DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
            )
            model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
            @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)
            pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
            ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
            qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
            qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.Line)
            # One slack pair and one Ohm's-law row per direction; the pair's own row is where
            # its coefficient is ±1, every other row 0.
            metas = ("p_ft", "p_tf", "q_ft", "q_tf")
            slack_up = Dict(
                m => IOM.get_variable(
                    container,
                    FlowActivePowerSlackUpperBound,
                    PSY.Line,
                    m,
                )
                for m in metas
            )
            slack_lo = Dict(
                m => IOM.get_variable(
                    container,
                    FlowActivePowerSlackLowerBound,
                    PSY.Line,
                    m,
                )
                for m in metas
            )
            cons = Dict(
                m => IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line, m)
                for m in metas
            )
            con_rate_ft =
                IOM.get_constraint(container, FlowRateConstraintFromTo, PSY.Line)
            con_rate_tf =
                IOM.get_constraint(container, FlowRateConstraintToFrom, PSY.Line)
            objective = JuMP.objective_function(IOM.get_jump_model(container))
            time_steps = IOM.get_time_steps(container)
            for line in PSY.get_components(PSY.Line, sys)
                name = PSY.get_name(line)
                rate = PSY.get_rating(line, PSY.SU)
                for t in time_steps
                    # Directional flow variables keep hard ±rating box bounds.
                    for var in (pft, ptf, qft, qtf)
                        @test JuMP.has_upper_bound(var[name, t])
                        @test JuMP.has_lower_bound(var[name, t])
                        @test JuMP.upper_bound(var[name, t]) == rate
                        @test JuMP.lower_bound(var[name, t]) == -rate
                    end

                    # `flow == physics + s⁺ − s⁻` ⇒ residual coefficient −1 on s⁺, +1 on s⁻,
                    # but ONLY in the pair's own directional row; the other three rows carry 0.
                    for own in metas
                        for row in metas
                            up_coef =
                                slack_residual_coefficient(
                                    cons[row][name, t],
                                    slack_up[own][name, t],
                                )
                            lo_coef =
                                slack_residual_coefficient(
                                    cons[row][name, t],
                                    slack_lo[own][name, t],
                                )
                            if row == own
                                @test up_coef == -1.0
                                @test lo_coef == 1.0
                            else
                                @test up_coef == 0.0
                                @test lo_coef == 0.0
                            end
                        end
                    end

                    # The exact apparent-power limit carries none of the slacks.
                    for con in (con_rate_ft, con_rate_tf)
                        for m in metas
                            @test slack_residual_coefficient(
                                con[name, t],
                                slack_up[m][name, t],
                            ) ==
                                  0.0
                            @test slack_residual_coefficient(
                                con[name, t],
                                slack_lo[m][name, t],
                            ) ==
                                  0.0
                        end
                    end

                    # All eight slack columns are priced.
                    for m in metas
                        @test JuMP.coefficient(objective, slack_up[m][name, t]) ==
                              POM.CONSTRAINT_VIOLATION_SLACK_COST
                        @test JuMP.coefficient(objective, slack_lo[m][name, t]) ==
                              POM.CONSTRAINT_VIOLATION_SLACK_COST
                    end
                end
            end
        end
    end
end

@testset "DCPLLNetworkModel + StaticBranchBounds with use_slacks builds and solves" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPLLNetworkModel))
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    @test !isempty(IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line))
    @test !isempty(IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line))
end

@testset "DCPNetworkModel + StaticBranchBounds with use_slacks slacks the Ohm's-law equality" begin
    # SBB rates the flow with hard variable bounds (±rating) and relaxes via the
    # flow-definition equality, NOT rate-inequality rows: the decision flow stays within
    # rating while the physical angle-implied flow may deviate by the signed slack. So the
    # NetworkFlowConstraint equality `p == -b*(θ_f - θ_t - shift) + slack_ub - slack_lb`
    # carries the slacks (coefficients -1 / +1 after normalization), there are no
    # FlowRateConstraint rows, and both slacks are priced.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    slack_ub = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line)
    slack_lb = IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line)
    ohm = IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line)
    objective = JuMP.objective_function(IOM.get_jump_model(container))
    time_steps = IOM.get_time_steps(container)
    @test !has_container_key(container, FlowRateConstraint, PSY.Line)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == rate
            @test JuMP.lower_bound(flow[name, t]) == -rate
            @test JuMP.normalized_coefficient(ohm[name, t], slack_ub[name, t]) == -1.0
            @test JuMP.normalized_coefficient(ohm[name, t], slack_lb[name, t]) == 1.0
            @test JuMP.coefficient(objective, slack_ub[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
            @test JuMP.coefficient(objective, slack_lb[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
        end
    end
end

@testset "PTDFNetworkModel/AreaPTDFNetworkModel + StaticBranchBounds with use_slacks wires the flow-definition slacks" begin
    # On PTDF-family networks NetworkFlowConstraint is not a rating constraint but the
    # flow-definition equality `PTDFBranchFlow - flow == slack_ub - slack_lb` (rhs 0.0
    # without slacks). The slack pair relaxes that equality, not the physical bound:
    # FlowActivePowerVariable still carries its hard ±rating bound from
    # `branch_rate_bounds!` regardless of use_slacks.
    sys_ptdf = PSB.build_system(PSITestSystems, "c_sys5")
    sys_area_ptdf = PSB.build_system(PSB.PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(sys_area_ptdf, Hour(24), Hour(1))
    build_cases = (
        (network_model = PTDFNetworkModel, sys = sys_ptdf),
        (network_model = AreaPTDFNetworkModel, sys = sys_area_ptdf),
    )
    for case in build_cases
        @testset "$(case.network_model)" begin
            sys = case.sys
            template =
                get_thermal_dispatch_template_network(NetworkModel(case.network_model))
            set_device_model!(
                template,
                DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
            )
            model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
            @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)
            flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
            slack_ub =
                IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line)
            slack_lb =
                IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line)
            net_flow_con =
                IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line)
            objective = JuMP.objective_function(IOM.get_jump_model(container))
            time_steps = IOM.get_time_steps(container)
            for line in PSY.get_components(PSY.Line, sys)
                name = PSY.get_name(line)
                rate = PSY.get_rating(line, PSY.SU)
                for t in time_steps
                    @test JuMP.has_upper_bound(flow[name, t])
                    @test JuMP.has_lower_bound(flow[name, t])
                    @test JuMP.upper_bound(flow[name, t]) == rate
                    @test JuMP.lower_bound(flow[name, t]) == -rate
                    @test JuMP.normalized_coefficient(
                        net_flow_con[name, t],
                        flow[name, t],
                    ) == -1.0
                    @test JuMP.normalized_coefficient(
                        net_flow_con[name, t],
                        slack_ub[name, t],
                    ) == -1.0
                    @test JuMP.normalized_coefficient(
                        net_flow_con[name, t],
                        slack_lb[name, t],
                    ) == 1.0
                    @test JuMP.coefficient(objective, slack_ub[name, t]) ==
                          POM.CONSTRAINT_VIOLATION_SLACK_COST
                    @test JuMP.coefficient(objective, slack_lb[name, t]) ==
                          POM.CONSTRAINT_VIOLATION_SLACK_COST
                end
            end
        end
    end
end

@testset "DCPLLNetworkModel + StaticBranchBounds with use_slacks wires the rating slacks" begin
    # With slacks the directional bounds (`_set_dcpll_flow_bounds!`) are skipped, so the
    # slacked FlowRateConstraint is the only rating enforcement and can actually relax:
    # `p - slack_ub <= rating`, `p + slack_lb >= -rating` for both directions, which share
    # the branch's single slack pair. Both slacks are priced in the objective.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPLLNetworkModel))
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
    slack_ub = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line)
    slack_lb = IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line)
    con_ft_ub = IOM.get_constraint(container, FlowRateConstraint, PSY.Line, "ft_ub")
    con_ft_lb = IOM.get_constraint(container, FlowRateConstraint, PSY.Line, "ft_lb")
    con_tf_ub = IOM.get_constraint(container, FlowRateConstraint, PSY.Line, "tf_ub")
    con_tf_lb = IOM.get_constraint(container, FlowRateConstraint, PSY.Line, "tf_lb")
    objective = JuMP.objective_function(IOM.get_jump_model(container))
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            # The slack path must leave the directional flows unbounded so the slack can relax.
            @test !JuMP.has_upper_bound(pft[name, t])
            @test !JuMP.has_lower_bound(pft[name, t])
            @test !JuMP.has_upper_bound(ptf[name, t])
            @test !JuMP.has_lower_bound(ptf[name, t])
            @test JuMP.normalized_coefficient(con_ft_ub[name, t], pft[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_ft_ub[name, t], slack_ub[name, t]) == -1.0
            @test JuMP.normalized_rhs(con_ft_ub[name, t]) == rate
            @test JuMP.normalized_coefficient(con_ft_lb[name, t], pft[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_ft_lb[name, t], slack_lb[name, t]) == 1.0
            @test JuMP.normalized_rhs(con_ft_lb[name, t]) == -rate
            @test JuMP.normalized_coefficient(con_tf_ub[name, t], ptf[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_tf_ub[name, t], slack_ub[name, t]) == -1.0
            @test JuMP.normalized_rhs(con_tf_ub[name, t]) == rate
            @test JuMP.normalized_coefficient(con_tf_lb[name, t], ptf[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_tf_lb[name, t], slack_lb[name, t]) == 1.0
            @test JuMP.normalized_rhs(con_tf_lb[name, t]) == -rate
            @test JuMP.coefficient(objective, slack_ub[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
            @test JuMP.coefficient(objective, slack_lb[name, t]) ==
                  POM.CONSTRAINT_VIOLATION_SLACK_COST
        end
    end
end

@testset "DCPNetworkModel + StaticBranchBounds without slacks bounds the flow variable" begin
    # StaticBranchBounds rates the flow purely with variable bounds at ±rating
    # (branch_rate_bounds!); it adds NO FlowRateConstraint inequality rows (those are only
    # for a time-varying DLR rating that a static bound cannot express).
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    time_steps = IOM.get_time_steps(container)
    @test !has_container_key(container, FlowRateConstraint, PSY.Line)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == rate
            @test JuMP.lower_bound(flow[name, t]) == -rate
        end
    end
end

@testset "NFANetworkModel + StaticBranchBounds enforces the rating as hard flow bounds" begin
    # NFA has no ModelConstructStage override for StaticBranchBounds, so it falls to the
    # generic `NetworkModel{<:AbstractActivePowerModel}` fallback, which calls
    # `branch_rate_bounds!` and sets ±rate directly on FlowActivePowerVariable.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(NFANetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == rate
            @test JuMP.lower_bound(flow[name, t]) == -rate
        end
    end
end

@testset "PTDFNetworkModel + StaticBranchBounds enforces the rating as hard flow bounds and ties flow to PTDFBranchFlow" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    net_flow_con = IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line)
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == rate
            @test JuMP.lower_bound(flow[name, t]) == -rate
            # The branch's own flow variable enters its NetworkFlowConstraint row with
            # coefficient -1.0 (flow == PTDFBranchFlow expression, moved to one side).
            @test JuMP.normalized_coefficient(net_flow_con[name, t], flow[name, t]) == -1.0
        end
    end
end

@testset "AreaPTDFNetworkModel + StaticBranchBounds enforces the rating as hard flow bounds (two_area_pjm_DA)" begin
    sys = PSB.build_system(PSB.PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(sys, Hour(24), Hour(1))
    template = get_thermal_dispatch_template_network(NetworkModel(AreaPTDFNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    net_flow_con = IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line)
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        rate = PSY.get_rating(line, PSY.SU)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == rate
            @test JuMP.lower_bound(flow[name, t]) == -rate
            @test JuMP.normalized_coefficient(net_flow_con[name, t], flow[name, t]) == -1.0
        end
    end
end

@testset "ACPNetworkModel/ACRNetworkModel/LPACCNetworkModel/IVRNetworkModel + StaticBranchBounds set hard rating bounds on the flow variables AND keep the quadratic FlowRateConstraint" begin
    # StaticBranchBounds adds explicit ±rating box bounds on all four directional flow
    # variables (PM parity: q shares p's ±rating), a solver-facing implementation
    # difference from StaticBranch. The quadratic apparent-power FlowRateConstraintFromTo/
    # ToFrom (p^2 + q^2 <= rate^2) is mathematically equivalent and is still built — both
    # mechanisms are present.
    for network_formulation in
        (ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel)
        @testset "$network_formulation" begin
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            template =
                get_thermal_dispatch_template_network(NetworkModel(network_formulation))
            set_device_model!(template, DeviceModel(PSY.Line, StaticBranchBounds))
            model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
            @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)
            pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
            qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
            ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
            qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.Line)
            con_ft = IOM.get_constraint(container, FlowRateConstraintFromTo, PSY.Line)
            con_tf = IOM.get_constraint(container, FlowRateConstraintToFrom, PSY.Line)
            time_steps = IOM.get_time_steps(container)
            for line in PSY.get_components(PSY.Line, sys)
                name = PSY.get_name(line)
                rate = PSY.get_rating(line, PSY.SU)
                for t in time_steps
                    @test JuMP.upper_bound(pft[name, t]) == rate
                    @test JuMP.lower_bound(pft[name, t]) == -rate
                    @test JuMP.upper_bound(qft[name, t]) == rate
                    @test JuMP.lower_bound(qft[name, t]) == -rate
                    @test JuMP.upper_bound(ptf[name, t]) == rate
                    @test JuMP.lower_bound(ptf[name, t]) == -rate
                    @test JuMP.upper_bound(qtf[name, t]) == rate
                    @test JuMP.lower_bound(qtf[name, t]) == -rate

                    co_ft = JuMP.constraint_object(con_ft[name, t])
                    co_tf = JuMP.constraint_object(con_tf[name, t])
                    @test co_ft.set == MOI.LessThan(rate^2)
                    @test JuMP.coefficient(co_ft.func, pft[name, t], pft[name, t]) == 1.0
                    @test JuMP.coefficient(co_ft.func, qft[name, t], qft[name, t]) == 1.0
                    @test co_tf.set == MOI.LessThan(rate^2)
                    @test JuMP.coefficient(co_tf.func, ptf[name, t], ptf[name, t]) == 1.0
                    @test JuMP.coefficient(co_tf.func, qtf[name, t], qtf[name, t]) == 1.0
                end
            end
        end
    end
end

@testset "StaticBranchBounds on a MonitoredLine bounds active by monitoring limits, reactive by rating" begin
    # `min_max_flow_limits(::PSY.MonitoredLine, ...)` (AC_branches.jl) collapses the (possibly
    # asymmetric) `PSY.get_flow_limits` into an ACTIVE-flow monitoring limit. That limit bounds
    # only the active directional variables; the reactive variables are bounded by the
    # symmetric thermal `branch_rating` (PM parity — q is bounded by the rating, not by an
    # active monitoring limit — and it keeps StaticBranchBounds ≡ StaticBranch, whose quadratic
    # apparent-power limit bounds |q| by the rating alone). Force asymmetric limits below the
    # rating so the test cannot pass by accident on a symmetric fixture.
    sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
    ml = first(PSY.get_components(PSY.MonitoredLine, sys))
    PSY.set_flow_limits!(ml, (from_to = 2.0 * PSY.MW, to_from = 4.0 * PSY.MW))
    limits = PSY.get_flow_limits(ml, PSY.SU)
    rate = PSY.get_rating(ml, PSY.SU)
    @test limits.from_to != limits.to_from
    @test limits.from_to != rate
    @test limits.to_from != rate
    # Guard: the reactive bound (rating) must be strictly wider than the collapsed active
    # monitoring limit, otherwise the reactive assertions would pass vacuously.
    @test rate > min(rate, limits.from_to, limits.to_from)

    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(template, DeviceModel(PSY.MonitoredLine, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.MonitoredLine)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.MonitoredLine)
    qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.MonitoredLine)
    qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.MonitoredLine)
    name = PSY.get_name(ml)
    time_steps = IOM.get_time_steps(container)
    for t in time_steps
        # Active variables keep the (asymmetric) monitoring limits.
        @test JuMP.upper_bound(pft[name, t]) == limits.from_to
        @test JuMP.lower_bound(pft[name, t]) == -limits.from_to
        @test JuMP.upper_bound(ptf[name, t]) == limits.to_from
        @test JuMP.lower_bound(ptf[name, t]) == -limits.to_from
        # Reactive variables widen to the symmetric thermal rating.
        @test JuMP.upper_bound(qft[name, t]) == rate
        @test JuMP.lower_bound(qft[name, t]) == -rate
        @test JuMP.upper_bound(qtf[name, t]) == rate
        @test JuMP.lower_bound(qtf[name, t]) == -rate
    end
end

@testset "PTDFNetworkModel + StaticBranchBounds pins MonitoredLine flow bounds via min_max_flow_limits, not the symmetric rating" begin
    # `min_max_flow_limits(::PSY.MonitoredLine, ::DeviceModel)` (AC_branches.jl:445-447)
    # defers to `get_min_max_limits(device, FlowRateConstraint, AbstractBranchFormulation)`,
    # which collapses the (possibly asymmetric) `flow_limits` and the rating into a single
    # symmetric `min(rating, to_from, from_to)` bound on the PTDF network's scalar
    # `FlowActivePowerVariable` (`branch_rate_bounds!`, AC_branches.jl:366-389). This is a
    # different code path from the directional ACP bounds exercised above.
    sys = PSB.build_system(PSITestSystems, "c_sys5_ml")
    ml = first(PSY.get_components(PSY.MonitoredLine, sys))
    PSY.set_flow_limits!(ml, (from_to = 2.0 * PSY.MW, to_from = 4.0 * PSY.MW))
    limits = PSY.get_flow_limits(ml, PSY.SU)
    rate = PSY.get_rating(ml, PSY.SU)
    @test limits.from_to != limits.to_from
    @test limits.from_to != rate
    @test limits.to_from != rate
    # Guard: the collapsed PTDF bound must actually be tighter than the symmetric rating,
    # otherwise this testset would pass vacuously even if flow_limits were ignored entirely.
    @test min(rate, limits.from_to, limits.to_from) != rate

    template = get_thermal_dispatch_template_network(
        NetworkModel(PTDFNetworkModel; network_matrix = PTDF(sys)),
    )
    set_device_model!(template, DeviceModel(PSY.MonitoredLine, StaticBranchBounds))
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    flow = IOM.get_variable(container, FlowActivePowerVariable, PSY.MonitoredLine)
    time_steps = IOM.get_time_steps(container)
    for line in PSY.get_components(PSY.MonitoredLine, sys)
        name = PSY.get_name(line)
        dev_limits = PSY.get_flow_limits(line, PSY.SU)
        dev_rate = PSY.get_rating(line, PSY.SU)
        expected_limit = min(dev_rate, dev_limits.from_to, dev_limits.to_from)
        for t in time_steps
            @test JuMP.has_upper_bound(flow[name, t])
            @test JuMP.has_lower_bound(flow[name, t])
            @test JuMP.upper_bound(flow[name, t]) == expected_limit
            @test JuMP.lower_bound(flow[name, t]) == -expected_limit
        end
    end
end

@testset "ACP + StaticBranchBounds use_slacks relaxes an otherwise-infeasible over-tight rating" begin
    # Line "1" (nodeA-nodeB) carries ~3.26 pu in an unconstrained ACP solve; cutting its
    # rating to 0.5 pu makes the directional ±rating box bounds too tight for any voltage
    # profile to satisfy Ohm's law at the peak-load hours, so the no-slack problem is
    # infeasible. The flow-definition slacks relax the Ohm's-law equalities: the flow the
    # voltages imply may exceed the box the variable is pinned to, changing the feasible set.
    cut = 0.5
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    line = PSY.get_component(PSY.Line, sys, "1")
    PSY.set_rating!(line, cut * PSY.SU)

    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    slack_objective = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model))

    container = IOM.get_optimization_container(model)
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
    qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
    qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.Line)
    p_ft_up = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "p_ft")
    p_ft_lo = IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line, "p_ft")
    p_tf_up = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, "p_tf")
    p_tf_lo = IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line, "p_tf")
    time_steps = IOM.get_time_steps(container)

    # Every directional flow variable respects its hard ±rating box bound: the relaxation is
    # on the Ohm's-law equality, never on the box.
    for component in PSY.get_components(PSY.Line, sys)
        component_name = PSY.get_name(component)
        rate = PSY.get_rating(component, PSY.SU)
        for t in time_steps
            for variable in (pft, ptf, qft, qtf)
                @test abs(JuMP.value(variable[component_name, t])) <= rate + 1e-6
            end
        end
    end

    # The relaxation is genuinely exercised: some flow-definition slack is active.
    total_slack = 0.0
    for meta in ("p_ft", "p_tf", "q_ft", "q_tf")
        for V in (FlowActivePowerSlackUpperBound, FlowActivePowerSlackLowerBound)
            total_slack +=
                sum(
                    max(JuMP.value(s), 0.0) for
                    s in IOM.get_variable(container, V, PSY.Line, meta)
                )
        end
    end
    @test total_slack > 1e-4

    # On the cut line itself, at the peak hours its own p_ft slack is active, so the
    # voltage-implied physical flow `pft - s⁺ + s⁻` exceeds the tightened rating even though
    # the flow variable is pinned inside it.
    line_name = PSY.get_name(line)
    peak = time_steps[argmax([
        JuMP.value(p_ft_up[line_name, t]) + JuMP.value(p_ft_lo[line_name, t]) for
        t in time_steps
    ])]
    line_slack = JuMP.value(p_ft_up[line_name, peak]) + JuMP.value(p_ft_lo[line_name, peak])
    @test line_slack > 1e-6
    # Reconstruct both directional physical (voltage-implied) active flows from `flow == physics
    # + s⁺ − s⁻`. Their sum is the line's active loss L ≥ 0.
    physics_ft =
        JuMP.value(pft[line_name, peak]) - JuMP.value(p_ft_up[line_name, peak]) +
        JuMP.value(p_ft_lo[line_name, peak])
    physics_tf =
        JuMP.value(ptf[line_name, peak]) - JuMP.value(p_tf_up[line_name, peak]) +
        JuMP.value(p_tf_lo[line_name, peak])
    line_loss = physics_ft + physics_tf
    @test abs(JuMP.value(pft[line_name, peak])) <= cut + 1e-6
    @test abs(physics_ft) > cut
    # Regression guard for the self-cancelling shared-pair bug: with one pair shared between
    # p_ft and p_tf the anti-symmetric rows cap the physical escape at L/2 (exactly zero on a
    # lossless line). Per-direction pairs let the physical flow exceed the rating by far more.
    @test abs(physics_ft) - cut > line_loss / 2 + 1e-6

    # The slack changed the feasible set: the same over-tight rating without slacks is
    # infeasible (Ipopt returns a locally-infeasible status). If a future Ipopt instead
    # converges, the no-slack objective must be strictly higher than the slacked one.
    sys_no_slack = PSB.build_system(PSITestSystems, "c_sys5")
    PSY.set_rating!(PSY.get_component(PSY.Line, sys_no_slack, "1"), cut * PSY.SU)
    template_no_slack = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(template_no_slack, DeviceModel(PSY.Line, StaticBranchBounds))
    model_no_slack =
        DecisionModel(template_no_slack, sys_no_slack; optimizer = ipopt_optimizer)
    @test build!(model_no_slack; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    status_no_slack = solve!(model_no_slack)
    if status_no_slack == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        @test IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_no_slack)) >
              slack_objective + 1e-3
    else
        @test status_no_slack != IOM.RunStatus.SUCCESSFULLY_FINALIZED
    end
end

@testset "StaticBranch and StaticBranchBounds reach the same ACP optimum at a binding rating (c_sys5)" begin
    # The mathematical-equivalence contract: box bounds plus the quadratic apparent-power
    # limit describe the same feasible set as the quadratic limit alone. Proving it on an
    # interior optimum says nothing about the rating machinery, so line "1" (which carries
    # ~3.29 pu apparent power otherwise) gets its rating cut to 2.0 pu — feasible without
    # slacks (0.5 pu is not, see the over-tight-rating testset) but BINDING at the optimum
    # in both formulations.
    cut = 2.0
    function _acp_binding_solve(formulation)
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        PSY.set_rating!(PSY.get_component(PSY.Line, sys, "1"), cut * PSY.SU)
        template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
        set_device_model!(template, DeviceModel(PSY.Line, formulation))
        model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        container = IOM.get_optimization_container(model)
        pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
        qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
        smax_ft = maximum(
            sqrt(JuMP.value(pft["1", t])^2 + JuMP.value(qft["1", t])^2) for
            t in IOM.get_time_steps(container)
        )
        objective = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model))
        return objective, smax_ft
    end
    objective_sb, smax_sb = _acp_binding_solve(StaticBranch)
    objective_sbb, smax_sbb = _acp_binding_solve(StaticBranchBounds)
    # The from-to apparent power sits ON the tightened rating at the peak hour: the
    # quadratic limit (StaticBranch) / box-plus-quadratic (StaticBranchBounds) is active,
    # not slack — a solution strictly inside the limit would fail these.
    @test isapprox(smax_sb, cut; atol = 1e-4)
    @test isapprox(smax_sbb, cut; atol = 1e-4)
    @test isapprox(objective_sb, objective_sbb; rtol = 1e-4)
end

@testset "StaticBranch and StaticBranchBounds reach the same DCP optimum at a binding rating (c_sys5)" begin
    # DCP enforces the rating as FlowRateConstraint lb/ub rows for both formulations; the
    # equivalence must hold with the ub row active. StaticBranch carries the flow as the
    # BThetaBranchFlow expression (angles are the only decision variables); StaticBranchBounds
    # keeps the FlowActivePowerVariable + defining equality. This is the correctness gate for
    # the expression-based refactor: both must reach the SAME physics/objective.
    # 2.0 pu on line "1" is feasible (1.0 pu is infeasible on this system) and binds at the
    # peak hours. HiGHS is deterministic, so the objectives must agree tightly.
    cut = 2.0
    _dcp_binding_flow(container, ::Type{StaticBranch}) =
        IOM.get_expression(container, BThetaBranchFlow, PSY.Line)
    _dcp_binding_flow(container, ::Type{StaticBranchBounds}) =
        IOM.get_variable(container, FlowActivePowerVariable, PSY.Line)
    function _dcp_binding_solve(formulation)
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        PSY.set_rating!(PSY.get_component(PSY.Line, sys, "1"), cut * PSY.SU)
        template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
        set_device_model!(template, DeviceModel(PSY.Line, formulation))
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        container = IOM.get_optimization_container(model)
        flow = _dcp_binding_flow(container, formulation)
        fmax = maximum(
            abs(JuMP.value(flow["1", t])) for t in IOM.get_time_steps(container)
        )
        objective = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model))
        return objective, fmax
    end
    objective_sb, fmax_sb = _dcp_binding_solve(StaticBranch)
    objective_sbb, fmax_sbb = _dcp_binding_solve(StaticBranchBounds)
    @test isapprox(fmax_sb, cut; atol = 1e-4)
    @test isapprox(fmax_sbb, cut; atol = 1e-4)
    @test isapprox(objective_sb, objective_sbb; rtol = 1e-4)
end

@testset "ACP StaticBranch + use_slacks wires the squared-domain slack into the apparent-power limit" begin
    # StaticBranch relaxes the quadratic rows: `p² + q² - slack_ub <= rate²`, so the
    # meta-less squared-domain slack enters both FlowRateConstraintFromTo and
    # FlowRateConstraintToFrom with an affine coefficient of -1.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(template, DeviceModel(PSY.Line, StaticBranch; use_slacks = true))
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    slack_ub = IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line)
    con_ft = IOM.get_constraint(container, FlowRateConstraintFromTo, PSY.Line)
    con_tf = IOM.get_constraint(container, FlowRateConstraintToFrom, PSY.Line)
    for line in PSY.get_components(PSY.Line, sys)
        name = PSY.get_name(line)
        for t in IOM.get_time_steps(container)
            @test JuMP.normalized_coefficient(con_ft[name, t], slack_ub[name, t]) == -1.0
            @test JuMP.normalized_coefficient(con_tf[name, t], slack_ub[name, t]) == -1.0
        end
    end
end

# The constraint container each per-network StaticBranchBounds wiring testset above names,
# plus the metas of the slack that relaxes it. Mirrors `_ohms_law_metas`: one method per
# network, no `Union` alias driving dispatch beyond the ACP/ACR/LPACC trio that already
# shares an Ohm's-law shape.
_sbb_slack_probe(::Type{DCPNetworkModel}) =
    (POM.NetworkFlowConstraint, IOM.CONTAINER_KEY_EMPTY_META, IOM.CONTAINER_KEY_EMPTY_META)
_sbb_slack_probe(::Type{PTDFNetworkModel}) =
    (POM.NetworkFlowConstraint, IOM.CONTAINER_KEY_EMPTY_META, IOM.CONTAINER_KEY_EMPTY_META)
_sbb_slack_probe(::Type{AreaPTDFNetworkModel}) =
    (POM.NetworkFlowConstraint, IOM.CONTAINER_KEY_EMPTY_META, IOM.CONTAINER_KEY_EMPTY_META)
_sbb_slack_probe(::Type{DCPLLNetworkModel}) =
    (FlowRateConstraint, "ft_ub", IOM.CONTAINER_KEY_EMPTY_META)
_sbb_slack_probe(::Type{<:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel}}) =
    (POM.NetworkFlowConstraint, "p_ft", "p_ft")
_sbb_slack_probe(::Type{IVRNetworkModel}) = (POM.NetworkFlowConstraint, "cr_fr", "cr_fr")

# Constraint-row wiring probe per formulation: StaticBranchBounds asserts its slack enters
# the row `_sbb_slack_probe` promises; StaticBranch's row wiring is pinned by the dedicated
# per-network wiring testsets above, so only the container/pricing contract is checked.
function _assert_slack_row_wiring(
    container,
    ::Type{StaticBranch},
    ::Type{<:AbstractNetworkModel},
)
    return
end

function _assert_slack_row_wiring(
    container,
    ::Type{StaticBranchBounds},
    ::Type{N},
) where {N <: AbstractNetworkModel}
    (constraint_type, constraint_meta, slack_meta) = _sbb_slack_probe(N)
    con = IOM.get_constraint(container, constraint_type, PSY.Line, constraint_meta)
    slack =
        IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, slack_meta)
    name = first(axes(con, 1))
    t = first(axes(con, 2))
    @test !iszero(slack_residual_coefficient(con[name, t], slack[name, t]))
    return
end

@testset "slack_spec names exactly the slack containers a slacked build creates and prices" begin
    # Trait-vs-reality guard: for every (formulation, network) pair whose slack_spec
    # declares machinery, a slacked build must create every (variable type, meta) container
    # the spec names and price each one at the violation cost; StaticBranchBounds must
    # additionally wire its slack into the constraint row the design promises.
    sys_default = PSB.build_system(PSITestSystems, "c_sys5")
    sys_area = PSB.build_system(PSB.PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(sys_area, Hour(24), Hour(1))
    all_formulations = (StaticBranch, StaticBranchBounds)
    for (network_formulation, optimizer, sys, formulations) in (
        (DCPNetworkModel, HiGHS_optimizer, sys_default, all_formulations),
        (PTDFNetworkModel, HiGHS_optimizer, sys_default, all_formulations),
        (AreaPTDFNetworkModel, HiGHS_optimizer, sys_area, all_formulations),
        (DCPLLNetworkModel, ipopt_optimizer, sys_default, all_formulations),
        # NFA has no rating/equality row for StaticBranchBounds to relax (see
        # branch_slack_specs.jl), so that pair is the rejected combo and stays excluded.
        (NFANetworkModel, HiGHS_optimizer, sys_default, (StaticBranch,)),
        (ACPNetworkModel, ipopt_optimizer, sys_default, all_formulations),
        (ACRNetworkModel, ipopt_optimizer, sys_default, all_formulations),
        (LPACCNetworkModel, ipopt_optimizer, sys_default, all_formulations),
        (IVRNetworkModel, ipopt_optimizer, sys_default, all_formulations),
    )
        for formulation in formulations
            @testset "$network_formulation $formulation" begin
                spec = POM.slack_spec(formulation, network_formulation)
                entries = POM.slack_variable_entries(spec)
                @test POM.supports_flow_slacks(formulation, network_formulation)
                @test !isempty(entries)
                template =
                    get_thermal_dispatch_template_network(
                        NetworkModel(network_formulation),
                    )
                set_device_model!(
                    template,
                    DeviceModel(PSY.Line, formulation; use_slacks = true),
                )
                model = DecisionModel(template, sys; optimizer = optimizer)
                @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                      IOM.ModelBuildStatus.BUILT

                container = IOM.get_optimization_container(model)
                objective = JuMP.objective_function(IOM.get_jump_model(container))
                for (variable_type, slack_meta) in entries
                    slack =
                        IOM.get_variable(container, variable_type, PSY.Line, slack_meta)
                    @test !isempty(slack)
                    name = first(axes(slack, 1))
                    t = first(axes(slack, 2))
                    @test JuMP.coefficient(objective, slack[name, t]) ==
                          POM.CONSTRAINT_VIOLATION_SLACK_COST
                end
                _assert_slack_row_wiring(container, formulation, network_formulation)
            end
        end
    end
end
