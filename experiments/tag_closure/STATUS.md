# Status

The entry point for every session. Written on 2026-09-23 around 11:30, during
the housekeeping (step H4), and updated at 13:55 the same day, when the
housekeeping was done. Update it when something here changes. Where a fact was
not checked, it says so.

## The goals

  - **G1, a closed and explained EDMF column: met on 2026-09-20.** The energy
    source tags on D4 under the increment prototype (FINDINGS E62 to E66, E73).
  - **G2, the sphere: met on 2026-09-22.** Ten days of the production physics
    in Float32 (E74, E75).
  - **G3, the current goal: the water tags under prognostic EDMF**,
    operational in the production configuration (a sphere with EDMF and 1M),
    with precipitation provenance: rain and snow carry their own tags. The
    exchange is the default and updraft copies are the audit. Plan:
    [G3_PLAN.md](G3_PLAN.md). To-do list and criteria: [G3_TODO.md](G3_TODO.md).
    The owner approved every job within G3, and its agents. GPU is outside G3.
  - **G4, next: the energy source tags**, with what G3 learns:
    [G4_TODO.md](G4_TODO.md). The full re-check of the findings happens at its
    start.
  - **Later, sketched and not approved:** M6 (devices, precision, input data
    and restarts at scale, with the GPU decision), M7 (a production trial and a
    supported envelope), M8 (air age, memory and forecasts). Each needs the
    owner. See [ROADMAP.md](ROADMAP.md) and [BACKLOG.md](BACKLOG.md).

## Where things stand

  - **G3 has not started running.** Its plan is final and reviewed. Nothing in
    it has run. Its first work package is WP0, and the plan assumes #95 merged
    with the partition-only factor.
  - **#95 carries the partition-only factor** at `dcf7d086`, as the owner
    decided (decision 5 of G3_PLAN). The job session reran the R2 ladder's
    default runs there and recorded the result as **E76**: after a day the
    exchange agrees with the copies within 1.6% (L1) at every timestep and
    Newton count, and the first hour does not converge by design. E76 is on
    the record branch as `eec7f363`, ported from `8726d2cb`.
  - **H3 re-checked what G3 relies on** ([review/verify_g3.md](review/verify_g3.md)):
    20 claims recomputed, 1 consistent, 1 stale (W7's line citation) and 2
    discrepant (E73's build-cost figure, and one cell of E75's table). The
    errata are in FINDINGS (`388d2f3a`). G3_PLAN's cost risk already cites
    E73's corrected figures.
  - **The housekeeping is done.** The condensed documents merged into the
    record branch as #98 (H6, 13:47), after the loss check (H5) found nothing
    lost and the collective review (H5b) found them sound. `main` was merged
    in after #99 (`30913645`). The plan is archived:
    [archive/2026-09-23/CONDENSE_PLAN.md](archive/2026-09-23/CONDENSE_PLAN.md).
  - **The archive was synced again** at 13:50, before the last four worktrees
    were removed. Its copy of scratch is identical to scratch (RUNS.md, "Where
    the data lives"; the archive's README gives the file count).

## Branches, worktrees and sessions

| Branch                             | Worktree                                                                                                         | Who                              | What                                                    |
|:---------------------------------- |:---------------------------------------------------------------------------------------------------------------- |:-------------------------------- |:------------------------------------------------------- |
| `claude/tag-closure-record`        | `ClimaAtmosResiDyn.jl` (the main clone); this session commits from `ClimaAtmosResiDyn-exp`, detached, and pushes | the job session and this session | the record, built on `main`. Both rebase before pushing |
| `claude/energy-source-tag-updraft` | `ClimaAtmosResiDyn-upd`, and `-upd-run` detached at `dcf7d086`                                                   | the job session                  | PR #95 and the energy runs                              |
| (detached, upstream v0.42.11)      | `ClimaAtmos-upstream-d331fe3`                                                                                    |                                  | the parity reference for the next upstream merge        |

The old experiment branch `claude/tag-closure-experiments` and the old G3
branch `claude/g3-programme` are retired. Their remote branches were deleted
after H6. Their tips are tagged `archive/tag-closure-experiments-final`
(`8726d2cb`) and `archive/g3-programme-final` (`a52b17f7`).

G3's model code is to go on `claude/water-tags-edmf` (G3_TODO). That branch
does not exist yet.

**The job session** runs the energy jobs and owns #95. It cannot be reached
through SendMessage; findings go through the owner.

**Two late commits are handled.** `8726d2cb` (E76) is ported to the record
branch as `eec7f363`. `a52b17f7` on `claude/g3-programme` removed
`review/pr95_blend_factor_instruction.md` at the owner's request, since #95
had carried the instruction out. The record branch does not have the file
either. Its text is kept under the tag `archive/g3-programme-2026-09-23`.

The archive tags on origin: `archive/tag-closure-experiments-2026-09-23`,
`archive/tag-closure-experiments-final`, `archive/g3-programme-2026-09-23`,
`archive/g3-programme-final`, `archive/c1b-wip-backup`,
`archive/c1c-sgs-diffusion`, `archive/m3-species-lists`,
`archive/upstream-vwb-species-guard` and `archive/tagged-tracers`.

**Where G3 works.** Model code goes on `claude/water-tags-edmf` in the worktree
`../ClimaAtmosResiDyn-wedmf`, and G3's runs launch from
`../ClimaAtmosResiDyn-wedmf-run`. Neither exists yet; WP1 creates them
(G3_PLAN, section 5). Records go on `claude/tag-closure-record`. Outside
`experiments/`, it differs from `main` only in
`toml/tag_closure_c1_reference.toml`, which committed configs point to. Merge
`origin/main` into it again when `main` moves.

## Pull requests

| PR  | Branch                                   | State                                                                                                                                                                                                                                                                                                                                                     | What                                                                                                                                                 |
|:--- |:---------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------- |
| #95 | `claude/energy-source-tag-updraft`       | open, at `afd470e7`: after `dcf7d086`, two docs commits and one that takes the allocation test's bound from the dependency versions. `src/` and `config/` are unchanged since `dcf7d086`, so E76 describes the head. Its CI at `afd470e7` was running at 13:50, with no failure yet. The runs at `dcf7d086`, `2044350e` and `cd21af3a` had been cancelled | the updraft gap: the exchange by default, updraft copies as the audit, with the partition-only factor                                                |
| #96 | `claude/terrabyte-setup`                 | merged 2026-09-23, 12:12 (`3ecb6d25`)                                                                                                                                                                                                                                                                                                                     | the terrabyte setup script, its stack file, and the docs that name both machines                                                                     |
| #97 | `claude/historical-tag-closure-pages`    | merged 2026-09-23, 12:12 (`b1a088a4`)                                                                                                                                                                                                                                                                                                                     | the "Historical" notes on `docs/src/tag_closure_memo.md` and `tag_closure_experiments.md`                                                            |
| #98 | `claude/tag-closure-condense`            | merged into the record branch 2026-09-23, 13:47 (`859d38f8`)                                                                                                                                                                                                                                                                                              | H6, the condensed documents                                                                                                                          |
| #99 | `claude/prek-exclude-experiment-records` | merged 2026-09-23, 13:30 (`e8fcc0f1`)                                                                                                                                                                                                                                                                                                                     | excludes the record's frozen files (`archive/`, `output/`, `review/`, `reference/`, `configs/` under `experiments/tag_closure/`) from the prek hooks |

Only the owner merges. The token cannot mark a PR ready for review.

## Jobs in flight

  - **The job session's R2 ladder default reruns** at `dcf7d086`, jobs
    `13782601` to `13782605`. All five had finished with exit status 0 by 11:05
    (read from their provenance on scratch at 11:25). E76 records them. Their
    small tables are not yet in `output/`.
  - **G3:** no jobs yet.
  - Slurm was queried at 13:50: no job of this account was queued or running.

## The housekeeping, H0 to H7: done

The owner revived the condense plan on 2026-09-23, and it was done the same
day. The plan, with each step's outcome, is archived:
[archive/2026-09-23/CONDENSE_PLAN.md](archive/2026-09-23/CONDENSE_PLAN.md).
Its checks are in [review/](review/): the register, H3's re-check
([verify_g3.md](review/verify_g3.md)), the loss check
([loss_check.md](review/loss_check.md)) and the collective review
([housekeeping_review_2026-09-23.md](review/agent_reviews/housekeeping_review_2026-09-23.md)).

| Step | Outcome                                                                                                                                           |
|:---- |:------------------------------------------------------------------------------------------------------------------------------------------------- |
| H0   | the tags on origin, the archive directory, the record branch, #96 and #97                                                                         |
| H1   | E76 written and ported (`eec7f363`); the main clone is on the record branch                                                                       |
| H2   | the register (`52710619`)                                                                                                                         |
| H3   | the re-check of what G3 relies on (`388d2f3a`)                                                                                                    |
| H4   | the condensed documents (`2a9d4619`, with E76 merged in as `89a1954b`)                                                                            |
| H5   | the loss check: nothing lost; its 2 blocking and 21 minor gaps fixed (`274f55b0`, `68b60a62`) and re-verified                                     |
| H5b  | the collective review: sound; its fixes in `466c1297`                                                                                             |
| H6   | #98, merged at 13:47 (`859d38f8`), after the owner's review points (`d7db56b7`) and the prek fix (`3c7da2dd`); then `main` merged in (`30913645`) |
| H7   | the cleanup: 26 worktrees removed and captured, the merged branches deleted, the archive tags set                                                 |

**One loss.** The first capture of the removed worktrees missed git-ignored
files, so 34 Slurm `.out` logs are gone. The archive README says what was
lost. Captures now keep ignored files.

**Still waiting on others:**

  - `-upd` and `-upd-run`: removed after #95 merges, each after a capture that
    keeps ignored files (the archive README gives the commands).
  - `$SCRATCH/claude_work`: cleaned when the job session no longer uses it. It
    is in the archive.
  - The owner is to confirm the wider local-branch rule: all 37 merged local
    branches were deleted, not only the listed ones. Nothing unique was lost.
  - An LRZ backup restore of the lost logs, if the owner wants one.
  - A PR to `main` that moves `docs/src/tag_closure_memo.md` and
    `tag_closure_experiments.md` into the archive and edits `docs/make.jl`
    (decision 6 of 2026-09-23).

## What needs approval

Model code, a default, a tolerance and an energy reference need the owner's
approval before they are written. Model code goes into draft PRs that only the
owner merges. Every job needs the owner's approval, unless a standing one
covers it. Standing now: every job within G3 (2026-09-23). A diagnostic never
changes the model's fields (`AGENTS.md`, "Fork parity with upstream").

## The owner's open decisions

  - **The budgets of G3_PLAN 6.1**, before V-W3, and **the sphere's budget**,
    before V-W11 ([G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)).
  - **The rain and snow tags' prognostic fields**, after the design note
    WP4b-D and its review ([G3_TODO](G3_TODO.md#decisions)).
  - **WP5's default transport under EDMF**, by the rule of G3_PLAN 4.3, after
    V-W3.
  - **A durable archive for the minimal reference datasets**, and its size
    budget. The archive directory may answer part of this.
  - **ERA5 forcing for V-W8**, if WP0 finds it is not on disk. A download needs
    the owner.
  - **The merge of #95.** WP0 starts from it.
  - **A rerun of `main`'s CI.** #96 and #97 were merged with `ci-required`
    failing on cancelled checks, not on a failed test, and `main`'s own CI
    runs were cancelled too. A rerun is the owner's to start.
  - **The wider local-branch rule of H7**, above.

Every decision taken so far is in [DECISIONS.md](DECISIONS.md).

## Where to look

| To find                                                                                   | Look in                                                                                                       |
|:----------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------- |
| how to set up, submit a run, compare runs, and the traps                                  | [README.md](README.md)                                                                                        |
| the milestones M0 to M8 and where each open item goes                                     | [ROADMAP.md](ROADMAP.md)                                                                                      |
| G3's plan, criteria and budgets                                                           | [G3_PLAN.md](G3_PLAN.md)                                                                                      |
| G3's to-do list                                                                           | [G3_TODO.md](G3_TODO.md)                                                                                      |
| G4's items, and the energy items of the former OPERATIONAL_TODO                           | [G4_TODO.md](G4_TODO.md)                                                                                      |
| open items beyond G4                                                                      | [BACKLOG.md](BACKLOG.md)                                                                                      |
| every decision of the owner                                                               | [DECISIONS.md](DECISIONS.md)                                                                                  |
| what has been measured, and what was falsified                                            | [FINDINGS.md](FINDINGS.md)                                                                                    |
| every run: commit, job, purpose, findings, where its data is                              | [RUNS.md](RUNS.md)                                                                                            |
| the energy attribution path, the mixing conventions, the updraft gap, the sub-grid design | [design/](design/)                                                                                            |
| the frozen external reviews of 2026-09-21                                                 | [reference/](reference/)                                                                                      |
| agent reviews, instructions, check scripts, the register                                  | [review/](review/)                                                                                            |
| H3's re-check of G3's claims                                                              | [review/verify_g3.md](review/verify_g3.md)                                                                    |
| the originals as they were, and where their content went                                  | [archive/2026-09-23/INDEX.md](archive/2026-09-23/INDEX.md)                                                    |
| the housekeeping of 2026-09-23 and its outcome                                            | [archive/2026-09-23/CONDENSE_PLAN.md](archive/2026-09-23/CONDENSE_PLAN.md)                                    |
| the run data                                                                              | `$SCRATCH/tag_closure/output/` and `~/git/Clima/ClimaAtmosResiDyn-archive/` (RUNS.md)                         |
| the user docs of the diagnostics                                                          | `docs/src/energy_source_tags.md`, `tagged_water.md`, `process_record.md`; #95's `energy_source_tags_guide.md` |
