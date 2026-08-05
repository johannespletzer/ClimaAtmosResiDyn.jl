using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaCore: Fields

const FT = Float64

# ===========================================================================
# WMO lapse-rate tropopause
#
# Exercised on synthetic single columns, where the answer is known from the
# temperature profile, rather than on a simulation.
# ===========================================================================

"""
Center-space temperature field of a single column, from a pointwise profile.
"""
function column_temperature(profile; z_elem = 60, z_max = 30_000)
    grid = CA.ColumnGrid(FT; z_elem, z_max, z_stretch = false)
    center_space = CA.get_spaces(grid).center_space
    ᶜz = Fields.coordinate_field(center_space).z
    return profile.(ᶜz)
end

function diagnosed_tropopause(ᶜT)
    ᶜz_tropopause = similar(ᶜT)
    ᶜscratch = similar(ᶜT)
    CA.set_tropopause_height!(
        ᶜz_tropopause,
        ᶜscratch,
        ᶜT,
        CA.TropopauseParameters{FT}(),
    )
    heights = unique(parent(ᶜz_tropopause))
    # The height must be the same at every level of the column.
    @test length(heights) == 1
    return only(heights)
end

@testset "WMO lapse-rate tropopause" begin
    # 6.5 K/km up to an isothermal stratosphere starting at 10977 m.
    standard(z) = max(FT(288) - FT(0.0065) * z, FT(216.65))
    z_tropopause = diagnosed_tropopause(column_temperature(standard))
    # The diagnosis lands on a model level, so it can be off by up to one
    # layer (500 m here) from the analytic value.
    @test abs(z_tropopause - 10_977) < 600

    # A 1 km isothermal layer at 8 km satisfies the lapse-rate criterion but
    # not the 2 km consistency check, so it must be skipped in favour of the
    # real tropopause at 15 km.
    function inversion(z)
        z < 8_000 && return FT(288) - FT(0.0065) * z
        z < 9_000 && return FT(236)
        z < 15_000 && return FT(236) - FT(0.0065) * (z - 9_000)
        return FT(197)
    end
    z_tropopause = diagnosed_tropopause(column_temperature(inversion))
    @test abs(z_tropopause - 15_000) < 600

    # A column that never stops cooling has no tropopause; the fallback fills
    # it in rather than leaving a zero, which would put the whole column in
    # the tracers' removal region.
    no_tropopause(z) = FT(288) - FT(0.0065) * z
    z_tropopause = diagnosed_tropopause(column_temperature(no_tropopause))
    @test z_tropopause == FT(CA.DEFAULT_TROPOPAUSE_HEIGHT)

    # Inversions below `search_min_height` must not be mistaken for the
    # tropopause: a strong surface inversion under an otherwise standard
    # profile still gives the standard answer.
    function surface_inversion(z)
        z < 1_000 && return FT(280) + FT(0.008) * z
        return max(FT(288) - FT(0.0065) * (z - 1_000), FT(216.65))
    end
    z_tropopause = diagnosed_tropopause(column_temperature(surface_inversion))
    @test z_tropopause > 10_000
end

# ===========================================================================
# Source-region grid
# ===========================================================================

@testset "stratospheric tracer source regions" begin
    chemistry_model = CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 6,
        n_height_bands = 8,
        band_depth = 5_000,
    )

    @test CA.n_latitude_bands(chemistry_model) == 6
    @test CA.n_height_bands(chemistry_model) == 8
    @test CA.n_tracers(chemistry_model) == 48

    # The bands tile latitude and height: each upper edge is the next lower
    # edge, and the outermost edges are infinite so nothing falls outside.
    (; latitude_lower_edges, latitude_upper_edges) = chemistry_model
    @test latitude_lower_edges[1] == -Inf
    @test latitude_upper_edges[end] == Inf
    @test collect(latitude_upper_edges[1:(end - 1)]) ==
          collect(latitude_lower_edges[2:end])
    @test latitude_upper_edges[3] == 0            # bands are 30 degrees wide

    (; height_lower_edges, height_upper_edges) = chemistry_model
    @test height_lower_edges[1] == 0
    @test height_upper_edges[end] == Inf
    @test collect(height_upper_edges[1:(end - 1)]) ==
          collect(height_lower_edges[2:end])
    @test height_lower_edges[3] == 10_000

    # Names are ordered with the latitude index varying fastest, matching the
    # order every loop over tracers uses.
    names = CA.stratospheric_tracer_symbols(chemistry_model)
    @test length(names) == 48
    @test names[1] == :ρq_gas_y01z01
    @test names[6] == :ρq_gas_y06z01
    @test names[7] == :ρq_gas_y01z02
    @test names[end] == :ρq_gas_y06z08
    @test allunique(names)

    # Every tracer has a diagnostic to output it through.
    for name in names
        short_name = String(name)[(ncodeunits("ρ") + 1):end]
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, short_name)
    end

    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = CA.MAX_TRACER_LATITUDE_BANDS + 1,
    )
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT;
        n_height_bands = 0,
    )
end

@testset "stratospheric tracer source and loss" begin
    production_rate = FT(2e-10)
    inverse_loss_timescale = FT(1 / 3600)
    ρ = FT(0.1)
    z_tropopause = FT(12_000)

    # A point inside the region: latitude in (0, 30], height above the
    # tropopause in (5000, 10000].
    source(z, lat) = CA.stratospheric_tracer_source(
        ρ, z, lat, z_tropopause,
        FT(0), FT(30), FT(5_000), FT(10_000), production_rate,
    )
    @test source(FT(20_000), FT(15)) == ρ * production_rate
    @test source(FT(20_000), FT(45)) == 0     # wrong latitude band
    @test source(FT(15_000), FT(15)) == 0     # below the band
    @test source(FT(25_000), FT(15)) == 0     # above the band

    # Bands are half-open, so adjacent bands neither overlap nor leave a gap.
    @test source(FT(17_000), FT(15)) == 0             # height exactly 5000
    @test source(FT(22_000), FT(15)) == ρ * production_rate  # exactly 10000
    @test source(FT(20_000), FT(0)) == 0              # latitude exactly 0
    @test source(FT(20_000), FT(30)) == ρ * production_rate  # exactly 30

    # The lowest band starts at the tropopause, which itself belongs to the
    # removal region, not to the band.
    at_tropopause = CA.stratospheric_tracer_source(
        ρ, z_tropopause, FT(15), z_tropopause,
        FT(0), FT(30), FT(0), FT(5_000), production_rate,
    )
    @test at_tropopause == 0

    loss(ρχ, z) = CA.stratospheric_tracer_loss(
        ρχ, z, z_tropopause, inverse_loss_timescale,
    )
    @test loss(FT(1e-8), FT(20_000)) == 0     # above the tropopause
    @test loss(FT(1e-8), FT(5_000)) == FT(1e-8) * inverse_loss_timescale
    @test loss(FT(1e-8), z_tropopause) == FT(1e-8) * inverse_loss_timescale
    # A negative value from the advection scheme must not be amplified.
    @test loss(FT(-1e-8), FT(5_000)) == 0
end

# ===========================================================================
# Prognostic state, tendency and budget on a small sphere
# ===========================================================================

@testset "stratospheric tracers in a simulation" begin
    chemistry_model = CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 3,
        n_height_bands = 2,
        band_depth = 5_000,
        production_rate = 1e-10,
    )
    simulation = CA.AtmosSimulation{FT}(;
        model = CA.AtmosModel(; chemistry_model),
        grid = CA.SphereGrid(
            FT;
            h_elem = 2,
            z_elem = 30,
            z_max = 60_000,
            z_stretch = false,
        ),
        dt = 5,
        t_end = 5,
        job_id = "passive_stratospheric_tracers_test",
        output_dir = mktempdir(),
        output_dir_style = "removepreexisting",
        diagnostics = CA.DiagnosticsConfig(; default = false),
    )
    Y = simulation.integrator.u
    p = simulation.integrator.p
    names = CA.stratospheric_tracer_symbols(chemistry_model)

    # Every source region has a tracer, and every tracer starts at zero.
    @test all(name -> name in propertynames(Y.c), names)
    @test all(name -> all(iszero, parent(getproperty(Y.c, name))), names)

    # The state assembly agrees with the names every tracer loop uses.
    initial = CA.Setups.chemistry_variables(FT(1), nothing, chemistry_model)
    @test keys(initial) == names
    @test all(iszero, values(initial))
    # Grid-scale only: the tracers get no SGS counterparts, which would
    # multiply the EDMF state by the number of source regions.
    @test CA.Setups.chemistry_sgs_variables(nothing, chemistry_model) == (;)

    Yₜ = similar(Y)
    Yₜ .= 0
    CA.chemistry_tendency!(Yₜ, Y, p, FT(0), chemistry_model)

    ᶜz = similar(Y.c.ρ)
    ᶜz .= Fields.coordinate_field(axes(Y.c)).z
    ᶜz_tropopause = similar(Y.c.ρ)
    CA.set_tropopause_height!(
        ᶜz_tropopause,
        similar(Y.c.ρ),
        p.precomputed.ᶜT,
        chemistry_model.tropopause,
    )
    above_tropopause = parent(ᶜz) .> parent(ᶜz_tropopause)

    total_source = zeros(size(parent(Y.c.ρ)))
    for name in names
        tendency = parent(getproperty(Yₜ.c, name))
        # The tracers start at zero, so there is no loss yet and the whole
        # tendency is the source.
        @test all(tendency .>= 0)
        @test any(tendency .> 0)
        @test all(iszero, tendency[.!above_tropopause])
        total_source .+= tendency
    end

    # The source regions partition the domain above the tropopause: every
    # point above it is fed by exactly one tracer.
    expected = parent(Y.c.ρ) .* chemistry_model.production_rate
    @test all(total_source[above_tropopause] .≈ expected[above_tropopause])
    @test all(iszero, total_source[.!above_tropopause])

    # At t = 0 the budget sees the sources but no burden and no loss.
    budget = CA.stratospheric_tracer_budget(Y, p, chemistry_model)
    @test length(budget.burden) == CA.n_tracers(chemistry_model)
    @test all(iszero, budget.burden)
    @test all(iszero, budget.loss)
    @test all(budget.source .> 0)
    # The budget diagnoses the same source the tendency applied, tracer by
    # tracer, which is what makes `burden / source` the tracer's lifetime.
    for (tracer_index, name) in enumerate(names)
        @test budget.source[tracer_index] ≈ sum(getproperty(Yₜ.c, name))
    end

    output_dir = mktempdir()
    CA.write_tracer_budget!(output_dir, 0.0, chemistry_model, budget)
    budget_file = CA.tracer_budget_path(output_dir)
    @test isfile(budget_file)
    budget_lines = readlines(budget_file)
    @test length(budget_lines) == CA.n_tracers(chemistry_model) + 1
    @test startswith(budget_lines[1], "time,tracer,")
    # Header written once, rows appended on the next call.
    CA.write_tracer_budget!(output_dir, 100.0, chemistry_model, budget)
    @test length(readlines(budget_file)) ==
          2 * CA.n_tracers(chemistry_model) + 1
end
