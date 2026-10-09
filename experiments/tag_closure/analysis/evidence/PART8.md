# Water baseline and cost pilot

The design is [design/PART8_BASELINE.md](../../design/PART8_BASELINE.md),
pre-registered before any job. This record fills the trio's results: runs and
provenance, the OD2 reading, parity and validity, the rows against W58, the
contract rows and the ranked tables, plus the trio's own cost lines. It holds
no number from the six cost jobs, which were still running when it was
written, and no PX12 verdict. The cost pairs, the first-hour origin verdicts
and the review record wait, each in its own section. Prior numbers (W54 to
W62, E87 to E90) are quoted as prior wherever they appear.

Every number below comes from a file under `$SCRATCH/tag_closure/part8/` (called
`$B`), whose log of each step is `$B/logs/<step>.txt`. The record commit is
`9e5155325b6d778ca558b6dd2c6651006add0a80`. The steps are the design's
section 6, steps 2 to 7, run unchanged on 2026-10-09 from this tree.

## Runs and provenance

The trio ran on main `bb2bedf23` (record `9e5155325`, run tree
`ClimaAtmosResiDyn-p8-run`), submitted 2026-10-09 at 13:56 CEST. Each took a
whole node. All three finished COMPLETED with Slurm exit 0:0 and driver exit 0.

| Run                   | Slurm ID | Node          | Wall      | MaxRSS    | Archive    |
|:--------------------- | --------:|:------------- | ---------:|:--------- |:---------- |
| p8_trmm0m_untagged_6h | 14170100 | hpdar07c02s01 | 8 min 45 s  | 7436730K  | not synced |
| p8_trmm0m_default_6h  | 14170101 | hpdar07c04s11 | 14 min 04 s | 7838175K  | not synced |
| p8_trmm0m_copies_6h   | 14170103 | hpdar09c02s05 | 14 min 18 s | 9409121K  | not synced |

The outputs are under `$SCRATCH/tag_closure/output/p8_trmm0m_<run>_6h/output_0000`
and the logs under `$SCRATCH/tag_closure/logs/part8/`. RUNS.md lists the same
three rows as pending. W58's three runs and logs were synced to the archive on
2026-10-09 and checked byte for byte (RUNS.md).

Exit codes of the steps: the OD2 reading, the tables, the ranks, the W58
comparison and the L1 comparison exit 0. The converter and the scorer exit 2 on
both bundles, as the design states. The scorer's qualification is NOT
QUALIFIED on both. Section "Contract rows" names the data failures.

## OD2 window reading

From `$B/od2.json`, `part8_pilot.py od2` on the twin at its own 10 min
cadence (37 samples, 0 to 6 h):

| Reading                         | Established window | Startup window ends |
|:------------------------------- |:------------------ | -------------------:|
| 10 min, the twin's own cadence  | yes, whole 6 h     | 0 s                 |
| 30 min, scorer COMMON.OD2_WINDOWS | none (null)      | not defined         |

The 10 min reading is the OD2 window of this record: a boundary at 0 s, so the
whole 6 h is established flow and the startup window has zero length. The
scorer's own reading at the bundle's 30 min cadence finds no established
window (`startup_end` null, windows startup 0 to 6 h, established null,
sensitivity_1h 1 h to 6 h). The difference is the whole of the established
window: 6 h at 10 min, none at 30 min. This is the same as W58's twin, as
the design's section 5 expects.

The scorer's rows keep the 30 min windows. Its `startup` rows are the 10 min
established reading by name, since both score 0 to 6 h on TRMM 0M. Its
`established` rows are NOT APPLICABLE and block nothing. The `sensitivity_1h`
rows score 1 h to 6 h beside them. No number or verdict changes. The scorer
was not edited. A scorer PR that reads OD2 from the twin's cadence comes
before part 10 scores rain on TRMM.

## Parent parity and validity

From `$B/default_score.json` and `$B/copies_score.json`.

| Row                      | Default bundle                | Copies bundle                |
|:------------------------ |:----------------------------- |:---------------------------- |
| COMMON.PARENT_PARITY     | NOT ASSESSABLE, COMPLETE      | NOT ASSESSABLE, COMPLETE     |
| differing exported fields | none (23 compared)           | none (23 compared)           |
| REFERENCE.PARENT_PARITY  | NOT ASSESSABLE, COMPLETE      | NOT ASSESSABLE, DATA FAILURE |
| COMMON.NEGATIVE_WATER    | PASS, max ratio 0, no latch   | PASS, max ratio 0, no latch  |
| COMMON.PARENT_TEMPERATURE | PASS, min 192.459 K          | PASS, min 192.459 K          |
| top-level change         | 0.29980746438781125 K         | 0.29980746438781125 K        |

The exported fields of both tagged runs are bit for bit the twin's: the
scorer's `differing` list is empty and `exported_outputs_identical` is true.
The row stays NOT ASSESSABLE because exported parity does not certify every
parent state field. The reference parity of the copies bundle is a data
failure because it has no reference (`missing reference variable: rho`).
Step 7 (`$B/logs/s7_compare.txt`) compares default against copies: all 24
fields are bitwise identical. No parent difference exists, so section 10's
first stop does not apply.

## Rows against W58

From `$B/w58.json` (`part8_pilot.py w58 --prefix p8`), from the scorer's
rows and from `$B/logs/s7_compare.txt`. Each value is compared bit for bit.

**H1.** `$B/w58.json` lists 0 differences. All 18 recorded TRMM rows of R4,
R5 and R8 are reproduced, value and verdict, to the last digit. So 0 of 18
rows differ from W58, and no recorded pass became a fail. H1 is not falsified
on these rows.

| W58 rule | Rows | Rerun against W58                                              |
|:-------- | ----:|:-------------------------------------------------------------- |
| R1       | 2    | 24 fields identical in step 7. Scorer parity: none differ      |
| R3       | 9    | Top change 0.29980746438781125 K, as W58. Negative water 0.0   |
| R4       | 4    | Reproduced. Default 3.767955639221502e-15, copies 3.5435e-4    |
| R5       | 3    | Reproduced. Own residual 2.3102e-6, repair 5.0522e-4 per day   |
| R7       | 9    | L1 at 1, 3 and 6 h equal W58 to the printed digits (below)     |
| R8       | 11   | Reproduced. Default led_fix all 0, copies led_fix 6.25e-7, 3.26e-7, 0 |
| C7       | 2    | Not recomputed by any step. Scorer D_p below as the nearest    |

R1 and R3 are read from step 7 and from the scorer's JSON, not from the
`w58` command, which covers R4, R5 and R8. R7 is read from step 7, which
prints three digits. C7 is W58's relative sum of `pr_tag` against `pr`. None
of steps 2 to 7 recomputes it. The scorer's WATER.PRECIP_INSTANTANEOUS
`max_absolute_rate_defect` is a different observable: 2.981555974335137e-19
(default) and 3.36656870214612e-08 (copies), against the design's prior
3.0e-19 and 3.4e-8.

The R7 reading of the default against the copies, step 7:

| Tag  | L1 at 1 h | L1 at 3 h | L1 at 6 h | W58 (1, 3, 6 h)            |
|:---- | ---------:| ---------:| ---------:|:-------------------------- |
| pbl  | 1.03e-04  | 4.55e-03  | 2.06e-02  | 1.03e-04, 4.55e-03, 2.06e-02 |
| free | 5.06e-05  | 2.07e-03  | 1.11e-02  | 5.06e-05, 2.07e-03, 1.11e-02 |
| evap | 7.42e-02  | 3.23e-02  | 4.14e-02  | 7.42e-02, 3.23e-02, 4.14e-02 |

The scorer's 1 h L1 (WATER.ORIGINS.<tag>.3600) equals W58's R7 1 h value to
all digits for pbl (0.00010349564346369095), free (5.0622779815267425e-05)
and evap (0.07420599282628981). Two small differences in observable, not in
number: the scorer's closure `gross_over_raw` is 3.781564603860974e-15 for the
default, W58's R4 is 3.767955639221502e-15 of the water. The first divides
the scorer's gross sum, the second the audit table's last row. The copies
read 3.543478145767747e-4 and 3.543478145767657e-4. These are two readings
of the same run, not a rerun change.

## Contract rows

From the scorer's JSON of both bundles. The scorer exits 2 on both and
qualifies neither (NOT QUALIFIED). Of the 68 rows in each: 21 NOT APPLICABLE.
The rest are below. None is a measured value over a limit.

| Verdict, data status       | Default | Copies |
|:-------------------------- | -------:| ------:|
| PASS, COMPLETE             | 7       | 7      |
| REPORTED ONLY, COMPLETE    | 3       | 3      |
| NOT ASSESSABLE, COMPLETE   | 17      | 13     |
| NOT ASSESSABLE, DATA FAILURE | 9     | 10     |
| FAIL, DATA FAILURE         | 11      | 14     |

PASS rows, both bundles: COMMON.ROSTER, COMMON.NEGATIVE_WATER,
COMMON.OD2_WINDOWS, COMMON.PARENT_TEMPERATURE, WATER.AGGREGATE_REPAIR on
`startup` and on `sensitivity_1h`, COMMON.FINAL_ARTIFACT_CHECK. REPORTED ONLY:
COMMON.PILOT_SCOPE, WATER.CLOSURE, WATER.PRECIP_INSTANTANEOUS.

The rows of the design's section 4, with the scorer's reading:

| 6.1.2 row                 | Scorer row                         | Both bundles                  |
|:------------------------- |:---------------------------------- |:----------------------------- |
| Scope                     | COMMON.ROSTER, COMMON.PILOT_SCOPE  | PASS, REPORTED ONLY           |
| Parent parity             | COMMON.PARENT_PARITY               | NOT ASSESSABLE (none differ)  |
| Parent validity           | NEGATIVE_WATER, PARENT_TEMPERATURE | PASS, PASS                    |
| Parent validity, Newton   | COMMON.NEWTON_TRIAL                | FAIL, DATA FAILURE            |
| Closure                   | WATER.CLOSURE                      | REPORTED ONLY                 |
| Named remainder           | WATER.NAMED_REMAINDER              | FAIL, DATA FAILURE            |
| Copies eligibility        | REFERENCE.ELIGIBILITY.*            | NOT ASSESSABLE (PX12)         |
| Per-tag origins, 1 h      | WATER.ORIGINS.<tag>.3600           | default NOT ASSESSABLE, copies FAIL, DATA FAILURE |
| Per-tag origins, 24 h     | WATER.ORIGINS.<tag>.86400          | NOT APPLICABLE                |
| Process/donor origins     | WATER.PROCESS_WEIGHTED.*           | FAIL, DATA FAILURE            |
| Numerical intervention    | WATER.AGGREGATE_REPAIR.*           | PASS                          |
| Numerical intervention    | WATER.LED_FIX.<tag>.*              | FAIL, DATA FAILURE            |
| Numerical intervention    | WATER.LED_INC.<tag>.*              | NOT ASSESSABLE, DATA FAILURE  |
| Accepted applications     | COMMON.ACCEPTED_APPLICATION_ACTIVITY | NOT ASSESSABLE              |
| 0M precipitation sum      | WATER.PRECIP_INSTANTANEOUS         | REPORTED ONLY                 |
| 0M precipitation, integrated | WATER.PRECIP_INTEGRATED.*       | NOT ASSESSABLE, DATA FAILURE  |
| Convergence, refinement   | COMMON.CONVERGENCE, REFINEMENT     | NOT ASSESSABLE                |
| Aggregation               | COMMON.AGGREGATION                 | NOT ASSESSABLE, DATA FAILURE  |
| Restart                   | COMMON.RESTART_PHYSICAL            | NOT ASSESSABLE                |
| Cost                      | COMMON.COST                        | NOT ASSESSABLE                |
| Held-out                  | COMMON.HELD_OUT                    | NOT ASSESSABLE                |

The converter and scorer exit codes and the named data failures, from
`$B/logs/s3_*.txt` and `$B/logs/s4_*.txt`. All are failures of data, none of
the model.

  - **Default bundle.** Converter exit 2, scorer exit 2. Candidate variables
    missing: `named_remainder`, `newton_error`, `process_amount`,
    `process_share`. Reference variables missing: `copy_residual` (per unit
    updraft mass, the scorer weights by the grid mean) and `process_share`.
    Submission file `LocalPreferences.toml` has no hash. The scorer's
    row failures are COMMON.NEWTON_TRIAL, WATER.NAMED_REMAINDER, the
    WATER.LED_FIX rows of the three tags in both windows, and
    WATER.PROCESS_WEIGHTED in both windows. COMMON.EVIDENCE fails on these.
  - **Copies bundle.** Converter exit 2, scorer exit 2. The same candidate
    variables and the same `LocalPreferences.toml` failure, plus the per-tag
    `led_inc_*` files and `*_applicable` columns missing from the output.
    The missing reference makes REFERENCE.PARENT_PARITY a data failure
    (`rho`) and the three WATER.ORIGINS.<tag>.3600 rows FAIL as data failures.

The per-tag WATER.LED_FIX failures are the cadence failure of the design's
section 6: the ledger fields are written every 30 min against a 150 s step.
The table path reads these from the audit, so the ranked table below has
their values.

## Ranked table of error terms

From `$B/default_rank.csv` and `$B/copies_rank.csv`, built by `part8_pilot.py
rank` from the scorer's JSON and the table rows. A fraction is a reading
against a cited limit, not a verdict. The ranking rule is the design's
section 7. The zeros of the default keep the table order.

**Default.**

| Rank | Term                     | Value        | Comparator                    | Fraction of limit |
| ----:|:------------------------ | ------------:|:----------------------------- | -----------------:|
| 1    | Closure residual         | 3.78e-15     | WATER_GROSS, 2e-3             | 1.89e-12          |
| 2    | Partition repair per day | 0.0          | AGGREGATE_REPAIR_PER_DAY, 5e-3 | 0                |
| 3    | led_fix, pbl             | 0.0          | LED_FIX_MAX, 2e-2             | 0                 |
| 4    | led_fix, free            | 0.0          | LED_FIX_MAX, 2e-2             | 0                 |
| 5    | led_fix, evap            | 0.0          | LED_FIX_MAX, 2e-2             | 0                 |

Listed without a rank, as the design's section 7 fixes:

| Term                        | Value          | Comparator and status                      |
|:--------------------------- | --------------:|:------------------------------------------ |
| Origin at 1 h, pbl (L1)     | 1.03e-04       | the rerun's copies, NOT ASSESSABLE (PX12)  |
| Origin at 1 h, free (L1)    | 5.06e-05       | the rerun's copies, NOT ASSESSABLE (PX12)  |
| Origin at 1 h, evap (abs L1) | 5.05e-03 kg/m2 | small-tag rule, SMALL, NOT ASSESSABLE     |
| Intervention events         | 27413          | NOT ASSESSABLE, no registered producer     |
| Parent Newton error         | 4.1e-3         | W57, D4-W, prior, 4.1 of NEWTON_MAX        |
| 0M precipitation sum        | 2.98e-19       | max abs rate defect, REPORTED ONLY         |

**Copies.**

| Rank | Term                      | Value      | Comparator                       | Fraction of limit |
| ----:|:------------------------- | ----------:|:-------------------------------- | -----------------:|
| 1    | Copies' repair per day    | 5.05e-04   | COMPARATOR_REPAIR_PER_DAY, 2e-3  | 0.2526            |
| 2    | Closure residual          | 3.54e-04   | WATER_GROSS, 2e-3                | 0.1772            |
| 3    | Copies' own residual      | 2.31e-06   | COPIES_RESIDUAL_MAX, 2e-4        | 0.01155           |
| 4    | Partition repair per day  | 8.57e-07   | AGGREGATE_REPAIR_PER_DAY, 5e-3   | 1.7e-04           |
| 5    | led_fix, pbl              | 6.25e-07   | LED_FIX_MAX, 2e-2                | 3.1e-05           |
| 6    | led_fix, free             | 3.26e-07   | LED_FIX_MAX, 2e-2                | 1.6e-05           |
| 7    | led_fix, evap             | 0.0        | LED_FIX_MAX, 2e-2                | 0                 |

Unranked in the copies bundle: intervention events 15317 (copy_repair 13769),
parent Newton error 4.1e-3 (prior, another case) and the 0M precipitation
sum 3.37e-08. PX5's filter share of the copies' corrections is
1.36e-23. The copies bundle has no origin terms, since it has no reference.

**H2.** The rerun's order is the design's prior order in both modes. The first
three terms are the same as W58's. The default's first term is the closure
residual, the copies' first term is the copies' repair. So H2 is not
falsified, and part 9 takes the prior order: default closure, partition
repair, `led_fix:pbl`, and copies' repair, closure, copies' own residual. The
default's ranks 2 to 5 are zeros and carry no information beyond the limit.
The default's first-hour origins wait for PX12 and give part 9 nothing.
Event counts (27413 and 15317) equal the design's prior. D_p equals the prior
to its printed digits.

## Cost

The trio's cost, one sample each on an exclusive node, not the WP9 measure.
Build is the sum of the cache, tendency and integrator phases in the `.err`
log. Step is the progress log's last line (`wall_time_total` over its 137 of
144 steps), with the log's own `wall_time_per_step` beside it. Peak memory is
Slurm's MaxRSS. W58 is the prior (jobs 14119365 to 14119367, shared nodes).

| Run      | Cache   | Tendency | Integrator | Build   | Step total / per step | Peak memory       |
|:-------- | -------:| --------:| ----------:| -------:|:--------------------- |:----------------- |
| untagged | 52.0 s  | 34.4 s   | 13.9 s     | 100.3 s | 6.04 s / 44.1 ms      | 7436730K (7.09 GiB) |
| default  | 73.3 s  | 75.5 s   | 61.1 s     | 209.9 s | 10.93 s / 79.8 ms     | 7838175K (7.48 GiB) |
| copies   | 71.1 s  | 104.8 s  | 47.7 s     | 223.6 s | 11.12 s / 81.2 ms     | 9409121K (8.97 GiB) |

| Run (W58, prior) | Build    | Step total / per step | Log's per-step at step 137 |
|:---------------- | --------:|:--------------------- |:------------------------- |
| untagged         | 158.0 s  | 9.36 s / 68.3 ms      | 65.0 ms                    |
| default          | 265.2 s  | 11.61 s / 84.7 ms     | 80.6 ms                    |
| copies           | 277.1 s  | 11.70 s / 85.4 ms     | 81.2 ms                    |

The rerun's builds are 37% (untagged), 21% (default) and 19% (copies) shorter
than W58's. Its steps are 35% shorter for the untagged twin, 6% for the
default. The tagged-to-untagged step ratio is 1.81 (default) and 1.84
(copies) on this pilot, against 1.24 and 1.25 in W58 (shared nodes). The
twin ran on an unshared node, which may explain part of the faster
twin. These are single samples. Wall times of the jobs: 525, 844 and 858 s.
The header of `runscripts/part8_trio.sh` quotes W58's last line as 9.4 s and
11.6 s. These are `wall_time_total`, not `wall_time_spent` (8.9 s and 11.0 s).

*To be filled from the six cost jobs (`analysis/wp9_cost_table.py` with
`--discard 1`).* For each mode at 8 + 8 with ledgers: step ratio, build,
allocation per step, peak memory, the block spreads and the node spread. E88
and its addendum as prior. H3's answer. No cap is set.

## What waits for PX12

*Filled when PX12's eligibility file is attached.* The first-hour origin
verdicts and the copies' eligibility, re-scored on the same bundles.

## Review record

*Filled by the record PR's review.* Agents, findings and the owner's
decisions.
