#=
Integration test for tagged prognostic energy tracers.

Runs one hour of a coarse dry baroclinic wave with Held-Suarez forcing and
region tags that form a partition of unity (a latitude band and its exact
complement), plus a Held-Suarez source tag, and asserts:

 1. at t = 0, the region tags partition ρe_tot to machine precision;
 2. after solving, all tags stay finite;
 3. the closure residual ρe_tot - Σ region tags stays small (the tags are
    transported by the generic tracer machinery while ρe_tot transports
    enthalpy, so the residual is a bounded monitor, not exactly zero);
 4. the Held-Suarez source tag accumulates a nonzero contribution.

This mirrors the manual validation performed on
`config/model_configs/baroclinic_wave_tagged_tracers.yml` (10 simulated
days: exact partition at t = 0, sub-percent residual growth).

Run either through the package test path (`Pkg.test()`, TEST_GROUP
"dynamics") or standalone with the pinned CI environment:

    julia +1.11 --project=.buildkite -e 'using Pkg; Pkg.instantiate()'
    julia +1.11 --project=.buildkite test/tagged_tracers_integration.jl

Do NOT run with an ad-hoc `--project=test` environment: this repo has no
`test/Project.toml`, so that resolves fresh (possibly incompatible)
dependency versions instead of the pinned set.
=#

using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

@testset "Tagged tracers integration" begin
    config = CA.AtmosConfig(
        Dict(
            "initial_condition" => "DryBaroclinicWave",
            "rad" => "held_suarez",
            "h_elem" => 4,
            "z_elem" => 10,
            "dt" => "300secs",
            "t_end" => "3600secs",
            # Float64: the closure assertions below are precision-sensitive
            # (the default FLOAT_TYPE is Float32)
            "FLOAT_TYPE" => "Float64",
            "output_default_diagnostics" => false,
            "tagged_tracers" => [
                Dict{String, Any}(
                    "name" => "tropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                    ),
                ),
                Dict{String, Any}(
                    "name" => "extratropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                        "inside" => false,
                    ),
                ),
                Dict{String, Any}("name" => "hs", "source" => "held_suarez"),
                Dict{String, Any}(
                    "name" => "hs_tropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                    ),
                    "source" => "held_suarez",
                ),
                Dict{String, Any}(
                    "name" => "hs_extratropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                        "inside" => false,
                    ),
                    "source" => "held_suarez",
                ),
            ],
        );
        job_id = "tagged_tracers_integration",
    )
    simulation = CA.get_simulation(config)
    Y₀ = simulation.integrator.u

    closure_deviation(Y) =
        maximum(
            abs.(
                parent(Y.c.ρe_tag_tropics) .+
                parent(Y.c.ρe_tag_extratropics) .- parent(Y.c.ρe_tot)
            ),
        ) / maximum(abs.(parent(Y.c.ρe_tot)))

    # 1. Region tags partition the initial energy to machine precision
    FT = eltype(Y₀)
    @test closure_deviation(Y₀) < 100 * eps(FT)
    # All source tags start at zero, including the region-restricted ones
    @test all(iszero, parent(Y₀.c.ρe_tag_hs))
    @test all(iszero, parent(Y₀.c.ρe_tag_hs_tropics))
    @test all(iszero, parent(Y₀.c.ρe_tag_hs_extratropics))

    CA.solve_atmos!(simulation)
    Y = simulation.integrator.u

    # 2. Tags stay finite
    for tag_field in
        (Y.c.ρe_tag_tropics, Y.c.ρe_tag_extratropics, Y.c.ρe_tag_hs)
        @test all(isfinite, parent(tag_field))
    end

    # 3. Closure of the partition pair stays a small monitored residual (the
    # manual 10-day validation showed sub-percent drift; one hour of a coarse
    # run should stay well below that)
    @test closure_deviation(Y) < 5e-3

    # 4. The Held-Suarez source tag accumulated a nonzero contribution
    hs_scale = maximum(abs.(parent(Y.c.ρe_tag_hs)))
    @test hs_scale > 0

    # 5. Process closure: the region-restricted source tags must sum to the
    # global source tag to near machine precision, because their masks sum
    # to 1 and transport is linear in the tracer
    @test maximum(
        abs.(
            parent(Y.c.ρe_tag_hs_tropics) .+
            parent(Y.c.ρe_tag_hs_extratropics) .- parent(Y.c.ρe_tag_hs)
        ),
    ) / hs_scale < 1e-6
end
