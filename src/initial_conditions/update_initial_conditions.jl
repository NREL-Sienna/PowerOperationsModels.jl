#################################################################################
# IC type -> variable/aux-variable type mapping (dispatch-based)
#################################################################################

_ic_variable_type(::Type{DevicePower}) = ActivePowerVariable()
_ic_variable_type(::Type{DeviceStatus}) = OnVariable()
_ic_variable_type(::Type{DeviceAboveMinPower}) = PowerAboveMinimumVariable()
_ic_variable_type(::Type{InitialTimeDurationOn}) = TimeDurationOn()
_ic_variable_type(::Type{InitialTimeDurationOff}) = TimeDurationOff()
_ic_variable_type(::Type{InitialEnergyLevel}) = EnergyVariable()

# Dispatch to the right container getter based on variable vs aux variable type
# FIXME we should add something like this to the API.
_get_from_container(source, var_type::VariableType, comp_type) =
    get_variable(source, var_type, comp_type)
_get_from_container(source, var_type::AuxVariableType, comp_type) =
    get_aux_variable(source, var_type, comp_type)

#################################################################################
# Generic update from EmulationModelStore
#################################################################################

function update_initial_conditions!(
    ics::Vector{<:InitialCondition{T}},
    store::EmulationModelStore,
    ::Dates.Millisecond,
) where {T <: InitialConditionType}
    var_type = _ic_variable_type(T)
    for ic in ics
        var_val = get_value(store, var_type, get_component_type(ic))
        set_ic_quantity!(ic, get_last_recorded_value(var_val)[get_component_name(ic)])
    end
    return
end

#################################################################################
# Generic update from a solved OptimizationContainer
#################################################################################

function update_initial_conditions!(
    ics::Vector{<:InitialCondition{T}},
    source::OptimizationContainer,
) where {T <: InitialConditionType}
    var_type = _ic_variable_type(T)
    t_last = last(get_time_steps(source))
    for ic in ics
        var = _get_from_container(source, var_type, get_component_type(ic))
        set_ic_quantity!(ic, jump_value(var[get_component_name(ic), t_last]))
    end
    return
end

"""
Transfer initial conditions from a solved source model to a target model.

Reads the last-timestep variable values from the source and sets them as
initial conditions on the target. Uses the IC-type-to-variable-type mapping
to determine which variable to read for each IC.

PSI handles this same thing by adding another layer of abstractions, using `SimulationState`
and reading/writing to `ModelStore`. But it's useful to be able to do the same thing
here in POM without those abstractions, for testing purposes.

!!! warning
    This is a naive transfer: it copies last-timestep variable values directly as ICs,
    without consideration of different time resolutions between source and target,
    pre-existing IC values on the target, or uptime/downtime duration scaling.
"""
function transfer_initial_conditions!(
    target::OperationModel,
    source::OperationModel,
)
    source_container = get_optimization_container(source)
    target_container = get_optimization_container(target)
    for key in keys(get_initial_conditions(target_container))
        ics = get_initial_condition(target_container, key)
        update_initial_conditions!(ics, source_container)
    end
    return
end
