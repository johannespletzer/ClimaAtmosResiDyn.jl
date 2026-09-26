#=
Integration test for the water tags' updraft copies under 0-moment
microphysics, with the microphysics implicit, the default.

Under 0M the updraft rains out: `microphysics_tendency!` takes water from
`q_totʲ` and air from `ρaʲ`. The copies' mirror takes each copy's share of
that water. No rain or snow is prognostic, so no path leaks. This file checks,
on the DYCOMS RF02 EDMF column with 0-moment microphysics and a passive
chemistry tracer in the updraft, after an hour:

 1. a passive tracer set to what a tag and its copy hold takes the copy's
    tendency, apart from the copy's three mirrors that act under 0M, at
    rounding. So the copies get the whole of the tracer machinery;
 2. with one composition everywhere, each copy's whole tendency is its share
    of `q_totʲ`'s, at rounding, apart from the surface flux, whose new water
    goes by region and source;
 3. the grid tags' rain-out is split by subdomain (WP4a). Each subdomain's
    part, taken from the real code, is that subdomain's rain times the tag's
    share there: the copy's own share in the updraft, and in the environment
    shares that sum to `S` and are not the grid mean's. `pr_tag` integrates
    the same increments, from one batch per output time, without allocating.
    `pr` less the partition's `pr_tag` is `pr_tag_res`, and that is the
    rain-out the shares leave, `∫ (Δʲ (1 - Sʲ) + Δ⁰ (1 - S))`, to rounding;
 4. the model's fields are those of the same column without tags, bit for bit;
 5. in the default mode, each subdomain's shares are the exchange's, the
    exchange's tendency is unchanged by the split, `pr` less the partition's
    `pr_tag` is `∫ (1 - S) (Δʲ + Δ⁰)`, and with the partition closed it is
    zero to rounding. The model's fields are the untagged column's.

The rain-out mirror and the split run on the implicit path here, where the 0M
sink lives by default. The explicit path runs in
`tagged_water_edmf_0m_explicit_integration.jl`, group
`tagging_water_edmf_0m_explicit`. See `docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

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

function test_same_model_fields(Y, Y_plain)
    # The tags, and in the default mode under `increment`, the default under
    # EDMF, the follower's ledger.
    is_tag(name) =
        startswith(string(name), "ρq_tag_") ||
        CA.is_water_tag_ledger_name(name) ||
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
    @test isequal(parent(Y.f), parent(Y_plain.f))
end

# Each subdomain's part of the split, from the real code: the split with the
# other subdomain's cached rate set to zero. The split is linear in the two
# rates, so the parts add up to it.
function subdomain_parts(Y, p, model)
    ᶜdqʲ = p.precomputed.ᶜmp_tendencyʲs.:(1).dq_tot_dt
    ᶜdq⁰ = p.precomputed.ᶜmp_tendency⁰.dq_tot_dt
    (savedʲ, saved⁰) = (copy(ᶜdqʲ), copy(ᶜdq⁰))
    function part(ᶜzeroed)
        ᶜzeroed .= 0
        ᶜdest = CA._water_fix_fields(Y.c.ρ, model.tags)
        CA.add_split_rainout!(ᶜdest, Y, p, model)
        ᶜdqʲ .= savedʲ
        ᶜdq⁰ .= saved⁰
        return ᶜdest
    end
    return (; updraft = part(ᶜdq⁰), environment = part(ᶜdqʲ))
end

# The two subdomains' rain-out, as the model adds it to `ρq_tot`, and the
# partition's sum of clamped grid shares `S`.
function rainout_inputs(Y, p)
    ᶜΔʲ = copy(CA._rainout_updraft(Y, p))
    ᶜΔ⁰ = copy(CA._rainout_environment(Y, p))
    CA.water_tag_share_norm!(p, Y)
    ᶜS = copy(p.scratch.ᶜtagging_q_share_norm)
    scale = maximum(abs, parent(ᶜΔʲ)) + maximum(abs, parent(ᶜΔ⁰))
    return (; ᶜΔʲ, ᶜΔ⁰, ᶜS, scale)
end

# To rounding against the rain-out: the split is a sum of a few products per
# cell, so the identities below hold to a few eps of the largest rate.
same_to_rounding(a, b, scale) =
    maximum(abs, parent(a) .- parent(b)) <= 100 * eps(Float64) * scale

column_integral(p, ᶜx) = (
    out = similar(p.scratch.ᶠtemp_field_level);
    CA.Operators.column_integral_definite!(out, ᶜx);
    out
)

function whole_tendency(Y, p, t)
    Yₜ = zero(Y)
    Yₜ_lim = zero(Y)
    CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t)
    Yₜ_implicit = zero(Y)
    CA.implicit_tendency!(Yₜ_implicit, Y, p, t)
    return Yₜ .+ Yₜ_lim .+ Yₜ_implicit
end

@testset "Water tags with updraft copies under 0M" begin
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
        "microphysics_model" => "0M",
        "chemistry_model" => "passive",
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
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
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" =>
                    ["q_tag_copy_res", "q_tag_leak_vdiff", "pr_tag_tropo"],
                "period" => "10mins",
            ),
        ],
    )
    copies = run_simulation(merge(edmf_dict, tag_dict), "water_tags_edmf_0m")
    Y = copies.integrator.u
    p = copies.integrator.p
    t = copies.integrator.t
    turbconv_model = p.atmos.turbconv_model
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    @test hasproperty(ᶜsgsʲ, :q_gas_A)
    @test all(isfinite, parent(Y.c))

    # 1. The tracer set to what `tropo` and its copy hold, in the grid mean and
    # in the updraft. The tracer machinery then gives both the same tendency,
    # and the copy has its mirrors on top: the rain-out, the relaxation at the
    # surface and the surface flux.
    @testset "A copy moves as a passive tracer, apart from its mirrors" begin
        Y_same = copy(Y)
        Y_same.c.ρq_gas_A .= Y.c.ρq_tag_tropo
        Y_same.c.sgsʲs.:(1).q_gas_A .= ᶜsgsʲ.q_tag_tropo
        @test maximum(parent(ᶜsgsʲ.q_tag_tropo)) > 0
        CA.set_precomputed_quantities!(Y_same, p, t)
        Yₜ = whole_tendency(Y_same, p, t)
        Yₜ_mirrors = zero(Y)
        CA.water_tag_copies_microphysics_tendency!(
            Yₜ_mirrors,
            Y_same,
            p,
            p.atmos.microphysics_model,
            turbconv_model,
        )
        CA.water_tag_copies_boundary_condition_tendency!(
            Yₜ_mirrors,
            Y_same,
            p,
            turbconv_model,
        )
        CA.water_tag_copies_surface_flux_tendency!(
            Yₜ_mirrors,
            Y_same,
            p,
            turbconv_model,
        )
        # The mirrors did something, so the check is not vacuous.
        @test maximum(abs, parent(Yₜ_mirrors.c.sgsʲs.:(1).q_tag_tropo)) > 0
        @test relative_difference(
            Yₜ.c.sgsʲs.:(1).q_tag_tropo .- Yₜ_mirrors.c.sgsʲs.:(1).q_tag_tropo,
            Yₜ.c.sgsʲs.:(1).q_gas_A,
        ) < 1e-10
    end

    # 2. Under 0M nothing leaks, so the copies' shares move with `q_totʲ`,
    # apart from the surface flux, which is taken out of both sides.
    @testset "One composition moves as the updraft's water" begin
        shares = (; tropo = 0.3, strat = 0.7, evap = 0.2)
        Y_uniform = copy(Y)
        for (name, share) in pairs(shares)
            getproperty(Y_uniform.c, Symbol(:ρq_tag_, name)) .=
                share .* Y.c.ρq_tot
            getproperty(Y_uniform.c.sgsʲs.:(1), Symbol(:q_tag_, name)) .=
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
        ᶜq_totʲₜ = Yₜ.c.sgsʲs.:(1).q_tot .- Yₜ_surface.c.sgsʲs.:(1).q_tot
        for (name, share) in pairs(shares)
            copy_name = Symbol(:q_tag_, name)
            @test relative_difference(
                getproperty(Yₜ.c.sgsʲs.:(1), copy_name) .-
                getproperty(Yₜ_surface.c.sgsʲs.:(1), copy_name),
                share .* ᶜq_totʲₜ,
            ) < 1e-10
        end
    end

    # 3. The rain-out goes by each subdomain's composition (WP4a): the
    # copies' own shares in the updraft, the environment's in the
    # environment. Over the partition that is the model's sink, up to what
    # parts the copies' partition from `q_totʲ` and the grid partition from
    # `ρq_tot`. The tags' precipitation adds up to `pr` in the same way.
    @testset "The rain-out is split by subdomain" begin
        # The testsets above left the cache at other states.
        CA.set_precomputed_quantities!(Y, p, t)
        model = p.atmos.water_tagging_model
        @test CA.splits_rainout(p, :microphysics)
        @test !CA.splits_rainout(p, :surface_flux)
        (; ᶜΔʲ, ᶜΔ⁰, ᶜS, scale) = rainout_inputs(Y, p)
        # Both subdomains rain here, so no check below is vacuous.
        @test maximum(abs, parent(ᶜΔʲ)) > 0
        @test maximum(abs, parent(ᶜΔ⁰)) > 0
        parts = subdomain_parts(Y, p, model)
        ᶜincrements = CA._water_fix_fields(Y.c.ρ, model.tags)
        CA.add_rainout_increments!(ᶜincrements, Y, p, model)
        @test all(isfinite, parent(ᶜincrements.ρq_tag_tropo))
        (tropo, strat, evap) = model.tags
        partition(ᶜx) = ᶜx.ρq_tag_tropo .+ ᶜx.ρq_tag_strat
        for tag in model.tags
            # The parts add up to the split.
            @test same_to_rounding(
                CA.tag_field(ᶜincrements, tag),
                CA.tag_field(parts.updraft, tag) .+
                CA.tag_field(parts.environment, tag),
                scale,
            )
            # The updraft's part goes by the copy's own share of `q_totʲ`.
            @test same_to_rounding(
                CA.tag_field(parts.updraft, tag),
                ᶜΔʲ .*
                CA.water_tag_fraction.(
                    CA.updraft_copy_field(ᶜsgsʲ, tag),
                    ᶜsgsʲ.q_tot,
                ),
                scale,
            )
        end
        # The environment's part: the partition's shares sum to `S`, and they
        # are not the grid mean's, which the grid rule would take.
        @test same_to_rounding(partition(parts.environment), ᶜS .* ᶜΔ⁰, scale)
        ᶜgrid_share = CA.water_tag_fraction.(Y.c.ρq_tag_tropo, Y.c.ρq_tot)
        @test maximum(
            abs,
            parent(parts.environment.ρq_tag_tropo) .-
            parent(ᶜΔ⁰ .* ᶜgrid_share),
        ) > 1e-6 * scale
        # The tags' precipitation integrates the same increments, from one
        # batch per output time, which holds every tag's part.
        CA.update_water_tag_rainouts!(Y, p, t)
        tag_pr(tag, phase) = copy(
            CA.water_tag_precipitation!(
                similar(p.scratch.ᶠtemp_field_level),
                Y,
                p,
                t,
                tag,
                phase,
            ),
        )
        for tag in model.tags
            @test isapprox(
                parent(tag_pr(tag, Val(:all))),
                parent(column_integral(p, CA.tag_field(ᶜincrements, tag)));
                rtol = 1e-12,
            )
        end
        # A second diagnostic at the same time reads the batch and does not
        # redo the shared work: a changed rate shows only after a new batch.
        tropo_pr = tag_pr(tropo, Val(:all))
        ᶜdq⁰ = p.precomputed.ᶜmp_tendency⁰.dq_tot_dt
        saved⁰ = copy(ᶜdq⁰)
        ᶜdq⁰ .*= 2
        @test isequal(parent(tag_pr(tropo, Val(:all))), parent(tropo_pr))
        CA.update_water_tag_rainouts!(Y, p, t)
        @test !isapprox(parent(tag_pr(tropo, Val(:all))), parent(tropo_pr))
        ᶜdq⁰ .= saved⁰
        CA.update_water_tag_rainouts!(Y, p, t)
        @test isequal(parent(tag_pr(tropo, Val(:all))), parent(tropo_pr))

        pr = p.precomputed.surface_rain_flux .+ p.precomputed.surface_snow_flux
        prra = p.precomputed.surface_rain_flux
        @test maximum(abs, parent(pr)) > 0
        # Over the partition, `pr` less the rain-out the shares leave: the
        # copies' sum `Sʲ` in the updraft and the grid partition's `S` in the
        # environment. `pr_tag_res` is that part. DYCOMS is warm, so the rain
        # is all of it.
        ᶜSʲ = zero.(ᶜS)
        for tag in (tropo, strat)
            ᶜSʲ .+= CA.water_tag_fraction.(
                CA.updraft_copy_field(ᶜsgsʲ, tag),
                ᶜsgsʲ.q_tot,
            )
        end
        residual = CA.water_tag_precipitation_residual!(
            similar(p.scratch.ᶠtemp_field_level),
            Y,
            p,
            t,
        )
        column_scale =
            maximum(abs, parent(column_integral(p, abs.(ᶜΔʲ) .+ abs.(ᶜΔ⁰))))
        @test maximum(
            abs,
            parent(
                column_integral(p, ᶜΔʲ .* (1 .- ᶜSʲ) .+ ᶜΔ⁰ .* (1 .- ᶜS)) .-
                residual,
            ),
        ) <= 1e-12 * column_scale
        @test maximum(
            abs,
            parent(pr .- tag_pr(tropo, Val(:all)) .- tag_pr(strat, Val(:all)) .- residual),
        ) <= 1e-12 * column_scale
        @test maximum(
            abs,
            parent(
                prra .- tag_pr(tropo, Val(:rain)) .- tag_pr(strat, Val(:rain)) .- residual,
            ),
        ) <= 1e-12 * column_scale
        # The residual is not zero here: the copies' partition and the grid
        # partition have drifted apart from their parents in an hour.
        @test maximum(abs, parent(residual)) > 0
        @test all(iszero, parent(tag_pr(tropo, Val(:snow))))
        out = similar(p.scratch.ᶠtemp_field_level)
        CA.water_tag_precipitation!(out, Y, p, t, tropo, Val(:all))
        @test (@allocated CA.water_tag_precipitation!(
            out,
            Y,
            p,
            t,
            tropo,
            Val(:all),
        )) <= 64
        CA.update_water_tag_rainouts!(Y, p, t)
        @test (@allocated CA.update_water_tag_rainouts!(Y, p, t)) <= 64
        # The split on the implicit path allocates next to nothing.
        CA.add_rainout_increments!(ᶜincrements, Y, p, model)
        @test (@allocated CA.add_rainout_increments!(ᶜincrements, Y, p, model)) <= 64
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "pr_tag_tropo")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "prsn_tag_evap")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "pr_tag_res")
    end

    # 4. The model's own fields.
    plain = run_simulation(edmf_dict, "water_tags_edmf_0m_plain")
    Y_plain = plain.integrator.u
    @testset "The model's fields do not depend on the copies" begin
        test_same_model_fields(Y, Y_plain)
    end

    # 5. The default mode splits the rain-out by the exchange's shares. They
    # sum to the grid partition's share in each subdomain, so the partition's
    # part is the sink up to the partition's residual.
    @testset "The default mode splits the rain-out" begin
        default_dict = merge(edmf_dict, tag_dict)
        delete!(default_dict, "water_tag_updraft_copy")
        # The copies' diagnostics do not exist without copies.
        default_dict["diagnostics"] = [
            Dict{String, Any}(
                "short_name" => ["pr_tag_tropo", "prsn_tag_evap"],
                "period" => "10mins",
            ),
        ]
        default = run_simulation(default_dict, "water_tags_edmf_0m_default")
        Y_default = default.integrator.u
        p_default = default.integrator.p
        t_default = default.integrator.t
        CA.set_precomputed_quantities!(Y_default, p_default, t_default)
        model = p_default.atmos.water_tagging_model
        turbconv_model = p_default.atmos.turbconv_model
        @test !CA.has_water_tag_updraft_copies(model)
        # Under EDMF the default mode follows the implicit increment by
        # default (#102); the split does not depend on the transport.
        @test model.transport isa CA.IncrementWaterTagTransport
        @test CA.splits_rainout(p_default, :microphysics)
        (; ᶜΔʲ, ᶜΔ⁰, ᶜS, scale) = rainout_inputs(Y_default, p_default)
        @test maximum(abs, parent(ᶜΔʲ)) > 0
        @test maximum(abs, parent(ᶜΔ⁰)) > 0

        # The exchange's tendency, before and after the split has written the
        # exchange's scratch, is the same bit for bit.
        exchange() = (
            Yₜ = zero(Y_default);
            CA.sgs_exchange_of_water_tags!(
                Yₜ,
                Y_default,
                p_default,
                turbconv_model,
                model,
            );
            Yₜ
        )
        before = exchange()
        parts = subdomain_parts(Y_default, p_default, model)
        @test isequal(parent(exchange().c), parent(before.c))

        # Each subdomain's shares are the grid mean's, partition-normalized,
        # plus that subdomain's difference from the exchange, times `S`.
        inputs = CA.water_exchange_inputs!(
            Y_default,
            p_default,
            turbconv_model,
            model,
        )
        (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags) = inputs
        ᶜΔφ⁰ = CA.ShareDifferences(flags, true).(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
        ᶜΔφʲ = CA.ShareDifferences(flags, false).(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
        differs = false
        for (i, tag) in enumerate(model.tags)
            share = CA.SplitShare(flags, Val(i))
            ᶜφ̄ = CA.water_tag_fraction.(
                CA.tag_field(Y_default.c, tag),
                Y_default.c.ρq_tot,
            )
            ᶜφʲ = share.(ᶜε̄, ᶜΔφʲ, ᶜS, ᶜφ̄)
            ᶜφ⁰ = share.(ᶜε̄, ᶜΔφ⁰, ᶜS, ᶜφ̄)
            @test same_to_rounding(
                CA.tag_field(parts.updraft, tag),
                ᶜΔʲ .* ᶜφʲ,
                scale,
            )
            @test same_to_rounding(
                CA.tag_field(parts.environment, tag),
                ᶜΔ⁰ .* ᶜφ⁰,
                scale,
            )
            differs |= maximum(abs, parent(ᶜφʲ) .- parent(ᶜφ⁰)) > 1e-6
        end
        # The exchange acts here, so the two subdomains' shares differ.
        @test differs
        partition(ᶜx) = ᶜx.ρq_tag_tropo .+ ᶜx.ρq_tag_strat
        @test same_to_rounding(partition(parts.updraft), ᶜS .* ᶜΔʲ, scale)
        @test same_to_rounding(partition(parts.environment), ᶜS .* ᶜΔ⁰, scale)

        # At the surface, `pr` less the partition's `pr_tag` is `pr_tag_res`,
        # the rain-out times `1 - S`.
        (tropo, strat, _) = model.tags
        function surface_parts(Y_state)
            CA.update_water_tag_rainouts!(Y_state, p_default, t_default)
            tag_pr(tag) = copy(
                CA.water_tag_precipitation!(
                    similar(p_default.scratch.ᶠtemp_field_level),
                    Y_state,
                    p_default,
                    t_default,
                    tag,
                    Val(:all),
                ),
            )
            pr =
                p_default.precomputed.surface_rain_flux .+
                p_default.precomputed.surface_snow_flux
            residual = copy(
                CA.water_tag_precipitation_residual!(
                    similar(p_default.scratch.ᶠtemp_field_level),
                    Y_state,
                    p_default,
                    t_default,
                ),
            )
            return (; pr, tags = tag_pr(tropo) .+ tag_pr(strat), residual)
        end
        column_scale = maximum(
            abs,
            parent(column_integral(p_default, abs.(ᶜΔʲ) .+ abs.(ᶜΔ⁰))),
        )
        surface = surface_parts(Y_default)
        @test maximum(abs, parent(surface.pr .- surface.tags .- surface.residual)) <=
              1e-12 * column_scale
        @test maximum(
            abs,
            parent(
                surface.residual .-
                column_integral(p_default, (1 .- ᶜS) .* (ᶜΔʲ .+ ᶜΔ⁰)),
            ),
        ) <= 1e-12 * column_scale
        # With the partition closed, the region tags' `pr_tag` is `pr` to
        # rounding. The tags are set to a closed partition of the same
        # composition, and the state's own `pr` is recomputed.
        Y_closed = copy(Y_default)
        ᶜtropo_share = clamp.(Y_default.c.ρq_tag_tropo ./ Y_default.c.ρq_tot, 0, 1)
        Y_closed.c.ρq_tag_tropo .= ᶜtropo_share .* Y_default.c.ρq_tot
        Y_closed.c.ρq_tag_strat .= Y_default.c.ρq_tot .- Y_closed.c.ρq_tag_tropo
        CA.set_precomputed_quantities!(Y_closed, p_default, t_default)
        closed = surface_parts(Y_closed)
        @test maximum(abs, parent(closed.pr .- closed.tags)) <= 1e-12 * column_scale
        @test maximum(abs, parent(closed.residual)) <= 1e-12 * column_scale
        CA.set_precomputed_quantities!(Y_default, p_default, t_default)
        ᶜincrements = CA._water_fix_fields(Y_default.c.ρ, model.tags)
        CA.add_rainout_increments!(ᶜincrements, Y_default, p_default, model)
        # Julia 1.10 allocates 696 bytes here (CI, 2026-09-24), 1.11 at most
        # 64, as `energy_source_tags_integration.jl`'s split solve does.
        split_bytes = @allocated CA.add_rainout_increments!(
            ᶜincrements,
            Y_default,
            p_default,
            model,
        )
        @info "The default mode's split allocates" split_bytes
        @test split_bytes <= 64 broken = VERSION < v"1.11"
        test_same_model_fields(Y_default, Y_plain)
    end
end
