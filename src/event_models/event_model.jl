"""
    EventKey(::Type{T}, ::Type{U})

Key identifying an event of contingency type `T` applied to devices of concrete type `U`.
Used as the key of the `DeviceModel.events` dict. Errors if `U` is abstract.
"""
struct EventKey{T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} <:
       IOM.AbstractEventKey
    meta::String
end

function EventKey(
    ::Type{T},
    ::Type{U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}}
    if isabstracttype(U)
        error("Type $U can't be abstract")
    end
    return EventKey{T, U}("")
end

IOM.get_entry_type(
    ::EventKey{T, U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} = T
IOM.get_component_type(
    ::EventKey{T, U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} = U

"""
Abstract type for the condition that triggers an event. POM stores conditions as data;
evaluating them requires a simulation runtime and happens outside this package.
"""
abstract type AbstractEventCondition end

"""
    ContinuousCondition()

Event condition that is triggered at all timesteps.
"""
struct ContinuousCondition <: AbstractEventCondition end

"""
    PresetTimeCondition(time_stamps::Vector{Dates.DateTime})

Event condition that is triggered at pre-determined times.
"""
struct PresetTimeCondition <: AbstractEventCondition
    time_stamps::Vector{Dates.DateTime}
end

"""
Return the time stamps at which `c` is triggered.
"""
get_time_stamps(c::PresetTimeCondition) = c.time_stamps

"""
    StateVariableValueCondition(variable_type, device_type, device_name, value)

Event condition triggered when the monitored variable equals `value` (p.u.).
"""
struct StateVariableValueCondition <: AbstractEventCondition
    variable_type::VariableType
    device_type::Type{<:PSY.Device}
    device_name::String
    value::Float64
end

get_variable_type(c::StateVariableValueCondition) = c.variable_type
get_device_type(c::StateVariableValueCondition) = c.device_type
get_device_name(c::StateVariableValueCondition) = c.device_name
# Qualified: `get_value` is IOM's generic (`get_value(::InitialCondition)`); a bare
# definition here would silently create a separate local `get_value` in POM's namespace
# (since it was only ever `using`'d, not `import`ed) and shadow IOM's method for every
# other unqualified `get_value(ic)` call across the package (storage, hybrid, thermal
# generation, AGC initial-condition consumers).
IOM.get_value(c::StateVariableValueCondition) = c.value

"""
    DiscreteEventCondition(condition_function::Function)

Event condition driven by a user-defined function evaluated by the simulation runtime.
"""
struct DiscreteEventCondition <: AbstractEventCondition
    condition_function::Function
end

get_condition_function(c::DiscreteEventCondition) = c.condition_function

"""
    EventModel(contingency_type, condition; timeseries_mapping, attributes)

Container binding a `PSY.Contingency` supplemental-attribute type to a trigger condition
and time-series mapping. Attach to a template with
`set_event_model!(template, event_model)`; build-time discovery populates
`attribute_device_map` (outage attribute id → device type → device names) and
distributes the event to the matching `DeviceModel`s.
"""
mutable struct EventModel{D <: PSY.Contingency, B <: AbstractEventCondition} <:
               IOM.AbstractEventModel
    condition::B
    timeseries_mapping::Dict{Symbol, Union{String, Nothing}}
    attribute_device_map::Dict{Int, Dict{DataType, Set{String}}}
    attributes::Dict{String, Any}

    function EventModel(
        contingency_type::Type{D},
        condition::B;
        timeseries_mapping = get_empty_timeseries_mapping(contingency_type),
        attributes = Dict{String, Any}(),
    ) where {D <: PSY.Contingency, B <: AbstractEventCondition}
        new{D, B}(
            condition,
            timeseries_mapping,
            Dict{Int, Dict{DataType, Set{String}}}(),
            attributes,
        )
    end
end

"""
Reserved time-series mapping keys for a contingency type. `:outage_status` is required
for `PSY.FixedForcedOutage`.
"""
function get_empty_timeseries_mapping(::Type{PSY.FixedForcedOutage})
    return Dict{Symbol, Union{String, Nothing}}(:outage_status => nothing)
end

function get_empty_timeseries_mapping(::Type{PSY.GeometricDistributionForcedOutage})
    return Dict{Symbol, Union{String, Nothing}}(
        :mean_time_to_recovery => nothing,
        :outage_transition_probability => nothing,
    )
end

"""
Return the `PSY.Contingency` subtype that `e` models.
"""
get_event_type(
    ::EventModel{D, B},
) where {D <: PSY.Contingency, B <: AbstractEventCondition} = D

"""
Return the trigger condition attached to `e`.
"""
get_event_condition(
    e::EventModel{D, B},
) where {D <: PSY.Contingency, B <: AbstractEventCondition} = e.condition

"""
Return `e`'s outage attribute id → device type → device names map, populated by
build-time discovery.
"""
get_attribute_device_map(e::EventModel) = e.attribute_device_map
