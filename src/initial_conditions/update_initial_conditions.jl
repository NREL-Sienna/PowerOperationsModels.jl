#################################################################################
# Device-specific update_initial_conditions! implementations
# These extend the stub from IOM for emulation model simulation
#################################################################################

# InitialTimeDurationOn updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{InitialTimeDurationOn, Nothing},
                InitialCondition{InitialTimeDurationOn, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{InitialTimeDurationOn, Nothing},
                InitialCondition{InitialTimeDurationOn, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, TimeDurationOn(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

# InitialTimeDurationOff updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{InitialTimeDurationOff, Nothing},
                InitialCondition{InitialTimeDurationOff, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{InitialTimeDurationOff, Nothing},
                InitialCondition{InitialTimeDurationOff, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, TimeDurationOff(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

# DevicePower updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{DevicePower, Nothing},
                InitialCondition{DevicePower, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{DevicePower, Nothing},
                InitialCondition{DevicePower, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, ActivePowerVariable(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

# DeviceStatus updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{DeviceStatus, Nothing},
                InitialCondition{DeviceStatus, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{DeviceStatus, Nothing},
                InitialCondition{DeviceStatus, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, OnVariable(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

# DeviceAboveMinPower updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{DeviceAboveMinPower, Nothing},
                InitialCondition{DeviceAboveMinPower, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{DeviceAboveMinPower, Nothing},
                InitialCondition{DeviceAboveMinPower, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, PowerAboveMinimumVariable(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

# InitialEnergyLevel updates
function update_initial_conditions!(
    ics::T,
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {
    T <: Union{
        Vector{
            Union{
                InitialCondition{InitialEnergyLevel, Nothing},
                InitialCondition{InitialEnergyLevel, Float64},
            },
        },
        Vector{
            Union{
                InitialCondition{InitialEnergyLevel, Nothing},
                InitialCondition{InitialEnergyLevel, JuMP.VariableRef},
            },
        },
    },
}
    for ic in ics
        var_val = get_value(store, EnergyVariable(), get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end
