# Configuring Tracers

This page is the configuration reference for the three kinds of tracer you can
switch on from a YAML file. It says what to write. The pages it links to say how
each one works and what its output means.

You do not need to write any Julia code, and you do not need to understand the
implementation to use these. Start from a block on this page, change the
numbers, and run.

## Which one do I want?

| I want to know…                          | Use                                       | Adds                                |
|:---------------------------------------- |:----------------------------------------- |:----------------------------------- |
| how long air stays in the stratosphere   | [`passive_tracers`](@ref passive_tracers) | one inert tracer per release region |
| where the water at a point came from     | [`water_tracers`](@ref water_tracers)     | one field `ρq_tag_<name>` per tag   |
| what heated or cooled the air at a point | [`energy_tracers`](@ref energy_tracers)   | one field `ρe_tag_<name>` per tag   |

The three are independent. You can switch on any one of them, or all three, in
the same run. Each is off by default and costs nothing when off.

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
burden has stopped drifting has a lifetime of `burden / source` — which is how
long air released in that region stays in the stratosphere.

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
lifetimes are: burden and source are both proportional to it, and only their
ratio is reported. Leave it alone unless the numbers are inconveniently small.

`loss_timescale` should be short compared with the lifetimes you are measuring
(years) and long compared with the timestep. It cannot be infinite — that would
remove the tracers' only sink, so they would never settle.

The budget table that the lifetimes come from is written every
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

| Group       | `source` label          | Process                                                      |
|:----------- |:----------------------- |:------------------------------------------------------------ |
| `radiative` | `radiation`             | all radiation modes (RRTMGP, gray, DYCOMS, TRMM\_LBA, ISDAC) |
| `turbulent` | `surface_flux`          | turbulent surface energy flux                                |
| `moist`     | `microphysics`          | microphysics energy sources, when stepped explicitly         |
| `moist`     | `precipitation`         | energy carried out of a level by falling precipitation       |
| `forcing`   | `held_suarez`           | Held–Suarez relaxation forcing                               |
| `forcing`   | `large_scale_advection` | prescribed large-scale advective forcing                     |
| `forcing`   | `subsidence`            | prescribed large-scale subsidence                            |
| `forcing`   | `external_forcing`      | externally prescribed (e.g. GCM-driven) forcing              |

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
below reduce it to one number and write it to a table as the run goes, so you
can see drift without waiting for the run to end.

```yaml
water_closure_check:
  period: "1days"        # how often to check
  tolerance: 1.0e-10     # warn above this relative residual

energy_closure_check:
  period: "1days"
  tolerance: 1.0e-6
```

Both keys are optional inside each block, and both blocks are off by default.
Each writes `water_tag_closure.csv` / `energy_tag_closure.csv` to the output
directory, with columns `time, total, tagged, residual, relative`, where
`relative = (total - tagged) / total`.

Exceeding the tolerance **warns and keeps running**. Closure drift is something
you want to watch grow, and ending a multi-year integration over it costs more
than it saves.

The check adds no tendency. It only reads the state and writes a table, so
switching it on does not change what the simulation produces.

### Why the two tolerances differ

The default for energy is looser than the one for water by four orders of
magnitude, and that is not arbitrary. The water tags ride the same transport
operators as `ρq_tot` apart from the implicit-versus-explicit vertical
advection split, so very little escapes them. The energy tags never receive
implicit transport or EDMFX sub-grid mass fluxes at all — that is deliberate,
because each tag is already transported in its own right and attributing the
`ρe_tot` version on top would count it twice — so a visibly larger residual is
the expected, correct behaviour, not a bug.

!!! tip "Calibrate on your own configuration"

    Treat both defaults as starting points. Run once, read the `relative`
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

```yaml
energy_tracers:
  - name: stratosphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0}
  - name: troposphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0, above: false}
```

!!! warning "Smoothing is required, not cosmetic"

    A sharp 0/1 mask produces Gibbs oscillations in the spectral-element
    discretization that contaminate the tagged fields from the first step. Set
    `width` comparable to, or larger than, the horizontal grid spacing. This
    matters most for `tanh_polygon`, where the vertices often come from a
    tool that rasterizes sharply — see
    [Tagged Energy Tracers](tagged_tracers.md) for turning an IPCC AR6
    reference region into a config block.

* * *

## Moving from the old configuration keys

These keys were replaced. Using one now raises an error naming its replacement,
so a configuration can be migrated from the error message alone.

| Old key                                          | Now                                                 |
|:------------------------------------------------ |:--------------------------------------------------- |
| `tagged_tracers`                                 | `energy_tracers` (same entries)                     |
| `tagged_water`                                   | `water_tracers` (same entries)                      |
| `chemistry_model: stratospheric_passive_tracers` | `passive_tracers`                                   |
| `tracer_source_latitude_bands`                   | `passive_tracers: release_grid: latitude_bands`     |
| `tracer_source_latitude_width`                   | `passive_tracers: release_grid: latitude_width`     |
| `tracer_source_height_bands`                     | `passive_tracers: release_grid: height_bands`       |
| `tracer_source_band_depth`                       | `passive_tracers: release_grid: height_depth`       |
| `tracer_source_band_spacing`                     | `passive_tracers: release_grid: height_spacing`     |
| `tracer_source_lowest_band_base`                 | `passive_tracers: release_grid: lowest_height`      |
| `tracer_source_boxes`                            | `passive_tracers: release_boxes`                    |
| `tracer_source_height_coordinate`                | `passive_tracers: heights_from`                     |
| `tracer_production_rate`                         | `passive_tracers: production_rate`                  |
| `tracer_loss_timescale`                          | `passive_tracers: loss_timescale`                   |
| `tropopause_lapse_rate_threshold`                | `passive_tracers: tropopause: lapse_rate_threshold` |
| `tropopause_consistency_depth`                   | `passive_tracers: tropopause: consistency_depth`    |
| `tropopause_search_min_height`                   | `passive_tracers: tropopause: search_min_height`    |
| `tropopause_search_max_height`                   | `passive_tracers: tropopause: search_max_height`    |

`dt_tracer_budget` is unchanged.

Boxes changed shape as well as place. Four keys per box became two pairs:

```yaml
# before
tracer_source_boxes:
  - {latitude_lower: -85.0, latitude_upper: -75.0, height_lower: 9989.7, height_upper: 10404.8}

# after
passive_tracers:
  release_boxes:
    - {latitude: [-85.0, -75.0], height: [9989.7, 10404.8]}
```

`chemistry_model` still exists, and still takes `passive` for the gas-phase
chemistry hook that carries the tracer `q_gas_A`. It no longer takes
`stratospheric_passive_tracers`.

## Worked examples in this repository

  - `config/model_configs/passive_stratospheric_tracers_ci.yml` — small grid, runs in minutes
  - `config/example_configs/passive_stratospheric_tracers.yml` — a multi-year aquaplanet run
  - `config/example_configs/strat_tracers_transient_a.yml` — an explicit box list
  - `config/model_configs/baroclinic_wave_tagged_water.yml` — water tags with closure checks
  - `config/model_configs/baroclinic_wave_tagged_tracers.yml` — energy tags with closure checks

## API

```@docs
ClimaAtmos.NAMED_TAG_REGIONS
ClimaAtmos.tag_region_from_config
ClimaAtmos.tag_sources_from_config
ClimaAtmos.passive_tracer_model
ClimaAtmos.energy_tracer_tuple
ClimaAtmos.water_tracer_tuple
ClimaAtmos.RETIRED_CONFIG_KEYS
ClimaAtmos.DEFAULT_CLOSURE_TOLERANCES
ClimaAtmos.closure_check_from_config
ClimaAtmos.tag_closure
ClimaAtmos.tag_closure_callback
```
