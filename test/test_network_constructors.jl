function add_load_time_series_data!(sys)
    # Fractions of each load's max_active_power, not absolute power, so total
    # demand stays under generation capacity across every timestep.
    profile = Dict(
        DateTime("2020-01-01T08:00:00") => [0.5, 0.6, 0.7, 0.7, 0.7],
        DateTime("2020-01-01T08:30:00") => [0.9, 0.9, 0.9, 0.9, 0.8],
        DateTime("2020-01-01T09:00:00") => [0.6, 0.6, 0.5, 0.5, 0.4],
    )
    resolution = Dates.Minute(5)
    forecast = Deterministic("max_active_power", profile, resolution)
    add_time_series!(sys, collect(get_components(StandardLoad, sys)), forecast)
    return sys
end

function _reduced_ptdf_duals_template()
    sys = build_system(PSITestSystems, "case11_network_reductions")
    add_load_time_series_data!(sys)
    nr = NetworkReduction[RadialReduction(), DegreeTwoReduction()]
    ptdf = PTDF(sys; network_reductions = nr)

    template = PowerOperationsProblemTemplate(
        NetworkModel(PTDFNetworkModel;
            network_matrix = ptdf,
            duals = [CopperPlateBalanceConstraint],
            reduce_radial_branches = PNM.has_radial_reduction(ptdf.network_reduction_data),
            reduce_degree_two_branches = PNM.has_degree_two_reduction(
                ptdf.network_reduction_data,
            ),
            use_slacks = false),
    )
    # Mirror the filter shape from issue #1594: a voltage threshold that selects
    # all lines in this all-230 kV system. The filter is registered (so the
    # filter_function code path runs) but does not exclude any branch from a
    # series chain, so reductions still drop lines from the constraint axis.
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            duals = [FlowRateConstraint],
            attributes = Dict(
                "filter_function" =>
                    x -> PSY.get_base_voltage(PSY.get_from(PSY.get_arc(x))) >= 230.0,
            ),
        ),
    )
    set_device_model!(template, TwoWindingTransformer, StaticBranch)
    return sys, template
end

# Regression test for PSI #1594
@testset "FlowRateConstraint duals with branch filter and network reductions" begin
    sys, template = _reduced_ptdf_duals_template()
    ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = get_optimization_container(ps_model)
    # The unfiltered Line set has 12 entries; full reduction leaves 6 entries
    # in the constraint axis. The dual container must use the same 6 entries.
    for meta in ("lb", "ub")
        cons_key = ConstraintKey(FlowRateConstraint, Line, meta)
        cons = get_constraint(container, cons_key)
        dual = get_duals(container)[cons_key]
        @test axes(dual)[1] == axes(cons)[1]
        @test length(axes(cons)[1]) <
              length(collect(get_components(Line, sys)))
        @test "4-5-i_1" in axes(cons)[1]
    end
end

# Companion to the build-only test above: the same reduced-PTDF setup, but
# solved end-to-end so the process_duals broadcast actually runs, not just the
# build-time axis check.
@testset "FlowRateConstraint duals with network reductions solved end-to-end" begin
    sys, template = _reduced_ptdf_duals_template()
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, StandardLoad, StaticPowerLoad)

    ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(ps_model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = get_optimization_container(ps_model)
    line_names = collect(get_name.(get_components(Line, sys)))
    for meta in ("lb", "ub")
        cons_key = ConstraintKey(FlowRateConstraint, Line, meta)
        cons = get_constraint(container, cons_key)
        dual = get_duals(container)[cons_key]
        @test axes(dual)[1] == axes(cons)[1]
        @test length(axes(cons)[1]) < length(line_names)
    end

    res = IOM.OptimizationProblemOutputs(ps_model)
    for meta in ("lb", "ub")
        cons_key = ConstraintKey(FlowRateConstraint, Line, meta)
        cons_axis = axes(get_constraint(container, cons_key))[1]
        duals_df = read_dual(res, cons_key; table_format = TableFormat.WIDE)
        dual_names = String.([c for c in propertynames(duals_df) if c != :DateTime])
        @test Set(dual_names) == Set(cons_axis)
        @test length(dual_names) < length(line_names)
        dual_values = Matrix(duals_df[:, propertynames(duals_df) .!= :DateTime])
        @test all(isfinite, dual_values)
    end
end

# No PSB system ships with both Areas and InterconnectingConverters, so the two
# 5-bus halves of sys10_pjm_ac_dc (bridged only by the DC ties) are split into
# two areas. Every converter must enter its Area, AC-bus, and DC-bus
# ActivePowerBalance expressions with the correct signed coefficients.
@testset "AreaPTDFNetworkModel with InterconnectingConverter" begin
    sys = build_system(PSISystems, "sys10_pjm_ac_dc")
    # Double the marginal cost of every Area_2-side thermal unit so the optimum
    # must move power across the DC ties (non-vacuity of the converter wiring).
    for g in get_components(ThermalStandard, sys)
        endswith(get_name(g), "-2") || continue
        op_cost = get_operation_cost(g)
        val_curve = get_value_curve(PSY.get_variable(op_cost))
        new_op_cost = ThermalGenerationCost(
            CostCurve(
                QuadraticCurve(
                    get_quadratic_term(val_curve),
                    2.0 * get_proportional_term(val_curve),
                    get_constant_term(val_curve),
                ),
                get_power_units(PSY.get_variable(op_cost)),
                get_vom_cost(PSY.get_variable(op_cost)),
            ),
            get_fixed(op_cost),
            get_start_up(op_cost),
            get_shut_down(op_cost),
        )
        set_operation_cost!(g, new_op_cost)
    end
    areas = [Area("Area_1", 0.0, 0.0, 0.0), Area("Area_2", 0.0, 0.0, 0.0)]
    for a in areas
        add_component!(sys, a)
    end
    for b in get_components(ACBus, sys)
        if get_number(b) <= 5
            set_area!(b, areas[1])
        else
            set_area!(b, areas[2])
        end
    end

    template = get_thermal_dispatch_template_network(AreaPTDFNetworkModel)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, DeviceModel(InterconnectingConverter, LosslessConverter))
    set_device_model!(template, DeviceModel(TModelHVDCLine, LosslessLine))
    set_hvdc_network_model!(template, TransportHVDCNetworkModel)

    ps_model = DecisionModel(
        template, sys; store_variable_names = true, optimizer = HiGHS_optimizer,
    )
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(ps_model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(ps_model)
    area_expr = IOM.get_expression(container, ActivePowerBalance, Area)
    ac_expr = IOM.get_expression(container, ActivePowerBalance, ACBus)
    dc_expr = IOM.get_expression(container, ActivePowerBalance, DCBus)
    conv = IOM.get_variable(container, ActivePowerVariable, InterconnectingConverter)
    converters = collect(get_components(InterconnectingConverter, sys))
    @test !isempty(converters)
    for ic in converters
        name = get_name(ic)
        bus = get_bus(ic)
        area_name = get_name(get_area(bus))
        bus_no = get_number(bus)
        dc_bus_no = get_number(get_dc_bus(ic))
        for t in (1, size(conv)[2])
            v = conv[name, t]
            @test JuMP.coefficient(area_expr[area_name, t], v) == 1.0
            @test JuMP.coefficient(ac_expr[bus_no, t], v) == 1.0
            @test JuMP.coefficient(dc_expr[dc_bus_no, t], v) == -1.0
        end
    end

    # The two areas exchange power only through the DC ties, so at the optimum the
    # converters must carry a non-zero transfer (non-vacuity of the wiring above).
    p = JuMP.value.(conv)
    @test maximum(abs.(p.data)) > 1e-3
end
