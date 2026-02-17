
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
    ::Type{<:AbstractPowerModel},
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
    ::Type{CopperPlatePowerModel},
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
) where {T <: PTDFPowerModel} # SecurityConstrainedAreaPTDFPowerModel is WIMP.
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
    ::Type{AreaBalancePowerModel},
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
    ::Type{AreaPTDFPowerModel},
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
               When combined with AreaPTDFPowerModel, the model can be infeasible if the data doesn't \
               have a well defined topology"
        subnetworks_ref_buses = collect(keys(subnetworks))
        container.expressions[ExpressionKey(ActivePowerBalance, PSY.System)] =
            make_container_array(subnetworks_ref_buses, time_steps)
    end

    return
end

#TODO Check if SecurityConstrainedAreaPTDFPowerModel needs something else
function make_system_expressions!(
    container::OptimizationContainer,
    subnetworks::Dict{Int, Set{Int}},
    ::Vector{Int},
    ::Type{SecurityConstrainedAreaPTDFPowerModel},
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
               When combined with SecurityConstrainedAreaPTDFPowerModel, the model can be infeasible if the data doesn't \
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
    if length(subnetworks) < 1
        @debug "Only one subnetwork detected in the system. Area - Subnetwork topology check is valid."
        return
    end

    @warn "More than one subnetwork detected in AreaBalancePowerModel. Topology consistency checks must be conducted."

    area_map = PSY.get_aggregation_topology_mapping(PSY.Area, sys)
    for (area, buses) in area_map
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
            @error "Area $(PSY.get_name(area)) is connected to multiple subnetworks $(subnets)."
            throw(
                IS.ConflictingInputsError(
                    "AreaBalancePowerModel doesn't support systems with Areas distributed across multiple asynchronous areas",
                ))
        end
    end
    return
end

function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{AreaBalancePowerModel},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    ::Dict{Int64, Set{Int64}},
)
    areas = get_available_components(network_model, PSY.Area, system)
    if isempty(areas)
        throw(
            IS.ConflictingInputsError(
                "AreaBalancePowerModel doesn't support systems with no defined Areas",
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
    make_system_expressions!(container, subnetworks, AreaBalancePowerModel, areas)
    return
end

function initialize_system_expressions!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    subnetworks::Dict{Int, Set{Int}},
    system::PSY.System,
    bus_reduction_map::Dict{Int64, Set{Int64}},
) where {T <: Union{AreaPTDFPowerModel, SecurityConstrainedAreaPTDFPowerModel}}
    areas = get_available_components(network_model, PSY.Area, system)
    if isempty(areas)
        throw(
            IS.ConflictingInputsError(
                "AreaPTDFPowerModel/SecurityConstrainedAreaPTDFPowerModel doesn't support systems with no Areas",
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

# NOTE: Commented out because it references TransportHVDCNetworkModel concrete type
# This should be defined in PowerSimulations if needed for specific network models
function initialize_hvdc_system!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    dc_model::U,
    system::PSY.System,
) where {T <: AbstractPowerModel, U <: TransportHVDCNetworkModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    @assert !isempty(dc_buses) "No DC buses found in the system. Consider adding DC Buses or removing HVDC network model."
    dc_bus_numbers = sort(PSY.get_number.(dc_buses))
    container.expressions[ExpressionKey(ActivePowerBalance, PSY.DCBus)] =
        make_container_array(dc_bus_numbers, get_time_steps(container))
    return
end

# NOTE: Commented out because it references VoltageDispatchHVDCNetworkModel concrete type
# This should be defined in PowerSimulations if needed for specific network models
function initialize_hvdc_system!(
    container::OptimizationContainer,
    network_model::NetworkModel{T},
    dc_model::U,
    system::PSY.System,
) where {T <: AbstractPowerModel, U <: VoltageDispatchHVDCNetworkModel}
    dc_buses = get_available_components(network_model, PSY.DCBus, system)
    @assert !isempty(dc_buses) "No DC buses found in the system. Consider adding DC Buses or removing HVDC network model."
    dc_bus_numbers = sort(PSY.get_number.(dc_buses))
    container.expressions[ExpressionKey(DCCurrentBalance, PSY.DCBus)] =
        make_container_array(dc_bus_numbers, get_time_steps(container))
    add_variable!(container, DCVoltage(), dc_buses, dc_model)
    return
end
