using Test
using ClimaAtmos
using Aqua

@testset "Aqua tests (performance-specific)" begin
    # This tests that we don't accidentally run into
    # https://github.com/JuliaLang/julia/issues/29393
    # Aqua.test_unbound_args(ClimaAtmos)
    ua = Aqua.detect_unbound_args_recursively(ClimaAtmos)
    @test length(ua) == 0

    # See: https://github.com/SciML/OrdinaryDiffEq.jl/issues/1750
    # Test that we're not introducing method ambiguities across deps
    ambs = Aqua.detect_ambiguities(ClimaAtmos; recursive = true)
    pkg_match(pkgname, pkdir::Nothing) = false
    pkg_match(pkgname, pkdir::AbstractString) = occursin(pkgname, pkdir)
    filter!(x -> pkg_match("ClimaAtmos", pkgdir(last(x).module)), ambs)

    # Uncomment for debugging:
    # for method_ambiguity in ambs
    #     @show method_ambiguity
    # end
    @test length(ambs) == 0
end

@testset "Aqua tests (all)" begin
    # julia-downgrade-compat (v2.7.0+) promotes the test-only [extras] into [deps] so
    # that Pkg.test cannot re-resolve away the minimized versions. ClimaAtmos
    # itself does not load those packages, so the stale-dependency check reports
    # all of them as stale in the downgrade job. Skip it there; the regular CI
    # jobs still run it against an unmodified Project.toml.
    in_downgrade_ci = get(ENV, "CLIMAATMOS_DOWNGRADE_CI", "false") == "true"
    # The persistent-task check walks the dependency tree and needs every name
    # in each `[deps]` section to be loadable. `LogExpFunctions` v1.0.1 lists
    # `ChangesOfVariables` in `[deps]` and in `[weakdeps]`, so the walk asks for
    # a package that a weak dependency alone does not install, and fails with
    # "Unable to locate `ChangesOfVariables`". `ChangesOfVariables` is therefore
    # a test-only dependency of this package, which puts it in the environment.
    # Remove it once `LogExpFunctions` stops listing it twice.
    Aqua.test_all(
        ClimaAtmos;
        persistent_tasks = true,
        stale_deps = !in_downgrade_ci,
    )
end

nothing
