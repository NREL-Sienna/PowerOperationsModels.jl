# Attaches a FixedForcedOutage supplemental attribute to `device` and a 0/1
# SingleTimeSeries named `ts_name` to the attribute. Returns the attribute.
# Adapted from PSI test/test_utils/events_simulation_utils.jl (build-relevant part only).
function attach_fixed_forced_outage!(
    sys::PSY.System,
    device::PSY.Device;
    ts_name = "outage_profile",
    outage_profile = nothing,
)
    outage = PSY.FixedForcedOutage(; outage_status = 0.0)
    PSY.add_supplemental_attribute!(sys, device, outage)
    resolution = first(PSY.get_time_series_resolutions(sys))
    initial_time = PSY.get_forecast_initial_timestamp(sys)
    horizon_count = Int(PSY.get_forecast_horizon(sys) / resolution)
    if isnothing(outage_profile)
        outage_profile = zeros(horizon_count)  # 0 = available for the whole horizon
    end
    ts_data = TimeSeries.TimeArray(
        range(initial_time; length = length(outage_profile), step = resolution),
        outage_profile,
    )
    ts = PSY.SingleTimeSeries(; name = ts_name, data = ts_data)
    PSY.add_time_series!(sys, outage, ts)
    return outage
end

# An `EventModel` for a `FixedForcedOutage` whose status series is `ts_name`, matching
# what `attach_fixed_forced_outage!` puts on the attribute.
fixed_outage_event(; ts_name = "outage_profile") = EventModel(
    PSY.FixedForcedOutage,
    ContinuousCondition();
    timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:outage_status => ts_name),
)

# Attach a `FixedForcedOutage` to `device`, build a `DecisionModel` for it, and return the
# model with its build status and event model. `recurrent` makes event parameters JuMP
# parameters (see `get_param_eltype`), which is what allows a test to fix them to an
# outage value.
function build_outage_model(
    sys,
    device;
    network = CopperPlateNetworkModel,
    template = nothing,
    optimizer = HiGHS_optimizer,
    recurrent = false,
)
    attach_fixed_forced_outage!(sys, device)
    event = fixed_outage_event()
    if isnothing(template)
        template = get_thermal_dispatch_template_network(NetworkModel(network))
    end
    set_event_model!(template, event)
    model = DecisionModel(template, sys; optimizer = optimizer)
    if recurrent
        IOM.get_optimization_container(model).built_for_recurrent_solves = true
    end
    status = build!(model; output_dir = mktempdir(; cleanup = true))
    return model, status, event
end

# Build a `MockOperationProblem` for `device_model` with the mock's outage attached to one
# device. Returns `(container, sys, model)`; most callers need only the first two, which a
# two-element destructuring picks up.
function mock_event_container(
    device_model::DeviceModel,
    network,
    sysname::Union{String, Nothing} = nothing;
    sys = PSB.build_system(PSITestSystems, sysname),
    recurrent = false,
)
    model = DecisionModel(MockOperationProblem, network, sys)
    mock_construct_device!(
        model,
        device_model;
        add_event_model = true,
        built_for_recurrent_solves = recurrent,
    )
    return IOM.get_optimization_container(model), sys, model
end

# The device the mock attributed, read back off the availability parameter. `get_components`
# iteration order is not stable across calls, so picking `first` from the system a second
# time can select a different device.
outaged_name(container, ::Type{T}) where {T <: PSY.Component} =
    axes(IOM.get_parameter_array(container, AvailableStatusParameter(), T))[1][1]

outaged_device(container, ::Type{T}, sys) where {T <: PSY.Component} =
    PSY.get_component(T, sys, outaged_name(container, T))

# Force the outage (availability = 0, requiring a `recurrent` build) and maximize exactly
# the variables it is supposed to suppress, so the result is zero only if the outage
# constraints actually bind. Returns the termination status and the optimal values.
function maximize_under_outage(container, ::Type{T}, var_types) where {T <: PSY.Component}
    name = outaged_name(container, T)
    status = IOM.get_parameter_array(container, AvailableStatusParameter(), T)
    for idx in eachindex(status)
        JuMP.fix(status[idx], 0.0; force = true)
    end
    arrays = [IOM.get_variable(container, v, T) for v in var_types]
    jm = IOM.get_jump_model(container)
    JuMP.@objective(
        jm,
        Max,
        sum(sum(a[name, t] for t in axes(a)[2]) for a in arrays)
    )
    JuMP.set_optimizer(jm, HiGHS.Optimizer)
    JuMP.set_silent(jm)
    JuMP.optimize!(jm)
    values = [[JuMP.value(a[name, t]) for t in axes(a)[2]] for a in arrays]
    return JuMP.termination_status(jm), values
end

# `c_sys5_hydro_pump_energy` needs reserves, a single time series, and the horizon
# transform before a pump-turbine model can be built on it.
function hydro_pump_energy_system()
    sys = PSB.build_system(
        PSITestSystems,
        "c_sys5_hydro_pump_energy";
        add_reserves = true,
        add_single_time_series = true,
    )
    transform_single_time_series!(sys, Hour(24), Hour(24))
    return sys
end

# Device families whose outage must drive one or more power variables to zero. Each case
# names the variables the outage is supposed to suppress; `maximize_under_outage` pushes
# on exactly those.
outage_zero_output_cases() = (
    (
        name = "thermal",
        dtype = PSY.ThermalStandard,
        device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment),
        network = DCPNetworkModel,
        build_sys = () -> PSB.build_system(PSITestSystems, "c_sys5_uc"),
        vars = [ActivePowerVariable],
    ),
    (
        name = "storage charge and discharge",
        dtype = EnergyReservoirStorage,
        device_model = DeviceModel(EnergyReservoirStorage, StorageDispatchWithReserves),
        network = DCPNetworkModel,
        build_sys = () -> PSB.build_system(PSITestSystems, "c_sys5_bat"),
        vars = [ActivePowerInVariable, ActivePowerOutVariable],
    ),
    (
        name = "hydro pump turbine and pump",
        dtype = HydroPumpTurbine,
        device_model = DeviceModel(
            HydroPumpTurbine,
            HydroPumpEnergyDispatch;
            attributes = Dict{String, Any}(
                "reservation" => true,
                "energy_target" => true,
            ),
        ),
        network = CopperPlateNetworkModel,
        build_sys = hydro_pump_energy_system,
        vars = [ActivePowerVariable, ActivePowerPumpVariable],
    ),
)
