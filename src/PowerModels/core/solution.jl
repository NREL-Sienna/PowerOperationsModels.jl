"PowerModels wrapper for the InfrastructureModels `sol_component_fixed` function."
function sol_component_fixed(
    aim::AbstractPowerModel,
    n::Int,
    comp_name::Symbol,
    field_name::Symbol,
    comp_ids,
    constant,
)
    return _IM.sol_component_fixed(
        aim,
        pm_it_sym,
        n,
        comp_name,
        field_name,
        comp_ids,
        constant,
    )
end

"PowerModels wrapper for the InfrastructureModels `sol_component_value` function."
function sol_component_value(
    aim::AbstractPowerModel,
    n::Int,
    comp_name::Symbol,
    field_name::Symbol,
    comp_ids,
    variables,
)
    return _IM.sol_component_value(
        aim,
        pm_it_sym,
        n,
        comp_name,
        field_name,
        comp_ids,
        variables,
    )
end

"PowerModels wrapper for the InfrastructureModels `sol_component_value_edge` function."
function sol_component_value_edge(
    aim::AbstractPowerModel,
    n::Int,
    comp_name::Symbol,
    field_name_fr::Symbol,
    field_name_to::Symbol,
    comp_ids_fr,
    comp_ids_to,
    variables,
)
    return _IM.sol_component_value_edge(
        aim,
        pm_it_sym,
        n,
        comp_name,
        field_name_fr,
        field_name_to,
        comp_ids_fr,
        comp_ids_to,
        variables,
    )
end
