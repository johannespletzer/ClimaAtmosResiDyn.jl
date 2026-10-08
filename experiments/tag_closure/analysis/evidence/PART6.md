# Independent water transport references

Base: `claude/plan-rev2` at `9c710edcea50d78e8e668e738223bc71c32a69f8`,
which holds the reviewed Part 4 scorer and the Part 5 accounting reader.
This is bounded offline implementation work. It runs no model. No physical
atmosphere, held-out or eight-tag claim is qualified by a small known-answer
case.

## Inventory and frozen design

[water_transport_design.json](water_transport_design.json) freezes equations,
IC/BC, densities, velocities, label definitions, exact physical times,
every refinement rung, scoring and mutation rules. The file records
`frozen_before_results: true`. That is the author's statement. Its hash shows
that the file has not changed since, not when it was written. These are
development cases. Soares, TRMM and sites 23/26 remain development cases
under OD14. No previous case is relabelled held-out. WA-SCOPE's two cases are
named (decision of 2026-10-08). The 24 h development case is the GCM-driven
column, and the held-out case is RICO 1M, 24 h. These fixtures are neither,
and nothing here is tuned on either. No new tolerance is set here.

| Existing reference or account                                                         | Shared components                                                           | Independent component and what it can establish                                                                                                                     | Disposition                                                       |
|:------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------- |
| `test/tagged_water_tests.jl`, plume/exchange bound tests                              | Production plume/bound kernels, partition masks                             | Explicit zero/full-mixing/restart and composition expectations check local kernels. They provide no numerical floor for transport                                   | Reuse. Not run by this PR                                         |
| `test/tagged_water_edmf_copies_integration.jl`, uniform composition/copies flux tests | Parent, generic SGS tracer flux, mirrors, tag update assumptions            | Constant-composition and copies sum identities check accounting. Same-parent isolation cannot test shared update rules                                              | Reuse. Not physical origin truth                                  |
| `test/prognostic_equations/tracer_mass_consistency_tests.jl`                          | Native continuity/transport operators                                       | Uniform chi tests discrete consistency. Subsidence boundary and non-vacuity checks are useful engineering tests                                                     | Reuse. Not independent advection solution                         |
| Existing `d4w_driver.jl`, `wp4c_diag_probe.jl`, `wp4c_gate_probe.jl`                  | Actual model operators and scratch states                                   | Accepted-state and fixed-parent probe patterns isolate per-rule exposure and lag                                                                                    | Reuse lifecycle/patterns. Do not assume complete per-tag producer |
| Analytic translation and labelled inflow                                              | Declared continuum equation, prescribed rho/u, IC/BC                        | Separately integrated cell averages test direction, density weighting, origin ownership and labelled inflow. No ClimaAtmos tag update is called                     | New minimal runnable known-answer cases                           |
| Independent finite-volume translation                                                 | The same continuum equation/IC/BC only                                      | Separately implemented first-order conservative upwind update measures numerical floor against analytic answers. Its diffusion is reported apart from label defects | New small numerical reference. Each rung retained                 |
| Conservative two-reservoir mixing                                                     | Prescribed equal opposing water flow and fixed reservoirs                   | Closed-form composition decay versus an independent backward-Euler/Newton 2x2 solve. Zero net parent transfer still mixes origins                                   | New minimal exchange case. No atmospheric plume claim             |
| PX11 passive air twin                                                                 | Parent/grid-scale operators. Copies also share updraft filter               | Source-free active tag-rule bundle only, with measured excluded physics and floors. Cannot validate a shared operator                                               | Existing scheduled design. Actual producer/execution blocked      |
| PX12 copies                                                                           | Parent, updraft generic transport, some source/bound/rain-out assumptions   | Independently implemented subgrid share/exchange components only after all copies checks pass                                                                       | Existing eligibility work. Actual rungs/evidence blocked          |
| Part5 closure/activity                                                                | Accepted parent/tag applications where available. Production registry empty | Signed/retained/application accounting detects cancellation, not whether the giving pool is right                                                                   | Reuse strict reader. Missing actual producers remain blockers     |

The useful minimum is two smooth periodic directions, two labelled boundary
directions and one conservative exchange. It tests nonuniform density,
nonuniform native cell geometry, overlapping/very small/zero source tracers,
and a total-preserving origin swap. It is not a general transport framework.
G3_PLAN 6.1.3 also asks for dry and zero-state limits. The frozen design has
no such case, and adding one would change its hash. A unit test checks
instead that a dry or zero-water parent is a data failure, as in the scorer.
The independent numerical reference is tested on known answers before it can
judge a candidate. Candidate error and reference discretization/integration
floors are reported separately. Floors are never subtracted from error.

## Equations and native convention

For a cell V, let m_i = rho chi_i be tag density and let rho obey
`d rho/dt + div(rho u) = S_rho`. Tag mass obeys

`d(rho chi_i)/dt + div(rho u chi_i) = S_i`.

Expanding gives `rho (d chi_i/dt + u.grad chi_i) = S_i - chi_i S_rho`.
Thus constant-velocity translation with variable advected rho is conservative
with S_i=S_rho=0. Keeping rho stationary while moving chi would solve a
different equation. Periodic fluxes cancel exactly in the domain integral.
At an open boundary the signed outward flux is `rho u chi_i n`. Its known
inflow label determines each origin. Subsidence's model advective form is a
different prescribed-density convention and must not be conflated with this
source-free conservative reference.

The smooth solution uses y=x-u t, k=2 pi/L,
`rho=rho0(1+a cos(k y))`, parent `m=q0 rho`,
`m_a=q0 rho0((1+a cos(k y))/2+b sin(k y))`, and `m_b=m-m_a`.
Analytic cell averages come from antiderivatives over each native face pair.
Specific exported concentrations, when used, are `integral(m_i)/integral(rho)`.
They are not point samples or unweighted averages of chi_i. Positive partition
fractions and source overlays are distinct. A conservative overlap remap is
allowed only as a separately measured discretization floor. No missing time
sample, truncation or time interpolation is accepted. Native alignment is
mandatory for the actual candidate comparison.

For inflow, rho and q0 are constant, the domain initially holds origin B,
and incoming water is origin A. The origin-A front travels at |u|. Its
cell mass is q0 rho times the exact interval intersection with that front.
Parent and partition sum are unchanged while the inventories acquire their
known boundary flux. Discontinuous-front L1 is reported separately from the
smooth case. No smooth convergence order or vanishing Linf is demanded.

For mixing, fixed parent water amounts are Q1,Q2 and equal opposing water
flows F conserve each parent's amount. Each tag obeys
`d m1/dt=F(m2/Q2-m1/Q1)`, `d m2/dt=-d m1/dt`.
With f_eq=(m1(0)+m2(0))/(Q1+Q2), lambda=F(1/Q1+1/Q2),
`m1(t)=Q1 f_eq+Q1 Q2/(Q1+Q2)(f1(0)-f2(0)) exp(-lambda t)`.
`m2(t)` is its conserved remainder. Analytic amounts are converted back to
native cell density with each thickness. The independent solve assembles its
own conservative 2x2 generator and evaluates the actual implicit residual and
Jacobian at every requested Newton count. This small linear Newton test is
not evidence about ClimaAtmos's nonlinear Newton floor.

An independent quadrature of the smooth profile checks analytic integration
at orders 8/16/32. Translation reports every grid (16/32/64) and timestep
(120/60/30 s). Newton is explicitly inapplicable. Mixing reports every dt and
actual Newton count (1/2/4). Grid refinement is inapplicable to two fixed
reservoirs. No best pair is selected. Raw per-tag errors, native mass defects,
and every known-answer numerical floor are retained at 1 h and 24 h.

## Acceptance and attribution scope

OD3 profile rules are reused unchanged at their approved physical endpoints:
first-hour region L1 1%, source L1 10%, Linf 25%. Day L1 2%, Linf 5%.
The reference imports these limits, the small-tag rule and OD12's quarter
from the scorer's named constants. The design file repeats them for the
record only, and a test checks that the copy matches. A labelled front's
floor is judged in L1 only, as the design's `front_convergence` states. A
candidate's own profile row keeps both norms.
A reference tag below 1% uses its absolute error against 2e-4 of the parent,
replacing both relative tests. Zero references have explicit zero/absolute
errors. Overlays never enter partition closure. OD12 requires each applicable
floor, in the same norm and units, at most a quarter of its tolerance. A
coarse numerical reference can be ineligible even when a refined one passes.
Every rung is shown. No candidate ranking uses a failed reference. The
machine-epsilon closure test is implementation verification, not a new
atmospheric closure tolerance. A known origin swap must pass that total test
and fail at least one origin row.

The existing submission manifest/readers/scorer carry this optional evidence.
Exact design/evaluator/spec/model/config/source hashes, native units/dtype,
geometry, tag names, times and independent-rule scope are required.

Eligibility is declared in an evidence file, as the decision of 2026-10-07
allows (Part 4 scorer choice 4). The adapter
[water_transport_adapter.py](water_transport_adapter.py) is the producing
script. It regenerates every archived rung from the independent equations,
measures each floor in OD3's norms and writes the declaration into
`water_reference_evidence.json`. The declaration holds the producer's name
and sha256, one floor per OD12 source, `converged`, `mirrors_complete` and
`jacobian_complete`. Each value carries the basis it rests on. The manifest
names and hashes the same producer. The scorer reads the declaration through
its own eligibility reader and does not import the adapter. Rerun on a
finished bundle, the adapter refuses a declaration that differs from its
recompute. The two fixture modules are therefore not scorer files. They are
pinned by the producer's hash and by the evidence file's `evaluator_files`,
beside the design hash.

| Declared value                                                          | What it rests on                                                                                                                                                                                                      |
|:----------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reference-discretization floor                                          | Measured from the rungs in numerical mode. In analytic mode it is a constructed roundoff bound, plus the measured quadrature floor for the smooth cases (next section).                                               |
| Source-injection, initialization, parent-solve and contamination floors | Stated as zero, each with its reason. They are statements about the frozen equations, not measurements. A nonzero initial-state error or an active excluded process refuses the evidence instead of entering a floor. |
| `converged`, numerical mode                                             | Measured. No refinement step toward the selected rung raises its floor, with a rise within the frozen roundoff allowance read as a tie.                                                                               |
| `converged`, analytic mode                                              | Declared true as inapplicable. A closed form has no ladder. The independent numerical route is reported in `closed_form_cross_check` and gates nothing.                                                               |
| `mirrors_complete`                                                      | Declared true as inapplicable. Source mirrors and the Jacobian are copies conditions (G3_PLAN 6.1.2). These equations have no source, and every excluded process reads zero.                                          |
| `jacobian_complete`                                                     | Measured for the exchange solve: the residual after the first Newton iteration is at roundoff. Declared true as inapplicable for the closed form and the explicit upwind.                                             |

Active-rule coverage stays reported, with the OD9 limitation, and is never a
gate (WA-GATES (b)). The TRMM pilot's first-hour row is untouched by this
work. It is scored only after PX12's eligibility, which these fixtures do not
supply. Parent parity is the scorer's, unchanged. In a full score,
exported-only parity leaves the eligibility rows and the origin rows not
assessable. The suite reports its fixture scope and actual floors. It cannot certify
PX11/PX12, parent physics, moist precipitation or a wider count/window. No
new state field or runtime hook is introduced here.

## Every Part6 obligation and its next dependency

| Obligation                                                        | Reused / new / triggered / blocked                      | Concrete completion or remaining gate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
|:----------------------------------------------------------------- |:------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Task1 exact dependency/current refs/source/guides                 | Reused and inspected                                    | The base is plan-rev2 at `9c710edc`, with the reviewed scorer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Task2 minimum inventory/design/freeze                             | New                                                     | This inventory and the frozen JSON. That it was frozen before results is the author's statement (owner line below).                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Task3 independent equations/scope/conventions                     | New                                                     | Analytic, independent numerical, same-parent, copies and closure distinguished above. No shared tag rule validates itself.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Task4 translation/mixing/density/direction/boundaries/mutant      | New                                                     | Runnable independent cases and adapter/tests. Source overlays/small/zero included. Exact closure with wrong origins required.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| PX1 then PX8 regardless low hourly screen                         | Reused. Actual execution blocked                        | Hourly screen cannot establish immateriality. Accepted-step exact subsidence exposure requires actual states and operator capture. Preserve two D4-W cases and site23 windows.                                                                                                                                                                                                                                                                                                                                                                            |
| PX16/PP-SUB                                                       | Triggered only                                          | Material PX8 plus OD13 and diagnostic-only approved job. No new runtime state/activation here.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| PX7 lag versus structure                                          | Reused. Blocked execution                               | Existing solver sets/probe. Freeze matched physical times, fixed-parent trial and full-parent trajectory separately. Existing monotone ratios <=.25/<=.75 for lag, >.9 structural. Neither validates origins.                                                                                                                                                                                                                                                                                                                                             |
| PX11 clean Soares / PX24 accounting                               | Reused. Blocked production channels                     | Measure sedimentation (<1e-4 parent), zero subsidence/forcing, surface/init/parent/linearity floors before scoring. No named active-rule claim without complete per-tag accounting. OD10 rounding attribution rule stays proposed.                                                                                                                                                                                                                                                                                                                        |
| PX12 TRMM0M / KI4-COPIES / UP1                                    | Reused. Blocked actual evidence                         | dt150/75, Newton2/10 and actual grid/count ladders. Grid/updraft pre-repair residuals/repair, mirrors/Jacobian, initialization/fallback, E per rung <=1e-3. Fixed-parent copies probe uses UP1's own 1-to-10 share-budget rule. Merely running a probe does not resolve it.                                                                                                                                                                                                                                                                               |
| Task6 floors/eligibility/count                                    | New known-answer floor reports. Production blocked      | Every numerical/integration rung retained. Each applicable OD12 floor quarter-tolerance. Full copies evidence still required at actual tag count. Eight-tag target unchanged.                                                                                                                                                                                                                                                                                                                                                                             |
| Task7 manifest/scorer identity/native evidence                    | Reused plus the producer of a declared eligibility file | No parallel manifest, time interpolation, unknown zero, metadata production pass or automatic Part5 completion. The scorer is unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Task8 equation/fault/refinement/mutation tests                    | New plus existing regression suites                     | Exact answers, conservation, zero/small/overlay, dry parent, stale hashes, units/times/geometry/scope/count, shared/ineligible refs, active exclusions, the scorer's reading of the declaration and the driver's exit codes.                                                                                                                                                                                                                                                                                                                              |
| Task9 docs                                                        | New                                                     | G3_TODO, STATUS, the crosswalk and the two READMEs state the partial scope. NEWS has no entry, since experiment tools are not listed there.                                                                                                                                                                                                                                                                                                                                                                                                               |
| Task10 record                                                     | New                                                     | This PR carries the code, the design, the configs and this record. Fixture outputs are regenerated by the commands in the README.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Option D / Part7 / residence-time / energy / Part9 closure tuning | Excluded or separately routed                           | No D4-W origin/convergence reopening, precipitation work on the giving pool, residence-time/energy reference work or production closure tuning.                                                                                                                                                                                                                                                                                                                                                                                                           |
| Waiting for the owner: what the reference models                  | Owner                                                   | The reference solves the continuum equation with first-order upwind of rho chi. The model moves tracers differently. Its vertical default is `vanleer_limiter` on specific chi (`implicit_tendency.jl`). Its horizontal transport is the spectral-element `split_divₕ` (`advection.jl`). Water tags that follow the parent's implicit increment take their vertical advection from that shared increment. The model's column has no labelled inflow boundary. So these cases check label arithmetic and the evidence workflow, not the model's operators. |
| Waiting for the owner: the ladder and the roundoff multiplier     | Owner                                                   | The grids 16/32/64, grid power 1.15, steps 120/60/30 s, Newton counts 1/2/4, quadrature orders 8/16/32 and the 128 eps multiplier are in no contract. PX12's rungs are dt 150/75 s and Newton 2/10, and OD10's proposed rounding row is 1e-10 relative. The dt ladder raises the upwind floor (next section), so it cannot show convergence. No test checks 128 eps from above and below.                                                                                                                                                                 |
| Waiting for the owner: Part 6's deliverable against ROADMAP's row | Owner                                                   | ROADMAP's Part 6 row asks to reuse PX1/PX8, PX7, PX11/PX24 and existing mixing tests, and to run PX12. This PR runs none of them and reuses no existing mixing test in code. It adds the analytic references that the row allows "after design".                                                                                                                                                                                                                                                                                                          |
| Waiting for the owner: frozen before results                      | Owner                                                   | `frozen_before_results` is self-asserted. The suite's own test tolerances, for example the 0.55 exchange ratio, are not in the design file.                                                                                                                                                                                                                                                                                                                                                                                                               |
| Waiting for the owner: inapplicable conditions declared true      | Owner                                                   | `mirrors_complete`, analytic-mode `converged` and `jacobian_complete` for references without an implicit solve are declared true as inapplicable, each with its basis. The scorer requires all three for every reference. If the owner reads them as false, every fixture except the numerical exchange becomes ineligible.                                                                                                                                                                                                                               |

## Execution limits

This PR runs no model and no Julia test. Part 5's verified production
producer registry is empty. Native accepted-step PX8/PX24, copies
applications/fallbacks and paired precipitation cannot be fabricated by a
manifest. Every dependent scientific judgment stays not assessable. Existing
Julia tests and configs remain runnable in a prepared checkout under the
repository's cluster and gated-job rules.

Runtime changes would require Float32/Float64 capture-off/on bitwise parent
parity, every native state field, checkpoint/restart continuity, distributed/
device and hot-path allocation/cost verification. This independent reference
code runs off the model hot path and claims none of those gates.

## Saved implementation and measured execution

The frozen design SHA256 remains
`c1af334b03727c3017810c46d2f826eff51dbdccccac55bb3c5ee6de044749d6`.
[water_transport_reference.py](water_transport_reference.py) implements the
native analytic antiderivatives, front intersections and exchange solution,
and separate quadrature, upwind and implicit-Newton solvers. It counts the
steps and Newton solves it executes.
[water_transport_adapter.py](water_transport_adapter.py) is the producer of
the declared eligibility file and its internal check.
[make_water_transport_fixture.py](make_water_transport_fixture.py) saves
complete immutable fixture archives, the declaration, config and source
identities and the measured results. Its exit codes follow the scorer's.
[The focused tests](test_water_transport_reference.py) check equations,
faults, the scorer's reading of each case and the driver's exit codes.
[Runnable commands](README.md#independent-water-known-answer-fixtures) use
both complete JSON configurations and preserve failed references.

Every case retains nine numerical rungs, and each smooth case also retains
nine quadrature rungs. A full suite records 45 numerical and 18 integration
rungs. All 18 quadrature rungs and all nine exchange rungs meet the quarter
rule. No upwind rung does.

### What analytic-mode eligibility rests on

In analytic mode the reference is the closed form, and the fixture's
candidate is the same closed form. The candidate passes by construction. The
reference-discretization floor is the larger of two numbers. The first is a
constructed roundoff bound: every tag of the closed form is scaled by
(1 + 128 eps) and compared with the closed form. That gives 2.84e-12 of the
tolerance in all five cases. It is a construction, not a measurement. The
second, for the smooth cases only, is the measured agreement of an
independent Gauss quadrature at orders 8, 16 and 32 on the comparison grid.
The quadrature shares the pointwise profile formulas with the closed form, so
it checks the cell integration, not the equation. For the fronts and the
exchange no measured floor enters. The producer names this verdict
"constructed eligibility". It is not a measured eligibility, and it says
nothing about a model's transport.

### What the numerical ladder shows

Largest floor fraction of each rung over all tags and both endpoints. The
front's floor is its L1 fraction. The first-hour L1 rows dominate every case.

| Case               | grid 16, dt 30 | grid 32, dt 30 | grid 64, dt 120 | grid 64, dt 60 | grid 64, dt 30 |
|:------------------ | --------------:| --------------:| ---------------:| --------------:| --------------:|
| Smooth, both signs | 8.369          | 5.294          | 2.847           | 2.949          | 2.999          |
| Front, positive    | 66.30          | 45.50          | 27.87           | 28.72          | 29.36          |
| Front, negative    | 50.26          | 72.67          | 51.73           | 52.67          | 53.13          |

The smooth upwind floor falls by 0.63 and then 0.57 per grid doubling. At the
measured 0.57, reaching the quarter would take about 1,300 cells. At first
order's asymptotic one half it would take about 800. Both are extrapolations,
not runs. Along the dt ladder the floor rises as the step shrinks. First-order
upwind's numerical diffusion is u dx (1 - C)/2 with Courant number C. In the
smooth cases C is 0.005 to 0.08, so a smaller step adds diffusion. The dt ladder cannot
show convergence for this scheme, and the producer declares every upwind
reference not converged for that reason. The negative front does not fall
with the grid either. At one hour it sits in the coarse cells at the inflow
end (grid power 1.15). The exchange floor is 0.0182, 0.0091 and 0.0046 at dt
120, 60 and 30 s, first order in dt. It is the same at Newton 1, 2 and 4,
because the system is linear and λ dt is at most 3.7e-3. Its Newton axis
measures nothing. The choice of ladder is the owner's (obligations table).

| Selected numerical reference (grid 64, dt 30, exchange Newton 4) | Reference-discretization floor | Converged            | Eligible      | Candidate disposition              |
|:---------------------------------------------------------------- | ------------------------------:|:-------------------- |:------------- |:---------------------------------- |
| Smooth positive                                                  | 2.99938                        | No, dt axis          | No            | Not assessable                     |
| Smooth negative                                                  | 2.99938                        | No, dt axis          | No            | Not assessable                     |
| Inflow positive                                                  | 29.3649                        | No, dt axis          | No            | Not assessable                     |
| Inflow negative                                                  | 53.1270                        | No, grid and dt axes | No            | Not assessable                     |
| Conservative exchange                                            | 0.00456819                     | Yes                  | Yes, measured | Manufactured equation check passes |

The analytic suite reports constructed eligibility for all five cases and
verifies all five closure-preserving wrong-origin mutants. Its exit is 0. The
numerical suite exits 3: its four upwind references are ineligible. These
values do not imply that refining beyond the frozen ladder would pass or
that any atmospheric reference is eligible. Every rung's raw rows are kept
in the result bundles, and no best pair is selected.

Fixture PASS requires the candidate's OD3 profiles, its partition closure
and its prescribed native exported-parent trajectory against the analytic
equation, within the frozen arithmetic allowance. Specific profiles and
closure alone would miss a proportional scaling of density, parent and all
tags. This is an implementation check and does not certify physical
all-state parent parity. Mutant verification checks the actual saved swap
and every frozen initial-state, parent and overlay invariant. Changing the
parent, an overlay or the kind of wrong-origin assignment fails it even when
total closure and origin discrimination hold.

On this tree the 36 focused tests pass, and so does the whole evidence
directory. The existing Bundle CLI validates an analytic fixture with exit 0.
The full acceptance scorer on the same fixture exits 2 and stays
`NOT QUALIFIED`. Native temperature, negative water, Newton, ledgers and the
6 h and 12 h samples are absent, and exported-only parity leaves its
eligibility rows not assessable. A fixture-driver PASS is not a full-scorer
pass.
