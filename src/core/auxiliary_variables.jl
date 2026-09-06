"""
Auxiliary Variable for Thermal Generation Models to keep track of time elapsed on
"""
struct TimeDurationOn <: AuxVariableType end

"""
Auxiliary Variable for Thermal Generation Models to keep track of time elapsed off
"""
struct TimeDurationOff <: AuxVariableType end

"""
Auxiliary Variable for Thermal Generation Models that solve for power above min
"""
struct PowerOutput <: AuxVariableType end

"""
Auxiliary Variable of DC Current Variables for DC Lines formulations
Docs abbreviation: ``p_l^{loss}``
"""
struct DCLineLosses <: AuxVariableType end

"""
Auxiliary Variables that are calculated using a `PowerFlowEvaluationModel`
"""
abstract type PowerFlowAuxVariableType <: AuxVariableType end

"""
Auxiliary Variable for the bus angle outputs from power flow evaluation
"""
struct PowerFlowVoltageAngle <: PowerFlowAuxVariableType end

"""
Auxiliary Variable for the bus voltage magnitude outputs from power flow evaluation
"""
struct PowerFlowVoltageMagnitude <: PowerFlowAuxVariableType end

"""
Auxiliary Variable for line power flow outputs from power flow evaluation
"""
abstract type BranchFlowAuxVariableType <: PowerFlowAuxVariableType end

"""
Auxiliary Variable for the line reactive flow in the from -> to direction from power flow evaluation
"""
struct PowerFlowBranchReactivePowerFromTo <: BranchFlowAuxVariableType end

"""
Auxiliary Variable for the line reactive flow in the to -> from direction from power flow evaluation
"""
struct PowerFlowBranchReactivePowerToFrom <: BranchFlowAuxVariableType end

"""
Auxiliary Variable for the line active flow in the from -> to direction from power flow evaluation
"""
struct PowerFlowBranchActivePowerFromTo <: BranchFlowAuxVariableType end

"""
Auxiliary Variable for the line active flow in the to -> from direction from power flow evaluation
"""
struct PowerFlowBranchActivePowerToFrom <: BranchFlowAuxVariableType end

"""
Auxiliary Variable for the loss factors from AC power flow evaluation that are calculated using the Jacobian matrix
"""
struct PowerFlowLossFactors <: PowerFlowAuxVariableType end

"""
Auxiliary Variable for the voltage stability factors from AC power flow evaluation that are calculated using the Jacobian matrix
"""
struct PowerFlowVoltageStabilityFactors <: PowerFlowAuxVariableType end

# should this be a subtype of BranchFlowAuxVariableType? It's line-related but has no flow direction.
"""
Auxiliary Variable for the active power loss on a line from AC power flow evaluation.
"""
struct PowerFlowBranchActivePowerLoss <: PowerFlowAuxVariableType end

# TODO reactive loss?

convert_output_to_natural_units(::Type{PowerOutput}) = true
convert_output_to_natural_units(
    ::Type{
        <:Union{
            PowerFlowBranchReactivePowerFromTo, PowerFlowBranchReactivePowerToFrom,
            PowerFlowBranchActivePowerFromTo, PowerFlowBranchActivePowerToFrom,
            PowerFlowBranchActivePowerLoss,
        },
    },
) = true

"""
The `PowerFlowAuxVariableType`s that are defined over components of type `C` — i.e. whose
values are indexed by branch or by bus. This is the complete universe of power flow
auxiliary variables; which *subset* of it a particular power flow evaluator actually
provides is the `_pf_provides_aux_var` trait in the `PowerFlowsExt`.

Returns a tuple rather than a `Vector` deliberately: callers iterate it with `map`, so each
element keeps its concrete `Type{T}` and the `_pf_provides_aux_var` calls resolve at
compile time. Adding a `PowerFlowAuxVariableType` means adding it here and giving it
`_pf_provides_aux_var` methods; `test_power_flow_in_the_loop.jl` asserts by reflection that
no concrete subtype is missing from these tuples, so a forgotten entry fails in CI rather
than silently never registering.
"""
function pf_aux_var_types end

pf_aux_var_types(::Type{PSY.ACBranch}) = (
    PowerFlowBranchReactivePowerFromTo,
    PowerFlowBranchReactivePowerToFrom,
    PowerFlowBranchActivePowerFromTo,
    PowerFlowBranchActivePowerToFrom,
    PowerFlowBranchActivePowerLoss,
)

pf_aux_var_types(::Type{PSY.ACBus}) = (
    PowerFlowVoltageAngle,
    PowerFlowVoltageMagnitude,
    PowerFlowLossFactors,
    PowerFlowVoltageStabilityFactors,
)

"Whether the auxiliary variable is calculated using a `PowerFlowEvaluationModel`"
# Default is_from_evaluator(::Type{<:AuxVariableType}) = false is in IOM interfaces.jl
is_from_evaluator(::Type{<:PowerFlowAuxVariableType}) = true
