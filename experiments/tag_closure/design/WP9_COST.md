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
    - Step time: 10 warm-up steps after the first, then 5 blocks of 20 steps. Each
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
    and its 111 steps within 4 hours (`BUILD_LIMIT=4h`, enforced by `timeout`).
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

## 6. Smoke test and submission

Before the runs, `wp9_cost.sh` ran on `hpda2_test` with `WP9_STEPS=3`,
`WP9_REPEATS=2` and `WP9_WARMUP=1` (jobs `13999148`, `13999149` and
`13999153` to `13999155`, output in `output/wp9_cost_smoke/`). It found that a batch
node has no git, so the submitter now reads the commits, and that the
untagged baseline refuses a mode other than the default, as designed. It also
showed that a build takes about 6.5 min and the first step about 8 min on the
smallest tagged 1M column, and that a warm-up of 1 step leaves compile in the
timed blocks. So the registered warm-up is 10 steps, and each block's compile
time is recorded. Submitted 2026-09-29 from the record commit that
`submit_wp9.sh` logs, at model `43b01ca1`: `water_default` 13999627,
`water_default_32` 13999628, `water_copies` 13999629, `water_1m_off` 13999630,
`water_1m_on` 13999631, `energy_default` 13999632, `energy_default_32` 13999633,
`energy_copies` 13999634, `energy_copies_32` 13999635. Results go to
`$SCRATCH/tag_closure/output/wp9_cost/<arm>/`, and the table is
`python3 analysis/wp9_cost_table.py $SCRATCH/tag_closure/output/wp9_cost`.

## 7. Amendment of 2026-09-29: exclusive nodes, and the rerun

The first pass (jobs 13999627 to 13999635, results in `output/wp9_cost/`) ran
8 of its 9 jobs on one shared node, `hpdar10c01s04`, at once, with load
averages of 28 to 77. 19 of its 30 tagged points had a block spread over 10%,
up to 65%, also when read as the ratio to the untagged baseline block by block
(`output/wp9_cost/fit_first_pass.txt`). Section 4's rule was to rerun a point
whose spread passes 10%. So many points fail it that the owner chose, on
2026-09-29, to rerun every tagged point on exclusive nodes.

What changes, and nothing else:

  - Every job takes `--exclusive`, one node per arm, and no other WP9 job
    shares it. Slurm's `--exclusive` also keeps other users' jobs off, so the
    load average should be near the process's own.
  - The points, tags, variants, base configs, warm-up (10), blocks (5 of 20),
    time limits, build limit (4 h), model commit `43b01ca1` and driver are the
    first pass's. The record commit is the one `submit_wp9.sh` logs, and it
    differs from the first pass only in the scripts that name the results
    directory and `--exclusive`.
  - The untagged baselines are rerun too, since each ratio is read against a
    baseline measured the same way. The copies arms and `water_1m_on` have no
    baseline point of their own, since the driver refuses one with a mode or
    with rain and snow tags. Their ratios use the baseline of the same base
    config from the default arm of the same rerun.
  - Energy copies at 32 tags is tried once more with the same 4 h cap.
    Water copies at 32 stays "not built in 8 h" (W34), as the owner accepted.
  - Results go to `$SCRATCH/tag_closure/output/wp9_cost_excl/<arm>/`, and logs
    to `$SCRATCH/tag_closure/logs/wp9_cost_excl/`.
  - The first pass stays as a comparison. Where the two passes differ by more
    than the second pass's own spread, both are reported, and the ratio quoted
    is the less favourable one.
  - A point of the rerun whose blocks still spread over 10% is reported with
    its spread and is not rerun again without the owner. The claim is then
    bounded by that spread.

The budget proposal of section 5 is made from the rerun, and stays marked as
waiting for the owner.

## 8. Amendment of 2026-10-01: the P2/P3 profile

Section 5's trigger fired in the exclusive rerun (`output/wp9_cost_excl/`).
Allocation per step grows with `N`. Water under EDMF, default mode, takes
264 KB per step at 2 tags and 5.1 MB at 32. Energy takes 1.9 MB and 14.6 MB.
The local exponent of the added step time from 8 to 32 tags is 1.5 to 2.3.
The owner approved the profile on 2026-10-01, at `43b01ca1`, the commit the
trigger fired at. The step-time measure itself waits for its own amendment and
rerun, after PR #139 and the vapour-row PR merge. This section does not change
it.

**Arms.** One job per arm, `--exclusive`, account `pn49go-c`, partition
`hpda2_compute`. The model, Julia, depot, modules, single rank and thread, and
the tags are section 4's. Points run in turn, each in its own process, with a
90 min limit.

| Arm                | Base config             | Mode    | Rain, snow | Points |
|:------------------ |:----------------------- |:------- |:---------- |:------ |
| `prof_water_edmf`  | `wp9_water_trmm0m_edmf` | default | no         | 2, 32  |
| `prof_energy_edmf` | `wp9_energy_d4_edmf`    | default | n/a        | 2, 32  |
| `prof_water_1m_on` | `wp9_water_1m_column`   | n/a     | yes        | 2, 8   |

The first two are section 5's default mode. The third is the steepest growth
in the rerun: 1.2 MB per step at 2 tags and 8.2 MB at 8, a ratio of 9.9 at 8.
Its 32-tag point is left out, since its build alone took 45 min. No copies,
ledgers or records: section 5 names the default mode.

**Tool.** `analysis/wp9_profile_driver.jl`, through `runscripts/wp9_cost.sh`
with `DRIVER_NAME=wp9_profile_driver.jl`, submitted by
`PROFILE=1 runscripts/submit_wp9.sh`. Results go to
`$SCRATCH/tag_closure/output/wp9_profile/<arm>/`. The driver builds the
point exactly as the cost driver does, and takes its first step and its 10
warm-up steps. Then it runs, in order:

 1. one timed block of 20 steps (time and bytes per step), and 20 steps that
    count the allocations;
 2. a time profile (`Profile`, 1 ms sampling) over at least 20 steps and at
    least 5 s;
 3. an allocation profile (`Profile.Allocs`) over 10 steps, at a sample rate
    that records about 200,000 allocations, scaled back to bytes per step.

Each sample and each allocation gets a phase: the outermost stack frame that
names a stepper hook (`update_jacobian!`, `implicit_tendency!`,
`remaining_tendency!`, `set_precomputed_quantities!`,
`set_implicit_precomputed_quantities!`, the limiter, DSS, constraint and
initialiser hooks, `ldiv!`), `callbacks`, or `other`. It also gets a frame,
the innermost one in the model's `src/`. It is marked as tag code when a frame
on its stack is in `src/parameterized_tendencies/tagged_tracers/`. The
functions that P2 and P3 name, `_energy_source_share_norm!` and
`is_energy_source_tag_name`, are counted whenever they are on the stack. The
bytes of type `String` are counted too.

**Outputs.** Per point: a summary CSV, time and allocation by phase, the top 80
frames by time and by allocation, the P2/P3 functions, and the top 40 types.
`analysis/wp9_profile_table.py` lays each arm's two points side by side, in
`output/wp9_profile/table.md`.

**How it is read.**

  - Where the allocation growth comes from: the frames ranked by the growth in
    bytes per step from the low to the high point, until they hold 80% of the
    growth. Their phases say whether it is in the implicit or the explicit
    tendency, the Jacobian or the cache. The same is done for time.
  - A profile attributes cost to frames. It bounds where the cost is recorded,
    not why it grows. The sampled shares have sampling error, and the table
    prints the sample counts.
  - P2 shows if `_energy_source_share_norm!` is on the stack in at least 5% of
    the energy arm's time samples at either point. P3 shows if
    `is_energy_source_tag_name` holds at least 5% of the bytes per step, or
    `String` bytes grow with `N`, at either point of any arm. P3 was named
    "under the audit". If that is the closure check, it is off here
    (section 4), and a P3 that does not show here is not shown absent there.
  - The profile's step time carries the sampler's overhead. The timed block,
    taken before it, is the step time quoted. Both are one run per point.
  - Nothing here sets a budget or changes model code. A fix to P2 or P3 is a
    model change and needs the owner.

## 9. Amendment of 2026-10-02: the rerun on the new physics

Written before any job of this section, and pushed first. The owner approved
the rerun on 2026-10-02 (task 5 of that day's goals). It follows the merge of
PR #139 (upstream `a9287b2d`, ClimaParams 1.2, CloudMicrophysics 0.43), #140
and #141. The results of sections 4 and 7 keep their commit, `43b01ca1`. They
count as prior evidence only (OD12 to OD14) and are not pooled with this run.

**Commit.** The model is `main` `b34bbd8b`, in a clean detached run tree,
`../ClimaAtmosResiDyn-wp9-run-b34`, with `.buildkite/LocalPreferences.toml`
copied in. Julia, depot, modules, one rank and one thread are section 4's.

**Warm-up.** In the exclusive rerun the excess sat in block 1 (water under
EDMF, 1M) or in blocks 1 and 2 (energy), and in the untagged baselines too.
Over blocks 3 to 5 every point spread by at most 2.4%. So the warm-up grows
from 10 steps to 50, which puts the first timed block after the last step of
the old block 2. The measure keeps its form: 5 blocks of 20 steps, the
minimum block, and the spread over all five. No block is dropped after the
fact. This was chosen over a measure on the later blocks because it changes
one number and leaves the rule as it was. It costs 40 steps per point, under
a minute except for 1M with rain and snow at 32 tags (about 35 s). Block `k`
still covers the same model time in every arm of a base config. The CSV
records the warm-up.

**Baseline on the same node.** Every arm runs its own untagged point `0`
first, in the same exclusive job. Each ratio is read against the baseline of
its own arm only. The table refuses an arm whose points ran on more than one
node. This removes the cross-node bias of section 7, which was at least 17%
for one pair.

**The combined arm.** `both_default` puts 8 water tags and 8 energy tags on
D4 (`wp9_energy_d4_edmf`, 1M, EDMF), default mode. The energy tags are
G4.15's eight. The water tags are the two region tags, split at 750 m as the
energy regions are, and six surface-flux source tags. Its points are `0`,
`8` (8 + 8) and `8:ledgers` (both families' per-tag ledgers). D4 is chosen
because the energy tags' offset and regions are set for it. The water tags
need only a region height. Its ratio is the 8 + 8 number the budget needs.

**Arms.** One exclusive job each, account `pn49go-c`, partition
`hpda2_compute`. Points run in turn, each in its own process, with section
4's 4 h build limit.

| Arm                 | Base config             | Mode    | Rain, snow | Points                                       |
|:------------------- |:----------------------- |:------- |:---------- |:-------------------------------------------- |
| `water_default`     | `wp9_water_trmm0m_edmf` | default | no         | 0, 2, 4, 8, 8:ledgers, 8:tracer, 8:increment |
| `water_default_32`  | `wp9_water_trmm0m_edmf` | default | no         | 0, 32                                        |
| `water_copies`      | `wp9_water_trmm0m_edmf` | copies  | no         | 0, 2, 4, 8, 8:ledgers                        |
| `water_1m_off`      | `wp9_water_1m_column`   | n/a     | no         | 0, 2, 4, 8, 32                               |
| `water_1m_on`       | `wp9_water_1m_column`   | n/a     | yes        | 0, 2, 4, 8, 32                               |
| `energy_default`    | `wp9_energy_d4_edmf`    | default | n/a        | 0, 2, 4, 8, 8:ledgers, 8:records             |
| `energy_default_32` | `wp9_energy_d4_edmf`    | default | n/a        | 0, 32                                        |
| `energy_copies`     | `wp9_energy_d4_edmf`    | copies  | n/a        | 0, 2, 4, 8, 8:ledgers                        |
| `both_default`      | `wp9_energy_d4_edmf`    | default | n/a        | 0, 8 (8 + 8), 8:ledgers                      |

Point `0` of a copies arm or of `water_1m_on` is the plain base config, with
no mode and no rain and snow tags. Not run: copies at 32 tags. Water did not
build in 8 h (W34) and energy did not finish in 4 h twice (jobs 13999635 and
14005221), both at `43b01ca1`. They are reported with that commit and not
retried.

**Check jobs first.** Three short jobs on `hpda2_test`, with 1 warm-up step
and 2 blocks of 3 steps, results in `$SCRATCH/tag_closure/output/wp9_check_b34/`:
`check_water_copies` (0, 2), `check_both` (0, 8) and `check_water_1m_on` (2).
They cover point `0` in a copies arm, the combined family and the rain and
snow tags on the new physics. The real jobs are submitted only if every check
point exits 0 and writes its CSV. With the 9 arms that is 12 jobs. From the
exclusive rerun's point times the arms should take about 18 h of wall time in
all, run in parallel. Results go to `$SCRATCH/tag_closure/output/wp9_cost_b34/`.

**The spread rule, as amended.** For every finished point, the tagged ones and
the baselines:

  - the block spread, max over min of its 5 blocks less 1, is at most 10%;
  - for a tagged point, the spread of its ratio to its arm's baseline, block
    by block, is at most 10% too.

If any point fails either, it is reported with its spreads, nothing is rerun,
and the work stops for the owner before any finding is drafted.

**How it is read.** As section 5, with the ratio to the same arm's baseline.
The step time quoted is the minimum block, with the median beside it, and the
less favourable of the two goes into a finding. The fit is
`analysis/wp9_cost_fit.py`, now per arm baseline. The cost budget is proposed
from it, marked as waiting for the owner. It is not set here.

**Changes to the tools, all before the jobs.** The driver takes `FAMILY=both`
and writes the warm-up into the CSV. The runscript runs point `0` without mode
or rain and snow tags. `submit_wp9.sh` takes `SET=b34` and `SET=b34check`. The
table and the fit read each arm against its own baseline when every arm has
one, and the table prints the ratio spread.
