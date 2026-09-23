#=
Integration test for the energy source tags under `PrognosticEDMFX`.

By default the tags have no updraft copy. So under `PrognosticEDMFX` they take
their shares of the parent's own sub-grid fluxes of `E = ρe_tot + c·ρ`, and
exchange provenance at the mass flux, which sums to zero over the partition. This file checks that
on the shipped DYCOMS RF02 EDMF column, with 1-moment microphysics and the
updrafts' vertical diffusion on:

 1. the run completes. The updrafts' vertical diffusion skips the tags, which
    they do not carry, and still reaches the fields they do carry;
 2. the partition's tendencies from the sub-grid mass flux add up to the
    parent's, and each face takes the shares of the cell the flux leaves. The
    flux is rebuilt with each of the parent's reconstructions;
 3. the partition's tendencies from sedimentation add up to the parent's, with
    the updraft and environment corrections. The whole flux is shared once, by
    its direction;
 4. the tag code allocates nothing of its own;
 5. the split Jacobian solver solves every tag and record apart;
 6. the model's own fields are those of the same run without tags, bit for bit.

The EDMF column is the most expensive model in the test suite to build, and the
run without tags is a second model type. So this file has its own test group.
See `docs/src/energy_source_tags.md`.
=#
using Test
import ClimaAtmos as CA

# As in `energy_source_tags_integration.jl`: one call to compile, then
# `@allocated` on a second call, inside a function that specializes on every
# argument.
function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

@testset "Energy source tags under PrognosticEDMFX" begin
    c = 50000.0
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a
    # single column, for an hour, with the diagnostics off.
    test_dict = Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "turbconv" => "prognostic_edmfx",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "edmfx_entr_model" => "Generalized",
        "edmfx_detr_model" => "Generalized",
        "edmfx_sgs_mass_flux" => true,
        "edmfx_sgs_diffusive_flux" => true,
        "edmfx_nh_pressure" => true,
        "edmfx_vertical_diffusion" => true,
        "edmfx_filter" => true,
        "prognostic_tke" => true,
        "microphysics_model" => "1M",
        # Cloud liquid falls at a fixed speed by default. The diagnostic speed
        # differs between the updraft and the grid mean.
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
        # The bounds below are relative to machine precision.
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
    )
    tag_dict = Dict{String, Any}(
        "energy_source_tags" => [
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
            Dict{String, Any}("name" => "rad", "source" => "radiation"),
        ],
        # The column's minimum of `ρe_tot / ρ` is about -45.4 kJ/kg, so the
        # tags partition a positive total and their shares are defined.
        "energy_source_tag_offset" => c,
        "energy_process_record" => ["precipitation"],
    )
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(test_dict, tag_dict);
            job_id = "energy_source_tags_edmf_integration",
        ),
    )
    # 1. The run completes. Before the updrafts' vertical diffusion skipped
    # the tags, it failed here, asking the updraft for a tag field.
    @test CA.solve_atmos!(simulation).ret_code == :success
    Y = simulation.integrator.u
    p = simulation.integrator.p
    t = simulation.integrator.t
    FT = eltype(Y)
    turbconv_model = p.atmos.turbconv_model
    @test turbconv_model isa CA.PrognosticEDMFX

    # The updraft exists and differs from the grid mean, or items 2 and 3 are
    # vacuous.
    @test maximum(parent(Y.c.sgsʲs.:(1).ρa)) > 0
    @test maximum(
        abs,
        parent(p.precomputed.ᶜTʲs.:(1)) .- parent(p.precomputed.ᶜT),
    ) > 0

    ᶜz = CA.Fields.coordinate_field(Y.c).z
    ᶠz = CA.Fields.coordinate_field(Y.f).z
    ᶜJ = CA.Fields.local_geometry_field(Y.c).J
    ᶠJ = CA.Fields.local_geometry_field(Y.f).J
    model = p.atmos.energy_source_tagging_model

    # The updrafts' vertical diffusion alone, into a zeroed tendency. The grid
    # mean diffuses the tags, and the updraft, which has no copy of them, is
    # skipped. A field the updraft carries still takes the grid mean's
    # specific tendency. Here that is `q_tot`, which this function moves by
    # `K_h` and by `K_e` alike in the grid mean and in the updraft.
    @testset "The updrafts' vertical diffusion skips only the tags" begin
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y, p, t, turbconv_model)
        @test maximum(abs, parent(Yₜ.c.ρe_src_strat)) > 0
        ᶜq_totₜ = @. Yₜ.c.ρq_tot / Y.c.ρ
        scale = maximum(abs, parent(ᶜq_totₜ))
        @test scale > 0
        @test maximum(
            abs,
            parent(Yₜ.c.sgsʲs.:(1).q_tot) .- parent(ᶜq_totₜ),
        ) < 100 * eps(FT) * scale
    end

    # A step partition, as in the sedimentation item of
    # `energy_source_tags_integration.jl`: all of `E` above 750 m in `strat`,
    # and all below in `tropo`. A flux of one sign in a band around the step
    # then shows which cell each face takes its shares from.
    Y_step = copy(Y)
    ᶜE_step = @. Y_step.c.ρe_tot + c * Y_step.c.ρ
    @. Y_step.c.ρe_src_strat = ifelse(ᶜz > 750, ᶜE_step, FT(0))
    @. Y_step.c.ρe_src_tropo = ᶜE_step - Y_step.c.ρe_src_strat
    above = parent(ᶜz) .> 750
    ᶠband = @. (ᶠz > 500) & (ᶠz < 1000)
    function check_donor(Yₜ_step, ᶜparent_tendency, rises)
        strat = parent(Yₜ_step.c.ρe_src_strat)
        tropo = parent(Yₜ_step.c.ρe_src_tropo)
        @test maximum(abs, strat .+ tropo .- parent(ᶜparent_tendency)) <
              100 * eps(FT) * maximum(abs, parent(ᶜparent_tendency))
        if rises
            # The cell below is the donor. So `strat` never reaches below the
            # step, and `tropo` reaches only the first cell above it.
            @test all(iszero, strat[.!above])
            @test count(!iszero, tropo[above]) == 1
        else
            # The cell above is the donor: the mirror image.
            @test all(iszero, tropo[above])
            @test count(!iszero, strat[.!above]) == 1
        end
    end

    # 2. The sub-grid mass flux. The parent's alone, into a zeroed tendency,
    # moves `ρe_tot` and, in moist air, `ρ`. The tags partition
    # `E = ρe_tot + c·ρ`, so theirs must add up to the tendency of that.
    @testset "The sub-grid mass flux moves the tags with the parent" begin
        Yₜ = zero(Y)
        CA.edmfx_sgs_mass_flux_tendency!(Yₜ, Y, p, t, turbconv_model)
        # The parent's code never reaches a tag, which has no updraft copy.
        @test all(iszero, parent(Yₜ.c.ρe_src_strat))
        ᶜE_tendency = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
        scale = maximum(abs, parent(ᶜE_tendency))
        @test scale > 0
        CA.sgs_mass_flux_of_energy_source_tags!(Yₜ, Y, p, turbconv_model)
        ᶜpartition_tendency = @. Yₜ.c.ρe_src_strat + Yₜ.c.ρe_src_tropo
        # The partition's exchange of provenance sums to zero. Its rounding
        # scales with the exchange, which can be larger than the net flux.
        Yₜ_exchange = zero(Y)
        CA.sgs_exchange_of_energy_source_tags!(
            Yₜ_exchange,
            Y,
            p,
            turbconv_model,
            model,
        )
        exchange_scale = maximum(abs, parent(Yₜ_exchange.c.ρe_src_strat))
        @test exchange_scale > 0
        @test maximum(
            abs,
            parent(ᶜpartition_tendency) .- parent(ᶜE_tendency),
        ) < 100 * eps(FT) * (scale + exchange_scale)
        @test all(isfinite, parent(Yₜ.c.ρe_src_rad))

        # The column runs `edmfx_sgsflux_upwinding: none`. The tags rebuild
        # the flux with whichever reconstruction the parent uses, so each is
        # checked here against the parent's `vertical_transport`, on the
        # updraft's energy flux. Rounding scales with the face flux over the
        # level spacing.
        (; ᶠu³, ᶠu³ʲs, ᶜρʲs, ᶜKʲs, ᶜh_tot) = p.precomputed
        ᶠu³_diff = @. ᶠu³ʲs.:(1) - ᶠu³
        ᶜenergy = @. (Y.c.sgsʲs.:(1).mse + ᶜKʲs.:(1) - ᶜh_tot) *
           CA.draft_area(Y.c.sgsʲs.:(1).ρa, ᶜρʲs.:(1))
        ᶠρʲ = @. CA.ᶠinterp(ᶜρʲs.:(1) * ᶜJ) / ᶠJ
        Δz_min = minimum(parent(CA.Fields.Δz_field(Y.c)))
        for upwinding in (:none, :first_order, :vanleer_limiter, :third_order)
            vtt = CA.vertical_transport(
                ᶜρʲs.:(1),
                ᶠu³_diff,
                ᶜenergy,
                p.dt,
                Val(upwinding),
            )
            ᶜparent_tendency = zero.(Y.c.ρ)
            @. ᶜparent_tendency += vtt
            # The helper returns a lazy face value. It is not broadcast over.
            ᶠface_value =
                CA._face_value_flux(ᶠu³_diff, ᶜenergy, p.dt, Val(upwinding))
            ᶠrebuilt_flux = @. ᶠρʲ * ᶠface_value
            ᶜrebuilt_tendency = @. -CA.ᶜadvdivᵥ(ᶠrebuilt_flux)
            flux_scale = maximum(abs, parent(ᶠrebuilt_flux)) / Δz_min
            @test flux_scale > 0
            @test maximum(
                abs,
                parent(ᶜrebuilt_tendency) .- parent(ᶜparent_tendency),
            ) < 100 * eps(FT) * flux_scale
        end

        # Each face takes the shares of the cell the flux leaves.
        CA.energy_source_share_norm!(p, Y_step)
        for rises in (false, true)
            ᶠflux = @. CA.CT3(ifelse(ᶠband, (rises ? 1 : -1) * FT(0.1), FT(0)))
            Yₜ_step = zero(Y_step)
            CA._sgs_energy_source_tag_fluxes!(
                Yₜ_step.c,
                Y_step.c,
                ᶜE_step,
                p.scratch.ᶜe_src_share_norm,
                ᶠflux,
                model.tags,
            )
            check_donor(Yₜ_step, (@. -CA.ᶜadvdivᵥ(ᶠflux)), rises)
        end
    end

    # 3. Sedimentation. Under EDMF the parent's energy flux has an updraft and
    # an environment correction besides the grid mean's.
    @testset "Sedimentation moves the tags with the corrections" begin
        Yₜ = zero(Y)
        CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
        ᶜE_tendency = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
        scale = maximum(abs, parent(ᶜE_tendency))
        @test scale > 0
        ᶜpartition_tendency = @. Yₜ.c.ρe_src_strat + Yₜ.c.ρe_src_tropo
        closure_error = maximum(
            abs,
            parent(ᶜpartition_tendency) .- parent(ᶜE_tendency),
        )
        @test closure_error < 100 * eps(FT) * scale
        @test all(isfinite, parent(Yₜ.c.ρe_src_rad))

        # Without the corrections, the tags would miss the parent by far more.
        # This is the grid mean's flux alone, as the first loop of
        # `vertical_advection_of_water_tendency!` builds it, shared as the tags
        # share it without EDMF.
        thermo_params = CA.CAP.thermodynamics_params(p.params)
        (; ᶜT, ᶜu) = p.precomputed
        ᶜΦ = p.core.ᶜΦ
        ᶠρ = @. CA.ᶠinterp(Y.c.ρ * ᶜJ) / ᶠJ
        Yₜ_grid_mean = zero(Y)
        CA.energy_source_share_norm!(p, Y)
        for (ρq_name, w_name, internal_energy) in (
            (:ρq_lcl, :ᶜwₗ, CA.TD.internal_energy_liquid),
            (:ρq_icl, :ᶜwᵢ, CA.TD.internal_energy_ice),
            (:ρq_rai, :ᶜwᵣ, CA.TD.internal_energy_liquid),
            (:ρq_sno, :ᶜwₛ, CA.TD.internal_energy_ice),
        )
            ᶜρq = getproperty(Y.c, ρq_name)
            ᶜq = @. CA.specific(ᶜρq, Y.c.ρ)
            ᶜw = getproperty(p.precomputed, w_name)
            ᶜenergy_flux = @. -(ᶜw) *
               ᶜq *
               (internal_energy(thermo_params, ᶜT) + ᶜΦ + $(CA.Kin(ᶜw, ᶜu)))
            CA.sediment_energy_source_tags!(
                Yₜ_grid_mean,
                Y,
                p,
                ᶜq,
                ᶜw,
                ᶜenergy_flux,
                ᶠρ,
            )
        end
        ᶜgrid_mean_tendency =
            @. Yₜ_grid_mean.c.ρe_src_strat + Yₜ_grid_mean.c.ρe_src_tropo
        correction_size = maximum(
            abs,
            parent(ᶜgrid_mean_tendency) .- parent(ᶜE_tendency),
        )
        @info "Sedimentation under EDMF" scale closure_error correction_size
        @test correction_size > 1000 * 100 * eps(FT) * scale

        # The whole flux is shared once, by its direction. A grid mean's flux
        # that falls, with corrections that rise by more, makes a flux that
        # rises. Then the cell below is the donor, as when the energy rises
        # alone. With no water given, the offset adds nothing.
        CA.energy_source_share_norm!(p, Y_step)
        ᶜnone = zero.(Y_step.c.ρ)
        ᶠρ_step = @. CA.ᶠinterp(Y_step.c.ρ * ᶜJ) / ᶠJ
        ᶜfalls = @. ifelse((ᶜz > 500) & (ᶜz < 1000), -FT(1000), FT(0))
        ᶠcorrection =
            @. CA.Geometry.WVector(ifelse(ᶠband, FT(2000), FT(0)))
        Yₜ_step = zero(Y_step)
        CA.keep_energy_source_sediment_correction!(p, ᶠcorrection)
        CA.sediment_energy_source_tags_with_corrections!(
            Yₜ_step,
            Y_step,
            p,
            ᶜnone,
            ᶜnone,
            ᶜfalls,
            ᶠρ_step,
            ᶠcorrection,
        )
        ᶜparent_tendency = @. -CA.ᶜprecipdivᵥ(
            ᶠρ_step * CA.ᶠtop_bias(CA.Geometry.WVector(ᶜfalls)) +
            2 * ᶠcorrection,
        )
        check_donor(Yₜ_step, ᶜparent_tendency, true)
    end

    # 4. The tag code allocates nothing of its own. The sub-grid flux reads the
    # environment's `mse` and `q_tot` through the parent's helpers, as the
    # parent's own flux does, and the exchange reads `mse` once more. Their
    # `ᶜenv_value` broadcasts over a closure, which Julia wraps in a `Ref`, 8
    # bytes each. That is all the tags' function allocates, by Julia's
    # allocation profiler, on the versions the fork runs. On the oldest
    # versions its compat allows, the exchange's broadcasts reach through the
    # environment's thermodynamic density, stop inferring and allocate per
    # cell, so the bound follows the environment. NEWS records it. The parent's
    # `edmfx_sgs_mass_flux_tendency!` allocated 62,928 bytes per call on this
    # column. The sedimentation check includes the parent's own corrections,
    # which run with or without tags.
    @testset "The tags do not allocate" begin
        Yₜ = zero(Y)
        @test second_call_allocations(
            CA.sgs_mass_flux_of_energy_source_tags!,
            Yₜ,
            Y,
            p,
            turbconv_model,
        ) <= (pkgversion(CA.ClimaCore) >= v"1" ? 24 : 32_768)
        @test second_call_allocations(
            CA.vertical_advection_of_water_tendency!,
            Yₜ,
            Y,
            p,
            t,
        ) == 0
    end

    # 5. The tags and the record couple to nothing in the Jacobian, so the
    # split solver solves each apart from the nested one. A cross block, say
    # between a tag and the updraft's velocity, would move the tag back into
    # the nested solver without an error, and the build time that #76 removed
    # would return. This cache has the integrator's types, so it costs no
    # compile.
    @testset "The split solver solves the tags and the record apart" begin
        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        diagnostic_names = filter(
            name ->
                CA.is_energy_source_tag_name(name) ||
                startswith(string(name), "prc_"),
            propertynames(Y.c),
        )
        @test length(diagnostic_names) == 4
        @test Set(map(field -> field.name, cache.solver.uncoupled)) ==
              Set(map(name -> CA.MatrixFields.FieldName(:c, name), diagnostic_names))
    end

    # 6. The tags and the record change none of the model's own fields. The
    # same run without them is a new model type, so this costs a second
    # compile. `isequal` tells signed zeros apart, which `==` does not. See
    # "Fork parity with upstream" in `docs/clima_atmos_specific.md`.
    @testset "The model's fields do not depend on the tags" begin
        plain_dict = merge(
            test_dict,
            Dict{String, Any}("output_dir" => mktempdir(pwd())),
        )
        plain = CA.get_simulation(
            CA.AtmosConfig(
                plain_dict;
                job_id = "energy_source_tags_edmf_integration_plain",
            ),
        )
        @test CA.solve_atmos!(plain).ret_code == :success
        Y_plain = plain.integrator.u
        @test all(
            name ->
                hasproperty(Y_plain.c, name) ||
                CA.is_energy_source_tag_name(name) ||
                startswith(string(name), "prc_"),
            propertynames(Y.c),
        )
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        for name in propertynames(Y_plain.c)
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        for name in propertynames(Y_plain.f)
            @test isequal(
                parent(getproperty(Y.f, name)),
                parent(getproperty(Y_plain.f, name)),
            )
        end
    end
end
