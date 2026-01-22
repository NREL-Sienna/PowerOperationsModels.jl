# Claude Code Guidelines for PowerOperationsModels.jl

## Project Overview

**PowerOperationsModels.jl** is a Julia package that contains optimization models for power system components. It is part of the NLR Sienna ecosystem for power system modeling and simulation.

**Note:** NREL (National Renewable Energy Laboratory) no longer exists and has been renamed to NLR (National Laboratory of the Rockies). References to "NREL-Sienna" in the codebase refer to the organization now known as Sienna only and the official name is NLR National Laboratory of the Rockies (formerly known as NREL).

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

## PowerModels Extension

The repository includes a **PowerModels.jl extension** (`ext/PowerModelsExt/`) that contains code originally from PowerModels.jl. This was done for two key reasons:

1. **Reduced Dependency Overhead**: By extracting only the necessary power flow formulations into an extension, we avoid loading the entire PowerModels.jl package when it's not needed. The extension is only loaded when PowerModels.jl is explicitly imported by the user.

2. **Better Abstraction Alignment**: The extracted code has been restructured to fit the IOM abstraction patterns, providing cleaner interfaces between power flow formulations and the optimization model construction.

The extension provides:
- AC power flow formulations (ACP, ACR, ACT)
- DC power flow formulations (DCP)
- Linear approximations (LPAC)
- SDP relaxations (WR, WRM)
- Branch flow formulations (BF, IV)
- Optimal power flow problem definitions

```
ext/PowerModelsExt/
├── core/           # Formulation infrastructure (base, constraint, variable, etc.)
├── form/           # Power flow formulations (acp.jl, dcp.jl, lpac.jl, etc.)
├── prob/           # Problem definitions (opf.jl, ots.jl, pf_bf.jl, etc.)
└── util/           # Utilities (flow_limit_cuts.jl, obbt.jl)
```

## Repository Structure

This is a **dual-structure repository**:

```
PowerOperationsModels.jl/
├── src/                                    # POM: Device-specific models
│   ├── PowerOperationsModels.jl            # Main module entry point
│   ├── core/                               # Type definitions
│   │   ├── variables.jl                    # Variable types (ActivePowerVariable, etc.)
│   │   ├── constraints.jl                  # Constraint types
│   │   ├── expressions.jl                  # Expression types
│   │   ├── parameters.jl                   # Parameter types
│   │   ├── formulations.jl                 # Device formulation abstractions
│   │   └── network_formulations.jl         # Network model formulations
│   ├── static_injector_models/             # Generator, load, source models
│   │   ├── thermal_generation.jl           # Thermal unit formulations
│   │   ├── renewable_generation.jl         # Renewable formulations
│   │   ├── electric_loads.jl               # Load formulations
│   │   └── *_constructor.jl                # Construction dispatch
│   ├── ac_transmission_models/             # AC branch models
│   ├── twoterminal_hvdc_models/            # Two-terminal HVDC
│   ├── mt_hvdc_models/                     # Multi-terminal HVDC
│   ├── services_models/                    # Reserves, AGC, interfaces
│   └── network_models/                     # Network formulations
│
├── ext/PowerModelsExt/                     # PowerModels.jl extension
│   ├── core/                               # Formulation infrastructure
│   ├── form/                               # Power flow formulations
│   ├── prob/                               # Problem definitions
│   └── util/                               # Utilities
│
├── InfrastructureOptimizationModels.jl/    # IOM: Optimization infrastructure
│   └── src/
│       ├── InfrastructureOptimizationModels.jl
│       ├── core/                           # Fundamental structures
│       │   ├── optimization_container.jl   # Central JuMP container
│       │   ├── device_model.jl             # Device model specification
│       │   ├── service_model.jl            # Service model specification
│       │   ├── network_model.jl            # Network model wrapper
│       │   └── initial_conditions.jl       # IC types
│       ├── common_models/                  # Reusable construction patterns
│       │   ├── add_variable.jl             # Variable addition interface
│       │   ├── add_constraints.jl          # Constraint interface
│       │   ├── add_to_expression.jl        # Expression building
│       │   ├── construct_device.jl         # Device construction dispatcher
│       │   └── objective_function.jl       # Objective interface
│       ├── operation/                      # Model execution
│       │   ├── decision_model.jl           # Single-shot optimization
│       │   ├── emulation_model.jl          # Rolling-horizon simulation
│       │   └── problem_template.jl         # Problem specification
│       ├── objective_function/             # Cost implementations
│       ├── initial_conditions/             # IC handling
│       └── utils/                          # Utilities
│
├── InfrastructureSystems.jl/               # IS: Base infrastructure (dependency)
│
├── test/                                   # Integration tests
├── docs/                                   # Documentation
├── Project.toml                            # Package dependencies
└── Manifest.toml                           # Locked dependencies
```

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

```julia
const PM = PowerModels
const PSY = PowerSystems
const IOM = InfrastructureOptimizationModels
const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const MOI = MathOptInterface
const PNM = PowerNetworkMatrices
const PFS = PowerFlows
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

This repository follows the [InfrastructureSystems.jl Style Guide](https://nrel-sienna.github.io/InfrastructureSystems.jl/stable/style/):

### Naming Conventions

- **Types**: `PascalCase` (e.g., `ActivePowerVariable`, `FlowRateConstraint`)
- **Functions**: `snake_case` (e.g., `add_variables!`, `construct_device!`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `LOG_GROUP_BRANCH_CONSTRUCTIONS`)
- **Mutating functions**: End with `!` (e.g., `build!`, `solve!`, `add_constraints!`)

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

### Documentation

Follow [InfrastructureSystems.jl Documentation Best Practices](https://nrel-sienna.github.io/InfrastructureSystems.jl/stable/docs_best_practices/explanation/):

```julia
"""
$(TYPEDSIGNATURES)

Brief description of what the function does.

# Arguments
- `container::OptimizationContainer`: The optimization container
- `devices`: Iterable of devices to process

# Returns
Nothing, modifies `container` in place.
"""
function add_variables!(container, devices)
    # implementation
end
```

## Julia Performance Best Practices

All code must follow Julia performance best practices:

### Type Stability
- Ensure functions are type-stable (return type depends only on input types)
- Avoid containers with abstract element types
- Use `@code_warntype` to check for type instabilities

### Avoid Global Variables
- Never use non-const global variables in performance-critical code
- Pass data through function arguments

### Preallocate Arrays
```julia
# Good: Preallocated
results = Vector{Float64}(undef, n)
for i in 1:n
    results[i] = compute(i)
end
```

### Use Views for Slices
```julia
# Good: Creates view (no allocation)
subarray = @view array[1:100]
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
