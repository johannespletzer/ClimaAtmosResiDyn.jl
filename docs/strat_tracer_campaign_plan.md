# Transient stratospheric passive-tracer campaign, 1979–2021

## Context

Measure stratospheric residence times τ = burden/source as a function of emission
location, from a transient, realistically forced 42-year integration on Levante.

The repo provides the tracer machinery, WMO tropopause diagnosis, budget table,
ActiveLink restart detection and a working MPI stack. Missing: a source-box
specification flexible enough for this sampling design, transient forcing
configuration, a raised model top, and a job chain that actually chains.

Decisions taken with the user:

- **Free-running transient**, not nudged. ClimaAtmos has no global nudging — the
  `config == "column"` assertion in `get_external_forcing_model`
  (`src/config/model_getters.jl:836-838`) fires for the reanalysis forcing modes.
  The run reproduces stratospheric climate statistics, not the observed sequence
  of SSWs or the QBO.
- **Seasonally varying analytic zonally symmetric SST**, via the new
  `prognostic_surface: "SeasonalSST"`. See the section below for what it does and
  does not fix.
- **Sampled boxes, not a tiling**, one model layer deep.
- **1979-01-01 → 2021-01-01** (`t_end: "15341days"` = 42×365 + 11 leap days).
  ~10 y is tracer spin-up, so ~32 usable years.
- **Two members with disjoint boxes.** Compile time grows as N^2.9.

Constraints: 24,000 node-hours this quarter, 8 h wallclock per job.

## The lower boundary: seasonal, but only over ocean

`zonally_symmetric_temperature` (`src/setups/Setups.jl:208-220`) is
`271 + 29·exp(−φ²/(2·26²)) − 6.5e-3·z`, with the time argument unused. That means
a 271 K polar surface year-round and **no seasonal cycle in the lower boundary at
all**. The seasonal cycle of high-latitude surface temperature is a primary driver
of stationary-wave forcing, hence of the Brewer–Dobson circulation and the polar
vortex life cycle — which are exactly what sets stratospheric residence time.

**Resolved: adopted.** `prognostic_surface: "SeasonalSST"` now exists and both
member configs use it. It adds
`amplitude · sind(2φ) · cos(2π (day − peak_day) / 365.25)` to the annual mean —
antisymmetric between the hemispheres, zero at the equator and the poles, peaking
near ±45°, phased to the calendar through `start_date`.

It does not close the gap entirely, and the results should say so: the shape suits
an *ocean* surface, whose seasonal range really is largest in midlatitudes and
small over polar water held near freezing by ice. The much larger seasonal cycle
of land and of sea ice is still absent, because standalone ClimaAtmos models
neither. Prescribed observed surface temperature (alternative 5) remains the way
to close it.

## Grid

`h_elem: 16`, `nh_poly: 3`, `z_elem: 120`, `z_max: 80000.0`, `dz_bottom: 200.0`,
`dt: 120secs`, sponge at 60 km (`zd_rayleigh = zd_viscous = 60000.0`).

**Timestep.** Vertical advection of the passive tracers is **explicit** — only
`ρe_tot` and `ρq_tot` go through the implicit path
(`src/prognostic_equations/advection.jl:249-256`; the implicit function's own
docstring says "Vertical advection of passive tracers by the mean flow is treated
explicitly", `implicit/implicit_tendency.jl:182`). So refining the vertical grid
does tighten the tracer CFL. Comparing `dt/Δz` against the two shipped configs
that already run this tendency:

| config | 0.5 km | 2 km | 5 km | 10 km | 15 km |
|---|---|---|---|---|---|
| `passive_stratospheric_tracers.yml` (ze63, dt 300) | 3.899 | 1.404 | 0.628 | 0.323 | 0.240 |
| `numerics_sphere_he16ze63.yml` (dt 120) | 1.559 | 0.562 | 0.251 | 0.129 | 0.096 |
| **proposed ze120 / 200 m (dt 120)** | 0.573 | 0.490 | 0.386 | 0.289 | 0.239 |

The proposal is *less* CFL-exposed at every height than the shipped tracer config,
and at most ~2× more than `he16ze63` in the mid-troposphere. `dt = 120 s` is
therefore inside demonstrated territory. Confirm in calibration regardless.

**Vertical resolution.** `z_elem 120` with `dz_bottom 200 m` gives layer
thicknesses of 415 m at 10 km rising to 1017 m at 55 km — the ~1 km box depth
requested. (`z_elem 150` gives 343–757 m for 25% more cost; `z_elem 80` gives
597–1738 m.) Cost: `dz_bottom` at 200 m coarsens the boundary layer, hence EDMF
and surface fluxes. Not unprecedented — several sphere configs run 500 m.

**Model top** 80 km, sponge moved to 60 km. `zd_rayleigh` is a free TOML
parameter, not tied to `z_max`; 40 km is merely what the shipped TOMLs set, and
that would sit inside the sampled region.

## Source boxes: 49 sampled boxes + 1 reference

**A box is a fixed-height slab, one model layer thick over flat terrain.** The
source mask is a pointwise test on the coordinate height at cell centres
(`stratospheric_passive_tracers.jl:259-277`). Setting the box edges to the
enclosing *faces* of a chosen level makes it exactly one cell over flat terrain.

**It is not exactly one cell everywhere.** With `topography: "Earth"` the default
`mesh_warp_type: "SLEVE"` (`sleve_eta: 0.7`, `sleve_s: 10.0`) warps the coordinate
below `0.7 × z_top` = 56 km — which is *all six* boxes. Over 3 km of orography the
terrain influence displaces levels by ~2.4 km at 10 km altitude, ~2.0 km at 19 km,
~0.5 km at 46 km, so a fixed-height window catches a level index that varies with
surface elevation, and occasionally two centres rather than one.

This is acceptable and is **not** a bug: a fixed physical-height slab is the
physically meaningful definition, and τ = burden/source self-normalizes because
both are diagnosed from the same mask. What must change is the acceptance
criterion — **≥1 centre in every column, typically exactly 1** — not "exactly 1
everywhere", which cannot be met. (Masking on level index instead would give
exactly one cell but would make the box follow the terrain, which is worse
physics.)

**Level selection.** Candidates from 10 km (above the ~9 km minimum tropopause) to
55 km (below the sponge). Take cell centres nearest six evenly spaced altitudes —
note `linspace` over the *level index* does not give even spacing on a
tanh-stretched mesh, yielding gaps growing 5.6 → 11.6 km.

| box | level (0-based) | z centre | depth | gap | face edges (m) |
|---|---|---|---|---|---|
| 1 | 34 | 10.20 km | 415 m | — | 9989.7 – 10404.8 |
| 2 | 52 | 19.11 km | 581 m | 8.91 km | 18821.2 – 19402.1 |
| 3 | 66 | 28.26 km | 728 m | 9.15 km | 27896.0 – 28623.5 |
| 4 | 77 | 36.91 km | 844 m | 8.65 km | 36485.7 – 37329.9 |
| 5 | 87 | 45.85 km | 943 m | 8.94 km | 45380.1 – 46322.6 |
| 6 | 96 | 54.68 km | 1017 m | 8.83 km | 54173.9 – 55191.1 |

The face heights in metres are the specification; confirm the index convention
against the model's own grid in calibration.

**Latitude — 9 bands, 10° wide, centred 0, ±25, ±35, ±60, ±80.** Width is 10°, not
5°: at `h_elem 16` the node spacing is 206 km = **1.85°**
(`numerics_sphere_he16ze63.yml:2`; 40030 km / (4·16·3)), so a 5° band spans only
~2.7 node rows meridionally. 10° gives ~5.4 and is properly resolved. The 25°/35°
bands then share an edge at exactly 30°, directly bracketing the subtropical
mixing barrier; ±60 samples the vortex edge, ±80 the polar cap.

**Level 34 is used only at ±60 and ±80.** At 10.2 km the tropical and subtropical
tropopause is above the box, so at 0°, ±25° and ±35° it would sit in the
troposphere and report τ ≈ `tracer_loss_timescale`. Dropping those five leaves
49 sampled boxes.

| Member | levels | boxes | tracers |
|---|---|---|---|
| A | 34 (±60, ±80 only), 66, 87 | 4 + 9 + 9 | 22 + 1 reference = 23 |
| B | 52, 77, 96 | 9 + 9 + 9 | 27 |

The reference box spans −90…90°, **20–55 km** (not 10–55 km: at fixed altitude the
source is ∝ ρ, so a 10 km base would put most of the emission in the upper
troposphere, and in the tropics below the tropopause). It gives a bulk
middle/upper-stratosphere residence time as an anchor.

**The fixed-altitude tradeoff, stated plainly.** The code's default is
`TropopauseRelativeHeight` precisely because it "keeps every box a fixed distance
above the sink whatever the latitude, which is what makes lifetimes from different
latitude bands comparable" (`stratospheric_passive_tracers.jl:29-33`). At fixed
altitude, τ(φ) at a given level conflates latitude with height-above-tropopause —
19 km is ~2 km above the tropical tropopause but ~9 km above the polar one. Report
τ against both z and z − ztrop(φ). Boxes at level 52 and above are stratospheric
at all latitudes, so this is a systematic offset, not a contamination. Level 34 at
±60/±80 additionally straddles the tropopause synoptically (±2 km), so it is a
blend of source-only and source-plus-sink periods; the clean diagnostic — the
source-weighted fraction of time above the instantaneous tropopause — does not
exist in the code, so treat level 34 as indicative only.

Tracer names collide across members (`y01z01` in A ≠ in B); band edges are written
into every row of `stratospheric_tracer_budget.csv`, so post-processing must key
on those.

Members share a configuration but are separate integrations; with `rad: allsky`
their trajectories diverge chaotically. Fine for a climatology, but they are not
one integration replicated.

## Budget

From `perf/tracer_scaling.jl`: 0.613 s/step over 6·4²·16·31 = 47,616 cells →
12.87 µs/cell/step; (1.311−0.613)/16/47616 → 0.92 µs/cell/tracer/step. Scaled to
6·16²·16·120 = 2,949,120 cells, ×2 for RRTMGP all-sky + EDMF, 128 ranks/node at
~60% intra-node efficiency, 262,980 steps/yr at dt 120 s, 42 years:

| | member A (23 tracers) | member B (27) |
|---|---|---|
| dynamics + physics | 0.99 s/step | 0.99 s/step |
| tracers | 0.81 s/step | 0.95 s/step |
| per simulated year | 131 node-h | 142 node-h |
| 42 years | 5,520 node-h | 5,950 node-h |

| nodes/job | assumed penalty | total node-h | elapsed (member B) |
|---|---|---|---|
| 4 | ~25% | ~14,300 | ~77 days |
| 6 | ~50% | ~17,200 | ~62 days |

**Elapsed time, not node-hours, is the scarce resource** — a quarter is ~91 days
and both members run in parallel. Spend spare node-hours on wider parallelism.
Measure strong scaling at **4 and 6 nodes only**: `h_elem 16` gives 6·16² = 1536
elements, so 8 nodes is 1024 ranks = 1.5 elements/rank, which cannot divide evenly
and would measure load imbalance rather than scaling.

The ×2 physics factor, the 60% intra-node efficiency and the 25%/50% multi-node
penalties are **assumptions, not measurements**; at 4–6 nodes there are only
3,840–5,760 cells per rank, where halo exchange rather than arithmetic dominates.
Treat the whole table as ±2×.

Compile time at 27 tracers extrapolates to ~25 min from the benchmark, but that
was measured with `held_suarez` + `vert_diff`; the production stack adds RRTMGP
all-sky, EDMF, aerosols and non-orographic GWD, all of which compile. Treat 25 min
as a floor and budget 25–45 min per restart.

If calibration comes in high, cut in this order: shorten to 30 years; drop level
96; drop to `h_elem 12`.

## Interpolation and analysis

The deliverable is τ(φ, z) on a 9 × 6 lattice with 10°-of-20° latitude gaps and
~9 km height gaps.

1. **Interpolate log τ, not τ.** τ grows roughly exponentially with height above
   the tropopause and spans orders of magnitude between surf zone and tropical
   pipe.
2. **Do not interpolate across a transport barrier.** τ(φ) has a near-step at the
   subtropical barrier and the vortex edge; a smooth interpolant invents a ramp and
   places it arbitrarily. The vortex edge is seasonal, so an annual-mean
   interpolant is doubly wrong there. The 25°/35° pair converts the subtropical
   step into a measurement; elsewhere report sampled values with the gap marked.
3. **Average τ over multiple years.** The source is `ρ · production_rate` inside
   the mask, so it tracks air density and varies seasonally even with a fixed mask;
   and burden/source is an instantaneous ratio in a seasonally varying
   stratosphere. Use multi-year means, and keep `lifetime_from_loss` (burden/loss)
   as a cross-check.
4. **Boxes can be summed.** The tracers are linear and share the transport, so
   summing k boxes gives burden ΣMᵢ and source ΣSᵢ exactly, i.e. the
   source-weighted mean of the τᵢ. What is *not* valid is inferring a
   whole-stratosphere τ from a sample that is not volume-proportional — which is
   why the full-domain reference box exists.
5. **Box depth varies, 415–1017 m**, and cell count per box varies over
   orography. Neither biases τ, but the boxes are not equal-depth samples, so do
   not read vertical structure finer than that.

## Work items

### 1. Explicit source-box list (prerequisite)

The existing keys cannot express this design. They build edges as
`lower[k] = base + (k−1)·spacing`, `upper[k] = lower[k] + depth` with a single
uniform width and depth, latitude centres at `−90 + (i−0.5)·180/n`, and take the
full latitude × height outer product
(`stratospheric_passive_tracers.jl:148-171`). The chosen boxes have non-uniform
spacing (17.9 / 17.7 km), non-uniform depth (415…1017 m), non-uniform latitude
centres, and are not an outer product (level 34 is used at only 4 of 9 latitudes).

Add an alternative constructor taking an explicit list of boxes, each carrying its
own latitude range and height range, keeping the uniform outer-product path as the
default so the CI config keeps working. Resolve model levels to face heights at
setup by reproducing `Meshes.HyperbolicTangentStretching(dz_bottom)` from
`z_max`/`z_elem`/`dz_bottom`/`z_stretch` (`src/simulation/grids.jl:356-357`).

Overlap must be *allowed* on this path, not rejected: the whole-domain reference
box encloses the sampled boxes by construction, and the tracers are independent
so a shared point simply feeds both. The real guard is that two boxes may not
share both a latitude and a height range, since they would claim the same name.

Touchpoints beyond the tendency — the outer product is assumed in all of these:

- `chemistry_tendency!` nested `for k, i` loop (`:334-397`)
- `stratospheric_tracer_budget` (`:453-485`) and `write_tracer_budget!` (`:543-582`)
- `stratospheric_tracer_symbols` (`:213-219`) and the `@generated`
  `stratospheric_tracer_fields` (`:232-240`)
- `chemistry_variables` (`src/setups/common/prognostic_variables.jl:152-160`)
- diagnostic registration (`src/diagnostics/stratospheric_tracer_diagnostics.jl:121-122`)
- config plumbing (`src/config/model_getters.jl:1411-1425`)

Decide and document the naming scheme for the explicit path (the `y{i}z{k}`
convention has no meaning without an outer product), and keep band edges in the
budget CSV since post-processing keys on them.

### 2. Calibration run

Production grid, 27 tracers, full transient physics. Measure:

- Strong scaling at 4 and 6 nodes — this sets the node count.
- `sypd` and `wall_time_per_timestep` (`timed_solve!`, `src/simulation/solve.jl:57-80`
  — note it does *not* report compile time; take that from the log timestamps).
- **Cells captured per source box, per column** — must be ≥1 everywhere; record
  the distribution, and confirm the level-index convention against the model grid.
- Tracer CFL and stability at `dt = 120 s`.
- Diagnosed `ztrop` by latitude and season, to quantify level-34 straddling.
- **Temporal coverage of the prescribed O3 and CO2 inputs over 1979–2021**
  (`ozone_cache` / `co2_cache`, `src/cache/tracer_cache.jl:17-76`). Coverage lives
  in ClimaArtifacts, not this repo; silent flat extrapolation of ozone would
  invalidate the campaign.

### 3. Job chaining — per-segment `t_end`

The naive scheme does not work: with `t_end` fixed at 15341 days the Julia process
never returns inside 8 h, SLURM kills the batch script, and nothing after `srun`
in `runscripts/xmodel.cpu:275-292` runs — so a self-resubmit line never executes.
A SLURM kill also writes no checkpoint: `solve_atmos!` saves only in its `catch`
branch and only when not distributed (`src/simulation/solve.jl:140-147`), so each
killed segment would discard up to a full checkpoint interval (~20% of compute at
30-day checkpoints and ~73 simulated days per slot).

Instead, **give each job a per-segment `t_end` aligned to the checkpoint cadence**.
`experiments/strat_tracers_transient.jl` calls `auto_detect_restart_file`
(`src/simulation/restart.jl:99-144`) to get the restart time, then sets
`t_end = min(t_restart + K·30 days, 15341 days)` with K from measured throughput
and ~1 h of margin. The run then finishes naturally, the 30-day checkpoint
callback fires at `t_end`, `solve_atmos!` returns, and the batch script reaches
its resubmit line. No work is discarded and no signal handling is needed.

`graceful_exit.dat` (`src/callbacks/callbacks.jl:641`, installed unconditionally at
`get_callbacks.jl:880`) is a backstop only — its own docstring warns it "may not be
reliable for MPI jobs, where ranks poll the file independently", and it does not
write a checkpoint either.

`runscripts/xmodel.chain`, from `xmodel.cpu`: `--time=08:00:00`, node count from
calibration, `--ntasks-per-node=128`, drop `--no-requeue`, resubmit unless the
campaign end was reached, and guard that `output_active` resolves before launching
(Lustre sync is a real failure mode over ~200 jobs; `test/restart.jl:228-231`).
Fix while here: line 44 defaults `SCRIPT` to `experiments/run_tracer.jl`, which
does not exist, and line 41 hard-codes `ROOT` with the portable version commented
out on line 40. Do **not** use `.buildkite/ci_driver.jl`, which tars and then
deletes `.hdf5`/`.nc` (`ci_driver.jl:249-257`).

### 4. Configs

`config/common_configs/numerics_sphere_he16ze120_top80.yml`, from
`numerics_sphere_he16ze63.yml` with `z_elem: 120`, `z_max: 80000.0`,
`dz_bottom: 200.0`.

`toml/strat_tracers_transient.toml`: `zd_rayleigh = zd_viscous = 60000.0`,
`precipitation_timescale = 120`. Use this rather than
`toml/prognostic_edmfx_1M.toml` because that file sets
`zd_rayleigh = zd_viscous = 40000.0`, inside the sampled region. (Its
`alpha_rayleigh_tracer` is *not* a reason: that parameter reaches only `ρtke` and
the EDMFX subdomain tracers, and only under `PrognosticEDMFX` —
`src/prognostic_equations/remaining_tendency.jl:124-157` — so it never touches
grid-mean `ρq_gas_*`, least of all under `edonly_edmfx`.)

`config/example_configs/strat_tracers_transient_{a,b}.yml`, on the physics stack of
`config/longrun_configs/amip_target.yml`:

```yaml
FLOAT_TYPE: "Float64"
start_date: "19790101"
t_end: "15341days"             # campaign end; each job overrides with a segment end
initial_condition: "WeatherModel"
era5_initial_condition_dir: <dir holding era5_init_processed_internal_19790101_0000.nc>

rad: "allsky"
dt_rad: "1hours"
insolation: "timevarying"
time_varying_trace_gases: ["CO2", "O3"]
aerosol_radiation: true
prescribed_aerosols: [CB1, CB2, DST01..DST05, OC1, OC2, SO4, SSLT01..SSLT05]
topography: "Earth"
topo_smoothing: true
non_orographic_gravity_wave: true
dt_nogw: "360secs"             # integer multiple of dt; amip_target's 400s is not
microphysics_model: "0M"
turbconv: "edonly_edmfx"
edmfx_sgs_diffusive_flux: true
surface_setup: "DefaultMoninObukhov"
prognostic_surface: "PrescribedSST"

chemistry_model: "stratospheric_passive_tracers"
tracer_source_height_coordinate: "altitude"
tracer_source_boxes: [...]     # new key, work item 1; schema TBD there
tracer_loss_timescale: "6hours"
dt_tracer_budget: "30days"

toml: [toml/strat_tracers_transient.toml]

dt_save_state_to_disk: "30days"
detect_restart_file: true

diagnostics:
  - short_name: [ztrop]
    reduction_time: average
    period: 30days
    writer: netcdf
  - short_name: [<2-3 representative q_gas_* fields>, ta, ua, va]
    reduction_time: average
    period: 30days
    writer: netcdf
```

`dt_save_state_to_disk` must be an integer multiple of every accumulation
`period`, and each segment must resume on an accumulation boundary — schedules
re-anchor at `date(t_start)` on restart (`get_callbacks.jl:169-214`). A mismatch
is warned about (`get_callbacks.jl:269-281`), not silent, but still corrupts the
means. 30-day checkpoints with 30-day averages satisfies both, and the
per-segment `t_end` of work item 3 keeps every restart on a boundary.

Emitting a few 3-D tracer fields as monthly means is cheap insurance over 42 years;
the budget CSV alone leaves nothing to diagnose a surprise with.

### 5. ERA5 initial condition for 1979-01-01

`AMIPFromERA5` reads a hard-wired artifact path with no config override and the
shipped artifact holds only 2010-01-01. Use `initial_condition: "WeatherModel"`
with `era5_initial_condition_dir` (`src/utils/weather_model.jl:63-80`).

**Provide the pre-processed file**, `era5_init_processed_internal_19790101_0000.nc`.
The `era5_raw_*` fallback is not equivalent: `to_z_levels_1d` requires dimensions
`pressure_level`/`latitude`/`longitude`/`valid_time`, i.e. pressure-level data,
which stops near 1 hPa (~48 km) and would be flat-extrapolated over the top 30 km
of an 80 km domain. The fallback also defaults `interp_w = false` (writes `w = 0`)
and has no visible root-rank guard, so 512 ranks would race to write it.

Required variables `t`, `q`, `u`, `v`, `w`, `p` on `lon`/`lat`/`z`; optional
`z_sfc`, `crwc`, `cswc`. Note `WeatherModel` interpolates onto `0:300:z_top` with
`Flat()` extrapolation, so everything above the source file's top is constant —
the file must reach into the mesosphere. DKRZ holds ERA5 under `/pool/data/ERA5`.

### 6. Post-processing

`post_processing/tracer_lifetimes.jl` reads one budget CSV; a chained run writes
one per `output_NNNN`. Add a step that walks the numbered directories, dedupes on
`(time, band edges)`, merges the members on band edges, takes multi-year means,
reports τ against both z and z − ztrop(φ), and interpolates in log τ with barrier
gaps marked rather than bridged.

## Known limitations to record with the results

- The seasonal SST cycle is an ocean one: no land or sea-ice seasonality, no
  ENSO, no SST trend. Stationary-wave forcing comes from `topography: "Earth"`
  and this cycle.
- `dz_bottom = 200 m` coarsens the boundary layer, degrading EDMF and surface
  fluxes.
- CH4, N2O and the CFCs are fixed constants (`radiation.jl:210-248`); only CO2 and
  O3 vary in time.
- No volcanic aerosol forcing exists: El Chichón (1982) and Pinatubo (1991) are
  both absent from a period that contains them.
- Restarts are not bit-reproducible unless `reproducible_restart: true`, not
  recommended for production.
- Grid and tracer set are frozen for the chain: the space is deserialized from the
  checkpoint and `Setups.initial_state` is never called on the restart branch
  (`AtmosSimulations.jl:364-383`), so changing `h_elem`, `z_elem`, `z_max` or any
  source-box key invalidates the run. The only guard is a soft `@warn` on the model
  hash (`restart.jl:37`).

## Unverified assumptions

Label these as such in any write-up:

1. The ×2 physics factor, 60% intra-node efficiency, and 25%/50% multi-node
   penalties; and that per-cell cost is resolution-independent.
2. Compile-time extrapolation (~25 min at 27 tracers) — a floor, measured on a
   cheaper physics stack.
3. That the `era5_inst_model_levels` artifact holds only 2010-01-01.
4. Temporal coverage of the O3 and CO2 inputs over 1979–2021 — **checked in
   calibration**, and campaign-invalidating if wrong.
5. DKRZ specifics: `/pool/data/ERA5` layout, 128 cores/node, queue turnaround over
   ~200 jobs, and the allocation itself.
6. `dt = 120 s` stability on this grid — argued from the `dt/Δz` table, confirmed
   in calibration.
7. Existence of a 1979-01-01 pre-processed ERA5 file reaching into the mesosphere.

## Surface temperature alternatives

`prognostic_surface: "PrescribedSST"` is a misnomer: it resolves to
`AnalyticTemperature(zonally_symmetric_temperature)` — steady, though it does
subtract 6.5 K/km over surface elevation, so there is elevation-driven contrast but
no thermal one. `ExternalTemperature` reads
`p.external_forcing.surface_fields.ts`, populated only by the column-mode
`ForcingFromFile` path. No SST or sea-ice artifact, and no sea-ice code, exists.

1. **Steady analytic SST** — the previous default; superseded.
2. **Seasonally varying analytic SST** — **implemented and adopted**, as
   `prognostic_surface: "SeasonalSST"` (`Setups.SeasonalOceanTemperature`).
3. **`prognostic_surface: "SlabOceanSST"`** — config only, but drifts to its own
   equilibrium and adds spin-up.
4. **ClimaCoupler AMIP** — the only route to observed SST/sea ice; out of scope.

5. **Prescribed observed surface temperature** — to be implemented separately,
   then folded back into this plan. Shape: a marker `SurfaceTemperature` subtype
   plus a cache entry holding a global `TimeVaryingInput`, mirroring
   `ozone_cache` (`src/cache/tracer_cache.jl:17-30`). The marker/cache split is
   required because `AtmosModel` is built before the spaces exist
   (`AtmosSimulations.jl:376`), so the type cannot hold a `Field`.

   Data: the user has HadISST1 on Levante (monthly, 1°, 1870–present, so it
   covers 1979–2021 and is finer than the 1.85° grid). Caveats:
   - **HadISST is ocean-only**; land carries a fill value. Standalone ClimaAtmos
     has no land model and needs a temperature everywhere, so HadISST cannot be
     the sole source. ERA5 skin temperature covers land, ocean and sea ice in one
     field and is the better single choice; ERA5 `skt` over land blended with
     HadISST over ocean is the higher-effort option.
   - HadISST supplies sea-ice **concentration** (`sic`), not temperature. Mapping
     ice points to roughly the freezing point gives the thermal effect but not the
     radiative one: `albedo_model` defaults to `ConstantAlbedo` and the only
     alternative, `RegressionFunctionAlbedo`, is an open-ocean formula
     (`model_getters.jl:1342-1354`). Sea ice would be radiatively invisible.
   - Apply the Taylor et al. (2000) mid-month adjustment before feeding monthly
     means to `TimeVaryingInput`/`LinearInterpolation`, or the seasonal amplitude
     is damped ~10–20% at the turning points.

## Verification

1. `TEST_GROUP=parameterizations` and `TEST_GROUP=restarts` stay green after the
   source-box change.
2. Unchanged CI path still runs (`passive_stratospheric_tracers_ci` with
   `numerics_sphere_he6ze31.yml`).
3. New config, 2-day run at reduced resolution: `Y.c` carries the expected tracer
   count, box edges match the configured faces, every box captures ≥1 cell centre
   in every column, `ztrop` is diagnosed, budget table is written.
4. Restart proof: run through two checkpoints, kill, resubmit, confirm
   `auto_detect_restart_file` picks the highest-numbered output directory holding a
   checkpoint and that `t_start` matches; confirm the per-segment `t_end` logic
   lands on a 30-day boundary.
5. Calibration run per work item 2, then re-derive the budget before launching.
