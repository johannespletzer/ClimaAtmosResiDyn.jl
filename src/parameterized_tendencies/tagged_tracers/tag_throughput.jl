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
total. The copies' residual is nonzero at rounding level almost everywhere, so
without a threshold the count would approach the number of cells times calls.
"""
const TAG_EVENT_THRESHOLD = 1e-12

"""
    tag_event(change, total)

`1` where `change` is more than rounding against the cell's `total`, else `0`,
as a `Float64`.
"""
@inline tag_event(change, total) =
    abs(change) > TAG_EVENT_THRESHOLD * abs(total) ? 1.0 : 0.0

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
for the audit. Collective.
"""
function tag_event_total(fields)
    isempty(fields) && return 0.0
    total = 0.0
    for ᶜfield in values(fields)
        total += sum(parent(ᶜfield))
    end
    buffer = [total]
    ClimaComms.allreduce!(ClimaComms.context(first(values(fields))), buffer, +)
    return buffer[1]
end
