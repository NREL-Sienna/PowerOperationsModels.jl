requires_initialization(::AbstractHybridFormulation) = false

#################################################################################
# Default time-series and attributes
#################################################################################

function get_default_time_series_names(
    ::Type{PSY.HybridSystem},
    ::Type{<:Union{FixedOutput, AbstractHybridFormulation}},
)
    return Dict{Type{<:TimeSeriesParameter}, String}(
        HybridRenewableActivePowerTimeSeriesParameter => "RenewableDispatch__max_active_power",
        HybridElectricLoadTimeSeriesParameter => "PowerLoad__max_active_power",
    )
end

function get_default_attributes(
    ::Type{PSY.HybridSystem},
    ::Type{<:Union{FixedOutput, AbstractHybridFormulation}},
)
    return Dict{String, Any}(
        "reservation" => true,
        "storage_reservation" => true,
        "energy_target" => false,
        "regularization" => false,
    )
end

# Small fixed cost rate on regularization slacks. Mirrors HSS REG_COST.
const HYBRID_REGULARIZATION_COST = 1e-3

#################################################################################
# PCC variables — ActivePowerInVariable / ActivePowerOutVariable
#################################################################################

get_variable_binary(
    ::Type{ActivePowerInVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{ActivePowerInVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_input_active_power_limits(d, PSY.SU).min
get_variable_upper_bound(
    ::Type{ActivePowerInVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_input_active_power_limits(d, PSY.SU).max
get_variable_multiplier(
    ::Type{ActivePowerInVariable},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = -1.0

get_variable_binary(
    ::Type{ActivePowerOutVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{ActivePowerOutVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_output_active_power_limits(d, PSY.SU).min
get_variable_upper_bound(
    ::Type{ActivePowerOutVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_output_active_power_limits(d, PSY.SU).max
get_variable_multiplier(
    ::Type{ActivePowerOutVariable},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = 1.0

get_variable_binary(
    ::Type{ReactivePowerVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
function get_variable_lower_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    limits = PSY.get_reactive_power_limits(d, PSY.SU)
    return limits === nothing ? nothing : limits.min
end
function get_variable_upper_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    limits = PSY.get_reactive_power_limits(d, PSY.SU)
    return limits === nothing ? nothing : limits.max
end
get_variable_multiplier(
    ::Type{ReactivePowerVariable},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = 1.0

get_variable_binary(
    ::Type{ReservationVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = true

get_min_max_limits(
    d::PSY.HybridSystem,
    ::Type{InputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_input_active_power_limits(d, PSY.SU)
get_min_max_limits(
    d::PSY.HybridSystem,
    ::Type{OutputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_output_active_power_limits(d, PSY.SU)
get_min_max_limits(
    d::PSY.HybridSystem,
    ::Type{ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_reactive_power_limits(d, PSY.SU)

#################################################################################
# Subcomponent power variables
#################################################################################

get_variable_binary(
    ::Type{HybridThermalActivePower},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridThermalActivePower},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
get_variable_upper_bound(
    ::Type{HybridThermalActivePower},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_active_power_limits(PSY.get_thermal_unit(d), PSY.SU).max

get_variable_binary(
    ::Type{HybridRenewableActivePower},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridRenewableActivePower},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
get_variable_upper_bound(
    ::Type{HybridRenewableActivePower},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_max_active_power(PSY.get_renewable_unit(d), PSY.SU)

get_variable_binary(
    ::Type{HybridStorageSubcomponentPower{ChargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridStorageSubcomponentPower{ChargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
get_variable_upper_bound(
    ::Type{HybridStorageSubcomponentPower{ChargeSide}},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_input_active_power_limits(PSY.get_storage(d), PSY.SU).max

get_variable_binary(
    ::Type{HybridStorageSubcomponentPower{DischargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridStorageSubcomponentPower{DischargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
get_variable_upper_bound(
    ::Type{HybridStorageSubcomponentPower{DischargeSide}},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_output_active_power_limits(PSY.get_storage(d), PSY.SU).max

get_variable_binary(
    ::Type{HybridStorageReservation},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = true

get_variable_binary(
    ::Type{RegularizationVariable{ChargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{RegularizationVariable{ChargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0

get_variable_binary(
    ::Type{RegularizationVariable{DischargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{RegularizationVariable{DischargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0

# Storage energy state on the hybrid (uses POM's standard EnergyVariable, keyed by HybridSystem)
get_variable_binary(
    ::Type{EnergyVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{EnergyVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) =
    PSY.get_storage_level_limits(PSY.get_storage(d)).min *
    PSY.get_storage_capacity(PSY.get_storage(d), PSY.SU) *
    PSY.get_conversion_factor(PSY.get_storage(d))
get_variable_upper_bound(
    ::Type{EnergyVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) =
    PSY.get_storage_level_limits(PSY.get_storage(d)).max *
    PSY.get_storage_capacity(PSY.get_storage(d), PSY.SU) *
    PSY.get_conversion_factor(PSY.get_storage(d))
get_variable_warm_start_value(
    ::Type{EnergyVariable},
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) =
    PSY.get_initial_storage_capacity_level(PSY.get_storage(d)) *
    PSY.get_storage_capacity(PSY.get_storage(d), PSY.SU) *
    PSY.get_conversion_factor(PSY.get_storage(d))

# End-of-period energy-target slacks (added when `energy_target = true`). Non-negative,
# defined only at the final time step. Mirrors POM storage's slack variables at
# energy_storage_models/storage_models.jl:376-402, keyed by HybridSystem.
function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    ::Type{<:AbstractHybridFormulation},
) where {
    T <: Union{HybridEnergyShortageVariable, HybridEnergySurplusVariable},
    U <: PSY.HybridSystem,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    last_time_range = time_steps[end]:time_steps[end]
    variable = add_variable_container!(
        container,
        T,
        U,
        PSY.get_name.(devices),
        last_time_range,
    )
    for d in devices
        PSY.get_storage(d) === nothing && continue
        name = PSY.get_name(d)
        variable[name, time_steps[end]] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_{$(PSY.get_name(d))}",
            lower_bound = 0.0
        )
    end
    return
end

# Thermal commitment OnVariable on a hybrid (binary)
get_variable_binary(
    ::Type{OnVariable},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = true
get_variable_lower_bound(
    ::Type{OnVariable},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = nothing
get_variable_upper_bound(
    ::Type{OnVariable},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = nothing

#################################################################################
# Reserve variables — bounds and binary flags
#################################################################################

get_variable_binary(
    ::Type{
        <:Union{
            AbstractHybridSubcomponentInjectorReserveVariableType,
            HybridStorageSubcomponentReserveVariable,
        },
    },
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{
        <:Union{
            AbstractHybridSubcomponentInjectorReserveVariableType,
            HybridStorageSubcomponentReserveVariable,
        },
    },
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0

# Per-subcomponent reserve upper bounds: limited by the subcomponent's headroom × the service's max output fraction
function get_variable_upper_bound(
    ::Type{HybridThermalReserveVariable},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) *
           PSY.get_active_power_limits(PSY.get_thermal_unit(d), PSY.SU).max
end
function get_variable_upper_bound(
    ::Type{HybridRenewableReserveVariable},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) *
           PSY.get_max_active_power(PSY.get_renewable_unit(d), PSY.SU)
end
function get_variable_upper_bound(
    ::Type{HybridStorageSubcomponentReserveVariable{ChargeSide}},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) *
           PSY.get_input_active_power_limits(PSY.get_storage(d), PSY.SU).max
end
function get_variable_upper_bound(
    ::Type{HybridStorageSubcomponentReserveVariable{DischargeSide}},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) *
           PSY.get_output_active_power_limits(PSY.get_storage(d), PSY.SU).max
end

# Hybrid PCC reserve variables — limited by the hybrid's PCC limits × max_output_fraction
get_variable_binary(
    ::Type{HybridPCCReserveVariable{DischargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridPCCReserveVariable{DischargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
function get_variable_upper_bound(
    ::Type{HybridPCCReserveVariable{DischargeSide}},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) *
           PSY.get_output_active_power_limits(d, PSY.SU).max
end

get_variable_binary(
    ::Type{HybridPCCReserveVariable{ChargeSide}},
    ::Type{PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = false
get_variable_lower_bound(
    ::Type{HybridPCCReserveVariable{ChargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = 0.0
function get_variable_upper_bound(
    ::Type{HybridPCCReserveVariable{ChargeSide}},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
)
    return PSY.get_max_output_fraction(r) * PSY.get_input_active_power_limits(d, PSY.SU).max
end

# Multipliers used by reserve aggregations (Out side gets +1; In side handled via separate dispatch in add_to_expression)
get_variable_multiplier(
    ::Type{
        <:Union{
            AbstractHybridSubcomponentInjectorReserveVariableType,
            HybridStorageSubcomponentReserveVariable,
        },
    },
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulationWithReserves},
    ::PSY.Reserve,
) = 1.0
get_variable_multiplier(
    ::Type{HybridPCCReserveVariable{DischargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulationWithReserves},
    ::PSY.Reserve,
) = 1.0
get_variable_multiplier(
    ::Type{HybridPCCReserveVariable{ChargeSide}},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulationWithReserves},
    ::PSY.Reserve,
) = 1.0

# When the system-side ActivePowerReserveVariable is added by the service constructor for a HybridSystem,
# direct it into the TotalReserveOffering channel keyed by HybridSystem (mirrors POM storage line 59).
get_expression_type_for_reserve(
    ::Type{ActivePowerReserveVariable},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:PSY.Reserve},
) = TotalReserveOffering

function get_variable_upper_bound(
    ::Type{ActivePowerReserveVariable},
    r::PSY.Reserve,
    d::PSY.HybridSystem,
    ::Type{<:AbstractReservesFormulation},
)
    return PSY.get_max_output_fraction(r) * (
        PSY.get_output_active_power_limits(d, PSY.SU).max +
        PSY.get_input_active_power_limits(d, PSY.SU).max
    )
end

# Disambiguate against the generic ORDC method in services_models/reserves.jl.
function get_variable_upper_bound(
    ::Type{ActivePowerReserveVariable},
    r::Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve},
    d::PSY.HybridSystem,
    ::Type{<:AbstractReservesFormulation},
)
    return PSY.get_output_active_power_limits(d, PSY.SU).max +
           PSY.get_input_active_power_limits(d, PSY.SU).max
end

#################################################################################
# Time-series parameter multipliers
#################################################################################

get_multiplier_value(
    ::HybridRenewableActivePowerTimeSeriesParameter,
    d::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) = PSY.get_max_active_power(PSY.get_renewable_unit(d), PSY.SU)

get_multiplier_value(
    ::HybridElectricLoadTimeSeriesParameter,
    d::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) = PSY.get_max_active_power(PSY.get_electric_load(d), PSY.SU)

get_parameter_multiplier(
    ::HybridRenewableActivePowerTimeSeriesParameter,
    ::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) = 1.0
get_parameter_multiplier(
    ::HybridElectricLoadTimeSeriesParameter,
    ::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) = 1.0

#################################################################################
# Initial conditions
#################################################################################

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{T, <:AbstractHybridFormulation},
) where {T <: PSY.HybridSystem} = model

initial_condition_default(
    ::InitialEnergyLevel,
    d::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) =
    PSY.get_initial_storage_capacity_level(PSY.get_storage(d)) *
    PSY.get_storage_capacity(PSY.get_storage(d), PSY.SU) *
    PSY.get_conversion_factor(PSY.get_storage(d))

initial_condition_variable(
    ::InitialEnergyLevel,
    d::PSY.HybridSystem,
    ::AbstractHybridFormulation,
) = EnergyVariable()

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    formulation::AbstractHybridFormulation,
) where {T <: PSY.HybridSystem}
    storage_devices = [d for d in devices if PSY.get_storage(d) !== nothing]
    if !isempty(storage_devices)
        add_initial_condition!(
            container,
            storage_devices,
            formulation,
            InitialEnergyLevel(),
        )
    end
    return
end

#################################################################################
# Specialized add_variables! for the per-service reserve variables.
#
# These variables are indexed by (service_type, service_name) in addition to
# (component_name, time). Mirrors POM storage's pattern at
# energy_storage_models/storage_models.jl:409–445.
#################################################################################

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    ::Type{F},
) where {
    T <: AbstractHybridReserveVariableType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    F <: AbstractHybridFormulation,
} where {D <: PSY.HybridSystem}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    services = Set{PSY.Service}()
    for d in devices
        union!(services, PSY.get_services(d))
    end
    isempty(services) && return
    for service in services
        # Restrict to devices that participate in this service
        participating = [d for d in devices if service in PSY.get_services(d)]
        isempty(participating) && continue
        variable = add_variable_container!(container, T,
            D,
            PSY.get_name.(participating),
            time_steps;
            meta = "$(typeof(service))_$(PSY.get_name(service))",
        )
        for d in participating, t in time_steps
            name = PSY.get_name(d)
            variable[name, t] = JuMP.@variable(
                get_jump_model(container),
                base_name = "$(T)_$(PSY.get_name(service))_{$(name), $(t)}",
                lower_bound = 0.0,
                upper_bound = get_variable_upper_bound(T, service, d, F),
            )
        end
    end
    return
end

#################################################################################
# Objective-function multipliers (positive — we minimize cost)
#################################################################################

objective_function_multiplier(::Type{<:VariableType}, ::Type{<:AbstractHybridFormulation}) =
    OBJECTIVE_FUNCTION_POSITIVE

#################################################################################
# PCC active-power balance: ActivePowerInVariable / ActivePowerOutVariable into
# the network's ActivePowerBalance expression.
#
# These delegate to POM's existing common_models/add_to_expression.jl methods,
# which dispatch on (ExpressionType, VariableType, AbstractDeviceFormulation).
# Because AbstractHybridFormulation <: IOM.AbstractDeviceFormulation, the
# generic methods work for HybridSystem out of the box. The methods here are
# left documented but not redefined to avoid ambiguity.
#################################################################################

#################################################################################
# Reserve term accumulation — unified across hybrid PCC and storage subcomponent.
#
# The parametric ReserveAggregationExpression{Direction, Scale, Side} family lets
# one helper handle both the hybrid-boundary aggregation (HybridPCCReserveVariable{DischargeSide}/In
# into HybridPCCReserveExpression{...}) and the storage-subcomponent aggregation
# (HybridStorageSubcomponentReserveVariable{ChargeSide}/Discharging... into StorageReserveBalanceExpression{...}).
# Mismatched-direction services are filtered out by dispatch on the Direction parameter
# of the expression type vs the Reserve direction (ReserveUp / ReserveDown).
# The Scale parameter (UnscaledReserve / DeployedReserve) drives the multiplier scale.
#################################################################################

# Multiplier scale: UnscaledReserve → 1.0; DeployedReserve → deployed_fraction(service).
_reserve_scale(
    ::Type{<:ReserveAggregationExpression{<:PSY.ReserveDirection, UnscaledReserve}},
    ::PSY.Service,
) = 1.0
_reserve_scale(
    ::Type{<:ReserveAggregationExpression{<:PSY.ReserveDirection, DeployedReserve}},
    s::PSY.Service,
) = PSY.get_deployed_fraction(s)

# Up-direction expressions: ReserveDown services are a no-op (skipped via dispatch).
_add_reserve_term!(
    ::Type{<:ReserveAggregationExpression{PSY.ReserveUp}},
    ::OptimizationContainer,
    _expression,
    ::Type{<:AbstractHybridReserveVariableType},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulationWithReserves},
    ::Int,
    ::PSY.Reserve{PSY.ReserveDown},
) = nothing

# Down-direction expressions: ReserveUp services are a no-op (skipped via dispatch).
_add_reserve_term!(
    ::Type{<:ReserveAggregationExpression{PSY.ReserveDown}},
    ::OptimizationContainer,
    _expression,
    ::Type{<:AbstractHybridReserveVariableType},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulationWithReserves},
    ::Int,
    ::PSY.Reserve{PSY.ReserveUp},
) = nothing

# Fallback: actually accumulate the (correct-direction) reserve term.
function _add_reserve_term!(
    ::Type{T},
    container::OptimizationContainer,
    expression,
    ::Type{U},
    d::V,
    ::Type{W},
    t::Int,
    service::PSY.Service,
) where {
    T <: ReserveAggregationExpression,
    U <: AbstractHybridReserveVariableType,
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
}
    name = PSY.get_name(d)
    variable =
        get_variable(container, U, V, "$(typeof(service))_$(PSY.get_name(service))")
    mult = get_variable_multiplier(U, d, W, service) * _reserve_scale(T, service)
    add_proportional_to_jump_expression!(expression[name, t], variable[name, t], mult)
    return
end

# Single add_to_expression! method covering both PCC boundary and storage subcomponent.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel{V, W},
) where {
    T <: ReserveAggregationExpression,
    U <: AbstractHybridReserveVariableType,
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
}
    expression = get_expression(container, T, V)
    for d in devices, service in PSY.get_services(d), t in get_time_steps(container)
        _add_reserve_term!(T, container, expression, U, d, W, t, service)
    end
    return
end

# Variant signature retained for callers that also pass a NetworkModel (hybrid PCC path).
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: ReserveAggregationExpression,
    U <: AbstractHybridReserveVariableType,
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
}
    add_to_expression!(container, T, U, devices, model)
    return
end

# Hybrid storage subcomponent feeds TotalReserveOffering keyed by HybridSystem.
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{TotalReserveOffering},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, W},
) where {
    U <: HybridStorageSubcomponentReserveVariable,
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
}
    time_steps = get_time_steps(container)
    for d in devices
        name = PSY.get_name(d)
        for service in PSY.get_services(d)
            expression = get_expression(container, TotalReserveOffering, V,
                "$(typeof(service))_$(PSY.get_name(service))")
            variable =
                get_variable(container, U, V, "$(typeof(service))_$(PSY.get_name(service))")
            mult = get_variable_multiplier(U, d, W, service)
            for t in time_steps
                add_proportional_to_jump_expression!(
                    expression[name, t],
                    variable[name, t],
                    mult,
                )
            end
        end
    end
    return
end

# Service-side: ActivePowerReserveVariable subtracted from per-hybrid TotalReserveOffering
# (mirrors storage_models.jl:781–808 pattern).
function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    service::V,
    devices::Vector{UV},
    service_model::ServiceModel{V, W},
) where {
    T <: TotalReserveOffering,
    U <: ActivePowerReserveVariable,
    UV <: PSY.HybridSystem,
    V <: PSY.Reserve,
    W <: AbstractReservesFormulation,
}
    s_name = PSY.get_name(service)
    variable = get_variable(container, U, V)
    for d in devices
        name = PSY.get_name(d)
        # Key on the concrete `typeof(service)` (as the creation site and every sibling lookup do):
        # for ReserveDemandCurve the ServiceModel type param `V` drops the unit-system parameter,
        # so keying on `V` would miss the stored expression.
        expression = get_expression(container, T, UV, "$(typeof(service))_$(s_name)")
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                expression[name, t],
                variable[(s_name, name, t)],
                -1.0,
            )
        end
    end
    return
end
#################################################################################
# Subcomponent (thermal / renewable) reserve accumulators — unified family.
#
# A single helper covers both thermal and renewable subcomponent reserve
# accumulation into a JuMP.AffExpr. The reserve variable type
# (U <: AbstractHybridSubcomponentInjectorReserveVariableType) selects which
# subcomponent we're aggregating, and the direction marker (Up / Down)
# filters out mismatched-direction services via dispatch.
#
# Callers in HybridThermalReserveLimitConstraint and HybridRenewableReserveLimit-
# Constraint invoke _subcomponent_reserve_expr(Up | ReserveDown, container,
# HybridThermalReserveVariable | HybridRenewableReserveVariable, d, t, services).
#################################################################################

# Up direction: ReserveDown service is a no-op.
_subcomponent_reserve_term!(
    ::Type{PSY.ReserveUp},
    ::JuMP.AffExpr,
    ::OptimizationContainer,
    ::Type{<:AbstractHybridSubcomponentInjectorReserveVariableType},
    ::PSY.HybridSystem,
    ::Int,
    ::PSY.Reserve{PSY.ReserveDown},
) = nothing

# Down direction: ReserveUp service is a no-op.
_subcomponent_reserve_term!(
    ::Type{PSY.ReserveDown},
    ::JuMP.AffExpr,
    ::OptimizationContainer,
    ::Type{<:AbstractHybridSubcomponentInjectorReserveVariableType},
    ::PSY.HybridSystem,
    ::Int,
    ::PSY.Reserve{PSY.ReserveUp},
) = nothing

# Fallback: accumulate the term for the correct-direction service.
function _subcomponent_reserve_term!(
    ::Type{<:PSY.ReserveDirection},
    expr::JuMP.AffExpr,
    container::OptimizationContainer,
    ::Type{U},
    d::V,
    t::Int,
    service::PSY.Service,
) where {
    U <: AbstractHybridSubcomponentInjectorReserveVariableType,
    V <: PSY.HybridSystem,
}
    s_name = PSY.get_name(service)
    s_type = typeof(service)
    key = VariableKey(U, V, "$(s_type)_$s_name")
    haskey(IOM.get_variables(container), key) || return
    var = get_variable(container, U, V, "$(s_type)_$s_name")
    add_proportional_to_jump_expression!(expr, var[PSY.get_name(d), t], 1.0)
    return
end

function _subcomponent_reserve_expr(
    ::Type{Dir},
    container::OptimizationContainer,
    ::Type{U},
    d::V,
    t::Int,
    services,
) where {
    Dir <: PSY.ReserveDirection,
    U <: AbstractHybridSubcomponentInjectorReserveVariableType,
    V <: PSY.HybridSystem,
}
    expr = JuMP.AffExpr(0.0)
    for service in services
        _subcomponent_reserve_term!(Dir, expr, container, U, d, t, service)
    end
    return expr
end

#################################################################################
# Thermal subcomponent constraints for HybridSystem.
#
# Mirrors HSS add_constraints.jl _add_thermallimit_withreserves! (lines 1477–1506)
# for the with-reserves case, and _add_thermal_on_variable_constraints! for the
# no-reserves case. Walks PSY.get_thermal_unit(d) for the thermal unit's limits.
#################################################################################

"""
Range constraint on the thermal subcomponent's active power, accounting for
up/down reserve allocations. Mirrors HSS `ThermalReserveLimit` (HSS
add_constraints.jl:1495–1506).
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridThermalReserveLimitConstraint},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_th = get_variable(container, HybridThermalActivePower, V)
    on_var = get_variable(container, OnVariable, V)

    con_ub = add_constraints_container!(
        container,
        HybridThermalReserveLimitConstraint,
        V,
        names,
        time_steps;
        meta = "ub",
    )
    con_lb = add_constraints_container!(
        container,
        HybridThermalReserveLimitConstraint,
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        thermal_unit = PSY.get_thermal_unit(d)
        thermal_unit === nothing && continue
        limits = PSY.get_active_power_limits(thermal_unit, PSY.SU)
        services = PSY.get_services(d)
        r_up = _subcomponent_reserve_expr(
            PSY.ReserveUp,
            container,
            HybridThermalReserveVariable,
            d,
            t,
            services,
        )
        r_dn = _subcomponent_reserve_expr(
            PSY.ReserveDown,
            container,
            HybridThermalReserveVariable,
            d,
            t,
            services,
        )
        con_ub[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_th[name, t] + r_up <= limits.max * on_var[name, t]
        )
        con_lb[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_th[name, t] - r_dn >= limits.min * on_var[name, t]
        )
    end
    return
end

# Per-bound traits: which side of `lim` to use, and which JuMP relation to emit.
_thermal_on_limit(::Type{HybridThermalOnVariableConstraint{UpperBound}}, lim) = lim.max
_thermal_on_limit(::Type{HybridThermalOnVariableConstraint{LowerBound}}, lim) = lim.min
_thermal_on_relation(::Type{HybridThermalOnVariableConstraint{UpperBound}}, jm, lhs, rhs) =
    JuMP.@constraint(jm, lhs <= rhs)
_thermal_on_relation(::Type{HybridThermalOnVariableConstraint{LowerBound}}, jm, lhs, rhs) =
    JuMP.@constraint(jm, lhs >= rhs)

"""
Bound link between thermal subcomponent power and its commitment status
(no-reserves case). Parametric on `BoundDirection` (from IOM): `{UpperBound}` enforces
`p_th ≤ max · on_var`, `{LowerBound}` enforces `p_th ≥ min · on_var`.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: HybridThermalOnVariableConstraint,
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_th = get_variable(container, HybridThermalActivePower, V)
    on_var = get_variable(container, OnVariable, V)
    constraint = add_constraints_container!(container, T, V, names, time_steps)
    jm = get_jump_model(container)
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        thermal_unit = PSY.get_thermal_unit(d)
        thermal_unit === nothing && continue
        bound = _thermal_on_limit(T, PSY.get_active_power_limits(thermal_unit, PSY.SU))
        constraint[name, t] =
            _thermal_on_relation(T, jm, p_th[name, t], bound * on_var[name, t])
    end
    return
end
#################################################################################
# Renewable subcomponent constraints for HybridSystem.
#
# - HybridRenewableActivePowerLimitConstraint: cap renewable subcomponent power
#   at the time-series-derived available output (no-reserves and reserves cases
#   share this; the reserve-aware variant carves out reserves in the with-reserves
#   constraint).
# - HybridRenewableReserveLimitConstraint: range constraint on renewable power
#   accounting for up/down reserves. The accumulator is shared with the thermal
#   case via `_subcomponent_reserve_expr`, dispatching on the variable type.
#################################################################################

"""
Cap renewable subcomponent power at the time-series-derived available output
(0 ≤ p_renewable[t] ≤ multiplier · ts[t]).
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridRenewableActivePowerLimitConstraint},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_re = get_variable(container, HybridRenewableActivePower, V)

    re_param_key = ParameterKey(HybridRenewableActivePowerTimeSeriesParameter, V)
    re_param_container = if haskey(IOM.get_parameters(container), re_param_key)
        get_parameter(container, HybridRenewableActivePowerTimeSeriesParameter, V)
    else
        nothing
    end
    re_multiplier =
        re_param_container === nothing ? nothing :
        get_multiplier_array(re_param_container)

    constraint = add_constraints_container!(
        container,
        HybridRenewableActivePowerLimitConstraint,
        V,
        names,
        time_steps,
    )

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        renewable_unit = PSY.get_renewable_unit(d)
        renewable_unit === nothing && continue
        if re_param_container !== nothing
            re_ref = get_parameter_column_refs(re_param_container, name)[t]
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_re[name, t] <= re_multiplier[name, t] * re_ref
            )
        else
            max_p = PSY.get_max_active_power(renewable_unit, PSY.SU)
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_re[name, t] <= max_p
            )
        end
    end
    return
end

"""
Range constraint on renewable subcomponent power accounting for reserves.
Mirrors HSS `RenewableReserveLimit`.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridRenewableReserveLimitConstraint},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_re = get_variable(container, HybridRenewableActivePower, V)

    re_param_key = ParameterKey(HybridRenewableActivePowerTimeSeriesParameter, V)
    re_param_container = if haskey(IOM.get_parameters(container), re_param_key)
        get_parameter(container, HybridRenewableActivePowerTimeSeriesParameter, V)
    else
        nothing
    end
    re_multiplier =
        re_param_container === nothing ? nothing :
        get_multiplier_array(re_param_container)

    con_ub = add_constraints_container!(
        container,
        HybridRenewableReserveLimitConstraint,
        V,
        names,
        time_steps;
        meta = "ub",
    )
    con_lb = add_constraints_container!(
        container,
        HybridRenewableReserveLimitConstraint,
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        renewable_unit = PSY.get_renewable_unit(d)
        renewable_unit === nothing && continue
        services = PSY.get_services(d)
        r_up = _subcomponent_reserve_expr(
            PSY.ReserveUp,
            container,
            HybridRenewableReserveVariable,
            d,
            t,
            services,
        )
        r_dn = _subcomponent_reserve_expr(
            PSY.ReserveDown,
            container,
            HybridRenewableReserveVariable,
            d,
            t,
            services,
        )
        if re_param_container !== nothing
            re_ref = get_parameter_column_refs(re_param_container, name)[t]
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_re[name, t] + r_up <= re_multiplier[name, t] * re_ref
            )
        else
            max_p = PSY.get_max_active_power(renewable_unit, PSY.SU)
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_re[name, t] + r_up <= max_p
            )
        end
        con_lb[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_re[name, t] - r_dn >= 0.0
        )
    end
    return
end
#################################################################################
# Storage subcomponent constraints for HybridSystem (Option D core).
#
# Most methods re-emit POM's storage reserve constraint TYPES with new dispatches
# on V <: PSY.HybridSystem, substituting PSY.get_storage(hybrid) for hybrid at
# every PSY accessor. The constraint TYPES are reused (same names, same purpose,
# same shape); only the dispatch context changes. Hybrid-specific constraint
# types are introduced for the inner-storage status (charge/discharge mode) and
# the charge/discharge reserve power limits, since their math is subtly different
# from POM's storage versions.
#################################################################################

#################################################################################
# HybridStorageBalanceConstraint — energy balance with optional reserve deployment
#################################################################################

# With-reserves formulation: pick the body based on whether services are wired up.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridStorageBalanceConstraint},
    devices::U,
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    if has_service_model(model)
        _hybrid_storage_balance_with_reserves!(container, devices, model, network_model)
    else
        _hybrid_storage_balance_no_reserves!(container, devices, model, network_model)
    end
    return
end

# Plain hybrid formulation (no reserves): always the no-reserves body.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridStorageBalanceConstraint},
    devices::U,
    model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    _hybrid_storage_balance_no_reserves!(container, devices, model, network_model)
    return
end

function _hybrid_storage_balance_no_reserves!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.HybridSystem, W <: AbstractHybridFormulation, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(d) for d in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)
    p_ch = get_variable(container, HybridStorageSubcomponentPower{ChargeSide}, V)
    p_ds = get_variable(container, HybridStorageSubcomponentPower{DischargeSide}, V)
    constraint = add_constraints_container!(
        container,
        HybridStorageBalanceConstraint,
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        d = IOM.get_component(ic)
        storage = PSY.get_storage(d)
        storage === nothing && continue
        eff = PSY.get_efficiency(storage)
        name = PSY.get_name(d)
        constraint[name, 1] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, 1] ==
            get_value(ic) +
            (p_ch[name, 1] * eff.in - p_ds[name, 1] / eff.out) * fraction_of_hour
        )
        for t in time_steps[2:end]
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                energy_var[name, t] ==
                energy_var[name, t - 1] +
                (p_ch[name, t] * eff.in - p_ds[name, t] / eff.out) * fraction_of_hour
            )
        end
    end
    return
end

function _hybrid_storage_balance_with_reserves!(
    container::OptimizationContainer,
    devices,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(d) for d in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)
    p_ch = get_variable(container, HybridStorageSubcomponentPower{ChargeSide}, V)
    p_ds = get_variable(container, HybridStorageSubcomponentPower{DischargeSide}, V)
    r_up_ds = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
        V,
    )
    r_up_ch = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
        V,
    )
    r_dn_ds = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
        V,
    )
    r_dn_ch = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
        V,
    )
    constraint = add_constraints_container!(
        container,
        HybridStorageBalanceConstraint,
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        d = IOM.get_component(ic)
        storage = PSY.get_storage(d)
        storage === nothing && continue
        eff = PSY.get_efficiency(storage)
        name = PSY.get_name(d)
        constraint[name, 1] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, 1] ==
            get_value(ic) +
            (
                ((p_ch[name, 1] + r_dn_ch[name, 1] - r_up_ch[name, 1]) * eff.in) -
                ((p_ds[name, 1] + r_up_ds[name, 1] - r_dn_ds[name, 1]) / eff.out)
            ) * fraction_of_hour
        )
        for t in time_steps[2:end]
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                energy_var[name, t] ==
                energy_var[name, t - 1] +
                (
                    ((p_ch[name, t] + r_dn_ch[name, t] - r_up_ch[name, t]) * eff.in) -
                    ((p_ds[name, t] + r_up_ds[name, t] - r_dn_ds[name, t]) / eff.out)
                ) * fraction_of_hour
            )
        end
    end
    return
end

#################################################################################
# HybridStorageStatusOnConstraint{ChargeSide} / HybridStorageStatusOnConstraint{DischargeSide}
# (no-reserves case — mutually exclusive charge/discharge via the inner storage
# reservation variable)
#################################################################################

# Side-keyed traits shared by HybridStorageStatusOnConstraint{Sd} and
# HybridStorageReservePowerLimitConstraint{Sd} below.
# - ChargeSide   : input limits,  reservation factor (1 - ss).
# - DischargeSide: output limits, reservation factor ss.
const _StorageSideConstraint{Sd} = Union{
    HybridStorageStatusOnConstraint{Sd},
    HybridStorageReservePowerLimitConstraint{Sd},
}

_storage_side_power_var(::Type{<:_StorageSideConstraint{Sd}}) where {Sd <: ReserveSide} =
    HybridStorageSubcomponentPower{Sd}
_storage_side_max(::Type{<:_StorageSideConstraint{ChargeSide}}, s) =
    PSY.get_input_active_power_limits(s, PSY.SU).max
_storage_side_max(::Type{<:_StorageSideConstraint{DischargeSide}}, s) =
    PSY.get_output_active_power_limits(s, PSY.SU).max
# Reservation-binary factor applied to the side limit. Charge side flips ss → (1-ss).
_storage_side_ss_factor(::Type{<:_StorageSideConstraint{ChargeSide}}, ss_val) = 1 - ss_val
_storage_side_ss_factor(::Type{<:_StorageSideConstraint{DischargeSide}}, ss_val) = ss_val

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: HybridStorageStatusOnConstraint,
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_var = get_variable(container, _storage_side_power_var(T), V)
    ss = get_variable(container, HybridStorageReservation, V)
    constraint = add_constraints_container!(container, T, V, names, time_steps)
    for d in devices, t in time_steps
        storage = PSY.get_storage(d)
        storage === nothing && continue
        name = PSY.get_name(d)
        max_p = _storage_side_max(T, storage)
        ss_factor = _storage_side_ss_factor(T, ss[name, t])
        constraint[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_var[name, t] <= max_p * ss_factor
        )
    end
    return
end

#################################################################################
# HybridStorageReservePowerLimitConstraint{ChargeSide}
# HybridStorageReservePowerLimitConstraint{DischargeSide}
# (with-reserves case — charge/discharge headroom under reservation +
# reserve-aware bounds, mirroring HSS's ChargingReservePowerLimit/
# DischargingReservePowerLimit)
#################################################################################

# Reserve-assignment expressions enter the bounds of the with-reserves storage
# power limits asymmetrically: charge UB picks up the down reserve (loading
# margin), charge LB subtracts the up reserve (headroom); discharge UB picks up
# the up reserve, discharge LB subtracts the down reserve.
_storage_side_ub_reserve_expr(
    ::Type{HybridStorageReservePowerLimitConstraint{ChargeSide}},
) =
    StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}
_storage_side_ub_reserve_expr(
    ::Type{HybridStorageReservePowerLimitConstraint{DischargeSide}},
) =
    StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}
_storage_side_lb_reserve_expr(
    ::Type{HybridStorageReservePowerLimitConstraint{ChargeSide}},
) =
    StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}
_storage_side_lb_reserve_expr(
    ::Type{HybridStorageReservePowerLimitConstraint{DischargeSide}},
) =
    StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide}

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: HybridStorageReservePowerLimitConstraint,
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_var = get_variable(container, _storage_side_power_var(T), V)
    has_ss = haskey(IOM.get_variables(container), VariableKey(HybridStorageReservation, V))
    ss = has_ss ? get_variable(container, HybridStorageReservation, V) : nothing
    r_ub = get_expression(container, _storage_side_ub_reserve_expr(T), V)
    r_lb = get_expression(container, _storage_side_lb_reserve_expr(T), V)
    con_ub = add_constraints_container!(
        container, T, V, names, time_steps; meta = "ub")
    con_lb = add_constraints_container!(
        container, T, V, names, time_steps; meta = "lb")
    for d in devices, t in time_steps
        storage = PSY.get_storage(d)
        storage === nothing && continue
        name = PSY.get_name(d)
        max_p = _storage_side_max(T, storage)
        ub_rhs = has_ss ? max_p * _storage_side_ss_factor(T, ss[name, t]) : max_p
        con_ub[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_var[name, t] + r_ub[name, t] <= ub_rhs
        )
        con_lb[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_var[name, t] - r_lb[name, t] >= 0.0
        )
    end
    return
end

#################################################################################
# Charge/Discharge regularization constraints — penalize step changes in the
# charge/discharge profile via a non-negative slack. Mirrors HSS
# add_constraints.jl:1255–1424. When reserves are present, the served reserve
# expressions enter the step-change quantity so the regularization smooths the
# *net* injection profile, not the bare charge/discharge variable.
#################################################################################

# Trait stubs for the unified Charge/Discharge regularization body. Sign
# convention for net injection: charge nets to (p − r_up + r_dn); discharge
# nets to (p + r_up − r_dn).
_reg_slack_var(::Type{RegularizationConstraint{Sd}}) where {Sd <: ReserveSide} =
    RegularizationVariable{Sd}
_reg_power_var(::Type{RegularizationConstraint{Sd}}) where {Sd <: ReserveSide} =
    HybridStorageSubcomponentPower{Sd}
_reg_reserve_exprs(::Type{RegularizationConstraint{Sd}}) where {Sd <: ReserveSide} = (
    StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, Sd},
    StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, Sd},
)
_reg_reserve_signs(::Type{RegularizationConstraint{ChargeSide}}) = (-1, +1)
_reg_reserve_signs(::Type{RegularizationConstraint{DischargeSide}}) = (+1, -1)

function _hybrid_served_reserve_pair(container, ::Type{T}, V, name, t) where {T}
    UpExpr, DnExpr = _reg_reserve_exprs(T)
    if has_container_key(container, UpExpr, V) &&
       has_container_key(container, DnExpr, V)
        up = get_expression(container, UpExpr, V)[name, t]
        dn = get_expression(container, DnExpr, V)[name, t]
        return up, dn
    end
    return 0.0, 0.0
end

# Per-formulation: does the regularization body include served-reserve terms?
# With-reserves formulation: include them only if the device model has a service model.
# Plain hybrid formulation: never include them (no axes to integrate against).
_regularization_has_services(::Type{<:AbstractHybridFormulationWithReserves}, model) =
    has_service_model(model)
_regularization_has_services(::Type{<:AbstractHybridFormulation}, _model) = false

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: RegularizationConstraint,
    U <: Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
} where {V <: PSY.HybridSystem}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    reg_var = get_variable(container, _reg_slack_var(T), V)
    p_var = get_variable(container, _reg_power_var(T), V)
    has_services = _regularization_has_services(W, model)
    s_up, s_dn = _reg_reserve_signs(T)
    con_ub = add_constraints_container!(
        container, T, V, names, time_steps; meta = "ub")
    con_lb = add_constraints_container!(
        container, T, V, names, time_steps; meta = "lb")
    jm = get_jump_model(container)
    t1 = first(time_steps)
    for d in devices
        PSY.get_storage(d) === nothing && continue
        name = PSY.get_name(d)
        # First time step: pin slack to zero (no previous step to compare against).
        con_ub[name, t1] = JuMP.@constraint(jm, reg_var[name, t1] == 0)
        con_lb[name, t1] = JuMP.@constraint(jm, reg_var[name, t1] == 0)
        for t in time_steps[2:end]
            if has_services
                up_prev, dn_prev =
                    _hybrid_served_reserve_pair(container, T, V, name, t - 1)
                up_t, dn_t = _hybrid_served_reserve_pair(container, T, V, name, t)
                lhs =
                    (p_var[name, t - 1] + s_up * up_prev + s_dn * dn_prev) -
                    (p_var[name, t] + s_up * up_t + s_dn * dn_t)
            else
                lhs = p_var[name, t - 1] - p_var[name, t]
            end
            con_ub[name, t] = JuMP.@constraint(jm, lhs <= reg_var[name, t])
            con_lb[name, t] = JuMP.@constraint(jm, lhs >= -reg_var[name, t])
        end
    end
    return
end

#################################################################################
# Reuse POM's ReserveCoverageConstraint{,EndOfPeriod} types with V <: HybridSystem
# dispatches. Bodies mirror storage_models.jl:1038–1108, substituting
# PSY.get_storage(d) for d at every PSY accessor.
#################################################################################

const _ReserveCoverageT =
    Union{ReserveCoverageConstraint, ReserveCoverageConstraintEndOfPeriod}

# Container setup: dispatch on service type. Up → "_discharge" suffix (storage discharges
# to deliver up-reserve); Down → "_charge" suffix. `lazy_container_addition!` is idempotent,
# so calling these methods more than once per (T, V, service) is safe.
function _init_coverage_container!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    names::Vector{String},
    time_steps::UnitRange{Int},
    service::PSY.Reserve{PSY.ReserveUp},
) where {T <: _ReserveCoverageT, V <: PSY.HybridSystem}
    return lazy_container_addition!(
        container, T, V, names, time_steps;
        meta = "$(typeof(service))_$(PSY.get_name(service))_discharge",
    )
end

function _init_coverage_container!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    names::Vector{String},
    time_steps::UnitRange{Int},
    service::PSY.Reserve{PSY.ReserveDown},
) where {T <: _ReserveCoverageT, V <: PSY.HybridSystem}
    return lazy_container_addition!(
        container, T, V, names, time_steps;
        meta = "$(typeof(service))_$(PSY.get_name(service))_charge",
    )
end

_init_coverage_container!(
    ::OptimizationContainer,
    ::Type{<:_ReserveCoverageT},
    ::Type{<:PSY.HybridSystem},
    ::Vector{String},
    ::UnitRange{Int},
    ::PSY.Service,
) = nothing  # subsumes the `(service isa PSY.Reserve) || continue` guard

# Constraint emission: dispatch on service type. Up uses HybridStorageSubcomponentReserveVariable{DischargeSide}
# bounded by SoC; Down uses HybridStorageSubcomponentReserveVariable{ChargeSide} bounded by (soc_max − SoC).
# Sustained-time accessors exist only on PSY.Reserve, so the param computation lives
# inside the per-direction helpers — the PSY.Service fallback never touches them.
function _emit_coverage_constraint!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    ic::InitialCondition,
    energy_var,
    ci_name::String,
    eff_in::Float64,
    inv_eff_out::Float64,
    fraction_of_hour::Float64,
    resolution::Dates.Period,
    storage::PSY.Storage,
    time_steps::UnitRange{Int},
    service::PSY.Reserve{PSY.ReserveUp},
) where {T <: _ReserveCoverageT, V <: PSY.HybridSystem}
    s_type = typeof(service)
    s_name = PSY.get_name(service)
    num_periods = PSY.get_sustained_time(service) / Dates.value(Dates.Second(resolution))
    sustained_param_discharge = inv_eff_out * fraction_of_hour * num_periods
    reserve_var =
        get_variable(
            container,
            HybridStorageSubcomponentReserveVariable{DischargeSide},
            V,
            "$(s_type)_$s_name",
        )
    con = get_constraint(container, T, V, "$(s_type)_$(s_name)_discharge")
    jm = get_jump_model(container)
    soc_min =
        PSY.get_storage_level_limits(storage).min *
        PSY.get_storage_capacity(storage, PSY.SU) *
        PSY.get_conversion_factor(storage)
    if time_offset(T) == -1
        con[ci_name, 1] = JuMP.@constraint(
            jm,
            sustained_param_discharge * reserve_var[ci_name, 1] <= get_value(ic) - soc_min
        )
        for t in time_steps[2:end]
            con[ci_name, t] = JuMP.@constraint(
                jm,
                sustained_param_discharge * reserve_var[ci_name, t] <=
                energy_var[ci_name, t - 1] - soc_min
            )
        end
    else  # EndOfPeriod
        for t in time_steps
            con[ci_name, t] = JuMP.@constraint(
                jm,
                sustained_param_discharge * reserve_var[ci_name, t] <=
                energy_var[ci_name, t] - soc_min
            )
        end
    end
    return
end

function _emit_coverage_constraint!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{V},
    ic::InitialCondition,
    energy_var,
    ci_name::String,
    eff_in::Float64,
    inv_eff_out::Float64,
    fraction_of_hour::Float64,
    resolution::Dates.Period,
    storage::PSY.Storage,
    time_steps::UnitRange{Int},
    service::PSY.Reserve{PSY.ReserveDown},
) where {T <: _ReserveCoverageT, V <: PSY.HybridSystem}
    s_type = typeof(service)
    s_name = PSY.get_name(service)
    num_periods = PSY.get_sustained_time(service) / Dates.value(Dates.Second(resolution))
    sustained_param_charge = eff_in * fraction_of_hour * num_periods
    reserve_var =
        get_variable(
            container,
            HybridStorageSubcomponentReserveVariable{ChargeSide},
            V,
            "$(s_type)_$s_name",
        )
    con = get_constraint(container, T, V, "$(s_type)_$(s_name)_charge")
    soc_max =
        PSY.get_storage_level_limits(storage).max *
        PSY.get_storage_capacity(storage, PSY.SU) *
        PSY.get_conversion_factor(storage)
    jm = get_jump_model(container)
    if time_offset(T) == -1
        con[ci_name, 1] = JuMP.@constraint(
            jm,
            sustained_param_charge * reserve_var[ci_name, 1] <= soc_max - get_value(ic)
        )
        for t in time_steps[2:end]
            con[ci_name, t] = JuMP.@constraint(
                jm,
                sustained_param_charge * reserve_var[ci_name, t] <=
                soc_max - energy_var[ci_name, t - 1]
            )
        end
    else  # EndOfPeriod
        for t in time_steps
            con[ci_name, t] = JuMP.@constraint(
                jm,
                sustained_param_charge * reserve_var[ci_name, t] <=
                soc_max - energy_var[ci_name, t]
            )
        end
    end
    return
end

_emit_coverage_constraint!(
    ::OptimizationContainer,
    ::Type{<:_ReserveCoverageT},
    ::Type{<:PSY.HybridSystem},
    ::InitialCondition,
    _energy_var,
    ::String,
    ::Float64,
    ::Float64,
    ::Float64,
    ::Dates.Period,
    ::PSY.Storage,
    ::UnitRange{Int},
    ::PSY.Service,
) = nothing

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, HybridDispatchWithReserves},
    network_model::NetworkModel{X},
) where {
    T <: _ReserveCoverageT,
    V <: PSY.HybridSystem,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(d) for d in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)

    services_set = Set{PSY.Service}()
    for ic in initial_conditions
        d = IOM.get_component(ic)
        union!(services_set, PSY.get_services(d))
    end

    for service in services_set
        _init_coverage_container!(container, T, V, names, time_steps, service)
    end

    for ic in initial_conditions
        d = IOM.get_component(ic)
        storage = PSY.get_storage(d)
        storage === nothing && continue
        ci_name = PSY.get_name(d)
        eff_in = PSY.get_efficiency(storage).in
        inv_eff_out = 1.0 / PSY.get_efficiency(storage).out
        for service in PSY.get_services(d)
            _emit_coverage_constraint!(
                container, T, V, ic, energy_var, ci_name,
                eff_in, inv_eff_out, fraction_of_hour, resolution,
                storage, time_steps, service,
            )
        end
    end
    return
end

#################################################################################
#################################################################################
# HybridEnergyTargetConstraint on hybrids with energy_target=true. A soft equality
# (e_T - e^+ + e^- = E_T) with non-negative surplus/shortage slacks penalized in the
# objective. Mirrors the storage StateofChargeTargetConstraint; the target RHS is
# scaled to absolute energy units to match the hybrid EnergyVariable.
#################################################################################
#################################################################################

function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridEnergyTargetConstraint},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, HybridDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.HybridSystem, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    energy_var = get_variable(container, EnergyVariable, V)
    surplus_var = get_variable(container, HybridEnergySurplusVariable, V)
    shortage_var = get_variable(container, HybridEnergyShortageVariable, V)
    constraint = add_constraints_container!(
        container,
        HybridEnergyTargetConstraint,
        V,
        names,
        [last(time_steps)],
    )
    for d in devices
        storage = PSY.get_storage(d)
        storage === nothing && continue
        name = PSY.get_name(d)
        target =
            PSY.get_storage_target(storage) *
            PSY.get_storage_capacity(storage, PSY.SU) *
            PSY.get_conversion_factor(storage)
        t_end = last(time_steps)
        constraint[name, t_end] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, t_end] - surplus_var[name, t_end] +
            shortage_var[name, t_end] == target
        )
    end
    return
end

#################################################################################
# Hybrid PCC ↔ subcomponent balance and reserve plumbing.
#
# These constraints are genuinely new — they have no analogue in POM's storage,
# thermal, or renewable code. They tie:
#   - PCC active-power variables (ActivePowerOutVariable / ActivePowerInVariable)
#     to the reservation variable (mutually exclusive charge/discharge at the
#     hybrid boundary)
#   - Internal subcomponent flows (thermal + renewable + storage discharge -
#     storage charge - load) to the PCC injection
#   - Per-subcomponent reserve allocations to the hybrid-boundary reserve
#     variables, and the hybrid-boundary reserve variables to the system-level
#     ActivePowerReserveVariable
#################################################################################

# Plain range constraints on the PCC variables, used when `reservation = false`.
# When `reservation = true` the PCC mutual-exclusion is enforced by
# `HybridStatusOnConstraint{DischargeSide}` / `HybridStatusOnConstraint{ChargeSide}` instead.
function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: Union{
        OutputActivePowerVariableLimitsConstraint,
        InputActivePowerVariableLimitsConstraint,
    },
    U <: Union{ActivePowerOutVariable, ActivePowerInVariable},
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
}
    add_range_constraints!(container, T, U, devices, model, X)
    return
end

"""
Couple the hybrid PCC active-power variable to the reservation binary so that
only one direction is active at a time. `HybridStatusOnConstraint{DischargeSide}` enforces
`p_out ≤ reservation·max_out` (out-mode when reservation=1); `HybridStatusOnConstraint{ChargeSide}`
enforces `p_in ≤ (1 − reservation)·max_in` (in-mode when reservation=0). With
ancillary services attached, the asymmetric reserve expressions enter both
bounds — Out side picks up Out{ReserveUp,Down}; In side picks up In{ReserveDown,Up} — mirroring
HSS `_add_constraints_status{out,in}_withreserves!`.
"""
# Side-keyed traits for HybridStatusOnConstraint{Sd}. The reserve-expression mapping is
# asymmetric: DischargeSide UB picks up Out-ReserveUp, In side UB picks up In-Down (and vice-versa
# for LB). The reservation-binary factor is `reservation` for DischargeSide, `(1-reservation)`
# for ChargeSide (mirrors the storage Charge/Discharge ss_factor trait).
_pcc_power_var(::Type{HybridStatusOnConstraint{DischargeSide}}) = ActivePowerOutVariable
_pcc_power_var(::Type{HybridStatusOnConstraint{ChargeSide}}) = ActivePowerInVariable
_pcc_max_limit(::Type{HybridStatusOnConstraint{DischargeSide}}, d) =
    PSY.get_output_active_power_limits(d, PSY.SU).max
_pcc_max_limit(::Type{HybridStatusOnConstraint{ChargeSide}}, d) =
    PSY.get_input_active_power_limits(d, PSY.SU).max
_pcc_reserve_ub_expr(::Type{HybridStatusOnConstraint{DischargeSide}}) =
    HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}
_pcc_reserve_ub_expr(::Type{HybridStatusOnConstraint{ChargeSide}}) =
    HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}
_pcc_reserve_lb_expr(::Type{HybridStatusOnConstraint{DischargeSide}}) =
    HybridPCCReserveExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide}
_pcc_reserve_lb_expr(::Type{HybridStatusOnConstraint{ChargeSide}}) =
    HybridPCCReserveExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}
_pcc_reservation_factor(::Type{HybridStatusOnConstraint{DischargeSide}}, r_val) = r_val
_pcc_reservation_factor(::Type{HybridStatusOnConstraint{ChargeSide}}, r_val) = 1 - r_val

# Helper: do PCC status constraints carry reserve terms? Type-dispatched, no body-level <:.
_pcc_has_reserves(::Type{<:AbstractHybridFormulationWithReserves}, model) =
    has_service_model(model)
_pcc_has_reserves(::Type{<:AbstractHybridFormulation}, _model) = false

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: HybridStatusOnConstraint,
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulation,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_var = get_variable(container, _pcc_power_var(T), V)
    reservation = get_variable(container, ReservationVariable, V)
    constraint = add_constraints_container!(container, T, V, names, time_steps)

    has_reserves = _pcc_has_reserves(W, model)
    r_ub, r_lb, con_lb = if has_reserves
        (
            get_expression(container, _pcc_reserve_ub_expr(T), V),
            get_expression(container, _pcc_reserve_lb_expr(T), V),
            add_constraints_container!(container, T, V, names, time_steps; meta = "lb"),
        )
    else
        (nothing, nothing, nothing)
    end

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        max_p = _pcc_max_limit(T, d)
        rhs_factor = _pcc_reservation_factor(T, reservation[name, t])
        if has_reserves
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_var[name, t] + r_ub[name, t] <= rhs_factor * max_p
            )
            con_lb[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_var[name, t] - r_lb[name, t] >= 0.0
            )
        else
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                p_var[name, t] <= rhs_factor * max_p
            )
        end
    end
    return
end

"""
Energy asset balance: the hybrid's PCC injection equals the sum of subcomponent
injections (thermal + renewable + storage discharge - storage charge - load).
When ancillary services are attached, served (deployed-fraction) reserve expressions
also enter the balance with sign pattern `+out_up - in_up - out_down + in_down`,
mirroring HSS `_add_constraints_energyassetbalance_with_reserves!`.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridEnergyAssetBalanceConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.HybridSystem, W <: AbstractHybridFormulation, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]
    p_out = get_variable(container, ActivePowerOutVariable, V)
    p_in = get_variable(container, ActivePowerInVariable, V)
    constraint = add_constraints_container!(
        container,
        HybridEnergyAssetBalanceConstraint,
        V,
        names,
        time_steps,
    )

    # Optional subcomponent variables — only present when the hybrid has them
    p_th = if haskey(IOM.get_variables(container), VariableKey(HybridThermalActivePower, V))
        get_variable(container, HybridThermalActivePower, V)
    else
        nothing
    end
    p_re =
        if haskey(IOM.get_variables(container), VariableKey(HybridRenewableActivePower, V))
            get_variable(container, HybridRenewableActivePower, V)
        else
            nothing
        end
    p_ch =
        if haskey(
            IOM.get_variables(container),
            VariableKey(HybridStorageSubcomponentPower{ChargeSide}, V),
        )
            get_variable(container, HybridStorageSubcomponentPower{ChargeSide}, V)
        else
            nothing
        end
    p_ds =
        if haskey(
            IOM.get_variables(container),
            VariableKey(HybridStorageSubcomponentPower{DischargeSide}, V),
        )
            get_variable(container, HybridStorageSubcomponentPower{DischargeSide}, V)
        else
            nothing
        end

    load_param_container =
        if haskey(
            IOM.get_parameters(container),
            ParameterKey(HybridElectricLoadTimeSeriesParameter, V),
        )
            get_parameter(container, HybridElectricLoadTimeSeriesParameter, V)
        else
            nothing
        end
    load_multiplier = if load_param_container === nothing
        nothing
    else
        get_multiplier_array(load_param_container)
    end

    has_reserves = W <: AbstractHybridFormulationWithReserves && has_service_model(model)
    serv_out_up, serv_out_dn, serv_in_up, serv_in_dn = if has_reserves
        (
            get_expression(
                container,
                HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
                V,
            ),
            get_expression(
                container,
                HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
                V,
            ),
            get_expression(
                container,
                HybridPCCReserveExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
                V,
            ),
            get_expression(
                container,
                HybridPCCReserveExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
                V,
            ),
        )
    else
        (nothing, nothing, nothing, nothing)
    end

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        rhs = JuMP.AffExpr(0.0)
        if p_th !== nothing && PSY.get_thermal_unit(d) !== nothing
            add_proportional_to_jump_expression!(rhs, p_th[name, t], 1.0)
        end
        if p_re !== nothing && PSY.get_renewable_unit(d) !== nothing
            add_proportional_to_jump_expression!(rhs, p_re[name, t], 1.0)
        end
        if p_ds !== nothing && PSY.get_storage(d) !== nothing
            add_proportional_to_jump_expression!(rhs, p_ds[name, t], 1.0)
        end
        if p_ch !== nothing && PSY.get_storage(d) !== nothing
            add_proportional_to_jump_expression!(rhs, p_ch[name, t], -1.0)
        end
        if load_param_container !== nothing && PSY.get_electric_load(d) !== nothing
            load_ref = get_parameter_column_refs(load_param_container, name)[t]
            add_proportional_to_jump_expression!(rhs, load_ref, -load_multiplier[name, t])
        end
        if has_reserves
            add_proportional_to_jump_expression!(rhs, serv_out_up[name, t], 1.0)
            add_proportional_to_jump_expression!(rhs, serv_in_dn[name, t], 1.0)
            add_proportional_to_jump_expression!(rhs, serv_out_dn[name, t], -1.0)
            add_proportional_to_jump_expression!(rhs, serv_in_up[name, t], -1.0)
        end
        constraint[name, t] = JuMP.@constraint(
            get_jump_model(container),
            p_out[name, t] - p_in[name, t] == rhs
        )
    end
    return
end

"""
Couple the hybrid PCC reserve variables (Out + In, summed across subcomponents)
to the system-level `ActivePowerReserveVariable` for each service the hybrid
participates in.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridReserveAssignmentConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]

    services = Set{PSY.Service}()
    for d in devices
        union!(services, PSY.get_services(d))
    end

    for service in services
        s_name = PSY.get_name(service)
        s_type = typeof(service)
        constraint =
            add_constraints_container!(container, HybridReserveAssignmentConstraint, V,
                names, time_steps;
                meta = "$(s_type)_$s_name")
        # System-level reserve variable for this service (merged, keyed
        # `(service, device, time)`).
        sys_reserve = get_variable(container, ActivePowerReserveVariable, s_type)
        # Per-hybrid reserve variables for this service
        r_out = get_variable(
            container,
            HybridPCCReserveVariable{DischargeSide},
            V,
            "$(s_type)_$s_name",
        )
        r_in = get_variable(
            container,
            HybridPCCReserveVariable{ChargeSide},
            V,
            "$(s_type)_$s_name",
        )
        for d in devices, t in time_steps
            name = PSY.get_name(d)
            (service in PSY.get_services(d)) || continue
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                r_out[name, t] + r_in[name, t] == sys_reserve[(s_name, name, t)]
            )
        end
    end
    return
end

"""
Couple the hybrid PCC reserve variables (Out + In) to the sum of per-subcomponent
reserve allocations (thermal + renewable + charging + discharging).
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{HybridReserveBalanceConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    V <: PSY.HybridSystem,
    W <: AbstractHybridFormulationWithReserves,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(d) for d in devices]

    services = Set{PSY.Service}()
    for d in devices
        union!(services, PSY.get_services(d))
    end

    for service in services
        s_name = PSY.get_name(service)
        s_type = typeof(service)
        constraint =
            add_constraints_container!(container, HybridReserveBalanceConstraint, V, names,
                time_steps;
                meta = "$(s_type)_$s_name")
        r_out = get_variable(
            container,
            HybridPCCReserveVariable{DischargeSide},
            V,
            "$(s_type)_$s_name",
        )
        r_in = get_variable(
            container,
            HybridPCCReserveVariable{ChargeSide},
            V,
            "$(s_type)_$s_name",
        )
        for d in devices, t in time_steps
            name = PSY.get_name(d)
            (service in PSY.get_services(d)) || continue
            rhs = JuMP.AffExpr(0.0)
            for var_t in (HybridThermalReserveVariable, HybridRenewableReserveVariable,
                HybridStorageSubcomponentReserveVariable{ChargeSide},
                HybridStorageSubcomponentReserveVariable{DischargeSide})
                key = VariableKey(var_t, V, "$(s_type)_$s_name")
                if haskey(IOM.get_variables(container), key)
                    var = get_variable(container, key)
                    add_proportional_to_jump_expression!(rhs, var[name, t], 1.0)
                end
            end
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                r_out[name, t] + r_in[name, t] == rhs
            )
        end
    end
    return
end
#################################################################################
# Objective function for HybridSystem.
#
# The hybrid envelope itself carries `MarketBidCost(nothing)`. The variable
# costs come from the subcomponents:
#   - Thermal subcomponent → ThermalGenerationCost (PSY 5.x)
#   - Renewable subcomponent → RenewableGenerationCost
#   - Storage subcomponent → StorageCost
#
# We walk into each subcomponent's operation_cost, then delegate to IOM's
# add_variable_cost_to_objective! with the subcomponent's cost data and the
# hybrid-specific variable type. The variable is keyed by the hybrid's name
# (not the subcomponent's), but the cost data drives the linear/piecewise terms.
#################################################################################

function _add_hybrid_subcomponent_variable_cost!(
    container::OptimizationContainer,
    ::Type{V},
    devices,
    accessor::Function,
    ::Type{W},
) where {V <: VariableType, W <: AbstractHybridFormulation}
    for d in devices
        sub = accessor(d)
        sub === nothing && continue
        op_cost = PSY.get_operation_cost(sub)
        # Use IOM's add_variable_cost_to_objective! with the hybrid device
        # but the subcomponent's cost data. The dispatch on (V, HybridSystem, W)
        # is what variable_cost(op_cost, V, HybridSystem, W) needs to see.
        add_variable_cost_to_objective!(container, V, d, op_cost, W)
    end
    return
end

# Hybrid `OnVariable` proportional cost — delegate to the standalone thermal
# `proportional_cost` so a hybrid-embedded thermal unit and a standalone copy with the
# same `ThermalGenerationCost` produce identical objective coefficients
# (`onvar_cost + vom_constant + fixed`). Implemented via the same IOM cost-term
# helpers (`add_cost_term_invariant!` / `add_cost_term_variant!`) that
# `add_proportional_cost_maybe_time_variant!` uses, so the time-variant fuel-cost
# branch lights up when the embedded thermal cost is backed by a time series.
function add_proportional_cost!(
    container::OptimizationContainer,
    ::Type{OnVariable},
    devices::Vector{D},
    ::Type{W},
) where {D <: PSY.HybridSystem, W <: AbstractHybridFormulation}
    multiplier = objective_function_multiplier(OnVariable, W)
    on_var = get_variable(container, OnVariable, D)
    for d in devices
        thermal = PSY.get_thermal_unit(d)
        thermal === nothing && continue
        thermal_cost = PSY.get_operation_cost(thermal)
        thermal_cost === nothing && continue
        # Select the variant- vs invariant-aware cost-term writer once per device, then
        # call it inside the time loop. Mirrors IOM.add_proportional_cost_maybe_time_variant!.
        add_cost_term! = if IOM.is_time_variant_proportional(thermal_cost)
            add_cost_term_variant!
        else
            add_cost_term_invariant!
        end
        name = PSY.get_name(d)
        for t in get_time_steps(container)
            cost_term = proportional_cost(
                container, thermal_cost, OnVariable, thermal,
                ThermalBasicUnitCommitment, t,
            )
            iszero(cost_term) && continue
            rate = cost_term * multiplier
            add_cost_term!(
                container, on_var[name, t], rate, ProductionCostExpression, D, name, t,
            )
        end
    end
    return
end

function objective_function!(
    container::OptimizationContainer,
    devices::U,
    model::DeviceModel{D, W},
    ::Type{<:AbstractNetworkModel},
) where {
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractHybridFormulation,
} where {D <: PSY.HybridSystem}
    devices_vec = collect(devices)
    hybrids_with_thermal = [d for d in devices_vec if PSY.get_thermal_unit(d) !== nothing]
    hybrids_with_renewable =
        [d for d in devices_vec if PSY.get_renewable_unit(d) !== nothing]
    hybrids_with_storage = [d for d in devices_vec if PSY.get_storage(d) !== nothing]

    # Thermal: variable cost on HybridThermalActivePower; OnVariable proportional cost
    # routed through POM's standard add_proportional_cost! pathway so hybrids match
    # standalone thermal exactly (onvar_cost + vom_constant + fixed).
    if !isempty(hybrids_with_thermal)
        _add_hybrid_subcomponent_variable_cost!(container, HybridThermalActivePower,
            hybrids_with_thermal, PSY.get_thermal_unit, W)
        add_proportional_cost!(container, OnVariable, hybrids_with_thermal, W)
    end

    # Renewable: variable cost on HybridRenewableActivePower (typically a curtailment cost)
    if !isempty(hybrids_with_renewable)
        _add_hybrid_subcomponent_variable_cost!(container, HybridRenewableActivePower,
            hybrids_with_renewable, PSY.get_renewable_unit, W)
    end

    # Storage: variable costs on charge/discharge, plus optional regularization penalty.
    if !isempty(hybrids_with_storage)
        _add_hybrid_subcomponent_variable_cost!(container,
            HybridStorageSubcomponentPower{ChargeSide},
            hybrids_with_storage, PSY.get_storage, W)
        _add_hybrid_subcomponent_variable_cost!(container,
            HybridStorageSubcomponentPower{DischargeSide},
            hybrids_with_storage, PSY.get_storage, W)
        if get_attribute(model, "regularization")
            _add_hybrid_regularization_cost!(
                container, RegularizationVariable{ChargeSide}, hybrids_with_storage, W)
            _add_hybrid_regularization_cost!(
                container, RegularizationVariable{DischargeSide}, hybrids_with_storage, W)
        end
        if get_attribute(model, "energy_target")
            _add_hybrid_energy_target_cost!(
                container, HybridEnergySurplusVariable, hybrids_with_storage, W)
            _add_hybrid_energy_target_cost!(
                container, HybridEnergyShortageVariable, hybrids_with_storage, W)
        end
    end
    return
end

# Routes regularization slacks through IOM's add_cost_term_invariant! so the penalty
# lands in both the objective and (when present) the production-cost expression.
function _add_hybrid_regularization_cost!(
    container::OptimizationContainer,
    ::Type{V},
    devices::Vector{D},
    ::Type{W},
) where {V <: VariableType, D <: PSY.HybridSystem, W <: AbstractHybridFormulation}
    multiplier = objective_function_multiplier(V, W)
    rate = HYBRID_REGULARIZATION_COST * multiplier
    var = get_variable(container, V, D)
    for d in devices
        PSY.get_storage(d) === nothing && continue
        name = PSY.get_name(d)
        for t in get_time_steps(container)
            add_cost_term_invariant!(
                container, var[name, t], rate, ProductionCostExpression, D, name, t,
            )
        end
    end
    return
end

# Penalizes the end-of-period energy-target slacks. The per-unit cost comes from the
# storage subcomponent's `StorageCost` (energy_surplus_cost / energy_shortage_cost),
# mirroring POM storage's StateofChargeTargetConstraint objective handling. Slacks live
# only at the final time step.
function _add_hybrid_energy_target_cost!(
    container::OptimizationContainer,
    ::Type{V},
    devices::Vector{D},
    ::Type{W},
) where {V <: VariableType, D <: PSY.HybridSystem, W <: AbstractHybridFormulation}
    multiplier = objective_function_multiplier(V, W)
    var = get_variable(container, V, D)
    t_end = last(get_time_steps(container))
    for d in devices
        storage = PSY.get_storage(d)
        storage === nothing && continue
        name = PSY.get_name(d)
        op_cost = PSY.get_operation_cost(storage)
        cost_term = proportional_cost(op_cost, V, d, W) * multiplier
        add_cost_term_invariant!(
            container, var[name, t_end], cost_term, ProductionCostExpression, D, name, t_end,
        )
    end
    return
end

#################################################################################
# IOM.variable_cost dispatches — reach into subcomponent cost types
#################################################################################

# Thermal subcomponent variable cost
IOM.variable_cost(
    cost::PSY.ThermalGenerationCost,
    ::Type{HybridThermalActivePower},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_variable(cost)

# Renewable subcomponent variable cost (typically a curtailment penalty)
IOM.variable_cost(
    cost::PSY.RenewableGenerationCost,
    ::Type{HybridRenewableActivePower},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_curtailment_cost(cost)

# Storage subcomponent variable costs
IOM.variable_cost(
    cost::PSY.StorageCost,
    ::Type{HybridStorageSubcomponentPower{ChargeSide}},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_charge_variable_cost(cost)

IOM.variable_cost(
    cost::PSY.StorageCost,
    ::Type{HybridStorageSubcomponentPower{DischargeSide}},
    ::Type{<:PSY.HybridSystem},
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_discharge_variable_cost(cost)

# End-of-period energy-target slack penalties, pulled from the storage subcomponent's
# StorageCost. Mirrors POM storage (energy_storage_models/storage_models.jl:74-75).
proportional_cost(
    cost::PSY.StorageCost,
    ::Type{HybridEnergySurplusVariable},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_energy_surplus_cost(cost)

proportional_cost(
    cost::PSY.StorageCost,
    ::Type{HybridEnergyShortageVariable},
    ::PSY.HybridSystem,
    ::Type{<:AbstractHybridFormulation},
) = PSY.get_energy_shortage_cost(cost)
