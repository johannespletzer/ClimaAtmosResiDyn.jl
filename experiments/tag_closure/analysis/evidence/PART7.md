# Independent water-transfer references

Base: `claude/plan-rev2` at `7c96c2046f440990b070ed65e38c08f2afeb8d92`,
which holds the reviewed Parts 4 to 6. The increment was first written
against the pre-review Part 6 head `9344147c69f4c58eb1197adf84f3b7b98df65440`.
The design file's `base_commit` and `base_tree` record that commit. The
port to the reviewed Part 6 pattern is described in
[Declared eligibility and the unchanged scorer](#declared-eligibility-and-the-unchanged-scorer).
Nothing here changes a model field, a runtime diagnostic, a threshold or a
production default. Physical precipitation qualification remains incomplete.

## Inventory before implementation

| Directed mechanism                    | Actual donor → receiver, units and timing                                                                                                | Shared code / ownership                                                                                                     | Independent work and error class                                                                                                                                            | Capture prerequisites and support                                                                                                            |
|:------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------- |
| 0M subdomain rain-out, WP4a-V/J       | Environment/updraft N → external loss, density tendency kg m^-3 s^-1, explicit/implicit evaluation                                       | `tagged_water_rainout.jl`, existing reconstruction/Jacobian, `ZERO_M_SPLIT`/`ZERO_M_RECONSTRUCTION_CHECK`, W32/W51 retained | Existing copies/reconstruction experiment reused, cannot validate its shared rain-out or establish stage-2 donor truth                                                      | Actual eligible copies, Newton ladder, subdomain applied losses, Julia/producer unavailable here                                             |
| Six 1M inter-compartment flows        | NR, NS, RN, RS, SR, SN, rate kg kg^-1 s^-1 averaged over model dt, coefficient times solved donor per microphysics substep               | `tagged_water_precipitation.jl:620–709`, repeats CloudMicrophysics linearized averaging and SGS evaluator                   | New positive-M independent ODE references identify wrong donor and erased opposing exchange. Frozen-rate replay validates conditional label evolution only, not model rates | Cache/substep/evaluation and accepted dt*b amounts required, original substep tests call production helper and are not an independent oracle |
| Pool attribution, WR13                | Donor pool composition mixes initial content with incoming integrated rates in one 3x3 solve                                             | `tagged_water_precipitation.jl:927–984`, local `Y` shares, stage/cache averaged rates                                       | New independent differential equation versus separately evaluated declared pool rule, temporal ordering error separated from spread                                         | Need frozen rate state/cadence/model identity, synthetic replay is runnable, actual PX14 run remains blocked                                 |
| Net-flow fallback, WR14               | Losing compartments → gaining compartments by start donor share, net tendency rate, no exchange at net zero                              | `tagged_water_precipitation.jl:988–1106`, before and after snapshots at 1487–1548                                           | Opposing-flow closed-compartment counterexample must fail label origin despite zero net parent changes                                                                      | Need six gross flows and fallback/bound/zero counters. Audit is rule spread, not reference error                                             |
| Negative numerical treatment          | Signed flows touching a negative compartment are oriented, zero target labels there, inflow withheld or passed on with donor composition | `tagged_water_precipitation.jl:1109–1242`, positive-target rule and ledgers                                                 | Separate declared-rule examples with hand answers, never infer physical f=X/M for M<0                                                                                       | Raw parent, flags, withheld/negative ledgers and accepted applications, physical references refuse negatives                                 |
| Rain/snow sedimentation with key      | Each level's R/S → lower level or separate boundary export, own R/S label, density rate and upward-positive face flux                    | `_sediment_precip_parts!` at 501–533, own parent species linear flux, Jacobian diagonal, explicit/implicit paths            | New independent column compartment chain with distinct levels/species/densities, separately integrated export label inventories                                             | Applied face/step parent+tag flux and geometry, shared parent flux alone cannot validate donor correctness                                   |
| Per-level reset without key, WR12     | Species' falling water takes local total/N composition instead of its rain/snow ownership                                                | `tagged_water.jl:770–1010`, renormalized partition shares inside flux                                                       | Isolated reset mutation against actual rain/snow label owner with identical parent/rates. Pool test is separate                                                             | No unbuilt EDMF stage assumed, real reset/PX14 rain window unavailable                                                                       |
| Surface precipitation                 | Actual bottom R/S labels plus cloud N share → exterior, kg m^-2 s^-1 upward-positive                                                     | `water_tag_precipitation_flux!` at 2034, lowest-cell J/surface-J geometry                                                   | Export conservation and exact integrated paired synthetic amounts, snapshots shown separately                                                                               | Same accepted parent/tag application required. No snapshot integration as accumulated precipitation                                          |
| State constraint/rescale/follow       | R/S ↔ N, rain before snow, target max(M,0), density increment                                                                            | 1577–1900, per-tag total ledgers can hide equal opposing compartment changes                                                | Reuse Part5 signed/retained/application reader, tests for totals versus labels and cancellation                                                                             | Base has no per-compartment closing step from later main/#146. Do not silently import it, capture correction legs required                   |
| Partition repair                      | Negative part redistribution within each species, preserves or changes per-tag total                                                     | 1907–1930 and shared `_apply_partition_repair!`                                                                             | Reuse original accounting tests, closure cannot certify origins                                                                                                             | Gross per tag+compartment applications/counters and restart continuity absent                                                                |
| Unsupported EDMF/copies precipitation | No implemented stage-2/3 owner/rate operator                                                                                             | `check_water_tag_precipitation_supported` at 2089 plus copy refusal                                                         | Explicitly blocked and routed to WP4b stages, not built here                                                                                                                | Refusals preserved, no runtime instrumentation                                                                                               |

## Frozen design and independence

`water_transfer_design.json` fixes the cases. Its SHA256,
`f2f881dfd789031efb08a37bd7ccc03aec27f278b802b70647acdd75c0ccea81`, is pinned in
`water_transfer_reference.py` and in both fixture configs. The hash shows
integrity only. It shows that the file has not changed since it was pinned,
not when it was written (decision of 2026-10-08 for Part 6, applied here).
It fixes
all amounts, units, compartment topology, IC, rates, boundaries, physical
samples (0, 1 h, 12 h, 24 h), 1/4/16/64 rungs, equations, norms, mutations,
floors and rules. The geometric cells and densities are native. This is a
small development suite with synthetic prescribed rates, not atmospheric data.
Complete partition origins conserve their total including explicitly tracked
boundary exports. Overlapping/very small/zero source overlays never enter
partition closure. Sources here are initial overlays, not injected water.

For M_c>0, f_i,c=X_i,c/M_c. Each nonnegative directed water rate F_c,d
removes F_c,d f_i,c from donor c and adds it to recipient d simultaneously.
For fixed rates, M evolves by the specified net rates. For linear kinetics,
F=kM and both parent and labels evolve with the independently specified
conservative generator. A fixed-rate accepted amount uses its declared
sampling time. A continuous ODE samples the evolving donor. The reference
never divides by zero or interprets negative water as a physical composition.
An empty kinetic donor has zero outflow. The exact one-way depletion case
uses its analytic limiting composition at its empty endpoint only.

One-way, equal/opposing exchange and the equal three-cycle have closed-form
answers. The other small cases use an independent high-precision scaled
matrix exponential, checked against separately assembled RK4 equations and
hand-derived limiting cases. Neither calls a ClimaAtmos donor/pool helper.
The pool diagnostic independently solves the documented coarse rule and is
not used as the oracle. Original WP4b substep tests share the production
microphysics attribution and only supply useful accounting regressions.

Every rung is retained. Rung64 is eligible only when its measured errors in
each applicable norm, plus the explicit arithmetic floor, are at most one
quarter of that norm's tolerance. A failed reference cannot rank candidates.
The day/hour OD3 profile numbers retain their approved endpoints. Per-species
origin rows reuse their magnitudes as development engineering checks only.
There is no approved atmospheric compartment-origin tolerance here. Reference
error, pool/net rule spread and closure are separate observables.

Process-weighted share error is sum A|f_cand-f_ref| / sum A using nonnegative
native integrated transfer amounts. With zero activity it is not applicable.
Absolute weighted mismatch and max share error accompany it. A transfer of Q
has transfer amount Q and donor+recipient leg activity 2Q. Signed residual,
gross per compartment and gross of the summed residual are separate. A
per-tag cumulative signed audit can cancel over accepted steps, so both its
endpoint magnitude and stepwise absolute variation are reported. Summing its
tags to zero is never proof of fidelity. Missing channels or positive
normalization denominators block that row. They do not become zeros.

## OD15 decisions needed before PX25 scoring

OD15 is **proposed/pending** at this dependency. No approval is invented. The
analytic development suite proceeds. Dependent campaign scores remain blocked.

| Choice                                    | Planning draft                                                                                                                                  | Current decision / dependent score                                                                                                                                                                                                        |
|:----------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Case/window/length                        | PrecipitatingColumn, W43's 6 km/30 levels/dt10 s/1500 s, second case not selected until untagged established rain is measured under OD2         | Owner decision required. Short case has no hourly/day output                                                                                                                                                                              |
| Short-case reading                        | Record original 24 h/second-12 h and day-audit rows as not assessable. Original missing-hour failure rule and R9 hourly proposal remain visible | Draft only. Owner decides whether missing-short hours fail or are not assessable                                                                                                                                                          |
| van Leer R/S closure                      | Retain approved 1e-8 against own compartment. No relaxed replacement                                                                            | Original row unchanged. Hourly applicability pending                                                                                                                                                                                      |
| Nonprecipitating residual                 | Report signed identity Nres=−(Rres+Sres) under increment plus both normalizations                                                               | No approved own-compartment tolerance. Reported only                                                                                                                                                                                      |
| Accumulated precipitation                 | Pair actual accepted parent/tag applications over identical steps. Report separately from instantaneous sum                                     | No additional scoring until owner decides                                                                                                                                                                                                 |
| Audit/gross-transfer normalization        | Six gross flows, native accepted amounts, per-tag max/integral endpoint and variation plus part/precip scales                                   | Reported only. Missing producer/denominator blocks                                                                                                                                                                                        |
| Audit trend                               | dt-halving ratios <=.75 twice converging, >1.1 either growing, .9–1.1 twice systematic, otherwise unresolved                                    | Proposed, never PASS. Non-doubling 1/default/10 substeps reported only                                                                                                                                                                    |
| Pool ordering within evolving model rates | Actual substep donor/rate capture or model-substep replay would be required                                                                     | Frozen rates do not validate changing rates. No diagnostic added under OD13                                                                                                                                                               |
| Held-out case                             | RICO 1M, 24 h is held out (WA-SCOPE, 2026-10-08). Criterion 8's columns are not held out for site-23 rules                                      | PrecipitatingColumn starts from RICO's θ and q_tot. Under OD14 (2026-10-09) it serves PT15 and PT16 arithmetic rows only and chooses no mode or default. The explicit-1M default is chosen on an independent second case, found with OD15 |

PX25 must use tracer/increment × first_order/vanleer_limiter × dt/dt2/dt4.
Only van Leer baseline also uses 1/10 microphysics substeps beside default.
Quadrature makes `microphysics_n_substeps_quadrature` effective (default2).
Without quadrature `microphysics_n_substeps` is effective (default3). Each of
the eight parent settings has its own untagged twin. Sixteen tagged arms share
only their matched parent. A changed config whose untagged bits stay identical
is a void perturbation. First order is a scheme, not a refinement rung. No
cross-parent difference is directly scored as origin error. Closure and the
audit cannot validate WR13 or WR14. No 12/24-hour rule is applied to 1500 s.

## Full Part7 obligation mapping

| Obligation                                                          | Reused / new / blocked                                | Evidence or remaining action                                                                                                         |
|:------------------------------------------------------------------- |:----------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------ |
| Exact dependency/refs/merge/intervening changes                     | Reconciled                                            | Merged with plan-rev2 at `7c96c2046` and ported to the declared-eligibility pattern. The scorer is unchanged                         |
| Applicable guides and acceptance/code inventory                     | Reused/new                                            | Root/shared/repo guides, G3_PLAN/ROADMAP/G3_TODO/provenance, actual source/test paths above                                          |
| Preregister all equations, IC, rates, BC, ladders, norms, decisions | New                                                   | Design and configs pinned by SHA256 (integrity only, not timing)                                                                     |
| One-way, opposing net-zero, three-cycle, unequal compositions       | New                                                   | Independent equation cases. One-way has a wrong-donor control, opposing an erased-exchange control, the others an origin permutation |
| Empty/near-depleted/depletion, zero activity                        | New                                                   | Positive reference limits and refusal of unsupported outflow, explicit N/A                                                           |
| Negative-rule handling                                              | Reused/new engineering tests                          | Separate declared numerical examples, no physical positive-composition claim                                                         |
| Distinct rain/snow levels/export/accumulation                       | New plus existing readers                             | Native chain, owner reset isolation, complete labelled exterior conservation                                                         |
| Pool/reset/closing totals versus labels                             | New plus Parts5/6                                     | Separate pool replay/reset, base closing absent, ledger-total cancellation tested without importing main                             |
| PX14 full 1/4/16/64 conditional replay and measured floors          | New synthetic, runtime blocked                        | Every rung retained, actual rain window/states/rates/substeps missing                                                                |
| PX25 matrix/effective key/parent parity/void perturbation           | New config/planning artifact, runtime blocked         | OD15/effective settings/untagged/rain evidence needed, no campaign score                                                             |
| PT15/PT16 original closure/audit interpretations                    | Reused, pending score                                 | Signed identities and proposed trend status preserved, no threshold/default change                                                   |
| Process-weighted and native per-tag/compartment diagnostics         | New                                                   | Positive applied amounts, explicit denominator rules, net/gross/sum distinguished                                                    |
| Correction gross/retained/applications/fallback/minima              | Reuse Parts4/5, runtime blocked                       | VERIFIED_PRODUCERS stays empty, synthetic metadata cannot certify production                                                         |
| Paired accepted precipitation/restart/reset/duplicate handling      | Reuse existing reader/tests + focused transfer faults | No snapshot integration or invented capture                                                                                          |
| Bundle/manifest/scorer native identity/coverage/ladder gates        | Reused narrow optional adapter                        | Pin exact model/spec/config/source/rates/time/geometry/dtype, reconstruct floors                                                     |
| Part6 parent scaling/closure/mutation invariant guards              | Reuse/generalize narrowly                             | Candidate must match prescribed parent and closure, mutation certificate exact IC/rates/overlays                                     |
| Unit/direction/geometry/hash/time/scope/reference faults            | New + affected suites                                 | Exact analytic/cancellation/refinement failure and malformed evidence tests                                                          |
| Runtime parity/restart/device/performance/allocation                | Blocked and separately routed                         | No Julia/prepared cluster, no model hot-path changes, exact unrun commands in handoff                                                |
| Review                                                              | Recorded in the PR                                    | No earlier independent review is on record. The review of 2026-10-08 is summarized in [Review record](#review-record)                |
| STATUS/TODO/CROSSWALK/evidence docs                                 | New                                                   | Scoped offline increment, not atmospheric qualification. NEWS has no entry, since experiment tools are not listed there              |
| Residence-time/energy/parent physics/closure tuning                 | Excluded                                              | Existing parts only, no new reference or physical model changes                                                                      |

## Declared eligibility and the unchanged scorer

The port of 2026-10-08 follows Part 6's reviewed pattern. The scorer has no
`water_transfer` hook, and `score_acceptance.py` is byte-identical to
`claude/plan-rev2` at `7c96c2046`.
[water_transfer_adapter.py](water_transfer_adapter.py) is the producing
script. It regenerates every archived rung from the independent equations,
measures the rung-64 floor and writes a declaration into
`transfer_reference_evidence.json`. The manifest's `reference.producer` names
and hashes the same script. The scorer reads the declaration through its own
eligibility reader. Rerun on a finished bundle, the adapter refuses a
declaration that differs from its recompute. The fixture driver requires the
scorer's reading to agree with the producer's.

| Declared value                                                          | What it rests on                                                                                                                                                                                                                                                                          |
|:----------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `independent_rules`                                                     | Measured. The case's one rule when the pinned rates move water. Empty for zero activity, which exercises no donor rule.                                                                                                                                                                   |
| Reference-discretization floor                                          | Measured. The RK4 rung 64 against the closed form or the independent exponential, in each applicable same norm plus the 128 eps arithmetic bound. The frozen design fixes this floor for both reference modes. Applied-share and export-origin rows are included.                         |
| Source-injection, initialization, parent-solve and contamination floors | Stated as zero, each with its reason. A nonzero initial state or an active excluded process refuses the evidence instead of entering a floor. In the kinetic cases the RK4 parent error is inside the reference-discretization floor.                                                     |
| `converged`                                                             | Measured. No step of the 1/4/16/64 ladder raises the floor by more than the scorer's `SECOND_HALF_TIE`. Part 6's rule, accepted for Part 7 on 2026-10-09. Every case converges on this ladder. `depleted_donor` and `single_transfer` do so through the tie, with margins of 3.0 and 4.3. |
| `mirrors_complete`, `jacobian_complete`                                 | Declared true as inapplicable. The equations have no source and no copies. RK4 and the closed forms have no implicit tag solve.                                                                                                                                                           |

A rung-64 reference that does not conserve its own water and labels, or
fails its directed balance, is refused as a broken reference. The adapter's
own floor eligibility used to include those checks. Every rung of every
case passes them.

Zero activity covers no rule by design (decision of 2026-10-09). The design
marks the case with `expected_rule_coverage: none`, and the producer refuses
the mark if the pinned rates move water. The scorer, unchanged, reads its
reference as covering no rule, so its candidate is not assessable and the
full scorer's eligibility rows read FAIL. The suite driver counts the case
as not applicable when its floors are eligible, keeps NOT ASSESSABLE in its
results and does not exit 3 for it.

## Measured offline increment

Both configurations, exact and selected RK4, cover the nine development
cases. Each retains 36 RK4 rungs (nine cases by four) and 28 separate pool
diagnostic rungs (seven fixed-rate cases by four). Both exit 0. Eight cases
have eligible references, their candidates pass and their registered origin
controls are verified. Zero activity is not applicable. The rung-64 floors,
including their arithmetic bounds, are:

| Case                                    | Rung-64 maximum floor / tolerance |
|:--------------------------------------- | ---------------------------------:|
| One-way transfer                        | 3.1554928181613646e-12            |
| Opposing net-zero exchange              | 4.765413720348596e-6              |
| Three-compartment cycle                 | 9.710551269683147e-7              |
| Unequal compositions                    | 1.970127373902598e-6              |
| Empty replenished donor                 | 1.0644126818743075e-9             |
| Exact depleted endpoint                 | 3.31216528779494e-12              |
| Stiff opposing floor                    | 8.310061860770055e-5              |
| Zero activity (not applicable)          | 2.853819184610238e-12             |
| Separate rain/snow sedimentation/export | 1.4004315613630354e-6             |

These are manufactured development measurements, not atmospheric reference
floors. The RK4 floors fall by about 16 for each fourfold refinement, second
order, because the applied-share row samples the stage donor. The stiff
case's rung 1 floor is 29 times the tolerance. Its rung 64 floor is 8.3e-5.
Pool rungs 1 and 4 fail in four cases, as expected of a coarse rule. The
depleted case's pool rung 16 also fails, from roundoff alone: one label
reaches -5.9e-17 at the depleted donor, where the closure allowance is
128 eps times 2e-6. The pool rungs are diagnostics and select nothing.

What passes by construction. The fixture candidate is the exact answer
itself. In exact mode its errors are zero, and in RK4 mode they equal the
rung-64 floor. Its PASS checks the reader and the equations, not a model.
In the one-way and depleted cases the donor composition is constant, so any
consistent integrator, the pool rule included, is exact there. Their floors
sit at the arithmetic bound. The zero-activity floor is the arithmetic bound
alone. The depleted case moves 2e-6 kg m^-2 against about 3 kg m^-2. A
candidate that moves no label there meets all 12 total rows and all 36
compartment rows, so the case cannot detect a missing transfer. The eight
cases without exports are single cells. There the approved total profile
rows are met by any candidate that moves labels only between N, R and S,
a no-transfer candidate included (12 of 12 in each). Only the
per-compartment rows discriminate, and they are development engineering
checks. In the sedimentation case the export-origin rows also discriminate.
All of them fall under the small-tag absolute rule.

The registered controls each keep the parent, every compartment closure and
every tag's total, and fail an origin row. Only the one-way case has a true
wrong-donor control: it applies the recipient's initial share to the
transferred amount. The opposing case erases the exchange: it keeps the
opposing water amounts and moves no label. The sedimentation case resets
the owner: rain and snow fall with their level's initial N composition. The
other six cases permute origins cyclically, a corruption control, not a
donor claim. The first three are checked through the bundle path. A fourth gap was found in review: two opposing edges that
both carry 4% extra of one origin leave labels, closure, directed balance
and the 5% applied-share row unchanged or within limits. The candidate check
now also requires each edge's applied partition labels to sum to its applied
water, at the roundoff allowance. A test covers it.

The full production scorer on a development fixture validates with exit 0
and scores with exit 2. Native temperature, negative water, Newton, ledgers
and parity rows are absent. The paired precipitation rows of the
sedimentation case are reported only (WA-PRECIP). No row scores
precipitation provenance as PASS.

The focused tests are in
[test_water_transfer_reference.py](test_water_transfer_reference.py). The
whole evidence directory passes on this tree.

## Review record

The PR's text said that an independent review had resolved its findings.
No record of such a review exists in the repository, so that statement is
withdrawn. The review of 2026-10-08 ported the
adapter, checked the equations and the controls by computation and added
the applied-partition check, the PX25 draft pin and the driver's exit codes.

A mutation pass on 2026-10-09 found numbers that no test pinned. The code
now reads the design's `profile_rules` instead of repeating them, and a
test ties them to the scorer's approved constants. Tests also pin the
judged endpoints to the scorer's `FIRST_HOUR` and `DAY`, the source overlay
definitions, the trend bounds and every PX25 value against its
preregistration. The exponential's internal settings (96 terms, the 0.5
scaling bound, the 16 eps depletion allowance and the 2e-15 initial
partition check) stay unpinned. A wrong value there would show in the
rung-64 floors, which are measured.
