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
    which is the one thing here that a plain-array unit test cannot show;
 7. with `energy_source_tag_offset`, the donor-proportional *loss* runs through
    the same solve, and the offset leaves the model's own state untouched;
 8. under 1-moment microphysics, sedimentation moves the tags with the water.
    The partition's fluxes add up to the parent's, and each face takes the
    shares of the cell that loses the energy, in either direction;
 9. under `energy_source_tag_transport: enthalpy`, the tags' vertical advection
    adds up to the parent's, each face takes the upwind cell's shares, and the
    model's state is untouched;
 10. on a small sphere, the same audit adds up to the parent's in horizontal
     advection and in hyperdiffusion.

Items 1 to 6 run on `ρe_tot` itself. It is non-positive across this column, so
`energy_source_fraction` returns zero and the loss never runs there. Production
is unaffected, because it is mask-weighted and never divides by the parent,
which is why item 6 is evidence. Item 7 gives the tags a positive total, so the
loss runs, and checks it where it shows: in the column integral of the residual,
where transport cancels.

The loss algebra itself is covered exactly in `energy_source_tags_tests.jl`,
against a parent that is positive by construction. See
`docs/src/energy_source_tags.md`.

A column with an altitude partition is the cheapest geometry that exercises
items 1 to 9. Horizontal transport and hyperdiffusion need a sphere, so item 10
builds the smallest one. Each tag set is a fresh `AtmosModel` type and costs a
full compile of the solve pipeline, which is why these files have their own
test group (see the note in `runtests.jl`). The offset is part of that type, and
so are the microphysics and the transport. So item 7 costs a second compile,
item 8 a third, item 9 a fourth and item 10 a fifth.
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
        # domain across 30 elements. It fails with
        # "gamma root failed to converge" before the model is built.
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

    # No sign is asserted, because none is promised here. Donor-proportional
    # loss bounds the depletion rate rather than the amount removed over a step,
    # the tags ride unlimited transport, and the repair acts only where the
    # total is positive, which `ρe_tot` is nowhere in this column. See the
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

    # 7. The loss half through a real solve. The run above never reaches it,
    # because `ρe_tot` is negative across this column. With an offset of
    # 50 kJ/kg the tags partition `ρe_tot + c·ρ`, which is positive everywhere,
    # since the column's minimum is about -45.4 kJ/kg.
    @testset "The loss half runs with an offset" begin
        c = 50000.0
        offset_simulation = CA.get_simulation(
            CA.AtmosConfig(
                merge(
                    test_dict,
                    Dict{String, Any}(
                        "energy_source_tag_offset" => c,
                        "output_dir" => mktempdir(pwd()),
                    ),
                );
                job_id = "energy_source_tags_integration_offset",
            ),
        )
        Y₀_offset = offset_simulation.integrator.u
        ᶜE₀ = @. Y₀_offset.c.ρe_tot + c * Y₀_offset.c.ρ
        @test minimum(parent(ᶜE₀)) > 0
        ᶜpartition₀ = @. Y₀_offset.c.ρe_src_strat + Y₀_offset.c.ρe_src_tropo
        @test maximum(abs.(parent(ᶜpartition₀) .- parent(ᶜE₀))) /
              maximum(abs.(parent(ᶜE₀))) < 100 * eps(FT)

        result = CA.solve_atmos!(offset_simulation)
        @test result.ret_code == :success
        Y_offset = offset_simulation.integrator.u

        # The offset reaches the tags and nothing else, so the model's own
        # state is bit for bit the one from the run without it.
        @test parent(Y_offset.c.ρ) == parent(Y.c.ρ)
        @test parent(Y_offset.c.ρe_tot) == parent(Y.c.ρe_tot)
        @test parent(Y_offset.c.ρq_tot) == parent(Y.c.ρq_tot)
        @test parent(Y_offset.c.uₕ) == parent(Y.c.uₕ)
        @test parent(Y_offset.f.u₃) == parent(Y.f.u₃)

        # Transport moves energy around the column but not in or out of it, so
        # the column integral of the residual keeps only what the processes
        # left unmatched. Without the loss half, that is every loss the tags
        # never took, and the tags hold more than the parent. With it, they
        # follow the parent down. At this test's 20 s the integral is
        # -2,382 J/m² without the loss half and -120 J/m² with it, a factor of
        # 19.9, so the bound of 5 leaves a factor of four. Over 120 s the
        # factor is 19.2.
        #
        # Both are absolute integrals on purpose. Each counts unmatched
        # increments in J/m², and the size of the parent does not enter it.
        # Dividing each by its own ∫|parent| would divide the ratio by the
        # ratio of the two parents' sizes, 6.5 here, which has nothing to do
        # with the loss half.
        signed_residual(Y, c) =
            sum(Y.c.ρe_tot .+ c .* Y.c.ρ) -
            sum(Y.c.ρe_src_strat .+ Y.c.ρe_src_tropo)
        without_loss = signed_residual(Y, 0)
        with_loss = signed_residual(Y_offset, c)
        @test abs(with_loss) < abs(without_loss) / 5

        # The repair runs by default, and its ledger is a diagnostic. Computing
        # the ledger once shows that the function behind `e_src_fix_<name>`
        # exists; registering the name does not. A source tag is only ever
        # clipped upward, so its ledger cannot be negative.
        ledger = CA.Diagnostics.compute_e_src_fix!(
            nothing,
            Y_offset,
            offset_simulation.integrator.p,
            offset_simulation.integrator.t,
            :ρe_src_rad,
        )
        @test all(isfinite, parent(ledger))
        @test minimum(parent(ledger)) >= 0
    end

    # 8. Sedimentation moves the tags. Under 1-moment microphysics the cloud and
    # the rain fall, and each face's energy flux is shared out by the shares of
    # the cell that loses the energy. What makes that transport is that the
    # partition's fluxes add up to the parent's, so sedimentation adds nothing
    # to `e_src_res`.
    @testset "Sedimentation moves the tags with the water" begin
        c = 50000.0
        sedimentation_simulation = CA.get_simulation(
            CA.AtmosConfig(
                merge(
                    test_dict,
                    Dict{String, Any}(
                        "microphysics_model" => "1M",
                        # Cloud liquid falls at a fixed speed by default. The
                        # diagnostic speed is nonzero wherever there is cloud.
                        "fixed_terminal_velocity_liquid" => false,
                        "energy_source_tag_offset" => c,
                        "t_end" => "60secs",
                        "output_dir" => mktempdir(pwd()),
                    ),
                );
                job_id = "energy_source_tags_integration_sedimentation",
            ),
        )
        result = CA.solve_atmos!(sedimentation_simulation)
        @test result.ret_code == :success
        # `local`, because the enclosing test set already has a `Y`, and a
        # plain assignment in a nested test set would overwrite it.
        local Y = sedimentation_simulation.integrator.u
        local p = sedimentation_simulation.integrator.p
        local t = sedimentation_simulation.integrator.t

        # Sedimentation alone, into a zeroed tendency. The tags partition
        # `E = ρe_tot + c·ρ`, so theirs must add up to the tendency of that.
        Yₜ = zero(Y)
        CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
        ᶜE_tendency = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
        scale = maximum(abs, parent(ᶜE_tendency))
        # Something fell, or the rest is vacuous.
        @test scale > 0
        ᶜpartition_tendency = @. Yₜ.c.ρe_src_strat + Yₜ.c.ρe_src_tropo
        @test maximum(
            abs,
            parent(ᶜpartition_tendency) .- parent(ᶜE_tendency),
        ) < 100 * eps(FT) * scale
        @test all(isfinite, parent(Yₜ.c.ρe_src_rad))

        # The donor. DYCOMS is warm, so the water carries positive energy, and
        # the energy falls with it. Ice can carry negative energy against the
        # reference plus the offset, and then the energy flux points up while
        # the water falls. Both directions are checked on a step partition,
        # all of `E` above 750 m in `strat` and all below in `tropo`, moved by
        # a flux of one sign in a band around the step. With no water given,
        # the offset adds nothing, and the flux is exactly the one set here.
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        Y_step = copy(Y)
        ᶜE = @. Y_step.c.ρe_tot + c * Y_step.c.ρ
        @. Y_step.c.ρe_src_strat = ifelse(ᶜz > 750, ᶜE, FT(0))
        @. Y_step.c.ρe_src_tropo = ᶜE - Y_step.c.ρe_src_strat
        CA.energy_source_share_norm!(p, Y_step)
        ᶜJ = CA.Fields.local_geometry_field(Y.c).J
        ᶠJ = CA.Fields.local_geometry_field(Y.f).J
        ᶠρ = @. CA.ᶠinterp(Y_step.c.ρ * ᶜJ) / ᶠJ
        ᶜnone = zero.(Y_step.c.ρ)
        above = parent(ᶜz) .> 750
        for direction in (-1, 1)
            ᶜflux = @. ifelse((ᶜz > 500) & (ᶜz < 1000), direction * FT(1000), FT(0))
            Yₜ_step = zero(Y_step)
            CA.sediment_energy_source_tags!(
                Yₜ_step,
                Y_step,
                p,
                ᶜnone,
                ᶜnone,
                ᶜflux,
                ᶠρ,
            )
            ᶜparent_tendency = @. -CA.ᶜprecipdivᵥ(
                ᶠρ * CA.ᶠtop_bias(CA.Geometry.WVector(ᶜflux)),
            )
            strat = parent(Yₜ_step.c.ρe_src_strat)
            tropo = parent(Yₜ_step.c.ρe_src_tropo)
            @test maximum(abs, strat .+ tropo .- parent(ᶜparent_tendency)) <
                  100 * eps(FT) * maximum(abs, parent(ᶜparent_tendency))
            if direction < 0
                # The energy falls, and the cell above is the donor. So `tropo`
                # never reaches above the step, and `strat` reaches only the
                # first cell below it.
                @test all(iszero, tropo[above])
                @test count(!iszero, strat[.!above]) == 1
            else
                # The energy rises, and the cell below is the donor: the mirror
                # image.
                @test all(iszero, strat[.!above])
                @test count(!iszero, tropo[above]) == 1
            end
        end
    end

    # 9. Enthalpy-form transport, the audit, on the column. The tags take their
    # shares of the parent's own flux of `E`, so the partition's vertical
    # tendency is the parent's. The model is untouched, so its state is the one
    # the first run ended in. A new transport is a new model type, and a
    # compile.
    @testset "Enthalpy transport moves the tags with the parent" begin
        local c = 50000.0
        audit_simulation = CA.get_simulation(
            CA.AtmosConfig(
                merge(
                    test_dict,
                    Dict{String, Any}(
                        "energy_source_tag_offset" => c,
                        "energy_source_tag_transport" => "enthalpy",
                        "output_dir" => mktempdir(pwd()),
                    ),
                );
                job_id = "energy_source_tags_integration_enthalpy",
            ),
        )
        result = CA.solve_atmos!(audit_simulation)
        @test result.ret_code == :success
        Y_audit = audit_simulation.integrator.u
        p_audit = audit_simulation.integrator.p
        t_audit = audit_simulation.integrator.t

        # The tags never act on the model, so its state is the first run's.
        Y_base = simulation.integrator.u
        @test parent(Y_audit.c.ρ) == parent(Y_base.c.ρ)
        @test parent(Y_audit.c.ρe_tot) == parent(Y_base.c.ρe_tot)
        @test parent(Y_audit.c.ρq_tot) == parent(Y_base.c.ρq_tot)
        @test parent(Y_audit.f.u₃) == parent(Y_base.f.u₃)
        for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
            @test all(isfinite, parent(getproperty(Y_audit.c, name)))
        end

        # The explicit vertical advection alone, into a zeroed tendency. The
        # partition's tendency is the parent's vertical transport of `E` at the
        # same state, with the parent's reconstruction. The tags' own
        # tendencies carry the size of the face fluxes, which is what rounding
        # scales with.
        Yₜ_audit = zero(Y_audit)
        CA.explicit_vertical_advection_tendency!(
            Yₜ_audit,
            Y_audit,
            p_audit,
            t_audit,
        )
        (; ᶠu³, ᶜh_tot) = p_audit.precomputed
        ᶜH = @. ᶜh_tot + c
        vtt = CA.vertical_transport(
            Y_audit.c.ρ,
            ᶠu³,
            ᶜH,
            p_audit.dt,
            p_audit.atmos.numerics.energy_q_tot_upwinding,
        )
        ᶜexpected = zero.(Y_audit.c.ρ)
        @. ᶜexpected += vtt
        strat = parent(Yₜ_audit.c.ρe_src_strat)
        tropo = parent(Yₜ_audit.c.ρe_src_tropo)
        scale = max(maximum(abs, strat), maximum(abs, tropo))
        @test scale > 0
        @test maximum(abs, strat .+ tropo .- parent(ᶜexpected)) <
              100 * eps(FT) * scale

        # The donor, on a step partition: all of `E` above 750 m in `strat` and
        # all below in `tropo`, moved by a flow of one sign in a band around
        # the step. The face takes the shares of the upwind cell, so the other
        # tag's tendency is exactly zero wherever its energy cannot reach.
        ᶜz = CA.Fields.coordinate_field(Y_audit.c).z
        ᶠz = CA.Fields.coordinate_field(Y_audit.f).z
        Y_step = copy(Y_audit)
        ᶜE = @. Y_step.c.ρe_tot + c * Y_step.c.ρ
        @. Y_step.c.ρe_src_strat = ifelse(ᶜz > 750, ᶜE, FT(0))
        @. Y_step.c.ρe_src_tropo = ᶜE - Y_step.c.ρe_src_strat
        above = parent(ᶜz) .> 750
        for direction in (-1, 1)
            @. ᶠu³ = CA.Geometry.Contravariant3Vector(
                ifelse((ᶠz > 500) & (ᶠz < 1000), direction * FT(0.01), FT(0)),
            )
            Yₜ_step = zero(Y_step)
            CA.enthalpy_vertical_advection_of_energy_source_tags!(
                Yₜ_step,
                Y_step,
                p_audit,
            )
            strat = parent(Yₜ_step.c.ρe_src_strat)
            tropo = parent(Yₜ_step.c.ρe_src_tropo)
            if direction > 0
                # The flow rises, and the cell below is the donor. So `strat`
                # never reaches below the step, and `tropo` reaches only the
                # first cell above it.
                @test all(iszero, strat[.!above])
                @test count(!iszero, tropo[above]) == 1
            else
                # The flow sinks, and the cell above is the donor: the mirror
                # image.
                @test all(iszero, tropo[above])
                @test count(!iszero, strat[.!above]) == 1
            end
        end
    end

    # 10. The audit horizontally and in hyperdiffusion, which need a sphere.
    # The smallest sphere that has both, for two steps, with the offset of the
    # tag-closure experiments. That is a fifth compile.
    @testset "Enthalpy transport on a sphere" begin
        local c = 110495.0
        sphere_simulation = CA.get_simulation(
            CA.AtmosConfig(
                Dict{String, Any}(
                    "config" => "sphere",
                    "h_elem" => 2,
                    "z_elem" => 4,
                    "z_max" => 30000.0,
                    "z_stretch" => false,
                    "dt" => "400secs",
                    "t_end" => "800secs",
                    "initial_condition" => "MoistBaroclinicWave",
                    "microphysics_model" => "0M",
                    "FLOAT_TYPE" => "Float64",
                    "output_default_diagnostics" => false,
                    "output_dir" => mktempdir(pwd()),
                    "energy_source_tag_offset" => c,
                    "energy_source_tag_transport" => "enthalpy",
                    "energy_source_tags" => [
                        Dict{String, Any}(
                            "name" => "tropics",
                            "region" => "tropics",
                        ),
                        Dict{String, Any}(
                            "name" => "extratropics",
                            "region" => "extratropics",
                        ),
                    ],
                );
                job_id = "energy_source_tags_integration_sphere",
            ),
        )
        result = CA.solve_atmos!(sphere_simulation)
        @test result.ret_code == :success
        Y_sphere = sphere_simulation.integrator.u
        p_sphere = sphere_simulation.integrator.p
        t_sphere = sphere_simulation.integrator.t
        tags_sum(x) =
            parent(x.c.ρe_src_tropics) .+ parent(x.c.ρe_src_extratropics)
        tags_scale(x) = max(
            maximum(abs, parent(x.c.ρe_src_tropics)),
            maximum(abs, parent(x.c.ρe_src_extratropics)),
        )

        # Horizontal advection. `split_divₕ` is linear in the value it moves.
        Yₜ_sphere = zero(Y_sphere)
        CA.horizontal_tracer_advection_tendency!(
            Yₜ_sphere,
            Y_sphere,
            p_sphere,
            t_sphere,
        )
        (; ᶜu, ᶜh_tot) = p_sphere.precomputed
        ᶜexpected = @. -CA.split_divₕ(Y_sphere.c.ρ * ᶜu, ᶜh_tot + c)
        @test tags_scale(Yₜ_sphere) > 0
        @test maximum(abs, tags_sum(Yₜ_sphere) .- parent(ᶜexpected)) <
              100 * eps(FT) * tags_scale(Yₜ_sphere)

        # Hyperdiffusion. The parent's is the only hyperdiffusion of `E`,
        # because `ρ` is not hyperdiffused, and the tags take none as tracers.
        Yₜ_sphere = zero(Y_sphere)
        Yₜ_lim = zero(Y_sphere)
        CA.hyperdiffusion_tendency!(
            Yₜ_sphere,
            Yₜ_lim,
            Y_sphere,
            p_sphere,
            t_sphere,
        )
        @test all(iszero, tags_sum(Yₜ_lim))
        @test tags_scale(Yₜ_sphere) > 0
        @test maximum(abs, tags_sum(Yₜ_sphere) .- parent(Yₜ_sphere.c.ρe_tot)) <
              100 * eps(FT) * tags_scale(Yₜ_sphere)
    end
end
