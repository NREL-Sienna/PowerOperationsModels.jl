sys_rts = PSB.build_system(PSISystems, "modified_RTS_GMLC_DA_sys")

# we only do a single timestep because multi time step stuff is the domain of PSI.
@testset "Initialization with ThermalStandardUnitCommitment" begin
    template = ProblemTemplate(CopperPlatePowerModel)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

    model = DecisionModel(
        template,
        sys_rts;
        optimizer = HiGHS_optimizer,
        initial_time = DateTime("2020-01-01T00:00:00"),
        horizon = Hour(48),
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    ####### Check initialization problem
    check_initialization_variable_count(model, ActivePowerVariable(), ThermalStandard)
    check_initialization_variable_count(model, OnVariable(), ThermalStandard)
    check_initialization_variable_count(model, StopVariable(), ThermalStandard)
    check_initialization_variable_count(model, StartVariable(), ThermalStandard)
    check_initialization_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_initialization_variable_count(model, ActivePowerVariable(), HydroDispatch)
    ####### Check initial condition from initialization step
    check_duration_on_initial_conditions_values(model, ThermalStandard)
    check_duration_off_initial_conditions_values(model, ThermalStandard)
    check_active_power_initial_condition_values(model, ThermalStandard)
    check_status_initial_conditions_values(model, ThermalStandard)
    ####### Check variables
    check_variable_count(model, ActivePowerVariable(), ThermalStandard)
    check_variable_count(model, StopVariable(), ThermalStandard)
    check_variable_count(model, OnVariable(), ThermalStandard)
    check_variable_count(model, StartVariable(), ThermalStandard)
    check_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_variable_count(model, ActivePowerVariable(), HydroDispatch)
    ####### Check constraints
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "lb",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "ub",
    )
    check_constraint_count(model, DurationConstraint(), ThermalStandard)
    check_constraint_count(model, RampConstraint(), ThermalStandard)
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard)
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard; meta = "aux")
    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )
    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        RenewableDispatch;
        meta = "ub",
    )

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Initialization with HydroCommitmentRunOfRiver" begin
    template = ProblemTemplate(CopperPlatePowerModel)
    set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, HydroDispatch, HydroCommitmentRunOfRiver)

    model = DecisionModel(
        template,
        sys_rts;
        optimizer = HiGHS_optimizer,
        initial_time = DateTime("2020-01-01T00:00:00"),
        horizon = Hour(48),
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    ####### Check initialization problem
    check_initialization_variable_count(model, ActivePowerVariable(), ThermalStandard)
    check_initialization_variable_count(model, OnVariable(), ThermalStandard)
    check_initialization_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_initialization_variable_count(model, ActivePowerVariable(), HydroDispatch)
    ####### Check initial condition from initialization step
    check_status_initial_conditions_values(model, ThermalStandard)

    ####### Check variables
    check_variable_count(model, ActivePowerVariable(), ThermalStandard)
    check_variable_count(model, StopVariable(), ThermalStandard)
    check_variable_count(model, OnVariable(), ThermalStandard)
    check_variable_count(model, StartVariable(), ThermalStandard)
    check_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_variable_count(model, ActivePowerVariable(), HydroDispatch)
    check_variable_count(model, OnVariable(), HydroDispatch)
    ####### Check constraints
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "lb",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "ub",
    )
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard)
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard; meta = "aux")

    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        RenewableDispatch;
        meta = "ub",
    )
    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "lb",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Initialization with ThermalCompactUnitCommitment" begin
    template = ProblemTemplate(CopperPlatePowerModel)
    set_device_model!(template, ThermalStandard, ThermalCompactUnitCommitment)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

    model = DecisionModel(
        template,
        sys_rts;
        optimizer = HiGHS_optimizer,
        initial_time = DateTime("2020-01-01T00:00:00"),
        horizon = Hour(48),
    )
    POM.instantiate_network_model!(model)
    POM.build_pre_step!(model)
    setup_ic_model_container!(model)
    ####### Check initialization problem constraints #####
    check_initialization_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "lb",
    )
    check_initialization_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "ub",
    )
    check_initialization_constraint_count(
        model,
        CommitmentConstraint(),
        ThermalStandard,
    )
    check_initialization_constraint_count(
        model,
        CommitmentConstraint(),
        ThermalStandard;
        meta = "aux",
    )
    check_initialization_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        RenewableDispatch;
        meta = "ub",
    )
    check_initialization_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "lb",
    )
    check_initialization_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )
    check_initialization_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )
    POM.reset!(model)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    ####### Check initialization problem
    check_initialization_variable_count(
        model,
        PowerAboveMinimumVariable(),
        ThermalStandard,
    )
    check_initialization_variable_count(model, OnVariable(), ThermalStandard)
    check_initialization_variable_count(model, StopVariable(), ThermalStandard)
    check_initialization_variable_count(model, StartVariable(), ThermalStandard)
    check_initialization_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_initialization_variable_count(model, ActivePowerVariable(), HydroDispatch)

    ####### Check initial condition from initialization step
    check_duration_on_initial_conditions_values(model, ThermalStandard)
    check_duration_off_initial_conditions_values(model, ThermalStandard)
    check_active_power_abovemin_initial_condition_values(model, ThermalStandard)
    check_status_initial_conditions_values(model, ThermalStandard)

    ####### Check variables
    check_variable_count(model, PowerAboveMinimumVariable(), ThermalStandard)
    check_variable_count(model, OnVariable(), ThermalStandard)
    check_variable_count(model, StopVariable(), ThermalStandard)
    check_variable_count(model, StartVariable(), ThermalStandard)
    check_variable_count(model, ActivePowerVariable(), RenewableDispatch)
    check_variable_count(model, ActivePowerVariable(), HydroDispatch)

    ####### Check constraints
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "lb",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        ThermalStandard;
        meta = "ub",
    )
    check_constraint_count(model, RampConstraint(), ThermalStandard)
    check_constraint_count(model, DurationConstraint(), ThermalStandard)
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard)
    check_constraint_count(model, CommitmentConstraint(), ThermalStandard; meta = "aux")
    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        RenewableDispatch;
        meta = "ub",
    )
    check_constraint_count(
        model,
        ActivePowerVariableTimeSeriesLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "lb",
    )
    check_constraint_count(
        model,
        ActivePowerVariableLimitsConstraint(),
        HydroDispatch;
        meta = "ub",
    )

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end
