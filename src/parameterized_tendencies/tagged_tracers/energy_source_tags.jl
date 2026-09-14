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
when they are disabled. Contains:

  - `ᶜenergy_source_masks`: one static center `Field` per region tag holding
    the smooth spatial mask of that tag's region, keyed like the state
    (`ρe_src_<name>`). Masks are evaluated once here and never inside a
    per-timestep broadcast.
  - `ᶜenergy_source_fix`: one center `Field` per tag, accumulating the energy
    that `repair_energy_source_tags!` has moved into or out of it. It is
    reported as `e_src_fix_<name>`. It lives in the cache, so it restarts at
    zero, as the water tags' ledger does.
  - `ᶜenergy_source_pos` and `ᶜenergy_source_neg`: the positive and negative
    parts of the partition's sum, which the repair fills itself.
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
    # The ledger exists whether or not the repair is on, so that
    # `e_src_fix_<name>` reads zero rather than failing when it is off.
    ᶜenergy_source_fix = _energy_source_fix_fields(Y.c.ρ, model.tags)
    ᶜenergy_source_pos = zero.(Y.c.ρ)
    ᶜenergy_source_neg = zero.(Y.c.ρ)
    return (;
        ᶜenergy_source_masks,
        ᶜenergy_source_fix,
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
    )
end

_energy_source_fix_fields(ᶜρ, ::Tuple{}) = (;)
_energy_source_fix_fields(ᶜρ, tags::Tuple) = merge(
    tag_entry(first(tags), zero.(ᶜρ)),
    _energy_source_fix_fields(ᶜρ, Base.tail(tags)),
)

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
with `ρq_tot ≤ 0` is a numerical artifact, though not a rare one: nothing in the
model enforces the bound and a sphere run routinely has it over part of its
volume. Moist total energy has no physical zero at all, because it depends on
the chosen thermodynamic and gravitational reference, and a shift of that
reference can put a whole region below zero at once. The
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

This step does not keep a tag non-negative. What it produces is a tendency: the
loss term sets the *rate* a tag is depleted at, in proportion to what it holds,
but the timestepper integrates that over a finite step and the amount removed is
roughly `dt * φ_k * Δ⁻`. Nothing here bounds that by the holding. Where the
total is not positive the share is undefined and
[`energy_source_fraction`](@ref) returns zero, so no loss is attributed there at
all. The tags are also exempt from both tracer limiters and ride the unlimited
explicit transport path. What puts a negative tag back, where the total is
positive, is `repair_energy_source_tags!`, after each state update, unless
`energy_source_tag_repair` is off. See the contract on
[`EnergySourceTag`](@ref).

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

# ============================================================================
# Repair
# ============================================================================

# A pure region tag has a region and no sources. Those tags partition the total,
# and the repair keeps their sum. Both properties are type parameters, so this
# resolves at compile time, as `_is_partition_tag` does for the water tags.
_is_energy_partition_tag(
    ::EnergySourceTag{name, R, Tuple{}},
) where {name, R <: AbstractTagRegion} = true
_is_energy_partition_tag(::EnergySourceTag) = false

"""
    energy_source_partition_repair(ρe_src, pos, neg, parent)

The value `repair_energy_source_tags!` gives a partition tag. `pos` and `neg` are
the positive and negative parts of the partition's sum in the same cell, and
`parent` is the total the tags partition there.

Where `parent` is positive, a negative tag is set to zero and the positive tags
are scaled by the common factor `max(pos + neg, 0) / pos`, the factor of the
water tags' repair, `water_tag_repair_factor`. The sum `pos + neg` is kept
exactly and every tag ends non-negative. Where the negatives outweigh the
positives, no non-negative partition has that sum, so every tag is zeroed, as
the water repair does.

Where `parent` is not positive the tag is left as it is. The donor share is
undefined there, and a region tag carries the parent's sign by design, so a
negative value is not an error to repair. Under the default energy reference
that is much of the troposphere. With a large enough `energy_source_tag_offset`
it is nowhere.
"""
@inline energy_source_partition_repair(ρe_src, pos, neg, parent) =
    parent > zero(parent) ?
    max(ρe_src, zero(ρe_src)) * water_tag_repair_factor(pos, neg) : ρe_src

"""
    energy_source_overlay_repair(ρe_src, parent)

The value `repair_energy_source_tags!` gives a tag that carries a source. Such a
tag is not a member of the partition. It marks the part of the total that came
in through its processes. Where `parent` is positive a negative value is set to
zero; elsewhere the tag is left alone, for the reason
`energy_source_partition_repair` gives.

There is no sum to keep, so the energy the clip adds comes from nowhere within
the tags. The ledger records it.
"""
@inline energy_source_overlay_repair(ρe_src, parent) =
    parent > zero(parent) ? max(ρe_src, zero(ρe_src)) : ρe_src

"""
    repair_energy_source_tags!(Y, p)

Keep the energy source tags non-negative where their total is positive.

The tags go negative for the reasons given in `docs/src/energy_source_tags.md`:
the finite step of the donor loss, and unlimited explicit transport with no
limiter. A negative tag voids its reading as an amount of energy from
somewhere. Through the clamp in `energy_source_fraction` it also distorts what
the other tags lose. This puts the tags back in range after each state update:

  - the partition tags keep their sum, through `energy_source_partition_repair`;
  - a tag that carries a source is clipped at zero, through
    `energy_source_overlay_repair`.

Both act only where the total the tags partition is positive, which is
everywhere with a large enough `energy_source_tag_offset`.

It does **not** force the region tags to add up to the total. That would drive
`e_src_res` to zero by construction and hide the transport mismatch the residual
exists to show. It removes only the negativity, as the water tags' partition
repair does.

Every change is added to `p.tagging.ᶜenergy_source_fix` and reported as
`e_src_fix_<name>`, so what the repair did stays distinguishable from what the
rule and the transport did. For the partition tags these changes sum to zero in
each cell, except where the negatives outweighed the positives and every tag was
zeroed. The ledger equals what the repair changed in the accepted state only at
the default `update_constrain_state_every: step`. At `stage` or `dss` the repair
also runs inside the step, where the stepper rescales or discards what it
changes, as it does for the water tags' `q_tag_fix`. The tags end each step
repaired either way.

On by default. `energy_source_tag_repair: false` switches it off, and leaves the
tags exactly as the rule and their transport make them, negative values
included. Called from `constrain_state!` after the water tags' repair. A no-op
when energy source tagging is disabled.
"""
repair_energy_source_tags!(Y, p) =
    _repair_energy_source_tags!(Y, p, p.atmos.energy_source_tagging_model)
_repair_energy_source_tags!(Y, p, ::Nothing) = nothing
function _repair_energy_source_tags!(Y, p, model::EnergySourceTaggingModel)
    model.repair || return nothing
    (; ᶜenergy_source_fix, ᶜenergy_source_pos, ᶜenergy_source_neg) = p.tagging
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    ᶜenergy_source_pos .= zero(eltype(ᶜenergy_source_pos))
    ᶜenergy_source_neg .= zero(eltype(ᶜenergy_source_neg))
    _accumulate_energy_source_partition!(
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
        Y.c,
        model.tags,
    )
    _apply_energy_source_repair!(
        Y.c,
        ᶜenergy_source_fix,
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
        ᶜparent,
        model.tags,
    )
    return nothing
end

# The partition's sum split into its positive and negative parts, over the pure
# region tags only. The tags that carry a source are outside the partition.
_accumulate_energy_source_partition!(ᶜpos, ᶜneg, ᶜY, ::Tuple{}) = nothing
function _accumulate_energy_source_partition!(ᶜpos, ᶜneg, ᶜY, tags::Tuple)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜρe_src = tag_field(ᶜY, tag)
        @. ᶜpos += max(ᶜρe_src, 0)
        @. ᶜneg += min(ᶜρe_src, 0)
    end
    return _accumulate_energy_source_partition!(
        ᶜpos,
        ᶜneg,
        ᶜY,
        Base.tail(tags),
    )
end

# `ᶜpos` and `ᶜneg` come from the state before the repair and are only read
# here, so each tag can be rewritten in place and a later tag's factor still
# holds. The ledger is written first, so it records the correction itself.
_apply_energy_source_repair!(ᶜY, ᶜfix, ᶜpos, ᶜneg, ᶜparent, ::Tuple{}) =
    nothing
function _apply_energy_source_repair!(
    ᶜY,
    ᶜfix,
    ᶜpos,
    ᶜneg,
    ᶜparent,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜtag_fix = tag_field(ᶜfix, tag)
    if _is_energy_partition_tag(tag)
        @. ᶜtag_fix +=
            energy_source_partition_repair(ᶜρe_src, ᶜpos, ᶜneg, ᶜparent) -
            ᶜρe_src
        @. ᶜρe_src =
            energy_source_partition_repair(ᶜρe_src, ᶜpos, ᶜneg, ᶜparent)
    else
        @. ᶜtag_fix += energy_source_overlay_repair(ᶜρe_src, ᶜparent) - ᶜρe_src
        @. ᶜρe_src = energy_source_overlay_repair(ᶜρe_src, ᶜparent)
    end
    return _apply_energy_source_repair!(
        ᶜY,
        ᶜfix,
        ᶜpos,
        ᶜneg,
        ᶜparent,
        Base.tail(tags),
    )
end
