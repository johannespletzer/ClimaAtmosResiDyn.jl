#####
##### Process-change records
#####
##### A record says what one process did, not where the energy or water present
##### came from. Each recorded process is one center field in `Y.c`, named
##### `prc_e_<process>` for energy and `prc_q_<process>` for water.
##### An applied-update event around a process differences `Yₜ.c.ρe_tot` and
##### `Yₜ.c.ρq_tot`, which gives the process's tendency. A record adds that
##### tendency to its own, and the timestepper integrates it. Records are prognostic but not transported, and
##### they are carried through a restart. See `docs/src/process_record.md`.

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

The implicit path has the same events, so these can hold `ForwardDiff.Dual`
numbers, which is why they live in `p.scratch`: it is dual-converted.
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

Record the current `Yₜ.c.ρe_tot` and `Yₜ.c.ρq_tot` in `p.scratch`, opening an
applied-update event for the process. A no-op for a process no record lists, and when neither
record is configured.

Paired with [`accumulate_process_record!`](@ref). On the explicit path it is
called from `snapshot_tags!` alongside the tag snapshots. On the implicit path
`implicit_tendency.jl` calls it directly, around the microphysics sink and
precipitation sedimentation.
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

Close the applied-update event opened by [`snapshot_process_record!`](@ref).
Add the process's tendency of `ρe_tot` and `ρq_tot` to that process's record.

The tendency is signed. A process that cools drives its energy record negative,
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

# Whether any process in this record matches `source`. Cheap, and it keeps an
# event for an unrecorded process from copying a whole field into scratch.
_records_process(model::ProcessRecordModel, source::Symbol) =
    any(p -> process_name(p) === source, model.processes)

# `ᶜΔ` is a difference of two tendencies, so it is the process's tendency. Adding it to the
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
