# Per-device ancillary-service (reserve) OFFER costs.
#
# A contributing device can OFFER a PWL price/quantity curve for providing a reserve service,
# stored via the PSY `set_service_bid!` path and retrieved with `get_services_bid`. This prices the
# device's reserve award `ActivePowerReserveVariable[(service, device, t)]` by its own offer curve
# instead of the flat `DEFAULT_RESERVE_COST`, using the delta/block-offer formulation:
#
#   δ_k >= 0,  δ_k <= P_{k+1} - P_k,  Σ_k δ_k == award,  objective += Σ_k slope_k · δ_k · dt
#
# Block variables are keyed 4D `(service_name, device_name, segment, time)` - the segment axis on
# top of the 3D `(service, device, time)` reserve award. Reuses the device offer PWL machinery
# (`_get_raw_pwl_data`, `get_piecewise_curve_per_system_unit`, `get_pwl_cost_expression_delta`).

_has_reserve_offer(device, service) =
    (c = PSY.get_operation_cost(device);
    c isa PSY.OfferCurveCost && service in PSY.get_ancillary_service_offers(c))

# Price every contributing device that offers into `service` by its offer curve; returns the set of
# device names so priced (the flat-cost pass skips them).
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
        # 4D block var keyed (service, device, segment, time). The segment axis `1:1` is only a
        # key-type carrier: `sparse_container_spec` infers `Tuple{String,String,Int,Int}` from the
        # axis eltypes and returns an empty SparseAxisArray with no axis validation, so segments
        # (which vary per device/time) are filled sparsely below - same pattern IOM uses for its
        # hardcoded 3-tuple device-cost PWL container, one axis wider.
        blk = lazy_container_addition!(container, PiecewiseLinearBlockReserveOffer,
            device_type,
            [service_name], names, 1:1, time_steps; sparse = true)
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
