# Independent water transport references

Base: `codex/correction-accounting-part5` at
`1b04926582941740f2599a92c57acb3ad0abb1c6`, tree
`1752d1248a3c5327c6d81becfe1ff0949dd8c3ed`. This is local bounded
implementation work. No physical atmosphere, held-out or eight-tag claim is
qualified by a small known-answer case. The dependency remains unmerged in
PR151. PR146 has since merged on main at `12377fb885149d5180031c0e6a41d8dc8041e4ef`;
its divergent model changes are not absorbed into this exact base.

## Inventory and frozen design

This design was saved before implementing or inspecting deciding results.
[water_transport_design.json](water_transport_design.json) freezes equations,
IC/BC, densities, velocities, label definitions, exact physical times,
every refinement rung, scoring and mutation rules. These are development
cases. Soares, TRMM and sites 23/26 remain development cases under OD14.
No previous case is relabelled held-out. A new scientific cutoff is pending
owner approval; numerical tests cannot approve it.

| Existing reference or account | Shared components | Independent component and what it can establish | Disposition |
|:--|:--|:--|:--|
| `test/tagged_water_tests.jl`, plume/exchange bound tests | Production plume/bound kernels, partition masks | Explicit zero/full-mixing/restart and composition expectations check local kernels; they provide no numerical floor for transport | Reuse; Julia execution blocked locally |
| `test/tagged_water_edmf_copies_integration.jl`, uniform composition/copies flux tests | Parent, generic SGS tracer flux, mirrors, tag update assumptions | Constant-composition and copies sum identities check accounting; same-parent isolation cannot test shared update rules | Reuse; not physical origin truth |
| `test/prognostic_equations/tracer_mass_consistency_tests.jl` | Native continuity/transport operators | Uniform chi tests discrete consistency; subsidence boundary and non-vacuity checks are useful engineering tests | Reuse; not independent advection solution |
| Existing `d4w_driver.jl`, `wp4c_diag_probe.jl`, `wp4c_gate_probe.jl` | Actual model operators and scratch states | Accepted-state and fixed-parent probe patterns isolate per-rule exposure and lag | Reuse lifecycle/patterns; do not assume complete per-tag producer |
| Analytic translation and labelled inflow | Declared continuum equation, prescribed rho/u, IC/BC | Separately integrated cell averages test direction, density weighting, origin ownership and labelled inflow; no ClimaAtmos tag update is called | New minimal runnable known-answer cases |
| Independent finite-volume translation | The same continuum equation/IC/BC only | Separately implemented first-order conservative upwind update measures numerical floor against analytic answers; its diffusion is reported apart from label defects | New small numerical reference; each rung retained |
| Conservative two-reservoir mixing | Prescribed equal opposing water flow and fixed reservoirs | Closed-form composition decay versus an independent backward-Euler/Newton 2x2 solve; zero net parent transfer still mixes origins | New minimal exchange case; no atmospheric plume claim |
| PX11 passive air twin | Parent/grid-scale operators; copies also share updraft filter | Source-free active tag-rule bundle only, with measured excluded physics and floors; cannot validate a shared operator | Existing scheduled design; actual producer/execution blocked |
| PX12 copies | Parent, updraft generic transport, some source/bracket/rain-out assumptions | Independently implemented subgrid share/exchange components only after all copies checks pass | Existing eligibility work; actual rungs/evidence blocked |
| Part5 closure/activity | Accepted parent/tag applications where available; production registry empty | Signed/retained/application accounting detects cancellation, not donor correctness | Reuse strict reader; missing actual producers remain blockers |

The useful minimum is two smooth periodic directions, two labelled boundary
directions and one conservative exchange. It tests nonuniform density,
nonuniform native cell geometry, overlapping/very small/zero source tracers,
and a total-preserving origin swap. It is not a general transport framework.
The independent numerical reference is tested on known answers before it can
judge a candidate. Candidate error and reference discretization/integration
floors are reported separately; floors are never subtracted from error.

## Equations and native convention

For a cell V, let m_i = rho chi_i be tag density and let rho obey
`d rho/dt + div(rho u) = S_rho`. Tag mass obeys

`d(rho chi_i)/dt + div(rho u chi_i) = S_i`.

Expanding gives `rho (d chi_i/dt + u.grad chi_i) = S_i - chi_i S_rho`.
Thus constant-velocity translation with variable advected rho is conservative
with S_i=S_rho=0; keeping rho stationary while moving chi would solve a
different equation. Periodic fluxes cancel exactly in the domain integral.
At an open boundary the signed outward flux is `rho u chi_i n`; its known
inflow label determines each origin. Subsidence's model advective form is a
different prescribed-density convention and must not be conflated with this
source-free conservative reference.

The smooth solution uses y=x-u t, k=2 pi/L,
`rho=rho0(1+a cos(k y))`, parent `m=q0 rho`,
`m_a=q0 rho0((1+a cos(k y))/2+b sin(k y))`, and `m_b=m-m_a`.
Analytic cell averages come from antiderivatives over each native face pair.
Specific exported concentrations, when used, are `integral(m_i)/integral(rho)`;
they are not point samples or unweighted averages of chi_i. Positive partition
fractions and source overlays are distinct. A conservative overlap remap is
allowed only as a separately measured discretization floor; no missing time
sample, truncation or time interpolation is accepted. Native alignment is
mandatory for the actual candidate comparison.

For inflow, rho and q0 are constant, the domain initially holds origin B,
and incoming water is origin A. The origin-A front travels at |u|; its
cell mass is q0 rho times the exact interval intersection with that front.
Parent and partition sum are unchanged while the inventories acquire their
known boundary flux. Discontinuous-front L1 is reported separately from the
smooth case; no smooth convergence order or vanishing Linf is demanded.

For mixing, fixed parent water amounts are Q1,Q2 and equal opposing water
flows F conserve each parent's amount. Each tag obeys
`d m1/dt=F(m2/Q2-m1/Q1)`, `d m2/dt=-d m1/dt`.
With f_eq=(m1(0)+m2(0))/(Q1+Q2), lambda=F(1/Q1+1/Q2),
`m1(t)=Q1 f_eq+Q1 Q2/(Q1+Q2)(f1(0)-f2(0)) exp(-lambda t)`;
`m2(t)` is its conserved remainder. Analytic amounts are converted back to
native cell density with each thickness. The independent solve assembles its
own conservative 2x2 generator and evaluates the actual implicit residual and
Jacobian at every requested Newton count. This small linear Newton test is
not evidence about ClimaAtmos's nonlinear Newton floor.

An independent quadrature of the smooth profile checks analytic integration
at orders 8/16/32. Translation reports every grid (16/32/64) and timestep
(120/60/30 s); Newton is explicitly inapplicable. Mixing reports every dt and
actual Newton count (1/2/4); grid refinement is inapplicable to two fixed
reservoirs. No best pair is selected. Raw per-tag errors, native mass defects,
and every known-answer numerical floor are retained at 1 h and 24 h.

## Acceptance and attribution scope

OD3 profile rules are reused unchanged at their approved physical endpoints:
first-hour region L1 1%, source L1 10%, Linf 25%; day L1 2%, Linf 5%.
A reference tag below 1% uses its absolute error against 2e-4 of the parent,
replacing both relative tests. Zero references have explicit zero/absolute
errors; overlays never enter partition closure. OD12 requires each applicable
floor, in the same norm and units, at most a quarter of its tolerance. A
coarse numerical reference can be ineligible even when a refined one passes;
every rung is shown. No candidate ranking uses a failed reference. The
machine-epsilon closure test is implementation verification, not a new
atmospheric closure tolerance. A known origin swap must pass that total test
and fail at least one origin row.

The existing submission manifest/readers/scorer carry this optional evidence.
Exact design/evaluator/spec/model/config/source hashes, native units/dtype,
geometry, tag names, times and independent-rule scope are required. Submitted
eligibility booleans, shared agreement and synthetic metadata are not runtime
production validation. The suite reports its fixture scope and actual floors;
it cannot certify PX11/PX12, parent physics, moist precipitation or a wider
count/window. No new state field or runtime hook is introduced here.

## Every Part6 obligation and its next dependency

| Obligation | Reused / new / triggered / blocked | Concrete completion or remaining gate |
|:--|:--|:--|
| Task1 exact dependency/current refs/source/guides | Reused and inspected | 150 exact-base blobs materialized; no git checkout/local branch. Current merge state documented separately from immutable source. |
| Task2 minimum inventory/design/freeze | New | This inventory and frozen JSON saved before implementation/results. |
| Task3 independent equations/scope/conventions | New | Analytic, independent numerical, same-parent, copies and closure distinguished above; no shared tag rule validates itself. |
| Task4 translation/mixing/density/direction/boundaries/mutant | New | Runnable independent cases and adapter/tests; source overlays/small/zero included; exact closure with wrong origins required. |
| PX1 then PX8 regardless low hourly screen | Reused; actual execution blocked | Hourly screen cannot establish immateriality; accepted-step exact subsidence exposure requires actual states and operator capture. Preserve two D4-W cases and site23 windows. |
| PX16/PP-SUB | Triggered only | Material PX8 plus OD13 and diagnostic-only approved job; no new runtime state/activation here. |
| PX7 lag versus structure | Reused; blocked execution | Existing solver sets/probe; freeze matched physical times, fixed-parent trial and full-parent trajectory separately. Existing monotone ratios <=.25/<=.75 for lag, >.9 structural; neither validates origins. |
| PX11 clean Soares / PX24 accounting | Reused; blocked production channels | Measure sedimentation (<1e-4 parent), zero subsidence/forcing, surface/init/parent/linearity floors before scoring. No named active-rule claim without complete per-tag accounting; OD10 rounding attribution rule stays proposed. |
| PX12 TRMM0M / KI4-COPIES / UP1 | Reused; blocked actual evidence | dt150/75, Newton2/10 and actual grid/count ladders; grid/updraft pre-repair residuals/repair, mirrors/Jacobian, initialization/fallback, E per rung <=1e-3. Fixed-parent copies probe uses UP1's own 1-to-10 share-budget rule; merely running a probe does not resolve it. |
| Task6 floors/eligibility/count | New known-answer floor reports; production blocked | Every numerical/integration rung retained; each applicable OD12 floor quarter-tolerance; full copies evidence still required at actual tag count. Eight-tag target unchanged. |
| Task7 manifest/scorer provenance/native evidence | Reused plus optional narrow adapter | No parallel manifest, time interpolation, unknown zero, metadata production pass or automatic Part5 completion. |
| Task8 equation/fault/refinement/mutation tests | New plus existing regression suites | Exact answers, conservation, zero/small/overlay, stale hashes, units/times/geometry/scope/count, shared/ineligible refs, active exclusions/incomplete coverage. Julia/netCDF4 execution blockers recorded. |
| Task9 docs/independent actual-diff review | New local deliverable | Update G3_TODO/STATUS/CROSSWALK/README/NEWS with partial scope; independent equations/floor/eligibility/mutation/performance review and fixes, then focused rerun. |
| Task10 handoff | New local artifacts | Exact files/base/patch/hashes, designs/configs, outputs/floors/mutants, tests/review/open tasks and draft PR text; no remote write. |
| Option D / Part7 / residence-time / energy / Part9 closure tuning | Excluded or separately routed | No D4-W origin/convergence reopening, precipitation-donor work, residence-time/energy reference work or production closure tuning. |

## Execution blockers and bounded next commands

No Julia binary or prepared runtime environment is available; netCDF4 is
absent. These are execution limitations, not model failures. Part5's verified
production producer registry is empty. Native accepted-step PX8/PX24, copies
applications/fallbacks and paired precipitation cannot be fabricated by a
manifest. Partial offline completion leaves every dependent scientific
judgment not assessable. Existing tests/configs remain runnable in a prepared
full checkout under the repo's cluster/gated-job rules; no jobs are launched
by this local implementation.

Runtime changes would require Float32/Float64 capture-off/on bitwise parent
parity, every native state field, checkpoint/restart continuity, distributed/
device and hot-path allocation/cost verification. This local independent
reference code runs off the model hot path and cannot claim those gates passed.
The exact future commands and required inputs are saved with the local handoff;
large simulations, dependencies and CI changes are outside this authorization.

## Saved implementation and measured execution

The frozen design SHA256 remains
`c1af334b03727c3017810c46d2f826eff51dbdccccac55bb3c5ee6de044749d6`.
[water_transport_reference.py](water_transport_reference.py) implements the
native analytic antiderivatives/front intersections/exchange solution and
separate quadrature/upwind/implicit-Newton equations.
[water_transport_adapter.py](water_transport_adapter.py) verifies the
archived independent rungs through the existing Bundle.
[make_water_transport_fixture.py](make_water_transport_fixture.py) saves
complete immutable fixture archives, config/source identities and measured
results; [focused tests](test_water_transport_reference.py) check equations
and faults. [Runnable commands](README.md#independent-water-known-answer-fixtures)
use both complete JSON configurations and preserve failed references.

Every case retains nine numerical rungs; each smooth case also retains nine
quadrature rungs. Thus a full suite records 45 numerical and 18 integration
rungs. All 18 quadrature rungs and nine exchange numerical rungs satisfy
the quarter-tolerance floor. No upwind rung in these registered grids/dt
passes that full gate. Analytic native answers remain eligible through their
measured independent integration and explicit arithmetic floors.

| Selected numerical reference (grid64/dt30; exchange Newton4) | Maximum fraction of OD3 tolerance | OD12 floor <= 0.25 | Candidate disposition |
|:--|--:|:--|:--|
| Smooth positive | 2.9993801653943066 | Ineligible | Not assessable |
| Smooth negative | 2.9993801653943053 | Ineligible | Not assessable |
| Inflow positive | 29.36493390915199 | Ineligible | Not assessable |
| Inflow negative | 53.126964373028336 | Ineligible | Not assessable |
| Conservative exchange | 0.004568187979689864 | Eligible | Manufactured equation check passes |

The analytic suite reports five eligible development cases and verifies all
five closure-preserving wrong-origin mutants. Its exit is 0. The numerical
suite's exit 3 preserves its four ineligible selected references. These
values do not imply that refining beyond the frozen ladder would pass or
that any atmospheric reference is eligible. Raw rows for every norm/tag/time
and rung, including conservation and actual Newton residuals/counts, are
retained in the local result bundles; no best pair was selected.

Resumed regression work confirmed and repaired incorrect same-parent metadata
for fixed-parent numerical inflow/exchange and a fixture PASS that ignored
candidate partition closure. Independent review also reproduced a proportional
scaling of density/parent/all tags that left specific profiles and closure
unchanged. Fixture PASS now also requires the candidate's prescribed native
exported-parent trajectory against the analytic equation, using the frozen
arithmetic allowance. This is an implementation check and does not certify
physical all-state parent parity. The corresponding regressions preserve
their initial conditions and fresh artifact hashes, so they test the actual
verdict rather than checksum rejection. Mutant verification also checks the
actual saved swap and all frozen IC/parent/source-preservation invariants;
changing the parent, an overlay or the kind of wrong-origin assignment fails
that certificate even when total closure and origin discrimination hold.

Julia/prepared runtime is absent, as is netCDF4. Historical broad discovery
ran 129 entries: 127 passed and two errored because netCDF4 was missing
(`test_compare_runs` import and energy-throughput fallback); increment
`test_process_budget` could not import for the same reason. These errors are
execution blockers, not passes or scientific model failures. The selected
acceptance/accounting/reference regression suite avoids those unavailable
dependency paths and is recorded separately in the handoff. No dependencies
were installed, tests disabled, runtime jobs launched or production registry
entries added. Fresh independent actual-diff review is complete, with no
concrete bugs remaining after the verified fixes. Both required mathematical/
physical and performance-guide passes, independent 22-test verification,
four fresh-hash verdict/mutation probes and native-specific conversion are
recorded in the local handoff. The earlier interrupted review is not counted
as completed evidence.

Final execution passes all 22 focused tests and the selected 127-test
acceptance/accounting/reference suite. The existing Bundle CLI validates a
final analytic fixture with exit 0. Running the full acceptance scorer on
that same fixture retains `NOT QUALIFIED` and exit 2: native temperature,
negative-water, Newton, ledger, other required time samples and full runtime
prerequisites are absent. A fixture-driver PASS is not a full-scorer pass.
Raw logs, final evaluator-stamped bundles, exact hashes and independent
review probes are saved in the local handoff alongside the earlier failures.
