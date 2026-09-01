#! format: off

"""
`PSY.VirtualParticipant`'s `max_supply`/`max_demand` are plain natural-units MW fields
(no `PSY.SU`/`PSY.NU` unit-system argument — not a convertible field), while POM models
in system per-unit. Bounds divide explicitly by the system base power:
`PSY.get_base_power(d, PSY.NU)` falls back to the attached system's base power for a
component with no dedicated device `base_power` field, which is the case here.
"""
get_variable_upper_bound(::Type{ActivePowerOutVariable}, d::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) =
    PSY.get_max_supply(d) / PSY.get_base_power(d, PSY.NU)
get_variable_lower_bound(::Type{ActivePowerOutVariable}, ::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) = 0.0
get_variable_upper_bound(::Type{ActivePowerInVariable}, d::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) =
    PSY.get_max_demand(d) / PSY.get_base_power(d, PSY.NU)
get_variable_lower_bound(::Type{ActivePowerInVariable}, ::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) = 0.0

get_variable_binary(::Type{ActivePowerOutVariable}, ::Type{<:PSY.VirtualParticipant}, ::Type{VirtualBidDispatch}) = false
get_variable_binary(::Type{ActivePowerInVariable}, ::Type{<:PSY.VirtualParticipant}, ::Type{VirtualBidDispatch}) = false

# FIXED-style block-bid commitment (z): binary, unbounded beyond {0,1}.
get_variable_binary(::Type{BlockBidCommitmentVariable}, ::Type{<:PSY.VirtualParticipant}, ::Type{VirtualBidDispatch}) = true

# Generic `= 1.0` PWL-parameter fallbacks for market components (not Device)
get_multiplier_value(::Type{<:AbstractPiecewiseLinearSlopeParameter}, ::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) = 1.0
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.VirtualParticipant, ::Type{VirtualBidDispatch}) = 1.0

#! format: on

"""
Per-variable VOM offer direction for `VirtualBidDispatch`: unlike single-variable
formulations (`IOM._vom_offer_direction(::Type{<:AbstractDeviceFormulation})`), a
`VirtualParticipant` has two independent cost-bearing variables on the SAME formulation, so
the formulation alone cannot tell which curve's VOM applies. `ActivePowerOutVariable` (the
supply/incremental award) reads its VOM off the incremental curve; `ActivePowerInVariable`
(the demand/decremental award) reads its VOM off the decremental curve.
"""
IOM._vom_offer_direction(::Type{ActivePowerOutVariable}, ::Type{VirtualBidDispatch}) =
    IOM.IncrementalOffer()
IOM._vom_offer_direction(::Type{ActivePowerInVariable}, ::Type{VirtualBidDispatch}) =
    IOM.DecrementalOffer()

"""
FIXED/VARIABLE block bids are costed directly from PWL segments
(`_add_block_bid_objective_terms!`), which never reads VOM: only CURVE-style devices go
through the standard `add_variable_cost!` -> `_add_vom_cost_to_objective!` path that does.
A nonzero VOM component on a FIXED/VARIABLE device's offer curve would therefore silently
vanish from the objective, so it is rejected loudly here instead (mirrors the
`ImportExportCost` "VOM cost must be zero" idiom in `_validate_occ_subtype`).
"""
function _validate_block_bid_vom!(d::PSY.VirtualParticipant, style::PSY.CurveStyles)
    style == PSY.CurveStyles.CURVE && return
    cost = PSY.get_operation_cost(d)
    for curve in (get_output_offer_curves(cost), get_input_offer_curves(cost))
        vom = IS.get_proportional_term(IS.get_vom_cost(curve))
        if !iszero(vom)
            error(
                "VirtualParticipant $(PSY.get_name(d)) has curve_style $(style) with a " *
                "nonzero VOM cost ($vom) on an offer curve. VOM is not supported for " *
                "FIXED/VARIABLE block bids (it would silently drop from the objective); " *
                "set the offer curve's vom_cost to zero.",
            )
        end
    end
    return
end

"""
Total MW span `[0, top_breakpoint]` of a static PWL offer curve, the quantity FIXED's `z`
and VARIABLE's shared variable both scale (see [`_validate_block_bid_span!`](@ref)).
"""
_block_bid_offer_span(curve::IS.CostCurve{IS.PiecewiseIncrementalCurve}) =
    last(IS.get_x_coords(IS.get_function_data(IS.get_value_curve(curve))))
_block_bid_offer_span(curve::IS.CostCurve{<:IS.TimeSeriesPiecewiseIncrementalCurve}) = error(
    "Time-series-backed offer curves are not yet supported for FIXED/VARIABLE block bids " *
    "(their envelope-vs-curve span cannot be validated at build time).",
)

"""
FIXED/VARIABLE block bids settle at the envelope (`max_supply`/`max_demand`,
[`_bid_max_mw`](@ref)) but are PRICED over the offer curve's own span
([`_block_bid_curve_value`](@ref)), which is a completely separate field. Nothing else ties
the two together, so a curve authored with a different top breakpoint than the envelope
silently mis-prices the block (it clears the envelope's quantity at the curve's average
price over a different quantity). Rejected loudly here, mirroring
[`_validate_block_bid_vom!`](@ref)'s idiom -- CURVE devices are exempt since their own
per-period variable is bounded directly by the curve (no separate envelope to mismatch).
"""
function _validate_block_bid_span!(d::PSY.VirtualParticipant, style::PSY.CurveStyles)
    style == PSY.CurveStyles.CURVE && return
    cost = PSY.get_operation_cost(d)
    for (meta, curve, envelope) in (
        ("incremental", get_output_offer_curves(cost), PSY.get_max_supply(d)),
        ("decremental", get_input_offer_curves(cost), PSY.get_max_demand(d)),
    )
        IOM.is_nontrivial_offer(curve) || continue
        span = _block_bid_offer_span(curve)
        if !isapprox(span, envelope)
            error(
                "VirtualParticipant $(PSY.get_name(d)) has curve_style $(style) with a " *
                "$(meta) offer curve spanning [0, $span] MW, which does not match its " *
                "$(meta) envelope of $envelope MW. FIXED/VARIABLE block bids settle the " *
                "envelope but are priced over the curve; the two must be equal or the " *
                "bid is silently mispriced. Fix the curve's top breakpoint or the " *
                "envelope field.",
            )
        end
    end
    return
end

"""
Validate `VirtualParticipant` `MarketBidCost`s and add the incremental/decremental PWL
parameters (slope/breakpoint, static or time-series-backed). Mirrors
`process_import_export_parameters!` for `Source`; startup/shutdown/cost-at-min are not
processed here since virtual bids carry no commitment. Runs for every device regardless
of `curve_style`: FIXED/VARIABLE block bids reuse the same PWL parameter machinery as
CURVE bids to evaluate their offer curve.
"""
function process_virtual_bid_parameters!(
    container::OptimizationContainer,
    devices_in,
    model::DeviceModel,
)
    devices = [d for d in devices_in if _has_market_bid_cost(d)]

    for d in devices
        style = _curve_style(PSY.get_operation_cost(d))
        _validate_block_bid_vom!(d, style)
        _validate_block_bid_span!(d, style)
    end

    for param in (
        IncrementalPiecewiseLinearSlopeParameter,
        IncrementalPiecewiseLinearBreakpointParameter,
        DecrementalPiecewiseLinearSlopeParameter,
        DecrementalPiecewiseLinearBreakpointParameter,
    )
        _process_occ_parameters_helper(param, container, model, devices)
    end
    return
end

#################################################################################
# Curve-style variable creation
#
# CURVE: a fresh ActivePowerOutVariable/InVariable JuMP variable per period, divisible
# across [0, mw/base] independently at each t.
# VARIABLE: the SAME ActivePowerOutVariable/InVariable JuMP object assigned at every
# period. Bounds are unchanged ([0, mw/base]), so this variable is still divisible; the
# per-period PWL cost machinery links `p[t] = Σδ_k(t)` for every t against that one shared
# object, giving a single shared fraction of the block cleared identically at every period
# with no new cost code.
# FIXED: excluded from the ActivePowerOutVariable/InVariable containers entirely (its
# quantity is not "the variable's own value" but "mw times a binary flag"), and instead
# gets its own `BlockBidCommitmentVariable` (z), built with the same
# create-once/reuse-every-period pattern as VARIABLE.
#################################################################################

"""
Split market components into the FIXED-style block bids (which get a
`BlockBidCommitmentVariable`) and the divisible CURVE/VARIABLE bids (which get
`ActivePowerOutVariable`/`ActivePowerInVariable`). Both construct stages need the same
split.
"""
function _partition_by_curve_style(devices)
    fixed = eltype(devices)[]
    divisible = eltype(devices)[]
    for d in devices
        style = _curve_style(PSY.get_operation_cost(d))
        if style == PSY.CurveStyles.FIXED
            push!(fixed, d)
        else
            push!(divisible, d)
        end
    end
    return fixed, divisible
end

"Envelope MW a `VirtualParticipant`'s bid is capped at for the given offer direction."
_bid_max_mw(::IOM.IncrementalOffer, d::PSY.VirtualParticipant) = PSY.get_max_supply(d)
_bid_max_mw(::IOM.DecrementalOffer, d::PSY.VirtualParticipant) = PSY.get_max_demand(d)
_bid_settlement_sign(::IOM.IncrementalOffer) = 1.0
_bid_settlement_sign(::IOM.DecrementalOffer) = -1.0
_bid_direction_meta(::IOM.IncrementalOffer) = "Out"
_bid_direction_meta(::IOM.DecrementalOffer) = "In"

_get_block_bid_variable(container::OptimizationContainer, dir::IOM.OfferDirection) =
    get_variable(
        container,
        BlockBidCommitmentVariable,
        PSY.VirtualParticipant,
        _bid_direction_meta(dir),
    )

function _new_bid_jump_var!(
    container::OptimizationContainer,
    ::Type{T},
    d::PSY.VirtualParticipant,
    t::Int,
) where {T <: VariableType}
    name = PSY.get_name(d)
    binary = get_variable_binary(T, PSY.VirtualParticipant, VirtualBidDispatch)
    var = JuMP.@variable(
        get_jump_model(container),
        base_name = "$(T)_$(PSY.VirtualParticipant)_{$(name), $(t)}",
        binary = binary,
    )
    ub = get_variable_upper_bound(T, d, VirtualBidDispatch)
    ub !== nothing && JuMP.set_upper_bound(var, ub)
    lb = get_variable_lower_bound(T, d, VirtualBidDispatch)
    lb !== nothing && !binary && JuMP.set_lower_bound(var, lb)
    if get_warm_start(get_settings(container))
        init = get_variable_warm_start_value(T, d, VirtualBidDispatch)
        init !== nothing && JuMP.set_start_value(var, init)
    end
    return var
end

function _populate_per_period_bid_variable!(
    container::OptimizationContainer,
    variable,
    ::Type{T},
    d::PSY.VirtualParticipant,
    time_steps,
) where {T <: VariableType}
    name = PSY.get_name(d)
    for t in time_steps
        variable[name, t] = _new_bid_jump_var!(container, T, d, t)
    end
    return
end

function _populate_shared_bid_variable!(
    container::OptimizationContainer,
    variable,
    ::Type{T},
    d::PSY.VirtualParticipant,
    time_steps,
) where {T <: VariableType}
    name = PSY.get_name(d)
    var = _new_bid_jump_var!(container, T, d, first(time_steps))
    for t in time_steps
        variable[name, t] = var
    end
    return
end

_populate_bid_variable!(
    container::OptimizationContainer,
    variable,
    ::Type{T},
    d::PSY.VirtualParticipant,
    time_steps,
    ::Val{PSY.CurveStyles.CURVE},
) where {T <: VariableType} =
    _populate_per_period_bid_variable!(container, variable, T, d, time_steps)

_populate_bid_variable!(
    container::OptimizationContainer,
    variable,
    ::Type{T},
    d::PSY.VirtualParticipant,
    time_steps,
    ::Val{PSY.CurveStyles.VARIABLE},
) where {T <: VariableType} =
    _populate_shared_bid_variable!(container, variable, T, d, time_steps)

"""
Creates the `BlockBidCommitmentVariable` (z) for every FIXED-style device, one per
(device, direction), reused at every period — see the curve-style section header.
"""
function _add_block_bid_commitment_variables!(
    container::OptimizationContainer,
    devices,
)
    isempty(devices) && return
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    for dir in (IOM.IncrementalOffer(), IOM.DecrementalOffer())
        meta = _bid_direction_meta(dir)
        variable = add_variable_container!(
            container, BlockBidCommitmentVariable, PSY.VirtualParticipant, meta, names,
            time_steps,
        )
        for d in devices
            _populate_shared_bid_variable!(
                container, variable, BlockBidCommitmentVariable, d, time_steps,
            )
        end
    end
    return
end

"""
Adds FIXED-style block-bid settlement terms: `z` scaled by `mw/base` (natural-units
`max_supply`/`max_demand` converted at the formulation surface, per the units rule) at
every period, `+z` on the supply (out) side and `-z` on the demand (in) side.
"""
function _add_block_bid_settlement_terms!(
    container::OptimizationContainer,
    devices,
    settlement_expr,
    time_steps,
)
    isempty(devices) && return
    for dir in (IOM.IncrementalOffer(), IOM.DecrementalOffer())
        z = _get_block_bid_variable(container, dir)
        sign = _bid_settlement_sign(dir)
        for d in devices
            name = PSY.get_name(d)
            mw = _bid_max_mw(dir, d) / PSY.get_base_power(d, PSY.NU)
            iszero(mw) && continue
            _add_settlement_terms!(settlement_expr, z, name, sign * mw, time_steps)
        end
    end
    return
end

"""
Total \$ value of clearing a block-bid device's full offer curve for one hour: the sum of
`slope_k * segment_width_k` over the whole curve. A block bid's curve is assumed to span
exactly `[0, mw]` (the same assumption CURVE-style devices make about their top
breakpoint), so this is the \$/h cost (or, for a decremental curve, value) of clearing the
entire block — the quantity FIXED's `z` and VARIABLE's shared variable both scale.
"""
function _block_bid_curve_value(
    dir::IOM.OfferDirection,
    container::OptimizationContainer,
    d::PSY.VirtualParticipant,
    t::Int,
)::Float64
    breakpoints, slopes = IOM._get_pwl_data(dir, container, d, t)
    return _pwl_curve_total(breakpoints, slopes)
end

# Function barrier: `_get_pwl_data`'s breakpoint/slope vectors are not inferrable at its
# call site, so the accumulation is compiled here against their concrete types.
function _pwl_curve_total(breakpoints, slopes)::Float64
    total = 0.0
    for i in eachindex(slopes)
        total += slopes[i] * (breakpoints[i + 1] - breakpoints[i])
    end
    return total
end

# Function barrier: `z` is read from an abstractly-typed variable container, so the term is
# built and routed here against the concrete `JuMP.VariableRef`.
function _add_block_bid_cost_term!(
    container::OptimizationContainer,
    z,
    name::String,
    coefficient::Float64,
    t::Int,
    is_variant::Bool,
)
    cost_expr = coefficient * z
    add_cost_to_expression!(
        container,
        ProductionCostExpression,
        cost_expr,
        PSY.VirtualParticipant,
        name,
        t,
    )
    if is_variant
        IOM.add_to_objective_variant_expression!(container, cost_expr)
    else
        IOM.add_to_objective_invariant_expression!(container, cost_expr)
    end
    return
end

"""
FIXED-style objective terms: the block's per-period \$ value (`_block_bid_curve_value`) is
multiplied by the shared commitment variable `z` and `dt`, never routed through
per-period PWL delta variables — `z` is the only decision, so IOM's block-offer PWL
primitives (`offer_curve_types.jl` `_block_offer_var`/`_block_offer_constraint`, meant for
per-segment divisible dispatch) don't fit this single-shared-variable shape; the terms are
built directly with `add_to_objective_*`/`add_cost_to_expression!` instead. VOM cost is
not modeled for FIXED bids (there is no per-period dispatch variable to carry it — only
VARIABLE/CURVE devices, which keep the standard `add_variable_cost!` path, get VOM), and
[`_validate_block_bid_vom!`](@ref) rejects a nonzero one rather than dropping it silently.
"""
function _add_block_bid_objective_terms!(
    container::OptimizationContainer,
    devices,
)
    isempty(devices) && return
    time_steps = get_time_steps(container)
    dt = Dates.value(get_resolution(container)) / MILLISECONDS_IN_HOUR
    for dir in (IOM.IncrementalOffer(), IOM.DecrementalOffer())
        z = _get_block_bid_variable(container, dir)
        sign = IOM._objective_sign(dir)
        for d in devices
            cost_curve = get_offer_curves(dir, d)
            IOM.is_nontrivial_offer(cost_curve) || continue
            name = PSY.get_name(d)
            is_variant = IOM.is_time_variant(cost_curve)
            static_value = 0.0
            if !is_variant
                static_value = _block_bid_curve_value(dir, container, d, first(time_steps))
            end
            for t in time_steps
                block_value = static_value
                if is_variant
                    block_value = _block_bid_curve_value(dir, container, d, t)
                end
                iszero(block_value) && continue
                _add_block_bid_cost_term!(
                    container,
                    z[name, t],
                    name,
                    sign * block_value * dt,
                    t,
                    is_variant,
                )
            end
        end
    end
    return
end

"""
A divisible virtual settles at a point OR at trading hubs (PSY enforces mutual exclusion);
a virtual with neither has no nodal footprint and writes nowhere. Under a nodal network
model the location must carry a `NodalRedistribution` component model, or the write fails
loudly on the missing `AggregateClearedInjection` container: the template asked to clear
a located virtual without modeling its location. Under `CopperPlateNetworkModel` location
is moot and the write is a declared no-op (see the method below). Location writes are
additive to the settlement-row writes: `AggregateClearedInjection` never feeds
`SettlementBalance`, so nothing is counted twice. Each hub receives the participant's full
award: the current bid plumbing carries one award per participant, not one per hub, so a
participant settling at several hubs is rejected until a per-hub split exists rather than
silently over-injecting.
"""
function _add_virtual_location_writes!(
    container::OptimizationContainer,
    d::PSY.VirtualParticipant,
    p_out::JuMP.VariableRef,
    p_in::JuMP.VariableRef,
    t::Int,
    ::NetworkModel{<:AbstractNetworkModel},
)
    point = PSY.get_settlement_point(d)
    if point !== nothing
        add_cleared_position!(container, point, p_out, 1.0, t)
        add_cleared_position!(container, point, p_in, -1.0, t)
        return
    end
    hubs = PSY.get_trading_hubs(d)
    if length(hubs) > 1
        error(
            "VirtualParticipant $(PSY.get_name(d)) settles at $(length(hubs)) trading hubs, " *
            "but its award is a single quantity with no per-hub split; nodal distribution " *
            "supports one trading hub per participant.",
        )
    end
    for hub in hubs
        add_cleared_position!(container, hub, p_out, 1.0, t)
        add_cleared_position!(container, hub, p_in, -1.0, t)
    end
    return
end

function _add_virtual_location_writes!(
    ::OptimizationContainer,
    ::PSY.VirtualParticipant,
    ::JuMP.VariableRef,
    ::JuMP.VariableRef,
    ::Int,
    ::NetworkModel{CopperPlateNetworkModel},
)
    return
end

"""
Argument stage for `VirtualBidDispatch`: creates `ActivePowerOutVariable`/
`ActivePowerInVariable` for CURVE/VARIABLE devices and `BlockBidCommitmentVariable` for
FIXED devices (dispatched on `PSY.get_curve_style`), populates MBC PWL parameters, and
adds every device's bid to the single system-wide `SettlementBalance` row (+out, -in) and,
for divisible devices, to their settlement location's `AggregateClearedInjection`
(`_add_virtual_location_writes!`). Never touches a physical `ActivePowerBalance` row
directly: the location model distributes the position.
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.VirtualParticipant, VirtualBidDispatch},
    ::IOM.MarketModel,
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(model, sys)
    add_cost_expressions!(container, devices, model)
    fixed_devices, divisible_devices = _partition_by_curve_style(devices)

    time_steps = get_time_steps(container)
    settlement_expr = get_expression(container, IOM.SettlementBalance, PSY.System)

    if !isempty(divisible_devices)
        names = PSY.get_name.(divisible_devices)
        p_out = add_variable_container!(
            container, ActivePowerOutVariable, PSY.VirtualParticipant, names, time_steps,
        )
        p_in = add_variable_container!(
            container, ActivePowerInVariable, PSY.VirtualParticipant, names, time_steps,
        )
        for d in divisible_devices
            name = PSY.get_name(d)
            style = _curve_style(PSY.get_operation_cost(d))
            _populate_bid_variable!(
                container,
                p_out,
                ActivePowerOutVariable,
                d,
                time_steps,
                Val(style),
            )
            _populate_bid_variable!(
                container,
                p_in,
                ActivePowerInVariable,
                d,
                time_steps,
                Val(style),
            )
            _add_settlement_terms!(settlement_expr, p_out, name, 1.0, time_steps)
            _add_settlement_terms!(settlement_expr, p_in, name, -1.0, time_steps)
            for t in time_steps
                _add_virtual_location_writes!(
                    container,
                    d,
                    p_out[name, t],
                    p_in[name, t],
                    t,
                    network_model,
                )
            end
        end
    end

    if !isempty(fixed_devices)
        _add_block_bid_commitment_variables!(container, fixed_devices)
        _add_block_bid_settlement_terms!(
            container,
            fixed_devices,
            settlement_expr,
            time_steps,
        )
    end

    process_virtual_bid_parameters!(container, devices, model)
    return
end

"""
Model stage for `VirtualBidDispatch`: adds the incremental (out) / decremental (in)
objective cost terms. CURVE/VARIABLE devices keep the standard PWL delta machinery
(`add_variable_cost!`); FIXED devices get bespoke single-variable terms
(`_add_block_bid_objective_terms!`). No range or budget constraints — bounds are set
directly on the variables at creation.
"""
function construct_market_component!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.VirtualParticipant, VirtualBidDispatch},
    ::IOM.MarketModel,
    ::NetworkModel{<:AbstractNetworkModel},
)
    devices = get_available_components(model, sys)
    fixed_devices, divisible_devices = _partition_by_curve_style(devices)

    if !isempty(divisible_devices)
        wrapped = IS.FlattenIteratorWrapper(PSY.VirtualParticipant, [divisible_devices])
        add_variable_cost!(container, ActivePowerOutVariable, wrapped, VirtualBidDispatch)
        add_variable_cost!(container, ActivePowerInVariable, wrapped, VirtualBidDispatch)
    end
    _add_block_bid_objective_terms!(container, fixed_devices)
    return
end
