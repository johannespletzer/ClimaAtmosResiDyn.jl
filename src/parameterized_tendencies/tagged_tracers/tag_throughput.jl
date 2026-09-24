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
    tag_ledger(fix, gross, count)

The three fields a correction writes for each tag: the signed ledger `fix`, its
gross twin and its count. Each is a `NamedTuple` keyed like the state.
"""
tag_ledger(fix, gross, count) = (; fix, gross, count)

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
mechanism and the increment corrections' ledgers, of both families.
"""
tag_state_ledger_names(atmos) = (
    water_tag_mechanism_names(atmos.water_tagging_model)...,
    _water_increment_ledger_names(atmos.water_tagging_model)...,
    energy_source_mechanism_names(atmos.energy_source_tagging_model)...,
    _energy_increment_ledger_names(atmos.energy_source_tagging_model)...,
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
the sum over the steps of `|L − L_prev|`; and `colgross`, the sum over the
steps of `|∫(L − L_prev) dz|` per column. `ᶜdiff` and `coldiff` are scratch.
`(;)` without state ledgers.
"""
function tag_ledger_step_cache(Y, atmos)
    names = tag_state_ledger_names(atmos)
    isempty(names) && return (;)
    ᶜdiff = _throughput_field(Y.c.ρ)
    coldiff = Fields.Field(Float64, axes(Fields.level(Y.f.u₃, half)))
    fill!(parent(coldiff), 0)
    ledgers = NamedTuple{names}(map(names) do name
        ᶜprev = _throughput_field(Y.c.ρ)
        ᶜprev .= getproperty(Y.c, name)
        colgross = similar(coldiff)
        fill!(parent(colgross), 0)
        (; ᶜprev, ᶜgross = _throughput_field(Y.c.ρ), colgross)
    end)
    return (; tag_ledger_steps = (; ledgers, ᶜdiff, coldiff))
end

"""
    accumulate_tag_ledger_gross!(integrator)

After an accepted step, add each state ledger's change over the step to its
gross, per cell and per column, and remember the ledger. It reads the state and
writes only its own cache.
"""
function accumulate_tag_ledger_gross!(integrator)
    Y = integrator.u
    (; ledgers, ᶜdiff, coldiff) = integrator.p.tagging.tag_ledger_steps
    _accumulate_ledger_gross!(Y, ledgers, ᶜdiff, coldiff, Val(keys(ledgers)))
    return nothing
end
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
    ::Val{names},
) where {names}
    each = map(names) do name
        quote
            let ᶜL = Y.c.$name, ledger = ledgers.$name
                @. ᶜdiff = ᶜL - ledger.ᶜprev
                @. ledger.ᶜgross += abs(ᶜdiff)
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
