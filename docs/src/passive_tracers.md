# Tracers

ClimaAtmos provides automatic treatment of conserved scalar tracers at two
levels: **grid-scale** (resolved) and **sub-grid scale** (SGS, inside
prognostic EDMF updrafts). Both levels use an auto-discovery mechanism: any
field that follows the naming convention is automatically picked up for
transport, diffusion, and other generic operations — no
additional code changes are required.

## Grid-Scale Tracers

Grid-scale tracers are density-weighted scalars ``\rho \chi`` stored at cell
centers in the prognostic state `Y.c`.

### Naming convention

A grid-scale tracer is identified by a name that starts with `ρ` followed
by the scalar name, e.g. `ρq_tot`, `ρq_lcl`, `ρn_rai`. The utility function
`gs_tracer_names(Y)` discovers all such tracers automatically by inspecting
`Y.c` and excluding non-tracer fields (`ρ`, `ρe_tot`, `uₕ`, `ρtke`,
`sgsʲs`).

### Automatically handled operations

| Operation            | Description                                            |
|:-------------------- |:------------------------------------------------------ |
| Horizontal advection | Flux-form divergence of ``\rho \chi \boldsymbol{u}_h`` |
| Vertical advection   | Upwinded vertical transport                            |
| Vertical diffusion   | Eddy-diffusivity-based mixing                          |
| Hyperdiffusion       | 4th-order ``\nabla^4`` stabilization with DSS          |

The iteration utility `foreach_gs_tracer(f, Y...)` applies a function `f` to
each discovered tracer.

## SGS Tracers (Prognostic EDMF)

When prognostic EDMF is enabled, each updraft carries its own set of scalar
fields inside `Y.c.sgsʲs.:(j)`. The utility function `sgs_tracer_names(Y)`
discovers all scalars in the first updraft (`Y.c.sgsʲs.:(1)`) and excludes
the core EDMF variables `ρa`, `mse`, and `q_tot`, which receive
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

This pairing is enforced by `get_ρχ_name(χ_name)` which constructs
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
| SGS diffusive flux (grid mean)                  | `edmfx_sgs_flux.jl`     | `for χ_name in sgs_tracer_names(Y)` |
| Updraft vertical diffusion                      | `mass_flux_closures.jl` | `for χ_name in sgs_tracer_names(Y)` |
| Updraft constraint enforcement                  | `mass_flux_closures.jl` | `for χ_name in sgs_tracer_names(Y)` |
| Rayleigh sponge damping                         | `remaining_tendency.jl` | `for χ_name in sgs_tracer_names(Y)` |

All SGS tracers (cloud species and precipitation alike) receive the same
reduced vertical diffusion coefficient (`α_vert_diff_microphysics`).

## Stratospheric Passive Tracers and Their Lifetimes

`chemistry_model: "stratospheric_passive_tracers"` adds a family of inert
grid-scale tracers designed to measure how long air stays in the stratosphere.
Each tracer has

  - **one source**: a constant production of mass fraction inside one
    (latitude band × height band) region, and
  - **one sink**: relaxation to zero at and below the model tropopause.

Because the source and the sink are the only terms, a tracer whose burden has
stopped drifting satisfies `source = loss`, and its lifetime is

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
latitude range reports a lifetime averaged over conditions that can differ by
years, and that average is not the lifetime of anywhere in particular. The
boxes are therefore allowed to leave gaps between them. They may never
**overlap**, though — that would make a point feed two tracers at once — and
the constructor refuses a `latitude_width` wider than the spacing between
boxes, or a `band_depth` deeper than `band_spacing`.

Measuring source heights from the local tropopause
(`tracer_source_height_coordinate: "tropopause"`, the default) is what makes
the coverage complete: the tropopause is 8 km lower at the poles than in the
tropics, so bands at fixed altitude would either leave the extratropical
lowermost stratosphere without a source or put the lowest tropical band below
the tropopause. Set `"altitude"` for bands at fixed heights above sea level
instead.

| Configuration key                     | Meaning                                              |
|:------------------------------------- |:---------------------------------------------------- |
| `tracer_source_latitude_bands`        | Number of latitude boxes (default 6)                 |
| `tracer_source_latitude_width`        | Width of each latitude box, in degrees (default 10)  |
| `tracer_source_height_bands`          | Number of height boxes (default 8)                   |
| `tracer_source_band_depth`            | Depth of each height box, in m (default 2000)        |
| `tracer_source_band_spacing`          | Distance between box bottoms, in m (default 5000)    |
| `tracer_source_lowest_band_base`      | Base of the lowest box above the reference, in m     |
| `tracer_source_height_coordinate`     | `"tropopause"` or `"altitude"`                        |
| `tracer_production_rate`              | Mass-fraction production inside a region, in s⁻¹     |
| `tracer_loss_timescale`               | E-folding time of the removal below the tropopause   |
| `dt_tracer_budget`                    | How often the budget table is written                |

Tracer `(i, k)` is `Y.c.ρq_gas_y<i>z<k>` and is output as `q_gas_y<i>z<k>`.

`tracer_production_rate` sets the magnitude of the tracers but **not** their
lifetimes: the tracers are linear, so burden and source scale together and
only their ratio is reported.

### The lower boundary

The tropopause is diagnosed online from the model temperature with the WMO
lapse-rate definition — the lowest level whose lapse rate has fallen to 2 K/km
and stays below it, on average, over the next 2 km — and is available as the
`ztrop` diagnostic. `tropopause_lapse_rate_threshold`,
`tropopause_consistency_depth`, `tropopause_search_min_height` and
`tropopause_search_max_height` control it; the search bounds keep
boundary-layer inversions and the stratopause from being mistaken for the
tropopause.

### Reading the results

Every `dt_tracer_budget`, the burden, source rate and loss rate of each tracer
are appended to `stratospheric_tracer_budget.csv` in the output directory,
together with `lifetime`, `lifetime_years`, `lifetime_from_loss` and
`imbalance = (source - loss) / source`.

`lifetime` and `lifetime_from_loss` are the same ratio measured against the
source and against the sink. They agree only in equilibrium, and before it they
bracket the answer from opposite sides: a tracer that is still filling has
`burden ≈ source × t`, so `lifetime` is simply the elapsed time — a two-day run
reports a two-day lifetime, which is arithmetic rather than a result — while
the lagging sink makes `lifetime_from_loss` start enormous and fall. The gap
between them closing is the signal that the run is long enough.

```
julia --project=.buildkite post_processing/tracer_lifetimes.jl <output_dir>
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
plot automatically at the end of a run. A tracer counts as equilibrated when both its imbalance and its
burden drift — the change in burden over the averaging window, divided by the
source — are near zero. Until then its lifetime is a lower bound, because its
burden is still filling up.

Expect this to take a while: stratospheric residence times are of order 1–5
years, so a run needs several times that on top of the circulation's own
spin-up. `config/example_configs/passive_stratospheric_tracers.yml` sets up a
moist aquaplanet with RRTMGP radiation for exactly this, and
`experiments/passive_stratospheric_tracers.jl` runs it; resubmitting the same
configuration continues from the newest checkpoint.

`config/model_configs/passive_stratospheric_tracers_ci.yml` is the two-day,
9-tracer version that CI runs. Its lifetimes are meaningless — nothing is near
equilibrium after two days — but it exercises the state assembly, the
tropopause diagnosis, the source and sink, the budget table and the restart
path, so it is the config to reach for when changing any of them.

!!! note "Cost"

    The tracers are grid-scale only — they get no SGS updraft counterparts,
    which would multiply the EDMF state by the number of source regions. Even
    so, `n_latitude_bands × n_height_bands` prognostic tracers is a large
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

## Adding a New Passive Tracer

To add a new passive tracer `A` that is transported through the full
grid-scale + SGS system, the only changes needed are:

### Step 1: Add `ρA` to the grid-scale prognostic state

In `prognostic_variables.jl`, add `ρA` to the center variables:

```julia
ρA = ρ * physical_state.A
```

This gives automatic grid-scale advection, diffusion, hyperdiffusion,
and surface flux — all handled by `foreach_gs_tracer`.

### Step 2: Add `A` to the SGS updraft state

In `prognostic_variables.jl`, add `A` to the SGS struct:

```julia
sgsʲs = uniform_subdomains((; ρa, mse, q_tot, A = physical_state.A), turbconv_model)
```

This gives automatic SGS entrainment, mass flux, diffusive flux,
vertical diffusion, updraft constraints, advection, and sponge damping —
all handled by `sgs_tracer_names`.

### Step 3: Initial condition

Set the initial value of `A` in the setup file (e.g. `Bomex.jl`):

```julia
A = FT(1.0)  # constant initial concentration
```

That's it — no tendency code changes needed.

### Step 4 (if using implicit solver): Update the Jacobian

The implicit solver's Jacobian (`manual_sparse_jacobian.jl`) uses hardcoded
tracer lists for performance reasons (`unrolled_foreach` with compile-time
tuples). Adding a new tracer to the Jacobian requires manually editing
several locations in `jacobian_cache` (sparsity pattern) and
`update_jacobian!` (numeric updates). Search for existing microphysics
tracer names (e.g. `q_lcl`, `q_rai`) to find each block and add the new
tracer alongside them.

Key locations to update:

| Location                                                                 | What to add                                |
|:------------------------------------------------------------------------ |:------------------------------------------ |
| `condensate_names` / `condensate_mass_names` in `jacobian_cache`         | `@name(c.ρA)`                              |
| `sgs_condensate_names` / `sgs_condensate_mass_names` in `jacobian_cache` | `@name(c.sgsʲs.:(1).A)`                    |
| SGS vertical diffusion block                                             | Append to `sgs_microphysics_tracers` tuple |
| SGS entrainment block                                                    | Append to `sgs_microphysics_tracers` tuple |
| Grid-mean + SGS mass flux block                                          | Append to `microphysics_tracers` tuple     |

For **moisture species** that affect pressure, buoyancy, or have a
sedimentation velocity, additional blocks need updating (pressure
gradient, sedimentation, SGS pressure/buoyancy). Search for existing
species like `q_rai` to locate each block.

!!! note

    A passive tracer that doesn't affect thermodynamics and has no
    sedimentation can often run without Jacobian entries. The implicit
    solver will still converge, just more slowly for that variable.

### Operations that remain manual

| Operation                         | Reason                       |
|:--------------------------------- |:---------------------------- |
| Initial / boundary conditions     | Problem-specific             |
| Source / sink terms               | Physics-specific             |
| Jacobian blocks (implicit solver) | See Step 4 above             |
| Diagnostics output                | User must define short names |

## Implementation details

The auto-discovery relies on two key patterns:

 1. **Field-name predicates** — `_is_sgs_tracer_name` and
    `is_ρ_weighted_name` filter the top-level field names at the type
    level, enabling `unrolled_filter` to resolve the tracer list with
    zero runtime cost.

 2. **`MatrixFields.get_field` + `FieldName`** — tracer fields are
    accessed via `MatrixFields.get_field(Y.c.sgsʲs.:(1), χ_name)` using
    the discovered `FieldName`. This is equivalent to direct property
    access (e.g. `Y.c.sgsʲs.:(1).q_lcl`) and compiles to the same code.
