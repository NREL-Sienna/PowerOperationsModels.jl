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

@info pkgdir(PowerOperationsModels)

function is_running_on_ci()
    return get(ENV, "CI", "false") == "true" || haskey(ENV, "GITHUB_ACTIONS")
end

open("cats_precompile_time.txt", "a") do io
    if length(ARGS) == 0 && !is_running_on_ci()
        push!(ARGS, "Local Test")
    end
    write(io, "| $(ARGS[1]) | $(precompile_time.time) |\n")
end

try
    # TODO Should probably be passed through argv but I think Github CI uses 
    # argv already somehow?
    cats_dir = "/Users/acostare/Documents/CATS-CaliforniaTestSystem/"
    include(joinpath(cats_dir, "Sienna/build_CATS.jl"))
    sys = build_CATS_system(first_order = true)
    transform_single_time_series!(sys, Hour(48), Hour(24))

    for i in 1:2
        template = ProblemTemplate(NetworkModel(PTDFPowerModel))
        model = DecisionModel(template, sys; name = "CATS_UC", optimizer = HiGHS.Optimizer)

        # Build
        _, time_build, _, _ = @timed begin
            output_dir = mktempdir(; cleanup = true)
            status = build!(model; output_dir = joinpath(output_dir, "CATS_UC"))
        end
        build_ok = status == IOM.ModelBuildStatus.BUILT 
        name = i > 1 ? "Postcompile" : "Precompile"
        open("cats_build_time.txt", "a") do io
            if build_ok
                write(io, "| $(ARGS[1])-Build Time $name | $(time_build) |\n")
            else
                write(io, "| $(ARGS[1])-Build Time $name | FAILED TO TEST |\n")
            end
        end

        # TODO CATS fails to solve at the moment.
        # # Solve
        # _, time_solve, _, _ = @timed begin
        #     solve = solve!(model)
        # end
        # solve_ok = solve == IOM.RunStatus.SUCCESSFULLY_FINALIZED
        # open("cats_solve_time.txt", "a") do io
        #     if solve_ok
        #         write(io, "| $(ARGS[1])-Solve Time $name | $(time_solve) |\n")
        #     else
        #         write(io, "| $(ARGS[1])-Solve Time $name | FAILED TO TEST |\n")
        #     end
        # end
    end
catch e
    rethrow(e)
    open("cats_build_time.txt", "a") do io
        write(io, "| $(ARGS[1])-Build Time | FAILED TO TEST |\n")
    end
end

if !is_running_on_ci()
    for file in ["cats_precompile_time.txt", "cats_build_time.txt", "cats_solve_time.txt"]
        name = replace(file, "_" => " ")[begin:(end - 4)]
        println("$name:")
        for line in eachline(open(file))
            println("\t", line)
        end
    end
end
