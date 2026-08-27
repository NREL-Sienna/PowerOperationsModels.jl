#################################################################################
# No-op stubs for event functions
#
# The contingency/event infrastructure lives in PowerSimulations.jl and has not yet
# been moved into POM. These stubs allow constructor code (which calls
# add_event_arguments!, etc.) to compile and run correctly when no events are
# configured. Once the event code is migrated, these stubs should be replaced by
# the real implementations.
#
# The feedforward stubs that used to live here have been replaced by the real
# device-side implementations in `src/feedforward/`.
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

function add_event_constraints!(
    ::OptimizationContainer,
    ::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    ::DeviceModel,
    ::NetworkModel,
) where {V <: PSY.Component}
    return
end
