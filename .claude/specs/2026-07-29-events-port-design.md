# Events feature port: PSI → POM — design spec

Date: 2026-07-29.
Status: approved design, pending implementation plan.

## Goal

Port the time-series/stochastic outage **events** feature from PowerSimulations.jl (PSI) into PowerOperationsModels.jl (POM), as part of the psy6 work.
POM gains everything portable: the full model-build machinery plus the container types.
The simulation runtime stays in PSI.
InfrastructureOptimizationModels.jl (IOM) requires **one small type-bound correction** (see the package split below); the rest of its domain-neutral scaffolding is consumed as-is.

## Disambiguation (load-bearing)

PSI has two unrelated features sharing "contingency"/"outage" vocabulary:

- **Feature A — outage events** (this spec): `EventModel`, `PSY.FixedForcedOutage` / `PSY.GeometricDistributionForcedOutage` supplemental attributes, availability/countdown/offset parameters, upper-bound outage constraints.
  In PSI this lives, confusingly, in `src/contingency_model/`.
- **Feature B — N-1 security-constrained (MODF)**: `DeviceModel.outages`, `supports_outages` formulation trait, post-contingency flow machinery.
  Already ported to POM.
  This spec does not touch it, and deliberately avoids colliding with it.

## Decisions (settled during brainstorming)

1. **Port, not migrate**: PSI `main` stays untouched; POM gains adapted code. PSI adopting POM/IOM is a separate future effort.
2. **POM scope = build + container types** (layers 1+2). Runtime projection (layer 3) stays PSI-only until a state abstraction exists in IOM/POM.
3. **Template-level attachment API** with build-time auto-discovery, mirroring Feature B's outage discovery pattern.
4. **Cleaned-up port** (approach B): fix PSI's known warts at the boundary instead of copying them.
5. **Hydro and storage are in scope**: POM owns those constructors in-repo (PSI does not), so the event methods from HydroPowerSimulations.jl (HPS) and StorageSystemsSimulations.jl (SSS) `src/contingency_model.jl` fold in, with their `test_events.jl` suites as reference behavior.

## Package split

### IOM — one type-bound correction (verified 2026-07-30)

Already present on `main` and consumed as-is:
`AbstractEventModel`, `AbstractEventKey` (`src/core/device_model.jl`), the `DeviceModel.events::Dict{AbstractEventKey, AbstractEventModel}` field, `set_event_model!(::DeviceModel, ...)`, `get_events`, `EventParameter`, and the `add_param_container!` overload for event parameters.

**Required fix:** the contingency slot of the event parameter machinery is bounded on the wrong IS hierarchy.
`PSY.Contingency <: SupplementalAttribute <: IS.InfrastructureSystemsType`, which is **not** under `IS.InfrastructureSystemsComponent` — but IOM bounds that slot as `IS.InfrastructureSystemsComponent` in `EventParametersAttributes` (`src/core/parameter_container.jl:83-101`) and in the `add_param_container!` event overload (`src/common_models/add_param_container.jl:96`).
Any real call with a contingency type (e.g. `PSY.FixedForcedOutage`) is a MethodError today; the scaffolding has never been exercised downstream.
Fix in IOM (domain-neutral — `IS.SupplementalAttribute` is an IS abstraction): change the bound to `T <: IS.SupplementalAttribute` / `V <: IS.SupplementalAttribute` in both files, and drop the `affected_devices::Vector{T}` field (it has zero readers in IOM; with the corrected bound its name no longer matches its type).
Local clone for this work: `/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl` (branch `mb/events-port`).
POM pins IOM to the floating `main` branch, so no POM pin change is needed — but the IOM PR must merge to `main` before POM CI can build events; local development bridges the gap with a Manifest-only `Pkg.develop` of the clone.

### POM — gains the portable feature

- New `src/event_models/` directory (build machinery + container types).
- New parameter/constraint types in `src/core/`.
- `events` field + `set_event_model!` on `PowerOperationsProblemTemplate`.
- Discovery/distribution/validation pass in `operation/template_validation.jl`.
- `add_event_arguments!` / `add_event_constraints!` call sites in the static-injector and storage constructors.

### PSI — untouched

Runtime stays: condition evaluation against `SimulationState`, Bernoulli sampling (`SimulationInternal.rng`), `apply_simulation_events!`, `update_decision_state!` / `update_system_state!` event methods, countdown-first parameter-update ordering, the feedforward `has_outage` override, `SimulationSequence(events = ...)` attachment.

### Out of scope

- Runtime parameter updates between solves (no IOM/POM state abstraction exists yet).
- Feature B (already in POM).
- Simulation orchestration of any kind (standing POM rule).

## POM type design and layout

New directory `src/event_models/` (name kills PSI's `contingency_model/` misnomer):

### `event_keys.jl`

`EventKey{T <: PSY.Contingency, U <: PSY.Component} <: IOM.AbstractEventKey` with `meta::String`; errors on abstract `U`.
Accessors `get_entry_type`, `get_component_type`.
Same shape as PSI's (`PSI/src/core/event_keys.jl`), subtyped under IOM's abstract.

### `event_model.jl`

`EventModel{D <: PSY.Contingency, B <: AbstractEventCondition} <: IOM.AbstractEventModel`.
Fields: `condition::B`, `timeseries_mapping::Dict{Symbol, Union{String, Nothing}}`, `attribute_device_map::Dict{Base.UUID, Dict{DataType, Set{String}}}`, `attributes::Dict{String, Any}`.
Change from PSI: the map **drops the per-simulation-model outer key** (`Dict{Symbol, ...}` in PSI) — POM builds one model at a time; the model-name dimension is runtime bookkeeping PSI keeps.
Reserved `timeseries_mapping` keys per contingency type (hardcoded, as in PSI `get_empty_timeseries_mapping`): `:outage_status` for `FixedForcedOutage`; `:mean_time_to_recovery`, `:outage_transition_probability` for `GeometricDistributionForcedOutage`.
Condition types, data-only structs under `AbstractEventCondition`: `ContinuousCondition`, `PresetTimeCondition`, `StateVariableValueCondition`, `DiscreteEventCondition`.
POM stores conditions but never evaluates them; evaluation is runtime and stays PSI-side.

### `event_traits.jl`

Injector-level capability trait **renamed to `supports_events(::Type{<:PSY.Component})`** (PSI calls it `supports_outages`, which collides with POM's existing Feature-B *formulation* trait).
Allow-list: `ThermalStandard`, `RenewableGen`, `ElectricLoad`, `HydroGen`, `Storage`; default `false` for `StaticInjection`.
Parameter defaults: `get_parameter_multiplier(::EventParameter, ...) = 1.0`; `get_initial_parameter_value` — `AvailableStatusParameter` → 1.0, countdown/offsets → 0.0.

### `event_arguments.jl`

The `add_event_arguments!` family, ported from `PSI/src/contingency_model/contingency_arguments.jl`:
generic `StaticInjection`, plus load and `FixedOutput` variants, each × active-power-only / full-AC network.
The event `_add_parameters!` path building parameter containers via IOM's `EventParameter` overload of `add_param_container!`.
The `add_to_expression!` methods injecting `ActivePowerOffsetParameter` / `ReactivePowerOffsetParameter` into `ActivePowerBalance` / `ReactivePowerBalance`, one method per network family — **retargeted from PowerModels abstracts to POM's native network formulation types** (`CopperPlateNetworkModel`, PTDF, `AreaBalanceNetworkModel`, generic AC abstract).
These methods live here, not in `common_models/add_to_expression.jl` (isolation from the concurrent transformer refactor; see Concurrency).

### `event_constraints.jl`

The `add_event_constraints!` family, ported from `PSI/src/contingency_model/contingency_constraints.jl`:
`ActivePowerOutageConstraint` via `add_parameterized_upper_bound_range_constraints` with `AvailableStatusParameter`; LHS per family (`ActivePowerRangeExpressionUB` for thermal/hydro, service-model-dependent expression for renewables, `ActivePowerVariable` for loads).
Quadratic `ReactivePowerOutageConstraint` (`q² <= ub · status`) with the reactive-upper-bound helpers, for full-AC networks.
Hydro methods absorbed from HPS `src/contingency_model.jl`; storage methods (including the charge/discharge input-output constraint builder and the storage reactive constraint) absorbed from SSS `src/contingency_model.jl`.

### Type registrations in `src/core/` — already present (verified 2026-07-29)

All four parameter types exist (`src/core/parameters.jl:208-223`): `AvailableStatusParameter`, `ActivePowerOffsetParameter`, `ReactivePowerOffsetParameter`, `AvailableStatusChangeCountdownParameter`, all `<: IOM.EventParameter`, with `should_write_resulting_value = true`.
All constraint types exist (`src/core/constraints.jl:631-633, 881`): `EventConstraint <: ConstraintType`, `ActivePowerOutageConstraint`, `ReactivePowerOutageConstraint`, and `ActivePowerPumpOutageConstraint` (hydro pump — relevant to the HPS port).
None are exported and none have consumers yet; the port adds exports and consumers, not the types.
`.claude/pom_port_plan.md`'s note that "only the `AvailableStatusParameter` type exists" is stale — correct it when updating the plan.
All new code uses `PSY.Contingency` bounds uniformly (PSI mixes `PSY.Outage` and `PSY.Contingency`; the cleaned-up port does not).

### Template integration

`PowerOperationsProblemTemplate` (POM-owned, `src/core/problem_template.jl`) gains `events::Vector{EventModel}`.
API: `set_event_model!(template, event_model)`, `get_event_models(template)`.

### Exports

`EventModel`, `EventKey`, `AbstractEventCondition` + the four condition types, the four parameter types, the two constraint types, `set_event_model!`, `supports_events`.
All exported symbols get docstrings and API-page registration (docs build is a gate).
Include order in `src/PowerOperationsModels.jl`: key/type files before `event_models/` consumers, `event_models/` before the constructors that call into it.

## Attachment, discovery, and build flow

### User flow

```julia
event = EventModel(PSY.FixedForcedOutage, ContinuousCondition;
                   timeseries_mapping = Dict(:outage_status => "outage_profile_1"))
set_event_model!(template, event)
model = DecisionModel(template, sys)
build!(model)
```

### Discovery and distribution (build-time)

A new `_build_device_model_events!(template, system)` in `operation/template_validation.jl`, running alongside the existing `_build_device_model_outages!` (Feature B).
It operates on the build copy of the template, so nothing leaks back to the caller's `DeviceModel`s — the same isolation Feature B guarantees (PSI regression: `test_problem_template.jl`).
For each event model on the template:

1. Collect the system's supplemental attributes of the event's contingency type; **error loudly if none exist** (PSI behavior and POM's no-silent-skip rule).
2. For each attribute, resolve attached devices, group names by concrete device type; keep only types passing `supports_events` that have a `DeviceModel` in the template; populate `event_model.attribute_device_map[uuid][device_type]`.
3. Call IOM's `set_event_model!(device_model, EventKey(contingency_type, device_type), event_model)` on each matching `DeviceModel`.

### Time-series validation

Ported from PSI `_validate_event_timeseries_data` (`simulation_sequence.jl:215-249`), run in the same pass:
every mapped name must resolve to a `SingleTimeSeries` **on the supplemental attribute** (not the device);
mapping keys must be in the reserved set for the contingency type;
`FixedForcedOutage` requires a non-nothing `:outage_status`.

### Build stages

POM's two-stage convention.
`ArgumentConstructStage`: constructors call `add_event_arguments!` unconditionally; it no-ops when the `DeviceModel.events` dict is empty (PSI's pattern).
It creates the availability/countdown/offset parameter containers and seeds initial values and multipliers; offset parameters are injected into balance expressions before constraints consume them (`add_expressions!` before `add_constraints!` invariant).
`ModelConstructStage`: `add_event_constraints!` adds the outage upper-bound constraints, and the quadratic reactive constraint under AC networks.
Inside `add_event_*`, devices are filtered by `PSY.has_supplemental_attributes(d, event_type)`; an empty result **errors** (never silently skips).
Sparse event-parameter containers remain a hard error (PSI behavior).

Constructor call sites (both stages):
`thermalgeneration_constructor.jl`, `renewablegeneration_constructor.jl`, `load_constructor.jl`, `source_constructor.jl` (args only, as PSI), `hydrogeneration_constructor.jl`, `energy_storage_models/storage_constructor.jl`, plus the `FixedOutput` paths (args only, no constraints).
PSI's per-formulation coverage (which formulations get which calls) is the reference; hydro/storage coverage follows HPS/SSS.

### psy6 adaptations (do not copy PSI verbatim)

- Every PSY getter on a convertible field passes `PSY.SU` explicitly (reactive-power upper-bound helpers, active-power limits — the ported PSI code predates the stateless-units rework).
- Network dispatch on POM's native network formulation types, not `PM.Abstract*PowerModel`.
- Supplemental-attributes accessor surface verified against psy6 PSY during implementation (`has_supplemental_attributes`, `get_supplemental_attributes`, `get_supplemental_attribute`, `get_components(sys, event)`, attribute-attached `get_time_series`); the attribute types exist in `PSY/src/outages.jl`.
- `Test.detect_ambiguities` after adding the overlapping `add_event_*` signatures (generic `StaticInjection` vs load/`FixedOutput` specializations).

### Initial conditions

Events are **excluded** from the initial-conditions template.
PSI encodes this as an omission plus a comment (`initial_conditions/initialization.jl:31`); POM documents it at the IC-template construction site and tests it.

## Testing

Test scope is build-level; POM has no `Simulation`.
PSI `test/test_events.jl` (13 testsets), HPS `test/test_events.jl`, and SSS `test/test_events.jl` are **reference behavior** (which formulations are event-aware, what gets created, forced-zero semantics), not portable code — they require simulation runtime.

### `test/test_events.jl` (new)

- Template attachment + discovery: `attribute_device_map` contents against a PSB fixture with attributes attached; loud error when no supplemental attributes exist; unknown `timeseries_mapping` keys rejected; missing `:outage_status` for `FixedForcedOutage` rejected; events excluded from the IC template; build-copy isolation (no leak to caller's `DeviceModel`s).
- Build assertions per device family: parameter containers exist with correct axes and initial values (status 1.0, countdown/offsets 0.0); `ActivePowerOutageConstraint` present with coefficient-level checks against hand-computed references (MODF-suite pattern); quadratic `ReactivePowerOutageConstraint` under AC; offset parameters appear in balance expressions for load/`FixedOutput`.
- Forced-outage build variant: a model built with the status parameter at 0 solves with zero output for the affected device.

### Constructor tests

Extend the existing per-formulation constructor tests with an `add_event_model = true` path, ported from PSI's `mock_construct_device!` but going through the real `set_event_model!` API (PSI's mock assigns the `events` field directly).
Assert variable/constraint/parameter counts for: thermal (UC + dispatch variants), renewable, loads (static/dispatch/interruption), `FixedOutput`, source, hydro, storage — the last two validated against HPS/SSS expectations.

### Coverage matrix and hygiene

Device families × network formulations: CopperPlate, PTDF, native DCP, native ACP (reactive path).
Helpers that attach attributes + `SingleTimeSeries` to PSB systems go in `test/test_utils/` (adapted from the build-relevant parts of PSI `test/test_utils/events_simulation_utils.jl`; PSI's file is not modified — HPS/SSS consume it).
Build warnings assert via `operation_problem.log`, not `@test_logs`.
`Test.detect_ambiguities` gate.

## Documentation

Docstrings on all exported symbols; API-page registration; docs must build.
A short formulation-docs entry for the event parameters/constraints, matching existing POM formulation docs.

## Concurrency and sequencing with the transformer-refactor work path

Concurrent plans: `.claude/plans/2026-07-26-transformer-refactor.md` (POM, HELD behind Task 0), `.claude/plans/2026-07-27-pnm-pf-prerequisites.md` (PNM/PF), `.claude/plans/2026-07-27-psy6-integration-roadmap.md` (stage overview).

### File-level overlap: small and append-only

The events port is mostly new files plus injector/storage constructor call sites; the transformer refactor lives in the branch/network layer.
Shared files and risk:

| File | Transformer plan | Events port | Risk |
|---|---|---|---|
| `src/PowerOperationsModels.jl` | includes/exports | includes/exports | textual only |
| `src/core/constraints.jl` | adds types | no additions needed (event constraint types already present) | none |
| `src/operation/template_validation.jl` | Task 8 edits Feature-B outage discovery | adds separate `_build_device_model_events!` | low; keep the events pass self-contained |
| thermal constructor tests, docs API page | light touches | extends | textual only |

Semantic isolation is by construction: `supports_events` never touches Feature B's `supports_outages` (Task 8's territory); event `add_to_expression!` methods live in `src/event_models/`, not `common_models/add_to_expression.jl` (which the transformer plan modifies); events dispatch on abstract network formulations, indifferent to transformer geometry internals.

### The load-restoration gate (the real constraint)

POM's `[sources]` pin upstream packages to floating branch refs with no committed Manifest, so every fresh resolve pulls branch tips.
PSY's transformer refactor (#1714, merged 2026-07-26 into `psy6`) deleted/renamed types POM references in top-level method signatures (`PhaseShiftingTransformer`, `TapTransformer`, `Transformer2W`, `Transformer3W`, and getters).
Consequently `using PowerOperationsModels` fails at load on fresh resolves (recorded baseline: `UndefVarError: PhaseShiftingTransformer` at `add_to_expression.jl:1912`).
Nothing can be compiled, built, or tested in CI until that is fixed.
Local environments holding a pre-#1714 Manifest resolve still work, but that state is not CI-reproducible.

The fix is the front slice of the transformer plan:
**Task 0** (hard gate: verify PNM prerequisites shipped, choose the PowerFlows ref — interim `psy6-rebase` pin — and pull the tips) and
**Task 1** (delete dead transformer-control formulations, sweep all stale type references incl. `PowerFlowsExt`; exit gate: POM loads with the extension and the stale-symbol grep is zero).

Load is not green: Tasks 2–9 restore suite correctness, and transformer-touching tests (and PSB fixtures containing transformers, e.g. `c_sys14`) stay red in between.
An events PR runs the full suite in CI, so **merging events to a green main queues behind transformer-plan completion (Task 9's final gate), not just Task 1**.

### Schedule

1. **Now**: author the events port on its own branch — zero dependency on transformer-plan APIs; PSY's outage types and IOM's scaffolding are on current pins.
   The IOM type-bound fix is authored in parallel in the local IOM clone and bridged into POM's test env via Manifest-only `Pkg.develop` until it merges to IOM `main`.
2. **After transformer Task 1**: rebase; run events tests locally (build-level tests on non-transformer fixtures such as `c_sys5` should pass).
3. **After transformer Task 9 and the IOM PR merging to `main`**: full-suite CI green achievable; merge events; whichever branch merges second rebases over append-only conflicts.

Discipline: the events branch makes **no `Project.toml`/pin changes** (it needs none); all env churn is owned by transformer Task 0.
Temporarily pinning PSY to a pre-#1714 SHA to merge events first is rejected: it violates the no-mid-project-pin-churn rule and forks the baseline the transformer plan builds against.

## Done criteria

- Formatter clean; full suite green (`--jobs=8`); docs build.
- `Test.detect_ambiguities` clean.
- `.claude/pom_port_plan.md` Workstream C event item updated to reflect what landed (including hydro/storage coverage beyond the original PSI-parity scope).

## Reference inventory (for the implementation plan)

- PSI: `src/core/event_keys.jl`, `src/core/event_model.jl`, `src/contingency_model/{contingency,contingency_arguments,contingency_constraints}.jl`, `src/core/parameters.jl:79-88, 582-605`, `src/core/constraints.jl:596-598`, `src/core/optimization_container.jl:1314-1340, 1478-1490`, `src/parameters/add_parameters.jl:36-54`, constructor call sites in `src/devices_models/device_constructors/{thermalgeneration,load,renewablegeneration,source}_constructor.jl`, `src/simulation/simulation_sequence.jl:201-316` (discovery/validation logic to re-host at template level).
- HPS: `src/contingency_model.jl`, `test/test_events.jl`.
- SSS: `src/contingency_model.jl`, `test/test_utils/events.jl`, `test/test_events.jl`.
- IOM (consumed, plus the type-bound fix above): `src/core/device_model.jl` (abstracts, `events` field, `set_event_model!`), `EventParameter` / `EventParametersAttributes`, `add_param_container!` overload; fix sites `src/core/parameter_container.jl:83-101` and `src/common_models/add_param_container.jl:85-103`; local clone at `/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl` (branch `mb/events-port`).
- PSY psy6: `src/outages.jl` (`Outage <: Contingency`, `FixedForcedOutage`, `GeometricDistributionForcedOutage`, `PlannedOutage`, monitored-components API).
