"""
Formulation type to enable standard unit commitment with intertemporal constraints and simplified startup profiles
"""
struct ThermalStandardUnitCommitment <: AbstractStandardUnitCommitment end

# `ThermalStandardUnitCommitment` defines no behavior of its own: every method that
# applies to it is dispatched on `AbstractStandardUnitCommitment` or a broader thermal
# abstract in `common/`.
