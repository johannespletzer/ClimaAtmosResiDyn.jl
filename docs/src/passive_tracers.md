# Passive Tracers

ClimaAtmos provides automatic treatment of conserved scalar tracers at two
levels: **grid-scale** (resolved) and **sub-grid scale** (SGS, inside
PROPHET updrafts). Both levels use an auto-discovery mechanism: any
field that follows the naming convention is automatically picked up for
transport, diffusion, and other generic operations; no
additional code changes are required.

## Grid-scale tracers

Grid-scale tracers are density-weighted scalars ``\rho \chi`` stored at cell
centers in the prognostic state `Y.c`.

### Naming convention

A grid-scale tracer is identified by a name that starts with `ρ` followed
by the scalar name, e.g. `ρq_tot`, `ρq_lcl`, `ρn_rai`. The utility function
`gs_tracer_names(Y)` discovers all such tracers automatically by keeping only
top-level `ρ`-prefixed names in `Y.c` (the `is_ρ_weighted_name` predicate,
which already excludes `uₕ` and `sgsʲs`) and then excluding `ρ`, `ρe_tot`,
and `ρtke`.

### Automatically handled operations

| Operation            | Description                                            |
|:-------------------- |:------------------------------------------------------ |
| Horizontal advection | Flux-form divergence of ``\rho \chi \boldsymbol{u}_h`` |
| Vertical advection   | Upwinded vertical transport                            |
| Vertical diffusion   | Eddy-diffusivity-based mixing                          |
| Hyperdiffusion       | 4th-order ``\nabla^4`` stabilization with DSS          |

The iteration utility `foreach_gs_tracer(f, Y...)` applies a function `f` to
each discovered tracer.

## SGS tracers (PROPHET)

When PROPHET is enabled, each updraft carries its own set of scalar
fields inside `Y.c.sgsʲs.:(j)`. The utility function `sgs_tracer_names(Y)`
discovers all scalars in the first updraft (`Y.c.sgsʲs.:(1)`) and excludes
the core PROPHET variables `ρa`, `mse`, and `q_tot`, which receive
physics-specific treatment.

### Naming convention

An SGS tracer `χ` in `Y.c.sgsʲs.:(j)` maps to a grid-scale
density-weighted counterpart `ρχ` in `Y.c`. For example:

| SGS field (in `sgsʲs.:(j)`) | Grid-scale field (in `Y.c`) |
|:--------------------------- |:--------------------------- |
| `q_lcl`                     | `ρq_lcl`                    |
| `q_rai`                     | `ρq_rai`                    |
| `n_rai`                     | `ρn_rai`                    |
| `A` (user-defined)          | `ρA`                        |

This pairing is enforced by `get_ρχ_name(χ_name)`, which constructs
`ρχ` from `χ`.

### Automatically handled operations

The following operations are auto-discovered for all SGS tracers. No code
changes are needed when adding a new tracer:

| Operation                                       | File                    | Pattern                             |
|:----------------------------------------------- |:----------------------- |:----------------------------------- |
| Horizontal advection                            | `advection.jl`          | `for χ_name in sgs_tracer_names(Y)` |
| Vertical advection (advective form)             | `advection.jl`          | `for χ_name in sgs_tracer_names(Y)` |
| Entrainment/detrainment mixing                  | `edmfx_entr_detr.jl`    | `for χ_name in sgs_tracer_names(Y)` |
| SGS mass flux (draft + environment → grid mean) | `edmfx_sgs_flux.jl`     | `for χ_name in sgs_tracer_names(Y)` |
| SGS diffusive flux (grid mean)                  | `edmfx_sgs_flux.jl`     | `foreach_gs_tracer(Yₜ, Y)`          |
| SGS hyperdiffusion                              | `hyperdiffusion.jl`     | `for χ_name in sgs_tracer_names(Y)` |
| Updraft constraint enforcement                  | `mass_flux_closures.jl` | `for χ_name in sgs_tracer_names(Y)` |
| Rayleigh sponge damping                         | `remaining_tendency.jl` | `for χ_name in sgs_tracer_names(Y)` |

Sedimenting species (`ρq_rai`, `ρq_sno`, `ρn_rai`) do not diffuse; cloud
condensate takes a share of the aggregate `ρq_tot` diffusion rather than a flux
of its own. Passive tracers diffuse independently with the full `K_h`.

## Stratospheric Passive Tracers and Their Residence Times

The `passive_tracers` key adds inert grid-scale tracers that are released in
small boxes above the tropopause and removed below it. It is off by default.
Each tracer has

  - **one source**: a constant production of mass fraction inside one
    (latitude band × height band) box, and
  - **one sink**: relaxation to zero at and below the model tropopause.

When a tracer's burden stops changing, the source equals the loss, and burden
over source is the residence time of the air released there:

```math
\tau = \frac{M}{S}
```

with ``M`` the global burden (kg) and ``S`` the global source rate
(kg s``^{-1}``). The tracers are grid-scale only. Tracer `(i, k)` is
`Y.c.ρq_gas_y<i>z<k>` and is output as `q_gas_y<i>z<k>`.

### Source boxes

The boxes sample the domain above the tropopause and do not tile it. Keeping a
box small is the point. A tracer emitted over a deep layer or a wide latitude
range reports a residence time averaged over conditions that can differ by
years, and that average belongs to no place in particular. So the boxes leave
gaps between them.

The boxes come from one of two forms, and the two have different overlap rules.
Setting both is an error.

  - **`release_grid`** is a latitude × height outer product. The default is 6
    latitude boxes 10° wide, centred from 75°S to 75°N, crossed with 8 height
    boxes 2 km deep, stacked every 5 km from the local tropopause up to 37 km
    above it. The grid refuses overlap, because a point would then feed two
    tracers. The latitude width must not exceed the spacing between boxes, and
    the height depth must not exceed the height spacing.
  - **`release_boxes`** is an explicit list, for bands at uneven spacing, boxes
    of differing depth, or a grid with some combinations left out. A list allows
    overlap. The tracers are independent, so a point inside two boxes feeds
    both, and a box spanning the whole domain can serve as a bulk reference.
    Two boxes with the same latitude range and the same height range are
    refused, because they would claim the same name.

```yaml
passive_tracers:
  release_grid:
    latitude_bands: 6
    latitude_width: 10.0
    height_bands: 8
    height_depth: 2000.0
    height_spacing: 5000.0
  heights_from: "tropopause"
  loss_timescale: "6hours"
```

These are the YAML keys. The Julia constructor of
`ClimaAtmos.StratosphericPassiveTracers` calls the same two settings
`band_depth` and `band_spacing`. Every YAML key, its default and the named
regions are in [Configuring Tracers](tracer_configuration.md).

An explicit list gives `latitude` as `[southern edge, northern edge]` in
degrees and `height` as `[bottom, top]` in m, measured from the reference that
`heights_from` chooses:

```yaml
passive_tracers:
  heights_from: "altitude"
  release_boxes:
    - {latitude: [-85.0, -75.0], height: [9989.7, 10404.8]}
    - {latitude: [75.0, 85.0], height: [9989.7, 10404.8]}
    - {latitude: [-5.0, 5.0], height: [27896.0, 28623.5]}
```

To make a box span exactly one model layer, give it that layer's face heights.
A box thinner than the local layer emits into whichever cell centres it
happens to capture, or none. For a list the tracer names number the distinct
latitude and height ranges in order of first appearance. They are labels, and
the box edges in each row of the budget table identify a box.

`production_rate` sets the magnitude of the tracers but not their residence
times, because the tracers are linear.

With `heights_from: "tropopause"`, the default, heights are measured from the
local tropopause. That keeps the coverage complete, because the tropopause is
about 8 km lower at the poles than in the tropics. `heights_from: "altitude"`
measures from sea level instead.

### The lower boundary

The tropopause is diagnosed online from the model temperature with the WMO
lapse-rate definition. It is the lowest level whose lapse rate has fallen to
2 K/km and stays below it, on average, over the next 2 km. It is available as
the `ztrop` diagnostic. The `tropopause` block of `passive_tracers` sets
`lapse_rate_threshold`, `consistency_depth`, `search_min_height` and
`search_max_height`. The search bounds keep boundary-layer inversions and the
stratopause from being mistaken for the tropopause.

### Reading the results

Every `dt_tracer_budget`, one row per tracer is appended to
`stratospheric_tracer_budget.csv` in the output directory. The columns are:

| Column                                                             | Meaning                                            |
|:------------------------------------------------------------------ |:-------------------------------------------------- |
| `time`, `tracer`                                                   | time and tracer name                               |
| `latitude_lower`, `latitude_upper`, `height_lower`, `height_upper` | the box edges                                      |
| `burden`, `source`, `loss`                                         | the global burden, source rate and loss rate       |
| `negative_burden`                                                  | negative tracer mass left by advection undershoots |
| `residence_time`, `residence_time_years`                           | `burden / source`                                  |
| `residence_time_from_loss`                                         | `burden / loss`                                    |
| `imbalance`                                                        | `(source - loss) / source`                         |

The sink acts only on positive mass, so `negative_burden` counts towards
`burden` but never towards `loss`. It biases `residence_time` low and keeps
`imbalance` from reaching zero. `burden + negative_burden` is the positive mass
the sink sees.

`residence_time` and `residence_time_from_loss` agree only in equilibrium.
Before it they bound the answer from both sides. A tracer that is still
filling has `burden ≈ source × t`, so `residence_time` is the elapsed time and not a
result, while the lagging sink makes `residence_time_from_loss` start large and
fall. The run is long enough when the gap closes.

Two scripts read the table. `post_processing/tracer_residence_times.jl <output_dir>` prints one row per tracer and flags the tracers not in
equilibrium: those whose imbalance or burden drift is not near zero. Until then
the residence time is a lower bound. `post_processing/plot_tracer_burdens.jl <output_dir>` writes `tracer_burdens.png`. Run both with
`julia --project=.buildkite`.

Residence times are of order 1–5 years, so a run needs several times that on
top of the circulation's own spin-up.
`config/example_configs/passive_stratospheric_tracers.yml` sets up a moist
aquaplanet for this, and `experiments/passive_stratospheric_tracers.jl` runs it.
Resubmitting the same configuration continues from the newest checkpoint.
`config/model_configs/passive_stratospheric_tracers_ci.yml` is the two-day,
9-tracer version that CI runs. Its residence times are meaningless, but it
exercises the source, the sink, the budget table and the restart path.

!!! note "Cost"

    The tracers are grid-scale only, with no SGS updraft counterparts. The
    default 6 × 8 = 48 tracers add 48 fields to `Y.c` and, with
    `implicit_diffusion: true`, 48 tridiagonal blocks to the Jacobian.
    Compile time grows steeply with the tracer count and is paid on every launch
    and restart. Run time per step is linear in it.
    `implicit_diffusion: false` removes the per-tracer Jacobian blocks.

### Types and functions

```@docs
ClimaAtmos.StratosphericPassiveTracers
ClimaAtmos.SourceBox
ClimaAtmos.GeometricHeight
ClimaAtmos.TropopauseRelativeHeight
ClimaAtmos.stratospheric_tracer_symbol
ClimaAtmos.stratospheric_tracer_symbols
ClimaAtmos.write_tracer_budget!
ClimaAtmos.TropopauseParameters
ClimaAtmos.climatological_tropopause_height
ClimaAtmos.wmo_tropopause_scan_step
ClimaAtmos.set_tropopause_height!
```

## Adding a New Passive Tracer

Adding a tracer is a developer task; see
[Adding a Passive Tracer](extending_tracers.md) in the Developer Guide.
