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
#####      in the initial-condition assembly (`setups/common/prognostic_variables.jl`).
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρe_tag_<name>`. Because
##### these names are ρ-weighted and not in the exclusion list of
##### `gs_tracer_names(Y)`, the existing tracer machinery automatically applies
##### advection, hyperdiffusion, sponges, vertical eddy diffusion (as a passive
##### scalar with `K_h`), and the corresponding implicit-Jacobian blocks. No
##### hand-written transport is needed (and none should be added).
#####
##### Masks are static in space and must be evaluated once (at initialization,
##### and later when building the source-attribution cache in Phase 4) — never
##### inside a per-timestep broadcast.

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
    return (one(z) + tanh((z - region.z_center) / region.width)) / 2
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

"""
    tag_initial_value(tag::TracerTag, ρe_tot, coord)

Initial value of the tagged field `ρe_tag_<name>` at a single point:

  - For region tags (`tag.region isa AbstractTagRegion`), the masked share of
    the initial total energy, `ρe_tot * M(coord)`. If the configured regions
    partition unity (e.g. a band and its complement), the region tags sum to
    `ρe_tot` at `t = 0`.
  - For pure source tags (`tag.region === nothing`), zero; the field then
    accumulates the attributed process tendency over time (Phase 4).
"""
@inline tag_initial_value(tag::TracerTag, ρe_tot, coord) =
    isnothing(tag.region) ? zero(ρe_tot) :
    ρe_tot * region_mask(tag.region, coord)

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
  - `"tanh_altitude"`: `(1 + tanh((z - z_center) / width)) / 2`;
    requires `z_center` and `width` in meters
  - `"tanh_latitude"`: smooth band `|lat| ≲ lat_bound` (or its complement when
    `inside: false`); requires `lat_bound` and `width` in degrees
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
    else
        error(
            """Unknown tagged tracer region type `$region_type`. Expected: \
            "everywhere" | "tanh_altitude" | "tanh_latitude".""",
        )
    end
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
        source = Symbol(get(entry, "source", "none"))
        if isnothing(region) && source == :none
            error(
                "Tagged tracer `$name` must specify a `region`, a `source`, or both.",
            )
        end
        return TracerTag{name}(region, source)
    end
    names = map(tag_name, tags)
    allunique(names) ||
        error("Tagged tracer names must be unique; got $(names).")
    return Tuple(tags)
end
