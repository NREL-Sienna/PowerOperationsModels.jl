#! format: off

"""
`MarketLoadBid`'s reserve range constraint reuses `PowerLoadDispatch`'s [0, max_active_power]
bound (electric_loads.jl), applied to the parameter-anchored range expressions instead of the
energy variable -- see the formulation docstring in `core/formulations.jl`.
"""
get_min_max_limits(
    d::PSY.ControllableLoad,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{MarketLoadBid},
) = (min = 0.0, max = PSY.get_max_active_power(d, PSY.SU))

#! format: on

"""
Seeds `ActivePowerRangeExpressionLB`/`UB` with the constant `max_active_power` (device
parameter, system per-unit) rather than the device's own `ActivePowerVariable`. This is the
decoupling documented on [`MarketLoadBid`](@ref): reserve eligibility rides the load's rated
capacity, not its (possibly zero-fixed) market energy. Reserve-service construction later adds
`\\mp r` terms into these same containers via the standard `PSY.ElectricLoad` reserve
machinery (`add_to_expression.jl`), keyed only by component type -- so this seeding step and
the service's own additions land in the same expression regardless of call order.
"""
function _seed_market_load_reserve_ranges!(
    container::OptimizationContainer,
    devices::Union{Vector{L}, IS.FlattenIteratorWrapper{L}},
    model::DeviceModel{L, MarketLoadBid},
) where {L <: PSY.ControllableLoad}
    time_steps = get_time_steps(container)
    for T in (ActivePowerRangeExpressionLB, ActivePowerRangeExpressionUB)
        has_container_key(container, T, L) || add_expressions!(container, T, devices, model)
        expression = get_expression(container, T, L)
        for d in devices
            name = PSY.get_name(d)
            pmax = PSY.get_max_active_power(d, PSY.SU)
            for t in time_steps
                add_proportional_to_jump_expression!(expression[name, t], pmax, 1.0)
            end
        end
    end
    return
end

_is_reserve_down_service(::PSY.Reserve{PSY.ReserveDown}) = true
_is_reserve_down_service(::PSY.Service) = false

"""
A `MarketLoadBid` load's reserve ranges are seeded on the constant `max_active_power`
parameter (`_seed_market_load_reserve_ranges!`), both bounded within `[0, max_active_power]`
(`get_min_max_limits`). For an `ElectricLoad`, down-reserve enters the UB expression at
`+1.0` (`add_to_expression.jl`: "Load down-reserve is committed extra consumption"), so with
`P` replaced by the constant `pmax` the UB constraint becomes `pmax + Σr_down <= pmax`, i.e.
`Σr_down <= 0` -- every down-reserve award is structurally forced to zero regardless of
system conditions. Rather than let that surface as a confusing zero award or infeasibility
far from the cause, reject a `MarketLoadBid` device contributing to a ReserveDown-direction
service loudly, naming both.
"""
function _validate_no_reserve_down!(d::PSY.ControllableLoad)
    for service in PSY.get_services(d)
        _is_reserve_down_service(service) || continue
        error(
            "MarketLoadBid device $(PSY.get_name(d)) contributes to ReserveDown service " *
            "$(PSY.get_name(service)): down-reserve is structurally zero for a " *
            "MarketLoadBid load (its reserve range is anchored on the constant " *
            "max_active_power parameter, not its energy variable, so any down-reserve " *
            "award is forced to zero) -- remove the device from the service, or model it " *
            "under a different load formulation.",
        )
    end
    return
end

"""
Argument stage for `MarketLoadBid`: creates `ActivePowerVariable` (bounds `[0, max_active_power]`
from the generic `PSY.ElectricLoad` getters), fixes it to zero every period for a costless
market bid (`_is_costless_offer`), adds every device's energy variable to the single system-wide
`SettlementBalance` row at `-1.0` (a decremental contributor, coefficient added regardless of
priced/costless so the fixed-zero coefficient is exactly-once and provably zero-valued), builds
the priced devices' decremental `MarketBidCost` PWL parameters, and seeds the parameter-anchored
reserve range expressions. Never touches a physical `ActivePowerBalance` row -- the component's
physical forecast is carried by a separate `StaticPowerLoad`-formulated twin `DeviceModel` in
`template.devices`.
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{L, MarketLoadBid},
    ::IOM.MarketModel,
) where {L <: PSY.ControllableLoad}
    devices = get_available_components(model, sys)
    add_cost_expressions!(container, devices, model)
    time_steps = get_time_steps(container)
    settlement_expr = get_expression(container, IOM.SettlementBalance, PSY.System)

    add_variables!(container, ActivePowerVariable, devices, MarketLoadBid)
    p = get_variable(container, ActivePowerVariable, L)

    priced_devices = L[]
    for d in devices
        _validate_no_reserve_down!(d)
        name = PSY.get_name(d)
        _add_settlement_terms!(settlement_expr, p, name, -1.0, time_steps)
        if _is_costless_offer(PSY.get_operation_cost(d))
            for t in time_steps
                JuMP.fix(p[name, t], 0.0; force = true)
            end
        else
            push!(priced_devices, d)
        end
    end

    if !isempty(priced_devices)
        process_market_bid_parameters!(container, priced_devices, model, false, true)
    end

    _seed_market_load_reserve_ranges!(container, devices, model)
    return
end

"""
Model stage for `MarketLoadBid`: bounds the reserve range expressions within
`[0, max_active_power]` (`get_min_max_limits`, above) and prices priced devices' energy
variable through the standard decremental `MarketBidCost` path (`add_variable_cost!`);
costless devices contribute no objective terms (their variable is fixed to zero).
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{L, MarketLoadBid},
    ::IOM.MarketModel,
) where {L <: PSY.ControllableLoad}
    devices = get_available_components(model, sys)

    # The bare `AbstractNetworkModel` type is unused downstream; it's forced by
    # `construct_market_component!`'s fixed signature (no `NetworkModel` instance available here).
    add_range_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionLB,
        devices,
        model,
        AbstractNetworkModel,
    )
    # Same: type argument only, unused downstream.
    add_range_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerRangeExpressionUB,
        devices,
        model,
        AbstractNetworkModel,
    )

    priced_devices = [d for d in devices if !_is_costless_offer(PSY.get_operation_cost(d))]
    if !isempty(priced_devices)
        wrapped = IS.FlattenIteratorWrapper(L, [priced_devices])
        add_variable_cost!(container, ActivePowerVariable, wrapped, MarketLoadBid)
    end
    return
end
