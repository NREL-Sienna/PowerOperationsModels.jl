"""
Fallback: `construct_market_component!` for `ArgumentConstructStage` and
`ModelConstructStage`. Mirrors the `construct_device!` fallback in `core/interfaces.jl`.
"""
function construct_market_component!(
    ::OptimizationContainer,
    ::IS.ComponentContainer,
    ::M,
    model::DeviceModel{D, F},
    ::IOM.MarketModel,
) where {
    M <: IOM.ConstructStage,
    D <: IS.InfrastructureSystemsComponent,
    F <: IOM.AbstractDeviceFormulation,
}
    error(
        "construct_market_component! not implemented for market component type $D with " *
        "formulation $F at $(_to_string(M)). Implement this method to add market-clearing " *
        "variables and expressions.",
    )
end

function construct_market_components!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    template::PowerOperationsProblemTemplate,
)
    market_model = get_market_model(template)
    market_model === nothing && return
    add_physical_bids_to_settlement!(container, template, sys)
    for component_model in values(IOM.get_market_component_models(market_model))
        construct_market_component!(
            container,
            sys,
            ArgumentConstructStage(),
            component_model,
            market_model,
        )
    end
    return
end

function construct_market_components!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    template::PowerOperationsProblemTemplate,
)
    market_model = get_market_model(template)
    market_model === nothing && return
    component_models = IOM.get_market_component_models(market_model)
    # Unreachable on a validated template -- `_check_market_model!` (template_validation.jl)
    # rejects an empty market model first. Kept so an unvalidated caller fails loudly rather
    # than building a settlement equality with nothing to clear against.
    if isempty(component_models)
        error(
            "Market model $(typeof(market_model)) has no market component models. This " *
            "should have been rejected at template validation; do not call " *
            "construct_market_components! on an unvalidated template.",
        )
    end
    for component_model in values(component_models)
        construct_market_component!(
            container,
            sys,
            ModelConstructStage(),
            component_model,
            market_model,
        )
    end
    add_constraints!(container, SettlementBalanceConstraint, sys, market_model)
    add_constraint_dual!(container, sys, market_model)
    return
end
