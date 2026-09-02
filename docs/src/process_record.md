# Process-Change Records

A process record answers a different question from a tag.

  - A **tag** says what share of the energy or water present here came from
    somewhere. See [Tagged Water Tracers](tagged_water.md) and
    [Tagged Energy Tracers](tagged_tracers.md).
  - A **record** says what one process did to it. Gains are positive, losses
    negative, and the two cancel.

The distinction matters because the two cannot be read off each other. An
amount that has been transported here is not a history of what happened here,
and a running total of gains and losses is not a composition of what is present.

Each recorded process adds one field per grid cell, output as
`e_prc_<process>` for moist energy and `q_prc_<process>` for total water.

## Enabling records

```yaml
energy_process_record: [radiation, surface_flux, held_suarez]
water_process_record: [surface_flux]
```

The entry takes the same shape as a tag's `source`: one process label, a list of
them, or a group name that expands to its members. The labels are exactly the
`source` labels of the energy and water tags, listed in
[Configuring Tracers](tracer_configuration.md), so `all` works here too. An
unknown label is refused at startup.

Both keys are off by default and cost nothing when off. `water_process_record`
needs `microphysics_model: "0M"` or `"1M"`, like the water tags.

Records are independent of the tags. Either key works with no tags configured at
all.

## What a record holds

Every attributed process is already wrapped in a bracket that differences
``\rho e_\mathrm{tot}`` and ``\rho q_\mathrm{tot}`` across the block. A record
accumulates that same difference:

```math
\mathrm{prc}_p \mathrel{+}= \Delta_p (\rho e_\mathrm{tot}),
```

so after some time `prc_p` is the net amount that process `p` has added since
the record started. Nothing is masked and nothing is split by sign, which is
what makes it a record rather than an attribution.

The output is divided by the current density, so `e_prc_<process>` is in
J kg⁻¹ and `q_prc_<process>` in kg kg⁻¹. Each increment was accumulated at its
own step's density, so this is not exactly the sum of the per-step specific
increments — the same caveat `q_tag_fix_<name>` carries.

!!! note "Cumulative, and carried across a restart"

    A record accumulates from the start of the run, and keeps its value through
    a restart. A budget over an interval is therefore the difference of two
    outputs, and a time *average* of a record is not meaningful.

    This is **not** the `q_tag_fix_<name>` contract. That one lives in the cache
    and does restart at zero, so a budget spanning a restart cannot be recovered
    from it. A record can, because it is prognostic and travels in the
    checkpoint.

## How the record is integrated

The bracket does not hand a record an amount. `snapshot_process_record!` copies
`Yₜ.c.ρe_tot` and `accumulate_process_record!` differences it, so what the
bracket yields is a difference of two *tendencies* — a rate, in J m⁻³ s⁻¹.

Turning a rate into an amount is integration, and the only thing that can do it
correctly here is the timestepper, which knows each stage's weight. So a record
adds the rate to its own tendency and is advanced like any other prognostic
variable. Summing the rate directly would give a total proportional to the
number of tendency evaluations, and therefore to `dt`; multiplying by `dt` by
hand would be right only for a single-stage explicit method and would misweight
the IMEX schemes actually in use.

## Cost

A record **is** a prognostic field, but it is not a tracer. Its name carries no
`ρ` prefix, and `gs_tracer_names` discovers grid-scale tracers by exactly that
lexical test, so nothing advects, diffuses, hyperdiffuses, sponges or limits a
record. It needs no hand-written Jacobian block either: `jacobian_cache`
completes the matrix with `fallback_identity_blocks`, giving these variables the
implicit residual `-ΔY`, so only the explicit tendency contributes — which is
precisely the intended behaviour.

The cost is one center field per recorded process in `Y`, and one broadcast per
process per tendency evaluation against a difference the bracket already
computed.

!!! warning "Do not add the missing `ρ`"

    A record holds a density-weighted quantity, so `ρprc_e_radiation` looks like
    the correct name. It is not. That prefix is the whole of what
    `gs_tracer_names` tests, and adding it would silently opt the record into
    every transport loop — destroying the property the record exists for. A test
    asserts the prefix is absent.

This is also why a record is not a tag: it is never moved by the flow, so it
says what happened in this cell, not what arrived here.

## What is not recorded

  - **Only the explicit tendency path**, because that is the only path with a
    snapshot/attribute bracket. `snapshot_tags!` and `attribute_tags!` are
    called from `remaining_tendency.jl` and nowhere else.

    This limit used to be a type barrier as well: a cache-resident record could
    not be written from the implicit path, which is evaluated with
    `ForwardDiff.Dual` numbers, because the cache holds plain floats. That
    barrier is gone. `Y`, `Yₜ`, `p.precomputed` and `p.scratch` are all
    dual-converted, so a prognostic record's snapshot and destination are both
    dual-safe. Extending the record to the implicit path is now a matter of
    adding brackets there, not of finding somewhere type-safe to write.

    Three labels are affected, and one of them can never be anything else.
    `precipitation` has **no explicit bracket at all** — the tendency it names
    is reached only from the implicit path — so an energy record that lists it
    is zero in every configuration. `microphysics` on the energy side is zero
    whenever microphysics is stepped implicitly, which is the default, because
    the implicit bracket covers the water half only. `microphysics` on the
    water side is zero under that same default, and is additionally a no-op
    under 1M, where `microphysics_tendency!` moves mass between species without
    changing `ρq_tot`.

    Configuring any of these labels warns at startup. A record that stays zero
    reads exactly like a process that did nothing, and no analysis downstream
    can tell the two apart, so the distinction has to be drawn at the point
    where the run is configured.

  - **Transport, phase changes, gravity-wave drag and numerical corrections**
    have no bracket to record, so they are absent entirely. A record covers the
    processes in `KNOWN_TAG_SOURCES` and `KNOWN_WATER_TAG_SOURCES` and nothing
    else.

Both limits matter for interpretation: the records of a run do **not** sum to
the change in the parent variable, and were never intended to. They are a
per-process history over the processes that are bracketed, not a closed budget
of the model.

## Interpretation limit

A record says what a process applied inside this model, under this
configuration, with this process grouping. It is not a counterfactual: it does
not say what would have happened had the process been absent, because the other
processes would have responded. Splitting one physical process into two
bracketed steps, or merging two, changes the records without changing the
simulation.

## API

```@docs
ClimaAtmos.ProcessRecordModel
ClimaAtmos.RecordedProcess
ClimaAtmos.process_name
ClimaAtmos.energy_process_record_variables
ClimaAtmos.water_process_record_variables
ClimaAtmos.energy_process_record_state_names
ClimaAtmos.water_process_record_state_names
ClimaAtmos.process_record_from_config
ClimaAtmos.warn_inactive_record_labels
ClimaAtmos.process_record_scratch
ClimaAtmos.snapshot_process_record!
ClimaAtmos.accumulate_process_record!
```
