abstract type PostContingencyConstraintType <: ConstraintType end

struct AbsoluteValueConstraint <: ConstraintType end
"""

Struct to create the constraint for starting up ThermalMultiStart units.
For more information check [ThermalGen Formulations](@ref ThermalGen-Formulations) for ThermalMultiStartUnitCommitment.

The specified constraint is formulated as:

```math
\\max\\{P^\\text{th,max} - P^\\text{th,shdown}, 0\\} \\cdot w_1^\\text{th} \\le u^\\text{th,init} (P^\\text{th,max} - P^\\text{th,min}) - P^\\text{th,init}
```
"""
struct ActiveRangeICConstraint <: ConstraintType end
"""
Struct to create the constraint to balance power across specified areas.
For more information check [Network Formulations](@ref network_formulations).

The specified constraint is generally formulated as:

```math
\\sum_{c \\in \\text{components}_a} p_t^c = 0, \\quad \\forall a\\in \\{1,\\dots, A\\}, t \\in \\{1, \\dots, T\\}
```
"""
struct AreaParticipationAssignmentConstraint <: ConstraintType end
struct BalanceAuxConstraint <: ConstraintType end
# Links a device's per-service reserve OFFER blocks to its reserve award:
# `Σ_k δ[(service, device, k, t)] == ActivePowerReserveVariable[(service, device, t)]`.
struct ReserveOfferLinkingConstraint <: ConstraintType end
"""
Struct to create the commitment constraint between the on, start, and stop variables.
For more information check [ThermalGen Formulations](@ref ThermalGen-Formulations).

The specified constraints are formulated as:

```math
u_1^\\text{th} = u^\\text{th,init} + v_1^\\text{th} - w_1^\\text{th} \\\\
u_t^\\text{th} = u_{t-1}^\\text{th} + v_t^\\text{th} - w_t^\\text{th}, \\quad \\forall t \\in \\{2,\\dots,T\\} \\\\
v_t^\\text{th} + w_t^\\text{th} \\le 1, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct CommitmentConstraint <: ConstraintType end
"""
Struct to create the constraint to balance power in the copperplate model.
For more information check [Network Formulations](@ref network_formulations).

The specified constraint is generally formulated as:

```math
\\sum_{c \\in \\text{components}} p_t^c = 0, \\quad \\forall t \\in \\{1, \\dots, T\\}
```
"""
struct CopperPlateBalanceConstraint <: ConstraintType end

"""
Coupling constraint linking a controllable shunt's reactive injection to its
[`ShuntSusceptanceVariable`](@ref) and the local bus voltage. Used by
[`ShuntSusceptanceDispatch`](@ref) under all AC network models (ACP/ACR/IVR):

```math
Q_{d,t} = b_{d,t} \\cdot V_{n(d),t}^2,
\\quad \\forall d \\in \\mathcal{D},\\, t \\in \\{1,\\dots,T\\}
```

Under ACP, ``V^2 = v_{n(d),t}^2`` (scalar magnitude squared); under ACR/IVR,
``V^2 = v_{r,n(d),t}^2 + v_{i,n(d),t}^2`` (rectangular components). The constraint is
always created regardless of control mode; the voltage-control objective is applied
separately via a `JuMP.fix` on the regulated bus magnitude.
"""
struct ShuntReactivePowerConstraint <: ConstraintType end

"""
Struct to create the duration constraint for commitment formulations, i.e. min-up and min-down.

For more information check [ThermalGen Formulations](@ref ThermalGen-Formulations).
"""
struct DurationConstraint <: ConstraintType end
struct EnergyBalanceConstraint <: ConstraintType end

"""
Struct to create the constraint that sets the reactive power to the power factor
in the RenewableConstantPowerFactor formulation for renewable units.

For more information check [RenewableGen Formulations](@ref PowerSystems.RenewableGen-Formulations).

The specified constraint is formulated as:

```math
q_t^\\text{re} = \\text{pf} \\cdot p_t^\\text{re}, \\quad \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct EqualityConstraint <: ConstraintType end
"""
Struct to create the constraint for semicontinuous feedforward limits.

For more information check [Feedforward Formulations](@ref ff_formulations).

The specified constraint is formulated as:

```math
\\begin{align*}
&  \\text{ActivePowerRangeExpressionUB}_t := p_t^\\text{th} - \\text{on}_t^\\text{th}P^\\text{th,max} \\le 0, \\quad  \\forall t\\in \\{1, \\dots, T\\}  \\\\
&  \\text{ActivePowerRangeExpressionLB}_t := p_t^\\text{th} - \\text{on}_t^\\text{th}P^\\text{th,min} \\ge 0, \\quad  \\forall t\\in \\{1, \\dots, T\\}
\\end{align*}
```
"""
struct FeedforwardSemiContinuousConstraint <: ConstraintType end
struct FeedforwardIntegralLimitConstraint <: ConstraintType end
"""
Struct to create the constraint for upper bound feedforward limits.

For more information check [Feedforward Formulations](@ref ff_formulations).

The specified constraint is formulated as:

```math
\\begin{align*}
&  \\text{AffectedVariable}_t - p_t^\\text{ff,ubsl} \\le \\text{SourceVariableParameter}_t, \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct FeedforwardUpperBoundConstraint <: ConstraintType end
"""
Struct to create the constraint for lower bound feedforward limits.

For more information check [Feedforward Formulations](@ref ff_formulations).

The specified constraint is formulated as:

```math
\\begin{align*}
&  \\text{AffectedVariable}_t + p_t^\\text{ff,lbsl} \\ge \\text{SourceVariableParameter}_t, \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct FeedforwardLowerBoundConstraint <: ConstraintType end
struct FeedforwardEnergyTargetConstraint <: ConstraintType end
"""
Struct to create the constraint that set the flow limits through a PhaseShiftingTransformer.

For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).

The specified constraint is formulated as:

```math
-R^\\text{max} \\le f_t \\le R^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct FlowLimitConstraint <: ConstraintType end
struct FlowLimitFromToConstraint <: ConstraintType end
struct FlowLimitToFromConstraint <: ConstraintType end

"""
Struct to create the constraints that set the power balance across a lossy HVDC two-terminal line.

For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).

The specified constraints are formulated as:

```math
\\begin{align*}
& f_t^\\text{to-from} - f_t^\\text{from-to} \\le L_1 \\cdot f_t^\\text{to-from} - L_0,\\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& f_t^\\text{from-to} - f_t^\\text{to-from} \\ge L_1 \\cdot f_t^\\text{from-to} + L_0,\\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& f_t^\\text{from-to} - f_t^\\text{to-from} \\ge - M^\\text{big} (1 - u^\\text{dir}_t),\\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& f_t^\\text{to-from} - f_t^\\text{from-to} \\ge - M^\\text{big} u^\\text{dir}_t,\\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
\\end{align*}
```
"""
struct HVDCPowerBalance <: ConstraintType end
struct FrequencyResponseConstraint <: ConstraintType end
"""
Struct to create the constraint the AC branch flows depending on the network model.
For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).

The specified constraint depends on the network model chosen. The most common application is the StaticBranch in a PTDF Network Model:

```math
f_t = \\sum_{i=1}^N \\text{PTDF}_{i,b} \\cdot \\text{Bal}_{i,t}, \\quad \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct NetworkFlowConstraint <: ConstraintType end
struct NetworkLossConstraint <: ConstraintType end
"""
Struct to create the constraint to balance active power in nodal formulation.
For more information check [Network Formulations](@ref network_formulations).

The specified constraint depends on the network model chosen.
"""
struct NodalBalanceActiveConstraint <: ConstraintType end
"""
Struct to create the constraint to balance reactive power in nodal formulation.
For more information check [Network Formulations](@ref network_formulations).

The specified constraint depends on the network model chosen.
"""
struct NodalBalanceReactiveConstraint <: ConstraintType end
"""Pins the voltage angle (and, for ACP, voltage magnitude) of a subnetwork's reference (slack) bus."""
struct ReferenceBusConstraint <: ConstraintType end
"""Rectangular-coordinate voltage magnitude bounds: vmin² ≤ vr² + vi² ≤ vmax²."""
struct VoltageMagnitudeConstraint <: ConstraintType end
"""
Ties a component-owned [`RegulatedVoltageMagnitude`](@ref) auxiliary variable to the
rectangular voltage components at its regulated bus under ACR/IVR formulations. One
entry per regulating device per time step:

```math
(v^{\\text{reg}}_{d,t})^2 = v_{r,n(d),t}^2 + v_{i,n(d),t}^2,
\\quad \\forall d \\in \\mathcal{D},\\, t \\in \\{1,\\dots,T\\}
```

Created by [`VoltageControlVSC`](@ref) and
[`VoltageControlConverter`](@ref) (and [`ShuntSusceptanceDispatch`](@ref) for
`FACTSControlDevice`). Under ACP the network [`VoltageMagnitude`](@ref) is a scalar
primitive, so neither this constraint nor [`RegulatedVoltageMagnitude`](@ref) is added.
"""
struct RegulatedVoltageMagnitudeConstraint <: ConstraintType end
"""IVR terminal-current apparent-power limit: cr² + ci² ≤ c_rating² where c_rating = rate_a / vmin."""
struct CurrentLimitConstraint <: ConstraintType end
"""Branch voltage-angle-difference limits: angmin ≤ va_fr - va_to ≤ angmax."""
struct AngleDifferenceConstraint <: ConstraintType end
"""LPAC convex cosine relaxation: cs ≤ 1 - (1-cos(vad_max))/vad_max² · (va_fr - va_to)²."""
struct CosineRelaxationConstraint <: ConstraintType end
struct ParticipationAssignmentConstraint <: ConstraintType end
"""
Struct to create the constraint to participation assignments limits in the active power reserves.
For more information check [Service Formulations](@ref service_formulations).

The constraint is as follows:

```math
r_{d,t} \\le \\text{Req} \\cdot \\text{PF} ,\\quad \\forall d\\in \\mathcal{D}_s, \\forall t\\in \\{1,\\dots, T\\} \\quad \\text{(static requirement)} \\\\
r_{d,t} \\le \\text{RequirementTimeSeriesParameter}_{t} \\cdot \\text{PF}\\quad  \\forall d\\in \\mathcal{D}_s, \\forall t\\in \\{1,\\dots, T\\}, \\quad \\text{(time-varying requirement)}
```
"""
struct ParticipationFractionConstraint <: ConstraintType end

# PiecewiseLinearCostConstraint: moved into IOM.

# AbstractPiecewiseLinearBlockOfferConstraint and concrete subtypes: moved into IOM

"""
Struct to create the PiecewiseLinearUpperBoundConstraint associated with a specified variable.

See [Piecewise linear cost functions](@ref pwl_cost) for more information.
"""
struct PiecewiseLinearUpperBoundConstraint <: ConstraintType end

"""
Struct to create the RampConstraint associated with a specified thermal device or reserve service.

For thermal units, see more information in [Thermal Formulations](@ref ThermalGen-Formulations). The constraint is as follows:
```math
-R^\\text{th,dn} \\le p_t^\\text{th} - p_{t-1}^\\text{th} \\le R^\\text{th,up}, \\quad \\forall  t\\in \\{1, \\dots, T\\}
```

For Ramp Reserve, see more information in [Service Formulations](@ref service_formulations). The constraint is as follows:

```math
r_{d,t} \\le R^\\text{th,up} \\cdot \\text{TF}\\quad  \\forall d\\in \\mathcal{D}_s, \\forall t\\in \\{1,\\dots, T\\}, \\quad \\text{(for ReserveUp)} \\\\
r_{d,t} \\le R^\\text{th,dn} \\cdot \\text{TF}\\quad  \\forall d\\in \\mathcal{D}_s, \\forall t\\in \\{1,\\dots, T\\}, \\quad \\text{(for ReserveDown)}
```
"""
struct RampConstraint <: ConstraintType end
struct RampLimitConstraint <: ConstraintType end
struct RangeLimitConstraint <: ConstraintType end
"""
Struct to create the constraint that set the AC flow limits through AC branches and HVDC two-terminal branches.

For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).

The specified constraint is formulated as:

```math
\\begin{align*}
&  f_t - f_t^\\text{sl,up} \\le R^\\text{max},\\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
&  f_t + f_t^\\text{sl,lo} \\ge -R^\\text{max},\\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct FlowRateConstraint <: ConstraintType end
"""
Post-contingency flow-rate limit on monitored branches:
`-R_m ≤ Σ_j MODF_post[m,c][j]·p_j ≤ R_m, ∀ t`, where `MODF_post[m,c]` is the
PNM `VirtualMODF` column for monitored arc `m` under contingency `c` and `R_m`
is the branch emergency rating (system base / per-unit).
"""
struct PostContingencyFlowRateConstraint <: PostContingencyConstraintType end

"""
Struct to create the constraint for branch flow rate limits from the 'from' bus to the 'to' bus.
For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).
"""
struct FlowRateConstraintFromTo <: ConstraintType end

"""
Struct to create the constraint for branch flow rate limits from the 'to' bus to the 'from' bus.
For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).
"""
struct FlowRateConstraintToFrom <: ConstraintType end
struct RegulationLimitsConstraint <: ConstraintType end

"""
Struct to create the constraint for satisfying active power reserve requirements.
For more information check [Service Formulations](@ref service_formulations).

The constraint is as follows:

```math
\\sum_{d\\in\\mathcal{D}_s} r_{d,t} + r_t^\\text{sl} \\ge \\text{Req},\\quad \\forall t\\in \\{1,\\dots, T\\} \\quad \\text{(static requirement)} \\\\
\\sum_{d\\in\\mathcal{D}_s} r_{d,t} + r_t^\\text{sl} \\ge \\text{RequirementTimeSeriesParameter}_{t},\\quad \\forall t\\in \\{1,\\dots, T\\} \\quad \\text{(time-varying requirement)}
```
"""
struct RequirementConstraint <: ConstraintType end
struct ReserveEnergyCoverageConstraint <: ConstraintType end
"""
Struct to create the constraint for ensuring that NonSpinning Reserve can be delivered from turn-off thermal units.

For more information check [Service Formulations](@ref service_formulations) for NonSpinningReserve.

The constraint is as follows:

```math
r_{d,t} \\le (1 - u_{d,t}^\\text{th}) \\cdot R^\\text{limit}_d, \\quad \\forall d \\in \\mathcal{D}_s, \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct ReservePowerConstraint <: ConstraintType end
struct SACEPIDAreaConstraint <: ConstraintType end
struct StartTypeConstraint <: ConstraintType end
"""
Struct to create the start-up initial condition constraints for ThermalMultiStart.

For more information check [ThermalGen Formulations](@ref ThermalGen-Formulations) for ThermalMultiStartUnitCommitment.
"""
struct StartupInitialConditionConstraint <: ConstraintType end
"""
Struct to create the start-up time limit constraints for ThermalMultiStart.

For more information check [ThermalGen Formulations](@ref ThermalGen-Formulations) for ThermalMultiStartUnitCommitment.
"""
struct StartupTimeLimitTemperatureConstraint <: ConstraintType end
"""
Struct to create the constraint that set the angle limits through a PhaseShiftingTransformer.

For more information check [Branch Formulations](@ref PowerSystems.Branch-Formulations).

The specified constraint is formulated as:

```math
\\Theta^\\text{min} \\le \\theta^\\text{shift}_t \\le \\Theta^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct PhaseAngleControlLimit <: ConstraintType end
struct InterfaceFlowLimit <: ConstraintType end
struct HVDCFlowCalculationConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Rectifier DC line voltage.

```math
v_d^r = \\frac{3}{\\pi}N^r \\left( \\sqrt{2}\frac{a^r v_\\text{ac}^r}{t^r}\\cos{\\alpha^r}-X^r I_d \\right)
```
"""
struct HVDCRectifierDCLineVoltageConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Inverter DC line voltage.

```math
v_d^i = \\frac{3}{\\pi}N^i \\left( \\sqrt{2}\frac{a^i v_\\text{ac}^i}{t^i}\\cos{\\gamma^i}-X^i I_d \\right)
```
"""
struct HVDCInverterDCLineVoltageConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Rectifier Overlap Angle.

```math
\\mu^r = \\arccos \\left( \\cos\\alpha^r - \\frac{\\sqrt{2} I_d X^r t^r}{a^r v_\\text{ac}^r} \\right) - \\alpha^r
```
"""
struct HVDCRectifierOverlapAngleConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Inverter Overlap Angle.

```math
\\mu^i = \\arccos \\left( \\cos\\gamma^i - \\frac{\\sqrt{2} I_d X^i t^r}{a^i v_\\text{ac}^i} \\right) - \\gamma^i
```
"""
struct HVDCInverterOverlapAngleConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Rectifier Power Factor Angle.

```math
\\phi^r = \\arctan \\left( \\frac{2\\mu^r + \\sin(2\\alpha^r) - \\sin(2(\\mu^r + \\alpha^r))}{\\cos(2\alpha^r) - \\cos(2(\\mu^r + \\alpha^r))} \\right)
```
"""
struct HVDCRectifierPowerFactorAngleConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the Inverter Power Factor Angle.

```math
\\phi^i = \\arctan \\left( \\frac{2\\mu^i + \\sin(2\\gamma^i) - \\sin(2(\\mu^i + \\gamma^i))}{\\cos(2\\gamma^i) - \\cos(2(\\mu^i + \\gamma^i))} \\right)
```
"""
struct HVDCInverterPowerFactorAngleConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the AC Current flowing into the AC side of the rectifier.

```math
i_\text{ac}^r = \\sqrt{6} \\frac{N^r}{\\pi}I_d
```
"""
struct HVDCRectifierACCurrentFlowConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the AC Current flowing into the AC side of the inverter.

```math
i_\text{ac}^i = \\sqrt{6} \\frac{N^i}{\\pi}I_d
```
"""
struct HVDCInverterACCurrentFlowConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the AC Power injection at the AC side of the rectifier.

```math
\\begin{align*}
p_\\text{ac}^r = \\sqrt{3} i_\\text{ac}^r \\frac{a^r v_\\text{ac}^r}{t^r}\\cos{\\phi^r} \\\\
q_\\text{ac}^r = \\sqrt{3} i_\\text{ac}^r \\frac{a^r v_\\text{ac}^r}{t^r}\\sin{\\phi^r} \\\\
\\end{align*}
```
"""
struct HVDCRectifierPowerCalculationConstraint <: ConstraintType end

"""
Struct to create the constraint that calculates the AC Power injection at the AC side of the inverter.

```math
\\begin{align*}
p_\\text{ac}^i = \\sqrt{3} i_\\text{ac}^i \\frac{a^i v_\\text{ac}^i}{t^i}\\cos{\\phi^i} \\\\
q_\\text{ac}^i = \\sqrt{3} i_\\text{ac}^i \\frac{a^i v_\\text{ac}^i}{t^i}\\sin{\\phi^i} \\\\
\\end{align*}
```
"""
struct HVDCInverterPowerCalculationConstraint <: ConstraintType end

"""
Struct to create the constraint that links the AC and DC side of the network.

```math
v_d^i = v_d^r - R_d I_d
```
"""
struct HVDCTransmissionDCLineConstraint <: ConstraintType end

"""
Per-terminal converter power-balance constraint for two-terminal VSC HVDC:

```math
\\begin{aligned}
p_{ft} &= v_f \\cdot I + (a_f I^2 + b_f |I| + c_f) \\\\
p_{tf} &= -v_t \\cdot I + (a_t I^2 + b_t |I| + c_t)
\\end{aligned}
```
"""
struct HVDCVSCConverterPowerConstraint <: ConstraintType end

"""
Cable Ohm's law for a two-terminal HVDC link with explicit DC resistance:

```math
v_f - v_t = (1/g) \\cdot I
```
"""
struct HVDCCableOhmsLawConstraint <: ConstraintType end

"""
Apparent-power limit at each terminal of a two-terminal VSC HVDC
(`HVDCTwoTerminalVSC`), added only on AC networks. Enforces ``|S_k| \\le
S_k^{\\max}`` for ``k \\in \\{f, t\\}`` via one of two shapes, selected by the
`"bilinear_approximation"` attribute:

- `"none"` (exact, NLP): exact disk ``p_k^2 + q_k^2 \\le (S_k^{\\max})^2``.
- any linearizing scheme: linear outer-approximation. The axis-aligned box
  ``|p_k|, |q_k| \\le S_k^{\\max}`` is added unconditionally; the four diagonal
  half-planes ``|p_k| \\pm q_k \\le S_k^{\\max}\\sqrt{2}`` are added when the
  device-model attribute `use_octagon` (default `true`) is on, in which case
  the intersection is a regular octagon circumscribing the disk
  (loose by at most ≈8.2% in area).
"""
struct HVDCVSCApparentPowerLimitConstraint <: ConstraintType end

"""
DC-terminal active-power control constraint for [`VoltageControlVSC`](@ref) and
[`VoltageControlConverter`](@ref) devices. Exactly one constraint entry per terminal per
time step is always created (count-invariant across control modes); only the coefficients
differ by mode:

- `DC_VOLTAGE` (terminal DC voltage regulation):
  ```math
  v_{dc,t} = \\text{setpoint}
  ```
- `DC_POWER` (active-power setpoint):
  ```math
  p_t = \\text{setpoint}
  ```
- `DC_VOLTAGE_DROOP` (droop control):
  ```math
  v_{dc,t} + \\text{droop\\_gain} \\cdot p_t = \\text{setpoint}
  ```

Constraint containers use `meta = "from"` and `meta = "to"` to distinguish the two
per-terminal entries for two-terminal links. Only valid under AC network models;
`VoltageControlVSC` and `VoltageControlConverter` are dropped from DC templates
automatically via `models_reactive_power`.
"""
struct HVDCDCControlConstraint <: ConstraintType end

abstract type PowerVariableLimitsConstraint <: ConstraintType end
"""
Struct to create the constraint to limit active power input expressions.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound and LowerBound expressions, but
in its most basic formulation is of the form:

```math
P^\\text{min} \\le p_t^\\text{in} \\le P^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""

"""
Struct to create the constraint to limit active power input expressions.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound and LowerBound expressions, but
in its most basic formulation is of the form:

```math
P^\\text{min} \\le p_t^\\text{in} \\le P^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct InputActivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end
"""
Struct to create the constraint to limit active power output expressions.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound and LowerBound expressions, but
in its most basic formulation is of the form:

```math
P^\\text{min} \\le p_t^\\text{out} \\le P^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct OutputActivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end
"""
Struct to create the constraint to limit active power expressions.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound and LowerBound expressions, but
in its most basic formulation is of the form:

```math
P^\\text{min} \\le p_t \\le P^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ActivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end

"""
Struct to create the constraint to limit reactive power expressions.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound and LowerBound expressions, but
in its most basic formulation is of the form:

```math
Q^\\text{min} \\le q_t \\le Q^\\text{max}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ReactivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end
"""
Struct to create the constraint to limit active power expressions by a time series parameter.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound expressions, but
in its most basic formulation is of the form:

```math
p_t \\le \\text{ActivePowerTimeSeriesParameter}_t, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ActivePowerVariableTimeSeriesLimitsConstraint <: PowerVariableLimitsConstraint end

"""
Struct to create the constraint to limit active power expressions by a time series parameter.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound expressions, but
in its most basic formulation is of the form:

```math
p_t^{out} \\le \\text{ActivePowerTimeSeriesParameter}_t, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ActivePowerOutVariableTimeSeriesLimitsConstraint <: PowerVariableLimitsConstraint end

"""
Struct to create the constraint to limit active power expressions by a time series parameter.
For more information check [Device Formulations](@ref formulation_intro).

The specified constraint depends on the UpperBound expressions, but
in its most basic formulation is of the form:

```math
p_t^{in} \\le \\text{ActivePowerTimeSeriesParameter}_t, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ActivePowerInVariableTimeSeriesLimitsConstraint <: PowerVariableLimitsConstraint end

"""
Struct to create the constraint to limit the import and exports in a determined period.
For more information check [Device Formulations](@ref formulation_intro).
"""
struct ImportExportBudgetConstraint <: ConstraintType end

struct LineFlowBoundConstraint <: ConstraintType end

abstract type EventConstraint <: ConstraintType end
struct ActivePowerOutageConstraint <: EventConstraint end
struct ReactivePowerOutageConstraint <: EventConstraint end

############################################################
########## Multi-Terminal Converter Constraints ############
############################################################
"""
Struct to create the constraints that set the current flowing through a DC line.
```math
\\begin{align*}
& i_l^{dc} = \\frac{1}{r_l} (v_{from,l} - v_{to,l}), \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct DCLineCurrentConstraint <: ConstraintType end

struct NodalBalanceCurrentConstraint <: ConstraintType end

"""
Struct to create the constraints that decide the balance of AC and DC power of the converter.

The specified constraints are formulated as:
```math
\\begin{align*}
& p_ac = p_dc - loss_t  \\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& loss_t = a i_c^2 + b i_c + c \\\\
\\end{align*}
```
"""
struct ConverterLossConstraint <: ConstraintType end

"""
Apparent-power capability disk for an `InterconnectingConverter` under an AC network model:
``p^2 + q^2 \\le \\text{rating}^2``, with `p` the converter `ActivePowerVariable` and `q` the
converter `ReactivePowerVariable`. One entry per converter per time step.
"""
struct ConverterPowerCapabilityConstraint <: ConstraintType end

"""
Defining constraint for the AC apparent current of a converter under an AC network
model: ``I_{ac}^2 \\, V_{ac}^2 = p^2 + q^2``, where ``V_{ac}^2`` is the AC bus
voltage magnitude squared (``v_m^2`` under ACP, ``v_r^2 + v_i^2`` under ACR/IVR),
`p` the terminal/converter AC active flow and `q` the reactive injection. One entry
per terminal/converter per time step.
"""
struct ConverterACCurrentConstraint <: ConstraintType end

"""
Struct to create the constraints that set the absolute value for the current to use in losses through a lossy Interconnecting Power Converter.
The specified constraint is formulated as:
```math
\\begin{align*}
& i_c^{dc} = i_c^+ - i_c^-, \\quad \\forall t \\in \\{1,\\dots, T\\}  \\\\
& i_c^+ \\le I_{max} \\cdot \\nu_c,  \\quad \\forall t \\in \\{1,\\dots, T\\}  \\\\
& i_c^+ \\le I_{max} \\cdot (1 - \\nu_c),  \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct CurrentAbsoluteValueConstraint <: ConstraintType end

#################################################################################
# Hydro Constraints
#################################################################################

struct EnergyLimitConstraint <: ConstraintType end
"""
Struct to create the constraint that set-up the target for reservoir formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
e_t + e^\\text{shortage} + e^\\text{surplus} = \\text{EnergyTargetTimeSeriesParameter}_t, \\quad \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct EnergyTargetConstraint <: ConstraintType end

"""
Struct to create the constraint that set-up the target for reservoir formulations. It can use head or volume as the storage variable.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
l_t + l^\\text{shortage} + l^\\text{surplus} = \\text{WaterTargetTimeSeriesParameter}_t, \\quad \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct WaterTargetConstraint <: ConstraintType end
struct EnergyShortageVariableLimitsConstraint <: ConstraintType end

"""
Struct to create the constraint that limits the budget for reservoir formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
\\sum_{t=1}^T p^\\text{hy}_t \\le \\sum_{t=1}^T \\text{EnergyBudgetTimeSeriesParameter}_t,
```
"""
struct EnergyBudgetConstraint <: ConstraintType end
"""
Struct to create the constraint that limits the budget for reservoir formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
\\sum_{t=1}^T f^\\text{hy}_t \\le \\sum_{t=1}^T \\text{WaterBudgetTimeSeriesParameter}_t,
```
"""
struct WaterBudgetConstraint <: ConstraintType end
struct EnergyCapacityConstraint <: ConstraintType end

"""
Struct to create the constraint that limits the pump power  for hydro pump formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
p^\\text{pump}_t \\le \\text{ActivePowerTimeSeriesParameter}_t,
```
"""
struct ActivePowerPumpVariableLimitsConstraint <: ConstraintType end

"""
Struct to create the constraint that limits the pump power based on the reservoir variable for hydro pump formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
p^\\text{pump}_t \\le P^\\text{max,pump} \\cdot (1 - \\text{ReservationVariable}_t),
```
"""
struct ActivePowerPumpReservationConstraint <: ConstraintType end

"""
Struct to create the constraint that limits the pump power  for hydro pump formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
e^\\text{pump}_t \\le \\text{EnergyCapacityTimeSeriesParameter}_t,
```
"""
struct EnergyCapacityTimeSeriesLimitsConstraint <: ConstraintType end

"""
Struct to create the constraint that limits the hydro usage for hydro formulations.

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
\\sum_{t=1}^T E^\\text{hy}_t \\le  \\text{HydroUsageLimitParameter}_T,
```
"""
struct FeedForwardHydroUsageLimitConstraint <: ConstraintType end

"""
Struct to model turbine outflow limits

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
\\ p_{t} = \\Delta t (f^{Tu}_{t-1}(0.5 K_1 (v_{t} + v_{t-1}) + K_2))
```
"""
struct HydroPowerConstraint <: ConstraintType end

"""
Struct to create the constraint for hydro reservoir storage

For more information check [HydroPowerSimulations Formulations](@ref HydroPowerSimulations-Formulations).

The specified constraint is formulated as:

```math
\\ v_{t} = v_{t-1} + \\Delta t (f^{UR}_{t-1} - f^{Sp}_{t-1} - f^{Tu}_{t-1})
```
"""
struct ReservoirInventoryConstraint <: ConstraintType end

"""
Struct to limit the turbine flow

```math
QW^{min} \\le \\sum_{j \\in J(i)}^T wq_{jt} \\le  QW^{max},
```
"""
struct TurbineFlowLimitConstraint <: ConstraintType end

"""
Struct to model turbine power output as a function of head

```math
p_{t} = \\eta \\rho g h_{t} f^{Tu}_{t},
```
"""
struct TurbinePowerOutputConstraint <: ConstraintType end

"""
Struct to model reservoir stored volume/head limits

```math
h_{t}^{min} \\le h_{t} \\le h_{t}^{max},
```
"""
struct ReservoirLevelLimitConstraint <: ConstraintType end

"""
Struct to model the final (target) volume/head storage constraint

```math
v_{T} = V^\\text{target},
```
"""
struct ReservoirLevelTargetConstraint <: ConstraintType end

"""
Struct to model the transformation from head to volume constraint

```math
v_{t} = h_{t} \\text{head_to_volume},
```
"""
struct ReservoirHeadToVolumeConstraint <: ConstraintType end

"""
Feedforward constraint to limit the water level budget for reservoir formulations.
"""
struct FeedForwardWaterLevelBudgetConstraint <: ConstraintType end

"""
Constraint to limit the active power pump variable during an event
"""
struct ActivePowerPumpOutageConstraint <: EventConstraint end

#################################################################################
# Energy Storage Constraints
#################################################################################

"""
Struct to create the state of charge target constraint at the end of period.
Used when the attribute `energy_target = true`.

The specified constraint is formulated as:

```math
e^{st}_{T} + e^{st+} - e^{st-} = E^{st}_{T},
```
"""
struct StateofChargeTargetConstraint <: ConstraintType end

"""
Struct to create the state of charge constraint limits.

The specified constraint is formulated as:

```math
E_{st}^{min} \\le e^{st}_{t} \\le E_{st}^{max}, \\quad \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct StateofChargeLimitsConstraint <: ConstraintType end

"""
Struct to create the storage cycling limits for the charge variable.
Used when `cycling_limits = true`.

The specified constraint is formulated as:

```math
\\sum_{t \\in \\mathcal{T}} \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t} sb_{stc,p,t} + p^{st,ch}_{t} \\right)\\eta^{ch}_{st} \\Delta t - c^{ch-} \\leq C_{st} E^{max}_{st}
```
"""
struct StorageCyclingCharge <: ConstraintType end
"""
Struct to create the storage cycling limits for the discharge variable.
Used when `cycling_limits = true`.

The specified constraint is formulated as:

```math
\\sum_{t \\in \\mathcal{T}} \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t} sb_{std,p,t} + p^{st,ds}_{t}\\right)\\frac{1}{\\eta^{ds}_{st}} \\Delta t - c^{ds-} \\leq C_{st} E^{max}_{st}
```
"""
struct StorageCyclingDischarge <: ConstraintType end

## Ancillary Service Provision Energy Constraints
"""
Struct to specify the lower and upper bounds of the discharge variable considering reserves.

The specified constraints are formulated as:

```math
\\begin{align*}
& p^{st, ds}_{t} + \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} sb_{std,p,t} \\leq \\text{ss}^{st}_{t}P^{max,ds}_{st} \\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& p^{st, ds}_{t} - \\sum_{p \\in \\mathcal{P}^{\text{as}_\\text{dn}}} sb_{std,p,t} \\geq 0, \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveDischargeConstraint <: ConstraintType end

"""
Struct to specify the lower and upper bounds of the charge variable considering reserves.

The specified constraints are formulated as:

```math
\\begin{align*}
&p^{st, ch}_{t} + \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} sb_{stc,p,t} \\leq (1 - \\text{ss}^{st}_{t})P^{max,ch}_{st}, \\quad \\forall t \\in \\{1,\\dots, T\\} \\\\
& p^{st, ch}_{t} - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} sb_{stc,p,t} \\geq 0, \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveChargeConstraint <: ConstraintType end

"""
Struct to specify the individual product ancillary service coverage at the beginning of the period for charge and discharge variables.

The specified constraints are formulated as:

```math
\\begin{align*}
& sb_{stc,p,1}  \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_0, \\quad \\forall p \\in \\mathcal{P}^{as_{dn}} \\\\
& sb_{stc,p,t}  \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_{t-1}, \\quad \\forall p \\in \\mathcal{P}^{as_{dn}},  \\forall t \\in \\{2,\\dots, T\\} \\\\
& sb_{std,p,1}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_0 - E^{min}_{st}, \\quad \\forall p \\in \\mathcal{P}^{as_{up}} \\\\
& sb_{std,p,t}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_{t-1} - E^{min}_{st}, \\quad \\forall p \\in \\mathcal{P}^{as_{up}},  \\forall t \\in \\{2,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveCoverageConstraint <: ConstraintType end
"""
Struct to specify the individual product ancillary service coverage at the end of the period for charge and discharge variables.

The specified constraints are formulated as:

```math
\\begin{align*}
& sb_{stc,p,t}  \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_{t}, \\quad \\forall p \\in \\mathcal{P}^{as_{dn}}, \\forall t \\in \\{1,\\dots, T\\} \\\\
& sb_{std,p,t}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_{t}- E^{min}_{st}, \\quad \\forall p \\in \\mathcal{P}^{as_{up}}, \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveCoverageConstraintEndOfPeriod <: ConstraintType end

"""
Struct to specify all products ancillary service coverage at the beginning of the period for charge and discharge variables.
Used when the attribute `complete_coverage = true`.

The specified constraints are formulated as:

```math
\\begin{align*}
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} sb_{stc,p,1}  \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_0 \\\\
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}}  sb_{stc,p,t} \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_{t-1}, \\quad \\forall t \\in \\{2,\\dots, T\\} \\\\
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} sb_{std,p,1}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_0 - E^{min}_{st} \\\\
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} sb_{std,p,t}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_{t-1}- E^{min}_{st}, \\quad \\forall t \\in \\{2,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveCompleteCoverageConstraint <: ConstraintType end

"""
Struct to specify all products ancillary service coverage at the end of the period for charge and discharge variables.
Used when the attribute `complete_coverage = true`.

The specified constraints are formulated as:

```math
\\begin{align*}
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}}  sb_{stc,p,t}  \\eta^{ch}_{st} N_{p} \\Delta t \\le E_{st}^{max} - e^{st}_{t}, \\quad \\forall t \\in \\{1,\\dots, T\\}  \\\\
& \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} sb_{std,p,t}  \\frac{1}{\\eta^{ds}_{st}} N_{p} \\Delta t \\leq e^{st}_{t}- E^{min}_{st}, \\quad \\forall t \\in \\{1,\\dots, T\\}
\\end{align*}
```
"""
struct ReserveCompleteCoverageConstraintEndOfPeriod <: ConstraintType end

"""
Struct to specify an auxiliary constraint for adding charge and discharge into a single active power reserve variable.

The specified constraint is formulated as:

```math
sb_{stc, p, t} + sb_{std, p, t} = r_{p,t}, \\quad \\forall p \\in \\mathcal{P}, \\forall t \\in \\{1,\\dots, T\\}
```
"""
struct StorageTotalReserveConstraint <: ConstraintType end

"""
Struct to specify the auxiliary constraints for regularization terms in the objective function for the charge variable.
Used when the attribute `regularization = true`.

The specified constraints are formulated as:

```math
\\begin{align*}
& \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t-1} sb_{stc,p,t-1} + p^{st,ch}_{t-1}  - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t-1} sb_{stc,p,t-1}\\right) - \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t} sb_{stc,p,t} + p^{st,ch}_{t}  - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t} sb_{stc,p,t}\\right) \\le z^{st, ch}_{t}, \\forall t \\in \\{2,\\dots, T\\}\\\\
& \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t-1} sb_{stc,p,t-1} + p^{st,ch}_{t-1}  - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t-1} sb_{stc,p,t-1}\\right) - \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t} sb_{stc,p,t} + p^{st,ch}_{t}  - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t} sb_{stc,p,t}\\right) \\ge -z^{st, ch}_{t}, \\forall t \\in \\{2,\\dots, T\\}
\\end{align*}
```
"""
struct StorageRegularizationConstraintCharge <: ConstraintType end

"""
Struct to specify the auxiliary constraints for regularization terms in the objective function for the discharge variable.
Used when the attribute `regularization = true`.

The specified constraints are formulated as:

```math
\\begin{align*}
& \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t-1} sb_{std,p,t-1} + p^{st,ds}_{t-1} - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t-1} sb_{std,p,t-1}\\right) -\\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t} sb_{std,p,t} + p^{st,ds}_{t} - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\text{dn}}} R^*_{p,t} sb_{std,p,t}\\right) \\le z^{st, ds}_{t}, \\forall t \\in \\{2,\\dots, T\\}\\\\
& \\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t-1} sb_{std,p,t-1} + p^{st,ds}_{t-1} - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{dn}}} R^*_{p,t-1} sb_{std,p,t-1}\\right) -\\left(\\sum_{p \\in \\mathcal{P}^{\\text{as}_\\text{up}}} R^*_{p,t} sb_{std,p,t} + p^{st,ds}_{t} - \\sum_{p \\in \\mathcal{P}^{\\text{as}_\text{dn}}} R^*_{p,t} sb_{std,p,t}\\right) \\ge -z^{st, ds}_{t}, \\forall t \\in \\{2,\\dots, T\\}
\\end{align*}
```
"""
struct StorageRegularizationConstraintDischarge <: ConstraintType end

"""
Struct to create the constraint to balance shifted power over the user-defined time horizons.
For more information check the [`PowerLoadShift`](@ref) formulation.
The specified constraints are formulated as:
```math
\\sum_{t \\in \\text{time horizon}_k } p_t^\\text{shift,up} - p_t^\\text{shift,dn} = 0 , \\quad \\forall k \\text{ time horizons}
```
"""
struct ShiftedActivePowerBalanceConstraint <: ConstraintType end

"""
Struct to create the constraint to balance shifted power over the user-defined time horizons.
For more information check the [`PowerLoadShift`](@ref) formulation.
The specified constraints are formulated as:
```math
p_t^\\text{realized} \\ge 0.0 , \\quad \\forall k \\text{ time horizons}
```
"""
struct RealizedShiftedLoadMinimumBoundConstraint <: ConstraintType end

"""
Struct to create the non-anticipativity constraint for the [`PowerLoadShift`](@ref) formulation.
This enforces that shift up can only occur after an equal or greater amount of shift down has
already been committed, preventing the optimizer from shifting load up before it has been
shifted down. The constraint is formulated as:

```math
\\sum_{\\tau=1}^{t} \\left( p_\\tau^\\text{shift,dn} - p_\\tau^\\text{shift,up} \\right) \\ge 0,
\\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct NonAnticipativityConstraint <: ConstraintType end

"""
Struct to create the constraint to limit shifted power active power between upper and lower bounds.
For more information check the [`PowerLoadShift`](@ref) formulation.
The specified constraints are formulated as:
```math
0 \\le p_t^\\text{shift, up} \\le P_t^\\text{upper}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ShiftUpActivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end

"""
Struct to create the constraint to limit shifted power active power between upper and lower bounds.
For more information check the [`PowerLoadShift`](@ref) formulation.
The specified constraints are formulated as:
```math
0 \\le p_t^\\text{shift, dn} \\le P_t^\\text{lower}, \\quad \\forall t \\in \\{1,\\dots,T\\}
```
"""
struct ShiftDownActivePowerVariableLimitsConstraint <: PowerVariableLimitsConstraint end

#################################################################################
# Hybrid System Constraints
#################################################################################

"""
Couples the hybrid PCC reserve variables (out + in) to the system-level
`ActivePowerReserveVariable` of each service the hybrid participates in.
"""
struct HybridReserveAssignmentConstraint <: ConstraintType end

"""
Couples the hybrid PCC reserve variables (out + in) to the sum of per-subcomponent reserve
allocations (thermal + renewable + charging + discharging).
"""
struct HybridReserveBalanceConstraint <: ConstraintType end

"""
Equates the hybrid's PCC active-power injection to the sum of internal subcomponent
flows (thermal + renewable + storage discharge - storage charge - load) net of served
reserves.
"""
struct HybridEnergyAssetBalanceConstraint <: ConstraintType end

"""
Status link between a hybrid PCC active-power variable and the reservation variable.
Parametric on [`ReserveSide`](@ref).
"""
struct HybridStatusOnConstraint{Sd <: ReserveSide} <: ConstraintType end

"""
Bound between thermal subcomponent power and its commitment status (no-reserves case).
Parametric on `BoundDirection` (from IOM).
"""
struct HybridThermalOnVariableConstraint{B <: IOM.BoundDirection} <: ConstraintType end

"Range constraint on thermal subcomponent power including up/down reserves."
struct HybridThermalReserveLimitConstraint <: ConstraintType end

"Upper bound on renewable subcomponent power from the time-series forecast."
struct HybridRenewableActivePowerLimitConstraint <: ConstraintType end

"Range constraint on renewable subcomponent power including up/down reserves."
struct HybridRenewableReserveLimitConstraint <: ConstraintType end

"Energy balance for the storage subcomponent of a hybrid system, including reserve deployment."
struct HybridStorageBalanceConstraint <: ConstraintType end

"""
Mutually-exclusive charge/discharge limit for the hybrid storage subcomponent
(no-reserves case). Parametric on [`ReserveSide`](@ref).
"""
struct HybridStorageStatusOnConstraint{Sd <: ReserveSide} <: ConstraintType end

"""
Charge- or discharge-side power limit for the hybrid storage subcomponent including
reserve carve-outs. Parametric on [`ReserveSide`](@ref).
"""
struct HybridStorageReservePowerLimitConstraint{Sd <: ReserveSide} <: ConstraintType end

"""
Bounds the absolute charge- or discharge-power step change between consecutive time
steps, penalizing oscillation. Active only when the hybrid `\"regularization\"`
attribute is set. Parametric on [`ReserveSide`](@ref).
"""
struct RegularizationConstraint{Sd <: ReserveSide} <: ConstraintType end

"""
End-of-period energy target for the storage subcomponent of a hybrid system.
Used when the attribute `energy_target = true`.

Like the storage [`StateofChargeTargetConstraint`](@ref), this is a soft equality with
non-negative surplus ([`HybridEnergySurplusVariable`](@ref), energy above target) and
shortage ([`HybridEnergyShortageVariable`](@ref), energy below target) slacks penalized
in the objective:

```math
e^{st}_{T} - e^{st+} + e^{st-} = E^{st}_{T}.
```
"""
struct HybridEnergyTargetConstraint <: ConstraintType end

"""
Offline-capability band row for commitment formulations whose
[`offline_reserve_in_range_ub`](@ref) trait is `false`: their commitment-gated range
expression stays `p + online`, and this row adds the offline awards back against the
static capability (`q_limit = pmax`):

`p + online + offline <= pmax * u + q_limit * (1 - u) = pmax`

Committed: offline competes with the online products for the HSL band. Off: the
semi-continuous range row zeroes `p` and the online awards, leaving `offline <= q_limit`.
Single award variable per (device, service): the device's merged offer curve prices both
provision states (documented approximation).
"""
struct OfflineReserveBandConstraint <: ConstraintType end
