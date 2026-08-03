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
#####      static region masks and a snapshot scratch field;
#####   3. `snapshot_tagged_ρe_tot!` / `attribute_tagged_ρe_tot!` brackets
#####      around the attributed processes in `additional_tendency!`
#####      (`prognostic_equations/remaining_tendency.jl`);
#####   4. `is_tagged_tracer_name` to exempt tags from nonnegativity limiting
#####      (`prognostic_equations/limited_tendencies.jl`).
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρe_tag_<name>`. Because
##### these names are ρ-weighted and not in the exclusion list of
##### `gs_tracer_names(Y)`, the existing tracer machinery automatically applies
##### advection, hyperdiffusion, sponges, vertical eddy diffusion (as a passive
##### scalar with `K_h`), and the corresponding implicit-Jacobian blocks. No
##### hand-written transport is needed (and none should be added).
#####
##### Source attribution only covers genuine sources/sinks of `ρe_tot`
##### (radiation, surface flux, microphysics, idealized forcing). Transport-like
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

"""
    tag_initial_value(tag::TracerTag, ρe_tot, coord)

Initial value of the tagged field `ρe_tag_<name>` at a single point:

  - For pure region tags (`tag.region isa AbstractTagRegion` and
    `tag.source === :none`), the masked share of the initial total energy,
    `ρe_tot * M(coord)`. If the configured regions partition unity (e.g. a
    band and its complement), the region tags sum to `ρe_tot` at `t = 0`.
  - For source tags, zero — **regardless of whether they also carry a
    region**. A source tag accumulates only the attributed process tendency
    (masked by its region when it has one); initializing a region-restricted
    source tag to `ρe_tot * M` would add the region's energy content on top
    of the accounting and break the identity that region-restricted source
    tags over a partition sum to the corresponding global source tag.
"""
@inline tag_initial_value(tag::TracerTag, ρe_tot, coord) =
    isnothing(tag.region) || tag.source !== :none ? zero(ρe_tot) :
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
  - `"tanh_altitude"`: `(1 + tanh((z - z_center) / width)) / 2` (or its exact
    complement when `above: false`); requires `z_center` and `width` in meters
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
        source == :none ||
            source in KNOWN_TAG_SOURCES ||
            error(
                "Unknown tagged tracer source `$source` for tag `$name`. " *
                "Supported sources: $(join(KNOWN_TAG_SOURCES, ", ")).",
            )
        return TracerTag{name}(region, source)
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

`Tuple` of the process labels that can be used as the `source` of a tagged
tracer. Each label corresponds to one attribution bracket in
`additional_tendency!` (see `prognostic_equations/remaining_tendency.jl`):

  - `:radiation`: all radiation modes (`radiation_tendency!`)
  - `:surface_flux`: turbulent surface fluxes (`surface_flux_tendency!`)
  - `:microphysics`: microphysics energy sources (`microphysics_tendency!`,
    only when microphysics is stepped explicitly)
  - `:held_suarez`: Held–Suarez relaxation forcing

Only genuine sources/sinks of `ρe_tot` are attributed. Transport-like
processes (advection, hyperdiffusion, sponges, interior vertical/SGS
diffusion) are excluded because every tag already receives its own transport
from the automatic tracer machinery. Processes handled by the implicit solver
are not attributed either; with implicit diffusion or implicit microphysics,
those contributions end up in the closure residual `ρe_tot - Σᵢ ρe_tag_i`.
"""
const KNOWN_TAG_SOURCES =
    (:radiation, :surface_flux, :microphysics, :held_suarez)

"""
    tagging_cache(Y, atmos::AtmosModel)

Cache entries used by tagged-tracer source attribution (stored as
`p.tagging`); `nothing` when tagging is disabled, at zero cost. Contains:

  - `ᶜmasks`: one static center `Field` per region tag, holding the smooth
    spatial mask of that tag's region, keyed like the state
    (`ρe_tag_<name>`). Masks are evaluated once here and never inside a
    per-timestep broadcast.
  - `ᶜρe_tot_snapshot`: scratch used by [`snapshot_tagged_ρe_tot!`](@ref) to
    record `Yₜ.c.ρe_tot` before an attributed process runs. This is a
    dedicated field rather than an entry of `p.scratch` so that the bracketed
    process cannot clobber it.
"""
tagging_cache(Y, atmos::AtmosModel) = _tagging_cache(Y, atmos.tagging_model)
_tagging_cache(Y, ::Nothing) = nothing
function _tagging_cache(Y, model::TaggingModel)
    ᶜmasks = _tag_masks(Fields.coordinate_field(Y.c), model.tags)
    _check_region_partition(ᶜmasks, model)
    return (; ᶜmasks, ᶜρe_tot_snapshot = similar(Y.c.ρ))
end

"""
    region_tag_state_names(tagging_model::TaggingModel)

`Tuple` of the state-field `Symbol`s (`:ρe_tag_<name>`) of the pure region
tags: tags with a region and `source === :none`. These are the tags whose sum
is expected to track `ρe_tot` (tags that also carry a `source` only
accumulate that source, so they would double-count region content).
"""
region_tag_state_names(tagging_model::TaggingModel) = Tuple(
    Symbol(:ρe_tag_, tag_name(tag)) for
    tag in tagging_model.tags if !isnothing(tag.region) && tag.source === :none
)

# The closure diagnostic `e_tag_res = (ρe_tot - Σᵢ ρe_tag_i) / ρ` only
# measures attribution leakage when the pure region masks form a partition of
# unity. Overlapping or incomplete regions are allowed (and sometimes
# intended), but then `e_tag_res` is dominated by the overlap/deficit, so say
# so once at initialization.
function _check_region_partition(ᶜmasks, model::TaggingModel)
    names = region_tag_state_names(model)
    isempty(names) && return nothing
    mask_sum = reduce(
        (a, b) -> a .+ b,
        map(name -> parent(getproperty(ᶜmasks, name)), names),
    )
    deviation = maximum(abs.(mask_sum .- 1))
    if deviation > 0.01
        @warn(
            "The region tag masks do not form a partition of unity (max " *
            "deviation of their sum from 1: $deviation). This is allowed, " *
            "but the closure diagnostic `e_tag_res` = (ρe_tot - Σᵢ " *
            "ρe_tag_i)/ρ will be dominated by the overlap/deficit rather " *
            "than by attribution leakage. For a clean closure monitor, use " *
            "region tags that sum to 1 (e.g. a region and its complement " *
            "via `inside: false` / `above: false`).",
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
    p.tagging.ᶜρe_tot_snapshot .= Yₜ.c.ρe_tot
    return nothing
end

"""
    attribute_tagged_ρe_tot!(Yₜ, p, source::Symbol)

Close an attribution bracket opened by [`snapshot_tagged_ρe_tot!`](@ref):
compute the increment `ᶜΔ = Yₜ.c.ρe_tot - snapshot` produced by the bracketed
process (labeled `source`, one of [`KNOWN_TAG_SOURCES`](@ref)) and add it to
the tagged tracer tendencies:

  - region tags (tag `source === :none`) receive `M * ᶜΔ`, where `M` is the
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
    (; ᶜmasks, ᶜρe_tot_snapshot) = p.tagging
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
    tag_receives_source(tag::TracerTag, source::Symbol)

Whether the attributed process labeled `source` contributes to `tag`: region
tags (tag `source === :none`) receive every attributed process, while source
tags only receive their own.
"""
tag_receives_source(tag::TracerTag, source::Symbol) =
    tag.source === :none || tag.source === source

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
    is_tagged_tracer_name(name)

Whether `name` (a `Symbol` like `:ρe_tag_strat`, or a
`MatrixFields.FieldName`) refers to a tagged prognostic energy tracer. Used
to exempt tags from machinery that assumes nonnegative tracers, since tagged
energies can be legitimately negative (e.g. accumulated cooling).
"""
is_tagged_tracer_name(name::Symbol) = startswith(string(name), "ρe_tag_")
is_tagged_tracer_name(name::MatrixFields.FieldName) =
    is_tagged_tracer_name(MatrixFields.extract_first(name))
