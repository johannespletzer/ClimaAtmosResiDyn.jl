#####
##### The gross of the tags' cache ledgers
#####
##### The cache ledgers `q_tag_fix_<name>`, `q_tag_upfix_<name>` and
##### `e_src_fix_<name>` are signed and cumulative. A correction of `+x` and
##### then `−x` reads zero, as does none at all.
##### Beside each, a gross sums the absolute value of every change, so opposite
##### changes do not cancel.
##### A count adds one for every cell-event whose change exceeds rounding.
##### Both record what was attempted: every call, including calls inside a
##### step that the stepper later discards.
#####
##### They are kept in Float64 whatever the model's float type. In Float32 a
##### sum of many small changes after a large one loses nearly all of them.

"""
    TAG_EVENT_THRESHOLD

A change counts as a cell-event where it exceeds this fraction of the cell's
total, or 16 rounding units of the total's float type if that is larger. The
copies' residual is nonzero at rounding level almost everywhere, so without a
bound the count would approach the number of cells times calls. In Float32
the rounding floor, about 1.9e-6, is the larger one.
"""
const TAG_EVENT_THRESHOLD = 1e-12

"""
    tag_event(change, total)

`1` where `change` is more than rounding against the cell's `total`, else `0`,
as a `Float64`.
"""
@inline tag_event(change, total) =
    abs(change) >
    max(TAG_EVENT_THRESHOLD, 16 * eps(typeof(abs(total)))) * abs(total) ? 1.0 :
    0.0

# A Float64 center field of zeros on the space of `ᶜρ`.
function _throughput_field(ᶜρ)
    ᶜfield = Fields.Field(Float64, axes(ᶜρ))
    fill!(parent(ᶜfield), 0)
    return ᶜfield
end

"""
    tag_throughput_fields(ᶜρ, tags)

One Float64 center field of zeros per tag, keyed like the state, for a gross
or a count beside a cache ledger. `tag_entry` gives each tag family's
key.
"""
tag_throughput_fields(ᶜρ, ::Tuple{}) = (;)
tag_throughput_fields(ᶜρ, tags::Tuple) = merge(
    tag_entry(first(tags), _throughput_field(ᶜρ)),
    tag_throughput_fields(ᶜρ, Base.tail(tags)),
)

"""
    tag_ledger(fix, gross, count, state = nothing)

The fields a correction writes for each tag: the signed ledger `fix`, its gross
and its count, each a `NamedTuple` keyed like the state, and, where each
tag keeps its own state ledger, `state`, a [`TagLedgerView`](@ref) of the
state, or `nothing`.
"""
tag_ledger(fix, gross, count, state = nothing) = (; fix, gross, count, state)

# The three fields of one tag in a ledger bundle.
tag_ledger_fields(ledger, tag) = (
    tag_field(ledger.fix, tag),
    tag_field(ledger.gross, tag),
    tag_field(ledger.count, tag),
)

"""
    tag_gross_total(fields)

The integral over the domain of the grosses beside the ledgers, summed over the
tags, for the audit: an amount, in the units of the ledger times volume. Collective, as
ClimaCore's `sum` is.
"""
function tag_gross_total(fields)
    total = 0.0
    for ᶜfield in values(fields)
        total += sum(ᶜfield)
    end
    return total
end

"""
    tag_event_total(fields)

The number of cell-events in the counts, summed over the cells and the tags,
for the audit. Collective, as ClimaCore's `sum` is. The count is divided by the
quadrature weight before the weighted sum, so each node counts once. It does
not read the field's storage, which holds a Float64 as two slots when the space
is Float32. On a sphere, a node on an element boundary counts once per element
that holds it.
"""
function tag_event_total(fields)
    isempty(fields) && return 0.0
    total = 0.0
    for ᶜfield in values(fields)
        ᶜWJ = Fields.local_geometry_field(axes(ᶜfield)).WJ
        total += sum(ᶜfield ./ ᶜWJ)
    end
    return total
end

#####
##### The state ledgers per mechanism, and their gross per step
#####
##### Each correction also adds, per application, the water or energy it moved
##### over the partition's tags to a state field of its own. The stepper
##### weights that field as it weights the tags, so it holds what the steps
##### retained. A read-only callback adds `|L − L_prev|` per step. That sum is
##### the retained gross.

"""
    WATER_TAG_MECHANISM_NAMES

The water tags' state ledgers per mechanism, present whenever water tags are:
the limiters' rescale where the parent held water, the emptying where it did
not, the partition repair's transfers, and the water the repair adds where it
zeroes every tag (`repairnet`). `WATER_TAG_COPY_MECHANISM_NAMES` adds the
copies' repair and the updraft filter's change to the copies. Their names
carry no `ρ` prefix, so no transport operator sees them.
"""
const WATER_TAG_MECHANISM_NAMES = (
    :q_tag_led_rescale,
    :q_tag_led_empty,
    :q_tag_led_repair,
    :q_tag_led_repairnet,
)
const WATER_TAG_COPY_MECHANISM_NAMES = (:q_tag_led_uprepair, :q_tag_led_upfilter)
const WATER_TAG_ALL_MECHANISM_NAMES =
    (WATER_TAG_MECHANISM_NAMES..., WATER_TAG_COPY_MECHANISM_NAMES...)

"""
    WATER_TAG_PRECIP_MECHANISM_NAMES

The water tags' state ledger of the closing step under
`water_tag_precipitation: true`: `q_tag_led_close`, what the closing step after
each follow added to the partition's rain and snow parts, or took from them
(`follow_water_tag_precipitation!`). Only with the key, so the state of other
runs keeps its layout. The key and updraft copies are never on together.
"""
const WATER_TAG_PRECIP_MECHANISM_NAMES = (:q_tag_led_close,)

"""
    WATER_TAG_LEAK_MECHANISM_NAMES

The water tags' state ledgers of the diffusion leak's correction, under
`water_tag_leak_correction: true` only: `q_tag_led_leaknet`, the partition's
correction, the net of what it gave the partition's tags.
`WATER_TAG_COPY_LEAK_MECHANISM_NAMES` adds the copies', `q_tag_led_upleaknet`,
times `ρaʲ` and summed over the updrafts. The correction is a tendency, so these
ledgers are exact per step at every `update_constrain_state_every`, and they
have no `attempted` total: a tendency is evaluated at every stage and Newton
iterate, and a sum over those evaluations is not what any step tried to move.
See [`correct_water_tag_diffusion_leak!`](@ref).
"""
const WATER_TAG_LEAK_MECHANISM_NAMES = (:q_tag_led_leaknet,)
const WATER_TAG_COPY_LEAK_MECHANISM_NAMES = (:q_tag_led_upleaknet,)

"""
    water_tag_leak_mechanism_names(model)

The names of the leak correction's ledgers, in state order, or `()` without
`water_tag_leak_correction: true`.
"""
water_tag_leak_mechanism_names(::Nothing) = ()
water_tag_leak_mechanism_names(model::WaterTaggingModel) =
    has_water_tag_leak_correction(model) ?
    (
        has_water_tag_updraft_copies(model) ?
        (WATER_TAG_LEAK_MECHANISM_NAMES..., WATER_TAG_COPY_LEAK_MECHANISM_NAMES...) :
        WATER_TAG_LEAK_MECHANISM_NAMES
    ) : ()

"""
    water_tag_leak_mechanism_variables(value, model)

The initial state of the leak correction's ledgers: zero, in the type of
`value`, per point. `(;)` without them.
"""
water_tag_leak_mechanism_variables(value, model) =
    _mechanism_zeros(value, Val(water_tag_leak_mechanism_names(model)))

"""
    is_water_tag_leak_mechanism_name(name)

Whether `name` is one of the leak correction's ledgers.
"""
is_water_tag_leak_mechanism_name(name::Symbol) =
    name in WATER_TAG_LEAK_MECHANISM_NAMES ||
    name in WATER_TAG_COPY_LEAK_MECHANISM_NAMES

"""
    ENERGY_SOURCE_MECHANISM_NAMES

The energy source tags' state ledgers of the partition repair: its transfers,
and the energy it adds where it zeroes every tag (`repairnet`).
"""
const ENERGY_SOURCE_MECHANISM_NAMES = (:e_src_led_repair, :e_src_led_repairnet)

"""
    water_tag_mechanism_names(model)

The names of the water tags' state ledgers per mechanism, in state order, or
`()` without water tags.
"""
water_tag_mechanism_names(::Nothing) = ()
water_tag_mechanism_names(model::WaterTaggingModel) = _water_tag_mechanism_names(
    Val(has_water_tag_updraft_copies(model)),
    Val(has_water_tag_precipitation(model)),
)
_water_tag_mechanism_names(::Val{false}, ::Val{false}) = WATER_TAG_MECHANISM_NAMES
_water_tag_mechanism_names(::Val{true}, ::Val{false}) =
    WATER_TAG_ALL_MECHANISM_NAMES
_water_tag_mechanism_names(::Val{false}, ::Val{true}) =
    (WATER_TAG_MECHANISM_NAMES..., WATER_TAG_PRECIP_MECHANISM_NAMES...)

"""
    energy_source_mechanism_names(model)

The names of the energy source tags' state ledgers per mechanism, or `()`
without energy source tags. They exist whether or not the repair is on, so
that turning it off does not change the state's layout.
"""
energy_source_mechanism_names(::Nothing) = ()
energy_source_mechanism_names(::EnergySourceTaggingModel) =
    ENERGY_SOURCE_MECHANISM_NAMES

"""
    water_tag_mechanism_variables(value, model)
    energy_source_mechanism_variables(value, model)

The initial state of each family's ledgers per mechanism: zero, in the type of
`value`, per point, for `grid_scale_center_variables`. The names are constants
chosen by dispatch, so the state's type can be inferred.
"""
water_tag_mechanism_variables(value, ::Nothing) = (;)
water_tag_mechanism_variables(value, model::WaterTaggingModel) =
    _mechanism_zeros(
        value,
        Val(
            _water_tag_mechanism_names(
                Val(has_water_tag_updraft_copies(model)),
                Val(has_water_tag_precipitation(model)),
            ),
        ),
    )
energy_source_mechanism_variables(value, ::Nothing) = (;)
energy_source_mechanism_variables(value, ::EnergySourceTaggingModel) =
    _mechanism_zeros(value, Val(ENERGY_SOURCE_MECHANISM_NAMES))
_mechanism_zeros(value, ::Val{names}) where {names} =
    NamedTuple{names}(ntuple(_ -> zero(value), Val(length(names))))

"""
    is_tag_mechanism_ledger_name(name)

Whether `name` is a state ledger per mechanism of either family.
"""
is_tag_mechanism_ledger_name(name::Symbol) =
    name in WATER_TAG_MECHANISM_NAMES ||
    name in WATER_TAG_COPY_MECHANISM_NAMES ||
    name in WATER_TAG_PRECIP_MECHANISM_NAMES ||
    name in ENERGY_SOURCE_MECHANISM_NAMES

"""
    tag_state_ledger_names(atmos)

Every state ledger of the tags that the per-step gross follows: the ledgers per
mechanism, the leak correction's, the increment corrections' ledgers, the
water tags' ledgers of the withheld gain, and each tag's own ledgers where the
tags keep them, of both families. The ledgers of the withheld gain are a
tendency's, as the leak correction's are, so they have no `attempted` total.
"""
tag_state_ledger_names(atmos) = (
    water_tag_mechanism_names(atmos.water_tagging_model)...,
    water_tag_leak_mechanism_names(atmos.water_tagging_model)...,
    _water_increment_ledger_names(atmos.water_tagging_model)...,
    water_tag_exp_ledger_names(atmos.water_tagging_model)...,
    water_tag_per_tag_ledger_names(atmos.water_tagging_model)...,
    energy_source_mechanism_names(atmos.energy_source_tagging_model)...,
    _energy_increment_ledger_names(atmos.energy_source_tagging_model)...,
    energy_source_per_tag_ledger_names(atmos.energy_source_tagging_model)...,
)
_water_increment_ledger_names(::Nothing) = ()
_water_increment_ledger_names(model) = water_tag_increment_ledger_names(model)
_energy_increment_ledger_names(::Nothing) = ()
_energy_increment_ledger_names(model) =
    energy_source_increment_ledger_names(model)

"""
    tag_ledger_step_cache(Y, atmos)

Per state ledger `L`, in Float64: `ᶜprev`, the value at the last step, which
starts from `Y`, so a restarted run does not count the restored ledger; `ᶜgross`,
the sum over the steps of `|L − L_prev|`; `colgross`, the sum over the steps of
`|∫(L − L_prev) dz|` per column; and `ᶜevents`, the number of steps in which
the change exceeded rounding against the cell's total (`tag_event`). `ᶜdiff`
and `coldiff` are scratch. `(;)` without state ledgers.

Beside them: `attempted`, per ledger that a kernel or the increment
correction writes, the sum over every call of the absolute value of what that
call added, including calls on stage values that the stepper discards;
`before`, per ledger per mechanism, the ledger kept before a call; and
`cadence`, the run's `update_constrain_state_every`, which
[`set_tag_ledger_cadence!`](@ref) sets. Each tag's own ledger of the limiters'
and the repair's corrections has no `attempted`: the gross beside the cache
ledger takes the same changes. Under `water_tag_precipitation: true` that gross
also counts the moves between a tag's own parts, which leave the tag's own
ledger unchanged. So a water tag's `attempted` exceeds its retained gross by
those moves too.

With water tags, also `negative_water`, the parent's negative water accumulator (see
[`negative_water_accumulator_cache`](@ref)), and `nothing` without them.
"""
function tag_ledger_step_cache(Y, atmos)
    names = tag_state_ledger_names(atmos)
    isempty(names) && return (;)
    ᶜdiff = _throughput_field(Y.c.ρ)
    coldiff = Fields.Field(Float64, axes(Fields.level(Y.f.u₃, half)))
    fill!(parent(coldiff), 0)
    ledgers = NamedTuple{names}(
        map(names) do name
            ᶜprev = _throughput_field(Y.c.ρ)
            ᶜprev .= getproperty(Y.c, name)
            colgross = similar(coldiff)
            fill!(parent(colgross), 0)
            (;
                ᶜprev,
                ᶜgross = _throughput_field(Y.c.ρ),
                colgross,
                ᶜevents = _throughput_field(Y.c.ρ),
            )
        end,
    )
    attempted_names = tag_attempted_ledger_names(atmos)
    attempted = NamedTuple{attempted_names}(
        map(_ -> _throughput_field(Y.c.ρ), attempted_names),
    )
    mechanism_names = (
        water_tag_mechanism_names(atmos.water_tagging_model)...,
        energy_source_mechanism_names(atmos.energy_source_tagging_model)...,
    )
    before = NamedTuple{mechanism_names}(
        map(_ -> _throughput_field(Y.c.ρ), mechanism_names),
    )
    return (;
        tag_ledger_steps = (;
            ledgers,
            ᶜdiff,
            coldiff,
            attempted,
            before,
            cadence = Ref(:step),
            negative_water = negative_water_accumulator_cache(
                Y,
                atmos.water_tagging_model,
            ),
        ),
    )
end

#####
##### The parent's negative water, over time
#####
##### The water closure check writes the parent's negative water at its rows
##### only. After every accepted step this accumulator adds it up.
##### `check_negative_water_step!` compares it with the check's level. A
##### negative excursion between two rows is counted, and it sets the flag if
##### it passes the level.

"""
    negative_water_accumulator_cache(Y, water_tagging_model)

The parent's negative water accumulator, in Float64, or `nothing` without water tags:

  - `ᶜamount`: per cell, the sum over the accepted steps of
    `max(-ρq_tot, 0) Δt`, in kg s m⁻³. It is `ρ max(-q_tot, 0)` without the
    division. Its volume integral is in kg s: the time integral of the
    parent's negative water since the start of the run.
  - `ᶜevents`: per cell, the number of accepted steps whose end state has
    `ρq_tot < 0` there.
  - `last_row`: the time, the integral of `ᶜamount` and the event count at the
    last audit row, `NaN` before the first row of a run or of a restarted
    segment. The audit reports the change since then.

Each accepted step adds the value of its end state
([`accumulate_negative_water!`](@ref)). A step whose end state has no negative
water anywhere leaves both fields bit for bit as they were. So their change
over an interval is exactly zero when no accepted step in it had negative
water. The converse holds for `ᶜevents`, which counts in whole steps: it
grows by 1 in each cell and step with any. A small amount can round away
against a large `ᶜamount` in the same cell. So the event count, not the
amount, is the exact test.

`ᶜamount` and `ᶜevents` live in the cache, never in the state, so the model's
fields cannot depend on them. The checkpoint carries them
(`tag_ledger_checkpoint_fields`). `last_row` is not carried: the first
row after a restart is at the checkpoint's time, where the run before wrote
its last row.
"""
negative_water_accumulator_cache(Y, ::Nothing) = nothing
negative_water_accumulator_cache(Y, model) = (;
    ᶜamount = _throughput_field(Y.c.ρ),
    ᶜevents = _throughput_field(Y.c.ρ),
    last_row = Ref((NaN, NaN, NaN)),
)

# The accumulator in `p.tagging`, or `nothing` without it.
negative_water_accumulator(tagging) =
    _negative_water_accumulator(_tag_ledger_steps(tagging))
_negative_water_accumulator(::Nothing) = nothing
_negative_water_accumulator(steps) = steps.negative_water

"""
    accumulate_negative_water!(accumulator, ᶜρq_tot, dt)

Add one accepted step to the parent's negative water accumulator `accumulator` (see
[`negative_water_accumulator_cache`](@ref)): `max(-ρq_tot, 0) dt` to `ᶜamount`, and
1 to `ᶜevents` where `ρq_tot < 0`. `dt` is the length of the step just
accepted, in seconds. Where `ρq_tot` is not negative, including `-0.0`, it
adds `-0.0` and `0.0`, which leave the accumulator bit for bit. A no-op without the
accumulator.
"""
accumulate_negative_water!(::Nothing, ᶜρq_tot, dt) = nothing
function accumulate_negative_water!(accumulator, ᶜρq_tot, dt)
    (; ᶜamount, ᶜevents) = accumulator
    @. ᶜamount += negative_water_density(ᶜρq_tot) * dt
    @. ᶜevents += ifelse(ᶜρq_tot < zero(ᶜρq_tot), 1.0, 0.0)
    return nothing
end

# The parent's negative water per volume, `max(-ρq_tot, 0)`, in Float64. The
# same split as the partition's (`water_tag_negative_part`), so `-0.0` is not
# negative water.
@inline negative_water_density(ρq_tot) =
    Float64(-water_tag_negative_part(ρq_tot))

"""
    check_negative_water_step!(integrator, void_above)

Compare the parent's negative water with `void_above` at the end of every
accepted step. Above `void_above` of `∫ρq_tot`, a run's water results are not
scored, whether or not a row of the water closure check sees it.

It takes [`negative_water_step_relative`](@ref) of the step's end state. Where
that passes `void_above`, it sets the water check's flag in
`p.tagging.negative_water_void` (see [`negative_water_void_flags`](@ref)),
which the next row of both tables writes as `negative_water_void = 1`. The
first time, the root process warns once. The flag then stays set, through a
restart too. A row of the check that sees the same state later in the step
does not warn again.

A crossing after the run's last row reaches no row. The water check's rows fall
every `period` from the start, so where `t_end` is not a multiple of the period,
or after a graceful exit, the last steps have no row after them. A step past the
level there still sets the flag and warns. A checkpoint written after it carries
the flag, and the next segment's rows are marked. But no row of this run's
tables shows it.

`void_above` is the water check's `negative_water_void_above`. `nothing`, for
`~` or without a water check, does no work at all. Otherwise every process
takes the first sum on every accepted step, and the second after a step with
negative water, since both are collective. It writes only the flag, never a
field, so the model's fields cannot depend on it.
"""
check_negative_water_step!(integrator, ::Nothing) = nothing
function check_negative_water_step!(integrator, void_above)
    Y = integrator.u
    relative = negative_water_step_relative(Y.c.ρq_tot)
    relative > void_above || return nothing
    voided = negative_water_voided(integrator.p, :water)
    first_void = !voided[]
    voided[] = true
    first_void && ClimaComms.iamroot(ClimaComms.context(Y.c)) &&
        @warn(
            "The water tags' parent has negative water $relative of its water at \
            the end of the step to t = $(Float64(integrator.t)) s, above \
            `negative_water_void_above` = $void_above. The tags partition only \
            its non-negative part, and `q_tag_negative` holds the rest. The run \
            goes on. Every later row of the water closure and audit tables is \
            marked `negative_water_void`, also after a restart. If the run ends \
            before its next row, no row shows this crossing: only this warning \
            and a checkpoint written after it record it."
        )
    return nothing
end

"""
    tag_attempted_ledger_names(atmos)

The state ledgers whose writers also add to an `attempted` accumulator: the
ledgers per mechanism, the increment corrections' ledgers, and each tag's own
ledger of the increment correction, of both families.
"""
tag_attempted_ledger_names(atmos) = (
    water_tag_mechanism_names(atmos.water_tagging_model)...,
    _water_increment_ledger_names(atmos.water_tagging_model)...,
    water_tag_ledger_inc_names(atmos.water_tagging_model)...,
    energy_source_mechanism_names(atmos.energy_source_tagging_model)...,
    _energy_increment_ledger_names(atmos.energy_source_tagging_model)...,
    energy_source_ledger_inc_names(atmos.energy_source_tagging_model)...,
)

"""
    set_tag_ledger_cadence!(p, update_constrain_state_every)

Record the run's `update_constrain_state_every` in the tags' ledger cache, for
the audit, and warn where the per-step gross of a transfer's ledger is not
exact. At `step`, the default, the corrections fire once per step on the
accepted state, so the change of a ledger per mechanism over a step is what the
step moved. At `stage` or `dss` each firing is weighted by its tableau weight,
which under ARS343 can be negative, so a transfer's ledger can fall within a
step, and its per-step change is neither what the step moved nor a bound on it.
Each tag's own ledger follows its tag at every cadence. A no-op without state
ledgers.
"""
set_tag_ledger_cadence!(p, cadence) =
    _set_tag_ledger_cadence!(_tag_ledger_steps(p.tagging), Symbol(cadence))
_set_tag_ledger_cadence!(::Nothing, cadence) = nothing
function _set_tag_ledger_cadence!(steps, cadence)
    steps.cadence[] = cadence
    any(is_tag_mechanism_ledger_name, keys(steps.ledgers)) &&
        cadence != :step &&
        @warn(
            "`update_constrain_state_every: $cadence`: the tags' ledgers per \
            mechanism record what each correction retained, but their change \
            over a step is not what the step moved, since a firing inside the \
            step is weighted by its tableau weight, which can be negative. \
            Their per-step gross and the audit's `_retained` columns are exact \
            only at `step`. Each tag's own ledgers, where kept, are exact at \
            every cadence.",
        )
    return nothing
end

# The ledger cache in `p.tagging`, or `nothing` where there is none. The test
# is on the type, so it folds away at compile time.
_tag_ledger_steps(::Nothing) = nothing
_tag_ledger_steps(tagging::NamedTuple) = _tag_ledger_steps(
    tagging,
    Val(hasfield(typeof(tagging), :tag_ledger_steps)),
)
_tag_ledger_steps(tagging, ::Val{true}) = tagging.tag_ledger_steps
_tag_ledger_steps(tagging, ::Val{false}) = nothing


"""
    accumulate_tag_ledger_gross!(integrator, negative_water_void_above = nothing)

After an accepted step, add each state ledger's change over the step to its
gross, per cell and per column, and remember the ledger. With water tags, also
add the step to the parent's negative water accumulator
([`accumulate_negative_water!`](@ref)). Where the water check sets
`negative_water_void_above`, also compare the parent's negative water with it
([`check_negative_water_step!`](@ref)). It reads the state and writes only its
own cache.
"""
function accumulate_tag_ledger_gross!(
    integrator,
    negative_water_void_above = nothing,
)
    Y = integrator.u
    (; atmos) = integrator.p
    (; ledgers, ᶜdiff, coldiff, negative_water) =
        integrator.p.tagging.tag_ledger_steps
    _accumulate_ledger_gross!(
        Y,
        ledgers,
        ᶜdiff,
        coldiff,
        _water_ledger_total(Y, atmos.water_tagging_model),
        _energy_ledger_total(Y, atmos.energy_source_tagging_model),
        Val(keys(ledgers)),
    )
    # The parent's negative water, from the step's end state. It is weighted
    # by the length of the step just accepted. ClimaTimeSteppers' `__step!`
    # (0.10.6 to 1.0.1) sets `integrator.dt` to `min(_dt, first(tstops) - t)`
    # before it steps, moves `t` by that, and only then runs the callbacks.
    # So `integrator.dt` is that step, shortened where it met a stop.
    # ClimaAtmos keeps time as `ITime`, whose sum is exact, so `t` moved by
    # exactly `dt`. `tagged_water_integration.jl` checks the accumulator
    # against the elapsed times over shortened steps.
    isnothing(negative_water) || accumulate_negative_water!(
        negative_water,
        Y.c.ρq_tot,
        Float64(float(integrator.dt)),
    )
    # The contract's level, at the end of every accepted step. A no-op for
    # `negative_water_void_above: ~`.
    check_negative_water_step!(integrator, negative_water_void_above)
    return nothing
end
# The total a change of each family's ledger counts as an event against: the
# parent's water, and the energy the energy source tags partition.
_water_ledger_total(Y, ::Nothing) = nothing
_water_ledger_total(Y, model) = Y.c.ρq_tot
_energy_ledger_total(Y, ::Nothing) = nothing
_energy_ledger_total(Y, model) = _energy_source_parent_field(Y, model.offset)
# The names are type parameters and each field is named by a literal. So the
# ledgers' part of the callback needs no run-time symbol and allocates nothing
# on a column. The exception is ClimaCore's `column_integral_definite!`, which
# the model's surface precipitation calls every step too. The check of the
# parent's negative water allocates where the water check has a level.
# ClimaCore's `sum` wraps each global sum in a one-element array for the
# allreduce. The check takes one sum on a clean parent and two after a step
# with negative water.
@generated function _accumulate_ledger_gross!(
    Y,
    ledgers,
    ᶜdiff,
    coldiff,
    ᶜwater_total,
    ᶜenergy_total,
    ::Val{names},
) where {names}
    each = map(names) do name
        total =
            startswith(string(name), "q_tag_") ? :ᶜwater_total : :ᶜenergy_total
        quote
            let ᶜL = Y.c.$name, ledger = ledgers.$name
                @. ᶜdiff = ᶜL - ledger.ᶜprev
                @. ledger.ᶜgross += abs(ᶜdiff)
                @. ledger.ᶜevents += tag_event(ᶜdiff, $total)
                Operators.column_integral_definite!(coldiff, ᶜdiff)
                @. ledger.colgross += abs(coldiff)
                @. ledger.ᶜprev = ᶜL
            end
        end
    end
    return quote
        $(each...)
        return nothing
    end
end

"""
    check_tag_mechanism_ledgers(restart_file, Y, expected, family, prefix,
                                config_key)

Compare the ledgers per mechanism in the restored state `Y` with `expected`, as
`check_restart_fields` does. A checkpoint with none of these ledgers is refused
with its own message, since the ledgers would otherwise start at zero partway
through the run.
"""
function check_tag_mechanism_ledgers(
    restart_file,
    Y,
    expected,
    family,
    prefix,
    config_key,
)
    in_family(name) =
        is_tag_mechanism_ledger_name(name) &&
        startswith(string(name), prefix)
    if !isempty(expected) && !any(in_family, propertynames(Y.c))
        error(
            "The restart file $restart_file was written before the $family \
            tags kept their ledgers per mechanism \
            ($(join(expected, ", "))). Such a checkpoint is refused, because \
            the ledgers would start at zero partway through the run. Start a \
            new run.",
        )
    end
    return check_restart_fields(
        restart_file,
        Y,
        in_family,
        expected,
        "$family tags' ledgers per mechanism",
        config_key,
        "",
    )
end

#####
##### Each tag's own ledgers: what was attempted beside what the steps
##### retained, the audit's report per ledger, and the accumulators carried
##### through a restart
#####

"""
    TagLedgerView{Kind}(obj)

A view of a state or tendency `obj`, such as `Y.c` or `Yₜ.c`, whose
`tag_field` for a tag is that tag's own ledger of kind `Kind` rather than the
tag: `q_tag_led_<Kind>_<name>` for a water tag and `e_src_led_<Kind>_<name>` for
an energy source tag. `Kind` is `:fix`, for the limiters' rescale and the
repair, `:inc`, for the increment correction, or, for water tags only, `:leak`
and `:upleak`, for the diffusion leak's correction of the tag and of its copies.
A kernel that changes the tags writes the same change into it, so each ledger
follows its tag's correction.
"""
struct TagLedgerView{Kind, O}
    obj::O
end
TagLedgerView{Kind}(obj) where {Kind} = TagLedgerView{Kind, typeof(obj)}(obj)
@generated tag_field(
    ledger_view::TagLedgerView{Kind},
    ::WaterTag{name},
) where {Kind, name} = :(ledger_view.obj.$(Symbol(:q_tag_led_, Kind, :_, name)))
@generated tag_field(
    ledger_view::TagLedgerView{Kind},
    ::EnergySourceTag{name},
) where {Kind, name} = :(ledger_view.obj.$(Symbol(:e_src_led_, Kind, :_, name)))

"""
    add_to_tag_ledger!(ledger_view, tag, change)

Add `change`, a field or a lazy broadcast, to the tag's own ledger in
`ledger_view`. A no-op for `nothing`, where the tags keep no ledger per tag.
"""
@inline add_to_tag_ledger!(::Nothing, tag, change) = nothing
@inline function add_to_tag_ledger!(ledger_view::TagLedgerView, tag, change)
    ᶜL = tag_field(ledger_view, tag)
    @. ᶜL += change
    return nothing
end

# The tag's name from its type, for the generated name lists below.
_tag_type_name(::Type{<:WaterTag{name}}) where {name} = name
_tag_type_name(::Type{<:EnergySourceTag{name}}) where {name} = name
@generated _prefixed_tag_names(::Val{prefix}, tags::Tuple) where {prefix} =
    QuoteNode(Tuple(Symbol(prefix, _tag_type_name(T)) for T in tags.parameters))

"""
    water_tag_ledger_fix_names(model)
    water_tag_ledger_inc_names(model)
    water_tag_ledger_leak_names(model)
    water_tag_ledger_upleak_names(model)
    water_tag_per_tag_ledger_names(model)

Each water tag's own state ledgers, in state order, under
`water_tag_ledger_per_tag: true`, and `()` otherwise:

  - `q_tag_led_fix_<name>` for every tag: what the limiters' rescale and the
    partition repair changed it by.
  - `q_tag_led_inc_<name>` under `water_tag_transport: increment`: what the
    correction after each solve moved into or out of it.
  - `q_tag_led_leak_<name>` under `water_tag_leak_correction: true`: what the
    diffusion leak's correction gave it.
  - `q_tag_led_upleak_<name>` under `water_tag_leak_correction: true` with
    updraft copies: what the correction gave its copies, times `ρaʲ`.

Their names carry no `ρ` prefix, so no transport operator sees them. The tag
names `led_*` are reserved.
"""
water_tag_ledger_fix_names(::Nothing) = ()
water_tag_ledger_fix_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) ?
    _prefixed_tag_names(Val(:q_tag_led_fix_), model.tags) : ()
water_tag_ledger_inc_names(::Nothing) = ()
water_tag_ledger_inc_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) && follows_water_increment(model) ?
    _prefixed_tag_names(Val(:q_tag_led_inc_), model.tags) : ()
water_tag_ledger_leak_names(::Nothing) = ()
water_tag_ledger_leak_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) && has_water_tag_leak_correction(model) ?
    _prefixed_tag_names(Val(:q_tag_led_leak_), model.tags) : ()
water_tag_ledger_upleak_names(::Nothing) = ()
water_tag_ledger_upleak_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) &&
    has_water_tag_leak_correction(model) &&
    has_water_tag_updraft_copies(model) ?
    _prefixed_tag_names(Val(:q_tag_led_upleak_), model.tags) : ()
water_tag_per_tag_ledger_names(model) = (
    water_tag_ledger_fix_names(model)...,
    water_tag_ledger_inc_names(model)...,
    water_tag_ledger_leak_names(model)...,
    water_tag_ledger_upleak_names(model)...,
)

"""
    energy_source_ledger_fix_names(model)
    energy_source_ledger_inc_names(model)
    energy_source_ledger_src_names(model)
    energy_source_per_tag_ledger_names(model)

Each energy source tag's own state ledgers, in state order, under
`energy_source_tag_ledger_per_tag: true`, and `()` otherwise:
`e_src_led_fix_<name>` for every tag, what the repair changed it by; under
`energy_source_tag_transport: enthalpy_increment`, `e_src_led_inc_<name>`, what
the correction after each solve moved into or out of it; and
`e_src_led_src_<name>` for every tag, what the sources
(`attribute_energy_source_tags!`) put into it or took out of it. The per-step
gross of the last one is the source throughput (`energy_source_throughput`).

The source ledgers end with `e_src_led_src_res`, the residual's own: what the
sources did to `e_src_res`, the part of the total the region tags did not take.
Only where the region tags' masks are a verified partition is its per-step gross
the loss rule's flush of the residual. The tag name `res` is refused, so the name
cannot collide with a tag's.
"""
energy_source_ledger_fix_names(::Nothing) = ()
energy_source_ledger_fix_names(model::EnergySourceTaggingModel) =
    has_energy_source_ledger_per_tag(model) ?
    _prefixed_tag_names(Val(:e_src_led_fix_), model.tags) : ()
energy_source_ledger_inc_names(::Nothing) = ()
energy_source_ledger_inc_names(model::EnergySourceTaggingModel) =
    has_energy_source_ledger_per_tag(model) &&
    model.transport isa EnthalpyIncrementEnergySourceTransport ?
    _prefixed_tag_names(Val(:e_src_led_inc_), model.tags) : ()
energy_source_ledger_src_names(::Nothing) = ()
energy_source_ledger_src_names(model::EnergySourceTaggingModel) =
    has_energy_source_ledger_per_tag(model) ? _src_ledger_names(model.tags) : ()
# The source ledgers of the tags, then the residual's, as one literal tuple.
@generated _src_ledger_names(tags::Tuple) = QuoteNode((
    (Symbol(:e_src_led_src_, _tag_type_name(T)) for T in tags.parameters)...,
    :e_src_led_src_res,
))

"""
    ENERGY_SOURCE_RESIDUAL_LEDGER

`:e_src_led_src_res`, the residual's own source ledger among each energy source
tag's source ledgers (`energy_source_ledger_src_names`). It belongs to no tag,
so the audit gives it no inventory fraction.
"""
const ENERGY_SOURCE_RESIDUAL_LEDGER = :e_src_led_src_res
energy_source_per_tag_ledger_names(model) = (
    energy_source_ledger_fix_names(model)...,
    energy_source_ledger_inc_names(model)...,
    energy_source_ledger_src_names(model)...,
)

"""
    water_tag_per_tag_ledger_variables(value, model)
    energy_source_per_tag_ledger_variables(value, model)

The initial state of each tag's own ledgers: zero, in the type of `value`, per
point, for `grid_scale_center_variables`. `(;)` without them.
"""
water_tag_per_tag_ledger_variables(value, model) =
    _mechanism_zeros(value, Val(water_tag_per_tag_ledger_names(model)))
energy_source_per_tag_ledger_variables(value, model) =
    _mechanism_zeros(value, Val(energy_source_per_tag_ledger_names(model)))

"""
    is_tag_per_tag_ledger_name(name)

Whether `name` is one tag's own state ledger, of either family.
"""
is_tag_per_tag_ledger_name(name::Symbol) =
    any(
        prefix -> startswith(string(name), prefix),
        TAG_PER_TAG_LEDGER_PREFIXES,
    )

# The prefixes of each tag's own ledgers, of both families.
const TAG_PER_TAG_LEDGER_PREFIXES = (
    "q_tag_led_fix_",
    "q_tag_led_inc_",
    "q_tag_led_leak_",
    "q_tag_led_upleak_",
    "e_src_led_fix_",
    "e_src_led_inc_",
    "e_src_led_src_",
)

"""
    water_tag_fix_ledger_view(Y, model)
    energy_source_fix_ledger_view(Y, model)
    water_tag_inc_ledger_view(Yₜ, model)
    energy_source_inc_ledger_view(Yₜ, model)

The [`TagLedgerView`](@ref) of `Y.c` (or `Yₜ.c`) that the corrections write
each tag's change into, or `nothing` where the tags keep no ledger per tag.
Chosen from the model's type, so it folds away at compile time.
"""
water_tag_fix_ledger_view(Y, model) =
    has_water_tag_ledger_per_tag(model) ? TagLedgerView{:fix}(Y.c) : nothing
energy_source_fix_ledger_view(Y, model) =
    has_energy_source_ledger_per_tag(model) ? TagLedgerView{:fix}(Y.c) :
    nothing
water_tag_inc_ledger_view(Yₜ, model) =
    has_water_tag_ledger_per_tag(model) ? TagLedgerView{:inc}(Yₜ.c) : nothing
energy_source_inc_ledger_view(Yₜ, model) =
    has_energy_source_ledger_per_tag(model) ? TagLedgerView{:inc}(Yₜ.c) :
    nothing

"""
    energy_source_src_ledger_view(Yₜ, model)

The [`TagLedgerView`](@ref) of `Yₜ.c` that the sources write each energy source
tag's change into, `e_src_led_src_<name>`, or `nothing` where the tags keep no
ledger per tag. The attribution adds to the tags' tendencies, so the ledger is a
tendency too. The stepper integrates it as it integrates the tag.
"""
energy_source_src_ledger_view(Yₜ, model) =
    has_energy_source_ledger_per_tag(model) ? TagLedgerView{:src}(Yₜ.c) :
    nothing

"""
    before_tag_ledgers!(p, Y, Val(names))
    after_tag_ledgers!(p, Y, Val(names))

Around a call of a correction kernel, keep each named ledger per mechanism, and
afterwards add the absolute value of its change to what that mechanism
attempted. A call on a stage value that the stepper discards counts too, so
`attempted` less the per-step gross is the work the steps discarded, at
`update_constrain_state_every: step`. No-ops without the ledger cache, as in
the unit tests' mock caches.
"""
before_tag_ledgers!(p, Y, names) =
    _before_tag_ledgers!(_tag_ledger_steps(p.tagging), Y, names)
after_tag_ledgers!(p, Y, names) =
    _after_tag_ledgers!(_tag_ledger_steps(p.tagging), Y, names)
_before_tag_ledgers!(::Nothing, Y, names) = nothing
_after_tag_ledgers!(::Nothing, Y, names) = nothing
@generated function _before_tag_ledgers!(
    steps::NamedTuple,
    Y,
    ::Val{names},
) where {names}
    each = map(name -> :(@. steps.before.$name = Y.c.$name), names)
    return quote
        $(each...)
        return nothing
    end
end
@generated function _after_tag_ledgers!(
    steps::NamedTuple,
    Y,
    ::Val{names},
) where {names}
    each = map(
        name -> :(@. steps.attempted.$name += abs(Y.c.$name - steps.before.$name)),
        names,
    )
    return quote
        $(each...)
        return nothing
    end
end

"""
    add_attempted!(p, Val(name), change)

Add `abs(change)` to the ledger `name`'s `attempted` accumulator, for the
increment corrections, which write their ledgers' change per stage directly.
A no-op without the ledger cache.
"""
add_attempted!(p, name, change) =
    _add_attempted!(_tag_ledger_steps(p.tagging), name, change)
_add_attempted!(::Nothing, name, change) = nothing
function _add_attempted!(steps::NamedTuple, ::Val{name}, change) where {name}
    ᶜattempted = getproperty(steps.attempted, name)
    @. ᶜattempted += abs(change)
    return nothing
end

"""
    add_attempted_per_tag!(p, Yₜ, dtγ, ledger_view, tags)

After the increment correction has written each tag's change per stage into
`ledger_view` of the tendency `Yₜ`, add `abs(dtγ · Yₜ)` of each tag's ledger to
its `attempted` accumulator. A no-op without ledgers per tag.
"""
add_attempted_per_tag!(p, Yₜ, dtγ, ::Nothing, tags) = nothing
add_attempted_per_tag!(p, Yₜ, dtγ, ledger_view::TagLedgerView, tags) =
    _add_attempted_per_tag!(_tag_ledger_steps(p.tagging), dtγ, ledger_view, tags)
_add_attempted_per_tag!(::Nothing, dtγ, ledger_view, tags) = nothing
_add_attempted_per_tag!(steps::NamedTuple, dtγ, ledger_view, ::Tuple{}) =
    nothing
function _add_attempted_per_tag!(
    steps::NamedTuple,
    dtγ,
    ledger_view,
    tags::Tuple,
)
    tag = first(tags)
    ᶜattempted = tag_field(TagLedgerView{:inc}(steps.attempted), tag)
    ᶜLₜ = tag_field(ledger_view, tag)
    @. ᶜattempted += abs(dtγ * ᶜLₜ)
    return _add_attempted_per_tag!(steps, dtγ, ledger_view, Base.tail(tags))
end

"""
    TAG_LEDGER_SMALL_TAG_BOUND

The small-tag bound for a tag's own ledgers, as a fraction of the family's
parent scale: 2e-4. Below it a tag holds too little for a ratio to the tag to
be read, and the audit reports that ratio as not
applicable ([`tag_ledger_normalization`](@ref)).
"""
const TAG_LEDGER_SMALL_TAG_BOUND = 2e-4

"""
    tag_ledger_normalization(retained, inventory, burden, parent_scale)

The ratios of one tag's own ledger, from its retained amount `retained`, the
tag's signed integral `inventory = ∫tag`, its absolute burden `burden = ∫|tag|`,
and the family's parent scale `parent_scale`, which is `NaN` where the run has
none:

  - `inventory_fraction`: `retained / inventory`, where `inventory > 0`. The
    ratio for a region tag, whose precondition is a positive inventory. It
    is ill-conditioned when a tag's positive and negative parts nearly cancel.
  - `burden_fraction`: `retained / burden`, where `burden > 0`. The ratio for a
    source-labelled tag and for any tag with negative parts. For a tag without
    negative parts it equals `inventory_fraction`.
  - `parent_fraction`: `retained / parent_scale`, where the scale is positive.
  - `applicable`: 1 where the burden is positive and at least
    [`TAG_LEDGER_SMALL_TAG_BOUND`](@ref) times the parent scale, and 0 where it
    is not. At 0 neither ratio to the tag applies, and the tag is judged by
    `parent_fraction`. Without a parent scale only a zero burden gives 0.

A ratio whose denominator is not positive is `NaN`. `applicable` is `NaN` only
where the burden or the retained amount is not finite.
"""
function tag_ledger_normalization(retained, inventory, burden, parent_scale)
    has_parent = isfinite(parent_scale) && parent_scale > 0
    bound = has_parent ? TAG_LEDGER_SMALL_TAG_BOUND * parent_scale : 0.0
    applicable =
        isfinite(burden) && isfinite(retained) ?
        (burden > 0 && burden >= bound ? 1.0 : 0.0) : NaN
    return (;
        inventory_fraction = inventory > 0 ? retained / inventory : NaN,
        burden_fraction = burden > 0 ? retained / burden : NaN,
        parent_fraction = has_parent ? retained / parent_scale : NaN,
        applicable,
    )
end

"""
    tag_ledger_audit(Y, p, prefix, scale, fix_gross, parent_scale)

The audit's columns for every state ledger of the family whose names start
with `prefix` (`"q_tag_"` or `"e_src_"`), each named by the ledger without the
prefix. Over the domain, as `scale` is:

  - `<L>_retained`, `<L>_retained_relative`: the per-step gross since the start
    of the run, `Σ |ΔL|` over the accepted steps, integrated, and over `scale`.
    Exact per step at `update_constrain_state_every: step` for the ledgers per
    mechanism, and at every cadence for each tag's own ledgers and the leak
    correction's;
  - `<L>_attempted`, `<L>_attempted_relative`: what the writers of `L` added,
    in absolute value, over every call, including stage values the stepper
    discards. For a tag's own ledger of the limiters' and the repair's
    corrections, the gross beside the cache ledger, `fix_gross`, which takes the
    same changes. `NaN` for the leak correction's ledgers, a tendency's,
    which have none. Under `water_tag_precipitation: true` that gross also
    counts the moves between a tag's own parts, which leave the tag's own
    ledger unchanged. So a water tag's `led_fix_<name>_attempted` exceeds
    `_retained` by those moves too;
  - `<L>_events`: the number of cell-steps whose change of `L` exceeded
    rounding against the cell's total;
  - for a tag's own ledger, `<L>_inventory_fraction`, `<L>_burden_fraction`,
    `<L>_parent_fraction` and `<L>_applicable`: `<L>_retained` over the tag's
    integral now, over its absolute burden now, and over `parent_scale`, and
    whether a ratio to the tag applies ([`tag_ledger_normalization`](@ref)).
    Under `water_tag_precipitation: true` a water tag's integral is the sum
    of its three parts, and its burden the sum of the parts' burdens.

With a tag's own ledgers, `ledger_parent_scale`: `parent_scale`, the family's
parent scale, `∫ρq_tot` for the water tags and for the energy source tags
`energy_source_ledger_parent_scale`, the gross source throughput. And
`ledger_cadence_step`: 1 at
`update_constrain_state_every: step`, 0 otherwise. `(;)` without the ledger
cache. Collective, as `sum` is.
"""
tag_ledger_audit(Y, p, prefix, scale, fix_gross, parent_scale) =
    _tag_ledger_audit(
        _tag_ledger_steps(p.tagging),
        Y,
        prefix,
        scale,
        fix_gross,
        parent_scale,
    )
_tag_ledger_audit(::Nothing, Y, prefix, scale, fix_gross, parent_scale) = (;)
function _tag_ledger_audit(steps, Y, prefix, scale, fix_gross, parent_scale)
    per_scale(x) = iszero(scale) ? zero(x) : x / scale
    tag_prefix = prefix == "q_tag_" ? "ρq_tag_" : "ρe_src_"
    names = Symbol[]
    values = Float64[]
    column!(name, value) = (push!(names, Symbol(name)); push!(values, value))
    per_tag = false
    for (name, ledger) in pairs(steps.ledgers)
        long = string(name)
        startswith(long, prefix) || continue
        short = chopprefix(long, prefix)
        retained = Float64(sum(ledger.ᶜgross))
        column!("$(short)_retained", retained)
        column!("$(short)_retained_relative", per_scale(retained))
        per_tag_fix = startswith(short, "led_fix_")
        attempted =
            per_tag_fix ?
            Float64(
                sum(
                    getproperty(
                        fix_gross,
                        Symbol(tag_prefix, chopprefix(short, "led_fix_")),
                    ),
                ),
            ) :
            haskey(steps.attempted, name) ?
            Float64(sum(getproperty(steps.attempted, name))) : NaN
        column!("$(short)_attempted", attempted)
        column!("$(short)_attempted_relative", per_scale(attempted))
        column!("$(short)_events", tag_event_total((ledger.ᶜevents,)))
        # The residual's source ledger belongs to no tag, so it has no
        # inventory to set its gross against.
        if is_tag_per_tag_ledger_name(name) &&
           name != ENERGY_SOURCE_RESIDUAL_LEDGER
            per_tag = true
            tag_name = foldl(
                chopprefix,
                ("led_fix_", "led_inc_", "led_src_", "led_leak_", "led_upleak_");
                init = short,
            )
            (inventory, burden) = _tag_ledger_inventory(Y.c, tag_prefix, tag_name)
            ratios = tag_ledger_normalization(
                retained,
                inventory,
                burden,
                Float64(parent_scale),
            )
            for (ratio, value) in pairs(ratios)
                column!("$(short)_$(ratio)", value)
            end
        end
    end
    isempty(names) && return (;)
    per_tag && column!("ledger_parent_scale", Float64(parent_scale))
    column!("ledger_cadence_step", steps.cadence[] == :step ? 1.0 : 0.0)
    return NamedTuple{Tuple(names)}(Tuple(values))
end

# A tag's signed integral and its absolute burden, for its own ledgers' ratios.
# Under `water_tag_precipitation: true` a water tag's water is the sum of its
# three parts, and its own ledger of the corrections takes all three. So the
# rain and snow parts are added, each with its own burden. Without the key the
# tag is its one field.
function _tag_ledger_inventory(ᶜY, tag_prefix, name)
    ᶜtag = getproperty(ᶜY, Symbol(tag_prefix, name))
    inventory = Float64(sum(ᶜtag))
    burden = Float64(sum(abs, ᶜtag))
    if tag_prefix == "ρq_tag_" && hasproperty(ᶜY, Symbol(:ρq_rtag_, name))
        for part_prefix in (:ρq_rtag_, :ρq_stag_)
            ᶜpart = getproperty(ᶜY, Symbol(part_prefix, name))
            inventory += Float64(sum(ᶜpart))
            burden += Float64(sum(abs, ᶜpart))
        end
    end
    return (inventory, burden)
end

"""
    energy_source_throughput(Y, p, model)

The gross energy the sources put into the energy source tags, over the domain
and since the start of the run. It is the sum over the partition's tags, the
region tags without sources, of the per-step gross of each tag's source ledger,
`Σ_steps |Δ e_src_led_src_<name>|`, integrated. The region tags receive
every source in full, gains by their masks and losses by their shares, so each
unit of source energy counts once. The source tags overlay them and are left out.
That holds only where their masks sum to one, a verified partition
([`energy_source_partition_verified`](@ref)). A strict subset counts too
little and an overlap too much, so the tables write `NaN` there. This function
returns the sum either way. A window's source throughput is the difference of
two values. `nothing` where the tags keep no ledger per tag. Collective, as `sum`
is.
"""
energy_source_throughput(Y, p, model) =
    _energy_source_throughput(_tag_ledger_steps(p.tagging), model)
_energy_source_throughput(steps, model) = nothing
function _energy_source_throughput(steps::NamedTuple, model::EnergySourceTaggingModel)
    isempty(energy_source_ledger_src_names(model)) && return nothing
    total = 0.0
    for name in energy_source_region_tag_state_names(model)
        ledger_name =
            Symbol(:e_src_led_src_, chopprefix(string(name), "ρe_src_"))
        total += Float64(sum(getproperty(steps.ledgers, ledger_name).ᶜgross))
    end
    return total
end

"""
    tag_ledger_checkpoint_fields(tagging)

The tags' accumulators a checkpoint carries, as a vector of
`name => field`: the cache ledgers `ᶜwater_fix`, `ᶜwater_upfix` and
`ᶜenergy_source_fix` with their grosses and counts, and, per state ledger,
the per-step gross, column gross, events and attempted. `ᶜprev` is not carried:
it is the ledger itself, which the state carries. With water tags, last, the
parent's negative water accumulator, `tag_ledger.negative_water.amount` and
`tag_ledger.negative_water.events` (see [`negative_water_accumulator_cache`](@ref)).
Empty without tags.
"""
function tag_ledger_checkpoint_fields(tagging)
    fields = Pair{String, Any}[]
    isnothing(tagging) && return fields
    for group in (
        :ᶜwater_fix,
        :ᶜwater_fix_gross,
        :ᶜwater_fix_count,
        :ᶜwater_upfix,
        :ᶜwater_upfix_gross,
        :ᶜwater_upfix_count,
        :ᶜenergy_source_fix,
        :ᶜenergy_source_fix_gross,
        :ᶜenergy_source_fix_count,
    )
        hasproperty(tagging, group) || continue
        group_name = replace(string(group), "ᶜ" => "")
        for (key, ᶜfield) in pairs(getproperty(tagging, group))
            push!(fields, "tag_ledger.$group_name.$key" => ᶜfield)
        end
    end
    steps = _tag_ledger_steps(tagging)
    isnothing(steps) && return fields
    for (name, ledger) in pairs(steps.ledgers)
        push!(fields, "tag_ledger.gross.$name" => ledger.ᶜgross)
        push!(fields, "tag_ledger.colgross.$name" => ledger.colgross)
        push!(fields, "tag_ledger.events.$name" => ledger.ᶜevents)
    end
    for (name, ᶜattempted) in pairs(steps.attempted)
        push!(fields, "tag_ledger.attempted.$name" => ᶜattempted)
    end
    append!(fields, negative_water_checkpoint_fields(steps.negative_water))
    append!(fields, water_application_checkpoint_fields(_water_meter(tagging)))
    return fields
end

# The negative water accumulator's fields in a checkpoint. A checkpoint may
# lack only these, so a restart treats them apart
# (`restore_tag_ledger_checkpoint!`).
negative_water_checkpoint_fields(::Nothing) = Pair{String, Any}[]
negative_water_checkpoint_fields(accumulator) = Pair{String, Any}[
    "tag_ledger.negative_water.amount" => accumulator.ᶜamount,
    "tag_ledger.negative_water.events" => accumulator.ᶜevents,
]
is_negative_water_checkpoint_field(name) =
    startswith(name, "tag_ledger.negative_water.")

"""
    write_tag_ledger_checkpoint!(writer, tagging)

Write the tags' accumulators (`tag_ledger_checkpoint_fields`) into the
checkpoint of `writer`, beside the state. A no-op without tags.
"""
function write_tag_ledger_checkpoint!(writer, tagging)
    for (name, field) in tag_ledger_checkpoint_fields(tagging)
        InputOutput.write!(writer, field, name)
    end
    return nothing
end

"""
    restore_tag_ledger_checkpoint!(tagging, restart_file, context)

Read the tags' accumulators back from `restart_file` into the cache just built,
so that a run continues them rather than starting them again at zero. The state
ledgers need nothing here: they are fields of the state, which the checkpoint
carries anyway.

The policy for a checkpoint without the accumulators:

  - A checkpoint with none of them starts them at zero, with a warning. The
    run then begins a new accumulator segment. Their totals, the audit's
    `_retained`, `_attempted` and `_events` among them, cover that segment
    only. They are not whole-run totals.
  - A checkpoint with some but not all of them is refused. Another
    configuration of the tags' ledgers wrote it.

The parent's negative water accumulator is treated apart. A checkpoint without
it starts it at zero, with its own warning, and the audit's `negative_water_*`
columns cover only this segment. A checkpoint with only part of it is refused.
The other accumulators are read as above.
"""
function restore_tag_ledger_checkpoint!(tagging, restart_file, context)
    all_fields = tag_ledger_checkpoint_fields(tagging)
    isempty(all_fields) && return nothing
    applications =
        filter(f -> is_water_application_checkpoint_field(first(f)), all_fields)
    fields = filter(
        f ->
            !is_negative_water_checkpoint_field(first(f)) &&
            !is_water_application_checkpoint_field(first(f)),
        all_fields,
    )
    later = filter(f -> is_negative_water_checkpoint_field(first(f)), all_fields)
    reader = InputOutput.HDF5Reader(restart_file, context)
    try
        restore_negative_water_accumulator!(reader, later, restart_file)
        restore_water_application_ledgers!(
            _water_meter(tagging),
            reader,
            applications,
            restart_file,
        )
        isempty(fields) && return nothing
        present = map(fields) do (name, _)
            haskey(reader.file, "fields/$name")
        end
        if !any(present)
            @warn(
                "The restart file $restart_file carries none of the tags' \
                accumulators: their cache ledgers, gross twins, counts, \
                per-step grosses and attempted totals. It was written before \
                they were carried. They start at zero, so this run begins a \
                new segment: the audit's grosses and the cumulative \
                diagnostics cover this segment only, not the whole run.",
            )
            return nothing
        end
        if !all(present)
            missing_names = [name for ((name, _), p) in zip(fields, present) if !p]
            error(
                "The restart file $restart_file carries some of the tags' \
                accumulators but not $(join(missing_names, ", ")). It was \
                written with another configuration of the tags' ledgers. \
                Restart with the same configuration, or start a new run.",
            )
        end
        for (name, field) in fields
            restored = InputOutput.read_field(reader, name)
            parent(field) .= parent(restored)
        end
    finally
        Base.close(reader)
    end
    return nothing
end

# Read the water tag producer's cumulative ledgers. Where the checkpoint has none
# of them, warn and keep the zeros: the receipt's header then says the ledgers
# start at zero in this segment. Some but not all is refused.
restore_water_application_ledgers!(::Nothing, reader, fields, restart_file) =
    nothing
function restore_water_application_ledgers!(meter, reader, fields, restart_file)
    present = map(((name, _),) -> haskey(reader.file, "fields/$name"), fields)
    if !any(present)
        @warn(
            "The restart file $restart_file carries none of the water tag \
            producer's ledgers. They start at zero, and the receipt marks this \
            segment's start.",
        )
        meter.ledger_start = "zero_at_restart"
        return nothing
    end
    all(present) || error(
        "The restart file $restart_file carries only part of the water tag \
        producer's ledgers. It was written with another roster. Restart with \
        the same configuration, or start a new run.",
    )
    for (name, field) in fields
        restored = InputOutput.read_field(reader, name)
        parent(field) .= parent(restored)
    end
    meter.ledger_start = "checkpoint"
    return nothing
end

# Read the negative water accumulator's fields. Where the checkpoint has none of
# them, warn and keep the zeros. Some but not all is refused, as for the others.
function restore_negative_water_accumulator!(reader, fields, restart_file)
    isempty(fields) && return nothing
    present = map(((name, _),) -> haskey(reader.file, "fields/$name"), fields)
    if !any(present)
        @warn(
            "The restart file $restart_file was written before the parent's \
            negative water accumulator was carried in a checkpoint. It starts at \
            zero for this segment, so the water audit's `negative_water_*` \
            columns cover only this segment.",
        )
        return nothing
    end
    all(present) || error(
        "The restart file $restart_file carries only part of the parent's \
        negative water accumulator. It was written by another version of the \
        accumulator. Start a new run.",
    )
    for (name, field) in fields
        restored = InputOutput.read_field(reader, name)
        parent(field) .= parent(restored)
    end
    return nothing
end
