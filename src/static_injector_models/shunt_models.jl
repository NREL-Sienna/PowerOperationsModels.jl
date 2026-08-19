#################################################################################
# Controllable shunt device traits and bounds helpers.
#
# Two concrete PSY types are supported:
#   - SwitchedAdmittance (<: ElectricLoad <: StaticInjection)
#   - FACTSControlDevice (<: StaticInjection)
#
# The constructor's device slot is bound to exactly these two types.
#################################################################################

# Susceptance limits (pu, system base) for the continuous shunt control variable `b`.
# SwitchedAdmittance: base imag(Y) plus the achievable block increments (continuous
# relaxation of the discrete steps). FACTSControlDevice: maximum shunt current band.
function _shunt_susceptance_limits(d::PSY.SwitchedAdmittance)
    b0 = imag(PSY.get_Y(d))
    steps = PSY.get_number_of_steps(d)
    incr = PSY.get_Y_increase(d)
    # Sum capacitive (positive imag) and inductive (negative imag) blocks separately so
    # that a device with mixed-sign blocks is not silently collapsed to b ∈ [0, 0].
    b_dec = sum(steps[i] * min(imag(incr[i]), 0.0) for i in eachindex(steps); init = 0.0)
    b_inc = sum(steps[i] * max(imag(incr[i]), 0.0) for i in eachindex(steps); init = 0.0)
    lo = b0 + b_dec
    hi = b0 + b_inc
    if !(isfinite(lo) && isfinite(hi))
        error(
            "SwitchedAdmittance $(PSY.get_name(d)) has non-finite susceptance limits; ",
            "check Y and Y_increase fields",
        )
    end
    return (min = lo, max = hi)
end

function _shunt_susceptance_limits(d::PSY.FACTSControlDevice)
    # max_shunt_current is stored in MVA at unity voltage. At V = 1 pu the reactive power
    # equals B * V² = B, so its system-base per-unit value IS the susceptance bound.
    b_max = PSY.get_max_shunt_current(d, PSY.SU)
    if !isfinite(b_max) || iszero(b_max)
        error(
            "FACTSControlDevice $(PSY.get_name(d)) has zero/invalid max_shunt_current; ",
            "cannot bound susceptance",
        )
    end
    return (min = -b_max, max = b_max)
end

# Non-dispatched susceptance (pu, system base) for FixedShuntAdmittance.
# SwitchedAdmittance: the base admittance imag(Y). FACTSControlDevice: the reactive-power
# setpoint at unity voltage (Q = b·V² = b at V = 1 pu), converted to system base like the
# max_shunt_current band.
_fixed_shunt_susceptance(d::PSY.SwitchedAdmittance) = imag(PSY.get_Y(d))

function _fixed_shunt_susceptance(d::PSY.FACTSControlDevice)
    s_base = PSY.get_base_power(d)
    if !isfinite(s_base) || iszero(s_base)
        error(
            "FACTSControlDevice $(PSY.get_name(d)) has zero/invalid system base power; ",
            "cannot convert the reactive-power setpoint to per unit",
        )
    end
    b = PSY.get_reactive_power_required(d) / s_base
    if !isfinite(b)
        error(
            "FACTSControlDevice $(PSY.get_name(d)) has a non-finite reactive-power ",
            "setpoint; cannot fix its susceptance",
        )
    end
    return b
end

#################################################################################
# ShuntSusceptanceVariable traits
#################################################################################

get_variable_binary(
    ::Type{ShuntSusceptanceVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{ShuntSusceptanceDispatch},
) = false

get_variable_multiplier(
    ::Type{ShuntSusceptanceVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{ShuntSusceptanceDispatch},
) = 1.0

function get_variable_lower_bound(
    ::Type{ShuntSusceptanceVariable},
    d::PSY.StaticInjection,
    ::Type{ShuntSusceptanceDispatch},
)
    return _shunt_susceptance_limits(d).min
end

function get_variable_upper_bound(
    ::Type{ShuntSusceptanceVariable},
    d::PSY.StaticInjection,
    ::Type{ShuntSusceptanceDispatch},
)
    return _shunt_susceptance_limits(d).max
end

#################################################################################
# ReactivePowerVariable traits for ShuntSusceptanceDispatch
#
# Q = b * V² is an equality with b ∈ [b_min, b_max] and V ∈ [v_min, v_max].
# The true Q range is the minimum and maximum over all four corners
# {b_min, b_max} × {v_min², v_max²}, because b can be negative (capacitive) so
# the extrema do not always occur at v_max.
#################################################################################

get_variable_binary(
    ::Type{ReactivePowerVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{ShuntSusceptanceDispatch},
) = false

get_variable_multiplier(
    ::Type{ReactivePowerVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{ShuntSusceptanceDispatch},
) = 1.0

function _reactive_power_bounds(d::PSY.StaticInjection)
    b = _shunt_susceptance_limits(d)
    # bus voltage limits are already per-unit
    vlims = PSY.get_voltage_limits(PSY.get_bus(d))
    vmin = vlims.min
    vmax = vlims.max
    if !isfinite(vmin) || !isfinite(vmax) || vmin <= 0.0
        error(
            "Device $(PSY.get_name(d)) bus has non-finite or non-positive voltage limits; ",
            "cannot bound ReactivePowerVariable",
        )
    end
    lo = minimum(bx * vx for bx in (b.min, b.max), vx in (vmin^2, vmax^2))
    hi = maximum(bx * vx for bx in (b.min, b.max), vx in (vmin^2, vmax^2))
    return (min = lo, max = hi)
end

function get_variable_lower_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.StaticInjection,
    ::Type{ShuntSusceptanceDispatch},
)
    return _reactive_power_bounds(d).min
end

function get_variable_upper_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.StaticInjection,
    ::Type{ShuntSusceptanceDispatch},
)
    return _reactive_power_bounds(d).max
end

#################################################################################
# ReactivePowerVariable traits for FixedShuntAdmittance
#
# Q = b_nominal * V² with b_nominal fixed, so the Q range is b_nominal over
# {v_min², v_max²}, ordered because b_nominal may be negative (capacitive).
#################################################################################

get_variable_binary(
    ::Type{ReactivePowerVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{FixedShuntAdmittance},
) = false

get_variable_multiplier(
    ::Type{ReactivePowerVariable},
    ::Type{<:PSY.StaticInjection},
    ::Type{FixedShuntAdmittance},
) = 1.0

function _fixed_reactive_power_bounds(d::PSY.StaticInjection)
    b = _fixed_shunt_susceptance(d)
    vlims = PSY.get_voltage_limits(PSY.get_bus(d))
    vmin = vlims.min
    vmax = vlims.max
    if !isfinite(vmin) || !isfinite(vmax) || vmin <= 0.0
        error(
            "Device $(PSY.get_name(d)) bus has non-finite or non-positive voltage limits; ",
            "cannot bound ReactivePowerVariable",
        )
    end
    lo = min(b * vmin^2, b * vmax^2)
    hi = max(b * vmin^2, b * vmax^2)
    return (min = lo, max = hi)
end

function get_variable_lower_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.StaticInjection,
    ::Type{FixedShuntAdmittance},
)
    return _fixed_reactive_power_bounds(d).min
end

function get_variable_upper_bound(
    ::Type{ReactivePowerVariable},
    d::PSY.StaticInjection,
    ::Type{FixedShuntAdmittance},
)
    return _fixed_reactive_power_bounds(d).max
end

#################################################################################
# Formulation metadata
#################################################################################

requires_initialization(::AbstractShuntFormulation) = false

function get_default_attributes(
    ::Type{<:PSY.StaticInjection},
    ::Type{<:AbstractShuntFormulation},
)
    return Dict{String, Any}()
end

function get_default_time_series_names(
    ::Type{<:PSY.StaticInjection},
    ::Type{<:AbstractShuntFormulation},
)
    return Dict{Type{<:TimeSeriesParameter}, String}()
end
