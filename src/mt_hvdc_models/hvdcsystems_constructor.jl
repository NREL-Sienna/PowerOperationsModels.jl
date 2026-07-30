function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LosslessConverter},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
)
    devices = get_available_components(
        model,
        sys,
    )
    add_variables!(container, ActivePowerVariable, devices, LosslessConverter)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LosslessConverter},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
)
    devices = get_available_components(
        model,
        sys,
    )
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_constraint_dual!(container, sys, model)
    return
end

# Shared DC-side converter modeling (variables, current/loss machinery), reused by
# both the active-power-network construct and the AC-network VoltageControlConverter
# construct so the bilinear-loss logic lives in exactly one place.
# AC networks (ACP/ACR/IVR): the loss is parameterized on the AC apparent current.
function _add_converter_loss_current_var!(
    container::OptimizationContainer,
    devices,
    ::DeviceModel{PSY.InterconnectingConverter, F},
    ::NetworkModel{<:_ConverterACVoltageNetwork},
) where {F <: AbstractQuadraticLossConverter}
    add_variables!(container, ConverterACCurrentVariable, devices, F)
    return
end

# Active-power-only networks: |I_dc| LP surrogate for the DC-current loss.
function _add_converter_loss_current_var!(
    container::OptimizationContainer,
    devices,
    ::DeviceModel{PSY.InterconnectingConverter, F},
    ::NetworkModel{<:AbstractActivePowerModel},
) where {F <: AbstractQuadraticLossConverter}
    add_variables!(container, CurrentAbsoluteValueVariable, devices, F)
    return
end

# LPACC: the linearized voltage has no magnitude primitive compatible with the AC
# apparent-current relation, so keep the DC-current loss with the |I_dc| surrogate.
function _add_converter_loss_current_var!(
    container::OptimizationContainer,
    devices,
    ::DeviceModel{PSY.InterconnectingConverter, F},
    ::NetworkModel{LPACCNetworkModel},
) where {F <: AbstractQuadraticLossConverter}
    add_variables!(container, CurrentAbsoluteValueVariable, devices, F)
    return
end

# AC networks: the I_ac defining constraints are built inside the ConverterLossConstraint
# method, so nothing extra here.
_add_converter_loss_current_constraints!(
    ::OptimizationContainer,
    _devices,
    ::DeviceModel{PSY.InterconnectingConverter, <:AbstractQuadraticLossConverter},
    ::NetworkModel{<:_ConverterACVoltageNetwork},
) = nothing

# Active-power-only networks: the |I_dc| surrogate constraints feed the loss.
function _add_converter_loss_current_constraints!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{PSY.InterconnectingConverter, <:AbstractQuadraticLossConverter},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    _add_abs_value_constraints!(
        container, devices, model, network_model, ConverterCurrent,
    )
    return
end

# LPACC keeps the DC-current loss, so it needs the same |I_dc| surrogate constraints.
function _add_converter_loss_current_constraints!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{PSY.InterconnectingConverter, <:AbstractQuadraticLossConverter},
    network_model::NetworkModel{LPACCNetworkModel},
)
    _add_abs_value_constraints!(
        container, devices, model, network_model, ConverterCurrent,
    )
    return
end

function _add_converter_dc_arguments!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{PSY.InterconnectingConverter, F},
    network_model::NetworkModel,
) where {F <: AbstractQuadraticLossConverter}
    add_variables!(container, ActivePowerVariable, devices, F)
    add_variables!(container, ConverterCurrent, devices, F)
    _add_converter_loss_current_var!(container, devices, model, network_model)
    add_to_expression!(
        container, ActivePowerBalance, ActivePowerVariable,
        devices, model, network_model,
    )
    add_to_expression!(
        container, DCCurrentBalance, ConverterCurrent,
        devices, model, network_model,
    )
    return
end

function _add_converter_dc_model!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{PSY.InterconnectingConverter, F},
    network_model::NetworkModel,
) where {F <: AbstractQuadraticLossConverter}
    time_steps = get_time_steps(container)
    ipc_names = [PSY.get_name(d) for d in devices]
    v_bounds, i_bounds = _converter_vi_bounds(devices)
    v_expr = _voltage_expr_per_converter(container, devices, ipc_names, time_steps)
    i_var = get_variable(container, ConverterCurrent, PSY.InterconnectingConverter)

    quad_cfg, bilin_cfg = _build_converter_configs(F, model, v_bounds, i_bounds)
    # The loss term reads `i_sq`; build it once and reuse it for the bilinear.
    i_sq_expr = IOM._add_quadratic_approx!(
        quad_cfg,
        container, PSY.InterconnectingConverter,
        ipc_names, time_steps,
        i_var, i_bounds,
        "i_sq",
    )
    _add_converter_bilinear!(
        bilin_cfg, quad_cfg,
        container, PSY.InterconnectingConverter,
        ipc_names, time_steps,
        v_expr, i_var, i_sq_expr,
        v_bounds, i_bounds,
        "vi",
    )
    # The loss-current variable was added in the ArgumentConstructStage; on
    # active-power networks ConverterLossConstraint reads `abs_i`, so its constraints
    # must come first. On AC networks the I_ac defining constraint is built inside
    # ConverterLossConstraint itself.
    _add_converter_loss_current_constraints!(container, devices, model, network_model)
    add_constraints!(container, ConverterLossConstraint, devices, model, network_model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, T},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
) where {T <: AbstractQuadraticLossConverter}
    devices = get_available_components(model, sys)
    _add_converter_dc_arguments!(container, devices, model, network_model)
    add_feedforward_arguments!(container, model, devices)
    return
end

function _voltage_expr_per_converter(
    container::OptimizationContainer,
    devices,
    ipc_names::Vector{String},
    time_steps,
)
    v_var = get_variable(container, DCVoltage, PSY.DCBus)
    bus_names = [PSY.get_name(PSY.get_dc_bus(d)) for d in devices]
    return JuMP.Containers.DenseAxisArray(
        [v_var[b, t] for b in bus_names, t in time_steps],
        ipc_names, time_steps,
    )
end

function _converter_vi_bounds(devices)
    n = length(devices)
    v_bounds = Vector{IOM.MinMax}(undef, n)
    i_bounds = Vector{IOM.MinMax}(undef, n)
    for (k, d) in enumerate(devices)
        # bus voltage limits are already per-unit
        v_min, v_max = PSY.get_voltage_limits(PSY.get_dc_bus(d))
        i_max = PSY.get_max_dc_current(d, PSY.SU)
        v_bounds[k] = IOM.MinMax((min = v_min, max = v_max))
        i_bounds[k] = IOM.MinMax((min = -i_max, max = i_max))
    end
    return v_bounds, i_bounds
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, T},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
) where {T <: AbstractQuadraticLossConverter}
    devices = get_available_components(model, sys)
    _add_converter_dc_model!(container, devices, model, network_model)
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container, devices, model, get_network_formulation(network_model),
    )
    return
end

# AC networks (ACP/ACR/IVR/LPACC): same DC-side physics as the active-power-network
# construct plus the AC terminal layer — a bounded ReactivePowerVariable injected
# into ReactivePowerBalance and the apparent-power capability disk. The
# VoltageControlConverter construct (voltage_control_converter_models.jl) is more
# specific and adds the control layer on top of the same pieces.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, T},
    network_model::NetworkModel{<:NativeACNetworkModel},
) where {T <: AbstractQuadraticLossConverter}
    devices = get_available_components(model, sys)
    _add_converter_dc_arguments!(container, devices, model, network_model)
    _maybe_add_reactive_power_variables!(
        container, devices, model, network_model, (ReactivePowerVariable,),
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, T},
    network_model::NetworkModel{<:NativeACNetworkModel},
) where {T <: AbstractQuadraticLossConverter}
    devices = get_available_components(model, sys)
    _add_converter_dc_model!(container, devices, model, network_model)
    _add_ic_apparent_power_limit!(container, devices, model, network_model)
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container, devices, model, get_network_formulation(network_model),
    )
    add_constraint_dual!(container, sys, model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LosslessConverter},
    network_model::NetworkModel{<:NativeACNetworkModel},
)
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, LosslessConverter)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    _maybe_add_reactive_power_variables!(
        container, devices, model, network_model, (ReactivePowerVariable,),
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LosslessConverter},
    network_model::NetworkModel{<:NativeACNetworkModel},
)
    devices = get_available_components(model, sys)
    _add_ic_apparent_power_limit!(container, devices, model, network_model)
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_constraint_dual!(container, sys, model)
    return
end

# LinearLossConverter: lossless transport-style AC/DC transfer (±P wiring shared
# with LosslessConverter) plus a linear loss draw `b·|I| + c` at the DC bus, with
# `CurrentAbsoluteValueVariable` as the nominal-voltage `|I| ≈ |P|` surrogate.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LinearLossConverter},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
)
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, LinearLossConverter)
    add_variables!(container, CurrentAbsoluteValueVariable, devices, LinearLossConverter)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    _add_linear_converter_loss_to_dc_balance!(container, devices, network_model)
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LinearLossConverter},
    network_model::NetworkModel{<:AbstractDCPNetworkModel},
)
    devices = get_available_components(model, sys)
    _add_abs_value_constraints!(
        container, devices, model, network_model, ActivePowerVariable,
    )
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_constraint_dual!(container, sys, model)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LinearLossConverter},
    network_model::NetworkModel{<:NativeACNetworkModel},
)
    devices = get_available_components(model, sys)
    add_variables!(container, ActivePowerVariable, devices, LinearLossConverter)
    add_variables!(container, CurrentAbsoluteValueVariable, devices, LinearLossConverter)
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerVariable,
        devices,
        model,
        network_model,
    )
    _add_linear_converter_loss_to_dc_balance!(container, devices, network_model)
    _maybe_add_reactive_power_variables!(
        container, devices, model, network_model, (ReactivePowerVariable,),
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LinearLossConverter},
    network_model::NetworkModel{<:NativeACNetworkModel},
)
    devices = get_available_components(model, sys)
    _add_abs_value_constraints!(
        container, devices, model, network_model, ActivePowerVariable,
    )
    _add_ic_apparent_power_limit!(container, devices, model, network_model)
    add_feedforward_constraints!(container, model, devices)
    add_to_objective_function!(
        container,
        devices,
        model,
        get_network_formulation(network_model),
    )
    add_constraint_dual!(container, sys, model)
    return
end

# The transport line touches only the DC-bus ActivePowerBalance, so the AC-side
# network model is irrelevant: valid on every network model.
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.TModelHVDCLine, LosslessLine},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(
        model,
        sys,
    )
    add_variables!(container, FlowActivePowerVariable, devices, LosslessLine)
    add_to_expression!(
        container,
        ActivePowerBalance,
        FlowActivePowerVariable,
        devices,
        model,
        network_model,
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    ::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.TModelHVDCLine, LosslessLine},
    ::NetworkModel{<:AbstractNetworkModel},
)
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.TModelHVDCLine, DCLossyLine},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(
        model,
        sys,
    )

    add_variables!(container, DCLineCurrent, devices, DCLossyLine)
    add_to_expression!(
        container,
        DCCurrentBalance,
        DCLineCurrent,
        devices,
        model,
        network_model,
    )
    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.TModelHVDCLine, DCLossyLine},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(
        model,
        sys,
    )
    add_constraints!(
        container,
        DCLineCurrentConstraint,
        devices,
        model,
        network_model,
    )
end
