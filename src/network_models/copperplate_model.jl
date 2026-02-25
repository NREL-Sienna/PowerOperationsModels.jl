function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    sys::U,
    model::NetworkModel{V},
) where {
    T <: CopperPlateBalanceConstraint,
    U <: PSY.System,
    V <: Union{CopperPlatePowerModel, PTDFPowerModel, SecurityConstrainedPTDFPowerModel},
}
    time_steps = get_time_steps(container)
    expressions = get_expression(container, ActivePowerBalance(), U)
    subnets = collect(keys(model.subnetworks))
    constraint = add_constraints_container!(container, T(), U, subnets, time_steps)
    for t in time_steps, k in keys(model.subnetworks)
        constraint[k, t] =
            JuMP.@constraint(get_jump_model(container), expressions[k, t] == 0)
    end

    return
end

########################### Dual variable handling ####################################
# CopperPlate and PTDF constraints are keyed on System, not ACBus,
# so dual registration and calculation need special handling.

function add_constraint_dual!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{T},
) where {T <: Union{CopperPlatePowerModel, AbstractPTDFModel}}
    if !isempty(get_duals(model))
        for constraint_type in get_duals(model)
            assign_dual_variable!(container, constraint_type, sys, model)
        end
    end
    return
end

function assign_dual_variable!(
    container::OptimizationContainer,
    constraint_type::Type{CopperPlateBalanceConstraint},
    ::U,
    network_model::NetworkModel{<:AbstractPowerModel},
) where {U <: PSY.System}
    time_steps = get_time_steps(container)
    ref_buses = get_reference_buses(network_model)
    add_dual_container!(container, constraint_type, U, ref_buses, time_steps)
    return
end

function _calculate_dual_variable_value!(
    container::OptimizationContainer,
    key::ConstraintKey{CopperPlateBalanceConstraint, PSY.System},
    ::PSY.System,
)
    constraint_container = get_constraint(container, key)
    dual_variable_container = get_duals(container)[key]
    for subnet in axes(constraint_container)[1], t in axes(constraint_container)[2]
        # See https://jump.dev/JuMP.jl/stable/manual/solutions/#Dual-solution-values
        dual_variable_container[subnet, t] = jump_value(constraint_container[subnet, t])
    end
    return
end

########################### Area Balance Constraints ###################################

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    sys::U,
    network_model::NetworkModel{V},
) where {
    T <: CopperPlateBalanceConstraint,
    U <: PSY.System,
    V <: Union{AreaPTDFPowerModel, SecurityConstrainedAreaPTDFPowerModel},
}
    time_steps = get_time_steps(container)
    expressions = get_expression(container, ActivePowerBalance(), PSY.Area)
    area_names = PSY.get_name.(get_available_components(network_model, PSY.Area, sys))
    constraint =
        add_constraints_container!(container, T(), PSY.Area, area_names, time_steps)
    jm = get_jump_model(container)
    for t in time_steps, k in area_names
        constraint[k, t] = JuMP.@constraint(jm, expressions[k, t] == 0)
    end

    return
end
