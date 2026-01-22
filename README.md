# PowerOperationsModels.jl

[![main - CI](https://github.com/NREL-Sienna/PowerOperationsModels.jl/workflows/main%20-%20CI/badge.svg)](https://github.com/NREL-Sienna/PowerOperationsModels.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/NREL-Sienna/PowerOperationsModels.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/NREL-Sienna/PowerOperationsModels.jl)
[![Documentation Build](https://github.com/NREL-Sienna/PowerOperationsModels.jl/workflows/Documentation/badge.svg?)](https://nrel-sienna.github.io/PowerOperationsModels.jl/stable)
[<img src="https://img.shields.io/badge/slack-@Sienna/PowerOperationsModels-sienna.svg?logo=slack">](https://join.slack.com/t/nrel-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)
[![PowerOperationsModels.jl Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/PowerOperationsModels)](https://pkgs.genieframework.com?packages=PowerOperationsModels)

`PowerOperationsModels.jl` is a Julia package that contains optimization models for power system components. It is part of the NREL Sienna ecosystem for power system modeling and simulation.

## Features

- Device-specific optimization models (thermal generators, renewables, storage, HVDC, loads, etc.)
- Integration with PowerSystems.jl for power system data structures
- Support for various network formulations via PowerModelsExt.jl which is code borrowed from PowerModels.jl for better integration.
- Designed to work with InfrastructureOptimizationModels.jl infrastructure

## Development

Contributions to the development and enhancement of PowerOperationsModels.jl are welcome. Please see [CONTRIBUTING.md](https://github.com/NREL-Sienna/PowerOperationsModels.jl/blob/main/CONTRIBUTING.md) for code contribution guidelines.

## License

PowerOperationsModels.jl is released under a BSD [license](https://github.com/NREL-Sienna/PowerOperationsModels.jl/blob/main/LICENSE). PowerOperationsModels.jl has been developed as part of the Sienna ecosystem at the U.S. Department of Energy's National Renewable Energy Laboratory ([NREL](https://www.nrel.gov/))
