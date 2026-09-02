#=
Integration test for the process records.

The unit tests in `process_record_tests.jl` drive the accumulator over a mock
`Yₜ` on plain arrays. That proves the arithmetic, including that the record
integrates a rate rather than counting tendency evaluations, but it steps the
state by hand and so says nothing about whether the family is wired into a
simulation. This file covers the paths it cannot reach:

 1. `AtmosConfig` carries `energy_process_record` through to the `AtmosModel`,
    so the `prc_e_<process>` fields exist in the prognostic state and start at
    zero;
 2. the records are prognostic but **not** tracers — nothing in the automatic
    transport machinery picks them up;
 3. the real timestepper integrates them, so a bracketed process that fires
    leaves a nonzero record;
 4. they survive a checkpoint round trip with their values intact, which is the
    contract that makes a window budget the difference of two outputs even
    across a restart.

Records are configured here with no tags at all, which is the combination the
documentation promises works and the one a tag-shaped guard is most likely to
miss.

The geometry is the shallow DYCOMS column the energy source tag test uses, for
the same reason: `radiation` only fires when a radiation scheme is configured,
and `rad: DYCOMS` belongs with the boundary layer it was written for. One
record set only, since each set is a fresh `AtmosModel` type and costs a full
compile of the solve pipeline (see the note in `runtests.jl`).
=#
using Test
import ClimaAtmos as CA

@testset "Process record integration" begin
    test_dict = Dict(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        # Uniform spacing, as the shipped DYCOMS configs use. `dz_bottom`
        # defaults to 500 m, which the tanh stretching cannot fit into a 1500 m
        # domain across 30 elements.
        "z_stretch" => false,
        # Without this the `radiation` bracket never runs and its record stays
        # at exactly zero, which is indistinguishable from a process that did
        # nothing. That is the failure mode `warn_inactive_record_labels`
        # exists to announce.
        "rad" => "DYCOMS",
        "microphysics_model" => "0M",
        "dt" => "10secs",
        "t_end" => "20secs",
        "dt_save_state_to_disk" => "20secs",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
        # No tags of any kind: a record is independent of them.
        "energy_process_record" => ["radiation", "surface_flux"],
    )

    simulation = CA.get_simulation(
        CA.AtmosConfig(test_dict; job_id = "process_record_integration"),
    )
    Y₀ = simulation.integrator.u

    # 1. The config reached the state, and a record starts at zero because it
    # is a history rather than a share of anything present.
    for name in (:prc_e_radiation, :prc_e_surface_flux)
        @test hasproperty(Y₀.c, name)
        @test all(iszero, parent(getproperty(Y₀.c, name)))
    end

    # No tags were configured, so nothing from the other families appeared.
    @test !hasproperty(Y₀.c, :ρe_tag_radiation)

    # 2. Not transported. `gs_tracer_names` discovers tracers by a purely
    # lexical `ρ` prefix, so the missing prefix on `prc_e_*` is the whole of
    # what keeps advection, diffusion, hyperdiffusion and the sponges off
    # these fields. That looks like a naming slip to anyone who knows the
    # convention, so it is asserted rather than left to a comment.
    transported = map(string, CA.gs_tracer_names(Y₀))
    @test !any(name -> occursin("prc_", name), transported)

    # A crashed solve returns `:simulation_crashed` rather than throwing, so an
    # unchecked result would let the assertions below run against a dead state.
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u

    for name in (:prc_e_radiation, :prc_e_surface_flux)
        @test all(isfinite, parent(getproperty(Y.c, name)))
    end

    # 3. The timestepper integrated the record. The accumulator adds a rate to
    # `Yₜ`, so a nonzero value here means the tendency was carried through the
    # solve rather than summed by hand. DYCOMS radiation cools this column
    # every step, so this is not a marginal signal.
    @test maximum(abs.(parent(Y.c.prc_e_radiation))) > 0

    # 4. Checkpoint round trip. Records live in `Y`, so they are written to the
    # checkpoint and restored with their values rather than restarting at
    # zero. This is what makes a budget over a window the difference of two
    # outputs even when a restart falls between them, and it is the one place
    # the records differ from `q_tag_fix_<name>`, which stays in the cache.
    restart_file = joinpath(simulation.output_dir, "day0.20.hdf5")
    @test isfile(restart_file)

    restarted = CA.get_simulation(
        CA.AtmosConfig(
            merge(test_dict, Dict("restart_file" => restart_file));
            job_id = "process_record_integration_restart",
        ),
    )
    Y_restart = restarted.integrator.u
    for name in (:prc_e_radiation, :prc_e_surface_flux)
        @test parent(getproperty(Y_restart.c, name)) ==
              parent(getproperty(Y.c, name))
    end
    # The restored record is genuinely carried over, not zeroed and refilled.
    @test !all(iszero, parent(Y_restart.c.prc_e_radiation))
end
