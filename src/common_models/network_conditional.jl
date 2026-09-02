# Helpers for machinery that should only appear when the network model actually represents
# the relevant physical quantity (reactive power).
#
# Every helper forwards on `reactive_power_support(N)` (core/network_formulations.jl) so the
# active-power-only path is chosen by METHOD DISPATCH, never by a runtime `if`. That is
# load-bearing, not defensive: `make_system_expressions!` allocates
# `ExpressionKey(ReactivePowerBalance, PSY.ACBus)` only under `HasReactivePower()`, so a
# leaked `add_to_expression!` is a `KeyError` during `build!`. The variable side fails more
# quietly — a leaked `add_variables!` produces free, uncosted JuMP columns that change
# neither the objective nor the solution — which is why the trait-vs-reality guard test
# asserts their absence explicitly.

_reactive_support(::NetworkModel{N}) where {N} = reactive_power_support(N)

#################################################################################
# Variables
#################################################################################

"""
Add reactive-power variable `V` for `devices` under formulation `F`, but only when the
network carries a reactive-power balance.
"""
_maybe_add_reactive_power_variable!(
    container::OptimizationContainer,
    ::Type{V},
    devices,
    ::Type{F},
    network_model::NetworkModel,
) where {V <: VariableType, F} = _add_reactive_variable!(
    _reactive_support(network_model),
    container,
    V,
    devices,
    F,
)

_add_reactive_variable!(
    ::HasReactivePower,
    container::OptimizationContainer,
    ::Type{V},
    devices,
    ::Type{F},
) where {V <: VariableType, F} = add_variables!(container, V, devices, F)

_add_reactive_variable!(
    ::NoReactivePower,
    ::OptimizationContainer,
    ::Type{V},
    _devices,
    ::Type{F},
) where {V <: VariableType, F} = nothing

#################################################################################
# Parameters
#################################################################################

"""
Add reactive-power parameter `P` for `devices`, but only when the network carries a
reactive-power balance.
"""
_maybe_add_reactive_power_parameters!(
    container::OptimizationContainer,
    ::Type{P},
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
) where {P <: ParameterType} = _add_reactive_parameters!(
    _reactive_support(network_model),
    container,
    P,
    devices,
    model,
)

_add_reactive_parameters!(
    ::HasReactivePower,
    container::OptimizationContainer,
    ::Type{P},
    devices,
    model::DeviceModel,
) where {P <: ParameterType} = add_parameters!(container, P, devices, model)

_add_reactive_parameters!(
    ::NoReactivePower,
    ::OptimizationContainer,
    ::Type{P},
    _devices,
    ::DeviceModel,
) where {P <: ParameterType} = nothing

#################################################################################
# Expression wiring
#################################################################################

"""
Wire `S` — a `VariableType` or a `ParameterType` — into `ReactivePowerBalance`, but only
when the network carries one. The device-specific `add_to_expression!` method remains
responsible for bus mapping and sign convention.
"""
_maybe_add_reactive_power_balance!(
    container::OptimizationContainer,
    ::Type{S},
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
) where {S <: Union{VariableType, ParameterType}} = _add_reactive_balance!(
    _reactive_support(network_model),
    container,
    S,
    devices,
    model,
    network_model,
)

_add_reactive_balance!(
    ::HasReactivePower,
    container::OptimizationContainer,
    ::Type{S},
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
) where {S <: Union{VariableType, ParameterType}} = add_to_expression!(
    container,
    ReactivePowerBalance,
    S,
    devices,
    model,
    network_model,
)

_add_reactive_balance!(
    ::NoReactivePower,
    ::OptimizationContainer,
    ::Type{S},
    _devices,
    ::DeviceModel,
    ::NetworkModel,
) where {S <: Union{VariableType, ParameterType}} = nothing

#################################################################################
# Constraints
#################################################################################

"""
Add a reactive-power-related constraint for a device, but only when the network carries a
reactive-power balance.
"""
_maybe_add_reactive_power_constraints!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
    constraint_type::Type{<:ConstraintType},
) = _add_reactive_constraints!(
    _reactive_support(network_model),
    container,
    devices,
    model,
    network_model,
    constraint_type,
)

_add_reactive_constraints!(
    ::HasReactivePower,
    container::OptimizationContainer,
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
    constraint_type::Type{<:ConstraintType},
) = add_constraints!(container, constraint_type, devices, model, network_model)

_add_reactive_constraints!(
    ::NoReactivePower,
    ::OptimizationContainer,
    _devices,
    ::DeviceModel,
    ::NetworkModel,
    ::Type{<:ConstraintType},
) = nothing

"""
Variable-typed form: adds a reactive-power constraint built from a specific variable (the
6-arg `add_constraints!` form), but only when the network carries a reactive-power balance.
"""
_maybe_add_reactive_power_constraints!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
    constraint_type::Type{<:ConstraintType},
    variable_type::Type{<:VariableType},
) = _add_reactive_constraints!(
    _reactive_support(network_model),
    container,
    devices,
    model,
    network_model,
    constraint_type,
    variable_type,
)

_add_reactive_constraints!(
    ::HasReactivePower,
    container::OptimizationContainer,
    devices,
    model::DeviceModel,
    network_model::NetworkModel,
    constraint_type::Type{<:ConstraintType},
    variable_type::Type{<:VariableType},
) = add_constraints!(
    container,
    constraint_type,
    variable_type,
    devices,
    model,
    network_model,
)

_add_reactive_constraints!(
    ::NoReactivePower,
    ::OptimizationContainer,
    _devices,
    ::DeviceModel,
    ::NetworkModel,
    ::Type{<:ConstraintType},
    ::Type{<:VariableType},
) = nothing

#################################################################################
# Coupled convenience
#################################################################################

"""
Add each variable type in `var_types` and wire it straight into `ReactivePowerBalance`.

Use only where the `add_variables!` and `add_to_expression!` calls are ALREADY adjacent —
routing non-adjacent calls through this helper moves reactive column creation past the
intervening `add_variables!`/`add_parameters!` calls, which reorders the JuMP model.
"""
function _maybe_add_reactive_power_variables!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{D, F},
    network_model::NetworkModel,
    var_types,
) where {D, F}
    for V in var_types
        _maybe_add_reactive_power_variable!(container, V, devices, F, network_model)
        _maybe_add_reactive_power_balance!(container, V, devices, model, network_model)
    end
    return
end
