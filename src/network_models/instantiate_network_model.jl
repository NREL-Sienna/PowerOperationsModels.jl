"""
Concrete implementations of `instantiate_network_model!` for specific network formulations.

These methods extend the generic dispatch from IOM's `operation_model_interface.jl`, which
calls `instantiate_network_model!(network_model, branch_models, number_of_steps, sys)`.
Each method here handles the formulation-specific setup: computing PTDF/LODF matrices,
discovering subnetworks, applying network reductions, etc.
"""

#################################################################################
# Helper functions (moved from IOM)
#################################################################################

function _make_subnetworks_from_subnetwork_axes(ptdf::PNM.PTDF)
    subnetworks = Dict{Int, Set{Int}}()
    for (ref_bus, ptdf_axes) in ptdf.subnetwork_axes
        subnetworks[ref_bus] = Set(ptdf_axes[1])
    end
    return subnetworks
end

function _make_subnetworks_from_subnetwork_axes(ptdf::PNM.VirtualPTDF)
    subnetworks = Dict{Int, Set{Int}}()
    for (ref_bus, ptdf_axes) in ptdf.subnetwork_axes
        subnetworks[ref_bus] = Set(ptdf_axes[2])
    end
    return subnetworks
end

function _assign_subnetworks_to_buses(
    model::NetworkModel{T},
    sys::PSY.System,
) where {T <: AbstractPTDFModel}
    subnetworks = model.subnetworks
    temp_bus_map = Dict{Int, Int}()
    network_reduction = get_network_reduction(model)
    for bus in get_available_components(model, PSY.ACBus, sys)
        bus_no = PSY.get_number(bus)
        mapped_bus_no = PNM.get_mapped_bus_number(network_reduction, bus)
        mapped_bus_no ∈ network_reduction.removed_buses && continue
        bus_mapped = false
        if haskey(temp_bus_map, bus_no)
            model.bus_area_map[bus] = temp_bus_map[bus_no]
            continue
        else
            for (subnet, bus_set) in subnetworks
                if mapped_bus_no ∈ bus_set
                    temp_bus_map[bus_no] = subnet
                    model.bus_area_map[bus] = subnet
                    bus_mapped = true
                    break
                end
            end
        end
        if !bus_mapped
            error(
                "Bus $(PSY.summary(bus)) not mapped to any reference bus: Mapped bus number: $(mapped_bus_no)",
            )
        end
    end
    return
end

_assign_subnetworks_to_buses(
    ::NetworkModel{T},
    ::PSY.System,
) where {T <: AbstractPowerModel} = nothing

#################################################################################
# Generic fallback for AbstractPowerModel (Ybus-based models: ACP, ACR, etc.)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{T},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
) where {T <: AbstractPowerModel}
    IOM._check_branch_network_compatibility(model, branch_models, sys)
    if isempty(model.subnetworks)
        model.subnetworks = PNM.find_subnetworks(sys)
    end
    if model.reduce_radial_branches && model.reduce_degree_two_branches
        @info "Applying both radial and degree two reductions"
        ybus = PNM.Ybus(
            sys;
            network_reductions = PNM.NetworkReduction[
                PNM.RadialReduction(),
                PNM.DegreeTwoReduction(),
            ],
        )
    elseif model.reduce_radial_branches
        @info "Applying radial reduction"
        ybus =
            PNM.Ybus(sys; network_reductions = PNM.NetworkReduction[PNM.RadialReduction()])
    elseif model.reduce_degree_two_branches
        @info "Applying degree two reduction"
        ybus = PNM.Ybus(
            sys;
            network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
        )
    else
        ybus = PNM.Ybus(sys)
    end
    model.network_reduction = deepcopy(PNM.get_network_reduction_data(ybus))
    #if !isempty(model.network_reductionget_net_reduction_data)
    # TODO: Network reimplement this when it becomes necessary. We don't have any
    # reductions that are incompatible right now.
    # check_network_reduction_compatibility(T)
    #end
    PNM.populate_branch_maps_by_type!(
        model.network_reduction,
        IOM._get_filters(branch_models),
    )
    empty!(model.reduced_branch_tracker)
    IOM.set_number_of_steps!(model.reduced_branch_tracker, number_of_steps)
    return
end

#################################################################################
# AreaBalancePowerModel
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{AreaBalancePowerModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    IOM._check_branch_network_compatibility(model, branch_models, sys)
    PNM.populate_branch_maps_by_type!(model.network_reduction)
    empty!(model.reduced_branch_tracker)
    IOM.set_number_of_steps!(model.reduced_branch_tracker, number_of_steps)
    return
end

#################################################################################
# CopperPlatePowerModel
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{CopperPlatePowerModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    IOM._check_branch_network_compatibility(model, branch_models, sys)
    if isempty(model.subnetworks)
        model.subnetworks = PNM.find_subnetworks(sys)
    end
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        model.network_reduction = deepcopy(PNM.get_network_reduction_data(PNM.Ybus(sys)))
        _assign_subnetworks_to_buses(model, sys)
    end
    empty!(model.reduced_branch_tracker)
    IOM.set_number_of_steps!(model.reduced_branch_tracker, number_of_steps)
    return
end

#################################################################################
# AbstractPTDFModel (PTDFPowerModel, AreaPTDFPowerModel)
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{<:AbstractPTDFModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    IOM._check_branch_network_compatibility(model, branch_models, sys)
    if IOM.get_PTDF_matrix(model) === nothing
        @info "PTDF Matrix not provided. Calculating using PowerNetworkMatrices.PTDF"
        if model.reduce_radial_branches && model.reduce_degree_two_branches
            @info "Applying both radial and degree two reductions"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[
                    PNM.RadialReduction(),
                    PNM.DegreeTwoReduction(),
                ],
            )
        elseif model.reduce_radial_branches
            @info "Applying radial reduction"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[PNM.RadialReduction()],
            )
        elseif model.reduce_degree_two_branches
            @info "Applying degree two reduction"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
            )
        else
            ptdf = PNM.VirtualPTDF(sys)
        end
        model.PTDF_matrix = ptdf
        model.network_reduction = deepcopy(ptdf.network_reduction_data)
    else
        model.network_reduction = deepcopy(model.PTDF_matrix.network_reduction_data)
    end

    if !model.reduce_radial_branches && PNM.has_radial_reduction(
        PNM.get_reductions(model.PTDF_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has reduced radial branches and mismatches the network \
                model specification reduce_radial_branches = false. Set the keyword argument \
                reduce_radial_branches = true in your network model"),
        )
    end
    if !model.reduce_degree_two_branches && PNM.has_degree_two_reduction(
        PNM.get_reductions(model.PTDF_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has reduced degree two branches and mismatches the network \
                model specification reduce_degree_two_branches = false. Set the keyword argument \
                reduce_degree_two_branches = true in your network model"),
        )
    end
    if model.reduce_radial_branches &&
       PNM.has_ward_reduction(PNM.get_reductions(model.PTDF_matrix.network_reduction_data))
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has  a ward reduction specified and the keyword argument \
                reduce_radial_branches = true. Set the keyword argument reduce_radial_branches = false \
                or provide a modified PTDF Matrix without the Ward reduction."),
        )
    end

    if model.reduce_radial_branches
        @assert !isempty(model.PTDF_matrix.network_reduction_data)
    end
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(model.PTDF_matrix)
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    PNM.populate_branch_maps_by_type!(
        model.network_reduction,
        IOM._get_filters(branch_models),
    )
    empty!(model.reduced_branch_tracker)
    IOM.set_number_of_steps!(model.reduced_branch_tracker, number_of_steps)
    return
end

#################################################################################
# AbstractSecurityConstrainedPTDFModel
#################################################################################

function IOM.instantiate_network_model!(
    model::NetworkModel{<:AbstractSecurityConstrainedPTDFModel},
    branch_models::BranchModelContainer,
    number_of_steps::Int,
    sys::PSY.System,
)
    IOM._check_branch_network_compatibility(model, branch_models, sys)
    if IOM.get_PTDF_matrix(model) === nothing
        @info "PTDF Matrix not provided. Calculating using PowerNetworkMatrices.PTDF"
        if model.reduce_radial_branches && model.reduce_degree_two_branches
            @info "Applying both radial and degree two reductions"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[
                    PNM.RadialReduction(),
                    PNM.DegreeTwoReduction(),
                ],
            )
        elseif model.reduce_radial_branches
            @info "Applying radial reduction"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[PNM.RadialReduction()],
            )
        elseif model.reduce_degree_two_branches
            @info "Applying degree two reduction"
            ptdf = PNM.VirtualPTDF(
                sys;
                network_reductions = PNM.NetworkReduction[PNM.DegreeTwoReduction()],
            )
        else
            ptdf = PNM.VirtualPTDF(sys)
        end
        model.PTDF_matrix = ptdf
        model.network_reduction = deepcopy(ptdf.network_reduction_data)
    else
        model.network_reduction = deepcopy(model.PTDF_matrix.network_reduction_data)
    end

    if !model.reduce_radial_branches && PNM.has_radial_reduction(
        PNM.get_reductions(model.PTDF_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has reduced radial branches and mismatches the network \\
                model specification reduce_radial_branches = false. Set the keyword argument \\
                reduce_radial_branches = true in your network model"),
        )
    end
    if !model.reduce_degree_two_branches && PNM.has_degree_two_reduction(
        PNM.get_reductions(model.PTDF_matrix.network_reduction_data),
    )
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has reduced degree two branches and mismatches the network \\
                model specification reduce_degree_two_branches = false. Set the keyword argument \\
                reduce_degree_two_branches = true in your network model"),
        )
    end
    if model.reduce_radial_branches &&
       PNM.has_ward_reduction(PNM.get_reductions(model.PTDF_matrix.network_reduction_data))
        throw(
            IS.ConflictingInputsError(
                "The provided PTDF Matrix has  a ward reduction specified and the keyword argument \\
                reduce_radial_branches = true. Set the keyword argument reduce_radial_branches = false \\
                or provide a modified PTDF Matrix without the Ward reduction."),
        )
    end

    if model.reduce_radial_branches
        @assert !isempty(model.PTDF_matrix.network_reduction_data)
    end
    model.subnetworks = _make_subnetworks_from_subnetwork_axes(model.PTDF_matrix)
    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    if IOM.get_LODF_matrix(model) === nothing
        @info "LODF Matrix not provided. Calculating using PowerNetworkMatrices.LODF"
        if model.reduce_radial_branches
            network_reduction = PNM.get_radial_reduction(sys)
        else
            network_reduction = PNM.NetworkReduction()
        end
        model.LODF_matrix =
            PNM.VirtualLODF(sys; network_reduction = network_reduction)
    end

    if !model.reduce_radial_branches &&
       !isempty(model.LODF_matrix.network_reduction_data.reductions) &&
       model.LODF_matrix.network_reduction_data.reduction_type ==
       PNM.NetworkReductionTypes.RADIAL
        throw(
            IS.ConflictingInputsError(
                "The provided LODF Matrix has reduced radial branches and mismatches the network \\
                model specification reduce_radial_branches = false. Set the keyword argument \\
                reduce_radial_branches = true in your network model"),
        )
    end

    if model.reduce_radial_branches &&
       !isempty(model.LODF_matrix.network_reduction_data.reductions) &&
       model.LODF_matrix.network_reduction_data.reduction_type ==
       PNM.NetworkReductionTypes.WARD
        throw(
            IS.ConflictingInputsError(
                "The provided LODF Matrix has  a ward reduction specified and the keyword argument \\
                reduce_radial_branches = true. Set the keyword argument reduce_radial_branches = false \\
                or provide a modified LODF Matrix without the Ward reduction."),
        )
    end
    PNM.populate_branch_maps_by_type!(
        model.network_reduction,
        IOM._get_filters(branch_models),
    )
    empty!(model.reduced_branch_tracker)
    IOM.set_number_of_steps!(model.reduced_branch_tracker, number_of_steps)
    return
end
