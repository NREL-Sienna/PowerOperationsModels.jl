
"""
Verify that solved branch flows respect the branch rating time series constraints.
For each branch carrying a rating time series, checks that
|flow| ≤ static_rating × rating_factor at each time step.
Adapted from PSI's check_branch_rating_time_series_flows! to work with POM's
in-memory model access.

For a parallel group the flow is bounded by the group's sum-of-max rating. The
test setup (`add_equivalent_ac_transmission_with_parallel_circuits!`) adds a
single equal-rating parallel circuit, so the group rating is 2× the original
single-branch rating.
"""
function check_branch_rating_time_series_flows!(
    model::DecisionModel,
    sys::PSY.System,
    branches_with_rating_ts::Vector{<:AbstractString},
    rating_factors::Vector{Float64},
    add_parallel_line_name::Union{Nothing, AbstractString} = nothing,
)
    container = IOM.get_optimization_container(model)
    for branch_name in branches_with_rating_ts
        branch = get_component(PSY.ACTransmission, sys, branch_name)
        is_parallel_group_flow =
            !isnothing(add_parallel_line_name) &&
            contains(branch_name, add_parallel_line_name)
        col_key = if is_parallel_group_flow
            replace(branch_name, "_copy" => "") * "double_circuit"
        else
            branch_name
        end

        static_rating = branch_rating_su(branch) * PSY.get_base_power(sys, PSY.NU)
        if is_parallel_group_flow
            static_rating *= 2
        end
        branch_type = typeof(branch)
        flow_expr = IOM.get_expression(container, PTDFBranchFlow, branch_type)
        n_rating = length(rating_factors)
        for (i, t) in enumerate(axes(flow_expr, 2))
            f = IOM.jump_value(flow_expr[col_key, t])
            rating_idx = mod1(i, n_rating)
            @test f <= static_rating * rating_factors[rating_idx] + 1e-5
            @test f >= -static_rating * rating_factors[rating_idx] - 1e-5
        end
    end
end

@testset "Network DC-PF with VirtualPTDF Model and implementing branch rating time series" begin
    line_device_model = DeviceModel(
        Line,
        StaticBranch;
        time_series_names = Dict(
            BranchRatingTimeSeriesParameter => "branch_rating",
        ))
    TapTransf_device_model = DeviceModel(
        TwoWindingTransformer,
        StaticBranch;
        time_series_names = Dict(
            BranchRatingTimeSeriesParameter => "branch_rating",
        ))
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
    ]
    PTDF_ref = IdDict{System, PTDF}(
        c_sys5 => PTDF(c_sys5),
        c_sys14 => PTDF(c_sys14),
        c_sys14_dc => PTDF(c_sys14_dc),
    )
    branches_with_rating_ts = IdDict{System, Vector{String}}(
        c_sys5 => ["1", "2", "6"],
        c_sys14 => ["Line1", "Line2", "Line9", "Line10", "Line12", "Trans2"],
        c_sys14_dc => ["Line1", "Line9", "Line10", "Line12", "Trans2"],
    )
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [120, 0, 264, 264, 24],
        c_sys14 => [120, 0, 600, 600, 24],
        c_sys14_dc => [168, 0, 648, 552, 24],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 241293.703,
        c_sys14 => 143365.0,
        c_sys14_dc => 142000.0,
    )
    n_steps = 2
    for (ix, sys) in enumerate(systems)
        add_branch_rating_time_series_to_system!(
            sys,
            branches_with_rating_ts[sys],
            n_steps,
            rating_factors;
            initial_date = "2024-01-01",
        )
        template = get_thermal_dispatch_template_network(
            NetworkModel(
                PTDFNetworkModel;
                network_matrix = PTDF_ref[sys],
            ),
        )

        set_device_model!(template, line_device_model)
        set_device_model!(template, TapTransf_device_model)
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)

        moi_tests(
            ps_model,
            test_results[sys]...,
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
            test_obj_values[sys],
            10000,
        )
        check_branch_rating_time_series_flows!(
            ps_model,
            sys,
            branches_with_rating_ts[sys],
            rating_factors,
            nothing,
        )
    end
end

@testset "Network DC-PF with PTDF Model and implementing branch rating time series with BranchesParallel of different types" begin
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
    ]
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    # BranchRatingTimeSeriesParameter constraints are correctly applied to
    # parallel arcs shared between different branch types. The mixed parallel
    # group's max rating is the sum of its individual members
    # (`get_sum_of_max_rating`), so adding a parallel copy doubles the group
    # capacity and lowers the optimum cost. ix=1's objective changed from the
    # pre-Phase-2 default to 256079.26 under the `single_element_contingency`
    # parallel-rating default.
    test_obj_values = [256079.26, 241417.66, 245042.86]
    parallel_lines_names_to_add = ["1", "2", "3"]
    n_steps = 2

    for slack_flag in [false, true]
        if slack_flag
            test_results = [408, 0, 264, 264, 24]
        else
            test_results = [120, 0, 264, 264, 24]
        end
        line_device_model = DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
            use_slacks = slack_flag,
        )
        for (ix, add_parallel_line_name) in enumerate(parallel_lines_names_to_add)
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            line_to_add_parallel = get_component(Line, sys, add_parallel_line_name)
            add_equivalent_ac_transmission_with_parallel_circuits!(
                sys,
                line_to_add_parallel,
                PSY.Line,
                PSY.MonitoredLine,
            )

            add_branch_rating_time_series_to_system!(
                sys,
                branches_with_rating_ts,
                n_steps,
                rating_factors;
                initial_date = "2024-01-01",
            )

            template = get_thermal_dispatch_template_network(
                NetworkModel(
                    PTDFNetworkModel;
                    network_matrix = PTDF(sys),
                ),
            )
            set_device_model!(template, line_device_model)
            set_device_model!(template, PSY.MonitoredLine, StaticBranch)
            ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

            @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT
            psi_constraint_test(ps_model, constraint_keys)

            moi_tests(
                ps_model,
                test_results...,
                false,
            )
            psi_checkobjfun_test(ps_model, objfuncs[1])
            psi_checksolve_test(
                ps_model,
                [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
                test_obj_values[ix],
                10000,
            )
            check_branch_rating_time_series_flows!(
                ps_model,
                sys,
                branches_with_rating_ts,
                rating_factors,
                add_parallel_line_name,
            )
        end
    end
end

@testset "Network DC-PF with PTDF Model and implementing branch rating time series with BranchesParallel of different types (MonitoredLine with BranchRatingTimeSeriesParameter)" begin
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
    ]

    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    # Mixed parallel groups use `get_sum_of_max_rating` (sum of branch ratings),
    # so the group capacity is double the single-line case. ix=1's objective
    # changed to 256079.26 under the `single_element_contingency` parallel-rating
    # default.
    test_obj_values = [256079.26, 240206.07, 242012.67]
    parallel_lines_names_to_add = ["1", "2", "3"]
    n_steps = 2

    for slack_flag in [false, true]
        if slack_flag
            test_results = [408, 0, 264, 264, 24]
        else
            test_results = [120, 0, 264, 264, 24]
        end
        line_device_model = DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
            use_slacks = slack_flag,
        )
        for (ix, add_parallel_line_name) in enumerate(parallel_lines_names_to_add)
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            line_to_add_parallel = get_component(Line, sys, add_parallel_line_name)
            add_equivalent_ac_transmission_with_parallel_circuits!(
                sys,
                line_to_add_parallel,
                PSY.Line,
                PSY.MonitoredLine,
            )

            add_branch_rating_time_series_to_system!(
                sys,
                [add_parallel_line_name * "_copy"],
                n_steps,
                rating_factors;
                initial_date = "2024-01-01",
            )

            template = get_thermal_dispatch_template_network(
                NetworkModel(
                    PTDFNetworkModel;
                    network_matrix = PTDF(sys),
                ),
            )
            set_device_model!(template, line_device_model)
            set_device_model!(template, PSY.MonitoredLine, StaticBranch)
            ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

            @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT
            psi_constraint_test(ps_model, constraint_keys)

            moi_tests(
                ps_model,
                test_results...,
                false,
            )
            psi_checkobjfun_test(ps_model, objfuncs[1])
            psi_checksolve_test(
                ps_model,
                [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
                test_obj_values[ix],
                10000,
            )
            check_branch_rating_time_series_flows!(
                ps_model,
                sys,
                [add_parallel_line_name * "_copy"],
                rating_factors,
                add_parallel_line_name,
            )
        end
    end
end

@testset "Network DC-PF with PTDF Model and implementing branch rating time series with BranchesParallel" begin
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
    ]
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    # All three parallel placements converge to the same objective because the
    # rating time series forces the parallel group's effective multiplier to
    # `get_sum_of_max_rating`, which restores the pre-parallel R capacity
    # regardless of which line is split.
    test_obj_values = [243877.86, 243877.86, 243877.86]
    parallel_lines_names_to_add = ["1", "2", "3"]
    n_steps = 2

    for slack_flag in [false, true]
        if slack_flag
            test_results = [408, 0, 264, 264, 24]
        else
            test_results = [120, 0, 264, 264, 24]
        end
        line_device_model = DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
            use_slacks = slack_flag,
        )
        for (ix, add_parallel_line_name) in enumerate(parallel_lines_names_to_add)
            sys = PSB.build_system(PSITestSystems, "c_sys5")
            line_to_add_parallel = get_component(Line, sys, add_parallel_line_name)
            add_equivalent_ac_transmission_with_parallel_circuits!(
                sys,
                line_to_add_parallel,
                PSY.Line,
            )

            add_branch_rating_time_series_to_system!(
                sys,
                branches_with_rating_ts,
                n_steps,
                rating_factors;
                initial_date = "2024-01-01",
            )

            template = get_thermal_dispatch_template_network(
                NetworkModel(
                    PTDFNetworkModel;
                    network_matrix = PTDF(sys),
                ),
            )
            set_device_model!(template, line_device_model)
            ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

            @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT
            psi_constraint_test(ps_model, constraint_keys)

            moi_tests(
                ps_model,
                test_results...,
                false,
            )
            psi_checkobjfun_test(ps_model, objfuncs[1])
            psi_checksolve_test(
                ps_model,
                [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
                test_obj_values[ix],
                10000,
            )
            check_branch_rating_time_series_flows!(
                ps_model,
                sys,
                branches_with_rating_ts,
                rating_factors,
                add_parallel_line_name,
            )
        end
    end
end

@testset "Network DC-PF with PTDF Model and implementing branch rating time series with Reductions" begin
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb"),
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
    ]
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    test_obj_values = [243859.89, 243884.35, 243877.86]
    parallel_lines_names_to_add = ["1", "2", "3"]
    n_steps = 2
    test_results_slacks = Dict(
        1 => [456, 0, 288, 288, 24],
        2 => [456, 0, 288, 288, 24],
        3 => [408, 0, 264, 264, 24],
    )
    test_results_no_slacks = Dict(
        1 => [120, 0, 288, 288, 24],
        2 => [120, 0, 288, 288, 24],
        3 => [120, 0, 264, 264, 24],
    )

    for slack_flag in [false, true]
        line_device_model = DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
            use_slacks = slack_flag,
        )
        for (ix, add_parallel_line_name) in enumerate(parallel_lines_names_to_add)
            if slack_flag
                test_results = test_results_slacks[ix]
            else
                test_results = test_results_no_slacks[ix]
            end
            sys = PSB.build_system(PSITestSystems, "c_sys5")

            line_to_add_parallel = get_component(Line, sys, add_parallel_line_name)
            add_equivalent_ac_transmission_with_series_parallel_circuits!(
                sys,
                line_to_add_parallel,
                PSY.Line,
            )

            add_branch_rating_time_series_to_system!(
                sys,
                branches_with_rating_ts,
                n_steps,
                rating_factors;
                initial_date = "2024-01-01",
            )
            nr = NetworkReduction[DegreeTwoReduction()]
            ptdf = PTDF(sys; network_reductions = nr)
            template = get_thermal_dispatch_template_network(
                NetworkModel(
                    PTDFNetworkModel;
                    #network_matrix = ptdf,
                    reduce_degree_two_branches = PNM.has_degree_two_reduction(
                        ptdf.network_reduction_data,
                    ),
                ),
            )
            set_device_model!(template, line_device_model)
            ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

            @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
                  IOM.ModelBuildStatus.BUILT
            psi_constraint_test(ps_model, constraint_keys)

            moi_tests(
                ps_model,
                test_results...,
                false,
            )
            psi_checkobjfun_test(ps_model, objfuncs[1])
            psi_checksolve_test(
                ps_model,
                [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
                test_obj_values[ix],
                10000,
            )
            check_branch_rating_time_series_flows!(
                ps_model,
                sys,
                branches_with_rating_ts,
                rating_factors,
                add_parallel_line_name,
            )
        end
    end
end

# ---------------------------------------------------------------------------
# Formulation-validation and network-formulation coverage ported from
# PowerSimulations.jl PR #1579 (Task 6.3). These exercise the
# `add_parameters` dispatch on `AbstractNetworkModel`: the
# `BranchRatingTimeSeriesParameter` container must be added under full-AC
# (`ACPNetworkModel`) and DC-OPF (`DCPNetworkModel`) networks, and incompatible
# branch formulations must be rejected at template validation.
# ---------------------------------------------------------------------------

@testset "Branch rating time series formulation validation" begin
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    n_steps = 2

    # Case 1: incompatible formulation (StaticBranchBounds, which rate-limits via
    # variable bounds rather than the parameter container) must raise an
    # IS.ConflictingInputsError at template validation. `build!` swallows build
    # exceptions into a FAILED status, so the check is exercised directly via
    # `validate_template`.
    sys_bounds = PSB.build_system(PSITestSystems, "c_sys5")
    add_branch_rating_time_series_to_system!(
        sys_bounds,
        branches_with_rating_ts,
        n_steps,
        rating_factors;
        initial_date = "2024-01-01",
    )
    template_bounds = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(
        template_bounds,
        DeviceModel(
            Line,
            StaticBranchBounds;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )
    model_bounds = DecisionModel(template_bounds, sys_bounds; optimizer = HiGHS_optimizer)
    @test_throws IS.ConflictingInputsError POM.validate_template(model_bounds)

    # Case 2: StaticBranchUnbounded with a rating time series must NOT error. The
    # formulation enforces no flow limits, so the series cannot be honored;
    # template validation emits a warning and the series is ignored. The model
    # still builds.
    sys_unbounded = PSB.build_system(PSITestSystems, "c_sys5")
    add_branch_rating_time_series_to_system!(
        sys_unbounded,
        branches_with_rating_ts,
        n_steps,
        rating_factors;
        initial_date = "2024-01-01",
    )
    template_unbounded =
        get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(
        template_unbounded,
        DeviceModel(
            Line,
            StaticBranchUnbounded;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )
    model_unbounded =
        DecisionModel(template_unbounded, sys_unbounded; optimizer = HiGHS_optimizer)
    @test (POM.validate_template(model_unbounded); true)
    @test build!(model_unbounded; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
end

@testset "Branch rating time series with DC OPF (DCPNetworkModel) network" begin
    # Under the native DCPNetworkModel the BranchRatingTimeSeriesParameter
    # container must be created and the FlowRate constraint RHS must vary across
    # time steps (the time-varying rating), not collapse to the static rating.
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    n_steps = 2

    sys = PSB.build_system(PSITestSystems, "c_sys5")
    add_branch_rating_time_series_to_system!(
        sys,
        branches_with_rating_ts,
        n_steps,
        rating_factors;
        initial_date = "2024-01-01",
    )

    template = get_thermal_dispatch_template_network(NetworkModel(DCPNetworkModel))
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(container, POM.BranchRatingTimeSeriesParameter, PSY.Line)

    # The single-direction FlowRateConstraint is split into "lb"/"ub" containers.
    @test IOM.has_container_key(
        container,
        FlowRateConstraint,
        PSY.Line,
        "lb",
    )
    @test IOM.has_container_key(
        container,
        FlowRateConstraint,
        PSY.Line,
        "ub",
    )

    # The FlowRate "ub" constraint RHS is built directly from `param * mult`, so
    # it must track the time-varying rating (static_rating * rating_factor[t]),
    # confirming the time series is consumed (not the static rating). The horizon
    # is 24 steps; the factors change every 6 steps, so the RHS must vary across
    # the factor boundaries and equal static_rating * factor at each step.
    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub"),
    )
    time_axis = axes(con_ub, 2)
    n_rating = length(rating_factors)
    for name in branches_with_rating_ts
        branch = get_component(PSY.ACTransmission, sys, name)
        static_rating = branch_rating_su(branch)
        for (i, t) in enumerate(time_axis)
            @test isapprox(
                JuMP.normalized_rhs(con_ub[name, t]),
                static_rating * rating_factors[mod1(i, n_rating)];
                rtol = 1e-5,
            )
        end
        # The RHS must genuinely vary across a factor boundary (0.99 -> 0.98).
        @test !isapprox(
            JuMP.normalized_rhs(con_ub[name, 1]),
            JuMP.normalized_rhs(con_ub[name, 7]);
            atol = 1e-6,
        )
    end
end

@testset "Branch rating time series with full AC (ACPNetworkModel) network" begin
    # Under the native ACPNetworkModel the BranchRatingTimeSeriesParameter
    # container must be created and the apparent-power FlowRate constraint RHS
    # must track the time-varying rating across time steps.
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    n_steps = 2

    sys = PSB.build_system(PSITestSystems, "c_sys5")
    add_branch_rating_time_series_to_system!(
        sys,
        branches_with_rating_ts,
        n_steps,
        rating_factors;
        initial_date = "2024-01-01",
    )

    template = get_thermal_dispatch_template_network(NetworkModel(ACPNetworkModel))
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )

    model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    @test IOM.has_container_key(container, POM.BranchRatingTimeSeriesParameter, PSY.Line)
    # Both apparent-power-flow constraints must be built (no `meta` suffix).
    @test IOM.has_container_key(container, FlowRateConstraintFromTo, PSY.Line)
    @test IOM.has_container_key(container, FlowRateConstraintToFrom, PSY.Line)

    # The FlowRateConstraintFromTo/ToFrom apparent-power constraint is
    # `pft^2 + qft^2 <= (rating * rating_factor[t])^2`, so its RHS is the squared
    # time-varying rating. It must track `(static_rating * rating_factor[t])^2`
    # and vary across the factor boundaries, confirming the time series is consumed.
    ac_ft = IOM.get_constraint(
        container,
        IOM.ConstraintKey(FlowRateConstraintFromTo, PSY.Line),
    )
    ac_tf = IOM.get_constraint(
        container,
        IOM.ConstraintKey(FlowRateConstraintToFrom, PSY.Line),
    )
    time_axis = axes(ac_ft, 2)
    n_rating = length(rating_factors)
    for name in branches_with_rating_ts
        branch = get_component(PSY.ACTransmission, sys, name)
        static_rating = branch_rating_su(branch)
        for (i, t) in enumerate(time_axis)
            expected = (static_rating * rating_factors[mod1(i, n_rating)])^2
            @test isapprox(JuMP.normalized_rhs(ac_ft[name, t]), expected; rtol = 1e-5)
            @test isapprox(JuMP.normalized_rhs(ac_tf[name, t]), expected; rtol = 1e-5)
        end
        @test !isapprox(
            JuMP.normalized_rhs(ac_ft[name, 1]),
            JuMP.normalized_rhs(ac_ft[name, 7]);
            atol = 1e-6,
        )
    end
end

@testset "CopperPlate network: branch rating time series is a no-op" begin
    # Guards the Phase-4 dispatch widening: the CopperPlate network constructor
    # is a no-op for branch models, so even when a StaticBranch DeviceModel is
    # configured with a BranchRatingTimeSeriesParameter time series the container
    # must NOT carry the parameter (the branch flows are not represented, so
    # there is nothing to rate-limit).
    #
    # NOTE: `AreaBalanceNetworkModel` is intentionally NOT exercised here because a
    # thermal-dispatch template with a StaticBranch Line model fails to build
    # under AreaBalance in PS6 (unrelated to branch ratings). The CopperPlate
    # no-op path is the representable guard for the dispatch widening.
    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    n_steps = 2

    sys = PSB.build_system(PSITestSystems, "c_sys5")
    add_branch_rating_time_series_to_system!(
        sys,
        branches_with_rating_ts,
        n_steps,
        rating_factors;
        initial_date = "2024-01-01",
    )

    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    @test !IOM.has_container_key(container, POM.BranchRatingTimeSeriesParameter, PSY.Line)
end

@testset "Branches sharing one rating forecast share a parameter row" begin
    # Bulk `add_time_series!` stores one array for both lines, so both resolve to the same
    # UUID. The UUID parameter axis must dedupe or JuMP rejects the repeated axis element.
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    line_a = get_component(ACTransmission, sys, "1")
    line_b = get_component(ACTransmission, sys, "2")
    PSY.set_rating!(line_b, 2 * PSY.get_rating(line_a, PSY.SU) * PSY.SU)

    data_ts =
        collect(DateTime("2024-01-01T00:00:00"):Hour(1):DateTime("2024-01-01T23:00:00"))
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)
    rating_data = SortedDict{Dates.DateTime, TimeSeries.TimeArray}()
    for t in 1:2
        rating_data[data_ts[1] + Day(t - 1)] =
            TimeArray(data_ts .+ Day(t - 1), rating_factors)
    end
    PSY.add_time_series!(
        sys,
        [line_a, line_b],
        PSY.Deterministic(
            "branch_rating",
            rating_data;
            scaling_factor_multiplier = get_rating,
        ),
    )
    @test IS.get_time_series_uuid(PSY.Deterministic, line_a, "branch_rating") ==
          IS.get_time_series_uuid(PSY.Deterministic, line_b, "branch_rating")

    template = get_thermal_dispatch_template_network(
        NetworkModel(PTDFNetworkModel; network_matrix = PTDF(sys)),
    )
    set_device_model!(
        template,
        DeviceModel(
            Line,
            StaticBranch;
            time_series_names = Dict(
                BranchRatingTimeSeriesParameter => "branch_rating",
            ),
        ),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    param_container =
        IOM.get_parameter(container, BranchRatingTimeSeriesParameter, PSY.Line)
    # One parameter row for the shared series; still one multiplier row per branch.
    @test length(axes(IOM.get_parameter_array(param_container))[1]) == 1
    @test Set(axes(IOM.get_multiplier_array(param_container))[1]) == Set(["1", "2"])
    @test jump_value.(IOM.get_parameter_column_refs(param_container, "1")) ==
          jump_value.(IOM.get_parameter_column_refs(param_container, "2"))

    # Sharing the profile does not merge the branches: each keeps its own rating scale.
    multipliers = IOM.get_multiplier_array(param_container)
    @test multipliers["2", 1] == 2 * multipliers["1", 1]
end
