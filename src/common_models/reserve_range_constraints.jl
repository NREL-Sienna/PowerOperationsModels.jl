# moved from IOM because they need FooPowerVariableLimitsConstraint.
@doc raw"""
Constructs min/max range constraint from device variable and reservation decision variable.



``` varcts[name, t] <= limits.max * (1 - varbin[name, t]) ```

``` varcts[name, t] >= limits.min * (1 - varbin[name, t]) ```

where limits in constraint_infos.

# LaTeX

`` 0 \leq x^{cts} \leq limits^{max} (1 - x^{bin}), \text{ for } limits^{min} = 0 ``

`` limits^{min} (1 - x^{bin}) \leq x^{cts} \leq limits^{max} (1 - x^{bin}), \text{ otherwise } ``
"""
function add_reserve_range_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::Type{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: VariableType,
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
    X <: AbstractPowerModel,
}
    array = get_variable(container, U(), V)
    add_reserve_bound_range_constraints!(
        container, T, LowerBound(), array, devices, model, true)
    add_reserve_bound_range_constraints!(
        container, T, UpperBound(), array, devices, model, true)
    return
end

function add_reserve_range_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::Type{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: ExpressionType,
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
    X <: AbstractPowerModel,
}
    array = get_expression(container, U(), W)
    add_reserve_bound_range_constraints!(
        container, T, get_bound_direction(U()), array, devices, model, true)
    return
end

@doc raw"""
Constructs min/max range constraint from device variable and reservation decision variable.



``` varcts[name, t] <= limits.max * varbin[name, t] ```

``` varcts[name, t] >= limits.min * varbin[name, t] ```

where limits in constraint_infos.

# LaTeX

`` limits^{min} x^{bin} \leq x^{cts} \leq limits^{max} x^{bin},``
"""
function add_reserve_range_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{W},
    model::DeviceModel{W, X},
    ::Type{Y},
) where {
    T <:
    Union{
        ReactivePowerVariableLimitsConstraint,
        ActivePowerVariableLimitsConstraint,
        OutputActivePowerVariableLimitsConstraint,
    },
    U <: VariableType,
    W <: PSY.Component,
    X <: AbstractDeviceFormulation,
    Y <: AbstractPowerModel,
}
    array = get_variable(container, U(), W)
    add_reserve_bound_range_constraints!(
        container, T, LowerBound(), array, devices, model, false)
    add_reserve_bound_range_constraints!(
        container, T, UpperBound(), array, devices, model, false)
    return
end

@doc raw"""
Constructs min/max range constraint from device variable and reservation decision variable.



``` varcts[name, t] <= limits.max * varbin[name, t] ```

``` varcts[name, t] >= limits.min * varbin[name, t] ```

where limits in constraint_infos.

# LaTeX

`` limits^{min} x^{bin} \leq x^{cts} \leq limits^{max} x^{bin},``
"""
function add_reserve_range_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{W},
    model::DeviceModel{W, X},
    ::Type{Y},
) where {
    T <:
    Union{
        ReactivePowerVariableLimitsConstraint,
        ActivePowerVariableLimitsConstraint,
        OutputActivePowerVariableLimitsConstraint,
    },
    U <: ExpressionType,
    W <: PSY.Component,
    X <: AbstractDeviceFormulation,
    Y <: AbstractPowerModel,
}
    array = get_expression(container, U(), W)
    add_reserve_bound_range_constraints!(
        container, T, get_bound_direction(U()), array, devices, model, false)
    return
end
