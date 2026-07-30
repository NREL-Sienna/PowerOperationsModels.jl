#! format: off
get_variable_lower_bound(::Type{ActivePowerVariable}, d::PSY.ThermalGen, ::Type{ThermalDispatchNoMin}) = 0.0
#! format: on

function get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    ::DeviceModel{T, D},
) where {T <: PSY.ThermalGen, D <: ThermalDispatchNoMin}
    return DeviceModel(T, ThermalDispatchNoMin)
end

"""
Min and max active power limits of generators for thermal dispatch no minimum formulations
"""
function get_min_max_limits(
    device::PSY.ThermalGen,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{ThermalDispatchNoMin},
)
    return (min = 0.0, max = PSY.get_active_power_limits(device, PSY.SU).max)
end

# can't have multi-start with ThermalDispatchNoMin.
function add_to_objective_function!(
    ::OptimizationContainer,
    ::IS.FlattenIteratorWrapper{PSY.ThermalMultiStart},
    ::DeviceModel{PSY.ThermalMultiStart, ThermalDispatchNoMin},
    ::Type{<:AbstractNetworkModel},
)
    throw(
        IS.ConflictingInputsError(
            "ThermalDispatchNoMin cost function is not compatible with ThermalMultiStart Devices.",
        ),
    )
end

"""
Add PWL cost terms for ThermalDispatchNoMin formulation.
Rejects non-convex or negative-slope PWL data since ThermalDispatchNoMin
cannot use SOS-2 formulations.
"""
function IOM.add_pwl_term_lambda!(
    container::IOM.OptimizationContainer,
    component::T,
    cost_function::Union{
        PSY.CostCurve{PSY.PiecewisePointCurve},
        PSY.FuelCurve{PSY.PiecewisePointCurve},
    },
    ::Type{U},
    ::Type{V},
) where {T <: PSY.ThermalGen, U <: IOM.VariableType, V <: ThermalDispatchNoMin}
    name = PSY.get_name(component)
    value_curve = PSY.get_value_curve(cost_function)
    cost_component = PSY.get_function_data(value_curve)
    base_power = IOM.get_model_base_power(container)
    device_base_power = PSY.get_base_power(component, PSY.NU)
    power_units = PSY.get_power_units(cost_function)

    # Normalize data
    data = IOM.get_piecewise_pointcurve_per_system_unit(
        cost_component,
        power_units,
        base_power,
        device_base_power,
    )
    @debug "PWL cost function detected for device $(name) using $V"
    slopes = PSY.get_slopes(data)
    if any(slopes .< 0) || !PSY.is_convex(data)
        throw(
            IS.InvalidValue(
                "The PWL cost data provided for generator $(name) is not compatible with $U.",
            ),
        )
    end

    # Compact PWL data does not exist anymore
    x_coords = PSY.get_x_coords(data)
    if x_coords[1] != 0.0
        y_coords = PSY.get_y_coords(data)
        x_first = round(x_coords[1]; digits = 3)
        y_first = round(y_coords[1]; digits = 3)
        slope_first = round(slopes[1]; digits = 3)
        guess_y_zero = y_coords[1] - slopes[1] * x_coords[1]
        @warn(
            "PWL has no 0.0 intercept for generator $(name). First point is given at (x = $(x_first), y = $(y_first)). Adding a first intercept at (x = 0.0, y = $(round(guess_y_zero, digits = 3)) to have equal initial slope $(slope_first)"
        )
        if guess_y_zero < 0.0
            error(
                "Added zero intercept has negative cost for generator $(name). Consider using other formulation or improve data.",
            )
        end
        intercept_point = (x = 0.0, y = guess_y_zero + IOM.COST_EPSILON)
        data = PSY.PiecewiseLinearData(vcat(intercept_point, PSY.get_points(data)))
        @assert PSY.is_convex(data)
    end

    time_steps = IOM.get_time_steps(container)
    pwl_cost_expressions = Vector{JuMP.AffExpr}(undef, time_steps[end])
    break_points = PSY.get_x_coords(data)
    sos_val = IOM._get_sos_value(container, V, component)
    temp_cost_function =
        create_temporary_cost_function_in_system_per_unit(cost_function, data)
    for t in time_steps
        IOM.add_pwl_variables_lambda!(container, T, name, t, data)
        power_var = IOM.get_variable(container, U, T)[name, t]
        IOM._add_pwl_constraint_standard!(
            container,
            component,
            break_points,
            sos_val,
            t,
            power_var,
        )
        pwl_cost =
            IOM.get_pwl_cost_expression_lambda(
                container,
                component,
                t,
                temp_cost_function,
                U,
                V,
            )
        pwl_cost_expressions[t] = pwl_cost
    end
    return pwl_cost_expressions
end
