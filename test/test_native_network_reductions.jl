import PowerNetworkMatrices as PNM

# `case11_network_reductions` under RadialReduction + DegreeTwoReduction exercises every
# reduction shape the native formulations must handle:
#   - radial:            "1-8-i_1" absorbed entirely (bus 8 -> 1), no arc entry
#   - series chain:      arc (1,2) = "1-6-i_1" + "6-7-i_1" + "7-2-i_1"
#   - cross-type chain:  arc (1,5) = Line "1-9-i_1" + TwoWindingTransformer "9-5-i_1"
#   - parallel:          arc (1,4) = "1-4-i_1" ∥ "1-4-i_2" -> entry "1-4-i_double_circuit"
#   - parallel-in-chain: arc (2,3) = "10-3-i_1" + ("2-10-i_1" ∥ "2-10-i_2")
#   - direct:            arc (4,5) = "4-5-i_1"
# Distinct reduced arcs across both branch types: (1,2), (1,4), (1,5), (2,3), (3,4), (4,5).
const CASE11_DISTINCT_REDUCED_ARCS = 6

function _case11_with_forecast()
    sys = PSB.build_system(PSITestSystems, "case11_network_reductions")
    dummy_data = Dict(
        DateTime("2020-01-01T08:00:00") => [5.0, 6, 7, 7, 7],
        DateTime("2020-01-01T08:30:00") => [9.0, 9, 9, 9, 8],
        DateTime("2020-01-01T09:00:00") => [6.0, 6, 5, 5, 4],
    )
    dummy_forecast = Deterministic("max_active_power", dummy_data, Dates.Minute(5))
    load = first(get_components(StandardLoad, sys))
    add_time_series!(sys, load, dummy_forecast)
    return sys
end

function _network_source_from_flags(radial::Bool, degree_two::Bool)
    reductions = PNM.NetworkReduction[]
    if radial
        push!(reductions, PNM.RadialReduction())
    end
    if degree_two
        push!(reductions, PNM.DegreeTwoReduction())
    end
    return NetworkReductionSpec(reductions)
end

function _solve_case11_native(
    network_formulation,
    optimizer;
    reduce::Bool = false,
    reduce_radial_branches::Bool = reduce,
    reduce_degree_two_branches::Bool = reduce,
)
    sys = _case11_with_forecast()
    net = NetworkModel(
        network_formulation;
        network_source = _network_source_from_flags(
            reduce_radial_branches,
            reduce_degree_two_branches,
        ),
    )
    template = get_thermal_dispatch_template_network(net)
    model = DecisionModel(template, sys; optimizer = optimizer)
    build_status = build!(
        model;
        output_dir = mktempdir(; cleanup = true),
        console_level = Logging.Error,
    )
    return model, build_status
end

# Branch-axis names of one POM.NetworkFlowConstraint container, asserting every entry is
# assigned (no #undef holes from skipped branches). Missing container -> empty axis
# (e.g. every arc of that type was claimed by the other branch type's constructor).
function _assigned_flow_constraint_axis(container, key)
    constraints = IOM.get_constraints(container)
    if !haskey(constraints, key)
        return String[]
    end
    cons = constraints[key]
    for idx in eachindex(cons.data)
        @test isassigned(cons.data, idx)
    end
    return collect(axes(cons)[1])
end

@testset "native DCP reduction: one corridor per reduced arc, exact parity" begin
    # StaticBranch under DCP carries its flow as the BThetaBranchFlow expression, built
    # against the same NetworkFlowConstraint-family dedup axis the (now unused, for
    # StaticBranch) variable-based Ohm's-law builder used — one representative name per
    # reduced arc, NOT every member device name (unlike the old FlowActivePowerVariable
    # container, which exposed every member name aliased to the same JuMP variable).
    model_red, status_red =
        _solve_case11_native(DCPNetworkModel, HiGHS_optimizer; reduce = true)
    @test status_red == IOM.ModelBuildStatus.BUILT
    @test solve!(model_red) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model_red)
    bfe_line = IOM.get_expression(container, BThetaBranchFlow, Line)
    bfe_xfmr = IOM.get_expression(container, BThetaBranchFlow, TwoWindingTransformer)

    # BThetaBranchFlow built exactly once per reduced arc, across both branch types.
    n_flow_expr = length(axes(bfe_line)[1]) + length(axes(bfe_xfmr)[1])
    @test n_flow_expr == CASE11_DISTINCT_REDUCED_ARCS

    # The radially-absorbed branch must not appear anywhere.
    @test !("1-8-i_1" in axes(bfe_line)[1])

    # The series chain (1,2) and the parallel group (1,4) collapse to ONE representative
    # name each — only one of the chain's three member names is a valid axis key.
    t1 = first(IOM.get_time_steps(container))
    chain_names_present =
        count(in(axes(bfe_line)[1]), ("1-6-i_1", "6-7-i_1", "7-2-i_1"))
    @test chain_names_present == 1
    @test "1-4-i_double_circuit" in axes(bfe_line)[1]
    @test !("1-4-i_1" in axes(bfe_line)[1])
    # Cross-type chain (1,5): the arc is claimed by exactly one branch type, so its name
    # appears in exactly one of the two containers, never both.
    cross_type_owners =
        count(in(axes(bfe_line)[1]), ("1-9-i_1",)) +
        count(in(axes(bfe_xfmr)[1]), ("9-5-i_1",))
    @test cross_type_owners == 1

    model_full, status_full =
        _solve_case11_native(DCPNetworkModel, HiGHS_optimizer; reduce = false)
    @test status_full == IOM.ModelBuildStatus.BUILT
    @test solve!(model_full) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # DC power flow is exactly invariant under radial + degree-two reduction: the direct
    # (un-reduced) line carries the same flow in both problems.
    res_red = IOM.OptimizationProblemOutputs(model_red)
    res_full = IOM.OptimizationProblemOutputs(model_full)
    pf_red = read_expression(
        res_red, "BThetaBranchFlow__Line"; table_format = TableFormat.WIDE,
    )
    pf_full = read_expression(
        res_full, "BThetaBranchFlow__Line"; table_format = TableFormat.WIDE,
    )
    @test isapprox(pf_red[1, "4-5-i_1"], pf_full[1, "4-5-i_1"]; atol = 1e-4)
end

@testset "native DCP reduction: radial-only and degree-two-only isolated" begin
    # Each reduction kind alone must change the branch-expression topology in its own way:
    # radial reduction absorbs the radial leaf but leaves the degree-two series chain as
    # distinct entries, and degree-two reduction does the opposite.

    # Radial-only: the radial leaf "1-8-i_1" is absorbed, but with degree-two reduction
    # OFF the (1,2) series-chain segments stay three DISTINCT entries.
    model_rad, status_rad = _solve_case11_native(
        DCPNetworkModel, HiGHS_optimizer;
        reduce_radial_branches = true, reduce_degree_two_branches = false,
    )
    @test status_rad == IOM.ModelBuildStatus.BUILT
    @test solve!(model_rad) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container_rad = IOM.get_optimization_container(model_rad)
    bfe_rad = IOM.get_expression(container_rad, BThetaBranchFlow, Line)
    @test !("1-8-i_1" in axes(bfe_rad)[1])
    @test "1-6-i_1" in axes(bfe_rad)[1]
    @test "6-7-i_1" in axes(bfe_rad)[1]
    @test "7-2-i_1" in axes(bfe_rad)[1]

    # Degree-two-only: with radial reduction OFF the radial leaf "1-8-i_1" is STILL
    # present, and the series chain IS collapsed to a single representative entry.
    model_deg, status_deg = _solve_case11_native(
        DCPNetworkModel, HiGHS_optimizer;
        reduce_radial_branches = false, reduce_degree_two_branches = true,
    )
    @test status_deg == IOM.ModelBuildStatus.BUILT
    @test solve!(model_deg) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container_deg = IOM.get_optimization_container(model_deg)
    bfe_deg = IOM.get_expression(container_deg, BThetaBranchFlow, Line)
    @test "1-8-i_1" in axes(bfe_deg)[1]
    chain_names_present_deg =
        count(in(axes(bfe_deg)[1]), ("1-6-i_1", "6-7-i_1", "7-2-i_1"))
    @test chain_names_present_deg == 1
end

@testset "native ACP reduction: one corridor per reduced arc, exact parity" begin
    model_red, status_red =
        _solve_case11_native(ACPNetworkModel, ipopt_optimizer; reduce = true)
    @test status_red == IOM.ModelBuildStatus.BUILT
    @test solve!(model_red) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model_red)

    # Four directional Ohm's-law constraints (p_ft/q_ft/p_tf/q_tf) per reduced arc,
    # each built exactly once across both branch types.
    for meta in ("p_ft", "q_ft", "p_tf", "q_tf")
        n =
            length(
                _assigned_flow_constraint_axis(
                    container, IOM.ConstraintKey(POM.NetworkFlowConstraint, Line, meta),
                ),
            ) + length(
                _assigned_flow_constraint_axis(
                    container,
                    IOM.ConstraintKey(
                        POM.NetworkFlowConstraint,
                        TwoWindingTransformer,
                        meta,
                    ),
                ),
            )
        @test n == CASE11_DISTINCT_REDUCED_ARCS
    end

    # Directional flow variables alias per reduced arc, including across types.
    t1 = first(IOM.get_time_steps(container))
    pft_line = IOM.get_variable(container, FlowActivePowerFromToVariable, Line)
    @test !("1-8-i_1" in axes(pft_line)[1])
    @test pft_line["1-6-i_1", t1] === pft_line["6-7-i_1", t1]
    @test pft_line["6-7-i_1", t1] === pft_line["7-2-i_1", t1]
    @test "1-4-i_double_circuit" in axes(pft_line)[1]
    pft_xfmr =
        IOM.get_variable(container, FlowActivePowerFromToVariable, TwoWindingTransformer)
    @test pft_line["1-9-i_1", t1] === pft_xfmr["9-5-i_1", t1]

    # The PNM series/parallel equivalents are exact two-port reductions, so the AC
    # solution (and objective) must match the unreduced problem.
    model_full, status_full =
        _solve_case11_native(ACPNetworkModel, ipopt_optimizer; reduce = false)
    @test status_full == IOM.ModelBuildStatus.BUILT
    @test solve!(model_full) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    obj_red = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_red))
    obj_full = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_full))
    @test isapprox(obj_red, obj_full; rtol = 1e-5)
end

@testset "native ACR/IVR/LPACC reduction: build, solve, ACP-oracle parity" begin
    model_acp, acp_status =
        _solve_case11_native(ACPNetworkModel, ipopt_optimizer; reduce = true)
    @test acp_status == IOM.ModelBuildStatus.BUILT
    @test solve!(model_acp) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    acp_obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_acp))

    # ACR and IVR are exact reformulations of ACP, so their reduced solves must match the
    # reduced ACP objective.
    for formulation in (ACRNetworkModel, IVRNetworkModel)
        model, status = _solve_case11_native(formulation, ipopt_optimizer; reduce = true)
        @test status == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        obj = IOM.get_objective_value(IOM.OptimizationProblemOutputs(model))
        @test isapprox(obj, acp_obj; rtol = 1e-4)
    end

    # LPACC is a linear approximation with a large gap to ACP on this system, so its
    # oracle is its own un-reduced solve. The corridor-level cosine relaxation is not
    # identical to the per-segment one, hence a small (observed ~0.6%) tolerance.
    model_lpacc_red, lpacc_red_status =
        _solve_case11_native(LPACCNetworkModel, ipopt_optimizer; reduce = true)
    @test lpacc_red_status == IOM.ModelBuildStatus.BUILT
    @test solve!(model_lpacc_red) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    model_lpacc_full, lpacc_full_status =
        _solve_case11_native(LPACCNetworkModel, ipopt_optimizer; reduce = false)
    @test lpacc_full_status == IOM.ModelBuildStatus.BUILT
    @test solve!(model_lpacc_full) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    lpacc_red_obj =
        IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_lpacc_red))
    lpacc_full_obj =
        IOM.get_objective_value(IOM.OptimizationProblemOutputs(model_lpacc_full))
    @test isapprox(lpacc_red_obj, lpacc_full_obj; rtol = 2e-2)
end

@testset "native NFA reduction: one corridor per reduced arc, build and solve" begin
    # NFA has no Ohm's law, only rating-bounded FlowActivePowerVariable and nodal
    # balance, so the flow-rate constraint (not NetworkFlowConstraint) is the corridor
    # to check: one lb/ub pair per reduced arc, shared across both branch types.
    model_red, status_red =
        _solve_case11_native(NFANetworkModel, HiGHS_optimizer; reduce = true)
    @test status_red == IOM.ModelBuildStatus.BUILT
    @test solve!(model_red) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model_red)
    n_lb =
        length(
            _assigned_flow_constraint_axis(
                container, IOM.ConstraintKey(POM.FlowRateConstraint, Line, "lb"),
            ),
        ) + length(
            _assigned_flow_constraint_axis(
                container,
                IOM.ConstraintKey(POM.FlowRateConstraint, TwoWindingTransformer, "lb"),
            ),
        )
    @test n_lb == CASE11_DISTINCT_REDUCED_ARCS

    pvar_line = IOM.get_variable(container, FlowActivePowerVariable, Line)
    @test !("1-8-i_1" in axes(pvar_line)[1])
    t1 = first(IOM.get_time_steps(container))
    @test pvar_line["1-6-i_1", t1] === pvar_line["6-7-i_1", t1]
    @test pvar_line["6-7-i_1", t1] === pvar_line["7-2-i_1", t1]
    @test "1-4-i_double_circuit" in axes(pvar_line)[1]
end

@testset "native DCPLL reduction: one corridor per reduced arc, build and solve" begin
    # DCPLL keeps DCP's Ohm's law on p_fr (NetworkFlowConstraint) plus a quadratic
    # loss-coupling constraint (NetworkLossConstraint); both must appear exactly once
    # per reduced arc.
    model_red, status_red =
        _solve_case11_native(DCPLLNetworkModel, ipopt_optimizer; reduce = true)
    @test status_red == IOM.ModelBuildStatus.BUILT
    @test solve!(model_red) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model_red)
    n_flow =
        length(
            _assigned_flow_constraint_axis(
                container, IOM.ConstraintKey(POM.NetworkFlowConstraint, Line),
            ),
        ) + length(
            _assigned_flow_constraint_axis(
                container,
                IOM.ConstraintKey(POM.NetworkFlowConstraint, TwoWindingTransformer),
            ),
        )
    @test n_flow == CASE11_DISTINCT_REDUCED_ARCS
    n_loss =
        length(
            _assigned_flow_constraint_axis(
                container, IOM.ConstraintKey(POM.NetworkLossConstraint, Line),
            ),
        ) + length(
            _assigned_flow_constraint_axis(
                container,
                IOM.ConstraintKey(POM.NetworkLossConstraint, TwoWindingTransformer),
            ),
        )
    @test n_loss == CASE11_DISTINCT_REDUCED_ARCS

    pft_line = IOM.get_variable(container, FlowActivePowerFromToVariable, Line)
    @test !("1-8-i_1" in axes(pft_line)[1])
    t1 = first(IOM.get_time_steps(container))
    @test pft_line["1-6-i_1", t1] === pft_line["6-7-i_1", t1]
    @test pft_line["6-7-i_1", t1] === pft_line["7-2-i_1", t1]
    @test "1-4-i_double_circuit" in axes(pft_line)[1]
    pft_xfmr =
        IOM.get_variable(container, FlowActivePowerFromToVariable, TwoWindingTransformer)
    @test pft_line["1-9-i_1", t1] === pft_xfmr["9-5-i_1", t1]
end

@testset "voltage-coupled device at a reduction-absorbed bus fails with a clear error" begin
    # PNM absorbs bus 8 (radial) even with a shunt attached; the shunt's q == b·v²
    # constraint needs the local voltage, which has no variables after the reduction.
    sys = _case11_with_forecast()
    bus8 = first(b for b in get_components(ACBus, sys) if PSY.get_number(b) == 8)
    shunt = PSY.SwitchedAdmittance(;
        name = "sh8",
        available = true,
        bus = bus8,
        Y = 0.0 + 0.1im,
        number_of_steps = [5],
        Y_increase = [0.0 + 0.02im],
    )
    PSY.add_component!(sys, shunt)
    net = NetworkModel(
        ACPNetworkModel;
        network_source = NetworkReductionSpec(
            PNM.RadialReduction(),
            PNM.DegreeTwoReduction(),
        ),
    )
    template = get_thermal_dispatch_template_network(net)
    set_device_model!(
        template, DeviceModel(PSY.SwitchedAdmittance, ShuntSusceptanceDispatch),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    out = mktempdir(; cleanup = true)
    @test build!(model; output_dir = out, console_level = Logging.Error) ==
          IOM.ModelBuildStatus.FAILED
    log = read(joinpath(out, "operation_problem.log"), String)
    @test occursin("absorbed by a network reduction", log)
end

# TODO: reenable with Phase angle control
@testset "PhaseAngleControl branch absorbed by a network reduction fails with a clear error" begin
    #    # "1-6-i_1" is one segment of the (1,2) series chain, so under reduction it has no
    #    # direct-branch entry of its own — the same _validate_controlled_branch_not_reduced
    #    # gate exercised above for VoltageControlTap also covers PhaseAngleControl.
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
    #        network_source = NetworkReductionSpec(
    #            PNM.RadialReduction(),
    #            PNM.DegreeTwoReduction(),
    #        ),
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
end

# TODO: reenable with tap control
@testset "tap regulated-bus resolution errors for non-retained bus numbers" begin
    #    sys = PSB.build_system(PSITestSystems, "c_sys14")
    #    tr = PSY.get_component(PSY.TwoWindingTransformer, sys, "Trans1")
    #    PSY.set_regulated_bus_number!(PSY.get_circuit(tr), 999)
    #    geom = POM._branch_geometry(tr)
    #    number_to_name = Dict(1 => "Bus 1")
    #    @test_throws ErrorException POM._tap_regulated_bus_name(tr, geom, number_to_name)
    #    bus_by_number = Dict(1 => PSY.get_from(PSY.get_arc(tr)))
    #    @test_throws ErrorException POM._tap_regulated_bus(tr, bus_by_number)
end

@testset "ACP + StaticBranchBounds use_slacks wires flow-definition slacks per reduced arc" begin
    # The c_sys5 coefficient tests exercise only the identity reduction; here the arcs
    # genuinely merge, so the flow-definition slack machinery is checked against the
    # reduced-arc representative names and the PNM equivalent ratings.
    sys = _case11_with_forecast()
    # Lower one NON-representative member of the (1,2) series chain so the arc's PNM
    # series-equivalent rating (the min over the chain) drops strictly below the
    # representative segment's own rating — the box bound must then follow the reduction
    # entry, not the raw representative device.
    tightened_member = "7-2-i_1"
    tightened_rating = 1.5
    PSY.set_rating!(
        PSY.get_component(PSY.Line, sys, tightened_member),
        tightened_rating * PSY.SU,
    )

    net = NetworkModel(
        ACPNetworkModel;
        network_source = NetworkReductionSpec(
            PNM.RadialReduction(),
            PNM.DegreeTwoReduction(),
        ),
    )
    template = get_thermal_dispatch_template_network(net)
    set_device_model!(
        template,
        DeviceModel(PSY.Line, StaticBranchBounds; use_slacks = true),
    )
    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(
        model;
        output_dir = mktempdir(; cleanup = true),
        console_level = Logging.Error,
    ) == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    network_model = get_network_model(get_template(model))
    nr = get_network_reduction(network_model)

    # Guard: a genuine (non-identity) reduction. An identity reduction would silently make
    # this a duplicate of the c_sys5 coefficient tests.
    @test !isempty(nr)
    line_entries = POM.get_name_to_arc_map_entries(nr, PSY.Line)
    reduced_names = collect(keys(line_entries))
    n_raw_lines = length(collect(PSY.get_components(PSY.Line, sys)))
    @test length(reduced_names) < n_raw_lines       # series/parallel arcs merged
    @test !("1-8-i_1" in reduced_names)             # radial leaf absorbed, no arc entry

    metas = POM.FLOW_DEFINITION_SLACK_METAS
    pft = IOM.get_variable(container, FlowActivePowerFromToVariable, PSY.Line)
    ptf = IOM.get_variable(container, FlowActivePowerToFromVariable, PSY.Line)
    qft = IOM.get_variable(container, FlowReactivePowerFromToVariable, PSY.Line)
    qtf = IOM.get_variable(container, FlowReactivePowerToFromVariable, PSY.Line)
    slack_up = Dict(
        m => IOM.get_variable(container, FlowActivePowerSlackUpperBound, PSY.Line, m)
        for m in metas
    )
    slack_lo = Dict(
        m => IOM.get_variable(container, FlowActivePowerSlackLowerBound, PSY.Line, m)
        for m in metas
    )

    # The four directional flow variables alias the shared per-arc refs, so they span the
    # full variable axis (every reduced-arc member name).
    variable_set = Set(reduced_names)
    for var in (pft, ptf, qft, qtf)
        @test Set(axes(var)[1]) == variable_set
    end

    cons = Dict(
        m => IOM.get_constraint(container, POM.NetworkFlowConstraint, PSY.Line, m)
        for m in metas
    )
    con_rate_ft = IOM.get_constraint(container, FlowRateConstraintFromTo, PSY.Line)
    con_rate_tf = IOM.get_constraint(container, FlowRateConstraintToFrom, PSY.Line)
    objective = JuMP.objective_function(IOM.get_jump_model(container))
    time_steps = IOM.get_time_steps(container)

    # The Ohm's-law equality is written once per reduced arc under its representative name;
    # the constraint axis is the per-arc claim set — a strict subset of the variable axis,
    # which lists every arc member. The flow-definition slacks must be keyed on exactly that
    # constraint axis, so no slack is created (and priced) without entering a row.
    constraint_names = collect(axes(cons["p_ft"])[1])
    constraint_set = Set(constraint_names)
    @test !isempty(constraint_names)
    @test issubset(constraint_set, variable_set)
    non_representative = setdiff(variable_set, constraint_set)
    @test !isempty(non_representative)   # the reduction genuinely merges arc members
    for m in metas
        @test Set(axes(slack_up[m])[1]) == constraint_set
        @test Set(axes(slack_lo[m])[1]) == constraint_set
        # No slack container entry exists for a non-representative arc member.
        for name in non_representative
            @test !(name in axes(slack_up[m])[1])
            @test !(name in axes(slack_lo[m])[1])
        end
    end

    for name in constraint_names
        for t in time_steps
            # `flow == physics + s⁺ − s⁻` ⇒ residual −1 on s⁺, +1 on s⁻, but ONLY in the
            # pair's own directional row; the other three rows carry 0. The cross-row zero
            # asserts guard against a shared self-cancelling pair leaking across the
            # anti-symmetric p_ft/p_tf rows.
            for own in metas
                for row in metas
                    up_coef = slack_residual_coefficient(
                        cons[row][name, t],
                        slack_up[own][name, t],
                    )
                    lo_coef = slack_residual_coefficient(
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

            # The exact apparent-power limits carry none of the slacks.
            for con in (con_rate_ft, con_rate_tf)
                for m in metas
                    @test slack_residual_coefficient(
                        con[name, t],
                        slack_up[m][name, t],
                    ) == 0.0
                    @test slack_residual_coefficient(
                        con[name, t],
                        slack_lo[m][name, t],
                    ) == 0.0
                end
            end
        end
    end

    # Directional flow variables carry hard ±(equivalent rating) box bounds, and every
    # slack column is priced. The equivalent rating is read from the reduction entry (the
    # PNM series/parallel aggregate reached exactly as `branch_rate_bounds!` does).
    all_maps = PNM.get_all_branch_maps_by_type(nr)
    device_model = get_model(get_template(model), PSY.Line)
    for (name, (arc, reduction)) in line_entries
        entry = all_maps[reduction][PSY.Line][arc]
        rating = POM.branch_rating(entry, device_model)
        for t in time_steps
            for var in (pft, ptf, qft, qtf)
                @test JuMP.has_upper_bound(var[name, t])
                @test JuMP.has_lower_bound(var[name, t])
                @test JuMP.upper_bound(var[name, t]) == rating
                @test JuMP.lower_bound(var[name, t]) == -rating
            end
        end
    end

    # Every slack column that exists (one per reduced arc, on the constraint axis) is priced
    # at the violation cost — there are no unpriced or priced-but-unconstrained columns.
    for name in constraint_names
        for t in time_steps
            for m in metas
                @test JuMP.coefficient(objective, slack_up[m][name, t]) ==
                      POM.CONSTRAINT_VIOLATION_SLACK_COST
                @test JuMP.coefficient(objective, slack_lo[m][name, t]) ==
                      POM.CONSTRAINT_VIOLATION_SLACK_COST
            end
        end
    end

    # Non-triviality: the tightened member sits inside the (1,2) series chain whose
    # representative row is "1-6-i_1". The bound on that representative equals the chain's
    # equivalent rating (the min = the tightened value), strictly below the representative
    # segment's own raw rating — so the bound is driven by the PNM reduction entry.
    (arc_12, red_12) = line_entries["1-6-i_1"]
    entry_12 = all_maps[red_12][PSY.Line][arc_12]
    @test PNM.get_equivalent_rating(entry_12) == tightened_rating
    representative_raw =
        PSY.get_rating(PSY.get_component(PSY.Line, sys, "1-6-i_1"), PSY.SU)
    @test tightened_rating < representative_raw
    @test JuMP.upper_bound(pft["1-6-i_1", first(time_steps)]) == tightened_rating
end

@testset "Reduction flags map to the same PNM reductions everywhere" begin
    for (radial, degree_two, expected) in (
        (false, false, 0),
        (true, false, 1),
        (false, true, 1),
        (true, true, 2),
    )
        net = NetworkModel(
            POM.DCPNetworkModel;
            network_source = _network_source_from_flags(radial, degree_two),
        )
        reductions = POM._source_reductions(get_network_source(net))
        @test length(reductions) == expected
        if radial
            @test POM.PNM.RadialReduction() in reductions
        end
    end

    # Unit coverage above pins the source -> reductions mapping itself, but not the
    # build sites that consume it. Drive each one through the real build pipeline and
    # read the reduction back off the built network model/matrices, so a site wired to
    # the wrong source would fail here.
    for (radial, degree_two) in ((false, false), (true, false), (false, true), (true, true))
        model_dcp, status_dcp = _solve_case11_native(
            DCPNetworkModel, HiGHS_optimizer;
            reduce_radial_branches = radial, reduce_degree_two_branches = degree_two,
        )
        @test status_dcp == IOM.ModelBuildStatus.BUILT
        nr_dcp = get_network_reduction(get_network_model(get_template(model_dcp)))
        @test PNM.has_radial_reduction(nr_dcp) == radial
        @test PNM.has_degree_two_reduction(nr_dcp) == degree_two

        # Plain PTDFNetworkModel, no outage-aware branch: no contingency matrix is
        # ever built, so this isolates the PTDF site.
        model_ptdf, status_ptdf = _solve_case11_native(
            PTDFNetworkModel, HiGHS_optimizer;
            reduce_radial_branches = radial, reduce_degree_two_branches = degree_two,
        )
        @test status_ptdf == IOM.ModelBuildStatus.BUILT
        nr_ptdf = get_network_reduction(get_network_model(get_template(model_ptdf)))
        @test PNM.has_radial_reduction(nr_ptdf) == radial
        @test PNM.has_degree_two_reduction(nr_ptdf) == degree_two

        # PTDFNetworkModel + an outage-aware branch derives a MODF alongside the PTDF.
        # No reconciliation pass exists any more to repair a divergence after the fact,
        # so the MODF's own reduction is asserted directly below: this isolates the MODF
        # site the way the two checks above isolate theirs, and pins the property the
        # shared factorization core is supposed to guarantee.
        sys_modf = _case11_with_forecast()
        outaged_line = PSY.get_component(PSY.Line, sys_modf, "4-5-i_1")
        transition = PSY.GeometricDistributionForcedOutage(;
            mean_time_to_recovery = 10,
            outage_transition_probability = 0.9999,
            monitored_components = [outaged_line],
        )
        PSY.add_supplemental_attribute!(sys_modf, outaged_line, transition)
        net_modf = NetworkModel(
            PTDFNetworkModel;
            network_source = _network_source_from_flags(radial, degree_two),
        )
        template_modf = get_thermal_dispatch_template_network(net_modf)
        set_device_model!(template_modf, PSY.Line, SecurityConstrainedStaticBranch)
        model_modf = DecisionModel(template_modf, sys_modf; optimizer = HiGHS_optimizer)
        @test build!(
            model_modf;
            output_dir = mktempdir(; cleanup = true),
            console_level = Logging.Error,
        ) == IOM.ModelBuildStatus.BUILT

        network_model_modf = get_network_model(get_template(model_modf))
        nr_ptdf_modf = get_network_reduction(network_model_modf)
        @test PNM.has_radial_reduction(nr_ptdf_modf) == radial
        @test PNM.has_degree_two_reduction(nr_ptdf_modf) == degree_two

        modf_matrix = IOM.get_contingency_matrix(network_model_modf)
        nr_modf = PNM.get_network_reduction_data(modf_matrix)
        @test PNM.has_radial_reduction(nr_modf) == radial
        @test PNM.has_degree_two_reduction(nr_modf) == degree_two

        # The MODF must not merely carry the same reduction flags as the PTDF; it must
        # be reduced onto the very same bus set, which is what makes the nodal-balance
        # rows and the post-contingency MODF columns dimensionally compatible.
        nr_ptdf_matrix =
            PNM.get_network_reduction_data(IOM.get_network_matrix(network_model_modf))
        @test PNM.get_bus_reduction_map(nr_modf) ==
              PNM.get_bus_reduction_map(nr_ptdf_matrix)
        @test PNM.get_bus_reduction_map(nr_modf) ==
              PNM.get_bus_reduction_map(nr_ptdf_modf)
    end
end

@testset "Reduction exceptions are collected per device model" begin
    sys = _case11_with_forecast()
    # Rating time series must share the load forecast's resolution/initial times —
    # DecisionModel rejects a system with mixed time series resolutions.
    rating_line = get_component(PSY.Line, sys, "4-5-i_1")
    rating_data = Dict(
        DateTime("2020-01-01T08:00:00") => fill(0.9, 5),
        DateTime("2020-01-01T08:30:00") => fill(0.9, 5),
        DateTime("2020-01-01T09:00:00") => fill(0.9, 5),
    )
    add_time_series!(
        sys,
        rating_line,
        Deterministic("branch_rating", rating_data, Dates.Minute(5)),
    )
    net = NetworkModel(
        POM.DCPNetworkModel;
        network_source = NetworkReductionSpec(PNM.RadialReduction()),
    )
    template = get_thermal_dispatch_template_network(net)
    set_device_model!(
        template,
        DeviceModel(
            PSY.Line,
            StaticBranch;
            time_series_names = Dict(BranchRatingTimeSeriesParameter => "branch_rating"),
        ),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    branch_models = get_branch_models(get_template(model))
    exceptions = POM._collect_reduction_exceptions(
        sys,
        get_network_model(get_template(model)),
        branch_models,
    )
    # "4-5-i_1" carries the rating time series; its endpoint buses (4, 5) must be
    # pinned so the reduction can't merge them away.
    @test 4 in exceptions
    @test 5 in exceptions
    @test length(exceptions) == 2
end

@testset "Caller-supplied reduction_exceptions survive the build's reduction" begin
    # Bus 8 hangs off a radial branch, so RadialReduction absorbs it into bus 1 unless
    # something pins it. Asserted through a real build so the wiring from the
    # NetworkModel keyword to the Ybus's irreducible set is what is under test.
    function _retained_after_build(exceptions)
        net = NetworkModel(
            POM.DCPNetworkModel;
            network_source = NetworkReductionSpec(PNM.RadialReduction()),
            reduction_exceptions = exceptions,
        )
        template = get_thermal_dispatch_template_network(net)
        model = DecisionModel(
            template,
            _case11_with_forecast();
            optimizer = HiGHS_optimizer,
        )
        @test build!(
            model;
            output_dir = mktempdir(; cleanup = true),
            console_level = Logging.Error,
        ) == IOM.ModelBuildStatus.BUILT
        network_model = get_network_model(get_template(model))
        @test get_reduction_exceptions(network_model) == exceptions
        return Set(
            keys(PNM.get_bus_reduction_map(get_network_reduction(network_model))),
        )
    end

    @test !(8 in _retained_after_build(Int[]))
    @test 8 in _retained_after_build([8])
end

@testset "Non-PTDF families honour a prebuilt source's reduction" begin
    # DCP consumes no sensitivity matrix, so a prebuilt PTDF or core is unused as a
    # matrix — but it still declares the reduced network the build must run on.
    reductions = PNM.NetworkReduction[PNM.RadialReduction()]

    function _dcp_reduction_from(build_source)
        sys = _case11_with_forecast()
        net = NetworkModel(POM.DCPNetworkModel; network_source = build_source(sys))
        template = get_thermal_dispatch_template_network(net)
        model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test build!(
            model;
            output_dir = mktempdir(; cleanup = true),
            console_level = Logging.Error,
        ) == IOM.ModelBuildStatus.BUILT
        return get_network_reduction(get_network_model(get_template(model)))
    end

    from_matrix = _dcp_reduction_from(
        sys -> PrebuiltMatrixSource(
            PNM.VirtualPTDF(
                sys;
                tol = POM.PTDF_ZERO_TOL,
                network_reductions = reductions,
            ),
        ),
    )
    @test PNM.has_radial_reduction(from_matrix)

    from_core = _dcp_reduction_from(
        sys -> PrebuiltCoreSource(
            PNM.VirtualFactorCore(
                PNM.Ybus(sys; network_reductions = reductions);
                tol = POM.PTDF_ZERO_TOL,
                system_uuid = IS.get_uuid(sys),
            ),
        ),
    )
    @test PNM.has_radial_reduction(from_core)

    # Control: the same formulation and template with a source that reduces nothing.
    # Without this the two assertions above could pass on an unreduced network.
    @test !PNM.has_radial_reduction(
        _dcp_reduction_from(sys -> IOM.DefaultNetworkSource()),
    )
end
