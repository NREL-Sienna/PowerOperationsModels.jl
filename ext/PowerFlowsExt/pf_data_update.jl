# Power flow in-the-loop: data update logic.
# Ported from PowerSimulations.jl/src/network_models/power_flow_evaluation.jl.
# Defines the `PFContribution` injection-sign resolver, the PowerFlowData and System
# writers, update_pf_data! (PowerFlowData and PSSEExporter variants), and update_pf_system!.

# Injection-sign resolver: the single source of truth mapping an optimization value to its
# power-flow contribution. `sign` equals the multiplier `add_to_expression!` applied to the bus
# balance, so PF reproduces the OPF nodal balance. Two thin writers consume it (below).
#   quantity : PFActiveQuantity | PFReactiveQuantity | PFAngleQuantity | PFMagnitudeQuantity
#   role     : active/reactive array selector PFInjectionRole | PFWithdrawalRole | PFHVDCNetRole
#              (PFNoRole for voltages, which assign to a bus-state array selected by quantity)
#   sign     : nodal-balance multiplier (+1 / -1)
#   partial  : System writer only — in/out variables accumulate onto a shared active_power field
# `quantity`/`role` are singleton tag types (not `Symbol`s) so the writers resolve the target
# array by dispatch instead of branching on runtime Symbol values — this keeps
# `PFContribution` concretely typed and `_write_value_to_pf_data!` type-stable.
abstract type PFQuantity end
struct PFActiveQuantity <: PFQuantity end
struct PFReactiveQuantity <: PFQuantity end
struct PFAngleQuantity <: PFQuantity end
struct PFMagnitudeQuantity <: PFQuantity end

abstract type PFRole end
struct PFInjectionRole <: PFRole end
struct PFWithdrawalRole <: PFRole end
struct PFHVDCNetRole <: PFRole end
struct PFNoRole <: PFRole end

struct PFContribution{Q <: PFQuantity, R <: PFRole}
    quantity::Q
    role::R
    sign::Float64
    partial::Bool
end

const _PF_FLOW_ENTRY = Union{VariableType, AuxVariableType}
const _PF_PARAM_ENTRY = ParameterType

# ---- variable / aux entries: the input category carries the direction ----
# mirrors `add_to_expression!`: StaticInjection (+1 injection), ElectricLoad (-1 withdrawal).
pf_contribution(
    ::Val{:active_power},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFActiveQuantity(), PFInjectionRole(), 1.0, false)
pf_contribution(
    ::Val{:active_power},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.ElectricLoad},
) = PFContribution(PFActiveQuantity(), PFWithdrawalRole(), -1.0, false)
# ActivePowerOutVariable: power output (positive injection); ActivePowerInVariable: withdrawal.
pf_contribution(
    ::Val{:active_power_out},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFActiveQuantity(), PFInjectionRole(), 1.0, true)
pf_contribution(
    ::Val{:active_power_in},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFActiveQuantity(), PFInjectionRole(), -1.0, true)
pf_contribution(
    ::Val{:reactive_power},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFReactiveQuantity(), PFInjectionRole(), 1.0, false)
pf_contribution(
    ::Val{:reactive_power},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.ElectricLoad},
) = PFContribution(PFReactiveQuantity(), PFWithdrawalRole(), -1.0, false)
pf_contribution(
    ::Union{Val{:voltage_angle_export}, Val{:voltage_angle_opf}},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.ACBus},
) = PFContribution(PFAngleQuantity(), PFNoRole(), 1.0, false)
pf_contribution(
    ::Union{Val{:voltage_magnitude_export}, Val{:voltage_magnitude_opf}},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.ACBus},
) = PFContribution(PFMagnitudeQuantity(), PFNoRole(), 1.0, false)

# ---- HVDC / PST two-terminal (variable entries) ----
# HVDC re-targets to `:hvdc_net` (`bus_hvdc_net_power`); signs follow the injection convention.
# from_to: -1. to_from: `FlowActivePowerToFromVariable` is -tf, signed negative for from→to flow
# (sign -1); a single `FlowActivePowerVariable` (lossless / PowerModels `:p_dc`) is +flow (sign +1).
pf_contribution(
    ::Val{:active_power_hvdc_pst_from_to},
    ::Type{<:_PF_FLOW_ENTRY},
    ::Type{<:PSY.TwoTerminalHVDC},
) = PFContribution(PFActiveQuantity(), PFHVDCNetRole(), -1.0, false)
pf_contribution(
    ::Val{:active_power_hvdc_pst_to_from},
    ::Type{POM.FlowActivePowerToFromVariable},
    ::Type{<:PSY.TwoTerminalHVDC},
) = PFContribution(PFActiveQuantity(), PFHVDCNetRole(), -1.0, false)
pf_contribution(
    ::Val{:active_power_hvdc_pst_to_from},
    ::Type{POM.FlowActivePowerVariable},
    ::Type{<:PSY.TwoTerminalHVDC},
) = PFContribution(PFActiveQuantity(), PFHVDCNetRole(), 1.0, false)
# psy6: disabled pending transformer refactor
# PhaseShiftingTransformer stays on the generic injection array: from_to -1, to_from +1.
# pf_contribution(
#     ::Val{:active_power_hvdc_pst_from_to},
#     ::Type{<:_PF_FLOW_ENTRY},
#     ::Type{<:PSY.PhaseShiftingTransformer},
# ) = PFContribution(PFActiveQuantity(), PFInjectionRole(), -1.0, false)
# pf_contribution(
#     ::Val{:active_power_hvdc_pst_to_from},
#     ::Type{<:_PF_FLOW_ENTRY},
#     ::Type{<:PSY.PhaseShiftingTransformer},
# ) = PFContribution(PFActiveQuantity(), PFInjectionRole(), 1.0, false)

# ---- parameter entries: the value already stores the signed nodal contribution ----
# `param_array .* multiplier_array` bakes the direction in, identical to what
# `add_to_expression!` adds to the balance. So these match the variable entries EXCEPT in/out,
# which become +1: re-applying the category sign would double-count (this is the #1631 fix).
pf_contribution(
    ::Val{:active_power},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFActiveQuantity(), PFInjectionRole(), 1.0, false)
pf_contribution(
    ::Union{Val{:active_power_in}, Val{:active_power_out}},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFActiveQuantity(), PFInjectionRole(), 1.0, true)
pf_contribution(
    ::Val{:active_power},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.ElectricLoad},
) = PFContribution(PFActiveQuantity(), PFWithdrawalRole(), -1.0, false)
pf_contribution(
    ::Val{:reactive_power},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.StaticInjection},
) = PFContribution(PFReactiveQuantity(), PFInjectionRole(), 1.0, false)
pf_contribution(
    ::Val{:reactive_power},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.ElectricLoad},
) = PFContribution(PFReactiveQuantity(), PFWithdrawalRole(), -1.0, false)
pf_contribution(
    ::Union{Val{:voltage_angle_export}, Val{:voltage_angle_opf}},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.ACBus},
) = PFContribution(PFAngleQuantity(), PFNoRole(), 1.0, false)
pf_contribution(
    ::Union{Val{:voltage_magnitude_export}, Val{:voltage_magnitude_opf}},
    ::Type{<:_PF_PARAM_ENTRY},
    ::Type{<:PSY.ACBus},
) = PFContribution(PFMagnitudeQuantity(), PFNoRole(), 1.0, false)

# ---- PowerFlowData writer ----
# Active/reactive quantities accumulate into an injection array chosen by (quantity, role);
# voltage quantities are assigned to a bus-state array selected by quantity.
_pf_writes_voltage(::PFQuantity) = false
_pf_writes_voltage(::PFAngleQuantity) = true
_pf_writes_voltage(::PFMagnitudeQuantity) = true

_pf_array(pfd::PFS.PowerFlowData, ::PFActiveQuantity, ::PFInjectionRole) =
    pfd.bus_active_power_injections
_pf_array(pfd::PFS.PowerFlowData, ::PFActiveQuantity, ::PFWithdrawalRole) =
    pfd.bus_active_power_withdrawals
_pf_array(pfd::PFS.PowerFlowData, ::PFActiveQuantity, ::PFHVDCNetRole) =
    pfd.bus_hvdc_net_power
_pf_array(pfd::PFS.PowerFlowData, ::PFReactiveQuantity, ::PFInjectionRole) =
    pfd.bus_reactive_power_injections
_pf_array(pfd::PFS.PowerFlowData, ::PFReactiveQuantity, ::PFWithdrawalRole) =
    pfd.bus_reactive_power_withdrawals
_pf_bus_state_array(pfd::PFS.PowerFlowData, ::PFAngleQuantity) = pfd.bus_angles
_pf_bus_state_array(pfd::PFS.PowerFlowData, ::PFMagnitudeQuantity) = pfd.bus_magnitude

# Function barrier: `category`, `T` (entry type) and `U` (component type) are compile-time
# constants here, so `pf_contribution` resolves statically and the resulting singleton
# `quantity`/`role` dispatch the array lookup with no runtime Symbol branching. One (dynamic)
# dispatch into this method happens per (category, key) in the caller's loop.
function _write_value_to_pf_data!(
    pf_data::PFS.PowerFlowData,
    ::Val{category},
    container::OptimizationContainer,
    key::OptimizationContainerKey{T, U},
    component_map,
) where {category, T, U}
    result = lookup_value(container, key)
    c = pf_contribution(Val(category), T, U)
    # Resolve the target array once per key so the inner write loop runs on a concrete `Matrix`.
    if _pf_writes_voltage(c.quantity)
        _write_pf_array!(_pf_bus_state_array(pf_data, c.quantity), true, c.sign,
            component_map, container, result)
    else
        _write_pf_array!(_pf_array(pf_data, c.quantity, c.role), false, c.sign,
            component_map, container, result)
    end
    return
end

# Function barrier: `arr` is a concrete `Matrix{Float64}`, so the per-(device, time) loop is
# monomorphic. `assign` overwrites (voltages); otherwise contributions accumulate.
function _write_pf_array!(
    arr::Matrix{Float64},
    assign::Bool,
    value_sign::Float64,
    component_map,
    container::OptimizationContainer,
    result,
)
    for (device_name, index) in component_map
        for t in get_time_steps(container)
            value = jump_value(result[device_name, t])
            if assign
                arr[index, t] = value
            else
                arr[index, t] += value_sign * value
            end
        end
    end
    return
end

function update_pf_data!(
    pf_e_data::PowerFlowEvaluationData{<:PFS.PowerFlowData},
    container::OptimizationContainer,
)
    pf_data = IOM.get_inner_data(pf_e_data)
    PFS.clear_injection_data!(pf_data)
    # `clear_injection_data!` does not reset `bus_hvdc_net_power`, which PowerFlows seeds from the
    # system at construction. Zero it before re-writing optimized HVDC flows, else the seed
    # double-counts (AC, #1635) or shadows the optimized DC flow. Co-located with the repopulate
    # below so they can't desync; skipped only if a `PowerFlowData` opts out of hvdc_pst.
    isempty(pf_input_keys_hvdc_pst(pf_data)) || (pf_data.bus_hvdc_net_power .= 0.0)
    input_map = get_input_key_map(pf_e_data)
    for (category, inputs) in input_map
        @debug "Writing $category to $(nameof(typeof(pf_data)))"
        for (key, component_map) in inputs
            _write_value_to_pf_data!(pf_data, Val(category), container, key, component_map)
        end
    end
    return
end

# ---- System writer: same `PFContribution`, sunk into component fields ----
# PERF direct dot access + manual unit conversions for performance and convenience.
# active/reactive convert to the component base; voltages are written raw.
_pf_to_comp(::Union{PFActiveQuantity, PFReactiveQuantity}, value::Float64, sys_base::Float64,
    comp::PSY.Component) = value * sys_base / PSY.get_base_power(comp, PSY.NU)
_pf_to_comp(
    ::Union{PFAngleQuantity, PFMagnitudeQuantity},
    value::Float64,
    ::Float64,
    ::PSY.Component,
) = value

# Set (or accumulate, for `partial` in/out contributions) the signed quantity on the component's
# field. `StandardLoad` (ZIP) has no scalar power field, so it routes to its constant-power
# component (`constant_active_power`/`constant_reactive_power`).
_set_comp_quantity!(comp::PSY.Component, ::PFActiveQuantity, v::Float64, partial::Bool) =
    partial ? (comp.active_power += v) : (comp.active_power = v)
_set_comp_quantity!(comp::PSY.Component, ::PFReactiveQuantity, v::Float64, ::Bool) =
    (comp.reactive_power = v)
_set_comp_quantity!(comp::PSY.StandardLoad, ::PFActiveQuantity, v::Float64, ::Bool) =
    (comp.constant_active_power = v)
_set_comp_quantity!(comp::PSY.StandardLoad, ::PFReactiveQuantity, v::Float64, ::Bool) =
    (comp.constant_reactive_power = v)
_set_comp_quantity!(comp::PSY.ACBus, ::PFAngleQuantity, v::Float64, ::Bool) =
    (comp.angle = v)
_set_comp_quantity!(comp::PSY.ACBus, ::PFMagnitudeQuantity, v::Float64, ::Bool) =
    (comp.magnitude = v)

function _apply_component_contribution!(
    comp::PSY.Component,
    c::PFContribution,
    value::Float64,
    sys_base::Float64,
)
    v = c.sign * _pf_to_comp(c.quantity, value, sys_base, comp)
    _set_comp_quantity!(comp, c.quantity, v, c.partial)
    return
end

# Function barrier mirroring `_write_value_to_pf_data!`: `category`/`T`/`U` are compile-time
# constants, so `pf_contribution` and `PSY.get_component(U, …)` resolve statically and the
# singleton `quantity` dispatches the field writes in `_apply_component_contribution!`.
function _write_component_contributions!(
    sys::PSY.System,
    container::OptimizationContainer,
    ::Val{category},
    key::OptimizationContainerKey{T, U},
    component_map,
    time_step::Int,
) where {category, T, U}
    result = lookup_value(container, key)
    c = pf_contribution(Val(category), T, U)
    sys_base = IOM.get_model_base_power(container)
    for (device_id, device_name) in component_map
        comp = PSY.get_component(U, sys, device_name)
        val = jump_value(result[device_id, time_step])
        _apply_component_contribution!(comp, c, val, sys_base)
    end
    return
end

function update_pf_system!(
    sys::PSY.System,
    container::OptimizationContainer,
    input_map::Dict{Symbol, <:Dict{OptimizationContainerKey, <:Any}},
    time_step::Int,
)
    # Reset active_power to zero for components that use separate in/out variables
    # (e.g. storage, import/export sources) before the additive += / -= updates.
    # Collect unique (type, name) pairs to avoid resetting the same component twice.
    reset_components = Set{Tuple{DataType, String}}()
    for category in (:active_power_in, :active_power_out)
        haskey(input_map, category) || continue
        for (key, component_map) in input_map[category]
            for (_, device_name) in component_map
                push!(reset_components, (get_component_type(key), device_name))
            end
        end
    end
    for (comp_type, device_name) in reset_components
        comp = PSY.get_component(comp_type, sys, device_name)
        comp.active_power = 0.0
    end
    for (category, inputs) in input_map
        @debug "Writing $category to (possibly internal) System"
        for (key, component_map) in inputs
            _write_component_contributions!(
                sys, container, Val(category), key, component_map, time_step)
        end
    end
end

"""
Update a `PowerFlowEvaluationData` containing a `PowerFlowContainer` that does not
`supports_multi_period` using a single `time_step` of the `OptimizationContainer`. To
properly keep track of outer step number, time steps must be passed in sequentially,
starting with 1.
"""
function update_pf_data!(
    pf_e_data::PowerFlowEvaluationData{PFS.PSSEExporter},
    container::OptimizationContainer,
    time_step::Int,
)
    pf_data = IOM.get_inner_data(pf_e_data)
    input_map = get_input_key_map(pf_e_data)
    update_pf_system!(PFS.get_system(pf_data), container, input_map, time_step)
    if !isnothing(pf_data.step)
        outer_step, _... = pf_data.step
        # time_step == 1 means we have rolled over to a new outer step
        # NOTE this is brittle but there is currently no way of getting this information
        # from upstream; may change in the future.
        (time_step == 1) && (outer_step += 1)
        pf_data.step = (outer_step, time_step)
    end
    return
end
