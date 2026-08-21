# Plan — phase-controlled transformers (`TransformerControlObjective.ACTIVE_POWER_FLOW`)

Branch `ac/pst`, based on `ac/transformer-control` (1d74849), which landed tap control
(`VOLTAGE` / `REACTIVE_POWER_FLOW`) for the native AC networks.

**Scope (confirmed):** DC networks only — `DCPNetworkModel`, `DCPLLNetworkModel`, and
`AbstractPTDFNetworkModel` (`PTDFNetworkModel`, `AreaPTDFNetworkModel`). AC networks
(ACP/ACR/LPACC/IVR) warn "not implemented" through the existing
`reduction_exceptions.jl` taxonomy. `NFANetworkModel` has no angles at all — same warn path.

---

## 0. Why DC-only is the natural split

Tap control is AC-shaped: `tap` enters the AC π-model in `_tapped_admittance`, and it was
explicitly rejected on DC (`_supports_tap(::NetworkModel{<:AbstractDCPNetworkModel}) = false`).

Phase control is the mirror image. PNM fixes the convention
(`PNM.get_series_phase_shift`, `PNM.arc_dc_shift_injection`):

```
f_from→to = b · (θ_f − θ_t − α)          nodal injection: +b·α at from, −b·α at to
```

α enters the DC model **linearly**, so every DC formulation stays an LP/QP. On AC it enters
as `cos(α)`/`sin(α)` inside the admittance rotation — trig-nonlinear for ACR/IVR,
non-convex for LPACC. That is a separate piece of work.

> **Sign trap.** Legacy PSI's `PhaseAngleControl` used `inv_x·(θ_f − θ_t + α)` — the
> *opposite* sign. Do not port PSI's sign; follow PNM's `− α`. Test 4 below pins this.

---

## 1. What already exists (scaffolding to complete, not invent)

| Symbol | Location | State |
|---|---|---|
| `PhaseShifterAngle <: VariableType` | `core/variables.jl:372` | defined, exported (`PowerOperationsModels.jl:577`) |
| `_CONTROL_VARS = Union{Type{TapRatioVariable}, Type{PhaseShifterAngle}}` | `AC_branches.jl:119` | done |
| `_branch_uses_control(::Type{PhaseShifterAngle}, …)` | `AC_branches.jl:132` | **calls `_phase_controlled`, which is undefined** — unreachable today |
| `_control_var_enabled`, `_branches_for_var`, reduction-aware `add_variables!` | `AC_branches.jl:122–320` | generic over `_CONTROL_VARS`; works unchanged |
| `PhaseAngleControl` formulation | `core/formulations.jl:270` | commented out — **delete** (superseded by the `enable_controls` attribute design) |
| `PhaseAngleControlLimit <: ConstraintType` | `core/constraints.jl:363` | live but dead — **delete** (α is bounded by variable bounds, as tap is) |
| commented PTDF `add_to_expression!` for `PhaseShifterAngle` | `common_models/add_to_expression.jl:1923` | **delete**; rewrite properly in step 5 |

So the variable-creation path is already generic; the work is the physics sites, the
control constraint, and the network/reduction taxonomy.

---

## 2. `RepresentativeBranch.jl` — predicates and the one implemented-controls table

Add beside the existing tap constants:

```julia
const _ACTIVE_CONTROL = PSY.TransformerControlObjective.ACTIVE_POWER_FLOW
const _PHASE_CONTROLS = (_ACTIVE_CONTROL,)

_active_controlled(rep, d::DeviceModel) = _control_objective(rep, d) === _ACTIVE_CONTROL

_phase_controlled(
    rep::RepresentativeBranch, d::DeviceModel,
    ::NetworkModel{<:Union{AbstractDCPNetworkModel, AbstractDCPLLNetworkModel}},
) = _control_objective(rep, d) in _PHASE_CONTROLS
_phase_controlled(::RepresentativeBranch, ::DeviceModel, ::NetworkModel) = false
```

(`AbstractPTDFNetworkModel <: AbstractDCPNetworkModel`, so PTDF is covered by the first method.)

**One table, two consumers.** Today `_controlled_circuit_names` hard-codes `_TAP_CONTROLS`
and `reduction_exceptions.jl` hard-codes `_IMPLEMENTED_CONTROLS = _TAP_CONTROLS` +
`_supports_tap`. These will drift. Replace both with:

```julia
_implemented_controls(::NetworkModel{<:NativeACNetworkModel}) = _TAP_CONTROLS
_implemented_controls(
    ::NetworkModel{<:Union{AbstractDCPNetworkModel, AbstractDCPLLNetworkModel}},
) = _PHASE_CONTROLS
_implemented_controls(::NetworkModel) = ()
```

and widen `_controlled_circuit_names(branch, device_model)` →
`_controlled_circuit_names(branch, device_model, network_model)`, testing against
`_implemented_controls(network_model)`. Without this, a phase-controlled circuit merged
into a parallel/series arc is *silently dropped* instead of hitting the existing
"Controlled transformer circuit … was merged into the reduced arc" error. Three call sites,
all inside `_branches_for_var`, which has `network_model` in scope.

---

## 3. Variable bounds, start, and the unset-data guard

In `AC_branches.jl`, beside the `TapRatioVariable` methods:

```julia
_branch_variable_bounds(::Type{PhaseShifterAngle}, rep, ::DeviceModel{…}, ::NetworkModel) =
    _control_limits(rep)
_branch_variable_start(::Type{PhaseShifterAngle}) = 0.0
```

`PSY.get_control_limits` is documented as "tap-ratio bounds for voltage/reactive-power
control **or phase-angle bounds (rad) for active-power control**" — a raw getter, no unit
argument, radians, no base conversion (same as `_angle_limits`). α is modeled **absolute**,
not as a deviation from the stored `α`, mirroring how `TapRatioVariable` is the absolute tap.

`convert_output_to_natural_units` stays at its `false` default — radians, like `VoltageAngle`.

---

## 4. Where α enters — the three angle-based sites

All three currently read a scalar `shift = _dc_shift(rep)`. The edit is uniform and follows
the existing `tap_var = if _tap_controlled(…) … else nothing end` idiom already in the file:

```julia
phase_var = _phase_controlled(rep, device_model, network_model) ?
    get_variable(container, PhaseShifterAngle, T) : nothing
# inside the time loop
shift = isnothing(phase_var) ? _dc_shift(rep) : phase_var[name, t]
```

`b * (va_f − va_t − shift)` stays an `AffExpr` either way.

| Network × formulation | Flow object | Site |
|---|---|---|
| DCP × `StaticBranch` | `BThetaBranchFlow` expression | `add_expressions!(BThetaBranchFlow, …)`, `AC_branches.jl:~2009` |
| DCP × `StaticBranchBounds` | `FlowActivePowerVariable` | `add_constraints!(NetworkFlowConstraint, …, DCPNetworkModel)`, `AC_branches.jl:~1946` |
| DCPLL × both | `FlowActivePowerFromToVariable` | `add_constraints!(NetworkFlowConstraint, …, DCPLLNetworkModel)`, `AC_branches.jl:~2342` |

The `BThetaBranchFlow` builder currently takes `::DeviceModel{T, StaticBranch}` unnamed —
name it. It also writes into `ActivePowerBalance`, so the variable α propagates to the nodal
balance for free (no separate injection needed on DCP).

**Build-order check (`operation/build_problem.jl:100–215`):** device Argument → services
Argument → **branch Argument** → **network Argument** → device Model → network Model →
**branch Model**. `PhaseShifterAngle` is created in the branch Argument stage, so it exists
before `BThetaBranchFlow` (network Argument), before the nodal balance closes (network
Model), and before `PTDFBranchFlow` (branch Model). No reordering needed.

---

## 5. PTDF — the only structurally different case

Under PTDF the shift is not in an Ohm's law; it is a pair of constant nodal injections plus a
constant flow offset. Three coordinated edits:

**5a. `network_constructor.jl:158` `_add_dc_phase_shift_injections!`** — skip controlled arcs.
Signature becomes `(container, model, template)`; `construct_network!` already receives
`template` (currently unnamed). Build `controlled_arcs::Set{Tuple{Int,Int}}` from
`get_branch_models(template)` and `continue` on a hit, so the constant `±b·α` is not added
alongside the variable one.

**5b. New `add_to_expression!(container, ActivePowerBalance, PhaseShifterAngle, devices,
device_model, network_model::NetworkModel{<:AbstractPTDFNetworkModel})`** in
`common_models/add_to_expression.jl` (replacing the commented block at :1923). For each
phase-controlled rep, with `b = _dc_susceptance(rep)`:

```
expr[from_no, t] += +b · α[name, t]
expr[to_no,   t] += −b · α[name, t]
```

Matching `arc_dc_shift_injection`'s `+b·α at from`. Register through
`search_for_reduced_branch_expression!` for consistency (phase-controlled arcs are forced to
`DIRECT_BRANCH_MAP` by step 2, so double-wiring is not actually reachable, but the tracker is
the house rule). Called from the PTDF Argument constructors right after `add_variables!`.

**5c. `AC_branches.jl:~695` `_make_flow_expressions!`** — its 5th argument is the `Float64`
`-PNM.arc_dc_shift_injection(nr, arc)`, added via `JuMP.add_to_expression!(acc, shift_offset)`.
For a controlled arc it must be the per-`t` `AffExpr` `−b·α[name, t]`. This runs inside a
`Threads.@spawn` map — add a **second method** dispatching on `Vector{JuMP.AffExpr}` rather
than widening the existing argument to a union, so the constant hot path stays type-stable.

Note `PTDFBranchFlow` is built in the branch **Model** stage, after the nodal balance closes,
so it sees the α injections from 5b. The α terms cancel across the system balance (+b, −b),
so the copper-plate/area balance is unaffected — correct physics.

---

## 6. `ActivePowerFlowControlConstraint`

New `ConstraintType` in `core/constraints.jl` beside `ReactivePowerFlowControlConstraint`
(:211), with docstring; export near `PowerOperationsModels.jl:781`. No registration needed —
`get_branch_argument_constraint_axis` builds the tracker map lazily with `get!`.

`_add_active_control_constraints!` in `AC_branches.jl`, a direct structural mirror of
`_add_reactive_control_constraints!` (:1485):

- gate on `_control_enabled(device_model)`
- sparse `(name, side, t)` container
- one representative per arc via `_representative_branches(network_model, T, ActivePowerFlowControlConstraint)`
- `_active_controlled(rep, device_model) || return`
- cross-check `line_lims.min ≤ cont_lims.min ≤ cont_lims.max ≤ line_lims.max`, error otherwise
- two rows per `t` against the flow object
- no-op fallback on `::NetworkModel`

Flow object by dispatch (`_active_flow_array(container, device_model, network_model, T)`),
mirroring the test helper `_dc_flows`:

| | DCP | DCPLL | PTDF |
|---|---|---|---|
| `StaticBranch` | `BThetaBranchFlow` expr | `FlowActivePowerFromToVariable` | `PTDFBranchFlow` expr |
| `StaticBranchBounds` | `FlowActivePowerVariable` | `FlowActivePowerFromToVariable` | `FlowActivePowerVariable` |

Hook into `_add_transformer_control_constraints!` (:1534) alongside the voltage/reactive calls.

**Units.** `get_controlled_quantity_limits` is a raw getter (no `units` argument); its PSY
docstring says "MW" for an active objective, but the existing `REACTIVE_POWER_FLOW` path
compares it directly against system-pu flow variables. Follow that precedent (system pu) so
the three objectives stay consistent, and raise the docstring discrepancy upstream in PSY
rather than diverging here.

**`regulated_bus_number` is not used.** For PSS/E COD=3 the controlled quantity is the flow
through the circuit itself; the existing reactive path ignores the field too.

---

## 7. Constructors (`branch_constructor.jl`)

Six Argument-stage methods get `add_variables!(container, PhaseShifterAngle, devices,
device_model, network_model)` (the two PTDF ones also get the 5b `add_to_expression!`), and
the six matching Model-stage methods get `_add_transformer_control_constraints!(container,
sys, devices, device_model, network_model)` — none of the DC constructors call it today.

| Formulation × network | Argument | Model |
|---|---|---|
| `StaticBranch` × DCP | ~839 | ~873 |
| `StaticBranchBounds` × DCP | ~1165 | ~1194 |
| `StaticBranch` × DCPLL | ~1002 | ~1052 |
| `StaticBranchBounds` × DCPLL | ~1084 | ~1133 |
| `StaticBranch` × PTDF | ~1219 | ~1258 |
| `StaticBranchBounds` × PTDF | ~1299 | ~1318 |

`StaticBranchUnbounded` is deliberately excluded (no flow object under DCP at all) — it falls
to the warn path in step 8, matching how tap control is scoped.

Run `Test.detect_ambiguities` — the generic
`DeviceModel{T, StaticBranch} × NetworkModel{<:AbstractActivePowerModel}` methods at :83/:99
must keep catching only CopperPlate/AreaBalance.

---

## 8. `reduction_exceptions.jl` — one taxonomy, no drift

Replace `_supports_tap` / `_IMPLEMENTED_CONTROLS` with `_implemented_controls(network_model)`
from step 2, and restructure `_pin_transformer_controls!` to:

```
obj.value > 0 && !available        → warn "the circuit is unavailable"
obj ∈ _implemented_controls(nm)    → pin the circuit's two endpoint buses
                                     (+ regulated bus, VOLTAGE only)
obj ∈ _TAP_CONTROLS                → warn "tap control is not supported on <N> networks"
obj ∈ _PHASE_CONTROLS              → warn "phase control is not supported on <N> networks"
otherwise                          → warn "not yet implemented for this DeviceModel/NetworkModel pair"
```

Add a formulation gate too: warn when the branch formulation is not `StaticBranch` /
`StaticBranchBounds` (`get_formulation(m)` is available on the `DeviceModel`). Phase control
pins **only** the circuit's own endpoints — not `regulated_bus_number`.

Existing test `"a tap control scheme builds no tap variable on a DC network"` asserts the
literal string `"DC networks do not support variable-tap"` in `operation_problem.log`; the new
wording must be updated there in lockstep.

---

## 9. Two explicitly-out-of-scope interactions (rejected loudly, not silently)

**Security-constrained N-1.** `security_constrained_branch.jl:580` builds post-contingency
MODF flow expressions from the *constant* `-PNM.arc_dc_shift_injection(nr, arc)`. With a
variable α those post-contingency flows are wrong. v1 **errors** when a phase-controlled
circuit's component type is also modeled with an `AbstractSecurityConstrainedStaticBranch`
formulation in the template (template validation, or `_branches_for_var`). Silent wrongness
here is exactly the failure class the repo guide calls out. Follow-up work, tracked in the PR.

**Power-flow-in-the-loop.** `ext/PowerFlowsExt/` pushes injections and voltages; it never
pushes taps or α (`grep` confirms: no tap/α handling at all). A PF evaluation alongside a
variable-α model solves the PF with the *stored* α. This is a pre-existing gap shared with tap
control — document it in the formulation-library entry, don't fix it here.

---

## 10. Dead code to delete in this PR

- `PhaseAngleControl` commented struct — `core/formulations.jl:270`; `# export PhaseAngleControl` — `PowerOperationsModels.jl:894`
- `PhaseAngleControlLimit` struct + docstring — `core/constraints.jl:~355–363`; its export if present; commented refs at `security_constrained_branch.jl:76–79`
- commented PTDF `add_to_expression!` block — `common_models/add_to_expression.jl:1911–1948`

---

## 11. Docs

`docs/src/reference/formulation_library.md` §"Tap and phase-angle control" (~260–268) is
**already stale** — it still documents the deleted `VoltageControlTap` / `TapControl`
*formulation types*. Rewrite it around the actual design: the `enable_controls` DeviceModel
attribute on `TwoWindingTransformer`/`ThreeWindingTransformer` + a per-objective ×
per-network support matrix (VOLTAGE / REACTIVE_POWER_FLOW → native AC;
ACTIVE_POWER_FLOW → DCP / DCPLL / PTDF; everything else warned), the α sign convention, and
the SC / power-flow-in-the-loop caveats from §9. Register
`ActivePowerFlowControlConstraint` on the API page (`docs/make.jl` must build).

---

## 12. Tests

Extend `test/test_utils/transformer_utils.jl`:

- `const P_FLOW_CONTROL = PSY.TransformerControlObjective.ACTIVE_POWER_FLOW`, `const PHASE_CONTROLS = (P_FLOW_CONTROL,)`
- `_default_quantity_limits` gains a phase branch (active flow band, pu)
- phase-appropriate default `control_limits` (e.g. `(min = −0.3, max = 0.3)` rad) — the PSY
  default `(0.9, 1.1)` is tap-shaped
- **fixture gap:** `c_sys14`'s `Trans1..4` all have `α = 0` and PSB ships no phase shifter, so
  every phase fixture must `PSY.set_α!` explicitly. Pick a transformer on a meshed path so the
  control actually binds — verify before writing assertions.

New `test/test_transformer_phase_controls.jl` (a sibling file, not an addition to the already-large
`test_transformer_controls.jl` — the parallel runner is bound by its slowest single file and
auto-discovers any top-level `test_*.jl`):

1. `enable_controls = false` → no `PhaseShifterAngle`, no `ActivePowerFlowControlConstraint`, on all DC networks × both formulations.
2. Variable and constraint exist **only** for the controlled circuit; α bounds == `control_limits`.
3. Phase objective on an AC network → no α variable, and `operation_problem.log` carries the "phase control is not supported" warning (build warnings go to the log, not `@test_logs`).
4. **Sign/equivalence (highest value):** α fixed via `JuMP.fix` to the stored `PSY.get_α` reproduces the `enable_controls = false` model — objective value and all flows. Mirrors the existing "a tap pinned at nominal reproduces the uncontrolled model" testset and is what pins the `−α` convention against PNM's constant path.
5. **Efficacy:** solve free, read the circuit flow, then set `controlled_quantity_limits` to a band strictly inside that value; assert the solved flow lands in the band. Mirrors the VOLTAGE / REACTIVE_POWER_FLOW testsets.
6. **DCP ↔ PTDF agreement:** same system and same α on both → identical flows. Catches the 5b/5c injection-and-offset signs independently of the DCP path.
7. **PowerFlows cross-check:** extend the existing "off-nominal two-winding taps agree with a PowerFlows DC solve (c_sys14)" testset with a non-zero *static* α, guarding `_dc_shift`'s sign against PF. Static only — variable α is not pushed to PF (§9).
8. **Reduction:** a phase-controlled circuit merged into a parallel/series arc hits the `_branches_for_var` error; a phase-controlled circuit and its arc survive radial + degree-two reduction.
9. `Test.detect_ambiguities` (already in `test_aqua.jl`) still clean.

Also update the string assertion in `test_transformer_controls.jl`'s DC testset (§8).

---

## 13. Order of work

1. Predicates + `_implemented_controls` + widen `_controlled_circuit_names` + rewrite the `reduction_exceptions.jl` taxonomy. No behavior change for tap — run `test_transformer_controls.jl` to prove it.
2. Bounds/start + DCP and DCPLL constructors + the three α substitution sites (§4).
3. `ActivePowerFlowControlConstraint` + `_add_active_control_constraints!` + flow-array dispatch (§6).
4. PTDF: injection skip, `add_to_expression!`, `_make_flow_expressions!` offset method (§5).
5. SC rejection (§9).
6. Dead-code deletion (§10).
7. Tests (§12), docs (§11).
8. `scripts/formatter/formatter_code.jl`; `julia --project=test test/runtests.jl --jobs=8`; `julia --project=docs docs/make.jl`.

Rough size: ~400–500 lines of `src/`, ~350 lines of tests, plus the docs rewrite.

---

## 14. Judgement calls made — flag if you disagree

| Call | Chosen | Alternative |
|---|---|---|
| α semantics | absolute angle (mirrors absolute `TapRatioVariable`) | deviation from stored `α` |
| Constraint type | new `ActivePowerFlowControlConstraint` (symmetry with the other two) | reuse the dead `PhaseAngleControlLimit` |
| `controlled_quantity_limits` units | system pu, following the reactive precedent | trust the PSY "MW" docstring and convert |
| Formulations | `StaticBranch` + `StaticBranchBounds` only | also `StaticBranchUnbounded` (has no DCP flow object) |
| SC + phase control | hard error | build it, accepting wrong post-contingency flows |
| PSY-default `control_limits` under a phase objective | warn | error, or accept silently |
