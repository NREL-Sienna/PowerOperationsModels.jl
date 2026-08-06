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
    _add_parameters!(container, T, devices, model)
    return
end

# Per-type service time-series parameter: all services of the type share one container
# keyed `(ParameterType, ServiceType)`, axed by service name.
function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    services::Vector{U},
    model::ServiceModel{U, V},
) where {T <: TimeSeriesParameter, U <: PSY.Service, V <: AbstractServiceFormulation}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, U)
        return
    end
    _add_parameters!(container, T, services, model)
    return
end

# Per-type operating reserve demand curve (ORDC) PWL cost params: all the type's services
# share one container (names axis + tranche axis).
function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    services::Vector{U},
    model::ServiceModel{V, W},
) where {
    T <: Union{
        AbstractPiecewiseLinearSlopeParameter,
        AbstractPiecewiseLinearBreakpointParameter,
    },
    U <: PSY.ReserveDemandTimeSeriesCurve,
    V <: PSY.ReserveDemandTimeSeriesCurve,
    W <: AbstractServiceFormulation,
}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, U)
        return
    end
    _add_parameters!(container, T, services, model)
    return
end

function add_branch_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
    network_model::NetworkModel{<:AbstractNetworkModel},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.ACTransmission}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, D)
        return
    end
    _add_time_series_parameters!(container, T, network_model, devices, model)
    return
end

#################################################################################
# _add_parameters! for TimeSeriesParameter → delegates to _add_time_series_parameters!
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    param::Type{T},
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

function _check_branch_rating_ts(
    ts::AbstractArray,
    ::Type{T},
    device::PSY.Device,
    model::DeviceModel{D, W},
) where {D <: PSY.Component, T <: TimeSeriesParameter, W <: AbstractDeviceFormulation}
    if !(T <: AbstractBranchRatingTimeSeriesParameter)
        return
    end

    rating = _branch_rating(device)
    if (T <: PostContingencyBranchRatingTimeSeriesParameter)
        if !(_branch_rating_b(device) === nothing)
            rating = _branch_rating_b(device)
        else
            @warn "Device $(typeof(device)) '$(PSY.get_name(device))' has Parameter $T but it has no static 'rating_b' defined."
        end
    end

    multiplier = get_multiplier_value(T, device, W)
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
    param::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    D <: PSY.Component,
    T <: TimeSeriesParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end

    time_steps = get_time_steps(container)
    ts_name = _get_time_series_name(T, first(devices), model)

    device_names = String[]
    devices_with_time_series = D[]
    initial_values = Dict{String, AbstractArray}()
    # device name -> ts_uuid cache so the second loop below doesn't re-query IS.
    device_ts_uuids = Dict{String, String}()
    model_interval = get_interval(get_settings(container))
    is_ts_interval = _to_is_interval(model_interval)
    model_resolution = get_resolution(get_settings(container))
    is_ts_resolution = _to_is_resolution(model_resolution)

    @debug "adding" T D ts_name ts_type _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER

    for device::D in devices
        if !PSY.has_time_series(device, ts_type, ts_name)
            @debug "Time series $(ts_type):$(ts_name) for $D, $(PSY.get_name(device)) not found. Skipping parameter addition for this device."
            continue
        end
        device_name = PSY.get_name(device)
        push!(device_names, device_name)
        push!(devices_with_time_series, device)
        ts_uuid = string(
            IS.get_time_series_uuid(
                ts_type,
                device,
                ts_name;
                resolution = is_ts_resolution,
                interval = is_ts_interval,
            ),
        )
        device_ts_uuids[device_name] = ts_uuid
        if !(ts_uuid in keys(initial_values))
            initial_values[ts_uuid] =
                IOM.get_time_series_initial_values!(
                    container,
                    ts_type,
                    device,
                    ts_name;
                    interval = model_interval,
                    resolution = model_resolution,
                )
            _check_branch_rating_ts(initial_values[ts_uuid], param, device, model)
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
        T,
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
    parent_param = IOM.get_parameter_array_data(param_container)
    for (i, (ts_uuid, raw_ts_vals)) in enumerate(initial_values)
        ts_vals = IOM.unwrap_for_param.((param_instance,), raw_ts_vals, (additional_axes,))
        @assert all(_size_wrapper.(ts_vals) .== (length.(additional_axes),))

        for step in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ts_vals[step], i, step)
        end
    end

    parent_mult = IOM.get_multiplier_array_data(param_container)
    for (i, device) in enumerate(devices_with_time_series)
        multiplier = get_multiplier_value(T, device, W)
        device_name = PSY.get_name(device)
        IOM._set_multiplier_at!(parent_mult, multiplier, i)
        IOM.add_component_name!(
            IOM.get_attributes(param_container),
            device_name,
            device_ts_uuids[device_name],
        )
    end
    return
end

#################################################################################
# _add_time_series_parameters! — network-aware overload for ACTransmission + PTDF
#################################################################################

function _add_time_series_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    network_model::NetworkModel{<:AbstractNetworkModel},
    devices::U,
    model::DeviceModel{D, W},
) where {
    D <: PSY.ACTransmission,
    T <: TimeSeriesParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end
    time_steps = get_time_steps(container)

    net_reduction_data = network_model.network_reduction
    reduced_branch_tracker = get_reduced_branch_tracker(network_model)
    all_branch_maps_by_type = PNM.get_all_branch_maps_by_type(net_reduction_data)

    # TODO: Temporary workaround to get the name where we assume all the names are the same across devices.
    ts_name = _get_time_series_name(T, first(devices), model)
    model_interval = get_interval(get_settings(container))
    ts_interval = model_interval
    device_name_axis, ts_uuid_axis =
        get_branch_argument_parameter_axes(
            net_reduction_data,
            devices,
            ts_type,
            ts_name;
            interval = ts_interval,
        )
    if isempty(device_name_axis)
        @info "No devices with time series $ts_name found for $D devices. Skipping parameter addition."
        return
    end
    # name -> ts_uuid cache built from the axis pair so the per-branch loop below
    # doesn't re-query IS.get_time_series_uuid for each branch.
    branch_ts_uuids = Dict{String, String}(zip(device_name_axis, ts_uuid_axis))
    additional_axes = ()
    param_container = add_param_container!(
        container,
        T,
        D,
        ts_type,
        ts_name,
        ts_uuid_axis,
        device_name_axis,
        additional_axes,
        time_steps,
    )
    IOM.set_subsystem!(IOM.get_attributes(param_container), IOM.get_subsystem(model))
    param_instance = T()
    jump_model = get_jump_model(container)
    parent_param = IOM.get_parameter_array_data(param_container)
    parent_mult = IOM.get_multiplier_array_data(param_container)
    # The param array's first axis is `ts_uuid_axis` (UUID-keyed) while the multiplier
    # array's first axis is `device_name_axis` (name-keyed); we need two separate row
    # lookups so parallel branches sharing a UUID still write their multiplier to the
    # correct (per-branch-name) row.
    param_lookup = get_parameter_array(param_container).lookup[1]
    mult_lookup = get_multiplier_array(param_container).lookup[1]
    for (name, (arc, reduction)) in PNM.get_name_to_arc_map(net_reduction_data, D)
        reduction_entry = all_branch_maps_by_type[reduction][D][arc]
        device_with_time_series =
            get_branch_with_time_series(reduction_entry, ts_type, ts_name)
        if device_with_time_series === nothing
            continue
        end
        ts_uuid = branch_ts_uuids[name]
        i_param = param_lookup[ts_uuid]
        i_mult = mult_lookup[name]

        has_entry, tracker_container = search_for_reduced_branch_parameter!(
            reduced_branch_tracker,
            arc,
            T,
        )

        if has_entry
            @assert !isempty(tracker_container) name arc reduction
        else
            raw_ts_vals = IOM.get_time_series_initial_values!(
                container,
                ts_type,
                device_with_time_series,
                ts_name;
                interval = ts_interval,
            )
            ts_vals =
                IOM.unwrap_for_param.((param_instance,), raw_ts_vals, (additional_axes,))
            @assert all(_size_wrapper.(ts_vals) .== (length.(additional_axes),))
        end
        # `_resolve_branch_multiplier` is `DeviceModel`-aware: it applies the
        # branch-rating aggregation policy (parallel groups use the summed rating;
        # non-parallel entries use `PNM.get_equivalent_rating`). The generic
        # `get_multiplier_value` only handles plain `PSY.ACTransmission` devices and
        # would call `PSY.get_rating` on a `BranchesParallel` reduction wrapper.
        multiplier = _resolve_branch_multiplier(T, reduction_entry, W, model)
        IOM._set_multiplier_at!(parent_mult, multiplier, i_mult)
        for t in time_steps
            if !has_entry
                # For non-recurrent builds, store the raw float in the tracker; for
                # recurrent builds (JuMP parameters), read back the VariableRef the
                # fast-path setter just created so parallel branch types share it.
                IOM._set_parameter_at!(parent_param, jump_model, ts_vals[t], i_param, t)
                if built_for_recurrent_solves(container)
                    tracker_container[t] = parent_param[i_param, t]
                else
                    tracker_container[t] = ts_vals[t]
                end
            else
                # Reuse the value (Float64) or VariableRef stored by the first branch
                # type that processed this arc.
                IOM._set_parameter_at!(
                    parent_param,
                    jump_model,
                    tracker_container[t],
                    i_param,
                    t,
                )
            end
        end
        IOM.add_component_name!(
            IOM.get_attributes(param_container),
            name,
            ts_uuid,
        )
    end
    return
end

_get_time_series_name(
    ::Type{T},
    ::PSY.Component,
    model::DeviceModel,
) where {T <: ParameterType} =
    get_time_series_names(model)[T]

# Time-varying ORDC: the slope/breakpoint parameters read from the curve time
# series referenced by the service's `variable` field.
_get_time_series_name(
    ::Type{
        <:Union{
            DecrementalPiecewiseLinearSlopeParameter,
            DecrementalPiecewiseLinearBreakpointParameter,
        },
    },
    service::PSY.ReserveDemandTimeSeriesCurve,
    ::ServiceModel,
) = IS.get_name(IS.get_time_series_key(PSY.get_variable(service)))

# The fact that we're seeing these parameters means that we should
# have a time-varying MBC/IEC, so the `get_time_series_key` call should be valid.

function _get_time_series_name(
    ::Type{StartupCostParameter},
    device::PSY.Component,
    ::DeviceModel,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_name(IS.get_time_series_key(PSY.get_start_up(op_cost)))
end

function _get_time_series_name(
    ::Type{ShutdownCostParameter},
    device::PSY.Component,
    ::DeviceModel,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_name(IS.get_time_series_key(PSY.get_shut_down(op_cost)))
end

function _get_time_series_name(
    ::Type{IncrementalCostAtMinParameter},
    device::PSY.Device,
    ::DeviceModel,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_name(
        IS.get_initial_input(
            PSY.get_value_curve(get_output_offer_curves(op_cost)),
        ),
    )
end

function _get_time_series_name(
    ::Type{DecrementalCostAtMinParameter},
    device::PSY.Device,
    ::DeviceModel,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_name(
        IS.get_initial_input(
            PSY.get_value_curve(get_input_offer_curves(op_cost)),
        ),
    )
end

function _get_time_series_name(
    ::Type{T},
    device::PSY.Component,
    ::DeviceModel,
) where {
    T <: Union{
        IncrementalPiecewiseLinearSlopeParameter,
        IncrementalPiecewiseLinearBreakpointParameter,
        DecrementalPiecewiseLinearSlopeParameter,
        DecrementalPiecewiseLinearBreakpointParameter,
    },
}
    return IS.get_name(_device_offer_curve_ts_key(T, device))
end

#################################################################################
# _get_expected_time_series_eltype — for ObjectiveFunctionParameter
#################################################################################

_get_expected_time_series_eltype(::Type{T}) where {T <: ParameterType} = Float64
_get_expected_time_series_eltype(::Type{StartupCostParameter}) = NTuple{3, Float64}

#################################################################################
# _param_to_vars — lookup: ObjectiveFunctionParameter → variable types
#################################################################################

_param_to_vars(::Type{FuelCostParameter}, ::Type{<:AbstractDeviceFormulation}) =
    (ActivePowerVariable,)
_param_to_vars(::Type{StartupCostParameter}, ::Type{<:AbstractThermalFormulation}) =
    (StartVariable,)
_param_to_vars(::Type{StartupCostParameter}, ::Type{ThermalMultiStartUnitCommitment}) =
    MULTI_START_VARIABLES
_param_to_vars(::Type{ShutdownCostParameter}, ::Type{<:AbstractThermalFormulation}) =
    (StopVariable,)
_param_to_vars(::Type{<:AbstractCostAtMinParameter}, ::Type{<:AbstractDeviceFormulation}) =
    (OnVariable,)
_param_to_vars(
    ::Union{
        Type{IncrementalPiecewiseLinearSlopeParameter},
        Type{IncrementalPiecewiseLinearBreakpointParameter},
    },
    ::Type{<:AbstractDeviceFormulation},
) =
    (PiecewiseLinearBlockIncrementalOffer,)
_param_to_vars(
    ::Union{
        Type{DecrementalPiecewiseLinearSlopeParameter},
        Type{DecrementalPiecewiseLinearBreakpointParameter},
    },
    ::Type{<:AbstractDeviceFormulation},
) =
    (PiecewiseLinearBlockDecrementalOffer,)
_param_to_vars(
    ::Union{
        Type{DecrementalPiecewiseLinearSlopeParameter},
        Type{DecrementalPiecewiseLinearBreakpointParameter},
    },
    ::Type{<:AbstractServiceFormulation},
) =
    (PiecewiseLinearBlockDecrementalOffer,)

#################################################################################
# calc_additional_axes — default implementations (no additional axes)
#################################################################################

calc_additional_axes(
    ::OptimizationContainer,
    ::Type{T},
    ::U,
    ::DeviceModel{D, W},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component} = ()

calc_additional_axes(
    ::OptimizationContainer,
    ::Type{T},
    ::U,
    ::ServiceModel{D, W},
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractServiceFormulation,
} where {D <: PSY.Service} = ()

#################################################################################
# Piecewise linear parameter helpers (time-varying ORDC)
#################################################################################

function get_max_tranches(component::PSY.Component, piecewise_ts::IS.TimeSeriesKey)
    data = PSY.get_data(PSY.get_time_series(component, piecewise_ts))
    return IOM.get_max_tranches(data)
end

# Batch form (mirrors the device methods below): size the tranche axis to the largest tranche
# count across the type's services; shorter per-hour curves are padded in `unwrap_for_param`.
#
# `services` is typed `Vector{<:ReserveDemandTimeSeriesCurve}` rather than tied to the
# `ServiceModel`'s component type, because that type can be partially applied (e.g.
# `ReserveDemandCurve` without its reserve-direction parameter) and `Vector` is invariant, so a
# vector of the concrete service instances would not match `Vector{D}`.
function calc_additional_axes(
    ::OptimizationContainer,
    ::Type{P},
    services::Vector{<:PSY.ReserveDemandTimeSeriesCurve},
    ::ServiceModel{<:PSY.ReserveDemandTimeSeriesCurve, W},
) where {
    P <: AbstractPiecewiseLinearSlopeParameter,
    W <: AbstractServiceFormulation,
}
    max_tranches = maximum(services) do service
        get_max_tranches(service, IS.get_time_series_key(PSY.get_variable(service)))
    end
    return (IOM.make_tranche_axis(max_tranches),)
end

function calc_additional_axes(
    ::OptimizationContainer,
    ::Type{P},
    services::Vector{<:PSY.ReserveDemandTimeSeriesCurve},
    ::ServiceModel{<:PSY.ReserveDemandTimeSeriesCurve, W},
) where {
    P <: AbstractPiecewiseLinearBreakpointParameter,
    W <: AbstractServiceFormulation,
}
    max_tranches = maximum(services) do service
        get_max_tranches(service, IS.get_time_series_key(PSY.get_variable(service)))
    end
    return (IOM.make_tranche_axis(max_tranches + 1),)  # one more breakpoint than tranches
end

function _device_offer_curve_ts_key(
    ::Type{
        <:Union{
            IncrementalPiecewiseLinearSlopeParameter,
            IncrementalPiecewiseLinearBreakpointParameter,
        },
    },
    device::PSY.Component,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_time_series_key(PSY.get_value_curve(get_output_offer_curves(op_cost)))
end

function _device_offer_curve_ts_key(
    ::Type{
        <:Union{
            DecrementalPiecewiseLinearSlopeParameter,
            DecrementalPiecewiseLinearBreakpointParameter,
        },
    },
    device::PSY.Component,
)
    op_cost = PSY.get_operation_cost(device)
    IS.@assert_op op_cost isa TS_OFFER_CURVE_COST_TYPES
    return IS.get_time_series_key(PSY.get_value_curve(get_input_offer_curves(op_cost)))
end

# Axes are sized to the batch-wide maximum tranche count; shorter per-hour curves
# are padded in `unwrap_for_param`.
function calc_additional_axes(
    ::OptimizationContainer,
    ::Type{T},
    devices::U,
    ::DeviceModel{D, W},
) where {
    T <: AbstractPiecewiseLinearSlopeParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    max_tranches =
        maximum(d -> get_max_tranches(d, _device_offer_curve_ts_key(T, d)), devices)
    return (IOM.make_tranche_axis(max_tranches),)
end

function calc_additional_axes(
    ::OptimizationContainer,
    ::Type{T},
    devices::U,
    ::DeviceModel{D, W},
) where {
    T <: AbstractPiecewiseLinearBreakpointParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    max_tranches =
        maximum(d -> get_max_tranches(d, _device_offer_curve_ts_key(T, d)), devices)
    return (IOM.make_tranche_axis(max_tranches + 1),)  # one more breakpoint than tranches
end

# Both device and service `calc_additional_axes` take the whole batch, so forward the
# collection `_add_objective_function_parameters!` already holds.
_calc_additional_axes(
    container::OptimizationContainer,
    ::Type{P},
    active,
    model::Union{DeviceModel, ServiceModel},
) where {P <: ParameterType} = calc_additional_axes(container, P, active, model)

#################################################################################
# _add_parameters! for ObjectiveFunctionParameter
#################################################################################

# Shared body for ObjectiveFunctionParameter cost params (slope/breakpoint, cost-at-min,
# startup/shutdown). Devices and reserve-demand-curve services alike are batched into one
# names-axis container with empty `meta`, filled per member. `W` is the formulation.
function _add_objective_function_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::V,
    model,
    ::Type{W};
    meta = IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ObjectiveFunctionParameter, V, W}
    D = eltype(devices)
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
        ts_name = _get_time_series_name(T, device, model)
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

    additional_axes = _calc_additional_axes(container, T, active_devices, model)
    param_container = add_param_container!(
        container,
        T,
        D,
        _param_to_vars(T, W),
        SOSStatusVariable.NO_VARIABLE,
        false,
        _get_expected_time_series_eltype(T),
        device_names,
        additional_axes...,
        time_steps;
        meta = meta,
    )

    param_instance = T()
    model_interval = get_interval(get_settings(container))
    ts_interval = model_interval
    parent_param = IOM.get_parameter_array_data(param_container)
    parent_mult = IOM.get_multiplier_array_data(param_container)
    for (i, (ts_name, device_name, device)) in
        enumerate(zip(ts_names, device_names, active_devices))
        raw_ts_vals =
            IOM.get_time_series_initial_values!(
                container,
                ts_type,
                device,
                ts_name;
                interval = ts_interval,
            )
        ts_vals = IOM.unwrap_for_param.((param_instance,), raw_ts_vals, (additional_axes,))
        @assert all(_size_wrapper.(ts_vals) .== (length.(additional_axes),))
        # PWL/cost-function path: parameter values from `unwrap_for_param` are
        # tuples-of-floats, while the multiplier itself is a scalar Float64.
        IOM._set_multiplier_at!(
            parent_mult,
            get_multiplier_value(T, device, W),
            i,
        )
        for step in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ts_vals[step], i, step)
        end
    end
    return
end

# Device entry: batch all components of a type into one names-axis container
# (`meta` defaults to empty, reproducing the prior key exactly).
function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, W},
) where {
    T <: ObjectiveFunctionParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractDeviceFormulation,
} where {D <: PSY.Component}
    _add_objective_function_parameters!(container, T, devices, model, W)
    return
end

#################################################################################
# _add_parameters! for time-varying ORDC slope/breakpoint cost parameters
#
# Same cost-parameter machinery as the device path: batch all the type's services into one
# container (names axis + tranche axis), the tranche axis sized to the batch-wide maximum via
# `calc_additional_axes`. Read back name-keyed by the delta-PWL machinery.
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    services::Vector{U},
    model::ServiceModel{V, W},
) where {
    T <: Union{
        AbstractPiecewiseLinearSlopeParameter,
        AbstractPiecewiseLinearBreakpointParameter,
    },
    U <: PSY.ReserveDemandTimeSeriesCurve,
    V <: PSY.ReserveDemandTimeSeriesCurve,
    W <: AbstractServiceFormulation,
}
    _add_objective_function_parameters!(container, T, services, model, W)
    return
end

#################################################################################
# _add_parameters! for ServiceModel TimeSeriesParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    services::Vector{U},
    model::ServiceModel{U, V},
) where {T <: TimeSeriesParameter, U <: PSY.Service, V <: AbstractServiceFormulation}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end
    ts_name = get_time_series_names(model)[T]
    time_steps = get_time_steps(container)
    model_interval = get_interval(get_settings(container))
    ts_interval = model_interval
    names = [PSY.get_name(s) for s in services]
    ts_uuids = [
        string(
            IS.get_time_series_uuid(
                ts_type,
                s,
                ts_name;
                interval = _to_is_interval(ts_interval),
            ),
        ) for s in services
    ]
    additional_axes = calc_additional_axes(container, T, services, model)
    parameter_container = add_param_container!(container, T,
        U,
        ts_type,
        ts_name,
        ts_uuids,
        names,
        additional_axes,
        time_steps,
    )
    IOM.set_subsystem!(IOM.get_attributes(parameter_container), IOM.get_subsystem(model))
    jump_model = get_jump_model(container)
    attributes = IOM.get_attributes(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    for (i, service) in enumerate(services)
        name = names[i]
        ts_vector = IOM.get_time_series(container, service, ts_name; interval = ts_interval)
        multiplier = get_multiplier_value(T, service, V)
        IOM._set_multiplier_at!(parent_mult, multiplier, i)
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ts_vector[t], i, t)
        end
        IOM.add_component_name!(attributes, name, ts_uuids[i])
    end
    return
end

#################################################################################
# _add_parameters! for VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
    parameter_container = add_param_container!(container, T, D, key, names, time_steps)
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    for (i, d) in enumerate(devices)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        if get_variable_warm_start_value(U, d, W) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U, d, W)
        end
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, inital_parameter_value, i, t)
        end
    end
    return
end

#################################################################################
# _add_parameters! for OnStatusParameter (ThermalGen-specific)
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
    parameter_container = add_param_container!(container, T, D, key, names, time_steps)
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    # Iterate the same filtered view used to construct `names` so enumeration index
    # `i` lines up with the parameter container's first axis.
    for (i, d) in enumerate(Iterators.filter(d -> !PSY.get_must_run(d), devices))
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        if get_variable_warm_start_value(U, d, W) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U, d, W)
        end
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, inital_parameter_value, i, t)
        end
    end
    return
end

#################################################################################
# _add_parameters! for FixValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
        add_param_container!(container, T, D, key, names, time_steps; meta = "$U")
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    for (i, d) in enumerate(devices)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        if get_variable_warm_start_value(U, d, W) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U, d, W)
        end
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, inital_parameter_value, i, t)
        end
    end
    return
end

#################################################################################
# _add_parameters! for AuxVarKey VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
    parameter_container = add_param_container!(container, T,
        D,
        key,
        names,
        time_steps,
    )
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)

    for (i, d) in enumerate(devices)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        ini_val = get_initial_parameter_value(T, d, W)
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ini_val, i, t)
        end
    end
    return
end

#################################################################################
# _add_parameters! for OnStatusParameter (general, non-feedforward)
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
    parameter_container = add_param_container!(container, T,
        D,
        VariableKey(OnVariable, D),
        names,
        time_steps,
    )
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)

    for (i, d) in enumerate(devices)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T, d, W),
            i,
        )
        ini_val = get_initial_parameter_value(T, d, W)
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ini_val, i, t)
        end
    end
    return
end

#################################################################################
# _add_parameters! for ServiceModel VariableValueParameter
#################################################################################

function _add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
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
    # TODO: per-service keying when service feedforwards are ported. Unreachable today, since
    # service feedforwards are no-op stubs in POM. `get_contributing_devices(model)` flattens
    # across all services of the type, so this builds a device-name-keyed parameter with no
    # service axis, inconsistent with the `(service, device, time)` reserve variables it must
    # feed forward against. Re-key by `(service, device)` reading
    # `get_contributing_devices(model, service_name)` before wiring service feedforwards.
    contributing_devices = IOM.get_contributing_devices(model)
    names = [PSY.get_name(device) for device in contributing_devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(container, T,
        S,
        key,
        names,
        time_steps,
    )
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    multiplier = get_parameter_multiplier(T, S, W)
    ini_val = get_initial_parameter_value(T, S, W)
    for (i, d) in enumerate(contributing_devices)
        IOM._set_multiplier_at!(parent_mult, multiplier, i)
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ini_val, i, t)
        end
    end
    return
end
