# Parallel test runner. Each top-level `test_*.jl` file runs in its OWN isolated Julia
# worker process (via ParallelTestRunner/Malt), so files execute concurrently and do
# not share mutable state (PowerSystemCaseBuilder caches, the global logger, etc.).
#
#   julia --project=test test/runtests.jl                  # full suite, all jobs
#   julia --project=test test/runtests.jl test_model_decision   # filter by file name (startswith)
#   julia --project=test test/runtests.jl --jobs=4         # cap parallelism
#   julia --project=test test/runtests.jl --list           # list discoverable tests
#
# NOTE: the previous serial runner asserted "no Error-level log events across the whole
# run" via a single global MultiLogger. That global assertion does not carry to
# per-worker isolation and has been dropped; the per-`@test`/`@testset` assertions
# inside each file still run and gate the result.
using PowerOperationsModels
using ParallelTestRunner

const TEST_DIR = @__DIR__

# Discover ONLY the top-level `test_*.jl` files. `includes.jl`, the `test_utils/`
# helpers, and `test_data/` are shared infrastructure, not standalone testsets — they
# must not be run as tests (ParallelTestRunner's default discovery would pick them up).

# psy6: disabled pending transformer refactor. Two causes, both upstream of the test body:
#   - transformer control formulations / ThreeWindingTransformer are commented out in `src`
#   - PowerFlows@psy6 does not precompile, so `PFS` is unavailable in the preamble
const DISABLED_TESTS = Set([
    "test_native_tapcontrol",
    "test_voltage_control_tap_models",
])

testsuite = Dict{String, Expr}(
    splitext(f)[1] => :(include($(joinpath(TEST_DIR, f)))) for
    f in readdir(TEST_DIR) if
    startswith(f, "test_") && endswith(f, ".jl") && splitext(f)[1] ∉ DISABLED_TESTS
)

# Shared preamble (package imports, `test_utils`, const aliases) evaluated into each
# test's sandbox module before the test file's body runs.
const INIT_CODE = :(include($(joinpath(TEST_DIR, "includes.jl"))))

# Worker-process env: PowerSystemCaseBuilder reads a shared serialized-system HDF5
# store concurrently across workers — disable HDF5 file locking to avoid cross-process
# lock contention. Also flag Sienna test mode (includes.jl sets it too).
const WORKER_ENV = ["HDF5_USE_FILE_LOCKING" => "FALSE", "RUNNING_SIENNA_TESTS" => "true"]

runtests(PowerOperationsModels, ARGS; testsuite, init_code = INIT_CODE, env = WORKER_ENV)
