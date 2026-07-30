function get_default_time_series_names(
    ::Type{PSY.ConstantReserveGroup{T}},
    ::Type{GroupReserve}) where {T <: PSY.ReserveDirection}
    return Dict{String, Any}()
end

function get_default_attributes(
    ::Type{PSY.ConstantReserveGroup{T}},
    ::Type{GroupReserve}) where {T <: PSY.ReserveDirection}
    return Dict{String, Any}()
end

############################### Reserve Variables` #########################################
"""
This function checks if the variables for reserves were created
"""
function check_activeservice_variables(
    container::OptimizationContainer,
    contributing_services::Vector{T},
) where {T <: PSY.Service}
    for service in contributing_services
        service_name = PSY.get_name(service)
        variable = get_variable(container, ActivePowerReserveVariable, typeof(service))
        # Merged container is keyed `(service_name, device_name, time)`; confirm this
        # contributing service actually has entries rather than just that the container
        # for the type exists.
        any(k -> k[1] == service_name, keys(variable.data)) || error(
            "The contributing service $service_name has no ActivePowerReserveVariable \
             entries; it must be modeled before the group reserve that references it.",
        )
    end
    return
end

################################## Reserve Requirement Constraint ##########################
"""
This function creates the requirement constraint that will be attained by the appropriate services
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{RequirementConstraint},
    service::SR,
    contributing_services::Vector{<:PSY.Service},
    model::ServiceModel{SR, GroupReserve},
) where {SR <: PSY.ConstantReserveGroup}
    time_steps = get_time_steps(container)
    service_name = PSY.get_name(service)
    # Dense 2D group-requirement container keyed `[group_name, time]`, created once per type
    # in `construct_service!`; fill this group's row.
    constraint = get_constraint(container, RequirementConstraint, SR)
    # Each contributing reserve's provision comes from its type's merged
    # `(service_name, device_name, time)` container; sum the contributing service's slice.
    contributing = [
        (PSY.get_name(r), get_variable(container, ActivePowerReserveVariable, typeof(r)))
        for r in contributing_services
    ]

    requirement = _get_requirement(service)
    for t in time_steps
        resource_expression = JuMP.GenericAffExpr{Float64, JuMP.VariableRef}()
        for (r_name, reserve_variable) in contributing
            # Function barrier: `contributing` holds abstractly-typed variable containers, so this
            # call specializes on `reserve_variable`'s concrete type; the `add_to_expression!`
            # inside is statically dispatched instead of once-per-entry dynamic dispatch.
            _accumulate_group_reserve!(resource_expression, reserve_variable, r_name, t)
        end
        constraint[service_name, t] =
            JuMP.@constraint(container.JuMPmodel, resource_expression >= requirement)
    end

    return
end

# TODO(services efficiency): this scans the contributing service's entire merged
# `(service_name, device_name, time)` container per `(group, t)`. Once the group's contributing
# device names are threaded through, replace the `.data` scan with a keyed slice to drop the
# O(entries) cost.
function _accumulate_group_reserve!(
    resource_expression::JuMP.GenericAffExpr,
    reserve_variable::SparseAxisArray,
    r_name::String,
    t::Int,
)
    for (key, var) in reserve_variable.data
        key[1] == r_name && key[3] == t || continue
        JuMP.add_to_expression!(resource_expression, var)
    end
    return
end
