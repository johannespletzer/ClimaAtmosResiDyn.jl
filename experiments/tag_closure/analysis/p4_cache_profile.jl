#=
Profile type inference inside `jacobian_cache` with P4's split, on a fresh state.

    julia +1.11 --project=<worktree with the fix>/.buildkite \
        experiments/tag_closure/analysis/p4_cache_profile.jl <config.yml>

Prints the inference tree down to the calls over a second in total.
=#

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

const Timings = Core.Compiler.Timings

config = CA.AtmosConfig(ARGS[1]; job_id = "cache_profile")
pa = config.parsed_args
params = CA.ClimaAtmosParameters(config)
setup = CA.get_setup_type(pa, CA.Parameters.thermodynamics_params(params))
atmos = CA.get_atmos(config, params; setup_type = setup)
spaces = CA.get_spaces(CA.get_grid(pa, params, config.comms_ctx))
Y = CA.Setups.initial_state(setup, params, atmos, spaces.center_space, spaces.face_space)
alg = CA.ManualSparseJacobian(;
    approximate_solve_iters = pa["approximate_linear_solve_iters"],
)

Timings.reset_timings()
Core.Compiler.__set_measure_typeinf(true)
start = time()
try
    Base.invokelatest(CA.jacobian_cache, alg, Y, atmos)
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
@printf("jacobian_cache: wall %.1f s, outside inference %.1f s\n", wall, root.time / 1e9)
function show_tree(node, depth)
    for child in sort(node.children; by = inclusive, rev = true)
        t = inclusive(child)
        t < 1.0 && break
        @printf("%s%.1f s  %s\n", "  "^depth, t, first(label(child), 150))
        depth < 7 && show_tree(child, depth + 1)
    end
end
show_tree(root, 1)
