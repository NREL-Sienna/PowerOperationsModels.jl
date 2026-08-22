# Marker singleton trait types used to parametrize hybrid/storage reserve variable,
# expression, and constraint families. These eliminate the need for paired sibling
# singletons across the codebase: a single parametric struct is used instead of
# every (Charge/Discharge) and (Unscaled/Deployed) sibling pair.

"""
Trait axis selecting how a reserve contribution is scaled into an aggregation:
[`UnscaledReserve`](@ref) (raw multiplier) or [`DeployedReserve`](@ref) (scaled by
`deployed_fraction`).
"""
abstract type ReserveScale end
"Reserve aggregation that uses the raw multiplier (1.0)."
struct UnscaledReserve <: ReserveScale end
"Reserve aggregation that scales the multiplier by `deployed_fraction`."
struct DeployedReserve <: ReserveScale end

"""
Trait axis selecting which side of a storage device or hybrid PCC a reserve variable acts
on: [`DischargeSide`](@ref) (outflow) or [`ChargeSide`](@ref) (inflow).
"""
abstract type ReserveSide end
"Discharge / outflow side of a storage or hybrid PCC."
struct DischargeSide <: ReserveSide end
"Charge / inflow side of a storage or hybrid PCC."
struct ChargeSide <: ReserveSide end

# ── Reserve-type predicate helpers ────────────────────────────────────────────────────
# The reserve tree distinguishes reserves by state (direction parameter, demand curve,
# attached series) rather than by struct type; these centralize that branch logic in one
# dispatch-based place (no `isa`).

"""
Direction of a reserve. `OfflineReserve` (non-spinning) has no direction type parameter and is
upward-only in every US market, so it maps to `PSY.ReserveUp`.
"""
_reserve_direction(::PSY.Reserve{T}) where {T <: PSY.ReserveDirection} = T
_reserve_direction(::PSY.OfflineReserve) = PSY.ReserveUp

"""
Upward reserve products a device can supply: up-direction reserves plus `OfflineReserve`
(non-spinning is upward-only). Excludes `GroupReserve` - devices serve a group's members,
never the group itself.
"""
const UP_RESERVE = Union{PSY.Reserve{PSY.ReserveUp}, PSY.OfflineReserve}

"Whether a reserve is non-spinning: `OfflineReserve` vs everything else under `AbstractReserve`."
_is_offline(::PSY.OfflineReserve) = true
_is_offline(::PSY.AbstractReserve) = false

"""
Whether a reserve's `requirement` is scaled by an attached requirement time series.

Resolves the series name from the `ServiceModel`'s `time_series_names` (a user can override the
name there), and deliberately does not pin the series' concrete `TimeSeriesData` type
(`Deterministic` in recurrent solves, `SingleTimeSeries` otherwise). Returns `false` when the
model declares no requirement series name (the formulation carries no requirement parameter).
"""
function _has_ts_requirement(model::ServiceModel, s::PSY.AbstractReserve)
    ts_names = get_time_series_names(model)
    haskey(ts_names, RequirementTimeSeriesParameter) || return false
    return PSY.has_time_series(s, ts_names[RequirementTimeSeriesParameter])
end

# ── ORDC (operating-reserve-demand-curve) predicates ─────────────────────────────────
# A demand curve lives on a reserve's `variable` field ("is this an ORDC" is
# `PSY.has_demand_curve`), so "static vs time-varying" is a runtime inspection of the curve
# (union-splits cleanly over the two `variable` members; reserves are few and read at build,
# so the cost is negligible).

"Whether a reserve's or group's ORDC curve is time-varying. Dispatches on the value-curve type (no `isa`)."
_ordc_is_ts(s::PSY.AbstractReserve) =
    _value_curve_is_ts(PSY.get_value_curve(PSY.get_variable(s)))
_value_curve_is_ts(::PSY.TimeSeriesPiecewiseIncrementalCurve) = true
_value_curve_is_ts(::PSY.PiecewiseIncrementalCurve) = false

"""
Meta string identifying one service inside the device-side reserve containers
(ancillary-service variables, `TotalReserveOffering` expressions, coverage constraints).
Always derive it from the service INSTANCE: a `ServiceModel`'s type parameter can be
partially applied (`OnlineReserve{ReserveUp}`, a `UnionAll`) while the containers are
written with the fully concrete instance type, and the two spellings do not match.
"""
_service_container_meta(service::PSY.Service) =
    "$(typeof(service))_$(PSY.get_name(service))"

"""
Whether a reserve type is an offline (non-spinning) product. Trait form of the
`OfflineReserve` check used by the offline-capability machinery.
"""
_is_offline_reserve(::Type{<:PSY.AbstractReserve}) = false
_is_offline_reserve(::Type{<:PSY.OfflineReserve}) = true

"""
Whether a device formulation folds offline-reserve awards into the commitment-gated range
expression (`ActivePowerRangeExpressionUB`). Defaults to `true` (the award consumes gated
headroom, so an OFF unit cannot supply). Commitment formulations that provide offline
capability through [`OfflineReserveBandConstraint`](@ref) return `false`.
"""
offline_reserve_in_range_ub(::Type{<:AbstractDeviceFormulation}) = true

"""
Whether a `DeviceModel` carries an `OfflineReserve` service. Gates the
[`OfflineReserveBandConstraint`](@ref) so that models without offline reserves build
exactly the classic single semi-continuous band row.
"""
_has_offline_reserve_service(model::DeviceModel) =
    has_service_model(model) &&
    any(sm -> _is_offline_reserve(get_component_type(sm)), get_services(model))
