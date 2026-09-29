# Process-Change Records

`energy_process_record` and `water_process_record` add one field per recorded
process. Each field accumulates the signed change that process made at each
grid point. Both keys are off by default and cost nothing when off. The records
do not change the simulation. Every model field is bit for bit what it would be
without them.

A record answers a different question from a tag.

  - A **tag** says what share of the energy or water present here came from
    somewhere. See [Tagged Water Tracers](tagged_water.md) and
    [Tagged Energy Tracers](tagged_tracers.md).
  - A **record** says what one process did to it. Gains are positive, losses
    negative, and the two cancel.

The two cannot be read off each other. An amount that has been transported here
is not a history of what happened here, and a running total of gains and losses
is not a composition of what is present. A record is never transported, so it
says what happened in this cell, not what arrived here. That also separates it
from a process tag, an `energy_tracers` entry with a `source`, which is
transported.

Each recorded process adds one field per grid cell, output as `e_prc_<process>`
for moist energy and `q_prc_<process>` for total water.

## Enabling records

```yaml
energy_process_record: [radiation, surface_flux, held_suarez]
water_process_record: [surface_flux]
```

The entry takes the same shape as a tag's `source`: one process label, a list of
them, or a group name that expands to its members. The labels are the `source`
labels of the energy and water tags, listed in
[Configuring Tracers](tracer_configuration.md), so `all` works here too. An
unknown label is refused at startup. `water_process_record` needs
`microphysics_model: "0M"` or `"1M"`, like the water tags. Either key works
with no tags configured.

## What a record holds

Every attributed process is wrapped in a bracket that differences
``\rho e_\mathrm{tot}`` and ``\rho q_\mathrm{tot}`` across the block. A record
accumulates that same difference:

```math
\mathrm{prc}_p \mathrel{+}= \Delta_p (\rho e_\mathrm{tot}),
```

so after some time `prc_p` is the net amount that process `p` has added since
the record started. Nothing is masked and nothing is split by sign.

The output is divided by the current density, so `e_prc_<process>` is in
J kg⁻¹ and `q_prc_<process>` in kg kg⁻¹. Each increment is accumulated at its
own step's density, so this is not exactly the sum of the per-step specific
increments.

!!! note "Cumulative, and carried across a restart"

    A record accumulates from the start of the run, and keeps its value through
    a restart, because it is a prognostic field and travels in the state. The
    change over an interval is the difference of two outputs, and a time
    *average* of a record is not meaningful.

    A restart must configure the same records. A restart whose `prc_e_*` or
    `prc_q_*` fields differ from the configuration is refused before the run is
    built.

The bracket yields a difference of two *tendencies*, so it is a rate, in
J m⁻³ s⁻¹. A record adds the rate to its own tendency, and the timestepper
integrates it with each stage's weight, as for any prognostic variable. Summing
the rate directly would give a total proportional to `dt`.

## Not transported

A record is a prognostic field but not a tracer. Its name carries no `ρ`
prefix, and the tracer loops (`gs_tracer_names`, the horizontal advection and
the SEM limiter) select fields by that prefix. So nothing advects, diffuses,
hyperdiffuses, sponges or limits a record.

!!! warning "Do not add the missing `ρ`"

    A record holds a density-weighted quantity, so `ρprc_e_radiation` looks like
    the correct name. It is not. Adding the prefix would opt the record into
    every transport loop. A test asserts the prefix is absent.

A record gets the fallback identity Jacobian block, so it takes each
bracketed increment as it is evaluated. That is right for its own row, since no
record's tendency depends on a record. It has no cross blocks. With a single
Newton iteration (`max_newton_iters_ode: 1`), a record takes its implicit
increments at the stage's first guess, while `ρe_tot` also gets the Jacobian's
coupling to other rows. Under 0-moment microphysics that coupling does not
reach the rain-out. Under 1M and 2M it includes sedimentation, so the records
and `ρe_tot` differ by a small linearised term.

The cost is one center field per recorded process, and one broadcast per
process per tendency evaluation.

## What is not recorded

  - **A label whose process does not run.** Both tendency paths are bracketed,
    the explicit one from `remaining_tendency.jl` and the implicit one from
    `implicit_tendency.jl`, around the microphysics sink and precipitation
    sedimentation. So `microphysics` is recorded however microphysics is
    stepped, and under 0-moment microphysics that is where rain leaves. Under
    1M, 2M and P3 it records nothing, because `microphysics_tendency!` moves
    mass between species without changing `ρq_tot` or `ρe_tot`. The rain-out is
    in `precipitation`, which names sedimentation and so stays zero under
    0-moment microphysics.

    A label that stays zero under the chosen microphysics warns at startup.
    A record that stays zero reads exactly like a process that did nothing, so
    the distinction is drawn when the run is configured.

  - **Transport, phase changes, gravity-wave drag and numerical corrections**
    have no bracket to record, so they are absent. A record covers the
    processes in `KNOWN_TAG_SOURCES` and `KNOWN_WATER_TAG_SOURCES` and nothing
    else.

At a point, the records do not sum to the change in the parent variable,
because transport moves the parent and has no record. In a column model
transport only moves energy between levels. With a record for every process
that changes the column's energy, they add up to its change in `ρe_tot`. That
holds to rounding under 0-moment microphysics, and up to the linearised term
under the other schemes.

## Interpretation limit

A record says what a process applied inside this model, under this
configuration, with this process grouping. It is not a counterfactual: it does
not say what would have happened had the process been absent, because the other
processes would have responded. Splitting one physical process into two
bracketed steps, or merging two, changes the records without changing the
simulation.

## Process record API

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
