# Water baseline and cost pilot

The design is [design/PART8_BASELINE.md](../../design/PART8_BASELINE.md),
pre-registered before any job. This record holds the results of all nine
jobs. They are the runs and their provenance, the OD2 reading, parity and
validity, the rows against W58, the contract rows, the ranked tables and the
cost. The section "Verdict" answers H1, H2 and H3 and applies the stop rules.
No PX12 verdict is here. It waits in its own section. Prior numbers (W54 to
W62, E87 to E90) are quoted as prior wherever they appear.

The numbers of steps 2 to 7 come from files under `$SCRATCH/tag_closure/part8/`
(called `$B`), whose log of each step is `$B/logs/<step>.txt`. The record
commit is `9e5155325b6d778ca558b6dd2c6651006add0a80`. The steps are the
design's section 6, steps 2 to 7, run unchanged on 2026-10-09 from this tree.
The section "Cost" names its own sources.

## Runs and provenance

The trio ran on main `bb2bedf23` (record `9e5155325`, run tree
`ClimaAtmosResiDyn-p8-run`), submitted 2026-10-09 at 13:56 CEST. Each took a
whole node. All three finished COMPLETED with Slurm exit 0:0 and driver exit 0.

| Run                   | Slurm ID | Node          | Wall        | MaxRSS   | Archive    |
|:--------------------- | --------:|:------------- | -----------:|:-------- |:---------- |
| p8_trmm0m_untagged_6h | 14170100 | hpdar07c02s01 | 8 min 45 s  | 7436730K | 2026-10-09 |
| p8_trmm0m_default_6h  | 14170101 | hpdar07c04s11 | 14 min 04 s | 7838175K | 2026-10-09 |
| p8_trmm0m_copies_6h   | 14170103 | hpdar09c02s05 | 14 min 18 s | 9409121K | 2026-10-09 |

The outputs are under `$SCRATCH/tag_closure/output/p8_trmm0m_<run>_6h/output_0000`
and the logs under `$SCRATCH/tag_closure/logs/part8/`. RUNS.md lists the three
runs and the cost set. The nine runs' outputs and logs, the manifests and the
results under `$B` were synced to the archive on 2026-10-09 and checked byte
for byte (the archive's README). W58's three runs and logs were synced the
same day, before the first job.

The copies' log has 12 warnings that the water tag closure residual exceeds
the warning level of 1e-10, one at each 30 min output. They run from 2.85e-5
at 30 min to 3.54e-4 at 6 h, the R4 value below. W58's copies log has the
same 12. The default and the twin have none. A warning level is not an
acceptance threshold.

Exit codes of the steps: the OD2 reading, the tables, the ranks, the W58
comparison and the L1 comparison exit 0. The converter and the scorer exit 2 on
both bundles, as the design states. The scorer's qualification is NOT
QUALIFIED on both. Section "Contract rows" names the data failures.

## OD2 window reading

From `$B/od2.json`, `part8_pilot.py od2` on the twin at its own 10 min
cadence (37 samples, 0 to 6 h):

| Reading                           | Established window | Startup window ends |
|:--------------------------------- |:------------------ | -------------------:|
| 10 min, the twin's own cadence    | yes, whole 6 h     | 0 s                 |
| 30 min, scorer COMMON.OD2_WINDOWS | none (null)        | not defined         |

The 10 min reading is the OD2 window of this record. Its boundary is at 0 s,
so the whole 6 h is established flow. The startup window has zero length. The
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

| Row                       | Default bundle              | Copies bundle                |
|:------------------------- |:--------------------------- |:---------------------------- |
| COMMON.PARENT_PARITY      | NOT ASSESSABLE, COMPLETE    | NOT ASSESSABLE, COMPLETE     |
| differing exported fields | none (23 compared)          | none (23 compared)           |
| REFERENCE.PARENT_PARITY   | NOT ASSESSABLE, COMPLETE    | NOT ASSESSABLE, DATA FAILURE |
| COMMON.NEGATIVE_WATER     | PASS, max ratio 0, no latch | PASS, max ratio 0, no latch  |
| COMMON.PARENT_TEMPERATURE | PASS, min 192.459 K         | PASS, min 192.459 K          |
| top-level change          | 0.29980746438781125 K       | 0.29980746438781125 K        |

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
rows and from `$B/logs/s7_compare.txt`. Not every value is compared bit for
bit. The `w58` command compares the 18 rows of R4, R5 and R8 to the last
digit. R3's top-level change is compared to all digits. R7 is compared at the
three printed digits at 3 h and 6 h, and to all digits at 1 h. C7 is not
recomputed. The table below says what applies to each rule.

**H1.** `$B/w58.json` lists 0 differences. All 18 recorded TRMM rows of R4,
R5 and R8 are reproduced, value and verdict, to the last digit. So 0 of 18
rows differ from W58, and no recorded pass became a fail. H1 is not falsified
on these rows. W58 reports R7 and C7 without a verdict, so neither can flip a
pass. The section "Verdict" states H1.

| W58 rule | Rows | Rerun against W58                                                     |
|:-------- | ----:|:--------------------------------------------------------------------- |
| R1       | 2    | Scorer: 23 fields against the twin, none differ. Review: 24 of 24     |
| R3       | 9    | Top change 0.29980746438781125 K, W58's to all digits. Neg. water 0.0 |
| R4       | 4    | Reproduced. Default 3.767955639221502e-15, copies 3.5435e-4           |
| R5       | 3    | Reproduced. Own residual 2.3102e-6, repair 5.0522e-4 per day          |
| R7       | 9    | L1 at 1, 3 and 6 h equal W58 to the printed digits (below)            |
| R8       | 11   | Reproduced. Default led_fix all 0, copies led_fix 6.25e-7, 3.26e-7, 0 |
| C7       | 2    | Not recomputed by any step. Scorer D_p below as the nearest           |

R1 and R3 are read from the scorer's JSON, not from the `w58` command, which
covers R4, R5 and R8. The scorer compares 23 fields of each tagged run with
the twin. Step 7 compares default with copies, not with the twin. W58's R1
compared the 24 fields the twin writes at 30 min. The record PR's review
compared those 24 fields of each tagged run with the twin, bit for bit, and
found all equal. R7 is read from step 7, which
prints three digits. C7 is W58's relative sum of `pr_tag` against `pr`. None
of steps 2 to 7 recomputes it. The scorer's WATER.PRECIP_INSTANTANEOUS
`max_absolute_rate_defect` is a different observable: 2.981555974335137e-19
(default) and 3.36656870214612e-08 (copies), against the design's prior
3.0e-19 and 3.4e-8.

The R7 reading of the default against the copies, step 7:

| Tag  | L1 at 1 h | L1 at 3 h | L1 at 6 h | W58 (1, 3, 6 h)              |
|:---- | ---------:| ---------:| ---------:|:---------------------------- |
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

| Verdict, data status         | Default | Copies |
|:---------------------------- | -------:| ------:|
| PASS, COMPLETE               | 7       | 7      |
| REPORTED ONLY, COMPLETE      | 3       | 3      |
| NOT ASSESSABLE, COMPLETE     | 17      | 13     |
| NOT ASSESSABLE, DATA FAILURE | 9       | 10     |
| FAIL, DATA FAILURE           | 11      | 14     |

PASS rows, both bundles: COMMON.ROSTER, COMMON.NEGATIVE_WATER,
COMMON.OD2_WINDOWS, COMMON.PARENT_TEMPERATURE, WATER.AGGREGATE_REPAIR on
`startup` and on `sensitivity_1h`, COMMON.FINAL_ARTIFACT_CHECK. REPORTED ONLY:
COMMON.PILOT_SCOPE, WATER.CLOSURE, WATER.PRECIP_INSTANTANEOUS.

The rows of the design's section 4, with the scorer's reading:

| 6.1.2 row                    | Scorer row                           | Both bundles                                      |
|:---------------------------- |:------------------------------------ |:------------------------------------------------- |
| Scope                        | COMMON.ROSTER, COMMON.PILOT_SCOPE    | PASS, REPORTED ONLY                               |
| Parent parity                | COMMON.PARENT_PARITY                 | NOT ASSESSABLE (none differ)                      |
| Parent validity              | NEGATIVE_WATER, PARENT_TEMPERATURE   | PASS, PASS                                        |
| Parent validity, Newton      | COMMON.NEWTON_TRIAL                  | FAIL, DATA FAILURE                                |
| Closure                      | WATER.CLOSURE                        | REPORTED ONLY                                     |
| Named remainder              | WATER.NAMED_REMAINDER                | FAIL, DATA FAILURE                                |
| Copies eligibility           | REFERENCE.ELIGIBILITY.*              | NOT ASSESSABLE (PX12)                             |
| Per-tag origins, 1 h         | WATER.ORIGINS.<tag>.3600             | default NOT ASSESSABLE, copies FAIL, DATA FAILURE |
| Per-tag origins, 24 h        | WATER.ORIGINS.<tag>.86400            | NOT APPLICABLE                                    |
| Process/donor origins        | WATER.PROCESS_WEIGHTED.*             | FAIL, DATA FAILURE                                |
| Numerical intervention       | WATER.AGGREGATE_REPAIR.*             | PASS                                              |
| Numerical intervention       | WATER.LED_FIX.<tag>.*                | FAIL, DATA FAILURE                                |
| Numerical intervention       | WATER.LED_INC.<tag>.*                | NOT ASSESSABLE, DATA FAILURE                      |
| Accepted applications        | COMMON.ACCEPTED_APPLICATION_ACTIVITY | NOT ASSESSABLE                                    |
| 0M precipitation sum         | WATER.PRECIP_INSTANTANEOUS           | REPORTED ONLY                                     |
| 0M precipitation, integrated | WATER.PRECIP_INTEGRATED.*            | NOT ASSESSABLE, DATA FAILURE                      |
| Convergence, refinement      | COMMON.CONVERGENCE, REFINEMENT       | NOT ASSESSABLE                                    |
| Aggregation                  | COMMON.AGGREGATION                   | NOT ASSESSABLE, DATA FAILURE                      |
| Restart                      | COMMON.RESTART_PHYSICAL              | NOT ASSESSABLE                                    |
| Cost                         | COMMON.COST                          | NOT ASSESSABLE                                    |
| Held-out                     | COMMON.HELD_OUT                      | NOT ASSESSABLE                                    |

Section 4 asks for some readings that the table above does not show. Each is
read from the scorer's JSON or the tables JSON, or stated as not produced.

  - **Closure over T+.** `gross_over_target` equals `gross_over_raw` in both
    bundles, 3.781564603860974e-15 (default) and 3.543478145767747e-4
    (copies). The positive target equals the raw water, 58.57910291455101.
  - **`led_inc` fractions.** The default's whole-run `led_inc` inventory
    fractions are 0.0221 (pbl), 0.0135 (free) and 0.0116 (evap). They have no
    limit and are reported. The copies' output has no `led_inc` fields, so the
    copies have no such reading.
  - **0M precipitation.** The no-rain absolute defect is 0.0 in both bundles.
    The tools give the maximum defect over the outputs, not D_p at each
    output. None of steps 2 to 7 produces the source shares.
  - **Copies' refinement and OD12 floors.** No tool produces them here. The
    scorer reads both from PX12's eligibility file, so they wait for PX12.
  - **Rain and snow, precipitation origins.** WATER.RAIN_SNOW_CLOSURE,
    WATER.PRECIP_TAG_SUM and WATER.PRECIP_NET_FLOW_AUDIT are NOT APPLICABLE in
    both bundles (0M).
  - **Reproducibility.** COMMON.EVIDENCE is FAIL, DATA FAILURE in both
    bundles. It lists the row data failures below and the missing hash of
    `LocalPreferences.toml`. COMMON.RESTART_PHYSICAL is NOT ASSESSABLE, since
    the pilot has no restart.

The converter and scorer exit codes and the named data failures, from
`$B/logs/s3_*.txt` and `$B/logs/s4_*.txt`. Each is a missing field, column or
hash. None is a measured value over a limit.

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
their values. The tables JSON gives these rows the contract text "scored per
OD2 window by the scorer, at accepted-step cadence". That is the contract's
intended row. Under the owner's decision of 2026-10-09 they are reported, not
scored.

## Ranked table of error terms

From `$B/default_rank.csv` and `$B/copies_rank.csv`, built by `part8_pilot.py rank` from the scorer's JSON and the table rows. A fraction is a reading
against a cited limit, not a verdict. The ranking rule is the design's
section 7. The zeros of the default keep the table order.

**Default.**

| Rank | Term                     | Value    | Comparator                     | Fraction of limit |
| ----:|:------------------------ | --------:|:------------------------------ | -----------------:|
| 1    | Closure residual         | 3.78e-15 | WATER_GROSS, 2e-3              | 1.89e-12          |
| 2    | Partition repair per day | 0.0      | AGGREGATE_REPAIR_PER_DAY, 5e-3 | 0                 |
| 3    | led_fix, pbl             | 0.0      | LED_FIX_MAX, 2e-2              | 0                 |
| 4    | led_fix, free            | 0.0      | LED_FIX_MAX, 2e-2              | 0                 |
| 5    | led_fix, evap            | 0.0      | LED_FIX_MAX, 2e-2              | 0                 |

Listed without a rank, as the design's section 7 fixes:

| Term                         | Value          | Comparator and status                     |
|:---------------------------- | --------------:|:----------------------------------------- |
| Origin at 1 h, pbl (L1)      | 1.03e-04       | the rerun's copies, NOT ASSESSABLE (PX12) |
| Origin at 1 h, free (L1)     | 5.06e-05       | the rerun's copies, NOT ASSESSABLE (PX12) |
| Origin at 1 h, evap (abs L1) | 5.05e-03 kg/m2 | small-tag rule, SMALL, NOT ASSESSABLE     |
| Intervention events          | 27413          | NOT ASSESSABLE, no registered producer    |
| Parent Newton error          | 4.1e-3         | W57, D4-W, prior, 4.1 of NEWTON_MAX       |
| 0M precipitation sum         | 2.98e-19       | max abs rate defect, REPORTED ONLY        |

**Copies.**

| Rank | Term                     | Value    | Comparator                      | Fraction of limit |
| ----:|:------------------------ | --------:|:------------------------------- | -----------------:|
| 1    | Copies' repair per day   | 5.05e-04 | COMPARATOR_REPAIR_PER_DAY, 2e-3 | 0.2526            |
| 2    | Closure residual         | 3.54e-04 | WATER_GROSS, 2e-3               | 0.1772            |
| 3    | Copies' own residual     | 2.31e-06 | COPIES_RESIDUAL_MAX, 2e-4       | 0.01155           |
| 4    | Partition repair per day | 8.57e-07 | AGGREGATE_REPAIR_PER_DAY, 5e-3  | 1.7e-04           |
| 5    | led_fix, pbl             | 6.25e-07 | LED_FIX_MAX, 2e-2               | 3.1e-05           |
| 6    | led_fix, free            | 3.26e-07 | LED_FIX_MAX, 2e-2               | 1.6e-05           |
| 7    | led_fix, evap            | 0.0      | LED_FIX_MAX, 2e-2               | 0                 |

Unranked in the copies bundle: intervention events 15317 (copy_repair 13769),
parent Newton error 4.1e-3 (prior, another case) and the 0M precipitation
sum 3.37e-08. PX5's filter share of the copies' corrections is
1.36e-23. The copies bundle has no origin terms, since it has no reference.

**H2.** The rerun's order is the design's prior order in both modes. The first
three terms are the same as W58's. The default's first term is the closure
residual, the copies' first term is the copies' repair. So H2 is not
falsified, and part 9 takes the prior order: default closure, partition
repair, `led_fix:pbl`, and copies' repair, closure, copies' own residual. The
default's ranks 2 to 5 are zeros. Their order is the tie rule's table order,
not a measured order.
The default's first-hour origins wait for PX12 and give part 9 nothing.
Event counts (27413 and 15317) equal the design's prior. D_p equals the prior
to its printed digits.

## Cost

The trio's cost, one sample each on an exclusive node, not the WP9 measure.
Build is the sum of the cache, tendency and integrator phases in the `.err`
log. Step is the progress log's last line (`wall_time_total` over its 137 of
144 steps), with the log's own `wall_time_per_step` beside it. The log's value
is `wall_time_spent` over the steps. Peak memory is Slurm's MaxRSS. W58 is the
prior (jobs 14119365 to 14119367, shared nodes).

| Run      | Cache  | Tendency | Integrator | Build   | Step total / per step | Log's per-step at step 137 | Peak memory         |
|:-------- | ------:| --------:| ----------:| -------:|:--------------------- |:-------------------------- |:------------------- |
| untagged | 52.0 s | 34.4 s   | 13.9 s     | 100.3 s | 6.04 s / 44.1 ms      | 41.9 ms                    | 7436730K (7.09 GiB) |
| default  | 73.3 s | 75.5 s   | 61.1 s     | 209.9 s | 10.93 s / 79.8 ms     | 75.9 ms                    | 7838175K (7.48 GiB) |
| copies   | 71.1 s | 104.8 s  | 47.7 s     | 223.6 s | 11.12 s / 81.2 ms     | 77.2 ms                    | 9409121K (8.97 GiB) |

| Run (W58, prior) | Build   | Step total / per step | Log's per-step at step 137 |
|:---------------- | -------:|:--------------------- |:-------------------------- |
| untagged         | 158.0 s | 9.36 s / 68.3 ms      | 65.0 ms                    |
| default          | 265.2 s | 11.61 s / 84.7 ms     | 80.6 ms                    |
| copies           | 277.1 s | 11.70 s / 85.4 ms     | 81.2 ms                    |

The rerun's builds are 37% (untagged), 21% (default) and 19% (copies) shorter
than W58's. Its steps are 35% shorter for the untagged twin, 6% for the
default. The tagged-to-untagged step ratio is 1.81 (default) and 1.84
(copies) on this pilot, against 1.24 and 1.25 in W58. All three rerun jobs
had a whole node, and W58's jobs shared nodes. These are single samples, and
this record reads no cause from them. Wall times of the jobs: 525, 844 and
858 s.
The header of `runscripts/part8_trio.sh` quotes W58's last line as 9.4 s and
11.6 s. These are `wall_time_total`, not `wall_time_spent` (8.9 s and 11.0 s).

The six cost jobs (14170104 to 14170109) completed on 2026-10-09 with exit 0
at every point. They ran on D4 with both families at the intended count, 0 and
8 + 8 tags with ledgers, one node per job, and no two replicates shared a
node. The table is
`analysis/wp9_cost_table.py $SCRATCH/tag_closure/output/wp9_cost_p8 --discard 1`,
so blocks 2 to 6 are read. Its output is in `$SCRATCH/tag_closure/part8/cost/`
(`wp9_cost_table.txt`). Every point's block spread is at most 2.4% and every
ratio's spread at most 2.5%, under the 10% bound. So all six jobs are quoted.
Nothing was rerun.

| Job          | Mode    | Node          | Elapsed | Point 0 step, ms | 8 + 8 step, ms | Ratio (min) | Ratio (median) | Quoted | Point 0 spread | 8 + 8 spread | Ratio spread |
|:------------ |:------- |:------------- | -------:| ----------------:| --------------:| -----------:| --------------:| ------:| --------------:| ------------:| ------------:|
| p8_default_a | default | hpdar09c02s07 | 0:56:25 | 4.508            | 41.053         | 9.106       | 9.076          | 9.106  | 0.7%           | 0.5%         | 0.4%         |
| p8_default_b | default | hpdar10c03s02 | 0:42:12 | 2.953            | 27.697         | 9.379       | 9.343          | 9.379  | 1.0%           | 0.6%         | 1.0%         |
| p8_default_c | default | hpdar10c03s04 | 0:56:31 | 4.531            | 40.775         | 8.998       | 8.977          | 8.998  | 2.3%           | 0.3%         | 2.5%         |
| p8_copies_a  | copies  | hpdar10c03s06 | 3:33:25 | 3.169            | 27.541         | 8.691       | 8.737          | 8.737  | 0.9%           | 2.4%         | 2.3%         |
| p8_copies_b  | copies  | hpdar07c04s07 | 5:10:30 | 4.463            | 39.375         | 8.823       | 8.852          | 8.852  | 1.2%           | 2.2%         | 1.9%         |
| p8_copies_c  | copies  | hpdar07c04s08 | 3:37:06 | 2.947            | 26.368         | 8.948       | 8.986          | 8.986  | 0.8%           | 2.2%         | 2.4%         |

The ratio is the 8 + 8 step over the same job's point 0, the minimum over
blocks 2 to 6 beside the median over the same blocks. The less favourable of
the two is quoted, which is the larger one. Spreads are (max - min) / min over
blocks 2 to 6.

| Job          | Build, s | Build / point 0 build | Build, h | First step, s | Allocation per step, B | Script's peak, GB | Slurm MaxRSS |
|:------------ | --------:| ---------------------:| --------:| -------------:| ----------------------:| -----------------:|:------------ |
| p8_default_a | 1361.5   | 2.135                 | 0.38     | 817.4         | 6038456                | 16.36             | 16999679K    |
| p8_default_b | 989.9    | 2.201                 | 0.27     | 629.6         | 6038456                | 13.22             | 13436392K    |
| p8_default_c | 1361.9   | 2.137                 | 0.38     | 836.2         | 6038456                | 16.26             | 16898520K    |
| p8_copies_a  | 10878.4  | 23.589                | 3.02     | 927.9         | 7180344                | 25.00             | 26052594K    |
| p8_copies_b  | 16140.9  | 25.300                | 4.48     | 1198.1        | 7180344                | 24.98             | 26029573K    |
| p8_copies_c  | 11114.3  | 24.231                | 3.09     | 910.7         | 7180344                | 24.94             | 25741104K    |

Point 0 allocates 560216 B per step in every job. The script's peak is the
process's maximum resident size after the 8 + 8 point, in the script's GB. The
Slurm MaxRSS is the batch step's, over the whole job.

| Mode    | Step ratio, quoted | Node spread of the ratio | Build, s           | Node spread of the build | Build ratio    | Step, ms (node spread) | Peak, script's GB |
|:------- |:------------------ |:------------------------ |:------------------ |:------------------------ |:-------------- |:---------------------- |:----------------- |
| default | 8.998 to 9.379     | 4.2%                     | 989.9 to 1361.9    | 37.6%                    | 2.135 to 2.201 | 27.70 to 41.05 (48.2%) | 13.22 to 16.36    |
| copies  | 8.737 to 8.986     | 2.9%                     | 10878.4 to 16140.9 | 48.4%                    | 23.59 to 25.30 | 26.37 to 39.38 (49.3%) | 24.94 to 25.00    |

The six jobs ran on six different nodes. The step ratio is steady across the
nodes. The absolute times are not. Point 0's step falls in two groups. One
is 2.95 to 3.17 ms (default b, copies a and c), the other 4.46 to 4.53 ms
(default a and c, copies b). The 8 + 8 step follows its job's group. The
ratio cancels this.
The build ratio spreads 3.1% (default) and 7.3% (copies), against 37.6% and
48.4% for the build seconds. The job p8_copies_b took 17,518 s for its 8 + 8
point against 11,962 and 12,177 s for its siblings. Its build (16,140.9 s),
first step (1,198.1 s) and block step (39.375 ms) are each 1.3 to 1.5 times
its siblings'. Its point 0 was slower too (build 638.0 s against 461.2 s and
458.7 s). The arm CSVs record a one-minute load average of 1.00 to 1.27 at
the twelve points. They show no more.

Prior. E88's default 8 + 8 step with ledgers was 9.098x of its point 0 and its
build 2.14x. The addendum built the copies at 8 + 8 without ledgers in
15,377 s (4 h 16 min). E88's 8 + 8 point peaked at 14.5 GB and the
addendum's copies at 21.4 GB, both without ledgers. The readings here are
8.998x to 9.379x and a build of 2.135x to 2.201x for the default. The copies
built in 10,878 s to 16,141 s with ledgers. The peaks are 13.2 to 16.4 GB
(default) and 24.9 to 25.0 GB (copies). OD3's cost row is 2x at the intended count, and its
copies row is a build within 4 h. The default's step ratio is 4.5 to 4.7 times
OD3's 2x. The copies' step ratio is 8.7x to 9.0x. The copies' build was within
4 h on two of the three nodes (3.02 h and 3.09 h) and 4.48 h on the third.

**H3's answer.** The default half says an 8 + 8 step with ledgers stays above
OD3's 2x. It holds on all three nodes (8.998x to 9.379x), as E88's 9.098x did.
So it is not falsified. The copies half says the copies do not build within
4 h. It holds on p8_copies_b (4.48 h). It does not hold on p8_copies_a and
p8_copies_c (3.02 h and 3.09 h). So the reading is split across the nodes.
The design fixes no rule for a split build. Two readings were open. Read as
written, a build within 4 h falsifies the copies half, and two did. Read with
section 8's "less favourable quoted", which the design states for the blocks
of one job, the slowest build of 4.48 h is quoted and the half holds. The
owner decided on 2026-10-09, after PRs #166 and #167, that the rule extends
to the nodes of a cost set. The copies' build is quoted as 4.48 h
(p8_copies_b). The builds of 3.02 h and 3.09 h (p8_copies_a and p8_copies_c)
are recorded as the favourable case. The copies half is not falsified.
Neither half is a criterion 10 verdict.
Criterion 10 is scored in part 10.

No cost cap is set from this cost set. The owner deferred WA-COST's cap on
2026-10-09, after PRs #166 and #167, until the walk fix is measured (section
"Verdict").

## Verdict

In the terms of the design's sections 1 and 10. This record sets no cap,
threshold, tolerance or default.

  - **H1, the prior stands: not falsified.** No recorded pass of W58 became a
    fail. The 18 rows of R4, R5 and R8 equal W58's to the last digit. R1 and
    R3 pass again. No parent field differs, and the top-level change equals
    W58's to all digits. R7 equals W58 at the printed digits, and to all
    digits at 1 h. C7 was not recomputed. W58 reports R7 and C7 without a
    verdict, so neither could flip a pass.
  - **H2, the order of the error terms: not falsified.** The rerun ranks the
    prior's first term first in each mode. In the default it is the closure
    residual (1.89e-12 of WATER_GROSS). In the copies it is the copies' repair
    (0.2526 of COMPARATOR_REPAIR_PER_DAY). The first three terms of each mode
    are the prior's. Part 9 takes the prior order.
  - **H3, the cost: not falsified.** The default half holds on all three
    nodes (8.998x to 9.379x against OD3's 2x, E88 9.098x). It is not
    falsified. The copies half is not falsified either. Two builds fall
    within 4 h (3.02 h and 3.09 h), and one does not (4.48 h). The owner
    decided on 2026-10-09 that section 8's rule "less favourable quoted"
    extends from the blocks of one job to the nodes of a cost set. So the
    copies' build is quoted as 4.48 h, and the other two are the favourable
    case. Neither half is a criterion 10 verdict.

The stop rules of section 10, one by one:

 1. **A parent difference.** None. The scorer finds no differing exported
    field in either tagged run (23 compared against the twin). Step 7 finds
    default and copies bitwise identical in 24 fields. The rule does not
    apply.
 2. **A flipped verdict.** None (H1). Nothing goes to the top of part 9's
    queue under this rule.
 3. **Another first term.** None (H2). Part 9 follows the prior order, which
    the rerun confirms.
 4. **A failed job.** None. All nine jobs finished COMPLETED with exit 0.
    Nothing was rerun.

Section 12's choices 4, 5 and 8 are decided (2026-10-09). So is choice 6's
listing of NOT ASSESSABLE terms without a rank or a fraction. Choices 1, 2, 3,
7 and 9 are decided as proposed (2026-10-09, after PRs #166 and #167). So are
choice 6's ranking rule and fix candidates. This record decides none of them.

The owner decided the items that waited, on 2026-10-09 after PRs #166 and
#167:

  - The copies half of H3 is not falsified. The slowest build, 4.48 h, is
    quoted. The builds of 3.02 h and 3.09 h are the favourable case.
  - WA-COST's cap is deferred until the walk fix is measured. No cap is set
    from this cost set. The entry in force stands: no cap for the pilot or
    for water alone, and caps gate level 4. The cap is set from the post-fix
    measurement that part 9's walk fix item pre-registers under WP9's spread
    rule.
  - The proposed choices of section 12 listed above are decided as proposed.

Nothing waits for the owner in part 8.

The follow-ups the owner decided on 2026-10-09 stay as decided. A scorer PR
reads OD2 from the twin's cadence before part 10 scores rain on TRMM. A
converter and scorer follow-up maps the per-tag `led_fix` columns before part
10. The registered producer is part 9's queue item.

The difference the design's section 2 lists is closed. Commit `dd2df01e8`
(2026-10-09, before the runs) moved the part 8 brief's walk fix measurement
to part 9's queue, as the delivery plan's section 3 has it.

What waits for PX12 is the next section. Part 8 is done except PX12's
readings.

## What waits for PX12

*Filled when PX12's eligibility file is attached.* The same bundles are then
re-scored, with no rerun. The design's section 9 lists what waits:

  - the first-hour origin verdicts, `WATER.ORIGINS.<tag>.3600`, and their rank,
  - the copies' eligibility: own residual, repair, refinement, OD12 floors,
    KI4-COPIES and UP1,
  - the parent's Newton error on TRMM, from PX12's P1 probe,
  - PX5's growth clause, from its `dt` 150/75 s ladder.

## Review record

*Filled by the record PR's review.* Agents, findings and the owner's
decisions.

2026-10-09, before the PR. A first-pass finder (worker, Sonnet high) checked
the record against the design and recomputed about 30 numbers. A reviewer
(clima-reviewer, Opus high) confirmed its findings and patched the record. It
brought the intro and the runs table to the finished state and narrowed H1's
"bit for bit" to what was compared. It added the log's per-step column, the
section 4 readings, the load average of 1.00 to 1.27, the copies' closure
warnings and the verdict. Tokens: the cost worker 81k, the finder 134k
and the reviewer 127k.

2026-10-09, the PR's review (clima-reviewer, Opus high). It re-ran the `w58`
command, with the same result, and recomputed about 40 numbers from the
results, logs, CSVs and Slurm. Three build ratios of the copies were rounded
from rounded seconds and are now 23.589, 25.300 and 24.231. R1's evidence now
names what each tool compares, and the review compared the twin's 24 fields
with both tagged runs. It removed a cause offered for the faster twin, stated
H1 and H2 as not falsified, named the two readings of H3's copies half, and
dropped the walk fix owner item, closed by `dd2df01e8` before the runs.
