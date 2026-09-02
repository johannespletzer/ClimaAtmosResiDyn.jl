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
 5. state and masks survive a checkpoint round trip;
 6. masked *production* reaches a source tag through a real bracketed process,
    which is the one thing here that a plain-array unit test cannot show.

**This file does not validate the attribution rule end to end.** `ρe_tot` is
non-positive across this column, so `energy_source_fraction` returns zero and
donor-proportional loss never runs here. Production is unaffected, because it
is mask-weighted and never divides by the parent, which is why item 6 is
evidence and a loss claim would not be.

The loss algebra is covered in `energy_source_tags_tests.jl` against a parent
that is positive by construction. That is a kernel test, so loss through a real
bracketed solve remains unvalidated. See `docs/src/energy_source_tags.md`.

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
                "z_center" => 750.0,
                "width" => 100.0,
            ),
        ),
        Dict{String, Any}(
            "name" => "tropo",
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 750.0,
                "width" => 100.0,
                "above" => false,
            ),
        ),
        # A source tag on the process that actually forces this column, so the
        # attribution rule has something to attribute.
        Dict{String, Any}("name" => "rad", "source" => "radiation"),
    ]
    test_dict = Dict(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        # DYCOMS_RF02 is a 1.5 km marine boundary layer, so it gets the geometry
        # the shipped DYCOMS configs use rather than the default 30 km column.
        "z_max" => 1500.0,
        "z_elem" => 30,
        # Uniform spacing, as the shipped DYCOMS configs use. `dz_bottom`
        # defaults to 500 m, which the tanh stretching cannot fit into a 1500 m
        # domain across 30 elements.
        "z_stretch" => false,
        # Radiation has to be switched on for the `rad` source tag to receive
        # anything. `initial_condition: DYCOMS_RF02` sets the state, not the
        # forcing, and `rad` defaults to `~`.
        "rad" => "DYCOMS",
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

    # A crashed solve returns `:simulation_crashed` rather than throwing, so an
    # unchecked result would let the assertions below run against a dead state.
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u

    # 4. Transport keeps them finite, and closure stays a bounded monitor. The
    # tags ride the generic tracer path while `ρe_tot` transports enthalpy, so
    # the residual is watched rather than expected to vanish. The bound is a
    # blow-up guard, not a precision claim: the machine-precision statement
    # this family does make is the t = 0 partition asserted above.
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        @test all(isfinite, parent(getproperty(Y.c, name)))
    end
    @test closure_deviation(Y) < 5e-2

    # Production reached the tag: it is mask-weighted and never divides by the
    # parent, so it works where the donor loss beside it is inert. A source tag
    # starts at zero, so anything nonzero came through the `radiation` bracket.
    # This needs `rad: DYCOMS` above, since the initial condition sets the
    # state and not the forcing.
    rad_scale = maximum(abs.(parent(Y.c.ρe_src_rad)))
    @test rad_scale > 0

    # No sign is asserted, because none is promised: donor-proportional loss
    # bounds the depletion rate rather than the amount removed over a step, and
    # the tags ride unlimited transport with no partition repair. See the
    # contract on `EnergySourceTag`. This is only a blow-up guard.
    parent_scale = maximum(abs.(parent(Y.c.ρe_tot)))
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        tag_scale = maximum(abs.(parent(getproperty(Y.c, name))))
        @test tag_scale < 10 * parent_scale
    end

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
