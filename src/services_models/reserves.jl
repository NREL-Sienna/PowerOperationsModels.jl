#! format: off
############################### Reserve Variables #########################################

get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.AbstractReserve}, ::Type{<:AbstractReservesFormulation}) = NaN
############################### ActivePowerReserveVariable, AbstractReserve #########################################
# One method covers OnlineReserve (<: Reserve) and OfflineReserve (<: AbstractReserve, no direction).
# ORDC reserves carry `max_output_fraction = 1.0`, so the capped bound is a no-op for them.
get_variable_binary(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.AbstractReserve}, ::Type{<:AbstractReservesFormulation}) = false
function get_variable_upper_bound(::Type{ActivePowerReserveVariable}, r::PSY.AbstractReserve, d::PSY.Device, ::Type{<:AbstractReservesFormulation})
    return PSY.get_max_output_fraction(r) * PSY.get_max_active_power(d, PSY.SU)
end
get_variable_lower_bound(::Type{ActivePowerReserveVariable}, ::PSY.AbstractReserve, ::PSY.Device, ::Type) = 0.0

############################### ServiceRequirementVariable (ORDC / StepwiseCostReserve) ################################
# Only created on the StepwiseCostReserve / GroupStepwiseCostReserve construct paths, so the
# formulation gates these to curve-bearing reserves and groups.
get_variable_binary(::Type{ServiceRequirementVariable}, ::Type{<:PSY.AbstractReserve}, ::Type{<:AbstractReservesFormulation}) = false
get_variable_upper_bound(::Type{ServiceRequirementVariable}, ::PSY.AbstractReserve, d::PSY.Component, ::Type{<:AbstractReservesFormulation}) = PSY.get_max_active_power(d, PSY.SU)
get_variable_lower_bound(::Type{ServiceRequirementVariable}, ::PSY.AbstractReserve, ::PSY.Component, ::Type{<:AbstractReservesFormulation}) = 0.0

# Reserve requirement in system units; the getter is units-aware for every reserve type.
_get_requirement(service) = PSY.get_requirement(service, PSY.SU)

# ── Degenerate-demand skip (formulation-driven) ──────────────────────────────────────
# Each reserve formulation has exactly ONE demand driver. When that driver is degenerate for a
# given service, the service imposes no demand of its own and its demand-side model is SKIPPED
# rather than emitted as a zero/degenerate constraint. The service is still built as supply: it
# keeps its `ActivePowerReserveVariable`, its device-side expression contributions, and its
# per-resource offer costs, so it can serve a `GroupReserve` (the group is then the only demand).
#
# Skipping (rather than emitting `requirement = 0` rows) avoids degenerate `sum(awards) >= 0`
# constraints and, with `max_participation_factor < 1`, a `requirement * factor == 0`
# participation cap that silently forces awards to zero.

"""
Whether `service` has a demand driver under `model`'s formulation. Requirement-based formulations
(`RangeReserve`, `RampReserve`, `NonSpinningReserve`) use `requirement`; `StepwiseCostReserve` uses
the operating reserve demand curve, and ignores `requirement` entirely.
"""
_has_reserve_demand(
    ::ServiceModel{<:PSY.AbstractReserve, <:AbstractReservesFormulation},
    service::PSY.AbstractReserve,
) = !iszero(_get_requirement(service))

_has_reserve_demand(
    ::ServiceModel{<:PSY.AbstractReserve, StepwiseCostReserve},
    service::PSY.AbstractReserve,
) = PSY.has_demand_curve(service)

# Group formulations mirror the service ones: `GroupRangeReserve` is driven by the group's
# scalar requirement, `GroupStepwiseCostReserve` by its demand curve (`requirement` ignored).
_has_reserve_demand(
    ::ServiceModel{<:PSY.GroupReserve, GroupRangeReserve},
    group::PSY.GroupReserve,
) = !iszero(_get_requirement(group))

_has_reserve_demand(
    ::ServiceModel{<:PSY.GroupReserve, GroupStepwiseCostReserve},
    group::PSY.GroupReserve,
) = PSY.has_demand_curve(group)

"Services in `services` that impose a demand of their own under `model`'s formulation."
_demand_services(model::ServiceModel, services::Vector{<:PSY.AbstractReserve}) =
    [s for s in services if _has_reserve_demand(model, s)]

# A member of a GroupReserve is EXPECTED to be supply-only, so its skip is routine (`@debug`).
# A standalone degenerate reserve is more likely an oversight, so it is surfaced (`@warn`).
function _is_group_member(sys::PSY.System, service::PSY.AbstractReserve)
    name = PSY.get_name(service)
    for group in PSY.get_components(PSY.GroupReserve, sys)
        any(m -> PSY.get_name(m) == name, PSY.get_contributing_services(group)) && return true
    end
    return false
end

# Groups do not nest: a skipped group is always standalone, so it always warns.
_is_group_member(::PSY.System, ::PSY.GroupReserve) = false

function _log_skipped_reserve_demand(
    sys::PSY.System,
    service::PSY.AbstractReserve,
    ::ServiceModel{<:PSY.AbstractReserve, F},
) where {F <: AbstractReservesFormulation}
    name = PSY.get_name(service)
    reason = F in (StepwiseCostReserve, GroupStepwiseCostReserve) ?
             "it has no operating reserve demand curve" : "its requirement is zero"
    if _is_group_member(sys, service)
        @debug "Service $(name) of type $(typeof(service)) is a GroupReserve member and $(reason); \
                skipping its own demand-side model. It still contributes supply to its group." _group =
            LOG_GROUP_SERVICE_CONSTUCTORS
    else
        @warn "Service $(name) of type $(typeof(service)) is modeled with $(F) but $(reason), so it \
               imposes no demand; skipping its demand-side model. It can still supply reserve to a \
               GroupReserve. Set a requirement or a demand curve if this service should procure \
               reserve on its own."
    end
    return
end

get_multiplier_value(::Type{RequirementTimeSeriesParameter}, d::PSY.AbstractReserve, ::Type{<:AbstractReservesFormulation}) = _get_requirement(d)

get_parameter_multiplier(::Type{<:VariableValueParameter}, d::Type{<:PSY.AbstractReserve}, ::Type{<:AbstractReservesFormulation}) = 1.0
get_initial_parameter_value(::Type{<:VariableValueParameter}, d::Type{<:PSY.AbstractReserve}, ::Type{<:AbstractReservesFormulation}) = 0.0

objective_function_multiplier(::Type{ServiceRequirementVariable}, ::Type{StepwiseCostReserve}) = -1.0
objective_function_multiplier(::Type{ServiceRequirementVariable}, ::Type{GroupStepwiseCostReserve}) = -1.0
uses_compact_power(::PSY.AbstractReserve, ::StepwiseCostReserve)=false
uses_compact_power(::PSY.AbstractReserve, ::GroupStepwiseCostReserve)=false
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.AbstractReserve, ::Type{<:AbstractReservesFormulation}) = 1.0
get_multiplier_value(::Type{<:AbstractPiecewiseLinearSlopeParameter}, ::PSY.AbstractReserve, ::Type{<:AbstractReservesFormulation}) = 1.0
# Operating reserve demand curves (ORDC) are willingness-to-pay (concave), i.e. a decremental
# offer.
# Routes the reserve PWL cost path through IOM's OfferDirection dispatch; making
# this incremental is a one-line change here. Mirrors `_onvar_offer_direction` /
# `_vom_offer_direction` in market_bid_overrides.jl.
_reserve_offer_direction(::PSY.AbstractReserve) = IOM.DecrementalOffer()
#! format: on

function get_initial_conditions_service_model(
    ::IOM.AbstractOptimizationModel,
    ::ServiceModel{T, D},
) where {T <: PSY.AbstractReserve, D <: AbstractReservesFormulation}
    return ServiceModel(T, D)
end

function get_default_time_series_names(
    ::Type{<:PSY.Reserve},
    ::Type{T},
) where {T <: Union{RangeReserve, RampReserve}}
    return Dict{Type{<:TimeSeriesParameter}, String}(
        RequirementTimeSeriesParameter => "requirement",
    )
end

function get_default_time_series_names(
    ::Type{<:PSY.OfflineReserve},
    ::Type{NonSpinningReserve},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        RequirementTimeSeriesParameter => "requirement",
    )
end

function get_default_time_series_names(
    ::Type{T},
    ::Type{<:AbstractReservesFormulation},
) where {T <: PSY.AbstractReserve}
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{<:PSY.AbstractReserve},
    ::Type{<:AbstractReservesFormulation},
)
    return Dict{String, Any}()
end

"""
Add variables for ServiceRequirementVariable for StepWiseCostReserve
"""
function add_reserve_variables!(
    container::OptimizationContainer,
    ::Type{T},
    services::Vector{D},
    formulation,
) where {
    T <: ServiceRequirementVariable,
    D <: PSY.AbstractReserve,
}
    time_steps = get_time_steps(container)
    service_names = [PSY.get_name(s) for s in services]
    # One dense container per service type, keyed `(service_name, time)`. Dense so the
    # ORDC delta-PWL constraint path can read its axes.
    variable = add_variable_container!(container, T, D, service_names, time_steps)

    jump_model = get_jump_model(container)
    for service in services
        service_name = PSY.get_name(service)
        for t in time_steps
            variable[service_name, t] = JuMP.@variable(
                jump_model,
                base_name = "$(T)_$(D)_{$(service_name), $(t)}",
                lower_bound = 0.0,
            )
        end
    end

    return
end

# Sum the reserve provision of one service across its contributing devices at time `t`,
# reading the service type's sparse container keyed `(service_name, device_name, time)`.
function _sum_service_reserves(
    reserve_variable::SparseAxisArray,
    service_name::String,
    contributing_devices::U,
    t::Int,
    extra::Int,
) where {
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSY.Component}
    acc = IOM.get_hinted_aff_expr(length(contributing_devices) + extra)
    for d in contributing_devices
        JuMP.add_to_expression!(acc, reserve_variable[(service_name, PSY.get_name(d), t)])
    end
    return acc
end

################################## Reserve Requirement Constraint ##########################
function add_constraints!(
    container::OptimizationContainer,
    T::Type{RequirementConstraint},
    service::SR,
    contributing_devices::U,
    model::ServiceModel{SR, V},
) where {
    SR <: PSY.AbstractReserve,
    V <: AbstractReservesFormulation,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    service_name = PSY.get_name(service)
    # Dense container keyed `[service_name, time]`, built per type; fill this service's row.
    constraint = get_constraint(container, T, SR)
    reserve_variable = get_variable(container, ActivePowerReserveVariable, SR)
    use_slacks = get_use_slacks(model)
    use_slacks && (slack_vars = get_variable(container, ReserveRequirementSlack, SR))
    requirement = _get_requirement(service)
    jump_model = get_jump_model(container)
    extra = use_slacks ? 1 : 0

    # A static reserve gets a scalar requirement RHS; a time-varying one scales it by an
    # attached requirement series (resolved by the model-configured name).
    if _has_ts_requirement(model, service)
        if built_for_recurrent_solves(container)
            param_container =
                get_parameter(container, RequirementTimeSeriesParameter, SR)
            param = get_parameter_column_refs(param_container, service_name)
            for t in time_steps
                resource_expression =
                    _sum_service_reserves(reserve_variable, service_name,
                        contributing_devices,
                        t, extra)
                use_slacks &&
                    JuMP.add_to_expression!(
                        resource_expression,
                        slack_vars[service_name, t],
                    )
                constraint[service_name, t] =
                    JuMP.@constraint(
                        jump_model,
                        resource_expression >= param[t] * requirement
                    )
            end
        else
            ts_vector = IOM.get_time_series(
                container,
                service,
                get_time_series_names(model)[RequirementTimeSeriesParameter];
                interval = get_interval(get_settings(container)),
            )
            for t in time_steps
                resource_expression =
                    _sum_service_reserves(reserve_variable, service_name,
                        contributing_devices,
                        t, extra)
                use_slacks &&
                    JuMP.add_to_expression!(
                        resource_expression,
                        slack_vars[service_name, t],
                    )
                constraint[service_name, t] = JuMP.@constraint(
                    jump_model,
                    resource_expression >= ts_vector[t] * requirement
                )
            end
        end
    else
        for t in time_steps
            resource_expression =
                _sum_service_reserves(reserve_variable, service_name, contributing_devices,
                    t,
                    extra)
            use_slacks &&
                JuMP.add_to_expression!(resource_expression, slack_vars[service_name, t])
            constraint[service_name, t] =
                JuMP.@constraint(jump_model, resource_expression >= requirement)
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ParticipationFractionConstraint},
    service::SR,
    contributing_devices::U,
    model::ServiceModel{SR, V},
) where {
    SR <: PSY.AbstractReserve,
    V <: AbstractReservesFormulation,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSY.Device}
    max_participation_factor = PSY.get_max_participation_factor(service)

    if max_participation_factor >= 1.0
        return
    end

    time_steps = get_time_steps(container)
    service_name = PSY.get_name(service)
    # Sparse constraint container keyed `(service_name, device_name, time)`.
    cons = lazy_container_addition!(container, T, SR,
        [service_name],
        [PSY.get_name(d) for d in contributing_devices],
        time_steps;
        sparse = true,
    )
    var_r = get_variable(container, ActivePowerReserveVariable, SR)
    jump_model = get_jump_model(container)
    requirement = _get_requirement(service)
    cap = requirement * max_participation_factor
    # Static reserve: constant participation cap. Time-varying reserve: scale by the requirement
    # series (recurrent -> parameter, else -> the resolved time series).
    if _has_ts_requirement(model, service)
        if built_for_recurrent_solves(container)
            param_container =
                get_parameter(container, RequirementTimeSeriesParameter, SR)
            param = get_parameter_column_refs(param_container, service_name)
            for t in time_steps, d in contributing_devices
                name = PSY.get_name(d)
                cons[(service_name, name, t)] = JuMP.@constraint(
                    jump_model,
                    var_r[(service_name, name, t)] <= cap * param[t]
                )
            end
        else
            ts_vector = IOM.get_time_series(
                container,
                service,
                get_time_series_names(model)[RequirementTimeSeriesParameter];
                interval = get_interval(get_settings(container)),
            )
            for t in time_steps, d in contributing_devices
                name = PSY.get_name(d)
                cons[(service_name, name, t)] = JuMP.@constraint(
                    jump_model,
                    var_r[(service_name, name, t)] <= cap * ts_vector[t]
                )
            end
        end
    else
        for t in time_steps, d in contributing_devices
            name = PSY.get_name(d)
            cons[(service_name, name, t)] = JuMP.@constraint(
                jump_model,
                var_r[(service_name, name, t)] <= cap
            )
        end
    end

    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    service::SR,
    model::ServiceModel{SR, T},
) where {SR <: PSY.AbstractReserve, T <: AbstractReservesFormulation}
    # Devices that submitted a reserve OFFER are priced by their offer curve; the rest keep the
    # flat DEFAULT_RESERVE_COST.
    offered = add_reserve_offer_costs!(container, service, model)
    contributing_names =
        [PSY.get_name(d) for d in get_contributing_devices(model, PSY.get_name(service))]
    add_reserves_proportional_cost!(
        container, ActivePowerReserveVariable, service, T, contributing_names;
        skip_devices = offered)
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{RequirementConstraint},
    service::SR,
    contributing_devices::U,
    ::ServiceModel{SR, StepwiseCostReserve},
) where {
    SR <: PSY.AbstractReserve,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    service_name = PSY.get_name(service)
    # Dense container keyed `[service_name, time]`, built per type; fill this service's row.
    constraint = get_constraint(container, T, SR)
    reserve_variable = get_variable(container, ActivePowerReserveVariable, SR)
    requirement_variable =
        get_variable(container, ServiceRequirementVariable, SR)
    jump_model = get_jump_model(container)
    for t in time_steps
        resource_expression =
            _sum_service_reserves(
                reserve_variable,
                service_name,
                contributing_devices,
                t,
                0,
            )
        constraint[service_name, t] = JuMP.@constraint(
            jump_model,
            resource_expression >= requirement_variable[service_name, t]
        )
    end

    return
end

_get_ramp_limits(::PSY.Component) = nothing
_get_ramp_limits(d::PSY.ThermalGen) = PSY.get_ramp_limits(d, PSY.SU)
_get_ramp_limits(d::PSY.HydroGen) = PSY.get_ramp_limits(d, PSY.SU)

function _get_ramp_constraint_contributing_devices(
    service::PSY.Reserve,
    contributing_devices::Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
) where {D <: PSY.Component}
    time_frame = PSY.get_time_frame(service)
    filtered_device = Vector{D}()
    for d in contributing_devices
        ramp_limits = _get_ramp_limits(d)
        if ramp_limits !== nothing
            p_lims = PSY.get_active_power_limits(d, PSY.SU)
            max_rate = abs(p_lims.min - p_lims.max) / time_frame
            if (ramp_limits.up >= max_rate) & (ramp_limits.down >= max_rate)
                @debug "Generator $(PSY.get_name(d)) has a nonbinding ramp limits. Constraints Skipped"
                continue
            else
                push!(filtered_device, d)
            end
        end
    end
    return filtered_device
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    service::SR,
    contributing_devices::Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    ::ServiceModel{SR, V},
) where {
    SR <: PSY.Reserve{PSY.ReserveUp},
    V <: AbstractReservesFormulation,
    D <: PSY.Component,
}
    ramp_devices = _get_ramp_constraint_contributing_devices(service, contributing_devices)
    service_name = PSY.get_name(service)
    if !isempty(ramp_devices)
        jump_model = get_jump_model(container)
        time_steps = get_time_steps(container)
        time_frame = PSY.get_time_frame(service)
        variable = get_variable(container, ActivePowerReserveVariable, SR)
        device_name_set = [PSY.get_name(d) for d in ramp_devices]
        con_up = lazy_container_addition!(container, T,
            SR,
            [service_name],
            device_name_set,
            time_steps;
            sparse = true,
        )
        for d in ramp_devices, t in time_steps
            name = PSY.get_name(d)
            ramp_limits = PSY.get_ramp_limits(d, PSY.SU)
            con_up[(service_name, name, t)] = JuMP.@constraint(
                jump_model,
                variable[(service_name, name, t)] <= ramp_limits.up * time_frame
            )
        end
    else
        @warn "Data doesn't contain contributing devices with ramp limits for service $service_name, consider adjusting your formulation"
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{RampConstraint},
    service::SR,
    contributing_devices::Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    ::ServiceModel{SR, V},
) where {
    SR <: PSY.Reserve{PSY.ReserveDown},
    V <: AbstractReservesFormulation,
    D <: PSY.Component,
}
    ramp_devices = _get_ramp_constraint_contributing_devices(service, contributing_devices)
    service_name = PSY.get_name(service)
    if !isempty(ramp_devices)
        jump_model = get_jump_model(container)
        time_steps = get_time_steps(container)
        time_frame = PSY.get_time_frame(service)
        variable = get_variable(container, ActivePowerReserveVariable, SR)
        device_name_set = [PSY.get_name(d) for d in ramp_devices]
        con_down = lazy_container_addition!(container, T,
            SR,
            [service_name],
            device_name_set,
            time_steps;
            sparse = true,
        )
        for d in ramp_devices, t in time_steps
            name = PSY.get_name(d)
            ramp_limits = PSY.get_ramp_limits(d, PSY.SU)
            con_down[(service_name, name, t)] = JuMP.@constraint(
                jump_model,
                variable[(service_name, name, t)] <= ramp_limits.down * time_frame
            )
        end
    else
        @warn "Data doesn't contain contributing devices with ramp limits for service $service_name, consider adjusting your formulation"
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ReservePowerConstraint},
    service::SR,
    contributing_devices::U,
    ::ServiceModel{SR, V},
) where {
    SR <: PSY.OfflineReserve,
    V <: AbstractReservesFormulation,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    if resolution > Dates.Minute(1)
        minutes_per_period = Dates.value(Dates.Minute(resolution))
    else
        @warn("Not all formulations support under 1-minute resolutions. Exercise caution.")
        minutes_per_period = Dates.value(Dates.Second(resolution)) / 60
    end
    service_name = PSY.get_name(service)
    cons = lazy_container_addition!(container, T,
        SR,
        [service_name],
        [PSY.get_name(d) for d in contributing_devices],
        time_steps;
        sparse = true,
    )
    var_r = get_variable(container, ActivePowerReserveVariable, SR)
    reserve_response_time = PSY.get_time_frame(service)
    jump_model = get_jump_model(container)
    for d in contributing_devices
        # Function barrier: `contributing_devices` may have an abstract element type, so the
        # callee specializes on the concrete types and dispatches once per device rather than
        # once per timestep.
        varstatus = get_variable(container, OnVariable, typeof(d))
        _add_reserve_power_constraint_device!(
            cons,
            var_r,
            varstatus,
            d,
            service_name,
            reserve_response_time,
            minutes_per_period,
            jump_model,
            time_steps,
        )
    end
    return
end

function _add_reserve_power_constraint_device!(
    cons,
    var_r,
    varstatus,
    d::D,
    service_name::String,
    reserve_response_time,
    minutes_per_period,
    jump_model,
    time_steps,
) where {D <: PSY.Component}
    name = PSY.get_name(d)
    startup_time = PSY.get_time_limits(d).up
    ramp_limits = _get_ramp_limits(d)
    if reserve_response_time > startup_time
        reserve_limit =
            PSY.get_active_power_limits(d, PSY.SU).min +
            (reserve_response_time - startup_time) * minutes_per_period * ramp_limits.up
    else
        reserve_limit = 0.0
    end
    for t in time_steps
        cons[(service_name, name, t)] = JuMP.@constraint(
            jump_model,
            var_r[(service_name, name, t)] <= (1 - varstatus[name, t]) * reserve_limit
        )
    end
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    service::S,
    model::ServiceModel{S, SR},
) where {
    S <: PSY.AbstractReserve,
    SR <: StepwiseCostReserve,
}
    # Demand side: price the endogenous ServiceRequirementVariable by the decremental
    # operating reserve demand curve. `objective_function_multiplier(ServiceRequirementVariable,
    # StepwiseCostReserve)` is -1, so this enters the objective as a benefit.
    add_reserves_variable_cost!(container, ServiceRequirementVariable, service, SR)
    # Supply side: price each contributing device's reserve award by its own reserve offer curve
    # (`set_service_bid!` path). No-op for devices that submitted no offer, and there is
    # deliberately no flat `DEFAULT_RESERVE_COST` fallback, so a service whose demand curve is
    # its only price signal is unchanged.
    add_reserve_offer_costs!(container, service, model)
    return
end

# The group's demand: price its ServiceRequirementVariable by the group demand curve (a
# benefit, multiplier -1). No offer costs on the group itself - offers live on the
# contributing services, priced by their own service models.
function add_to_objective_function!(
    container::OptimizationContainer,
    service::S,
    ::ServiceModel{S, GroupStepwiseCostReserve},
) where {S <: PSY.GroupReserve}
    add_reserves_variable_cost!(
        container,
        ServiceRequirementVariable,
        service,
        GroupStepwiseCostReserve,
    )
    return
end

function add_reserves_variable_cost!(
    container::OptimizationContainer,
    ::Type{U},
    service::T,
    ::Type{V},
) where {
    T <: PSY.AbstractReserve,
    U <: VariableType,
    V <: Union{StepwiseCostReserve, GroupStepwiseCostReserve},
}
    _add_reserves_variable_cost_to_objective!(container, U, service, V)
    return
end

function _add_reserves_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{T},
    component::PSY.AbstractReserve,
    ::Type{U},
) where {T <: VariableType, U <: Union{StepwiseCostReserve, GroupStepwiseCostReserve}}
    component_name = PSY.get_name(component)
    @debug "PWL Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    # If array is full of tuples with zeros return 0.0
    time_steps = get_time_steps(container)
    # FIXME clashes with name of a function...ick.
    variable_cost = PSY.get_variable(component)
    if variable_cost isa Nothing
        error(
            "Operating reserve demand curve $(component_name) does not have cost data.",
        )
    elseif !(variable_cost isa PSY.CostCurve)
        error(
            "Operating reserve demand curve $(component_name) has cost data of type \
            $(typeof(variable_cost)), \
            but a `PSY.CostCurve` is required for the $(U) formulation.",
        )
    end

    # A time-varying curve enters the objective as a variant expression, a static curve as an
    # invariant one. The curve type is the source of truth, read via `is_time_variant`;
    # its per-timestep parameters are populated only for TS-backed ORDCs (see
    # `process_stepwise_cost_reserve_parameters!`, gated on `_ordc_is_ts`).
    is_t_variant = is_time_variant(variable_cost)

    pwl_cost_expressions =
        add_pwl_term_delta!(container, component, variable_cost, T, U)
    for t in time_steps
        add_to_expression!(
            container,
            ProductionCostExpression,
            pwl_cost_expressions[t],
            component,
            t,
        )
        if is_t_variant
            IOM.add_to_objective_variant_expression!(container, pwl_cost_expressions[t])
        else
            add_to_objective_invariant_expression!(container, pwl_cost_expressions[t])
        end
    end
    return
end

"""
Add the decremental piecewise slope/breakpoint cost parameters for the time-varying operating
reserve demand curves in `services` (those whose `variable` curve is time-series-backed). Static
ORDCs and fixed-requirement reserves carry no such parameters and are skipped.
"""
function process_stepwise_cost_reserve_parameters!(
    container::OptimizationContainer,
    model::ServiceModel,
    services::Vector{D},
) where {D <: PSY.AbstractReserve}
    # Only time-series-backed ORDCs need the per-timestep slope/breakpoint parameters.
    ts_services = [s for s in services if _ordc_is_ts(s)]
    isempty(ts_services) && return
    # These share one offer direction, so the slope/breakpoint param containers are built once.
    dir = _reserve_offer_direction(first(ts_services))
    for param in (IOM._breakpoint_param(dir), IOM._slope_param(dir))
        add_parameters!(container, param, ts_services, model)
    end
    return
end

function add_reserves_proportional_cost!(
    container::OptimizationContainer,
    ::Type{U},
    service::T,
    ::Type{V},
    contributing_names::Vector{String};
    skip_devices = Set{String}(),
) where {
    T <: PSY.AbstractReserve,
    U <: ActivePowerReserveVariable,
    V <: AbstractReservesFormulation,
}
    base_p = get_model_base_power(container)
    service_name = PSY.get_name(service)
    reserve_variable = get_variable(container, U, T)
    # Index this service's slice of the `(service, device, time)` container by its contributing
    # device names, so each provision is priced once without scanning the whole container.
    # `skip_devices` are priced by their offer curve in `add_reserve_offer_costs!` instead.
    cost = DEFAULT_RESERVE_COST / base_p
    for name in contributing_names
        name in skip_devices && continue
        for t in get_time_steps(container)
            add_to_objective_invariant_expression!(
                container,
                cost * reserve_variable[(service_name, name, t)],
            )
        end
    end
    return
end
