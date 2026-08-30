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
  - **Coupled AMIP surface** via ClimaCoupler: prescribed observed SST and sea ice
    over 1979–2021. This is the main track; the seasonal analytic SST added to
    ClimaAtmos is the fallback.
  - **Sampled boxes, not a tiling**, one model layer deep.
  - **1979-01-01 → 2021-01-01** (`t_end: "15341days"` = 42×365 + 11 leap days).
    ~10 y is tracer spin-up, so ~32 usable years.
  - **Two members with disjoint boxes.** Compile time grows as N^2.9.

Constraints: 24,000 node-hours this quarter, 8 h wallclock per job.

## Surface boundary: coupled AMIP with ClimaCoupler

**This is the main track.** The analytic surface temperature — steady or
seasonal — was the largest remaining physical shortcut in the campaign. A
coupled AMIP run removes it: prescribed *observed* SST and sea ice over exactly
the campaign period, from data that already ships with the coupler.

Adopting it supersedes `prognostic_surface: "SeasonalSST"`, which stays in the
codebase as the fallback if the coupled route proves impractical (see
"Fallback: atmosphere-only" below). It also changes the cost basis: the budget
section's node-hour figures were derived for an atmosphere-only CPU run and do
**not** carry over.

Checked against ClimaCoupler at `953c273`.

### What already works in our favour

  - **The fork's tracers come along.** The coupler's AMIP environment
    `Pkg.develop`s the local ClimaAtmos checkout
    (`.buildkite/coupler_perf/pipeline.yml`), and this fork is version `0.42.6`,
    exactly what `experiments/AMIP/Manifest-v1.11.toml` pins. No version fight
    is expected.
  - **The boundary data ships with the coupler and covers the period.**
    `src/Models/prescr_ocean.jl` reads the `historical_sst_sic` artifact, file
    `MODEL.SST.HAD187001-198110.OI198111-202206.nc` — the PCMDI AMIP II
    dataset: HadISST to 1981-10, NOAA OI to 2022-06. It spans 1979–2021 and is
    already the mid-month-adjusted product, so no Taylor et al. preprocessing is
    needed. Sea-ice concentration comes from the same artifact via
    `src/Models/prescr_seaice.jl`. Both accept a `sst_path` / `sic_path`
    override for locally held data.
  - **Sea ice is a real surface**, not a cold patch of ocean, so it is not
    radiatively invisible the way a prescribed-SST-only field would be.
  - **`mode_name: "amip"` selects the components for you.**
    `validate_model_types_for_mode` (`src/Input.jl:940+`) forces
    `ocean_model = prescribed` and `ice_model = prescribed`; `land_model`
    defaults to `"bucket"`, which is the cheap option (`integrated` is ClimaLand).
  - **Restarts carry the tracers.** `detect_restart_files: true` plus
    `checkpoint_dt`; `restart_model_state!` (`src/Checkpointer.jl:385`) does
    `Y .= Y_new` over the whole prognostic state.
  - **There is already an AMIP config close to ours**:
    `config/longrun_configs/amip_edonly.yml` with
    `config/atmos_configs/climaatmos_edonly.yml` — `h_elem 16`,
    `edonly_edmfx`, `0M`, `insolation: timevarying`, `["CO2", "O3"]`, the same
    MERRA-2 aerosol list, non-orographic GWD, and `initial_condition: AMIPFromERA5`.

### What it would take

 1. **A coupler config**, modelled on `amip_edonly.yml`: `mode_name: "amip"`,
    `surface_setup: "PrescribedSurface"`, `albedo_model: "CouplerAlbedo"`,
    `land_model: "bucket"`, `dt_cpl: "120secs"`, and `checkpoint_dt: "30days"` to
    stay aligned with `dt_tracer_budget` and the diagnostic accumulation windows.
 2. **Our atmos config, pointed at by `atmos_config_file`.** Config precedence is
    `merge(atmos_default, coupler_default_cli, atmos_config_dict, coupler_config_dict)`
    (`src/Input.jl:404-418`), so **the coupler config wins over the atmos config
    file** — keep the two from setting the same key. The path is resolved with
    `joinpath(pkgdir(ClimaCoupler), atmos_config_file)`, so an absolute path
    pointing back into this repo works; a relative one must live inside the
    coupler checkout.
 3. **The atmos config is left alone.** `surface_setup` and `albedo_model` are
    overridden from the coupler config instead of being removed, so the member
    configs stay runnable standalone on the fallback. `prognostic_surface` is
    inert under coupling. The delta from `climaatmos_edonly.yml` is
    `z_elem: 120`, `z_max: 80000.0`, `dz_bottom: 200.0`, our sponge TOML, and the
    `passive_tracers` block.
 4. **A second Julia environment on Levante** — `experiments/AMIP/Project.toml`,
    instantiated with the fork dev'd in, on its own depot alongside the existing
    one. `runscripts/setup-julia-levante.tcsh` would need a variant.

### What does not change

  - The 1979 initial condition. `AMIPFromERA5` still reads a hard-wired
    artifact path holding only 2010-01-01, so `WeatherModel` plus our own
    pre-processed ERA5 file is still the route.
  - No volcanic aerosol forcing; CH4, N2O and the CFCs still fixed.
  - The source-box design, the level selection, and the member split.

### Costs and open risks

  - **Two more component models** (bucket land, prescribed ice) to configure,
    checkpoint and debug.
  - **Cost is unmeasured for our case.** The only published figure is
    `BASELINE_SYPD: "0.310"` for `gpu_amip_progedmf_1M_land_he16` on one A100
    (`.buildkite/coupler_perf/pipeline.yml`). That is heavier physics
    (prognostic EDMF, 1M microphysics, *integrated* land) at 63 levels, against
    our cheaper physics at ~2× the levels plus ~25 tracers. It is not
    transferable in either direction — it has to be measured.
  - **The coupler's AMIP work is GPU-first.** CPU/MPI is supported
    (`CLIMACOMMS_CONTEXT: "MPI"` steps exist) but every AMIP performance and
    longrun pipeline is CUDA. Our working Levante stack is the CPU one; the GPU
    stack exists (`setup-julia-levante.tcsh gpu`, `runscripts/xmodel.1gpu` and
    its siblings) but is less exercised.
  - **Allocation.** It covers the `gpu` partition, and the coupled run is viable
    on CPU. The chaining script targets the CPU `compute` partition; switching it
    to GPU is a header change plus `CLIMACOMMS_DEVICE=CUDA` and the GPU depot.
  - **Our tracer refactor is not covered by the coupler contract test.**
    `test/coupler_compatibility.jl` exercises the surface API, not the
    prognostic state; the coupler reads the tracers through
    `get_model_prog_state`, which the refactor did not touch but has not been
    exercised coupled either.

### Chaining, on the coupler

The per-segment `t_end` scheme of work item 3 carries over, and is simpler here.
The coupler's checkpoint schedule is
`EveryCalendarDtSchedule(checkpoint_dt; start_date)` (`src/SimCoordinator.jl:448`),
anchored on `start_date` rather than on the restart time — unlike ClimaAtmos,
which re-anchors at `date(t_start)`. So checkpoints land on fixed calendar
boundaries no matter where a segment begins, and any segment end on such a
boundary is safe.

The driver is `experiments/AMIP/run_simulation.jl`: `CoupledSimulation(config_file)`
then `run!(cs)`. `run!` also writes `sypd.txt` and `walltime_per_step.txt`
(`save_sypd_walltime_to_disk`, `src/SimCoordinator.jl:134`), so the calibration
measurement of work item 2 comes for free rather than needing instrumentation.

Still to establish: whether a run reaching `t_end` writes a final checkpoint, and
what happens on a SLURM kill. Both are the same questions asked of ClimaAtmos in
work item 3 and should be answered the same way — by giving each job a segment
`t_end` on a checkpoint boundary so it finishes cleanly.

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

| config                                             | 0.5 km | 2 km  | 5 km  | 10 km | 15 km |
|:-------------------------------------------------- |:------ |:----- |:----- |:----- |:----- |
| `passive_stratospheric_tracers.yml` (ze63, dt 300) | 3.899  | 1.404 | 0.628 | 0.323 | 0.240 |
| `numerics_sphere_he16ze63.yml` (dt 120)            | 1.559  | 0.562 | 0.251 | 0.129 | 0.096 |
| **proposed ze120 / 200 m (dt 120)**                | 0.573  | 0.490 | 0.386 | 0.289 | 0.239 |

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

| box | level (0-based) | z centre | depth  | gap     | face edges (m)    |
|:--- |:--------------- |:-------- |:------ |:------- |:----------------- |
| 1   | 34              | 10.20 km | 415 m  | —       | 9989.7 – 10404.8  |
| 2   | 52              | 19.11 km | 581 m  | 8.91 km | 18821.2 – 19402.1 |
| 3   | 66              | 28.26 km | 728 m  | 9.15 km | 27896.0 – 28623.5 |
| 4   | 77              | 36.91 km | 844 m  | 8.65 km | 36485.7 – 37329.9 |
| 5   | 87              | 45.85 km | 943 m  | 8.94 km | 45380.1 – 46322.6 |
| 6   | 96              | 54.68 km | 1017 m | 8.83 km | 54173.9 – 55191.1 |

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
troposphere and report τ ≈ the configured `loss_timescale`. Dropping those five leaves
49 sampled boxes.

| Member | levels                     | boxes     | tracers               |
|:------ |:-------------------------- |:--------- |:--------------------- |
| A      | 34 (±60, ±80 only), 66, 87 | 4 + 9 + 9 | 22 + 1 reference = 23 |
| B      | 52, 77, 96                 | 9 + 9 + 9 | 27                    |

The reference box spans −90…90°, **20–55 km** (not 10–55 km: at fixed altitude the
source is ∝ ρ, so a 10 km base would put most of the emission in the upper
troposphere, and in the tropics below the tropopause). It gives a bulk
middle/upper-stratosphere residence time as an anchor.

**The fixed-altitude tradeoff, stated plainly.** The code's default is
`TropopauseRelativeHeight` precisely because it "keeps every box a fixed distance
above the sink whatever the latitude, which is what makes residence times from
different latitude bands comparable" (`stratospheric_passive_tracers.jl:32-34`).
At fixed altitude, τ(φ) at a given level conflates latitude with
height-above-tropopause — 19 km is ~2 km above the tropical tropopause but ~9 km
above the polar one. Report τ against both z and z − ztrop(φ). Boxes at level 52
and above are stratospheric at all latitudes, so this is a systematic offset, not
a contamination. Level 34 at ±60/±80 additionally straddles the tropopause
synoptically (±2 km), so it is a blend of source-only and source-plus-sink
periods; the clean diagnostic — the source-weighted fraction of time above the
instantaneous tropopause — does not exist in the code, so treat level 34 as
indicative only.

Tracer names collide across members (`y01z01` in A ≠ in B); band edges are written
into every row of `stratospheric_tracer_budget.csv`, so post-processing must key
on those.

Members share a configuration but are separate integrations; with `rad: allsky`
their trajectories diverge chaotically. Fine for a climatology, but they are not
one integration replicated.

## Budget

**These figures are for an atmosphere-only CPU run and do not carry over to the
coupled main track.** They remain here because they still bound the *atmosphere*
part of the cost and because they set the fallback's budget. The coupled run adds
bucket land and prescribed ice, and is GPU-first; its cost has to be measured, not
scaled from this table. See the surface-boundary section.

From `perf/tracer_scaling.jl`: 0.613 s/step over 6·4²·16·31 = 47,616 cells →
12.87 µs/cell/step; (1.311−0.613)/16/47616 → 0.92 µs/cell/tracer/step. Scaled to
6·16²·16·120 = 2,949,120 cells, ×2 for RRTMGP all-sky + EDMF, 128 ranks/node at
~60% intra-node efficiency, 262,980 steps/yr at dt 120 s, 42 years:

|                    | member A (23 tracers) | member B (27) |
|:------------------ |:--------------------- |:------------- |
| dynamics + physics | 0.99 s/step           | 0.99 s/step   |
| tracers            | 0.81 s/step           | 0.95 s/step   |
| per simulated year | 131 node-h            | 142 node-h    |
| 42 years           | 5,520 node-h          | 5,950 node-h  |

| nodes/job | assumed penalty | total node-h | elapsed (member B) |
|:--------- |:--------------- |:------------ |:------------------ |
| 4         | ~25%            | ~14,300      | ~77 days           |
| 6         | ~50%            | ~17,200      | ~62 days           |

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
    stratosphere. Use multi-year means, and keep `residence_time_from_loss`
    (burden/loss) as a cross-check.
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

### 2. Coupled AMIP setup — done

Delivered:

  - `config/coupler_configs/strat_tracers_amip_{a,b}.yml.in` — coupler config
    templates. Templates, not runnable configs: the chaining script substitutes
    the atmos config path and the segment end.
  - `runscripts/setup-julia-amip-levante.sh` — builds the AMIP environment on a
    login node, on its own depot, with this fork dev'd in, and verifies the
    system MPI, parallel HDF5 and that the tracers are actually present.

Three traps were found while building it, all now handled in the templates and
documented there:

  - **`coupler_toml` replaces the atmos TOML list rather than adding to it**
    (`ext/ClimaCouplerClimaAtmosExt.jl:689-693`). Setting it would silently
    discard `toml/strat_tracers_transient.toml` and put the sponge back inside
    the sampled region. It is deliberately left unset.
  - **`coupler_default_cli` merges *before* the atmos config file**, so the
    coupler's own defaults for `surface_setup` and `albedo_model` lose to
    whatever the atmos config says. Our atmos config sets
    `surface_setup: "DefaultMoninObukhov"` for standalone use, which would take
    the atmosphere out of coupled mode. Both keys are set explicitly in the
    coupler config, which merges last.
  - **`dt_atmos` is preferred over `dt` whenever the key is present**
    (`ext/ClimaCouplerClimaAtmosExt.jl:677-680`), so only `dt` is set, matching
    the shipped AMIP configs.

`prognostic_surface` is left in the atmos configs. It is inert under coupling —
the coupler writes straight into `p.precomputed.sfc_conditions.T_sfc`
(`ext/ClimaCouplerClimaAtmosExt.jl:373-376`) and `update_surface_conditions!`
returns early when the flux scheme is `nothing` — so the member configs stay
runnable standalone on the fallback.

### 3. Calibration run

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

### 4. Job chaining — done

`runscripts/xmodel.amip` runs one segment and resubmits itself. Each job reads
the newest checkpoint from `<base>/checkpoints`, sets the segment end to
`min(restart_t + SEGMENT_DAYS, campaign end)`, renders the config, runs, and
resubmits unless the campaign is finished or the segment failed.

Verified against the coupler source and by exercising the logic directly:

  - Checkpoints are named `checkpoint_<model>_<t>.hdf5` with `t` in whole
    seconds, and live in `<base>/checkpoints` — outside the numbered
    `output_XXXX` directories, so they accumulate in one place across segments.
    The parser was tested against underscored model names (`clima_seaice`),
    numeric-versus-lexical ordering, and malformed files.
  - `SEGMENT_DAYS` must be a whole number of checkpoint intervals or segments
    would not end on a checkpoint; the script refuses to run otherwise.
  - **SLURM copies the batch script into its spool directory**, so
    `${BASH_SOURCE[0]}` is not the file in the repository and cannot be used to
    resubmit. The script uses `SLURM_SUBMIT_DIR` and checks it can find itself
    before running anything, since otherwise the segment would run and the chain
    would then die silently.

`SEGMENT_DAYS` defaults to 150 and must be set from the calibration run's
measured throughput.

### 5. Configs

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

dt_tracer_budget: "30days"
passive_tracers:
  heights_from: "altitude"
  loss_timescale: "6hours"
  release_boxes: [...]         # explicit box list; see work item 1

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

### 6. ERA5 initial condition for 1979-01-01

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

### 7. Post-processing — partly done

`post_processing/merge_tracer_budgets.jl` merges the budget tables across
segments and members. It walks both output layouts (`output_XXXX/` for a
standalone run, `output_XXXX/clima_atmos/` for a coupled one), deduplicates on
`(time, box edges)` keeping the row from the segment that carried the run
forward, and merges members on box edges rather than on tracer name — the names
collide across members while the edges do not. Standard library only.

Still to write, once there is output to write it against: the log-τ
interpolation with barrier gaps marked, and reporting τ against both `z` and
`z − ztrop(φ)`.

## Work remaining

Nothing in this branch has been run as a simulation. It was written in an
environment with no Julia toolchain, so every claim rests on reading the code,
and CI is the only thing that has executed any of it. Treat the first Levante
job as the first real test.

### Before anything can run

 1. **Point the runscripts at the coupler checkout.** `COUPLER` in
    `runscripts/xmodel.amip` and `runscripts/setup-julia-amip-levante.sh` is a
    placeholder; the local clone is at `/home/b/b309159/git/ClimaCoupler.jl`.
 2. **Reconcile `xmodel.amip` with `xmodel.cpu`.** The AMIP chaining script was
    derived from `xmodel.cpu` before that file was rewritten, so the two have
    diverged and the differences have not been reviewed.
 3. **Produce the 1979-01-01 ERA5 initial condition** (work item 6).
    `era5_init_processed_internal_19790101_0000.nc` has to come from DKRZ's own
    holdings under `/pool/data/ERA5`, and has to reach into the mesosphere,
    because `WeatherModel` extrapolates flat above the file's top. The upstream
    route does not work from here: the `wxquest_initial_conditions` artifact is
    declared with a tree hash and no download block, so it resolves only on a
    machine that already holds the data.

### The calibration run (work item 3)

This gates everything downstream. It sets `SEGMENT_DAYS`, which is a placeholder
`150` until measured, and the node count, and it replaces the budget table,
which is atmosphere-only and carries a ±2× error bar. It must also confirm three
things that are currently assumed:

  - every source box captures at least one cell centre in every column;
  - `dt = 120 s` is stable on this grid;
  - the prescribed O₃ and CO₂ inputs actually cover 1979–2021. Silent flat
    extrapolation of ozone would invalidate the campaign.

### Still to write

 4. **Post-processing** (work item 7): interpolation in log τ with the transport
    barriers marked rather than bridged, and τ reported against both `z` and
    `z − ztrop(φ)`. Waiting on output to write it against.
 5. **A coupled smoke test** (verification item 5). `test/coupler_compatibility.jl`
    covers the surface API but not the prognostic state, so nothing yet checks
    that the tracers survive a coupled run and a checkpoint round-trip.

### Unexercised code

`post_processing/merge_tracer_budgets.jl` has never been run. Neither has
`runscripts/xmodel.amip`, beyond exercising its checkpoint-parsing logic
directly. The source-box change, the seasonal SST and the docs are covered by
CI; nothing else here is.

## Known limitations to record with the results

  - On the coupled main track the surface is observed SST and sea ice, so this is
    no longer a limitation. If the campaign falls back to atmosphere-only, it
    returns: the analytic seasonal cycle is an ocean one, with no land or sea-ice
    seasonality, no ENSO and no SST trend.
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
 5. DKRZ specifics: `/pool/data/ERA5` layout, 128 cores/node, and queue turnaround
    over ~200 jobs. The allocation itself is confirmed: 24,000 node-hours, and it
    covers the `gpu` partition.
 6. `dt = 120 s` stability on this grid — argued from the `dt/Δz` table, confirmed
    in calibration.
 7. Existence of a 1979-01-01 pre-processed ERA5 file reaching into the mesosphere.

## Fallback: atmosphere-only surface temperature

`prognostic_surface: "PrescribedSST"` is a misnomer: it resolves to
`AnalyticTemperature(zonally_symmetric_temperature)` — steady, though it does
subtract 6.5 K/km over surface elevation, so there is elevation-driven contrast but
no thermal one. `ExternalTemperature` reads
`p.external_forcing.surface_fields.ts`, populated only by the column-mode
`ForcingFromFile` path. No SST or sea-ice artifact, and no sea-ice code, exists.

If the coupled route proves impractical — allocation, GPU stack, or schedule —
these are the atmosphere-only options, in order of preference:

 1. **Seasonally varying analytic SST** — **implemented**, as
    `prognostic_surface: "SeasonalSST"` (`Setups.SeasonalOceanTemperature`). The
    member configs currently set this, and it is what the campaign falls back to.

 2. **Steady analytic SST** — the previous default; no reason to prefer it now.

 3. **`prognostic_surface: "SlabOceanSST"`** — config only, but drifts to its own
    equilibrium and adds spin-up.

 4. **ClimaCoupler AMIP** — promoted to the main track; see the surface-boundary
    section above.

 5. **Prescribed observed surface temperature** — to be implemented separately,
    then folded back into this plan. Shape: a marker `SurfaceTemperature` subtype
    plus a cache entry holding a global `TimeVaryingInput`, mirroring
    `ozone_cache` (`src/cache/tracer_cache.jl:17-30`). The marker/cache split is
    required because `AtmosModel` is built before the spaces exist
    (`AtmosSimulations.jl:376`), so the type cannot hold a `Field`.

    Data: the user has HadISST1 on Levante (monthly, 1°, 1870–present, so it
    covers 1979–2021 and is finer than the 1.85° grid). Caveats:

      + **HadISST is ocean-only**; land carries a fill value. Standalone ClimaAtmos
        has no land model and needs a temperature everywhere, so HadISST cannot be
        the sole source. ERA5 skin temperature covers land, ocean and sea ice in one
        field and is the better single choice; ERA5 `skt` over land blended with
        HadISST over ocean is the higher-effort option.
      + HadISST supplies sea-ice **concentration** (`sic`), not temperature. Mapping
        ice points to roughly the freezing point gives the thermal effect but not the
        radiative one: `albedo_model` defaults to `ConstantAlbedo` and the only
        alternative, `RegressionFunctionAlbedo`, is an open-ocean formula
        (`model_getters.jl:1342-1354`). Sea ice would be radiatively invisible.
      + Apply the Taylor et al. (2000) mid-month adjustment before feeding monthly
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
 5. Coupled smoke test: a short AMIP run with one member config, confirming the
    tracers appear in the coupled prognostic state, the budget table is written,
    and a checkpoint/restart round-trip preserves them. `test/coupler_compatibility.jl`
    covers the surface API but not the tracer state, so this is the gap it leaves.
 6. Calibration run per work item 3, then re-derive the budget before launching.
