#################################################################################
# Fallback / stub definitions for functions that are defined and called
# entirely within POM (no call sites in IOM).
#################################################################################

_to_string(::Type{IOM.ArgumentConstructStage}) = "ArgumentConstructStage"
_to_string(::Type{IOM.ModelConstructStage}) = "ModelConstructStage"

"""
Fallback: `construct_device!` for `ArgumentConstructStage` and `ModelConstructStage`.
"""
function construct_device!(
    ::IOM.OptimizationContainer,
    ::IS.ComponentContainer,
    ::M,
    model::IOM.DeviceModel{D, F},
    network_model::IOM.NetworkModel{S},
) where {
    M <: IOM.ConstructStage,
    D <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
    S,
}
    error(
        "construct_device! not implemented for device type $D with formulation $F " *
        "at $(_to_string(M)). Implement this method to add variables and expressions.",
    )
end

function construct_service!(
    ::IOM.OptimizationContainer,
    ::IS.ComponentContainer,
    ::IOM.ConstructStage,
    model::IOM.ServiceModel{S, F},
    devices_template::Dict{Symbol, IOM.DeviceModel},
    incompatible_device_types::Set{<:DataType},
    network_model::IOM.NetworkModel{N},
) where {S <: PSY.Service, F <: IOM.AbstractServiceFormulation, N}
    error(
        "construct_service! not implemented for service type $S with formulation $F.",
    )
end

"""
Add objective function contributions for devices.
"""
function add_to_objective_function!(
    ::IOM.OptimizationContainer,
    ::Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    ::IOM.DeviceModel{U, F},
    ::Type{S},
) where {
    U <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
    S <: PM.AbstractPowerModel,
}
    error(
        "add_to_objective_function! not implemented for device type $U with formulation $F and power model $S.",
    )
    return
end

"""
Add constraints to the optimization container.
"""
function add_constraints!(
    ::IOM.OptimizationContainer,
    ::Type{T},
    devices::Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    model::IOM.DeviceModel{U, F},
    network_model::IOM.NetworkModel{S},
) where {
    T <: IS.Optimization.ConstraintType,
    U <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
    S,
}
    error(
        "add_constraints! not implemented for constraint type $T, " *
        "device type $U with formulation $F.",
    )
end

"""
Get the multiplier for a variable type when adding to an expression.
Default implementation returns 1.0.
"""
get_variable_multiplier(
    ::IS.Optimization.VariableType,
    ::Type{<:IS.InfrastructureSystemsComponent},
    ::IOM.AbstractDeviceFormulation,
) = 1.0

"""
Get the multiplier for an expression type based on parameter type.
"""
function get_expression_multiplier(
    ::P,
    ::Type{T},
    ::D,
    ::F,
) where {
    P <: IS.Optimization.ParameterType,
    T <: IS.Optimization.ExpressionType,
    D <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
}
    error(
        "get_expression_multiplier not implemented for parameter $P, expression $T, " *
        "device $D, formulation $F.",
    )
end

"""
Get multiplier value for a time series parameter.
"""
function get_multiplier_value(
    ::T,
    ::U,
    ::F,
) where {
    T <: IOM.TimeSeriesParameter,
    U <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
}
    return 1.0
end

"""
Get the multiplier value for a parameter type.
"""
function get_multiplier_value(
    ::P,
    ::D,
    ::F,
) where {
    P <: IS.Optimization.ParameterType,
    D <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
}
    error(
        "get_multiplier_value not implemented for parameter $P, device $D, formulation $F.",
    )
end

"""
Add power flow evaluation data to the container.
"""
function add_power_flow_data!(
    ::IOM.OptimizationContainer,
    evaluators::Vector{<:IOM.AbstractPowerFlowEvaluationModel},
    ::IS.ComponentContainer,
)
    if !isempty(evaluators)
        error(
            "Power flow in-the-loop with the new IOM-POM-PSI split isn't working yet.",
        )
    end
end

"""
Get the device model to use for initialization.
"""
get_initial_conditions_device_model(
    ::IOM.OperationModel,
    model::IOM.DeviceModel{T, IOM.FixedOutput},
) where {T <: PSY.Device} = model

get_initial_conditions_device_model(
    ::IOM.OperationModel,
    ::IOM.DeviceModel{T, D},
) where {T <: PSY.Device, D <: IOM.AbstractDeviceFormulation} =
    error("`get_initial_conditions_device_model` must be implemented for $T and $D")
