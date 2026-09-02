# Trait-vs-reality guards. Each testset asserts that what a trait axis DECLARES matches
# what a real `build!` produces. `declared`/`forbidden` are computed by calling the trait
# function — never restated by hand, or the test would only prove it agrees with itself.

@testset "reactive_power_support declares exactly the reactive machinery a build creates" begin
    sys = PSB.build_system(PSITestSystems, "c_sys5")

    # The reactive containers a thermal device contributes under an AC network. Computed
    # from the trait, so a network whose `reactive_power_support` changes flips both lists.
    _reactive_specs() = [
        ContainerSpec(:expression, ReactivePowerBalance, PSY.ACBus),
        ContainerSpec(:variable, ReactivePowerVariable, PSY.ThermalStandard),
    ]
    _has_q(N) = POM.reactive_power_support(N) === POM.HasReactivePower()
    declared(_F, N) = _has_q(N) ? _reactive_specs() : ContainerSpec[]
    forbidden(_F, N) = _has_q(N) ? ContainerSpec[] : _reactive_specs()

    cases = (
        (DCPNetworkModel, HiGHS_optimizer, sys, (ThermalBasicDispatch,)),
        (PTDFNetworkModel, HiGHS_optimizer, sys, (ThermalBasicDispatch,)),
        (NFANetworkModel, HiGHS_optimizer, sys, (ThermalBasicDispatch,)),
        (CopperPlateNetworkModel, HiGHS_optimizer, sys, (ThermalBasicDispatch,)),
        (DCPLLNetworkModel, ipopt_optimizer, sys, (ThermalBasicDispatch,)),
        (ACPNetworkModel, ipopt_optimizer, sys, (ThermalBasicDispatch,)),
        (ACRNetworkModel, ipopt_optimizer, sys, (ThermalBasicDispatch,)),
        (LPACCNetworkModel, ipopt_optimizer, sys, (ThermalBasicDispatch,)),
        (IVRNetworkModel, ipopt_optimizer, sys, (ThermalBasicDispatch,)),
    )

    assert_trait_matches_build(
        "reactive_power_support",
        cases;
        declared = declared,
        forbidden = forbidden,
        template_for = (_F, N) -> get_thermal_dispatch_template_network(NetworkModel(N)),
    )

    # Every native nodal formulation must be in the case list above.
    assert_axis_coverage(
        POM.AbstractNetworkModel,
        (
            DCPNetworkModel,
            PTDFNetworkModel,
            AreaPTDFNetworkModel,
            NFANetworkModel,
            CopperPlateNetworkModel,
            AreaBalanceNetworkModel,
            DCPLLNetworkModel,
            ACPNetworkModel,
            ACRNetworkModel,
            LPACCNetworkModel,
            IVRNetworkModel,
        ),
    )
end

@testset "network_has_reactive_power stays derived from reactive_power_support" begin
    # The predicate used by template validation and the trait used for dispatch were two
    # independent method tables before they were unified; this pins them together.
    for N in (
        DCPNetworkModel,
        PTDFNetworkModel,
        AreaPTDFNetworkModel,
        NFANetworkModel,
        CopperPlateNetworkModel,
        AreaBalanceNetworkModel,
        DCPLLNetworkModel,
        ACPNetworkModel,
        ACRNetworkModel,
        LPACCNetworkModel,
        IVRNetworkModel,
    )
        @test POM.network_has_reactive_power(N) ==
              (POM.reactive_power_support(N) === POM.HasReactivePower())
    end
end

@testset "voltage_coordinates partitions the AC-native formulations" begin
    @test POM.voltage_coordinates(ACPNetworkModel) === POM.PolarVoltage()
    @test POM.voltage_coordinates(LPACCNetworkModel) === POM.PolarVoltage()
    @test POM.voltage_coordinates(ACRNetworkModel) === POM.RectangularVoltage()
    @test POM.voltage_coordinates(IVRNetworkModel) === POM.RectangularVoltage()
    for N in (
        DCPNetworkModel,
        DCPLLNetworkModel,
        NFANetworkModel,
        PTDFNetworkModel,
        CopperPlateNetworkModel,
        AreaBalanceNetworkModel,
    )
        @test POM.voltage_coordinates(N) === POM.NoVoltageCoordinates()
    end

    # The rectangular set is exactly what `Union{ACRNetworkModel, IVRNetworkModel}` used to
    # spell out at 17 call sites.
    rectangular = filter(
        N -> POM.voltage_coordinates(N) === POM.RectangularVoltage(),
        [
            DCPNetworkModel,
            DCPLLNetworkModel,
            NFANetworkModel,
            PTDFNetworkModel,
            AreaPTDFNetworkModel,
            CopperPlateNetworkModel,
            AreaBalanceNetworkModel,
            ACPNetworkModel,
            ACRNetworkModel,
            LPACCNetworkModel,
            IVRNetworkModel,
        ],
    )
    @test Set(rectangular) == Set([ACRNetworkModel, IVRNetworkModel])
end
