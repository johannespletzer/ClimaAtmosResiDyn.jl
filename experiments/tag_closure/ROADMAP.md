# The roadmap

Moved on 2026-09-23 from the top of OPERATIONAL_TODO.md, whose original is
[archive/2026-09-23/OPERATIONAL_TODO.md](archive/2026-09-23/OPERATIONAL_TODO.md).
Only its pointers were changed. The entry point for a session is
[STATUS.md](STATUS.md).

Set on 2026-09-23. It divides what is left of the owner's goal of 2026-09-10
into milestones M0 to M8. The milestones come from
[reference/repo-operability-pathway.md](reference/repo-operability-pathway.md),
a review of 2026-09-21 that is kept as written. Its reasoning is in
[reference/untapped-potential-assessment-extended.md](reference/untapped-potential-assessment-extended.md).
The status lives here and in [STATUS.md](STATUS.md), not in those two files.

**Operational** means, in the pathway's words, that a declared configuration:
runs reproducibly; leaves the parent atmosphere unchanged by the diagnostics,
within the parity contract; meets independently justified scientific
criteria; and has a measured, affordable cost. It does not mean that every
configuration upstream supports has been validated for every diagnostic.

**Two families walk the milestones in turn.** The owner decided on 2026-09-23:
- the tagged water tracers go first, as G3, and become operational in the
  production configuration, a sphere with EDMF and 1M;
- the energy source tags follow, as G4, with what G3 learns.

Water has a true reference under EDMF, exact mass bookkeeping, and no offset
or sign problem. So the shared machinery is qualified there first. The
process records go with the energy family in G4.

| Milestone | Outcome | Water tags (G3) | Energy source tags (G4) |
|:--|:--|:--|:--|
| M0 | Every result traceable: manifests, a verifier, a run inventory, archived data | the tools are built (verifier, mutation tests, manifest, inventory) and serve both families; review open (G3 WP0) | uses G3's tools |
| M1 | Correctness gaps closed, claims narrowed | refusals, known issues, EDMF support in both modes, restarts, a file-based start (G3 WP1, WP3, V-W8, V-W9) | #95: R3 to R6 fixed in `e71430fb`, R1 in `dbe7435c`; the partition-only factor is in `dcf7d086`, and #95 is open at `afd470e7` (G4.1) |
| M2 | A claim contract per family, independent accounting, gross diagnostics | closure on D4-W, the copies' residual, leaks named; gross accumulators for both families (G3 WP3, WP6) | the process budget, the residual report, warnings apart from acceptance (G4.3 to G4.6) |
| M3 | A suite of small reference cases, each converged | D4-W and TRMM 0M, the ladder, Float32 (G3 V-W3, V-W4, V-W7) | the R2 ladder is done (E76); the ladder at #95's merged head and the rest wait (G4.7, G4.8) |
| M4 | Cost measured and budgeted | both families, both modes (G3 WP9) | from G3 |
| M5 | The mixing closure and precipitation provenance chosen by experiment | exchange against copies, the follower's default, the 0M split, rain and snow tags, held-out columns (G3 WP5, WP4a, WP4b, V-W5, V-W6) | offset, placement variants, carried-over design, held-out columns, the energy default (G4.9 to G4.12) |
| sphere | Ten days in the production configuration | V-W11 | G4.13 |
| M6 | Devices, precision, input data and restarts at scale | not started; the GPU decision belongs here | not started |
| M7 | A production trial and a supported envelope | not started | not started |
| M8 | Extensions: air age, memory and forecasts | — | memory number (G4.14); the rest later |

The goals after G4 are sketched, not approved. Each needs the owner. The
plan for G3 is [G3_PLAN.md](G3_PLAN.md), reviewed and finalised, and its
to-do list is [G3_TODO.md](G3_TODO.md). G4's items are in
[G4_TODO.md](G4_TODO.md).

G1 and G2 were met before the roadmap existed. They covered parts of M1, M3
and M5 for the energy tags on D4 and on the sphere (E62 to E75), and their
numbers enter M0's inventory as historical results. The pathway puts M4
before M5. G3 reverses that: it chooses the closure on columns, where runs
are cheap, and measures the cost before its sphere run.

## Where the open items go

An agent matched every open item of OPERATIONAL_TODO's sections 2 to 7 and of
its Plan to a milestone on 2026-09-23. This session checked the doubtful ones.
Items marked "G3 …" are in [G3_TODO.md](G3_TODO.md), and items marked "G4.n"
in [G4_TODO.md](G4_TODO.md). The rest wait for a later goal or lie outside the
roadmap. They are in [BACKLOG.md](BACKLOG.md), except the energy items within
M1 to M5, which are at the end of G4_TODO.md. Each keeps its original ID there.
Beware of reused names:
- the milestones M3 to M5 are not the N items M3 to M5 of the archived
  OPERATIONAL_TODO's section 4;
- PR #95's review items R1 to R6 are not this list's R items;
- G3's work packages WP0 to WP9 are not the water findings W1 to W14.

| Milestone | Open items |
|:--|:--|
| M0 | synergy 2, the Float64 twin (G3 WP0); synergy 1, the early warning (G4.2); `analysis/phase_c.jl`, which reads only `c*` runs, is replaced by the verifier (done) |
| M1 | the file-based run of item 14, B14 (G3 V-W8, water and energy tags); U5 (G4.1, and G3 WP3 for water); D1 with D3 (G4.1, closes with #95). Later: C6's leftovers, a parity test for the stratospheric tracers (P6) |
| M2 | C4 and synergy 6 (G4.6); synergy 5 (G4.14, after G3 WP6); U9, A5 and synergy 4 (G4.4); U2's calibration, item 11 (G4.5). Later: A2's runtime part and A3; the open questions on D1's residual and the sphere's 17%, unless G4.6 names them |
| M3 to M5 | R5 (G3 V-W4 records each rung's cost); U8 (G4.10, while the choice for a winter run belongs to M7); P2 and P3 (G3 WP9). Later: A4, A6, C7, P7's optional fix. C1c stays shelved, since the increment prototype replaced it |
| M6 | MP1 on more than one node, U6, the model's own restart drift (E58), the GPU (item 13) |
| M8 | ice provenance where ice lasts (open question 3), C1d, U7. Synergy 3, the water tags in the updrafts, is now G3 itself |
| outside | upstream: the ClimaCore issue, P5, the `ShipwayHill2012VelocityProfile` report, the N items M4 and M5 (2M and P3); CI: P8, Plan A.2's manual run; too terse to place: open question 4 |

**Done, not yet struck through in the archived OPERATIONAL_TODO:**
 - C1b (#91) and C2 (#92), in section 2, items 4 and 5;
 - V2 (E74, E75), in item 10;
 - item 15 (#93);
 - B9 and the items bundled with it (#77);
 - T6: `test/energy_source_tags_edmf_integration.jl` on `main` checks the
   partition against the parent to 100 eps;
 - the N item M3: `test/tracer_processes_tests.jl` on `main`;
 - Plan A.1 (G1 is met), A.3 (questions 2 and 3, decided on 2026-09-19), A.4's
   NaN decision (fixed on 2026-09-20), and C.4 (V2 and V6 ran).

They are not carried into G4_TODO.md or BACKLOG.md. The archived original
keeps them where they stood.

## The current goal: G3, the water tags under EDMF

The owner set G3 on 2026-09-23 and re-scoped it the same day. The tagged water
tracers are brought to work under prognostic EDMF, in both modes: the exchange
by default, updraft copies as the audit. Precipitation provenance is included,
with rain and snow carrying their own tags. The water tags become operational
in the production configuration.

The plan, with twelve criteria, the design, work packages, experiments,
budgets and the review's findings, is [G3_PLAN.md](G3_PLAN.md). The to-do
list is [G3_TODO.md](G3_TODO.md). The owner approved every job within G3, and
the agents listed there.

**The next goal, G4: the energy source tags,** with what G3 learns. Its
items are listed in [G4_TODO.md](G4_TODO.md). The job session carries #95 to its
merge, and runs the ladder at the merged head.
