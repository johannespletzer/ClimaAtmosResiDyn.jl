#####
##### Energy source tags
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρe_src_<name>` holding
##### part of the total moist energy `ρe_tot`. The `energy_source_tags` config
##### key switches them on. Types live in `types.jl` and config parsing in
##### `config/tracer_config.jl`. The physics is written up in
##### `docs/src/energy_source_tags.md`.
#####
##### This is the energy counterpart of the water tags in `tagged_water.jl`, and
##### it is a different quantity from `ρe_tag_*` in `tagged_tracers.jl`. A source
##### tag holds energy that is present now, traced back to where it came from.
##### An `ρe_tag_*` tag configured with `source` is a signed process tag: it
##### holds the signed increment one process applied. That is not the same as
##### the process-change record, which is the separate `prc_*` family in
##### `process_record.jl`. Both are useful; they answer different questions.
#####
##### This file carries the state, the masks, the transport hook-up and the
##### attribution rule. Production is shared out by region mask and loss is
##### taken from each tag in proportion to what it already holds, which is what
##### makes a tag an amount of energy present rather than a running total. A
##### partition of region tags closes under pure dynamics, and the rule is
##### built to keep that true once sources and sinks are attributed.
#####
##### Tag names are ρ-weighted, so `gs_tracer_names(Y)` picks them up and the
##### usual tracer machinery supplies advection, hyperdiffusion, sponges,
##### vertical eddy diffusion and the implicit-Jacobian blocks. Leave transport
##### to that machinery. Attributing it here would count it twice.
#####
##### Masks are static in space. Evaluate them once when building the cache,
##### outside any per-timestep broadcast.

# ============================================================================
# Names and state
# ============================================================================

# Build a single-entry NamedTuple `(; ρe_src_<name> = value)`. As for the other
# two families, the field name is computed at compile time from the tag's type
# parameter, so this is type-stable and GPU-compatible.
@generated function tag_entry(::EnergySourceTag{name}, value) where {name}
    field_name = Symbol(:ρe_src_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

# Compile-time lookup of the entry `ρe_src_<name>` in a state or tendency
# `Field` (e.g. `Yₜ.c`) or in the mask cache `NamedTuple`.
@generated tag_field(obj, ::EnergySourceTag{name}) where {name} =
    :(obj.$(Symbol(:ρe_src_, name)))

# Region-less tags carry no mask, exactly as for the other two families.
_tag_mask_entry(ᶜcoord, ::EnergySourceTag{name, Nothing}) where {name} = (;)
_tag_mask_entry(ᶜcoord, tag::EnergySourceTag) =
    tag_entry(tag, region_mask.(Ref(tag.region), ᶜcoord))

"""
    energy_source_tagging_variables(ρe_tot, local_geometry, model)

NamedTuple of tagged prognostic fields `(; ρe_src_<name₁> = ..., ...)` for a
single grid point, to be splatted into the center prognostic state alongside the
other grid-scale variables. Returns `(;)` when energy source tagging is disabled
(`model === nothing`).

Initial values come from `tag_initial_value`, so a pure region tag starts as its
masked share of `ρe_tot` and a tag carrying a source starts at zero.
"""
energy_source_tagging_variables(ρe_tot, local_geometry, ::Nothing) = (;)
energy_source_tagging_variables(
    ρe_tot,
    local_geometry,
    model::EnergySourceTaggingModel,
) = _energy_source_variables(ρe_tot, local_geometry.coordinates, model.tags)

_energy_source_variables(ρe_tot, coord, ::Tuple{}) = (;)
_energy_source_variables(ρe_tot, coord, tags::Tuple) = merge(
    tag_entry(first(tags), tag_initial_value(first(tags), ρe_tot, coord)),
    _energy_source_variables(ρe_tot, coord, Base.tail(tags)),
)

"""
    energy_source_tag_state_names(model::EnergySourceTaggingModel)

`Tuple` of the state-field `Symbol`s (`:ρe_src_<name>`) of every tag.
"""
energy_source_tag_state_names(model::EnergySourceTaggingModel) =
    Tuple(Symbol(:ρe_src_, tag_name(tag)) for tag in model.tags)

"""
    energy_source_region_tag_state_names(model::EnergySourceTaggingModel)

`Tuple` of the state-field `Symbol`s of the pure region tags: those with a
region and no sources. These are the tags whose sum is expected to track
`ρe_tot`, so they are what the closure residual is summed over.
"""
energy_source_region_tag_state_names(model::EnergySourceTaggingModel) = Tuple(
    Symbol(:ρe_src_, tag_name(tag)) for
    tag in model.tags if !isnothing(tag.region) && isempty(tag.sources)
)

"""
    is_energy_source_tag_name(name)

Whether `name` (a `Symbol` like `:ρe_src_tropics`, or a
`MatrixFields.FieldName`) refers to an energy source tag.
"""
is_energy_source_tag_name(name::Symbol) = startswith(string(name), "ρe_src_")
is_energy_source_tag_name(name::MatrixFields.FieldName) =
    is_energy_source_tag_name(MatrixFields.extract_first(name))

# ============================================================================
# Cache
# ============================================================================

"""
    _energy_source_tagging_cache(Y, model)

Cache entries used by the energy source tags, merged into `p.tagging`; `nothing`
when they are disabled. Contains `ᶜenergy_source_masks`, one static center
`Field` per region tag holding the smooth spatial mask of that tag's region,
keyed like the state (`ρe_src_<name>`). Masks are evaluated once here and never
inside a per-timestep broadcast.
"""
_energy_source_tagging_cache(Y, ::Nothing) = nothing
function _energy_source_tagging_cache(Y, model::EnergySourceTaggingModel)
    ᶜenergy_source_masks = _tag_masks(Fields.coordinate_field(Y.c), model.tags)
    _check_region_partition(
        ᶜenergy_source_masks,
        energy_source_region_tag_state_names(model),
        "e_src_res",
        "ρe_src",
    )
    _check_parent_positivity(Y)
    return (; ᶜenergy_source_masks)
end

# The donor share `φ_k = ρe_src_k / ρe_tot` needs a positive parent to mean
# anything. Moist total energy has no physical zero, so a shifted thermodynamic
# or gravitational reference can put part of the domain at or below it, and
# there the shares are undefined and `energy_source_fraction` returns zero
# instead.
#
# This runs unconditionally at initialization, because nothing else will say so.
# The closure check reports `nonpositive_fraction` every time it fires, but it
# is optional: a run with source tags and no `energy_source_closure_check` would
# otherwise get no warning at all. A bad reference is bad from t = 0, so
# checking the initial state catches the case that matters without costing a
# reduction every step.
#
# `sum` is used rather than `minimum` because `sum` is the reduction documented
# to reduce across processes.
function _check_parent_positivity(Y)
    ᶜρe_tot = Y.c.ρe_tot
    ᶜflag = similar(ᶜρe_tot)
    @. ᶜflag = ifelse(ᶜρe_tot <= zero(ᶜρe_tot), one(ᶜρe_tot), zero(ᶜρe_tot))
    nonpositive_volume = sum(ᶜflag)
    iszero(nonpositive_volume) && return nothing
    @. ᶜflag = one(ᶜρe_tot)
    volume = sum(ᶜflag)
    fraction = iszero(volume) ? nonpositive_volume : nonpositive_volume / volume
    @warn(
        "`ρe_tot` is non-positive over $(fraction * 100)% of the domain " *
        "volume at initialization. The energy source tags divide by it to get " *
        "each tag's donor share, so the shares are undefined there and " *
        "`energy_source_fraction` returns zero rather than a meaningful " *
        "number. Moist total energy has no physical zero, so this usually " *
        "means the chosen thermodynamic or gravitational reference puts part " *
        "of the domain below it. Tag values elsewhere are still computed, but " *
        "they are conditional on that reference. Enable " *
        "`energy_source_closure_check` to keep watching it during the run.",
    )
    return nothing
end

# ============================================================================
# Attribution
# ============================================================================

"""
    energy_source_fraction(ρe_src, ρe_tot)

The donor share `φ = ρe_src / ρe_tot` of a tag in the local moist energy,
clamped to `[0, 1]` and defined to be zero where `ρe_tot` is not positive.

This is the energy counterpart of `water_tag_fraction`, and it carries one
weakness that the water version does not. `ρq_tot > 0` is enforced by the parent
model, so a water donor share is always well posed. `ρe_tot` has no physical
zero: it depends on the chosen thermodynamic and gravitational energy reference,
and a shift of that reference can make it non-positive somewhere. The fallback
below keeps the arithmetic finite there, but it does not make the answer
meaningful. A configuration whose `ρe_tot` goes non-positive anywhere is one
whose source shares cannot be interpreted, and the run reports that through
`e_src_res` rather than silently.
"""
@inline energy_source_fraction(ρe_src, ρe_tot) =
    ρe_tot > zero(ρe_tot) ?
    min(max(ρe_src / ρe_tot, zero(ρe_tot)), one(ρe_tot)) : zero(ρe_tot)

"""
    snapshot_energy_source_tags!(p, Yₜ)

Record the current `Yₜ.c.ρe_tot` in `p.scratch`, opening an attribution bracket
for the energy source tags. A no-op when they are disabled.

Paired with [`attribute_energy_source_tags!`](@ref). This uses its own buffer
rather than the one the `ρe_tag_*` family uses, so that either family can be
configured without the other.
"""
snapshot_energy_source_tags!(p, Yₜ) = _snapshot_energy_source_tags!(
    p,
    Yₜ,
    p.atmos.energy_source_tagging_model,
)
_snapshot_energy_source_tags!(p, Yₜ, ::Nothing) = nothing
function _snapshot_energy_source_tags!(p, Yₜ, ::EnergySourceTaggingModel)
    p.scratch.ᶜe_src_snapshot .= Yₜ.c.ρe_tot
    return nothing
end

"""
    attribute_energy_source_tags!(Yₜ, Y, p, source::Symbol)

Close a bracket opened by [`snapshot_energy_source_tags!`](@ref): compute the
increment `Δ = Yₜ.c.ρe_tot - snapshot` produced by the bracketed process
(labeled `source`) and add `M_k·Δ⁺ - φ_k·Δ⁻` to each tag's tendency, where `M_k`
is the tag's mask and `φ_k` its donor share of the local moist energy.

Production reaches a tag only when it lists `source`; pure region tags list none
and so receive every process. Loss reaches **every** tag, whatever it lists,
because energy leaves in proportion to what is actually present. That asymmetry
is what makes a tag an amount rather than a running total. It is the same rule
the water tags use, and the opposite of the `ρe_tag_*` family, which applies the
whole signed increment by mask.

This step does not keep a tag non-negative, and nothing downstream does either.
What it produces is a tendency: the loss term sets the *rate* a tag is depleted
at, in proportion to what it holds, but the timestepper integrates that over a
finite step and the amount removed is roughly `dt * φ_k * Δ⁻`. Nothing bounds
that by the holding. Where `ρe_tot` is not positive the share is undefined and
[`energy_source_fraction`](@ref) returns zero, so no loss is attributed there at
all. The tags are also exempt from both tracer limiters and ride the unlimited
explicit transport path, and unlike the water tags there is no partition repair.
See the contract on [`EnergySourceTag`](@ref).

`Y` is needed in addition to `Yₜ` because the donor share is a property of the
current state. A no-op when energy source tagging is disabled.
"""
attribute_energy_source_tags!(Yₜ, Y, p, source::Symbol) =
    _attribute_energy_source_tags!(
        Yₜ,
        Y,
        p,
        source,
        p.atmos.energy_source_tagging_model,
    )
_attribute_energy_source_tags!(Yₜ, Y, p, source, ::Nothing) = nothing
function _attribute_energy_source_tags!(
    Yₜ,
    Y,
    p,
    source,
    model::EnergySourceTaggingModel,
)
    (; ᶜenergy_source_masks) = p.tagging
    ᶜsnapshot = p.scratch.ᶜe_src_snapshot
    ᶜΔ = @. lazy(Yₜ.c.ρe_tot - ᶜsnapshot)
    _accumulate_energy_source_tags!(
        Yₜ.c,
        Y.c,
        ᶜenergy_source_masks,
        ᶜΔ,
        source,
        model.tags,
    )
    return nothing
end

# The split `Δ = Δ⁺ - Δ⁻` appears below as `max(Δ, 0)` and `min(Δ, 0)`, written
# the same way as in `tagged_water.jl` and for the same two reasons: it keeps the
# update in one broadcast, and a `-` directly before a modifier letter such as
# `ᶜ` parses as the suffixed operator `-ᶜ`, which Julia leaves undefined.
_accumulate_energy_source_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, ::Tuple{}) = nothing
function _accumulate_energy_source_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tags::Tuple,
)
    _accumulate_energy_source_tag!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, first(tags))
    return _accumulate_energy_source_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        Base.tail(tags),
    )
end

# Region-less tag: production weight is 1 wherever the tag receives this source.
function _accumulate_energy_source_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::EnergySourceTag{name, Nothing},
) where {name}
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            max(ᶜΔ, 0) +
            min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜY.ρe_tot)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜY.ρe_tot)
    end
    return nothing
end

# Tag with a region: production is masked. Loss stays donor-proportional, so
# energy leaves from wherever the tag is holding it.
function _accumulate_energy_source_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::EnergySourceTag,
)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜmask = tag_field(ᶜmasks, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            ᶜmask * max(ᶜΔ, 0) +
            min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜY.ρe_tot)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜY.ρe_tot)
    end
    return nothing
end
