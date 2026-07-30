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
