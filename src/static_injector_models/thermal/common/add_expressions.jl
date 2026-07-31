"""
Thermal generators get the full constituent decomposition. Constituent expressions
auto-propagate into `ProductionCostExpression` (see IOM `_propagate_to_production_cost!`),
so we register the aggregate as well as the parts. `FuelConsumptionExpression` is added
only when at least one device has a `FuelCurve`, mirroring the existing FuelConsumption
specialization.
"""
function add_cost_expressions!(
    container::OptimizationContainer,
    devices::U,
    model::DeviceModel{D, W},
) where {
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractThermalFormulation,
} where {D <: PSY.ThermalGen}
    time_steps = get_time_steps(container)
    n = length(devices)
    all_names = Vector{String}(undef, n)
    fuel_names = sizehint!(String[], n)
    has_quad_fuel = false
    for (i, d) in enumerate(devices)
        name = PSY.get_name(d)
        all_names[i] = name
        fuel_curve = _get_cost_if_exists(PSY.get_operation_cost(d))
        _is_fuel_curve(fuel_curve) || continue
        push!(fuel_names, name)
        if !has_quad_fuel
            has_quad_fuel = _value_curve_is_quadratic(PSY.get_value_curve(fuel_curve))
        end
    end
    if !isempty(fuel_names)
        expr_type = has_quad_fuel ? JuMP.QuadExpr : GAE
        add_expression_container!(
            container, FuelConsumptionExpression, D, fuel_names, time_steps;
            expr_type = expr_type,
        )
    end
    add_expression_container!(container, ProductionCostExpression, D, all_names, time_steps)
    add_expression_container!(container, FuelCostExpression, D, all_names, time_steps)
    add_expression_container!(container, StartUpCostExpression, D, all_names, time_steps)
    add_expression_container!(container, ShutDownCostExpression, D, all_names, time_steps)
    add_expression_container!(container, FixedCostExpression, D, all_names, time_steps)
    add_expression_container!(container, VOMCostExpression, D, all_names, time_steps)
    return
end
