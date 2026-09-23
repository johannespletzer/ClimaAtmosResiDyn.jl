#=
Integration test for the water tags under prognostic EDMF, in the default mode
(`water_tag_updraft_copy: false`).

The tags have no updraft state. Each takes its share of the parent's sub-grid
mass flux of water, from the donor cell. An exchange of provenance at the
updraft's mass flux moves the updraft's own composition, from a plume rescaled
to the updraft's water, and sums to zero over the partition. This file checks,
on the DYCOMS RF02 EDMF column with 1-moment microphysics, after an hour:

 1. the partition stays closed;
 2. the partition's sub-grid tendencies sum to the parent's;
 3. with one composition everywhere, each tag takes exactly its share of the
    parent's sub-grid flux, and the exchange moves nothing;
 4. the vertical diffusion's leak, in closed form, is the difference the
    diffusion makes between the partition and the parent;
 5. the audit reports where the exchange's bound binds;
 6. the tags' sub-grid flux allocates next to nothing of its own;
 7. the model's fields are those of the same column without tags, bit for bit.

The check against the column without tags needs a second model type, so the
file builds the EDMF column twice and has a test group of its own. See
`docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

# One call to compile, then `@allocated` on a second call, inside a function
# that specializes on every argument.
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

# The largest absolute difference of two fields, relative to the largest
# absolute value of the second.
relative_difference(a, b) =
    maximum(abs, parent(a) .- parent(b)) / maximum(abs, parent(b))

@testset "Water tags under PrognosticEDMFX" begin
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a
    # single column with 1-moment microphysics, for an hour. It drizzles, so
    # the diffusion's leak is not zero.
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
    )
    tagged = run_simulation(merge(edmf_dict, tag_dict), "water_tags_edmf")
    Y = tagged.integrator.u
    p = tagged.integrator.p
    t = tagged.integrator.t
    model = p.atmos.water_tagging_model
    turbconv_model = p.atmos.turbconv_model
    @test !CA.has_water_tag_updraft_copies(model)
    @test !hasproperty(Y.c.sgsʲs.:(1), :q_tag_tropo)

    # 1. The partition stays closed, within bounds about twice what this column
    # gives after an hour on Julia 1.11: 3.5e-5 net and 5.4e-4 gross, relative
    # to the column's water. This test does not split that by cause; the
    # vertical diffusion's leak under 1M and the advection split are two
    # candidates (`docs/src/tagged_water.md`). The same column with grid-scale
    # tags only, which miss the sub-grid flux, gave 2.2e-2 gross after the hour
    # (FINDINGS W17), so the bound tells the two apart.
    @testset "The partition stays closed" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        @info "Water tags on the EDMF column after an hour" closure.relative closure.gross_relative
        @test abs(closure.relative) < 1e-4
        @test closure.gross_relative < 1e-3
        @test all(isfinite, parent(Y.c))
    end

    Yₜ_parent = zero(Y)
    CA.edmfx_sgs_mass_flux_tendency!(Yₜ_parent, Y, p, t, turbconv_model)
    ᶜparent_flux = Yₜ_parent.c.ρq_tot
    @test maximum(abs, parent(ᶜparent_flux)) > 0

    # 2. The donor shares are renormalized over the partition, and the exchange
    # sums to zero over it. So the partition's sub-grid tendencies add up to
    # the parent's, at rounding.
    @testset "The partition takes the parent's sub-grid flux" begin
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model)
        @test maximum(abs, parent(Yₜ.c.ρq_tag_evap)) > 0
        @test relative_difference(
            Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat,
            ᶜparent_flux,
        ) < 1e-12
    end

    # With one composition everywhere, the plume's is the grid mean's.
    shares = (; ρq_tag_tropo = 0.3, ρq_tag_strat = 0.7, ρq_tag_evap = 0.2)
    Y_uniform = copy(Y)
    for (name, share) in pairs(shares)
        getproperty(Y_uniform.c, name) .= share .* Y.c.ρq_tot
    end

    # 3. Each tag then takes exactly its share of the parent's flux, and the
    # exchange, which moves only a difference of composition, moves nothing.
    @testset "One composition moves as the parent" begin
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_water_tags!(Yₜ, Y_uniform, p, turbconv_model)
        for (name, share) in pairs(shares)
            @test relative_difference(
                getproperty(Yₜ.c, name),
                share .* ᶜparent_flux,
            ) < 1e-12
        end
    end

    # 4. The diffusion moves the tags at `K_h + K_e` on their whole value, and
    # the parent at `K_h` on the water without rain and snow. The closed form
    # is that difference.
    @testset "The vertical diffusion's leak in closed form" begin
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y_uniform, p, t, turbconv_model)
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:vdiff))
        @info "The vertical diffusion's leak on the EDMF column, kg/kg/s" maximum(
            abs,
            parent(ᶜleak),
        )
        @test maximum(abs, parent(ᶜleak)) > 0
        @test relative_difference(
            Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot,
            ᶜleak .* Y.c.ρ,
        ) < 1e-8
        # The paths this column does not have leak nothing.
        for path in (:hdiff, :hyperdiff, :sponge)
            CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(path))
            @test all(iszero, parent(ᶜleak))
        end
    end

    # 5. The audit's own columns.
    @testset "The audit reports the exchange's bound" begin
        audit = CA.water_tag_edmf_audit(Y, p, model, 1.0)
        @info "Where the exchange's bound binds" audit
        @test propertynames(audit) ==
              (:exchange_volume_fraction, :bound_partition, :bound_evap)
        @test 0 < audit.exchange_volume_fraction <= 1
        @test 0 <= audit.bound_partition <= 1
        @test 0 <= audit.bound_evap <= 1
    end

    # 6. The flux reads the environment's water through the parent's helper,
    # which broadcasts over a closure that Julia wraps in a `Ref`, as the
    # energy source tags' flux does.
    @testset "The tags' sub-grid flux does not allocate" begin
        Yₜ = zero(Y)
        @test second_call_allocations(
            CA.sgs_mass_flux_of_water_tags!,
            Yₜ,
            Y,
            p,
            turbconv_model,
        ) <= 64
    end

    # 7. The model's own fields. `isequal` tells signed zeros apart, which `==`
    # does not. See "Fork parity with upstream" in
    # `docs/clima_atmos_specific.md`.
    @testset "The model's fields do not depend on the tags" begin
        plain = run_simulation(edmf_dict, "water_tags_edmf_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
        is_tag(name) = startswith(string(name), "ρq_tag_")
        @test Set(filter(!is_tag, propertynames(Y.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
