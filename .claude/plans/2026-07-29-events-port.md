# Events Port (PSI → POM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the time-series outage events feature (PSI "Feature A") into POM so a standalone `DecisionModel` builds event parameters and outage constraints, per the approved spec at `.claude/specs/2026-07-29-events-port-design.md`.

**Architecture:** New `src/event_models/` directory holds the container types (`EventKey`, `EventModel`, condition structs), traits, parameter builders, and constraint builders.
POM already has the parameter/constraint types in `src/core/`, no-op stubs for `add_event_arguments!`/`add_event_constraints!` in `src/core/feedforward_interface.jl:49-69`, and every constructor call site wired — this port replaces the stubs with real dispatch methods and adds template-level attachment plus build-time discovery.
IOM needs exactly one correction (Task 4b): its event parameter machinery bounds the contingency slot on `IS.InfrastructureSystemsComponent`, but contingency types live under `IS.SupplementalAttribute` — every other IOM piece is consumed as-is.

**Tech Stack:** Julia, JuMP, PowerSystems (psy6), InfrastructureOptimizationModels (main), HiGHS/Ipopt for tests, PowerSystemCaseBuilder fixtures.

## Global Constraints

- Never run `git commit` or `git push`. Leave all edits unstaged; run `git add -N <file>` for each newly created file so it shows in `git diff`.
- All Julia commands use `julia --project=test`; never bare `julia` or `--project=.`.
- Run the formatter after completing each task: `julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'`.
- Every `PSY` getter on a unit-convertible field passes `PSY.SU` explicitly (e.g. `PSY.get_active_power_limits(d, PSY.SU)`). Never copy PSI getter calls verbatim — PSI predates the stateless-units rework.
- No `Project.toml` or `[sources]` pin changes of any kind.
- No new reaches into non-exported `IOM._*` helpers beyond those POM already uses (`IOM._set_multiplier_at!`, `IOM._set_parameter_at!`, `IOM.get_multiplier_array_data`, `IOM.get_parameter_array_data` are already in use in `src/common_models/add_parameters.jl` and may be used here).
- All type bounds use `PSY.Contingency` (never `PSY.Outage`) for event dispatch.
- `add_*!` methods end with bare `return`; store JuMP objects via `add_*_container!`, never return collections.
- Do not touch `src/common_models/add_to_expression.jl`, `src/ac_transmission_models/`, or `src/network_models/` — the concurrent transformer-refactor plan owns those files. All new event code lives in `src/event_models/`, `src/core/problem_template.jl`, `src/operation/template_validation.jl`, and test files.
- Do not modify PSI, HPS, SSS, or PSY checkouts.
- IOM changes happen ONLY in the local clone at `/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl` (branch `mb/events-port`), ONLY as scoped in Task 4b, under IOM's house rules: never edit the `version` field in its `Project.toml`, use its own formatter script, prefer mocks over PSY types in its tests, and add no `using`/`include`/`const` lines to individual `test_*.jl` files (they are included by `InfrastructureOptimizationModelsTests.jl`).
- New exported symbols need docstrings; the docs build (`julia --project=docs docs/make.jl`) is a completion gate.

## Reference sources (read-only)

- PSI: `/Users/mbossart/sienna/PowerSimulations.jl` — `src/core/event_keys.jl`, `src/core/event_model.jl`, `src/contingency_model/*.jl`.
- HPS `src/contingency_model.jl` and SSS `src/contingency_model.jl` — fetch from GitHub `Sienna-Platform/{HydroPowerSimulations,StorageSystemsSimulations}.jl` `main` if needed; the relevant code is reproduced in Tasks 7–8.
- IOM provides (via `using InfrastructureOptimizationModels`, `src/PowerOperationsModels.jl:206`): `AbstractEventModel`, `AbstractEventKey`, `DeviceModel.events::Dict{AbstractEventKey, AbstractEventModel}`, `set_event_model!(::DeviceModel, key, event)`, `get_events(::DeviceModel)`, `EventParameter`, `EventParametersAttributes`, and `add_param_container!(container, ::Type{T<:EventParameter}, ::Type{U}, ::Type{V}, axs...)` (note: IOM takes `Type{T}`, not an instance like PSI).
  The `V` slot of that overload requires the Task 4b bound fix (`IS.InfrastructureSystemsComponent` → `IS.SupplementalAttribute`) before it dispatches for contingency types.
  Local IOM clone: `/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl`, branch `mb/events-port`.

---

### Task 0: Environment gate and baseline

**Files:** none modified.

- [ ] **Step 1: Verify POM loads.**

Run: `julia --project=test -e 'using PowerOperationsModels; println("LOADED")'`
Expected: prints `LOADED`.
If it fails with `UndefVarError: PhaseShiftingTransformer` (or any missing transformer symbol): **STOP — do not work around it.**
The environment has resolved PSY past the #1714 transformer refactor; load restoration is owned by `.claude/plans/2026-07-26-transformer-refactor.md` Tasks 0–1.
Report the blocker and end the session.

- [ ] **Step 2: Baseline test run.**

Run: `julia --project=test test/runtests.jl test_device_thermal_generation_constructors`
Expected: PASS. Record the result; later tasks must not regress it.

---

### Task 1: Container types — `src/event_models/event_model.jl`

**Files:**
- Create: `src/event_models/event_model.jl`
- Modify: `src/PowerOperationsModels.jl` (includes + exports)
- Test: `test/test_events.jl` (new)

**Interfaces:**
- Consumes: `IOM.AbstractEventKey`, `IOM.AbstractEventModel` (available unqualified via `using InfrastructureOptimizationModels`), `PSY.Contingency`, `PSY.FixedForcedOutage`, `PSY.GeometricDistributionForcedOutage`, `VariableType`.
- Produces: `EventKey{T,U}`, `EventKey(::Type{T}, ::Type{U})`, `get_entry_type(::EventKey)`, `get_component_type(::EventKey)`, `AbstractEventCondition`, `ContinuousCondition`, `PresetTimeCondition`, `StateVariableValueCondition`, `DiscreteEventCondition`, `EventModel{D,B}`, `EventModel(contingency_type, condition; timeseries_mapping, attributes)`, `get_empty_timeseries_mapping(::Type)`, `get_event_type`, `get_event_condition`, `get_attribute_device_map`. Tasks 2–9 use all of these names exactly as written.

- [ ] **Step 1: Write the failing test.**

Create `test/test_events.jl`:

```julia
@testset "EventKey and EventModel construction" begin
    key = EventKey(PSY.FixedForcedOutage, PSY.ThermalStandard)
    @test IOM.get_entry_type(key) == PSY.FixedForcedOutage
    @test IOM.get_component_type(key) == PSY.ThermalStandard
    # Abstract component types are rejected
    @test_throws ErrorException EventKey(PSY.FixedForcedOutage, PSY.ThermalGen)

    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    @test get_event_type(em) == PSY.FixedForcedOutage
    @test get_event_condition(em) isa ContinuousCondition
    @test em.timeseries_mapping == Dict{Symbol, Union{String, Nothing}}(:outage_status => nothing)
    @test isempty(get_attribute_device_map(em))

    em_geo = EventModel(PSY.GeometricDistributionForcedOutage, ContinuousCondition())
    @test Set(keys(em_geo.timeseries_mapping)) ==
          Set([:mean_time_to_recovery, :outage_transition_probability])

    pc = PresetTimeCondition([Dates.DateTime("2024-01-01T05:00:00")])
    @test get_time_stamps(pc) == [Dates.DateTime("2024-01-01T05:00:00")]
end
```

Note: `IOM.get_entry_type`/`IOM.get_component_type` are used above on the assumption IOM defines those generics; if `IOM.get_entry_type` does not exist, define POM-owned generics in this file and test unqualified `get_entry_type(key)` instead — check with `julia --project=test -e 'using InfrastructureOptimizationModels; println(isdefined(InfrastructureOptimizationModels, :get_entry_type))'` and use whichever holds.

- [ ] **Step 2: Run it to verify it fails.**

Run: `julia --project=test -e 'include("test/includes.jl"); include("test/test_events.jl")'`
Expected: FAIL with `UndefVarError: EventKey`.

- [ ] **Step 3: Write the implementation.**

Create `src/event_models/event_model.jl` (adapted from PSI `src/core/event_keys.jl` + `src/core/event_model.jl`; changes: subtype the IOM abstracts, drop the per-simulation-model outer key of `attribute_device_map`, add docstrings):

```julia
"""
    EventKey(::Type{T}, ::Type{U})

Key identifying an event of contingency type `T` applied to devices of concrete type `U`.
Used as the key of the `DeviceModel.events` dict. Errors if `U` is abstract.
"""
struct EventKey{T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} <:
       IOM.AbstractEventKey
    meta::String
end

function EventKey(
    ::Type{T},
    ::Type{U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}}
    if isabstracttype(U)
        error("Type $U can't be abstract")
    end
    return EventKey{T, U}("")
end

get_entry_type(
    ::EventKey{T, U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} = T
get_component_type(
    ::EventKey{T, U},
) where {T <: PSY.Contingency, U <: Union{PSY.Component, PSY.System}} = U

"""
Abstract type for the condition that triggers an event. POM stores conditions as data;
evaluating them requires a simulation runtime and happens outside this package.
"""
abstract type AbstractEventCondition end

"""
    ContinuousCondition()

Event condition that is triggered at all timesteps.
"""
struct ContinuousCondition <: AbstractEventCondition end

"""
    PresetTimeCondition(time_stamps::Vector{Dates.DateTime})

Event condition that is triggered at pre-determined times.
"""
struct PresetTimeCondition <: AbstractEventCondition
    time_stamps::Vector{Dates.DateTime}
end

get_time_stamps(c::PresetTimeCondition) = c.time_stamps

"""
    StateVariableValueCondition(variable_type, device_type, device_name, value)

Event condition triggered when the monitored variable equals `value` (p.u.).
"""
struct StateVariableValueCondition <: AbstractEventCondition
    variable_type::VariableType
    device_type::Type{<:PSY.Device}
    device_name::String
    value::Float64
end

get_variable_type(c::StateVariableValueCondition) = c.variable_type
get_device_type(c::StateVariableValueCondition) = c.device_type
get_device_name(c::StateVariableValueCondition) = c.device_name
get_value(c::StateVariableValueCondition) = c.value

"""
    DiscreteEventCondition(condition_function::Function)

Event condition driven by a user-defined function evaluated by the simulation runtime.
"""
struct DiscreteEventCondition <: AbstractEventCondition
    condition_function::Function
end

get_condition_function(c::DiscreteEventCondition) = c.condition_function

"""
    EventModel(contingency_type, condition; timeseries_mapping, attributes)

Container binding a `PSY.Contingency` supplemental-attribute type to a trigger condition
and time-series mapping. Attach to a template with
`set_event_model!(template, event_model)`; build-time discovery populates
`attribute_device_map` (outage attribute UUID → device type → device names) and
distributes the event to the matching `DeviceModel`s.
"""
mutable struct EventModel{D <: PSY.Contingency, B <: AbstractEventCondition} <:
               IOM.AbstractEventModel
    condition::B
    timeseries_mapping::Dict{Symbol, Union{String, Nothing}}
    attribute_device_map::Dict{Base.UUID, Dict{DataType, Set{String}}}
    attributes::Dict{String, Any}

    function EventModel(
        contingency_type::Type{D},
        condition::B;
        timeseries_mapping = get_empty_timeseries_mapping(contingency_type),
        attributes = Dict{String, Any}(),
    ) where {D <: PSY.Contingency, B <: AbstractEventCondition}
        new{D, B}(
            condition,
            timeseries_mapping,
            Dict{Base.UUID, Dict{DataType, Set{String}}}(),
            attributes,
        )
    end
end

"""
Reserved time-series mapping keys for a contingency type. `:outage_status` is required
for `PSY.FixedForcedOutage`.
"""
function get_empty_timeseries_mapping(::Type{PSY.FixedForcedOutage})
    return Dict{Symbol, Union{String, Nothing}}(:outage_status => nothing)
end

function get_empty_timeseries_mapping(::Type{PSY.GeometricDistributionForcedOutage})
    return Dict{Symbol, Union{String, Nothing}}(
        :mean_time_to_recovery => nothing,
        :outage_transition_probability => nothing,
    )
end

get_event_type(
    ::EventModel{D, B},
) where {D <: PSY.Contingency, B <: AbstractEventCondition} = D

get_event_condition(
    e::EventModel{D, B},
) where {D <: PSY.Contingency, B <: AbstractEventCondition} = e.condition

get_attribute_device_map(e::EventModel) = e.attribute_device_map
```

If Step 1's isdefined check showed IOM owns `get_entry_type`/`get_component_type` generics, define the two methods as `IOM.get_entry_type(...)`/`IOM.get_component_type(...)` extensions instead of new generics (POM may already extend them for other key types — check `grep -rn "get_entry_type" src/` and match the existing style).

- [ ] **Step 4: Wire include and exports.**

In `src/PowerOperationsModels.jl`:
find the last `include("core/...")` line (`grep -n 'include("core/' src/PowerOperationsModels.jl | tail -1`) and insert after it:

```julia
include("event_models/event_model.jl")
```

Find the export section (`grep -n '^export' src/PowerOperationsModels.jl | head -3`) and add, grouped with a comment near the other model-container exports:

```julia
export EventModel
export EventKey
export AbstractEventCondition
export ContinuousCondition
export PresetTimeCondition
export StateVariableValueCondition
export DiscreteEventCondition
export get_empty_timeseries_mapping
export get_event_type
export get_event_condition
export get_attribute_device_map
export set_event_model!
```

(`set_event_model!` currently resolves to IOM's function; POM re-exports it and Task 3 adds the template method to the same generic.)

- [ ] **Step 5: Run the test to verify it passes.**

Run: `julia --project=test -e 'include("test/includes.jl"); include("test/test_events.jl")'`
Expected: PASS.

- [ ] **Step 6: Track and format.**

```bash
git add -N src/event_models/event_model.jl test/test_events.jl
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

---

### Task 2: Traits — `src/event_models/event_traits.jl`

**Files:**
- Create: `src/event_models/event_traits.jl`
- Modify: `src/PowerOperationsModels.jl` (include + export)
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: `EventModel` (Task 1), the parameter types in `src/core/parameters.jl:208-223` (`AvailableStatusParameter`, `ActivePowerOffsetParameter`, `ReactivePowerOffsetParameter`, `AvailableStatusChangeCountdownParameter`), `EventParameter` (IOM).
- Produces: `supports_events(::Type{<:PSY.Component})::Bool`, `get_parameter_multiplier(::EventParameter, ::PSY.Device, ::EventModel)`, `get_initial_parameter_value(::<each event parameter>, ::PSY.Device, ::EventModel)`. Tasks 4 and 5 call these exact signatures.

- [ ] **Step 1: Write the failing test.** Append to `test/test_events.jl`:

```julia
@testset "Event traits" begin
    @test POM.supports_events(PSY.ThermalStandard)
    @test POM.supports_events(PSY.RenewableDispatch)
    @test POM.supports_events(PSY.PowerLoad)
    @test POM.supports_events(PSY.HydroDispatch)
    @test POM.supports_events(PSY.EnergyReservoirStorage)
    @test !POM.supports_events(PSY.Source)

    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    d = PSY.ThermalStandard(nothing)
    @test POM.get_initial_parameter_value(AvailableStatusParameter(), d, em) == 1.0
    @test POM.get_initial_parameter_value(AvailableStatusChangeCountdownParameter(), d, em) == 0.0
    @test POM.get_initial_parameter_value(ActivePowerOffsetParameter(), d, em) == 0.0
    @test POM.get_initial_parameter_value(ReactivePowerOffsetParameter(), d, em) == 0.0
    @test POM.get_parameter_multiplier(AvailableStatusParameter(), d, em) == 1.0
end
```

Check how the test preamble aliases the package (`grep -n "const POM\|import PowerOperationsModels" test/includes.jl test/test_utils/*.jl | head -5`); if the alias is different (e.g. `PSI` for compatibility), use that alias.
If `PSY.ThermalStandard(nothing)` is unavailable in psy6, use `first(PSY.get_components(PSY.ThermalStandard, PSB.build_system(PSB.PSITestSystems, "c_sys5")))` instead.

- [ ] **Step 2: Run to verify it fails** (same include command as Task 1). Expected: FAIL with `UndefVarError: supports_events` (or MethodError).

- [ ] **Step 3: Implement.** Create `src/event_models/event_traits.jl`:

```julia
#! format: off
get_parameter_multiplier(::EventParameter, ::PSY.Device, ::EventModel) = 1.0
get_initial_parameter_value(::ActivePowerOffsetParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::ReactivePowerOffsetParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::AvailableStatusChangeCountdownParameter, ::PSY.Device, ::EventModel) = 0.0
get_initial_parameter_value(::AvailableStatusParameter, ::PSY.Device, ::EventModel) = 1.0

"""
Whether devices of this type support outage events (`EventModel`). This is a device-type
capability trait for time-series outage events — distinct from `supports_outages`, the
formulation trait for security-constrained (MODF) branch contingencies.
"""
supports_events(::Type{T}) where {T <: PSY.Component} = false
supports_events(::Type{T}) where {T <: PSY.ThermalStandard} = true
supports_events(::Type{T}) where {T <: PSY.RenewableGen} = true
supports_events(::Type{T}) where {T <: PSY.ElectricLoad} = true
supports_events(::Type{T}) where {T <: PSY.Storage} = true
supports_events(::Type{T}) where {T <: PSY.HydroGen} = true
#! format: on
```

Note the fallback is `PSY.Component` (PSI used `PSY.StaticInjection`); the wider fallback lets discovery (Task 4) query any device type safely.
If `get_parameter_multiplier`/`get_initial_parameter_value` generics already have POM methods with different owner modules, extend the same function the existing methods extend (check `grep -rn "function get_initial_parameter_value\|get_initial_parameter_value(" src/common_models/add_parameters.jl | head -3` and mirror).

- [ ] **Step 4: Wire include + export.** In `src/PowerOperationsModels.jl` add after the Task 1 include:

```julia
include("event_models/event_traits.jl")
```

Add `export supports_events` next to the Task 1 export block.

- [ ] **Step 5: Run the test to verify it passes.** Expected: PASS.
- [ ] **Step 6:** `git add -N src/event_models/event_traits.jl`; run the formatter.

---

### Task 3: Template attachment

**Files:**
- Modify: `src/core/problem_template.jl` (struct + accessors), `src/PowerOperationsModels.jl` (export)
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: `EventModel` (Task 1), `PowerOperationsProblemTemplate` (`src/core/problem_template.jl`).
- Produces: `PowerOperationsProblemTemplate.events::Vector{EventModel}`, `set_event_model!(template::PowerOperationsProblemTemplate, event_model::EventModel)`, `get_event_models(template)::Vector{EventModel}`. Task 4 consumes these.

- [ ] **Step 1: Write the failing test.** Append to `test/test_events.jl`:

```julia
@testset "Template-level event attachment" begin
    template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
    @test isempty(get_event_models(template))
    em = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    set_event_model!(template, em)
    @test length(get_event_models(template)) == 1
    @test get_event_models(template)[1] === em
    # Same event model instance can't be attached twice
    @test_throws ErrorException set_event_model!(template, em)
end
```

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL with `UndefVarError: get_event_models` or MethodError on `set_event_model!`.

- [ ] **Step 3: Implement.** In `src/core/problem_template.jl`:

Add `events::Vector{<:Any}`? No — the struct is declared before `EventModel` exists in include order (`core/` is included before `event_models/`).
Type the field as `Vector{IOM.AbstractEventModel}` (IOM abstract, already loaded):

```julia
mutable struct PowerOperationsProblemTemplate <: IOM.AbstractProblemTemplate
    network_model::NetworkModel{<:AbstractNetworkModel}
    devices::DevicesModelContainer
    branches::BranchModelContainer
    services::ServicesModelContainer
    events::Vector{IOM.AbstractEventModel}
    function PowerOperationsProblemTemplate(
        network::NetworkModel{T},
    ) where {T <: AbstractNetworkModel}
        new(
            network,
            DevicesModelContainer(),
            BranchModelContainer(),
            ServicesModelContainer(),
            Vector{IOM.AbstractEventModel}(),
        )
    end
end
```

Below the existing accessors (`get_device_models` etc.) add:

```julia
get_event_models(template::PowerOperationsProblemTemplate) = template.events

"""
    set_event_model!(template::PowerOperationsProblemTemplate, event_model)

Attach an outage-event model to the template. At build time the event is validated,
its `attribute_device_map` is populated from the system's supplemental attributes, and
it is distributed to every matching `DeviceModel`.
"""
function set_event_model!(
    template::PowerOperationsProblemTemplate,
    event_model::IOM.AbstractEventModel,
)
    if any(e -> e === event_model, template.events)
        error("This event model is already attached to the template")
    end
    push!(template.events, event_model)
    return
end
```

Check whether `Base.isempty(template::PowerOperationsProblemTemplate)` should consider events: it exists at `src/core/problem_template.jl` (checks devices/branches/services) — leave it unchanged; a template with only events and no device models is still "empty" for build purposes.

- [ ] **Step 4: Export.** Add `export get_event_models` to the Task 1 export block (`set_event_model!` was exported in Task 1).
- [ ] **Step 5: Run the test to verify it passes.** Expected: PASS.
- [ ] **Step 6:** Formatter.

---

### Task 4: Build-time discovery and time-series validation

**Files:**
- Modify: `src/operation/template_validation.jl`
- Create: `test/test_utils/events_test_utils.jl`
- Modify: `test/includes.jl` (only if test_utils files are explicitly included there — check `grep -n "test_utils" test/includes.jl`; mirror how `add_branch_rating_time_series.jl` is included)
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: Tasks 1–3 symbols; `PSY.get_supplemental_attributes(T, sys)`, `PSY.get_associated_components(sys, attribute)` (verified present in psy6 `src/get_components_interface.jl:70`), `PSY.add_supplemental_attribute!`, `IS.get_uuid`, `IOM.set_event_model!(::DeviceModel, key, event)`, `get_model(template, type)`.
- Produces: `_build_device_model_events!(template, sys)` (internal, called from `validate_template_impl!`), `_validate_event_timeseries_data(sys, event, event_model)` (internal), test helper `attach_fixed_forced_outage!(sys, device; ts_name = "outage_profile")`.

- [ ] **Step 1: Write the test helper.** Create `test/test_utils/events_test_utils.jl`:

```julia
# Attaches a FixedForcedOutage supplemental attribute to `device` and a 0/1
# SingleTimeSeries named `ts_name` to the attribute. Returns the attribute.
# Adapted from PSI test/test_utils/events_simulation_utils.jl (build-relevant part only).
function attach_fixed_forced_outage!(
    sys::PSY.System,
    device::PSY.Device;
    ts_name = "outage_profile",
    outage_profile = nothing,
)
    outage = PSY.FixedForcedOutage(; outage_status = 0.0)
    PSY.add_supplemental_attribute!(sys, device, outage)
    resolution = PSY.get_time_series_resolution(sys)
    initial_time = PSY.get_forecast_initial_timestamp(sys)
    horizon_count = PSY.get_forecast_horizon(sys)
    if isnothing(outage_profile)
        outage_profile = zeros(horizon_count)  # 0 = available for the whole horizon
    end
    ts_data = TimeSeries.TimeArray(
        range(initial_time; length = length(outage_profile), step = resolution),
        outage_profile,
    )
    ts = PSY.SingleTimeSeries(; name = ts_name, data = ts_data)
    PSY.add_time_series!(sys, outage, ts)
    return outage
end
```

Verify the psy6 accessor names compile (`PSY.get_time_series_resolution`, `PSY.get_forecast_initial_timestamp`, `PSY.get_forecast_horizon`); if a name errors, find the psy6 equivalent with `grep -rn "forecast_initial_timestamp\|get_forecast_horizon" ~/sienna/psy6/PowerSystems.jl/src/PowerSystems.jl` and substitute.
Include the helper the same way sibling `test/test_utils/*.jl` files are included (they are loaded by `test/includes.jl`; confirm and mirror).

- [ ] **Step 2: Write the failing tests.** Append to `test/test_events.jl`:

```julia
@testset "Event discovery and validation at build" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    outage = attach_fixed_forced_outage!(sys, thermal)

    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:outage_status => "outage_profile"),
    )
    set_event_model!(template, em)

    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) == IOM.ModelBuildStatus.BUILT

    # Discovery populated the map: attribute uuid -> device type -> names
    map_ = get_attribute_device_map(em)
    uuid = IS.get_uuid(outage)
    @test haskey(map_, uuid)
    @test map_[uuid][PSY.ThermalStandard] == Set([PSY.get_name(thermal)])

    # The caller's template DeviceModels were not mutated (build-copy isolation)
    caller_dm = get_model(template, PSY.ThermalStandard)
    @test isempty(IOM.get_events(caller_dm))
end

@testset "Event validation errors" begin
    sys_clean = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:outage_status => "outage_profile"),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys_clean; optimizer = HiGHS_optimizer)
    # No supplemental attributes in the system -> loud build failure
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED

    # Unknown mapping key rejected
    sys2 = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal2 = first(PSY.get_components(PSY.ThermalStandard, sys2))
    attach_fixed_forced_outage!(sys2, thermal2)
    template2 = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em_bad = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:not_a_parameter => "outage_profile"),
    )
    set_event_model!(template2, em_bad)
    model2 = DecisionModel(template2, sys2; optimizer = HiGHS_optimizer)
    @test build!(model2; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED

    # FixedForcedOutage requires :outage_status mapping
    sys3 = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal3 = first(PSY.get_components(PSY.ThermalStandard, sys3))
    attach_fixed_forced_outage!(sys3, thermal3)
    template3 = get_thermal_dispatch_template_network(NetworkModel(CopperPlateNetworkModel))
    em_nomapping = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
    set_event_model!(template3, em_nomapping)
    model3 = DecisionModel(template3, sys3; optimizer = HiGHS_optimizer)
    @test build!(model3; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.FAILED
end
```

Adjust the PSB system name if `c_sys5_uc` is not what POM tests use — check `grep -rn 'build_system' test/test_device_thermal_generation_constructors.jl | head -3` and use the same fixture family.
`build!` failure semantics: if `build!` throws instead of returning `FAILED`, assert with `@test_throws` — match whatever `test/test_model_decision.jl` does for build failures.
The build-copy isolation assertion assumes `build!` finalizes a copied template (mirroring Feature B's `_build_device_model_outages!` isolation).
If it fails because POM finalizes the caller's template in place for events too, check how `_build_device_model_outages!` achieves isolation (`src/operation/template_validation.jl:456-544`) and route event distribution through the same copy.

- [ ] **Step 3: Run to verify failure.** Expected: first testset FAILS (map not populated — discovery doesn't exist yet; the build may even succeed with events silently ignored, which is exactly the gap).

- [ ] **Step 4: Implement discovery + validation.** In `src/operation/template_validation.jl`, after `_build_device_model_outages!(template, system)` (line ~116, inside `validate_template_impl!`), add:

```julia
    _build_device_model_events!(template, system)
```

Then add at the end of the file (adapted from PSI `src/simulation/simulation_sequence.jl:215-296`, re-hosted at template level; the per-simulation-model map key is dropped):

```julia
#################################################################################
# Outage-event discovery and validation (time-series outage events; distinct
# from the security-constrained `_build_device_model_outages!` above)
#################################################################################

"""
For each event model attached to the template: validate its time-series mapping,
populate `attribute_device_map` (attribute UUID → concrete device type → device names)
from the system's supplemental attributes, and distribute the event model to every
`DeviceModel` in the template whose device type carries the attribute and supports
events.
"""
function _build_device_model_events!(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
)
    for event_model in get_event_models(template)
        event_type = get_event_type(event_model)
        if isempty(PSY.get_supplemental_attributes(event_type, sys))
            error(
                "There are no supplemental attributes of type $event_type in the system. \
                 Add the outage data to the system or remove the event model from the \
                 template.",
            )
        end
        for event in PSY.get_supplemental_attributes(event_type, sys)
            _validate_event_timeseries_data(sys, event, event_model)
            event_uuid = IS.get_uuid(event)
            attribute_device_map = get_attribute_device_map(event_model)
            attribute_device_map[event_uuid] = Dict{DataType, Set{String}}()
            device_types_with_attribute = Set{DataType}()
            for device in PSY.get_associated_components(sys, event)
                dtype = typeof(device)
                if !supports_events(dtype)
                    @warn "Device $(PSY.get_name(device)) of type $dtype carries a \
                           $event_type attribute but the type does not support events; \
                           it will not be modeled." _group =
                        IOM.LOG_GROUP_MODELS_VALIDATION
                    continue
                end
                push!(device_types_with_attribute, dtype)
                name_set = get!(
                    attribute_device_map[event_uuid],
                    dtype,
                    Set{String}(),
                )
                push!(name_set, PSY.get_name(device))
            end
            for device_type in device_types_with_attribute
                device_model = get_model(template, device_type)
                if device_model === nothing
                    @warn "Devices of type $device_type carry a $event_type attribute \
                           but the template has no DeviceModel for that type; the event \
                           will not be modeled for them." _group =
                        IOM.LOG_GROUP_MODELS_VALIDATION
                    continue
                end
                key = EventKey(event_type, device_type)
                if !haskey(IOM.get_events(device_model), key)
                    IOM.set_event_model!(device_model, key, event_model)
                end
            end
        end
    end
    return
end

function _validate_event_timeseries_data(
    sys::PSY.System,
    event::PSY.Contingency,
    event_model::EventModel,
)
    for (k, v) in event_model.timeseries_mapping
        if !isnothing(v)
            try
                PSY.get_time_series(IS.SingleTimeSeries, event, v)
            catch
                device_names =
                    PSY.get_name.(PSY.get_associated_components(sys, event))
                error(
                    "Event $event belonging to devices $device_names is missing a \
                     time series with name $v",
                )
            end
        end
        if !haskey(get_empty_timeseries_mapping(typeof(event)), k)
            error(
                "Key $k passed as part of the event time series mapping does not \
                 correspond to a parameter.",
            )
        end
        if k == :outage_status && isnothing(v)
            error(
                "FixedForcedOutage requires a timeseries mapping for the \
                 :outage_status parameter",
            )
        end
    end
    return
end
```

Verification notes for the implementer:
`get_model(template, device_type)` — confirm the accessor name POM/IOM uses to fetch a `DeviceModel` from a template by component type (`grep -rn "function get_model" src/ | head -3`, else check IOM); adjust the call if it is `get_model(template.devices, ...)` or similar.
`IOM.LOG_GROUP_MODELS_VALIDATION` — confirm the constant exists (`grep -rn "LOG_GROUP" src/operation/template_validation.jl | head -2`) and reuse whatever group that file already logs under.
`PSY.get_time_series(IS.SingleTimeSeries, event, v)` — supplemental attributes carry time series through IS; if the psy6 method signature differs, check `grep -rn "get_time_series" ~/sienna/psy6/InfrastructureSystems.jl/src/supplemental_attributes.jl` and adapt.

- [ ] **Step 5: Run the tests.** Both new testsets pass. Also re-run Task 1–3 testsets (whole `test/test_events.jl`).
- [ ] **Step 6: Initial-conditions exclusion test.** POM builds an initialization problem from a reduced template (see `src/initial_conditions/initialization.jl`).
Verify events are not copied into it: read the template-construction code there; if it copies device models wholesale (including `events`), clear events on the IC copy and add a code comment stating IC problems never model outage events.
Append to `test/test_events.jl` a testset asserting the built model's IC container has no event parameters:

```julia
@testset "Events excluded from initialization problem" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    template = get_thermal_standard_uc_template()
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:outage_status => "outage_profile"),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) == IOM.ModelBuildStatus.BUILT
    ic_container = IOM.get_initial_conditions_optimization_container(model)
    ic_keys = IOM.get_parameter_keys(ic_container)
    @test !any(k -> IOM.get_entry_type(k) <: EventParameter, ic_keys)
end
```

Adjust helper names to what exists: template helper (`grep -n "get_thermal_standard_uc_template\|get_thermal_dispatch_template" test/test_utils/operations_problem_templates.jl`), IC container accessor and key listing (`grep -rn "initial_conditions_optimization_container\|get_parameter_keys" src/ test/ | head -5`).
This testset requires Task 5's parameter machinery to be meaningful (before Task 5, no event parameters exist anywhere, so it passes vacuously); re-run it after Task 5 and confirm it still passes.

- [ ] **Step 7:** `git add -N test/test_utils/events_test_utils.jl`; formatter; run the full events file plus `julia --project=test test/runtests.jl test_problem_template` to confirm no Feature-B regression.

---

### Task 4b: IOM type-bound fix (executed in the IOM clone)

**Repo:** `/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl`, branch `mb/events-port`. All steps in this task run from that directory.

**Files:**
- Modify: `src/core/parameter_container.jl:83-101`, `src/common_models/add_param_container.jl:85-103`
- Test: add a testset to the IOM test file that covers `add_param_container!` (find it: `grep -rln "add_param_container!" test/ | head -3`; use the file the existing parameter-container tests live in)

**Why:** `PSY.Contingency <: SupplementalAttribute <: IS.InfrastructureSystemsType`, which is not under `IS.InfrastructureSystemsComponent`.
IOM's event overload of `add_param_container!` and `EventParametersAttributes` bound the contingency slot as `IS.InfrastructureSystemsComponent`, so any call with a real contingency type is a MethodError.
The `affected_devices::Vector{T}` field has zero readers in IOM (`grep -rn "affected_devices" src/ test/` returns only the definition) and is dropped.

**Interfaces:**
- Produces: `add_param_container!(container, ::Type{T<:EventParameter}, ::Type{U<:IS.InfrastructureSystemsComponent}, ::Type{V<:IS.SupplementalAttribute}, axs...)` and `EventParametersAttributes{T<:IS.SupplementalAttribute, U<:ParameterType}`. POM Task 5 calls the former with `V = PSY.FixedForcedOutage`.

- [ ] **Step 1: Write the failing test.** In the IOM test file that covers parameter containers, add (mirroring the file's existing mock/container fixtures — reuse whatever mock `OptimizationContainer` factory its sibling testsets use):

```julia
@testset "Event parameter container accepts supplemental-attribute contingency types" begin
    container = # same mock container construction as the surrounding testsets
    IOM.add_param_container!(
        container,
        MockEventParameter,
        MockThermalGen,
        MockContingency,
        ["dev1", "dev2"],
        1:24,
    )
    key = IOM.ParameterKey(MockEventParameter, MockThermalGen)
    pc = IOM.get_parameter(container, key)
    @test IOM.get_attributes(pc) isa IOM.EventParametersAttributes{MockContingency}
end
```

Supporting mock types: check `test/mocks/` for an existing `MockThermalGen` (it exists per IOM conventions) and for any existing `SupplementalAttribute`/`EventParameter` mocks; if absent, add to the mocks file:

```julia
struct MockContingency <: IS.SupplementalAttribute end
struct MockEventParameter <: InfrastructureOptimizationModels.EventParameter end
```

Adjust accessor names (`get_parameter`, `get_attributes`, `ParameterKey` arity) to match the file's surrounding testsets — copy their exact style.

- [ ] **Step 2: Run to verify it fails.**

Run: `julia --project=test test/runtests.jl`
Expected: the new testset FAILS with a MethodError (no `add_param_container!` method matching `MockContingency`, which is not an `IS.InfrastructureSystemsComponent`).
If IOM's runner supports file filtering, run just the affected file per its README/runtests conventions.

- [ ] **Step 3: Apply the fix.** In `src/core/parameter_container.jl:83-101` replace the three `EventParametersAttributes` definitions with:

```julia
"""
Attributes for event (contingency) parameters. `T` is the `IS.SupplementalAttribute`
subtype describing the contingency and `U` is the parameter type stored in the container.
"""
struct EventParametersAttributes{
    T <: IS.SupplementalAttribute,
    U <: ParameterType,
} <: ParameterAttributes end

function EventParametersAttributes(
    ::Type{T},
    ::Type{U},
) where {T <: IS.SupplementalAttribute, U <: ParameterType}
    return EventParametersAttributes{T, U}()
end

function get_param_type(
    ::EventParametersAttributes{T, U},
) where {T <: IS.SupplementalAttribute, U <: ParameterType}
    return U
end
```

In `src/common_models/add_param_container.jl:96` change the event overload's where-clause bound from `V <: IS.InfrastructureSystemsComponent` to `V <: IS.SupplementalAttribute` (the body is unchanged).

- [ ] **Step 4: Run the IOM suite.**

Run: `julia --project=test test/runtests.jl`
Expected: PASS including the new testset and Aqua checks.

- [ ] **Step 5: IOM formatter and tracking.**

```bash
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
git add -N .   # new test/mock files only; leave everything unstaged, never commit
git status --short
```

Report the diff summary; the user opens the IOM PR from `mb/events-port`.

- [ ] **Step 6: Bridge the fix into POM's test environment** (back in the POM repo). POM's `[sources]` pins IOM to the GitHub `main` branch, which does not have this fix yet; override the resolution locally (Manifest-only — `Project.toml` is untouched):

Run: `julia --project=test -e 'using Pkg; Pkg.develop(path="/Users/mbossart/sienna/psy6/InfrastructureOptimizationModels.jl"); using PowerOperationsModels; println("LOADED")'`
Expected: resolves and prints `LOADED`.
`test/Manifest.toml` is not checked in, so this override is invisible to git and to CI; Task 11 verifies the upstream state before final sign-off.

---

### Task 5: Event parameters and balance injection — `src/event_models/event_arguments.jl`

> **Gate:** Task 4b must be complete and its Step 6 `Pkg.develop` bridge active, otherwise `_add_parameters!` fails with a MethodError on `add_param_container!`.

**Files:**
- Create: `src/event_models/event_arguments.jl`
- Modify: `src/PowerOperationsModels.jl` (include), `test/test_utils/mock_operation_models.jl` (enable `add_event_model`)
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: Tasks 1–2 symbols; IOM's `add_param_container!(container, ::Type{T<:EventParameter}, ::Type{U}, ::Type{V}, axs...)`; `IOM.get_multiplier_array_data`, `IOM.get_parameter_array_data`, `IOM._set_multiplier_at!`, `IOM._set_parameter_at!` (existing POM reaches); `_balance_expression_targets` and `_apply_term_to_targets!` (`src/common_models/add_to_expression.jl:30-98`); `get_rebuild_model`, `get_settings`, `has_container_key` (same usage as `src/common_models/add_parameters.jl:17-46`).
- Produces: `add_parameters!(container, ::Type{T}, devices, device_model, event_model::EventModel)`, `_add_parameters!(container, ::T<:EventParameter, devices, device_model, event_model)`, `add_to_expression!(container, ::Type{T<:SystemBalanceExpressions}, ::Type{U<:EventParameter}, devices, device_model, network_model)`, and the specific `add_event_arguments!` methods that override the no-op stub in `src/core/feedforward_interface.jl:51-58`. Tasks 6–9 rely on these.

- [ ] **Step 1: Write the failing test.** Append to `test/test_events.jl`:

```julia
@testset "Event parameters via mock construct - ThermalStandard UC" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    model = PSI.mock_decision_model_from_system_name("c_sys5_uc")  # see note below
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, AvailableStatusParameter(), PSY.ThermalStandard),
    )
    @test !isnothing(
        IOM.get_parameter(
            container,
            AvailableStatusChangeCountdownParameter(),
            PSY.ThermalStandard,
        ),
    )
    param_array =
        IOM.get_parameter_array(container, AvailableStatusParameter(), PSY.ThermalStandard)
    # Initial availability is 1.0 for every (device, t)
    @test all(IOM.jump_value.(param_array.data) .== 1.0)
end
```

Note: `mock_decision_model_from_system_name` is a placeholder for however existing POM tests build a `DecisionModel{MockOperationProblem}` — copy the exact construction from an existing `mock_construct_device!` caller (`grep -n -B5 "mock_construct_device!" test/test_device_source_constructors.jl | head -12`) and use the same helper (likely `PSI.DecisionModel(MockOperationProblem, ...)`-style via a `mock_*` factory in `test/test_utils/mock_operation_models.jl`).
Likewise confirm accessor names `IOM.get_parameter`, `IOM.get_parameter_array`, `IOM.jump_value` against usage in existing POM tests (`grep -rn "get_parameter_array\|jump_value" test/test_utils/model_checks.jl | head -5`) and match.

- [ ] **Step 2: Run to verify failure.** Expected: FAIL — `mock_construct_device!` currently errors when `add_event_model = true` ("Event models are not supported in InfrastructureOptimizationModels...").

- [ ] **Step 3: Implement the parameter machinery.** Create `src/event_models/event_arguments.jl` with:

```julia
#################################################################################
# Event parameter creation (ArgumentConstructStage)
#################################################################################

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    device_model::DeviceModel{D, W},
    event_model::EventModel{V, X},
) where {
    T <: ParameterType,
    U <: Vector{D},
    V <: PSY.Contingency,
    W <: AbstractDeviceFormulation,
    X <: AbstractEventCondition,
} where {D <: PSY.Component}
    if get_rebuild_model(get_settings(container)) && has_container_key(container, T, D)
        return
    end
    _add_parameters!(container, T(), devices, device_model, event_model)
    return
end

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    devices::Vector{U},
    device_model::DeviceModel{U, W},
    event_model::EventModel{V, X},
) where {
    T <: EventParameter,
    U <: PSY.Component,
    V <: PSY.Contingency,
    W <: AbstractDeviceFormulation,
    X <: AbstractEventCondition,
}
    @debug "adding" T U V _group = IOM.LOG_GROUP_OPTIMIZATION_CONTAINER
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(
        container,
        T,
        U,
        V,
        PSY.get_name.(devices),
        time_steps,
    )
    jump_model = get_jump_model(container)
    parent_mult = IOM.get_multiplier_array_data(parameter_container)
    parent_param = IOM.get_parameter_array_data(parameter_container)
    for (i, d) in enumerate(devices)
        ini_val = get_initial_parameter_value(T(), d, event_model)
        IOM._set_multiplier_at!(
            parent_mult,
            get_parameter_multiplier(T(), d, event_model),
            i,
        )
        for t in time_steps
            IOM._set_parameter_at!(parent_param, jump_model, ini_val, i, t)
        end
    end
    return
end

#################################################################################
# Offset parameters into the system balance expressions.
# One method for every network family: `_balance_expression_targets` resolves the
# system/area/nodal targets per network model (this replaces PSI's four
# per-network methods).
#################################################################################

function add_to_expression!(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    device_model::DeviceModel{V, W},
    network_model::NetworkModel{X},
) where {
    T <: SystemBalanceExpressions,
    U <: EventParameter,
    V <: PSY.StaticInjection,
    W <: AbstractDeviceFormulation,
    X <: AbstractNetworkModel,
}
    param_array = get_parameter_array(container, U(), V)
    multiplier = get_parameter_multiplier_array(container, U(), V)
    time_steps = get_time_steps(container)
    for d in devices
        targets = _balance_expression_targets(container, T, network_model, d)
        name = PSY.get_name(d)
        for t in time_steps
            _apply_term_to_targets!(targets, param_array[name, t], multiplier[name, t], t)
        end
    end
    return
end

#################################################################################
# add_event_arguments! — overrides the no-op stub in core/feedforward_interface.jl
# for the injector families. No-ops when the DeviceModel has no events attached.
#################################################################################

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel,
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        for p_type in [AvailableStatusChangeCountdownParameter, AvailableStatusParameter]
            add_parameters!(
                container,
                p_type,
                devices_with_attributes,
                device_model,
                event_model,
            )
        end
    end
    return
end
```

Verify accessor availability: `get_parameter_array(container, ::EventParameter, ::Type)` and `get_parameter_multiplier_array(container, ::EventParameter, ::Type)` — check `grep -rn "get_parameter_multiplier_array" src/ | head -3`; if POM does not already use them, they are IOM exports (same names PSI used) — confirm with `julia --project=test -e 'using InfrastructureOptimizationModels; println(isdefined(InfrastructureOptimizationModels, :get_parameter_multiplier_array))'`.
`get_entry_type(key)` here is the Task 1 method for `EventKey`.

- [ ] **Step 4: Wire the include.** In `src/PowerOperationsModels.jl`, find the last `include("common_models/...")` line and insert after it:

```julia
include("event_models/event_arguments.jl")
```

- [ ] **Step 5: Enable the mock path.** In `test/test_utils/mock_operation_models.jl:116-133`, replace the `if add_event_model ... error(...) end` block with (adapted from PSI `test/test_utils/mock_operation_models.jl:114-131`, but using the real `set_event_model!` API instead of assigning the `events` field):

```julia
    if add_event_model
        sys = IOM.get_system(problem)
        device_type = IOM.get_component_type(model)
        event_device = first(PSY.get_components(device_type, sys))
        transition_data = PSY.FixedForcedOutage(; outage_status = 0.0)
        PSY.add_supplemental_attribute!(sys, event_device, transition_data)
        mock_event_key = EventKey(PSY.FixedForcedOutage, device_type)
        mock_event_model = EventModel(PSY.FixedForcedOutage, ContinuousCondition())
        set_event_model!(model, mock_event_key, mock_event_model)
    end
```

Confirm `IOM.get_component_type(model)` works on a `DeviceModel` (check `grep -rn "get_component_type" src/operation/template_validation.jl | head -2` for the established accessor and reuse it).

- [ ] **Step 6: Run the Task 5 test.** Expected: PASS. Also rerun the whole `test/test_events.jl` and `julia --project=test test/runtests.jl test_device_thermal_generation_constructors` (no regressions from the mock change).
- [ ] **Step 7:** Formatter.

---

### Task 6: Load and FixedOutput argument variants (offset parameters)

**Files:**
- Modify: `src/event_models/event_arguments.jl`
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: Task 5 machinery; load formulations `StaticPowerLoad`, `PowerLoadDispatch`, `PowerLoadInterruption` (`src/core/formulations.jl:65-75`); `FixedOutput` (IOM); network abstracts `AbstractActivePowerModel`, `AbstractReactivePowerNetworkModel` (`src/PowerOperationsModels.jl:33-41`); `ActivePowerBalance`, `ReactivePowerBalance`.
- Produces: `add_event_arguments!` methods for loads and `FixedOutput` that additionally create `ActivePowerOffsetParameter` (and `ReactivePowerOffsetParameter` on reactive-capable networks) and inject them into the balance expressions.

- [ ] **Step 1: Write the failing test.** Append to `test/test_events.jl`:

```julia
@testset "Event arguments for loads add offset parameters" begin
    device_model = DeviceModel(PSY.PowerLoad, StaticPowerLoad)
    model = # same mock DecisionModel construction as the Task 5 testset, system "c_sys5_uc"
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_parameter(container, ActivePowerOffsetParameter(), PSY.PowerLoad),
    )
    # CopperPlate mock network -> active power balance expression contains the offset param.
    # AvailableStatus/Countdown params exist too.
    @test !isnothing(
        IOM.get_parameter(container, AvailableStatusParameter(), PSY.PowerLoad),
    )
end
```

- [ ] **Step 2: Run to verify failure.** Expected: FAIL — the generic `StaticInjection` method from Task 5 runs (no offset parameter is created), so `get_parameter` for `ActivePowerOffsetParameter` errors/returns nothing.

- [ ] **Step 3: Implement.** Append to `src/event_models/event_arguments.jl` four methods (adapted from PSI `contingency_arguments.jl:30-230`; PSI's `PM.AbstractActivePowerModel` → `AbstractActivePowerModel`, `PM.AbstractPowerModel` → `AbstractReactivePowerNetworkModel`):

```julia
const _EventLoadFormulations =
    Union{StaticPowerLoad, PowerLoadDispatch, PowerLoadInterruption}

function _add_event_offset_arguments!(
    container::OptimizationContainer,
    devices_with_attributes::Vector{U},
    device_model::DeviceModel,
    network_model::NetworkModel,
    event_model::EventModel,
    with_reactive::Bool,
) where {U <: PSY.StaticInjection}
    for p_type in [AvailableStatusChangeCountdownParameter, AvailableStatusParameter]
        add_parameters!(
            container,
            p_type,
            devices_with_attributes,
            device_model,
            event_model,
        )
    end
    add_parameters!(
        container,
        ActivePowerOffsetParameter,
        devices_with_attributes,
        device_model,
        event_model,
    )
    add_to_expression!(
        container,
        ActivePowerBalance,
        ActivePowerOffsetParameter,
        devices_with_attributes,
        device_model,
        network_model,
    )
    if with_reactive
        add_parameters!(
            container,
            ReactivePowerOffsetParameter,
            devices_with_attributes,
            device_model,
            event_model,
        )
        add_to_expression!(
            container,
            ReactivePowerBalance,
            ReactivePowerOffsetParameter,
            devices_with_attributes,
            device_model,
            network_model,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: _EventLoadFormulations,
} where {U <: PSY.PowerLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            false,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: _EventLoadFormulations,
} where {U <: PSY.PowerLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            true,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, FixedOutput},
    network_model::NetworkModel{<:AbstractActivePowerModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            false,
        )
    end
    return
end

function add_event_arguments!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, FixedOutput},
    network_model::NetworkModel{<:AbstractReactivePowerNetworkModel},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
} where {U <: PSY.StaticInjection}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        _add_event_offset_arguments!(
            container,
            devices_with_attributes,
            device_model,
            network_model,
            event_model,
            true,
        )
    end
    return
end
```

The `_add_event_offset_arguments!` helper is a POM addition (PSI repeats the body four times); it is private to this file.

- [ ] **Step 4: Ambiguity check.** The load methods overlap the Task 5 generic (`U<:StaticInjection`, unconstrained network) and the `FixedOutput` methods overlap both.

Run: `julia --project=test -e 'using Test, PowerOperationsModels; println(length(detect_ambiguities(PowerOperationsModels)))'`
Expected: same count as before this task (measure on `main` first if unsure; new count must not increase).
If new ambiguities appear between the load and `FixedOutput` methods (a `DeviceModel{PowerLoad, FixedOutput}` matches both), add tie-breaker methods `add_event_arguments!(container, devices, ::DeviceModel{U, FixedOutput}, ::NetworkModel{<:AbstractActivePowerModel}) where {U <: PSY.PowerLoad}` (and the reactive twin) that forward to the `FixedOutput` behavior.

- [ ] **Step 5: Run the test to verify it passes.** Expected: PASS.
- [ ] **Step 6:** Formatter; rerun `test/test_events.jl` in full.

---

### Task 7: Core event constraints — `src/event_models/event_constraints.jl`

**Files:**
- Create: `src/event_models/event_constraints.jl`
- Modify: `src/PowerOperationsModels.jl` (include + constraint exports)
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: `ActivePowerOutageConstraint`, `ReactivePowerOutageConstraint` (`src/core/constraints.jl:631-633`); `add_parameterized_upper_bound_range_constraints` (same call shape as `src/static_injector_models/hydro_generation.jl:614-622`); `ActivePowerRangeExpressionUB`, `ActivePowerVariable`, `ReactivePowerVariable`; `has_service_model` (`src/PowerOperationsModels.jl:160`); `add_constraints_container!`, `get_parameter_array`, `get_parameter_multiplier_array`, `get_jump_model`, `get_time_steps`.
- Produces: `add_event_constraints!` methods for `PSY.ThermalGen`, `PSY.RenewableGen`, `PSY.ElectricLoad` (× active-only / reactive-capable networks); `add_reactive_power_contingency_constraint(...)` and `_get_reactive_power_upper_bound(device)`. Task 8 reuses `add_reactive_power_contingency_constraint` exactly as named.

- [ ] **Step 1: Write the failing test.** Append to `test/test_events.jl`:

```julia
@testset "Event constraints - thermal UC counts and coefficients" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    model = # same mock DecisionModel construction as Task 5, system "c_sys5_uc"
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
    cons = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.ThermalStandard,
    )
    n_thermal_with_event = 1  # mock attaches the outage to exactly one device
    time_steps = IOM.get_time_steps(container)
    @test size(cons)[1] == n_thermal_with_event
    @test size(cons)[2] == length(time_steps)
    # Coefficient check: constraint is expr(p) - ub * status <= 0 with status = 1.0
    # (params are plain Float64 in a non-recurrent build, so the RHS is baked in).
    c1 = JuMP.constraint_object(cons[axes(cons)[1][1], 1])
    @test c1.set isa MOI.LessThan{Float64}
end
```

Confirm `IOM.get_constraint` naming against existing tests (`grep -rn "get_constraint(" test/test_utils/model_checks.jl | head -3`).

- [ ] **Step 2: Run to verify failure.** Expected: FAIL — no `ActivePowerOutageConstraint` container exists (the stub `add_event_constraints!` no-ops).

- [ ] **Step 3: Implement.** Create `src/event_models/event_constraints.jl` (adapted from PSI `contingency_constraints.jl`; network bounds swapped to POM abstracts; **`PSY.SU` added to every convertible getter**):

```julia
#################################################################################
# Event outage constraints (ModelConstructStage). Overrides the no-op stub in
# core/feedforward_interface.jl for the supported injector families.
#################################################################################

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.ThermalGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerRangeExpressionUB,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.ThermalGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerRangeExpressionUB,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.RenewableGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        lhs_type =
            has_service_model(device_model) ? ActivePowerRangeExpressionUB :
            ActivePowerVariable
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            lhs_type,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.RenewableGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        lhs_type =
            has_service_model(device_model) ? ActivePowerRangeExpressionUB :
            ActivePowerVariable
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            lhs_type,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.ElectricLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.ElectricLoad}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

#################################################################################
# Quadratic reactive-power outage constraint: q^2 <= ub * status
#################################################################################

function add_reactive_power_contingency_constraint(
    container::OptimizationContainer,
    ::Type{ReactivePowerOutageConstraint},
    ::Type{ReactivePowerVariable},
    ::Type{AvailableStatusParameter},
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, W},
    ::Type{X},
) where {
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
    X <: AbstractReactivePowerNetworkModel,
}
    array_reactive = get_variable(container, ReactivePowerVariable(), V)
    _add_reactive_power_contingency_constraint_impl!(
        container,
        ReactivePowerOutageConstraint,
        array_reactive,
        AvailableStatusParameter(),
        devices,
        model,
    )
    return
end

function _add_reactive_power_contingency_constraint_impl!(
    container::OptimizationContainer,
    ::Type{ReactivePowerOutageConstraint},
    array_reactive,
    param::AvailableStatusParameter,
    devices::Union{Vector{V}, IS.FlattenIteratorWrapper{V}},
    model::DeviceModel{V, W},
) where {
    V <: PSY.Component,
    W <: AbstractDeviceFormulation,
}
    time_steps = get_time_steps(container)
    names = PSY.get_name.(devices)
    constraint_container = add_constraints_container!(
        container,
        ReactivePowerOutageConstraint(),
        V,
        names,
        time_steps;
        meta = "ub",
    )
    param_array = get_parameter_array(container, param, V)
    jump_model = get_jump_model(container)
    for device in devices, t in time_steps
        name = PSY.get_name(device)
        ub = _get_reactive_power_upper_bound(device)
        constraint_container[name, t] = JuMP.@constraint(
            jump_model,
            (array_reactive[name, t])^2 <= (ub * param_array[name, t])
        )
    end
    return
end

_get_reactive_power_upper_bound(device::PSY.StaticInjection) = begin
    limits = PSY.get_reactive_power_limits(device, PSY.SU)
    max(limits.max^2, limits.min^2)
end

_get_reactive_power_upper_bound(device::PSY.ElectricLoad) =
    PSY.get_max_reactive_power(device, PSY.SU)^2
```

- [ ] **Step 4: Wire include and exports.** Add after the Task 5 include:

```julia
include("event_models/event_constraints.jl")
```

Check whether `ActivePowerOutageConstraint`/`ReactivePowerOutageConstraint`/`ActivePowerPumpOutageConstraint`/the four event parameter types are already exported (`grep -n "OutageConstraint\|AvailableStatus\|OffsetParameter" src/PowerOperationsModels.jl`); export any that are missing.

- [ ] **Step 5: Run the test.** Expected: PASS.
Then add and run two more testsets following the identical pattern: renewable (`DeviceModel(PSY.RenewableDispatch, RenewableFullDispatch)`, expect `ActivePowerVariable` LHS since no service model) and load (`DeviceModel(PSY.PowerLoad, PowerLoadDispatch)`, expect the constraint on `ActivePowerVariable`).
Use the fixture each device type exists in (`c_sys5_re` for renewables, `c_sys5` for loads — confirm with `grep -rn "c_sys5_re" test/test_device_renewable_generation_constructors.jl | head -2`).
- [ ] **Step 6:** Formatter; ambiguity count check as in Task 6 Step 4.

---

### Task 8: Hydro and storage event constraints

**Files:**
- Modify: `src/event_models/event_constraints.jl`
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: Task 7's `add_reactive_power_contingency_constraint`; `ActivePowerPumpOutageConstraint` (`src/core/constraints.jl:881`), `ActivePowerPumpVariable` (`src/core/variables.jl:667`), `ActivePowerInVariable`, `ActivePowerOutVariable` (storage); `PSY.HydroGen`, `PSY.HydroPumpTurbine`, `PSY.EnergyReservoirStorage`.
- Produces: `add_event_constraints!` for `PSY.HydroGen` (×2 networks), `PSY.HydroPumpTurbine` (×2), `PSY.EnergyReservoirStorage` (×2); helpers `add_pump_turbine_active_power_contingency_constraints!` and `add_input_output_active_power_contingency_constraints!`.

- [ ] **Step 1: Write the failing tests.** Append to `test/test_events.jl`:

```julia
@testset "Event constraints - hydro" begin
    device_model = DeviceModel(PSY.HydroDispatch, HydroDispatchRunOfRiver)
    model = # mock DecisionModel construction, hydro fixture (see note)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
    @test !isnothing(
        IOM.get_constraint(container, ActivePowerOutageConstraint(), PSY.HydroDispatch),
    )
end

@testset "Event constraints - storage" begin
    device_model = DeviceModel(PSY.EnergyReservoirStorage, StorageDispatchWithReserves)
    model = # mock DecisionModel construction, storage fixture (see note)
    mock_construct_device!(model, device_model; add_event_model = true)
    container = IOM.get_optimization_container(model)
    cons_in = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.EnergyReservoirStorage,
        "input",
    )
    cons_out = IOM.get_constraint(
        container,
        ActivePowerOutageConstraint(),
        PSY.EnergyReservoirStorage,
        "output",
    )
    @test !isnothing(cons_in)
    @test !isnothing(cons_out)
end
```

Fixture and formulation notes: find the hydro fixture and formulation names used by `test/test_device_hydro_constructors.jl` (`grep -n "build_system\|DeviceModel(" test/test_device_hydro_constructors.jl | head -6`) and the storage equivalents in `test/test_storage_device_models.jl`-style files (`grep -rn "EnergyReservoirStorage" test/ | head -5`); use the same names.
The meta-string variant of `IOM.get_constraint` (`"input"`/`"output"`) — confirm the accessor arity in `test/test_utils/model_checks.jl` usage; if metas are addressed differently, match it.
If POM has a `PSY.HydroPumpTurbine` formulation and fixture, add a third testset for the pump constraint (`ActivePowerPumpOutageConstraint`); if no fixture exists (`grep -rn "HydroPumpTurbine" test/ | head -3` empty), note it in the test file as uncovered and still implement the methods.

- [ ] **Step 2: Run to verify failure.** Expected: FAIL (constraints don't exist — the generic stub no-ops for hydro/storage).

- [ ] **Step 3: Implement.** Append to `src/event_models/event_constraints.jl` (ported from HPS/SSS `src/contingency_model.jl` with `PSY.SU` unit fixes and POM network abstracts; the `@assert !isempty` in SSS becomes a loud `error` to match the rest of the file):

```julia
#################################################################################
# Hydro (ported from HydroPowerSimulations src/contingency_model.jl)
#################################################################################

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.HydroGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerRangeExpressionUB,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.HydroGen}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_parameterized_upper_bound_range_constraints(
            container,
            ActivePowerOutageConstraint,
            ActivePowerRangeExpressionUB,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end
```

Note on the HydroGen active-power LHS: HPS uses `ActivePowerRangeExpressionUB`.
If a targeted hydro formulation in POM does not create that expression, the constraint call will throw at build — run the Task 8 hydro testset against each hydro formulation POM's constructors wire (`grep -n "DeviceModel{" src/static_injector_models/hydrogeneration_constructor.jl | head`), and for any formulation without the UB range expression use `ActivePowerVariable` as the LHS in a formulation-specific method, mirroring the renewable pattern.

```julia
function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.HydroPumpTurbine}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_pump_turbine_active_power_contingency_constraints!(
            container,
            devices_with_attributes,
            device_model,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.HydroPumpTurbine}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_pump_turbine_active_power_contingency_constraints!(
            container,
            devices_with_attributes,
            device_model,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_pump_turbine_active_power_contingency_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
} where {U <: PSY.HydroPumpTurbine}
    names = PSY.get_name.(devices)
    time_steps = get_time_steps(container)
    array_active_power = get_variable(container, ActivePowerVariable(), U)
    array_active_power_pump = get_variable(container, ActivePowerPumpVariable(), U)
    constraint_active_power = add_constraints_container!(
        container,
        ActivePowerOutageConstraint(),
        U,
        names,
        time_steps,
    )
    constraint_active_power_pump = add_constraints_container!(
        container,
        ActivePowerPumpOutageConstraint(),
        U,
        names,
        time_steps,
    )
    param_array = get_parameter_array(container, AvailableStatusParameter(), U)
    jump_model = get_jump_model(container)
    for device in devices, t in time_steps
        name = PSY.get_name(device)
        ub_active_power = PSY.get_active_power_limits(device, PSY.SU).max
        constraint_active_power[name, t] = JuMP.@constraint(
            jump_model,
            array_active_power[name, t] <= ub_active_power * param_array[name, t]
        )
        ub_active_power_pump = PSY.get_active_power_limits_pump(device, PSY.SU).max
        constraint_active_power_pump[name, t] = JuMP.@constraint(
            jump_model,
            array_active_power_pump[name, t] <=
            ub_active_power_pump * param_array[name, t]
        )
    end
    return
end

#################################################################################
# Storage (ported from StorageSystemsSimulations src/contingency_model.jl)
#################################################################################

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractActivePowerModel,
} where {U <: PSY.EnergyReservoirStorage}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_input_output_active_power_contingency_constraints!(
            container,
            devices_with_attributes,
            device_model,
        )
    end
    return
end

function add_event_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
    network_model::NetworkModel{W},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
    W <: AbstractReactivePowerNetworkModel,
} where {U <: PSY.EnergyReservoirStorage}
    for (key, event_model) in get_events(device_model)
        event_type = get_entry_type(key)
        devices_with_attributes =
            [d for d in devices if PSY.has_supplemental_attributes(d, event_type)]
        isempty(devices_with_attributes) &&
            error("no devices found with a supplemental attribute for event $event_type")
        add_input_output_active_power_contingency_constraints!(
            container,
            devices_with_attributes,
            device_model,
        )
        add_reactive_power_contingency_constraint(
            container,
            ReactivePowerOutageConstraint,
            ReactivePowerVariable,
            AvailableStatusParameter,
            devices_with_attributes,
            device_model,
            W,
        )
    end
    return
end

function add_input_output_active_power_contingency_constraints!(
    container::OptimizationContainer,
    devices::T,
    device_model::DeviceModel{U, V},
) where {
    T <: Union{Vector{U}, IS.FlattenIteratorWrapper{U}},
    V <: AbstractDeviceFormulation,
} where {U <: PSY.EnergyReservoirStorage}
    names = PSY.get_name.(devices)
    time_steps = get_time_steps(container)
    array_in = get_variable(container, ActivePowerInVariable(), U)
    array_out = get_variable(container, ActivePowerOutVariable(), U)
    constraint_input = add_constraints_container!(
        container,
        ActivePowerOutageConstraint(),
        U,
        names,
        time_steps;
        meta = "input",
    )
    constraint_output = add_constraints_container!(
        container,
        ActivePowerOutageConstraint(),
        U,
        names,
        time_steps;
        meta = "output",
    )
    param_array = get_parameter_array(container, AvailableStatusParameter(), U)
    jump_model = get_jump_model(container)
    for device in devices, t in time_steps
        name = PSY.get_name(device)
        ub_input = PSY.get_input_active_power_limits(device, PSY.SU).max
        constraint_input[name, t] = JuMP.@constraint(
            jump_model,
            array_in[name, t] <= ub_input * param_array[name, t]
        )
        ub_output = PSY.get_output_active_power_limits(device, PSY.SU).max
        constraint_output[name, t] = JuMP.@constraint(
            jump_model,
            array_out[name, t] <= ub_output * param_array[name, t]
        )
    end
    return
end
```

- [ ] **Step 4: Run the tests.** Expected: PASS (with fixture/formulation names resolved per Step 1 notes).
- [ ] **Step 5:** Formatter; ambiguity count check; run `julia --project=test test/runtests.jl test_device_hydro_constructors` for regression.

---

### Task 9: End-to-end build/solve tests and forced-outage behavior

**Files:**
- Test: `test/test_events.jl`

**Interfaces:**
- Consumes: everything from Tasks 1–8; `HiGHS_optimizer` (`test/test_utils/solver_definitions.jl`); PSB fixtures.

- [ ] **Step 1: Full-template build+solve across networks.** Append to `test/test_events.jl`:

```julia
@testset "E2E: thermal UC with FixedForcedOutage event - $(net)" for net in
    (CopperPlateNetworkModel, PTDFNetworkModel, DCPNetworkModel)
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc")
    thermal = first(PSY.get_components(PSY.ThermalStandard, sys))
    attach_fixed_forced_outage!(sys, thermal)
    template = get_thermal_dispatch_template_network(NetworkModel(net))
    em = EventModel(
        PSY.FixedForcedOutage,
        ContinuousCondition();
        timeseries_mapping = Dict{Symbol, Union{String, Nothing}}(:outage_status => "outage_profile"),
    )
    set_event_model!(template, em)
    model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          IOM.ModelBuildStatus.BUILT
    @test solve!(model) == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = IOM.OptimizationProblemOutputs(model)
    # Event parameters are written to results (should_write_resulting_value = true)
    @test "AvailableStatusParameter__ThermalStandard" in
          IOM.list_parameter_names(res)
end
```

Confirm `solve!` vs `IOM.solve!` and `list_parameter_names` against `test/test_model_decision.jl` usage and match.
Add an ACP variant testset (`ACPNetworkModel` with `ipopt_optimizer`) asserting the quadratic `ReactivePowerOutageConstraint` exists:
`IOM.get_constraint(IOM.get_optimization_container(model), ReactivePowerOutageConstraint(), PSY.ThermalStandard, "ub")`.

- [ ] **Step 2: Forced-zero behavior.** Append:

```julia
@testset "Forced outage drives device output to zero" begin
    device_model = DeviceModel(PSY.ThermalStandard, ThermalBasicUnitCommitment)
    model = # mock DecisionModel construction as in Task 5, system "c_sys5_uc"
    mock_construct_device!(
        model,
        device_model;
        add_event_model = true,
        built_for_recurrent_solves = true,
    )
    container = IOM.get_optimization_container(model)
    param_array = IOM.get_parameter_array(
        container,
        AvailableStatusParameter(),
        PSY.ThermalStandard,
    )
    outaged_name = axes(param_array)[1][1]
    for t in axes(param_array)[2]
        JuMP.fix(param_array[outaged_name, t], 0.0; force = true)
    end
    jm = IOM.get_jump_model(container)
    JuMP.set_optimizer(jm, HiGHS.Optimizer)
    JuMP.set_silent(jm)
    JuMP.optimize!(jm)
    @test JuMP.termination_status(jm) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    p = IOM.get_variable(container, ActivePowerVariable(), PSY.ThermalStandard)
    @test all(
        abs(JuMP.value(p[outaged_name, t])) <= 1e-6 for t in axes(p)[2]
    )
end
```

In recurrent-solve mode the parameters are fixed JuMP variables, so `JuMP.fix` works; the UC formulation lets the unit commit off, keeping the model feasible with zero output.
If the mock container carries no objective, `optimize!` solves a feasibility problem — that is sufficient; the binding `p ≤ max·status = 0` constraint forces the result regardless of objective.
If the mock construct does not build the balance/objective needed for feasibility, relax the test to: assert the `ActivePowerOutageConstraint` row for `(outaged_name, t)` has its RHS/parameter term at `0.0` after fixing (inspect via `JuMP.constraint_object`).

- [ ] **Step 3: Run the whole events file.**

Run: `julia --project=test -e 'include("test/includes.jl"); include("test/test_events.jl")'`
Expected: all testsets PASS.

- [ ] **Step 4: Run the file under the parallel runner** (fresh-module context catches `Main`-only bugs):

Run: `julia --project=test test/runtests.jl test_events`
Expected: PASS.

- [ ] **Step 5:** Formatter.

---

### Task 10: Documentation

**Files:**
- Modify: `docs/src/reference/public.md` (and `docs/src/reference/formulation_library.md` if it enumerates constraints/parameters)

- [ ] **Step 1: Register new public symbols.** Open `docs/src/reference/public.md` and determine its convention (explicit `@docs` blocks vs `@autodocs`).
If symbols are listed explicitly, add: `EventModel`, `EventKey`, `AbstractEventCondition`, `ContinuousCondition`, `PresetTimeCondition`, `StateVariableValueCondition`, `DiscreteEventCondition`, `set_event_model!`, `get_event_models`, `supports_events`, `get_empty_timeseries_mapping`, `get_event_type`, `get_event_condition`, `get_attribute_device_map`, plus the parameter/constraint types if other parameters/constraints are listed there (`AvailableStatusParameter`, `AvailableStatusChangeCountdownParameter`, `ActivePowerOffsetParameter`, `ReactivePowerOffsetParameter`, `ActivePowerOutageConstraint`, `ReactivePowerOutageConstraint`, `ActivePowerPumpOutageConstraint`).

- [ ] **Step 2: Formulation-library entry.** If `docs/src/reference/formulation_library.md` documents device formulations' constraints, add a short "Outage events" subsection:

```markdown
## Outage events

Attaching an `EventModel` for a `PSY.Contingency` supplemental attribute (e.g.
`FixedForcedOutage`) to a template adds availability parameters and outage
constraints to every supported device carrying the attribute.

Parameters (per device and time step): `AvailableStatusParameter` (1 = available,
initialized to 1), `AvailableStatusChangeCountdownParameter`, and for loads and
`FixedOutput` devices the balance offsets `ActivePowerOffsetParameter` /
`ReactivePowerOffsetParameter`.

Constraints:

``math
p_{d,t} \le \overline{P}_d \cdot \text{status}_{d,t}
``

with the LHS given by the device family (range-expression upper bound for thermal
and hydro, the active power variable for loads and renewables without services,
charge/discharge variables for storage, generation and pumping variables for pump
turbines). Under reactive-power-capable networks the quadratic constraint
``q_{d,t}^2 \le \overline{Q}_d^2 \cdot \text{status}_{d,t}`` is also added.

The parameter values are constant within a single build; updating them across
solves (outage sampling, countdown projection) is simulation-runtime functionality
that lives outside this package.
```

(Match the file's existing math-fence style — ```` ```math ```` fences vs `` ``math `` inline — before pasting.)

- [ ] **Step 3: Build docs.**

Run: `julia --project=docs docs/make.jl`
Expected: build completes; no missing-docstring or cross-reference errors.
Fix any failures by adding the flagged docstring or registration.

- [ ] **Step 4:** Formatter (it formats `docs/src` too).

---

### Task 11: Final gates and plan-file bookkeeping

**Files:**
- Modify: `.claude/pom_port_plan.md`

- [ ] **Step 1: Ambiguity gate.**

Run: `julia --project=test -e 'using Test, PowerOperationsModels; a = detect_ambiguities(PowerOperationsModels); println(length(a)); foreach(println, a)'`
Expected: count identical to `main` baseline (measure by stashing if needed). New ambiguities from `add_event_*` overlaps must be fixed with tie-breaker methods, not ignored.

- [ ] **Step 2: Full test suite.**

Run: `julia --project=test test/runtests.jl --jobs=8`
Expected: all files PASS, including `test_events`. Investigate and fix any regression before proceeding (per repo rules, fix unrelated flakiness you hit rather than rerunning around it).

- [ ] **Step 3: Update the port plan.** In `.claude/pom_port_plan.md`:
correct the stale line 144-147 note ("POM has no `core/event_model.jl` ... only the `AvailableStatusParameter` type exists") to record that the event framework is ported (template-level `set_event_model!`, `src/event_models/`, build-level `test_events.jl`), that hydro/storage/pump-turbine constraint coverage from HPS/SSS is included, and that the remaining PSI-side gap is simulation-runtime only (condition evaluation, sampling, state projection — out of POM scope).
Also update the "Workstream C" line in the execution order accordingly.

- [ ] **Step 4: Verify the IOM fix is upstream and drop the local override.** Confirm the Task 4b change has merged to IOM `main` (`gh pr list --repo Sienna-Platform/InfrastructureOptimizationModels.jl --state merged --search "SupplementalAttribute"` or ask the user).
Then restore POM's normal resolution and re-verify against the real upstream:

Run: `julia --project=test -e 'using Pkg; Pkg.free("InfrastructureOptimizationModels"); Pkg.update("InfrastructureOptimizationModels")'`
(if `Pkg.free` errors for a `[sources]`-pinned package, `Pkg.update("InfrastructureOptimizationModels")` alone re-resolves from the pinned branch once the dev entry is removed — check `test/Manifest.toml` no longer holds a local path for IOM).
Then rerun: `julia --project=test test/runtests.jl test_events`
Expected: PASS against IOM `main`. If the IOM PR has not merged yet, leave the `Pkg.develop` bridge in place, report events as blocked-on-IOM-merge, and do not sign off the plan.

- [ ] **Step 5: Final formatter pass and diff review.**

```bash
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
git add -N src/event_models/ test/test_utils/events_test_utils.jl test/test_events.jl
git status --short
```

Expected: only intended files modified/added; everything unstaged (`git add -N` only marks intent); no commits made.

---

## Plan self-review notes (already applied)

- Spec coverage: package split (Tasks 1–8 POM-side; IOM gets exactly the Task 4b type-bound correction, everything else consumed as-is), template attachment + discovery + TS validation (Tasks 3–4), psy6 units fixes (`PSY.SU` in Tasks 7–8 code), IC exclusion (Task 4 Step 6), hydro/storage/pump coverage (Task 8), E2E + forced-zero behavior (Task 9), docs gate (Task 10), ambiguities + full suite + IOM-merge verification + port-plan bookkeeping (Task 11), concurrency constraint (Global Constraints: forbidden files owned by the transformer plan).
- Deviation from spec, deliberate: constructor count-tests live in `test/test_events.jl` rather than appended to the existing `test_device_*_constructors.jl` files, to keep the events branch free of textual conflicts with the concurrent transformer-refactor branch. Coverage is identical.
- Deviation from spec, deliberate: PSI's four per-network `add_to_expression!` methods collapse into one method built on POM's `_balance_expression_targets` (covers CopperPlate, PTDF/AreaPTDF, AreaBalance, and nodal AC/DCP in one dispatch) — POM grew this abstraction after the spec's inventory was written.
- The `events` field on `PowerOperationsProblemTemplate` is typed `Vector{IOM.AbstractEventModel}` (not `Vector{EventModel}` as the spec sketched) because `core/problem_template.jl` is included before `event_models/`; accessors still return the concrete `EventModel`s.
- Known verification points intentionally delegated to task steps (each has an explicit check command): IOM ownership of `get_entry_type` generics, `get_model(template, T)` accessor name, `PSY.get_time_series` on supplemental attributes, mock `DecisionModel` factory name, fixture names per device family, `IOM.get_constraint` meta arity, hydro formulations lacking `ActivePowerRangeExpressionUB`.
