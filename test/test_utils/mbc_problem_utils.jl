"""
Problem-only port of PSI's `test/test_utils/mbc_simulation_utils.jl`.

PSI's original harness ran each fixture as both a single problem and a full
`Simulation`, to catch divergence between the two paths. POM has no `Simulation`, so
this file keeps only the single-problem path (`run_generic_mbc_prob`), which is what
these tests use to check MarketBidCost coefficient wiring end to end via solved
objective values.
"""

const FormulationDict =
    Dict{Type{<:PSY.Device}, Union{DeviceModel, Type{<:IOM.AbstractDeviceFormulation}}}
const DEFAULT_FORMULATIONS =
    FormulationDict(
        ThermalStandard => ThermalBasicUnitCommitment,
        PowerLoad => StaticPowerLoad,
        InterruptiblePowerLoad => PowerLoadInterruption,
        RenewableDispatch => RenewableFullDispatch,
    )

function set_formulations!(
    template::PowerOperationsProblemTemplate,
    sys::PSY.System,
    device_to_formulation::FormulationDict,
)
    for (device, formulation) in device_to_formulation
        if !isempty(get_components(device, sys))
            _set_formulations_helper(template, device, formulation)
        end
    end
    for (device, formulation) in DEFAULT_FORMULATIONS
        if !haskey(device_to_formulation, device) && !isempty(get_components(device, sys))
            _set_formulations_helper(template, device, formulation)
        end
    end
    return
end

_set_formulations_helper(
    template::PowerOperationsProblemTemplate,
    device::Type{<:PSY.Device},
    formulation::Type{<:IOM.AbstractDeviceFormulation},
) =
    set_device_model!(template, device, formulation)
_set_formulations_helper(
    template::PowerOperationsProblemTemplate,
    _,
    device_model::DeviceModel,
) =
    set_device_model!(template, device_model)

const _ANY_MBC = Union{PSY.MarketBidCost, PSY.MarketBidTimeSeriesCost}
_is_mbc(::_ANY_MBC) = true
_is_mbc(::PSY.OperationalCost) = false

function build_generic_mbc_model(
    sys::System;
    multistart::Bool = false,
    standard::Bool = false,
    device_to_formulation = FormulationDict(),
)
    template = PowerOperationsProblemTemplate(
        NetworkModel(
            CopperPlateNetworkModel;
            duals = [CopperPlateBalanceConstraint],
        ),
    )

    set_formulations!(template, sys, device_to_formulation)
    if standard
        set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    end
    if multistart
        set_device_model!(template, ThermalMultiStart, ThermalMultiStartUnitCommitment)
    end

    model = DecisionModel(
        template,
        sys;
        name = "UC",
        store_variable_names = true,
        optimizer = HiGHS_optimizer_small_gap,
    )
    return model
end

function run_generic_mbc_prob(
    sys::System;
    multistart::Bool = false,
    standard = false,
    test_success = true,
    is_decremental::Bool = false,
    device_to_formulation = FormulationDict(),
)
    model = build_generic_mbc_model(
        sys;
        multistart = multistart,
        standard = standard,
        device_to_formulation = device_to_formulation,
    )
    build_result = build!(model; output_dir = mktempdir())
    test_success && @test build_result == IOM.ModelBuildStatus.BUILT
    solve_result = solve!(model)
    test_success && @test solve_result == IOM.RunStatus.SUCCESSFULLY_FINALIZED
    res = OptimizationProblemOutputs(model)
    return model, res
end

# Layer of indirection kept for parity with PSI/IEC's simulation-shaped result readers:
# a problem-only result is a single DataFrame, so it is wrapped to look like the
# per-step SortedDict a simulation result would produce.
_maybe_upgrade_to_dict(input::AbstractDict) = input
_maybe_upgrade_to_dict(input::DataFrame) =
    SortedDict{DateTime, DataFrame}(first(input[!, :DateTime]) => input)

read_variable_dict(
    res::IOM.OptimizationProblemOutputs,
    var_name::Type{<:IOM.VariableType},
    comp_type::Type{<:PSY.Component},
) =
    _maybe_upgrade_to_dict(read_variable(res, var_name, comp_type))

function _read_one_value(res, var_name, comp_type, unit_name)
    df = vcat(values(read_variable_dict(res, var_name, comp_type))...)
    matched = @rsubset(df, :name == unit_name)
    return sum(matched.value)
end

"Test that the two systems (typically one without time series and one with constant time series) solve to the same objective"
function test_generic_mbc_equivalence(sys0, sys1; kwargs...)
    _, res0 = run_generic_mbc_prob(sys0; kwargs...)
    _, res1 = run_generic_mbc_prob(sys1; kwargs...)
    obj_val_0 = IOM.get_objective_value(res0)
    obj_val_1 = IOM.get_objective_value(res1)
    @test isapprox(obj_val_0, obj_val_1; atol = 0.0001)
    return
end
