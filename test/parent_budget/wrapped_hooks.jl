import ClimaTimeSteppers as CTS

# A copy of `integrator` whose tendency function has some hooks wrapped, so a
# test can read each stage the stepper evaluates.
#
# `wrappers` maps a field of the `ClimaODEFunction` to a function that takes
# the hook and returns its replacement. The copy shares the state, the cache,
# the callbacks and the saved solution with the original, which must not be
# stepped again. The stepper reads the tendency function from the solution's
# problem, so only that changes. A wrapper that writes nothing the model reads
# leaves the trajectory as it is.
function with_wrapped_hooks(integrator; wrappers...)
    f = integrator.sol.prob.f
    hooks = Dict{Symbol, Any}(name => getfield(f, name) for name in fieldnames(typeof(f)))
    for (name, wrap) in wrappers
        hooks[name] = wrap(hooks[name])
    end
    prob = integrator.sol.prob
    problem =
        CTS.ODEProblem(CTS.ClimaODEFunction(; hooks...), prob.u0, prob.tspan, prob.p)
    sol = CTS.ODESolution(integrator.sol.t, integrator.sol.u, problem, integrator.sol.alg)
    fields = (
        name === :sol ? sol : getfield(integrator, name) for
        name in fieldnames(typeof(integrator))
    )
    return typeof(integrator).name.wrapper(fields...)
end
