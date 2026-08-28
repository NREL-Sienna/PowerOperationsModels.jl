"""
Distribution factors multiply cleared-quantity variables, so they must reach JuMP as
numbers. `IOM.get_param_eltype` returns `JuMP.VariableRef` for recurrent solves with
`rebuild_model` off, which would make `df * cleared_q` a product of two variable
references. Guard at build time rather than surfacing as a solver error mid-simulation.
"""
function assert_numeric_distribution_factors(container::OptimizationContainer)
    if IOM.get_param_eltype(container) !== Float64
        error(
            "Nodal distribution requires rebuild_model = true. With recurrent solves " *
            "and rebuild_model off, DistributionFactorParameter would hold JuMP " *
            "parameters and df * cleared_q would be nonlinear.",
        )
    end
    return
end

# Membership differs by location type: dispatch, never branch on the type.
get_member_buses(::PSY.System, bus::PSY.ACBus) = [bus]
get_member_buses(sys::PSY.System, zone::PSY.LoadZone) = PSY.get_buses(sys, zone)
get_member_buses(::PSY.System, hub::PSY.TradingHub) = PSY.get_buses(hub)

"""
Feature key of the `distribution_factor` series a settlement location carries for one of
its member buses. `PSY.ACBus` does not own time series, so the location owns one series per
member bus, distinguished by the bus number feature; InfrastructureSystems stores every
series sharing a name in one table, buses as columns.
"""
bus_factor_features(bus::PSY.ACBus) = Dict{String, Any}("bus" => PSY.get_number(bus))

function _has_factor_series(location::PSY.Component, bus::PSY.ACBus)
    return IS.has_time_series(
        location, IS.Deterministic, DISTRIBUTION_FACTOR_TS_NAME;
        features = bus_factor_features(bus),
    )
end

function _any_factor_series(
    location::T,
    buses,
) where {T <: Union{PSY.LoadZone, PSY.TradingHub}}
    return any(b -> _has_factor_series(location, b), buses)
end

function _zero_factors(
    container::OptimizationContainer,
    buses::Vector{PSY.ACBus},
    network_model::NetworkModel,
)
    reduction = get_network_reduction(network_model)
    bus_numbers = sort!(unique([PNM.get_mapped_bus_number(reduction, b) for b in buses]))
    time_steps = get_time_steps(container)
    factors = JuMP.Containers.DenseAxisArray(
        zeros(length(bus_numbers), length(time_steps)), bus_numbers, time_steps,
    )
    return reduction, factors
end

"""
Read the per-bus distribution factors for `location` (one series per member bus, owned by
the location, keyed by [`bus_factor_features`](@ref)) into a numeric
`(retained bus number, timestep)` array. A member bus without a factor series contributes
`0.0`: ERCOT membership rules admit abandoned buses, and factor-set quality (summing to one)
is an ingestion concern, not a modeling one. Factors on buses eliminated by the network
reduction are summed into their retained bus.
"""
function get_distribution_factors(
    container::OptimizationContainer,
    sys::PSY.System,
    location::T,
    network_model::NetworkModel{U},
) where {T <: Union{PSY.LoadZone, PSY.TradingHub}, U <: AbstractNetworkModel}
    buses = get_member_buses(sys, location)
    if !_any_factor_series(location, buses)
        return _fallback_factors(container, location, buses, network_model)
    end
    reduction, factors = _zero_factors(container, buses, network_model)
    time_steps = get_time_steps(container)
    initial_time = get_initial_time(container)
    for bus in buses
        _has_factor_series(location, bus) || continue
        values = IS.get_time_series_values(
            IS.Deterministic, location, DISTRIBUTION_FACTOR_TS_NAME;
            start_time = initial_time, len = length(time_steps),
            features = bus_factor_features(bus),
        )
        bus_no = PNM.get_mapped_bus_number(reduction, bus)
        for t in time_steps
            factors[bus_no, t] += values[t]
        end
    end
    @debug "Distribution factor sums for $(PSY.get_name(location))" [
        sum(factors[:, t]) for t in time_steps
    ] _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    return factors
end

"""A nodal settlement point distributes to itself: identity, factor 1.0."""
function get_distribution_factors(
    container::OptimizationContainer,
    ::PSY.System,
    bus::PSY.ACBus,
    network_model::NetworkModel{U},
) where {U <: AbstractNetworkModel}
    reduction = get_network_reduction(network_model)
    bus_no = PNM.get_mapped_bus_number(reduction, bus)
    time_steps = get_time_steps(container)
    return JuMP.Containers.DenseAxisArray(ones(1, length(time_steps)), [bus_no], time_steps)
end

# A LoadZone with no series anywhere is a data defect the ingestion side owns, but the
# zone still cannot silently vanish from the model: error naming the fix.
function _fallback_factors(
    ::OptimizationContainer,
    zone::PSY.LoadZone,
    ::Vector{PSY.ACBus},
    ::NetworkModel,
)
    error(
        "Load zone $(PSY.get_name(zone)) has no $(DISTRIBUTION_FACTOR_TS_NAME) series for " *
        "any member bus. Attach one Deterministic series per member bus to the zone with " *
        "features (\"bus\" => bus number).",
    )
end

# A hub with no series distributes uniformly across its member buses: PSY documents hub
# member buses as unweighted, so uniform is a declared default, not a silent fallback.
function _fallback_factors(
    container::OptimizationContainer,
    ::PSY.TradingHub,
    buses::Vector{PSY.ACBus},
    network_model::NetworkModel,
)
    reduction, factors = _zero_factors(container, buses, network_model)
    share = 1.0 / length(buses)
    for bus in buses
        bus_no = PNM.get_mapped_bus_number(reduction, bus)
        for t in get_time_steps(container)
            factors[bus_no, t] += share
        end
    end
    return factors
end

const SettlementLocation = Union{PSY.ACBus, PSY.LoadZone, PSY.TradingHub}

"""
Settlement locations are topology and market components with no `available` flag, so
`get_available_components` does not apply. Honors the model's subsystem and
`"filter_function"` attribute the same way.
"""
function get_settlement_locations(
    model::DeviceModel{T, NodalRedistribution},
    sys::PSY.System,
) where {T <: SettlementLocation}
    subsystem = get_subsystem(model)
    filter_function = get_attribute(model, "filter_function")
    if filter_function === nothing
        return PSY.get_components(T, sys; subsystem_name = subsystem)
    end
    return PSY.get_components(filter_function, T, sys; subsystem_name = subsystem)
end

"""
Write a signed contribution into a settlement location's cleared-position expression.
The single API market transactions use; an unhandled location type (an `Area` or `Arc`)
has no method and fails loudly.
"""
function add_cleared_position!(
    container::OptimizationContainer,
    location::T,
    variable::JuMP.VariableRef,
    multiplier::Float64,
    t::Int,
) where {T <: SettlementLocation}
    expression = get_expression(container, AggregateClearedInjection, T)
    add_proportional_to_jump_expression!(
        expression[PSY.get_name(location), t], variable, multiplier,
    )
    return
end

function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{T, NodalRedistribution},
    ::IOM.MarketModel,
    ::NetworkModel{<:AbstractNetworkModel},
) where {T <: SettlementLocation}
    assert_numeric_distribution_factors(container)
    names = PSY.get_name.(get_settlement_locations(model, sys))
    time_steps = get_time_steps(container)
    add_expression_container!(container, AggregateClearedInjection, T, names, time_steps)
    variable = add_variable_container!(
        container, ClearedPositionVariable, T, names, time_steps,
    )
    jump_model = get_jump_model(container)
    for name in names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            base_name = "$(ClearedPositionVariable)_$(T)_{$(name), $(t)}",
        )
    end
    return
end

function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{T, NodalRedistribution},
    ::IOM.MarketModel,
    network_model::NetworkModel{U},
) where {T <: SettlementLocation, U <: AbstractNetworkModel}
    locations = collect(get_settlement_locations(model, sys))
    names = PSY.get_name.(locations)
    time_steps = get_time_steps(container)
    expression = get_expression(container, AggregateClearedInjection, T)
    variable = get_variable(container, ClearedPositionVariable, T)
    constraint = add_constraints_container!(
        container, ClearedPositionConstraint, T, names, time_steps,
    )
    jump_model = get_jump_model(container)
    for name in names, t in time_steps
        constraint[name, t] = JuMP.@constraint(
            jump_model, variable[name, t] == expression[name, t],
        )
    end
    for location in locations
        distribute_cleared_position!(container, sys, location, network_model)
    end
    return
end

"""
Fan a settlement location's cleared position out onto its member buses so a nodal network
model prices the congestion that position creates. Sign-free: every instrument wrote its
own sign into `AggregateClearedInjection`. Inline, one term per bus: no per-bus variable or
constraint. Factors are `Float64` coefficients, so the term stays linear even though the
position is a variable.
"""
function distribute_cleared_position!(
    container::OptimizationContainer,
    sys::PSY.System,
    location::T,
    network_model::NetworkModel{U},
) where {T <: SettlementLocation, U <: AbstractNetworkModel}
    name = PSY.get_name(location)
    factors = get_distribution_factors(container, sys, location, network_model)
    position = get_variable(container, ClearedPositionVariable, T)
    nodal = get_expression(container, ActivePowerBalance, PSY.ACBus)
    for bus_no in axes(factors)[1], t in get_time_steps(container)
        add_proportional_to_jump_expression!(
            nodal[bus_no, t], position[name, t], factors[bus_no, t],
        )
    end
    return
end

# CopperPlate has no nodal expression to distribute into: the cleared position already
# sits in the system balance, so redistribution is a declared no-op, not a silently
# discovered one.
function distribute_cleared_position!(
    ::OptimizationContainer,
    ::PSY.System,
    ::T,
    ::NetworkModel{CopperPlateNetworkModel},
) where {T <: SettlementLocation}
    return
end
