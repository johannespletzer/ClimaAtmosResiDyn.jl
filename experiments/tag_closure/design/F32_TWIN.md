# V-W7: the Float32 twin of D4-W, pre-registered before any run (2026-10-02)

Task T4 of `agent-progress/goals-2026-10-02b.md` (outside the repository).
G3_TODO's V-W7 and criterion 9. Written and pushed before any of its jobs,
the check job included. Nothing here sets or changes a threshold. The factor
of 10 is criterion 9's own (G3_PLAN section 2). Every other budget quoted is
an approved row of G3_PLAN 6.1 or OD3.

## 1. The question

Criterion 9: "A Float32 twin of D4-W meets criteria 3 and 4 within 10× the
Float64 residual. This is a precision-sensitivity check. It decides no cause."
Under option D (DECISIONS.md, 2026-10-02) D4-W keeps criteria 3, 4, 9 and 10.
Criteria 5 and 6 are not judged on D4-W, so no per-tag accuracy is judged
here.

**In Float32, are the tagged D4-W runs bit for bit their untagged twin in both
modes, and is each criterion-4 measure at most 10 times its Float64 value on
the same physics, the same day and the same window?**

## 2. The Float64 reference

The reference is the G3 baseline at 60 levels (design/G3_BASELINE_RERUN.md,
runs 1 to 3; FINDINGS W54 and W55):

| mode    | Float64 run              | job        | finding |
|:------- |:------------------------ |:---------- |:------- |
| none    | `g3b_d4w_untagged_z60_c` | `14119357` | W54     |
| default | `g3b_d4w_default_z60_c`  | `14119359` | W55     |
| copies  | `g3b_d4w_copies_z60_c`   | `14119358` | W54     |

They ran on `main` `b34bbd8b`, with upstream `a9287b2d` physics, ClimaParams
1.2 and CloudMicrophysics 0.43. The model for this task is `main` `d3c5e42f`
(#142, #143, #145 on top). Between the two, `src/` changes only message and
docstring text, plus `auto_sparse_jacobian.jl`, which runs only with
`use_auto_jacobian: true`. D4-W leaves that key at its default, `false`. The
ClimaCore cap of #145 (at most 1.0.1) changes nothing either, because the
reference's `.buildkite` manifest already held ClimaCore 1.0.1, and the
manifest is the same at both commits.

**P0, the confirmation.** One Float64 job reruns `g3b_d4w_default_z60_c` on
`d3c5e42f` as `f32_d4w_default_z60_c_f64`, the config unchanged except for
its header and `job_id`. It passes when every NetCDF file is bit for bit the
reference's and both tables (`water_tag_closure.csv`,
`water_tag_audit.csv`) are byte for byte the same. If it passes, W54's and
W55's numbers are the Float64 reference on `d3c5e42f`. The copies' and the
twin's code paths changed only in text too, so they are not rerun.

*If P0 fails,* the reference becomes Float64 runs on `d3c5e42f`: the twin and
the copies are rerun as `f32_d4w_{untagged,copies}_z60_c_f64`, by an
amendment recorded before those two jobs, and the scorer reads all three
`_f64` runs. That makes 7 jobs with the check, within the task's 8.

## 3. The runs

Each Float32 config is its Float64 config with only the header, the `job_id`
and `FLOAT_TYPE: "Float32"` changed. So the case is W54's and W55's: DYCOMS
RF02, prognostic EDMF with one updraft, 1M stepped implicitly, ARS222, `dt`
120 s, one Newton iteration, 60 levels, centred SGS reconstruction, one day,
the copies started from the plume by `analysis/water/d4w_driver.jl`, per-tag
ledgers on, `radiation_reset_rng_seed: true`.

| # | run (`configs/<run>.yml`)   | precision | mode         | gives                            |
|:- |:--------------------------- |:--------- |:------------ |:-------------------------------- |
| 1 | `f32_d4w_untagged_z60_c`    | Float32   | none         | R1's reference, the window, PREC |
| 2 | `f32_d4w_default_z60_c`     | Float32   | the follower | R1, the default's measures       |
| 3 | `f32_d4w_copies_z60_c`      | Float32   | copies       | R1, the copies' measures         |
| 4 | `f32_d4w_default_z60_c_f64` | Float64   | the follower | P0                               |

**Trees.** The model is a clean detached tree at `d3c5e42f`,
`../ClimaAtmosResiDyn-f32-run`, with `.buildkite/LocalPreferences.toml`
copied from the G3 baseline's run tree. The configs, the driver, the scorer
and the runscripts come from `claude/rec-f32` at the pushed commit that holds
this file. Each job goes through `runscripts/g3base_submit.sh` with
`RUN_TREE=../ClimaAtmosResiDyn-f32-run` and `EXPECT_SHA=d3c5e42f…`. It refuses
a dirty tree, a run tree at another commit and an unpushed record. It stamps
the manifest through `submit_g3.sh`, and `provenance.txt` names both commits.
Output: `$SCRATCH/tag_closure/output/<run>/output_0000`.

**Slurm:** `-A pn49go-c -p hpda2_compute --cpus-per-task=2 --mem=48G`, one
task, not exclusive, since nothing here is timed.

## 4. What is scored, and how

The scorer is `analysis/water/f32_score.py`. Its R4, R5 and R8 code is
`g3base_score.py`'s for the plain case, unchanged, applied to both precisions.
Its smoke mode (`F32_SMOKE=1`) reads the Float64 runs as the Float32 ones. Run
before this was pushed, it gave back W54's and W55's numbers (R4 6.49e-6 and
1.12e-3, R5 7.10e-5 and 3.98e-3, R8 2.10e-3) with every ratio 1. Its scores
mean nothing.

**The window.** OD2's end of startup is read from the Float64 twin by
`g3base_score.py`'s rule: 1 h, as in W54. Both precisions use that window, so
the two values of a measure cover the same hours. The Float32 twin's own
window is reported.

| rule | metric                                                                                                        | pass rule                                                       |
|:---- |:------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------- |
| P0   | the Float64 rerun on `d3c5e42f` against the reference                                                         | bit for bit (NetCDF), byte for byte (tables)                    |
| R1   | each Float32 tagged run against the Float32 twin: every NetCDF file the twin writes, values and times         | bit for bit, in both modes (criterion 3 within Float32)         |
| M    | each judged criterion-4 measure below, in each mode where it exists                                           | Float32 value at most 10 × the Float64 value                    |
| M0   | a judged measure whose Float64 value is exactly zero (`led_fix` of `evap`, `evap_tropo`, `evap_strat` in W55) | no factor applies; judged on its own row's budget (2% per tag)  |
| C9   | criterion 9                                                                                                   | pass when R1 passes in both modes and every M and M0 row passes |

The judged criterion-4 measures are those `g3base_score.py` reads for
criterion 4 on D4-W (design/G3_BASELINE_RERUN.md, section 4, "How each
criterion is read"):

  - **R4, both modes:** the gross residual at 24 h, of the water; and the
    second 12 h's addition, `G(24) − G(12)`. Criterion 4's "the second 12 h
    add no more than the first" compares two parts of one run. Under
    criterion 9 the second half's addition is held to 10 times its Float64
    value. The inequality as written is reported.
  - **R8, both modes, in the established window:** the partition repair's
    retained gross per day; each tag's `led_fix` inventory fraction.
  - **R5, the copies:** their own residual, the largest over the outputs; their
    repair's retained gross per day in the window, divided by the water at
    24 h.

**Reported, not judged:** the whole-day readings of R5 and R8, R5 on the
window's mean water, `led_inc` per tag, the second-half inequality and its
absolute amounts, R3 on the Float32 runs (the 150 K floor, the top level, the
negative water), and PREC: the parent's column water in the Float32 twin
against the Float64 twin, at 24 h and at its largest over the 10-minute
outputs. PREC says how far apart the two atmospheres are, which the 10×
comparison does not.

A non-finite value or a missing hour is a failure.

**Not judged here, and why.**

  - *What the named parts leave* (criterion 4's third clause, 1e-6 at 24 h).
    It needs the 10-Newton twin's split, and the Float64 reference has none on
    the new physics. So it is not assessable in either precision here, and W60
    says so.
  - *The rain and snow tags against `ρq_rai` and `ρq_sno`.* Under EDMF they
    are refused until WP4b's stage 2, so they do not exist on D4-W yet.
  - *Per-tag accuracy* (criteria 5 and 6), by option D.

**How a pass reads.** Criterion 9 compares each measure with its own Float64
value, not with criterion 4's budgets. The copies' repair fails its own budget
in Float64 (3.98e-3 a day against 2e-3, W54). A Float32 value within 10 times
that passes criterion 9 and still fails criterion 4's row. W60 quotes both.

## 5. The check job

Before the real jobs, one job runs, on the run tree's model and with the D4-W
driver, runs 1 to 3 to 2 h, as `f32_check_{untagged,default,copies}`.
Their configs are runs 1 to 3 with only `job_id` and `t_end: "2hours"`
changed. They are kept outside both trees, in
`$SCRATCH/claude_work/f32/check/`, so no real run's output is touched. It is
submitted through `g3base_submit.sh` with `KIND=check`, `CHECK_RUNS` set to
the three configs and `CHECK_PROBE_CONFIG=none`. `runscripts/g3base_check.sh`
now skips the probes for `none`, and is otherwise unchanged. Output:
`$SCRATCH/tag_closure/output/f32_check_*/output_0000`, logs in
`$SCRATCH/tag_closure/output/f32_check/`.

It passes when all three runs exit 0 and the two tagged runs write their
closure and audit tables and every configured diagnostic. The check's
parity at 2 h is read and reported; it does not hold the real jobs. If the
check fails, the real jobs wait, and a fix to a config or a script is
committed and pushed first. If Float32 itself breaks the model (a crash or a
non-finite state that no config can avoid), no model code is changed: W60
bounds the failure and the task stops.

## 6. Expected, before the runs

R1 passes in both modes: the tags write no model field, and Float32 changes no
branch of that logic. P0 passes, since only text changed. The Float32 closure
residuals are larger than the Float64 ones. On D4's energy, E65's twin gave a
ratio of 1.3 to 2.4 over the first eight hours. The water partition closes
to 6.5e-6 in Float64, about 100 times Float32's unit roundoff (6e-8). If
Float32 adds rounding at that level each step, the gross residual could grow
by 720 steps times that, about 4e-5, which is under 10 times 6.5e-6. So the
default's R4 is expected to pass, with little margin. The repair rows (R5,
R8) are not set by rounding, and are expected to stay within a factor of 2
of their Float64 values. This is an expectation, not a rule.

## 7. Jobs and cost

| job             | runs      | limit | expected, from W54's and W55's jobs |
|:--------------- |:--------- |:----- |:----------------------------------- |
| check           | section 5 | 3 h   | about 1 h (three builds)            |
| Float32 twin    | 1         | 3 h   | 0.5 to 0.6 h                        |
| Float32 default | 2         | 6 h   | 0.7 h                               |
| Float32 copies  | 3         | 6 h   | 1.2 to 1.3 h                        |
| Float64 default | 4 (P0)    | 6 h   | 0.7 h                               |

Five jobs with the check, within the task's 8 (7 if P0 fails). About 4.5 hours
of job time. The limits are caps, not the estimate.

## 8. What this does not do

It decides no cause: that needs tagged and untagged pairs at each precision,
and refinement (criterion 9's own text). The two precisions give two
atmospheres, so a measure's ratio mixes rounding with a different trajectory
(PREC reports how different). One case, one grid, one day, one Newton
iteration. It compares the tags with their own residuals, not with an
independent reference (PX13). R1 checks the written diagnostics, not the
prognostic state. Finding: W60.
