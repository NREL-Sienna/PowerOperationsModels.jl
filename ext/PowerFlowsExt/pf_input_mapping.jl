# Power flow in-the-loop: input mapping infrastructure.
# Ported from PowerSimulations.jl/src/network_models/power_flow_evaluation.jl
# (lines 1-383). Defines PF_INPUT_KEY_PRECEDENCES, _make_temp_component_map,
# _make_pf_input_map!, branch/bus aux-var helpers, and add_power_flow_data!.

# Defines the order of precedence for each type of information that could be sent to PowerFlows.jl
const PF_INPUT_KEY_PRECEDENCES = Dict(
    :active_power => [
        IOM.ActivePowerVariable,
        POM.PowerOutput,
        POM.ActivePowerTimeSeriesParameter,
    ],
    :reactive_power =>
        [POM.ReactivePowerVariable, POM.ReactivePowerTimeSeriesParameter],
    :voltage_angle_export => [POM.PowerFlowVoltageAngle, POM.VoltageAngle],
    :voltage_magnitude_export =>
        [POM.PowerFlowVoltageMagnitude, POM.VoltageMagnitude],
    :voltage_angle_opf => [POM.VoltageAngle],
    :voltage_magnitude_opf => [POM.VoltageMagnitude],
    :active_power_hvdc_pst_from_to =>
        [POM.FlowActivePowerFromToVariable, POM.FlowActivePowerVariable],
    :active_power_hvdc_pst_to_from =>
        [POM.FlowActivePowerToFromVariable, POM.FlowActivePowerVariable],
)

const RELEVANT_COMPONENTS_SELECTOR =
    PSY.make_selector(Union{PSY.StaticInjection, PSY.Bus, PSY.Branch})

function _add_aux_variables!(
    container::OptimizationContainer,
    component_map::Dict{Type{<:AuxVariableType}, <:Set{<:Tuple{DataType, Any}}},
)
    for (var_type, components) in pairs(component_map)
        component_types = unique(first.(components))
        for component_type in component_types
            component_names = [v for (k, v) in components if k <: component_type]
            sort!(component_names)
            add_aux_variable_container!(
                container,
                var_type,
                component_type,
                component_names,
                get_time_steps(container),
            )
        end
    end
end

# Trait that determines which types of information are needed for each type of power flow
pf_input_keys(::PFS.ABAPowerFlowData) =
    [:active_power]
pf_input_keys(::PFS.PTDFPowerFlowData) =
    [:active_power]
pf_input_keys(::PFS.vPTDFPowerFlowData) =
    [:active_power]
pf_input_keys(::PFS.ACPowerFlowData) =
    [:active_power, :reactive_power, :voltage_angle_opf, :voltage_magnitude_opf]
pf_input_keys(::PFS.PSSEExporter) =
    [:active_power, :reactive_power, :voltage_angle_export, :voltage_magnitude_export]
# HVDC/PST flows feed every `PowerFlowData` solve. They route by component (see the resolver
# in pf_data_update.jl: HVDC → `bus_hvdc_net_power`, PST → `bus_active_power_injections`);
# `update_pf_data!` clears the HVDC channel before re-population.
pf_input_keys_hvdc_pst(::PFS.PowerFlowData) =
    [:active_power_hvdc_pst_from_to, :active_power_hvdc_pst_to_from]

_get_component_bus_for_map(component::PSY.Branch, ::Val{:from}) =
    PSY.get_from_bus(component)
_get_component_bus_for_map(component::PSY.Branch, ::Val{:to}) = PSY.get_to_bus(component)
_get_component_bus_for_map(component::PSY.Component, ::Nothing) = PSY.get_bus(component)

# Generalized function to create component maps by name to the index in the PowerFlowData bus arrays
function _make_temp_component_map(
    pf_data::PFS.PowerFlowData,
    sys::PSY.System,
    component_type::DataType,
    side::Union{Val{:from}, Val{:to}, Nothing},
)
    nrd = PFS.get_network_reduction_data(pf_data)
    temp_component_map = Dict{DataType, Dict{String, Int}}()
    components = PSY.get_available_components(component_type, sys)
    bus_lookup = PFS.get_bus_lookup(pf_data)
    for comp in components
        comp_type = typeof(comp)
        bus_dict = get!(temp_component_map, comp_type, Dict{String, Int}())
        bus_number = PSY.get_number(_get_component_bus_for_map(comp, side))
        bus_dict[PSY.get_name(comp)] = PNM.get_bus_index(bus_number, bus_lookup, nrd)
    end
    return temp_component_map
end

# Maps the StaticInjection component type by name to the
# index in the PowerFlow data arrays going from Bus number to bus index
function _make_temp_component_map(pf_data::PFS.PowerFlowData, sys::PSY.System)
    temp_component_map = _make_temp_component_map(
        pf_data,
        sys,
        PSY.StaticInjection,
        nothing,
    )
    # Add ACBus components for voltage magnitude and angle export
    bus_lookup = PFS.get_bus_lookup(pf_data)
    nrd = PFS.get_network_reduction_data(pf_data)
    temp_component_map[PSY.ACBus] =
        Dict(
            PSY.get_name(c) => PNM.get_bus_index(PSY.get_number(c), bus_lookup, nrd) for
            c in PSY.get_available_components(PSY.ACBus, sys)
        )
    return temp_component_map
end

_get_temp_component_map_lhs(comp::PSY.Component) = PSY.get_name(comp)
_get_temp_component_map_lhs(comp::PSY.Bus) = PSY.get_number(comp)

# Creates dicts of components by type
function _make_temp_component_map(::PFS.SystemPowerFlowContainer, sys::PSY.System)
    temp_component_map =
        Dict{DataType, Dict{Union{String, Int64}, String}}()
    relevant_components = PSY.get_available_components(RELEVANT_COMPONENTS_SELECTOR, sys)
    for comp_type in unique(typeof.(relevant_components))
        # NOTE we avoid using bus numbers here because PSY.get_bus(system, number) is O(n)
        temp_component_map[comp_type] =
            Dict(
                _get_temp_component_map_lhs(c) => PSY.get_name(c) for
                c in relevant_components if c isa comp_type
            )
    end
    return temp_component_map
end

function _make_pf_input_map!(
    pf_e_data::PowerFlowEvaluationData,
    container::OptimizationContainer,
    sys::PSY.System,
)
    pf_data = IOM.get_inner_data(pf_e_data)
    temp_component_map = _make_temp_component_map(pf_data, sys)
    map_type = valtype(temp_component_map)
    pf_e_data.input_key_map = Dict{Symbol, Dict{OptimizationContainerKey, map_type}}()

    available_keys = vcat(
        [
            collect(pairs(f(container))) for
            f in [get_variables, get_aux_variables, get_parameters]
        ]...,
    )
    for category in pf_input_keys(pf_data)
        pf_data_opt_container_map = Dict{OptimizationContainerKey, map_type}()
        @info "Adding input map to send $category to $(nameof(typeof(pf_data)))"
        @assert haskey(PF_INPUT_KEY_PRECEDENCES, category) "No source precedence defined for power-flow input category $category"
        precedence = PF_INPUT_KEY_PRECEDENCES[category]
        _add_category_to_map!(
            precedence,
            available_keys,
            temp_component_map,
            pf_data_opt_container_map,
        )
        pf_e_data.input_key_map[category] = pf_data_opt_container_map
    end
    _add_two_terminal_elements_map!(sys, pf_data, available_keys, pf_e_data.input_key_map)
    return
end

"""
    _add_category_to_map!(
        precedence::Vector{DataType},
        available_keys::Vector{Pair{OptimizationContainerKey, Any}},
        temp_component_map::Dict{DataType, <:Dict},
        pf_data_opt_container_map::Dict{OptimizationContainerKey, <:Dict},
    )

For every results variable from the optimization, finds the corresponding mapping between
the optimization variable and the `PowerFlowData` variable, following the `precedence` list
to break ties when multiple sources exist for the same component type.
"""
function _add_category_to_map!(
    precedence::Vector{DataType},
    available_keys::Vector{Pair{OptimizationContainerKey, Any}},
    temp_component_map::Dict{DataType, <:Dict},
    pf_data_opt_container_map::Dict{OptimizationContainerKey, <:Dict},
)
    added_injection_types = DataType[]
    for entry_type in precedence
        for (key, val) in available_keys
            if get_entry_type(key) === entry_type
                comp_type = get_component_type(key)
                if comp_type ∈ added_injection_types ||
                   comp_type ∉ keys(temp_component_map)
                    continue
                end
                push!(added_injection_types, comp_type)

                name_bus_ix_map = valtype(temp_component_map)()
                comp_names =
                    if (key isa ParameterKey)
                        get_component_names(get_attributes(val))
                    else
                        axes(val)[1]
                    end
                for comp_name in comp_names
                    name_bus_ix_map[comp_name] =
                        temp_component_map[comp_type][comp_name]
                end
                pf_data_opt_container_map[key] = name_bus_ix_map
            end
        end
    end
end

# the function to map HVDC power transfers as bus injections is not applicable to PSSEExporter:
_add_two_terminal_elements_map!(
    ::PSY.System,
    ::PFS.PSSEExporter,
    ::Vector{Pair{OptimizationContainerKey, Any}},
    ::Dict{Symbol, <:Dict{OptimizationContainerKey, <:Dict}},
) = nothing

"""
Adds mappings for two-terminal elements (HVDC components) that connect the power flow
results (from → to, to → from) to the mappings for all component types. Their results are
added as bus injections in the `PowerFlowData` as a simplified representation.
"""
function _add_two_terminal_elements_map!(
    sys::PSY.System,
    pf_data::PFS.PowerFlowData,
    available_keys::Vector{Pair{OptimizationContainerKey, Any}},
    input_key_map::Dict{Symbol, <:Dict{OptimizationContainerKey, <:Dict}},
)
    # psy6: PSY.PhaseShiftingTransformer dropped from this tuple pending transformer refactor
    for element_type in (PSY.TwoTerminalHVDC,)
        # A two-terminal element whose from and to resolve to one bus would collapse its
        # from_to/to_from injections onto the same row; guard against that here.
        for comp in PSY.get_available_components(element_type, sys)
            @assert PSY.get_number(PSY.get_from_bus(comp)) !=
                    PSY.get_number(PSY.get_to_bus(comp)) "Two-terminal $(PSY.get_name(comp)) maps from and to to the same bus"
        end
        for (category, side) in zip(
            [:active_power_hvdc_pst_from_to, :active_power_hvdc_pst_to_from],
            [Val(:from), Val(:to)],
        )
            category ∈ pf_input_keys_hvdc_pst(pf_data) || continue

            temp_component_map = _make_temp_component_map(
                pf_data,
                sys,
                element_type,
                side,
            )
            isempty(temp_component_map) && continue

            precedence = PF_INPUT_KEY_PRECEDENCES[category]
            pf_data_opt_container_map =
                Dict{OptimizationContainerKey, valtype(temp_component_map)}()
            _add_category_to_map!(
                precedence,
                available_keys,
                temp_component_map,
                pf_data_opt_container_map,
            )
            category_map = get!(
                input_key_map,
                category,
                Dict{OptimizationContainerKey, valtype(temp_component_map)}(),
            )
            merge!(category_map, pf_data_opt_container_map)
        end
    end
    return
end

# Trait that determines what branch aux vars we can get from each PowerFlowContainer
branch_aux_vars(::PFS.ACPowerFlowData) =
    [
        POM.PowerFlowBranchReactivePowerFromTo,
        POM.PowerFlowBranchReactivePowerToFrom,
        POM.PowerFlowBranchActivePowerFromTo,
        POM.PowerFlowBranchActivePowerToFrom,
        POM.PowerFlowBranchActivePowerLoss,
    ]
branch_aux_vars(::PFS.ABAPowerFlowData) =
    [POM.PowerFlowBranchActivePowerFromTo, POM.PowerFlowBranchActivePowerToFrom]
branch_aux_vars(::PFS.PTDFPowerFlowData) =
    [POM.PowerFlowBranchActivePowerFromTo, POM.PowerFlowBranchActivePowerToFrom]
branch_aux_vars(::PFS.vPTDFPowerFlowData) =
    [POM.PowerFlowBranchActivePowerFromTo, POM.PowerFlowBranchActivePowerToFrom]
branch_aux_vars(::PFS.PSSEExporter) = DataType[]

# Same for bus aux vars. Loss/voltage-stability factors are registered ONLY when their
# `get_calculate_*` flag is set — the same flag under which `_get_pf_result` returns a
# non-`nothing` matrix (`PFS.get_loss_factors` / `get_voltage_stability_factors` are `nothing`
# otherwise). Keep these two conditions in lockstep so the read-back never indexes a `nothing`.
function bus_aux_vars(data::PFS.ACPowerFlowData)
    vars = [POM.PowerFlowVoltageAngle, POM.PowerFlowVoltageMagnitude]
    if PFS.get_calculate_loss_factors(data)
        push!(vars, POM.PowerFlowLossFactors)
    end
    if PFS.get_calculate_voltage_stability_factors(data)
        push!(vars, POM.PowerFlowVoltageStabilityFactors)
    end
    return vars
end

bus_aux_vars(::PFS.ABAPowerFlowData) = [POM.PowerFlowVoltageAngle]
bus_aux_vars(::PFS.PTDFPowerFlowData) = DataType[]
bus_aux_vars(::PFS.vPTDFPowerFlowData) = DataType[]
bus_aux_vars(::PFS.PSSEExporter) = DataType[]

# TODO: Needs update for MultiTerminal HVDC
_get_branch_component_tuples(sys::PSY.System) = [
    (typeof(c), PSY.get_name(c)) for
    c in PSY.get_available_components(PSY.ACBranch, sys)
]

_get_bus_component_tuples(pfd::PFS.PowerFlowData) =
    tuple.(PSY.ACBus, keys(PFS.get_bus_lookup(pfd)))

_get_bus_component_tuples(pfd::PFS.SystemPowerFlowContainer) =
    [
        (typeof(c), PSY.get_number(c)) for
        c in PSY.get_available_components(PSY.ACBus, PFS.get_system(pfd))
    ]

function _with_time_steps(pf::T, n::Int) where {T <: PFS.PowerFlowEvaluationModel}
    fields = Dict(fn => getfield(pf, fn) for fn in fieldnames(T))
    fields[:time_steps] = n
    return T(; fields...)
end

_with_time_steps(pf::PFS.PSSEExportPowerFlow, ::Int) = pf

function POM.add_power_flow_data!(
    container::OptimizationContainer,
    network_model::IOM.NetworkModel,
    sys::PSY.System,
)
    evaluations = get_evaluations(network_model)
    # The user supplies the power-flow evaluators on the NetworkModel
    # (`NetworkModel(...; evaluations = ...)`), but IOM.calculate_aux_variables! reads
    # the evaluations off the OptimizationContainer (see IOM
    # optimization_container.jl `calculate_aux_variables!`). Alias the container's
    # field to the NetworkModel's EvaluationContainer so the runtime PF data we register
    # below via `add_evaluation_data!` is the same object the aux-var calc reads later.
    # This is a consequence of the IOM/POM split owning evaluators on the NetworkModel
    # (user config) while the container is the runtime object — not a standalone bugfix.
    container.evaluations = evaluations
    isempty(evaluations) && return

    branch_aux_var_components =
        Dict{Type{<:AuxVariableType}, Set{Tuple{<:DataType, String}}}()
    bus_aux_var_components = Dict{Type{<:AuxVariableType}, Set{Tuple{<:DataType, <:Int}}}()
    n_time_steps = length(get_time_steps(container))
    for (T, evaluator) in pairs(get_evaluators(evaluations))
        # `evaluator` is a `POM.PowerFlowEvaluator` config wrapper; unwrap to the
        # underlying PowerFlows model before building the runtime container.
        evaluator = _with_time_steps(POM.get_power_flow_model(evaluator), n_time_steps)
        @info "Building PowerFlow evaluator using $(evaluator)"
        pf_data = PFS.make_power_flow_container(evaluator, sys)
        pf_e_data = PowerFlowEvaluationData(pf_data)
        my_branch_aux_vars = branch_aux_vars(pf_data)
        my_bus_aux_vars = bus_aux_vars(pf_data)

        my_branch_components = _get_branch_component_tuples(sys)
        for branch_aux_var in my_branch_aux_vars
            to_add_to = get!(
                branch_aux_var_components,
                branch_aux_var,
                Set{Tuple{<:DataType, String}}(),
            )
            push!.(Ref(to_add_to), my_branch_components)
        end

        my_bus_components = _get_bus_component_tuples(pf_data)
        for bus_aux_var in my_bus_aux_vars
            to_add_to =
                get!(bus_aux_var_components, bus_aux_var, Set{Tuple{<:DataType, <:Int}}())
            push!.(Ref(to_add_to), my_bus_components)
        end
        add_evaluation_data!(evaluations, T, pf_e_data)
    end

    _add_aux_variables!(container, branch_aux_var_components)
    _add_aux_variables!(container, bus_aux_var_components)

    # Make the input maps after adding aux vars so output of one power flow can be input of another
    for pf_e_data in values(get_evaluation_data(evaluations))
        _make_pf_input_map!(pf_e_data, container, sys)
    end
    return
end
