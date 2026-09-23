# Plan: consolidate the record, condense the documents, lose nothing

First approved by the owner on 2026-09-19 and put on hold the same day.
**Revived on 2026-09-23 in this form**, as the housekeeping before G3's
development. The version of 2026-09-19 is in the archive tag
`archive/tag-closure-experiments-2026-09-23`. Archive this file when the plan
is done.

## The owner's decisions of 2026-09-23

 1. Revive this plan. The results are re-checked only where G3 relies on
    them; the full re-check moves to the start of G4.
 2. Rebuild the record branch on `main`.
 3. Take the terrabyte setup to `main` in a small PR.
 4. The durable archive is a directory on terrabyte next to the worktrees:
    `~/git/Clima/ClimaAtmosResiDyn-archive/`. The workspace `AGENTS.md`
    records it as an exception to "no data in `$HOME`".
 5. Worktree and branch removal goes by a list the owner approves (step H7).
 6. `docs/src/tag_closure_memo.md` and `tag_closure_experiments.md` are marked
    historical, and move to the archive later.

## Done on 2026-09-23 (H0 and the first half of H6)

 - **Tags on origin**, so every original stays reachable:
   - `archive/tag-closure-experiments-2026-09-23` (the old experiment branch
     at `eead88c3`);
   - `archive/g3-programme-2026-09-23` (`2d7fa835`);
   - `archive/c1b-wip-backup`, `archive/c1c-sgs-diffusion`,
     `archive/m3-species-lists` and `archive/upstream-vwb-species-guard`,
     which until then were local branches only.
 - **The archive directory**, `~/git/Clima/ClimaAtmosResiDyn-archive/`
   (1.7 GB, with `SHA256SUMS` and a README):
   - `scratch_tag_closure/`, an exact copy of `$SCRATCH/tag_closure/`: 2,692
     files, the run output and the spheres' checkpoints;
   - `scratch_claude_work/`, a copy of `$SCRATCH/claude_work/`;
   - `worktrees/<name>/`, for each of the 27 worktrees, its commit, its local
     patch and its untracked files: job logs, and copies of `experiments/`.

   The originals were left in place.
 - **The record branch `claude/tag-closure-record`** (`31ac42e0`):
   - It is the G3 branch merged with `main`, so the history of both sides is
     kept.
   - Every file outside `experiments/` is `main`'s, except three: the C1
     reference TOML, which committed configs point at, and the two terrabyte
     scripts, until PR #96 merges.
   - Of the 146 files that had differed, 139 held old versions `main` had
     already had. The other seven were the terrabyte setup and the TOML, so
     nothing was dropped.
 - **PR #96** (draft): the terrabyte setup script, its stack file, and the
   docs that name both machines.
 - **PR #97** (draft): the "Historical" notes on the two doc pages.
 - The check scripts behind the G3 plan's review and the #95 instruction are
   in `review/checks/`.

## The target structure

```
experiments/tag_closure/
  STATUS.md       one page, the entry point for every session: the goals, where
                  things stand, branches, sessions and jobs in flight, the
                  owner's open decisions, where to look
  ROADMAP.md      the roadmap M0-M8 by family, the goals G1-G4 and later, and
                  where each open item goes (moved from OPERATIONAL_TODO's top)
  DECISIONS.md    every owner decision, dated, in one line with a link
  G3_PLAN.md      today's G3_WATER_PLAN.md
  G3_TODO.md      the water list only
  G4_TODO.md      G4.1-G4.14, and the energy items of OPERATIONAL_TODO
                  sections 2-7 with their IDs
  BACKLOG.md      open items beyond G4: M6-M8, upstream, CI; each with its ID,
                  milestone and source
  FINDINGS.md     condensed by topic, with dated errata and a table of
                  superseded and falsified claims. The numbering is kept, and
                  G3 continues at W15 for water and G4 at E77 for energy (E76 is the R2 ladder)
  RUNS.md         the run register: config, commit, worktree, purpose,
                  finding, and where its data lives (repo, scratch, archive)
  README.md       a short operator guide for terrabyte: manifest, verifier,
                  submitting, traps
  design/         live references: ATTRIBUTION_PATH, TRACER_AND_FLUX,
                  UPDRAFT_GAP, SUBGRID_AND_MICROPHYSICS_DESIGN
  reference/      the frozen external reviews: the pathway, the assessment
  review/         agent_reviews/, instructions, checks/, register/
  archive/2026-09-23/   every original, unchanged: the full OPERATIONAL_TODO,
                  LEARNINGS, NEXT_SESSION, LEVANTE_TASKS, TODO_REVIEW, the
                  finished designs (ENTHALPY_AUDIT_DESIGN,
                  RESTART_GUARD_DESIGN, C1_reference_shift), the drafts
                  (CLIMACORE_ISSUE_DRAFT, UPSTREAM_VWB_PR_DRAFT,
                  PARENT_BUDGET_DEFECT_PR, USER_GUIDE_DRAFT), this plan, and
                  FINDINGS and README as they were
  analysis/ configs/ output/ plots/ overrides/ runscripts/   unchanged
OPERATIONAL_TODO.md   a stub pointing to STATUS.md, so links keep working
```

**Content moves, nothing is lost:**
 - What only LEARNINGS holds moves into FINDINGS as short reasons.
 - USER_GUIDE_DRAFT is archived only after a check that #95's
   `energy_source_tags_guide.md` covers it (D1 with D3). What it does not cover
   goes to G4_TODO.
 - The two historical doc pages move into `archive/` once PR #97 has merged.

## Safeguards

 - Nothing is deleted. Every original goes, unchanged, to
   `archive/2026-09-23/`, and the archive tags hold the branches.
 - A committed measurement never changes. A correction is a dated erratum
   beside its entry. Output directories are not touched.
 - The register (H2) lists every claim, decision, open item, run directory and
   document. Each row must end with a home in the new structure, or in the
   archive with a pointer. The loss check (H5) runs until it finds no gap.
 - Checks only read. A check that would need a simulation goes on a list for
   G3 or G4.
 - Before a worktree is removed or scratch is cleaned, the archive is synced
   again (its README says how).
 - Out of scope: the code of #95 and of G3's PRs, and any running job.

## Steps

| Step | What | Who (model, effort) |
|:--|:--|:--|
| H1 | The job session writes its R2 entry, then stops editing the record documents until H6 merges. It moves to `claude/tag-closure-record`, where its later commits land. The owner relays this | job session |
| H2 | **The register**, in `review/register/`, one CSV each: claims (ID, document, the claim in a line, its numbers, its evidence, its status), decisions, open items, runs (directory, config, commit, where the data lives), and documents (kind, date, proposed home) | agent (Sonnet, medium) |
| H3 | **Re-check what G3 relies on**: W1–W14, E40, E44, E53, E55, E59, E64, E66, E73, E75. Each gets a verdict: recomputed, consistent, unverifiable, discrepant, stale or superseded. Report to `review/verify_g3.md` | agent (Sonnet, high) |
| H4 | **Write the new structure** on `claude/tag-closure-condense`, from the register and H3's verdicts. AGENTS.md's style; the main session adjudicates every discrepant or stale claim first | agent (Opus, high) |
| H5 | **The loss check**, by an agent that did not write: every register row has a home; every number is unchanged; every run directory is referenced; nothing new is claimed. Repeated until clean | agent (Opus, high) |
| H5b | **A collective review of H1 to H7**, added by the owner on 2026-09-23. The documents, the loss check, the register, the branches and tags, the archive, PRs #96 and #97, and H7's removals are reviewed together, before the owner sees the PR. Report to `review/agent_reviews/` | independent agent (Opus) |
| H6 | The owner reviews a PR of the condense branch into the record branch. The G3 branch is retired. The job session's commits since `eead88c3` are ported, since they touch only `experiments/` | this session, owner |
| H7 | The approved cleanup: worktrees (below), local branches, remote branches merged into `main`, `claude_work`, the memory files | this session, after approval |

The agent definitions in `~/.claude/agents/` load only when a session starts.
Until then the agents run as `general-purpose` with the model set, and their
effort is the default.

## H7, approved by the owner on 2026-09-23 and partly done

Done the same day:
 - The archive was synced again, and each worktree captured again (its
   untracked files and patch, checked by count and size). Then the 22
   worktrees marked "remove" below were removed. Seven remain: the main clone,
   `-exp`, `-upd`, `-upd-run`, `ClimaAtmos-upstream-d331fe3`, `-setup` and
   `-histdocs`.
 - Local branches deleted: 37 merged into `main`, `list`, and the four that
   are now tagged.
 - Remote branches deleted: the six merged into `main`. The earlier count of
   55 was mostly stale references to branches GitHub had already deleted on
   merge.
 - `tagged-tracers` held two commits found nowhere else (PR #31's merge and a
   test fix), and its branch was gone from origin. It is now tagged
   `archive/tagged-tracers`. The branch itself stays; it was not on the list.

Still to do, when their conditions are met:
 - `-upd` and `-upd-run`: after #95 merges.
 - `-setup` and `-histdocs`: after #96 and #97 merge.
 - The main clone moves to the record branch in H1.
 - Remote `claude/tag-closure-experiments` and `claude/g3-programme` are
   deleted at H6. Both are tagged.
 - `claude_work` is left alone while the job session uses it (its test
   environment and run scripts). It is in the archive.
 - Three local branches that were not on the list stay:
   `claude/review-open-prs-tasks-wxiw0k` (on origin),
   `claude/terrabyte-julia-setup` (nothing unique) and `tagged-tracers`
   (tagged).

## Worktrees and branches: the approved fates (H7)

Every worktree's commit is reachable from a branch or tag, and its local patch
and untracked files are in the archive. A worktree's removal keeps its branch.

| Worktree | Commit | Proposed | Why |
|:--|:--|:--|:--|
| `ClimaAtmosResiDyn.jl` (main clone) | old experiment branch | keep; switch to `claude/tag-closure-record` in H1 | the job session's |
| `-exp` | record branch | keep | this session's |
| `-upd`, `-upd-run` | #95 | keep until #95 merges | the job session's |
| `-setup`, `-histdocs` | #96, #97 | remove after they merge | |
| `ClimaAtmos-upstream-d331fe3` | upstream v0.42.11 | keep | parity reference for the next upstream merge |
| `ClimaAtmos-upstream-vwb` | decision 12's record | remove | tagged `archive/upstream-vwb-species-guard` |
| `-c1b`, `-c2`, `-inc`, `-rec`, `-localprefs`, `-pr88` | merged (#91, #92, #94, #93, #90, #89) | remove | in `main` |
| `-b1`, `-buildtime-edmf`, `-c1b-val`, `-c2-val`, `-c1c-base`, `-inc-run`, `-inc-run2`, `-inc-run3` | detached, in `main` | remove | runs done; logs and patches archived |
| `-c1c`, `-c1c-opt1`, `-c1c-opt2`, `-c1c-opt3` | shelved C1c | remove | tagged `archive/c1c-sgs-diffusion`; the option variants' uncommitted edits are in the archive as patches |
| `-m3` | species-list test | remove | the test is on `main`; tagged `archive/m3-species-lists` |
| `-p4` | `edd44e1d` | remove | reachable from the record branch |
| `-ci-review` | CI review branch | remove | the branch is on origin |

**Local branches to delete** (none holds a commit that only it has):
- `list`, an old pointer into `main`;
- the merged `claude/*` branches of the removed worktrees;
- `c1b-wip-backup`, `claude/energy-source-tag-sgs-diffusion`,
  `claude/energy-source-tag-species-lists` and `upstream-vwb-species-guard`,
  all four now tagged.

**Remote branches:** 55 `claude/*` branches on origin are merged into `main`.
Delete them; their PRs keep the history. The 16 unmerged ones stay until
reviewed one by one.

## Numbering from here on

G3's findings continue as W15, W16, … in the water section. G4's continue as
E77, E78, …, since E76 went to the R2 ladder on 2026-09-23. A finding that concerns both families is filed where its
measurement was made, with a pointer from the other section.
