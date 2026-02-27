@testset "Decision Model kwargs" begin
    template = get_thermal_dispatch_template_network()
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")

    @test_throws MethodError DecisionModel(template, c_sys5; bad_kwarg = 10)

    model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    model = DecisionModel(
        MockOperationProblem,
        get_thermal_dispatch_template_network(
            NetworkModel(CopperPlatePowerModel; use_slacks = true),
        ),
        c_sys5_re;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    model = DecisionModel(
        get_thermal_dispatch_template_network(),
        c_sys5;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    #"Test passing custom JuMP model"
    my_model = JuMP.Model()
    my_model.ext[:PSI_Testing] = 1
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(
        get_thermal_dispatch_template_network(),
        c_sys5,
        my_model;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test haskey(IOM.get_optimization_container(model).JuMPmodel.ext, :PSI_Testing)
end

@testset "Set optimizer at solve call" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    UC = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(UC; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(UC; optimizer = HiGHS_optimizer) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(UC)
    @test isapprox(get_objective_value(res), 340000.0; atol = 100000.0)
    vars = res.variable_values
    @test IOM.VariableKey(ActivePowerVariable, PSY.ThermalStandard) in keys(vars)
    @test size(read_variable(res, "StartVariable__ThermalStandard")) == (120, 3)
    @test size(
        read_variable(
            res,
            "StartVariable__ThermalStandard";
            table_format = TableFormat.WIDE,
        ),
    ) == (24, 6)
    @test size(read_parameter(res, "ActivePowerTimeSeriesParameter__PowerLoad")) == (72, 3)
    @test size(read_expression(res, "ProductionCostExpression__ThermalStandard")) ==
          (120, 3)
    @test size(read_aux_variable(res, "TimeDurationOn__ThermalStandard")) == (120, 3)
    @test length(read_variables(res; table_format = TableFormat.WIDE)) == 4
    @test length(read_parameters(res; table_format = TableFormat.WIDE)) == 1
    @test length(read_duals(res; table_format = TableFormat.WIDE)) == 0
    @test length(read_expressions(res; table_format = TableFormat.WIDE)) == 2
    @test read_variables(
        res,
        ["StartVariable__ThermalStandard"];
        table_format = TableFormat.WIDE,
    )["StartVariable__ThermalStandard"] ==
          read_variable(
        res,
        "StartVariable__ThermalStandard";
        table_format = TableFormat.WIDE,
    )
    @test read_variables(
        res,
        [(StartVariable, ThermalStandard)];
        table_format = TableFormat.WIDE,
    )["StartVariable__ThermalStandard"] ==
          read_variable(
        res,
        StartVariable,
        ThermalStandard;
        table_format = TableFormat.WIDE,
    )
    @test read_parameters(
        res,
        ["ActivePowerTimeSeriesParameter__PowerLoad"];
        table_format = TableFormat.WIDE,
    )["ActivePowerTimeSeriesParameter__PowerLoad"] ==
          read_parameter(
        res,
        "ActivePowerTimeSeriesParameter__PowerLoad";
        table_format = TableFormat.WIDE,
    )
    @test read_parameters(
        res,
        [(ActivePowerTimeSeriesParameter, PowerLoad)];
        table_format = TableFormat.WIDE,
    )["ActivePowerTimeSeriesParameter__PowerLoad"] ==
          read_parameter(
        res,
        ActivePowerTimeSeriesParameter,
        PowerLoad;
        table_format = TableFormat.WIDE,
    )
    @test read_aux_variables(
        res,
        ["TimeDurationOff__ThermalStandard"];
        table_format = TableFormat.WIDE,
    )["TimeDurationOff__ThermalStandard"] ==
          read_aux_variable(
        res,
        "TimeDurationOff__ThermalStandard";
        table_format = TableFormat.WIDE,
    )
    @test read_aux_variables(
        res,
        [(TimeDurationOff, ThermalStandard)];
        table_format = TableFormat.WIDE,
    )["TimeDurationOff__ThermalStandard"] ==
          read_aux_variable(
        res,
        TimeDurationOff,
        ThermalStandard;
        table_format = TableFormat.WIDE,
    )
    @test read_expressions(
        res,
        ["ProductionCostExpression__ThermalStandard"];
        table_format = TableFormat.WIDE,
    )["ProductionCostExpression__ThermalStandard"] == read_expression(
        res,
        "ProductionCostExpression__ThermalStandard";
        table_format = TableFormat.WIDE,
    )
    @test read_expressions(
        res,
        [(ProductionCostExpression, ThermalStandard)];
        table_format = TableFormat.WIDE,
    )["ProductionCostExpression__ThermalStandard"] ==
          read_expression(
        res,
        ProductionCostExpression,
        ThermalStandard;
        table_format = TableFormat.WIDE,
    )
    @test length(read_aux_variables(res; table_format = TableFormat.WIDE)) == 2
    @test first(
        keys(
            read_aux_variables(
                res,
                [(TimeDurationOff, ThermalStandard)];
                table_format = TableFormat.WIDE,
            ),
        ),
    ) ==
          "TimeDurationOff__ThermalStandard"
    export_outputs(res)
    outputs_dir = joinpath(output_dir, "outputs")
    @test isfile(joinpath(outputs_dir, "optimizer_stats.csv"))
    variables_dir = joinpath(outputs_dir, "variables")
    @test isfile(joinpath(variables_dir, "ActivePowerVariable__ThermalStandard.csv"))
end

@testset "Test optimization debugging functions" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    container = IOM.get_optimization_container(model)
    MOIU.attach_optimizer(container.JuMPmodel)
    constraint_indices = get_all_constraint_index(model)
    for (key, index, moi_index) in constraint_indices
        val1 = get_constraint_index(model, moi_index)
        val2 = container.constraints[key].data[index]
        @test val1 == val2
    end
    @test get_constraint_index(model, length(constraint_indices) + 1) === nothing

    var_keys = IOM.get_all_variable_keys(model)
    var_index = get_all_variable_index(model)
    for (ix, (key, index, moi_index)) in enumerate(var_keys)
        index_tuple = var_index[ix]
        @test index_tuple[1] == IOM.encode_key(key)
        @test index_tuple[2] == index
        @test index_tuple[3] == moi_index
        val1 = get_variable_index(model, moi_index)
        val2 = container.variables[key].data[index]
        @test val1 == val2
    end
    @test get_variable_index(model, length(var_index) + 1) === nothing
end

@testset "Decision Model Solve with Slacks" begin
    c_sys5_re = PSB.build_system(PSITestSystems, "c_sys5_re")
    networks = [PTDFPowerModel, DCPPowerModel, ACPPowerModel]
    for network in networks
        template = get_thermal_dispatch_template_network(
            NetworkModel(network; use_slacks = true, PTDF_matrix = PTDF(c_sys5_re)),
        )
        model = DecisionModel(template, c_sys5_re; optimizer = ipopt_optimizer)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    end
end

@testset "Test OptimizationProblemOutputs interfaces" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_re")
    template = get_template_dispatch_with_network(
        NetworkModel(CopperPlatePowerModel; duals = [CopperPlateBalanceConstraint]),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemOutputs(model)
    container = IOM.get_optimization_container(model)
    constraint_key = IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System)
    constraints = IOM.get_constraints(container)[constraint_key]
    dual_outputs = IOM.read_duals(container)[constraint_key]
    dual_outputs_read = read_dual(res, constraint_key; table_format = TableFormat.WIDE)
    realized_dual_outputs =
        read_duals(res, [constraint_key]; table_format = TableFormat.WIDE)[IOM.encode_key_as_string(
            constraint_key,
        )]
    realized_dual_outputs_str =
        read_duals(
            res,
            [IOM.encode_key_as_string(constraint_key)];
            table_format = TableFormat.WIDE,
        )[IOM.encode_key_as_string(
            constraint_key,
        )]
    @test dual_outputs ==
          dual_outputs_read[:, propertynames(dual_outputs_read) .!= :DateTime] ==
          realized_dual_outputs[:, propertynames(realized_dual_outputs) .!= :DateTime] ==
          realized_dual_outputs_str[
              :,
              propertynames(realized_dual_outputs_str) .!= :DateTime,
          ]
    for i in axes(constraints)[1], j in axes(constraints)[2]
        dual = JuMP.dual(constraints[i, j])
        @test isapprox(dual, dual_outputs[j, 1])
    end

    system = IOM.get_system(model)
    parameter_key = IOM.ParameterKey(ActivePowerTimeSeriesParameter, PSY.PowerLoad)
    param_vals = IOM.read_parameters(container)[parameter_key]
    for load in get_components(PowerLoad, system)
        name = get_name(load)
        vals = get_time_series_values(Deterministic, load, "max_active_power")
        vals = vals .* get_max_active_power(load) * -1.0
        @test all(vals .== param_vals[name, :])
    end

    res = OptimizationProblemOutputs(model)
    @test length(list_variable_names(res)) == 1
    @test length(list_dual_names(res)) == 1
    @test get_model_base_power(res) == 100.0
    @test isa(get_objective_value(res), Float64)
    @test isa(res.variable_values, Dict{IOM.VariableKey, DataFrames.DataFrame})
    @test isa(
        read_variables(res; table_format = TableFormat.WIDE),
        Dict{String, DataFrames.DataFrame},
    )
    @test isa(IOM.get_total_cost(res), Float64)
    @test isa(get_optimizer_stats(res), DataFrames.DataFrame)
    @test isa(res.dual_values, Dict{IOM.ConstraintKey, DataFrames.DataFrame})
    @test isa(
        read_duals(res; table_format = TableFormat.WIDE),
        Dict{String, DataFrames.DataFrame},
    )
    @test isa(res.parameter_values, Dict{IOM.ParameterKey, DataFrames.DataFrame})
    @test isa(
        read_parameters(res; table_format = TableFormat.WIDE),
        Dict{String, DataFrames.DataFrame},
    )
    @test isa(IOM.get_resolution(res), Dates.TimePeriod)
    @test isa(IOM.get_forecast_horizon(res), Int64)
    @test isa(get_realized_timestamps(res), StepRange{DateTime})
    @test isa(IOM.get_source_data(res), PSY.System)
    @test length(get_timestamps(res)) == 24

    PSY.set_available!(first(get_components(ThermalStandard, sys)), false)
    # FIXME missing functions, get_groups and get_components on OptimizationProblemOutputs.
    #@test collect(get_components(ThermalStandard, res)) ==
    #      collect(get_available_components(ThermalStandard, get_system(res)))
    #sel = PSY.make_selector(ThermalStandard; groupby = :each)
    #@test collect(get_groups(sel, res)) ==
    #      collect(get_available_groups(sel, get_system(res)))
end

@testset "Solve DecisionModelModel with auto-build" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    UC = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test_throws ErrorException solve!(UC)
    @test solve!(UC; optimizer = HiGHS_optimizer, output_dir = output_dir) ==
          IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Test Serialization, deserialization and write optimizer problem" begin
    fpath = mktempdir(; cleanup = true)
    sys = PSB.build_system(PSITestSystems, "c_sys5_re")
    template = get_template_dispatch_with_network(
        NetworkModel(CopperPlatePowerModel; duals = [CopperPlateBalanceConstraint]),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = fpath) == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    file_list = sort!(collect(readdir(fpath)))
    model_name = IOM.get_name(model)
    @test IOM._JUMP_MODEL_FILENAME in file_list
    @test IOM._SERIALIZED_MODEL_FILENAME in file_list
    ED2 = DecisionModel(fpath, HiGHS_optimizer)
    @test build!(ED2; output_dir = fpath) == IOM.ModelBuildStatus.BUILT
    psi_checksolve_test(ED2, [MOI.OPTIMAL], 240000.0, 10000)

    path2 = mktempdir(; cleanup = true)
    model_no_sys =
        DecisionModel(template, sys; optimizer = HiGHS_optimizer, system_to_file = false)

    @test build!(model_no_sys; output_dir = path2) == IOM.ModelBuildStatus.BUILT
    @test solve!(model_no_sys) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    file_list = sort!(collect(readdir(path2)))
    @test !any(occursin.(r"\.h5$", file_list))
    ED3 = DecisionModel(path2, HiGHS_optimizer; system = sys)
    build!(ED3; output_dir = path2)
    psi_checksolve_test(ED3, [MOI.OPTIMAL], 240000.0, 10000)
end

@testset "Test NonSpinning reserve model" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5_uc_non_spin"; add_reserves = true)
    template = get_thermal_standard_uc_template()
    set_device_model!(
        template,
        DeviceModel(ThermalMultiStart, ThermalStandardUnitCommitment),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserveNonSpinning, NonSpinningReserve, "NonSpinningReserve"),
    )

    UC = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(UC; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(UC) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(UC)
    # This test needs to be reviewed
    # @test isapprox(get_objective_value(res), 256937.0; atol = 10000.0)
    vars = res.variable_values
    service_key = IOM.VariableKey(
        ActivePowerReserveVariable,
        PSY.VariableReserveNonSpinning,
        "NonSpinningReserve",
    )
    @test service_key in keys(vars)
end

@testset "Test serialization/deserialization of DecisionModel outputs" begin
    path = mktempdir(; cleanup = true)
    sys = PSB.build_system(PSITestSystems, "c_sys5_re")
    template = get_template_dispatch_with_network(
        NetworkModel(CopperPlatePowerModel; duals = [CopperPlateBalanceConstraint]),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = path) == IOM.ModelBuildStatus.BUILT
    @test solve!(model; export_problem_outputs = true) ==
          IOM.RunStatus.SUCCESSFULLY_FINALIZED
    outputs1 = OptimizationProblemOutputs(model)
    var1_a = read_variable(outputs1, ActivePowerVariable, ThermalStandard)
    # Ensure that we can deserialize strings into keys.
    var1_b = read_variable(outputs1, "ActivePowerVariable__ThermalStandard")

    # Results were automatically serialized here.
    outputs2 = OptimizationProblemOutputs(IOM.get_output_dir(model))
    var2 = read_variable(outputs2, ActivePowerVariable, ThermalStandard)
    @test var1_a == var2

    # Serialize to a new directory with the exported function.
    outputs_path = joinpath(path, "outputs")
    serialize_outputs(outputs1, outputs_path)
    @test isfile(joinpath(outputs_path, IOM._PROBLEM_OUTPUTS_FILENAME))
    outputs3 = OptimizationProblemOutputs(outputs_path)
    var3 = read_variable(outputs3, ActivePowerVariable, ThermalStandard)
    @test var1_a == var3
    @test get_source_data(outputs3) === nothing
    set_source_data!(outputs3, get_source_data(outputs1))
    @test get_source_data(outputs3) isa PSY.System

    exp_file =
        joinpath(path, "outputs", "variables", "ActivePowerVariable__ThermalStandard.csv")
    var4 = read_dataframe(exp_file)
    # Manually Multiply by the base power var1_a has natural units and export writes directly from the solver
    @test var1_a.value == var4.value .* 100.0

    @test length(readdir(IOM.export_realized_outputs(outputs1))) === 7
end

@testset "Test Numerical Stability of Constraints" begin
    template = get_thermal_dispatch_template_network()
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    valid_bounds =
        (coefficient = (min = 1.0, max = 1.0), rhs = (min = 0.4, max = 9.930296584))
    model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    bounds = IOM.get_constraint_numerical_bounds(model)
    _check_constraint_bounds(bounds, valid_bounds)

    model_bounds = IOM.get_detailed_constraint_numerical_bounds(model)
    valid_model_bounds = Dict(
        :CopperPlateBalanceConstraint__System => (
            coefficient = (min = 1.0, max = 1.0),
            rhs = (min = 6.434489705000001, max = 9.930296584),
        ),
        :ActivePowerVariableLimitsConstraint__ThermalStandard__lb =>
            (coefficient = (min = 1.0, max = 1.0), rhs = (min = Inf, max = -Inf)),
        :ActivePowerVariableLimitsConstraint__ThermalStandard__ub =>
            (coefficient = (min = 1.0, max = 1.0), rhs = (min = 0.4, max = 6.0)),
    )
    for (constraint_key, constraint_bounds) in model_bounds
        _check_constraint_bounds(
            constraint_bounds,
            valid_model_bounds[IOM.encode_key(constraint_key)],
        )
    end
end

@testset "Test Numerical Stability of Variables" begin
    template = get_template_basic_uc_simulation()
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5_uc")
    valid_bounds = (min = 0.0, max = 6.0)
    model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    bounds = IOM.get_variable_numerical_bounds(model)
    _check_variable_bounds(bounds, valid_bounds)

    model_bounds = IOM.get_detailed_variable_numerical_bounds(model)
    valid_model_bounds = Dict(
        :StopVariable__ThermalStandard => (min = 0.0, max = 1.0),
        :StartVariable__ThermalStandard => (min = 0.0, max = 1.0),
        :ActivePowerVariable__ThermalStandard => (min = 0.4, max = 6.0),
        :OnVariable__ThermalStandard => (min = 0.0, max = 1.0),
    )
    for (variable_key, variable_bounds) in model_bounds
        _check_variable_bounds(
            variable_bounds,
            valid_model_bounds[IOM.encode_key(variable_key)],
        )
    end
end

@testset "Decision Model initial_conditions test for ThermalGen" begin
    ######## Test with ThermalStandardUnitCommitment ########
    template = get_thermal_standard_uc_template()
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_pglib"; force_build = true)
    set_device_model!(template, ThermalMultiStart, ThermalStandardUnitCommitment)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    check_duration_on_initial_conditions_values(model, ThermalStandard)
    check_duration_off_initial_conditions_values(model, ThermalStandard)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    ######## Test with ThermalMultiStartUnitCommitment ########
    template = get_thermal_standard_uc_template()
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_pglib"; force_build = true)
    set_device_model!(template, ThermalMultiStart, ThermalMultiStartUnitCommitment)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    check_duration_on_initial_conditions_values(model, ThermalStandard)
    check_duration_off_initial_conditions_values(model, ThermalStandard)
    check_duration_on_initial_conditions_values(model, ThermalMultiStart)
    check_duration_off_initial_conditions_values(model, ThermalMultiStart)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    ######## Test with ThermalStandardUnitCommitment ########
    template = get_thermal_standard_uc_template()
    c_sys5_uc = PSB.build_system(PSITestSystems, "c_sys5_pglib"; force_build = true)
    set_device_model!(template, ThermalMultiStart, ThermalStandardUnitCommitment)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    model = DecisionModel(template, c_sys5_uc; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    check_duration_on_initial_conditions_values(model, ThermalStandard)
    check_duration_off_initial_conditions_values(model, ThermalStandard)
    check_duration_on_initial_conditions_values(model, ThermalMultiStart)
    check_duration_off_initial_conditions_values(model, ThermalMultiStart)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Decision Model initial_conditions test for Hydro" begin
    ######## Test with HydroDispatchRunOfRiver ########
    template = get_thermal_dispatch_template_network()
    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hyd"; force_build = true)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyDispatch)
    set_device_model!(template, HydroReservoir, HydroEnergyModelReservoir)
    model = DecisionModel(template, c_sys5_hyd; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    @test !IOM.has_initial_condition_value(
        initial_conditions_data,
        ActivePowerVariable(),
        HydroTurbine,
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    ######## Test with HydroCommitmentRunOfRiver ########
    template = get_thermal_dispatch_template_network()
    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hyd"; force_build = true)
    set_device_model!(template, HydroDispatch, HydroCommitmentRunOfRiver)
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyCommitment)
    set_device_model!(template, HydroReservoir, HydroEnergyModelReservoir)
    model = DecisionModel(template, c_sys5_hyd; optimizer = HiGHS_optimizer)

    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    @test IOM.has_initial_condition_value(
        initial_conditions_data,
        OnVariable(),
        HydroTurbine,
    )
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Test serialization of InitialConditionsData" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    optimizer = HiGHS_optimizer

    # Construct and build with default behavior that builds initial conditions.
    model = DecisionModel(template, sys; optimizer = optimizer)
    output_dir = mktempdir(; cleanup = true)

    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    ic_file = IOM.get_initial_conditions_file(model)
    test_ic_serialization_outputs(model; ic_file_exists = true, message = "make")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # Build again. Initial conditions should be rebuilt.
    POM.reset!(model)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    test_ic_serialization_outputs(model; ic_file_exists = true, message = "make")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # Build again, use existing initial conditions.
    model = DecisionModel(
        template,
        sys;
        optimizer = optimizer,
        deserialize_initial_conditions = true,
    )
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    test_ic_serialization_outputs(model; ic_file_exists = true, message = "deserialize")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # Construct and build again with custom initial conditions file.
    initialization_file = joinpath(output_dir, ic_file * ".old")
    mv(ic_file, initialization_file)
    touch(ic_file)
    model = DecisionModel(
        template,
        sys;
        optimizer = optimizer,
        initialization_file = initialization_file,
        deserialize_initial_conditions = true,
    )
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    test_ic_serialization_outputs(model; ic_file_exists = true, message = "deserialize")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # Construct and build again while skipping build of initial conditions.
    rm(ic_file)
    model = DecisionModel(template, sys; optimizer = optimizer, initialize_model = false)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    test_ic_serialization_outputs(model; ic_file_exists = false, message = "skip")
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    # Conflicting inputs
    model = DecisionModel(
        template,
        sys;
        optimizer = optimizer,
        initialize_model = false,
        deserialize_initial_conditions = true,
    )
    @test build!(model; output_dir = output_dir, console_level = Logging.AboveMaxLevel) ==
          IOM.ModelBuildStatus.FAILED
    model = DecisionModel(
        template,
        sys;
        optimizer = optimizer,
        initialize_model = false,
        initialization_file = "init_file.bin",
    )
    @test build!(model; output_dir = output_dir, console_level = Logging.AboveMaxLevel) ==
          IOM.ModelBuildStatus.FAILED
end

@testset "Solve with detailed optimizer stats" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    UC = DecisionModel(
        template,
        c_sys5;
        optimizer = HiGHS_optimizer,
        detailed_optimizer_stats = true,
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(UC; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(UC) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    # We only test this field because most free solvers don't support detailed stats
    @test !ismissing(get_optimizer_stats(UC).objective_bound)
end

@testset "Test filter function attribute" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    template = get_thermal_standard_uc_template()
    new_model = DeviceModel(
        ThermalStandard,
        ThermalBasicUnitCommitment;
        attributes = Dict("filter_function" => x -> PSY.get_name(x) != "Alta"),
    )
    set_device_model!(template, new_model)
    UC = DecisionModel(
        template,
        c_sys5;
        optimizer = HiGHS_optimizer,
        detailed_optimizer_stats = true,
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(UC; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(UC) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    # We only test this field because most free solvers don't support detailed stats
    p_variable = IOM.get_variable(
        IOM.get_optimization_container(UC),
        ActivePowerVariable(),
        ThermalStandard,
    )
    @test "Alta" ∉ axes(p_variable, 1)
end

@testset "Test for isolated buses" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    add_component!(c_sys5,
        ACBus(
            10,
            "node_none",
            true,
            "ISOLATED",
            0,
            1.0,
            (min = 0.9, max = 1.05),
            230,
            nothing,
            nothing,
        ),
    )

    template = get_thermal_standard_uc_template()
    new_model = DeviceModel(
        ThermalStandard,
        ThermalBasicUnitCommitment;
    )
    set_device_model!(template, new_model)
    UC = DecisionModel(
        template,
        c_sys5;
        optimizer = HiGHS_optimizer,
        detailed_optimizer_stats = true,
    )
    output_dir = mktempdir(; cleanup = true)
    @test build!(UC; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(UC) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Test for single row output variables" begin
    template = get_thermal_dispatch_template_network()
    c_sys5_bat = PSB.build_system(PSITestSystems, "c_sys5_bat_ems"; force_build = true)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    set_device_model!(template, device_model)
    output_dir = mktempdir(; cleanup = true)
    model = DecisionModel(
        template,
        c_sys5_bat;
        optimizer = HiGHS_optimizer,
    )
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(model)
    shortage = read_variable(res, "StorageEnergyShortageVariable__EnergyReservoirStorage")
    @test nrow(shortage) == 1
end

@testset "solve! with auto-build does not forward unknown kwargs to build!" begin
    # Regression test: solve! accepts kwargs... and forwards them to
    # build_if_not_already_built! → build!. Extra kwargs (like optimizer) must be
    # filtered before reaching build!, which has explicit keyword arguments.
    template = get_thermal_dispatch_template_network()
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test solve!(
        model;
        output_dir = output_dir,
        optimizer = HiGHS_optimizer,
    ) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end
