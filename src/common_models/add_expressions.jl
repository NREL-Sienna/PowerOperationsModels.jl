#################################################################################
# Expression container creation
# These create expression containers for devices and services
#################################################################################

function _ref_index(network_model::NetworkModel{<:AbstractPowerModel}, bus::PSY.ACBus)
    return get_reference_bus(network_model, bus)
end

function _ref_index(::NetworkModel{AreaPTDFPowerModel}, device_bus::PSY.ACBus)
    return PSY.get_name(PSY.get_area(device_bus))
end

_get_variable_if_exists(::PSY.MarketBidCost) = nothing
_get_variable_if_exists(cost::PSY.OperationalCost) = PSY.get_variable(cost)

function get_reference_bus(
    model::NetworkModel{T},
    b::PSY.ACBus,
)::Int where {T <: AbstractPowerModel}
    if isempty(model.bus_area_map)
        return first(keys(model.subnetworks))
    else
        return model.bus_area_map[b]
    end
end

"""
Generic implementation to add expression containers for devices.
"""
function add_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: ExpressionType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    add_expression_container!(container, T(), D, names, time_steps)
    return
end

"""
Specialized implementation for FuelConsumptionExpression that checks for fuel curves.
"""
function add_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: FuelConsumptionExpression,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    names = String[]
    found_quad_fuel_functions = false
    for d in devices
        op_cost = PSY.get_operation_cost(d)
        fuel_curve = _get_variable_if_exists(op_cost)
        if fuel_curve isa PSY.FuelCurve
            push!(names, PSY.get_name(d))
            if !found_quad_fuel_functions
                found_quad_fuel_functions =
                    PSY.get_value_curve(fuel_curve) isa PSY.QuadraticCurve
            end
        end
    end

    if !isempty(names)
        expr_type = found_quad_fuel_functions ? JuMP.QuadExpr : GAE
        add_expression_container!(
            container,
            T(),
            D,
            names,
            time_steps;
            expr_type = expr_type,
        )
    end
    return
end

"""
Generic implementation for service models with reserves.
"""
function add_expressions!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::ServiceModel{V, W},
) where {
    T <: ExpressionType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: PSY.Reserve,
    W <: AbstractReservesFormulation,
} where {D <: PSY.Component}
    time_steps = get_time_steps(container)
    @assert length(devices) == 1
    add_expression_container!(
        container,
        T(),
        D,
        PSY.get_name.(devices),
        time_steps;
        meta = get_service_name(model),
    )
    return
end
