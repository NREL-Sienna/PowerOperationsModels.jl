# Pins every (category, entry, component) -> PFContribution mapping so a new device can't
# silently desync the OPF->PowerFlows injection-sign path. The resolver lives inside the
# PowerFlows weakdep extension, reached here via `Base.get_extension`.
# TODO: reenable when incorporated PF changes
@testset "pf_contribution resolver table" begin
#    PFExt = Base.get_extension(PowerOperationsModels, :PowerFlowsExt)
#    @test PFExt !== nothing
#    P = PFExt.PFContribution
#    pf_contribution = PFExt.pf_contribution
#    FAPV = POM.FlowActivePowerVariable
#    FToF = POM.FlowActivePowerToFromVariable
#    # singleton quantity/role tags (replace the former Symbol fields)
#    ACT, REAC = PFExt.PFActiveQuantity(), PFExt.PFReactiveQuantity()
#    ANG, MAG = PFExt.PFAngleQuantity(), PFExt.PFMagnitudeQuantity()
#    INJ, WD, HVDC, NONE = PFExt.PFInjectionRole(), PFExt.PFWithdrawalRole(),
#    PFExt.PFHVDCNetRole(), PFExt.PFNoRole()
#
#    # --- generic injectors / loads (variable entries) ---
#    @test pf_contribution(
#        Val(:active_power),
#        IOM.ActivePowerVariable,
#        PSY.ThermalStandard,
#    ) == P(ACT, INJ, 1.0, false)
#    @test pf_contribution(Val(:active_power), IOM.ActivePowerVariable, PSY.PowerLoad) ==
#          P(ACT, WD, -1.0, false)
#    @test pf_contribution(
#        Val(:active_power_out),
#        IOM.ActivePowerOutVariable,
#        PSY.ThermalStandard,
#    ) == P(ACT, INJ, 1.0, true)
#    @test pf_contribution(
#        Val(:active_power_in),
#        IOM.ActivePowerInVariable,
#        PSY.ThermalStandard,
#    ) == P(ACT, INJ, -1.0, true)
#    @test pf_contribution(
#        Val(:reactive_power),
#        POM.ReactivePowerVariable,
#        PSY.ThermalStandard,
#    ) == P(REAC, INJ, 1.0, false)
#    @test pf_contribution(Val(:reactive_power), POM.ReactivePowerVariable, PSY.PowerLoad) ==
#          P(REAC, WD, -1.0, false)
#
#    # --- voltages assign (no direction) ---
#    @test pf_contribution(Val(:voltage_angle_opf), POM.VoltageAngle, PSY.ACBus) ==
#          P(ANG, NONE, 1.0, false)
#    @test pf_contribution(Val(:voltage_magnitude_opf), POM.VoltageMagnitude, PSY.ACBus) ==
#          P(MAG, NONE, 1.0, false)
#
#    # --- parameters are pre-signed: in/out collapse to +1 (the #1631 fix) ---
#    @test pf_contribution(
#        Val(:active_power_in),
#        POM.ActivePowerInTimeSeriesParameter,
#        PSY.ThermalStandard,
#    ) == P(ACT, INJ, 1.0, true)
#    @test pf_contribution(
#        Val(:active_power),
#        POM.ActivePowerTimeSeriesParameter,
#        PSY.PowerLoad,
#    ) == P(ACT, WD, -1.0, false)
#
#    # --- HVDC re-targets to :hvdc_net (PowerFlows' bus_hvdc_net_power); same signs as
#    #     injection. single var to_from is +1, directional to_from is -1, from_to is -1 ---
#    @test pf_contribution(
#        Val(:active_power_hvdc_pst_to_from),
#        FAPV,
#        PSY.TwoTerminalGenericHVDCLine,
#    ) == P(ACT, HVDC, 1.0, false)
#    @test pf_contribution(
#        Val(:active_power_hvdc_pst_to_from),
#        FToF,
#        PSY.TwoTerminalGenericHVDCLine,
#    ) == P(ACT, HVDC, -1.0, false)
#    @test pf_contribution(
#        Val(:active_power_hvdc_pst_from_to),
#        FAPV,
#        PSY.TwoTerminalGenericHVDCLine,
#    ) == P(ACT, HVDC, -1.0, false)
#
#    # --- PhaseShiftingTransformer: from_to -1, to_from +1 ---
#    @test pf_contribution(
#        Val(:active_power_hvdc_pst_to_from),
#        FAPV,
#        PSY.PhaseShiftingTransformer,
#    ) == P(ACT, INJ, 1.0, false)
#    @test pf_contribution(
#        Val(:active_power_hvdc_pst_from_to),
#        FAPV,
#        PSY.PhaseShiftingTransformer,
#    ) == P(ACT, INJ, -1.0, false)
end
