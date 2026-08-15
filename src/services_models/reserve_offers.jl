# Per-device reserve offer costs.
#
# A contributing device can offer a piecewise-linear price/quantity curve for providing a reserve
# service, stored via the PSY `set_service_bid!` path and read with `get_services_bid`. This prices
# the device's reserve award `ActivePowerReserveVariable[(service, device, t)]` by its own offer
# curve instead of the flat `DEFAULT_RESERVE_COST`, using the delta/block-offer formulation:
#
#   δ_k >= 0,  δ_k <= P_{k+1} - P_k,  Σ_k δ_k == award,  objective += Σ_k slope_k · δ_k · dt
#
# Block variables are keyed `(service_name, device_name, segment, time)` - the segment axis on top
# of the `(service, device, time)` reserve award. Reuses the device offer machinery
# (`_get_raw_pwl_data`, `get_piecewise_curve_per_system_unit`, `get_pwl_cost_expression_delta`).

# Does `device` offer into `service`? Only `MarketBidCost` / `MarketBidTimeSeriesCost` carry
# reserve offers readable via `get_services_bid`. `ImportExportCost` / `ImportExportTimeSeriesCost`
# have an `ancillary_service_offers` field too but are not supported by `get_services_bid`, so they
# must reach the `false` fallback or an offering `Source` would hit a MethodError.
_has_reserve_offer(device, service) =
    _cost_offers_reserve(PSY.get_operation_cost(device), service)
_cost_offers_reserve(cost::Union{PSY.MarketBidCost, PSY.MarketBidTimeSeriesCost}, service) =
    service in PSY.get_ancillary_service_offers(cost)
_cost_offers_reserve(::PSY.OperationalCost, service) = false

# Price every contributing device that offers into `service` by its offer curve; returns the set of
# device names so priced (the flat-cost pass skips them).
# A group has no contributing devices, so it can carry no per-device offers; with
# `GroupReserve <: AbstractReserve` the generic method below would otherwise accept it.
# Offers live on the group's contributing services and are priced by their own models.
function add_reserve_offer_costs!(
    ::OptimizationContainer,
    service::SR,
    ::ServiceModel{SR, T},
) where {SR <: PSY.GroupReserve, T <: AbstractReservesFormulation}
    throw(
        IS.ConflictingInputsError(
            "Per-resource reserve offers live on a group's contributing services, not on \
            the group $(PSY.get_name(service)) itself.",
        ),
    )
end

function add_reserve_offer_costs!(
    container::OptimizationContainer,
    service::SR,
    model::ServiceModel{SR, T},
) where {SR <: PSY.AbstractReserve, T <: AbstractReservesFormulation}
    service_name = PSY.get_name(service)
    award = get_variable(container, ActivePowerReserveVariable, SR)
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    dt = Dates.value(Dates.Second(resolution)) / SECONDS_IN_HOUR
    base_p = get_model_base_power(container)
    initial_time = IOM.get_initial_time(container)
    jump_model = get_jump_model(container)
    offered = Set{String}()

    for (device_type, devices) in get_contributing_devices_map(model, service_name)
        offering = [d for d in devices if _has_reserve_offer(d, service)]
        isempty(offering) && continue
        names = [PSY.get_name(d) for d in offering]
        # Block var keyed `(service, device, segment, time)` via
        # `IOM.sparse_variable_key_type(PiecewiseLinearBlockReserveOffer)`. Segments vary per
        # device and time, so they are filled sparsely below.
        blk = lazy_container_addition!(
            container,
            PiecewiseLinearBlockReserveOffer,
            device_type,
        )
        cons =
            lazy_container_addition!(container, ReserveOfferLinkingConstraint, device_type,
                [service_name], names, time_steps; sparse = true)
        for d in offering
            dev_name = PSY.get_name(d)
            cost = PSY.get_operation_cost(d)
            dev_base = PSY.get_base_power(d)
            bid = PSY.get_services_bid(
                d, cost, service; start_time = initial_time, len = length(time_steps))
            curves = values(bid)
            for t in time_steps
                bp_c, slope_c, unit = IOM._get_raw_pwl_data(
                    IOM.IncrementalOffer(), container, device_type, dev_name, curves[t],
                    t)
                breakpoints, slopes = IOM.get_piecewise_curve_per_system_unit(
                    bp_c, slope_c, unit, base_p, dev_base)
                nseg = length(slopes)
                pwl_vars = Vector{JuMP.VariableRef}(undef, nseg)
                for k in 1:nseg
                    v =
                        blk[(service_name, dev_name, k, t)] = JuMP.@variable(
                            jump_model,
                            base_name = "PiecewiseLinearBlockReserveOffer_$(device_type)_{$(service_name), $(dev_name), $(k), $(t)}",
                            lower_bound = 0.0,
                        )
                    JuMP.@constraint(jump_model, v <= breakpoints[k + 1] - breakpoints[k])
                    pwl_vars[k] = v
                end
                cons[(service_name, dev_name, t)] = JuMP.@constraint(
                    jump_model, sum(pwl_vars) == award[(service_name, dev_name, t)])
                add_to_objective_invariant_expression!(
                    container, get_pwl_cost_expression_delta(pwl_vars, slopes, dt))
            end
            push!(offered, dev_name)
        end
    end
    return offered
end
