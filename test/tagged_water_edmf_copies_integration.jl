#=
Integration test for `water_tag_updraft_copy: true`, the audit of the water
tags' mixing through the updrafts.

Each tag gets a copy in the updraft, `q_tag_<name>`, which the model moves as
any other updraft tracer. Five mirrors give the copies what the updraft's water
gets and a tracer does not: the 0M rain-out, the 1M sedimentation, the
relaxation at the surface, the surface flux and the repair after the filter. This file checks,
on the DYCOMS RF02 EDMF column with 1-moment microphysics, after an hour:

 1. the copies exist, and the rebuild sets them to `q_totʲ φ̄ᵢ`;
 2. the default mode's flux and exchange do nothing, and the model's SGS
    tracer flux moves the tags;
 3. the partition and the copies stay closed;
 4. with one composition everywhere, each copy's whole tendency is its share
    of `q_totʲ`'s, up to the diffusion's leak, whose closed form it checks, and
    up to the surface flux, whose new water goes by region and source. The
    partition's copies take all of the updraft's surface flux;
 5. the copies' own code allocates next to nothing;
 6. the model's fields are those of the same column without tags, bit for bit.

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
        # mean's share.
        Y_rebuilt = copy(Y)
        CA.rebuild_water_tag_updraft_copies!(Y_rebuilt, model, turbconv_model)
        @test isapprox(
            parent(Y_rebuilt.c.sgsʲs.:(1).q_tag_tropo),
            parent(ᶜsgsʲ.q_tot .* CA.water_tag_fraction.(Y.c.ρq_tag_tropo, Y.c.ρq_tot));
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
    # residual after the filter.
    @testset "The partition and the copies stay closed" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        audit = CA.water_tag_edmf_audit(Y, p, model, closure.scale)
        @info "Water tags with copies on the EDMF column after an hour" closure.relative closure.gross_relative audit
        @test abs(closure.relative) < 1e-10
        @test closure.gross_relative < 1e-8
        @test propertynames(audit) == (
            :copy_residual,
            :copy_residual_relative,
            :copy_repair,
            :copy_repair_relative,
        )
        @test audit.copy_residual_relative < 1e-8
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
        # The partition's copies take the updraft's whole surface flux.
        @test relative_difference(
            Yₜ_surface.c.sgsʲs.:(1).q_tag_tropo .+
            Yₜ_surface.c.sgsʲs.:(1).q_tag_strat,
            ᶜq_totʲₜ_surface,
        ) < 1e-12
        ᶜq_totʲₜ = Yₜ.c.sgsʲs.:(1).q_tot .- ᶜq_totʲₜ_surface
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:diffusion_up))
        @test maximum(abs, parent(ᶜleak)) > 0
        # The leak per unit mass of updraft air.
        ᶜleakʲ = ᶜleak .* Y.c.ρ ./ ᶜsgsʲ.ρa
        for (name, share) in pairs(shares)
            copy_name = Symbol(:q_tag_, name)
            ᶜχₜ =
                getproperty(Yₜ.c.sgsʲs.:(1), copy_name) .-
                getproperty(Yₜ_surface.c.sgsʲs.:(1), copy_name)
            @test relative_difference(ᶜχₜ, share .* (ᶜq_totʲₜ .+ ᶜleakʲ)) <
                  1e-10
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
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
