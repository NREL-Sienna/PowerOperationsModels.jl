"""
    build_opb(pm::AbstractPowerModel)
"""
function build_opb(pm::AbstractPowerModel)
    variable_bus_voltage_magnitude_only(pm)
    variable_gen_power(pm)

    objective_min_fuel_cost(pm)

    for i in ids(pm, :components)
        constraint_network_power_balance(pm, i)
    end
end

function ref_add_connected_components!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    apply_pm!(_ref_add_connected_components!, ref, data)
end

function _ref_add_connected_components!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    component_sets = calc_connected_components(data)
    ref[:components] =
        Dict(i => c for (i, c) in enumerate(sort(collect(component_sets); by = length)))
end
