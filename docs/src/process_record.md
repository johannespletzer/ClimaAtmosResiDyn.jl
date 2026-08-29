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

!!! note "Cumulative within a segment"

    A record accumulates from the start of the simulation segment and restarts
    at zero. A budget over an interval is therefore the difference of two
    outputs, and a time *average* of a record is not meaningful.

## Cost

A record is **not a prognostic field**. It lives in the cache, so nothing
transports it, no limiter touches it, and it adds no Jacobian block. The cost is
one field per recorded process and one broadcast per process per step, against a
difference the bracket already computed.

This is also why a record is not a tag: it is never moved by the flow, so it
says what happened in this cell, not what arrived here.

## What is not recorded

  - **Only the explicit tendency path.** The implicit path is evaluated with
    `ForwardDiff.Dual` numbers when an automatic-differentiation Jacobian is
    used, and only `p.precomputed` and `p.scratch` are converted to dual-typed
    fields. Writing a record from there would put a `Dual` into a plain-float
    cache field.

    Three labels are affected, and one of them can never be anything else.
    `precipitation` has **no explicit bracket at all** — the tendency it names
    is reached only from the implicit path — so an energy record that lists it
    is zero in every configuration. `microphysics` on the energy side is zero
    whenever microphysics is stepped implicitly, which is the default, because
    the implicit bracket covers the water half only. `microphysics` on the
    water side is zero under that same default, and is additionally a no-op
    under 1M, where `microphysics_tendency!` moves mass between species without
    changing `ρq_tot`.

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
ClimaAtmos.process_record_state_names
ClimaAtmos.process_record_from_config
ClimaAtmos.process_record_cache
ClimaAtmos.process_record_scratch
ClimaAtmos.snapshot_process_record!
ClimaAtmos.accumulate_process_record!
```
