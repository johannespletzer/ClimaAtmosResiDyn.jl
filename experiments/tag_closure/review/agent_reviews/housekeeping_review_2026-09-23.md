# H5b: a collective review of the housekeeping, H0 to H7

Step H5b of [CONDENSE_PLAN.md](../../CONDENSE_PLAN.md), added by the owner on
2026-09-23. An independent agent that wrote none of H0 to H7 reviewed all of
it together, before the owner's review of the condense PR (H6). Written on
2026-09-23, between 12:25 and 12:45 CEST.

The state reviewed, after `git fetch origin`:

| Ref | Commit |
|:--|:--|
| `origin/claude/tag-closure-condense` | `68b60a62` |
| `origin/claude/tag-closure-record` | `eec7f363` |
| `origin/main` | `3ecb6d25` (#96 merged at 12:12, #97 at 12:12) |
| `origin/claude/energy-source-tag-updraft` (#95) | `afd470e7` (moved at 12:31) |
| `origin/claude/tag-closure-experiments` | `8726d2cb` |
| `origin/claude/g3-programme` | `a52b17f7` |

Everything below was checked by a command, not read from a claim. Where a
check was not possible, the last section says so.

## Verdict

**Sound with notes. No finding blocks H6.** Nothing in git is lost. The
condensed documents are complete, the originals are archived byte for byte,
the errata are right, and the condense branch fast-forwards onto the record
branch. But the world moved while the documents were being finished. #96 and
#97 merged at 12:12, and #95 moved at 12:31. So STATUS and three other files
are stale on the PRs, and the record branch is now behind `main` outside
`experiments/`.

Two things went wrong in H7, both small:
- The worktree capture skipped git-ignored files. The 34 Slurm `.out` logs of
  the removed worktrees were deleted without a copy, while the archive's
  README says it holds them.
- H7 deleted 30 local branches that the approved list did not name. Every one
  was merged into `main`, so nothing is lost. But the record does not say that
  the list was exceeded.

Fix S1 and S5 before the owner opens H6, and S2 at H6. Fix S3 before the next
worktree is removed.

## The eight areas

| # | Area | Verdict | Findings |
|:--|:--|:--|:--|
| 1 | The documents | sound with notes | S1, S6, N5, N6, N9, N10 |
| 2 | Nothing lost (the loss check, spot-checked) | sound | N8 |
| 3 | Branches and tags | sound with notes | S2, S5 |
| 4 | The archive directory | problem, small in impact | S3, N4 |
| 5 | PRs #96 and #97 | sound | N3, N7 |
| 6 | H7's cleanup | problem, small in impact; nothing in git lost | S3, S4, N1, N2 |
| 7 | H1 | sound | none |
| 8 | Readiness for G3 | sound with notes | S7, N11 |

What each area passed:

1. **Documents.** Every file of the target structure exists: STATUS, ROADMAP,
   DECISIONS, G3_PLAN, G3_TODO, G4_TODO, BACKLOG, FINDINGS, RUNS, README,
   `design/` (4), `reference/` (2), `archive/2026-09-23/` (14 originals and
   INDEX) and the OPERATIONAL_TODO stub. CONDENSE_PLAN stays live until the
   plan is done, as it says. 260 relative links in the live `.md` files
   resolve, anchors included. The one miss is a Documenter `(@ref)` inside a
   quoted review, which is not a link. Numbering agrees everywhere: W15 on,
   E77 on, E76 the R2 ladder (FINDINGS:31-32, README:182-183,
   CONDENSE_PLAN:73 and 195-196). The open decisions agree between STATUS,
   G3_TODO, DECISIONS and G3_PLAN 6.1. The goals agree. The style is simple
   and readable.
2. **Nothing lost.** See "The spot check" below: 30 register rows and 21
   archived paragraphs, all with a home. The four errata are right. E76 keeps
   every number. The 14 archived files are byte-identical to `eec7f363`.
3. **Branches and tags.** Against `main` as the record branch was built on
   (`c99ff7bd`), the record differs outside `experiments/` in exactly the
   three files. `git merge-tree --write-tree` of record and condense is clean
   (`f70ad255`), and record is an ancestor of condense, so H6 is a
   fast-forward. All seven archive tags are on origin (`git ls-remote`) and
   point where their messages and CONDENSE_PLAN say: `eead88c3`, `2d7fa835`,
   and the four former local branches and `tagged-tracers` at their tips. E76
   on the record (`eec7f363`) is a cherry-pick of `8726d2cb` with an identical
   patch; only the hunk offset differs.
4. **Archive.** `sha256sum -c SHA256SUMS --quiet` passes on all 5,434 files.
   `rsync -an --delete --itemize-changes`, also with `-c`, shows no difference
   between `$SCRATCH/tag_closure/` and `scratch_tag_closure/` (2,697 files
   each). All 22 removed worktrees have `HEAD.txt`, and each commit in them is
   reachable from a branch or tag. The workspace `AGENTS.md` records the
   exception (lines 67-71).
5. **PRs.** #96 is exactly the terrabyte setup. Both scripts have the same
   blobs as the archive tag's (`a3db7de2`, `f2259f80`). `runscripts/README.md`,
   `AGENTS.md` and `.gitignore` are the tag's versions. `clima_atmos_specific.md`
   is `main`'s, with only the `runscripts/` paragraph changed. #97 is exactly
   the two "Historical" banners, 17 added lines. Both merged.
6. **H7.** The eight worktrees now present are the seven listed plus
   `-condense`. The heads of all 36 PRs behind the deleted merged branches are
   ancestors of `origin/main`. The four tagged branches were deleted only
   where `git tag --points-at` found their tag. The six deleted remote
   branches were merged. The main clone, `-upd`, `-upd-run`,
   `$SCRATCH/claude_work` and the scratch depot all exist, and the job session
   is still writing to `claude_work/upd_run/` (12:23).
7. **H1.** The main clone is on `claude/tag-closure-record` at `eec7f363`. Its
   reflog shows the E76 commit at 11:24 and the checkout to the record branch
   at 11:28. The old experiment branch is at `8726d2cb` locally and on origin,
   so nothing was committed there after E76. The main clone and `-upd` have no
   uncommitted changes.
8. **Readiness.** G3 can start WP0 except its first item, "#95 merged". The
   plan is final and reviewed. The criteria are in G3_PLAN 2 and G3_TODO. The
   open decisions are listed in one place each. Results go to FINDINGS W15 on
   and RUNS.md on the record branch, and model code to `claude/water-tags-edmf`,
   which does not exist yet. The standing approval covers G3's jobs. The
   budgets of 6.1 are needed before V-W3, not before WP0.

## Findings

### Blocking

None.

### Should fix

**S1. STATUS and four other files are stale on the PRs.** The owner merged #96
and #97 at 12:12 CEST (merge commits `3ecb6d25`, `b1a088a4`). That was before
the last fix commit, `68b60a62` at 12:23. #95 moved from `cd21af3a` to
`afd470e7` at 12:31.
- STATUS, "Pull requests": #96 and #97 "draft"; #95 "at `cd21af3a` ... CI
  started there at 11:30 and was still running at 12:20". In fact every CI
  run at `dcf7d086`, `2044350e` and `cd21af3a` was cancelled when the next
  push superseded it (`gh run list`). The run at `afd470e7` is queued. So no
  CI has completed on #95 since the partition-only factor.
- `afd470e7` changes only `NEWS.md` and two tests. `src/` and `config/` are
  unchanged since `dcf7d086` (`git diff --stat`), so E76 still describes the
  head.
- STATUS, H7 row, and CONDENSE_PLAN, "Still to do": `-setup` and `-histdocs`
  wait "for #96 and #97". They are now due.
- DECISIONS.md, 2026-09-23: "#96 is a draft".
- README.md, Setup: "The script is on this branch and in PR #96". It is on
  `main` now.
- `archive/2026-09-23/INDEX.md`: the two doc pages move "once #97 has merged".
  That condition is met (see N7 for how).

*Fix:* update these lines before H6. Give #95's head as `afd470e7`, with
model code as at `dcf7d086`, and say that no CI has completed there yet.

**S2. The record branch is now behind `main` outside `experiments/`.** With
#96 and #97 merged, `git diff origin/main origin/claude/tag-closure-record --
. ':(exclude)experiments'` lists 7 files. Six are #96's and #97's edits, which
the record lacks: `.gitignore`, `AGENTS.md`, `docs/clima_atmos_specific.md`,
`runscripts/README.md` and the two doc pages. The seventh is the C1 TOML. The
two terrabyte scripts are now identical on both. `git merge-tree
--write-tree origin/claude/tag-closure-condense origin/main` is clean
(`c9607f5a`), and afterwards only `toml/tag_closure_c1_reference.toml`
differs from `main`.

*Fix:* at H6, after the fast-forward, merge `origin/main` into the record
branch. Then change "except three files" to "except the C1 TOML" in
CONDENSE_PLAN, STATUS and the memory note.

**S3. The worktree capture skipped git-ignored files. 34 Slurm `.out` logs
were deleted without a copy, and the archive's README says it holds them.**
- The capture command in the archive README is `git ls-files --others
  --exclude-standard`, which leaves out ignored files. The root `.gitignore`
  ignores `*.out` and `*.log`. The runscripts write `tag-closure-c-%j.out`
  into the worktree root.
- `worktrees/*/untracked/` holds 94 `.err` files and no `.out` or `.log`.
  The live `-upd-run` has a `.out` beside each of its 30 `.err`. One of them,
  `tag-closure-c-13761738.out`, is 1,470 bytes: the run, config, commit,
  node, modules, start time, the driver's exit status and the end time.
- The 10 removed worktrees with job logs held 34 `.err`, so 34 `.out` went
  with `git worktree remove --force`. 33 of those jobs have a
  `provenance.txt` in scratch and in the archive, which repeats most of the
  header. The 34th, `13505763` (`g2_v2_diag_newton2`, cancelled at its time
  limit), has no provenance. Only its `.err` survives, in
  `worktrees/ClimaAtmosResiDyn-inc-run3/untracked/`.
- The archive README, and RUNS.md under "Where the data lives", say
  `untracked/` holds "job `.out` and `.err` logs". That is wrong for `.out`.
- Also not in the archive, and only in live worktrees:
  - `-upd-run`'s 30 `.out` files;
  - the main clone's 16 ignored `.out` files under
    `experiments/tag_closure/output/` (Levante phase A, for example
    `a1_dt10/tag-closure-a-27360071.out`);
  - six ignored logs under `review/agent_reviews/updraft_gap_bound/`, in both
    the main clone and `-upd-run`.
- `-upd-run` was captured at 08:45Z, while the reruns were still going. They
  ended at 09:05Z. So the archive's `.err` files for jobs `13782601` to
  `13782605` are partial (`cmp` differs for all five).

*Fix:*
- Correct the archive README and RUNS.md: `.err` logs were captured; the
  `.out` logs of the removed worktrees were not, and `provenance.txt` repeats
  their header.
- Add ignored files to the capture, minus build products. For example, also
  pipe `git ls-files --others --ignored --exclude-standard | grep -v -E
  'Manifest|LocalPreferences|docs/build|__pycache__|test/output|^output/'`
  into the same `rsync`.
- Capture `-upd-run` and the main clone again before either is removed or
  cleaned.
- Record the 34 lost `.out` files in CONDENSE_PLAN's H7 section.

**S4. H7 deleted 30 local branches that the approved list did not name, and
the record does not say so.**
- The list the owner approved at 08:55Z ("I approve H7", against the plan at
  `746f33ac`) names `list`, "the merged `claude/*` branches of the removed
  worktrees", and four tagged branches.
- The command that ran deleted every local branch that is an ancestor of
  `origin/main` and not checked out: 37 branches (this session's transcript,
  "merged to delete: 37").
- Six of the 37 belonged to removed worktrees: `edmf-sharing`,
  `restart-guard`, `implicit-increment`, `process-records-not-advected`,
  `untrack-local-preferences` and `merge-upstream-v0.42.11`. One was `list`.
- The other 30 had no worktree: `claude/parent-budget-2-journal` to
  `-8-report`, `claude/ci-*`, `claude/energy-source-tag-offset` and the like,
  and `passive-tracers`, which is not a `claude/*` branch at all.
- Nothing is lost. The head of every PR behind these names is an ancestor of
  `origin/main` (36 checked with `git merge-base --is-ancestor`). `list`
  pointed at `e63ad194`, which is in `main` too.
- CONDENSE_PLAN says "37 merged into `main`", which is true, but not that this
  was wider than the approved wording.

*Fix:* one sentence in CONDENSE_PLAN's H7 section: the rule applied was
"every local branch merged into `main`". Ask the owner to confirm it after the
fact.

**S5. H6 is to delete the two old remote branches, "both tagged". The tags
stop one commit short, so the deletion would orphan their tips.**
- `claude/tag-closure-experiments` is at `8726d2cb` (E76). Its tag is at
  `eead88c3`, the parent.
- `claude/g3-programme` is at `a52b17f7` (the removal of the #95
  instruction). Its tag is at `2d7fa835`, the parent.
- `git for-each-ref --contains` finds each tip only on its own local and
  remote branch. Neither branch has a PR, so GitHub keeps no `refs/pull` copy.
- The content is ported. The E76 patch is identical in `eec7f363`, and the
  condense branch removes the file too. So this is about citations, not
  content.
- The live documents cite both hashes: STATUS (`8726d2cb`); `a52b17f7` in
  G3_TODO:73, G3_PLAN:26-27 and DECISIONS; G4_TODO:184.

*Fix:* before H6 deletes the branches, tag both tips, for example
`archive/tag-closure-experiments-final` and `archive/g3-programme-final`.
Tags are pushes, so this needs the owner's approval. The alternative is to
cite `eec7f363` and the condense commit instead, and drop "Both are tagged".
Also decide the fate of the two local branches, which the plan does not
mention.

**S6. ROADMAP, G4_TODO and FINDINGS contradict STATUS on #95, the R2 ladder
and G3.**
- ROADMAP, M1 row: "the partition-only factor sent to the job session". STATUS
  says #95 carries it at `dcf7d086`.
- ROADMAP, M3 row: "the R2 ladder is running in the job session". The last
  paragraph: "The job session continues the energy work in flight: #95 and
  the R2 ladder". E76 has recorded the ladder, and only its rerun at #95's
  merged head is left (G4_TODO, G4.7).
- G4_TODO:4-5: "except where the job session runs energy work now: PR #95 and
  the R2 ladder".
- FINDINGS:15-16: "G3 ... is under way". STATUS: "G3 has not started
  running".

ROADMAP says "Only its pointers were changed", which kept stale state in a
live file.

*Fix:* update these cells and sentences, and drop "Only its pointers were
changed" from ROADMAP.

**S7. The memory notes will be wrong after the merge.** They live outside the
repository, in
`~/.claude/projects/-dss-dsshome1-0D-di38kez-git-Clima-ClimaAtmosResiDyn-jl/memory/`.
This session edits them in H7.
- `housekeeping-2026-09-23.md`:
  - "E76 onward for energy (G4)" should read E77. As written, a later session
    could give a G4 finding the number E76 a second time.
  - "Draft PRs: #96, #97": both merged.
  - "Outside `experiments/` it equals `main`, except the C1 TOML and the two
    terrabyte scripts": after S2, only the TOML.
  - "Seven remain": eight, with `-condense`.
  - The old branches are "frozen as the tags": the tags stop one commit short
    (S5).
- `programme-after-g2.md`, and its line in MEMORY.md:
  - the plan is `G3_WATER_PLAN.md`: it is now `G3_PLAN.md`;
  - "branch `claude/g3-programme`", "(worktree `ClimaAtmosResiDyn-exp`,
    pushed)" and "Merge it into `claude/tag-closure-experiments` at gates":
    that branch is retired, and the record branch is `claude/tag-closure-record`;
  - "The roadmap in OPERATIONAL_TODO": now ROADMAP.md;
  - `experiments/tag_closure/repo-operability-pathway.md`: now under
    `reference/`;
  - R1's θ question is "awaiting the owner": it was decided and built at
    `dcf7d086`.
- `goal-g1-g2.md`:
  - G1 and G2 are "defined at the top of `OPERATIONAL_TODO.md` on branch
    `claude/tag-closure-experiments`": now
    `archive/2026-09-23/OPERATIONAL_TODO.md`, and FINDINGS;
  - "Read section 0 and 'The current goal' of `OPERATIONAL_TODO.md` first":
    read STATUS.md first;
  - "push the experiment branch after each step": the record branch;
  - the worktree `../ClimaAtmosResiDyn-inc` was removed in H7.
- These three are still correct:
  - `scratch-testenv-depot.md`: `inc_testenv` and
    `inc_run/integration_job.sh` exist;
  - `mpi-runs-terrabyte.md`;
  - `gh-upstream-remote-default.md`: `remote.origin.gh-resolved` is `base`.

*Fix:* rewrite the three notes in H7, after H6.

### Notes

**N1. `-condense` is on no list.** The worktree and the remote branch
`claude/tag-closure-condense` were made for H4, after H7 ran. Add both to
H7's "after H6" items.

**N2. H7 pruned stale remote-tracking refs, including unmerged ones, without
the one-by-one review the plan promised.**
- The plan said "The 16 unmerged ones stay until reviewed one by one". H7's
  remote step began with `git fetch --prune`. Afterwards 7 unmerged remote
  `claude/*` branches were left. The other 9 had been deleted on GitHub
  earlier, and the prune dropped their last local refs. Only `tagged-tracers`
  was caught, because a local branch with that name existed.
- `git fsck --unreachable --no-reflogs` now finds 57 dangling commits. Three
  are the heads of closed PRs #23, #39 and #45, which GitHub keeps under
  `refs/pull`. Most of the rest are old stashes, "tmp" check commits,
  Documenter builds and amended or rebased versions.
- 18 have a patch-id found on no ref. Examples: `f95d4ed9` "Add V5's restart
  pair and a Float32 D4 run", `7b600ada`, `e4956939`, `e7b3d386` and
  `b46cf223`.
- Which of them the prune orphaned cannot be reconstructed, since no list
  survives. Most are older than two weeks, so the next `git gc` may drop
  them.

*Suggestion:* put a `git bundle` of the dangling tips into the archive. It is
cheap, and the owner decides.

**N3. #96 and #97 merged with `ci-required` failing.** Each shows 14
cancelled checks, 23 successes and no failing test job (`gh pr view
--json statusCheckRollup`). `main`'s CI at `b1a088a4` and `3ecb6d25` was
cancelled too, so no complete CI has run on `main` since the merges. The risk
is low, since both PRs touch docs and scripts only. The token cannot rerun
Actions runs. The owner can.

**N4. Smaller inaccuracies in the archive's README.**
- Its capture recipe writes no `branch:` line, but it says `HEAD.txt` "gives
  the commit and branch". The existing files do have the line.
- It points to "RUNS.md on `claude/tag-closure-record`". That holds only after
  H6.
- "Last synced ... after the day's reruns had finished" is true for scratch.
  It is not true for the kept worktrees' captures (S3).
- `scratch_claude_work/` trails the live `claude_work` by 2 logs and a
  deleted temporary directory. That is expected while the job session uses
  it.

**N5. STATUS's H5 row says too much.** "Its 2 blocking and 21 minor gaps are
fixed and re-verified": four minors (m7, m14, m15, m16) were accepted, not
fixed. The last fixes, `68b60a62`, were not re-verified by the loss-check
agent. This review checked them: n1, n2 (16,752,519 KiB is 17.15 GB), n3,
m13 and m15 hold.

**N6. Style.** The documents are written in short, plain sentences.
- Some sentences were inserted by search and replace and never re-wrapped.
  They run past 90 columns: G3_PLAN:26-27 and 485, G3_TODO:73, DECISIONS:76,
  FINDINGS:11 and 32, CONDENSE_PLAN:73 and 196, INDEX:12, README:196.
- RUNS.md's row for the OOM run says "Killed for memory" twice.

**N7. Moving the historical doc pages needs a PR to `main`.** `main`'s
`docs/make.jl:130-131` lists both pages. So "move to the archive later" means
a PR that removes the pages and edits `make.jl`, merged by the owner. It is
not an edit on the record branch, which must stay equal to `main` outside
`experiments/`.

**N8. Two details of E76's provenance line, inherited unchanged from the
original.**
- "`13768363` to `13768369` (the copies runs at `dbe7435c`)": that range also
  holds the superseded default runs `13768364`, `13768366` and `13768368`
  (`sacct`). The copies runs are the odd IDs.
- "`output/v3_upd_default*`": the repository holds only E73's
  `v3_upd_default` and `v3_upd_copies`. The ladder's tables are on scratch,
  which STATUS says.

For G4's re-check. This is not a condensing defect.

**N9. Some scratch directories are not in RUNS.md.** These are in the archive,
but RUNS.md does not describe them, and the originals did not either:
- `logs/` (28 MB, 105 files);
- `newton_lag_slurm/`, `p4_fix/`, `p4_profile/`, `p4_stages/`,
  `p4_stages_smoke/` and `smoke/`;
- `output/dryrun/`, which holds one `provenance.txt`.

A line in RUNS.md would finish the map.

**N10. BACKLOG and ROADMAP disagree on `phase_c.jl`.** BACKLOG lists it as
open, and ROADMAP counts it done. BACKLOG says so itself. It could be struck.

**N11. Readiness: where G3's runs launch from is not stated.** G3_TODO says
this session runs G3 from `-exp`. `-exp` is on the record branch, which has no
#95 code. V-W1 needs `main` with #95, and `-upd-run` is the job session's.
State which worktree G3's runs use once #95 merges.

## The spot check (area 2)

**Register rows, 30.** They were drawn at random with a fixed seed, plus the
decisions checked by reading.
- *Claims (10):* E66, E44b, E52, E72, E44, R10, `LEARNINGS:A3:1`, E36, W6
  and W8. Each has its entry in FINDINGS. Every number in the register's
  `numbers` column is in the entry (script, commas and signs normalised).
- *Decisions (6):* the `gh` default (2026-09-16), the exchange's face scheme
  (2026-09-20), "G3 water, G4 energy" (2026-09-23), the standing G1/G2 goal
  (2026-09-19), P6 skipped (2026-09-14) and "one moist model: no"
  (2026-09-18). All six are in DECISIONS.md under their dates.
- *Items (8):* these have their homes:
  - `G4.1`: G4_TODO;
  - `FQ-3` and `FQ-13`: BACKLOG;
  - `OT-B8`: BACKLOG, M6;
  - `OT-SYN2`: G4_TODO, and G3_TODO WP0 by content;
  - `G3-WP3-6`: G3_TODO WP3, "Bound activation ...".
  - `OT-T4` and `OT-S-C5` are done, with target "archive", and are there.
- *Runs (6):* `climacore_nameset_repro`, `a1_dt10`, `twin_c1_limiter_off`,
  `c1c_opt1_d4_enthalpy`, `g2_v2_sphere_newton10` and `p4_edmf_tags`. Each
  has its RUNS.md row, and the job ID matches.
- *Every scratch run directory:* all 81 under `output/` appear in RUNS.md,
  except `dryrun` (N9). So do all 107 directories under `output/` in the
  repository.

**Archived paragraphs, 21.** These are from the archived OPERATIONAL_TODO,
sections 4 to 6, and LEVANTE_TASKS. None was in H5's sample.
- *Live:*
  - ClimaCore field-name sets (E44d) in BACKLOG;
  - A4's acceptance, "5 J/kg", and A5, the overlay-bound diagnostic, in
    G4_TODO;
  - P5's 22,576 and 58,160 bytes in BACKLOG;
  - A3's acceptance, 1.2e-3, in G4_TODO;
  - C1d in BACKLOG;
  - C6's `isfinite` leftovers, C7 and A6 in G4_TODO;
  - U7 in BACKLOG;
  - U9's `abort_above` in G4_TODO;
  - R5 in G3_TODO V-W4;
  - "the sphere's remaining 17%" in G4.6;
  - D1's pressure-work candidate in G4_TODO;
  - E14, E16 and E24 in BACKLOG;
  - C1's reference shift in FINDINGS E11 to E16;
  - `phase_c.jl` in BACKLOG.
- *In the archive, with a pointer by ID from a live file:*
  - P6's "14 files in `src/`" (BACKLOG P6 → OT section 4);
  - P3's `energy_source_tags.jl:148` (G3_TODO WP9);
  - U8's floor temperatures, 228, 215 and 187 K, and "150 kJ/kg keeps dry air
    positive to 173 K" (G4.10 → OT section 4, with 228 K quoted live).
- *Done, and kept in the archive:* LEVANTE_TASKS' fixed validator defects
  (ISDAC).

**Errata.** All four are present and right. Each was checked against its
source:
- **E73:** `output/v3_upd_default/run.log:104` says 600.291 s, and
  `v3_upd_copies/run.log:105` says 3504.054 s. The smoke test `13519152` in
  `claude_work/upd_run/` gives 401.954 s and 788.947 s. §12 keeps the old
  claim.
- **E75:** `output/g2_v2_sphere_mix/tags_vs_no_mixing.txt:4` gives `rad` L1
  at 1 h as 1.08e-03. §12 keeps 0.15%.
- **W7:** at `49b2ec97`, `rescale_water_tags!` sits at lines 695-741. On
  `main` its docstring sits at lines 784-825.
- **E50:** the dated erratum is at FINDINGS:1092-1094. It gives 2026-09-17 →
  2026-09-18 and its source.

**E76.** The condensed entry has the same table. It keeps every number of
the original's bullets: 1.6%, 2.6%, 1.54%, 2.51%, 14.3% to 21.3%, 0.64% to
0.88%, 0.91% to 1.13%, 6.5%, 1.89% to 0.13%, 1.73% to 0.12%, and 0.5% to 1%.
The jobs and commits are the same. Dropped:
- the date of the owner's choice of the face scheme, 2026-09-20, which
  DECISIONS keeps;
- "a factor of fourteen";
- the reason the copies runs are unaffected.

**Archive files.** All 14 files in `archive/2026-09-23/` other than INDEX
have the same blob as `eec7f363:experiments/tag_closure/<name>`. That includes
FINDINGS.md, which is `eec7f363`'s, with E76. The committed and on-disk
versions agree.

## Open ends, and who acts

| When | What | Who |
|:--|:--|:--|
| before H6 | S1: refresh STATUS, DECISIONS, README, CONDENSE_PLAN and INDEX for #96 and #97 merged and #95 at `afd470e7` | this session |
| before H6 | S5: propose tags at `8726d2cb` and `a52b17f7`, or reword the citations | this session proposes, the owner approves the push |
| before H6 | S6: ROADMAP's M1 and M3 cells and its last paragraph, G4_TODO's opening, FINDINGS' "under way" | this session |
| before H6 | S4: record that H7's branch rule was wider than the list | this session writes it, the owner confirms |
| before H6 | S3: correct the archive README and RUNS.md on `.out`; fix the capture command | this session |
| at H6 | review and merge the condense PR, a fast-forward | the owner |
| at H6 | S2: merge `origin/main` into the record branch | this session, after the owner's merge |
| at H6 | delete remote `claude/tag-closure-experiments` and `claude/g3-programme`, after S5; decide the two local branches | this session, on the approved list |
| after H6 | H7, now due: remove `-setup` and `-histdocs`; delete `claude/terrabyte-setup` and `claude/historical-tag-closure-pages`, local and remote (merged, so in the approved class) | this session |
| after H6 | remove `-condense` and remote `claude/tag-closure-condense` (N1); archive CONDENSE_PLAN.md when the plan is done | this session, the owner approves the addition |
| after H6 | S7: rewrite the three memory notes | this session |
| after H6 | N7: a PR to `main` that moves the two historical doc pages and edits `docs/make.jl` | this session drafts, the owner merges |
| after #95 merges | re-capture `-upd-run` with ignored files, then remove `-upd` and `-upd-run` | this session; the job session hands them over |
| after #95 merges | the R2 ladder at the merged head (G4.7); E76's small tables into `output/` | the job session |
| when the job session stops using it | re-sync `claude_work`, then decide its fate | the job session tells the owner; this session syncs |
| any time | N2: bundle the dangling commits into the archive, or not | the owner decides |
| any time | N3: rerun `main`'s CI at `3ecb6d25` | the owner (the token cannot) |
| now | merge #95. Its CI at `afd470e7` is queued, and none has completed since `dcf7d086` | the owner |
| before V-W3 / V-W11 | the budgets of G3_PLAN 6.1, and the sphere's | the owner |
| as they arise | ERA5 for V-W8; the archive for minimal datasets; WP5's default; the rain and snow fields after WP4b-D | the owner |
| start of G4 | the 11 conflicts marked H4-B in `conflicts.csv`, and the full re-check | the G4 session |

## What I could not check

- **What else the removed worktrees held that git ignores.** The directories
  are gone. Besides the 34 `.out` files, anything under a root `output/`, and
  any `*.log`, `*.json`, `*.png` or `*.nc` outside `experiments/`, would have
  gone uncaptured.
- **Whether the removed worktrees had uncommitted edits beyond the captured
  patches.** Only the captures remain. The 22 captures are stamped "final,
  before removal", 08:56Z.
- **Which remote-tracking refs H7's prune removed** (N2). Their reflogs went
  with them, and no listing was printed.
- **The owner's approval, beyond "I approve H7."** The scope in S4 is read
  from the plan text at `746f33ac`.
- **Anchors on GitHub.** The link check uses GitHub's slug rules as
  reimplemented here, not rendered pages.
- **The findings themselves.** Only E76 and the four errata were checked
  against their sources. H3 covered G3's claims, and the rest waits for G4.
- **#95's guide against USER_GUIDE_DRAFT** (the G4.1 list) was not re-checked.
- **LEARNINGS in full.**

## Method and write discipline

- The commands used were `git` (`fetch`, `ls-remote`, `diff`, `merge-tree
  --write-tree`, `merge-base`, `for-each-ref --contains`, `fsck --unreachable
  --no-reflogs`, `patch-id`), `gh ... pr view`, `gh run list`, `gh run view`,
  `squeue`, `sacct`, `sha256sum -c`, `rsync -an` and `cmp`.
- Small Python scripts with `python/3.12` checked the links, sampled the
  register and parsed the session transcript for H7's commands and output.
- Nothing was committed, pushed, merged or submitted.
- This file is the only one written in the repository. Temporary lists went
  to the session's scratchpad. One command wrote a file to `/tmp` and
  removed it in the same call.
