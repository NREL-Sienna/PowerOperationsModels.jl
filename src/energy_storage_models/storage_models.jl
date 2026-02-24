#! format: off
requires_initialization(::AbstractStorageFormulation) = false

get_variable_multiplier(_, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = NaN
########################### ActivePowerInVariable, Storage #################################
get_variable_binary(::ActivePowerInVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_lower_bound(::ActivePowerInVariable, d::PSY.Storage, ::AbstractStorageFormulation) = 0.0
get_variable_upper_bound(::ActivePowerInVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_input_active_power_limits(d).max
get_variable_multiplier(::ActivePowerInVariable, d::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = -1.0

########################### ActivePowerOutVariable, Storage #################################
get_variable_binary(::ActivePowerOutVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_lower_bound(::ActivePowerOutVariable, d::PSY.Storage, ::AbstractStorageFormulation) = 0.0
get_variable_upper_bound(::ActivePowerOutVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_output_active_power_limits(d).max
get_variable_multiplier(::ActivePowerOutVariable, d::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = 1.0

########################### ReactivePowerVariable, Storage #################################
get_variable_binary(::ReactivePowerVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_lower_bound(::ReactivePowerVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_reactive_power_limits(d).min
get_variable_upper_bound(::ReactivePowerVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_reactive_power_limits(d).max
get_variable_multiplier(::ReactivePowerVariable, d::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = 1.0

############## EnergyVariable, Storage ####################
get_variable_binary(::EnergyVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_upper_bound(::EnergyVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_storage_level_limits(d).max * PSY.get_storage_capacity(d) * PSY.get_conversion_factor(d)
get_variable_lower_bound(::EnergyVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_storage_level_limits(d).min * PSY.get_storage_capacity(d) * PSY.get_conversion_factor(d)
get_variable_warm_start_value(::EnergyVariable, d::PSY.Storage, ::AbstractStorageFormulation) = PSY.get_initial_storage_capacity_level(d) * PSY.get_storage_capacity(d) * PSY.get_conversion_factor(d)

############## ReservationVariable, Storage ####################
get_variable_binary(::ReservationVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = true

############## Ancillary Services Variables ####################
get_variable_binary(::AncillaryServiceVariableDischarge, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_binary(::AncillaryServiceVariableCharge, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false

function get_variable_upper_bound(::AncillaryServiceVariableCharge, r::PSY.Reserve, d::PSY.Storage, ::AbstractStorageFormulation)
    return PSY.get_max_output_fraction(r) * PSY.get_input_active_power_limits(d).max
end

function get_variable_upper_bound(::AncillaryServiceVariableDischarge, r::PSY.Reserve, d::PSY.Storage, ::AbstractStorageFormulation)
    return PSY.get_max_output_fraction(r) * PSY.get_output_active_power_limits(d).max
end

function get_variable_upper_bound(::AncillaryServiceVariableCharge, r::PSY.ReserveDemandCurve, d::PSY.Storage, ::AbstractStorageFormulation)
    return PSY.get_input_active_power_limits(d).max
end

function get_variable_upper_bound(::AncillaryServiceVariableDischarge, r::PSY.ReserveDemandCurve, d::PSY.Storage, ::AbstractStorageFormulation)
    return PSY.get_output_active_power_limits(d).max
end

function get_variable_upper_bound(::ActivePowerReserveVariable, r::PSY.Reserve, d::PSY.Storage, ::AbstractReservesFormulation)
    return PSY.get_max_output_fraction(r) * (PSY.get_output_active_power_limits(d).max + PSY.get_input_active_power_limits(d).max)
end
function get_variable_upper_bound(::ActivePowerReserveVariable, r::PSY.ReserveDemandCurve, d::PSY.Storage, ::AbstractReservesFormulation)
    return PSY.get_max_output_fraction(r) * (PSY.get_output_active_power_limits(d).max + PSY.get_input_active_power_limits(d).max)
end

get_expression_type_for_reserve(::ActivePowerReserveVariable, ::Type{<:PSY.Storage}, ::Type{<:PSY.Reserve}) = TotalReserveOffering

############### Energy Targets Variables #############
get_variable_binary(::StorageEnergyShortageVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_binary(::StorageEnergySurplusVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false

############### Cycling Limits Variables #############
get_variable_binary(::StorageChargeCyclingSlackVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_binary(::StorageDischargeCyclingSlackVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false

########################Objective Function##################################################
objective_function_multiplier(::VariableType, ::AbstractStorageFormulation)=OBJECTIVE_FUNCTION_POSITIVE
objective_function_multiplier(::StorageEnergySurplusVariable, ::AbstractStorageFormulation)=OBJECTIVE_FUNCTION_POSITIVE
objective_function_multiplier(::StorageEnergyShortageVariable, ::AbstractStorageFormulation)=OBJECTIVE_FUNCTION_POSITIVE

proportional_cost(cost::PSY.StorageCost, ::StorageEnergySurplusVariable, ::PSY.EnergyReservoirStorage, ::AbstractStorageFormulation)=PSY.get_energy_surplus_cost(cost)
proportional_cost(cost::PSY.StorageCost, ::StorageEnergyShortageVariable, ::PSY.EnergyReservoirStorage, ::AbstractStorageFormulation)=PSY.get_energy_shortage_cost(cost)
proportional_cost(::PSY.StorageCost, ::StorageChargeCyclingSlackVariable, ::PSY.EnergyReservoirStorage, ::AbstractStorageFormulation)=CYCLE_VIOLATION_COST
proportional_cost(::PSY.StorageCost, ::StorageDischargeCyclingSlackVariable, ::PSY.EnergyReservoirStorage, ::AbstractStorageFormulation)=CYCLE_VIOLATION_COST


variable_cost(cost::PSY.StorageCost, ::ActivePowerOutVariable, ::PSY.Storage, ::AbstractStorageFormulation)=PSY.get_discharge_variable_cost(cost)
variable_cost(cost::PSY.StorageCost, ::ActivePowerInVariable, ::PSY.Storage, ::AbstractStorageFormulation)=PSY.get_charge_variable_cost(cost)

######################## Parameters ##################################################

get_parameter_multiplier(::EnergyTargetParameter, ::PSY.Storage, ::AbstractStorageFormulation) = 1.0
get_parameter_multiplier(::EnergyLimitParameter, ::PSY.Storage, ::AbstractStorageFormulation) = 1.0
get_parameter_multiplier(::LowerBoundValueParameter, ::PSY.Storage, ::AbstractStorageFormulation) = 1.0
get_parameter_multiplier(::UpperBoundValueParameter, ::PSY.Storage, ::AbstractStorageFormulation) = 1.0

############## ReservationVariable, Storage ####################
get_variable_binary(::StorageRegularizationVariable, ::Type{<:PSY.Storage}, ::AbstractStorageFormulation) = false
get_variable_upper_bound(::StorageRegularizationVariable, d::PSY.Storage, ::AbstractStorageFormulation) = max(PSY.get_input_active_power_limits(d).max, PSY.get_output_active_power_limits(d).max)
get_variable_lower_bound(::StorageRegularizationVariable, d::PSY.Storage, ::AbstractStorageFormulation) = 0.0

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

function variable_cost(
    cost::PSY.StorageCost,
    ::StorageRegularizationVariable,
    ::PSY.Storage,
    ::AbstractStorageFormulation,
)
    return PSY.CostCurve(PSY.LinearCurve(STORAGE_REG_COST), PSY.UnitSystem.SYSTEM_BASE)
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
    ::OperationModel,
    model::DeviceModel{T, <:AbstractStorageFormulation},
) where {T <: PSY.Storage} = model

initial_condition_default(
    ::InitialEnergyLevel,
    d::PSY.Storage,
    ::AbstractStorageFormulation,
) =
    PSY.get_initial_storage_capacity_level(d) *
    PSY.get_storage_capacity(d) *
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
) = PSY.get_reactive_power_limits(device)
get_min_max_limits(
    device::PSY.Storage,
    ::Type{InputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
) = PSY.get_input_active_power_limits(device)
get_min_max_limits(
    device::PSY.Storage,
    ::Type{OutputActivePowerVariableLimitsConstraint},
    ::Type{<:AbstractStorageFormulation},
) = PSY.get_output_active_power_limits(device)

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: OutputActivePowerVariableLimitsConstraint,
    U <: ActivePowerOutVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    if get_attribute(model, "reservation")
        add_reserve_range_constraints!(container, T, U, devices, model, X)
    else
        add_range_constraints!(container, T, U, devices, model, X)
    end
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: ActivePowerInVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    if get_attribute(model, "reservation")
        add_reserve_range_constraints!(container, T, U, devices, model, X)
    else
        add_range_constraints!(container, T, U, devices, model, X)
    end
end

function add_reserve_range_constraint_with_deployment!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: OutputActivePowerVariableLimitsConstraint,
    U <: ActivePowerOutVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, U(), V)
    ss_var = get_variable(container, ReservationVariable(), V)
    r_up_ds = get_expression(container, ReserveDeploymentBalanceUpDischarge(), V)
    r_dn_ds = get_expression(container, ReserveDeploymentBalanceDownDischarge(), V)

    constraint = add_constraints_container!(container, T(), V, names, time_steps)

    for d in devices, t in time_steps
        ci_name = PSY.get_name(d)
        constraint[ci_name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerout_var[ci_name, t] + r_up_ds[ci_name, t] - r_dn_ds[ci_name, t] <=
            ss_var[ci_name, t] * PSY.get_output_active_power_limits(d).max
        )
    end
end

function add_reserve_range_constraint_with_deployment!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: ActivePowerInVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, U(), V)
    ss_var = get_variable(container, ReservationVariable(), V)
    r_up_ch = get_expression(container, ReserveDeploymentBalanceUpCharge(), V)
    r_dn_ch = get_expression(container, ReserveDeploymentBalanceDownCharge(), V)

    constraint = add_constraints_container!(container, T(), V, names, time_steps)

    for d in devices, t in time_steps
        ci_name = PSY.get_name(d)
        constraint[ci_name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerin_var[ci_name, t] + r_dn_ch[ci_name, t] - r_up_ch[ci_name, t] <=
            (1.0 - ss_var[ci_name, t]) * PSY.get_input_active_power_limits(d).max
        )
    end
end

function add_reserve_range_constraint_with_deployment_no_reservation!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: OutputActivePowerVariableLimitsConstraint,
    U <: ActivePowerOutVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, U(), V)
    r_up_ds = get_expression(container, ReserveDeploymentBalanceUpDischarge(), V)
    r_dn_ds = get_expression(container, ReserveDeploymentBalanceDownDischarge(), V)

    constraint = add_constraints_container!(container, T(), V, names, time_steps)

    for d in devices, t in time_steps
        ci_name = PSY.get_name(d)
        constraint[ci_name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerout_var[ci_name, t] + r_up_ds[ci_name, t] - r_dn_ds[ci_name, t] <=
            PSY.get_output_active_power_limits(d).max
        )
    end
end

function add_reserve_range_constraint_with_deployment_no_reservation!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: ActivePowerInVariable,
    V <: PSY.Storage,
    W <: AbstractStorageFormulation,
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, U(), V)
    r_up_ch = get_expression(container, ReserveDeploymentBalanceUpCharge(), V)
    r_dn_ch = get_expression(container, ReserveDeploymentBalanceDownCharge(), V)

    constraint = add_constraints_container!(container, T(), V, names, time_steps)

    for d in devices, t in time_steps
        ci_name = PSY.get_name(d)
        constraint[ci_name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerin_var[ci_name, t] + r_dn_ch[ci_name, t] - r_up_ch[ci_name, t] <=
            PSY.get_input_active_power_limits(d).max
        )
    end
end

function add_constraints!(
    container::OptimizationContainer,
    T::Type{<:ReactivePowerVariableLimitsConstraint},
    U::Type{<:ReactivePowerVariable},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, W},
    ::NetworkModel{X},
) where {V <: PSY.Storage, W <: AbstractStorageFormulation, X <: PM.AbstractPowerModel}
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
              PSY.get_storage_capacity(d) *
              PSY.get_conversion_factor(d),
        max = PSY.get_storage_level_limits(d).max *
              PSY.get_storage_capacity(d) *
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
) where {V <: PSY.Storage, W <: AbstractStorageFormulation, X <: PM.AbstractPowerModel}
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
    formulation::AbstractStorageFormulation,
) where {
    T <: Union{AncillaryServiceVariableDischarge, AncillaryServiceVariableCharge},
    U <: PSY.Storage,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    services = Set()
    for d in devices
        union!(services, PSY.get_services(d))
    end
    for service in services
        variable = add_variable_container!(
            container,
            T(),
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
                    get_variable_upper_bound(T(), service, d, formulation)
            )
        end
    end
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{T},
    devices::IS.FlattenIteratorWrapper{U},
    formulation::AbstractStorageFormulation,
) where {
    T <: Union{StorageEnergyShortageVariable, StorageEnergySurplusVariable},
    U <: PSY.Storage,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    last_time_range = time_steps[end]:time_steps[end]
    variable = add_variable_container!(
        container,
        T(),
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
    formulation::AbstractStorageFormulation,
) where {
    T <: Union{StorageChargeCyclingSlackVariable, StorageDischargeCyclingSlackVariable},
    U <: PSY.Storage,
}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    last_time_range = time_steps[end]:time_steps[end]
    variable = add_variable_container!(
        container,
        T(),
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
    ::Type{ReserveAssignmentBalanceDownCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveAssignmentBalanceDownCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveAssignmentBalanceUpCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveAssignmentBalanceUpCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveAssignmentBalanceDownDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveAssignmentBalanceDownDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveAssignmentBalanceUpDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveAssignmentBalanceUpDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

### Deployment ###
get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveDeploymentBalanceDownCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveDeploymentBalanceDownCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveDeploymentBalanceUpCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableCharge},
    ::Type{ReserveDeploymentBalanceUpCharge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveDeploymentBalanceDownDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 0.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveDeploymentBalanceDownDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveDeploymentBalanceUpDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveUp},
) = 1.0

get_variable_multiplier(
    ::Type{AncillaryServiceVariableDischarge},
    ::Type{ReserveDeploymentBalanceUpDischarge},
    d::PSY.Storage,
    ::StorageDispatchWithReserves,
    ::PSY.Reserve{PSY.ReserveDown},
) = 0.0

#! format: off
# Use 1.0 because this is to allow to reuse the code below on add_to_expression
get_fraction(::Type{ReserveAssignmentBalanceUpDischarge}, d::PSY.Reserve) = 1.0
get_fraction(::Type{ReserveAssignmentBalanceUpCharge}, d::PSY.Reserve) = 1.0
get_fraction(::Type{ReserveAssignmentBalanceDownDischarge}, d::PSY.Reserve) = 1.0
get_fraction(::Type{ReserveAssignmentBalanceDownCharge}, d::PSY.Reserve) = 1.0

# Needs to implement served fraction in PSY
get_fraction(::Type{ReserveDeploymentBalanceUpDischarge}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{ReserveDeploymentBalanceUpCharge}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{ReserveDeploymentBalanceDownDischarge}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
get_fraction(::Type{ReserveDeploymentBalanceDownCharge}, d::PSY.Reserve) = PSY.get_deployed_fraction(d)
#! format: on

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{AreaPTDFPowerModel},
) where {
    T <: ActivePowerBalance,
    U <: Union{ActivePowerOutVariable, ActivePowerInVariable},
    V <: PSY.Storage,
    W <: AbstractDeviceFormulation,
}
    variable = get_variable(container, U(), V)
    area_expr = get_expression(container, T(), PSY.Area)
    nodal_expr = get_expression(container, T(), PSY.ACBus)
    network_reduction = get_network_reduction(network_model)
    for d in devices
        name = PSY.get_name(d)
        device_bus = PSY.get_bus(d)
        area_name = PSY.get_name(PSY.get_area(device_bus))
        bus_no = PNM.get_mapped_bus_number(network_reduction, device_bus)
        for t in get_time_steps(container)
            _add_to_jump_expression!(
                area_expr[area_name, t],
                variable[name, t],
                get_variable_multiplier(U(), V, W()),
            )
            _add_to_jump_expression!(
                nodal_expr[bus_no, t],
                variable[name, t],
                get_variable_multiplier(U(), V, W()),
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
    T <: StorageReserveChargeExpression,
    U <: AncillaryServiceVariableCharge,
    V <: PSY.Storage,
    W <: StorageDispatchWithReserves,
}
    expression = get_expression(container, T(), V)
    for d in devices
        name = PSY.get_name(d)
        services = PSY.get_services(d)
        for s in services
            s_name = PSY.get_name(s)
            variable = get_variable(container, U(), V, "$(typeof(s))_$s_name")
            mult = get_variable_multiplier(U, T, d, W(), s) * get_fraction(T, s)
            for t in get_time_steps(container)
                _add_to_jump_expression!(expression[name, t], variable[name, t], mult)
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
    T <: StorageReserveDischargeExpression,
    U <: AncillaryServiceVariableDischarge,
    V <: PSY.Storage,
    W <: StorageDispatchWithReserves,
}
    expression = get_expression(container, T(), V)
    for d in devices
        name = PSY.get_name(d)
        services = PSY.get_services(d)
        for s in services
            s_name = PSY.get_name(s)
            variable = get_variable(container, U(), V, "$(typeof(s))_$s_name")
            mult = get_variable_multiplier(U, T, d, W(), s) * get_fraction(T, s)
            for t in get_time_steps(container)
                _add_to_jump_expression!(expression[name, t], variable[name, t], mult)
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
            expression = get_expression(container, T(), V, "$(typeof(s))_$(s_name)")
            variable = get_variable(container, U(), V, "$(typeof(s))_$s_name")
            for t in get_time_steps(container)
                _add_to_jump_expression!(expression[name, t], variable[name, t], 1.0)
            end
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Vector{UV},
    service_model::ServiceModel{V, W},
) where {
    T <: TotalReserveOffering,
    U <: ActivePowerReserveVariable,
    UV <: PSY.Storage,
    V <: PSY.Reserve,
    W <: AbstractReservesFormulation,
}
    for d in devices
        name = PSY.get_name(d)
        s_name = get_service_name(service_model)
        expression = get_expression(container, T(), UV, "$(V)_$(s_name)")
        variable = get_variable(container, U(), V, s_name)
        for t in get_time_steps(container)
            _add_to_jump_expression!(expression[name, t], variable[name, t], -1.0)
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
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
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
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable(), V)

    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)

    r_up_ds = get_expression(container, ReserveDeploymentBalanceUpDischarge(), V)
    r_up_ch = get_expression(container, ReserveDeploymentBalanceUpCharge(), V)
    r_dn_ds = get_expression(container, ReserveDeploymentBalanceDownDischarge(), V)
    r_dn_ch = get_expression(container, ReserveDeploymentBalanceDownCharge(), V)

    constraint = add_constraints_container!(
        container,
        EnergyBalanceConstraint(),
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        device = get_component(ic)
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
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable(), V)

    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)

    constraint = add_constraints_container!(
        container,
        EnergyBalanceConstraint(),
        V,
        names,
        time_steps,
    )

    for ic in initial_conditions
        device = get_component(ic)
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

"""
Add Energy Balance Constraints for AbstractStorageFormulation
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{ReserveDischargeConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    names = String[PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)
    r_up_ds = get_expression(container, ReserveAssignmentBalanceUpDischarge(), V)
    r_dn_ds = get_expression(container, ReserveAssignmentBalanceDownDischarge(), V)

    constraint_ds_ub = add_constraints_container!(
        container,
        ReserveDischargeConstraint(),
        V,
        names,
        time_steps;
        meta = "ub",
    )

    constraint_ds_lb = add_constraints_container!(
        container,
        ReserveDischargeConstraint(),
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices, t in time_steps
        name = PSY.get_name(d)
        constraint_ds_ub[name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerout_var[name, t] + r_up_ds[name, t] <=
            PSY.get_output_active_power_limits(d).max
        )
        constraint_ds_lb[name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerout_var[name, t] - r_dn_ds[name, t] >=
            PSY.get_output_active_power_limits(d).min
        )
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ReserveChargeConstraint},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    names = String[PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    r_up_ch = get_expression(container, ReserveAssignmentBalanceUpCharge(), V)
    r_dn_ch = get_expression(container, ReserveAssignmentBalanceDownCharge(), V)

    constraint_ch_ub = add_constraints_container!(
        container,
        ReserveChargeConstraint(),
        V,
        names,
        time_steps;
        meta = "ub",
    )

    constraint_ch_lb = add_constraints_container!(
        container,
        ReserveChargeConstraint(),
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices, t in get_time_steps(container)
        name = PSY.get_name(d)
        constraint_ch_ub[name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerin_var[name, t] + r_dn_ch[name, t] <=
            PSY.get_input_active_power_limits(d).max
        )
        constraint_ch_lb[name, t] = JuMP.@constraint(
            get_jump_model(container),
            powerin_var[name, t] - r_up_ch[name, t] >=
            PSY.get_input_active_power_limits(d).min
        )
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
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable(), V)

    services_set = Set()
    for ic in initial_conditions
        storage = get_component(ic)
        union!(services_set, PSY.get_services(storage))
    end

    for service in services_set
        service_name = PSY.get_name(service)
        if typeof(service) <: PSY.Reserve{PSY.ReserveUp}
            add_constraints_container!(
                container,
                T(),
                V,
                names,
                time_steps;
                meta = "$(typeof(service))_$(service_name)_discharge",
            )
        elseif typeof(service) <: PSY.Reserve{PSY.ReserveDown}
            add_constraints_container!(
                container,
                T(),
                V,
                names,
                time_steps;
                meta = "$(typeof(service))_$(service_name)_charge",
            )
        end
    end

    for ic in initial_conditions
        storage = get_component(ic)
        ci_name = PSY.get_name(storage)
        inv_efficiency = 1.0 / PSY.get_efficiency(storage).out
        eff_in = PSY.get_efficiency(storage).in
        soc_limits = (
            min = PSY.get_storage_level_limits(storage).min *
                  PSY.get_storage_capacity(storage) *
                  PSY.get_conversion_factor(storage),
            max = PSY.get_storage_level_limits(storage).max *
                  PSY.get_storage_capacity(storage) *
                  PSY.get_conversion_factor(storage),
        )
        for service in PSY.get_services(storage)
            sustained_time = PSY.get_sustained_time(service)
            num_periods = sustained_time / Dates.value(Dates.Second(resolution))
            sustained_param_discharge = inv_efficiency * fraction_of_hour * num_periods
            sustained_param_charge = eff_in * fraction_of_hour * num_periods
            service_name = PSY.get_name(service)
            reserve_var_discharge = get_variable(
                container,
                AncillaryServiceVariableDischarge(),
                V,
                "$(typeof(service))_$service_name",
            )
            reserve_var_charge = get_variable(
                container,
                AncillaryServiceVariableCharge(),
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
    X <: PM.AbstractPowerModel,
}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    initial_conditions = get_initial_condition(container, InitialEnergyLevel(), V)
    energy_var = get_variable(container, EnergyVariable(), V)

    services_set = Set()
    for ic in initial_conditions
        storage = get_component(ic)
        union!(services_set, PSY.get_services(storage))
    end

    services_types = unique(typeof.(services_set))

    for serv_type in services_types
        if serv_type <: PSY.Reserve{PSY.ReserveUp}
            add_constraints_container!(
                container,
                T(),
                V,
                names,
                time_steps;
                meta = "$(serv_type)_discharge",
            )
        elseif serv_type <: PSY.Reserve{PSY.ReserveDown}
            add_constraints_container!(
                container,
                T(),
                V,
                names,
                time_steps;
                meta = "$(serv_type)_charge",
            )
        end
    end

    for ic in initial_conditions
        storage = get_component(ic)
        ci_name = PSY.get_name(storage)
        inv_efficiency = 1.0 / PSY.get_efficiency(storage).out
        eff_in = PSY.get_efficiency(storage).in
        soc_limits = (
            min = PSY.get_storage_level_limits(storage).min *
                  PSY.get_storage_capacity(storage) *
                  PSY.get_conversion_factor(storage),
            max = PSY.get_storage_level_limits(storage).max *
                  PSY.get_storage_capacity(storage) *
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
            reserve_var_discharge = get_variable(
                container,
                AncillaryServiceVariableDischarge(),
                V,
                "$(typeof(service))_$service_name",
            )
            reserve_var_charge = get_variable(
                container,
                AncillaryServiceVariableCharge(),
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
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    services = Set()
    for d in devices
        union!(services, PSY.get_services(d))
    end

    for s in services
        s_name = PSY.get_name(s)
        expression = get_expression(
            container,
            TotalReserveOffering(),
            V,
            "$(typeof(s))_$(s_name)",
        )
        device_names, time_steps = axes(expression)
        constraint_container = add_constraints_container!(
            container,
            StorageTotalReserveConstraint(),
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
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    energy_var = get_variable(container, EnergyVariable(), V)
    surplus_var = get_variable(container, StorageEnergySurplusVariable(), V)
    shortfall_var = get_variable(container, StorageEnergyShortageVariable(), V)

    device_names, time_steps = axes(energy_var)
    constraint_container = add_constraints_container!(
        container,
        StateofChargeTargetConstraint(),
        V,
        device_names,
    )

    for d in devices
        name = PSY.get_name(d)
        target = PSY.get_storage_target(d)
        constraint_container[name] = JuMP.@constraint(
            get_jump_model(container),
            energy_var[name, time_steps[end]] - surplus_var[name, time_steps[end]] +
            shortfall_var[name, time_steps[end]] == target
        )
    end

    return
end

# no test coverage
function add_cycling_charge_without_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    slack_var = get_variable(container, StorageChargeCyclingSlackVariable(), V)

    constraint = add_constraints_container!(container, StorageCyclingCharge(), V, names)

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d) *
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

# no test coverage
function add_cycling_charge_with_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]

    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    slack_var = get_variable(container, StorageChargeCyclingSlackVariable(), V)
    r_dn_ch = get_expression(container, ReserveDeploymentBalanceDownCharge(), V)

    constraint = add_constraints_container!(container, StorageCyclingCharge(), V, names)

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d) *
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

# no test coverage
function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageCyclingCharge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    if has_service_model(model)
        add_cycling_charge_with_reserves!(container, devices, model, network_model)
    else
        add_cycling_charge_without_reserves!(container, devices, model, network_model)
    end
    return
end

# no test coverage
function add_cycling_discharge_without_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)
    slack_var = get_variable(container, StorageDischargeCyclingSlackVariable(), V)

    constraint =
        add_constraints_container!(container, StorageCyclingDischarge(), V, names)

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d) *
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

# no test coverage
function add_cycling_discharge_with_reserves!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{V},
    ::DeviceModel{V, StorageDispatchWithReserves},
    ::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    time_steps = get_time_steps(container)
    resolution = get_resolution(container)
    fraction_of_hour = Dates.value(Dates.Minute(resolution)) / MINUTES_IN_HOUR
    names = [PSY.get_name(x) for x in devices]
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)
    slack_var = get_variable(container, StorageDischargeCyclingSlackVariable(), V)
    r_up_ds = get_expression(container, ReserveDeploymentBalanceUpDischarge(), V)

    constraint =
        add_constraints_container!(container, StorageCyclingDischarge(), V, names)

    for d in devices
        name = PSY.get_name(d)
        e_max =
            PSY.get_storage_level_limits(d).max *
            PSY.get_storage_capacity(d) *
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

# no test coverage
function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageCyclingDischarge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.EnergyReservoirStorage, X <: PM.AbstractPowerModel}
    if has_service_model(model)
        add_cycling_discharge_with_reserves!(container, devices, model, network_model)
    else
        add_cycling_discharge_without_reserves!(container, devices, model, network_model)
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageRegularizationConstraintCharge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    names = [PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    reg_var = get_variable(container, StorageRegularizationVariableCharge(), V)
    powerin_var = get_variable(container, ActivePowerInVariable(), V)
    has_services = has_service_model(model)

    if has_services
        r_up_ch = get_expression(container, ReserveDeploymentBalanceUpCharge(), V)
        r_dn_ch = get_expression(container, ReserveDeploymentBalanceDownCharge(), V)
    end

    constraint_ub = add_constraints_container!(
        container,
        StorageRegularizationConstraintCharge(),
        V,
        names,
        time_steps;
        meta = "ub",
    )

    constraint_lb = add_constraints_container!(
        container,
        StorageRegularizationConstraintCharge(),
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices
        name = PSY.get_name(d)
        constraint_ub[name, 1] =
            JuMP.@constraint(get_jump_model(container), reg_var[name, 1] == 0)
        constraint_lb[name, 1] =
            JuMP.@constraint(get_jump_model(container), reg_var[name, 1] == 0)

        for t in time_steps[2:end]
            if has_services
                constraint_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    (
                        powerin_var[name, t - 1] + r_dn_ch[name, t - 1] -
                        r_up_ch[name, t - 1]
                    ) - (powerin_var[name, t] + r_dn_ch[name, t] - r_up_ch[name, t]) <=
                    reg_var[name, t]
                )
                constraint_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    (
                        powerin_var[name, t - 1] + r_dn_ch[name, t - 1] -
                        r_up_ch[name, t - 1]
                    ) - (powerin_var[name, t] + r_dn_ch[name, t] - r_up_ch[name, t]) >=
                    -reg_var[name, t]
                )
            else
                constraint_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    powerin_var[name, t - 1] - powerin_var[name, t] <= reg_var[name, t]
                )
                constraint_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    powerin_var[name, t - 1] - powerin_var[name, t] >= -reg_var[name, t]
                )
            end
        end
    end

    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{StorageRegularizationConstraintDischarge},
    devices::IS.FlattenIteratorWrapper{V},
    model::DeviceModel{V, StorageDispatchWithReserves},
    network_model::NetworkModel{X},
) where {V <: PSY.Storage, X <: PM.AbstractPowerModel}
    names = [PSY.get_name(x) for x in devices]
    time_steps = get_time_steps(container)
    reg_var = get_variable(container, StorageRegularizationVariableDischarge(), V)
    powerout_var = get_variable(container, ActivePowerOutVariable(), V)
    has_services = has_service_model(model)
    if has_services
        r_up_ds = get_expression(container, ReserveDeploymentBalanceUpDischarge(), V)
        r_dn_ds = get_expression(container, ReserveDeploymentBalanceDownDischarge(), V)
    end

    constraint_ub = add_constraints_container!(
        container,
        StorageRegularizationConstraintDischarge(),
        V,
        names,
        time_steps;
        meta = "ub",
    )

    constraint_lb = add_constraints_container!(
        container,
        StorageRegularizationConstraintDischarge(),
        V,
        names,
        time_steps;
        meta = "lb",
    )

    for d in devices
        name = PSY.get_name(d)
        constraint_ub[name, 1] =
            JuMP.@constraint(get_jump_model(container), reg_var[name, 1] == 0)
        constraint_lb[name, 1] =
            JuMP.@constraint(get_jump_model(container), reg_var[name, 1] == 0)
        for t in time_steps[2:end]
            if has_services
                constraint_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    (
                        powerout_var[name, t - 1] + r_up_ds[name, t - 1] -
                        r_dn_ds[name, t - 1]
                    ) - (powerout_var[name, t] + r_up_ds[name, t] - r_dn_ds[name, t]) <=
                    reg_var[name, t]
                )
                constraint_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    (
                        powerout_var[name, t - 1] + r_up_ds[name, t - 1] -
                        r_dn_ds[name, t - 1]
                    ) - (powerout_var[name, t] + r_up_ds[name, t] - r_dn_ds[name, t]) >=
                    -reg_var[name, t]
                )
            else
                constraint_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    powerout_var[name, t - 1] - powerout_var[name, t] <= reg_var[name, t]
                )
                constraint_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    powerout_var[name, t - 1] - powerout_var[name, t] >= -reg_var[name, t]
                )
            end
        end
    end
    return
end

########################### Objective Function and Costs ######################
# no test coverage
function objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    model::DeviceModel{T, U},
    ::Type{V},
) where {T <: PSY.Storage, U <: AbstractStorageFormulation, V <: PM.AbstractPowerModel}
    add_variable_cost!(container, ActivePowerOutVariable(), devices, U())
    add_variable_cost!(container, ActivePowerInVariable(), devices, U())
    if get_attribute(model, "regularization")
        add_variable_cost!(
            container,
            StorageRegularizationVariableCharge(),
            devices,
            U(),
        )
        add_variable_cost!(
            container,
            StorageRegularizationVariableDischarge(),
            devices,
            U(),
        )
    end

    return
end

function objective_function!(
    container::OptimizationContainer,
    devices::IS.FlattenIteratorWrapper{PSY.EnergyReservoirStorage},
    model::DeviceModel{PSY.EnergyReservoirStorage, T},
    ::Type{V},
) where {T <: AbstractStorageFormulation, V <: PM.AbstractPowerModel}
    # TODO problem with time varying MBC.
    add_variable_cost!(container, ActivePowerOutVariable(), devices, T())
    add_variable_cost!(container, ActivePowerInVariable(), devices, T())
    if get_attribute(model, "energy_target")
        add_proportional_cost!(container, StorageEnergySurplusVariable(), devices, T())
        add_proportional_cost!(container, StorageEnergyShortageVariable(), devices, T())
    end
    if get_attribute(model, "cycling_limits")
        add_proportional_cost!(
            container,
            StorageChargeCyclingSlackVariable(),
            devices,
            T(),
        )
        add_proportional_cost!(
            container,
            StorageDischargeCyclingSlackVariable(),
            devices,
            T(),
        )
    end
    if get_attribute(model, "regularization")
        add_variable_cost!(
            container,
            StorageRegularizationVariableCharge(),
            devices,
            T(),
        )
        add_variable_cost!(
            container,
            StorageRegularizationVariableDischarge(),
            devices,
            T(),
        )
    end
    return
end

# no test coverage
function add_proportional_cost!(
    container::OptimizationContainer,
    ::T,
    devices::IS.FlattenIteratorWrapper{U},
    formulation::AbstractStorageFormulation,
) where {
    T <: Union{StorageChargeCyclingSlackVariable, StorageDischargeCyclingSlackVariable},
    U <: PSY.EnergyReservoirStorage,
}
    time_steps = get_time_steps(container)
    variable = get_variable(container, T(), U)
    for d in devices
        name = PSY.get_name(d)
        op_cost_data = PSY.get_operation_cost(d)
        cost_term = proportional_cost(op_cost_data, T(), d, formulation)
        add_to_objective_invariant_expression!(
            container,
            variable[name, time_steps[end]] * cost_term,
        )
    end
end

function add_proportional_cost!(
    container::OptimizationContainer,
    ::T,
    devices::IS.FlattenIteratorWrapper{U},
    formulation::AbstractStorageFormulation,
) where {
    T <: Union{StorageEnergyShortageVariable, StorageEnergySurplusVariable},
    U <: PSY.EnergyReservoirStorage,
}
    time_steps = get_time_steps(container)
    variable = get_variable(container, T(), U)
    for d in devices
        name = PSY.get_name(d)
        op_cost_data = PSY.get_operation_cost(d)
        cost_term = proportional_cost(op_cost_data, T(), d, formulation)
        add_to_objective_invariant_expression!(
            container,
            variable[name, time_steps[end]] * cost_term,
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
    p_variable_results = get_variable(container, ActivePowerOutVariable(), T)
    aux_variable_container = get_aux_variable(container, StorageEnergyOutput(), T)
    device_names = axes(aux_variable_container, 1)
    for name in device_names, t in time_steps
        aux_variable_container[name, t] =
            jump_value(p_variable_results[name, t]) * fraction_of_hour
    end

    return
end

################## Storage Systems with Market Bid Cost ###################

function _add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::T,
    component::PSY.Component,
    cost_function::PSY.MarketBidCost,
    ::U,
) where {
    T <: Union{ActivePowerOutVariable, StorageRegularizationVariableDischarge},
    U <: AbstractStorageFormulation,
}
    component_name = PSY.get_name(component)
    @debug "Market Bid" _group = LOG_GROUP_COST_FUNCTIONS component_name
    incremental_cost_curves = PSY.get_incremental_offer_curves(cost_function)
    if !isnothing(incremental_cost_curves)
        add_pwl_term!(false, container, component, cost_function, T(), U())
    end
    return
end

function _add_variable_cost_to_objective!(
    container::OptimizationContainer,
    ::T,
    component::PSY.Component,
    cost_function::PSY.MarketBidCost,
    ::U,
) where {
    T <: Union{ActivePowerInVariable, StorageRegularizationVariableCharge},
    U <: AbstractStorageFormulation,
}
    component_name = PSY.get_name(component)
    @debug "Market Bid" _group = LOG_GROUP_COST_FUNCTIONS component_name
    decremental_cost_curves = PSY.get_decremental_offer_curves(cost_function)
    if !isnothing(decremental_cost_curves)
        add_pwl_term!(true, container, component, cost_function, T(), U())
    end
    return
end
