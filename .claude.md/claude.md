# Claude Code Guidelines for PowerOperationsModels.jl

**Package role:** Utility foundation library
**Julia compat:** ^1.10

## Overview

Modeling library for power systems operations. For general Sienna coding practices, conventions, and performance guidelines, see [Sienna.md](Sienna.md). Always check both files before making plans or changes. **Update [claude.md](claude.md) whenever the file/directory structure changes.**

## Design Philosophy: Layered Abstractions

This project implements a **three-tier abstraction hierarchy** for building operational optimization problems in power systems. Each layer has a specific responsibility and level of abstraction:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ABSTRACTION HIERARCHY                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  HIGHEST LEVEL: InfrastructureSystems.jl (IS)                     │  │
│  │  ─────────────────────────────────────────                        │  │
│  │  • Base infrastructure types and interfaces                       │  │
│  │  • Optimization key types (VariableKey, ConstraintKey, etc.)      │  │
│  │  • Time series infrastructure                                     │  │
│  │  • Generic system component abstractions                          │  │
│  │  • Domain-agnostic utilities                                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                              ▲                                          │
│                              │ extends                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  MID LEVEL: InfrastructureOptimizationModels.jl (IOM)             │  │
│  │  ─────────────────────────────────────────────                    │  │
│  │  • OptimizationContainer: JuMP model wrapper                      │  │
│  │  • DeviceModel, ServiceModel, NetworkModel specifications         │  │
│  │  • ProblemTemplate: optimization problem structure                │  │
│  │  • DecisionModel, EmulationModel: execution frameworks            │  │
│  │  • Common model construction patterns (add_variables!,            │  │
│  │    add_constraints!, add_to_expression!, etc.)                    │  │
│  │  • Objective function infrastructure                              │  │
│  │  • Initial conditions handling                                    │  │
│  │  • Power-system agnostic optimization building blocks             │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                              ▲                                          │
│                              │ implements                               │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  IMPLEMENTATION LEVEL: PowerOperationsModels.jl (POM)             │  │
│  │  ─────────────────────────────────────────────                    │  │
│  │  • Device-specific formulations (ThermalBasicUnitCommitment,      │  │
│  │    RenewableFullDispatch, StaticBranch, HVDCTwoTerminalDispatch)  │  │
│  │  • Variable types (ActivePowerVariable, OnVariable, StartVariable)│  │
│  │  • Constraint types (device-specific operational constraints)     │  │
│  │  • Network formulations (CopperPlate, PTDF, PowerModels-based)    │  │
│  │  • Service models (reserves, AGC, transmission interfaces)        │  │
│  │  • Concrete implementations using IOM infrastructure              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why This Separation Matters

1. **InfrastructureSystems (IS)** provides the highest-level abstractions that are reusable across any infrastructure domain—not just power systems. It defines key types, time series handling, and generic optimization interfaces.

2. **InfrastructureOptimizationModels (IOM)** builds on IS to provide optimization-specific infrastructure. It defines how to construct, manage, and solve optimization models without knowing the specifics of power system devices. This layer handles the "how" of building optimization problems.

3. **PowerOperationsModels (POM)** implements the actual power system device models. It defines the "what"—the specific variables, constraints, and formulations for thermal generators, renewable generators, storage, HVDC lines, loads, and network representations.

This separation enables:
- **Reusability**: IOM can be used for non-power-system optimization problems
- **Maintainability**: Changes to device formulations don't affect the optimization infrastructure
- **Extensibility**: New device types can be added by implementing IOM interfaces
- **Testing**: Each layer can be tested independently

## PowerModels Submodule

The repository includes an embedded **PowerModels submodule** (`src/PowerModels/`) containing code adapted from PowerModels.jl. This provides power flow formulations without requiring the external PowerModels.jl dependency.

The submodule provides:
- AC power flow formulations (ACP, ACR, ACT)
- DC power flow formulations (DCP)
- Linear approximations (LPAC)
- SDP relaxations (WR, WRM)
- Branch flow formulations (BF, IV)
- Optimal power flow problem definitions

```
src/PowerModels/
├── PowerModels.jl  # Submodule entry point
├── core/           # Formulation infrastructure (base, constraint, variable, etc.)
├── form/           # Power flow formulations (acp.jl, dcp.jl, lpac.jl, etc.)
├── prob/           # Problem definitions (opf.jl, ots.jl, pf_bf.jl, etc.)
└── util/           # Utilities (flow_limit_cuts.jl, obbt.jl)
```

There is also an **InfrastructureModels submodule** (`src/InfrastructureModels/`) containing generic optimization infrastructure adapted from InfrastructureModels.jl:

```
src/InfrastructureModels/
├── InfrastructureModels.jl  # Submodule entry point
└── core/                    # Base types, data handling, constraints, solution processing
```

## Repository Structure

> **Maintenance note:** Update this section whenever files or directories are added, moved, or removed. Stale structure documentation leads to incorrect assumptions during planning.

```
PowerOperationsModels.jl/
├── src/
│   ├── PowerOperationsModels.jl            # Main module entry point (all includes/exports here)
│   ├── area_interchange.jl                 # Area interchange balance
│   ├── core/                               # Type definitions (no implementation logic)
│   │   ├── definitions.jl                  # Shared constants and aliases
│   │   ├── physical_constant_definitions.jl# Physical constants (base MVA, etc.)
│   │   ├── variables.jl                    # Variable types (ActivePowerVariable, etc.)
│   │   ├── auxiliary_variables.jl          # Auxiliary variable types
│   │   ├── constraints.jl                  # Constraint types
│   │   ├── expressions.jl                  # Expression types
│   │   ├── parameters.jl                   # Parameter types
│   │   ├── formulations.jl                 # Device formulation abstract types
│   │   ├── network_formulations.jl         # Network model formulation types
│   │   ├── initial_conditions.jl           # Initial condition types
│   │   ├── feedforward_interface.jl        # Feedforward constraint interface
│   │   └── default_interface_methods.jl    # Default fallback implementations
│   ├── common_models/                      # Shared model-building utilities
│   │   ├── add_expressions.jl              # add_expressions! implementations
│   │   ├── add_parameters.jl               # add_parameters! implementations
│   │   ├── add_to_expression.jl            # add_to_expression! implementations
│   │   ├── make_system_expressions.jl      # System-level expression construction
│   │   ├── market_bid_overrides.jl         # Market bid cost overrides
│   │   └── reserve_range_constraints.jl    # Reserve range constraint helpers
│   ├── initial_conditions/
│   │   ├── device_initial_conditions.jl    # Device IC initialization
│   │   └── update_initial_conditions.jl    # IC update between solves
│   ├── static_injector_models/             # Generator and load device models
│   │   ├── thermal_generation.jl           # Thermal unit formulations
│   │   ├── thermalgeneration_constructor.jl
│   │   ├── renewable_generation.jl         # Renewable formulations
│   │   ├── renewablegeneration_constructor.jl
│   │   ├── hydro_generation.jl             # Hydro formulations
│   │   ├── hydrogeneration_constructor.jl
│   │   ├── electric_loads.jl               # Load formulations
│   │   ├── load_constructor.jl
│   │   ├── source.jl                       # Generic source model
│   │   ├── source_constructor.jl
│   │   ├── reactivepower_device.jl         # Reactive power device (SynCon)
│   │   ├── reactivepowerdevice_constructor.jl
│   │   └── static_injection_security_constrained_models.jl
│   ├── ac_transmission_models/
│   │   ├── AC_branches.jl                  # AC line/transformer formulations
│   │   └── branch_constructor.jl
│   ├── twoterminal_hvdc_models/
│   │   ├── TwoTerminalDC_branches.jl       # Two-terminal HVDC formulations
│   │   └── branch_constructor.jl
│   ├── mt_hvdc_models/
│   │   ├── HVDCsystems.jl                  # Multi-terminal HVDC formulations
│   │   └── hvdcsystems_constructor.jl
│   ├── services_models/
│   │   ├── reserves.jl                     # Reserve formulations
│   │   ├── reserve_group.jl                # Reserve group constraints
│   │   ├── agc.jl                          # AGC formulations
│   │   ├── transmission_interface.jl       # Transmission interface limits
│   │   ├── service_slacks.jl               # Service slack variables
│   │   └── services_constructor.jl
│   ├── network_models/
│   │   ├── copperplate_model.jl            # CopperPlate (no network)
│   │   ├── area_balance_model.jl           # Area-level balance
│   │   ├── hvdc_networks.jl                # HVDC network models
│   │   ├── hvdc_network_constructor.jl
│   │   ├── network_slack_variables.jl      # Network slack variables
│   │   ├── pm_translator.jl                # PowerModels data translation
│   │   ├── powermodels_interface.jl        # PM formulation interface
│   │   ├── security_constrained_models.jl  # N-1 security constraints
│   │   ├── instantiate_network_model.jl    # Network model instantiation
│   │   └── network_constructor.jl
│   ├── InfrastructureModels/               # Embedded InfrastructureModels submodule
│   │   ├── InfrastructureModels.jl
│   │   └── core/                           # Base types, data, constraints, solution
│   └── PowerModels/                        # Embedded PowerModels submodule
│       ├── PowerModels.jl
│       ├── core/                           # Formulation infrastructure
│       ├── form/                           # AC/DC power flow formulations
│       ├── prob/                           # OPF/OTS problem definitions
│       └── util/                           # Flow limit cuts, OBBT
├── ext/
│   └── PowerFlowsExt/
│       └── PowerFlowsExt.jl                # PowerFlows.jl extension
├── test/
│   ├── runtests.jl
│   ├── includes.jl
│   ├── test_device_thermal_generation_constructors.jl
│   ├── test_device_renewable_generation_constructors.jl
│   ├── test_device_hydro_constructors.jl
│   ├── test_device_load_constructors.jl
│   ├── test_device_source_constructors.jl
│   ├── test_device_branch_constructors.jl
│   ├── test_device_hvdc.jl
│   ├── test_device_lcc.jl
│   ├── test_device_synchronous_condenser_constructors.jl
│   ├── test_utils/                         # Shared test helpers and systems
│   │   ├── common_operation_model.jl
│   │   ├── mock_operation_models.jl
│   │   ├── model_checks.jl
│   │   ├── operations_problem_templates.jl
│   │   ├── solver_definitions.jl
│   │   ├── iec_test_systems.jl
│   │   ├── iec_simulation_utils.jl
│   │   ├── mbc_system_utils.jl
│   │   └── add_market_bid_cost.jl
│   └── performance/
│       └── performance_test.jl
├── scripts/
│   └── formatter/
│       ├── formatter_code.jl               # Run with: julia -e 'include("scripts/formatter/formatter_code.jl")'
│       └── Project.toml
├── docs/
├── Project.toml
└── Manifest.toml
```

IOM (`InfrastructureOptimizationModels.jl`) and IS (`InfrastructureSystems.jl`) are **external package dependencies**, not subdirectories of this repo. They are resolved via `Project.toml`.

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `InfrastructureSystems.jl` | Base infrastructure, optimization key types (highest abstraction) |
| `PowerSystems.jl` | Power system data structures (devices, services, networks) |
| `JuMP.jl` | Mathematical optimization modeling |
| `PowerModels.jl` | Power flow formulations (via extension, optional) |
| `PowerFlows.jl` | Power flow calculations |
| `PowerNetworkMatrices.jl` | PTDF, LODF matrices |

## Type Aliases

We don't create const type aliases anymore, the preferd way to work is to use `import PowerSystems as PSY` or more generally `import DEPENDENCY as DEP` for any other package.

```julia
import PowerModels as PM
import PowerSystems as PSY
import InfrastructureOptimizationModels as IOM
import InfrastructureSystems as IS
import InfrastructureSystems.Optimization as ISOPT
import MathOptInterface as MOI
import PowerNetworkMatrices as PNM
import PowerFlows as PFS
```
## Architecture Patterns

### Device Model Construction (Two-Stage Pattern)

Models follow a two-stage construction pattern with `construct_device!`:

```julia
# Stage 1: ArgumentConstructStage - Add variables and parameters
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    device_model::DeviceModel{T, Formulation},
    network_model::NetworkModel{N},
) where {T <: PSY.Device, N <: PM.AbstractPowerModel}
    devices = get_available_components(device_model, sys)
    add_variables!(container, VariableType, devices, Formulation())
    add_parameters!(container, ParameterType, devices, device_model)
    add_to_expression!(container, ExpressionType, VariableType, devices, device_model, network_model)
    add_feedforward_arguments!(container, device_model, devices)
    return
end

# Stage 2: ModelConstructStage - Add constraints
function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    device_model::DeviceModel{T, Formulation},
    network_model::NetworkModel{N},
) where {T <: PSY.Device, N <: PM.AbstractPowerModel}
    devices = get_available_components(device_model, sys)
    add_constraints!(container, ConstraintType, devices, device_model, network_model)
    add_feedforward_constraints!(container, device_model, devices)
    objective_function!(container, devices, device_model, N)
    add_constraint_dual!(container, sys, device_model)
    return
end
```

### Key Types

- `OptimizationContainer`: Central container holding JuMP model, variables, constraints, parameters (IOM)
- `DeviceModel{D, F}`: Specifies device type `D` and formulation `F` (IOM)
- `ServiceModel{S, F}`: Specifies service type `S` and formulation `F` (IOM)
- `NetworkModel{N}`: Network formulation wrapper (IOM)
- `ProblemTemplate`: Defines optimization problem structure (IOM)
- `DecisionModel`: Single-shot optimization model (IOM)
- `EmulationModel`: Rolling-horizon simulation model (IOM)

## Coding Style Requirements

Naming conventions, documentation practices, performance guidelines, and general Julia style are in [Sienna.md](Sienna.md). POM-specific conventions:

### Code Organization

- One type per file when the type has significant methods
- Group related functions in the same file
- Use `include()` statements in main module file to control load order
- Keep files focused and reasonably sized

### Type Annotations

- Use type annotations on function arguments for dispatch
- Use parametric types with `where` clauses for flexibility
- Prefer abstract types in signatures for extensibility

```julia
# Good: Flexible parametric signature
function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model::DeviceModel{D, F},
    network_model::NetworkModel{N},
) where {T <: ConstraintType, U <: Union{Vector, IS.FlattenIteratorWrapper}, D <: PSY.Device, F, N}
```

## Testing

### Running Tests

```julia
using Pkg
Pkg.test("PowerOperationsModels")

# Or for InfrastructureOptimizationModels specifically
cd("InfrastructureOptimizationModels.jl")
Pkg.test()
```

### Test Utilities

- Use `HiGHS` for LP/MIP testing
- Use `Ipopt` for nonlinear testing
- Use `PowerSystemCaseBuilder` for test systems

## Common Development Tasks

### Adding a New Device Formulation

1. Define the formulation type in `src/core/formulations.jl`
2. Implement `construct_device!` for both `ArgumentConstructStage` and `ModelConstructStage`
3. Add variable/constraint types if needed in `src/core/`
4. Register exports in main module
5. Add tests

### Adding a New Variable Type

```julia
# In src/core/variables.jl
struct MyNewVariable <: VariableType end

# Implement add_variables! method
function add_variables!(
    container::OptimizationContainer,
    ::Type{MyNewVariable},
    devices::U,
    formulation::F,
) where {U, F}
    # Implementation using IOM infrastructure
end

# Export in main module
export MyNewVariable
```

## Important Notes

1. **Layer Boundaries**: Respect the abstraction hierarchy. Device-specific code belongs in POM, optimization infrastructure in IOM, base types in IS.

2. **Method Ambiguity**: The codebase uses extensive multiple dispatch. Check for ambiguity with `Test.detect_ambiguities`.

3. **Network Model Compatibility**: Not all device formulations work with all network models. Check existing signatures.

4. **PowerModels Extension**: The PM extension is optional. Code should work with simpler network models when PM is not loaded.

5. **Expression Order**: `add_expressions!` must come before `add_constraints!` that use those expressions.

## Debugging

- Enable debug logging: `ENV["SIIP_LOGGING_CONFIG"] = "debug"`
- Use `LOG_GROUP_*` constants for targeted debug output
- Check `optimization_debugging.jl` for debugging utilities
