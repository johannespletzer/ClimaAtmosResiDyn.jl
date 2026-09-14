#=
Profile type inference inside `FieldMatrixWithSolver`, the piece of the Jacobian
build that grows with the tags (P4).

    julia +1.11 --project=<worktree>/.buildkite \
        experiments/tag_closure/analysis/p4_solver_profile.jl <config.yml> [split]

`p4_jacobian_pieces.jl` found that building the solver takes 14 s on the 0M
column without tags and 89 s with 8, and that solving the tags apart from the
rest does not change that. This builds the state, the blocks, the matrix and
the solver algorithm untimed, and then builds `FieldMatrixWithSolver` under
`Core.Compiler.Timings`. It prints the inference tree down to the calls that
take more than a second in total, so the growing call can be named, and the 25
methods with the most exclusive time.
=#

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaCore.MatrixFields as MatrixFields

const Timings = Core.Compiler.Timings

config_path = ARGS[1]
split = length(ARGS) >= 2 && ARGS[2] == "split"
split && include(joinpath(@__DIR__, "p4_split_solver.jl"))
name = splitext(basename(config_path))[1]
config = CA.AtmosConfig(config_path; job_id = "solver_profile_$name")
pa = config.parsed_args
params = CA.ClimaAtmosParameters(config)
setup = CA.get_setup_type(pa, CA.Parameters.thermodynamics_params(params))
atmos = CA.get_atmos(config, params; setup_type = setup)
spaces = CA.get_spaces(CA.get_grid(pa, params, config.comms_ctx))
Y = CA.Setups.initial_state(setup, params, atmos, spaces.center_space, spaces.face_space)
FT = eltype(Y)
(; topography_flag, diffusion_flag) = CA._derivative_flags(atmos, Y)
process_block_pairs = CA.merge_jacobian_blocks((
    CA.sgs_advection_jacobian_blocks(Y, atmos)...,
    CA.advection_jacobian_blocks(Y, atmos, topography_flag)...,
    CA.diffusion_jacobian_blocks(Y, atmos, diffusion_flag)...,
    CA.sedimentation_jacobian_blocks(Y, atmos)...,
    CA.sgs_massflux_jacobian_blocks(Y, atmos)...,
))
block_pairs =
    (process_block_pairs..., CA.fallback_identity_blocks(process_block_pairs, Y, FT)...)
matrix = MatrixFields.FieldMatrix(block_pairs...)
iters = get(pa, "approximate_linear_solve_iters", 1)
alg = CA.jacobian_solver_algorithm(Y, atmos, diffusion_flag, iters)
split &&
    (alg = CA.split_uncoupled_solver(alg, CA.uncoupled_jacobian_names(block_pairs), iters))
println("blocks: ", length(block_pairs), ", fields: ", propertynames(Y.c))

Timings.reset_timings()
Core.Compiler.__set_measure_typeinf(true)
start = time()
try
    Base.invokelatest(MatrixFields.FieldMatrixWithSolver, matrix, Y, alg)
finally
    Core.Compiler.__set_measure_typeinf(false)
    Timings.close_current_timer()
end
wall = time() - start
root = Timings._timings[1]

function inclusive(node)
    total, stack = 0.0, [node]
    while !isempty(stack)
        n = pop!(stack)
        total += n.time / 1e9
        append!(stack, n.children)
    end
    return total
end
label(node) =
    (mi = node.mi_info.mi; m = mi.def;
        m isa Method ?
        string(m.module, ".", m.name, " ", basename(string(m.file)), ":", m.line) :
        string(m))

@printf("FieldMatrixWithSolver: wall %.1f s, outside inference %.1f s, inference %.1f s\n",
    wall, root.time / 1e9, inclusive(root) - root.time / 1e9)

println("\nthe inference tree, calls over 1 s inclusive, to depth 8:")
function show_tree(node, depth)
    for child in sort(node.children; by = inclusive, rev = true)
        t = inclusive(child)
        t < 1.0 && break
        @printf("%s%.1f s  %s\n", "  "^depth, t, first(label(child), 150))
        depth < 8 && show_tree(child, depth + 1)
    end
end
show_tree(root, 1)

exclusive = Dict{String, Float64}()
counts = Dict{String, Int}()
stack = copy(root.children)
while !isempty(stack)
    node = pop!(stack)
    key = label(node)
    exclusive[key] = get(exclusive, key, 0.0) + node.time / 1e9
    counts[key] = get(counts, key, 0) + 1
    append!(stack, node.children)
end
println("\nthe 25 methods with the most exclusive inference time:")
for key in
    sort(collect(keys(exclusive)); by = k -> exclusive[k], rev = true)[1:min(25, end)]
    @printf("  %6.2f s  %6d  %s\n", exclusive[key], counts[key], first(key, 150))
end
