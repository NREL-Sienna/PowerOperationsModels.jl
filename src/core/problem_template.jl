"""
    PowerOperationsProblemTemplate(::Type{T}) where {T<:AbstractNetworkModel}

Creates a model reference of the InfrastructureOptimizationModels Optimization Problem.

# Arguments

  - `model::Type{T<:AbstractNetworkModel}`:

# Example

template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
"""
mutable struct PowerOperationsProblemTemplate <: IOM.AbstractProblemTemplate
    network_model::NetworkModel{<:AbstractNetworkModel}
    devices::DevicesModelContainer
    branches::BranchModelContainer
    services::ServicesModelContainer
    events::Vector{IOM.AbstractEventModel}
    function PowerOperationsProblemTemplate(
        network::NetworkModel{T},
    ) where {T <: AbstractNetworkModel}
        new(
            network,
            DevicesModelContainer(),
            BranchModelContainer(),
            ServicesModelContainer(),
            Vector{IOM.AbstractEventModel}(),
        )
    end
end

function Base.isempty(template::PowerOperationsProblemTemplate)
    if !isempty(template.devices)
        return false
    elseif !isempty(template.branches)
        return false
    elseif !isempty(template.services)
        return false
    else
        return true
    end
end

PowerOperationsProblemTemplate(::Type{T}) where {T <: AbstractNetworkModel} =
    PowerOperationsProblemTemplate(NetworkModel(T))

PowerOperationsProblemTemplate() = PowerOperationsProblemTemplate(CopperPlateNetworkModel)

get_device_models(template::PowerOperationsProblemTemplate) = template.devices
get_branch_models(template::PowerOperationsProblemTemplate) = template.branches
get_service_models(template::PowerOperationsProblemTemplate) = template.services
get_network_model(template::PowerOperationsProblemTemplate) = template.network_model
get_network_formulation(template::PowerOperationsProblemTemplate) =
    get_network_formulation(get_network_model(template))
get_hvdc_network_model(template::PowerOperationsProblemTemplate) =
    template.network_model.hvdc_network_model

"""
Return the outage-event models attached to `template` via `set_event_model!`.
"""
get_event_models(template::PowerOperationsProblemTemplate) = template.events

# Returns `Vector{Type}`, not `Vector{DataType}`: a service component type can be a
# UnionAll (e.g. PSY6 parameterized `ReserveDemandCurve{ReserveUp}` on a unit-system
# type, leaving a trailing free parameter), which is not a `DataType`.
function get_component_types(template::PowerOperationsProblemTemplate)::Vector{Type}
    return vcat(
        get_component_type.(values(get_device_models(template))),
        get_component_type.(values(get_branch_models(template))),
        get_component_type.(values(get_service_models(template))),
    )
end

function get_model(
    template::PowerOperationsProblemTemplate,
    ::Type{T},
) where {T <: PSY.Device}
    if T <: PSY.Branch
        return get(template.branches, nameof(T), nothing)
    elseif T <: PSY.Device
        return get(template.devices, nameof(T), nothing)
    else
        error("Component $T not present in the template")
    end
end

function get_model(
    template::PowerOperationsProblemTemplate,
    ::Type{T},
    name::String = NO_SERVICE_NAME_PROVIDED,
) where {T <: PSY.Service}
    if haskey(template.services, (name, Symbol(T)))
        return template.services[(name, Symbol(T))]
    else
        error("Service $T $name not present in the template")
    end
end

# Note to devs. PSY exports set_model! these names are chosen to avoid name clashes

"""
Sets the network model in a template.
"""
function set_network_model!(
    template::PowerOperationsProblemTemplate,
    model::NetworkModel{<:AbstractNetworkModel},
)
    template.network_model = model
    return
end

"""
Sets the network model in a template.
"""
function set_hvdc_network_model!(
    template::PowerOperationsProblemTemplate,
    model::Union{Nothing, AbstractHVDCNetworkModel},
)
    set_hvdc_network_model!(template.network_model, model)
    return
end

"""
Sets the network model in a template.
"""
function set_hvdc_network_model!(
    template::PowerOperationsProblemTemplate,
    model::Type{U},
) where {U <: AbstractHVDCNetworkModel}
    set_hvdc_network_model!(template.network_model, model())
    return
end

"""
Sets the device model in a template using the component type and formulation.
Builds a default DeviceModel
"""
function set_device_model!(
    template::PowerOperationsProblemTemplate,
    component_type::Type{<:PSY.Device},
    formulation::Type{<:AbstractDeviceFormulation},
)
    set_device_model!(template, DeviceModel(component_type, formulation))
    return
end

"""
Sets the device model in a template using a DeviceModel instance.
Routes to devices dictionary.
"""
function set_device_model!(
    template::PowerOperationsProblemTemplate,
    model::DeviceModel{D},
) where {D <: IS.InfrastructureSystemsComponent}
    set_model!(template.devices, model)
    return
end

"""
Sets the device model in a template using a DeviceModel instance.
Specialization for Branch types - routes to branches dictionary.
"""
function set_device_model!(
    template::PowerOperationsProblemTemplate,
    model::DeviceModel{D},
) where {D <: PSY.Branch}
    set_model!(template.branches, model)
    return
end

"""
    set_event_model!(template::PowerOperationsProblemTemplate, event_model)

Attach an outage-event model to the template. At build time the event is validated,
its `attribute_device_map` is populated from the system's supplemental attributes, and
it is distributed to every matching `DeviceModel`.
"""
function IOM.set_event_model!(
    template::PowerOperationsProblemTemplate,
    event_model::IOM.AbstractEventModel,
)
    if any(e -> e === event_model, template.events)
        error("This event model is already attached to the template")
    end
    push!(template.events, event_model)
    return
end

# `IOM._deepcopy_template` already shares the network model's PNM matrices by reference
# across the template/copy boundary because their solver caches hold raw factorization
# handles that error on deepcopy; the matrices are read-only inputs, so sharing them is
# safe. Event models need the same treatment for a different reason: build-time discovery
# (`_build_device_model_events!`) mutates `EventModel.attribute_device_map`, and callers
# inspect that mutation on the exact object they passed to `set_event_model!`. A plain
# `deepcopy` of the template would clone each event model, so the mutation performed on
# the copy used to build the model would be invisible on the caller's original object.
# Null the field before delegating to the generic (PNM-matrix-aware) implementation, then
# restore identity on both sides so discovery writes land on the caller's own objects.
function IOM._deepcopy_template(template::PowerOperationsProblemTemplate)
    events = template.events
    template.events = IOM.AbstractEventModel[]
    template_ = try
        invoke(IOM._deepcopy_template, Tuple{IOM.AbstractProblemTemplate}, template)
    finally
        template.events = events
    end
    template_.events = copy(events)
    return template_
end

"""
Sets the service model in a template using a name and the service type and formulation.
Builds a default ServiceModel with use_service_name set to true.
"""
function set_service_model!(
    template::PowerOperationsProblemTemplate,
    service_name::String,
    service_type::Type{<:PSY.Service},
    formulation::Type{<:AbstractServiceFormulation},
)
    set_service_model!(
        template,
        service_name,
        ServiceModel(service_type, formulation; use_service_name = true),
    )
    return
end

"""
Sets the service model in a template using a ServiceModel instance.
"""
function set_service_model!(
    template::PowerOperationsProblemTemplate,
    service_type::Type{<:PSY.Service},
    formulation::Type{<:AbstractServiceFormulation},
)
    set_service_model!(template, ServiceModel(service_type, formulation))
    return
end

function set_service_model!(
    template::PowerOperationsProblemTemplate,
    service_name::String,
    model::ServiceModel{T, <:AbstractServiceFormulation},
) where {T <: PSY.Service}
    set_model!(template.services, (service_name, Symbol(T)), model)
    return
end

function set_service_model!(
    template::PowerOperationsProblemTemplate,
    model::ServiceModel{<:PSY.Service, <:AbstractServiceFormulation},
)
    set_model!(template.services, model)
    return
end

function _add_contributing_device_by_type!(
    service_model::ServiceModel,
    contributing_device::T,
    incompatible_device_types::Set{DataType},
    modeled_devices::Set{DataType},
) where {T <: PSY.Device}
    !PSY.get_available(contributing_device) && return
    if T ∈ incompatible_device_types || T ∉ modeled_devices
        return
    end
    push!(get!(get_contributing_devices_map(service_model), T, T[]), contributing_device)
    return
end

function _populate_contributing_devices!(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    service_models = get_service_models(template)
    isempty(service_models) && return

    device_models = get_device_models(template)
    branch_models = get_branch_models(template)
    # Type stability: explicitly type the Set to avoid widening to Set{Type}
    modeled_devices = Set{DataType}(get_component_type(m) for m in values(device_models))
    union!(modeled_devices, (get_component_type(m) for m in values(branch_models)))
    incompatible_device_types = get_incompatible_devices(device_models)
    services_mapping = PSY.get_contributing_device_mapping(sys)
    if isempty(keys(services_mapping))
        @warn "The system doesn't include any services. No services will be modeled, consider removing the service models from the template." _group =
            LOG_GROUP_SERVICE_CONSTUCTORS
        empty!(service_models)
        return
    end
    for (service_key, service_model) in service_models
        @debug "Populating service $(service_key)"
        empty!(get_contributing_devices_map(service_model))
        S = get_component_type(service_model)
        service = PSY.get_component(S, sys, get_service_name(service_model))
        if service === nothing
            @info "The data doesn't include services of type $(S) and name $(get_service_name(service_model)), consider changing the service models" _group =
                LOG_GROUP_SERVICE_CONSTUCTORS
            continue
        end
        # Key by the concrete service type. `S` from the model can be a UnionAll
        # (e.g. PSY6 parameterized `ReserveDemandCurve{ReserveUp}` on a unit-system
        # type, leaving a trailing free parameter), but `get_contributing_device_mapping`
        # keys by `typeof(service)`, so match that to avoid a KeyError.
        service_devices_key = (type = typeof(service), name = PSY.get_name(service))
        contributing_devices_ =
            services_mapping[service_devices_key].contributing_devices
        for d in contributing_devices_
            _add_contributing_device_by_type!(
                service_model,
                d,
                incompatible_device_types,
                modeled_devices,
            )
        end
        if isempty(get_contributing_devices_map(service_model))
            error(
                "The contributing devices for service $(PSY.get_name(service)) is empty. Add contributing devices to the service in the data to continue.",
            )
        end
    end
    return
end

function _modify_device_model!(
    devices_template::Dict{Symbol, DeviceModel},
    service_model::ServiceModel{<:PSY.Reserve, <:AbstractReservesFormulation},
    contributing_devices::Vector{<:PSY.Component},
)
    # Type stability: explicitly type the Set to avoid widening
    for dt in Set{DataType}(typeof.(contributing_devices))
        for device_model in values(devices_template)
            # add message here when it exists
            get_component_type(device_model) != dt && continue
            service_model in device_model.services && continue
            # type instability: pushing to vector of abstract type
            push!(device_model.services, service_model)
        end
    end

    return
end

function _modify_device_model!(
    ::Dict{Symbol, DeviceModel},
    ::ServiceModel{<:PSY.ReserveNonSpinning, <:AbstractReservesFormulation},
    ::Vector{<:PSY.Component},
)
    return
end

function _modify_device_model!(
    ::Dict{Symbol, DeviceModel},
    ::ServiceModel{PSY.TransmissionInterface, ConstantMaxInterfaceFlow},
    ::Vector,
)
    return
end

function _modify_device_model!(
    ::Dict{Symbol, DeviceModel},
    ::ServiceModel{PSY.TransmissionInterface, VariableMaxInterfaceFlow},
    ::Vector,
)
    return
end

function _add_services_to_device_model!(template::PowerOperationsProblemTemplate)
    service_models = get_service_models(template)
    devices_template = get_device_models(template)
    for (service_key, service_model) in service_models
        S = get_component_type(service_model)
        (S <: PSY.AGC || S <: PSY.ConstantReserveGroup) && continue
        contributing_devices = get_contributing_devices(service_model)
        isempty(contributing_devices) && continue
        _modify_device_model!(devices_template, service_model, contributing_devices)
    end
    return
end

function _populate_aggregated_service_model!(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    services_template = get_service_models(template)
    for (key, service_model) in services_template
        attributes = get_attributes(service_model)
        use_slacks = service_model.use_slacks
        duals = service_model.duals
        if pop!(attributes, "aggregated_service_model", false)
            delete!(services_template, key)
            D = get_component_type(service_model)
            B = get_formulation(service_model)
            for service in get_available_components(service_model, sys)
                new_key = (PSY.get_name(service), Symbol(D))
                if !haskey(services_template, new_key)
                    template.services[new_key] =
                        ServiceModel(
                            D,
                            B,
                            PSY.get_name(service);
                            use_slacks = use_slacks,
                            duals = duals,
                            attributes = attributes,
                        )
                else
                    error("Key $new_key already assigned in ServiceModel")
                end
            end
        end
    end
    return
end

function finalize_template!(template::PowerOperationsProblemTemplate, sys::PSY.System)
    _populate_aggregated_service_model!(template, sys)
    _populate_contributing_devices!(template, sys)
    _add_services_to_device_model!(template)
    return
end
