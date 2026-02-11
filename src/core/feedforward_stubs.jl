#################################################################################
# No-op stubs for feedforward and event functions
#
# The full feedforward and contingency/event infrastructure lives in
# PowerSimulations.jl and has not yet been moved into POM.  These stubs allow
# constructor code (which calls add_feedforward_arguments!, etc.) to compile
# and run correctly when no feedforwards or events are configured.
#
# Once the feedforward code is migrated, these stubs should be replaced by the
# real implementations.
#################################################################################

# ---- Feedforward arguments (ArgumentConstructStage) ----

function add_feedforward_arguments!(
    ::OptimizationContainer,
    ::DeviceModel,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    return
end

function add_feedforward_arguments!(
    ::OptimizationContainer,
    ::ServiceModel,
    ::PSY.Service,
)
    return
end

# ---- Feedforward constraints (ModelConstructStage) ----

function add_feedforward_constraints!(
    ::OptimizationContainer,
    ::DeviceModel,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
) where {V <: PSY.Component}
    return
end

function add_feedforward_constraints!(
    ::OptimizationContainer,
    ::ServiceModel,
    ::PSY.Service,
)
    return
end

# ---- Event arguments (ArgumentConstructStage) ----

function add_event_arguments!(
    ::OptimizationContainer,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel,
    ::NetworkModel,
) where {V <: PSY.Component}
    return
end

# ---- Event constraints (ModelConstructStage) ----

function add_event_constraints!(
    ::OptimizationContainer,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel,
    ::NetworkModel,
) where {V <: PSY.Component}
    return
end
# requires SemiContinuousFeedforward to be defined, which probably belongs in PSI
has_semicontinuous_feedforward(
    model::DeviceModel,
    ::Type{T},
) where {T <: Union{VariableType, ExpressionType}} = false
