#####
##### Tagged prognostic energy tracers
#####
##### This file contains the full implementation of the tagged-tracer feature.
##### The corresponding types (`AbstractTagRegion`, `TracerTag`, `TaggingModel`,
##### and the `AtmosTagging` model group) are defined in `types.jl`, and the
##### config getter `AtmosTagging(::AtmosConfig)` is defined in
##### `config/model_getters.jl`. Everything else about tagging lives here, so
##### the rest of the model code only needs:
#####
#####   1. `tagging_variables(ρe_tot, local_geometry, atmos_model.tagging_model)`
#####      in the initial-condition assembly (`setups/common/prognostic_variables.jl`);
#####   2. `tagging_cache(Y, atmos)` in `cache/cache.jl`, which precomputes the
#####      static region masks, and `tagging_scratch(Y, atmos)` in
#####      `cache/temporary_quantities.jl` for the snapshot buffer;
#####   3. `snapshot_tagged_ρe_tot!` / `attribute_tagged_ρe_tot!` brackets
#####      around the attributed processes in `additional_tendency!`
#####      (`prognostic_equations/remaining_tendency.jl`) and around
#####      precipitation sedimentation in `implicit_tendency!`
#####      (`prognostic_equations/implicit/implicit_tendency.jl`);
#####   4. `is_tagged_tracer_name` to exempt tags from the tracer limiters
#####      (`prognostic_equations/limited_tendencies.jl`).
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρe_tag_<name>`. Because
##### these names are ρ-weighted and not in the exclusion list of
##### `gs_tracer_names(Y)`, the existing tracer machinery automatically applies
##### advection, hyperdiffusion, sponges, vertical eddy diffusion (as a passive
##### scalar with `K_h`), and the corresponding implicit-Jacobian blocks. No
##### hand-written transport is needed (and none should be added).
#####
##### Source attribution only covers processes that the tags do NOT already
##### receive through that machinery — see `KNOWN_TAG_SOURCES` for the list and
##### `TAG_SOURCE_GROUPS` for the user-facing groupings. Transport-like
##### processes (advection, diffusion, sponges) must NOT be attributed: each tag
##### already receives its own transport from the tracer machinery, so masked
##### attribution of `ρe_tot` transport would count it twice.
#####
##### Masks are static in space and must be evaluated once (when building the
##### cache) — never inside a per-timestep broadcast.

"""
    region_mask(region::AbstractTagRegion, coord)

Evaluate the smooth spatial mask `M(coord) ∈ [0, 1]` of `region` at a single
coordinate point `coord` (e.g. an element of `Fields.coordinate_field(space)`).

Smooth `tanh` transitions are used instead of step functions to avoid Gibbs
oscillations in the spectral-element horizontal discretization.
"""
function region_mask end

region_mask(::EntireDomain, coord) = one(coord.z)

function region_mask(region::TanhAltitudeRegion, coord)
    z = coord.z
    above = (one(z) + tanh((z - region.z_center) / region.width)) / 2
    return region.above ? above : one(above) - above
end

function region_mask(region::TanhLatitudeRegion, coord)
    lat = coord.lat # degrees; requires spherical geometry (LatLongZPoint)
    band =
        (
            tanh((lat + region.lat_bound) / region.width) -
            tanh((lat - region.lat_bound) / region.width)
        ) / 2
    return region.inside ? band : one(band) - band
end

# Shift `lon` into the 360°-wide window centered on `lon_ref`, so that
# longitudes on either side of the antimeridian can be compared directly.
@inline _wrap_lon(lon, lon_ref) = lon_ref + mod(lon - lon_ref + 180, 360) - 180

# Smooth band `x_min ≲ x ≲ x_max`: 1 well inside, 0 well outside, 1/2 on each
# edge, with `tanh` transitions of the given width.
@inline _tanh_band(x, x_min, x_max, width) =
    (tanh((x - x_min) / width) - tanh((x - x_max) / width)) / 2

function region_mask(region::TanhBoxRegion, coord)
    lat = coord.lat
    # Evaluate longitudes in the frame centered on the box, so a box that
    # crosses the antimeridian stays contiguous
    lon_center = region.lon_min + mod(region.lon_max - region.lon_min, 360) / 2
    lon = _wrap_lon(coord.long, lon_center)
    lon_max = region.lon_min + mod(region.lon_max - region.lon_min, 360)
    box =
        _tanh_band(lat, region.lat_min, region.lat_max, region.width) *
        _tanh_band(lon, region.lon_min, lon_max, region.width)
    return region.inside ? box : one(box) - box
end

# Whether (x, y) lies inside the polygon, by ray casting. The vertices are
# assumed to already be in a common longitude frame.
@inline function _point_in_polygon(vertices::NTuple{N}, x, y) where {N}
    inside = false
    x_prev, y_prev = vertices[N]
    for i in 1:N
        x_cur, y_cur = vertices[i]
        if ((y_cur > y) != (y_prev > y)) && (
            x <
            (x_prev - x_cur) * (y - y_cur) / (y_prev - y_cur) + x_cur
        )
            inside = !inside
        end
        x_prev, y_prev = x_cur, y_cur
    end
    return inside
end

# Distance from (x, y) to the segment (x1, y1)–(x2, y2).
@inline function _distance_to_segment(x, y, x1, y1, x2, y2)
    dx, dy = x2 - x1, y2 - y1
    len² = dx * dx + dy * dy
    t =
        len² > 0 ?
        min(max(((x - x1) * dx + (y - y1) * dy) / len², zero(x)), one(x)) :
        zero(x)
    return hypot(x - (x1 + t * dx), y - (y1 + t * dy))
end

# Distance from (x, y) to the polygon boundary, in degrees of great-circle
# arc: longitude separations are scaled by cos(lat) so that the smoothing
# width means the same physical distance at every latitude.
@inline function _distance_to_polygon(vertices::NTuple{N}, x, y) where {N}
    cos_lat = max(cosd(y), eps(y))
    x_scaled = x * cos_lat
    dist = typemax(y)
    x_prev, y_prev = vertices[N] # start from the closing edge
    for i in 1:N
        x_cur, y_cur = vertices[i]
        dist = min(
            dist,
            _distance_to_segment(
                x_scaled, y, x_prev * cos_lat, y_prev, x_cur * cos_lat, y_cur,
            ),
        )
        x_prev, y_prev = x_cur, y_cur
    end
    return dist
end

function region_mask(region::TanhPolygonRegion, coord)
    # Work in the longitude frame of the first vertex so that polygons
    # crossing the antimeridian stay contiguous
    lon_ref = region.vertices[1][1]
    lon = _wrap_lon(coord.long, lon_ref)
    lat = coord.lat
    vertices = unrolled_map(v -> (_wrap_lon(v[1], lon_ref), v[2]), region.vertices)
    distance = _distance_to_polygon(vertices, lon, lat)
    # Signed: negative inside, so the mask tends to 1 there
    signed_distance =
        _point_in_polygon(vertices, lon, lat) ? -distance : distance
    mask = (one(lat) - tanh(signed_distance / region.width)) / 2
    return region.inside ? mask : one(mask) - mask
end

"""
    tag_initial_value(tag::AbstractTracerTag, ρχ, coord)

Initial value of a tagged field at a single point, where `ρχ` is the parent
quantity being partitioned (`ρe_tot` for a [`TracerTag`](@ref), `ρq_tot` for a
[`WaterTag`](@ref)):

  - For pure region tags (`tag.region isa AbstractTagRegion` and
    no sources), the masked share of the initial parent, `ρχ * M(coord)`. If the
    configured regions partition unity (e.g. a band and its complement), the
    region tags sum to `ρχ` at `t = 0`.
  - For source tags, zero — **regardless of whether they also carry a
    region**. A source tag accumulates only the attributed process tendency
    (masked by its region when it has one); initializing a region-restricted
    source tag to `ρχ * M` would add the region's content on top of the
    accounting and break the identity that region-restricted source tags over a
    partition sum to the corresponding global source tag.
"""
@inline tag_initial_value(tag::AbstractTracerTag, ρχ, coord) =
    isnothing(tag.region) || !isempty(tag.sources) ? zero(ρχ) :
    ρχ * region_mask(tag.region, coord)

# Build a single-entry NamedTuple `(; ρe_tag_<name> = value)`. The field name
# is computed at compile time from the tag's type parameter, so this is fully
# type-stable and GPU-compatible.
@generated function tag_entry(::TracerTag{name}, value) where {name}
    field_name = Symbol(:ρe_tag_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

"""
    tagging_variables(ρe_tot, local_geometry, tagging_model)

NamedTuple of tagged prognostic fields `(; ρe_tag_<name₁> = ..., ...)` for a
single grid point, to be splatted into the center prognostic state alongside
the other grid-scale variables. Returns `(;)` when tagging is disabled
(`tagging_model === nothing`).
"""
tagging_variables(ρe_tot, local_geometry, ::Nothing) = (;)
tagging_variables(ρe_tot, local_geometry, model::TaggingModel) =
    _tag_variables(ρe_tot, local_geometry.coordinates, model.tags)

_tag_variables(ρe_tot, coord, ::Tuple{}) = (;)
_tag_variables(ρe_tot, coord, tags::Tuple) = merge(
    tag_entry(first(tags), tag_initial_value(first(tags), ρe_tot, coord)),
    _tag_variables(ρe_tot, coord, Base.tail(tags)),
)

# ============================================================================
# Config parsing
# ============================================================================

"""
    tag_region_from_config(region_config, FT)

Convert the `region` entry of a `tagged_tracers` config item (a `Dict` parsed
from YAML, or `nothing`) into an `AbstractTagRegion` (or `nothing`).

Supported `type` values:

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
function tag_region_from_config(region_config, ::Type{FT}) where {FT}
    haskey(region_config, "type") || error(
        "Each `region` entry of `tagged_tracers` must specify a `type` " *
        """(`"everywhere"`, `"tanh_altitude"`, or `"tanh_latitude"`).""",
    )
    region_type = region_config["type"]
    if region_type == "everywhere"
        return EntireDomain()
    elseif region_type == "tanh_altitude"
        haskey(region_config, "z_center") && haskey(region_config, "width") ||
            error(
                "`tanh_altitude` regions require `z_center` and `width` (in meters).",
            )
        return TanhAltitudeRegion(
            FT(region_config["z_center"]),
            FT(region_config["width"]),
            Bool(get(region_config, "above", true)),
        )
    elseif region_type == "tanh_latitude"
        haskey(region_config, "lat_bound") && haskey(region_config, "width") ||
            error(
                "`tanh_latitude` regions require `lat_bound` and `width` (in degrees).",
            )
        return TanhLatitudeRegion(
            FT(region_config["lat_bound"]),
            FT(region_config["width"]),
            Bool(get(region_config, "inside", true)),
        )
    elseif region_type == "tanh_box"
        all(
            key -> haskey(region_config, key),
            ("lon_min", "lon_max", "lat_min", "lat_max", "width"),
        ) || error(
            "`tanh_box` regions require `lon_min`, `lon_max`, `lat_min`, " *
            "`lat_max`, and `width` (in degrees).",
        )
        return TanhBoxRegion(
            FT(region_config["lon_min"]),
            FT(region_config["lon_max"]),
            FT(region_config["lat_min"]),
            FT(region_config["lat_max"]),
            FT(region_config["width"]),
            Bool(get(region_config, "inside", true)),
        )
    elseif region_type == "tanh_polygon"
        haskey(region_config, "vertices") && haskey(region_config, "width") ||
            error(
                "`tanh_polygon` regions require `vertices` (a list of " *
                "`[lon, lat]` pairs) and `width` (in degrees).",
            )
        vertices = region_config["vertices"]
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
            FT(region_config["width"]),
            Bool(get(region_config, "inside", true)),
        )
    else
        error(
            """Unknown tagged tracer region type `$region_type`. Expected: \
            "everywhere" | "tanh_altitude" | "tanh_latitude" | "tanh_box" | \
            "tanh_polygon".""",
        )
    end
end

"""
    tag_sources_from_config(source_config, name, known = KNOWN_TAG_SOURCES,
                            groups = TAG_SOURCE_GROUPS)

Convert the `source` entry of a `tagged_tracers` (or `tagged_water`) config item
into a `Tuple` of process labels. Accepts `nothing` (no sources), a single
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
                "Unknown tagged tracer source `$key` for tag `$name`. " *
                "Supported processes: $(join(known, ", ")). " *
                "Supported groups: $(join(keys(groups), ", ")).",
            )
        end
    end
    return Tuple(unique(sources))
end

"""
    tagged_tracer_tuple(entries, FT)

Convert the parsed `tagged_tracers` config entries (a vector of `Dict`s from
YAML) into a `Tuple` of [`TracerTag`](@ref)s suitable for constructing a
[`TaggingModel`](@ref). Validates that every entry has a unique `name` and at
least one of `region` / `source`.
"""
function tagged_tracer_tuple(entries, ::Type{FT}) where {FT}
    tags = map(collect(entries)) do entry
        haskey(entry, "name") ||
            error("Each `tagged_tracers` entry must specify a `name`.")
        name = Symbol(entry["name"])
        region = tag_region_from_config(get(entry, "region", nothing), FT)
        sources = tag_sources_from_config(get(entry, "source", nothing), name)
        if isnothing(region) && isempty(sources)
            error(
                "Tagged tracer `$name` must specify a `region`, a `source`, or both.",
            )
        end
        return TracerTag{name}(region, sources)
    end
    names = map(tag_name, tags)
    allunique(names) ||
        error("Tagged tracer names must be unique; got $(names).")
    return Tuple(tags)
end

# ============================================================================
# Source attribution
# ============================================================================

"""
    KNOWN_TAG_SOURCES

`Tuple` of the process labels that can be attributed to a tagged tracer. Each
label corresponds to one attribution bracket in `additional_tendency!` (see
`prognostic_equations/remaining_tendency.jl`):

  - `:radiation`: all radiation modes (`radiation_tendency!`)
  - `:surface_flux`: turbulent surface energy flux (`surface_flux_tendency!`)
  - `:microphysics`: microphysics energy sources (`microphysics_tendency!`,
    only when microphysics is stepped explicitly)
  - `:held_suarez`: Held–Suarez relaxation forcing
  - `:large_scale_advection`: prescribed large-scale advective forcing
  - `:subsidence`: prescribed large-scale subsidence
  - `:external_forcing`: externally prescribed (e.g. GCM-driven) forcing
  - `:precipitation`: energy carried out of a level by sedimenting
    precipitation (`vertical_advection_of_water_tendency!`). This is the one
    attributed process on the **implicit** path; it is bracketed inside
    `implicit_tendency!`, which is safe because that function zeroes `Yₜ` on
    every evaluation. With 1-moment and 2-moment microphysics this is where
    the moist energy sink lives, since those schemes change only the water
    species and leave `ρe_tot` to the sedimentation flux.

A process is attributable only if the tags do **not** already receive it
through the automatic tracer machinery. This excludes every transport-like
term — advection, hyperdiffusion, sponges, interior vertical diffusion, LES
SGS diffusion — because each tag is transported in its own right, so masked
attribution of the `ρe_tot` version would count it twice. It also excludes
most tendencies applied by the implicit solver (implicit vertical transport,
implicit diffusion) and EDMFX SGS mass fluxes, which have no bracket; those
land in the closure residual `ρe_tot - Σᵢ ρe_tag_i`. Precipitation
sedimentation is the one implicit process that *is* attributed, because it
is a genuine energy sink that the tags never receive.

See also [`TAG_SOURCE_GROUPS`](@ref) for the group labels that expand to
sets of these processes.
"""
const KNOWN_TAG_SOURCES = (
    :radiation,
    :surface_flux,
    :microphysics,
    :precipitation,
    :held_suarez,
    :large_scale_advection,
    :subsidence,
    :external_forcing,
)

"""
    TAG_SOURCE_GROUPS

Named groups of process labels, usable wherever a `source` is expected so
that a tag can follow a whole class of processes without listing each one:

  - `:radiative`: radiative heating/cooling
  - `:turbulent`: turbulent exchange with the surface
  - `:moist`: energy sources from phase changes and precipitation formation
  - `:forcing`: prescribed/idealized forcings (Held–Suarez, large-scale
    advection, subsidence, external forcing)
  - `:all`: every process in [`KNOWN_TAG_SOURCES`](@ref)

Groups expand at configuration time, so `source: forcing` and
`source: [held_suarez, large_scale_advection, subsidence, external_forcing]`
produce identical tags.
"""
const TAG_SOURCE_GROUPS = (;
    radiative = (:radiation,),
    turbulent = (:surface_flux,),
    moist = (:microphysics, :precipitation),
    forcing = (
        :held_suarez,
        :large_scale_advection,
        :subsidence,
        :external_forcing,
    ),
    all = KNOWN_TAG_SOURCES,
)

"""
    tagging_cache(Y, atmos::AtmosModel)

Cache entries used by tagged-tracer source attribution (stored as
`p.tagging`); `nothing` when tagging is disabled, at zero cost. Contains:

  - `ᶜmasks`: one static center `Field` per region tag, holding the smooth
    spatial mask of that tag's region, keyed like the state
    (`ρe_tag_<name>`). Masks are evaluated once here and never inside a
    per-timestep broadcast.

The buffer that [`snapshot_tagged_ρe_tot!`](@ref) records `Yₜ.c.ρe_tot` into
lives in `p.scratch` instead (see [`tagging_scratch`](@ref)), because the
implicit tendency is evaluated with `ForwardDiff.Dual` numbers when an
automatic-differentiation Jacobian is used, and only `p.precomputed` and
`p.scratch` are converted to dual-typed fields.
"""
function tagging_cache(Y, atmos::AtmosModel)
    energy = _tagging_cache(Y, atmos.tagging_model)
    water = _water_tagging_cache(Y, atmos.water_tagging_model)
    isnothing(energy) && isnothing(water) && return nothing
    return (; _or_empty(energy)..., _or_empty(water)...)
end
_or_empty(::Nothing) = (;)
_or_empty(nt) = nt

_tagging_cache(Y, ::Nothing) = nothing
function _tagging_cache(Y, model::TaggingModel)
    ᶜmasks = _tag_masks(Fields.coordinate_field(Y.c), model.tags)
    _check_region_partition(
        ᶜmasks,
        region_tag_state_names(model),
        "e_tag_res",
        "ρe_tag",
    )
    return (; ᶜmasks)
end

"""
    tagging_scratch(Y, atmos::AtmosModel)

Scratch fields needed by tagged-tracer source attribution, merged into
`p.scratch`; empty when tagging is disabled. `ᶜtagging_snapshot` holds
`Yₜ.c.ρe_tot` from the last [`snapshot_tagged_ρe_tot!`](@ref); no other code
touches it, so a bracketed process cannot clobber it. `ᶜtagging_q_snapshot` is
its water counterpart, and `ᶜtagging_q_share_norm` holds the partition-share
denominator of [`water_tag_share_norm!`](@ref).
"""
tagging_scratch(Y, atmos::AtmosModel) = (;
    (
        isnothing(atmos.tagging_model) ? (;) :
        (; ᶜtagging_snapshot = similar(Y.c.ρ))
    )...,
    (
        isnothing(atmos.water_tagging_model) ? (;) :
        (;
            ᶜtagging_q_snapshot = similar(Y.c.ρ),
            ᶜtagging_q_share_norm = similar(Y.c.ρ),
        )
    )...,
)

"""
    region_tag_state_names(tagging_model::TaggingModel)

`Tuple` of the state-field `Symbol`s (`:ρe_tag_<name>`) of the pure region
tags: tags with a region and no sources. These are the tags whose sum
is expected to track `ρe_tot` (tags that also carry a `source` only
accumulate that source, so they would double-count region content).
"""
region_tag_state_names(tagging_model::TaggingModel) = Tuple(
    Symbol(:ρe_tag_, tag_name(tag)) for
    tag in tagging_model.tags if !isnothing(tag.region) && isempty(tag.sources)
)

# The closure diagnostic `<residual_name> = (parent - Σᵢ tagᵢ) / ρ` only
# measures attribution leakage when the pure region masks form a partition of
# unity. Overlapping or incomplete regions are allowed (and sometimes
# intended), but then the residual is dominated by the overlap/deficit, so say
# so once at initialization.
function _check_region_partition(ᶜmasks, names, residual_name, tag_prefix)
    isempty(names) && return nothing
    mask_sum = reduce(
        (a, b) -> a .+ b,
        map(name -> parent(getproperty(ᶜmasks, name)), names),
    )
    deviation = maximum(abs.(mask_sum .- 1))
    if deviation > 0.01
        @warn(
            "The `$tag_prefix` region masks do not form a partition of unity " *
            "(max deviation of their sum from 1: $deviation). This is " *
            "allowed, but the closure diagnostic `$residual_name` will be " *
            "dominated by the overlap/deficit rather than by attribution " *
            "leakage. For a clean closure monitor, use region tags that sum " *
            "to 1 (e.g. a region and its complement via `inside: false` / " *
            "`above: false`).",
        )
    end
    return nothing
end

_tag_masks(ᶜcoord, ::Tuple{}) = (;)
_tag_masks(ᶜcoord, tags::Tuple) = merge(
    _tag_mask_entry(ᶜcoord, first(tags)),
    _tag_masks(ᶜcoord, Base.tail(tags)),
)
_tag_mask_entry(ᶜcoord, ::TracerTag{name, Nothing}) where {name} = (;)
_tag_mask_entry(ᶜcoord, tag::TracerTag) =
    tag_entry(tag, region_mask.(Ref(tag.region), ᶜcoord))

"""
    snapshot_tagged_ρe_tot!(p, Yₜ)

Record the current value of `Yₜ.c.ρe_tot` in the tagging cache, opening an
attribution bracket. A no-op when tagging is disabled.

Together with [`attribute_tagged_ρe_tot!`](@ref) this brackets a block of
explicit tendency calls: whatever the block adds to `Yₜ.c.ρe_tot` is
attributed to the tagged tracers without modifying the process itself.
Brackets must not be nested.
"""
snapshot_tagged_ρe_tot!(p, Yₜ) =
    _snapshot_tagged_ρe_tot!(p, Yₜ, p.atmos.tagging_model)
_snapshot_tagged_ρe_tot!(p, Yₜ, ::Nothing) = nothing
function _snapshot_tagged_ρe_tot!(p, Yₜ, ::TaggingModel)
    p.scratch.ᶜtagging_snapshot .= Yₜ.c.ρe_tot
    return nothing
end

"""
    attribute_tagged_ρe_tot!(Yₜ, p, source::Symbol)

Close an attribution bracket opened by [`snapshot_tagged_ρe_tot!`](@ref):
compute the increment `ᶜΔ = Yₜ.c.ρe_tot - snapshot` produced by the bracketed
process (labeled `source`, one of [`KNOWN_TAG_SOURCES`](@ref)) and add it to
the tagged tracer tendencies:

  - pure region tags (no sources) receive `M * ᶜΔ`, where `M` is the
    tag's precomputed mask — every attributed process counts, so that the sum
    of a partition-of-unity set of region tags tracks `ρe_tot`;
  - source tags receive `ᶜΔ` only when their `source` matches, weighted by
    their mask when they also have a region.

A no-op when tagging is disabled.
"""
attribute_tagged_ρe_tot!(Yₜ, p, source::Symbol) =
    _attribute_tagged_ρe_tot!(Yₜ, p, source, p.atmos.tagging_model)
_attribute_tagged_ρe_tot!(Yₜ, p, source, ::Nothing) = nothing
function _attribute_tagged_ρe_tot!(Yₜ, p, source, model::TaggingModel)
    (; ᶜmasks) = p.tagging
    ᶜρe_tot_snapshot = p.scratch.ᶜtagging_snapshot
    ᶜΔρe_tot = @. lazy(Yₜ.c.ρe_tot - ᶜρe_tot_snapshot)
    _accumulate_tags!(Yₜ.c, ᶜmasks, ᶜΔρe_tot, source, model.tags)
    return nothing
end

_accumulate_tags!(ᶜYₜ, ᶜmasks, ᶜΔ, source, ::Tuple{}) = nothing
function _accumulate_tags!(ᶜYₜ, ᶜmasks, ᶜΔ, source, tags::Tuple)
    tag = first(tags)
    tag_receives_source(tag, source) && _accumulate_tag!(ᶜYₜ, ᶜmasks, ᶜΔ, tag)
    return _accumulate_tags!(ᶜYₜ, ᶜmasks, ᶜΔ, source, Base.tail(tags))
end

"""
    tag_receives_source(tag::AbstractTracerTag, source::Symbol)

Whether the attributed process labeled `source` contributes to `tag`: pure
region tags (no sources) receive every attributed process, while source tags
only receive the processes they list.

For a [`WaterTag`](@ref) this governs *production* only — every water tag is
depleted by every attributed loss, whatever it lists.
"""
tag_receives_source(tag::AbstractTracerTag, source::Symbol) =
    isempty(tag.sources) || source in tag.sources

function _accumulate_tag!(
    ᶜYₜ,
    ᶜmasks,
    ᶜΔ,
    tag::TracerTag{name, Nothing},
) where {name}
    ᶜρe_tagₜ = tag_field(ᶜYₜ, tag)
    @. ᶜρe_tagₜ += ᶜΔ
    return nothing
end
function _accumulate_tag!(ᶜYₜ, ᶜmasks, ᶜΔ, tag::TracerTag)
    ᶜρe_tagₜ = tag_field(ᶜYₜ, tag)
    ᶜmask = tag_field(ᶜmasks, tag)
    @. ᶜρe_tagₜ += ᶜmask * ᶜΔ
    return nothing
end

# Compile-time lookup of the entry `ρe_tag_<name>` in a state or tendency
# `Field` (e.g. `Yₜ.c`) or in the mask cache `NamedTuple`.
@generated tag_field(obj, ::TracerTag{name}) where {name} =
    :(obj.$(Symbol(:ρe_tag_, name)))

"""
    is_energy_tag_name(name)

Whether `name` (a `Symbol` like `:ρe_tag_strat`, or a
`MatrixFields.FieldName`) refers to a tagged prognostic energy tracer.
"""
is_energy_tag_name(name::Symbol) = startswith(string(name), "ρe_tag_")
is_energy_tag_name(name::MatrixFields.FieldName) =
    is_energy_tag_name(MatrixFields.extract_first(name))

"""
    is_water_tag_name(name)

Whether `name` (a `Symbol` like `:ρq_tag_tropics`, or a
`MatrixFields.FieldName`) refers to a tagged prognostic water tracer.
"""
is_water_tag_name(name::Symbol) = startswith(string(name), "ρq_tag_")
is_water_tag_name(name::MatrixFields.FieldName) =
    is_water_tag_name(MatrixFields.extract_first(name))

"""
    is_tagged_tracer_name(name)

Whether `name` refers to a tagged prognostic tracer of either family. Used to
exempt tags from the tracer limiters, for different reasons per family: tagged
energies can be legitimately negative (e.g. accumulated cooling), while tagged
waters must not be limited independently of each other because a shape-preserving
adjustment applied per tag would break `Σᵢ ρq_tag_i = ρq_tot`. Water tags instead
follow the parent's limiting through [`rescale_water_tags!`](@ref).
"""
is_tagged_tracer_name(name) =
    is_energy_tag_name(name) || is_water_tag_name(name)
