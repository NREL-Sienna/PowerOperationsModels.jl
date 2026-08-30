#! format: off
get_variable_binary(::Type{ClearedTransferVariable}, ::Type{PSY.PointToPointBid}, ::Type{SpreadBid}) = false
get_variable_lower_bound(::Type{ClearedTransferVariable}, ::PSY.PointToPointBid, ::Type{SpreadBid}) = 0.0
# `max_active_power` is a plain natural-units MW field (not a convertible field), so the
# bound divides explicitly by the system base power, as `VirtualBidDispatch` does.
get_variable_upper_bound(::Type{ClearedTransferVariable}, d::PSY.PointToPointBid, ::Type{SpreadBid}) =
    PSY.get_max_active_power(d) / PSY.get_base_power(d, PSY.NU)

# Generic `= 1.0` PWL-parameter fallbacks for market components (not Device)
get_multiplier_value(::Type{<:AbstractPiecewiseLinearSlopeParameter}, ::PSY.PointToPointBid, ::Type{SpreadBid}) = 1.0
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.PointToPointBid, ::Type{SpreadBid}) = 1.0
#! format: on

"""
A spread bid prices a single award, so the offer direction is a pure function of the
formulation and the one-argument trait suffices. Incremental is the economically correct
side: the cleared quantity `q` injects at `to` and withdraws at `from`, so the system saving
from a marginal MW is the `to`-minus-`from` price spread, and a convex increasing cost term
`C(q)` clears the bid up to `C'(q) = spread`. That is exactly a willingness-to-pay curve on
the spread, and it matches PSY's "incremental side only" contract for `spread_bid`.
"""
IOM._vom_offer_direction(::Type{SpreadBid}) = IOM.IncrementalOffer()

"""
Reject a `spread_bid` that cannot mean what a spread bid means.

FIXED/VARIABLE block-bid clearing is not modelled: a spread bid's whole model is one
divisible quantity per period, so a block style would be priced here as if divisible.

A willingness-to-pay on the `to`-minus-`from` spread lives on the incremental side (PSY
documents `spread_bid` as "incremental side only", and see `_vom_offer_direction` for why
that is the economically correct side). A curve authored on the decremental side would
otherwise leave the bid looking unpriced and clearing free, so it is rejected rather than
skipped. Both mirror `VirtualBidDispatch`'s `_validate_block_bid_vom!` idiom.
"""
function _validate_spread_bid!(container::OptimizationContainer, bid::PSY.PointToPointBid)
    cost = IOM.get_operation_cost(bid)
    name = PSY.get_name(bid)
    style = _curve_style(cost)
    if style != PSY.CurveStyles.CURVE
        error(
            "PointToPointBid $(name) has spread_bid curve_style $(style). Only CURVE is " *
            "supported: a spread bid clears as one divisible quantity per period, so " *
            "FIXED/VARIABLE block clearing has no meaning for it.",
        )
    end
    if _offer_curve_is_genuine(container, bid, get_input_offer_curves(cost))
        error(
            "PointToPointBid $(name) has a decremental spread_bid curve. A spread bid's " *
            "willingness-to-pay belongs on the incremental side; a decremental curve is " *
            "never priced and would leave the bid clearing free.",
        )
    end
    return
end

"""
Warn on a spread bid whose incremental curve is the `MarketBidCost(nothing)` placeholder (or
a stored-but-inert time series). Such a bid carries no willingness-to-pay, so it contributes
no objective term and clears its full `max_active_power` envelope whenever the spread is
favourable — free optionality that is almost never intended. It is a warning rather than an
error because an unpriced envelope is a representable instrument, but it must not pass
silently.
"""
function _spread_bid_is_priced(
    container::OptimizationContainer,
    bid::PSY.PointToPointBid,
)
    curve = get_output_offer_curves(IOM.get_operation_cost(bid))
    if !_offer_curve_is_genuine(container, bid, curve)
        @warn "PointToPointBid $(PSY.get_name(bid)) has no incremental spread_bid curve. " *
              "It contributes no objective term and will clear its full " *
              "$(PSY.get_max_active_power(bid)) MW envelope up to congestion."
        return false
    end
    return true
end

"""
Validate the spread bids and add the incremental PWL parameters (slope/breakpoint) that a
time-series-backed `spread_bid` prices against. Mirrors `process_virtual_bid_parameters!`;
only the incremental side is processed, since PSY stores a spread bid's willingness-to-pay
curve on the incremental side only, and there are no startup/shutdown/cost-at-min fields to
process for a bid that carries no commitment.
"""
function process_spread_bid_parameters!(
    container::OptimizationContainer,
    bids,
    model::DeviceModel,
)
    for param in (
        IncrementalPiecewiseLinearSlopeParameter,
        IncrementalPiecewiseLinearBreakpointParameter,
    )
        _process_occ_parameters_helper(param, container, model, bids)
    end
    return
end

"""
Argument stage for `SpreadBid`: a point-to-point spread bid is one cleared quantity at two
locations with opposite signs, a withdrawal at `from` and an injection at `to`. The two
`add_cleared_position!` writes are the whole model of the instrument. Because they cancel
and each location's factor set is what distributes them, the bid contributes nothing net
system-wide and moves the solution only through the nodal pattern, which is what an
up-to-congestion bid is. It is excluded from `SettlementBalance` outright: its two settlement
terms would cancel exactly, so writing them would add non-zero entries for no effect. A
terminal type without a `NodalRedistribution` component model in the template fails loudly
on the missing `AggregateClearedInjection` container.

The stage also adds the incremental PWL parameters a time-series-backed `spread_bid` is
priced against in the model stage.
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.PointToPointBid, SpreadBid},
    ::IOM.MarketModel,
    ::NetworkModel{<:AbstractNetworkModel},
)
    bids = collect(get_available_components(model, sys))
    names = PSY.get_name.(bids)
    time_steps = get_time_steps(container)
    add_cost_expressions!(container, bids, model)
    variable = add_variable_container!(
        container, ClearedTransferVariable, PSY.PointToPointBid, names, time_steps,
    )
    jump_model = get_jump_model(container)
    for bid in bids
        _validate_spread_bid!(container, bid)
        name = PSY.get_name(bid)
        for t in time_steps
            variable[name, t] = JuMP.@variable(
                jump_model,
                base_name = "$(ClearedTransferVariable)_$(PSY.PointToPointBid)_{$(name), $(t)}",
                lower_bound =
                    get_variable_lower_bound(ClearedTransferVariable, bid, SpreadBid),
                upper_bound =
                    get_variable_upper_bound(ClearedTransferVariable, bid, SpreadBid),
            )
            add_cleared_position!(container, PSY.get_from(bid), variable[name, t], -1.0, t)
            add_cleared_position!(container, PSY.get_to(bid), variable[name, t], 1.0, t)
        end
    end
    process_spread_bid_parameters!(container, bids, model)
    return
end

"""
Model stage for `SpreadBid`: the willingness-to-pay curve on the `to`-minus-`from` spread
(`PSY.get_spread_bid`, reached through `IOM.get_operation_cost`) becomes the bid's objective
term through the standard incremental PWL path, so the bid clears up to the quantity where
its marginal bid price meets the cleared spread instead of clearing free.

Two independent quantities bound the award and the tighter one binds: the
`max_active_power` envelope, which bounds the variable directly, and the offer curve's own
top breakpoint, which bounds it through the PWL delta constraint. Authoring them to
different values is legitimate (the curve is the offer), so they are not validated against
each other as `VirtualBidDispatch`'s block bids are.

No other constraints: everything else about the instrument is its two signed position
writes from the argument stage.
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.PointToPointBid, SpreadBid},
    ::IOM.MarketModel,
    ::NetworkModel{<:AbstractNetworkModel},
)
    bids = [
        b for b in get_available_components(model, sys)
        if _spread_bid_is_priced(container, b)
    ]
    isempty(bids) && return
    wrapped = IS.FlattenIteratorWrapper(PSY.PointToPointBid, [bids])
    add_variable_cost!(container, ClearedTransferVariable, wrapped, SpreadBid)
    return
end
