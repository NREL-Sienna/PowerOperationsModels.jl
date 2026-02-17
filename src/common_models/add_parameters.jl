#################################################################################
# add_parameters! implementations
#
# These provide the main `add_parameters!` dispatchers and internal helpers
# for adding parameter containers to the OptimizationContainer.
# Moved from PowerSimulations.jl/src/parameters/add_parameters.jl during the
# three-tier split.
#
# Functions that depend on feedforward or contingency infrastructure are
# intentionally omitted — they will be added when that code is migrated.
#################################################################################

#################################################################################
# Main dispatchers
#################################################################################

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, D)
        return
    end
    _add_parameters!(container, T(), devices, model)
    return
end

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    service::U,
    model::ServiceModel{U, V},
) where {T <: TimeSeriesParameter, U <: PSY.Service, V <: AbstractServiceFormulation}
    if get_rebuild_model(get_settings(container)) &&
       has_container_key(container, T, U, PSY.get_name(service))
        return
    end
    _add_parameters!(container, T(), service, model)
    return
end

#################################################################################
# _add_parameters! for TimeSeriesParameter → delegates to _add_time_series_parameters!
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    param::T,
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: TimeSeriesParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    _add_time_series_parameters!(container, param, devices, model)
    return
end

#################################################################################
# Helpers for _add_time_series_parameters!
#################################################################################

function _check_dynamic_branch_rating_ts(
    ts::AbstractArray,
    ::T,
    device::PSY.Device,
    model::DeviceModel{D, W},
) where {D <: PSY.Component, T <: TimeSeriesParameter, W <: AbstractDeviceFormulation}
    if !(T <: AbstractDynamicBranchRatingTimeSeriesParameter)
        return
    end

    rating = PSY.get_rating(device)
    if (T <: PostContingencyDynamicBranchRatingTimeSeriesParameter)
        if !(PSY.get_rating_b(device) === nothing)
            rating = PSY.get_rating_b(device)
        else
            @warn "Device $(typeof(device)) '$(PSY.get_name(device))' has Parameter $T but it has no static 'rating_b' defined."
        end
    end

    multiplier = get_multiplier_value(T(), device, W())
    if !all(x -> x >= rating, multiplier * ts)
        @warn "There are values of Parameter $T associated with $(typeof(device)) '$(PSY.get_name(device))' lower than the device static rating $(rating)."
    end
    return
end

# Extends `size` to tuples, treating them like scalars
_size_wrapper(elem) = size(elem)
_size_wrapper(::Tuple) = ()

#################################################################################
# _add_time_series_parameters! — main workhorse
#################################################################################

function _add_time_series_parameters!(
    container::OptimizationContainer,
    param::T,
    devices,
    model::DeviceModel{D, W},
) where {D <: PSY.Component, T <: TimeSeriesParameter, W <: AbstractDeviceFormulation}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end

    time_steps = get_time_steps(container)
    ts_name = _get_time_series_name(T(), first(devices), model)

    device_names = String[]
    devices_with_time_series = D[]
    initial_values = Dict{String, AbstractArray}()

    @debug "adding" T D ts_name ts_type _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER

    for device::D in devices
        if !PSY.has_time_series(device, ts_type, ts_name)
            @info "Time series $(ts_type):$(ts_name) for $D, $(PSY.get_name(device)) not found skipping parameter addition."
            continue
        end
        push!(device_names, PSY.get_name(device))
        push!(devices_with_time_series, device)
        ts_uuid = string(IS.get_time_series_uuid(ts_type, device, ts_name))
        if !(ts_uuid in keys(initial_values))
            initial_values[ts_uuid] =
                IOM.get_time_series_initial_values!(container, ts_type, device, ts_name)
            _check_dynamic_branch_rating_ts(initial_values[ts_uuid], param, device, model)
        end
    end

    if isempty(device_names)
        error(
            "No devices with time series $ts_name found for $D devices. Check DeviceModel time_series_names field.",
        )
    end

    additional_axes =
        calc_additional_axes(container, param, devices_with_time_series, model)
    param_container = add_param_container!(
        container,
        param,
        D,
        ts_type,
        ts_name,
        collect(keys(initial_values)),
        device_names,
        additional_axes,
        time_steps,
    )
    IOM.set_subsystem!(IOM.get_attributes(param_container), IOM.get_subsystem(model))

    jump_model = get_jump_model(container)
    param_instance = T()
    for (ts_uuid, raw_ts_vals) in initial_values
        ts_vals = _unwrap_for_param.(Ref(param_instance), raw_ts_vals, Ref(additional_axes))
        @assert all(_size_wrapper.(ts_vals) .== Ref(length.(additional_axes)))

        for step in time_steps
            IOM.set_parameter!(param_container, jump_model, ts_vals[step], ts_uuid, step)
        end
    end

    for device in devices_with_time_series
        multiplier = get_multiplier_value(T(), device, W())
        device_name = PSY.get_name(device)
        for step in time_steps
            IOM.set_multiplier!(param_container, multiplier, device_name, step)
        end
        IOM.add_component_name!(
            IOM.get_attributes(param_container),
            device_name,
            string(IS.get_time_series_uuid(ts_type, device, ts_name)),
        )
    end
    return
end

#################################################################################
# _get_time_series_name — layer of indirection for time series name lookup
#################################################################################

_get_time_series_name(::T, ::PSY.Component, model::DeviceModel) where {T <: ParameterType} =
    get_time_series_names(model)[T]

_get_time_series_name(::StartupCostParameter, device::PSY.Component, ::DeviceModel) =
    IS.get_name(PSY.get_start_up(PSY.get_operation_cost(device)))

_get_time_series_name(::ShutdownCostParameter, device::PSY.Component, ::DeviceModel) =
    IS.get_name(PSY.get_shut_down(PSY.get_operation_cost(device)))

_get_time_series_name(
    ::IncrementalCostAtMinParameter,
    device::PSY.Device,
    ::DeviceModel,
) =
    IS.get_name(PSY.get_incremental_initial_input(PSY.get_operation_cost(device)))

_get_time_series_name(
    ::DecrementalCostAtMinParameter,
    device::PSY.Device,
    ::DeviceModel,
) =
    IS.get_name(PSY.get_decremental_initial_input(PSY.get_operation_cost(device)))

#################################################################################
# _get_expected_time_series_eltype — for ObjectiveFunctionParameter
#################################################################################

_get_expected_time_series_eltype(::T) where {T <: ParameterType} = Float64
_get_expected_time_series_eltype(::StartupCostParameter) = NTuple{3, Float64}

#################################################################################
# _param_to_vars — lookup: ObjectiveFunctionParameter → variable types
#################################################################################

_param_to_vars(::FuelCostParameter, ::AbstractDeviceFormulation) = (ActivePowerVariable,)
_param_to_vars(::StartupCostParameter, ::AbstractThermalFormulation) = (StartVariable,)
_param_to_vars(::StartupCostParameter, ::ThermalMultiStartUnitCommitment) =
    MULTI_START_VARIABLES
_param_to_vars(::ShutdownCostParameter, ::AbstractThermalFormulation) = (StopVariable,)
_param_to_vars(::AbstractCostAtMinParameter, ::AbstractDeviceFormulation) = (OnVariable,)
_param_to_vars(
    ::Union{
        IncrementalPiecewiseLinearSlopeParameter,
        IncrementalPiecewiseLinearBreakpointParameter,
    },
    ::AbstractDeviceFormulation,
) =
    (PiecewiseLinearBlockIncrementalOffer,)
_param_to_vars(
    ::Union{
        DecrementalPiecewiseLinearSlopeParameter,
        DecrementalPiecewiseLinearBreakpointParameter,
    },
    ::AbstractDeviceFormulation,
) =
    (PiecewiseLinearBlockDecrementalOffer,)

#################################################################################
# calc_additional_axes — default implementations (no additional axes)
#################################################################################

calc_additional_axes(
    ::OptimizationContainer,
    ::T,
    ::U,
    ::DeviceModel{D, W},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component} = ()

calc_additional_axes(
    ::OptimizationContainer,
    ::T,
    ::U,
    ::ServiceModel{D, W},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractServiceFormulation,
} where {D <: PSY.Service} = ()

#################################################################################
# _unwrap_for_param — default implementation (identity)
#################################################################################

_unwrap_for_param(::ParameterType, ts_elem, expected_axs) = ts_elem

#################################################################################
# Piecewise linear parameter helpers
# NOTE: _unwrap_for_param overloads, get_max_tranches, make_tranche_axis, and
# lookup_additional_axes belong in PSI (multi-timestep update path), not POM.
#################################################################################

#################################################################################
# _add_parameters! for ObjectiveFunctionParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    param::T,
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: ObjectiveFunctionParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error(
            "add_parameters! for ObjectiveFunctionParameter is not compatible with $ts_type",
        )
    end
    time_steps = get_time_steps(container)

    ts_names = String[]
    device_names = String[]
    active_devices = D[]
    for device in devices
        ts_name = _get_time_series_name(T(), device, model)
        if PSY.has_time_series(device, ts_type, ts_name)
            push!(ts_names, ts_name)
            push!(device_names, PSY.get_name(device))
            push!(active_devices, device)
        else
            @debug "Skipped time series for $D, $(PSY.get_name(device))"
        end
    end
    if isempty(active_devices)
        return
    end
    jump_model = get_jump_model(container)

    additional_axes = calc_additional_axes(container, param, active_devices, model)
    param_container = add_param_container!(
        container,
        param,
        D,
        _param_to_vars(T(), W()),
        SOSStatusVariable.NO_VARIABLE,
        false,
        _get_expected_time_series_eltype(T()),
        device_names,
        additional_axes...,
        time_steps,
    )

    param_instance = T()
    for (ts_name, device_name, device) in zip(ts_names, device_names, active_devices)
        raw_ts_vals =
            IOM.get_time_series_initial_values!(container, ts_type, device, ts_name)
        ts_vals = _unwrap_for_param.(Ref(param_instance), raw_ts_vals, Ref(additional_axes))
        @assert all(_size_wrapper.(ts_vals) .== Ref(length.(additional_axes)))
        for step in time_steps
            IOM.set_parameter!(
                param_container,
                jump_model,
                ts_vals[step],
                device_name,
                step,
            )
            IOM.set_multiplier!(
                param_container,
                get_multiplier_value(T(), device, W()),
                device_name,
                step,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for ServiceModel TimeSeriesParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    service::U,
    model::ServiceModel{U, V},
) where {T <: TimeSeriesParameter, U <: PSY.Service, V <: AbstractServiceFormulation}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end
    ts_name = get_time_series_names(model)[T]
    time_steps = get_time_steps(container)
    name = PSY.get_name(service)
    ts_uuid = string(IS.get_time_series_uuid(ts_type, service, ts_name))
    @debug "adding" T U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    additional_axes = calc_additional_axes(container, T(), [service], model)
    parameter_container = add_param_container!(
        container,
        T(),
        U,
        ts_type,
        ts_name,
        [ts_uuid],
        [name],
        additional_axes,
        time_steps;
        meta = name,
    )

    IOM.set_subsystem!(IOM.get_attributes(parameter_container), IOM.get_subsystem(model))
    jump_model = get_jump_model(container)
    ts_vector = IOM.get_time_series(container, service, T(), name)
    multiplier = get_multiplier_value(T(), service, V())
    for t in time_steps
        IOM.set_multiplier!(parameter_container, multiplier, name, t)
        IOM.set_parameter!(parameter_container, jump_model, ts_vector[t], ts_uuid, t)
    end
    IOM.add_component_name!(IOM.get_attributes(parameter_container), name, ts_uuid)
    return
end

#################################################################################
# _add_parameters! for VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::VariableKey{U, D},
    model::DeviceModel{D, W},
    devices::V,
) where {
    T <: VariableValueParameter,
    U <: VariableType,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(container, T(), D, key, names, time_steps)
    jump_model = get_jump_model(container)
    for d in devices
        name = PSY.get_name(d)
        if get_variable_warm_start_value(U(), d, W()) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U(), d, W())
        end
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                inital_parameter_value,
                name,
                t,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for OnStatusParameter (ThermalGen-specific)
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::VariableKey{U, D},
    model::DeviceModel{D, W},
    devices::V,
) where {
    T <: OnStatusParameter,
    U <: OnVariable,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractThermalFormulation,
} where {D <: PSY.ThermalGen}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices if !PSY.get_must_run(device)]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(container, T(), D, key, names, time_steps)
    jump_model = get_jump_model(container)
    for d in devices
        if PSY.get_must_run(d)
            continue
        end
        name = PSY.get_name(d)
        if get_variable_warm_start_value(U(), d, W()) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U(), d, W())
        end
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                inital_parameter_value,
                name,
                t,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for FixValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::VariableKey{U, D},
    model::DeviceModel{D, W},
    devices::V,
) where {
    T <: FixValueParameter,
    U <: VariableType,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices]
    time_steps = get_time_steps(container)
    parameter_container =
        add_param_container!(container, T(), D, key, names, time_steps; meta = "$U")
    jump_model = get_jump_model(container)
    for d in devices
        name = PSY.get_name(d)
        if get_variable_warm_start_value(U(), d, W()) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U(), d, W())
        end
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                inital_parameter_value,
                name,
                t,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for AuxVarKey VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::AuxVarKey{U, D},
    model::DeviceModel{D, W},
    devices::V,
) where {
    T <: VariableValueParameter,
    U <: AuxVariableType,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(
        container,
        T(),
        D,
        key,
        names,
        time_steps,
    )
    jump_model = get_jump_model(container)

    for d in devices
        name = PSY.get_name(d)
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                get_initial_parameter_value(T(), d, W()),
                name,
                t,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for OnStatusParameter (general, non-feedforward)
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    devices::V,
    model::DeviceModel{D, W},
) where {
    T <: OnStatusParameter,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    @debug "adding" T D V _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER

    # When the OnStatusParameter is added without a feedforward it takes a Float value.
    # This is used to handle the special case of compact formulations.
    !isempty(IOM.get_feedforwards(model)) && return
    names = [PSY.get_name(device) for device in devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(
        container,
        T(),
        D,
        VariableKey(OnVariable, D),
        names,
        time_steps,
    )
    jump_model = get_jump_model(container)

    for d in devices
        name = PSY.get_name(d)
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                get_initial_parameter_value(T(), d, W()),
                name,
                t,
            )
        end
    end
    return
end

#################################################################################
# _add_parameters! for ServiceModel VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::VariableKey{U, S},
    model::ServiceModel{S, W},
    devices::V,
) where {
    S <: PSY.AbstractReserve,
    T <: VariableValueParameter,
    U <: VariableType,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractReservesFormulation,
} where {D <: PSY.Component}
    @debug "adding" T D U _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    contributing_devices = IOM.get_contributing_devices(model)
    names = [PSY.get_name(device) for device in contributing_devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(
        container,
        T(),
        S,
        key,
        names,
        time_steps;
        meta = get_service_name(model),
    )
    jump_model = get_jump_model(container)
    for d in contributing_devices
        name = PSY.get_name(d)
        for t in time_steps
            IOM.set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), S, W()),
                name,
                t,
            )
            IOM.set_parameter!(
                parameter_container,
                jump_model,
                get_initial_parameter_value(T(), S, W()),
                name,
                t,
            )
        end
    end
    return
end
