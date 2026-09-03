#################################################################################
# Market Bid / Import-Export Cost Plumbing
#
# PSY-specific plumbing moved out of IOM's `objective_function/value_curve_cost.jl`.
# Responsibilities:
#   * Accessor wrappers that resolve MBC / IEC offer curves (static + time-series).
#   * Cost detection predicates (_has_market_bid_cost / _has_import_export_cost).
#   * Parameter-field dispatch tables over PSY getter functions.
#   * Component-level validation (validate_occ_component, curvity checks).
#   * Parameter processing orchestration (process_market_bid_parameters!,
#     process_import_export_parameters!).
#   * Static PWL data retrieval (_get_raw_pwl_data for CostCurve{PiecewiseIncrementalCurve}).
#   * The static add_pwl_term_delta! / add_variable_cost_to_objective! / VOM cost path.
#
# IOM owns the generic OfferDirection dispatch table, _consider_parameter, the
# TS-backed add_variable_cost_to_objective! path, and the delta PWL primitives
# (add_pwl_variables_delta!, add_pwl_constraint_delta!, get_pwl_cost_expression_delta).
#################################################################################

#################################################################################
# Union aliases for MBC / IEC / TS offer curve cost types
#################################################################################

const MBC_TYPES = Union{PSY.MarketBidCost, PSY.MarketBidTimeSeriesCost}
const IEC_TYPES = Union{PSY.ImportExportCost, PSY.ImportExportTimeSeriesCost}
const TS_OFFER_CURVE_COST_TYPES =
    Union{PSY.MarketBidTimeSeriesCost, PSY.ImportExportTimeSeriesCost}

#################################################################################
# Section 1: Offer Curve Accessor Wrappers
# Map PSY cost types (MarketBidCost, ImportExportCost) to a unified interface.
#################################################################################

####################### get_{output/input}_offer_curves #########################
# 1-argument getters: straight getfield calls (same PSY getter for static and TS variants)
get_output_offer_curves(cost::IEC_TYPES) = PSY.get_import_offer_curves(cost)
get_output_offer_curves(cost::MBC_TYPES) = PSY.get_incremental_offer_curves(cost)
get_input_offer_curves(cost::IEC_TYPES) = PSY.get_export_offer_curves(cost)
get_input_offer_curves(cost::MBC_TYPES) = PSY.get_decremental_offer_curves(cost)

# 2-argument getters: resolve time series if needed, return static curve(s).
# Static types: delegate to 1-arg getter (no resolution needed).
get_output_offer_curves(
    ::IS.InfrastructureSystemsComponent,
    cost::PSY.ImportExportCost;
    kwargs...,
) = PSY.get_import_offer_curves(cost)
get_output_offer_curves(
    ::IS.InfrastructureSystemsComponent,
    cost::PSY.MarketBidCost;
    kwargs...,
) = PSY.get_incremental_offer_curves(cost)
get_input_offer_curves(
    ::IS.InfrastructureSystemsComponent,
    cost::PSY.ImportExportCost;
    kwargs...,
) = PSY.get_export_offer_curves(cost)
get_input_offer_curves(
    ::IS.InfrastructureSystemsComponent,
    cost::PSY.MarketBidCost;
    kwargs...,
) = PSY.get_decremental_offer_curves(cost)
# TS types: resolve via PSY's 2-arg getters.
get_output_offer_curves(
    component::IS.InfrastructureSystemsComponent,
    cost::PSY.ImportExportTimeSeriesCost;
    kwargs...,
) = PSY.get_import_variable_cost(component, cost; kwargs...)
get_output_offer_curves(
    component::IS.InfrastructureSystemsComponent,
    cost::PSY.MarketBidTimeSeriesCost;
    kwargs...,
) = PSY.get_incremental_variable_cost(component, cost; kwargs...)
get_input_offer_curves(
    component::IS.InfrastructureSystemsComponent,
    cost::PSY.ImportExportTimeSeriesCost;
    kwargs...,
) = PSY.get_export_variable_cost(component, cost; kwargs...)
get_input_offer_curves(
    component::IS.InfrastructureSystemsComponent,
    cost::PSY.MarketBidTimeSeriesCost;
    kwargs...,
) = PSY.get_decremental_variable_cost(component, cost; kwargs...)

######################### get_offer_curves(direction, ...) ##############################

# direction and device:
get_offer_curves(::IOM.DecrementalOffer, device::PSY.StaticInjection) =
    get_input_offer_curves(PSY.get_operation_cost(device))
get_offer_curves(::IOM.IncrementalOffer, device::PSY.StaticInjection) =
    get_output_offer_curves(PSY.get_operation_cost(device))
IOM.get_initial_input(::IOM.DecrementalOffer, device::PSY.StaticInjection) =
    IS.get_initial_input(
        IS.get_value_curve(get_input_offer_curves(PSY.get_operation_cost(device))),
    )
IOM.get_initial_input(::IOM.IncrementalOffer, device::PSY.StaticInjection) =
    IS.get_initial_input(
        IS.get_value_curve(get_output_offer_curves(PSY.get_operation_cost(device))),
    )

# direction and cost curve (needed for VOM code path):
get_offer_curves(::IOM.DecrementalOffer, op_cost::PSY.OfferCurveCost) =
    get_input_offer_curves(op_cost)
get_offer_curves(::IOM.IncrementalOffer, op_cost::PSY.OfferCurveCost) =
    get_output_offer_curves(op_cost)

# direction and operating reserve demand curve (ORDC) reserve service: the curve is on the
# `variable` field (a CostCurve, static or time-series-backed) rather than split
# across incremental/decremental sides. Direction is irrelevant to the lookup; the
# service-side direction trait (`_reserve_offer_direction`) is decremental.
get_offer_curves(
    ::IOM.OfferDirection,
    service::PSY.AbstractReserve,
) = PSY.get_variable(service)

#################################################################################
# Section 3: _get_parameter_field Dispatch Table
# Maps parameter types to PSY getter functions.
#################################################################################

IOM._get_parameter_field(::Type{<:StartupCostParameter}, op_cost) =
    PSY.get_start_up(op_cost)
IOM._get_parameter_field(::Type{<:ShutdownCostParameter}, op_cost) =
    PSY.get_shut_down(op_cost)
IOM._get_parameter_field(::Type{<:IncrementalCostAtMinParameter}, op_cost) =
    IS.get_initial_input(IS.get_value_curve(get_output_offer_curves(op_cost)))
IOM._get_parameter_field(::Type{<:DecrementalCostAtMinParameter}, op_cost) =
    IS.get_initial_input(IS.get_value_curve(get_input_offer_curves(op_cost)))
IOM._get_parameter_field(
    ::Type{
        <:Union{
            IncrementalPiecewiseLinearSlopeParameter,
            IncrementalPiecewiseLinearBreakpointParameter,
        },
    },
    op_cost,
) = get_output_offer_curves(op_cost)
IOM._get_parameter_field(
    ::Type{
        <:Union{
            DecrementalPiecewiseLinearSlopeParameter,
            DecrementalPiecewiseLinearBreakpointParameter,
        },
    },
    op_cost,
) = get_input_offer_curves(op_cost)

#################################################################################
# Section 4: Device Cost Detection Predicates (generic)
#################################################################################

_has_market_bid_cost(device::PSY.StaticInjection) =
    _has_market_bid_cost(PSY.get_operation_cost(device))
_has_market_bid_cost(::MBC_TYPES) = true
_has_market_bid_cost(::PSY.OperationalCost) = false

_has_import_export_cost(::PSY.StaticInjection) = false
_has_import_export_cost(device::PSY.Source) =
    _has_import_export_cost(PSY.get_operation_cost(device))
_has_import_export_cost(::IEC_TYPES) = true
_has_import_export_cost(::PSY.OperationalCost) = false

_has_offer_curve_cost(device::IS.InfrastructureSystemsComponent) =
    _has_market_bid_cost(device) || _has_import_export_cost(device)

# With the static/TS type split, time-series parameters are determined by cost type:
# TS cost types always have time-series parameters; static types never do.
_has_parameter_time_series(device::PSY.StaticInjection) =
    _has_parameter_time_series(PSY.get_operation_cost(device))

_has_parameter_time_series(::TS_OFFER_CURVE_COST_TYPES) = true
_has_parameter_time_series(::PSY.OperationalCost) = false

# Mirrors IOM's TS-cost predicate so validate_occ_component can short-circuit on TS types.
IOM._is_time_series_cost(::PSY.MarketBidTimeSeriesCost) = true

# MBC / IEC cleanly split static vs TS by type, so `is_time_variant_proportional` is a flat
# type dispatch — no instance lookup (unlike FuelCurve-backed ThermalGenerationCost).
IOM.is_time_variant_proportional(::PSY.MarketBidCost) = false
IOM.is_time_variant_proportional(::PSY.MarketBidTimeSeriesCost) = true

# `PSY.StartUpStages` is a plain NamedTuple: the static, non-time-series `start_up` field
# of a MarketBidCost. IOM's generic predicate delegates to `IS.is_time_series_backed`,
# which has no method for it, so state the answer here where PSY types are in scope.
IOM.is_time_variant(::PSY.StartUpStages) = false
IOM.is_time_variant_proportional(::PSY.ImportExportCost) = false
IOM.is_time_variant_proportional(::PSY.ImportExportTimeSeriesCost) = true

#################################################################################
# Section 6: Validation
#################################################################################

function IOM.validate_occ_breakpoints_slopes(
    device::PSY.StaticInjection,
    dir::IOM.OfferDirection,
)
    offer_curves = get_offer_curves(dir, device)
    _validate_occ_curves(device, dir, offer_curves)
end

# Static: validate convexity/concavity and cost-type-specific constraints
function _validate_occ_curves(
    device::PSY.StaticInjection,
    dir::IOM.OfferDirection,
    cost_curve::IS.CostCurve{IS.PiecewiseIncrementalCurve},
)
    device_name = IS.get_name(device)
    cost_curve_name = nameof(typeof(PSY.get_operation_cost(device)))
    IOM.curvity_check(dir, cost_curve) ||
        throw(
            ArgumentError(
                "$(uppercasefirst(string(dir))) $cost_curve_name for component $(device_name) is non-$(IOM.expected_curvity(dir))",
            ),
        )
    _validate_occ_subtype(PSY.get_operation_cost(device), dir, cost_curve, device_name)
end

# TS-backed: validated at parameter population time, not here
_validate_occ_curves(::PSY.StaticInjection, ::IOM.OfferDirection,
    ::IS.CostCurve{<:IS.TimeSeriesPiecewiseIncrementalCurve}) = nothing

_validate_occ_subtype(::PSY.MarketBidCost, ::IOM.OfferDirection, ::IS.CostCurve, args...) =
    nothing

function _validate_occ_subtype(
    ::PSY.ImportExportCost,
    ::IOM.OfferDirection,
    curve::IS.CostCurve,
    args...,
)
    !iszero(IS.get_vom_cost(curve)) && throw(
        ArgumentError(
            "For ImportExportCost, VOM cost must be zero.",
        ),
    )
    !iszero(IS.get_initial_input(curve)) && throw(
        ArgumentError(
            "For ImportExportCost, initial input must be zero.",
        ),
    )
    fd = IS.get_function_data(IS.get_value_curve(curve))
    if !iszero(first(IS.get_x_coords(fd)))
        throw(
            ArgumentError(
                "For ImportExportCost, the first breakpoint must be zero.",
            ),
        )
    end
end

function IOM.validate_occ_component(
    ::Type{<:StartupCostParameter},
    device::PSY.StaticInjection,
)
    op_cost = PSY.get_operation_cost(device)
    # TS types are validated at parameter population time
    IOM._is_time_series_cost(op_cost) && return
    startup = PSY.get_start_up(op_cost)
    if startup isa Union{NTuple{3, Float64}, PSY.StartUpStages}
        @warn "Multi-start costs detected for non-multi-start unit $(IS.get_name(device)), will take the maximum"
    elseif !(startup isa Float64)
        throw(
            ArgumentError(
                "Expected Float64, NTuple{3, Float64}, or StartUpStages startup cost but got $(typeof(startup)) for $(IS.get_name(device))",
            ),
        )
    end
    return
end

function IOM.validate_occ_component(
    ::Type{<:ShutdownCostParameter},
    device::PSY.StaticInjection,
)
    op_cost = PSY.get_operation_cost(device)
    # TS types are validated at parameter population time
    IOM._is_time_series_cost(op_cost) && return
    # Static MBC: shut_down is LinearCurve; ThermalGenerationCost: shut_down is Float64
    shutdown = PSY.get_shut_down(op_cost)
    if shutdown isa IS.LinearCurve
        return  # valid
    elseif shutdown isa Float64
        return  # valid (e.g. ThermalGenerationCost)
    else
        throw(
            ArgumentError(
                "Expected Float64 or LinearCurve shutdown cost but got $(typeof(shutdown)) for $(IS.get_name(device))",
            ),
        )
    end
end

# Consistency of initial_input vs offer curves is guaranteed by the static/TS type split
IOM.validate_occ_component(::Type{<:AbstractCostAtMinParameter}, ::PSY.StaticInjection) =
    nothing

IOM.validate_occ_component(
    ::Type{<:IncrementalPiecewiseLinearBreakpointParameter},
    device::PSY.StaticInjection,
) = IOM.validate_occ_breakpoints_slopes(device, IOM.IncrementalOffer())

IOM.validate_occ_component(
    ::Type{<:DecrementalPiecewiseLinearBreakpointParameter},
    device::PSY.StaticInjection,
) = IOM.validate_occ_breakpoints_slopes(device, IOM.DecrementalOffer())

# Slope and breakpoint validations are done together, nothing to do here
IOM.validate_occ_component(
    ::Type{<:AbstractPiecewiseLinearSlopeParameter},
    device::PSY.StaticInjection,
) = nothing

#################################################################################
# Section 7: Parameter Processing Orchestration
#################################################################################

function _process_occ_parameters_helper(
    ::Type{P},
    container::OptimizationContainer,
    model,
    devices,
) where {P <: ParameterType}
    for device in devices
        IOM.validate_occ_component(P, device)
    end
    if IOM._consider_parameter(P, container, model)
        ts_devices =
            filter(device -> _has_parameter_time_series(device), devices)
        (length(ts_devices) > 0) && add_parameters!(container, P, ts_devices, model)
    end
end

"Validate ImportExportCosts and add the appropriate parameters"
function process_import_export_parameters!(
    container::OptimizationContainer,
    devices_in,
    model::DeviceModel,
)
    devices = [d for d in devices_in if _has_import_export_cost(d)]

    for param in (
        IncrementalPiecewiseLinearSlopeParameter,
        IncrementalPiecewiseLinearBreakpointParameter,
        DecrementalPiecewiseLinearSlopeParameter,
        DecrementalPiecewiseLinearBreakpointParameter,
    )
        _process_occ_parameters_helper(param, container, model, devices)
    end
end

"Validate MarketBidCosts and add the appropriate parameters"
function process_market_bid_parameters!(
    container::OptimizationContainer,
    devices_in,
    model::DeviceModel,
    incremental::Bool = true,
    decremental::Bool = false,
)
    devices = [d for d in devices_in if _has_market_bid_cost(d)]
    isempty(devices) && return

    for param in (
        StartupCostParameter,
        ShutdownCostParameter,
    )
        _process_occ_parameters_helper(param, container, model, devices)
    end
    if incremental
        for param in (
            IncrementalCostAtMinParameter,
            IncrementalPiecewiseLinearSlopeParameter,
            IncrementalPiecewiseLinearBreakpointParameter,
        )
            _process_occ_parameters_helper(param, container, model, devices)
        end
    end
    if decremental
        for param in (
            DecrementalCostAtMinParameter,
            DecrementalPiecewiseLinearSlopeParameter,
            DecrementalPiecewiseLinearBreakpointParameter,
        )
            _process_occ_parameters_helper(param, container, model, devices)
        end
    end
end

#################################################################################
# Section 10: Static-curve PWL Data Retrieval
# (The TS-curve branch lives in IOM because it only uses IS types.)
#################################################################################

function IOM._get_pwl_data(
    dir::IOM.OfferDirection,
    container::OptimizationContainer,
    component::T,
    time::Int;
    meta = IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: IS.InfrastructureSystemsComponent}
    name = IS.get_name(component)
    cost_data = get_offer_curves(dir, component)
    breakpoint_cost_component, slope_cost_component, unit_system =
        IOM._get_raw_pwl_data(dir, container, T, name, cost_data, time; meta = meta)

    breakpoints, slopes = IOM.get_piecewise_curve_per_system_unit(
        breakpoint_cost_component,
        slope_cost_component,
        unit_system,
        get_model_base_power(container),
        PSY.get_base_power(component, PSY.NU),
    )
    return breakpoints, slopes
end

# static curve: read directly from the cost curve. `meta` is accepted (and
# ignored) so the kwarg threaded by `_get_pwl_data` resolves for either branch.
function IOM._get_raw_pwl_data(
    ::IOM.OfferDirection,
    ::OptimizationContainer,
    ::Type{<:IS.InfrastructureSystemsComponent},
    ::String,
    cost_data::IS.CostCurve{IS.PiecewiseIncrementalCurve},
    ::Int;
    meta = IOM.CONTAINER_KEY_EMPTY_META,
)
    cost_component = IS.get_function_data(IS.get_value_curve(cost_data))
    return IS.get_x_coords(cost_component),
    IS.get_y_coords(cost_component),
    IS.get_power_units(cost_data)
end

#################################################################################
# Section 11: Static PSY.OfferCurveCost objective entry points
#################################################################################

"""
Add PWL objective terms using the **delta (incremental/block-offer) formulation** for
static (non-time-series-backed) PSY.OfferCurveCost cost functions.
"""
function IOM.add_pwl_term_delta!(
    dir::IOM.OfferDirection,
    container::OptimizationContainer,
    component::T,
    ::PSY.OfferCurveCost,
    ::Type{U},
    ::Type{V},
) where {
    T <: IS.InfrastructureSystemsComponent,
    U <: VariableType,
    V <: AbstractDeviceFormulation,
}
    W = IOM._block_offer_var(dir)
    X = IOM._block_offer_constraint(dir)

    name = IS.get_name(component)
    resolution = get_resolution(container)
    dt = Dates.value(resolution) / MILLISECONDS_IN_HOUR
    time_steps = get_time_steps(container)
    is_variant = IOM.is_time_variant(get_offer_curves(dir, component))
    # Static offer curves are time-invariant: compute breakpoints/slopes once.
    static_breakpoints, static_slopes = if is_variant
        (Float64[], Float64[])
    else
        IOM._get_pwl_data(dir, container, component, first(time_steps))
    end
    for t in time_steps
        breakpoints, slopes = if is_variant
            IOM._get_pwl_data(dir, container, component, t)
        else
            (static_breakpoints, static_slopes)
        end
        pwl_vars =
            add_pwl_variables_delta!(
                container,
                W,
                T,
                name,
                t,
                length(slopes);
                upper_bound = Inf,
            )
        add_pwl_constraint_delta!(
            container,
            component,
            U,
            V,
            breakpoints,
            pwl_vars,
            t,
            X,
        )
        pwl_cost =
            get_pwl_cost_expression_delta(pwl_vars, slopes, IOM._objective_sign(dir) * dt)

        add_cost_to_expression!(
            container,
            ProductionCostExpression,
            pwl_cost,
            T,
            name,
            t,
        )

        if is_variant
            IOM.add_to_objective_variant_expression!(container, pwl_cost)
        else
            IOM.add_to_objective_invariant_expression!(container, pwl_cost)
        end
    end
end

function IOM.add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{T},
    component::IS.InfrastructureSystemsComponent,
    cost_function::PSY.OfferCurveCost,
    ::Type{U},
) where {T <: VariableType, U <: AbstractDeviceFormulation}
    component_name = IS.get_name(component)
    @debug "Market Bid" _group = LOG_GROUP_COST_FUNCTIONS component_name
    # Build-context form, as above: presence-only would reject the inert series a one-sided
    # bid stores on its unoffered side.
    if IOM.is_nontrivial_offer(container, component, get_input_offer_curves(cost_function))
        throw(
            ArgumentError(
                "Component $(component_name) is not allowed to participate as a demand.",
            ),
        )
    end
    IOM.add_pwl_term_delta!(
        IOM.IncrementalOffer(),
        container,
        component,
        cost_function,
        T,
        U,
    )
    return
end

# Default: most formulations use incremental offers
IOM._vom_offer_direction(::Type{<:AbstractDeviceFormulation}) = IOM.IncrementalOffer()

function IOM._add_vom_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{T},
    component::IS.InfrastructureSystemsComponent,
    op_cost::PSY.OfferCurveCost,
    ::Type{U},
) where {T <: VariableType, U <: AbstractDeviceFormulation}
    dir = IOM._vom_offer_direction(U)
    cost_curves = get_offer_curves(dir, op_cost)
    if IOM.is_time_variant(cost_curves)
        @warn "$(typeof(dir)) curves are time variant, there is no VOM cost source. Skipping VOM cost."
        return
    end
    _add_vom_cost_to_objective_helper!(
        container, T, component, op_cost, cost_curves, U)
    return
end

function _add_vom_cost_to_objective_helper!(
    container::OptimizationContainer,
    ::Type{T},
    component::IS.InfrastructureSystemsComponent,
    ::PSY.OfferCurveCost,
    cost_data::IS.CostCurve{IS.PiecewiseIncrementalCurve},
    ::Type{U},
) where {T <: VariableType, U <: AbstractDeviceFormulation}
    power_units = IS.get_power_units(cost_data)
    cost_term = IS.get_proportional_term(IS.get_vom_cost(cost_data))
    IOM.add_proportional_cost_invariant!(
        container, T, component, cost_term, power_units, 1.0, VOMCostExpression)
    return
end

#################################################################################
# Section 12: IOM extension-point bridges
# IOM declares `get_base_power`, `get_operation_cost`, etc. as abstract stubs so
# it doesn't depend on PowerSystems. POM provides the methods that forward to
# the corresponding PSY getters for PSY component and cost types.
#################################################################################

# IS4 made units explicit on getters. System base power is the MVA anchor
# (`PSY.NU`); device power/limit getters are read in system-per-unit (`PSY.SU`),
# reproducing the SYSTEM_BASE context the build used to set statefully. The
# one-arg component `get_base_power(c, PSY.NU)` is the device MVA base and is unchanged.
IOM.get_base_power(sys::PSY.System) = PSY.get_base_power(sys, PSY.NU)
IOM.get_base_power(c::PSY.Component) = PSY.get_base_power(c, PSY.NU)
IOM.get_operation_cost(c::PSY.Component) = PSY.get_operation_cost(c)
IOM.get_must_run(c::PSY.Component) = PSY.get_must_run(c)
IOM.get_active_power_limits(c::PSY.Component) = PSY.get_active_power_limits(c, PSY.SU)
# `RenewableGen` has no `active_power_limits` field: return (0.0, max_active_power)
IOM.get_active_power_limits(c::PSY.RenewableGen) =
    (min = 0.0, max = PSY.get_max_active_power(c, PSY.SU))
IOM.get_max_active_power(c::PSY.Component) = PSY.get_max_active_power(c, PSY.SU)
IOM.get_ramp_limits(c::PSY.Component) = PSY.get_ramp_limits(c, PSY.SU)
IOM.get_start_up(op_cost) = PSY.get_start_up(op_cost)
IOM.get_shut_down(op_cost) = PSY.get_shut_down(op_cost)
IOM.get_dc_bus(c::PSY.Component) = PSY.get_dc_bus(c)
IOM.get_bustype(c::PSY.ACBus) = PSY.get_bustype(c)
IOM.has_service(c::PSY.Component, args...) = PSY.has_service(c, args...)

# PSY.System override for the forecast-initial-timestamp adapter that IOM uses in
# init_optimization_container!. The stateful unit-system adapters were dropped: IS4
# made units explicit on getters, so IOM no longer normalizes the system to
# SYSTEM_BASE during the build.
IOM.temp_get_forecast_initial_timestamp(sys::PSY.System) =
    PSY.get_forecast_initial_timestamp(sys)

# PSY.System bridges for IOM system-query stubs (see IOM common_models/interfaces.jl).
# These forward to PSY's public API so IOM never has to touch sys.data.

IOM.stores_time_series_in_memory(sys::PSY.System) = PSY.stores_time_series_in_memory(sys)
IOM.get_time_series_resolutions(sys::PSY.System) = PSY.get_time_series_resolutions(sys)
IOM.get_time_series_counts(sys::PSY.System) = PSY.get_time_series_counts(sys)
IOM.get_forecast_interval(sys::PSY.System) = PSY.get_forecast_interval(sys)
IOM.get_forecast_horizon(sys::PSY.System; kwargs...) =
    PSY.get_forecast_horizon(sys; kwargs...)
IOM.get_forecast_summary_table(sys::PSY.System) = PSY.get_forecast_summary_table(sys)
IOM.transform_single_time_series!(
    sys::PSY.System,
    horizon::Dates.Period,
    interval::Dates.Period;
    kwargs...,
) = PSY.transform_single_time_series!(sys, horizon, interval; kwargs...)
# The system's own UUID (`System.metadata.uuid`) — IOM uses this as a filename identifier.
IOM.get_system_uuid(sys::PSY.System) = PSY.get_system_uuid(sys)
# PSY.get_components restricts T <: PSY.Component; IOM passes IS.InfrastructureSystemsComponent.
# Bridge directly to IS.get_components to preserve the looser typing.
IOM.get_subsystem_components(
    ::Type{T},
    sys::PSY.System;
    subsystem_name = nothing,
) where {T <: IS.InfrastructureSystemsComponent} =
    IS.get_components(T, sys.data; subsystem_name)

# PSY doesn't expose get_time_series_counts_by_type publicly; reach through sys.data here.
IOM.get_time_series_counts_by_type(sys::PSY.System) =
    IS.get_time_series_counts_by_type(sys.data)

# PSY cost-type dispatches for variable-cost and get_variable_cost:
IOM.get_variable_cost(cost) = PSY.get_variable_operation_cost(cost)

# Not really market bid related--better spot?
IOM.component_for_hvdc_interpolation(::Nothing) = PSY.DCBus
IOM.component_for_network_dual(::Nothing) = PSY.ACBus
