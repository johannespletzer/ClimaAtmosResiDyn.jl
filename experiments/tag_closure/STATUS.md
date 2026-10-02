# Status

The entry point for every session. Written on 2026-09-23 around 11:30, during
the housekeeping (step H4). Updated at 13:55 the same day, when the
housekeeping was done, at 16:45 after #95 merged, and at 18:15 with WP0
done, and on 2026-09-24 at 09:30 (the catch-up the owner asked for), 12:40 and
20:00 (rev. 2 of the work plan, steps 0 and 1), 21:10 (the owner's answers
to the register) and later that evening (OD3 approved; known issue 7's option
A; step 2 pre-registered), on 2026-09-25 (the owner's answers of that day), on
2026-09-26 (the provenance pathway, proposed), on 2026-09-27 (PT15, PT16,
PX25 and OD15 added to it, proposed), and on 2026-09-28 (the PRs merged
that week, the work of 2026-09-27 that was never pushed, the housekeeping).
Update it when something here changes,
and at each milestone of a work package and at each goal's end. The checklist
for those moments is in [README.md](README.md), "Closing a work package or a
goal". Where a fact was
not checked, it says so.

## The goals

  - **G1, a closed and explained EDMF column: met on 2026-09-20.** The energy
    source tags on D4 under the increment prototype (FINDINGS E62 to E66, E73).
  - **G2, the sphere: met on 2026-09-22.** Ten days of the production physics
    in Float32 (E74, E75).
  - **G3, the current goal: the water tags under prognostic EDMF**, with
    precipitation provenance: rain and snow carry their own tags. The exchange
    is the default and updraft copies are the audit, where they are eligible.
    Plan: [G3_PLAN.md](G3_PLAN.md). To-do list and criteria:
    [G3_TODO.md](G3_TODO.md). The owner approved every job within G3, and its
    agents. GPU is outside G3.
      + *Where G3 stands, rev. 2 (2026-09-24).* The goal is operation in the
        production configuration (a sphere with EDMF and 1M), but only under
        the contract's verdicts ([ROADMAP.md](ROADMAP.md), "The acceptance
        contract"). Baseline D4-W and TRMM pass parent parity and partition
        closure under the follower, the default under EDMF (W24, W26, W28,
        W31, W33). D4-W's provenance is *not assessable*: the copies fail
        their own repair criterion there, 0.60% of the water a day against
        0.20% (W21). Other baseline cases get a provenance verdict only where
        the comparator passes eligibility in that run.
      + *Open:* resolution and reconstruction support (W25); the explicit-1M
        default (W33 failed; the same-atmosphere check passed, W35; the owner
        decides whether W33's verdict changes); the copies' qualification
        (WP5b-C); intervention metrics (WP6 step 3, built, not yet validated
        by the integration tests); the rain and snow fields (WP4b); cost at
        the intended tag count (WP9, OD8); the sphere (OD6).
  - **G4 status, rev. 2 (2026-09-24).** Energy is merged (#95), and its use
    is conditional.
      + `enthalpy_increment` with 1M stepped explicitly is refused on
        `claude/energy-explicit-1m-guard` (`33eeb5cd`, not yet a PR) until
        G4.16 passes, with the opt-in key
        `energy_source_tag_increment_allow_explicit_1m` (a proposed name) for
        development runs. `main` still runs it (E80). *Superseded
        2026-09-24, 21:10:* the guard covers 1M, 2M and P3 stepped explicitly
        (`e55ae293`), and the proposed key is now
        `energy_source_tag_increment_allow_explicit_microphysics`.
      + The energy copies lack the mseʲ mirrors (G4.1, G4.11). So the
        default-against-copies gaps of E76, and of E73 at the baseline, are
        not provenance verdicts: the comparator is not eligible. E39 is a
        closure result against the Newton count, not a default-against-copies
        gap.
      + Energy percentages await restatement against an offset-invariant
        scale (OD4).
      + The sphere: the one-Newton parent is not valid (E69); with two
        iterations the residual still grows at day ten, though more slowly
        (E70, E74); the long-run criterion waits on OD6.
  - **G4, next: the energy source tags**, with what G3 learns:
    [G4_TODO.md](G4_TODO.md). The full re-check of the findings happens at its
    start.
  - **What upstream must change** for the tags, since the fork cannot:
    [UPSTREAM_REQUIREMENTS.md](UPSTREAM_REQUIREMENTS.md), started on
    2026-09-23 with the 0M rain-out's Jacobian diagonal (UP1).
  - **Later, sketched and not approved:** M6 (devices, precision, input data
    and restarts at scale, with the GPU decision), M7 (a production trial and a
    supported envelope), M8 (air age, memory and forecasts). Each needs the
    owner. See [ROADMAP.md](ROADMAP.md) and [BACKLOG.md](BACKLOG.md).

## Where things stand

  - **Update, 2026-10-02: WP9's cost measured on the new physics.** Drafts
    of W52 and E88 are on `claude/rec-wp9`, waiting for the Opus review
    before the merge into `plan-rev2`. Every arm ran with its own untagged
    baseline on the same exclusive node, and the first timed block was
    discarded (`design/WP9_COST.md` sections 10 and 11, at `b34bbd8b` and
    `d3c5e42f`). Every point quoted passes the 10% spread rule. The default
    mode costs 1.43× at 8 water tags (TRMM), 1.58× at 8 energy tags (D4) and
    4.16× at 8 + 8 on D4, 9.10× with ledgers. The two families do not add:
    alone on D4 they cost 1.44× and 1.53×. **The 8 + 8 step time exceeds
    OD3's ceiling of 2×, approved 2026-09-24.** Unless the owner revises that
    row, criterion 10 fails. A budget is proposed in G3_TODO (WP9) and waits
    for the owner.

  - **The session goal of 2026-09-28** (the owner). It is met when:

     1. the extended probe of section 9.7 has run and is scored and
        recorded as W48;
     2. the owner has a decision brief on C's revision, drawn from W47 and
        W48, with options and a recommendation;
     3. two PRs against `main` are open, with the #119 and the #121
        follow-ups from the backups, and both pass the tests locally and in
        CI.

    WP4a-J, W21's surface flux and the walk-throughs come later.

  - **Update, 2026-09-28: PRs merged, unpushed work found, housekeeping.**
    Written by the session that reviewed #125. `main` was at `cfc2152c`,
    and is at `d2f119ab` since #126 merged that evening.

      + *Merged into `main` since 2026-09-26:* #104, #107, #109, #111 to
        #121, #124 and #125 (the table under "Pull requests"). #122 merged
        into this branch on 2026-09-27. #126 merged later that day. Open:
        #123 (draft).
      + *#126, merged 2026-09-28 (`d2f119ab`).* #118 called the parent's own negative-water total "the
        ledger", against #125's rule: budget is the parent's, ledger is a
        tag's, record is a process's. #126 renamed it "accumulator", the
        owner's choice. The checkpoint keys stay as they are.
      + *Work of 2026-09-27 that was never pushed.* Three worktrees held
        commits or edits that no remote had. They are kept on origin as
        backups, and the owner asked to keep them as they are:
          * `claude/backup/negflag-2026-09-27` (`c509c830`): #118's latch at
            every accepted step, its tests and the docs left over from
            #116's review. It was merged into #118 before #118 merged, so it
            is on `main`.
          * `claude/backup/wp4c-2026-09-27` (`b0133d78`): three commits for
            #119, and about 530 lines of tests and docs never committed. Not
            on `main` (G3_TODO, WP4c).
          * `claude/backup/wp4b-2026-09-27` (`5d904221`): follow-ups for
            #121, never committed. Not on `main` (G3_TODO, WP4b).
      + *Option C's miss probe, scored later that day: W47.* Job `13987196`
        finished on 2026-09-25 with exit status 0, and nobody had scored it.
        By the pre-registered rules, three of the four rises in which no
        ledger changed by half the rise go to candidate 5, the forcing's
        vertical fluctuation, in class-N cells (parent at or below zero). In
        the fourth no candidate is supported. The forcing as a whole
        attributes it (1.000, as in every rise), and that term only
        contributes (0.47). Subsidence alone also attributes every rise, but
        maps to no candidate (W47). The owner chose to probe more first
        (below).
      + *#118's CI: one runner shutdown.* On 2026-09-28 the Julia 1.10 job
        `tagging_water_precipitation` stopped after 52 minutes, when GitHub's
        runner received a shutdown signal during the sphere test. The rerun
        passed. The log does not show the cause. That job's Julia process
        peaks at 14.6 to 14.7 GiB (`maxrss`) on a 16 GB runner, on `main`
        too, so memory is one candidate. If it recurs, the sphere tests get
        a test group of their own.
      + *Housekeeping.* 24 worktrees whose work is on `main` were captured
        into the archive and removed, and 22 merged remote branches were deleted
        ("Branches, worktrees and sessions"). The archive's
        `scratch_tag_closure/` was synced first.
      + *The owner's answers, later on 2026-09-28* (DECISIONS.md):
          * C: probe more first, and rerun the probe on `main` now;
          * two PRs from the backups;
          * W45 after C's revision; OD7 deferred;
          * WP4a: the pair, then the copies;
          * W21: model the surface flux;
          * WP6 confirmed;
          * OD9 to OD15, G4.3 to G4.6 and WP4b's points walked through
            later.
      + *W48, 2026-09-29:* the extended probe on `main` (section 9.7). By
        leave-one-out, subsidence carries every rise (84% to 95% of the
        forcing's growth goes without it), and the vertical fluctuation
        carries none. The mechanism is shown cell by cell. C's revision
        waits on the owner, with W47 and W48.
      + *2026-09-29:* the owner chose C's revision: the explicit brackets
        give the region tags the target's gain (design section 10, option
        1). ClimaParams v1.1.16 turned `main`'s CI red by switching on the
        geometric SGS-variance term. #128 caps it at v1.1.15.
      + *Where the next session starts:* #128, then #127's CI and the #119
        follow-ups' PR; C's revision (design, pre-registration, PR); WP4a-J;
        W21's surface flux. The
        uncommitted start of W45's investigation in `-plan2` is backed up
        as `claude/backup/plan2-2026-09-25` (`b3cd940a`). Record work now
        uses the worktree `../ClimaAtmosResiDyn-rec`, detached, pushing
        `HEAD:claude/plan-rev2`.
      + *`main` merged into this branch* (`679c52dd`, `main` at `cfc2152c`),
        its first merge since 2026-09-23. All 21 conflicts went to
        `main`'s side. Outside `experiments/tag_closure/` this branch is
        `main` again, plus `toml/tag_closure_c1_reference.toml`.

  - **Update, 2026-09-26: the provenance pathway, proposed.**
    [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md) proposes a revision of rev.
    2 toward provenance evidence for both families. Closure is one question
    per cell, and the model knows its answer. Provenance is the rest, and the
    model computes no answer for it. The page gives evidence levels, and per
    tag an observed spread and an exposure screen, neither of them an error
    bound. It gives sixteen theories and a plan of five gates; the other
    experiments wait for a measured result. It was revised the same day after
    the owner's review. It proposes OD9 to OD15 to the owner; OD3 and OD5
    stay as decided. PT15, PT16, PX25 and OD15 were added on 2026-09-27,
    from the owner's review of #121. Nothing has run.

      + **Where the newest results live.** On 2026-09-26 they were on
        `claude/plan-rev2` at `a6949414`, 78 commits ahead of
        `claude/tag-closure-record`, and no other branch held a record commit
        that it lacked. Check that before building on either branch.

  - **Update, 2026-09-25: the owner's answers, W25 scored, the probe read.**
    Each decision's state is in ROADMAP.md's register, the single source;
    the open ones are listed below ("The owner's open decisions").

      + The owner answered WP4b-D (the three parts, gross flows; steps 7, 8
        and 8b unblocked), OD4's quantity (an exact accumulator), the WP4c
        gate's OD3 reading, and the mirrors' relaxation (by composition).
      + W25's isolation (step 2) is scored (`output/w25i/`). The copies fail
        their repair row on every rung, so provenance is not assessable
        there. The parent's two-iteration Newton error exceeds 1e-3 on every
        assessable rung.
      + Known issue 7's probe is read (`output/issue7_probe/`): it points to
        C. The choice among B, C and D is the owner's.
      + Jobs `13944447` to `13944462` (G4.16, the WP4c gate, the mirrors) are
        with the parent session.

  - *Superseded 2026-09-25: see the update above.* **Update, 2026-09-24, later: OD3 approved, option A, step 2 ready.**

      + The owner approved the OD3 thresholds, OD2's window rule and OD6's
        ceiling, as drafted (ROADMAP.md, "The OD3 thresholds"). Step 2 is
        unblocked.
      + Known issue 7: option A is built. No closure check ends a run by
        default; water's old level, 1.0, marks its rows void
        (`claude/tag-closure-no-abort`, `00c9eedb`, for a PR against `main`).
        The closure check ended the follower runs (job `13917157`'s `.err`,
        line 1401). The probe is pre-registered and its run tree prepared
        (`design/NEGATIVE_PARENT_WATER.md`, section 5); then the owner chooses
        among B, C and D.
      + Step 2 is pre-registered, with its configs and scripts
        (`design/W25_ISOLATION.md`); its 46 jobs are not submitted.
      + The sphere: a 1 to 2 day 60-level run, untagged and with 8 + 8 tags,
        measures its cost first, after step 8a.
      + Draft PRs #108 (the guard) and #109 (WP6 step 3) are open; all 16
        validation jobs passed (`output/wp6_step3/jobs/`,
        `output/g416_guard/jobs/`).

  - *Superseded later the same day: see the register.* **Update, 2026-09-24, 21:10: the owner's answers.** The owner answered
    the register (ROADMAP.md, "The owner's answers"): OD1 the sphere at 60
    levels; OD2 physical windows; OD4 gross source throughput; OD5 bounded
    passes; OD6 90 days to saturation; OD8 8 tags with copies at 8; W33
    opt-in until M5; the per-tag ledgers on in validation and qualification
    runs; 2M and P3 refused until measured; draft PRs when green. OD7 is
    deferred. OD3 is drafted in ROADMAP.md and waits for approval; step 2
    waits for it.

      + **Known issue 7**, a parity-class defect: at site 23 the tagged long
        runs end while the untagged twin completes 90 days. The fix is step
        8a, before the sphere; the options are in
        `design/NEGATIVE_PARENT_WATER.md`, and the choice is the owner's.
      + The branches `claude/plan-rev2`, `claude/energy-explicit-1m-guard` and
        `claude/water-tags-wp6-step3` are pushed by the parent session. Its
        validation jobs `13924194` to `13924209` run; five had passed by its
        last report.
      + New commits, not pushed: the guard's extension (`e55ae293`), known
        issue 7 on `claude/water-tags-wp6-step3` (`18e7ef1d`), and these
        records.

  - **Update, 2026-09-24, 20:00: rev. 2 of the work plan, steps 0 and 1.**
    The owner revised the plan (ROADMAP.md, "Rev. 2 of the work plan").

      + Step 0 is done: the energy explicit-1M guard with its test
        (`claude/energy-explicit-1m-guard`, `33eeb5cd`), these entries, the
        in-place edits of G3_PLAN, G3_TODO, G4_TODO and ROADMAP, the decision
        register OD1 to OD8, and the comparator-eligibility annotations on
        W21 (D4-W), W29, E39 and E76.
      + Step 1 is built: WP6 step 3 with the per-tag ledger, on
        `claude/water-tags-wp6-step3` (on #103; G3_TODO, WP6). Unit tests
        pass on the login node. The integration tests and the check script
        wait for a compute node.
      + Nothing is pushed. Steps 2 and 3 wait on OD1 to OD3; see "The
        owner's open decisions".
      + Since the plan's pinned SHA (`65925262`): W35 passed (WP5b-V's
        same-atmosphere check); WP9a is draft PR #106 and G4.15a draft PR #107,
        both on #102; the long runs' first submission is void and the second
        is running (G4_TODO, G4.15); WP5b-C's first build is in
        `../ClimaAtmosResiDyn-wedmf5c`, not pushed and not in FINDINGS.

  - **Update, 2026-09-24, 12:40.** The owner reviewed #104 and #105; both are
    answered on the PRs and pushed.

      + **#104 (WP4a) at `dfd93d7c`.** `pr_tag` reads one batch per output
        time; `pr_tag_res` added; the residual identities tested to rounding;
        the explicit path is a CI group, `tagging_water_edmf_0m_explicit`.
        Local tests pass. W30: the diagnostics' cost after the batch is
        linear, and the default mode's plume grows superlinearly past 8 tags
        (a WP9 item); no negative-area rain-out on TRMM. Follow-ups WP4a-V and
        WP4a-J. The 32-tag copies timing is still building.
      + **#105 (WP5b) at `801c52dd`.** The xhigh review's B1 (the unsplit
        solver) is fixed; the real blocks are tested against finite
        differences in both float types; the follower with 1M stepped
        explicitly is opt-in again. Evidence tagged `evidence/wp5b-w29`.
        Follow-ups WP5b-V, WP5b-P and WP5b-C.
      + D4-W with the blocks (W31): the one-day gross residual falls from
        1.35e-4 to 7.3e-6, parent bit for bit. The three 1M integration files
        pass at `11b8d875`.
      + Running: the 32-tag copies timings, CI on #104 and #105.

  - **Update, 2026-09-24, 09:50.**

      + The owner confirmed the session's scope: finish it, and leave WP5b
        to the other session.
      + #102's reviewed head (`e29384ee`) is merged into WP4a (#104,
        `53cd2db3`) and WP6 (#103, `f22cfb27`), and both are pushed.
      + Their unit and config tests pass at the merges. Two integration tests
        are running, jobs `13892718` and `13892721`, and so is CI on
        #102–#104.
      + Next session: read those two tests and the CI.
      + Otherwise every open item waits on the owner (DECISIONS.md) or
        belongs to WP5b.

  - **Update, 2026-09-24, 09:30.** The session's goal grew twice overnight.
    Late on 2026-09-23 it added WP5. On 2026-09-24 it added WP4b-D and
    Batch 2: V-W8, WP6, WP4a and V-W4.

      + **WP3, #101: green.** The owner's review is answered on the PR.
      + **WP5, #102.** Built, reviewed at xhigh, and validated on D4-W (W24).
        The owner reviewed it on 2026-09-24, and all seven points are taken at
        `a3a23d80` (docs fix `e29384ee`; CI queued).
          * `increment` is now the default in the default mode under EDMF,
            where it is supported.
          * The follower is refused with 1M stepped explicitly.
          * Its column total goes only where the mismatch has its sign. That
            halves the water it moves on D4-W (W28).
          * The evidence behind the default is tagged `evidence/w24`.
      + **Explicit 1M.** The owner chose the tags' sedimentation cross blocks
        for this path. That is the next piece of work.
      + **WP6, #103: steps 1 and 2 are built and green.** The review at high
        effort is taken; it found a Float32 bug in step 1's event count.
        Checks at the other cadences are in W27. Step 3 waits on the owner's
        three points.
      + **WP4a, #104: a draft.** The review at xhigh is taken. The split is
        validated on TRMM 0M, where it moves the tags by at most 0.47%, both
        modes alike (W26). The explicit path is parity-checked. The Jacobian
        of known issue 4 waits on the owner.
      + **WP4b-D:** the design note is reviewed. ~~The fields wait on the
        owner.~~ Decided 2026-09-25: the three parts, gross flows; steps 7, 8
        and 8b unblocked; a separate agent builds step 7, stage 1.
      + **V-W8 is done (W22).**
      + *Superseded 2026-09-25: see the register and `output/w25i/`.* **V-W4 is done (W25).**
          * The default meets its budgets on the time-step and Newton rungs,
            but not at 60 or 120 levels.
          * At 120 levels, and for the copies under first-order upwinding,
            the partition breaks. Neither break is isolated yet.
      + Every open decision is in [DECISIONS.md](DECISIONS.md), "Waiting for
        the owner". When a WP reaches a milestone, run the checklist in
        [README.md](README.md), "Closing a work package or a goal".

  - **Update, late on 2026-09-23.** WP1 is draft PR #100, green, waiting for
    the owner. WP3 is PR #101: built, reviewed by `clima-numerics-reviewer`
    and by the owner, whose points are addressed at `4a1c91a4`. **V-W3 is
    done (FINDINGS W21).** Every tag meets its budget against the copies on
    D4-W. The default's closure is 0.71% at 24 h with one Newton iteration and
    0.13% with ten, so WP5's rule selects the follower. The copies' repair
    (0.6% a day) is over its bound, and a surface-layer tag fails its first
    hour. Three owner decisions follow (G3_TODO, Decisions). **#101's CI is
    red:** the copies group misses closure on the explicit microphysics path
    it switched to in `73fa27bd`, 0.9% after an hour. Probes are queued.
    **The owner added WP5 to the session's goal**, after WP3's open items.
    Upstream needs: [UPSTREAM_REQUIREMENTS.md](UPSTREAM_REQUIREMENTS.md).

  - **G3's WP0 is done, and WP1 waits only for CI.** **This session's
    goal**, set by the owner on 2026-09-23, is WP0 and WP1. WP0: the plan
    checked against the merged #95; V-W0a, V-W0c and V-W1 run, recorded as
    W15 to W19 and put through the verifier; the verifier fixed and extended
    to water (M8); the manifest in the submit path; the inventory classified;
    the Float64-twin helper; the reference datasets in the archive; V-W8
    moved to the GCM-driven column, whose forcing is fetched. WP1: draft PR
    #100, reviewed by `clima-reviewer` and by the owner, whose four points
    are addressed at `30dcfee9`; its CI is queued on GitHub. **The owner
    extended the goal to WP3 at 18:20**: draft PR-W3 on
    `claude/water-tags-edmf-wp3`, stacked on #100, then V-W3. See G3_TODO for
    each item. #95 merged on 2026-09-23 at 16:32
    (`0b2b1032`), which WP0 was waiting for.

  - **#95 brought the partition-only factor to `main`** (from `dcf7d086`;
    head `b9c6e7b0`), as the owner decided (decision 5 of G3_PLAN). The job session reran the R2 ladder's
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

| Branch                        | Worktree                                                                                                         | Who                              | What                                                                     |
|:----------------------------- |:---------------------------------------------------------------------------------------------------------------- |:-------------------------------- |:------------------------------------------------------------------------ |
| `claude/tag-closure-record`   | `ClimaAtmosResiDyn.jl` (the main clone); this session commits from `ClimaAtmosResiDyn-exp`, detached, and pushes | the job session and this session | the record, built on `main`. Both rebase before pushing                  |
| `claude/water-tags-edmf`      | `ClimaAtmosResiDyn-wedmf`                                                                                        | this session                     | G3's model code; draft PR #100                                           |
| (detached, the record branch) | `ClimaAtmosResiDyn-wedmf-run`                                                                                    | this session                     | G3's runs launch from here, at a commit the manifest records             |
| (detached, upstream v0.42.11) | `ClimaAtmos-upstream-d331fe3`                                                                                    |                                  | the parity reference for the next upstream merge                         |
| `claude/water-tags-edmf-wp3`  | `ClimaAtmosResiDyn-wedmf3`                                                                                       | this session                     | WP3, #101                                                                |
| `claude/water-tags-edmf-wp5`  | `ClimaAtmosResiDyn-wedmf5`                                                                                       | this session                     | WP5, #102                                                                |
| `claude/water-tags-edmf-wp6`  | `ClimaAtmosResiDyn-wedmf6`                                                                                       | this session                     | WP6, #103                                                                |
| `claude/water-tags-edmf-wp4a` | `ClimaAtmosResiDyn-wedmf4a`                                                                                      | this session                     | WP4a, #104                                                               |
| (detached run trees)          | `-wedmf-run`, `-wedmf4a-run`, `-wedmf5-run`, `-wedmf5r-run`                                                      | this session                     | the record merged with a PR's head; each run's manifest names its commit |

The old experiment branch `claude/tag-closure-experiments` and the old G3
branch `claude/g3-programme` are retired. Their remote branches were deleted
after H6. Their tips are tagged `archive/tag-closure-experiments-final`
(`8726d2cb`) and `archive/g3-programme-final` (`a52b17f7`).

**The job session** runs the energy jobs. #95, which it owned, has merged.
Its worktrees `-upd` and `-upd-run` were captured into the archive with their
ignored files and removed at 16:40, and the branch was deleted. The job
session cannot be reached through SendMessage; findings go through the owner.

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

**Where the work goes (2026-09-28).**

  - *Records* go on `claude/plan-rev2`. They are committed from
    `../ClimaAtmosResiDyn-rec`, detached, and pushed with
    `git push origin HEAD:claude/plan-rev2` after a rebase. Outside
    `experiments/tag_closure/`, this branch differs from `main` only in
    `toml/tag_closure_c1_reference.toml`, which committed configs point to.
    Merge `origin/main` into it again when `main` moves.
  - *Model code* goes on a branch off `main`, one per change, and reaches
    `main` by a PR.
  - *Runs* launch from a detached run tree at a record commit. Where a run
    needs code not yet on `main`, the PR's branch is merged into that tree.

Until 2026-09-25 the record was `claude/tag-closure-record`, and G3's code
went on `claude/water-tags-edmf` (worktrees `-wedmf` and `-wedmf-run`,
2026-09-23). `-wedmf` was removed on 2026-09-28.

**2026-09-28, after that day's housekeeping.** The table above is as it
stood on 2026-09-23. Beside the repository there are now:

  - the main clone, `ClimaAtmos-upstream-d331fe3`, `-exp`, and `-plan2`,
    which holds this branch with another session's uncommitted edits;
  - `-plan2g4`;
  - `-wp4b` and `-wp4c`, with the uncommitted follow-ups under "Where
    things stand";
  - the long runs' branches: `-lr`, `-lr-absm`, `-lrc`, `-lrc-absm` and
    `-g415`;
  - 22 detached run trees, `-g411-run` to `-wp4c-run`. No remote has their
    commits.

The owner kept these. On origin the branches are:

  - `main` and `gh-pages`;
  - this branch, `claude/plan-rev2-g4` and `claude/tag-closure-record`;
  - `claude/review-open-prs-tasks-wxiw0k` and `claude/pr118-merge-preview`;
  - #123's branch;
  - the four backups: `claude/backup/*-2026-09-27` and
    `claude/backup/plan2-2026-09-25`.

The 24 worktrees removed were:

  - the 18 branch worktrees of PRs #100 to #117 and #120;
  - `-negflag` (#118);
  - four detached trees whose head is in `main`;
  - a job worktree.

Each is captured in the archive's `worktrees/`.

## Pull requests

| PR   | Branch                                   | State                                                                                                                                                                                                                                                                                                                                                                                 | What                                                                                                                                                 |
|:---- |:---------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------- |
| #95  | `claude/energy-source-tag-updraft`       | merged 2026-09-23, 16:32 (`0b2b1032`), at `b9c6e7b0`. That head fixes the allocation tests that failed CI at `afd470e7` (E77's erratum, E78); the tags' tendency is bit for bit that of `afd470e7`, so E76 still describes it. At the merge, CI at `b9c6e7b0` was still running with no failure: 6 checks passed, 34 queued or running. `main`'s CI at `0b2b1032` was queued at 16:40 | the updraft gap: the exchange by default, updraft copies as the audit, with the partition-only factor                                                |
| #96  | `claude/terrabyte-setup`                 | merged 2026-09-23, 12:12 (`3ecb6d25`)                                                                                                                                                                                                                                                                                                                                                 | the terrabyte setup script, its stack file, and the docs that name both machines                                                                     |
| #97  | `claude/historical-tag-closure-pages`    | merged 2026-09-23, 12:12 (`b1a088a4`)                                                                                                                                                                                                                                                                                                                                                 | the "Historical" notes on `docs/src/tag_closure_memo.md` and `tag_closure_experiments.md`                                                            |
| #98  | `claude/tag-closure-condense`            | merged into the record branch 2026-09-23, 13:47 (`859d38f8`)                                                                                                                                                                                                                                                                                                                          | H6, the condensed documents                                                                                                                          |
| #99  | `claude/prek-exclude-experiment-records` | merged 2026-09-23, 13:30 (`e8fcc0f1`)                                                                                                                                                                                                                                                                                                                                                 | excludes the record's frozen files (`archive/`, `output/`, `review/`, `reference/`, `configs/` under `experiments/tag_closure/`) from the prek hooks |
| #100 | `claude/water-tags-edmf`                 | merged into `main` (`5ef18980`)                                                                                                                                                                                                                                                                                                                                                       |                                                                                                                                                      |
| #101 | `claude/water-tags-edmf-wp3`             | merged into its stacked base; its content reached `main` through #110                                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #102 | `claude/water-tags-edmf-wp5`             | merged into #101's branch; reached `main` through #110                                                                                                                                                                                                                                                                                                                                |                                                                                                                                                      |
| #103 | `claude/water-tags-edmf-wp6`             | merged into `main`                                                                                                                                                                                                                                                                                                                                                                    |                                                                                                                                                      |
| #104 | `claude/water-tags-edmf-wp4a`            | merged into `main` 2026-09-26 (`e003e7aa`), at `860fcce4`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #105 | `claude/water-tags-sed-cross`            | merged into `main` 2026-09-25 (`ab0beb7a`), at `464f6fd0`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #106 | `claude/water-tags-plume-cost`           | merged into `main` 2026-09-24 (`3eac4d44`), at `bfd9ff08`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #107 | `claude/energy-follower-check-names`     | merged into `main` 2026-09-26 (`0ca2ca97`), at `fd1e86e1`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #108 | `claude/energy-explicit-1m-guard`        | merged into `main` 2026-09-25 (`99b4b6b0`), at `2f7987d5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #109 | `claude/water-tags-wp6-step3`            | merged into `main` 2026-09-26 (`405b5b63`), at `6f6152a2`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #110 | `claude/water-tags-edmf-wp3`             | merged into `main` 2026-09-24 (`14ed3b51`), at `7f384796`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #111 | `claude/water-tags-copy-cross`           | merged into `main` 2026-09-26 (`d1eb9606`), at `105ba0f1`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #112 | `claude/tag-closure-no-abort`            | merged into `main` 2026-09-26 (`03b6d428`), at `ca74cecd`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #113 | `claude/energy-tags-sed-cross`           | merged into `main` 2026-09-27 (`7f54d0fa`), at `b9798fd5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #114 | `claude/energy-copies-mirrors`           | merged into `main` 2026-09-26 (`fb1bffdf`), at `528ca1a2`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #115 | `claude/energy-source-throughput`        | merged into `main` 2026-09-26 (`fe7d3d26`), at `c4fa73b5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #116 | `claude/water-tags-negative-parent`      | merged into `main` 2026-09-27 (`7f2b7244`), at `6e8769cf`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #117 | `claude/downgrade-groups-from-runtests`  | merged into `main` 2026-09-26 (`6fb78f2b`), at `afda1f1a`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #118 | `claude/water-tags-negative-water-flag`  | merged into `main` 2026-09-28 (`09d66bcb`), at `2115426f`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #119 | `claude/water-tags-leak-correction`      | merged into `main` 2026-09-28 (`134c442f`), at `818b6238`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #120 | `claude/energy-claims-budget`            | merged into `main` 2026-09-28 (`43f9eaa7`), at `ef49771f`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #121 | `claude/water-tags-rain-snow`            | merged into `main` 2026-09-28 (`6489e110`), at `4d600bd9`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #122 | `claude/tag-provenance-certainty-zwkx73` | merged into `claude/plan-rev2` 2026-09-27 (`4aeacf81`), at `130064d6`                                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #123 | `claude/water-tags-substep-attribution`  | draft, against `main`, at `7fb9cabc` (per-substep attribution of the 1M microphysics)                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #124 | `claude/docs-issue7-after-116`           | merged into `main` 2026-09-28 (`283a18ec`), at `9481e412`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #125 | `claude/terminology-to-main`             | merged into `main` 2026-09-28 (`cfc2152c`), at `1ff3e8c0`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #126 | `claude/negative-water-accumulator`      | merged into `main` 2026-09-28 (`d2f119ab`), at `c165ae18`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |

Only the owner merges. The token cannot mark a PR ready for review. Rows #104
to #126 were read from GitHub on 2026-09-28.

## Jobs in flight

  - **The job session's R2 ladder default reruns** at `dcf7d086`, jobs
    `13782601` to `13782605`. All five had finished with exit status 0 by 11:05
    (read from their provenance on scratch at 11:25). E76 records them. Their
    small tables are not yet in `output/`.
  - **G3:** V-W0a (six runs), V-W0c, V-W1 and the known-issue-1 test run
    finished on 2026-09-23 and are recorded as W15 to W19.
  - Slurm was queried at 18:10: no job of this account was queued or running.
  - **2026-09-24, 09:20:** no job of this account is queued or running. Every
    run of the night is recorded, W22 to W28.
  - **2026-09-24, evening, from the record (not queried with Slurm):** the
    long runs' second submission, jobs `13917157` to `13917199`
    (G4_TODO, G4.15), and the 32-copies build, job `13911480`, with an 8 h
    limit (W34).
  - **2026-09-25, 15:40, queried with Slurm:** the 32-copies build
    (`13911480`) timed out at 8 h without building (W34). Option C's
    validation and the ledger-ratio runs finished and are recorded (W42,
    E85). Queued or running: WP4c's corrections V1 and V2 (`13973348`,
    `13973349`), G4.6's three runs (`13975411`, `13975417`, `13975419`),
    #120's increment integration test (`13975420`), and #119's two test
    groups (`13975443`, `13975444`).
  - **2026-09-28, queried with Slurm:** no job of this account is queued or
    running. Option C's miss probe (`13987196`) and WP4c's V1 and V2
    (`13973348`, `13973349`) finished on 2026-09-25. V1 and V2 are W45. The
    probe was scored later that day as W47. Two test jobs for PRs ran that
    day and passed: `13995633` for #118 and `13996629` for #126. The
    extended probe's check job, `13996777`, passed (1 h 57 min, both CSVs
    written, the per-level sums equal to the step totals). The probe itself,
    `13996867`, was submitted at 22:22 from the run tree at `e09e0986`. It
    finished at 01:29 on 2026-09-29 and is W48.

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

  - `$SCRATCH/claude_work`: cleaned when the job session no longer uses it. It
    is in the archive.
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

*Scope added (provenance pathway, 2026-09-26):* OD9 to OD15 are proposed, not
yet open. OD15 was added on 2026-09-27. Each becomes open when the owner
accepts it ([PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md), section 9).

Each decision's current state is in ROADMAP.md's register, the single source.
OD7 is the only open numbered decision. Open now, each with its entry in
[DECISIONS.md](DECISIONS.md), "Waiting for the owner":

  - **OD7**, G4.15's rule for energy, deferred until site 23 can be scored.
  - **Option C after its validation (W42).** V2 fails at site 23 (2.2%
    against 0.2%) and `pbl`'s per-tag row (2.03%). By the design note's
    section 8.3 the owner decides; site 23's long-run rerun, which OD7 waits
    on, is not submitted until then. *Decided 2026-09-25: probe the miss
    first* (the register), then validate C again. *2026-09-28:* scored as
    W47. The owner chose to probe more first (section 9.7). C's revision
    stays open.
  - ~~**Known issue 7's option among B, C and D.**~~ Decided 2026-09-25:
    option C (the register). Built; its validation is pre-registered.
  - ~~**WP4a's two points**~~ decided 2026-09-28 (the register).
  - ~~**WP6's three points**~~ confirmed as built, 2026-09-28 (the register).
  - **The explicit-1M water default, at M5** (W33 stays a failure).
  - ~~**W21's surface rule in the first hour**~~ decided 2026-09-28 (the
    register).
  - **OD9 to OD15, G4.3 to G4.6's seven points, WP4b's five points:** to be
    walked through one at a time (the register, 2026-09-28).

Not plan decisions, kept as they stood on 2026-09-23 and not rechecked:

  - **`main`'s CI at `0b2b1032`**, after #95's merge.
  - **A rerun of `main`'s CI** after #96 and #97, the owner's to start.

*Superseded on 2026-09-25 by the list above; kept as written:*

>   - **Rev. 2's register, OD1 to OD8** ([ROADMAP.md](ROADMAP.md), "The
>     decision register"). ~~All eight are open. Steps 2 and 3 of the revised
>     order wait on OD1, OD2 and OD3.~~ *Superseded 2026-09-24, 21:10:* OD1,
>     OD4, OD5 and OD8 are set, and OD2 and OD6 are set in form. Still open:
>
>       + ~~**the approval of the OD3 draft** (ROADMAP.md, "The OD3 threshold
>         draft"), which includes OD2's levels, OD6's ceiling and the proposed
>         60-level stretching. Step 2 waits for it;~~ *Approved 2026-09-24, as
>         drafted.* The stretching is used for the short sphere run;
>       + **OD7**, deferred by the owner until, for example, known issue 7 is
>         fixed and site 23 can be scored;
>       + **known issue 7's fix**: ~~which option~~ A is chosen and built; the
>         choice among B, C and D follows the probe
>         (`design/NEGATIVE_PARENT_WATER.md`);
>       + ~~**OD4's throughput source**: the process records as a lower bound, or
>         a new per-step accumulator (`review/od4_denominator_audit.md`).~~
>         Decided 2026-09-25: an exact accumulator.
>
>     The register's first list, kept as written:
>
>       + OD1, the production envelope: levels, SGS reconstruction, Δt, Newton
>         count, microphysics, the intended tag counts.
>       + OD2, the window boundaries per case.
>       + OD3, the thresholds not yet set.
>       + OD4, the offset-invariant scale for energy percentages.
>       + OD5, how *not assessable* is treated at M5.
>       + OD6, the sphere's ceiling, growth bound and run length.
>       + OD7, G4.15's rule for energy.
>       + OD8, the audit's feasibility at the intended tag count.
>
>   - ~~**W33's verdict**, after the same-atmosphere check passed (W35).~~
>     *Decided 2026-09-24:* W33 stays a failure, W35 beside it; the explicit-1M
>     water follower stays opt-in until M5.
>
>   - ~~**WP6 step 3's open questions**~~ *Decided 2026-09-24:* off by default,
>     on in every validation and qualification run; the fraction uses the tag's
>     current inventory, the absolute amount beside it. Kept as written:
>     ([review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md](review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md)):
>     whether each tag's ledger is on by default, and the denominator of the
>     per-tag fraction.
>
>   - **The sphere's numbers**, before V-W11, and **the default mode's cost
>     budget**, after V-W10's first measurements and before V-W11. The other
>     budgets were set on 2026-09-23
>     ([G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)).
>
>   - ~~**The rain and snow tags' prognostic fields**, after the design note
>     WP4b-D and its review ([G3_TODO](G3_TODO.md#decisions)).~~ Decided
>     2026-09-25 (DECISIONS.md).
>
>   - WP4a's, WP6's and WP4b-D's points, the copies' repair, the surface rule,
>     and V-W4's two breaks: [DECISIONS.md](DECISIONS.md), "Waiting for the
>     owner".
>
>   - **`main`'s CI at `0b2b1032`**, after #95's merge, which was queued at
>     16:40. V-W1 runs on it.
>
>   - **A rerun of `main`'s CI.** #96 and #97 were merged with `ci-required`
>     failing on cancelled checks, not on a failed test, and `main`'s own CI
>     runs were cancelled too. A rerun is the owner's to start.

Every decision taken so far is in [DECISIONS.md](DECISIONS.md).

## Where to look

| To find                                                                                                                                      | Look in                                                                                                       |
|:-------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------- |
| how to set up, submit a run, compare runs, and the traps                                                                                     | [README.md](README.md)                                                                                        |
| the milestones M0 to M8 and where each open item goes                                                                                        | [ROADMAP.md](ROADMAP.md)                                                                                      |
| rev. 2: the acceptance contract, the decision register OD1 to OD8, the execution order                                                       | [ROADMAP.md](ROADMAP.md), "Rev. 2 of the work plan"                                                           |
| the provenance pathway, proposed: the evidence levels, the theories PT1 to PT16, the gated plan and the experiments PX0 to PX25, OD9 to OD15 | [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md)                                                                |
| G3's plan, criteria and budgets                                                                                                              | [G3_PLAN.md](G3_PLAN.md)                                                                                      |
| G3's to-do list                                                                                                                              | [G3_TODO.md](G3_TODO.md)                                                                                      |
| G4's items, and the energy items of the former OPERATIONAL_TODO                                                                              | [G4_TODO.md](G4_TODO.md)                                                                                      |
| open items beyond G4                                                                                                                         | [BACKLOG.md](BACKLOG.md)                                                                                      |
| every decision of the owner                                                                                                                  | [DECISIONS.md](DECISIONS.md)                                                                                  |
| what has been measured, and what was falsified                                                                                               | [FINDINGS.md](FINDINGS.md)                                                                                    |
| every run: commit, job, purpose, findings, where its data is                                                                                 | [RUNS.md](RUNS.md)                                                                                            |
| the energy attribution path, the mixing conventions, the updraft gap, the sub-grid design                                                    | [design/](design/)                                                                                            |
| the frozen external reviews of 2026-09-21                                                                                                    | [reference/](reference/)                                                                                      |
| agent reviews, instructions, check scripts, the register                                                                                     | [review/](review/)                                                                                            |
| H3's re-check of G3's claims                                                                                                                 | [review/verify_g3.md](review/verify_g3.md)                                                                    |
| the originals as they were, and where their content went                                                                                     | [archive/2026-09-23/INDEX.md](archive/2026-09-23/INDEX.md)                                                    |
| the housekeeping of 2026-09-23 and its outcome                                                                                               | [archive/2026-09-23/CONDENSE_PLAN.md](archive/2026-09-23/CONDENSE_PLAN.md)                                    |
| the run data                                                                                                                                 | `$SCRATCH/tag_closure/output/` and `~/git/Clima/ClimaAtmosResiDyn-archive/` (RUNS.md)                         |
| the user docs of the diagnostics                                                                                                             | `docs/src/energy_source_tags.md`, `tagged_water.md`, `process_record.md`; #95's `energy_source_tags_guide.md` |
