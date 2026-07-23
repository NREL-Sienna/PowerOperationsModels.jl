# One `ServiceModel` per service TYPE (like `DeviceModel`). `construct_service!` runs once
# per type: it gets all services of the type via `get_available_components(model, sys)`,
# reads each service's contributing devices from the nested per-service map
# (`get_contributing_devices(model, service_name)`), and builds. The reserve variable /
# constraint containers are merged per `(entry type, service type)`; each service fills its
# own slice. `GroupReserve` is deferred to last.
#
# TODO(services stability, deferred B1): `get_contributing_devices(model, service_name)` (used by
# the `construct_service!` methods below) flattens across device types, so its element type widens
# to an abstract ancestor when a service has more than one contributing device type; the downstream
# builders then dynamic-dispatch per device. Iterate `get_contributing_devices_map(model, name)`
# (`Dict{DataType, Vector}`, concretely-typed groups) and call the builders once per homogeneous
# group instead. Build-time-only; this is the POM twin of the deferred IOM per-type-group barrier.
# See .claude/plans/service-refactor-stability.md.

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

    groupservice = nothing
    for (key, service_model) in services_template
        if get_formulation(service_model) === GroupReserve  # constructed last
            groupservice = key
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
    groupservice === nothing || construct_service!(
        container,
        sys,
        stage,
        services_template[groupservice],
        devices_template,
        incompatible_device_types,
        network_model,
    )
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

    groupservice = nothing
    for (key, service_model) in services_template
        if get_formulation(service_model) === GroupReserve  # constructed last
            groupservice = key
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
    groupservice === nothing || construct_service!(
        container,
        sys,
        stage,
        services_template[groupservice],
        devices_template,
        incompatible_device_types,
        network_model,
    )
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.Reserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    add_parameters!(container, RequirementTimeSeriesParameter, services, model)
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

# ConstantReserve has no requirement time series, so its argument stage skips the
# parameter add. The model stage is the shared `SR <: PSY.AbstractReserve` method below.
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.ConstantReserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
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

# Shared RangeReserve model stage for both `PSY.Reserve` and `PSY.ConstantReserve`;
# the inner `add_constraints!` calls resolve per service type.
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

_maybe_process_stepwise(container, model, service::PSY.ReserveDemandTimeSeriesCurve) =
    process_stepwise_cost_reserve_parameters!(container, model, service)
_maybe_process_stepwise(container, model, service) = nothing

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, StepwiseCostReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.Reserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    add_reserve_variables!(
        container,
        ServiceRequirementVariable,
        services,
        StepwiseCostReserve(),
    )
    # Merged dense `(service, time)` cost-expression container, built once over all services.
    add_expressions!(container, ProductionCostExpression, services, model)
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_service_variables!(
            container,
            ActivePowerReserveVariable,
            service,
            contributing_devices,
            StepwiseCostReserve,
        )
        _maybe_process_stepwise(container, model, service)
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
) where {SR <: PSY.Reserve}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    # Dense service-indexed requirement container, built once per type, filled per service.
    add_constraints_container!(
        container,
        RequirementConstraint,
        SR,
        PSY.get_name.(services),
        get_time_steps(container),
    )
    for service in services
        contributing_devices = get_contributing_devices(model, PSY.get_name(service))
        add_constraints!(
            container,
            RequirementConstraint,
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
    Constructs a service for ConstantReserveGroup.
"""
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::ServiceModel{SR, GroupReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.ConstantReserveGroup}
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
    model::ServiceModel{SR, GroupReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
    ::NetworkModel{<:AbstractNetworkModel},
) where {SR <: PSY.ConstantReserveGroup}
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
    add_parameters!(container, RequirementTimeSeriesParameter, services, model)
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
) where {SR <: PSY.ReserveNonSpinning}
    services = _services_with_contributors(model, sys)
    isempty(services) && return
    add_parameters!(container, RequirementTimeSeriesParameter, services, model)
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
) where {SR <: PSY.ReserveNonSpinning}
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
        # Merged per-type parameter containers over all interfaces (empty meta), filled per
        # interface by the vector `_add_parameters!` path.
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
