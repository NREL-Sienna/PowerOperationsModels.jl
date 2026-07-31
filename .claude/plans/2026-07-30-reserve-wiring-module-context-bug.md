# Follow-up: reserve wiring into `ActivePowerRangeExpressionUB` is module-context dependent

> Discovered 2026-07-30 during the events-port final fix wave, while attempting a
> renewable + service-model event-constraint test. Pre-existing bug, unrelated to events.
> Not yet root-caused; recorded here so the investigation isn't lost.

## Symptom (100% reproducible, not flakiness)

Build a real (non-mock) template on `c_sys5_re` with `add_reserves = true`:
`RenewableFullDispatch` device model + `RangeReserve` service model, then `build!` a `DecisionModel`.

- Run as a top-level script (`julia --project=test script.jl`, `Main` context):
  `has_service_model(device_model)` is `true` and `ActivePowerRangeExpressionUB` rows contain
  **2 terms** (`ActivePowerVariable` + the reserve variable) — correct.
- Run the identical code inside **any** wrapping `module` block (exactly how
  `ParallelTestRunner` runs every test file — fresh module, not `Main`):
  the `ActivePowerReserveVariable` container exists, but the reserve variable
  **never lands in `ActivePowerRangeExpressionUB`** — rows have only 1 term.

Traced through `finalize_template!`, `_populate_contributing_devices!`,
`_add_services_to_device_model!`, `construct_services!` without isolating the trigger.

## Strongest lead

`src/core/problem_template.jl` keys the **services** dict by `Symbol(T)`
(lines ~93-94 and ~247 at time of writing) while the devices/branches paths use
`nameof(T)` (lines ~80, ~82).
`Symbol(T)`/`string(T)` dict keys are exactly the module-context bug class this repo's
CLAUDE.md already documents under "ParallelTestRunner specifics" (`Symbol(T)` embeds the
defining module path for types resolved differently in a fresh module; `nameof` does not).

## Impact

Any test or user code exercising service-augmented range expressions under the parallel
runner may silently build without reserve contributions — a silent-wrong-model class, not
a loud failure.
Also blocks adding a renewable+service event-constraint testset (the events port shipped
without that branch covered for this reason).

## Suggested next step

Reproduce with a minimal `module M; include(...); end` wrapper, then audit
`problem_template.jl`'s `Symbol(T)` keying against `nameof(T)`, fix, and add a
parallel-runner regression test plus the deferred renewable+service event testset.
