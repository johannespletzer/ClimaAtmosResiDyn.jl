# Bringing the energy source tags and the process records to operation

The owner's goal, set on 2026-09-10, is to keep both families and make them
operational. This list names what is left. It merges four reviews made on
2026-09-11 (readiness, form A, the leftover residuals, and sub-grid transport
with ice and the other microphysics schemes). On 2026-09-14 it was rebuilt as a
list of what remains, and an Opus agent reviewed it against the repository.
Its findings are folded in; its report is
[TODO_REVIEW_2026-09-14.md](TODO_REVIEW_2026-09-14.md).

Production, as the owner decided on 2026-09-11, is a GPU sphere in Float32,
with EDMF and 1M. The GPU check comes last, once the physics is robust and
complete.

Nothing here is approved unless it says so. Model code, a default, a tolerance,
an energy reference and every run need the owner's approval before they are
written or submitted. The standing approvals of 2026-09-14 are listed under
"Decided".

Priorities: **B** blocks operation, **S** should be fixed, **N** is nice to
have. Sizes: S is under a day, M one to three days, L several PRs or a
campaign.

## The roadmap

Set on 2026-09-23. It divides what is left of the owner's goal of 2026-09-10
into milestones M0 to M8. The milestones come from
[repo-operability-pathway.md](repo-operability-pathway.md), a review of
2026-09-21 that is kept as written. Its reasoning is in
[untapped-potential-assessment-extended.md](untapped-potential-assessment-extended.md).
The status lives here, not in those two files.

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
| M1 | Correctness gaps closed, claims narrowed | refusals, known issues, EDMF support in both modes, restarts, a file-based start (G3 WP1, WP3, V-W8, V-W9) | #95: R3 to R6 fixed in `e71430fb`, R1 in `dbe7435c`; the partition-only factor sent to the job session (G4.1) |
| M2 | A claim contract per family, independent accounting, gross diagnostics | closure on D4-W, the copies' residual, leaks named; gross accumulators for both families (G3 WP3, WP6) | the process budget, the residual report, warnings apart from acceptance (G4.3 to G4.6) |
| M3 | A suite of small reference cases, each converged | D4-W and TRMM 0M, the ladder, Float32 (G3 V-W3, V-W4, V-W7) | the R2 ladder is running in the job session; the rest waits (G4.7, G4.8) |
| M4 | Cost measured and budgeted | both families, both modes (G3 WP9) | from G3 |
| M5 | The mixing closure and precipitation provenance chosen by experiment | exchange against copies, the follower's default, the 0M split, rain and snow tags, held-out columns (G3 WP5, WP4a, WP4b, V-W5, V-W6) | offset, placement variants, carried-over design, held-out columns, the energy default (G4.9 to G4.12) |
| sphere | Ten days in the production configuration | V-W11 | G4.13 |
| M6 | Devices, precision, input data and restarts at scale | not started; the GPU decision belongs here | not started |
| M7 | A production trial and a supported envelope | not started | not started |
| M8 | Extensions: air age, memory and forecasts | — | memory number (G4.14); the rest later |

The goals after G4 are sketched, not approved. Each needs the owner. The
plan for G3 is [G3_WATER_PLAN.md](G3_WATER_PLAN.md), reviewed and finalised,
and its to-do list with G4's items is [G3_TODO.md](G3_TODO.md).

G1 and G2 were met before the roadmap existed. They covered parts of M1, M3
and M5 for the energy tags on D4 and on the sphere (E62 to E75), and their
numbers enter M0's inventory as historical results. The pathway puts M4
before M5. G3 reverses that: it chooses the closure on columns, where runs
are cheap, and measures the cost before its sphere run.

### Where the open items below go

An agent matched every open item of sections 2 to 7 and of the Plan to a
milestone on 2026-09-23. This session checked the doubtful ones. Items marked
"G3 …" or "G4.n" are in `G3_TODO.md`. The rest wait for a later goal or lie
outside the roadmap. Beware of reused names:
- the milestones M3 to M5 are not the N items M3 to M5 of section 4;
- PR #95's review items R1 to R6 are not this list's R items;
- G3's work packages WP0 to WP9 are not the water findings W1 to W14.

| Milestone | Open items |
|:--|:--|
| M0 | synergy 2, the Float64 twin (G3 WP0); synergy 1, the early warning (G4.2); `analysis/phase_c.jl`, which reads only `c*` runs, is replaced by the verifier (done) |
| M1 | the file-based run of item 14 (G3 V-W8, water and energy tags); U5 (G4.1, and G3 WP3 for water); D1 with D3 (G4.1, closes with #95). Later: C6's leftovers, a parity test for the stratospheric tracers (P6) |
| M2 | C4 and synergy 6 (G4.6); synergy 5 (G4.14, after G3 WP6); U9, A5 and synergy 4 (G4.4); U2's calibration, item 11 (G4.5). Later: A2's runtime part and A3; the open questions on D1's residual and the sphere's 17%, unless G4.6 names them |
| M3 to M5 | R5 (G3 V-W4 records each rung's cost); U8 (G4.10, while the choice for a winter run belongs to M7); P2 and P3 (G3 WP9). Later: A4, A6, C7, P7's optional fix. C1c stays shelved, since the increment prototype replaced it |
| M6 | MP1 on more than one node, U6, the model's own restart drift (E58), the GPU (item 13) |
| M8 | ice provenance where ice lasts (open question 3), C1d, U7. Synergy 3, the water tags in the updrafts, is now G3 itself |
| outside | upstream: the ClimaCore issue, P5, the `ShipwayHill2012VelocityProfile` report, the N items M4 and M5 (2M and P3); CI: P8, Plan A.2's manual run; too terse to place: open question 4 |

**Done, not yet struck through below:**
 - C1b (#91) and C2 (#92), in section 2, items 4 and 5;
 - V2 (E74, E75), in item 10;
 - item 15 (#93);
 - B9 and the items bundled with it (#77);
 - T6: `test/energy_source_tags_edmf_integration.jl` on `main` checks the
   partition against the parent to 100 eps;
 - the N item M3: `test/tracer_processes_tests.jl` on `main`;
 - Plan A.1 (G1 is met), A.3 (questions 2 and 3, decided on 2026-09-19), A.4's
   NaN decision (fixed on 2026-09-20), and C.4 (V2 and V6 ran).

Striking them where they stand is left for the next condensing, which is on
hold.

## The current goal: G3, the water tags under EDMF

The owner set G3 on 2026-09-23 and re-scoped it the same day. The tagged water
tracers are brought to work under prognostic EDMF, in both modes: the exchange
by default, updraft copies as the audit. Precipitation provenance is included,
with rain and snow carrying their own tags. The water tags become operational
in the production configuration.

The plan, with twelve criteria, the design, work packages, experiments,
budgets and the review's findings, is [G3_WATER_PLAN.md](G3_WATER_PLAN.md).
The to-do list is [G3_TODO.md](G3_TODO.md). The owner approved every job
within G3, and the agents listed there.

**The next goal, G4: the energy source tags,** with what G3 learns. Its
items are listed at the end of `G3_TODO.md`. The job session continues the
energy work in flight: #95 and the R2 ladder.

## G1, a closed and explained EDMF column (met on 2026-09-20)

Proposed on 2026-09-19, for the owner to confirm. An intermediate goal on the
way to production: the smallest setup that holds every stiff implicit process
production has. That is the EDMF column D4: the DYCOMS RF02 column with one
updraft, 1M microphysics, implicit diffusion and implicit vertical advection,
for a day. A run takes about 40 minutes, and E59 showed the gap there.

**G1 is met when, on D4 under the enthalpy form:**

 1. **Closure.** The gross residual at 24 h is at most 1e4 J/m². Today it is
    6.32e5 (`c1c_base_d4_enthalpy`, E59). It does not grow systematically: the
    second 12 hours add no more than the first.
 2. **The remainder is explained.** What is left is split into named parts:
    the column-integral part, which implicit sources and sinks leave, and each
    process the tags do not yet follow. Each part is reported with its size.
 3. **The model is untouched.** `ta` and `rhoa` are bit for bit those of the
    same run without the change, and a CI test checks the model's fields.
 4. **Correctness is measured, not only closure.** The tags are compared
    pointwise with a reference run that has a converged Newton solve. The
    per-tag difference is reported for `rad`, `sfc`, `sub`, `mp` and the region
    tags. A threshold is set once the first numbers exist (E60 shows why the
    column integral is not enough).
 5. **Float32 holds too.** A Float32 twin meets 1 to 3 within ten times the
    Float64 residual.
 6. **It is reviewed and tested.** An agent's review with its findings fixed,
    unit and integration tests in CI, and a pull request ready for the owner.

**G1's status on 2026-09-19,** with the prototype `enthalpy_increment`:

| # | criterion | status |
|:--|:--|:--|
| 1 | closure ≤ 1e4 J/m², no systematic growth | **met** (E62): 267 J/m² at 24 h; the second 12 h add 75, the first 192 |
| 2 | the remainder in named parts | **met** (E64): the one-iteration solve's column totals, 313 gross, less the loss rule's flushing, +44; nothing else above 1 J/m² |
| 3 | `ta`, `rhoa` bit for bit, and a CI test | **met** (E62, E65); the test is `tagging_source_increment` in #94 (every model field against the column without tags) |
| 4 | per-tag correctness against a converged reference | **met** (E66, E73), threshold set by the owner on 2026-09-20: (a) the one-iteration solve's effect at 1 h, L1 ≤ 1% (region) and ≤ 10% (source), L∞ ≤ 25%, measured 0.1% and 1 to 6%; (b) the default's mixing against the audit's updraft copies at 24 h, L1 ≤ 2% every tag and L∞ ≤ 5%, measured 0.66% and 2.5% |
| 5 | Float32 within 10× | **met** (E65): 607 J/m², bit for bit against the Float32 base |
| 6 | reviewed, tested, PR ready | **met**: review fixed (three blocking findings); unit 630/630 and integration 71/71 locally; **draft PR #94**, which contains #93, with CI all green (67 checks, the new group on 1.10 and 1.11 and in the downgrade jobs, and the docs build); #93 green too (35 checks) |

Decided by the owner on 2026-09-19 (see "Decided"): the hybrid mixing
convention, `c` kept at 110,495 J/kg, and the correction as built. #93 and
#94 are merged. Criterion 4's threshold is asked again once the updraft gap
is closed: one logical, updraft copies (audit) against a zero-sum exchange
(default), UPDRAFT_GAP.md "The chosen way".

**On the way to G2:**
  - #93 must merge before any sphere run; the prototype's branch has it.
  - ~~Under a deep atmosphere the correction's face flux did not scale with
    the face areas.~~ Fixed in `04d63916` on #94 (E67): 0.41% of each move
    before, rounding after.
  - V2's feasibility run, `g2_v2_sphere_test` (job `13504957`): the
    production physics on a sphere under the prototype, in Float32. It builds
    in about 15 minutes, steps at 6.3 s per 20 s step on one process, and
    peaks at 17 GB. After an hour it closes to 2.3e-6 of the scale, zero-sum,
    with the ledger's left part at 19% of the gross.
  - **Submitted on 2026-09-19:** V2, `g2_v2_sphere` (job `13504999`, ten
    days, 24 ranks on `hpda2_compute`), and its twin `g2_v2_sphere_newton10`
    (job `13505000`, one day, ten fixed Newton iterations), both from
    `../ClimaAtmosResiDyn-inc-run3` at `04d63916`.
    On 24 ranks the build took 43 minutes and the first step with the
    callbacks' compile another 50. Then V2 steps at 0.71 s per step, nine
    times one process, so its ten days end near 14:40 on 2026-09-19. Its
    first hour closes to 2.31e-6 of the scale, as on one process.
  - **The updraft gap's bound from V2's checkpoints** (days 1 to 3,
    `analysis/increment/updraft_gap_bound.jl`, preliminary): in the tropics
    the gap would move 15 to 30% a day of the surface-sourced tags, against
    their total daily change of 40 to 140%; elsewhere under 4%. The share of
    columns whose air below 10 km the mass flux turns over within a day grows
    from 15% to 27%. An agent reviews the method.
  - **V2's model top collapses (found 2026-09-19, 10:40).** With one Newton
    iteration the top level (27 km) cools by 4 to 15 K an hour from the start
    and sits at the 150 K floor from 6 h on; the level below settles near
    198 K. The converged twin holds 218 K. Radiation warms the level slightly
    in both, so the cooling is the implicit dynamics' under a one-iteration
    solve. It is the model's own behaviour in V2's configuration; the tags
    feed back into nothing, `E` stays positive, and the closure is unaffected.
    But V2 is then not the production-physics test G2 asks for. Three
    three-hour variants look for the cause: sponges off, two Newton
    iterations, no mountain (jobs `13505762` to `13505764`). V2 runs on.
    **Diagnosed:** without sponges the top level cools exactly as in V2
    (216.2, 205.1 and 190.1 K at 1, 2 and 3 h), and without the mountain
    nearly so (215.5, 203.1, 188.7 K). With two Newton iterations it holds
    219.3 and 218.9 K, as the ten-iteration twin does. So the one-iteration
    solve alone makes the collapse. V2 runs again with two iterations,
    `g2_v2_sphere_n2` (job `13505896`, submitted 12:20); its per-tag twin
    stays `g2_v2_sphere_newton10`.
  - **The converged twin does not close the sphere better:** 2.78e-5 of the
    scale at 24 h against V2's 2.45e-5, because both are Float32. The same
    two hours in Float64 close to 5.7e-15, and without the sponges nothing
    changes (E70). So on the sphere the residual is Float32 rounding; the
    explicit processes add nothing measurable.
  - Recorded: V2's ten days and the Float64 twin (E70), the offset doubled on
    D4 (E71, the remainder ∝ `c`, the source tags 4 to 6%), the updraft
    estimate over nine days (E72), the updraft gap closed on D4 (E73), and
    **G2's ten days, `g2_v2_sphere_n2` (E74)**: the model top holds at 218 to
    220 K, the gross residual reaches 2.0e-4 of the scale and slows, and
    every tag is within 3.1e-4 of the converged twin at 1 h. **G2 is met (E75).** The
    second ten-day run with the updraft mixing, `g2_v2_sphere_mix`, closes as
    the first did, 2.003e-4 of the scale against 2.009e-4, and moves the
    source tags by 10 to 19% in L1 over the ten days, with their integrals
    about 1%. So the sphere's per-tag reading depends on the mixing
    convention at the 10% level, well above the solver's 3.1e-4. Nothing of
    G1 or G2 is open. The condensing of CONDENSE_PLAN.md is on hold, and the
    synergies of section 7 are prepared but not started.

**Out of G1:** the sphere, horizontal transport and hyperdiffusion, runs
longer than a day, the conventions of question 2 (the reference form as the
default, and the choice of `c`), and the GPU.

**The path to G1:** the increment prototype (`enthalpy_increment`, below),
then the correctness checks. If the prototype cannot reach criterion 1, the
remainder analysis says which process to share next.

**The next goal, G2: met on 2026-09-22.** The sphere. V2 with the prototype:
ten days in Float32, with the outputs of item 10, the residual's growth set
against its loss rate (E60), and a twin that gives the per-tag pointwise
error. Delivered by `g2_v2_sphere_n2` (E74, closure and the solver's per-tag
error) and `g2_v2_sphere_mix` (E75, the per-tag fields under the default the
fork now runs).

## Where things stand (2026-09-18)

Merged into `main`:

  - **Before the review round:** #65 and the offset (#68); #69, the implicit
    bracket and the repair (`08682fd8`); #70, sedimentation as transport, the
    EDMF refusal and the label warnings (`3b4b6056`); #73, the docs deploy
    (`327cd207`); #80, `SeasonalSST` removed (`2f60df85`).
  - **2026-09-17:** #72, the enthalpy audit; #74, the docs after #70; #75, the
    Float32 group; #78, the allocation checks; #81, the defect test on the
    moist column; and the CI work, #82, #83 and #84.
  - **2026-09-18:** #86, Aqua held below 0.8.17; #85, one moist column in the
    `parent_budget` group; #79, the parity rule (`730b5b18`).

Also on 2026-09-18: #87, the parity exception recorded; #77, the safe
defaults (`2eb7b4a9`); #76, the split solver (`38661891`); #90,
`.buildkite/LocalPreferences.toml` untracked (`23a57f02`); and #89, the merge
of upstream v0.42.11 (`369c8f28`, a merge commit whose second parent,
d331fe30, is the parity reference).

The table below is the review round of 2026-09-16, kept for its record.

On 2026-09-16 each open PR got a review, and the owner had another session
push patches for the findings with a clear fix (the record is on
`claude/review-open-prs-tasks-wxiw0k`, `review-fixes/2026-09-16/`). Nobody had
run those patches. This session added the findings that needed a Julia run,
and ran the patched files locally.

| PR  | What                                                                  | Review patches, then this session                                                                 | Local runs, this session                  |
|:--- |:--------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------- |:----------------------------------------- |
| #72 | The enthalpy audit, `energy_source_tag_transport`, with its docs      | `uₕ` compared, both refusals tested, two transport sentences; then every model field with `isequal`, the vertical and horizontal checks against the parent's own terms, three doc sentences | integration 70/70, config 15 sets         |
| #74 | D2: the energy source tag docs brought up to date after #70           | three sentences; its clash with #77 is fixed on #77                                               | docs only                                 |
| #75 | T2: a Float32 integration test of the tags and records, own CI group  | whole state on restart, the repair after the solve; then `isequal`                                 | Float32 integration 51/51                 |
| #76 | P4's fix: tags and records solved apart from the Jacobian's solver    | docs entries, a recursion for the 1.10 allocation; then a tridiagonal two-iteration unit test, the iteration count taken from the algorithm, `isequal` | unit 229/229, integration 52/52           |
| #77 | B9: the offset required, the closure check and label check by default | docs entries, NEWS, the zero guard, five passages; then tests of the audit columns and the spin-up, R3 on both limiters, the tolerance sentences | unit 250/250, config 15 sets, integration 52/52 |
| #78 | T3: the tag and record code allocates nothing                         | `Vararg{Any, N}`, comments and docs                                                               | records 17/17, source tags 52/52          |
| #79 | The parity rule, now with a test per family                           | known departures, `isequal`, scope; then an on/off test in each of the four tag and record families | records 22/22, source tags 53/53, water 111/111, energy tags 32/32 |

The fragile defect test that failed `Downgrade 1.11 - parent_budget` on #72
(decision 13) is fixed by #81. The token cannot write to Actions on the fork
(`gh run rerun` and `gh run cancel` get HTTP 403), so the owner reruns,
cancels and dispatches runs.

Measured so far: 0M on a column and a sphere, and 1M on a warm column, a day
each (E26 to E39, E43); 1M with ice on a cold column for an hour, with a twin
without vertical diffusion (E42, E42b); the EDMF build time with and without
tags, why it grows and the fix (E44 to E44e); C7's sphere in Float32 (E45) and
on 4 MPI ranks (E47), each closing as C7 does, to rounding; the tag cost on that
sphere, 1.46× (T9); where the repair's trades sit (E46), and that 10° masks
remove them (E48).

Since then: B1, the energy tag family for ten days (E50); the fork's parity
with upstream across #89 and C1b (E51); EDMF with the energy source tags, in
Float64 (E53) and Float32 (E55); a restart through C2's guard (E54); and the
EDMF build time, which is upstream's (E56).

Not yet run: the energy source tags for longer than a day, 2M and P3, a
file-based initial condition (section 2, item 14), more than one node, and the
GPU.

## 0. In flight

State on 2026-09-19.

  - **#91 (C1b) and #92 (C2) are merged,** and `main`'s CI at `50b2a4d2`,
    which has both, passes.
  - **C1c is shelved (E59).** Each of its three placements made D4's residual
    larger, because the tags' share lags the parent's stiff implicit
    diffusion and the gap accumulates. Its branch
    `claude/energy-source-tag-sgs-diffusion` (`9aeb5205`) stays local.
  - **The increment prototype, toward G1.** The owner chose on 2026-09-19 to
    rebuild the tags' implicit channel on the parent's own increment (question
    1 of the attribution path). It is the opt-in
    `energy_source_tag_transport: enthalpy_increment`, on
    `claude/energy-source-tag-implicit-increment` (worktree
    `../ClimaAtmosResiDyn-inc`, pushed to `faa98974`): after each Newton solve,
    the tags take the parent's increment of `E`, as a donor-shared vertical
    flux built from the per-cell mismatch, and the part that changes a
    column's total stays in `e_src_res`.
      + C9's column closes to rounding (1.1e-6 J/m² at 1 h), model bit for bit.
      + An agent's review found two defects, both fixed in `faa98974`: the
        stepper check (it refuses SSP333, the IMKG algorithms, prescribed flow
        and algorithms without Newton) and the parent-budget ledger's hook
        flag. Unit tests 521/521.
      + **D4 meets criterion 1 (E62):** 267 J/m² at 24 h against the base's
        6.32e5, the second 12 hours adding 75 against the first's 192, and
        `ta` and `rhoa` bit for bit.
      + **The ledger and the test group are committed** (`c0bc637f`, pushed):
        `e_src_inc_left` and `e_src_inc_moved`, their diagnostics and audit
        columns, the restart guard for them, and the group
        `tagging_source_increment` with
        `test/energy_source_tags_increment_integration.jl`. The integration
        test is running (job `13504842`), and so is an agent's review.
      + **Criterion 2 is met (E64):** the 267 J/m² are the one-iteration
        solve's column totals (313 gross), less the loss rule's flushing
        (+44); nothing else shows above 1 J/m². Converged, the prototype
        closes to 0.08 J/m².
      + **Criterion 5 is met (E65):** Float32 gives 607 J/m², with `ta` and
        `rhoa` bit for bit the Float32 base's.
      + **Criterion 4 is measured (E66).** Against the converged per-flux
        reference, on the same atmosphere, the tags differ by 8 to 12% (region,
        L1) and 68 to 126% (source tags). That is the mixing convention: the
        reference keeps `sfc` in the lowest cell, the prototype's tags mix it
        through the boundary layer. The one-iteration solve's own effect, at
        1 h against the converged prototype, is 0.1% (region) and 1 to 6%
        (source tags). Proposed threshold, for the owner: L1 ≤ 1% and ≤ 10%,
        L∞ ≤ 25%. Which convention is right is question 2; V3 would measure
        it.
      + **The review of the ledger (agent, 2026-09-19)** found three blocking
        defects, all fixed in `f7beca97`: the docs' `@ref` targets, a test
        tolerance, and the `-0.0` path, which could change model fields under
        `energy_q_tot_upwinding: none` (the mode now refuses it). Also fixed:
        the ledger in the tracer loops (the positive rule, now in #93 and
        merged into the branch), and the tests and docs it asked for.
        Unit tests 630/630. The integration test is running (job `13504941`).
  - **The diagnostic (E61):** with a converged Newton solve, C1c's option 1
    reaches 2.3e5 J/m² at 12 h against 3.2e6 with one iteration, and half the
    base's 4.6e5. So the implicit timing gap was most of E59's drift, as the
    prototype assumes. A slow growth remains, not separated.
  - **Recorded on 2026-09-18:** E57 (#89's remaining parity paths, bit for
    bit), E58 (V5 without tags: the model's own restart is not bit for bit on
    C5's column), E59 (C1c), E60 (how mislabelled energy evolves: it is flushed
    only as fast as it is lost, and the column integral hides per-tag errors),
    and the attribution discussion
    ([ATTRIBUTION_PATH.md](ATTRIBUTION_PATH.md)).
  - **V2's outputs are set** (item 10 of section 2). Its configuration is not
    written yet. It should run on the prototype, if G1 is met.
  - **#89 is merged.** An agent's review, reading only, found no blocking
    defect. Open from it:
      + R1: the upstream groups have not run on Julia 1.10 with the new
        packages. Neither #89 nor `main` had a manual `ci.yml` run, which is
        the one that runs them. The owner starts it;
      + ~~R2~~: done (E57). A restart and the vertical water borrowing
        limiter are bit for bit. The prescribed-flow column fails upstream
        too, on `ITime`, so the fork's hook there cannot be run;
      + R3: the committed `.buildkite` manifest keeps upstream's
        `project_hash`, so every setup rewrites two lines. They stay
        uncommitted unless the owner decides otherwise;
      + nits for a follow-up PR: a vacuous `===` test in
        `test/coupler_compatibility.jl`, NEWS's stale Aqua headline,
        docstrings without the tagging keywords, a species list parsed twice,
        and an unmatched `@test_throws`;
      + the NaN tags under file-based initial conditions, section 2, item 14.
  - **CI after #89 is slower (P8),** 1.4 to 2.1 times on the same runner CPUs.
    Accepted for now by the owner.
  - **P7 is closed (E56):** the build time is upstream's.
  - **Runs of 2026-09-18,** all with the owner's approval: B1 (E50), C1b's
    validation (E53), V5 and C1b in Float32 (E54, E55).
  - **Worktrees for runs:** `../ClimaAtmosResiDyn-c1b-val` at #91's
    `9dd30a90` and `../ClimaAtmosResiDyn-c2-val` at #92's `e4e9e5b3`, both
    detached, with this branch's run files copied in. Remove them once the
    PRs merge, with `../ClimaAtmos-upstream-d331fe3` and `-localprefs`.
  - **#76's allocation, settled:** on Julia 1.11 the split and the unsplit
    solve allocate nothing; on 1.10 both allocate 1,056 bytes, which ClimaCore's
    own coupled solve does and the split does not add to. The test marks
    "split allocates zero" broken on 1.10 only.
  - **This branch has `main` merged in only up to `38661891`,** before #89.
    Runs launched from here use that model code. Runs of the open PRs go
    through the worktrees above.
  - **`gh` and the `upstream` remote.** With no default repository, `gh`
    prefers a remote named `upstream`, and `gh pr create` without `-R` goes to
    `CliMA/ClimaAtmos.jl`. The fork is `gh`'s default for this clone. Pass
    `-R johannespletzer/ClimaAtmosResiDyn.jl` anyway in other clones. The
    token cannot cancel, rerun or dispatch Actions runs.
  - **CI cost.** The CI review and its plan are on
    `claude/review-open-prs-tasks-wxiw0k` (`review-fixes/2026-09-17/`,
    `plan_review.md` sections 1 to 5, with the owner's decisions). Merged:
    #82 to #86. #77's run used 571 runner-minutes in 33 jobs, against about
    1,820 in 68 before. Next: phase C on the tagging files, one PR per file,
    each reviewed by the owner, first `tagged_water_integration.jl`.

## Decided

On 2026-09-19:

  - **V3 is approved** by the owner: the passive tracer with an updraft copy
    beside the tags on D4, to measure the tags' mixing against the air's own
    (UPDRAFT_GAP.md, "How to measure it", item 2).
  - **The documents are to be corroborated and condensed** after V2's entries,
    by the plan in [CONDENSE_PLAN.md](CONDENSE_PLAN.md), approved by the owner.
    The originals are archived in the tree; the scope is `experiments/tag_closure/`.
    On hold by the owner since 13:10, until further notice.
  - **#93 and #94 are merged** by the owner (#94 at 13:40 UTC). The
    prototype `enthalpy_increment` is on `main`.
  - **Criterion 4 of G1 waits for the updraft gap.** The owner: "Accuracy is
    highly important. Lets ask that question again after the updraft gap is
    closed." So no threshold is set now, and G1 stays open on criterion 4.
    Closing the gap needs model code (UPDRAFT_GAP.md, "Ways to close it").
  - **The short-term goal (the owner, 2026-09-20): finish G2, then the
    review's polish.** In order: `g2_v2_sphere_mix`, the ten days with the
    updraft mixing, and its entry; then the three small items of
    `review/agent_reviews/updraft_78e19e23.md` (N1 the exchange's scratch only
    under prognostic EDMF, N2 the plume on the lower face's velocity), and
    housekeeping: every run's small text outputs kept in the repository, and
    the README's register saying whose NetCDF is only on scratch. The GPU
    compile is dropped (the owner, 2026-09-20). N2 changes the tags a little,
    so its effect is measured on D4 against the copies, not by another sphere
    run. Nothing
    beyond G2. The condensing stays on hold. Keep token use low: long polls,
    one entry per result, no agents unless asked.
  - **Criterion 4's threshold, set on 2026-09-20** (the owner): two parts, as
    in the goal table's row 4. Both parts are met, so **G1 is met**. The
    updraft gap's PR is #95, whose CI is green (71 checks, 1 skipped). It
    stays a draft: this token cannot mark a pull request ready for review.
  - **The exchange keeps the parent's face scheme** (the owner, 2026-09-20),
    centred where the parent is centred, which matches the audit most
    closely. The repair therefore acts at the inversion in the first hours,
    in both modes (E73).
  - **G2 reports two ten-day runs** (the owner, 2026-09-20): the one now
    running, `g2_v2_sphere_n2`, for closure and the residual, which the
    exchange does not change, and then a rerun with the updraft mixing on for
    the per-tag numbers that match the merged default.
  - **The way to close the updraft gap: one logical** that switches between
    updraft copies of the tags (the audit mode) and a zero-sum exchange (the
    default). The design is in UPDRAFT_GAP.md, "The chosen way". Branch
    `claude/energy-source-tag-updraft`.
    **Built and measured (E73).** Branch head `78e19e23` (worktree
    `../ClimaAtmosResiDyn-upd`, run worktree `../ClimaAtmosResiDyn-upd-run`).
    On D4 for a day both modes keep `ta` bit for bit; the default stays
    within 0.7% (L1) of the copies after a day and 2.6% after six hours,
    where the tags without updraft mixing were 14% and 71% off. Two defects
    were found by the tests and fixed: the shares were normalised over all
    tags, not the partition (`e010f780`; the first default run is
    superseded), and a `Val` built at run time made the exchange allocate
    (`78e19e23`, numerics unchanged).
    **Reviewed** at `78e19e23` by an agent
    (`review/agent_reviews/updraft_78e19e23.md`): the physics and the parity
    hold. One blocker (CI time: the copies' run now has its own group,
    `tagging_source_updraft`) and six should-fix items, all addressed in
    `c87ad5ff` and `38278c2d`: the exchange is refused without a partition,
    the plume's weight cannot overflow in Float32, the shares are stored once
    per call, the zero sum holds everywhere, the restart guard's copy check is
    tested, and stale text is updated.
    **Open, in order:** the four test groups at `38278c2d` (jobs `13536384`,
    `13536385`, `13536454`, `13536455`); the default D4 day again at the head
    for provenance (`13536456`); a PR from `claude/energy-source-tag-updraft`;
    then criterion 4's threshold is asked again, with E73's numbers.
  - **Question 2a, the mixing convention: the hybrid, as built.** Tracer-like
    mixing for turbulent exchange, and the enthalpy flux form for resolved
    transport and pressure work (TRACER_AND_FLUX.md, recommendation).
  - **Question 2b, the offset: keep 110,495 J/kg** for every G1 and G2 run,
    stated with each per-tag result (E71 gives the sensitivity). U8's
    temperature-floor rule comes before any run whose surface air could fall
    below about 228 K.
  - **Question 3, the correction: keep it as built.** It moves only the
    column-local part, logged in `e_src_inc_moved`; the column totals stay
    visible in `e_src_res` and the ledger.


On 2026-09-11:

  - **Production** is a GPU sphere in Float32, with EDMF and 1M.
  - **EDMF:** refuse `prognostic_edmfx` with tags now (C1a, done in #70), and
    build the sharing later (C1b): under both transports, in the implicit
    tendency, with the guard of the shared loop (B4).

On 2026-09-14:

  - **The offset (U1):** required whenever energy source tags are set. An
    explicit `0` keeps today's behaviour. The refusal quotes the tested values:
    110,495 J/kg, and the smallest offsets that made the total positive, 45.4
    kJ/kg on the DYCOMS column and 100.4 kJ/kg on the moist sphere (E6).
    How to choose it for a long run is open: U8.
  - **The closure check (U2, R1):** on by default whenever the tags are set,
    daily, reported from a spin-up reference, report-only until V2 and V3
    calibrate a tolerance per transport.
  - **The per-process checks (A2, A3):** the label check at configuration now.
    A2's runtime part and A3, form A online, later, as optional validation
    features.
  - **The S items,** grouped: now C5, P1, D2 (all done or in a PR); with B9 U3,
    U4, R3, T4; with C1b M3, T5; before the GPU T3; with V2 C4, V6; with D1 D3.
    A4, A5 and A7 move to N.
  - **Merges:** the owner merged #69 and #70, and approved pushing #72's docs,
    retargeting it to `main` and taking it out of draft, and opening #74.
  - **Standing approvals,** so that the work runs without stopping. The main
    session takes P4 and every task that needs approval; an agent took T2.
      - **P4 jobs:** up to 8 on `hpda2_test`, at most 2 CPUs, 48G and 2 h
        each. 7 used: 3 inference profiles, 2 cancelled validations of the
        first commit, 2 validations (E44e). 1 left.
      - **Code, as draft PRs to `main`, merged only by the owner:** P4's fix
        (#76); B9 with U3, U4, R3 and T4 (#77); C2's restart guard with T1,
        after #72 merges; C1b, after #76 and #72 merge.
      - **Runs at their predecessors' settings:** the C6 twin with a 10° mask
        (done, E48); V5, restart equivalence (up to 2 jobs, after C2); C1b's
        validation (up to 5 jobs: the D4 pair, D4 with
        `edmfx_vertical_diffusion: true`, D5).
      - **Pushes:** the main session's branches and T2's, as draft PRs.
  - **Parity with upstream, a boundary condition.** Simulation results from
    ClimaAtmos and from this fork must be binary identical: the fork develops
    a diagnostic only. With a diagnostic on, every field upstream has stays bit
    for bit the same. Written into `AGENTS.md` and
    `docs/clima_atmos_specific.md` ("Fork parity with upstream"), on this
    branch and in #79 for `main`.
  - **`SeasonalSST` is removed entirely** (#80, and on this branch in
    `c00aca1e`). It was new physics. The transient stratospheric tracer
    examples use `PrescribedSST` again.
  - **The binary comparison against an upstream checkout is skipped for now**
    (P6).

On 2026-09-17:

  - **The fragile defect test (decision 13):** the convergence check stays on
    the moist DYCOMS column. A dry column with implicit diffusion never stood
    above rounding in 64 runs. Merged as #81.
  - **The CI plan** (`plan_review.md` section 5):
      + fork-owned groups keep Julia 1.10 and 1.11, upstream groups run on
        1.11, and a manual `ci` run covers 1.10 for a PR that edits upstream
        code;
      + `Downstream` runs after merges, weekly and on demand;
      + package images are built for a portable CPU target, now;
      + the `parent_budget` group gets a type audit before any split.
  - **Aqua:** first add the missing weak dependency as a test extra. When the
    walk stopped at the next package, the bound on Aqua replaced it (#86).

On 2026-09-18, going through section 1 with the owner:

  - **#77's three choices** (decision 2): accepted as written.
  - **C2's design** (decision 11): approved, minimal.
      + The check also covers the process-record fields.
      + The spin-up reference follows #77: it is taken again after a
        restart.
      + No override key.
      + Starting tags from a tagless checkpoint is an N item, U7.
  - **The parity break** (decision 12): `dd06318f` stays as a named exception.
    No upstream PR is opened. The local branch `upstream-vwb-species-guard` and
    [UPSTREAM_VWB_PR_DRAFT.md](UPSTREAM_VWB_PR_DRAFT.md) stay as a record.
  - **ClimaCore** (decision 3): #76 keeps the `MatrixFields` internals. The
    drafted issue is not filed.
  - **The named regions' width** (decision 10): 2° stays. The docs should say
    that a mask narrower than the grid spacing makes the repair trade, and
    that a 10° mask avoids it on coarse grids (with D3).
  - **V1** (decision 5): folded into V2, which becomes a 10-day Float32 run.
  - **Phase B** (decision 7): B1 is approved, one job, at the plan's
    settings.
  - **Runs** (decision 8): V2 and V6 are approved, to run once C1b is merged.
    MP1 on two nodes is not.
  - **B3** (decision 6, the design's decision 5): extend the audit to the SGS
    diffusive flux, as C1c, after C1b. This changes the decision of 2026-09-11.
  - **2M and P3** (decision 6, the design's decision 6): upstream lifts the
    model's gate. When it does, the tags accept 2M and refuse P3 at
    configuration until the parent's P3 sedimentation is fixed.
  - **A4** (decision 4): later, as N.
  - **D1** (decision 9): after V2.
  - **Aqua's walk upstream** (14): not reported.
  - **One moist model in `parent_budget`** (15): no.
  - **#80's NEWS entry:** none.
  - **Worktrees:** the 17 whose branches are merged are removed.
  - **CI minutes:** collected from #77's run and recorded in `plan_review.md`.

## 1. Decisions for the owner

None open. Every decision of this section was made on 2026-09-18; see
"Decided". #76, #77 and #87 merged the same day.

## 2. Blocking operation (B), in dependency order

 1. ~~**Merge #70.**~~ Done (`3b4b6056`).
 2. ~~**Merge #72.**~~ Done on 2026-09-17. C2 and C1b can build on
    `energy_source_tag_transport` now.
 3. **P4, the EDMF build time with tags.** The D4 column with 8 tags and 5
    records did not build in two hours (E44, E44b). E44d names the cause:
    ClimaCore builds the implicit Jacobian's nested solver with compile-time
    work on the names of every field, which grows much faster than their
    number. #76 solves the tags and records apart, and builds the rest over the
    other fields only. On the 0M column with 8 tags the increments are
    identical to the unsplit solver's, with and without implicit diffusion, and
    the Jacobian cache builds in 20.8 s against 97.4 s. On the EDMF column with
    8 tags and 5 records the whole build now takes 21 minutes, and 8 tags add
    37 s to `get_simulation` against 1,891 s before (E44e). Merged as #76 on
    2026-09-18.
 4. **C1b, share EDMF's sub-grid fluxes among the tags** (design option B).
    Needs #72 and #76 merged.
      - B1, the SGS mass flux, with the donor from the sign of the flux of `E`;
        B2, each species' whole sedimentation face flux, the corrections
        included; B4, a guard in the shared tracer loop,
        `edmfx_sgs_flux.jl:403-409`.
      - Both transports, in the implicit tendency. About 220 lines and 200 of
        tests.
      - T6, an EDMF integration item: the partition's tendencies from the SGS
        mass flux and sedimentation match the parent's to 100 eps. It adds an
        EDMF compile to CI.
      - Validation (approved): the D4 pair, D5, and D4 with
        `edmfx_vertical_diffusion: true`, the shipped setting.
      - Then narrow C1a's refusal to `updraft_number > 1`.
      - Size M.
 5. **C2, a restart guard** (approved, after #72). Write the offset, the tag
    set, the transport and the repair setting into the checkpoint, and fail with
    a named key on a mismatch (`restart.jl:34-39`). With T1. Size S to M.
 6. **V5, restart equivalence** (approved, after C2). Two segments against one
    run, with the offset and the repair. Size S. **Ran on 2026-09-18 (E54).**
    The guard passed, and the restart restored the tags exactly. But the
    model itself does not restart this column bit for bit, even with
    `reproducible_restart: true`: every model field differs by 1e-11 to 1e-9
    after 12 hours, and the tags only as much. So the state criterion is not
    met, for a reason outside the tags. The same pair without tags differs
    by exactly as much, and its model fields equal the tagged pair's bit for
    bit (E58). So the tags pass V5; the model's own restart of this column
    does not.
 7. **Float32.** ~~V3~~ is done (E45). ~~T2~~, the Float32 test group, is
    merged (#75). Runs longer than a day are untested; that is U6. Size S.
 8. ~~**MP1, more than one process.**~~ Done (E47): on 4 ranks C7's sphere
    closes as on one process, to rounding. More than one node is untested.
 9. **The decided defaults and checks (B9).** Written: U1, the offset
    required; U2 with R1, the closure check on by default, daily, report-only,
    with a spin-up reference at 1 h and `false` to switch it off; A2, a warning
    at configuration for a process that runs with no tag following it (flags
    subsidence on C5's column and microphysics on C6's sphere, nothing on C7).
    With U3, U4, R3 and T4. Merged as #77 on 2026-09-18, with its three
    choices accepted.
10. **V2, the production physics on a sphere:** EDMF with
    `edmfx_vertical_diffusion: true`, vertical diffusion, sponges, topography
    and 1M, with `analysis/transport_ledger.jl`. It sizes C4. Needs C1b and
    #76. Approved on 2026-09-18 as a ten-day Float32 run, with V1 folded in
    and V6. Its configuration is not written yet. **It must write,** as the
    owner decided on 2026-09-18 after E60:
      + `e_src_res`, `rhoa`, every tag `e_src_<name>` and the 3-D process
        records `e_prc_<process>`, every 6 hours, so that the residual's
        growth can be set against its loss rate, `λ_R·G`, cell by cell;
      + the closure check with `audit: true` at a 6-hour period, so the
        gross residual is a time series and not one row a day.

    E60 predicts no levelling within ten days, since the loss rate is near
    0.002 a day where the residual sits on a sphere. If the residual levels
    off, mixing and not the rule bounds it. A twin under `enthalpy` on the
    same atmosphere would give the per-tag pointwise error, the number a user
    needs; it is a second job and needs its own approval.
11. **Calibrate** U2's tolerance per transport from V2 and V3, and add the
    warning.
12. **D1, the user guide into the docs,** with D3.
13. **The GPU, last.** Run the diagnostic on a GPU on Levante, with Float32 and
    T3, and fix what that forces.
14. ~~**File-based initial conditions start the region tags as NaN.**~~
    **Fixed on 2026-09-20** in `claude/energy-source-tag-updraft` (`92e9ac26`):
    `initial_state` calls `rebuild_tags_from_state!` after the setup's
    overwrite, which sets each tag by the rule that built it and the updraft
    copies from their tags. Idempotent where nothing overwrote the state, and
    a restart does not go through it. A unit test covers it. No run from a
    file has been made with tags on. The description below is what it was.
14b. **The defect, as found.** Found by
    #89's review on 2026-09-18, and confirmed by reading; not run. `WeatherModel`,
    `AMIPFromERA5` and `MoistFromFile` build the pointwise state from NaN
    placeholders, and `overwrite_initial_state!` (`src/types.jl:3229`) then
    rewrites `ρ`, `ρe_tot`, `ρq_tot`, the condensates and the winds from the
    file. The tags were built from the placeholders
    (`src/setups/common/prognostic_variables.jl:60-92`), and nothing builds
    them again. So every region tag of `ρe_tag_*`, `ρe_src_*` and `ρq_tag_*`
    starts as NaN, and the run stops at the first NaN check where upstream
    runs. Source tags and records start at zero and are unaffected, as are the
    stratospheric passive tracers. No experiment used such an initial
    condition. It blocks any production run that starts from a file. The fix
    builds the tags again from the overwritten state, a hook after
    `overwrite_initial_state!`, with a test on a file-based column. Model
    code; needs the owner's approval. Before that, a refusal at configuration
    time would turn the NaN into a clear error.
15. **The process records are advected horizontally on a sphere.** Found on
    2026-09-19 while building the prototype's ledger. The horizontal
    advection of tracers (`advection.jl:121`) and the SEM limiter
    (`limited_tendencies.jl:88`) loop over every field `is_tracer_var`
    accepts, not over `gs_tracer_names`. `is_tracer_var` excludes only `ρ`,
    `ρtke`, energy, momentum and SGS names, so `prc_e_*` and `prc_q_*` pass.
    On a sphere the records were moved with the air, against
    `docs/src/process_record.md`. The global integral is kept, so form B
    closed; pointwise records were wrong. Columns have no horizontal
    advection and are unaffected. It blocks V2, which writes the 3-D records.
    Confirmed on a sphere (E63). The fix, `is_process_record_var` excluded
    from `is_tracer_var`, is draft PR #93 (`61d8dc3d`), with a unit test; the
    owner merges. The prototype's ledger fields need the same exclusion
    before G2.

## 3. Should fix (S)

Done or in a pull request:

  - ~~**C5.**~~ Where the repair's large trades sit: just beyond the 20° edge
    where the region tags meet (E46). With 10° masks there are none (E48).
  - ~~**P1.**~~ The tag cost on a sphere: 1.46× (T9).
  - ~~**D2,**~~ the stale docs: merged in #74 (fixes 3, 7, 9, 10) and #72
    (fixes 5, 7). Fix 4 needs no change.
  - **U3,** `e_src_fix_<name>` in the default output when the repair is on;
    **U4,** the source tags' negative parts and minimum, and the energy the
    repair moved, in the audit table; **R3,** a warning when clipping `ρq_tot`
    changes `ρe_tot` outside every bracket; **T4,**
    `config/model_configs/baroclinic_wave_energy_source_tags.yml`. All in #77.

With C1b (B4):

  - **M3.** A test that `water_advection.jl:51-56` and
    `gs_sedimenting_mass_candidates` list the same species. Written, and
    committed only locally, on `claude/energy-source-tag-species-lists`
    (`68cfe17f`), to open with C1b. Four mutations of the source each fail
    it.
  - ~~**T5.** The cold column as an integration item.~~ **Done on
    2026-09-20:** `test/energy_source_tags_cold_column.jl` runs the 1-moment
    cold precipitating column and checks the upward branch on the initial
    state, where every cell of falling ice carries negative `E`, and that a
    minute of it leaves every tag finite, non-negative and the partitioned
    total positive. The 2-moment schemes stay in
    `analysis/subgrid_check_cold.jl`, since the model refuses to build them.

Before the GPU (B13):

  - ~~**T3.**~~ In #78: the tag and record code allocates nothing in a tendency
    evaluation or in the repair. #76's split solver allocates nothing either
    (a check added to #76).

With V2 (B10):

  - **C4.** `c·Δρ` from processes the tags do not bracket: vertical diffusion,
    sponges, hyperdiffusion, EDMF, LES (`energy_source_tags.jl:102-111`).
    Measure on V2, then share them as transport or document the size.
  - ~~**V6.** Topography.~~ **Covered on 2026-09-20.** G2's ten days
    (`g2_v2_sphere_n2`, E74) ran with `topography: "DCMIP200"` and closed to
    2.0e-4 of the scale, and the unit tests check the increment correction's
    face-area scaling on deep and shallow spheres with and without a mountain
    (E67). A dedicated topography experiment is not needed.
  - **T5's cold column** is now a test,
    `test/energy_source_tags_cold_column.jl`, in the `tagging_source` group.

With D1 (B12):

  - **D3, caveats:** C1 and C4, what is untested, stitching `e_src_fix` across
    restarts, choosing `c`, and ice passing provenance upward (E41).

Found on 2026-09-18:

  - ~~**P7.**~~ **Not a regression (E56).** The fork builds the EDMF column in
    the same wall time as upstream. E52 summed the logged stages, and upstream
    compiles the Jacobian solver before the timed block, where no stage counts
    it. What is real is small: without tags the cache holds the solver twice,
    and the ODE function compiles in 11 s against 4 s. A fix was tried in
    scratch and was bit for bit on `edmf_column`: `@generated` tag predicates,
    the solver builder chosen from the model's type, and the solver kept once.
    It saves seconds, so it is optional and not approved. Before it merges it
    needs parity on `moist_sphere` and `column_1m`, testset 6 of the source-tag
    integration file, and a tagged build with water tags. Unexplained: whole
    parity runs are 5 to 6% slower in the fork.
  - **P8. #89 makes CI's test groups slower.** Measured on 2026-09-18 by
    comparing #89's run at `c068d564` with `main`'s at `38661891`. On
    identical runner CPUs #89's jobs took 1.4 to 2.1 times as long, in six
    pairs; for example, `tagging_source` on 1.10 took 44 minutes against 21.
    Precompiling the new package versions adds only 1.5 to 2.5 minutes, and
    that goes once `main` saves a cache after the merge. The rest is in the
    tests: `tagging_source` on 1.11 tested for 61 minutes against 35. The EDMF
    column's tendency function built as fast after the merge as before it on
    the login node (397 s against 413 s), so the time goes elsewhere. Whether
    upstream v0.42.11 and ClimaCore 1.0 cause it, or the fork's code on them,
    is not known. `ci 1.11 parent_budget` took 72 minutes and `tagging_source`
    on 1.11 64, near the 90-minute limit. #91 adds a sixth compile to
    `tagging_source` and a group that builds the EDMF column twice. **Accepted
    for now by the owner on 2026-09-18:** watch #91's first run after the
    rebase. The options, if it goes over: raise the limit, or split the two
    groups, in a PR of their own.

## 4. Nice to have (N)

  - **ClimaCore upstream.** Its field-name sets check every pair against every
    other at compile time (E44d). Scaling that down would help every model
    with many tracers, and would let #76 use public API only.
  - **A4.** Signed overlay shares (decision 4). Accept when a C9 twin gives form
    A of at most 5 J/kg, or at most 1e-6 with the loss signed too, and `sfc` no
    longer freezes at a node, with `ta` and the partition residual unchanged.
  - **A5.** An overlay-bound diagnostic: the mass fraction where an overlay is
    negative, and where a member exceeds its group's sum.
  - ~~**A7.**~~ Done (E49): a transport error cancels along the direction it
    moved, and a process no tag follows, or the repair, keeps its sum.
  - **Parity checks (P6).** The on/off half is merged (#79): each tag and
    record family now runs the same column with and without it and compares
    every model field with `isequal`, as the ledger's envelope test already
    did. All four match bit for bit locally. Still open: the stratospheric
    passive tracers have no such test, and nothing compares the fork with an
    upstream checkout. That run sets a reproducibility reference, and the
    owner chose on 2026-09-14 to skip it for now. Besides `dd06318f`
    (decision 12), a first read of the 14 files in `src/` where the fork
    rewrites upstream lines, against `v0.42.9`, found nothing else that acts
    without a diagnostic. The files the fork only adds to were not read for
    this. `SeasonalSST` is gone (#80).
  - **P5.** The explicit tendency's generic tracer loops allocate, with or
    without tags, and each tag adds to it: 22,576 bytes per call without tags
    and 58,160 with four on a 1M column (#78's description). Shared model
    code, not tag code.
  - **A2's runtime part and A3,** as optional validation features: ∫Δ⁺ per
    label at runtime, and form A as a global integral online. Accept A3 at
    about 1.2e-3 on a C6-type run and at most 1e-4 on C7, C9 and C10 at 24 h.
  - **The region masks' width.** With 10° masks the repair never trades between
    the region tags, against ±30,915 J/kg with the named regions' 2° (E48). A
    wider mask blurs provenance: each region tag keeps a few percent of the
    other region's energy. Decided on 2026-09-18: 2° stays, and the docs say
    so with D3.
  - **C1c.** B3, the SGS diffusive flux under `enthalpy`. Approved on
    2026-09-18, after C1b (plan C4). Built on 2026-09-18
    (`claude/energy-source-tag-sgs-diffusion`, `9aeb5205`, not pushed), and
    compared in three placements (E59): each makes D4's residual larger,
    because the tags' share lags the parent's stiff implicit diffusion and the
    gap accumulates. Not to be opened in this form. Open: a Jacobian block for
    the shared flux, or sharing the parent's implicit increment. Both need
    the owner's decision.
  - **C1d.** Option C, per-updraft tag shares; about three times B.
  - **C6.** Review leftovers: `isfinite` before the conversion to `FT`, `nothing`
    inside a broadcast at init, `parent` shadowed in tests. The Float32 rounding
    floor stays N (E45).
  - **C7.** Jacobian blocks for the tags' sedimentation and the implicit
    bracket.
  - **A6.** A tag-only vertical upwinding key (E37).
  - **P2.** Compute `energy_source_share_norm!` once per evaluation, and skip it
    when nothing sediments. **P3.** A string allocation per tracer per
    evaluation under the audit (`energy_source_tags.jl:148`).
  - **U7. Start tagging from a checkpoint, a future opportunity.** Today the
    tags can start only at t = 0. A restart cannot switch them on. C2's guard
    (#92) refuses a checkpoint whose tag fields differ from the configuration,
    and nothing gives a tag a value from a restored state. So a climate run
    cannot spin up for months or years without tags and then start tagging.
    The opportunity is a new tag experiment whose clock starts at the restart,
    with an offset of its own (U8). It needs:
      + an explicit start mode, off by default. In it a pure region tag starts
        as its mask times `E` of the restored state, and a source tag at zero,
        as at t = 0 (`tag_initial_value`);
      + the process records started at zero the same way;
      + the guard to accept a checkpoint without these fields in that mode
        only, and to record the settings from that start on.

    Changing the settings of tags already in a checkpoint stays refused. Model
    code: the initialization path and the guard. Out of C2's scope (C2's
    question 4). Size M. Added on 2026-09-18 at the owner's request, not to be
    built now.
  - **U5.** A clear error when the tag list changes across a restart (C2 covers
    most of it). **U6.** Records in Float64, or reset at each output, for long
    Float32 runs; over a day they match Float64 to 4e-4 at 24 h (E45).
  - **U8. Choosing the offset, options.** The offset `c` belongs to a tag
    experiment. It is fixed at t = 0 and kept through every restart, which
    C2's guard enforces. The atmosphere does not depend on it (E17), but the
    tags do (E19).
      + **The risk.** The guidance today is the 110,495 J/kg the experiments
        used, and the refusal message quotes the minima of two initial
        states. On the moist sphere that leaves about 10 kJ/kg. For dry, still
        air, `e_tot + c > 0` needs `T > T₀ − (c − R_d T₀ − g z) / cv_d`. At
        110,495 J/kg that is 228 K at sea level, 215 K at 1 km and 187 K at
        3 km. A production run over a continental winter can plausibly go
        colder near the surface. No run with an offset has crossed yet, but
        none lasted more than a day.
      + **What happens there.** The shares are zero where `e_tot + c ≤ 0`. The
        tags stop losing energy but keep gaining it. Sedimentation, the EDMF
        sub-grid flux and the `enthalpy` audit move no tag out of such a
        cell. The repair does not act there. The residual shows all of it. By
        the formula, the overclaim outlasts the cold spell, and later losses
        relax it only in part. That is not measured.
      + **Option 1: choose `c` from a temperature floor** over the whole run,
        not from the initial state: `c ≥ R_d T₀ + cv_d (T₀ − T_floor) − g z`.
        The refusal message and the docs would say so. 150 kJ/kg keeps dry air
        at sea level positive down to 173 K. The cost, measured for a doubled
        `c` (E19): the source tag moves by about 1%, and the region tags'
        negative undershoots grow 1.5 times, which the repair absorbs.
      + **Option 2: one `c` for every setup whose tags are compared,** since
        the tags depend on it. It is reported with the results, as part of
        the energy reference.
      + **A new `c` needs a new tag experiment,** from t = 0, or from a
        checkpoint with U7. A new `c` at a restart would leave
        `(c_new − c_old)·ρ` that no tag holds.

    `c` is an energy reference, so this needs the owner's approval. Decide
    before the first production run that spans a winter. Added on 2026-09-18,
    not to be built now.
  - **U9. The offset's headroom in the closure table.** Today the table shows
    only `nonpositive_fraction`. So a drift toward `e_tot + c = 0` shows only
    once a cell has crossed. A column with the domain's minimum of `e_tot + c`
    shows the margin before that. It needs a minimum reduced across
    processes, and it changes the table's column count, which parsers notice.
    Optionally, add an `abort_above` for `nonpositive_fraction`. A run with
    only source tags has no closure check by default. It is checked only when
    the cache is built, at the start and at each restart. Size S. Added on
    2026-09-18, not to be built now.
  - **R5.** A converged Newton solve for closure studies; its cost is not
    measured.
  - **M4,** when 2M returns: D2 and one integration item. **M5,** when the
    parent's P3 is fixed: D3.

## 5. Housekeeping

  - **Worktrees** beside the repository. Each has a copied
    `.buildkite/LocalPreferences.toml`, which `main` tracks: never commit it.
    Checked on 2026-09-18 against `origin/main`.
      + **Removed on 2026-09-18, their branch merged:** `-audit` (#72),
        `-docs` (#74), `-float32` (#75), `-t3` (#78), `-parity` (#79),
        `-noseasonal` (#80), `-defect` (#81), `-ci-phase-a` (#82 to #84, #86),
        `-pb-audit` (#85), `-docsfix` (#73), `-repair` (#70), `-offset` (#68),
        `-pr65`, `-split`, `-b3` and `-b5`; also `-c1b-check`, a detached
        scratch merge. None held uncommitted work; the ignored files were
        manifests, a docs build and local test output.
      + **Also removed on 2026-09-18:** `-buildtime` (#76), `-defaults` (#77)
        and `-parity-doc` (#87).
      + **Keep:** `-buildtime-edmf` (#76's validation, detached, with a
        local change that must never be committed; C1b's validation may
        reuse it); `-m3` (M3, local only, until C1b); `-p4` (detached
        at `edd44e1d`, P4's diagnosis); `-ci-review` (the CI review's branch);
        `../ClimaAtmos-upstream-vwb` (decision 12).
  - ~~**The known defects** in `LEVANTE_TASKS.md`.~~ Fixed on 2026-09-14: the
    validator now follows the model's `if`/`elseif` chain, so ISDAC skips the
    `implicit_diffusion` rule, and it checks the ISDAC and prescribed-flow
    asserts too; `output/c0_sphere_deep/` has a provenance reconstructed from
    its logs, and the analysis skips a run whose provenance records a failed
    exit with a note instead of a warning.
  - **`analysis/phase_c.jl`** reads only runs named `c*`; the D, P, V and MP
    runs are in FINDINGS only.
  - ~~**NEXT_SESSION.md** needs the day's state.~~ It points here, with a
    summary of the day.

## 6. Open questions, not blocking

  - What makes D1's zero-sum gross residual (E42, E42b). Candidate: pressure
    work in grid-mean vertical advection under tracer transport. An audit twin
    of D1 would test it.
  - What the sphere's remaining 17% of the audit's first-hour residual is
    (E39b).
  - How much provenance the upward branch moves where ice persists (D5, after
    C1b).
  - E14, E16's remainder and E24.

## 7. Synergies: what the findings give when combined

Written on 2026-09-20, after reading FINDINGS end to end. Each item reuses
machinery that already exists; none is a new experiment from scratch. The
owner asked for items 1, 2 and 4 to be prepared.

 1. **The increment ledger as a diagnostic of the parent's own solver.**
    *Prepared, see below.* `e_src_inc_left` is the part of the parent's
    implicit increment that changes a column's total and that no tendency
    accounts for (E64). E69 then found that one Newton iteration destroys V2's
    model top within a day, and E74 that two iterations hold it. So the ledger
    already measures the solver's non-conservation, and would have flagged
    that collapse in the first hour. Nothing uses it that way. This is the one
    item here that could be offered upstream.
 2. **A two-hour Float64 twin as a standard recipe.** *Prepared, see below.*
    E70 split the sphere's residual into rounding and structure with two hours
    in Float64; E45, E55 and E65 did the same by hand elsewhere. Together they
    are a method, not four measurements. It costs one short run and answers
    the first question anyone asks of a residual.
 3. **The updraft exchange belongs to the water tags too.** The energy tags now
    mix provenance through the updrafts (E73). The water tags have the same
    gap under EDMF and it has never been examined. The plume and the exchange
    are family-agnostic in shape, so most of the work is wiring. It is the
    largest scientific gain here and the largest piece of work, and it is
    beyond G2.
 4. **The closure check could forecast, not only report.** *Prepared, see
    below.* E60 gives the rate at which the loss rule flushes the residual, and
    E74 computes where it would level off (`G*/G`). Both come from quantities
    the audit already reduces. A run would then say "this settles near X", not
    only "the residual is X now".
 5. **A memory number for every run.** *Prepared, see below.* E60's `τ = E/L`
    says how long a tag remembers, and E71 shows the offset acts through
    exactly that. It is the most important interpretive number for a reader of
    the tags, and nothing reports it. It falls out of the same reduction as
    item 4.
 6. **One per-process budget across both families.** *Prepared, see below.*
    E23 left 1.37 MJ/m² of a column's energy change unexplained. The process
    records say what each process did, and the ledger says what the solve left
    behind. Crossing them needs no model code, but no committed run pairs the
    full record list with the ledger, so it needs one short run of its own.

### Prepared: item 1, the ledger as a solver diagnostic

  - **What to build.** A probe configuration and a warning. The probe is the
    cheapest tag set that makes the ledger meaningful: two region tags that
    partition the domain, no source tags, `energy_source_tag_transport:
    enthalpy_increment`. The warning fires when `increment_left`, over the
    partitioned total, passes a level, or when it grows over a run.
  - **Where.** The audit already carries `increment_left` and
    `increment_left_gross` (`energy_source_tags.jl`,
    `_energy_source_ledger_audit`). The check would sit beside the closure
    check's warning, in `get_callbacks.jl`, with its own key.
  - **Calibration.** D4 with one iteration gives 313 J/m² gross in a day and
    0.094 with ten iterations (E64); V2's sphere gives 37% of the residual
    with two iterations (E74). So the level is a fraction of the partitioned
    total, and the growth matters more than the size.
  - **Cost.** Small: no new state, one reduction per check.
  - **Beyond this repo.** Upstream has no such monitor. Offering it would need
    the probe to be described in the tags' own terms, since the ledger only
    exists with the tags on.

### Prepared: item 2, the Float64 twin recipe

  - **What to build.** A documented recipe and a helper. Given a run's config,
    the helper writes the twin: `FLOAT_TYPE: Float64`, `t_end` two hours, one
    process, everything else the same. The comparison reads both closure
    tables and reports the residual in each, and their ratio.
  - **Where.** `experiments/tag_closure/analysis/increment/float64_twin.py`
    for the comparison, and a section in
    `docs/src/energy_source_tags_guide.md` under "Is the answer
    trustworthy?".
  - **What it decides.** Whether a residual is rounding or structure. On the
    sphere the twin closed to 5.7e-15 against 3.85e-6 in Float32 (E70), so the
    answer there was rounding; on D4 the Float32 residual is 2.3 times the
    Float64 one (E65), so there it is structure.
  - **Cost.** An hour of wall time per configuration, and no model code.

### Prepared: item 4, the closure check as a forecast

  - **What to build.** Two more columns in the audit table: the flush rate the
    loss rule gives, and the level the residual would settle at, `G*`, with
    the ratio to the present residual.
  - **How.** `analysis/increment/v2_sphere.py` already computes both from the
    closure and audit tables. The first step is to lift that computation into
    a helper the repository owns, so the experiment scripts and the docs share
    it. The second, if it proves stable, is to compute the flush rate in the
    run itself from the tags' own losses, which the attribution rule already
    sums, and write it to the audit table.
  - **What it needs to be honest about.** The rate is not constant: on V2 it
    ran from 0.0105 to 0.0165 a day (E74). The forecast is an order of
    magnitude, not a number.
  - **Cost.** Analysis only for the first step.

### Prepared: item 5, a memory number for every run

  - **What it is.** `τ = E / L`: the partitioned total over the rate at which
    the loss rule takes from it, in days. It says how long a tag's energy stays
    before the rule flushes it, and so how far back a reading of the tags
    reaches. E60 measured it by hand: 4 to 20 days on D4, about zero in the
    surface layer, and 1 to 2 years above 10 km on C9's sphere, where most of
    the residual sits. The initial-energy tags lose 8.6% and 12.3% a day on
    D4, a memory of 8 to 11 days.
  - **Step 1, from what is on disk.** A script forms `L` per cell from the
    process records, which log each process's applied increment, as the sum of
    the negative parts, and divides `E` by it. Output: `τ` per level, the
    mass-weighted median, and `τ` where the residual sits, which is the number
    that matters for the closure. `analysis/increment/memory_time.py`, over
    the runs that already carry records and tags (`c6_column_repair`,
    `c1c_base_d4_enthalpy`, `c5_sphere_gray`).
  - **Its own check.** `τ` must scale with `e + c`: doubling the offset should
    multiply it by about 2.6 on D4 (E60's formula, E71's run). Both runs exist,
    `g1_inc_d4` and `g1_inc_d4_2c`, so the script can be validated the day it
    is written.
  - **Step 2, in the run.** The attribution rule already sums each bracket's
    loss before sharing it out, so accumulating it per cell costs one field and
    gives `L` exactly, rather than from the records. Then `τ` joins the audit
    table beside item 4's forecast, and the guide reads it as "this run
    remembers about N days".
  - **Cost.** Step 1 is analysis only. Step 2 is one accumulator field and one
    audit column.

### Prepared: item 6, one per-process budget across both families

  - **What it closes.** Over an interval, the change of the partitioned total
    `E` should equal the sum of what each process did, plus what the implicit
    solve left behind, plus what the repair moved. The process records give the
    first (E9, E26), the increment ledger the second (E64), and
    `e_src_fix_<name>` the third. Nothing has added them up. E23's 1.37 MJ/m²
    of unexplained change on a column is the gap this would name.
  - **The data gap.** No committed run has both. The runs with the full record
    list use the `tracer` or `enthalpy` transport, so they have no ledger
    (`c1c_base_d4_enthalpy`, `c6_column_repair`); the runs with the ledger
    record only precipitation (`g1_inc_d4`). So it needs one D4 run with
    `energy_source_tag_transport: enthalpy_increment` and
    `energy_process_record` listing every process the column has. About 40
    minutes, after G2.
  - **What to build.** `analysis/increment/process_budget.py`: read the
    records, the ledger, the repair's ledger and the closure table, and print
    the budget per layer and for the column, with the remainder named as such.
    Each process's term must include `c` times its change of mass, as the
    offset's rule requires (E71 showed the remainder scales with `c`).
  - **What it would settle.** Whether the residual on a column is fully
    accounted for by the processes plus the solve, which is the question E23
    left open and which sections 6 and 7 of FINDINGS still list.
  - **Cost.** One short run and one analysis script.

## Plan

### A. Waiting for the owner

 1. **Confirm G1,** the intermediate goal at the top of this list, or adjust
    its criteria.
 2. **A manual `ci.yml` run on `main`,** for R1: the upstream groups on Julia
    1.10 with the new packages.
 3. **The attribution path** ([ATTRIBUTION_PATH.md](ATTRIBUTION_PATH.md)).
    Question 1, rebuilding the implicit channel on the parent's increment, was
    decided on 2026-09-19: the prototype is under way. Still open:
      + question 2, the conventions: whether the enthalpy form is the
        reference definition and not only an audit, and how `c` is chosen
        (U8; recommended: `c = c_p,d·T₀` = 274,388 J/kg, which counts dry
        internal energy from 0 K);
      + question 3, whether the prototype's correction may bring `e_src_res`
        to rounding by construction. Recommended: yes, with its own ledger,
        a switch, and a warning past a stated size. Needed before the
        prototype becomes a pull request.
 4. **Decisions, none urgent:**
      + section 2, item 14: the NaN tags under file-based initial conditions,
        first a refusal, then the fix. Needed before any tagged run from a
        file;
      + U8 and U9: how to choose the offset, and a headroom column. Before the
        first production run that spans a winter;
      + U7: starting tags from a checkpoint;
      + where the model's restart of C5's column stops being bit for bit
        (E58): 0M, the 12 hours, the code before #89, or
        `reproducible_restart: true`. It is upstream's, not the tags'. Short
        runs on the login node would separate it;
      + report upstream: `ShipwayHill2012VelocityProfile` fails on `ITime`
        (E57);
      + P7's optional fix (E56), which saves seconds.

### B. Can be done now, without a new approval

None of these writes model code, a default or a tolerance, or submits a run.
All seven were done on 2026-09-14.

 1. ~~**T3.**~~ #78: the tag and record code allocates nothing, checked in the
    integration files' own simulations, so CI compiles nothing more. #76 got
    the same check for its split solver: its update and its solve allocate
    nothing, while the unsplit solve allocates 48 bytes per call. That check is
    on #76 (`41432652`); its integration file passes 52 of 52 locally (T10).
 2. ~~**M3.**~~ Written, committed locally on
    `claude/energy-source-tag-species-lists`, to open with C1b. It reads the
    two species lists from `water_advection.jl` and fails on each of four
    mutations.
 3. ~~**C2's design.**~~ [RESTART_GUARD_DESIGN.md](RESTART_GUARD_DESIGN.md)
    (decision 11). The hash that `restart.jl` compares is stable across
    processes and changes with the offset, a region and the repair, but only
    warns.
 4. ~~**C1b's plan against #72 and #76.**~~ A new last section of
    `SUBGRID_AND_MICROPHYSICS_DESIGN.md`: the two PRs merge cleanly, B's anchors
    are where the design says, no tag gains a Jacobian block, and T6 should
    assert the split solver's uncoupled list on the EDMF column.
 5. ~~**A7.**~~ E49, `output/a7_gap_cancellation/`.
 6. ~~**Housekeeping.**~~ See section 5.
 7. ~~**A draft of the ClimaCore issue.**~~
    [CLIMACORE_ISSUE_DRAFT.md](CLIMACORE_ISSUE_DRAFT.md), with a ClimaCore-only
    reproducer (`analysis/climacore_nameset_repro.jl`). Not filed.

### C. Unlocked by merges, already approved

 1. ~~**C2**~~, the restart guard with T1, is #92, and V5 ran (E54).
 2. ~~**B1**~~, phase B's ten-day run of the energy tag family: ran on
    2026-09-18 (E50).
 3. ~~**C1b**~~, the EDMF sharing, is #91. Its validation ran: the D4 pair,
    D4 with the updrafts' vertical diffusion and D5 (E53), and D4 in Float32
    (E55).
 4. **After #91 merges:**
      + C1c, the audit's share of the SGS diffusive flux, as a draft PR. E53
        points to the eddy diffusion as D4's remaining residual;
      + V2 as a ten-day Float32 run with the production physics, V1 folded in,
        and V6, topography (both approved);
      + then the calibration of U2's tolerance, and D1 with D3.
 5. **Done on 2026-09-18:** the worktrees of merged branches are removed
    (section 5).

### D. Needs a new approval

 1. **A4,** signed overlay shares: model code and a C9 twin (N, later).
 2. **Runs:** MP1 on more than one node; an audit twin of D1 (section 6).
 3. **The N items that change model code:** C6's leftovers, C7, A6, P2, P3,
    U5, U6, U7, R5, A2's runtime part and A3.
 4. **The GPU,** last, with T3.

## Done, for reference

  - **Model:** C1a and M2 (#70); C3 and R2's timing (#72); the #69 help text
    and records comment; the runscript's `srun --mpi=pmix`.
  - **Runs and analyses:** D1 and its twin (E42, E42b); R4 (E39b, E43); the D4
    pair (E40, E44); the D4 build control (E44); P4's split test (E44b) and
    stage timing (E44c); P4's inference profiles (E44d); P4's fix on EDMF
    (E44e); V3 (E45); C5's repair
    trades (E46); MP1 (E47); the 10° mask twin (E48); P1 (T9).
  - **Docs:** the guide's fixes 1, 2, 6 and 8 (#69, #70); 3, 5, 7, 9 and 10
    (#72, #74).
  - **Pull requests opened on 2026-09-14:** #74 (D2), #75 (T2), #76 (P4's
    fix), #77 (B9).
  - **Merged on 2026-09-17 and 2026-09-18:** #72, #74, #75, #76, #77, #78,
    #79, #81, #85, #87, #89, #90; the CI work #82, #83, #84 and #86.
  - **Runs of 2026-09-18:** B1 (E50), the parity of #89 and of C1b (E51),
    C1b's validation (E53), V5 (E54), C1b in Float32 (E55), and P7's
    measurement (E56).
  - #72 merged into this branch (`57ed9c1f`).
