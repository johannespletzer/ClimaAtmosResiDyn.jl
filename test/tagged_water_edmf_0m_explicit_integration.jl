#=
Integration test for the 0M rain-out split by EDMF subdomain (WP4a) with the
microphysics stepped explicitly.

There the split runs from `remaining_tendency!`, in the `:microphysics`
bracket that `open_applied_update!` and `close_applied_update!` put around the
microphysics. This file checks, on the DYCOMS RF02 EDMF column with 0-moment
microphysics as `tagged_water_edmf_0m_integration.jl` runs it, but with
`implicit_microphysics: false`, in the default mode and with updraft copies,
after an hour:

 1. the bracket gives the tags the split, and the parent the two subdomains'
    rain-out;
 2. each subdomain gives each region tag a part, and the partition's parts are
    the sink times the partition's sum of shares in each subdomain, to
    rounding. `pr` less the partition's `pr_tag` is `pr_tag_res`;
 3. the model's fields are those of the same column without tags, bit for bit.

The file compiles the EDMF column three times, so it has its own test group.
See `docs/src/tagged_water.md`.
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

function test_same_model_fields(Y, Y_plain)
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

# To rounding against the rain-out: the split is a sum of a few products per
# cell, so the identities below hold to a few eps of the largest rate.
same_to_rounding(a, b, scale) =
    maximum(abs, parent(a) .- parent(b)) <= 100 * eps(Float64) * scale

# The `:microphysics` bracket of `remaining_tendency!`, on its own.
function explicit_microphysics_bracket(Y, p, t)
    Yₜ = zero(Y)
    CA.open_applied_update!(Yₜ, p, :microphysics)
    CA.microphysics_tendency!(
        Yₜ,
        Y,
        p,
        t,
        p.atmos.microphysics_model,
        p.atmos.turbconv_model,
    )
    CA.water_tag_copies_microphysics_tendency!(
        Yₜ,
        Y,
        p,
        p.atmos.microphysics_model,
        p.atmos.turbconv_model,
    )
    CA.close_applied_update!(Yₜ, Y, p, :microphysics)
    return Yₜ
end

# Each subdomain's part of the split, from the real code: the split with the
# other subdomain's cached rate set to zero.
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

column_integral(p, ᶜx) = (
    out = similar(p.scratch.ᶠtemp_field_level);
    CA.Operators.column_integral_definite!(out, ᶜx);
    out
)

@testset "The 0M rain-out split, microphysics explicit" begin
    explicit_dict = Dict{String, Any}(
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
        "implicit_microphysics" => false,
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
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => ["pr_tag_tropo", "prra_tag_strat", "pr_tag_res"],
                "period" => "10mins",
            ),
        ],
    )
    plain = run_simulation(explicit_dict, "water_tags_0m_explicit_plain")
    Y_plain = plain.integrator.u

    for (mode, extra) in (
        ("default mode", Dict{String, Any}()),
        ("copies", Dict{String, Any}("water_tag_updraft_copy" => true)),
    )
        @testset "$mode" begin
            simulation = run_simulation(
                merge(explicit_dict, tag_dict, extra),
                "water_tags_0m_explicit_$(replace(mode, " " => "_"))",
            )
            Y = simulation.integrator.u
            p = simulation.integrator.p
            t = simulation.integrator.t
            model = p.atmos.water_tagging_model
            @test CA.has_water_tag_updraft_copies(model) == (mode == "copies")
            @test p.atmos.microphysics_tendency_timestepping == CA.Explicit()
            @test CA.splits_rainout(p, :microphysics)
            CA.set_precomputed_quantities!(Y, p, t)

            ᶜΔʲ = copy(CA._rainout_updraft(Y, p))
            ᶜΔ⁰ = copy(CA._rainout_environment(Y, p))
            scale = maximum(abs, parent(ᶜΔʲ)) + maximum(abs, parent(ᶜΔ⁰))
            @test maximum(abs, parent(ᶜΔʲ)) > 0
            @test maximum(abs, parent(ᶜΔ⁰)) > 0
            CA.water_tag_share_norm!(p, Y)
            ᶜS = copy(p.scratch.ᶜtagging_q_share_norm)
            ᶜsgsʲ = Y.c.sgsʲs.:(1)
            # The updraft's sum of the partition's shares: `S` in the default
            # mode, the copies' own sum with copies.
            ᶜSʲ = copy(ᶜS)
            if mode == "copies"
                ᶜSʲ .= 0
                for tag in model.tags
                    CA._is_partition_tag(tag) || continue
                    ᶜSʲ .+= CA.water_tag_fraction.(
                        CA.updraft_copy_field(ᶜsgsʲ, tag),
                        ᶜsgsʲ.q_tot,
                    )
                end
            end

            # 1. The bracket gives the tags the split and the parent the sink.
            ᶜincrements = CA._water_fix_fields(Y.c.ρ, model.tags)
            CA.add_rainout_increments!(ᶜincrements, Y, p, model)
            Yₜ = explicit_microphysics_bracket(Y, p, t)
            @test same_to_rounding(Yₜ.c.ρq_tot, ᶜΔʲ .+ ᶜΔ⁰, scale)
            for tag in model.tags
                @test same_to_rounding(
                    CA.tag_field(Yₜ.c, tag),
                    CA.tag_field(ᶜincrements, tag),
                    scale,
                )
            end

            # 2. Each subdomain gives each region tag a part, and the
            # partition's parts are the sink times its sum of shares.
            parts = subdomain_parts(Y, p, model)
            partition(ᶜx) = ᶜx.ρq_tag_tropo .+ ᶜx.ρq_tag_strat
            for tag in model.tags
                CA._is_partition_tag(tag) || continue
                @test maximum(abs, parent(CA.tag_field(parts.updraft, tag))) > 0
                @test maximum(abs, parent(CA.tag_field(parts.environment, tag))) > 0
            end
            @test same_to_rounding(partition(parts.updraft), ᶜSʲ .* ᶜΔʲ, scale)
            @test same_to_rounding(partition(parts.environment), ᶜS .* ᶜΔ⁰, scale)
            # At the surface: `pr` less the partition's `pr_tag` is
            # `pr_tag_res`, and is the sink's part the shares leave.
            CA.update_water_tag_rainouts!(Y, p, t)
            tag_pr(tag) = copy(
                CA.water_tag_precipitation!(
                    similar(p.scratch.ᶠtemp_field_level),
                    Y,
                    p,
                    t,
                    tag,
                    Val(:all),
                ),
            )
            (tropo, strat, _) = model.tags
            pr = p.precomputed.surface_rain_flux .+ p.precomputed.surface_snow_flux
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
                parent(pr .- tag_pr(tropo) .- tag_pr(strat) .- residual),
            ) <= 1e-12 * column_scale
            expected = column_integral(
                p,
                ᶜΔʲ .* (1 .- ᶜSʲ) .+ ᶜΔ⁰ .* (1 .- ᶜS),
            )
            @test maximum(abs, parent(residual .- expected)) <=
                  1e-12 * column_scale

            # 3. The model's fields.
            test_same_model_fields(Y, Y_plain)
        end
    end
end
