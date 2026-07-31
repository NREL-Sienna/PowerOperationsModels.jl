"""
Formulation type to enable basic dispatch without any intertemporal (ramp) constraints
"""
struct ThermalBasicDispatch <: AbstractThermalDispatchFormulation end

# `ThermalBasicDispatch` defines no behavior of its own: every method that applies to it
# is dispatched on `AbstractThermalDispatchFormulation` or a broader thermal abstract in
# `common/`.
