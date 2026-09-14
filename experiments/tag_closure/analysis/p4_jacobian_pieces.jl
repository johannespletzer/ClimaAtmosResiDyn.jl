#=
Time each piece of building the implicit Jacobian, with its compile (P4).

    julia +1.11 --project=<worktree>/.buildkite \
        experiments/tag_closure/analysis/p4_jacobian_pieces.jl <config.yml>

The inference profiles of the 0M column (`p4_inference_profile.jl`) put nearly
all of the build's growth with the tags under `args_integrator`, in
UnrolledUtilities and in the field-name sets of ClimaCore's MatrixFields. That
is where the Jacobian is built. This script builds the state the way
`AtmosSimulation` does, and then calls the pieces of `jacobian_cache` one at a
time, each through `invokelatest` so that its compile falls inside its timer:
  - each per-process list of blocks, and their merge;
  - `fallback_identity_blocks`, the `-I` blocks for every field left without one;
  - `FieldMatrix`, the matrix from the blocks;
  - `jacobian_solver_algorithm`;
  - `FieldMatrixWithSolver`, the matrix with its solver's caches.

Run it at 0 and 8 tags and compare. Each call is timed once, so a piece that an
earlier piece already compiled reads short.
=#

const T_START = time()

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaCore.MatrixFields as MatrixFields

function timed(label, f, args...; kwargs...)
    start = time()
    value = Base.invokelatest(f, args...; kwargs...)
    @printf("[pieces] %-44s %8.1f s   (since start %7.1f s)\n", label, time() - start,
        time() - T_START)
    flush(stdout)
    return value
end

config_path = ARGS[1]
name = splitext(basename(config_path))[1]
# With `split` as the second argument, the solver is P4's prototype fix, from
# `p4_split_solver.jl`, and the last piece times that solver instead.
split = length(ARGS) >= 2 && ARGS[2] in ("split", "core")
split && include(joinpath(@__DIR__, "p4_split_solver.jl"))
# With `core`, the solver is built only over the fields that couple to others,
# against a state template without the uncoupled ones, so that ClimaCore's
# name tree, and with it every complement it takes, leaves them out.
core = length(ARGS) >= 2 && ARGS[2] == "core"
import ClimaCore.Fields as Fields
config = timed("AtmosConfig", CA.AtmosConfig, config_path; job_id = "pieces_$name")
pa = config.parsed_args
params = timed("parameters", CA.ClimaAtmosParameters, config)
setup = CA.get_setup_type(pa, CA.Parameters.thermodynamics_params(params))
atmos = timed("get_atmos", CA.get_atmos, config, params; setup_type = setup)
grid = timed("get_grid", CA.get_grid, pa, params, config.comms_ctx)
spaces = timed("get_spaces", CA.get_spaces, grid)
Y = timed(
    "initial state",
    CA.Setups.initial_state,
    setup,
    params,
    atmos,
    spaces.center_space,
    spaces.face_space,
)
println("[pieces] prognostic fields: ", propertynames(Y.c))
FT = eltype(Y)

flags = timed("derivative flags", CA._derivative_flags, atmos, Y)
(; topography_flag, diffusion_flag) = flags
sgs_advection =
    timed("sgs_advection_jacobian_blocks", CA.sgs_advection_jacobian_blocks, Y, atmos)
advection = timed(
    "advection_jacobian_blocks",
    CA.advection_jacobian_blocks,
    Y,
    atmos,
    topography_flag,
)
diffusion = timed(
    "diffusion_jacobian_blocks",
    CA.diffusion_jacobian_blocks,
    Y,
    atmos,
    diffusion_flag,
)
sedimentation =
    timed("sedimentation_jacobian_blocks", CA.sedimentation_jacobian_blocks, Y, atmos)
sgs_massflux =
    timed("sgs_massflux_jacobian_blocks", CA.sgs_massflux_jacobian_blocks, Y, atmos)
process_block_pairs = timed(
    "merge_jacobian_blocks",
    CA.merge_jacobian_blocks,
    (sgs_advection..., advection..., diffusion..., sedimentation..., sgs_massflux...),
)
println("[pieces] process blocks: ", length(process_block_pairs))
fallback = timed(
    "fallback_identity_blocks",
    CA.fallback_identity_blocks,
    process_block_pairs,
    Y,
    FT,
)
println("[pieces] fallback blocks: ", length(fallback))
block_pairs = (process_block_pairs..., fallback...)
matrix = timed("FieldMatrix", MatrixFields.FieldMatrix, block_pairs...)
alg = timed(
    "jacobian_solver_algorithm",
    CA.jacobian_solver_algorithm,
    Y,
    atmos,
    diffusion_flag,
    get(pa, "approximate_linear_solve_iters", 1),
)
if core
    uncoupled = timed("uncoupled_jacobian_names", CA.uncoupled_jacobian_names, block_pairs)
    println("[pieces] uncoupled fields: ", uncoupled)
    uncoupled_strings = string.(uncoupled)
    core_c_names = Tuple(
        n for n in propertynames(Y.c) if
        !(string(CA.MatrixFields.FieldName(:c, n)) in uncoupled_strings)
    )
    core_types = Tuple{map(n -> eltype(getproperty(Y.c, n)), core_c_names)...}
    c_core = similar(Y.c, NamedTuple{core_c_names, core_types})
    Y_core = Fields.FieldVector(; c = c_core, f = Y.f)
    println("[pieces] core center fields: ", propertynames(Y_core.c))
    core_pairs =
        Tuple(pair for pair in block_pairs if !(string(pair.first[1]) in uncoupled_strings))
    core_matrix = timed("FieldMatrix, core", MatrixFields.FieldMatrix, core_pairs...)
    with_solver = timed(
        "FieldMatrixWithSolver, core",
        MatrixFields.FieldMatrixWithSolver,
        core_matrix,
        Y_core,
        alg,
    )
    @printf("[pieces] done   (since start %7.1f s)\n", time() - T_START)
    exit()
end
if split
    uncoupled = timed("uncoupled_jacobian_names", CA.uncoupled_jacobian_names, block_pairs)
    println("[pieces] uncoupled fields: ", uncoupled)
    alg = timed(
        "split_uncoupled_solver",
        CA.split_uncoupled_solver,
        alg,
        uncoupled,
        get(pa, "approximate_linear_solve_iters", 1),
    )
end
with_solver = timed(
    split ? "FieldMatrixWithSolver, split" : "FieldMatrixWithSolver",
    MatrixFields.FieldMatrixWithSolver,
    matrix,
    Y,
    alg,
)
@printf("[pieces] done   (since start %7.1f s)\n", time() - T_START)
