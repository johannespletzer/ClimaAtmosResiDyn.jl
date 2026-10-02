# Criterion 3 on two MPI ranks (W59)

Pre-registered on 2026-10-02, before any job, for task T2 of the goals of
2026-10-02 (batch 2). Key `mpi`. Record branch `claude/rec-mpi`. The model is
main `d3c5e42f`, run from the clean detached tree `../ClimaAtmosResiDyn-mpi-run`.

## 1. What is checked

G3_PLAN section 2, criterion 3: with water tags on, every model field is bit
for bit that of the run without them, in both modes. The column checks
(W17–W51, and the CI tests of section 6) cover D4-W, a 0M EDMF column, and
implicit and explicit microphysics. Only the two-rank part is missing. A column
cannot be split across ranks, so this needs a horizontal domain.

The question is narrow. Does anything the tags add change a model field when
the domain is split across two processes? The paths that differ under MPI are
the exchange of the ranks' boundary values (the DSS of `Y`, where the tags sit
in the same field vector as the model's fields), the global sums of the
closure check and its audit, and any code that runs on the root rank only.

## 2. Configuration

The G2 sphere's physics (`g2_v2_sphere_n2`, E74/E75): prognostic EDMF with
one updraft, 1M with implicit microphysics, clear-sky radiation every hour,
DCMIP200 topography, both sponges, `DefaultMoninObukhov` surface, ARS222,
two Newton iterations, `dt` 20 s. Changed from G2, to make the run small:

| Key          | G2            | W59          | Why                                  |
|:------------ |:------------- |:------------ |:------------------------------------ |
| `h_elem`     | 6             | 2            | 24 elements, 12 on each of two ranks |
| `FLOAT_TYPE` | Float32       | Float64      | the precision of the column checks   |
| `t_end`      | 10 days       | 6 hours      | 1,080 steps, about 1–2 h per run     |
| energy tags  | 7 and records | none         | criterion 3 is about the water tags  |
| checkpoints  | daily         | every 30 min | 12 saved states per run              |

Water tags, in the tagged runs: the set of `docs/src/tagged_water.md`,
`tropics` and `extratropics` (a partition by latitude), `evap`
(`source: surface_flux`) and `evap_tropics`, with `water_closure_check`
(every 30 min, audit on).

Modes:

  - **default**: `water_tag_updraft_copy: false` and `water_tag_transport`
    unset. Under prognostic EDMF with ARS222, a partition tag and implicit 1M,
    `default_water_tag_transport` chooses `increment`. The run's log shows
    the choice.
  - **copies**: `water_tag_updraft_copy: true`. Eligible here: prognostic
    EDMF, and `edmfx_mse_q_tot_upwinding` equals `edmfx_tracer_upwinding`
    (both `first_order`, the defaults). The transport is then `tracer`.

Refusals checked (`src/config/tracer_config.jl` at `d3c5e42f`): no water-tag
check refers to the sphere or to MPI. The tags are refused under prognostic
EDMF with more than one updraft, under `amd_les`, and with explicit 1M under
the autodiff Jacobian. The copies are refused without prognostic EDMF and with
two upwinding schemes. `water_tag_precipitation` is refused under EDMF, so the
rain and snow tags are not part of this check. None of the refusals applies.

The six configs, `configs/w59_mpi_{untagged,default,copies}_r{1,2}.yml`, differ
only in `job_id` and the tag keys. `_r2` runs on `--ntasks=2`, `_r1` on one.

**A bound on what this covers.** The atmosphere starts dry
(`DecayingProfile`, G2's start). Its water comes from the surface flux, so the
region tags start at zero, and cloud and precipitation may be small or absent
in six hours. The run is a check of the MPI paths, not of the moist physics.
The column checks cover those. The score reports how much water, cloud and
precipitation the untagged two-rank run holds at 6 h, so the coverage is
stated.

## 3. Runs

Six jobs, one per config, all at once, logs in
`$SCRATCH/tag_closure/logs/w59_mpi/%x-%j.{out,err}`: `sbatch -A pn49go-c -p hpda2_compute`
through `runscripts/mpi_submit.sh`. It checks that the run tree is clean and
at `d3c5e42f`, that this record is pushed, and then calls `submit_g3.sh`,
which writes the manifest. The driver is `run_tag_closure.jl`, without changes
to the state. Two ranks: `--ntasks=2 --time=06:00:00 --mem=64G`. One rank:
`--ntasks=1 --time=10:00:00 --mem=48G`. The cap is eight jobs, so two remain
for a rerun after a failure that is not the model's (node, time limit).

## 4. Fields compared, and the pass rule

`analysis/water/mpi_score.sh` scores the runs, with two scripts.

  - `mpi_parity.jl parity`: every checkpoint (`day*.hdf5`). Each state is
    read whole on one process. Every property chain of the untagged `Y`, down
    to a scalar or a vector field, must be in the tagged `Y` and be equal bit
    for bit (raw bits, so signed zeros and NaN payloads count). This is the
    full prognostic state: `ρ`, `uₕ`, `u₃`, `ρe_tot`, `ρq_tot`, the 1M
    species, `ρtke`, and the updraft's fields. The tagged state may hold more
    fields: the tags, and in copies mode the tags' copies in the updraft.
  - `parity_untagged.py` (V-W3's script, unchanged): every NetCDF diagnostic
    the untagged run writes, at every output time (every 30 min, from 0 to
    6 h), bit for bit in the tagged run. That is 54 fields: the grid mean, the
    surface fluxes and precipitation, radiation, the updraft and environment,
    and the turbulence closure. They are interpolated to a latitude-longitude
    grid, so they sample the fields. The checkpoints cover every node.

Smoke of `mpi_parity.jl` before any job, on `g2_v2_sphere_n2`'s 24-rank
checkpoints: a state against itself passes (32 fields, exit 0); day 1 against
day 2 under the same name fails on 30 of the 32 fields (exit 1).

**Pass rule.** For each mode, default and copies, on two ranks: every field
of the untagged run equal bit for bit to the tagged run's at every saved time,
in both checks, with every checkpoint and every output time present in both.
One field that differs at one time fails the mode.

**Reported, not judged.** The same two checks on one rank. Then one rank
against two for each run, untagged and both modes: for each field of `Y`,
the tags included, how many points differ, the largest difference, and the
largest relative to the field's largest value (`mpi_parity.jl report`). The
order of the sums at the ranks' boundary may differ between one rank and two,
so these may differ at rounding. They decide nothing here. The closure
check's largest relative and gross relative residual over the run
(`water_tag_closure.csv`) is reported for the four tagged runs, and the
untagged two-rank run's largest `hus`, `clw`, `cli`, `husra`, `hussn`, `pr`
and `hfls` at 0 h and 6 h, as the coverage of section 2.

**If parity fails.** Bound the cause: which field, the first checkpoint at
which it differs, and whether the difference sits at the ranks' boundary or
everywhere. Then stop and report. No model code changes in this task.

## 5. Results

FINDINGS W59 (draft, 2026-10-02): both modes pass on two ranks, 0 of
884,736 state values and 0 of 54 diagnostics differ. The coverage numbers
of `mpi_score.sh` first read the NetCDF time axis wrongly; it was fixed
before anything was recorded. The judged checks compare whole arrays and were
not affected.

## 6. The CI column checks

Criterion 3 says the column checks run in CI. At `d3c5e42f`, each file below
compares the model's fields with those of the same column without tags, bit
for bit, and is in `KNOWN_TEST_GROUPS` (`test/runtests.jl`), which `ci.yml`
reads for its matrix:

| Test group                         | File                                                  | Column                         |
|:---------------------------------- |:----------------------------------------------------- |:------------------------------ |
| `tagging_water_edmf`               | `test/tagged_water_edmf_integration.jl`               | 1M EDMF, default mode          |
| `tagging_water_edmf_copies`        | `test/tagged_water_edmf_copies_integration.jl`        | 1M EDMF, copies, explicit 1M   |
| `tagging_water_edmf_0m`            | `test/tagged_water_edmf_0m_integration.jl`            | 0M EDMF                        |
| `tagging_water_edmf_0m_explicit`   | `test/tagged_water_edmf_0m_explicit_integration.jl`   | 0M EDMF, explicit microphysics |
| `tagging_water_increment`          | `test/tagged_water_increment_integration.jl`          | 1M EDMF, increment transport   |
| `tagging_water_increment_explicit` | `test/tagged_water_increment_explicit_integration.jl` | increment, explicit 1M         |

None of them runs on two ranks. CI has no MPI job for the tags. This run is
the two-rank evidence.

## 7. Amendment, 2026-10-02: the moist pair

Pre-registered after W59 (reviewed in `3caacd8e`, merged in `3740a028`) and
before any job of this amendment. The owner decided on 2026-10-02 to close
W59's bound: W59 started dry and held no cloud or rain by 6 h. Same model,
run tree, driver, scripts and mode definitions as sections 2 to 4.

**Configuration.** `configs/w59m_mpi_{untagged,default,copies}_r{1,2}.yml`
are W59's configs with two changes:

  - `initial_condition: MoistBaroclinicWaveWithEDMF`, the moist baroclinic
    wave with a draft area of 0.2 and no TKE at the start. It is the moist
    start the model supports under prognostic EDMF on a sphere
    (`src/setups/MoistBaroclinicWave.jl`). `DecayingProfile` carries no
    moisture.
  - No topography (`NoWarp`, the default), since the wave is balanced over a
    flat surface.

**Feasibility check before the jobs.** One untagged process on the login
node, 1 h of the `_r1` config, judges nothing. It shows that the start builds
and runs at h_elem 2. If it fails, nothing is submitted, and the amendment
is reported as not run. *Done before the push:* it returned `success` after
28 min on the login node, with every field finite. At 30 min its largest
`clw` was 5.1e-4, `cli` 2.5e-5, `husra` 2.5e-5 and `pr` 1.3e-4 (all 0 at
0 h), and `hus` was 1.8e-2. Output in
`$SCRATCH/claude_work/mpi/smoke_moist/` (not a record).

**Runs.** Six jobs, as in section 3: untagged, default and copies, each on two
ranks and on one. Prefix `w59m_mpi`, logs in
`$SCRATCH/tag_closure/logs/w59_mpi/`. No reruns: six jobs is the cap.

**Pass rule.** Section 4's rule, unchanged, on the two-rank runs, for each
mode. One rank, and one rank against two, are reported only. Scored by
`PREFIX=w59m_mpi MOIST_GATE=1 mpi_score.sh`.

**Moisture gate.** The untagged two-rank run must be moist. Its largest
`clw` must reach 1e-5 kg/kg, or its largest `husra` 1e-6 kg/kg, at some
30-min output after 0 h. If neither does, the amendment fails as
uninformative, whatever the parity says. `mpi_score.sh` checks the gate and
prints the two peaks. Its smoke on W59's dry runs reads NOT MOIST, as it
must (both peaks 0).

Reported beside the gate: the largest `cli`, `hussn` and `pr`, and the global
integrals of `ρq_lcl`, `ρq_rai` and `ρq_tot` at 6 h (`mpi_water.jl`).
