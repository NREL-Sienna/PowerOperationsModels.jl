# PowerOperationsModels.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in the `sienna-psy6` skill — invoke it. This file is repo-specific and does not restate them.

## Purpose & place in the stack

POM is the **collection of operational optimization models for power systems**: the concrete device, service, and network formulations plus the `PowerOperationModel` problem-type chain. It builds JuMP models from PowerSystems components.

Abstraction hierarchy (low → high level of generality):

- **InfrastructureSystems (IS)** — domain-agnostic base: optimization key types (`VariableKey`, `ConstraintKey`, …), time series, generic component abstractions. (`InfrastructureSystems.Optimization` = `ISOPT`.)
- **InfrastructureOptimizationModels (IOM)** — domain-neutral optimization infrastructure: `OptimizationContainer`, `DeviceModel{D,F}` / `ServiceModel{S,F}` / `NetworkModel{N}`, `ProblemTemplate`, `DecisionModel{M}` / `EmulationModel{M}` (parameterized over the single abstract tag `IOM.AbstractOptimizationProblem`), both stores, settings, the generic `add_*!` builders, objective/initial-condition infra. Reusable beyond power systems.
- **POM (this repo)** — the "what": device formulations (`ThermalBasicUnitCommitment`, `RenewableFullDispatch`, `StaticBranch`, storage, HVDC, …), variable/constraint/expression/parameter types, network formulations, service models, and the concrete problem taxonomy.

PSI (the old PowerSimulations.jl) ≈ POM + IOM. Many ports into POM originate from PSI PRs.

IS and IOM are **external package dependencies** (resolved via `Project.toml`/`[sources]`), not subdirectories.

### The IOM/POM split (PR #104 "Redistribute operation models")

IOM was made domain-neutral. The power-flavoured taxonomy was **moved out of IOM into POM** (`src/core/problem_types.jl`):

- POM owns `PowerOperationModel <: IOM.AbstractOptimizationProblem`, then `DecisionProblem`/`EmulationProblem`, `DefaultDecisionProblem`/`DefaultEmulationProblem`, `GenericOpProblem`/`GenericEmulationProblem`. POM dispatches on `DecisionModel{<:PowerOperationModel}` etc. The no-type-param `DecisionModel(template, sys)` default + the EmulationModel update chain live in POM (`src/operation/`).
- IOM removed `OperationModel`, `DecisionProblem`, `EmulationProblem`, the `Generic*`/`Default*` problem types, and the `Simulation*` stubs. The old `OperationModel` abstract → `IOM.AbstractOptimizationModel`. `validate_time_series!` / `validate_template` are stubs on the neutral abstract.
- **Gotcha:** when a symbol seems "not defined in IOM", check whether #104 moved it to POM — define/dispatch on the POM chain, do **not** re-add it to IOM.

## Optimization Model Construction Conventions

### `add_*!()` methods must not return collections
Methods that create variables, constraints, or expressions (`add_variables!`, `add_constraints!`, `add_expressions!`, etc.) must always end with a bare `return` (i.e., return `nothing`). They must never return dicts or collections of JuMP objects. Instead, instantiate the appropriate container via `add_*_container!` and store all created objects there.

### Inline expressions when possible
Expression construction should be inlined at the point of use. Only store an expression in a container when it is intended to be reused across multiple constraints or objective terms. Avoid creating expression containers solely as intermediate computation steps.

## Device construction: two-stage `construct_device!`

Every device/service/network formulation implements `construct_device!` (or `construct_service!` / `construct_network!`) for **two** dispatch stages:

- `ArgumentConstructStage` — add variables, parameters, expressions, feedforward arguments.
- `ModelConstructStage` — add constraints, feedforward constraints, objective terms, constraint duals.

`add_expressions!` must run before `add_constraints!` that consume those expressions. Not all device formulations are compatible with all network models — check existing method signatures before adding a new pair.

## Source layout — the non-obvious parts

`src/` is organized by device family (`static_injector_models/`, `energy_storage_models/`,
`ac_transmission_models/`, `twoterminal_hvdc_models/`, `mt_hvdc_models/`, `hybrid_system_models/`,
`services_models/`, `network_models/`), each pairing a model file with a `*_constructor.jl`. `core/`
holds type definitions only; `common_models/` the shared builders; `operation/` the build and model
drivers. What you can't see from `ls`:

- `core/problem_types.jl` — the `PowerOperationModel` chain, moved out of IOM by PR #104.
- `core/interfaces.jl` — includes `PowerFlowEvaluator`, which wraps PF models.
- `services_models/agc.jl` is **not included** in the module (TODO: needs `_get_ace_error`).
- `ext/PowerFlowsExt/` — the PowerFlows.jl weakdep extension. Code must work when PF is not loaded.
- Native network formulations are `*NetworkModel` structs in `core/network_formulations.jl`
  (`DCPNetworkModel`, `ACPNetworkModel`, `ACRNetworkModel`, `IVRNetworkModel`, `LPACCNetworkModel`,
  `NFANetworkModel`, `DCPLLNetworkModel`, plus `CopperPlateNetworkModel` /
  `AreaBalanceNetworkModel` / `PTDFNetworkModel`) — built directly against JuMP with **no
  PowerModels.jl dependency**, despite the familiar names.

## Imports / aliases

POM uses `import X as Y` and `const Y = X` aliases declared **in the main module** — do not introduce per-file aliases. Canonical: `IS = InfrastructureSystems`, `ISOPT = InfrastructureSystems.Optimization`, `PSY = PowerSystems`, `PNM = PowerNetworkMatrices`, `IOM = InfrastructureOptimizationModels`. In the extension: `IOM`, `PFS = PowerFlows`. POM re-exports `PTDF`/`VirtualPTDF` from PNM. Native `DCPNetworkModel`/`ACPNetworkModel` are **POM structs** in `core/network_formulations.jl`, not PowerModels re-exports.

## Commands (verified)

All Julia invocations use `--project=test` (deps live in `test/Project.toml`); never bare `julia`/`--project`.

```sh
# Full test suite (ParallelTestRunner: each top-level test_*.jl runs in its own Malt worker)
julia --project=test test/runtests.jl
# Filter by file name (startswith), cap parallelism, or list:
julia --project=test test/runtests.jl test_model_decision
julia --project=test test/runtests.jl --jobs=8
julia --project=test test/runtests.jl --list
# Run one test file directly (loads shared preamble first):
julia --project=test -e 'include("test/includes.jl"); include("test/test_native_dcp_acp_models.jl")'

# Formatter (run after EVERY task, before reporting done)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'

# Docs
julia --project=docs docs/make.jl
```

Solvers: `HiGHS` (LP/MILP), `Ipopt` (NLP), `SCS` (SDP) — helpers `HiGHS_optimizer`/`ipopt_optimizer` in `test/test_utils/solver_definitions.jl`. Test systems come from `PowerSystemCaseBuilder` (PSB). Aqua checks are in `test/test_aqua.jl`.

### ParallelTestRunner specifics
- Discovers only top-level `test/test_*.jl`; `includes.jl`, `test_utils/`, `test_data/` are shared infra (not run as tests) — no need to edit `runtests.jl`/`includes.jl` to add a test file.
- Per-worker env sets `HDF5_USE_FILE_LOCKING=FALSE` (PSB reads a shared serialized-system HDF5 store concurrently) and `RUNNING_SIENNA_TESTS=true`.
- Each test runs in a **fresh module, not `Main`** — surfaces `Main`-only bugs. If a test fails only under the parallel runner, suspect module-context issues (`Symbol(T)`/`string(T)` dict keys, `getfield(Main, …)`); prefer `nameof`. Wall-clock is bound by the slowest single file (`test_device_hvdc` is the long pole).
- The old serial runner's global "no Error-level log events" `MultiLogger` assertion was **dropped** — it doesn't carry to per-worker isolation. Per-`@test`/`@testset` assertions still gate results.
- Warnings inside `build!` go to the build's `operation_problem.log` (wrapped in `with_logger`) — `@test_logs` at the call site can't see them; assert by reading the log file.

## Recipe: add a device formulation (end-to-end)

1. Define the formulation type under the right abstract in `src/core/formulations.jl`-equivalent for its family; define any new variable/constraint/parameter types in `core/` (check for dead/duplicate types first).
2. Implement both `construct_device!` stages in the family's `*_constructor.jl`; add the `add_variables!`/`add_constraints!`/`add_to_expression!`/objective methods in the family model file. Mirror the closest existing formulation's structure — divergence should be the point, not an accident.
3. Every PSY getter on a convertible field passes `PSY.SU`; index by component name; respect network reduction (branch-pair-keyed vars index by branch name).
4. Check device×network compatibility against existing signatures; run `Test.detect_ambiguities`.
5. Test: build + solve on a PSB fixture, then coefficient-level asserts against an independent reference (MODF-suite pattern); remember build warnings land in `operation_problem.log`.
6. Formatter; full suite (`--jobs=8`); **docs must build** (new exported types need docstrings + API-page registration).

## POM-specific conventions, invariants, gotchas

- **Layer boundaries:** device/network formulations + `PowerOperationModel` chain live in POM; `OptimizationContainer`/`DecisionModel`/settings/generic builders in IOM; base key/TS types in IS. Don't push power-specific logic down into IOM.
- **`network_reduction` must always be populated** by POM's `instantiate_network_model!` for every network model (CopperPlate/AreaBalance set an identity reduction). It is `Union{Nothing,...}` on the IOM side. Concrete `BranchReductionOptimizationTracker` + `get_constraint_map_by_type` live in POM `network_models/network_reductions.jl`; IOM keeps only the abstract `AbstractBranchReductionTracker`. IOM evaluators must be `<:IOM.AbstractEvaluator`; POM wraps PF models in `PowerFlowEvaluator` (`core/interfaces.jl`).
- **Two reduction types, one object — know which you need.** `get_network_reduction(model)` returns PNM's `NetworkReductionData`: bus/arc maps, equivalent admittances and ratings, `get_mapped_bus_number`, `arc_dc_*`. `get_reduction_index(model)` returns POM's `ReductionIndex` (`core/reduction_index.jl`), which *contains* that same object plus this template's type-organized views — the by-type branch maps, `name_to_arc`, and `component_to_reduction_name`. The views are keyed to the template, not the reduction, because each `DeviceModel`'s `filter_function` decides which branches participate; PNM derives them on demand via `build_branch_maps_by_type` and POM owns the result for the build. Reach the views through `get_name_to_arc_map_entries` / `get_reduction_entry` / `get_reduction_entries`, never by indexing the maps directly, and unwrap with `get_reduction_data(index)` when a PNM helper wants the reduction itself. Nothing is copied, so `PNM.get_network_reduction_data(matrix) === get_network_reduction(model)`.
- **Parallel branches** between the same `(from_bus, to_bus)` pair are reduced to one equivalent branch by PowerNetworkMatrices **before** reaching POM. Index branch-pair-keyed variables (LPAC cosine vars, voltage approximations) by branch name directly — do not add dedupe bookkeeping; it's a non-problem at this layer.
- **Security-constrained N-1 uses MODF** (Modified Outage Distribution Factors: PNM `VirtualMODF`/`ContingencySpec`), in `ac_transmission_models/security_constrained_branch.jl`. The old LODF-based `network_models/security_constrained_models.jl` and all generator-side (G-1) SC have been **removed** — do not reintroduce LODF or gen-side MODF. `NetworkModel.contingency_matrix`, `DeviceModel.outages`, and `supports_outages` (default false; POM specializes `true` for `AbstractSecurityConstrainedStaticBranch`) live in IOM.
- **Units (IS4/psy6 rework) — the highest-risk silent-failure class.** The stateful `SYSTEM_BASE` normalization is gone (`temp_set_units_base_system!` is removed/commented out upstream). Every `PSY` getter read during model build must pass the intended unit system **explicitly**: optimization models are all system base, so use `PSY.SU`. PNM aggregators already return system base (no `PSY.SU` needed). If objective/limit/rating values come out wrong post-refactor, suspect units first. Known traps: AC apparent-power rating RHS must be squared `(rating·factor)^2`; PSY setters reject bare `Float64` under psy6 (`set_rating_b!(line, 0.9*PSY.SU)`).
- **psy6 is a planned breaking release:** no compat shims, no deprecation framing, no serialization aliases for renamed enums — fix callers instead. Old serialized systems are expected to be regenerated. Never touch changelogs (unmaintained since 1.0).
- **No mid-project Project.toml version/compat bumps.** `[sources]` currently pin git branches: IS→`IS4`, PSY/PNM→`psy6`, IOM→`main`. Do the version/compat pass once at release time, not during cross-repo co-dev. Do not copy PSI Project.toml version bumps when porting PRs.
- **Method ambiguity:** the codebase relies on extensive multiple dispatch — check with `Test.detect_ambiguities` when adding overlapping signatures. Use parametric `where` signatures with abstract bounds for extensibility.

## DecisionModel test API (PowerSystems 6, verified)

- Status: `IOM.ModelBuildStatus.BUILT`, `IOM.RunStatus.SUCCESSFULLY_FINALIZED` (not `_FINISHED`).
- Results: `res = IOM.OptimizationProblemOutputs(model)` (not `OptimizationProblemResults`); `read_variable(res, "VarType__DeviceType"; table_format = TableFormat.WIDE)`. Keys use `"__"` delimiter (e.g. `"FlowActivePowerVariable__Line"`, `"VoltageAngle__ACBus"`). Base power: `IOM.get_model_base_power(res)`.
- Units gotcha: `FlowActivePowerVariable` output is MW (natural units, `convert_output_to_natural_units=true`); `VoltageAngle` is unitless. Native DC ohm law (pu): `p_pu == b * (va_from - va_to - shift)` with the DC susceptance `b = PNM.get_series_susceptance(branch, PSY.SU)` (= `1/(tap*x)`, tap-divided for transformers) — not the r-inclusive π-model susceptance.
- Template helper `get_thermal_dispatch_template_network(NetworkModel(<Formulation>))` and reduction kwargs `NetworkModel(DCPNetworkModel; reduce_radial_branches=true, reduce_degree_two_branches=true)` come from `test/test_utils/`.
- Reduction test systems: `c_sys5`/`c_sys14` reduce nothing (assert build+solve only). Use `case11_network_reductions` (purpose-built ~4 series arcs) or matpower cases for real reductions — but those lack forecast data, so a full `DecisionModel` `build!` errors; for white-box reduction tests build `NetworkReductionData` directly via `PNM.Ybus(sys; network_reductions=[...])` + `PNM.get_network_reduction_data(ybus)`, and derive the type-organized maps with `PNM.build_branch_maps_by_type(nrd)` (no `deepcopy` needed — that function does not mutate the reduction).

## Known open debt & active work (2026-07 snapshot)

- **~30 bare-unit PSY getters remain in build code** (the units rule above is stated but not fully enforced yet): known sites include `get_angle_limits` in `AC_branches.jl` (~1750, 1767) and `pm_translator.jl` (~280), and `get_loss` across `TwoTerminalDC_branches.jl` (71, 166, 221, 380, 818, and more). Angle limits are radians — no base conversion; loss terms are convertible. When touching one of these files, fix the bare getters in it. This POM/PNM/PF consumer sweep is the open remainder of the units-ecosystem closure effort.
- **Silent TS-missing device skip** (`common_models/add_parameters.jl:~175`): a device whose time series is missing gets `@debug` + skip — it silently drops out of the model. Named silent-failure pattern; never extend it, and prefer converting it to a loud error when the opportunity arises.
- **PSI port backlog** lives in `.claude/pom_port_plan.md`: fork baseline ≈ PSI #1503, PSI swept through #1640. Highlights: no `core/event_model.jl` yet (no `EventModel`/`FixedForcedOutage` machinery — Tier-0 blocker); service-side G-1 (PSI #1617) pending; a list of symbol-verified absent bugfixes/features (#1519, #1527, #1535, #1587, #1508, #1614, #1622, …). Porting rule: formulation-specific → POM, generic optimization core → IOM; adapt to POM's type-based dispatch, don't copy PSI code verbatim. Simulation orchestration is out of scope — never port it.
- **Direct-write hot spots to not extend:** `instantiate_network_model!` is a ~15-step mutation cascade with direct `model.field =` writes and no rollback; some `.data` writes into IOM containers exist (`thermal_generation.jl`). Prefer setters; don't add new direct reaches.

## Cross-package coupling (summary)

- **PowerSystems (PSY):** data structures (devices/services/networks) consumed by every formulation. psy6/IS4 units rework is in flight — see the units gotcha above.
- **InfrastructureOptimizationModels (IOM):** `OptimizationContainer`, `DecisionModel`/`EmulationModel`, settings, generic `add_*!`/store/objective infra. POM dispatches its problem-type chain on IOM abstracts. Watch for symbols moved POM-side by PR #104 / PNM-decoupling. **POM currently calls ~56 non-exported `IOM._*` helpers** — that surface is load-bearing but informal; do not add new `_*` reaches (formalizing the contract is the top audit action), and expect breakage there when IOM refactors.
- **PowerNetworkMatrices (PNM):** PTDF/LODF/MODF, branch reductions, rating aggregators (system base). Reduction happens before POM sees branches.
- **InfrastructureSystems (IS):** base optimization + time-series key types, time series, units engine (`ISOPT` = `InfrastructureSystems.Optimization`). IS4 made units domain-agnostic (`relative_units`, `IS.convert_cost_coefficient`, `_unitful` getters).
- **PowerFlows (PFS):** optional weakdep, wired through `ext/PowerFlowsExt/` (power-flow-in-the-loop, headroom, signed-injection PF data update). Code must work when PF is not loaded.

## Debugging

- Debug logging: `ENV["SIIP_LOGGING_CONFIG"] = "debug"`; use `LOG_GROUP_*` constants for targeted output.
- Leave edits **unstaged** in the working tree (user reviews via plain `git diff`); use `git add -N` for new files so they show. Never `git commit` unless explicitly told.
