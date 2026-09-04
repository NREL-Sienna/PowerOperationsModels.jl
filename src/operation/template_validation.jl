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
    _build_device_model_events!(template, system)
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

_is_security_constrained(
    ::DeviceModel{<:PSY.ACTransmission, <:AbstractSecurityConstrainedStaticBranch},
) = true
_is_security_constrained(::DeviceModel) = false

_has_unsupported_phase(t::_TRANSFORMERS, m::DeviceModel{<:_TRANSFORMERS}) = any(
    _control_objective(c, m) in _PHASE_CONTROLS || !iszero(PSY.get_α(c)) for
    c in PSY.get_circuits(t)
)
_has_unsupported_phase(_, ::DeviceModel) = false
# A transformer carrying an outage need not have a `DeviceModel` in the template. Its
# control objective is then inert, but a nonzero fixed shift still corrupts the MODF
# columns of every monitored arc, so the static angle alone is disqualifying.
_has_unsupported_phase(t::_TRANSFORMERS, ::Nothing) =
    any(!iszero(PSY.get_α(c)) for c in PSY.get_circuits(t))
_has_unsupported_phase(_, ::Nothing) = false

_has_unsupported_phase(m::DeviceModel{<:_TRANSFORMERS}) =
    any(_has_unsupported_phase(t, m) for t in get_device_cache(m))
_has_unsupported_phase(::DeviceModel) = false

function _check_security_constrained_phase_control(
    branch_models::IOM.BranchModelContainer,
    network_model::NetworkModel{<:Union{DCPNetworkModel, AbstractDCPLLNetworkModel}},
)
    any(_is_security_constrained(m) for m in values(branch_models)) || return
    any(_has_unsupported_phase(m) for m in values(branch_models)) && throw(
        IS.ConflictingInputsError(
            "N-1 DCP/DCPLL networks do not support any transformers with phase-control or nonzero phase.",
        ),
    )
    return
end

_check_security_constrained_phase_control(::IOM.BranchModelContainer, ::NetworkModel) =
    nothing

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

function _assert_transformer_outages(
    transformer::T,
    branch_models::IOM.BranchModelContainer,
) where {T <: _TRANSFORMERS}
    model = get(branch_models, nameof(T), nothing)
    _has_unsupported_phase(transformer, model) && throw(
        IS.ConflictingInputsError(
            "Phase-shifting transformers and transformers with non-zero angle may not be outages.",
        ),
    )
    return
end

_assert_transformer_outages(::PSY.Device, ::IOM.BranchModelContainer) =
    nothing

# Monitored components exist; no controlled transformer outages
function _check_monitored_components(
    branch_models::IOM.BranchModelContainer,
    sys::PSY.System,
)
    for branch_model in values(branch_models)
        IOM.supports_outages(IOM.get_formulation(branch_model)) || continue
        for outage_id in keys(get_outages(branch_model))
            outage = PSY.get_supplemental_attribute(sys, outage_id)
            for uuid in PSY.get_monitored_components(outage)
                isnothing(IS.get_component(sys, uuid)) && throw(
                    IS.ConflictingInputsError(
                        "Monitored component with UUID $uuid on outage $outage_id is not found in the system.",
                    ),
                )
            end
            for component in PSY.get_associated_components(sys, outage)
                _assert_transformer_outages(component, branch_models)
            end
        end
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

    modeled_types = Set{Type}(get_component_types(template))
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
    modeled_types::Set{Type},
)
    per_type = Dict{DataType, Set{String}}()
    uncovered = Set{DataType}()
    for uuid in PSY.get_monitored_components(outage)
        component = IS.get_component(sys, uuid)
        isnothing(component) && throw(
            IS.ConflictingInputsError(
                "Outage $(outage_id) references monitored component UUID $(uuid) that is \
                 not present in the system.",
            ),
        )
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

#################################################################################
# Outage-event discovery and validation (time-series outage events; distinct
# from the security-constrained `_build_device_model_outages!` above)
#################################################################################

"""
For each event model attached to the template: validate its time-series mapping,
populate `attribute_device_map` (attribute id → concrete device type → device names)
from the system's supplemental attributes, and distribute the event model to every
`DeviceModel` in the template whose device type carries the attribute and supports
events.
"""
function _build_device_model_events!(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    for event_model in get_event_models(template)
        event_type = get_event_type(event_model)
        attributes = PSY.get_supplemental_attributes(event_type, sys)
        if isempty(attributes)
            error(
                "There are no supplemental attributes of type $event_type in the system. \
                 Add the outage data to the system or remove the event model from the \
                 template.",
            )
        end
        for event in attributes
            _validate_event_timeseries_data(sys, event, event_model)
            event_id = IS.get_id(event)
            attribute_device_map = get_attribute_device_map(event_model)
            attribute_device_map[event_id] = Dict{DataType, Set{String}}()
            device_types_with_attribute = Set{DataType}()
            for device in PSY.get_associated_components(sys, event)
                dtype = typeof(device)
                if !supports_events(dtype)
                    @warn "Device $(PSY.get_name(device)) of type $dtype carries a \
                           $event_type attribute but the type does not support events; \
                           it will not be modeled." _group =
                        IOM.LOG_GROUP_MODELS_VALIDATION
                    continue
                end
                push!(device_types_with_attribute, dtype)
                name_set = get!(
                    attribute_device_map[event_id],
                    dtype,
                    Set{String}(),
                )
                push!(name_set, PSY.get_name(device))
            end
            for device_type in device_types_with_attribute
                device_model = get_model(template, device_type)
                if device_model === nothing
                    @warn "Devices of type $device_type carry a $event_type attribute \
                           but the template has no DeviceModel for that type; the event \
                           will not be modeled for them." _group =
                        IOM.LOG_GROUP_MODELS_VALIDATION
                    continue
                end
                key = EventKey(event_type, device_type)
                existing_events = IOM.get_events(device_model)
                if haskey(existing_events, key)
                    # The same event model can legitimately be discovered again for this
                    # device type (e.g. a second outage attribute of the same contingency
                    # type attached to another device of the same type); re-registering it
                    # is a no-op. A *different* event model targeting the same
                    # (contingency type, device type) pair can't both be honored — the
                    # device model has one slot per key — so that case must fail loudly
                    # instead of silently dropping the second registration.
                    existing_events[key] === event_model && continue
                    error(
                        "Two distinct event models of contingency type $event_type both \
                         target device type $device_type. Only one event model per \
                         (contingency type, device type) pair is supported. Merge the \
                         event models or remove one from the template.",
                    )
                elseif !isempty(existing_events)
                    # A second event model of a *different* contingency type also can't
                    # coexist on one device model: event parameter containers are keyed
                    # by (parameter type, device type) only — the contingency type is
                    # not part of the key — so the two models' parameters would collide
                    # in the optimization container. Fail here with a clear message
                    # instead of deep in container construction.
                    other_types = join(
                        unique(get_event_type(m) for m in values(existing_events)),
                        ", ",
                    )
                    error(
                        "Device type $device_type is already targeted by an event model \
                         of contingency type $other_types; a second event model of \
                         contingency type $event_type cannot be added because event \
                         parameters are keyed by device type only and would collide. \
                         Attach at most one event model per device type.",
                    )
                end
                IOM.set_event_model!(device_model, key, event_model)
            end
        end
    end
    return
end

function _validate_event_timeseries_data(
    sys::PSY.System,
    event::PSY.Contingency,
    event_model::EventModel,
)
    for (k, v) in event_model.timeseries_mapping
        if !isnothing(v)
            try
                PSY.get_time_series(IS.SingleTimeSeries, event, v)
            catch e
                # A missing series surfaces as ArgumentError; anything else is a real
                # failure that must not be masked as missing data.
                e isa ArgumentError || rethrow()
                device_names =
                    PSY.get_name.(PSY.get_associated_components(sys, event))
                error(
                    "Event $event belonging to devices $device_names is missing a \
                     time series with name $v",
                )
            end
        end
        if !haskey(get_empty_timeseries_mapping(typeof(event)), k)
            error(
                "Key $k passed as part of the event time series mapping does not \
                 correspond to a parameter.",
            )
        end
        if k == :outage_status && isnothing(v)
            error(
                "FixedForcedOutage requires a timeseries mapping for the \
                 :outage_status parameter",
            )
        end
    end
    return
end
