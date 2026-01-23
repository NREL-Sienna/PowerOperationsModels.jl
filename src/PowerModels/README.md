# PowerModels

This submodule contains code derived from [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl), the Julia/JuMP package for Steady-State Power Network Optimization originally developed at Los Alamos National Laboratory (LANL).

## Purpose

PowerModels provides optimal power flow (OPF) formulations and network constraint implementations for PowerOperationsModels.jl.

## Evolution of Integration

This submodule represents the evolution of the PowerModels.jl integration that was previously embedded directly within the Sienna ecosystem packages. By restructuring this code as a submodule:

  - **Modularity**: The PowerModels.jl dependency becomes optional, reducing the dependency footprint for users who don't need AC/nonlinear power flow formulations
  - **Maintainability**: The integration code is isolated in a single location, making it easier to update and maintain
  - **Flexibility**: Users can choose whether to load PowerModels.jl based on their specific modeling needs

## Removed Components

The following components from PowerModels.jl have been intentionally excluded from this submodule, as these capabilities are provided by other packages in the Sienna ecosystem:

  - **Parsing code**: Data parsing and import functionality is handled by [PowerSystems.jl](https://github.com/NREL-Sienna/PowerSystems.jl)
  - **DC power flow**: Implemented in [PowerFlows.jl](https://github.com/NREL-Sienna/PowerFlows.jl)
  - **AC power flow (NLSolve)**: Implemented in [PowerFlows.jl](https://github.com/NREL-Sienna/PowerFlows.jl)

This submodule focuses exclusively on optimization-based formulations for use within the PowerOperationsModels.jl framework.

## Contents

The submodule includes:

  - **core/**: Fundamental data structures, variables, constraints, and objective functions
  - **form/**: Power flow formulations (ACP, ACR, ACT, DCP, LPAC, BF, WR, WRM, IV, APO)
  - **prob/**: Problem specifications (OPF, OTS, power flow variants)
  - **util/**: Utility functions including OBBT and flow limit cuts

## License

This code is distributed under the BSD 3-Clause License from Los Alamos National Security, LLC. See [LICENSE.md](LICENSE.md) for the full license text.

## Original Source

PowerModels.jl is developed and maintained by the Advanced Network Science Initiative (ANSI) at Los Alamos National Laboratory. For the original package, visit the [PowerModels.jl repository](https://github.com/lanl-ansi/PowerModels.jl).
