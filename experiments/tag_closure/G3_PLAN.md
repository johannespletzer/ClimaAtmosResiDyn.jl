# G3 plan: water tags under EDMF

## Delivery status and order (2026-10-05)

[ROADMAP's execution order](ROADMAP.md#the-execution-order) now governs the
remaining work. This document remains authoritative for G3's technical
design and numerical criteria. Dated results and decisions below are retained.
Parts 2, 4, 5 and 6–10 deliver the first scoped water capability. Part 12 expands
it toward the full production target. The twelve criteria are not silently
narrowed by qualifying a smaller workflow. [PLAN_CROSSWALK.md](PLAN_CROSSWALK.md)
maps every criterion, work-package sub-item and decision to its delivery part.
The original section 5 order below is historical dependency context. Use the
roadmap for execution. Water parity and restart checks apply to every relevant
change, not only the later production-expansion parts.

PR #146 is open at `33cbfd4fa282618788cea54de7a69696b592ead8` on
2026-10-05. Its stage-1 fixes do not establish WP4b stage 2/3 or precipitation
origin validity. Signed closing-ledger cancellation stays in part 5.
Validation of origins against known compositions stays in part 7. Preserve W33, W54 and W60's registered
failures. W62 does not retrospectively change W60.

Final version of 2026-09-23. The draft (`f3ae8ca7`) was reviewed by an
independent agent (`review/agent_reviews/g3_water_plan_review.md`). Every
finding is handled here; the section "Review" at the end maps each to its
change. G3's to-do list, `G3_TODO.md`, follows this plan. Nothing in it has
been run.

*Revised in place on 2026-09-24 by rev. 2 of the work plan* (ROADMAP.md, "Rev.
2 of the work plan"): sections 2, 4.2, 5 and 6.1 below. Each change says
"rev. 2". Every result is reported with the verdicts of the acceptance
contract in ROADMAP.md, and the thresholds rev. 2 adds wait on the owner's
register, OD1 to OD8. *Each decision's current state is in ROADMAP.md's
register, the single source; all but OD7 are decided.*

*Scope added (provenance pathway, 2026-09-26):* the provenance pathway,
[PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md), adds notes to sections 2, 3,
4.1, 4.2, 4.3, 4.5, 6, 6.1, 8 and 9. Each says so. Nothing here is struck.

## 0. Decisions this plan rests on

The owner decided on 2026-09-23:

 1. **G3 is the water tags under EDMF. G4 is the energy source tags**, and
    uses what G3 learns (section 9).
 2. The water tags are to become **operational in the production
    configuration**: a sphere with prognostic EDMF and 1M. So EDMF support is a
    correctness requirement for this family, not an extension. On the roadmap
    it moves out of M8 into M1 to M5. *Set on 2026-09-24 (OD1):* the
    production configuration is `g2_v2_sphere_n2` at 60 levels, with 1M stepped
    implicitly and two Newton iterations, and 8 water and 8 energy tags (OD8).
 3. **Precipitation provenance is in scope, and rain and snow carry their own
    tags** (the review's option b). Under 0M the sink is split by subdomain.
    Under 1M falling water keeps the provenance it had where it formed.
 4. **The exchange is the default, and updraft copies are the audit**, behind
    one switch, as for the energy tags in #95. Measuring the exchange against
    the copies confirms the choice.
 5. **The bound takes its factor from the partition only**, and each source
    tag gets its own. This applies to both families. The instruction for #95 (`2ecc1d86`) was
    carried out in #95 at `dcf7d086` and then removed at the owner's request (`a52b17f7`). Its text is kept under the tag `archive/g3-programme-2026-09-23`.
 6. **This session runs G3's jobs.** A separate session runs the energy jobs.

The plan assumes **PR #95 is merged into `main` with decision 5**. Code
references are to #95's head, `dbe7435c`, unless stated otherwise. Where the
merged code differs, the plan follows the code.

The standing rules hold:

  - model fields stay bit for bit (parity);
  - model code goes into draft PRs that only the owner merges;
  - every result gets a FINDINGS entry;
  - thresholds are set before the runs that test them.

**GPU is out of G3**, as the old G3 had it. The sphere runs on CPU with MPI.

## 1. Why water first

  - **A reference exists.** A water tag is a mass tracer. Its copy in the
    updraft is moved by the same generic code that moves every updraft tracer
    (`sgs_tracer_names`, `docs/src/extending_tracers.md`).
      + Four terms are not generic, and the copies must mirror them (4.1). With
        those mirrors, copies that partition the updraft's `q_tot` are the
        reference for the default mode.
      + Under 1M this holds given one assumption: cloud condensate carries the
        composition of the subdomain it sits in. Rain and snow carry their own
        tags (4.5).
  - **The bookkeeping is exact, to rounding.** The model defines the
    environment by subtraction, `ρa⁰χ⁰ = ρχ − Σⱼ ρaʲχʲ` (`ᶜspecific_env_value`).
    So the inventory bound holds for water with the weight `q_totᵏ`. The review
    checked 20,000 random cases: zero sums to 4e-15, shares down to −3.5e-14.
    It holds while the environment's blend weight is 1 (`a⁰ > 4.2e-4`). Where
    `q_tot⁰ ≤ 0` at a Newton iterate, the exchange does nothing. For energy,
    `Σₖ ρaᵏAᵏ ≠ ρĀ` leaves a real mismatch.
  - **Fewer confounders.** No offset `c`, and no sign problem. No choice
    between the tracer and enthalpy forms, and no pressure work. Phase changes
    conserve `q_tot`.

## 2. G3 is met when

The owner set the thresholds on 2026-09-23, before any G3 run (6.1). The
sphere's numbers and the default mode's cost budget are set later, in a form
fixed now.

| #  | Criterion                                                                                                                                                                                                                                                                                                                                                                                                                           | Milestone |
|:-- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------- |
| 1  | Every G3 headline number is recomputed by the verifier from runs stamped with a manifest. The verifier covers `q_tag_*`, the copies, the rain and snow tags and `pr_tag_*`.                                                                                                                                                                                                                                                         | M0        |
| 2  | Unsupported combinations are refused at configuration, with a test for each (4.8). Known issues 1, 3 and 4 are closed or restated. A file-based column starts with finite water tags. A checkpoint round trip holds in both modes, on the column and on the sphere.                                                                                                                                                                 | M1        |
| 3  | **Parity.** With water tags on, every model field is bit for bit that of the run without them, in both modes. Checked on the 1M EDMF column (D4-W), a 0M EDMF column, with implicit and explicit microphysics, and on two MPI ranks. The column checks run in CI.                                                                                                                                                                   | M1        |
| 4  | **Closure.** On D4-W the water partition's gross residual at 24 h is within budget (6.1), and the second 12 h add no more than the first. What remains is split into named parts, and what the named parts leave is within its budget. The copies' own residual, `q_totʲ − Σᵢ χᵢʲ`, is within its budget, and so is what their repair moves. Under 1M the rain and snow tags close against `ρq_rai` and `ρq_sno`.                   | M2        |
| 5  | **Per-tag accuracy.** *(Restated 2026-10-02, option D: not judged on D4-W; see below.)* Against the copies, the default's per-tag error on D4-W and on the deep development column is within budget at 24 h and in the first hour. A tag below 1% of the partition is judged on its absolute error. A CI test shows the copies and a passive tracer agree to rounding without water-specific terms. Manufactured mixing tests pass. | M3, M5    |
| 6  | **Convergence, as robustness.** *(Restated 2026-10-02, option D: not judged on D4-W; see below.)* At every rung of time step, grid and Newton count, the default meets the per-tag budget. The copies' shares move by less than the per-tag L1 budget between the baseline and the finest rung, with the parent's own change reported beside them.                                                                                  | M3        |
| 7  | **Precipitation provenance.** Under 0M the sink is split by subdomain. Under 1M rain and snow carry tags. `Σᵢ pr_tagᵢ = pr` within budget. The net-flow attribution between compartments is audited against gross process rates on a column, within budget. Surface precipitation by tag is reported with its assumptions.                                                                                                          | M5        |
| 8  | **Held-out columns.** RICO (1M), BOMEX (1M), ARM SGP (1M, deep, continental) and the GCM-driven column (0M) meet criteria 4 and 5 without retuning.                                                                                                                                                                                                                                                                                 | M5        |
| 9  | **Float32.** A Float32 twin of D4-W meets criteria 3 and 4 within 10× the Float64 residual. This is a precision-sensitivity check. It decides no cause: that needs tagged and untagged pairs at each precision, and refinement.                                                                                                                                                                                                     | M3        |
| 10 | **Cost.** Build time, step time and peak memory are measured in both modes and with the rain and snow tags. The copies are measured at 2, 4 and 8 tags and extrapolated, with a time limit. The allocation gates pass. The default mode meets its cost budget, set before V-W11.                                                                                                                                                    | M4        |
| 11 | **Sphere.** Ten days of the G2 sphere with water tags under the chosen default meet the sphere budget: its form is fixed in 6.1, its numbers before the run. A one-day copies twin gives the per-tag error there. A restart holds.                                                                                                                                                                                                  | —         |
| 12 | Reviewed and tested: agent reviews with their findings fixed, CI green, and draft PRs ready. The docs are updated: `tagged_water.md`, whose "same diffusion operators" claim is wrong under 1M; `known_issues.md`; NEWS; and a claim contract for tagged water.                                                                                                                                                                     | M1, M2    |

*Restated 2026-10-02 (option D, the owner):* criteria 5 and 6 are not
judged on D4-W. There the copies are not an eligible comparator at production
cost: their repair fails R5 at 3.98e-3 of the water a day against 2e-3, and
PX5 finds no per-step cause (W54). D4-W keeps criteria 3, 4, 9 and 10, which
do not need the copies. Per-tag accuracy and its convergence are judged where
an eligible reference exists: TRMM 0M against the copies, once PX12 confirms
their eligibility there, and the Soares air twin (PX11), where a passive tracer
built apart from the tag rules must equal the source-free tag. The deep
development column and the held-out columns (criterion 8) keep criterion 5 if
their copies are eligible. G3's accuracy claim is narrowed to match: the tags
are shown accurate where a clean reference exists, not on drizzling
stratocumulus. D4-W's tags are shown to close and are costed. A D4-W
reference (a copies-only fix, or the air twin with PP-TRACER, PX17) is not
pursued unless the owner reopens it.

*Restated 2026-10-02 (criterion 9's rounding floor, the owner):* a Float32
measure meets criterion 9 if it is at most `max(10 × Float64, 3 · eps32 · √n_steps)`, where `eps32 = 2^-23` and `n_steps` is the number of time steps
the measure accumulates over (9.6e-6 of the water for a day at 120 s). The
floor was set after W60's addendum had failed criterion 9 on the named parts
at ten Newton iterations. That verdict stands. The rule is judged on a fresh
pre-registered run (`design/F32_TWIN.md`, section 10).

*Rev. 2:* each criterion is judged by the acceptance contract's rows in
ROADMAP.md, with pass, fail or not assessable. Criterion 4 is the closure row
and criterion 5 the provenance row. Criterion 5 is judged only against copies
that pass comparator eligibility in that run. Where they do not, it is not
assessable, and the Insight 10 tests (refinement, per-tag intervention,
aggregation) bound it under OD5. Criterion 11's plateau is replaced by OD6's
ceiling and growth bound (6.1).

*Scope added (provenance pathway, 2026-09-26, pending OD9 and OD11; OD12 and
OD14 accepted 2026-10-02; revised after the owner's review):* the criteria
and the pathway's
evidence levels. The criteria are judged as approved. The levels are reported
beside them.

  - **Criterion 5** would also report a fidelity level, the observed spread
    and the exposure screen per tag, with the active, shared and untested
    rules. Neither the spread nor the screen is an error bound. Copies that
    pass eligibility validate only the active rules they do not share: the
    plume, the exchange and the SGS share. Its clause "a CI test shows the
    copies and a passive tracer agree to rounding without water-specific
    terms" stays a CI identity test (W20's copies group). PX11 (the Soares
    air twin, the pathway's clean label benchmark) adds a scored run beside
    it and does not replace it. The pathway defers PX9 (the propagation
    probe) and PX18 (a band region) until a measured result needs them.
  - **Criterion 7:** the net-flow audit and WP4b's pool rule map to PX14,
    deferred until WP4b moves toward validation.
    *Scope added (provenance pathway, 2026-09-27, from the owner's review of
    #121, pending OD15):* the audit is also reported normalized, and the
    compartments' residuals and `Σ pr_tag` are recorded over a refinement
    matrix (PX25). The approved audit row, 10% of each tag's precipitation
    over the day (6.1), is unchanged.
  - **Criterion 8** stays as approved. PX23, one held-out case named before
    any rule is tuned, is reported beside it as Val-4, under OD14's hygiene.
    The owner stated on 2026-09-26 (PR #122) that the GCM-driven column,
    which starts from site 23, does not count as held out for a rule
    developed using site 23. Val-4 stays not assessable until an independent
    case and its reference are fixed.
  - **Criterion 12:** the claim contract for tagged water carries the rule
    classification of the pathway's section 4 and the declared labelling
    model of its section 1 (OD11).

*The owner's answers, 2026-09-24 (ROADMAP.md, "The owner's answers").*
Criterion 11's "ten days of the G2 sphere" is superseded: ninety days of
`g2_v2_sphere_n2` at 60 levels, judged by the level the residual reaches over
the 90 days against OD6's ceiling. Criteria 5 and 8 are judged at 8 tags, with
copies at 8 as the direct audit where they pass eligibility (OD8). Criterion
10's copies at 32 tags are a cost item only, not qualified. Under OD5 a
configuration whose provenance is not assessable qualifies only as "provenance
bounded, not validated", and only if the Insight 10 tests pass.

### 2.1 Part 2: the first useful water workflow (proposed, 2026-10-06)

The water acceptance specification is section 6.1.1 onward. It makes the
approved rows executable without changing their values or treating a short
benchmark as the full G3 objective. This Part 2 is documentation, not a water
qualification result. Sections 0 and 2, OD1–OD8, option D and the later owner
amendments remain in force. The pathway's OD9–OD11 labels remain proposed.

**Recommendation for the first increment:** reuse the existing TRMM_LBA 0M
EDMF column and its three named tracers, with six hours as the baseline pilot.
It is the nearest existing moist case with subdomain rain-out, parent parity,
small measured intervention and a plausible copies comparator. Use it to ask:
"Under the declared label model, how much of the column's current total water
carries a lower-entry or upper-entry label, and how much carries the surface
moisture-source label?" Inventory attribution is the initial useful claim.
Surface precipitation attribution is a separate claim requiring its own
reference and acceptance rule. Neither has a new pass from this plan.

The region tags are **entry labels, not exclusively initial-region labels**.
`pbl` starts with the smooth lower-altitude mask (centre 1000 m, width 200 m).
`free` starts with its complement. Subsequent attributed production receives
the same fixed spatial masks. Loss in proportion to what each tag holds depletes both. These
two pure region tags form the partition. `evap` starts at zero, receives
`surface_flux` production, and is depleted by loss and transport. It overlaps
the region partition. Never add `evap` to `pbl + free` in a closure or
precipitation-total test. A claim about water initially below 1 km would need
a different declared model and reference. This configuration does not supply
it. The masks do not diagnose a changing physical boundary-layer height.
See [`docs/src/tagged_water.md`](../../docs/src/tagged_water.md), Attribution,
and `water_region_tag_state_names` / `attribute_tagged_ρq_tot!` in
[`tagged_water.jl`](../../src/parameterized_tendencies/tagged_tracers/tagged_water.jl).

Use the resolved configuration of
[`g3b_trmm0m_default_6h.yml`](configs/g3b_trmm0m_default_6h.yml): a CPU
column, 82 uniform vertical elements to 16400 m, `dt: 150secs`, ARS222,
Float64, prognostic EDMF with one updraft, grid-scale cloud, 0M microphysics,
implicit diffusion and two approximate linear-solve iterations. EDMF mass
flux, diffusive flux, pressure, vertical diffusion, filter and prognostic TKE
are on. Retain its calibrated TOML and resolve inherited SGS reconstruction,
Newton controls, limiters and all other defaults in the evidence manifest.
The overlay alone is not the complete configuration. Use
`water_tag_transport: increment` explicitly for the candidate, and the
separate [`copies overlay`](configs/g3b_trmm0m_copies_6h.yml) with
`water_tag_updraft_copy: true` as the audit. These explicit settings select
this workflow. They choose no new repository default. Use the fixed-Newton,
direct block solver for the parity claim. Do not extend it to Krylov or
residual-based Newton termination. Ledgers and audit are required even though
they are off by default. Section 6.1.1 lists additional outputs still needed.

The represented inventory is `ρq_tot`, all water phases. Under 0M there are
no prognostic rain/snow reservoirs: rain-out removes water locally, split by
EDMF subdomain. The column tests vertical transport, EDMF exchange, local
sources/sinks and numerical interventions. It supplies no horizontal
transport, 1M sedimentation, rain/snow donor-pool, MPI sphere, Float32 or
production-envelope qualification. It supplies no residence time or air age.

W58's existing six-hour evidence is parity and accounting evidence. Its R4, R5
and R8 passes stand as recorded, at the six-hour end that
`design/G3_BASELINE_RERUN.md` pre-registered for TRMM. Closure under the
correction after each solve and the partition's instantaneous precipitation sum
are near rounding. The copies' residual and repair pass their recorded checks. Its per-tag differences
are reported only. PX12 must still establish comparator eligibility, including
refinement and KI4-COPIES/UP1. Current gross accounting and independent origin
tests remain required. W58's `pbl` difference at six hours is already slightly
above the approved 24-hour L1 row if that row were transplanted. Do not loosen
a tolerance to turn that observation into a pass.

**Three scopes and their gates:**

| Scope                         | What it can establish                                                                                                                                    | Remaining gate                                                                                                                                                                                                 |
|:----------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial useful workflow above | Conditional inventory attribution for this declared entry/source model, in this column and time interval.                                                | WA-SCOPE (decided 2026-10-07, no qualified three-tag scope), eligible PX12 and independent active-rule tests, and every required matrix row. Six-hour differences remain reported under the existing contract. |
| Mechanism reference cases     | PX11/PX24 source-free transport, manufactured mixing, PX12 subgrid audit and Part 7 known-donor transfer references, each for its measured active rules. | OD12 reference floors/independence and OD14 held-out hygiene. No clean transport pass qualifies moist EDMF or precipitation.                                                                                   |
| Full G3 production objective  | The twelve criteria above, at OD8's intended eight water tags, the approved held-out cases and OD1/OD6's 60-level 1M EDMF sphere over ninety days.       | Parts 10/12 plus relevant implementation, precision, restart, cost and owner gates. Three-tag evidence is no aggregation bridge to eight-tag qualification.                                                    |

WA-SCOPE was decided on 2026-10-07. It does not narrow OD8 or move a
24-hour threshold to six hours, and no three-tag or six-hour scope is
qualified. Prefer the existing pilot for implementation/reference
development. Before a scientifically qualified short workflow is claimed,
the owner must fix its endpoint, tag count, metrics and use-specific accuracy
rationale. The alternative is to retain the approved first-hour and 24-hour
assessment at eight tags. That requires the longer/intended-count evidence
and a declared eight-tag model, rather than silently relabelling this pilot.
Expected effort is a documentation/configuration reuse increment followed by
PX12's existing reference work, complete gross accounting and one cost pilot.
New moist reference design may dominate. W58 is not an estimate for a
90-day sphere. Cost is measured before default selection or expensive runs.

**Disposition of every G3 criterion:** no smaller workflow deletes a row.

| Criterion         | Initial scope disposition                                                                                                        | Destination and full-G3 obligation                                                                                       |
|:----------------- |:-------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------ |
| 1 Evidence        | Required for every claimed number. Current scorer coverage is incomplete.                                                        | Part 4. The verifier covers copies, all compartments and precipitation when introduced.                                  |
| 2 Support/restart | Require this workflow's supported setup, finite start and restart continuity.                                                    | Parts 4/9/10. Retain file-based start, column/sphere and both-mode round trips in Part 12.                               |
| 3 Parity          | Required for tagged/untagged twins in each claimed mode.                                                                         | Every relevant change and Parts 8/10. Broader 1M, explicit and MPI evidence remains scoped to its tested configurations. |
| 4 Closure         | Required for the partition and comparator, with the approved window limits respected.                                            | Parts 5/8/10. D4-W/named parts and EDMF rain/snow closure remain open where not evidenced.                               |
| 5 Origins         | Required against eligible references for named active rules. W58 reported only.                                                  | Parts 6/8/10. Intended-count deep/held-out cases remain. Option D excludes a D4-W judgment.                              |
| 6 Convergence     | Required for reference eligibility and tag numerics. Report parent changes separately.                                           | Parts 6/8/10. Retain grid/time/Newton ladders at the intended count. No D4-W origin ladder under option D.               |
| 7 Precipitation   | Separate, currently unqualified claim. 0M does not test rain/snow reservoirs.                                                    | Part 7 references, applicable Part 9 fixes, Parts 10/12 evidence. Retain all WP4b EDMF stages and audit.                 |
| 8 Held-out        | Freeze an independent case/reference before any benchmark-driven tuning. Missing evidence blocks the applicable qualified claim. | Parts 6/10. Retain all four approved columns in Part 12, with site 23 excluded as held-out for a rule tuned there.       |
| 9 Float32         | Outside the first Float64 claim, explicitly unqualified.                                                                         | Part 12. Preserve D4-W parity/closure checks, W60's failed verdict and W62's limited rounding-floor evidence.            |
| 10 Cost           | Required at the claimed tag count and in both claimed modes before selection.                                                    | Parts 8/10. Part 12 intended-count/sphere measurements and allocation gates stay open.                                   |
| 11 Sphere         | Outside this column claim, explicitly unqualified.                                                                               | Part 8 cost pilot then Part 12. Retain ninety days, residual ceiling/growth, eligible copies twin and restart.           |
| 12 Review/docs    | Required for the contract and each later implementation/qualification.                                                           | Parts 2/4/9/10. Retain CI, draft PR readiness, claim contract, known issues, NEWS and current-code docs.                 |

## 3. What EDMF does to the water, and what the tags miss today

From the inventory of 2026-09-23 and the review, at `dbe7435c`.

| Path                                                                                                                                           | What it does to water                                                                                                                                                                                     | The tags today                                                                                                                                                                                                            |
|:---------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SGS mass flux (`edmfx_sgs_flux.jl:28-175`)                                                                                                     | Moves `ρq_tot`, `ρ` and each species by the updraft's and environment's flux. Always implicit (`implicit_tendency.jl:118`), with Jacobian blocks `(ρq_tot, q_totʲ)`, `(ρq_tot, ρ)` and the species'.      | **Nothing.** No updraft field, so the loop never sees them.                                                                                                                                                               |
| SGS diffusive flux (`:213-427`)                                                                                                                | `ρq_tot` takes `K_h` on `q_tot_eff` (1M: without rain and snow) and `K_e` in the tracer loop (`α = 0`).                                                                                                   | **Leak under 1M:** tags take `(K_h + K_e)` on their whole value. Exact under 0M. The updraft mirror is skipped (B4 guard).                                                                                                |
| Grid-scale hyperdiffusion (`hyperdiffusion.jl:496` against `:548`) and viscous sponge (`viscous_sponge.jl:197` against `:228`)                 | Act on `q_tot_eff` for `ρq_tot` under 1M.                                                                                                                                                                 | **Leak under 1M,** the same kind.                                                                                                                                                                                         |
| Updraft vertical-diffusion mirror (`edmfx_sgs_flux.jl:330` against `:415`) and updraft hyperdiffusion (`hyperdiffusion.jl:555` against `:618`) | The same `q_tot_eff` treatment for `q_totʲ`.                                                                                                                                                              | Copies would inherit the **leak**.                                                                                                                                                                                        |
| Updraft advection, entrainment, filter (`mass_flux_closures.jl:303-316`: clamp to `[0, ρq_tag/ρa]`, reset to `ρq_tag/ρ` where `ρa < ϵ`)        | Move `sgsʲs.q_tot`. The filter never writes `ρq_tot`.                                                                                                                                                     | Generic for copies.                                                                                                                                                                                                       |
| **Updraft 1M sedimentation** (`advection.jl:440-441`, `updraft_sedimentation!` with lateral inflow `α_lat ∂a/∂z ρ⁰w⁰χ⁰`, `:561`)               | Changes `sgsʲs.q_tot` and the updraft species.                                                                                                                                                            | **Copies miss it.** It is not generic.                                                                                                                                                                                    |
| Microphysics, 0M (`microphysics/tendency.jl:101-133`)                                                                                          | The environment (`ρa⁰`) and each updraft (`ρaʲ`) contribute `dq_tot_dt`, and `Δ = Δ⁰ + ΣΔʲ` to rounding.                                                                                                  | Mass exact. **Composition** is the cell's average.                                                                                                                                                                        |
| Microphysics, 1M (`:153-191`)                                                                                                                  | Net tendencies of `q_lcl`, `q_icl`, `q_rai` and `q_sno` per subdomain (`ᶜmp_tendency⁰`, `ᶜmp_tendencyʲs`), from CloudMicrophysics' bulk tendencies. No process rates are exposed. Never changes `ρq_tot`. | Correctly a no-op for total water.                                                                                                                                                                                        |
| Sedimentation, 1M (`water_advection.jl:41-218`)                                                                                                | Grid-mean flux per species. EDMF corrects only the energy flux.                                                                                                                                           | Mass exact. **Composition is reset at each level** (the mirror takes the donor cell's total-water share), so `pr_tag` would be the lowest cell's composition.                                                             |
| Updraft surface boundary (`edmfx_boundary_condition.jl:337-384`)                                                                               | Relaxes `q_totʲ` at level 1 toward `q_b = q̄ + C√σ²`, where the excess is never negative.                                                                                                                 | Nothing at grid scale. Copies need a target.                                                                                                                                                                              |
| Surface flux, forcings, subsidence                                                                                                             | Grid-mean writers, bracketed.                                                                                                                                                                             | Followed. *Scope added (provenance pathway, 2026-09-26): subsidence reaches the tags only through the local bracket, although `subsidence!` is linear in χ; the default and the copies share this rule (PX1, PX8, PX16).* |
| Vertical advection of `ρq_tot` (`implicit_tendency.jl:252, 395`)                                                                               | Implicit, with a post-Newton correction.                                                                                                                                                                  | Explicit for the tags: the known drift.                                                                                                                                                                                   |
| `rescale_water_tags!`                                                                                                                          | Runs inside `tracer_nonnegativity_constraint!`, **before** the filter (`constrain_state.jl:44-48`). Only `repair_water_tag_partition!` runs after it.                                                     | —                                                                                                                                                                                                                         |
| The updraft's precipitation mass loss on the implicit path                                                                                     | `sgs_ρa_implicit_tendency!` overwrites microphysics' `ρa` sink (`initialize_implicit_problem.jl:291`), while `q_totʲ` keeps the `(1 − q)` dilution.                                                       | Documented. The copies' rule mirrors `q_totʲ`.                                                                                                                                                                            |

## 4. Technical design

### 4.1 One switch, two modes

A new key, `water_tag_updraft_copy` (default `false`).

**Default: donor flux plus exchange.** The tags stay grid-scale. In the
implicit tendency, right after the parent's SGS mass flux, each tag takes:

  - **its donor share** of the parent's `ρq_tot` SGS flux, taken from the cell
    the flux leaves;
  - **the exchange** `Xᵢ = Σₖ ρᵏaᵏ(u³ᵏ − u³)(φᵏᵢ − φ̄ᵢ) q_totᵏ`. The bound is
    #95's with decision 5, weighted by `q_totᵏ`. The environment's differences
    follow from the updraft's.

Neither term has a Jacobian block (see 4.3). Under van Leer the exchange is
first-order upwind. The tags' sedimentation does have one today, a diagonal
(`manual_sparse_jacobian.jl:1265-1329`). WP3 and WP4b extend it rather than
build a new one.

**The water plume** differs from the energy plume in two ways:

  - **It is rescaled to the model's updraft water.** At each level, after the
    mixing step, the plume's specific contents are scaled so that they sum to
    `sgsʲs.q_tot`. The shares stay the same, and the next level's mixing
    weights become right. The updraft loses water by 0M rain-out and 1M
    sedimentation, and a plume without this is biased toward low-level water.
    In the review's toy deep plume, the boundary-layer share at the top was
    0.62 without the loss against 0.19 with it.
  - **It starts at level 1 with the grid mean's composition**, the same rule
    as the copies' boundary target below.

It is computed once per evaluation, at the top of `implicit_tendency!`, into
scratch the tags own. The sedimentation mirror (`implicit_tendency.jl:340`)
and the microphysics bracket (`:66`) need it before the SGS flux runs
(`:118`).

**Audit: copies.** Each tag gets `q_tag_<name>` in every `sgsʲs`. The
generic machinery moves them. Four terms are not generic and are mirrored:

 1. **The updraft's 0M sink.** `χᵢʲ += dq (φʲᵢ − χᵢʲ)`, with
    `φʲᵢ = clamp(χᵢʲ / q_totʲ, 0, 1)`. Summed over a partition that holds, it
    is the parent's `q_totʲ += dq (1 − q_totʲ)` exactly (checked to 3e-18). A
    drift keeps its ratio to `q_totʲ` (WP3 review, S6; "decays" was wrong).
 2. **The updraft's 1M sedimentation.** The falling updraft condensate
    carries the copies' composition, and the lateral inflow the environment's.
    The term is linear in `χ` and in `ρ⁰w⁰χ⁰`, so the copies sum to the
    parent's. With rain and snow tags on (4.5), the falling rain and snow carry
    their own copies' composition. Without them, they carry the updraft's
    total-water composition. The term gets a diagonal Jacobian entry, like the
    parent's species.
 3. **The surface boundary.** The parent relaxes `q_totʲ` toward `q_b`. Each
    copy relaxes toward `χᵢ_b = q_b φ̄ᵢ`, the grid mean's composition. The same
    rule starts the plume. It gives no tag water the cell does not hold. An
    `evap` tag at t = 0 gets nothing in the updraft. The energy copies use the
    same rule, and G4 keeps it for both families. A surface pulse measures its
    effect (V-W3).
 4. **The copies' own partition.** After the filter, the residual
    `r = q_totʲ − Σᵢ∈P χᵢʲ` is repaired over the partition copies. It is added
    by share, floored at what the copies hold, as `water_tag_rescale_shift`
    does. The signed amount goes to `q_tag_upfix_<name>`. The filter increment
    is **not** handed on: the filter already clamps each copy, so doing both
    would count the filter twice. `r` before the repair is written as a
    diagnostic, and criterion 4 bounds it.

**Initialisation and rebuild of copies:** `χᵢʲ = q_totʲ φ̄ᵢ`, not the grid
mean's specific value. So the copies sum to `q_totʲ`, also after a file-based
rewrite or a restart. This is a water-specific rebuild, not
`_rebuild_updraft_copies!`. The comparison runs of section 6 start the copies
from the plume instead, through their driver, so that the first hour measures
the dynamics and not a spin-up.

**Expected differences between the modes,** not to be budgeted away:

  - Donor share plus exchange equals the copies' flux only up to the
    reconstruction. At a front they differ by `M⁰(q⁰ − q̄)(φ̄_above − φ̄_below)`.
  - The copies' fluxes sum to the parent's only while both partitions hold.
  - Under van Leer the copies' face values do not sum to the parent's. So
    copies are qualified under first-order or centred reconstruction.
  - Copies need `edmfx_mse_q_tot_upwinding` equal to `edmfx_tracer_upwinding`.
    They are refused otherwise.
  - **Added in WP3, after the review:** the copies take the updraft's share
    of the surface moisture flux by region and source (the fifth mirror,
    FINDINGS W20). The default mode's plume starts at level 1 from the grid
    mean's composition and has no counterpart. So `evap` in the updraft can
    differ severalfold between the modes near the surface. By the reviewer's
    estimate, fresh surface water is 0.3 to 1% of the updraft's water at
    level 1, and `evap` holds about 1% of the column in the first hour. This
    alone could fail the first-hour source-tag budget. V-W3 measures it. The
    owner decides whether the plume's start should model it. *Open
    (DECISIONS.md, "Waiting for the owner").*
    *Scope added (provenance pathway, 2026-09-26; revised after the owner's
    review):* PX13 would compare the three admissible surface treatments. If
    they spread by more than the first-hour source row, first-hour `evap` is
    convention-sensitive and the claim is narrowed. PX13 and a surface rule
    that composes the flux (PP-SFC) are deferred until the owner takes up
    this rule, or PX11's surface floor fails.

### 4.2 The `q_tot_eff` leaks under 1M

Under 1M, the parent's diffusion, hyperdiffusion and sponge act on
`q_tot − q_rai − q_sno`, while the tags act on their whole value. The paths
are:

  - grid-scale vertical diffusion;
  - grid-scale hyperdiffusion;
  - the viscous sponge;
  - the updraft's diffusion mirror;
  - the updraft's hyperdiffusion;
  - on the sphere only, the horizontal SGS diffusive flux
    (`edmfx_sgs_flux.jl:444-595`), found by WP0's check of the merged code. A
    column has no horizontal gradient, so V-W0c cannot size it.

**Without the rain and snow tags,** each leak is corrected by subtracting the
tag's precipitation part: `ρq_tagₜ −= ∇·(ρK ∇(ψᵢ q_p))` per species. `ψᵢ` is
the same composition the sedimentation mirror uses, and the sign is minus. A
1-D check gives 6e-15 with minus and 0.125 with plus, against 0.062 today.

**With the rain and snow tags** (4.5), a tag's diffusing water is known
exactly as its non-precipitating part. The correction then uses that part and
is exact.

Before any correction is written, an exact diagnostic of each path's leak,
computed from the state in closed form, sizes it on D4-W and on the sphere.
V-W0c's estimate for the grid-scale vertical diffusion on D4-W is 0.9% of the
column's water a day (FINDINGS W18). That is a source on the closed manifold,
estimated from hourly samples before the follower existed.

*Rev. 2 (2026-09-24) replaces the rule that a path gets its correction when
its leak exceeds a tenth of the closure budget, and the conclusion that D4-W
can pass only with the correction or the rain and snow tags.* The follower
already closes D4-W: 1.5e-4 of the water in a day with one Newton iteration
(W24), and 7.3e-6 with the sedimentation cross blocks (W31). So whether a
distinct remainder exists after the follower is not measured. And a
correction's value may lie in attribution rather than closure. The follower
compares the partition with the parent's whole implicit increment, so it may
absorb column-neutral parts of several operator mismatches; that is an
inference, not a measured decomposition.

**The entry gate for WP4c.** On one parent state, for each operator, measure
the source before the follower, the residual's actual growth, the follower's
correction and the remainder after it. A correction is retained if it:

 1. leaves a remainder after the follower;
 2. cuts the follower's share of that operator's transfer by more than the
    intervention threshold (OD3); or
 3. changes per-tag provenance by more than the provenance threshold (OD3).

A correction retained only under 3 becomes a default only with an eligible
comparator or a documented mechanistic argument for its attribution, for
example charging the 1M leak to the tags whose condensate leaked. The rest are
deferred with their decomposition numbers, not deleted.

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* part 3 accumulates its difference per cell and step without feedback,
and reports the net. So it is a first-order estimate of an observed spread
between two rules that both close. It is not a bound, and its ratio to part 2b
is not evidence for the exposure inequality. PX2 would give the realized value
from W38's run and V1. It is deferred until OD11 lists ψ as admissible, or PX7
finds the follower's work structural.

### 4.3 Following the parent's increment (WP5)

The parent's SGS water flux has Jacobian blocks. The tags' donor flux, their
exchange and the copies' flux have none. So with one Newton iteration the tags
take the flux at the stage's first guess, while the parent takes the solved
one. That is E59's mechanism. Default and copies both lag in the same way, so
comparing them cannot show it.

Hence:

  - **V-W3 includes a 10-Newton twin of each mode** (E64's split). The
    one-iteration part of the gross residual is the default run's residual
    minus its twin's.
  - **The rule, fixed now:** if that part exceeds a quarter of the closure
    budget, the follower becomes the default transport under EDMF.
  - **WP5 is built right after WP3 and before WP4,** whatever V-W3 shows, since
    the energy family's production run already follows the increment. The rule
    decides only the default.
  - The follower is the key `water_tag_transport: increment`. After each Newton
    solve the tags take the parent's increment of `ρq_tot`. The part that
    changes a column's total stays out of the tags, with ledgers
    `q_tag_inc_left` and `q_tag_inc_moved`. *Added 2026-09-24 (the review of
    #102):* so the follower never changes the partition's column total, and a
    lag in the surface outflow stays in the net residual; the part left out is
    spread by `|m|` and its profile does not show where it arose.
  - The tags' explicit vertical advection is then skipped, as `advection.jl:257`
    does for the energy tags. Otherwise it would count twice.
  - Its post-solve hook composes with `EnergySourceIncrementCorrection` in one
    hook. It reuses the stepper check. ARS222 passes it in practice, since
    D4's increment runs used it, but no test asserts that; WP5 adds one.
  - **Known issue 4 is not claimed as fixed.** The parent's 0M sink has no
    Jacobian block either, so parent and tags take it at the same iterate. It
    also changes the column's total, which the follower leaves in place.
    V-W0a restates or closes that issue.

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* the follower's moved part is an assumed rule. PX7, the pathway's gate
C, splits it into lag, which enters the numerical error `F`, and structure,
which is a convention reported with its observed spread. Neither branch
validates it. PX3 would measure the placement's effect on composition (W24
against W28); it is deferred until the owner takes up OD7. The exposure screen's
premises are in the pathway's section 3.

### 4.4 Precipitation provenance under 0M (WP4a)

The sink is split by subdomain in both tendency paths, implicit and explicit
microphysics:

  - production is `Σₖ max(Δᵏ, 0)` by mask;
  - loss is `Σₖ min(Δᵏ, 0) φᵏ`.

Here `Δʲ = ρaʲ dq_tot_dtʲ`, and `Δ⁰` is the environment's term weighted by
`ρa⁰` as `tendency.jl:109-117` builds it, not a remainder. `φʲ` is the bounded
plume share (default) or the copies' share, and `φ⁰` follows from the bounded
exchange's environment. The tags then sum to `Δ` even where the parts differ
in sign. `pr_tag_<name>` is the column integral of each tag's loss.

### 4.5 Rain and snow carry their own tags (WP4b)

**The principle.** Each tag gets rain and snow parts that partition `ρq_rai`
and `ρq_sno`. Falling water then carries the composition it had where it
formed, not that of each cell it passes. Cloud liquid and ice carry the
composition of the non-precipitating water of their subdomain. They sediment
slowly and form locally.

**The central choice, for the design note (WP4b-D):** which fields are
prognostic.

  - **Recommended:** non-precipitating, rain and snow parts, `ρq_tag_<name>`,
    `ρq_rtag_<name>` and `ρq_stag_<name>`, with the total water per tag derived
    for output. Then:
      + each part's sedimentation is linear in the part itself;
      + its Jacobian diagonal is the parent species', with no share derivative;
      + the tags stay split-solvable;
      + the non-precipitating part diffuses exactly as the parent's `q_tot_eff`;
      + the leaks of 4.2 vanish by construction.
  - **The cost of that choice:** with the key on, `ρq_tag_<name>` changes
    meaning, from total to non-precipitating water. The key is therefore
    opt-in, `water_tag_precipitation: true`, 1M only. Its restart guard refuses
    a change, and output still offers `q_tag_<name>` as the total.
  - **The alternative:** keep the total prognostic and add the rain and snow
    parts. That needs off-diagonal blocks between a tag's fields under stiff
    sedimentation (rain Courant number about 12 on D4). Or it lags them.

**Microphysics attribution.** 1M exposes only the net tendency of each species
per subdomain. So the three compartments exchange by the net-flow donor rule.

  - Non-precipitating water `N` (vapour and cloud), rain `R` and snow `S` have
    net changes `ΔN = −ΔR − ΔS`.
  - A compartment that loses gives its own composition.
  - A compartment that gains receives the losers' compositions, weighted by
    their losses.

This is exact when the flows in a cell and a step go one way, and an
approximation otherwise. An example is rain that forms and evaporates in the
same cell and step. **An audit bounds the error.** On a column, it recomputes
the gross process rates offline with CloudMicrophysics' individual 1M
functions from saved states: autoconversion, accretion, evaporation,
deposition and melting. It then compares that attribution with the net-flow
one. The environment's sub-grid quadrature makes the audit approximate there;
the design note states how.

**Every operator that moves the parent's rain and snow is mirrored,** with the
parent's coefficients. The list is verified in the design note:

  - grid-scale advection;
  - vertical diffusion (`α = 0`, `K_e` only, under EDMF);
  - *corrected 2026-09-24 (WP4b-D):* not hyperdiffusion and not the viscous
    sponge, which leave rain and snow alone (`hyperdiffusion.jl:531-544`,
    `viscous_sponge.jl:224-229`); the Rayleigh sponge on the updraft's species
    and DSS, which were missing;
  - the SGS mass flux, since the species have updraft copies;
  - sedimentation, grid-mean and updraft;
  - microphysics;
  - the limiters and state constraints (rescale and repair per compartment);
  - the filter.

**Under EDMF:**

  - **In the default mode** the rain and snow parts are grid-scale. The
    updraft's rain and snow take the composition of the updraft's
    non-precipitating water from the plume, since they formed there. The
    environment's follow by subtraction, bounded as in the exchange.
    Sedimentation uses the parent's own flux split by subdomain,
    `ρʲaʲwʲqʲ` and the rest. The review showed that mass weighting gets this
    wrong when updraft rain falls faster.
  - **In copies mode** the rain and snow parts have copies too. That is three
    copies per tag.

**Output:** `pr_tag_<name>`, the bottom-face flux of the tag's rain and snow
parts plus its cloud species' flux. `Σᵢ pr_tagᵢ = pr` is checked.

**The design note WP4b-D** fixes the fields, the operator list with file:line
references, the attribution, the Jacobian entries, the scratch the tags own,
the audit's method and the cost. The `clima-numerics-reviewer` (xhigh)
reviews it before any code. Implementation is staged:

 1. a 1M column without EDMF;
 2. EDMF in the default mode;
 3. copies.

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* PX14 would replay the pool rule and the sedimentation reset with
sub-steps, in `PrecipitatingColumn`'s rain-out window only. It is deferred until
WP4b moves toward validation. Until stage 2, WP4b is refused under EDMF, so the
production envelope keeps the reset.

*Scope added (provenance pathway, 2026-09-27, from the owner's review of #121,
pending OD15):* stage 1 attributes by the gross flows, so the audit now holds
the net-flow rule's difference from them. That is an observed spread between
two rules, not a bound on the pool's error. PX14 is the pool's reference.
PX25 reports the audit on two scales: the gross microphysical transfer, and
the rain or snow mass or each tag's precipitation. It also records each
compartment's residual under both transports, both upwinding schemes and
several time steps. The review's sub-step-resolved reference test (item 4)
and a horizontally varying operator test (item 6) were added to #121 in
`00b4ecf`. #121's commit `3681fc2` reports item 4's test file passing on the
login node, and `835ff9a` item 6's sphere passing. Neither is in FINDINGS.md,
so they are tests, not results.

### 4.6 Shared code (WP2), after the water design has settled

The water helpers are written for water first, in WP3 to WP4b. After V-W3 and
V-W5, only the identical parts move into shared code: `ShareDifferences` with
a weight argument, the partition flags and the face flux. A CI unit test runs
the old and new helpers side by side on random inputs, bit for bit. The
energy tags' reference is a run of the merged `main` with decision 5, not
E73's outputs.

### 4.7 Restart

No restart guard exists for `water_tracers` today. `restart.jl` checks the
energy families and `water_process_record` only (WP0's check of the merged
code). WP3 builds one, on the energy guard's model. It checks the water tags,
the copies, the rain and snow parts and their copies, and refuses:

  - missing or extra copies;
  - a changed switch;
  - a changed `water_tag_precipitation`.

The rebuild uses `q_totʲ φ̄ᵢ` (4.1). The ledgers restart at zero, with segment
metadata (WP6).

### 4.8 Refusals

  - **WP1, now:**
      + Refuse `water_tracers` with `prognostic_edmfx` until WP3 lands.
      + Refuse them with the AMD LES model always.
      + Warn under `PrescribedFlow`.
      + `water_process_record` is not refused: the records are not transported.
        `check_water_tagging_supported` serves both families, so these
        refusals get a check of their own.
      + Reserve the tag names that collide with diagnostics: `res`, `fix_*`,
        `upfix_*`, `inc_*`, `rtag_*`, `stag_*`.
  - **After WP3:**
      + Allow one updraft.
      + Refuse `updraft_number > 1`.
      + Refuse copies without prognostic EDMF, or with unequal updraft
        upwinding.
      + Refuse the exchange without region tags that partition the domain, as
        `check_energy_source_exchange_partition` does.
      + Refuse `water_tag_precipitation` without 1M.
  - Each refusal concerns only the diagnostic's own keys, and each has a test.

## 5. Work packages and their order

Historical implementation inventory: retain these dependencies and evidence,
but schedule remaining work through [ROADMAP](ROADMAP.md#the-execution-order).
The order and branch assignments recorded below are not new instructions
to recreate completed work or use the older experiment branch.

| WP     | What                                                                                                                                                                                                                                                                                                                                                                                                                                            | Kind              | Depends on   | Review       |
|:------ |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------- |:------------ |:------------ |
| WP0    | #95 merged with decision 5 (job session, owner). The phase-1 review. The verifier extended to `q_tag_*`, copies, rain and snow parts and `pr_tag_*`. Checks: the ERA5 forcing of V-W8 is on disk, and V-W2 can be set up. The sizing run V-W0c                                                                                                                                                                                                  | analysis          | —            | this session |
| WP1    | Refusals and reserved names (4.8). Known issue 1 closed with the post-#64 CI numbers; issue 3 updated. **Draft PR-W1**                                                                                                                                                                                                                                                                                                                          | model code, small | WP0          | Opus, high   |
| WP3    | Total water under EDMF (4.1): the switch; donor flux and exchange with the rescaled plume; copies with their four mirrors, rebuild and repair; restart guard; refusals lifted; bound activation in the audit; leak diagnostics (4.2); CI group `tagging_water_edmf` with the parity, manufactured-mixing and copies-against-tracer tests. **Draft PR-W3**                                                                                       | model code        | WP1          | Opus, xhigh  |
| WP5    | The follower (4.3). **Draft PR-W5**                                                                                                                                                                                                                                                                                                                                                                                                             | model code        | WP3          | Opus, xhigh  |
| WP4a   | The 0M split (4.4) and `pr_tag` under 0M. **Draft PR-W4a**                                                                                                                                                                                                                                                                                                                                                                                      | model code        | WP5          | Opus, xhigh  |
| WP4b-D | Design note for rain and snow tags (4.5)                                                                                                                                                                                                                                                                                                                                                                                                        | design            | WP3          | Opus, xhigh  |
| WP4b   | Rain and snow tags in three stages (4.5), with the audit script. **Draft PR-W4b**                                                                                                                                                                                                                                                                                                                                                               | model code        | WP4b-D, WP4a | Opus, xhigh  |
| WP4c   | The leak corrections that 4.2's rule selects, for runs without rain and snow tags. *Scope added (rev. 2):* 4.2's operator decomposition is the entry gate, with the three-part retention rule; corrections not retained are deferred, not deleted                                                                                                                                                                                               | model code        | V-W0c, V-W3  | with WP4b    |
| WP6    | Gross accumulators for both families: absolute repair and fix throughput with event counts, per-step `\|m_left\|`, attempted against retained, restart segments. **Draft PR-W6**. *Scope added (rev. 2):* step 3 before the sphere and the default decisions: accepted-step gross throughput, attempted against retained transfer, event counts, restart stitching, validity by cadence, and each tag's cumulative correction against its water | model code        | WP0          | Opus, high   |
| WP2    | Shared helpers, only the identical parts (4.6)                                                                                                                                                                                                                                                                                                                                                                                                  | refactor          | V-W3, V-W5   | Opus, xhigh  |
| WP8    | Docs: `tagged_water.md` (EDMF, precipitation, the corrected operator claim), the claim contract, `known_issues.md`, NEWS                                                                                                                                                                                                                                                                                                                        | docs              | WP4b         | Opus, high   |
| WP9    | Cost for both families (V-W10). *Scope added (rev. 2):* the audit-feasibility decision (OD8) comes early, before WP5b-C and G4.1/G4.11; then build time, peak memory and per-step scaling at the intended tag count for the default and the comparator, the aggregation test and the sphere's run-length budget                                                                                                                                 | benchmarks        | WP4b         | this session |

Order:

 1. WP0, then WP1.
 2. WP3 with its CI group.
 3. V-W1 to V-W3, which fix WP5's default.
 4. WP5, then WP4a.
 5. WP4b-D, then WP4b, with WP4c beside it.
 6. WP2, WP8 and WP9, before the sphere.

WP6 runs in parallel from WP0 on.

*Rev. 2 (2026-09-24)* reorders what is left, with the decisions each step
needs: WP6 step 3; then W25's isolation (OD1 to OD3) beside the audit
feasibility (OD8); WP5b-C at OD8's tag counts; WP5b-V's remaining arms; WP4c's
gate; WP4b; WP9's cost qualification; the sphere (OD6). The full order, with
G4's, is in ROADMAP.md, "The execution order".

**Branches:** model code on `claude/water-tags-edmf` from `main`, with
worktree `../ClimaAtmosResiDyn-wedmf` and run worktree
`../ClimaAtmosResiDyn-wedmf-run`. Experiments, configs and analysis stay on
`claude/tag-closure-record` (until 2026-09-23 `claude/g3-programme`, now retired).

## 6. Experiments

All runs are stamped with the manifest and compared with the verifier.
**D4-W** is D4 (DYCOMS RF02, prognostic EDMF, one updraft, 1M, 30 levels,
dt 120 s, one day, Float64), but with water tags instead of energy tags and
`edmfx_vertical_diffusion: true`, as every shipped EDMF column and the sphere
set it. Its tags:

  - region tags `tropo` and `strat`, below and above 750 m;
  - `evap` (`surface_flux`), `evap_tropo` and `evap_strat`;
  - the passive tracer.

The identity `evap_tropo + evap_strat = evap` is not exact under decision 5,
nor where the copies' filter binds. Bound activation is logged per source tag,
so a violation can be traced.

*Scope added (provenance pathway, 2026-09-26):* D4-W subsides, with DYCOMS's
`w = −3.75e-6 z`. Both modes reach the tags' subsidence through the same
bracket, so their comparison cannot see it (PX1, PX8). The identity above is
also weak where `evap_tropo` and `evap_strat` are fed by fixed masks. Then
they are constant multiples of `evap`, except where a source tag's own θ
binds or the repair acts, and proportionality is the invariant to check
(PX4, deferred until a Fid-1 label is reported).

**The deep 0M development case** is TRMM_LBA with 0M, 3 h. The held-out set of
criterion 8 is separate.

| Run   | What it decides                                                                                                                                                                                                                                                                                                                                                                  | Jobs     | Needs      |
|:----- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------- |:---------- |
| V-W0a | Known issue 4: a precipitating 0M column without EDMF, 1 against 10 Newton iterations. Closes or restates the issue                                                                                                                                                                                                                                                              | 2        | WP0        |
| V-W0c | Sizing before WP3's details are fixed: one untagged D4-W day with EDMF diagnostics. The updraft's share of rain and snow, the surface excess `C√σ²`, and the five 1M leaks in closed form                                                                                                                                                                                        | 1        | WP0        |
| V-W1  | "Before": D4-W with grid-scale tags on `main` + #95, before WP1's refusal, plus the untagged twin                                                                                                                                                                                                                                                                                | 2        | WP0        |
| V-W3  | D4-W, default against copies on one atmosphere, 1 to 24 h; each with a 10-Newton twin; bound activation; a surface pulse. The TRMM 0M development case, default against copies                                                                                                                                                                                                   | 8        | WP3        |
| V-W4  | The ladder, default and copies at each rung: dt 60 and 30; Newton 2, 4 and 10; 60 and 120 levels; first-order upwinding. The copies' own convergence is read from the same runs                                                                                                                                                                                                  | 18       | V-W3, WP5  |
| V-W5  | Precipitation: the 0M split on and off (TRMM development case, both modes). Rain and snow tags on and off on a 1M column without EDMF and on D4-W (both modes). The net-flow audit on the column. `Σ pr_tag = pr`                                                                                                                                                                | 10       | WP4a, WP4b |
| V-W6  | Held out, default and copies each: RICO 1M (24 h), BOMEX (`bomex_column`, dt 120 s, 6 h, with the passive tracer), ARM SGP 1M (1 day), GCM-driven 0M (6 h)                                                                                                                                                                                                                       | 8        | V-W5       |
| V-W7  | Float32 twin of D4-W                                                                                                                                                                                                                                                                                                                                                             | 1        | V-W5       |
| V-W8  | A file-based column with water and energy tags: `prognostic_edmfx_gcmdriven_column` (0M, the GCM start from site 23) for 3 h. Its forcing, the `cfsite_gcm_forcing` artifact, downloads through the package manager and was fetched on 2026-09-23. The owner chose it over the ERA5 column, whose forcing is not downloadable                                                    | 1        | WP3        |
| V-W9  | Restart round trips: D4-W in both modes, and with rain and snow tags                                                                                                                                                                                                                                                                                                             | 4        | WP4b       |
| V-W10 | Cost: 2, 4, 8 and 32 tags where they build in time, both modes, with and without rain and snow tags, both families. *2026-09-24 (OD8):* qualification is at 8 tags; 32 is a cost item only                                                                                                                                                                                       | about 14 | WP4b       |
| V-W11 | The sphere: `g2_v2_sphere_n2` with water tags and rain and snow tags under the chosen default, 10 days, 24 ranks (about 16.5 h and 500 GB, as E75). *Superseded 2026-09-24 (OD1, OD6):* 90 days at 60 levels, with 8 water and 8 energy tags and the per-tag ledgers; its cost is ROADMAP.md's M4 estimate. A one-day copies twin. A restart after day 1. A two-rank parity pair | 5        | all above  |

That makes about 70 column-scale jobs and 5 sphere jobs. Column runs go to
`hpda2_test` where they fit in two hours, otherwise `hpda2_compute`.

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* the pathway's runs, by gate.

| Run  | What it decides                                                                                                                                                                                                                                                                                                | Needs                                      |
|:---- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------ |
| V-P0 | Gate A and gate B's screen, no runs: PX0 (the archive) and PX1 (the subsidence screen)                                                                                                                                                                                                                         | step 1b                                    |
| V-P1 | Gates B to E, existing keys: PX8 after PX1, whatever PX1 finds; PX7 (the follower's lag or structure); PX24 and PX11 (the clean label benchmark and its per-tag accounting), then PX23 (one held-out case, not assessable until an independent case and its reference are fixed); PX22 (energy at a fixed `c`) | OD11, OD12, OD14                           |
| V-P2 | Gate B's probe PR: PX16 with PP-SUB, only if PX8 is material                                                                                                                                                                                                                                                   | OD13                                       |
| V-P3 | Deferred until a measured result needs them: PX2 to PX6, PX9, PX10, PX12 to PX15, PX17 to PX21 and the other probe PRs; *PX25, added 2026-09-27 (provenance pathway, from the owner's review of #121)*                                                                                                         | their triggers (the pathway's section 7.2) |

*Scope added (provenance pathway, 2026-09-27, from the check of PR #122,
comment 5857451675):* PX25 (V-P3) is not in the V-W table's total of about 70
column-scale jobs, and no approved budget counts its jobs. Step 8's cost
ceilings bound the model's cost, not a job count. Counted from its arms in the
pathway, PX25 has 24 jobs per case, 16 tagged arms and 8 untagged twins. With
a second case it has 48. Its column runs go to the same queues by the same
rule.

### 6.1 Budgets, fixed before the runs

*Rev. 2 (2026-09-24).* A result is no longer given one closure-oriented
verdict. It is reported with the acceptance contract's rows in ROADMAP.md, each
pass, fail or not assessable, with the water-specific thresholds below:

  - **Windows.** Startup or source pulse, established flow and long run are
    scored apart, with boundaries fixed per case before its first scored run
    (OD2). A 24-hour average does not excuse a failed first-hour process whose
    whole event happens then.
  - **Comparator eligibility first.** Before any default-against-copies
    judgment, the copies are checked in that run: their closure, their repair
    against 0.20% of the water a day, their Newton and time-step stability,
    and their mirrors and Jacobian terms. Where they fail, provenance is not
    assessable.
  - **Intervention.** The accepted-step repair and follower throughput and
    the per-tag cumulative correction against each tag's water (WP6 step 3)
    are reported beside closure. Their thresholds are OD3's. *Set on
    2026-09-24:* the per-tag ledgers are on in every validation and
    qualification run, though off by default. The fraction uses the tag's
    current inventory, and the absolute amount is reported beside it.

**Set by the owner on 2026-09-23**, before any G3 run. Two parts are set
later, in the form fixed here: the sphere's numbers before V-W11, and the
default mode's cost budget after V-W10's first measurements. The measures are
those of `analysis/increment/tag_correctness.py`:

  - L1 is `∫ρ|Δq|dz / ∫ρ|q_ref|dz`;
  - L∞ is `max |Δq| / max |q_ref|`, normalised by the peak.

The verifier computes both (WP0).

  - **Per tag, default against copies, at 24 h:** L1 ≤ 2% and L∞ ≤ 5%. These
    are G1's criterion 4b for energy. E76 met them at every time step and
    Newton count, with 1.6% and 2.6% at worst. *Replaced 2026-09-26 at the
    owner's request (PR #122):* the row rests on G1's criterion 4b and OD3's
    approval, and it stands as approved. E66 is not a reason for it. E66's
    measured spread, 8% to 126% in L1 against a reference that keeps its own
    residual (E86), is reported apart from the row. The sentence replaced
    here cited E66 as a convention spread of about 1% in L1, which E66 does
    not support (see E66's annotation in FINDINGS).

  - **Per tag, in the first hour:** L1 ≤ 1% for the region tags and ≤ 10% for
    the source tags, and L∞ ≤ 25%. This is G1's split of 2026-09-20. It
    applies because the copies start from the plume. E76's first hour
    measured the copies' spin-up from the grid mean instead.

  - **Small tags.** A tag with less than 1% of the partition passes on its
    absolute error, `∫ρ|Δq|dz ≤ 2e-4 ∫ρq_tot dz`. Its relative error is
    reported. `evap` starts at zero, so its relative error is unstable early.

  - **Closure:** at 24 h the gross residual is at most 0.2% of `∫ρq_tot`. A
    residual `R` shifts the shares by about `R/ρq_tot`, so this is a tenth of
    the per-tag L1 budget. The second 12 h add no more than the first. WP5's
    rule (4.3) and the leak rule (4.2) use this budget.

  - **What the named parts leave:** at most 1e-6 of `∫ρq_tot` at 24 h. The
    named parts are the one-iteration part from the 10-Newton twin, the loss
    rule's flushing, the leaks and the ledgers. The 0.2% alone would pass a
    missed process worth 0.1% of the water. On D4's energy the same remainder
    was about 1e-8 (E64).

  - **The copies' own residual** is at most a tenth of the closure budget,
    0.02%. It holds by construction, so **their repair** is bounded too: over
    the day, `q_tag_upfix_*` moves at most 0.2% of `∫ρq_tot`. Beyond that the
    audit is flagged, since the repair then shapes it.
    *Note from WP3's review (2026-09-23), the numbers unchanged:* the residual
    does not hold by construction. It also carries the grid partition's
    residual, the Newton mismatch, the leaks and the rain-out's clamp
    (`review/agent_reviews/wp3_numerics_review_2026-09-23.md`, S5). The
    ledger is signed, so its size can understate what the repair moved.

  - **Convergence, as robustness** (criterion 6):

      + at every rung of V-W4, the default meets the per-tag budgets;
      + the copies' shares `q_tagᵢ/q_tot` move by less than 2% in L1 between
        the baseline and the finest rung of each ladder. The parent's own
        change is reported beside them, since each rung is a different
        atmosphere;
      + first-order upwinding is another scheme, not a refinement. It is
        reported and not judged (E76: 6.5% for `sfc`).

    The proposal this replaces, a quarter of the per-tag budget between
    rungs, would fail on E76's energy ladder: `sfc` goes from 0.53% to 1.36%
    between dt 60 and 30 s. W1 found the water residual flat in the time
    step, bounded by the limiter.

  - **Rain and snow:** in Float64, their closure against `ρq_rai` and
    `ρq_sno` within 1e-8 relative, and `Σ pr_tag = pr` within 1e-8 relative.
    Float32 comes under criterion 9. The net-flow audit is within 10% of each
    tag's precipitation over the day. It passes or fails on the 1M column
    without EDMF. Under EDMF it is reported, since the environment's
    quadrature makes the audit approximate there. A tag with less than 1% of
    the precipitation passes within 0.1% of the total. If the audit fails,
    the attribution is labelled approximate, and process rates are needed
    (section 8).

  - **Leak corrections:** *rev. 2* replaces "a path is corrected when its leak
    exceeds a tenth of the closure budget" with 4.2's entry gate and its
    three-part retention rule.

  - **The sphere.** The form is fixed now. Its numbers are set before V-W11.
    *Set on 2026-09-24 (OD6):* the sphere runs 90 days, to saturation, and is
    judged by the level observed, against a ceiling relative to the smallest
    analysed tag. The ceiling's value is drafted in ROADMAP.md's OD3 table,
    ~~pending approval~~ approved 2026-09-24 (the register).

      + At every output, `Σᵢ ρq_tagᵢ ≤ ρq_tot (1 + 1e-6)` at every point, and
        the non-positive fraction does not grow. Issue #64 went to 1e130 and
        still exited 0 (W6).
      + *Rev. 2 replaces "the gross residual plateaus after day 1".* The
        residual stays below an absolute ceiling set against the smallest tag
        that will be analysed, and meets a growth-rate or loss-timescale bound
        fixed beforehand (OD6). An example of such a bound: the end-of-run
        source rate times the longest flushing timescale stays below the
        ceiling. The reason: the two-Newton energy sphere grows from 2.77e-5
        at day 1 to 2.01e-4 at day 10, still slowing, and its loss rule
        flushes at 0.0105 to 0.0165 a day, 60 to 95 days (E74). Ten days is
        11 to 17% of that timescale *(derived)*. Take the residual's net
        growth over days 1 to 10, 1.9e-5 a day *(derived)*, as its source. If
        it held, the residual would level off near 1.2e-3 to 1.8e-3
        *(derived)*, 6 to 9 times the day-10 value. Adding back what the loss
        rule flushed over those days raises the source to about 2.1e-5 a day
        and the level to 1.3e-3 to 2.0e-3 *(derived)*. This does not predict
        the water sphere. It shows that a day-one plateau is not a general
        criterion.
      + The accepted-step repair and follower throughput, and each tag's
        drift, stay bounded, apart from the residual (OD3).
      + The run length is stated, and budgeted under M4 (OD6).
      + The one-day copies twin meets the per-tag budgets, where it passes
        comparator eligibility.
      + The restart carries the tags bit for bit.

  - **The default mode's cost:** a budget for step time and build time per
    tag. This session proposes it from V-W10's first measurements, and the
    owner sets it before V-W11. The copies are measured, not budgeted.

**How the budgets are read**, set by the owner on 2026-09-23 on the proposals
of the phase-1 tools review (`review/agent_reviews/phase1_tools_review_2026-09-23.md`,
R5 and R7). `w` is `ρ_ref Δz`, and `total_ref` is the reference's
`Σ q_tot w`.

  - A tag's share `S` of the partition is taken from the reference run at the
    same hour.
  - For a small tag, `S < 0.01`, the absolute test replaces both L1 and L∞.
    The relative numbers are still reported. A tag whose reference is zero
    at that hour counts as small.
  - A tag that is both a region and a source tag, such as `evap_tropo`, is
    judged as a source tag.
  - A non-finite value or a missing hour is a failure. The 6 h and 12 h
    outputs are reported, not judged.
  - The gross residual is `G(t) = Σ |q_tag_res| w / total_ref`. "The second
    12 h add no more than the first" means `G(24) − G(12) ≤ G(12) − G(0)`.
  - The remainder after the named parts is taken over a list of fields,
    since the parts' output names are fixed later.
  - The precipitation audit over the day needs averaged or accumulated
    precipitation output, not hourly samples. The D4-W configs write it from
    V-W3 on.

The copies' definitions (R8) and those of the rain and snow parts (R9) stay
proposals until WP3 and WP4b fix their fields.

A threshold is not changed after a failure without a recorded decision and a
new validation. If the default fails the per-tag budgets on a case, the
exchange is not accepted as the default there, and the options go to the
owner.

### 6.1.1 Water observables and accounting conventions (Part 2)

This specification applies to the proposed workflow in section 2.1 and to
the full G3 claims where their configurations activate a row. It uses the
approved numbers earlier in 6.1 and ROADMAP's OD3 table. The matrix below
references those rows instead of maintaining another numerical threshold
table. No six-hour origin tolerance, 0M precipitation tolerance, or
three-tag qualification has been approved by this documentation revision.

**State and weights.** Let `c` be a represented water compartment, `i` a tag,
and `P` the set of pure region tags. In the current implementation:

| Symbol / output       | Definition, units and location                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
|:--------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Q_T = ρq_tot`        | Total water density, kg m^-3, including vapour, cloud liquid/ice and precipitation when present. `q_tot = Q_T/ρ`. `hus` is this total, not vapour. See `compute_q_tag!` and comments in [`tagged_water_diagnostics.jl`](../../src/diagnostics/tagged_water_diagnostics.jl), and `set_implicit_precomputed_quantities!` in [`precomputed_quantities.jl`](../../src/cache/precomputed_quantities.jl). Under 1M its `q_liq` includes rain and `q_ice` includes snow. Under 0M they come from saturation adjustment and hold no precipitation. |
| `Q_N`, `Q_R`, `Q_S`   | Under the rain/snow key only: `Q_N = Q_T - ρq_rai - ρq_sno`, `Q_R = ρq_rai`, `Q_S = ρq_sno`, all kg m^-3. `Q_N` includes vapour and non-precipitating cloud condensate. See `water_tag_part_parent` in [`tagged_water_precipitation.jl`](../../src/parameterized_tendencies/tagged_tracers/tagged_water_precipitation.jl). These prognostic precipitation compartments do not exist in the proposed 0M case.                                                                                                                               |
| `X_i,c`               | Tagged water density in a compartment, kg m^-3. Without the rain/snow key `ρq_tag_i` tags `Q_T`. With it, `ρq_tag_i`, `ρq_rtag_i`, `ρq_stag_i` tag N/R/S. `q_tag_i` is total tagged water per unit mass, kg kg^-1. `q_ntag_i`, `q_rtag_i`, `q_stag_i` are the separate parts. `qv_tag_i` is a derived well-mixed phase allocation, not an independently transported vapour origin.                                                                                                                                                         |
| `Q_c+`, `Q_c-`, `r_c` | `Q_c+ = max(Q_c,0)`, `Q_c- = min(Q_c,0)`, `r_c = Q_c+ - Σ(i∈P) X_i,c`. `q_tag_res` is the total residual per unit mass. With separate parts also use `q_ntag_res`, `q_rtag_res`, `q_stag_res`. `q_tag_negative` is the sum of negative compartment parts per unit mass. See `water_partition_target`, `water_partition_negative_part` and the diagnostic compute functions.                                                                                                                                                                |
| `M(t)`, `T+(t)`       | Raw parent water `M = ∫Q_T dV`, and partition target `T+ = Σ_c ∫Q_c+ dV`, kg (kg m^-2 for a column normalized to unit horizontal area). Report both when they differ. `M` must be finite and positive for its normalized rows. The existing closure/audit scale is `T+`. The ledger parent scale is raw `M`. Never silently substitute one for the other when negative water occurs.                                                                                                                                                       |
| `I_i`, `B_i`          | Current signed inventory `I_i = Σ_c ∫X_i,c dV` and burden `B_i = Σ_c ∫abs(X_i,c) dV`, kg or column kg m^-2. Sum burdens of individual parts before cancellation. Source-labelled/signed tags use `B_i` in the approved intervention row. A pure region tag requires positive `I_i`.                                                                                                                                                                                                                                                        |

Integrals use the model's cell volumes and quadrature weights, summed across
MPI ranks once. The weight of cell l is `w_l = ρ_ref,l J_l`, with `J_l` its volume weight. On a column normalized to unit area `J_l = Δz_l`, so `w_l = ρ_ref,l Δz_l` in kg m^-2, as `compare_runs.py` uses. On the sphere `J_l` includes the horizontal area, and A is in kg. Take `Δz_l` from the actual faces, not from nominal `dz_bottom` or output-index spacing. `compare_runs.py` rebuilds the faces from the centres, which is exact where centres are face midpoints. `g3base_score.py`'s `thickness()` puts faces midway between centres, which is exact only on a uniform grid. A mean, an unweighted array sum and a mass
integral are different observables. Save coordinates, cell weights and the
choice of reference density in the evidence bundle. The model's Field
`sum` already integrates with its space weights. Do not multiply them again.

For a non-negative complete partition, summing **only `P`** recovers the
parent. More generally, pointwise to rounding,
`Q_T = Σ_c [Σ(i∈P) X_i,c + r_c + Q_c-]`. Keep the negative remainder visible
instead of saying that non-negative tags partition negative water. No such
sum identity applies to `evap` or overlapping source tags. Numerical
projection onto a partition can satisfy this identity with wrong origins.

**Balances and reference equations.** For an inventory over fixed domain D
and window `[a,b]`, use signed amounts in kg (or column kg m^-2):

```math
I_{i,c}(b)-I_{i,c}(a)
= S_{i,c}-O_{i,c}-\Phi_{i,c}
+\sum_{d\ne c}(F_{i,d\to c}-F_{i,c\to d})
+C_{i,c}+U_{i,c} .
```

`S` is external physical production, `O` local physical removal, `Φ` net
outward boundary transport, and `F` a directed internal transfer. Each is
integrated over the same domain/window using the solver's applied weights.
`C` is a signed numerical correction and `U` the unexplained discrepancy.
Count surface evaporation in `S` or `Φ`, once, and 0M rain-out in `O` or the
precipitation exit, once. Under 1M a transfer N→R/S conserves total water.
Sedimentation is boundary transport, not another external production.
Internal transfers cancel in the total across compartments, but per-tag
donor mistakes need not affect that total. For a known donor transfer of
amount `F_d→c`, the independent reference is
`F_i,d→c = F_d→c X_i,d/Q_d` under the declared well-mixed donor-pool model,
with the same amount removed from d and added to c. Use the actual donor,
not the receiving pool or the net sum of opposing transfers. Empty/negative
donors require an explicitly tested fallback and an invalidity flag, not an
invented composition. Parts 5/7 supply missing directed event measurements
and independently implemented references.

For an attributed local source or sink the declared tendency is
`dX_i/dt = M_i G - φ_i max(-Δ,0)`, with Δ the process's tendency of the parent, a **rate**,
`G = max(Δ,0)` where the relevant compartment is non-negative, zero below
zero under TargetGain, `M_i` its permitted source/region mask, and `φ_i` the
guarded share of what the tag holds. Loss reaches every tag. This equation does not represent
simultaneous gross production and loss when the applied-update event exposes only their net. The 0M EDMF microphysics path instead uses `Δ^j φ_i^j + Δ^0 φ_i^0`,
the signed rates of each subdomain with its own reconstructed/copy
composition. Copies have the documented source-tag environment gain
exception. See `attribute_tagged_ρq_tot!` / `TargetGain` in `tagged_water.jl`
and `add_split_rainout!` in
[`tagged_water_rainout.jl`](../../src/parameterized_tendencies/tagged_tracers/tagged_water_rainout.jl).
Shared use of these rules is not an independent test of their physical truth.

**Metrics, sampling and small denominators.**

| Metric / observable              | Computation, meaning, sampling and missing-data rule                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|:-------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inventory and profile origins    | `I_i` and spatial `q_tag_i(t)` from accepted-state outputs at matching physical times. For candidate versus eligible reference: `A_i = Σ_l w_l abs(q_i-q_ref,i)`, `L1_i = A_i/Σ_l w_l abs(q_ref,i)`, `L∞_i = max(abs(q_i-q_ref,i))/max(abs(q_ref,i))`. A is kg m^-2, the two relative errors dimensionless. The reference share is `S_i = Σ_l w_l q_ref,i / M_ref` at that same time. Apply 6.1's small-tag absolute rule, `A_i ≤ 2e-4 M_ref` where `S_i < 0.01`. It replaces both relative tests. A zero reference counts as small. Report undefined relative errors, never zero. Non-finite tag/reference, missing required time or mismatched labels/geometry is a data failure.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Closure                          | Signed net `N_r = Σ_c ∫r_c dV`, gross `A_r = Σ_c ∫abs(r_c) dV`. Report compartment grosses separately so cross-compartment cancellation is visible. The code's total `q_tag_res` gives only the gross of the summed residual under the rain/snow key, which may be smaller. It is not a substitute for individual-part residuals. The owner-approved legacy `G(t)` in 6.1's "How the budgets are read" is `Σ_l abs(q_tag_res) w_l / M_ref`, with **raw** reference water `M_ref = Σ_l q_tot,ref w_l`. Use the matching untagged parent as the accounting reference, whose equality to the tagged parent is independently checked. Existing closure/audit CSVs instead normalize by target T+. Recompute/convert using the recorded absolute residual and correct weights/M_ref, and report both denominators. Even a small negative remainder can change a near-threshold verdict. Preserve the approved total-residual score alongside separate-part gross diagnostics. Changing the scored observable needs an owner decision. 6.1 defines the 0/12/24 h growth rule and named-parts remainder. Endpoint/state residuals are not time-integrated correction activity.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Parent validity                  | Negative-water magnitude `N = -∫min(Q_T,0)dV`, positive M required for `N/M`. Record the online `negative_water_void` latch and the accepted-step negative-water amount/events as well as offline output checks. A last-step crossing must not be missed. With parts, also record each compartment's negative water. Temperature/floor/top-level checks and fixed-parent Newton one-step E use OD3 definitions. E is always reported.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Copies                           | `copy_residual` is `∫ρa^j abs(max(q_tot^j,0) - Σ(i∈P) χ_i^j) dV` before the **last repair**, normalized in the existing audit by its supplied target scale. The implementation uses the updraft's non-negative target. Report its raw negative remainder separately. Recompute the approved raw-parent denominator rather than silently adopting the audit's T+ scale. `q_tag_copy_res` is that cached pre-repair specific residual, not a current-state residual or a maximum across stages. Record cadence and evaluate eligibility at all required checks. Copy repair's signed cached `q_tag_upfix_i` cannot measure gross retained activity.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Numerical intervention           | For a cumulative **density ledger** L, signed window amount is `∫[L(b)-L(a)]dV`. Accepted-step retained activity is `H_L[a,b] = Σ(n in window) ∫abs(L_n-L_(n-1))dV`. The current `_retained` columns hold `H_L` from the run start, or from the start of a new segment after a legacy restart, so a window is `_retained(b) − _retained(a)`. `_attempted` counts all calls, including discarded stages. Under the rain/snow key a tag's `led_fix_<name>_attempted` also counts moves between its own parts. These are distinct from absolute amounts of every accepted applied correction/compartment leg, which Part 5 must measure to catch cancellations inside a step. Neither is an origin error or bound. Undo per-mass output with density at each endpoint before subtraction. Do not use one endpoint's density for both. Record fix, the correction after each solve (`led_inc`), rescale/empty/repair, uprepair/upfilter, negative-water allocations, bound/fallback events and attempted activity separately.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Intervention normalization       | Daily rates use `H_L[a,b] / M(b) × 86400/(b-a)` and report absolute H and a mean-parent reading beside the endpoint-parent reading. This describes the measured window. It predicts no full-day activity from six hours. Per-tag approved retained fractions use `H_fix,i[a,b]/I_i(b)` for a positive pure region inventory, or `/B_i(b)` for a source/signed tag. Report both plus parent fraction. Apply OD3's small-burden not-applicable disposition explicitly. A zero/non-positive denominator is undefined unless the approved applicability rule exempts it, never an automatic pass. Missing `_applicable`, burden or numerator is a data failure. `led_inc` is reported and judged through its existing refinement/retention gates.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Precipitation at output          | `pr` and `pr_tag_i` are upward-positive kg m^-2 s^-1. Physical downward precipitation is normally negative. Under 0M `water_tag_precipitation!` integrates the attributed rain-out rate at the output state, using the same vertical integration as parent `pr`. Its rain/snow diagnostic split is diagnostic phase information, not transported reservoirs. Under 1M with separate tags `water_tag_precipitation_flux!` uses the bottom-level sedimentation fluxes of the tag's rain and snow parts, plus its share of the non-precipitating water times the cloud liquid and ice fluxes. Define signed rate defect `D_p = pr - Σ(i∈P) pr_tag_i`, kg m^-2 s^-1, and report each source share separately. Zero/no-rain states require absolute defects, no division by zero or omission of a spurious tag flux.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Precipitation over a window      | The exact observable is the applied amount `P_i[a,b] = -Σ_n Δt_n Σ_s b_s p_i(n,s)`, kg m^-2, over accepted steps n. `b_s` are the weights of the tableau part that steps the 0M rain-out: `b_imp` under `implicit_microphysics: true` (the default and the TRMM pilot, ARS222 `b_imp ≈ (0, 0.707, 0.293)`), `b_exp` otherwise. `p_i(n,s)` is the column integral of the tendency the stepper applied at stage s, not the rate at the stage state. For an implicit stage it is the Newton-implied `(U_s − Û_s)/(Δt a_ss)`, which with a fixed Newton count differs from the evaluated rate and mixes every implicit process. No current output provides it. The parent budget's `impl.microphysics_removal_0m` row measures the parent's applied amount but refuses EDMF. Some weights are negative (ARS222 `b_exp ≈ (−0.707, 1.707, 0)`, ARS343 `b ≈ (0, 1.208, −0.644, 0.436)`), so a step can apply an upward amount while every stage rate is downward. Split signs per accepted step and cell, after weighting. Rejected evaluations count no applied amount. The current `reduction_time: average` is the mean of the step-end rates, a right-endpoint quadrature. A writer's interval average times its interval length is equivalent only if its sampling/weights represent that same applied flux. Otherwise report a diagnostic quadrature with its measured floor, not exact model precipitation. P is the signed downward amount: retain positive and negative contributions separately where subdomain terms can have both signs. Clipping the rate to downward-only silently changes the observable. Snapshot samples and trapezoids through hourly/half-hourly endpoints are not exact accepted precipitation. The current TRMM overlay averages parent `pr` only. It does not provide averaged `pr_tag_i`. This missing paired accumulation must be supplied in Parts 4/5 before a window-integrated claim. On a sphere multiply by area weights for kg. Per-tag attribution error is `abs(P_i-P_ref,i)/abs(P_ref,i)` where positive precipitation exists. Small/no-rain tags use the applicable approved absolute rule or an owner-fixed 0M rule. |
| Process-weighted origins / audit | For eligible donor shares, `D_i = Σ_e abs(F_e) abs(φ_i,e-φ_ref,i,e) / Σ_e abs(F_e)`. F is the applied process amount over this window, with spatial/time weights already included. It is dimensionless and uses OD3's process-weighted row. If total F is zero, report inactive/not applicable plus absolute defect. A nonzero transfer with a missing donor is not inactive. The 1M pool audit instead uses the approved per-tag precipitation scale and small-precipitation rule in 6.1. Under EDMF it is reported, as specified there. An audit sharing the pool rule tests accounting, not independent donor provenance.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Convergence / aggregation        | Report fixed-parent trial-step E and throughput ratios per time/Newton rung, plus full-run per-tag errors at each rung and the parent's change. Repaired output convergence alone is not reference convergence. Relative L∞ for aggregation compares the same named nested groups at matching time against their own group-run reference. Zero groups use absolute differences and do not manufacture a relative pass. OD8's aggregation row remains reported. It does not qualify three tags for eight.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Cost / reproducibility           | Build wall seconds, steady accepted-step wall seconds per step, peak memory per rank and total, tag count/modes/output settings and uncertainty, on matched hardware/software/process counts. Separate compilation, output/audit overhead and solve time. Archive immutable model and record SHAs, resolved YAML/TOML, Manifest, machine/MPI/precision, seed, checksums, scorer SHA, row results and restart segment IDs. These are required evidence, not scientific error estimates.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

**Restart and cadence.** Preserve tag definitions/compartments/masks/sources
and all accepted-step accumulators through a checkpoint. Current checkpoints
carry the cache signed `q_tag_fix_i`/`q_tag_upfix_i`, their gross twins/counts,
state ledgers and step-gross accumulators. Legacy checkpoints without the
cache accumulators restart them at zero with a warning and cannot by
themselves establish continuous-window accounting. Do not double-count the restored
ledger as a new event, reset a cumulative numerator to make a ratio pass, or
subtract endpoint values from different unaligned segments. Join continuous
segments using their recorded offsets and physical times. Require an exact
round trip and continuous-run/restarted-run comparison for the claimed
configuration and both claimed modes, including negative-water latch and
accumulator. The checks live in
[`water_tag_checkpoint.jl`](../../src/parameterized_tendencies/tagged_tracers/water_tag_checkpoint.jl)
and `restore_tag_ledger_checkpoint!` in
[`tag_throughput.jl`](../../src/parameterized_tendencies/tagged_tracers/tag_throughput.jl). The negative-water latch is written and restored in `tag_closure_checkpoint.jl`.
Use `update_constrain_state_every: step` for interpreting existing mechanism
retained grosses. Stage/DSS cadence is not the same applied measurement.
Record whether diagnostics are cached pre-repair, accepted endpoint,
interval average or accumulator. Never compare unlike conventions.

### 6.1.2 Water acceptance matrix (authoritative Part 2 specification)

Each row records configuration, observable/window, threshold citation,
reference eligibility, evidence and consequence. All rows inherit 6.1.1's
units, integration and restart conventions. The matrix routes the approved rows. Conditions it adds beyond the approved register were decided on 2026-10-07 (DECISIONS, WA-GATES): cancellation-safe leg accounting and initialization/fallback coverage are conditions, and material-rule coverage stays reported. Store separate verdicts for
startup/source-pulse, established flow and long run where the metric is
defined there. Obtain OD2's physical boundary from the untagged twin before
scoring. Use its approved sustained-tendency/pulse rule. Preserve the owner's
2026-10-02 **from-one-hour sensitivity row** beside the physical-window row.
If there is no established window, that row is not assessable, not the whole
run relabelled as established. A first-hour endpoint score does not replace
the startup exposure measurement. A day average cannot erase a failed pulse.

Verdicts are **pass**, **fail**, or **not assessable**, with a reason and
prerequisite. Use an explicit **not applicable** disposition only where the
approved rule or declared scope excludes a row. It is never a pass. OD3's per-tag intervention row (2026-09-25) is the approved source of this disposition. Preserve
reported-only results without turning them into either a pass or a required
test failure. Missing required data, non-finite input, an incomplete run or misaligned timestamps/labels **fails** the affected row and the reproducibility row (6.1, 2026-09-23: "a non-finite value or a missing hour is a failure"). Label it a data/execution failure, so that it is not read as a scientific negative result. A scientifically
invalid parent, ineligible reference, unresolved approval or inactive
comparison makes the affected scientific judgment **not assessable**, while
recording the failed prerequisite separately. An implementation crash is not
a scientific negative result. No scorer exit code alone establishes a pass.

| Row and applicable claim                                     | Observable and window                                                                                                                                                                 | Approved threshold / owner gate                                                                                                                                                               | Required reference and evidence                                                                                                                                                                                                                             | Failure or missing-work consequence                                                                                                                                                                                                                                                                |
|:------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scope, support and definitions — every claim                 | Section 2.1's resolved config, label model, compartments, exclusions and required outputs. Setup and full run.                                                                        | Existing support/refusal rules (4.8), and WA-SCOPE for a short three-tag qualified claim.                                                                                                     | `tracer_config.jl` guards, finite initial state, resolved config and claim declaration.                                                                                                                                                                     | Unsupported setup or mismatched definitions fails. Missing owner scope blocks qualification. Parts 2/4/9.                                                                                                                                                                                          |
| Parent parity — both candidate and copies                    | Every parent prognostic field and parent output, identical times/dtypes/geometry, throughout run and restart. Exact bit representation including signed zero.                         | Fork parity rule. Section 2 criterion 3 and OD3 "Parent validity: parity".                                                                                                                    | Matching untagged twins, same immutable model/Manifest/machine/MPI/solver. `g3base_score.py` R1 is output parity evidence, not a check of unwritten state fields.                                                                                           | Any parent difference fails and blocks the workflow claim. Parts 4/8/9/10. Broader MPI/solver scope stays in 12.                                                                                                                                                                                   |
| Parent physical/numerical validity — every claim             | Temperature floor/top-level change, raw negative-water N/M and persistent latch, fixed-parent one-step E. OD2 windows and whole run.                                                  | OD3 parent validity rows, including its 2026-09-25 E amendment. OD12 own-transport reference gate.                                                                                            | Offline profiles plus accepted-step latch/negative-water audit. Trial-step probes. R3/R2 supply only their actual sampled coverage. Copies/tracer/passive arms solving their own transport retain OD12's E gate. Diagnostic parity alone does not waive it. | A measured violation fails the prerequisite. Affected origin rows become not assessable. Missing accepted-step coverage is a data failure. Parts 4/5/6/8/9.                                                                                                                                        |
| Partition/compartment closure — every partition claim        | Net/gross residuals, absolute and normalized, individual compartments where present, and G(0), G(12), G(24) and named-parts remainder.                                                | 6.1 "Closure", "What the named parts leave", "Rain and snow", and OD6 for long sphere. W58's six-hour R4 pass stands as recorded. It is not criterion 4's 24-hour verdict and waives nothing. | Pure-region state outputs, parent raw/target scales, named ledgers and verifier. R4 and compartment diagnostics where available.                                                                                                                            | Closure failure fails accounting. A pass supplies no origin validation. Missing compartments/named parts go to Parts 4/5/8, and full sphere to 12.                                                                                                                                                 |
| Copies eligibility — required before comparison              | Pre-repair copies residual, retained repair rates in each window, stability at time/grid/Newton rungs, source mirrors/Jacobian and initialization/fallback coverage.                  | 6.1 copies residual/repair, OD3 "Comparator: refinement", and OD12 each reference floor.                                                                                                      | PX12 in this actual case/model/tag count, including KI4-COPIES/UP1 and per-rung E probes. Archive raw rates, parent scales, mirrors and convergence. R5 alone is insufficient.                                                                              | Any required reference check fails eligibility. Candidate origins are not assessable. No selecting the mode closest to a failed repaired comparator. Part 6, and missing accounting in 5. D4-W stays excluded under option D.                                                                      |
| Per-tag inventory origins — named active independent rules   | A_i, L1_i and L∞_i at the approved first-hour and 24-hour outputs, every tag/rung, and small-tag condition at each output.                                                            | 6.1 approved region/source/small-tag rules. Six-hour/three-tag qualified use waits for WA-SCOPE. No transplantation of endpoint tolerances.                                                   | Eligible PX12 for subgrid rules plus the independent active-rule coverage in 6.1.3. Same times/weights/masks. Verifier report per tag, not a worst-tag average.                                                                                             | Any required tag/time fails the scoped attribution claim. Ineligible reference makes it not assessable. Absent required output is a data failure. Parts 6/8/9/10.                                                                                                                                  |
| Process/donor origins — active transfers                     | Process-weighted D_i over startup/pulse and established windows, with absolute defect and transfer amount for zero/small denominators.                                                | OD3 "Provenance, process-weighted", and OD12 independence/floors. Missing coverage or new transfer metric needs a preregistered owner decision.                                               | Known donors or a faithful independently implemented operator. PX11/PX24 test transport only, PX12 subgrid only, Part 7 transfers. Save directed legs and donor composition.                                                                                | Shared-rule agreement is accounted-only. Wrong donor fails the tested rule. Zero activity proves no transfer accuracy. Parts 5/6/7/9.                                                                                                                                                              |
| Numerical intervention — every claim                         | H_fix/H_repair, per-tag retained fractions, signed net, attempted activity, absolute accepted applications/legs, event counts, fallbacks and bounds. Each OD2 window and sensitivity. | OD3 aggregate/per-tag/refinement rows with small-burden applicability and 2026-09-25 denominators. No new tolerance is applied to a different gross observable.                               | Current `tag_ledger_audit` / `tag_ledger_normalization` plus Part 5 cancellation-safe measurements. Report `led_inc` separately. Complete coverage is required even when historical retained ratios pass.                                                   | Threshold violation fails intervention. Incomplete cancellation/leg accounting blocks an accounted/qualified claim if the owner accepts WA-GATES (a). Until then it is a reported limitation. Signed or cell-step net cannot establish low total activity or an origin error bound. Parts 4/5/8/9. |
| 0M precipitation sum — reported accounting claim             | D_p and source fractions at all outputs, paired integrated P_i/P over physical windows when available, with no-rain absolute defects.                                                 | No approved 0M sum/attribution tolerance in `design/G3_BASELINE_RERUN.md` C7. WA-PRECIP owner rule before a scored claim. Do not borrow 1M's closure tolerance.                               | W58/C7 is instantaneous accounting only. Require both parent and tag interval averages/accepted accumulations and matching sign convention before window-integrated scoring.                                                                                | Report current evidence with its limitation. The window-integrated row is not assessable until Parts 4/5 supply the accumulation, which the current overlay does not request. A wrong sum is an accounting defect. An exact sum gives no origin pass. Parts 4/5/7/8.                               |
| Precipitation origins / rain-snow transfer — separate claim  | Each P_i against independent donor reference, compartment closure and pool audit over the day, and PX25 refinement outputs.                                                           | 6.1 rain/snow and small-precipitation audit rows. EDMF audit reported-only. OD15 at PX25 preregistration and WA-PRECIP for an additional 0M qualified use.                                    | Part 7 directed donor/phase/sedimentation references, PX14/PX25 with measured floors. Shared process-rate audit is accounting. Current rain/snow key refuses EDMF and copies. No presumed support.                                                          | Failed audit retains "approximate" attribution where the approved rule says so. Independent origin failure blocks the qualified precipitation claim. Stages 2/3, applicable Part 9 implementation and Part 12 remain open.                                                                         |
| Convergence / robustness — claimed inventory/reference       | All per-tag rows at every time/grid/Newton rung. Reference share movement, retained throughput ratios, fixed-parent trials, parent changes.                                           | 6.1 "Convergence, as robustness", OD3 refinement rows and OD12 floors. First-order upwinding is another scheme, reported.                                                                     | PX12/reference ladders and existing fixed-parent probes, with full-run differences separately labelled.                                                                                                                                                     | A required rung fails the corresponding claim or comparator. Repaired convergence is insufficient. Parts 6/8/9/10. D4-W criteria 5/6 excluded by option D.                                                                                                                                         |
| Aggregation — intended count                                 | Nested sums against their declared group-run reference at matched time, absolute error for zero group, and Float64 norm.                                                              | OD3 aggregation row, **reported**, OD8 direct eight-tag audit.                                                                                                                                | Explicit mapping of tag/group source masks and matched parents. A three-tag pilot cannot infer eight-tag behavior.                                                                                                                                          | Record departures and investigate. Never average away another failure or promote count scope. Parts 4/6/8/12.                                                                                                                                                                                      |
| Reproducibility / restart — every claim                      | Complete immutable provenance/evidence, exact checkpoint round trip and continuous vs segmented state/ledger/latch/accumulator comparison in both claimed modes.                      | Section 2 criteria 1/2/12, 4.7 and ROADMAP reproducibility row. Complete or fail.                                                                                                             | RUNS manifest/checksums and verifier, tag checkpoint schema and ledger restore. Score continuous windows without resets/double counting.                                                                                                                    | Missing required record or restart divergence fails reproducibility. No qualifying score. Parts 4/9/10, broader columns/sphere in 12.                                                                                                                                                              |
| Cost — every selected/qualified scope                        | Matched build/step/memory at claimed count, both modes and diagnostic settings, before default or expensive runs.                                                                     | OD3 cost rows and WP9 allocation gates at their stated intended count. Scope-specific cost/memory cap waits for owner if absent. OD6 sphere estimate is not a measured bound.                 | `design/WP9_COST.md`, independent timed pilot and hardware/software manifest. Criterion 10's recorded failure stands (E88's 8 + 8 step and OD3's copies row). W52 is the water half.                                                                        | Failure blocks default/production selection. Unmeasured cap is not assessable. Part 8 pilot/Part 9 fix/Part 10 scope, full eight-plus-eight cost and sphere in 12.                                                                                                                                 |
| Held-out evidence / qualification — declared operating range | Fixed independent case, window, metrics and eligible reference before tuning, and applicable inventory/precipitation rows without retuning.                                           | OD14 hygiene and section 2 criterion 8. WA-SCOPE specifies initial held-out requirement, does not waive it.                                                                                   | PX23 after PX11/PX24, suitable moist/transfer references for moist claims. TRMM/Soares/sites 23/26 are development cases. RICO eligibility requires OD14/OD15 scrutiny if used in PX25.                                                                     | Missing independent case/reference blocks applicable qualification. A failed held-out result cannot be tuned and called held-out again. Parts 6/7/10, and full approved list in 12.                                                                                                                |

**Overall decision.** Before qualification, record the claim's configuration,
tag count, interval, observable and required rows. An inventory-only scope
does not qualify precipitation. A Float64 column does not qualify Float32,
eight tags or a sphere. A scoped **qualified attribution** claim requires
approved scope/accuracy rules, pass in every required row at every required tag/time/rung, reproducibility, measured acceptable cost and applicable held-out evidence. Of Part 2's two further conditions (DECISIONS, WA-GATES, 2026-10-07), complete cancellation-safe accounting is a condition, delivered by part 5, and coverage of all material active rules stays reported until OD9 is decided. A failed required row cannot be
averaged away. A required not-assessable row blocks the claim.

OD5 is preserved: where provenance is not assessable, its specified Insight
10 tests can permit the historical verdict **"provenance bounded, not
validated"**. Report exactly which tests and thresholds passed. That verdict
is not independent validation, a mathematical error bound, or automatic
level 3/4 delivery qualification. Observed spread, correction activity and a
screen with an assumed amplification factor do not bound future origin error
without propagation assumptions and evidence. No wording change to OD5 is
adopted here. Part 2 can finish with pending owner choices. The affected
scientific claims then stay blocked.

### 6.1.3 References, independence and discriminating checks

OD12 permits a reference to validate only rules it does not share and that
are active in the case. Measure every excluded process as inactive rather
than infer inactivity from a configuration name. Record each floor (source
injection/surface, initialization, parent solve, contamination and reference
discretization) in the units/norm of the compared observable and demonstrate
the approved quarter-tolerance condition. A reference with no floor or
convergence evidence is not yet eligible. Its eligible tag count, time
window and code SHA are part of the claim, not repository-wide properties.

| Reference                                              | Independently tested mechanisms                                                                                                   | Shared assumptions/operators and exclusions                                                                                                                                                                                                  | Required floor/convergence evidence                                                                                                                                                                   |
|:------------------------------------------------------ |:--------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PX11 Soares air twin + PX24                            | Source-free resolved/subgrid transport rules named by the actual benchmark and passive-tracer construction.                       | Same parent and declared initial mask model. Only active rules implemented apart from tag rules count. No sinks, subsidence, sedimentation or precipitating moist EDMF qualification from a clean window.                                    | Per-tag process accounting first. Surface/injection/initialization/parent/contamination floors and tag/reference refinement. Missing-channel inventory precedes an inactive-rule declaration. Part 6. |
| PX12 TRMM 0M copies                                    | Plume, exchange and SGS-share treatment that copies implement independently of the candidate reconstruction, for this moist case. | Generic updraft transport and parent are shared. The attributed-process source rule, rain-out composition assumptions, corrections and other shared rules remain unvalidated. Passing copies total repair does not prove individual origins. | Grid and updraft residual/repair, mirrors/Jacobian, KI4-COPIES/UP1, E per rung, time/grid/Newton stability, start-composition and surface floors. Eligible at actual count/window. Part 6.            |
| Analytic/manufactured transport and mixing             | Exact solution of a declared tracer equation and known composition after linear mixing, label permutation and superposition.      | Verifies implementation/label arithmetic. It cannot validate unresolved moist physics or an assumed atmospheric mixing volume.                                                                                                               | Independent analytic/equation implementation, discretization order and dry/zero-state limits. Floors below the applicable approved rule. Reuse PX11/PX24 and existing manufactured tests. Part 6.     |
| Known-donor transfer / precipitation replay, PX14/PX25 | Directed transfers between distinct compositions, phase ownership and transport of the actual falling donor.                      | Prescribed parent rates/thermodynamics may be shared. An independently written donor calculation is needed. The same pool attribution applied twice is a shared-rule audit. Non-EDMF stage 1 does not validate EDMF stages 2/3.              | Known-answer event amounts, per-leg mass conservation, timestep/microphysics-substep refinement, small/no-precipitation absolute defects. OD15 before new scored refinement/pool rows. Part 7.        |
| D4-W copies                                            | No eligible origin judgment at production cost under option D.                                                                    | Repair fails. Do not replace eligibility by agreement or a repaired closure pass.                                                                                                                                                            | Keep parity, closure, Float32 and cost evidence. No copies-only fix or D4-W passive-tracer reference until the owner explicitly reopens it.                                                           |

The following are specifications for later discriminating tests, not new
experiments run by Part 2. Make each independent reference fail for a known
wrong origin while the parent's total remains unchanged:

  - Swap the `pbl`/`free` names or source mapping without changing their sum.
    The verifier must reject label mismatch, or show the per-tag wrong-origin
    error for a deliberately swapped solution. Part 4 data validation / Part 6.
  - Transfer a fixed positive amount from donor A to B with different tag
    compositions. Compare each leg to A's known composition. Repeat with two
    equal opposing transfers: zero net mass transfer does not mean zero origin
    exchange. Part 7. Directed gross accounting in Part 5.
  - Use an empty donor, an empty receiver and a negative compartment. Require
    declared fallback behavior, recorded invalidity, finite output and no
    fabricated origin pass. Zero activity alone is not validation. Parts 5/7.
  - Apply `+x` then `-x` to one tag inside an accepted step, and move water
    between its N/R/S parts while preserving its total. The signed and current
    cell-step ledger can close. Absolute accepted applications/legs must record
    the activity and independent donor evidence must detect wrong attribution.
    Part 5 accounting / Part 7 donor tests.

Keep three kinds of conclusion separate: **implementation verification**
against known equations, **validation of the declared label model** for
named active rules, and **real atmospheric provenance**. The last requires
evidence for the physical mixing/phase/donor assumptions and the intended
scientific application. Neither a passive-tracer identity nor a copies
comparison supplies it. State the model's uniform composition assumptions
and their untested processes beside every practical water-origin claim.

### 6.1.4 Tolerance rationale and unresolved scientific choices

Each threshold has three distinct statuses: **owner-approved operational
tolerance**, **measured numerical/reference floor**, and **use-specific
scientific accuracy requirement**. An approved number remains in force even
if the third rationale has not been demonstrated. A floor is measured for
the actual precision/reference/window, not inferred from a failed score.

| Approved source                                                         | Existing rationale and applicability                                                                                                                                    | Floor and scientific limitation                                                                                                                                                                                                                                                                                                                        |
|:----------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 6.1 per-tag first-hour/24-hour and small-tag rules, OD3 provenance rows | Inherited G1 operational criteria approved before G3 runs. It distinguishes region/source startup and avoids ill-conditioned relative scores for small tags.            | E66 did not justify a water accuracy tolerance. Retain its corrected record. OD12 floor checks are needed. Whether these errors are adequate for the intended origin inference is unestablished. WA-SCOPE must fix a use/interval/count, not merely accept a historically small difference.                                                            |
| 6.1 closure/named parts/copies residual, OD3 closure                    | Intended to keep partition discrepancy smaller than the operational per-tag allowance and expose missed channels.                                                       | A small closure residual bounds neither origin redistribution nor the sum of numerical activity. Compare numerical floors separately. Complete origin tests and cancellation-safe accounting remain required.                                                                                                                                          |
| OD3 comparator repair/refinement and intervention                       | Operational limits prevent a correction-shaped comparator or a large intervention from being mistaken for evidence. Approved denominators/window semantics still apply. | Signed and accepted-step net ledgers may cancel. Absolute applied-leg activity is an additional observable, not a silently revised tolerance. A cumulative origin error bound would require justified propagation. No such bound is established.                                                                                                       |
| OD3 process-weighted row and 6.1 precipitation audit                    | Tests actual process-weighted shares and a day-scale audit in its stated 1M/non-EDMF scope. EDMF audit is approximate and reported.                                     | The pool model and independent donor floor are still required. No approved 0M C7 threshold exists. OD15/WA-PRECIP decide additional application and zero/small-precipitation treatment before scoring.                                                                                                                                                 |
| OD3 refinement/aggregation                                              | Operational robustness, with full-run parent changes separated. Aggregation reported under OD8.                                                                         | Refinement is not physical truth and repair can enforce convergence. Reference discretization error must be below the applicable comparison tolerance, with sensitivity to the parent reported.                                                                                                                                                        |
| Criterion 9's owner rounding floor, `design/F32_TWIN.md` §10            | Limited Float32 precision-sensitivity criterion for accumulated criterion-4 measures.                                                                                   | Preserve `max(10 × Float64, 3 · eps32 · sqrt(n_steps))` with the existing accumulated measure and its actual step count. It does not relax origin rows, comparator eligibility, cost, parent validity or every Float32 field. W60's ten-iteration failure stands. W62 does not retrospectively rescore it or independently retest reused default data. |
| OD3 parent validity/cost, OD6 sphere ceiling                            | Numerical/physical trajectory screens and operational resource limits. The sphere level is observed over ninety days with growth reported.                              | Passing a screen is not physical validation of the model. Criterion 10's recorded cost failure stands (E88). M4's sphere estimate is a planning extrapolation. Actual memory/runtime pilot precedes expensive qualification. The residual/source/flush model is a diagnostic assumption, not residence time or a forecast bound.                       |

**Owner proposals are recorded in DECISIONS.md, decided 2026-10-07:** WA-SCOPE
(a qualified initial use, count/window and accuracy rationale), WA-PRECIP
(additional 0M precipitation acceptance), and any missing local cost/memory
cap. Prefer measuring the current pilot and the approved reference floors
first. Do not introduce a relaxed six-hour tolerance because W58's reported
`pbl` result lies just outside the 24-hour row. Retain OD7 and proposed
OD9–OD11, OD15 at PX25 preregistration, and all existing experimental/default
gates. No scientific default is selected by this contract.

### 6.1.5 Evidence implementation and Part 2 completion

Implement the **evidence**, in the existing parts, in this order:

 1. Part 4 inventories reusable post-#139 evidence and freezes config/labels,
    times/units/weights/scorer schema. Recompute headline values with the
    verifier. Fault-inject missing variable, truncated run, shifted time,
    signed zero and tag permutation as PX0 specifies. Do not trust a script's
    zero return code or fill missing ratios with zero.
 2. Part 5 supplies complete accepted applied-correction/compartment-leg
    activity, per-tag copy repair and event/fallback coverage beside current
    signed/cell-step retained and attempted measures. Add restart continuity
    and cancelling/opposing-leg checks. Preserve approved scoring semantics.
 3. Part 6 finishes PX11/PX24 and PX12's eligibility/floors. Preserve PX1→PX8
    even when the hourly screen is small. PP-SUB/PX16 retains OD13's trigger.
    Part 7 independently tests donor/precipitation mechanisms and resolves
    OD15's preregistration choices. Record inactive/shared/untested rules.
 4. Part 8 measures the integrated baseline, the dominant remaining origin
    error and actual cost. Part 9 makes only the targeted implementation
    corrections justified by that evidence. Part 10 qualifies the owner-fixed
    initial scope without held-out retuning. Part 12 retains the broader
    production, intended-count, precision and ninety-day obligations.

Known limits of existing tooling must be resolved before it scores this
matrix: `analysis/water/g3base_score.py` scored W58's six-hour R4/R5/R8 passes, hardcodes its TRMM intervention start at zero rather than
deriving OD2 windows, and reports R7/C7 only. Its R8 reconstructs inventory
from retained/fraction and can emit zero when the denominator is unavailable.
It also chooses the inventory fraction for every tag rather than enforcing
the source/signed burden rule. Missing verifier/CSV columns are sometimes
labelled not assessable where the new report must distinguish a data failure. It divides R4 and R8's aggregate by the closure CSV's `total`, the partition target T+, not raw M. Its `thickness()` is exact only on a uniform grid: 0.19% off for a water column on a 60-level stretched grid. The audit's `_relative` columns are over the audit scale T+, and they read zero where that scale is zero.
These limitations do not rewrite W58 or other historical findings. Part 4
must validate the actual denominators, window applicability and data states.
`cr_windows_score.py` and `f32_named_floor.py` supply their documented
window/precision readings only. Existing ledger and diagnostic fields do not
yet constitute complete directed origin reference coverage.

PR #146, if merged, changes rows here. A closing step brings each tag's rain
and snow parts to their compartment after the correction after each solve.
Their compartment closure then holds by construction and is no attribution
evidence. The PR adds the ledger `q_tag_led_close`, which the intervention row
must then include. It also reorders the rescale's legs, and under the
rain/snow key it changes the tags' hyperdiffusion. Re-read the closure,
intervention and precipitation-origin rows when it merges.

Part 2 is complete when the documentation defines every claimed observable,
equation, required matrix row, existing threshold source, reference gate,
owner choice and downstream evidence destination, proposes a value with its
rationale for each missing use-specific tolerance or records the owner's
deferral of it (ROADMAP, Part 2. Deferred 2026-10-07, under W62's rule), and independent review findings are resolved. This completion makes future acceptance decisions
reviewable once evidence/approvals exist. It does not certify water origins.
It changes no executable code, simulation, threshold or default.

## 7. Agents

Each runs at the reasoning level of its definition in `~/.claude/agents/`,
once a session has loaded them. Until then, `general-purpose` with the model
set. None submits jobs, pushes or merges. Reports go to
`review/agent_reviews/`.

| Task                                                                         | Agent                      | Model, effort  |
|:---------------------------------------------------------------------------- |:-------------------------- |:-------------- |
| Extend the verifier (WP0); comparison tables; the audit script's scaffolding | `clima-analysis-builder`   | Sonnet, medium |
| Review WP3, WP5, WP4a, WP4b-D, WP4b, WP2                                     | `clima-numerics-reviewer`  | Opus, xhigh    |
| Review WP1, WP6, WP8                                                         | `clima-reviewer`           | Opus, high     |
| Red team before the default and WP5's default are confirmed                  | `clima-numerics-reviewer`  | Opus, xhigh    |
| Hook inventory for the claim contract; operator list for WP4b-D              | `clima-inventory-explorer` | Sonnet, medium |

## 8. Risks and open questions

  - *Scope added (provenance pathway, 2026-09-26):* **common-mode references.**
    A reference cannot see a rule it shares, so agreement between the default
    and the copies says nothing about the grid-scale rules. **The exposure
    screen may exceed the row** on D4-W (the follower's part 2b alone is
    about 7.2% for `tropo`). A screen is not a bound, so this does not show
    an error above the row. **References have floors** and
    conventions of their own. **Classification gaming** is blocked by fixing
    OD11 before any score. **Run trees** differ between PRs.
    **`tracer_upwinding` also moves the 1M species,** so tracer-mode twins
    change the 1M parent. See the pathway's section 11.

  - **The tracer form lags under stiff implicit fluxes** (E59). The follower is
    built anyway (4.3). The rule decides only the default.

  - **The net-flow attribution between compartments** is exact only for
    one-way flows. The audit bounds it. If it fails its budget, process rates
    are needed. They exist only inside CloudMicrophysics' bulk tendencies, and
    recomputing them with the sub-grid quadrature is costly.

  - **Rain and snow tags must mirror every operator on the species.** One
    missed operator shows as a compartment closure error. Their tight budget
    (1e-8) is designed to catch it.

  - **Cost.** Rain and snow tags triple the fields per tag, and copies triple
    them again. At 32 tags the copies may not build within `hpda2_test`
    (E73 with its erratum: eight energy copies took the EDMF column's build from 600 s to 3504 s in separate cold jobs, about 5.8×; about 2× when built after the default in one process). They are the
    audit, not the default.

  - **Composition assumptions:**

      + cloud condensate carries the non-precipitating composition of its
        subdomain;
      + in the default mode, the updraft's rain carries the updraft's
        non-precipitating composition.

    Both are stated with every precipitation result.

  - **The steady plume**, rescaled to `q_totʲ`, is exact for proportional
    sinks. It is not exact for sharp fronts; bound activation measures how
    often those occur.

  - **The model keeps the updraft's precipitated mass on the implicit path**
    (section 3, last row). The copies follow `q_totʲ` and stay consistent with
    it. Documented, not ours to change.

  - **V-W8's forcing** is on scratch, in the Julia depot. Scratch is not
    durable; the package manager fetches it again if it goes.

  - **Nothing is sized yet.** V-W0c comes before WP3's details are fixed.

  - **Two families at once.** WP2 comes last, and bit-for-bit tag fields guard
    it.

## 9. G4, the energy source tags, with what G3 learns

*Scope added (provenance pathway, 2026-09-26):* what G4 takes from the pathway
is in [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md), section 10.

What transfers is structure and method, not accuracy. The weight differs
(`Aᵏ` with an offset, against `q_totᵏ`), and so do the sinks. The plume's
measured accuracy for water does not qualify it for energy.

  - **Carried over:**
      + the structure of the plume rescale (for energy, to the updraft's `Aʲ`);
      + one surface rule for both families: the grid mean's composition;
      + the per-subdomain split, for `precipitation` and for EDMF's sedimentation
        corrections;
      + the idea of compartments, for the energy that falling water carries;
      + the follower's composition with the water hook;
      + the qualified reconstruction settings, as starting points;
      + the gross accumulators and the cost results.
  - **Energy-specific, in G4:**
      + the offset sweep and U8;
      + headroom (U9);
      + the sign problem;
      + the enthalpy form and pressure work;
      + the subdomain energy mismatch;
      + the residual report;
      + warnings kept apart from acceptance, and U2's calibration;
      + the D4 process budget (synergy 6);
      + the R2 energy ladder of the job session;
      + held-out columns for energy;
      + the choice of the energy default;
      + the ten-day energy sphere.

## 10. Prior evidence on the old physics (2026-10-02)

Main is now `b34bbd8b`, and its model physics is upstream `a9287b2d`
(STATUS.md, "Update, 2026-10-02: physics baseline"). Every number below was
measured before that. Each keeps its commit label and counts as prior
evidence only. None of these is a threshold or baseline for a gated run until
a rerun on post-#139 `main` replaces it.

The reruns are tasks 5 and 7 of `agent-progress/goals-2026-10-02.md` (outside
the repository). Task 5 is WP9's cost (W52 and E88). Task 7 is the G3
baseline reruns, including W50's C. Task 7's design decides which of the
rows marked task 7 fit its 12 jobs. A row marked "none planned" has no rerun
in either task. The list was made from the owner's named findings and by
searching FINDINGS.md and ROADMAP.md for thresholds and baselines measured
on D4, D4-W, TRMM, the sphere and sites 23 and 26. It may not be complete.

| Label                                            | What it measured                                                                                                                          | Commit                                    | Replaced by                                                                                                                     |
|:------------------------------------------------ |:----------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------- |
| OD3's thresholds (ROADMAP, "The OD3 thresholds") | every numeric row, set 2026-09-23 and 24 and judged on D4-W, TRMM and column runs                                                         | `9085e264` to `705c8ed0`                  | task 7 re-scores each row its runs can reach; the cost rows go to task 5; the energy, aggregation and sphere rows: none planned |
| R5 (W38's rule)                                  | the copies' own repair against 0.20% a day on D4-W, 0.66% a day at 60 levels centred                                                      | `705c8ed0`                                | task 7 (W50's C and the D4-W copies reruns)                                                                                     |
| W17 to W51, parity claims                        | each tagged run bit for bit its twin, one claim per run                                                                                   | each run's own                            | none planned. Every run of tasks 5 and 7 checks parity again                                                                    |
| W21                                              | V-W3, D4-W for a day: per-tag budgets against the copies; the follower rule chosen at one Newton iteration; the copies' repair 0.6% a day | `9085e264`, `b5f40586`                    | task 7 (D4-W default and copies day)                                                                                            |
| W22                                              | GCM-driven column, site 23, 3 h: the water partition closes to 4.2e-4 gross                                                               | `837db55b`                                | none planned                                                                                                                    |
| W24                                              | the follower's D4-W closure, 1.5e-4 of the column in a day, 6e-10 with ten iterations                                                     | `9acb4956`                                | task 7 (D4-W follower day)                                                                                                      |
| W25                                              | the D4-W ladder at seven rungs: time step, Newton count, 60 and 120 levels, first order                                                   | `1db57be5`, `705c8ed0`                    | task 7, only the rungs its design takes                                                                                         |
| W26                                              | the 0M split on TRMM 0M for 6 h: tags move by at most 0.47%, `Σ pr_tag` within 1.8e-3 of `pr`                                             | `3a8f1c70`, `34f9a334`                    | task 7 if its design keeps criterion 7's TRMM 0M run; PX12 comes later                                                          |
| W28                                              | the same-sign rule on D4-W and TRMM 0M: the follower moves half the water, closes the partition to 4e-15 on TRMM 0M                       | `5d1afcc0`, `71bd4061`                    | task 7 (D4-W follower day)                                                                                                      |
| W32                                              | WP4a-V on TRMM 0M: the reconstruction's error against the copies' (`E_recon ≤ 0.75 E_grid`)                                               | on W26's runs                             | none planned                                                                                                                    |
| W33, W35                                         | TRMM 1M with explicit microphysics: closure 1.8e-6, the second Newton iteration's error ratio                                             | `2588623e`                                | none planned. The owner decides first whether W33's verdict changes                                                             |
| W34                                              | the plume's allocation at 8 and 32 tags, after the one-broadcast fix                                                                      | `bfd9ff08`                                | task 5                                                                                                                          |
| WP9's first pass (no finding yet)                | the cost at 2 to 32 tags, 19 of 30 points spread over 10%                                                                                 | `43b01ca1`                                | task 5 (W52 for water, E88 for energy)                                                                                          |
| W36, E81                                         | 90 days at sites 26 and 23: gross closure at rounding level at site 26, water tags ending the site 23 runs                                | `b01f926a`, `952d960d`                    | none planned                                                                                                                    |
| W38                                              | D4-W isolation, rules R1 to R8 at 30, 60 and 120 levels: closure, Newton error, comparator, refinement                                    | `705c8ed0`                                | task 7                                                                                                                          |
| W40                                              | WP4c's gate on D4-W at 30 levels: the 1M diffusion leak, 2.9% of the water a day                                                          | WP4c run tree (record, #109, #105, #112)  | none planned                                                                                                                    |
| W41                                              | the parent's Newton error at 60 levels, 1.9e-3 with four iterations against OD3's 1e-3                                                    | `705c8ed0`                                | task 7 (the Newton row)                                                                                                         |
| W42                                              | site 23 to day 90 under option C: V2 overshoot 2.2%, V5 2.03%                                                                             | `e6bab0fc`, `078c122c`                    | none planned. W49 replaced it                                                                                                   |
| W49                                              | option C's revision at sites 23 and 26 over 90 days: V5 fails at site 23 (`pbl` 7.3% against 2%)                                          | `b6d452b5` (model `0eb329b2`)             | none planned in tasks 5 and 7. The `led_fix` probe (W53) is the follow-up                                                       |
| W50                                              | W21's surface rule on D4-W: R5 fails (copies' repair 0.37% to 0.45% a day), first hour 13.1% against 14.3%                                | `04fa29fe` (fix), `a15e3d5e` (main)       | task 7 (W50's C: the 60-level copies day and its twin). PX12 (W50's B) follows                                                  |
| E73, E76                                         | D4's updraft exchange against the audit's copies: within 1% at 24 h, the ladder over time step and Newton count                           | `3ec098f1`, `dcf7d086`                    | none planned                                                                                                                    |
| E74, E75                                         | the sphere for ten days: gross closure 2.0e-4 of the scale, the updraft mixing's 10 to 19% shift                                          | `04d63916`, `846ef55d`                    | none planned. The sphere is OD6's                                                                                               |
| E84 (E83)                                        | the energy copies' repair on D4, 3.1% of the throughput a day against 0.20%; the exact throughput                                         | `df315dc4` (E83: `a5c9160c`)              | none planned. G4's levels come from post-#139 runs at G4's start                                                                |
| E86                                              | the energy records' closure verdicts on OD4's scale; the exchange's repair 7.3% a day on D4                                               | the runs of E62 to E84, mainly `df315dc4` | none planned. As E84                                                                                                            |
| E87                                              | G4.6's D4 process budget: the identity closes to 1e-6 J/m² a day, C4 not in the residual (A5 fails)                                       | `0164c2fd`                                | none planned. As E84                                                                                                            |
| E89                                              | the energy plume start on D4: closure 5.3e-14, `sfc` moves 7.3% at 1 h                                                                    | `10cdeebd` (fix), `43b01ca1` (main)       | none planned. As E84                                                                                                            |

## Review

The independent review of the draft, `review/agent_reviews/g3_water_plan_review.md`, and what changed:

| Finding                                               | Change                                                                                                                                            |
|:----------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------- |
| B1 copies miss the updraft's 1M sedimentation         | Mirror 2 in 4.1; section 1 states the assumption; section 3 row                                                                                   |
| B2 plume ignores the updraft's losses                 | Rescale to `q_totʲ` (4.1); risk corrected                                                                                                         |
| B3 `pr_tag` under 1M is the lowest cell's composition | Owner chose option b: rain and snow tags (4.5, WP4b-D, WP4b)                                                                                      |
| B4 WP5's rule is blind, and WP5 comes after WP4       | 10-Newton twins in V-W3; the rule fixed in 4.3; WP5 built before WP4; known issue 4 claim dropped; explicit advection skipped                     |
| S1 the repair counts the filter twice                 | Repair the residual, not the filter increment; output `r`; criterion 4                                                                            |
| S2 the surface rule                                   | The grid mean's composition as the relaxation target, the same for the plume and for both families; surface pulse in V-W3                         |
| S3 V-W2 ill posed                                     | A CI test at rounding, plus manufactured mixing tests (WP3)                                                                                       |
| S4 five leak paths, and the sign                      | All paths in section 3 and 4.2; minus sign; exact diagnostics; rule by threshold; exact with rain and snow tags                                   |
| S5 upwinding                                          | Copies refused unless the two settings agree                                                                                                      |
| S6 the 0M split                                       | Production and loss by subdomain; bounded shares; both paths (4.4)                                                                                |
| S7 ψ's weighting and Jacobian                         | ψ replaced by rain and snow tags; flux split by subdomain in the default mode; diagonal Jacobian                                                  |
| S8 budgets                                            | Closure tied to the per-tag budget; copies start from the plume; absolute errors for small tags; sphere budget before V-W11                       |
| S9 the reference's convergence                        | Criterion 6                                                                                                                                       |
| S10 `edmfx_vertical_diffusion`                        | True in D4-W                                                                                                                                      |
| S11 the process identity                              | `evap_strat` added; expected violations stated                                                                                                    |
| S12 `water_process_record`                            | Not refused                                                                                                                                       |
| S13 the rebuild of copies                             | `q_totʲ φ̄ᵢ` (4.1, 4.7)                                                                                                                           |
| S14 criteria for production                           | MPI pair, sphere restart, 0M EDMF and explicit microphysics parity, the copies' residual, `Σ pr_tag = pr`, refusal tests; GPU stated out of scope |
| S15 WP2 too early                                     | WP2 last, identical parts only, bitwise side-by-side test                                                                                         |
| S16 the development case                              | TRMM 0M, 3 h, in V-W3; held-out set separate                                                                                                      |
| N1–N13                                                | Taken up in sections 1, 3, 4.1, 4.3, 4.8, 6 and 8                                                                                                 |

The design of the rain and snow tags is new since the review, and has not
been reviewed. Its design note gets its own review, at xhigh, before any code
(WP4b-D).
