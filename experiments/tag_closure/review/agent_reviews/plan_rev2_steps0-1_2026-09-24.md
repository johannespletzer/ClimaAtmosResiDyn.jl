# Rev. 2 of the work plan, steps 0 and 1: what was done, 2026-09-24

The owner's "Simulation-results synthesis and in-place work-plan revision,
rev. 2" was carried out by an agent for steps 0 and 1 of its execution order.
The agent stopped before step 2, which needs OD1 to OD3. Nothing was pushed,
no job was submitted, and no owner decision was filled in. This report is
the agent's own account, not a review of the plan.

## 1. Commits

| Branch                            | Worktree                        | Base                   | Commits                                                                                                                                                                      |
|:--------------------------------- |:------------------------------- |:---------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude/energy-explicit-1m-guard` | `ClimaAtmosResiDyn-g416guard`   | `main` at `0b2b1032`   | `33eeb5cd` the guard, its test and docs                                                                                                                                      |
| `claude/water-tags-wp6-step3`     | `ClimaAtmosResiDyn-wp6s3`       | #103 at `f22cfb27`     | `98324f00` code; `6e93eec0` config keys and docs; `a0d00b25` tests                                                                                                           |
| `claude/plan-rev2`                | `ClimaAtmosResiDyn-plan2`       | the record at `66a10f07` | `0ccef48f` step 0's record edits; the next commit, step 1's record entries (design note section 10, the check script, `output/wp6_step3/`) and this report                |

## 2. Step 0

### 2.1 The guard (G4.16's interim refusal)

`energy_source_tag_transport: enthalpy_increment` with `microphysics_model: 1M`
and `implicit_microphysics: false` now errors in `AtmosTagging`
(`check_energy_source_increment_microphysics_supported`,
`src/config/tracer_config.jl`), unless the opt-in key is set.

  - **The key, a proposed name:** `energy_source_tag_increment_allow_explicit_1m`,
    default `false`. With `true` the configuration runs and the model warns.
    The key is refused without `energy_source_tags`, as its sibling keys are.
  - **Documented** in `config/default_configs/default_config.yml`,
    `docs/src/energy_source_tags.md` (the requirements of the increment
    mode), the guide's key table and NEWS.
  - **Only a refusal.** It reads only the tags' own keys and the
    microphysics keys. Without the tags, with another transport, or with the
    microphysics implicit, nothing changes. No test and no shipped config sets
    the refused combination. The record's `g415_n5_explicit_n1.yml` and
    `g415_n5_explicit_n10.yml` do, so they need the key on a branch with the
    guard.
  - **Scope:** only 1M, as the plan names it. 2M and P3 stepped explicitly are
    neither measured nor refused.
  - **Tested** in `test/config/tracer_config.jl`: the default errors (two
    message checks), the opt-in passes with its warning, implicit 1M and the
    tracer transport are unchanged, a quoted value and the key without tags
    are refused. On the login node the file passes, the testset 24/24, and
    `test/config.jl` passes (every key has help and value; config files set
    only schema keys). Logs: `output/g416_guard/`.

### 2.2 The records

  - **ROADMAP.md:** the M2 to M5 rows and a new section "Rev. 2 of the work
    plan" with the acceptance contract, the decision register OD1 to OD8
    (each `OWNER DECISION REQUIRED (ODn)`), and the execution order with
    each step's state. The sentence "G3 reverses that" (M4 after M5) now says
    that rev. 2 keeps M4 before M5.
  - **STATUS.md:** the conditional G3 status, the new G4 status, an update
    entry for rev. 2, OD1 to OD8 under the open decisions, rows for #105 to
    #107, the jobs the record names as running, and a "Where to look" row.
  - **G3_PLAN.md:** a revision note at the top; a rev. 2 note under the
    criteria of section 2; 4.2's rule replaced by the entry gate with the
    three-part retention rule; 6.1's single verdict replaced by the contract,
    windows (OD2), comparator eligibility first, and intervention; the
    sphere's plateau replaced by OD6's ceiling and growth bound, with the
    derived figures; WP4c, WP6 and WP9 rows with "Scope added (rev. 2)"; the
    revised order.
  - **G3_TODO.md:** OD1 to OD8 under Decisions; "Scope added (rev. 2)" on the
    W25 follow-up, WP5b-V, WP5b-C (with its unpushed state), WP4c, WP4b, WP6
    and WP9; the sphere's numbers now in OD6's form.
  - **G4_TODO.md:** a rev. 2 note; "Scope added (rev. 2)" on G4.1 (with G4.11),
    G4.3 to G4.6, G4.7 and G4.8, G4.15 and G4.16; G4.16's last item ticked
    with the guard's commit.
  - **DECISIONS.md:** OD1 to OD8 and W33's verdict under "Waiting for the
    owner"; a 2026-09-24 entry listing what rev. 2 decides.
  - **FINDINGS.md annotations, none of them a rewrite:** W21 for D4-W, with
    one-line pointers in W24, W25, W28 and W31; W29; E39; E76; and W18, whose
    consequence rev. 2's 4.2 supersedes. The index now reads W1–W35.

## 3. The record's version where the plan differs

The plan pins `65925262`. The record was at `66a10f07`: `ea42cf26` (W35),
`48013282` (#106, #107), `ac94a422` (the long runs' seeded radiation, first
submission void), `c80f1abb` (the second submission), `66a10f07` (the seed
trap in README). Where the plan or the task's notes differ from the record,
the record's version was written:

 1. **The same-atmosphere addendum is done.** W35 passes both criteria. At
    `dt` 120 s the one-step `E` falls from 2.6e-2 to 1.2e-3 for `pbl` and from
    3.9e-2 to 1.7e-3 for `free` with a second iteration. With one iteration
    it halves at 60 s (ratios 0.50 and 0.47). W33 stays a failure; the owner
    decides whether its verdict changes. The plan's STATUS wording "same-
    atmosphere addendum pending" and step 5's "execute the addendum" were
    written as done.
 2. **E39 is not a default-against-copies gap.** The plan (Insight 2, G4.1/
    G4.11) groups "energy sfc gaps (E39, E76)". E39 has no copies: it measures
    the audit's first-hour closure against the Newton count and the step. The
    first-hour `sfc` gaps of 14 to 21% are E76's; E73's 16% at 1 h is the same
    comparison at the baseline. E39's annotation says so.
 3. **E76's first hour worsens monotonically as the step shrinks,** 14.3% at
    120 s, 19.4% at 60 s, 21.3% at 30 s. The plan says it "does not improve
    monotonically".
 4. **E79's "closure near 1e-5"** is the same-sign rule's 9.2e-6 (G4.15b, not
    merged). The merged |m| rule gives 2.3e-6. The moved ledger is 0.289 and
    0.288 under the two.
 5. **E75's "10–19%"** is its title. Its ten-day table runs from 9.1% (`rad`)
    to 19.1% (`new_extratropics`).
 6. **Water's 7.8e-3 lag is W23's net residual** (the copies row; the default
    row is 7.7e-3 net and 1.6e-2 gross). Ten iterations remove the net
    (−4.3e-7) but leave the gross at 7.5e-4 and 7.7e-4 under the tracer
    transport. "Ten iterations nearly remove both" holds for the net.
 7. **W31's 7.3e-6** is measured against W28's same-sign run, 1.35e-4, not
    W24's |m| run, 1.5e-4.
 8. **ROADMAP had M5 before M4 for G3** ("G3 reverses that"). The plan says
    "keep M4 before M5". ROADMAP now records the change.
 9. **WP5b-C** (the task's notes). Built in `../ClimaAtmosResiDyn-wedmf5c` at
    `d2b3dc60`; not pushed; not in FINDINGS; probe output in
    `output/wp5c_probe/`. The record's `copies_audit.txt` gives, on W23's
    column under the follower, the copies' last-step residual 1.005e-4 to
    9.15e-5 of the water and their cumulative repair 9.16e-4 to 6.52e-4; under
    the tracer transport −4.1% and +4.2%. The 68/68 test and the 1e-16 block
    check are not in the record. The tracked files say only that the copies on
    every pushed branch lack their own explicit-1M cross blocks and a fix is
    pending.
10. **The long runs' second submission** (jobs `13917157` to `13917199`) is in
    G4_TODO. "Its tagged runs are bit for bit equal to their untagged twins so
    far" is not in the record, so no tracked file says it.
11. **Job `13911480`** (32 copies, 8 h) is recorded as running in W34. Slurm was
    not queried.
12. **Housekeeping found stale:** FINDINGS' index said W1–W33 (W34 and W35
    exist); STATUS's PR table lacked #105 to #107.
13. **G4.16** left "refuse, or document the lag" to the owner. Rev. 2 decides:
    refuse, with an opt-in.
14. **G3_TODO** said WP6 step 3 waits on the owner's three points. Rev. 2 says
    it needs none; the code takes the conservative side of each (section 4.5).

## 4. Step 1: WP6 step 3 with the per-tag ledger

The design is section 10 of `design/GROSS_ACCUMULATORS.md`. In short:

### 4.1 What was built

  - **Accepted-step gross throughput.** The per-step gross of every state
    ledger (step 2's callback) is reported in the audit as `<L>_retained` and
    `<L>_retained_relative`.
  - **Attempted against retained.** Each ledger per mechanism gets a Float64
    `attempted` accumulator: the kernel keeps the ledger before a call and adds
    |change| after it, stage values the stepper discards included. The
    increment corrections add each stage's |entry| for `inc_left` and
    `inc_moved`, both families. Reported as `<L>_attempted`.
  - **Event counts** per accepted step, in the callback, against the cell's
    water or partitioned energy: `<L>_events`.
  - **Validity by cadence.** `ledger_cadence_step` in the audit; a warning at
    setup under `stage` or `dss`.
  - **Restart stitching.** The checkpoint carries every cache accumulator:
    `ᶜwater_fix`, `ᶜwater_upfix`, `ᶜenergy_source_fix`, their twins and
    counts, and per state ledger the gross, column gross, events and
    attempted total. `AtmosSimulation` reads them back. A checkpoint without
    them starts them at zero with a warning; a partial set is refused.
  - **The per-tag ledger (Insight 10), opt-in per family:**
    `water_tag_ledger_per_tag`, `energy_source_tag_ledger_per_tag`.
    `q_tag_led_fix_<name>` (rescale, emptying, repair) for every tag and,
    under the follower, `q_tag_led_inc_<name>`; `e_src_led_fix_<name>` and
    `e_src_led_inc_<name>` likewise. The kernels write each tag's change into
    its ledger from the same expression; the follower's flux goes through the
    same kernel into the ledger's tendency, so it is the tag's change bit for
    bit. The audit reports each ledger's `_inventory_fraction`: the retained
    gross over the tag's integral now.

### 4.2 What the per-tag fraction bounds

Under the follower most of `led_inc` is the parent's vertical advection, which
the tags no longer take explicitly. So the fraction bounds the follower's
intervention on a tag from above. It does not isolate it.

### 4.3 Parity

Every new write goes to the cache or to the ledgers' own state fields; the
tags' and the model's arithmetic is unchanged. Without the new keys the state
is #103's. The increment integration test now runs its tagged column with
both families' ledgers per tag, so its bitwise parity check covers them.

### 4.4 Tests

See section 5.

### 4.5 Open questions, with the conservative default taken

 1. A pre-WP6 checkpoint: still refused (the owner's point 1 of the note's
    section 8). A checkpoint from after step 2 and before step 3 restarts with
    the cache accumulators at zero and a warning.
 2. Loss and τ stay out of WP6 (point 2).
 3. The ledgers per mechanism stay as they are, exact per step at `step`
    only (point 3). The per-tag ledgers are exact at every cadence, per tag and
    kind, not per tag and mechanism.
 4. **New:** the per-tag ledgers are off by default. Each adds one state
    field per tag, two under the follower, with their build-time and memory
    cost. The owner may want them on for qualification runs.
 5. **New:** the per-tag fraction's denominator is the tag's integral at the
    audit's time, as rev. 2 words it. Other denominators can be formed offline
    from `_retained`. It belongs with OD3's per-tag threshold.

## 5. Validation

On the login node, Julia 1.11.9, the terrabyte depot, test environments in
`$SCRATCH/claude_work/plan2/{guard,wp6s3}_testenv` that point at the
worktrees:

| What                                                        | Result                                                                                                 |
|:----------------------------------------------------------- |:------------------------------------------------------------------------------------------------------ |
| guard: `test/config/tracer_config.jl`                       | pass; "energy_source_tags against the scheme" 24/24                                                   |
| guard: `test/config.jl`                                     | pass                                                                                                   |
| wp6s3: `test/tagged_water_tests.jl`                         | 567 passed (457 at `f22cfb27`, the same file there)                                                    |
| wp6s3: `test/energy_source_tags_tests.jl`                   | 548 passed                                                                                             |
| wp6s3: `test/config/tracer_config.jl`                       | 267 passed                                                                                             |
| wp6s3: `test/tagged_water_increment_integration.jl`         | not finished: stopped after 34 min on the login node, still in its first build, with no output; for a compute node |

The water unit test file prints "Internal error: during type inference ...
Encountered stack overflow" for step 1's Float32 test with a 1002-element
tuple. It prints the same at `f22cfb27` (`output/wp6_step3/base_tagged_water_tests.log`),
and every test passes in both.

Formatting: every changed Julia and Markdown file of the two code branches is
clean under the pinned JuliaFormatter 2.10.1, and the Markdown link check
passes. The record's Markdown was not run through the formatter: it reflows
tables the edits do not touch.

## 6. Status at the hand-over, and the commands to run

Nothing is pushed and no job was submitted. On a compute node, from
`$SCRATCH/claude_work/plan2`, with the job scripts there
(`test_group_job.sh` runs test files with the scratch test environment, as the
record's earlier test jobs did; `check_job.sh` runs the check script):

    W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/plan2
    S="sbatch --account=hpda-c --partition=hpda2_compute --time=03:00:00 --cpus-per-task=2 --mem=48G"
    # step 1, WP6 step 3, at a0d00b25: one job per group
    for files in tagged_water_increment_integration tagged_water_edmf_copies_integration \
        tagged_water_edmf_integration tagged_water_edmf_0m_integration tagged_water_integration \
        "energy_source_tags_integration energy_source_tags_cold_column" \
        energy_source_tags_edmf_integration energy_source_tags_increment_integration \
        energy_source_tags_updraft_integration energy_source_tags_float32_integration \
        process_record_integration restart parent_budget/restart_ledger_tests; do
      env CODE=/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-wp6s3 TESTENV=$W/wp6s3_testenv \
          TESTFILES="$files" $S --job-name=wp6s3 \
          --output=$W/jobs/%x-%j.out --error=$W/jobs/%x-%j.err $W/test_group_job.sh
    done
    $S --job-name=wp6s3-checks --output=$W/jobs/%x-%j.out --error=$W/jobs/%x-%j.err $W/check_job.sh
    # step 0, the guard, at 33eeb5cd
    for files in energy_source_tags_increment_integration energy_source_tags_updraft_integration; do
      env CODE=/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-g416guard TESTENV=$W/guard_testenv \
          TESTFILES="$files" $S --job-name=g416 \
          --output=$W/jobs/%x-%j.out --error=$W/jobs/%x-%j.err $W/test_group_job.sh
    done

The groups are `tagging_water_increment`, `tagging_water_edmf_copies`,
`tagging_water_edmf`, `tagging_water_edmf_0m`, `tagging_water`,
`tagging_source`, `tagging_source_edmf`, `tagging_source_increment`,
`tagging_source_updraft`, `tagging_source_float32`, `tagging_record`,
`restarts` and the parent budget's restart test. The first is the one that
exercises the ledgers per tag; the rest check that nothing else moved, since
the checkpoint writer, the audit and the kernels changed for every tag run.
The guard's two groups run `enthalpy_increment` with 1M stepped implicitly and
must pass unchanged. The remaining `infrastructure` files can run on the login
node.

## 7. Derived figures, recomputed

  - **Ten days against the flushing timescale (Insight 8).** E74: 0.0105 to
    0.0165 a day, so 95.2 and 60.6 days. 10/95.2 = 10.5%, 10/60.6 = 16.5%:
    "11 to 17%".
  - **The net growth over days 1 to 10:** (2.01e-4 − 2.77e-5)/9 = 1.93e-5 a day.
  - **The level if that were the source:** 1.93e-5/0.0165 = 1.17e-3 and
    1.93e-5/0.0105 = 1.83e-3; 5.8 and 9.1 times 2.01e-4. The plan's "1.2 to
    1.8e-3, 6 to 9 times" reproduces under its assumption.
  - **With the flushed loss added back:** the mean residual over days 1 to 10
    by the trapezoid rule on E74's five points is 1.25e-4. The source is
    1.93e-5 + k·1.25e-4: 2.13e-5 at k = 0.0165 and 2.06e-5 at k = 0.0105. The
    level is 1.29e-3 and 1.96e-3, 6.4 and 9.7 times day 10. G3_PLAN 6.1 gives
    both.
  - **The copies' build (Insight 9):** 2417/699 = 3.46 = 2^1.79, so about
    N^1.8. At 32 copies, 2417 × 3.46 = 8357 s = 2.3 h. The 4 h attempt did not
    build (W30).
  - **W35's "20-fold":** 2.6e-2/1.2e-3 = 21.7 (`pbl`), 3.9e-2/1.7e-3 = 22.9
    (`free`).

## 8. The owner's decisions, as questions

  - **OD1.** Which configuration is production? Vertical levels, SGS
    reconstruction, Δt, Newton iterations, microphysics (0M or 1M, explicit or
    implicit), and the intended number of water tags and of energy tags.
  - **OD2.** For each case (D4-W, TRMM 0M and 1M, the GCM-driven column, the
    WP4b held-out case), where does the startup or source-pulse window end,
    where does established flow start and end, and what is the long-run window?
  - **OD3.** Which thresholds for parent validity; provenance beyond today's
    2%/5% and first-hour budgets; intervention, aggregate and per tag (for
    example a ceiling on `_inventory_fraction`); comparator eligibility beyond
    0.20% a day; how far throughput must shrink under refinement; the
    aggregation tolerance; and cost ceilings (build time, peak memory, per-step
    time)?
  - **OD4.** Which offset-invariant scale do energy percentages use? The
    candidate is the cumulative gross source throughput into the tags over the
    same window. May the audit of the E-records' denominators start?
  - **OD5.** At M5, does *not assessable* block a configuration, or pass it as
    "provenance bounded, not validated" when the Insight 10 tests pass?
  - **OD6.** For the sphere: which absolute ceiling, relative to the smallest
    tag analysed; which growth-rate or loss-timescale bound; and which run
    length, budgeted under M4?
  - **OD7.** For energy, after the long runs: the same-sign rule (no cell
    corrects more than its own mismatch, at four times the gross on D4,
    9.2e-6 against 2.3e-6) or |m|?
  - **OD8.** Is the reference copies at the intended tag count, whose build
    may not finish (699 s at 8, 2417 s at 16, none within 4 h at 32), or copies
    at the largest buildable count plus the aggregation bridge?

## 9. What is open

  - The integration groups and the check script (the commands are in the
    summary returned to the parent), then a review (high) of step 3 and a PR
    on #103; the guard's PR to `main`.
  - Step 3's questions 4 and 5 above, and the owner's three points of the
    note's section 8.
  - Everything from step 2 on waits on OD1 to OD3.

## 10. Addendum, 2026-09-24 evening: the owner's answers

The owner answered the register and five more points. The agent recorded them
(ROADMAP.md, "The owner's answers"; STATUS, DECISIONS, G3_PLAN, G3_TODO,
G4_TODO) and did the work they asked for:

  - **The OD3 draft** in ROADMAP.md, every number a proposal with its reason
    and the nearest measured value, with OD2's windows per case, OD6's
    ceiling, a 60-level stretching (the GCM-driven column's rule scaled to
    30 km) and M4's estimate for the 90-day, 60-level sphere, about 37 days
    on 24 ranks if cost grows in proportion *(derived)*. Step 2 waits for its
    approval.
  - **The energy guard, extended** to 1M, 2M and P3 stepped explicitly, key
    renamed to the proposal
    `energy_source_tag_increment_allow_explicit_microphysics`
    (`claude/energy-explicit-1m-guard`, `e55ae293`). The config test passes
    on the login node (testset 36/36), and so does `test/config.jl`.
  - **Water, unchanged.** The water tags refuse 2M and P3 at configuration,
    whatever the transport (`check_water_tagging_supported`). Checked on the
    login node for 2M and 2MP3 under both transports. No water branch was made.
  - **Known issue 7**, the site 23 crash, on `claude/water-tags-wp6-step3`
    (`18e7ef1d`), the branch that holds #102 and #103, the water code the long
    runs ran. The fix options: `design/NEGATIVE_PARENT_WATER.md`.
  - **OD4's audit**, first pass: `review/od4_denominator_audit.md`. It sorts
    the denominators and restates no number.
  - FINDINGS is left to the parent session (W36, E81).

One point for the owner, found while drafting OD3: Insight 10's refinement
test expects the follower's throughput to shrink under refinement. The
follower's moved ledger holds the parent's vertical advection, which does not
shrink with the step. So the draft applies the refinement test to the repair
and to `inc_left`, not to `inc_moved`. Testing the follower's lag alone needs a
way to separate the advection.
