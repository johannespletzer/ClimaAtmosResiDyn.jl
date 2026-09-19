# Plan: corroborate the results and condense the documents

Approved by the owner on 2026-09-19, to run once V2's findings are written.
Archive this file with the others when the plan is done.

## Why

The experiment branch holds about 10,300 lines in 18 documents. FINDINGS alone
is 2,800 lines, about 108 entries (E1 to E67, the water, reference, cost and
method entries). Several are stale; FINDINGS' header still reads "state as of
2026-09-10". Of 92 committed output directories, 60 still have their NetCDF on
scratch, which is not durable. The goal is documents that state the facts,
each claim checked against its evidence, and nothing of the experiments lost.

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

## Phases

1. **A claim register** (one agent, Sonnet, medium effort). Every claim into
   `review/claims.csv`: its ID, document, the claim in a line, its numbers,
   its evidence (output directory, job, script, commit), its status (live,
   superseded, falsified) and where else it appears. Also each document's kind
   (record, plan, design, draft, instruction) and a proposed fate.
2. **Checking the results** (four agents in parallel, read-only). Verdicts:
   recomputed, consistent, unverifiable (data gone), discrepant (with the
   recomputed number), stale (a code reference moved), superseded. Each writes
   `review/verify_<group>.md`.
   - A: E53 to E67 and V2, the EDMF, prototype and G1/G2 work. Opus, high.
     Recompute each number with the recorded scripts, and check the physics
     arguments.
   - B: E25 to E52, the audit, repair, Float32, MPI, restart and parity.
     Sonnet, high. Against the committed CSVs; recompute where scratch data
     survives.
   - C: E1 to E24, the water entries, the energy reference, cost and method.
     Sonnet, medium. Mostly the committed CSVs and logs; say where data is
     gone.
   - D: code references and consistency across documents. Sonnet, medium.
     File and line references against today's code; the same numbers in
     FINDINGS, OPERATIONAL_TODO, ATTRIBUTION_PATH, NEWS and the docs; PR and
     commit IDs.
3. **Adjudication** (the main session). Every discrepant or stale claim gets a
   decision: an erratum, a rewording, or a dismissal with its reason.
4. **Condensing** (one writer agent, Opus, high, AGENTS.md's style).
   - FINDINGS becomes a register of facts by topic: closure by transport,
     EDMF, the implicit channel, Float32, MPI and restart, records, cost. One
     line each, with the number and its evidence. Superseded and falsified
     claims in one table with pointers. About 500 to 700 lines.
   - OPERATIONAL_TODO keeps what is open and what was decided, with a short
     table of what is done.
   - README keeps the run register (configuration, worktree and commit,
     purpose, finding) without its narration.
   - ATTRIBUTION_PATH, TRACER_AND_FLUX and UPDRAFT_GAP stay, the first with
     its summary brought to the present.
   - LEARNINGS, NEXT_SESSION, LEVANTE_TASKS, TODO_REVIEW and the drafts go to
     the archive, with pointers. What LEARNINGS alone holds moves into
     FINDINGS as short reasons.
   - A one-page STATUS.md: the goals, the open decisions, where to look.
5. **The loss check** (one agent that did not write, Opus, medium to high).
   Every claim of the register is in the new documents, or archived or
   superseded with a pointer; every number is the same; every run directory
   is referenced; nothing new is claimed. Gaps are fixed, and the check runs
   once more.
6. **The owner's review:** the PR with the new documents, the register, the
   four reports and the errata.

About seven agents and most of a day.
