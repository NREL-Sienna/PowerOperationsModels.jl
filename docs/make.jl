using Documenter
import DataStructures: OrderedDict
using PowerOperationsModels
using DocumenterInterLinks

links = InterLinks(
    "PowerSystems" => "https://sienna-platform.github.io/PowerSystems.jl/stable/",
    "PowerSimulations" => "https://sienna-platform.github.io/PowerSimulations.jl/stable/",
)

include(joinpath(@__DIR__, "make_tutorials.jl"))
make_tutorials()

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Tutorials" => Any[
        "Running a Problem with Service Bids" => "tutorials/generated_service_bids.md",
    ],
    # "How to..." => Any["stub" => "how_to_guides/stub.md"],
    # "Explanation" => Any["stub" => "explanation/stub.md"],
    "Reference" => Any[
        "Formulation Library" => "reference/formulation_library.md",
        "Developers" => [
            "Developer Guidelines" => "reference/developer_guidelines.md",
            "Optimization Container Axes" => "reference/optimization_container_axes.md",
            "Internals" => "reference/internal.md",
        ],
        "Public API" => "reference/public.md",
    ],
)

makedocs(
    modules = [PowerOperationsModels],
    format = Documenter.HTML(
        prettyurls = haskey(ENV, "GITHUB_ACTIONS"),
        size_threshold = nothing,),
    sitename = "github.com/Sienna-Platform/PowerOperationsModels.jl",
    authors = "Sienna-Platform",
    pages = Any[p for p in pages],
    draft = false,
    plugins = [links],
)

deploydocs(
    repo="github.com/Sienna-Platform/PowerOperationsModels.jl",
    target="build",
    branch="gh-pages",
    devbranch="main",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)
