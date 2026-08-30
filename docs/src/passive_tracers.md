# Passive Tracers

ClimaAtmos provides automatic treatment of conserved scalar tracers at two
levels: **grid-scale** (resolved) and **sub-grid scale** (SGS, inside
PROPHET updrafts). Both levels use an auto-discovery mechanism: any
field that follows the naming convention is automatically picked up for
transport, diffusion, and other generic operations; no
additional code changes are required.

## Grid-Scale Tracers

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

## SGS Tracers (PROPHET)

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

Sedimenting microphysics species are diffused with the reduced coefficient
`α_vert_diff_microphysics * K_h`; passive tracers use the unscaled `K_h`.

## Stratospheric Passive Tracers and Their Residence Times

The `passive_tracers` configuration key adds a family of inert
grid-scale tracers designed to measure how long air stays in the stratosphere.
Each tracer has

  - **one source**: a constant production of mass fraction inside one
    (latitude band × height band) region, and
  - **one sink**: relaxation to zero at and below the model tropopause.

Because the source and the sink are the only terms, a tracer whose burden has
stopped drifting satisfies `source = loss`, and its residence time is

```math
\tau = \frac{M}{S}
```

with ``M`` the global burden (kg) and ``S`` the global source rate
(kg s``^{-1}``). Multiplying ``S`` by a year gives the annual source rate the
burden is divided by.

### Source boxes sample the domain

The source regions are small boxes that **sample** the domain above the
tropopause rather than tiling it. By default there are 6 latitude boxes 10°
wide, centred from 75°S to 75°N, crossed with 8 height boxes 2 km deep stacked
every 5 km from the local tropopause up to 37 km above it.

Keeping a box small is the point: a tracer emitted over a deep layer or a wide
latitude range reports a residence time averaged over conditions that can
differ by years, and that average is not the residence time of anywhere in
particular. The boxes are therefore allowed to leave gaps between them. They
may never **overlap**, though — that would make a point feed two tracers at
once — and the constructor refuses a `latitude_width` wider than the spacing
between boxes, or a `band_depth` deeper than `band_spacing`.

Measuring source heights from the local tropopause
(`heights_from: "tropopause"`, the default) is what makes
the coverage complete: the tropopause is 8 km lower at the poles than in the
tropics, so bands at fixed altitude would either leave the extratropical
lowermost stratosphere without a source or put the lowest tropical band below
the tropopause. Set `heights_from: "altitude"` for bands at fixed heights above
sea level instead.

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

Every key, its default, and the named regions are listed in
[Configuring Tracers](tracer_configuration.md).

Tracer `(i, k)` is `Y.c.ρq_gas_y<i>z<k>` and is output as `q_gas_y<i>z<k>`.

### Boxes that are not a latitude × height grid

The keys above describe a latitude × height outer product with one width, one
depth and one spacing. When that is the wrong shape — bands at uneven spacing,
boxes of differing depth, or a grid with some combinations left out because
they would sit below the tropopause — list the boxes explicitly instead:

```yaml
passive_tracers:
  heights_from: "altitude"
  release_boxes:
    - {latitude: [-85.0, -75.0], height: [9989.7, 10404.8]}
    - {latitude: [75.0, 85.0], height: [9989.7, 10404.8]}
    - {latitude: [-5.0, 5.0], height: [27896.0, 28623.5]}
```

`latitude` is `[southern edge, northern edge]` in degrees, and `height` is
`[bottom, top]` in m, measured from the reference chosen by `heights_from`. To
make a box span exactly one model layer,
give it that layer's face heights; they follow from `z_max`, `z_elem`,
`dz_bottom` and `z_stretch`, and a box thinner than the local layer would
otherwise emit into whichever cell centres it happened to capture, or none.

Setting both `release_boxes` and `release_grid` is an error. Boxes are named by
numbering the distinct latitude and height ranges in order of first appearance,
so an outer product spelled out box by box reproduces the familiar `y<i>z<k>`
numbering. For an irregular list those indices are labels rather than grid
coordinates, and the box edges written into every row of the budget table — not
the names — are what identifies a box.

Boxes may overlap. The tracers are independent, so a point inside two of them
feeds both and each budget stays self-consistent; a box spanning the whole
domain, used as a bulk reference, deliberately encloses the sampled boxes. Two
boxes sharing both a latitude and a height range are refused, because they would
claim the same name.

`production_rate` sets the magnitude of the tracers but **not** their residence
times: the tracers are linear, so burden and source scale together and only
their ratio is reported.

### The lower boundary

The tropopause is diagnosed online from the model temperature with the WMO
lapse-rate definition — the lowest level whose lapse rate has fallen to 2 K/km
and stays below it, on average, over the next 2 km — and is available as the
`ztrop` diagnostic. The `tropopause` block of `passive_tracers` controls it
(`lapse_rate_threshold`, `consistency_depth`, `search_min_height` and
`search_max_height`); the search bounds keep
boundary-layer inversions and the stratopause from being mistaken for the
tropopause.

### Reading the results

Every `dt_tracer_budget`, the burden, source rate and loss rate of each tracer
are appended to `stratospheric_tracer_budget.csv` in the output directory,
together with `negative_burden`, `residence_time`, `residence_time_years`,
`residence_time_from_loss` and `imbalance = (source - loss) / source`.

`negative_burden` is the magnitude of negative tracer mass left by advection
undershoots at the box edges. The sink acts only on positive mass, so this part
counts towards `burden` but never towards `loss`: it biases `residence_time`
low and stops `imbalance` reaching zero even in equilibrium.
`burden + negative_burden` is the positive mass the sink sees, and comparing
the two says how far the bias goes.

`residence_time` and `residence_time_from_loss` are the same ratio measured
against the source and against the sink. They agree only in equilibrium, and
before it they bracket the answer from opposite sides: a tracer that is still
filling has `burden ≈ source × t`, so `residence_time` is simply the elapsed
time — a two-day run reports a two-day residence time, which is arithmetic
rather than a result — while the lagging sink makes `residence_time_from_loss`
start enormous and fall. The gap between them closing is the signal that the
run is long enough.

```
julia --project=.buildkite post_processing/tracer_residence_times.jl <output_dir>
```

prints one row per tracer and flags the tracers that are not yet in
equilibrium. Alongside it,

```
julia --project=.buildkite post_processing/plot_tracer_burdens.jl <output_dir>
```

writes `tracer_burdens.png` (300 dpi) with every tracer's burden against time
in one panel — colour for height box, dash pattern for latitude box, so the
legend stays at `n_latitude + n_height` entries rather than their product. A
burden still rising linearly is a tracer still filling; one that has levelled
off is in equilibrium. The experiment script and the CI job both write this
plot automatically at the end of a run. A tracer counts as equilibrated when
both its imbalance and its burden drift — the change in burden over the
averaging window, divided by the source — are near zero. Until then its
residence time is a lower bound, because its burden is still filling up.

Expect this to take a while: stratospheric residence times are of order 1–5
years, so a run needs several times that on top of the circulation's own
spin-up. `config/example_configs/passive_stratospheric_tracers.yml` sets up a
moist aquaplanet with RRTMGP radiation for exactly this, and
`experiments/passive_stratospheric_tracers.jl` runs it; resubmitting the same
configuration continues from the newest checkpoint.

`config/model_configs/passive_stratospheric_tracers_ci.yml` is the two-day,
9-tracer version that CI runs. Its residence times are meaningless — nothing is
near equilibrium after two days — but it exercises the state assembly, the
tropopause diagnosis, the source and sink, the budget table and the restart
path, so it is the config to reach for when changing any of them.

!!! note "Cost"

    The tracers are grid-scale only — they get no SGS updraft counterparts,
    which would multiply the EDMF state by the number of source regions. Even
    so, one prognostic tracer per source box is a large
    state: the default 6 × 8 = 48 tracers add 48 fields to `Y.c` and, with
    `implicit_diffusion: true`, 48 tridiagonal blocks to the Jacobian.

    Compilation, not memory, is what limits the grid. Setup is almost entirely
    compile time and grows roughly as `N^2.9` in the tracer count, measured
    with `perf/tracer_scaling.jl` and paid again on every launch and restart:
    about 17 minutes at 24 tracers against over two hours at 48. Run time per
    step is linear instead, about 44 ms per tracer on a small CPU grid, so the
    tracers dominate a step long before they dominate anything else. Because
    they are inert and only `ρq_tot` feeds back on the dynamics, several runs
    covering different slices of the source grid cost little more in total than
    one run covering all of it, and much less in wall clock. Setting
    `implicit_diffusion: false` removes the per-tracer Jacobian blocks if the
    cost is still binding.

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

Adding a tracer is developer territory; see
[Adding a Passive Tracer](extending_tracers.md) in the Developer Guide.
