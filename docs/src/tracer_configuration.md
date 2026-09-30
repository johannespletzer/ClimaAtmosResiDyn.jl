# Configuring Tracers

This page is the configuration reference for the tracer and tag features. Each
one is a top-level YAML key, and each is off by default. With one on, every
model field that exists without it stays bit for bit as in the same run with it
off, under the default solver settings. Only the feature's own fields and
output are added. The [parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream) states the limits. It does not
cover `use_krylov_method` or `use_newton_rtol`, whose residual norm includes the
feature's fields, and the stratospheric passive tracers have no on/off test
yet.

Start from a block on this page, change the numbers, and run. No Julia code is
needed. The pages linked below say how each family works and what its output
means.

## Which one do I want?

| I want to know…                          | Use                                                  | Adds                                 | Details                                                                                             |
|:---------------------------------------- |:---------------------------------------------------- |:------------------------------------ |:--------------------------------------------------------------------------------------------------- |
| how long air stays in the stratosphere   | [`passive_tracers`](@ref passive_tracers)            | one inert tracer per release region  | [Passive Tracers](passive_tracers.md)                                                               |
| where the water at a point came from     | [`water_tracers`](@ref water_tracers)                | one field `ρq_tag_<name>` per tag    | [Tagged Water Tracers](tagged_water.md)                                                             |
| how much of that water is rain or snow   | `water_tag_precipitation: true` (Experimental)       | a rain and a snow part per water tag | [Rain and Snow Tags](tagged_water_precipitation.md)                                                 |
| where the energy at a point came from    | [`energy_source_tags`](@ref energy_source_tags_conf) | one field `ρe_src_<name>` per tag    | [Energy Source Tags: a user guide](energy_source_tags_guide.md), [reference](energy_source_tags.md) |
| what heated or cooled the air at a point | [`energy_tracers`](@ref energy_tracers)              | one field `ρe_tag_<name>` per tag    | [Tagged Energy Tracers](tagged_tracers.md)                                                          |
| what each process did to the energy      | `energy_process_record`                              | one field `prc_e_<process>` each     | [Process-Change Records](process_record.md)                                                         |
| what each process did to the water       | `water_process_record`                               | one field `prc_q_<process>` each     | [Process-Change Records](process_record.md)                                                         |

The families are independent. Switch on any one of them, or all of them, in the
same run.

The tags attribute water and energy by the rules you configure: the region
masks, the `source` labels, and each family's transport and loss rules. Their
results are attributions defined by those rules, not a unique physical history.
Energy source tag results also depend on `energy_source_tag_offset`, so report
the offset with them.

## What the words mean

The [glossary](glossary.md) defines these terms. In short:

  - **region tag**: an entry with a `region` and no `source`. A transported part
    of the parent variable. The region tags together form one partition of it.
  - **source tag**: an entry of `water_tracers` or `energy_source_tags` with a
    `source`. The amount of the parent that is present now and that the rules
    attribute to that process. A repair puts a negative tag back, for the energy source tags
    under `energy_source_tag_repair` (on by default). Its repair ledger,
    `q_tag_fix_<name>` or `e_src_fix_<name>`, logs what it moved.
  - **signed process tag**: an `energy_tracers` entry with a `source`. It starts
    at zero and holds the signed running total of what that process added. It
    goes negative under net cooling.
  - **process-change record**: the `prc_e_<process>` and `prc_q_<process>`
    fields. One per process, not per tag, and never transported.
  - **closure**: whether the tags still add up to the variable they split.

`water_tracers` and `energy_source_tags` share out production by mask and take
loss from each tag in proportion to what it holds. `energy_tracers` applies the
whole signed increment by mask. The rule differs between the families, not the
key. See [Attribution](tagged_water.md#Attribution) and
[What a tag means](tagged_tracers.md#What-a-tag-means).

## Combining configuration files

The keys are separate top-level keys, so they can come from separate
configuration files. Later files override earlier ones key by key. A run
assembled from a numerics file, a water-tracer file and an energy-tracer file
keeps all three.

!!! warning "One key sets the whole block"

    Overriding is per top-level key, not per setting inside it. If two
    configuration files both set `passive_tracers`, the later one replaces the
    earlier one completely. The settings are not combined. Write the whole block
    in one file.

* * *

## [`passive_tracers`](@id passive_tracers)

Inert tracers that are produced inside fixed regions and removed below the
tropopause. Production and removal are the only terms. So when a tracer's burden
has stopped changing, `burden / source` is the residence time of air released in
that region. Physics and output: [Passive Tracers](passive_tracers.md).

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

    Setup cost grows steeply with the number of tracers, and it is paid again on
    every launch and restart. Tracers do not interact, so several small runs
    covering different regions are cheaper than one large one.

### Keys

| Key               | Meaning                                                                                                                           | Default      |
|:----------------- |:--------------------------------------------------------------------------------------------------------------------------------- |:------------ |
| `release_grid`    | release regions on a regular latitude × height grid                                                                               | none         |
| `release_boxes`   | release regions listed one by one                                                                                                 | none         |
| `heights_from`    | what heights are measured from: `tropopause` or `altitude`                                                                        | `tropopause` |
| `production_rate` | how fast tracer is made inside a release region, in 1/s. It scales the tracer values, not the residence times                     | `1.0e-10`    |
| `loss_timescale`  | decay time below the tropopause. Short compared with the residence times you measure, long compared with the timestep, and finite | `6hours`     |
| `tropopause`      | how the tropopause is found, see below                                                                                            | see below    |

Exactly one of `release_grid` and `release_boxes` is required. Setting both, or
neither, is an error. The budget table that the residence times come from is
written every `dt_tracer_budget`, a separate top-level key because it is an
output cadence like `dt_rad`.

Every key of `release_grid` is optional:

| Key              | Meaning                                                                  | Default |
|:---------------- |:------------------------------------------------------------------------ |:------- |
| `latitude_bands` | number of latitude boxes, centred on equal divisions from pole to pole   | `6`     |
| `latitude_width` | width of each latitude box, in degrees. At most the spacing of the boxes | `10`    |
| `height_bands`   | number of height boxes, stacked upwards                                  | `8`     |
| `height_depth`   | thickness of each height box, in m. At most `height_spacing`             | `2000`  |
| `height_spacing` | distance between the bottoms of successive height boxes, in m            | `5000`  |
| `lowest_height`  | height of the bottom of the lowest box, in m                             | `0`     |

The grid refuses boxes that would overlap. To place boxes freely, list them in
`release_boxes`, one per line. `latitude` is `[southern edge, northern edge]` in
degrees and `height` is `[bottom, top]` in m.

```yaml
passive_tracers:
  heights_from: "altitude"
  release_boxes:
    - {latitude: [-85.0, -75.0], height: [9989.7, 10404.8]}
    - {latitude: [-5.0, 5.0], height: [27896.0, 28623.5]}
```

Listed boxes may overlap. The tracers are independent, so a point inside two of
them feeds both. Two boxes with the same latitude and height range are refused,
because they would claim the same name. To make a box one model layer thick, use
that layer's face heights.

`tropopause` takes four optional keys: `lapse_rate_threshold` (`0.002`, WMO
threshold in K/m), `consistency_depth` (`2000.0`, depth above a candidate over
which the mean lapse rate must stay below the threshold, in m),
`search_min_height` (`5000.0`, lowest height a tropopause may be found at, in m,
which excludes boundary-layer inversions) and `search_max_height` (`25000.0`,
highest, in m).

* * *

## [`water_tracers`](@id water_tracers)

Splits total water into labelled parts, so you can see where the water at a
point came from. Each tag adds one prognostic field `ρq_tag_<name>`. It needs
`microphysics_model: "0M"` or `"1M"`. Physics and output:
[Tagged Water Tracers](tagged_water.md).

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

Setting `water_tag_precipitation: true` splits each water tag into the water
that is neither rain nor snow, rain, and snow. It is Experimental and needs 1M
microphysics without EDMF. See [Rain and Snow Tags](tagged_water_precipitation.md).

* * *

## [`energy_tracers`](@id energy_tracers)

Splits moist energy into labelled parts, so you can see what heated or cooled
the air at a point. Each tag adds one prognostic field `ρe_tag_<name>`. Physics
and output: [Tagged Energy Tracers](tagged_tracers.md).

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

## [`energy_source_tags` and process records](@id energy_source_tags_conf)

`energy_source_tags` split `ρe_tot + c·ρ` by where the energy present now came
from. `c` is `energy_source_tag_offset`, in J/kg, which the tags require. The
tags take the entries and the `source` labels of `energy_tracers`, and the water
tags' rule. `energy_process_record` and `water_process_record` list the
processes to record. They work with no tags configured.

```yaml
microphysics_model: "0M"
energy_source_tag_offset: 110495.0
energy_source_tags:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
  - name: sfc
    source: surface_flux
energy_process_record: [radiation, surface_flux]
water_process_record: [surface_flux]
```

Two labels differ for the source tags. `precipitation` receives nothing, because
the tags follow sedimentation as transport. `microphysics` receives energy only
under 0-moment microphysics. Each case warns at startup. A record warns for
`precipitation` where nothing sediments, and for `microphysics` outside 0-moment
microphysics. `water_process_record` needs `microphysics_model: "0M"` or `"1M"`
and uses the water labels.

A Newton solve that stops on a residual norm over the whole state sees the
energy source tags. Use a fixed iteration count or a direct solve. See
[Energy Source Tags: a user guide](energy_source_tags_guide.md) and
[Process-Change Records](process_record.md).

* * *

## Tag entries

`water_tracers`, `energy_tracers` and `energy_source_tags` take the same kind of
entry. Each needs a unique `name` and at least one of `region` and `source`.

| Field    | Meaning                                                                                           |
|:-------- |:------------------------------------------------------------------------------------------------- |
| `name`   | what the tag is called. Appears in the output as `q_tag_<name>`, `e_tag_<name>` or `e_src_<name>` |
| `region` | where the tag starts out. A [named region](#Named-regions), or a region written out in full       |
| `source` | which process the tag follows. One label, or a list of them                                       |

What a tag starts as depends on which of the two you give it:

  - **`region` only.** Starts as the share of water (or energy) inside that
    region, and is then carried around by the flow.
  - **`source` only.** Starts at zero and accumulates only from that process.
  - **Both.** Starts at zero and accumulates from that process, but only inside
    that region. Useful for asking "how much of the evaporation happened in the
    tropics?".

A tag's name becomes part of its diagnostics' names, so some names are reserved:

  - `res` is reserved in all three families. It is the closure residual,
    `q_tag_res`, `e_tag_res` or `e_src_res`.
  - A `water_tracers` name may not begin with `fix_`, `upfix_`, `inc_`, `rtag_`,
    `stag_`, `fixgross_`, `fixcount_`, `upfixgross_`, `upfixcount_`, `led_` or
    `aud_`, and may not begin with `negative`. `fix_` begins the repair ledger
    `q_tag_fix_<name>`, `negative` the diagnostic `q_tag_negative`, and `aud_`
    the microphysics audit fields `q_rtag_aud_<name>` and `q_stag_aud_<name>`.
    The others begin other ledgers or are held.
  - An `energy_source_tags` name may not begin with `fix_`, `fixgross_`,
    `fixcount_`, `inc_` or `led_`.
  - The underscore is part of each prefix, so `fixed`, `income` and `rtagged`
    are allowed.

!!! warning "Use exactly one set of regions per run"

    The closure diagnostics `q_tag_res`, `e_tag_res` and `e_src_res` add up
    **all** the tags that have a region and no source. They are meaningful only
    if those tags cover the domain exactly once, such as a region and its
    complement, `tropics` and `extratropics`. Two overlapping decompositions in
    one run make the residual meaningless. A warning is printed at startup when
    the masks do not add up to 1.

### Named regions

| Name           | Where                                       |
|:-------------- |:------------------------------------------- |
| `everywhere`   | the whole domain                            |
| `tropics`      | within 20° of the equator, smoothed over 2° |
| `extratropics` | the exact complement of `tropics`           |

`tropics` and `extratropics` are a valid pair for the closure diagnostics.

### Regions written out in full

Anything else is written as a mapping with a `type`. Edges are smoothed with a
`tanh` over the given `width` rather than being sharp.

| `type`          | Required                                                      | Meaning                                        |
|:--------------- |:------------------------------------------------------------- |:---------------------------------------------- |
| `everywhere`    | none                                                          | the whole domain                               |
| `tanh_altitude` | `z_center`, `width` (m)                                       | above a height                                 |
| `tanh_latitude` | `lat_bound`, `width` (degrees)                                | within `lat_bound` of the equator              |
| `tanh_box`      | `lon_min`, `lon_max`, `lat_min`, `lat_max`, `width` (degrees) | a longitude–latitude box                       |
| `tanh_polygon`  | `vertices` (a list of `[lon, lat]` pairs), `width` (degrees)  | a polygon spanning less than 180° of longitude |

Every type except `everywhere` also takes `inside: false` (`above: false` for
`tanh_altitude`) to select the exact complement instead. `tanh_latitude`,
`tanh_box` and `tanh_polygon` need spherical geometry.

```yaml
energy_tracers:
  - name: stratosphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0}
  - name: troposphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0, above: false}
```

Parameters that describe no region are refused at startup, with a message that
names the key:

| Key                  | Must be                        | Why                                                                                                                                                                                                                                                          |
|:-------------------- |:------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `width`              | greater than zero              | Zero leaves the edge undefined: a point exactly on it gives `NaN`. A negative width complements `tanh_altitude` and `tanh_polygon`, makes a `tanh_latitude` band negative, and is silently ignored by `tanh_box`.                                            |
| `lat_bound`          | greater than zero              | The band is `abs(lat) ≤ lat_bound`. Zero is empty, and a negative bound makes the mask negative.                                                                                                                                                             |
| `lat_min`, `lat_max` | `lat_min` below `lat_max`      | Equal bounds give a mask of zero, and reversed bounds a negative one.                                                                                                                                                                                        |
| `lon_min`, `lon_max` | a box must span some longitude | Longitudes are compared modulo 360°, so a box may cross the antimeridian (`lon_min: 170`, `lon_max: -170` is 20° wide). A full turn looks like no turn, so `lon_min: -180`, `lon_max: 180` is refused. For a band over every longitude, use `tanh_latitude`. |
| `vertices`           | at least 3 `[lon, lat]` pairs  | Fewer do not enclose an area.                                                                                                                                                                                                                                |

!!! warning "Smoothing is required, not cosmetic"

    In longitude and latitude (`tanh_latitude`, `tanh_box`, `tanh_polygon`,
    whose `width` is in degrees), a sharp 0/1 mask produces Gibbs oscillations
    in the spectral-element horizontal discretization. They contaminate the
    tagged fields from the first step. Set `width` comparable to, or larger
    than, the horizontal grid spacing. This matters most for `tanh_polygon`,
    where the vertices often come from a tool that rasterizes sharply. See
    [Tagged Energy Tracers](tagged_tracers.md) for turning an IPCC AR6 reference
    region into a config block.

    `tanh_altitude` is different. Its `width` is in metres and the vertical grid
    is finite-difference, so there is no ringing. A transition thinner than the
    local layer spacing is not resolved, so set `width` at least as thick as the
    layers the edge crosses.

* * *

## Checking closure while a run goes

Closure means that the tags still add up to the field they split. The
`q_tag_res`, `e_tag_res` and `e_src_res` diagnostics give it as a 3-D field to
look at afterwards. A closure check reduces it to a few numbers and writes them
to a table every `period`, so you can see drift while the run goes. The check
adds no tendency. It reads the state and writes a table.

```yaml
water_closure_check:
  period: "1days"        # how often to check
  tolerance: 1.0e-10     # warn above this relative residual
  void_above: 1.0        # above this, warn once and mark every later row void
  abort_above: ~         # end the run above this one; never, by default
  audit: false           # write the second table
  negative_water_void_above: 1.0e-4  # water only
energy_closure_check:
  tolerance: 1.0e-6
energy_source_closure_check:
  spin_up: "1hours"
```

There is one block per family. Every block is optional, and every key in it is
optional. `water_closure_check` and `energy_closure_check` are off by default.
`energy_source_closure_check` is on by default whenever the tags include a
region tag without a `source`, and `false` switches it off. A check without its
tracer family is refused at startup, and so is a family whose entries all carry
a `source`, because there is nothing to close against.

| Key                         | Meaning                                                                                                                                                                      | Water   | `energy_tracers` | Energy source tags                                                     |
|:--------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------- |:---------------- |:---------------------------------------------------------------------- |
| `period`                    | how often to check                                                                                                                                                           | `1days` | `1days`          | `1days`                                                                |
| `tolerance`                 | warn when `gross_relative` passes it. `~`: never warn about the residual                                                                                                     | `1e-10` | `1e-6`           | per transport: `tracer` 1.0, `enthalpy` 0.1, `enthalpy_increment` 0.01 |
| `void_above`                | warn once, then mark this and every later row void. The run goes on                                                                                                          | `1.0`   | none             | none                                                                   |
| `abort_above`               | end the run                                                                                                                                                                  | none    | none             | none                                                                   |
| `spin_up`                   | take a reference residual at this time, and report the residual since then beside it                                                                                         | none    | none             | `1hours`                                                               |
| `audit`                     | write the audit table                                                                                                                                                        | `false` | `false`          | `false`                                                                |
| `throughput_tolerance`      | warn when the gross residual over the gross source throughput since the start passes it. Needs `energy_source_tag_ledger_per_tag: true` and region tags whose masks sum to 1 |         |                  | none                                                                   |
| `negative_water_void_above` | mark rows void when the parent's negative water over its water passes it. `~` switches it off                                                                                | `1e-4`  |                  |                                                                        |

The defaults are starting points. Set your own from the first run's closure
table: a tolerance a little above the level your configuration settles at turns
the warning into news. The water tags ride the same transport operators as
`ρq_tot` apart from the implicit-vs-explicit vertical advection split, so their
residual is small. The energy families get larger residuals by design.
`ρe_tot` is moved as enthalpy, and vertically on the implicit path. The
`energy_tracers` tags move as passive tracers and receive no EDMFX sub-grid
mass flux. The energy source tags' residual depends on their
`energy_source_tag_transport`, which is why their default tolerance does too.
See [Energy Source Tags](energy_source_tags.md).

Water has a void level of 1.0 because a set of non-negative tags inside a
non-negative parent misses it by at most the parent itself. Passing 1 means the
tags hold water that is not there, or the parent has gone negative. Both energy
families have none. Their residual is divided by `∫|ρe_tot|`, whose zero is a
convention, so a shifted energy reference can make a ratio large with nothing
wrong. Writing `void_above: ~` turns the water default off.

### The closure table

Each check writes `<family>_tag_closure.csv` to the output directory:
`water_tag_closure.csv`, `energy_tag_closure.csv` or
`energy_source_tag_closure.csv`. All integrals are over the whole domain.

| Column                                                                                                                            | What it is                                                                                                  |
|:--------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------- |
| `time`                                                                                                                            | simulation time, in s                                                                                       |
| `total`, `tagged`                                                                                                                 | `∫parent dV` and `∫Σ tags dV`                                                                               |
| `residual`, `relative`                                                                                                            | `total - tagged`, and it over `scale`                                                                       |
| `gross_residual`, `gross_relative`                                                                                                | `∫abs(parent - Σ tags) dV`, and it over `scale`                                                             |
| `scale`                                                                                                                           | `∫abs(parent) dV`                                                                                           |
| `nonpositive_fraction`                                                                                                            | volume fraction where the parent is zero or negative                                                        |
| `residual_at_spin_up`, `residual_since_spin_up`, `relative_since_spin_up`                                                         | with `spin_up`: the reference, the residual since, and it over `scale`. `NaN` before the reference is taken |
| `headroom_min`, `headroom_min_z`, and with per-tag ledgers `source_partition_valid`, `source_throughput`, `gross_over_throughput` | energy source tags only. See [Energy Source Tags](energy_source_tags.md)                                    |
| `closure_void`                                                                                                                    | 1 from the first void row on, else 0. Present where the check has a void level                              |
| `negative_water_relative`, `negative_water_void`                                                                                  | water only, unless `negative_water_void_above` is `~`. See below                                            |

`gross_relative` is the number the levels are compared with. `total` and
`tagged` are global integrals, so a partition that is too high in one place and
too low in another has a signed residual of zero. Taking the absolute value
before integrating removes that cancellation, and `gross_relative` is never
smaller than `|relative|`. The signed pair says which way the leak goes.

The divisor is `scale`, not `total`, because the parent may be signed. Moist
total energy has no physical zero, so `∫ρe_tot` can be zero or negative, and a
ratio over it could never exceed a positive tolerance.

`nonpositive_fraction` is the volume fraction of the domain where the parent is
zero or negative at the row. Where it is above zero the check warns on every
row. For water, the tags' shares are undefined there. Closure cannot show this,
because complementary region tags can partition a negative parent exactly.
Volume and mass tell opposite stories on a moist sphere. Cells with no water
take up much of the volume and almost none of the mass, so the audit also gives
`nonpositive_mass_fraction`. Both read the grid-mean parent at the check's times
only, so a cell that goes negative and back between two checks does not show.

### Levels

Each level is separate from the others.

| Level                  | What passing it does                                    |
|:---------------------- |:------------------------------------------------------- |
| `tolerance`            | warns, every time                                       |
| `throughput_tolerance` | warns, every time. Energy source tags only              |
| `void_above`           | warns once, and marks this row and every later one void |
| `abort_above`          | ends the run                                            |

The check warns above `tolerance`, marks later rows void above `void_above`, and
ends the run only above an explicit `abort_above`. A diagnostic never ends a run
that the model would complete. A residual larger than the field it measures says
the tags no longer describe anything, and the void flag says so while the run
goes on.

None of the levels says a run is acceptable. `closure_void = 0` says only that
the residual has not passed `void_above`. The parent can be non-positive
earlier, which `nonpositive_fraction` shows.

The checkpoint records each family's void flag. A restarted run reads it back
before its first check, so a run split into segments marks its rows as one run
would, and a check that restarts as void says so in a warning. A checkpoint
without a family's void flag restarts that family as not void, with a warning.

### The audit table

`audit: true` writes `<family>_tag_audit.csv` beside the closure table. It splits
the residual into parts that mean different things. It is a separate file so
that switching it on does not change the closure table's columns. Join the two
on `time`. It costs a handful of extra global reductions per check.

| Column                                                                                        | What it is                                                                               |
|:--------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------- |
| `untagged`                                                                                    | `∫max(parent - Σ tags, 0)`: parent the tags do not account for                           |
| `overclaimed`                                                                                 | `∫max(Σ tags - parent, 0)`: parent the tags claim that is not there                      |
| `orphaned`                                                                                    | mass in cells whose parent is positive while every partition tag is empty                |
| `orphaned_volume_fraction`                                                                    | volume fraction of those cells                                                           |
| `nonpositive_mass`                                                                            | mass where the parent is not positive                                                    |
| `untagged_relative`, `overclaimed_relative`, `orphaned_relative`, `nonpositive_mass_fraction` | the four above over the closure table's `scale`                                          |
| `negative_water_integral`                                                                     | water only: `∫∫max(-ρq_tot, 0) dV dt` since the start of the run, in kg s                |
| `negative_water_interval`                                                                     | its change since the previous audit row, in kg s                                         |
| `negative_water_interval_mean_relative`                                                       | that change over the interval's length, over `∫ρq_tot dV` at this row                    |
| `negative_water_interval_events`                                                              | cell-steps in the interval whose end state had `ρq_tot < 0`. Exactly 0 when none had any |
| `closure_void`, `negative_water_void`                                                         | the flags, last, where they apply                                                        |

`untagged + overclaimed` is `gross_residual` to reduction round-off. The two
mean opposite things. Untagged water has an origin that nothing claims to know.
Overclaimed water is the tags asserting water that does not exist, which is the
direction a runaway takes. `orphaned` shows whether provenance is gone rather
than drifting: nothing re-tags an emptied cell, so its water stays anonymous. It
counts total loss only, so it is a lower bound. For water, `nonpositive_mass` is
`∫abs(min(ρq_tot, 0)) dV` of the raw `ρq_tot`. The energy source tags add
columns of their own. See [Energy Source Tags](energy_source_tags.md).

### The parent's negative water

`ρq_tot` is not kept non-negative by default (`tracer_nonnegativity_method: ~`).
The water tags partition `max(ρq_tot, 0)`. Where `ρq_tot` is negative they
partition zero, and `q_tag_negative` holds the parent's negative water. Under
`water_tag_precipitation` the same rule applies to each part separately.

The closure check compares the tags with `max(ρq_tot, 0)`. So a parent whose own
water has gone negative can close perfectly, with `closure_void` at 0. The water
check therefore also reads the raw `ρq_tot`.

`negative_water_relative` is `∫max(-ρq_tot, 0) dV / ∫ρq_tot dV` at the row. It
is 0 where no cell is negative, and `Inf` where some cell is negative and
`∫ρq_tot` is not positive. `negative_water_void_above` is the level for it,
`1e-4` by default. The check compares the ratio with it at every row and at the
end of every accepted step. The first time it passes, the check warns once. From
then on `negative_water_void` is 1 on every row of both tables, also after the
parent recovers. `~` drops both columns and the per-step check. Zero marks the
rows at the first negative water. Only `water_closure_check` takes the key.

Because the check also runs after every accepted step, an excursion between two
rows still sets the flag, and the next row is the first one marked. That row's
own `negative_water_relative` can be below the level. A crossing after the last
row shows in the warning and the checkpoint but in no table, so choose a `t_end`
that is a multiple of `period`. The check reads the state at the end of each
accepted step, not within a step.

The flag and the accumulator behind the audit's `negative_water_*` columns live
in the cache and the checkpoint, not in the model's state. A checkpoint without
the flag restarts with the flag false, with a warning. A checkpoint without the
accumulator starts it at zero, with a warning, and the `negative_water_*`
columns then cover this segment only. The per-cell diagnostics
`q_tag_negative_integral`, in kg s m⁻³, and `q_tag_negative_events` are opt-in.

The per-step check costs one global sum after every accepted step, and a second
one after a step that ends with negative water somewhere. Under MPI both are
collective. With the key at `~`, the step does neither.

* * *

## Worked examples in this repository

  - `config/model_configs/passive_stratospheric_tracers_ci.yml`: small grid, runs in minutes
  - `config/example_configs/passive_stratospheric_tracers.yml`: a multi-year aquaplanet run
  - `config/example_configs/strat_tracers_transient_a.yml`: an explicit box list
  - `config/model_configs/baroclinic_wave_tagged_water.yml`: water tags with a closure check
  - `config/model_configs/baroclinic_wave_tagged_tracers.yml`: the same for energy tags
  - `config/model_configs/baroclinic_wave_energy_source_tags.yml`: energy source tags laid out for the per-process checks, with records

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
ClimaAtmos.negative_water_step_level
ClimaAtmos.negative_water_void_flags
ClimaAtmos.write_negative_water_void_attributes!
ClimaAtmos.restore_negative_water_void!
```
