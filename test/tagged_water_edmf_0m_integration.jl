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
 3. the model's fields are those of the same column without tags, bit for bit.

The rain-out mirror runs on the implicit path here, where the 0M sink lives by
default. Its explicit hook is the same function; `tagging_water_edmf_copies`
runs 1M explicitly, where that hook is a no-op, for the parity of the explicit
path. See `docs/src/tagged_water.md`.
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
                "short_name" => ["q_tag_copy_res", "q_tag_leak_vdiff"],
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

    # 3. The model's own fields.
    @testset "The model's fields do not depend on the copies" begin
        plain = run_simulation(edmf_dict, "water_tags_edmf_0m_plain")
        Y_plain = plain.integrator.u
        is_tag(name) = startswith(string(name), "ρq_tag_")
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
end
