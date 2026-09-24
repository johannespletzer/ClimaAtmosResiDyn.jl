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
    # Each of these parses as arithmetic while describing a mask that is wrong
    # rather than merely unusual: zero everywhere, negative everywhere, or `NaN`
    # on the edge. The error has to name the key, because the value is accepted
    # arithmetic that nothing downstream would flag.
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

    # Longitudes are compared modulo 360 so a box may cross the antimeridian,
    # which leaves a whole turn indistinguishable from none. `-180` to `180` is
    # the obvious way to write "every longitude", and it has to be rejected
    # rather than read as a mask of zero everywhere.
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

@testset "water_tracers refusals" begin
    evap = [Dict("name" => "evap", "source" => "surface_flux")]
    water_config(extra, job_id) = tracer_config(
        ["microphysics_model" => "0M", "water_tracers" => evap, extra...];
        job_id,
    )

    @test isnothing(CA.check_water_tracers_transport_supported(nothing, false))
    # Under prognostic EDMF the tags follow one updraft, by default through a
    # donor share and an exchange, or through copies. More than one updraft is
    # refused.
    edmf = CA.AtmosTagging(
        water_config(["turbconv" => "prognostic_edmfx"], "water_tags_edmf"),
    )
    @test edmf.water_tagging_model isa CA.WaterTaggingModel
    @test !CA.has_water_tag_updraft_copies(edmf.water_tagging_model)
    @test_throws "`updraft_number: 1`" CA.AtmosTagging(
        water_config(
            ["turbconv" => "prognostic_edmfx", "updraft_number" => 2],
            "water_tags_edmf_two_updrafts",
        ),
    )
    # The copies: under prognostic EDMF only, with one reconstruction for the
    # updraft's water and its tracers, and only with tags to copy.
    copies = CA.AtmosTagging(
        water_config(
            ["turbconv" => "prognostic_edmfx", "water_tag_updraft_copy" => true],
            "water_tags_copies",
        ),
    )
    @test CA.has_water_tag_updraft_copies(copies.water_tagging_model)
    @test_throws "needs `turbconv: prognostic_edmfx`" CA.AtmosTagging(
        water_config(["water_tag_updraft_copy" => true], "water_tags_copies_no_edmf"),
    )
    @test_throws "`edmfx_mse_q_tot_upwinding` equal" CA.AtmosTagging(
        water_config(
            [
                "turbconv" => "prognostic_edmfx",
                "water_tag_updraft_copy" => true,
                "edmfx_mse_q_tot_upwinding" => "third_order",
            ],
            "water_tags_copies_upwinding",
        ),
    )
    @test_throws "no tags to copy" CA.AtmosTagging(
        tracer_config(
            ["microphysics_model" => "0M", "water_tag_updraft_copy" => true];
            job_id = "water_copies_without_tags",
        ),
    )
    @test_throws "no tags for it to move" CA.AtmosTagging(
        tracer_config(
            ["microphysics_model" => "0M", "water_tag_transport" => "increment"];
            job_id = "water_increment_without_tags",
        ),
    )
    @test_throws "must be `true` or `false`" CA.water_tag_updraft_copy_from_config(
        "true",
    )
    # AMD's diffusivity comes from each tracer's own gradient, so the tags'
    # diffusion does not add up to the parent's.
    @test_throws "amd_les: true" CA.AtmosTagging(
        water_config(["amd_les" => true], "water_tags_amd"),
    )
    # Eddy diffusion alone shares one diffusivity, so the sum holds under 0M.
    # Under 1M the known q_tot_eff leak applies, as under any diffusion, and is
    # not refused.
    edonly = CA.AtmosTagging(
        water_config(["turbconv" => "edonly_edmfx"], "water_tags_edonly"),
    )
    @test edonly.water_tagging_model isa CA.WaterTaggingModel
    # The records are not transported, so they stay allowed under EDMF.
    records = CA.AtmosTagging(
        tracer_config(
            [
                "microphysics_model" => "0M",
                "turbconv" => "prognostic_edmfx",
                "water_process_record" => ["surface_flux"],
            ];
            job_id = "water_records_edmf",
        ),
    )
    @test records.water_process_record !== nothing
    @test records.water_tagging_model === nothing
    # And under AMD, which breaks only the transported tags.
    records_amd = CA.AtmosTagging(
        tracer_config(
            [
                "microphysics_model" => "0M",
                "amd_les" => true,
                "water_process_record" => ["surface_flux"],
            ];
            job_id = "water_records_amd",
        ),
    )
    @test records_amd.water_process_record !== nothing
    @test records_amd.water_tagging_model === nothing
    # The prescribed flow's surface moisture flux enters ρq_tot untagged. The
    # warning sees the built model, since the setup can bring the flow.
    flow = CA.ShipwayHill2012VelocityProfile{FT}()
    tagging = CA.WaterTaggingModel(CA.water_tracer_tuple(evap, FT))
    @test_logs (:warn, r"prescribed flow") CA.warn_water_tags_under_prescribed_flow(
        flow,
        tagging,
    )
    @test_logs CA.warn_water_tags_under_prescribed_flow(nothing, tagging)
    @test_logs CA.warn_water_tags_under_prescribed_flow(flow, nothing)
    # Both routes to a flow reach the warning through `get_atmos`: the setup's
    # own, as the shipped kinematic driver uses it, and the key.
    for (entries, job_id) in (
        (["initial_condition" => "ShipwayHill2012"], "water_tags_flow_setup"),
        (
            [
                "initial_condition" => "DYCOMS_RF02",
                "prescribed_flow" => "ShipwayHill2012",
                # The model runs a prescribed flow explicitly only.
                "implicit_microphysics" => false,
            ],
            "water_tags_flow_key",
        ),
    )
        config = tracer_config(
            [
                "config" => "column",
                "z_max" => 2000.0,
                "z_elem" => 10,
                "z_stretch" => false,
                "microphysics_model" => "1M",
                "water_tracers" => evap,
                entries...,
            ];
            job_id,
        )
        params = CA.ClimaAtmosParameters(config)
        setup = CA.get_setup_type(
            config.parsed_args,
            CA.Parameters.thermodynamics_params(params),
        )
        grid = CA.get_grid(config.parsed_args, params, config.comms_ctx)
        @test_logs (:warn, r"prescribed flow") match_mode = :any CA.get_atmos(
            config,
            params,
            grid;
            setup_type = setup,
        )
    end

    # Names that would take the name of another diagnostic of the family.
    @test_throws "`res` is a reserved tag name" CA.water_tracer_tuple(
        [Dict("name" => "res", "source" => "surface_flux")],
        FT,
    )
    for name in ("fix_a", "upfix_a", "inc_left", "rtag_a", "stag_a")
        @test_throws "`$name` is refused" CA.water_tracer_tuple(
            [Dict("name" => name, "source" => "surface_flux")],
            FT,
        )
    end
    # A reserved prefix counts only as a prefix, with its underscore.
    for name in ("evap_fix", "fixed", "income", "stagnant", "rtagged")
        @test CA.water_tracer_tuple(
            [Dict("name" => name, "source" => "surface_flux")],
            FT,
        )[1] isa CA.WaterTag
    end
end

@testset "energy_source_tags against the scheme" begin
    entries = [
        Dict{String, Any}("name" => "a", "region" => "tropics"),
        Dict{String, Any}("name" => "b", "region" => "extratropics"),
        Dict{String, Any}("name" => "mp", "source" => "microphysics"),
    ]
    source_config(name, pairs...) = tracer_config(
        [
            "energy_source_tags" => entries,
            "energy_source_tag_offset" => 110495.0,
            pairs...,
        ];
        job_id = "tracer_config_source_$name",
    )
    # The warnings that `AtmosTagging` gives about one label.
    label_warnings(config, label) = filter(
        log -> occursin("lists `$label`", string(log.message)),
        first(Test.collect_test_logs(() -> CA.AtmosTagging(config))),
    )

    # Every run with these tags states its offset. Without the key the tags are
    # refused, and the message quotes the offsets that were tested. `0` keeps
    # the tags on `ρe_tot`.
    without_offset = tracer_config(
        ["energy_source_tags" => entries];
        job_id = "tracer_config_source_no_offset",
    )
    @test_throws r"needs `energy_source_tag_offset`" CA.AtmosTagging(
        without_offset,
    )
    @test_throws r"110495 J/kg" CA.AtmosTagging(without_offset)
    no_offset = source_config("zero_offset", "energy_source_tag_offset" => 0)
    @test isnothing(CA.AtmosTagging(no_offset).energy_source_tagging_model.offset)
    # An offset without tags is still refused.
    @test_throws ErrorException CA.AtmosTagging(
        tracer_config(
            ["energy_source_tag_offset" => 110495.0];
            job_id = "tracer_config_source_offset_alone",
        ),
    )

    # The model runs `prognostic_edmfx` with one updraft only, and the tags
    # share the updraft corrections to sedimentation, which it computes for
    # the first updraft only. So one updraft is allowed, and two are refused
    # when the tags are configured. Eddy diffusion moves the tags as tracers
    # under both EDMF variants. That is allowed, and warned.
    @test_logs (:warn, r"prognostic_edmfx") match_mode = :any CA.AtmosTagging(
        source_config("edmf", "turbconv" => "prognostic_edmfx"),
    )
    @test_throws r"updraft_number: 1" CA.AtmosTagging(
        source_config(
            "edmf_two",
            "turbconv" => "prognostic_edmfx",
            "updraft_number" => 2,
        ),
    )
    @test_logs (:warn, r"edonly_edmfx") match_mode = :any CA.AtmosTagging(
        source_config("edonly", "turbconv" => "edonly_edmfx"),
    )

    # Only 0-moment microphysics changes `ρe_tot`. So under 1M the `mp` tag and
    # a `microphysics` record stay zero, and each says so.
    one_moment = source_config(
        "1m",
        "microphysics_model" => "1M",
        "energy_process_record" => ["microphysics", "precipitation"],
    )
    @test length(label_warnings(one_moment, "microphysics")) == 2
    # Under 1M sedimentation runs, so the `precipitation` record is quiet.
    @test isempty(label_warnings(one_moment, "precipitation"))

    zero_moment = source_config(
        "0m",
        "microphysics_model" => "0M",
        "energy_process_record" => ["microphysics", "precipitation"],
    )
    @test isempty(label_warnings(zero_moment, "microphysics"))
    @test length(label_warnings(zero_moment, "precipitation")) == 1

    # The offset and the transport act on the tags, so each is refused alone.
    @test_throws ErrorException CA.AtmosTagging(
        tracer_config(
            ["energy_source_tag_offset" => 110495.0];
            job_id = "tracer_config_source_offset_alone",
        ),
    )
    @test_throws ErrorException CA.AtmosTagging(
        tracer_config(
            ["energy_source_tag_transport" => "enthalpy"];
            job_id = "tracer_config_source_transport_alone",
        ),
    )
    # With tags, the key reaches the model.
    enthalpy = CA.AtmosTagging(
        source_config("enthalpy", "energy_source_tag_transport" => "enthalpy"),
    )
    @test enthalpy.energy_source_tagging_model.transport isa
          CA.EnthalpyEnergySourceTransport
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

    # A box written as four separate keys, which the schema rejects.
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

    # `chemistry_model: stratospheric_passive_tracers` errors, and the message
    # names the `passive_tracers` key to use instead.
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
    aborts = CA.DEFAULT_CLOSURE_ABORT_LEVELS

    # Both keys are optional.
    bare = CA.closure_check_from_config(
        Dict{String, Any}(),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )
    @test bare.period == "1days"
    @test bare.tolerance == FT(tolerances.water)
    @test bare.abort_above == FT(aborts.water)
    # The audit is extra reductions and a second file, so it is opt-in.
    @test bare.audit == false

    set = CA.closure_check_from_config(
        Dict(
            "period" => "6hours",
            "tolerance" => 1.0e-8,
            "abort_above" => 5.0,
        ),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )
    @test set.period == "6hours"
    @test set.tolerance == FT(1.0e-8)
    @test set.abort_above == FT(5.0)

    audited = CA.closure_check_from_config(
        Dict{String, Any}("audit" => true),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )
    @test audited.audit == true
    # Turning the audit on changes nothing else about the check.
    @test audited.period == bare.period
    @test audited.tolerance == bare.tolerance
    @test audited.abort_above == bare.abort_above

    # Off is off.
    @test isnothing(
        CA.closure_check_from_config(
            nothing,
            "`water_closure_check`",
            FT;
            default_tolerance = tolerances.water,
            default_abort_above = aborts.water,
        ),
    )

    # A tolerance of zero is legitimate -- it warns every period, which is how
    # you confirm the threshold is being read at all.
    zero_tolerance = CA.closure_check_from_config(
        Dict("tolerance" => 0.0),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )
    @test zero_tolerance.tolerance == FT(0)

    # `abort_above: ~` is how a family that defaults to having a level opts out
    # of it. Zero is refused instead of read as "always", because a run
    # configured that way would die at the first check whatever its residual
    # was, and `~` already says "never" without the ambiguity.
    no_abort = CA.closure_check_from_config(
        Dict{String, Any}("abort_above" => nothing),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )
    @test isnothing(no_abort.abort_above)
    @test_throws ErrorException CA.closure_check_from_config(
        Dict("abort_above" => 0.0),
        "`water_closure_check`",
        FT;
        default_tolerance = tolerances.water,
        default_abort_above = aborts.water,
    )

    # The two energy families have no default level at all: their residual is
    # normalised by a quantity whose zero is a convention, so no one number
    # transfers between configurations.
    @test isnothing(aborts.energy)
    @test isnothing(aborts.energy_source)
    @test isnothing(
        CA.closure_check_from_config(
            Dict{String, Any}(),
            "`energy_closure_check`",
            FT;
            default_tolerance = tolerances.energy,
            default_abort_above = aborts.energy,
        ).abort_above,
    )

    # A typo in the block names itself, like every other nested block.
    err = try
        CA.closure_check_from_config(
            Dict("tolerence" => 1.0e-8),
            "`water_closure_check`",
            FT;
            default_tolerance = tolerances.water,
            default_abort_above = aborts.water,
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
            default_abort_above = aborts.water,
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
    check = (; period = "1days", tolerance = FT(1.0e-10), abort_above = FT(1))

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

@testset "Energy source closure check" begin
    tolerances = CA.DEFAULT_CLOSURE_TOLERANCES
    # The energy source family has no default tolerance, so its check reports
    # without warning until a calibrated level is set.
    @test isnothing(tolerances.energy_source)

    # Parsing, and the default that applies when the block is bare.
    bare = CA.closure_check_from_config(
        Dict{String, Any}(),
        "`energy_source_closure_check`",
        FT;
        default_tolerance = tolerances.energy_source,
        default_abort_above = CA.DEFAULT_CLOSURE_ABORT_LEVELS.energy_source,
    )
    @test bare.period == "1days"
    @test isnothing(bare.tolerance)
    @test isnothing(bare.abort_above)
    @test isnothing(bare.spin_up)
    @test_throws ErrorException CA.closure_check_from_config(
        Dict{String, Any}("spin_up" => "0secs"),
        "`energy_source_closure_check`",
        FT;
        default_tolerance = nothing,
        default_abort_above = nothing,
    )

    # With the tags, the check is on by default: daily, report-only, from a
    # spin-up reference an hour in. `false` switches it off, and tags without a
    # pure region tag get no check, since there is no partition to close.
    partition_entries = [
        Dict{String, Any}("name" => "trop", "region" => "tropics"),
        Dict{String, Any}("name" => "rad", "source" => "radiation"),
    ]
    default_check = CA.energy_source_closure_check_from_config(
        nothing,
        partition_entries,
        CA.TracerEnergySourceTransport(),
        FT,
    )
    @test default_check.period == "1days"
    # The default tolerance follows the transport: a runaway guard, calibrated
    # from the tag-closure runs.
    @test default_check.tolerance == FT(CA.ENERGY_SOURCE_CLOSURE_TOLERANCES.tracer)
    @test CA.energy_source_closure_check_from_config(
        nothing,
        partition_entries,
        CA.EnthalpyIncrementEnergySourceTransport(),
        FT,
    ).tolerance == FT(CA.ENERGY_SOURCE_CLOSURE_TOLERANCES.enthalpy_increment)
    @test CA.energy_source_closure_check_from_config(
        Dict{String, Any}("tolerance" => 1.0e-3),
        partition_entries,
        CA.TracerEnergySourceTransport(),
        FT,
    ).tolerance == FT(1.0e-3)
    @test default_check.spin_up == "1hours"
    @test !default_check.audit
    @test isnothing(
        CA.energy_source_closure_check_from_config(
            false,
            partition_entries,
            CA.TracerEnergySourceTransport(),
            FT,
        ),
    )
    @test isnothing(
        CA.energy_source_closure_check_from_config(
            nothing,
            [Dict{String, Any}("name" => "rad", "source" => "radiation")],
            CA.TracerEnergySourceTransport(),
            FT,
        ),
    )
    @test isnothing(
        CA.energy_source_closure_check_from_config(
            nothing,
            nothing,
            CA.TracerEnergySourceTransport(),
            FT,
        ),
    )
    # `source: none` still makes a pure region tag.
    @test !isnothing(
        CA.energy_source_closure_check_from_config(
            nothing,
            [
                Dict{String, Any}(
                    "name" => "trop",
                    "region" => "tropics",
                    "source" => "none",
                ),
            ],
            CA.TracerEnergySourceTransport(),
            FT,
        ),
    )

    # The key reaches the config, with the run's float type rather than this
    # file's, exactly as the other two families do.
    config = tracer_config(
        [
            "energy_source_tags" => [
                Dict{String, Any}("name" => "trop", "region" => "tropics"),
                Dict{String, Any}(
                    "name" => "extra",
                    "region" => "extratropics",
                ),
            ],
            "energy_source_tag_offset" => 0,
            "energy_source_closure_check" =>
                Dict("period" => "6hours", "tolerance" => 1.0e-5),
        ];
        job_id = "tracer_config_energy_source_closure",
    )
    checks = CA.closure_checks_from_config(config)
    @test checks.energy_source.period == "6hours"
    @test checks.energy_source.tolerance isa eltype(config)
    @test checks.energy_source.tolerance == eltype(config)(1.0e-5)

    scheduling = (;
        output_dir = mktempdir(),
        dt = nothing,
        t_start = nothing,
        t_end = nothing,
        checkpoint_frequency = nothing,
    )
    check = (; period = "1days", tolerance = FT(1.0e-6), abort_above = nothing)
    callback_kwargs = (;
        family = "energy_source",
        total_name = :ρe_tot,
        state_names = CA.energy_source_region_tag_state_names,
        config_key = "energy_source_closure_check",
        tracer_key = "energy_source_tags",
    )

    # A partition of region tags is what the callback needs to exist at all.
    # The successful construction itself is not asserted here: past the
    # validation the builder promotes `period` against `dt`, `t_start` and
    # `t_end`, so it needs real schedule values rather than the `nothing`s the
    # rejection paths below use, and no test in this suite builds one. The
    # tagging integration tests cover the assembled callback in a real run.
    partition = CA.EnergySourceTaggingModel(
        CA.energy_source_tracer_tuple(
            [
                Dict{String, Any}("name" => "trop", "region" => "tropics"),
                Dict{String, Any}(
                    "name" => "extra",
                    "region" => "extratropics",
                ),
            ],
            FT,
        ),
    )
    @test !isempty(CA.energy_source_region_tag_state_names(partition))

    # Checking a family that is switched off names the key that would enable it.
    err = try
        CA.tag_closure_callback(
            check,
            nothing;
            callback_kwargs...,
            scheduling...,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("energy_source_tags", err.msg)

    # Source-only tags form no partition, so there is nothing to close against.
    source_only = CA.EnergySourceTaggingModel(
        CA.energy_source_tracer_tuple(
            [Dict{String, Any}("name" => "rad", "source" => "radiation")],
            FT,
        ),
    )
    @test isempty(CA.energy_source_region_tag_state_names(source_only))
    err = try
        CA.tag_closure_callback(
            check,
            source_only;
            callback_kwargs...,
            scheduling...,
        )
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("region", err.msg)

    # No block means no callback, and no complaint about the family.
    @test CA.tag_closure_callback(
        nothing,
        nothing;
        callback_kwargs...,
        scheduling...,
    ) == ()

    # The family writes its own table, so a run with several checks on does not
    # have them overwrite each other.
    dir = mktempdir()
    closure = (;
        total = 3.0,
        tagged = 2.0,
        residual = 1.0,
        relative = 1 / 3,
        gross_residual = 5.0,
        gross_relative = 5 / 3,
        scale = 3.0,
        nonpositive_fraction = 0.0,
    )
    CA.write_tag_closure!(dir, 0.0, "energy_source", closure)
    path = CA.tag_closure_path(dir, "energy_source")
    @test basename(path) == "energy_source_tag_closure.csv"
    @test isfile(path)
    @test path != CA.tag_closure_path(dir, "energy")

    # A check with a spin-up reference writes three more columns, `NaN` until
    # the reference is taken and the residual since afterwards.
    reference_dir = mktempdir()
    reference = Ref{Any}(nothing)
    CA.write_tag_closure!(reference_dir, 0.0, "energy_source", closure; reference)
    reference[] = 0.25
    CA.write_tag_closure!(
        reference_dir,
        86400.0,
        "energy_source",
        closure;
        reference,
    )
    lines = readlines(CA.tag_closure_path(reference_dir, "energy_source"))
    @test endswith(
        lines[1],
        "residual_at_spin_up,residual_since_spin_up,relative_since_spin_up",
    )
    before = parse.(Float64, split(lines[2], ","))
    after = parse.(Float64, split(lines[3], ","))
    @test length(before) == length(after) == 12
    @test all(isnan, before[10:12])
    @test after[10] == 0.25
    @test after[11] == closure.residual - 0.25
    @test after[12] == (closure.residual - 0.25) / closure.scale

    # An identically zero parent gives a zero ratio, as the other columns do,
    # and not `Inf` or `NaN`.
    zero_dir = mktempdir()
    zero_closure = merge(closure, (; scale = 0.0))
    CA.write_tag_closure!(zero_dir, 0.0, "energy_source", zero_closure; reference)
    zero_row =
        parse.(
            Float64,
            split(readlines(CA.tag_closure_path(zero_dir, "energy_source"))[2], ","),
        )
    @test zero_row[11] == closure.residual - 0.25
    @test zero_row[12] == 0
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
        scale = 3.0,
        nonpositive_fraction = 0.0,
    )
    CA.write_tag_closure!(dir, 0.0, "water", closure)
    CA.write_tag_closure!(dir, 86400.0, "water", closure)

    path = CA.tag_closure_path(dir, "water")
    @test isfile(path)
    rows = readlines(path)
    # Header written once, then one row per call.
    @test rows[1] ==
          "time,total,tagged,residual,relative,gross_residual," *
          "gross_relative,scale,nonpositive_fraction"
    @test length(rows) == 3
    @test startswith(rows[2], "0.0,3.0,2.0,1.0,")
    @test endswith(rows[2], ",5.0,$(5 / 3),3.0,0.0")
    @test startswith(rows[3], "86400.0,")
    # Every header column is filled in.
    @test all(row -> length(split(row, ",")) == 9, rows)
end

@testset "Audit table" begin
    dir = mktempdir()
    audit = (;
        untagged = 3.0,
        untagged_relative = 1.0,
        overclaimed = 2.0,
        overclaimed_relative = 2 / 3,
        orphaned = 1.0,
        orphaned_relative = 1 / 3,
        orphaned_volume_fraction = 0.25,
        nonpositive_mass = 0.5,
        nonpositive_mass_fraction = 1 / 6,
    )
    CA.write_tag_audit!(dir, 0.0, "water", audit)
    CA.write_tag_audit!(dir, 86400.0, "water", audit)

    path = CA.tag_audit_path(dir, "water")
    @test basename(path) == "water_tag_audit.csv"
    @test isfile(path)
    # A file of its own, so turning the audit on leaves the schema of the
    # closure table alone for whatever already reads it.
    @test path != CA.tag_closure_path(dir, "water")
    @test !isfile(CA.tag_closure_path(dir, "water"))

    rows = readlines(path)
    @test rows[1] ==
          "time,untagged,untagged_relative,overclaimed," *
          "overclaimed_relative,orphaned,orphaned_relative," *
          "orphaned_volume_fraction,nonpositive_mass," *
          "nonpositive_mass_fraction"
    @test length(rows) == 3
    @test startswith(rows[2], "0.0,3.0,1.0,2.0,")
    @test startswith(rows[3], "86400.0,")
    # Every header column is filled in.
    @test all(row -> length(split(row, ",")) == 10, rows)

    # A family's own columns go after the common ones, under their own names.
    extra_dir = mktempdir()
    extra = (; source_negative = 9.0, source_minimum = -3.0)
    CA.write_tag_audit!(extra_dir, 0.0, "energy_source", audit; extra)
    extra_rows = readlines(CA.tag_audit_path(extra_dir, "energy_source"))
    @test endswith(
        extra_rows[1],
        ",nonpositive_mass_fraction,source_negative,source_minimum",
    )
    @test length(split(extra_rows[2], ",")) == 12
    @test endswith(extra_rows[2], ",9.0,-3.0")
end

@testset "Shipped tracer configs still build a model" begin
    # The shipped configs are the interface's real regression test. Each one
    # has to keep building the model it describes.
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

    # The energy source tags' example sets the offset they require, and its
    # layout gets the closure check by default.
    source = CA.AtmosConfig(
        joinpath(
            CA.config_path,
            "model_configs/baroclinic_wave_energy_source_tags.yml",
        );
        job_id = "baroclinic_wave_energy_source_tags",
    )
    source_model = CA.AtmosTagging(source).energy_source_tagging_model
    @test length(source_model.tags) == 7
    @test source_model.offset == eltype(source)(110495)
    @test CA.closure_checks_from_config(source).energy_source.spin_up == "1hours"
end

# `water_tag_transport`'s default (the owner's review of #102, point 1). G3_PLAN
# 4.3's rule makes the follower the default in the default mode under EDMF,
# where the configuration supports it, and keeps `tracer` elsewhere.
@testset "water_tag_transport's default" begin
    region(above) = Dict{String, Any}(
        "type" => "tanh_altitude",
        "z_center" => 750.0,
        "width" => 100.0,
        "above" => above,
    )
    partition = [
        Dict{String, Any}("name" => "tropo", "region" => region(false)),
        Dict{String, Any}("name" => "strat", "region" => region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ]
    edmf = ["turbconv" => "prognostic_edmfx"]
    config(extra, job_id; tags = partition) = tracer_config(
        ["microphysics_model" => "0M", "water_tracers" => tags, extra...];
        job_id,
    )
    transport(extra, job_id; kwargs...) =
        CA.AtmosTagging(config(extra, job_id; kwargs...)).water_tagging_model.transport
    increment = CA.IncrementWaterTagTransport
    tracer = CA.TracerWaterTagTransport
    @test transport(edmf, "water_default_edmf") isa increment
    # An explicit key overrides it, either way.
    @test transport([edmf..., "water_tag_transport" => "tracer"], "water_edmf_tracer") isa
          tracer
    @test transport(["water_tag_transport" => "increment"], "water_increment") isa
          increment
    # Elsewhere the default is `tracer`: without EDMF, with copies, without the
    # parent's post-solve correction, and without a region tag.
    @test transport([], "water_default_plain") isa tracer
    @test transport(
        [edmf..., "water_tag_updraft_copy" => true],
        "water_default_copies",
    ) isa tracer
    @test transport(
        [edmf..., "energy_q_tot_upwinding" => "none"],
        "water_default_no_correction",
    ) isa tracer
    @test transport(
        edmf,
        "water_default_sources_only";
        tags = [partition[3]],
    ) isa tracer
    # With 1M, on either path: the tags' sedimentation cross blocks let the
    # follower close the explicit path too (WP5b, FINDINGS W29).
    @test transport(
        [edmf..., "microphysics_model" => "1M", "implicit_microphysics" => false],
        "water_default_explicit_1m",
    ) isa increment
    @test transport(
        [edmf..., "microphysics_model" => "1M"],
        "water_default_implicit_1m",
    ) isa increment
    @test_throws "must be `tracer` or `increment`" CA.water_tag_transport_from_config(
        "follow",
    )
end
