precompile_time = @timed using PowerOperationsModels

using PowerOperationsModels
const POM = PowerOperationsModels
using InfrastructureOptimizationModels
const IOM = InfrastructureOptimizationModels
using PowerSystems
const PSY = PowerSystems
using Logging
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using HiGHS
using Dates
using PowerFlows

@info pkgdir(PowerOperationsModels)

function is_running_on_ci()
    return get(ENV, "CI", "false") == "true" || haskey(ENV, "GITHUB_ACTIONS")
end

open("precompile_time.txt", "a") do io
    if length(ARGS) == 0 && !is_running_on_ci()
        push!(ARGS, "Local Test")
    end
    write(io, "| $(ARGS[1]) | $(precompile_time.time) |\n")
end

function set_device_models!(template::ProblemTemplate, uc::Bool = true)
    if uc
        set_device_model!(template, ThermalMultiStart, ThermalStandardUnitCommitment)
        set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
        set_device_model!(template, HydroDispatch, FixedOutput)
    else
        set_device_model!(template, ThermalMultiStart, ThermalBasicDispatch)
        set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
        set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    end

    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, DeviceModel(Line, StaticBranch))
    set_device_model!(template, Transformer2W, StaticBranchUnbounded)
    set_device_model!(template, TapTransformer, StaticBranchUnbounded)
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(VariableReserve{ReserveDown}, RangeReserve),
    )
    return template
end

try
    sys_rts_da = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
    sys_rts_rt = build_system(PSISystems, "modified_RTS_GMLC_RT_sys")

    for sys in [sys_rts_da, sys_rts_rt]
        g = get_component(ThermalStandard, sys, "121_NUCLEAR_1")
        set_must_run!(g, true)
    end

    for i in 1:2
        ptdf_da = PTDF(sys_rts_da)

        template_uc = ProblemTemplate(
            NetworkModel(
                PTDFPowerModel;
                use_slacks = true,
                PTDF_matrix = ptdf_da,
                duals = [CopperPlateBalanceConstraint],
            ),
        )
        set_device_models!(template_uc)

        template_ed = ProblemTemplate(
            NetworkModel(
                PTDFPowerModel;
                use_slacks = true,
                PTDF_matrix = PTDF(sys_rts_rt),
                duals = [CopperPlateBalanceConstraint],
            ),
        )
        set_device_models!(template_ed, false)

        uc = DecisionModel(
            template_uc,
            sys_rts_da;
            name = "UC",
            optimizer = optimizer_with_attributes(HiGHS.Optimizer,
                "mip_rel_gap" => 0.01,
                "log_to_console" => false),
            system_to_file = false,
            initialize_model = true,
            optimizer_solve_log_print = false,
            direct_mode_optimizer = true,
            check_numerical_bounds = false,
        )

        ed = DecisionModel(
            template_ed,
            sys_rts_rt;
            name = "ED",
            optimizer = optimizer_with_attributes(HiGHS.Optimizer,
                "mip_rel_gap" => 0.01,
                "log_to_console" => false),
            system_to_file = false,
            initialize_model = true,
            check_numerical_bounds = false,
        )

        # Build
        _, time_build, _, _ = @timed begin
            output_dir = mktempdir(; cleanup = true)
            uc_status = build!(uc; output_dir = joinpath(output_dir, "UC"))
            ed_status = build!(ed; output_dir = joinpath(output_dir, "ED"))
        end

        build_ok =
            uc_status == IOM.ModelBuildStatus.BUILT &&
            ed_status == IOM.ModelBuildStatus.BUILT

        name = i > 1 ? "Postcompile" : "Precompile"
        open("build_time.txt", "a") do io
            if build_ok
                write(io, "| $(ARGS[1])-Build Time $name | $(time_build) |\n")
            else
                write(io, "| $(ARGS[1])-Build Time $name | FAILED TO TEST |\n")
            end
        end

        # Solve UC, transfer ICs, solve ED
        _, time_solve, _, _ = @timed begin
            uc_solve = solve!(uc)
            POM.transfer_initial_conditions!(ed, uc)
            ed_solve = solve!(ed)
        end

        solve_ok =
            uc_solve == IOM.RunStatus.SUCCESSFULLY_FINALIZED &&
            ed_solve == IOM.RunStatus.SUCCESSFULLY_FINALIZED

        open("solve_time.txt", "a") do io
            if solve_ok
                write(io, "| $(ARGS[1])-Solve Time $name | $(time_solve) |\n")
            else
                write(io, "| $(ARGS[1])-Solve Time $name | FAILED TO TEST |\n")
            end
        end
    end
catch e
    rethrow(e)
    open("build_time.txt", "a") do io
        write(io, "| $(ARGS[1])-Build Time | FAILED TO TEST |\n")
    end
end

if !is_running_on_ci()
    for file in ["precompile_time.txt", "build_time.txt", "solve_time.txt"]
        name = replace(file, "_" => " ")[begin:(end - 4)]
        println("$name:")
        for line in eachline(open(file))
            println("\t", line)
        end
    end
end
