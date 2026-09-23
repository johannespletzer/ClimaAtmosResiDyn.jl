# Status

The entry point for every session. Written on 2026-09-23 around 11:30, during
the housekeeping (step H4). Update it when something here changes. Where a
fact was not checked, it says so.

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
    the record branch as `eec7f363`, ported from `8726d2cb`, and the condense branch
    has it (`89a1954b`).
  - **H3 re-checked what G3 relies on** ([review/verify_g3.md](review/verify_g3.md)):
    20 claims recomputed, 1 consistent, 1 stale (W7's line citation) and 2
    discrepant (E73's build-cost figure, and one cell of E75's table). The
    errata are in FINDINGS (`388d2f3a`). G3_PLAN's cost risk already cites
    E73's corrected figures.
  - **The documents are condensed** on `claude/tag-closure-condense` (H4,
    `2a9d4619` and `89a1954b`). The loss check (H5) found nothing lost. Its
    2 blocking and 21 minor gaps are fixed and were re-verified.
  - **The archive was synced again** after the day's reruns finished. Its copy
    of scratch holds 2,697 files, identical to scratch; with `claude_work` and
    the worktree captures the archive holds 5,434 files (RUNS.md, "Where the
    data lives").

## Branches, worktrees and sessions

| Branch                                | Worktree                                                                                                         | Who                              | What                                                                                                                        |
|:------------------------------------- |:---------------------------------------------------------------------------------------------------------------- |:-------------------------------- |:--------------------------------------------------------------------------------------------------------------------------- |
| `claude/tag-closure-record`           | `ClimaAtmosResiDyn.jl` (the main clone); this session commits from `ClimaAtmosResiDyn-exp`, detached, and pushes | the job session and this session | the record, built on `main`. Both rebase before pushing                                                                     |
| `claude/tag-closure-condense`         | `ClimaAtmosResiDyn-condense`                                                                                     | H4's agents                      | the condensed documents, until H6 merges them into the record branch                                                        |
| `claude/energy-source-tag-updraft`    | `ClimaAtmosResiDyn-upd`, and `-upd-run` detached at `dcf7d086`                                                   | the job session                  | PR #95 and the energy runs                                                                                                  |
| `claude/tag-closure-experiments`      | none                                                                                                             | frozen                           | the old experiment branch, tagged at `eead88c3`. Its last commit, `8726d2cb` (E76), is ported. H6 deletes the remote branch |
| `claude/g3-programme`                 | none                                                                                                             | retired at H6                    | the old G3 branch, tagged at `2d7fa835`. H6 deletes the remote branch                                                       |
| `claude/terrabyte-setup`              | `ClimaAtmosResiDyn-setup`                                                                                        |                                  | PR #96                                                                                                                      |
| `claude/historical-tag-closure-pages` | `ClimaAtmosResiDyn-histdocs`                                                                                     |                                  | PR #97                                                                                                                      |
| (detached, upstream v0.42.11)         | `ClimaAtmos-upstream-d331fe3`                                                                                    |                                  | the parity reference for the next upstream merge                                                                            |

G3's model code is to go on `claude/water-tags-edmf` (G3_TODO). That branch
does not exist yet.

**The job session** runs the energy jobs and owns #95. It cannot be reached
through SendMessage; findings go through the owner.

**Two late commits are handled.** `8726d2cb` (E76) is ported to the record
branch as `eec7f363`. `a52b17f7` on `claude/g3-programme` removed
`review/pr95_blend_factor_instruction.md` at the owner's request, since #95
had carried the instruction out. The condense branch removes the file too.
Its text is kept under the tag `archive/g3-programme-2026-09-23`.

The archive tags on origin: `archive/tag-closure-experiments-2026-09-23`,
`archive/g3-programme-2026-09-23`, `archive/c1b-wip-backup`,
`archive/c1c-sgs-diffusion`, `archive/m3-species-lists`,
`archive/upstream-vwb-species-guard` and `archive/tagged-tracers`.

**Where G3 works.** Model code goes on `claude/water-tags-edmf` in the worktree
`../ClimaAtmosResiDyn-wedmf`, and G3's runs launch from
`../ClimaAtmosResiDyn-wedmf-run`. Neither exists yet; WP1 creates them
(G3_PLAN, section 5). Records go on `claude/tag-closure-record`. At H6,
`origin/main` is merged into the record branch. The terrabyte scripts are in
`main` since #96, so afterwards only the C1 TOML differs from `main` outside
`experiments/`.

## Pull requests

| PR  | Branch                                | State                                                                                                                                                                                                                                                                                                                                       | What                                                                                                                                             |
|:--- |:------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------ |
| #95 | `claude/energy-source-tag-updraft`    | open, at `afd470e7`: after `dcf7d086`, two docs commits and one that takes the allocation test's bound from the dependency versions. The CI runs at `dcf7d086`, `2044350e` and `cd21af3a` were cancelled. The run at `afd470e7` has been queued since 12:31. `src/` and `config/` are unchanged since `dcf7d086`, so E76 describes the head | the updraft gap: the exchange by default, updraft copies as the audit, with the partition-only factor. Its CI at `dcf7d086` was not checked here |
| #96 | `claude/terrabyte-setup`              | merged 2026-09-23, 12:12 (`3ecb6d25`)                                                                                                                                                                                                                                                                                                       | the terrabyte setup script, its stack file, and the docs that name both machines                                                                 |
| #97 | `claude/historical-tag-closure-pages` | merged 2026-09-23, 12:12 (`b1a088a4`)                                                                                                                                                                                                                                                                                                       | the "Historical" notes on `docs/src/tag_closure_memo.md` and `tag_closure_experiments.md`                                                        |

Only the owner merges. The token cannot mark a PR ready for review.

## Jobs in flight

  - **The job session's R2 ladder default reruns** at `dcf7d086`, jobs
    `13782601` to `13782605`. All five had finished with exit status 0 by 11:05
    (read from their provenance on scratch at 11:25). E76 records them. Their
    small tables are not yet in `output/`.
  - **G3:** no jobs yet.
  - Slurm was not queried, so a job started since then would not show here.

## The housekeeping, H1 to H7

The plan is [CONDENSE_PLAN.md](CONDENSE_PLAN.md).

| Step | What                                                                                                                                                | State                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
|:---- |:--------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H0   | tags on origin, the archive directory, the record branch, #96, #97                                                                                  | done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| H1   | the job session writes its R2 entry, then stops editing the record documents until H6 merges, and moves to the record branch. The owner relays this | done: E76 is written and ported (`eec7f363`), and the main clone is on the record branch since 2026-09-23                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| H2   | the register, `review/register/`                                                                                                                    | done (`52710619`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| H3   | re-check what G3 relies on                                                                                                                          | done (`388d2f3a`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| H4   | write the new structure on the condense branch                                                                                                      | done (`2a9d4619`), with E76 merged in from the record branch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| H5   | the loss check, by an agent that did not write                                                                                                      | done: nothing lost; its 2 blocking and 21 minor gaps are fixed and re-verified ([review/loss_check.md](review/loss_check.md))                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| H5b  | a collective review of H1 to H7 by an independent agent, the owner's request                                                                        | done: sound ([report](review/agent_reviews/housekeeping_review_2026-09-23.md)). It checked the documents, a sample for losses, the branches and tags, the archive's checksums and scratch copy, #96, #97, H7's removals and H1. Its fixes are in `466c1297`. Its follow-ups: merge `origin/main` at H6; the conditional H7 items; the owner to confirm the wider branch rule; an optional LRZ restore; CI reruns                                                                                                                                                                                          |
| H6   | the owner reviews a PR of the condense branch into the record branch; the G3 branch and the old experiment branch retire                            | waiting                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| H7   | the approved cleanup                                                                                                                                | partly done (CONDENSE_PLAN, H7). The first capture missed git-ignored files, so 34 Slurm `.out` logs of the removed worktrees are lost; the archive README says what, and the capture is fixed. The local-branch rule applied was wider than the list: every merged local branch went; nothing unique was lost. Due now: `-setup` and `-histdocs`, since #96 and #97 merged. Waiting: `-upd` and `-upd-run` for #95's merge, after a capture with ignored files; `-condense` and the two old remote branches at H6 (their tips are tagged `archive/*-final`); `claude_work` while the job session uses it |

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
  - **The merge of #95.** #96 and #97 are merged. They were merged with
    `ci-required` failing on cancelled checks, not on a failed test, and `main`'s
    own CI runs were cancelled too. A rerun of `main`'s CI is the owner's to
    start.
  - **H6:** the review of the condense PR.

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
| the run data                                                                              | `$SCRATCH/tag_closure/output/` and `~/git/Clima/ClimaAtmosResiDyn-archive/` (RUNS.md)                         |
| the user docs of the diagnostics                                                          | `docs/src/energy_source_tags.md`, `tagged_water.md`, `process_record.md`; #95's `energy_source_tags_guide.md` |
