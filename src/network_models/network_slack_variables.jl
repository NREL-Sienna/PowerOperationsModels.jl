#! format: off
get_variable_multiplier(::Type{SystemBalanceSlackUp}, ::Type{<: Union{PSY.ACBus, PSY.Area, PSY.System}}, ::Type{<:AbstractDeviceFormulation}) = 1.0
get_variable_multiplier(::Type{SystemBalanceSlackDown}, ::Type{<: Union{PSY.ACBus, PSY.Area, PSY.System}}, ::Type{<:AbstractDeviceFormulation}) = -1.0
get_variable_multiplier(::Type{SystemBalanceSlackUp}, ::Type{<: Union{PSY.ACBus, PSY.Area, PSY.System}}, ::Type{<:AbstractNetworkModel}) = 1.0
get_variable_multiplier(::Type{SystemBalanceSlackDown}, ::Type{<: Union{PSY.ACBus, PSY.Area, PSY.System}}, ::Type{<:AbstractNetworkModel}) = -1.0
#! format: on

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    ::PSY.System,
    network_model::NetworkModel{U},
) where {
    T <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    U <: Union{CopperPlateNetworkModel, PTDFNetworkModel},
}
    time_steps = get_time_steps(container)
    reference_buses = get_reference_buses(network_model)
    variable =
        add_variable_container!(container, T, PSY.System, reference_buses, time_steps)

    for t in time_steps, bus in reference_buses
        variable[bus, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "slack_{$(T), $(bus), $t}",
            lower_bound = 0.0
        )
    end
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    sys::PSY.System,
    network_model::NetworkModel{U},
) where {
    T <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    U <: Union{AreaBalanceNetworkModel, AreaPTDFNetworkModel},
}
    time_steps = get_time_steps(container)
    areas = get_name.(get_available_components(network_model, PSY.Area, sys))
    variable =
        add_variable_container!(container, T, PSY.Area, areas, time_steps)

    for t in time_steps, area in areas
        variable[area, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "slack_{$(T), $(area), $t}",
            lower_bound = 0.0
        )
    end

    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    sys::PSY.System,
    network_model::NetworkModel{U},
) where {
    T <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    U <: AbstractActivePowerModel,
}
    time_steps = get_time_steps(container)
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        bus_numbers =
            PSY.get_number.(get_available_components(network_model, PSY.ACBus, sys))
    else
        bus_numbers = collect(keys(PNM.get_bus_reduction_map(network_reduction)))
    end

    variable = add_variable_container!(container, T, PSY.ACBus, bus_numbers, time_steps)
    for t in time_steps, n in bus_numbers
        variable[n, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "slack_{$(T), $n, $t}",
            lower_bound = 0.0
        )
    end
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    sys::PSY.System,
    network_model::NetworkModel{U},
) where {
    T <: Union{SystemBalanceSlackUp, SystemBalanceSlackDown},
    U <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    network_reduction = get_network_reduction(network_model)
    if isempty(network_reduction)
        bus_numbers =
            PSY.get_number.(get_available_components(network_model, PSY.ACBus, sys))
    else
        bus_numbers = collect(keys(PNM.get_bus_reduction_map(network_reduction)))
    end
    variable_active =
        add_variable_container!(container, T, PSY.ACBus, "P", bus_numbers, time_steps)
    variable_reactive =
        add_variable_container!(container, T, PSY.ACBus, "Q", bus_numbers, time_steps)

    for t in time_steps, n in bus_numbers
        variable_active[n, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "slack_{p, $(T), $n, $t}",
            lower_bound = 0.0
        )
        variable_reactive[n, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "slack_{q, $(T), $n, $t}",
            lower_bound = 0.0
        )
    end
    return
end

"""
Cost applied to physical balance slacks (`SystemBalanceSlackUp`/`SystemBalanceSlackDown`).
Zero when a market model is present: the settlement balance is the binding accounting
identity there, and the physical slack exists only so the network's own balance stays
feasible independent of the settlement outcome.

Two consequences of pricing both slack directions at exactly `0.0`, by design, not oversight:

  - The physical balance's own dual is **identically zero** under a market model. LP dual
    feasibility on `e(x) + s_up - s_dn == 0` with `s_up, s_dn >= 0` and both carrying a zero
    objective coefficient forces `λ <= 0` (from `s_up`) and `λ >= 0` (from `s_dn`), so
    `λ ≡ 0`. Requesting `CopperPlateBalanceConstraint` (or the nodal equivalent) in
    `NetworkModel.duals` alongside a market model is meaningless — the settlement dual
    (`SettlementBalanceConstraint`) is the price signal in this design, not the physical one.
  - The individual `(s_up, s_dn)` split is **not unique**: with both free and unpenalized,
    `(s_up, s_dn) = (a + k, k)` is optimal for every `k >= 0`, an unbounded ray inside the
    optimal face. Only the **NET** value `s_up - s_dn` is a well-defined unserved-physical-
    load measure — it equals the true imbalance `-e(x)` regardless of which vertex the
    solver's presolve/simplex path happens to land on. Never read `s_up` (or `s_dn`) alone as
    "the" unserved load under a market model; always read the net.
"""
_balance_slack_cost(::NetworkModel, ::Nothing) = BALANCE_SLACK_COST
_balance_slack_cost(::NetworkModel, ::IOM.MarketModel) = 0.0

"""
Whether the physical balance carries `SystemBalanceSlackUp`/`SystemBalanceSlackDown`. A
market model forces them on regardless of `use_slacks` — priced at `0.0`
([`_balance_slack_cost`](@ref)) so the network's own balance stays feasible independent of
the settlement outcome.
"""
_uses_balance_slacks(model::NetworkModel, ::Nothing) = get_use_slacks(model)
_uses_balance_slacks(::NetworkModel, ::IOM.MarketModel) = true

function add_to_objective_function!(
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel{T},
    market_model::Union{Nothing, IOM.MarketModel},
) where {T <: Union{CopperPlateNetworkModel, PTDFNetworkModel}}
    variable_up = get_variable(container, SystemBalanceSlackUp, PSY.System)
    variable_dn = get_variable(container, SystemBalanceSlackDown, PSY.System)
    reference_buses = get_reference_buses(network_model)
    cost = _balance_slack_cost(network_model, market_model)

    for t in get_time_steps(container), n in reference_buses
        add_to_objective_invariant_expression!(
            container,
            (variable_dn[n, t] + variable_up[n, t]) * cost,
        )
    end
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel{T},
    market_model::Union{Nothing, IOM.MarketModel},
) where {T <: Union{AreaBalanceNetworkModel, AreaPTDFNetworkModel}}
    variable_up = get_variable(container, SystemBalanceSlackUp, PSY.Area)
    variable_dn = get_variable(container, SystemBalanceSlackDown, PSY.Area)
    areas = PSY.get_name.(get_available_components(network_model, PSY.Area, sys))
    cost = _balance_slack_cost(network_model, market_model)

    for t in get_time_steps(container), n in areas
        add_to_objective_invariant_expression!(
            container,
            (variable_dn[n, t] + variable_up[n, t]) * cost,
        )
    end
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel{T},
    market_model::Union{Nothing, IOM.MarketModel},
) where {T <: AbstractActivePowerModel}
    variable_up = get_variable(container, SystemBalanceSlackUp, PSY.ACBus)
    variable_dn = get_variable(container, SystemBalanceSlackDown, PSY.ACBus)
    bus_numbers = axes(variable_up)[1]
    IS.@assert_op bus_numbers == axes(variable_dn)[1]
    cost = _balance_slack_cost(network_model, market_model)
    for t in get_time_steps(container), n in bus_numbers
        add_to_objective_invariant_expression!(
            container,
            (variable_dn[n, t] + variable_up[n, t]) * cost,
        )
    end
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel{T},
    market_model::Union{Nothing, IOM.MarketModel},
) where {T <: AbstractNetworkModel}
    variable_p_up = get_variable(container, SystemBalanceSlackUp, PSY.ACBus, "P")
    variable_p_dn = get_variable(container, SystemBalanceSlackDown, PSY.ACBus, "P")
    variable_q_up = get_variable(container, SystemBalanceSlackUp, PSY.ACBus, "Q")
    variable_q_dn = get_variable(container, SystemBalanceSlackDown, PSY.ACBus, "Q")
    bus_numbers = axes(variable_p_up)[1]
    IS.@assert_op bus_numbers == axes(variable_q_dn)[1]
    cost = _balance_slack_cost(network_model, market_model)
    for t in get_time_steps(container), n in bus_numbers
        add_to_objective_invariant_expression!(
            container,
            (
                variable_p_dn[n, t] +
                variable_p_up[n, t] +
                variable_q_dn[n, t] +
                variable_q_up[n, t]
            ) * cost,
        )
    end
    return
end
