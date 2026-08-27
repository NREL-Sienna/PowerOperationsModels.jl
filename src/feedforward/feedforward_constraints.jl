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

function _lower_bound_range_with_parameter!(
    jump_model::JuMP.Model,
    constraint_container::JuMPConstraintArray,
    lhs_array,
    param_multiplier::JuMPFloatArray,
    param_array::Union{JuMPVariableArray, JuMPFloatArray},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    time_steps = axes(constraint_container)[2]
    for device in devices
        if hasmethod(PSY.get_must_run, Tuple{V})
            PSY.get_must_run(device) && continue
        end
        name = PSY.get_name(device)
        for t in time_steps
            constraint_container[name, t] = JuMP.@constraint(
                jump_model,
                lhs_array[name, t] >= param_multiplier[name, t] * param_array[name, t]
            )
        end
    end
    return
end

function _upper_bound_range_with_parameter!(
    jump_model::JuMP.Model,
    constraint_container::JuMPConstraintArray,
    lhs_array,
    param_multiplier::JuMPFloatArray,
    param_array::Union{JuMPVariableArray, JuMPFloatArray},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    time_steps = axes(constraint_container)[2]
    for device in devices
        if hasmethod(PSY.get_must_run, Tuple{V})
            PSY.get_must_run(device) && continue
        end
        name = PSY.get_name(device)
        for t in time_steps
            constraint_container[name, t] = JuMP.@constraint(
                jump_model,
                lhs_array[name, t] <= param_multiplier[name, t] * param_array[name, t]
            )
        end
    end
    return
end

# The commitment status enters through the range expressions (see
# `_add_feedforward_arguments!`), so the parameter contributes to the LHS and the
# multiplier arrays here are zero.
function _add_sc_feedforward_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::P,
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
    constraint_lb =
        add_constraints_container!(container, T, V, names, time_steps; meta = "$(U)_lb")
    constraint_ub =
        add_constraints_container!(container, T, V, names, time_steps; meta = "$(U)_ub")
    array_lb = get_expression(container, ActivePowerRangeExpressionLB, V)
    array_ub = get_expression(container, ActivePowerRangeExpressionUB, V)
    parameter = get_parameter_array(container, P, V)
    mult_ub = DenseAxisArray(zeros(length(names), time_steps[end]), names, time_steps)
    mult_lb = DenseAxisArray(zeros(length(names), time_steps[end]), names, time_steps)
    jump_model = get_jump_model(container)
    _upper_bound_range_with_parameter!(
        jump_model,
        constraint_ub,
        array_ub,
        mult_ub,
        parameter,
        devices,
    )
    _lower_bound_range_with_parameter!(
        jump_model,
        constraint_lb,
        array_lb,
        mult_lb,
        parameter,
        devices,
    )
    return
end

function _add_sc_feedforward_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::P,
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
    constraint_lb =
        add_constraints_container!(container, T, V, names, time_steps; meta = "$(U)_lb")
    constraint_ub =
        add_constraints_container!(container, T, V, names, time_steps; meta = "$(U)_ub")
    variable = get_variable(container, U, V)
    parameter = get_parameter_array(container, P, V)
    upper_bounds = [get_variable_upper_bound(U, d, W) for d in devices]
    lower_bounds = [get_variable_lower_bound(U, d, W) for d in devices]
    if any(isnothing.(upper_bounds)) || any(isnothing.(lower_bounds))
        throw(IS.InvalidValueError("Bounds for variable $U $V not defined correctly"))
    end
    mult_ub = DenseAxisArray(repeat(upper_bounds, 1, time_steps[end]), names, time_steps)
    mult_lb = DenseAxisArray(repeat(lower_bounds, 1, time_steps[end]), names, time_steps)
    jump_model = get_jump_model(container)
    _upper_bound_range_with_parameter!(
        jump_model,
        constraint_ub,
        variable,
        mult_ub,
        parameter,
        devices,
    )
    _lower_bound_range_with_parameter!(
        jump_model,
        constraint_lb,
        variable,
        mult_lb,
        parameter,
        devices,
    )
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
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        var_axes = JuMP.axes(variable)
        @assert issetequal(var_axes[1], PSY.get_name.(devices))
        IS.@assert_op var_axes[2] == time_steps
        # A non-zero lower bound left on the variable would fight the semicontinuous
        # constraint and can make the model infeasible when the unit is off.
        for v in variable
            if JuMP.has_lower_bound(v) && JuMP.lower_bound(v) > 0.0
                @debug "lb reset" JuMP.lower_bound(v) v _group =
                    IOM.LOG_GROUP_FEEDFORWARDS_CONSTRUCTION
                JuMP.set_lower_bound(v, 0.0)
            end
        end
        _add_sc_feedforward_constraints!(
            container,
            FeedforwardSemiContinuousConstraint,
            parameter_type(),
            var,
            devices,
            model,
        )
    end
    return
end

function add_feedforward_constraints!(
    container::OptimizationContainer,
    model::DeviceModel{T, U},
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::SemiContinuousFeedforward,
) where {T <: PSY.ThermalGen, U <: AbstractThermalFormulation}
    parameter_type = get_default_parameter_type(ff, T)
    time_steps = get_time_steps(container)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        var_axes = JuMP.axes(variable)
        @assert issetequal(var_axes[1], PSY.get_name.(devices))
        IS.@assert_op var_axes[2] == time_steps
        # A must-run unit keeps its own lower bound: it is never turned off, so the
        # semicontinuous constraints skip it entirely.
        for d in devices
            PSY.get_must_run(d) && continue
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
            parameter_type(),
            var,
            devices,
            model,
        )
    end
    return
end

@doc raw"""
Constructs a parameterized upper bound constraint to implement feedforward from other models.

``` variable[name, t] <= param[name, t] * multiplier[name, t] ```

With `add_slacks = true` the bound is relaxed by a non-negative slack penalized at
`BALANCE_SLACK_COST`:

``` variable[name, t] - slack[name, t] <= param[name, t] * multiplier[name, t] ```
"""
function add_feedforward_constraints!(
    container::OptimizationContainer,
    ::DeviceModel,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ff::UpperBoundFeedforward,
) where {T <: PSY.Component}
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    param_ub = get_parameter_array(container, parameter_type, T)
    multiplier_ub = get_parameter_multiplier_array(container, parameter_type, T)
    jump_model = get_jump_model(container)
    use_slacks = get_slacks(ff)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set, set_time = JuMP.axes(variable)
        @assert issetequal(device_name_set, PSY.get_name.(devices))
        IS.@assert_op set_time == time_steps

        var_type = get_entry_type(var)
        con_ub = add_constraints_container!(
            container,
            FeedforwardUpperBoundConstraint,
            T,
            device_name_set,
            time_steps;
            meta = "$(var_type)ub",
        )
        # NOTE (deviation from PowerSimulations): PSI allocates
        # `UpperBoundFeedForwardSlack` when `add_slacks = true` but never references it
        # in this constraint, so the slack has no effect there. POM wires it in.
        slack_var = if use_slacks
            get_variable(container, UpperBoundFeedForwardSlack, T, "$(var_type)")
        else
            nothing
        end

        for t in time_steps, name in device_name_set
            if use_slacks
                con_ub[name, t] = JuMP.@constraint(
                    jump_model,
                    variable[name, t] - slack_var[name, t] <=
                    param_ub[name, t] * multiplier_ub[name, t]
                )
            else
                con_ub[name, t] = JuMP.@constraint(
                    jump_model,
                    variable[name, t] <= param_ub[name, t] * multiplier_ub[name, t]
                )
            end
        end
    end
    return
end

@doc raw"""
Constructs a parameterized lower bound constraint to implement feedforward from other models.

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
    time_steps = get_time_steps(container)
    parameter_type = get_default_parameter_type(ff, T)
    param_lb = get_parameter_array(container, parameter_type, T)
    multiplier_lb = get_parameter_multiplier_array(container, parameter_type, T)
    jump_model = get_jump_model(container)
    use_slacks = get_slacks(ff)
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set, set_time = JuMP.axes(variable)
        @assert issetequal(device_name_set, PSY.get_name.(devices))
        IS.@assert_op set_time == time_steps

        var_type = get_entry_type(var)
        con_lb = add_constraints_container!(
            container,
            FeedforwardLowerBoundConstraint,
            T,
            device_name_set,
            time_steps;
            meta = "$(var_type)lb",
        )
        slack_var = if use_slacks
            get_variable(container, LowerBoundFeedForwardSlack, T, "$(var_type)")
        else
            nothing
        end

        for t in time_steps, name in device_name_set
            if use_slacks
                con_lb[name, t] = JuMP.@constraint(
                    jump_model,
                    variable[name, t] + slack_var[name, t] >=
                    param_lb[name, t] * multiplier_lb[name, t]
                )
            else
                con_lb[name, t] = JuMP.@constraint(
                    jump_model,
                    variable[name, t] >= param_lb[name, t] * multiplier_lb[name, t]
                )
            end
        end
    end
    return
end

@doc raw"""
Pins a variable in this model to the value of a variable in another model.

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
    for var in get_affected_values(ff)
        variable = get_variable(container, var)
        device_name_set, set_time = JuMP.axes(variable)
        @assert issetequal(device_name_set, PSY.get_name.(devices))
        IS.@assert_op set_time == time_steps

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
