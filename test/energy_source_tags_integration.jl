#=
Integration test for the energy source tags.

The unit tests in `energy_source_tags_tests.jl` call the state builders and the
name helpers directly, on scalars and plain arrays. Nothing there proves the
family is wired into a simulation at all, which is what this file covers:

 1. `AtmosConfig` carries `energy_source_tags` through to the `AtmosModel`, so
    the `ρe_src_*` fields exist in the prognostic state;
 2. the region masks reach `p.tagging.ᶜenergy_source_masks` and partition unity;
 3. at t = 0 the region tags partition `ρe_tot` to machine precision;
 4. the generic tracer machinery transports the tags, they stay finite, and the
    closure residual stays a small bounded monitor;
 5. state and masks survive a checkpoint round trip.

The attribution rule is not implemented yet on this branch, so a tag carrying a
`source` stays at exactly zero. That is asserted rather than worked around; the
rule's own assertions arrive with the rule.

A column with an altitude partition is the cheapest geometry that exercises all
of it — latitude regions and the Held-Suarez source would need a sphere. One
tag set only: each set is a fresh `AtmosModel` type and costs a full compile of
the solve pipeline, which is why these files have their own test group (see the
note in `runtests.jl`).
=#
using Test
import ClimaAtmos as CA

@testset "Energy source tags integration" begin
    tags = [
        Dict{String, Any}(
            "name" => "strat",
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 12000.0,
                "width" => 1000.0,
            ),
        ),
        Dict{String, Any}(
            "name" => "tropo",
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 12000.0,
                "width" => 1000.0,
                "above" => false,
            ),
        ),
        # A source tag, to pin the documented behaviour of this branch: with no
        # attribution rule it starts at zero and stays there.
        Dict{String, Any}("name" => "rad", "source" => "radiation"),
    ]
    test_dict = Dict(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "microphysics_model" => "0M",
        "dt" => "10secs",
        "t_end" => "20secs",
        "dt_save_state_to_disk" => "20secs",
        # Float64 is required, not cosmetic: the t = 0 partition is asserted at
        # machine precision.
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
        "energy_source_tags" => tags,
    )

    simulation = CA.get_simulation(
        CA.AtmosConfig(test_dict; job_id = "energy_source_tags_integration"),
    )
    Y₀ = simulation.integrator.u
    FT = eltype(Y₀)

    # 1. The config reached the state. Without this the rest is vacuous.
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        @test hasproperty(Y₀.c, name)
    end

    # 2. The masks reached the cache and partition unity. This is the only path
    # that runs `_energy_source_tagging_cache`.
    masks = simulation.integrator.p.tagging.ᶜenergy_source_masks
    @test hasproperty(masks, :ρe_src_strat)
    @test hasproperty(masks, :ρe_src_tropo)
    mask_sum =
        parent(masks.ρe_src_strat) .+ parent(masks.ρe_src_tropo)
    @test maximum(abs.(mask_sum .- 1)) < 100 * eps(FT)

    # The masks are built from the config rather than stored, so a source tag
    # with no region contributes none.
    @test !hasproperty(masks, :ρe_src_rad)

    closure_deviation(Y) =
        maximum(
            abs.(
                parent(Y.c.ρe_src_strat) .+ parent(Y.c.ρe_src_tropo) .-
                parent(Y.c.ρe_tot),
            ),
        ) / maximum(abs.(parent(Y.c.ρe_tot)))

    # 3. The region tags partition the initial energy to machine precision, and
    # the source tag starts at zero.
    @test closure_deviation(Y₀) < 100 * eps(FT)
    @test all(iszero, parent(Y₀.c.ρe_src_rad))

    CA.solve_atmos!(simulation)
    Y = simulation.integrator.u

    # 4. Transport keeps them finite, and closure stays a bounded monitor. The
    # tags ride the generic tracer path while `ρe_tot` transports enthalpy, so
    # the residual is watched rather than expected to vanish.
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        @test all(isfinite, parent(getproperty(Y.c, name)))
    end
    @test closure_deviation(Y) < 5e-3

    # With no attribution rule the source tag is still exactly zero. When the
    # rule lands this assertion is the one that has to change.
    @test all(iszero, parent(Y.c.ρe_src_rad))

    # 5. Checkpoint round trip: the state survives bit-for-bit and the masks,
    # which are rebuilt from the config rather than stored, are reproduced.
    restart_file = joinpath(simulation.output_dir, "day0.20.hdf5")
    @test isfile(restart_file)

    restarted = CA.get_simulation(
        CA.AtmosConfig(
            merge(test_dict, Dict("restart_file" => restart_file));
            job_id = "energy_source_tags_integration_restart",
        ),
    )
    Y_restart = restarted.integrator.u
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        @test parent(getproperty(Y_restart.c, name)) ==
              parent(getproperty(Y.c, name))
    end
    restarted_masks = restarted.integrator.p.tagging.ᶜenergy_source_masks
    for name in (:ρe_src_strat, :ρe_src_tropo)
        @test parent(getproperty(restarted_masks, name)) ==
              parent(getproperty(masks, name))
    end
end
