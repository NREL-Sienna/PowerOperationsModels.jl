#################################################################################
# Device-specific add_to_expression! implementations
# These extend the generic infrastructure from IOM with device-specific methods
#
# Note: Generic functions (add_expressions!, add_*_to_jump_expression!) are
# defined in IOM and imported by POM
#################################################################################

# Network model type mappings for system-level expressions
_system_expression_type(::Type{PTDFNetworkModel}) = PSY.System
_system_expression_type(::Type{CopperPlateNetworkModel}) = PSY.System
_system_expression_type(::Type{AreaPTDFNetworkModel}) = PSY.Area
_system_expression_type(::Type{AreaBalanceNetworkModel}) = PSY.Area

"""
Resolve, for a device under a given network model, the set of `(expression_matrix,
row_index)` entries that the device's injection contributes to.

This is the *only* axis on which the many device-injection `add_to_expression!` methods
differ; the `_add_*_to_balance!` helpers pair this resolver with a per-device term and
share [`_apply_term_to_targets!`](@ref) for the inner write, keeping the device/time loop
short. Dispatch is on disjoint network-model subtrees, so no ambiguity:

  - `<:AbstractNetworkModel` — nodal bus only (default AC models; also the
    security-constrained PTDF variants, matching prior variable-method behavior)
  - `CopperPlateNetworkModel` — system reference bus only
  - `AreaBalanceNetworkModel` — area only
  - `PTDFNetworkModel` / `AreaPTDFNetworkModel` — system/area entry plus nodal bus
"""
function _balance_expression_targets(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{<:AbstractNetworkModel},
    d::PSY.Component,
) where {T <: ExpressionType}
    bus_no =
        PNM.get_mapped_bus_number(get_network_reduction(network_model), PSY.get_bus(d))
    return ((get_expression(container, T, PSY.ACBus), bus_no),)
end

function _balance_expression_targets(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{CopperPlateNetworkModel},
    d::PSY.Component,
) where {T <: ExpressionType}
    ref_bus = get_reference_bus(network_model, PSY.get_bus(d))
    return ((get_expression(container, T, PSY.System), ref_bus),)
end

function _balance_expression_targets(
    container::OptimizationContainer,
    ::Type{T},
    ::NetworkModel{AreaBalanceNetworkModel},
    d::PSY.Component,
) where {T <: ExpressionType}
    area_name = PSY.get_name(PSY.get_area(PSY.get_bus(d)))
    return ((get_expression(container, T, PSY.Area), area_name),)
end

function _balance_expression_targets(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{X},
    d::PSY.Component,
) where {T <: ExpressionType, X <: Union{PTDFNetworkModel, AreaPTDFNetworkModel}}
    bus = PSY.get_bus(d)
    bus_no = PNM.get_mapped_bus_number(get_network_reduction(network_model), bus)
    ref_index = _ref_index(network_model, bus)
    return (
        (get_expression(container, T, _system_expression_type(X)), ref_index),
        (get_expression(container, T, PSY.ACBus), bus_no),
    )
end

const _BalanceTermValue = Union{Float64, JuMP.AbstractJuMPScalar}

"""
Apply a `value * multiplier` term to each `(expression_matrix, row_index)` target a device
contributes to, as resolved by [`_balance_expression_targets`](@ref): one target for
single-bus/area/system network models, two for PTDF/AreaPTDF (a nodal entry plus a
system/area entry).

Tail recursion keeps the heterogeneous length-1/length-2 tuples type stable; the compiler
unrolls it.
"""
_apply_term_to_targets!(::Tuple{}, ::_BalanceTermValue, ::Float64, ::Int) = nothing

function _apply_term_to_targets!(
    targets::Tuple,
    value::_BalanceTermValue,
    multiplier::Float64,
    t::Int,
)
    expression, row = targets[1]
    add_proportional_to_jump_expression!(expression[row, t], value, multiplier)
    return _apply_term_to_targets!(Base.tail(targets), value, multiplier, t)
end

"""
Constant device power for a `StaticPowerLoad`-style injection. Active vs reactive is
already encoded in the balance-expression type, so it is resolved by dispatch rather than
by passing a getter.
"""
_constant_power(::Type{<:ActivePowerBalance}, d) = PSY.get_active_power(d, PSY.SU)
_constant_power(::Type{<:ReactivePowerBalance}, d) = PSY.get_reactive_power(d, PSY.SU)

"""
Add a device variable to a balance expression for any network model. Targets come from
[`_balance_expression_targets`](@ref) and the inner write from
[`_apply_term_to_targets!`](@ref); the contributed term is
`get_variable_multiplier(U, V, W) * variable[name, t]`.
"""
function _add_variable_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: VariableType, V <: PSY.StaticInjection, W}
    variable = get_variable(container, U, V)
    multiplier = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        for t in time_steps
            _apply_term_to_targets!(targets, variable[name, t], multiplier, t)
        end
    end
    return
end

"""
Add a device time-series parameter to a balance expression. The contributed term is
`multiplier[name, t] * parameter[name, t]`, with targets from
[`_balance_expression_targets`](@ref).
"""
function _add_ts_parameter_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: TimeSeriesParameter, V <: PSY.Device, W}
    param_container = get_parameter(container, U, V)
    multiplier = get_multiplier_array(param_container)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        refs = get_parameter_column_refs(param_container, name)
        for t in time_steps
            _apply_term_to_targets!(targets, refs[t], multiplier[name, t], t)
        end
    end
    return
end

"""
Add an electric-load time-series parameter to a balance expression. Mirrors
[`_add_ts_parameter_to_balance!`](@ref) but falls back to a unit value scaled by
`get_multiplier_value(U, d, W)` (with a warning) when a device lacks the time series.
"""
function _add_load_ts_parameter_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    model::DeviceModel{V, W},
) where {T <: ExpressionType, U <: TimeSeriesParameter, V <: PSY.ElectricLoad, W}
    param_container = get_parameter(container, U, V)
    multiplier = get_multiplier_array(param_container)
    ts_name = get_time_series_names(model)[U]
    ts_type = get_default_time_series_type(container)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        if PSY.has_time_series(d, ts_type, ts_name)
            refs = get_parameter_column_refs(param_container, name)
            for t in time_steps
                _apply_term_to_targets!(targets, refs[t], multiplier[name, t], t)
            end
        else
            @warn "Device $(name) does not have time series of type $(ts_type) with name $(ts_name). Using default value of 1.0 for all time steps."
            fallback_multiplier = get_multiplier_value(U, d, W)
            for t in time_steps
                _apply_term_to_targets!(targets, 1.0, fallback_multiplier, t)
            end
        end
    end
    return
end

"""
Add a constant device power (e.g. a `StaticPowerLoad` motor load) to a balance
expression with multiplier `-1.0`. Active vs reactive power is selected by the expression
type `T` via [`_constant_power`](@ref); targets come from
[`_balance_expression_targets`](@ref).
"""
function _add_constant_power_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
) where {T <: ExpressionType, V <: PSY.Component}
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        value = _constant_power(T, d)
        for t in time_steps
            _apply_term_to_targets!(targets, value, -1.0, t)
        end
    end
    return
end

#################################################################################
# Branch/HVDC directional-flow helpers
#
# Branch and HVDC flow variables enter the balance expressions at one or both
# terminal buses (and, for PTDF/CopperPlate, at the reference bus when the arc
# crosses subnetworks). The many `add_to_expression!` methods below differ only
# along a few axes — which terminal, the sign, and whether the system/area row
# also receives the term — so they share these helpers and become thin wrappers.
#
# Which terminal a directional flow variable lands on is fixed by the variable
# name (`FromTo`/`ReceivedFrom`/VSC `From` -> from-bus; `ToFrom`/`ReceivedTo`/VSC
# `To` -> to-bus), so it is resolved by dispatch on the variable type rather than
# passed as an argument. This invariant holds for the branch and HVDC paths below;
# the exception is `_add_hvdc_copperplate_flow!`, which hardcodes `sys_expr[ref_bus_to]`
# for both flow directions (the copperplate subnetwork balance requires the to-side
# reference bus regardless of variable direction). The sign is physics, not naming
# (e.g. LCC converters consume reactive at both ends), so `multiplier` stays explicit.
# (Longer term, a PSY branch-directionality type could replace these `_terminal_bus`
# selectors.)
#################################################################################

"""
Select the bus of `arc` that a directional flow variable lands on: from-side variables
(`FromTo` / `ReceivedFrom` / VSC `From`) resolve to the from-bus, to-side variables
(`ToFrom` / `ReceivedTo` / VSC `To`) to the to-bus.

The terminal is fixed by the variable type, so it is resolved by dispatch rather than
passed as an argument. One method per variable type (rather than a 5-member `Union` per
side, which exceeds the union-splitting threshold).
"""
_terminal_bus(::Type{FlowActivePowerFromToVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{FlowReactivePowerFromToVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{HVDCActivePowerReceivedFromVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{HVDCRectifierActivePowerVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{HVDCRectifierReactivePowerVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{HVDCReactivePowerFromVariable}, arc) = PSY.get_from(arc)
_terminal_bus(::Type{FlowActivePowerToFromVariable}, arc) = PSY.get_to(arc)
_terminal_bus(::Type{FlowReactivePowerToFromVariable}, arc) = PSY.get_to(arc)
_terminal_bus(::Type{HVDCActivePowerReceivedToVariable}, arc) = PSY.get_to(arc)
_terminal_bus(::Type{HVDCInverterActivePowerVariable}, arc) = PSY.get_to(arc)
_terminal_bus(::Type{HVDCInverterReactivePowerVariable}, arc) = PSY.get_to(arc)
_terminal_bus(::Type{HVDCReactivePowerToVariable}, arc) = PSY.get_to(arc)

# Reduced-arc twins of `_terminal_bus`: a reduction entry's terminal is an end of its
# `(from_no, to_no)` arc tuple (already retained bus numbers), not a PSY bus object.
_terminal_arc_end(
    ::Type{<:Union{FlowActivePowerFromToVariable, FlowReactivePowerFromToVariable}},
    arc_tuple::Tuple{Int, Int},
) = arc_tuple[1]

_terminal_arc_end(
    ::Type{<:Union{FlowActivePowerToFromVariable, FlowReactivePowerToFromVariable}},
    arc_tuple::Tuple{Int, Int},
) = arc_tuple[2]

"""
Add a single directional branch/HVDC terminal flow variable to a nodal balance
expression. The terminal bus is fixed by the variable type `U` via
[`_terminal_bus`](@ref) and `multiplier` is the signed nodal contribution. Shared
by the ACP branch-flow methods and the HVDC LCC/VSC terminal methods.
"""
function _add_terminal_flow_to_nodal!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    multiplier::Float64,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.Component}
    _add_terminal_flow_to_nodal_by_device!(
        container, T, U, devices, network_model, multiplier,
    )
    return
end

# AC transmission under an active network reduction: variables are keyed by reduction-entry
# name and shared per reduced arc (across entries and branch types), so each arc's variable
# enters the balance exactly once, at its reduced-arc terminal (a retained bus number).
function _add_terminal_flow_to_nodal!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    multiplier::Float64,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.ACTransmission}
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        _add_terminal_flow_to_nodal_by_device!(
            container, T, U, devices, network_model, multiplier,
        )
        return
    end
    var = get_variable(container, U, V)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    tracker = get_reduced_branch_tracker(network_model)
    time_steps = get_time_steps(container)
    for (name, (arc_tuple, _)) in get_name_to_arc_map_entries(network_reduction, V)
        if search_for_reduced_branch_expression!(tracker, arc_tuple, T, U)
            continue
        end
        bus_no = _terminal_arc_end(U, arc_tuple)
        for t in time_steps
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                var[name, t],
                multiplier,
            )
        end
    end
    return
end

function _add_terminal_flow_to_nodal_by_device!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    multiplier::Float64,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.Component}
    var = get_variable(container, U, V)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no =
            PNM.get_mapped_bus_number(network_reduction, _terminal_bus(U, PSY.get_arc(d)))
        for t in time_steps
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                var[name, t],
                multiplier,
            )
        end
    end
    return
end

"""
Add a lossless branch/HVDC flow variable to both terminal nodal balances:
`-1.0` at the from-bus (power leaves) and `+1.0` at the to-bus.
"""
function _add_both_terminals_to_nodal!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.Component}
    _add_both_terminals_to_nodal_by_device!(container, T, U, devices, network_model)
    return
end

# AC transmission under an active network reduction: variables are keyed by reduction-entry
# name and shared per reduced arc (across entries and branch types), so each arc's variable
# enters the balances exactly once, at the reduced arc's retained endpoints.
function _add_both_terminals_to_nodal!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.ACTransmission}
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        _add_both_terminals_to_nodal_by_device!(container, T, U, devices, network_model)
        return
    end
    var = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.ACBus)
    tracker = get_reduced_branch_tracker(network_model)
    time_steps = get_time_steps(container)
    for (name, (arc_tuple, _)) in get_name_to_arc_map_entries(network_reduction, V)
        if search_for_reduced_branch_expression!(tracker, arc_tuple, T, U)
            continue
        end
        for t in time_steps
            flow_variable = var[name, t]
            add_proportional_to_jump_expression!(
                expression[arc_tuple[1], t],
                flow_variable,
                -1.0,
            )
            add_proportional_to_jump_expression!(
                expression[arc_tuple[2], t],
                flow_variable,
                1.0,
            )
        end
    end
    return
end

function _add_both_terminals_to_nodal_by_device!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.Component}
    var = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_from =
            PNM.get_mapped_bus_number(network_reduction, PSY.get_from(PSY.get_arc(d)))
        bus_no_to = PNM.get_mapped_bus_number(network_reduction, PSY.get_to(PSY.get_arc(d)))
        for t in time_steps
            flow_variable = var[name, t]
            add_proportional_to_jump_expression!(
                expression[bus_no_from, t],
                flow_variable,
                -1.0,
            )
            add_proportional_to_jump_expression!(
                expression[bus_no_to, t],
                flow_variable,
                1.0,
            )
        end
    end
    return
end

"""
Add a single directional HVDC flow variable to both the nodal and the
system/area balance of a PTDF network. The variable contributes `multiplier` at
the chosen terminal's nodal bus, and the same at that terminal's reference bus
when the arc crosses subnetworks. The terminal (from/to) is fixed by the variable
type `U` via [`_terminal_bus`](@ref) for both the nodal and reference-bus entry.
"""
function _add_terminal_flow_to_ptdf_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel{X},
    multiplier::Float64,
) where {
    T <: ExpressionType,
    U <: VariableType,
    V <: PSY.Component,
    X <: AbstractPTDFNetworkModel,
}
    var = get_variable(container, U, V)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    sys_expr = get_expression(container, T, _system_expression_type(X))
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        arc = PSY.get_arc(d)
        side_bus = _terminal_bus(U, arc)
        bus_no = PNM.get_mapped_bus_number(network_reduction, side_bus)
        # System/area row key: `_ref_index` yields the reference-bus number for
        # PTDF (System-keyed) and the area name for AreaPTDF (Area-keyed). The
        # `ref_bus_from != ref_bus_to` crossing check uses raw reference numbers.
        ref_index = _ref_index(network_model, side_bus)
        ref_bus_from = get_reference_bus(network_model, PSY.get_from(arc))
        ref_bus_to = get_reference_bus(network_model, PSY.get_to(arc))
        for t in time_steps
            flow_variable = var[name, t]
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                flow_variable,
                multiplier,
            )
            if ref_bus_from != ref_bus_to
                add_proportional_to_jump_expression!(
                    sys_expr[ref_index, t],
                    flow_variable,
                    multiplier,
                )
            end
        end
    end
    return
end

"""
Add an HVDC flow variable to a CopperPlate system balance. The flow only matters
across subnetworks (it leaves one reference bus and arrives at another), so it
contributes `multiplier` at the to-side reference bus for inter-subnetwork arcs.
"""
function _add_hvdc_copperplate_flow!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel{CopperPlateNetworkModel},
    multiplier::Float64,
) where {T <: ExpressionType, U <: VariableType, V <: PSY.Component}
    has_subnetworks(network_model) || return
    var = get_variable(container, U, V)
    sys_expr = get_expression(container, T, PSY.System)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        ref_bus_from = get_reference_bus(network_model, PSY.get_from(PSY.get_arc(d)))
        ref_bus_to = get_reference_bus(network_model, PSY.get_to(PSY.get_arc(d)))
        ref_bus_from == ref_bus_to && continue
        for t in time_steps
            add_proportional_to_jump_expression!(
                sys_expr[ref_bus_to, t],
                var[name, t],
                multiplier,
            )
        end
    end
    return
end

"""
Default implementation to add parameters to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.Device,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    _add_ts_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

"""
Generic electric load implementation to add parameters to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.ElectricLoad,
    W <: AbstractLoadFormulation,
    X <: AbstractNetworkModel,
}
    _add_load_ts_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

"""
Motor load implementation to add constant power to ActivePowerBalance expression
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerTimeSeriesParameter,
    V <: PSY.MotorLoad,
    W <: StaticPowerLoad,
    X <: AbstractNetworkModel,
}
    _add_constant_power_to_balance!(
        container,
        T,
        devices,
        network_model,
    )
    return
end

"""
Motor load implementation to add constant power to ActivePowerBalance expression for AreaBalanceNetworkModel
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerTimeSeriesParameter,
    V <: PSY.MotorLoad,
    W <: StaticPowerLoad,
}
    _add_constant_power_to_balance!(
        container,
        T,
        devices,
        network_model,
    )
    return
end

"""
Motor load implementation to add constant power to ActivePowerBalance expression
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ReactivePowerBalance,
    U <: ReactivePowerTimeSeriesParameter,
    V <: PSY.MotorLoad,
    W <: StaticPowerLoad,
    X <: ACPNetworkModel,
}
    _add_constant_power_to_balance!(
        container,
        T,
        devices,
        network_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.Device,
    W <: AbstractDeviceFormulation,
}
    _add_ts_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.ElectricLoad,
    W <: AbstractLoadFormulation,
}
    _add_load_ts_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

"""
Default implementation to add device variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: VariableType,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: VariableType,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, model)
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions.

Handles HVDCs internal to a subnetwork, by subtracting losses from power in subnetwork.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: HVDCLosses,
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalDispatch,
    X <: Union{PTDFNetworkModel, CopperPlateNetworkModel},
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.System)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        device_bus_from = PSY.get_from(PSY.get_arc(d))
        device_bus_to = PSY.get_to(PSY.get_arc(d))
        ref_bus_from = get_reference_bus(network_model, device_bus_from)
        ref_bus_to = get_reference_bus(network_model, device_bus_to)
        if ref_bus_from == ref_bus_to
            for t in time_steps
                add_proportional_to_jump_expression!(
                    expression[ref_bus_from, t],
                    variable[name, t],
                    get_variable_multiplier(U, V, W),
                )
            end
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
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: HVDCLosses,
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalDispatch,
    X <: Union{AreaPTDFNetworkModel, AreaBalanceNetworkModel},
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.Area)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        device_bus_from = PSY.get_from(PSY.get_arc(d))
        area_name = PSY.get_name(PSY.get_area(device_bus_from))
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[area_name, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
        end
    end
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{PTDFNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerToFromVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractTwoTerminalDCLineFormulation,
}
    _add_terminal_flow_to_ptdf_balance!(
        container, T, U, devices, network_model, -1.0,
    )
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerFromToVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractTwoTerminalDCLineFormulation,
    X <: AbstractPTDFNetworkModel,
}
    _add_terminal_flow_to_ptdf_balance!(
        container, T, U, devices, network_model, -1.0,
    )
    return
end

"""
PWL implementation to add received HVDC branch variables to SystemBalanceExpressions.
Both received terminals contribute +1.0 at their terminal's nodal and system rows;
the from/to terminal is resolved from the variable type.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: Union{HVDCActivePowerReceivedFromVariable, HVDCActivePowerReceivedToVariable},
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalPiecewiseLoss,
    X <: AbstractPTDFNetworkModel,
}
    _add_terminal_flow_to_ptdf_balance!(
        container, T, U, devices, network_model, 1.0,
    )
    return
end

"""
PWL received HVDC contribution to the CopperPlate system balance. Each received
terminal contributes +1.0 at its own terminal's reference-bus row, so a line whose
terminals share one subnetwork nets out to -(losses) and a line crossing subnetworks
transfers the sent/received power between the rows with the loss included.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: Union{HVDCActivePowerReceivedFromVariable, HVDCActivePowerReceivedToVariable},
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalPiecewiseLoss,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.System)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        ref_bus = get_reference_bus(network_model, _terminal_bus(U, PSY.get_arc(d)))
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[ref_bus, t],
                variable[name, t],
                1.0,
            )
        end
    end
    return
end

"""
PWL received HVDC contribution to the AreaBalance area balances. Each received terminal
contributes +1.0 at its own terminal's area row: a line crossing areas is a genuine
inter-area interchange (with the loss included), and a line internal to one area nets
out to -(losses).
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: Union{HVDCActivePowerReceivedFromVariable, HVDCActivePowerReceivedToVariable},
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalPiecewiseLoss,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.Area)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        area_name = PSY.get_name(PSY.get_area(_terminal_bus(U, PSY.get_arc(d))))
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[area_name, t],
                variable[name, t],
                1.0,
            )
        end
    end
    return
end

"""
HVDC LCC implementation to add ActivePowerBalance expression for HVDCRectifierActivePowerVariable variable
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,                        # expression
    U <: HVDCRectifierActivePowerVariable,          # variable
    V <: PSY.TwoTerminalHVDC,                      # power system type
    W <: HVDCTwoTerminalLCC,                        # formulation
    X <: AbstractReactivePowerNetworkModel,                  # network model
}
    _add_terminal_flow_to_nodal!(
        container, T, U, devices, network_model, -1.0,
    )
    return
end

"""
HVDC LCC implementation to add ActivePowerBalance expression for HVDCInverterActivePowerVariable variable
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: HVDCInverterActivePowerVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalLCC,
    X <: AbstractReactivePowerNetworkModel,
}
    _add_terminal_flow_to_nodal!(
        container, T, U, devices, network_model, 1.0,
    )
    return
end

"""
HVDC LCC: both terminals' reactive power consumption is consumed at their own bus (-1.0)
in ReactivePowerBalance. The rectifier/inverter terminal is resolved from the variable type.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ReactivePowerBalance,
    U <: Union{HVDCRectifierReactivePowerVariable, HVDCInverterReactivePowerVariable},
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalLCC,
    X <: AbstractReactivePowerNetworkModel,
}
    _add_terminal_flow_to_nodal!(
        container, T, U, devices, network_model, -1.0,
    )
    return
end

# A VSC terminal can inject or consume Q freely, so the variable enters
# `ReactivePowerBalance` as a signed injection (+1.0) rather than a load (−1.0).
# The from/to terminal is resolved by `_terminal_bus` on the variable type.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ReactivePowerBalance,
    U <: Union{HVDCReactivePowerFromVariable, HVDCReactivePowerToVariable},
    V <: PSY.TwoTerminalVSCLine,
    W <: AbstractTwoTerminalVSCFormulation,
    X <: NativeACNetworkModel,
}
    _add_terminal_flow_to_nodal!(container, T, U, devices, network_model, 1.0)
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerToFromVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractTwoTerminalDCLineFormulation,
    X <: CopperPlateNetworkModel,
}
    _add_hvdc_copperplate_flow!(container, T, U, devices, network_model, 1.0)
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerFromToVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractTwoTerminalDCLineFormulation,
    X <: CopperPlateNetworkModel,
}
    _add_hvdc_copperplate_flow!(container, T, U, devices, network_model, -1.0)
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerFromToVariable,
    V <: PSY.Branch,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_ = PSY.get_number(PSY.get_from(PSY.get_arc(d)))
        bus_no = PNM.get_mapped_bus_number(network_reduction, bus_no_)
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[bus_no, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
        end
    end
    return
end

"""
Default implementation to add branch variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerToFromVariable,
    V <: PSY.ACBranch,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_ = PSY.get_number(PSY.get_to(PSY.get_arc(d)))
        bus_no = PNM.get_mapped_bus_number(network_reduction, bus_no_)
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[bus_no, t],
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
    ::DeviceModel{V, HVDCTwoTerminalDispatch},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerToFromVariable,
    V <: PSY.TwoTerminalHVDC,
}
    variable = get_variable(container, U, V)
    expression = get_expression(container, T, PSY.Area)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        area_name = PSY.get_name(PSY.get_area(PSY.get_to(PSY.get_arc(d))))
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[area_name, t],
                variable[name, t],
                get_variable_multiplier(U, V, HVDCTwoTerminalDispatch),
            )
        end
    end
    return
end

"""
Default implementation to add parameters to Copperplate SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
}
    _add_ts_parameter_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

"""
Electric Load implementation to add parameters to Copperplate SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.ElectricLoad,
    W <: AbstractLoadFormulation,
}
    _add_load_ts_parameter_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

"""
Motor load implementation to add parameters to SystemBalanceExpressions CopperPlate
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerTimeSeriesParameter,
    V <: PSY.MotorLoad,
    W <: StaticPowerLoad,
}
    _add_constant_power_to_balance!(
        container,
        T,
        devices,
        network_model,
    )
    return
end

"""
Default implementation to add variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: VariableType,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

"""
Default implementation to add parameters to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: AbstractPTDFNetworkModel,
}
    param_container = get_parameter(container, U, V)
    multiplier = get_multiplier_array(param_container)
    sys_expr = get_expression(container, T, _system_expression_type(X))
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        bus_no = PNM.get_mapped_bus_number(network_reduction, PSY.get_number(device_bus))
        ref_index = _ref_index(network_model, device_bus)
        param = get_parameter_column_refs(param_container, name)
        for t in time_steps
            add_proportional_to_jump_expression!(
                sys_expr[ref_index, t],
                param[t],
                multiplier[name, t],
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                param[t],
                multiplier[name, t],
            )
        end
    end
    return
end

"""
Electric Load implementation to add parameters to PTDF SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: TimeSeriesParameter,
    V <: PSY.ElectricLoad,
    W <: AbstractLoadFormulation,
    X <: AbstractPTDFNetworkModel,
}
    param_container = get_parameter(container, U, V)
    multiplier = get_multiplier_array(param_container)
    sys_expr = get_expression(container, T, _system_expression_type(X))
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    ts_name = get_time_series_names(device_model)[U]
    ts_type = get_default_time_series_type(container)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        has_ts = PSY.has_time_series(d, ts_type, ts_name)
        if !has_ts
            @warn "Device $(name) does not have time series of type $(ts_type) with name $(ts_name). Using default value of 1.0 for all time steps."
        end
        device_bus = PSY.get_bus(d)
        bus_no_ = PSY.get_number(device_bus)
        bus_no = PNM.get_mapped_bus_number(network_reduction, bus_no_)
        ref_index = _ref_index(network_model, device_bus)
        for t in time_steps
            if has_ts
                param = get_parameter_column_refs(param_container, name)[t]
                mult = multiplier[name, t]
            else
                param = 1.0
                mult = get_multiplier_value(U, d, W)
            end
            add_proportional_to_jump_expression!(sys_expr[ref_index, t], param, mult)
            add_proportional_to_jump_expression!(nodal_expr[bus_no, t], param, mult)
        end
    end
    return
end

"""
Default implementation to add variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: VariableType,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: PTDFNetworkModel,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

"""
Motor Load implementation to add constant motor power to PTDF SystemBalanceExpressions
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: ActivePowerTimeSeriesParameter,
    V <: PSY.MotorLoad,
    W <: StaticPowerLoad,
    X <: AbstractPTDFNetworkModel,
}
    sys_expr = get_expression(container, T, PSY.System)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        device_bus = PSY.get_bus(d)
        bus_no = PNM.get_mapped_bus_number(network_reduction, device_bus)
        ref_index = _ref_index(network_model, device_bus)
        for t in time_steps
            add_proportional_to_jump_expression!(
                sys_expr[ref_index, t],
                PSY.get_active_power(d, PSY.SU),
                -1.0,
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                PSY.get_active_power(d, PSY.SU),
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
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: AreaPTDFNetworkModel,
}
    _add_variable_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

"""
Implementation of add_to_expression! for lossless branch/network models
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerVariable,
    V <: PSY.ACBranch,
    W <: AbstractBranchFormulation,
    X <: AbstractActivePowerModel,
}
    _add_both_terminals_to_nodal!(container, T, U, devices, network_model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ActivePowerBalance},
    ::Type{FlowActivePowerVariable},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    ::DeviceModel{PSY.AreaInterchange, W},
    network_model::NetworkModel{U},
) where {
    W <: AbstractBranchFormulation,
    U <: Union{AreaBalanceNetworkModel, AreaPTDFNetworkModel},
}
    flow_variable = get_variable(container, FlowActivePowerVariable, PSY.AreaInterchange)
    expression = get_expression(container, ActivePowerBalance, PSY.Area)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        area_from_name = PSY.get_name(PSY.get_from_area(d))
        area_to_name = PSY.get_name(PSY.get_to_area(d))
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[area_from_name, t],
                flow_variable[name, t],
                -1.0,
            )
            add_proportional_to_jump_expression!(
                expression[area_to_name, t],
                flow_variable[name, t],
                1.0,
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ActivePowerBalance},
    ::Type{FlowActivePowerVariable},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    ::DeviceModel{PSY.AreaInterchange, W},
    network_model::NetworkModel{U},
) where {
    W <: AbstractBranchFormulation,
    U <: AbstractNetworkModel,
}
    @debug "AreaInterchanges do not contribute to ActivePowerBalance expressions in non-area models."
    return
end

"""
Implementation of add_to_expression! for lossless branch/network models
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractBranchFormulation,
    X <: PTDFNetworkModel,
}
    var = get_variable(container, U, V)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    sys_expr = get_expression(container, T, PSY.System)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_from =
            PNM.get_mapped_bus_number(network_reduction, PSY.get_from(PSY.get_arc(d)))
        bus_no_to = PNM.get_mapped_bus_number(network_reduction, PSY.get_to(PSY.get_arc(d)))
        ref_bus_from = get_reference_bus(network_model, PSY.get_from(PSY.get_arc(d)))
        ref_bus_to = get_reference_bus(network_model, PSY.get_to(PSY.get_arc(d)))
        for t in time_steps
            flow_variable = var[name, t]
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no_from, t],
                flow_variable,
                -1.0,
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no_to, t],
                flow_variable,
                1.0,
            )
            if ref_bus_from != ref_bus_to
                add_proportional_to_jump_expression!(
                    sys_expr[ref_bus_from, t],
                    flow_variable,
                    -1.0,
                )
                add_proportional_to_jump_expression!(
                    sys_expr[ref_bus_to, t],
                    flow_variable,
                    1.0,
                )
            end
        end
    end
    return
end

"""
Implementation of add_to_expression! for lossless branch/network models
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerVariable,
    V <: PSY.ACBranch,
    W <: AbstractBranchFormulation,
}
    inter_network_branches = V[]
    for d in devices
        ref_bus_from = get_reference_bus(network_model, PSY.get_from(PSY.get_arc(d)))
        ref_bus_to = get_reference_bus(network_model, PSY.get_to(PSY.get_arc(d)))
        if ref_bus_from != ref_bus_to
            push!(inter_network_branches, d)
        end
    end
    if !isempty(inter_network_branches)
        var = get_variable(container, U, V)
        sys_expr = get_expression(container, T, PSY.System)
        time_steps = get_time_steps(container)
        for d in devices
            name = PSY.get_name(d)
            ref_bus_from = get_reference_bus(network_model, PSY.get_from(PSY.get_arc(d)))
            ref_bus_to = get_reference_bus(network_model, PSY.get_to(PSY.get_arc(d)))
            if ref_bus_from == ref_bus_to
                continue
            end
            for t in time_steps
                flow_variable = var[name, t]
                add_proportional_to_jump_expression!(
                    sys_expr[ref_bus_from, t],
                    flow_variable,
                    -1.0,
                )
                add_proportional_to_jump_expression!(
                    sys_expr[ref_bus_to, t],
                    flow_variable,
                    1.0,
                )
            end
        end
    end
    return
end

# psy6: disabled pending transformer refactor
# """
# Implementation of add_to_expression! for lossless branch/network models
# """
# function add_to_expression!(
#     container::OptimizationContainer,
#     ::Type{T},
#     ::Type{U},
#     devices::IS.FlattenIteratorWrapper{PSY.PhaseShiftingTransformer},
#     ::DeviceModel{PSY.PhaseShiftingTransformer, V},
#     network_model::NetworkModel{<:AbstractPTDFNetworkModel},
# ) where {T <: ActivePowerBalance, U <: PhaseShifterAngle, V <: PhaseAngleControl}
#     var = get_variable(container, U, PSY.PhaseShiftingTransformer)
#     expression = get_expression(container, T, PSY.ACBus)
#     network_reduction = get_network_reduction(network_model)
#     time_steps = get_time_steps(container)
#     for d in devices
#         name = PSY.get_name(d)
#         bus_no_from =
#             PNM.get_mapped_bus_number(network_reduction, PSY.get_from(PSY.get_arc(d)))
#         bus_no_to = PNM.get_mapped_bus_number(network_reduction, PSY.get_to(PSY.get_arc(d)))
#         # Per-device reactance multiplier for phase shifter
#         x_mult = 1.0 / PSY.get_x(d, PSY.SU)
#         for t in time_steps
#             flow_variable = var[name, t]
#             add_proportional_to_jump_expression!(
#                 expression[bus_no_from, t],
#                 flow_variable,
#                 -x_mult * get_variable_multiplier(U, PSY.PhaseShiftingTransformer, V),
#             )
#             add_proportional_to_jump_expression!(
#                 expression[bus_no_to, t],
#                 flow_variable,
#                 x_mult * get_variable_multiplier(U, PSY.PhaseShiftingTransformer, V),
#             )
#         end
#     end
#     return
# end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: Union{ActivePowerRangeExpressionUB, ActivePowerRangeExpressionLB},
    U <: VariableType,
    V <: PSY.Device,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    variable = get_variable(container, U, V)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        add_proportional_to_jump_expression!(expression[name, t], variable[name, t], 1.0)
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::ServiceModel{X, W},
) where {
    T <: ActivePowerRangeExpressionUB,
    U <: VariableType,
    V <: PSY.Component,
    X <: PSY.Reserve{PSY.ReserveUp},
    W <: AbstractReservesFormulation,
}
    service_name = get_service_name(model)
    variable = get_variable(container, U, X, service_name)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        add_proportional_to_jump_expression!(expression[name, t], variable[name, t], 1.0)
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{InterfaceTotalFlow},
    ::Type{T},
    service::S,
    model::ServiceModel{PSY.TransmissionInterface, U},
) where {
    T <: Union{InterfaceFlowSlackUp, InterfaceFlowSlackDown},
    U <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow},
    S <: PSY.TransmissionInterface,
}
    expression = get_expression(container, InterfaceTotalFlow, PSY.TransmissionInterface)
    service_name = PSY.get_name(service)
    variable = get_variable(container, T, PSY.TransmissionInterface, service_name)
    time_steps = get_time_steps(container)
    for t in time_steps
        add_proportional_to_jump_expression!(
            expression[service_name, t],
            variable[service_name, t],
            get_variable_multiplier(T, S, U),
        )
    end
    return
end

function _handle_nodal_or_zonal_interfaces(
    br_type::Type{V},
    net_reduction_data::PNM.NetworkReductionData,
    direction_map::Dict{String, Int},
    contributing_devices::Vector{V},
    # A `JuMPVariableArray` (StaticBranchBounds) or an `AffExpr` container (DCP StaticBranch's
    # BThetaBranchFlow); `add_proportional_to_jump_expression!` handles either scalar.
    variable::DenseAxisArray,
    expression::DenseAxisArray, # There is no good type for a DenseAxisArray slice
) where {V <: PSY.ACTransmission}
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)
    for (name, (arc, reduction)) in
        PNM.get_name_to_arc_map(net_reduction_data, br_type)
        reduction_entry = all_branch_maps_by_type[reduction][br_type][arc]
        if _reduced_entry_in_interface(reduction_entry, contributing_devices)
            if isempty(direction_map)
                direction = 1.0
            else
                direction = _get_direction(
                    arc,
                    reduction_entry,
                    direction_map,
                    net_reduction_data,
                )
            end
            for t in axes(variable, 2)
                add_proportional_to_jump_expression!(
                    expression[t],
                    variable[name, t],
                    Float64(direction),
                )
            end
        end
    end
    return
end

function _handle_nodal_or_zonal_interfaces(
    ::Type{PSY.AreaInterchange},
    net_reduction_data::PNM.NetworkReductionData,
    direction_map::Dict{String, Int},
    contributing_devices::Vector{PSY.AreaInterchange},
    variable::JuMPVariableArray,
    expression::DenseAxisArray, # There is no good type for a DenseAxisArray slice
)
    for device in contributing_devices
        name = PSY.get_name(device)
        if isempty(direction_map)
            direction = 1.0
        else
            direction = direction_map[name]
        end
        for t in axes(variable, 2)
            add_proportional_to_jump_expression!(
                expression[t],
                variable[name, t],
                Float64(direction),
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{InterfaceTotalFlow},
    ::Type{FlowActivePowerVariable},
    service::PSY.TransmissionInterface,
    model::ServiceModel{PSY.TransmissionInterface, V},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {V <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    net_reduction_data = get_network_reduction(network_model)
    expression = get_expression(container, InterfaceTotalFlow, PSY.TransmissionInterface)
    service_name = get_service_name(model)
    direction_map = PSY.get_direction_mapping(service)
    contributing_devices_map = get_contributing_devices_map(model)
    for (br_type, contributing_devices) in contributing_devices_map
        variable = get_variable(container, FlowActivePowerVariable, br_type)
        _handle_nodal_or_zonal_interfaces(
            br_type,
            net_reduction_data,
            direction_map,
            contributing_devices,
            variable,
            expression[service_name, :],
        )
    end
    return
end

# Under DCP a StaticBranch carries flow as the BThetaBranchFlow expression (no
# FlowActivePowerVariable); StaticBranchBounds still carries a variable. Read whichever
# each contributing branch type built and sum it into the interface.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{InterfaceTotalFlow},
    ::Type{FlowActivePowerVariable},
    service::PSY.TransmissionInterface,
    model::ServiceModel{PSY.TransmissionInterface, V},
    network_model::NetworkModel{DCPNetworkModel},
) where {V <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    net_reduction_data = get_network_reduction(network_model)
    expression = get_expression(container, InterfaceTotalFlow, PSY.TransmissionInterface)
    service_name = get_service_name(model)
    direction_map = PSY.get_direction_mapping(service)
    contributing_devices_map = get_contributing_devices_map(model)
    for (br_type, contributing_devices) in contributing_devices_map
        if has_container_key(container, BThetaBranchFlow, br_type)
            flow = get_expression(container, BThetaBranchFlow, br_type)
        else
            flow = get_variable(container, FlowActivePowerVariable, br_type)
        end
        _handle_nodal_or_zonal_interfaces(
            br_type,
            net_reduction_data,
            direction_map,
            contributing_devices,
            flow,
            expression[service_name, :],
        )
    end
    return
end

function _is_interchanges_interfaces(
    contributing_devices_map::Dict,
)
    if PSY.AreaInterchange ∈ keys(contributing_devices_map)
        @assert length(keys(contributing_devices_map)) == 1
        return true
    end
    return false
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{InterfaceTotalFlow},
    ::Type{FlowActivePowerVariable},
    service::PSY.TransmissionInterface,
    model::ServiceModel{PSY.TransmissionInterface, V},
    network_model::NetworkModel{AreaPTDFNetworkModel},
) where {V <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    net_reduction_data = get_network_reduction(network_model)
    expression = get_expression(container, InterfaceTotalFlow, PSY.TransmissionInterface)
    service_name = get_service_name(model)
    direction_map = PSY.get_direction_mapping(service)
    contributing_devices_map = get_contributing_devices_map(model)
    # Ignore interfaces over lines for AreaPTDFModel
    if !_is_interchanges_interfaces(contributing_devices_map)
        return
    end
    variable = get_variable(container, FlowActivePowerVariable, PSY.AreaInterchange)
    _handle_nodal_or_zonal_interfaces(
        PSY.AreaInterchange,
        net_reduction_data,
        direction_map,
        contributing_devices_map[PSY.AreaInterchange],
        variable,
        expression[service_name, :],
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{InterfaceTotalFlow},
    ::Type{PTDFBranchFlow},
    service::PSY.TransmissionInterface,
    model::ServiceModel{PSY.TransmissionInterface, V},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
) where {V <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    net_reduction_data = get_network_reduction(network_model)
    expression = get_expression(container, InterfaceTotalFlow, PSY.TransmissionInterface)
    service_name = get_service_name(model)
    direction_map = PSY.get_direction_mapping(service)
    contributing_devices_map = get_contributing_devices_map(model)
    # Interfaces over interchanges
    if _is_interchanges_interfaces(contributing_devices_map)
        return
    end

    for (br_type, contributing_devices) in contributing_devices_map
        flow_expression = get_expression(container, PTDFBranchFlow, br_type)
        # nearly identical to _handle_nodal_or_zonal_interfaces: differences are
        # expression[service_name, t] vs expression[t], flow_expression[name, t] vs variable[name, t]
        all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)
        for (name, (arc, reduction)) in PNM.get_name_to_arc_map(net_reduction_data, br_type)
            reduction_entry = all_branch_maps_by_type[reduction][br_type][arc]
            if _reduced_entry_in_interface(reduction_entry, contributing_devices)
                if isempty(direction_map)
                    direction = 1.0
                else
                    direction = _get_direction(
                        arc,
                        reduction_entry,
                        direction_map,
                        net_reduction_data,
                    )
                end
                for t in axes(flow_expression, 2)
                    JuMP.add_to_expression!(
                        expression[service_name, t],
                        flow_expression[name, t],
                        Float64(direction),
                    )
                end
            end
        end
    end
    return
end

"""
Sign relating a branch's native from→to flow to the PTDF column used for its
`PTDFBranchFlow`. Returns `-1.0` only for a series-reduction member whose native
orientation is `:ToFrom` relative to the merged path; `+1.0` otherwise. Errors
on an unknown reduction kind rather than returning a silently wrong sign.
"""
function get_ptdf_orientation_sign(
    net_reduction_data::PNM.NetworkReductionData,
    ::Type{T},
    name::AbstractString,
) where {T <: PSY.ACTransmission}
    arc, reduction = PNM.get_name_to_arc_maps(net_reduction_data)[T][name]
    if reduction == "direct_branch_map" ||
       reduction == "parallel_branch_map" ||
       reduction == "transformer3W_map"
        return 1.0
    elseif reduction == "series_branch_map"
        series = PNM.get_all_branch_maps_by_type(net_reduction_data)[reduction][T][arc]
        for (i, segment) in enumerate(series)
            if PNM.get_name(segment) == name
                return series.segment_orientations[i] == :FromTo ? 1.0 : -1.0
            end
        end
        error(
            "get_ptdf_orientation_sign: segment '$name' not found in series " *
            "reduction for arc $arc ($T)",
        )
    end
    return error(
        "get_ptdf_orientation_sign: unhandled reduction map '$reduction' for " *
        "branch '$name' ($T); cannot determine flow orientation",
    )
end

function _get_direction(
    ::Tuple{Int, Int},
    reduction_entry::PSY.ACTransmission,
    direction_map::Dict{String, Int},
    ::PNM.NetworkReductionData,
)
    name = PSY.get_name(reduction_entry)
    if !haskey(direction_map, name)
        @warn "Direction not found for $(summary(reduction_entry)). Will use the default from -> to direction"
        return 1.0
    else
        return direction_map[name]
    end
end

function _get_direction(
    arc_tuple::Tuple{Int, Int},
    reduction_entry::PNM.BranchesParallel,
    direction_map::Dict{String, Int},
    net_reduction_data::PNM.NetworkReductionData,
)
    # Loops through parallel branches twice, but there are relatively few parallel branches per reduction entry:
    directions = [
        _get_direction(arc_tuple, x, direction_map, net_reduction_data) for
        x in reduction_entry
    ]
    if allequal(directions)
        return first(directions)
    end
    throw(
        ArgumentError(
            "The interface direction mapping contains a double circuit with opposite directions. Modify the data to have consistent directions for double circuits.",
        ),
    )
end

function _get_direction(
    arc_tuple::Tuple{Int, Int},
    reduction_entry::PNM.BranchesSeries,
    direction_map::Dict{String, Int},
    net_reduction_data::PNM.NetworkReductionData,
)
    # direction of segments from the user provided mapping:
    mapping_directions = [
        _get_direction(arc_tuple, x, direction_map, net_reduction_data) for
        x in reduction_entry
    ]
    # direction of segments relative to the reduced degree two chain:
    _, segment_orientations =
        PNM._get_chain_data(arc_tuple, reduction_entry, net_reduction_data)
    segment_directions = [x == :FromTo ? 1.0 : -1.0 for x in segment_orientations]
    net_directions = mapping_directions .* segment_directions
    if allequal(net_directions)
        return first(net_directions)
    else
        throw(
            ArgumentError(
                "The interface direction mapping for degree two chain with arc $(arc_tuple) is inconsistent. Check the mapping entries and the orientation of the segment arcs within the chain.",
            ),
        )
    end
end

function _reduced_entry_in_interface(
    reduction_entry::PSY.ACTransmission,
    contributing_devices::Vector{<:PSY.ACTransmission},
)
    reduction_entry_name = PSY.get_name(reduction_entry)
    # This is compared by name given that the reduction data uses copies of the devices
    # so, simple comparisons will not work
    for device in contributing_devices
        device_name = PSY.get_name(device)
        if reduction_entry_name == device_name
            return true
        end
    end
    return false
end

_error_msg(::Type{PNM.BranchesParallel}) =
    "An interface is specified with only part of a double-circuit that has been reduced. Modify the data to include all parallel segments."
_error_msg(::Type{PNM.BranchesSeries}) =
    "An interface is specified with only part of a degree two chain reduction that has been reduced. Modify the data to include all segments of the reduced chain."

function _reduced_entry_in_interface(
    reduction_entry::T,
    contributing_devices::Vector{<:PSY.ACTransmission},
) where {T <: Union{PNM.BranchesParallel, PNM.BranchesSeries}}
    in_interface = [
        _reduced_entry_in_interface(x, contributing_devices) for
        x in reduction_entry
    ]

    if !allequal(in_interface)
        branch_names = [PSY.get_name(x) for x in reduction_entry]
        throw(ArgumentError(_error_msg(T) * " Offending branches: $(branch_names)."))
    end
    return first(in_interface)
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::ServiceModel{X, W},
) where {
    T <: ActivePowerRangeExpressionLB,
    U <: VariableType,
    V <: PSY.Component,
    X <: PSY.Reserve{PSY.ReserveDown},
    W <: AbstractReservesFormulation,
}
    service_name = get_service_name(model)
    variable = get_variable(container, U, X, service_name)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        add_proportional_to_jump_expression!(expression[name, t], variable[name, t], -1.0)
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::U,
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: Union{ActivePowerRangeExpressionUB, ActivePowerRangeExpressionLB},
    U <: OnStatusParameter,
    V <: PSY.Device,
    W <: AbstractDeviceFormulation,
}
    parameter_array = get_parameter_array(container, U, V)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        mult = get_expression_multiplier(U, T, d, W)
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[name, t],
                parameter_array[name, t],
                -mult,
                mult,
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{U},
    model::ServiceModel{V, W},
    devices_template::Dict{Symbol, DeviceModel},
) where {U <: VariableType, V <: PSY.Reserve, W <: AbstractReservesFormulation}
    contributing_devices_map = get_contributing_devices_map(model)
    for (device_type, devices) in contributing_devices_map
        device_model = get(devices_template, Symbol(device_type), nothing)
        device_model === nothing && continue
        expression_type = get_expression_type_for_reserve(U, device_type, V)
        add_to_expression!(container, expression_type, U, devices, model)
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    ::PSY.System,
    network_model::NetworkModel{W},
) where {
    T <: ActivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    W <: Union{CopperPlateNetworkModel, PTDFNetworkModel},
}
    variable = get_variable(container, U, PSY.System)
    expression = get_expression(container, T, _system_expression_type(W))
    reference_buses = get_reference_buses(network_model)
    time_steps = get_time_steps(container)
    for t in time_steps, n in reference_buses
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.System, W),
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    sys::PSY.System,
    network_model::NetworkModel{V},
) where {
    T <: ActivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    V <: AreaPTDFNetworkModel,
}
    variable =
        get_variable(container, U, _system_expression_type(AreaPTDFNetworkModel))
    expression =
        get_expression(container, T, _system_expression_type(AreaPTDFNetworkModel))
    areas = get_available_components(network_model, PSY.Area, sys)
    time_steps = get_time_steps(container)
    for t in time_steps, n in PSY.get_name.(areas)
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.Area, AreaPTDFNetworkModel),
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    sys::PSY.System,
    ::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
}
    variable = get_variable(container, U, PSY.Area)
    expression = get_expression(container, T, PSY.Area)
    @assert_op length(axes(variable, 1)) == length(axes(expression, 1))
    time_steps = get_time_steps(container)
    for t in time_steps, n in axes(expression, 1)
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.Area, AreaBalanceNetworkModel),
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    sys::PSY.System,
    ::NetworkModel{W},
) where {
    T <: ActivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    W <: AbstractActivePowerModel,
}
    variable = get_variable(container, U, PSY.ACBus)
    expression = get_expression(container, T, PSY.ACBus)
    @assert_op length(axes(variable, 1)) == length(axes(expression, 1))
    # We uses axis here to avoid double addition of the slacks to the aggregated buses
    time_steps = get_time_steps(container)
    for t in time_steps, n in axes(expression, 1)
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.ACBus, W),
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    sys::PSY.System,
    ::NetworkModel{W},
) where {
    T <: ActivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    W <: AbstractNetworkModel,
}
    variable = get_variable(container, U, PSY.ACBus, "P")
    expression = get_expression(container, T, PSY.ACBus)
    # We uses axis here to avoid double addition of the slacks to the aggregated buses
    time_steps = get_time_steps(container)
    for t in time_steps, n in axes(expression, 1)
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.ACBus, W),
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    sys::PSY.System,
    ::NetworkModel{W},
) where {
    T <: ReactivePowerBalance,
    U <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    W <: AbstractNetworkModel,
}
    variable = get_variable(container, U, PSY.ACBus, "Q")
    expression = get_expression(container, T, PSY.ACBus)
    # We uses axis here to avoid double addition of the slacks to the aggregated buses
    time_steps = get_time_steps(container)
    for t in time_steps, n in axes(expression, 1)
        add_proportional_to_jump_expression!(
            expression[n, t],
            variable[n, t],
            get_variable_multiplier(U, PSY.ACBus, W),
        )
    end
    return
end

function add_cost_to_expression!(
    container::OptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    component::T,
    time_period::Int,
) where {
    S <: CostExpressions,
    T <: Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve},
}
    if has_container_key(container, S, T, PSY.get_name(component))
        device_cost_expression = get_expression(container, S, T, PSY.get_name(component))
        component_name = PSY.get_name(component)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::U,
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: NetActivePower,
    U <: Union{ActivePowerInVariable, ActivePowerOutVariable},
    V <: PSY.Source,
    W <: AbstractSourceFormulation,
}
    expression = get_expression(container, T, V)
    variable = get_variable(container, U, V)
    mult = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        for t in time_steps
            JuMP.add_to_expression!(
                expression[name, t],
                variable[name, t] * mult,
            )
        end
    end
    return
end

#=
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    areas::IS.FlattenIteratorWrapper{V},
    model::ServiceModel{PSY.AGC, W},
) where {
    T <: Union{EmergencyUp, EmergencyDown},
    U <:
    Union{AdditionalDeltaActivePowerUpVariable, AdditionalDeltaActivePowerDownVariable},
    V <: PSY.Area,
    W <: AbstractServiceFormulation,
}
    names = PSY.get_name.(areas)
    time_steps = get_time_steps(container)
    if !has_container_key(container, T, V)
        expression = add_expression_container!(container, T, V, names, time_steps)
    end
    expression = get_expression(container, T, V)
    variable = get_variable(container, U, V)
    for n in names, t in time_steps
        add_proportional_to_jump_expression!(expression[n, t], variable[n, t], 1.0)
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    services::IS.FlattenIteratorWrapper{V},
    model::ServiceModel{V, W},
) where {
    T <: RawACE,
    U <: SteadyStateFrequencyDeviation,
    V <: PSY.AGC,
    W <: AbstractServiceFormulation,
}
    names = PSY.get_name.(services)
    time_steps = get_time_steps(container)
    if !has_container_key(container, T, V)
        expression = add_expression_container!(container, T, PSY.AGC, names, time_steps)
    end
    expression = get_expression(container, T, PSY.AGC)
    variable = get_variable(container, U, PSY.AGC)
    for s in services, t in time_steps
        name = PSY.get_name(s)
        # Per-device bias multiplier for AGC frequency deviation
        bias_mult = -10 * PSY.get_bias(s)
        add_proportional_to_jump_expression!(
            expression[name, t],
            variable["System", t],
            bias_mult * get_variable_multiplier(U, V, W),
        )
    end
    return
end
=#

# Cost expression methods - add cost terms to ProductionCostExpression containers
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{S},
    cost_expression::JuMPOrFloat,
    component::T,
    time_period::Int,
) where {S <: Union{CostExpressions, FuelConsumptionExpression}, T <: PSY.Component}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S, T)
        component_name = PSY.get_name(component)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    component::T,
    time_period::Int,
) where {
    S <: CostExpressions,
    T <: Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve},
}
    if has_container_key(container, S, T, PSY.get_name(component))
        device_cost_expression =
            get_expression(container, S, T, PSY.get_name(component))
        component_name = PSY.get_name(component)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

################################################################################
# ACPNetworkModel branch-flow → nodal balance contributions
#
# Each directional flow variable is subtracted from the nodal balance at the
# bus where it originates (power leaves that bus, so it reduces the net injection).
#
# Convention:  expressions[bus, t] == 0  means  Σ_injections - Σ_flows_out = 0
#   pft  leaves from-bus  →  -1.0 at from_bus in ActivePowerBalance
#   ptf  leaves to-bus    →  -1.0 at to_bus   in ActivePowerBalance
#   qft  leaves from-bus  →  -1.0 at from_bus in ReactivePowerBalance
#   qtf  leaves to-bus    →  -1.0 at to_bus   in ReactivePowerBalance
################################################################################

"""
HVDC two-terminal lossless active-power flow contribution to `ActivePowerBalance`.

Wires the single `FlowActivePowerVariable` directly: subtracts at the from-bus,
adds at the to-bus. Used by every native nodal network model.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: FlowActivePowerVariable,
    V <: PSY.TwoTerminalHVDC,
    W <: AbstractBranchFormulation,
    X <: NativeNodalNetworkModel,
}
    _add_both_terminals_to_nodal!(container, T, U, devices, network_model)
    return
end

# The HVDC directional active flows (FromTo/ToFrom) reach the nodal balances of the
# native nodal networks through the generic `PSY.Branch`/`PSY.ACBranch` directional-flow
# methods above (−1.0 at the variable's own terminal); no HVDC-specific method is
# needed. Under the AC natives the link is an active-power-only injector: nothing
# enters `ReactivePowerBalance`.

"""
PWL received HVDC active power contribution to the nodal `ActivePowerBalance` for the
native nodal network models (AC and DC). Both received terminals contribute +1.0 at
their own bus, mirroring the PTDF PWL wiring; under the AC natives the link offers no
reactive power.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: Union{HVDCActivePowerReceivedFromVariable, HVDCActivePowerReceivedToVariable},
    V <: PSY.TwoTerminalHVDC,
    W <: HVDCTwoTerminalPiecewiseLoss,
    X <: NativeNodalNetworkModel,
}
    _add_terminal_flow_to_nodal!(container, T, U, devices, network_model, 1.0)
    return
end

# NOTE: kept as two concrete-variable methods (not merged into a `U <: Union{...}`).
# Generic `PSY.Branch`/`ACBranch` active-flow methods elsewhere dispatch on the
# concrete `FlowActivePower{From,To}Variable`; unioning the variable axis here would
# tie with them (each more specific on a different axis) and become ambiguous.
"""
FlowActivePowerFromToVariable contribution to ActivePowerBalance for ACP, ACR, and DCPLL:
subtracted from the from-bus nodal balance (power leaves from-bus).
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ActivePowerBalance},
    ::Type{FlowActivePowerFromToVariable},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, W},
    network_model::NetworkModel{
        <:Union{
            ACPNetworkModel,
            ACRNetworkModel,
            DCPLLNetworkModel,
            LPACCNetworkModel,
            IVRNetworkModel,
        },
    },
) where {T <: PSY.ACTransmission, W <: AbstractBranchFormulation}
    _add_terminal_flow_to_nodal!(
        container, ActivePowerBalance, FlowActivePowerFromToVariable, devices,
        network_model, -1.0,
    )
    return
end

"""
FlowActivePowerToFromVariable contribution to ActivePowerBalance for ACP, ACR, DCPLL, and IVR:
subtracted from the to-bus nodal balance (power leaves to-bus).
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ActivePowerBalance},
    ::Type{FlowActivePowerToFromVariable},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, W},
    network_model::NetworkModel{
        <:Union{
            ACPNetworkModel,
            ACRNetworkModel,
            DCPLLNetworkModel,
            LPACCNetworkModel,
            IVRNetworkModel,
        },
    },
) where {T <: PSY.ACTransmission, W <: AbstractBranchFormulation}
    _add_terminal_flow_to_nodal!(
        container, ActivePowerBalance, FlowActivePowerToFromVariable, devices,
        network_model, -1.0,
    )
    return
end

"""
FlowReactivePower{From,To} branch contribution to ReactivePowerBalance for
ACPNetworkModel and ACRNetworkModel. Each directional reactive flow is subtracted from its
originating terminal's reactive balance; the terminal is resolved from the variable type.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ReactivePowerBalance},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, W},
    network_model::NetworkModel{
        <:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {
    T <: PSY.ACTransmission,
    U <: Union{FlowReactivePowerFromToVariable, FlowReactivePowerToFromVariable},
    W <: AbstractBranchFormulation,
}
    _add_terminal_flow_to_nodal!(
        container, ReactivePowerBalance, U, devices, network_model, -1.0,
    )
    return
end

"""
HVDC two-terminal lossless reactive flow → ReactivePowerBalance for ACPNetworkModel, ACRNetworkModel, and IVRNetworkModel.
Mirrors the AC ACP/ACR/IVR convention: each directional reactive flow leaves its
originating bus, so subtract at that terminal (resolved from the variable type).
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{ReactivePowerBalance},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, W},
    network_model::NetworkModel{
        <:Union{ACPNetworkModel, ACRNetworkModel, LPACCNetworkModel, IVRNetworkModel},
    },
) where {
    T <: PSY.TwoTerminalHVDC,
    U <: Union{FlowReactivePowerFromToVariable, FlowReactivePowerToFromVariable},
    W <: AbstractBranchFormulation,
}
    _add_terminal_flow_to_nodal!(
        container, ReactivePowerBalance, U, devices, network_model, -1.0,
    )
    return
end
