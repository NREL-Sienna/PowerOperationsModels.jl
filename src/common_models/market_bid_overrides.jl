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
    PSY.get_operation_cost(device) isa PSY.MarketBidCost

#################################################################################
# Section 2: _consider_parameter — compact commitment startup
# Compact/multi-start formulations have HotStart/WarmStart/ColdStart variables
# in addition to the normal StartVariable.
#################################################################################

_consider_parameter(
    ::StartupCostParameter,
    container::OptimizationContainer,
    ::DeviceModel{T, D},
) where {T, D <: AbstractCompactUnitCommitment} =
    any(has_container_key.([container], [StartVariable, MULTI_START_VARIABLES...], [T]))

#################################################################################
# Section 3: Device-specific validate_occ_component
#################################################################################

# ThermalMultiStart: accept NTuple{3, Float64} and StartUpStages without warning
function validate_occ_component(
    ::StartupCostParameter,
    device::PSY.ThermalMultiStart,
)
    startup = PSY.get_start_up(PSY.get_operation_cost(device))
    _validate_eltype(
        Union{Float64, NTuple{3, Float64}, StartUpStages},
        device,
        startup,
        " startup cost",
    )
end

# Renewable / Storage: warn on nonzero startup, shutdown, and no-load costs

function validate_occ_component(
    ::StartupCostParameter,
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    startup = PSY.get_start_up(PSY.get_operation_cost(device))
    apply_maybe_across_time_series(device, startup) do x
        if x != PSY.single_start_up_to_stages(0.0)
            @warn "Nonzero startup cost detected for renewable generation or storage device $(get_name(device))."
        end
    end
end

function validate_occ_component(
    ::ShutdownCostParameter,
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    shutdown = PSY.get_shut_down(PSY.get_operation_cost(device))
    apply_maybe_across_time_series(device, shutdown) do x
        if x != 0.0
            @warn "Nonzero shutdown cost detected for renewable generation or storage device $(get_name(device))."
        end
    end
end

function validate_occ_component(
    ::IncrementalCostAtMinParameter,
    device::Union{PSY.RenewableDispatch, PSY.Storage},
)
    no_load_cost = PSY.get_no_load_cost(PSY.get_operation_cost(device))
    if !isnothing(no_load_cost)
        apply_maybe_across_time_series(device, no_load_cost) do x
            if x != 0.0
                @warn "Nonzero no-load cost detected for renewable generation or storage device $(get_name(device))."
            end
        end
    end
end

function validate_occ_component(
    ::DecrementalCostAtMinParameter,
    device::PSY.Storage,
)
    no_load_cost = PSY.get_no_load_cost(PSY.get_operation_cost(device))
    if !isnothing(no_load_cost)
        apply_maybe_across_time_series(device, no_load_cost) do x
            if x != 0.0
                @warn "Nonzero no-load cost detected for storage device $(get_name(device))."
            end
        end
    end
end

#################################################################################
# Section 4: _include_min_gen_power_in_constraint
# Whether the PWL block offer constraint should include p_min * on_var.
#################################################################################

_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Source},
    ::ActivePowerOutVariable,
    ::AbstractDeviceFormulation,
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Source},
    ::ActivePowerInVariable,
    ::AbstractDeviceFormulation,
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.RenewableDispatch},
    ::ActivePowerVariable,
    ::AbstractDeviceFormulation,
) = false
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.Generator},
    ::ActivePowerVariable,
    ::AbstractDeviceFormulation,
) = true
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::ActivePowerVariable,
    ::PowerLoadInterruption,
) = true
_include_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::ActivePowerVariable,
    ::PowerLoadDispatch,
) = false
_include_min_gen_power_in_constraint(
    ::Type,
    ::PowerAboveMinimumVariable,
    ::AbstractDeviceFormulation,
) = false

#################################################################################
# Section 5: _include_constant_min_gen_power_in_constraint
# Whether the PWL block offer constraint should include p_min as a constant
# (for formulations that have nonzero minimum power but no OnVariable).
#################################################################################

_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::ActivePowerVariable,
    ::PowerLoadDispatch,
) = true
_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.ControllableLoad},
    ::ActivePowerVariable,
    ::PowerLoadInterruption,
) = false
_include_constant_min_gen_power_in_constraint(
    ::Type{<:PSY.RenewableGen},
    ::ActivePowerVariable,
    ::AbstractRenewableDispatchFormulation,
) = true

#################################################################################
# Section 6: Source ImportExport — both incremental and decremental offers
#################################################################################

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::ActivePowerOutVariable,
    component::PSY.Source,
    cost_function::PSY.ImportExportCost,
    ::ImportExportSourceModel,
)
    isnothing(get_output_offer_curves(cost_function)) && return
    add_pwl_term!(
        IncrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerOutVariable(),
        ImportExportSourceModel(),
    )
    return
end

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::ActivePowerInVariable,
    component::PSY.Source,
    cost_function::PSY.ImportExportCost,
    ::ImportExportSourceModel,
)
    isnothing(get_input_offer_curves(cost_function)) && return
    add_pwl_term!(
        DecrementalOffer(),
        container,
        component,
        cost_function,
        ActivePowerInVariable(),
        ImportExportSourceModel(),
    )
    return
end

#################################################################################
# Section 7: Load formulation — decremental offers only
#################################################################################

function add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::T,
    component::PSY.Component,
    cost_function::PSY.OfferCurveCost,
    ::U,
) where {T <: VariableType, U <: AbstractControllablePowerLoadFormulation}
    component_name = PSY.get_name(component)
    @debug "Market Bid" _group = LOG_GROUP_COST_FUNCTIONS component_name
    if !(isnothing(get_output_offer_curves(cost_function)))
        error("Component $(component_name) is not allowed to participate as a supply.")
    end
    add_pwl_term!(
        DecrementalOffer(),
        container,
        component,
        cost_function,
        T(),
        U(),
    )
    return
end

_vom_offer_direction(::AbstractControllablePowerLoadFormulation) = DecrementalOffer()

#################################################################################
# Section 7: Service-specific PWL (ReserveDemandCurve, StepwiseCostReserve)
#################################################################################

"""
PWL block offer constraints for ORDC (ReserveDemandCurve).
"""
function _add_pwl_constraint!(
    container::OptimizationContainer,
    component::T,
    ::U,
    break_points::Vector{Float64},
    pwl_vars::Vector{JuMP.VariableRef},
    period::Int,
) where {T <: PSY.ReserveDemandCurve, U <: ServiceRequirementVariable}
    name = PSY.get_name(component)
    variables = get_variable(container, U(), T, name)
    const_container = lazy_container_addition!(
        container,
        PiecewiseLinearBlockIncrementalOfferConstraint(),
        T,
        axes(variables)...;
        meta = name,
    )
    add_pwl_block_offer_constraints!(
        get_jump_model(container),
        const_container,
        name,
        period,
        variables[name, period],
        pwl_vars,
        break_points,
    )
    return
end

"""
PWL cost terms for StepwiseCostReserve (AbstractServiceFormulation).
"""
function _add_pwl_term!(
    container::OptimizationContainer,
    component::T,
    cost_data::PSY.CostCurve{PSY.PiecewiseIncrementalCurve},
    ::U,
    ::V,
) where {T <: PSY.Component, U <: VariableType, V <: AbstractServiceFormulation}
    multiplier = objective_function_multiplier(U(), V())
    resolution = get_resolution(container)
    dt = Dates.value(Dates.Second(resolution)) / SECONDS_IN_HOUR
    base_power = get_model_base_power(container)
    value_curve = PSY.get_value_curve(cost_data)
    power_units = PSY.get_power_units(cost_data)
    cost_component = PSY.get_function_data(value_curve)
    device_base_power = PSY.get_base_power(component)
    data = get_piecewise_curve_per_system_unit(
        cost_component,
        power_units,
        base_power,
        device_base_power,
    )
    name = PSY.get_name(component)
    time_steps = get_time_steps(container)
    pwl_cost_expressions = Vector{JuMP.AffExpr}(undef, time_steps[end])
    slopes = IS.get_y_coords(data)
    break_points = PSY.get_x_coords(data)
    for t in time_steps
        pwl_vars = add_pwl_variables!(
            container,
            PiecewiseLinearBlockIncrementalOffer,
            T,
            name,
            t,
            length(slopes);
            upper_bound = Inf,
        )
        _add_pwl_constraint!(container, component, U(), break_points, pwl_vars, t)
        pwl_cost_expressions[t] = get_pwl_cost_expression(pwl_vars, slopes, multiplier * dt)
    end
    return pwl_cost_expressions
end
