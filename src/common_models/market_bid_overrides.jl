#################################################################################
# Device-Specific Overloads for Market Bid / Import-Export Cost
#
# These extend the generic (device-agnostic) infrastructure in IOM's
# objective_function/market_bid.jl with overloads that dispatch on
# POM-specific device types and formulation types.
#################################################################################

#################################################################################
# Section 1: Device-specific cost detection predicates
#################################################################################

_has_market_bid_cost(::PSY.RenewableNonDispatch) = false
_has_market_bid_cost(::PSY.PowerLoad) = false
_has_market_bid_cost(device::PSY.ControllableLoad) =
    PSY.get_operation_cost(device) isa MBC_TYPES

#################################################################################
# Section 1b: Generic MarketBidCost OnVariable proportional cost
#
# Shared between thermals, hydros, and interruptible loads. The OnVariable cost
# for MBC is the offer curve's `initial_input` (cost at minimum generation). The
# only per-device variation is whether that comes from the incremental side
# (generators) or the decremental side (controllable loads). Direction is set
# by the `_onvar_offer_direction` trait.
#################################################################################

_onvar_offer_direction(::PSY.Generator) = IncrementalOffer()
_onvar_offer_direction(::PSY.ControllableLoad) = DecrementalOffer()

_cost_at_min_param(::IncrementalOffer) = IncrementalCostAtMinParameter()
_cost_at_min_param(::DecrementalOffer) = DecrementalCostAtMinParameter()

# Static MarketBidCost: read initial_input directly from the offer curve.
proportional_cost(
    ::OptimizationContainer,
    ::PSY.MarketBidCost,
    ::Type{OnVariable},
    comp::Union{PSY.Generator, PSY.ControllableLoad},
    ::Type{<:AbstractDeviceFormulation},
    ::Int,
) = IOM.get_initial_input(_onvar_offer_direction(comp), comp)

# Time-series MarketBidCost: read from parameter container populated by add_parameters!.
function proportional_cost(
    container::OptimizationContainer,
    ::PSY.MarketBidTimeSeriesCost,
    ::Type{OnVariable},
    comp::T,
    ::Type{<:AbstractDeviceFormulation},
    t::Int,
) where {T <: Union{PSY.Generator, PSY.ControllableLoad}}
    param = _cost_at_min_param(_onvar_offer_direction(comp))
    name = get_name(comp)
    param_arr = get_parameter_array(container, param, T)
    param_mult = get_parameter_multiplier_array(container, param, T)
    return param_arr[name, t] * param_mult[name, t]
end

#################################################################################
# Section 2: _consider_parameter — compact commitment startup
# Compact/multi-start formulations have HotStart/WarmStart/ColdStart variables
# in addition to the normal StartVariable.
#################################################################################

_consider_parameter(
    ::Type{StartupCostParameter},
    container::OptimizationContainer,
    ::DeviceModel{T, D},
) where {T, D <: AbstractCompactUnitCommitment} =
    any(has_container_key.([container], [StartVariable, MULTI_START_VARIABLES...], [T]))

#################################################################################
# Section 3: Device-specific validate_occ_component
#################################################################################

# ThermalMultiStart: accept NTuple{3, Float64} and PSY.StartUpStages without warning
function IOM.validate_occ_component(
    ::Type{StartupCostParameter},
    device::PSY.ThermalMultiStart,
)
    startup = PSY.get_start_up(PSY.get_operation_cost(device))
    # A TS-backed startup is a bare time-series key referencing NTuple{3, Float64}
    # stages. Keys carry no element type (`eltype(typeof(key))` is `Any` for every key
    # type, so any check against it is unsatisfiable); the referenced series' element
    # type is validated when the parameter is populated (IOM `time_series_utils`).
    startup isa IS.TimeSeriesKey && return
    _validate_eltype(
        Union{Float64, NTuple{3, Float64}, PSY.StartUpStages},
        device,
        startup,
        " startup cost",
    )
end

# Renewable / Storage: warn on nonzero startup, shutdown, and no-load costs

function IOM.validate_occ_component(
    ::Type{StartupCostParameter},
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    startup = PSY.get_start_up(PSY.get_operation_cost(device))
    apply_maybe_across_time_series(device, startup) do x
        # x may be Float64 (TGC), PSY.StartUpStages (static MBC), or NTuple{3, Float64}
        # (elements of a TS-backed startup key). `values` normalizes both NamedTuple
        # and Tuple.
        if any(!iszero, x isa Number ? (x,) : values(x))
            @warn "Nonzero startup cost detected for renewable generation or storage device $(get_name(device))."
        end
    end
end

# LinearCurve (static) and TimeSeriesLinearCurve (TS) are the only types carried in
# MBC/ImportExportCost shutdown and no-load fields. Only the static case is meaningfully
# comparable to zero at validation time — for TS we'd need to iterate the series, which
# the time-series store may not even have populated yet.
# FIXME better solution?
_scalar_if_static(x::IS.LinearCurve) = IS.get_proportional_term(x)
_scalar_if_static(::IS.TimeSeriesLinearCurve) = nothing

function IOM.validate_occ_component(
    ::Type{ShutdownCostParameter},
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    x = _scalar_if_static(PSY.get_shut_down(PSY.get_operation_cost(device)))
    if !isnothing(x) && x != 0.0
        @warn "Nonzero shutdown cost detected for renewable generation or storage device $(get_name(device))."
    end
end

function IOM.validate_occ_component(
    ::Type{IncrementalCostAtMinParameter},
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    x = _scalar_if_static(PSY.get_minimum_energy_offer(PSY.get_operation_cost(device)))
    if !isnothing(x) && x != 0.0
        @warn "Nonzero minimum-energy offer detected for renewable generation or storage device $(get_name(device))."
    end
end

function IOM.validate_occ_component(
    ::Type{DecrementalCostAtMinParameter},
    device::PSY.Storage,
)
    x = _scalar_if_static(PSY.get_minimum_energy_offer(PSY.get_operation_cost(device)))
    if !isnothing(x) && x != 0.0
        @warn "Nonzero minimum-energy offer detected for storage device $(get_name(device))."
    end
end

#################################################################################
# Section 4: _include_min_gen_power_in_constraint
# Whether the PWL block offer constraint should include p_min * on_var.
#################################################################################

_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Source},
    ::Type{ActivePowerOutVariable},
    ::Type{<:AbstractDeviceFormulation},
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Source},
    ::Type{ActivePowerInVariable},
    ::Type{<:AbstractDeviceFormulation},
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.RenewableDispatch},
    ::Type{ActivePowerVariable},
    ::Type{<:AbstractDeviceFormulation},
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Generator},
    ::Type{ActivePowerVariable},
    ::Type{<:AbstractDeviceFormulation},
) = true
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::Type{ActivePowerVariable},
    ::Type{PowerLoadInterruption},
) = true
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::Type{ActivePowerVariable},
    ::Type{PowerLoadDispatch},
) = false
_include_min_gen_power_in_constraint(
    ::Type,
    ::Type{PowerAboveMinimumVariable},
    ::Type{<:AbstractDeviceFormulation},
) = false

#################################################################################
# Section 5: _include_constant_min_gen_power_in_constraint
# Whether the PWL block offer constraint should include p_min as a constant
# (for formulations that have nonzero minimum power but no OnVariable).
#################################################################################

_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::Type{ActivePowerVariable},
    ::Type{PowerLoadDispatch},
) = true
_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::Type{ActivePowerVariable},
    ::Type{PowerLoadInterruption},
) = false
_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.RenewableGen},
    ::Type{ActivePowerVariable},
    ::Type{<:AbstractRenewableDispatchFormulation},
) = true

#################################################################################
# Section 6: Source ImportExport — both incremental and decremental offers
#################################################################################

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{ActivePowerOutVariable},
    component::PSY.Source,
    cost_function::IEC_TYPES,
    ::Type{ImportExportSourceModel},
)
    IOM.is_nontrivial_offer(get_output_offer_curves(cost_function)) || return
    add_pwl_term_delta!(
        IncrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerOutVariable,
        ImportExportSourceModel,
    )
    return
end

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{ActivePowerInVariable},
    component::PSY.Source,
    cost_function::IEC_TYPES,
    ::Type{ImportExportSourceModel},
)
    IOM.is_nontrivial_offer(get_input_offer_curves(cost_function)) || return
    add_pwl_term_delta!(
        DecrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerInVariable,
        ImportExportSourceModel,
    )
    return
end

#################################################################################
# Section 6b: Storage — discharge is an incremental (supply) offer, charge is a
# decremental (demand) offer. Certain market resources bid both sides, so the storage
# objective (storage_models.jl `add_to_objective_function!`) calls
# `add_variable_cost!` for ActivePowerOutVariable AND ActivePowerInVariable.
# Mirrors the Source ImportExport pair above.
#################################################################################
function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{ActivePowerOutVariable},
    component::PSY.Storage,
    cost_function::PSY.OfferCurveCost,
    ::Type{U},
) where {U <: AbstractStorageFormulation}
    IOM.is_nontrivial_offer(get_output_offer_curves(cost_function)) || return
    add_pwl_term_delta!(
        IncrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerOutVariable,
        U,
    )
    return
end

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{ActivePowerInVariable},
    component::PSY.Storage,
    cost_function::PSY.OfferCurveCost,
    ::Type{U},
) where {U <: AbstractStorageFormulation}
    IOM.is_nontrivial_offer(get_input_offer_curves(cost_function)) || return
    add_pwl_term_delta!(
        DecrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerInVariable,
        U,
    )
    return
end

#################################################################################
# Section 7: Load formulation — decremental offers only
#################################################################################

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::Type{T},
    component::PSY.Component,
    cost_function::PSY.OfferCurveCost,
    ::Type{U},
) where {T <: VariableType, U <: AbstractControllablePowerLoadFormulation}
    component_name = PSY.get_name(component)
    @debug "Market Bid" _group = LOG_GROUP_COST_FUNCTIONS component_name
    if IOM.is_nontrivial_offer(get_output_offer_curves(cost_function))
        throw(
            ArgumentError(
                "Component $(component_name) is not allowed to participate as a supply.",
            ),
        )
    end
    add_pwl_term_delta!(
        DecrementalOffer(),
        container,
        component,
        cost_function,
        T,
        U,
    )
    return
end

_vom_offer_direction(::Type{<:AbstractControllablePowerLoadFormulation}) =
    DecrementalOffer()

#################################################################################
# Section 7: Service-specific PWL (ORDC on a reserve, StepwiseCostReserve)
#################################################################################

"""
Add the delta PWL objective terms for an operating reserve demand curve (ORDC) service
(`StepwiseCostReserve` over an `OnlineReserve`/`OfflineReserve` carrying a demand curve).
"""
function add_pwl_term_delta!(
    container::OptimizationContainer,
    component::T,
    ::PSY.CostCurve,
    ::Type{U},
    ::Type{V},
) where {
    T <: PSY.AbstractReserve,
    U <: VariableType,
    V <: AbstractServiceFormulation,
}
    dir = _reserve_offer_direction(component)
    # objective_function_multiplier(U, V) == IOM._objective_sign(dir) for the
    # decremental ORDC offer (OBJECTIVE_FUNCTION_NEGATIVE); kept as the service-side
    # multiplier API.
    multiplier = objective_function_multiplier(U, V)
    resolution = get_resolution(container)
    dt = Dates.value(Dates.Second(resolution)) / SECONDS_IN_HOUR
    name = PSY.get_name(component)
    time_steps = get_time_steps(container)
    pwl_cost_expressions = Vector{JuMP.AffExpr}(undef, time_steps[end])
    for t in time_steps
        # Name-keyed slope/breakpoint params, same as the device offer path.
        break_points, slopes = IOM._get_pwl_data(dir, container, component, t)
        pwl_vars = add_pwl_variables_delta!(
            container,
            IOM._block_offer_var(dir),
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
            break_points,
            pwl_vars,
            t,
            IOM._block_offer_constraint(dir),
        )
        pwl_cost_expressions[t] =
            get_pwl_cost_expression_delta(pwl_vars, slopes, multiplier * dt)
    end
    return pwl_cost_expressions
end
