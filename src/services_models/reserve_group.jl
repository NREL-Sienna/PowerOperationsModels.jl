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
        # The container is keyed `(service_name, device_name, time)` and shared by the whole
        # service type, so check for this service's own entries, not just that it exists.
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
    # Dense container keyed `[group_name, time]`, built per type; fill this group's row.
    constraint = get_constraint(container, RequirementConstraint, SR)
    requirement = _get_requirement(service)

    # Bucket every contributing reserve's provision by time step in a single pass. The
    # constraint sums across all of them, so no per-service key is needed.
    member_vars = _group_member_variables(container, contributing_services, time_steps)
    jump_model = get_jump_model(container)

    for t in time_steps
        vars = member_vars[t]
        resource_expression = IOM.get_hinted_aff_expr(length(vars))
        for var in vars
            JuMP.add_to_expression!(resource_expression, var)
        end
        constraint[service_name, t] =
            JuMP.@constraint(jump_model, resource_expression >= requirement)
    end

    return
end

# Collect the group's contributing reserve variables into one bucket per time step, so the
# constraint loop above indexes straight in rather than re-scanning per `(group, t)`. Services
# of the same type share one `(service_name, device_name, time)` container, so each container
# is scanned once.
function _group_member_variables(
    container::OptimizationContainer,
    contributing_services::Vector{<:PSY.Service},
    time_steps::UnitRange{Int},
)
    member_names = Set(PSY.get_name(r) for r in contributing_services)
    index = [JuMP.VariableRef[] for _ in time_steps]
    scanned = Set{DataType}()
    for r in contributing_services
        rtype = typeof(r)
        rtype in scanned && continue
        push!(scanned, rtype)
        reserve_variable = get_variable(container, ActivePowerReserveVariable, rtype)
        for (key, var) in reserve_variable.data
            key[1] in member_names || continue
            push!(index[key[3]], var)
        end
    end
    return index
end
