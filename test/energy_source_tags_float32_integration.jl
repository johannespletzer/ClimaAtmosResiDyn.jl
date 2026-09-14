#=
Float32 integration test for the energy source tags and the process records.

Production runs both families in Float32 on a GPU. The kernel-level unit
tests already loop over `(Float32, Float64)` (`energy_source_tags_tests.jl`,
`process_record_tests.jl`), so the arithmetic itself is covered in Float32.
What is missing is a real solve: `energy_source_tags_integration.jl` and
`process_record_integration.jl` both force `FLOAT_TYPE => "Float64"`, so
nothing runs the state builders, the transport, the repair, the closure
check or the accumulator through an actual timestepper in Float32. A one-day
CPU sphere run has been checked by hand against its Float64 twin, but no
automated test exercises this.

Both families are configured in the same run rather than in two files, for
two reasons. First, a tag name is a type parameter, so `energy_source_tags`
and `energy_process_record` together are one `AtmosModel` type and one
compile of the whole solve pipeline; splitting them would pay for that
compile twice. Second, `docs/src/energy_source_tags.md` promises the two
families are independent, and configuring them together is the combination
most likely to reveal that they are not.

The offset and 1-moment microphysics are folded into this same run rather
than run separately, again to keep the compile count at one:

 1. `AtmosConfig` carries `energy_source_tags` and `energy_process_record`
    through to the `AtmosModel` in Float32, so the `ρe_src_<name>` and
    `prc_e_<process>` fields exist and start at the right value;
 2. the records are not swept up by the generic tracer transport;
 3. with `energy_source_tag_offset` from the start, the region tags partition
    `E = ρe_tot + c·ρ` at t = 0, bounded in `eps(Float32)` terms relative to
    the scale of `E`. `ρe_tot` alone is non-positive across this column (see
    `energy_source_tags_integration.jl`), so the offset is not optional here;
    without it the donor loss never runs and the partition check above would
    be checking a partition of a field the run never touches;
 4. a short solve succeeds with the tags, the offset, the repair (on by
    default), 1-moment sedimentation, the closure check and the records all
    active together, and every field involved stays finite;
 5. production reaches a source tag, and the records accumulate a nonzero
    value, both in Float32;
 6. sedimentation's flux partition adds up to the parent's, in Float32, the
    same check `energy_source_tags_integration.jl` makes in Float64 at
    `100 eps`;
 7. state and masks survive a checkpoint round trip in Float32.

What this file does not repeat: the with-versus-without-offset comparison of
the loss half's effect on the column residual (`energy_source_tags_integration.jl`,
"The loss half runs with an offset") needs a second simulation without the
offset to compare against, which is a second compile. The donor-share and
sediment-share arithmetic themselves are already looped over `(Float32,
Float64)` in `energy_source_tags_tests.jl`; this file only has to show that
arithmetic is reached by a real Float32 solve, not re-derive it.
=#
using Test
import ClimaAtmos as CA

@testset "Energy source tags and process records ($Float32)" begin
    c = 50000.0
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
        # A source tag on the process that forces this column, so production
        # has something to attribute.
        Dict{String, Any}("name" => "rad", "source" => "radiation"),
    ]
    test_dict = Dict(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        # DYCOMS_RF02 is a 1.5 km marine boundary layer, so it gets the
        # geometry the shipped DYCOMS configs use rather than the default
        # 30 km column.
        "z_max" => 1500.0,
        "z_elem" => 30,
        # Uniform spacing, as the shipped DYCOMS configs use. `dz_bottom`
        # defaults to 500 m, which the tanh stretching cannot fit into a
        # 1500 m domain across 30 elements.
        "z_stretch" => false,
        # Radiation has to be on for the `rad` source tag and the
        # `prc_e_radiation` record to receive anything.
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        # Cloud liquid falls at a fixed speed by default. The diagnostic
        # speed is nonzero wherever there is cloud, which is what gives
        # sedimentation something to move.
        "fixed_terminal_velocity_liquid" => false,
        "dt" => "10secs",
        # Long enough for cloud to form and fall under 1M, as the
        # sedimentation item of `energy_source_tags_integration.jl` uses.
        "t_end" => "60secs",
        "dt_save_state_to_disk" => "60secs",
        # The point of this file: run the tags and the records through a
        # real solve in Float32 rather than Float64.
        "FLOAT_TYPE" => "Float32",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
        "energy_source_tags" => tags,
        "energy_source_tag_offset" => c,
        "energy_process_record" => ["radiation", "surface_flux"],
        # Exercises the closure check's own reductions and CSV write in
        # Float32. The default tolerance (1e-6) is far below the residual
        # this family is known to carry (bound 5e-2 in the Float64
        # integration test), so this checks the check runs and stays
        # finite, not that it passes its own tolerance.
        "energy_source_closure_check" => Dict{String, Any}("period" => "20secs"),
    )

    simulation = CA.get_simulation(
        CA.AtmosConfig(
            test_dict;
            job_id = "energy_source_tags_float32_integration",
        ),
    )
    Y₀ = simulation.integrator.u
    FT = eltype(Y₀)
    @test FT == Float32

    # 1. Both families reached the state, at the values each promises at
    # t = 0: a region tag its masked share, a source tag and every record
    # zero.
    for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
        @test hasproperty(Y₀.c, name)
    end
    @test all(iszero, parent(Y₀.c.ρe_src_rad))
    for name in (:prc_e_radiation, :prc_e_surface_flux)
        @test hasproperty(Y₀.c, name)
        @test all(iszero, parent(getproperty(Y₀.c, name)))
    end

    # 2. Records are prognostic but not tracers. `gs_tracer_names` discovers
    # tracers by a lexical `ρ` prefix, so the missing prefix on `prc_e_*` is
    # what keeps them out of advection, diffusion, hyperdiffusion and the
    # sponges. Checked here rather than assumed, because it is the same
    # naming-convention hazard `process_record_integration.jl` guards.
    transported = map(string, CA.gs_tracer_names(Y₀))
    @test !any(name -> occursin("prc_", name), transported)

    # The masks reached the cache and partition unity, at Float32 precision.
    masks = simulation.integrator.p.tagging.ᶜenergy_source_masks
    mask_sum = parent(masks.ρe_src_strat) .+ parent(masks.ρe_src_tropo)
    @test maximum(abs.(mask_sum .- 1)) < 100 * eps(FT)

    # 3. The region tags partition `E = ρe_tot + c·ρ` at t = 0, bounded in
    # `eps(Float32)` terms relative to the scale of `E`. This is the Float32
    # analogue of the machine-precision check
    # `energy_source_tags_integration.jl` makes on `ρe_tot` alone; here it is
    # made on the offset total because that is the one that is positive
    # everywhere in this column.
    ᶜE₀ = @. Y₀.c.ρe_tot + FT(c) * Y₀.c.ρ
    @test minimum(parent(ᶜE₀)) > 0
    ᶜpartition₀ = @. Y₀.c.ρe_src_strat + Y₀.c.ρe_src_tropo
    @test maximum(abs.(parent(ᶜpartition₀) .- parent(ᶜE₀))) /
          maximum(abs.(parent(ᶜE₀))) < 100 * eps(FT)

    # A crashed solve returns `:simulation_crashed` rather than throwing, so
    # an unchecked result would let the assertions below run against a dead
    # state.
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u
    p = simulation.integrator.p
    t = simulation.integrator.t

    # 4. Transport, the repair, sedimentation and the accumulator all leave
    # finite state in Float32.
    for name in (
        :ρe_src_strat,
        :ρe_src_tropo,
        :ρe_src_rad,
        :prc_e_radiation,
        :prc_e_surface_flux,
    )
        @test all(isfinite, parent(getproperty(Y.c, name)))
    end

    # 5. Production reached the source tag: a source tag starts at zero, so
    # anything nonzero came through the `radiation` bracket.
    @test maximum(abs.(parent(Y.c.ρe_src_rad))) > 0

    # The record accumulated a nonzero value in Float32. DYCOMS radiation
    # cools this column every step, so this is not a marginal signal, and it
    # is the Float32 analogue of the check `process_record_integration.jl`
    # makes on the same field in Float64.
    @test maximum(abs.(parent(Y.c.prc_e_radiation))) > 0

    # The repair's ledger is a diagnostic. Computing it once in Float32 shows
    # the function behind `e_src_fix_<name>` runs and stays finite; a source
    # tag is only ever clipped upward, so its ledger cannot be negative.
    ledger = CA.Diagnostics.compute_e_src_fix!(nothing, Y, p, t, :ρe_src_rad)
    @test all(isfinite, parent(ledger))
    @test minimum(parent(ledger)) >= 0

    # 6. Sedimentation, into a zeroed tendency. The tags partition
    # `E = ρe_tot + c·ρ`, so theirs must add up to the tendency of that, at
    # the same `100 eps` bound `energy_source_tags_integration.jl` asserts in
    # Float64.
    Yₜ = zero(Y)
    CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
    ᶜE_tendency = @. Yₜ.c.ρe_tot + FT(c) * Yₜ.c.ρ
    scale = maximum(abs, parent(ᶜE_tendency))
    # Something fell, or the rest is vacuous.
    @test scale > 0
    ᶜpartition_tendency = @. Yₜ.c.ρe_src_strat + Yₜ.c.ρe_src_tropo
    @test maximum(
        abs,
        parent(ᶜpartition_tendency) .- parent(ᶜE_tendency),
    ) < 100 * eps(FT) * scale
    @test all(isfinite, parent(Yₜ.c.ρe_src_rad))

    # The closure check ran, wrote its CSV and stayed finite. Its own
    # tolerance is not asserted; see the comment on `energy_source_closure_check`
    # above.
    closure_path = joinpath(simulation.output_dir, "energy_source_tag_closure.csv")
    @test isfile(closure_path)
    closure_rows = readlines(closure_path)
    # A header plus at least one row at t = 20 s.
    @test length(closure_rows) > 1
    gross_relative = parse(Float64, split(closure_rows[end], ",")[7])
    @test isfinite(gross_relative)

    # 7. Checkpoint round trip: both families survive bit for bit, and the
    # masks, rebuilt from the config rather than stored, are reproduced.
    restart_file = joinpath(simulation.output_dir, "day0.60.hdf5")
    @test isfile(restart_file)

    restarted = CA.get_simulation(
        CA.AtmosConfig(
            merge(test_dict, Dict("restart_file" => restart_file));
            job_id = "energy_source_tags_float32_integration_restart",
        ),
    )
    Y_restart = restarted.integrator.u
    for name in (
        :ρe_src_strat,
        :ρe_src_tropo,
        :ρe_src_rad,
        :prc_e_radiation,
        :prc_e_surface_flux,
    )
        @test parent(getproperty(Y_restart.c, name)) ==
              parent(getproperty(Y.c, name))
    end
    # The restored records are genuinely carried over, not zeroed and
    # refilled.
    @test !all(iszero, parent(Y_restart.c.prc_e_radiation))
    restarted_masks = restarted.integrator.p.tagging.ᶜenergy_source_masks
    for name in (:ρe_src_strat, :ρe_src_tropo)
        @test parent(getproperty(restarted_masks, name)) ==
              parent(getproperty(masks, name))
    end
end
