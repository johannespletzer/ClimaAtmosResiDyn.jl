# Findings register

This is the register of what the tag-closure series measured. Each finding has
an ID, the claim in a sentence or two, its numbers, and its evidence: the run
directory, the job, the script and the commit. Where a claim is bounded, to one
geometry, one resolution or an uncontrolled comparison, the bound is part of
the finding. An inference is marked as one.

**State as of 2026-09-23.** Where an entry gained a date or a commit in the
condensing, its source is another part of the original FINDINGS (such as
its old section 8), the register, RUNS.md or `review/verify_g3.md`. The register holds W1–W14 for the water tags,
E1–E76 with sub-entries for the energy source tags and the `ρe_tag_*` family,
R1–R11 for the energy reference, T1–T10 for cost and M1–M6 for method. G1, a
closed and explained EDMF column, was met on 2026-09-20 (E62, E64, E65, E66,
E73). G2, ten days on the sphere, was met on 2026-09-22 (E74, E75). G3, the
water tags under EDMF, is set by [G3_PLAN.md](G3_PLAN.md), and its work starts
with WP0. G4, the energy
source tags, follows by [G4_TODO.md](G4_TODO.md). Where things stand is in
[STATUS.md](STATUS.md), and what waits beyond G4 in [BACKLOG.md](BACKLOG.md).

**Condensed on 2026-09-23.** The register is grouped by topic, not by date.
Every ID is kept, and every number is quoted as the original gives it; where
an erratum corrects one, both stand beside the entry. The reasoning and the
secondary numbers are cut. The original, with its full text
and its old sections 7 ("What is not established") and 8 ("Next"), is archived
unchanged at [archive/2026-09-23/FINDINGS.md](archive/2026-09-23/FINDINGS.md).
Read it for any entry's full argument. The reasoning run by run is in
[archive/2026-09-23/LEARNINGS.md](archive/2026-09-23/LEARNINGS.md); the claims
only LEARNINGS held are here, with their register IDs (`LEARNINGS:A2:1` and so
on, from `review/register/claims.csv`).

**Numbering from here on.** G3's water findings continue at W15, W16, … in
section 1. G4's energy findings continue at E77, E78, … (E76, the R2 ladder, is the last before G4) in the section of their
topic. A finding that concerns both families is filed where its measurement was
made, with a pointer from the other section. A correction is a dated erratum
beside its entry, and the claim it replaces goes into section 12.

**Where the data is.** Each entry names its `output/<run>/` directory, which
holds the small tables. Where each run's NetCDF lives, on scratch or in the
archive, is in [RUNS.md](RUNS.md). Paths such as `analysis/…` and `output/…` are
relative to this directory.

## Names used here

  - **Form A** compares, pointwise, the new energy split by region with the
    same energy split by process. **Form B** compares the change of `∫ρe_tot`
    with the sum of the process records.
  - **The audit** is `energy_source_tag_transport: enthalpy` (#72). **The
    prototype** is `enthalpy_increment` (#94, on `main`). **The repair** is
    `energy_source_tag_repair`. **The offset** `c` is `energy_source_tag_offset`,
    110,495 J kg⁻¹ unless stated.
  - **D4** is the DYCOMS RF02 EDMF column with 1M, 8 tags and 5 records, a day
    at `dt` 120 s. **V2** is the production physics on a sphere (E69).
  - Two names are used twice. **V3** is C7 in Float32 in E45, and the
    passive-tracer twin on D4 in E68 and E73. **C2** is the implicit-path
    brackets (#69) in the run plan, and the restart guard (#92) in the old
    to-do list.
  - Labels such as T3, T6, A2, A7, U8, R5 or P4 inside an entry name items of
    the old to-do list, [archive/2026-09-23/OPERATIONAL_TODO.md](archive/2026-09-23/OPERATIONAL_TODO.md),
    not register IDs.

The series' short names, where an entry cites a run by name only. Jobs and
commits are from `review/register/runs.csv`; phase A's worktrees had local
changes, which [RUNS.md](RUNS.md) records.

| name | run directories                                                                                               | jobs                                           | commit                         |
|:---- |:------------------------------------------------------------------------------------------------------------- |:---------------------------------------------- |:------------------------------ |
| A1   | `a1_dt10`, `a1_dt5`, `a1_dt2p5`; control `a1_dt10_notags`                                                     | `27360483`, `27360484`, `27360496`; `27368035` | `3659746d`; `c7c00de9`         |
| A2   | `a2_none_dt{10,5,2p5}`, `a2_first_order_dt{10,5,2p5}`                                                         | `27360825` to `27360830`                       | `66d6dedc`                     |
| A3   | `a3_1m`; companion `a3_0m_vert_diff`                                                                          | `27361330`; `27369130`                         | `49b2ec97`; `af9cee7d`         |
| A4   | `a4_float32`                                                                                                  | `27361268`                                     | `49b2ec97`                     |
| A5   | `a5_sphere_limiter`; pre-fix in `before_issue_64_fix/`                                                        | `27367905`                                     | `8ed98b63`; pre-fix `49b2ec97` |
| C0   | `c0_column`, `c0_sphere`, `c0_sphere_audit`, with its terrabyte reading in `terrabyte/`                       | `27361326`, `27361327`, `27369268`             | `49b2ec97`, `bcbe190f`         |
| C1   | `c1_sphere_shift`                                                                                             | `13383684`                                     | `72a1bc6a`                     |
| C3   | `c3_column_record`                                                                                            | `27367733`                                     | `1a9a419e`                     |
| C4   | `c4_sphere_tag_offset`, `c4_sphere_tag_offset_2x`                                                             | `13384913`, `13384914`                         | `29430612`                     |
| C5   | `c5_column_offset`, `c5_sphere_gray`                                                                          | `13385401`, `13385402`                         | `bca389ba`                     |
| C6   | `c6_column_repair`, `c6_column_no_repair`, `c6_sphere_repair`, `c6_sphere_no_repair`, `c6_sphere_first_order` | `13385450` to `13385454`                       | `f3bbdb7b`                     |
| C7   | `c7_sphere_mp`                                                                                                | `13399601`                                     | `414f5f1b`                     |
| C8   | `c8_column_1m`                                                                                                | `13401744`                                     | `c11d1d3b`                     |
| C9   | `c9_column_enthalpy`, `c9_sphere_enthalpy`                                                                    | `13402392`, `13402393`                         | `0bfb5037`                     |
| C10  | `c10_sphere_enthalpy_repair`                                                                                  | `13403083`                                     | `7dc0a302`                     |

## Index

| IDs                                              | section                                             |
|:------------------------------------------------ |:--------------------------------------------------- |
| W1–W31                                           | 1. Water tags                                       |
| E25, E27, E29, E31–E37, E41, E42, E42b, E46, E48 | 2. Energy source tags: closure by transport         |
| E1–E6, E9b, E9c, E10–E19, E71, R1–R11            | 3. The energy reference and the offset              |
| E40, E53                                         | 4. EDMF and the updrafts                            |
| E39, E39b, E43, E59, E61, E62, E64–E67           | 5. The implicit channel and the increment prototype |
| E45, E47, E51, E54, E55, E57, E58                | 6. Parity, Float32, MPI and restarts                |
| E7–E9, E20–E24, E26, E28, E30, E38, E49, E63     | 7. The process records and the per-process checks   |
| E50, E60, E69, E70, E74, E75                     | 8. The sphere and long runs                         |
| E68, E72, E73, E76                               | 9. Mixing: V3 and the updraft gap                   |
| T1–T10, E44, E44b–E44e, E52, E56, E77, E78       | 10. Cost                                            |
| M1–M8                                            | 11. Method                                          |
| old claims, errata, conflicts                    | 12. Superseded and falsified claims                 |
| FQ-1 to FQ-24                                    | 13. What is not established                         |

## 1. Water tags

**W1. The residual is limiter-bounded, not discretization-bounded.** The default
van Leer ladder is flat across `dt` 10, 5 and 2.5 s, slope −0.011. The linear
ladders converge: +0.255 under `first_order` and +0.464 under `none`. At `dt`
10 s the fully linear reconstruction sits 13.8× below van Leer. A2 changes
`energy_q_tot_upwinding` and `tracer_upwinding` together, so 13.8× is not the
limiter's share alone. *A1, A2; `output/summary_a.csv`.*
*Open (LEARNINGS:A2:1).* Both linear ladders are sub-first-order, and `none`
stops converging: 2.054e-7 at `dt` 10, 1.049e-7 at 5, near the ideal 1.027e-7,
then 1.080e-7 at 2.5, 2.1× above the ideal. A floor near 1e-7 remains. Its
candidates are untested. *A2, jobs `27360825` to `27360830`.*

**W2. So implicit water tags are not worth their Jacobian cost.** They would
remove discretization error, and W1 says that is not the part that is there.
*A1, A2.*

**W3. A column trips no limiter, so the ladders measure operator disagreement
with nothing subtracted.** The correction ledger is identically zero across all
eleven column runs. *A1–A4.*

**W4. Float32 costs nothing on a column.** `a4_float32` gives 2.745e-5 against
`a1_dt10`'s 2.660e-5, a 3% difference. The reduction's own floor, at t = 0, is
2.338e-8 in Float32 against 2.700e-17 in Float64, about 500× below the memo's
`100 eps ≈ 1.2e-5` (LEARNINGS:A4:1). Bounded to a column; a sphere reduces over
many more cells. E45 took Float32 to a sphere for a day. *A4.*

**W5. A3's gap was vertical diffusion, not 1M.** `a3_1m` reads 29× below
`a1_dt10` on `max |q_tag_res|`, with two keys changed. The companion splits it:
`vert_diff` on with 0M held gives a factor of 0.037, 1M on with `vert_diff` held
0.934, and both 0.035. So vertical diffusion makes 27× of the 29×, and 1M 7%.
A3 alone, 9.844e-8 against A1's 2.844e-6, was uninterpretable
(LEARNINGS:A3:1, superseded by W5). *A1, A3, `a3_0m_vert_diff`.*

**W5b. The 1M `q_tot_eff` mismatch is not measurable on a column, and does not
raise the residual.** Holding `vert_diff` fixed, 1M moves `max |q_tag_res|` from
1.054e-7 to 9.845e-8, 7% down. A column reaches only the vertical branch of the
mismatch; hyperdiffusion and the viscous sponge need a sphere. *A3,
`a3_0m_vert_diff`.*

**W6. Issue #64: on a sphere the water tags diverged to 1e130 while `ρq_tot`
stayed bounded, and the run exited 0 reporting success.** `gross_relative` was
3.07e-5 at 1 h, 0.809 at 3 h, 24.2 at 4 h and 5.9e113 at 24 h, with the parent
at 1.62e16 throughout. *A5 before the fix, at `49b2ec97`;
`output/a5_sphere_limiter/before_issue_64_fix/`.*

**W7. The mechanism was the multiplicative rescale itself, not its documented
precondition.** With `e = ρq_tot − Σₖ ρq_tag_k`, the old rule gave
`e_after = r · e_before` in every cell with a positive parent, unconditionally.
The docstring's `ρq_tag ≤ ρq_tot_before` governs non-negativity, not closure.
An identity, not a measurement. *Verified against `tagged_water.jl:800`; the
randomised sequences it was first found with are not in the tree.*
*Erratum, 2026-09-23 (H3): the line has moved. Before the fix the rule was in
`_rescale_water_tags!`, about lines 695-741 of the pre-fix `tagged_water.jl`.
Today's docstring near line 814 restates the same fact. The mechanism holds in
both.* The hypothesis made at the time (LEARNINGS:A5:1, superseded by W7) was
that `water_tag_rescale_ratio`, unclamped above, amplifies once a tag exceeds
`ρq_tot_before`. `nonpositive_fraction` had reached 0.363 within the first hour
and stayed near 0.35.

**W8. The existing integration test could not see the divergence.** It runs
this configuration for one hour (`tagged_water_integration.jl:237`) and bounds
`max |residual| / max |ρq_tot|` at `:312`, not `gross_relative`. On the pre-fix
run that quantity is 7.5e-6 at 1 h and 6.0e-5 at 2 h, against a bound of 1e-2.
The failure starts between hours two and three.

**W9. The fix holds through a full day, and plateaus.** Post-fix
`gross_relative` is 1.89e-4 at 6 h, 2.51e-4 at 12 h and 2.79e-4 at 24 h. This is
no margin against the test's 1e-2, which bounds another quantity. *A5, re-run at
`8ed98b6`.*

**W10. The fix did not hold closure by emptying the tags.** `orphaned_relative`
is 2.5e-9, `nonpositive_fraction` unchanged at 0.35–0.36, and the signed
residual −7.5e-6 relative. *A5 audit.*

**W11. The residual is balanced, not directional.** `untagged_relative`
1.3556e-4 against `overclaimed_relative` 1.4307e-4, a 5% difference, as
transport leakage gives. The pre-fix runaway was pure overclaim. *A5 audit.*

**W12. The corrections changed character, which is the mechanistic evidence for
the fix.** Before it, `q_tag_fix_extratropics` 1.027e115 against
`q_tag_fix_tropics` 4.55e109, a factor of 2e5. After it, the two per-tag maxima
agree to fifteen digits, and their sum's maximum is smaller than either:
sum-preserving redistribution. Domain maxima, so a signature, not a proof. *A5.*

**W13. Phase A has a sphere operator residual.** `max |q_tag_res|` is 1.9e-5 at
24 h, 1.5e-5 at 6 h and 1.91e-5 at 17 h, flat after. The column at `dt` 10 gives
2.84e-6. Not a controlled comparison: A5 is `dt` 300 on `h_elem` 4, the column
30 levels at `dt` 10. Reduced over the remapped lat-lon field. *A5.*

**W14. The ledger keeps growing while the residual does not:** 6.2e-4 at 24 h,
32× the residual, still rising. *A5.*

**W15. V-W0a's first pair did not test known issue 4: the 0M column rains only
in its first hour.** DYCOMS RF02 under 0M without EDMF, with the DYCOMS
radiation and the decaying diffusion, dt 120 s, one day, tags `tropo`,
`strat` and `evap`, with 1 and with 10 Newton iterations. The initial cloud,
0.15 kg m⁻² of liquid, rains out within the hour; after that `pr` is zero at
every output and the liquid water path is zero from 2 h on. Column water grows
from 11.57 to 13.28 kg m⁻² by evaporation. The closure's `gross_relative` is
3.9e-3 at 1 h, 1.0e-3 at 5 h and 8.3e-5 at 24 h with one iteration, and 4.9e-3,
1.3e-3 and 7.4e-5 with ten. The signed residual is −5.5e-4 to −6.7e-4 kg m⁻²
from the first hour on with one iteration and −7.0e-4 to −9.5e-4 with ten, an
overclaim. Between the two runs the region tags' shares
differ by 1.0e-3 to 1.2e-3 in L1 at 1 h and by 6.6e-5 to 1.6e-4 at 24 h, while
`hus` differs by 4.2e-5 and 1.3e-5. *Jobs `13829854`, `13829855`,
`hpda2_test`, 2026-09-23, from `../ClimaAtmosResiDyn-wedmf-run` at `c537903b`
(`main` after #95); `output/w0a_0m_newton1/`, `output/w0a_0m_newton10/`,
`analysis/water/w0a_newton_day.py`. The share differences were recomputed by
the verifier (`compare_runs.py --ladder-share`) and agree to the digits given;
`output/w0a_0m_newton1/verifier_share.txt` and `.json`.*

**W16. Known issue 4 is real in the code but not visible in the answer: its
missing Jacobian diagonal changes the tags' Newton sensitivity by less than
4% on a raining 0M column. That sensitivity is the closure residual, which
grows as the solve converges.** *Erratum, 2026-09-23, after the owner's review
of #100: the headline claims more than the runs show. Moving microphysics
from the implicit to the explicit path also changes the operator splitting and
the discrete integration path, so the comparison below does not isolate the
missing diagonal. What it shows is narrower: on this 0M column the region
tags' 1-against-10-iteration difference changed by at most 4% between the two
paths, and `evap`'s by up to 24% at a size near 2e-5. Known issue 4 stays
open; isolating it needs runs that differ only in the diagonal (G3_TODO,
WP4a).* V-W0a's controlled pairs: the first two hours
of W15's column, when its cloud rains out, at 6-minute output, with implicit
or explicit microphysics, each at 1 and 10 Newton iterations. With explicit
microphysics the 0M sink is off the Newton path.

| L1 of the share, 1 against 10 iterations | 6 min  | 30 min | 60 min | 120 min |
|:---------------------------------------- | ------:| ------:| ------:| -------:|
| `tropo`, implicit microphysics           | 1.9e-3 | 1.3e-3 | 1.0e-3 | 7.4e-4  |
| `tropo`, explicit microphysics           | 2.0e-3 | 1.3e-3 | 1.0e-3 | 7.4e-4  |
| `strat`, implicit                        | 2.3e-3 | 1.4e-3 | 1.2e-3 | 9.2e-4  |
| `strat`, explicit                        | 2.4e-3 | 1.4e-3 | 1.1e-3 | 9.1e-4  |
| `hus` itself, implicit                   | 6.6e-5 | 5.0e-5 | 4.2e-5 | 3.2e-5  |

For the region tags the implicit and explicit rows differ by at most 4%,
with no fixed sign. `evap`, which holds 1% of the water in the first hour,
differs by up to 24%, of a quantity near 2e-5. So the region tags' 25-fold
larger sensitivity than the parent's comes from elsewhere.
It matches the change in the closure residual: `gross_relative` is 3.9e-3 at
1 h with one iteration and 4.9e-3 with ten, in both modes. A converged solve
makes the parent's implicit vertical advection more implicit, while the tags
are advected explicitly, so the split between them grows (the header of
`tagged_water.jl`). A proportional loss leaves each cell's shares unchanged,
so a missing diagonal on it acts only through what else changes the shares in
the step, which fits a small effect. *Inferred, not separated:* whether the
residual's early peak (7e-3 at 6 minutes, falling to 2.6e-3 at 2 h) is the
advection split at this step, or the initial adjustment, needs a `dt` ladder.
WP5's follower, which takes the parent's increment, is the planned cure for
the split (G3_PLAN 4.3). *Jobs `13831761` to `13831764`, `hpda2_test`,
2026-09-23, from `../ClimaAtmosResiDyn-wedmf-run` at `2a6f1294`;
`output/w0a_0m_{implicit,explicit}_newton{1,10}_2h/`,
`analysis/water/w0a_newton_2x2.py` (`output/w0a_0m_implicit_newton10_2h/newton_2x2.txt`).
The share differences at 6 and 30 minutes and 1 and 2 hours were recomputed by
the verifier (`compare_runs.py --ladder-share --hours 0.1,0.5,1,2`) and agree
to the digits given; `verifier_share.txt` and `.json` in the two `_newton1_2h`
output directories.*

**W17. V-W1, the "before": with grid-scale tags only, D4-W's water partition
drifts to 15% of the column's water in a day, and the model is untouched.**
D4-W is D4 (DYCOMS RF02, prognostic EDMF, one updraft, 1M, dt 120 s) with
`edmfx_vertical_diffusion: true`, water tags instead of energy tags, and V3's
passive tracer set to the `tropo` mask. On `main` after #95 the tags have no
updraft fields.

| `water_tag_closure.csv`        | 1 h         | 5 h     | 12 h               | 24 h        |
|:------------------------------ | -----------:| -------:| ------------------:| -----------:|
| `gross_relative`               | 0.022       | 0.078   | 0.123              | 0.151       |
| `relative` (signed)            | −2.4e-4     | −5.0e-3 | −0.016             | −0.052      |
| untagged / overclaimed, kg m⁻² | 0.13 / 0.13 |         | 0.62 / 0.79 (11 h) | 0.57 / 1.18 |

The gross residual is 75 times the closure budget of 0.2% at 24 h; the second
12 h add less than the first. The tags overclaim more than they miss, so they
hold water the column has lost. Against the passive tracer, which mixes as the
air does, the `tropo` share differs by 0.088 in L1 at 1 h and 0.23 at 24 h; its
column mean is 0.83 against the tracer's 0.74. That gap is the missing
sub-grid flux plus the region attribution of new water (E68's erratum), not
separated. The split `evap_tropo + evap_strat = evap` holds to 1e-15, as it
must for tags that all see the same operators. **Parity:** all 37 fields the
untagged twin writes, the updraft and environment fields and the tracer among
them, are bit for bit the same at all 25 outputs. *Jobs `13829853` (tagged) and
`13829852` (twin), `hpda2_test`, 2026-09-23, from `../ClimaAtmosResiDyn-wedmf-run`
at `c537903b`, driver `analysis/water/d4w_driver.jl`;
`output/w1_d4w_grid_tags/` (with `parity.txt`), `analysis/water/d4w_parity.py`,
`analysis/water/d4w_before_and_sizing.py`. The parity was recomputed by the
verifier (`compare_runs.py --parity-only`): 37 fields bit for bit;
`output/w1_d4w_grid_tags/verifier_parity.txt`. The closure numbers are the
model's own table; the tracer comparison is a single-run analysis, which the
verifier does not cover.*

**W18. V-W0c sizes WP3: on D4-W the updraft holds no rain worth tagging and
there is no snow, but the 1M diffusion leak alone would fail the closure
budget.** The untagged D4-W day of W17, with the EDMF diagnostics.

  - **Rain and snow in the updraft.** The rain water path is 3.6e-3 to
    7.0e-3 kg m⁻², and the updraft holds under 0.01% of it at every hour.
    There is no snow. Surface precipitation averages 1.2e-5 kg m⁻² s⁻¹ over
    the hourly samples. So D4-W cannot exercise the rain and snow tags'
    updraft composition; the deep and continental cases of V-W5 and V-W6
    have to.
  - **The surface excess.** At the first level the updraft is moister than
    the environment by 2.9e-4 to 3.0e-4 kg kg⁻¹, about 3% of `q_tot`, while
    the environment's standard deviation there is 2.0e-5 to 3.1e-5. The
    updraft covers 10% of the area.
  - **The 1M `q_tot_eff` leak.** On a column only the grid-scale vertical
    diffusion leaks; hyperdiffusion and the sponge are off. The tags diffuse
    their whole value while `ρq_tot` diffuses without rain and snow, so the
    partition's sum is off by `∂z(ρ K ∂z q_p)`. With `K` the model's `edt`
    (up to 225 m² s⁻¹) and the hourly samples, the net change per level over
    the day sums to 0.9% of the column's water, 0.85% with the environment's
    area. That is 4.5 times the closure budget and 45 times the level at which
    G3_PLAN 4.2 corrects a path, and 6% of W17's residual. *An estimate:*
    hourly samples of a quantity that varies within the hour, and `edt` in
    place of the operator's own coefficients. WP4c's exact diagnostic replaces
    it. Consequence: D4-W's closure (criterion 4) can pass only with WP4c's
    correction or with the rain and snow tags, which remove the leak by
    construction.

*Job `13829852`, as W17; `output/w0c_d4w_untagged/before_and_sizing.txt`.
Single-run estimates, which the verifier does not cover; the script is
`analysis/water/d4w_before_and_sizing.py`.*

**W19. After #64's fix, the water integration test's two closure quantities
sit well inside their bounds.** On `main` at `0b2b1032` and Julia 1.11,
`test/tagged_water_integration.jl` passes all 111 tests. The sphere's
limiter-rescale residual, `maximum(abs.(residual)) / scale`, is 7.4e-4 against
1.17e-3 before the fix and a bound of 1e-2. The 1M sedimentation `norm` lies
between 0.9996 and 1.0003, against 1.00006 on `ci 1.10` before the fix and a
bound of 1 + 1e-2: the drift grew fivefold with the fix and stays 30 times
inside its bound. Known issue 1 is closed with these (#100). *Job `13831751`,
`hpda2_test`, 2026-09-23, the test file with two `@info` lines added, against
`../ClimaAtmosResiDyn-wedmf-run`; `output/ki1_integration/`.*

**W20. WP3's development runs: the tags following the updraft cut D4-W's
closure residual 27 to 77 times in the first three hours, 27 at 3 h, and the
copies needed a fifth mirror, the surface moisture flux into the updraft.** Three-hour D4-W
columns, as V-W1's but with WP3's code, before V-W3. Relative to the column's
water, from each run's `water_tag_closure.csv` and `water_tag_audit.csv`:

| gross residual                  | 1 h     | 2 h     | 3 h     |
|:------------------------------- | -------:| -------:| -------:|
| V-W1, grid-scale tags (W17)     | 2.2e-2  | 2.3e-2  | 4.4e-2  |
| default mode                    | 5.4e-4  | 3.0e-4  | 1.6e-3  |
| copies, four mirrors            | 3.8e-4  | 2.0e-4  | 4.0e-4  |
| copies, five mirrors            | 3.7e-4  | 2.0e-4  | 3.9e-4  |

| copies                                  | 1 h     | 2 h     | 3 h     |
|:--------------------------------------- | -------:| -------:| -------:|
| residual before repair, four mirrors    | 9.0e-5  | 4.1e-5  | 4.3e-5  |
| residual before repair, five mirrors    | 5.6e-5  | 6.2e-6  | 8.6e-6  |
| repair, cumulative, four mirrors        | 1.5e-3  | 3.1e-3  | 4.3e-3  |
| repair, cumulative, five mirrors        | 2.6e-4  | 7.8e-4  | 9.9e-4  |

  - **The fifth mirror.** `surface_flux_tendency!` adds the surface moisture
    flux to `q_totʲ` in the lowest cell and gives every other updraft tracer
    a zero flux. The copies missed it, and G3_PLAN 4.1 lists only four
    mirrors. The 0M CI group found it: with one composition everywhere, each
    copy's whole tendency missed its share of `q_totʲ`'s by 60% of the
    largest, the same for every share. The mirror gives the copies the
    updraft's increment by the grid tags' rule for `surface_flux`. With it
    the group passes, a passive tracer set to a copy's values taking the
    copy's tendency apart from its mirrors to 1e-10. The numerics review
    found the term independently and lists every writer of `q_totʲ`, with no
    further term missed.
  - **What the repair still moves.** With the fifth mirror the repair moved
    about 0.1% of the column's water in 3 h, 4.4 times less than without it.
    At 0.02 to 0.05% an hour it would pass G3_PLAN 6.1's 0.2% over the day
    within 4 to 10 h. What makes it is not isolated. The review lists
    candidates (S5): the grid partition's residual reaching the copies
    through entrainment and the filter, the Newton mismatch, the leaks and
    the rain-out's clamp. V-W3's day measures it against the budget.
  - **The column is the same.** The column's total water is identical in
    every run at every hour. The default mode's run after `water_tag_plume!`
    was split out matches the one before byte for byte, in both tables and in
    all 48 NetCDF files.
  - The default mode's gross residual at 3 h is already 0.16%, near the
    day's budget. W18's estimate of the vertical diffusion's leak, 0.9% a day,
    would account for it, but these runs do not split it.

*Development runs, not V-W3: 3 h, `hpda2_test`, 2026-09-23, from frozen
snapshots of `claude/water-tags-edmf-wp3` with `claude_work/g3/wp3/dev_driver.jl`
(no passive tracer set, copies started from the grid mean). Jobs `13845275`
(default, 3d5ab52e), `13851541` (default, 6b687e0a), `13845274` (copies, four
mirrors, 3d5ab52e), `13851540` (copies, five mirrors, 6b687e0a); tables and
configs in `output/wp3_dev/`. The numbers are the model's own tables; the
verifier was not run on them. The CI group's result: job `13846383`, and
`13851548` with the mirror.*

**W21. V-W3: on D4-W every tag meets its budget against the copies, but the
default mode's closure does not with one Newton iteration, 0.71% at 24 h
against 0.2%. With ten it is 0.13%. So WP5's rule selects the follower. The
copies' repair moves 0.6% of the water in a day, three times its bound, so
the audit is flagged.** D4-W for a day, default against copies on one
atmosphere, each at one and ten Newton iterations. The copies start from the
plume. The verifier judged each pair with `--judge` (G3_PLAN 6.1). In all
three D4-W pairs the parent fields are bit for bit the same, and the default
days match the untagged twin `w0c_d4w_untagged`.

Per tag, default against copies (L1 / L∞):

| tag, iterations | 1 h           | 24 h          | budget 1 h / 24 h (L1, L∞)    |
|:--------------- | -------------:| -------------:|:----------------------------- |
| `tropo`, 1      | 0.22% / 1.4%  | 0.73% / 3.4%  | region: 1%, 25% / 2%, 5%      |
| `tropo`, 10     | 0.21% / 1.4%  | 0.17% / 0.49% |                               |
| `strat`, 1      | 0.62% / 3.7%  | 0.47% / 1.1%  |                               |
| `strat`, 10     | 0.55% / 3.4%  | 0.23% / 0.84% |                               |
| `evap`, 1       | 6.6% / 7.2%   | 0.96% / 4.2%  | source: 10%, 25% / 2%, 5%     |
| `evap`, 10      | 4.6% / 7.3%   | 0.22% / 0.28% |                               |

The gross closure residual, relative to the column's water, from each run's
`water_tag_closure.csv`:

| run            | 1 h     | 12 h    | 24 h    |
|:-------------- | -------:| -------:| -------:|
| default, 1     | 5.4e-4  | 3.0e-3  | 7.1e-3  |
| default, 10    | 9.9e-5  | 5.8e-4  | 1.3e-3  |
| copies, 1      | 3.7e-4  | 2.1e-3  | 1.8e-3  |
| copies, 10     | 9.6e-5  | 7.4e-4  | 1.8e-3  |

  - **WP5's rule.** The one-iteration part of the default's residual is
    7.1e-3 − 1.3e-3 = 5.8e-3, twelve times a quarter of the budget (5e-4).
    By G3_PLAN 4.3 the follower becomes the default transport under EDMF.
  - **The second 12 h** add more than the first in the default runs at both
    iteration counts (4.1e-3 against 3.0e-3, and 7.3e-4 against 5.8e-4) and
    in the copies at ten (1.0e-3 against 7.4e-4). The copies at one iteration
    peak before 24 h.
  - **The one-iteration lag is not the same in both modes.** G3_PLAN 4.3
    says both lag alike, so comparing them cannot show the lag. Here ten
    iterations cut the default's residual 5.4 times and the copies' by 4%. The
    modes' disagreement at 24 h falls about fourfold (`tropo` 0.73% to 0.17%,
    `evap` 0.96% to 0.22%). These pairs change only the iteration count, in
    both modes at once, so they bound the lag's effect on the comparison. They
    do not isolate it in either mode.
  - **The copies' own partition.** The residual before the repair is 1.0e-5
    at 24 h with one iteration and 6.5e-6 with ten, inside 6.1's 2e-4. The
    repair, cumulative, moves 0.60% of the column's water over the day with
    one iteration and 0.27% with ten. 6.1 bounds it at 0.2%, so the audit is
    flagged at both: the repair shapes the copies. W20's development runs
    extrapolated 0.24 to 1.2% a day. What makes it is still not isolated.
  - **Bound activation** (default mode, the fraction of the 30 levels where
    a tag's admissibility bound acts, over the audit's rows): `evap` at most
    0.3 and 2.5% on average, with one iteration or ten. The partition's bound
    never acted with one iteration, and on one level at most with ten.
  - **The surface pulse.** The same pair at one iteration with the partition
    split at 50 m: `sfc` below, `air` above. `sfc` misses its first-hour
    budget, L1 14.4% and L∞ 17.4% against 1% and 25%. It is within budget
    from 6 h on (L1 0.51% at 6 h, 0.98% and L∞ 4.1% at 24 h). `air` and
    `evap` pass. So in the first hour the two modes' surface rules move a
    surface-layer tag differently by an order of magnitude more than the
    budget. The pair does not say which mode is nearer the truth. The
    default's partition bound acted on up to 27% of the levels here, 1.6% on
    average. The closure is as on the plain day (6.9e-3 and 1.6e-3 at 24 h).
  - **TRMM 0M, 3 h**, the development case, both modes at one iteration, and
    the copies at two and ten and the default at ten. The gross residual at
    3 h is 7.8e-5 to 1.2e-4 on every rung. Default against copies at 3 h
    (L1): `evap` 1.05% with one iteration and 1.04% with ten, `pbl` 0.25%
    and `free` 0.12% with ten. The copies' own residual stays below 7.1e-7
    and their repair below 1e-5. Across iteration counts the atmosphere
    changes (`hus` by up to 2% at 3 h), and the tags move with it by the same
    amount in both modes (`pbl` L1 2.0%, `evap` 7%, one against ten
    iterations). So the ladder does not bound the 0M copies' own Newton lag,
    and known issue 4 stays as it is.

*V-W3, `hpda2_test`, 2026-09-23, launched with `analysis/water/d4w_driver.jl`
(copies started from the plume) from `../ClimaAtmosResiDyn-wedmf-run`. The
default days, the pulse's default and the TRMM pair ran WP3 at `9aab6690`
(run tree `9085e264`): jobs `13857585`, `13857591`, `13857587`, `13857589`,
`13857590`. The copies days and the pulse's copies ran WP3 at `fe1331f2`
(run tree `b5f40586`): jobs `13862420`, `13862422`, `13862421`. The TRMM
ladder ran at `fe1331f2` (run tree `d06e48f1`): jobs `13863847`, `13863849`,
`13863850`. `fe1331f2` changes only the copies' Jacobian block, and the head
of #101, `4a1c91a4`, only a refusal, docstrings and diagnostic metadata, so
the tags evolve in these runs as at `4a1c91a4`. Verifier reports in
`output/w3_d4w/` and `output/w3_trmm0m/`.*

**W22. V-W8: on the GCM-driven file-based column, water and energy source tags
run together under EDMF with the model untouched, and the water partition
closes to 4.2e-4 gross after 3 h.** The column of
`prognostic_edmfx_gcmdriven_column.yml` (HadGEM2-A AMIP forcing, site 23, 0M,
prognostic EDMF, 60 stretched levels to 40 km, the sponge on, dt 10 s), for
3 h. Water tags `pbl` and `free` split at 1 km, `evap` (`surface_flux`) and
`fcg` (the forcing group: large-scale advection, subsidence and the external
forcing with its nudging), in WP3's default mode; energy source tags `pbl`,
`free`, `sfc` and `rad` with the offset 110495 J/kg.

  - **Parity.** All 24 fields the untagged twin writes are bit for bit the
    same at every half-hourly output (the verifier, `--parity-only`).
  - **Water.** The gross residual is 3.4e-4 of the column's water at 30 min
    and 4.2e-4 at 3 h, the net 4.0e-6. `evap` holds 2.0% of the column's water
    at 3 h, `fcg` 0.048%; their minima are −4.4e-10 and −2.5e-14 kg/kg. The
    exchange runs on 3.7% of the volume, and neither bound acted.
  - **Energy source tags.** The gross residual is 1.2e-3 at 30 min and 1.3e-3
    at 3 h, so nearly all of it arrives in the first half hour.
  - **Cost.** 19.3 ms a step with the eight tags against 13.5 ms without,
    43% more.

The model warns that the external forcing and the microphysics change `ρe_tot`
with no energy tag following them; the configuration chose that. *Jobs
`13866552` (tags) and `13866551` (twin), `hpda2_compute`, 2026-09-24, from
`../ClimaAtmosResiDyn-wedmf-run` at `837db55b` (the record branch with WP3 at
`4a1c91a4`); `output/w8_gcm/parity.txt`. The closure numbers are the model's
own tables.*

**W23. With the 1M microphysics on the explicit path and one Newton iteration,
the water tags lag the parent's solve by 0.8% of the column's water in an
hour, in both EDMF modes. Ten iterations close it.** The CI group
`tagging_water_edmf_copies` failed at `4a1c91a4` for this reason. Its column
(DYCOMS RF02, prognostic EDMF, 1M, 30 levels, dt 120 s, ARS222), an hour, with
the partition `tropo`/`strat` at 750 m and `evap`, run as a probe in six
variants. Closure after the hour, relative to the column's water:

| mode, microphysics, iterations | net       | gross    |
|:------------------------------ | ---------:| --------:|
| copies, implicit, 1            | −3.7e-5   | 3.7e-4   |
| copies, explicit, 1            | 7.8e-3    | 9.7e-3   |
| copies, explicit, 10           | −4.3e-7   | 7.5e-4   |
| default, implicit, 1           | −3.5e-5   | 5.4e-4   |
| default, explicit, 1           | 7.7e-3    | 1.6e-2   |
| default, explicit, 10          | −4.4e-7   | 7.7e-4   |

  - **The mechanism.** The parent's `ρq_tot` row carries a cross block from
    each sedimenting species (`update_sedimentation_jacobian!`,
    `manual_sparse_jacobian.jl:1233-1236`); the tags' rows carry only their
    own diagonal, and the cross terms are dropped on purpose
    (`update_water_tag_sedimentation_jacobian!`, 1283-1288). With one
    iteration the tags therefore miss part of the parent's sedimentation
    update. The table bounds the effect to the explicit path and one
    iteration, and ten iterations remove it. Why the explicit path makes it
    200 times larger than the implicit one is not isolated.
  - **The copies' residual** before the repair was 9.3e-5 with ten
    iterations, 1.9e-4 on the explicit path with one, and 5.6e-5 on the
    implicit path with one.
  - **The fix in #101** (`06adcf1c`): the copies group keeps the explicit path,
    which its parity check needs, and runs ten iterations. The composition
    check's NaN was the test dividing by `ρaʲ`, which is exactly zero on 8 of
    the 30 levels; it now takes the leak only where there is an updraft.
  - **What it leaves.** The lag is a property of the tags on this path, not
    of the copies. WP5's follower removes only its column-neutral part: its
    flux vanishes at both boundaries, so it never changes the partition's
    column total (the review of #102, S1). The net part, about half the gross
    in the default row and 80% in the copies row, most likely the linearized
    surface outflow of sedimentation, would stay and land in
    `q_tag_inc_left`. *Corrected on 2026-09-24; this entry first said the
    follower is built to remove the lag.* The explicit-path probe with the
    follower measures it.

**W24. WP5's follower closes D4-W's water partition to 1.5e-4 of the column
in a day with one Newton iteration, 47 times less than without it, and to
6e-10 with ten; every tag meets its budget against the copies, closer than
before. On the explicit 1M path it removes only the column-neutral half of
W23's lag.** The validation of #102 (`water_tag_transport: increment`), on
D4-W as V-W3's default day otherwise, and the explicit-path probes of W23 with
the follower.

| D4-W, default mode, 24 h                  | gross   | net      |
|:----------------------------------------- | -------:| --------:|
| tracer transport, 1 iteration (W21)       | 7.1e-3  | 2.0e-3   |
| **follower, 1 iteration**                 | 1.5e-4  | 2.4e-5   |
| tracer transport, 10 iterations (W21)     | 1.3e-3  | 1.1e-4   |
| **follower, 10 iterations**               | 5.6e-10 | 1.1e-10  |
| copies, 1 iteration (W21)                 | 1.8e-3  | 3.1e-4   |

  - **Against the copies** (the verifier, `--judge`, on one atmosphere; every
    parent field bit for bit): PASS at both iteration counts. At 24 h, one
    iteration, `tropo` L1 0.25% (0.73% under the tracer transport, W21),
    `strat` 0.41% (0.47%), `evap` 0.41% (0.96%); at 1 h `evap` 6.5% (6.6%).
    With ten iterations 0.25%, 0.32% and 0.25%.
  - **The closure's growth.** With one iteration the gross residual is 4.1e-5
    at 1 h, 1.1e-4 at 12 h and 1.5e-4 at 24 h: the second 12 h add less than
    the first, as 6.1 asks. The part left out at 24 h is −2.6e-5 of the column
    net and 2.0e-4 gross over the cells.
  - **What remains with one iteration** is the part of the parent's increment
    that changes a column's total, which the follower cannot move (the review
    of #102, S1). With ten iterations the Newton solve converges and that part
    vanishes with the rest.
  - **The partition's negativity (review S3).** Its minimum stays at 1.4e-9
    kg/kg, and the partition repair's ledger (gross over the cells, net over
    time) reaches 2.9e-3 of the column's water with the follower, as under the
    tracer transport; the copies' run has 5.2e-3. Nearly all of it arrives in
    the first 12 h, in every mode.
  - **The explicit 1M path, W23's column, an hour, one iteration:**

    | mode, transport       | net     | gross   |
    |:--------------------- | -------:| -------:|
    | default, tracer (W23) | 7.7e-3  | 1.6e-2  |
    | default, follower     | 7.9e-3  | 8.0e-3  |
    | copies, tracer (W23)  | 7.8e-3  | 9.7e-3  |
    | copies, follower      | 7.9e-3  | 8.0e-3  |

    The follower removes the column-neutral part and leaves the net, as its
    invariant says. Closing the net needs the column-total part routed out
    through the bottom face, or the tags' sedimentation cross blocks (for the
    owner).

*Jobs `13868824` (one iteration) and `13868825` (ten), `hpda2_compute`,
2026-09-24, D4-W driver, from `../ClimaAtmosResiDyn-wedmf-run` at `9acb4956`
(the record branch with WP5 at `867a5264`; `fd07d902` changes no numerics);
the verifier's reports in `output/w5_d4w/`. Probes `13868842`, `13868843` with
`analysis/water/explicit_probe.jl` (a transport argument added) from the WP5
worktree at `867a5264`.*

*Probes: `analysis/water/explicit_probe.jl` from the WP3 test snapshot at
`4a1c91a4`, `hpda2_compute`, 2026-09-24, jobs `13865359`, `13865360`,
`13865367`, `13866583`, `13866584`, `13866585`; the model's own
`tag_closure` after the hour; `output/wp3_explicit_probe/results.txt`.*

**W25. V-W4: under the follower, the default meets every per-tag budget
against the copies at the time-step and Newton rungs. At 60 levels it misses
the first hour's budget, and at 120 levels it misses every hour's. At 120
levels both modes lose the partition. With first-order upwinding the copies
lose it, and the default does not. The parent fields are bit for bit the same
in every pair.** D4-W ran for a day at seven rungs: dt 60 and 30 s, Newton 2
and 4, 60 and 120 levels, and first-order upwinding of the sub-grid flux. W24
has the Newton-10 rung. Each rung ran in two modes:
  - the default mode under the follower (`water_tag_transport: increment`);
  - with copies, started from the plume.

The verifier judged each pair (`--judge`, G3_PLAN 6.1). It also compared each
run's shares with its mode's baseline (`--ladder-share`). The baselines are
V-W3's copies day and W24's follower day.

Default against copies, L1 in percent, at 1 h / 24 h:

| rung        | `tropo`     | `strat`     | `evap`      | judge                          |
|:----------- | -----------:| -----------:| -----------:|:------------------------------ |
| dt 60 s     | 0.29 / 0.24 | 0.73 / 0.40 | 5.4 / 0.47  | pass                           |
| dt 30 s     | 0.30 / 0.23 | 0.75 / 0.58 | 8.6 / 0.45  | pass                           |
| Newton 2    | 0.21 / 0.24 | 0.56 / 0.28 | 4.7 / 0.41  | pass                           |
| Newton 4    | 0.22 / 0.21 | 0.56 / 0.31 | 4.6 / 0.39  | pass                           |
| 60 levels   | 0.57 / 0.40 | 1.36 / 1.72 | 11.8 / 0.22 | fail at 1 h: `strat`, `evap`   |
| 120 levels  | 23 / 19     | 8.0 / 9.2   | 31 / 3.8    | fail at 1 h and 24 h           |
| first order | 0.15 / 77   | 0.39 / 36   | 4.3 / 4.8   | reported, not judged; 23 h     |

The gross closure residual at 24 h, relative to the column's water, and the
copies' repair over the day:

| rung        | default | copies | copies' repair |
|:----------- | -------:| ------:| --------------:|
| baseline    | 1.5e-4  | 1.8e-3 | 0.60%          |
| dt 60 s     | 8.2e-5  | 1.7e-3 | 1.6%           |
| dt 30 s     | 2.3e-5  | 1.6e-3 | 1.8%           |
| Newton 2    | 5.7e-5  | 1.9e-3 | 0.30%          |
| Newton 4    | 4.3e-7  | 1.5e-3 | 0.28%          |
| 60 levels   | 8.3e-5  | 1.6e-3 | 0.62%          |
| 120 levels  | 3.0e-2  | 0.12   | 88%            |
| first order | 7.8e-5  | 1.06   | 95%            |

  - **G3_PLAN 6.1's convergence criterion has two parts.**
      + *The default meets the per-tag budgets at every rung.* It does at dt
        60 and 30 s and at 2, 4 and 10 Newton iterations. It does not at 60
        levels in the first hour: `strat` L1 is 1.36% against 1%, and `evap`
        11.8% against 10%. It does not at 120 levels at any hour.
      + *The copies' shares move by less than 2% in L1 between the baseline
        and the finest rung.*
          * On the Newton ladder they do. At ten iterations and 24 h the
            moves are 0.1%, 0.4% and 1.7%.
          * On the time-step ladder they do not. At dt 30 s and 24 h they are
            5.0%, 17% and 7.9%.
          * But there the parent's `hus` moves 7.9% as well, and the
            default's shares move as the copies' do (5.1%, 17% and 8.1%).
            This pair changes the atmosphere with the time step, so it does
            not separate the tags' convergence from the atmosphere's.
          * The level ladder can be compared only by column totals. At 120
            levels and 24 h the copies' `tropo` column share is 12.3 points
            above the baseline, and the default's is 4.9 points below.
  - **At 120 levels both modes lose the partition.**
      + In the default mode the follower leaves out 3.0e-2 of the column's
        water by 12 h (`q_tag_inc_left`). That is the whole gross residual.
      + With copies, the gross residual is 0.17 at 1 h, and the copies'
        repair moves 88% of the water over the day.
      + At 30 and 60 levels the same modes close to about 1e-4 (default) and
        1.6e-3 (copies).
      + Which operator parts the partition at 120 levels is not isolated.
  - **First-order upwinding of the sub-grid flux.**
      + The default closes to 7.8e-5 at 24 h.
      + The copies' gross residual grows from 2.4e-4 at 1 h to 8.8e-3 at 5 h,
        3.2e-2 at 12 h and 1.06 at 24 h. There the closure check's abort
        level of 1.0 ended the run, at its last check.
      + Their repair moves 95% of the water.
      + This is not isolated either. The parent reconstructs `q_tot` and the
        tracers with the same scheme (`edmfx_sgs_flux.jl`).
      + So on this column the copies are no audit under first-order upwinding
        or at 120 levels.
  - **The copies' repair grows as the time step shrinks.** It moves 0.60% of
    the water at dt 120 s, 1.6% at 60 s and 1.8% at 30 s. It shrinks with
    more Newton iterations, to 0.28% at four. It is over G3_PLAN 6.1's 0.2%
    bound at every rung.
  - **The cost (R5) is not answered here.** The progress logger's time per
    step is not consistent across rungs: dt 30 s takes less per step than dt
    60 s. Compiling dominated each job, 12 to 13 min in the default mode and
    28 to 41 min with copies. V-W10 measures cost.

*V-W4, `hpda2_compute`, 2026-09-24, run with the D4-W driver from
`../ClimaAtmosResiDyn-wedmf-run` at `1db57be5`. That tree is the record branch
at `b53c2a55` with WP5 at `867a5264`. `fd07d902` changes only docs, a
compile-time form of one predicate and a refusal, so the tags evolve as at
#102's head. Jobs `13870216` to `13870229`. Script
`analysis/water/vw4_verify.sh`; its reports are in `output/w4_d4w/`. The
first-order pair was compared over 23 h, the copies' last output.*

**W26. WP4a's split of the 0M rain-out, on TRMM 0M for 6 h: the model's fields
are unchanged bit for bit, the tags move by at most 0.47% of a tag's water,
and `Σ pr_tag` is `pr` to within 1.8e-3. The split moves both modes alike, so
their agreement is unchanged.** Two pairs of runs, each on one atmosphere,
from 0 to 6 h (TRMM rains from about 3 h):
  - the split: #104 at `b4c44841`;
  - the grid rule: #102 at `fd07d902`, the twins.

Each pair ran in the default mode and with copies. The verifier compared them.

  - **Parity.** Split against grid rule, in both modes, and #104's 3 h pair
    against V-W3's `w3_trmm0m_*` runs: every model field bit for bit (24
    fields, `--parity-only`).
  - **The split's effect** on each tag, same mode and atmosphere, L1 at 6 h
    (4 h in brackets):

    | tag    | default         | copies          |
    |:------ | ---------------:| ---------------:|
    | `pbl`  | 0.44% (0.098%)  | 0.47% (0.10%)   |
    | `free` | 0.23% (0.048%)  | 0.25% (0.049%)  |
    | `evap` | 0.45% (0.14%)   | 0.44% (0.13%)   |

    The split takes more of `pbl`'s water and less of `free`'s, so the
    updraft's rain carries more boundary-layer water than the grid mean's
    composition gives it. The effect grows with the rain. At 3 h, before the
    rain, it is 4e-6.
  - **Default against copies,** L1 at 6 h, with the split and with the grid
    rule: `pbl` 1.54% and 1.53%, `free` 0.82% and 0.82%, `evap` 1.72% and
    1.71%. The split does not narrow or widen the gap between the modes.
  - **`pr_tag`.** Over the partition, `pr_tag_pbl + pr_tag_free` is `pr` to
    within 1.8e-3 at every half hour with rain, in both modes. The rain's
    source moves from `pbl` (95% at 3 h) to `free` (70% at 6 h). The modes
    differ in `pbl`'s share by at most 6 points (at 5 h), and the surface
    tag's share is 4 to 7%. No `pbl` water falls as snow at the output
    times.
  - **The explicit path.** The same 0M EDMF column with explicit
    microphysics, an hour, in both modes, matches its untagged twin bit for
    bit (`analysis/water/wp4a_explicit_parity.jl`, 20 tests).

*`hpda2_compute`, 2026-09-24, D4-W driver. The 3 h pair ran from
`../ClimaAtmosResiDyn-wedmf-run` at `3a8f1c70`, jobs `13876508` and
`13876509`. The 6 h split pair ran from `../ClimaAtmosResiDyn-wedmf4a-run` at
`34f9a334`, jobs `13877542` and `13877543`. The grid-rule twins ran from
`../ClimaAtmosResiDyn-wedmf5-run` at `9abb1f62`, jobs `13877544` and
`13877545`. The explicit-path script ran as job `13874414` at `63a1ddaa`; its
log is in `output/wp4a_explicit_parity/`. Reports are in
`output/w4a_trmm0m/`.*

**W27. WP6's state ledgers under the other cadences: parity holds at `stage`
and `dss` with ARS343, and the per-step gross is exact bit for bit. At `dss`
the follower and the partition repair work orders of magnitude harder than at
`stage`.** The code review's script (`analysis/water/wp6_cadence_checks.jl`)
ran four configurations for 30 min each (15 steps of 120 s): the 1M EDMF
DYCOMS column under ARS343, with the vertical water borrowing limiter and the
updraft filter, at `update_constrain_state_every` `stage` or `dss`, with the
follower or with copies.
  - Each run's model fields equal the untagged run's at the same cadence, bit
    for bit.
  - The callback's gross equals `Σ|ΔL|` recorded by stepping by hand, bit for
    bit.
  - A run restarted from a mid-run checkpoint (ARS222, 20 min) ends with the
    state ledgers of the uninterrupted run, bit for bit.
  - 153 tests passed.
  - **At `dss` the transfer ledger `q_tag_led_repair` goes negative**, to
    −5.3e-7 with the follower and −2.6e-6 with copies. The code review
    predicted this from the negative stage weight (its S2). At `stage` the
    repair did not act in these 15 steps.
  - **At `dss` with the follower,** the largest cell values after 15 steps
    are much larger than at `stage`:

    | ledger                | `dss`   | `stage` |
    |:--------------------- | -------:| -------:|
    | `q_tag_led_repairnet` | 1.7e-2  | 0       |
    | `q_tag_inc_left`      | 2.7e-2  | 5.4e-5  |
    | `q_tag_inc_moved`     | 1.4e-2  | 1.6e-4  |

    These are state values in kg m⁻³, per cell. With copies at `dss`,
    `q_tag_led_repairnet` reaches 3.1e-3 and `q_tag_led_upfilter` 2.0e-2.
  - The follower's note (WP5) says the constraints at `dss` run between its
    snapshot and its solve, so their changes enter the mismatch. These runs
    agree with that, but do not isolate it.
  - `update_constrain_state_every: dss` is not the default, and no G3 run
    uses it.

*`hpda2_compute`, 2026-09-24, job `13877977`, from `../ClimaAtmosResiDyn-wedmf6`
at `e65009ef`; `1b976a97` changes only how the callback finds its fields. The
output is in `output/wp6_cadence/results.txt`.*

**W28. The owner's review of #102, point 4: leaving the column's total out only
where the mismatch has its sign, instead of spreading it by |m|, halves the
water the follower moves on D4-W. Nothing else measured changes beyond a
fifth. On TRMM 0M the two rules coincide, and the follower closes the
partition to 4e-15 where the tracer transport reaches 5e-4.** The same-sign
rule is #102 at `5bfa7cea`. W24's D4-W day under the |m| rule is the reference.
TRMM 0M ran for 6 h under both rules, in the default mode with the follower.
The copies' runs are the references.

| D4-W, 24 h, one Newton iteration                       | \|m\| (W24) | same sign |
|:------------------------------------------------------- | ----------:| ---------:|
| gross closure residual                                  | 1.53e-4    | 1.35e-4   |
| net closure residual                                    | +2.4e-5    | +4.2e-5   |
| left out (`increment_left_relative`)                    | −2.57e-5   | −2.55e-5  |
| moved, the cells' absolute ledgers summed               | 4.8e-2     | 2.4e-2    |
| the partition repair's ledger, the same way             | 2.9e-3     | 2.9e-3    |
| smallest tag value, kg/kg                               | 1.4e-9     | 1.4e-9    |
| against the copies, L1 at 24 h, `tropo`/`strat`/`evap`  | 0.25/0.41/0.41% | 0.25/0.41/0.42% |

  - The model's fields are bit for bit the same under both rules (37 fields
    on D4-W, 24 on TRMM).
  - The part left out is the same, since it is the columns' total by
    construction. Only where it lands differs.
  - The moved ledger's gross over the cells is net over time in each cell
    (the review's point 5), so the halving is a lower bound on what the |m|
    rule moved beyond the same-sign rule's.
  - **On TRMM 0M, 6 h,** the follower leaves out about 1e-16 of the column's
    water, so there is no column total to place, and the rules agree to
    rounding.
      + The gross residual is 1.6e-15 under |m| and 3.6e-15 under the
        same-sign rule.
      + The moved ledger is 6.9e-3 in both. No tag goes negative.
      + Against the copies at 6 h: `pbl` 1.52%, `free` 0.83%, `evap` 1.72%, in
        both.
      + The tracer transport's and the copies' own gross residuals on the same
        case are 5.0e-4 at 6 h.

*`hpda2_compute`, 2026-09-24, D4-W driver. D4-W same-sign: job `13887329`, from
`../ClimaAtmosResiDyn-wedmf5r-run` at `5d1afcc0` (the record with #102 at
`5bfa7cea`). TRMM |m|: job `13887330`, from `../ClimaAtmosResiDyn-wedmf5-run`
at `71bd4061` (#102 at `fd07d902`). TRMM same-sign: job `13887331`, from
`5d1afcc0`. Reports and `analysis/water/w5r_rule_compare.py`'s output are in
`output/w5r/`.*

**W29. The tags' sedimentation cross blocks close W23's explicit-1M lag. With
one Newton iteration, the follower's residual after an hour falls from 7.9e-3
of the water to 2e-8. The model's fields are bit for bit the same.** This is
the owner's distinguishing experiment for #102's point 3, run on W23's column:
DYCOMS RF02, 1M, prognostic EDMF, microphysics stepped explicitly, ARS222, one
Newton iteration, one hour. Eight runs cover every combination of:
  - the cross blocks off (WP5b's control, `f8da0913`, the refusal lifted) or
    on (`c2bf8a62`);
  - the default mode or copies;
  - the tracer transport or the follower.

| run                        | net      | gross   | left out | repair  |
|:-------------------------- | --------:| -------:| --------:| -------:|
| default, follower, off     | +7.9e-3  | 8.5e-3  | +7.9e-3  | 1.8e-4  |
| default, follower, **on**  | −2.1e-8  | 5.7e-8  | −2.1e-8  | 2.2e-4  |
| default, tracer, off       | +7.7e-3  | 1.6e-2  |          | 2.3e-4  |
| default, tracer, on        | −1.5e-5  | 6.8e-3  |          | 2.3e-4  |
| copies, follower, off      | +7.9e-3  | 8.3e-3  | +7.9e-3  | 2.4e-4  |
| copies, follower, on       | −1.2e-8  | 5.3e-8  | −1.2e-8  | 2.6e-4  |
| copies, tracer, off        | +7.8e-3  | 9.7e-3  |          | 2.7e-4  |
| copies, tracer, on         | −1.3e-5  | 7.4e-3  |          | 2.7e-4  |

`repair` is the partition repair's ledger, summed as absolute values over the
cells, over the column's water. No tag goes negative in any run.

  - **The parent's fields** (ρ, ρq_tot, ρe_tot, ρq_rai, ρq_sno) are the same,
    value for value, in all eight runs.
  - **The net lag is gone under both transports.** Under the tracer transport
    the gross stays at 7e-3. That is its explicit advection's mismatch, which
    the follower removes.
  - **Default against copies** (L1 over the column, per tag, `tropo`, `strat`,
    `evap`):

    | transport | cross blocks off     | on                   |
    |:--------- |:-------------------- |:-------------------- |
    | follower  | 0.55%, 0.87%, 3.8%   | 0.29%, 0.72%, 5.8%   |
    | tracer    | 1.8%, 0.65%, 6.2%    | 0.46%, 0.76%, 6.4%   |

    The region tags agree better. The small source tag `evap` does not, but
    its first-hour budget is 10%. The copies' own rows in the updraft do not
    have the cross blocks yet, so the audit is not yet symmetric in the modes.
  - One column for one hour does not bound the lag elsewhere. D4-W for a day
    on the implicit path, in both modes, is the next check.

*`hpda2_compute`, 2026-09-24, jobs `13892249` to `13892256`. The script is
`analysis/water/wp5b_probe.jl`, run from `../ClimaAtmosResiDyn-wedmf5b-off` at
`f8da0913` and `../ClimaAtmosResiDyn-wedmf5b` at `c2bf8a62`. The compute nodes
print no commit. The final columns, the RESULT lines and
`analysis/water/wp5b_compare.py`'s output are in `output/wp5b_probe/`.*

*Qualified 2026-09-24, after the xhigh review and the owner's review of #105.*
  - "The model's fields are bit for bit the same" rests on the five fields the
    probe wrote, and `ρq_sno` is zero there. The integration test
    `tagging_water_increment_explicit` compares every model field of the
    tagged explicit column with its untagged twin, bit for bit, and passes.
  - With the cross blocks, the partition repair's ledger under the follower
    rose from 1.84e-4 to 2.22e-4 of the water (+21%). Not explained.
  - W29 shows closure and the lag the blocks remove on one column. It does not
    show that each tag's provenance is more accurate (`evap`, above).
  - The evidence is pinned as the tag `evidence/wp5b-w29`
    (`output/wp5b_probe/EVIDENCE.md`).
  - On the implicit path the blocks also lowered the increment test's one-hour
    gross residual under the follower from 4.1e-5 to 3.2e-8 (job `13893926`).

**W30. `pr_tag`'s cost after the batch, and the rain-out of negative areas on
TRMM (the owner's review of #104, findings 1 and 5).**
  - **The cost.** All 3N `pr_tag`, `prra_tag` and `prsn_tag` at one output
    time, at TRMM's initial state, now (one batch per output time) and at
    `53cd2db3` (each call redid the shared work):

    | mode    | tags | now      | at `53cd2db3` |
    |:------- | ----:| --------:| -------------:|
    | default | 2    | 2.8e-5 s | 1.5e-4 s      |
    | default | 8    | 1.7e-4 s | 8.5e-4 s      |
    | default | 32   | 2.5e-3 s | 1.3e-1 s      |
    | copies  | 2    | 2.9e-5 s | 1.2e-4 s      |
    | copies  | 8    | 2.0e-4 s | 5.7e-4 s      |

    After the batch, each diagnostic costs 5 to 8 µs at every size. The batch
    is one evaluation of the split. In the default mode it grows from 4.5e-5 s
    at 8 tags to 1.7e-3 s at 32, and 75% of that is the exchange's plume
    (`water_exchange_inputs!`, 2.6e-5 s to 1.3e-3 s). The split allocates
    5.7 kB at 8 tags and 1.5 MB at 32; at 3 tags the integration test measures
    at most 64 bytes on Julia 1.11. The model's exchange calls the same plume
    at every implicit evaluation. Where in the plume the growth arises is not
    isolated.
  - **Negative areas.** On W26's TRMM column over 6 h, after every one of 144
    steps (80 with rain), both modes: no rain-out from a subdomain whose area
    is negative, and no gain. So on this run the signed attribution is the
    physical rain-out at every accepted state. It bounds nothing for other
    cases.

*`hpda2_compute`, 2026-09-24, WP4a at `8af5f6f4`. Scripts
`analysis/water/wp4a_pr_tag_scaling.jl`, `wp4a_pr_tag_breakdown.jl` and
`wp4a_negative_area_probe.jl`; the RESULT lines and columns are in
`output/wp4a_review/`.*

**W31. On the implicit path the tags' sedimentation cross blocks cut D4-W's
one-day gross closure residual under the follower from 1.35e-4 to 7.3e-6,
and move nothing else measured by more than an eighth. The model's fields are
bit for bit the same.** WP5b at `0aad20ee` against W28's same-sign run, the
reference, both D4-W for 24 h with one Newton iteration:

| D4-W, 24 h                                             | W28 (no blocks) | with blocks |
|:------------------------------------------------------- | ---------:| ---------:|
| gross closure residual                                  | 1.35e-4   | 7.3e-6    |
| net closure residual                                    | +4.2e-5   | −5.2e-6   |
| left out (`increment_left_relative`)                    | −2.55e-5  | −7.1e-6   |
| moved, the cells' absolute ledgers summed               | 2.40e-2   | 2.68e-2   |
| smallest tag value, kg/kg                               | 1.4e-9    | 1.4e-9    |
| against the copies (`w3_d4w_copies`), L1 at 24 h, `tropo`/`strat`/`evap` | 0.25/0.41/0.42% | 0.25/0.41/0.41% |

  - All 37 of the parent's output fields are bit for bit the same.
  - The tags themselves move by at most 1.6e-4 (L1 at 24 h) against W28's.
  - Against the copies run with the blocks (`w5b_d4w_copies`) the L1 is
    0.26/0.41/0.41%.
  - The moved ledger's gross over the cells is net over time in each cell, so
    the 12% rise bounds, and does not measure, the extra water moved.

*`hpda2_compute`, 2026-09-24, D4-W driver, jobs `13893927` and `13893928`,
from `../ClimaAtmosResiDyn-wedmf5b-run` at `0d130367` (the record with WP5b at
`0aad20ee`). `compare_runs.py`'s and `w5r_rule_compare.py`'s output are in
`output/wp5b_d4w/`.*

## 2. Energy source tags: closure by transport

Under the default `tracer` transport the tags move as passive tracers while the
parent moves enthalpy. These entries measure what that leaves, and what the
audit, the repair and sedimentation change. The residual cause by cause is in
[design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md), section 1.2.

### 2.1 Pressure work makes the residual's growth

**E25. On the column, after its first ten minutes, pressure work is the whole
of the residual's growth.** `analysis/transport_ledger.jl` stepped
`c6_column_no_repair`, repair off, and split the growth at each step's start.
Over 50 minutes the residual moved 72,000 J m⁻², gross. Pressure work, the
parent moving `h_tot` while the tags move `e`, makes 72,260 of it; transport of
the residual already there 421; the per-tag van Leer limiter 268; everything
else 381. The parts sum to 72,250, with a regression slope of 1.000, and 0.9999
on pressure work alone. Bounded to one column, 50 minutes, no horizontal
transport. The first ten minutes are left out; in the first minute the residual
jumps by about 143,000 J m⁻², which a step-start estimate cannot see
(section 12). *Terrabyte login node, model code of `f3bbdb7b`;
`output/transport_ledger_column/`.*

**E31. On the sphere too, pressure work is nearly all of the residual's
growth.** The same script on `c6_sphere_no_repair` at its 400 s step, from the
end of the first hour. Over five hours the residual moved 4.86e20 J, gross.
Pressure work, vertical 6.67e20 and horizontal 3.28e20, is at least 4.56e20 J,
93% of the change. Hyperdiffusion is 1.18e19, 2.4%, and the per-tag limiter
9.47e16, 2e-4. The parts sum to 4.83e20 J, with a slope of 1.005. So an audit
of vertical transport alone would miss the horizontal part. Bounded to one
configuration and five hours. *Job `13399604`, script and model code of
`6af01228`; `output/transport_ledger_sphere/`.*

### 2.2 The enthalpy audit

The audit (#72, built at `511e00e9` from
[archive/2026-09-23/ENTHALPY_AUDIT_DESIGN.md](archive/2026-09-23/ENTHALPY_AUDIT_DESIGN.md))
moves the tags by their shares of the parent's enthalpy fluxes, in vertical and
horizontal advection and hyperdiffusion. It is refused without an offset.

**E34. Moved as enthalpy, the tags follow their total: the closure residual
stops growing, and on the column form A closes to 7e-6 J kg⁻¹.** C9 is C6's
column and C7's sphere with only the transport changed, repair off; `ta` is
identical to the reference.

| closure residual              | tracer, the reference | enthalpy, C9 |
|:----------------------------- | ---------------------:| ------------:|
| column, gross at 1 h, J m⁻²   | 166,016               | 2,695        |
| column, gross at 24 h, J m⁻²  | 2,442,276             | 2,284        |
| column, signed at 24 h, J m⁻² | −187,999              | +199         |
| sphere, gross at 1 h, J       | 1.30e21               | 2.54e20      |
| sphere, gross at 24 h, J      | 2.82e21               | 2.54e20      |
| sphere, signed at 24 h, J     | −2.82e19              | −1.16e17     |

After the first hour the residual does not grow: at 24 h it is 1,069 times
smaller on the column and 11 times on the sphere. What makes the first hour's residual is not
separated here; the initial adjustment of E13 and E25 is the candidate. Later
entries answer it: the one-iteration Newton increment, 99% of it on the column
(E39) and 83% on the sphere (E39b). Column form A closes to
6.6e-6 J kg⁻¹, against 60.7 under tracer transport (E26), so that gap was the
per-tag transport; form B stays at 3.3e-7 J m⁻². Sphere form A gets worse,
76.8 J kg⁻¹ at 24 h against C7's 20.2, where negative source tags are clamped
(E36). The audit costs about 5% per step: 2.54 ms against 2.43 on the column,
2.19 s against 2.07 on the sphere. Bounded to one column and one sphere, a day
each, repair off. *C9, jobs `13402392`, `13402393` at `0bfb5037`;
`analysis/c5_process_closure.jl`, `analysis/same_atmosphere.jl`;
`output/c9_column_enthalpy/`, `output/c9_sphere_enthalpy/`.*

**E35. With the repair on, the audit's sphere keeps its residual, and its form A
gets worse, not better.** C10 is C9's sphere with the repair on; `ta` is C9's.
The closure residual is C9's to four digits, 2.5357e20 J against 2.5359e20 at
24 h, since the repair keeps the partition's sum. Form A is 274 J kg⁻¹ at 24 h,
1.5e-2, against C9's 76.8 and C7's 20.2. The repair lifts negative source tags
by energy the other side of form A does not receive: `sfc` by up to 397 J kg⁻¹.
Its ledger at the worst node, 397.04, is what C9's `sfc` reaches there, −397.06.
The region tags trade up to ±16,294 J kg⁻¹, against ±30,920 under tracer
transport (E27). *Corrected on 2026-09-11:* E35 first quoted 54.9 J kg⁻¹ as form
A "with the repair's ledgers taken back out". The ledgers are not transported,
so that field is off by up to 22.0 J kg⁻¹ against C9, and by 219 under tracer
transport (section 12). *C10, job `13403083` at `7dc0a302`;
`analysis/c5_process_closure.jl`, `analysis/same_atmosphere.jl`;
`output/c10_sphere_enthalpy_repair/`; the correction by
`analysis/formA_mechanism.jl`.*

**E36. Under the audit, a negative source tag freezes at its node and sinks
faster: the clamp in the audit's transport.** An overlay's share is clamped at
zero, so a negative overlay neither moves nor loses, while its neighbours keep
pushing. C9's `sfc` minimum sits at one node from 12 h on, 43.7°N, 164.8°W,
250 m, and falls ever faster: −112, −172, −236, −310 and −397 J kg⁻¹ at 12, 15,
18, 21 and 24 h. C7's moves among four nodes and levels off at −208. At 24 h,
78% of the gap's absolute sum lies within one grid point of the points where
the source tags' negative parts add up to below −1 J kg⁻¹, on 39% of the points;
on C7, 11% on 51%. The gap cancels along levels, not within columns (E49). That
the clamp is the only cause is inferred from the code; a C9 twin with signed
overlay shares would decide it (section 13). *`analysis/formA_mechanism.jl`,
`formA_followup.jl`, `formA_last.jl` on C7, C9 and C10;
`output/formA_mechanism/`.*

**E37. C7's form-A gap under tracer transport is the per-tag van Leer limiter,
with a small part from the loss clamp.** C6's shared tags equal C7's, so C6's
first-order run, less `mp`, is C7 with a linear scheme. At C7's worst point its
first-order equivalent is −0.044 J kg⁻¹, against 20.2. First order removes
99.8% of the gap's absolute sum at 6 h and 97% at 24 h. The gap sits where
`sfc` falls from 17,404 to 463 to 0 J kg⁻¹ over the lowest three levels, and
grows close to the square of time. The loss clamp makes about 3% at 24 h,
peaking at 4.87 J kg⁻¹ where `sfc` is negative all day. This settles E30's open
point. *The scripts of E36.*

### 2.3 The repair and the region masks

The repair, on by default, keeps the tags non-negative where their total is
positive. The partition tags keep their sum, tags that carry a source are
clipped at zero, and every change goes to `e_src_fix_<name>`. It was built on
2026-09-10 with the implicit microphysics bracket (section 7).
`analysis/bracket_repair_smoke.jl` ran both on a DYCOMS column for two minutes
at 50 kJ kg⁻¹. The microphysics record read −568 J m⁻², where it had been zero.
The state was bit for bit the same with and without the repair, which clipped
the radiation tag's −2.9e-9 to zero. The signed residual at 120 s went from
−744 J m⁻², the tags overclaiming, to +382 J m⁻², a remainder that run did not
explain.

**E27. With the repair on, no tag goes negative on the sphere, and the region
tags trade a lot of energy to get there.** On C5's gray sphere, repair off, the
region tags reach −9,628 and −11,664 J kg⁻¹ and `sfc` −208. With the repair on,
the region tags' cumulative ledgers reach ±30,920 J kg⁻¹ at their worst points,
against maxima of about 220 kJ kg⁻¹. The tags that carry a source were lifted by
up to 707 J kg⁻¹ (`sfc`), 473 and 249 (`new_extratropics`, `new_tropics`) and 79
(`rad`). `ta` is identical with the repair on and off. Where the trades sit is
E46. *C6, jobs `13385452`, `13385453`.*

**E29. The region tags' negativity does not come from their vertical
upwinding.** With first-order upwinding they still reach −9,566 and
−11,588 J kg⁻¹, against −9,628 and −11,664 with van Leer. That leaves their
horizontal transport and hyperdiffusion, neither limited for tags, and the
finite-step loss; E19 points at transport. *C6, jobs `13385453`, `13385454`.*

**E46. The repair's large trades sit just beyond the edge where the two region
tags meet, and each tag is lifted only on the other's side.** On this grid the
2°-wide mask at 20° is a step between the rows at 18.0° and 23.1°. Under tracer
transport 96% of the tropics ledger's gross lies in the second and third rows
out from the step, 2% beside it. The extremes, ±30,915 J kg⁻¹, sit on the second
rows at the top level, 26.9 km. Under the audit 42% lies beside the step and 47%
in the next rows, and the extremes, ±16,294 J kg⁻¹, sit at 11 km. The repair
lifts each tag only beyond its own edge, in 100% of its gross under tracer
transport and 99.5% or 99.9% under the audit. The two ledgers cancel in every
cell to 7.3e-10 J kg⁻¹ or better. Which operator makes the undershoots is not
separated. *C6, jobs `13385452`, `13385453`; C9 and C10, jobs `13402393`,
`13403083`; `analysis/repair_trades.jl`; `output/repair_trades/`.*

**E48. With the region masks 10° wide, the repair never trades between the
region tags: the step of the 2° mask makes all of E46's trades.** The twin is
`c6_sphere_repair` with 10°-wide `tanh_latitude` regions, at `f399b9f8`; `ta` is
C6's. `e_src_fix_tropics` goes from ±30,915 J kg⁻¹ to 0, and the region ledger's
gross from 1 to 0 relative to C6's. The closure residual is −4.087e19 J against
−4.074e19, and form A's largest gap 148.781 J kg⁻¹ in both. A 10° mask never
reaches zero: the extratropics mask is 0.036 at the equator, where a 2° mask is
4e-9. So each region tag holds a few percent of the other region's energy. The
owner kept 2° on 2026-09-18 (decision 10, [DECISIONS.md](DECISIONS.md)). *Job
`13441633` at `f399b9f8`; `output/c6_sphere_wide_mask/`;
`analysis/wide_mask_trades.jl`, `analysis/same_atmosphere.jl`,
`analysis/c5_process_closure.jl`.*

### 2.4 Sedimentation and ice

Sedimentation moves the source tags since `91b9bbb9` (#70). Each face takes the
parent's sedimentation energy flux plus `c` times its mass flux, shared by the
cell that loses the energy. There is no Jacobian block.

**E32. Moved with the falling water, the tags follow sedimentation out of the
column.** `analysis/sedimentation_smoke.jl` runs `c6_column_repair` under 1M for
an hour, with the tags' sedimentation on and off; the model's state is identical.
The `precipitation` record is −1,327 J m⁻² net and 3,772 gross. Without the
transport the signed residual reaches −3,029 J m⁻² at 1 h; with it, +196 J m⁻²,
15 times smaller. The +196 is the loss rule acting on tracer transport's
residual, not the missing Jacobian block, whose lag is −7.8 J m⁻² (E39). The
gross residual barely changes, 177,377 against 179,609 J m⁻², since pressure
work makes it (E25). Bounded to one warm column, one hour, liquid only.
*Terrabyte login node, model code of `91b9bbb9`; `output/sedimentation_smoke/`.*

**E33. On a 1M column for a day, with sedimentation moving the tags, both
per-process checks hold, less tightly than on the 0M column.** C8 is C6's column
under 1M, repair on, with an `mp` tag and a `precipitation` record. Form B
closes to −5.3 J m⁻² of 897,043, 6e-6; what that is, is not separated here (later: the Newton lag, E43). Form A's
two splits agree to 117 J kg⁻¹ at 24 h, 7.1e-4, at 75 m, against C6's 60.7; it is not
separated here either (later: the per-tag transport, E43). The rain took 158,979 J m⁻² out of the column. The
gross residual at 24 h is 2.46e6 J m⁻², against 2.44e6 on the 0M column. *C8,
job `13401744` at `c11d1d3b`; `analysis/c5_process_closure.jl`;
`output/c8_column_1m/`.*

**E41. Falling ice takes sedimentation's upward branch in every cell, and the
partition stays closed through it.** Build checks on `PrecipitatingColumn` under
1M, 100 levels to 10 km, with the offset, on the login node. At t = 0 all 79
cells with cloud ice and all 69 with snow carry negative energy per kilogram,
down to −193 kJ kg⁻¹, so every face under falling ice takes the lower cell's
shares. The partition's sedimentation tendency matches the parent's to 5.7e-15
of its largest value, within 100 eps. Stepped six times at 10 s with the repair,
it closes to 1.6e-15, and every tag stays non-negative. 2M and 2MP3 do not
build: the model's own gate stops the cache (`precomputed_quantities.jl:160-167`),
and the tags play no part. *A design agent, login node, 2026-09-11;
`analysis/subgrid_light_check.jl 1M|2M|2MP3`, `analysis/subgrid_check_cold.jl 1M`;
`output/subgrid_build_checks/`.*

**E42. Through an hour of falling ice, the column stays closed and the tags stay
non-negative.** D1 is `PrecipitatingColumn` under 1M, 200 levels to 10 km, with
the offset and the repair on, for an hour. The signed residual is 0.29 J m⁻² of
6.37e8, 4.5e-10, constant after the first minute. The gross is 1.12e6 J m⁻²
after the first minute and 2.37e6 at 1 h, 3.7e-3, zero-sum; 42% of its growth is
in the ice layers. `lower`'s column integral above 5.6 km rises from 13,969 to
53,245 J m⁻². Form B closes to 0.14 J m⁻² of 95,023. As first written, E42 read
the gross as vertical diffusion's doing and could not separate the upward branch
from diffusion; E42b falsifies the first and separates the second
(section 12). Bounded to one column, one hour, ice that mostly sublimates in its
first minute. *D1, job `13404535` at `78586e39`; `analysis/c5_process_closure.jl`,
`analysis/d1_residual_profile.jl`; `output/d1_column_1m_ice/`.*

**E42b. Without vertical diffusion, the upward branch lifts about a fifth of
what D1's `lower` gained above its boundary. The gross residual is unchanged,
so vertical diffusion does not make it.** The twin is D1 with `vert_diff` and
`implicit_diffusion` off. `lower`'s rise above 5.6 km is 7,879 J m⁻², against
D1's 39,276. The gross residual is 1.119e6 against 1.118e6 J m⁻² after the first
minute and 2.350e6 against 2.370e6 at 1 h; the signed residual is 0.286 in both.
The next candidate for the gross is grid-mean vertical advection under tracer
transport, pressure work as in E25, untested (section 13). *D1's twin, job
`13412243` at `cf1e9c7c`; the scripts of E42; `output/d1_column_1m_ice_no_vdiff/`.*

## 3. The energy reference and the offset

### 3.1 The barrier: a total that is not positive

The donor rule shares a loss by `ρe_src_k / ρe_tot`. At the model's reference
that share is undefined over much of the domain.

**E1. The donor rule is inert over almost the whole domain.** Where
`ρe_tot ≤ 0`, `energy_source_fraction` returns zero, so the loss never runs
while production does. That is 96.7% of the DYCOMS column's volume and 43.276%
of a moist sphere's, the latter constant to the last digit over 24 h. *C0.*

**E2. A source tag goes negative, and the residual does not show it.** A source
tag reaches −209 J kg⁻¹ on the sphere while `e_src_res` shows nothing, because
the residual sums only the pure region tags. *C0.* E2 first put this down to
production accumulating without loss. With the loss running everywhere the tag
is as negative (E14), so that reading is superseded (section 12).

**E3. One level crossing changes the behaviour of the whole column.**
`max e_src_rad` rises for the seven hours before the transition from 30 to 29
non-positive levels, then falls by 137 J kg⁻¹ in the transition's hour. The tag
can lose only where a level supports a donor share. *C0.*

**E4. The closure residual reaches 13.5% of `∫|ρe_tot|` in one day**, growing
monotonically. *C0, C3, identically.*

**E5. The non-positive region is the troposphere, not a thin layer or a domain
artifact.** On the sphere the sign changes at the face at 13.02 km. The
r²-weighted volume below it is 0.4327600, against the closure table's
0.4327600052941768, eight digits without shared code. The column is negative at
all 30 levels, with a step at 825 m, the DYCOMS inversion. *C0,
`where_negative.jl`.*

**E6. The smallest shift making the field positive is 45.4 kJ kg⁻¹ on the column
and 100.4 kJ kg⁻¹ on the sphere.** Since the region is the bulk troposphere, the
shift cannot be small. *C0.*

**E9b. The barrier is 1.8× larger than the headline figure.** `c0_sphere_audit`,
`c0_sphere` with `audit: true`, measures `nonpositive_mass_fraction` 0.7839
against `nonpositive_fraction` 0.43276, a ratio of 1.811, and 0.7813 at t = 0. So
78.4%, not 43.3%, of `∫|ρe_tot|` sits where the donor share is undefined (M1).
*C0 audit.*

**E9c. The energy residual is directional, where water's is balanced (W11).**
`overclaimed_relative` 1.2245e-2 against `untagged_relative` 3.1795e-3, a ratio
of 3.85: production without loss. `orphaned_relative` is exactly 0.0. M2's
identity holds: 3.1795e-3 + 1.2245e-2 = 1.5424236987e-2 = `gross_relative`.
*C0 audit.*

**E10. The barrier is structural, not numerical.** No tolerance makes an
undefined quantity readable. Total energy has no physical zero, so a shift
relocates the arbitrariness. C1 tests whether a well-posed donor rule is
achievable, not whether the reading means something. An argument, not a run.

### 3.2 The convention

**R1. The convention is enthalpy zero, not internal-energy zero.**
`internal_energy_dry(T) = cv_d·(T − T_0) − R_d·T_0`, and
`internal_energy_dry(T_0 = 273.16)` returns −78396.92, `−R_d·T_0` at `R_d` =
287.0. *Read from Thermodynamics on Levante.*

**R2. The 7.8e4 J kg⁻¹ gap C0 could not account for is that term: a convention,
not an initialisation error.** `TD.total_energy` on the DYCOMS surface state
returns −44,009 against the field's −43,125, the 2% being the approximated
state. C0's 43.276% stands.

**R3. ClimaAtmos already carries the convention in its analytic Jacobian.**
`manual_sparse_jacobian.jl:835` and `:1805` write `T_0 * cp_d`, not
`T_0 * cv_d`.

**R4. The derivative that sets any reference shift is `−cp_d`,** so lowering
`T_0` is more effective than the textbook reading by `γ = cp_d/cv_d` = 1.4. The
sphere needs `ΔT_0` = 100.0 K and the column 45.2 K.

**R5. `T_0` is not a free datum.** `LH_v(T) = LH_v0 + (cp_v − cp_l)(T − T_0)`,
with `cp_v − cp_l` = −2322. Moving `T_0` to 173.2 K with `LH_v0` fixed drops
`LH_v` at 288.3 K by 9.4%, a change of physics. Confirmed against the package:
`latent_heat_vapor(288.3)` returns 2.46564492e6 against a predicted
2,465,644.92.

**R6. Everything physical depends on `T_0` only through `LH_0 − Δcp·T_0`, so the
shift has an exact invariance.** The map `T_0 → T_0 + δ`,
`LH_v0 → LH_v0 + (cp_v − cp_l)·δ`, `LH_s0 → LH_s0 + (cp_v − cp_i)·δ` leaves every
latent heat and the saturation vapour pressure unchanged, and moves `e_int` by
`−cp_d·δ`. `LH_f0 = LH_s0 − LH_v0` follows.

**R7. C1 therefore needs no code change.** `T_0`, `LH_v0` and `LH_s0` are
settable; `LH_f0`, every `cv_*` and `e_int_v0` are derived.
`create_parameters.jl:75` builds the parameters from the TOML dict. C1 is three
TOML entries plus the owner's approval.

**R8. C1's acceptance test is exact, and it passes.** `LH_v(288.3)`,
`LH_f(273.16)` and `p_sat(288.3)` must stay 2.46564492e6, 333600.0 and
1721.1532852305072. `analysis/c1_acceptance.jl` builds the parameters from
`toml/tag_closure_c1_reference.toml` as a run does and makes 38 checks from
150 K to 330 K, over liquid, ice and the mixture ramp. All pass; the worst
relative change is 9.2e-16. *Run on terrabyte, 2026-09-10.* The before-values
are in [archive/2026-09-23/C1_reference_shift.md](archive/2026-09-23/C1_reference_shift.md).

**R9. The shift is not a constant.** Under C1's map every water phase moves by
`cp_l·|δ|`, so the coefficient is `c(q) = (1 − q_tot)·cp_d + q_tot·cp_l`, from
1004.5 dry to 1068.0 at `q_tot` = 0.02, a 6.3% spread. Positivity must be
checked pointwise. At t = 0 the parent's minimum is −100,416 J kg⁻¹ in the
extratropics against −23,686 in the tropics: the most negative cells are cold
and dry, so the sizing rests on the dry coefficient.
*`analysis/c1_acceptance.jl`; the minima are C0's region tags at t = 0.* The
coefficient and the location first recorded here were wrong (section 12).

**R10. Shifting only the share's denominator should be dropped rather than
costed.** The region tags sum to `ρe_tot`, not `ρe_tot + c`, so where `e < 0`
the loss adds energy, diverging as `e` approaches `−c`. That rules out this
shape, not the route: rebasing the tags onto the shifted total too is the
offset (3.3).

**R11. C1's remaining costs are firm rather than conditional.** The shift must
clear the tropospheric minimum (E6). A source tag's discriminating share goes as
`1/(e + c)`. And the check normalises by `∫|ρe_tot|`, which the shift grows
2.85× (E15), so an unchanged residual reads as an improvement. It was first
recorded as about 2.2× (section 12). Over a day, doubling the offset moves the
source tag by about 1% (E19).

### 3.3 The shift and the offset, measured

C1 moved the model's reference by R6's map. The offset instead gives the tags a
shadow total `E = ρe_tot + c·ρ`, which the model never uses; `c` = 110,495
J kg⁻¹ matches C1's shift. Per-process closure holds once each process's
increment includes `c` times its change in mass. The offset is the route the
series adopted, and the owner kept `c` = 110,495 J kg⁻¹ for every G1 and G2 run
([DECISIONS.md](DECISIONS.md)). A rule for choosing `c`, and its cost in memory,
is in [design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md), section 3.3.

**E11. Under C1's shift the parent is positive everywhere, all day.**
`nonpositive_fraction`, `nonpositive_mass_fraction` and `orphaned` are 0.0 at
every hourly sample, so the loss runs over the whole domain. The shifted
atmosphere differs from the unshifted by up to 1.1e-3 in `uₕ` (E16). *C1,
against `c0_sphere_audit` re-run on terrabyte, as are E12 to E15.*

**E12. With the loss running, the residual stops being directional and grows
more slowly.** The audit's overclaim-to-undertag ratio stays at 1.002 to 1.033,
where the unshifted run climbs from 1.49 to 3.85. `gross_residual` at 24 h is
1.846e21 against 2.626e21, 0.70 of the unshifted. *C1.*

**E13. Both runs make the same jump in the first hour, so that part does not
depend on the reference.** `gross_residual` goes from about 1e7 at t = 0 to
1.2485e21 in C1 and 1.2343e21 unshifted at 1 h, 1.2% apart; in C1 that is 68%
of the day's residual. The candidate, the `p·u` difference between enthalpy and
tracer transport, was measured after the first minutes by E25 and E31. The
first-minute jump is open (section 13). *C1.*

**E14. A positive parent does not keep the tags non-negative.** `sfc` reaches
−219.9 J kg⁻¹ at 24 h, against −209.2 unshifted. The region tags reach −11,575
(`tropics`, 7 h) and −9,632 (`extratropics`, 4 h), with the parent positive
everywhere. Finite-step donor loss or unlimited transport, not separated
(section 13). *C1.*

**E15. `gross_relative` improves 4.06×, and 2.85× of that is the scale.** It is
0.00380 against 0.01542 at 24 h. `∫|ρe_tot|` is 2.84× larger at t = 0 and 2.85×
at 24 h. E12's 0.70 is the comparison that means something. *C1.*

**E16. The C1 shift is not a pure relabelling in the discrete model. The leading
cause is the limiter on vertical energy transport, most but not all of it.**
`run_c1_twin.jl` runs C1 with and without the shift in one process. The
differences after one 400 s step, relative to each field's maximum:

| both halves with                   | `ρ`     | `ρq_tot` | `uₕ`    | `u₃`    |
|:---------------------------------- | -------:| --------:| -------:| -------:|
| C1's settings                      | 3.8e-5  | 7.8e-6   | 1.3e-4  | 3.5e-4  |
| a converged Newton solve           | 3.6e-5  | 7.4e-6   | 1.3e-4  | 4.1e-4  |
| `energy_q_tot_upwinding: none`     | 3.7e-8  | 5.7e-10  | 1.8e-7  | 4.7e-5  |
| that, and no surface-flux tendency | 3.71e-8 | 4.4e-10  | 1.75e-7 | 4.67e-5 |

So it is not the implicit solve. It is mostly the `T_post_imp!` hook
(`implicit_tendency.jl:335-372`), whose van Leer limiter acts on `h_tot`, to
which the shift adds `(cp_l − cp_d)·|δ|·q_tot`. The rest is not the surface-flux
path; with the limiter off, `ρ`'s difference still grows to 5.8e-6 by 5 h. What
starts it is open (section 13). The owner took up no fifth twin on 2026-09-10,
because the offset leaves the model alone. *Jobs `13383683`, `13384080`,
`13384884`, `13385303`, at `72a1bc6a`, `4a40838f`, `9b00e7b1`, `9e796fac`;
`output/twin_c1/`, `twin_c1_newton/`, `twin_c1_limiter_off/`,
`twin_c1_limiter_off_no_sfc/`.*

**E17. An offset in the tags' total leaves the atmosphere untouched.** The two
C4 runs differ only in `c`, 110,495 and 220,990 J kg⁻¹. Their `ta` is identical
in every value, largest difference 0.0, and `nonpositive_fraction` is 0.0 at
every sample. On a DYCOMS column the state is bit for bit with and without an
offset. *C4, jobs `13384913`, `13384914`; `analysis/same_atmosphere.jl`,
`analysis/offset_smoke.jl`.*

**E18. C1's tag results belong to the tag rule, not to its changed
atmosphere.** C4 at C1's size reproduces them: `gross_residual` within 0.7% of
C1's all day, and 0.70 of the baseline at 24 h. The audit reads 1.001 at 3 h and
1.013 at 24 h, against C1's 1.002 and 1.033. The region tag minima are −11,575
and −9,631 J kg⁻¹, against C1's −11,575 and −9,632, and `sfc` reaches −212.5
against C1's −219.9. So E11 to E14 hold without E16. *C4, against C1 and the
terrabyte baseline.*

**E19. Doubling the offset barely moves the source tag, and makes the region
tags more negative.** On the identical atmosphere, `c` = 220,990 against 110,495
moves the absolute residual by +0.9% and `sfc`'s maximum by +1.1%, 19,706
against 19,486; the audit balance goes from 1.013 to 1.009. The region tags'
minima grow 1.51×, to −17,505 and −14,563, as transport undershoots that scale
with a region tag's energy would, an argument, not a measurement. *C4 at both
offsets.*

**E71. Doubling the offset `c` leaves the model bit for bit and nearly doubles
the prototype's remainder on D4; the source tags change by 4 to 6% in a day.**
ATTRIBUTION_PATH.md's V5. `g1_inc_d4_2c` is `g1_inc_d4` with `c` = 220,990 J/kg;
`ta` and `rhoa` are bit for bit. The remainder is 509 J/m² gross at 24 h against
267. Written as `A + c·B`, about 90% is `c·B`, `c` times a change of the
column's mass the tags' tendencies lack (E64). In integral at 24 h the tags
change by: `rad` +4.4%, `sfc` +6.3%, `sub` +4.5%, `new_strat` +4.2%, `new_tropo`
+6.0%, `strat` +177%, `tropo` +152%. So `c` sets the loss rule's memory, and a
per-tag result must state its `c`. *Job `13509167`, `hpda2_test`, 2026-09-19,
from `../ClimaAtmosResiDyn-inc-run2` at `c0bc637f`; `output/g1_inc_d4_2c`.*

## 4. EDMF and the updrafts

Under prognostic EDMF the tags first saw none of the sub-grid fluxes (E40). The
owner decided on 2026-09-11 to refuse `prognostic_edmfx` with tags at once
(C1a, in #70) and to share the sub-grid fluxes later (C1b, #91). The design is
[design/SUBGRID_AND_MICROPHYSICS_DESIGN.md](design/SUBGRID_AND_MICROPHYSICS_DESIGN.md);
D4's residual split by layer is in
[design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md), section 1.3.
Elsewhere: the EDMF build, E44 to E44e (section 10); Float32 on D4, E55
(section 6); the implicit channel on D4, E59 and E61 to E66 (section 5); the
updraft gap, E68, E72, E73 (section 9).

**E40. Under `prognostic_edmfx` the tags got none of the sub-grid mass flux, and
every shipped EDMF configuration failed with tags.** Build checks on the DYCOMS
RF02 EDMF column under 1M, with the offset, on the login node; nothing stepped.
Every shipped config sets `edmfx_vertical_diffusion: true`, which applies the
grid mean's tendency to the updraft's copy of every tracer
(`edmfx_sgs_flux.jl:403-409`). No tag has one, so the call fails. On a
synthetic updraft the sub-grid mass flux changes `E` by 11.5 W m⁻³ summed, and
the partition by exactly zero. Sedimentation under EDMF misses the parent's by
3.4e-3 of its largest value, because the tags did not share the updraft and
environment corrections (`water_advection.jl:127-186`). A full EDMF simulation
with tags did not build in 15 minutes on the login node, with the cache at
108 s. On `hpda2_test` the D4 pair did not build in two hours either, reaching
6.7 GB (jobs `13404536`, `13404537`); E44 to E44e find why. Bounded to one
column, one synthetic state, tendencies called one at a time. *A design agent,
login node, 2026-09-11; `analysis/subgrid_light_check.jl edmf`,
`analysis/subgrid_check_edmf.jl`; `output/subgrid_build_checks/`.*

**E53. With C1b, the EDMF columns run with tags. The gross residual is zero-sum
and stays near half a percent, and the records close the column's budget.**
C1b's validation runs, from `fe69cd06`. D5 is TRMM LBA deep convection with ice,
82 levels, for 6 h.

| run                                             | `relative` | `gross_residual`, J/m² | `gross_relative` | untagged / overclaimed, J/m² | form B gap, J/m² |
|:----------------------------------------------- | ----------:| ----------------------:| ----------------:|:---------------------------- | ----------------:|
| `d4_column_edmf`, tracer                        | 9.2e-5     | 6.71e5                 | 5.9e-3           | 3.41e5 / 3.30e5              | 0.49 of 8.9e5    |
| `d4_column_edmf_enthalpy`                       | 3.7e-4     | 5.41e5                 | 4.7e-3           | 2.92e5 / 2.50e5              | 0.49 of 8.9e5    |
| `d4_column_edmf_vd`, the updrafts' diffusion on | 4.5e-4     | 6.83e5                 | 6.0e-3           | 3.67e5 / 3.16e5              | 1.4 of 9.3e5     |
| `d5_column_edmf_ice`, 6 h                       | -8.2e-7    | 2.76e6                 | 3.1e-3           | 1.380e6 / 1.381e6            | -317 of 1.05e7   |

Untagged and overclaimed are about equal, and nothing is orphaned: a transport
mismatch, not a missing process. Form A's gap cancels in the column. `ta` and
`rhoa` are bit for bit in the D4 pair. The audit leaves most of D4's residual,
5.4e5 J/m² against C9's 2,284 (E34). It did not reach the EDMF eddy diffusion,
inferred here to make the remainder; E59 to E62 follow that up. How much C1b removed is not measured,
since D4 did not build without it before #76. E59's base is 17% higher and not
interchangeable (section 12). *Jobs `13503558` to `13503561`, `hpda2_test`,
2026-09-18, from `../ClimaAtmosResiDyn-c1b-val` at `fe69cd06`;
`analysis/reduce_run.jl`, `analysis/c5_process_closure.jl`;
`output/d4_column_edmf/`, `d4_column_edmf_enthalpy/`, `d4_column_edmf_vd/`,
`d5_column_edmf_ice/`.*

## 5. The implicit channel and the increment prototype

The stepper takes one Newton iteration per stage. With one iteration a stage's
implicit contribution, `T_imp[i] = (U − temp)/dtγ` in ClimaTimeSteppers'
`imex_ark.jl`, is the increment linearised about the stage's initial guess. The
tags and the records have no cross blocks in the Jacobian, so they take their
increments at the initial guess, while `ρe_tot` also gets the Jacobian's
coupling. The prototype `enthalpy_increment` makes the tags follow the parent's
implicit increment; its ledger is `e_src_inc_left` and `e_src_inc_moved`. The
numerics are in [design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md),
section 2.

**E39. The audit's first-hour residual and C8's form-B remainder are the
one-iteration Newton increment.** A reviewer stepped C9's column:

| variant                                      | gross after the first step | gross at 1 h, J m⁻² |
|:-------------------------------------------- | --------------------------:| -------------------:|
| one Newton iteration, as run                 | 2,675                      | 2,695               |
| Newton converged (10 iterations, rtol 1e-10) | 25                         | 20.5                |
| no post-Newton upwind correction             | 2,729                      | 2,757               |
| both                                         | 7.8                        | 13.1                |
| a 5 s step                                   | 2,169 at 5 s               | 2,239               |

98% of the first hour's residual is made in the first 10 s step, during the
initial adjustment, and converging removes 99% of it. After the first hour the
loss rule alone reproduces C9's column. On the sphere 69% of the 24 h residual's
gross is in the top two levels, by an approximate mass weighting. C8's form-B
remainder is the same lag in the records: per step it tracks `dtγ` times the
precipitation record's rate, with a correlation of 0.9945. E32's +196 J m⁻² is
the loss rule; the missing block's lag is −7.8 J m⁻² at 600 s. *A reviewer
agent on the terrabyte login node, 2026-09-11; `analysis/first_hour_0m.jl`,
`c8_variants.jl`, `formb_vs_flux.py`, `after_first_hour.py`,
`signed_by_loss_rule.py`, `sphere_levels.py`; `output/newton_lag/`.*

**E39b. On the sphere, the one Newton iteration makes 83% of the audit's
first-hour residual.** `analysis/first_hour_sphere.jl` steps C9's sphere for two
hours, as run and converged (10 iterations, rtol 1e-10). The gross at 1 h is
2.5352e20 J with one iteration and 4.24e19 converged, 17% left; on the column 1%
was left. The first 400 s step makes nearly all of it. What the converged 17%
is, is open (section 13). *Job `13408404` at `78586e39`;
`output/newton_lag/first_hour_sphere_slurm/`.*

**E43. On the 1M column over a day, the audit keeps form A below
4.4e-7 J kg⁻¹, and a converged Newton solve takes form B to −3.8e-3 J m⁻².**
`analysis/c8_variants.jl`, C8's column in four variants; converged is 10
iterations to rtol 1e-10.

| variant                                 | length | gross residual at the end, J m⁻² | form B at the end, J m⁻² | form A, largest, J kg⁻¹ |
|:--------------------------------------- |:------ | --------------------------------:| ------------------------:| -----------------------:|
| tracer, one Newton iteration, as C8 ran | 1 h    | 177,377                          | −0.80                    | 7.9e-3                  |
| tracer, converged                       | 1 h    | 177,342                          | −1.8e-4                  | 7.9e-3                  |
| enthalpy, one Newton iteration          | 24 h   | 193                              | −5.29                    | 4.3e-7                  |
| enthalpy, converged                     | 24 h   | 12.0                             | −3.8e-3                  | 2.8e-7                  |

So C8's form-A gap is the per-tag transport, and its form-B remainder the Newton
lag. Under tracer transport a converged solve does not shrink the residual,
because pressure work makes it. *Job `13408403` at `78586e39`;
`output/newton_lag/c8_variants_slurm/`.*

**E59. C1c, as built, makes the EDMF column's residual under the enthalpy audit
larger, in all three placements.** D4 under `enthalpy` for a day, from four
checkouts that differ only in C1c.

| gross residual, J/m²                                       | 1 h    | 4 h    | 12 h   | 24 h   | `gross_relative` at 24 h |
|:---------------------------------------------------------- | ------:| ------:| ------:| ------:| ------------------------:|
| base, `main`: the tags diffuse as tracers                  | 1.68e5 | 3.27e5 | 4.61e5 | 6.32e5 | 5.5e-3                   |
| option 1: the share beside the parent, no Jacobian block   | 1.98e5 | 9.29e5 | 3.25e6 | 6.71e6 | 5.9e-2                   |
| option 2: option 1 with the tracer-diffusion blocks kept   | 5.05e4 | 2.26e5 | 6.49e5 | 1.18e6 | 1.0e-2                   |
| option 3: option 1 with the share in the explicit tendency | 5.67e4 | 2.52e5 | 7.90e5 | 1.46e6 | 1.3e-2                   |

C1c removes the form mismatch at first, then each option grows about linearly
and passes the base after 4 to 6 hours. The parent's eddy diffusion is implicit
and stiff, and the tags' share does not follow its implicit update. Option 2
also moves the repair 400 times more. `ta` is identical in all four runs. The
base is 17% above E53's 5.41e5, since E53 ran before #89 (section 12). C1c is
not to be opened as a pull request in this form; it is shelved in
[BACKLOG.md](BACKLOG.md), replaced by following the parent's increment. A
scalar model of the stepper that reproduces the ordering is in
[design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md), section 2.2. *Jobs
`13504651` to `13504654`, `hpda2_test`, 2026-09-18, from
`../ClimaAtmosResiDyn-c1c-{base,opt1,opt2,opt3}`: `main` at `50b2a4d2`, C1c at
`9aeb5205` with the variants' patches; `output/c1c_*_d4_enthalpy/`.*

**E61. Most of C1c's drift is the implicit timing gap: with a converged Newton
solve, option 1's residual at 12 h is 14 times smaller.** Option 1 with up to
ten iterations to rtol 1e-8, for 12 hours: 4.51e4, 8.49e4, 1.66e5 and
2.32e5 J/m² at 1, 4, 8 and 12 h, against 1.98e5, 9.29e5, 2.00e6 and 3.25e6
with one iteration, and the base's 1.68e5, 3.27e5, 3.20e5 and 4.61e5. It still
grows; what is left is not separated. A converged solve changes the trajectory and
costs several times the step, so it is a diagnostic, not the path (to-do item
R5). *Job `13504771`, `hpda2_test`, 2026-09-19, from
`../ClimaAtmosResiDyn-c1c-opt1` at `9aeb5205`;
`output/c1c_opt1_newton_d4_enthalpy/`.*

**E62. Following the parent's increment closes the EDMF column: 267 J/m² at 24 h
against 6.32e5, with the model bit for bit.** D4 under `enthalpy_increment`,
the prototype at `35042f33`, against `c1c_base_d4_enthalpy` (E59).

| gross residual, J/m²            | 1 h    | 4 h    | 12 h   | 24 h   | `gross_relative` at 24 h |
|:------------------------------- | ------:| ------:| ------:| ------:| ------------------------:|
| base, `enthalpy` (E59)          | 1.68e5 | 3.27e5 | 4.61e5 | 6.32e5 | 5.5e-3                   |
| prototype, `enthalpy_increment` | 92.8   | 112    | 192    | 267    | 2.4e-6                   |

G1's criterion 1 is met: 37 times below the target of 1e4, and the second
12 hours add 75 J/m² to the first's 192. The residual is zero-sum, −0.53 J/m²
signed. The base's free-troposphere step, row 3d of ATTRIBUTION_PATH.md, is
gone. `ta` and `rhoa` are bit for bit the base's at all 25 hours (criterion 3,
the run half). The tags differ from the base's by at most 1.7% pointwise. *Job
`13504818`, `hpda2_test`, 2026-09-19, from `../ClimaAtmosResiDyn-inc-run` at
`35042f33`; `output/inc_d4_enthalpy_increment/`, with
`analysis/increment/d4_compare.py` and `tag_correctness.py`.*

**E64. The prototype's remainder on D4 is the one-iteration solve's column
totals, less what the loss rule flushes. No process the tags miss shows above
1 J/m².** `g1_inc_d4` reruns E62 with the ledger and gives 266.942 J/m² at
24 h, with `ta` and `rhoa` bit for bit. `other = e_src_res − e_src_inc_left`.

| 24 h, J/m², signed (gross)          | below 550 m  | 550 to 800 m | above 800 m | column      |
|:----------------------------------- | ------------:| ------------:| -----------:| -----------:|
| residual `e_src_res`                | +117.6 (143) | −97.8 (103)  | −20.3 (20)  | −0.5 (267)  |
| left in place by the correction     | +117.8 (144) | −142.3 (148) | −21.0 (21)  | −45.5 (313) |
| other                               | −0.24        | +44.5        | +0.76       | +45.0 (46)  |
| the loss rule's flushing, predicted | −0.24        | +43.5        | +0.73       | +44.0       |

The column-total part, 313 J/m² gross, is what the correction cannot move within
a column. With ten iterations to rtol 1e-8 (`g1_inc_newton_d4`) the whole
residual is 0.080 J/m² at 24 h, so it comes from the one-iteration solve. Its
candidates are sedimentation through the surface and the 1M sink, not separated.
`other` is the loss rule's flushing. The correction moves far more than it
leaves: `e_src_inc_moved` is 3.3e7 J/m² gross at 24 h. So G1's criterion 2 is
met. *Jobs `13504889` (`g1_inc_d4`), `13504890` (`g1_inc_newton_d4`),
`hpda2_test`, 2026-09-19, from `../ClimaAtmosResiDyn-inc-run2` at `c0bc637f`;
`output/g1_inc_d4/`, `output/g1_inc_newton_d4/`, with `remainder_split.txt`
from `analysis/increment/remainder_split.py`.*

**E65. In Float32 the prototype closes D4 to 607 J/m², 2.3 times its Float64
residual, with the model bit for bit.** `g1_inc_d4_float32` against
`g1_base_d4_float32`, both Float32: the base reads 1.68e5, 3.12e5, 5.19e5 and
7.53e5 J/m² at 1, 4, 12 and 24 h; the prototype 120, 222, 439 and 607; the
prototype in Float64 (E62) 92.8, 112, 192 and 267. G1's criterion 5 is met:
within ten times the Float64 residual (2,670). `ta` and `rhoa` are bit for bit
the Float32 base's. `other` does not follow the loss rule here; its size fits
Float32 rounding, inferred, not separated. *Jobs `13504891` (prototype,
`c0bc637f`) and `13504828` (base, `main` at `50b2a4d2`), `hpda2_test`,
2026-09-19; `output/g1_inc_d4_float32/`, `output/g1_base_d4_float32/`.*

**E66. Per tag, the prototype's error from its one-iteration solve is 0.1% for
the region tags and 1 to 6% for the source tags. Against a reference that shares
each flux by its donor, the tags differ by far more, and that difference is the
mixing convention, not an error.** G1's criterion 4 on D4. The reference is
C1c's option 1 converged, every implicit flux shared at the tendency level by
its donor. With ten fixed iterations, `g1_ref_newton10_d4` and
`g1_inc_newton10_d4` have `ta` and `rhoa` bit for bit.

| per tag at 24 h                             | `rad` | `sfc` | `sub` | `strat` | `tropo` | `new_strat` | `new_tropo` |
|:------------------------------------------- | -----:| -----:| -----:| -------:| -------:| -----------:| -----------:|
| against the reference, L1                   | 0.68  | 1.26  | 1.17  | 0.12    | 0.08    | 0.97        | 1.03        |
| against the reference, integral             | −3.2% | −2.4% | +18%  | +3.4%   | −2.5%   | +12%        | −2.0%       |
| one iteration against converged, at 1 h, L1 | 0.010 | 0.056 | 0.046 | 0.0011  | 0.0014  | 0.034       | 0.047       |
| one iteration against converged, at 1 h, L∞ | 0.014 | 0.12  | 0.038 | 0.0051  | 0.0059  | 0.023       | 0.12        |

The reference mixes no provenance where the net flux is small; the prototype's
tags diffuse as tracers through the well-mixed boundary layer. So the first two
rows measure the convention ([design/TRACER_AND_FLUX.md](design/TRACER_AND_FLUX.md);
ATTRIBUTION_PATH.md, sections 3.4 and 3.5). The reference leaves 5.99e5 J/m² of
its own residual. The last two rows are the solve's effect, measured at 1 h
while the two atmospheres still nearly agree. The converged prototype closes to
0.0016 J/m² at 24 h. The threshold, proposed here, was set by the owner on
2026-09-20 ([DECISIONS.md](DECISIONS.md)): at 1 h, L1 at most 1% for the region
tags and 10% for the source tags, L∞ at most 25%. Measured: 0.14%, 5.6% and 12%.
*Jobs `13504926` (reference, `../ClimaAtmosResiDyn-c1c-opt1` at `9aeb5205`) and
`13504927` (prototype, `c0bc637f`), `hpda2_test`, 2026-09-19;
`output/g1_inc_newton10_d4/tags_against_reference.txt`,
`output/inc_d4_enthalpy_increment/tags_against_converged.txt`, from
`analysis/increment/tag_correctness.py`.*

**E67. Under a deep atmosphere the correction put 0.4% of each cell's move in
the wrong place, until its flux was scaled by the face areas.** On the smallest
test sphere, 30 km deep, the top face is 1/0.9906 times the bottom one. With a
set increment, the partition change and the ledger's moved part differed by up
to 4.7e-6 J/m³, 0.41% of the move, before the fix, and by 2e-11 after it. The
error would have gone into `e_src_res`. The fix scales the flux by the bottom
face's area over each face's own (`04d63916`, on #94); on a flat grid nothing
changes. *Jobs `13504953` (fixed) and `13504956` (`c0bc637f`), `hpda2_test`,
2026-09-19; `analysis/increment/sphere_increment_deep.jl`.*

## 6. Parity, Float32, MPI and restarts

A configuration upstream can run must give bit for bit the same results in the
fork (AGENTS.md, "Fork parity with upstream"). Elsewhere: Float32 on a water
column, W4; the prototype in Float32, E65; the sphere's Float32 rounding, E70.

**E45. In Float32, C7's sphere closes as it does in Float64, to the last place
the Float32 integrals hold.** V3 here is C7, the 0M sphere for a day, with
`FLOAT_TYPE: Float32`, at `297eda4c`. At 24 h the closure residual is
−2.8247e19 J against C7's −2.8227e19, `gross_relative` 5.8892e-3 against
5.8893e-3, form A's largest gap 20.2146 J kg⁻¹ against 20.2127, and the
`solve!` wall time 444.4 s against 448.0 s. In steps of a Float32 total the two
residuals lie at most 3.4 apart in any hour. Rounding sets a floor near 1e-7:
the t = 0 residual is one step, 7.5e-8 of the total. This settles W4's sphere
question for a day. Not covered: longer runs, the audit, the repair, 1M and a
GPU, in Float32. *Job `13440822` at `297eda4c`, against C7, job `13399601`;
`output/v3_sphere_float32/`; `analysis/reduce_run.jl`,
`analysis/c5_process_closure.jl`, `analysis/float_type_compare.jl`.*

**E47. On 4 MPI ranks, C7's sphere closes as it does on one process, to
rounding.** MP1 is C7 on 4 ranks with `srun --mpi=pmix`. After t = 0 the largest
relative differences are 2.1e-14 in the audit table, 9.2e-13 in form A, 9.3e-13
in the tag extrema, 2.5e-13 in the record extrema, and 7.7e-11 in the closure
residual at 1 h. `ta` differs by at most 1.6e-12 K. The solve is 3.8× faster,
117.4 s against 448.0 s. Not covered: other rank counts, more than one node, a
restart across rank counts. *MP1, job `13440991` at `c2842ba6`;
`output/mp1_sphere_4ranks/`, `analysis/float_type_compare.jl`,
`analysis/same_atmosphere.jl`.*

**E51. With no diagnostic on, the fork after the merge of upstream v0.42.11
gives upstream's results bit for bit, and so does C1b against `main`.** Both
checks compare the end state and one implicit, remaining and limiter tendency
with `isequal`. #89: the fork at `d83ffcc3` against upstream `d331fe30`, on the
EDMF column with 1M for 1 h, a DYCOMS 1M column for 10 min, and B1's 0M wave
without tags for a day, all bit for bit. C1b: `main` at `38661891` against C1b
at `fe69cd06`, on the two columns, bit for bit. Not covered: diagnostics,
restarts, MPI, GPU, Float32, the SEM limiter, a prescribed flow, other
radiation, a slab surface, topography. `analysis/parity/` was hardened after
these runs. *Job `13503291`, `hpda2_test`, node `hpdar03c01s11`, 2026-09-18;
the C1b check on the login node; `output/parity_89_d331fe3/`,
`output/parity_c1b_main/`.*

**E54. A restart carries the tags and the records exactly, but the model itself
does not restart this column bit for bit, even with
`reproducible_restart: true`.** V5 ran C5's column for a day, and again from its
checkpoint at 12 h, from #92 at `e4e9e5b3`. At the restart the tags are restored
exactly. At 24 h every model field differs: `ρ` by 1.5e-10 of its largest value,
`uₕ` by 2e-11, `ρe_tot` by 1.7e-9, `ρq_tot` by 8e-10, `u₃` by 3e-9. The tags
differ from 4e-11 to 1.4e-8. The closure continues to 4e-9 in `residual` and
8e-10 in `gross_residual`. So V5's criterion is not met, for a reason outside
the tags (E58). *Jobs `13503985`, `13503986`, `hpda2_test`, 2026-09-18, from
`../ClimaAtmosResiDyn-c2-val` at `e4e9e5b3`; `analysis/v5_compare_h5.py`;
`output/v5_c5_continuous/`, `output/v5_c5_restarted/`.*

**E55. In Float32, C1b's EDMF column keeps the size of the Float64 residual over
the day, but the residual tilts toward overclaiming.**
`d4_column_edmf_vd_float32`, from #91 at `9dd30a90`. `gross_relative` at 24 h is
6.93e-3 against 5.98e-3, and the day's means 4.68e-3 against 4.80e-3, so the
size is the same. Overclaimed over untagged runs 0.91 to 1.14, mean 1.02, in
Float32, and 0.73 to 0.99, mean 0.85, in Float64. Form B misses by 56 J/m² of
8.8e5, against 1.4 of 9.3e5, the size Float32 sums reach. Whether the tilt is
rounding or the different atmosphere is not separated. *Job `13503987`,
`hpda2_test`, 2026-09-18, from `../ClimaAtmosResiDyn-c1b-val` at `9dd30a90`;
`analysis/c5_process_closure.jl`; `output/d4_column_edmf_vd_float32/`.*

**E57. #89's fork is bit for bit upstream on a restart and under the vertical
water borrowing limiter. The prescribed-flow column does not run upstream.** The
fork at `c068d564` against upstream `d331fe30`. A restart in two stages is bit
for bit, and so is the 1M column with `vertical_water_borrowing`. The
Shipway-Hill column fails in both checkouts at the first step:
`ShipwayHill2012VelocityProfile` compares an `ITime` with a `Float64`
(`src/types.jl:1715`). That failure is upstream's. *Job `13504311`,
`hpda2_test`, 2026-09-18, compared on the login node; `output/parity_89_r2/`.*

**E58. The model itself does not restart C5's column bit for bit; the tags
change nothing across a restart.** V5's pair without tags, records or check,
from #92 at `e4e9e5b3`. At 24 h the restart differs by `ρ` 1.758e-10, `ρe_tot`
1.604e-4 and `u₃` 1.543e-11, the same numbers as E54. With tags and without, the
model's fields are bit for bit. So E54's difference is the model's restart. A 1M
column restarted after 5 minutes is exact (E57); which difference matters is not
separated. *Jobs `13504312`, `13504313`, `hpda2_test`, 2026-09-18, from
`../ClimaAtmosResiDyn-c2-val`; `analysis/v5_compare_h5.py`;
`output/v5_c5_continuous_notags/`, `output/v5_c5_restarted_notags/`.*

## 7. The process records and the per-process checks

A process record `e_prc_<process>` is a signed running total of what a process
applied; a source tag is a share of the energy present. On 2026-09-10 the owner
decided to keep both: the tags say where the energy present came from, the
records what each process did. The implicit microphysics sink is bracketed for
the tags and the records (#69). The label check at configuration, that every
active label has a process tag, came with #77.

**E7. C3 is a controlled comparison.** It reproduces `c0_column` bit for bit:
`gross_relative` 0.13456131085846748, `max_abs_e_src_res` 26888.66561703798,
most-negative tag −44972.50629142498. The record perturbs nothing. *C3.*

**E8. On that run the source tag misses the dominant physical term.** At 24 h
the source tag `e_src_rad` runs from −2.07e-9 to +4,321 J kg⁻¹, and the process
record `e_prc_radiation` from −20,566 to +7,587 J kg⁻¹. The record's larger
excursion is cloud-top cooling, the point of a DYCOMS column. The tag, pinned at
zero from below by E1, cannot show it. *C3.*

**E9. So the process record is a demonstrated alternative, not merely an
available one.** It reads the physics the tags cannot, where they are inert, and
does not depend on the reference. A record is a running total and a tag a share,
so E8's rows are not to be differenced. *C3.*

**E20. Checked per process, the tags found a process nobody had listed:
subsidence.** C5 splits the new energy by region and by process. On the sphere
the two splits agree to 20.2 J kg⁻¹ at 24 h, 9.6e-4 of the new energy's largest
value. On the column they differ by 17,954 J kg⁻¹ at 675 m at 24 h, because the
DYCOMS setup runs `LargeScaleSubsidence` and no process tag lists it. With a
`sub` tag the column closes (E26). The sphere's gap was the rain-out (E28, E30),
then the limiter (E37). *C5, jobs `13385401`, `13385402`;
`analysis/c5_process_closure.jl`.*

**E21. On the column, a region's initial energy only falls.** The column
integrals of `strat − new_strat` and `tropo − new_tropo` fall at every sample,
from 5.268e7 to 5.008e7 J m⁻² and from 6.030e7 to 5.224e7. On the sphere the
same differences reach −9,617 and −11,638 J kg⁻¹, where the region tags are
negative (E14). *C5.*

**E22. The radiation tag holds nothing where radiation cools, with the loss
running.** At 675 m, where the radiation record is most negative at 24 h (−20,566 J kg⁻¹, as in C3), the `rad` tag
holds 0.0044 J kg⁻¹ of a total of 61,718 J kg⁻¹, a share of 7.1e-8. The loss
takes by share, and radiation added almost nothing there. So a source tag cannot
show where its process removed energy. *C5, `cloud_top.csv`.*

**E23. The column's records left 1.37 MJ m⁻² of its energy change unexplained
over a day: subsidence and the 0M rain-out, which no record reached then.**
Radiation's record is −6.62 MJ m⁻² and the surface flux's +9.42, 109 W m⁻²;
together +2.80 MJ m⁻², while `∫ρe_tot` rose 1.43. E26 splits the −1.37 MJ m⁻².
*C5.*

**E24. C5's radiation tag outgrows C3's after four hours, which the loss cannot
do on the same atmosphere.** 1,865 against 1,873 J kg⁻¹ at 4 h, then 5,990
against 4,272 at 22 h. The atmospheres agree. C3 ran on Levante with uncommitted
changes, so a code difference is possible. Not established (section 13). *C5
against C3.*

**E26. With its subsidence listed, the column closes per process and per
record.** C6 brackets the implicit rain-out, repairs negative tags, and adds a
`sub` tag and records for all four processes. Form A closes to 60.7 J kg⁻¹ at
24 h, 3.8e-4, against C5's 17,954; what is left is the per-tag transport (E34).
Form B closes to 3.3e-7 J m⁻² of 1.43 MJ m⁻². C5's unexplained −1,365,477 J m⁻²
is subsidence's −1,277,826 and the rain-out's −87,651, to the joule. *C6, jobs
`13385450`, `13385451` at `f3bbdb7b`; `analysis/c5_process_closure.jl`.*

**E28. On the sphere, the per-process check found the rain-out producing
energy.** The region split exceeds the process split by up to 149 J kg⁻¹ at
24 h, 7e-3, where the microphysics record is +270.6 J kg⁻¹. Condensate colder
than the reference carries negative energy, so removing it raises the total;
the `new_` tags take that, and no process tag lists `microphysics`. An `mp` tag
closes it (E30). *C6, jobs `13385452` to `13385454`;
`analysis/c5_process_closure.jl`.*

**E30. With a `microphysics` tag, the sphere closes per process.** C7 is
`c6_sphere_no_repair` with an `mp` tag. The splits agree to 20.2 J kg⁻¹ at 24 h,
9.5e-4, against C6's 149 and 7e-3. The rest grows as the square of time and is
the per-tag limiter (E37). The `mp` tag reaches 149 J kg⁻¹ and the microphysics
record 270.7. Nothing else changes. *C7, job `13399601` at `414f5f1b`;
`analysis/c5_process_closure.jl`, `analysis/same_atmosphere.jl`.*

**E38. Form A's global integral separates a missing process from numerical
noise. Its largest pointwise gap does not.**

| run                    | largest gap / largest new energy | ∫ gap / ∫ new energy |
|:---------------------- | --------------------------------:| --------------------:|
| C6, no `mp` tag        | 7.0e-3                           | 1.26e-3              |
| C7, tracer             | 9.5e-4                           | 5.2e-5               |
| C9, audit              | 4.1e-3                           | 4.7e-5               |
| C10, audit with repair | 1.5e-2                           | 6.0e-4               |

Transport errors cancel in the integral; a missing process does not. `mp`'s own
integral is 1.21e-3, and the repair's created energy 5.8e-4. A check of labels
at configuration carries the same information and would have caught E20 and E28
before any run. So read form A as a global integral, and without the repair
(section 12). The integrals use a hydrostatic density on the remapped grid, so
they are approximate. *`analysis/formA_followup.jl`.*

**E49. Summed over levels and over columns, form A's gap shows which way a
transport error moved. A process that no tag follows, and the repair, keep most
of their sum.** The fraction kept is the absolute value of the gap's
mass-weighted sums over its weighted gross; one means nothing cancels.

| run, at 24 h                  | what makes the gap                                      | kept over levels | kept over columns | kept overall | ∫ gap / ∫ new energy |
|:----------------------------- |:------------------------------------------------------- | ----------------:| -----------------:| ------------:| --------------------:|
| C7, sphere, tracer            | the per-tag limiter (E37)                               | 0.037            | 0.99              | 0.035        | 5.2e-5               |
| C9, sphere, audit             | the loss clamp, horizontally (E36)                      | 0.88             | 0.073             | 0.041        | 4.7e-5               |
| C10, sphere, audit and repair | the repair's created energy (E38)                       | 0.92             | 0.93              | 0.23         | 6.0e-4               |
| C6, sphere, no repair         | the rain-out has no tag (E28)                           | 0.47             | 0.99              | 0.46         | 1.26e-3              |
| C6, sphere, repair            | the same, and the repair                                | 0.62             | 0.70              | 0.42         | 3.5e-3               |
| C5, column, 0M                | subsidence has no tag (E20)                             | 1.00             | —                 | 1.00         | 0.26                 |
| C8, column, 1M, tracer        | not separated (E33); later, the per-tag transport (E43) | 0.011            | —                 | 0.011        | −1.5e-5              |
| C9, column, audit             | rounding (E34)                                          | 0.066            | —                 | 0.066        | 2.6e-12              |

A transport error cancels along the way it moved. A process no tag follows, and
the repair, keep their sums; the repair ledgers and the label check tell those
two apart. *A7, on the login node from the runs' hourly NetCDF;
`analysis/c5_process_closure.jl`; `output/a7_gap_cancellation/`.*

**E63. On a sphere the process records were advected with the air. This was a
bug, and it is fixed.** The horizontal tracer advection (`advection.jl:121`) and
the SEM limiter (`limited_tendencies.jl:88`) select fields by `is_tracer_var`,
which let `prc_e_*` and `prc_q_*` through. On the smallest test sphere the
advection moved a record by up to 2.6 J m⁻³ s⁻¹ before the fix, and exactly zero
after it. Global integrals were kept, so form B closed on the spheres; columns
were unaffected. The fix, `is_process_record_var`, is #93, now merged; V2 ran
from a branch that had it. *Jobs `13504847` (fixed, at `61d8dc3d`) and
`13504848` (the prototype at `faa98974`), `hpda2_test`, 2026-09-19;
`analysis/increment/sphere_record_advection.jl`.*

## 8. The sphere and long runs

**E50. The energy tags (`ρe_tag_*`) on a moist baroclinic wave with vertical
diffusion miss `ρe_tot` by 7% of its gross after ten days, and pointwise by 7%
of the largest `|e_tot|` after a week.** B1, `b1_base`: `MoistBaroclinicWave`,
0M, `h_elem` 6, `z_elem` 10, `dt` 400 s, two latitude tags, 10 days, Float64.
The owner approved B1 alone (decision 7 of 2026-09-18); B1a to B1c, B2 and B3
are not approved. *Erratum, 2026-09-23 (condensing, loss check): the original
entry dated decision 7 to 2026-09-17. The archived OPERATIONAL_TODO records it
under 2026-09-18, "going through section 1", and so does DECISIONS.md.*

| day | `relative` | `gross_relative` | `max \|e_tag_res\|`, J/kg | over `max \|e_tot\|` |
| ---:| ----------:| ----------------:| -------------------------:| --------------------:|
| 1   | 3.63e-5    | 0.0120           | 4,093                     | 0.037                |
| 5   | 2.49e-4    | 0.0234           | 7,324                     | 0.067                |
| 8   | 3.79e-4    | 0.0333           | 9,282                     | 0.085                |
| 9   | 9.06e-4    | 0.0716           | 27,483                    | 0.252                |
| 10  | 1.04e-3    | 0.0698           | 17,278                    | 0.159                |

More than half of the gross comes in the 30 hours from day 8 to day 9.25, which
fits the wave breaking; no run separates a cause. The docs' figure for a dry
wave, below one percent, does not carry over, but B1 is moist, so it does not
falsify it; B2, the dry case, has not run. Which operator carries the residual
is not known. Cost: 0.628 SYPD on 2 CPUs, 63 minutes of solve. *Job `13501290`,
`hpda2_test`, 2026-09-18; model `main` at `38661891`, driver and configuration
at `58d9b0c8`; `analysis/reduce_run.jl`, `analysis/b1_residual_scale.jl`;
`output/b1_base/`.*

**E60. The tags' mislabelled energy is flushed only as fast as it is lost, often
slowly, and the one-day plateau is mixing, not the rule. So over long runs the
error can keep growing, and the column integral hides most of it.** An analysis
of recorded runs. The loss rule changes `R = E − Σ region tags` by `−(R/E)·Δ⁻`,
so `R` flushes at the rate `E` is lost where `R` sits. On D4 that is 0.05 to
0.26 a day, 4 to 20 days. On C9's sphere 91% of `|R|` sits above 10 km, where it
is 0.0013 to 0.0025 a day, 1 to 2 years. D4's one-day plateau is the EDMF eddy
diffusion mixing `R` as a tracer. B1, a fair proxy, grows past a saturating fit:
0.43% of the sphere's `E` at day 1, 0.97% at day 7, 2.5% at day 10. And the
column integral hides per-tag error: C6 and C9 differ pointwise by 5 to 10% in
their small tags but by 0.1 to 0.3% in column integral. So an estimate given to
the owner, a level of 0.5 to 5% within weeks, does not hold (section 12). V2
measured the flush rate on a sphere (E70, E74). *`analysis/displacement_check/`;
`output/displacement_check/`, from the runs' NetCDF on scratch.*

**E69. With one Newton iteration, V2's model top collapses to the 150 K floor
within 6 h; two iterations prevent it.** V2 (`g2_v2_sphere`) is the production
physics on a sphere under the prototype: EDMF with the updrafts' vertical
diffusion, implicit eddy diffusion, both sponges, a DCMIP200 mountain, 1M,
Float32, 10 levels to 30 km, `dt` 20 s, 24 ranks.

| top level (27 km), mean   | 1 h     | 2 h   | 3 h   | 6 h                     |
|:------------------------- | -------:| -----:| -----:| -----------------------:|
| V2, one iteration         | 216.2 K | 205.1 | 190.1 | 156.0, 18% at the floor |
| without sponges           | 216.2   | 205.1 | 190.1 |                         |
| without the mountain      | 215.5   | 203.1 | 188.7 |                         |
| two iterations            | 219.3   | 218.9 |       |                         |
| ten iterations (the twin) | 219.3   | 218.9 | 218.7 | 218.5                   |

The one-iteration solve alone makes the collapse; it is the model's own, since
the tags feed back into nothing. The first V2 is kept as a record of the tags'
bookkeeping on that atmosphere, with this caveat. On the sphere the converged
twin does not close better, 2.78e-5 of the scale at 24 h against 2.45e-5,
because both are Float32 (E70). The twin cannot measure one iteration's per-tag
error here, since the atmospheres differ by 4 K at 1 h; the two-iteration rerun
is the run to compare (E74). *Erratum, 2026-09-19: the third point's
explanation, as first written, is wrong (section 12). With two iterations the
sphere's residual is Float32 rounding alone (E70).* *Jobs `13504999` (V2),
`13505000` (the twin), `13505762` to `13505764` (three-hour variants),
2026-09-19, from `../ClimaAtmosResiDyn-inc-run3` at `04d63916`;
`output/g2_v2_*`.*

**E70. On the sphere, V2's residual is Float32 rounding. The explicit processes
and the sponges add nothing measurable.** Two hours of `g2_v2_diag_newton2` (two
iterations) again, in Float64 and in Float32 without sponges. The gross residual,
of the scale, at 0, 1 and 2 h: Float32 1.0e-8, 2.36e-6, 3.85e-6; without sponges
1.0e-8, 2.34e-6, 3.87e-6; Float64 2.6e-17, 3.6e-15, 5.7e-15. V2's one-iteration
column totals, 16% of its gross at ten days, are not decided by this. V2's ten
days as run: the gross is 2.45e-5 of the scale at 1 day, 9.4e-5 at 5 and 1.58e-4
at 10, flushed at 0.011 to 0.015 a day (`output/g2_v2_sphere/v2_sphere_analysis.txt`).
*Jobs `13509165` (Float64), `13509166` (no sponges), `hpda2_test`, 2026-09-19,
from `../ClimaAtmosResiDyn-inc-run3` at `04d63916`; `output/g2_v2_f64_2h`,
`output/g2_v2_nosponge_2h`.*

**E74. G2: the sphere closes over ten days. With two Newton iterations the model
top holds, and the tags' gross residual reaches 2.0e-4 of the scale, still
slowing.** `g2_v2_sphere_n2`, V2 with two iterations. The gross residual, of the
scale, is 2.77e-5 at 1 day, 7.95e-5 at 3, 1.24e-4 at 5, 1.57e-4 at 7 and 2.01e-4
at 10. The top level stays at 218 to 220 K, with a global minimum of 210.7 K.
The loss rule flushes the residual at 0.0105 to 0.0165 a day, 60 to 95 days. It
is Float32 rounding (E70). Against the converged twin `g2_v2_sphere_newton10` at
1 h, every tag is within 3.1e-4 in L1: criterion 4's solver part. The run
predates the updraft mixing (E73), which cannot move the closure; E75 has the
per-tag fields with it. *Job `13505896`, `hpda2_compute`, 2026-09-19 to
2026-09-20, from `../ClimaAtmosResiDyn-inc-run3` at `04d63916`;
`output/g2_v2_sphere_n2/`, with `v2_sphere.py` and `tag_correctness_sphere.py`.*

**E75. G2 complete: with the updraft's mixing the sphere closes as before, and
the source tags move by 10 to 19% over ten days.** `g2_v2_sphere_mix` is
`g2_v2_sphere_n2` from the branch that mixes provenance through the updrafts
(E73), the fork's default. The closure is 2.003e-4 of the scale at ten days
against 2.009e-4 without the mixing. Against that run, in L1:

| L1                 | 1 h                   | 24 h   | 5 d   | 10 d        |
|:------------------ | ---------------------:| ------:| -----:| -----------:|
| `sfc`              | 0.27%                 | 4.9%   | 10.0% | 12.1%       |
| `rad`              | 0.108%, erratum below | 1.7%   | 8.4%  | 9.1%        |
| `new_extratropics` | 0.06%                 | 2.9%   | 8.8%  | 19.1%       |
| region tags        | 1e-8                  | 0.008% | 0.5%  | 1.2 to 1.9% |

*Erratum, 2026-09-23 (H3): `rad` at 1 h is 0.108%, not 0.15% as first written
(`output/g2_v2_sphere_mix/tags_vs_no_mixing.txt`, L1 1.08e-03). Every other
cell matches.* The integrals move by about 1%. So a ten-day sphere's source
tags depend on the mixing convention at the 10% level, well above the solver's
3.1e-4 (E74). `ta` agrees to under 0.0005 K. G2 is met. *Job `13548198`,
`hpda2_compute`, 2026-09-21 to 2026-09-22, 16.5 h of wall time, from
`../ClimaAtmosResiDyn-upd-run` at `846ef55d`. A first attempt, `13538434`, was
killed for memory, 200 GB against the 500 GB needed; it is kept as
`g2_v2_sphere_mix_oom_13538434` on scratch. `output/g2_v2_sphere_mix/`.*

## 9. Mixing: V3 and the updraft gap

Under EDMF the tags' updraft share is the grid mean's, so the provenance the
updraft carries is not followed: the updraft gap. What it is, why it is large
yet invisible to closure, and the way chosen to close it are in
[design/UPDRAFT_GAP.md](design/UPDRAFT_GAP.md); the tracer and flux conventions
are in [design/TRACER_AND_FLUX.md](design/TRACER_AND_FLUX.md). On 2026-09-19
the owner chose the hybrid convention as built, and one switch: updraft copies
of the tags as the audit, a zero-sum exchange as the default
([DECISIONS.md](DECISIONS.md)).

**E68. V3 set a passive tracer with an updraft copy beside the tags on D4. What
it measured, `ψ − q_gas_A`, is the updraft gap plus the attribution of new
energy by mask; the gap alone is E73's.** D4 under the prototype with
`chemistry_model: passive`; the tracer `q_gas_A` starts as the `tropo` mask, and
`ψ = tropo/(tropo + strat)` equal to it. The L1 of `ψ − q_gas_A` is 7.8% at 1 h,
6.6% at 3 h, 3.9% at 6 h and 3.2% at 24 h, largest at the inversion early on.
After a day the tracer holds 10.1% air from above the inversion and the tags
7.0%. `ta` is bit for bit `g1_inc_d4`'s, and the closure 266.94240759 J/m² at
24 h. *Erratum, 2026-09-19: the premise is wrong. The region tags have no
sources, so they take every source's gain by their mask, while a loss takes from
every tag in proportion. So `ψ` rises above the tracer even with the air's own
mixing. With updraft copies (E73) the gap in the boundary layer is 0.3 points at
6 h and 1.3 points at 24 h, most of it the attribution.* The first reading is in
section 12. *Job `13505756`, `hpda2_test`, 2026-09-19, from
`../ClimaAtmosResiDyn-inc-run3` at `04d63916`; `analysis/increment/v3_driver.jl`,
`v3_compare.py`; `output/v3_d4_passive_tracer/`.*

**E72. Over V2's nine days, the updraft gap would lift the tropical `sfc` tag's
centroid by about as much as the tag itself rises.** UPDRAFT_GAP.md's estimate
(`updraft_gap_estimate.jl`, reviewed) on days 1 to 9 of V2, with E69's caveat.
It gives an initial rate, and its days cannot be added.

| tropics                                                      | days 1 to 4           | days 5 to 9            |
|:------------------------------------------------------------ | ---------------------:| ----------------------:|
| updraft top, area mean                                       | 1.8 to 2.6 km         | 2.8 to 3.4 km          |
| `sfc` centroid rise from the gap, m a day, upwind to centred | 86 to 185, 158 to 507 | 137 to 261, 166 to 285 |
| `sfc` centroid's actual change, m a day                      | 142 to 699            | 265 to 372             |

So where the surface's energy sits in the vertical is uncertain at order one in
convective regions. The column totals and the horizontal split are not affected.
An estimate, not a measurement; E73 measured the gap on D4. *On a login node,
`analysis/increment/updraft_gap_estimate.jl` on V2's daily checkpoints;
`output/g2_v2_sphere/updraft_gap_estimate_days1-9.txt`.*

**E73. The updraft gap is closed on D4. The default exchange stays within 1% of
the audit's updraft copies after a day, and within 3% after six hours.** Both
modes ran a day on D4 with V3's tracer (`v3_upd_default`, `v3_upd_copies`); `ta`
and `rhoa` are `g1_inc_d4`'s bit for bit.

| L1 against the copies, `sfc` (region tags) | 1 h         | 6 h          | 12 h         | 24 h          |
|:------------------------------------------ | -----------:| ------------:| ------------:| -------------:|
| no updraft mixing (V3, E68)                | 61% (8.6%)  | 71% (4.6%)   | 33% (2.4%)   | 14% (2.3%)    |
| the default exchange                       | 16% (0.14%) | 2.5% (0.42%) | 1.6% (0.09%) | 0.66% (0.07%) |

At 24 h every tag is within 0.7% in L1 and 2.5% at its largest point, which
meets G1's criterion 4(b), L1 at most 2% and L∞ at most 5%, set by the owner on
2026-09-20. The default closes to 267.07 J/m² at 24 h, the copies to 365, with
the same column totals, −45.52 J/m². Against the tracer the copies come within
0.3 points of `q_gas_A` in the boundary layer at 6 h and 1.3 at 24 h (E68).
Rerun twice at the branch head. After the review's fixes (`38278c2d`, job
`13536456`) `ta` is bit for bit and every tag within 2e-14. After the plume moved
to the face below each cell (`846ef55d`, job `13538433`) `ta` and `rhoa` are bit
for bit, the closure 267.047 against 267.068, and `sfc` 0.64% against 0.66% at
24 h (`output/v3_upd_default/head_846ef55d/`). So the numbers stand. The copies add a field per tag to the updraft; the default adds
no state. *Erratum, 2026-09-23 (housekeeping re-check H3, `review/verify_g3.md`):
the D4 runs cited below built separately and cold, and their tendency build took
600.3 s with the default (`13528772`) and 3504.1 s with the copies (`13523326`),
about 5.8×. The 402 s and 789 s first quoted in this entry (now in §12) come from a smoke
test, job `13519152`, that built both in one process, the copies second: about
2× after the default's build. Neither is a controlled benchmark;
G3's V-W10 measures it.* *Jobs `13528772` (default, at `e010f780`) and
`13523326` (copies, at `3ec098f1`), `hpda2_test`, 2026-09-19, from
`../ClimaAtmosResiDyn-upd-run`, with `analysis/increment/v3_driver.jl`. A first
default run at `3ec098f1` is superseded
(`v3_upd_default_prefix_e010f780_superseded` on scratch). `output/v3_upd_default/`,
`output/v3_upd_copies/`.*

**E76. The exchange's ladder: its agreement with the audit holds at 24 h across
the time step and the Newton count, and the first hour does not converge. R2 of
the review of #95.** Five pairs of D4 days, each a default run and an
updraft-copies run on one atmosphere, so each pair's difference is the
exchange's error against the audit at that setting. `ta` and `rhoa` are bit for
bit in every pair.

| L1 against the copies    | `sfc` 1 h | `sfc` 6 h | `sfc` 24 h | `strat` 24 h |
|:------------------------ | ---------:| ---------:| ----------:| ------------:|
| 120 s, 1 Newton, centred | 14.3%     | 2.6%      | 0.64%      | 0.91%        |
| 60 s                     | 19.4%     | 3.1%      | 0.53%      | 1.25%        |
| 30 s                     | 21.3%     | 2.5%      | 1.36%      | 1.09%        |
| 2 Newton iterations      | 15.5%     | 2.2%      | 0.88%      | 1.13%        |
| first-order upwind       | 14.7%     | 11.0%     | 6.5%       | 0.22%        |

At 24 h every tag is within 1.6% in L1 and 2.6% at its largest point, at every
time step and Newton count. That meets G1's criterion 4b (L1 ≤ 2%, L∞ ≤ 5%) with
margin: the worst tag is `sub` at 1.54% and `sfc` at 2.51%. The first hour gets
worse as the step shrinks, 14.3% to 21.3% for `sfc`, so it is not a
discretisation error. It is the copies' spin-up from the grid mean against a
plume that is steady from the first step, and the two schemes' different
bounds. It is a difference of convention, and a first-hour reading should say
which convention it used. One Newton iteration against two moves `sfc` at 24 h
from 0.64% to 0.88%, and the region tags from 0.91% to 1.13%, so the error is
not the solver's. First-order upwinding of the sub-grid flux costs an order of
magnitude (6.5% against 0.64% for `sfc` at 24 h), which supports keeping the
parent's reconstruction. The blend factor's fix (`dcf7d086`) takes the region
tags' first-hour L1 from 1.89% to 0.13% at the baseline, and from 1.73% to
0.12% with two Newton iterations. Late-time numbers move little, the region
tags from about 0.5% to about 1%. *Jobs `13782601` to `13782605` (the default
runs at `dcf7d086`) and `13768363` to `13768369` (the copies runs at
`dbe7435c`, which the fix does not touch), terrabyte, 2026-09-23, from
`../ClimaAtmosResiDyn-upd-run`. The earlier default runs at `dbe7435c` are
superseded. `output/v3_upd_default*`, `output/v3_upd_copies*`; RUNS.md lists
each output.*

## 10. Cost

Other costs sit beside their findings: the audit, about 5% per step (E34);
Float32, no speed-up on a CPU (E45); 4 MPI ranks, 3.8× faster (E47); B1, 0.628
SYPD (E50); the updraft copies' build (E73).

### 10.1 Run time

**T1. Compilation dominates these jobs.** `a1_dt10` reports
`solve! walltime = 3.337` s inside a job of 295 s, with `sypd: 2.956` and
`wall_time_per_timestep: 9 ms 269 µs`. So job wall times are not a tag cost.

**T2. The A1 configuration costs 6.1× its untagged control.** `solve! walltime`
3.337 s against 0.548 s, 6.09; `sypd` 2.956 against 17.992; per timestep
9.269 ms against 1.522 ms. A second `.err` in `output/a1_dt10/`, job `27360071`,
gives 5.97, so the ratio carries about 2% of run-to-run scatter. *A1, jobs
`27360483` and `27360071`.*

**T3. That is the cost of the configuration, not of the tags:**
`water_closure_check` every 10 s against a `dt` of 10 s, a global reduction on
every step, plus diagnostics every 60 s.

**T4. The clean measurement is 1.32×.** The C0 pair, three energy source tags
with the check and diagnostics hourly, over 8640 steps: `solve! walltime`
11.225 s against 8.521 s, 1.317; `sypd` 21.088 against 27.779; per timestep
1.299 ms against 986.3 µs. So most of A1's factor is the check. One
configuration, column and node. *C0, jobs `27361326` and `27368587`.*

**T5. Short runs skew per-step figures.** The untagged columns read 1.522 ms and
986 µs per timestep, over 360 and 8640 steps. Not a controlled pair:
`c0_column_notags` runs DYCOMS radiation, `a1_dt10_notags` none. Ratios are read
within a pair, never across.

**T6. The reference shift costs nothing.** C1's `solve! walltime` is 349.0 s
against 345.6 s unshifted, 1.0% apart; `sypd` 0.678 against 0.685. *C1, jobs
`13383684`, `13383685`.*

**T7. The tag offset costs no more than the scatter.** C4's `solve! walltime` is
353.3 s at C1's offset and 355.8 s at twice it, against 345.6 s unshifted and
349.0 s for C1. *C4, jobs `13384913`, `13384914`.*

**T8. The repair costs about 1%.** C6's `solve! walltime` is 21.47 s with the
repair and 21.01 s without on the column, and 435.9 s against 431.5 s on the
sphere. First-order tag upwinding took 423.7 s. *C6, jobs `13385450` to
`13385454`.*

**T9. On the sphere the tags cost 1.46×.** P1 is C7 against C7 with no tags,
records, check or diagnostics: `solve! walltime` 445.75 s against 305.44 s,
1.459; `sypd` 0.531 against 0.775; per timestep 2.063 s against 1.414 s; the
whole job 18.2 min against 11.0 min, 1.66. That is the feature as used, 7 tags,
3 records, the audited check and 12 fields written hourly, not split. One pair,
one node, CPU only. *P1, jobs `13440989`, `13440990` at `c2842ba6`;
`output/p1_sphere_tags/`, `output/p1_sphere_notags/`.*

**T10. The tag and record code allocates nothing. The explicit tendency
allocates without tags, and each tag adds to it.** `@allocated` on a second
call, 1M DYCOMS column, Float64, 4 tags and 3 records, against none (to-do item
T3). The brackets, `energy_source_share_norm!`, `repair_energy_source_tags!`,
`vertical_advection_of_water_tendency!` and `implicit_tendency!` allocate 0
bytes. `remaining_tendency!` allocates 58,160 bytes against 22,576, all in the
shared tracer loops; `constrain_state!` 32 against 32. #76's split solver
allocates nothing, and the unsplit ClimaCore solve 48 bytes per call. Checked by
tests (#78, #76). CPU, Julia 1.11.9, without CI's bounds checks. *Login node at
`3b4b6056` and `7d190db1`; `analysis/t3_allocations.jl`,
`analysis/t3_allocation_profile.jl`, `analysis/t3_split_solver_allocations.jl`.*

### 10.2 The EDMF build

**E44. With the tags, the EDMF column did not build in two hours. Without them
it builds in 410 s.** The D4 pair, with 8 tags, 5 records, the audited check and
hourly diagnostics, stopped at the two-hour limit with no output.
`d4_column_edmf_notags` built in 410 s, cache 129 s, tendency function 228 s,
integrator 53 s, and ran its hour in 18.5 minutes. So the tags made the build
more than 17 times slower. This blocked the tags under EDMF until #76 (E44e).
*Jobs `13404536`, `13404537` at `78586e39`, and `13414334` at `41adabc5`, on
`hpda2_test`; `output/d4_column_edmf_notags/`.*

**E44b. The EDMF build grows faster than the number of fields the tags and
records add, and the tags with the records alone take it past two hours.** P4
adds D4's parts back one at a time, with no check and no diagnostics, at
`edd44e1d`. The logged build stages take 410 s with no tags, 572 s with 2 and
876 s with 8; the whole job 18.5, 27 and 60 minutes. With 8 tags and 5 records
the build was not reached, and the job was stopped after 120 minutes. So 2
fields add 8.5 minutes, 8 add 42 and 13 more than 100. Once built, a column
steps in 17 ms. *Jobs `13415603`, `13415604`, `13415605` at `edd44e1d`;
`output/p4_edmf_two_tags/`, `output/p4_edmf_tags/`.*

**E44c. The EDMF build's growth with the tags is nearly all in building the
simulation, and most of it is compiled before the driver's first timer starts.**
`analysis/p4_build_stages.jl` times each stage with its compile inside.
`get_simulation` takes 712.2, 916.3 and 2603.6 s with 0, 2 and 8 tags. Of that,
the part no timer logs is 277, 400 and 1805 s. `get_simulation` grows by 204 s
with 2 tags and 1,891 s with 8. Once built, the column steps in 13.8, 13.7 and
14.7 ms. The whole script takes 1142, 1367 and 3120 s. The candidate named then,
the tag code's recursion over its tuple, is not the cause (E44d). *Jobs
`13440706`, `13440707`, `13440637` at `edd44e1d`; `output/p4_build_stages/`.*

**E44d. The growth is ClimaCore building the implicit Jacobian's solver: its
compile-time work on the state's field names grows much faster than their
number.** Julia's inference timer shows the growth is inference: from 0 to 8
tags it grows by 1,889 s on the EDMF column and 87 s on the 0M column. No tag or
record function is among the methods that grow. On the EDMF column, `==` on
tuples of field names grows from 88,597 specializations to 412,854. Timed apart,
`FieldMatrixWithSolver` takes 14.1 s with 13 blocks and 89.2 s with the 8 tags'
21. A `BlockLowerTriangularSolve` prototype still took 95.2 s. Built over the
coupled fields alone, the solver takes 13.6 s with 8 tags. A ClimaCore issue was
drafted and not filed
([archive/2026-09-23/CLIMACORE_ISSUE_DRAFT.md](archive/2026-09-23/CLIMACORE_ISSUE_DRAFT.md);
decision 3 of 2026-09-18). *Jobs `13441219`, `13441220`, `13441221` at
`edd44e1d`, and the login node; `analysis/p4_inference_profile.jl`,
`p4_profile_compare.jl`, `p4_jacobian_pieces.jl`, `p4_solver_profile.jl`,
`p4_split_solver.jl`; `output/p4_inference_profile/`,
`output/climacore_nameset_repro/`.*

**E44e. With the tags and records solved apart, the EDMF column with 8 tags and
5 records builds in 21 minutes, and the tags add 37 s to its build.** #76's
`SplitJacobianSolver` solves the coupled fields with the nested solver and each
tag and record on its own. `get_simulation` takes 712.2 s without tags; with 8
tags 748.8 s against 2603.6 before; with 8 tags and 5 records 757.1 s. The whole
script takes 1142 s without tags, and 1239 and 1257 s with #76, against 3120 s
and over 7,200 before. The
increments are identical in every field. This unblocked every EDMF run with
tags (E53). *At `a55d15ce`, jobs `13441606`, `13441607`, from
`../ClimaAtmosResiDyn-buildtime-edmf`; `analysis/p4_build_stages.jl`,
`p4_split_check.jl`, `p4_cache_time.jl`, `p4_cache_profile.jl`;
`output/p4_fix_validation/`, `output/p4_inference_profile/`.*

**E52. With no diagnostic on, the fork's logged stage "built tendency function"
takes 396.7 s on the EDMF column where upstream's takes 21.8 s; the whole build
takes the same time (E56).** From the logs of E51's job. The cache took 150.1 s
against 150.9, and the integrator 88.0 s against 76.2. On the 1M column the
tendency function takes 22.4 s against 7.0 s. *Corrected by E56:* the stage
times are right, but their sum is not the build time. The first reading is in
section 12. *The job and logs of E51.*

**E56. The fork does not build the EDMF column more slowly than upstream. E52's
gap is where the compile is counted.** Both spend about 400 s compiling the same
`FieldMatrixWithSolver`. Upstream does it before the timed block, the fork
inside it. `get_simulation` took 788 and 834 s upstream, in two runs, and 823 s
in the fork. The first `get_jacobian` took 400 s upstream and 406 s in the fork.
Two breaks in inference, #76's `invokelatest` and the tag-name predicates, move
the compile into the block; removing both gives upstream's 22.4 s. A fix that
does so was tried and not committed; it waits in [BACKLOG.md](BACKLOG.md).
*Login node, one core, 2026-09-18; scripts, patches and logs in
`$SCRATCH/claude_work/p7/`.*

**E77. The exchange allocates 17,416 bytes per call when ClimaCore is pinned to
the compat floor, and nothing of ours is the cause. The allocation is
ClimaCore's own `DataScope` reduction over a broadcast's layout arguments.**
The downgrade jobs of CI pin every dependency to its oldest allowed version,
and there the `tagging_source_updraft` group's allocation test failed while the
same test passed on current versions. Pinning ClimaCore to 0.16.0 in a local
environment with everything else current reproduces the CI figure exactly:
`exchange: 17416`, against 8 bytes with ClimaCore 1.0.0.

  - **The allocation is entirely at two lines of ClimaCore.** An allocation
    profile of the exchange attributes all of it to
    `DataLayouts/scopes.jl:76`, `DataScope(arg1, arg2, args...) = DataScope(DataScope(arg1), DataScope(arg2, args...))`, reached from
    `DataLayouts/broadcast.jl:131`, `DataScope(bc) = DataScope(layout_args(bc)...)`, inside `foreach_point`.
  - **What is allocated is the broadcast itself, not our data.** The five
    largest entries, 16,096 of the 17,416 bytes in ten allocations, are
    `Broadcasted` objects and tuples of them. The vararg reduction over the
    broadcast's layout arguments is materialised on the heap instead of being
    unrolled away.
  - **Raising the compat floor to 0.16.1 would not help.** The two lines are
    textually identical in 0.16.0, 0.16.1 and 1.0.0, and the whole
    `src/DataLayouts` tree is byte-identical between 0.16.0 and 0.16.1. What
    changed by 1.0.0 is around them: 0.16.0 carries a local `Utilities.Unrolled`
    module of hand-written unrolled shims, which 1.0.0 removes in favour of
    UnrolledUtilities. Pinning 0.16.1 also fails for an unrelated reason, a
    callback condition returning `nothing` inside ClimaTimeSteppers, so it is
    not a usable floor either way.
  - **What was ruled out first.** The kernel's own shape allocates nothing on
    both versions, in both layouts; `column_accumulate!` allocates nothing on
    both; nested lazy inputs cost 480 bytes on both; and materialising the
    intermediate ratios or subdomain energies makes current versions worse, 424
    and 4,824 bytes. Thermodynamics is cleared by the pin experiment itself.

The test's bound is therefore scoped by the resolved ClimaCore version in
`afd470e7`, strict at 8 and 24 bytes on current versions and loose at 32,768 on
the floor, with the reason in `NEWS.md`. Both downgrade groups pass with it.
*2026-09-23, login node, in `$SCRATCH/claude_work/dg_atmos`, a full ClimaAtmos
environment resolved offline against the terrabyte-cpu depot with ClimaCore
pinned; the probe is `$SCRATCH/claude_work/upd_run/alloc_types.jl` and its log
is beside it.* *Erratum, 2026-09-23 (E78): the premise is wrong. At `afd470e7`
the exchange allocates 17,416 bytes per call with ClimaCore 1.0.0 and 1.0.1 as
well, so the version does not decide it. The bound scoped by the version failed
in CI, where ClimaCore resolves to 1.0.1. The only 8-byte figure in the probe's
logs is `alloc_login2.log` of 2026-09-20, from the kernel before `e71430fb`;
that the 8 bytes came from there is inferred. The cause is the kernel's lazy
inputs, and E78 has the fix. The downgrade groups that failed were
`tagging_source_increment` and `tagging_source_edmf` (run `35836620186`, at
`dcf7d086`), not `tagging_source_updraft`.* The first reading is in section 12.

**E78. The exchange's 17 kB per call came from its own kernel, with every
ClimaCore version. With its inputs written to scratch, the exchange allocates
only the parent helper's 8 bytes again.** At `afd470e7` the exchange allocated
17,416 bytes per call on the DYCOMS column with ClimaCore 0.16.0, 1.0.0 and 1.0.1
alike, on Julia 1.11.9. CI on Julia 1.10 measured 17,736. The profile puts it
at the two share-difference broadcasts, 8,376 bytes in 31 allocations each.
Since `9e7a9638` their inputs `ᶜroom` and `ᶜenergy_ratio` were lazy. They
reached through both subdomains' energies and the environment's density, and
ClimaCore boxed each broadcast in its `DataScope` reduction (E77).
`foreach_point` runs that reduction once before its loop, so the cost is per
call, not per cell.

  - **Forms tried**, with bytes on all three versions. Each was bit for bit
    `afd470e7` in the tags' tendency. With the two ratios written to scratch,
    424 bytes; with the density, 13,848; with both, 216; with the two
    subdomain energies, 4,824.
  - **The fix writes the environment's density with `TD.air_density`, and the
    two ratios, to three scalar fields of the exchange's scratch.** The
    exchange then allocates 8 bytes per call, and the tags' whole SGS flux 24.
    That is the `Ref` around the closure in `ᶜspecific_env_mse`. It holds on
    all three versions with Julia 1.11.9, and with ClimaCore 1.0.1 on Julia
    1.10.12. The Julia 1.10 run with the floor's packages is left to the
    downgrade CI. The probe's 216 bytes came from
    writing its lazy density object, not from the direct write. The parent's
    own write of the same density, `microphysics_cache.jl:990`, allocates
    nothing.
  - **Nothing else moves.** The tags' tendency is bit for bit that of
    `afd470e7`, so E76 describes the head. `tagging_source_increment` (96 of
    96) and `tagging_source_edmf` (53 of 53) pass with ClimaCore 1.0.1 on
    Julia 1.11 and 1.10. Those runs still had the provisional bounds of 216
    and 232 bytes. The tests' bounds are 8 and 24 bytes again, without the
    version gate, on the measurements above.

*2026-09-23, jobs `13812434`–`13812436` (the forms), `13816955`–`13816957` and
`13822248` (the fix), and `13816958`, `13816959`, `13816961` and `13816962`
(the two test files), `hpda2_test`;
`$SCRATCH/claude_work/upd_run/alloc_forms.jl`, `alloc_verify.jl` and
`forms_def.jl`, with the environments `cc101_env`, `upd_testenv`, `dg_atmos`
and `j110_env` in `$SCRATCH/claude_work/`. The fix is `b9c6e7b0` on
`claude/energy-source-tag-updraft`. Reviewed by an agent, which found
the change bit-identical by reading.*

## 11. Method

**M1. Volume fractions and mass fractions can differ by six orders of
magnitude.** On A5, `nonpositive_fraction` is 0.351 and
`nonpositive_mass_fraction` 2.77e-7, a factor of 1.3 million. For energy it goes
the other way: `c0_sphere_audit` measures 0.7839 against a volume fraction of
0.43276, 1.811× (E9b). `nonpositive_fraction` is a volume fraction, not a count:
`tagged_tracers.jl:456-459` sums a field of ones over the region, and the
docstring at `:421` says so. On the sphere 0.43276 is the r²-weighted volume
below 13.02 km, where the count fraction would be 7/10.

**M2. `untagged + overclaimed = gross_residual` exactly**, confirmed on a model
run, not only on randomised states. So the audit gives a residual's direction,
where `gross_relative` gives its size.

**M3. The operator residual and the audit do not overlap.** The audit integrates
the residual as it stands; the operator residual is a pointwise `max abs` with
the correction ledger added back.

**M4. Practical traps, all hit at least once.** `.buildkite` must be
instantiated on a login node under the run's own depot. `module purge` strips
git, so provenance is resolved before it. The global `.gitignore` drops
`output/`, `*.png` and `*.log`. `sypd` goes to stderr, so it is in the `.err`.

**M5. The most negative tag hides the source tags.** On `c0_sphere` the most
negative tag is the region tag `extratropics`, −100,416 J kg⁻¹, the parent's own
minimum at t = 0, while `sfc` reaches −209.19 at 24 h unseen. `phase_c.jl` now
reports the most negative source tag on its own. *C0, from
`source_tag_extrema.csv`.*

**M6. Levante and terrabyte agree to rounding, not bit for bit.** The terrabyte
re-run of `c0_sphere_audit` differs from Levante's in the last digits from t = 0 on, and by at most
1.5e-14 in `gross_residual` over the day; `nonpositive_mass_fraction` at 24 h agrees to every digit. On
one machine runs are deterministic. *`c0_sphere_audit` on both machines, and the
twin test.*

**M7. A control that changes more than the variable in question bounds an
effect; it does not isolate it.** W16 compared implicit with explicit
microphysics to isolate a missing Jacobian entry, but moving microphysics also
changes the operator splitting and the integration path. So the result is a
bound on this case, stated with its least favourable number (the source tag's
24%), not a cause. To isolate an effect, change only it: here, the same
implicit residual and integration with and without the entry. The owner's
review of #100, 2026-09-23.

**M8. The phase-1 verifier printed right numbers that its tests could not
defend; it is fixed, and no published number changed.** A review of the
evidence tools (`review/agent_reviews/phase1_tools_review_2026-09-23.md`)
recomputed all 28 non-zero rows of E73's table independently and found them
exact. But 17 of 19 planted defects passed the six tests, among them wrong
weights, an unweighted L1, a flipped sign and the lowest level only, and a NaN
or a fill value gave exit 0 with `nan` metrics that a budget check would pass.
After the fixes (`82c0c32f` and its successor) the tests pin every metric on a
nonuniform grid and reproduce E73 from a fixture in the repository, a
mutation check catches 16 of 16 planted defects, and non-finite values are
refused. The verifier now covers the water family, judges G3's budgets, checks
parity against an untagged twin, reads any output period and fractional hours.
From here on every G3 headline number goes through it (criterion 1).

## 12. Superseded and falsified claims

Kept because a later reader would otherwise re-derive them. From the old section
6, the errata, `review/register/conflicts.csv` and LEARNINGS. Eleven more
inconsistencies, found while condensing, are the rows of `conflicts.csv` marked
H4-B. They are not settled: the entries stand as recorded until G4's full
re-check (G4_TODO.md).

| old claim                                                                                                                                                                                | what replaced it                                                                                                                                                                     | where                                                 |
|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:----------------------------------------------------- |
| The operator residual's sign, as first written in the plan.                                                                                                                              | Corrected by 20,000 randomised states, verified independently.                                                                                                                       | [archive](archive/2026-09-23/FINDINGS.md), §6         |
| The #64 mechanism as the docstring's precondition failing, with `water_tag_rescale_ratio` unclamped above (LEARNINGS:A5:1).                                                              | The multiplicative rescale scales the error whether or not the precondition holds.                                                                                                   | W7                                                    |
| W7's citation `tagged_water.jl:800`.                                                                                                                                                     | Pre-fix lines about 695-741; today's docstring near 814. Erratum 2026-09-23.                                                                                                         | W7                                                    |
| A3 alone as evidence about 1M: 9.844e-8 against A1's 2.844e-6 (LEARNINGS:A3:1).                                                                                                          | Two keys moved; vertical diffusion is 27× of the 29×.                                                                                                                                | W5                                                    |
| Phase B gated on A5's divergence.                                                                                                                                                        | `b1_base` has no limiter, and the energy family no rescale and no partition repair.                                                                                                  | E50                                                   |
| E2's negative source tag as a product of the inert donor rule; C1's expectation that a positive parent keeps the tags non-negative.                                                      | With the loss running everywhere the tag reaches −219.9 J kg⁻¹ and the region tags go negative.                                                                                      | E14                                                   |
| The −100 kJ kg⁻¹ offset as an initialisation error.                                                                                                                                      | A convention.                                                                                                                                                                        | R2                                                    |
| An "effective reference near 381 K".                                                                                                                                                     | An artifact of reading the gap as a temperature in the wrong convention.                                                                                                             | R1, R2                                                |
| A factor of 2.5 for the `T_0` shift, in the wrong direction.                                                                                                                             | `γ` = 1.4 the other way.                                                                                                                                                             | R4                                                    |
| `cv_d` in the moisture coefficient.                                                                                                                                                      | `cp_d` on the dry part.                                                                                                                                                              | R9                                                    |
| R9's `c(q) = q_d·cp_d + q_v·cp_v + q_l·cp_l + q_i·cp_i`, 1021.6 at `q_tot` = 0.02, spread 1.7%.                                                                                          | `(1 − q_tot)·cp_d + q_tot·cp_l`, 1068.0, spread 6.3%; the error was on the safe side.                                                                                                | R9                                                    |
| R9's "the largest `c(q)` sits in the warm moist low levels, which are the most negative".                                                                                                | The most negative cells are cold and dry.                                                                                                                                            | R9                                                    |
| `T_0`, `T_triple` and `T_freeze` "all 273.16".                                                                                                                                           | `T_freeze` is 273.15.                                                                                                                                                                | [archive](archive/2026-09-23/FINDINGS.md), §6         |
| The acceptance test in the C1 TOML's header.                                                                                                                                             | It could not run, and never read the file.                                                                                                                                           | R8                                                    |
| "The shift grows `∫\|ρe_tot\|` about 2.2×".                                                                                                                                              | 2.84× at t = 0 and 2.85× at 24 h.                                                                                                                                                    | E15, R11                                              |
| That the only alternative to shifting the model's reference was shifting the share's denominator.                                                                                        | Rebasing the tags onto the shifted total, the offset, leaves the model alone.                                                                                                        | R10, E17                                              |
| The one-iteration implicit solve as the cause of E16.                                                                                                                                    | Converged, `ρ`'s one-step difference is 3.6e-5 against 3.8e-5.                                                                                                                       | E16                                                   |
| The limiter as all of E16.                                                                                                                                                               | Off, it brought `ρ` from 3.6e-5 to 3.7e-8, not to rounding.                                                                                                                          | E16                                                   |
| The surface-flux code path as the rest of E16.                                                                                                                                           | Off as well, `ρ`'s difference stays 3.71e-8.                                                                                                                                         | E16                                                   |
| "A source tag went negative", naming `extratropics`.                                                                                                                                     | `phase_c.jl` called a region tag a source tag.                                                                                                                                       | M5                                                    |
| `.out` for the timing figures.                                                                                                                                                           | They are in `.err`.                                                                                                                                                                  | M4                                                    |
| An estimate at each step's start as enough to screen the operators.                                                                                                                      | Over the first ten minutes it missed by more than the change, 346,100 against 142,700 J m⁻²; after them by 1.4%.                                                                     | E25                                                   |
| Evaluating the tendencies on the run's own cache between steps as harmless.                                                                                                              | It changed the run; the script now uses a second simulation.                                                                                                                         | E25, E31                                              |
| E20's reading of the sphere's gap as the per-tag limiter or the share clamp.                                                                                                             | The rain-out's production; then the per-tag limiter.                                                                                                                                 | E28, E30, E37                                         |
| E20 and E23: the column's 17,954 J kg⁻¹ gap and 1.37 MJ m⁻² unrecorded.                                                                                                                  | Subsidence and the rain-out, to the joule; form A 60.7 with them listed.                                                                                                             | E26                                                   |
| E28: a 149 J kg⁻¹ sphere gap with no tag for it.                                                                                                                                         | An `mp` tag closes it to 20.2.                                                                                                                                                       | E30                                                   |
| E34's reading of the audit's first-hour residual as the initial adjustment.                                                                                                              | The one-iteration Newton increment.                                                                                                                                                  | E39, E39b                                             |
| E32's +196 J m⁻² as possibly the tags' missing Jacobian block.                                                                                                                           | The loss rule; the block's lag is −7.8 J m⁻².                                                                                                                                        | E39                                                   |
| E33's open points: form A 117 J kg⁻¹ and form B −5.3 J m⁻².                                                                                                                              | The per-tag transport, and the Newton lag.                                                                                                                                           | E43                                                   |
| That under the audit the tags follow the parent's vertical flux at the stage state.                                                                                                      | At the solved stage state; the parent's side is the one-iteration increment.                                                                                                         | E39                                                   |
| That the repair would bring the audit's sphere form A back to C7's 20 J kg⁻¹.                                                                                                            | 274 J kg⁻¹ with the repair.                                                                                                                                                          | E35                                                   |
| E35 as first written: form A "with the repair's ledgers taken back out" is 54.9 J kg⁻¹, so the clamp is at most part of C9's gap.                                                        | The ledgers are not transported; off by up to 22.0 J kg⁻¹ against C9, 219 under tracer transport. Corrected 2026-09-11.                                                              | E35                                                   |
| LEARNINGS, C9's carry-over: read form A with the repair on.                                                                                                                              | C10's entry: read it as a global integral, and without the repair.                                                                                                                   | E38                                                   |
| That `ρ` is not hyperdiffused, so the offset adds nothing to the audit's hyperdiffusion.                                                                                                 | `hyperdiffusion.jl:495-497` takes the water flux out of `ρ`; fixed in #72, `7a290c98`, 2026-09-11.                                                                                   | archive/2026-09-23/ENTHALPY_AUDIT_DESIGN.md           |
| That vertical diffusion makes D1's gross residual, and cannot be told apart from the upward branch (E42).                                                                                | The twin without it has the same gross, 2.350e6 against 2.370e6 J m⁻²; the branch lifts a fifth.                                                                                     | E42b                                                  |
| That the tag code's recursion makes the EDMF build slow (E44c's candidate).                                                                                                              | ClimaCore's Jacobian solver.                                                                                                                                                         | E44d                                                  |
| That solving the tags in a group of their own removes the growth.                                                                                                                        | The prototype took as long.                                                                                                                                                          | E44d                                                  |
| E52: the fork builds the EDMF column in 635 s where upstream takes 249 s.                                                                                                                | The whole build takes the same time.                                                                                                                                                 | E56                                                   |
| E53's 5.41e5 J/m² and E59's base, 6.32e5, as one D4 baseline.                                                                                                                            | 17% apart, since E53 ran before #89 with ClimaCore 0.16 and upstream v0.42.9. Not interchangeable.                                                                                   | E59                                                   |
| C1c, the SGS diffusive flux under the audit (decision 6 of 2026-09-18).                                                                                                                  | Each placement makes D4's residual larger; shelved.                                                                                                                                  | E59, E61, E62                                         |
| An estimate given to the owner: misplaced energy levels off at 0.5 to 5% of `E` within weeks.                                                                                            | It does not hold.                                                                                                                                                                    | E60                                                   |
| E68's premise that `ψ − q_gas_A` is the updraft gap alone; a lasting error of about 3 points of share in the boundary layer, the tags taking in about a third less of the entrained air. | Attribution by mask adds to it; the gap alone is 0.3 points at 6 h and 1.3 at 24 h. Erratum 2026-09-19.                                                                              | E68, E73                                              |
| E69's third point: the sphere's residual is the explicit processes the tags do not follow, and Float32.                                                                                  | Float32 rounding alone. Erratum 2026-09-19.                                                                                                                                          | E70                                                   |
| The old to-do list's plan to compare V2's one-iteration run with `g2_v2_sphere_newton10`.                                                                                                | The atmospheres differ by 4 K at 1 h; `g2_v2_sphere_n2` is the run to compare.                                                                                                       | E69, E74                                              |
| E73's cost: the copies double the tendency build, 789 s against 402 s.                                                                                                                   | A smoke test's numbers; the D4 runs took 3504.1 s against 600.3 s. Erratum 2026-09-23.                                                                                               | E73                                                   |
| E75: `rad` L1 at 1 h is 0.15%.                                                                                                                                                           | 0.108%. Erratum 2026-09-23.                                                                                                                                                          | E75                                                   |
| The updraft-gap-bound script's headline: 15 to 30% a day of the tropical surface tags, elsewhere under 4%.                                                                               | Under the centred reconstruction 46% and 27% for `sfc`, and 9 to 51% elsewhere.                                                                                                      | review/agent_reviews/updraft_gap_bound/review.md; E72 |
| That `dd06318f`'s fixes "change no simulation results".                                                                                                                                  | With an explicit species list the fork runs `enforce_mass_energy_consistency!`, which upstream `v0.42.9` skips. Read from the code, not run; a named parity exception (decision 12). | [DECISIONS.md](DECISIONS.md)                          |
| E77: the exchange allocates 17,416 bytes only at ClimaCore's compat floor and 8 bytes with 1.0.0, so the test's bound can follow the ClimaCore version.                                  | 17,416 bytes with 0.16.0, 1.0.0 and 1.0.1 alike, from the kernel's lazy inputs. Written to scratch, 8 bytes on all three. Erratum 2026-09-23.                                        | E77, E78                                              |
| E77: the downgrade CI failed in `tagging_source_updraft`.                                                                                                                                | In `tagging_source_increment` and `tagging_source_edmf`, run `35836620186`. Erratum 2026-09-23.                                                                                      | E77                                                   |

## 13. What is not established

The open questions of the old section 7, with the IDs of
`review/register/items.csv` and where each is tracked now. Other bounds stay in
their entries as "not separated".

| ID             | open question                                                                                     | tracked in                                                                  |
|:-------------- |:------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------- |
| FQ-3           | What starts E16's remainder once the limiter is off: 3.7e-8 in `ρ` after one step, 5.8e-6 by 5 h. | [BACKLOG.md](BACKLOG.md)                                                    |
| FQ-4           | Why a tag goes negative under a positive parent (E14).                                            | BACKLOG                                                                     |
| FQ-5           | What makes the residual's first-minute jump (E13, E25).                                           | BACKLOG                                                                     |
| FQ-6           | Why C5's radiation tag outgrows C3's after four hours (E24).                                      | BACKLOG                                                                     |
| FQ-10          | How much provenance the upward branch moves where ice persists (D1: a fifth, E42b).               | G4_TODO G4.11                                                               |
| FQ-11          | What makes D1's zero-sum gross residual (E42, E42b).                                              | [G4_TODO.md](G4_TODO.md) G4.6                                               |
| FQ-13          | 2M and P3, behind the model's gate (E41).                                                         | BACKLOG (upstream gate)                                                     |
| FQ-15          | Whether the audit's transport clamp is all of its sphere form-A gap (E36).                        | [G4_TODO.md](G4_TODO.md), "Energy items within M1 to M5"                    |
| FQ-17          | What the sphere's converged 17% is (E39b).                                                        | [G4_TODO.md](G4_TODO.md) G4.6                                               |
| FQ-21          | Float32 beyond a day, under the audit, with 1M, on a GPU (E45).                                   | [G4_TODO.md](G4_TODO.md), "Items that G3 takes up" (G3_TODO V-W7 for water) |
| FQ-22          | Whether 1M changes the water residual on a sphere (W5b).                                          | [G4_TODO.md](G4_TODO.md), "Items that G3 takes up" (G3_TODO)                |
| FQ-23          | The tag cost on a GPU, and under EDMF (T4, T9).                                                   | BACKLOG (M6); G3_TODO WP9                                                   |
| FQ-24          | R11's suppression cost over long runs (E19).                                                      | G4_TODO G4.10                                                               |
| LEARNINGS:A2:1 | Why the linear water ladders are sub-first-order (W1).                                            | BACKLOG, "M0 to M5, not energy-specific"                                    |

Settled, and struck in the original: FQ-1 (E9b), FQ-2 (R8), FQ-7 (E28, E30),
FQ-8 (E37), FQ-9 (E39), FQ-12 (E53), FQ-14 (E43), FQ-16 (E39, E39b), FQ-18
(E26), FQ-19 (E34) and FQ-20 (E46; E48 then showed a 10° mask removes the
trades).
