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
    function PowerOperationsProblemTemplate(
        network::NetworkModel{T},
    ) where {T <: AbstractNetworkModel}
        new(
            network,
            DevicesModelContainer(),
            BranchModelContainer(),
            ServicesModelContainer(),
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
) where {T <: PSY.Service}
    if haskey(template.services, Symbol(T))
        return template.services[Symbol(T)]
    else
        error("Service $T not present in the template")
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
Sets the service model in a template using the service type and formulation.
One `ServiceModel` covers every service of its type in the system.
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
    model::ServiceModel{<:PSY.Service, <:AbstractServiceFormulation},
)
    set_model!(template.services, model)
    return
end

function _add_contributing_device_by_type!(
    service_model::ServiceModel,
    service_name::String,
    contributing_device::T,
    incompatible_device_types::Set{DataType},
    modeled_devices::Set{DataType},
) where {T <: PSY.Device}
    !PSY.get_available(contributing_device) && return
    if T ∈ incompatible_device_types || T ∉ modeled_devices
        return
    end
    # Lazy `get!(f, dict, key)` defaults: the 3-arg `get!(dict, key, default)` builds
    # `default` eagerly on every call, allocating a throwaway map/vector even on the common
    # hit path (a service/type already present after its first device). Passing the type as `f`
    # uses it as a zero-arg constructor - lazy (runs only on a miss), no anonymous closure. The
    # map and vector here are inserted and then mutated (the `push!`), so - unlike the read-only
    # accessor - they must be fresh instances and cannot share IOM's empty-map const.
    inner = get!(
        Dict{DataType, Vector{<:IS.InfrastructureSystemsComponent}},
        get_contributing_devices_map(service_model),
        service_name,
    )
    # TODO(services stability, deferred B2): the map value is typed
    # `Vector{<:IS.InfrastructureSystemsComponent}` (abstract element) in the IOM
    # `contributing_devices_map` field, so this `push!` dynamic-dispatches. The `Vector{T}` default
    # does build a concrete `Vector{T}` at runtime, but the declared field type widens what the
    # compiler sees. Rooted in the IOM struct (Comment A); build-time-only.
    # `get!(Vector{T}, ...)` uses the type as the zero-arg constructor - lazy (runs only on a
    # miss) with no anonymous closure.
    push!(get!(Vector{T}, inner, T), contributing_device)
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
    # One model per service type; fill the per-service nested map for every available
    # service of each type. `get_available_components` already restricts this loop to
    # available services, and `_add_contributing_device_by_type!` records only available,
    # modeled, compatible devices (PSY's mapping includes unavailable ones). After
    # populating each reserve we require at least one such device: a modeled reserve with no
    # available provider can never meet its requirement - it would silently force slacks or
    # make the model infeasible - so error loudly and name it rather than dropping it.
    # A modeled TransmissionInterface likewise needs at least one available contributing branch,
    # or its flow limit is meaningless. ConstantReserveGroup is exempt (see the check below).
    for (service_key, service_model) in service_models
        @debug "Populating service model $(service_key)"
        empty!(get_contributing_devices_map(service_model))
        service_type = get_component_type(service_model)
        for service in get_available_components(service_model, sys)
            service_name = PSY.get_name(service)
            # Key by the concrete service type. The model type can be a UnionAll
            # (e.g. PSY6 parameterized `ReserveDemandCurve{ReserveUp}` on a unit-system
            # type), but `get_contributing_device_mapping` keys by `typeof(service)`.
            service_devices_key = (type = typeof(service), name = service_name)
            if haskey(services_mapping, service_devices_key)
                for d in services_mapping[service_devices_key].contributing_devices
                    _add_contributing_device_by_type!(
                        service_model,
                        service_name,
                        d,
                        incompatible_device_types,
                        modeled_devices,
                    )
                end
            end
            # Exempt ConstantReserveGroup: a GroupReserve aggregates other services, so its
            # contributing-device map is empty by design; without this the error would fire on
            # every group reserve (the bug that previously made ConstantReserveGroup unbuildable).
            # Reserves and transmission interfaces DO draw on devices/branches, so an empty map
            # there is a real misconfiguration. AGC is not modeled in POM, so it never reaches here.
            if !(service_type <: PSY.ConstantReserveGroup) &&
               isempty(get_contributing_devices_map(service_model, service_name))
                error(
                    "Service \"$(service_name)\" of type $(typeof(service)) has no available contributing devices/branches. Assign available contributing devices/branches to it in the system data, or remove its service model from the template.",
                )
            end
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
            # TODO(services stability, deferred B2): `device_model.services` is
            # `Vector{ServiceModel}` (abstract element), so this `push!` and any later iteration of
            # it dynamic-dispatch. The root is the IOM `DeviceModel.services` field type (the POM
            # twin of IOM review Comment A); it cannot be fixed here and needs an IOM struct-typing
            # pass. Build-time-only. See .claude/plans/service-refactor-stability.md.
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

function finalize_template!(template::PowerOperationsProblemTemplate, sys::PSY.System)
    _populate_contributing_devices!(template, sys)
    _add_services_to_device_model!(template)
    return
end
