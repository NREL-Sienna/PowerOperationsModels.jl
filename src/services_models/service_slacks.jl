function add_reserve_slacks!(
    container::OptimizationContainer,
    ::Type{T},
    service_names::Vector{String},
) where {T <: Union{PSY.Reserve, PSY.ReserveNonSpinning}}
    time_steps = get_time_steps(container)
    # Dense 2D container keyed `[service_name, time]`, built once per service type over all
    # the type's services (`use_slacks` is per type). Lower bound 0, penalty in objective.
    variable = add_variable_container!(container, ReserveRequirementSlack, T,
        service_names, time_steps)

    jump_model = get_jump_model(container)
    for name in service_names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            base_name = "slack_{$(name), $(t)}",
            lower_bound = 0.0
        )
        add_to_objective_invariant_expression!(
            container,
            variable[name, t] * SERVICES_SLACK_COST,
        )
    end
    return
end

function transmission_interface_slacks!(
    container::OptimizationContainer,
    services::Vector{T},
) where {T <: PSY.TransmissionInterface}
    time_steps = get_time_steps(container)
    interface_names = [PSY.get_name(s) for s in services]
    jump_model = get_jump_model(container)

    # DELETE-AFTER-REVIEW: reviewer context on the container change; remove once the PR is approved.
    # One dense 2D container per (slack variable type, TransmissionInterface) keyed
    # `[interface_name, time]`, built once over all interfaces (`use_slacks` is per type),
    # empty meta. Each interface's slacks carry its own violation penalty.
    for variable_type in [InterfaceFlowSlackUp, InterfaceFlowSlackDown]
        variable =
            add_variable_container!(
                container,
                variable_type,
                T,
                interface_names,
                time_steps,
            )
        for service in services
            name = PSY.get_name(service)
            penalty = PSY.get_violation_penalty(service)
            for t in time_steps
                variable[name, t] = JuMP.@variable(
                    jump_model,
                    base_name = "$(T)_$(variable_type)_{$(name), $(t)}",
                    lower_bound = 0.0,
                )
                add_to_objective_invariant_expression!(
                    container,
                    variable[name, t] * penalty,
                )
            end
        end
    end

    return
end
