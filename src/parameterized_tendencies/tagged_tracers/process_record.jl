#####
##### Process-change records
#####
##### A process record answers a different question from a tag. A tag says what
##### share of the energy or water present came from somewhere. A record says
##### what one process did to it. Gains are positive and losses negative, so a
##### record is a history and not a composition.
#####
##### Each recorded process gets one center prognostic field in `Y.c`, named
##### `prc_e_<process>` for energy and `prc_q_<process>` for water. The
##### `energy_process_record` and `water_process_record` config keys switch them
##### on. The physics is written up in `docs/src/process_record.md`.
#####
##### Every bracketed process is wrapped in `snapshot_tags!` and
##### `attribute_tags!`, which difference `Yₜ.c.ρe_tot` and `Yₜ.c.ρq_tot` across
##### the block. That difference is a *rate*, so a record adds it to its own
##### tendency and lets the timestepper integrate it, exactly as the tags do.
##### Summing the rate directly would give a total that scales with the number
##### of tendency evaluations and therefore with `dt`.
#####
##### Records are prognostic but not transported. The timestepper advances them
##### and nothing else touches them: no advection, no limiter, no Jacobian block
##### beyond the fallback identity. They accumulate from the start of the run
##### and are carried through a restart, so a budget over an interval is the
##### difference of two outputs. This differs from `q_tag_fix_<name>`, which
##### lives in the cache and does restart at zero.
#####
##### Only the explicit tendency path is recorded, because that is the only
##### path with a bracket: `snapshot_tags!` and `attribute_tags!` are called
##### from `remaining_tendency.jl` and nowhere else. So `precipitation` never
##### reaches a record at all, its only bracket being on the implicit path, and
##### `microphysics` reaches one only when it is stepped explicitly. Both stay
##### zero otherwise, even when configured.
#####
##### Note this is no longer a type restriction. While records lived in the
##### cache, the implicit path could not write one because it is evaluated with
##### `ForwardDiff.Dual` numbers. Now that a record is prognostic, both its
##### snapshot (`p.scratch`) and its destination (`Yₜ`) are dual-converted, so
##### extending it to the implicit path only needs brackets there. See
##### `docs/src/process_record.md`.

# ============================================================================
# Names and state fields
# ============================================================================

# Build a single-entry NamedTuple `(; prc_e_<process> = value)` for energy and
# `(; prc_q_<process> = value)` for water. As for the tags, the field name is
# computed at compile time from the type parameter, so this is type-stable and
# GPU-compatible.
#
# The missing `ρ` in these prefixes is deliberate and load-bearing. A record
# holds a density-weighted quantity (J/m³, kg/m³), so `ρprc_e_radiation` would
# be the honest name — but `gs_tracer_names` discovers grid-scale tracers with
# the purely lexical test `startswith(string(name), "ρ")`, and its docstring
# notes that adding such a field to the state is all it takes to opt into the
# advection, diffusion and hyperdiffusion loops. A record must stay out of all
# of them, because transport is one of the things it exists to be separate
# from. Do not "fix" the name.
@generated function energy_record_entry(
    ::RecordedProcess{name},
    value,
) where {name}
    field_name = Symbol(:prc_e_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end
@generated function water_record_entry(
    ::RecordedProcess{name},
    value,
) where {name}
    field_name = Symbol(:prc_q_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

# Compile-time lookup of `prc_e_<process>` / `prc_q_<process>` in a state or
# tendency `Field` (e.g. `Yₜ.c`).
@generated energy_record_field(obj, ::RecordedProcess{name}) where {name} =
    :(obj.$(Symbol(:prc_e_, name)))
@generated water_record_field(obj, ::RecordedProcess{name}) where {name} =
    :(obj.$(Symbol(:prc_q_, name)))

_energy_record_variables(ρe_tot, ::Tuple{}) = (;)
_energy_record_variables(ρe_tot, processes::Tuple) = merge(
    energy_record_entry(first(processes), zero(ρe_tot)),
    _energy_record_variables(ρe_tot, Base.tail(processes)),
)
_water_record_variables(ρq_tot, ::Tuple{}) = (;)
_water_record_variables(ρq_tot, processes::Tuple) = merge(
    water_record_entry(first(processes), zero(ρq_tot)),
    _water_record_variables(ρq_tot, Base.tail(processes)),
)

"""
    energy_process_record_variables(ρe_tot, energy_process_record)

NamedTuple of energy-record prognostic fields `(; prc_e_<process₁> = ..., ...)`
for a single grid point, to be splatted into the center prognostic state
alongside the other grid-scale variables. Returns `(;)` when the record is
disabled (`energy_process_record === nothing`).

Every record starts at zero. It is a history of what a process has done since
the run began, not a share of what is present, so there is nothing to
partition at `t = 0`.
"""
energy_process_record_variables(ρe_tot, ::Nothing) = (;)
energy_process_record_variables(ρe_tot, model::ProcessRecordModel) =
    _energy_record_variables(ρe_tot, model.processes)

"""
    water_process_record_variables(ρq_tot, water_process_record)

NamedTuple of water-record prognostic fields `(; prc_q_<process₁> = ..., ...)`
for a single grid point. The water counterpart of
[`energy_process_record_variables`](@ref); starts at zero for the same reason.
"""
water_process_record_variables(ρq_tot, ::Nothing) = (;)
water_process_record_variables(ρq_tot, model::ProcessRecordModel) =
    _water_record_variables(ρq_tot, model.processes)

"""
    energy_process_record_state_names(model::ProcessRecordModel)

`Tuple` of the prognostic-field `Symbol`s (`:prc_e_<process>`) this energy
record adds to `Y.c`.
"""
energy_process_record_state_names(model::ProcessRecordModel) =
    Tuple(Symbol(:prc_e_, process_name(p)) for p in model.processes)

"""
    water_process_record_state_names(model::ProcessRecordModel)

`Tuple` of the prognostic-field `Symbol`s (`:prc_q_<process>`) this water
record adds to `Y.c`.
"""
water_process_record_state_names(model::ProcessRecordModel) =
    Tuple(Symbol(:prc_q_, process_name(p)) for p in model.processes)

"""
    process_record_scratch(Y, atmos::AtmosModel)

Scratch fields the process records need, merged into `p.scratch`; empty when
neither record is configured. `ᶜprc_e_snapshot` holds `Yₜ.c.ρe_tot` from the
last [`snapshot_process_record!`](@ref) and `ᶜprc_q_snapshot` its water
counterpart.

These are separate from the tags' own snapshot buffers on purpose. A record can
be configured without any tags, and giving it its own buffers keeps the two
features independent rather than making one depend on the other being enabled.

Only the explicit tendency path is bracketed, so nothing here is ever written
with a `ForwardDiff.Dual`.
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
    _accumulate_records!(
        energy_record_field,
        Yₜ.c,
        ᶜΔ,
        source,
        model.processes,
    )
    return nothing
end

_accumulate_water_record!(Yₜ, p, source, ::Nothing) = nothing
function _accumulate_water_record!(Yₜ, p, source, model::ProcessRecordModel)
    source in KNOWN_WATER_TAG_SOURCES || return nothing
    ᶜsnapshot = p.scratch.ᶜprc_q_snapshot
    ᶜΔ = @. lazy(Yₜ.c.ρq_tot - ᶜsnapshot)
    _accumulate_records!(water_record_field, Yₜ.c, ᶜΔ, source, model.processes)
    return nothing
end

# Whether any process in this record matches `source`. Cheap, and it keeps a
# bracket for an unrecorded process from copying a whole field into scratch.
_records_process(model::ProcessRecordModel, source::Symbol) =
    any(p -> process_name(p) === source, model.processes)

# `ᶜΔ` is a difference of two tendencies, so it is a rate. Adding it to the
# record's own tendency hands the integration to the timestepper, which weights
# every stage correctly. Accumulating it into a plain field instead would sum
# rates and give a total proportional to the number of tendency evaluations.
# `field_of` selects the family's `@generated` accessor and is a singleton, so
# passing it costs nothing at run time.
_accumulate_records!(field_of, ᶜYₜ, ᶜΔ, source, ::Tuple{}) = nothing
function _accumulate_records!(field_of, ᶜYₜ, ᶜΔ, source, processes::Tuple)
    process = first(processes)
    if process_name(process) === source
        ᶜrecordₜ = field_of(ᶜYₜ, process)
        @. ᶜrecordₜ += ᶜΔ
    end
    return _accumulate_records!(
        field_of,
        ᶜYₜ,
        ᶜΔ,
        source,
        Base.tail(processes),
    )
end
