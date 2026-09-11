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
implicit residual `-ΔY`. So a record takes each bracketed increment as it is
evaluated, with no Jacobian correction. Those are the explicit brackets'
increments, and on the implicit path those of the microphysics sink and of
sedimentation. That is the intended behaviour, since no record's tendency
depends on a record.

The records have no cross blocks, though. With a single Newton iteration
(`max_newton_iters_ode: 1`), a record takes its implicit increments at the
stage's first guess, while `ρe_tot` also gets the Jacobian's coupling to other
rows. Under 0-moment microphysics that coupling does not reach the rain-out,
and a column's records add up to its change in `ρe_tot` to rounding. Under 1M
and 2M it includes sedimentation, so the two differ by a small linearised term.
On a 1M column over a day, that term tracked the precipitation record's rate
times the step, and it did not accumulate.

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

  - **A label whose process does not run.** Both tendency paths are bracketed.
    `open_applied_update!` and `close_applied_update!` call the record's
    snapshot and accumulate halves from `remaining_tendency.jl`, for a label in
    `KNOWN_TAG_SOURCES`, and `implicit_tendency.jl` brackets the records itself
    around the implicit microphysics sink and precipitation sedimentation. `Y`,
    `Yₜ`, `p.precomputed` and `p.scratch` are all dual-converted, so a record's
    snapshot and destination are both safe on the implicit path, which is
    evaluated with `ForwardDiff.Dual` numbers.

    So `microphysics` is recorded however microphysics is stepped, and under
    0-moment microphysics that is where rain leaves. Under 1M, 2M and P3 it
    records nothing, on either side: `microphysics_tendency!` moves mass
    between species without changing `ρq_tot` or `ρe_tot`, and the rain-out is
    in `precipitation`. `precipitation` names sedimentation, which 0-moment
    microphysics does not have, so a record that lists it stays zero there.

    A label that stays zero under the chosen microphysics warns at startup:
    `precipitation` under 0-moment microphysics, and `microphysics` under the
    other schemes. A record that stays zero reads
    exactly like a process that did nothing, and no analysis downstream can tell
    the two apart, so the distinction has to be drawn at the point where the run
    is configured.

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
