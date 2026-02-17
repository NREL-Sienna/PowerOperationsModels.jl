# System builders for ImportExportCost tests.
# The simulation infrastructure (run_iec_sim, etc.) lives in PSI's iec_simulation_utils.jl.

const IECComponentType = Source
const IEC_COMPONENT_NAME = "source"
const SEL_IEC = make_selector(IECComponentType, IEC_COMPONENT_NAME)

function make_5_bus_with_import_export(;
    add_single_time_series::Bool = false,
    name = nothing,
)
    sys = build_system(
        PSITestSystems,
        "c_sys5_uc";
        add_single_time_series = add_single_time_series,
    )

    source = IECComponentType(;
        name = IEC_COMPONENT_NAME,
        available = true,
        bus = get_component(ACBus, sys, "nodeC"),
        active_power = 0.0,
        reactive_power = 0.0,
        active_power_limits = (min = -2.0, max = 2.0),
        reactive_power_limits = (min = -2.0, max = 2.0),
        R_th = 0.01,
        X_th = 0.02,
        internal_voltage = 1.0,
        internal_angle = 0.0,
        base_power = 100.0,
    )

    import_curve = make_import_curve(
        [0.0, 100.0, 105.0, 120.0, 200.0],
        [5.0, 10.0, 20.0, 40.0],
    )

    export_curve = make_export_curve(
        [0.0, 100.0, 105.0, 120.0, 200.0],
        [12.0, 8.0, 4.0, 1.0],  # elsewhere the final slope is 0.0 but that's problematic here
    )

    ie_cost = ImportExportCost(;
        import_offer_curves = import_curve,
        export_offer_curves = export_curve,
        ancillary_service_offers = Vector{Service}(),
        energy_import_weekly_limit = 1e6,
        energy_export_weekly_limit = 1e6,
    )

    set_operation_cost!(source, ie_cost)
    add_component!(sys, source)
    @assert get_component(SEL_IEC, sys) == source

    isnothing(name) || set_name!(sys, name)
    return sys
end
