const _TEMPLATE_VALIDATION_EXCLUSIONS = [PSY.Arc, PSY.Area, PSY.ACBus, PSY.LoadZone]

# Reconcile the model's resolution setting against the resolutions present in the
# system's time series: set it when unset and a single resolution exists, and error on
# ambiguous (multiple-resolution) or unavailable resolutions. Shared by the DecisionModel
# and EmulationModel `validate_time_series!` methods.
function _reconcile_resolution!(settings, sys)
    available_resolutions = IOM.get_time_series_resolutions(sys)
    if get_resolution(settings) == IOM.UNSET_RESOLUTION &&
       length(available_resolutions) != 1
        throw(
            IS.ConflictingInputsError(
                "Data contains multiple resolutions, the resolution keyword argument must be added to the Model. Time Series Resolutions: $(available_resolutions)",
            ),
        )
    elseif get_resolution(settings) != IOM.UNSET_RESOLUTION &&
           length(available_resolutions) > 1
        if get_resolution(settings) ∉ available_resolutions
            throw(
                IS.ConflictingInputsError(
                    "Resolution $(get_resolution(settings)) is not available in the system data. Time Series Resolutions: $(available_resolutions)",
                ),
            )
        end
    else
        IOM.set_resolution!(settings, first(available_resolutions))
    end
    return
end

"""
The branches a service model requires to be modeled, and the services that require them.
Carried per concrete branch type so a filter can be widened per branch model, and so a
missing branch model can be reported against the service that needed it.
"""
struct ServiceBranchRequirement
    branch_names::Set{String}
    service_names::Set{String}
end

ServiceBranchRequirement() = ServiceBranchRequirement(Set{String}(), Set{String}())

# Only branch-typed contributors matter: a reserve's thermal contributors are modeled
# through their own device models and carry no flow into a service expression.
_record_service_branch!(
    ::Dict{DataType, ServiceBranchRequirement},
    ::PSY.Device,
    ::String,
) = nothing

function _record_service_branch!(
    forced::Dict{DataType, ServiceBranchRequirement},
    branch::PSY.Branch,
    service_name::String,
)
    PSY.get_available(branch) || return
    entry = get!(ServiceBranchRequirement, forced, typeof(branch))
    push!(entry.branch_names, PSY.get_name(branch))
    push!(entry.service_names, service_name)
    return
end

"""
The branches that must be modeled because a service model in the template depends on their
flow, keyed by concrete branch type. Read from the system's own contributing-device mapping
rather than from the service model's map, which has already been narrowed by component type
and so cannot report a branch type the template fails to model.
"""
function _collect_service_branch_names(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    forced = Dict{DataType, ServiceBranchRequirement}()
    service_models = get_service_models(template)
    isempty(service_models) && return forced
    network_formulation = get_network_formulation(get_network_model(template))
    # Nothing to force where no branch flow is built, and AreaPTDF resolves interfaces over
    # AreaInterchange components alone, ignoring the lines that cross them.
    branches_modeled(network_formulation) || return forced
    network_formulation <: AreaPTDFNetworkModel && return forced
    services_mapping = PSY.get_contributing_device_mapping(sys)
    isempty(services_mapping) && return forced
    for service_model in values(service_models)
        for service in get_available_components(service_model, sys)
            service_name = PSY.get_name(service)
            key = (type = typeof(service), name = service_name)
            haskey(services_mapping, key) || continue
            for device in services_mapping[key].contributing_devices
                _record_service_branch!(forced, device, service_name)
            end
        end
    end
    return forced
end

"""
A branch filter widened with the branches a service model requires. Named rather than anonymous
so that re-validating a template unwraps the previous widening instead of nesting another layer.
"""
struct WidenedBranchFilter{F} <: Function
    original::F
    names::Set{String}
end

function (f::WidenedBranchFilter)(x)
    return (PSY.get_name(x) ∈ f.names)::Bool || (f.original(x))::Bool
end

_unwiden_branch_filter(f) = f
_unwiden_branch_filter(f::WidenedBranchFilter) = f.original

"""
Widen each branch model's filter so it also admits the branches its services require.

Only a model that already carries a filter is rewritten. A model with no filter admits every
available branch already, and installing a filter on it would flip `model_has_branch_filters`
and force the network catalog to rebuild, both without changing which branches are modeled.

Idempotent and unconditional: every filtered branch model is first unwrapped back to the user's
own predicate, then re-widened from the current `forced` set only if that type still has a
requirement. This is what keeps a rebuild from leaving a stale widening in place after the
template or system data changes between `build!` passes (a service model removed from the
template, or every interface branch made unavailable) — the old early-return-on-empty and
continue-on-no-entry left the previous pass's `WidenedBranchFilter` installed in both cases.
"""
function _widen_branch_filters!(
    branch_models::IOM.BranchModelContainer,
    forced::Dict{DataType, ServiceBranchRequirement},
)
    for branch_model in values(branch_models)
        original_filter = get_attribute(branch_model, "filter_function")
        original_filter === nothing && continue
        unwidened = _unwiden_branch_filter(original_filter)
        entry = get(forced, get_component_type(branch_model), nothing)
        if entry === nothing
            get_attributes(branch_model)["filter_function"] = unwidened
        else
            get_attributes(branch_model)["filter_function"] =
                WidenedBranchFilter(unwidened, entry.branch_names)
        end
    end
    return
end

"""
Reject a template whose service models depend on a branch type it does not model.

A filter can be widened to admit a branch, but a missing branch model cannot be conjured: there
is no formulation with which to build the branch's flow, so the service's flow expression would
be short by that branch's contribution with nothing to signal it.
"""
function _check_service_branch_models(
    template::PowerOperationsProblemTemplate,
    forced::Dict{DataType, ServiceBranchRequirement},
)
    isempty(forced) && return
    modeled_branch_types = Set{DataType}(
        get_component_type(m) for m in values(get_branch_models(template))
    )
    for (branch_type, entry) in forced
        branch_type ∈ modeled_branch_types && continue
        branch_list = join(sort!(collect(entry.branch_names)), ", ")
        service_list = join(sort!(collect(entry.service_names)), ", ")
        throw(
            IS.ConflictingInputsError(
                "Branches of type $(branch_type) contribute to the service(s) $(service_list) \
                but the template has no branch model for that type: $(branch_list). Their flow \
                would be omitted from the service's flow expression. Add a branch model for \
                $(branch_type), remove the service model from the template, or detach the \
                branch(es) from the service in the system data.",
            ),
        )
    end
    return
end

function validate_template_impl!(model::IOM.AbstractOptimizationModel)
    template = get_template(model)
    settings = get_settings(model)
    if isempty(template)
        error("Template can't be empty for models $(IOM.get_problem_type(model))")
    end
    system = get_system(model)
    modeled_types = IOM.get_component_types(template)
    system_component_types = PSY.get_existing_component_types(system)
    network_model = get_network_model(template)
    valid_device_types = union(modeled_types, _TEMPLATE_VALIDATION_EXCLUSIONS)
    unmodeled_branch_types = DataType[]

    for m in setdiff(system_component_types, valid_device_types)
        @warn "The template doesn't include models for components of type $(m), consider changing the template" _group =
            IOM.LOG_GROUP_MODELS_VALIDATION
        if m <: PSY.ACTransmission
            push!(unmodeled_branch_types, m)
        end
    end

    device_keys_to_delete = Symbol[]
    network_formulation = get_network_formulation(network_model)
    for (k, device_model) in template.devices
        make_device_cache!(device_model, system, get_check_components(settings))
        if isempty(get_device_cache(device_model))
            @info "The system data doesn't include devices of type $(k), consider changing the models in the template" _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
            push!(device_keys_to_delete, k)
        elseif models_reactive_power(get_formulation(device_model)) &&
               !network_has_reactive_power(network_formulation)
            @info "Device model $(k) models reactive power but network model $(network_formulation) has no reactive power; dropping it from the template" _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
            push!(device_keys_to_delete, k)
        elseif !_formulation_supports_network(get_formulation(device_model), network_model)
            throw(
                IS.ConflictingInputsError(
                    "Device model $(k) with formulation $(get_formulation(device_model)) has no construct path for network model $(network_formulation). Use a network model this formulation supports, change the formulation, or remove the device from the template.",
                ),
            )
        end
    end
    for k in device_keys_to_delete
        delete!(template.devices, k)
    end

    # Branches carrying a modeled service's flow must be modeled whether or not they pass a
    # branch filter, so widen the filters before the device caches are built from them.
    forced_service_branches = _collect_service_branch_names(template, system)
    _widen_branch_filters!(template.branches, forced_service_branches)

    model_has_branch_filters = false
    branch_keys_to_delete = Symbol[]
    validate_branches =
        get_check_components(settings) &&
        branches_modeled(get_network_formulation(network_model))
    for (k, device_model) in template.branches
        make_device_cache!(device_model, system, validate_branches)
        if isempty(get_device_cache(device_model))
            @info "The system data doesn't include Branches of type $(k), consider changing the models in the template" _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
            push!(branch_keys_to_delete, k)
        elseif models_reactive_power(get_formulation(device_model)) &&
               !network_has_reactive_power(network_formulation)
            @info "Branch model $(k) models reactive power but network model $(network_formulation) has no reactive power; dropping it from the template" _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
            push!(branch_keys_to_delete, k)
            push!(unmodeled_branch_types, get_component_type(device_model))
        elseif !_formulation_supports_network(get_formulation(device_model), network_model)
            throw(
                IS.ConflictingInputsError(
                    "Branch model $(k) with formulation $(get_formulation(device_model)) has no construct path for network model $(network_formulation). Use a network model this formulation supports, change the formulation, or remove the branch from the template.",
                ),
            )
        else
            _validate_branch_slack_request(k, device_model, network_formulation)
            push!(network_model.modeled_branch_types, get_component_type(device_model))
        end
        if get_attribute(device_model, "filter_function") !== nothing
            model_has_branch_filters = true
        end
    end
    for k in branch_keys_to_delete
        delete!(template.branches, k)
    end
    # After the deletions: a branch model dropped here is as absent as one never added.
    _check_service_branch_models(template, forced_service_branches)
    _check_security_constrained_three_winding_transformer(template.branches)
    _check_security_constrained_network(template.branches, network_model)
    _check_security_constrained_phase_control(template.branches, network_model)
    _check_voltage_regulation_conflicts!(template, system, network_model)
    _check_branch_rating_time_series_formulation!(template.branches, system)
    validate_network_model(network_model, unmodeled_branch_types, model_has_branch_filters)
    _build_device_model_outages!(template, system)
    # Must follow `_build_device_model_outages!`: that call is what fills the per-type
    # monitored-name maps this check reads.
    _check_monitored_components(template.branches, system)
    return
end

#################################################################################
# Security-constrained branch validation and outage population
#################################################################################

function _any_component_has_branch_rating_ts(
    ::Type{P},
    device_model::DeviceModel,
    sys::PSY.System,
) where {P <: AbstractBranchRatingTimeSeriesParameter}
    haskey(get_time_series_names(device_model), P) || return false
    ts_name = get_time_series_names(device_model)[P]
    # Only the modeled forecast matters: operations consume a
    # Deterministic-family forecast, never a bare SingleTimeSeries. Use the
    # same `ts_type` the reduction path resolves so both pathways agree on
    # what "has the branch rating time series" means.
    ts_type = IOM.get_deterministic_time_series_type(sys)
    return any(
        c -> PSY.has_time_series(c, ts_type, ts_name),
        get_device_cache(device_model),
    )
end

# Both `BranchRatingTimeSeriesParameter` and
# `PostContingencyBranchRatingTimeSeriesParameter` are only honored by the
# `StaticBranch` (pre-contingency PTDF / DCP / ACP) and
# `AbstractSecurityConstrainedStaticBranch` constructors. Any other
# formulation that carries either series passes validation but never builds a
# usable parameter container, so the series would be silently ignored —
# reject it up front instead. `StaticBranchUnbounded` enforces no flow limits
# at all, so the series is simply unused there: warn rather than error.
function _check_branch_rating_time_series_formulation!(
    branch_models::IOM.BranchModelContainer,
    sys::PSY.System,
)
    for (_, device_model) in branch_models
        D = get_component_type(device_model)
        B = get_formulation(device_model)
        for P in (
            BranchRatingTimeSeriesParameter,
            PostContingencyBranchRatingTimeSeriesParameter,
        )
            _any_component_has_branch_rating_ts(P, device_model, sys) || continue
            if B <: StaticBranch || B <: AbstractSecurityConstrainedStaticBranch
                continue
            elseif B <: StaticBranchUnbounded
                @warn "$(P) is attached to $(D) components but $(B) does not \
                       enforce flow limits; the branch rating time series will \
                       be ignored for these branches." _group =
                    IOM.LOG_GROUP_MODELS_VALIDATION
                continue
            else
                throw(
                    IS.ConflictingInputsError(
                        "$(P) is only supported with the StaticBranch or \
                        AbstractSecurityConstrainedStaticBranch formulations, \
                        but branch type $(D) was configured with $(B). Remove \
                        the branch rating time series from the components or \
                        change the formulation.",
                    ),
                )
            end
        end
    end
    return
end

function _check_security_constrained_three_winding_transformer(
    branch_model::DeviceModel{
        PSY.ThreeWindingTransformer,
        <:AbstractSecurityConstrainedStaticBranch,
    },
)
    throw(
        IS.ConflictingInputsError(
            "Security-constrained branch formulations are not implemented \
            yet for ThreeWindingTransformers.",
        ),
    )
end

_check_security_constrained_three_winding_transformer(::DeviceModel) = nothing

function _check_security_constrained_three_winding_transformer(
    branch_models::IOM.BranchModelContainer,
)
    for device_model in values(branch_models)
        _check_security_constrained_three_winding_transformer(device_model)
    end
    return
end

# Whether an `AbstractSecurityConstrainedStaticBranch` has a `construct_device!`
# path for this network model. The MODF post-contingency flow is a lossless
# linear DC construct, so only PTDF/AreaPTDF/DCP build full post-contingency
# limits; NFA/CopperPlate/AreaBalance are intentional no-ops. The fallback
# returns `false` so the AC and lossy networks fail fast at validation instead
# of hitting a `MethodError` during build.
_sc_branch_network_supported(::NetworkModel{<:AbstractPTDFNetworkModel}) = true
_sc_branch_network_supported(::NetworkModel{DCPNetworkModel}) = true
_sc_branch_network_supported(::NetworkModel{NFANetworkModel}) = true
_sc_branch_network_supported(::NetworkModel{CopperPlateNetworkModel}) = true
_sc_branch_network_supported(::NetworkModel{AreaBalanceNetworkModel}) = true
_sc_branch_network_supported(::NetworkModel) = false

"""
Trait axis describing which network models a device formulation has a `construct_device!`
path for. The set of network models a formulation builds under cuts across the formulation
type hierarchy, so it cannot be expressed as a supertype. Declare one
[`network_support`](@ref) method per formulation; downstream packages extend the gate the
same way, which a `Union` alias could not allow.
"""
abstract type NetworkSupport end
"Formulation builds under every network model. Default."
struct AllNetworks <: NetworkSupport end
"""
Formulation needs a full AC network; the linear-programming AC cold-start approximation
(LPACC, [`LPACCNetworkModel`](@ref)) linearizes the reactive layer and cannot build it.
"""
struct AllNetworksExceptLPACC <: NetworkSupport end
"""
Formulation whose defining feature is its reactive-power behavior; only the networks
with a reactive-power balance (ACP/ACR/IVR/LPACC) build it. Building it on an
active-power-only network would silently discard that feature, so those networks are
rejected instead of dropped.
"""
struct ReactiveNetworksOnly <: NetworkSupport end

"""
    network_support(::Type{<:AbstractDeviceFormulation}) -> NetworkSupport

Which network models a device formulation can be constructed under. Defaults to
[`AllNetworks`](@ref); a formulation whose `construct_device!` is bound to a narrower
network type must declare it here or it fails deep inside `build!` instead of at template
validation.
"""
network_support(::Type{<:AbstractDeviceFormulation}) = AllNetworks()

# LPACC is reactive-capable at the network level (`network_has_reactive_power` is true), so
# the coarse reactive-power gate admits these devices even though their control layer has no
# LPACC construct path.
network_support(::Type{ShuntSusceptanceDispatch}) = AllNetworksExceptLPACC()

# An LCC's reactive consumption is the reason to model it as HVDCTwoTerminalLCC; on a
# network without a reactive balance use HVDCTwoTerminalDispatch/Lossless instead.
network_support(::Type{HVDCTwoTerminalLCC}) = ReactiveNetworksOnly()

# Whether a device/branch formulation has a `construct_device!` path for this network model.
# Without this check an unsupported pair fails later with a generic "construct_device! not
# implemented" error that `build!` swallows into a FAILED status.
function _formulation_supports_network(
    ::Type{F},
    network_model::NetworkModel,
) where {F <: AbstractDeviceFormulation}
    return _supports_network(network_support(F), network_model)
end

_supports_network(::AllNetworks, ::NetworkModel) = true

_supports_network(::AllNetworksExceptLPACC, ::NetworkModel) = true
_supports_network(::AllNetworksExceptLPACC, ::NetworkModel{LPACCNetworkModel}) = false

_supports_network(::ReactiveNetworksOnly, ::NetworkModel) = false
_supports_network(
    ::ReactiveNetworksOnly,
    ::NetworkModel{<:AbstractReactivePowerNetworkModel},
) = true

# Validation-time counterpart of the `supports_flow_slacks` gate (see
# core/branch_slack_specs.jl): a use_slacks request on a pair whose `slack_spec` declares
# no machinery is a hard conflict on branch-modeling networks. CopperPlate/AreaBalance
# build no branch containers at all, so the request is inert there — warn instead of
# erroring to keep templates reusable on aggregated networks.
function _validate_branch_slack_request(
    key::Symbol,
    device_model::IOM.DeviceModel,
    ::Type{N},
) where {N <: AbstractNetworkModel}
    get_use_slacks(device_model) || return
    F = get_formulation(device_model)
    supports_flow_slacks(F, N) && return
    if branches_modeled(N)
        throw(
            IS.ConflictingInputsError(
                "Branch model $(key) with formulation $(F) has use_slacks = true, but " *
                "$(N) builds no flow-definition equality, rating constraint row or " *
                "quadratic limit for this formulation, so there is nothing for the " *
                "slack to relax. Remove use_slacks, change the formulation, or use a " *
                "different network model.",
            ),
        )
    end
    @warn "use_slacks = true on branch model $(key) has no effect: $(N) does not model " *
          "individual branch flows." _group = IOM.LOG_GROUP_MODELS_VALIDATION
    return
end

# Construct-time backstop (NFA StaticBranchBounds ArgumentConstructStage), so mock/direct
# construct paths that bypass template validation stay protected.
function _check_flow_slack_support(
    device_model::IOM.DeviceModel,
    network_model::NetworkModel,
)
    get_use_slacks(device_model) || return
    F = get_formulation(device_model)
    N = get_network_formulation(network_model)
    supports_flow_slacks(F, N) && return
    throw(
        ArgumentError(
            "$(F) formulation and $(N) is not compatible with the use of slacks",
        ),
    )
end

# Circuits this model puts in ACTIVE_POWER_FLOW control, named as `_controlled_circuit_names`
# names them. Read off the device cache: the network reduction does not exist yet at
# validation time, so the `RepresentativeBranch` API is unavailable here.
function _phase_controlled_circuit_names(
    device_model::DeviceModel{<:_TRANSFORMERS, <:_CONTROL_FORMULATIONS},
    network_model::NetworkModel,
)
    names = String[]
    _control_enabled(device_model) || return names
    _supports_phase_control(network_model) || return names
    for transformer in get_device_cache(device_model)
        circuits = PSY.get_circuits(transformer)
        for (i, circuit) in enumerate(circuits)
            _control_objective(circuit, device_model) in _PHASE_CONTROLS || continue
            if length(circuits) == 1
                push!(names, PSY.get_name(transformer))
            else
                push!(names, "$(PSY.get_name(transformer))_winding_$(i)")
            end
        end
    end
    return names
end

_phase_controlled_circuit_names(::DeviceModel, ::NetworkModel) = String[]

_is_security_constrained(
    ::DeviceModel{<:PSY.ACTransmission, <:AbstractSecurityConstrainedStaticBranch},
) = true
_is_security_constrained(::DeviceModel) = false

# `_build_post_contingency_flow_expressions_for_outage` builds every post-contingency flow
# from the FIXED `_dc_shift_injection`, never from `PhaseShifterAngle`. A variable angle
# would therefore move only the base case, leaving the N-1 rows silently wrong, so reject
# the pair instead of building it.
function _check_security_constrained_phase_control(
    branch_models::IOM.BranchModelContainer,
    network_model::NetworkModel,
)
    sc_types = [
        get_component_type(m) for m in values(branch_models) if
        _is_security_constrained(m)
    ]
    isempty(sc_types) && return
    controlled = reduce(
        vcat,
        (_phase_controlled_circuit_names(m, network_model) for m in values(branch_models));
        init = String[],
    )
    isempty(controlled) && return
    throw(
        IS.ConflictingInputsError(
            "Phase-controlled transformer circuit(s) $(join(controlled, ", ")) cannot be \
             combined with the security-constrained branch model(s) for \
             $(join(sc_types, ", ")): post-contingency MODF flows are built from the fixed \
             phase shift, so a variable phase-shifter angle would make them wrong. Disable \
             the circuit control or drop the security-constrained formulation.",
        ),
    )
end

function _check_security_constrained_network(
    branch_model::DeviceModel{<:PSY.ACTransmission, B},
    network_model::NetworkModel,
) where {B <: AbstractSecurityConstrainedStaticBranch}
    _sc_branch_network_supported(network_model) || throw(
        IS.ConflictingInputsError(
            "$(B) is not supported with network model \
            $(get_network_formulation(network_model)). Supported network \
            models are PTDF, AreaPTDF and DCP. Security-constrained \
            branches are not available on AC or lossy network models \
            (ACP/ACR/IVR/LPACC/DCPLL) because the MODF post-contingency \
            formulation is a lossless linear DC construct. NFA, \
            CopperPlate and AreaBalance are inert for \
            security-constrained branches.",
        ),
    )
    return
end

_check_security_constrained_network(::DeviceModel, ::NetworkModel) = nothing

function _check_security_constrained_network(
    branch_models::IOM.BranchModelContainer,
    network_model::NetworkModel,
)
    for device_model in values(branch_models)
        _check_security_constrained_network(device_model, network_model)
    end
    return
end

function _check_monitored_components(
    branch_model::DeviceModel{
        <:PSY.ACTransmission,
        <:AbstractSecurityConstrainedStaticBranch,
    },
    sys::PSY.System,
)
    for (uuid, per_type) in get_outages(branch_model)
        for (T, names) in per_type
            for name in names
                !PSY.has_component(sys, T, name) && error(
                    "Monitored component \"$name\" (type $T) for outage $uuid is " *
                    "absent from both the network-reduction name-to-arc map and the " *
                    "component-to-reduction map. Verify the component exists in the " *
                    "system and is modeled with a security-constrained branch formulation.",
                )
            end
        end
    end
    return
end

_check_monitored_components(::DeviceModel, ::PSY.System) = nothing

function _check_monitored_components(
    branch_models::IOM.BranchModelContainer,
    sys::PSY.System,
)
    for branch_model in values(branch_models)
        _check_monitored_components(branch_model, sys)
    end
    return
end

# Under ACP a VOLTAGE-control device pins the shared network VoltageMagnitude at its
# regulated bus via JuMP.fix(force=true); two devices on one bus silently override
# each other (last write wins). Detect that at validation. LPACC has the same shape
# (the shared VoltageDeviation is pinned directly). Under ACR/IVR each device owns a
# (component, tag) RegulatedVoltageMagnitude aux variable, so the same clash is
# solver-infeasibility, not a silent override — those networks skip the check.
_voltage_regulation_can_collide(::NetworkModel) = false
_voltage_regulation_can_collide(::NetworkModel{ACPNetworkModel}) = true
_voltage_regulation_can_collide(::NetworkModel{LPACCNetworkModel}) = true

# (device name, regulated ACBus) for the components this model puts in a voltage-
# control mode. Default: nothing regulates voltage (DeviceModelForBranches is a
# DeviceModel alias, so this one default covers both device and branch models). One
# specialization per regulating formulation, reusing each family's regulated-bus
# resolver.
_voltage_regulated_buses(::IOM.DeviceModel, ::PSY.System, ::NetworkModel) =
    Tuple{String, PSY.ACBus}[]

# Regulated buses from VOLTAGE-controlled transformers on AC networks
function _voltage_regulated_buses(
    device_model::DeviceModel{<:_TRANSFORMERS, F},
    sys::PSY.System,
    network_model::NetworkModel,
) where {F <: AbstractBranchFormulation}
    pairs = Tuple{String, PSY.ACBus}[]
    _control_enabled(device_model) || return pairs
    for d in get_available_components(device_model, sys)
        for (i, circuit) in enumerate(PSY.get_circuits(d))
            PSY.get_control_objective(circuit) === _VOLTAGE_CONTROL || continue
            _supports_tap_control(network_model) || continue
            bus = PSY.get_bus(sys, PSY.get_regulated_bus_number(circuit))
            name = "$(PSY.get_name(d))_winding_$i"
            if isnothing(bus)
                error(
                    "The regulated bus number for circuit $name is not a valid bus number: it must correspond to a valid bus number in the network.",
                )
            end
            push!(pairs, (name, bus))
        end
    end
    return pairs
end

function _voltage_regulated_buses(
    device_model::IOM.DeviceModel{T, ShuntSusceptanceDispatch},
    sys::PSY.System,
    ::NetworkModel,
) where {T <: PSY.FACTSControlDevice}
    pairs = Tuple{String, PSY.ACBus}[]
    for d in get_available_components(device_model, sys)
        if PSY.get_control_mode(d) == PSY.FACTSOperationModes.NML
            push!(pairs, (PSY.get_name(d), PSY.get_bus(d)))
        end
    end
    return pairs
end

function _voltage_regulated_buses(
    device_model::IOM.DeviceModel{T, VoltageControlConverter},
    sys::PSY.System,
    ::NetworkModel,
) where {T <: PSY.InterconnectingConverter}
    pairs = Tuple{String, PSY.ACBus}[]
    for d in get_available_components(device_model, sys)
        if PSY.get_ac_control(d) == PSY.VSCACControlModes.AC_VOLTAGE
            push!(pairs, (PSY.get_name(d), PSY.get_bus(d)))
        end
    end
    return pairs
end

function _voltage_regulated_buses(
    device_model::IOM.DeviceModelForBranches{T, VoltageControlVSC},
    sys::PSY.System,
    ::NetworkModel,
) where {T <: PSY.TwoTerminalVSCLine}
    pairs = Tuple{String, PSY.ACBus}[]
    for d in get_available_components(device_model, sys)
        arc = PSY.get_arc(d)
        if PSY.get_ac_control_from(d) == PSY.VSCACControlModes.AC_VOLTAGE
            push!(pairs, ("$(PSY.get_name(d))_from", PSY.get_from(arc)))
        end
        if PSY.get_ac_control_to(d) == PSY.VSCACControlModes.AC_VOLTAGE
            push!(pairs, ("$(PSY.get_name(d))_to", PSY.get_to(arc)))
        end
    end
    return pairs
end

# Reject templates where two voltage regulators target the same bus under ACP.
function _check_voltage_regulation_conflicts!(
    template::IOM.AbstractProblemTemplate,
    sys::PSY.System,
    network_model::NetworkModel,
)
    _voltage_regulation_can_collide(network_model) || return
    bus_regulators = Dict{Int, Vector{String}}()
    for device_model in
        Iterators.flatten((values(template.devices), values(template.branches)))
        for (dev_name, bus) in _voltage_regulated_buses(device_model, sys, network_model)
            push!(get!(Vector{String}, bus_regulators, PSY.get_number(bus)), dev_name)
        end
    end
    for (bus_no, regulators) in bus_regulators
        if length(regulators) > 1
            throw(
                IS.ConflictingInputsError(
                    "Bus $(bus_no) is voltage-regulated by multiple devices ($(regulators)) under a network with a shared per-bus voltage variable (ACP/LPACC); their setpoints would silently override each other (JuMP.fix). Keep at most one voltage regulator per bus.",
                ),
            )
        end
    end
    return
end

"""
Populate `device_model.outages` for every security-constrained (SC) branch
device model in the template, in a single pass over the system's outage
supplemental attributes. `DeviceModel{D, SC}` claims an outage iff `D` is among
the types of the outaged (attached) components. The inner dict carries the
per-modeled-type breakdown of monitored component names.

Selection semantics:
- If `m.outages` is non-empty when this runs, the user explicitly listed UUIDs
  via the constructor kwarg. Restrict to those UUIDs only; warn for any
  user-listed UUID that produced no `D`-type entry.
- If `m.outages` is empty, auto-discover. Honor `"include_planned_outages"` on
  `m`'s attributes (default `false`) — `PlannedOutage`s are skipped on the
  auto-discover path unless the attribute is `true`.

The monitored set is exactly what each outage lists in its
`monitored_components`; an outage with empty `monitored_components` is treated
as "monitor nothing" (a warning is emitted). A monitored component whose type
is not a modeled `PSY.ACTransmission` branch type is reported once per type and
skipped.
"""
function _build_device_model_outages!(
    template::IOM.AbstractProblemTemplate,
    sys::PSY.System,
)
    sc_models = _sc_branch_models(template)
    isempty(sc_models) && return

    modeled_types = Set{DataType}(get_component_types(template))
    selection = _take_outage_selection!(sc_models)
    uncovered_types = Dict{DataType, Set{Int}}()

    for outage in PSY.get_supplemental_attributes(PSY.Outage, sys)
        outage_id = IS.get_id(outage)
        if isempty(PSY.get_monitored_components(outage))
            @warn "Outage $(outage_id) ($(typeof(outage))) has empty \
                   monitored_components; no post-contingency variables or \
                   constraints will be created for this outage." _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
            continue
        end

        per_type, uncovered =
            _monitored_components_by_modeled_type(outage, outage_id, sys, modeled_types)
        for comp_type in uncovered
            push!(get!(Set{Int}, uncovered_types, comp_type), outage_id)
        end
        isempty(per_type) && continue

        attached_types = _attached_component_types(outage, sys)
        covered = _assign_outage_to_sc_models!(
            sc_models,
            selection,
            outage,
            outage_id,
            per_type,
            attached_types,
        )
        if !covered
            @warn "Outage $(outage_id) is attached to component(s) of \
                   type $(collect(attached_types)), but no DeviceModel with \
                   an AbstractSecurityConstrainedStaticBranch formulation \
                   covers those types; it will not contribute any \
                   post-contingency constraints." _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
        end
    end

    _warn_uncovered_monitored_types(uncovered_types)
    _warn_unmatched_user_outages(sc_models, selection)
    return
end

# SC branch device models in the template.
function _sc_branch_models(template::IOM.AbstractProblemTemplate)
    return IOM.DeviceModelForBranches[
        m for m in values(get_branch_models(template)) if
        get_formulation(m) <: AbstractSecurityConstrainedStaticBranch
    ]
end

# Per SC-model component type, the user's explicit outage-UUID allow-list from
# the constructor kwarg: a non-empty set restricts auto-discovery to those
# UUIDs; an empty set means auto-discover all. Clears `m.outages` so the main
# pass can repopulate it; the cleared UUIDs survive in the returned map.
function _take_outage_selection!(sc_models::Vector{<:IOM.DeviceModelForBranches})
    selection = Dict{Symbol, Set{Int}}()
    for m in sc_models
        selection[nameof(get_component_type(m))] = Set{Int}(keys(get_outages(m)))
        empty!(get_outages(m))
    end
    return selection
end

# Monitored-component names grouped by their concrete (modeled) type. Returns
# `(per_type, uncovered)` where `uncovered` is the set of monitored component
# types the template does not model.
function _monitored_components_by_modeled_type(
    outage::PSY.Outage,
    outage_id::Int,
    sys::PSY.System,
    modeled_types::Set{DataType},
)
    per_type = Dict{DataType, Set{String}}()
    uncovered = Set{DataType}()
    for uuid in PSY.get_monitored_components(outage)
        component = IS.get_component(sys, uuid)
        if isnothing(component)
            @warn "Outage $(outage_id) references monitored component \
                   UUID $(uuid) that is not present in the system; \
                   skipping." _group = IOM.LOG_GROUP_MODELS_VALIDATION
            continue
        end
        comp_type = typeof(component)
        if comp_type <: PSY.ACTransmission && comp_type in modeled_types
            push!(get!(Set{String}, per_type, comp_type), PSY.get_name(component))
        else
            push!(uncovered, comp_type)
        end
    end
    return per_type, uncovered
end

function _attached_component_types(outage::PSY.Outage, sys::PSY.System)
    return Set{DataType}(
        typeof(c) for c in PSY.get_associated_components(sys, outage)
    )
end

# Whether SC model `m` claims `outage`. `sel` is `m`'s component-type slice of
# the user's explicit outage allow-list: non-empty restricts to those UUIDs;
# empty means auto-discover (claim all, skipping `PlannedOutage`s unless the
# model opts in via the `"include_planned_outages"` attribute).
function _sc_model_claims_outage(
    m::IOM.DeviceModelForBranches,
    outage::PSY.Outage,
    outage_id::Int,
    sel::Set{Int},
)
    isempty(sel) || return outage_id in sel
    if outage isa PSY.PlannedOutage
        return get_attribute(m, "include_planned_outages") === true
    end
    return true
end

# Assign `per_type` to every SC model whose component type is among the outage's
# attached types and that claims the outage. Returns whether any SC model
# covered an attached type.
function _assign_outage_to_sc_models!(
    sc_models::Vector{<:IOM.DeviceModelForBranches},
    selection::Dict{Symbol, Set{Int}},
    outage::PSY.Outage,
    outage_id::Int,
    per_type::Dict{DataType, Set{String}},
    attached_types::Set{DataType},
)
    covered = false
    for m in sc_models
        D = get_component_type(m)
        D in attached_types || continue
        covered = true
        if _sc_model_claims_outage(m, outage, outage_id, selection[nameof(D)])
            get_outages(m)[outage_id] = per_type
        end
    end
    return covered
end

function _warn_uncovered_monitored_types(
    uncovered_types::Dict{DataType, Set{Int}},
)
    for (comp_type, offending) in uncovered_types
        @warn "Monitored components of type $(comp_type) appear in outages \
               $(collect(offending)) but $(comp_type) is not a modeled \
               ACTransmission branch type; their post-contingency variables \
               will be skipped." _group = IOM.LOG_GROUP_MODELS_VALIDATION
    end
    return
end

function _warn_unmatched_user_outages(
    sc_models::Vector{<:IOM.DeviceModelForBranches},
    selection::Dict{Symbol, Set{Int}},
)
    for m in sc_models
        D = get_component_type(m)
        sel = selection[nameof(D)]
        isempty(sel) && continue
        for uuid in sel
            haskey(get_outages(m), uuid) && continue
            @warn "Outage $(uuid) listed on DeviceModel{$D, \
                   $(get_formulation(m))} is not attached to a component \
                   of type $D in the system — it will not contribute any \
                   post-contingency constraints." _group =
                IOM.LOG_GROUP_MODELS_VALIDATION
        end
    end
    return
end
