# [Feedforwards](@id feedforwards_explanation)

```@meta
CurrentModule = PowerOperationsModels
```

A **feedforward** binds a model's decision variables to the recorded **state of the system**.
It is the mechanism by which a model is told what the system is already doing or already
planning to do — which units are online, what a set point currently is, how much energy is
in storage — so that the model optimizes around that reality instead of re-deciding it.

Mechanically, a feedforward does two things to the model it is attached to:

 1. it allocates a parameter container that will hold the relevant piece of system state, and
 2. it builds constraints that tie the model's variables to that parameter.

!!! warning "A feedforward is not a model-to-model link"
    
    It is tempting to read a feedforward as "the day-ahead model tells the real-time model
    what to do." That picture is wrong, and it leads to wrong intuitions about what
    feedforwards can express.
    
    A feedforward relates a model to the **system state**, not to another model. The source
    is a quantity in that state, and the model attached to the feedforward reads it. It does
    not know, and cannot ask, which model last wrote it — or whether any model wrote it at
    all.

## The system state is the thing being modeled

Real operations do not work by having one optimization hand its answer to the next. They
work by maintaining a shared, authoritative picture of the system, and by having every tool
read from and contribute to that picture. A Current Operating Plan records what each
resource intends to do over the coming hours. A state estimator produces the best available
estimate of what the system is doing right now. Unit commitment, security analysis, and
real-time dispatch all consume those, and their results update them in turn. No tool takes
dictation from another tool; each one is a view onto the same evolving system.

Sienna reproduces that structure. The system state is a first-class object that persists
across executions: models write their results into it, and models read from it. A
feedforward is the reading half made explicit — a declaration that *this variable, in this
model, is constrained by that quantity in the system state*.

Framing it this way answers questions the model-to-model picture cannot:

  - **Why does `source` name a variable type and not a model?** Because it names a quantity
    in the state. Which model produced it is a scheduling concern, resolved elsewhere.
  - **Why can a model read state it never produced?** Because state can come from a
    measurement, a forecast, an external schedule, or an operator override just as legitimately
    as from another optimization.
  - **Why is the same feedforward valid in different simulation arrangements?** Because it
    describes a relationship to the system, and the system is what stays fixed when the
    arrangement of models around it changes.

The decomposition into coarse and fine models exists for tractability — no realistic system
admits a full day of five-minute dispatch with binary commitment in one problem. But the
decomposition is *why there are several models*, not what a feedforward is. What a
feedforward does is keep each of those models honest about the state of the system it is
modeling.

## What POM does, and what it does not

POM builds the *receiving* half: the parameter container, the slack variables if any, and
the constraints that read them. Populating that parameter from the system state between
executions requires the state itself — which quantities are recorded, at what resolution,
and how they advance in time — and that machinery lives in `PowerSimulations`, not here.

The practical consequence: building a POM model with a feedforward attached gives you a
model whose feedforward parameters still hold their *initial* values. The constraints are
real and will bind, but no state has been fed into them. This is the expected condition for a
standalone `DecisionModel`; it becomes meaningful when the model runs against a live state.

## Construction happens in two stages

Feedforwards follow the same two-stage rule as every device formulation:

| Stage                    | Call                           | What it adds                                                   |
|:------------------------ |:------------------------------ |:-------------------------------------------------------------- |
| `ArgumentConstructStage` | `add_feedforward_arguments!`   | the parameter container, slack variables, and expression terms |
| `ModelConstructStage`    | `add_feedforward_constraints!` | the JuMP constraints that read the parameter                   |

The split matters for the semicontinuous case described below, where the argument stage
contributes to expressions that constraints later consume.

## Attaching a feedforward

Feedforwards attach to a `DeviceModel`, which is then set on the template like any other:

```julia
device_model = DeviceModel(ThermalStandard, ThermalStandardDispatch)

attach_feedforward!(
    device_model,
    SemiContinuousFeedforward(;
        component_type = ThermalStandard,
        source = OnVariable,
        affected_values = [ActivePowerVariable],
    ),
)

set_device_model!(template, device_model)
```

Three arguments define every feedforward:

  - `component_type` — the `PowerSystems` component family the feedforward applies to.
  - `source` — the `VariableType` or `AuxVariableType` that names the **quantity in the
    system state** to read. It names what to read, never where it came from.
  - `affected_values` — the variables in *this* model that the constraints will bind.

`meta` disambiguates the source key when the same quantity is recorded under different
labels, and `add_slacks` is available on the two bound feedforwards.

The four available types, their parameters, constraints, and exact constraint expressions
are tabulated in [Feedforward Formulations](@ref ff_formulations). The guidance for choosing
between them:

  - **`UpperBoundFeedforward`** — cap a variable at the value the state records. The usual
    case is holding dispatch to a standing award or schedule.
  - **`LowerBoundFeedforward`** — the mirror image; enforce a floor, such as a contracted
    minimum output.
  - **`SemiContinuousFeedforward`** — respect a *commitment status* recorded in the state.
    The affected variable is forced to zero when the state says the unit is offline, and
    confined to its operating range when it is online. This is the common case for any model
    that dispatches units whose on/off status it does not itself decide.
  - **`FixValueFeedforward`** — pin a variable to an exact value. Use it when the state
    records a set point rather than a limit — an HVDC flow or an interchange schedule that
    this model is not free to re-optimize.

## The semicontinuous feedforward substitutes; it does not stack

The other three feedforwards add constraints alongside whatever the device formulation
already builds. `SemiContinuousFeedforward` is different, and understanding why prevents a
class of silent modeling errors.

A unit commitment formulation writes its own range constraints in terms of its `OnVariable`:
the unit generates between its minimum and maximum *times the commitment binary*. When the
commitment status is read from the system state instead, there is no binary to multiply —
there is a parameter. So the commitment enters the `ActivePowerRangeExpressionUB` and
`ActivePowerRangeExpressionLB` expressions during the argument stage, scaled by the device's
own limits, and the formulation's native range constraints are **suppressed**. Building both
would constrain the unit twice over, with the tighter of the two silently winning.

Suppression is not automatic bookkeeping: each formulation asks
`has_semicontinuous_feedforward` before it builds its range constraints. A
formulation that forgets the check double-constrains its devices, which is why the check
appears in the thermal and hydro dispatch *and* unit-commitment paths alike.

The multiplier applied to the commitment parameter depends on the formulation, because the
formulations do not all schedule the same quantity:

| Formulation family            | Scheduled variable          | Upper-range multiplier | Lower-range multiplier |
|:----------------------------- |:--------------------------- |:---------------------- |:---------------------- |
| Standard thermal formulations | `ActivePowerVariable`       | ``P_{max}``            | ``P_{min}``            |
| Compact thermal formulations  | `PowerAboveMinimumVariable` | ``P_{max} - P_{min}``  | ``0``                  |

Compact formulations model power *above* the minimum, so their range starts at zero and
spans the operating band. POM resolves this through a formulation trait rather than a
hardcoded variable type, so asking whether a range expression is fed by a semicontinuous
feedforward gives the right answer for both families without the caller knowing which it has.

!!! note "Must-run units are excluded"
    
    A must-run unit is never turned off, so it carries no commitment parameter entry and
    receives no semicontinuous constraints. It keeps its ordinary range constraints and its
    contribution to the power balance. This exclusion is applied consistently across the
    parameter, expression, and constraint paths — a must-run unit that picked up a
    semicontinuous constraint would be constrained by a parameter that was never populated
    for it.

## Slacks on bound feedforwards

`UpperBoundFeedforward` and `LowerBoundFeedforward` accept `add_slacks = true`:

```julia
UpperBoundFeedforward(;
    component_type = ThermalStandard,
    source = ActivePowerVariable,
    affected_values = [ActivePowerVariable],
    add_slacks = true,
)
```

This adds a non-negative slack variable that relaxes the bound — subtracted on an upper
bound, added on a lower bound — and penalizes it in the objective at `BALANCE_SLACK_COST`.
The penalty is set high enough that the slack is only used when the alternative is
infeasibility.

Reach for slacks when the recorded state can legitimately conflict with the model's own
physics: a bound recorded at hourly resolution may be momentarily unattainable at five-minute
resolution given ramp limits. An infeasible model tells you nothing about *where* the
conflict is; a slack that turns out nonzero points straight at the device and the interval.

## Rules when attaching

`attach_feedforward!` enforces the invariants that the parameter containers depend on, and
it does so at template-definition time rather than deep inside `build!`:

  - Attaching a **field-for-field identical** feedforward twice is a no-op, so templates can
    be assembled incrementally without duplicating containers.
  - Attaching a feedforward that shares a source key with an attached one but **differs in
    any other field** raises an error naming the conflicting fields. Silently keeping only
    the first would drop a constraint the caller asked for.
  - A device model may carry **at most one `SemiContinuousFeedforward`** per component type,
    and **at most one `UpperBoundFeedforward` and one `LowerBoundFeedforward`**. Their
    parameter containers are keyed by parameter and component type only, so a second one
    would collide.

Different feedforward *types* coexist freely on the same device model — a semicontinuous
commitment feed plus an upper bound on the same units is a normal combination.

## Current limitations

!!! warning "Feedforwards attach to device models only"
    
    `attach_feedforward!` on a `ServiceModel` throws, and `set_service_model!` rejects a
    `ServiceModel` constructed with a non-empty `feedforwards` keyword. Per-type service
    models key their reserve variables by `(service_name, device_name, time)` while the
    feedforward parameter path is keyed `(device_name, time)`; the two are dimensionally
    inconsistent until the service parameter path is re-keyed. See
    [Feedforward Formulations](@ref ff_formulations) for the full note.

`FixValueFeedforward` is the only type that accepts a `ParameterType` among its
`affected_values`, but the device-model construction path supports variable targets only and
raises an explicit error otherwise. The other three accept `VariableType` affected values
exclusively, and reject anything else at construction rather than at build.
