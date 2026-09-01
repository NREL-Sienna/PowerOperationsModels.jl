#################################################################################
# Feedforward constraints (ModelConstructStage)
#
# Ties the affected variables to the `VariableValueParameter` allocated during the
# ArgumentConstructStage. The parameter's values are populated between model
# executions by PowerSimulations; here they are only read.
#################################################################################

function add_feedforward_constraints!(
    container::OptimizationContainer,
    model::DeviceModel,
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    for ff in get_feedforwards(model)
        @debug "constraints" ff V _group = IOM.LOG_GROUP_FEEDFORWARDS_CONSTRUCTION
        add_feedforward_constraints!(container, model, devices, ff)
    end
    return
end

function add_feedforward_constraints!(
    ::OptimizationContainer,
    model::ServiceModel,
    ::PSY.Service,
)
    ffs = get_feedforwards(model)
    if !isempty(ffs)
        throw(
            ArgumentError(
                "Service feedforwards are not supported yet; see `attach_feedforward!`.",
            ),
        )
    end
    return
end

# `must_run` has no shared abstract type to hang off: it sits on the two concrete `ThermalGen`
# types and on `HydroPumpTurbine`, whose sibling `HydroTurbine` lacks it. Reading it through a
# trait keeps the must-run skip on dispatch instead of a per-device `hasmethod` probe.
_is_must_run(::PSY.Component)::Bool = false
_is_must_run(d::PSY.ThermalGen)::Bool = PSY.get_must_run(d)
_is_must_run(d::PSY.HydroPumpTurbine)::Bool = PSY.get_must_run(d)

# IOM's `upper_bound_range_with_parameter!` / `lower_bound_range_with_parameter!` read the
# multiplier straight out of the parameter container. The semicontinuous feedforward supplies
# its own -- zeros when the status already sits inside the range expressions, the variable's
# own bounds otherwise -- and has to skip must-run units, so it keeps this loop. The per-entry
# constraint is IOM's `add_range_bound_constraint!`, and the direction is IOM's `BoundDirection`.
# Named apart from IOM's own `_bound_range_with_parameter!`, which this deliberately does not
# call.
#
# `param_multiplier` also accepts a scalar (every device/time shares one value, e.g. the
# semicontinuous path's zero) or a `Dict` keyed by device name (constant across time, e.g. a
# variable's own bound) so neither caller has to materialize a dense device x time matrix
# just to read it back once per entry.
_multiplier_at(m::JuMPFloatArray, name, t) = m[name, t]
_multiplier_at(m::Real, ::Any, ::Any) = m
_multiplier_at(m::AbstractDict, name, ::Any) = m[name]

function _feedforward_bound_range_with_parameter!(
    dir::IOM.BoundDirection,
    jump_model::JuMP.Model,
    constraint_container::JuMPConstraintArray,
    lhs_array,
    param_multiplier::Union{JuMPFloatArray, Real, AbstractDict},
    param_array::Union{JuMPVariableArray, JuMPFloatArray},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    time_steps = axes(constraint_container)[2]
    for device in devices
        _is_must_run(device) && continue
        name = PSY.get_name(device)
        for t in time_steps
            IOM.add_range_bound_constraint!(
                dir,
                jump_model,
                constraint_container,
                name,
                t,
                lhs_array[name, t],
                _multiplier_at(param_multiplier, name, t),
                param_array[name, t],
            )
        end
    end
    return
end

function _add_sc_feedforward_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{P},
    ::VariableKey{U, V},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel{V, W},
) where {
    T <: FeedforwardSemiContinuousConstraint,
    P <: OnStatusParameter,
    U <: Union{ActivePowerVariable, PowerAboveMinimumVariable},
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
}
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    parameter = get_parameter_array(container, P, V)
    jump_model = get_jump_model(container)
    # The commitment status already entered through the range expressions (see
    # `_add_feedforward_arguments!`), so the parameter adds nothing on the right-hand side.
    zero_multiplier = 0.0
    for (dir, expression_type) in (
        (IOM.UpperBound(), ActivePowerRangeExpressionUB),
        (IOM.LowerBound(), ActivePowerRangeExpressionLB),
    )
        constraint = add_constraints_container!(
            container,
            T,
            V,
            names,
            time_steps;
            meta = "$(U)_$(IOM.constraint_meta(dir))",
        )
        _feedforward_bound_range_with_parameter!(
            dir,
            jump_model,
            constraint,
            get_expression(container, expression_type, V),
            zero_multiplier,
            parameter,
            devices,
        )
    end
    return
end

function _add_sc_feedforward_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{P},
    ::VariableKey{U, V},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel{V, W},
) where {
    T <: FeedforwardSemiContinuousConstraint,
    P <: ParameterType,
    U <: VariableType,
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
}
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    variable = get_variable(container, U, V)
    parameter = get_parameter_array(container, P, V)
    upper_bounds = [get_variable_upper_bound(U, d, W) for d in devices]
    lower_bounds = [get_variable_lower_bound(U, d, W) for d in devices]
    if any(isnothing, upper_bounds) || any(isnothing, lower_bounds)
        throw(IS.InvalidValueError("Bounds for variable $U $V not defined correctly"))
    end
    jump_model = get_jump_model(container)
    for (dir, bound_values) in
        ((IOM.UpperBound(), upper_bounds), (IOM.LowerBound(), lower_bounds))
        constraint = add_constraints_container!(
            container,
            T,
            V,
            names,
            time_steps;
            meta = "$(U)_$(IOM.constraint_meta(dir))",
        )
        # The bound is constant across time for a given device, so a `Dict` keyed by name
        # stands in for the multiplier without repeating it into a device x time matrix.
        multiplier = Dict(zip(names, bound_values))
        _feedforward_bound_range_with_parameter!(
            dir,
            jump_model,
            constraint,
            variable,
            multiplier,
            parameter,
            devices,
        )
    end
    return
end

function add_feedforward_constraints!(
    container::OptimizationContainer,
    model::DeviceModel,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::SemiContinuousFeedforward,
) where {T <: PSY.Component}
    parameter_type = get_default_parameter_type(ff, T)
    time_steps = get_time_steps(container)
    devices_names = PSY.get_name.(devices)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        _check_device_time_axes(variable, devices_names, time_steps)
        # A non-zero lower bound left on the variable would fight the semicontinuous
        # constraint and can make the model infeasible when the unit is off. A must-run
        # unit keeps its own lower bound instead: it is never turned off, and
        # `_feedforward_bound_range_with_parameter!` skips it, so clearing the bound here
        # would leave it with no lower bound at all.
        for d in devices
            _is_must_run(d) && continue
            for v in variable[PSY.get_name(d), :]
                if JuMP.has_lower_bound(v) && JuMP.lower_bound(v) > 0.0
                    @debug "lb reset $(PSY.get_name(d))" JuMP.lower_bound(v) v _group =
                        IOM.LOG_GROUP_FEEDFORWARDS_CONSTRUCTION
                    JuMP.set_lower_bound(v, 0.0)
                end
            end
        end
        _add_sc_feedforward_constraints!(
            container,
            FeedforwardSemiContinuousConstraint,
            parameter_type,
            var,
            devices,
            model,
        )
    end
    return
end

# The upper- and lower-bound feedforwards differ only in the constraint type, the slack
# type, the sign the slack enters with, and the sense of the inequality. The first three
# are resolved by dispatch on `IOM.BoundDirection` below; the last is IOM's
# `add_range_bound_constraint!`, the same primitive the semicontinuous path uses.
_feedforward_constraint_type(::IOM.UpperBound) = FeedforwardUpperBoundConstraint
_feedforward_constraint_type(::IOM.LowerBound) = FeedforwardLowerBoundConstraint

_feedforward_slack_type(::IOM.UpperBound) = UpperBoundFeedForwardSlack
_feedforward_slack_type(::IOM.LowerBound) = LowerBoundFeedForwardSlack

# A slack relaxes the bound, so it moves the constrained side toward the parameter.
_slack_adjusted(::IOM.UpperBound, variable, slack) = variable - slack
_slack_adjusted(::IOM.LowerBound, variable, slack) = variable + slack

function _add_bound_feedforward_constraints!(
    container::OptimizationContainer,
    dir::IOM.BoundDirection,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::AbstractAffectFeedforward,
) where {T <: PSY.Component}
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    param = get_parameter_array(container, parameter_type, T)
    multiplier = get_parameter_multiplier_array(container, parameter_type, T)
    jump_model = get_jump_model(container)
    use_slacks = get_slacks(ff)
    devices_names = PSY.get_name.(devices)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set = _check_device_time_axes(variable, devices_names, time_steps)

        var_type = get_entry_type(var)
        constraint = add_constraints_container!(
            container,
            _feedforward_constraint_type(dir),
            T,
            device_name_set,
            time_steps;
            meta = "$(var_type)$(IOM.constraint_meta(dir))",
        )
        # NOTE (deviation from PowerSimulations): PSI allocates the slack when
        # `add_slacks = true` but never references it in this constraint, so the slack
        # has no effect there. POM wires it in.
        if use_slacks
            slack = get_variable(container, _feedforward_slack_type(dir), T, "$(var_type)")
        end
        for t in time_steps, name in device_name_set
            if use_slacks
                lhs = _slack_adjusted(dir, variable[name, t], slack[name, t])
            else
                lhs = variable[name, t]
            end
            IOM.add_range_bound_constraint!(
                dir,
                jump_model,
                constraint,
                name,
                t,
                lhs,
                multiplier[name, t],
                param[name, t],
            )
        end
    end
    return
end

@doc raw"""
Constructs a parameterized upper bound constraint that holds the affected variable to a
quantity read from the system state.

``` variable[name, t] <= param[name, t] * multiplier[name, t] ```

With `add_slacks = true` the bound is relaxed by a non-negative slack penalized at
`BALANCE_SLACK_COST`:

``` variable[name, t] - slack[name, t] <= param[name, t] * multiplier[name, t] ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::UpperBoundFeedforward,
) where {T <: PSY.Component, U <: AbstractDeviceFormulation}
    _add_bound_feedforward_constraints!(container, IOM.UpperBound(), devices, ff)
    return
end

@doc raw"""
Constructs a parameterized lower bound constraint that holds the affected variable to a
quantity read from the system state.

``` variable[name, t] >= param[name, t] * multiplier[name, t] ```

With `add_slacks = true` the bound is relaxed by a non-negative slack penalized at
`BALANCE_SLACK_COST`:

``` variable[name, t] + slack[name, t] >= param[name, t] * multiplier[name, t] ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::LowerBoundFeedforward,
) where {T <: PSY.Component, U <: AbstractDeviceFormulation}
    _add_bound_feedforward_constraints!(container, IOM.LowerBound(), devices, ff)
    return
end

@doc raw"""
Pins a variable in this model to a quantity read from the system state.

``` variable[name, t] == param[name, t] * multiplier[name, t] ```

NOTE (deviation from PowerSimulations): PSI applies this with `JuMP.fix`. That only
works when the parameter container holds `Float64`; under `built_for_recurrent_solves`
— the only mode in which a feedforward is ever used — the container holds JuMP
parameters (`JuMP.VariableRef`), and `JuMP.fix` rejects the resulting `AffExpr`. PSI
never hits this because it exercises `FixValueFeedforward` only on services, never on
a `DeviceModel`. An equality constraint is what PSI's own docstring describes, works
in both storage modes, and tracks the parameter automatically when it is repopulated.
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::FixValueFeedforward,
) where {T <: PSY.Component}
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    source_key = get_optimization_container_key(ff)
    var_type = get_entry_type(source_key)
    param = get_parameter_array(container, parameter_type, T, "$var_type")
    multiplier = get_parameter_multiplier_array(container, parameter_type, T, "$var_type")
    jump_model = get_jump_model(container)
    devices_names = PSY.get_name.(devices)
    for var in get_affected_values(ff)
        # `FixValueFeedforward` accepts a `ParameterType` affected value so the service-side
        # path can use one later, but there is no device-side parameter-target
        # implementation; fail with something readable instead of a `get_variable` MethodError.
        if !(var isa VariableKey)
            error(
                "FixValueFeedforward on a DeviceModel only supports VariableType affected \
                 values; got $(get_entry_type(var)). Parameter targets are implemented \
                 only on the service side, which POM does not support yet.",
            )
        end
        variable = get_variable(container, var)
        device_name_set = _check_device_time_axes(variable, devices_names, time_steps)

        affected_var_type = get_entry_type(var)
        con = add_constraints_container!(
            container,
            FeedforwardFixValueConstraint,
            T,
            device_name_set,
            time_steps;
            meta = "$(affected_var_type)",
        )
        for t in time_steps, name in device_name_set
            con[name, t] = JuMP.@constraint(
                jump_model,
                variable[name, t] == param[name, t] * multiplier[name, t]
            )
        end
    end
    return
end

@doc raw"""
Constructs a constraint that bounds a reservoir's cumulative outgoing water flow, summed
over the full model horizon, to the water usage budget read from the system state.

``` sum(water_out[name, :]) <= sum(param[name, :]) ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::WaterLevelBudgetFeedforward,
) where {T <: PSY.HydroReservoir, U <: AbstractDeviceFormulation}
    names = PSY.get_name.(devices)
    water_out = get_expression(container, TotalHydroFlowRateReservoirOutgoing, T)
    # A single value per device, summed over the whole horizon; `["horizon"]` is the same
    # degenerate second axis `WaterBudgetConstraint` uses for the analogous constraint, since
    # IOM rejects 1D constraint containers (issue #15).
    con = add_constraints_container!(
        container,
        FeedForwardWaterLevelBudgetConstraint,
        T,
        names,
        ["horizon"],
    )
    param = get_parameter_array(container, WaterLevelBudgetParameter, T)
    if built_for_recurrent_solves(container)
        jump_model = get_jump_model(container)
        for name in names
            con[name, "horizon"] = JuMP.@constraint(
                jump_model,
                sum(water_out[name, :]) <= sum(param[name, :])
            )
        end
    end
    return
end

@doc raw"""
Constructs a constraint holding a reservoir variable to a minimum target read from the
system state at `target_period`, relaxed by a `HydroEnergyShortageVariable` slack penalized
in the objective at `penalty_cost`.

``` variable[name, target_period] + slack[name, target_period] >= param[name, target_period] * multiplier[name, target_period] ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::ReservoirTargetFeedforward,
) where {T <: PSY.HydroReservoir, U <: AbstractDeviceFormulation}
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    param = get_parameter_array(container, parameter_type, T)
    multiplier = get_parameter_multiplier_array(container, parameter_type, T)
    target_period = get_target_period(ff)
    penalty_cost = get_penalty_cost(ff)
    jump_model = get_jump_model(container)
    devices_names = PSY.get_name.(devices)
    slack_var = get_variable(container, HydroEnergyShortageVariable, T)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set = _check_device_time_axes(variable, devices_names, time_steps)

        var_type = get_entry_type(var)
        # A single value per device, at `target_period`; `["horizon"]` is the same degenerate
        # second axis `WaterBudgetConstraint` uses, since IOM rejects 1D constraint containers.
        con = add_constraints_container!(
            container,
            FeedforwardEnergyTargetConstraint,
            T,
            device_name_set,
            ["horizon"];
            meta = "$(var_type)target",
        )
        for name in device_name_set
            con[name, "horizon"] = JuMP.@constraint(
                jump_model,
                variable[name, target_period] + slack_var[name, target_period] >=
                param[name, target_period] * multiplier[name, target_period]
            )
            add_to_objective_invariant_expression!(
                container,
                slack_var[name, target_period] * penalty_cost,
            )
        end
    end
    return
end

@doc raw"""
Constructs a constraint bounding the sum of a variable over consecutive blocks of
`number_of_periods` time steps to a per-block limit read from the system state.

``` sum(variable[name, t] for t in block) <= sum(param[name, t] * multiplier[name, t] for t in block) ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::ReservoirLimitFeedforward,
) where {T <: PSY.Component, U <: AbstractDeviceFormulation}
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    param = get_parameter_array(container, parameter_type, T)
    multiplier = get_parameter_multiplier_array(container, parameter_type, T)
    affected_periods = get_number_of_periods(ff)
    jump_model = get_jump_model(container)
    devices_names = PSY.get_name.(devices)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set = _check_device_time_axes(variable, devices_names, time_steps)

        if affected_periods > time_steps[end]
            error(
                "The number of affected periods $affected_periods is larger than the " *
                "periods available $(time_steps[end])",
            )
        end
        no_trenches = time_steps[end] ÷ affected_periods
        var_type = get_entry_type(var)
        con = add_constraints_container!(
            container,
            FeedforwardIntegralLimitConstraint,
            T,
            device_name_set,
            1:no_trenches;
            meta = "$(var_type)integral",
        )
        for name in device_name_set, i in 1:no_trenches
            block = (1 + (i - 1) * affected_periods):(i * affected_periods)
            con[name, i] = JuMP.@constraint(
                jump_model,
                sum(variable[name, t] for t in block) <=
                sum(param[name, t] * multiplier[name, t] for t in block)
            )
        end
    end
    return
end

@doc raw"""
Constructs a constraint bounding a hydro unit's cumulative active power usage, summed over
the full model horizon, to a hydro energy usage limit read from the system state.

``` fraction_of_hour * sum(power[name, :]) <= param[name, end] ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    model::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::HydroUsageLimitFeedforward,
) where {T <: PSY.HydroGen, U <: AbstractHydroFormulation}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = PSY.get_name.(devices)
    power_var = get_variable(container, ActivePowerVariable, T)
    param = get_parameter_array(container, HydroUsageLimitParameter, T)
    jump_model = get_jump_model(container)
    # A single value per device, summed over the whole horizon; `["horizon"]` is the same
    # degenerate second axis `WaterBudgetConstraint` uses, since IOM rejects 1D constraint
    # containers.
    con = add_constraints_container!(
        container,
        FeedForwardHydroUsageLimitConstraint,
        T,
        names,
        ["horizon"],
    )
    if built_for_recurrent_solves(container)
        for name in names
            param_value = param[name, time_steps[end]]
            if has_service_model(model)
                served_reg_dn =
                    get_expression(container, HydroServedReserveDownExpression, T)
                served_reg_up = get_expression(container, HydroServedReserveUpExpression, T)
                con[name, "horizon"] = JuMP.@constraint(
                    jump_model,
                    fraction_of_hour * sum(
                        power_var[name, t] + served_reg_up[name, t] -
                        served_reg_dn[name, t] for t in time_steps
                    ) <= param_value
                )
            else
                con[name, "horizon"] = JuMP.@constraint(
                    jump_model,
                    fraction_of_hour * sum(power_var[name, :]) <= param_value
                )
            end
        end
    end
    return
end
