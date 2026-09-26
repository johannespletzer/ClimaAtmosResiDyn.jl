#=
Integration test for `water_tag_updraft_copy: true`, the audit of the water
tags' mixing through the updrafts.

Each tag gets a copy in the updraft, `q_tag_<name>`, which the model moves as
any other updraft tracer. Five mirrors give the copies what the updraft's water
gets and a tracer does not: the 0M rain-out, the 1M sedimentation, the
relaxation at the surface, the surface flux and the repair after the filter. This file checks,
on the DYCOMS RF02 EDMF column with 1-moment microphysics, stepped explicitly
so that parity covers the tags' brackets on the explicit path, after an hour:

 1. the copies exist, and the rebuild sets them to `q_totʲ φ̄ᵢ`;
 2. the default mode's flux and exchange do nothing, and the model's SGS
    tracer flux moves the tags;
 3. the partition and the copies stay closed;
 4. with one composition everywhere, each copy's whole tendency is its share
    of `q_totʲ`'s, up to the diffusion's leak, whose closed form it checks, and
    up to the surface flux, whose new water goes by region and source. The
    partition's copies take all of the updraft's surface flux;
 5. the copies' own code allocates next to nothing;
 6. the model's fields are those of the same column without tags, bit for bit;
 7. the partition copies' sedimentation cross blocks to each updraft species
    sum to the updraft water's block, `(q_totʲ, qʲ)`, to rounding (WP5b-C).

The copies are a model type of their own, and the check against the column
without tags needs a second. So the file builds the EDMF column twice and has a
test group of its own. See `docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

function run_simulation(config_dict, job_id)
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(
                config_dict,
                Dict{String, Any}("output_dir" => mktempdir(pwd())),
            );
            job_id,
        ),
    )
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

relative_difference(a, b) =
    maximum(abs, parent(a) .- parent(b)) / maximum(abs, parent(b))

# The whole tendency, explicit and implicit, as the stepper sums them.
function whole_tendency(Y, p, t)
    Yₜ = zero(Y)
    Yₜ_lim = zero(Y)
    CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t)
    Yₜ_implicit = zero(Y)
    CA.implicit_tendency!(Yₜ_implicit, Y, p, t)
    return Yₜ .+ Yₜ_lim .+ Yₜ_implicit
end

@testset "Water tags with updraft copies" begin
    edmf_dict = Dict{String, Any}(
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
        "implicit_microphysics" => false,
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        # On the explicit microphysics path with one Newton iteration the
        # tags lag the parent's solve: the parent's rows carry the
        # sedimenting species' cross blocks and the tags' do not
        # (`update_water_tag_sedimentation_jacobian!`). After an hour the
        # partition then misses by 0.8% net. With ten iterations it closes to
        # 4e-7 net and 8e-4 gross. That lag is WP5's to follow; this file
        # checks the copies, so it converges the solve.
        "max_newton_iters_ode" => 10,
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
    )
    tag_dict = Dict{String, Any}(
        "water_tracers" => [
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        "water_tag_updraft_copy" => true,
        # The audit and the diagnostics write scratch from callbacks, so the
        # parity check below covers them too.
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => [
                    "q_tag_leak_vdiff",
                    "q_tag_leak_diffusion_up",
                    "q_tag_copy_res",
                    "q_tag_upfix_tropo",
                    "q_tag_led_upfilter",
                    "q_tag_led_repair_gross",
                    "q_tag_led_uprepair_colgross",
                ],
                "period" => "10mins",
            ),
        ],
    )
    copies = run_simulation(merge(edmf_dict, tag_dict), "water_tags_edmf_copies")
    Y = copies.integrator.u
    p = copies.integrator.p
    t = copies.integrator.t
    model = p.atmos.water_tagging_model
    turbconv_model = p.atmos.turbconv_model
    ᶜsgsʲ = Y.c.sgsʲs.:(1)

    # 1. The copies.
    @testset "The updraft carries a copy of each tag" begin
        @test CA.has_water_tag_updraft_copies(model)
        @test CA.water_tag_updraft_copy_names(model) ==
              (:q_tag_tropo, :q_tag_strat, :q_tag_evap)
        for name in CA.water_tag_updraft_copy_names(model)
            @test hasproperty(ᶜsgsʲ, name)
        end
        # The surface's water has reached the updraft.
        @test maximum(parent(ᶜsgsʲ.q_tag_evap)) > 0
        @test all(isfinite, parent(Y.c.sgsʲs))
        # The rebuild sets each copy to the updraft's water times the grid
        # mean's share: on a grid mean with set shares, those shares.
        Y_rebuilt = copy(Y)
        Y_rebuilt.c.ρq_tag_tropo .= 0.3 .* Y.c.ρq_tot
        Y_rebuilt.c.ρq_tag_strat .= 0.7 .* Y.c.ρq_tot
        CA.rebuild_water_tag_updraft_copies!(Y_rebuilt, model, turbconv_model)
        @test isapprox(
            parent(Y_rebuilt.c.sgsʲs.:(1).q_tag_tropo),
            parent(0.3 .* ᶜsgsʲ.q_tot);
            rtol = 1e-14,
        )
        @test isapprox(
            parent(Y_rebuilt.c.sgsʲs.:(1).q_tag_strat),
            parent(0.7 .* ᶜsgsʲ.q_tot);
            rtol = 1e-14,
        )
        # The comparison runs' driver starts the copies from the default
        # mode's plume instead, which is rescaled so that the partition holds
        # the updraft's water.
        Y_plume = copy(Y)
        CA.start_water_tag_copies_from_plume!(Y_plume, p)
        ᶜsgsʲ_plume = Y_plume.c.sgsʲs.:(1)
        @test isapprox(
            parent(ᶜsgsʲ_plume.q_tag_tropo .+ ᶜsgsʲ_plume.q_tag_strat),
            parent(ᶜsgsʲ.q_tot);
            rtol = 1e-14,
        )
        @test !isequal(
            parent(ᶜsgsʲ_plume.q_tag_tropo),
            parent(ᶜsgsʲ.q_tag_tropo),
        )
    end

    # 2. The default mode's flux and exchange do nothing, and the model's own
    # SGS tracer flux moves the tags.
    @testset "The model's SGS tracer flux moves the tags" begin
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model)
        @test all(iszero, parent(Yₜ))
        CA.edmfx_sgs_mass_flux_tendency!(Yₜ, Y, p, t, turbconv_model)
        @test maximum(abs, parent(Yₜ.c.ρq_tag_evap)) > 0
        @test maximum(abs, parent(Yₜ.c.ρq_tag_tropo)) > 0
    end

    # 3. The partition closes, and the copies' repair finds only a small
    # residual. This column with ten Newton iterations gave -4.3e-7 net,
    # 7.5e-4 gross and a copies' residual of 9.3e-5 after an hour (a probe
    # run of the WP3 branch). The copies' bound is G3_PLAN 6.1's budget for
    # it. What the repair moves is printed, not bounded here: it bounds a sum
    # of several parts (`docs/src/tagged_water.md`).
    @testset "The partition and the copies stay closed" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        audit = CA.water_tag_edmf_audit(Y, p, model, closure.scale)
        @info "Water tags with copies on the EDMF column after an hour" closure.relative closure.gross_relative audit
        @test abs(closure.relative) < 1e-4
        @test closure.gross_relative < 1e-3
        @test propertynames(audit) == (
            :copy_residual,
            :copy_residual_relative,
            :copy_repair,
            :copy_repair_relative,
        )
        @test audit.copy_residual_relative < 2e-4
    end

    # WP6: the state ledgers per mechanism. The repairs run in
    # `constrain_state!`, which at the default cadence fires once per step, on
    # the accepted state. So what the steps retained is what the repairs
    # attempted, and the cache ledgers give it. No limiter acts here, so the
    # partition's cache gross is the repair's alone.
    @testset "The state ledgers per mechanism" begin
        (; ᶜwater_fix_gross, ᶜwater_upfix) = p.tagging
        close(a, b) = isapprox(
            parent(a),
            parent(b);
            rtol = 1e-10,
            atol = 1e-12 * maximum(abs, parent(Y.c.ρq_tot)),
        )
        # The repair's transfer ledger and half its net make up half its
        # gross, since the transfer is half the changes less their net.
        @test close(
            Y.c.q_tag_led_repair .+ Y.c.q_tag_led_repairnet ./ 2,
            (ᶜwater_fix_gross.ρq_tag_tropo .+ ᶜwater_fix_gross.ρq_tag_strat) ./
            2,
        )
        @test close(
            Y.c.q_tag_led_uprepair,
            ᶜwater_upfix.ρq_tag_tropo .+ ᶜwater_upfix.ρq_tag_strat,
        )
        @test maximum(abs, parent(Y.c.q_tag_led_uprepair)) > 0
        @test maximum(abs, parent(Y.c.q_tag_led_upfilter)) > 0
        # The gross per step is at least what the ledger holds, per cell and
        # per column, since each ledger starts at zero.
        (; ledgers) = p.tagging.tag_ledger_steps
        @test propertynames(ledgers) == CA.water_tag_mechanism_names(model)
        for name in propertynames(ledgers)
            ᶜL = getproperty(Y.c, name)
            (; ᶜgross, colgross) = getproperty(ledgers, name)
            @test all(parent(ᶜgross) .>= abs.(parent(ᶜL)) .* (1 - 1e-12))
            column_total = similar(colgross)
            CA.Operators.column_integral_definite!(column_total, ᶜL)
            @test all(
                parent(colgross) .>= abs.(parent(column_total)) .* (1 - 1e-12),
            )
        end
    end

    # 4. With one composition everywhere, every term the copies take from the
    # tracer machinery or from the mirrors is its share of `q_totʲ`'s. There
    # are two exceptions. The diffusion's mirror: a copy takes its grid-mean
    # tag's diffusion, on the whole value, and `q_totʲ` the parent's, on the
    # water without rain and snow. That difference is the closed form's leak.
    # And the surface flux: new water goes to the tags by region and source,
    # not by share. So it is taken out of both sides, and checked on its own.
    @testset "One composition moves as the updraft's water" begin
        shares = (; tropo = 0.3, strat = 0.7, evap = 0.2)
        Y_uniform = copy(Y)
        ᶜsgsʲ_uniform = Y_uniform.c.sgsʲs.:(1)
        for (name, share) in pairs(shares)
            getproperty(Y_uniform.c, Symbol(:ρq_tag_, name)) .=
                share .* Y.c.ρq_tot
            getproperty(ᶜsgsʲ_uniform, Symbol(:q_tag_, name)) .=
                share .* ᶜsgsʲ.q_tot
        end
        CA.set_precomputed_quantities!(Y_uniform, p, t)
        Yₜ = whole_tendency(Y_uniform, p, t)
        Yₜ_surface = zero(Y)
        CA.surface_flux_tendency!(Yₜ_surface, Y_uniform, p, t)
        CA.water_tag_copies_surface_flux_tendency!(
            Yₜ_surface,
            Y_uniform,
            p,
            turbconv_model,
        )
        ᶜq_totʲₜ_surface = Yₜ_surface.c.sgsʲs.:(1).q_tot
        @test maximum(abs, parent(ᶜq_totʲₜ_surface)) > 0
        # The partition's copies take the updraft's whole surface flux, and
        # `evap`, which receives the surface flux and has no region, all the
        # new water and its share of any dew.
        @test relative_difference(
            Yₜ_surface.c.sgsʲs.:(1).q_tag_tropo .+
            Yₜ_surface.c.sgsʲs.:(1).q_tag_strat,
            ᶜq_totʲₜ_surface,
        ) < 1e-12
        @test relative_difference(
            Yₜ_surface.c.sgsʲs.:(1).q_tag_evap,
            max.(ᶜq_totʲₜ_surface, 0) .+
            min.(ᶜq_totʲₜ_surface, 0) .* shares.evap,
        ) < 1e-12
        ᶜq_totʲₜ = Yₜ.c.sgsʲs.:(1).q_tot .- ᶜq_totʲₜ_surface
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:diffusion_up))
        @test maximum(abs, parent(ᶜleak)) > 0
        # The leak per unit mass of updraft air, where there is an updraft.
        # Above the cloud `ρaʲ` is exactly zero on some levels, and there the
        # leak is zero too.
        ᶜleakʲ = @. ifelse(
            ᶜsgsʲ.ρa > 0,
            ᶜleak * Y.c.ρ / ᶜsgsʲ.ρa,
            zero(ᶜleak),
        )
        @test all(isfinite, parent(ᶜleakʲ))
        for (name, share) in pairs(shares)
            copy_name = Symbol(:q_tag_, name)
            ᶜχₜ =
                getproperty(Yₜ.c.sgsʲs.:(1), copy_name) .-
                getproperty(Yₜ_surface.c.sgsʲs.:(1), copy_name)
            @test relative_difference(ᶜχₜ, share .* (ᶜq_totʲₜ .+ ᶜleakʲ)) <
                  1e-10
        end
    end

    # 4b. The sedimentation mirror takes the updraft's share for the falling
    # updraft water and the environment's for the inflow. With one composition
    # everywhere a swap would not show, so here the shares differ between the
    # subdomains, and the mirror is compared with the model's own operator fed
    # the shares by hand: falling water only, inflow only, and both.
    @testset "The sedimentation mirror takes each subdomain's share" begin
        # Updraft shares, and environment shares, per tag.
        up = (; tropo = 0.3, strat = 0.7, evap = 0.6)
        env = (; tropo = 0.8, strat = 0.2, evap = 0.1)
        Y_m = copy(Y)
        ᶜρaq_totʲ = ᶜsgsʲ.ρa .* ᶜsgsʲ.q_tot
        for name in (:tropo, :strat, :evap)
            getproperty(Y_m.c.sgsʲs.:(1), Symbol(:q_tag_, name)) .=
                getproperty(up, name) .* ᶜsgsʲ.q_tot
            getproperty(Y_m.c, Symbol(:ρq_tag_, name)) .=
                getproperty(up, name) .* ᶜρaq_totʲ .+
                getproperty(env, name) .* (Y.c.ρq_tot .- ᶜρaq_totʲ)
        end
        ᶜρʲ = p.precomputed.ᶜρʲs.:(1)
        ᶜa = CA.draft_area.(ᶜsgsʲ.ρa, ᶜρʲ)
        ᶜw = zero.(Y.c.ρ) .+ 3.0
        ᶜinv_ρ̂ = zero.(Y.c.ρ) .+ 1.0
        ᶠJ = CA.Fields.local_geometry_field(Y.f).J
        α_lat = 1.0
        ᶜq_rain = ᶜsgsʲ.q_rai .+ 1e-6
        ᶜinflow = Y.c.ρ .* 1e-6
        ᶜzero = zero.(Y.c.ρ)
        expected_vtt = similar(Y.c.ρ)
        for (ᶜqʲ, ᶜρ⁰w⁰q⁰, what) in (
            (ᶜq_rain, ᶜzero, "falling only"),
            (ᶜzero, ᶜinflow, "inflow only"),
            (ᶜq_rain, ᶜinflow, "both"),
        )
            Yₜ = zero(Y)
            CA.sediment_water_tag_copies!(
                Yₜ,
                Y_m,
                p,
                1,
                ᶜqʲ,
                ᶜw,
                ᶜa,
                ᶜρ⁰w⁰q⁰,
                α_lat,
                ᶜinv_ρ̂,
                ᶠJ,
            )
            for name in (:tropo, :strat, :evap)
                CA.updraft_sedimentation!(
                    expected_vtt,
                    p,
                    ᶜρʲ,
                    ᶜw,
                    ᶜa,
                    ᶜqʲ .* getproperty(up, name),
                    ᶠJ,
                    ᶜρ⁰w⁰q⁰ .* getproperty(env, name),
                    α_lat,
                )
                ᶜχₜ = getproperty(Yₜ.c.sgsʲs.:(1), Symbol(:q_tag_, name))
                @test maximum(abs, parent(ᶜχₜ)) > 0
                # The environment's shares come through the model's
                # regularized environment values, so they agree to about the
                # regularization, far below a swapped share's error.
                @test relative_difference(ᶜχₜ, expected_vtt) < 1e-4
            end
        end
    end

    # 5. The copies' own code.
    @testset "The copies do not allocate" begin
        Yₜ = zero(Y)
        @test second_call_allocations(
            CA.water_tag_copies_boundary_condition_tendency!,
            Yₜ,
            Y,
            p,
            turbconv_model,
        ) <= 64
        @test second_call_allocations(CA.repair_water_tag_copies!, copy(Y), p) <=
              64
    end

    # 6. The model's own fields.
    @testset "The model's fields do not depend on the copies" begin
        plain = run_simulation(edmf_dict, "water_tags_edmf_copies_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
        is_tag(name) =
            startswith(string(name), "ρq_tag_") ||
            CA.is_tag_mechanism_ledger_name(name)
        @test Set(filter(!is_tag, propertynames(Y.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            name == :sgsʲs && continue
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        for name in propertynames(Y_plain.c.sgsʲs.:(1))
            @test isequal(
                parent(getproperty(Y.c.sgsʲs.:(1), name)),
                parent(getproperty(Y_plain.c.sgsʲs.:(1), name)),
            )
        end
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end

    # WP6, after the parity check, since these step the run on. The updraft
    # filter's ledger is its change of the partition copies' water, and the
    # ledgers' kernels allocate nothing.
    @testset "The filter's ledger and the kernels' allocation" begin
        Y_filter = copy(Y)
        # A negative copy, which the filter clamps, so the check is not vacuous.
        Y_filter.c.sgsʲs.:(1).q_tag_tropo .-= 1e-3
        copy_water(Y) =
            Y.c.sgsʲs.:(1).ρa .*
            (Y.c.sgsʲs.:(1).q_tag_tropo .+ Y.c.sgsʲs.:(1).q_tag_strat)
        ᶜbefore = copy_water(Y_filter)
        ᶜledger = copy(Y_filter.c.q_tag_led_upfilter)
        CA.snapshot_water_tag_copy_water!(Y_filter, p)
        CA.enforce_physical_constraints!(Y_filter, p, t, p.atmos)
        CA.record_water_tag_copy_filter!(Y_filter, p)
        ᶜchange = copy_water(Y_filter) .- ᶜbefore
        @test maximum(abs, parent(ᶜchange)) > 0
        @test isapprox(
            parent(Y_filter.c.q_tag_led_upfilter .- ᶜledger),
            parent(ᶜchange);
            rtol = 1e-12,
            atol = 1e-14 * maximum(abs, parent(ᶜbefore)),
        )
        CA.snapshot_water_tag_copy_water!(Y_filter, p)
        @test (@allocated CA.snapshot_water_tag_copy_water!(Y_filter, p)) == 0
        CA.record_water_tag_copy_filter!(Y_filter, p)
        @test (@allocated CA.record_water_tag_copy_filter!(Y_filter, p)) == 0
        CA.repair_water_tag_partition!(Y_filter, p)
        @test (@allocated CA.repair_water_tag_partition!(Y_filter, p)) == 0
        CA.repair_water_tag_copies!(Y_filter, p)
        @test (@allocated CA.repair_water_tag_copies!(Y_filter, p)) == 0
    end

    # The gross per step is the ledgers' change over that step, per cell, bit
    # for bit: one more step, taken by hand.
    @testset "The ledgers' gross, one step by hand" begin
        integrator = copies.integrator
        (; ledgers) = integrator.p.tagging.tag_ledger_steps
        names = keys(ledgers)
        @test names == CA.water_tag_mechanism_names(model)
        L_before = map(n -> Float64.(parent(getproperty(integrator.u.c, n))), names)
        G_before = map(n -> copy(parent(getproperty(ledgers, n).ᶜgross)), names)
        CA.CTS.step!(integrator)
        for (i, n) in enumerate(names)
            ᶜL = Float64.(parent(getproperty(integrator.u.c, n)))
            @test parent(getproperty(ledgers, n).ᶜgross) ==
                  G_before[i] .+ abs.(ᶜL .- L_before[i])
        end
        # At most ClimaCore's column integral, about 200 bytes a call where it
        # allocates, one call per ledger.
        CA.accumulate_tag_ledger_gross!(integrator)
        @test (@allocated CA.accumulate_tag_ledger_gross!(integrator)) <=
              256 * length(names)
    end

    # 7. Each copy falls with its share of each species, as `q_totʲ` falls
    # with all of it, so each copy's row has a block to each species' column
    # (WP5b-C). Over the partition the updraft's shares sum to one, and so do
    # the environment's, so the partition copies' blocks sum to the updraft
    # water's.
    @testset "The copies' sedimentation cross blocks sum to the water's" begin
        integrator = copies.integrator
        alg = CA.ManualSparseJacobian(; approximate_solve_iters = 2)
        cache = CA.jacobian_cache(alg, integrator.u, p.atmos)
        CA.update_jacobian!(alg, cache, integrator.u, p, 60.0, integrator.t)
        sgs(name) = CA.sgs_state_name(CA.MatrixFields.FieldName(name))
        partition_copies = (:q_tag_tropo, :q_tag_strat)
        for species in CA.sedimenting_sgs_mass_names(integrator.u)
            ᶜblock = cache.matrix[sgs(:q_tot), CA.sgs_state_name(species)]
            ᶜsum = copy(ᶜblock)
            parent(ᶜsum) .= 0
            for name in partition_copies
                ᶜcopy_block = cache.matrix[sgs(name), CA.sgs_state_name(species)]
                @. ᶜsum = ᶜsum + ᶜcopy_block
            end
            scale = maximum(abs, parent(ᶜblock))
            @test scale > 0
            @test maximum(abs, parent(ᶜsum) .- parent(ᶜblock)) <=
                  100 * eps(Float64) * scale
        end
    end
end
