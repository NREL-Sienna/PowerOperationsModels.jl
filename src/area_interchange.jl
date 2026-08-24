#! format: off
get_multiplier_value(::Type{FromToFlowLimitParameter}, d::PSY.AreaInterchange, ::Type{<:AbstractBranchFormulation}) = -1.0 * PSY.get_from_to_flow_limit(d)
get_multiplier_value(::Type{ToFromFlowLimitParameter}, d::PSY.AreaInterchange, ::Type{<:AbstractBranchFormulation}) = PSY.get_to_from_flow_limit(d)

get_parameter_multiplier(::Type{FixValueParameter}, ::PSY.AreaInterchange, ::Type{<:AbstractBranchFormulation}) = 1.0
get_parameter_multiplier(::Type{LowerBoundValueParameter}, ::PSY.AreaInterchange, ::Type{<:AbstractBranchFormulation}) = 1.0
get_parameter_multiplier(::Type{UpperBoundValueParameter}, ::PSY.AreaInterchange, ::Type{<:AbstractBranchFormulation}) = 1.0

get_initial_conditions_device_model(
    ::IOM.AbstractOptimizationModel,
    model::DeviceModel{PSY.AreaInterchange, T},
) where {T <: AbstractBranchFormulation} = DeviceModel(PSY.AreaInterchange, T)

#! format: on

function get_default_time_series_names(
    ::Type{PSY.AreaInterchange},
    ::Type{V},
) where {V <: AbstractBranchFormulation}
    return Dict{Type{<:TimeSeriesParameter}, String}(
        FromToFlowLimitParameter => "from_to_flow_limit",
        ToFromFlowLimitParameter => "to_from_flow_limit",
    )
end

function get_default_attributes(
    ::Type{PSY.AreaInterchange},
    ::Type{V},
) where {V <: AbstractBranchFormulation}
    return Dict{String, Any}()
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{FlowActivePowerVariable},
    model::NetworkModel{T},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    ::Type{<:AbstractBranchFormulation},
) where {T <: AbstractNetworkModel}
    time_steps = get_time_steps(container)

    variable = add_variable_container!(container, FlowActivePowerVariable,
        PSY.AreaInterchange,
        PSY.get_name.(devices),
        time_steps,
    )

    for device in devices, t in time_steps
        device_name = get_name(device)
        variable[device_name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "FlowActivePowerVariable_AreaInterchange_{$(device_name), $(t)}",
        )
    end
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{FlowActivePowerVariable},
    model::NetworkModel{CopperPlateNetworkModel},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    ::Type{<:AbstractBranchFormulation},
)
    @warn(
        "CopperPlateNetworkModel ignores AreaInterchanges. Instead use AreaBalanceNetworkModel."
    )
    return
end

"""
Add flow constraints for area interchanges
"""
function add_constraints!(
    container::OptimizationContainer,
    ::Type{FlowLimitConstraint},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    model::DeviceModel{PSY.AreaInterchange, StaticBranch},
    ::NetworkModel{T},
) where {T <: AbstractNetworkModel}
    time_steps = get_time_steps(container)
    device_names = PSY.get_name.(devices)

    con_ub = add_constraints_container!(container, FlowLimitConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "ub",
    )

    con_lb = add_constraints_container!(container, FlowLimitConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "lb",
    )

    var_array = get_variable(container, FlowActivePowerVariable, PSY.AreaInterchange)
    if !all(PSY.has_time_series.(devices))
        for device in devices
            ci_name = PSY.get_name(device)
            to_from_limit = PSY.get_flow_limits(device, PSY.SU).to_from
            from_to_limit = PSY.get_flow_limits(device, PSY.SU).from_to
            for t in time_steps
                con_lb[ci_name, t] =
                    JuMP.@constraint(
                        get_jump_model(container),
                        var_array[ci_name, t] >= -1.0 * from_to_limit
                    )
                con_ub[ci_name, t] =
                    JuMP.@constraint(
                        get_jump_model(container),
                        var_array[ci_name, t] <= to_from_limit
                    )
            end
        end
    else
        param_container_from_to =
            get_parameter(container, FromToFlowLimitParameter, PSY.AreaInterchange)
        param_multiplier_from_to =
            get_parameter_multiplier_array(container, FromToFlowLimitParameter,
                PSY.AreaInterchange,
            )
        param_container_to_from =
            get_parameter(container, ToFromFlowLimitParameter, PSY.AreaInterchange)
        param_multiplier_to_from =
            get_parameter_multiplier_array(container, ToFromFlowLimitParameter,
                PSY.AreaInterchange,
            )
        jump_model = get_jump_model(container)
        for device in devices
            name = PSY.get_name(device)
            param_from_to = get_parameter_column_refs(param_container_from_to, name)
            param_to_from = get_parameter_column_refs(param_container_to_from, name)
            for t in time_steps
                con_lb[name, t] = JuMP.@constraint(
                    jump_model,
                    var_array[name, t] >=
                    param_multiplier_from_to[name, t] * param_from_to[t]
                )
                con_ub[name, t] = JuMP.@constraint(
                    jump_model,
                    var_array[name, t] <=
                    param_multiplier_to_from[name, t] * param_to_from[t]
                )
            end
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{LineFlowBoundConstraint},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    model::DeviceModel{PSY.AreaInterchange, <:AbstractBranchFormulation},
    network_model::NetworkModel{T},
    inter_area_branch_map::Dict{
        Tuple{String, String},
        Dict{DataType, Vector{String}},
    },
) where {T <: AbstractPTDFNetworkModel}
    @assert !isempty(inter_area_branch_map)

    time_steps = get_time_steps(container)
    device_names = PSY.get_name.(devices)

    con_ub = add_constraints_container!(container, LineFlowBoundConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "ub",
    )

    con_lb = add_constraints_container!(container, LineFlowBoundConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "lb",
    )

    area_ex_var = get_variable(container, FlowActivePowerVariable, PSY.AreaInterchange)
    branch_catalog = get_branch_catalog(network_model)
    # Memoize the PTDF orientation sign per (type, name): a degree-two series
    # member whose native from→to is `:ToFrom` relative to the merged arc
    # contributes with a flipped sign to the area sum.
    orientation_sign_cache = Dict{Tuple{DataType, String}, Float64}()
    jm = get_jump_model(container)
    for area_interchange in devices
        inter_change_name = PSY.get_name(area_interchange)
        area_from_name = PSY.get_name(PSY.get_from_area(area_interchange))
        area_to_name = PSY.get_name(PSY.get_to_area(area_interchange))
        direction_branch_map = Dict{Float64, Dict{DataType, Vector{String}}}()
        if haskey(inter_area_branch_map, (area_from_name, area_to_name))
            # 1 is the multiplier
            direction_branch_map[1.0] =
                inter_area_branch_map[(area_from_name, area_to_name)]
        end
        if haskey(inter_area_branch_map, (area_to_name, area_from_name))
            # -1 is the multiplier because the direction is reversed
            direction_branch_map[-1.0] =
                inter_area_branch_map[(area_to_name, area_from_name)]
        end
        if isempty(direction_branch_map)
            @warn(
                "There are no branches modeled in Area InterChange $(summary(area_interchange)) \
          LineFlowBoundConstraint not created"
            )
            continue
        end

        for t in time_steps
            sum_of_flows = JuMP.AffExpr()
            for (mult, inter_area_branches) in direction_branch_map
                for (type, names) in inter_area_branches
                    _add_ptdf_area_tie_flows!(
                        sum_of_flows,
                        container,
                        type,
                        names,
                        mult,
                        branch_catalog,
                        orientation_sign_cache,
                        t,
                    )
                end
            end
            con_ub[inter_change_name, t] =
                JuMP.@constraint(jm, sum_of_flows <= area_ex_var[inter_change_name, t])
            con_lb[inter_change_name, t] =
                JuMP.@constraint(jm, sum_of_flows >= area_ex_var[inter_change_name, t])
        end
    end
    return
end

function _add_ptdf_area_tie_flows!(
    sum_of_flows::JuMP.AffExpr,
    container::OptimizationContainer,
    ::Type{V},
    names::Vector{String},
    mult::Float64,
    branch_catalog::PNM.BranchCatalog,
    orientation_sign_cache::Dict{Tuple{DataType, String}, Float64},
    t::Int,
) where {V <: PSY.ACTransmission}
    flow_expr = get_expression(container, PTDFBranchFlow, V)
    for name in names
        orientation_sign = get!(orientation_sign_cache, (V, name)) do
            get_ptdf_orientation_sign(branch_catalog, V, name)
        end
        JuMP.add_to_expression!(
            sum_of_flows,
            flow_expr[name, t],
            mult * orientation_sign,
        )
    end
    return
end

# HVDC tie lines carry flow variables, not a PTDFBranchFlow expression. They are metered
# like the AC-network interchange path: at the terminal on the interchange's from-area
# side, so a lossy directional tie contributes its exporting-end flow.
function _add_ptdf_area_tie_flows!(
    sum_of_flows::JuMP.AffExpr,
    container::OptimizationContainer,
    ::Type{V},
    names::Vector{String},
    mult::Float64,
    branch_catalog::PNM.BranchCatalog,
    orientation_sign_cache::Dict{Tuple{DataType, String}, Float64},
    t::Int,
) where {V <: PSY.TwoTerminalHVDC}
    if mult > 0.0
        measured_variable_type = FlowActivePowerFromToVariable
    else
        measured_variable_type = FlowActivePowerToFromVariable
    end
    _add_measured_tie_line_flows!(
        sum_of_flows,
        container,
        measured_variable_type,
        V,
        names,
        branch_catalog,
        orientation_sign_cache,
        t,
    )
    return
end

# On the AC networks a tie line is lossy, so its two directional active-flow variables
# differ by the line loss and the interchange must fix a measurement end. It is measured
# at the exporting (from-area) boundary: each tie line contributes the directional flow
# variable metered at its terminal inside the interchange's from-area, so the measured
# export includes the tie-line loss. A branch keyed (from_area, to_area) is metered at
# its own from terminal (FlowActivePowerFromToVariable); a branch keyed
# (to_area, from_area) at its own to terminal (FlowActivePowerToFromVariable).
function add_constraints!(
    container::OptimizationContainer,
    ::Type{LineFlowBoundConstraint},
    devices::IS.FlattenIteratorWrapper{PSY.AreaInterchange},
    model::DeviceModel{PSY.AreaInterchange, <:AbstractBranchFormulation},
    network_model::NetworkModel{T},
    inter_area_branch_map::Dict{
        Tuple{String, String},
        Dict{DataType, Vector{String}},
    },
) where {T <: AbstractReactivePowerNetworkModel}
    @assert !isempty(inter_area_branch_map)

    time_steps = get_time_steps(container)
    device_names = PSY.get_name.(devices)

    con_ub = add_constraints_container!(container, LineFlowBoundConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "ub",
    )

    con_lb = add_constraints_container!(container, LineFlowBoundConstraint,
        PSY.AreaInterchange,
        device_names,
        time_steps;
        meta = "lb",
    )

    area_ex_var = get_variable(container, FlowActivePowerVariable, PSY.AreaInterchange)
    branch_catalog = get_branch_catalog(network_model)
    orientation_sign_cache = Dict{Tuple{DataType, String}, Float64}()
    jm = get_jump_model(container)
    for area_interchange in devices
        inter_change_name = PSY.get_name(area_interchange)
        area_from_name = PSY.get_name(PSY.get_from_area(area_interchange))
        area_to_name = PSY.get_name(PSY.get_to_area(area_interchange))
        measured_branch_map = Dict{DataType, Dict{DataType, Vector{String}}}()
        if haskey(inter_area_branch_map, (area_from_name, area_to_name))
            measured_branch_map[FlowActivePowerFromToVariable] =
                inter_area_branch_map[(area_from_name, area_to_name)]
        end
        if haskey(inter_area_branch_map, (area_to_name, area_from_name))
            measured_branch_map[FlowActivePowerToFromVariable] =
                inter_area_branch_map[(area_to_name, area_from_name)]
        end
        if isempty(measured_branch_map)
            @warn(
                "There are no branches modeled in Area InterChange $(summary(area_interchange)) \
          LineFlowBoundConstraint not created"
            )
            continue
        end

        for t in time_steps
            sum_of_flows = JuMP.AffExpr()
            for (measured_variable_type, inter_area_branches) in measured_branch_map
                for (type, names) in inter_area_branches
                    _add_measured_tie_line_flows!(
                        sum_of_flows,
                        container,
                        measured_variable_type,
                        type,
                        names,
                        branch_catalog,
                        orientation_sign_cache,
                        t,
                    )
                end
            end
            con_ub[inter_change_name, t] =
                JuMP.@constraint(jm, sum_of_flows <= area_ex_var[inter_change_name, t])
            con_lb[inter_change_name, t] =
                JuMP.@constraint(jm, sum_of_flows >= area_ex_var[inter_change_name, t])
        end
    end
    return
end

function _add_measured_tie_line_flows!(
    sum_of_flows::JuMP.AffExpr,
    container::OptimizationContainer,
    ::Type{U},
    ::Type{V},
    names::Vector{String},
    branch_catalog::PNM.BranchCatalog,
    orientation_sign_cache::Dict{Tuple{DataType, String}, Float64},
    t::Int,
) where {
    U <: Union{FlowActivePowerFromToVariable, FlowActivePowerToFromVariable},
    V <: PSY.ACBranch,
}
    flow_variable, measured_direction_mult = _resolve_measured_flow(container, U, V)
    for name in names
        orientation_sign = get!(orientation_sign_cache, (V, name)) do
            _tie_line_orientation_sign(branch_catalog, V, name)
        end
        JuMP.add_to_expression!(
            sum_of_flows,
            flow_variable[name, t],
            measured_direction_mult * orientation_sign,
        )
    end
    return
end

# Resolve the container variable that carries the measured-terminal export and its
# sign. First match wins; a device type builds exactly one formulation per template,
# so at most one family is present. Multipliers convert each family's convention to
# "export at the measured terminal": the directional pair and the LCC rectifier are
# already exports (+1); the LCC inverter and the PWL received variables are
# injections at their terminal (-1); the lossless fallback is signed from -> to.
function _resolve_measured_flow(
    container::OptimizationContainer,
    ::Type{U},
    ::Type{V},
) where {
    U <: Union{FlowActivePowerFromToVariable, FlowActivePowerToFromVariable},
    V <: PSY.ACBranch,
}
    if has_container_key(container, U, V)
        return get_variable(container, U, V), 1.0
    end
    lcc_variable = _measured_lcc_variable(U)
    if has_container_key(container, lcc_variable, V)
        return get_variable(container, lcc_variable, V),
        _measured_lcc_mult(U)
    end
    received_variable = _measured_received_variable(U)
    if has_container_key(container, received_variable, V)
        return get_variable(container, received_variable, V), -1.0
    end
    if has_container_key(container, FlowActivePowerVariable, V)
        return get_variable(container, FlowActivePowerVariable, V),
        _measured_direction_mult(U)
    end
    error(
        "AreaInterchange cannot meter tie lines of type $V: the container has none of ",
        "the flow variables ($U, $(_measured_lcc_variable(U)), ",
        "$(_measured_received_variable(U)), FlowActivePowerVariable). ",
        "Add a DeviceModel for $V to the template or remove the tie from the interchange.",
    )
end

_measured_lcc_variable(::Type{FlowActivePowerFromToVariable}) =
    HVDCRectifierActivePowerVariable
_measured_lcc_variable(::Type{FlowActivePowerToFromVariable}) =
    HVDCInverterActivePowerVariable
_measured_lcc_mult(::Type{FlowActivePowerFromToVariable}) = 1.0
_measured_lcc_mult(::Type{FlowActivePowerToFromVariable}) = -1.0

_measured_received_variable(::Type{FlowActivePowerFromToVariable}) =
    HVDCActivePowerReceivedFromVariable
_measured_received_variable(::Type{FlowActivePowerToFromVariable}) =
    HVDCActivePowerReceivedToVariable

_measured_direction_mult(::Type{FlowActivePowerFromToVariable}) = 1.0
_measured_direction_mult(::Type{FlowActivePowerToFromVariable}) = -1.0

function _tie_line_orientation_sign(
    branch_catalog::PNM.BranchCatalog,
    ::Type{T},
    name::AbstractString,
) where {T <: PSY.ACTransmission}
    return get_ptdf_orientation_sign(branch_catalog, T, name)
end

# HVDC tie lines are never network-reduced, so their native orientation always matches.
function _tie_line_orientation_sign(
    ::PNM.BranchCatalog,
    ::Type{T},
    ::AbstractString,
) where {T <: PSY.TwoTerminalHVDC}
    return 1.0
end
