# The G3 baselines on the new physics: pre-registered before any run (2026-10-02)

Task 7 of `agent-progress/goals-2026-10-02.md` (outside the repository), and
G3_TODO's "Reruns on the new physics". Written and pushed before any of its
jobs, the check job included. Every pass rule below is an approved OD3 row
(ROADMAP.md, 2026-09-24, with the revisions of 2026-09-25) or a rule already
pre-registered in `design/W25_ISOLATION.md`, sections 4 and 8, or in PX5
(PROVENANCE_PATHWAY.md). Nothing here sets or changes a threshold.

## 1. The question

Main is `b34bbd8b`. Its physics is upstream `a9287b2d`, with ClimaParams 1.2
and CloudMicrophysics 0.43 (STATUS.md, "Update, 2026-10-02: physics
baseline"). Since OD12 to OD14 (DECISIONS.md, 2026-10-02), gated runs use
post-#139 `main`, and every number measured before it is prior evidence only
(G3_PLAN.md, section 10). So the runs behind G3's criteria have no number on
the physics G3 will report.

**What does each G3 criterion and OD3 row that a column run can reach read on
`b34bbd8b`?** In particular, W50's C (DECISIONS.md, 2026-10-02): are the
copies an eligible comparator on D4-W at 60 levels now, and what does PX5's
rule say about why not?

## 2. The baseline set

The smallest set that lets each criterion and OD3 row that a column reaches
be scored once on the new physics, within 12 jobs. Every config is the last
pre-registered config of its run with only its header, its `job_id` and
`radiation_reset_rng_seed: true` changed, except where the table says so.
Neither DYCOMS's nor TRMM_LBA's radiation here calls RRTMGP, so the seed key
changes nothing in these runs. It is set because the runs are compared (RUNS.md,
"The base commit from 2026-10-02").

| #  | run (`configs/<run>.yml`)      | made from                                                                   | mode         | what it gives                                             | old findings it updates           |
|:-- |:------------------------------ |:--------------------------------------------------------------------------- |:------------ |:--------------------------------------------------------- |:--------------------------------- |
| 1  | `g3b_d4w_untagged_z60_c`       | `w50_d4w_untagged_z60_c`                                                    | none         | the twin: R1's reference, OD2's window, R3                | W50's twin                        |
| 2  | `g3b_d4w_copies_z60_c`         | `w50_d4w_copies_z60_c_main`                                                 | copies       | **W50's C**: R5, PX5's share, R4 and R8 of the copies     | W50 (R5), W38, W21's repair, R5   |
| 3  | `g3b_d4w_default_z60_c`        | `w50_d4w_default_z60_c_main`                                                | the follower | R1, R3, R4, R8; R7 against run 2                          | W24, W28 (D4-W), W38, W50         |
| 4  | `g3b_d4w_untagged_z30_c`       | `w50_d4w_untagged_z30_c`                                                    | none         | the pulse's twin and window                               | W50's twin                        |
| 5  | `g3b_d4w_pulse_default_z30_c`  | `w50_d4w_pulse_default_z30_c_main`                                          | the follower | the pulse: R1, R4, R8; R7's first hour                    | W21's pulse, W50's pulse          |
| 6  | `g3b_d4w_pulse_copies_z30_c`   | `w50_d4w_pulse_copies_z30_c_main`                                           | copies       | the pulse's copies: R5 at 30 levels                       | W21, W50                          |
| 7  | P2 on run 2's config           | `w25_probes.jl`, `PROBE=refinement`                                         | copies       | R6 at 60 levels; PX5's growth per halving of `dt`         | W38's R6, W25's comparator ladder |
| 8  | P1, then P2, on run 3's config | `w25_probes.jl`, `fixed_parent` with `TRIALS=1,2,3,4`, then `refinement`    | the follower | R2 (the Newton row) at 1 to 4 iterations, R10; R9         | W41, W38's R2, R9, R10; W25, W24  |
| 9  | `g3b_trmm0m_untagged_6h`       | `w4a_trmm0m_default_6h` without tags                                        | none         | TRMM's twin: R1, R3                                       | new; W26 had none                 |
| 10 | `g3b_trmm0m_default_6h`        | `w4a_trmm0m_default_6h`, follower key of `w5r_trmm0m_increment_samesign_6h` | the follower | criterion 7: `Σ pr_tag` against `pr`; R4, R8; R7 reported | W26, W28 (TRMM)                   |
| 11 | `g3b_trmm0m_copies_6h`         | `w4a_trmm0m_copies_6h`                                                      | copies       | R5 on TRMM 0M; R7's comparator                            | W26, W21's TRMM repair            |

Runs 10 and 11 add `water_tag_ledger_per_tag: true` and the ledgers' output,
which every validation run carries since 2026-09-24. Run 10 adds the follower,
`water_tag_transport: increment`. That is the default mode under EDMF where it
applies (G3_PLAN 4.3), and W28 measured TRMM with it. Run 9 drops the tags and
writes the parent's water every 10 minutes, as the D4-W twins do. No model
field depends on any of these keys.

All D4-W runs are W50's case: DYCOMS RF02, prognostic EDMF with one updraft,
1M stepped implicitly, ARS222, `dt` 120 s, one Newton iteration, centred SGS
reconstruction, one day, Float64, the copies started from the plume by
`analysis/water/d4w_driver.jl`. W21's surface rule is in `main` since #136, so
there is one arm. The 60-level runs are the main case (OD1). The pulse stays at
30 levels, because at 60 its 10 m edge meets 25 m cells (PX13, W50's design).
TRMM 0M is W26's column: 82 levels, `dt` 150 s, 6 h, with the same driver.

**Left out, so their old numbers stay prior evidence.** The plain D4-W pair at
30 levels (W21, W24 and W28 measured 30 levels; the pulse gives R5 at 30
levels, and the 60-level runs are the main case). W25's full-run rungs (`dt`
60 and 30 s, two and four iterations, 120 levels, first order): P1 and P2 test
time step and iterations on one parent state instead. P3, the first-step
probes. TRMM 1M (W33, W35), the GCM-driven column (W22), the long site runs
(W36, W42, W49), the sphere, W32's reconstruction check, W40's leak gate and
every energy row. G3_PLAN section 10 lists each.

## 3. Code, trees and jobs

  - **The model** is a clean detached tree at `main` `b34bbd8b`,
    `../ClimaAtmosResiDyn-g3base-run`, with `.buildkite/LocalPreferences.toml`
    copied in (RUNS.md, "The run-tree rule"). Julia 1.11 with its
    `.buildkite` project and the scratch depot.
  - **The driver, the configs, the probes and the runscripts** come from this
    record branch, `claude/rec-g3base`, at the pushed commit that holds this
    section. `runscripts/g3base_submit.sh` refuses a job unless both trees are
    clean, the run tree is at `b34bbd8b` and the record's commit is on a
    remote branch. It passes the run tree's `.buildkite` as the project and
    stamps the manifest through `submit_g3.sh`. `tag_closure_common.sh` now
    also writes `model_commit` and `model_tree` into `provenance.txt` when
    they are set. The record's own commit stays in `commit`.
  - **Full runs** (1 to 6, 9 to 11) go through `phase_c.sh` with
    `d4w_driver.jl`, writing `$SCRATCH/tag_closure/output/<run>/output_0000`.
  - **Probes** (7, 8) go through `runscripts/g3base_probe.sh`, which runs
    `w25_probes.jl` once per entry of `PROBES` and writes
    `$SCRATCH/tag_closure/output/g3base_probes/<probe>/`. The probes keep
    W38's settings: P1 to 6 h with a ten-iteration reference; P2 from the
    6 h state, five one-hour variants (`dt` 120 s with 1, 2 and 10 iterations,
    60 and 30 s with one).
  - **Slurm:** `-A pn49go-c -p hpda2_compute --cpus-per-task=2 --mem=48G`, not
    exclusive, since nothing here is timed.

**The check job,** before the real jobs. One job runs, on the run tree's model:
the copies at 60 levels to 2 h, and TRMM 0M with the follower to 1 h, each with
the D4-W driver; then P1 (`TRIALS=1,2`, to 20 minutes) and P2 (from 20
minutes, 10-minute variants at `dt` 120 and 60 s) on the default at 60 levels.
Its configs are runs 2, 10 and 3 with only `job_id` (`g3b_check_*`) and `t_end`
changed. They are kept outside both trees, in
`$SCRATCH/claude_work/g3base/check/`, so no real run's output is touched.
`runscripts/g3base_check.sh` runs them. It passes when every step exits 0, the
two driver runs write their closure and audit tables and every configured
diagnostic, and the probe CSVs carry `error_n2_ρq_tot` and
`q_tag_led_upfilter_per_hour`. If it fails, the real jobs wait, and a fix that
changes a config or a script is committed and pushed first.

## 4. What is scored, and how

The scorer is `analysis/water/g3base_score.py`. Its code is `w25_score.py`'s
and `w50_score.py`'s, with one arm, plus PX5 and the TRMM rows. OD2's windows
come from each D4-W rung's twin by the approved rule (`w25_compare.py`'s). The
pulse takes the 30-level twin's window, as in W50. TRMM's rates are read over
the whole 6 h, which is stricter than a window that drops the startup. The
smoke run (`G3B_SMOKE=1`) read W50's main arm, W38's probes and W26's TRMM
pair before this was pushed, and gave back their recorded numbers (R5 4.48e-3
and 3.69e-3, R2 4.1e-3, `Σ pr_tag` 1.8e-3). Its scores mean nothing for
`b34bbd8b`.

| #   | metric                                                                                                                                                                                                                                       | pass rule                                                                                                                                                                                                                                                                                  | OD3 row, or source                           |
|:--- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:-------------------------------------------- |
| R1  | each tagged run against its twin: every NetCDF file the twin writes at the tagged run's period                                                                                                                                               | bit for bit                                                                                                                                                                                                                                                                                | Parent validity: parity                      |
| R2  | P1: the parent's `E` for `ρq_tot` in established flow, at 2 iterations; 1, 3 and 4 reported                                                                                                                                                  | at most 1e-3. Reported always; it gates only verdicts between different parents (2026-09-25)                                                                                                                                                                                               | Parent validity: Newton                      |
| R3  | every run: points at the 150 K floor, the top level's change, the parent's negative water                                                                                                                                                    | none; below 5 K; below 1e-4 of the water                                                                                                                                                                                                                                                   | Parent validity: temperature, negative water |
| R4  | gross residual at the end (24 h; TRMM 6 h), of the water; second half against the first                                                                                                                                                      | 0.2%; no more in the second 12 h on D4-W, read relative to the water as in W50. The absolute amounts are reported beside it. TRMM's halves are reported only, since its rain starts at 3 h                                                                                                 | Closure, water                               |
| R5  | copies: their own residual, the largest output; their repair's retained gross per day                                                                                                                                                        | 0.02%; 0.20% of `∫ρq_tot` a day, divided by the water at the end as W38 and W50. The mean water's reading is reported beside it                                                                                                                                                            | Comparator: its own residual; its repair     |
| R6  | P2, copies: the repair per hour at `dt` 60 against 120 s, 30 against 60 s, 2 and 10 iterations against 1                                                                                                                                     | at most 1.1 times the coarser rung's                                                                                                                                                                                                                                                       | Comparator: refinement                       |
| R7  | default against copies per tag, L1 and L∞ at 1 h and 24 h (`compare_runs.py --judge`); small tags on absolute error                                                                                                                          | 1%, 10%, 25% in the first hour; 2%, 5% at 24 h; `2e-4 ∫ρq_tot`. A verdict only where R5 passes on the case, and R6 too at 60 levels. Where R5 passes on the pulse, R7 waits for R6, as in W50. TRMM: L1 and L∞ at 1, 3 and 6 h, reported only, since no refinement probe runs on TRMM here | Provenance rows                              |
| R8  | the partition repair's retained gross per day; each tag's `led_fix` inventory fraction                                                                                                                                                       | 0.5% of `∫ρq_tot` a day; 2% per tag. `led_inc` reported                                                                                                                                                                                                                                    | Intervention, aggregate; per tag             |
| R9  | P2, default: the partition repair's and `inc_left`'s throughput per hour, finer rung against coarser                                                                                                                                         | at most 0.75; above 0.9 flags a structural cause                                                                                                                                                                                                                                           | Refinement                                   |
| R10 | P1, each tag: `E` at 2 iterations against 1                                                                                                                                                                                                  | at most 0.75; above 0.9 flags                                                                                                                                                                                                                                                              | Refinement                                   |
| PX5 | copies at 60 levels: the filter's share of the copies' two corrections, `led_upfilter / (led_upfilter + led_uprepair)`, gross, in run 2's established window; the filter's per-hour gross in P2 at `dt` 60 against 120 s and 30 against 60 s | a share of at least 0.7 that grows by at least 1.5 times at both halvings is a per-step cause. Otherwise, "no eligible D4-like comparator at production cost". A share below 0.7 decides it without the growth                                                                             | PX5, PT10                                    |
| C7  | TRMM, both modes: `pr_tag_pbl + pr_tag_free` against `pr` at every output with rain; `evap`'s share                                                                                                                                          | reported. 6.1's 1e-8 is for the 1M rain and snow tags, so no 0M threshold exists. W26 measured 1.8e-3                                                                                                                                                                                      | Criterion 7                                  |

Also reported, not judged: PX5's share over the whole day and in each P2
variant, and the filter's gross within 50 m of the mean cloud top (`clw` above
1e-5) against the column's (PT10's "concentrates at cloud top"). And the
copies' repair per hour at 2 and 10 iterations against 1, PT10's "falls with
iterations".

**How each criterion is read.** These are readings on the new physics, not
G3's verdicts.

  - Criterion 3 (parity): R1 on D4-W at 60 and 30 levels and on TRMM 0M. The
    MPI and explicit checks are CI's and are not rerun.
  - Criterion 4 (closure): R4 and R8 on runs 3, 5 and 10; the copies' own
    residual and repair (R5) on runs 2, 6 and 11.
  - Criterion 5 (per-tag accuracy): R7, where the copies are eligible.
  - Criterion 6 (convergence, as robustness): R6, R9 and R10 at 60 levels,
    on one parent state. The grid rungs are not rerun.
  - Criterion 7 (precipitation provenance under 0M): C7. The net-flow audit
    is PX14's and is not run.
  - OD3's parent rows: R1, R2, R3 on every run.
  - W50's C: R5 on run 2 with run 1 as its twin, and PX5.

## 5. Expected, before the runs

R1 and R3 pass. R4 passes in both modes on D4-W, as on the old physics. The
copies' repair on D4-W stays above 0.20% a day, so R5 fails and R7 is not
assessable on D4-W. The new SGS-variance term and the Ri weight act on D4-W's
EDMF, so the repair may move either way. The smoke run read a filter share of
zero in W50's established window (the filter's 36 events, 14% of the two
corrections over the day, all fell in the startup) and no filter in W38's P2
hour. So PX5 is expected to read "no eligible D4-like comparator at
production cost", with the repair, not the filter, dominating. R2 stays above
1e-3 at two iterations (W41: 4.1e-3). On TRMM 0M the closure stays near
rounding under the follower (W28: 4e-15) and `Σ pr_tag` near W26's 1.8e-3.

## 6. Jobs and cost

| job                | runs      | limit | expected, from W50's and W38's jobs on the old code |
|:------------------ |:--------- |:----- |:--------------------------------------------------- |
| check              | section 3 | 3 h   | about 1.5 h (four builds)                           |
| twins              | 1, 4      | 3 h   | 0.5 to 0.6 h each                                   |
| default, 60 levels | 3         | 6 h   | 0.7 h                                               |
| copies, 60 levels  | 2         | 6 h   | 1.2 to 1.3 h                                        |
| the pulse          | 5, 6      | 4 h   | 0.8 h and 1.4 h                                     |
| P2, copies         | 7         | 6 h   | 1.2 h                                               |
| P1 and P2, default | 8         | 8 h   | 1.5 h (W41's P1 took 36 minutes)                    |
| TRMM 0M            | 9 to 11   | 3 h   | 0.5 to 1.3 h each                                   |

Twelve jobs with the check: within the task's 12. About 12 hours of job time in
all, or about 18 hours if the new physics is half again as slow. That is within
the task's 24 hours. The limits are caps, not the estimate.

## 7. Findings

One draft finding per result, from W54 (W52 is WP9's, W53 the `led_fix`
probe's). Each names the old finding it updates and quotes the least
favourable number. They are drafts on `claude/rec-g3base` until an Opus
review, and G3_TODO is not ticked here.

  - W54: W50's C, the copies at 60 levels and PX5 (runs 1, 2, 7).
  - W55: the D4-W day at 60 levels in the default mode (runs 1, 3, and 2 for
    R7).
  - W56: the surface pulse at 30 levels (runs 4 to 6).
  - W57: the probes at 60 levels: the Newton row and the refinement rows
    (runs 7, 8).
  - W58: TRMM 0M, 6 h (runs 9 to 11).

## 8. What this does not do

It sets no threshold and no level, and does not rescore an old finding. It
does not qualify the sphere's grid, or any case but D4-W and TRMM 0M. It does
not run PX12 (W50's B), the WP4b fix, G4's levels or WP9's cost. It compares
the modes with each other, not with an independent reference (PX13). R1 checks
the written diagnostics, not the prognostic state.
