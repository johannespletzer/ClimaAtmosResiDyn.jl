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
##### Everything here reads configuration and returns model objects. This is the
##### only place that touches a config `Dict`, so the physics works from model
##### objects alone:
#####
#####   - `parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl`
#####   - `parameterized_tendencies/tagged_tracers/tagged_tracers.jl`
#####   - `parameterized_tendencies/tagged_tracers/tagged_water.jl`
#####
##### The names a user may put in a `source` are exactly the tendencies with an
##### attribution bracket. That makes the lists a property of the physics, so
##### `KNOWN_TAG_SOURCES`, `TAG_SOURCE_GROUPS`, `KNOWN_WATER_TAG_SOURCES` and
##### `WATER_TAG_SOURCE_GROUPS` live with it. This file reads them.
#####
##### User documentation: `docs/src/tracer_configuration.md`.

# ============================================================================
# Validating nested mappings
# ============================================================================
#
# `strict_config` checks top-level key names only. Every nested block below goes
# through `checked_mapping` as well, so a key misspelled inside a block names
# itself instead of being dropped in silence.

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

"""
    parse_smoothing_width(spec, context, FT)

Read the `width` of a `tanh` region out of `spec`, erroring unless it is
positive.

`width` divides the distance to the region edge, so a zero width is not a sharp
region but an undefined one: away from the edge the mask becomes a step, which
is the Gibbs case the smoothing exists to prevent, and a point sitting exactly
on the edge evaluates `0/0` and gives `NaN`. One `NaN` in a static mask spreads
through the tagged field on the first step.

A negative width does something different to each shape of mask, none of it
what was meant:

  - `tanh_altitude` and `tanh_polygon` are a single `tanh`, so the sign gives
    the exact complement — the wrong region, but still a mask in `[0, 1]`.
  - `tanh_latitude` is a *difference* of two, so the sign negates it: the mask
    reaches `-1` where it should reach 1, and the tag holds a negative share of
    the parent field.
  - `tanh_box` is a *product* of two such differences, so the two sign flips
    cancel and the mask is unchanged. The width is silently read as its own
    absolute value, which is the quietest failure of the three.
"""
function parse_smoothing_width(spec, context, ::Type{FT}) where {FT}
    width = FT(spec["width"])
    width > 0 || error(
        "$context needs a positive `width`, got $width. The width is the \
        distance over which the edge is smoothed, so zero leaves a sharp mask \
        (and `NaN` exactly on the edge). A negative width is wrong in a \
        different way for each region type: it complements `tanh_altitude` \
        and `tanh_polygon`, negates `tanh_latitude` so the mask reaches -1, \
        and does nothing at all to `tanh_box`, whose two sign flips cancel.",
    )
    return width
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

Every type except `"everywhere"` accepts `inside: false` (`above: false` for
`"tanh_altitude"`) to select the exact complement of the mask. The whole domain
has no complement, so `"everywhere"` takes no key besides `type`.

Parameters that would define no region are refused here rather than left to
produce a mask that is silently wrong: every `width` must be positive,
`lat_bound` must be positive, a box needs `lat_min` below `lat_max`, and a box
must span some longitude. A non-positive `width` is the one worth spelling out:
it does not make a sharp region, it makes an undefined one, because a point
sitting exactly on the edge evaluates `0/0`.
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
            parse_smoothing_width(spec, context, FT),
            Bool(get(spec, "above", true)),
        )
    elseif region_type == "tanh_latitude"
        checked_mapping(
            spec,
            context;
            required = ("type", "lat_bound", "width"),
            optional = ("inside",),
        )
        width = parse_smoothing_width(spec, context, FT)
        lat_bound = FT(spec["lat_bound"])
        # The band is `tanh((lat + b)/w) - tanh((lat - b)/w)`, all over 2. That
        # is zero everywhere when `b` is zero, and negative everywhere when `b`
        # is negative -- a tag holding a negative share of the parent field.
        lat_bound > 0 || error(
            "$context needs a positive `lat_bound`, got $lat_bound. The band \
            is `|lat| <= lat_bound`, so zero makes it empty and a negative \
            bound makes the mask itself negative.",
        )
        return TanhLatitudeRegion(
            lat_bound,
            width,
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
        width = parse_smoothing_width(spec, context, FT)
        lon_min, lon_max = FT(spec["lon_min"]), FT(spec["lon_max"])
        lat_min, lat_max = FT(spec["lat_min"]), FT(spec["lat_max"])
        lat_min < lat_max || error(
            "$context needs `lat_min` below `lat_max`, got $lat_min and \
            $lat_max. Equal bounds make the mask zero everywhere, and \
            reversed bounds make it negative.",
        )
        # Longitudes are compared modulo 360 so that a box may cross the
        # antimeridian, which leaves a full turn indistinguishable from no
        # turn: `mod(180 - -180, 360)` is 0, and the mask is zero everywhere.
        mod(lon_max - lon_min, 360) > 0 || error(
            "$context spans no longitude: `lon_min` and `lon_max` are $lon_min \
            and $lon_max, a whole number of turns apart, so the mask is zero \
            everywhere. Longitudes are compared modulo 360 -- which is what \
            lets a box cross the antimeridian -- so a full 360-degree box \
            cannot be told from an empty one. For a band that covers every \
            longitude and is symmetric about the equator, use a \
            `tanh_latitude` region instead.",
        )
        return TanhBoxRegion(
            lon_min,
            lon_max,
            lat_min,
            lat_max,
            width,
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
            parse_smoothing_width(spec, context, FT),
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

"""
    tag_region_spec(region)

The configuration `region` is built from, as `type` and then the type's keys in
the order the type declares them, each a `String => value` pair. The values
keep the region's own float type. It is the inverse of
[`tag_region_from_config`](@ref): `Dict(tag_region_spec(region))` reads back
to the same region, in `Float64` and in `Float32`. The restart guard writes it
into a checkpoint in the words a configuration uses, so that a changed region
can be named. A named region such as `tropics` comes back as its mapping.
"""
tag_region_spec(::EntireDomain) = ["type" => "everywhere"]
tag_region_spec(region::TanhAltitudeRegion) = [
    "type" => "tanh_altitude",
    "z_center" => region.z_center,
    "width" => region.width,
    "above" => region.above,
]
tag_region_spec(region::TanhLatitudeRegion) = [
    "type" => "tanh_latitude",
    "lat_bound" => region.lat_bound,
    "width" => region.width,
    "inside" => region.inside,
]
tag_region_spec(region::TanhBoxRegion) = [
    "type" => "tanh_box",
    "lon_min" => region.lon_min,
    "lon_max" => region.lon_max,
    "lat_min" => region.lat_min,
    "lat_max" => region.lat_max,
    "width" => region.width,
    "inside" => region.inside,
]
tag_region_spec(region::TanhPolygonRegion) = [
    "type" => "tanh_polygon",
    "vertices" => [[lon, lat] for (lon, lat) in region.vertices],
    "width" => region.width,
    "inside" => region.inside,
]

"""
    tag_region_text(region)

`region` on one line, in the words of its configuration, for example
`tanh_altitude(z_center = 750.0, width = 100.0, above = true)`, and
`everywhere` for the whole domain. `none` for a tag without a region. Numbers
print in the region's own float type, the shortest text that reads back to the
same value, so a `Float32` region prints `750.3` and not its `Float64` widening.
"""
tag_region_text(::Nothing) = "none"
function tag_region_text(region)
    spec = tag_region_spec(region)
    type = last(first(spec))
    length(spec) == 1 && return type
    keys = join(
        (string(key, " = ", region_value_text(value)) for (key, value) in spec[2:end]),
        ", ",
    )
    return string(type, "(", keys, ")")
end
region_value_text(value) = string(value)
region_value_text(values::AbstractVector) =
    string("[", join(map(region_value_text, values), ", "), "]")

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
    RESERVED_WATER_TAG_PREFIXES

Name prefixes that a `water_tracers` tag may not take. A tag's diagnostic is
`q_tag_<name>`. `fix_` starts the ledger `q_tag_fix_<name>` of the limiters
and constraints, so a tag named `fix_a` would take the name of tag `a`'s
ledger, and the first registered diagnostic would win silently. `upfix_` is
held for the updraft copies' repair ledger, which collides the same way.
`inc_` is held for an increment follower's ledgers, `q_tag_inc_left` and
`q_tag_inc_moved`. `rtag_` and `stag_` are held for the rain and snow parts,
whose output names are not fixed yet. Refusing them now keeps configurations
valid when those diagnostics arrive. `fixgross_`, `fixcount_`, `upfixgross_`
and `upfixcount_` start the ledgers' gross twins and counts, and `led_` the
ledgers per mechanism, `q_tag_led_rescale` and the others.
"""
const RESERVED_WATER_TAG_PREFIXES = (
    "fix_",
    "upfix_",
    "inc_",
    "rtag_",
    "stag_",
    "fixgross_",
    "fixcount_",
    "upfixgross_",
    "upfixcount_",
    "led_",
)

"""
    RESERVED_ENERGY_SOURCE_TAG_PREFIXES

Name prefixes that an `energy_source_tags` tag may not take, for the reason
`RESERVED_WATER_TAG_PREFIXES` gives. A tag's diagnostic is
`e_src_<name>`, and `fix_` starts the repair's ledger `e_src_fix_<name>`,
`fixgross_` and `fixcount_` its gross twin and count, `inc_` the
increment correction's ledger `e_src_inc_left` and `e_src_inc_moved`, and
`led_` the repair's ledger per mechanism `e_src_led_repair`.
"""
const RESERVED_ENERGY_SOURCE_TAG_PREFIXES =
    ("fix_", "fixgross_", "fixcount_", "inc_", "led_")

"""
    tracer_tag_tuple(entries, FT; tag_type, key, known, groups, reserved_prefixes = ())

Shared reader for the `water_tracers` and `energy_tracers` lists, which have the
same entry schema: a unique `name`, plus a `region`, a `source`, or both.

`tag_type` is [`TracerTag`](@ref) or [`WaterTag`](@ref), `key` is the config key
being read (used in error messages), and `known` / `groups` are that family's
source tables. A name starting with one of `reserved_prefixes` is refused.
"""
function tracer_tag_tuple(
    entries,
    ::Type{FT};
    tag_type,
    key,
    known,
    groups,
    reserved_prefixes = (),
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
    # `res` is taken by the closure residual. Every family registers its
    # per-tag diagnostics first and then unconditionally deletes and re-registers
    # `<prefix>_res`, so a tag named `res` is either silently replaced by the
    # residual or, when the family has no region tags, deleted and never
    # re-registered — leaving a configured diagnostic that does not exist.
    # Cheaper to refuse the name than to make the registration order safe.
    :res in names && error(
        "`res` is a reserved tag name in `$key`: it collides with the closure \
        residual diagnostic. Choose another name.",
    )
    for name in names, prefix in reserved_prefixes
        startswith(String(name), prefix) && error(
            "Tag names starting with `$prefix` are reserved in `$key`, so \
            `$name` is refused. Such a name can take, or will be able to take, \
            the name of another diagnostic of the family. Choose another name.",
        )
    end
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
    reserved_prefixes = RESERVED_WATER_TAG_PREFIXES,
)

"""
    energy_source_tracer_tuple(entries, FT; microphysics_model = nothing)

Convert the parsed `energy_source_tags` config entries into a `Tuple` of
[`EnergySourceTag`](@ref)s suitable for constructing an
[`EnergySourceTaggingModel`](@ref).

The entry schema is the one `energy_tracers` uses, and the process labels are
the same, because a source tag and a process tag select from the same set of
bracketed processes. Only the rule applied to them differs.

Not every accepted label can actually fire here; see
[`warn_inactive_energy_source_labels`](@ref), which is called from this
function. It needs `microphysics_model` to tell which labels the scheme leaves
at zero.
"""
function energy_source_tracer_tuple(
    entries,
    ::Type{FT};
    microphysics_model = nothing,
) where {FT}
    tags = tracer_tag_tuple(
        entries,
        FT;
        tag_type = EnergySourceTag,
        key = "energy_source_tags",
        known = KNOWN_TAG_SOURCES,
        groups = TAG_SOURCE_GROUPS,
        reserved_prefixes = RESERVED_ENERGY_SOURCE_TAG_PREFIXES,
    )
    warn_inactive_energy_source_labels(tags, microphysics_model)
    return tags
end

"""
    warn_inactive_energy_source_labels(tags, microphysics_model = nothing)

Warn about `energy_source_tags` labels that cannot contribute, so a tag that
will stay at zero says so at configuration time rather than at analysis time.

The labels are shared with `energy_tracers`, but the two families do not see
the same processes. `precipitation` is the sedimentation of precipitating
species, and this family does not count it as production: sedimentation moves
energy from level to level, and the tags follow it as transport instead, each by
its share of what the losing cell holds. So a source tag listing
`precipitation` receives nothing in any configuration, while the `ρe_tag_*`
family does. Under 0-moment microphysics, rain leaves through `microphysics`
instead, which reaches this family on both tendency paths.

`microphysics` is the other label that can stay at zero. Only 0-moment
microphysics changes `ρe_tot`, through its rain-out. The 1-moment, 2-moment and
P3 schemes move water between species, and the energy leaves with
sedimentation. A dry model has no microphysics. So a tag listing `microphysics`
gets a warning under every `microphysics_model` but 0-moment. With
`microphysics_model = nothing` the scheme is not known, and there is no warning
for it.

A warning and not an error: `moist` and `all` are useful shorthands that happen
to include `precipitation` and `microphysics`, and refusing them would make the
group labels unusable for a family they otherwise serve.
"""
function warn_inactive_energy_source_labels(tags, microphysics_model = nothing)
    for tag in tags
        sources = tag.sources
        isempty(sources) && continue
        :precipitation in sources && @warn(
            "`energy_source_tags` tag `$(tag_name(tag))` lists " *
            "`precipitation`, which cannot contribute to a source tag. It is " *
            "the sedimentation of precipitating species, which moves energy " *
            "between levels rather than adding it. Where water sediments, " *
            "the tags follow it as transport instead, so nothing is credited " *
            "to `precipitation`. The `energy_tracers` family does attribute " *
            "it. Under 0-moment microphysics, rain leaves through " *
            "`microphysics` instead. Note `moist` and `all` both expand to " *
            "include `precipitation`.",
        )
        :microphysics in sources &&
            microphysics_is_inert(microphysics_model) &&
            @warn(
                "`energy_source_tags` tag `$(tag_name(tag))` lists " *
                "`microphysics`, which cannot contribute under " *
                "$(nameof(typeof(microphysics_model))). Only 0-moment " *
                "microphysics changes `ρe_tot`. The other schemes move " *
                "water between species, and the energy leaves with " *
                "sedimentation, which the tags follow as transport. Note " *
                "`moist` and `all` both expand to include `microphysics`.",
            )
    end
    return nothing
end

# Whether a microphysics model leaves the `microphysics` label with nothing to
# attribute or record. Only 0-moment microphysics changes `ρe_tot` and
# `ρq_tot`, through its rain-out. `nothing` means the model is not known.
microphysics_is_inert(::Nothing) = false
microphysics_is_inert(::EquilibriumMicrophysics0M) = false
microphysics_is_inert(::AbstractMicrophysicsModel) = true

# Whether a microphysics model sediments anything, so that `precipitation` can
# record. `nothing` means the model is not known, and then the label counts as
# inactive, as it did before the model was passed.
has_sedimentation(::Nothing) = false
has_sedimentation(::Union{DryModel, EquilibriumMicrophysics0M}) = false
has_sedimentation(::AbstractMicrophysicsModel) = true

"""
    active_energy_source_processes(atmos)

The process labels whose bracket changes `ρe_tot` in a run of `atmos`, as a
`Tuple` of `Symbol`s.

`precipitation` is never among them: for the energy source tags it is transport,
not production. `microphysics` is, only under 0-moment microphysics, whose
rain-out is the one microphysics that changes `ρe_tot`.
"""
function active_energy_source_processes(atmos)
    radiation_mode = atmos.radiation_mode
    active = (
        :radiation =>
            !isnothing(radiation_mode) && !(radiation_mode isa HeldSuarezForcing),
        :held_suarez => radiation_mode isa HeldSuarezForcing,
        :surface_flux => !atmos.disable_surface_flux_tendency,
        :subsidence => !isnothing(atmos.subsidence),
        :large_scale_advection => !isnothing(atmos.ls_adv),
        :external_forcing => !isnothing(atmos.external_forcing),
        :microphysics =>
            atmos.microphysics_model isa EquilibriumMicrophysics0M,
    )
    return Tuple(label for (label, is_active) in active if is_active)
end

"""
    warn_untagged_energy_source_processes(atmos)

Warn about each process that changes `ρe_tot` in this run and that no energy
source tag follows.

The per-process check, form A, sets the new energy split by region against the
new energy split by process. A process that produces energy and has no tag of
its own opens a gap there. That is how the tag-closure experiments found
subsidence on a column and the rain-out of cold condensate on a sphere. Checking
the labels at configuration finds the same gap before the run.

The check applies to a run that follows processes, one with at least one tag
that carries some sources but not all of them. A tag that lists every process,
through `all`, follows no process in particular, so it does not count as
following any. A run with region tags alone gets no warning, since it does not
split energy by process.
"""
function warn_untagged_energy_source_processes(atmos)
    model = atmos.energy_source_tagging_model
    isnothing(model) && return nothing
    all_labels = Set(KNOWN_TAG_SOURCES)
    process_tags = filter(collect(model.tags)) do tag
        sources = Set(tag.sources)
        !isempty(sources) && sources != all_labels
    end
    isempty(process_tags) && return nothing
    followed = Set{Symbol}()
    for tag in process_tags
        union!(followed, tag.sources)
    end
    for label in active_energy_source_processes(atmos)
        label in followed && continue
        @warn(
            "`$label` changes `ρe_tot` in this run, and no `energy_source_tags` \
            tag follows it. Its production goes to the region tags that list \
            `all`, and to no process tag, so the new energy split by process \
            misses it. Add a tag with `source: $label` to follow it.",
        )
    end
    return nothing
end

"""
    warn_unbracketed_energy_source_constraints(atmos, vwb_species = nothing)

Warn when a state constraint or a limiter changes `ρe_tot` outside every bracket
in a run with energy source tags.

Three paths clip `ρq_tot` and then move the clipped water's mass and energy into
`ρ` and `ρe_tot` through `enforce_mass_energy_consistency!`:

  - the element constraint, as `constrain_qtot` does;
  - the quasimonotone limiter, `apply_sem_quasimonotone_limiter: true`;
  - vertical water borrowing, when its species include `ρq_tot`. `vwb_species`
    is that list, as `vertical_water_borrowing_species_from_config` gives it,
    and `nothing` means every tracer.

No bracket sees that change, so no tag takes it, and it lands in `e_src_res`.
"""
function warn_unbracketed_energy_source_constraints(atmos, vwb_species = nothing)
    model = atmos.energy_source_tagging_model
    _warn_unbracketed_energy_source_constraints(
        model,
        atmos.water.tracer_nonnegativity_method,
    )
    _warn_unbracketed_energy_source_limiters(model, atmos, vwb_species)
    return nothing
end
_warn_unbracketed_energy_source_constraints(model, method) = nothing
_warn_unbracketed_energy_source_constraints(
    ::EnergySourceTaggingModel,
    ::TracerNonnegativityElementConstraint{true},
) = @warn(
    "`energy_source_tags` with a `tracer_nonnegativity_method` that clips \
    `ρq_tot`: the clip changes `ρ` and `ρe_tot` outside every bracket, so no \
    tag takes the change, and it goes to `e_src_res`.",
)

# The two limiters that clip `ρq_tot`. A dry model has no `ρq_tot` to clip.
_warn_unbracketed_energy_source_limiters(model, atmos, vwb_species) = nothing
function _warn_unbracketed_energy_source_limiters(
    ::EnergySourceTaggingModel,
    atmos,
    vwb_species,
)
    atmos.water.microphysics_model isa DryModel && return nothing
    atmos.numerics.limiter isa QuasiMonotoneLimiter && @warn(
        "`energy_source_tags` with `apply_sem_quasimonotone_limiter: true`: the \
        limiter clips `ρq_tot` and changes `ρ` and `ρe_tot` to match, outside \
        every bracket, so no tag takes the change, and it goes to `e_src_res`.",
    )
    atmos.water.tracer_nonnegativity_method isa
    TracerNonnegativityVerticalWaterBorrowing &&
        _should_apply_limiter_to_tracer(:ρq_tot, vwb_species) &&
        @warn(
            "`energy_source_tags` with `tracer_nonnegativity_method: \
            vertical_water_borrowing` on `ρq_tot`: the borrowing changes `ρ` \
            and `ρe_tot` to match, outside every bracket, so no tag takes the \
            change, and it goes to `e_src_res`.",
        )
    return nothing
end

# ============================================================================
# Closure checking
# ============================================================================

"""
    DEFAULT_CLOSURE_TOLERANCES

Default relative-residual tolerance of each tag family's closure check.

Water differs from the `energy` family by four orders of magnitude on
purpose. The water tags ride the same transport operators as `ρq_tot` apart
from the implicit-vs-explicit vertical advection split, so their residual is
small. Neither energy family receives the parent's implicit vertical advection
or the EDMFX SGS mass flux, and transport is not attributed on top, by design
(see `KNOWN_TAG_SOURCES`). So a much larger residual is expected and normal.
Sedimentation reaches both: the `ρe_tag_*` family attributes it under
`precipitation`, and the energy source tags follow it as transport of their own.

These are starting points, not derived numbers. Read the first run's closure
table and set a tolerance that sits above the level your configuration settles
at, so that the warning means something changed.

The energy source tags take their default from
[`ENERGY_SOURCE_CLOSURE_TOLERANCES`](@ref) instead, one level per transport,
because their residual depends on how the tags move. The entry here is
`nothing` so that nothing reads a single level for them.
"""
const DEFAULT_CLOSURE_TOLERANCES =
    (; water = 1.0e-10, energy = 1.0e-6, energy_source = nothing)

"""
    ENERGY_SOURCE_CLOSURE_TOLERANCES

Default `tolerance` of the energy source tags' closure check, one per
`energy_source_tag_transport`. The check compares them against
`gross_relative`, the partition's residual over the total it partitions.

They are runaway guards, not fine thresholds. Each sits above the largest value
measured in a healthy run of that transport, over the 59 runs of the
tag-closure experiments, but not by the same margin: 7.1 times for `tracer`,
1.7 for `enthalpy` and 50 for `enthalpy_increment`. The `enthalpy` margin is
the thinnest because its largest run, a rebuilt sub-grid diffusion that was
later shelved, sat far above its own typical level.

| transport            | typical | largest measured                        | default |
|:-------------------- | -------:| ---------------------------------------:| -------:|
| `tracer`             | 6e-3    | 1.4e-1                                  | 1.0     |
| `enthalpy`           | 5e-3    | 5.9e-2                                  | 0.1     |
| `enthalpy_increment` | 3e-6    | 2.0e-4 (ten days, Float32, on a sphere) | 0.01    |

The residual grows with the length of a run, so a level that suits a day is too
tight for a season. These warn only when the tags hold energy that is far from
what the parent has, which is what a broken run looks like. Read your own first
run's closure table and set `tolerance` in the block to something tighter that
means "this configuration changed".

The normalization's zero is a convention, so a level tuned under one energy
reference means something else under another.
"""
const ENERGY_SOURCE_CLOSURE_TOLERANCES =
    (; tracer = 1.0, enthalpy = 0.1, enthalpy_increment = 0.01)

"""
    energy_source_closure_tolerance(transport)

The default closure tolerance for `transport`, from
[`ENERGY_SOURCE_CLOSURE_TOLERANCES`](@ref).
"""
energy_source_closure_tolerance(::TracerEnergySourceTransport) =
    ENERGY_SOURCE_CLOSURE_TOLERANCES.tracer
energy_source_closure_tolerance(::EnthalpyEnergySourceTransport) =
    ENERGY_SOURCE_CLOSURE_TOLERANCES.enthalpy
energy_source_closure_tolerance(::EnthalpyIncrementEnergySourceTransport) =
    ENERGY_SOURCE_CLOSURE_TOLERANCES.enthalpy_increment

"""
    DEFAULT_CLOSURE_ABORT_LEVELS

Default `abort_above` level of each tag family's closure check: the relative
residual at which the run ends rather than warns, or `nothing` where no single
level means the same thing in every configuration.

Water gets `1.0`. `gross_relative` is `∫|ρq_tot - Σ tags| / ∫|ρq_tot|`, and any
set of non-negative tags that stays inside a non-negative parent misses it by at
most the parent itself, pointwise. So an honest partition cannot reach 1, and
neither can an honest strict subset of one, which leaves most of the water
untagged and drives the ratio *towards* 1 from below. Passing 1 means the tags
hold water that is not there, or the parent has gone negative. That is a broken
state rather than drift, and it is ten orders of magnitude above the level the
default `tolerance` warns at. Issue #64 is the run this level exists for: its
residual passed 1 in the fourth simulated hour and reached 1e113 by the end of
the day, while the run reported success.

Both energy families get `nothing`. Their residual is normalized by `∫|ρe_tot|`,
whose zero is a convention: a shifted energy reference can make the denominator
arbitrarily small and the ratio arbitrarily large with nothing actually wrong, so
no level transfers between configurations. Set one per run, once its closure
table shows where that run settles.
"""
const DEFAULT_CLOSURE_ABORT_LEVELS =
    (; water = 1.0, energy = nothing, energy_source = nothing)

"""
    closure_check_from_config(spec_value, context, FT; default_tolerance,
                              default_abort_above, default_spin_up = nothing)

Read a `water_closure_check`, `energy_closure_check` or
`energy_source_closure_check` block into
`(; period, tolerance, abort_above, audit, spin_up)`, or `nothing` when the key
is absent.

Every key is optional: `period` defaults to `"1days"`, `tolerance` to the
family's entry in [`DEFAULT_CLOSURE_TOLERANCES`](@ref) and `abort_above` to its
entry in [`DEFAULT_CLOSURE_ABORT_LEVELS`](@ref). Writing `abort_above: ~` turns
the abort off for a family that defaults to having one. A `tolerance` of `~`
means the check never warns about the residual; the warning about a non-positive
parent stays.

`audit` defaults to `false`. Setting it writes a second table beside the closure
table, splitting the residual into the parts that mean different things; see
[`tag_audit`](@ref). It costs a handful of extra global reductions per check and
changes nothing about the run, so it is safe to leave on for a run whose tags
are under investigation.

`spin_up` is a time after the start, such as `"1hours"`, or `~` for none. When
set, the check takes the residual once at that time and writes no row for it,
and every later row reports the residual since then beside the residual itself.
The first hour of a run makes a residual that is an artefact of the initial
adjustment, and the rows since the spin-up leave it out. The reference is taken
again after a restart, at `spin_up` after the restart. Every family's block
accepts the key; only the energy source family sets it by default.
"""
closure_check_from_config(
    ::Nothing,
    context,
    ::Type{FT};
    default_tolerance,
    default_abort_above,
    default_spin_up = nothing,
) where {FT} = nothing

function closure_check_from_config(
    spec_value,
    context,
    ::Type{FT};
    default_tolerance,
    default_abort_above,
    default_spin_up = nothing,
) where {FT}
    spec = checked_mapping(
        spec_value,
        context;
        optional = ("period", "tolerance", "abort_above", "audit", "spin_up"),
    )
    period = get(spec, "period", "1days")
    isfinite(time_to_seconds(period)) || error(
        "$context `period` must be finite; an infinite period never checks \
        anything, which is what leaving the block out already does.",
    )
    tolerance = closure_tolerance_from_config(
        get(spec, "tolerance", default_tolerance),
        context,
        FT,
    )
    abort_above = closure_abort_above_from_config(
        get(spec, "abort_above", default_abort_above),
        context,
        FT,
    )
    audit = Bool(get(spec, "audit", false))
    spin_up = get(spec, "spin_up", default_spin_up)
    isnothing(spin_up) ||
        (isfinite(time_to_seconds(spin_up)) && time_to_seconds(spin_up) > 0) ||
        error(
            "$context `spin_up` must be a positive, finite time such as \
            \"1hours\", or `~` for none; got $(repr(spin_up)).",
        )
    return (; period, tolerance, abort_above, audit, spin_up)
end

"""
    closure_tolerance_from_config(value, context, FT)

Read the `tolerance` entry of a closure-check block, as an `FT` or `nothing`.
`nothing` means the check reports and never warns.
"""
closure_tolerance_from_config(::Nothing, context, ::Type{FT}) where {FT} =
    nothing

function closure_tolerance_from_config(value, context, ::Type{FT}) where {FT}
    tolerance = FT(value)
    tolerance >= 0 || error(
        "$context `tolerance` must not be negative, got $tolerance. It is \
        compared against the absolute value of the relative residual.",
    )
    return tolerance
end

"""
    energy_source_closure_check_from_config(value, entries, FT)

Read `energy_source_closure_check`. Unlike the other two families' checks, this
one is on by default whenever the tags include a pure region tag, a tag with a
`region` and no `source`, which is what closure needs:

  - `~`, the default, gives a daily check with no tolerance, from a spin-up
    reference one hour after the start, without the audit;
  - `false` switches the check off;
  - a mapping sets the keys of [`closure_check_from_config`](@ref), with the same
    defaults.

`~` with no pure region tag gives no check, since there is no partition to close.
"""
function energy_source_closure_check_from_config(
    value,
    entries,
    transport,
    ::Type{FT},
) where {FT}
    value === false && return nothing
    if isnothing(value)
        has_energy_source_partition_entry(entries) || return nothing
        value = Dict{String, Any}()
    end
    return closure_check_from_config(
        value,
        "`energy_source_closure_check`",
        FT;
        default_tolerance = energy_source_closure_tolerance(transport),
        default_abort_above = DEFAULT_CLOSURE_ABORT_LEVELS.energy_source,
        default_spin_up = "1hours",
    )
end

# Whether the `energy_source_tags` entries include a pure region tag, one with a
# `region` and no `source`, or only the source `none`.
has_energy_source_partition_entry(::Nothing) = false
has_energy_source_partition_entry(entries) =
    entries isa AbstractVector && any(entries) do entry
        entry isa AbstractDict || return false
        haskey(entry, "region") || return false
        source = get(entry, "source", nothing)
        sources =
            isnothing(source) ? () :
            source isa AbstractString ? (source,) : Tuple(source)
        return all(==("none"), string.(sources))
    end

"""
    closure_abort_above_from_config(value, context, FT)

Read the `abort_above` entry of a closure-check block, as an `FT` or `nothing`.

`nothing` means the run never ends over closure, which is what the two energy
families default to. Zero is refused rather than read as "always abort": a run
configured that way would die at the first check whatever its residual was, and
`~` already says "never" without the ambiguity.
"""
closure_abort_above_from_config(::Nothing, context, ::Type{FT}) where {FT} =
    nothing

function closure_abort_above_from_config(value, context, ::Type{FT}) where {FT}
    abort_above = FT(value)
    abort_above > 0 || error(
        "$context `abort_above` must be positive, got $abort_above. Use `~` to \
        keep warning without ever ending the run.",
    )
    return abort_above
end

"""
    closure_checks_from_config(config::AtmosConfig)

Read the closure-check blocks, as `(; water, energy_source, energy)`.
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
            default_abort_above = DEFAULT_CLOSURE_ABORT_LEVELS.water,
        ),
        energy_source = energy_source_closure_check_from_config(
            pa["energy_source_closure_check"],
            pa["energy_source_tags"],
            energy_source_transport_from_config(
                get(pa, "energy_source_tag_transport", "tracer"),
            ),
            FT,
        ),
        energy = closure_check_from_config(
            pa["energy_closure_check"],
            "`energy_closure_check`",
            FT;
            default_tolerance = DEFAULT_CLOSURE_TOLERANCES.energy,
            default_abort_above = DEFAULT_CLOSURE_ABORT_LEVELS.energy,
        ),
    )
end

"""
    process_record_from_config(record_config, key, known, groups; microphysics_model)

Convert an `energy_process_record` or `water_process_record` config entry into a
[`ProcessRecordModel`](@ref), or `nothing` when the key is absent or empty.

The entry takes the same shape as a tag's `source`: one process label, a list of
them, or a group name that expands to its members. Reusing
[`tag_sources_from_config`](@ref) here is deliberate, so that a record and a tag
name their processes identically and an unknown label is refused the same way.
`microphysics_model`, `nothing` by default, lets the label warnings see the
scheme.
"""
process_record_from_config(
    ::Nothing,
    key,
    known,
    groups;
    microphysics_model = nothing,
) = nothing
function process_record_from_config(
    record_config,
    key,
    known,
    groups;
    microphysics_model = nothing,
)
    processes = tag_sources_from_config(record_config, key, known, groups)
    isempty(processes) && return nothing
    warn_inactive_record_labels(processes, key, microphysics_model)
    return ProcessRecordModel(Tuple(RecordedProcess{p}() for p in processes))
end

"""
    warn_inactive_record_labels(processes, key, microphysics_model = nothing)

Warn about process-record labels that cannot record anything, so a record that
will stay at zero says so at configuration time rather than at analysis time.

Both tendency paths are bracketed for the records, so a label is inactive only
where its process does not exist or does not change the recorded total.

  - `precipitation` records nothing where nothing sediments: under 0-moment
    microphysics, where rain leaves through `microphysics` instead, and in a
    dry model.
  - `microphysics` records nothing under every scheme but 0-moment. The others
    move water between species and never change `ρe_tot` or `ρq_tot`. Their
    rain-out is in the `precipitation` record.

With `microphysics_model = nothing` the scheme is not known. Then it warns about
`precipitation` whenever it is listed, and not about `microphysics`.

A zero record is the dangerous case precisely because it is indistinguishable
from a real one. A process that genuinely did nothing and a process that was
never observed both read as `0.0`, and nothing downstream can tell them apart.

A warning and not an error, for the reason
[`warn_inactive_energy_source_labels`](@ref) gives: `moist` and `all` are
useful group labels that happen to include `precipitation`, and refusing them
would make the groups unusable for the processes they do cover.
"""
function warn_inactive_record_labels(processes, key, microphysics_model = nothing)
    :precipitation in processes &&
        !has_sedimentation(microphysics_model) &&
        @warn(
            "`$key` lists `precipitation`, which records the sedimentation of " *
            "precipitating species. Under 0-moment microphysics there is none, " *
            "so its record stays zero there, which reads the same as a process " *
            "that did nothing, and rain leaves through `microphysics` instead. " *
            "Note `moist` and `all` both expand to include `precipitation`.",
        )
    :microphysics in processes &&
        microphysics_is_inert(microphysics_model) &&
        @warn(
            "`$key` lists `microphysics`, which records nothing under " *
            "$(nameof(typeof(microphysics_model))). Only 0-moment " *
            "microphysics changes `ρe_tot` and `ρq_tot`. The other schemes " *
            "move water between species, so this record stays zero, which " *
            "reads the same as a process that did nothing. Their rain-out is " *
            "in the `precipitation` record.",
        )
    return nothing
end

"""
    energy_source_offset_from_config(value, FT)

Parse `energy_source_tag_offset`. `~` and `0` give `nothing`, which leaves the
energy source tags on `ρe_tot` exactly as without the key. A positive number is
the offset in J/kg, as `FT`. A negative or non-finite value is an error, since
it could only make the tags' total less positive.
"""
function energy_source_offset_from_config(value, ::Type{FT}) where {FT}
    isnothing(value) && return nothing
    value isa Real || error(
        "`energy_source_tag_offset` must be a number of J/kg, got $(repr(value)).",
    )
    (isfinite(value) && value >= 0) || error(
        "`energy_source_tag_offset` must be finite and not negative, got $value.",
    )
    iszero(value) && return nothing
    return FT(value)
end

"""
    check_energy_source_offset_given(value)

Refuse `energy_source_tags` when `energy_source_tag_offset` is not set.

`ρe_tot` has no physical zero, and it is negative over much of a typical domain.
Where the total the tags partition is not positive, the donor share is undefined,
and the loss half of the attribution rule does not run. An offset makes that
total positive without touching the model. So the key has no default, and every
run with these tags states its offset. `0` is accepted, and keeps the tags on
`ρe_tot` itself.

The values quoted are those the tag-closure experiments tested.
"""
function check_energy_source_offset_given(value)
    isnothing(value) && error(
        "`energy_source_tags` needs `energy_source_tag_offset`, an energy per \
        kilogram of air in J/kg that the tags add to `ρe_tot`. Without one the \
        donor share is undefined wherever `ρe_tot` is not positive, which is \
        much of a typical domain. The tag-closure experiments used 110495 J/kg. \
        The smallest offsets that made the total positive there were \
        45.4 kJ/kg on the DYCOMS RF02 column and 100.4 kJ/kg on the moist \
        baroclinic wave sphere. Set `energy_source_tag_offset: 0` to keep the \
        tags on `ρe_tot` itself.",
    )
    return nothing
end

"""
    energy_source_repair_from_config(value)

Parse `energy_source_tag_repair`. `true`, the default, and `~` keep the energy
source tags non-negative where their total is positive; `false` leaves them as
the attribution rule and their transport make them. Anything else is an error,
so that a quoted `"false"` cannot silently read as on.
"""
function energy_source_repair_from_config(value)
    isnothing(value) && return true
    value isa Bool || error(
        "`energy_source_tag_repair` must be `true` or `false`, got \
        $(repr(value)).",
    )
    return value
end

"""
    energy_source_transport_from_config(value)

Parse `energy_source_tag_transport`. `tracer`, the default, and `~` move the
energy source tags as passive tracers. `enthalpy` moves them by their shares of
the parent's own flux, as an audit. `enthalpy_increment` is that audit with the
tags following the parent's implicit increment after each Newton solve. Both
need `energy_source_tag_offset`, which `EnergySourceTaggingModel` checks.
Anything else is an error.
"""
function energy_source_transport_from_config(value)
    (isnothing(value) || value == "tracer") &&
        return TracerEnergySourceTransport()
    value == "enthalpy" && return EnthalpyEnergySourceTransport()
    value == "enthalpy_increment" &&
        return EnthalpyIncrementEnergySourceTransport()
    return error(
        "`energy_source_tag_transport` must be `tracer`, `enthalpy` or \
        `enthalpy_increment`, got $(repr(value)).",
    )
end

"""
    energy_source_updraft_copy_from_config(value)

Parse `energy_source_tag_updraft_copy`. `false`, the default, and `~` give the
energy source tags no copy in the updrafts; `true` gives them one. Anything
else is an error, so that a quoted `"true"` cannot silently read as off.
"""
function energy_source_updraft_copy_from_config(value)
    isnothing(value) && return false
    value isa Bool || error(
        "`energy_source_tag_updraft_copy` must be `true` or `false`, got \
        $(repr(value)).",
    )
    return value
end

"""
    check_energy_source_updraft_copy_supported(turbconv)

Refuse `energy_source_tag_updraft_copy: true` without `turbconv: prognostic_edmfx`, the only model with updrafts that carry tracers.
"""
function check_energy_source_updraft_copy_supported(turbconv)
    turbconv == "prognostic_edmfx" && return nothing
    return error(
        "`energy_source_tag_updraft_copy: true` needs `turbconv: \
        prognostic_edmfx`, got `turbconv: $(repr(turbconv))`. Only that model \
        has updrafts that carry tracers, and so a copy of the tags.",
    )
end

"""
    check_energy_source_tagging_supported(turbconv, updraft_number)

Refuse `energy_source_tags` under `turbconv: prognostic_edmfx` with more than
one updraft, and warn under `prognostic_edmfx` with one and under
`edonly_edmfx`.

Under `prognostic_edmfx` the tags take their shares of the parent's sub-grid
mass flux of energy, and exchange provenance at the updraft's mass flux
(`sgs_mass_flux_of_energy_source_tags!`), unless they have updraft copies. They
also take their shares of the updraft and environment corrections to
sedimentation (`sediment_energy_source_tags_with_corrections!`).
The model itself runs `prognostic_edmfx` with one updraft only, and asserts
that when it builds its cache. This check refuses more at configuration time,
with a message. It would refuse them even if the model allowed more, because
the model computes those corrections for the first updraft only, and the
sharing has been checked with one updraft.

Both EDMF variants have eddy diffusion. It moves the tags as passive tracers,
while it moves `ρe_tot` in enthalpy form. The difference goes to `e_src_res`, as
it does under vertical diffusion, so this is a warning. Under
`energy_source_tag_transport: enthalpy_increment` with implicit diffusion, the
correction after each solve takes it instead.
"""
function check_energy_source_tagging_supported(turbconv, updraft_number)
    if turbconv == "prognostic_edmfx" && updraft_number > 1
        error(
            "`energy_source_tags` with `turbconv: prognostic_edmfx` need \
            `updraft_number: 1`, got $updraft_number. The model runs \
            `prognostic_edmfx` with one updraft only. The tags take their \
            shares of the updraft and environment corrections to \
            sedimentation, and the model computes those for the first \
            updraft only. The tags' exchange at the mass flux also takes the \
            environment as the grid mean less one updraft.",
        )
    elseif turbconv in ("prognostic_edmfx", "edonly_edmfx")
        @warn(
            "`energy_source_tags` with `turbconv: $turbconv`: the eddy \
            diffusion moves the tags as passive tracers, while it moves \
            `ρe_tot` in enthalpy form. The difference goes to `e_src_res`, \
            unless `energy_source_tag_transport: enthalpy_increment` takes \
            it after each implicit solve.",
        )
    end
    return nothing
end

"""
    check_water_tracers_transport_supported(turbconv, amd_les, updraft_number = 1)

Refuse `water_tracers` where the model moves `ρq_tot` in a way the tags do not
follow.

  - `turbconv: prognostic_edmfx` with more than one updraft is refused. The
    tags follow one updraft: by their share of its water flux and an
    exchange, or by copies (`water_tag_updraft_copy`), and both take the
    environment as the grid mean less that updraft. The model itself runs one
    updraft only and asserts that when it builds its cache; this refuses more,
    with a message. With one updraft the tags follow it.
  - `amd_les: true` is refused. AMD diffuses each tracer with a diffusivity
    taken from that tracer's own gradient. The operator is nonlinear, so in
    general the tags' diffusion does not add up to that of `ρq_tot`, and no
    repair restores the partition. Smagorinsky–Lilly and constant horizontal
    diffusion share one diffusivity and keep it.

`docs/known_issues.md`, issue 3, describes both. The check is kept apart from
`check_water_tagging_supported`, which also gates
`water_process_record`. The records are not transported, so neither applies to
them. A prescribed flow is warned about once the model is built, since the
setup can bring one without the key; see
`warn_water_tags_under_prescribed_flow`.
"""
function check_water_tracers_transport_supported(
    turbconv,
    amd_les,
    updraft_number = 1,
)
    turbconv == "prognostic_edmfx" &&
        updraft_number > 1 &&
        error(
            "`water_tracers` with `turbconv: prognostic_edmfx` need \
            `updraft_number: 1`, got $updraft_number. The tags follow one \
            updraft, by their share of its water flux and an exchange or by \
            copies, and take the environment as the grid mean less that \
            updraft. `water_process_record` is allowed.",
        )
    amd_les === true && error(
        "`water_tracers` with `amd_les: true` are not supported. AMD diffuses \
        each tracer with a diffusivity taken from that tracer's own gradient, \
        so in general the tags' diffusion does not add up to that of \
        `ρq_tot`, and the partition breaks. `smagorinsky_lilly` and \
        `constant_horizontal_diffusion` share one diffusivity and keep it. \
        See docs/known_issues.md, issue 3.",
    )
    return nothing
end

"""
    default_water_tag_transport(parsed_args, updraft_copies, tags)

The transport the water tags take when `water_tag_transport` is not set.

G3_PLAN 4.3 fixed the rule before V-W3 ran. If the default mode's one-iteration
part of the closure residual exceeds a quarter of the 0.2% budget, the follower
becomes the default under EDMF. V-W3 measured twelve times that (FINDINGS W21
on the record branch). So `increment` is the default in the default mode under
`turbconv: prognostic_edmfx`, where the configuration shows it is supported:

  - an ARS algorithm, which solves every stage it uses;
  - an `energy_q_tot_upwinding` other than `none`, so the parent has a
    post-solve correction;
  - microphysics other than 1M stepped explicitly, where the follower is
    refused ([`check_water_tag_increment_supported`](@ref));
  - a region tag without a source, which the follower needs.

Elsewhere, and with copies, `tracer`. The model still checks what the
configuration cannot show, such as whether the regions partition the domain.
"""
function default_water_tag_transport(parsed_args, updraft_copies, tags)
    tracer = TracerWaterTagTransport()
    get(parsed_args, "turbconv", nothing) == "prognostic_edmfx" || return tracer
    updraft_copies && return tracer
    startswith(string(get(parsed_args, "ode_algo", "ARS343")), "ARS") ||
        return tracer
    string(get(parsed_args, "energy_q_tot_upwinding", "vanleer_limiter")) ==
    "none" && return tracer
    _explicit_one_moment_config(parsed_args) && return tracer
    any(_is_partition_tag, tags) || return tracer
    return IncrementWaterTagTransport()
end
_explicit_one_moment_config(parsed_args) =
    get(parsed_args, "microphysics_model", nothing) == "1M" &&
    get(parsed_args, "implicit_microphysics", true) == false

"""
    water_tag_updraft_copy_from_config(value)

Parse `water_tag_updraft_copy`. `false`, the default, and `~` give the water
tags no copy in the updrafts; `true` gives them one. Anything else is an
error, so that a quoted `"true"` cannot silently read as off.
"""
function water_tag_updraft_copy_from_config(value)
    isnothing(value) && return false
    value isa Bool || error(
        "`water_tag_updraft_copy` must be `true` or `false`, got \
        $(repr(value)).",
    )
    return value
end

"""
    water_tag_transport_from_config(value, default = TracerWaterTagTransport())

Parse `water_tag_transport`. `tracer` moves the water tags as tracers.
`increment` makes them follow the parent's implicit increment after each Newton
solve. `~`, the default, gives `default`, which
[`default_water_tag_transport`](@ref) chooses from the configuration. Anything
else is an error.
"""
function water_tag_transport_from_config(
    value,
    default = TracerWaterTagTransport(),
)
    isnothing(value) && return default
    value == "tracer" && return TracerWaterTagTransport()
    value == "increment" && return IncrementWaterTagTransport()
    return error(
        "`water_tag_transport` must be `tracer` or `increment`, got \
        $(repr(value)).",
    )
end

"""
    water_tag_transport_text(transport)

The config value of a water tag transport, for messages and the restart guard.
"""
water_tag_transport_text(::TracerWaterTagTransport) = "tracer"
water_tag_transport_text(::IncrementWaterTagTransport) = "increment"

"""
    check_water_tag_updraft_copy_supported(turbconv, mse_q_tot_upwinding, tracer_upwinding)

Refuse `water_tag_updraft_copy: true` without `turbconv: prognostic_edmfx`, the
only model with updrafts that carry tracers, and where the updraft's water and
its tracers are reconstructed differently. The copies' SGS fluxes sum to the
parent's only when both use one reconstruction:
`edmfx_mse_q_tot_upwinding` moves `q_totʲ`, and `edmfx_tracer_upwinding` moves
every updraft tracer, the copies among them.
"""
function check_water_tag_updraft_copy_supported(
    turbconv,
    mse_q_tot_upwinding,
    tracer_upwinding,
)
    turbconv == "prognostic_edmfx" || error(
        "`water_tag_updraft_copy: true` needs `turbconv: prognostic_edmfx`, \
        got `turbconv: $(repr(turbconv))`. Only that model has updrafts that \
        carry tracers, and so a copy of the tags.",
    )
    mse_q_tot_upwinding == tracer_upwinding || error(
        "`water_tag_updraft_copy: true` needs `edmfx_mse_q_tot_upwinding` equal \
        to `edmfx_tracer_upwinding`, got $(repr(mse_q_tot_upwinding)) and \
        $(repr(tracer_upwinding)). The first reconstructs the updraft's water \
        and the second its tracers, the copies among them. With two \
        reconstructions the copies' fluxes do not sum to the parent's.",
    )
    return nothing
end

"""
    warn_water_tags_under_prescribed_flow(prescribed_flow, water_tagging_model)

Warn when a run with water tags has a prescribed flow. The flow's surface
moisture flux enters `ρq_tot` with no tagged counterpart, so that water is
untagged, and the closure residual `q_tag_res` grows by it where region tags
partition the domain. The flow also clips negative `ρq_tot` to zero whenever
the state is constrained. The tags follow the clip through
[`rescale_water_tags!`](@ref), and `q_tag_fix_<name>` records what it moved.

It takes the built model's fields, because the flow comes from the setup, as
`initial_condition: ShipwayHill2012` gives it, or from the `prescribed_flow`
key. `get_atmos` calls it.
"""
warn_water_tags_under_prescribed_flow(prescribed_flow, water_tagging_model) =
    isnothing(prescribed_flow) || isnothing(water_tagging_model) ? nothing :
    @warn(
        "`water_tracers` with a prescribed flow: the flow's surface moisture \
        flux enters `ρq_tot` untagged, so `q_tag_res`, where region tags are \
        configured, grows by it. The flow also clips negative `ρq_tot` when \
        the state is constrained, which the tags follow and \
        `q_tag_fix_<name>` records.",
    )

"""
    AtmosTagging(config::AtmosConfig)

Assemble the `AtmosTagging` group from the `energy_tracers`, `water_tracers`,
`energy_source_tags` (with `energy_source_tag_offset`, `energy_source_tag_repair`,
`energy_source_tag_transport` and `energy_source_tag_updraft_copy`),
`energy_process_record` and
`water_process_record` config keys. Any of them
being `~` (null) or an empty list disables that feature entirely, at no runtime
cost.

Energy source tags are refused without `energy_source_tag_offset`, see
`check_energy_source_offset_given`, and under `turbconv: prognostic_edmfx` with
more than one updraft, see `check_energy_source_tagging_supported`. Water
tags are refused under `turbconv: prognostic_edmfx` and `amd_les: true`, see
`check_water_tracers_transport_supported`. The label warnings of the energy
source tags and the records see the microphysics model, and the warning for
water tags under a prescribed flow sees the built model
(`warn_water_tags_under_prescribed_flow`).
"""
function AtmosTagging(config::AtmosConfig)
    FT = eltype(config)
    microphysics_model = get_microphysics_model(config.parsed_args)
    entries = config.parsed_args["energy_tracers"]
    tagging_model = if isnothing(entries) || isempty(entries)
        nothing
    else
        TaggingModel(energy_tracer_tuple(entries, FT))
    end
    water_entries = config.parsed_args["water_tracers"]
    water_updraft_copies = water_tag_updraft_copy_from_config(
        get(config.parsed_args, "water_tag_updraft_copy", false),
    )
    water_transport_value = get(config.parsed_args, "water_tag_transport", nothing)
    water_transport = water_tag_transport_from_config(water_transport_value)
    water_tagging_model = if isnothing(water_entries) || isempty(water_entries)
        water_updraft_copies && error(
            "`water_tag_updraft_copy: true` is set but `water_tracers` is \
            not, so there are no tags to copy. Configure `water_tracers`, or \
            drop the key.",
        )
        water_transport isa TracerWaterTagTransport || error(
            "`water_tag_transport: \
            $(water_tag_transport_text(water_transport))` is set but \
            `water_tracers` is not, so there are no tags for it to move. \
            Configure `water_tracers`, or drop the key.",
        )
        nothing
    else
        check_water_tagging_supported(microphysics_model)
        check_water_tracers_transport_supported(
            get(config.parsed_args, "turbconv", nothing),
            get(config.parsed_args, "amd_les", false),
            get(config.parsed_args, "updraft_number", 1),
        )
        water_updraft_copies && check_water_tag_updraft_copy_supported(
            get(config.parsed_args, "turbconv", nothing),
            get(config.parsed_args, "edmfx_mse_q_tot_upwinding", "first_order"),
            get(config.parsed_args, "edmfx_tracer_upwinding", "first_order"),
        )
        water_tags = water_tracer_tuple(water_entries, FT)
        water_transport = water_tag_transport_from_config(
            water_transport_value,
            default_water_tag_transport(
                config.parsed_args,
                water_updraft_copies,
                water_tags,
            ),
        )
        water_transport isa IncrementWaterTagTransport &&
            _explicit_one_moment_config(config.parsed_args) &&
            error(_EXPLICIT_ONE_MOMENT_INCREMENT_MESSAGE)
        WaterTaggingModel(
            water_tags;
            updraft_copies = water_updraft_copies,
            transport = water_transport,
        )
    end
    source_entries = config.parsed_args["energy_source_tags"]
    source_offset_value =
        get(config.parsed_args, "energy_source_tag_offset", nothing)
    source_offset = energy_source_offset_from_config(source_offset_value, FT)
    source_repair = energy_source_repair_from_config(
        get(config.parsed_args, "energy_source_tag_repair", true),
    )
    source_transport = energy_source_transport_from_config(
        get(config.parsed_args, "energy_source_tag_transport", "tracer"),
    )
    source_updraft_copies = energy_source_updraft_copy_from_config(
        get(config.parsed_args, "energy_source_tag_updraft_copy", false),
    )
    energy_source_tagging_model =
        if isnothing(source_entries) || isempty(source_entries)
            isnothing(source_offset) || error(
                "`energy_source_tag_offset` is set but `energy_source_tags` \
                is not, so there are no tags for it to offset. Configure \
                `energy_source_tags`, or drop `energy_source_tag_offset`.",
            )
            !(source_transport isa TracerEnergySourceTransport) && error(
                "`energy_source_tag_transport: \
                $(energy_source_transport_text(source_transport))` is set but \
                `energy_source_tags` is not, so there are no tags for it to \
                move. Configure `energy_source_tags`, or drop the key.",
            )
            source_updraft_copies && error(
                "`energy_source_tag_updraft_copy: true` is set but \
                `energy_source_tags` is not, so there are no tags to copy. \
                Configure `energy_source_tags`, or drop the key.",
            )
            nothing
        else
            check_energy_source_offset_given(source_offset_value)
            check_energy_source_tagging_supported(
                get(config.parsed_args, "turbconv", nothing),
                get(config.parsed_args, "updraft_number", 1),
            )
            source_updraft_copies && check_energy_source_updraft_copy_supported(
                get(config.parsed_args, "turbconv", nothing),
            )
            EnergySourceTaggingModel(
                energy_source_tracer_tuple(
                    source_entries,
                    FT;
                    microphysics_model,
                ),
                source_offset;
                repair = source_repair,
                transport = source_transport,
                updraft_copies = source_updraft_copies,
            )
        end
    energy_process_record = process_record_from_config(
        config.parsed_args["energy_process_record"],
        "energy_process_record",
        KNOWN_TAG_SOURCES,
        TAG_SOURCE_GROUPS;
        microphysics_model,
    )
    water_process_record = process_record_from_config(
        config.parsed_args["water_process_record"],
        "water_process_record",
        KNOWN_WATER_TAG_SOURCES,
        WATER_TAG_SOURCE_GROUPS;
        microphysics_model,
    )
    # Parse before checking the microphysics model. A record that names no
    # process is disabled, and a disabled record must not demand a moist model.
    # Checking first made `water_process_record: []` fail on a dry run with a
    # message naming a key the user had not set.
    isnothing(water_process_record) || check_water_tagging_supported(
        microphysics_model,
        "water_process_record",
    )
    return AtmosTagging(;
        tagging_model,
        water_tagging_model,
        energy_source_tagging_model,
        energy_process_record,
        water_process_record,
    )
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
