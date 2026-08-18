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
        latitude_width = 10,
        band_depth = 2_000,
        band_spacing = 5_000,
    )

    @test CA.n_tracers(chemistry_model) == 48

    # The edges are stored per box, not per band, so the keyword constructor's
    # outer product appears as each latitude repeated once per height band.
    (; latitude_lower_edges, latitude_upper_edges) = chemistry_model
    @test length(latitude_lower_edges) == 48
    widths = latitude_upper_edges .- latitude_lower_edges
    @test all(w -> w ≈ 10, widths)

    # The boxes sample the domain rather than tiling it: each stays within the
    # size it was asked for, and none overlaps its neighbour.
    latitude_lowers = unique(latitude_lower_edges)
    latitude_uppers = unique(latitude_upper_edges)
    @test length(latitude_lowers) == 6
    @test all(
        i -> latitude_uppers[i] < latitude_lowers[i + 1],
        1:(length(latitude_lowers) - 1),
    )
    # Centred on the midpoints of six equal divisions of pole to pole, so the
    # set is symmetric about the equator and stays inside it.
    centers = (latitude_lowers .+ latitude_uppers) ./ 2
    @test centers ≈ [-75, -45, -15, 15, 45, 75]
    @test minimum(latitude_lower_edges) >= -90
    @test maximum(latitude_upper_edges) <= 90

    (; height_lower_edges, height_upper_edges) = chemistry_model
    @test length(height_lower_edges) == 48
    depths = height_upper_edges .- height_lower_edges
    @test all(d -> d ≈ 2_000, depths)
    height_lowers = unique(height_lower_edges)
    height_uppers = unique(height_upper_edges)
    @test length(height_lowers) == 8
    @test all(
        k -> height_uppers[k] < height_lowers[k + 1],
        1:(length(height_lowers) - 1),
    )
    @test height_lowers[1] == 0          # bottom box sits on the tropopause
    @test height_lowers[3] == 10_000     # stacked every 5 km
    @test all(isfinite, height_upper_edges)   # no open-ended box

    # Overlapping boxes would make a point feed two tracers at once, so they
    # are refused rather than silently double-counted.
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 6,
        latitude_width = 40,      # wider than the 30 degree spacing
    )
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT;
        band_depth = 6_000,       # deeper than the 5 km spacing
        band_spacing = 5_000,
    )

    # Names are ordered with the latitude index varying fastest, matching the
    # order every loop over tracers uses.
    names = CA.stratospheric_tracer_symbols(chemistry_model)
    @test length(names) == 48
    @test names[1] == :ρq_gas_y01z01
    @test names[6] == :ρq_gas_y06z01
    @test names[7] == :ρq_gas_y01z02
    @test names[end] == :ρq_gas_y06z08
    @test allunique(names)

    # Every tracer has a diagnostic to output it through, registered from the
    # model rather than at load time.
    CA.Diagnostics.register_stratospheric_tracer_diagnostics!(chemistry_model)
    for name in names
        short_name = String(name)[(ncodeunits("ρ") + 1):end]
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, short_name)
    end

    # Registering from the model means the grid has no fixed upper bound: a
    # 500-tracer grid registers as readily as the 48-tracer one above.
    large_model = CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 20,
        n_height_bands = 25,
        latitude_width = 5,
    )
    @test CA.n_tracers(large_model) == 500
    CA.Diagnostics.register_stratospheric_tracer_diagnostics!(large_model)
    @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "q_gas_y20z25")

    # Registration is a no-op for a model without passive tracers.
    @test isnothing(
        CA.Diagnostics.register_stratospheric_tracer_diagnostics!(nothing),
    )

    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT;
        n_height_bands = 0,
    )
end

@testset "stratospheric tracer explicit source boxes" begin
    # A grid that no combination of the band keys can express: the height
    # boxes have different depths and uneven spacing, and the lowest one is
    # used at only two of the three latitudes.
    boxes = [
        CA.SourceBox(FT(-85), FT(-75), FT(9_990), FT(10_405)),
        CA.SourceBox(FT(75), FT(85), FT(9_990), FT(10_405)),
        CA.SourceBox(FT(-85), FT(-75), FT(27_896), FT(28_624)),
        CA.SourceBox(FT(-5), FT(5), FT(27_896), FT(28_624)),
        CA.SourceBox(FT(75), FT(85), FT(27_896), FT(28_624)),
    ]
    model = CA.StratosphericPassiveTracers(FT, boxes)

    @test CA.n_tracers(model) == 5
    @test model.latitude_lower_edges[1] ≈ -85
    @test model.height_upper_edges[end] ≈ 28_624
    # Depths differ between the two height levels, which the outer-product
    # constructor cannot represent.
    @test !(
        model.height_upper_edges[1] - model.height_lower_edges[1] ≈
        model.height_upper_edges[3] - model.height_lower_edges[3]
    )

    # Names index the distinct latitude and height ranges in order of first
    # appearance, so the equator box is latitude 3 even though it appears last.
    names = CA.stratospheric_tracer_symbols(model)
    @test names == (
        :ρq_gas_y01z01,
        :ρq_gas_y02z01,
        :ρq_gas_y01z02,
        :ρq_gas_y03z02,
        :ρq_gas_y02z02,
    )
    @test allunique(names)

    CA.Diagnostics.register_stratospheric_tracer_diagnostics!(model)
    @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "q_gas_y03z02")

    # The keyword constructor is the same thing with an outer product, so the
    # two agree when the explicit list spells that product out.
    grid_model = CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 2,
        n_height_bands = 2,
        latitude_width = 10,
        band_depth = 2_000,
        band_spacing = 5_000,
    )
    spelled_out = CA.StratosphericPassiveTracers(
        FT,
        [
            CA.SourceBox(FT(-50), FT(-40), FT(0), FT(2_000)),
            CA.SourceBox(FT(40), FT(50), FT(0), FT(2_000)),
            CA.SourceBox(FT(-50), FT(-40), FT(5_000), FT(7_000)),
            CA.SourceBox(FT(40), FT(50), FT(5_000), FT(7_000)),
        ],
    )
    @test CA.stratospheric_tracer_symbols(grid_model) ==
          CA.stratospheric_tracer_symbols(spelled_out)
    @test collect(grid_model.latitude_lower_edges) ≈
          collect(spelled_out.latitude_lower_edges)
    @test collect(grid_model.height_lower_edges) ≈
          collect(spelled_out.height_lower_edges)

    # Overlap is allowed: the tracers are independent, so a shared point feeds
    # both and each budget stays self-consistent. A whole-domain reference box
    # enclosing the sampled boxes is the case this exists for.
    nested = CA.StratosphericPassiveTracers(
        FT,
        [
            CA.SourceBox(FT(-10), FT(10), FT(0), FT(2_000)),
            CA.SourceBox(FT(-90), FT(90), FT(0), FT(50_000)),
        ],
    )
    @test CA.n_tracers(nested) == 2
    @test CA.boxes_overlap(
        CA.SourceBox(FT(-10), FT(10), FT(0), FT(2_000)),
        CA.SourceBox(FT(-90), FT(90), FT(0), FT(50_000)),
    )
    # Boxes that only touch at an edge do not overlap: the membership test is
    # half-open, so the shared edge belongs to exactly one of them.
    @test !CA.boxes_overlap(
        CA.SourceBox(FT(-10), FT(0), FT(0), FT(2_000)),
        CA.SourceBox(FT(0), FT(10), FT(0), FT(2_000)),
    )

    # Two boxes with the same latitude and height range would claim the same
    # name, which is refused.
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT,
        [
            CA.SourceBox(FT(-10), FT(10), FT(0), FT(2_000)),
            CA.SourceBox(FT(-10), FT(10), FT(0), FT(2_000)),
        ],
    )

    # Empty ranges and empty lists are rejected rather than silently producing
    # a tracer with no source.
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT,
        [CA.SourceBox(FT(10), FT(10), FT(0), FT(2_000))],
    )
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT,
        [CA.SourceBox(FT(-10), FT(10), FT(2_000), FT(0))],
    )
    @test_throws ErrorException CA.StratosphericPassiveTracers(
        FT,
        CA.SourceBox{FT}[],
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

    # The boxes sample the domain rather than covering it, so a point above
    # the tropopause is fed by at most one tracer — never two — and nothing at
    # or below the tropopause is fed at all.
    expected = parent(Y.c.ρ) .* chemistry_model.production_rate
    @test all(total_source .<= expected .* (1 + 1e-6))
    @test any(total_source .> 0)
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

# ===========================================================================
# Burden plot
# ===========================================================================

@testset "tracer burden plot" begin
    include(joinpath(pkgdir(CA), "post_processing", "plot_tracer_burdens.jl"))

    chemistry_model = CA.StratosphericPassiveTracers(
        FT;
        n_latitude_bands = 3,
        n_height_bands = 2,
    )
    n = CA.n_tracers(chemistry_model)
    output_dir = mktempdir()
    # Two output times of a tracer that is still filling, which is the shape
    # every real budget table starts with.
    for (step, t) in enumerate((0.0, 86400.0))
        budget = (;
            burden = collect(FT, (1:n) .* 1e9 .* (step - 1)),
            source = collect(FT, (1:n) .* 1e4),
            loss = zeros(FT, n),
        )
        CA.write_tracer_budget!(output_dir, t, chemistry_model, budget)
    end

    dpi = 300
    size_inches = (4, 3)
    path = plot_tracer_burdens(output_dir; dpi, size_inches)
    @test isfile(path)
    @test endswith(path, "tracer_burdens.png")

    # The PNG header carries the pixel dimensions, so the dpi request can be
    # checked rather than assumed: bytes 17-24 are the IHDR width and height,
    # big-endian.
    header = read(path)[1:24]
    @test header[2:4] == UInt8['P', 'N', 'G']
    png_size = (
        Int(only(reinterpret(UInt32, reverse(header[17:20])))),
        Int(only(reinterpret(UInt32, reverse(header[21:24])))),
    )
    # One pixel of slack: the point-to-pixel scaling is not exact in binary.
    @test all(abs.(png_size .- round.(Int, size_inches .* dpi)) .<= 1)
end
