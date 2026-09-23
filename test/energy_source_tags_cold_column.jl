#=
Integration test for the energy source tags on a cold precipitating column.

Sedimentation moves energy between levels, and each face's flux is shared out by
the cell that loses the energy. Which cell that is depends on the sign of the
energy the falling water carries. Warm rain carries positive `E` and the donor
is the cell above. Ice well below freezing carries negative `E` against the
reference plus the offset, and then the donor is the cell *below*: the upward
branch of `sediment_energy_source_tags!`.

`PrecipitatingColumn` starts with cloud ice at 6 to 9 km and snow at 5 to 8 km,
so ice falls from the first step and that branch runs on a real state. Only a
set flux in a unit test had reached it before. This file checks, on a
1-moment column:

 1. every cell of falling ice carries negative `E`, so the branch is
    exercised;
 2. the partition's sedimentation tendency adds up to the parent's;
 3. with a step partition inside the ice layer, the lower tag gains above the
    step and the upper tag gains in no cell below it, which only the upward
    branch can do;
 4. a minute of the column runs, every tag stays finite and non-negative, and
    the partitioned total stays positive.

The first three are checked on the initial state. Most of the ice sublimates
within that minute, since the profile's air is below ice saturation aloft, and
after it nothing crosses the step (FINDINGS E41 of the tag-closure
experiments).

It is in the `tagging_source` group, which already builds a tagged column. The
experiments' `analysis/subgrid_check_cold.jl` is the wider version of this,
covering 2-moment schemes as well. See `docs/src/energy_source_tags.md`.
=#
using Test
import ClimaAtmos as CA

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 5000.0,
    "width" => 200.0,
    "above" => above,
)

@testset "Energy source tags on a cold precipitating column" begin
    c = 110495.0
    z_step = 6500.0
    config_dict = Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "PrecipitatingColumn",
        "surface_setup" => "DefaultMoninObukhov",
        "z_elem" => 100,
        "z_max" => 10000.0,
        "z_stretch" => false,
        "dt" => "10secs",
        "t_end" => "60secs",
        "cloud_model" => "grid_scale",
        "implicit_microphysics" => true,
        "microphysics_model" => "1M",
        "use_sgs_quadrature" => false,
        "vert_diff" => "DecayWithHeightDiffusion",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
        "energy_source_tags" => [
            Dict{String, Any}("name" => "upper", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "lower", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
        ],
        "energy_source_tag_offset" => c,
    )
    simulation = CA.get_simulation(
        CA.AtmosConfig(config_dict; job_id = "energy_source_tags_cold_column"),
    )
    Y = simulation.integrator.u
    p = simulation.integrator.p
    t = simulation.integrator.t
    FT = eltype(Y)
    CA.set_precomputed_quantities!(Y, p, t)
    ᶜz = CA.Fields.coordinate_field(Y.c).z
    ᶜE = @. Y.c.ρe_tot + c * Y.c.ρ

    # The branch is checked on the initial state. Most of the ice sublimates
    # within the minute, since the profile's air is below ice saturation aloft,
    # and after it nothing crosses the step.
    @testset "Falling ice makes the cell below the donor" begin
        # 1. Falling ice carries negative `E` per unit mass, which is what
        # makes the cell below the donor.
        thermo_params = CA.Parameters.thermodynamics_params(p.params)
        (; ᶜT) = p.precomputed
        (; ᶜΦ) = p.core
        ᶜe_ice = @. CA.TD.internal_energy_ice(thermo_params, ᶜT) + ᶜΦ + c
        ᶜice = Y.c.ρq_sno .+ Y.c.ρq_icl
        falling = parent(ᶜice) .> 1e-9 .* parent(Y.c.ρ)
        @test count(falling) > 0
        @test all(parent(ᶜe_ice)[falling] .< 0)

        # 2. The partition's sedimentation tendency is the parent's.
        Yₜ = zero(Y)
        CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
        ᶜE_tendency = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
        ᶜpartition_tendency = @. Yₜ.c.ρe_src_upper + Yₜ.c.ρe_src_lower
        scale = maximum(abs, parent(ᶜE_tendency))
        @test scale > 0
        @test maximum(
            abs,
            parent(ᶜpartition_tendency) .- parent(ᶜE_tendency),
        ) < 100 * eps(FT) * scale

        # 3. A step partition inside the ice layer. Under the downward branch
        # alone the lower tag could never gain above the step.
        Y_step = copy(Y)
        @. Y_step.c.ρe_src_upper = ifelse(ᶜz > z_step, ᶜE, FT(0))
        @. Y_step.c.ρe_src_lower = ᶜE - Y_step.c.ρe_src_upper
        Yₜ_step = zero(Y_step)
        CA.vertical_advection_of_water_tendency!(Yₜ_step, Y_step, p, t)
        above = parent(ᶜz) .> z_step
        lower = parent(Yₜ_step.c.ρe_src_lower)
        upper = parent(Yₜ_step.c.ρe_src_upper)
        @test count(!iszero, lower[above]) > 0
        @test all(iszero, upper[.!above])
        ᶜE_tendency_step = @. Yₜ_step.c.ρe_tot + c * Yₜ_step.c.ρ
        step_scale = maximum(abs, parent(ᶜE_tendency_step))
        @test maximum(abs, upper .+ lower .- parent(ᶜE_tendency_step)) <
              100 * eps(FT) * step_scale
    end

    # A minute of it, with the repair on.
    @testset "The column runs and the tags stay sound" begin
        @test CA.solve_atmos!(simulation).ret_code == :success
        Y = simulation.integrator.u
        ᶜE_end = @. Y.c.ρe_tot + c * Y.c.ρ
        for name in (:ρe_src_upper, :ρe_src_lower, :ρe_src_sfc)
            ᶜtag = getproperty(Y.c, name)
            @test all(isfinite, parent(ᶜtag))
            @test minimum(parent(ᶜtag)) >= 0
        end
        # The offset keeps the partitioned total positive, so every share is
        # defined.
        @test minimum(parent(ᶜE_end)) > 0
        # The tags ride the plain tracer path here, so the residual is the
        # transport mismatch, not rounding. It stays far below the total.
        ᶜresidual = @. ᶜE_end - Y.c.ρe_src_upper - Y.c.ρe_src_lower
        @test sum(abs.(ᶜresidual)) < 1e-2 * sum(abs.(ᶜE_end))
    end
end
