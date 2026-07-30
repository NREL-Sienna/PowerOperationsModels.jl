#! format: off
get_variable_binary(::Type{ActivePowerVariable}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = false
get_variable_warm_start_value(::Type{ActivePowerVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_active_power(d, PSY.SU)
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_active_power_limits(d, PSY.SU).min
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_variable_multiplier(::Type{<:VariableType}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = 1.0


function _get_flow_bounds(d::PSY.TModelHVDCLine)
    check_hvdc_line_limits_consistency(d)
    from_min = PSY.get_active_power_limits_from(d, PSY.SU).min
    to_min = PSY.get_active_power_limits_to(d, PSY.SU).min
    from_max = PSY.get_active_power_limits_from(d, PSY.SU).max
    to_max = PSY.get_active_power_limits_to(d, PSY.SU).max

    if from_min >= 0.0 && to_min >= 0.0
        min_rate = min(from_min, to_min)
    elseif from_min <= 0.0 && to_min <= 0.0
        min_rate = max(from_min, to_min)
    elseif from_min <= 0.0 && to_min >= 0.0
        min_rate = from_min
    elseif to_min <= 0.0 && from_min >= 0.0
        min_rate = to_min
    else
        @assert false
    end

    if from_max >= 0.0 && to_max >= 0.0
        max_rate = min(from_max, to_max)
    elseif from_max <= 0.0 && to_max <= 0.0
        max_rate = max(from_max, to_max)
    elseif from_max <= 0.0 && to_max >= 0.0
        max_rate = from_max
    elseif from_max >= 0.0 && to_max <= 0.0
        max_rate = to_max
    else
        @assert false
    end

    return min_rate, max_rate
end


get_variable_binary(::Type{FlowActivePowerVariable}, ::Type{PSY.TModelHVDCLine}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_binary(::Type{DCLineCurrent}, ::Type{PSY.TModelHVDCLine}, ::Type{<:AbstractBranchFormulation}) = false
get_variable_warm_start_value(::Type{FlowActivePowerVariable}, d::PSY.TModelHVDCLine, ::Type{<:AbstractBranchFormulation}) = PSY.get_active_power_flow(d, PSY.SU)
get_variable_lower_bound(::Type{FlowActivePowerVariable}, d::PSY.TModelHVDCLine, ::Type{<:AbstractBranchFormulation}) = _get_flow_bounds(d)[1]
get_variable_upper_bound(::Type{FlowActivePowerVariable}, d::PSY.TModelHVDCLine, ::Type{<:AbstractBranchFormulation}) = _get_flow_bounds(d)[2]

# This is an approximation for DC lines since the actual current limit depends on the voltage, that is a variable in the optimization problem
function get_variable_lower_bound(::Type{DCLineCurrent}, d::PSY.TModelHVDCLine, ::Type{<:AbstractBranchFormulation})
    p_min_flow = _get_flow_bounds(d)[1]
    arc = PSY.get_arc(d)
    bus_from = arc.from
    bus_to = arc.to
    max_v = max(PSY.get_magnitude(bus_from), PSY.get_magnitude(bus_to))
    return p_min_flow / max_v
end
# This is an approximation for DC lines since the actual current limit depends on the voltage, that is a variable in the optimization problem
function get_variable_upper_bound(::Type{DCLineCurrent}, d::PSY.TModelHVDCLine, ::Type{<:AbstractBranchFormulation})
    p_max_flow = _get_flow_bounds(d)[2]
    arc = PSY.get_arc(d)
    bus_from = arc.from
    bus_to = arc.to
    max_v = max(PSY.get_magnitude(bus_from), PSY.get_magnitude(bus_to))
    return p_max_flow / max_v
end
get_variable_multiplier(::Type{<:VariableType}, ::Type{PSY.TModelHVDCLine}, ::Type{<:AbstractBranchFormulation}) = 1.0

requires_initialization(::AbstractConverterFormulation) = false
requires_initialization(::LosslessLine) = false

function get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{PSY.InterconnectingConverter, <:AbstractConverterFormulation},
)
    return model
end

function get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{PSY.TModelHVDCLine, D},
) where {D <: AbstractDCLineFormulation}
    return model
end


function get_default_time_series_names(
    ::Type{PSY.InterconnectingConverter},
    ::Type{<:AbstractConverterFormulation},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_time_series_names(
    ::Type{PSY.TModelHVDCLine},
    ::Type{<:AbstractBranchFormulation},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{PSY.InterconnectingConverter},
    ::Type{<:AbstractConverterFormulation},
)
    return Dict{String, Any}()
end

function get_default_attributes(
    ::Type{PSY.InterconnectingConverter},
    ::Type{QuadraticLossConverter},
)
    return copy(BILINEAR_APPROX_DEFAULT_ATTRIBUTES)
end

function get_default_attributes(
    ::Type{PSY.InterconnectingConverter},
    ::Type{VoltageControlConverter},
)
    return copy(BILINEAR_APPROX_DEFAULT_ATTRIBUTES)
end

function get_default_attributes(
    ::Type{PSY.TModelHVDCLine},
    ::Type{<:AbstractBranchFormulation},
)
    return Dict{String, Any}()
end


############################################
######## Quadratic Converter Model #########
############################################

## Binaries ###
get_variable_binary(::Type{ConverterCurrent}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = false
get_variable_binary(::Type{CurrentAbsoluteValueVariable}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = false

### Warm Start ###
get_variable_warm_start_value(::Type{ConverterCurrent}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_dc_current(d, PSY.SU)

### Lower Bounds ###
get_variable_lower_bound(::Type{ConverterCurrent}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = -PSY.get_max_dc_current(d, PSY.SU)
get_variable_lower_bound(::Type{CurrentAbsoluteValueVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = 0.0

### Upper Bounds ###
get_variable_upper_bound(::Type{ConverterCurrent}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_max_dc_current(d, PSY.SU)
get_variable_upper_bound(::Type{CurrentAbsoluteValueVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_max_dc_current(d, PSY.SU)

# AC apparent-current variable (AC networks only): 0 ≤ I_ac ≤ S_max/vmin.
# Warm-started at the rated apparent current S_max (pu, at nominal voltage), which is
# strictly interior to (0, S_max/vmin). Seeding away from 0 is essential: at I_ac = 0
# the defining-relation gradient d(I_ac^2·V^2)/dI_ac = 2·I_ac·V^2 vanishes, so a
# zero start (which |P0| would give for an idle converter) is a degenerate point that
# traps Ipopt at a locally-infeasible restoration.
get_variable_binary(::Type{ConverterACCurrentVariable}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = false
get_variable_lower_bound(::Type{ConverterACCurrentVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = CONVERTER_AC_CURRENT_FLOOR
get_variable_upper_bound(::Type{ConverterACCurrentVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = _converter_ac_current_max(PSY.get_rating(d, PSY.SU), PSY.get_voltage_limits(PSY.get_bus(d)).min, PSY.get_name(d))
get_variable_warm_start_value(::Type{ConverterACCurrentVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = PSY.get_rating(d, PSY.SU)

#! format: on

##### AC-side reactive power (VoltageControlConverter) #####

# Dispatch-based finite-limit guard: a missing `reactive_power_limits` is a
# malformed-data error for an AC-side converter, surfaced here rather than as a
# downstream non-finite bound.
_require_reactive_limits(limits::NamedTuple, ::PSY.InterconnectingConverter) = limits
function _require_reactive_limits(::Nothing, d::PSY.InterconnectingConverter)
    return error(
        "InterconnectingConverter $(PSY.get_name(d)) has no reactive_power_limits; ",
        "VoltageControlConverter requires finite reactive_power_limits.",
    )
end

#! format: off
get_variable_binary(::Type{ReactivePowerVariable}, ::Type{PSY.InterconnectingConverter}, ::Type{<:AbstractConverterFormulation}) = false
get_variable_warm_start_value(::Type{ReactivePowerVariable}, ::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = 0.0
get_variable_lower_bound(::Type{ReactivePowerVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = _require_reactive_limits(PSY.get_reactive_power_limits(d, PSY.SU), d).min
get_variable_upper_bound(::Type{ReactivePowerVariable}, d::PSY.InterconnectingConverter, ::Type{<:AbstractConverterFormulation}) = _require_reactive_limits(PSY.get_reactive_power_limits(d, PSY.SU), d).max
#! format: on

############################################
############## Expressions #################
############################################

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: Union{ActivePowerBalance, DCCurrentBalance},
    U <: Union{FlowActivePowerVariable, DCLineCurrent},
    V <: PSY.TModelHVDCLine,
    W <: AbstractDCLineFormulation,
    X <: AbstractNetworkModel,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.DCBus)
    for d in devices
        arc = PSY.get_arc(d)
        to_bus_number = PSY.get_number(PSY.get_to(arc))
        from_bus_number = PSY.get_number(PSY.get_from(arc))
        for t in get_time_steps(container)
            name = PSY.get_name(d)
            add_proportional_to_jump_expression!(
                expression[to_bus_number, t],
                variable[name, t],
                1.0,
            )
            add_proportional_to_jump_expression!(
                expression[from_bus_number, t],
                variable[name, t],
                -1.0,
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractConverterFormulation,
    X <: NativeNodalNetworkModel,
}
    _add_to_expression!(
        container,
        T,
        U,
        devices,
        device_model,
        network_model,
    )
    return
end

function _add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractConverterFormulation,
    X <: AbstractNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_dc = get_expression(container, T, PSY.DCBus)
    expression_ac = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    for d in devices, t in get_time_steps(container)
        name = PSY.get_name(d)
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        bus_number_ac = PNM.get_mapped_bus_number(network_reduction, PSY.get_bus(d))
        add_proportional_to_jump_expression!(
            expression_ac[bus_number_ac, t],
            variable[name, t],
            1.0,
        )
        add_proportional_to_jump_expression!(
            expression_dc[bus_number_dc, t],
            variable[name, t],
            -1.0,
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractConverterFormulation,
    X <: AreaPTDFNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_dc = get_expression(container, T, PSY.DCBus)
    expression_ac = get_expression(container, T, PSY.ACBus)
    area_expr = get_expression(container, T, PSY.Area)
    network_reduction = get_network_reduction(network_model)
    multiplier = get_variable_multiplier(U, V, W)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        area_name = PSY.get_name(PSY.get_area(device_bus))
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        bus_number_ac = PNM.get_mapped_bus_number(network_reduction, device_bus)
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                area_expr[area_name, t],
                variable[name, t],
                multiplier,
            )
            add_proportional_to_jump_expression!(
                expression_ac[bus_number_ac, t],
                variable[name, t],
                multiplier,
            )
            add_proportional_to_jump_expression!(
                expression_dc[bus_number_dc, t],
                variable[name, t],
                -1.0,
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: DCCurrentBalance,
    U <: ConverterCurrent,
    V <: PSY.InterconnectingConverter,
    W <: AbstractQuadraticLossConverter,
    X <: NativeACNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_dc = get_expression(container, T, PSY.DCBus)
    for d in devices
        name = PSY.get_name(d)
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                expression_dc[bus_number_dc, t],
                variable[name, t],
                -1.0,
            )
        end
    end
    return
end

# AC networks: the converter active power injects into its AC bus's
# ActivePowerBalance only; the DC-side coupling is via ConverterCurrent ->
# DCCurrentBalance (VoltageDispatchHVDCNetworkModel has no DCBus ActivePowerBalance).
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractQuadraticLossConverter,
    X <: NativeACNetworkModel,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

# AC networks: the converter reactive injection enters ReactivePowerBalance at the
# converter's AC bus (+1.0 signed injection, via get_variable_multiplier == 1.0).
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ReactivePowerBalance,
    U <: ReactivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractConverterFormulation,
    X <: NativeACNetworkModel,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractConverterFormulation,
    X <: PTDFNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_dc = get_expression(container, T, PSY.DCBus)
    expression_ac = get_expression(container, T, PSY.ACBus)
    sys_expr = get_expression(container, T, PSY.System)
    network_reduction = get_network_reduction(network_model)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        bus_number_ac = PNM.get_mapped_bus_number(network_reduction, device_bus)
        ref_bus = get_reference_bus(network_model, device_bus)
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                sys_expr[ref_bus, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
            add_proportional_to_jump_expression!(
                expression_ac[bus_number_ac, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
            add_proportional_to_jump_expression!(
                expression_dc[bus_number_dc, t],
                variable[name, t],
                -1.0,
            )
        end
    end

    return
end

# QuadraticLossConverter under PTDF: the converter active power injects into the AC
# side only (System reference bus + ACBus). The DC-side coupling is ConverterCurrent ->
# DCCurrentBalance; VoltageDispatchHVDCNetworkModel builds no DCBus ActivePowerBalance,
# so — unlike the shared AbstractConverterFormulation method above — this must not touch
# it.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerVariable,
    V <: PSY.InterconnectingConverter,
    W <: AbstractQuadraticLossConverter,
    X <: PTDFNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_ac = get_expression(container, T, PSY.ACBus)
    sys_expr = get_expression(container, T, PSY.System)
    network_reduction = get_network_reduction(network_model)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        bus_number_ac = PNM.get_mapped_bus_number(network_reduction, device_bus)
        ref_bus = get_reference_bus(network_model, device_bus)
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                sys_expr[ref_bus, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
            add_proportional_to_jump_expression!(
                expression_ac[bus_number_ac, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: DCCurrentBalance,
    U <: ConverterCurrent,
    V <: PSY.InterconnectingConverter,
    W <: AbstractQuadraticLossConverter,
    X <: PTDFNetworkModel,
}
    variable = get_variable(container, U, V)
    expression_dc = get_expression(container, T, PSY.DCBus)
    for d in devices
        name = PSY.get_name(d)
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                expression_dc[bus_number_dc, t],
                variable[name, t],
                -1.0,
            )
        end
    end
    return
end

# LinearLossConverter: a loss function with a quadratic term cannot be represented;
# refuse it instead of silently dropping the `a·I²` term.
function _check_linear_converter_loss(d::PSY.InterconnectingConverter)
    loss_function = PSY.get_loss_function(d)
    a = _get_quadratic_term(loss_function)
    if !iszero(a)
        error(
            "InterconnectingConverter $(PSY.get_name(d)) has a loss function with a ",
            "non-zero quadratic term ($(a)); LinearLossConverter models only the ",
            "proportional and constant loss terms. Use QuadraticLossConverter or set ",
            "the quadratic term to zero.",
        )
    end
    return
end

# LinearLossConverter loss draw on the DC-side `ActivePowerBalance`: the AC/DC
# transfer keeps the lossless ±P wiring (shared `AbstractConverterFormulation`
# methods) and the loss `b·|I| + c` is an additional withdrawal at the DC bus.
# `CurrentAbsoluteValueVariable` is the nominal-voltage surrogate for `|I|`
# (`I ≈ P` at `v = 1` pu), pinned to `|P|` by cost minimization since the loss
# increases the required generation.
function _add_linear_converter_loss_to_dc_balance!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{PSY.InterconnectingConverter},
    ::NetworkModel{<:AbstractNetworkModel},
)
    expression_dc = get_expression(container, ActivePowerBalance, PSY.DCBus)
    abs_var =
        get_variable(container, CurrentAbsoluteValueVariable, PSY.InterconnectingConverter)
    system_base = get_model_base_power(container)
    for d in devices
        _check_linear_converter_loss(d)
        name = PSY.get_name(d)
        loss_function = PSY.get_loss_function(d)
        # Assumes the loss curve is authored in the converter device base (see PSY #1728,
        # unresolved): then `b` is base-invariant and only the constant `c` rescales to
        # system base. `|I|` is the system-base surrogate for `|P|`.
        base_factor = PSY.get_base_power(d, PSY.NU) / system_base
        b = PSY.get_proportional_term(loss_function)
        c = PSY.get_constant_term(loss_function) * base_factor
        bus_number_dc = PSY.get_number(PSY.get_dc_bus(d))
        for t in get_time_steps(container)
            iszero(b) || add_proportional_to_jump_expression!(
                expression_dc[bus_number_dc, t],
                abs_var[name, t],
                -b,
            )
            iszero(c) ||
                JuMP.add_to_expression!(expression_dc[bus_number_dc, t], -c)
        end
    end
    return
end

############################################
############## Constraints #################
############################################

############## HVDC Lines ##################
function add_constraints!(
    container::OptimizationContainer,
    ::Type{DCLineCurrentConstraint},
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    network_model::NetworkModel{V},
) where {T <: PSY.TModelHVDCLine, U <: DCLossyLine, V <: AbstractNetworkModel}
    variable = get_variable(container, DCLineCurrent, T)
    dc_voltage = get_variable(container, DCVoltage, PSY.DCBus)
    time_steps = get_time_steps(container)
    constraints = add_constraints_container!(container, DCLineCurrentConstraint,
        T,
        PSY.get_name.(devices),
        time_steps,
    )

    for d in devices
        arc = PSY.get_arc(d)
        from_bus_name = PSY.get_name(arc.from)
        to_bus_name = PSY.get_name(arc.to)
        name = PSY.get_name(d)
        # get_r on TModelHVDCLine is already pu (SYSTEM_BASE); single-arg getter, no unit marker — no PSY.SU conversion applies
        r = PSY.get_r(d)
        if iszero(r)
            for t in time_steps
                constraints[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    dc_voltage[from_bus_name, t] == dc_voltage[to_bus_name, t]
                )
            end
        else
            for t in get_time_steps(container)
                constraints[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    variable[name, t] ==
                    (dc_voltage[from_bus_name, t] - dc_voltage[to_bus_name, t]) / r
                )
            end
        end
    end
    return
end

############## Converters ##################

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ConverterLossConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    ::NetworkModel{X},
) where {
    U <: PSY.InterconnectingConverter,
    V <: AbstractQuadraticLossConverter,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    P_ac_var = get_variable(container, ActivePowerVariable, U)
    vi_expr = get_expression(container, IOM.BilinearProductExpression, U, "vi")
    i_sq_expr = get_expression(container, IOM.QuadraticExpression, U, "i_sq")
    abs_i_var = get_variable(container, CurrentAbsoluteValueVariable, U)

    ipc_names = [PSY.get_name(d) for d in devices]
    loss_const = add_constraints_container!(
        container, ConverterLossConstraint, U, ipc_names, time_steps,
    )

    jump_model = get_jump_model(container)
    for device in devices
        name = PSY.get_name(device)
        loss_function = PSY.get_loss_function(device)
        a = _get_quadratic_term(loss_function)
        b = PSY.get_proportional_term(loss_function)
        c = PSY.get_constant_term(loss_function)
        for t in time_steps
            loss = _quadratic_converter_loss_expr(
                a, b, c, i_sq_expr[name, t], abs_i_var[name, t],
            )
            loss_const[name, t] = JuMP.@constraint(
                jump_model,
                P_ac_var[name, t] == vi_expr[name, t] - loss,
            )
        end
    end
    return
end

# AC-network converter loss parameterized on the AC apparent current
# I_ac = sqrt(P_ac^2 + Q^2)/|V_ac| (Beerten/MATACDC VSC loss) so reactive loading
# incurs loss. The DC-side coupling P_ac == v*I_dc - loss is unchanged in structure;
# only the loss argument changes from I_dc to I_ac. The exact NLP defining relation
# I_ac^2 * V_ac^2 == P_ac^2 + Q^2 is built here. No integer/binary variables (Ipopt).
function add_constraints!(
    container::OptimizationContainer,
    ::Type{ConverterLossConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    network_model::NetworkModel{<:_ConverterACVoltageNetwork},
) where {U <: PSY.InterconnectingConverter, V <: AbstractQuadraticLossConverter}
    time_steps = get_time_steps(container)
    P_ac_var = get_variable(container, ActivePowerVariable, U)
    Q_var = get_variable(container, ReactivePowerVariable, U)
    vi_expr = get_expression(container, IOM.BilinearProductExpression, U, "vi")
    i_ac_var = get_variable(container, ConverterACCurrentVariable, U)
    v_arrays = _fetch_voltage_arrays(container, network_model)

    ipc_names = [PSY.get_name(d) for d in devices]
    loss_const = add_constraints_container!(
        container, ConverterLossConstraint, U, ipc_names, time_steps,
    )
    defn_const = add_constraints_container!(
        container, ConverterACCurrentConstraint, U, ipc_names, time_steps,
    )

    jump_model = get_jump_model(container)
    for device in devices
        name = PSY.get_name(device)
        bus_name = PSY.get_name(PSY.get_bus(device))
        loss_function = PSY.get_loss_function(device)
        a = _get_quadratic_term(loss_function)
        b = PSY.get_proportional_term(loss_function)
        c = PSY.get_constant_term(loss_function)
        for t in time_steps
            iac = i_ac_var[name, t]
            defn_const[name, t] = _converter_ac_current_definition(
                jump_model, iac, P_ac_var[name, t], Q_var[name, t], v_arrays, bus_name,
                t,
            )
            loss = _quadratic_converter_loss_expr(a, b, c, iac^2, iac)
            loss_const[name, t] = JuMP.@constraint(
                jump_model,
                P_ac_var[name, t] == vi_expr[name, t] - loss,
            )
        end
    end
    return
end

############################################
########### Objective Function #############
############################################

function add_to_objective_function!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{PSY.InterconnectingConverter},
    ::DeviceModel{PSY.InterconnectingConverter, D},
    ::Type{<:AbstractNetworkModel},
) where {D <: AbstractConverterFormulation}
    return
end
