"""
Physical-bid dispatch variables: the injection/withdrawal variables generation, storage, and
priced controllable loads already contribute to `ActivePowerBalance`. These are the only
variable types that enter the settlement row alongside the market components — fixed
parameters (forecasts, `StaticPowerLoad`) never do, since a settlement term must be a cleared
bid, not a forecast. `PowerAboveMinimumVariable` covers the compact thermal family
(`ThermalCompactDispatch`/`AbstractCompactUnitCommitment`, whose dispatch variable is power
above minimum rather than total power); `ActivePowerPumpVariable` covers `HydroPumpTurbine`'s
withdrawal. Each type's own `get_variable_multiplier` is the same one its physical
`ActivePowerBalance` contribution uses, so this sweep mirrors that row exactly for every
formulation whose physical injection is a plain `variable * multiplier` term. The compact-UC
family's SECOND physical term — the pmin-scaled `OnVariable` (`_add_pmin_scaled_on_to_balance!`)
— is not a plain multiplier term (it also scales by each device's own `p_min`) and is mirrored
separately by [`_add_compact_on_term_to_settlement!`](@ref).
"""
const PHYSICAL_BID_VARIABLE_TYPES = (
    ActivePowerVariable,
    ActivePowerInVariable,
    ActivePowerOutVariable,
    PowerAboveMinimumVariable,
    ActivePowerPumpVariable,
)

"""
Function barrier for the settlement sweep: [`add_physical_bids_to_settlement!`](@ref) reads
`variable`, `multiplier`, and the settlement expression out of abstractly-typed containers
keyed by runtime `DataType`s, so the term-writing loop is compiled here against the concrete
argument types instead of dispatching dynamically once per `(name, t)`.
"""
function _add_settlement_terms!(
    settlement_expr,
    variable,
    name,
    multiplier::Float64,
    time_steps,
)
    for t in time_steps
        add_proportional_to_jump_expression!(
            settlement_expr[1, t],
            variable[name, t],
            multiplier,
        )
    end
    return
end

function _add_settlement_terms!(settlement_expr, variable, multiplier::Float64, time_steps)
    for name in axes(variable)[1]
        _add_settlement_terms!(settlement_expr, variable, name, multiplier, time_steps)
    end
    return
end

"""
Mirror the compact-UC pmin-scaled `OnVariable` term into the settlement row (see
[`PHYSICAL_BID_VARIABLE_TYPES`](@ref)'s docstring). No-op for every other device/formulation
pair — only `AbstractCompactUnitCommitment` formulations for `PSY.ThermalGen` add an
`OnVariable` term to `ActivePowerBalance` beyond their `PowerAboveMinimumVariable`. Mirrors
`_add_pmin_scaled_on_to_balance!` (CopperPlateNetworkModel's no-must-run-branch variant),
which is exact since [`_check_market_model!`](@ref) restricts a market model to
`CopperPlateNetworkModel`.
"""
function _add_compact_on_term_to_settlement!(
    ::OptimizationContainer,
    settlement_expr,
    sys::PSY.System,
    ::Type{V},
    ::Type{W},
    time_steps,
) where {V <: IS.InfrastructureSystemsComponent, W}
    return
end

function _add_compact_on_term_to_settlement!(
    container::OptimizationContainer,
    settlement_expr,
    sys::PSY.System,
    ::Type{V},
    ::Type{W},
    time_steps,
) where {V <: PSY.ThermalGen, W <: AbstractCompactUnitCommitment}
    has_container_key(container, OnVariable, V) || return
    on = get_variable(container, OnVariable, V)
    base_multiplier = get_variable_multiplier(OnVariable, V, W)
    for name in axes(on)[1]
        d = PSY.get_component(V, sys, name)
        pmin_multiplier = PSY.get_active_power_limits(d, PSY.SU).min * base_multiplier
        _add_settlement_terms!(settlement_expr, on, name, pmin_multiplier, time_steps)
    end
    return
end

"""
Add generation, storage, and priced controllable load physical-bid dispatch variables to the
settlement row, mirroring each device's `ActivePowerBalance` contribution (same variable,
same `get_variable_multiplier`) into `SettlementBalance`. Covers
[`PHYSICAL_BID_VARIABLE_TYPES`](@ref) plus the compact-UC pmin-scaled `OnVariable` term
([`_add_compact_on_term_to_settlement!`](@ref)) — variables only, never parameters. Must be
called from the market Argument stage after device variables exist.
"""
function add_physical_bids_to_settlement!(
    container::OptimizationContainer,
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    settlement_expr = get_expression(container, IOM.SettlementBalance, PSY.System)
    time_steps = get_time_steps(container)
    for device_model in values(get_device_models(template))
        V = get_component_type(device_model)
        W = get_formulation(device_model)
        for U in PHYSICAL_BID_VARIABLE_TYPES
            has_container_key(container, U, V) || continue
            _add_settlement_terms!(
                settlement_expr,
                get_variable(container, U, V),
                get_variable_multiplier(U, V, W),
                time_steps,
            )
        end
        _add_compact_on_term_to_settlement!(
            container,
            settlement_expr,
            sys,
            V,
            W,
            time_steps,
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    sys::U,
    market_model::IOM.MarketModel,
) where {T <: SettlementBalanceConstraint, U <: PSY.System}
    time_steps = get_time_steps(container)
    expr = get_expression(container, IOM.SettlementBalance, U)
    row_axis = axes(expr)[1]
    constraint = add_constraints_container!(container, T, U, row_axis, time_steps)
    jm = get_jump_model(container)
    for t in time_steps, k in row_axis
        constraint[k, t] = JuMP.@constraint(jm, expr[k, t] == 0)
    end
    return
end

########################### Dual variable handling ####################################
# SettlementBalanceConstraint is System-keyed, mirroring how CopperPlateBalanceConstraint's
# dual is special-cased (network_models/copperplate_model.jl).

function add_constraint_dual!(
    container::OptimizationContainer,
    sys::PSY.System,
    market_model::IOM.MarketModel,
)
    if !isempty(IOM.get_duals(market_model))
        for constraint_type in IOM.get_duals(market_model)
            assign_dual_variable!(container, constraint_type, sys, market_model)
        end
    end
    return
end

function assign_dual_variable!(
    container::OptimizationContainer,
    constraint_type::Type{SettlementBalanceConstraint},
    ::U,
    ::IOM.MarketModel,
) where {U <: PSY.System}
    time_steps = get_time_steps(container)
    row_axis = axes(get_constraint(container, ConstraintKey(constraint_type, U)))[1]
    add_dual_container!(container, constraint_type, U, row_axis, time_steps)
    return
end

function _calculate_dual_variable_value!(
    container::OptimizationContainer,
    key::ConstraintKey{SettlementBalanceConstraint, PSY.System},
    ::PSY.System,
)
    constraint_container = get_constraint(container, key)
    dual_variable_container = get_duals(container)[key]
    for row in axes(constraint_container)[1], t in axes(constraint_container)[2]
        dual_variable_container[row, t] = jump_value(constraint_container[row, t])
    end
    return
end
