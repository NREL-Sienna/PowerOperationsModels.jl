# InterconnectingConverter formulations across network models:
#   - LosslessConverter / LinearLossConverter / QuadraticLossConverter on the AC
#     networks (ACP/ACR/IVR/LPACC), with the reactive terminal layer.
#   - LinearLossConverter on every network model, with coefficient-level checks of
#     the linear loss draw at the DC bus.
#   - VoltageControlConverter and VoltageControlVSC on LPACC: the control layer
#     must exist (non-empty constraint containers) and pin the controlled
#     quantities, not silently no-op.

# sys10_pjm_ac_dc with the marginal cost of every side-2 thermal unit doubled so
# the optimum must move power across the DC ties (non-vacuous converter flows).
function _build_converter_sys(;
    loss = QuadraticCurve(0.0, 0.0, 0.0),
    reactive_limit = 1.5,
    ac_control = VSCACControlModes.AC_REACTIVE_POWER,
    ac_setpoint = 0.0,
    dc_control = VSCDCControlModes.DC_VOLTAGE,
    dc_setpoint = 1.0,
    dc_voltage_droop = 0.0,
    with_areas = false,
)
    sys = build_system(PSISystems, "sys10_pjm_ac_dc")
    for g in get_components(ThermalStandard, sys)
        endswith(get_name(g), "-2") || continue
        op_cost = get_operation_cost(g)
        val_curve = get_value_curve(PSY.get_variable(op_cost))
        new_op_cost = ThermalGenerationCost(
            CostCurve(
                QuadraticCurve(
                    get_quadratic_term(val_curve),
                    2.0 * get_proportional_term(val_curve),
                    get_constant_term(val_curve),
                ),
                get_power_units(PSY.get_variable(op_cost)),
                get_vom_cost(PSY.get_variable(op_cost)),
            ),
            get_fixed(op_cost),
            get_start_up(op_cost),
            get_shut_down(op_cost),
        )
        set_operation_cost!(g, new_op_cost)
    end
    for ic in get_components(InterconnectingConverter, sys)
        set_loss_function!(ic, loss)
        set_max_dc_current!(ic, 2.0 * PSY.SU)
        set_reactive_power_limits!(
            ic, (min = -reactive_limit * PSY.SU, max = reactive_limit * PSY.SU),
        )
        set_ac_control!(ic, ac_control)
        set_ac_setpoint!(ic, ac_setpoint)
        set_dc_control!(ic, dc_control)
        set_dc_setpoint!(ic, dc_setpoint)
        set_dc_voltage_droop!(ic, dc_voltage_droop)
    end
    if with_areas
        areas = [Area("Area_1", 0.0, 0.0, 0.0), Area("Area_2", 0.0, 0.0, 0.0)]
        for a in areas
            add_component!(sys, a)
        end
        for b in get_components(ACBus, sys)
            if get_number(b) <= 5
                set_area!(b, areas[1])
            else
                set_area!(b, areas[2])
            end
        end
    end
    return sys
end

function _converter_template(
    network,
    converter_model::DeviceModel;
    hvdc_model = TransportHVDCNetworkModel,
    line_formulation = LosslessLine,
)
    template = PowerOperationsProblemTemplate(NetworkModel(network))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, DeviceModel(TModelHVDCLine, line_formulation))
    set_device_model!(template, converter_model)
    set_hvdc_network_model!(template, hvdc_model)
    return template
end

function _build_converter_model(template, sys, optimizer)
    model = DecisionModel(
        template, sys; store_variable_names = true, optimizer = optimizer,
    )
    status = build!(model; output_dir = mktempdir(; cleanup = true))
    return model, status
end

_all_assigned(arr) = all(isassigned(arr.data, i) for i in eachindex(arr.data))

# AC-side (non-DC-bus) balance coefficient checks of a converter's
# ActivePowerVariable, by network model type. The converter must contribute +1.0
# to each of its AC-side balance rows.
function _assert_converter_ac_side(container, ic, v, t, ::Type{<:AbstractNetworkModel})
    expr = IOM.get_expression(container, ActivePowerBalance, ACBus)
    @test JuMP.coefficient(expr[get_number(get_bus(ic)), t], v) == 1.0
    return
end

function _assert_converter_ac_side(container, ic, v, t, ::Type{PTDFNetworkModel})
    sys_expr = IOM.get_expression(container, ActivePowerBalance, PSY.System)
    coefficients = [JuMP.coefficient(sys_expr[r, t], v) for r in axes(sys_expr)[1]]
    @test count(==(1.0), coefficients) == 1
    ac_expr = IOM.get_expression(container, ActivePowerBalance, ACBus)
    @test JuMP.coefficient(ac_expr[get_number(get_bus(ic)), t], v) == 1.0
    return
end

function _assert_converter_ac_side(container, ic, v, t, ::Type{AreaPTDFNetworkModel})
    area_expr = IOM.get_expression(container, ActivePowerBalance, Area)
    @test JuMP.coefficient(area_expr[get_name(get_area(get_bus(ic))), t], v) == 1.0
    ac_expr = IOM.get_expression(container, ActivePowerBalance, ACBus)
    @test JuMP.coefficient(ac_expr[get_number(get_bus(ic)), t], v) == 1.0
    return
end

# LinearLossConverter: assert the transport wiring and the linear loss draw at the
# DC bus. AreaBalance mirrors LosslessConverter and wires nothing.
function _assert_linear_loss_coefficients(container, sys, b_term, c_term, net)
    p = IOM.get_variable(container, ActivePowerVariable, InterconnectingConverter)
    abs_v =
        IOM.get_variable(container, CurrentAbsoluteValueVariable, InterconnectingConverter)
    dc_expr = IOM.get_expression(container, ActivePowerBalance, DCBus)
    for ic in get_components(InterconnectingConverter, sys)
        name = get_name(ic)
        dc_no = get_number(get_dc_bus(ic))
        for t in (1, size(p)[2])
            @test JuMP.coefficient(dc_expr[dc_no, t], p[name, t]) == -1.0
            @test JuMP.coefficient(dc_expr[dc_no, t], abs_v[name, t]) == -b_term
            @test JuMP.constant(dc_expr[dc_no, t]) == -c_term
            _assert_converter_ac_side(container, ic, p[name, t], t, net)
        end
    end
    cons = IOM.get_constraints(container)
    for meta in ("ge_pos", "ge_neg")
        key = ConstraintKey(
            POM.CurrentAbsoluteValueConstraint, InterconnectingConverter, meta,
        )
        @test haskey(cons, key)
        @test _all_assigned(cons[key])
    end
    return
end

@testset "LinearLossConverter wires P and the linear loss on active-power networks" begin
    b_term = 0.05
    c_term = 0.01
    for (net, optimizer) in (
        (PTDFNetworkModel, HiGHS_optimizer),
        (AreaPTDFNetworkModel, HiGHS_optimizer),
        (NFANetworkModel, HiGHS_optimizer),
        (DCPNetworkModel, HiGHS_optimizer),
        (DCPLLNetworkModel, ipopt_optimizer),
    )
        sys = _build_converter_sys(;
            loss = QuadraticCurve(0.0, b_term, c_term),
            with_areas = true,
        )
        template = _converter_template(
            net, DeviceModel(InterconnectingConverter, LinearLossConverter),
        )
        model, status = _build_converter_model(template, sys, optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        container = IOM.get_optimization_container(model)
        _assert_linear_loss_coefficients(container, sys, b_term, c_term, net)
    end
end

@testset "LinearLossConverter loss surrogate pins |P| at the optimum" begin
    b_term = 0.05
    c_term = 0.01
    sys = _build_converter_sys(; loss = QuadraticCurve(0.0, b_term, c_term))
    template = _converter_template(
        DCPNetworkModel, DeviceModel(InterconnectingConverter, LinearLossConverter),
    )
    model, status = _build_converter_model(template, sys, HiGHS_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container = IOM.get_optimization_container(model)
    p =
        JuMP.value.(
            IOM.get_variable(container, ActivePowerVariable, InterconnectingConverter).data,
        )
    abs_p =
        JuMP.value.(
            IOM.get_variable(
                container, CurrentAbsoluteValueVariable, InterconnectingConverter,
            ).data,
        )
    # The cost asymmetry forces a non-zero DC transfer, and the loss draw pins the
    # surrogate to |P| (an unpinned surrogate would make this vacuous).
    @test maximum(abs.(p)) > 1e-3
    @test isapprox(abs_p, abs.(p); atol = 1e-6)
end

@testset "LinearLossConverter rejects a quadratic loss function" begin
    sys = _build_converter_sys(; loss = QuadraticCurve(0.01, 0.05, 0.01))
    template = _converter_template(
        DCPNetworkModel, DeviceModel(InterconnectingConverter, LinearLossConverter),
    )
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    output_dir = mktempdir(; cleanup = true)
    @test build!(model; output_dir = output_dir) == IOM.ModelBuildStatus.FAILED
    log_text = ""
    for (root, _, files) in walkdir(output_dir)
        for f in files
            if f == "operation_problem.log"
                log_text = read(joinpath(root, f), String)
            end
        end
    end
    @test occursin("non-zero quadratic term", log_text)
end

_assert_formulation_specific(container, sys, b, c, net, ::Type{LosslessConverter}) =
    nothing
function _assert_formulation_specific(
    container, sys, b, c, net, ::Type{LinearLossConverter},
)
    _assert_linear_loss_coefficients(container, sys, b, c, net)
    return
end

@testset "LosslessConverter and LinearLossConverter on AC networks" begin
    b_term = 0.05
    c_term = 0.01
    for net in (ACPNetworkModel, ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)
        for formulation in (LosslessConverter, LinearLossConverter)
            sys = _build_converter_sys(; loss = QuadraticCurve(0.0, b_term, c_term))
            template = _converter_template(
                net, DeviceModel(InterconnectingConverter, formulation),
            )
            model, status = _build_converter_model(template, sys, ipopt_optimizer)
            @test status == IOM.ModelBuildStatus.BUILT
            container = IOM.get_optimization_container(model)
            p = IOM.get_variable(container, ActivePowerVariable, InterconnectingConverter)
            q = IOM.get_variable(
                container, ReactivePowerVariable, InterconnectingConverter,
            )
            ac_expr = IOM.get_expression(container, ActivePowerBalance, ACBus)
            reactive_expr = IOM.get_expression(container, ReactivePowerBalance, ACBus)
            dc_expr = IOM.get_expression(container, ActivePowerBalance, DCBus)
            for ic in get_components(InterconnectingConverter, sys)
                name = get_name(ic)
                bus_no = get_number(get_bus(ic))
                dc_no = get_number(get_dc_bus(ic))
                for t in (1, size(p)[2])
                    @test JuMP.coefficient(ac_expr[bus_no, t], p[name, t]) == 1.0
                    @test JuMP.coefficient(reactive_expr[bus_no, t], q[name, t]) == 1.0
                    @test JuMP.coefficient(dc_expr[dc_no, t], p[name, t]) == -1.0
                end
            end
            cons = IOM.get_constraints(container)
            disk_key = ConstraintKey(
                POM.ConverterPowerCapabilityConstraint, InterconnectingConverter,
            )
            @test haskey(cons, disk_key)
            @test _all_assigned(cons[disk_key])
            _assert_formulation_specific(
                container, sys, b_term, c_term, net, formulation,
            )
        end
    end
end

@testset "LosslessConverter solves on ACP and LPACC with reactive support" begin
    for net in (ACPNetworkModel, LPACCNetworkModel)
        sys = _build_converter_sys()
        template = _converter_template(
            net, DeviceModel(InterconnectingConverter, LosslessConverter),
        )
        model, status = _build_converter_model(template, sys, ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        container = IOM.get_optimization_container(model)
        p =
            JuMP.value.(
                IOM.get_variable(
                    container, ActivePowerVariable, InterconnectingConverter,
                ).data,
            )
        @test maximum(abs.(p)) > 1e-3
    end
end

_uses_ac_apparent_current(::Type{<:AbstractNetworkModel}) = true
_uses_ac_apparent_current(::Type{LPACCNetworkModel}) = false

@testset "QuadraticLossConverter on AC networks" begin
    for net in (ACPNetworkModel, ACRNetworkModel, IVRNetworkModel, LPACCNetworkModel)
        sys = _build_converter_sys(; loss = QuadraticCurve(0.01, 0.01, 0.0))
        template = _converter_template(
            net,
            DeviceModel(InterconnectingConverter, QuadraticLossConverter);
            hvdc_model = VoltageDispatchHVDCNetworkModel,
            line_formulation = DCLossyLine,
        )
        model, status = _build_converter_model(template, sys, ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        container = IOM.get_optimization_container(model)
        vars = IOM.get_variables(container)
        cons = IOM.get_constraints(container)

        q = IOM.get_variable(container, ReactivePowerVariable, InterconnectingConverter)
        i_dc = IOM.get_variable(container, ConverterCurrent, InterconnectingConverter)
        reactive_expr = IOM.get_expression(container, ReactivePowerBalance, ACBus)
        current_expr = IOM.get_expression(container, DCCurrentBalance, DCBus)
        for ic in get_components(InterconnectingConverter, sys)
            name = get_name(ic)
            bus_no = get_number(get_bus(ic))
            dc_no = get_number(get_dc_bus(ic))
            for t in (1, size(q)[2])
                @test JuMP.coefficient(reactive_expr[bus_no, t], q[name, t]) == 1.0
                @test JuMP.coefficient(current_expr[dc_no, t], i_dc[name, t]) == -1.0
            end
        end

        loss_key =
            ConstraintKey(POM.ConverterLossConstraint, InterconnectingConverter)
        @test haskey(cons, loss_key)
        @test _all_assigned(cons[loss_key])
        disk_key = ConstraintKey(
            POM.ConverterPowerCapabilityConstraint, InterconnectingConverter,
        )
        @test haskey(cons, disk_key)
        @test _all_assigned(cons[disk_key])

        has_ac_current = any(
            k -> occursin("ConverterACCurrentVariable", string(k)), keys(vars),
        )
        has_abs_current = any(
            k -> occursin("CurrentAbsoluteValueVariable", string(k)), keys(vars),
        )
        # LPACC keeps the DC-current loss (no AC magnitude primitive); the full AC
        # networks use the AC apparent-current loss.
        @test has_ac_current == _uses_ac_apparent_current(net)
        @test has_abs_current == !_uses_ac_apparent_current(net)
    end
end

@testset "QuadraticLossConverter solves on LPACC with the DC-current loss" begin
    sys = _build_converter_sys(; loss = QuadraticCurve(0.01, 0.01, 0.0))
    template = _converter_template(
        LPACCNetworkModel,
        DeviceModel(InterconnectingConverter, QuadraticLossConverter);
        hvdc_model = VoltageDispatchHVDCNetworkModel,
        line_formulation = DCLossyLine,
    )
    model, status = _build_converter_model(template, sys, ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    container = IOM.get_optimization_container(model)
    i_vals =
        JuMP.value.(
            IOM.get_variable(container, ConverterCurrent, InterconnectingConverter).data,
        )
    abs_vals =
        JuMP.value.(
            IOM.get_variable(
                container, CurrentAbsoluteValueVariable, InterconnectingConverter,
            ).data,
        )
    @test isapprox(abs_vals, abs.(i_vals); atol = 1e-5)
end

@testset "VoltageControlConverter LPACC control layer pins phi, Q, and vdc" begin
    v_sp = 1.01
    dc_sp = 1.0
    sys = _build_converter_sys(;
        loss = QuadraticCurve(0.01, 0.01, 0.0),
        ac_control = VSCACControlModes.AC_VOLTAGE,
        ac_setpoint = v_sp,
        dc_control = VSCDCControlModes.DC_VOLTAGE,
        dc_setpoint = dc_sp,
    )
    template = _converter_template(
        LPACCNetworkModel,
        DeviceModel(InterconnectingConverter, VoltageControlConverter);
        hvdc_model = VoltageDispatchHVDCNetworkModel,
        line_formulation = DCLossyLine,
    )
    model, status = _build_converter_model(template, sys, ipopt_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    cons = IOM.get_constraints(container)
    control_key =
        ConstraintKey(POM.HVDCDCControlConstraint, InterconnectingConverter)
    @test haskey(cons, control_key)
    @test _all_assigned(cons[control_key])
    loss_key = ConstraintKey(POM.ConverterLossConstraint, InterconnectingConverter)
    @test haskey(cons, loss_key)
    @test _all_assigned(cons[loss_key])

    # AC_VOLTAGE pins the LPACC voltage deviation phi = |V| - 1 at the converter bus.
    phi = IOM.get_variable(container, VoltageDeviation, ACBus)
    for ic in get_components(InterconnectingConverter, sys)
        bus_name = get_name(get_bus(ic))
        @test JuMP.is_fixed(phi[bus_name, 1])
        @test JuMP.fix_value(phi[bus_name, 1]) == v_sp - 1.0
    end

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    vdc = JuMP.value.(IOM.get_variable(container, DCVoltage, DCBus))
    for ic in get_components(InterconnectingConverter, sys)
        dc_bus = get_name(get_dc_bus(ic))
        for t in axes(vdc)[2]
            @test isapprox(vdc[dc_bus, t], dc_sp; atol = 1e-5)
        end
    end
end

@testset "VoltageControlConverter is count-invariant across AC control modes (LPACC)" begin
    function _lpacc_container_for_ac_mode(mode, setpoint)
        sys = _build_converter_sys(;
            loss = QuadraticCurve(0.01, 0.01, 0.0),
            ac_control = mode,
            ac_setpoint = setpoint,
        )
        template = _converter_template(
            LPACCNetworkModel,
            DeviceModel(InterconnectingConverter, VoltageControlConverter);
            hvdc_model = VoltageDispatchHVDCNetworkModel,
            line_formulation = DCLossyLine,
        )
        model, status = _build_converter_model(template, sys, ipopt_optimizer)
        @test status == IOM.ModelBuildStatus.BUILT
        return IOM.get_optimization_container(model)
    end

    c_v = _lpacc_container_for_ac_mode(VSCACControlModes.AC_VOLTAGE, 1.0)
    c_q = _lpacc_container_for_ac_mode(VSCACControlModes.AC_REACTIVE_POWER, 0.0)
    var_v = IOM.get_variables(c_v)
    var_q = IOM.get_variables(c_q)
    @test Set(keys(var_v)) == Set(keys(var_q))
    for k in keys(var_v)
        @test size(var_v[k]) == size(var_q[k])
    end
    con_v = IOM.get_constraints(c_v)
    con_q = IOM.get_constraints(c_q)
    @test Set(keys(con_v)) == Set(keys(con_q))
    for k in keys(con_v)
        @test size(con_v[k]) == size(con_q[k])
    end
end

# TwoTerminalVSCLine fixture: c_sys5_uc with one AC line replaced by a VSC line.
function _vsc_lpacc_sys(;
    ac_control_from = VSCACControlModes.AC_VOLTAGE,
    ac_setpoint_from = 1.02,
    dc_control_from = VSCDCControlModes.DC_VOLTAGE,
    dc_setpoint_from = 1.0,
    ac_control_to = VSCACControlModes.AC_REACTIVE_POWER,
    ac_setpoint_to = 0.0,
    dc_control_to = VSCDCControlModes.DC_POWER,
    dc_setpoint_to = 0.0,
)
    sys = build_system(PSITestSystems, "c_sys5_uc")
    line = get_component(Line, sys, "1")
    remove_component!(sys, line)
    vsc = TwoTerminalVSCLine(;
        name = get_name(line),
        available = true,
        arc = get_arc(line),
        active_power_flow = 0.0,
        rating = 2.0,
        active_power_limits_from = (min = -2.0, max = 2.0),
        active_power_limits_to = (min = -2.0, max = 2.0),
        g = 50.0,
        dc_current = 0.0,
        reactive_power_from = 0.0,
        dc_control_from = dc_control_from,
        ac_control_from = ac_control_from,
        dc_setpoint_from = dc_setpoint_from,
        ac_setpoint_from = ac_setpoint_from,
        converter_loss_from = QuadraticCurve(0.01, 0.0, 0.0),
        max_dc_current_from = 5.0,
        rating_from = 2.0,
        reactive_power_limits_from = (min = -2.0, max = 2.0),
        power_factor_weighting_fraction_from = 1.0,
        voltage_limits_from = (min = 0.95, max = 1.05),
        dc_voltage_droop_from = 0.0,
        reactive_power_to = 0.0,
        dc_control_to = dc_control_to,
        ac_control_to = ac_control_to,
        dc_setpoint_to = dc_setpoint_to,
        ac_setpoint_to = ac_setpoint_to,
        converter_loss_to = QuadraticCurve(0.01, 0.0, 0.0),
        max_dc_current_to = 5.0,
        rating_to = 2.0,
        reactive_power_limits_to = (min = -2.0, max = 2.0),
        power_factor_weighting_fraction_to = 1.0,
        voltage_limits_to = (min = 0.95, max = 1.05),
        dc_voltage_droop_to = 0.0,
    )
    add_component!(sys, vsc)
    return sys
end

@testset "VoltageControlVSC LPACC control layer pins phi, Q, and the DC quantities" begin
    v_sp = 1.02
    dc_sp = 1.0
    q_sp = 0.0
    p_sp = 0.0
    sys = _vsc_lpacc_sys(;
        ac_setpoint_from = v_sp,
        dc_setpoint_from = dc_sp,
        ac_setpoint_to = q_sp,
        dc_setpoint_to = p_sp,
    )
    template = PowerOperationsProblemTemplate(NetworkModel(LPACCNetworkModel))
    set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, DeviceModel(TwoTerminalVSCLine, VoltageControlVSC))
    model = DecisionModel(
        template, sys; store_variable_names = true, optimizer = ipopt_optimizer,
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    cons = IOM.get_constraints(container)
    for meta in ("from", "to")
        key = ConstraintKey(POM.HVDCDCControlConstraint, TwoTerminalVSCLine, meta)
        @test haskey(cons, key)
        @test _all_assigned(cons[key])
    end

    vsc = first(get_components(TwoTerminalVSCLine, sys))
    arc = get_arc(vsc)
    phi = IOM.get_variable(container, VoltageDeviation, ACBus)
    from_bus = get_name(get_from(arc))
    @test JuMP.is_fixed(phi[from_bus, 1])
    @test JuMP.fix_value(phi[from_bus, 1]) == v_sp - 1.0
    q_t = IOM.get_variable(container, POM.HVDCReactivePowerToVariable, TwoTerminalVSCLine)
    @test JuMP.is_fixed(q_t[get_name(vsc), 1])
    @test JuMP.fix_value(q_t[get_name(vsc), 1]) == q_sp

    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    v_f =
        JuMP.value.(
            IOM.get_variable(container, POM.HVDCFromDCVoltage, TwoTerminalVSCLine),
        )
    p_tf =
        JuMP.value.(
            IOM.get_variable(container, FlowActivePowerToFromVariable, TwoTerminalVSCLine),
        )
    name = get_name(vsc)
    for t in axes(v_f)[2]
        @test isapprox(v_f[name, t], dc_sp; atol = 1e-5)
        @test isapprox(p_tf[name, t], p_sp; atol = 1e-5)
    end
end

@testset "LinearLossConverter scales loss constant and current limit by converter base" begin
    # Converter base_power (50) != system base (100): the DC-side loss constant and the
    # DC-current limit are on the converter's own base and must be rescaled by
    # base_power/system_base = 0.5 into the system-base DC balance. The proportional loss
    # term is a base-invariant fraction and must not change.
    b_term = 0.05
    c_term = 0.01
    i_max = 2.0
    sys = _build_converter_sys(; loss = QuadraticCurve(0.0, b_term, c_term))
    system_base = get_base_power(sys)
    converter_base = 50.0
    for ic in get_components(InterconnectingConverter, sys)
        set_base_power!(ic, converter_base)
    end
    factor = converter_base / system_base

    template = _converter_template(
        DCPNetworkModel, DeviceModel(InterconnectingConverter, LinearLossConverter),
    )
    model, status = _build_converter_model(template, sys, HiGHS_optimizer)
    @test status == IOM.ModelBuildStatus.BUILT

    container = IOM.get_optimization_container(model)
    p = IOM.get_variable(container, ActivePowerVariable, InterconnectingConverter)
    abs_v =
        IOM.get_variable(container, CurrentAbsoluteValueVariable, InterconnectingConverter)
    dc_expr = IOM.get_expression(container, ActivePowerBalance, DCBus)
    for ic in get_components(InterconnectingConverter, sys)
        name = get_name(ic)
        dc_no = get_number(get_dc_bus(ic))
        @test JuMP.upper_bound(abs_v[name, 1]) == i_max * factor
        for t in (1, size(p)[2])
            @test JuMP.coefficient(dc_expr[dc_no, t], abs_v[name, t]) == -b_term
            @test JuMP.constant(dc_expr[dc_no, t]) == -c_term * factor
        end
    end
end

@testset "DCLosslessLine is removed" begin
    @test !isdefined(POM, :DCLosslessLine)
end
