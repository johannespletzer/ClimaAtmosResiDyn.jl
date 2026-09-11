# Energy Source Tags and Process Records: a User's Guide

*Draft of 2026-09-11, written against `claude/tag-closure-experiments` at
`17badbe7`, and brought up to FINDINGS E41 the same day. It is meant for
`docs/src/`, so its links are relative to that directory. Moving it there is
the owner's call. Both features are experimental. This page says how to use them and how far to
trust what they write. [Energy Source Tags](energy_source_tags.md) and
[Process-Change Records](process_record.md) say how they work. The numbers
quoted here come from the tag-closure series, `experiments/tag_closure/FINDINGS.md`,
and each carries its entry, such as E34.*

## Two questions, two diagnostics

| you want to know | use | output |
|:-- |:-- |:-- |
| how much of the energy here now came from a region or a process | `energy_source_tags` | `e_src_<name>`, in J/kg |
| what a process has done to the energy here | `energy_process_record` | `e_prc_<process>`, in J/kg |
| the same for total water | `water_process_record` | `q_prc_<process>`, in kg/kg |

The two answer different questions, and neither can be read off the other.

  - A **tag** moves with the air. It holds an amount of energy that is present
    now, labelled by where it entered.
  - A **record** stays where its process acted. It holds the signed sum of what
    that process added there. Gains are positive and losses negative.

So after a day, a radiation tag shows where radiatively gained energy has gone
to. The radiation record shows where radiation heated and cooled. They are not
the same field and should not be differenced.

The `energy_tracers` family, with fields `ρe_tag_<name>`, is a third thing, a
signed process tag that moves. This page does not cover it. See
[Tagged Energy Tracers](tagged_tracers.md).

## Where they can be used today

| configuration | energy source tags | energy records |
|:-- |:-- |:-- |
| 0M or 1M, no EDMF | yes. 0M measured on a column and a sphere, 1M on a warm column, a day each | yes |
| dry, no EDMF | yes, by the code. Not measured for this family | yes |
| 2M, no EDMF | no. The model itself disables 2M on this branch, pending a CloudMicrophysics fix (`src/cache/precomputed_quantities.jl:160-167`). By the code, the tags need nothing beyond 1M once it returns | no |
| 2MP3 (P3 ice) | no. Disabled with 2M, and its sedimentation has further gaps behind that | no |
| `turbconv: edonly_edmfx` | should run, by the code; not yet tried. The eddy diffusion moves the tags as plain tracers | yes |
| `turbconv: prognostic_edmfx`, `edmfx_vertical_diffusion: true` (every shipped EDMF config) | no. The run fails with `type NamedTuple has no field e_src_<name>`. The updraft diffusion asks for a tag field the updraft does not carry | yes |
| `turbconv: prognostic_edmfx`, `edmfx_vertical_diffusion: false` | should run, by the code; not yet stepped. The tags miss the sub-grid mass flux and the sedimentation corrections, so do not read `e_src_res` there as the tags' closure | yes |

Nothing refuses these configurations at startup today. A design to refuse or
support them is with the owner.

`water_process_record`, like the water tags, needs `microphysics_model: "0M"`
or `"1M"`. It is refused otherwise.

## Setting up

### A minimal block

```yaml
energy_source_tags:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
energy_source_tag_offset: 110495.0
energy_source_closure_check:
  period: "1hours"
```

  - Each tag needs a unique `name`, and a `region`, a `source`, or both. The name
    `res` is reserved.
  - A tag with a region and no source is a **region tag**. The region tags must
    form one partition: their masks must add up to 1 everywhere. The model warns
    at startup when they do not.
  - A tag with a source starts at zero and collects only what its processes
    add. It is an **overlay**, not part of the partition.
  - The regions and the process labels are listed in
    [Configuring Tracers](tracer_configuration.md).
  - Every key is off by default and costs nothing when off.

### Choose an offset

Always set `energy_source_tag_offset` for this family.

Moist total energy has no physical zero. Under the model's reference,
`ρe_tot` is negative over much of a moist atmosphere: 43% of a moist sphere's
volume, holding 78% of its `∫|ρe_tot|` (E1, E9b), and all of a DYCOMS column at
startup. A tag's share of the total is undefined where the total is not
positive. There the loss half of the rule does not run.

With an offset `c`, in J/kg, the tags split `E = ρe_tot + c·ρ` instead. The
model never sees `E`, so the simulated atmosphere is the same to the last bit
(E17).

  - **Size.** `c` must make `E` positive everywhere. The smallest value that did
    was 45.4 kJ/kg on the DYCOMS column and 100.4 kJ/kg on a moist sphere (E6).
    The series uses 110,495 J/kg for both. If the startup warning reports a
    non-positive fraction, raise `c`.
  - **Price.** The shares depend on `c`, as they depended on the reference. A
    larger `c` makes a source tag less distinct from a plain mask. Doubling `c`
    moved the surface tag by about 1% over a day (E19).
  - **Required** for `energy_source_tag_transport: enthalpy`, which refuses to
    start without it. Recommended wherever condensate falls: without an offset
    the tags do not follow the falling water where `E` is not positive, and the
    model warns at startup.

### Keep the repair on

`energy_source_tag_repair` is on by default. After each step it puts negative
tags back, wherever `E` is positive.

  - The region tags keep their sum. A negative one is set to zero, and the
    positive ones give up the deficit in proportion.
  - An overlay is clipped at zero. That adds energy the other tags do not lose.
  - Every change goes into the ledger `e_src_fix_<name>`.

The ledger is exact at the default `update_constrain_state_every: step`. Switch
the repair off only to measure what it does. Without it the tags go negative,
on a sphere by thousands of J/kg for the region tags (E14, E27), and a negative
tag has no meaning as an amount.

### Choose the transport

`energy_source_tag_transport` takes `tracer`, the default, or `enthalpy`.

  - **`tracer`** moves each tag as a passive tracer. The model moves `ρe_tot` as
    enthalpy. The difference is pressure work, and it is what `e_src_res` grows
    by: all of the growth on a column after its first ten minutes (E25), and at
    least 93% on a sphere (E31).
  - **`enthalpy`** is an audit. In vertical and horizontal advection and in
    hyperdiffusion, each tag takes its share of the model's own flux of `E`. So
    transport stops adding to `e_src_res` (E34). The shares are taken first order
    from the upwind cell, so a region's edge smears more. It costs about 5% per
    step (E34).

Run the audit as a pair: the same configuration with `tracer` and with
`enthalpy`. The difference between their residuals is what transport adds.

### Add process records

```yaml
energy_process_record: [radiation, surface_flux, microphysics]
water_process_record: [surface_flux]
```

A record takes one label, a list, or a group such as `all`. Records work with
or without tags. Not every label records something in every configuration:

| label | energy record | energy source tag with this `source` |
|:-- |:-- |:-- |
| `radiation`, `surface_flux`, `held_suarez`, `large_scale_advection`, `subsidence`, `external_forcing` | when the process runs | when the process runs |
| `microphysics` | under 0M, the rain-out. Under 1M, 2M and P3 it stays zero, because the microphysics there moves water between species and never changes `ρe_tot` | the same |
| `precipitation` | sedimentation of the falling species. Zero under 0M, which has none | never. The tags follow sedimentation as transport. The startup warns |

Under 1M and 2M the rain-out therefore appears in `e_prc_precipitation`, not in
`e_prc_microphysics`. On the water side, `q_prc_microphysics` is zero under 1M
for the same reason.

A zero record reads exactly like a process that did nothing. Check the table
before trusting a zero.

## Three layouts that work

**Monitoring.** One partition, an offset, the repair on, `tracer`, an hourly or
daily closure check, and a record for each process you care about. This is the
cheapest layout that still says when the tags stop meaning something.

**Validating a new configuration.** Use the layout of the series' runs, for
example `experiments/tag_closure/configs/c8_column_1m.yml`:

  - the region tags, say `strat` and `tropo`;
  - one overlay per region with `source: all`, say `new_strat` and
    `new_tropo`. It collects every process's new energy in that region;
  - one overlay per process that runs, say `rad`, `sfc`, `sub`;
  - a record for each of those processes;
  - `audit: true` in the closure check, and `rhoa` and `ta` on a column.

This layout makes the per-process checks below possible. If a process runs and
has no tag, form A shows it. That is how the series found subsidence (E20) and
the rain-out of cold condensate (E28).

**Splitting the residual.** The validating layout twice, with `tracer` and with
`enthalpy`.

## What to write out

| name | units | what it is |
|:-- |:-- |:-- |
| `e_src_<name>` | J/kg | the tag's energy per unit mass |
| `e_src_fix_<name>` | J/kg | energy the repair has moved into (positive) or out of (negative) the tag. Cumulative since the start of the run segment, and reset on restart |
| `e_src_res` | J/kg | `(E - Σ region tags) / ρ`, with `E = ρe_tot + c·ρ` |
| `e_prc_<process>` | J/kg | what the process has added since the run started. Carried through a restart |
| `q_prc_<process>` | kg/kg | the same for total water |
| `energy_source_tag_closure.csv` | | the closure table, one row per check |
| `energy_source_tag_audit.csv` | | with `audit: true`, the residual split by direction |

  - Sample instantaneously. Records and ledgers are running sums, so a time
    average of one is meaningless. A budget over an interval is the difference
    of two samples.
  - On a column, add `rhoa`. The column integrals of the records need it.
  - Add `ta` to one run of a pair. The model never reads the tags, so `ta` must
    be identical in both runs. That checks that nothing else changed.
  - `output_default_diagnostics: false` keeps the output to what you list.

## How to read the output

### A tag

A tag is an amount of energy traced to where it entered. That reading holds only
where `E` is positive and the tag is not negative. With a large enough offset
and the repair on, that is everywhere.

  - **Production goes by mask, loss by share.** New energy is labelled by where
    it entered. Energy that leaves is taken from every tag in proportion to what
    it holds.
  - **A source tag cannot show where its process removed energy.** Where
    radiation cools most on the DYCOMS column, the radiation tag holds
    0.004 J/kg while the radiation record reads −20,566 J/kg (E22). The loss is
    taken from whatever energy is there, and radiation added almost none of it.
    To see cooling, read the record.
  - **Falling ice carries provenance upward.** Ice at 250 K has an internal
    energy of about −382 kJ/kg under the model's reference. With its
    geopotential and the offset added, that stays negative through the
    troposphere. So where ice falls from one cell into the one below, the lower
    cell loses `E` and the upper cell gains it. So the tags pass energy upward, taken from the lower
    cell's shares. This keeps the tags closed and non-negative. It is
    accounting, not a path the air took. Across a vertical region boundary, the
    lower region's tag moves up while snow falls.
  - **The tags are grid-scale only.** No updraft carries its own tags.

### The closure residual

`e_src_res` is `E` minus the sum of the region tags, per unit mass. It is a
monitored residual, not a machine-precision identity, and it is not a ratio.

  - It covers the region tags only. An overlay going negative, or a region error
    cancelled by an opposite one, does not show in it.
  - Under `tracer` it grows with pressure work, as above. Under `enthalpy` it
    stops growing after the first hour (E34). The first hour's residual comes
    from the stepper's single Newton iteration during the initial adjustment.
    On the column a converged solve removes 99% of it (E39). After that, what
    is left is the terms the tags still take as tracers: vertical diffusion,
    the sponges and the sub-grid closures.
  - Processes that change `ρ` without a bracket, such as vertical diffusion of
    water, move `E` by `c` times that change, and the difference lands here.
  - Under `prognostic_edmfx` it also holds the whole sub-grid mass flux of
    energy, and the sedimentation corrections between updraft and environment.
    The tags see neither.
  - The repair keeps the partition's sum, so the residual is the same with the
    repair on or off (E35).

The closure table reduces `e_src_res` to numbers. `gross_relative`, compared
against the tolerance, is `∫|E - Σ tags|` over `∫|E|`. That denominator grows
with the offset, so a larger `c` reads as a smaller relative residual for the
same miss (E15). Across runs with different offsets, compare `gross_residual`,
not `gross_relative`. The energy families have no default `abort_above`. Set one
once a first run shows where your configuration settles.

### The repair's ledger

  - For the region tags the ledgers add up to zero in each cell. The repair
    moves energy between them. The exception is a cell whose negative tags
    outweigh the positive ones, where every tag is set to zero.
  - For an overlay the ledger only grows. The clip adds energy that no other
    tag loses.
  - Large region ledgers mean large transport undershoots. On the gray sphere
    they reached ±30,920 J/kg under `tracer` (E27), and ±16,294 under the audit
    (E35).

### A record

A record is the signed sum of what its process applied in that cell. It is not
moved by the flow.

  - The output is divided by the current density. Each increment was added at
    its own step's density. So it is not exactly the sum of the per-step
    specific increments.
  - At one point, the records do not add up to the change in `ρe_tot`, because
    transport moves energy between points and has no record.
  - Over a whole column, transport cancels. Then the records' column integrals
    should add up to the change in the column's energy. That is form B.

### The per-process checks

With the validating layout, two checks compare parts that obey the same rule.
`experiments/tag_closure/analysis/c5_process_closure.jl <output_dir>` computes
both.

  - **Form A**, at each point: `Σ new_<region> - Σ <process tags>`. Both sides
    are overlays that collect the same new energy, one split by region and one
    by process. They agree as long as the rule stays linear in the tags. So
    form A breaks where a tag is negative and its share is clamped, where the
    repair lifts an overlay, or where a process runs without a tag of its own.
  - **Form B**, on a column only: the change in the column integral of `ρe_tot`,
    minus the column integrals of the records. The difference is what no record
    sees.
  - **The initial energy**, `<region> - new_<region>`, is what was in a region
    at the start. On a column its integral can only fall (E21).

Each check is blind to something.

  - Form A cannot see transport errors. Both sides are overlays moved by the
    same transport, so an error common to both cancels. It does not see
    pressure work, and it would not see the missing sub-grid flux under EDMF.
  - Form B cannot see transport either, because transport cancels in the column
    integral. It sees a process with no record, or an energy change outside
    every bracket.
  - Only the closure residual sees transport.

## Which check to trust where

| check | column, `tracer` | column, `enthalpy` | sphere, `tracer` | sphere, `enthalpy` |
|:-- |:-- |:-- |:-- |:-- |
| closure residual | yes. It grows with pressure work: 2.44e6 J/m² gross at 24 h under 0M, 2.46e6 under 1M (E33, E34) | yes, and clean: 2,284 J/m² at 24 h (E34) | yes. 2.82e21 J gross at 24 h (E34) | yes, and clean: 2.54e20 J, flat after the first hour (E34, E35) |
| form A, largest gap | yes. 60.7 J/kg at 24 h under 0M (E26), 117 J/kg under 1M (E33) | yes, and very tight: 6.6e-6 J/kg (E34) | yes, once every process that runs has a tag: 20.2 J/kg at 24 h (E30) | **no.** 76.8 J/kg with the repair off, 274 J/kg with it on (E34, E35) |
| form A, global integral | not computed | not computed | yes. 5.2e-5 of the new energy, against 1.26e-3 with a process untagged (E38) | yes. 4.7e-5 with the repair off. 6.0e-4 with it on, which is the energy the repair created (E38) |
| form B | yes. 3.3e-7 J/m² under 0M (E26), 5.3 J/m² of 897,043 under 1M (E33) | yes (E34) | not available: the lat-lon output gives no domain integral | not available |

The global integrals of E38 are approximate. They take a hydrostatic density on
the remapped grid.

**The lesson of E35 to E38.** On a sphere, form A's largest gap is numerical
noise. Under the audit it is not a clean check, with the repair on or off.
  - With the repair off, a negative overlay's share is clamped. It freezes at
    its node while its neighbours' shares keep pushing it (E36).
  - With the repair on, the repair lifts overlays on one side of form A and not
    the other (E35). Subtracting the repair's ledgers does not undo it, because
    a repaired value moves on and feeds the shares after it (E35).
  - Under `tracer`, the gap is the per-tag van Leer limiter (E37).

Transport errors cancel over the sphere, and a missing process does not. So
read form A as a global integral, and rely on the closure residual for
transport.

Not yet run: ice through time, and anything under EDMF. On a real cold state,
ice takes sedimentation's upward branch in every cell, and the partition closes
to 100 eps (E41). Under EDMF the tags get no sub-grid mass flux (E40). 2M cannot
run on this branch at all. On those, read all three checks as untested.

## What it costs

| item | cost | source |
|:-- |:-- |:-- |
| three tags with an hourly closure check and hourly output, on a column | 1.32× the untagged run | T4 |
| a closure check every step | dominates everything else. A1's 6.1× was mostly the check | T2, T3 |
| the offset | none measurable | T7 |
| the repair | about 1%, within run-to-run scatter | T8, E35 |
| `enthalpy` transport | about 5% per step | E34 |
| a record | one field, and one broadcast per tendency evaluation | by construction |
| `audit: true` | a few more global reductions per check | by construction |

These are one column and one sphere on one machine. They bound the cost for
similar runs. They do not predict it for others.

Check hourly or daily, never every step. Each distinct tag set is a new model
type and a full compile, which dominates a short job (T1).

## What the output cannot tell you

  - **Not what would have happened.** A tag says what contributed to the
    simulated energy. It does not say what would change if a process were
    altered. The other processes would respond.
  - **Not independent of the offset.** The shares depend on `c`, as they
    depended on the energy reference.
  - **Not an amount where it is negative.** Without the repair, tags go
    negative, even under a positive total (E14).
  - **Not conservation of the overlays.** The repair adds energy to an overlay
    from nowhere, and logs it.
  - **Not physical completeness.** Closure proves that the tracked terms add up
    to the total. It does not prove that the set of processes is complete.
  - **Not where a process removed energy.** Use the record (E22).
  - **Not a closed budget at a point.** The records add up only over a column,
    where transport cancels.
  - **Not sub-grid provenance.** The tags are grid-scale only.
  - **Not an air path, where ice falls.** The upward pass of provenance is
    accounting.
  - **Not sharp edges under the audit.** First-order shares smear. On the
    column, the radiation tag at the most cooled level held 5.8 J/kg under the
    audit, against 0.004 under `tracer` (E34).
  - **Not the rain-out under 1M and 2M,** in `microphysics`. It is in
    `e_prc_precipitation`, and no source tag receives it as production.
  - **Not tested widely.** One column type and one sphere type, a day each.

## Messages at startup

| message | what to do |
|:-- |:-- |
| the total the tags split is non-positive over some % of the domain | set or raise `energy_source_tag_offset` |
| condensate sediments but there is no offset | set an offset |
| a tag or a record lists `precipitation` | expected with `all` or `moist`. Such a tag receives nothing from it |
| the region masks do not add up to 1 | use one region and its complement |

Refused at startup: `enthalpy` without an offset, an offset or `enthalpy`
without tags, a closure check without its family, a family with only overlays,
and a tag named `res`.

## Proposed fixes to the existing pages

Each was checked against the code on this branch.

 1. **`tracer_configuration.md:40-43`** says energy source tags "have no repair
    at all and no non-negativity guarantee". The repair exists and is on by
    default (`energy_source_tag_repair`). Say: "The repair keeps them
    non-negative where their total is positive, and logs every change in
    `e_src_fix_<name>`. Without it they are not guaranteed non-negative."
 2. **`config/default_configs/default_config.yml:478`**, the help of
    `energy_source_tags`, says "unlimited transport has no repair". Same fix.
 3. **`tracer_configuration.md:410-414`** says the energy tags "never receive
    implicit transport or EDMFX sub-grid mass fluxes", "deliberate, because each
    tag is already transported in its own right". For the source tags both
    halves are now wrong. They receive sedimentation in the implicit step
    (`water_advection.jl:99-107`). And nothing transports them for the sub-grid
    mass flux: they have no updraft copy, so that flux reaches no tag. The
    docstring at `src/config/tracer_config.jl:564-569` repeats the first half.
 4. **`energy_source_tags.md:90-96`** says sedimentation adds nothing to
    `e_src_res`. True without EDMF. Under `prognostic_edmfx` the corrections
    between updraft and environment (`water_advection.jl:127-186`) are not
    shared, and they do add to it.
 5. **`energy_source_tags.md:292-294`**, under the audit: "the SGS closures"
    stay as under `tracer`. Add that the EDMF mass flux reaches the tags in
    neither mode.
 6. **`energy_source_tags.md:338`**, "grid-scale only". Add the consequences:
    no sub-grid mass flux, and a failed run with `edmfx_vertical_diffusion: true`.
 7. **`energy_source_tags.md:211-227`**, the tested boundary. The integration
    test now also covers sedimentation and the audit on a column and a small
    sphere (items 8 to 10 of `test/energy_source_tags_integration.jl`).
 8. **`process_record.md:120-125`** says `microphysics` is recorded however
    microphysics is stepped, and that the water side is a no-op under 1M. The
    energy side is a no-op too, under 1M, 2M and P3: the microphysics there
    never writes `ρe_tot`.
 9. **`process_record.md:137-140`** says the records do not add up to the
    change in the parent. At a point, yes. Over a column they do, to 3.3e-7 J/m²
    under 0M (E26). Say both.
10. **Neither page defines form A and form B**, or the validating layout. Link
    this guide, or move its "per-process checks" section into
    `energy_source_tags.md`.
