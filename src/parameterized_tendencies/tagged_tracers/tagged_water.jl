#####
##### Tagged prognostic water tracers
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρq_tag_<name>` that holds
##### part of the total water `ρq_tot`. Regions, masks, state entries and
##### restarts are shared with the energy tags in `tagged_tracers.jl`. Config
##### parsing is in `config/tracer_config.jl`. The physics is in
##### `docs/src/tagged_water.md`.
#####
##### The usual tracer machinery transports the tags, so only the processes in
##### `KNOWN_WATER_TAG_SOURCES` are attributed. A process's tendency gives
##### production to the tags by region mask and takes loss in proportion to what
##### each tag holds. Each tag's sedimentation flux is built like the parent's
##### and scaled by its share. `ρq_tot` is advected implicitly and the tags
##### explicitly, which is the one unavoidable source of tag closure drift
##### (`q_tag_res`). Under `water_tag_precipitation: true` every share below
##### divides by `water_tag_parent` (see `tagged_water_precipitation.jl`).

# ============================================================================
# Names, state, and initial values
# ============================================================================

# Build a single-entry NamedTuple `(; ρq_tag_<name> = value)`. As for the energy
# tags, the field name is computed at compile time from the tag's type
# parameter, so this is type-stable and GPU-compatible.
@generated function tag_entry(::WaterTag{name}, value) where {name}
    field_name = Symbol(:ρq_tag_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

# Compile-time lookup of the entry `ρq_tag_<name>` in a state or tendency
# `Field` (e.g. `Yₜ.c`) or in a keyed cache `NamedTuple`.
@generated tag_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:ρq_tag_, name)))

# The tag's state field as a `MatrixFields.FieldName` relative to `Y.c`, the
# form the Jacobian indexes blocks by. `@name` needs a literal, so the name is
# built from the tag's type parameter instead. The result is a singleton type,
# so this stays a compile-time constant.
@generated function water_tag_field_name(::WaterTag{name}) where {name}
    field_name = Symbol(:ρq_tag_, name)
    return :(MatrixFields.FieldName($(QuoteNode(field_name))))
end

"""
    water_tagging_variables(ρq_tot, local_geometry, water_tagging_model)

NamedTuple of tagged prognostic water fields `(; ρq_tag_<name₁> = ..., ...)` for
a single grid point, to be splatted into the center prognostic state alongside
the other grid-scale variables. Returns `(;)` when water tagging is disabled
(`water_tagging_model === nothing`).

Must be evaluated with the same `ρq_tot` that `moisture_variables` puts into the
state. Then region tags whose masks sum to 1 sum to the partition's target,
`water_tag_partition_target(ρq_tot)`, exactly at `t = 0`.
"""
water_tagging_variables(ρq_tot, local_geometry, ::Nothing) = (;)
water_tagging_variables(ρq_tot, local_geometry, model::WaterTaggingModel) =
    _tag_variables(
        water_tag_partition_target(ρq_tot),
        local_geometry.coordinates,
        model.tags,
    )

"""
    water_tag_state_names(model::WaterTaggingModel)

`Tuple` of the state-field `Symbol`s (`:ρq_tag_<name>`) of every water tag.
"""
water_tag_state_names(model::WaterTaggingModel) =
    Tuple(Symbol(:ρq_tag_, tag_name(tag)) for tag in model.tags)

"""
    water_region_tag_state_names(model::WaterTaggingModel)

`Tuple` of the state-field `Symbol`s of the region water tags: those with a
region and no sources. These are the tags whose sum is expected to track
`ρq_tot`, and the ones `q_tag_res` sums over. A tag that also carries a `source`
starts at zero and accumulates only that source, so including it would
double-count.
"""
water_region_tag_state_names(model::WaterTaggingModel) = Tuple(
    Symbol(:ρq_tag_, tag_name(tag)) for
    tag in model.tags if !isnothing(tag.region) && isempty(tag.sources)
)

# ============================================================================
# Config parsing
# ============================================================================

"""
    KNOWN_WATER_TAG_SOURCES

`Tuple` of the process labels that can be attributed to a tagged water tracer.
This is a *different, smaller* set than [`KNOWN_TAG_SOURCES`](@ref), because it
lists only the processes that actually move total water:

  - `:surface_flux`: turbulent surface moisture flux (evaporation, or dew when
    the flux is negative)
  - `:microphysics`: the 0-moment total-water sink (`dq_tot_dt ≤ 0`)
  - `:large_scale_advection`: prescribed large-scale advective moistening/drying
  - `:subsidence`: prescribed large-scale subsidence
  - `:external_forcing`: externally prescribed (e.g. GCM-driven) forcing and
    nudging of `q_tot`

Three deliberate absences:

  - `:radiation` and `:held_suarez` appear in `KNOWN_TAG_SOURCES` but do not move
    water. The shared applied-update event still runs at those call sites. The
    water kernel returns without computing a change.
  - `:precipitation` is absent by design. With 0-moment microphysics
    `vertical_advection_of_water_tendency!` has no sedimenting species to loop
    over and is a no-op. With 1-moment it is a flux divergence between levels.
    Each tag gets its own flux, built like the parent's and scaled by its share,
    and not a net source. A net source would double-count and mislabel the water
    arriving from the cell above. See [`sediment_water_tags!`](@ref).
  - `tracer_nonnegativity_vapor_tendency!` moves water between condensate species
    and diagnostic vapor and leaves `ρq_tot` unchanged.

Transport-like tendencies (advection, hyperdiffusion, sponges, vertical and SGS
diffusion) are never attributed: each tag is transported in its own right, so
attributing the `ρq_tot` version on top would count transport twice.

See also [`WATER_TAG_SOURCE_GROUPS`](@ref).
"""
const KNOWN_WATER_TAG_SOURCES = (
    :surface_flux,
    :microphysics,
    :large_scale_advection,
    :subsidence,
    :external_forcing,
)

"""
    WATER_TAG_SOURCE_GROUPS

Named groups of water process labels, usable wherever a `source` is expected:

  - `:surface`: turbulent exchange with the surface
  - `:forcing`: prescribed/idealized forcings (large-scale advection,
    subsidence, external forcing and nudging)
  - `:all`: every process in [`KNOWN_WATER_TAG_SOURCES`](@ref)

Groups expand at configuration time.
"""
const WATER_TAG_SOURCE_GROUPS = (;
    surface = (:surface_flux,),
    forcing = (:large_scale_advection, :subsidence, :external_forcing),
    all = KNOWN_WATER_TAG_SOURCES,
)

"""
    check_water_tagging_supported(microphysics_model)

Throw a descriptive error unless `microphysics_model` is one the water tags can
close against.

  - `EquilibriumMicrophysics0M`: every writer of `ρq_tot` is a *local* source or
    sink, so attributing the processes' tendencies is exact and nothing
    sediments.
  - `NonEquilibriumMicrophysics1M`: the condensate species are prognostic and
    sediment, moving `ρq_tot` between levels. That is a flux divergence rather
    than a local source, so it is not attributed. Each tag gets its own flux,
    built like the parent's and scaled by its share (see
    [`sediment_water_tags!`](@ref)). Under 1M this is the only microphysical
    writer of `ρq_tot`, because `microphysics_tendency!` moves mass between
    species only. So the `:microphysics` applied-update event adds nothing
    there.

2-moment and P3 are unsupported. They add the origin of number concentration,
which is a separate question from the origin of mass that the tags carry.
"""
check_water_tagging_supported(::EquilibriumMicrophysics0M, key = "water_tracers") =
    nothing
check_water_tagging_supported(
    ::NonEquilibriumMicrophysics1M,
    key = "water_tracers",
) = nothing
check_water_tagging_supported(::DryModel, key = "water_tracers") = error(
    "`$key` requires a moist model: with `microphysics_model: dry` " *
    "there is no `ρq_tot` in the prognostic state to partition.",
)
check_water_tagging_supported(model, key = "water_tracers") = error(
    "`$key` supports `microphysics_model: 0M` and `1M` only (got " *
    "$(nameof(typeof(model)))). 2-moment and P3 schemes additionally carry " *
    "prognostic number concentrations, whose origin is a separate question " *
    "from the origin of the water mass these tags partition. Mirroring only the " *
    "mass flux would leave the number field untagged and the two inconsistent.",
)

# ============================================================================
# Cache
# ============================================================================

_tag_mask_entry(ᶜcoord, ::WaterTag{name, Nothing}) where {name} = (;)
_tag_mask_entry(ᶜcoord, tag::WaterTag) =
    tag_entry(tag, region_mask.(Ref(tag.region), ᶜcoord))

_water_fix_fields(ᶜρ, ::Tuple{}) = (;)
_water_fix_fields(ᶜρ, tags::Tuple) = merge(
    tag_entry(first(tags), zero.(ᶜρ)),
    _water_fix_fields(ᶜρ, Base.tail(tags)),
)

"""
    _water_tagging_cache(Y, water_tagging_model)

Cache entries used by water-tag attribution, merged into `p.tagging`. It is
`nothing` when water tagging is disabled. Contains:

  - `ᶜwater_masks`: one static center `Field` per region tag holding the smooth
    spatial mask of that tag's region, keyed like the state (`ρq_tag_<name>`).
    Masks are evaluated once here and never inside a per-timestep broadcast.
  - `ᶜwater_fix`: the fix ledger. One center `Field` per tag accumulating the
    water that the limiters, the state constraints and the partition repair
    have moved into or out of that tag (see [`rescale_water_tags!`](@ref) and
    [`repair_water_tag_partition!`](@ref)). It is cumulative since the start of
    the run and the checkpoint carries it through a restart. A checkpoint with
    none of the tags' accumulators starts them at zero, with a warning. The
    change over an interval is the difference of two outputs.
  - `ᶜwater_fix_gross`, `ᶜwater_fix_count`: the tag's gross beside the fix
    ledger, and the count of its events, in Float64. The gross is the absolute
    value of every change. The count has one per cell-event above rounding
    (`tag_event`). Both cover every call, including changes inside a step the
    stepper discards. See `tag_throughput.jl`.
  - `ᶜwater_pos`, `ᶜwater_neg`: the positive and negative parts of the partition
    sum, `Σₖ max(ρq_tagₖ, 0)` and `Σₖ min(ρq_tagₖ, 0)`. Both corrections use
    them. [`rescale_water_tags!`](@ref) needs only the positive part, as the
    denominator of the share it hands the parent's increment out by.
    [`repair_water_tag_partition!`](@ref) needs both. Each fills them itself
    before use, so neither depends on the other having run. They live in the
    cache rather than `p.scratch` because both corrections run on the real state
    in `limiters_func!` and `constrain_state!`, never inside a dual-typed
    tendency evaluation.

The `ρq_tot` snapshot that [`snapshot_tagged_ρq_tot!`](@ref) records lives in
`p.scratch` instead, because the implicit tendency is evaluated with
`ForwardDiff.Dual` numbers when an automatic-differentiation Jacobian is used and
only `p.precomputed` and `p.scratch` are converted to dual-typed fields.
"""
_water_tagging_cache(Y, ::Nothing) = nothing
# With updraft copies, the copies' repair (`repair_water_tag_copies!`) keeps its
# fix ledger `ᶜwater_upfix`, one field per tag like `ᶜwater_fix`, the residual it
# repaired, for the diagnostic `q_tag_copy_res`, and two sums it reads. The
# updraft filter's ledger keeps the copies' water from before the filter.
_water_copy_cache(Y, model) =
    has_water_tag_updraft_copies(model) ?
    (;
        ᶜwater_upfix = _water_fix_fields(Y.c.ρ, model.tags),
        ᶜwater_upfix_gross = tag_throughput_fields(Y.c.ρ, model.tags),
        ᶜwater_upfix_count = tag_throughput_fields(Y.c.ρ, model.tags),
        ᶜwater_copy_residual = zero.(Y.c.ρ),
        ᶜwater_copy_sum = zero.(Y.c.ρ),
        ᶜwater_copy_pos = zero.(Y.c.ρ),
        ᶜwater_copy_before = zero.(Y.c.ρ),
    ) : (;)
function _water_tagging_cache(Y, model::WaterTaggingModel)
    ᶜwater_masks = _tag_masks(Fields.coordinate_field(Y.c), model.tags)
    _check_region_partition(
        ᶜwater_masks,
        water_region_tag_state_names(model),
        "q_tag_res",
        "ρq_tag",
    )
    _check_water_increment_partition(
        ᶜwater_masks,
        water_region_tag_state_names(model),
        model,
    )
    ᶜwater_fix = _water_fix_fields(Y.c.ρ, model.tags)
    ᶜwater_pos = zero.(Y.c.ρ)
    ᶜwater_neg = zero.(Y.c.ρ)
    return (;
        ᶜwater_masks,
        ᶜwater_fix,
        # The closure check's parent, the partition's target.
        ᶜwater_parent = zero.(Y.c.ρ),
        ᶜwater_fix_gross = tag_throughput_fields(Y.c.ρ, model.tags),
        ᶜwater_fix_count = tag_throughput_fields(Y.c.ρ, model.tags),
        ᶜwater_pos,
        ᶜwater_neg,
        _water_copy_cache(Y, model)...,
        _water_tag_increment_cache(Y, model)...,
        _water_tag_precipitation_cache(Y, model)...,
    )
end

# ============================================================================
# Source attribution
# ============================================================================

"""
    water_tag_fraction(ρq_tag, ρq_tot)

The share `φ = ρq_tag / ρq_tot` of a tag in the local total water, clamped to
`[0, 1]` and zero where the parent is not positive. The clamp keeps the rule well
posed when the tags have drifted slightly out of partition through transport
leakage, and when `ρq_tot` is positive but negligible.
"""
@inline water_tag_fraction(ρq_tag, ρq_tot) =
    ρq_tot > zero(ρq_tot) ?
    min(max(ρq_tag / ρq_tot, zero(ρq_tot)), one(ρq_tot)) : zero(ρq_tot)

# Whether `water_tag_fraction` is the unclamped share `ρq_tag / ρq_tot`, so that
# it moves with both. At the clamp's two ends it takes the unclamped slope.
@inline _water_tag_fraction_unclamped(ρq_tag, ρq_tot) =
    ρq_tot > zero(ρq_tot) && zero(ρq_tot) <= ρq_tag / ρq_tot <= one(ρq_tot)

"""
    water_tag_fraction_derivative_tag(ρq_tag, ρq_tot)

The derivative of [`water_tag_fraction`](@ref) in `ρq_tag`: `1 / ρq_tot` where
the unclamped share lies in `[0, 1]`. Where the clamp binds, or where there is
no water, the share does not move, so it is zero. The implicit Jacobian's
rain-out entries use it (`water_tag_rainout_jacobian`).
"""
@inline water_tag_fraction_derivative_tag(ρq_tag, ρq_tot) =
    _water_tag_fraction_unclamped(ρq_tag, ρq_tot) ? inv(ρq_tot) : zero(ρq_tot)

"""
    water_tag_fraction_derivative_parent(ρq_tag, ρq_tot)

The derivative of [`water_tag_fraction`](@ref) in `ρq_tot`: `−ρq_tag / ρq_tot²`
where the unclamped share lies in `[0, 1]`, and zero elsewhere, as for
`water_tag_fraction_derivative_tag`.
"""
@inline water_tag_fraction_derivative_parent(ρq_tag, ρq_tot) =
    _water_tag_fraction_unclamped(ρq_tag, ρq_tot) ?
    -(ρq_tag / ρq_tot) / ρq_tot : zero(ρq_tot)

"""
    water_tag_partition_target(ρq_tot)
    water_tag_negative_part(ρq_tot)

What the region tags partition, and what they leave to a named remainder.
Numerics can take the parent's water below zero, and no set of non-negative
tags can partition a negative amount. So the partition's target is the parent's
non-negative part, `max(ρq_tot, 0)`. Its negative part, `min(ρq_tot, 0)`, is the
remainder that the diagnostic `q_tag_negative` reports. The two add up to
`ρq_tot`. Where the parent is not negative the target is `ρq_tot` itself, bit
for bit. `-0.0` stays `-0.0`.

Increment transport takes the target's increment
([`correct_water_tag_increment!`](@ref)). The limiters' rescale and the copies'
repair aim at it ([`water_tag_rescale_shift`](@ref)). The closure check and
`q_tag_res` compare the partition with it ([`water_closure_total`](@ref)).
"""
@inline water_tag_partition_target(ρq_tot) =
    ifelse(ρq_tot < zero(ρq_tot), zero(ρq_tot), ρq_tot)
@inline water_tag_negative_part(ρq_tot) =
    ifelse(ρq_tot < zero(ρq_tot), ρq_tot, zero(ρq_tot))

"""
    water_tag_target_gain(Δ, ρq_tot)

The rate at which a process with tendency `Δ` of the parent raises the
partition's target, `max(ρq_tot, 0)`, at the state `ρq_tot`: `max(Δ, 0)` where
`ρq_tot` is not negative, and zero where it is. Where the parent is below
zero, a gain fills its negative part and the target stays at zero. At zero a
gain lifts the parent into the positive range, so the target takes all of it.
`-0.0` is not below zero, so a parent that is never negative gives `max(Δ, 0)`
bit for bit.

`ρq_tot` here is the partition's parent. Under `water_tag_precipitation: true`
that is the non-precipitating water, `ρq_tot - ρq_rai - ρq_sno`
(`water_tag_parent`), whose sign decides, not that of `ρq_tot`.

Every applied-update event gives every tag that receives its label this gain, by
mask. The loss half already follows the target, because a tag's share is zero
where the parent is not positive. So on a closed partition the event's tendency
is the target's. A source tag is a part of the target too.

The rule is read at the state of each stage. The tableau's explicit weights
include negative ones, so in a step whose parent crosses zero the partition's
gain over the step can be negative, and a tag that holds nothing can end the
step below zero.
"""
@inline water_tag_target_gain(Δ, ρq_tot) =
    ifelse(ρq_tot < zero(ρq_tot), zero(Δ), max(Δ, 0))

"""
    TargetGain()
    ParentGain()

How an applied-update event gives a process's gain to the tags.

  - `TargetGain()`, every applied-update event, explicit and implicit: the gain of the
    partition's target, `water_tag_target_gain`, for every tag that receives
    the label, a tag that lists sources too. The split 0M rain-out in copies
    mode applies it to the updraft's part (`water_tag_split_change`). What it
    withholds goes to the ledger `q_tag_exp_negative`.
  - `ParentGain()`: `max(Δ, 0)` wherever the parent is. No event of the model
    uses it. The tests compare with it.
"""
abstract type WaterTagGainRule end
struct TargetGain <: WaterTagGainRule end
struct ParentGain <: WaterTagGainRule end
Base.broadcastable(rule::WaterTagGainRule) = tuple(rule)

# A tag's gain under `rule`.
@inline water_tag_gain(::TargetGain, Δ, ρq_tot) =
    water_tag_target_gain(Δ, ρq_tot)
@inline water_tag_gain(::ParentGain, Δ, ρq_tot) = max(Δ, 0)
# Every tag that receives a label takes the event's rule. A source tag is a
# part of the target, which is zero where the parent is below zero.
_tag_gain_rule(rule, tag) = rule

"""
    water_tag_withheld_gain(rule, Δ, ρq_tot)

The part of a process's tendency `Δ` that fills the parent's negative part
instead of reaching the tags: `max(Δ, 0)` where the parent `ρq_tot` is below
zero under `TargetGain()`, and zero elsewhere and under `ParentGain()`. It does
not read the tags. The ledger `q_tag_exp_negative` takes it at every
applied-update event.
"""
@inline water_tag_withheld_gain(::TargetGain, Δ, ρq_tot) =
    ifelse(ρq_tot < zero(ρq_tot), max(Δ, zero(Δ)), zero(Δ))
@inline water_tag_withheld_gain(::ParentGain, Δ, ρq_tot) = zero(Δ)

"""
    WATER_TAG_EXP_LEDGER_NAMES

The ledgers of the gain the rule withholds, state fields in kg m⁻³:

  - `q_tag_exp_negative`: with water tags, the gain every applied-update event
    withholds where the partition's parent is below zero
    (`water_tag_withheld_gain`). Under `water_tag_precipitation: true`
    also the net inflow the microphysics and the vapour event give the
    non-precipitating water while it is below zero.
  - `q_tag_exp_negative_precip`: under the key only, the same for rain and
    snow while negative.

They read the parent, not the tags. The stepper weights them as it weights the
tags. Their names carry no `ρ` prefix, so no transport or limiter reaches them.
The tag names `exp_*` are reserved.
"""
const WATER_TAG_EXP_LEDGER_NAMES = (:q_tag_exp_negative, :q_tag_exp_negative_precip)

# The ledgers a model has, in state order, and their zeros.
water_tag_exp_ledger_names(::Nothing) = ()
water_tag_exp_ledger_names(model::WaterTaggingModel) =
    has_water_tag_precipitation(model) ? WATER_TAG_EXP_LEDGER_NAMES :
    (:q_tag_exp_negative,)
water_tag_exp_ledger_variables(value, model) =
    _mechanism_zeros(value, Val(water_tag_exp_ledger_names(model)))
is_water_tag_exp_ledger_name(name::Symbol) = name in WATER_TAG_EXP_LEDGER_NAMES

# A tag's part of the updraft's 0M rain-out in copies mode, `x = Δʲ·φʲ`. It
# is signed: `Δʲ = ρaʲ·dq_tot_dtʲ` is a gain where the updraft's area is
# negative. Under `TargetGain` the gain is withheld where the grid parent is
# below zero, as the applied-update events withhold theirs, and a loss is kept.
# A region tag's part of the environment's rain-out is zero there already, since its
# share is scaled by the grid shares' sum `S`, which is zero where the parent
# is not positive. A source tag's environment part is not changed. Where the
# parent is not negative this is `x`, bit for bit.
@inline water_tag_split_change(::ParentGain, x, ρq_tot) = x
@inline water_tag_split_change(::TargetGain, x, ρq_tot) =
    ifelse(ρq_tot < zero(ρq_tot), min(x, zero(x)), x)

"""
    microphysics_gain_rule(atmos)

The gain rule of the `:microphysics` applied-update event: `TargetGain()`, on the
implicit path and on the explicit one. On the implicit path the sign is read at
each Newton iterate. The diagnostics' rain-out follows the event by this
function, so the two agree.
"""
microphysics_gain_rule(atmos) =
    _microphysics_gain_rule(atmos.microphysics_tendency_timestepping)
_microphysics_gain_rule(::Implicit) = TargetGain()
_microphysics_gain_rule(timestepping) = TargetGain()

"""
    water_closure_total(model)

What the water closure check compares the partition with, in the form
`closure_parent` takes: without water tags `:ρq_tot`, and with them a function
that fills `p.tagging.ᶜwater_parent` with the partition's target,
`water_tag_partition_target(ρq_tot)`, and returns it. The closure's `total`,
`scale` and residuals are then over the parent's non-negative water. Its
negative part is the named remainder `q_tag_negative`. Under
`water_tag_precipitation: true` the target is the sum of the three
compartments' non-negative parts ([`water_partition_target`](@ref)).
"""
water_closure_total(::Nothing) = :ρq_tot
water_closure_total(::WaterTaggingModel) = water_closure_parent
function water_closure_parent(Y, p)
    ᶜparent = p.tagging.ᶜwater_parent
    @. ᶜparent = $(water_partition_target(Y.c, p.atmos.water_tagging_model))
    return ᶜparent
end

# The closure's `nonpositive_fraction` and the audit's `nonpositive_mass` read
# the raw parent, since the partition's target is never negative. Under
# `water_tag_precipitation: true` that is still the raw `ρq_tot`, not the
# compartments' negative parts, as `parent_negative_water` says.
closure_signed_parent(Y, p, ::typeof(water_closure_parent)) = Y.c.ρq_tot

"""
    DEFAULT_NEGATIVE_WATER_VOID_ABOVE

Default `negative_water_void_above` of the water closure check: `1e-4`. Past
it, the parent's negative water, `∫max(-ρq_tot, 0) dV`, is more than this
fraction of the parent's water, `∫ρq_tot dV`. The check compares the two at
each of its rows and at the end of every accepted step. Once the ratio passes
the level, every later row is marked `negative_water_void`.
"""
const DEFAULT_NEGATIVE_WATER_VOID_ABOVE = 1.0e-4

"""
    parent_negative_water(Y)

The parent's negative water, from the raw `ρq_tot`:

  - `negative = ∫max(-ρq_tot, 0) dV`, which is `Σ ρ max(-q_tot, 0) dV`, in kg;
  - `total = ∫ρq_tot dV`, in kg;
  - `relative = negative / total` ([`negative_water_relative`](@ref)).

Not the partition's target `max(ρq_tot, 0)`, whose negative part is zero by
construction. Without `water_tag_precipitation`, `negative` is the integral of
`ρ q_tag_negative` up to sign. With it, it is not. There `q_tag_negative` is
the sum of the three compartments' negative parts, and a cell with negative
rain or snow but positive `ρq_tot` adds to `q_tag_negative` and not here. The
check reads the raw `ρq_tot` by the owner's decision of 2026-09-25, so it does
not gate those remainders. `q_ntag_res`, `q_rtag_res`, `q_stag_res` and
`q_tag_negative` report them. It writes no field, not even scratch. So the check at every accepted step
([`check_negative_water_step!`](@ref)), which takes the same sums, writes none
either. `Base.sum` reduces across processes, so this is collective: every
process must call it.
"""
function parent_negative_water(Y)
    ᶜρq_tot = Y.c.ρq_tot
    negative = sum(negative_water_integrand, ᶜρq_tot)
    total = sum(ᶜρq_tot)
    return (; negative, total, relative = negative_water_relative(negative, total))
end

# The parent's negative water per volume, `max(-ρq_tot, 0)`, in the parent's
# float type. It uses the partition's split, so `-0.0` is not negative water.
@inline negative_water_integrand(ρq_tot) = -water_tag_negative_part(ρq_tot)

"""
    negative_water_step_relative(ᶜρq_tot)

The ratio that [`parent_negative_water`](@ref) gives,
`∫max(-ρq_tot, 0) dV / ∫ρq_tot dV`, for the check at every accepted step. It
takes the same two sums, so the same state gives the same ratio, bit for bit.
Where no cell is negative it stops after the first sum, and the ratio is 0.

Both sums are collective. The first adds terms that are not negative, so it is
zero on every process or on none. So every process takes the same branch.
"""
function negative_water_step_relative(ᶜρq_tot)
    negative = sum(negative_water_integrand, ᶜρq_tot)
    iszero(negative) && return zero(negative)
    return negative_water_relative(negative, sum(ᶜρq_tot))
end

"""
    negative_water_relative(negative, total)

`negative / total`, guarded: `0` where `negative` is zero, whatever `total` is,
and `Inf` where `negative` is positive and `total` is not. A parent whose
water is zero or less in all has no scale to measure its negative part
against, and a run in that state is past any level.
"""
negative_water_relative(negative, total) =
    iszero(negative) ? zero(negative) :
    total > zero(total) ? negative / total : oftype(negative, Inf)

"""
    snapshot_tagged_ρq_tot!(p, Yₜ)

Record the current value of `Yₜ.c.ρq_tot` in `p.scratch`, opening the water
half of an applied-update event. A no-op when water tagging is disabled.

Together with [`attribute_tagged_ρq_tot!`](@ref) this surrounds a block of
tendency calls. Whatever the block adds to `Yₜ.c.ρq_tot` is attributed to the
tagged water tracers without modifying the process itself. Events must not be
nested.
"""
snapshot_tagged_ρq_tot!(p, Yₜ) =
    _snapshot_tagged_ρq_tot!(p, Yₜ, p.atmos.water_tagging_model)
_snapshot_tagged_ρq_tot!(p, Yₜ, ::Nothing) = nothing
function _snapshot_tagged_ρq_tot!(p, Yₜ, ::WaterTaggingModel)
    p.scratch.ᶜtagging_q_snapshot .= Yₜ.c.ρq_tot
    return nothing
end

"""
    attribute_tagged_ρq_tot!(Yₜ, Y, p, source::Symbol, rule = TargetGain())

Close the applied-update event opened by [`snapshot_tagged_ρq_tot!`](@ref). Add
`M_k·G - φ_k·Δ⁻` to each tag's tendency for the tendency of the process
`source`, `Δ = Yₜ.c.ρq_tot - snapshot`. `M_k` is the tag's mask, and `φ_k` its
share of the partition's parent `N`, `ρq_tot` or under `water_tag_precipitation`
the non-precipitating water. `G = Δ⁺`, and under `rule = TargetGain()`, every
event's rule, zero where `N < 0`. That withheld gain goes to the ledger
`q_tag_exp_negative`.

Production reaches a tag only if it lists `source`, or has a region and no
source. Loss reaches every tag. A no-op without water tags or water process.
"""
attribute_tagged_ρq_tot!(Yₜ, Y, p, source::Symbol, rule = TargetGain()) =
    _attribute_tagged_ρq_tot!(Yₜ, Y, p, source, p.atmos.water_tagging_model, rule)
_attribute_tagged_ρq_tot!(Yₜ, Y, p, source, ::Nothing, rule) = nothing
function _attribute_tagged_ρq_tot!(
    Yₜ,
    Y,
    p,
    source,
    model::WaterTaggingModel,
    rule,
)
    source in KNOWN_WATER_TAG_SOURCES || return nothing
    ᶜρq_tot_snapshot = p.scratch.ᶜtagging_q_snapshot
    ᶜΔρq_tot = @. lazy(Yₜ.c.ρq_tot - ᶜρq_tot_snapshot)
    ᶜparent = water_tag_parent(Y.c, model)
    # The ledger takes the withheld gain once per event, whatever the tags
    # hold. It comes before the split's return, so that the grid kernel and
    # both split modes write it.
    ᶜwithheldₜ = Yₜ.c.q_tag_exp_negative
    @. ᶜwithheldₜ += water_tag_withheld_gain(rule, ᶜΔρq_tot, ᶜparent)
    # Under 0M and prognostic EDMF the rain-out goes to the tags by each
    # subdomain's composition (`tagged_water_rainout.jl`).
    splits_rainout(p, source) &&
        return add_split_rainout!(Yₜ.c, Y, p, model, nothing, rule)
    (; ᶜwater_masks) = p.tagging
    _accumulate_water_tags!(
        Yₜ.c,
        Y.c,
        ᶜwater_masks,
        ᶜΔρq_tot,
        source,
        model.tags,
        ᶜparent,
        rule,
    )
    return nothing
end

# The split `Δ = Δ⁺ - Δ⁻` appears below as `max(Δ, 0)` and `min(Δ, 0)`. The loss
# term is written `+ min(Δ, 0) * φ` instead of the equivalent `- max(-Δ, 0) * φ`
# for two reasons. It keeps the whole update in one broadcast over `ᶜΔ`. And a
# `-` directly before a modifier letter such as `ᶜ` parses as the suffixed
# operator `-ᶜ`, which Julia leaves undefined.
#
# `ᶜparent` is the water the tags partition. The loss's share divides by it.
# It is `ρq_tot`, or under `water_tag_precipitation: true` the water that is
# neither rain nor snow (`water_tag_parent`). An attributed process moves only
# `ρq_tot`, so under the key its change is the non-precipitating water's. The
# tags' gain reads the sign of the same water, so under the key the target is
# that compartment's.
#
# `rule` is the gain rule, `TargetGain()` for every event and by default.
_accumulate_water_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, tags::Tuple) =
    _accumulate_water_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, tags, ᶜY.ρq_tot)
_accumulate_water_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, tags::Tuple, ᶜparent) =
    _accumulate_water_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        tags,
        ᶜparent,
        TargetGain(),
    )
_accumulate_water_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, ::Tuple{}, ᶜparent, rule) =
    nothing
function _accumulate_water_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tags::Tuple,
    ᶜparent,
    rule,
)
    tag = first(tags)
    _accumulate_water_tag!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        tag,
        ᶜparent,
        _tag_gain_rule(rule, tag),
    )
    return _accumulate_water_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        Base.tail(tags),
        ᶜparent,
        rule,
    )
end

# Region-less tag: production weight is 1 wherever the tag receives this source.
# Such a tag is a source tag, a part of the target, so its gain follows `rule`
# as a region tag's does. Under `TargetGain()` there is none where the parent is
# below zero.
function _accumulate_water_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::WaterTag{name, Nothing},
    ᶜparent,
    rule,
) where {name}
    ᶜρq_tagₜ = tag_field(ᶜYₜ, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    if tag_receives_source(tag, source)
        @. ᶜρq_tagₜ +=
            water_tag_gain(rule, ᶜΔ, ᶜparent) +
            min(ᶜΔ, 0) * water_tag_fraction(ᶜρq_tag, ᶜparent)
    else
        @. ᶜρq_tagₜ += min(ᶜΔ, 0) * water_tag_fraction(ᶜρq_tag, ᶜparent)
    end
    return nothing
end

# Tag with a region: production is masked. Loss is in proportion to what the tag
# holds, so water leaves from wherever the tag is holding it. The gain follows `rule`
# (`_tag_gain_rule`): under `TargetGain()` it is the target's, zero where the
# parent is below zero, for a region tag that lists sources too.
function _accumulate_water_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::WaterTag,
    ᶜparent,
    rule,
)
    ᶜρq_tagₜ = tag_field(ᶜYₜ, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    ᶜmask = tag_field(ᶜmasks, tag)
    if tag_receives_source(tag, source)
        @. ᶜρq_tagₜ +=
            ᶜmask * water_tag_gain(rule, ᶜΔ, ᶜparent) +
            min(ᶜΔ, 0) * water_tag_fraction(ᶜρq_tag, ᶜparent)
    else
        @. ᶜρq_tagₜ += min(ᶜΔ, 0) * water_tag_fraction(ᶜρq_tag, ᶜparent)
    end
    return nothing
end

# ============================================================================
# Sedimentation (1-moment and higher)
# ============================================================================

##### Each tag's flux is built like the parent's and scaled by its share. For a
##### sedimenting species `s` with terminal velocity `wₛ` and specific content `qₛ`,
##### `vertical_advection_of_water_tendency!` adds
#####
#####     vtt = -ᶜprecipdivᵥ(ᶠρ * ᶠtop_bias(WVector(-wₛ) * qₛ))
#####
##### to `Yₜ.c.ρ` and `Yₜ.c.ρq_tot`. A tag gets the same expression with its
##### share `φ̂ₖ` placed inside the reconstruction:
#####
#####     vttₖ = -ᶜprecipdivᵥ(ᶠρ * ᶠtop_bias(WVector(-wₛ) * qₛ * φ̂ₖ))
#####
##### That placement has three effects. Tag closure is exact, because both
##### operators are linear, so shares summing to 1 pointwise give
##### `Σₖ vttₖ = vtt` to roundoff. The origin is right, because `ᶠtop_bias`
##### samples the cell the water falls from. Surface removal comes for free,
##### because `ᶜprecipdivᵥ` leaves the bottom face as free outflow.
#####
##### Only the grid-mean flux gets tag fluxes. The `PrognosticEDMFX` subdomain
##### corrections apply to the energy flux, and the tags are grid-scale only.
##### `docs/src/tagged_water.md` works through the shares and the Jacobian.

# A region tag has a region and no sources. The region tags form the partition
# whose shares are renormalized to sum to 1. Both properties are type
# parameters, so this resolves at compile time. It matches the runtime filter in
# `water_region_tag_state_names`.
_is_partition_tag(
    ::WaterTag{name, R, Tuple{}},
) where {name, R <: AbstractTagRegion} = true
_is_partition_tag(::WaterTag) = false

"""
    water_tag_sediment_share(ρq_tag, ρq_tot, norm)

Fraction of a sedimenting species' mass carried by a *region* tag: its clamped
share `φ = ρq_tag / ρq_tot` divided by `norm`, the sum of the clamped shares of
every region tag.

The renormalization is what preserves exact tag closure. Unlimited transport
lets a tag drift slightly out of the partition, and `water_tag_fraction` then
clamps. After that the raw shares do not sum to 1, and `Σₖ vttₖ = vtt` fails
by the size of the drift. Dividing by `norm` restores it.

The result is always in `[0, 1]`. Each clamped share is one of the non-negative
terms of `norm`, so no amplification is possible however small `norm` becomes.
Where `norm` is zero there is no tagged water to sediment and the share is zero.
Tag closure cannot hold in a cell whose tags are all empty but whose `ρq_tot` is
not, and that discrepancy surfaces in `q_tag_res`.
"""
@inline water_tag_sediment_share(ρq_tag, ρq_tot, norm) =
    norm > zero(norm) ? water_tag_fraction(ρq_tag, ρq_tot) / norm : zero(norm)

"""
    water_tag_source_sediment_share(ρq_tag, ρq_tot)

Fraction of a sedimenting species' mass carried by a *source* tag: its own
clamped share, unnormalized.

Source tags are not part of the partition. They start at zero and accumulate one
process, so no closure constraint applies to them and there is nothing to
renormalize against. Their water falls out like any other, in proportion to what
the tag holds. The loss half of [`attribute_tagged_ρq_tot!`](@ref) uses the same
rule.
"""
@inline water_tag_source_sediment_share(ρq_tag, ρq_tot) =
    water_tag_fraction(ρq_tag, ρq_tot)

"""
    water_tag_sediment_dshare(ρq_tag, ρq_tot, norm)
    water_tag_source_sediment_dshare(ρq_tag, ρq_tot)

Derivative of the corresponding share with respect to `ρq_tag`, for the implicit
sedimentation Jacobian (see `update_sedimentation_jacobian!`).

For a region tag `norm` depends on `ρq_tag` too, which contributes the `(1 - φ̂)`
factor. A tag that already owns all of the local water cannot increase its
share, so the derivative vanishes there rather than staying at
`1/(ρq_tot ⋅ norm)`. Both derivatives are zero wherever the `[0, 1]` clamp is
active, matching the tendency's own piecewise behavior.
"""
@inline function water_tag_sediment_dshare(ρq_tag, ρq_tot, norm)
    (ρq_tot > zero(ρq_tot) && norm > zero(norm)) || return zero(ρq_tot)
    φ = ρq_tag / ρq_tot
    (φ > zero(φ) && φ < one(φ)) || return zero(ρq_tot)
    return (one(φ) - φ / norm) / (ρq_tot * norm)
end

@inline function water_tag_source_sediment_dshare(ρq_tag, ρq_tot)
    ρq_tot > zero(ρq_tot) || return zero(ρq_tot)
    φ = ρq_tag / ρq_tot
    (φ > zero(φ) && φ < one(φ)) || return zero(ρq_tot)
    return inv(ρq_tot)
end

"""
    water_tag_sediment_dshare_field(Y, p, tag)

Lazy field of `∂φ̂/∂ρq_tag` for `tag`, selecting the region or source form.
`_is_partition_tag` resolves on the tag's type, so the branch folds away and the
return type is inferred.

Requires [`water_tag_share_norm!`](@ref) to have been evaluated for the current
state.
"""
function water_tag_sediment_dshare_field(Y, p, tag)
    ᶜρq_tag = tag_field(Y.c, tag)
    ᶜρq_tot = water_tag_parent(Y.c, p.atmos.water_tagging_model)
    if _is_partition_tag(tag)
        ᶜnorm = p.scratch.ᶜtagging_q_share_norm
        return @. lazy(water_tag_sediment_dshare(ᶜρq_tag, ᶜρq_tot, ᶜnorm))
    else
        return @. lazy(water_tag_source_sediment_dshare(ᶜρq_tag, ᶜρq_tot))
    end
end

"""
    water_tag_sediment_share_field(Y, p, tag)

Lazy field of `tag`'s share `φ̂` of each sedimenting species, as
[`sediment_water_tags!`](@ref) takes it: [`water_tag_sediment_share`](@ref) for
a region tag, [`water_tag_source_sediment_share`](@ref) for a source tag. It
scales the parent's sedimentation cross block into the tag's.

Requires [`water_tag_share_norm!`](@ref) to have been evaluated for the current
state.
"""
function water_tag_sediment_share_field(Y, p, tag)
    ᶜρq_tag = tag_field(Y.c, tag)
    ᶜρq_tot = water_tag_parent(Y.c, p.atmos.water_tagging_model)
    if _is_partition_tag(tag)
        ᶜnorm = p.scratch.ᶜtagging_q_share_norm
        return @. lazy(water_tag_sediment_share(ᶜρq_tag, ᶜρq_tot, ᶜnorm))
    else
        return @. lazy(water_tag_source_sediment_share(ᶜρq_tag, ᶜρq_tot))
    end
end

"""
    water_tag_share_norm!(p, Y)

Fill `p.scratch.ᶜtagging_q_share_norm` with `Σⱼ clamp(ρq_tag_j / ρq_tot)` over
the *region* tags, the denominator [`water_tag_sediment_share`](@ref) divides
by. A no-op when water tagging is disabled.

Under `water_tag_precipitation: true` the share is of the water that is neither
rain nor snow ([`water_tag_parent`](@ref)), and the rain and snow parts' own
denominators are filled beside it, in `ᶜtagging_q_share_norm_rai` and
`ᶜtagging_q_share_norm_sno`.

Lives in `p.scratch` rather than `p.tagging` for the same reason as the `ρq_tot`
snapshot: the implicit tendency is evaluated with `ForwardDiff.Dual` numbers when
an automatic-differentiation Jacobian is used, and only `p.precomputed` and
`p.scratch` are converted to dual-typed fields.

Must be recomputed whenever the state changes, once per tendency evaluation and
once per Jacobian update, because it is a property of the current `Y`.
"""
water_tag_share_norm!(p, Y) =
    _water_tag_share_norm!(p, Y, p.atmos.water_tagging_model)
_water_tag_share_norm!(p, Y, ::Nothing) = nothing
function _water_tag_share_norm!(p, Y, model::WaterTaggingModel)
    ᶜnorm = p.scratch.ᶜtagging_q_share_norm
    ᶜnorm .= zero(eltype(ᶜnorm))
    _accumulate_share_norm!(
        ᶜnorm,
        Y.c,
        model.tags,
        water_tag_parent(Y.c, model),
    )
    _water_tag_precipitation_share_norms!(p, Y, model)
    return nothing
end

_accumulate_share_norm!(ᶜnorm, ᶜY, tags::Tuple) =
    _accumulate_share_norm!(ᶜnorm, ᶜY, tags, ᶜY.ρq_tot)
_accumulate_share_norm!(ᶜnorm, ᶜY, ::Tuple{}, ᶜparent) = nothing
function _accumulate_share_norm!(ᶜnorm, ᶜY, tags::Tuple, ᶜparent)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_tag = tag_field(ᶜY, tag)
        @. ᶜnorm += water_tag_fraction(ᶜρq_tag, ᶜparent)
    end
    return _accumulate_share_norm!(ᶜnorm, ᶜY, Base.tail(tags), ᶜparent)
end

"""
    sediment_water_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶠρ, ρq_name)

Add one sedimenting species' flux divergence to every tagged water tracer. Each
tag's flux is built like the parent's and scaled by its share. `ᶜq` is that
species' specific content, `ᶜw` its terminal velocity and `ᶠρ` the
face-interpolated density. These are the same three quantities the parent
`ρq_tot` flux is built from in `vertical_advection_of_water_tendency!`, so the
tagged fluxes sum to it exactly. `ρq_name` is the species' `@name`.

Under `water_tag_precipitation: true` rain falls in each tag's rain part and
snow in its snow part, linearly, and only the cloud falls in `ρq_tag_<name>`,
by its share of the water that is neither rain nor snow. See
`_sediment_water_tag_parts!`.

Call once per species, from inside that function's species loop, with
[`water_tag_share_norm!`](@ref) already evaluated for the current state. A no-op
when water tagging is disabled.
"""
sediment_water_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶠρ, ρq_name) =
    _sediment_water_tags_of_model!(
        Yₜ,
        Y,
        p,
        ᶜq,
        ᶜw,
        ᶠρ,
        ρq_name,
        p.atmos.water_tagging_model,
    )
_sediment_water_tags_of_model!(Yₜ, Y, p, ᶜq, ᶜw, ᶠρ, ρq_name, ::Nothing) =
    nothing
function _sediment_water_tags_of_model!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶠρ,
    ρq_name,
    model::WaterTaggingModel,
)
    has_water_tag_precipitation(model) && return _sediment_water_tag_parts!(
        Yₜ,
        Y,
        p,
        ᶜq,
        ᶜw,
        ᶠρ,
        ρq_name,
        model,
    )
    _sediment_water_tags!(
        Yₜ.c,
        Y.c,
        p.scratch.ᶜtagging_q_share_norm,
        ᶜq,
        ᶜw,
        ᶠρ,
        model.tags,
    )
    return nothing
end

_sediment_water_tags!(ᶜYₜ, ᶜY, ᶜnorm, ᶜq, ᶜw, ᶠρ, tags::Tuple) =
    _sediment_water_tags!(ᶜYₜ, ᶜY, ᶜnorm, ᶜq, ᶜw, ᶠρ, tags, ᶜY.ρq_tot)
_sediment_water_tags!(ᶜYₜ, ᶜY, ᶜnorm, ᶜq, ᶜw, ᶠρ, ::Tuple{}, ᶜparent) = nothing
function _sediment_water_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜnorm,
    ᶜq,
    ᶜw,
    ᶠρ,
    tags::Tuple,
    ᶜparent,
)
    tag = first(tags)
    ᶜρq_tagₜ = tag_field(ᶜYₜ, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    # `-(ᶜw)` is parenthesized, as in `vertical_advection_of_water_tendency!`.
    # A `-` directly before a modifier letter parses as the suffixed operator
    # `-ᶜ`, which Julia leaves undefined.
    if _is_partition_tag(tag)
        @. ᶜρq_tagₜ +=
            -1 * ᶜprecipdivᵥ(
                ᶠρ * ᶠtop_bias(
                    Geometry.WVector(-(ᶜw)) *
                    ᶜq *
                    water_tag_sediment_share(ᶜρq_tag, ᶜparent, ᶜnorm),
                ),
            )
    else
        @. ᶜρq_tagₜ +=
            -1 * ᶜprecipdivᵥ(
                ᶠρ * ᶠtop_bias(
                    Geometry.WVector(-(ᶜw)) *
                    ᶜq *
                    water_tag_source_sediment_share(ᶜρq_tag, ᶜparent),
                ),
            )
    end
    return _sediment_water_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜnorm,
        ᶜq,
        ᶜw,
        ᶠρ,
        Base.tail(tags),
        ᶜparent,
    )
end

"""
    sedimenting_water_tag_names(Y)

`Tuple` of `@name`s (relative to `Y.c`) of the tagged water tracers that get a
sedimentation flux of their own, and so need their own implicit sedimentation
Jacobian block.

Empty when water tagging is disabled, and empty under 0-moment microphysics,
where there is no sedimenting species and the tags behave like any other passive
tracer. Used by both the Jacobian block allocation and the
Jacobian update so the two cannot disagree about which blocks exist.
"""
sedimenting_water_tag_names(Y) =
    isempty(sedimenting_mass_names(Y)) ? () :
    unrolled_filter(is_water_tag_name, gs_tracer_names(Y))

# ============================================================================
# Applied-update events for all families
# ============================================================================

"""
    snapshot_tags!(p, Yₜ, source::Symbol)
    attribute_tags!(Yₜ, Y, p, source::Symbol)

Open and close the tag half of one applied-update event for every tagging family
at once, and for the process records. The energy half is unconditional, because
every attributed process is an energy process. The water half fires only for
`source in KNOWN_WATER_TAG_SOURCES`, so radiation costs a water-tagged run
nothing.

This is the tag half of the applied-update event. The tendency code calls
[`open_applied_update!`](@ref) and `close_applied_update!`, which reach
here only for a `source` in `KNOWN_TAG_SOURCES` and feed the parent budget
for every label.

Each half is a no-op when its own model is `nothing`, so a run with only one
family enabled pays only for that family.

The same event also feeds the process records, which difference the same two
fields to record what the process applied. See
[`snapshot_process_record!`](@ref).
"""
function snapshot_tags!(p, Yₜ, source::Symbol)
    snapshot_tagged_ρe_tot!(p, Yₜ)
    if source in KNOWN_WATER_TAG_SOURCES
        snapshot_tagged_ρq_tot!(p, Yₜ)
    end
    snapshot_energy_source_tags!(p, Yₜ)
    snapshot_process_record!(p, Yₜ, source)
    return nothing
end

function attribute_tags!(Yₜ, Y, p, source::Symbol)
    attribute_tagged_ρe_tot!(Yₜ, p, source)
    attribute_tagged_ρq_tot!(Yₜ, Y, p, source)
    attribute_energy_source_tags!(Yₜ, Y, p, source)
    accumulate_process_record!(Yₜ, p, source)
    return nothing
end

# ============================================================================
# Numerical corrections
# ============================================================================

# Both numerical corrections need the partition sum split into its positive and
# negative parts, over the region tags only. Source tags are outside the
# partition, so they are excluded here exactly as they are from the
# sedimentation denominator in `_accumulate_share_norm!`.
_accumulate_partition_pos!(ᶜpos, ᶜY, ::Tuple{}) = nothing
function _accumulate_partition_pos!(ᶜpos, ᶜY, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_tag = tag_field(ᶜY, tag)
        @. ᶜpos += max(ᶜρq_tag, 0)
    end
    return _accumulate_partition_pos!(ᶜpos, ᶜY, Base.tail(tags))
end

_accumulate_partition_neg!(ᶜneg, ᶜY, ::Tuple{}) = nothing
function _accumulate_partition_neg!(ᶜneg, ᶜY, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_tag = tag_field(ᶜY, tag)
        @. ᶜneg += min(ᶜρq_tag, 0)
    end
    return _accumulate_partition_neg!(ᶜneg, ᶜY, Base.tail(tags))
end

"""
    water_tag_rescale_shift(ρq_tag, ρq_tot_after, ρq_tot_before, pos)

Return the signed water that [`rescale_water_tags!`](@ref) moves into a region
tag when a limiter or state constraint changes `ρq_tot` from `ρq_tot_before` to
`ρq_tot_after`. `pos` is `Σⱼ max(ρq_tag_j, 0)` over the region tags of the same
cell.

The parent's change `Δ` is handed out in proportion to what each tag holds,

    shift_k = Δ · max(ρq_tag_k, 0) / pos,

so the shares sum to one and the tags take `Δ` in full. This is the rule that
[`attribute_tagged_ρq_tot!`](@ref) applies to a process's loss, written as an
increment. It adds `Δ` to the tags and leaves the closure error
`e = ρq_tot - Σₖ ρq_tag_k` where it was. Scaling the tags would multiply `e` by
the same factor, and a cell that a limiter lifts every stage would grow its error
geometrically.

  - `Δ` is the change of the partition's target
    ([`water_tag_partition_target`](@ref)), floored at `-pos`. Where the parent
    stays non-negative it is `ρq_tot_after - ρq_tot_before`. The floor keeps a
    non-negative tag non-negative, because the tags cannot pay out more water
    than they hold. Where it binds, the water the parent still holds shows in
    `q_tag_res`.
  - A tag that is already negative gets no share, because `max(ρq_tag_k, 0)` is
    zero. [`repair_water_tag_partition!`](@ref) is the correction for it.
  - Where `pos` is zero nothing moves, and the change shows in `q_tag_res`.
    Water is never put into a tag that holds none.
  - Where `ρq_tot_before ≤ 0` the tag is emptied and the shift is `-ρq_tag`. The
    rescale is applied to the whole field, so this branch is reached in every
    cell whose parent was non-positive, whether or not anything moved there. It
    is written for a nonnegativity constraint that clips a negative parent up to
    zero. Emptying the tags with it keeps them in step with the parent and
    records the removal in `q_tag_fix_<name>`.
"""
@inline function water_tag_rescale_shift(
    ρq_tag,
    ρq_tot_after,
    ρq_tot_before,
    pos,
)
    ρq_tot_before > zero(ρq_tot_before) || return -ρq_tag
    pos > zero(pos) || return zero(ρq_tag)
    Δ = max(water_tag_partition_target(ρq_tot_after) - ρq_tot_before, -pos)
    return Δ * max(ρq_tag, zero(ρq_tag)) / pos
end

"""
    water_tag_source_rescale_shift(ρq_tag, ρq_tot_after, ρq_tot_before)

The same signed water, for a *source* tag: its own clamped share of the parent's
change, unnormalized.

Source tags are not part of the partition. They start at zero and accumulate one
process, so no closure constraint applies to them and there is nothing to
renormalize against. This matches `water_tag_source_sediment_share`, which draws
the same distinction for the sedimentation flux.

The parent's loss is floored at `-ρq_tot_before` for the reason the partition
version floors it at `-pos`: a share of at most one, of a loss of at most the
parent, cannot take a non-negative tag below zero. The `ρq_tot_before ≤ 0` branch
removes the tag, as it does for a region tag.
"""
@inline function water_tag_source_rescale_shift(
    ρq_tag,
    ρq_tot_after,
    ρq_tot_before,
)
    ρq_tot_before > zero(ρq_tot_before) || return -ρq_tag
    Δ = max(ρq_tot_after, zero(ρq_tot_after)) - ρq_tot_before
    return Δ * water_tag_fraction(ρq_tag, ρq_tot_before)
end

"""
    rescale_water_tags!(Y, p, ᶜρq_tot_before)

Give the tags the parent's change `Δ = ρq_tot_after - ρq_tot_before` after the
limiters or state constraints have corrected `ρq_tot`. A no-op when water
tagging is disabled.

Each tag takes `Δ` in proportion to what it holds, `ρq_tag_k += Δ · share_k`,
and is not scaled. The shares of the region tags sum to one, so the partition
takes `Δ` in full and no non-negative tag is driven below zero. Limiting each tag
independently would give neither, because a shape-preserving adjustment applied
per tag has no reason to sum to the parent's. That is why water tags are excluded
from the tracer limiters by [`is_tagged_tracer_name`](@ref).

  - The share is the renormalized one for a region tag and the tag's own clamped
    share for a source tag, as in [`sediment_water_tags!`](@ref). See
    [`water_tag_rescale_shift`](@ref) and
    [`water_tag_source_rescale_shift`](@ref) for the `ρq_tot ≤ 0` branch and the
    floor that bounds the loss.
  - It does not assume that the tags partition `ρq_tot`, and does not restore
    that. With `e = ρq_tot - Σₖ ρq_tag_k`, the closure error that `q_tag_res`
    reports, it leaves `e` where it was whenever the partition holds some water
    and the floor does not bind. It moves `e` by at most `|Δ|` where the floor
    binds. Where the parent is non-positive every tag is removed, so `e` moves by
    the whole tag sum there. It never multiplies `e`.
  - `ᶜρq_tot_before` holds `ρq_tot` from before the correction. `Y.c.ρq_tot`
    already holds the corrected value. The signed water moved goes to the fix
    ledger `p.tagging.ᶜwater_fix`, which the `q_tag_fix_<name>` diagnostic
    reports. So "the limiters moved water" stays distinguishable from "the
    transport operators disagree", which `q_tag_res` alone would conflate.
  - Under `water_tag_precipitation: true` a correction can also change `ρq_rai`
    and `ρq_sno`. Their changes since
    [`snapshot_water_tag_precipitation!`](@ref) move between the tags' rain or
    snow parts and their non-precipitating parts
    ([`water_tag_part_follow_shift`](@ref)). Where a compartment is negative
    before or after, the non-precipitating parts then also take the rest of
    their compartment's change of target. The non-precipitating parts take the
    change of `ρq_tot` on their own compartment `ρq_tot - ρq_rai - ρq_sno`.
    The changes that raise that compartment go first, and those that lower it
    last, so it does not pass zero in between.
"""
rescale_water_tags!(Y, p, ᶜρq_tot_before) =
    _rescale_water_tags!(Y, p, ᶜρq_tot_before, p.atmos.water_tagging_model)
_rescale_water_tags!(Y, p, ᶜρq_tot_before, ::Nothing) = nothing
function _rescale_water_tags!(Y, p, ᶜρq_tot_before, model::WaterTaggingModel)
    # What this call adds to the ledgers per mechanism goes to their
    # `attempted`, whether or not the stepper keeps it. One pair of calls covers
    # both branches, since the parts' rescale under
    # `water_tag_precipitation: true` adds to the same two ledgers.
    mechanisms = Val((:q_tag_led_rescale, :q_tag_led_empty))
    before_tag_ledgers!(p, Y, mechanisms)
    if has_water_tag_precipitation(model)
        _rescale_water_tag_parts!(Y, p, ᶜρq_tot_before, model, Val(true))
    else
        (; ᶜwater_fix, ᶜwater_fix_gross, ᶜwater_fix_count, ᶜwater_pos) = p.tagging
        ᶜwater_pos .= zero(eltype(ᶜwater_pos))
        _accumulate_partition_pos!(ᶜwater_pos, Y.c, model.tags)
        _apply_water_tag_rescale!(
            Y.c,
            tag_ledger(
                ᶜwater_fix,
                ᶜwater_fix_gross,
                ᶜwater_fix_count,
                water_tag_fix_ledger_view(Y, model),
            ),
            ᶜwater_pos,
            ᶜρq_tot_before,
            model.tags,
        )
    end
    after_tag_ledgers!(p, Y, mechanisms)
    return nothing
end

# `ᶜpos` is read-only here and comes from the pre-correction state, so each tag
# can be rewritten in place and a later tag's share still holds. Same reasoning
# as `_apply_partition_repair!` below.
#
# `ᶜafter` is the corrected parent, `ρq_tot` without the key. Under
# `water_tag_precipitation: true` it is the corrected non-precipitating water,
# and `ᶜρq_tot_before` that water before the correction.
#
# `ᶜgate`, where given, is a lazy field of `Bool`s. Outside it every field this
# writes is left as it was, bit for bit, signed zeros included. `nothing`
# applies the rescale everywhere.
_apply_water_tag_rescale!(ᶜY, ledger, ᶜpos, ᶜρq_tot_before, tags::Tuple) =
    _apply_water_tag_rescale!(
        ᶜY,
        ledger,
        ᶜpos,
        ᶜρq_tot_before,
        tags,
        ᶜY.ρq_tot,
        nothing,
    )
_apply_water_tag_rescale!(ᶜY, ledger, ᶜpos, ᶜρq_tot_before, tags::Tuple, ᶜafter) =
    _apply_water_tag_rescale!(
        ᶜY,
        ledger,
        ᶜpos,
        ᶜρq_tot_before,
        tags,
        ᶜafter,
        nothing,
    )
_apply_water_tag_rescale!(
    ᶜY,
    ledger,
    ᶜpos,
    ᶜρq_tot_before,
    ::Tuple{},
    ᶜafter,
    ᶜgate,
) = nothing
function _apply_water_tag_rescale!(
    ᶜY,
    ledger,
    ᶜpos,
    ᶜρq_tot_before,
    tags::Tuple,
    ᶜafter,
    ᶜgate,
)
    tag = first(tags)
    ᶜρq_tag = tag_field(ᶜY, tag)
    (ᶜfix, ᶜgross, ᶜcount) = tag_ledger_fields(ledger, tag)
    # Accumulate the signed change before applying it, so the fix ledger
    # records the correction itself and not its effect on an already-corrected
    # tag. The shift is recomputed on the spot. A few comparisons and a divide
    # cost less than a scratch field per tag, and this stays allocation free.
    # The gross and the count take the same shift.
    if _is_partition_tag(tag)
        # The state ledgers per mechanism take the partition's shift: the
        # rescale where the parent held water, the emptying where it did not.
        @. ᶜY.q_tag_led_rescale += _gated(
            ᶜgate,
            ifelse(
                ᶜρq_tot_before > 0,
                water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
                zero(ᶜρq_tot_before),
            ),
        )
        @. ᶜY.q_tag_led_empty += _gated(
            ᶜgate,
            ifelse(
                ᶜρq_tot_before > 0,
                zero(ᶜρq_tot_before),
                water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
            ),
        )
        @. ᶜgross += _gated(
            ᶜgate,
            abs(water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos)),
        )
        @. ᶜcount += _gated(
            ᶜgate,
            tag_event(
                water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
                ᶜρq_tot_before,
            ),
        )
        # The tag's own ledger, where kept, takes the same change.
        add_to_tag_ledger!(
            ledger.state,
            tag,
            @. lazy(
                _gated(
                    ᶜgate,
                    water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
                ),
            )
        )
        @. ᶜfix += _gated(
            ᶜgate,
            water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
        )
        @. ᶜρq_tag += _gated(
            ᶜgate,
            water_tag_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before, ᶜpos),
        )
    else
        @. ᶜgross += _gated(
            ᶜgate,
            abs(water_tag_source_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before)),
        )
        @. ᶜcount += _gated(
            ᶜgate,
            tag_event(
                water_tag_source_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before),
                ᶜρq_tot_before,
            ),
        )
        add_to_tag_ledger!(
            ledger.state,
            tag,
            @. lazy(
                _gated(
                    ᶜgate,
                    water_tag_source_rescale_shift(
                        ᶜρq_tag,
                        ᶜafter,
                        ᶜρq_tot_before,
                    ),
                ),
            )
        )
        @. ᶜfix += _gated(
            ᶜgate,
            water_tag_source_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before),
        )
        @. ᶜρq_tag += _gated(
            ᶜgate,
            water_tag_source_rescale_shift(ᶜρq_tag, ᶜafter, ᶜρq_tot_before),
        )
    end
    return _apply_water_tag_rescale!(
        ᶜY,
        ledger,
        ᶜpos,
        ᶜρq_tot_before,
        Base.tail(tags),
        ᶜafter,
        ᶜgate,
    )
end

# A change outside the gate is `-0`, which leaves any value it is added to as it
# was, bit for bit, `-0.0` included. Without a gate the change is kept.
@inline _gated(::Nothing, change) = change
@inline _gated(gate::Bool, change) = ifelse(gate, change, -zero(change))

# ============================================================================
# Partition repair
# ============================================================================

"""
    water_tag_repair_factor(pos, neg)

The common factor that [`repair_water_tag_partition!`](@ref) applies to the
non-negative part of each region tag: `max(pos + neg, 0) / pos`, and zero
where there is no positive water to redistribute into.
"""
@inline water_tag_repair_factor(pos, neg) =
    pos > zero(pos) ? max(pos + neg, zero(pos)) / pos : zero(pos)

"""
    repair_water_tag_partition!(Y, p)

Restore non-negativity of the region tags without changing their sum.

Unlimited transport lets the region tags drift out of the partition. They ride
the explicit passive-tracer path with a nonlinear flux limiter applied per field,
which does not satisfy `Σ F(χᵢ) = F(Σ χᵢ)`, so individual tags can go below
zero.

A negative tag is not merely cosmetic. [`water_tag_fraction`](@ref) clamps it to
a zero share, which shrinks the renormalization denominator `norm`. That lets
[`water_tag_sediment_share`](@ref) hand a surviving tag a share far larger than
the water it actually holds. The share is bounded by 1, but the mass removed
*relative to what the tag owns* is amplified by `1/norm`. That drives the tag
negative in turn. The feedback compounds every step, and it takes the
sedimentation Jacobian with it, since `∂φ̂/∂ρq_tag` grows like
`1/Σⱼ ρq_tag_j` with only a `norm > 0` guard.

For each cell, writing `S⁺ = Σₖ max(ρq_tagₖ, 0)` and `S⁻ = Σₖ min(ρq_tagₖ, 0)`
over the region tags, this sets

    ρq_tagₖ ← max(ρq_tagₖ, 0) · max(S⁺ + S⁻, 0) / S⁺,

absorbing the negative water into the positive tags in proportion to what each
holds. The sum `S⁺ + S⁻` is preserved exactly and every tag ends non-negative.
Where the negatives outweigh the positives (`S⁺ + S⁻ < 0`) no non-negative
partition can have that sum, so every tag is zeroed and the deficit surfaces in
`q_tag_res` rather than being hidden.

This deliberately does **not** renormalize the tags onto `ρq_tot`. Forcing
`Σᵢ ρq_tag_i = ρq_tot` every step would drive `q_tag_res` to zero by
construction and destroy the leakage monitor it exists to provide. The repair
removes only the negativity, leaving genuine transport leakage visible and
bounding the clamped-share denominator by that leakage instead of by how far a
tag has gone negative.

Source tags are left alone. They are not part of the partition, carry no closure
obligation, and are already excluded from the renormalization denominator by
`_accumulate_share_norm!`.

The signed water moved is accumulated into `p.tagging.ᶜwater_fix` alongside the
limiter corrections, so it is reported by the `q_tag_fix_<name>` diagnostic.

Called from `constrain_state!` after the limiters and state constraints have
finished with `ρq_tot`. A no-op when water tagging is disabled.
"""
repair_water_tag_partition!(Y, p) =
    _repair_water_tag_partition!(Y, p, p.atmos.water_tagging_model)
_repair_water_tag_partition!(Y, p, ::Nothing) = nothing
function _repair_water_tag_partition!(Y, p, model::WaterTaggingModel)
    (; ᶜwater_fix, ᶜwater_fix_gross, ᶜwater_fix_count) = p.tagging
    (; ᶜwater_pos, ᶜwater_neg) = p.tagging
    ᶜwater_pos .= zero(eltype(ᶜwater_pos))
    ᶜwater_neg .= zero(eltype(ᶜwater_neg))
    _accumulate_partition_pos!(ᶜwater_pos, Y.c, model.tags)
    _accumulate_partition_neg!(ᶜwater_neg, Y.c, model.tags)
    mechanisms = Val((:q_tag_led_repair, :q_tag_led_repairnet))
    before_tag_ledgers!(p, Y, mechanisms)
    ledger = tag_ledger(
        ᶜwater_fix,
        ᶜwater_fix_gross,
        ᶜwater_fix_count,
        water_tag_fix_ledger_view(Y, model),
    )
    _apply_partition_repair!(
        Y.c,
        ledger,
        ᶜwater_pos,
        ᶜwater_neg,
        model.tags,
    )
    # Where every tag is zeroed, the repair adds `max(-(pos + neg), 0)` to the
    # partition's sum. That part is not moved between tags, so it leaves the
    # transfer's ledger, which took half of every change, and goes to its own.
    @. Y.c.q_tag_led_repair -= max(-(ᶜwater_pos + ᶜwater_neg), 0) / 2
    @. Y.c.q_tag_led_repairnet += max(-(ᶜwater_pos + ᶜwater_neg), 0)
    # Under `water_tag_precipitation: true` the rain parts and the snow parts
    # are repaired the same way, each among themselves, into the same ledgers.
    # Each tag's own ledger takes their changes too. They add to the ledgers
    # per mechanism, so they run before `after_tag_ledgers!`.
    _repair_water_tag_precip_parts!(Y, p, ledger, model)
    after_tag_ledgers!(p, Y, mechanisms)
    return nothing
end

# `ᶜpos` and `ᶜneg` are read-only here and come from the pre-repair state, so
# each tag can be rewritten in place and a later tag's factor still holds.
# `part` is the tags' part the repair acts on: the one field of each tag
# without the key, and one of its three parts with it.
_apply_partition_repair!(ᶜY, ledger, ᶜpos, ᶜneg, tags::Tuple) =
    _apply_partition_repair!(
        ᶜY,
        ledger,
        ᶜpos,
        ᶜneg,
        tags,
        NonPrecipitatingPart(),
    )
_apply_partition_repair!(ᶜY, ledger, ᶜpos, ᶜneg, ::Tuple{}, part) = nothing
function _apply_partition_repair!(ᶜY, ledger, ᶜpos, ᶜneg, tags::Tuple, part)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_tag = water_tag_part_field(ᶜY, tag, part)
        (ᶜfix, ᶜgross, ᶜcount) = tag_ledger_fields(ledger, tag)
        # Fix ledger first, so it records the correction itself and not its
        # effect on an already-corrected tag. This matches
        # `rescale_water_tags!`. The repair moves water between the tags, so the
        # gross counts each transfer twice, once out and once in. The state
        # ledger takes half of it, the water moved.
        @. ᶜY.q_tag_led_repair +=
            abs(
                max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg) -
                ᶜρq_tag,
            ) / 2
        @. ᶜgross += abs(
            max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg) - ᶜρq_tag,
        )
        @. ᶜcount += tag_event(
            max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg) - ᶜρq_tag,
            ᶜpos,
        )
        add_to_tag_ledger!(
            ledger.state,
            tag,
            @. lazy(
                max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg) - ᶜρq_tag,
            )
        )
        @. ᶜfix +=
            max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg) - ᶜρq_tag
        @. ᶜρq_tag = max(ᶜρq_tag, 0) * water_tag_repair_factor(ᶜpos, ᶜneg)
    end
    return _apply_partition_repair!(
        ᶜY,
        ledger,
        ᶜpos,
        ᶜneg,
        Base.tail(tags),
        part,
    )
end
