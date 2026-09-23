# G3 plan: water tags under EDMF

Final version of 2026-09-23. The draft (`f3ae8ca7`) was reviewed by an
independent agent (`review/agent_reviews/g3_water_plan_review.md`). Every
finding is handled here; the section "Review" at the end maps each to its
change. G3's to-do list, `G3_TODO.md`, follows this plan. Nothing in it has
been run.

## 0. Decisions this plan rests on

The owner decided on 2026-09-23:

 1. **G3 is the water tags under EDMF. G4 is the energy source tags**, and
    uses what G3 learns (section 9).
 2. The water tags are to become **operational in the production
    configuration**: a sphere with prognostic EDMF and 1M. So EDMF support is a
    correctness requirement for this family, not an extension. On the roadmap
    it moves out of M8 into M1 to M5.
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

| #  | Criterion                                                                                                                                                                                                                                                                                                                                                                                                         | Milestone |
|:-- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------- |
| 1  | Every G3 headline number is recomputed by the verifier from runs stamped with a manifest. The verifier covers `q_tag_*`, the copies, the rain and snow tags and `pr_tag_*`.                                                                                                                                                                                                                                       | M0        |
| 2  | Unsupported combinations are refused at configuration, with a test for each (4.8). Known issues 1, 3 and 4 are closed or restated. A file-based column starts with finite water tags. A checkpoint round trip holds in both modes, on the column and on the sphere.                                                                                                                                               | M1        |
| 3  | **Parity.** With water tags on, every model field is bit for bit that of the run without them, in both modes. Checked on the 1M EDMF column (D4-W), a 0M EDMF column, with implicit and explicit microphysics, and on two MPI ranks. The column checks run in CI.                                                                                                                                                 | M1        |
| 4  | **Closure.** On D4-W the water partition's gross residual at 24 h is within budget (6.1), and the second 12 h add no more than the first. What remains is split into named parts, and what the named parts leave is within its budget. The copies' own residual, `q_totʲ − Σᵢ χᵢʲ`, is within its budget, and so is what their repair moves. Under 1M the rain and snow tags close against `ρq_rai` and `ρq_sno`. | M2        |
| 5  | **Per-tag accuracy.** Against the copies, the default's per-tag error on D4-W and on the deep development column is within budget at 24 h and in the first hour. A tag below 1% of the partition is judged on its absolute error. A CI test shows the copies and a passive tracer agree to rounding without water-specific terms. Manufactured mixing tests pass.                                                 | M3, M5    |
| 6  | **Convergence, as robustness.** At every rung of time step, grid and Newton count, the default meets the per-tag budget. The copies' shares move by less than the per-tag L1 budget between the baseline and the finest rung, with the parent's own change reported beside them.                                                                                                                                  | M3        |
| 7  | **Precipitation provenance.** Under 0M the sink is split by subdomain. Under 1M rain and snow carry tags. `Σᵢ pr_tagᵢ = pr` within budget. The net-flow attribution between compartments is audited against gross process rates on a column, within budget. Surface precipitation by tag is reported with its assumptions.                                                                                        | M5        |
| 8  | **Held-out columns.** RICO (1M), BOMEX (1M), ARM SGP (1M, deep, continental) and the GCM-driven column (0M) meet criteria 4 and 5 without retuning.                                                                                                                                                                                                                                                               | M5        |
| 9  | **Float32.** A Float32 twin of D4-W meets criteria 3 and 4 within 10× the Float64 residual. This is a precision-sensitivity check. It decides no cause: that needs tagged and untagged pairs at each precision, and refinement.                                                                                                                                                                                   | M3        |
| 10 | **Cost.** Build time, step time and peak memory are measured in both modes and with the rain and snow tags. The copies are measured at 2, 4 and 8 tags and extrapolated, with a time limit. The allocation gates pass. The default mode meets its cost budget, set before V-W11.                                                                                                                                  | M4        |
| 11 | **Sphere.** Ten days of the G2 sphere with water tags under the chosen default meet the sphere budget: its form is fixed in 6.1, its numbers before the run. A one-day copies twin gives the per-tag error there. A restart holds.                                                                                                                                                                                | —         |
| 12 | Reviewed and tested: agent reviews with their findings fixed, CI green, and draft PRs ready. The docs are updated: `tagged_water.md`, whose "same diffusion operators" claim is wrong under 1M; `known_issues.md`; NEWS; and a claim contract for tagged water.                                                                                                                                                   | M1, M2    |

## 3. What EDMF does to the water, and what the tags miss today

From the inventory of 2026-09-23 and the review, at `dbe7435c`.

| Path                                                                                                                                           | What it does to water                                                                                                                                                                                     | The tags today                                                                                                                                                |
|:---------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SGS mass flux (`edmfx_sgs_flux.jl:28-175`)                                                                                                     | Moves `ρq_tot`, `ρ` and each species by the updraft's and environment's flux. Always implicit (`implicit_tendency.jl:118`), with Jacobian blocks `(ρq_tot, q_totʲ)`, `(ρq_tot, ρ)` and the species'.      | **Nothing.** No updraft field, so the loop never sees them.                                                                                                   |
| SGS diffusive flux (`:213-427`)                                                                                                                | `ρq_tot` takes `K_h` on `q_tot_eff` (1M: without rain and snow) and `K_e` in the tracer loop (`α = 0`).                                                                                                   | **Leak under 1M:** tags take `(K_h + K_e)` on their whole value. Exact under 0M. The updraft mirror is skipped (B4 guard).                                    |
| Grid-scale hyperdiffusion (`hyperdiffusion.jl:496` against `:548`) and viscous sponge (`viscous_sponge.jl:197` against `:228`)                 | Act on `q_tot_eff` for `ρq_tot` under 1M.                                                                                                                                                                 | **Leak under 1M,** the same kind.                                                                                                                             |
| Updraft vertical-diffusion mirror (`edmfx_sgs_flux.jl:330` against `:415`) and updraft hyperdiffusion (`hyperdiffusion.jl:555` against `:618`) | The same `q_tot_eff` treatment for `q_totʲ`.                                                                                                                                                              | Copies would inherit the **leak**.                                                                                                                            |
| Updraft advection, entrainment, filter (`mass_flux_closures.jl:303-316`: clamp to `[0, ρq_tag/ρa]`, reset to `ρq_tag/ρ` where `ρa < ϵ`)        | Move `sgsʲs.q_tot`. The filter never writes `ρq_tot`.                                                                                                                                                     | Generic for copies.                                                                                                                                           |
| **Updraft 1M sedimentation** (`advection.jl:440-441`, `updraft_sedimentation!` with lateral inflow `α_lat ∂a/∂z ρ⁰w⁰χ⁰`, `:561`)               | Changes `sgsʲs.q_tot` and the updraft species.                                                                                                                                                            | **Copies miss it.** It is not generic.                                                                                                                        |
| Microphysics, 0M (`microphysics/tendency.jl:101-133`)                                                                                          | The environment (`ρa⁰`) and each updraft (`ρaʲ`) contribute `dq_tot_dt`, and `Δ = Δ⁰ + ΣΔʲ` to rounding.                                                                                                  | Mass exact. **Composition** is the cell's average.                                                                                                            |
| Microphysics, 1M (`:153-191`)                                                                                                                  | Net tendencies of `q_lcl`, `q_icl`, `q_rai` and `q_sno` per subdomain (`ᶜmp_tendency⁰`, `ᶜmp_tendencyʲs`), from CloudMicrophysics' bulk tendencies. No process rates are exposed. Never changes `ρq_tot`. | Correctly a no-op for total water.                                                                                                                            |
| Sedimentation, 1M (`water_advection.jl:41-218`)                                                                                                | Grid-mean flux per species. EDMF corrects only the energy flux.                                                                                                                                           | Mass exact. **Composition is reset at each level** (the mirror takes the donor cell's total-water share), so `pr_tag` would be the lowest cell's composition. |
| Updraft surface boundary (`edmfx_boundary_condition.jl:337-384`)                                                                               | Relaxes `q_totʲ` at level 1 toward `q_b = q̄ + C√σ²`, where the excess is never negative.                                                                                                                 | Nothing at grid scale. Copies need a target.                                                                                                                  |
| Surface flux, forcings, subsidence                                                                                                             | Grid-mean writers, bracketed.                                                                                                                                                                             | Followed.                                                                                                                                                     |
| Vertical advection of `ρq_tot` (`implicit_tendency.jl:252, 395`)                                                                               | Implicit, with a post-Newton correction.                                                                                                                                                                  | Explicit for the tags: the known drift.                                                                                                                       |
| `rescale_water_tags!`                                                                                                                          | Runs inside `tracer_nonnegativity_constraint!`, **before** the filter (`constrain_state.jl:44-48`). Only `repair_water_tag_partition!` runs after it.                                                     | —                                                                                                                                                             |
| The updraft's precipitation mass loss on the implicit path                                                                                     | `sgs_ρa_implicit_tendency!` overwrites microphysics' `ρa` sink (`initialize_implicit_problem.jl:291`), while `q_totʲ` keeps the `(1 − q)` dilution.                                                       | Documented. The copies' rule mirrors `q_totʲ`.                                                                                                                |

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
    owner decides whether the plume's start should model it.

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
computed from the state in closed form, sizes it on D4-W and on the sphere. A
path gets its correction when its leak exceeds a tenth of the closure budget.
V-W0c's estimate for the grid-scale vertical diffusion on D4-W is 0.9% of the
column's water a day (FINDINGS W18), 45 times that level. So that path needs
its correction, or the rain and snow tags, before criterion 4 is judged on
D4-W.

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
    changes a column's total stays in place, with ledgers `q_tag_inc_left` and
    `q_tag_inc_moved`.
  - The tags' explicit vertical advection is then skipped, as `advection.jl:257`
    does for the energy tags. Otherwise it would count twice.
  - Its post-solve hook composes with `EnergySourceIncrementCorrection` in one
    hook. It reuses the stepper check. ARS222 passes it in practice, since
    D4's increment runs used it, but no test asserts that; WP5 adds one.
  - **Known issue 4 is not claimed as fixed.** The parent's 0M sink has no
    Jacobian block either, so parent and tags take it at the same iterate. It
    also changes the column's total, which the follower leaves in place.
    V-W0a restates or closes that issue.

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

| WP     | What                                                                                                                                                                                                                                                                                                                                                      | Kind              | Depends on   | Review       |
|:------ |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------- |:------------ |:------------ |
| WP0    | #95 merged with decision 5 (job session, owner). The phase-1 review. The verifier extended to `q_tag_*`, copies, rain and snow parts and `pr_tag_*`. Checks: the ERA5 forcing of V-W8 is on disk, and V-W2 can be set up. The sizing run V-W0c                                                                                                            | analysis          | —            | this session |
| WP1    | Refusals and reserved names (4.8). Known issue 1 closed with the post-#64 CI numbers; issue 3 updated. **Draft PR-W1**                                                                                                                                                                                                                                    | model code, small | WP0          | Opus, high   |
| WP3    | Total water under EDMF (4.1): the switch; donor flux and exchange with the rescaled plume; copies with their four mirrors, rebuild and repair; restart guard; refusals lifted; bound activation in the audit; leak diagnostics (4.2); CI group `tagging_water_edmf` with the parity, manufactured-mixing and copies-against-tracer tests. **Draft PR-W3** | model code        | WP1          | Opus, xhigh  |
| WP5    | The follower (4.3). **Draft PR-W5**                                                                                                                                                                                                                                                                                                                       | model code        | WP3          | Opus, xhigh  |
| WP4a   | The 0M split (4.4) and `pr_tag` under 0M. **Draft PR-W4a**                                                                                                                                                                                                                                                                                                | model code        | WP5          | Opus, xhigh  |
| WP4b-D | Design note for rain and snow tags (4.5)                                                                                                                                                                                                                                                                                                                  | design            | WP3          | Opus, xhigh  |
| WP4b   | Rain and snow tags in three stages (4.5), with the audit script. **Draft PR-W4b**                                                                                                                                                                                                                                                                         | model code        | WP4b-D, WP4a | Opus, xhigh  |
| WP4c   | The leak corrections that 4.2's rule selects, for runs without rain and snow tags                                                                                                                                                                                                                                                                         | model code        | V-W0c, V-W3  | with WP4b    |
| WP6    | Gross accumulators for both families: absolute repair and fix throughput with event counts, per-step `\|m_left\|`, attempted against retained, restart segments. **Draft PR-W6**                                                                                                                                                                          | model code        | WP0          | Opus, high   |
| WP2    | Shared helpers, only the identical parts (4.6)                                                                                                                                                                                                                                                                                                            | refactor          | V-W3, V-W5   | Opus, xhigh  |
| WP8    | Docs: `tagged_water.md` (EDMF, precipitation, the corrected operator claim), the claim contract, `known_issues.md`, NEWS                                                                                                                                                                                                                                  | docs              | WP4b         | Opus, high   |
| WP9    | Cost for both families (V-W10)                                                                                                                                                                                                                                                                                                                            | benchmarks        | WP4b         | this session |

Order:

 1. WP0, then WP1.
 2. WP3 with its CI group.
 3. V-W1 to V-W3, which fix WP5's default.
 4. WP5, then WP4a.
 5. WP4b-D, then WP4b, with WP4c beside it.
 6. WP2, WP8 and WP9, before the sphere.

WP6 runs in parallel from WP0 on.

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

**The deep 0M development case** is TRMM_LBA with 0M, 3 h. The held-out set of
criterion 8 is separate.

| Run   | What it decides                                                                                                                                                                                                                                                                                                               | Jobs     | Needs      |
|:----- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------- |:---------- |
| V-W0a | Known issue 4: a precipitating 0M column without EDMF, 1 against 10 Newton iterations. Closes or restates the issue                                                                                                                                                                                                           | 2        | WP0        |
| V-W0c | Sizing before WP3's details are fixed: one untagged D4-W day with EDMF diagnostics. The updraft's share of rain and snow, the surface excess `C√σ²`, and the five 1M leaks in closed form                                                                                                                                     | 1        | WP0        |
| V-W1  | "Before": D4-W with grid-scale tags on `main` + #95, before WP1's refusal, plus the untagged twin                                                                                                                                                                                                                             | 2        | WP0        |
| V-W3  | D4-W, default against copies on one atmosphere, 1 to 24 h; each with a 10-Newton twin; bound activation; a surface pulse. The TRMM 0M development case, default against copies                                                                                                                                                | 8        | WP3        |
| V-W4  | The ladder, default and copies at each rung: dt 60 and 30; Newton 2, 4 and 10; 60 and 120 levels; first-order upwinding. The copies' own convergence is read from the same runs                                                                                                                                               | 18       | V-W3, WP5  |
| V-W5  | Precipitation: the 0M split on and off (TRMM development case, both modes). Rain and snow tags on and off on a 1M column without EDMF and on D4-W (both modes). The net-flow audit on the column. `Σ pr_tag = pr`                                                                                                             | 10       | WP4a, WP4b |
| V-W6  | Held out, default and copies each: RICO 1M (24 h), BOMEX (`bomex_column`, dt 120 s, 6 h, with the passive tracer), ARM SGP 1M (1 day), GCM-driven 0M (6 h)                                                                                                                                                                    | 8        | V-W5       |
| V-W7  | Float32 twin of D4-W                                                                                                                                                                                                                                                                                                          | 1        | V-W5       |
| V-W8  | A file-based column with water and energy tags: `prognostic_edmfx_gcmdriven_column` (0M, the GCM start from site 23) for 3 h. Its forcing, the `cfsite_gcm_forcing` artifact, downloads through the package manager and was fetched on 2026-09-23. The owner chose it over the ERA5 column, whose forcing is not downloadable | 1        | WP3        |
| V-W9  | Restart round trips: D4-W in both modes, and with rain and snow tags                                                                                                                                                                                                                                                          | 4        | WP4b       |
| V-W10 | Cost: 2, 4, 8 and 32 tags where they build in time, both modes, with and without rain and snow tags, both families                                                                                                                                                                                                            | about 14 | WP4b       |
| V-W11 | The sphere: `g2_v2_sphere_n2` with water tags and rain and snow tags under the chosen default, 10 days, 24 ranks (about 16.5 h and 500 GB, as E75). A one-day copies twin. A restart after day 1. A two-rank parity pair                                                                                                      | 5        | all above  |

That makes about 70 column-scale jobs and 5 sphere jobs. Column runs go to
`hpda2_test` where they fit in two hours, otherwise `hpda2_compute`.

### 6.1 Budgets, fixed before the runs

**Set by the owner on 2026-09-23**, before any G3 run. Two parts are set
later, in the form fixed here: the sphere's numbers before V-W11, and the
default mode's cost budget after V-W10's first measurements. The measures are
those of `analysis/increment/tag_correctness.py`:

  - L1 is `∫ρ|Δq|dz / ∫ρ|q_ref|dz`;
  - L∞ is `max |Δq| / max |q_ref|`, normalised by the peak.

The verifier computes both (WP0).

  - **Per tag, default against copies, at 24 h:** L1 ≤ 2% and L∞ ≤ 5%. These
    are G1's criterion 4b for energy. E76 met them at every time step and
    Newton count, with 1.6% and 2.6% at worst. A looser budget would let the
    default's error exceed the spread from the mixing convention alone, about
    1% in L1 (E66).

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

  - **Leak corrections:** a path is corrected when its leak exceeds a tenth of
    the closure budget.

  - **The sphere.** The form is fixed now. The plateau's numbers are set from
    the column results before V-W11.

      + At every output, `Σᵢ ρq_tagᵢ ≤ ρq_tot (1 + 1e-6)` at every point, and
        the non-positive fraction does not grow. Issue #64 went to 1e130 and
        still exited 0 (W6).
      + The gross residual plateaus after day 1.
      + The one-day copies twin meets the per-tag budgets.
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
