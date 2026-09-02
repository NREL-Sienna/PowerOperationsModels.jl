# ACR network formulation. Provides bus voltage real (vr) and imaginary (vi)
# variables, slack-bus pinning (vi_ref == 0, vr_ref == vm_set), rectangular voltage-
# magnitude bounds, and active+reactive nodal balance.
#
# Branch flow variables, rate limits, and the rectangular AC Ohm's law are added by the
# branch device construction path (see AC_branches.jl and branch_constructor.jl).
#
# Entry points dispatch on the `voltage_coordinates` trait rather than enumerating
# {ACR, IVR} in a Union: the two share rectangular coordinates but sit in sibling branches
# of the network tree, so no supertype names the pair. Only the `RectangularVoltage`
# implementations exist, so a polar or non-voltage formulation reaching one of these raises
# a MethodError naming the trait instead of the network type.
#
# Convention: variables/constraints indexed by ACBus use bus NAME (String) — see dcp_model.jl.
# _bus_name_number_pairs / _retained_number_to_name / _bus_by_number are defined in
# dcp_model.jl (same module scope) and available here.

function add_variables!(
    container::OptimizationContainer,
    ::Type{VoltageReal},
    sys::PSY.System,
    network_model::NetworkModel{N},
) where {N <: AbstractNetworkModel}
    return _add_voltage_real_variables!(
        voltage_coordinates(N),
        container,
        sys,
        network_model,
    )
end

function _add_voltage_real_variables!(
    ::RectangularVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel,
)
    _add_bounded_bus_voltage_variable!(
        container, VoltageReal, sys, network_model,
        bus -> begin
            # bus voltage limits are already per-unit
            vlim = PSY.get_voltage_limits(bus)
            return (-vlim.max, vlim.max, PSY.get_magnitude(bus))
        end,
    )
    return
end

function add_variables!(
    container::OptimizationContainer,
    ::Type{VoltageImaginary},
    sys::PSY.System,
    network_model::NetworkModel{N},
) where {N <: AbstractNetworkModel}
    return _add_voltage_imaginary_variables!(
        voltage_coordinates(N),
        container,
        sys,
        network_model,
    )
end

function _add_voltage_imaginary_variables!(
    ::RectangularVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel,
)
    _add_bounded_bus_voltage_variable!(
        container, VoltageImaginary, sys, network_model,
        bus -> begin
            # bus voltage limits are already per-unit
            vlim = PSY.get_voltage_limits(bus)
            return (-vlim.max, vlim.max, 0.0)
        end,
    )
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{ReferenceBusConstraint},
    sys::PSY.System,
    network_model::NetworkModel{N},
) where {N <: AbstractNetworkModel}
    return _add_rectangular_reference_bus_constraints!(
        voltage_coordinates(N),
        container,
        sys,
        network_model,
    )
end

function _add_rectangular_reference_bus_constraints!(
    ::RectangularVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel,
)
    time_steps = get_time_steps(container)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    number_to_name = _retained_number_to_name(sys, network_model)
    subnets = network_model.subnetworks
    subnet_keys = collect(keys(subnets))

    cons_vi = add_constraints_container!(
        container,
        ReferenceBusConstraint,
        PSY.ACBus,
        subnet_keys,
        time_steps;
        meta = "vi",
    )
    cons_vr = add_constraints_container!(
        container,
        ReferenceBusConstraint,
        PSY.ACBus,
        subnet_keys,
        time_steps;
        meta = "vr",
    )

    for k in subnet_keys
        # `k` is the reference bus number assigned by PNM. Pin vi = 0 (angle = 0)
        # and vr = v_set (magnitude setpoint). With vi = 0, vr = sqrt(vr^2) = vm.
        # Only the reference buses are resolved (O(#subnets) name lookups), not a
        # whole-system number→bus map.
        ref_name = number_to_name[k]
        ref_bus = PSY.get_component(PSY.ACBus, sys, ref_name)
        _assert_reference_voltage_within_limits(ref_bus)
        v_set = PSY.get_magnitude(ref_bus)
        for t in time_steps
            cons_vi[k, t] =
                JuMP.@constraint(get_jump_model(container), vi[ref_name, t] == 0.0)
            cons_vr[k, t] =
                JuMP.@constraint(get_jump_model(container), vr[ref_name, t] == v_set)
        end
    end
    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{VoltageMagnitudeConstraint},
    sys::PSY.System,
    network_model::NetworkModel{N},
) where {N <: AbstractNetworkModel}
    return _add_voltage_magnitude_constraints!(
        voltage_coordinates(N),
        container,
        sys,
        network_model,
    )
end

function _add_voltage_magnitude_constraints!(
    ::RectangularVoltage,
    container::OptimizationContainer,
    sys::PSY.System,
    network_model::NetworkModel,
)
    time_steps = get_time_steps(container)
    vr = get_variable(container, VoltageReal, PSY.ACBus)
    vi = get_variable(container, VoltageImaginary, PSY.ACBus)
    pairs = _bus_name_number_pairs(sys, network_model)
    bus_names = [name for (name, _) in pairs]
    bus_by_name = _bus_by_name(sys)

    cons = add_constraints_container!(
        container,
        VoltageMagnitudeConstraint,
        PSY.ACBus,
        bus_names,
        time_steps,
    )

    for name in bus_names
        bus = bus_by_name[name]
        # bus voltage limits are already per-unit
        vlim = PSY.get_voltage_limits(bus)
        for t in time_steps
            cons[name, t] = JuMP.@constraint(
                get_jump_model(container),
                vlim.min^2 <= vr[name, t]^2 + vi[name, t]^2 <= vlim.max^2,
            )
        end
    end
    return
end
