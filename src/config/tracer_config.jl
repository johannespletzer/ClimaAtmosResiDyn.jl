#####
##### Tracer configuration
#####
##### The YAML → object translation for the three tracer families a user can
##### switch on:
#####
#####   `passive_tracers`  inert tracers released in fixed regions and removed
#####                      below the tropopause (`StratosphericPassiveTracers`)
#####   `water_tracers`    tags that split total water by origin (`WaterTag`)
#####   `energy_tracers`   tags that split moist energy by origin (`TracerTag`)
#####
##### Everything here reads configuration and returns model objects. The physics
##### lives elsewhere and never sees a config `Dict`:
#####
#####   - `parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl`
#####   - `parameterized_tendencies/tagged_tracers/tagged_tracers.jl`
#####   - `parameterized_tendencies/tagged_tracers/tagged_water.jl`
#####
##### Which processes may be named in a `source` is a statement about which
##### tendencies have an attribution bracket, so `KNOWN_TAG_SOURCES`,
##### `TAG_SOURCE_GROUPS`, `KNOWN_WATER_TAG_SOURCES` and
##### `WATER_TAG_SOURCE_GROUPS` stay with the physics too. This file only reads
##### them.
#####
##### User documentation: `docs/src/tracer_configuration.md`.

# ============================================================================
# Validating nested mappings
# ============================================================================
#
# `strict_config` checks top-level key names only, so without these a
# misspelled key inside a nested block is silently dropped. Every nested block
# below goes through `checked_mapping`, so a typo names itself.

"""
    config_mapping(value, context)

Return `value` as a config mapping, erroring unless it is one. `context` names
the block for the error message, e.g. `"`passive_tracers.release_grid`"`.
"""
function config_mapping(value, context)
    value isa AbstractDict || error(
        "$context must be a mapping of `key: value` pairs, got a $(typeof(value)).",
    )
    return value
end

# `` `a`, `b` ``, for listing key names in an error message.
quoted_keys(keys) = join(map(k -> "`$k`", keys), ", ")

"""
    checked_mapping(value, context; required = (), optional = ())

Validate one nested configuration block and return it.

`value` must be a mapping, it must carry every key in `required`, and it must
carry nothing outside `required` and `optional`.

Unknown keys and missing keys are reported together, unknown ones first. A
misspelling breaks both rules at once — writing `widht` invents a key and
removes `width` — and naming what was actually typed is the half that says what
to fix. Reporting only the missing key would send the reader looking for a key
they thought they had written.
"""
function checked_mapping(value, context; required = (), optional = ())
    spec = config_mapping(value, context)
    allowed = sort(unique(string.((required..., optional...))))
    unknown = sort(setdiff(string.(keys(spec)), allowed))
    absent = sort([string(k) for k in required if !haskey(spec, k)])
    isempty(unknown) && isempty(absent) && return spec

    problems = String[]
    isempty(unknown) || push!(
        problems,
        "has unknown $(length(unknown) == 1 ? "key" : "keys") \
        $(quoted_keys(unknown))",
    )
    isempty(absent) || push!(problems, "is missing $(quoted_keys(absent))")
    return error(
        "$context $(join(problems, " and ")). " *
        "Allowed keys: $(quoted_keys(allowed)).",
    )
end

"""
    parse_bounds(spec, key, context, FT)

Read a `key: [lower, upper]` pair out of `spec` as a `Tuple{FT, FT}`.

Ranges are written as two-element lists so that a box reads as the two numbers
it is, rather than as four separate keys.
"""
function parse_bounds(spec, key, context, ::Type{FT}) where {FT}
    value = spec[key]
    (value isa AbstractVector && length(value) == 2) || error(
        "$context `$key` must be a two-element list `[lower, upper]`, " *
        "got $(repr(value)).",
    )
    return (FT(value[1]), FT(value[2]))
end

# ============================================================================
# Tag regions
# ============================================================================

"""
    NAMED_TAG_REGIONS

Plain-language names usable wherever a tag `region` is expected, so that a first
configuration needs no `tanh` parameters.

  - `everywhere`: the whole domain
  - `tropics`: within 20° of the equator
  - `extratropics`: the exact complement of `tropics`

`tropics` and `extratropics` are a partition of unity, which is what the closure
diagnostics `e_tag_res` and `q_tag_res` need — they sum *all* pure region tags,
so a run should configure exactly one partition.

The set is deliberately small. A hemisphere is missing because no existing
region type can express one: [`TanhLatitudeRegion`](@ref) is symmetric about the
equator, and [`TanhBoxRegion`](@ref) degenerates over a full 360° of longitude.

Anything else is written out in full; see [`tag_region_from_config`](@ref).
"""
const NAMED_TAG_REGIONS = (
    "everywhere" => Dict("type" => "everywhere"),
    "tropics" => Dict(
        "type" => "tanh_latitude",
        "lat_bound" => 20.0,
        "width" => 2.0,
    ),
    "extratropics" => Dict(
        "type" => "tanh_latitude",
        "lat_bound" => 20.0,
        "width" => 2.0,
        "inside" => false,
    ),
)

"""
    named_tag_region(name)

Expand one of [`NAMED_TAG_REGIONS`](@ref) into the equivalent explicit `region`
mapping, or error listing the names that exist.
"""
function named_tag_region(name)
    for (candidate, spec) in NAMED_TAG_REGIONS
        candidate == name && return spec
    end
    known = join(map(pair -> "`$(first(pair))`", NAMED_TAG_REGIONS), ", ")
    return error(
        "Unknown region name `$name`. Named regions: $known. " *
        "Anything else is written out in full, e.g. " *
        "`region: {type: tanh_latitude, lat_bound: 30.0, width: 2.0}`.",
    )
end

"""
    tag_region_from_config(region_config, FT)

Convert the `region` entry of a `water_tracers` or `energy_tracers` config item
into an `AbstractTagRegion` (or `nothing` when the entry is absent).

The entry is either one of the names in [`NAMED_TAG_REGIONS`](@ref), or a
mapping carrying a `type`:

  - `"everywhere"`: mask is 1 in the whole domain
  - `"tanh_altitude"`: `(1 + tanh((z - z_center) / width)) / 2` (or its exact
    complement when `above: false`); requires `z_center` and `width` in meters
  - `"tanh_latitude"`: smooth band `|lat| ≲ lat_bound` (or its complement when
    `inside: false`); requires `lat_bound` and `width` in degrees
  - `"tanh_box"`: smooth longitude–latitude box; requires `lon_min`,
    `lon_max`, `lat_min`, `lat_max`, and `width`, all in degrees
  - `"tanh_polygon"`: smooth arbitrary polygon (e.g. an IPCC AR6 / ATLAS
    reference region); requires `vertices` (a list of `[lon, lat]` pairs in
    degrees) and `width`

All region types accept `inside: false` (`above: false` for
`"tanh_altitude"`) to select the exact complement of the mask.
"""
tag_region_from_config(::Nothing, ::Type{FT}) where {FT} = nothing

tag_region_from_config(name::AbstractString, ::Type{FT}) where {FT} =
    tag_region_from_config(named_tag_region(name), FT)

function tag_region_from_config(region_config, ::Type{FT}) where {FT}
    spec = config_mapping(region_config, "A tracer `region`")
    haskey(spec, "type") || error(
        "A tracer `region` must give a `type`, or use one of the named " *
        "regions $(join(map(pair -> "`$(first(pair))`", NAMED_TAG_REGIONS), ", ")).",
    )
    region_type = spec["type"]
    context = "A `$region_type` region"
    if region_type == "everywhere"
        checked_mapping(spec, context; required = ("type",))
        return EntireDomain()
    elseif region_type == "tanh_altitude"
        checked_mapping(
            spec,
            context;
            required = ("type", "z_center", "width"),
            optional = ("above",),
        )
        return TanhAltitudeRegion(
            FT(spec["z_center"]),
            FT(spec["width"]),
            Bool(get(spec, "above", true)),
        )
    elseif region_type == "tanh_latitude"
        checked_mapping(
            spec,
            context;
            required = ("type", "lat_bound", "width"),
            optional = ("inside",),
        )
        return TanhLatitudeRegion(
            FT(spec["lat_bound"]),
            FT(spec["width"]),
            Bool(get(spec, "inside", true)),
        )
    elseif region_type == "tanh_box"
        checked_mapping(
            spec,
            context;
            required = (
                "type", "lon_min", "lon_max", "lat_min", "lat_max", "width",
            ),
            optional = ("inside",),
        )
        return TanhBoxRegion(
            FT(spec["lon_min"]),
            FT(spec["lon_max"]),
            FT(spec["lat_min"]),
            FT(spec["lat_max"]),
            FT(spec["width"]),
            Bool(get(spec, "inside", true)),
        )
    elseif region_type == "tanh_polygon"
        checked_mapping(
            spec,
            context;
            required = ("type", "vertices", "width"),
            optional = ("inside",),
        )
        vertices = spec["vertices"]
        length(vertices) >= 3 ||
            error("`tanh_polygon` regions require at least 3 vertices.")
        vertex_tuple = Tuple(
            map(vertices) do vertex
                length(vertex) == 2 || error(
                    "Each `tanh_polygon` vertex must be a `[lon, lat]` pair, " *
                    "got $(vertex).",
                )
                (FT(vertex[1]), FT(vertex[2]))
            end,
        )
        return TanhPolygonRegion(
            vertex_tuple,
            FT(spec["width"]),
            Bool(get(spec, "inside", true)),
        )
    else
        error(
            """Unknown tracer region type `$region_type`. Expected: \
            "everywhere" | "tanh_altitude" | "tanh_latitude" | "tanh_box" | \
            "tanh_polygon".""",
        )
    end
end

# ============================================================================
# Tag sources
# ============================================================================

"""
    tag_sources_from_config(source_config, name, known = KNOWN_TAG_SOURCES,
                            groups = TAG_SOURCE_GROUPS)

Convert the `source` entry of an `energy_tracers` (or `water_tracers`) config
item into a `Tuple` of process labels. Accepts `nothing` (no sources), a single
string, or a list of strings; each string is either a process in `known` or a
group in `groups`, which expands to its members. Duplicates (e.g. from
overlapping groups) are removed.

`known` and `groups` are arguments rather than hard-coded so that the water tags
can reuse this parser with their own, different source table (see
[`KNOWN_WATER_TAG_SOURCES`](@ref)).
"""
tag_sources_from_config(
    ::Nothing,
    name,
    known = KNOWN_TAG_SOURCES,
    groups = TAG_SOURCE_GROUPS,
) = ()
function tag_sources_from_config(
    source_config,
    name,
    known = KNOWN_TAG_SOURCES,
    groups = TAG_SOURCE_GROUPS,
)
    entries =
        source_config isa AbstractString ? (source_config,) :
        Tuple(source_config)
    sources = Symbol[]
    for entry in entries
        key = Symbol(entry)
        key === :none && continue
        if haskey(groups, key)
            append!(sources, getproperty(groups, key))
        elseif key in known
            push!(sources, key)
        else
            error(
                "Unknown tracer source `$key` for tag `$name`. " *
                "Supported processes: $(join(known, ", ")). " *
                "Supported groups: $(join(keys(groups), ", ")).",
            )
        end
    end
    return Tuple(unique(sources))
end

# ============================================================================
# Water and energy tracers
# ============================================================================

"""
    tracer_tag_tuple(entries, FT; tag_type, key, known, groups)

Shared reader for the `water_tracers` and `energy_tracers` lists, which have the
same entry schema: a unique `name`, plus a `region`, a `source`, or both.

`tag_type` is [`TracerTag`](@ref) or [`WaterTag`](@ref), `key` is the config key
being read (used in error messages), and `known` / `groups` are that family's
source tables.
"""
function tracer_tag_tuple(
    entries,
    ::Type{FT};
    tag_type,
    key,
    known,
    groups,
) where {FT}
    entries isa AbstractVector || error(
        "`$key` must be a list of tracer entries, got a $(typeof(entries)).",
    )
    tags = map(enumerate(collect(entries))) do (index, entry)
        context = "`$key` entry $index"
        spec = checked_mapping(
            entry,
            context;
            required = ("name",),
            optional = ("region", "source"),
        )
        name = Symbol(spec["name"])
        region = tag_region_from_config(get(spec, "region", nothing), FT)
        sources =
            tag_sources_from_config(get(spec, "source", nothing), name, known, groups)
        if isnothing(region) && isempty(sources)
            error(
                "Tracer `$name` in `$key` must specify a `region`, a `source`, \
                or both.",
            )
        end
        return tag_type{name}(region, sources)
    end
    names = map(tag_name, tags)
    allunique(names) || error("Names in `$key` must be unique; got $(names).")
    return Tuple(tags)
end

"""
    energy_tracer_tuple(entries, FT)

Convert the parsed `energy_tracers` config entries into a `Tuple` of
[`TracerTag`](@ref)s suitable for constructing a [`TaggingModel`](@ref).
"""
energy_tracer_tuple(entries, ::Type{FT}) where {FT} = tracer_tag_tuple(
    entries,
    FT;
    tag_type = TracerTag,
    key = "energy_tracers",
    known = KNOWN_TAG_SOURCES,
    groups = TAG_SOURCE_GROUPS,
)

"""
    water_tracer_tuple(entries, FT)

Convert the parsed `water_tracers` config entries into a `Tuple` of
[`WaterTag`](@ref)s suitable for constructing a [`WaterTaggingModel`](@ref).
"""
water_tracer_tuple(entries, ::Type{FT}) where {FT} = tracer_tag_tuple(
    entries,
    FT;
    tag_type = WaterTag,
    key = "water_tracers",
    known = KNOWN_WATER_TAG_SOURCES,
    groups = WATER_TAG_SOURCE_GROUPS,
)

# ============================================================================
# Closure checking
# ============================================================================

"""
    DEFAULT_CLOSURE_TOLERANCES

Default relative-residual tolerance of each tag family's closure check.

The two differ by four orders of magnitude on purpose. The water tags ride the
same transport operators as `ρq_tot` apart from the implicit-vs-explicit
vertical advection split, so their residual is small. The energy tags never
receive implicit transport or EDMFX SGS mass fluxes at all, which is by design
(see `KNOWN_TAG_SOURCES`), so a much larger residual is expected and normal.

These are starting points, not derived numbers. Read the first run's closure
table and set a tolerance that sits above the level your configuration settles
at, so that the warning means something changed.
"""
const DEFAULT_CLOSURE_TOLERANCES = (; water = 1.0e-10, energy = 1.0e-6)

"""
    closure_check_from_config(spec_value, context, FT; default_tolerance)

Read a `water_closure_check` or `energy_closure_check` block into
`(; period, tolerance)`, or `nothing` when the key is absent.

Both keys are optional: `period` defaults to `"1days"` and `tolerance` to the
family's entry in [`DEFAULT_CLOSURE_TOLERANCES`](@ref).
"""
closure_check_from_config(
    ::Nothing,
    context,
    ::Type{FT};
    default_tolerance,
) where {FT} = nothing

function closure_check_from_config(
    spec_value,
    context,
    ::Type{FT};
    default_tolerance,
) where {FT}
    spec = checked_mapping(
        spec_value,
        context;
        optional = ("period", "tolerance"),
    )
    period = get(spec, "period", "1days")
    isfinite(time_to_seconds(period)) || error(
        "$context `period` must be finite; an infinite period never checks \
        anything, which is what leaving the block out already does.",
    )
    tolerance = FT(get(spec, "tolerance", default_tolerance))
    tolerance >= 0 || error(
        "$context `tolerance` must not be negative, got $tolerance. It is \
        compared against the absolute value of the relative residual.",
    )
    return (; period, tolerance)
end

"""
    closure_checks_from_config(config::AtmosConfig)

Read both closure-check blocks, as `(; water, energy)`.
"""
function closure_checks_from_config(config::AtmosConfig)
    pa = config.parsed_args
    FT = eltype(config)
    return (;
        water = closure_check_from_config(
            pa["water_closure_check"],
            "`water_closure_check`",
            FT;
            default_tolerance = DEFAULT_CLOSURE_TOLERANCES.water,
        ),
        energy = closure_check_from_config(
            pa["energy_closure_check"],
            "`energy_closure_check`",
            FT;
            default_tolerance = DEFAULT_CLOSURE_TOLERANCES.energy,
        ),
    )
end

"""
    AtmosTagging(config::AtmosConfig)

Assemble the `AtmosTagging` group from the `energy_tracers` and `water_tracers`
config keys. Either being `~` (null) or an empty list disables that family
entirely, at no runtime cost.
"""
function AtmosTagging(config::AtmosConfig)
    FT = eltype(config)
    entries = config.parsed_args["energy_tracers"]
    tagging_model = if isnothing(entries) || isempty(entries)
        nothing
    else
        TaggingModel(energy_tracer_tuple(entries, FT))
    end
    water_entries = config.parsed_args["water_tracers"]
    water_tagging_model = if isnothing(water_entries) || isempty(water_entries)
        nothing
    else
        check_water_tagging_supported(
            get_microphysics_model(config.parsed_args),
        )
        WaterTaggingModel(water_tracer_tuple(water_entries, FT))
    end
    return AtmosTagging(; tagging_model, water_tagging_model)
end

# ============================================================================
# Passive tracers
# ============================================================================

"""
    parse_release_boxes(box_specs, FT)

Turn the `passive_tracers: release_boxes` entry into a vector of
[`SourceBox`](@ref)es.

Each entry is a mapping with `latitude: [lower, upper]` in degrees and
`height: [lower, upper]` in m, measured from the reference chosen by
`heights_from`. A box that should span exactly one model layer takes that
layer's face heights.
"""
function parse_release_boxes(box_specs, ::Type{FT}) where {FT}
    box_specs isa AbstractVector || error(
        "`passive_tracers: release_boxes` must be a list of boxes, got a \
        $(typeof(box_specs)).",
    )
    isempty(box_specs) &&
        error("`passive_tracers: release_boxes` must list at least one box.")
    return map(enumerate(collect(box_specs))) do (index, box_spec)
        context = "`passive_tracers: release_boxes` entry $index"
        spec = checked_mapping(
            box_spec,
            context;
            required = ("latitude", "height"),
        )
        latitude = parse_bounds(spec, "latitude", context, FT)
        height = parse_bounds(spec, "height", context, FT)
        SourceBox(latitude[1], latitude[2], height[1], height[2])
    end
end

"""
    parse_release_grid(grid_spec, FT)

Turn the `passive_tracers: release_grid` entry into the keyword arguments of the
grid constructor of [`StratosphericPassiveTracers`](@ref).

Every key is optional; an omitted key keeps that constructor's default.
"""
function parse_release_grid(grid_spec, ::Type{FT}) where {FT}
    context = "`passive_tracers: release_grid`"
    spec = checked_mapping(
        grid_spec,
        context;
        optional = (
            "latitude_bands",
            "latitude_width",
            "height_bands",
            "height_depth",
            "height_spacing",
            "lowest_height",
        ),
    )
    # The constructor supplies the defaults, so only what was set is forwarded.
    keywords = Dict{Symbol, Any}()
    haskey(spec, "latitude_bands") &&
        (keywords[:n_latitude_bands] = Int(spec["latitude_bands"]))
    haskey(spec, "height_bands") &&
        (keywords[:n_height_bands] = Int(spec["height_bands"]))
    haskey(spec, "latitude_width") &&
        (keywords[:latitude_width] = FT(spec["latitude_width"]))
    haskey(spec, "height_depth") &&
        (keywords[:band_depth] = FT(spec["height_depth"]))
    haskey(spec, "height_spacing") &&
        (keywords[:band_spacing] = FT(spec["height_spacing"]))
    haskey(spec, "lowest_height") &&
        (keywords[:lowest_band_base] = FT(spec["lowest_height"]))
    return keywords
end

"""
    parse_tropopause(tropopause_spec, FT)

Turn the `passive_tracers: tropopause` entry into [`TropopauseParameters`](@ref).
`nothing` (the key omitted) gives the defaults.
"""
parse_tropopause(::Nothing, ::Type{FT}) where {FT} = TropopauseParameters{FT}()
function parse_tropopause(tropopause_spec, ::Type{FT}) where {FT}
    context = "`passive_tracers: tropopause`"
    spec = checked_mapping(
        tropopause_spec,
        context;
        optional = (
            "lapse_rate_threshold",
            "consistency_depth",
            "search_min_height",
            "search_max_height",
        ),
    )
    defaults = TropopauseParameters{FT}()
    return TropopauseParameters{FT}(;
        lapse_rate_threshold = FT(
            get(spec, "lapse_rate_threshold", defaults.lapse_rate_threshold),
        ),
        consistency_depth = FT(
            get(spec, "consistency_depth", defaults.consistency_depth),
        ),
        search_min_height = FT(
            get(spec, "search_min_height", defaults.search_min_height),
        ),
        search_max_height = FT(
            get(spec, "search_max_height", defaults.search_max_height),
        ),
    )
end

"""
    passive_tracer_model(passive_spec, FT)

Build the [`StratosphericPassiveTracers`](@ref) model from the `passive_tracers`
config block.

Release regions come from either `release_grid` (a regular latitude × height
grid) or `release_boxes` (an explicit list). Exactly one is required.

Setting both is an error: they describe the same thing two ways, and silently
preferring one would hide half the configuration. Setting neither is an error
too, rather than falling back to the grid constructor's 6 × 8 default — 48
tracers is hours of setup, which is not something to arrive at by omission.
"""
function passive_tracer_model(passive_spec, ::Type{FT}) where {FT}
    context = "`passive_tracers`"
    spec = checked_mapping(
        passive_spec,
        context;
        optional = (
            "release_grid",
            "release_boxes",
            "heights_from",
            "production_rate",
            "loss_timescale",
            "tropopause",
        ),
    )

    has_grid = haskey(spec, "release_grid")
    has_boxes = haskey(spec, "release_boxes")
    has_grid &&
        has_boxes &&
        error(
            "$context sets both `release_grid` and `release_boxes`. Use " *
            "`release_grid` for a regular latitude × height grid, or " *
            "`release_boxes` to list the boxes explicitly, but not both.",
        )
    has_grid ||
        has_boxes ||
        error(
            "$context must say where the tracers are released, with either " *
            "`release_grid` (a regular latitude × height grid) or " *
            "`release_boxes` (an explicit list of boxes).",
        )

    heights_from = get(spec, "heights_from", "tropopause")
    height_coordinate = if heights_from == "tropopause"
        TropopauseRelativeHeight()
    elseif heights_from == "altitude"
        GeometricHeight()
    else
        error(
            """$context `heights_from` is `$heights_from`; expected \
            "tropopause" (regions follow the local tropopause) or "altitude" \
            (fixed heights above sea level).""",
        )
    end

    loss_timescale = time_to_seconds(get(spec, "loss_timescale", "6hours"))
    isfinite(loss_timescale) || error(
        "$context `loss_timescale` must be finite; an infinite timescale " *
        "removes the tracers' only sink, so they never reach equilibrium.",
    )

    production_rate = FT(get(spec, "production_rate", 1.0e-10))
    tropopause = parse_tropopause(get(spec, "tropopause", nothing), FT)

    shared = (; production_rate, loss_timescale, height_coordinate, tropopause)

    has_boxes && return StratosphericPassiveTracers(
        FT,
        parse_release_boxes(spec["release_boxes"], FT);
        shared...,
    )

    grid = parse_release_grid(spec["release_grid"], FT)
    return StratosphericPassiveTracers(FT; grid..., shared...)
end

"""
    AtmosChem(config::AtmosConfig)

Assemble the `AtmosChem` group from a configuration.

`chemistry_model` accepts `~` (null) for no chemistry or `"passive"` for
`GasPhaseChem`, the gas-phase hook whose tendency comes from the
`ClimaAtmosMusica` extension. `passive_tracers` selects the inert stratospheric
tracers instead. Both fill the same slot, so setting both is an error.
"""
function AtmosChem(config::AtmosConfig)
    pa = config.parsed_args
    FT = eltype(config)
    chem = pa["chemistry_model"]
    passive_spec = pa["passive_tracers"]

    if !isnothing(chem) && !isnothing(passive_spec)
        error(
            "`chemistry_model: $(repr(chem))` and `passive_tracers` cannot " *
            "both be set; a run carries one chemistry model.",
        )
    end

    chemistry_model = if !isnothing(passive_spec)
        passive_tracer_model(passive_spec, FT)
    elseif isnothing(chem)
        nothing
    elseif chem == "passive"
        GasPhaseChem()
    else
        error(
            """Unknown chemistry_model `$chem`. Expected: ~ | "passive". \
            For the inert stratospheric tracers, use the `passive_tracers` \
            configuration key.""",
        )
    end
    return AtmosChem(; chemistry_model)
end
