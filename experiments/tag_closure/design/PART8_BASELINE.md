# Part 8: water baseline and cost pilot, pre-registered

Proposed 2026-10-09. The owner decided the open choices on 2026-10-09, after
PRs #166 and #167 (section 12). Written before any job of this part. Record
branch `claude/part8-baseline` from `claude/plan-rev2` at
`aa3e80ea9`. The runs use `main` at `bb2bedf23`. The brief is
[DELIVERY_PLAN section 5, part 8](../DELIVERY_PLAN.md#part-8-water-baseline-and-cost-pilot).
The contract is [G3_PLAN 6.1.1](../G3_PLAN.md#611-water-observables-and-accounting-conventions-part-2)
and [6.1.2](../G3_PLAN.md#612-water-acceptance-matrix-authoritative-part-2-specification).
Where this note and a source differ, the source wins.

A baseline is not a qualification. It raises no level, sets no threshold,
default or tolerance, and changes no model code. Every choice this note makes
was marked "proposed, 2026-10-09" and is listed in section 12, which marks
each decided choice.

## 1. The question

Which error term of the initial useful water workflow is largest on the
current `main`, in each mode, and what do the tags cost at the intended count?
Part 9 takes its order from the answer. A second question rides along: do
W58's numbers stand after PR #146 and ClimaParams 1.3.0?

Three readings answer it.

  - **H1, the prior stands.** The rerun gives W58's recorded verdicts. It is
    falsified if any recorded pass of W58 becomes a fail. Each number is
    compared bit for bit with its prior. A changed number is reported beside
    the prior, not judged.
  - **H2, the order of the error terms.** From W58's data, run through this
    note's tools on 2026-10-09, the order is the one in section 7. It is
    falsified if the rerun ranks another term first in a mode. Part 9 then
    follows the rerun, not the prior.
  - **H3, the cost.** The 8 + 8 step with ledgers in the default mode stays
    above OD3's 2x, as E88's 9.10x did. The copies at 8 + 8 with ledgers do
    not build within 4 h, as E88's addendum found without ledgers. Either is
    falsified by the reading in section 8. Neither is a verdict. Criterion
    10 is scored in part 10.

## 2. Inputs and their state

| Input                                         | State on 2026-10-09                                  | Default used here                                                     |
|:--------------------------------------------- |:---------------------------------------------------- |:--------------------------------------------------------------------- |
| OD9 to OD11, the labels                       | Proposed (DECISIONS 2026-10-07)                      | The table uses them with the mark "proposed"                          |
| OD15                                          | Proposed (DECISIONS 2026-10-09)                      | Not used. It concerns 1M precipitation                                |
| W54 to W62 after #146 and ClimaParams 1.3.0   | Measured at `b34bbd8b`, before both                  | Labelled prior. The reruns answer it. Changed numbers sit beside them |
| Six-hour, three-tag and 0M precipitation rows | No tolerance approved (6.1.1, WA-SCOPE, WA-PRECIP)   | Reported, not scored                                                  |
| PX12, comparator eligibility on TRMM 0M       | Queued under part 7, not run                         | Origin rows computed, verdict not assessable until PX12 (section 9)   |
| W58's archive sync                            | Not done. W58 exists on scratch only (RUNS.md)       | The session syncs it before the first job                             |
| The 1-2-day sphere pilot                      | 12d's brief                                          | Not in this part                                                      |
| The walk fix                                  | Part 9's queue item (DELIVERY_PLAN sections 3 and 5) | Not measured here                                                     |

The part 8 brief says the walk fix's post-fix measurement is in 12c. Section
3 of the delivery plan and the part 9 brief put it in part 9's queue. This
note follows section 3 and lists the difference for the owner.

## 3. Configuration and modes

The fixed settings are W58's. The three configs
[`p8_trmm0m_{untagged,default,copies}_6h.yml`](../configs/) are W58's
`g3b_trmm0m_*_6h.yml` with a new `job_id` and three comment lines, so the
output goes to its own directory. A test pins the rest of each file to W58's
(`test_part8_pilot.py`, `JobScriptTests`).

  - **Case.** TRMM_LBA, a prognostic EDMF column with 0M microphysics, 82
    levels to 16.4 km, `dt` 150 s, ARS222, Float64, 6 h (144 steps).
  - **Tags.** Three: `pbl` and `free`, region tags split at 1000 m, which
    partition the water, and `evap`, a source tag on the surface flux. Per-tag
    ledgers on. The closure check and its audit every 30 min.
  - **Modes.** `default` is the follower (`water_tag_transport: increment`).
    `copies` sets `water_tag_updraft_copy: true`. The untagged twin has no tag
    key. It writes `hus` and `rhoa` every 10 min for OD2.
  - **Output.** Every field every 30 min. The precipitation `pr` also as a
    30 min average.
  - **Model.** `main` `bb2bedf23`. Since W58's `b34bbd8b` it has #145, #143,
    #142, #146, #156 (ClimaParams 1.3.0) and #160 (tests only).

The explicit-1M rule is part 7's (WP5b-V). It is not compared here.

## 4. Observables and rows

Every row is the contract's row in 6.1.2 with its observable from 6.1.1.
Thresholds are cited by the scorer's names, whose values `score_acceptance.py`
holds and `test_acceptance.py` pins. "Scored" means the scorer gives a verdict
against an approved number. "Reported" means a number without a verdict. The
scorer runs with `pilot_first_hour`, the TRMM 0M 6 h scope of 2026-10-07.

| 6.1.2 row                        | Observable on the pilot                                                 | Threshold ID                                                                                  | Status on the pilot                                                                                              |
|:-------------------------------- |:----------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------- |
| Scope and definitions            | Resolved config, tag roster, pilot scope                                | Support rules (4.8), WA-SCOPE                                                                 | Roster scored. Pilot scope reported, low power                                                                   |
| Parent parity                    | Every exported field bit for bit against the twin, both modes           | Fork parity rule                                                                              | Not assessable: exported scope only. A differing field stops the part (section 10)                               |
| Parent validity                  | Negative water, latch, temperature floor, top-level change              | NEGATIVE_WATER_MAX, TEMPERATURE_FLOOR_K, TOP_CHANGE_K                                         | Scored                                                                                                           |
| Parent validity, Newton          | Fixed-parent one-step E                                                 | NEWTON_MAX                                                                                    | Data failure: no field. W57's E is a prior from D4-W. PX12's P1 probe measures TRMM                              |
| Closure                          | Gross residual at 6 h over raw untagged water, and over T+              | WATER_GROSS                                                                                   | Reported: the approved closure is at 24 h, no transplant                                                         |
| Named remainder                  | Named-parts remainder                                                   | NAMED_REMAINDER_MAX                                                                           | Data failure: no field. Reported as a limitation                                                                 |
| Copies eligibility               | Copies' own residual, repair per day, refinement, OD12 floors           | COPIES_RESIDUAL_MAX, COMPARATOR_REPAIR_PER_DAY, COMPARATOR_REFINEMENT_MAX, FLOOR_FRACTION_MAX | Reported from the tables. Eligibility waits for PX12                                                             |
| Per-tag origins, 1 h             | A_i, L1_i, L∞_i at 1 h, small-tag rule                                  | ORIGIN_L1_FIRST_HOUR, ORIGIN_LINF_FIRST_HOUR, SMALL, SMALL_SHARE                              | Default bundle: not assessable until PX12, values kept. Copies bundle: no reference, so a data failure           |
| Per-tag origins, 3 and 6 h       | L1 and L∞ default against copies                                        | none                                                                                          | Reported, as W58                                                                                                 |
| Per-tag origins, 24 h            | none                                                                    | ORIGIN_L1_DAY, ORIGIN_LINF_DAY                                                                | Not applicable (pilot scope)                                                                                     |
| Process/donor origins            | Process-weighted D_i                                                    | PROCESS_WEIGHTED_MAX                                                                          | Data failure: no applied process amounts. Part 7's references                                                    |
| Numerical intervention           | Aggregate repair per day, per-tag `led_fix` fraction, `led_inc`, counts | AGGREGATE_REPAIR_PER_DAY, LED_FIX_MAX                                                         | Aggregate scored per OD2 window. Per-tag rows a data failure in the scorer (section 6), reported from the tables |
| Accepted applications            | Cancellation-safe application accounting (part 5 reader)                | WA-GATES (a)                                                                                  | Not assessable: no registered producer                                                                           |
| 0M precipitation sum             | D_p and source shares at each output, no-rain absolute defect           | none (WA-PRECIP)                                                                              | Reported. The integrated row is not assessable                                                                   |
| Rain/snow, precipitation origins | none                                                                    | 6.1 rain and snow rows                                                                        | Not applicable (0M)                                                                                              |
| Convergence, refinement          | Time, grid and Newton ladders                                           | OD3 refinement rows                                                                           | Not assessable: no ladder here. PX12 has the `dt` 150/75 s ladder                                                |
| Aggregation                      | Nested groups at the intended count                                     | OD3 aggregation row                                                                           | Not assessable: three tags                                                                                       |
| Reproducibility, restart         | Evidence row, checkpoint round trip                                     | Criteria 1, 2, 12                                                                             | Evidence scored. Restart not assessable: the pilot has no restart                                                |
| Cost                             | Build, step, peak memory at 8 + 8, both modes, with ledgers             | OD3 cost rows, OD3 copies row                                                                 | Measured here (section 8), reported. Criterion 10 is scored in part 10                                           |
| Held-out                         | none                                                                    | OD14, criterion 8                                                                             | Not assessable                                                                                                   |

On W58 the scorer exits 2 on both bundles, and the rerun is expected to give
the same rows. Every FAIL row is a data failure. None is a measured value over
a limit. Both bundles fail COMMON.NEWTON_TRIAL, WATER.NAMED_REMAINDER,
WATER.PROCESS_WEIGHTED and the per-tag WATER.LED_FIX rows in both windows
(section 6). COMMON.EVIDENCE fails too. It lists every row data failure, and
the submission record holds no hash for `LocalPreferences.toml`. The copies
bundle has no reference (section 12, choice 8). So its three
`WATER.ORIGINS.<tag>.3600` rows fail as data failures, and
REFERENCE.PARENT_PARITY is not assessable with a data failure. The ranked
table skips those origin rows. An exit code alone establishes nothing.

## 5. The OD2 window, read first

Before any scoring, OD2's approved rule is read on the untagged twin at its
own 10 min cadence:

    python3 analysis/evidence/part8_pilot.py od2 $OUT/p8_trmm0m_untagged_6h/output_0000 --period 10m

On W58's twin this gives a boundary at 0 s, so the whole 6 h is established
flow and the startup window has zero length. At the 30 min cadence of the
bundle, which the scorer's own OD2 row reads, the same twin has no
established window. The rule's peak rate falls in the rain after 3 h, so
three early intervals are already below 10% of it at 10 min. The boundary
marks the onset of rain more than a startup. It is reported as it falls.

The reading is fixed now, before the rerun (decided 2026-10-09):

  - The record states the 10 min reading as the OD2 window. The 10 min output
    exists for OD2 (the twin's config says so).
  - The scorer's window rows keep the windows the scorer computes at 30 min.
    The record states both readings and their difference. The scorer is not
    edited by this part.
  - The from-one-hour sensitivity row is the scorer's `sensitivity_1h`
    window, 1 h to 6 h. It stays beside the physical window.
  - The record maps each of the scorer's `startup` rows to the 10 min
    established reading by name. On TRMM 0M both cadences score the same
    interval, 0 to 6 h plus the sensitivity row, so no number or verdict
    changes here. A scorer PR that reads OD2 from the twin's cadence comes
    before part 10 scores rain on TRMM, or before a case where the two
    cadences give different windows. The scorer is not edited by this part.

## 6. Converter, scorer and glue

The converter and the scorer are used unchanged. `part8_pilot.py` adds the
glue the pilot needs. It holds no threshold of its own. It imports every limit
from the scorer, or from `closure_verdict.py` as the scorer does, and a test
pins them. It does four things.

  - **`w58`** recomputes W58's table rows (R4, R5, R8) from the closure and
    audit tables with `g3base_score.py`'s arithmetic. On the repository's
    `output/g3base/data/` it reproduces all 18 recorded TRMM rows bit for
    bit, with their verdicts. With `--prefix p8` it reads the rerun's tables
    from each run's `output_0000` under the output root and lists every row
    that differs from W58. That list answers H1 for these rows.
  - **`od2`** reads the OD2 boundary as in section 5.
  - **`tables`** writes one run's table rows. They carry the per-tag `led_fix`
    fractions from the audit's `_retained` columns, which are the 6.1.1
    observable `H_L` at accepted-step cadence. The scorer's per-tag rows read
    the ledger fields instead, and those are written every 30 min against an
    accepted step of 150 s. So the scorer names them a data failure. The table
    path reports two readings per tag: the audit's inventory fraction, as W58
    recorded it, and the scorer's fraction, a region tag over its signed
    inventory and a source tag over its absolute burden, with the small-burden
    exemption. The ranked table reads the scorer's fraction (decided
    2026-10-09). Adding step-cadence ledger output would change W58's
    configuration, so it is not done here (decided 2026-10-09). The follow-up
    before part 10 is converter and scorer together: the per-tag `_retained`
    columns mapped as `repair_retained` is, read through the scorer's
    cumulative-amount path per G3_PLAN 6.1.2. Its tests: W58's bundle gives
    COMPLETE rows equal to the table's numbers, and a mutated non-zero value
    fails above LED_FIX_MAX.
  - **`rank`** builds the ranked table of section 7 from the scorer's JSON and
    the table rows.

The scorer-level reproduction of W58's verdict is the existing test
`test_w58_pilot_first_hour` in `test_convert_output.py`. It converts and
scores W58's NetCDF output, and it skips where that output is absent, as on
CI. `test_part8_pilot.py` reproduces the table rows from the repository's
copy and always runs.

The order after the runs, all by the session or a `worker`. First, check that
every job finished. A failed job is an execution failure, recorded as such.
Then the commands below, numbered as steps 2 to 7. Run on W58's output, with
`g3b` in place of `p8`, they run as written on 2026-10-09 and give W58's
numbers of section 7.

```sh
# From experiments/tag_closure. REC is the record commit of the runs and
# REPO a clone that holds it. B is a new directory for the results.
OUT=$SCRATCH/tag_closure/output
B=$SCRATCH/tag_closure/part8
mkdir -p $B
# 2. The OD2 reading on the twin.
python3 analysis/evidence/part8_pilot.py od2 $OUT/p8_trmm0m_untagged_6h/output_0000 --period 10m \
    --json $B/od2.json
# 3. The default bundle, with the copies as reference, and the copies bundle, with none.
python3 analysis/evidence/convert_output.py --family water \
    --candidate $OUT/p8_trmm0m_default_6h/output_0000 --reference $OUT/p8_trmm0m_copies_6h/output_0000 \
    --untagged $OUT/p8_trmm0m_untagged_6h/output_0000 --period 30m --pilot-first-hour --same-parent \
    --planning-commit $REC --scorer-commit $REC --git-repo $REPO --out $B/default
python3 analysis/evidence/convert_output.py --family water \
    --candidate $OUT/p8_trmm0m_copies_6h/output_0000 \
    --untagged $OUT/p8_trmm0m_untagged_6h/output_0000 --period 30m --pilot-first-hour \
    --planning-commit $REC --scorer-commit $REC --git-repo $REPO --out $B/copies
# 4. The scorer on both bundles.
for m in default copies; do
    python3 analysis/evidence/score_acceptance.py score $B/$m/manifest.json --json $B/${m}_score.json
done
# 5. The table rows and the ranked table of each mode.
for m in default copies; do
    python3 analysis/evidence/part8_pilot.py tables $OUT/p8_trmm0m_${m}_6h/output_0000 $m \
        --json $B/${m}_tables.json
    python3 analysis/evidence/part8_pilot.py rank --mode $m --score $B/${m}_score.json \
        --tables $B/${m}_tables.json --newton 4.10e-3 --newton-source "FINDINGS W57, D4-W, prior" \
        --out $B/${m}_rank.csv
done
# 6. The rerun's table rows against W58's record (H1).
python3 analysis/evidence/part8_pilot.py w58 $OUT output/g3base/g3base_scores.csv --prefix p8 \
    --json $B/w58.json
# 7. The 3 h and 6 h L1 rows that W58 reported.
python3 analysis/evidence/compare_runs.py --reference $OUT/p8_trmm0m_copies_6h/output_0000 \
    --run $OUT/p8_trmm0m_default_6h/output_0000 --family water --hours 1,3,6
```

The converter and the scorer exit 2 on both bundles, as section 4 states.

## 7. The ranked table of error terms

One table per mode, written by `part8_pilot.py rank`. Its columns: rank, mode,
term, observable, value, units, limit ID, fraction of the limit, status,
source, fix candidate, note. Every number names its source: a scorer row ID
and metric, or a table column.

| Term                   | Observable and source                                                            | Fix candidate in part 9's queue                                  |
|:---------------------- |:-------------------------------------------------------------------------------- |:---------------------------------------------------------------- |
| Closure residual       | WATER.CLOSURE `gross_over_raw`                                                   | Default: none known. Copies: none, they are the comparator (UP1) |
| Partition repair       | Audit `led_repair_retained` per day over the endpoint water                      | WP4c leak corrections, gated by PX7 and PX2                      |
| Copies' repair         | Audit `led_uprepair_retained` per day, PX5's filter share in the note            | WP4a-J and UP1 after PX12's result                               |
| Copies' own residual   | Audit `copy_residual_relative`, maximum over outputs                             | WP4a-J and UP1 after PX12's result                               |
| Origin at 1 h, per tag | `WATER.ORIGINS.<tag>.3600`, the binding norm or the small-tag rule               | WP4a-J and UP1 after PX12, WP4b stages 2 and 3 once rain starts  |
| `led_fix`, per tag     | Audit `led_fix_<tag>_retained` over the scorer's denominator by tag kind         | WP4c leak corrections, gated by PX7 and PX2                      |
| Intervention counts    | Audit `*_events` at the end. Part 5 reader: COMMON.ACCEPTED_APPLICATION_ACTIVITY | None in the queue yet. Part 9's exempt producer item             |
| Parent Newton error    | W57's E at 2 iterations, prior from D4-W. PX12's P1 probe for TRMM               | None known in the queue. The Newton count is OD1's configuration |
| 0M precipitation sum   | WATER.PRECIP_INSTANTANEOUS `max_absolute_rate_defect`                            | WP4b stages 2 and 3 (criterion 7)                                |

**The ranking rule** (decided 2026-10-09, after PRs #166 and #167). A term
measured on the pilot with a cited limit is ranked by its value over that limit,
largest first. An
origin row uses the larger of `L1/ORIGIN_L1_FIRST_HOUR` and
`L∞/ORIGIN_LINF_FIRST_HOUR`, or the small-tag absolute rule where the scorer
applies it. A prior from another case and a term without a limit are listed
after the ranked rows, without a rank. So is a term the scorer marks NOT
ASSESSABLE. It shows its value and the comparator's name, with no fraction of
a limit (decided 2026-10-09). Until PX12 attaches its eligibility file, the
first-hour origin terms are such readings (section 9).
Ties, such as several zeros, keep the order of the table above. A fraction is
a reading against a cited limit. It is not a verdict, and a six-hour reading
against a 24 h limit is not a transplant.

**The origin comparator** (decided 2026-10-09). The brief asks for the
first-hour L1 against the references that parts 6 and 7 made eligible. Those
parts made references eligible on their own known-answer fixtures, not on
TRMM 0M. Which comparator is eligible on this case is PX12's answer, and PX12
is part 7's run, not yet made. So the default bundle reads its origin terms
against the rerun's copies, as W58 did. The scorer marks them NOT ASSESSABLE,
so they are listed, not ranked. Once PX12's eligibility file gives them a
verdict, the rule above ranks them. If PX12 names another comparator, the
record says so and reads the origin terms against it. If PX12 finds the
copies ineligible on this case, the terms stay unranked readings and part 9
takes nothing from them.

**The prior order**, from W58's data on 2026-10-09:

| Mode    | Rank 1                             | Rank 2                           | Rank 3                       | Listed                                       |
|:------- |:---------------------------------- |:-------------------------------- |:---------------------------- |:-------------------------------------------- |
| default | Closure at 6 h, 1.9e-12 (reported) | Partition repair, 0              | `led_fix:pbl`, 0             | Newton prior 4.1, 27,413 events, D_p 3.0e-19 |
| copies  | Copies' repair, 0.253              | Closure at 6 h, 0.177 (reported) | Copies' own residual, 0.0116 | Newton prior 4.1, 15,317 events, D_p 3.4e-8  |

The default's closure is 1.9e-12 of the limit, and its partition repair and
`led_fix` are zero. Its first-hour origins are listed without a rank, as
values against the rerun's copies with no fraction of a limit (decided
2026-10-09). They wait for PX12, and part 9 takes no fix from an origin
reading that is not assessable. The copies bundle has no
origin terms, since it has no reference. The listed parent Newton error is
four times NEWTON_MAX on D4-W. It is not this case, and no fix in the queue
addresses it.

## 8. Runs and their cost

Nine jobs, none submitted by this PR. Each is submitted by the session after
the owner approves it. All write under `$SCRATCH/tag_closure/output`.

| Job                   | Config or arm                               | Estimated node-hours | Limit | Memory | Source of the estimate                       |
|:--------------------- |:------------------------------------------- | --------------------:| -----:|:------ |:-------------------------------------------- |
| p8_trmm0m_untagged_6h | `p8_trmm0m_untagged_6h.yml`                 | 0.2                  | 1 h   | 48G    | W58 job 14119365: 10.7 min                   |
| p8_trmm0m_default_6h  | `p8_trmm0m_default_6h.yml`                  | 0.25                 | 1 h   | 48G    | W58 job 14119366: 14.8 min                   |
| p8_trmm0m_copies_6h   | `p8_trmm0m_copies_6h.yml`                   | 0.25                 | 1 h   | 48G    | W58 job 14119367: 14.9 min                   |
| p8_default_a, _b, _c  | D4, both families, default, 0 and 8:ledgers | 1.0 each             | 4 h   | 200G   | E88 both_d3c5: 0 and 8:ledgers took 0.95 h   |
| p8_copies_a, _b, _c   | D4, both families, copies, 0 and 8:ledgers  | 5.5 each             | 9 h   | 200G   | E88 addendum: build 4 h 16 min, peak 21.4 GB |

E88's both_d3c5 job ran points 0, 8 and 8:ledgers in 1,140, 1,682 and 2,286 s
(its `status.csv`). Its 8 + 8 point peaked at 14.5 GB without ledgers. The
copies' 21.4 GB is also without ledgers. The 200G request covers both.

About 20.2 node-hours expected and 42 at the limits. The cost set has energy
tags and more than 24 h at its limits, so it goes to the owner as a set first
(DELIVERY_PLAN section 2). The scripts are
[`runscripts/part8_trio.sh`](../runscripts/part8_trio.sh) and
[`runscripts/part8_cost.sh`](../runscripts/part8_cost.sh), which calls
`submit_wp9.sh` with `SET=p8`. Each header carries its estimate.

**The trio.** One job per run, a whole node each (`--exclusive`), 2 CPUs,
through `g3base_submit.sh` with the run tree at `bb2bedf23`. The twin is
submitted first. The jobs are independent, so it need not start first. The
pilot's own cost is read from these jobs: the build is the sum of
the cache, tendency and integrator phases in the `.err` log, the step is the wall
time of the progress log's last line over the steps it counts, and the peak
memory is Slurm's MaxRSS. W58's last line counts 137 of the 144 steps. The step includes output and the closure audit. It is one sample on
one node, reported, not the WP9 measure (decided 2026-10-09).

**The cost pairs** (decided 2026-10-09). Each job runs the untagged point 0
and then 8 water and 8 energy tags with both families' per-tag ledgers, on D4,
in one mode. The ledgers are the diagnostics the owner put on every
validation run (2026-09-24). The driver allows no closure check, so the check's
cost stays T2/T3's. Three jobs per mode, so the replicates can fall on three
nodes. E88's addendum found the copies' build 6.8% over 4 h, inside the node
spread of the untagged build, so the node spread is read here. The driver,
the warm-up of 50 steps and the six blocks are WP9 section 10's.

**How the cost is read.** WP9 section 11's rule: blocks 2 to 6, the minimum
and the median, the less favourable quoted. The rule extends from the blocks
of one job to the nodes of a cost set (decided 2026-10-09, after PRs #166
and #167). The less favourable node is quoted, for the copies' build the
slowest, and the other nodes are recorded as the favourable case. Each
point's block spread and its ratio's block spread are at most 10%, or the job is
reported with its spreads
and not quoted. Nothing is rerun. For each mode: the step ratio to its own
point 0, the build ratio and seconds, allocation per step and peak memory, and
the spread across the three nodes. If two replicates land on one node, that is
reported. E88 (9.098x with ledgers, build 2.14x) and the addendum (copies
build 15,377 s without ledgers) are quoted as prior. OD3's cost row, 2x at
the intended count, and its copies row, a build within 4 h, are cited beside
the readings. No cost cap is proposed, and none is set. WA-COST's cap is
deferred until the walk fix is measured (decided 2026-10-09). It is set from
the post-fix measurement that part 9's walk fix item pre-registers.

## 9. What waits for PX12

PX12 is part 7's run. Its declared eligibility file attaches to the existing
bundles through `manifest.py --attach-acceptance`, with no rerun here.

  - The first-hour origin verdicts, `WATER.ORIGINS.<tag>.3600`.
  - The copies' eligibility: own residual, repair, refinement, KI4-COPIES and
    UP1.
  - The parent's Newton error on TRMM, from its P1 probe. Until then W57's
    D4-W value is a prior.
  - PX5's growth clause, from its `dt` 150/75 s ladder. Until then PX5's
    reading on TRMM is the filter's share alone.
  - The rank of the origin terms. Until PX12, they are readings only, listed
    without a rank or a fraction (section 7).

## 10. What stops the part, and what would change the plan

  - **A parent difference.** Any exported field of a tagged run that is not
    bit for bit the twin's is a defect under the fork's parity rule. The
    record states it, ranks nothing, and stops for the owner.
  - **A flipped verdict.** A recorded pass of W58 that fails on the rerun is
    a regression since `b34bbd8b`. It goes to the top of part 9's queue with
    the commit range #145 to #160.
  - **Another first term.** If the rerun ranks another term first in a mode,
    part 9 follows the rerun.
  - **A failed job.** It is an execution failure, not a scientific result.
    The session reports it and does not rerun without the owner.

## 11. Budget

The PR: 0.9M subagent tokens, of which the author 300 to 400k. The record
PR after the runs: 0.3M. The runs: section 8.

## 12. Choices made here, proposed 2026-10-09 unless marked decided

 1. The trio's configs differ from W58's only in `job_id` and comments.
    Decided 2026-10-09.
 2. The trio takes whole nodes, so its build and step are a one-sample cost
    reading of the pilot. Decided 2026-10-09.
 3. The cost pairs: three jobs per mode, each with point 0 and 8 + 8 with
    ledgers. Decided 2026-10-09.
 4. The OD2 reading of section 5: the twin's 10 min cadence for the record,
    the scorer's 30 min windows kept and the difference stated. Decided
    2026-10-09.
 5. The per-tag `led_fix` rows are reported from the audit's `_retained`
    columns. No step-cadence output is added. Decided 2026-10-09, with the
    converter and scorer follow-up of section 6 before part 10.
 6. The ranking rule and the fix candidates of section 7. NOT ASSESSABLE
    terms, the first-hour origins until PX12, are listed without a rank or a
    fraction (decided 2026-10-09). The rule itself and the fix candidates are
    decided 2026-10-09, after PRs #166 and #167.
 7. W57's D4-W Newton error is listed as a prior, unranked. Decided
    2026-10-09.
 8. The default bundle has the copies as reference, since no reference of
    parts 6 and 7 is eligible on TRMM 0M before PX12 (section 7). The copies
    bundle has no reference. Decided 2026-10-09.
 9. The brief's "D4-W" for the cost pairs is read as WP9's D4 column,
    `wp9_energy_d4_edmf` (DYCOMS RF02, 1M, EDMF, 30 levels), where E88
    measured 8 + 8. The D4-W runs of W54 to W57 use another config. Decided
    2026-10-09.
