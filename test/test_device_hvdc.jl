@testset "HVDC System Tests" begin
    sys_5 = build_system(PSISystems, "sys10_pjm_ac_dc")
    template_uc = PowerOperationsProblemTemplate(NetworkModel(
        DCPNetworkModel,
        #use_slacks=true,
        #network_matrix =PTDF(sys_5),
        #duals=[CopperPlateBalanceConstraint],
    ))

    set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, DeviceModel(Line, StaticBranch))
    set_device_model!(template_uc, DeviceModel(InterconnectingConverter, LosslessConverter))
    set_device_model!(template_uc, DeviceModel(TModelHVDCLine, LosslessLine))
    set_hvdc_network_model!(template_uc, TransportHVDCNetworkModel)
    model = DecisionModel(
        template_uc, sys_5;
        name = "UC", optimizer = HiGHS_optimizer, horizon = _SHORT_HORIZON,
    )
    @test build!(model; output_dir = mktempdir()) == IOM.ModelBuildStatus.BUILT
    # StaticBranch under DCP carries flow as the BThetaBranchFlow expression (no
    # FlowActivePowerVariable, no Ohm's-law equality): -24 variables and -24 equalities.
    moi_tests(model, 114, 24, 104, 44, 52, true)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    template_uc = PowerOperationsProblemTemplate(
        NetworkModel(
            PTDFNetworkModel;
            #use_slacks=true,
            network_matrix = PTDF(sys_5),
            #duals=[CopperPlateBalanceConstraint],
        ),
    )

    set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, DeviceModel(Line, StaticBranch))
    set_device_model!(template_uc, DeviceModel(InterconnectingConverter, LosslessConverter))
    set_device_model!(template_uc, DeviceModel(TModelHVDCLine, LosslessLine))
    set_hvdc_network_model!(template_uc, TransportHVDCNetworkModel)
    model = DecisionModel(
        template_uc, sys_5;
        name = "UC", optimizer = HiGHS_optimizer, horizon = _SHORT_HORIZON,
    )
    @test build!(model; output_dir = mktempdir()) == IOM.ModelBuildStatus.BUILT
    moi_tests(model, 94, 0, 104, 44, 32, true)
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

function _generate_test_hvdc_sys()
    sys = build_system(PSISystems, "sys10_pjm_ac_dc")
    th_names_2 = ["Alta-2", "Sundance-2", "Park City-2", "Solitude-2", "Brighton-2"]
    for th_name in th_names_2
        g = PSY.get_component(PSY.ThermalStandard, sys, th_name)
        op_cost = g.operation_cost
        val_curve = op_cost.variable.value_curve
        new_prop_term = get_proportional_term(val_curve) * 2.0
        if g.name == "Park City-2"
            new_prop_term = new_prop_term + 5.0
        end
        new_quad_cost = QuadraticCurve(
            get_quadratic_term(val_curve),
            new_prop_term,
            get_constant_term(val_curve),
        )
        new_op_cost = ThermalGenerationCost(
            CostCurve(
                new_quad_cost,
                PSY.get_power_units(op_cost.variable),
                op_cost.variable.vom_cost,
            ),
            op_cost.fixed,
            op_cost.start_up,
            op_cost.shut_down,
        )
        set_operation_cost!(g, new_op_cost)
    end

    for ipc in get_components(InterconnectingConverter, sys)
        new_dc_loss = QuadraticCurve(0.01, 0.01, 0.0)
        set_loss_function!(ipc, new_dc_loss)
        set_max_dc_current!(ipc, 2.0 * PSY.SU)
    end
    return sys
end

@testset "HVDC System with Transport Network" begin
    sys = _generate_test_hvdc_sys()
    template = PowerOperationsProblemTemplate(NetworkModel(DCPNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, TModelHVDCLine, LosslessLine)
    set_device_model!(template, InterconnectingConverter, LosslessConverter)
    set_hvdc_network_model!(template, TransportHVDCNetworkModel)
    model =
        DecisionModel(
            template,
            sys;
            store_variable_names = true,
            optimizer = HiGHS_optimizer,
            horizon = _SHORT_HORIZON,
        )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "HVDC CurrentAbsoluteValueVariable matches |ConverterCurrent| at MILP optimum" begin
    # Force a ~2 pu side-2 generation deficit (within the 2 converters × 2.0 pu DC
    # import capacity) so side-2 must import over the DC ties. Under CopperPlate the
    # HVDC links are ignored and the converters idle at I = 0 — a degenerate optimum
    # sitting on the bin2 |I| PWL breakpoint (the vacuous, x86_64-HiGHS-fragile solve).
    # PTDF keeps the two AC islands separate, so the deficit drives real converter
    # current and the |I| check below is non-vacuous and off the breakpoint. deepcopy
    # isolates the limit change from the PSB-cached system shared by the other testsets.
    sys = deepcopy(_generate_test_hvdc_sys())
    for (name, cap) in (("Brighton-2", 2.0), ("Solitude-2", 2.0))
        PSY.set_active_power_limits!(
            get_component(ThermalStandard, sys, name),
            (min = 0.0 * PSY.SU, max = cap * PSY.SU),
        )
    end
    template = PowerOperationsProblemTemplate(
        NetworkModel(PTDFNetworkModel; network_matrix = PTDF(sys)),
    )
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, TModelHVDCLine, DCLossyLine)
    set_device_model!(
        template,
        DeviceModel(
            InterconnectingConverter, QuadraticLossConverter;
            attributes = Dict(
                "bilinear_approximation" => "bin2",
                "bilinear_relative_tolerance" => 0.35,
            ),
        ),
    )
    set_hvdc_network_model!(template, VoltageDispatchHVDCNetworkModel)
    model = DecisionModel(
        template, sys;
        store_variable_names = true, optimizer = HiGHS_optimizer,
        horizon = _SHORT_HORIZON,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED

    container = IOM.get_optimization_container(model)
    i_vals =
        JuMP.value.(
            IOM.get_variable(container, ConverterCurrent, InterconnectingConverter).data,
        )
    abs_i_vals =
        JuMP.value.(
            IOM.get_variable(
                container,
                CurrentAbsoluteValueVariable,
                InterconnectingConverter,
            ).data,
        )
    # Making sure we avoided I = 0
    @test maximum(abs.(i_vals)) > 0.5
    @test isapprox(abs_i_vals, abs.(i_vals); atol = 1e-4)
end

@testset "QuadraticLossConverter builds under representative bilinear schemes" begin
    sys = _generate_test_hvdc_sys()
    for scheme in ("bin2", "nmdt")
        template = PowerOperationsProblemTemplate(
            NetworkModel(PTDFNetworkModel; network_matrix = PTDF(sys)),
        )
        set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
        set_device_model!(template, PowerLoad, StaticPowerLoad)
        set_device_model!(template, DeviceModel(Line, StaticBranch))
        set_device_model!(template, TModelHVDCLine, DCLossyLine)
        set_device_model!(
            template,
            DeviceModel(
                InterconnectingConverter, QuadraticLossConverter;
                attributes = Dict{String, Any}("bilinear_approximation" => scheme),
            ),
        )
        set_hvdc_network_model!(template, VoltageDispatchHVDCNetworkModel)
        model = DecisionModel(
            template,
            sys;
            optimizer = HiGHS_optimizer,
            horizon = _SHORT_HORIZON,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
    end
end

##############################################################################
################ Two-Terminal VSC HVDC tests #################################
##############################################################################

# Build a small AC test system and replace an AC line with a TwoTerminalVSCLine
# so we have a concrete VSC device to exercise the formulation against.
function _generate_test_vsc_sys(;
    g = 50.0,
    rating_from = 2.0,
    rating_to = 2.0,
    loss_a = 0.01,
    loss_b = 0.0,
    loss_c = 0.0,
)
    sys = build_system(PSITestSystems, "c_sys5_uc")
    line = get_component(Line, sys, "1")
    remove_component!(sys, line)

    vsc = TwoTerminalVSCLine(;
        name = get_name(line),
        available = true,
        arc = get_arc(line),
        active_power_flow = 0.0,
        rating = max(rating_from, rating_to),
        active_power_limits_from = (min = -rating_from, max = rating_from),
        active_power_limits_to = (min = -rating_to, max = rating_to),
        g = g,
        dc_current = 0.0,
        reactive_power_from = 0.0,
        dc_control_from = VSCDCControlModes.DC_VOLTAGE,
        ac_control_from = VSCACControlModes.AC_VOLTAGE,
        dc_setpoint_from = 1.0,
        ac_setpoint_from = 1.0,
        converter_loss_from = QuadraticCurve(loss_a, loss_b, loss_c),
        max_dc_current_from = 5.0,
        rating_from = rating_from,
        reactive_power_limits_from = (min = -rating_from, max = rating_from),
        power_factor_weighting_fraction_from = 1.0,
        voltage_limits_from = (min = 0.95, max = 1.05),
        dc_voltage_droop_from = 0.0,
        reactive_power_to = 0.0,
        dc_control_to = VSCDCControlModes.DC_POWER,
        ac_control_to = VSCACControlModes.AC_REACTIVE_POWER,
        dc_setpoint_to = 0.0,
        ac_setpoint_to = 0.0,
        converter_loss_to = QuadraticCurve(loss_a, loss_b, loss_c),
        max_dc_current_to = 5.0,
        rating_to = rating_to,
        reactive_power_limits_to = (min = -rating_to, max = rating_to),
        power_factor_weighting_fraction_to = 1.0,
        voltage_limits_to = (min = 0.95, max = 1.05),
        dc_voltage_droop_to = 0.0,
    )
    add_component!(sys, vsc)
    return sys
end

function _build_vsc_model(
    converter_model::DeviceModel,
    network,
    optimizer;
    sys = _generate_test_vsc_sys(),
)
    template = PowerOperationsProblemTemplate(NetworkModel(network))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, converter_model)
    return DecisionModel(
        template, sys;
        store_variable_names = true, optimizer = optimizer, horizon = _SHORT_HORIZON,
    )
end

# A single HVDCTwoTerminalVSC formulation, switched between MILP and exact (NLP)
# via the "bilinear_approximation" attribute ("bin2" vs the default "none").
_vsc_milp(attrs...) = DeviceModel(
    TwoTerminalVSCLine, HVDCTwoTerminalVSC;
    attributes = Dict{String, Any}("bilinear_approximation" => "bin2", attrs...),
)
_vsc_nlp() = DeviceModel(TwoTerminalVSCLine, HVDCTwoTerminalVSC)  # default "none"

@testset "HVDC VSC LP vs NLP objective agreement" begin
    function _solve(converter_model, optimizer)
        sys = _generate_test_vsc_sys()
        model = _build_vsc_model(converter_model, DCPNetworkModel, optimizer; sys = sys)
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        c = IOM.get_optimization_container(model)
        flow = vec(
            JuMP.value.(
                IOM.get_variable(c, FlowActivePowerFromToVariable, TwoTerminalVSCLine).data,
            ),
        )
        return (obj = c.optimizer_stats.objective_value, flow = flow)
    end
    lp = _solve(_vsc_milp("bilinear_relative_tolerance" => 0.1), HiGHS_optimizer)
    nlp = _solve(_vsc_nlp(), ipopt_optimizer)
    # Non-vacuity: both models actually push the VSC near its 2.0 pu rating.
    @test maximum(abs.(lp.flow)) > 1.5
    @test maximum(abs.(nlp.flow)) > 1.5
    # Solutions agree, not just objectives: aggregate throughput within a few %.
    @test isapprox(sum(abs.(lp.flow)), sum(abs.(nlp.flow)); rtol = 0.1)
    @test isapprox(lp.obj, nlp.obj; rtol = 0.05)
end

@testset "HVDCTwoTerminalVSC builds under representative bilinear schemes" begin
    sys = _generate_test_vsc_sys()
    # One squares-based ("bin2") and one discretization-based ("nmdt") scheme
    # cover both `_add_converter_bilinear!` branches.
    for scheme in ("bin2", "nmdt")
        template = PowerOperationsProblemTemplate(NetworkModel(DCPNetworkModel))
        set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
        set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
        set_device_model!(template, PowerLoad, StaticPowerLoad)
        set_device_model!(template, DeviceModel(Line, StaticBranch))
        set_device_model!(
            template,
            DeviceModel(
                TwoTerminalVSCLine, HVDCTwoTerminalVSC;
                attributes = Dict{String, Any}("bilinear_approximation" => scheme),
            ),
        )
        model = DecisionModel(
            template,
            sys;
            optimizer = HiGHS_optimizer,
            horizon = _SHORT_HORIZON,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
    end
end

@testset "HVDC VSC: higher cable resistance increases cost" begin
    # Smaller g => larger R = 1/g => more losses => optimum should not improve.
    function _solve_with_g(g_value)
        sys = _generate_test_vsc_sys(; g = g_value)
        model = _build_vsc_model(
            _vsc_milp("bilinear_relative_tolerance" => 0.2),
            DCPNetworkModel, HiGHS_optimizer; sys = sys,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        return IOM.get_optimization_container(model).optimizer_stats.objective_value
    end
    low_R_obj = _solve_with_g(100.0)   # large g, small R
    high_R_obj = _solve_with_g(20.0)   # smaller g, larger R
    @test high_R_obj >= low_R_obj - 1e-6
end

@testset "HVDC VSC: tighter PQ rating raises cost on AC" begin
    function _solve_with_rating(s)
        sys = _generate_test_vsc_sys(; rating_from = s, rating_to = s)
        model = _build_vsc_model(
            _vsc_nlp(), ACPNetworkModel, ipopt_optimizer; sys = sys,
        )
        @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
              IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        return IOM.get_optimization_container(model).optimizer_stats.objective_value
    end
    looser = _solve_with_rating(2.0)
    tighter = _solve_with_rating(1.0)
    @test tighter >= looser - 1e-6
end
