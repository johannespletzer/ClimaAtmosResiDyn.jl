# Status

## Part 11a energy references, design (2026-10-09)

The [pre-registered design](design/PART11A_ENERGY_REFERENCES.md) builds the
eight cases of G4_CLAIM_CONTRACTS section 6 as offline known answers. Each
case freezes its convention `c`. Stored-energy cases and the radiation record
are separate references. The tools and tests are in `analysis/evidence/`
(`energy_reference*.py`). Every case's wrong-origin mutant is caught in a
test. The [PX22 draft](configs/part11a_px22_draft/README.md) waits for the
owner. **Part 11a is not done.** No run, scorer, default or tolerance change
is supplied.

## Part 8 water baseline and cost pilot, design (2026-10-09)

The [pre-registered design](design/PART8_BASELINE.md) fixes the baseline of
the TRMM 0M 6 h pilot on `main` `bb2bedf23` before any job: the
configuration, both modes and the twin, the contract's rows and which are
scored or reported, the thresholds by ID, the OD2 reading, the ranked table of
error terms with a fix candidate per term, and the cost at 8 + 8 tags on D4.
Nine jobs are scripted with their estimates (`runscripts/part8_trio.sh`,
`runscripts/part8_cost.sh`), about 20 node-hours. None is submitted.

`analysis/evidence/part8_pilot.py` is the glue. It reproduces W58's 18 TRMM
table rows bit for bit from the repository's `output/g3base/data/`, reads OD2
at the twin's own cadence and builds the ranked table. It adds no threshold.
On W58's twin OD2 finds the boundary at 0 s at 10 min and no established
window at 30 min, so the design fixes which reading the record states. The
[record skeleton](analysis/evidence/PART8.md) has its sections and no numbers.

**Part 8 is not done.** The runs, the record and the ranked table wait for
the owner's approval of each job and for W58's archive sync. The first-hour
origin verdicts wait for PX12 (part 7). Four choices of the design's section
12 are decided (2026-10-09), the rest are proposed. No model, default, tolerance or scorer change is supplied.

## Part 7 independent water-transfer software (2026-10-08)

The [transfer design and obligation inventory](analysis/evidence/PART7.md)
have runnable independent donor-composition equations for one-way transfer,
opposing net-zero exchange, a three-compartment cycle, unequal compositions,
empty and depleted donors, zero activity and separate rain and snow column
exports. A declared negative-water map is an engineering test, not a
physical negative composition. Pool replay and pool/net audit spread stay
apart from reference error. Each case's control keeps the parent and every
total and fails an origin row. Only the one-way case has a true wrong-donor
control. The opposing case erases the exchange, the sedimentation case
resets the owner and the other six permute origins.

The adapter follows Part 6's reviewed pattern. It is the producer of a
declared eligibility file that the unchanged scorer reads. Both nine-case
suites, exact and RK4, retain 36 RK4 and 28 pool rungs and exit 0. Eight
cases have eligible rung-64 references, the largest floor fraction being
`8.310061860770055e-5`. Zero activity covers no rule by design (decision of
2026-10-09), so its candidate stays not assessable and the driver counts it
as not applicable. [Commands](analysis/evidence/README.md#independent-water-transfer-fixtures)
reproduce this work. The whole evidence directory passes.

**Part 7 physical qualification remains incomplete.** These six-label
prescribed-rate development cases check conditional attribution equations,
not model microphysics rates, atmospheric PX14 or PX25, or precipitation and
EDMF stages 2 and 3. The [PX25 draft matrix](configs/part7_px25_draft/README.md)
of 16 tagged arms and 8 parents is a draft pending the owner. OD15 is
proposed. The 1500 s case has no approved hour or day score, and the second
established-rain case is unselected. Its PrecipitatingColumn starts from
RICO's profiles, and RICO 1M 24 h is the held-out case (WA-SCOPE), so OD14
independence is an owner item. Accepted rates and substeps, corrections,
Part 5 production capture, eight tags and full windows, parity, restart,
device and cost remain required. The full acceptance scorer on a development
fixture keeps `NOT QUALIFIED` and exit 2. No model, default, tolerance,
dependency or CI change is supplied. Older dated records below retain their
scope.

## Part 6 independent water reference software (2026-10-08)

The [frozen design and obligation inventory](analysis/evidence/PART6.md)
now have runnable native cell-average known answers for signed periodic
translation with advected nonuniform density, signed labelled inflow on
nonuniform cells and conservative two-reservoir exchange. Independent
quadrature and conservative upwind / implicit-Newton references report every
registered rung. The adapter is the producer of a declared eligibility file,
as the decision of 2026-10-07 allows. The manifest names and hashes it, and
the reviewed scorer reads the declaration through its own reader, unchanged.
Wrong-origin label swaps preserve total closure and fail the origin rows.
Fixture PASS also requires candidate partition closure and the prescribed
exported-parent trajectory. Same-parent status comes from the actual parent
values. Mutant verification checks the registered swap and unchanged initial
state, parent and source overlays.

The analytic fixtures pass all five equation cases and label-swap checks.
Their eligibility is constructed, not measured: the candidate equals the
closed form, and the floor is a constructed roundoff bound, plus a measured
quadrature floor in the smooth cases. The numerical fixture suite returns
exit 3. All four upwind references exceed OD12's quarter rule. On the
fixed-CFL ladder the smooth and positive-front floors fall at every doubling,
and the negative front rises on its first doubling. The
exchange reference is eligible on a measured floor. Every one of the 21
numerical and 18 quadrature rungs is retained, including failures. The 38
focused tests and the whole evidence directory pass.
[Commands](analysis/evidence/README.md) reproduce the bounded work without
launching a model run.

**Part 6 physical qualification remains incomplete.** These five-label
manufactured development cases establish implementation checks only. They
supply no atmospheric PX1/PX8/PX7/PX11/PX24/PX12 execution, actual copies
grid/updraft residual/repair/mirror/Jacobian/fallback evidence, KI4-COPIES/UP1
verdict, eight-tag/full-window reference, OD14 held-out result or production
origin qualification. Part 5's verified runtime-producer registry remains
empty. No parent model, default, dependency, CI or approved tolerance changes
are supplied. Residence-time and energy-reference work stay deferred. Five
choices wait for the owner, listed in PART6's obligations table.

## Part 5 offline accounting layer (2026-10-07)

The [Part 5 inventory/design](analysis/evidence/PART5.md) and existing
[evidence workflow](analysis/evidence/README.md) now include a strict native
weighted-application reader, cancellation-safe S/H/A and directed-leg
reports, distinct trial/evaluation counters, and paired signed parent/tag
precipitation integration. The 71 accounting tests and the evidence
directory's 228 tests pass. These are offline results only.

**Part 5 remains incomplete.** No verified producer exists, so no submission
clears the production completeness gate. [PART5](analysis/evidence/PART5.md)
lists the runtime evidence that is still missing. PR #146 merged on main at
`12377fb88` on 2026-10-07. Its closing channel is not on this base yet.
No runtime/default/checkpoint/dependency/CI/threshold or historical output
changes are supplied.

## Part 4 offline evidence and scoring (2026-10-07)

The common manifest extension, strict native readers and deterministic
water/energy row scorer are implemented in
[analysis/evidence](analysis/evidence/README.md). The
[coverage matrix](analysis/evidence/PART4.md) identifies measured rows and
explicit remaining scientific gates. All 89 offline analytic/fault tests pass.
Reviewed on 2026-10-07, see the PR's review comment.

This raises software capability only. No simulation, physical qualification,
new default, tolerance, dependency or CI change is supplied. Historical
scorers and results remain unchanged. Missing accepted-application accounting
is Part 5. Independent water/transfer/energy references are Parts 6/7/11a.
Actual integrated/cost/restart/held-out qualification evidence remains in
8/10/11b–d/12, with the existing owner approvals still required. The radiation
record is an unqualified diagnostic (EA-USE, 2026-10-07): reported, with no
stored-source throughput/copies gate and no accuracy, cost or scope row.

## Current delivery entry point (2026-10-06)

The active plan is [ROADMAP.md](ROADMAP.md#the-execution-order).
[PLAN_CROSSWALK.md](PLAN_CROSSWALK.md) preserves every source obligation and
its delivery destination. The dated status narrative below is evidence
history. Use the newest applicable finding and decision, not the oldest
unchecked task, to establish completion.

| Capability                                                                                                                            | Evidence now recorded                                                                                                                                                                                                                                                                                                                                    | Next increment                                                                                                                           | Limitation                                                                                                                                                                                                                     |
|:------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Water, D4-W                                                                                                                           | Parity and closure evidence exists. W54 comparator repair still fails. Cost is measured and fails criterion 10 against OD3's 2× (8 + 8 step 4.16×, kept 2026-10-07).                                                                                                                                                                                     | Parts 2/4/5. Per-tag accuracy moves to TRMM 0M and Soares in part 6 (option D).                                                          | Criteria 5/6 are not judged on D4-W under option D. No validated origin claim. The cost budget waits for the owner.                                                                                                            |
| Water, TRMM_LBA 0M entry/source inventory pilot (development pilot, WA-SCOPE decided 2026-10-07), Float64 / three tracers / six hours | Level 0 in part: label meanings, observable and configuration documented in Part 2. WA-SCOPE (2026-10-07) gives it no qualified scope. It scores the first-hour row only, after PX12. W58 records both-mode parent parity, default closure and instantaneous partition precipitation near rounding. Copies residual/repair passed those measured checks. | Parts 4/5 complete data/accounting, Part 6 PX12 and independent active-rule coverage, and owner WA-SCOPE/WA-COST before a qualified use. | `pbl`/`free` are entry-mask partition labels, `evap` an overlapping source tracer. W58 R7 is reported only. No PX12 refinement, no six-hour/eight-tag qualification, and workflow restart evidence is not established here.    |
| Water, clean transport references                                                                                                     | PX11/PX24 remain the scheduled source-free reference route.                                                                                                                                                                                                                                                                                              | Part 6 after contract floors/accounting and OD14 held-out freeze.                                                                        | Validates only named active transport rules. It cannot qualify precipitating EDMF or surface origins.                                                                                                                          |
| Water, 0M surface precipitation origins                                                                                               | W58 C7 is an instantaneous accounting report in the three-tag pilot.                                                                                                                                                                                                                                                                                     | Parts 4/5 paired accumulation, Part 7 independent attribution, and owner WA-PRECIP.                                                      | No approved 0M C7 tolerance or accumulated per-tag window evidence from the current overlay. Exact sum does not prove correct origins.                                                                                         |
| Rain/snow, non-EDMF stage 1                                                                                                           | PR #146 merged on `main` at `12377fb88` on 2026-10-07. Implementation/test evidence differs from qualification.                                                                                                                                                                                                                                          | Part 5 cancellation accounting, part 7 attribution against known compositions, applicable part 9 integration.                            | Stage 2/3 EDMF and independent origin evidence remain open. A signed closing ledger cannot bound cumulative error.                                                                                                             |
| Energy, signed-radiation record (unqualified diagnostic, EA-USE 2026-10-07)                                                           | Level 0: Part 3 defines one-record/zero-source-tag non-EDMF DYCOMS use, independent flux route and explicit exclusions. C3/C5 give historical interpretation evidence only.                                                                                                                                                                              | Parts 4/11a/11b. Not qualified (EA-USE, 2026-10-07). Verified in 11a and reported.                                                       | No 24 h workflow parity (a two-step integration test covers parity and checkpoint restoration), independent accepted-stage flux, reference floor, restart continuity or measured cost. No stored-source or total-budget claim. |
| Energy, stored source provenance / EDMF                                                                                               | Level 0: fixed-convention meanings and applicable matrix documented. Tags/records and historical conditional budgets exist. E84 copies remain ineligible.                                                                                                                                                                                                | Parts 4/5/11a then 11b–d. Existing OD7/OD11 and seven-point level gates.                                                                 | cΔρ is not generally cΔwater. Θx nets within a cell/accepted step. C4 per-tag outflow, intervention and independent origin coverage remain open. Water qualification is not energy qualification.                              |
| Production envelope                                                                                                                   | W59 MPI and W60/W62 precision evidence cover stated cases only.                                                                                                                                                                                                                                                                                          | Part 12 after relevant qualification and cost gates.                                                                                     | Preserve W60 failure and W62's narrower pass. No blanket production verdict.                                                                                                                                                   |

No evidence level is assigned yet. Parts 2 and 3 define what each level needs. No level is assigned to a whole family without matching the required
configuration-specific evidence. Residence-time and air-age work is deferred.
G4.14 loss timescales and PX19 correction-flush screens are not ages and keep
their existing gates. This change is documentation only: no simulations,
model changes, threshold revisions or merges.

**Part 2 documentation:** the water use/definitions, equations, acceptance
matrix, reference gates, tolerance rationale and twelve-criterion disposition
are documented in [G3_PLAN](G3_PLAN.md#21-part-2-the-first-useful-water-workflow-proposed-2026-10-06),
with the [matrix in 6.1.2](G3_PLAN.md#612-water-acceptance-matrix-authoritative-part-2-specification).
The independent review of the actual diff is pending. Part 2 is recorded
complete only after its findings are resolved. WA-SCOPE,
WA-PRECIP, WA-COST and WA-GATES were decided on 2026-10-07 (DECISIONS). They
approve no new tolerance.
Preparing this contract does not raise scientific qualification. Current
cell-step retained and attempted ledger readings remain useful but cannot
exclude cancelling applied corrections. Parts 4/5 own the documented scorer
and accounting gaps. OD5's historical conditional verdict is retained
without a mathematical error-bound claim. OD9–OD11 remain proposed.

**Part 3 documentation:** energy meanings, equations, proposed first signed
record use, [canonical matrix](design/G4_CLAIM_CONTRACTS.md#5-energy-acceptance-matrix),
reference designs and downstream obligations are prepared. Independent
actual-diff review and final consistency validation are in progress. No
scientific evidence level is raised. EA-USE, EA-STATE and EA-C4 were decided on 2026-10-07 (DECISIONS). The
record stays an unqualified diagnostic, growth-only scoring stays, and the
C4 reading amends E87. EA-ACCURACY and EA-COST lapse with it. OD7/OD9–11 and remaining G4
numerical levels keep their gates.
The approved OD4 scale is defined exactly as the code records it, including
within-step cancellation, and legacy interim/runtime estimates are separated.
Parts 4/5 own density differencing, persistent-state residual and accepted
activity scorer/accounting gaps. No executable change was made here.

**Part 3 source recheck, 2026-10-06:** PR #147 remains open/unmerged at
`24b7536a351c57f4c5b639b868e6b499acc4e763`. PR #148 is open/unmerged on
`codex/water-acceptance-part2` at `fb8ddf62540df8c36095313bec3dee17aa2b5206`,
with Part 1 as its base. Part 2 is one six-document commit ahead. Part 3 uses
that exact immutable source/planning snapshot, with current `main`
`d3c5e42f54515729f53216ae6b8ba268bea8262f`. These branch checks do not reverify
PR #146 or establish current simulation qualification. The review of 2026-10-07 then patched Part 1 to `d68ab8e6a` and Part 2 to `be77a25db`, merged forward into this branch. The snapshot heads above are the ones this document was derived from. Part 3 itself is the branch `codex/energy-acceptance-part3`, stacked on Part 2.

**Source state rechecked 2026-10-06:** Part 1 PR #147 is open/unmerged on
`codex/plan-capability-increments-part1` at
`24b7536a351c57f4c5b639b868e6b499acc4e763`, against `claude/plan-rev2`
`58d3535467dc330f1baf1a69936d683c778a3d18`. Part 2 uses that immutable
documentation/source snapshot. It creates no model-result evidence. PR #146's
recorded October 5 status below has not been reverified by this source check.

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

  - **Update, 2026-10-02: W59's moist pair (addendum, reviewed).** The owner
    asked to close W59's dry-start bound. From the moist baroclinic wave
    with EDMF, on a flat sphere at h_elem 2, cloud, rain, snow and surface
    precipitation are present at every output after 0 h. The tagged runs
    are bit for bit their twin on two ranks in both modes (0 of 884,736
    state values, 0 of 54 diagnostics). Criterion 3 is met without the
    dry-start bound, on two ranks for 6 h. Opus review 2026-10-02: the
    numbers reproduce, the moist runs compare the same 19 `Y` fields, and
    the 1M species are nonzero in them. The moisture gate's thresholds were
    set after the smoke, so the gate is labelled as not blind.

  - **Update, 2026-10-02: W59, criterion 3 on two MPI ranks.** On the G2
    sphere's physics at h_elem 2 for 6 h, the tagged runs are bit for bit
    their untagged twin on two ranks, in both modes (0 of 884,736 state
    values and 0 of 54 diagnostics differ). The start is dry, so by 6 h only
    0.17 kg m⁻² of surface water is in, with no cloud or rain. So the check
    covers the MPI paths, not the moist physics on two ranks. One rank and
    two differ in every model field from 30 min, with or without tags. The
    parent's negative water is 0.52 of its net water (0.34 of its positive
    water) at 6 h. Criterion 3 is met for the MPI paths (W59, reviewed).

  - **Update, 2026-10-02: criterion 9 under the rounding floor (W62,
    reviewed).** After W60's addendum the owner set the floor
    `max(10 × Float64, 3 · eps32 · √n_steps)`. On fresh runs at ten Newton
    iterations (`design/F32_TWIN.md`, section 10) every judged measure
    passes in both modes. The least margin is the default's
    `q_tag_inc_left`, 4.35e-6 of the water against 9.60e-6. The floor
    decides only the default's rows. The default's fresh pair repeats the
    addendum's runs bit for bit, so there the pass shows consistency with
    Float32's rounding, not an independent test. The copies are new data
    and pass the plain 10× rule. W60's registered verdict at ten iterations
    stays "fails". Criterion 9 stays partial: the rain and snow tags'
    Float32 closure waits for T3's stage 2.

  - **Update, 2026-10-02: V-W7's named parts (W60 addendum, draft).** In

  - **Update, 2026-10-02: V-W7's named parts (W60 addendum, reviewed).** In
    Float64 the named parts leave 4.1e-7 of the water at 24 h with one Newton
    iteration and 3.8e-13 with ten, so criterion 4's named-parts clause
    passes (1e-6). Criterion 4 stays partial on the copies' repair and the
    rain and snow tags. In Float32 ten iterations leave 3.2e-6 and a
    residual of 3.9e-6, 8.5 and 1.8 million times Float64's, so criterion 9
    fails on the named parts at ten iterations. Those Float32 values sit at
    Float32's accumulated rounding, about eps·√n (3.2e-6 at 24 h), and the
    10× limits lie below the Float32 partition's 1.7e-8 at 0 h. So the
    failure cannot tell a defect from rounding. With one iteration they are
    within 10 times at 24 h (9.1 at most, at the same rounding level; 14.5
    at 12 h, not judged). The owner set a rounding floor on 2026-10-02,
    max(10×Float64, 3·eps32·√n), to be judged on a fresh, pre-registered run. The rain
    and snow tags' Float32 closure waits for T3's stage 2.

  - **Update, 2026-10-02: V-W7, the Float32 twin (W60, reviewed).** D4-W in
    Float32 on `main` `d3c5e42f` (`design/F32_TWIN.md`). Both modes are bit
    for bit the Float32 twin. Each judged criterion-4 measure is at most 1.21
    times its Float64 value (the default's second 12 h), against criterion
    9's 10. So criterion 9 passes on what was measured, and stays partial:
    the named parts and the rain and snow tags are not assessable in either
    precision. The default's residual is 85 times Float64's at 1 h, which no
    rule judges; Float64's value there is below Float32's rounding level.
    The copies' repair still fails criterion 4's own row (3.29e-3 a day). P0
    reproduces W55's default run bit for bit on `d3c5e42f`. W54's twin and
    copies were not rerun, since their code changed only in text.

  - **Update, 2026-10-02: transport-1 on a sphere (W61, reviewed).** Measured
    after the fact for the WP4b fix PR (#146, merged 2026-10-07), one configuration: the
    moist baroclinic wave at `h_elem` 6 with two region tags under the key, 3
    days. `main`'s form of the tags' hyperdiffusion raises their variance on
    the states it makes. The passive form lowers the repair and emptying
    ledgers 14.6 to 43 times and the parts' residual 54.7 times. The
    emptying's ratio falls with time (49 at 1 day). The rescale's ledger
    hardly moves (0.98 at 3 days). The anti-diffusive regime
    `0 < q_tot_eff < q_tot_r` is inferred from a flat state, not located on
    the sphere. The passive form's exchange of inventory between tags was not
    measured.

  - **Update, 2026-10-02: option D accepted.** D4-W has no eligible comparator
    at production cost (W54, PX5). Criteria 5 and 6 are not judged on D4-W.
    Per-tag accuracy moves to TRMM 0M (after PX12) and the Soares air twin
    (PX11). See DECISIONS and the note under G3_PLAN's criteria.

  - **Update, 2026-10-02: the G3 baselines on the new physics, and W53.**
    Five findings rerun the baselines at `b34bbd8b`. Each names the old one it
    updates.

      + **W54 (W50's C):** the copies' repair still fails R5, 3.98e-3 of the
        water a day against 2e-3. PX5 finds no eligible D4-like comparator at
        production cost. PX12 (W50's B) comes next.
      + **W55:** the D4-W default day closes to 6.5e-6. Over the whole day
        the partition repair is 1.2e-2 a day.
      + **W56:** the surface pulse's copies at 30 levels pass R5 in the
        window, 1.36e-3 a day. Over the day they reach 2.39e-3. Run 12 (P2 at
        30 levels) passes R6, so R7 is a verdict: it fails on `sfc` at 1 h,
        L1 12.6% against 1%. Every tag passes at 24 h.
      + **W57:** the parent's Newton error is 4.1e-3 at two iterations and
        1.4e-3 at four.
      + **W58:** TRMM 0M closes to 3.8e-15 in both modes.
      + **W53:** the revision's rule alone makes V5's `led_fix` rise at site
        23. Where the repair refills `free`, the follower drained it in the
        same step (share 0.999; 0.591 for `pbl`).
      + **Answered by the owner later on 2026-10-02** (DECISIONS):
          * why the follower drains `free` more under the rule: a probe will
            be pre-registered;
          * V5's 2% limit, since `main` is at 2.7% and 2.3%: it stays;
          * OD2's windows, which do not mark a startup on the new twins
            (their peak tendency comes at 3.2 to 3.3 h): the rule stays, and
            each finding that uses it adds its verdict from 1 h as a
            sensitivity row.

  - **Update, 2026-10-02: physics baseline.** Main is `b34bbd8b` (2026-10-02).
    Its model physics is upstream `a9287b2d`. Nothing was run for this entry.
    The record was changed only.

      + **The merges:** #139 (`24c1aaa0`, upstream `a9287b2d`, on the previous
        upstream base `d331fe30`), then #140 (`5e67d344`, the parent-budget
        docs) and #141 (`b34bbd8b`, the vapour-constraint registry row is
        zero, zero, zero).
      + **What changed for the tag runs (#139's upstream physics):**
          * the Ri weight on the SGS variance (#4837);
          * uniform SGS-quadrature fractions (#4850);
          * the SGS parameters out of the provisional set (#4856);
          * implicit vertical Smagorinsky (#4824);
          * correctness fixes (#4842);
          * the empirical `l_TKE` (#4853);
          * an ice-formation option (#4859);
          * CloudMicrophysics from 0.40 to 0.43 (#4847 and #4866; the fork's
            compat was 0.39 and 0.40). The 1M replay passes `w`.
      + **Compat:** ClimaParams 1.2 sets `sgs_variance_horizontal_scale_factor`
        to 3.0, as 1.1.16 first did. ClimaParams 1.1.15 does not define it,
        so the fork's own default of 0 applied. This ends #128's 1.1.15 cap
        and the drift it held off. CloudMicrophysics is 0.43.
      + **Parity:** the fork matched `a9287b2d` bit for bit on 7 configs (PR
        #139's body).
      + **The rule:** gated runs use post-#139 `main` (DECISIONS, 2026-10-02).
        Old-physics numbers keep their commit label and are prior evidence
        only. They are listed in [G3_PLAN.md](G3_PLAN.md), section 10, each
        with the rerun that will replace it, or "none planned".
      + **The run base:** a clean detached run tree at `b34bbd8b` or later,
        with `.buildkite/LocalPreferences.toml` copied in. The CI-version test
        envs are `$SCRATCH/claude_work/main_{ci111,ci110,docs}_env`. Slurm is
        `-A pn49go-c -p hpda2_compute`. A smoke run at `b34bbd8b` (the BOMEX
        EDMF column, 10 steps, job 14095717) passed.
      + **The reruns:** tasks 5 and 7 of `agent-progress/goals-2026-10-02.md`
        (outside the repository). Task 5 is WP9's cost, which gives W52 and
        E88. Task 7 is the G3 baselines, including W50's C. Their items are in
        [G3_TODO.md](G3_TODO.md) and [G4_TODO.md](G4_TODO.md), under "Reruns
        on the new physics". Nothing is ticked.
      + **Not planned:** the energy findings E84, E86 and E87, the sites 23 and
        26 runs, the sphere and the rest of the "none planned" rows. G4's
        levels come from post-#139 runs at G4's start.

  - **Update, 2026-10-02: the owner's walk-through.** The owner chose the
    recommended option on all five items (DECISIONS.md, 2026-10-02). Nothing
    was run. The record was changed only.

      + **Provenance pathway:** OD12, OD13 and OD14 are accepted, because
        they gate runs. OD9 to OD11 stay proposed until a gated result
        exists. OD15 is answered at PX25's pre-registration.
      + **New rule:** gated runs use post-#139 `main` (`24c1aaa0` or later;
        #139 merged 2026-10-01 with upstream `a9287b2d`). Numbers measured on
        the old physics keep their commit label and are prior evidence only.
      + **WP4b:** one fix PR, two to three days, for the five points and the
        review's four should-fix findings. Not built.
      + **W50:** the copies' repair is open. First, rerun W50's 60-level
        copies day and its twin on post-#139 `main` (two jobs) and score
        PX5's rule. Then PX12 on TRMM 0M (about 12 short jobs). Not
        submitted.
      + **G4.3 to G4.6:** the definitions are decided (points 1, 4's form, 5
        and 7). The levels of points 2, 3, 4 and 6 are set from post-#139 runs
        at G4's start.
      + **KI4-COPIES and UP1:** a fixed-parent one-step probe is folded into
        PX12. UP1 is decided by its own rule.

  - **Update, 2026-09-30.**

      + **Merged:** #127 (the #121 follow-ups), #128 (ClimaParams capped at
        1.1.15), #129 (the #119 follow-ups; the docs split,
        `tagged_water_api.md`) and #130 (WP4a-J,
        `water_tag_rainout_jacobian`, opt-in and off; known issue 4 closed for
        the grid rule, W51; plus a Julia 1.10 allocation fix in
        `update_diffusion_jacobian!`). Other sessions merged #131 to #134
        (tiered CI, split memory groups, docs simplification, CI for other
        workflows).
      + **WP4a-J is closed** (2026-09-30), by the checklist in README.md: W51
        in FINDINGS, the 17 runs in RUNS, `output/wp4aj/` with the #130 fix's
        checks in `tests_130/`, and the decision (off by default) in
        DECISIONS. Its follow-up, the copies' part of known issue 4 and UP1,
        waits for the owner.
      + **PR #135, merged 2026-09-30** (`b983d62b`; the WP4b review's transport-2):
        `q_tag_leak_vdiff` and `q_tag_leak_sponge` report under the rain and
        snow key. After the owner's review, the leak means the raw
        difference, in both modes: the path's source for `q_tag_res` plus
        `q_tag_negative`, evaluated at option C's target. Its tests are
        running.
      + **WP4b stage-1 review**
        (`review/agent_reviews/wp4b_stage1_review_2026-09-30.md`): 12
        findings kept, none moving a model field. The should-fix ones are
        micro-1, transport-1, transport-2 (in #135), state-1 and state-2.
      + **W50** (the W21 surface rule at `03eb4dbd`): R1 and R4 pass. R5
        fails on all rungs (the copies' repair is 3.9e-3 to 4.6e-3 a day
        against 2e-3), so R7 is not assessable and D4-W's provenance stays
        not assessable. The pulse's surface first hour is 13.1% (fix)
        against 14.3% (main), budget 1%.
      + **W21 is closed** (2026-09-30): #136, W21's plume surface-flux start
        for water and energy, is merged (merge commit `6657ae6c`). It gives
        the default mode's water and energy plume the surface flux at the
        lowest level. The rule is chosen and test-supported, not validated as
        a provenance improvement: W50's comparator fails its repair criterion
        (R5), so the first hour stays not assessable. E89 (the energy
        measurement on D4) is reported, not judged: R1 passes, and `sfc` and
        `new_tropo` move by 7.3% and 7.1% (L∞) at 1 h. The review's eight
        test jobs (`14014802` to `14014809`, Julia 1.10.12 and 1.11.9 with
        CI's versions, at `2ebf7648`, one docs-only commit before the PR
        head) all passed. The record is W50 and E89 in FINDINGS, the RUNS
        section "W50 and E89: the review checks of #136", and `output/w50/`
        and `output/e89/`.
      + **C's revision** (W49, `design/NEGATIVE_PARENT_WATER.md` section
        11): the code is on `claude/option-c-revision` (`a4b492ec`), with the
        rule, coupling-1 and the review's wording fixes. The 30-day parity
        passes Q8 twice (`cfb72587`, `a4b492ec`). Every model field is bit
        for bit, and the tags differ from `main` from about day 11.5. The
        rule review (`review/agent_reviews/crev_rule_review_2026-09-30.md`)
        found no blocker. Its kernel-1 is in Q2. One test bug in the
        coupling-1 test is being fixed. The owner's section-11 review (Q2 to
        Q9) is pending. The 90-day validation waits for it. *Superseded
        2026-10-01: W49 ran, the owner decided on its verdicts, and #137
        merged (`b4ebfca5`); see the update line of 2026-10-01 below.*
      + **WP9:** the first pass was noisy (19 of 30 points spread over 10%,
        node contention). The exclusive-node rerun (jobs `14005213` to
        `14005221`) is pending, with an estimated start of 2026-10-01. The
        energy finding number is E88 (E79 is taken). The budget waits for the
        owner.
      + **G3's criteria** are restated in
        [G3_TODO.md](G3_TODO.md#g3-is-met-when).
      + **Owner decisions of 2026-09-29/30** are in
        [DECISIONS.md](DECISIONS.md).

  - *Superseded 2026-09-30: met on 2026-09-29 (W48, the C brief, #127 and
    #129 merged).* **The session goal of 2026-09-28** (the owner). It is met
    when:

  - **Update, 2026-10-02: WP9's cost measured on the new physics.** W52 and E88
    are recorded, after an Opus review (`b73df5ec`, numbers and wording; no
    verdict changed). Every arm ran with its own untagged
    baseline on the same exclusive node, and the first timed block was
    discarded (`design/WP9_COST.md` sections 10 and 11, at `b34bbd8b` and
    `d3c5e42f`). Every point quoted passes the 10% spread rule. The default
    mode costs 1.43× at 8 water tags (TRMM), 1.58× at 8 energy tags (D4) and
    4.16× at 8 + 8 on D4, 9.10× with ledgers. The two families do not add:
    alone on D4 they cost 1.44× and 1.53×. **The 8 + 8 step time exceeds
    OD3's ceiling of 2×, approved 2026-09-24.** *Decided 2026-10-02 (the
    owner): profile first, then decide. OD3's 2× stays for now, so criterion
    10 is recorded as failing.* Under `design/WP9_COST.md` section 12 (drafts,
    reviewed 2026-10-02): E90 locates the 8 + 8 excess in the parent's
    walks over tracer names, at least 51% of it and about all of it for the
    stepper, not in the tag code. Inferred from the code: `propertynames`
    of `Y.c` runs at run time once `Y.c` has 32 fields or more (8 + 8 has
    38). A fix would be pure performance, best in ClimaCore. OD3's copies
    row fails: both families' copies at 8 built in 4 h 16 min, 6.8% over,
    on the slowest of three nodes.

  - **The session goal of 2026-09-28** (the owner). It is met when:

     1. the extended probe of section 9.7 has run and is scored and
        recorded as W48;
     2. the owner has a decision brief on C's revision, drawn from W47 and
        W48, with options and a recommendation;
     3. two PRs against `main` are open, with the #119 and the #121
        follow-ups from the backups, and both pass the tests locally and in
        CI.

    WP4a-J, W21's surface flux and the walk-throughs come later.

  - **Update, 2026-09-29: WP4a-J, draft (the `wp4aj` agent).** The pair is
    built behind `water_tag_rainout_jacobian`, `false` by default, on
    `claude/wp4a-j-jacobian-switch` at `f2c1e6a5` (not yet a PR). Its tests
    pass, each of four mutants fails its test file, and the branch without
    the key matches `main` bit for bit (jobs `13999575` to `13999577`). The
    pre-registration is `design/ZERO_M_SPLIT.md` section 5.1, with no new
    tolerance. Its 17 runs (`13999648` to `13999664`) are scored as **W51:
    known issue 4 is closed on the raining 0M column.** One Newton iteration
    without the entries stays within the first-hour budgets at 1 h, at worst
    1.52e-3 in L1 against 1%. The pair keeps every model field bit for bit,
    moves the tags by at most 1.75e-5 in L1 and changes the one-iteration
    error by at most 1.5% of it, with a sign that depends on the tag.

      + *Departures from the design,* dated amendments in 5.1: the run count
        (17, against section 5's "eleven"; its table lists thirteen, plus
        the 40-iteration checks and an untagged twin); zero entries where
        the share is clamped or `ρq_tot ≤ 0`; the block to `ρq_tot` a
        diagonal row, not a tridiagonal one. After the runs, the verifier's
        pairing allowlist gained the new key; no number changed.
      + *Decided 2026-09-29:* the switch stays opt-in and off by default, as
        proposed (5.2). Known issue 4's update, drafted in 5.2, is applied to
        `docs/known_issues.md` on the model branch for the PR.

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
            later. *Done 2026-10-02:* see the walk-through update above.
      + *W48, 2026-09-29:* the extended probe on `main` (section 9.7). By
        leave-one-out, subsidence carries every rise (84% to 95% of the
        forcing's growth goes without it), and the vertical fluctuation
        carries none. The mechanism is shown cell by cell. C's revision
        waits on the owner, with W47 and W48.
      + *2026-09-29:* the owner chose C's revision: the explicit brackets
        give the region tags the target's gain (design section 10, option
        1). ClimaParams v1.1.16 turned `main`'s CI red by switching on the
        geometric SGS-variance term. #128 caps it at v1.1.15.
      + *W50, 2026-09-29:* W21's surface rule, measured at `03eb4dbd` (the
        water fix), not the PR head. R1 and R4 pass in both arms. R5 fails on
        all three rungs: the copies' repair is 0.37% to 0.45% of the water a
        day against 0.20%, the same in both arms. So provenance and the first
        hour stay not assessable. The rule lowers `evap`'s and `sfc`'s first-hour
        L1 but raises some L∞ and 24 h numbers (FINDINGS W50; the two scorings agree
        on every verdict).
      + *E89, 2026-09-30:* W21's plume start on D4 (W50), measured at
        `10cdeebd`. R1 passes in both arms and closure is 5.3e-14. `sfc` and
        `new_tropo` move by 7.3% and 7.1% (L∞) at 1 h. `sfc`'s column integral
        rises by 2.3e-3 at 1 h, and the post-hoc read shows an upward shift.
        Reported, not judged (FINDINGS E89).
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

| PR           | Branch                                   | State                                                                                                                                                                                                                                                                                                                                                                                 | What                                                                                                                                                 |
|:------------ |:---------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------- |
| #95          | `claude/energy-source-tag-updraft`       | merged 2026-09-23, 16:32 (`0b2b1032`), at `b9c6e7b0`. That head fixes the allocation tests that failed CI at `afd470e7` (E77's erratum, E78); the tags' tendency is bit for bit that of `afd470e7`, so E76 still describes it. At the merge, CI at `b9c6e7b0` was still running with no failure: 6 checks passed, 34 queued or running. `main`'s CI at `0b2b1032` was queued at 16:40 | the updraft gap: the exchange by default, updraft copies as the audit, with the partition-only factor                                                |
| #96          | `claude/terrabyte-setup`                 | merged 2026-09-23, 12:12 (`3ecb6d25`)                                                                                                                                                                                                                                                                                                                                                 | the terrabyte setup script, its stack file, and the docs that name both machines                                                                     |
| #97          | `claude/historical-tag-closure-pages`    | merged 2026-09-23, 12:12 (`b1a088a4`)                                                                                                                                                                                                                                                                                                                                                 | the "Historical" notes on `docs/src/tag_closure_memo.md` and `tag_closure_experiments.md`                                                            |
| #98          | `claude/tag-closure-condense`            | merged into the record branch 2026-09-23, 13:47 (`859d38f8`)                                                                                                                                                                                                                                                                                                                          | H6, the condensed documents                                                                                                                          |
| #99          | `claude/prek-exclude-experiment-records` | merged 2026-09-23, 13:30 (`e8fcc0f1`)                                                                                                                                                                                                                                                                                                                                                 | excludes the record's frozen files (`archive/`, `output/`, `review/`, `reference/`, `configs/` under `experiments/tag_closure/`) from the prek hooks |
| #100         | `claude/water-tags-edmf`                 | merged into `main` (`5ef18980`)                                                                                                                                                                                                                                                                                                                                                       |                                                                                                                                                      |
| #101         | `claude/water-tags-edmf-wp3`             | merged into its stacked base; its content reached `main` through #110                                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #102         | `claude/water-tags-edmf-wp5`             | merged into #101's branch; reached `main` through #110                                                                                                                                                                                                                                                                                                                                |                                                                                                                                                      |
| #103         | `claude/water-tags-edmf-wp6`             | merged into `main`                                                                                                                                                                                                                                                                                                                                                                    |                                                                                                                                                      |
| #104         | `claude/water-tags-edmf-wp4a`            | merged into `main` 2026-09-26 (`e003e7aa`), at `860fcce4`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #105         | `claude/water-tags-sed-cross`            | merged into `main` 2026-09-25 (`ab0beb7a`), at `464f6fd0`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #106         | `claude/water-tags-plume-cost`           | merged into `main` 2026-09-24 (`3eac4d44`), at `bfd9ff08`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #107         | `claude/energy-follower-check-names`     | merged into `main` 2026-09-26 (`0ca2ca97`), at `fd1e86e1`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #108         | `claude/energy-explicit-1m-guard`        | merged into `main` 2026-09-25 (`99b4b6b0`), at `2f7987d5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #109         | `claude/water-tags-wp6-step3`            | merged into `main` 2026-09-26 (`405b5b63`), at `6f6152a2`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #110         | `claude/water-tags-edmf-wp3`             | merged into `main` 2026-09-24 (`14ed3b51`), at `7f384796`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #111         | `claude/water-tags-copy-cross`           | merged into `main` 2026-09-26 (`d1eb9606`), at `105ba0f1`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #112         | `claude/tag-closure-no-abort`            | merged into `main` 2026-09-26 (`03b6d428`), at `ca74cecd`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #113         | `claude/energy-tags-sed-cross`           | merged into `main` 2026-09-27 (`7f54d0fa`), at `b9798fd5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #114         | `claude/energy-copies-mirrors`           | merged into `main` 2026-09-26 (`fb1bffdf`), at `528ca1a2`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #115         | `claude/energy-source-throughput`        | merged into `main` 2026-09-26 (`fe7d3d26`), at `c4fa73b5`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #116         | `claude/water-tags-negative-parent`      | merged into `main` 2026-09-27 (`7f2b7244`), at `6e8769cf`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #117         | `claude/downgrade-groups-from-runtests`  | merged into `main` 2026-09-26 (`6fb78f2b`), at `afda1f1a`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #118         | `claude/water-tags-negative-water-flag`  | merged into `main` 2026-09-28 (`09d66bcb`), at `2115426f`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #119         | `claude/water-tags-leak-correction`      | merged into `main` 2026-09-28 (`134c442f`), at `818b6238`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #120         | `claude/energy-claims-budget`            | merged into `main` 2026-09-28 (`43f9eaa7`), at `ef49771f`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #121         | `claude/water-tags-rain-snow`            | merged into `main` 2026-09-28 (`6489e110`), at `4d600bd9`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #122         | `claude/tag-provenance-certainty-zwkx73` | merged into `claude/plan-rev2` 2026-09-27 (`4aeacf81`), at `130064d6`                                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #123         | `claude/water-tags-substep-attribution`  | draft, against `main`, at `7fb9cabc` (per-substep attribution of the 1M microphysics)                                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #124         | `claude/docs-issue7-after-116`           | merged into `main` 2026-09-28 (`283a18ec`), at `9481e412`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #125         | `claude/terminology-to-main`             | merged into `main` 2026-09-28 (`cfc2152c`), at `1ff3e8c0`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #126         | `claude/negative-water-accumulator`      | merged into `main` 2026-09-28 (`d2f119ab`), at `c165ae18`                                                                                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #127         | (the #121 follow-ups)                    | merged into `main` by 2026-09-30                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                                      |
| #128         | (ClimaParams capped at 1.1.15)           | merged into `main` by 2026-09-30                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                                      |
| #129         | (the #119 follow-ups; docs split)        | merged into `main` by 2026-09-30                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                                      |
| #130         | (WP4a-J, `water_tag_rainout_jacobian`)   | merged into `main` by 2026-09-30; opt-in and off; known issue 4 closed for the grid rule (W51); Julia 1.10 allocation fix                                                                                                                                                                                                                                                             |                                                                                                                                                      |
| #131 to #134 | (other sessions)                         | merged by 2026-09-30: tiered CI, split memory groups, docs simplification, CI for other workflows                                                                                                                                                                                                                                                                                     |                                                                                                                                                      |
| #135         | (the WP4b review's transport-2)          | merged 2026-09-30 (`b983d62b`); the leak is the raw difference in both modes; test 4b sets `EDMF_interface_entr_efficiency` for ClimaParams 1.1.15                                                                                                                                                                                                                                    |                                                                                                                                                      |
| #136         | (W21: the plume's surface-flux start)    | merged 2026-09-30 (`6657ae6c`); water and energy; a chosen, test-supported rule; W50 and E89 recorded                                                                                                                                                                                                                                                                                 |                                                                                                                                                      |
| #137         | `claude/option-c-revision`               | merged 2026-10-01 (`b4ebfca5`); C's revision for known issue 7; W49's V2 counts as its validation, V5's `led_fix` at site 23 is an open failure                                                                                                                                                                                                                                       |                                                                                                                                                      |

Only the owner merges. The token cannot mark a PR ready for review. Rows #104
to #126 were read from GitHub on 2026-09-28.
Rows #127 to #135 are from the coordinating session's report of 2026-09-30,
not read from GitHub here. Row #137 is from the coordinating session's
report of 2026-10-01, also not read from GitHub here. Both branches that this
sentence once named as not yet in a PR are now merged: `claude/w21-surface-flux`
as #136 and `claude/option-c-revision` as #137.

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
  - **2026-09-29, `crev` (C's revision), draft for the coordinator:** the
    revision is built on `claude/option-c-revision` (`c756390d`) and its
    validation is registered (`design/NEGATIVE_PARENT_WATER.md`, section 11).
    Its checks passed: the unit tests, a mutant, all nine `tagging_water*`
    files (jobs `13999599` to `13999609`, `14000300`, `14000301`), and a
    10-day parity check at site 23 (`13999610` to `13999613`). The rule did
    not act by day 10. No validation run is submitted: the owner reviews
    section 11 and its questions (11.10) first.
  - **2026-09-30, `crev`:** the 30-day parity rerun (`14005271` to `14005274`)
    passes Q8's rule. Every model field and the day-30 state are bit for bit in
    all four pairs. The region tags differ from `main`'s from day 11.5, so the
    rule acted (design 11.8, `output/cr_parity30/`). Nothing is extended.
  - **2026-09-30, `crev`, after the review's fixes** (`a4b492ec`): the unit
    tests, the mutants and eight of nine `tagging_water*` files pass, and the
    30-day parity passes Q8 again (`14010408` to `14010411`; the tags equal
    the first 30-day run's bit for bit). One check failed, a test defect
    (index type); fixed at `210eeece`, the file passes and its mutant fails
    as intended (`14012892`, `14012893`; design 11.8).
  - **2026-09-30, from the coordinating session's report (not queried with
    Slurm here):** WP9's exclusive-node rerun, jobs `14005213` to `14005221`,
    is pending, with an estimated start of 2026-10-01. The w21s coverage and
    parity reruns are running. The test for #135 is running. The coupling-1
    test failure of job `14010383` is a test bug, being fixed.
  - **2026-09-30, `crev`, the owner's answers to 11.10:** Q2 accepted; Q3,
    Q4 and Q5 extend the rule now; Q6 builds the ledger `q_tag_exp_negative`;
    Q7 sets W5 (`R ≤ 0.1 R48`); Q9 amends V3's fallback. The extension's
    design is section 11.11, revised after an agent's review. 11.7 carries the
    dated amendments, made before any run. Nothing is built or run. The owner
    reviews 11.11 next (its 11.11.13).
  - **2026-10-01, `crev`, the 90-day validation (W49, model `0eb329b2`):**
    all seven jobs (`14015465` to `14015471`) completed with exit 0. V1, V2,
    V2b, V3, V4, V4b, W0 to W2 and W5 pass (W3 and W4 are reported). V2's
    largest gross is 4.056e-4 at site 23 (budget 2e-3; the control on `main`
    2.24e-2), and no check exceeds 0.2%. W42's V2 failure is gone. V5 fails
    at site 23: `led_fix` of `pbl` 7.33e-2 and of `free` 6.520e-2 (largest
    6.601e-2, day 82.25) at day 90, limit 2e-2 (`main`: 2.73e-2, 2.27e-2).
    That is larger than W42's (`pbl` 2.03%). It measured `0eb329b2`
    (approved by the owner on 2026-10-01 through the coordinating session),
    not #137's head. #137's head adds `main`'s #129 to #136, the `a491b3c7`
    meter fix, the audit docstring and the stage-local `δL`, so the tag-side
    numbers need not carry over. The score is of the bundle and bounds the
    rule's part. 11.7 states no consequence for a V5 failure, so the owner
    decides (FINDINGS W49, `output/w49/`).
  - **2026-10-01, the owner's decision on W49, and #137 merged**
    (`b4ebfca5`): W49's V2 counts as C's validation (V2 at site 23 is 4.1e-4
    against 2e-3; the control on `main` is 2.2e-2). V5's `led_fix` fails at
    site 23 and stays an open failure: `pbl` is at 7.33% and `free` at 6.52%
    against 2%, and the control is at 2.73% and 2.27%, a rise of about 2.7 to
    2.9 times with the cause untraced. A follow-up probe will trace the rise.
    It is not designed or run. The record is design 11.10 (item 10),
    DECISIONS.md (2026-10-01) and FINDINGS W49. Known issue 7's option C
    revision is closed in the records except for that probe.

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

*Update 2026-10-02:* OD12 to OD14 are accepted. OD9 to OD11 and OD15 stay
proposed.

*Scope added (provenance pathway, 2026-09-26):* OD9 to OD15 were proposed, not
yet open. OD15 was added on 2026-09-27. Each becomes open when the owner
accepts it ([PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md), section 9).

Each decision's current state is in ROADMAP.md's register, the single source.
OD7 is the only open numbered decision. OD9 to OD11 and OD15 are proposed, not
open. Open now, each with its entry in
[DECISIONS.md](DECISIONS.md), "Waiting for the owner":

  - **OD7**, G4.15's rule for energy, deferred until site 23 can be scored.

  - ~~**Option C after its validation (W42).**~~ *Closed 2026-10-01: #137
    merged, W49's V2 counts as C's validation, and V5's `led_fix` stays an
    open failure that a probe will trace (the update line of 2026-10-01).*
    The text as it stood: V2 fails at site 23 (2.2%
    against 0.2%) and `pbl`'s per-tag row (2.03%). By the design note's
    section 8.3 the owner decides; site 23's long-run rerun, which OD7 waits
    on, is not submitted until then. *Decided 2026-09-25: probe the miss
    first* (the register), then validate C again. *2026-09-28:* scored as
    W47. The owner chose to probe more first (section 9.7). C's revision
    stays open. *Superseded 2026-09-30: C's revision is built and its
    parity passes; see the next item.*

  - ~~**Known issue 7's option among B, C and D.**~~ Decided 2026-09-25:
    option C (the register). Built; its validation is pre-registered.

  - ~~**WP4a's two points**~~ decided 2026-09-28 (the register).

  - ~~**WP6's three points**~~ confirmed as built, 2026-09-28 (the register).

  - **The explicit-1M water default, at M5** (W33 stays a failure).

  - ~~**W21's surface rule in the first hour**~~ decided 2026-09-28 (the
    register).

  - **C's section 11.10 questions, Q2 to Q9** (2026-09-30;
    `design/NEGATIVE_PARENT_WATER.md`). Q1 and Q8 are decided (2026-09-29).
    Open:

      + Q2: the stages split a crossing step, unbiased, with a miss of
        either sign (the review's kernel-1). Accept, or ask for another
        split, for example reading the sign once per step.
      + Q3: extend the rule to the implicit microphysics bracket?
      + Q4: give source tags and region tags that list sources the rule?
      + Q5: give transfers into a negative compartment the target's
        treatment, in a later change?
      + Q6: build the ledger `q_tag_exp_negative`?
      + Q7: the windows' rule, "the rise goes" if `R <= 0.1 R48`.
      + Q9: V3's fallback clause (the review's kernel-2). Change it, or
        leave it?

    The 30-day parity of Q8 passed twice. The 90-day validation waits for
    these answers.

  - ~~**The WP4b walk-through, with the stage-1 review's findings**~~
    *Decided 2026-10-02: one fix PR (the update line of that date).* The
    text as it stood
    (`review/agent_reviews/wp4b_stage1_review_2026-09-30.md`): 12 findings
    kept, none moving a model field. The should-fix ones are micro-1,
    transport-1, transport-2 (in #135), state-1 and state-2. The review
    bears on P1 to P5: micro-1 and state-1 are evidence for revisiting P2,
    micro-3 favours a gate or sub-key for P3, and transport-1 is a sign
    problem in P4's correction. To be walked through one point at a time.

  - ~~**OD9 to OD15, G4.3 to G4.6's seven points, WP4b's five points**~~
    *Walked through 2026-10-02 (the register).* Still open from it: OD9 to
    OD11, OD15 at PX25's pre-registration, and G4's levels at G4's start.

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
