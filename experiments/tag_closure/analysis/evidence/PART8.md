# Water baseline and cost pilot

Skeleton, 2026-10-09. The design is
[design/PART8_BASELINE.md](../../design/PART8_BASELINE.md), pre-registered
before any job. This record holds no number yet. Each section says what fills
it. The follow-up record PR fills them after the runs, from the commands of
the design's section 6. Prior numbers (W54 to W62, E87 to E90) are quoted as
prior wherever they appear.

## Runs and provenance

*Filled by the record PR.* One row per job of the design's section 8: job ID,
Slurm ID, node, model commit `bb2bedf23`, record commit, exit status, wall
time, and the archive path after the sync. W58's archive sync is recorded
first. RUNS.md gets the same rows.

## OD2 window reading

*Filled from `part8_pilot.py od2` on the twin, before any score.* The 10 min
boundary, the scorer's 30 min reading from its COMMON.OD2_WINDOWS row, and
their difference, as the design's section 5 fixes.

## Parent parity and validity

*Filled from the scorer's COMMON.PARENT_PARITY, COMMON.NEGATIVE_WATER and
COMMON.PARENT_TEMPERATURE rows of both bundles.* The exported fields compared
and any that differ. A difference stops the part (design section 10).

## Rows against W58

*Filled from `part8_pilot.py w58 --prefix p8` and the scorer's rows.* Each of
W58's rows (R1, R3, R4, R5, R7, R8, C7) with its prior value and verdict
beside the rerun's. Changed numbers are listed, not judged. H1's answer.

## Contract rows

*Filled from the scorer's JSON of both bundles.* Every row of the design's
section 4 with its verdict, data status and limitation. The scorer's exit
code and the named data failures.

## Ranked table of error terms

*Filled from `part8_pilot.py rank`, one table per mode.* The columns of the
design's section 7, every number with its source. H2's answer, and the order
part 9 takes.

## Cost

*Filled from the trio's logs and the six cost jobs (`analysis/wp9_cost_table.py`
with `--discard 1`).* The pilot's build, step and peak memory. For each mode
at 8 + 8 with ledgers: step ratio, build, allocation per step, peak memory,
the block spreads and the node spread. E88 and its addendum as prior. H3's
answer. No cap is set.

## What waits for PX12

*Filled when PX12's eligibility file is attached.* The first-hour origin
verdicts and the copies' eligibility, re-scored on the same bundles.

## Review record

*Filled by the record PR's review.* Agents, findings and the owner's
decisions.
