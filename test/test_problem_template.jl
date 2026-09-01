# This file is WIP while the interface for templates is finalized

@testset "Branch validation scoped to modeled networks" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    line = first(PSY.get_components(PSY.Line, sys))
    arc = PSY.get_arc(line)
    PSY.set_base_voltage!(PSY.get_to(arc), 10 * PSY.get_base_voltage(PSY.get_from(arc)))

    cp_model =
        DecisionModel(get_thermal_dispatch_template_network(CopperPlateNetworkModel), sys)
    @test POM.validate_template(cp_model) === nothing

    ptdf_model = DecisionModel(get_thermal_dispatch_template_network(PTDFNetworkModel), sys)
    Logging.with_logger(Logging.NullLogger()) do
        @test_throws IS.InvalidValue POM.validate_template(ptdf_model)
    end

    dcp_model = DecisionModel(get_thermal_dispatch_template_network(DCPNetworkModel), sys)
    Logging.with_logger(Logging.NullLogger()) do
        @test_throws IS.InvalidValue POM.validate_template(dcp_model)
    end

    ab_template = PowerOperationsProblemTemplate(AreaBalanceNetworkModel)
    set_device_model!(ab_template, PSY.PowerLoad, StaticPowerLoad)
    set_device_model!(ab_template, PSY.ThermalStandard, ThermalBasicDispatch)
    ab_model = DecisionModel(ab_template, sys)
    @test POM.validate_template(ab_model) === nothing
end

@testset "Settings export_optimization_model format" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")
    @test IOM.get_export_optimization_model(IOM.Settings(sys)) ==
          IOM.OptimizationModelExportFormat.NONE
    @test IOM.get_export_optimization_model(
        IOM.Settings(sys; export_optimization_model = IOM.OptimizationModelExportFormat.LP),
    ) == IOM.OptimizationModelExportFormat.LP
    @test IOM.get_export_optimization_model(
        IOM.Settings(sys; export_optimization_model = "mof"),
    ) == IOM.OptimizationModelExportFormat.MOF
    @test IOM.get_export_optimization_model(
        IOM.Settings(sys; export_optimization_model = " lp "),
    ) == IOM.OptimizationModelExportFormat.LP
    @test IOM.get_export_optimization_model(
        IOM.Settings(sys; export_optimization_model = ""),
    ) == IOM.OptimizationModelExportFormat.NONE
    @test_throws IS.ConflictingInputsError IOM.Settings(
        sys;
        export_optimization_model = "json",
    )
    @test_throws IS.ConflictingInputsError IOM.Settings(
        sys;
        export_optimization_model = true,
    )
end

@testset "Manual Operations Template" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, Line, StaticBranchUnbounded)
    @test !isempty(template.devices)
    @test !isempty(template.branches)
    @test isempty(template.services)
end

@testset "validate_available_devices" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5_il")
    @test isempty(PSY.get_components(PSY.HydroDispatch, sys))
    @test POM.validate_available_devices(
        DeviceModel(PSY.ThermalStandard, ThermalBasicDispatch),
        sys,
    )
    @test !POM.validate_available_devices(
        DeviceModel(PSY.HydroDispatch, HydroDispatchRunOfRiver),
        sys,
    )
end

@testset "set_service_model! rejects feedforwards on ServiceModel" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    ff = UpperBoundFeedforward(;
        component_type = PSY.ThermalStandard,
        source = ActivePowerVariable,
        affected_values = [ActivePowerVariable],
    )
    # `ServiceModel`'s `feedforwards` kwarg is still accepted by IOM's constructor; POM must
    # reject it here, at template definition, rather than let it reach `build!` and fail
    # deep inside `add_feedforward_arguments!`.
    service_model =
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve; feedforwards = [ff])
    @test_throws ArgumentError set_service_model!(template, service_model)
end

@testset "Operations Template Overwrite" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    @test_logs (:warn, "Overwriting ThermalStandard existing model") set_device_model!(
        template,
        DeviceModel(ThermalStandard, ThermalBasicUnitCommitment),
    )
    @test IOM.get_formulation(template.devices[:ThermalStandard]) ==
          ThermalBasicUnitCommitment
end
