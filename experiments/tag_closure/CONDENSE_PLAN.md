# Plan: corroborate the results and condense the documents

Approved by the owner on 2026-09-19, to run once V2's findings are written.
Updated the same day at 12:00, after V2's model top collapsed and V3 ran.
Archive this file with the others when the plan is done.

## Why

The experiment branch holds about 10,400 lines in 19 documents. FINDINGS alone
is 2,800 lines, about 108 entries (E1 to E67, the water, reference, cost and
method entries). Several are stale; FINDINGS' header still reads "state as of
2026-09-10". Of 92 committed output directories, 60 still have their NetCDF on
scratch, which is not durable. The goal is documents that state the facts,
each claim checked against its evidence, and nothing of the experiments lost.

## Before phase 1

Phase 1 starts when these are done. Items 1 and 2 are the "V2 entries" the
approval waits for.

1. **V2's diagnosis.** In V2 the model top (27 km) cools to the 150 K floor
   within 6 h under one Newton iteration, while the converged twin holds
   218 K. Three three-hour variants look for the cause: sponges off, two
   Newton iterations, no mountain (jobs `13505762` to `13505764`). Done:
   only the second keeps the top at 219 K, so the one-iteration solve makes
   the collapse. V2 runs again with two iterations, `g2_v2_sphere_n2` (job
   `13505896`). Its entries follow as a delta if the condensing has started.
2. **The entries for the new results,** in FINDINGS, with their outputs under
   `output/`:
   - V2 as it ran: ten days of closure, the residual against its loss rate,
     and the collapse as the model's own, with its caveat for every reading;
   - the converged twin: on the sphere the residual is not the solver's
     (2.78e-5 against 2.45e-5 at 24 h), unlike D4;
   - the diagnosis of item 1;
   - the updraft gap's estimate, as corrected by its review (below);
   - V3 on D4: at 1 h the inversion cell differs by 58 points of share, and
     at 24 h the tags hold 7.0% air from above the inversion against the
     tracer's 10.1%, with `ta` bit for bit.
3. **UPDRAFT_GAP.md brought in line with its review:** an estimate of the
   initial rate, not a bound. The deep-convection figures ("to 10 km", "3 to
   10 days") do not describe V2's first days, whose updrafts end at 1.8 to
   2.6 km in the tropics.
4. ~~**The agent reviews kept in the repository.**~~ Done:
   `review/agent_reviews/` holds the two reviews of the prototype
   (`35042f33`, `c0bc637f`) and the review of the updraft estimate, with its
   check scripts and logs.

If V2 is rerun, the condensing does not wait for it. The rerun's entries are
added afterwards, and group A checks them as a delta.

## Safeguards

- Tag the commit before the work, and move every original, unchanged, to
  `archive/2026-09-19/`. Nothing is deleted.
- Work on `claude/tag-closure-condense`, merged by a PR into
  `claude/tag-closure-experiments` that the owner reviews.
- A committed measurement never changes. A correction is a dated erratum
  beside its entry. Output directories are not touched.
- Out of scope: `docs/src/tag_closure_memo.md` and
  `docs/src/tag_closure_experiments.md`, the user docs and code of #93 and
  #94, and any running job.
- Checking only reads. No simulation runs; a check that would need one goes
  on a list for the owner.
- The newest runs' NetCDF and checkpoints (V2, its twin, the diagnostics, V3)
  exist only on scratch. Group A checks them first.

## Phases

1. **A claim register** (one agent, Sonnet, medium effort). Every claim into
   `review/claims.csv`: its ID, document, the claim in a line, its numbers,
   its evidence (output directory, job, script, commit), its status (live,
   superseded, falsified) and where else it appears. Also each document's kind
   (record, plan, design, draft, instruction, discussion) and a proposed fate.
2. **Checking the results** (four agents in parallel, read-only). Verdicts:
   recomputed, consistent, unverifiable (data gone), discrepant (with the
   recomputed number), stale (a code reference moved), superseded. Each writes
   `review/verify_<group>.md`. Where an agent review in
   `review/agent_reviews/` already checked a claim, the agent starts from it
   and does not redo it.
   - A: E53 onward, including V2, its twin, the diagnostics, V3 and the
     updraft estimate: the EDMF, prototype and G1/G2 work. Opus, high.
     Recompute each number with the recorded scripts
     (`analysis/increment/`: `d4_compare.py`, `remainder_split.py`,
     `tag_correctness.py`, `tag_correctness_sphere.py`, `v2_sphere.py`,
     `updraft_gap_estimate.jl`, `v3_compare.py`), and check the physics
     arguments.
   - B: E25 to E52, the audit, repair, Float32, MPI, restart and parity.
     Sonnet, high. Against the committed CSVs; recompute where scratch data
     survives.
   - C: E1 to E24, the water entries, the energy reference, cost and method.
     Sonnet, medium. Mostly the committed CSVs and logs; say where data is
     gone.
   - D: code references and consistency across documents. Sonnet, medium.
     File and line references against today's code; the same numbers in
     FINDINGS, OPERATIONAL_TODO, ATTRIBUTION_PATH, TRACER_AND_FLUX,
     UPDRAFT_GAP, NEWS and the docs; PR and commit IDs.
3. **Adjudication** (the main session). Every discrepant or stale claim gets a
   decision: an erratum, a rewording, or a dismissal with its reason.
4. **Condensing** (one writer agent, Opus, high, AGENTS.md's style).
   - FINDINGS becomes a register of facts by topic: closure by transport,
     EDMF, the implicit channel, Float32, MPI and restart, records, the
     sphere, mixing (V3 and the updraft gap), cost. One line each, with the
     number and its evidence. Superseded and falsified claims in one table
     with pointers. About 500 to 700 lines.
   - OPERATIONAL_TODO keeps what is open and what was decided, with a short
     table of what is done.
   - README keeps the run register (configuration, worktree and commit,
     purpose, finding) without its narration.
   - ATTRIBUTION_PATH, TRACER_AND_FLUX and UPDRAFT_GAP stay, the first with
     its summary brought to the present.
   - LEARNINGS, NEXT_SESSION, LEVANTE_TASKS, TODO_REVIEW, the drafts and this
     plan go to the archive, with pointers. What LEARNINGS alone holds moves
     into FINDINGS as short reasons.
   - A one-page STATUS.md: the goals, where things stand, where to look, and
     the owner's open decisions: the threshold of G1's criterion 4, question
     2 (the conventions; TRACER_AND_FLUX.md), question 3, V2's configuration
     if it is rerun, and merging #93 and then #94.
5. **The loss check** (one agent that did not write, Opus, medium to high).
   Every claim of the register is in the new documents, or archived or
   superseded with a pointer; every number is the same; every run directory
   is referenced; nothing new is claimed. Gaps are fixed, and the check runs
   once more.
6. **The owner's review:** the PR with the new documents, the register, the
   four reports and the errata.

About seven agents and most of a day.
