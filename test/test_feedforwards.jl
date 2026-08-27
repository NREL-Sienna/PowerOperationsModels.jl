#################################################################################
# Device-side feedforward construction.
#
# These assert the built JuMP objects, not just their counts: every multiplier
# below is an independently hand-computable number taken from PSY data, so a
# silently wrong `get_expression_multiplier` / `get_parameter_multiplier` shows up
# as a coefficient mismatch rather than an unchanged constraint total.
#
# Populating the feedforward parameters between executions lives in
# PowerSimulations; here the parameters are only read.
#################################################################################

"""
Active power limits, system base, keyed by device name — the independent reference
the coefficient assertions below are checked against.
"""
function _ff_limits(sys)
    return Dict(
        PSY.get_name(d) => PSY.get_active_power_limits(d, PSY.SU) for
        d in PSY.get_components(PSY.ThermalStandard, sys)
    )
end

@testset "UpperBoundFeedforward on ThermalStandard: constraint coefficients" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_ub = UpperBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_ub)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)

    container = IOM.get_optimization_container(model)
    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardUpperBoundConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)ub",
        ),
    )
    var = IOM.get_variable(container, ActivePowerVariable, PSY.ThermalStandard)
    param = IOM.get_parameter_array(
        container,
        UpperBoundValueParameter,
        PSY.ThermalStandard,
    )
    mult = IOM.get_parameter_multiplier_array(
        container,
        UpperBoundValueParameter,
        PSY.ThermalStandard,
    )

    names, time_steps = JuMP.axes(var)
    @test !isempty(names)
    for name in names, t in time_steps
        # `get_parameter_multiplier(<:VariableValueParameter, ::ThermalGen, ...) = 1.0`
        @test mult[name, t] == 1.0
        con = con_ub[name, t]
        # p[n, t] - 1.0 * param[n, t] <= 0
        @test JuMP.normalized_coefficient(con, var[name, t]) == 1.0
        @test JuMP.normalized_coefficient(con, param[name, t]) == -1.0
        @test JuMP.normalized_rhs(con) == 0.0
        @test JuMP.constraint_object(con).set isa MOI.LessThan
    end
end

@testset "UpperBoundFeedforward slacks are wired in and penalized" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_ub = UpperBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
        add_slacks = true,
    )
    attach_feedforward!(device_model, ff_ub)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)

    container = IOM.get_optimization_container(model)
    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardUpperBoundConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)ub",
        ),
    )
    slack = IOM.get_variable(
        container,
        UpperBoundFeedForwardSlack,
        PSY.ThermalStandard,
        "$(ActivePowerVariable)",
    )
    names, time_steps = JuMP.axes(slack)
    for name in names, t in time_steps
        # p[n, t] - slack[n, t] - param[n, t] <= 0
        @test JuMP.normalized_coefficient(con_ub[name, t], slack[name, t]) == -1.0
        @test JuMP.lower_bound(slack[name, t]) == 0.0
    end

    # An unpenalized slack would make the bound vacuous; assert the objective cost.
    obj = JuMP.objective_function(IOM.get_jump_model(container))
    for name in names, t in time_steps
        @test get(obj.terms, slack[name, t], 0.0) == POM.BALANCE_SLACK_COST
    end
end

@testset "LowerBoundFeedforward on ThermalStandard: constraint coefficients" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_lb = LowerBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_lb)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)

    container = IOM.get_optimization_container(model)
    con_lb = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardLowerBoundConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)lb",
        ),
    )
    var = IOM.get_variable(container, ActivePowerVariable, PSY.ThermalStandard)
    param = IOM.get_parameter_array(
        container,
        LowerBoundValueParameter,
        PSY.ThermalStandard,
    )

    names, time_steps = JuMP.axes(var)
    for name in names, t in time_steps
        con = con_lb[name, t]
        # p[n, t] - 1.0 * param[n, t] >= 0
        @test JuMP.normalized_coefficient(con, var[name, t]) == 1.0
        @test JuMP.normalized_coefficient(con, param[name, t]) == -1.0
        @test JuMP.constraint_object(con).set isa MOI.GreaterThan
    end
end

@testset "SemiContinuousFeedforward on ThermalStandardDispatch: expression coefficients" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_sc = SemiContinuousFeedforward(;
        component_type = PSY.ThermalStandard,
        source = OnVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_sc)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    limits = _ff_limits(c_sys5)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)

    container = IOM.get_optimization_container(model)
    param = IOM.get_parameter_array(container, OnStatusParameter, PSY.ThermalStandard)
    var = IOM.get_variable(container, ActivePowerVariable, PSY.ThermalStandard)
    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardSemiContinuousConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)_ub",
        ),
    )
    con_lb = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardSemiContinuousConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)_lb",
        ),
    )

    names, time_steps = JuMP.axes(var)
    for name in names
        # `get_expression_multiplier(OnStatusParameter, ActivePowerRangeExpressionUB,
        #  ::ThermalGen, <:AbstractThermalFormulation) = active_power_limits.max`
        max_limit = limits[name].max
        min_limit = limits[name].min
        for t in time_steps
            # UB: p[n, t] - max * u[n, t] <= 0
            @test JuMP.normalized_coefficient(con_ub[name, t], var[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_ub[name, t], param[name, t]) ≈ -max_limit
            @test JuMP.normalized_rhs(con_ub[name, t]) == 0.0
            # LB: p[n, t] - min * u[n, t] >= 0
            @test JuMP.normalized_coefficient(con_lb[name, t], var[name, t]) == 1.0
            @test JuMP.normalized_coefficient(con_lb[name, t], param[name, t]) ≈ -min_limit
            @test JuMP.normalized_rhs(con_lb[name, t]) == 0.0
        end
        # A positive variable lower bound would fight the semicontinuous LB constraint.
        @test all(
            !JuMP.has_lower_bound(var[name, t]) || JuMP.lower_bound(var[name, t]) == 0.0
            for t in time_steps
        )
    end
end

@testset "SemiContinuousFeedforward on ThermalCompactDispatch: native range constraints are suppressed" begin
    ff_sc = SemiContinuousFeedforward(;
        component_type = PSY.ThermalStandard,
        source = OnVariable,
        affected_values = [PowerAboveMinimumVariable],
    )

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    limits = _ff_limits(c_sys5)

    # Without the feedforward the formulation builds its own range constraints.
    plain_model = DeviceModel(PSY.ThermalStandard, ThermalCompactDispatch)
    plain = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(plain, plain_model; built_for_recurrent_solves = true)
    plain_container = IOM.get_optimization_container(plain)
    @test IOM.has_container_key(
        plain_container,
        ActivePowerVariableLimitsConstraint,
        PSY.ThermalStandard,
        "ub",
    )

    # With it, the semicontinuous constraints replace them. This is the case the
    # generic `AbstractThermalDispatchFormulation` gate gets wrong: it resolves the
    # affected value to `ActivePowerVariable`, not `PowerAboveMinimumVariable`, so
    # without the compact-specific method both sets of bounds would be built.
    device_model = DeviceModel(PSY.ThermalStandard, ThermalCompactDispatch)
    attach_feedforward!(device_model, ff_sc)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)
    container = IOM.get_optimization_container(model)

    @test !IOM.has_container_key(
        container,
        ActivePowerVariableLimitsConstraint,
        PSY.ThermalStandard,
        "ub",
    )
    @test !IOM.has_container_key(
        container,
        ActivePowerVariableLimitsConstraint,
        PSY.ThermalStandard,
        "lb",
    )

    param = IOM.get_parameter_array(container, OnStatusParameter, PSY.ThermalStandard)
    var = IOM.get_variable(container, PowerAboveMinimumVariable, PSY.ThermalStandard)
    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardSemiContinuousConstraint,
            PSY.ThermalStandard,
            "$(PowerAboveMinimumVariable)_ub",
        ),
    )
    names, time_steps = JuMP.axes(var)
    for name in names, t in time_steps
        # Compact dispatch schedules power above minimum, so the UB multiplier is the
        # band width `max - min`, not `max`.
        band = limits[name].max - limits[name].min
        @test JuMP.normalized_coefficient(con_ub[name, t], var[name, t]) == 1.0
        @test JuMP.normalized_coefficient(con_ub[name, t], param[name, t]) ≈ -band
    end
end

@testset "SemiContinuousFeedforward skips must-run thermal units" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    must_run_unit = first(PSY.get_components(PSY.ThermalStandard, c_sys5))
    must_run_name = PSY.get_name(must_run_unit)
    PSY.set_must_run!(must_run_unit, true)

    # `ThermalBasicDispatch` has no ramp constraints; see the broken testset below for
    # why `ThermalStandardDispatch` cannot be used here yet.
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicDispatch)
    ff_sc = SemiContinuousFeedforward(;
        component_type = PSY.ThermalStandard,
        source = OnVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_sc)

    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)
    container = IOM.get_optimization_container(model)

    # A must-run unit is never turned off, so POM leaves it out of the
    # `OnStatusParameter` container entirely (`add_parameters.jl`) and the
    # semicontinuous constraints skip it.
    param = IOM.get_parameter_array(container, OnStatusParameter, PSY.ThermalStandard)
    @test must_run_name ∉ JuMP.axes(param)[1]

    con_ub = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardSemiContinuousConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)_ub",
        ),
    )
    time_steps = JuMP.axes(con_ub)[2]
    ix = con_ub.lookup[1][must_run_name]
    for t in time_steps
        @test !isassigned(con_ub.data, ix, t)
    end

    PSY.set_must_run!(must_run_unit, false)
end

# KNOWN DEFECT (needs an IOM fix, tracked in the port notes):
# POM excludes must-run units from the `OnStatusParameter` container, but IOM's
# `add_linear_ramp_constraints!` OnStatusParameter branch
# (`common_models/rateofchange_constraints.jl`) indexes `on_status[name, t]` for every
# ramp device, so a must-run unit throws `KeyError`. That branch was unreachable while
# feedforwards were stubbed out, since `OnStatusParameter` only enters a dispatch model
# through a `SemiContinuousFeedforward`. The fix is in IOM: treat a name missing from
# the parameter container as a constant status of 1.0.
@testset "must-run unit under SemiContinuousFeedforward with ramp constraints" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    must_run_unit = first(PSY.get_components(PSY.ThermalStandard, c_sys5))
    PSY.set_must_run!(must_run_unit, true)

    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_sc = SemiContinuousFeedforward(;
        component_type = PSY.ThermalStandard,
        source = OnVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_sc)
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)

    built = try
        mock_construct_device!(model, device_model; built_for_recurrent_solves = true)
        true
    catch
        false
    end
    @test_broken built

    PSY.set_must_run!(must_run_unit, false)
end

@testset "FixValueFeedforward pins the affected variable to the parameter" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_fix = FixValueFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff_fix)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    mock_construct_device!(model, device_model; built_for_recurrent_solves = true)

    container = IOM.get_optimization_container(model)
    var = IOM.get_variable(container, ActivePowerVariable, PSY.ThermalStandard)
    param = IOM.get_parameter_array(
        container,
        FixValueParameter,
        PSY.ThermalStandard,
        "$(ActivePowerVariable)",
    )
    mult = IOM.get_parameter_multiplier_array(
        container,
        FixValueParameter,
        PSY.ThermalStandard,
        "$(ActivePowerVariable)",
    )
    con = IOM.get_constraint(
        container,
        IOM.ConstraintKey(
            FeedforwardFixValueConstraint,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)",
        ),
    )

    names, time_steps = JuMP.axes(var)
    for name in names, t in time_steps
        # p[n, t] - mult * param[n, t] == 0
        @test mult[name, t] == 1.0
        @test JuMP.normalized_coefficient(con[name, t], var[name, t]) == 1.0
        @test JuMP.normalized_coefficient(con[name, t], param[name, t]) ≈ -mult[name, t]
        @test JuMP.normalized_rhs(con[name, t]) == 0.0
        @test JuMP.constraint_object(con[name, t]).set isa MOI.EqualTo
    end

    # The update step in PowerSimulations re-populates the parameter through these keys.
    attrs = IOM.get_parameter_attributes(
        container,
        IOM.ParameterKey(
            FixValueParameter,
            PSY.ThermalStandard,
            "$(ActivePowerVariable)",
        ),
    )
    @test IOM.VariableKey(ActivePowerVariable, PSY.ThermalStandard) ∈ attrs.affected_keys
end

@testset "attach_feedforward! is idempotent and rejects ServiceModel" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff = UpperBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
    )
    attach_feedforward!(device_model, ff)
    attach_feedforward!(device_model, ff)
    @test length(IOM.get_feedforwards(device_model)) == 1

    service_model = ServiceModel(OnlineReserve{ReserveUp}, RangeReserve)
    @test_throws ErrorException attach_feedforward!(service_model, ff)
end

@testset "has_semicontinuous_feedforward checks every attached feedforward" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalCompactDispatch)
    # Two semicontinuous feedforwards with distinct source keys, the one affecting
    # PowerAboveMinimumVariable attached second.
    attach_feedforward!(
        device_model,
        SemiContinuousFeedforward(;
            component_type = PSY.ThermalStandard,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
            meta = "other",
        ),
    )
    attach_feedforward!(
        device_model,
        SemiContinuousFeedforward(;
            component_type = PSY.ThermalStandard,
            source = OnVariable,
            affected_values = [PowerAboveMinimumVariable],
        ),
    )
    @test length(IOM.get_feedforwards(device_model)) == 2
    # Inspecting only the first would miss this and double-constrain the unit.
    @test POM.has_semicontinuous_feedforward(device_model, PowerAboveMinimumVariable)
    @test POM.has_semicontinuous_feedforward(device_model, ActivePowerVariable)
end

@testset "FixValueFeedforward rejects a parameter target on a DeviceModel" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalStandardDispatch)
    ff_fix = FixValueFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerTimeSeriesParameter],
    )
    attach_feedforward!(device_model, ff_fix)

    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5)
    # Readable error rather than a `get_variable` MethodError.
    @test_throws ErrorException mock_construct_device!(
        model,
        device_model;
        built_for_recurrent_solves = true,
    )
end

@testset "Feedforwards reject non-variable affected values" begin
    @test_throws ErrorException UpperBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [OnStatusParameter],
    )
    @test_throws ErrorException SemiContinuousFeedforward(;
        component_type = PSY.ThermalStandard,
        source = OnVariable,
        affected_values = [OnStatusParameter],
    )
end
