using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

# Unit tests for the YAML -> object translation in `src/config/tracer_config.jl`.
# The physics of the three tracer families is covered by
# `test/tagged_tracers_tests.jl`, `test/tagged_water_tests.jl` and
# `test/parameterized_tendencies/chemistry/passive_stratospheric_tracers.jl`.

const FT = Float64

# `AtmosChem` and `AtmosTagging` take an `AtmosConfig`, so the config has to be
# built rather than passing a bare `Dict`.
tracer_config(entries; job_id) =
    CA.AtmosConfig(Dict{String, Any}(entries); job_id)

@testset "Named regions" begin
    @test CA.tag_region_from_config("everywhere", FT) isa CA.EntireDomain

    tropics = CA.tag_region_from_config("tropics", FT)
    @test tropics isa CA.TanhLatitudeRegion
    @test tropics.lat_bound == FT(20)
    @test tropics.width == FT(2)
    @test tropics.inside

    extratropics = CA.tag_region_from_config("extratropics", FT)
    @test extratropics isa CA.TanhLatitudeRegion
    @test !extratropics.inside

    # `tropics` and `extratropics` must stay an exact partition of unity: the
    # closure diagnostics `e_tag_res` / `q_tag_res` sum all pure region tags.
    for lat in FT.((-90, -25, -20, 0, 12.5, 20, 60, 90))
        coord = (; lat = lat, z = FT(1000))
        total =
            CA.region_mask(tropics, coord) + CA.region_mask(extratropics, coord)
        @test total ≈ one(FT)
    end

    # A named region is exactly the explicit form it stands for.
    explicit = CA.tag_region_from_config(
        Dict("type" => "tanh_latitude", "lat_bound" => 20.0, "width" => 2.0),
        FT,
    )
    @test explicit == tropics

    err = try
        CA.tag_region_from_config("subtropics", FT)
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("tropics", err.msg)      # the message lists what does exist
end

@testset "Region parsing rejects typos" begin
    # Without this a misspelled key is silently dropped: `strict_config`
    # validates top-level key names only.
    err = try
        CA.tag_region_from_config(
            Dict("type" => "tanh_latitude", "lat_bound" => 20.0, "widht" => 2.0),
            FT,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("widht", err.msg)

    # A missing required key is named too.
    err = try
        CA.tag_region_from_config(
            Dict("type" => "tanh_latitude", "lat_bound" => 20.0),
            FT,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("width", err.msg)

    @test_throws ErrorException CA.tag_region_from_config(
        Dict("type" => "tanh_hemisphere", "width" => 2.0),
        FT,
    )
end

@testset "Region parsing rejects masks that define no region" begin
    # Each of these parses, and each used to build a mask that is wrong rather
    # than merely unusual: zero everywhere, negative everywhere, or `NaN` on
    # the edge. The error has to name the key, since the value is accepted
    # arithmetic and nothing downstream would complain.
    region_error(spec) =
        try
            CA.tag_region_from_config(spec, FT)
            nothing
        catch e
            e
        end

    # A zero width is not a sharp edge but an undefined one: `0/0` exactly on
    # the edge is `NaN`, and one `NaN` in a static mask spreads through the
    # tagged field on the first step. A negative width swaps the region for its
    # complement without saying so.
    for width in (0.0, -2.0)
        err = region_error(
            Dict("type" => "tanh_latitude", "lat_bound" => 20.0, "width" => width),
        )
        @test err isa ErrorException
        @test occursin("width", err.msg)
    end

    # Every region type checks its own width.
    for spec in (
        Dict("type" => "tanh_altitude", "z_center" => 12000.0, "width" => 0.0),
        Dict(
            "type" => "tanh_box",
            "lon_min" => -60.0,
            "lon_max" => -10.0,
            "lat_min" => -10.0,
            "lat_max" => 10.0,
            "width" => 0.0,
        ),
        Dict(
            "type" => "tanh_polygon",
            "vertices" => [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]],
            "width" => 0.0,
        ),
    )
        err = region_error(spec)
        @test err isa ErrorException
        @test occursin("width", err.msg)
    end

    # The band is `|lat| <= lat_bound`, so zero is empty and negative gives a
    # negative mask -- a tag holding a negative share of the parent field.
    for lat_bound in (0.0, -20.0)
        err = region_error(
            Dict(
                "type" => "tanh_latitude",
                "lat_bound" => lat_bound,
                "width" => 2.0,
            ),
        )
        @test err isa ErrorException
        @test occursin("lat_bound", err.msg)
    end

    # A valid box, with the one or two keys each case is about overridden.
    box(overrides...) = merge(
        Dict{String, Any}(
            "type" => "tanh_box",
            "lon_min" => -60.0,
            "lon_max" => -10.0,
            "lat_min" => -10.0,
            "lat_max" => 10.0,
            "width" => 1.0,
        ),
        Dict{String, Any}(overrides...),
    )

    # Reversed or equal latitude bounds are the same defect on the other axis.
    for (lat_min, lat_max) in ((10.0, -10.0), (10.0, 10.0))
        err = region_error(box("lat_min" => lat_min, "lat_max" => lat_max))
        @test err isa ErrorException
        @test occursin("lat_min", err.msg)
    end

    # Longitudes are compared modulo 360 so that a box may cross the
    # antimeridian, which leaves a whole turn indistinguishable from none:
    # `-180` to `180` is the obvious way to write "every longitude" and used to
    # give a mask of zero everywhere.
    for (lon_min, lon_max) in ((-180.0, 180.0), (0.0, 360.0), (30.0, 30.0))
        err = region_error(box("lon_min" => lon_min, "lon_max" => lon_max))
        @test err isa ErrorException
        @test occursin("longitude", err.msg)
    end

    # A box that wraps the antimeridian is still fine -- that is the whole
    # reason longitudes are compared modulo 360.
    wrapping = CA.tag_region_from_config(
        box("lon_min" => 170.0, "lon_max" => -170.0),
        FT,
    )
    @test wrapping isa CA.TanhBoxRegion
end

@testset "energy_tracers and water_tracers" begin
    entries = [
        Dict("name" => "tropics", "region" => "tropics"),
        Dict("name" => "extratropics", "region" => "extratropics"),
        Dict("name" => "hs", "source" => "held_suarez"),
    ]
    tags = CA.energy_tracer_tuple(entries, FT)
    @test length(tags) == 3
    @test map(CA.tag_name, tags) == (:tropics, :extratropics, :hs)
    @test tags[3].region === nothing
    @test tags[3].sources == (:held_suarez,)

    water = CA.water_tracer_tuple(
        [Dict("name" => "evap", "source" => "surface_flux")],
        FT,
    )
    @test water[1] isa CA.WaterTag
    @test water[1].sources == (:surface_flux,)

    # Duplicate names would claim the same prognostic field.
    @test_throws ErrorException CA.energy_tracer_tuple(
        [Dict("name" => "a", "region" => "tropics"),
            Dict("name" => "a", "source" => "held_suarez")],
        FT,
    )
    # A tag with neither a region nor a source tracks nothing.
    @test_throws ErrorException CA.energy_tracer_tuple(
        [Dict("name" => "a")],
        FT,
    )
    # An unknown entry key, and a source the family does not attribute.
    @test_throws ErrorException CA.energy_tracer_tuple(
        [Dict("name" => "a", "regoin" => "tropics")],
        FT,
    )
    @test_throws ErrorException CA.water_tracer_tuple(
        [Dict("name" => "a", "source" => "held_suarez")],
        FT,
    )

    config = tracer_config(
        [
            "energy_tracers" => entries,
            "microphysics_model" => "0M",
            "water_tracers" =>
                [Dict("name" => "evap", "source" => "surface_flux")],
        ];
        job_id = "tracer_config_tags",
    )
    tagging = CA.AtmosTagging(config)
    @test tagging.tagging_model isa CA.TaggingModel
    @test tagging.water_tagging_model isa CA.WaterTaggingModel

    # `~` and `[]` both mean "off", at no runtime cost.
    for value in (nothing, [])
        off = CA.AtmosTagging(
            tracer_config(
                ["energy_tracers" => value, "water_tracers" => value];
                job_id = "tracer_config_tags_off_$(isnothing(value))",
            ),
        )
        @test off.tagging_model === nothing
        @test off.water_tagging_model === nothing
    end
end

@testset "passive_tracers release grid" begin
    spec = Dict(
        "release_grid" => Dict(
            "latitude_bands" => 3,
            "latitude_width" => 10.0,
            "height_bands" => 2,
            "height_depth" => 2000.0,
            "height_spacing" => 5000.0,
            "lowest_height" => 1000.0,
        ),
        "production_rate" => 2.0e-10,
        "loss_timescale" => "6hours",
    )
    model = CA.passive_tracer_model(spec, FT)
    @test model isa CA.StratosphericPassiveTracers
    @test CA.n_tracers(model) == 6           # 3 latitude x 2 height
    @test model.production_rate == FT(2.0e-10)
    @test model.loss_timescale == FT(6 * 3600)
    @test model.height_coordinate isa CA.TropopauseRelativeHeight
    @test minimum(model.height_lower_edges) == FT(1000)

    # Everything but the release regions has a default.
    bare = CA.passive_tracer_model(
        Dict("release_grid" => Dict("latitude_bands" => 2, "height_bands" => 2)),
        FT,
    )
    @test CA.n_tracers(bare) == 4
    @test bare.loss_timescale == FT(6 * 3600)
end

@testset "passive_tracers release boxes" begin
    spec = Dict(
        "heights_from" => "altitude",
        "release_boxes" => [
            Dict("latitude" => [-85.0, -75.0], "height" => [10000.0, 10400.0]),
            Dict("latitude" => [75.0, 85.0], "height" => [10000.0, 10400.0]),
        ],
    )
    model = CA.passive_tracer_model(spec, FT)
    @test CA.n_tracers(model) == 2
    @test model.height_coordinate isa CA.GeometricHeight
    @test model.latitude_lower_edges == (FT(-85), FT(75))
    @test model.height_upper_edges == (FT(10400), FT(10400))

    # A box written the old way, with four separate keys.
    @test_throws ErrorException CA.passive_tracer_model(
        Dict(
            "release_boxes" => [
                Dict(
                    "latitude_lower" => -85.0, "latitude_upper" => -75.0,
                    "height_lower" => 10000.0, "height_upper" => 10400.0,
                ),
            ],
        ),
        FT,
    )
    # A range that is not a `[lower, upper]` pair.
    @test_throws ErrorException CA.passive_tracer_model(
        Dict(
            "release_boxes" =>
                [Dict("latitude" => -85.0, "height" => [1.0, 2.0])],
        ),
        FT,
    )
end

@testset "passive_tracers validation" begin
    grid = Dict("latitude_bands" => 2, "height_bands" => 2)
    boxes = [Dict("latitude" => [-5.0, 5.0], "height" => [1.0e4, 1.1e4])]

    # Two ways of saying where the tracers are released. Preferring one
    # silently would hide half the configuration.
    err = try
        CA.passive_tracer_model(
            Dict("release_grid" => grid, "release_boxes" => boxes),
            FT,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("release_grid", err.msg) && occursin("release_boxes", err.msg)

    # Neither is an error too: falling back to the 6 x 8 default would mean
    # hours of setup for 48 tracers nobody asked for.
    err = try
        CA.passive_tracer_model(Dict("production_rate" => 1.0e-10), FT)
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("release_grid", err.msg) && occursin("release_boxes", err.msg)

    @test_throws ErrorException CA.passive_tracer_model(
        Dict("release_grid" => grid, "heights_from" => "pressure"),
        FT,
    )
    # An infinite loss timescale removes the tracers' only sink.
    @test_throws ErrorException CA.passive_tracer_model(
        Dict("release_grid" => grid, "loss_timescale" => "Inf"),
        FT,
    )
    # Typos in each nested block.
    @test_throws ErrorException CA.passive_tracer_model(
        Dict("release_grid" => Dict("latitude_band" => 2)),
        FT,
    )
    @test_throws ErrorException CA.passive_tracer_model(
        Dict("release_grid" => grid, "tropopause" => Dict("lapse_rate" => 0.002)),
        FT,
    )
    @test_throws ErrorException CA.passive_tracer_model(
        Dict("release_grid" => grid, "prodcution_rate" => 1.0e-10),
        FT,
    )

    tropopause = CA.passive_tracer_model(
        Dict(
            "release_grid" => grid,
            "tropopause" => Dict("search_max_height" => 30000.0),
        ),
        FT,
    ).tropopause
    @test tropopause.search_max_height == FT(30000)
    # Unset tropopause keys keep their defaults.
    @test tropopause.lapse_rate_threshold ==
          CA.TropopauseParameters{FT}().lapse_rate_threshold
end

@testset "AtmosChem" begin
    off = CA.AtmosChem(tracer_config([]; job_id = "tracer_config_chem_off"))
    @test off.chemistry_model === nothing

    gas = CA.AtmosChem(
        tracer_config(
            ["chemistry_model" => "passive"];
            job_id = "tracer_config_chem_passive",
        ),
    )
    @test gas.chemistry_model isa CA.GasPhaseChem

    passive = CA.AtmosChem(
        tracer_config(
            [
                "passive_tracers" => Dict(
                    "release_grid" =>
                        Dict("latitude_bands" => 2, "height_bands" => 2),
                ),
            ];
            job_id = "tracer_config_chem_strat",
        ),
    )
    @test passive.chemistry_model isa CA.StratosphericPassiveTracers

    # Both fill the same slot in `AtmosChem`.
    @test_throws ErrorException CA.AtmosChem(
        tracer_config(
            [
                "chemistry_model" => "passive",
                "passive_tracers" => Dict(
                    "release_grid" =>
                        Dict("latitude_bands" => 2, "height_bands" => 2),
                ),
            ];
            job_id = "tracer_config_chem_both",
        ),
    )

    # The retired `chemistry_model` value points at the key that replaced it.
    err = try
        CA.AtmosChem(
            tracer_config(
                ["chemistry_model" => "stratospheric_passive_tracers"];
                job_id = "tracer_config_chem_retired",
            ),
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("passive_tracers", err.msg)
end

@testset "Closure checks" begin
    tolerances = CA.DEFAULT_CLOSURE_TOLERANCES

    # Both keys are optional.
    bare = CA.closure_check_from_config(
        Dict{String, Any}(),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
    )
    @test bare.period == "1days"
    @test bare.tolerance == FT(tolerances.water)

    set = CA.closure_check_from_config(
        Dict("period" => "6hours", "tolerance" => 1.0e-8),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
    )
    @test set.period == "6hours"
    @test set.tolerance == FT(1.0e-8)

    # Off is off.
    @test isnothing(
        CA.closure_check_from_config(
            nothing,
            "`water_closure_check`",
            FT;
            default_tolerance = tolerances.water,
        ),
    )

    # A tolerance of zero is legitimate -- it warns every period, which is how
    # you confirm the threshold is being read at all.
    zero_tolerance = CA.closure_check_from_config(
        Dict("tolerance" => 0.0),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
    )
    @test zero_tolerance.tolerance == FT(0)

    # A typo in the block names itself, like every other nested block.
    err = try
        CA.closure_check_from_config(
            Dict("tolerence" => 1.0e-8),
            "`water_closure_check`",
            FT;
            default_tolerance = tolerances.water,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("tolerence", err.msg)

    # An infinite period never checks anything, which is what leaving the block
    # out already does; a negative tolerance compares against an absolute value.
    for bad in (Dict("period" => "Inf"), Dict("tolerance" => -1.0))
        @test_throws ErrorException CA.closure_check_from_config(
            bad,
            "`water_closure_check`",
            FT;
            default_tolerance = tolerances.water,
        )
    end

    # The energy family is looser on purpose: its tags never receive implicit
    # transport, so its residual is legitimately larger.
    @test tolerances.energy > tolerances.water

    config = tracer_config(
        [
            "water_closure_check" => Dict("period" => "6hours"),
            "energy_closure_check" => Dict("tolerance" => 1.0e-4),
        ];
        job_id = "tracer_config_closure",
    )
    checks = CA.closure_checks_from_config(config)
    @test checks.water.period == "6hours"
    # This path takes its float type from the run, through `eltype(config)`,
    # rather than from this file's `FT`. `FLOAT_TYPE` defaults to Float32, and
    # `Float32(1e-4) != Float64(1e-4)`.
    @test checks.energy.tolerance isa eltype(config)
    @test checks.energy.tolerance == eltype(config)(1.0e-4)
end

@testset "Closure checks refuse what they cannot compute" begin
    scheduling = (;
        output_dir = mktempdir(),
        dt = nothing,
        t_start = nothing,
        t_end = nothing,
        checkpoint_frequency = nothing,
    )
    check = (; period = "1days", tolerance = FT(1.0e-10))

    # Asking to check a family that is switched off.
    err = try
        CA.tag_closure_callback(
            check,
            nothing;
            family = "water",
            total_name = :ρq_tot,
            state_names = CA.water_region_tag_state_names,
            config_key = "water_closure_check",
            tracer_key = "water_tracers",
            scheduling...,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("water_tracers", err.msg)

    # Tags configured, but none of them is a pure region tag, so there is no
    # partition to close against.
    source_only = CA.WaterTaggingModel(
        CA.water_tracer_tuple(
            [Dict("name" => "evap", "source" => "surface_flux")],
            FT,
        ),
    )
    @test isempty(CA.water_region_tag_state_names(source_only))
    err = try
        CA.tag_closure_callback(
            check,
            source_only;
            family = "water",
            total_name = :ρq_tot,
            state_names = CA.water_region_tag_state_names,
            config_key = "water_closure_check",
            tracer_key = "water_tracers",
            scheduling...,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("region", err.msg)

    # No block means no callback, and no complaint about a missing family.
    @test CA.tag_closure_callback(
        nothing,
        nothing;
        family = "water",
        total_name = :ρq_tot,
        state_names = CA.water_region_tag_state_names,
        config_key = "water_closure_check",
        tracer_key = "water_tracers",
        scheduling...,
    ) == ()
end

@testset "Closure table" begin
    dir = mktempdir()
    # A signed residual of 1 that came from local misses of +3 and -2, which is
    # the case the gross columns exist to distinguish: the signed pair cannot
    # tell it from a uniform miss of 1.
    closure = (;
        total = 3.0,
        tagged = 2.0,
        residual = 1.0,
        relative = 1 / 3,
        gross_residual = 5.0,
        gross_relative = 5 / 3,
    )
    CA.write_tag_closure!(dir, 0.0, "water", closure)
    CA.write_tag_closure!(dir, 86400.0, "water", closure)

    path = CA.tag_closure_path(dir, "water")
    @test isfile(path)
    rows = readlines(path)
    # Header written once, then one row per call.
    @test rows[1] ==
          "time,total,tagged,residual,relative,gross_residual,gross_relative"
    @test length(rows) == 3
    @test startswith(rows[2], "0.0,3.0,2.0,1.0,")
    @test endswith(rows[2], ",5.0,$(5 / 3)")
    @test startswith(rows[3], "86400.0,")
    # Every header column is filled in.
    @test all(row -> length(split(row, ",")) == 7, rows)
end

@testset "Shipped tracer configs still build a model" begin
    # The migrated configs are the interface's real regression test: each must
    # still produce the model it produced under the old keys.
    for (file, job_id) in (
        ("model_configs/passive_stratospheric_tracers_ci.yml",
            "passive_stratospheric_tracers_ci"),
        ("example_configs/passive_stratospheric_tracers.yml",
            "passive_stratospheric_tracers"),
        ("example_configs/strat_tracers_transient_a.yml",
            "strat_tracers_transient_a"),
        ("example_configs/strat_tracers_transient_b.yml",
            "strat_tracers_transient_b"),
    )
        config = CA.AtmosConfig(joinpath(CA.config_path, file); job_id)
        @test CA.AtmosChem(config).chemistry_model isa
              CA.StratosphericPassiveTracers
    end

    energy = CA.AtmosConfig(
        joinpath(CA.config_path, "model_configs/baroclinic_wave_tagged_tracers.yml");
        job_id = "baroclinic_wave_tagged_tracers",
    )
    @test length(CA.AtmosTagging(energy).tagging_model.tags) == 5

    water = CA.AtmosConfig(
        joinpath(CA.config_path, "model_configs/baroclinic_wave_tagged_water.yml");
        job_id = "baroclinic_wave_tagged_water",
    )
    @test length(CA.AtmosTagging(water).water_tagging_model.tags) == 5
end
