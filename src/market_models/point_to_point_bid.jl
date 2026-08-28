#! format: off
get_variable_binary(::Type{ClearedTransferVariable}, ::Type{PSY.PointToPointBid}, ::Type{SpreadBid}) = false
get_variable_lower_bound(::Type{ClearedTransferVariable}, ::PSY.PointToPointBid, ::Type{SpreadBid}) = 0.0
# `max_active_power` is a plain natural-units MW field (not a convertible field), so the
# bound divides explicitly by the system base power, as `VirtualBidDispatch` does.
get_variable_upper_bound(::Type{ClearedTransferVariable}, d::PSY.PointToPointBid, ::Type{SpreadBid}) =
    PSY.get_max_active_power(d) / PSY.get_base_power(d, PSY.NU)
#! format: on

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
    variable = add_variable_container!(
        container, ClearedTransferVariable, PSY.PointToPointBid, names, time_steps,
    )
    jump_model = get_jump_model(container)
    for bid in bids
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
    return
end

"""
Model stage for `SpreadBid`: no constraints beyond the variable bounds. The spread
willingness-to-pay (`PSY.get_spread_bid`) is not yet priced into the objective, so the bid
clears at zero cost up to congestion.
"""
function construct_market_component!(
    ::OptimizationContainer,
    ::PSY.System,
    ::ModelConstructStage,
    ::DeviceModel{PSY.PointToPointBid, SpreadBid},
    ::IOM.MarketModel,
    ::NetworkModel{<:AbstractNetworkModel},
)
    return
end
