# tools for working with the "basic" versions of PowerModels data dict

"""
given a powermodels data dict produces a new data dict that conforms to the
following basic network model requirements.
- no dclines
- no switches
- no inactive components
- all components are numbered from 1-to-n
- the network forms a single connected component
- there exactly one phase angle reference bus
- generation cost functions are quadratic
- all branches have explicit thermal limits
- phase shift on all transformers is set to 0.0
- bus shunts have 0.0 conductance values
users requiring any of the features listed above for their analysis should use
the non-basic PowerModels routines.
"""
function make_basic_network(data::Dict{String,<:Any})
    # These initial checks are redundant with the checks in make_basic_network!
    # We keep them here so they run _before_ we create a deepcopy of the data
    # The checks are fast so this redundancy has little performance impact
    if _IM.ismultiinfrastructure(data)
        error("make_basic_network does not support multiinfrastructure data")
    end

    if _IM.ismultinetwork(data)
        error("make_basic_network does not support multinetwork data")
    end

    data = deepcopy(data)

    make_basic_network!(data)

    return data
end

"""
given a powermodels data dict, modifies it in-place to conform to basic network model requirements.

See [`make_basic_network`](@ref) for more information.
"""
function make_basic_network!(data::Dict{String,<:Any})
    if _IM.ismultiinfrastructure(data)
        error("make_basic_network does not support multiinfrastructure data")
    end

    if _IM.ismultinetwork(data)
        error("make_basic_network does not support multinetwork data")
    end

    # TODO transform PWL costs into linear costs
    for (i,gen) in data["gen"]
        if get(gen, "cost_model", 2) != 2
            error("make_basic_network only supports network data with polynomial cost functions, generator $(i) has a piecewise linear cost function")
        end
    end
    standardize_cost_terms!(data, order=2)

    # set conductance to zero on all shunts
    for (i,shunt) in data["shunt"]
        if !isapprox(shunt["gs"], 0.0)
            @warn "setting conductance on shunt $(i) from $(shunt["gs"]) to 0.0"
            shunt["gs"] = 0.0
        end
    end

    # ensure that branch components always have a rate_a value
    calc_thermal_limits!(data)

    # set phase shift to zero on all branches
    for (i,branch) in data["branch"]
        if !isapprox(branch["shift"], 0.0)
            @warn "setting phase shift on branch $(i) from $(branch["shift"]) to 0.0"
            branch["shift"] = 0.0
        end
    end

    # ensure single connected component
    select_largest_component!(data)

    # ensure that components connected in inactive buses are also inactive
    propagate_topology_status!(data)

    # ensure there is exactly one reference bus
    ref_buses = Set{Int}()
    for (i,bus) in data["bus"]
        if bus["bus_type"] == 3
            push!(ref_buses, bus["index"])
        end
    end
    if length(ref_buses) > 1
        @warn "network data specifies $(length(ref_buses)) reference buses"
        for ref_bus_id in ref_buses
            data["bus"]["$(ref_bus_id)"]["bus_type"] = 2
        end
        ref_buses = Set{Int}()
    end
    if length(ref_buses) == 0
        gen = _biggest_generator(data["gen"])
        @assert length(gen) > 0
        gen_bus = gen["gen_bus"]
        ref_bus = data["bus"]["$(gen_bus)"]
        ref_bus["bus_type"] = 3
        @warn "setting bus $(gen_bus) as reference based on generator $(gen["index"])"
    end

    # remove switches by merging buses
    resolve_switches!(data)

    # switch resolution can result in new parallel branches
    correct_branch_directions!(data)

    # set remaining unsupported components as inactive
    dcline_status_key = pm_component_status["dcline"]
    dcline_inactive_status = pm_component_status_inactive["dcline"]
    for (i,dcline) in data["dcline"]
        dcline[dcline_status_key] = dcline_inactive_status
    end

    # remove inactive components
    for (comp_key, status_key) in pm_component_status
        comp_count = length(data[comp_key])
        status_inactive = pm_component_status_inactive[comp_key]
        data[comp_key] = _filter_inactive_components(data[comp_key], status_key=status_key, status_inactive_value=status_inactive)
        if length(data[comp_key]) < comp_count
            @info "removed $(comp_count - length(data[comp_key])) inactive $(comp_key) components"
        end
    end

    # re-number non-bus component ids
    for comp_key in keys(pm_component_status)
        if comp_key != "bus"
            data[comp_key] = _renumber_components!(data[comp_key])
        end
    end

    # renumber bus ids
    bus_ordered = sort([bus for (i,bus) in data["bus"]], by=(x) -> x["index"])

    bus_id_map = Dict{Int,Int}()
    for (i,bus) in enumerate(bus_ordered)
        bus_id_map[bus["index"]] = i
    end
    update_bus_ids!(data, bus_id_map)

    data["basic_network"] = true

    return data
end

"""
given a component dict returns a new dict where inactive components have been
removed.
"""
function _filter_inactive_components(comp_dict::Dict{String,<:Any}; status_key="status", status_inactive_value=0)
    filtered_dict = Dict{String,Any}()

    for (i,comp) in comp_dict
        if comp[status_key] != status_inactive_value
            filtered_dict[i] = comp
        end
    end

    return filtered_dict
end

"""
given a component dict returns a new dict where components have been renumbered
from 1-to-n ordered by the increasing values of the orginal component id.
"""
function _renumber_components!(comp_dict::Dict{String,<:Any})
    comp_ordered = sort([(comp["index"], comp) for (i, comp) in comp_dict], by=(x) -> x[1])

    # Delete existing keys
    empty!(comp_dict)
    # Update component indices and re-build the dict keys
    for (i_new, (i_old, comp)) in enumerate(comp_ordered)
        comp["index"] = i_new
        comp_dict["$(i_new)"] = comp
    end

    return comp_dict
end



"""
given a basic network data dict, returns a complex valued vector of bus voltage
values in rectangular coordinates as they appear in the network data.
"""
function calc_basic_bus_voltage(data::Dict{String,<:Any})
    if !get(data, "basic_network", false)
        @warn "calc_basic_bus_voltage requires basic network data and given data may be incompatible. make_basic_network can be used to transform data into the appropriate form."
    end

    b = [bus for (i,bus) in data["bus"] if bus["bus_type"] != 4]
    bus_ordered = sort(b, by=(x) -> x["index"])

    return [bus["vm"]*cos(bus["va"]) + bus["vm"]*sin(bus["va"])im for bus in bus_ordered]
end

"""
given a basic network data dict, returns a complex valued vector of bus power
injections as they appear in the network data.
"""
function calc_basic_bus_injection(data::Dict{String,<:Any})
    if !get(data, "basic_network", false)
        @warn "calc_basic_bus_injection requires basic network data and given data may be incompatible. make_basic_network can be used to transform data into the appropriate form."
    end

    bi_dict = calc_bus_injection(data)
    bi_vect = [bi_dict[1][i] + bi_dict[2][i]im for i in 1:length(data["bus"])]

    return bi_vect
end

"""
given a basic network data dict, returns a complex valued vector of branch
series impedances.
"""
function calc_basic_branch_series_impedance(data::Dict{String,<:Any})
    if !get(data, "basic_network", false)
        @warn "calc_basic_branch_series_impedance requires basic network data and given data may be incompatible. make_basic_network can be used to transform data into the appropriate form."
    end

    b = [branch for (i,branch) in data["branch"] if branch["br_status"] != 0]
    branch_ordered = sort(b, by=(x) -> x["index"])

    return [branch["br_r"] + branch["br_x"]im for branch in branch_ordered]
end


"""
given a basic network data dict, returns a sparse integer valued incidence
matrix with one row for each branch and one column for each bus in the network.
In each branch row a +1 is used to indicate the _from_ bus and -1 is used to
indicate _to_ bus.
"""
function calc_basic_incidence_matrix(data::Dict{String,<:Any})
    if !get(data, "basic_network", false)
        @warn "calc_basic_incidence_matrix requires basic network data and given data may be incompatible. make_basic_network can be used to transform data into the appropriate form."
    end

    E, N = length(data["branch"])::Int, length(data["bus"])::Int
    # I = [..., e, e, ...]
    I = repeat(1:E; inner=2)
    J = zeros(Int, 2 * E)
    for e in 1:E
        branch = data["branch"]["$e"]
        J[2*e-1] = branch["f_bus"]::Int
        J[2*e] = branch["t_bus"]::Int
    end
    # V = [..., 1, -1, ...]
    V = repeat([1, -1]; outer=E)
    return SparseArrays.sparse(I, J, V, E, N)
end

"""
given a basic network data dict, returns a sparse real valued branch susceptance
matrix with one row for each branch and one column for each bus in the network.
Multiplying the branch susceptance matrix by bus phase angels yields a vector
active power flow values for each branch.
"""
function calc_basic_branch_susceptance_matrix(data::Dict{String,<:Any})
    if !get(data, "basic_network", false)
        @warn "calc_basic_branch_susceptance_matrix requires basic network data and given data may be incompatible. make_basic_network can be used to transform data into the appropriate form."
    end

    I = Int[]
    J = Int[]
    V = Float64[]

    b = [branch for (i,branch) in data["branch"] if branch["br_status"] != 0]
    branch_ordered = sort(b, by=(x) -> x["index"])
    for (i,branch) in enumerate(branch_ordered)
        g,b = calc_branch_y(branch)
        push!(I, i); push!(J, branch["f_bus"]); push!(V,  b)
        push!(I, i); push!(J, branch["t_bus"]); push!(V, -b)
    end

    return SparseArrays.sparse(I,J,V)
end
