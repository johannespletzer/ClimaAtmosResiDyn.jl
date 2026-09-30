#=
Unit tests for `water_tag_rainout_jacobian` (known issue 4, WP4a-J).

Under 0M microphysics stepped implicitly each water tag loses `min(Δ, 0) φ` in
the `:microphysics` bracket, with `Δ = ρ dq_tot_dt` and `φ` its clamped share.
The switch gives each tag's row of the manual Jacobian that loss's derivative
in the tag, on its diagonal, and in `ρq_tot`, in a block to `ρq_tot`'s column.
The blocks are built here from the real update on a small column and checked
against finite differences of the tags' real rain-out tendency
(`_accumulate_water_tags!`), where the partition has drifted and clamps bind.
The configurations where the switch does nothing, and its refusals, are
checked too. `tagged_water_rainout_jacobian_integration.jl` checks it in a run.
=#
using Test
import ClimaAtmos as CA

const CC = CA.ClimaCore
const MF = CA.MatrixFields

@testset "The share's derivatives" begin
    for FT in (Float32, Float64)
        ρq_tot = FT(0.012)
        for ρq_tag in (FT(0), FT(0.003), FT(0.012))
            @test CA.water_tag_fraction_derivative_tag(ρq_tag, ρq_tot) ==
                  inv(ρq_tot)
            @test CA.water_tag_fraction_derivative_parent(ρq_tag, ρq_tot) ≈
                  -ρq_tag / ρq_tot^2
        end
        # Where the clamp binds, or there is no water, the share does not move.
        for (ρq_tag, ρq_tot) in (
            (FT(0.02), FT(0.012)),
            (FT(-0.001), FT(0.012)),
            (FT(0.003), FT(0)),
            (FT(0.003), FT(-0.001)),
            (FT(0), FT(0)),
        )
            @test CA.water_tag_fraction_derivative_tag(ρq_tag, ρq_tot) === zero(FT)
            @test CA.water_tag_fraction_derivative_parent(ρq_tag, ρq_tot) ===
                  zero(FT)
        end
    end
    # Central differences of the share itself, away from the clamps.
    h = 1e-7
    for (ρq_tag, ρq_tot) in ((0.004, 0.011), (0.0005, 0.02), (0.018, 0.019))
        φ(tag, tot) = CA.water_tag_fraction(tag, tot)
        dtag =
            (φ(ρq_tag + h * ρq_tag, ρq_tot) - φ(ρq_tag - h * ρq_tag, ρq_tot)) /
            (2 * h * ρq_tag)
        dtot =
            (φ(ρq_tag, ρq_tot + h * ρq_tot) - φ(ρq_tag, ρq_tot - h * ρq_tot)) /
            (2 * h * ρq_tot)
        @test CA.water_tag_fraction_derivative_tag(ρq_tag, ρq_tot) ≈ dtag rtol = 1e-7
        @test CA.water_tag_fraction_derivative_parent(ρq_tag, ρq_tot) ≈ dtot rtol =
            1e-7
    end
end

# A 0M column with three tags: a drifted partition of two region tags and a
# source tag. Clamps bind in three cells, one cell holds no water, and in one
# cell the rain-out is a gain, which reaches the tags by their masks alone.
function rainout_column(
    FT;
    rainout_jacobian = true,
    microphysics_model = CA.EquilibriumMicrophysics0M(),
    microphysics_tendency_timestepping = CA.Implicit(),
    turbconv_model = nothing,
)
    column(staggering) = CC.CommonSpaces.ColumnSpace(
        FT;
        z_min = 0,
        z_max = 2000,
        z_elem = 16,
        staggering,
    )
    ᶜspace = column(CC.CommonSpaces.CellCenter())
    ᶠspace = column(CC.CommonSpaces.CellFace())
    ᶜz = CC.Fields.coordinate_field(ᶜspace).z
    region(above) = CA.TanhAltitudeRegion(FT(750), FT(100), above)
    tags = (
        CA.WaterTag{:tropo}(region(false)),
        CA.WaterTag{:strat}(region(true)),
        CA.WaterTag{:evap}(nothing, :surface_flux),
    )
    model = CA.WaterTaggingModel(tags; rainout_jacobian)
    ᶜnames = (:ρ, :ρe_tot, :ρq_tot, :ρq_tag_tropo, :ρq_tag_strat, :ρq_tag_evap)
    Y = CC.Fields.FieldVector(;
        c = similar(
            CC.Fields.coordinate_field(ᶜspace),
            NamedTuple{ᶜnames, NTuple{length(ᶜnames), FT}},
        ),
        f = similar(
            CC.Fields.coordinate_field(ᶠspace),
            NamedTuple{(:u₃,), Tuple{FT}},
        ),
    )
    fill!(parent(Y.f), 0)
    @. Y.c.ρ = FT(1.2) * exp(-(ᶜz) / 8000)
    @. Y.c.ρe_tot = Y.c.ρ * FT(2.5e5)
    @. Y.c.ρq_tot = Y.c.ρ * (FT(0.012) - FT(4e-6) * ᶜz)
    ᶜbelow = @. (1 - tanh((ᶜz - 750) / 100)) / 2
    # A drifted partition: `tropo` holds 10% too much, `strat` 5% too little.
    @. Y.c.ρq_tag_tropo = FT(1.1) * ᶜbelow * Y.c.ρq_tot
    @. Y.c.ρq_tag_strat = FT(0.95) * (1 - ᶜbelow) * Y.c.ρq_tot
    @. Y.c.ρq_tag_evap = FT(0.3) * Y.c.ρq_tot
    ρq_tot = parent(Y.c.ρq_tot)
    parent(Y.c.ρq_tag_tropo)[2] = FT(1.5) * ρq_tot[2]
    parent(Y.c.ρq_tag_evap)[5] = FT(1.2) * ρq_tot[5]
    parent(Y.c.ρq_tag_evap)[9] = FT(-0.1) * ρq_tot[9]
    ρq_tot[12] = 0
    ᶜmp_tendency = similar(
        Y.c.ρ,
        NamedTuple{(:dq_tot_dt, :e_tot_hlpr), NTuple{2, FT}},
    )
    @. ᶜmp_tendency.dq_tot_dt = -FT(2e-6) * (1 + sin(ᶜz / 300))
    @. ᶜmp_tendency.e_tot_hlpr = FT(1e4)
    parent(ᶜmp_tendency.dq_tot_dt)[7] = FT(1e-6)
    atmos = (;
        microphysics_model,
        microphysics_tendency_timestepping,
        turbconv_model,
        water_tagging_model = model,
    )
    p = (; atmos, precomputed = (; ᶜmp_tendency))
    ᶜmasks = (; ρq_tag_tropo = ᶜbelow, ρq_tag_strat = @. 1 - ᶜbelow)
    return (; Y, p, tags, ᶜmasks)
end

# The tags' rain-out tendency, as the `:microphysics` bracket computes it under
# 0M without prognostic EDMF.
function rainout_tendencies(Y, p, tags, ᶜmasks)
    ᶜYₜ = CA._water_fix_fields(Y.c.ρ, tags)
    ᶜΔ = @. Y.c.ρ * p.precomputed.ᶜmp_tendency.dq_tot_dt
    CA._accumulate_water_tags!(
        ᶜYₜ,
        Y.c,
        ᶜmasks,
        ᶜΔ,
        :microphysics,
        tags,
        Y.c.ρq_tot,
    )
    return ᶜYₜ
end

c(name) = MF.FieldName(:c, name)
const tag_names = (:ρq_tag_tropo, :ρq_tag_strat, :ρq_tag_evap)

@testset "The tags' rain-out blocks, assembled" begin
    for FT in (Float32, Float64)
        (; Y, p, tags, ᶜmasks) = rainout_column(FT)
        split = CA.UseDerivative()
        pairs = CA.water_tag_rainout_jacobian_blocks(Y, p.atmos, split)
        @test Set(map(pair -> pair.first, pairs)) == Set((
            map(name -> (c(name), c(name)), tag_names)...,
            map(name -> (c(name), c(:ρq_tot)), tag_names)...,
        ))
        matrix = MF.FieldMatrix(pairs...)
        dtγ = FT(35)
        (; ρq_tot) = Y.c
        ᶜz = CC.Fields.coordinate_field(Y.c).z
        ᶜloss = @. min(Y.c.ρ * p.precomputed.ᶜmp_tendency.dq_tot_dt, 0)

        # With explicit diffusion nothing else writes a tag's diagonal, so the
        # update starts it at `-I`. What was in the block does not survive.
        for name in tag_names
            fill!(parent(matrix[c(name), c(name)]), NaN)
            fill!(parent(matrix[c(name), c(:ρq_tot)]), NaN)
        end
        explicit = CA.IgnoreDerivative()
        CA.update_water_tag_rainout_jacobian!(matrix, Y, p, dtγ, explicit, split)
        # A second update gives the same blocks: nothing accumulates.
        once = map(name -> copy(parent(matrix[c(name), c(name)])), tag_names)
        CA.update_water_tag_rainout_jacobian!(matrix, Y, p, dtγ, explicit, split)
        for (name, block) in zip(tag_names, once)
            @test isequal(parent(matrix[c(name), c(name)]), block)
        end

        # The diagonal is `-I` plus the loss's derivative in the tag, and the
        # block to `ρq_tot` the loss's derivative in `ρq_tot`, both by `dtγ`.
        for name in tag_names
            ᶜρq_tag = getproperty(Y.c, name)
            diagonal = matrix[c(name), c(name)]
            cross = matrix[c(name), c(:ρq_tot)]
            ᶜv = @. ρq_tot * (1 + sin(ᶜz / 170)) / 2
            ᶜexpected_diagonal = @. -(ᶜv) +
               dtγ * ᶜloss * CA.water_tag_fraction_derivative_tag(ᶜρq_tag, ρq_tot) * ᶜv
            ᶜexpected_cross = @. dtγ * ᶜloss *
               CA.water_tag_fraction_derivative_parent(ᶜρq_tag, ρq_tot) * ᶜv
            ᶜdiagonal_v = @. diagonal * ᶜv
            ᶜcross_v = @. cross * ᶜv
            scale = maximum(abs, parent(ᶜv))
            @test maximum(
                abs,
                parent(ᶜdiagonal_v) .- parent(ᶜexpected_diagonal),
            ) <= 10 * eps(FT) * scale
            @test maximum(abs, parent(ᶜcross_v) .- parent(ᶜexpected_cross)) <=
                  10 * eps(FT) * scale
            # The entries are live below the clamp, and zero where it binds,
            # where there is no water, and where the rain-out is a gain.
            @test maximum(abs, parent(ᶜcross_v)) > 0
            @test all(iszero, parent(ᶜcross_v)[[7, 12]])
        end
        @test iszero(parent(matrix[c(:ρq_tag_tropo), c(:ρq_tot)])[2])
        @test iszero(parent(matrix[c(:ρq_tag_evap), c(:ρq_tot)])[5])
        @test iszero(parent(matrix[c(:ρq_tag_evap), c(:ρq_tot)])[9])

        # With implicit diffusion `update_diffusion_jacobian!` has assigned the
        # diagonal, and the entry adds to it.
        implicit = CA.UseDerivative()
        ᶜdiffusion = similar(Y.c.ρ, MF.TridiagonalMatrixRow{FT})
        diffusion_values = reshape(parent(ᶜdiffusion), 16, 3)
        diffusion_values .= FT(0.01) .* sin.(reshape(1:48, 16, 3))
        diffusion_values[:, 2] .-= 1
        # The entries outside the column.
        diffusion_values[1, 1] = 0
        diffusion_values[end, 3] = 0
        for name in tag_names
            matrix[c(name), c(name)] .= ᶜdiffusion
        end
        CA.update_water_tag_rainout_jacobian!(matrix, Y, p, dtγ, implicit, split)
        for name in tag_names
            ᶜρq_tag = getproperty(Y.c, name)
            added = reshape(parent(matrix[c(name), c(name)]), 16, 3)
            @test isequal(added[:, [1, 3]], diffusion_values[:, [1, 3]])
            ᶜentry = @. dtγ * ᶜloss *
                        CA.water_tag_fraction_derivative_tag(ᶜρq_tag, ρq_tot)
            @test added[:, 2] ≈ diffusion_values[:, 2] .+ vec(parent(ᶜentry)) rtol =
                10 * eps(FT)
        end

        # Each block is the derivative of the tags' real rain-out tendency: in
        # the tag for the diagonal, and in `ρq_tot` for the block to it, with
        # `Δ` fixed, as the solve holds `dq_tot_dt`. Central differences, so
        # Float64 only. The steps stay inside the clamps: each is proportional
        # to what it moves, so a share near zero does not cross it.
        FT == Float64 || continue
        # The explicit form again, whose diagonal is `-I` plus the entry.
        CA.update_water_tag_rainout_jacobian!(matrix, Y, p, dtγ, explicit, split)
        h = 1e-6
        # The tag's tendency after a step `± h ᶜv` in the field `name`.
        function stepped(name, ᶜv, sign)
            moved = deepcopy(Y)
            ᶜmoved = getproperty(moved.c, name)
            @. ᶜmoved += sign * h * ᶜv
            return rainout_tendencies(moved, p, tags, ᶜmasks)
        end
        central(ᶜplus, ᶜminus) = @. dtγ * (ᶜplus - ᶜminus) / (2 * h)
        for name in tag_names
            ᶜρq_tag = getproperty(Y.c, name)
            ᶜv = @. ᶜρq_tag * (1 + sin(ᶜz / 170)) / 2
            ᶜexpected = central(
                getproperty(stepped(name, ᶜv, 1), name),
                getproperty(stepped(name, ᶜv, -1), name),
            )
            # The block holds `dtγ ∂T/∂Y - I`.
            block = matrix[c(name), c(name)]
            ᶜJv = @. block * ᶜv + ᶜv
            scale = maximum(abs, parent(ᶜJv))
            @test scale > 0
            @test maximum(abs, parent(ᶜJv) .- parent(ᶜexpected)) <= 1e-7 * scale
        end
        ᶜv = @. ρq_tot * (1 + cos(ᶜz / 230)) / 2
        (plus, minus) = (stepped(:ρq_tot, ᶜv, 1), stepped(:ρq_tot, ᶜv, -1))
        for name in tag_names
            ᶜexpected = central(getproperty(plus, name), getproperty(minus, name))
            block = matrix[c(name), c(:ρq_tot)]
            ᶜJv = @. block * ᶜv
            scale = maximum(abs, parent(ᶜJv))
            @test scale > 0
            @test maximum(abs, parent(ᶜJv) .- parent(ᶜexpected)) <= 1e-7 * scale
        end
    end
end

@testset "Where the switch does nothing" begin
    FT = Float64
    split = CA.UseDerivative()
    unsplit = CA.IgnoreDerivative()
    blocks(setup, flag) =
        CA.water_tag_rainout_jacobian_blocks(setup.Y, setup.p.atmos, flag)
    on = rainout_column(FT)
    @test CA.uses_water_tag_rainout_jacobian(on.p.atmos, split)
    @test length(blocks(on, split)) == 6
    # Off, without the split solver (`use_auto_jacobian`), under 1M, on the
    # explicit path, and under prognostic EDMF, no blocks exist.
    for setup in (
        rainout_column(FT; rainout_jacobian = false),
        rainout_column(FT; microphysics_model = CA.NonEquilibriumMicrophysics1M()),
        rainout_column(FT; microphysics_tendency_timestepping = CA.Explicit()),
        rainout_column(
            FT;
            turbconv_model = CA.PrognosticEDMFX{1, false}(FT(0.5)),
        ),
    )
        @test !CA.uses_water_tag_rainout_jacobian(setup.p.atmos, split)
        @test blocks(setup, split) == ()
        @test CA.water_tag_rainout_jacobian_names(setup.p.atmos, split) == ()
    end
    @test !CA.uses_water_tag_rainout_jacobian(on.p.atmos, unsplit)
    @test blocks(on, unsplit) == ()
    # Without water tags the switch is off.
    @test !CA.has_water_tag_rainout_jacobian(nothing)
    @test !CA.has_water_tag_rainout_jacobian(CA.WaterTaggingModel(on.tags))
    @test CA.has_water_tag_rainout_jacobian(on.p.atmos.water_tagging_model)
    # Where it does nothing, the update touches no block.
    off = rainout_column(FT; rainout_jacobian = false)
    matrix = MF.FieldMatrix(blocks(on, split)...)
    for name in tag_names
        fill!(parent(matrix[c(name), c(name)]), NaN)
    end
    CA.update_water_tag_rainout_jacobian!(matrix, off.Y, off.p, FT(35), unsplit, split)
    CA.update_water_tag_rainout_jacobian!(matrix, on.Y, on.p, FT(35), unsplit, unsplit)
    for name in tag_names
        @test all(isnan, parent(matrix[c(name), c(name)]))
    end
end

@testset "The key and its refusals" begin
    @test CA.tag_ledger_per_tag_from_config(true, "water_tag_rainout_jacobian")
    @test !CA.tag_ledger_per_tag_from_config(false, "water_tag_rainout_jacobian")
    @test_throws r"`water_tag_rainout_jacobian` must be `true` or `false`" CA.tag_ledger_per_tag_from_config(
        "yes",
        "water_tag_rainout_jacobian",
    )
    check = CA.check_water_tag_rainout_jacobian_supported
    @test isnothing(check(Dict{String, Any}()))
    @test isnothing(check(Dict{String, Any}("turbconv" => "diagnostic_edmfx")))
    @test isnothing(check(Dict{String, Any}("turbconv" => "edonly_edmfx")))
    @test_throws r"refused under `turbconv: prognostic_edmfx`" check(
        Dict{String, Any}("turbconv" => "prognostic_edmfx"),
    )

    # Through the configuration.
    tags = [
        Dict{String, Any}(
            "name" => "low",
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 750.0,
                "width" => 100.0,
                "above" => false,
            ),
        ),
    ]
    config(extra) = CA.AtmosConfig(
        merge(
            Dict{String, Any}(
                "config" => "column",
                "microphysics_model" => "0M",
                "output_default_diagnostics" => false,
            ),
            extra,
        );
        job_id = "water_tag_rainout_jacobian_key",
    )
    tagging(extra) = CA.AtmosTagging(config(extra))
    on = Dict{String, Any}("water_tracers" => tags, "water_tag_rainout_jacobian" => true)
    @test CA.has_water_tag_rainout_jacobian(tagging(on).water_tagging_model)
    @test !CA.has_water_tag_rainout_jacobian(
        tagging(Dict{String, Any}("water_tracers" => tags)).water_tagging_model,
    )
    @test_throws r"`water_tag_rainout_jacobian: true` is set but `water_tracers` is not" tagging(
        Dict{String, Any}("water_tag_rainout_jacobian" => true),
    )
    @test_throws r"refused under `turbconv: prognostic_edmfx`" tagging(
        merge(on, Dict{String, Any}("turbconv" => "prognostic_edmfx")),
    )
    # Accepted where it does nothing.
    @test CA.has_water_tag_rainout_jacobian(
        tagging(merge(on, Dict{String, Any}("implicit_microphysics" => false))).water_tagging_model,
    )
end
