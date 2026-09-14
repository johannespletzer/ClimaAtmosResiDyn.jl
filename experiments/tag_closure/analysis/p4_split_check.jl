#=
Check P4's fix: that the split Jacobian solver gives the same increments as the
unsplit one, to the bit, and see what building each costs.

    julia +1.11 --project=<worktree with the fix>/.buildkite \
        experiments/tag_closure/analysis/p4_split_check.jl <config.yml> [n_steps]

It builds the simulation, which uses the split solver when the state has tags or
records, and steps it `n_steps` times (default 30), so that the tags hold
something. Then, from that state, it builds two Jacobian caches, the split one
and the unsplit one (`split_uncoupled_fields = false`), fills both with
`update_jacobian!`, solves one right-hand side with each, and compares every
value of the two increments. The right-hand side is the state times a
reproducible random factor per value, so that every field is nonzero.

It prints the time each cache takes to build, compile included, and exits
non-zero unless the increments are identical.
=#

using Printf
using Random
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

config_path = ARGS[1]
n_steps = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 30
name = splitext(basename(config_path))[1]

config = CA.AtmosConfig(config_path; job_id = "split_check_$name")
start = time()
simulation = CA.get_simulation(config)
@printf("[check] get_simulation %.1f s\n", time() - start)
integrator = simulation.integrator
start = time()
for _ in 1:n_steps
    CTS.step!(integrator)
end
@printf("[check] %d steps %.1f s, t = %s\n", n_steps, time() - start, integrator.t)

Y = integrator.u
p = integrator.p
atmos = p.atmos
alg = CA.ManualSparseJacobian(;
    approximate_solve_iters = config.parsed_args["approximate_linear_solve_iters"],
)

timed_cache(label; kwargs...) = begin
    start = time()
    cache = Base.invokelatest(CA.jacobian_cache, alg, Y, atmos; kwargs...)
    @printf("[check] %-32s %.1f s\n", label, time() - start)
    cache
end
split_cache = timed_cache("jacobian_cache, split")
unsplit_cache = timed_cache("jacobian_cache, unsplit"; split_uncoupled_fields = false)
println("[check] split solver: ", nameof(typeof(split_cache.solver)))
if split_cache.solver isa CA.SplitJacobianSolver
    println("[check] uncoupled fields: ", map(u -> u.name, split_cache.solver.uncoupled))
end

dtγ = eltype(Y)(0.5 * 10)
for cache in (split_cache, unsplit_cache)
    CA.update_jacobian!(alg, cache, Y, p, dtγ, integrator.t)
end

R = copy(Y)
rng = MersenneTwister(1)
for array in (parent(R.c), parent(R.f))
    array .*= 1 .+ 0.1 .* rand(rng, eltype(array), size(array))
end
ΔY_split = zero(Y)
ΔY_unsplit = zero(Y)
CA.invert_jacobian!(alg, split_cache, ΔY_split, R)
CA.invert_jacobian!(alg, unsplit_cache, ΔY_unsplit, R)

identical = true
for name in propertynames(Y.c)
    a = parent(getproperty(ΔY_split.c, name))
    b = parent(getproperty(ΔY_unsplit.c, name))
    same = isequal(a, b)
    global identical &= same
    @printf("[check] c.%-20s %s, largest difference %.3g, largest value %.3g\n", name,
        same ? "identical" : "DIFFERENT", maximum(abs, a .- b), maximum(abs, b))
end
for name in propertynames(Y.f)
    a = parent(getproperty(ΔY_split.f, name))
    b = parent(getproperty(ΔY_unsplit.f, name))
    same = isequal(a, b)
    global identical &= same
    @printf("[check] f.%-20s %s\n", name, same ? "identical" : "DIFFERENT")
end
println(identical ? "[check] all increments identical" : "[check] increments DIFFER")
exit(identical ? 0 : 1)
