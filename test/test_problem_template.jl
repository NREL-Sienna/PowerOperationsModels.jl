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

@testset "Template market model wiring" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    @test get_market_model(template) === nothing
    # `IOM.FixedOutput` stands in as a concrete `IOM.AbstractDeviceFormulation`; this
    # testset is about the template wiring, not any particular market formulation.
    @test_throws ArgumentError set_market_component_model!(
        template,
        PSY.VirtualParticipant,
        IOM.FixedOutput,
    )
    set_market_model!(
        template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    @test IOM.get_settlement_domain(get_market_model(template)) === PSY.System

    set_market_component_model!(template, PSY.VirtualParticipant, IOM.FixedOutput)
    @test haskey(
        IOM.get_market_component_models(get_market_model(template)),
        nameof(PSY.VirtualParticipant),
    )

    # A non-System settlement domain is rejected at validation time, not at set time --
    # mirroring how set_network_model! defers to validate_template_impl!.
    bad_domain_template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_market_model!(
        bad_domain_template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.LoadZone),
    )
    @test_throws ArgumentError POM._check_market_model!(bad_domain_template)

    bad_network_template = PowerOperationsProblemTemplate(ACPNetworkModel)
    set_market_model!(
        bad_network_template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    @test_throws ArgumentError POM._check_market_model!(bad_network_template)

    # I7: only CopperPlateNetworkModel is accepted, even though PTDF/AreaBalance/DCP are
    # all `<: AbstractActivePowerModel` too -- their branch/area constraints stay binding
    # and would silently congestion-contaminate the settlement price. Error names the
    # offending formulation.
    for bad_formulation in (PTDFNetworkModel, AreaBalanceNetworkModel, DCPNetworkModel)
        ptdf_template = PowerOperationsProblemTemplate(bad_formulation)
        set_market_model!(
            ptdf_template,
            IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
        )
        err = nothing
        try
            POM._check_market_model!(ptdf_template)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin(string(bad_formulation), err.msg)
    end

    # A CopperPlate market template is otherwise accepted (no component models yet).
    cp_template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    set_market_model!(
        cp_template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )

    # I1: an empty market-component container is a configuration error at validation time.
    err_empty = nothing
    try
        POM._check_market_model!(cp_template)
    catch e
        err_empty = e
    end
    @test err_empty isa ArgumentError
    @test occursin("no market component models", err_empty.msg)

    set_market_component_model!(cp_template, PSY.VirtualParticipant, IOM.FixedOutput)
    @test POM._check_market_model!(cp_template) === nothing

    # I2: use_slacks = true on the network model conflicts with a market model (the market
    # rule zeroes the physical slack cost regardless, so the penalty can never be honored).
    slacks_template = PowerOperationsProblemTemplate(
        NetworkModel(CopperPlateNetworkModel; use_slacks = true),
    )
    set_market_model!(
        slacks_template,
        IOM.MarketModel(SettlementMarket; settlement_domain = PSY.System),
    )
    set_market_component_model!(slacks_template, PSY.VirtualParticipant, IOM.FixedOutput)
    err_slacks = nothing
    try
        POM._check_market_model!(slacks_template)
    catch e
        err_slacks = e
    end
    @test err_slacks isa ArgumentError
    @test occursin("use_slacks", err_slacks.msg)
end
