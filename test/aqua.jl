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
    # `Project.toml` holds Aqua below 0.8.17, which the persistent-task check
    # needs. 0.8.17 walks the dependency tree itself, with
    # `Base.locate_package` for every name in each package's `[deps]` section,
    # and it does not skip the names that also stand in `[weakdeps]`. Pkg does
    # not put a weak dependency in the manifest, so the walk asks for a package
    # that is not there and the check errors. 0.8.16 resolved the environment
    # through Pkg instead, which filters weak dependencies.
    #
    # Many packages list a dependency in both sections, an idiom from before
    # Julia 1.9. `LogExpFunctions` v1.0.1 lists three names that way and
    # `IntervalSets` v0.7.11 all three of its own, so naming the missing
    # packages one by one does not end: the first attempt here added
    # `ChangesOfVariables` and the walk then stopped at `RecipesBase`.
    #
    # Raise the bound once Aqua skips `[weakdeps]` in that walk.
    Aqua.test_all(
        ClimaAtmos;
        persistent_tasks = true,
        stale_deps = !in_downgrade_ci,
    )
end

nothing
