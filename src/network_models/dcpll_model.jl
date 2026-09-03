# DCPLL network formulation. Same bus/balance structure as DCP (voltage angles,
# reference-bus pinning, active nodal balance). Branch losses are handled by directional
# flow variables + a quadratic loss constraint in the branch construction path.
# VoltageAngle is added in the ArgumentConstructStage (network_constructor.jl generic
# method); this ModelConstructStage method closes the balance/reference constraints.

function construct_network!(
    container::OptimizationContainer,
    sys::PSY.System,
    model::NetworkModel{DCPLLNetworkModel},
    template::PowerOperationsProblemTemplate,
    ::ModelConstructStage,
)
    _construct_voltage_network!(
        container, sys, model, get_market_model(template); reactive = false,
    )
    return
end
