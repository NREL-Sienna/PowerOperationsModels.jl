#########################################
#### RESERVOIR BUDGET DISPATCH TESTS ####
#########################################
@testset "Hydro DCPLossLess with HydroTurbineEnergyDispatch and HydroEnergyModelReservoir (with budget) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        attributes = Dict{String, Any}(
            "energy_target" => false,
            "hydro_budget" => true,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 120, 0, 25, 24, 24, false)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "Hydro ACPNetworkModel with HydroTurbineEnergyDispatch and HydroEnergyModelReservoir (with budget) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        use_slacks = true,
        attributes = Dict{String, Any}(
            "energy_target" => false,
            "hydro_budget" => true,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 192, 0, 49, 48, 24, false)
    psi_checkobjfun_test(model, GAEVF)
end

###########################################
#### RESERVOIR BUDGET COMMITMENT TESTS ####
###########################################

@testset "Hydro DCPLossLess with HydroTurbineEnergyCommitment and HydroEnergyModelReservoir (with budget) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyCommitment)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        attributes = Dict{String, Any}(
            "energy_target" => false,
            "hydro_budget" => true,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 144, 0, 25, 24, 24, true)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "Hydro ACPNetworkModel with HydroTurbineEnergyCommitment and HydroEnergyModelReservoir (with budget) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyCommitment)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        attributes = Dict{String, Any}(
            "energy_target" => false,
            "hydro_budget" => true,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 168, 0, 49, 48, 24, true)
    psi_checkobjfun_test(model, GAEVF)
end

#########################################
#### RESERVOIR TARGET DISPATCH TESTS ####
#########################################

@testset "Hydro DCPLossLess with HydroTurbineEnergyDispatch and HydroEnergyModelReservoir (with target) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        attributes = Dict{String, Any}(
            "energy_target" => true,
            "hydro_budget" => false,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, DCPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 120, 0, 24, 24, 25, false)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "Hydro ACPNetworkModel with HydroTurbineEnergyDispatch and HydroEnergyModelReservoir (with target) Formulations" begin
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        attributes = Dict{String, Any}(
            "energy_target" => true,
            "hydro_budget" => false,
        ),
    )

    c_sys5_hyd = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")

    # No Parameters Testing
    model = DecisionModel(MockOperationProblem, ACPNetworkModel, c_sys5_hyd)
    mock_construct_device!(model, turbine_model)
    mock_construct_device!(model, reservoir_model)
    moi_tests(model, 144, 0, 48, 48, 25, false)
    psi_checkobjfun_test(model, GAEVF)
end

#########################################
########### RUN OF RIVER TESTS ##########
#########################################

@testset "Solving ED Hydro System using Dispatch Run of River" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy")
    networks = [ACPNetworkModel, DCPNetworkModel]

    test_outputs =
        Dict{Any, Float64}(ACPNetworkModel => 136581.41, DCPNetworkModel => 135382.37)

    for net in networks
        @testset "HydroRoR ED model $(net)" begin
            template = get_thermal_dispatch_template_network(net)
            set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
            ED = DecisionModel(
                EconomicDispatchProblem,
                template,
                sys;
                optimizer = ipopt_optimizer,
            )
            @test build!(ED; output_dir = mktempdir(; cleanup = true)) ==
                  ModelBuildStatus.BUILT
            psi_checksolve_test(
                ED,
                [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
                test_outputs[net],
                1000,
            )
        end
    end
end

@testset "Solving ED Hydro System using Commitment Run of River" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy")
    net = CopperPlateNetworkModel

    template = get_thermal_dispatch_template_network(net)
    set_device_model!(template, HydroDispatch, HydroCommitmentRunOfRiver)

    @testset "HydroRoR ED model $(net)" begin
        ED =
            DecisionModel(UnitCommitmentProblem, template, sys; optimizer = HiGHS_optimizer)
        @test build!(ED; output_dir = mktempdir(; cleanup = true)) ==
              ModelBuildStatus.BUILT
        psi_checksolve_test(ED, [MOI.OPTIMAL, MOI.LOCALLY_SOLVED], 135382.38, 1000)
    end
end

# currently broken due to PSB lagging behind.
@testset "Test Reserves from Hydro with RunOfRiver" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, HydroTurbine, HydroDispatchRunOfRiver)
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(ReserveDemandCurve{ReserveUp}, StepwiseCostReserve),
    )

    c_sys5_hyd = PSB.build_system(
        PSITestSystems,
        "c_sys5_hyd";
        add_reserves = true,
        force_build = true,
    )
    model = DecisionModel(template, c_sys5_hyd)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          ModelBuildStatus.BUILT
    # The value of this test needs to be revised
    # moi_tests(model, 240, 0, 48, 96, 72, false)
end

#########################################
###### RESERVOIR SYSTEM TESTS ###########
#########################################

@testset "Solving ED Hydro System using Dispatch with Reservoir" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")
    networks = [ACPNetworkModel, DCPNetworkModel]
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyDispatch)
    models = [
        DeviceModel(
            HydroReservoir,
            HydroEnergyModelReservoir;
            attributes = Dict{String, Any}(
                "energy_target" => true,
                "hydro_budget" => false,
            ),
        ),
        DeviceModel(
            HydroReservoir,
            HydroEnergyModelReservoir;
            attributes = Dict{String, Any}(
                "energy_target" => false,
                "hydro_budget" => true,
            ),
        ),
    ]
    test_outputs = Dict{Any, Float64}(
        (ACPNetworkModel, HydroEnergyModelReservoir, true) => 136296.0,
        (DCPNetworkModel, HydroEnergyModelReservoir, true) => 135404.0,
        (ACPNetworkModel, HydroEnergyModelReservoir, false) => 131305.0,
        (DCPNetworkModel, HydroEnergyModelReservoir, false) => 130479.0,
    )

    for net in networks
        for reservoir_model in models
            formulation = get_formulation(reservoir_model)
            attrs = IOM.get_attributes(reservoir_model)
            energy_target = get(attrs, "energy_target", false)
            hydro_budget = get(attrs, "hydro_budget", false)
            @testset "$(formulation) with energy_target: $energy_target, and hydro_budget: $hydro_budget, ED model on $(net)" begin
                template = get_thermal_dispatch_template_network(net)
                set_device_model!(template, turbine_model)
                set_device_model!(template, reservoir_model)

                ED = DecisionModel(
                    EconomicDispatchProblem,
                    template,
                    sys;
                    optimizer = ipopt_optimizer,
                )
                @test build!(ED; output_dir = mktempdir(; cleanup = true)) ==
                      ModelBuildStatus.BUILT
                psi_checksolve_test(
                    ED,
                    [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
                    test_outputs[(net, formulation, energy_target)],
                    1000,
                )
            end
        end
    end
end

@testset "Solving ED Hydro System using Commitment with Reservoir" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")
    net = DCPNetworkModel
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineEnergyCommitment)
    models = [
        DeviceModel(
            HydroReservoir,
            HydroEnergyModelReservoir;
            attributes = Dict{String, Any}(
                "energy_target" => true,
                "hydro_budget" => false,
            ),
        ),
        DeviceModel(
            HydroReservoir,
            HydroEnergyModelReservoir;
            attributes = Dict{String, Any}(
                "energy_target" => false,
                "hydro_budget" => true,
            ),
        ),
    ]
    test_outputs = Dict{Any, Float64}(
        (DCPNetworkModel, HydroEnergyModelReservoir, true) => 141061.0,
        (DCPNetworkModel, HydroEnergyModelReservoir, false) => 144109.0,
    )

    for reservoir_model in models
        formulation = get_formulation(reservoir_model)
        attrs = IOM.get_attributes(reservoir_model)
        energy_target = get(attrs, "energy_target", false)
        hydro_budget = get(attrs, "hydro_budget", false)
        @testset "$(formulation) with energy_target: $energy_target, and hydro_budget: $hydro_budget, ED model on $(net)" begin
            template = get_thermal_dispatch_template_network(net)
            set_device_model!(template, turbine_model)
            set_device_model!(template, reservoir_model)

            ED = DecisionModel(
                EconomicDispatchProblem,
                template,
                sys;
                optimizer = HiGHS_optimizer,
            )
            @test build!(ED; output_dir = mktempdir(; cleanup = true)) ==
                  ModelBuildStatus.BUILT
            psi_checksolve_test(
                ED,
                [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
                test_outputs[(net, formulation, energy_target)],
                10000, #update to 10k to handle the difference in Mac and Ubuntu. Likely a HiGHS issue.
            )
        end
    end
end

########################################################
####### Hydro DISPATCH RUN OF RIVER BUDGET TEST ########
########################################################
@testset "Test Hydro Dispatch Run Of River Formulations " begin
    device_model = DeviceModel(HydroDispatch, HydroDispatchRunOfRiver;
        use_slacks = true,
        attributes = Dict("hydro_budget" => true, "hydro_budget_interval" => Hour(24)))

    sys = PSB.build_system(PSITestSystems, "c_sys5_hy"; add_single_time_series = true)
    hy = only(get_components(HydroDispatch, sys))
    max_power = get_max_active_power(hy, PSY.SU)
    resolution = Dates.Hour(1)
    tstamp = range(DateTime("2024-01-01T00:00:00"); step = resolution, length = 48)
    data = ones(length(tstamp)) / (get_base_power(sys, PSY.NU) * max_power)
    ts = SingleTimeSeries("hydro_budget", TimeArray(tstamp, data))
    add_time_series!(sys, hy, ts)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    mock_construct_device!(model, device_model)
    moi_tests(model, 48, 0, 49, 24, 0, false)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "Hydro Dispatch Run Of River without budget omits budget constraint" begin
    device_model = DeviceModel(HydroDispatch, HydroDispatchRunOfRiver; use_slacks = true)

    sys = PSB.build_system(PSITestSystems, "c_sys5_hy"; add_single_time_series = true)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, sys)
    mock_construct_device!(model, device_model)

    container = IOM.get_optimization_container(model)
    @test !haskey(
        IOM.get_constraints(container),
        IOM.ConstraintKey(EnergyBudgetConstraint, HydroDispatch),
    )
    @test !haskey(
        IOM.get_variables(container),
        IOM.VariableKey(HydroEnergyShortageVariable, HydroDispatch),
    )
end

@testset "Solve Hydro Dispatch Run Of River" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy"; add_single_time_series = true)

    hydro_budget = 24
    eps = 1e-6

    hy = only(get_components(HydroDispatch, c_sys5_hy))
    max_power = get_max_active_power(hy, PSY.SU)

    tstamp = range(DateTime("2024-01-01T00:00:00"); step = Dates.Hour(1), length = 48)
    data = ones(length(tstamp)) / (get_base_power(c_sys5_hy, PSY.NU) * max_power)
    ts = SingleTimeSeries("hydro_budget", TimeArray(tstamp, data))
    add_time_series!(c_sys5_hy, first(get_components(HydroDispatch, c_sys5_hy)), ts)
    #remove_time_series!(c_sys5_hy, Deterministic)
    transform_single_time_series!(c_sys5_hy, Hour(24), Hour(24))

    template_uc = PowerOperationsProblemTemplate()
    set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
    set_device_model!(
        template_uc,
        DeviceModel(HydroDispatch, HydroDispatchRunOfRiver;
            attributes = Dict("hydro_budget" => true,
                "hydro_budget_interval" => Hour(hydro_budget))),
    )
    model = DecisionModel(
        template_uc,
        c_sys5_hy;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)
    df = read_variable(outputs, "ActivePowerVariable__HydroDispatch")
    hydro_power_sum =
        sum(df[!, :value])

    @test abs(hydro_power_sum - hydro_budget) <= eps
end

@testset "Make Hydro Dispatch Run Of River with Reserves" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(
        PSITestSystems,
        "c_sys5_hy";
        add_single_time_series = true,
        add_reserves = true,
    )

    # Fix reserve parameters
    reg_up = only(get_components(VariableReserve{ReserveUp}, c_sys5_hy))
    reg_dn = only(get_components(VariableReserve{ReserveDown}, c_sys5_hy))
    set_deployed_fraction!(reg_up, 0.0)
    set_deployed_fraction!(reg_dn, 0.0)
    set_requirement!(reg_up, 0.01 * PSY.SU)
    set_requirement!(reg_dn, 0.01 * PSY.SU)

    hydro_budget = 24
    eps = 1e-6

    hy = only(get_components(HydroDispatch, c_sys5_hy))

    # Update Service allocation
    # Remove reg up from hydro, but leave reg dn
    remove_service!(hy, reg_up)

    # Add reg up to thermals
    for th in get_components(ThermalStandard, c_sys5_hy)
        add_service!(th, reg_up, c_sys5_hy)
    end

    max_power = get_max_active_power(hy, PSY.SU)
    tstamp = range(DateTime("2024-01-01T00:00:00"); step = Dates.Hour(1), length = 48)
    data = ones(length(tstamp)) / (get_base_power(c_sys5_hy, PSY.NU) * max_power)
    ts = SingleTimeSeries("hydro_budget", TimeArray(tstamp, data))
    add_time_series!(c_sys5_hy, first(get_components(HydroDispatch, c_sys5_hy)), ts)

    ## add extra hydro budget
    hy_copy = HydroDispatch(;
        name = "HydroDispatchCopy",
        available = get_available(hy),
        bus = get_bus(hy),
        active_power = get_active_power(hy, PSY.SU),
        reactive_power = get_reactive_power(hy, PSY.SU),
        rating = get_rating(hy, PSY.SU),
        prime_mover_type = get_prime_mover_type(hy),
        active_power_limits = get_active_power_limits(hy, PSY.SU),
        reactive_power_limits = get_reactive_power_limits(hy, PSY.SU),
        ramp_limits = get_ramp_limits(hy, PSY.SU),
        time_limits = get_time_limits(hy),
        base_power = get_base_power(hy, PSY.NU),
    )
    add_component!(c_sys5_hy, hy_copy)
    copy_time_series!(hy_copy, hy)

    transform_single_time_series!(c_sys5_hy, Hour(24), Hour(24))

    template_uc = PowerOperationsProblemTemplate()
    set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
    set_device_model!(
        template_uc,
        DeviceModel(HydroDispatch, HydroDispatchRunOfRiver;
            attributes = Dict("hydro_budget" => true,
                "hydro_budget_interval" => Hour(hydro_budget))),
    )
    set_service_model!(template_uc, VariableReserve{ReserveUp}, RangeReserve)
    set_service_model!(template_uc, VariableReserve{ReserveDown}, RangeReserve)
    model = DecisionModel(
        template_uc,
        c_sys5_hy;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED
end

################################################
####### Hydro PUMP ENERGY DISPATCH TEST ########
################################################
@testset "Test Hydro Pump Energy Dispatch Formulations " begin
    device_model = DeviceModel(
        HydroPumpTurbine,
        HydroPumpEnergyDispatch;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "energy_target" => true,
        ),
    )

    c_sys5_bat =
        PSB.build_system(
            PSITestSystems,
            "c_sys5_hydro_pump_energy";
            add_reserves = true,
            add_single_time_series = true,
        )

    hy_pump = first(PSY.get_components(HydroPumpTurbine, c_sys5_bat))
    transform_single_time_series!(c_sys5_bat, Hour(24), Hour(24))

    model = DecisionModel(MockOperationProblem, CopperPlateNetworkModel, c_sys5_bat)
    mock_construct_device!(model, device_model)
    moi_tests(model, 72, 0, 48, 24, 0, true)
    psi_checkobjfun_test(model, GAEVF)
end

@testset "Test Hydro Pump Energy Dispatch Formulations 2" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_bat =
        PSB.build_system(
            PSITestSystems,
            "c_sys5_hydro_pump_energy";
            add_reserves = true,
            add_single_time_series = true,
        )

    hy_pump = first(PSY.get_components(HydroPumpTurbine, c_sys5_bat))

    transform_single_time_series!(c_sys5_bat, Hour(24), Hour(24))

    template_uc = PowerOperationsProblemTemplate()
    set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
    set_device_model!(
        template_uc,
        DeviceModel(
            HydroPumpTurbine,
            HydroPumpEnergyDispatch;
            attributes = Dict{String, Any}(
                "reservation" => true,
                "energy_target" => true,
            ),
        ),
    )

    model = DecisionModel(
        template_uc,
        c_sys5_bat;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED
end

#########################################
######## HydroBlock model Tests #########
#########################################

@testset "Test Hydro Block Optimization Formulation" begin
    output_dir = mktempdir(; cleanup = true)
    modeling_horizon = 3 * 24 * 1

    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")
    res = first(PSY.get_components(HydroReservoir, sys))

    set_head_to_volume_factor!(res, LinearFunctionData(1.0))
    set_storage_level_limits!(res, (min = 4000, max = 6000))
    set_level_targets!(res, 0.9)
    template_ed = PowerOperationsProblemTemplate(
        NetworkModel(
            CopperPlateNetworkModel;
        ),
    )

    set_device_model!(template_ed, ThermalStandard, ThermalBasicDispatch)
    set_device_model!(template_ed, PowerLoad, StaticPowerLoad)
    set_device_model!(template_ed, HydroReservoir, HydroWaterFactorModel)
    set_device_model!(template_ed, HydroTurbine, HydroWaterFactorModel)

    model = DecisionModel(
        template_ed,
        sys;
        name = "ED",
        optimizer = ipopt_optimizer,
        optimizer_solve_log_print = true,
        store_variable_names = true,
        horizon = Hour(24),
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; optimizer = ipopt_optimizer, output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)
    power_load = read_parameter(outputs, "ActivePowerTimeSeriesParameter__PowerLoad")
    reservoir_inflow = read_parameter(outputs, "InflowTimeSeriesParameter__HydroReservoir")

    water_spillage = read_variable(outputs, "WaterSpillageVariable__HydroReservoir")
    thermal_power = read_variable(outputs, "ActivePowerVariable__ThermalStandard")
    hydro_power = read_variable(outputs, "ActivePowerVariable__HydroTurbine")

    turbine_output = read_aux_variable(outputs, "HydroEnergyOutput__HydroTurbine")
    reservoir_volume =
        read_variable(outputs, "HydroReservoirVolumeVariable__HydroReservoir")

    var = read_variable(
        outputs,
        "HydroReservoirVolumeVariable__HydroReservoir";
        table_format = TableFormat.WIDE,
    )

    # check the second step is equal to the first step + dispatch
end

################################################
######## HydroWaterModelReservoir TEST #########
################################################

@testset "Solve HydroWaterModelReservoir" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    reservoir = only(get_components(HydroReservoir, c_sys5_hy))
    hydro_inflow_ts = get_time_series_array(Deterministic, reservoir, "inflow")

    template = PowerOperationsProblemTemplate()
    set_device_model!(template, HydroTurbine, HydroTurbineBilinearDispatch)
    set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)

    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_hy;
        optimizer = ipopt_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)

    moi_tests(model, 288, 0, 168, 168, 72, false)
    psi_checkobjfun_test(model, AffExpr)

    df_outflow = read_expression(outputs, "TotalHydroFlowRateTurbineOutgoing__HydroTurbine")
    hydro_vol_df =
        read_variables(outputs, [(HydroReservoirVolumeVariable, HydroReservoir)])["HydroReservoirVolumeVariable__HydroReservoir"]
    hydro_spillage_df =
        read_variables(outputs, [(WaterSpillageVariable, HydroReservoir)])["WaterSpillageVariable__HydroReservoir"]

    total_inflow = sum(values(hydro_inflow_ts))
    total_outflow = sum(df_outflow[!, :value])
    total_spillage = sum(hydro_spillage_df[!, :value])

    tol = 1e-4
    calculated_vf =
        (hydro_vol_df[1, :value]) +
        (
            (total_inflow - total_outflow - total_spillage) *
            POM.SECONDS_IN_HOUR *
            POM.M3_TO_KM3
        )

    @test isapprox(calculated_vf, hydro_vol_df[end, :value], atol = tol)

    psi_checksolve_test(
        model,
        [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL, MOI.LOCALLY_SOLVED],
        210949.49,
        1000,
    )
end

@testset "HydroTurbineBilinearDispatch (MILP): variable-bound plumbing to IOM" begin
    output_dir = mktempdir(; cleanup = true)

    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    template = PowerOperationsProblemTemplate()
    set_device_model!(
        template,
        DeviceModel(
            HydroTurbine,
            HydroTurbineBilinearDispatch;
            attributes = Dict("bilinear_approximation" => "bin2"),
        ),
    )
    set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )
    @test build!(model; output_dir = output_dir) == ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    time_steps = IOM.get_time_steps(container)
    flow = IOM.get_variable(container, HydroTurbineFlowRateVariable, HydroTurbine)
    head = IOM.get_variable(container, HydroReservoirHeadVariable, HydroReservoir)

    reservoirs = collect(get_components(HydroReservoir, sys))
    @test !isempty(reservoirs)
    for res in reservoirs
        # HEAD reservoirs store level limits directly in meters; bounds should match.
        @test PSY.get_level_data_type(res) == PSY.ReservoirDataType.HEAD
        limits = PSY.get_storage_level_limits(res)
        r_name = PSY.get_name(res)
        for t in time_steps
            v = head[r_name, t]
            @test JuMP.lower_bound(v) == limits.min
            @test JuMP.upper_bound(v) == limits.max
        end
    end

    turbines = collect(get_components(HydroTurbine, sys))
    @test !isempty(turbines)
    for turbine in turbines
        outflow = PSY.get_outflow_limits(turbine)
        @test outflow !== nothing
        t_name = PSY.get_name(turbine)
        for res in reservoirs, t in time_steps
            v = flow[t_name, PSY.get_name(res), t]
            @test JuMP.lower_bound(v) == outflow.min
            @test JuMP.upper_bound(v) == outflow.max
        end
    end
end

@testset "HydroTurbineBilinearDispatch: TurbinePowerOutputConstraint unit conversion" begin
    output_dir = mktempdir(; cleanup = true)

    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    template = PowerOperationsProblemTemplate()
    set_device_model!(template, HydroTurbine, HydroTurbineBilinearDispatch)
    set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        sys;
        optimizer = ipopt_optimizer,
        store_variable_names = true,
    )
    @test build!(model; output_dir = output_dir) == ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    time_steps = IOM.get_time_steps(container)
    base_power = IOM.get_model_base_power(container)
    constraint = IOM.get_constraint(container, TurbinePowerOutputConstraint, HydroTurbine)
    power = IOM.get_variable(container, ActivePowerVariable, HydroTurbine)
    flow = IOM.get_variable(container, HydroTurbineFlowRateVariable, HydroTurbine)
    head = IOM.get_variable(container, HydroReservoirHeadVariable, HydroReservoir)

    for turbine in get_components(HydroTurbine, sys)
        t_name = PSY.get_name(turbine)
        conv = PSY.get_conversion_factor(turbine)
        elev = PSY.get_powerhouse_elevation(turbine)
        reservoirs =
            filter(PSY.get_available, PSY.get_connected_head_reservoirs(sys, turbine))
        scale = POM.GRAVITATIONAL_CONSTANT * POM.WATER_DENSITY * conv / (1e6 * base_power)

        # power = scale * Σ_res (head_res * flow - elev * flow)
        #   ⇒ rearranged: power - scale * Σ head*flow + scale*elev * Σ flow == 0
        for t in time_steps
            con = constraint[t_name, t]
            con_obj = JuMP.constraint_object(con)
            @test con_obj.set isa MOI.EqualTo{Float64}

            # Linear coefficients: power has +1, each flow has +scale*elev.
            @test JuMP.normalized_coefficient(con, power[t_name, t]) ≈ 1.0
            for res in reservoirs
                @test JuMP.normalized_coefficient(
                    con,
                    flow[t_name, PSY.get_name(res), t],
                ) ≈ scale * elev

                # Quadratic cross term head*flow has -scale.
                quad_terms = con_obj.func.terms
                pair = JuMP.UnorderedPair(
                    head[PSY.get_name(res), t],
                    flow[t_name, PSY.get_name(res), t],
                )
                @test get(quad_terms, pair, 0.0) ≈ -scale
            end
        end
    end
end

@testset "Solve HydroWaterModelReservoir with bilinear approximations" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    reservoir = only(get_components(HydroReservoir, c_sys5_hy))
    hydro_inflow_ts = get_time_series_array(Deterministic, reservoir, "inflow")

    template = PowerOperationsProblemTemplate()
    set_device_model!(
        template,
        DeviceModel(
            HydroTurbine,
            HydroTurbineBilinearDispatch;
            attributes = Dict("bilinear_approximation" => "bin2"),
        ),
    )
    set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)

    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_hy;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)

    psi_checkobjfun_test(model, AffExpr)

    df_outflow = read_expression(outputs, "TotalHydroFlowRateTurbineOutgoing__HydroTurbine")
    hydro_vol_df =
        read_variables(outputs, [(HydroReservoirVolumeVariable, HydroReservoir)])["HydroReservoirVolumeVariable__HydroReservoir"]
    hydro_spillage_df =
        read_variables(outputs, [(WaterSpillageVariable, HydroReservoir)])["WaterSpillageVariable__HydroReservoir"]

    total_inflow = sum(values(hydro_inflow_ts))
    total_outflow = sum(df_outflow[!, :value])
    total_spillage = sum(hydro_spillage_df[!, :value])

    tol = 1e-4
    calculated_vf =
        (hydro_vol_df[1, :value]) +
        (
            (total_inflow - total_outflow - total_spillage) *
            POM.SECONDS_IN_HOUR *
            POM.M3_TO_KM3
        )

    @test isapprox(calculated_vf, hydro_vol_df[end, :value], atol = tol)

    psi_checksolve_test(
        model,
        [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL, MOI.LOCALLY_SOLVED],
        213043.54,
        1000,
    )
end

@testset "Solve HydroWaterModelReservoir with Budget" begin
    sys = PSB.build_system(
        PSITestSystems,
        "c_sys5_hy_turbine_head";
        force_build = true,
        add_single_time_series = true,
    )
    res = only(get_components(HydroReservoir, sys))
    inflow_array = get_time_series_array(SingleTimeSeries, res, "inflow")
    tstamp = timestamp(inflow_array)
    vals = values(inflow_array)
    budget_array = TimeArray(tstamp, vals .* 0.5)
    budget_ts = SingleTimeSeries("hydro_budget", budget_array)
    add_time_series!(sys, res, budget_ts)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, HydroTurbine, HydroTurbineWaterLinearDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => false, "hydro_budget" => true),
    )
    set_device_model!(template, reservoir_model)

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = false,
    )
    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    sol = OptimizationProblemOutputs(model)
    flow = read_expression(sol, "TotalHydroFlowRateReservoirOutgoing__HydroReservoir")[
        !,
        "value",
    ]
    @test sum(flow) <= sum(vals) / 4.0
end

@testset "Solve HydroWaterModelReservoir with Target" begin
    sys = PSB.build_system(
        PSITestSystems,
        "c_sys5_hy_turbine_head";
        force_build = true,
        add_single_time_series = true,
    )
    res = only(get_components(HydroReservoir, sys))
    hydro_cost = HydroReservoirCost(1e5, 0.0, 0.0)
    set_operation_cost!(res, hydro_cost)
    inflow_array = get_time_series_array(SingleTimeSeries, res, "inflow")
    tstamp = timestamp(inflow_array)
    vals = values(inflow_array)
    head_array = TimeArray(tstamp, 490.0 * ones(length(vals)))
    target_ts = SingleTimeSeries("hydro_target", head_array)
    add_time_series!(sys, res, target_ts)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, HydroTurbine, HydroTurbineWaterLinearDispatch)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => true, "hydro_budget" => false),
    )
    set_device_model!(template, reservoir_model)

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = false,
    )
    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    sol = OptimizationProblemOutputs(model)
    head = read_variable(sol, "HydroReservoirHeadVariable__HydroReservoir")[!, "value"]
    @test head[24] >= 490
end

@testset "Solve HydroWaterModelReservoir with Budget and Commitment" begin
    sys = PSB.build_system(
        PSITestSystems,
        "c_sys5_hy_turbine_head";
        force_build = true,
        add_single_time_series = true,
    )
    res = only(get_components(HydroReservoir, sys))
    inflow_array = get_time_series_array(SingleTimeSeries, res, "inflow")
    tstamp = timestamp(inflow_array)
    vals = values(inflow_array)
    budget_array = TimeArray(tstamp, vals .* 0.5)
    budget_ts = SingleTimeSeries("hydro_budget", budget_array)
    add_time_series!(sys, res, budget_ts)
    transform_single_time_series!(sys, Hour(24), Hour(24))
    turb = first(get_components(HydroTurbine, sys))
    set_active_power_limits!(turb, (min = 0.1 * PSY.SU, max = 5.2 * PSY.SU))
    set_operation_cost!(turb, HydroGenerationCost(
        CostCurve(LinearCurve(1.0)),
        2.0,
    ))

    template = PowerOperationsProblemTemplate(NetworkModel(CopperPlateNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, HydroTurbine, HydroTurbineWaterLinearCommitment)
    reservoir_model = DeviceModel(
        HydroReservoir,
        HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => false, "hydro_budget" => true),
    )
    set_device_model!(template, reservoir_model)

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = false,
    )
    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    sol = OptimizationProblemOutputs(model)
    flow = read_expression(sol, "TotalHydroFlowRateReservoirOutgoing__HydroReservoir")[
        !,
        "value",
    ]
    @test sum(flow) <= sum(vals) / 4.0
end

#####################################################
######## HydroWaterModelReservoir Cascading #########
#####################################################

@testset "Solve Cascading HydroWaterModelReservoir" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_cascading_turbine_head")

    template = PowerOperationsProblemTemplate()
    set_device_model!(template, HydroTurbine, HydroTurbineBilinearDispatch)
    set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)

    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_hy;
        optimizer = ipopt_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)

    moi_tests(model, 504, 0, 216, 216, 120, false)
    psi_checkobjfun_test(model, AffExpr)
end

@testset "Solve Cascading HydroEnergyModelReservoir" begin
    output_dir = mktempdir(; cleanup = true)

    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_cascading_turbine_head")

    template = PowerOperationsProblemTemplate()
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyDispatch)
    set_device_model!(template, HydroReservoir, HydroEnergyModelReservoir)

    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        c_sys5_hy;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
    )

    @test build!(model; output_dir = output_dir) ==
          ModelBuildStatus.BUILT

    @test solve!(model; output_dir = output_dir) ==
          IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    outputs = OptimizationProblemOutputs(model)

    moi_tests(model, 360, 0, 168, 168, 72, false)
    psi_checkobjfun_test(model, AffExpr)
end

###################################################################
######## Energy HydroPump and Turbine in same Reservoir #########
###################################################################

@testset "Solve Energy model with both Turbine and Reservoir" begin
    sys = build_hydro_with_both_pump_and_turbine()
    template = PowerOperationsProblemTemplate()
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyDispatch)
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyCommitment)
    res_model = DeviceModel(
        HydroReservoir,
        HydroEnergyModelReservoir;
        use_slacks = true,
        attributes = Dict{String, Any}(
            "energy_target" => false,
            "hydro_budget" => true,
        ),
    )
    set_device_model!(template, res_model)
    set_device_model!(template, HydroPumpTurbine, HydroPumpEnergyDispatch)
    p_model = DeviceModel(
        HydroPumpTurbine,
        HydroPumpEnergyCommitment;
        attributes = Dict{String, Any}(
            "reservation" => true,
        ),
    )
    set_device_model!(template, p_model)

    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)

    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        calculate_conflict = true,
    )

    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED

    p_model = DeviceModel(
        HydroPumpTurbine,
        HydroPumpEnergyCommitment;
        attributes = Dict{String, Any}(
            "reservation" => false,
        ),
    )
    set_device_model!(template, p_model)

    model = DecisionModel(
        template,
        sys;
        optimizer = HiGHS_optimizer,
        store_variable_names = true,
        calculate_conflict = true,
    )

    @test build!(model; output_dir = mktempdir()) == ModelBuildStatus.BUILT
    @test solve!(model) == IS.Simulation.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Hydro breakpoint multiplier and market-bid commitment traits" begin
    # Regression for the hydro market-bid breakpoint mis-scaling bug (2026-07
    # diagnosis); breakpoints are system-units so the multiplier must be 1.0 like every
    # other device type.
    demo_hydro = PSY.HydroDispatch(nothing)

    # Test breakpoint multiplier methods return 1.0 for FixedOutput and AbstractHydroFormulation
    @test POM.get_multiplier_value(
        POM.AbstractPiecewiseLinearBreakpointParameter,
        demo_hydro,
        POM.FixedOutput,
    ) == 1.0

    @test POM.get_multiplier_value(
        POM.AbstractPiecewiseLinearBreakpointParameter,
        demo_hydro,
        POM.HydroDispatchRunOfRiver,
    ) == 1.0

    # Lower-bound checks need a NONZERO static min: the demo device's default limits are
    # (min = 0, max = 0), under which every path returns 0.0. SU units require system
    # attachment, so attach the demo to a throwaway System first.
    lb_sys = PSY.System(100.0)
    lb_bus = PSY.ACBus(; number = 1, name = "LB_B1", available = true,
        bustype = PSY.ACBusTypes.REF, angle = 0.0, magnitude = 1.0,
        voltage_limits = (min = 0.9, max = 1.1), base_voltage = 345.0)
    PSY.add_component!(lb_sys, lb_bus)
    PSY.set_bus!(demo_hydro, lb_bus)
    PSY.add_component!(lb_sys, demo_hydro)
    PSY.set_active_power_limits!(demo_hydro, (min = 0.17 * PSY.SU, max = 0.21 * PSY.SU))

    # Dispatch formulations keep the hard variable bound at the static min: a real
    # min-gen under an always-on formulation is intended behavior. A unit whose min must
    # be escapable (e.g. inert market-bid hours) belongs under HydroCommitmentRunOfRiver,
    # where the min is On-gated, not hard-coded to 0 at the dispatch bound.
    @test POM.get_variable_lower_bound(
        POM.ActivePowerVariable,
        demo_hydro,
        POM.HydroDispatchRunOfRiver,
    ) == 0.17
    @test POM.get_variable_lower_bound(
        POM.ActivePowerVariable,
        demo_hydro,
        POM.HydroWaterFactorModel,
    ) == 0.17

    # Unit commitment: variable lb is 0.0 (the min moves into the semicontinuous
    # p >= min * On range constraint, so an OFF unit can sit at 0)
    @test POM.get_variable_lower_bound(
        POM.ActivePowerVariable,
        demo_hydro,
        POM.HydroCommitmentRunOfRiver,
    ) == 0.0

    # Market-bid PWL offset gating: commitment adds breakpoint1 * OnVariable to the block
    # offer constraint (escapable when OFF); dispatch adds it as a constant (always on).
    @test POM._include_min_gen_power_in_constraint(
        PSY.HydroDispatch,
        POM.ActivePowerVariable,
        POM.HydroCommitmentRunOfRiver,
    )
    @test !POM._include_min_gen_power_in_constraint(
        PSY.HydroDispatch,
        POM.ActivePowerVariable,
        POM.HydroDispatchRunOfRiver,
    )
    @test POM._include_constant_min_gen_power_in_constraint(
        PSY.HydroDispatch,
        POM.ActivePowerVariable,
        POM.HydroDispatchRunOfRiver,
    )

    # HydroCommitmentRunOfRiver has no duration/ramp constraints and never consumes
    # initial conditions, so it must not force an initialization sub-model (mirrors
    # ThermalBasicUnitCommitment).
    @test !POM.requires_initialization(POM.HydroCommitmentRunOfRiver())

    # The hydro OnVariable proportional cost must route through the market-bid-aware
    # maybe-time-variant path (like thermal UC), not IOM's static path whose
    # `PSY.get_fixed(cost)` does not exist for market bid costs and used to error the
    # HydroCommitmentRunOfRiver + market-bid objective build.
    @test hasmethod(
        POM.add_proportional_cost!,
        Tuple{
            POM.OptimizationContainer,
            Type{POM.OnVariable},
            IS.FlattenIteratorWrapper{PSY.HydroDispatch},
            Type{POM.HydroCommitmentRunOfRiver},
        },
    )
    @test hasmethod(
        POM.proportional_cost,
        Tuple{
            POM.OptimizationContainer,
            PSY.MarketBidCost,
            Type{POM.OnVariable},
            PSY.HydroDispatch,
            Type{POM.HydroCommitmentRunOfRiver},
            Int,
        },
    )
end

####################################################
#### AC NETWORK COVERAGE FOR HYDRO WATER MODELS ####
####################################################
# HydroTurbine <: PSY.HydroGen: a missing AC construct path silently falls through to
# the generic run-of-river dispatch with no water-flow variables. Each testset asserts
# the water-side containers are non-empty to catch that regression.
@testset "Hydro turbine water dispatch formulations build the real water model on AC networks" begin
    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    ac_networks = (ACPNetworkModel, ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)

    for formulation in (HydroTurbineBilinearDispatch, HydroTurbineWaterLinearDispatch)
        for network_formulation in (ac_networks..., DCPNetworkModel)
            template = PowerOperationsProblemTemplate(NetworkModel(network_formulation))
            set_device_model!(template, HydroTurbine, formulation)
            set_device_model!(template, HydroReservoir, HydroWaterModelReservoir)
            set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
            set_device_model!(template, PowerLoad, StaticPowerLoad)
            set_device_model!(template, Line, StaticBranch)

            model = DecisionModel(
                template,
                c_sys5_hy;
                optimizer = ipopt_optimizer,
                store_variable_names = true,
            )
            @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                  ModelBuildStatus.BUILT

            container = IOM.get_optimization_container(model)

            flow = IOM.get_variable(container, HydroTurbineFlowRateVariable, HydroTurbine)
            @test !isempty(flow)
            turbine_power_constraint =
                IOM.get_constraint(container, TurbinePowerOutputConstraint, HydroTurbine)
            @test !isempty(turbine_power_constraint)

            if network_formulation in ac_networks
                q = IOM.get_variable(container, ReactivePowerVariable, HydroTurbine)
                balance = IOM.get_expression(container, POM.ReactivePowerBalance, PSY.ACBus)
                t1 = first(IOM.get_time_steps(container))
                for device in PSY.get_components(HydroTurbine, c_sys5_hy)
                    name = PSY.get_name(device)
                    bus_no = PSY.get_number(PSY.get_bus(device))
                    @test JuMP.coefficient(balance[bus_no, t1], q[name, t1]) == 1.0
                end
            end
        end
    end
end

@testset "HydroTurbineWaterLinearCommitment builds the real water model on AC networks" begin
    # HydroTurbineWaterLinearCommitment adds OnVariable (binary). Combined with an AC
    # network's inherently nonlinear power flow, no attached solver in this suite supports
    # both a MILP and a nonlinear network simultaneously, so this uses the mock container
    # idiom (no solver attached) instead of build!()/solve!(). The turbine and reservoir
    # formulations cross-reference each other's variables, so both device models must have
    # their ArgumentConstructStage run before either's ModelConstructStage.
    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_head")
    reservoir_model = DeviceModel(HydroReservoir, HydroWaterModelReservoir)
    turbine_model = DeviceModel(HydroTurbine, HydroTurbineWaterLinearCommitment)
    ac_networks = (ACPNetworkModel, ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)

    for network_formulation in (ac_networks..., DCPNetworkModel)
        model = DecisionModel(MockOperationProblem, network_formulation, c_sys5_hy)
        mock_construct_devices!(model, (reservoir_model, turbine_model))

        container = IOM.get_optimization_container(model)

        flow = IOM.get_variable(container, HydroTurbineFlowRateVariable, HydroTurbine)
        @test !isempty(flow)
        on_var = IOM.get_variable(container, OnVariable, HydroTurbine)
        @test !isempty(on_var)
        turbine_power_constraint =
            IOM.get_constraint(container, TurbinePowerOutputConstraint, HydroTurbine)
        @test !isempty(turbine_power_constraint)

        if network_formulation in ac_networks
            q = IOM.get_variable(container, ReactivePowerVariable, HydroTurbine)
            balance = IOM.get_expression(container, POM.ReactivePowerBalance, PSY.ACBus)
            t1 = first(IOM.get_time_steps(container))
            for device in PSY.get_components(HydroTurbine, c_sys5_hy)
                name = PSY.get_name(device)
                bus_no = PSY.get_number(PSY.get_bus(device))
                @test JuMP.coefficient(balance[bus_no, t1], q[name, t1]) == 1.0
            end
        end
    end
end

@testset "HydroWaterFactorModel builds the real water model on AC networks" begin
    ac_networks = (ACPNetworkModel, ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)
    sys = PSB.build_system(PSITestSystems, "c_sys5_hy_turbine_energy")
    res = first(PSY.get_components(HydroReservoir, sys))
    set_head_to_volume_factor!(res, LinearFunctionData(1.0))
    set_storage_level_limits!(res, (min = 4000, max = 6000))
    set_level_targets!(res, 0.9)

    for network_formulation in (ac_networks..., DCPNetworkModel)
        template = PowerOperationsProblemTemplate(NetworkModel(network_formulation))
        set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
        set_device_model!(template, PowerLoad, StaticPowerLoad)
        set_device_model!(template, HydroReservoir, HydroWaterFactorModel)
        set_device_model!(template, HydroTurbine, HydroWaterFactorModel)
        set_device_model!(template, Line, StaticBranch)

        model = DecisionModel(
            template,
            sys;
            optimizer = ipopt_optimizer,
            store_variable_names = true,
            horizon = Hour(24),
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              ModelBuildStatus.BUILT

        container = IOM.get_optimization_container(model)

        flow = IOM.get_variable(container, HydroTurbineFlowRateVariable, HydroTurbine)
        @test !isempty(flow)
        hydro_power_constraint =
            IOM.get_constraint(container, POM.HydroPowerConstraint, HydroTurbine)
        @test !isempty(hydro_power_constraint)

        if network_formulation in ac_networks
            q = IOM.get_variable(container, ReactivePowerVariable, HydroTurbine)
            balance = IOM.get_expression(container, POM.ReactivePowerBalance, PSY.ACBus)
            t1 = first(IOM.get_time_steps(container))
            for device in PSY.get_components(HydroTurbine, sys)
                name = PSY.get_name(device)
                bus_no = PSY.get_number(PSY.get_bus(device))
                @test JuMP.coefficient(balance[bus_no, t1], q[name, t1]) == 1.0
            end
        end
    end
end

@testset "HydroCommitmentRunOfRiver builds the real model with reactive power on AC networks" begin
    c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy")
    device_model = DeviceModel(HydroDispatch, HydroCommitmentRunOfRiver)

    for network_formulation in
        (
        ACPNetworkModel,
        ACRNetworkModel,
        IVRNetworkModel,
        LPACCNetworkModel,
        DCPNetworkModel,
    )
        model = DecisionModel(MockOperationProblem, network_formulation, c_sys5_hy)
        mock_construct_device!(model, device_model)

        container = IOM.get_optimization_container(model)

        on_var = IOM.get_variable(container, OnVariable, HydroDispatch)
        @test !isempty(on_var)

        if network_formulation != DCPNetworkModel
            q = IOM.get_variable(container, ReactivePowerVariable, HydroDispatch)
            balance = IOM.get_expression(container, POM.ReactivePowerBalance, PSY.ACBus)
            t1 = first(IOM.get_time_steps(container))
            for device in PSY.get_components(HydroDispatch, c_sys5_hy)
                name = PSY.get_name(device)
                bus_no = PSY.get_number(PSY.get_bus(device))
                @test JuMP.coefficient(balance[bus_no, t1], q[name, t1]) == 1.0
            end
        end
    end
end

@testset "HydroCommitmentRunOfRiver container schema is stable across network families" begin
    for (net, expected_reactive) in ((DCPNetworkModel, false), (ACPNetworkModel, true))
        c_sys5_hy = PSB.build_system(PSITestSystems, "c_sys5_hy")
        device_model = DeviceModel(HydroDispatch, HydroCommitmentRunOfRiver)

        model = DecisionModel(MockOperationProblem, net, c_sys5_hy)
        mock_construct_device!(model, device_model)

        container = IOM.get_optimization_container(model)
        con_keys = Set(string.(keys(IOM.get_constraints(container))))
        @test any(occursin("ReactivePowerVariableLimitsConstraint", k) for k in con_keys) ==
              expected_reactive
    end
end

@testset "Hydro pump energy formulations build the real model with reactive power on AC networks" begin
    c_sys5_pump = PSB.build_system(
        PSITestSystems,
        "c_sys5_hydro_pump_energy";
        add_single_time_series = true,
    )
    transform_single_time_series!(c_sys5_pump, Hour(24), Hour(24))

    for formulation in (HydroPumpEnergyDispatch, HydroPumpEnergyCommitment)
        device_model = DeviceModel(
            HydroPumpTurbine,
            formulation;
            attributes = Dict{String, Any}("reservation" => true),
        )
        for network_formulation in (
            ACPNetworkModel,
            ACRNetworkModel,
            IVRNetworkModel,
            LPACCNetworkModel,
            DCPNetworkModel,
        )
            model = DecisionModel(MockOperationProblem, network_formulation, c_sys5_pump)
            mock_construct_device!(model, device_model)

            container = IOM.get_optimization_container(model)

            pump_var =
                IOM.get_variable(container, ActivePowerPumpVariable, HydroPumpTurbine)
            @test !isempty(pump_var)
            if formulation == HydroPumpEnergyCommitment
                on_var = IOM.get_variable(container, OnVariable, HydroPumpTurbine)
                @test !isempty(on_var)
            end

            if network_formulation != DCPNetworkModel
                q = IOM.get_variable(container, ReactivePowerVariable, HydroPumpTurbine)
                balance =
                    IOM.get_expression(container, POM.ReactivePowerBalance, PSY.ACBus)
                t1 = first(IOM.get_time_steps(container))
                for device in PSY.get_components(HydroPumpTurbine, c_sys5_pump)
                    name = PSY.get_name(device)
                    bus_no = PSY.get_number(PSY.get_bus(device))
                    @test JuMP.coefficient(balance[bus_no, t1], q[name, t1]) == 1.0
                end
            end
        end
    end
end

@testset "Concrete pump formulations receive the pump default attributes" begin
    for formulation in (HydroPumpEnergyDispatch, HydroPumpEnergyCommitment)
        attributes = POM.get_default_attributes(PSY.HydroPumpTurbine, formulation)
        @test attributes["reservation"] == false

        m = which(
            POM.get_default_attributes,
            Tuple{Type{PSY.HydroPumpTurbine}, Type{formulation}},
        )
        @test occursin("AbstractHydroPumpFormulation", string(m.sig))
    end
end
