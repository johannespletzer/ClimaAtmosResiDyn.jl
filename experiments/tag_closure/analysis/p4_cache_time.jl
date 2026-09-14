#=
Time building the implicit Jacobian's cache on a fresh state, with and without
the split of P4's fix, each with its compile.

    julia +1.11 --project=<worktree with the fix>/.buildkite \
        experiments/tag_closure/analysis/p4_cache_time.jl <config.yml>

The split cache is built first, so its time holds only its own compile. If the
unsplit cache then still takes long, the split did not compile it.
=#

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

config = CA.AtmosConfig(ARGS[1]; job_id = "cache_time")
pa = config.parsed_args
params = CA.ClimaAtmosParameters(config)
setup = CA.get_setup_type(pa, CA.Parameters.thermodynamics_params(params))
atmos = CA.get_atmos(config, params; setup_type = setup)
spaces = CA.get_spaces(CA.get_grid(pa, params, config.comms_ctx))
Y = CA.Setups.initial_state(setup, params, atmos, spaces.center_space, spaces.face_space)
alg = CA.ManualSparseJacobian(;
    approximate_solve_iters = pa["approximate_linear_solve_iters"],
)
orders = Dict(
    "split_first" => (("split", (;)), ("unsplit", (; split_uncoupled_fields = false))),
    "unsplit_first" =>
        (("unsplit", (; split_uncoupled_fields = false)), ("split", (;))),
)
for (label, kwargs) in orders[length(ARGS) >= 2 ? ARGS[2] : "split_first"]
    start = time()
    cache = Base.invokelatest(CA.jacobian_cache, alg, Y, atmos; kwargs...)
    @printf(
        "[cache] %-8s %7.1f s  %s\n",
        label,
        time() - start,
        nameof(typeof(cache.solver))
    )
end
