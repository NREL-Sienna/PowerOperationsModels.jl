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

# Fallback for device models with no outage-constraint implementation. It must stay a
# no-op for the empty-events case (every constructor calls this unconditionally), but a
# device model that carries events and lands here would get availability parameters that
# nothing in the optimization enforces — a silent wrong model — so that case errors.
function add_event_constraints!(
    ::OptimizationContainer,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    device_model::DeviceModel,
    ::NetworkModel,
) where {V <: PSY.Component}
    if !isempty(get_events(device_model))
        error(
            "DeviceModel{$(get_component_type(device_model)), \
             $(get_formulation(device_model))} has event models attached but no \
             add_event_constraints! implementation; its devices would get availability \
             parameters that no constraint enforces. Remove the event model or implement \
             event constraints for this device model.",
        )
    end
    return
end
# requires SemiContinuousFeedforward to be defined, which probably belongs in PSI
has_semicontinuous_feedforward(
    model::DeviceModel,
    ::Type{T},
) where {T <: Union{VariableType, ExpressionType}} = false
