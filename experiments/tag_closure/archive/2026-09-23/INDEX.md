# The archive of 2026-09-23

The documents of `experiments/tag_closure/` as they were on 2026-09-23, before
the condensing of [CONDENSE_PLAN.md](../../CONDENSE_PLAN.md). Each was moved
here unchanged, with `git mv`, so its history follows it. README.md and
OPERATIONAL_TODO.md were moved the same way, and new files took their old
names. FINDINGS.md is a copy of the record branch's version at `eec7f363`,
since the live FINDINGS.md goes on. Outside the archive, the moved live files
changed in these ways only: links, two of them in
`design/SUBGRID_AND_MICROPHYSICS_DESIGN.md`; a banner sentence in each file in
`reference/`, pointing to ROADMAP, G3_TODO and G4_TODO; and G3_PLAN.md's
sentence on the removed #95 instruction. Nothing here is edited. A committed measurement never changes; a correction goes into the
live FINDINGS.md as a dated erratum.

This index is `INDEX.md` because `README.md` here is the archived operator's
guide itself.

**Links inside these files may point to old paths.** They were written for
`experiments/tag_closure/` and for the file names of the time: for example
`OPERATIONAL_TODO.md`, `G3_WATER_PLAN.md` (now `G3_PLAN.md`), or the design
notes now in `design/`. Read such a link against the two tables below.

| Old path, in `experiments/tag_closure/` | Now |
|:--|:--|
| `G3_WATER_PLAN.md` | [G3_PLAN.md](../../G3_PLAN.md) |
| `ATTRIBUTION_PATH.md`, `TRACER_AND_FLUX.md`, `UPDRAFT_GAP.md`, `SUBGRID_AND_MICROPHYSICS_DESIGN.md` | [design/](../../design/) |
| `repo-operability-pathway.md`, `untapped-potential-assessment-extended.md` | [reference/](../../reference/) |
| `OPERATIONAL_TODO.md` | a stub at the same path, pointing on; the original is here |
| `README.md` | a new operator's guide at the same path; the original is here |
| every other file named below | here |

The branches of that time are kept as tags on origin, among them
`archive/tag-closure-experiments-2026-09-23` and
`archive/g3-programme-2026-09-23`. The run data outside git is in
`~/git/Clima/ClimaAtmosResiDyn-archive/`, described in
[RUNS.md](../../RUNS.md).

| File | What it was | Why archived | Its live content now |
|:--|:--|:--|:--|
| [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md) | the rolling status and to-do list of the energy work: the roadmap, G1 and G2, decisions, the B, S and N items, synergies, Plan A to D | split up | [ROADMAP.md](../../ROADMAP.md), [DECISIONS.md](../../DECISIONS.md), [G4_TODO.md](../../G4_TODO.md), [BACKLOG.md](../../BACKLOG.md), [STATUS.md](../../STATUS.md); a stub at [OPERATIONAL_TODO.md](../../OPERATIONAL_TODO.md) says where each section went |
| [README.md](README.md) | the operator's guide to the harness, for Levante and the owner submitting by hand, with the run tables | replaced by a short terrabyte guide | [README.md](../../README.md); the run tables in [RUNS.md](../../RUNS.md). Levante and the phase A to C details stay here |
| [FINDINGS.md](FINDINGS.md) | the numbered findings as they were | condensed by topic | [FINDINGS.md](../../FINDINGS.md), with the numbering kept |
| [LEARNINGS.md](LEARNINGS.md) | the barrier register, one narrative entry per run, up to job P4 (2026-09-14) | stale | what only it held goes into [FINDINGS.md](../../FINDINGS.md) as short reasons |
| [NEXT_SESSION.md](NEXT_SESSION.md) | the handover of 2026-09-18: reading order, rules, traps, conventions | stale, replaced by later state | [STATUS.md](../../STATUS.md); its conventions and traps in [README.md](../../README.md) |
| [LEVANTE_TASKS.md](LEVANTE_TASKS.md) | the task list up to 2026-09-14: what to run next, PRs of 2026-09-10, known defects | stale | its one open item, LT-4, in [BACKLOG.md](../../BACKLOG.md); its decision of 2026-09-10 in [DECISIONS.md](../../DECISIONS.md) |
| [TODO_REVIEW_2026-09-14.md](TODO_REVIEW_2026-09-14.md) | an agent's review of the remaining-tasks list, 2026-09-14 | its findings were folded into OPERATIONAL_TODO | nothing further |
| [ENTHALPY_AUDIT_DESIGN.md](ENTHALPY_AUDIT_DESIGN.md) | the design of the enthalpy audit switch, with the owner's four decisions of 2026-09-11 | finished, built as #72 | the decisions in [DECISIONS.md](../../DECISIONS.md); the feature in `docs/src/energy_source_tags.md` |
| [RESTART_GUARD_DESIGN.md](RESTART_GUARD_DESIGN.md) | the design of C2, the restart guard | finished, built as #92 | C2's design decision in [DECISIONS.md](../../DECISIONS.md); U7 in [BACKLOG.md](../../BACKLOG.md) |
| [C1_reference_shift.md](C1_reference_shift.md) | the argument and recipe of C1, the reference shift, with a raw-probe appendix | superseded in practice by the tags' offset (C4) | FINDINGS E11 to E16 (C1), E17 to E19 (C4), and section 3, the energy reference |
| [CLIMACORE_ISSUE_DRAFT.md](CLIMACORE_ISSUE_DRAFT.md) | a draft ClimaCore issue on compile-time scaling (E44d, E44e) | a draft, not filed (decision 3 of 2026-09-18) | the item in [BACKLOG.md](../../BACKLOG.md), upstream |
| [UPSTREAM_VWB_PR_DRAFT.md](UPSTREAM_VWB_PR_DRAFT.md) | a draft upstream PR for the vertical-water-borrowing guard | a draft, not opened (decision 12); `dd06318f` stays a named parity exception | [DECISIONS.md](../../DECISIONS.md), 2026-09-18; the tag `archive/upstream-vwb-species-guard` |
| [PARENT_BUDGET_DEFECT_PR.md](PARENT_BUDGET_DEFECT_PR.md) | the PR body of the parent-budget defect test fix (decision 13) | done, merged as #81 | [DECISIONS.md](../../DECISIONS.md), 2026-09-17 |
| [USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md) | a full user's guide draft for the energy source tags and the process records, 2026-09-11 | checked against #95's guide on 2026-09-23 | #95's `docs/src/energy_source_tags_guide.md`; what that does not cover is listed under G4.1 in [G4_TODO.md](../../G4_TODO.md) |

Still to come here: CONDENSE_PLAN.md, once the plan is done, and
`docs/src/tag_closure_memo.md` and `tag_closure_experiments.md`. #97 marked them
historical and has merged. Moving them needs a PR to `main` that also edits
`docs/make.jl` (the owner's decision 6 of 2026-09-23).
