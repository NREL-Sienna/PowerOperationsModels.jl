#! format: off
########################### ElectricLoad ####################################

get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.ElectricLoad}, ::Type{<:AbstractLoadFormulation}) = -1.0

########################### ActivePowerVariable, ElectricLoad ####################################

get_variable_binary(::Type{ActivePowerVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{<:AbstractLoadFormulation}) = false
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.ElectricLoad, ::Type{<:AbstractLoadFormulation}) = 0.0
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.ElectricLoad, ::Type{<:AbstractLoadFormulation}) = PSY.get_max_active_power(d, PSY.SU)
# Dispatch-basis split (see `LoadDispatchBasis`): a priced load keeps its limits, an unoffered
# load is pinned at zero.
get_variable_upper_bound(::Type{ActivePowerVariable}, d::PSY.ControllableLoad, ::Type{<:Union{PowerLoadDispatch, PowerLoadInterruption}}) =
    _active_power_upper_bound(get_dispatch_basis(PSY.get_operation_cost(d)), d)

########################### ReactivePowerVariable, ElectricLoad ####################################

get_variable_binary(::Type{ReactivePowerVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{<:AbstractLoadFormulation}) = false

get_variable_lower_bound(::Type{ReactivePowerVariable}, d::PSY.ElectricLoad, ::Type{<:AbstractLoadFormulation}) = 0.0
get_variable_upper_bound(::Type{ReactivePowerVariable}, d::PSY.ElectricLoad, ::Type{<:AbstractLoadFormulation}) = PSY.get_max_reactive_power(d, PSY.SU)

########################### ReactivePowerVariable, ElectricLoad ####################################

get_variable_binary(::Type{OnVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{<:AbstractLoadFormulation}) = true

get_multiplier_value(::Type{<:TimeSeriesParameter}, d::PSY.ElectricLoad, ::Type{StaticPowerLoad}) = -1*PSY.get_max_active_power(d, PSY.SU)
get_multiplier_value(::Type{ReactivePowerTimeSeriesParameter}, d::PSY.ElectricLoad, ::Type{StaticPowerLoad}) = -1*PSY.get_max_reactive_power(d, PSY.SU)
get_multiplier_value(::Type{<:TimeSeriesParameter}, d::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation}) = PSY.get_max_active_power(d, PSY.SU)

########################### ShiftablePowerLoad #####################################

get_variable_binary(::Type{ShiftUpActivePowerVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{PowerLoadShift}) = false
get_variable_lower_bound(::Type{ShiftUpActivePowerVariable}, d::PSY.ElectricLoad, ::Type{PowerLoadShift}) = 0.0
get_variable_upper_bound(::Type{ShiftUpActivePowerVariable}, d::PSY.ElectricLoad, ::Type{PowerLoadShift}) = nothing # Unbounded above by default, but can be limited by time series parameters

get_variable_binary(::Type{ShiftDownActivePowerVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{PowerLoadShift}) = false
get_variable_lower_bound(::Type{ShiftDownActivePowerVariable}, d::PSY.ElectricLoad, ::Type{PowerLoadShift}) = 0.0
get_variable_upper_bound(::Type{ShiftDownActivePowerVariable}, d::PSY.ElectricLoad, ::Type{PowerLoadShift}) = nothing # Unbounded above by default, but can be limited by time series parameters

variable_cost(cost::PSY.OperationalCost, ::Type{ShiftUpActivePowerVariable}, ::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation})=PSY.get_variable_operation_cost(cost)
variable_cost(cost::PSY.OperationalCost, ::Type{ShiftDownActivePowerVariable}, ::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation})=PSY.get_variable_operation_cost(cost)

########################### Reserve provision, ElectricLoad ################################
# The inverse of a generator: up reserve is shed (P - r_up >= 0), down reserve is extra
# consumption (P + r_down <= forecast). OfflineReserve (non-spin) is upward-only, so a
# load provides it as committed shed like any up reserve.
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{<:UP_RESERVE}) = ActivePowerRangeExpressionLB
get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.ElectricLoad}, ::Type{<:PSY.Reserve{PSY.ReserveDown}}) = ActivePowerRangeExpressionUB

######################################################

# To avoid ambiguity with default_interface_methods.jl:
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.ElectricLoad, ::Type{StaticPowerLoad}) = 1.0
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, ::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation}) = 1.0


########################Objective Function##################################################
proportional_cost(cost::Nothing, ::Type{OnVariable}, ::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation})=1.0
proportional_cost(cost::PSY.OperationalCost, ::Type{OnVariable}, ::PSY.ElectricLoad, ::Type{<:AbstractControllablePowerLoadFormulation})=PSY.get_fixed(cost)

objective_function_multiplier(::Type{<:VariableType}, ::Type{<:AbstractControllablePowerLoadFormulation})=OBJECTIVE_FUNCTION_NEGATIVE
objective_function_multiplier(::Type{ShiftUpActivePowerVariable}, ::Type{PowerLoadShift})=OBJECTIVE_FUNCTION_NEGATIVE
objective_function_multiplier(::Type{ShiftDownActivePowerVariable}, ::Type{PowerLoadShift})=OBJECTIVE_FUNCTION_POSITIVE

#! format: on

# proportional cost: connects to common implementation in IOM
# see also the thermal + hydro forwarder in common_models/objective_function.jl
add_proportional_cost!(
    container::OptimizationContainer,
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{T},
    ::Type{PowerLoadInterruption},
) where {U <: OnVariable, T <: PSY.ControllableLoad} =
    add_proportional_cost_maybe_time_variant!(
        container,
        U,
        devices,
        PowerLoadInterruption,
    )

function get_default_time_series_names(
    ::Type{<:PSY.ElectricLoad},
    ::Type{<:AbstractLoadFormulation},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        ActivePowerTimeSeriesParameter => "max_active_power",
        ReactivePowerTimeSeriesParameter => "max_active_power",
    )
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.ElectricLoad, V <: AbstractLoadFormulation}
    return Dict{String, Any}()
end

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, <:AbstractLoadFormulation},
) where {T <: PSY.ElectricLoad} = DeviceModel(T, StaticPowerLoad)

function get_default_time_series_names(
    ::Type{<:PSY.MotorLoad},
    ::Type{<:AbstractLoadFormulation},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_time_series_names(
    ::Type{<:PSY.ShiftablePowerLoad},
    ::Type{PowerLoadShift},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        ActivePowerTimeSeriesParameter => "max_active_power",
        ReactivePowerTimeSeriesParameter => "max_active_power",
        ShiftUpActivePowerTimeSeriesParameter => "shift_up_max_active_power",
        ShiftDownActivePowerTimeSeriesParameter => "shift_down_max_active_power",
    )
end

####################### Expressions #########################

function add_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: RealizedShiftedLoad,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: PowerLoadShift,
} where {D <: PSY.ShiftablePowerLoad}
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    expression = add_expression_container!(container, T, D, names, time_steps)
    shift_up = get_variable(container, ShiftUpActivePowerVariable, D)
    shift_down = get_variable(container, ShiftDownActivePowerVariable, D)
    param_container = get_parameter(container, ActivePowerTimeSeriesParameter, D)
    multiplier = get_multiplier_array(param_container)
    for t in time_steps, d in devices
        name = PSY.get_name(d)
        expression[name, t] =
            get_parameter_column_refs(param_container, name)[t] * multiplier[name, t] +
            shift_up[name, t] - shift_down[name, t]
    end
    return
end

"""
Electric Load implementation to add the realized shifted load to `ActivePowerBalance`
expressions for any network model. Targets come from
[`_balance_expression_targets`](@ref) (nodal bus, system, area, or PTDF/AreaPTDF
system+bus pair), matching how every other injection enters the balance; the multiplier
`-1.0` matches `get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.ElectricLoad},
::Type{<:AbstractLoadFormulation})`, the sign convention shared by every load formulation.
"""
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: ActivePowerBalance,
    U <: RealizedShiftedLoad,
    V <: PSY.ShiftablePowerLoad,
    W <: PowerLoadShift,
    X <: AbstractNetworkModel,
}
    realized_load = get_expression(container, U, V)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        for t in time_steps
            _apply_term_to_targets!(targets, realized_load[name, t], -1.0, t)
        end
    end
    return
end

####################################### Reactive Power Constraints #########################
# Power factor sin(atan(q/p)) in closed form via the Pythagorean identity.
function _controllable_load_power_factor(d::PSY.ElectricLoad)
    q_max = PSY.get_max_reactive_power(d, PSY.SU)
    p_max = PSY.get_max_active_power(d, PSY.SU)
    denom = sqrt(q_max^2 + p_max^2)
    if iszero(denom)
        return 0.0
    end
    return q_max / denom
end

"""
Reactive Power Constraints on Controllable Loads Assume Constant power_factor
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ReactivePowerVariableLimitsConstraint},
    U::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    V <: PSY.ElectricLoad,
    W <: AbstractControllablePowerLoadFormulation,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    constraint = add_constraints_container!(container, T,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    jump_model = get_jump_model(container)
    reactive = get_variable(container, U, V)
    real = get_variable(container, ActivePowerVariable, V)
    for d in devices
        name = PSY.get_name(d)
        pf = _controllable_load_power_factor(d)
        for t in time_steps
            constraint[name, t] =
                JuMP.@constraint(jump_model, reactive[name, t] == real[name, t] * pf)
        end
    end
    return
end

"""
Reactive power for `PowerLoadShift` referenced against the `RealizedShiftedLoad`
expression: this formulation never creates an `ActivePowerVariable`, so the generic
`AbstractControllablePowerLoadFormulation` method above (which reads `ActivePowerVariable`)
does not apply.
"""
function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ReactivePowerVariableLimitsConstraint},
    U::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.ShiftablePowerLoad,
    W <: PowerLoadShift,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    constraint = add_constraints_container!(container, T,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    jump_model = get_jump_model(container)
    reactive = get_variable(container, U, V)
    realized_load = get_expression(container, RealizedShiftedLoad, V)
    for d in devices
        name = PSY.get_name(d)
        pf = _controllable_load_power_factor(d)
        for t in time_steps
            constraint[name, t] = JuMP.@constraint(
                jump_model,
                reactive[name, t] == realized_load[name, t] * pf
            )
        end
    end
    return
end

# Upper bound is the load's forecast; with reserves, `ActivePowerRangeExpressionUB`
# (= P + Σ r_down) rides the same bound, capping down awards by the forecast headroom.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActivePowerVariableLimitsConstraint},
    U::Type{<:Union{VariableType, ActivePowerRangeExpressionUB}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ControllableLoad, W <: PowerLoadDispatch, X <: AbstractNetworkModel}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

# `ActivePowerRangeExpressionLB` (= P - Σ r_up) >= 0: an up award cannot exceed the
# load's consumption. Reached only when the load carries a reserve service.
function add_constraints!(
    container::OptimizationContainer,
    T::Type{ActivePowerVariableLimitsConstraint},
    U::Type{ActivePowerRangeExpressionLB},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ControllableLoad, W <: PowerLoadDispatch, X <: AbstractNetworkModel}
    add_range_constraints!(container, T, U, devices, model, X)
    return
end

# Only `min` is consumed (shed floor); the upper bound rides the forecast parameter.
get_min_max_limits(
    d::PSY.ControllableLoad,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{PowerLoadDispatch},
) = (min = 0.0, max = PSY.get_max_active_power(d, PSY.SU))

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ActivePowerVariableLimitsConstraint},
    U::Type{<:VariableType},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ControllableLoad, W <: PowerLoadInterruption, X <: AbstractNetworkModel}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ActivePowerVariableLimitsConstraint},
    U::Type{OnVariable},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ControllableLoad, W <: PowerLoadInterruption, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    constraint = add_constraints_container!(container, T,
        V,
        PSY.get_name.(devices),
        time_steps;
        meta = "binary",
    )
    on_variable = get_variable(container, U, V)
    power = get_variable(container, ActivePowerVariable, V)
    jump_model = get_jump_model(container)
    for t in time_steps, d in devices
        name = PSY.get_name(d)
        pmax = PSY.get_max_active_power(d, PSY.SU)
        constraint[name, t] =
            JuMP.@constraint(jump_model, power[name, t] <= on_variable[name, t] * pmax)
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ShiftedActivePowerBalanceConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ShiftablePowerLoad, W <: PowerLoadShift, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    time_steps_end = time_steps[end]
    # Keep this container 2D (name, terminal-time marker) to match standard indexing patterns.
    constraint = add_constraints_container!(
        container,
        T,
        V,
        PSY.get_name.(devices),
        [time_steps_end],
    )
    up_variable = get_variable(container, ShiftUpActivePowerVariable, V)
    down_variable = get_variable(container, ShiftDownActivePowerVariable, V)
    jump_model = get_jump_model(container)
    for d in devices
        name = PSY.get_name(d)
        constraint[name, time_steps_end] =
            JuMP.@constraint(
                jump_model,
                sum(up_variable[name, t] - down_variable[name, t] for t in time_steps) ==
                0.0
            )
    end
    additional_balance_interval = get_attribute(model, "additional_balance_interval")
    if !isnothing(additional_balance_interval)
        if !(additional_balance_interval isa Dates.Period)
            throw(
                IS.InvalidValue(
                    "The additional_balance_interval attribute must be a Dates.Period, got $(typeof(additional_balance_interval)).",
                ),
            )
        end
        interval_ms = Dates.Millisecond(additional_balance_interval).value
        if interval_ms <= 0
            throw(
                IS.InvalidValue(
                    "The additional_balance_interval attribute must be greater than zero.",
                ),
            )
        end

        resolution = get_resolution(container)
        resolution_ms = Dates.Millisecond(resolution).value

        if interval_ms % resolution_ms != 0
            throw(
                IS.InvalidValue(
                    "The additional_balance_interval attribute must be an integer multiple of model resolution (interval_ms = $(interval_ms), resolution_ms = $(resolution_ms)).",
                ),
            )
        end

        interval_length = interval_ms ÷ resolution_ms
        if interval_length > length(time_steps)
            throw(
                IS.InvalidValue(
                    "The additional_balance_interval attribute must be less than or equal to the optimization horizon.",
                ),
            )
        end

        interval_ranges = [
            start_idx:min(start_idx + interval_length - 1, length(time_steps)) for
            start_idx in 1:interval_length:length(time_steps)
        ]
        interval_end_steps =
            [time_steps[last(interval_range)] for interval_range in interval_ranges]
        constraint_aux = add_constraints_container!(
            container,
            T,
            V,
            PSY.get_name.(devices),
            interval_end_steps;
            meta = "additional",
        )
        for d in devices
            name = PSY.get_name(d)
            for interval_range in interval_ranges
                end_time_step = time_steps[last(interval_range)]
                constraint_aux[name, end_time_step] = JuMP.@constraint(
                    container.JuMPmodel,
                    sum(
                        up_variable[name, t] - down_variable[name, t] for
                        t in time_steps[interval_range]
                    ) == 0.0
                )
            end
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{RealizedShiftedLoadMinimumBoundConstraint},
    U::Type{<:ExpressionType},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ShiftablePowerLoad, W <: PowerLoadShift, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    constraint = add_constraints_container!(
        container,
        T,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    realized_load = get_expression(container, U, V)
    jump_model = get_jump_model(container)
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        constraint[name, t] = JuMP.@constraint(jump_model, realized_load[name, t] >= 0.0)
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{NonAnticipativityConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ShiftablePowerLoad, W <: PowerLoadShift, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    constraint = add_constraints_container!(
        container,
        T,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    up_variable = get_variable(container, ShiftUpActivePowerVariable, V)
    down_variable = get_variable(container, ShiftDownActivePowerVariable, V)
    jump_model = get_jump_model(container)
    for d in devices
        name = PSY.get_name(d)
        for t in time_steps
            constraint[name, t] = JuMP.@constraint(
                jump_model,
                sum(down_variable[name, τ] - up_variable[name, τ] for τ in 1:t) >= 0.0
            )
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ShiftUpActivePowerVariableLimitsConstraint},
    U::Type{<:VariableType},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ShiftablePowerLoad, W <: PowerLoadShift, X <: AbstractNetworkModel}
    add_parameterized_upper_bound_range_constraints(
        container,
        ShiftUpActivePowerVariableLimitsConstraint,
        U,
        ShiftUpActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ShiftDownActivePowerVariableLimitsConstraint},
    U::Type{<:VariableType},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.ShiftablePowerLoad, W <: PowerLoadShift, X <: AbstractNetworkModel}
    add_parameterized_upper_bound_range_constraints(
        container,
        ShiftDownActivePowerVariableLimitsConstraint,
        U,
        ShiftDownActivePowerTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

"""
What determines a controllable load's dispatch. A load with a priced offer is dispatched
economically within its limits. A load with no offer is not in the energy market at all: its
dispatch is pinned at zero, and its limits serve only to set the up-reserve range it can
shed into. This is the ERCOT AS-only interruptible load.
"""
abstract type LoadDispatchBasis end
struct PricedDispatch <: LoadDispatchBasis end
struct UnofferedDispatch <: LoadDispatchBasis end

_active_power_upper_bound(::PricedDispatch, d::PSY.ControllableLoad) =
    PSY.get_max_active_power(d, PSY.SU)
_active_power_upper_bound(::UnofferedDispatch, ::PSY.ControllableLoad) = 0.0

# Is this cost curve zero-valued, i.e. it puts no price on the device's dispatch? A market
# bid with any offer attached (even a supply-side one, which is invalid for a load and is
# rejected downstream) is an offer, not an absence of one.
_is_costless_offer(cost::PSY.LoadCost) =
    PSY.get_variable_operation_cost(cost) == zero(PSY.CostCurve)
_is_costless_offer(cost::PSY.MarketBidCost) = _has_no_offer_curves(cost)
# A real (non-placeholder) time-series key means a genuine offer is attached; whether its
# resolved values are all zero is unknowable before the series is read.
_is_costless_offer(cost::PSY.MarketBidTimeSeriesCost) = _has_no_offer_curves(cost)
_is_costless_offer(::PSY.OperationalCost) = false

_has_no_offer_curves(cost::Union{PSY.MarketBidCost, PSY.MarketBidTimeSeriesCost}) =
    !IOM.is_nontrivial_offer(get_input_offer_curves(cost)) &&
    !IOM.is_nontrivial_offer(get_output_offer_curves(cost))

# Holy-trait function barrier: called once per device at build and dispatched immediately
# into a concrete method, so the value-dependent return type is not on any hot path.
function get_dispatch_basis(cost::PSY.OperationalCost)
    if _is_costless_offer(cost)
        return UnofferedDispatch()
    end
    return PricedDispatch()
end

_push_by_basis!(::PricedDispatch, priced, ::Vector, d) = push!(priced, d)
_push_by_basis!(::UnofferedDispatch, ::Vector, unoffered, d) = push!(unoffered, d)

"""
Split controllable loads into priced and unoffered, wrapped for the standard builders.
"""
function _partition_by_dispatch_basis(
    devices::IS.FlattenIteratorWrapper{L},
) where {L <: PSY.ControllableLoad}
    priced = L[]
    unoffered = L[]
    for d in devices
        basis = get_dispatch_basis(PSY.get_operation_cost(d))
        _push_by_basis!(basis, priced, unoffered, d)
    end
    return IS.FlattenIteratorWrapper(L, [priced]), IS.FlattenIteratorWrapper(L, [unoffered])
end

"""
Seeds `ActivePowerRangeExpressionLB`/`UB` with the constant `max_active_power` (system
per-unit) rather than the device's `ActivePowerVariable`, so reserve eligibility rides the
load's rated capacity instead of its energy dispatch: an unoffered load pinned at zero can
still shed up to its limit as up-reserve. Reserve-service construction later adds `∓ r`
terms into these same containers via the standard `PSY.ElectricLoad` reserve machinery
(`add_to_expression.jl`), keyed only by component type, so this seeding and the service's
own additions land in the same expression regardless of call order.
"""
function _seed_reserve_ranges_on_limits!(
    container::OptimizationContainer,
    devices::Union{Vector{L}, IS.FlattenIteratorWrapper{L}},
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
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

_is_reserve_down_service_model(::ServiceModel{<:PSY.Reserve{PSY.ReserveDown}}) = true
_is_reserve_down_service_model(::ServiceModel) = false

"""
An unoffered load's UB range is anchored on the constant `max_active_power` and bounded by
the forecast (`pmax + Σ r_down <= forecast * pmax`), so any down-reserve award is
structurally forced to zero. Reject a template that asks an unoffered load to provide a
ReserveDown service rather than let it surface as a confusing zero award.
"""
function _validate_unoffered_no_reserve_down!(
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    unoffered::IS.FlattenIteratorWrapper{L},
) where {L <: PSY.ControllableLoad}
    isempty(unoffered) && return
    for service_model in get_services(model)
        _is_reserve_down_service_model(service_model) || continue
        error(
            "Unoffered (costless) $(L) devices $(PSY.get_name.(unoffered)) are modeled " *
            "under $(get_formulation(model)) with ReserveDown service model " *
            "$(get_component_type(service_model)): an unoffered load is pinned at zero " *
            "and its down-reserve is structurally zero. Price the load's offer, or remove " *
            "the ReserveDown service model.",
        )
    end
    return
end

"""
With reserves, the dispatch limits move to the range expressions so awards consume shed or
forecast headroom (load direction map above). Priced loads anchor the range on their
`ActivePowerVariable`; unoffered loads, pinned at zero, anchor it on their limits.
"""
function add_reserve_range_expressions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{L},
    model::DeviceModel{L, <:AbstractControllablePowerLoadFormulation},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {L <: PSY.ControllableLoad}
    for T in (ActivePowerRangeExpressionLB, ActivePowerRangeExpressionUB)
        add_expressions!(container, T, devices, model)
    end
    priced, unoffered = _partition_by_dispatch_basis(devices)
    _validate_unoffered_no_reserve_down!(model, unoffered)
    for T in (ActivePowerRangeExpressionLB, ActivePowerRangeExpressionUB)
        add_to_expression!(container, T, ActivePowerVariable, priced, model, network_model)
    end
    _seed_reserve_ranges_on_limits!(container, unoffered, model)
    return
end

############################## FormulationControllable Load Cost ###########################
# An unoffered load's dispatch is pinned at zero, so it carries no energy cost term and
# nothing is left for a costless-load-selling-reserves guard to catch.
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ControllableLoad, U <: PowerLoadDispatch}
    priced, _ = _partition_by_dispatch_basis(devices)
    add_variable_cost!(container, ActivePowerVariable, priced, U)
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ControllableLoad, U <: PowerLoadInterruption}
    priced, _ = _partition_by_dispatch_basis(devices)
    add_variable_cost!(container, ActivePowerVariable, priced, U)
    add_proportional_cost!(container, OnVariable, devices, U)
    return
end

# code repetition: basically copy-paste from thermal_generation.jl, just change types
# and incremental to decremental.
function proportional_cost(
    container::OptimizationContainer,
    cost::PSY.LoadCost,
    S::Type{OnVariable},
    T::PSY.ControllableLoad,
    U::Type{PowerLoadInterruption},
    t::Int,
)
    return onvar_cost(container, cost, S, T, U, t) +
           PSY.get_constant_term(PSY.get_vom_cost(PSY.get_variable_operation_cost(cost))) +
           PSY.get_fixed(cost)
end

function onvar_cost(
    container::OptimizationContainer,
    cost::PSY.LoadCost,
    ::Type{OnVariable},
    d::PSY.ControllableLoad,
    ::Type{PowerLoadInterruption},
    t::Int,
)
    return _onvar_cost(container, PSY.get_variable_operation_cost(cost), d, t)
end

# LoadCost has no FuelCurve-backed `_onvar_cost` path; the OnVariable proportional
# term's rate (vom_constant + fixed + onvar_cost) is always static here.
IOM.is_time_variant_proportional(::PSY.LoadCost) = false

# MarketBidCost (static + time-series) proportional_cost/is_time_variant_proportional are generic —
# see common_models/market_bid_overrides.jl.

########## PowerLoadShift Formulation Costs ###############

function objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    ::Type{<:AbstractNetworkModel},
) where {T <: PSY.ShiftablePowerLoad, U <: PowerLoadShift}
    add_variable_cost!(container, ShiftUpActivePowerVariable, devices, U)
    add_variable_cost!(container, ShiftDownActivePowerVariable, devices, U)
    return
end

### Special Method to skip VOM cost on ShiftUpActivePowerVariable ###
function add_variable_cost!(
    container::OptimizationContainer,
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{T},
    ::Type{V},
) where {T <: PSY.ShiftablePowerLoad, U <: ShiftUpActivePowerVariable, V <: PowerLoadShift}
    for d in devices
        op_cost_data = PSY.get_operation_cost(d)
        add_variable_cost_to_objective!(container, U, d, op_cost_data, V)
    end
    return
end
