# WP9 / V-W10: the cost of the tags, pre-registered

Written 2026-09-29, before any V-W10 run, on the record branch `claude/rec-wp9`.
It fixes the measurement. It sets no budget. G3_PLAN 6.1 says the owner sets the
default mode's cost budget from V-W10's first measurements, before V-W11.

## 1. What V-W10 asks

G3_PLAN's V-W10 row: cost at 2, 4, 8 and 32 tags where they build in time, both
modes, with and without rain and snow tags, both families. OD8 (decided
2026-09-24) qualifies at 8 water and 8 energy tags. 32 is a cost item only.
WP9's row adds build time, peak memory and per-step scaling at the intended tag
count for the default and the comparator. G3_TODO adds that P2 and P3 (G4_TODO)
are profiled only if the profile shows them.

The modes are the default (no copies: the tags follow the parent's mass flux,
plus the exchange from the rescaled plume) and the copies (an audit tracer per
tag in each updraft). The families are the water tags (`water_tracers`) and the
energy source tags (`energy_source_tags`).

The measures are the wall time per step, the allocation per step, the peak
memory and the build time, with the compile time kept apart.

## 2. What `main` 43b01ca1 can do

  - `water_tag_precipitation` (rain and snow tags) needs 1M and is refused under
    EDMF. So it has no updraft mode. Its arm is a 1M column without EDMF.
  - The energy source tags have no rain and snow tags. The precipitation
    column does not apply to them.
  - So "both modes, with and without rain and snow tags" is: the two modes under
    EDMF without rain and snow tags, and the rain and snow tags on and off
    without EDMF. Their cross is not buildable, and the table says so.

## 3. Arms

Each arm is one Slurm job on one node, and each point in it is one Julia process.
Points run in turn, smallest first.

| Arm                | Family | Base config                | Mode    | Rain, snow | Points                                              |
|:-------------------|:-------|:---------------------------|:--------|:-----------|:----------------------------------------------------|
| `water_default`    | water  | `wp9_water_trmm0m_edmf`    | default | no         | 0, 2, 4, 8, 8:ledgers, 8:tracer, 8:increment        |
| `water_default_32` | water  | `wp9_water_trmm0m_edmf`    | default | no         | 32                                                  |
| `water_copies`     | water  | `wp9_water_trmm0m_edmf`    | copies  | no         | 2, 4, 8, 8:ledgers                                  |
| `water_1m_off`     | water  | `wp9_water_1m_column`      | n/a     | no         | 0, 2, 4, 8, 32                                      |
| `water_1m_on`      | water  | `wp9_water_1m_column`      | n/a     | yes        | 2, 4, 8, 32                                         |
| `energy_default`   | energy | `wp9_energy_d4_edmf`       | default | n/a        | 0, 2, 4, 8, 8:ledgers, 8:records                    |
| `energy_default_32`| energy | `wp9_energy_d4_edmf`       | default | n/a        | 32                                                  |
| `energy_copies`    | energy | `wp9_energy_d4_edmf`       | copies  | n/a        | 2, 4, 8, 8:ledgers                                  |
| `energy_copies_32` | energy | `wp9_energy_d4_edmf`       | copies  | n/a        | 32                                                  |

Point `0` is the untagged baseline of the base config. `:ledgers` adds the
per-tag ledgers, which the owner set on for every validation and qualification
run (2026-09-24). `:records` adds the five energy process records. `:tracer` and
`:increment` set `water_tag_transport` explicitly, so the follower's cost is
read against the tracer transport, and the table's `follower` column says what
the default `~` chose at each point.

Not run, and why. 32 water tags with copies did not build on TRMM's column in 2 h
(`13900297`), 4 h (`13898602`) or 8 h (`13911480`), and copies build time went
from 699 s at 8 to 2417 s at 16 (FINDINGS W30, W34). The code path is unchanged
by this goal, so it is not run again. It is reported as "not built in 8 h". The
`water_1m_*` arms have no mode, since they have no EDMF.

The tags: water tags are two region tags that partition the column, plus `N - 2`
source tags on the surface flux (the layout of `wp4a_pr_tag_scaling.jl`). Energy
tags at 8 are G4.15's eight, 2 and 4 are their first entries, and 32 adds 24
source tags that repeat the four sources. Every tag beyond the region tags is a
source tag, so the cost of a tag is that of a source tag, not of a region tag.

## 4. Pre-registration

  - **Machine.** LRZ terrabyte, partition `hpda2_compute`, account `hpda-c`, one
    node per job, `--cpus-per-task=4`. The nodes are shared, so a job's step
    times can carry other jobs' load. The driver records the node and its 1-minute
    load, the ratios use the minimum over the blocks, and the block spread is
    printed. It is not exclusive. If the spread of a point passes 10%, the point
    is run again on another node, and both are reported.
  - **Threads and ranks.** One rank, `ClimaComms` SINGLETON, CPU, one Julia
    thread, BLAS and OpenMP at one. As every column run before.
  - **Model.** A clean detached tree at `main` `43b01ca1`, Julia 1.11.9, the
    scratch depot `terrabyte-cpu`, gcc 13.2.0 and openmpi 4.1.8. The model
    tree is `../ClimaAtmosResiDyn-wp9-run`. The driver and configs come from
    the record tree at a pushed commit. Both must be clean, and the jobs log both
    commits.
  - **What is timed.**
    - Build: `AtmosConfig` and `get_simulation` together, with the runtime's own
      compile and recompile time and GC time reported apart.
    - The first step alone. It compiles the stepper, so it is the compile cost
      that the build did not take.
    - Step time: 4 warm-up steps after the first, then 5 blocks of 20 steps. Each
      block is timed as a whole with its allocated bytes and GC time, after a
      `GC.gc()`. The point's step time is the minimum block, with the median and
      the maximum beside it. Block `k` covers the same model time in every arm of
      a base config.
    - Memory: `Sys.maxrss()` after the build, after the warm-up and at the end.
      Slurm's `MaxRSS` (`sacct`) is the cross-check.
  - **Nothing else runs.** No diagnostics, no output and no closure check, and
    `energy_source_closure_check: false`, so the timing is the tags' own. The
    check's cost is known (T2, T3). It is not part of this measure.
  - **Builds in time.** A point builds in time if its process finishes the build
    and its 105 steps within 4 hours (`BUILD_LIMIT=4h`, enforced by `timeout`).
    Otherwise the table lists the point as not finished, with the exit status
    (124 is the timeout). The job's own time limit is set above the sum of its
    points' limits. An OOM is recorded as its exit status, and the point is
    reported as not finished for memory. The job's memory is 64 GB for the
    small arms and 200 GB for the `_32` arms.
  - **Baseline.** Point `0` of each base config, run in the first job of its base
    config, with the same code and settings and no tag key. Ratios are within a
    base config only (T5: never across).
  - **Scale of the claim.** One node type, one column per family, CPU only, one
    run per point. The numbers bound the cost on that column. The sphere's
    cost is M4's estimate, and the GPU is BACKLOG's.

The driver, the table script and the runscript are `analysis/wp9_cost_driver.jl`,
`analysis/wp9_cost_table.py` and `runscripts/wp9_cost.sh`.

## 5. What is read from it, and what is not set

The table gives, per tag count and mode: build time, first step, step time and
its ratio to the untagged baseline, the added step time per tag, allocation per
step and peak memory. From them the scaling in the tag count is read as a fit of
the added step time and the build time to `N`, with the exponent stated with the
points it rests on.

**No budget is set here.** G3_PLAN 6.1: "This session proposes it from V-W10's
first measurements, and the owner sets it before V-W11." So the budget's form
(a step-time ratio at 8 + 8 tags, a build-time ceiling, and a peak memory per
rank) is proposed with the first table, marked as waiting for the owner's
approval, and OD3's cost rows in ROADMAP.md are to be read beside it. The copies
are measured, not budgeted.

If the step-time growth in `N` is not linear, or the allocation per step is not
constant in `N`, a profile of the default mode's implicit and explicit tendency
is the next step, and P2 and P3 are read from it. That needs no model code
either. A hook in the model is not added by this goal.

## 6. Smoke test

Before the runs, `wp9_cost.sh` was run on `hpda2_test` with `WP9_STEPS=3`,
`WP9_REPEATS=2` and `WP9_WARMUP=1`, for the 1M column (points 0, 2, 2:ledgers)
and the energy column with copies (0, 2). Its result is in the progress file
and in RUNS.md's entry.
