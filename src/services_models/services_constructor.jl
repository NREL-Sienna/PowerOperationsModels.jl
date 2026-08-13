# One `ServiceModel` per service TYPE (like `DeviceModel`). `construct_service!` runs once
# per type: it gets all services of the type via `get_available_components(model, sys)`,
# reads each service's contributing devices from the nested per-service map
# (`get_contributing_devices(model, service_name)`), and builds. Reserve variable and
# constraint containers are shared per `(entry type, service type)`, with each service
# filling its own slice. Group formulations are deferred to last (their members must exist).
#
# TODO(services stability): See issue #216.

# Group formulations aggregate other services' award variables, so they construct after
# every non-group service model.
_is_deferred_group_formulation(::Type{GroupRangeReserve}) = true
_is_deferred_group_formulation(::Type{GroupStepwiseCostReserve}) = true
_is_deferred_group_formulation(::Type) = false

# Collect the type's available services that have at least one modeled contributing device.
# The concrete element type keeps `add_parameters!` / `add_service_variables!` dispatch happy.
function _services_with_contributors(
    model::ServiceModel,
    sys::PSY.System,
)
    return [
        s for s in get_available_components(model, sys) if
        !isempty(get_contributing_devices_map(model, PSY.get_name(s)))
    ]
end

# Groups are device-less, so the device-map filter above cannot apply. The comprehensions
# keep the eltype concrete (e.g. `GroupReserve{ReserveUp, NaturalUnit}`): a bare
# `PSY.GroupReserve[]` accumulator would canonicalize container keys direction-less,
# unreachable by readers keyed on `GroupReserve{Dir}`.
function _groups_with_demand(model::ServiceModel, sys::PSY.System)
    candidates = [
        g for g in get_available_components(model, sys) if
        !isempty(PSY.get_contributing_services(g))
    ]
    for g in candidates
        _has_reserve_demand(model, g) || _log_skipped_reserve_demand(sys, g, model)
    end
    return [g for g in candidates if _has_reserve_demand(model, g)]
end

function construct_services!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ArgumentConstructStage,
    services_template::ServicesModelContainer,
    devices_template::DevicesModelContainer,
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    isempty(services_template) && return
    incompatible_device_types = get_incompatible_devices(devices_template)

    deferred_groups = Symbol[]
    for (key, service_model) in services_template
        if _is_deferred_group_formulation(get_formulation(service_model))
            push!(deferred_groups, key)  # constructed last
            continue
        end
        isempty(get_contributing_devices_map(service_model)) && continue
        construct_service!(
            container,
            sys,
            stage,
            service_model,
            devices_template,
            incompatible_device_types,
            network_model,
        )
    end
    for key in deferred_groups
        construct_service!(
            container,
            sys,
            stage,
            services_template[key],
            devices_template,
            incompatible_device_types,
            network_model,
        )
    end
    return
end

function construct_services!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ModelConstructStage,
    services_template::ServicesModelContainer,
    devices_template::DevicesModelContainer,
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    isempty(services_template) && return
    incompatible_device_types = get_incompatible_devices(devices_template)

    deferred_groups = Symbol[]
    for (key, service_model) in services_template
        if _is_deferred_group_formulation(get_formulation(service_model))
            push!(deferred_groups, key)  # constructed last
            continue
        end
        isempty(get_contributing_devices_map(service_model)) && continue
        construct_service!(
            container,
            sys,
            stage,
            service_model,
            devices_template,
            incompatible_device_types,
            network_model,
        )
    end
    for key in deferred_groups
        construct_service!(
            container,
            sys,
            stage,
            services_template[key],
            devices_template,
            incompatible_device_types,
            network_model,
        )
    end
    return
end

# One argument stage covers static and time-series-scaled reserves: the requirement
# time-series parameter is added only for services that carry a requirement series.
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.AbstractReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # A service with a zero requirement imposes no demand: its demand-side model is skipped, so it
    # needs no requirement parameter either. It is still built as supply below (its
    # `ActivePowerReserveVariable` awards, wired into the device-side expressions).
    demand_services = _demand_services(model, services)
    ts_services = [s for s in demand_services if _has_ts_requirement(model, s)]
    isempty(ts_services) ||
        add_parameters!(container, RequirementTimeSeriesParameter, ts_services, model)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_service_variables!(
            container,
            ActivePowerReserveVariable,
            service,
            contributing_devices,
            RangeReserve,
        )
        add_to_expression!(
            container,
            ActivePowerReserveVariable,
            service,
            model,
            devices_template,
        )
        add_feedforward_arguments!(container, model, service)
    end
    return
end

# Shared RangeReserve model stage for every `OnlineReserve`/`OfflineReserve`;
# the inner `add_constraints!` calls branch on the attached requirement series.
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.AbstractReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # Only services that actually impose a demand get requirement rows; the containers are sized to
    # that subset so a skipped service leaves no empty rows behind.
    demand_services = _demand_services(model, services)
    if !isempty(demand_services)
        demand_names = PSY.get_name.(demand_services)
        # Dense service-indexed containers are built once per type, then filled per service.
        add_constraints_container!(
            container,
            RequirementConstraint,
            SR,
            demand_names,
            get_time_steps(container),
        )
        get_use_slacks(model) && add_reserve_slacks!(container, SR, demand_names)
    end
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        if _has_reserve_demand(model, service)
            add_constraints!(
                container,
                RequirementConstraint,
                service,
                contributing_devices,
                model,
            )
            add_constraints!(
                container,
                ParticipationFractionConstraint,
                service,
                contributing_devices,
                model,
            )
            add_to_objective_function!(container, service, model)
        else
            # Supply-only: no requirement of its own (it may serve a GroupReserve). Price any
            # per-resource offers, but add no requirement constraint and no flat reserve cost.
            _log_skipped_reserve_demand(sys, service, model)
            add_reserve_offer_costs!(container, service, model)
        end
        add_feedforward_constraints!(container, model, service)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, StepwiseCostReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.AbstractReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # A service with no demand curve imposes no demand: it gets no ServiceRequirementVariable, no
    # cost expression, and no PWL parameters. It is still built as supply below (its
    # `ActivePowerReserveVariable` awards, wired into the device-side expressions), so it can serve
    # a GroupReserve. Sizing these containers to the demand subset keeps them free of empty rows.
    demand_services = _demand_services(model, services)
    if !isempty(demand_services)
        add_reserve_variables!(
            container,
            ServiceRequirementVariable,
            demand_services,
            StepwiseCostReserve(),
        )
        # Dense `(service, time)` cost-expression container, built once over the demand services.
        add_expressions!(container, ProductionCostExpression, demand_services, model)
        # Slope/breakpoint PWL cost params for the time-series-backed ORDCs (no-op otherwise).
        process_stepwise_cost_reserve_parameters!(container, model, demand_services)
    end
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_service_variables!(
            container,
            ActivePowerReserveVariable,
            service,
            contributing_devices,
            StepwiseCostReserve,
        )
        add_to_expression!(
            container,
            ActivePowerReserveVariable,
            service,
            model,
            devices_template,
        )
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, StepwiseCostReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.AbstractReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    demand_services = _demand_services(model, services)
    if !isempty(demand_services)
        # Dense service-indexed requirement container, sized to the demand subset.
        add_constraints_container!(
            container,
            RequirementConstraint,
            SR,
            PSY.get_name.(demand_services),
            get_time_steps(container),
        )
    end
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        if _has_reserve_demand(model, service)
            add_constraints!(
                container,
                RequirementConstraint,
                service,
                contributing_devices,
                model,
            )
            add_to_objective_function!(container, service, model)
        else
            # Supply-only: no demand curve of its own (it may serve a GroupReserve). Price any
            # per-resource offers; emit no requirement equality and no demand-side objective term.
            _log_skipped_reserve_demand(sys, service, model)
            add_reserve_offer_costs!(container, service, model)
        end
        add_feedforward_constraints!(container, model, service)
    end
    add_constraint_dual!(container, sys, model)
    return
end

#=
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{S, T},
    devices_template::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {S <: PSY.AGC, T <: AbstractAGCFormulation}
    services = get_available_components(model, sys)
    agc_areas = PSY.get_area.(services)
    areas = PSY.get_components(PSY.Area, sys)
    if !isempty(setdiff(areas, agc_areas))
        throw(
            IS.ConflictingInputsError(
                "All area must have an AGC service assigned in order to model the System's Frequency regulation",
            ),
        )
    end

    add_agc_variables!(container, SteadyStateFrequencyDeviation)
    add_variables!(container, AreaMismatchVariable, services, T)
    add_variables!(container, SmoothACE, services, T)
    add_variables!(container, LiftVariable, services, T)
    add_variables!(container, ActivePowerVariable, areas, T)
    add_variables!(container, DeltaActivePowerUpVariable, services, T)
    add_variables!(container, DeltaActivePowerDownVariable, services, T)
    add_variables!(container, AdditionalDeltaActivePowerUpVariable, areas, T)
    add_variables!(container, AdditionalDeltaActivePowerDownVariable, areas, T)

    add_initial_condition!(container, services, T(), AreaControlError())

    add_to_expression!(
        container,
        EmergencyUp,
        AdditionalDeltaActivePowerUpVariable,
        areas,
        model,
    )

    add_to_expression!(
        container,
        EmergencyDown,
        AdditionalDeltaActivePowerDownVariable,
        areas,
        model,
    )

    add_to_expression!(container, RawACE, SteadyStateFrequencyDeviation, services, model)

    add_feedforward_arguments!(container, model, services)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{S, T},
    devices_template::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {S <: PSY.AGC, T <: AbstractAGCFormulation}
    areas = PSY.get_components(PSY.Area, sys)
    services = get_available_components(model, sys)

    add_constraints!(container, AbsoluteValueConstraint, LiftVariable, services, model)
    add_constraints!(
        container,
        FrequencyResponseConstraint,
        SteadyStateFrequencyDeviation,
        services,
        model,
        sys,
    )
    add_constraints!(
        container,
        SACEPIDAreaConstraint,
        SteadyStateFrequencyDeviation,
        services,
        model,
        sys,
    )
    add_constraints!(container, BalanceAuxConstraint, SmoothACE, services, model, sys)

    add_feedforward_constraints!(container, model, services)

    add_constraint_dual!(container, sys, model)

    add_to_objective_function!(container, services, model)
    return
end
=#

"""
    Constructs a service for GroupRangeReserve.
"""
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, GroupRangeReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.GroupReserve}
    for service in get_available_components(model, sys)
        contributing_services = PSY.get_contributing_services(service)
        # check if variables exist
        check_activeservice_variables(container, contributing_services)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, GroupRangeReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.GroupReserve}
    groups = collect(get_available_components(model, sys))
    # Dense group-indexed requirement container, built once over all groups of the type.
    add_constraints_container!(
        container,
        RequirementConstraint,
        SR,
        PSY.get_name.(groups),
        get_time_steps(container),
    )
    for service in groups
        contributing_services = PSY.get_contributing_services(service)
        add_constraints!(
            container,
            RequirementConstraint,
            service,
            contributing_services,
            model,
        )
    end
    add_constraint_dual!(container, sys, model)
    return
end

"""
    Constructs a service for GroupStepwiseCostReserve: the group's demand curve is cleared by
    the summed awards of its contributing services.
"""
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, GroupStepwiseCostReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.GroupReserve}
    groups = _groups_with_demand(model, sys)
    isempty(groups) && return
    # Dense (group, time) container: the delta-PWL block constraint reads axes(variables).
    add_reserve_variables!(
        container,
        ServiceRequirementVariable,
        groups,
        GroupStepwiseCostReserve(),
    )
    add_expressions!(container, ProductionCostExpression, groups, model)
    # Slope/breakpoint PWL cost params for time-series-backed group curves (no-op otherwise).
    process_stepwise_cost_reserve_parameters!(container, model, groups)
    for group in groups
        check_activeservice_variables(container, PSY.get_contributing_services(group))
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, GroupStepwiseCostReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.GroupReserve}
    groups = _groups_with_demand(model, sys)
    isempty(groups) && return
    add_constraints_container!(
        container,
        RequirementConstraint,
        SR,
        PSY.get_name.(groups),
        get_time_steps(container),
    )
    for group in groups
        add_constraints!(
            container,
            RequirementConstraint,
            group,
            PSY.get_contributing_services(group),
            model,
        )
        add_to_objective_function!(container, group, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, RampReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.Reserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # Only services carrying a requirement series get the parameter (a curve-only ORDC of the
    # same type has none).
    ts_services = [s for s in services if _has_ts_requirement(model, s)]
    isempty(ts_services) ||
        add_parameters!(container, RequirementTimeSeriesParameter, ts_services, model)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_service_variables!(
            container,
            ActivePowerReserveVariable,
            service,
            contributing_devices,
            RampReserve,
        )
        add_to_expression!(
            container,
            ActivePowerReserveVariable,
            service,
            model,
            devices_template,
        )
        add_feedforward_arguments!(container, model, service)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, RampReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.Reserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    service_names = PSY.get_name.(services)
    # Dense service-indexed containers are built once per type, then filled per service.
    add_constraints_container!(
        container,
        RequirementConstraint,
        SR,
        service_names,
        get_time_steps(container),
    )
    get_use_slacks(model) && add_reserve_slacks!(container, SR, service_names)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_constraints!(
            container,
            RequirementConstraint,
            service,
            contributing_devices,
            model,
        )
        add_constraints!(container, RampConstraint, service, contributing_devices, model)
        add_constraints!(
            container,
            ParticipationFractionConstraint,
            service,
            contributing_devices,
            model,
        )
        add_to_objective_function!(container, service, model)
        add_feedforward_constraints!(container, model, service)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, NonSpinningReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.OfflineReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # Only services carrying a requirement series get the parameter (a curve-only ORDC of the
    # same type has none).
    ts_services = [s for s in services if _has_ts_requirement(model, s)]
    isempty(ts_services) ||
        add_parameters!(container, RequirementTimeSeriesParameter, ts_services, model)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_service_variables!(
            container,
            ActivePowerReserveVariable,
            service,
            contributing_devices,
            NonSpinningReserve,
        )
        add_feedforward_arguments!(container, model, service)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{SR, NonSpinningReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.OfflineReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    service_names = PSY.get_name.(services)
    # Dense service-indexed containers are built once per type, then filled per service.
    add_constraints_container!(
        container,
        RequirementConstraint,
        SR,
        service_names,
        get_time_steps(container),
    )
    get_use_slacks(model) && add_reserve_slacks!(container, SR, service_names)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_constraints!(
            container,
            RequirementConstraint,
            service,
            contributing_devices,
            model,
        )
        add_constraints!(
            container,
            ReservePowerConstraint,
            service,
            contributing_devices,
            model,
        )
        add_constraints!(
            container,
            ParticipationFractionConstraint,
            service,
            contributing_devices,
            model,
        )
        add_to_objective_function!(container, service, model)
        add_feedforward_constraints!(container, model, service)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{T, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {T <: PSY.TransmissionInterface}
    interfaces = collect(get_available_components(model, sys))
    # Lazy container addition for the expressions.
    lazy_container_addition!(container, InterfaceTotalFlow,
        T,
        PSY.get_name.(interfaces),
        get_time_steps(container),
    )
    if get_use_slacks(model)
        transmission_interface_slacks!(container, interfaces)
    end
    for interface in interfaces
        add_feedforward_arguments!(container, model, interface)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{AreaBalanceNetworkModel},
)
    interfaces = collect(get_available_components(model, sys))
    # Lazy container addition for the expressions.
    lazy_container_addition!(container, InterfaceTotalFlow,
        PSY.TransmissionInterface,
        PSY.get_name.(interfaces),
        get_time_steps(container),
    )
    @warn "AreaBalanceNetworkModel doesn't model individual line flows and it ignores the flows on AC Transmission Devices"
    if get_use_slacks(model)
        transmission_interface_slacks!(container, interfaces)
    end
    for interface in interfaces
        add_feedforward_arguments!(container, model, interface)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{<:AbstractActivePowerModel},
)
    for service in get_available_components(model, sys)
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            FlowActivePowerVariable,
            service,
            model,
            network_model,
        )

        if get_use_slacks(model)
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackUp,
                service,
                model,
            )
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackDown,
                service,
                model,
            )
        end

        add_constraints!(container, InterfaceFlowLimit, service, model)
        add_feedforward_constraints!(container, model, service)
        add_to_objective_function!(container, service, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{PTDFNetworkModel},
)
    for service in get_available_components(model, sys)
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            PTDFBranchFlow,
            service,
            model,
            network_model,
        )

        if get_use_slacks(model)
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackUp,
                service,
                model,
            )
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackDown,
                service,
                model,
            )
        end

        add_constraints!(container, InterfaceFlowLimit, service, model)
        add_feedforward_constraints!(container, model, service)
        add_to_objective_function!(container, service, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{AreaPTDFNetworkModel},
)
    for service in get_available_components(model, sys)
        # This function makes interfaces for the AC Branches
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            PTDFBranchFlow,
            service,
            model,
            network_model,
        )

        # This function makes interfaces for the interchanges
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            FlowActivePowerVariable,
            service,
            model,
            network_model,
        )

        if get_use_slacks(model)
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackUp,
                service,
                model,
            )
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackDown,
                service,
                model,
            )
        end

        add_constraints!(container, InterfaceFlowLimit, service, model)
        add_feedforward_constraints!(container, model, service)
        add_to_objective_function!(container, service, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, VariableMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{<:AbstractPTDFNetworkModel},
)
    for service in get_available_components(model, sys)
        # This function makes interfaces for the AC Branches
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            PTDFBranchFlow,
            service,
            model,
            network_model,
        )

        if get_use_slacks(model)
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackUp,
                service,
                model,
            )
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackDown,
                service,
                model,
            )
        end

        add_constraints!(container, InterfaceFlowLimit, service, model)
        add_feedforward_constraints!(container, model, service)
        add_to_objective_function!(container, service, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, U},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{T},
) where {
    T <: AbstractNetworkModel,
    U <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow},
}
    error("TransmissionInterface models not implemented for PowerModel of type $T")
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, VariableMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{<:AbstractNetworkModel},
)
    interfaces = collect(get_available_components(model, sys))
    # Lazy container addition for the expressions.
    lazy_container_addition!(container, InterfaceTotalFlow,
        PSY.TransmissionInterface,
        PSY.get_name.(interfaces),
        get_time_steps(container),
    )
    has_ts = PSY.has_time_series.(interfaces)
    if any(has_ts) && !all(has_ts)
        error(
            "Not all TransmissionInterfaces devices have time series. Check data to complete (or remove) time series.",
        )
    end
    if get_use_slacks(model)
        transmission_interface_slacks!(container, interfaces)
    end
    if !isempty(interfaces) && all(has_ts)
        for interface in interfaces
            name = PSY.get_name(interface)
            num_ts = length(unique(PSY.get_name.(PSY.get_time_series_keys(interface))))
            if num_ts < 2
                error(
                    "TransmissionInterface $name has less than two time series. It is required to add both min_flow and max_flow time series.",
                )
            end
        end
        # One parameter container per type over all interfaces, filled per interface by the
        # vector `_add_parameters!` path.
        add_parameters!(container, MinInterfaceFlowLimitParameter, interfaces, model)
        add_parameters!(container, MaxInterfaceFlowLimitParameter, interfaces, model)
    end
    for interface in interfaces
        add_feedforward_arguments!(container, model, interface)
    end
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::ServiceModel{PSY.TransmissionInterface, U},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {U <: Union{ConstantMaxInterfaceFlow, VariableMaxInterfaceFlow}}
    for service in get_available_components(model, sys)
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            FlowActivePowerVariable,
            service,
            model,
            network_model,
        )

        if get_use_slacks(model)
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackUp,
                service,
                model,
            )
            add_to_expression!(
                container,
                InterfaceTotalFlow,
                InterfaceFlowSlackDown,
                service,
                model,
            )
        end

        add_constraints!(container, InterfaceFlowLimit, service, model)
        add_feedforward_constraints!(container, model, service)
        add_to_objective_function!(container, service, model)
    end
    add_constraint_dual!(container, sys, model)
    return
end
