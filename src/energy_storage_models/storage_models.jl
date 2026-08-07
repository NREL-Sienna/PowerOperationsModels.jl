#! format: off
requires_initialization(::AbstractStorageFormulation) = false

get_variable_multiplier(::Type{<:VariableType}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = NaN
########################### ActivePowerInVariable, Storage #################################
get_variable_binary(::Type{ActivePowerInVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_lower_bound(::Type{ActivePowerInVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 0.0
get_variable_upper_bound(::Type{ActivePowerInVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_input_active_power_limits(d, PSY.SU).max
get_variable_multiplier(::Type{ActivePowerInVariable}, d::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = -1.0

########################### ActivePowerOutVariable, Storage #################################
get_variable_binary(::Type{ActivePowerOutVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_lower_bound(::Type{ActivePowerOutVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 0.0
get_variable_upper_bound(::Type{ActivePowerOutVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_output_active_power_limits(d, PSY.SU).max
get_variable_multiplier(::Type{ActivePowerOutVariable}, d::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = 1.0

########################### ReactivePowerVariable, Storage #################################
get_variable_binary(::Type{ReactivePowerVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_lower_bound(::Type{ReactivePowerVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).min
get_variable_upper_bound(::Type{ReactivePowerVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_reactive_power_limits(d, PSY.SU).max
get_variable_multiplier(::Type{ReactivePowerVariable}, d::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = 1.0

############## EnergyVariable, Storage ####################
get_variable_binary(::Type{EnergyVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_upper_bound(::Type{EnergyVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_storage_level_limits(d).max * PSY.get_storage_capacity(d, PSY.SU) * PSY.get_conversion_factor(d)
get_variable_lower_bound(::Type{EnergyVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_storage_level_limits(d).min * PSY.get_storage_capacity(d, PSY.SU) * PSY.get_conversion_factor(d)
get_variable_warm_start_value(::Type{EnergyVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = PSY.get_initial_storage_capacity_level(d) * PSY.get_storage_capacity(d, PSY.SU) * PSY.get_conversion_factor(d)

############## ReservationVariable, Storage ####################
get_variable_binary(::Type{ReservationVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = true

############## Ancillary Services Variables ####################
get_variable_binary(::Type{AncillaryServiceVariableDischarge}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_binary(::Type{AncillaryServiceVariableCharge}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false

function get_variable_upper_bound(::Type{AncillaryServiceVariableCharge}, r::PSY.Reserve, d::PSY.Storage, ::Type{<:AbstractStorageFormulation})
    return PSY.get_max_output_fraction(r) * PSY.get_input_active_power_limits(d, PSY.SU).max
end

function get_variable_upper_bound(::Type{AncillaryServiceVariableDischarge}, r::PSY.Reserve, d::PSY.Storage, ::Type{<:AbstractStorageFormulation})
    return PSY.get_max_output_fraction(r) * PSY.get_output_active_power_limits(d, PSY.SU).max
end

function get_variable_upper_bound(::Type{AncillaryServiceVariableCharge}, r::Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation})
    return PSY.get_input_active_power_limits(d, PSY.SU).max
end

function get_variable_upper_bound(::Type{AncillaryServiceVariableDischarge}, r::Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation})
    return PSY.get_output_active_power_limits(d, PSY.SU).max
end

function get_variable_upper_bound(::Type{ActivePowerReserveVariable}, r::PSY.Reserve, d::PSY.Storage, ::Type{<:AbstractReservesFormulation})
    return PSY.get_max_output_fraction(r) * (PSY.get_output_active_power_limits(d, PSY.SU).max + PSY.get_input_active_power_limits(d, PSY.SU).max)
end
function get_variable_upper_bound(::Type{ActivePowerReserveVariable}, r::Union{PSY.ReserveDemandCurve, PSY.ReserveDemandTimeSeriesCurve}, d::PSY.Storage, ::Type{<:AbstractReservesFormulation})
    return PSY.get_max_output_fraction(r) * (PSY.get_output_active_power_limits(d, PSY.SU).max + PSY.get_input_active_power_limits(d, PSY.SU).max)
end

get_expression_type_for_reserve(::Type{ActivePowerReserveVariable}, ::Type{<:PSY.Storage}, ::Type{<:PSY.Reserve}) = TotalReserveOffering

############### Energy Targets Variables #############
get_variable_binary(::Type{StorageEnergyShortageVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_binary(::Type{StorageEnergySurplusVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false

############### Cycling Limits Variables #############
get_variable_binary(::Type{StorageChargeCyclingSlackVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_binary(::Type{StorageDischargeCyclingSlackVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false

########################Objective Function##################################################
objective_function_multiplier(::Type{<:VariableType}, ::Type{<:AbstractStorageFormulation})=OBJECTIVE_FUNCTION_POSITIVE
objective_function_multiplier(::Type{StorageEnergySurplusVariable}, ::Type{<:AbstractStorageFormulation})=OBJECTIVE_FUNCTION_POSITIVE
objective_function_multiplier(::Type{StorageEnergyShortageVariable}, ::Type{<:AbstractStorageFormulation})=OBJECTIVE_FUNCTION_POSITIVE

proportional_cost(cost::PSY.StorageCost, ::Type{StorageEnergySurplusVariable}, ::PSY.EnergyReservoirStorage, ::Type{<:AbstractStorageFormulation})=PSY.get_energy_surplus_cost(cost)
proportional_cost(cost::PSY.StorageCost, ::Type{StorageEnergyShortageVariable}, ::PSY.EnergyReservoirStorage, ::Type{<:AbstractStorageFormulation})=PSY.get_energy_shortage_cost(cost)
proportional_cost(::PSY.StorageCost, ::Type{StorageChargeCyclingSlackVariable}, ::PSY.EnergyReservoirStorage, ::Type{<:AbstractStorageFormulation})=CYCLE_VIOLATION_COST
proportional_cost(::PSY.StorageCost, ::Type{StorageDischargeCyclingSlackVariable}, ::PSY.EnergyReservoirStorage, ::Type{<:AbstractStorageFormulation})=CYCLE_VIOLATION_COST


IOM.variable_cost(cost::PSY.StorageCost, ::Type{ActivePowerOutVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation})=PSY.get_discharge_variable_cost(cost)
IOM.variable_cost(cost::PSY.StorageCost, ::Type{ActivePowerInVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation})=PSY.get_charge_variable_cost(cost)

######################## Parameters ##################################################

get_parameter_multiplier(::Type{EnergyTargetParameter}, ::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 1.0
get_parameter_multiplier(::Type{EnergyLimitParameter}, ::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 1.0
get_parameter_multiplier(::Type{LowerBoundValueParameter}, ::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 1.0
get_parameter_multiplier(::Type{UpperBoundValueParameter}, ::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 1.0

############## ReservationVariable, Storage ####################
get_variable_binary(::Type{<:StorageRegularizationVariable}, ::Type{<:PSY.Storage}, ::Type{<:AbstractStorageFormulation}) = false
get_variable_upper_bound(::Type{<:StorageRegularizationVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = max(PSY.get_input_active_power_limits(d, PSY.SU).max, PSY.get_output_active_power_limits(d, PSY.SU).max)
get_variable_lower_bound(::Type{<:StorageRegularizationVariable}, d::PSY.Storage, ::Type{<:AbstractStorageFormulation}) = 0.0

#! format: on

_include_min_gen_power_in_constraint(
    ::PSY.EnergyReservoirStorage,
    ::ActivePowerOutVariable,
    ::AbstractStorageFormulation,
) = false
_include_min_gen_power_in_constraint(
    ::PSY.EnergyReservoirStorage,
    ::ActivePowerInVariable,
    ::AbstractStorageFormulation,
) = false

function IOM.variable_cost(
    ::PSY.StorageCost,
    ::Type{<:StorageRegularizationVariable},
    ::Type{<:PSY.Storage},
    ::Type{<:AbstractStorageFormulation},
)
    return PSY.CostCurve(PSY.LinearCurve(STORAGE_REG_COST), PSY.SU)
end

function get_default_time_series_names(
    ::Type{D},
    ::Type{<:Union{FixedOutput, AbstractStorageFormulation}},
) where {D <: PSY.Storage}
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{PSY.EnergyReservoirStorage},
    ::Type{T},
) where {T <: AbstractStorageFormulation}
    return Dict{String, Any}(
        "reservation" => true,
        "cycling_limits" => false,
        "energy_target" => false,
        "complete_coverage" => false,
        "regularization" => false,
    )
end

######################## Make initial Conditions for a Model ####################
get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{T, <:AbstractStorageFormulation},
) where {T <: PSY.Storage} = model

initial_condition_default(
    ::InitialEnergyLevel,
    d::PSY.Storage,
    ::AbstractStorageFormulation,
) =
    PSY.get_initial_storage_capacity_level(d) *
    PSY.get_storage_capacity(d, PSY.SU) *
    PSY.get_conversion_factor(d)
initial_condition_variable(
    ::InitialEnergyLevel,
    d::PSY.Storage,
    ::AbstractStorageFormulation,
) = EnergyVariable()

function initial_conditions!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{St},
    formulation::AbstractStorageFormulation,
) where {St <: PSY.Storage}
    add_initial_condition!(container, devices, formulation, InitialEnergyLevel())
    return
end

############################# Power Constraints ###########################
get_min_max_limits(
    device::PSY.Storage,
    ::Type{<:ReactivePowerVariableLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
) = PSY.get_reactive_power_limits(device, PSY.SU)
get_min_max_limits(
    device::PSY.Storage,
    ::Type{InputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
) = PSY.get_input_active_power_limits(device, PSY.SU)
get_min_max_limits(
    device::PSY.Storage,
    ::Type{OutputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
) = PSY.get_output_active_power_limits(device, PSY.SU)

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: Union{
        OutputActivePowerVariableLimitsConstraint, InputActivePowerVariableLimitsConstraint,
    },
    U <: Union{ActivePowerOutVariable, ActivePowerInVariable},
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: AbstractNetworkModel,
}
    if get_attribute(model, "reservation")
        add_reserve_range_constraints!(container, T, U, devices, model, X)
    else
        add_range_constraints!(container, T, U, devices, model, X)
    end
    return
end

# Direction-dependent reserve-deployment expression pairs and max-limit accessors.
# For OutputActivePower (discharge), "effective power" is `P_out + up - down`.
# For InputActivePower (charge), it's `P_in + down - up` — reserves swap roles because
# a charging battery's net power is increased by downward reserves.
_deployment_increasing_expr(::Type{<:OutputActivePowerVariableLimitsConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide}
_deployment_decreasing_expr(::Type{<:OutputActivePowerVariableLimitsConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide}
_deployment_increasing_expr(::Type{<:InputActivePowerVariableLimitsConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide}
_deployment_decreasing_expr(::Type{<:InputActivePowerVariableLimitsConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide}

# Reservation-binary handling: discharge active when ss=1, charge active when ss=0.
_reservation_factor(::Type{<:OutputActivePowerVariableLimitsConstraint}, ss, name, t) =
    ss[name, t]
_reservation_factor(::Type{<:InputActivePowerVariableLimitsConstraint}, ss, name, t) =
    1.0 - ss[name, t]

function _add_deployment_upper_bound!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W};
    with_reservation::Bool,
) where {
    T <: Union{
        OutputActivePowerVariableLimitsConstraint, InputActivePowerVariableLimitsConstraint,
    },
    U <: Union{ActivePowerOutVariable, ActivePowerInVariable},
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(x) for x in devices]
    jump_model = get_jump_model(container)
    power_var = get_variable(container, U, V)
    r_inc = get_expression(container, _deployment_increasing_expr(T), V)
    r_dec = get_expression(container, _deployment_decreasing_expr(T), V)
    ss_var = with_reservation ? get_variable(container, ReservationVariable, V) : nothing

    constraint = add_constraints_container!(container, T, V, names, time_steps)
    for d in devices, t in time_steps
        ci_name = PSY.get_name(d)
        effective_power =
            power_var[ci_name, t] + r_inc[ci_name, t] - r_dec[ci_name, t]
        bound = IOM.get_bound(IOM.UpperBound(), IOM.get_min_max_limits(d, T, W))
        bin = with_reservation ? _reservation_factor(T, ss_var, ci_name, t) : 1.0
        IOM.add_range_bound_constraint!(
            IOM.UpperBound(), jump_model, constraint, ci_name, t,
            effective_power, bound, bin,
        )
    end
    return
end

add_reserve_range_constraint_with_deployment!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices,
    model::DeviceModel,
    ::NetworkModel,
) where {T, U} =
    _add_deployment_upper_bound!(
        container, T, U, devices, model; with_reservation = true)

add_reserve_range_constraint_with_deployment_no_reservation!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices,
    model::DeviceModel,
    ::NetworkModel,
) where {T, U} =
    _add_deployment_upper_bound!(
        container, T, U, devices, model; with_reservation = false)

function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ReactivePowerVariableLimitsConstraint},
    U::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.Storage, W <: AbstractStorageFormulation, X <: AbstractNetworkModel}
    add_range_constraints!(container, T, U, devices, model, X)
    return
end

############################# Energy Constraints ###########################
"""
Min and max limits for Energy Capacity Constraint and AbstractStorageFormulation
"""
function get_min_max_limits(
    d::PSY.Storage,
    ::Type{StateofChargeLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
)
    min_max_limits = (
        min = PSY.get_storage_level_limits(d).min *
              PSY.get_storage_capacity(d, PSY.SU) *
              PSY.get_conversion_factor(d),
        max = PSY.get_storage_level_limits(d).max *
              PSY.get_storage_capacity(d, PSY.SU) *
              PSY.get_conversion_factor(d),
    )
    return min_max_limits
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StateofChargeLimitsConstraint},
    ::Type{EnergyVariable},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.Storage, W <: AbstractStorageFormulation, X <: AbstractNetworkModel}
    add_range_constraints!(
        container,
        StateofChargeLimitsConstraint,
        EnergyVariable,
        devices,
        model,
        X,
    )
    return
end

############################# Add Variable Logic ###########################
function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{F},
) where {
    T <: Union{AncillaryServiceVariableDischarge, AncillaryServiceVariableCharge},
    U <: PSY.Storage,
    F <: AbstractStorageFormulation,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    services = Set()
    for d in devices
        union!(services, PSY.get_services(d))
    end
    for service in services
        variable = add_variable_container!(container, T,
            U,
            PSY.get_name.(devices),
            time_steps;
            meta = "$(typeof(service))_$(PSY.get_name(service))",
        )

        for d in devices, t in time_steps
            name = PSY.get_name(d)
            variable[name, t] = JuMP.@variable(
                get_jump_model(container),
                base_name = "$(T)_$(PSY.get_name(service))_{$(PSY.get_name(d)), $(t)}",
                lower_bound = 0.0,
                upper_bound =
                    get_variable_upper_bound(T, service, d, F)
            )
        end
    end
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{<:AbstractStorageFormulation},
) where {
    T <: Union{StorageEnergyShortageVariable, StorageEnergySurplusVariable},
    U <: PSY.Storage,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    last_time_range = time_steps[end]:time_steps[end]
    variable = add_variable_container!(container, T,
        U,
        PSY.get_name.(devices),
        last_time_range,
    )
    for d in devices
        name = PSY.get_name(d)
        variable[name, time_steps[end]] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_{$(PSY.get_name(d))}",
            lower_bound = 0.0
        )
    end
    return
end

# no test coverage
function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{<:AbstractStorageFormulation},
) where {
    T <: Union{StorageChargeCyclingSlackVariable, StorageDischargeCyclingSlackVariable},
    U <: PSY.Storage,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    last_time_range = time_steps[end]:time_steps[end]
    variable = add_variable_container!(container, T,
        U,
        PSY.get_name.(devices),
        last_time_range,
    )
    for d in devices
        name = PSY.get_name(d)
        variable[name, time_steps[end]] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_{$(PSY.get_name(d))}",
            lower_bound = 0.0
        )
    end
    return
end

############################# Expression Logic for Ancillary Services ######################
get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{
        StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide},
    },
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{
        StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide},
    },
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

### Deployment ###
get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
    },
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
    },
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide}},
    d::PSY.Storage,
    ::Type{StorageDispatchWithReserves},
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

#! format: off
# Use 1.0 because this is to allow to reuse the code below on add_to_expression
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}}, d::PSY.Reserve) = 1.0
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}}, d::PSY.Reserve) = 1.0
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide}}, d::PSY.Reserve) = 1.0
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}}, d::PSY.Reserve) = 1.0

# Needs to implement served fraction in PSY
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide}}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide}}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide}}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide}}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
#! format: on

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaPTDFNetworkModel},
) where {
    T <: ActivePowerBalance,
    U <: Union{ActivePowerOutVariable, ActivePowerInVariable},
    V <: PSY.Storage,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U, V)
    area_expr = get_expression(container, T, PSY.Area)
    nodal_expr = get_expression(container, T, PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        area_name = PSY.get_name(PSY.get_area(device_bus))
        bus_no = PNM.get_mapped_bus_number(network_reduction, device_bus)
        for t in get_time_steps(container)
            add_proportional_to_jump_expression!(
                area_expr[area_name, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
            add_proportional_to_jump_expression!(
                nodal_expr[bus_no, t],
                variable[name, t],
                get_variable_multiplier(U, V, W),
            )
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <:
    StorageReserveBalanceExpression{<:PSY.ReserveDirection, <:ReserveScale, ChargeSide},
    U <: AncillaryServiceVariableCharge,
    V <: PSY.Storage,
    W <: StorageDispatchWithReserves,
}
    expression = get_expression(container, T, V)
    for d in devices
        name = PSY.get_name(d)
        services = PSY.get_services(d)
        for s in services
            s_name = PSY.get_name(s)
            variable = get_variable(container, U, V, "$(typeof(s))_$s_name")
            mult = get_variable_multiplier(U, T, d, W, s) * get_fraction(T, s)
            for t in get_time_steps(container)
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

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <:
    StorageReserveBalanceExpression{<:PSY.ReserveDirection, <:ReserveScale, DischargeSide},
    U <: AncillaryServiceVariableDischarge,
    V <: PSY.Storage,
    W <: StorageDispatchWithReserves,
}
    expression = get_expression(container, T, V)
    for d in devices
        name = PSY.get_name(d)
        services = PSY.get_services(d)
        for s in services
            s_name = PSY.get_name(s)
            variable = get_variable(container, U, V, "$(typeof(s))_$s_name")
            mult = get_variable_multiplier(U, T, d, W, s) * get_fraction(T, s)
            for t in get_time_steps(container)
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

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
) where {
    T <: TotalReserveOffering,
    U <: Union{AncillaryServiceVariableDischarge, AncillaryServiceVariableCharge},
    V <: PSY.Storage,
    W <: StorageDispatchWithReserves,
}
    for d in devices
        name = PSY.get_name(d)
        services = PSY.get_services(d)
        for s in services
            s_name = PSY.get_name(s)
            expression = get_expression(container, T, V, "$(typeof(s))_$(s_name)")
            variable = get_variable(container, U, V, "$(typeof(s))_$s_name")
            for t in get_time_steps(container)
                add_proportional_to_jump_expression!(
                    expression[name, t],
                    variable[name, t],
                    1.0,
                )
            end
        end
    end
    return
end

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
    UV <: PSY.Storage,
    V <: PSY.Reserve,
    W <: AbstractReservesFormulation,
}
    s_name = PSY.get_name(service)
    variable = get_variable(container, U, V)
    for d in devices
        name = PSY.get_name(d)
        expression = get_expression(container, T, UV, "$(V)_$(s_name)")
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

"""
Add Energy Balance Constraints for AbstractStorageFormulation
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{EnergyBalanceConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: AbstractNetworkModel}
    if has_service_model(model)
        add_energybalance_with_reserves!(container, devices, model, network_model)
    else
        add_energybalance_without_reserves!(container, devices, model, network_model)
    end
end

function add_energybalance_with_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)

    powerin_var = get_variable(container, ActivePowerInVariable, V)
    powerout_var = get_variable(container, ActivePowerOutVariable, V)

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

    constraint = add_constraints_container!(container, EnergyBalanceConstraint,
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        device = IOM.get_component(ic)
        efficiency = PSY.get_efficiency(device)
        name = PSY.get_name(device)
        constraint[name, 1] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, 1] ==
            get_value(ic) +
            (
                (
                    (powerin_var[name, 1] + r_dn_ch[name, 1] - r_up_ch[name, 1]) *
                    efficiency.in
                ) - (
                    (powerout_var[name, 1] + r_up_ds[name, 1] - r_dn_ds[name, 1]) /
                    efficiency.out
                )
            ) * fraction_of_hour
        )

        for t in time_steps[2:end]
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                energy_var[name, t] ==
                energy_var[name, t - 1] +
                (
                    (
                        (powerin_var[name, t] + r_dn_ch[name, t] - r_up_ch[name, t]) *
                        efficiency.in
                    ) - (
                        (powerout_var[name, t] + r_up_ds[name, t] - r_dn_ds[name, t]) /
                        efficiency.out
                    )
                ) * fraction_of_hour
            )
        end
    end
    return
end

function add_energybalance_without_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)

    powerin_var = get_variable(container, ActivePowerInVariable, V)
    powerout_var = get_variable(container, ActivePowerOutVariable, V)

    constraint = add_constraints_container!(container, EnergyBalanceConstraint,
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        device = IOM.get_component(ic)
        efficiency = PSY.get_efficiency(device)
        name = PSY.get_name(device)
        constraint[name, 1] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, 1] ==
            get_value(ic) +
            (
                (powerin_var[name, 1] * efficiency.in) -
                (powerout_var[name, 1] / efficiency.out)
            ) * fraction_of_hour
        )

        for t in time_steps[2:end]
            constraint[name, t] = JuMP.@constraint(
                get_jump_model(container),
                energy_var[name, t] ==
                energy_var[name, t - 1] +
                (
                    (powerin_var[name, t] * efficiency.in) -
                    (powerout_var[name, t] / efficiency.out)
                ) * fraction_of_hour
            )
        end
    end
    return
end

# Reserve-assignment bounds for discharge (Up) / charge (Down):
#   UB: power + up_assignment <= max
#   LB: power - down_assignment >= min
# Same shape for both directions, parametrized by the "assignment" expression pair and
# power variable/limits; routed through `IOM.add_range_bound_constraint!`.
_reserve_assignment_power_var(::Type{ReserveDischargeConstraint}) = ActivePowerOutVariable
_reserve_assignment_power_var(::Type{ReserveChargeConstraint}) = ActivePowerInVariable
_reserve_assignment_up_expr(::Type{ReserveDischargeConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, DischargeSide}
_reserve_assignment_down_expr(::Type{ReserveDischargeConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, DischargeSide}
_reserve_assignment_up_expr(::Type{ReserveChargeConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveUp, UnscaledReserve, ChargeSide}
_reserve_assignment_down_expr(::Type{ReserveChargeConstraint}) =
    StorageReserveBalanceExpression{PSY.ReserveDown, UnscaledReserve, ChargeSide}
_reserve_assignment_limits(::Type{ReserveDischargeConstraint}, d) =
    PSY.get_output_active_power_limits(d, PSY.SU)
_reserve_assignment_limits(::Type{ReserveChargeConstraint}, d) =
    PSY.get_input_active_power_limits(d, PSY.SU)

"""
Reserve-assignment range constraints for discharge (T = ReserveDischargeConstraint)
and charge (T = ReserveChargeConstraint) under `StorageDispatchWithReserves`.
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {
    T <: Union{ReserveDischargeConstraint, ReserveChargeConstraint},
    V <: PSY.Storage,
    X <: AbstractNetworkModel,
}
    names = String[PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    jump_model = get_jump_model(container)
    power_var = get_variable(container, _reserve_assignment_power_var(T), V)
    r_up = get_expression(container, _reserve_assignment_up_expr(T), V)
    r_dn = get_expression(container, _reserve_assignment_down_expr(T), V)

    con_ub = add_constraints_container!(container, T, V, names, time_steps; meta = "ub")
    con_lb = add_constraints_container!(container, T, V, names, time_steps; meta = "lb")
    for d in devices, t in time_steps
        name = PSY.get_name(d)
        limits = _reserve_assignment_limits(T, d)
        IOM.add_range_bound_constraint!(
            IOM.UpperBound(), jump_model, con_ub, name, t,
            power_var[name, t] + r_up[name, t], limits.max)
        IOM.add_range_bound_constraint!(
            IOM.LowerBound(), jump_model, con_lb, name, t,
            power_var[name, t] - r_dn[name, t], limits.min)
    end
    return
end

time_offset(::Type{ReserveCoverageConstraint}) = -1
time_offset(::Type{ReserveCoverageConstraintEndOfPeriod}) = 0
time_offset(::Type{ReserveCompleteCoverageConstraint}) = -1
time_offset(::Type{ReserveCompleteCoverageConstraintEndOfPeriod}) = 0

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {
    T <: Union{ReserveCoverageConstraint, ReserveCoverageConstraintEndOfPeriod},
    V <: PSY.Storage,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)

    services_set = Set()
    for ic in initial_conditions
        storage = IOM.get_component(ic)
        union!(services_set, PSY.get_services(storage))
    end

    for service in services_set
        service_name = PSY.get_name(service)
        if typeof(service) <: PSY.Reserve{PSY.ReserveUp}
            add_constraints_container!(container, T,
                V,
                names,
                time_steps;
                meta = "$(typeof(service))_$(service_name)_discharge",
            )
        elseif typeof(service) <: PSY.Reserve{PSY.ReserveDown}
            add_constraints_container!(container, T,
                V,
                names,
                time_steps;
                meta = "$(typeof(service))_$(service_name)_charge",
            )
        end
    end

    for ic in initial_conditions
        storage = IOM.get_component(ic)
        ci_name = PSY.get_name(storage)
        inv_efficiency = 1.0 / PSY.get_efficiency(storage).out
        eff_in = PSY.get_efficiency(storage).in
        soc_limits = (
            min = PSY.get_storage_level_limits(storage).min *
                  PSY.get_storage_capacity(storage, PSY.SU) *
                  PSY.get_conversion_factor(storage),
            max = PSY.get_storage_level_limits(storage).max *
                  PSY.get_storage_capacity(storage, PSY.SU) *
                  PSY.get_conversion_factor(storage),
        )
        for service in PSY.get_services(storage)
            sustained_time = PSY.get_sustained_time(service)
            num_periods = sustained_time / Dates.value(Dates.Second(resolution))
            sustained_param_discharge = inv_efficiency * fraction_of_hour * num_periods
            sustained_param_charge = eff_in * fraction_of_hour * num_periods
            service_name = PSY.get_name(service)
            reserve_var_discharge =
                get_variable(container, AncillaryServiceVariableDischarge,
                    V,
                    "$(typeof(service))_$service_name",
                )
            reserve_var_charge = get_variable(container, AncillaryServiceVariableCharge,
                V,
                "$(typeof(service))_$service_name",
            )
            if typeof(service) <: PSY.Reserve{PSY.ReserveUp}
                con_discharge = get_constraint(
                    container,
                    T(),
                    V,
                    "$(typeof(service))_$(service_name)_discharge",
                )

                if time_offset(T) == -1
                    con_discharge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_discharge * reserve_var_discharge[ci_name, 1] <=
                        get_value(ic) - soc_limits.min
                    )
                elseif time_offset(T) == 0
                    con_discharge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_discharge * reserve_var_discharge[ci_name, 1] <=
                        energy_var[ci_name, 1] - soc_limits.min
                    )
                else
                    @assert false
                end
                for t in time_steps[2:end]
                    con_discharge[ci_name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_discharge * reserve_var_discharge[ci_name, t] <=
                        energy_var[ci_name, t + time_offset(T)] - soc_limits.min
                    )
                end
            elseif typeof(service) <: PSY.Reserve{PSY.ReserveDown}
                con_charge = get_constraint(
                    container,
                    T(),
                    V,
                    "$(typeof(service))_$(service_name)_charge",
                )
                if time_offset(T) == -1
                    con_charge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_charge * reserve_var_charge[ci_name, 1] <=
                        soc_limits.max - get_value(ic)
                    )
                elseif time_offset(T) == 0
                    con_charge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_charge * reserve_var_charge[ci_name, 1] <=
                        soc_limits.max - energy_var[ci_name, 1]
                    )
                else
                    @assert false
                end

                for t in time_steps[2:end]
                    con_charge[ci_name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        sustained_param_charge * reserve_var_charge[ci_name, t] <=
                        soc_limits.max - energy_var[ci_name, t + time_offset(T)]
                    )
                end

            else
                @assert false
            end
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {
    T <:
    Union{ReserveCompleteCoverageConstraint, ReserveCompleteCoverageConstraintEndOfPeriod},
    V <: PSY.Storage,
    X <: AbstractNetworkModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable, V)

    services_set = Set()
    for ic in initial_conditions
        storage = IOM.get_component(ic)
        union!(services_set, PSY.get_services(storage))
    end

    services_types = unique(typeof.(services_set))

    for serv_type in services_types
        if serv_type <: PSY.Reserve{PSY.ReserveUp}
            add_constraints_container!(container, T,
                V,
                names,
                time_steps;
                meta = "$(serv_type)_discharge",
            )
        elseif serv_type <: PSY.Reserve{PSY.ReserveDown}
            add_constraints_container!(container, T,
                V,
                names,
                time_steps;
                meta = "$(serv_type)_charge",
            )
        end
    end

    for ic in initial_conditions
        storage = IOM.get_component(ic)
        ci_name = PSY.get_name(storage)
        inv_efficiency = 1.0 / PSY.get_efficiency(storage).out
        eff_in = PSY.get_efficiency(storage).in
        soc_limits = (
            min = PSY.get_storage_level_limits(storage).min *
                  PSY.get_storage_capacity(storage, PSY.SU) *
                  PSY.get_conversion_factor(storage),
            max = PSY.get_storage_level_limits(storage).max *
                  PSY.get_storage_capacity(storage, PSY.SU) *
                  PSY.get_conversion_factor(storage),
        )
        expr_up_discharge = Set()
        expr_dn_charge = Set()
        for service in PSY.get_services(storage)
            sustained_time = PSY.get_sustained_time(service)
            num_periods = sustained_time / Dates.value(Dates.Second(resolution))
            sustained_param_discharge = inv_efficiency * fraction_of_hour * num_periods
            sustained_param_charge = eff_in * fraction_of_hour * num_periods
            service_name = PSY.get_name(service)
            reserve_var_discharge =
                get_variable(container, AncillaryServiceVariableDischarge,
                    V,
                    "$(typeof(service))_$service_name",
                )
            reserve_var_charge = get_variable(container, AncillaryServiceVariableCharge,
                V,
                "$(typeof(service))_$service_name",
            )
            if typeof(service) <: PSY.Reserve{PSY.ReserveUp}
                push!(
                    expr_up_discharge,
                    sustained_param_discharge * reserve_var_discharge[ci_name, :],
                )
            elseif typeof(service) <: PSY.Reserve{PSY.ReserveDown}
                push!(
                    expr_dn_charge,
                    sustained_param_charge * reserve_var_charge[ci_name, :],
                )
            else
                @assert false
            end
        end
        for serv_type in services_types
            if serv_type <: PSY.Reserve{PSY.ReserveUp}
                con_discharge =
                    get_constraint(container, T(), V, "$(serv_type)_discharge")
                total_sustained = JuMP.AffExpr()
                for vds in expr_up_discharge
                    JuMP.add_to_expression!(total_sustained, vds[1])
                end
                if time_offset(T) == -1
                    con_discharge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <= get_value(ic) - soc_limits.min
                    )
                elseif time_offset(T) == 0
                    con_discharge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <= energy_var[ci_name, 1] - soc_limits.min
                    )
                else
                    @assert false
                end
                for t in time_steps[2:end]
                    total_sustained = JuMP.AffExpr()
                    for vds in expr_up_discharge
                        JuMP.add_to_expression!(total_sustained, vds[t])
                    end
                    con_discharge[ci_name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <=
                        energy_var[ci_name, t + time_offset(T)] - soc_limits.min
                    )
                end
            elseif serv_type <: PSY.Reserve{PSY.ReserveDown}
                con_charge = get_constraint(container, T(), V, "$(serv_type)_charge")
                total_sustained = JuMP.AffExpr()
                for vch in expr_dn_charge
                    JuMP.add_to_expression!(total_sustained, vch[1])
                end
                if time_offset(T) == -1
                    con_charge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <= soc_limits.max - get_value(ic)
                    )
                elseif time_offset(T) == 0
                    con_charge[ci_name, 1] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <= soc_limits.max - energy_var[ci_name, 1]
                    )
                else
                    @assert false
                end

                for t in time_steps[2:end]
                    total_sustained = JuMP.AffExpr()
                    for vch in expr_dn_charge
                        JuMP.add_to_expression!(total_sustained, vch[t])
                    end
                    con_charge[ci_name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        total_sustained <=
                        soc_limits.max - energy_var[ci_name, t + time_offset(T)]
                    )
                end
            else
                @assert false
            end
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageTotalReserveConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: AbstractNetworkModel}
    services = Set()
    for d in devices
        union!(services, PSY.get_services(d))
    end

    for s in services
        s_name = PSY.get_name(s)
        expression = get_expression(container, TotalReserveOffering,
            V,
            "$(typeof(s))_$(s_name)",
        )
        device_names, time_steps = axes(expression)
        constraint_container =
            add_constraints_container!(container, StorageTotalReserveConstraint,
                typeof(s),
                device_names,
                time_steps;
                meta = "$(s_name)_$V",
            )
        for name in device_names, t in time_steps
            constraint_container[name, t] =
                JuMP.@constraint(get_jump_model(container), expression[name, t] == 0.0)
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StateofChargeTargetConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    energy_var = get_variable(container, EnergyVariable, V)
    surplus_var = get_variable(container, StorageEnergySurplusVariable, V)
    shortfall_var = get_variable(container, StorageEnergyShortageVariable, V)

    device_names, time_steps = axes(energy_var)
    constraint_container =
        add_constraints_container!(container, StateofChargeTargetConstraint,
            V,
            device_names,
            [time_steps[end]],
        )

    for d in devices
        name = PSY.get_name(d)
        target = PSY.get_storage_target(d)
        constraint_container[name, time_steps[end]] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, time_steps[end]] - surplus_var[name, time_steps[end]] +
            shortfall_var[name, time_steps[end]] == target
        )
    end

    return
end

function add_cycling_charge_without_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, ActivePowerInVariable, V)
    slack_var = get_variable(container, StorageChargeCyclingSlackVariable, V)

    constraint = add_constraints_container!(
        container, StorageCyclingCharge, V, names, [time_steps[end]])

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d, PSY.SU) *
            PSY.get_conversion_factor(d)
        cycle_count = PSY.get_cycle_limits(d)
        efficiency = PSY.get_efficiency(d)
        constraint[name, time_steps[end]] = JuMP.@constraint(
            get_jump_model(container),
            sum((
                powerin_var[name, t] * efficiency.in * fraction_of_hour for t in time_steps
            )) - slack_var[name, time_steps[end]] <= e_max * cycle_count
        )
    end
    return
end

function add_cycling_charge_with_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, ActivePowerInVariable, V)
    slack_var = get_variable(container, StorageChargeCyclingSlackVariable, V)
    r_dn_ch = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
        V,
    )

    constraint = add_constraints_container!(
        container, StorageCyclingCharge, V, names, [time_steps[end]])

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d, PSY.SU) *
            PSY.get_conversion_factor(d)
        cycle_count = PSY.get_cycle_limits(d)
        efficiency = PSY.get_efficiency(d)
        constraint[name, time_steps[end]] = JuMP.@constraint(
            get_jump_model(container),
            sum((
                (powerin_var[name, t] + r_dn_ch[name, t]) *
                efficiency.in *
                fraction_of_hour for t in time_steps
            )) - slack_var[name, time_steps[end]] <= e_max * cycle_count
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageCyclingCharge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    if has_service_model(model)
        add_cycling_charge_with_reserves!(container, devices, model, network_model)
    else
        add_cycling_charge_without_reserves!(container, devices, model, network_model)
    end
    return
end

function add_cycling_discharge_without_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, ActivePowerOutVariable, V)
    slack_var = get_variable(container, StorageDischargeCyclingSlackVariable, V)

    constraint =
        add_constraints_container!(
            container, StorageCyclingDischarge, V, names, [time_steps[end]])

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d, PSY.SU) *
            PSY.get_conversion_factor(d)
        cycle_count = PSY.get_cycle_limits(d)
        efficiency = PSY.get_efficiency(d)
        constraint[name, time_steps[end]] = JuMP.@constraint(
            get_jump_model(container),
            sum(
                (powerout_var[name, t] / efficiency.out) * fraction_of_hour for
                t in time_steps
            ) - slack_var[name, time_steps[end]] <= e_max * cycle_count
        )
    end
    return
end

function add_cycling_discharge_with_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, ActivePowerOutVariable, V)
    slack_var = get_variable(container, StorageDischargeCyclingSlackVariable, V)
    r_up_ds = get_expression(
        container,
        StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
        V,
    )

    constraint =
        add_constraints_container!(
            container, StorageCyclingDischarge, V, names, [time_steps[end]])

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d, PSY.SU) *
            PSY.get_conversion_factor(d)
        cycle_count = PSY.get_cycle_limits(d)
        efficiency = PSY.get_efficiency(d)
        constraint[name, time_steps[end]] = JuMP.@constraint(
            get_jump_model(container),
            sum(
                ((powerout_var[name, t] + r_up_ds[name, t]) / efficiency.out) *
                fraction_of_hour for t in time_steps
            ) - slack_var[name, time_steps[end]] <= e_max * cycle_count
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageCyclingDischarge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: AbstractNetworkModel}
    if has_service_model(model)
        add_cycling_discharge_with_reserves!(container, devices, model, network_model)
    else
        add_cycling_discharge_without_reserves!(container, devices, model, network_model)
    end
    return
end

# Trait stubs for the unified Charge/Discharge regularization body. Sign
# convention for net injection: charge nets to (p − r_up + r_dn); discharge
# nets to (p + r_up − r_dn). Mirrors the hybrid pair in
# src/hybrid_system_models/hybrid_systems.jl.
_storage_reg_slack_var(::Type{StorageRegularizationConstraintCharge}) =
    StorageRegularizationVariableCharge
_storage_reg_slack_var(::Type{StorageRegularizationConstraintDischarge}) =
    StorageRegularizationVariableDischarge
_storage_reg_power_var(::Type{StorageRegularizationConstraintCharge}) =
    ActivePowerInVariable
_storage_reg_power_var(::Type{StorageRegularizationConstraintDischarge}) =
    ActivePowerOutVariable
_storage_reg_reserve_exprs(::Type{StorageRegularizationConstraintCharge}) =
    (
        StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, ChargeSide},
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, ChargeSide},
    )
_storage_reg_reserve_exprs(::Type{StorageRegularizationConstraintDischarge}) =
    (
        StorageReserveBalanceExpression{PSY.ReserveUp, DeployedReserve, DischargeSide},
        StorageReserveBalanceExpression{PSY.ReserveDown, DeployedReserve, DischargeSide},
    )
_storage_reg_reserve_signs(::Type{StorageRegularizationConstraintCharge}) = (-1, +1)
_storage_reg_reserve_signs(::Type{StorageRegularizationConstraintDischarge}) = (+1, -1)

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {
    T <: Union{
        StorageRegularizationConstraintCharge,
        StorageRegularizationConstraintDischarge,
    },
    V <: PSY.Storage,
    X <: AbstractNetworkModel,
}
    names = [PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    reg_var = get_variable(container, _storage_reg_slack_var(T), V)
    p_var = get_variable(container, _storage_reg_power_var(T), V)
    has_services = has_service_model(model)
    s_up, s_dn = _storage_reg_reserve_signs(T)
    UpExpr, DnExpr = _storage_reg_reserve_exprs(T)
    r_up = has_services ? get_expression(container, UpExpr, V) : nothing
    r_dn = has_services ? get_expression(container, DnExpr, V) : nothing

    constraint_ub =
        add_constraints_container!(container, T, V, names, time_steps; meta = "ub")
    constraint_lb =
        add_constraints_container!(container, T, V, names, time_steps; meta = "lb")
    jm = get_jump_model(container)

    for d in devices
        name = PSY.get_name(d)
        constraint_ub[name, 1] = JuMP.@constraint(jm, reg_var[name, 1] == 0)
        constraint_lb[name, 1] = JuMP.@constraint(jm, reg_var[name, 1] == 0)
        for t in time_steps[2:end]
            lhs = if has_services
                (
                    p_var[name, t - 1] +
                    s_up * r_up[name, t - 1] +
                    s_dn * r_dn[name, t - 1]
                ) - (p_var[name, t] + s_up * r_up[name, t] + s_dn * r_dn[name, t])
            else
                p_var[name, t - 1] - p_var[name, t]
            end
            constraint_ub[name, t] = JuMP.@constraint(jm, lhs <= reg_var[name, t])
            constraint_lb[name, t] = JuMP.@constraint(jm, lhs >= -reg_var[name, t])
        end
    end
    return
end

########################### Objective Function and Costs ######################
# no test coverage
function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    ::Type{V},
) where {T <: PSY.Storage, U <: AbstractStorageFormulation, V <: AbstractNetworkModel}
    add_variable_cost!(container, ActivePowerOutVariable, devices, U)
    add_variable_cost!(container, ActivePowerInVariable, devices, U)
    if get_attribute(model, "regularization")
        add_variable_cost!(
            container,
            StorageRegularizationVariableCharge,
            devices,
            U,
        )
        add_variable_cost!(
            container,
            StorageRegularizationVariableDischarge,
            devices,
            U,
        )
    end

    return
end

function add_to_objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{PSY.EnergyReservoirStorage},
    model::DeviceModel{PSY.EnergyReservoirStorage, T},
    ::Type{V},
) where {T <: AbstractStorageFormulation, V <: AbstractNetworkModel}
    # TODO problem with time varying MBC.
    add_variable_cost!(container, ActivePowerOutVariable, devices, T)
    add_variable_cost!(container, ActivePowerInVariable, devices, T)
    if get_attribute(model, "energy_target")
        add_proportional_cost!(container, StorageEnergySurplusVariable, devices, T)
        add_proportional_cost!(container, StorageEnergyShortageVariable, devices, T)
    end
    if get_attribute(model, "cycling_limits")
        add_proportional_cost!(
            container,
            StorageChargeCyclingSlackVariable,
            devices,
            T,
        )
        add_proportional_cost!(
            container,
            StorageDischargeCyclingSlackVariable,
            devices,
            T,
        )
    end
    if get_attribute(model, "regularization")
        add_variable_cost!(
            container,
            StorageRegularizationVariableCharge,
            devices,
            T,
        )
        add_variable_cost!(
            container,
            StorageRegularizationVariableDischarge,
            devices,
            T,
        )
    end
    return
end

# Storage cycling/energy-target slack penalties are applied only at the final timestep
# (a single horizon-end accumulator), not per-timestep — so we can't delegate to the
# IOM default `add_proportional_cost!`, which loops over all timesteps.
# no test coverage
function add_proportional_cost!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{U},
    ::Type{F},
) where {
    T <: Union{
        StorageChargeCyclingSlackVariable, StorageDischargeCyclingSlackVariable,
        StorageEnergyShortageVariable, StorageEnergySurplusVariable,
    },
    U <: PSY.EnergyReservoirStorage,
    F <: AbstractStorageFormulation,
}
    t_end = last(get_time_steps(container))
    variable = get_variable(container, T, U)
    for d in devices
        name = PSY.get_name(d)
        op_cost_data = PSY.get_operation_cost(d)
        cost_term = proportional_cost(op_cost_data, T, d, F)
        IOM.add_cost_term_invariant!(
            container, variable[name, t_end], cost_term,
            ProductionCostExpression, U, name, t_end,
        )
    end
end

function calculate_aux_variable_value!(
    container::OptimizationContainer,
    ::AuxVarKey{StorageEnergyOutput, T},
    system::PSY.System,
) where {T <: PSY.Storage}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    p_variable_output = get_variable(container, ActivePowerOutVariable, T)
    aux_variable_container = get_aux_variable(container, StorageEnergyOutput, T)
    device_names = axes(aux_variable_container, 1)
    for name in device_names, t in time_steps
        aux_variable_container[name, t] =
            jump_value(p_variable_output[name, t]) * fraction_of_hour
    end

    return
end
