function add_variable_cost_to_objective!(
    ::OptimizationContainer,
    ::T,
    component::PSY.Component,
    cost_function::PSY.CostCurve{IS.QuadraticCurve},
    ::U,
) where {
    T <: PowerAboveMinimumVariable,
    U <: Union{AbstractCompactUnitCommitment, ThermalCompactDispatch},
}
    throw(
        IS.ConflictingInputsError(
            "Quadratic Cost Curves are not compatible with Compact formulations",
        ),
    )
    return
end
