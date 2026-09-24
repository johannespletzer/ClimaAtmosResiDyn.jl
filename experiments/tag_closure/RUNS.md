# The run register

One row per run directory of `review/register/runs.csv` (H2, 2026-09-23):
its output, commit, date, job, purpose, the findings that use it, and where its
data lives. How to submit a run is in [README.md](README.md). What a run
established is in [FINDINGS.md](FINDINGS.md), under the IDs given here.

## Where the data lives

A run's data is in up to three places.

  - **The repository**, `output/<run>/`: the small text outputs. These are the
    closure and audit tables, the merged `<run>.yml`, `run.log`,
    `provenance.txt`, and any analysis text. `output/summary_a.csv` and
    `summary_c.csv` are the phase summaries, and `plots/` holds their figures.
    The old README's rules for this directory are in [README.md](README.md).
  - **Scratch**, `$SCRATCH/tag_closure/output/<run>/output_XXXX/`, that is
    `/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/`: the NetCDF
    diagnostics, the checkpoints and the full logs. `output_active` is a link
    to the newest `output_XXXX`. Scratch is not durable.
  - **The archive**, `~/git/Clima/ClimaAtmosResiDyn-archive/`: a copy of
    scratch, made on 2026-09-23 by the owner's decision.

The archive's own `README.md` describes it. In short:

  - `scratch_tag_closure/` is an exact copy of `$SCRATCH/tag_closure/`: run
    output, checkpoints, logs and profiles. Its `output/<run>/output_XXXX/`
    matches this register.
  - `scratch_claude_work/` is a copy of `$SCRATCH/claude_work/`, the agents'
    working files for past PRs: PR bodies, test logs, test environments.
  - `reference_data/` holds the minimal datasets behind the headline tables
    G3 relies on (W15 to W18, E73, E76, E62 to E66): hard links into the
    scratch copy, one directory per finding, with SHA-256 sums in its
    `MANIFEST.tsv`. At most 5 GB, by the owner's decision of 2026-09-23.
  - `worktrees/<name>/` holds, for each of the 27 worktrees of 2026-09-23, its
    commit (`HEAD.txt`), its local patch (`modified.patch`) and its untracked
    files (`untracked/`): job `.err` logs, and copies of `experiments/` with
    results written there. Git ignores `.out` logs, so for the 22 removed
    worktrees they were not captured and are lost (the archive README, "What
    was lost"). For the main clone and `-upd-run` they are in `ignored/`.
  - `git/ClimaAtmosResiDyn-all-2026-09-23.bundle` holds every branch and tag,
    and the 57 commits no ref reached on 2026-09-23.
  - `SHA256SUMS` lists every file. It is refreshed after each sync.

To use it, read from it in place. Do not write into it except to sync it.
Check a file against `SHA256SUMS` with `sha256sum -c` from the archive's root.
A NetCDF run that is gone from scratch can be read from
`scratch_tag_closure/output/<run>/output_XXXX/`, for example with
`analysis/evidence/compare_runs.py`.

**Sync it again before a worktree is removed or scratch is cleaned**, so
nothing written since is lost. From the archive's root:

    rsync -a /dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/ scratch_tag_closure/

For a worktree, capture its `HEAD.txt`, `modified.patch` and untracked files
again into `worktrees/<name>/`. The commands are in the archive's README.

**Last synced on 2026-09-23, after the day's reruns had finished.** That
includes the five default reruns at `dcf7d086` (10:57 to 11:05). The copy of
scratch, `scratch_tag_closure/`, holds 2,697 files, identical to scratch. With
`claude_work` (678) and the worktree captures (2,058) the archive holds 5,434
files.

## How to read the table

  - **Output** is the `output_XXXX` index on scratch, as the register gives it.
  - **Commit** is the one `provenance.txt` records, shortened. "(dirty)" means
    it records `commit_dirty: yes`. The old README warns that for the runs of
    2026-09-10 this may be the old runscript's failure path, not an
    observation. Where the commit is "—", the register found none.
  - **Config** "same" means `configs/<run>.yml`, and "none" that the output
    comes from an analysis script, not a model run.
  - **Repo** says whether the small tables are in `output/<run>/`.
  - **Scratch** and **Archive** give the NetCDF and checkpoint (`.hdf5`) files
    under the run's directory, each counted once, as checked on 2026-09-23
    around 11:30. "dir only" is a directory without them, and "none" no
    directory. The two columns agree for every run.
  - **The counts agree with the register,** which was corrected on this branch.
    An earlier version, and `output/SCRATCH_INVENTORY.md` of 2026-09-20, counted
    the newest output twice, through the `output_active` link. Each file is
    counted once: `c1c_base_d4_enthalpy` has 24 NetCDF files, not 48. The v3
    ladder's counts include the reruns of 2026-09-23.
  - **Corrections to the register:** `v3_upd_default` has outputs 0000 to 0005.
    The ladder rungs' commits and jobs are in the second table.
    `g2_v2_sphere_mix_oom_13538434` ran `configs/g2_v2_sphere_mix.yml`; the
    register names a file that does not exist.

## The runs

### Phase A: the water tags

| Run                    | Output | Config | Commit           | Date       | Job      | Purpose                                                                                              | Findings                                    | Repo | Scratch | Archive |
|:---------------------- |:------ |:------ |:---------------- |:---------- |:-------- |:---------------------------------------------------------------------------------------------------- |:------------------------------------------- |:---- |:------- |:------- |
| `a1_dt10`              | 0000   | same   | 3659746d (dirty) | 2026-09-10 | 27360483 | A1, van Leer, dt 10s.                                                                                | W1, T1, T2                                  | yes  | none    | none    |
| `a1_dt10_notags`       | 0000   | same   | c7c00de9 (dirty) | 2026-09-10 | 27368035 | A1 at dt 10s with no water tags; the cost baseline.                                                  | T1, T2                                      | yes  | none    | none    |
| `a1_dt2p5`             | 0000   | same   | 3659746d (dirty) | 2026-09-10 | 27360496 | A1, van Leer, dt 2.5s.                                                                               | W1                                          | yes  | none    | none    |
| `a1_dt5`               | 0000   | same   | 3659746d (dirty) | 2026-09-10 | 27360484 | A1, van Leer, dt 5s.                                                                                 | W1                                          | yes  | none    | none    |
| `a2_first_order_dt10`  | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360828 | A2, both upwinding keys first_order, dt 10s.                                                         | W1, W2                                      | yes  | none    | none    |
| `a2_first_order_dt2p5` | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360830 | A2, both upwinding keys first_order, dt 2.5s.                                                        | W1, W2                                      | yes  | none    | none    |
| `a2_first_order_dt5`   | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360829 | A2, both upwinding keys first_order, dt 5s.                                                          | W1, W2                                      | yes  | none    | none    |
| `a2_none_dt10`         | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360825 | A2, both upwinding keys none, dt 10s.                                                                | W1, W2                                      | yes  | none    | none    |
| `a2_none_dt2p5`        | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360827 | A2, both upwinding keys none, dt 2.5s.                                                               | W1, W2                                      | yes  | none    | none    |
| `a2_none_dt5`          | 0000   | same   | 66d6dedc (dirty) | 2026-09-10 | 27360826 | A2, both upwinding keys none, dt 5s.                                                                 | W1, W2                                      | yes  | none    | none    |
| `a3_0m_vert_diff`      | 0000   | same   | af9cee7d (dirty) | 2026-09-10 | 27369130 | A3's companion, 0M with vert_diff on, dt 10s, isolates the vertical-diffusion vs 1M contributions.   | W5, W5b                                     | yes  | none    | none    |
| `a3_1m`                | 0000   | same   | 49b2ec97 (dirty) | 2026-09-10 | 27361330 | A3, microphysics_model:1M, dt 10s.                                                                   | W5                                          | yes  | none    | none    |
| `a4_float32`           | 0000   | same   | 49b2ec97 (dirty) | 2026-09-10 | 27361268 | A4, FLOAT_TYPE:Float32, dt 10s.                                                                      | W4                                          | yes  | none    | none    |
| `a5_sphere_limiter`    | 0000   | same   | 8ed98b63 (dirty) | 2026-09-10 | 27367905 | A5, sphere with the SEM limiter, dt 300s, one day; the water-tag divergence (issue #64) and its fix. | W6, W7, W8, W9, W10, W11, W12, W13, W14, M1 | yes  | none    | none    |

### Phase B: the energy tag family

| Run       | Output | Config | Commit   | Date       | Job      | Purpose                                                                                                | Findings | Repo | Scratch | Archive |
|:--------- |:------ |:------ |:-------- |:---------- |:-------- |:------------------------------------------------------------------------------------------------------ |:-------- |:---- |:------- |:------- |
| `b1_base` | 0000   | same   | 38661891 | 2026-09-18 | 13501290 | B1, hyperdiffusion and vertical diffusion both on; 10-day moist baroclinic wave energy-tag family run. | E50      | yes  | 3 nc    | 3 nc    |

### Phase C: the energy source tags

| Run                          | Output                                                                                               | Config | Commit           | Date       | Job      | Purpose                                                                                                                                                                                             | Findings                                                         | Repo | Scratch  | Archive  |
|:---------------------------- |:---------------------------------------------------------------------------------------------------- |:------ |:---------------- |:---------- |:-------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------- |:---- |:-------- |:-------- |
| `c0_column`                  | 0000                                                                                                 | same   | 49b2ec97 (dirty) | 2026-09-10 | 27361326 | C0, DYCOMS source column with rad:DYCOMS, one day; the barrier census.                                                                                                                              | E1, E2, E3, E4, E5, E6, R2                                       | yes  | none     | none     |
| `c0_column_notags`           | 0000                                                                                                 | same   | c7c00de9 (dirty) | 2026-09-10 | 27368036 | C0's column with no source tags; the cost baseline.                                                                                                                                                 | T3, T4                                                           | yes  | none     | none     |
| `c0_sphere`                  | 0000                                                                                                 | same   | 49b2ec97 (dirty) | 2026-09-10 | 27361327 | C0, moist sphere, one day; the barrier census.                                                                                                                                                      | E1, E5, E6, M5                                                   | yes  | none     | none     |
| `c0_sphere_audit`            | 0000                                                                                                 | same   | bcbe190f (dirty) | 2026-09-10 | 27369268 | c0_sphere with audit:true and nothing else changed; the mass-fraction / audit-table baseline reused as C1/C4's baseline.                                                                            | E9b, E9c, M1, M6                                                 | yes  | 4 nc     | 4 nc     |
| `c0_sphere_deep`             | 0000                                                                                                 | same   | ce769194         | 2026-09-10 | 27369030 | Failed, exit status 1. C0's depth control: the same sphere on the 60km grid; dropped as redundant with where_negative.jl / c0_sphere_audit. The config stays (LEVANTE_TASKS, register item `LT-1`). | (none; superseded before use)                                    | yes  | none     | none     |
| `c10_sphere_enthalpy_repair` | 0000                                                                                                 | same   | 7dc0a302         | 2026-09-11 | 13403083 | C10, c9_sphere_enthalpy with the repair on and its ledgers in the output (old README). The register recorded no purpose.                                                                            | E35, E36, E38, E46, E49, M6 (the FINDINGS entries that name C10) | yes  | 19 nc    | 19 nc    |
| `c1_sphere_shift`            | 0000                                                                                                 | same   | 72a1bc6a         | 2026-09-10 | 13383684 | C1, c0_sphere_audit under the reference shift, delta=-110K.                                                                                                                                         | E11, E12, E13, E14, E15, E16, R7, R8, T6                         | yes  | 4 nc     | 4 nc     |
| `c3_column_record`           | 0000                                                                                                 | same   | 1a9a419e (dirty) | 2026-09-10 | 27367733 | C3, c0_column with energy_process_record beside the tags.                                                                                                                                           | E7, E8, E9                                                       | yes  | none     | none     |
| `c4_sphere_tag_offset`       | 0000                                                                                                 | same   | 29430612         | 2026-09-10 | 13384913 | C4, c0_sphere_audit with the tags on rho*e_tot + c*rho, c=110,495 J/kg.                                                                                                                             | E17, E18, T7                                                     | yes  | 5 nc     | 5 nc     |
| `c4_sphere_tag_offset_2x`    | 0000                                                                                                 | same   | 29430612         | 2026-09-10 | 13384914 | C4 at twice the offset, on the identical atmosphere.                                                                                                                                                | E17, E19, T7                                                     | yes  | 5 nc     | 5 nc     |
| `c5_column_offset`           | 0000                                                                                                 | same   | bca389ba         | 2026-09-10 | 13385401 | C5, C3's column with the offset, per-process tags, two records and rhoa.                                                                                                                            | E20, E21, E22, E23                                               | yes  | 10 nc    | 10 nc    |
| `c5_sphere_gray`             | 0000                                                                                                 | same   | bca389ba         | 2026-09-10 | 13385402 | C5, C4's sphere with rad:gray, per-process tags and two records.                                                                                                                                    | E20, E21, E24                                                    | yes  | 9 nc     | 9 nc     |
| `c6_column_no_repair`        | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f3bbdb7b         | 2026-09-10 | 13385451 | c6_column_repair with the repair off.                                                                                                                                                               | E25, E26                                                         | yes  | 29 nc    | 29 nc    |
| `c6_column_repair`           | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f3bbdb7b         | 2026-09-10 | 13385450 | C6, C5's column on the bracket and the repair.                                                                                                                                                      | E26, E29, T8                                                     | yes  | 29 nc    | 29 nc    |
| `c6_sphere_first_order`      | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f3bbdb7b         | 2026-09-10 | 13385454 | c6_sphere_no_repair with the tags moved by first-order upwinding.                                                                                                                                   | E29                                                              | yes  | 24 nc    | 24 nc    |
| `c6_sphere_no_repair`        | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f3bbdb7b         | 2026-09-10 | 13385453 | c6_sphere_repair with the repair off.                                                                                                                                                               | E28, E29, E46                                                    | yes  | 24 nc    | 24 nc    |
| `c6_sphere_repair`           | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f3bbdb7b         | 2026-09-10 | 13385452 | C6, C5's sphere on the bracket and the repair.                                                                                                                                                      | E27, E46, T8                                                     | yes  | 24 nc    | 24 nc    |
| `c6_sphere_wide_mask`        | 0000 (failed startup, missing e_src_fix function) + 0001 (resubmitted on f3bbdb7b, the one analysed) | same   | f399b9f8         | 2026-09-14 | 13441633 | The C6 twin with the region masks 10 degrees wide instead of 2.                                                                                                                                     | E48                                                              | yes  | 17 nc    | 17 nc    |
| `c7_sphere_mp`               | 0000                                                                                                 | same   | 414f5f1b         | 2026-09-11 | 13399601 | C7, c6_sphere_no_repair with an mp tag on source:microphysics.                                                                                                                                      | E30, E31, E45, E47, T9                                           | yes  | 12 nc    | 12 nc    |
| `c8_column_1m`               | 0000                                                                                                 | same   | c11d1d3b         | 2026-09-11 | 13401744 | C8, c6_column_repair under 1-moment microphysics, with sedimentation moving the tags, a day.                                                                                                        | E33, E43                                                         | yes  | 24 nc    | 24 nc    |
| `c9_column_enthalpy`         | 0000                                                                                                 | same   | 0bfb5037         | 2026-09-11 | 13402392 | C9, c6_column_no_repair with the tags moved as enthalpy.                                                                                                                                            | E34, E39                                                         | yes  | 21 nc    | 21 nc    |
| `c9_sphere_enthalpy`         | 0000                                                                                                 | same   | 0bfb5037         | 2026-09-11 | 13402393 | C9, c7_sphere_mp with the tags moved as enthalpy.                                                                                                                                                   | E34, E36, E38, E39b                                              | yes  | 12 nc    | 12 nc    |
| `twin_c1`                    | 0000                                                                                                 | same   | 72a1bc6a         | 2026-09-10 | 13383683 | A twin test; it exits 1 by design when the twins differ. C1 twin test: the model with and without the reference shift, one step and a day.                                                          | E16                                                              | yes  | dir only | dir only |
| `twin_c1_limiter_off`        | 0000                                                                                                 | same   | 9b00e7b1         | 2026-09-10 | 13384884 | A twin test; it exits 1 by design when the twins differ. Twin with the van Leer energy limiter switched off in both halves.                                                                         | E16                                                              | yes  | dir only | dir only |
| `twin_c1_limiter_off_no_sfc` | 0000                                                                                                 | same   | 9e796fac         | 2026-09-10 | 13385303 | A twin test; it exits 1 by design when the twins differ. Twin with the limiter off and the surface-flux tendency off in both halves.                                                                | E16                                                              | yes  | dir only | dir only |
| `twin_c1_newton`             | 0000                                                                                                 | same   | 4a40838f         | 2026-09-10 | 13384080 | A twin test; it exits 1 by design when the twins differ. Twin with the Newton solve converged in both halves.                                                                                       | E16                                                              | yes  | dir only | dir only |

### Phase D and P4: sub-grid transport, ice, and the EDMF build time

| Run                         | Output                                                | Config | Commit   | Date       | Job      | Purpose                                                                                       | Findings | Repo | Scratch  | Archive  |
|:--------------------------- |:----------------------------------------------------- |:------ |:-------- |:---------- |:-------- |:--------------------------------------------------------------------------------------------- |:-------- |:---- |:-------- |:-------- |
| `d1_column_1m_ice`          | 0000                                                  | same   | 78586e39 | 2026-09-11 | 13404535 | D1, PrecipitatingColumn under 1M: ice through sedimentation's upward branch, an hour.         | E42      | yes  | 18 nc    | 18 nc    |
| `d1_column_1m_ice_no_vdiff` | 0000                                                  | same   | cf1e9c7c | 2026-09-11 | 13412243 | D1 with vertical diffusion off, to separate the upward branch from diffusion.                 | E42b     | yes  | 18 nc    | 18 nc    |
| `d4_column_edmf`            | 0000 (placeholder, no data) + 0001 (the analysed run) | same   | fe69cd06 | 2026-09-18 | 13503558 | D4, DYCOMS RF02 EDMF column with C1b's sharing, tags on tracer transport, a day.              | E53      | yes  | 24 nc    | 24 nc    |
| `d4_column_edmf_enthalpy`   | 0000 (placeholder, no data) + 0001 (the analysed run) | same   | fe69cd06 | 2026-09-18 | 13503559 | d4_column_edmf with the tags moved as enthalpy.                                               | E53      | yes  | 24 nc    | 24 nc    |
| `d4_column_edmf_notags`     | 0000                                                  | same   | 41adabc5 | 2026-09-11 | 13414334 | D4's column with no tags, for an hour; the EDMF-build-time control.                           | E44      | yes  | dir only | dir only |
| `d4_column_edmf_vd`         | 0000                                                  | same   | fe69cd06 | 2026-09-18 | 13503560 | d4_column_edmf with the updrafts' vertical diffusion on (shipped setting), under C1b's guard. | E53      | yes  | 24 nc    | 24 nc    |
| `d4_column_edmf_vd_float32` | 0000                                                  | same   | 9dd30a90 | 2026-09-18 | 13503987 | d4_column_edmf_vd in Float32; C1b's sharing at production precision.                          | E55      | yes  | 24 nc    | 24 nc    |
| `d5_column_edmf_ice`        | 0000                                                  | same   | fe69cd06 | 2026-09-18 | 13503561 | D5, TRMM LBA EDMF deep convection under 1M, 6h.                                               | E53      | yes  | 21 nc    | 21 nc    |
| `p4_edmf_tags`              | 0000                                                  | same   | edd44e1d | 2026-09-11 | 13415604 | P4, D4's column with its 8 tags only, for build time.                                         | E44b     | yes  | dir only | dir only |
| `p4_edmf_two_tags`          | 0000                                                  | same   | edd44e1d | 2026-09-11 | 13415603 | P4, D4's column with its two region tags only, for build time.                                | E44b     | yes  | dir only | dir only |

### C1c: the SGS diffusive flux under the audit (shelved)

| Run                           | Output | Config | Commit   | Date       | Job      | Purpose                                                                                                                                   | Findings | Repo | Scratch | Archive |
|:----------------------------- |:------ |:------ |:-------- |:---------- |:-------- |:----------------------------------------------------------------------------------------------------------------------------------------- |:-------- |:---- |:------- |:------- |
| `c1c_base_d4_enthalpy`        | 0000   | same   | 50b2a4d2 | 2026-09-18 | 13504651 | The C1c comparison: d4_column_edmf_enthalpy on main without C1c (old README). The register recorded no purpose.                           | E59, E62 | yes  | 24 nc   | 24 nc   |
| `c1c_opt1_d4_enthalpy`        | 0000   | same   | 9aeb5205 | 2026-09-18 | 13504652 | The C1c comparison: option 1, the tags' share beside the parent's flux, no Jacobian block (old README). The register recorded no purpose. | E59      | yes  | 24 nc   | 24 nc   |
| `c1c_opt1_newton_d4_enthalpy` | 0000   | same   | 9aeb5205 | 2026-09-18 | 13504771 | The C1c diagnostic: option 1 with a converged Newton solve, 12 hours (old README). The register recorded no purpose.                      | E61      | yes  | 24 nc   | 24 nc   |
| `c1c_opt2_d4_enthalpy`        | 0000   | same   | 9aeb5205 | 2026-09-18 | 13504653 | The C1c comparison: option 1 with the tags' tracer-diffusion blocks kept (old README). The register recorded no purpose.                  | E59      | yes  | 24 nc   | 24 nc   |
| `c1c_opt3_d4_enthalpy`        | 0000   | same   | 9aeb5205 | 2026-09-18 | 13504654 | The C1c comparison: option 1 with the tags' share in the explicit tendency (old README). The register recorded no purpose.                | E59      | yes  | 24 nc   | 24 nc   |

### Operational checks: Float32, MPI, cost, restarts

| Run                       | Output | Config | Commit   | Date       | Job      | Purpose                                                                                           | Findings | Repo | Scratch       | Archive       |
|:------------------------- |:------ |:------ |:-------- |:---------- |:-------- |:------------------------------------------------------------------------------------------------- |:-------- |:---- |:------------- |:------------- |
| `mp1_sphere_4ranks`       | 0000   | same   | c2842ba6 | 2026-09-14 | 13440991 | MP1, c7_sphere_mp on 4 MPI ranks.                                                                 | E47      | yes  | 12 nc         | 12 nc         |
| `p1_sphere_notags`        | 0000   | same   | c2842ba6 | 2026-09-14 | 13440990 | P1, c7_sphere_mp without tags, records, check or diagnostics; the untagged half of the cost pair. | T9       | yes  | dir only      | dir only      |
| `p1_sphere_tags`          | 0000   | same   | c2842ba6 | 2026-09-14 | 13440989 | P1, c7_sphere_mp under its own name, the tagged half of the cost pair.                            | T9       | yes  | 12 nc         | 12 nc         |
| `v3_sphere_float32`       | 0000   | same   | 297eda4c | 2026-09-14 | 13440822 | V3 (operational check), c7_sphere_mp in Float32.                                                  | E45      | yes  | 12 nc         | 12 nc         |
| `v5_c5_continuous`        | 0000   | same   | e4e9e5b3 | 2026-09-18 | 13503985 | V5, C5's column for a day with a checkpoint every 12 hours, reproducible_restart:true.            | E54      | yes  | 10 nc, 2 hdf5 | 10 nc, 2 hdf5 |
| `v5_c5_continuous_notags` | 0000   | same   | e4e9e5b3 | 2026-09-18 | 13504312 | V5's follow-up: v5_c5_continuous without tags, records or closure check.                          | E58      | yes  | 0 nc, 2 hdf5  | 0 nc, 2 hdf5  |
| `v5_c5_restarted`         | 0000   | same   | e4e9e5b3 | 2026-09-18 | 13503986 | V5, the same run restarted from its twin's checkpoint at 12 hours, through C2's guard.            | E54      | yes  | 10 nc, 1 hdf5 | 10 nc, 1 hdf5 |
| `v5_c5_restarted_notags`  | 0000   | same   | e4e9e5b3 | 2026-09-18 | 13504313 | V5's follow-up: the same run without tags, restarted from its twin's checkpoint at 12 hours.      | E58      | yes  | 0 nc, 1 hdf5  | 0 nc, 1 hdf5  |

### G1: the increment prototype on D4

| Run                         | Output | Config | Commit   | Date       | Job      | Purpose                                                                                      | Findings | Repo | Scratch | Archive |
|:--------------------------- |:------ |:------ |:-------- |:---------- |:-------- |:-------------------------------------------------------------------------------------------- |:-------- |:---- |:------- |:------- |
| `g1_base_d4_float32`        | 0000   | same   | 50b2a4d2 | 2026-09-19 | 13504828 | c1c_base_d4_enthalpy in Float32; the baseline of G1's Float32 twin.                          | E65      | yes  | 24 nc   | 24 nc   |
| `g1_inc_d4`                 | 0000   | same   | c0bc637f | 2026-09-19 | 13504889 | The increment prototype on D4 with its ledger written hourly, a day.                         | E64      | yes  | 26 nc   | 26 nc   |
| `g1_inc_d4_2c`              | 0000   | same   | c0bc637f | 2026-09-19 | 13509167 | g1_inc_d4 with c=220,990 J/kg (2x offset), identical atmosphere.                             | E71      | yes  | 26 nc   | 26 nc   |
| `g1_inc_d4_float32`         | 0000   | same   | c0bc637f | 2026-09-19 | 13504891 | The prototype in Float32, G1's Float32 twin.                                                 | E65      | yes  | 26 nc   | 26 nc   |
| `g1_inc_newton10_d4`        | 0000   | same   | c0bc637f | 2026-09-19 | 13504927 | The prototype with the reference's fixed ten Newton iterations, a day.                       | E66      | yes  | 26 nc   | 26 nc   |
| `g1_inc_newton_d4`          | 0000   | same   | c0bc637f | 2026-09-19 | 13504890 | The prototype with the reference's converged Newton solve, a day.                            | E64      | yes  | 26 nc   | 26 nc   |
| `g1_ref_newton10_d4`        | 0000   | same   | 9aeb5205 | 2026-09-19 | 13504926 | G1's per-flux reference (option 1, converged solve) with ten Newton iterations fixed, a day. | E66      | yes  | 24 nc   | 24 nc   |
| `g1_ref_newton_d4`          | 0000   | same   | 9aeb5205 | 2026-09-19 | 13504827 | G1's reference for the tags' correctness: option 1 with a converged Newton solve, a day.     | E61      | yes  | 24 nc   | 24 nc   |
| `inc_d4_enthalpy_increment` | 0000   | same   | 35042f33 | 2026-09-19 | 13504818 | The increment prototype: D4 under enthalpy_increment.                                        | E62      | yes  | 24 nc   | 24 nc   |

### G2: V2, the production physics on a sphere

| Run                             | Output | Config                         | Commit   | Date       | Job      | Purpose                                                                                                                                                                                                                                                                    | Findings                                                                  | Repo | Scratch        | Archive        |
|:------------------------------- |:------ |:------------------------------ |:-------- |:---------- |:-------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------- |:---- |:-------------- |:-------------- |
| `g2_v2_diag_newton2`            | 0000   | same                           | —        | —          | —        | 2-hour diagnostic slice of V2 with two Newton iterations, one process, in Float32.                                                                                                                                                                                         | E70                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_diag_nosponge`           | 0000   | same                           | 04d63916 | 2026-09-19 | 13505762 | 3-hour V2 diagnostic variant with sponges off, to test the model-top collapse cause.                                                                                                                                                                                       | E69                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_diag_notopo`             | 0000   | same                           | 04d63916 | 2026-09-19 | 13505764 | 3-hour V2 diagnostic variant with no mountain, to test the model-top collapse cause.                                                                                                                                                                                       | E69                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_f64_2h`                  | 0000   | same                           | 04d63916 | 2026-09-19 | 13509165 | g2_v2_diag_newton2's 2 hours rerun in Float64, to split rounding from structure.                                                                                                                                                                                           | E70                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_nosponge_2h`             | 0000   | same                           | 04d63916 | 2026-09-19 | 13509166 | The same 2 hours in Float32 without sponges.                                                                                                                                                                                                                               | E70                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_sphere`                  | 0000   | same                           | 04d63916 | 2026-09-19 | 13504999 | V2: the production physics on a sphere under the prototype, Float32, ten days, one Newton iteration (model-top collapse found).                                                                                                                                            | E69, E72                                                                  | yes  | 16 nc, 10 hdf5 | 16 nc, 10 hdf5 |
| `g2_v2_sphere_mix`              | 0000   | same                           | 846ef55d | 2026-09-21 | 13548198 | V2's ten days again from the branch that mixes provenance through the updrafts (E73's default), two Newton iterations.                                                                                                                                                     | E75                                                                       | yes  | 16 nc, 10 hdf5 | 16 nc, 10 hdf5 |
| `g2_v2_sphere_mix_oom_13538434` | 0000   | `configs/g2_v2_sphere_mix.yml` | 846ef55d | 2026-09-21 | 13538434 | Killed for memory. First attempt at g2_v2_sphere_mix, killed for memory (asked 200GB, needed ~500GB); superseded by job 13548198. The register names `configs/g2_v2_sphere_mix_oom_13538434.yml`, which does not exist; the run's provenance names `g2_v2_sphere_mix.yml`. | (supersedes into E75's run)                                               | no   | 16 nc          | 16 nc          |
| `g2_v2_sphere_n2`               | 0000   | same                           | 04d63916 | 2026-09-19 | 13505896 | V2 again with two Newton iterations, after one iteration collapsed the model top; ten days.                                                                                                                                                                                | E74                                                                       | yes  | 16 nc, 10 hdf5 | 16 nc, 10 hdf5 |
| `g2_v2_sphere_newton10`         | 0000   | same                           | 04d63916 | 2026-09-19 | 13505000 | V2's twin with ten fixed Newton iterations, first day, for per-tag correctness.                                                                                                                                                                                            | E74                                                                       | yes  | 16 nc          | 16 nc          |
| `g2_v2_sphere_test`             | 0000   | same                           | 04d63916 | 2026-09-19 | 13504957 | V2's feasibility run: production physics on a sphere under the prototype, Float32, two hours.                                                                                                                                                                              | (feasibility check, referenced in OPERATIONAL_TODO G1 'On the way to G2') | yes  | 16 nc          | 16 nc          |

### V3 and the updraft gap, with the R2 ladder

| Run                                         | Output                                                                                                        | Config | Commit   | Date       | Job      | Purpose                                                                                                                                               | Findings                                           | Repo | Scratch | Archive |
|:------------------------------------------- |:------------------------------------------------------------------------------------------------------------- |:------ |:-------- |:---------- |:-------- |:----------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------- |:---- |:------- |:------- |
| `v3_d4_passive_tracer`                      | 0000                                                                                                          | same   | 04d63916 | 2026-09-19 | 13505756 | V3: a passive tracer with an updraft copy beside the tags on D4, for the updraft gap.                                                                 | E68                                                | yes  | 30 nc   | 30 nc   |
| `v3_upd_copies`                             | 0000                                                                                                          | same   | 3ec098f1 | 2026-09-19 | 13523326 | D4 under the updraft-gap fix, audit mode (updraft copies of the tags).                                                                                | E73                                                | yes  | 30 nc   | 30 nc   |
| `v3_upd_copies_dt30`                        | 0001 (below)                                                                                                  | same   | below    | 2026-09-23 | below    | V-W4-style ladder rung: copies mode at dt 30s (scratch only, not yet copied back).                                                                    | (R2 ladder, job session; not yet a FINDINGS entry) | no   | 30 nc   | 30 nc   |
| `v3_upd_copies_dt60`                        | 0001 (below)                                                                                                  | same   | below    | 2026-09-23 | below    | Ladder rung: copies mode at dt 60s (scratch only).                                                                                                    | (R2 ladder, job session)                           | no   | 30 nc   | 30 nc   |
| `v3_upd_copies_newton2`                     | 0001 (below)                                                                                                  | same   | below    | 2026-09-23 | below    | Ladder rung: copies mode with two Newton iterations (scratch only).                                                                                   | (R2 ladder, job session)                           | no   | 30 nc   | 30 nc   |
| `v3_upd_copies_upwind`                      | 0001 (below)                                                                                                  | same   | below    | 2026-09-23 | below    | Ladder rung: copies mode with first-order upwinding (scratch only).                                                                                   | (R2 ladder, job session)                           | no   | 30 nc   | 30 nc   |
| `v3_upd_default`                            | 0000-0005 (at e010f780, 38278c2d, 846ef55d, e71430fb, dbe7435c and dcf7d086; the last two in the table below) | same   | e010f780 | 2026-09-19 | 13528772 | D4 under the updraft-gap fix, default mode (zero-sum exchange); reran multiple times at head as the plume/blend-factor code changed.                  | E73                                                | yes  | 180 nc  | 180 nc  |
| `v3_upd_default_dt30`                       | 0001, 0002 (below)                                                                                            | same   | below    | 2026-09-23 | below    | Ladder rung: default mode at dt 30s (scratch only).                                                                                                   | (R2 ladder, job session)                           | no   | 90 nc   | 90 nc   |
| `v3_upd_default_dt60`                       | 0001, 0002 (below)                                                                                            | same   | below    | 2026-09-23 | below    | Ladder rung: default mode at dt 60s (scratch only).                                                                                                   | (R2 ladder, job session)                           | no   | 90 nc   | 90 nc   |
| `v3_upd_default_newton2`                    | 0001, 0002 (below)                                                                                            | same   | below    | 2026-09-23 | below    | Ladder rung: default mode with two Newton iterations (scratch only).                                                                                  | (R2 ladder, job session)                           | no   | 90 nc   | 90 nc   |
| `v3_upd_default_prefix_e010f780_superseded` | 0000                                                                                                          | same   | 3ec098f1 | 2026-09-19 | 13523325 | Superseded by `v3_upd_default`. First default-mode run at e010f780, whose shares were normalised over all tags rather than the partition; superseded. | E73 (superseded run, noted in its evidence)        | yes  | 30 nc   | 30 nc   |
| `v3_upd_default_upwind`                     | 0001, 0002 (below)                                                                                            | same   | below    | 2026-09-23 | below    | Ladder rung: default mode with first-order upwinding (scratch only).                                                                                  | (R2 ladder, job session)                           | no   | 90 nc   | 90 nc   |

### G3: the water tags under EDMF

Every G3 run is stamped with a manifest at submission, kept as
`output/<run>/manifest.json`, and launched from `../ClimaAtmosResiDyn-wedmf-run`.

| Run                           | Output | Config | Commit   | Date       | Job        | Purpose                                                                                 | Findings | Repo | Scratch | Archive |
|:----------------------------- |:------ |:------ |:-------- |:---------- |:---------- |:--------------------------------------------------------------------------------------- |:-------- |:---- |:------- |:------- |
| `w0a_0m_newton1`              | 0000   | same   | c537903b | 2026-09-23 | `13829854` | V-W0a: known issue 4 on a 0M column without EDMF, one day, one Newton iteration         | W15      | yes  | 15 nc   | not yet |
| `w0a_0m_newton10`             | 0000   | same   | c537903b | 2026-09-23 | `13829855` | the same with ten iterations                                                            | W15      | yes  | 15 nc   | not yet |
| `w0a_0m_implicit_newton1_2h`  | 0000   | same   | 2a6f1294 | 2026-09-23 | `13831761` | V-W0a's controlled pairs: the rain-out hour, implicit microphysics, one iteration       | W16      | yes  | 15 nc   | not yet |
| `w0a_0m_implicit_newton10_2h` | 0000   | same   | 2a6f1294 | 2026-09-23 | `13831762` | implicit microphysics, ten iterations                                                   | W16      | yes  | 15 nc   | not yet |
| `w0a_0m_explicit_newton1_2h`  | 0000   | same   | 2a6f1294 | 2026-09-23 | `13831763` | explicit microphysics, one iteration: the control, with the 0M sink off the Newton path | W16      | yes  | 15 nc   | not yet |
| `w0a_0m_explicit_newton10_2h` | 0000   | same   | 2a6f1294 | 2026-09-23 | `13831764` | explicit microphysics, ten iterations                                                   | W16      | yes  | 15 nc   | not yet |
| `w0c_d4w_untagged`            | 0000   | same   | c537903b | 2026-09-23 | `13829852` | V-W0c and V-W1's twin: D4-W with no water tags, with the EDMF diagnostics that size WP3 | W17, W18 | yes  | 37 nc   | not yet |
| `w1_d4w_grid_tags`            | 0000   | same   | c537903b | 2026-09-23 | `13829853` | V-W1: D4-W with grid-scale water tags on `main` after #95, the "before"                 | W17      | yes  | 48 nc   | not yet |
| `w3_d4w_default`              | 0000   | same   | 9085e264 | 2026-09-23 | `13857585` | V-W3: D4-W, WP3's default mode (exchange), a day, one Newton iteration                  | W21      | yes  | 52 nc   | not yet |
| `w3_d4w_default_n10`          | 0000   | same   | 9085e264 | 2026-09-23 | `13857591` | its 10-Newton twin, for WP5's rule                                                      | W21      | yes  | 52 nc   | not yet |
| `w3_d4w_copies`               | 0000   | same   | b5f40586 | 2026-09-23 | `13862420` | V-W3: D4-W, updraft copies started from the plume, one iteration: the audit             | W21      | yes  | 56 nc   | not yet |
| `w3_d4w_copies_n10`           | 0000   | same   | b5f40586 | 2026-09-23 | `13862422` | its 10-Newton twin                                                                      | W21      | yes  | 56 nc   | not yet |
| `w3_d4w_pulse_default`        | 0000   | same   | 9085e264 | 2026-09-23 | `13857587` | V-W3's surface pulse: the partition split at 50 m, default mode                         | W21      | yes  | 48 nc   | not yet |
| `w3_d4w_pulse_copies`         | 0000   | same   | b5f40586 | 2026-09-23 | `13862421` | the surface pulse, copies                                                               | W21      | yes  | 52 nc   | not yet |
| `w3_trmm0m_default`           | 0000   | same   | 9085e264 | 2026-09-23 | `13857589` | V-W3: the TRMM 0M development case, 3 h, default mode                                   | W21      | yes  | 32 nc   | not yet |
| `w3_trmm0m_copies`            | 0000   | same   | 9085e264 | 2026-09-23 | `13857590` | the TRMM case, copies                                                                   | W21      | yes  | 35 nc   | not yet |
| `w3_trmm0m_default_n10`       | 0000   | same   | d06e48f1 | 2026-09-23 | `13863850` | the TRMM Newton ladder: default, ten iterations                                         | W21      | yes  | 32 nc   | not yet |
| `w3_trmm0m_copies_n2`         | 0000   | same   | d06e48f1 | 2026-09-23 | `13863847` | the ladder: copies, two iterations                                                      | W21      | yes  | 35 nc   | not yet |
| `w3_trmm0m_copies_n10`        | 0000   | same   | d06e48f1 | 2026-09-23 | `13863849` | the ladder: copies, ten iterations                                                      | W21      | yes  | 35 nc   | not yet |
| `w8_gcm_tags`                 | 0000   | same   | 837db55b | 2026-09-24 | `13866552` | V-W8: the GCM-driven file-based column with water and energy source tags, 3 h           | W22      | yes  | 39 nc   | not yet |
| `w8_gcm_untagged`             | 0000   | same   | 837db55b | 2026-09-24 | `13866551` | its untagged twin, for parity                                                           | W22      | yes  | 25 nc   | not yet |
| `w5_d4w_increment`            | 0000   | same   | 9acb4956 | 2026-09-24 | `13868824` | WP5's validation: D4-W, the default mode with the follower, one Newton iteration        | W24      | yes  | 54 nc   | not yet |
| `w5_d4w_increment_n10`        | 0000   | same   | 9acb4956 | 2026-09-24 | `13868825` | its 10-Newton twin                                                                      | W24      | yes  | 54 nc   | not yet |
| `w4_d4w_default_dt60`         | 0000   | same   | 1db57be5 | 2026-09-24 | `13870224` | V-W4: D4-W, dt 60 s, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_dt60`          | 0000   | same   | 1db57be5 | 2026-09-24 | `13870217` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_dt30`         | 0000   | same   | 1db57be5 | 2026-09-24 | `13870223` | V-W4: D4-W, dt 30 s, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_dt30`          | 0000   | same   | 1db57be5 | 2026-09-24 | `13870216` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_n2`           | 0000   | same   | 1db57be5 | 2026-09-24 | `13870225` | V-W4: D4-W, two Newton iterations, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_n2`            | 0000   | same   | 1db57be5 | 2026-09-24 | `13870218` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_n4`           | 0000   | same   | 1db57be5 | 2026-09-24 | `13870226` | V-W4: D4-W, four Newton iterations, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_n4`            | 0000   | same   | 1db57be5 | 2026-09-24 | `13870219` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_z60`          | 0000   | same   | 1db57be5 | 2026-09-24 | `13870229` | V-W4: D4-W, 60 levels, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_z60`           | 0000   | same   | 1db57be5 | 2026-09-24 | `13870222` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_z120`         | 0000   | same   | 1db57be5 | 2026-09-24 | `13870228` | V-W4: D4-W, 120 levels, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_z120`          | 0000   | same   | 1db57be5 | 2026-09-24 | `13870221` | the same rung with copies | W25      | yes  | 56 nc   | not yet |
| `w4_d4w_default_upwind`       | 0000   | same   | 1db57be5 | 2026-09-24 | `13870227` | V-W4: D4-W, first-order SGS-flux upwinding, the default mode with the follower | W25      | yes  | 54 nc   | not yet |
| `w4_d4w_copies_upwind`        | 0000   | same   | 1db57be5 | 2026-09-24 | `13870220` | the same rung with copies; aborted at 24 h by the closure check (1.06) | W25      | no  | 56 nc   | not yet |
| `w4a_trmm0m_default`          | 0000   | same   | 3a8f1c70 | 2026-09-24 | `13876508` | WP4a's validation: TRMM 0M, 3 h, the split, default mode | W26      | yes  | 37 nc   | not yet |
| `w4a_trmm0m_copies`           | 0000   | same   | 3a8f1c70 | 2026-09-24 | `13876509` | the same with copies | W26      | yes  | 40 nc   | not yet |
| `w4a_trmm0m_default_6h`       | 0000   | same   | 34f9a334 | 2026-09-24 | `13877542` | TRMM 0M, 6 h, the split, default mode | W26      | yes  | 37 nc   | not yet |
| `w4a_trmm0m_copies_6h`        | 0000   | same   | 34f9a334 | 2026-09-24 | `13877543` | the same with copies | W26      | yes  | 40 nc   | not yet |
| `w4a_trmm0m_default_6h_grid`  | 0000   | same   | 9abb1f62 | 2026-09-24 | `13877544` | the grid rule's twin at #102's head, default mode | W26      | yes  | 32 nc   | not yet |
| `w4a_trmm0m_copies_6h_grid`   | 0000   | same   | 9abb1f62 | 2026-09-24 | `13877545` | the same with copies | W26      | yes  | 35 nc   | not yet |

The commits of the `w3_*` rows are the run tree's. They carry WP3 at
`9aab6690` (`9085e264`) or at `fe1331f2` (`b5f40586`, `d06e48f1`); W21 says
why the runs describe #101's head too. The verifier's reports are in
`output/w3_d4w/` and `output/w3_trmm0m/`.

The D4-W runs use the driver `analysis/water/d4w_driver.jl`, which sets the
passive tracer to the `tropo` mask. For the `w3_*` copies it also starts the
copies from the default mode's plume.

### Analysis outputs, not model runs

| Run                       | Output | Config | Commit   | Date | Job | Purpose                                                                                                                           | Findings       | Repo | Scratch  | Archive  |
|:------------------------- |:------ |:------ |:-------- |:---- |:--- |:--------------------------------------------------------------------------------------------------------------------------------- |:-------------- |:---- |:-------- |:-------- |
| `a7_gap_cancellation`     | 0000   | none   | —        | —    | —   | Analysis output (login node) of analysis/c5_process_closure.jl's gap_cancellation.csv over 8 existing runs, for A7/E49.           | E49            | yes  | none     | none     |
| `climacore_nameset_repro` | 0000   | none   | —        | —    | —   | ClimaCore-only reproducer for FieldMatrixWithSolver's compile-time scaling (CLIMACORE_ISSUE_DRAFT.md).                            | E44d           | yes  | none     | none     |
| `displacement_check`      | 0000   | none   | —        | —    | —   | Login-node analysis of how mislabelled energy is flushed/mixed over long runs (E60), reading existing runs' NetCDF.               | E60            | yes  | none     | none     |
| `formA_mechanism`         | 0000   | none   | —        | —    | —   | Analysis scripts (formA_mechanism.jl / formA_followup.jl / formA_last.jl) tracing why the audit's form-A gap arises on C7/C9/C10. | E35, E36, E38  | yes  | none     | none     |
| `inc_c9_check`            | 0000   | none   | —        | —    | —   | A reviewer's login-node recomputation/check of C9's first-hour residual (result.txt).                                             | E39            | yes  | none     | none     |
| `newton_lag`              | 0000   | none   | —        | —    | —   | Analysis-script outputs (first_hour_sphere.jl, c8_variants.jl) isolating the Newton-lag mechanism on C9's column/sphere and C8.   | E39, E39b, E43 | yes  | none     | none     |
| `p4_build_stages`         | 0000   | none   | —        | —    | —   | analysis/p4_build_stages.jl timing each build stage of the EDMF column at 0/2/8 tags.                                             | E44c           | yes  | none     | none     |
| `p4_fix_validation`       | 0000   | none   | —        | —    | —   | Validation of #76's split-Jacobian-solver fix on the EDMF column with 8 tags, and with 8 tags + 5 records.                        | E44e           | yes  | none     | none     |
| `p4_inference_profile`    | 0000   | none   | —        | —    | —   | Julia inference-timer profiles (0/2/8 tags) naming the EDMF build's compile-time cause.                                           | E44d, E44e     | yes  | none     | none     |
| `parity_89_d331fe3`       | 0000   | none   | —        | —    | —   | #89's parity check: the fork vs upstream d331fe30 on one node, three configurations.                                              | E51, E52       | yes  | none     | none     |
| `parity_89_r2`            | 0000   | none   | —        | —    | —   | #89's review-round-2 parity paths: restart, vertical-water-borrowing limiter, prescribed-flow column.                             | E57            | yes  | none     | none     |
| `parity_c1b_main`         | 0000   | none   | —        | —    | —   | C1b parity check: main vs C1b (fe69cd06) on the login node, two columns.                                                          | E51            | yes  | none     | none     |
| `repair_trades`           | 0000   | none   | 111c0833 | —    | —   | analysis/repair_trades.jl output: where the repair's large ledgers sit relative to the region-tag edge.                           | E46            | yes  | none     | none     |
| `sedimentation_smoke`     | 0000   | none   | —        | —    | —   | Login-node smoke test: sedimentation moving the source tags on/off, DYCOMS column, 1M, an hour.                                   | E32            | yes  | dir only | dir only |
| `subgrid_build_checks`    | 0000   | none   | —        | —    | —   | Build checks for energy source tags under EDMF/ice/2M/2MP3 on the terrabyte login node.                                           | E40, E41       | yes  | none     | none     |
| `transport_ledger_column` | 0000   | none   | —        | —    | —   | analysis/transport_ledger.jl stepping c6_column_no_repair by hand, splitting the residual's growth by operator.                   | E25            | yes  | none     | none     |
| `transport_ledger_sphere` | 0000   | none   | —        | —    | —   | analysis/transport_ledger.jl on c6_sphere_no_repair, splitting the sphere residual's growth by operator.                          | E31            | yes  | dir only | dir only |

## The v3 outputs on scratch, one row per output

The register leaves the ladder's commit, date and job blank, and gives
`v3_upd_default` several outputs in one row. This table is read from each
output's `provenance.txt` on scratch, on 2026-09-23. An `output_0000` without
a provenance file is not listed. The R2 ladder is FINDINGS E76, written by the
job session in `8726d2cb` and ported to the record branch as `eec7f363`.

| Run                                         | Output     | Commit             | Started                 | Job                | Note                                                 |
|:------------------------------------------- |:---------- |:------------------ |:----------------------- |:------------------ |:---------------------------------------------------- |
| `v3_upd_default_prefix_e010f780_superseded` | 0000       | 3ec098f1           | 2026-09-19 20:02        | 13523325           | shares normalised over all tags; superseded          |
| `v3_upd_copies`                             | 0000       | 3ec098f1           | 2026-09-19 20:02        | 13523326           | the copies of E73                                    |
| `v3_upd_default`                            | 0000       | e010f780           | 2026-09-19 21:30        | 13528772           | the default of E73                                   |
| `v3_upd_default`                            | 0001       | 38278c2d           | 2026-09-19 23:15        | 13536456           | the default D4 day again at the head, for provenance |
| `v3_upd_default`                            | 0002       | 846ef55d           | 2026-09-21 09:18        | 13538433           | rerun                                                |
| `v3_upd_default`                            | 0003       | e71430fb           | 2026-09-23 07:37        | 13760348           | rerun                                                |
| `v3_upd_default`                            | 0004       | dbe7435c           | 2026-09-23 08:34        | 13768361           | superseded by 0005 (E76)                             |
| `v3_upd_default`                            | 0005       | dcf7d086           | 2026-09-23 10:21        | 13782601           | E76, with the partition-only factor                  |
| `v3_upd_default_dt60`                       | 0001, 0002 | dbe7435c, dcf7d086 | 2026-09-23 08:34, 10:21 | 13768362, 13782602 | 0002 is E76's                                        |
| `v3_upd_default_newton2`                    | 0001, 0002 | dbe7435c, dcf7d086 | 2026-09-23 08:34, 10:21 | 13768364, 13782603 | 0002 is E76's                                        |
| `v3_upd_default_upwind`                     | 0001, 0002 | dbe7435c, dcf7d086 | 2026-09-23 08:34, 10:21 | 13768366, 13782604 | 0002 is E76's                                        |
| `v3_upd_default_dt30`                       | 0001, 0002 | dbe7435c, dcf7d086 | 2026-09-23 08:35, 10:21 | 13768368, 13782605 | 0002 is E76's                                        |
| `v3_upd_copies_dt60`                        | 0001       | dbe7435c           | 2026-09-23 08:34        | 13768363           | E76                                                  |
| `v3_upd_copies_newton2`                     | 0001       | dbe7435c           | 2026-09-23 08:34        | 13768365           | E76                                                  |
| `v3_upd_copies_upwind`                      | 0001       | dbe7435c           | 2026-09-23 08:34        | 13768367           | E76                                                  |
| `v3_upd_copies_dt30`                        | 0001       | dbe7435c           | 2026-09-23 08:35        | 13768369           | E76                                                  |

Every one of these exited 0. `g2_v2_sphere_mix_oom_13538434` has its
provenance in `output_0000` on scratch (commit `846ef55d`, job `13538434`,
exit status 1), where the register gives index 0001.

## How runs were submitted, where the old README recorded more

Phase A ran with `runscripts/phase_a.sh`, B1 with `phase_b.sh`, and every
other run with `phase_c.sh`. The old README's run tables add where a run was
submitted from. The worktrees named here were removed on 2026-09-23. Their
commit, patch and untracked files are in the archive under `worktrees/`.

| Runs                                                                                            | Submitted from, or how                                                                                                                                       |
|:----------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `c1c_base_d4_enthalpy`, `g1_base_d4_float32`                                                    | `../ClimaAtmosResiDyn-c1c-base`                                                                                                                              |
| `c1c_opt1_d4_enthalpy`, `c1c_opt1_newton_d4_enthalpy`, `g1_ref_newton_d4`, `g1_ref_newton10_d4` | `../ClimaAtmosResiDyn-c1c-opt1`                                                                                                                              |
| `c1c_opt2_d4_enthalpy`                                                                          | `../ClimaAtmosResiDyn-c1c-opt2`                                                                                                                              |
| `c1c_opt3_d4_enthalpy`                                                                          | `../ClimaAtmosResiDyn-c1c-opt3`                                                                                                                              |
| `inc_d4_enthalpy_increment`                                                                     | `../ClimaAtmosResiDyn-inc`                                                                                                                                   |
| `g1_inc_d4`, `g1_inc_newton10_d4`                                                               | a worktree of the prototype with the ledger                                                                                                                  |
| `g1_inc_newton_d4`, `g1_inc_d4_float32`                                                         | a worktree of the prototype                                                                                                                                  |
| `v3_d4_passive_tracer`                                                                          | `DRIVER=.../analysis/increment/v3_driver.jl`, from a worktree of the prototype; its provenance names `../ClimaAtmosResiDyn-inc-run3`                         |
| `g2_v2_sphere_test`                                                                             | a worktree of the prototype with the deep-atmosphere scaling                                                                                                 |
| `g2_v2_sphere`, `g2_v2_sphere_n2`, `g2_v2_sphere_newton10`                                      | 24 MPI ranks, from a worktree of the prototype. The archived OPERATIONAL_TODO names `../ClimaAtmosResiDyn-inc-run3` at `04d63916` for the first and the last |
| `d4_column_edmf_vd`, `d4_column_edmf_vd_float32`                                                | a worktree of C1b; OPERATIONAL_TODO names `../ClimaAtmosResiDyn-c1b-val` at `9dd30a90`                                                                       |
| `v5_c5_continuous`, `v5_c5_continuous_notags`, then `v5_c5_restarted`, `v5_c5_restarted_notags` | a worktree of C2; OPERATIONAL_TODO names `../ClimaAtmosResiDyn-c2-val` at `e4e9e5b3`. Each restarted run after its continuous twin                           |
| `p4_edmf_two_tags`, `p4_edmf_tags`, `p4_edmf_tags_records`                                      | a worktree at `edd44e1d`                                                                                                                                     |
| `mp1_sphere_4ranks`                                                                             | `--ntasks=4`                                                                                                                                                 |
| `p1_sphere_tags`, `p1_sphere_notags`                                                            | submitted together                                                                                                                                           |
| `g2_v2_sphere_mix`, its OOM attempt, and every `v3_upd_*` run                                   | `../ClimaAtmosResiDyn-upd-run`, by their provenance                                                                                                          |

## Configurations with no output directory

| Config                                                                  | What it is                                                                                                         | Why it has no output                                                                              |
|:----------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------- |
| `b1_notags`                                                             | B1 with no energy tags, the cost baseline                                                                          | not approved: only B1 was (decision 7 of 2026-09-18)                                              |
| `b1a_no_hyperdiff`, `b1b_no_vert_diff`, `b1c_neither`                   | B1 without hyperdiffusion, without vertical diffusion, without either                                              | not approved (decision 7)                                                                         |
| `b2_dry_hs`                                                             | B2, the dry Held-Suarez baroclinic wave, 10 days                                                                   | not approved (decision 7)                                                                         |
| `b3_limiter`                                                            | B3, B1 with `apply_sem_quasimonotone_limiter: true`                                                                | not approved (decision 7)                                                                         |
| `d2_column_2m_ice`                                                      | D1 under 2M                                                                                                        | cannot run while the model disables 2M                                                            |
| `d3_column_p3`                                                          | D1 under 2MP3                                                                                                      | cannot run: the 2M gate, then gaps in the parent's P3 sedimentation                               |
| `p4_edmf_tags_records`                                                  | P4, D4's column with its 8 tags and 5 records                                                                      | no directory of its own. Its build stages after the fix are in `output/p4_fix_validation/` (E44e) |
| `p4_column_0m_tags`, `p4_column_0m_two_tags`, `p4_column_0m_tags_vdiff` | P4 on the login node: the build's growth with the tags on the 0M column, and the fix check with implicit diffusion | login-node checks, with no directory of their own                                                 |

The ladder's configurations (`v3_upd_*_dt30`, `_dt60`, `_newton2`, `_upwind`)
have outputs on scratch and in the archive, but no directory in `output/` yet.

## Other files in `output/`

  - `summary_a.csv` and `summary_c.csv`: the phase summaries that
    `analysis/phase_a.jl` and `phase_c.jl` write.
  - `SCRATCH_INVENTORY.md`: what was on scratch on 2026-09-20. It counts the
    newest output twice, as said above.
  - `a5_sphere_limiter/before_issue_64_fix/`: A5's reading before the fix of
    issue #64, kept beside the rerun. README.md says why an earlier reading
    goes into a subdirectory.
