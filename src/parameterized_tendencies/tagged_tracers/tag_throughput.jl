#####
##### The gross throughput of the tags' cache ledgers (WP6)
#####
##### The cache ledgers `q_tag_fix_<name>`, `q_tag_upfix_<name>` and
##### `e_src_fix_<name>` are signed and cumulative: a correction of `+x` and
##### then `−x` reads zero, as does none at all. Beside each, a gross twin adds
##### the absolute value of every change and a count adds one for every
##### cell-event whose change exceeds rounding. Both record what was
##### attempted: every call, including those inside a step that the stepper
##### later discards (design/GROSS_ACCUMULATORS.md on the record branch,
##### section 3.4).
#####
##### They are kept in Float64 whatever the model's float type. In Float32 a
##### sum of many small changes after a large one loses nearly all of them.

"""
    TAG_EVENT_THRESHOLD

A change counts as a cell-event where it exceeds this fraction of the cell's
total, or 16 rounding units of the total's float type if that is larger. The
copies' residual is nonzero at rounding level almost everywhere, so without a
threshold the count would approach the number of cells times calls. In Float32
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
twin or a count beside a cache ledger. `tag_entry` gives each tag family's
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
twin and its count, each a `NamedTuple` keyed like the state, and, where each
tag keeps its own state ledger (WP6, step 3), `state`, a
[`TagLedgerView`](@ref) of the state, or `nothing`.
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

The integral over the domain of the gross twins, summed over the tags, for the
audit: an amount, in the units of the ledger times volume. Collective, as
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
##### The state ledgers per mechanism, and their gross per step (WP6, step 2)
#####
##### Each correction also adds, per application, the water or energy it moved
##### over the partition's tags to a state field of its own. The stepper then
##### weights that field as it weights the tags, so it holds what the steps
##### retained. A read-only callback adds `|L − L_prev|` per step, the retained
##### gross. design/GROSS_ACCUMULATORS.md, sections 3.1, 3.2 and 9.

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
water_tag_mechanism_names(model::WaterTaggingModel) =
    _water_tag_mechanism_names(Val(has_water_tag_updraft_copies(model)))
_water_tag_mechanism_names(::Val{false}) = WATER_TAG_MECHANISM_NAMES
_water_tag_mechanism_names(::Val{true}) = WATER_TAG_ALL_MECHANISM_NAMES

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
        Val(_water_tag_mechanism_names(Val(has_water_tag_updraft_copies(model)))),
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
    name in ENERGY_SOURCE_MECHANISM_NAMES

"""
    tag_state_ledger_names(atmos)

Every state ledger of the tags that the per-step gross follows: the ledgers per
mechanism, the increment corrections' ledgers, and each tag's own ledgers where
the tags keep them (step 3), of both families.
"""
tag_state_ledger_names(atmos) = (
    water_tag_mechanism_names(atmos.water_tagging_model)...,
    _water_increment_ledger_names(atmos.water_tagging_model)...,
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

Beside them (step 3): `attempted`, per ledger that a kernel or the increment
correction writes, the sum over every call of the absolute value of what that
call added, including calls on stage values that the stepper discards;
`before`, per ledger per mechanism, the ledger kept before a call; and
`cadence`, the run's `update_constrain_state_every`, which
[`set_tag_ledger_cadence!`](@ref) sets. Each tag's own ledger of the limiters'
and the repair's corrections has no `attempted`: the cache ledger's gross twin
takes the same changes.
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
        ),
    )
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
    accumulate_tag_ledger_gross!(integrator)

After an accepted step, add each state ledger's change over the step to its
gross, per cell and per column, and remember the ledger. It reads the state and
writes only its own cache.
"""
function accumulate_tag_ledger_gross!(integrator)
    Y = integrator.u
    (; atmos) = integrator.p
    (; ledgers, ᶜdiff, coldiff) = integrator.p.tagging.tag_ledger_steps
    _accumulate_ledger_gross!(
        Y,
        ledgers,
        ᶜdiff,
        coldiff,
        _water_ledger_total(Y, atmos.water_tagging_model),
        _energy_ledger_total(Y, atmos.energy_source_tagging_model),
        Val(keys(ledgers)),
    )
    return nothing
end
# The total a change of each family's ledger counts as an event against: the
# parent's water, and the energy the energy source tags partition.
_water_ledger_total(Y, ::Nothing) = nothing
_water_ledger_total(Y, model) = Y.c.ρq_tot
_energy_ledger_total(Y, ::Nothing) = nothing
_energy_ledger_total(Y, model) = _energy_source_parent_field(Y, model.offset)
# The names are type parameters, and each field is named by a literal, so the
# callback needs no run-time symbol and allocates nothing on a column. The one
# call that has allocated, about 200 bytes, in some measurements is ClimaCore's
# `column_integral_definite!`, which the model's surface precipitation calls
# every step too.
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
`check_restart_fields` does. A checkpoint written before these ledgers holds
none of them. It is refused with its own message, since the ledgers would
otherwise start at zero partway through the run. Whether to start them at zero
with a warning instead is the owner's decision (design/GROSS_ACCUMULATORS.md,
section 8).
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
##### Step 3 (WP6): each tag's own ledgers, what was attempted beside what the
##### steps retained, the audit's report per ledger, and the accumulators
##### carried through a restart. design/GROSS_ACCUMULATORS.md on the record
##### branch, section 10.
#####

"""
    TagLedgerView{Kind}(obj)

A view of a state or tendency `obj`, such as `Y.c` or `Yₜ.c`, whose
`tag_field` for a tag is that tag's own ledger of kind `Kind` rather than the
tag: `q_tag_led_<Kind>_<name>` for a water tag and `e_src_led_<Kind>_<name>` for
an energy source tag. `Kind` is `:fix`, for the limiters' rescale and the
repair, or `:inc`, for the increment correction. A kernel that changes the tags
writes the same change into it, so each ledger follows its tag's correction.
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
    water_tag_per_tag_ledger_names(model)

Each water tag's own state ledgers, in state order, under
`water_tag_ledger_per_tag: true`, and `()` otherwise: `q_tag_led_fix_<name>`
for every tag, what the limiters' rescale and the partition repair changed it
by; and under `water_tag_transport: increment`, `q_tag_led_inc_<name>`, what
the follower moved into or out of it. Their names carry no `ρ` prefix, so no
transport operator sees them, and the tag names `led_*` are reserved.
"""
water_tag_ledger_fix_names(::Nothing) = ()
water_tag_ledger_fix_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) ?
    _prefixed_tag_names(Val(:q_tag_led_fix_), model.tags) : ()
water_tag_ledger_inc_names(::Nothing) = ()
water_tag_ledger_inc_names(model::WaterTaggingModel) =
    has_water_tag_ledger_per_tag(model) && follows_water_increment(model) ?
    _prefixed_tag_names(Val(:q_tag_led_inc_), model.tags) : ()
water_tag_per_tag_ledger_names(model) =
    (water_tag_ledger_fix_names(model)..., water_tag_ledger_inc_names(model)...)

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
`e_src_led_src_<name>` for every tag, what the sources' brackets
(`attribute_energy_source_tags!`) put into it or took out of it. The last one's
per-step gross is OD4's scale (`energy_source_throughput`).
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
    has_energy_source_ledger_per_tag(model) ?
    _prefixed_tag_names(Val(:e_src_led_src_), model.tags) : ()
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
        (
            "q_tag_led_fix_",
            "q_tag_led_inc_",
            "e_src_led_fix_",
            "e_src_led_inc_",
            "e_src_led_src_",
        ),
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

The [`TagLedgerView`](@ref) of `Yₜ.c` that the sources' brackets write each
energy source tag's change into, `e_src_led_src_<name>`, or `nothing` where the
tags keep no ledger per tag. The brackets add to the tags' tendencies, so the
ledger is a tendency too: the stepper integrates it as it integrates the tag.
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
parent scale: 2e-4, as in G3's small-tag rule. Below it a tag holds too little
for a ratio to the tag to be read, and the audit reports that ratio as not
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
    ratio for a pure region tag, whose precondition is a positive inventory. It
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
    mechanism, and at every cadence for each tag's own ledgers;
  - `<L>_attempted`, `<L>_attempted_relative`: what the writers of `L` added,
    in absolute value, over every call, including stage values the stepper
    discards. For a tag's own ledger of the limiters' and the repair's
    corrections, the cache ledger's gross twin `fix_gross`, which takes the
    same changes;
  - `<L>_events`: the number of cell-steps whose change of `L` exceeded
    rounding against the cell's total;
  - for a tag's own ledger, `<L>_inventory_fraction`, `<L>_burden_fraction`,
    `<L>_parent_fraction` and `<L>_applicable`: `<L>_retained` over the tag's
    integral now, over its absolute burden now, and over `parent_scale`, and
    whether a ratio to the tag applies ([`tag_ledger_normalization`](@ref)).

With a tag's own ledgers, `ledger_parent_scale`: `parent_scale`, the family's
parent scale, `∫ρq_tot` for the water tags and for the energy source tags
`energy_source_ledger_parent_scale`, OD4's gross source throughput. And
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
        if is_tag_per_tag_ledger_name(name)
            per_tag = true
            tag_name = chopprefix(
                chopprefix(chopprefix(short, "led_fix_"), "led_inc_"),
                "led_src_",
            )
            ᶜtag = getproperty(Y.c, Symbol(tag_prefix, tag_name))
            ratios = tag_ledger_normalization(
                retained,
                Float64(sum(ᶜtag)),
                Float64(sum(abs, ᶜtag)),
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

"""
    energy_source_throughput(Y, p, model)

OD4's scale (the owner, 2026-09-24 and 2026-09-25): the gross energy the
sources put into the energy source tags, over the domain and since the start
of the run. It is the sum over the partition's tags, the region tags without
sources, of the per-step gross of each tag's source ledger,
`Σ_steps |Δ e_src_led_src_<name>|`, integrated. The partition's tags receive
every source in full, gains by their masks and losses by their shares, so each
unit of source energy counts once; the source tags overlay it and are left out.
A window's throughput is the difference of two values. `nothing` where the
tags keep no ledger per tag. Collective, as `sum` is.
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

The tags' accumulators a checkpoint carries (WP6, step 3), as a vector of
`name => field`: the cache ledgers `ᶜwater_fix`, `ᶜwater_upfix` and
`ᶜenergy_source_fix` with their gross twins and counts, and, per state ledger,
the per-step gross, column gross, events and attempted. `ᶜprev` is not carried:
it is the ledger itself, which the state carries. Empty without tags.
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
    return fields
end

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

  - It holds none of them: it was written before they were carried. They start
    at zero with a warning. The run then begins a new accumulator segment, and
    their totals, the audit's `_retained`, `_attempted` and `_events` among
    them, cover that segment only. They are not whole-run totals.
  - It holds some but not all of them: it is refused. Another configuration of
    the tags' ledgers wrote it.
"""
function restore_tag_ledger_checkpoint!(tagging, restart_file, context)
    fields = tag_ledger_checkpoint_fields(tagging)
    isempty(fields) && return nothing
    reader = InputOutput.HDF5Reader(restart_file, context)
    try
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
