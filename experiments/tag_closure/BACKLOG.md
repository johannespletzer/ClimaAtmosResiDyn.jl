# Backlog: open items beyond G3 and G4

What is open and belongs to neither G3 ([G3_TODO.md](G3_TODO.md)) nor G4
([G4_TODO.md](G4_TODO.md)): milestones M6 to M8, work that only upstream can
do, CI, and what lies outside the roadmap. The energy items within M1 to M5
that G4 has not taken up are at the end of G4_TODO.md, not here. The
milestones are in [ROADMAP.md](ROADMAP.md).

Each item keeps its original ID. "Register" is its row in
`review/register/items.csv`. Sources: "OT" is the archived
[OPERATIONAL_TODO.md](archive/2026-09-23/OPERATIONAL_TODO.md), "FQ" is an
open question from the archived FINDINGS' section 7, "What is not established"
(the live queue is [FINDINGS section 13](FINDINGS.md#13-what-is-not-established)), "LT" is the archived
[LEVANTE_TASKS.md](archive/2026-09-23/LEVANTE_TASKS.md), and "old README" is
the archived [README.md](archive/2026-09-23/README.md).

Nothing here is approved. Model code, a run or an upstream report each needs
the owner.

## M6: devices, precision, input data and restarts at scale

| ID | Register | Summary | Source |
|:--|:--|:--|:--|
| B13, GPU | `OT-B13`, `OT-PD4` | The GPU, last: run the diagnostic on a GPU in Float32, with T3, and fix what that forces. OT names Levante. On terrabyte the GPU stack is identified but not verified (`runscripts/terrabyte_stacks.env`) | OT section 2, item 13; Plan D.4 |
| MP1 | `OT-B8`, `OT-PD2` | More than one node. MP1 ran on 4 ranks on one node and closed as on one process (E47). More than one node is untested, and not approved (decision 8 of 2026-09-18) | OT section 2, item 8; Plan D.2 |
| U6 | `OT-U5U6`, `OT-B7` | Records in Float64, or reset at each output, for long Float32 runs. Over a day they match Float64 to 4e-4 at 24 h (E45). Float32 runs longer than a day are untested | OT section 4; OT section 2, item 7 |
| E58 | `OT-PA4` | Where the model's own restart of C5's column stops being bit for bit: 0M, the 12 hours, the code before #89, or `reproducible_restart: true`. It is upstream's, not the tags'. Short runs on the login node would separate it | Plan A.4 |
| FQ-23 (GPU) | `FQ-23` | The tag cost on a GPU. The EDMF part is G3 WP9 and V-W10 | archived FINDINGS §7; live: FINDINGS §13 |

## M7: a production trial and a supported envelope

Nothing of M7 is itemised yet. U8's choice of `c` for a winter run belongs
here (ROADMAP). The sweep itself is G4.10.

## M8: extensions

| ID | Register | Summary | Source |
|:--|:--|:--|:--|
| open question 3, FQ-10 | `OT-Q3`, `FQ-10` | How much provenance ice moves upward where ice lasts (deep convection, D5). On D1 it was about a fifth (E42b). Related to G4.11's compartments | OT section 6; FINDINGS section 7 |
| C1d | `OT-C1d` | Option C: per-updraft tag shares, about three times the cost of option B | OT section 4 (shelved) |
| U7 | `OT-U7`, `OT-PA4` | Start tagging from a checkpoint: an explicit start mode, records started at zero, and a guard that accepts a tagless checkpoint in that mode only. Added on 2026-09-18, not to be built now | OT section 4 (shelved); Plan A.4 |

## Upstream only

| ID | Register | Summary | Source |
|:--|:--|:--|:--|
| ClimaCore issue | `OT-N-ClimaCore` | ClimaCore's field-name sets check every pair at compile time (E44d). Scaling that down would let #76 use public API only. The draft issue is not filed (decision 3 of 2026-09-18); it is in the archive | OT section 4 (shelved) |
| P5 | `OT-P5` | The explicit tendency's generic tracer loops allocate: 22,576 bytes per call without tags, 58,160 with four, on a 1M column. Shared model code, not tag code | OT section 4 (shelved) |
| ShipwayHill report | `OT-PA4` | Report upstream that `ShipwayHill2012VelocityProfile` fails on `ITime` (E57) | Plan A.4 |
| M4, M5 (N items) | `OT-M4M5design` | When 2M returns: D2 and one integration item (M4). When the parent's P3 is fixed: D3 (M5). From SUBGRID_AND_MICROPHYSICS_DESIGN's own list | OT section 4 |
| FQ-13 | `FQ-13` | 2M and P3: the model disables both (E41). By the code the tags need nothing more for 2M than for 1M; P3 has gaps in the parent's own sedimentation. The owner's rule for when the gate lifts is in DECISIONS.md (2026-09-18) | archived FINDINGS §7; live: FINDINGS §13 |

## CI

| ID | Register | Summary | Source |
|:--|:--|:--|:--|
| P8 | `OT-P8` | #89 made CI's test groups 1.4 to 2.1 times slower. Accepted for now by the owner on 2026-09-18. If a group goes over the 90-minute limit: raise the limit, or split the two groups in a PR of their own | OT section 3 (waiting) |
| Plan A.2 | `OT-PA2` | A manual `ci.yml` run on `main`, for #89's review item R1: the upstream groups on Julia 1.10 with the new packages. The owner starts it | Plan A.2 |
| CI phase C | (not in the register) | Phase C of the CI plan on the tagging files, one PR per file, each reviewed by the owner, first `tagged_water_integration.jl`. State as of 2026-09-19 | OT section 0, "CI cost" |

## M0 to M5, not energy-specific

| ID | Register | Summary | Milestone | Source |
|:--|:--|:--|:--|:--|
| `phase_c.jl` | `OT-H-phasec` | `analysis/phase_c.jl` reads only runs named `c*`. ROADMAP counts this done: the verifier replaces it | M0 | OT section 5 |
| P6 | `OT-P6` | Parity checks: the on/off half is merged (#79). The stratospheric passive tracers have no such test. Nothing compares the fork with an upstream checkout, skipped for now (decision of 2026-09-14) | M1 | OT section 4 |
| LT-4 | `LT-4` | Whether to lengthen `test/tagged_water_integration.jl` past A5's onset. The issue-64 fix strengthened the test instead; the coverage gap is narrowed, not closed. Related to G3 WP1's known issue 1 | outside (register) | LT, "0. Checked 2026-09-10"; old README, "Open items" |
| P7 | `OT-P7` | Not a regression (E56). An optional fix saves seconds and is not approved. Before it merges it needs parity on `moist_sphere` and `column_1m`, testset 6 of the source-tag integration file, and a tagged build with water tags. Unexplained: whole parity runs are 5 to 6% slower in the fork | M3 to M5 (ROADMAP) | OT section 3 (shelved); Plan A.4 |
| A2 (water) | `LEARNINGS:A2:1` | Both linear water ladders of phase A are sub-first-order, and `none` stops converging near dt 2.5 s, with a floor near 1e-7 (FINDINGS W1). Candidates are listed, none tested | M3 | `archive/2026-09-23/LEARNINGS.md`, A2 |

## Outside the roadmap: open questions

| ID | Register | Summary | Source |
|:--|:--|:--|:--|
| open question 4 | `OT-Q4` | E14, E16's remainder and E24, the unresolved mechanisms. Too terse to place (ROADMAP) | OT section 6 |
| FQ-3 | `FQ-3` | What is left of E16 once the limiter is off: 3.7e-8 in ρ after one step, growing to 5.8e-6 by 5 h. Not the surface-flux code path | archived FINDINGS §7; live: FINDINGS §13 |
| FQ-4 | `FQ-4` | Why a tag goes negative under a positive parent (E14): the finite-step donor loss or the unlimited explicit transport. E19 points at transport for the region tags | archived FINDINGS §7; live: FINDINGS §13 |
| FQ-5 | `FQ-5` | What makes the residual's first-minute jump (E13, E25). A ledger weighted by the stepper's own stages would split it | archived FINDINGS §7; live: FINDINGS §13 |
| FQ-6 | `FQ-6` | Why C5's radiation tag outgrows C3's after four hours (E24). The runs differ in machine and code | archived FINDINGS §7; live: FINDINGS §13 |
| C3 on a sphere | (not in the register) | Whether C3 also wants a sphere counterpart. As registered it is the column only | old README, "Open items" |

## Code housekeeping, not in the register

From #89's review, as recorded on 2026-09-19 in the archived OPERATIONAL_TODO,
section 0. Not re-checked since.

 - Nits for a follow-up PR: a vacuous `===` test in
   `test/coupler_compatibility.jl`, NEWS's stale Aqua headline, docstrings
   without the tagging keywords, a species list parsed twice, and an unmatched
   `@test_throws`.
 - R3 of that review: the committed `.buildkite` manifest keeps upstream's
   `project_hash`, so every setup rewrites two lines. They stay uncommitted
   unless the owner decides otherwise.
