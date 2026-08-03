# Optimization Container Axes

`add_variable_container!`/`add_constraints_container!`/`add_dual_container!`/`add_expression_container!`/`add_param_container!`
build a `JuMP.Containers.DenseAxisArray` (or `SparseAxisArray` when `sparse = true`) whose
dimensionality is exactly the number of axis arguments passed after the container type and
device type. **POM does not build genuinely 1D dense containers.** Every dense
variable/constraint/expression/parameter container must carry at least 2 axes, indexed
`[device_name, time_step]` for the common case. Where a quantity is conceptually 1D (a
whole-horizon budget, an end-of-horizon target, a system-wide scalar), the missing axis is
filled with an explicit **singleton placeholder** (`["horizon"]`, `[time_steps[end]]`, `[1]`,
`["System"]`, or `[service_name]`) rather than omitted — see IOM issue #15 and POM issues
#178/#180/#174 for the history: an earlier pass documented 1D containers as acceptable given
adequate test coverage and correct indexing, but that was overturned in favor of a hard
"always ≥2 axes" convention, since a genuinely 1D container silently invites exactly the class
of bug fixed below.

Two failure modes to watch for when touching any of these:

  - Indexing a container with fewer/more keys than it was created with. `DenseAxisArray`
    tolerates a trailing index of `1` (Julia's linear-indexing convention) without erroring,
    but any other extra index raises a `KeyError` — this is precisely how a 1D container
    silently drifts out of sync with 2-key indexing until it's exercised by a test with a
    non-trivial time axis. (`StorageCyclingCharge`/`StorageCyclingDischarge` shipped with
    exactly this bug — built 1D, indexed with 2 keys downstream — undetected because the
    code path had zero test coverage.)
  - Adding a new call site for one of the `ConstraintType`/`VariableType`/`ExpressionType`
    keys below without checking how the *existing* call sites index it — mirror the
    established pattern instead of guessing.

## Containers with a synthetic singleton axis (conceptually 1D, built 2D)

The 2nd (or, for the two system-wide/service-keyed cases, 1st) axis is always exactly one
element. Always indexed downstream with **both** keys — never a single key.

| Container type                                                | File                                           | Placeholder axis              | Notes                                                                                                                                                                                                                       |
|:------------------------------------------------------------- |:---------------------------------------------- |:----------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `StateofChargeTargetConstraint`                               | `energy_storage_models/storage_models.jl`      | `[time_steps[end]]`           | End-of-horizon state-of-charge target; indexed `[name, time_steps[end]]`.                                                                                                                                                   |
| `StorageCyclingCharge` / `StorageCyclingDischarge`            | `energy_storage_models/storage_models.jl`      | `[time_steps[end]]`           | Whole-horizon cycling budget; indexed `[name, time_steps[end]]`.                                                                                                                                                            |
| `EnergyBudgetConstraint` / `WaterBudgetConstraint`            | `static_injector_models/hydro_generation.jl`   | `["horizon"]`                 | Whole-horizon energy/water budget; indexed `[name, "horizon"]`. (The budget-interval variant of `EnergyBudgetConstraint` uses a real multi-element `eachindex(windows)` axis instead — not a placeholder.)                  |
| `ReservoirLevelTargetConstraint`                              | `static_injector_models/hydro_generation.jl`   | `[time_steps[end]]`           | End-of-horizon reservoir level target; indexed `[name, time_steps[end]]`.                                                                                                                                                   |
| `ImportExportBudgetConstraint` (`meta = "import"`/`"export"`) | `static_injector_models/source.jl`             | `["horizon"]`                 | Whole-horizon import/export budget; indexed `[name, "horizon"]`.                                                                                                                                                            |
| `ActiveRangeICConstraint`                                     | `static_injector_models/thermal_generation.jl` | `[1]`                         | End-of-horizon initial-condition range constraint; indexed `[name, 1]`.                                                                                                                                                     |
| `SteadyStateFrequencyDeviation` (variable + constraint)       | `services_models/agc.jl`                       | `["System"]` (1st axis)       | System-wide AGC scalar; indexed `["System", t]`. **Dead code** — `agc.jl` is not `include`d in `PowerOperationsModels.jl` (needs `_get_ace_error`), so this is unreachable today; kept consistent for when it's re-enabled. |
| `InterfaceFlowSlackUp` / `InterfaceFlowSlackDown`             | `services_models/service_slacks.jl`            | `[interface_name]` (1st axis) | One **dense** container per (slack variable type, `TransmissionInterface`), built once over all interfaces with no `meta` and filled per interface; the axis is real (interface names), indexed `[interface_name, t]`.      |

Also already-2D-by-construction, kept here for completeness (2nd axis is a true singleton but
was never a bare 1D container — no fix needed, just easy to misread as one):

| Container type                                                               | File                                         | 2nd-axis expression                                 | Notes                                                                                                                    |
|:---------------------------------------------------------------------------- |:-------------------------------------------- |:--------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------ |
| `StorageEnergyShortageVariable` / `StorageEnergySurplusVariable`             | `energy_storage_models/storage_models.jl`    | `last_time_range = time_steps[end]:time_steps[end]` | End-of-horizon energy-target slack variables.                                                                            |
| `StorageChargeCyclingSlackVariable` / `StorageDischargeCyclingSlackVariable` | `energy_storage_models/storage_models.jl`    | `last_time_range = time_steps[end]:time_steps[end]` | End-of-horizon cycling slack variables (paired with `StorageCyclingCharge`/`StorageCyclingDischarge` above).             |
| `HybridEnergyShortageVariable` / `HybridEnergySurplusVariable`               | `hybrid_system_models/hybrid_systems.jl`     | `last_time_range = time_steps[end]:time_steps[end]` | Mirrors the storage slack variables above, keyed by `HybridSystem`.                                                      |
| `EnergyTargetConstraint`                                                     | `static_injector_models/hydro_generation.jl` | `[time_steps[end]]`                                 | End-of-horizon reservoir energy target.                                                                                  |
| `WaterTargetConstraint`                                                      | `static_injector_models/hydro_generation.jl` | `[time_steps[end]]`                                 | End-of-horizon reservoir water target.                                                                                   |
| `HydroUsageLimitParameter`                                                   | `static_injector_models/hydro_generation.jl` | `[time_steps[end]]`                                 | Parameter container for an aux-variable value; explicitly commented in-code as "a single column".                        |
| `ShiftedActivePowerBalanceConstraint` (default `meta`)                       | `static_injector_models/electric_loads.jl`   | `[time_steps[end]]`                                 | Explicitly commented in-code: "Keep this container 2D (name, terminal-time marker) to match standard indexing patterns." |

**Not a singleton — don't misclassify:** `ShiftedActivePowerBalanceConstraint` built with
`meta = "additional"` (same file, `electric_loads.jl`) looks similar (`interval_end_steps`
as the 2nd axis) but is **not** a true singleton — its length depends on the device model's
`additional_balance_interval` attribute and can hold one column per sub-interval of the
horizon, not just the final one. It's still always 2D and indexed `container[name, t]` in a
loop, so no bug there; it just isn't part of the "always exactly one column" family above.

## 3D containers

| Container type                                                              | File                                           | Notes                                                                                                                          |
|:--------------------------------------------------------------------------- |:---------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------ |
| `HydroTurbineFlowRateVariable`                                              | `static_injector_models/hydro_generation.jl`   | Indexed `[turbine_name, reservoir_name, time_step]` — flow rate depends on both the turbine and which reservoir it draws from. |
| `StartupInitialConditionConstraint` (`meta = "ub"`/`"lb"`, `sparse = true`) | `static_injector_models/thermal_generation.jl` | `SparseAxisArray` indexed `[name, time_step, start_stage]`.                                                                    |

Everything else built via `add_*_container!` is 2D `[device_name, time_step]`, including the
practically-1D singleton-second-axis containers above — they're still 2 axes and follow the
normal `container[name, t]` indexing pattern.

### MarketBidCost PWL block-offer variables: a 3D container that bypasses `add_*_container!`

Time-varying offer-curve costs (`MarketBidCost`, `ImportExportCost`, and the
`ReserveDemandCurve`/ORDC service cost) use a genuinely 3D structure — `(device_name, pwl_segment_index, time_step)` — but it is **not** built via the `add_*_container!` +
`Vararg` axes mechanism documented above. It's a `SparseAxisArray{JuMP.VariableRef}` keyed
by `Tuple{String, Int, Int}`, constructed as empty and populated per-`(name, t)` by IOM.

### Merged service (reserve) containers, keyed by service type

Service models are registered **per type** — `set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))`, no service name, exactly like
`set_device_model!`. `construct_service!` runs once per type: it iterates the type's
services (`get_available_components(model, sys)`) and reads each service's contributing
devices from the model's per-service `contributing_devices_map`. Reserve entries no longer
disambiguate services with `meta = service_name`; all services of a given `(entry type, service type)` share one container, with the service name as an axis value. Density follows
whether the entry depends on the contributing-device axis:

  - **Device-indexed entries** (depend on contributing devices) — `ActivePowerReserveVariable`,
    `ParticipationFractionConstraint`, `RampConstraint`, `ReservePowerConstraint` — are one
    `SparseAxisArray` keyed `(service_name, device_name, time_step)` (empty `meta`). Sparse
    because each service's contributing-device set is ragged. Filled per service via
    `lazy_container_addition!(...; sparse = true)`; indexed `container[(service_name, device_name, t)]`.
  - **Service-indexed entries** (no dependence on contributing devices) —
    `RequirementConstraint`, `ReserveRequirementSlack`, `ServiceRequirementVariable`, and the
    `RequirementTimeSeriesParameter` — are one **dense** container per service type keyed
    `(service_name, time_step)` (empty `meta`), built once over all the type's services
    (reusing the same dense component builders devices use) and filled per service; indexed
    `container[service_name, t]`. `use_slacks` is per type: `ReserveRequirementSlack` is built
    over all the type's services when the type uses slacks, and omitted otherwise.

The service duals mirror the merged constraint containers. Results flatten leading
dimensions to encoded columns, e.g. `ActivePowerReserveVariable__<ServiceType>` with
`"service_name__device_name"` columns (WIDE) — mirroring the PWL block-offer flattening
above. The transmission-interface flow-limit parameters and slacks and the ORDC
(`StepwiseCostReserve`) piecewise cost parameters are likewise merged **dense** per-type
containers with empty `meta`, built once over all the type's services/interfaces. The
storage/hybrid reserve sub-containers are the remaining `meta`-keyed service containers.
