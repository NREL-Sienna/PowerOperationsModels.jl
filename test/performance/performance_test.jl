precompile_time = @timed using PowerOperationsModels

using PowerOperationsModels
const POM = PowerOperationsModels
using InfrastructureOptimizationModels
const IOM = InfrastructureOptimizationModels
using PowerSystems
const PSY = PowerSystems
import InfrastructureSystems as IS
using Logging
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using HiGHS
using Dates

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

function set_device_models!(template::PowerOperationsProblemTemplate, uc::Bool = true)
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
    set_device_model!(template, TwoWindingTransformer, StaticBranchUnbounded)
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveUp}, RangeReserve),
    )
    set_service_model!(
        template,
        ServiceModel(OnlineReserve{ReserveDown}, RangeReserve),
    )
    return template
end

try
    # Build both systems, then merge the 5-minute SingleTimeSeries from the
    # realization system onto the DA system so a single System carries raw
    # 1-hour and 5-minute data that can be transformed separately per model.
    sys_rts_da = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
    sys_rts_rt = build_system(PSISystems, "modified_RTS_GMLC_RT_sys")

    # Drop the transform that PSB pre-baked so we can attach new per-resolution
    # transforms and leave both static series intact.
    PSY.transform_single_time_series!(
        sys_rts_da,
        Hour(48),
        Hour(24);
        resolution = Hour(1),
        delete_existing = true,
    )
    PSY.transform_single_time_series!(
        sys_rts_da,
        Hour(1),
        Minute(15);
        resolution = Minute(5),
        delete_existing = false,
    )

    for g in get_components(ThermalStandard, sys_rts_da)
        get_name(g) == "121_NUCLEAR_1" && set_must_run!(g, true)
    end

    for i in 1:2
        template_uc = PowerOperationsProblemTemplate(
            NetworkModel(
                PTDFNetworkModel;
                use_slacks = true,
                duals = [CopperPlateBalanceConstraint],
            ),
        )
        set_device_models!(template_uc)

        template_ed = PowerOperationsProblemTemplate(
            NetworkModel(
                PTDFNetworkModel;
                use_slacks = true,
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
            initialize_model = true,
            optimizer_solve_log_print = false,
            direct_mode_optimizer = true,
            check_numerical_bounds = false,
            horizon = Hour(48),
            interval = Hour(24),
            resolution = Hour(1),
        )

        ed = DecisionModel(
            template_ed,
            sys_rts_da;
            name = "ED",
            optimizer = optimizer_with_attributes(HiGHS.Optimizer,
                "mip_rel_gap" => 0.01,
                "log_to_console" => false),
            initialize_model = true,
            check_numerical_bounds = false,
            horizon = Hour(48),
            interval = Hour(24),
            resolution = Hour(1),
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
