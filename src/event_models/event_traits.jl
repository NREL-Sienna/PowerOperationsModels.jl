#! format: off
get_parameter_multiplier(::EventParameter, ::PSY.Device, ::EventModel) = 1.0
get_initial_parameter_value(::ActivePowerOffsetParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::ReactivePowerOffsetParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::AvailableStatusChangeCountdownParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::AvailableStatusParameter, ::PSY.Device, ::EventModel) = 1.0

"""
Whether devices of this type support outage events (`EventModel`). This is a device-type
capability trait for time-series outage events — distinct from `supports_outages`, the
formulation trait for security-constrained (MODF) branch contingencies.
"""
supports_events(::Type{T}) where {T <: PSY.Component} = false
supports_events(::Type{T}) where {T <: PSY.ThermalStandard} = true
supports_events(::Type{T}) where {T <: PSY.RenewableGen} = true
supports_events(::Type{T}) where {T <: PSY.ElectricLoad} = true
supports_events(::Type{T}) where {T <: PSY.Storage} = true
supports_events(::Type{T}) where {T <: PSY.HydroGen} = true
#! format: on
