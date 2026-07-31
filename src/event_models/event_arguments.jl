#################################################################################
# Event parameter creation (ArgumentConstructStage)
#################################################################################

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    device_model::DeviceModel{D, W},
    event_model::EventModel{V, X},
) where {
    T <: ParameterType,
    U <: Vector{D},
    V <: PSY.Contingency,
    W <: AbstractDeviceFormulation,
    X <: AbstractEventCondition,
} where {D <: PSY.Component}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, D)
        return
    end
    _add_parameters!(container, T(), devices, device_model, event_model)
    return
end

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    devices::Vector{U},
    device_model::DeviceModel{U, W},
    event_model::EventModel{V, X},
) where {
    T <: EventParameter,
    U <: PSY.Component,
    V <: PSY.Contingency,
    W <: AbstractDeviceFormulation,
    X <: AbstractEventCondition,
}
    @debug "adding" T U V _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(
        container,
        T,
        U,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    for (i, d) in enumerate(devices)
        ini_val = get_initial_parameter_value(T(), d, event_model)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T(), d, event_model),
            i,
        )
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ini_val, i, t)
        end
    end
    return
end

#################################################################################
# Offset parameters into the system balance expressions.
# One method for every network family: `_balance_expression_targets` resolves the
# system/area/nodal targets per network model (this replaces PSI's four
# per-network methods).
#################################################################################

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: EventParameter,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    param_array = get_parameter_array(container, U(), V)
    multiplier = get_parameter_multiplier_array(container, U(), V)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        for t in time_steps
            _apply_term_to_targets!(targets, param_array[name, t], multiplier[name, t], t)
        end
    end
    return
end

#################################################################################
# add_event_arguments! — overrides the no-op stub in core/feedforward_interface.jl
# for the injector families. No-ops when the DeviceModel has no events attached.
#################################################################################

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel,
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        for p_type in [AvailableStatusChangeCountdownParameter, AvailableStatusParameter]
            add_parameters!(
                container,
                p_type,
                devices_with_attributes,
                device_model,
                event_model,
            )
        end
    end
    return
end

#################################################################################
# Load and FixedOutput argument variants: on top of the generic status/countdown
# parameters above, these devices also get an offset parameter injected directly
# into the system balance expression(s), so an outage event can remove/restore
# a device's contribution without touching its dispatch variables.
#################################################################################

const _EventLoadFormulations =
    Union{StaticPowerLoad, PowerLoadDispatch, PowerLoadInterruption}

function _add_event_offset_arguments!(
    container::OptimizationContainer,
    devices_with_attributes::Vector{U},
    device_model::DeviceModel,
    network_model::NetworkModel,
    event_model::EventModel,
    with_reactive::Bool,
) where {U <: PSY.StaticInjection}
    for p_type in [AvailableStatusChangeCountdownParameter, AvailableStatusParameter]
        add_parameters!(
            container,
            p_type,
            devices_with_attributes,
            device_model,
            event_model,
        )
    end
    add_parameters!(
        container,
        ActivePowerOffsetParameter,
        devices_with_attributes,
        device_model,
        event_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerOffsetParameter,
        devices_with_attributes,
        device_model,
        network_model,
    )
    if with_reactive
        add_parameters!(
            container,
            ReactivePowerOffsetParameter,
            devices_with_attributes,
            device_model,
            event_model,
        )
        add_to_expression!(
            container,
            ReactivePowerBalance,
            ReactivePowerOffsetParameter,
            devices_with_attributes,
            device_model,
            network_model,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: _EventLoadFormulations,
} where {U <: PSY.PowerLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            false,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: _EventLoadFormulations,
} where {U <: PSY.PowerLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            true,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, FixedOutput},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            false,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, FixedOutput},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            true,
        )
    end
    return
end
