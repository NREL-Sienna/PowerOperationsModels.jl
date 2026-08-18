@testset "Parallel-branch multiplier rows are populated per-branch (no NaN)" begin
    # Regression coverage for the multiplier-axis bug where parallel branches
    # sharing a time-series UUID had their multipliers written to the wrong row
    # of the device-name-keyed multiplier array, leaving the other branch's row
    # at the construction-time NaN fill.
    line_device_model = DeviceModel(
        Line,
        StaticBranch;
        time_series_names = Dict(
            BranchRatingTimeSeriesParameter => "branch_rating",
        ),
    )

    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    for parallel_line_name in ["1", "2", "3"]
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        line_to_add_parallel = get_component(Line, sys, parallel_line_name)
        add_equivalent_ac_transmission_with_parallel_circuits!(
            sys,
            line_to_add_parallel,
            PSY.Line,
        )
        add_branch_rating_time_series_to_system!(
            sys,
            branches_with_rating_ts,
            2,
            rating_factors;
            initial_date = "2024-01-01",
        )

        template = get_thermal_dispatch_template_network(
            NetworkModel(PTDFNetworkModel),
        )
        set_device_model!(template, line_device_model)
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(ps_model)
        param_key = IOM.ParameterKey(BranchRatingTimeSeriesParameter, Line)
        param_container = IOM.get_parameter(container, param_key)
        mult_array = IOM.get_multiplier_array(param_container)
        device_name_axis = axes(mult_array)[1]

        # Every device row in the multiplier array must be fully populated for
        # branches that actually carry the time series — no rows left at the
        # NaN sentinel from the fill! at construction time.
        for name in device_name_axis
            row = mult_array[name, :]
            @test !any(isnan, row)
        end
    end
end

@testset "Series-chain reduction with branch rating time series builds and resolves multiplier" begin
    # Regression: a branch rating time series on a `PNM.BranchesSeries` reduction
    # used to resolve its multiplier via `PSY.get_rating`, whose generic `Device`
    # fallback throws `ArgumentError` for the wrapper — the build failed.
    line_device_model = DeviceModel(
        Line,
        StaticBranch;
        time_series_names = Dict(
            BranchRatingTimeSeriesParameter => "branch_rating",
        ),
    )

    branches_with_rating_ts = ["1", "2", "6"]
    rating_factors = vcat([fill(x, 6) for x in [0.99, 0.98, 1.0, 0.95]]...)

    for series_line_name in ["1", "2", "6"]
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        line_to_make_series = get_component(Line, sys, series_line_name)
        add_equivalent_ac_transmission_with_series_parallel_circuits!(
            sys,
            line_to_make_series,
            PSY.Line,
        )
        add_branch_rating_time_series_to_system!(
            sys,
            branches_with_rating_ts,
            2,
            rating_factors;
            initial_date = "2024-01-01",
        )

        template = get_thermal_dispatch_template_network(
            NetworkModel(PTDFNetworkModel),
        )
        set_device_model!(template, line_device_model)
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(ps_model)
        param_key = IOM.ParameterKey(BranchRatingTimeSeriesParameter, Line)
        param_container = IOM.get_parameter(container, param_key)
        mult_array = IOM.get_multiplier_array(param_container)

        # Multipliers must be finite, positive ratings — no NaN sentinel rows.
        for name in axes(mult_array)[1]
            row = mult_array[name, :]
            @test !any(isnan, row)
            @test all(v -> isfinite(v) && v > 0.0, row)
        end
    end
end

@testset "Parallel-branch static rating uses single_element_contingency default" begin
    # Numerical-behavior regression for Phase 2: the default parallel-branch
    # rating-aggregation method changed to `single_element_contingency`. This
    # guards (a) that the default DeviceModel attribute is the post-Phase-2
    # method, and (b) that the default actually drives the optimization: a
    # parallel pair built with the default produces the SAME objective as one
    # built with an explicit `single_element_contingency` attribute, and a
    # STRICTLY HIGHER objective than `sum_of_max` (which doubles the group
    # capacity and so relaxes the binding flow limit). No rating time series
    # here, so the static `branch_rating` path is exercised.
    function _parallel_objective(parallel_line_name, method)
        sys = PSB.build_system(PSITestSystems, "c_sys5")
        line = get_component(Line, sys, parallel_line_name)
        add_equivalent_ac_transmission_with_parallel_circuits!(sys, line, PSY.Line)
        attrs = if isnothing(method)
            Dict{String, Any}()
        else
            Dict{String, Any}(POM.PARALLEL_BRANCH_MAX_RATING_KEY => method)
        end
        template = get_thermal_dispatch_template_network(
            NetworkModel(PTDFNetworkModel),
        )
        set_device_model!(template, DeviceModel(Line, StaticBranch; attributes = attrs))
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        solve!(ps_model)
        return JuMP.objective_value(IOM.get_jump_model(ps_model))
    end

    # The default attribute on a freshly-constructed StaticBranch DeviceModel.
    @test POM.get_attribute(
        DeviceModel(Line, StaticBranch),
        POM.PARALLEL_BRANCH_MAX_RATING_KEY,
    ) == "single_element_contingency"

    for parallel_line_name in ["1", "2", "6"]
        obj_default = _parallel_objective(parallel_line_name, nothing)
        obj_single = _parallel_objective(
            parallel_line_name, "single_element_contingency",
        )
        obj_sum = _parallel_objective(parallel_line_name, "sum_of_max")

        # Default resolves to single_element_contingency.
        @test isapprox(obj_default, obj_single; rtol = 1e-6)
        # The N-1 default is strictly more conservative than the unconstrained
        # sum-of-max aggregation, so it yields a higher dispatch cost.
        @test obj_default > obj_sum + 1.0
    end
end
