#################################################################################
# No-op stubs for event functions
#
# The contingency/event infrastructure lives in PowerSimulations.jl and has not yet
# been moved into POM. These stubs allow constructor code (which calls
# add_event_arguments!, etc.) to compile and run correctly when no events are
# configured. Once the event code is migrated, these stubs should be replaced by
# the real implementations.
#################################################################################

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
