# Review of the planning stack PRs #147, #148 and #149

Date: 2026-10-07. Overseer session on Fable (Claude Code), with delegated
agents: for each PR a Sonnet first pass (`worker`, high effort) and an Opus
confirmation (`clima-reviewer` for #147, `clima-numerics-reviewer` at xhigh
for #148 and #149), plus a Sonnet worker per PR for the semicolon rewrite.
Mechanical checks ran as scripts, kept in `review/checks/plan_docs/`.

The three PRs are documentation only, stacked on `claude/plan-rev2`
(58d3535): #147 reconciles the plan into capability increments and adds
`PLAN_CROSSWALK.md`, #148 defines the water acceptance contract (G3_PLAN
6.1.1 to 6.1.5), #149 rewrites `design/G4_CLAIM_CONTRACTS.md` into the
energy acceptance contract.

Files read: the three diffs and every changed planning document, the base
versions on `claude/plan-rev2`, PR #146's diff, and the sources the documents
make claims about: `src/parameterized_tendencies/tagged_tracers/`
(`energy_source_tags.jl`, `tag_throughput.jl`, `process_record.jl`,
`tagged_water*.jl`, `water_tag_checkpoint.jl`, `tag_closure_checkpoint.jl`,
`energy_source_checkpoint.jl`), `src/parent_budget/`, `src/diagnostics/`,
`src/cache/precomputed_quantities.jl`, `test/process_record_integration.jl`,
`analysis/evidence/compare_runs.py`, `analysis/water/g3base_score.py`,
`analysis/increment/{od4_restate,process_budget,g411_eligibility,tag_correctness}.py`,
and E87's archived output for the C4 computations.

Decisions read: `DECISIONS.md`, ROADMAP's register, `review/od4_restatement.md`,
`review/od4_denominator_audit.md`, `design/G3_BASELINE_RERUN.md`.

Fork parity: no PR touches model code. No finding moves an upstream field.

Outcome: all blocking findings were fixable by text and are patched on the
three branches (#147 `d68ab8e6a`, #148 `be77a25db`, #149 see its PR
comment), with the stack merged forward. Owner decisions are listed in each
PR's section D or E and in the PR comments. Mechanical results after the
patches: every link, anchor and crosswalk pointer resolves, every table row
has its header's column count, prek passes, and the added text has no
semicolons outside code spans, URLs and verbatim quotes. One formatter trap
was found: the pinned JuliaFormatter turns `&#124;` into a raw pipe outside
code spans, which splits table cells, so pipes inside cells are written as
`\|`.

Severity classes: blocking (wrong or lost content, a contradiction, a
decision written as the owner's), patch (a safe textual fix), owner (a choice
only the owner can make), nit. Finding ids F are the first pass's, O the
confirming reviewer's. Edits C/R/D/S/T/P/V are the exact edits applied.

## PR #147: plan reconciliation and crosswalk

Head `24b7536a3` against base `58d353546`. Line numbers are the PR head's. The semicolon rewrite keeps every line count, so they are also the work copies' (the rewrite copies). Section C's "old" text is quoted from the work copies, after the rewrite, so the edits go on top of it.
Checked by hand: the diff, the base ROADMAP/DECISIONS/G4_TODO, FINDINGS W52-W62, DECISIONS 2026-10-02 and 2026-09-29/30, G3_TODO's WP9 budget, the #146 commits `b702ff171` and `33cbfd4fa` (local), and 40 crosswalk rows.

### A. The worker's findings

| id | verdict | class | one-line statement |
|:--|:--|:--|:--|
| F1 | CONFIRMED | blocking | Parts 5 and 7 form a cycle. ROADMAP:725 says part 5's closure rule needs part 7, and part 7 (689) depends on part 5. Fix by text (R2). |
| F2 | CONFIRMED | blocking | Parts 12a-d put M6/M7 work into the active order (multi-node, devices, production, "Publish supported envelope"). ROADMAP:45 and STATUS:94-97 still call that work not approved. Fix by text (R1). |
| F3 | CONFIRMED | owner | G4 no longer waits for G3. Parts 11a-d have no water dependency, so this covers the whole of G4, not only "preparatory work". It reverses the owner's order of 2026-09-23 (ROADMAP:21-25, G4_TODO:1 title). G4_TODO:20-23 rewrites the base sentence "It waits for G3". |
| F4 | CONFIRMED | owner | The 90-day sphere (12d) now waits for 12a-c and qualification. In the base it needed only OD6, after step 8a. |
| F5 | MODIFIED | blocking | The real defect is worse than "two homes". The owner's 1-2-day sphere pilot (2026-09-24) is M4 work (ROADMAP:38 M4 row, "after step 8a") and must come before M5 (ROADMAP:52-53). 12d now puts it behind qualification and 12a-c. 12c also needs an "earlier cost pilot" (see O7). Fix by text (R10). |
| F6 | MODIFIED | patch | PX16 has three homes: part 6's text (688), CW:814 "2 / 6 / 7 / 8" and CW:1279 "9 only after PX8 and OD13". The worker's CW:604 is an unrelated row (#95's factor). Make part 9 the home (R3, C8). |
| F7 | CONFIRMED | patch | G3_PLAN:8 leaves parts 4 and 5 out of the water capability. G4_TODO:7-9 leaves out 11a's dependency on part 5. |
| F8 | CONFIRMED | patch | "eligible PX12" (688) misreads PX12. PX12 is the scheduled eligibility test and has not run (721-722). |
| F9 | CONFIRMED | patch | Reproducibility appears only in part 4 and in no level. The base's "M4's ceilings fixed" (step 8) has no home. Fixed by R9 (levels) and R13 (ceilings). |
| F10 | CONFIRMED | patch | Old step numbers clash with part numbers (G4_TODO:63 and 475, G3_TODO:1019 and 1086, ROADMAP:416-562). Add one sentence each to ROADMAP, G3_TODO and G4_TODO. |
| F11 | MODIFIED | nit | G3_TODO:951 is base text outside the PR's hunks. Dating the head is enough (T4). |
| F12 | REJECTED | - | G3_TODO:341 is an unchanged [x] record of the question of 2026-09-28. Its answer was "not in WP6". Rewriting it would alter a dated record. The deferral is stated elsewhere. |
| F13 | CONFIRMED | nit | G4_TODO:16-17 "residual-flush diagnostics" belong to G4.4's flush-rate column and PX19, not to G4.14. |
| F14 | MODIFIED | blocking | DECISIONS:3-24 records, in the owner's voice and outside the file's marks, an adoption the owner has not recorded. The adoption covers the new order, the energy-parallel start and the deferral. Fix by text: make it a proposal in "Waiting for the owner" (D1-D2). |
| F15 | CONFIRMED | owner | ROADMAP:61 and :674 (also G3_PLAN:5, PROVENANCE_PATHWAY:6) declare the order in force and superseding rev. 2. That stands only once the owner adopts it. Interim mark: R14. |
| F16 | CONFIRMED | owner | Levels 0-4 are a third labelling scheme beside the contract's verdicts and OD9's proposed labels. Adopting it is the owner's choice. R9 only makes it consistent. |
| F17 | CONFIRMED | owner | The residence-time and air-age deferral is stated as decided in six places. No register row or dated entry carries it. If the owner said it, the owner records it. D2 carries it as proposed until then. |
| F18 | MODIFIED | patch | "Waiting for the owner" lists more than OD7: also the explicit-1M default at M5, OD9-OD11, OD15 and the G4.3-6 levels. The new list (DECISIONS:13-16) leaves out the explicit-1M default, E89 (DECISIONS:392), the WP9 cost budget (G3_TODO:1405) and 2M/P3 (upstream). Replace it with a pointer and add the budget (D2, D3). |
| F19 | CONFIRMED | patch | The new section separates the title from the file's own introduction. D1 removes it. |
| F20 | MODIFIED | patch | An owner review exists (commit `b702ff171`, "The owner's review of #146, points 1 and 3"). A review at the head `33cbfd4` is not shown. State that precisely (D4, T2). |
| F21 | CONFIRMED | patch | The rule "an agent stops at a step whose decision is open and asks the owner" was deleted with the Needs column. Restore it in the stop rules (R8). |
| F22 | CONFIRMED | blocking | Lost dependency: base 8b "if the owner adopts OD9 ... step 8b also needs OD11". It is in no head file except as a crosswalk excerpt routed to "2 / 3". Fix by text (R8, C4). |
| F23 | CONFIRMED | patch | CW:212, 214-217 give the generic "2 / 3" destination. The real homes are given in C2-C6. |
| F24 | CONFIRMED | nit | The "State (2026-09-25)" column is gone. Its facts survive elsewhere and no status regressed. |
| F25 | CONFIRMED | nit | "true reference ... no offset or sign problem" became "candidate references". This agrees with option D. |
| F26 | MODIFIED | patch | The M8 row (ROADMAP:43) drops "memory and forecasts". No decision defers forecasts, and G4.4 holds one (see O1). Restore them (R11). |
| F27 | CONFIRMED | nit | G4_TODO:22 loses "at #95's merged head" (T7). |
| F28 | REJECTED | - | PROVENANCE_PATHWAY:1631 now says "The list below records the earlier step numbers". The numbering is labelled. |
| F29 | MODIFIED | nit | CW:826's destination already says "preserve historical failures". The header (14-15) bars promotion. An optional wording edit is C13. |
| F30 | MODIFIED | patch | Only FQ-20's open remainder (wider mask) is unrouted (C12). FQ-2's remainder is FQ-3, routed at CW:1846/1949. FQ-21's remainder is routed at CW:1855. |
| F31 | CONFIRMED | patch | CW:121 (known issue 7, superseded the same day) is routed to the cost pilot. Route it as CW:171 does (C1). |
| F32 | MODIFIED | patch | CW:799 and CW:814 contradict the PX rows (1355, 1279). CW:885's destination is right, but "Open in source" hides that it is deferred. All three need a deferred disposition (C7-C9). |
| F33 | CONFIRMED | patch | Duplicate of F23. One set of edits covers both. |
| F34 | CONFIRMED | nit | CW:1491 belongs to part 4, which is where PX0 is (C11). |
| F35 | CONFIRMED | nit | PX5 ran (W54, "no eligible D4-like comparator"). CW:1373 still routes it as live (C14). |
| F36 | CONFIRMED | nit | Rows for standing failures (CW:120, 1586) do not show the failure in the disposition column. No promotion. |
| F37 | REJECTED | - | The worker itself found no defect. The headings are in different files and no link targets them. |
| F38 | CONFIRMED | patch | STATUS has no level column although ROADMAP:90-91 asks for one. STATUS:13 "cost evidence exists" hides criterion 10's failure (4.16x against 2x). Fix: S1, S3. |
| F39 | CONFIRMED | nit | The dates are fine. The STATUS changelog is not extended. |
| F40 | CONFIRMED | nit | EOF blank lines. These belong to the separate formatting fix. |
| F41 | CONFIRMED | nit | "bracket" appears only in verbatim excerpts. No action. |
| F42 | CONFIRMED | patch | "provenance" appears in new prose at ROADMAP:112, 117, 687, 692, 724, G3_PLAN:17-18 and STATUS:13, 15. Use "origin". |
| F43 | MODIFIED | patch | Class raised from nit, since the programme's rules require it. "donor" at ROADMAP:131, 689, 725, G3_PLAN:18, G3_TODO:22, STATUS:15, PROVENANCE_PATHWAY:13. "follower" at ROADMAP:695. Keep G4.14's own "donor-loss" (ROADMAP:74) as the source's term. |

### B. Own findings

| id | verdict | class | one-line statement |
|:--|:--|:--|:--|
| O1 | new | blocking | The PR defers G4.4's prepared forecast design (synergy 4, `OT-SYN4`) without a decision. CW:1042-1046 say "Deferred forecast extension". CW:948 routes the same synergy 4 to "5 / 11b", and items.csv lists OT-SYN4 as open with target G4.4. Fix by text (C10, R11). The owner says whether the flush-rate forecast falls under the owner's residence-time exclusion. |
| O2 | new | owner | The cost gate has no path. Part 10 needs "fixed cost ceilings". Criterion 10 fails against OD3's 2x (8 + 8 step 4.16x), and the budget waits for the owner (G3_TODO:1388-1425). The only performance part, 12c, comes after qualification, and E90 places the excess in the parent's walks, possibly upstream. The owner either revises OD3's step row or moves a bounded performance fix before part 10. R13 names the gate. |
| O3 | new | owner | #146 books its closing step in a dedicated ledger. The in-force decision of 2026-10-02 (DECISIONS:285-287) says "booked in the rescale's ledgers". The PR buries this as "verify the decision trail". It needs the owner's yes at #146's merge. D4 records it as waiting. |
| O4 | new | patch | The levels are not stated as cumulative, and none asks for reproducibility. As written, level 4 could be reached without level 3, which contradicts ROADMAP:105-107. R9 fixes both. The ten aspects in ROADMAP:112-114 point to the contract for their definitions, and that is sound. |
| O5 | new | owner | M5 default selection (base 8b, including the explicit-1M default and W33) has no named part. Part 8 says only "before selecting fixes/defaults". The owner places it, probably in 9 or 10, after part 8's cost. R8 keeps its gates (OD9/OD11) meanwhile. |
| O6 | new | owner | Part 2 picks "one useful initial water workflow" with W54-W62 already known. That risks choosing the scope by which cases pass. Proposed safeguard: part 2 states the workflow's user and reason before part 8 and lists the cases that fail. The safeguard's wording is for the owner. |
| O7 | new | blocking | A second cycle, between 12c and 12d. 12c needs the "Earlier cost pilot", 12d runs "first the ... cost pilot", and 12d needs 12a-c. If 12c's pilot is 12d's, the order cannot start. R10 says 12c means part 8's pilot. |
| O8 | new | note | Parts 8 and 9 loop ("Re-establish baseline after changes") with no cap or end condition. Suggest: part 9 ends when part 10's criteria pass or the owner stops it. |
| O9 | new | patch | STATUS:13's next step for D4-W is "eligible references in 6". Under option D, D4-W has no eligible comparator, and per-tag accuracy moves to TRMM 0M and Soares (DECISIONS:307-311). Fix: S1. |
| O10 | checked | - | Failed evidence, checked against FINDINGS and DECISIONS. No part claims a pass that FINDINGS records as failed. W54 (R5 fails), W60 (fails at ten iterations, W62 narrower), W33, D4-W under option D and V5 `led_fix` (W53, DECISIONS:323) are all preserved. W58 passes as stated. The one soft claim is STATUS:13 on cost (F38). |

### C. Exact edits (after the semicolon rewrite)

Rows prefixed "interim" mark owner items as proposed. They apply only if the owner has not confirmed before merge. Crosswalk edits name the row line and the cell (destination = third column, disposition = fourth).

#### ROADMAP.md
- **R1 (F2)** line 706. Old: `there. Placing expanded coverage in part 12 does not postpone those checks.` New: `there. Placing expanded coverage in part 12 does not postpone those checks. Parts 12a–d also hold M6 and M7 work: multi-node runs, devices, a production trial and the supported envelope. That work stays sketched and not approved, as above. Each such item needs the owner before it starts. The G3 items these parts reuse (V-W7, V-W9, WP9, OD1/OD6's sphere) keep their existing approval and gates.`
- **R2 (F1, F42, F43)** lines 723-725. Old: `the owner (option D). PR #146 implementation does not close WP4b's EDMF or` / `provenance qualification obligations. The known signed-ledger cancellation` / `concern belongs to part 5. Its closure rule needs part 7's donor tests.` New: `the owner (option D). PR #146 implementation does not close WP4b's EDMF or` / `origin qualification obligations. The known signed-ledger cancellation` / `concern belongs to part 5, which delivers accounting that shows cancellation. Part 7's known-composition tests then check the closing rule's attribution. Part 7 needs part 5's outputs, not a part 5 verdict on the closing rule.`
- **R3 (F6, F8)** line 688, column 2. Old: `Reuse PX1/PX8, PX7, PX11/PX24, eligible PX12 and existing mixing tests.` New: `Reuse PX1/PX8, PX7, PX11/PX24 and existing mixing tests. Run PX12, the scheduled 0M eligibility test.` Column 3. Old: `PX16 only after PX8's trigger and OD13.` New: `PX16 (PP-SUB) goes to part 9, only after PX8's trigger and OD13.`
- **R4 (F42)** line 112. Old: `accounting/closure, provenance,` New: `accounting/closure, origin,`. Line 117. Old: `model, and evidence for real atmospheric provenance.` New: `model, and evidence for real atmospheric origins.`
- **R5 (F42)** line 687. Old: `No unsupported cumulative provenance-error bound.` New: `No cumulative origin-error bound is claimed without support.`
- **R6 (F42)** line 692. Old: `Unresolved provenance cannot be called validated.` New: `Unresolved origins cannot be called validated.`
- **R7 (F43)** line 131. Old: `manufactured cases, and independently implemented known-donor transfers,` New: `manufactured cases, and independently implemented transfers of known composition,`. Line 689. Old: `Known donor compositions distinguish` New: `Known compositions of the giving pool distinguish`. Line 695. Old: `subsidence and follower choices` New: `subsidence and choices for the correction after each solve`.
- **R8 (F21, F22, O5)** line 727. Old: `**Stop rules.** An unavailable independent reference blocks the corresponding` New: `**Stop rules.** An agent stops at a part whose owner decision is open and asks the owner. Default selection (M5) follows rev. 2's rules as approved, within the cost ceilings. If the owner adopts OD9, it also needs OD11, and the verdict records are reported beside it. An unavailable independent reference blocks the corresponding`
- **R9 (F9, O4)** line 93. Old: `level from one successful case.` New: `level from one successful case. Each level requires the levels below it.`. Line 98. Old: `| 1 Operational | That configuration runs and has the required parent parity and restart evidence. |` New: `| 1 Operational | That configuration runs and has the required parent parity, restart and reproducibility evidence (part 4's records). |`
- **R10 (F5, O7)** line 690, column 2. Old: `Measure dominant errors, intervention and intended-count cost before selecting fixes/defaults.` New: `Measure dominant errors, intervention and intended-count cost before selecting fixes/defaults. This is the column cost pilot. The owner's 1–2-day sphere pilot is M4 work and may run once part 8's contract exists (see 12d).` Line 699. Old: `Earlier cost pilot and scientific baseline.` New: `Part 8's cost pilot and scientific baseline.` Line 700, column 3. Old: `Relevant qualification, 12a–c, parent validity and affordable cost.` New: `The 90-day run: relevant qualification, 12a–c, parent validity and affordable cost. The 1–2-day pilot keeps its earlier gate (OD6, after the negative-parent fix, merged as #137) and comes before M5 selection, as M4 requires.`
- **R11 (F26, O1)** line 43, column 2. Old: `Extensions: air age deferred. Numerical-loss diagnostics retain their gates` New: `Extensions: air age (deferral proposed 2026-10-05), memory and forecasts. Numerical-loss diagnostics retain their gates`
- **R12 (F10)** line 676. Old: `The old steps are mapped in [PLAN_CROSSWALK.md](../PLAN_CROSSWALK.md). Their` New: `Step numbers elsewhere in these documents are the earlier order's. The old steps are mapped in [PLAN_CROSSWALK.md](../PLAN_CROSSWALK.md). Their`
- **R13 (F9, O2)** line 692, column 3. Old: `Parts 8/9, fixed cost ceilings, OD14 held-out hygiene.` New: `Parts 8/9, cost ceilings fixed by the owner (the WP9 budget is waiting, criterion 10 fails against OD3's 2×), OD14 held-out hygiene.`
- **R14 interim (F15)** line 61. Old: `This revision changes the active execution order in place.` New: `This revision proposes to change the active execution order in place (proposed 2026-10-05, waiting for the owner, DECISIONS.md).` Line 674. Old: `This is the active delivery sequence as of 2026-10-05. It supersedes the` New: `Proposed 2026-10-05, waiting for the owner: once adopted, this is the active delivery sequence. It supersedes the`

#### DECISIONS.md
- **D1 (F14, F19)** Delete lines 3-25 (from `## Planning revision of 2026-10-05` through the blank line after `that task. This plan does not authorize or perform its merge.`).
- **D2 (F14, F17, F18)** Insert after line 51 (the blank line after `record; the answered and superseded entries are in the next section.`):
  ```
    - **The planning revision of 2026-10-05 (PR #147).** Proposed
      2026-10-05, waiting for the owner. PR #147's brief says the owner asked
      for an in-place plan by capability and evidence, without residence-time
      work. The proposal: ROADMAP's parts 1 to 12d replace rev. 2's execution
      order. Residence-time and air-age features are deferred. G4.14's loss
      timescale and PX19's flush screen keep their meaning and gates. The
      energy contract and energy references may start before G3 ends. The
      proposal approves no threshold, scientific default, simulation
      campaign or OD9 to OD11 label. OD5's "bounded" wording stays, without
      implying a mathematical error bound.
      [ROADMAP](../ROADMAP.md#the-execution-order)

  ```
- **D3 (F18, O2)** Insert directly after D2:
  ```
    - **The WP9 cost budget (criterion 10).** OD3's 2× stays for now, so
      criterion 10 fails (8 + 8 step 4.16×). A revised step row is proposed.
      Water qualification (ROADMAP part 10) needs it.
      [G3T](../G3_TODO.md#wp2-wp8-wp9-consolidation-docs-cost)

  ```
- **D4 (F20, O3)** Insert after line 296 (`        the microphysics hook.`):
  ```
        + *Update 2026-10-05, a status note:* #146 is open at `33cbfd4f`,
          built, with the owner's review points 1 and 3 answered in
          `b702ff17`. Its closing step books a dedicated closing ledger, not
          the rescale's ledgers named above. Whether that meets this decision
          is **waiting** for the owner, at #146's merge.
  ```

#### STATUS.md
- **S1 (F38, F42, O9)** line 13. Old: `| Water, D4-W | Parity/closure and cost evidence exists. W54 comparator repair still fails. | Parts 2/4/5, then eligible references in 6. | Criteria 5/6 are not judged on D4-W under option D. No validated provenance claim. |` New: `| Water, D4-W | Parity and closure evidence exists. W54 comparator repair still fails. Cost is measured and fails criterion 10 against OD3's 2× (8 + 8 step 4.16×). | Parts 2/4/5. Per-tag accuracy moves to TRMM 0M and Soares in part 6 (option D). | Criteria 5/6 are not judged on D4-W under option D. No validated origin claim. The cost budget waits for the owner. |`
- **S2 (F42, F43)** line 15. Old: `part 7 donor attribution` New: `part 7 attribution against known compositions`. Old: `independent provenance remain open.` New: `independent origin evidence remain open.`
- **S3 (F38)** line 19. Old: `No level is assigned to a whole family without matching the required` New: `No evidence level is assigned yet. Parts 2 and 3 define what each level needs. No level is assigned to a whole family without matching the required`

#### G3_PLAN.md
- **P1 (F7)** line 8. Old: `Parts 2 and 6–10 deliver the first scoped water capability.` New: `Parts 2, 4, 5 and 6–10 deliver the first scoped water capability.`
- **P2 (F42, F43)** lines 17-19. Old: `provenance validity. Signed closing-ledger cancellation and donor-origin` / `validation remain parts 5 and 7.` New: `origin validity. Signed closing-ledger cancellation stays in part 5.` / `Validation of origins against known compositions stays in part 7.`

#### G3_TODO.md
- **T1 (F10)** line 15. Old: `precipitation/EDMF stages remain in WP4b. All later parts retain their gates.` New: `precipitation/EDMF stages remain in WP4b. All later parts retain their gates. "Step n" below means the earlier order's step. The crosswalk maps it.`
- **T2 (F20)** line 17. Old: `PR #146 is built and reviewed but still open at` New: ``PR #146 is built, with the owner's review points 1 and 3 answered in `b702ff17`. It is still open at``
- **T3 (F43)** line 22. Old: `Parts 5 and 7 own cancellation tests and independent donor tests.` New: `Part 5 owns the cancellation tests. Part 7 owns the independent known-composition tests.`
- **T4 (F11, nit)** line 951. Old: ``Open as #146 (head `9dc512f1`), not merged.`` New: ``Open as #146 (head `9dc512f1` on 2026-10-02), not merged.``

#### G4_TODO.md
- **T5 (F7)** lines 8-9. Old: `build eligible independent references once that contract and evidence tools` / `exist.` New: `build eligible independent references once that contract, part 4's evidence` / `tools and the applicable part 5 accounting exist.`
- **T6 (F13, F10)** lines 16-18. Old: `G4.14's instantaneous loss timescale` / `and residual-flush diagnostics retain their original conditions and are` / `not residence time. Air-age and residence-time extensions are deferred.` New: `G4.14's instantaneous loss timescale,` / `G4.4's flush-rate column and PX19's flush screen retain their original conditions and are` / `not residence time. Air-age and residence-time extensions are deferred. "Step n" below means the earlier order's step.`
- **T7 (F27, nit)** line 22. Old: `except work on PR #95 and its ladder.` New: `except the job session's work on PR #95 and the ladder at #95's merged head.`
- **T8 interim (F3)** line 10. Old: `PRs. The older phrase "after G3" does not block this preparatory work. It` New: `PRs. Proposed 2026-10-05, waiting for the owner: the older phrase "after G3" would not block this work. It`

#### PROVENANCE_PATHWAY.md
- **V1 (F43)** line 13. Old: `known-donor/analytic references` New: `known-composition/analytic references`

#### PLAN_CROSSWALK.md
- **C1 (F31)** row 121, destination. Old: `8 / 11b cost pilot → 12d` New: `8 → 9. Superseded the same day by option C (see the register).`
- **C2 (F23)** row 212, destination. Old: `2 / 3 contract reconciliation. The applicable implementation or qualification part inherits the source gate.` New: `8 → 9 if triggered (PX2).`
- **C3 (F23)** row 214, same old destination. New: `7. Items 5 and 7 go to PX25 (7 / 8, OD15 gate).`
- **C4 (F22)** row 215, same old destination. New: `Default selection (M5). It needs OD11 if the owner adopts OD9. See ROADMAP's stop rules.`
- **C5 (F23)** row 216, same old destination. New: `7 / 8. OD15 gate.`
- **C6 (F23)** row 217, same old destination. New: `12d. Numerical-flush screen.`
- **C7 (F32)** row 799. Destination old `7 / 8 → 9 / 10` new `8 → 9 if triggered`. Disposition old `Open in source. Verify before scheduling.` new `Deferred in source with its trigger. Do not schedule.`
- **C8 (F6, F32)** row 814. Destination old `2 / 6 / 7 / 8. Section requirements inherited by named water mechanism.` new `9 only after PX8 and OD13`. Disposition as in C7.
- **C9 (F32)** row 885, disposition as in C7.
- **C10 (O1)** rows 1042-1046, destination. Old: `Deferred forecast extension. No qualification from extrapolation.` New: `11b (G4.4 synergy 4). No qualification from extrapolation.`
- **C11 (F34)** row 1491, destination. Old: `2 / 3. Designs in 6 / 7 / 11a and their named PX destinations.` New: `4 (PX0).`
- **C12 (F30)** row 1966, treatment. Old: `Retain historical completion. Do not redevelop.` New: `Retain historical completion. The wider-mask question stays open, outside the roadmap.`
- **C13 (F29, nit)** row 826, disposition. Old: `Completion recorded. Reuse scoped evidence.` New: `Completion recorded. The verdict is a failure (R5). Preserve it.`
- **C14 (F35, nit)** row 1373, destination. Old: `6 / 8. Option D restricts D4-W work.` New: `Run 2026-10-02 in W54: no eligible comparator. Option D restricts D4-W work.`

Count: 46 edits. ROADMAP 14 (R1-R14), DECISIONS 4, STATUS 3, G3_PLAN 2, G3_TODO 4, G4_TODO 4, PROVENANCE_PATHWAY 1, crosswalk 14 (C10 is one edit applied to five rows, and R14 and T8 are interim). After applying them, re-run the link and anchor checks. The new text has no semicolons.

### D. Semicolon rewrite spot-check

- **The crosswalk map: all 115 lines read.** Every rewrite keeps its meaning. The only rewrites beyond punctuation are articles ("The source status or gate applies") and line 103, `1, 4 and 5, plus the energy guard in 11c.` Both are faithful. Line 61 (`2 / 3 / 4. Proposed labels only. 7 / 8. Decide at PX25 preregistration.`) keeps the original's two-destination form, which was already terse. No change of meaning.
- **The other nine files: all 36 word-diff hunks read, not a sample of 30.** ROADMAP 15, STATUS 3, DECISIONS 4, G3_TODO 4, G3_PLAN 3, G4_TODO 3, PROVENANCE_PATHWAY 2, BACKLOG 1, UPSTREAM_REQUIREMENTS 1. The comma-list rewrites (DECISIONS:13-14, G3_TODO:10-11) and the joins at ROADMAP:702 and 713 keep their meaning.
- **Structure.** Pipe counts per table row are identical in PLAN_CROSSWALK, ROADMAP and STATUS. Relative links (58) and crosswalk source links (2082) are identical in count. The link at ROADMAP:676 is intact. No table or link is broken.
- Verdict: no rewrite changed meaning or broke a table or a link. Nothing to fix. Section C is written against the rewritten text.

### E. Verdict for the owner

PR #147 can merge after the patches. First, the owner settles four things that only the owner can decide.

1. **Adoption.** Does the owner adopt parts 1-12d as the active order, in place of rev. 2's steps (F14, F15)? If yes, the owner writes the DECISIONS line himself, and the interim marks R14 and T8 are dropped. If not, D1-D2 and R14 keep the plan as a proposal.
2. **Energy before G3 ends (F3).** As written, parts 11a-d can run the whole of G4 beside water. The owner's order of 2026-09-23 said G3 first.
3. **Residence time and forecasts (F17, O1).** the owner confirms that the owner excluded residence-time and air-age work. the owner also says whether G4.4's flush-rate forecast falls under that exclusion. Without the owner's word it stays in 11b, as C10 and R11 restore.
4. **The cost path and the sphere (O2, F4, O5).** Will the owner revise OD3's step row, or put a performance fix before part 10? Does the 90-day sphere wait for 12a-c? Which part selects the M5 default? R10 already restores the 1-2-day pilot's earlier gate.

The five blocking findings are F1, F2, F5, F14 and F22, and the own findings O1 and O7. Every one of them is fixable by the text in section C. None needs a run or a code change. The owner also decides O3, whether #146's dedicated closing ledger meets the owner's decision of 2026-10-02, but at #146's merge, not #147's. The progress levels (F16) and the part-2 scope safeguard (O6) can be settled at part 2.

## PR #148: the water acceptance contract

Line numbers are head-file lines under `experiments/tag_closure/` unless a `src/` or `docs/` path.
Checked by computation: ARS222/ARS343 stage weights and the sign flips (Julia 1.11 on the
ClimaTimeSteppers 1.0.1 tableaux of the Manifest, and Python), TRMM's flux ramp times, the face
reconstructions on a stretched grid, the Float32 floor (3·2^-23·√720 = 9.60e-6). Everything else by reading.

### A. The worker's findings

| id | verdict | class | statement |
|:--|:--|:--|:--|
| F1 | MODIFIED | blocking | The conflict is real, but two of its pieces are approved: "not applicable" is OD3's per-tag intervention disposition (2026-09-25), and "a non-finite value or a missing hour is a failure" is the owner's rule of 2026-09-23 (G3_PLAN 6.1, "How the budgets are read"). The PR's separate "data/execution failure" verdict breaks ROADMAP:245's three verdicts. #147's ROADMAP:728 ("missing data → not assessable") breaks the owner rule. Fix: a data failure is a **fail**, labelled as such (C20, C24, C41, C43, C46). |
| F2 | CONFIRMED | blocking | No review record exists. The newest file in review/agent_reviews is dated 2026-09-30. Completion is claimed at G3_TODO:11, at G3_TODO:35 (`[x]`) and at STATUS:31-32, although G3_PLAN:1239 itself requires resolved review findings (C34, C35, C45). |
| F3 | MODIFIED | owner | Narrower than stated. Already approved: per-tag ledgers in every validation run (6.1, 2026-09-24), copies as the audit (OD8), the from-1-h row (2026-10-02) and both-mode restart (criterion 2). New: (a) complete cancellation-safe applied-leg accounting as a qualification condition, (b) "coverage of all material active rules", where materiality is the pathway's exploratory term and "validated for named rules" is OD9 (proposed), and (c) O8. Fix: record them as WA-GATES proposals and qualify "authoritative" (C5, C19, C23, C26, C38). |
| F4 | CONFIRMED | patch | ROADMAP:156 gives an instruction, but G3_PLAN 2.1 and WA-SCOPE are proposals (C39, C44). |
| F5 | CONFIRMED | patch | Level 0 needs the intended use, which WA-SCOPE leaves open (C44). |
| F6 | CONFIRMED | owner | #147's Part 2 row says "Propose missing tolerances". The PR proposes no value, and its completion rule (G3_PLAN:1239) leaves that out (C33 gives the proposed sentence). |
| F7 | MODIFIED | owner | The point stands: the eight-tag/24-h alternative names no case. OD2's 24-h cases are D4-W (excluded for 5/6 by option D), the GCM-driven column and RICO (held out). The evidence is wrong, though. TRMM's lhf rises from 0 at 0 h to its peak at 5.25 h, is 97% of the peak at 6 h and stays positive to 10.5 h (TRMM_LBA.jl:77-79, computed). See O6. |
| F8 | REJECTED | — | "Fixed-Newton, direct block solver" is the fork's own parity-contract wording (docs/clima_atmos_specific.md:405: "a fixed number of Newton iterations with the direct block solver"). `ManualSparseJacobian(approximate_solve_iters)` is that solver. A link to the contract is optional. |
| F9 | CONFIRMED | patch | `_retained` is H_L counted from the run start, or from a new segment after a legacy restart (tag_throughput.jl:1022-1025, :1236-1294). Under the rain/snow key `_attempted` also counts moves between a tag's own parts (:1027-1031) (C15). |
| F10 | CONFIRMED | patch | The averaged `pr` is the mean of the step-end rates (`EveryStepSchedule`, src/callbacks/get_callbacks.jl:121-125), so it is a quadrature. Folded into O1's rewrite (C17). |
| F11 | CONFIRMED | patch | w_l is defined only for the column. The sphere needs J. `g3base_score.thickness()` is exact only on a uniform grid (O4) (C11, C31). |
| F12 | CONFIRMED | nit | Under 0M, q_liq and q_ice come from saturation adjustment (precomputed_quantities.jl:742-743, against :771-776) (C10). |
| F13 | CONFIRMED | nit | The latch is in tag_closure_checkpoint.jl:114-160 (C18). |
| F14 | CONFIRMED | patch | W58's R4, R5 and R8 are recorded passes at the pre-registered TRMM 6-h end (FINDINGS:2597-2606, design/G3_BASELINE_RERUN.md:137). "Readings" demotes them (C7, C22, C30, C36). |
| F15 | MODIFIED | patch | The failure is misattributed. W52 has no failure verdict ("The budget waits for the owner", G3_TODO:1233), and its default at 8 water tags is 1.43×, inside 2×. The recorded failure is criterion 10 at 8 + 8: E88's step at 4.16× against OD3's 2× (owner 2026-10-02, G3_TODO:1445, :1464), plus OD3's copies row at 4 h 16 min (C4, C25, C29, C37). |
| F16 | MODIFIED | patch | Add only a cross-reference. Whether to fold the two questions into one is the owner's choice (C3). |
| F17 | MODIFIED | blocking | The deleted sentence is rev. 2 contract text from commit 0ccef48f8, and #147 forbids silent rewrites of OD5. Restore the sentence and keep the new reading as a proposal (C42, C5 item d). |
| F18 | MODIFIED | patch | Merged into F19 (C32). |
| F19 | MODIFIED | patch | #146 is unmerged, so one pointer paragraph is enough, not notes on each row. Its hyperdiffusion change acts only under the rain/snow key and does not touch the 0M pilot. Its closing step makes R/S compartment closure hold by construction (C32). |
| F20 | CONFIRMED | patch | "Bracket" appears at G3_PLAN:1016, 1017, 1021 and 1142 (C12, C13, C27). |
| F21 | CONFIRMED | patch | Replace the new non-quoted "provenance" (C2, C8, C9, C15, C21, C23, C24, C28, C40, C47), "donor-proportional"/"donor share" (C6, C13) and "follower" (C7, C15). Keep the OD row names, the OD5 quote and the PX14/PX25 "known donor" names. |
| F22 | CONFIRMED | nit | Map criterion 9 to 12a, 2 to 12b, 10 to 12c and 11 to 12d. |
| F23 | CONFIRMED | nit | Add "the criterion's full text in section 2 stays the obligation" below the disposition table. |
| F24 | CONFIRMED | nit | Name one part as the owner of the paired accumulator. |
| F25 | CONFIRMED | nit | The wording is unclear in the owner's record (C1). |
| F26 | MODIFIED | nit | Quote the approved inequality rather than adding a threshold table (C14). |

Worker's "Verified claims": I re-checked the formulas, signs, normalization scales, restart policy, refusals and W58/W60/W62 numbers. All hold, except the TRMM flux sub-claim in F7.

### B. Own findings

| id | class | statement |
|:--|:--|:--|
| O1 | blocking | G3_PLAN:1041 defines `P_i = -Σ_n Δt_n Σ_s b_s pr_i(n,s)`, which is not the applied amount in the pilot. Details follow the table. Fix: C17. |
| O2 | blocking | ROADMAP:248-251 deletes the rev. 2 contract sentence "G3_PLAN 6.1, M2 and G4.3 to G4.6 refer to this table and do not restate it" (0ccef48f8). The worker listed it among the removed lines but did not flag it. Restore it and add the new sentence beside it (C41). |
| O3 | patch | The existing tools mostly divide by T+, not raw M. The audit's `_retained_relative` and `fix_gross_relative` use the audit `scale`, which is T+ (tagged_water_increment.jl:727-737). `g3base_score` R4 uses `gross_relative` (over T+), and R8's aggregate divides by the closure CSV's `total`, also T+ (:263, :284-291). `per_scale` returns 0 for a zero scale. Neither appears in 6.1.5's limits. W58 is unaffected, since R3 found no negative water (C31). |
| O4 | patch | On a 60-level geometric grid (30 m bottom, 45 km top), `g3base_score.thickness()` is 2.1% off in the bottom cell, 3.9% off at most, and 0.19% off for a water-column integral. `compare_runs.compute_faces_and_dz` is exact to 6e-15. 0.19% is close to the 0.2% closure budget. TRMM's uniform grid is exact in both (C11, C31). |
| O5 | patch | G3_PLAN:1040 says the 1M per-tag flux uses "actual rain/snow tagged donor fluxes". It also carries the tag's N-share of cloud liquid and ice sedimentation (tagged_water_precipitation.jl:2046-2052) (C16). |
| O6 | owner | The pilot's OD2 windows are undecided. TRMM's lhf, `554·max(0,cos(π/2(1−t/5.25 h)))^1.3`, stays above 10% of its peak from 0.57 h to 9.93 h (computed). If OD2's pulse clause covers this ramp, startup does not end inside 6 h, and the established-flow rows are not assessable. The approved per-tag rows sit at 1 h and 24 h, so under the approved rules a 6-h run can score only the first-hour row. WA-SCOPE should say which windows the pilot scores. |
| O7 | note | The small-tag share S_i uses the signed integral (compare_runs.py:826-827). A signed tag whose parts nearly cancel is therefore judged by the absolute rule, while OD3's intervention applicability uses the burden. Report B_i/M_ref beside S_i. Whether the burden governs is the owner's call. |
| O8 | owner | The copies-eligibility row (G3_PLAN:1096) adds grid rungs and initialization/fallback coverage. 6.1 lists closure, repair, Newton and time-step stability, mirrors and Jacobian. OD3's refinement row covers dt and Newton only. Record this as WA-GATES item c, unless PX12's pre-registration already has it. |

O1 in detail:

- (a) The TRMM overlay keeps `implicit_microphysics: true` (the default). So the 0M rain-out is stepped with `b_imp` (ARS222: 0, 0.707, 0.293).
- (b) ClimaTimeSteppers 1.0.1 applies the Newton-implied tendency `T_imp[s] = (U_s − Û_s)/(Δt a_ss)` (imex_ark.jl:283-287).
- (c) With `max_newton_iters_ode: 1`, that tendency is not the rate evaluated at U_s, and it mixes every implicit process. Under EDMF the implicit refresh also re-aggregates frozen specific tendencies with the iterate's ρa (microphysics_cache.jl:712-728).
- (d) No output exposes stage values. `pr` and `pr_tag` are rates at the step-end state (tagged_water_rainout.jl:357-364).
- (e) The parent budget measures exactly this amount (`impl.microphysics_removal_0m`, "applied increment with accepted implicit weight"), but refuses EDMF (`impl.out_of_scope`, coverage.md:165, :173).
- (f) Some weights are negative: ARS222 `b_exp` = (−0.707, 1.707, 0), ARS343 `b` = (0, 1.208, −0.644, 0.436). Computed examples: explicit ARS222 with stage rates (1, 0) applies −0.707·rate·Δt, and ARS343 with (1, 3, 1) applies −0.289·Δt. A step can therefore apply an upward amount even though every stage rate is downward.

Also confirmed:

- **H_L.** The density ledger accumulates per cell (`ᶜgross += abs(L − prev)`, tag_throughput.jl:596-603) from the run start. A window is the difference of two outputs.
- **Weights.** `w = ρ_ref Δz` matches `compare_runs.py:1287-1295` and `g3base_score.py:236-238`. This is the FV cell mass per unit area, and the model's `sum` uses the same J = Δz on a column.
- **Small tags.** "Zero reference counts as small" and the 1% share against raw total_ref match 6.1 (2026-09-23) and `compare_runs.py:812-841`.
- **Signs.** `pr` and `pr_tag` are upward-positive (microphysics_cache.jl:1294-1318). `D_p = pr − Σ_P pr_tag` equals `pr_tag_res` under 0M.
- **No-rain absolute defects.** These are right. A nonzero `pr_tag_i` at `pr` = 0 arises only from opposite-signed subdomain terms or a withheld gain.
- **Preservation.** The PR removes no line in G3_PLAN, so the twelve criteria, option D, OD3's numbers and the F32 floor are unchanged. W60's failure, W62's limits and D4-W's restriction to 3/4/9/10 are kept.

### C. Exact edits (47), by file

DECISIONS.md

- C1 (F25) :5-6. Old: "The user authorized preparation/review of the water acceptance documentation, then its agent execution/resumption." New: "The owner asked agents to prepare and review the Part 2 water acceptance documentation."
- C2 (F21) :15. Old: "0M precipitation provenance is unqualified" New: "0M precipitation origins are unqualified"
- C3 (F16) :15, after "OD15 separately decides PX25's additional 1M/EDMF pool/refinement rows." Add: " OD15 also asks whether accumulated `Σ pr_tag` is scored under 1M. One window convention can serve both, if the owner so chooses."
- C4 (F15) :16. Old: "W52's intended-count cost failures stand." New: "Criterion 10's recorded failure stands: the 8 + 8 step at 4.16× against OD3's 2× (E88, the owner 2026-10-02), and OD3's copies row (8 + 8 copies built in 4 h 16 min). W52 is the water half: 1.43× at 8 tags, 2.43× with per-tag ledgers, 7.38× at 32."
- C5 (F3, F17, O8) new row after :16: "| WA-GATES — conditions the matrix adds | Accept, amend or reject, as conditions of a qualified water claim. (a) Complete cancellation-safe accounting of accepted applied corrections and compartment legs (G3_PLAN 6.1.2, intervention row and overall decision). (b) Eligible independent coverage of all material active rules, with "material" defined. The pathway's materiality is exploratory, and "validated for named rules" is proposed OD9. (c) Grid-rung stability and initialization/fallback coverage in copies eligibility, beyond 6.1's list and OD3's time-step and Newton refinement. (d) The Part 2 reading of ROADMAP's contract sentence on OD5. | Part 2 recommends (a) to (c) as stated, and (d) beside OD5's unchanged wording. | Until decided, the matrix reports these beside the approved rows. They are not approved gates. |"

G3_PLAN.md

- C6 (F21) :211. Old: "Donor-proportional loss depletes both." New: "Loss in proportion to what each tag holds depletes both."
- C7 (F14, F21) :246-248. Old: "W58's existing six-hour evidence is parity and accounting evidence: follower closure and the partition's instantaneous precipitation sum are near rounding; the copies' residual/repair pass their recorded checks." New: "W58's existing six-hour evidence is parity and accounting evidence. Its R4, R5 and R8 passes stand as recorded, at the six-hour end that `design/G3_BASELINE_RERUN.md` pre-registered for TRMM. Closure under the correction after each solve and the partition's instantaneous precipitation sum are near rounding. The copies' residual and repair pass their recorded checks."
- C8 (F21) :284. Old: "no D4-W provenance ladder" New: "no D4-W origin ladder"
- C9 (F21) :958. Old: "No six-hour provenance tolerance" New: "No six-hour origin tolerance"
- C10 (F12) :966. Old: "Its `q_liq` includes rain and `q_ice` includes snow." New: "Under 1M its `q_liq` includes rain and `q_ice` includes snow. Under 0M they come from saturation adjustment and hold no precipitation."
- C11 (F11, O4) :974-977. Old: "For this fixed column the profile verifier's weights are `w_l = ρ_ref,l Δz_l`; determine `Δz_l` from the actual faces and quadrature, not just nominal `dz_bottom` or output-index spacing. A sphere also needs horizontal metric/area weights." New: "The weight of cell l is `w_l = ρ_ref,l J_l`, with `J_l` its volume weight. On a column normalized to unit area `J_l = Δz_l`, so `w_l = ρ_ref,l Δz_l` in kg m^-2, as `compare_runs.py` uses. On the sphere `J_l` includes the horizontal area, and A is in kg. Take `Δz_l` from the actual faces, not from nominal `dz_bottom` or output-index spacing. `compare_runs.py` rebuilds the faces from the centres, which is exact where centres are face midpoints. `g3base_score.py`'s `thickness()` puts faces midway between centres, which is exact only on a uniform grid."
- C12 (F20) :1016-1017. Old: "For a bracketed local source/sink the declared tendency is" New: "For an attributed local source or sink the declared tendency is". Old: "with Δ the parent's bracketed **rate**," New: "with Δ the process's tendency of the parent, a **rate**,"
- C13 (F20, F21) :1020-1021. Old: "guarded donor share" New: "guarded share of what the tag holds". Old: "when the bracket exposes only their net" New: "when the applied-update event exposes only their net"
- C14 (F26) :1034. Old: "Apply 6.1's small-tag absolute rule when its share condition holds; it replaces both relative tests." New: "Apply 6.1's small-tag absolute rule, `A_i ≤ 2e-4 M_ref` where `S_i < 0.01`. It replaces both relative tests."
- C15 (F9, F21) :1038. Old: "The current `_retained` columns implement this; `_attempted` counts all calls including discarded stages." New: "The current `_retained` columns hold `H_L` from the run start, or from the start of a new segment after a legacy restart, so a window is `_retained(b) − _retained(a)`. `_attempted` counts all calls, including discarded stages. Under the rain/snow key a tag's `led_fix_<name>_attempted` also counts moves between its own parts." Old: "Neither is a provenance error or bound." New: "Neither is an origin error or bound." Old: "Record fix/follower, rescale" New: "Record fix, the correction after each solve (`led_inc`), rescale"
- C16 (O5) :1040. Old: "uses actual rain/snow tagged donor fluxes" New: "uses the bottom-level sedimentation fluxes of the tag's rain and snow parts, plus its share of the non-precipitating water times the cloud liquid and ice fluxes"
- C17 (O1, F10) :1041. Old: "`P_i[a,b] = -Σ_n Δt_n Σ_s b_s pr_i(n,s)`, kg m^-2, using **accepted applied stage weights** of the corresponding explicit/implicit flux update; rejected evaluations count no applied amount." New: "The exact observable is the applied amount `P_i[a,b] = -Σ_n Δt_n Σ_s b_s p_i(n,s)`, kg m^-2, over accepted steps n. `b_s` are the weights of the tableau part that steps the 0M rain-out: `b_imp` under `implicit_microphysics: true` (the default and the TRMM pilot, ARS222 `b_imp ≈ (0, 0.707, 0.293)`), `b_exp` otherwise. `p_i(n,s)` is the column integral of the tendency the stepper applied at stage s, not the rate at the stage state. For an implicit stage it is the Newton-implied `(U_s − Û_s)/(Δt a_ss)`, which with a fixed Newton count differs from the evaluated rate and mixes every implicit process. No current output provides it. The parent budget's `impl.microphysics_removal_0m` row measures the parent's applied amount but refuses EDMF. Some weights are negative (ARS222 `b_exp ≈ (−0.707, 1.707, 0)`, ARS343 `b ≈ (0, 1.208, −0.644, 0.436)`), so a step can apply an upward amount while every stage rate is downward. Split signs per accepted step and cell, after weighting. Rejected evaluations count no applied amount. The current `reduction_time: average` is the mean of the step-end rates, a right-endpoint quadrature."
- C18 (F13) :1060, after "[`tag_throughput.jl` (link as in the document)." Add: " The negative-water latch is written and restored in `tag_closure_checkpoint.jl`."
- C19 (F3) after :1070 ("…integration and restart conventions."). Add: " The matrix routes the approved rows. Conditions it adds beyond the approved register are proposals, waiting for the owner (DECISIONS, WA-GATES)."
- C20 (F1) :1081. Old: "it is never a pass." New: "it is never a pass. OD3's per-tag intervention row (2026-09-25) is the approved source of this disposition." :1083-1084. Old: "Missing required data, non-finite input, incomplete run or misaligned timestamps/labels is a **data/execution failure**." New: "Missing required data, non-finite input, an incomplete run or misaligned timestamps/labels **fails** the affected row and the reproducibility row (6.1, 2026-09-23: "a non-finite value or a missing hour is a failure"). Label it a data/execution failure, so that it is not read as a scientific negative result."
- C21 (F21) :1094. Old: "affected provenance becomes not assessable" New: "affected origin rows become not assessable"
- C22 (F14) :1095. Old: "Six-hour R4 is a historical baseline reading, not a new 24-hour waiver." New: "W58's six-hour R4 pass stands as recorded. It is not criterion 4's 24-hour verdict and waives nothing."
- C23 (F3, F21) :1099. Old: "incomplete cancellation/leg accounting blocks an accounted/qualified claim. Signed or cell-step net cannot establish low total activity or a provenance bound." New: "incomplete cancellation/leg accounting blocks an accounted/qualified claim if the owner accepts WA-GATES (a). Until then it is a reported limitation. Signed or cell-step net cannot establish low total activity or an origin error bound."
- C24 (F1, F21) :1100. Old: "Report current evidence with limitation; missing accumulation is a data gap, wrong sum an accounting defect. No provenance pass from exact sum." New: "Report current evidence with its limitation. The window-integrated row is not assessable until Parts 4/5 supply the accumulation, which the current overlay does not request. A wrong sum is an accounting defect. An exact sum gives no origin pass."
- C25 (F15) :1105. Old: "W52's recorded cost failures stand." New: "Criterion 10's recorded failure stands (E88's 8 + 8 step and OD3's copies row). W52 is the water half."
- C26 (F3) :1112-1115. Old: "pass in every required row at every required tag/time/rung, complete cancellation-safe accounting, eligible independent coverage of all material active rules, reproducibility, measured acceptable cost and applicable held-out evidence." New: "pass in every required row at every required tag/time/rung, reproducibility, measured acceptable cost and applicable held-out evidence. Part 2 proposes two more conditions, waiting for the owner (DECISIONS, WA-GATES): complete cancellation-safe accounting, and eligible independent coverage of all material active rules."
- C27 (F20) :1142. Old: "source/bracket, rain-out composition assumptions" New: "the attributed-process source rule, rain-out composition assumptions"
- C28 (F21) :1145 Old: "No eligible provenance judgment" New: "No eligible origin judgment". :1160 Old: "fabricated provenance pass" New: "fabricated origin pass". :1190 Old: "It does not relax provenance," New: "It does not relax origin rows,"
- C29 (F15) :1191. Old: "W52 cost failures stand." New: "Criterion 10's recorded cost failure stands (E88)."
- C30 (F14) :1226-1227. Old: "records historical TRMM six-hour R4/R5/R8 readings," New: "scored W58's six-hour R4/R5/R8 passes,"
- C31 (O3, O4, F11) after :1232 ("…distinguish a data failure."). Add: " It divides R4 and R8's aggregate by the closure CSV's `total`, the partition target T+, not raw M. Its `thickness()` is exact only on a uniform grid: 0.19% off for a water column on a 60-level stretched grid. The audit's `_relative` columns are over the audit scale T+, and they read zero where that scale is zero."
- C32 (F18, F19) after :1237. Add a paragraph: "PR #146, if merged, changes rows here. A closing step brings each tag's rain and snow parts to their compartment after the correction after each solve. Their compartment closure then holds by construction and is no attribution evidence. The PR adds the ledger `q_tag_led_close`, which the intervention row must then include. It also reorders the rescale's legs, and under the rain/snow key it changes the tags' hyperdiffusion. Re-read the closure, intervention and precipitation-origin rows when it merges."
- C33 (F6, owner) :1239-1241. Old: "owner choice and downstream evidence destination, and independent review findings are resolved." New: "owner choice and downstream evidence destination, proposes a value with its rationale for each missing use-specific tolerance or records the owner's deferral of it (ROADMAP, Part 2), and independent review findings are resolved."

G3_TODO.md

- C34 (F2) :10-11. Old: "is documented and independently reviewed. Next:" New: "is drafted. Its independent review is pending. Next:"
- C35 (F2) :35-38. Old: "- [x] **Part 2 documentation:** independent actual-diff review completed, findings resolved, and links, equations/units, all twelve dispositions and approved-criteria/threshold/crosswalk preservation checked. This completion qualifies no water claim; the owner and evidence gates below stay open." New: "- [ ] **Part 2 documentation:** drafted in PR #148. Links and crosswalk pointers pass the mechanical checks. Open: the independent review of the actual diff and the resolution of its findings. Completion will qualify no water claim. The owner and evidence gates below stay open."
- C36 (F14) :50. Old: "Preserve current six-hour R4/R5/R8 readings and reported R7/C7 as history." New: "Preserve W58's recorded six-hour R4/R5/R8 passes and its reported R7/C7."
- C37 (F15) :73. Old: "W52's cost failures are not closed here." New: "Criterion 10's recorded cost failure (E88's 8 + 8 point) is not closed here."

ROADMAP.md

- C38 (F3) :148. Old: "The authoritative water observables, equations, required evidence and" New: "The water observables, equations, required evidence and". After the sentence that ends at :150, add: " Conditions beyond the approved register wait for the owner (DECISIONS, WA-GATES)."
- C39 (F4) :156. Old: "Reuse TRMM_LBA 0M's six-hour, three-tracer baseline as the first pilot." New: "Part 2 proposes TRMM_LBA 0M's six-hour, three-tracer baseline as the first pilot (WA-SCOPE, waiting)."
- C40 (F21) :160 Old: "with provenance reported only" New: "with origins reported only". :169 Old: "provenance differences" New: "origin differences". :173 Old: "without provenance qualification" New: "without origin qualification"
- C41 (O2, F1) :248-251. Old: "This table supplies the common rows; [G3_PLAN's water matrix (link as in the document) supplies water-specific definitions and applicability. M2 and G4.3 to G4.6 retain their own technical specifications and the existing threshold sources." New: "G3_PLAN 6.1, M2 and G4.3 to G4.6 refer to this table and do not restate it. [G3_PLAN's water matrix (link as in the document) maps these rows to water observables and applicability without restating their thresholds (Part 2, proposed). A row that an approved rule excludes is reported as not applicable (OD3, 2026-09-25), never as a pass. Missing or non-finite data fails (G3_PLAN 6.1)."
- C42 (F17) :265-269. Old: "Where no comparator is eligible, convergence, intervention and aggregation are OD5's conditional evidence for its historical "provenance bounded, not validated" verdict. They do not by themselves establish a mathematical error bound or validate origins; preserve the owner wording and the limitation together." New: "Where no comparator is eligible, the convergence, intervention and aggregation rows can bound the default's provenance but not validate it. *Part 2 reading, proposed (DECISIONS, WA-GATES (d)):* these rows are OD5's conditional evidence for its "provenance bounded, not validated" verdict. They do not by themselves establish a mathematical error bound."
- C43 (F1; base text from #147, apply there or here) :728. Old: "Missing data/reference produces not assessable, not an omitted row." New: "A missing reference produces not assessable. Missing or non-finite data fails (G3_PLAN 6.1, 2026-09-23). Neither is an omitted row."

STATUS.md

- C44 (F4, F5) :14. Old: "| Water, TRMM_LBA 0M entry/source inventory pilot, Float64 / three tracers / six hours | Level 0: label meanings/configuration documented in Part 2." New: "| Water, TRMM_LBA 0M entry/source inventory pilot (proposed, WA-SCOPE), Float64 / three tracers / six hours | Level 0 in part: label meanings, observable and configuration documented in Part 2. The intended use waits for WA-SCOPE."
- C45 (F2) :31-32. Old: "Independent actual-diff review and consistency validation are complete; the two normalization/target findings were resolved." New: "The independent review of the actual diff is pending. Part 2 is recorded complete only after its findings are resolved."

PLAN_CROSSWALK.md

- C46 (F1) :2204. Old: "Missing data/ratios fail as data; scientific missing prerequisites are not assessable." New: "Missing or non-finite data fails (6.1, 2026-09-23) and is labelled a data failure. A missing scientific prerequisite is not assessable."
- C47 (F21) :2210. Old: "not provenance or comparator eligibility" New: "not origins or comparator eligibility"

The edits add no semicolons. C5, C19, C23, C26, C38 and C42 change no approved row. They mark the PR's additions as proposals.

### D. Verdict for the owner

#148 can merge after the patches above. It would then be a documentation of proposals with Part 2 left unchecked, and no approved criterion, threshold or historical verdict would change.

The five blocking items are all text fixes: F1, F2, F17, O1 and O2.

- F2 is the premature completion claim.
- F17 and O2 restore two rev. 2 contract sentences that the PR deleted.
- F1 brings the verdict vocabulary back to pass, fail and not assessable, with data failures as fail under your 2026-09-23 rule.
- O1 makes the precipitation window equation honest for the pilot. Under implicit 0M microphysics with one Newton iteration, no current output measures the applied amount, and the parent budget that does refuses EDMF.

Before Part 2 can be recorded complete, or the matrix called canonical, you would need to decide:

1. WA-GATES: whether complete cancellation-safe leg accounting, coverage of all "material" active rules and the stricter copies eligibility become conditions of a qualified water claim (F3, O8).
2. Whether Part 2 must propose values for the missing tolerances, as #147's Part 2 row asks, or may record their deferral (F6).
3. The pilot's scored windows. TRMM's surface flux is near its peak at 6 h, and under the approved rules a 6-h run has only the first-hour row. You would also name the case for the eight-tag/24-h alternative (O6, F7).
4. Whether to accept the Part 2 reading of OD5's contract sentence (F17, WA-GATES d).
5. The existing WA-SCOPE, WA-PRECIP and WA-COST items.

Under the owner's rules, the merge itself also waits for you.

## PR #149: the energy acceptance contract

Head 5dd23a830 (S/wt149), base `origin/codex/water-acceptance-part2`. CC = `experiments/tag_closure/design/G4_CLAIM_CONTRACTS.md`.
EST = `src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl`, TT = `tag_throughput.jl`, PR = `process_record.jl`.
Checked by computation, with scripts in S/checks/o149 that read the archived E87 NetCDF/CSV output at `$SCRATCH/tag_closure/output/g46_d4_budget{,_2c}/output_0000`:
O1 (c·M_U against surface precipitation), `B(2c)−B(c)`, the decomposition of the record-based estimate, the sign of `pr`, and Θx(2c)/Θx(c) (F19).
Everything else was checked by reading the code at the head and the base. No simulation was run.

### A. First-pass findings

| id | verdict | class | statement |
|:--|:--|:--|:--|
| F1 | CONFIRMED | blocking | Base reporting item 4 ("least favourable number…; the bound rather than a cause…") is gone from CC, ROADMAP, G3_PLAN and DECISIONS. Restore it in section 5 (C34). |
| F2 | MODIFIED | blocking | D4 identities I and II take `cΔρ` from the source ledgers and the c/2c pair, so they need no restriction. Only D4's third C4 measure (D4_PROCESS_BUDGET.md:76-78) and E87's sentence "the process records do not bracket it either" use water as mass. CC:232-233 then cites that estimate's sign as evidence, which contradicts CC:65-73. Fix with C8 and C22. |
| F3 | CONFIRMED | patch | `B` means the parent-budget stock (CC:208), D4's `Σ_P L_src+L_R` (CC:222-223, 231) and the burden `B_k` (CC:396). Rename D4's to `B_src` (C20, C22). |
| F4 | CONFIRMED | patch | Contract and code use `R_parent` and `Q_final_map` (contract.md:94, transaction.jl:11). CC:208 and CC:468 use `R_update` and `Q_map` (C18, C36). |
| F5 | MODIFIED | blocking | CC:65-66 defines "a bracket" as `δp(ρe_tot)+cδp(ρ)` for every consumer. CC:190 then says the record integrates "the signed bracketed energy rate". The record integrates the `ρe_tot` difference only (PR:189-190, no `ρ` term). The record also differences `ρq_tot`, never `ρ`. For surface_flux or microphysics records the stated equation is wrong. Fix with C7 and C17. |
| F6 | CONFIRMED | patch | `test/process_record_integration.jl` runs the pilot column (0M, DYCOMS radiation, 30 uniform layers, dt 10 s, no tags) for two steps with radiation and surface_flux records. It checks `isequal` on every Y.c/Y.f field, checkpoint restoration (`==`, `!all(iszero)`) and zero allocations. CC:280-283 and STATUS:18 call parity and restart simply "missing" (C27, C43). |
| F7 | CONFIRMED | patch | CC 4.4 covers tag accumulators only. Records are Y fields, and `energy_source_checkpoint.jl:168-177` refuses a restart file without them. Say what applies to the pilot (C33). |
| F8 | CONFIRMED | patch | Repair acts only where `E_c>0` (EST:1231-1233, 1247-1248). "rescales positives to preserve their pre-repair sum" also misreads the factor, which keeps the partition's sum (C15). |
| F9 | CONFIRMED | patch | STATUS:61-62 "no Part 3 branch/commit or publication is claimed" is stale once the PR exists (C44). |
| F10 | CONFIRMED | patch | New prose uses "bracket(ed)" at CC:18, 65, 93, 97, 112, 156, 190, 226, 229-230, 261, 264 and PLAN_CROSSWALK:2232. The adopted words are attributed process and applied-update event (C2, C11-C13, C21, C23, C24, C51). |
| F11 | MODIFIED | nit | The `g411_eligibility.py:106` docstring still says "lower bound". The script's printed label (line ~171) already says "not a bound, E84". CC makes no claim about the docstring, so the fix belongs to Part 4 (C50). |
| F12 | CONFIRMED | patch | `gross_over_throughput = gross_residual(t)/H_x(t)` from run start (energy_source_report.jl:88-90). `throughput_tolerance` checks it. It is neither `ΔG(W)/Θx(W)` nor a 4.3 state report (C30). |
| F13 | CONFIRMED | patch | Per-tag source ledgers are exact at every cadence (TT:505-515 warning text). Only the mechanism ledgers need `step`. "accepted-step cadence are needed" (CC:326) is ambiguous (C29). |
| F14 | CONFIRMED | patch | ROADMAP rows 3, 11a and 11b dropped gate and reuse clauses ("Fixed convention and owner decisions before scored energy tests", "process-budget identities and existing manufactured tests", "Can proceed beside water references", "parent-budget support limitations remain", "quantify dominant … effects"). Restore them (C39-C42). |
| F15 | CONFIRMED | patch | The anchors for E22's 7.1e-8 (FINDINGS:4164) and E71's +152/+177% (od4_denominator_audit.md:15) are gone from the contract (C4, C9). |
| F16 | CONFIRMED | patch | The claim levels 1-4 and "Level 6 excluded" (contract.md:39-43) and the registry row `map.repair_energy_source_tags` (coverage_registry.jl:1282-1291, invariant zero ×3) were dropped (C15, C19). |
| F17 | MODIFIED | owner | It was not low-confidence. The column pair's `M_U` contains sedimentation's surface mass exit by construction, and on E87 it is almost all of it. See O1. |
| F18 | MODIFIED | patch | CC:276-277 already mentions the parent-budget radiation coverage. Make it concrete: `xfer.radiation_toa` and `xfer.radiation_surface` (coverage_registry.jl:1352-1389) give an accepted-weight column check of the record's integration from the model's own flux. That flux is shared, so the check is not independent physics (C26). |
| F19 | MODIFIED | owner | CC:78-80 is right. The accumulator (TT:604-605, 1150-1159) has no `c`. Its inputs do: `offset*(Yₜ.c.ρ−ᶜρ_snapshot)` (EST:1031) and shares over `ρe_tot+cρ` (EST:838-840). Measured on E87's pair: Θx(2c)/Θx(c) = 1.0167 at 1, 6 and 24 h and over the 1-24 h window. Θi and the runtime fallback contain no `c`, so the interim is the offset-invariant one. Whether to annotate the register's OD4 question title is the owner's call (C10). |
| F20 | CONFIRMED | owner | DECISIONS:5-7 names a review model and states an owner authorization inside the owner's register. The owner confirms or rewords it (C45). |
| F21 | MODIFIED | patch | Section 3 is already headed "Recommendation, awaiting EA-USE". One closing sentence removes the imperative ambiguity. No decision is needed (C28). |
| F22 | MODIFIED | nit | Symbol collisions confirmed. The serious one, two different A5s, is raised separately as O3. Also "C4" names both an experiment (`c4_sphere_tag_offset`, beside C3/C5) and the limitation. |
| F23 | CONFIRMED | patch | "provenance" appears in new prose at CC:11, 19, 24, 286-287, 425, 433, 495 and 541. Row names ("Provenance, per tag", OD5's label) stay as they are (C1, C3, C5, C28, C31, C32, C37, C38). |
| F24 | MODIFIED | owner | OD2's approved row "DYCOMS 0M" lists no established window (ROADMAP:568). The pilot's 24 h scored window is therefore itself an EA-USE choice. Say so (C25, C46). |
| F25 | CONFIRMED | nit | Zero-norm returns zero (EST:1451). The wording is accurate. No edit. |
| F26 | CONFIRMED | nit | `tag_ledger_normalization` (TT:974-1008) does exist. The G4_TODO rewording is accurate. No edit. |

### B. Own findings

| id | verdict | class | statement |
|:--|:--|:--|:--|
| O1 | NEW | owner (text: blocking-grade, C8/C14/C22/C47-C49) | **E87's C4 is the offset part of the surface precipitation.** From the archived E87 output: `B(2c)−B(c) = c·3.21305 kg m⁻²`, which equals `q_prc_surface_flux` exactly. `ΔM = 2.17279`, so `M_U = −1.04026 kg m⁻²` and `c·M_U = −1.1494e5` (E87's number). The day's surface precipitation (24 × `pr_1h_average`) is `−1.03829 kg m⁻²`, a 0.19% difference. Sedimentation is not attributed for the source tags (implicit_tendency.jl:375-386), but the tags' sedimentation flux is `−wq(e_int+Φ+K+c)` (EST:1505-1521, "adds nothing to `e_src_res`"). So the tags already carry that `cF_M` as transport. This is why A5 (the follower's `I`) saw only −28 J m⁻². Mass moved inside the column (diffusion, sponge, hyperdiffusion, implicit ρ advection) integrates to zero over the column, so the column pair cannot see the genuine C4 at all. Its evidence is identity II per layer and `I(2c)−I(c)`. CC:229-235, DECISIONS:21-25, G4_TODO:99 and the OD9-11 row ("C4 prevent …") repeat E87's reading without this. The decided treatment (document the size) can stand, but the reading of E87 needs the owner. |
| O2 | NEW | patch | `process_budget.py` treats `pr` as positive downward (comment, and `+ Σ pr dt`). ClimaAtmos `pr` is negative for falling precipitation (microphysics_cache.jl:1342, `sfc_ρ·q·(−w)`; archived day −1.038 kg m⁻²). The record estimate therefore subtracted P instead of adding it. E87's +1.06e4 = c·(ΔM − Σq_prc + ∫pr) decomposes as c·(−P − P₂₃ − q_subs) = c·(−1.040 − 0.999 + 2.135), with P₂₃ the 23 hourly averages the script sums. With both the sign and the mass rule corrected, c·(ΔM − q_prc,sfc + P) = −2.2e2 J m⁻² ≈ 0. The script is not in this diff, so route the fix to Part 4 (C50). |
| O3 | NEW | patch | "A5" names two checks. RESIDUAL_REPORT.md §4 uses it for the overlay bound (seven-point point 5, CC:166). D4_PROCESS_BUDGET §4 uses it for C4's two measures (E87's failure, CC:232). DECISIONS:21-25 uses both in one paragraph ("A5 means the partition's sum … failed A5 cross-check"). Qualify each as G4.4's or G4.6's A5 (C16, C47). |
| O4 | NEW | patch | Parity statements (CC:57-59 and the matrix parity row CC:464) omit the fork rule's scope: default solver only, with `use_krylov_method`/`use_newton_rtol` not covered (clima_atmos_specific.md:405). Section 3 does fix the solver for the pilot, but the matrix row applies to "every configured diagnostic" (C6, C35). |
| O5 | NEW | patch | Large-scale advection also writes `ρq_tot` and `ρe_tot` but no `ρ` (large_scale_advection.jl). CC:69 names only subsidence and external forcing. CC:156 should say the tags' sedimentation share carries `cF_M`, which is the code fact behind O1 (C8, C14). |
| O6 | NEW | nit | `analysis/increment/tag_correctness.py:46,58-59` weights layers by `np.gradient(z)` (exact only for uniform grids) and floors denominators at `1e-300`. A zero reference with a zero tag then scores L1 = 0, a pass, while CC:379-380 and CC:422-423 forbid an epsilon denominator and require "undefined" there. CC:434 already says the scorers do not supply the evidence. Route to Part 4 (C50). |

Checked and found correct: E_c and ΔE_c with `cΔρ` (EST:1028-1032). The water-for-mass identity holds only for surface_flux, 0M microphysics, diffusion and sedimentation (same increment to `ρ` and `ρq_tot`) and fails for subsidence, external forcing and large-scale advection. φ = clamp(a/E_c) for E_c>0 (EST:838-840). The loss/gain equation and `L̇_R = (1−ΣM)δ⁺ − (1−Σφ)δ⁻ → −(R/E_c)δ⁻` were checked by hand algebra. a_k(0) = M_k E_c(0). F_c = F_E + cF_M (EST:1505-1521). Θx: cellwise |ΔL| per accepted step over partition source ledgers, NaN on an unverified partition (TT:597-608, 1150-1159; EST:704-711). Θi uses end-of-interval ρ and the seven/four process rosters (od4_restate.py:44-45, 141-151; g411_eligibility.py:42, 116-123). The runtime fallback is Σ_all prc_e ⟨|P|⟩ (EST:735-739). Per-mass outputs are `e_prc`, `q_prc`, state ledgers, `_gross` and `_attempted` (÷ρ(t); PRD:26-28, TLD:62-72, 90-95). `_colgross` is J m⁻² and the negative-water accumulator is per volume. So CC:193-202 is exact in exact arithmetic for "cumulative specific output", given instantaneous outputs (CC:304). D4 identities I and II match D4_PROCESS_BUDGET.md:42-60. ΔG(W)/Θx(W) is unchanged. No OD row, threshold, number or checkbox changed (diff hunks: ROADMAP 181, 247, 774, 782; G4_TODO adds `- [ ]` only; DECISIONS adds at top). The loss check of the 126 lines agrees with the first pass, except as amended by F1, F15 and F16.

### C. Exact edits (old → new). Line numbers are at the head.

**design/G4_CLAIM_CONTRACTS.md**
- C1 L10-11: `does not qualify energy\nprovenance or authorize` → `does not qualify energy\norigins or authorize`
- C2 L18: `increment of the bracketed process, with` → `increment of the attributed process, with`
- C3 L19: `| Tag provenance, energy-source label validity,` → `| Tag origins, energy-source label validity,`
- C4 L23: `E22 measured this separation.` → `E22 measured this separation: where radiation cools most, the radiation tag holds 7.1e-8 of the cell's total.`
- C5 L24: `to produce a provenance error.` → `to produce an origin error.`
- C6 L58-59: `every parent field must remain bitwise identical to the\nsame untagged twin.` → `every parent field must remain bitwise identical to the\nsame untagged twin under the default solver of the [fork parity rule](../../../../docs/clima_atmos_specific.md#fork-parity-with-upstream).`
- C7 L65-69: replace the four lines starting `**Mass is not water.** A bracket differences` and ending `at the same stage, including any final maps.` with:
  `**Mass is not water.** For the source tags, a process's applied-update event gives`
  `` `δp = δp^ρe + c δp^ρ` [J m⁻³ s⁻¹], from its `ρe_tot` and `ρ` tendencies. It does not substitute ``
  `` the total-water tendency `δp^ρq`. A water record may stand for the mass part only ``
  `` after a process-specific discrete proof that `δp^ρ = δp^ρq` at the same stage, including any final maps. ``
- C8 L69-73: `Subsidence and external forcing\ncan change water … remain recorded with this restriction.` →
  `Subsidence, large-scale advection and external forcing change water while their implemented mass contribution is zero. General `c Δρq_tot` accounting is therefore invalid. The original contract's generic water-record substitution is corrected here. D4's identities I and II take `cΔρ` from the attributed processes and the `c`/`2c` pair, so this does not affect them. D4's third C4 measure, `c·(ΔM − Σ_p P_q,p − (−∫pr dt))`, uses the water records as mass, with subsidence among them, so it is not a mass estimate. E87's record-based estimate and its sign are therefore not evidence under this rule. Both files stay as recorded.`
- C9 L77: `the parent trajectory is unchanged (E71).` → `the parent trajectory is unchanged: doubling `c` moved the region tags' integrals by 152% and 177% (E71).`
- C10 L78: `Even the discrete source throughput may change with `c`.` → `The discrete source throughput changes with `c` too. Its accumulator has no `c`, but each ledger increment carries `cΔρ` and each share divides by `E_c`. On E87's D4 pair, Θx at `2c` is 1.7% above Θx at `c` at 1, 6 and 24 h. The records, and so Θi, have no `c`.`
- C11 L93-94: `receives every bracketed\nsource's gain` → `receives every attributed\nsource's gain`
- C12 L97: `and `δp` the bracketed rate,` → `and `δp` the process's tendency of `E_c`,`
- C13 L112: `A bracket contributes` → `An applied-update event contributes`
- C14 L156-157: `` `precipitation` sedimentation is tag transport, not a bracketed tag source;\n0M rainout is the `microphysics` source. `` → `For the energy source tags, `precipitation` sedimentation is transport, not an attributed source. The tags' share of its flux is `F_E + cF_M`, so the offset leaves with the falling mass and adds nothing to `e_src_res`. 0M rainout is the `microphysics` source.`
- C15 L161-164: `Partition repair clips negative tags … Neither\nwrites a parent source.` → `Where `E_c > 0`, partition repair clips negative tags and rescales the positive ones so that the partition keeps its pre-repair sum. If that sum is negative it zeroes every tag. There overlay repair clips a negative value and can add overlay inventory. Where `E_c ≤ 0` the tags are left as they are. Neither writes a parent source. The parent budget declares the repair the final map `map.repair_energy_source_tags`, invariant zero for mass, water and energy.`
- C16 L166: `A5's decided bound compares each overlay with the **partition's sum**.` → `G4.4's A5, as decided, compares each overlay with the **partition's sum**. G4.6's A5 is a different check: C4's two measures (below).`
- C17 L190-191: `Its tendency is the signed bracketed\nenergy rate, integrated by the actual stage weights.` → `Its tendency is `δp^ρe` alone, the process's signed `ρe_tot` tendency without `c δp^ρ`, integrated by the actual stage weights. For a mass-changing process `ΔP_p` is therefore not the tags' `∫δp`.`
- C18 L208: `` `R_update = ΔB − Σ_channels Q_envelope − Σ_maps Q_map` `` → `` `R_parent = ΔB − Σ_channels Q_envelope − Σ_maps Q_final_map` ``
- C19 L212: `The parent budget's energy is `ρe_tot`, without `cρ`.` → `The parent budget's energy is `ρe_tot`, without `cρ`. It claims levels 1 to 4 of its contract. Level 6, attribution to an origin, is excluded there.`
- C20 L222-223: `` `ΔE_c = ΔB + ΔP_e,precipitation + c M_U + X_I`.\n`B = Σ_P L_src,k + L_R`; `` → `` `ΔE_c = ΔB_src + ΔP_e,precipitation + c M_U + X_I`.\n`B_src = Σ_P L_src,k + L_R` (`B` in D4_PROCESS_BUDGET); ``
- C21 L226: `includes unbracketed energy/implicit lag` → `includes unattributed energy and the implicit lag`
- C22 L229-235: replace the paragraph `C4 is the unbracketed … present the historical number as a bound.` with:
  `C4 is `c` times the mass change of processes the tags do not attribute. With bitwise-identical parents and complete attributed sums, the `c`/`2c` pair gives `cM_U = cΔM − [ΔB_src(2c) − ΔB_src(c)]`. Over a column, `M_U` holds every mass change outside an attributed process. That includes sedimentation's exit through the surface, whose `cF_M` the tags carry as transport. Mass moved inside the column integrates to zero there, so per-layer evidence (identity II and `I(2c) − I(c)`) is needed for it. E87 found −1.15e5 J m⁻²/day, 0.55% of the day's Θx, and its G4.6 A5 check failed. On E87's archived output `M_U` is −1.040 kg m⁻² and the day's surface precipitation −1.038 kg m⁻², so that size is almost entirely the precipitation's offset. This reading is waiting for the owner (DECISIONS, EA-C4). The owner decided 2026-10-02 to document C4's size, not distribute it as transport. Repeat the measurement on the stated post-#139 case with `c·∫pr dt` separated. Never present the historical number as a bound.`
- C23 L261: `A copied bracket is not independent;` → `A copied applied-update event is not independent;`
- C24 L263-264: `verifies the\nbracketing/integration,` → `verifies the\nevent capture and integration,`
- C25 L267-269: `Use OD2's untagged-parent startup rule, report startup separately, score the\nestablished window only if it exists, and include the decided 1 h sensitivity\nrow.` → `Use OD2's untagged-parent startup rule, report startup separately and include the decided 1 h sensitivity row. Score the established window only if it exists. OD2's approved DYCOMS 0M row lists none, so EA-USE also fixes the scored window.`
- C26 L276-277: `The parent-budget radiation coverage must be checked separately\nif a later baseline enables it; this initial workflow does not require it.` → `The parent budget's flux-form legs `xfer.radiation_toa` and `xfer.radiation_surface` already measure the accepted column exchange from the model's own flux. Part 11a may reuse them to check the record's integration and weights. They share the model's flux, so they do not verify the radiation parameterization. This initial workflow does not require them.`
- C27 L280-283: `Missing: current parity,\nrecord-versus-independent-flux evidence, sampling/refinement floor, restart,\naccuracy rationale and cost for this workflow.` → `` `test/process_record_integration.jl` runs this column with radiation and surface-flux records and no tags for two steps. It checks `isequal` parity of every model field, the records' checkpoint restoration and zero allocations. Missing for this workflow: 24 h parity, record-versus-independent-flux evidence, sampling/refinement floor, continuous-versus-restarted continuity, accuracy rationale and cost. ``
- C28 L286-287: `source-provenance goal` → `source-origin goal`. `a stored-provenance pass.` → `a stored-origin pass. Every setting in this section belongs to the EA-USE proposal, not to a decided configuration.`
- C29 L325-326: ``finite values,\n`energy_source_tag_ledger_per_tag: true` and accepted-step cadence are needed.`` → ``finite values and `energy_source_tag_ledger_per_tag: true` are needed. Each tag's own source ledger is exact at every `update_constrain_state_every` cadence. Only the mechanism ledgers need `step`.``
- C30 L371: `application of the approved growth tolerance. **EA-STATE**` → `application of the approved growth tolerance. The closure table's `gross_over_throughput`, which `throughput_tolerance` checks, is `G(t)/H_x(t)` from the run start, which is neither reading. **EA-STATE**`
- C31 L425: `This provenance cutoff` → `This origin-row cutoff`
- C32 L433: `not a provenance pass;` → `not an origin pass;`
- C33 L448: append after `continuous/restarted qualification evidence.`: ` For the record-only pilot only the records apply. They are prognostic fields that the checkpoint restores, and a restart refuses a file that lacks a configured record (`energy_source_checkpoint.jl`). Its continuity evidence is a continuous-versus-restarted comparison of `prc_e_radiation` and the parent.`
- C34 L457: append after `owner approvals before the deciding evidence.`: ` Where a row has a choice of number, such as a window, arm, rung or tag, it reports the least favourable one. Where a control changes more than one thing, it reports the bound the control sets, not a cause.`
- C35 L464: `Fork parity rule and OD3 parity; diagnostics must leave parent unchanged.` → `Fork parity rule, under its default solver (fixed Newton count, direct block solve), and OD3 parity; diagnostics must leave parent unchanged.`
- C36 L468: `` | `R_update`, `R_attribution` in 2.4 `` → `` | `R_parent`, `R_attribution` in 2.4 ``
- C37 L495: `real atmospheric provenance.` → `real atmospheric origins.`
- C38 L541: `a provenance accuracy tolerance.` → `an origin accuracy tolerance.`

**ROADMAP.md**
- C39 L777, row 3 gate: `Missing scientific choices/evidence stay blocked; no code or runs. |` → `Missing scientific choices/evidence stay blocked; no code or runs. Fixed convention and owner decisions before scored energy tests. No automatic inheritance of water's rules. |`
- C40 L785, row 11a: `fixed-convention tests; reuse G4.7/8 and PX22. |` → `fixed-convention tests; reuse G4.7/8, PX22, process-budget identities and existing manufactured tests. |`
- C41 L785, row 11a gate: `the record-only pilot does not inherit source-tag gates. |` → `the record-only pilot does not inherit source-tag gates. Can proceed beside water references. Parent-budget support limitations remain. |`
- C42 L786, row 11b: `eligible references and cost. |` → `eligible references and cost. Quantify dominant signed-process, source-attribution and convention effects. |`

**STATUS.md**
- C43 L18: `No current workflow parity, independent accepted-stage flux, reference floor, restart or measured cost;` → `No 24 h workflow parity (a two-step integration test covers parity and checkpoint restoration), independent accepted-stage flux, reference floor, restart continuity or measured cost;`
- C44 L60-62: `No local checkout\nexists in this execution; original and revised files are separately\nmaterialized, and no Part 3 branch/commit or publication is claimed.` → `Part 3 itself is the branch `codex/energy-acceptance-part3`, stacked on Part 2.`

**DECISIONS.md** (the owner's record: C45 needs the owner's wording, and C48 is a waiting proposal)
- C45 L5-7: `The owner authorized the Part 3 handout's execution and independent review\nwith GPT-6.1 Sol, max reasoning. This authorizes documentation preparation;\nno scientific tolerance/default/run/publication is approved by that request.` → `The user authorized preparation and independent review of the Part 3 energy documentation. This approves no scientific tolerance, default, run or publication.`
- C46 L13, EA-USE row: `startup existence and restart evidence remain missing.` → `startup existence and restart evidence remain missing. OD2's approved DYCOMS 0M row lists no established window, so the scored window is part of this choice.`
- C47 L21-25: `A5 means the partition's sum` → `G4.4's A5 means the partition's sum`. `C4's per-tag outflow and failed A5 cross-check remain evidence gaps.` → `C4's per-tag outflow and the failed G4.6 A5 cross-check remain evidence gaps. EA-C4 proposes how E87's size is read.`
- C48 new row after the Seven-point row: `| **EA-C4:** Is E87's C4 size read as the offset of the surface precipitation, which the tags carry by sedimentation transport, rather than as unattributed mass change? | Recommend recording that reading as an amendment to E87, keeping the decided treatment (document the size), and repeating the post-#139 measurement with `c·∫pr dt` separated and per-layer evidence for internal unattributed mass changes. Simpler alternative: keep E87's reading and add only the measured comparison. | Review check on the archived E87 output: `M_U` −1.040 kg m⁻² against −1.038 kg m⁻² of surface precipitation (0.2%). `B(2c)−B(c)` equals `c` times the surface-flux water record exactly. The record estimate counted subsidence water as mass and took `pr` as positive downward, but ClimaAtmos `pr` is negative for falling precipitation. One column, one day, pre-#139 code. | The reading of C4 in G4.6, OD9–11's "C4 prevents" rationale and Part 11b's C4 measurement design. |`

**G4_TODO.md**
- C49 L99: `repeated C4 size and failed-A5 investigation,` → `repeated C4 size with the surface-precipitation offset `c·∫pr dt` separated (EA-C4), the G4.6 A5 investigation,`
- C50 L82: `rescore or approval of a new normalization.` → `rescore or approval of a new normalization. Fix the scripts' known defects first: `process_budget.py` adds `∫pr dt` as if `pr` were positive downward, `tag_correctness.py` weights by `np.gradient(z)` and floors denominators at `1e-300`, and `g411_eligibility.py`'s docstring still calls the interim a lower bound.`

**PLAN_CROSSWALK.md**
- C51 L2232: `explicit implicit/unbracketed remainder` → `explicit implicit and unattributed remainder`

### D. Verdict for the owner

The equations in 2.1-2.4 and the `cΔρ` correction match the code. c multiplies the process's moist-air density tendency (EST:1031), not `ρq_tot`, and the old `cΔρq_tot` form held only where the code writes the same increment to `ρ` and `ρq_tot`. Θx, Θi and the runtime fallback are described as the code computes them. The per-mass differencing rule is exact for the outputs it names. No approved threshold, OD number, window rule or G4 status changed, and the ΔG(W)/Θx(W) growth reading is preserved.

Three blocking items remain, and text fixes all of them:
- F1: a lost reporting rule.
- F5: the record's tendency is stated with the `c` term that the record does not carry.
- F2: CC cites E87's water-record estimate as evidence while its own rule invalidates it.

O1 changes the scientific reading of E87, so I recommend the owner sees it before merge. The C4 size that the contract asks to document and repeat equals, to 0.2%, the offset of the surface precipitation. The source tags already carry that offset by sedimentation transport. The record-based "opposite sign" came from treating subsidence water as mass and from a reversed `pr` sign.

#149 can merge after C1-C51, provided that:
- C22 and C48 keep the O1 reading marked as waiting, so the PR records no new decision;
- the owner confirms or rewrites C45 (F20), the statement about the owner's own authorization;
- the owner accepts C46 and C25 as wording only. The window choice itself stays inside EA-USE (F24).

Still owner choices after merge, all left as proposals: EA-USE, EA-ACCURACY, EA-COST, EA-STATE, EA-C4 (O1), OD7, OD9-11, the seven-point levels, and whether to annotate the OD4 question title "offset-invariant" (F19). On E87's pair the decided Θx moves 1.7% when c doubles, while the interim Θi does not move. The `process_budget.py` sign and the `tag_correctness.py` weights are Part 4 code fixes (C50) and are not part of this PR.
