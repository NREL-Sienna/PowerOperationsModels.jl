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
    requirement = _get_requirement(service)

    # Index each contributing reserve's provision from its type's merged
    # `(service_name, device_name, time)` container, keyed `(service_name, t)`, in a single pass.
    member_vars = _group_member_variables(container, contributing_services)

    for t in time_steps
        resource_expression = JuMP.GenericAffExpr{Float64, JuMP.VariableRef}()
        for r in contributing_services
            for var in get(member_vars, (PSY.get_name(r), t), JuMP.VariableRef[])
                JuMP.add_to_expression!(resource_expression, var)
            end
        end
        constraint[service_name, t] =
            JuMP.@constraint(container.JuMPmodel, resource_expression >= requirement)
    end

    return
end

# Bucket the group's contributing reserve variables by `(service_name, time)` in one pass over
# each contributing service's merged `(service_name, device_name, time)` container, so the
# constraint loop above does keyed lookups instead of re-scanning the whole container per
# `(group, t)`. Same-type services share one merged container, so each container is scanned once.
function _group_member_variables(
    container::OptimizationContainer,
    contributing_services::Vector{<:PSY.Service},
)
    member_names = Set(PSY.get_name(r) for r in contributing_services)
    index = Dict{Tuple{String, Int}, Vector{JuMP.VariableRef}}()
    scanned = Set{DataType}()
    for r in contributing_services
        rtype = typeof(r)
        rtype in scanned && continue
        push!(scanned, rtype)
        reserve_variable = get_variable(container, ActivePowerReserveVariable, rtype)
        for (key, var) in reserve_variable.data
            key[1] in member_names || continue
            push!(get!(Vector{JuMP.VariableRef}, index, (key[1], key[3])), var)
        end
    end
    return index
end
