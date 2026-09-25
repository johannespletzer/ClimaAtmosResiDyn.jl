# Configuring Tracers

This page is the configuration reference for the tracer and tagging features
you can switch on from a YAML file. It says what to write. The pages it links to say how
each one works and what its output means.

You do not need to write any Julia code, and you do not need to understand the
implementation to use these. Start from a block on this page, change the
numbers, and run.

## Which one do I want?

| I want to know…                          | Use                                           | Adds                                |
|:---------------------------------------- |:--------------------------------------------- |:----------------------------------- |
| how long air stays in the stratosphere   | [`passive_tracers`](@ref passive_tracers)     | one inert tracer per release region |
| where the water at a point came from     | [`water_tracers`](@ref water_tracers)         | one field `ρq_tag_<name>` per tag   |
| where the energy at a point came from    | [`energy_source_tags`](energy_source_tags.md) | one field `ρe_src_<name>` per tag   |
| what heated or cooled the air at a point | [`energy_tracers`](@ref energy_tracers)       | one field `ρe_tag_<name>` per tag   |
| what each process did to the energy      | [`energy_process_record`](process_record.md)  | one field `prc_e_<process>` each    |
| what each process did to the water       | [`water_process_record`](process_record.md)   | one field `prc_q_<process>` each    |

They are independent. Switch on any one of them, or all of them, in the same
run. Each is off by default and costs nothing when off.

## What the words mean

Three of these families use the word "tag", and all three accept a `source`
key, but a tag does not hold the same kind of quantity in each.

  - **source tag**: an amount of the parent variable that is present now, traced
    back to where it came from. Both `water_tracers` and `energy_source_tags`
    are source tags, and they differ in what is guaranteed of the result. Water
    ends up non-negative wherever its parent does: every correction that touches
    a water tag preserves non-negativity, and `repair_water_tag_partition!` puts
    a negative holding back, with the `q_tag_fix_<name>` diagnostic logging how
    much was moved. Nothing keeps `ρq_tot` itself non-negative, though —
    `tracer_nonnegativity_method` is off by default — and where the parent is
    not positive the shares are undefined and the tags of that cell mean
    nothing, which the `nonpositive_fraction` column of the closure table
    reports. Energy source tags are **not non-negative on their own** — the
    loss term bounds the depletion rate rather than the amount removed over a
    step, and their parent has no physical zero to begin with. The repair,
    `energy_source_tag_repair`, is on by default. It puts a negative tag back
    wherever the tags' total is positive, and `e_src_fix_<name>` logs how much
    it moved. See [Energy Source Tags](energy_source_tags.md).
  - **signed process tag**: an `energy_tracers` entry configured with `source`.
    It starts at zero and holds the signed increment its process has added,
    going negative under net cooling. A running total of what a process did,
    not a source amount. Transported like any other tag.
  - **process-change record**: the `prc_e_<process>` and `prc_q_<process>`
    fields from the `energy_process_record` and `water_process_record` keys.
    Also a signed running total, but one field per process rather than per tag,
    and never transported. Reserve the phrase for these: a signed process tag
    is a different object and calling both by one name has already caused
    confusion.
  - **region tag**: a transported partition of the parent variable, in either
    family.
  - **source tracing**: what the source tags do. A description of the method,
    not the name of any output.
  - **closure**: whether the tags still add up to the variable they split. Also
    called a sum-to-total test.

A process-change record is available on its own, without any tags, through the
`energy_process_record` and `water_process_record` keys. See
[Process-Change Records](process_record.md).

The families differ in the *rule*, not the key. `water_tracers` and
`energy_source_tags` share out production by mask and take loss from each tag
in proportion to what it already holds, which yields an amount present.
`energy_tracers` applies the whole signed increment by mask, and an entry there
is a signed process tag only when it is configured with `source`: a `region`
entry is a transported partition. See
[Attribution](tagged_water.md#Attribution) and
[What a tag means](tagged_tracers.md#What-a-tag-means).

Two words are deliberately not used here. *Heat tagging* names a different
method that tags potential temperature; this tags moist total energy. A *source
fingerprint* is the pattern that source shares form across space and time, which
is an analysis product rather than anything the model writes out.

They are also separate top-level keys, so they can come from separate
configuration files. A run assembled from a numerics file, a water-tracer file
and an energy-tracer file keeps all three: later files override earlier ones key
by key, and these are three different keys.

!!! warning "One key sets the whole block"

    Overriding is per top-level key, not per setting inside it. If two
    configuration files both set `passive_tracers`, the later one replaces the
    earlier one completely — the settings are not combined. Write the whole
    block in one file.

* * *

## [`passive_tracers`](@id passive_tracers)

Inert tracers that are produced inside fixed regions and removed below the
tropopause. Because production and removal are the only terms, a tracer whose
burden has stopped drifting has a residence time of `burden / source` — which
is how long air released in that region stays in the stratosphere.

Physics and output: [Passive Tracers](passive_tracers.md).

### Starter block

Twelve tracers, from six latitude bands crossed with two height bands:

```yaml
passive_tracers:
  release_grid:
    latitude_bands: 6        # how many latitude boxes, spread pole to pole
    latitude_width: 10.0     # how wide each one is, in degrees
    height_bands: 2          # how many height boxes, stacked upwards
    height_depth: 2000.0     # how thick each one is, in m
    height_spacing: 10000.0  # how far apart their bottoms are, in m
  loss_timescale: "6hours"   # how fast tracer decays below the tropopause
```

!!! tip "Start small"

    Setup cost grows steeply with the number of tracers — roughly as the cube
    of it — and is paid again on every launch and restart. Six latitude bands
    by four height bands takes about 17 minutes to set up; doubling the height
    bands takes over two hours. Tracers do not interact, so several small runs
    covering different regions are cheaper than one large one.

### Settings

| Key               | Meaning                                                    | Default      |
|:----------------- |:---------------------------------------------------------- |:------------ |
| `release_grid`    | release regions on a regular latitude × height grid        | —            |
| `release_boxes`   | release regions listed one by one                          | —            |
| `heights_from`    | what heights are measured from: `tropopause` or `altitude` | `tropopause` |
| `production_rate` | how fast tracer is made inside a release region, in 1/s    | `1.0e-10`    |
| `loss_timescale`  | decay time below the tropopause                            | `6hours`     |
| `tropopause`      | how the tropopause is found                                | see below    |

Exactly one of `release_grid` and `release_boxes` is required. Setting both is
an error, and so is setting neither — 48 tracers is hours of setup, which is
not a thing to arrive at by leaving a key out.

`production_rate` sets how large the tracer values are, not how long the
residence times are: burden and source are both proportional to it, and only
their ratio is reported. Leave it alone unless the numbers are inconveniently
small.

`loss_timescale` should be short compared with the residence times you are
measuring (years) and long compared with the timestep. It cannot be infinite —
that would remove the tracers' only sink, so they would never settle.

The budget table that the residence times come from is written every
`dt_tracer_budget`, which is a separate top-level key because it is an output
cadence like `dt_rad`.

#### `release_grid`

Every key is optional; anything you leave out keeps its default.

| Key              | Meaning                                                                                                  | Default |
|:---------------- |:-------------------------------------------------------------------------------------------------------- |:------- |
| `latitude_bands` | number of latitude boxes, centred on equal divisions from pole to pole                                   | `6`     |
| `latitude_width` | width of each latitude box, in degrees. Must not exceed the spacing between them, or boxes would overlap | `10`    |
| `height_bands`   | number of height boxes, stacked upwards                                                                  | `8`     |
| `height_depth`   | thickness of each height box, in m. Must not exceed `height_spacing`                                     | `2000`  |
| `height_spacing` | distance between the bottoms of successive height boxes, in m                                            | `5000`  |
| `lowest_height`  | height of the bottom of the lowest box, in m                                                             | `0`     |

#### `release_boxes`

Use this when the boxes are not a neat latitude × height grid: uneven spacing,
boxes of different thickness, or a grid with some combinations left out. Each
box is one line:

```yaml
passive_tracers:
  heights_from: "altitude"
  release_boxes:
    - {latitude: [-85.0, -75.0], height: [9989.7, 10404.8]}
    - {latitude: [-5.0, 5.0], height: [27896.0, 28623.5]}
    - {latitude: [75.0, 85.0], height: [45380.1, 46322.6]}
```

`latitude` is `[southern edge, northern edge]` in degrees and `height` is
`[bottom, top]` in m. To make a box exactly one model layer thick, use that
layer's face heights.

Boxes may overlap. The tracers are independent, so a point inside two of them
simply feeds both. What is refused is two boxes with the same latitude *and*
height range, because they would claim the same name.

#### `tropopause`

Rarely changed. Every key is optional.

| Key                    | Meaning                                                                                               | Default   |
|:---------------------- |:----------------------------------------------------------------------------------------------------- |:--------- |
| `lapse_rate_threshold` | WMO lapse-rate threshold, in K/m                                                                      | `0.002`   |
| `consistency_depth`    | depth above a candidate tropopause over which the mean lapse rate must stay below the threshold, in m | `2000.0`  |
| `search_min_height`    | lowest height a tropopause may be found at, in m. Excludes boundary-layer inversions                  | `5000.0`  |
| `search_max_height`    | highest height a tropopause may be found at, in m                                                     | `25000.0` |

* * *

## [`water_tracers`](@id water_tracers)

Splits total water into labelled parts, so you can see where the water at a
point came from. Each tag adds one prognostic field `ρq_tag_<name>`.

Physics and output: [Tagged Water Tracers](tagged_water.md).

Needs `microphysics_model: "0M"` or `"1M"`.

### Starter block

```yaml
microphysics_model: "0M"
water_tracers:
  - name: tropics
    region: tropics          # water that was in the tropics to begin with
  - name: extratropics
    region: extratropics
  - name: evap
    source: surface_flux     # water that evaporated from the surface
```

### Where water can come from

A `source` says which process a tag follows.

| Group     | `source` label          | Process                                                        |
|:--------- |:----------------------- |:-------------------------------------------------------------- |
| `surface` | `surface_flux`          | evaporation from the surface, or dew when the flux is negative |
| *(none)*  | `microphysics`          | the 0-moment total-water sink                                  |
| `forcing` | `large_scale_advection` | prescribed large-scale moistening or drying                    |
| `forcing` | `subsidence`            | prescribed large-scale subsidence                              |
| `forcing` | `external_forcing`      | externally prescribed (e.g. GCM-driven) forcing and nudging    |

A group name may be used wherever a label is expected, and `all` expands to
every process in the table.

!!! note "`microphysics` is in no named group"

    `source: surface` selects `surface_flux` only, so a tag written that way
    follows evaporation but not the 0-moment sink. `all` is the only group that
    includes `microphysics`. To follow both without the forcings, list them:
    `source: [surface_flux, microphysics]`.

* * *

## [`energy_tracers`](@id energy_tracers)

Splits moist energy into labelled parts, so you can see what heated or cooled
the air at a point. Each tag adds one prognostic field `ρe_tag_<name>`.

Physics and output: [Tagged Energy Tracers](tagged_tracers.md).

### Starter block

```yaml
energy_tracers:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
  - name: rad
    source: radiation        # energy put in or taken out by radiation
```

### What energy can come from

| Group       | `source` label          | Process                                                                        |
|:----------- |:----------------------- |:------------------------------------------------------------------------------ |
| `radiative` | `radiation`             | all radiation modes (RRTMGP, gray, DYCOMS, TRMM\_LBA, ISDAC)                   |
| `turbulent` | `surface_flux`          | turbulent surface energy flux                                                  |
| `moist`     | `microphysics`          | microphysics energy sources; for `energy_tracers` only when stepped explicitly |
| `moist`     | `precipitation`         | energy carried out of a level by falling precipitation                         |
| `forcing`   | `held_suarez`           | Held–Suarez relaxation forcing                                                 |
| `forcing`   | `large_scale_advection` | prescribed large-scale advective forcing                                       |
| `forcing`   | `subsidence`            | prescribed large-scale subsidence                                              |
| `forcing`   | `external_forcing`      | externally prescribed (e.g. GCM-driven) forcing                                |

!!! note "Which moist label carries the signal"

    With 0-moment microphysics the moist energy sink appears in `microphysics`.
    The 1-moment and 2-moment schemes change only the water species, and the
    energy leaves with the falling precipitation, so the signal appears in
    `precipitation` instead. Tagging the `moist` group covers both.

* * *

## Checking closure while a run goes

"Closure" is the statement that the tags still add up to the field they split.
It is what tells you the tags mean what they say. The `q_tag_res` / `e_tag_res`
diagnostics give it to you as a 3-D field to look at afterwards; the two keys
below reduce it to two numbers and write them to a table every `period`, so you
can see drift without waiting for the run to end.

```yaml
water_closure_check:
  period: "1days"        # how often to check
  tolerance: 1.0e-10     # warn above this relative residual
  void_above: 1.0        # above this, warn once and mark every later row
                         # closure_void, also after a restart
  abort_above: ~         # end the run above this one; never, by default
  audit: false           # write the second table described below
  negative_water_void_above: 1.0e-4  # water only: above this fraction of
                         # negative water, mark every later row
                         # negative_water_void, also after a restart

energy_closure_check:
  period: "1days"
  tolerance: 1.0e-6
  void_above: ~          # the default for both energy families
  abort_above: ~
```

Every key is optional inside each block, and both blocks are off by default.
Both also accept `spin_up`, described under the energy source tags.
Each writes `water_tag_closure.csv` / `energy_tag_closure.csv` to the output
directory, with columns `time`, `total`, `tagged`, `residual`, `relative`,
`gross_residual`, `gross_relative`, `scale` and `nonpositive_fraction`, then a
column `closure_void` where the check has a void level. The water table ends
with `negative_water_relative` and `negative_water_void`, unless
`negative_water_void_above` is `~` (see below).

`residual = total - tagged` is the signed miss between two global integrals, and
`relative` is it over `scale = ∫|parent|`. `gross_residual` integrates the
pointwise `|parent - Σ tags|` instead, and `gross_relative` is that over `scale`
too. The normalizer is `∫|parent|` rather than `total` because the parent may be
signed: moist total energy has no physical zero, so `∫ρe_tot` can be negative or
zero under a shifted reference and a ratio taken over it could never exceed a
positive tolerance. `nonpositive_fraction` is the volume fraction where the
parent is not positive, reported separately because closure cannot reveal it.

The distinction matters, and `gross_relative` is the one the tolerance is
compared against. Because `total` and `tagged` are each a single global
integral, a partition that is too high by some amount in one place and too low
by the same amount somewhere else has a signed residual of exactly zero — it
reports perfect closure while being locally wrong. Taking the absolute value
before integrating cannot cancel that way. `gross_relative` is never smaller
than `|relative|`, so watching it also catches everything the signed number
would; the signed pair is still written because its sign says which way the
leak goes.

Exceeding the tolerance **warns and keeps running**. Closure drift is something
you want to watch grow, and ending a multi-year integration over it costs more
than it saves.

Exceeding `void_above` **marks the tags void, and the run goes on.** That is a
different event from drift: a residual larger than the field it measures says
the tags no longer describe anything. The check warns once, and from then on it
writes `closure_void` as 1 on every row of its closure table and its audit
table. The tags are a diagnostic, and a diagnostic must never end a run that
the model would complete. Before, water's check ended the run at this level,
and so ended runs whose parent's own water had gone negative (known issue 7).
Only water has a default level, `1.0`. A set of non-negative tags inside a
non-negative parent misses it by at most the parent itself, pointwise, so an
honest partition cannot reach 1 — and neither can an honest strict subset of one, which leaves
most of the water untagged and pushes the ratio towards 1 from below. Passing 1
means the tags hold water that is not there, or the parent has gone negative.
Both energy families default to `~`, no level at all, because their residual is
normalized by `∫|ρe_tot|`, whose zero is a convention: a shifted energy
reference can make that denominator arbitrarily small and the ratio
arbitrarily large with nothing wrong. Set one per run once its first closure
table shows where that configuration settles. Writing `void_above: ~` turns the
water default off.

The flag holds across a restart. The checkpoint records it, and the restarted
run reads it back before its first check. So a run split into segments marks
its rows as one run would. A check that restarts as void says so in a warning.
A checkpoint written before the flag was recorded restarts as not void, also
with a warning.

`closure_void` is about the closure only. It says that the residual has passed
`void_above`, and nothing else. `closure_void = 0` does not mean that the tags
or the parent are valid. It only means that the residual has not passed the
level yet. The parent's water can go negative long before that. At site 23 of
the tag-closure long runs, the parent's `q_tot` went below zero from day 10.
The water closure passed 1.0 only at day 48 in one run, and at day 74.5 in two
others.

For the parent, read `nonpositive_fraction` in the same row. It is the volume
fraction of the domain where the parent is zero or negative, at the time of the
row, and the check warns on every row where it is above zero. For water, that
means the tags' shares are undefined somewhere. The audit's
`nonpositive_mass_fraction` gives the same by mass. Both read the grid-mean
parent at the check's times only, so a cell that goes negative and back between
two checks does not show. Unlike `closure_void`, they are not kept from one row
to the next. For water, the next section adds a flag that is kept, and a
ledger that sees every step.

### The parent's negative water

The water tags partition the parent's non-negative water, `max(ρq_tot, 0)`
(known issue 7, option C). The closure check compares them with that. So a
parent whose own water has gone negative can close perfectly, and
`closure_void` stays 0. The water check therefore also reads the parent's own
negative water, from the raw `ρq_tot`, not from the partition's target.

`negative_water_relative`, on every row of the water closure table, is

    ∫max(-ρq_tot, 0) dV / ∫ρq_tot dV,

the parent's negative water, `Σ ρ max(-q_tot, 0) dV`, over its water, at the
row's time. It is 0 where no cell is negative, and `Inf` where some cell is
negative and `∫ρq_tot` is not positive. This is the tag-closure contract's row
"Parent validity: negative water" read at the checks: above `1e-4`, a run's
water results are not scored.

`negative_water_void_above`, `1e-4` by default, is that level. The first row
whose `negative_water_relative` passes it warns once, and from then on
`negative_water_void` is 1 on every row of the closure table and of the audit
table, also after the parent recovers. The checkpoint records the flag, as it
records `closure_void`, and a restarted run reads it back before its first
check. A checkpoint written before the flag restarts it at 0, with a warning.
`negative_water_void_above: ~` drops both columns. Zero marks the rows at the
first negative water. Only `water_closure_check` takes the key.

`negative_water_void` says one thing: the parent's negative water passed the
level at a check. `negative_water_void = 0` does not say that the parent is
valid in any other way. The check reads the state at its own times only, so
an excursion that begins and ends between two checks does not set the flag. At
site 23 of the tag-closure long runs, the negative water rose from zero within
one 6-hour interval at the start of each spell, and fell back to zero within
one at its end. So an excursion shorter than the interval is possible.

The audit sees every step instead. After each accepted step, a ledger in the
cache adds `max(-ρq_tot, 0) Δt` per cell, and counts the cells whose `ρq_tot`
is below zero. The checkpoint carries it. The water audit table reports it:

| column                                  | what it is                                                                                   |
|:--------------------------------------- |:-------------------------------------------------------------------------------------------- |
| `negative_water_integral`               | `∫∫max(-ρq_tot, 0) dV dt` since the start of the run, in kg s                                 |
| `negative_water_interval`               | its change since the previous audit row, in kg s                                              |
| `negative_water_interval_mean_relative` | that change over the interval's length, over `∫ρq_tot dV` at this row                          |
| `negative_water_interval_events`        | cell-steps in the interval whose end state had `ρq_tot < 0`; exactly 0 when none had any      |
| `negative_water_void`                   | the flag above, last                                                                          |

An interval with `negative_water_interval_events = 0` had no negative water
at the end of any accepted step, anywhere. The first row of a run, or of a
restarted segment, has an empty interval, so its interval columns are 0. The
interval's mean divides by `∫ρq_tot` at the row, not over the interval, so it
does not set the flag. A checkpoint written before the ledger restarts it at
zero, with a warning. The per-cell fields are the opt-in diagnostics
`q_tag_negative_integral`, in kg s m⁻³, and `q_tag_negative_events`.

Both the flag and the ledger live in the cache and in the checkpoint, never in
the model's state, so neither can change a model field.

Exceeding `abort_above` **ends the run**, where a user sets it. No family sets
one by default. Set it when a run whose tags no longer mean anything is not
worth its compute.

The check adds no tendency. It only reads the state and writes a table, so
switching it on does not change what the simulation produces.

### The audit table

`gross_relative` is the right number to compare against a tolerance and the
wrong number to diagnose with. It adds together situations that are not the same
problem and do not have the same answer. Setting `audit: true` writes a second
table, `<family>_tag_audit.csv`, that separates them. It is off by default,
costs a handful of extra global reductions per check, and changes nothing about
the run.

| column                     | what it is                                                            |
|:-------------------------- |:--------------------------------------------------------------------- |
| `untagged`                 | `∫max(parent - Σ tags, 0)`: water the tags do not account for         |
| `overclaimed`              | `∫max(Σ tags - parent, 0)`: water the tags claim that is not there    |
| `orphaned`                 | mass in cells whose parent still holds water while every tag is empty |
| `orphaned_volume_fraction` | volume fraction of those cells                                        |
| `nonpositive_mass`         | mass where the parent is not positive                                 |

Each of the first three also has a `_relative` column over the same `scale` the
closure table uses, and `nonpositive_mass_fraction` is `nonpositive_mass` over
it. For water, `nonpositive_mass` is `∫|min(ρq_tot, 0)| dV` of the raw
`ρq_tot`. The partition's target, `max(ρq_tot, 0)`, is never negative, so read
from it the column would be 0 by construction. `scale` is the target's
integral, `∫max(ρq_tot, 0) dV`. The water audit table also has the negative
water ledger's columns, after `closure_void` (see above). A separate file rather than more columns on the closure table, so that
turning the audit on does not change a schema other runs and analysis scripts
already read. Join the two on `time`.

Three things it tells you that the closure table cannot.

**Which way the tags are wrong.** `untagged + overclaimed` is `gross_residual`
to reduction round-off, so nothing is lost by reading them apart. The identity
is exact pointwise; each of the three is its own volume integral and rounds
separately, so compare them with a tolerance. They mean opposite
things. Untagged water has an origin that nothing claims to know, which is
recoverable in principle. Overclaimed water is the tags asserting water that
does not exist, which is not a physical state at all and is the direction a
runaway takes.

**Whether provenance is drifting or gone.** A tag that is a little wrong still
maps water to where it came from. A cell whose tags have all been emptied does
not, and nothing re-tags it afterwards: that water stays anonymous for the rest
of the run and mixes into its neighbours. `orphaned` counts total loss only, so
it is a lower bound — a cell left holding a sliver of one tag does not appear
there and shows up in `untagged` instead.

**How much of the field the undefined region actually holds.**
`nonpositive_fraction` in the closure table is a volume fraction while `scale`
is a mass integral, and on a moist sphere the two tell opposite stories: cells
with no water take up much of the volume and almost none of the mass. Reading
the volume fraction alone says most of the domain has undefined shares. Reading
the mass fraction alone says the state is nearly clean. Both are true, and a
cell that holds negligible mass can still be where a scheme breaks.

### Why the two tolerances differ

The default for energy is looser than the one for water by four orders of
magnitude, and that is not arbitrary. The water tags ride the same transport
operators as `ρq_tot` apart from the implicit-versus-explicit vertical
advection split, so very little escapes them. The energy tags follow their
parent less closely. The `ρe_tag_*` family rides the passive-tracer path, and
so do the energy source tags under the default
`energy_source_tag_transport: tracer`. Meanwhile `ρe_tot` is moved as enthalpy,
pressure work included, and vertically on the implicit path. The `enthalpy`
audit moves the source tags with the parent's own advective and hyperdiffusive
fluxes instead, but still explicitly (see
[Moving the tags as enthalpy, an audit](@ref)).
Transport is not attributed on top of that. Each tag is already transported in
its own right, and attributing the `ρe_tot` version as well would count it
twice. The `ρe_tag_*` family has no updraft copy, so the EDMFX sub-grid mass
flux does not reach it through the updrafts. By default the energy source tags
have none either. They take their shares of the parent's own sub-grid flux
instead, with one updraft, and exchange provenance at the mass flux. With
`energy_source_tag_updraft_copy: true` they have copies, and the model's SGS
tracer flux moves them. Sedimentation reaches both families: the `ρe_tag_*` family
attributes it under `precipitation`, and the energy source tags follow it on
the implicit path as transport of their own (see
[Energy Source Tags](energy_source_tags.md)). So a visibly larger residual is
the expected, correct behaviour, not a bug.

!!! tip "Calibrate on your own configuration"

    Treat the water and energy defaults as starting points. The energy source
    tags have none, and their check never warns about the residual until you
    set one. Run once, read the `relative`
    column, and set a tolerance a little above the level your configuration
    settles at. A tolerance tuned that way turns the warning into news; one
    left at a default that your setup never meets is just noise.

Two configurations are refused at startup rather than left to mislead you: a
check enabled without its tracer family, and a family whose entries all carry a
`source`. Closure is the sum of the *pure region* tags — a tag with a `source`
starts at zero and is not part of the partition — so with none of them there is
nothing to close against.

* * *

## Tag entries

`water_tracers` and `energy_tracers` take the same kind of entry. Each needs a
unique `name` and at least one of `region` and `source`.

Some names are reserved, because a tag's name becomes part of a diagnostic's
name, and another diagnostic of the family would take it:

  - `res` is reserved in both families. It is the closure residual,
    `q_tag_res` or `e_tag_res`.
  - A `water_tracers` name may not begin with `fix_`, `upfix_`, `inc_`,
    `rtag_` or `stag_`. `fix_` begins the ledger `q_tag_fix_<name>`; the
    others are held for diagnostics still to come.
  - The underscore is part of each prefix, so names such as `fixed`, `income`
    and `rtagged` are allowed.

| Field    | Meaning                                                                                     |
|:-------- |:------------------------------------------------------------------------------------------- |
| `name`   | what the tag is called. Appears in the output as `q_tag_<name>` / `e_tag_<name>`            |
| `region` | where the tag starts out. A [named region](#Named-regions), or a region written out in full |
| `source` | which process the tag follows. One label, or a list of them                                 |

What a tag starts as depends on which of the two you give it:

  - **`region` only.** Starts as the share of water (or energy) inside that
    region, and is then carried around by the flow.
  - **`source` only.** Starts at zero and accumulates only from that process.
  - **Both.** Starts at zero and accumulates from that process, but only inside
    that region. Useful for asking "how much of the evaporation happened in the
    tropics?".

!!! warning "Use exactly one set of regions per run"

    The closure diagnostics `q_tag_res` and `e_tag_res` add up **all** the tags
    that have a region and no source. They are only meaningful if those tags
    cover the domain exactly once — a region and its complement, such as
    `tropics` and `extratropics`. Two overlapping decompositions in one run make
    the residual meaningless. A warning is printed at startup when the masks do
    not add up to 1.

### Named regions

The quickest way to write a region:

| Name           | Where                     |
|:-------------- |:------------------------- |
| `everywhere`   | the whole domain          |
| `tropics`      | within 20° of the equator |
| `extratropics` | everywhere else           |

`tropics` and `extratropics` are exact complements, so they are a valid pair for
the closure diagnostics above.

### Regions written out in full

Anything else is written as a mapping with a `type`. Edges are smoothed with a
`tanh` over the given `width` rather than being sharp.

| `type`          | Required                                                      | Meaning                           |
|:--------------- |:------------------------------------------------------------- |:--------------------------------- |
| `everywhere`    | —                                                             | the whole domain                  |
| `tanh_altitude` | `z_center`, `width` (m)                                       | above a height                    |
| `tanh_latitude` | `lat_bound`, `width` (degrees)                                | within `lat_bound` of the equator |
| `tanh_box`      | `lon_min`, `lon_max`, `lat_min`, `lat_max`, `width` (degrees) | a longitude–latitude box          |
| `tanh_polygon`  | `vertices` (a list of `[lon, lat]` pairs), `width` (degrees)  | an arbitrary polygon              |

Every type except `everywhere` also takes `inside: false` (`above: false` for
`tanh_altitude`) to select the exact complement instead.

#### What the numbers have to satisfy

Four combinations describe no region at all, and are refused with a message
naming the key rather than run:

  - `width` must be **greater than zero**, for every type. Zero is not a sharp
    edge, it is an undefined one: a point sitting exactly on the edge gives
    `NaN`, and one `NaN` spreads through the tagged field on the first step.
    A negative width goes wrong differently for each type — it gives you the
    complement of a `tanh_altitude` or `tanh_polygon` region, it turns a
    `tanh_latitude` band *negative*, and it does nothing whatever to a
    `tanh_box`, which quietly uses the width without its minus sign.
  - `lat_bound` must be **greater than zero**. The band is `|lat| ≤ lat_bound`,
    so zero is empty and a negative bound makes the mask itself negative — the
    tag would hold a negative share of the air.
  - A box needs `lat_min` **below** `lat_max`. Equal bounds give a mask of zero
    everywhere, reversed bounds a negative one.
  - A box must **span some longitude**. Longitudes are compared modulo 360°,
    which is what lets a box cross the antimeridian (`lon_min: 170`,
    `lon_max: -170` is a 20° box), and it also means a full turn looks exactly
    like no turn. Writing `lon_min: -180, lon_max: 180` for "every longitude"
    used to give a mask of zero everywhere. If you want a band over every
    longitude and it is symmetric about the equator, use `tanh_latitude`.

```yaml
energy_tracers:
  - name: stratosphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0}
  - name: troposphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0, above: false}
```

!!! warning "Smoothing is required, not cosmetic"

    In longitude and latitude — `tanh_latitude`, `tanh_box`, `tanh_polygon`,
    whose `width` is in degrees — a sharp 0/1 mask produces Gibbs oscillations
    in the spectral-element horizontal discretization that contaminate the
    tagged fields from the first step. Set `width` comparable to, or larger
    than, the horizontal grid spacing. This matters most for `tanh_polygon`,
    where the vertices often come from a tool that rasterizes sharply — see
    [Tagged Energy Tracers](tagged_tracers.md) for turning an IPCC AR6
    reference region into a config block.

    `tanh_altitude` is a different case. Its `width` is in metres and the
    vertical grid is finite-difference rather than spectral, so there is no
    ringing to avoid. Smoothing there is about resolution: a transition
    thinner than the local layer spacing is not resolved, so set `width` at
    least as thick as the layers the edge crosses.

* * *

## Worked examples in this repository

  - `config/model_configs/passive_stratospheric_tracers_ci.yml` — small grid, runs in minutes
  - `config/example_configs/passive_stratospheric_tracers.yml` — a multi-year aquaplanet run
  - `config/example_configs/strat_tracers_transient_a.yml` — an explicit box list
  - `config/model_configs/baroclinic_wave_tagged_water.yml` — water tags with a closure check
  - `config/model_configs/baroclinic_wave_tagged_tracers.yml` — the same for energy tags
  - `config/model_configs/baroclinic_wave_energy_source_tags.yml` — energy source tags laid out for the per-process checks, with records

## Tracer configuration API

```@docs
ClimaAtmos.NAMED_TAG_REGIONS
ClimaAtmos.tag_region_from_config
ClimaAtmos.tag_region_spec
ClimaAtmos.tag_region_text
ClimaAtmos.tag_sources_from_config
ClimaAtmos.passive_tracer_model
ClimaAtmos.energy_tracer_tuple
ClimaAtmos.water_tracer_tuple
ClimaAtmos.DEFAULT_CLOSURE_TOLERANCES
ClimaAtmos.ENERGY_SOURCE_CLOSURE_TOLERANCES
ClimaAtmos.energy_source_closure_tolerance
ClimaAtmos.DEFAULT_CLOSURE_ABORT_LEVELS
ClimaAtmos.DEFAULT_CLOSURE_VOID_LEVELS
ClimaAtmos.closure_check_from_config
ClimaAtmos.tag_closure
ClimaAtmos.tag_audit
ClimaAtmos.tag_closure_callback
ClimaAtmos.tag_closure_callback!
ClimaAtmos.write_tag_closure!
ClimaAtmos.tag_closure_void_flags
ClimaAtmos.write_tag_closure_void_attributes!
ClimaAtmos.restore_tag_closure_void!
ClimaAtmos.closure_signed_parent
ClimaAtmos.negative_water_rows
ClimaAtmos.negative_water_void_flags
ClimaAtmos.write_negative_water_void_attributes!
ClimaAtmos.restore_negative_water_void!
```
