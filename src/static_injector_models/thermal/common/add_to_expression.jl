"""
Add a compact unit-commitment `OnVariable` scaled by per-device `p_min`, with no must-run
branch (matches PSI; the `On` variable carries the `p_min` scale). Used by the CopperPlate
and PTDF compact-UC methods.
"""
function _add_pmin_scaled_on_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnVariable, V <: PSY.ThermalGen, W}
    variable = get_variable(container, U, V)
    base_multiplier = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = PSY.get_active_power_limits(d, PSY.SU).min * base_multiplier
        for t in time_steps
            _apply_term_to_targets!(targets, variable[name, t], multiplier, t)
        end
    end
    return
end

"""
Add a compact unit-commitment `OnVariable` to a balance expression. Must-run units
have `On ≡ 1`, so their `p_min` contribution enters as a constant; all others
contribute `p_min * get_variable_multiplier(U, V, W) * On[name, t]`. Targets come from
[`_balance_expression_targets`](@ref), so this is correct for every network model
(nodal, area, system, PTDF).
"""
function _add_compact_on_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnVariable, V <: PSY.ThermalGen, W}
    variable = get_variable(container, U, V)
    base_multiplier = get_variable_multiplier(U, V, W)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = PSY.get_active_power_limits(d, PSY.SU).min * base_multiplier
        if PSY.get_must_run(d)
            # On ≡ 1 for must-run units, so the term is the constant p_min * mult.
            for t in time_steps
                _apply_term_to_targets!(targets, 1.0, multiplier, t)
            end
        else
            for t in time_steps
                _apply_term_to_targets!(targets, variable[name, t], multiplier, t)
            end
        end
    end
    return
end

"""
Add a thermal `OnStatusParameter` to a balance expression with the device-specific
`get_expression_multiplier(U, T, d, W)`, targets from
[`_balance_expression_targets`](@ref).
"""
function _add_onstatus_parameter_to_balance!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    network_model::NetworkModel,
    ::DeviceModel{V, W},
) where {T <: ExpressionType, U <: OnStatusParameter, V <: PSY.ThermalGen, W}
    parameter = get_parameter_array(container, U, V)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        multiplier = get_expression_multiplier(U, T, d, W)
        for t in time_steps
            _apply_term_to_targets!(targets, parameter[name, t], multiplier, t)
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    _add_onstatus_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
}
    _add_compact_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
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
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
    X <: AbstractNetworkModel,
}
    _add_compact_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaBalanceNetworkModel},
) where {
    T <: SystemBalanceExpressions,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: Union{AbstractCompactUnitCommitment, ThermalCompactDispatch},
}
    _add_compact_on_to_balance!(container, T, U, devices, network_model, device_model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    _add_onstatus_parameter_to_balance!(container, T, U, devices, network_model, model)
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{CopperPlateNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
}
    # No must-run branch here (matches PSI); the On variable carries the P_min scale.
    _add_pmin_scaled_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
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
    U <: OnStatusParameter,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
    X <: AbstractPTDFNetworkModel,
}
    parameter = get_parameter_array(container, U, V)
    sys_expr = get_expression(container, T, PSY.System)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        bus_no_ = PSY.get_number(PSY.get_bus(d))
        bus_no = PNM.get_mapped_bus_number(network_reduction, bus_no_)
        mult = get_expression_multiplier(U, T, d, W)
        device_bus = PSY.get_bus(d)
        ref_index = _ref_index(network_model, device_bus)
        for t in time_steps
            add_proportional_to_jump_expression!(
                sys_expr[ref_index, t],
                parameter[name, t],
                mult,
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                parameter[name, t],
                mult,
            )
        end
    end
    return
end

# The on variables are included in the system balance expressions becuase they
# are multiplied by the Pmin and the active power is not the total active power
# but the power above minimum.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: OnVariable,
    V <: PSY.ThermalGen,
    W <: AbstractCompactUnitCommitment,
    X <: PTDFNetworkModel,
}
    # No must-run branch here (matches PSI); the On variable carries the P_min scale.
    _add_pmin_scaled_on_to_balance!(
        container,
        T,
        U,
        devices,
        network_model,
        device_model,
    )
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
    V <: PSY.ThermalGen,
    W <: AbstractThermalDispatchFormulation,
}
    parameter_array = get_parameter_array(container, U, V)
    if !has_container_key(container, T, V)
        add_expressions!(container, T, devices, model)
    end
    expression = get_expression(container, T, V)
    time_steps = get_time_steps(container)
    for d in devices
        if PSY.get_must_run(d)
            continue
        end
        name = PSY.get_name(d)
        mult = get_expression_multiplier(U, T, d, W)
        for t in time_steps
            add_proportional_to_jump_expression!(
                expression[name, t],
                parameter_array[name, t],
                -mult,
            )
        end
    end
    return
end

# Per-device fuel consumption term builders, dispatched on the value-curve type so the
# decision of how to translate the curve into JuMP terms is a method-resolution problem
# rather than a runtime branch.

# LinearCurve fuel: linear in the dispatch variable. Routes through the IOM helper
# so the propagation rules (FuelConsumptionExpression is non-ConstituentCost, so the
# objective hook is skipped here) live in one place.
function _add_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{C},
    variable,
    name::String,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.LinearCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {C <: PSY.ThermalGen}
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    rate = prop_term_per_unit * dt
    for t in time_steps
        IOM.add_cost_term_to_expression!(
            container, variable[name, t], rate,
            FuelConsumptionExpression, C, name, t,
        )
    end
    return
end

# QuadraticCurve fuel: quadratic in the dispatch variable. The shape doesn't fit the
# `quantity * rate` form, so the cost is built locally and added with `JuMP.add_to_expression!`.
function _add_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{C},
    variable,
    name::String,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.QuadraticCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {C <: PSY.ThermalGen}
    expression = get_expression(container, FuelConsumptionExpression, C)
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    quadratic_term = PSY.get_quadratic_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    quad_term_per_unit = get_quadratic_cost_per_system_unit(
        quadratic_term, power_units, base_power, device_base_power)
    for t in time_steps
        fuel_expr =
            (
                variable[name, t] .^ 2 * quad_term_per_unit +
                variable[name, t] * prop_term_per_unit
            ) * dt
        JuMP.add_to_expression!(expression[name, t], fuel_expr)
    end
    return
end

# Piecewise/incremental/average-rate value curves are populated through their own
# objective paths; no contribution to FuelConsumptionExpression here.
_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.PiecewisePointCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.IncrementalCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:PSY.ThermalGen}, _, ::String,
    ::PSY.FuelCurve, ::PSY.AverageRateCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: FuelConsumptionExpression,
    U <: ActivePowerVariable,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U, V)
    time_steps = get_time_steps(container)
    base_power = get_model_base_power(container)
    resolution = get_resolution(container)
    dt = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    for d in devices
        var_cost = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(var_cost) || continue
        name = PSY.get_name(d)
        device_base_power = PSY.get_base_power(d, PSY.NU)
        value_curve = PSY.get_value_curve(var_cost)
        _add_fuel_consumption_term!(
            container, V, variable, name, var_cost, value_curve,
            base_power, device_base_power, dt, time_steps,
        )
    end
end

# Compact formulation: dispatch variable is "above-minimum"; constant P_min term is
# added per-time-step, gated by the SOS status (no_variable / parameter / variable).
function _add_compact_fuel_consumption_term!(
    container::OptimizationContainer,
    ::Type{W},
    expression,
    variable,
    d::V,
    var_cost::PSY.FuelCurve,
    value_curve::PSY.LinearCurve,
    base_power::Float64,
    device_base_power::Float64,
    dt::Float64,
    time_steps,
) where {V <: PSY.ThermalGen, W <: AbstractDeviceFormulation}
    name = PSY.get_name(d)
    P_min = PSY.get_active_power_limits(d, PSY.SU).min
    power_units = PSY.get_power_units(var_cost)
    proportional_term = PSY.get_proportional_term(value_curve)
    prop_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term, power_units, base_power, device_base_power)
    on_var_type = typeof(get_default_on_variable(d))
    for t in time_steps
        sos_status = _get_sos_value(container, W, d)
        bin = IOM._determine_bin_lhs(
            container, sos_status, V, name, t; on_var_type = on_var_type,
        )
        JuMP.add_to_expression!(
            expression[name, t], P_min * prop_term_per_unit * dt, bin)
        JuMP.add_to_expression!(
            expression[name, t], prop_term_per_unit * dt, variable[name, t])
    end
    return
end

# Compact formulation does not accept QuadraticCurve fuel — the SOS gating breaks down
# for quadratic terms.
_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{W}, _, _, ::PSY.ThermalGen, ::PSY.FuelCurve,
    ::PSY.QuadraticCurve, ::Float64, ::Float64, ::Float64, _,
) where {W <: AbstractDeviceFormulation} =
    error("Quadratic Curves are not accepted with Compact Formulation: $W")

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.PiecewisePointCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.IncrementalCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

_add_compact_fuel_consumption_term!(
    ::OptimizationContainer, ::Type{<:AbstractDeviceFormulation},
    _, _, ::PSY.ThermalGen, ::PSY.FuelCurve, ::PSY.AverageRateCurve,
    ::Float64, ::Float64, ::Float64, _) = nothing

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: FuelConsumptionExpression,
    U <: PowerAboveMinimumVariable,
    V <: PSY.ThermalGen,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U, V)
    time_steps = get_time_steps(container)
    base_power = get_model_base_power(container)
    resolution = get_resolution(container)
    dt = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    for d in devices
        var_cost = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(var_cost) || continue
        expression = get_expression(container, T, V)
        device_base_power = PSY.get_base_power(d, PSY.NU)
        value_curve = PSY.get_value_curve(var_cost)
        _add_compact_fuel_consumption_term!(
            container, W, expression, variable, d, var_cost, value_curve,
            base_power, device_base_power, dt, time_steps,
        )
    end
end
