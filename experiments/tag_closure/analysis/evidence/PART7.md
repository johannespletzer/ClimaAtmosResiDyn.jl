# Independent water-transfer references

Dependency: `codex/water-transport-references-part6` at
`9344147c69f4c58eb1197adf84f3b7b98df65440`, tree
`dd499d34df3e121165e6280ba68d9eed191976c8`. The local source is a partial
exact-tree materialization, not a git checkout or local branch. The initial
read-only receipts recorded PR154 open and unmerged at this pinned head and
main divergent at `12377fb885149d5180031c0e6a41d8dc8041e4ef`. The publication
check found Part 6 advanced by 26 commits to
`da991fffa09d85567cab23cdb99deb13e9c779d0`. This increment is reviewed only
against the pinned base above; reconciliation with the advanced Part 6
scorer/contracts/tests is required before merge. Later-main precipitation
closing/order changes are not in the pinned source.
Nothing here changes a model field, a runtime diagnostic, a threshold or a
production default. Physical precipitation qualification remains incomplete.

## Inventory before implementation

| Directed mechanism | Actual donor → receiver; units and timing | Shared code / ownership | Independent work and error class | Capture prerequisites and support |
|:--|:--|:--|:--|:--|
| 0M subdomain rain-out, WP4a-V/J | Environment/updraft N → external loss; density tendency kg m^-3 s^-1, explicit/implicit evaluation | `tagged_water_rainout.jl`, existing reconstruction/Jacobian, `ZERO_M_SPLIT`/`ZERO_M_RECONSTRUCTION_CHECK`; W32/W51 retained | Existing copies/reconstruction experiment reused; cannot validate its shared rain-out or establish stage-2 donor truth | Actual eligible copies, Newton ladder, subdomain applied losses; Julia/producer unavailable here |
| Six 1M inter-compartment flows | NR, NS, RN, RS, SR, SN; rate kg kg^-1 s^-1 averaged over model dt; coefficient times solved donor per microphysics substep | `tagged_water_precipitation.jl:620–709`; repeats CloudMicrophysics linearized averaging and SGS evaluator | New positive-M independent ODE references identify wrong donor and erased opposing exchange. Frozen-rate replay validates conditional label evolution only, not model rates | Cache/substep/evaluation and accepted dt*b amounts required; original substep tests call production helper and are not an independent oracle |
| Pool attribution, WR13 | Donor pool composition mixes initial content with incoming integrated rates in one 3x3 solve | `tagged_water_precipitation.jl:927–984`; local `Y` shares, stage/cache averaged rates | New independent differential equation versus separately evaluated declared pool rule; temporal ordering error separated from spread | Need frozen rate state/cadence/model identity; synthetic replay is runnable, actual PX14 run remains blocked |
| Net-flow fallback, WR14 | Losing compartments → gaining compartments by start donor share; net tendency rate, no exchange at net zero | `tagged_water_precipitation.jl:988–1106`, bracket snapshots at 1487–1548 | Opposing-flow closed-compartment counterexample must fail label origin despite zero net parent changes | Need six gross flows and fallback/bound/zero counters. Audit is rule spread, not reference error |
| Negative numerical treatment | Signed flows touching a negative compartment are oriented; zero target labels there; inflow withheld or passed on with donor composition | `tagged_water_precipitation.jl:1109–1242`; positive-target rule and ledgers | Separate declared-rule examples with hand answers; never infer physical f=X/M for M<0 | Raw parent, flags, withheld/negative ledgers and accepted applications; physical references refuse negatives |
| Rain/snow sedimentation with key | Each level's R/S → lower level or separate boundary export, own R/S label; density rate and upward-positive face flux | `_sediment_precip_parts!` at 501–533; own parent species linear flux, Jacobian diagonal; explicit/implicit paths | New independent column compartment chain with distinct levels/species/densities; separately integrated export label inventories | Applied face/step parent+tag flux and geometry; shared parent flux alone cannot validate donor correctness |
| Per-level reset without key, WR12 | Species' falling water takes local total/N composition instead of its rain/snow ownership | `tagged_water.jl:770–1010`; renormalized partition shares inside flux | Isolated reset mutation against actual rain/snow label owner with identical parent/rates. Pool test is separate | No unbuilt EDMF stage assumed; real reset/PX14 rain window unavailable |
| Surface precipitation | Actual bottom R/S labels plus cloud N share → exterior; kg m^-2 s^-1 upward-positive | `water_tag_precipitation_flux!` at 2034; lowest-cell J/surface-J geometry | Export conservation and exact integrated paired synthetic amounts; snapshots shown separately | Same accepted parent/tag application required. No snapshot integration as accumulated precipitation |
| State constraint/rescale/follow | R/S ↔ N, rain before snow, target max(M,0); density increment | 1577–1900; per-tag total ledgers can hide equal opposing compartment changes | Reuse Part5 signed/retained/application reader; tests for totals versus labels and cancellation | Base has no per-compartment closing step from later main/#146. Do not silently import it; capture correction legs required |
| Partition repair | Negative part redistribution within each species, preserves or changes per-tag total | 1907–1930 and shared `_apply_partition_repair!` | Reuse original accounting tests; closure cannot certify origins | Gross per tag+compartment applications/counters and restart continuity absent |
| Unsupported EDMF/copies precipitation | No implemented stage-2/3 owner/rate operator | `check_water_tag_precipitation_supported` at 2089 plus copy refusal | Explicitly blocked and routed to WP4b stages, not built here | Refusals preserved; no runtime instrumentation |

## Frozen design and independence

`water_transfer_design.json` was saved before reference code and deciding
results. Its SHA256 is recorded in the configs and recovery receipt. It fixes
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
sampling time; a continuous ODE samples the evolving donor. The reference
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
origin rows reuse their magnitudes as development engineering checks only;
there is no approved atmospheric compartment-origin tolerance here. Reference
error, pool/net rule spread and closure are separate observables.

Process-weighted share error is sum A|f_cand-f_ref| / sum A using nonnegative
native integrated transfer amounts. With zero activity it is not applicable.
Absolute weighted mismatch and max share error accompany it. A transfer of Q
has transfer amount Q and donor+recipient leg activity 2Q. Signed residual,
gross per compartment and gross of the summed residual are separate. A
per-tag cumulative signed audit can cancel over accepted steps, so both its
endpoint magnitude and stepwise absolute variation are reported. Summing its
tags to zero is never proof of fidelity. Missing channels or positive
normalization denominators block that row; they do not become zeros.

## OD15 decisions needed before PX25 scoring

OD15 is **proposed/pending** at this dependency. No approval is invented. The
analytic development suite proceeds; dependent campaign scores remain blocked.

| Choice | Frozen planning draft | Current decision / dependent score |
|:--|:--|:--|
| Case/window/length | PrecipitatingColumn, W43's 6 km/30 levels/dt10 s/1500 s; second case not selected until untagged established rain is measured under OD2 | Owner decision required; short case has no hourly/day output |
| Short-case reading | Record original 24 h/second-12 h and day-audit rows as not assessable; original missing-hour failure rule and R9 hourly proposal remain visible | Draft only; owner decides whether missing-short hours fail or are not assessable |
| van Leer R/S closure | Retain approved 1e-8 against own compartment; no relaxed replacement | Original row unchanged; hourly applicability pending |
| Nonprecipitating residual | Report signed identity Nres=−(Rres+Sres) under increment plus both normalizations | No approved own-compartment tolerance; reported only |
| Accumulated precipitation | Pair actual accepted parent/tag applications over identical steps; report separately from instantaneous sum | No additional scoring until owner decides |
| Audit/gross-transfer normalization | Six gross flows, native accepted amounts; per-tag max/integral endpoint and variation plus part/precip scales | Reported only; missing producer/denominator blocks |
| Audit trend | dt-halving ratios <=.75 twice converging; >1.1 either growing; .9–1.1 twice systematic; otherwise unresolved | Proposed, never PASS. Non-doubling 1/default/10 substeps reported only |
| Pool ordering within evolving model rates | Actual substep donor/rate capture or model-substep replay would be required | Frozen rates do not validate changing rates; no diagnostic added under OD13 |
| Held-out case | Exclude TRMM1M/RICO fallback and criterion-8 columns from tuning | OD14 accepted; PrecipitatingColumn shares RICO profiles; held-out independence unresolved |

PX25 must use tracer/increment × first_order/vanleer_limiter × dt/dt2/dt4;
only van Leer baseline also uses 1/10 microphysics substeps beside default.
Quadrature makes `microphysics_n_substeps_quadrature` effective (default2);
without quadrature `microphysics_n_substeps` is effective (default3). Each of
the eight parent settings has its own untagged twin; sixteen tagged arms share
only their matched parent. A changed config whose untagged bits stay identical
is a void perturbation. First order is a scheme, not a refinement rung. No
cross-parent difference is directly scored as origin error. Closure and the
audit cannot validate WR13 or WR14. No 12/24-hour rule is applied to 1500 s.

## Full Part7 obligation mapping

| Obligation | Reused / new / blocked | Evidence or remaining action |
|:--|:--|:--|
| Exact dependency/refs/merge/intervening changes | Inspected/reused | Remote receipts; partial tree-verified source; no silent merge, originals immutable |
| Applicable guides and acceptance/code inventory | Reused/new | Root/shared/repo guides; G3_PLAN/ROADMAP/G3_TODO/provenance; actual source/test paths above |
| Preregister all equations, IC, rates, BC, ladders, norms, decisions | New | Frozen design and configs, before code/results |
| One-way, opposing net-zero, three-cycle, unequal compositions | New | Independent equation cases plus wrong-donor/erased-opposition controls |
| Empty/near-depleted/depletion, zero activity | New | Positive reference limits and refusal of unsupported outflow; explicit N/A |
| Negative-rule handling | Reused/new engineering tests | Separate declared numerical examples; no physical positive-composition claim |
| Distinct rain/snow levels/export/accumulation | New plus existing readers | Native chain, owner reset isolation, complete labelled exterior conservation |
| Pool/reset/closing totals versus labels | New plus Parts5/6 | Separate pool replay/reset; base closing absent; ledger-total cancellation tested without importing main |
| PX14 full 1/4/16/64 conditional replay and measured floors | New synthetic; runtime blocked | Every rung retained; actual rain window/states/rates/substeps missing |
| PX25 matrix/effective key/parent parity/void perturbation | New config/planning artifact; runtime blocked | OD15/effective settings/untagged/rain evidence needed; no campaign score |
| PT15/PT16 original closure/audit interpretations | Reused; pending score | Signed identities and proposed trend status preserved; no threshold/default change |
| Process-weighted and native per-tag/compartment diagnostics | New | Positive applied amounts, explicit denominator rules; net/gross/sum distinguished |
| Correction gross/retained/applications/fallback/minima | Reuse Parts4/5; runtime blocked | VERIFIED_PRODUCERS stays empty; synthetic metadata cannot certify production |
| Paired accepted precipitation/restart/reset/duplicate handling | Reuse existing reader/tests + focused transfer faults | No snapshot integration or invented capture |
| Bundle/manifest/scorer native identity/coverage/ladder gates | Reused narrow optional adapter | Pin exact model/spec/config/source/rates/time/geometry/dtype; reconstruct floors |
| Part6 parent scaling/closure/mutation invariant guards | Reuse/generalize narrowly | Candidate must match prescribed parent and closure; mutation certificate exact IC/rates/overlays |
| Unit/direction/geometry/hash/time/scope/reference faults | New + affected suites | Exact analytic/cancellation/refinement failure and malformed evidence tests |
| Runtime parity/restart/device/performance/allocation | Blocked and separately routed | No Julia/prepared cluster; no model hot-path changes; exact unrun commands in handoff |
| Independent actual-diff review and resolution | Complete local review | Mathematical/physical and written-performance passes; fresh-hash probes close the directed-amount/roster findings; 33 focused tests pass |
| STATUS/TODO/CROSSWALK/NEWS/evidence docs/local patch/draft PR/handoff | New local handoff | Preserve all prior decisions/failures; exact reviewed-base patch and hashes; scoped offline increment, not atmospheric qualification |
| Publication versus runtime/merge actions | Push and PR description now authorized | Root publishes the exact reviewed-base handoff; merge, large campaigns, dependencies and CI changes are outside this increment |
| Residence-time/energy/parent physics/closure tuning | Excluded | Existing parts only; no new reference or physical model changes |

## Measured offline increment and review resolution

The final-code exact and selected-RK4 configurations each returned
exit 0 for all nine development cases and registered origin controls. Each
configuration retains 36 RK4 and 28 separate pool diagnostic rungs. The
selected 64-substep same-norm floors, including their arithmetic bounds,
were eligible in every case; coarse failures remain archived. The following
maximum fractions use the fixed quarter-tolerance eligibility budget:

| Case | Selected-64 maximum floor / tolerance |
|:--|--:|
| One-way transfer | 3.1554928181613646e-12 |
| Opposing net-zero exchange | 4.765413720348596e-6 |
| Three-compartment cycle | 9.710551269683147e-7 |
| Unequal compositions | 1.970127373902598e-6 |
| Empty replenished donor | 1.0644126818743075e-9 |
| Exact depleted endpoint | 3.31216528779494e-12 |
| Stiff opposing floor | 8.310061860770055e-5 |
| Zero activity | 2.853819184610238e-12 |
| Separate rain/snow sedimentation/export | 1.4004315613630354e-6 |

These are manufactured development measurements, not atmospheric reference
floors. Zero activity does not validate a donor rule. Source overlays do not
enter closure; per-compartment and export-origin tolerances remain explicitly
engineering checks. Actual PX14 rate/cadence/rain evidence, PX25 and OD15,
producer/lifecycle capture, held-out/count/window, parity/restart/device/cost
and physical precipitation/EDMF qualification remain absent.

Independent actual-patch review reproduced an evidence gap with fresh
artifact hashes: doubled or initially negative directed water activity, or
a zero-weight pseudo application list, could retain fixture PASS with exact
endpoint fields. The implementation now declares the candidate's exact
integrated synthetic-interval convention and reconstructs every directed
mean-share application from its native accumulators. The candidate's water
amounts reproduce the pinned rates; an arbitrary nonempty application list
is refused. Native water accumulators are nonnegative, monotone and
zero-initial; label accumulators are finite and zero-initial. Every native
parent/label endpoint change is checked against the directed incidence sum,
with a same-unit arithmetic allowance based only on its own initial and
operated magnitudes. Fixture PASS and reference floors require consistency.
This changes no frozen equation, case, norm or tolerance.

The fix preserves label-origin discrimination. Candidate label amounts are
not replaced by oracle labels or normalized to a correct partition share.
The net-erasure mutant can therefore retain real directed water activity
and zero origin transfers, and fail process/origin rows. Generic registered
origin permutations remain corruption controls and may also fail directed
label balance; they are not represented as complete wrong-donor applications.
Fresh-hash tests check malformed water/rosters, initial accumulator offsets
and label amounts that disagree with otherwise correct endpoint profiles.

The complete existing Bundle CLI validation returned exit 0. The full
production scorer returned exit 2 and `NOT QUALIFIED`, retaining missing
native/runtime/accounting/approval rows rather than promoting the fixture.
The first focused execution retained its checksum-diagnostic assertion
failure; preserving the underlying Bundle reason resolved it without
changing science. Complete bounded acceptance and accounting reruns pass
49 and 56 tests; the previously truncated CLI-fault test also passes.
Earlier incomplete logs are inconclusive. The full 27-test transport/closure
run has one existing missing-`netCDF4` error; an explicitly selected supported
26-test subset passes, without changing or skipping any original test.
The final source-stamped rerun passes 33 focused tests, 49 acceptance tests,
56 accounting tests and the explicitly supported 26 transport/closure tests.
The first final accounting attempt lacks a completion summary and remains
inconclusive; its separate confirmation records expected/run=56 with no
failures, errors or skips. Both full nine-case suites were regenerated with
these evaluator identities and retain all rungs. Independent supplemental
review reproduced every prior malformed-evidence counterexample with fresh
hashes: invalid water/rosters/initial offsets are refused, and label amounts
that disagree with correct endpoint profiles fail directed balance. Valid
wrong-donor, net-erasure and owner-reset controls retain their discriminatory
meaning. No concrete code bugs remain in that review. Its mathematical and
written-performance passes concern bounded offline Python/NumPy code; no
model hot path or device allocation claim is made.

| Final identity | SHA256 |
|:--|:--|
| Frozen design | `2f57920536d142dca834ed67df9ed0f6e09305ec11833b484f8b200849238a42` |
| Equation/reference evaluator | `714e543384471f24a5eb65364d1bedb3b56db7ae640a1f8919660fb50abc2d9d` |
| Native Bundle adapter | `d22bdf4cb651f7787fe1eb824bf5fc4c5a7c1905273d22cbb50f1b2b97feb526` |
| Complete fixture driver | `87d1e89b23ed918176e5582972e9162a19e22f86f59afcc1a782d6083474ae1a` |
| Existing acceptance scorer | `e42d50363b82418575e3c50a4e554a2be9f6cedd0f7b247ded1d5f6d17493161` |

Local raw logs, complete native archives, review probes/report and a
base-verified applyable patch accompany the publication handoff. The
reproducible commands are in the evidence README. Physical completeness
and reconciliation with the advanced Part 6 branch remain open.
