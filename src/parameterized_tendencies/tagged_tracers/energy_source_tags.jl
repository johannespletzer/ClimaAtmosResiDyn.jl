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
##### tag holds energy that is present now, traced back to where it came from,
##### which holds only where the partitioned total is positive and the tag is
##### non-negative. That total is `ρe_tot`, or `ρe_tot + c·ρ` under an offset.
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
##### `energy_source_tag_offset` gives the tags a total the model never uses,
##### `ρe_tot + c·ρ`, which can be positive where `ρe_tot` is not. Every place
##### below that reads the parent goes through `energy_source_parent` or one of
##### its field forms, so without an offset the arithmetic is exactly as before.
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
    energy_source_tagging_variables(ρe_parent, local_geometry, model)

NamedTuple of tagged prognostic fields `(; ρe_src_<name₁> = ..., ...)` for a
single grid point, to be splatted into the center prognostic state alongside the
other grid-scale variables. Returns `(;)` when energy source tagging is disabled
(`model === nothing`).

`ρe_parent` is the total the tags partition, from `energy_source_parent`:
`ρe_tot`, or `ρe_tot + c·ρ` with an offset. Initial values come from
`tag_initial_value`, so a pure region tag starts as its masked share of that
total and a tag carrying a source starts at zero.
"""
energy_source_tagging_variables(ρe_parent, local_geometry, ::Nothing) = (;)
energy_source_tagging_variables(
    ρe_parent,
    local_geometry,
    model::EnergySourceTaggingModel,
) = _energy_source_variables(ρe_parent, local_geometry.coordinates, model.tags)

_energy_source_variables(ρe_parent, coord, ::Tuple{}) = (;)
_energy_source_variables(ρe_parent, coord, tags::Tuple) = merge(
    tag_entry(first(tags), tag_initial_value(first(tags), ρe_parent, coord)),
    _energy_source_variables(ρe_parent, coord, Base.tail(tags)),
)

"""
    energy_source_parent(ρe_tot, ρ, model)

The total the energy source tags partition at one point: `ρe_tot` itself, or
`ρe_tot + c·ρ` when `model` carries an offset `c` in J/kg.

The model never uses this total. Only the tags see it, so an offset changes what
they split and leaves the simulated atmosphere exactly as it was. That is the
reason for it. `ρe_tot` has no physical zero, and under the default energy
reference it is negative over much of a typical domain, where the donor share
`ρe_src_k / ρe_tot` is undefined. A large enough `c` makes the total positive
everywhere without moving the thermodynamic reference, which would reach the
model's own numerics. See `docs/src/energy_source_tags.md`.

`c·ρ` is energy carried by mass, so a process that changes `ρ` changes the total
by `c` times that change. The attribution bracket counts it for the processes it
covers, which are the labels in `KNOWN_TAG_SOURCES`. A process that writes
`Yₜ.c.ρ` under any other label, or under none, moves the offset total without
reaching a tag, and that difference lands in `e_src_res`. Vertical diffusion,
the viscous sponge, the LES SGS closures and hyperdiffusion are all in that
group, so the residual carries a `c`-proportional term wherever they are active
that it did not carry without an offset. A constant per unit mass does pass
unchanged through transport that is consistent with the mass flux, and through
limiters built on differences.
"""
@inline energy_source_parent(ρe_tot, ρ, ::Nothing) = ρe_tot
@inline energy_source_parent(ρe_tot, ρ, model::EnergySourceTaggingModel) =
    _offset_parent(ρe_tot, ρ, model.offset)

# The same total from the offset alone, so that it can be broadcast. `nothing`
# broadcasts as a scalar.
@inline _offset_parent(ρe_tot, ρ, ::Nothing) = ρe_tot
@inline _offset_parent(ρe_tot, ρ, offset) = ρe_tot + offset * ρ

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
    _check_parent_positivity(Y, model)
    return (; ᶜenergy_source_masks)
end

"""
    energy_source_scratch(Y, model)

Scratch fields of the energy source tags, merged into `p.scratch`: the
bracket's snapshot of `Yₜ.c.ρe_tot`, and with an offset also a snapshot of
`Yₜ.c.ρ` and a field the closure check fills with the offset total.
"""
energy_source_scratch(Y, model::EnergySourceTaggingModel) =
    _energy_source_scratch(Y, model.offset)
_energy_source_scratch(Y, ::Nothing) = (; ᶜe_src_snapshot = similar(Y.c.ρ))
_energy_source_scratch(Y, offset) = (;
    ᶜe_src_snapshot = similar(Y.c.ρ),
    ᶜe_src_ρ_snapshot = similar(Y.c.ρ),
    ᶜe_src_parent = similar(Y.c.ρ),
)

"""
    energy_source_closure_total(model)

What the energy source closure check compares its region tags against, in the
form `closure_parent` takes: `:ρe_tot`, or with an offset a function that fills
a scratch field with the offset total and returns it.
"""
energy_source_closure_total(::Nothing) = :ρe_tot
energy_source_closure_total(model::EnergySourceTaggingModel) =
    _energy_source_closure_total(model.offset)
_energy_source_closure_total(::Nothing) = :ρe_tot
_energy_source_closure_total(offset) =
    (Y, p) -> _fill_energy_source_parent!(p.scratch.ᶜe_src_parent, Y, offset)
function _fill_energy_source_parent!(ᶜparent, Y, offset)
    @. ᶜparent = Y.c.ρe_tot + offset * Y.c.ρ
    return ᶜparent
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
#
# With an offset the check is made on the offset total, since that is what the
# shares divide by.
function _check_parent_positivity(Y, model)
    ᶜρe_tot = Y.c.ρe_tot
    offset = model.offset
    ᶜflag = similar(ᶜρe_tot)
    @. ᶜflag = ifelse(
        _offset_parent(ᶜρe_tot, Y.c.ρ, offset) <= zero(ᶜρe_tot),
        one(ᶜρe_tot),
        zero(ᶜρe_tot),
    )
    nonpositive_volume = sum(ᶜflag)
    iszero(nonpositive_volume) && return nothing
    @. ᶜflag = one(ᶜρe_tot)
    volume = sum(ᶜflag)
    fraction = iszero(volume) ? nonpositive_volume : nonpositive_volume / volume
    parent =
        isnothing(offset) ? "`ρe_tot`" :
        "`ρe_tot + $(offset)·ρ`, the total the energy source tags partition,"
    @warn(
        "$parent is non-positive over $(fraction * 100)% of the domain " *
        "volume at initialization. The energy source tags divide by it to get " *
        "each tag's donor share, so the shares are undefined there and " *
        "`energy_source_fraction` returns zero rather than a meaningful " *
        "number. Moist total energy has no physical zero, so this usually " *
        "means the chosen thermodynamic or gravitational reference puts part " *
        "of the domain below it. Tag values elsewhere are still computed, but " *
        "they are conditional on that reference. A large enough " *
        "`energy_source_tag_offset` gives the tags a positive total without " *
        "moving the model's reference. Enable `energy_source_closure_check` " *
        "to keep watching it during the run.",
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

This is the energy counterpart of `water_tag_fraction`, and the two share the
same weakness for different reasons. Total water has a physical zero, so a cell
with `ρq_tot ≤ 0` is a numerical artifact and a rare one; moist total energy has
none, because it depends on the chosen thermodynamic and gravitational reference,
and a shift of that reference can put a whole region below zero at once. The
fallback below keeps the arithmetic finite in either case, but it does not make
the answer meaningful. A configuration whose `ρe_tot` goes non-positive anywhere
is one whose source shares cannot be interpreted there, and the run reports that
through `e_src_res` and through the `nonpositive_fraction` column of its closure
table rather than silently.

With `energy_source_tag_offset` the second argument is the offset total
`ρe_tot + c·ρ` rather than `ρe_tot`; see `energy_source_parent`.
"""
@inline energy_source_fraction(ρe_src, ρe_tot) =
    ρe_tot > zero(ρe_tot) ?
    min(max(ρe_src / ρe_tot, zero(ρe_tot)), one(ρe_tot)) : zero(ρe_tot)

"""
    snapshot_energy_source_tags!(p, Yₜ)

Record the current `Yₜ.c.ρe_tot` in `p.scratch`, opening an attribution bracket
for the energy source tags, and with an offset `Yₜ.c.ρ` as well. A no-op when
they are disabled.

Paired with [`attribute_energy_source_tags!`](@ref). This uses its own buffers
rather than the ones the `ρe_tag_*` family uses, so that the two can be
configured independently.
"""
snapshot_energy_source_tags!(p, Yₜ) = _snapshot_energy_source_tags!(
    p,
    Yₜ,
    p.atmos.energy_source_tagging_model,
)
_snapshot_energy_source_tags!(p, Yₜ, ::Nothing) = nothing
function _snapshot_energy_source_tags!(p, Yₜ, model::EnergySourceTaggingModel)
    p.scratch.ᶜe_src_snapshot .= Yₜ.c.ρe_tot
    _snapshot_mass!(p, Yₜ, model.offset)
    return nothing
end
_snapshot_mass!(p, Yₜ, ::Nothing) = nothing
function _snapshot_mass!(p, Yₜ, offset)
    p.scratch.ᶜe_src_ρ_snapshot .= Yₜ.c.ρ
    return nothing
end

"""
    attribute_energy_source_tags!(Yₜ, Y, p, source::Symbol)

Close a bracket opened by [`snapshot_energy_source_tags!`](@ref): compute the
increment `Δ = Yₜ.c.ρe_tot - snapshot` produced by the bracketed process
(labeled `source`) and add `M_k·Δ⁺ - φ_k·Δ⁻` to each tag's tendency, where `M_k`
is the tag's mask and `φ_k` its donor share of the local moist energy.

With an offset `c` the increment is that of the offset total instead,
`Δ + c·(Yₜ.c.ρ - ρ snapshot)`, and `φ_k` is the share of `ρe_tot + c·ρ`. A
process that moves mass then moves the offset energy that mass carries, so the
region tags still account for the whole increment.

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
    ᶜΔ = _energy_source_increment(Yₜ, p.scratch, model.offset)
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    _accumulate_energy_source_tags!(
        Yₜ.c,
        Y.c,
        ᶜenergy_source_masks,
        ᶜΔ,
        source,
        model.tags,
        ᶜparent,
    )
    return nothing
end

# The bracketed process's increment to the total the tags partition. With an
# offset `c`, a process that changes the mass changes the total by `c` times
# that change. The two differences are taken separately, so the large
# tendencies accumulated before the bracket cancel within each field rather than
# across them.
function _energy_source_increment(Yₜ, scratch, ::Nothing)
    ᶜsnapshot = scratch.ᶜe_src_snapshot
    return @. lazy(Yₜ.c.ρe_tot - ᶜsnapshot)
end
function _energy_source_increment(Yₜ, scratch, offset)
    ᶜsnapshot = scratch.ᶜe_src_snapshot
    ᶜρ_snapshot = scratch.ᶜe_src_ρ_snapshot
    return @. lazy((Yₜ.c.ρe_tot - ᶜsnapshot) + offset * (Yₜ.c.ρ - ᶜρ_snapshot))
end

# The total the donor share divides by, as a field: `Y.c.ρe_tot` itself without
# an offset, so that path is unchanged, and a lazy sum with one.
_energy_source_parent_field(Y, ::Nothing) = Y.c.ρe_tot
_energy_source_parent_field(Y, offset) = @. lazy(Y.c.ρe_tot + offset * Y.c.ρ)

# The split `Δ = Δ⁺ - Δ⁻` appears below as `max(Δ, 0)` and `min(Δ, 0)`, written
# the same way as in `tagged_water.jl` and for the same two reasons: it keeps the
# update in one broadcast, and a `-` directly before a modifier letter such as
# `ᶜ` parses as the suffixed operator `-ᶜ`, which Julia leaves undefined.
#
# `ᶜparent` is the total the donor share divides by. Called without it, it is
# `ᶜY.ρe_tot`, which is what a model without an offset uses.
_accumulate_energy_source_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, tags::Tuple) =
    _accumulate_energy_source_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        tags,
        ᶜY.ρe_tot,
    )
_accumulate_energy_source_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, ::Tuple{}, ᶜparent) =
    nothing
function _accumulate_energy_source_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tags::Tuple,
    ᶜparent,
)
    _accumulate_energy_source_tag!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        first(tags),
        ᶜparent,
    )
    return _accumulate_energy_source_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        Base.tail(tags),
        ᶜparent,
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
    ᶜparent,
) where {name}
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            max(ᶜΔ, 0) + min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
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
    ᶜparent,
)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜmask = tag_field(ᶜmasks, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            ᶜmask * max(ᶜΔ, 0) +
            min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    end
    return nothing
end
