"given a constant value, builds the standard component-wise solution structure"
function sol_component_fixed(
    aim::AbstractInfrastructureModel,
    it::Symbol,
    n::Int,
    comp_name::Symbol,
    field_name::Symbol,
    comp_ids,
    constant,
)
    for i in comp_ids
        @assert !haskey(sol(aim, it, n, comp_name, i), field_name)
        sol(aim, it, n, comp_name, i)[field_name] = constant
    end
end

"given a variable that is indexed by component ids, builds the standard solution structure"
function sol_component_value(
    aim::AbstractInfrastructureModel,
    it::Symbol,
    n::Int,
    comp_name::Symbol,
    field_name::Symbol,
    comp_ids,
    variables,
)
    for i in comp_ids
        @assert !haskey(sol(aim, it, n, comp_name, i), field_name)
        sol(aim, it, n, comp_name, i)[field_name] = variables[i]
    end
end

"maps asymmetric edge variables into components"
function sol_component_value_edge(
    aim::AbstractInfrastructureModel,
    it::Symbol,
    n::Int,
    comp_name::Symbol,
    field_name_fr::Symbol,
    field_name_to::Symbol,
    comp_ids_fr,
    comp_ids_to,
    variables,
)
    for (l, i, j) in comp_ids_fr
        @assert !haskey(sol(aim, it, n, comp_name, l), field_name_fr)
        sol(aim, it, n, comp_name, l)[field_name_fr] = variables[(l, i, j)]
    end

    for (l, i, j) in comp_ids_to
        @assert !haskey(sol(aim, it, n, comp_name, l), field_name_to)
        sol(aim, it, n, comp_name, l)[field_name_to] = variables[(l, i, j)]
    end
end
