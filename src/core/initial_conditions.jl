"""
Initial condition for volume in reservoir in [`PowerSystems.HydroReservoir`](@extref) formulations
"""
struct InitialReservoirVolume <: InitialConditionType end

######################### Initial Conditions Definitions#####################################
struct DevicePower <: InitialConditionType end
struct DeviceAboveMinPower <: InitialConditionType end
struct DeviceStatus <: InitialConditionType end
struct InitialTimeDurationOn <: InitialConditionType end
struct InitialTimeDurationOff <: InitialConditionType end
struct InitialEnergyLevel <: InitialConditionType end
struct AreaControlError <: InitialConditionType end

# Decide whether to run the initial conditions reconciliation algorithm based on the presence of any of these
requires_reconciliation(::Type{<:InitialConditionType}) = false

requires_reconciliation(::Type{InitialTimeDurationOn}) = true
requires_reconciliation(::Type{InitialTimeDurationOff}) = true
requires_reconciliation(::Type{DeviceStatus}) = true
requires_reconciliation(::Type{DevicePower}) = true # to capture a case when device is off in HA but producing power in ED
requires_reconciliation(::Type{DeviceAboveMinPower}) = true # ramping limits may make power differences in thermal compact devices between models infeasible
requires_reconciliation(::Type{InitialEnergyLevel}) = true # large differences in initial storage levels could lead to infeasibilities
# Not requiring reconciliation for AreaControlError
