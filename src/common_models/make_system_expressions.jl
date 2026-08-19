
function make_container_array(ax...)
    return IOM.remove_undef!(DenseAxisArray{GAE}(undef, ax...))
end

"""
Generic fallback for full power flow models (ACP, ACR, etc.).
Creates both ActivePowerBalance and ReactivePowerBalance on ACBus.
"""
function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{<:AbstractNetworkModel},
    bus_reduction_map::Dict{Int64, Set{Int64}},
)
    time_steps = get_time_steps(container)
    if isempty(bus_reduction_map)
        ac_bus_numbers = collect(Iterators.flatten(values(subnetworks)))
    else
        ac_bus_numbers = collect(keys(bus_reduction_map))
    end
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.ACBus) =>
            make_container_array(ac_bus_numbers, time_steps),
        ExpressionKey(ReactivePowerBalance, PSY.ACBus) =>
            make_container_array(ac_bus_numbers, time_steps),
    )
    return
end

"""
Fallback for active-power-only models (DCP, NFA, etc.).
Creates only ActivePowerBalance on ACBus (no reactive power).
"""
function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{<:AbstractActivePowerModel},
    bus_reduction_map::Dict{Int64, Set{Int64}},
)
    time_steps = get_time_steps(container)
    if isempty(bus_reduction_map)
        ac_bus_numbers = collect(Iterators.flatten(values(subnetworks)))
    else
        ac_bus_numbers = collect(keys(bus_reduction_map))
    end
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.ACBus) =>
            make_container_array(ac_bus_numbers, time_steps),
    )
    return
end

function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{CopperPlateNetworkModel},
    bus_reduction_map::Dict{Int64, Set{Int64}},
)
    time_steps = get_time_steps(container)
    subnetworks_ref_buses = collect(keys(subnetworks))
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.System) =>
            make_container_array(subnetworks_ref_buses, time_steps),
    )
    return
end

function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{T},
    bus_reduction_map::Dict{Int64, Set{Int64}},
) where {T <: PTDFNetworkModel}
    time_steps = get_time_steps(container)
    if isempty(bus_reduction_map)
        ac_bus_numbers = collect(Iterators.flatten(values(subnetworks)))
    else
        ac_bus_numbers = collect(keys(bus_reduction_map))
    end
    subnetworks = collect(keys(subnetworks))
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.System) =>
            make_container_array(subnetworks, time_steps),
        ExpressionKey(ActivePowerBalance, PSY.ACBus) =>
        # Bus numbers are sorted to guarantee consistency in the order between the
        # containers
            make_container_array(sort!(ac_bus_numbers), time_steps),
    )
    return
end

function make_system_expressions!(
    container::OptimizationContainer,
    ::Dict{Int, Set{Int}},
    ::Type{AreaBalanceNetworkModel},
    areas::IS.FlattenIteratorWrapper{PSY.Area},
)
    time_steps = get_time_steps(container)
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.Area) =>
            make_container_array(PSY.get_name.(areas), time_steps),
    )
    return
end

function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{AreaPTDFNetworkModel},
    areas::IS.FlattenIteratorWrapper{PSY.Area},
    bus_reduction_map::Dict{Int64, Set{Int64}},
)
    time_steps = get_time_steps(container)
    if isempty(bus_reduction_map)
        ac_bus_numbers = collect(Iterators.flatten(values(subnetworks)))
    else
        ac_bus_numbers = collect(keys(bus_reduction_map))
    end
    container.expressions = Dict(
        ExpressionKey(ActivePowerBalance, PSY.Area) =>
            make_container_array(PSY.get_name.(areas), time_steps),
        ExpressionKey(ActivePowerBalance, PSY.ACBus) =>
        # Bus numbers are sorted to guarantee consistency in the order between the
        # containers
            make_container_array(sort!(ac_bus_numbers), time_steps),
    )

    if length(subnetworks) > 1
        @warn "The system contains $(length(subnetworks)) synchronous regions. \
               When combined with AreaPTDFNetworkModel, the model can be infeasible if the data doesn't \
               have a well defined topology"
        subnetworks_ref_buses = collect(keys(subnetworks))
        container.expressions[ExpressionKey(ActivePowerBalance, PSY.System)] =
            make_container_array(subnetworks_ref_buses, time_steps)
    end

    return
end

#################################################################################
# initialize_system_expressions! overrides for area-based network models
#################################################################################

function _verify_area_subnetwork_topology(sys::PSY.System, subnetworks::Dict{Int, Set{Int}})
    if length(subnetworks) <= 1
        @debug "Only one subnetwork detected in the system. Area - Subnetwork topology check is valid."
        return
    end

    @warn "More than one subnetwork detected in AreaBalanceNetworkModel. Topology consistency checks must be conducted."

    area_map = PSY.get_aggregation_topology_mapping(PSY.Area, sys)
    # Keyed by area name, not by the Area component.
    for (area_name, buses) in area_map
        bus_numbers =
            [
                PSY.get_number(b) for
                b in buses if PSY.get_bustype(b) != PSY.ACBusTypes.ISOLATED
            ]
        subnets = Int[]
        for (subnet, subnet_bus_numbers) in subnetworks
            if !isdisjoint(bus_numbers, subnet_bus_numbers)
                push!(subnets, subnet)
            end
        end
        if length(subnets) > 1
            @error "Area $(area_name) is connected to multiple subnetworks $(subnets)."
            throw(
                IS.ConflictingInputsError(
                    "AreaBalanceNetworkModel doesn't support systems with Areas distributed across multiple asynchronous areas",
                ))
        end
    end
    return
end

function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{AreaBalanceNetworkModel},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    ::Dict{Int64, Set{Int64}},
)
    areas = get_available_components(network_model, PSY.Area, system)
    if isempty(areas)
        throw(
            IS.ConflictingInputsError(
                "AreaBalanceNetworkModel doesn't support systems with no defined Areas",
            ),
        )
    end
    area_interchanges = PSY.get_available_components(PSY.AreaInterchange, system)
    if isempty(area_interchanges) ||
       PSY.AreaInterchange ∉ network_model.modeled_branch_types
        @warn "The system does not contain any AreaInterchanges. The model won't have any power flowing between the areas."
    end
    if !isempty(area_interchanges) &&
       PSY.AreaInterchange ∉ network_model.modeled_branch_types
        @warn "AreaInterchanges are not included in the model template. The model won't have any power flowing between the areas."
    end
    _verify_area_subnetwork_topology(system, subnetworks)
    make_system_expressions!(container, subnetworks, AreaBalanceNetworkModel, areas)
    return
end

function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    bus_reduction_map::Dict{Int64, Set{Int64}},
) where {T <: AreaPTDFNetworkModel}
    areas = get_available_components(network_model, PSY.Area, system)
    if isempty(areas)
        throw(
            IS.ConflictingInputsError(
                "AreaPTDFNetworkModel doesn't support systems with no Areas",
            ),
        )
    end
    dc_bus_numbers = [
        PSY.get_number(b) for
        b in get_available_components(network_model, PSY.DCBus, system)
    ]
    make_system_expressions!(
        container,
        subnetworks,
        dc_bus_numbers,
        T,
        areas,
        bus_reduction_map,
    )
    return
end

function initialize_hvdc_system!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    dc_model::U,
    system::PSY.System,
) where {T <: AbstractNetworkModel, U <: TransportHVDCNetworkModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    @assert !isempty(dc_buses) "No DC buses found in the system. Consider adding DC Buses or removing HVDC network model."
    dc_bus_numbers = sort(PSY.get_number.(dc_buses))
    container.expressions[ExpressionKey(ActivePowerBalance, PSY.DCBus)] =
        make_container_array(dc_bus_numbers, get_time_steps(container))
    return
end

function initialize_hvdc_system!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    dc_model::U,
    system::PSY.System,
) where {T <: AbstractNetworkModel, U <: VoltageDispatchHVDCNetworkModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    @assert !isempty(dc_buses) "No DC buses found in the system. Consider adding DC Buses or removing HVDC network model."
    dc_bus_numbers = sort(PSY.get_number.(dc_buses))
    container.expressions[ExpressionKey(DCCurrentBalance, PSY.DCBus)] =
        make_container_array(dc_bus_numbers, get_time_steps(container))
    add_variables!(container, DCVoltage, dc_buses, U)
    return
end
