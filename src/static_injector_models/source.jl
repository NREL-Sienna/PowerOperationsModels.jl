#! format: off

requires_initialization(::ImportExportSourceModel) = false


get_variable_multiplier(::Type{ActivePowerOutVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = 1.0
get_variable_multiplier(::Type{ActivePowerInVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = -1.0
get_variable_multiplier(::Type{ReactivePowerVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = 1.0
############## ActivePowerVariables, Source ####################
get_variable_binary(::Type{ActivePowerInVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = false
get_variable_binary(::Type{ActivePowerOutVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = false
get_variable_lower_bound(::Type{ActivePowerInVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = 0.0
get_variable_lower_bound(::Type{ActivePowerOutVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = 0.0
get_variable_upper_bound(::Type{ActivePowerInVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = -PSY.get_active_power_limits(d, PSY.SU).min
get_variable_upper_bound(::Type{ActivePowerOutVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max

############## ReactivePowerVariable, Source ####################
get_variable_binary(::Type{ReactivePowerVariable}, ::Type{<:PSY.Source}, ::Type{<:AbstractSourceFormulation}) = false
get_variable_lower_bound(::Type{ReactivePowerVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).min
get_variable_upper_bound(::Type{ReactivePowerVariable}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).max

get_multiplier_value(::Type{ActivePowerTimeSeriesParameter}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_multiplier_value(::Type{ActivePowerOutTimeSeriesParameter}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_multiplier_value(::Type{ActivePowerInTimeSeriesParameter}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = PSY.get_active_power_limits(d, PSY.SU).max
get_multiplier_value(::Type{ActivePowerTimeSeriesParameter}, d::PSY.Source, ::Type{FixedOutput}) = PSY.get_active_power_limits(d, PSY.SU).max
get_multiplier_value(::Type{ActivePowerOutTimeSeriesParameter}, d::PSY.Source, ::Type{FixedOutput}) = PSY.get_active_power_limits(d, PSY.SU).max
get_multiplier_value(::Type{ActivePowerInTimeSeriesParameter}, d::PSY.Source, ::Type{FixedOutput}) = PSY.get_active_power_limits(d, PSY.SU).min
# This additional method definition is used to avoid ambiguity with the method defined in default_interface_methods.jl
get_multiplier_value(::Type{<:AbstractPiecewiseLinearBreakpointParameter}, d::PSY.Source, ::Type{<:AbstractSourceFormulation}) = 1.0

############## ReservationVariable, Source ####################
get_variable_binary(::Type{ReservationVariable}, ::Type{<:PSY.Source}, ::Type{ImportExportSourceModel}) = true


#! format: on
# FixedOutput is entirely time-series driven, so it defaults to the in/out series.
# Every other source formulation treats time series as opt-in: a default here flips
# the constructors' `haskey` gates on and hard-errors any system without the series.
function get_default_time_series_names(
    ::Type{U},
    ::Type{FixedOutput},
) where {U <: PSY.Source}
    return Dict{Type{<:TimeSeriesParameter}, String}(
        ActivePowerOutTimeSeriesParameter => "max_active_power_out",
        ActivePowerInTimeSeriesParameter => "max_active_power_in",
    )
end

function get_default_time_series_names(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.Source, V <: AbstractSourceFormulation}
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
) where {U <: PSY.Source, V <: Union{FixedOutput, AbstractSourceFormulation}}
    return Dict{String, Any}(
        "reservation" => true,
    )
end

function get_min_max_limits(
    device::PSY.Source,
    ::Type{ActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractSourceFormulation},
)
    return PSY.get_active_power_limits(device, PSY.SU)
end

function get_min_max_limits(
    device::PSY.Source,
    ::Type{InputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractSourceFormulation},
)
    return PSY.get_active_power_limits(device, PSY.SU)  # TODO do we need a new field in PSY for this -- input active power limits?
end

function get_min_max_limits(
    device::PSY.Source,
    ::Type{ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractSourceFormulation},
)
    return PSY.get_reactive_power_limits(device, PSY.SU)
end

##### Constraints ######

function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:PowerVariableLimitsConstraint},
    U::Type{<:Union{VariableType, ExpressionType}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.Source,
    W <: AbstractSourceFormulation,
    X <: AbstractNetworkModel,
}
    if get_attribute(model, "reservation")
        add_reserve_range_constraints!(container, T, U, devices, model, X)
    else
        add_range_constraints!(container, T, U, devices, model, X)
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{ImportExportBudgetConstraint},
    devices::IS.FlattenIteratorWrapper{U},
    model::DeviceModel{U, V},
    network_model::NetworkModel{X},
) where {
    U <: PSY.Source,
    V <: AbstractSourceFormulation,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    resolution_in_hours = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    hours_in_horizon = length(time_steps) * resolution_in_hours
    p_out = get_variable(container, ActivePowerOutVariable, U)
    p_in = get_variable(container, ActivePowerInVariable, U)
    names = PSY.get_name.(devices)
    constraint_export =
        add_constraints_container!(container, ImportExportBudgetConstraint,
            U,
            names,
            ["horizon"];
            meta = "export",
        )
    constraint_import = add_constraints_container!(container, ImportExportBudgetConstraint,
        U,
        names,
        ["horizon"];
        meta = "import",
    )

    # Limits are named from the system's perspective: importing means the source injects
    # into the system (ActivePowerOutVariable); exporting means it absorbs
    # (ActivePowerInVariable).
    for d in devices
        name = PSY.get_name(d)
        op_cost = PSY.get_operation_cost(d)
        week_import_limit = PSY.get_energy_import_weekly_limit(op_cost)
        week_export_limit = PSY.get_energy_export_weekly_limit(op_cost)
        constraint_import[name, "horizon"] = JuMP.@constraint(
            get_jump_model(container),
            resolution_in_hours * sum(p_out[name, t] for t in time_steps) <=
            week_import_limit * (hours_in_horizon / HOURS_IN_WEEK)
        )
        constraint_export[name, "horizon"] = JuMP.@constraint(
            get_jump_model(container),
            resolution_in_hours * sum(p_in[name, t] for t in time_steps) <=
            week_export_limit * (hours_in_horizon / HOURS_IN_WEEK)
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActivePowerOutVariableTimeSeriesLimitsConstraint},
    U::Type{<:Union{ActivePowerOutVariable, ActivePowerRangeExpressionUB}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.Source,
    W <: AbstractSourceFormulation,
    X <: AbstractNetworkModel,
}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerOutVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerOutTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ActivePowerInVariableTimeSeriesLimitsConstraint},
    U::Type{<:Union{ActivePowerInVariable, ActivePowerRangeExpressionUB}},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.Source,
    W <: AbstractSourceFormulation,
    X <: AbstractNetworkModel,
}
    add_parameterized_upper_bound_range_constraints(
        container,
        ActivePowerInVariableTimeSeriesLimitsConstraint,
        U,
        ActivePowerInTimeSeriesParameter,
        devices,
        model,
        X,
    )
    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    ::DeviceModel{T, U},
    ::Type{V},
) where {T <: PSY.Source, U <: AbstractSourceFormulation, V <: AbstractNetworkModel}
    add_variable_cost!(container, ActivePowerOutVariable, devices, U)
    add_variable_cost!(container, ActivePowerInVariable, devices, U)
    return
end

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{PSY.Source, T},
) where {T <: AbstractSourceFormulation} = DeviceModel(PSY.Source, T)
