#####
##### Process-change records
#####
##### A process record answers a different question from a tag. A tag says what
##### share of the energy or water present came from somewhere. A record says
##### what one process did to it. Gains are positive and losses negative, so a
##### record is a history and not a composition.
#####
##### Each recorded process gets one center `Field` in `p.tagging`, named
##### `prc_<process>`. The `energy_process_record` and `water_process_record`
##### config keys switch them on. The physics is written up in
##### `docs/src/process_record.md`.
#####
##### The increment a record needs is already computed. Every bracketed process
##### is wrapped in `snapshot_tags!` and `attribute_tags!`, which difference
##### `Yₜ.c.ρe_tot` and `Yₜ.c.ρq_tot` across the block. A record adds one
##### broadcast against that same difference, so it costs a field per process
##### and nothing else.
#####
##### Records are cache-resident, not prognostic. Nothing transports them,
##### nothing limits them, and they add no Jacobian block. They accumulate
##### within a simulation segment and restart at zero, which is the same
##### contract `q_tag_fix_<name>` follows.
#####
##### Only the explicit tendency path is recorded. The implicit path would need
##### to write a `ForwardDiff.Dual` into a cache field that holds plain floats,
##### which is why `microphysics` on the water side and `precipitation` on the
##### energy side are absent from a record even when they are configured. See
##### `docs/src/process_record.md`.

# ============================================================================
# Names and cache fields
# ============================================================================

# Build a single-entry NamedTuple `(; prc_<process> = value)`. As for the tags,
# the field name is computed at compile time from the type parameter, so this is
# type-stable and GPU-compatible.
@generated function record_entry(::RecordedProcess{name}, value) where {name}
    field_name = Symbol(:prc_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

# Compile-time lookup of the entry `prc_<process>` in a keyed cache NamedTuple.
@generated record_field(obj, ::RecordedProcess{name}) where {name} =
    :(obj.$(Symbol(:prc_, name)))

_record_fields(ᶜρ, ::Tuple{}) = (;)
_record_fields(ᶜρ, processes::Tuple) = merge(
    record_entry(first(processes), zero.(ᶜρ)),
    _record_fields(ᶜρ, Base.tail(processes)),
)

"""
    process_record_state_names(model::ProcessRecordModel)

`Tuple` of the cache-field `Symbol`s (`:prc_<process>`) this record holds.
"""
process_record_state_names(model::ProcessRecordModel) =
    Tuple(Symbol(:prc_, process_name(p)) for p in model.processes)

"""
    process_record_cache(Y, atmos::AtmosModel)

Cache entries used by the process records, merged into `p.tagging`; `nothing`
when neither record is configured. Contains:

  - `ᶜenergy_prc`: one center `Field` per recorded energy process, holding the
    signed `ρe_tot` increment that process has applied, keyed `prc_<process>`.
  - `ᶜwater_prc`: the same for `ρq_tot`.

Both are cumulative since the start of the simulation segment and reset on
restart, so a budget over an interval is the difference of two outputs.

These live in the cache rather than in `p.scratch` because they must survive
between timesteps. That is also why only the explicit tendency path writes to
them: `p.scratch` is converted to dual-typed fields for an automatic
differentiation Jacobian and the cache is not, so an implicit-path write would
be a `ForwardDiff.Dual` going into a `Float64` field.
"""
function process_record_cache(Y, atmos::AtmosModel)
    energy = _process_record_fields(Y, atmos.energy_process_record, :ᶜenergy_prc)
    water = _process_record_fields(Y, atmos.water_process_record, :ᶜwater_prc)
    isnothing(energy) && isnothing(water) && return nothing
    return (; _or_empty(energy)..., _or_empty(water)...)
end

_process_record_fields(Y, ::Nothing, key) = nothing
function _process_record_fields(Y, model::ProcessRecordModel, key)
    return NamedTuple{(key,)}((_record_fields(Y.c.ρ, model.processes),))
end

"""
    process_record_scratch(Y, atmos::AtmosModel)

Scratch fields the process records need, merged into `p.scratch`; empty when
neither record is configured. `ᶜprc_e_snapshot` holds `Yₜ.c.ρe_tot` from the
last [`snapshot_process_record!`](@ref) and `ᶜprc_q_snapshot` its water
counterpart.

These are separate from the tags' own snapshot buffers on purpose. A record can
be configured without any tags, and giving it its own buffers keeps the two
features independent rather than making one depend on the other being enabled.
"""
process_record_scratch(Y, atmos::AtmosModel) = (;
    (
        isnothing(atmos.energy_process_record) ? (;) :
        (; ᶜprc_e_snapshot = similar(Y.c.ρ))
    )...,
    (
        isnothing(atmos.water_process_record) ? (;) :
        (; ᶜprc_q_snapshot = similar(Y.c.ρ))
    )...,
)

# ============================================================================
# Recording
# ============================================================================

"""
    snapshot_process_record!(p, Yₜ, source::Symbol)

Record the current `Yₜ.c.ρe_tot` and `Yₜ.c.ρq_tot` in `p.scratch`, opening a
process-record bracket. A no-op for a process no record lists, and when neither
record is configured.

Paired with [`accumulate_process_record!`](@ref). Called from `snapshot_tags!`
alongside the tag snapshots, so a record needs no bracket of its own.
"""
function snapshot_process_record!(p, Yₜ, source::Symbol)
    _snapshot_energy_record!(p, Yₜ, source, p.atmos.energy_process_record)
    _snapshot_water_record!(p, Yₜ, source, p.atmos.water_process_record)
    return nothing
end

_snapshot_energy_record!(p, Yₜ, source, ::Nothing) = nothing
function _snapshot_energy_record!(p, Yₜ, source, model::ProcessRecordModel)
    _records_process(model, source) || return nothing
    p.scratch.ᶜprc_e_snapshot .= Yₜ.c.ρe_tot
    return nothing
end

_snapshot_water_record!(p, Yₜ, source, ::Nothing) = nothing
function _snapshot_water_record!(p, Yₜ, source, model::ProcessRecordModel)
    source in KNOWN_WATER_TAG_SOURCES || return nothing
    _records_process(model, source) || return nothing
    p.scratch.ᶜprc_q_snapshot .= Yₜ.c.ρq_tot
    return nothing
end

"""
    accumulate_process_record!(Yₜ, p, source::Symbol)

Close a bracket opened by [`snapshot_process_record!`](@ref): add the increment
the bracketed process applied to `ρe_tot` and `ρq_tot` to that process's record.

The increment is signed. A process that cools drives its energy record negative,
which is the point of the diagnostic.

A no-op for a process no record lists, and when neither record is configured.
"""
function accumulate_process_record!(Yₜ, p, source::Symbol)
    _accumulate_energy_record!(Yₜ, p, source, p.atmos.energy_process_record)
    _accumulate_water_record!(Yₜ, p, source, p.atmos.water_process_record)
    return nothing
end

_accumulate_energy_record!(Yₜ, p, source, ::Nothing) = nothing
function _accumulate_energy_record!(Yₜ, p, source, model::ProcessRecordModel)
    ᶜsnapshot = p.scratch.ᶜprc_e_snapshot
    ᶜΔ = @. lazy(Yₜ.c.ρe_tot - ᶜsnapshot)
    _accumulate_records!(p.tagging.ᶜenergy_prc, ᶜΔ, source, model.processes)
    return nothing
end

_accumulate_water_record!(Yₜ, p, source, ::Nothing) = nothing
function _accumulate_water_record!(Yₜ, p, source, model::ProcessRecordModel)
    source in KNOWN_WATER_TAG_SOURCES || return nothing
    ᶜsnapshot = p.scratch.ᶜprc_q_snapshot
    ᶜΔ = @. lazy(Yₜ.c.ρq_tot - ᶜsnapshot)
    _accumulate_records!(p.tagging.ᶜwater_prc, ᶜΔ, source, model.processes)
    return nothing
end

# Whether any process in this record matches `source`. Cheap, and it keeps a
# bracket for an unrecorded process from copying a whole field into scratch.
_records_process(model::ProcessRecordModel, source::Symbol) =
    any(p -> process_name(p) === source, model.processes)

_accumulate_records!(records, ᶜΔ, source, ::Tuple{}) = nothing
function _accumulate_records!(records, ᶜΔ, source, processes::Tuple)
    process = first(processes)
    if process_name(process) === source
        ᶜrecord = record_field(records, process)
        @. ᶜrecord += ᶜΔ
    end
    return _accumulate_records!(records, ᶜΔ, source, Base.tail(processes))
end
