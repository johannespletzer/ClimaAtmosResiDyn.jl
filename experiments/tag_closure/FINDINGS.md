# Findings register

Everything the tag-closure series has established, in one place, for later
reference. One line of claim, the number that supports it, and the run it came
from. The reasoning is in [LEARNINGS.md](LEARNINGS.md), one entry per run; the
C1 argument is in [C1_reference_shift.md](C1_reference_shift.md); what to run
next is in [LEVANTE_TASKS.md](LEVANTE_TASKS.md).

State as of 2026-09-10 on `claude/tag-closure-experiments`. 17 of 25 configured
runs are live in `output/`. Phase A and phase C are complete except for C1 and
C2, which need approval.

A finding here is something a run measured. Where a claim is bounded — one
geometry, one resolution, an uncontrolled comparison — the bound is part of the
finding and is stated with it.

## 1. Water tags

**W1. The residual is limiter-bounded, not discretization-bounded.** The default
van Leer ladder is flat across `dt` 10, 5 and 2.5 s, slope −0.011, while both
linear ladders converge: +0.255 under `first_order` and +0.464 under `none`. At
`dt` 10 s the fully linear reconstruction sits 13.8× below van Leer. *A1, A2.*

**W2. So implicit water tags are not worth their Jacobian cost.** Moving the
tags into the implicit solve would remove discretization error, and W1 says that
is not the part that is there. This was the question phase A was built to
answer, and it is answered. *A1, A2.*

**W3. A column trips no limiter, so the ladders measure operator disagreement
with nothing subtracted.** The correction ledger is identically zero across all
eleven column runs. *A1–A4.*

**W4. `Float32` costs nothing on a column.** `a4_float32` gives 2.745e-5 against
`a1_dt10`'s 2.660e-5 at the same configuration — a 3% difference. Explicitly not
established on a sphere. *A4.*

**W5. A3 is uninterpretable as it stands.** `a3_1m` reads 5.50e-6 against
`a1_dt10`'s 2.66e-5, but it differs in two keys, `microphysics_model` *and*
`vert_diff`, so the gap is not attributable to 1M. One matched 0M column run
with `vert_diff` on would separate them. The config is deliberately not written.
*A3.*

**W6. Issue #64: the water tags diverged to 1e130 on a sphere while `ρq_tot`
stayed bounded, and the run exited 0 reporting success.** `gross_relative` ran
3.07e-5 at 1 h, 0.809 at 3 h, 24.2 at 4 h, 5.9e113 at 24 h, with the parent at
1.62e16 throughout. *A5, pre-fix, archived under
`output/a5_sphere_limiter/before_issue_64_fix/`.*

**W7. The mechanism was the multiplicative rescale itself, not its documented
precondition.** Writing `e = ρq_tot − Σₖ ρq_tag_k`, the old rule gave
`e_after = r · e_before` in *every* cell with a positive parent, unconditionally
— scaling the tags scales the error with them. The docstring's
`ρq_tag ≤ ρq_tot_before` governs non-negativity, not closure. *Verified against
source, 200,000 randomised correction sequences.*

**W8. The existing test could not see it.** `tagged_water_integration.jl:237`
runs this configuration for one hour and asserts below 1e-2. At one hour the
value is 3.07e-5. The window ended before the failure.

**W9. The fix holds through a full day, and plateaus.** Post-fix `gross_relative`
is 1.89e-4 at 6 h, 2.51e-4 at 12 h, 2.79e-4 at 24 h — each doubling of elapsed
time adding less. Exit 0, the `abort_above` level of 1.0 never approached, and
36× of margin against the integration test's bound. *A5, re-run at `8ed98b6`.*

**W10. It did not hold closure by emptying the tags.** `orphaned_relative` is
2.5e-9, five orders below the residual, so almost no mass sits in cells whose
parent holds water while every tag is empty. `nonpositive_fraction` is unchanged
at 0.35–0.36 and the signed residual is −7.5e-6 relative. This was the one
outcome `gross_relative` could not distinguish from a runaway, and it is
excluded by measurement rather than inference. *A5 audit.*

**W11. The residual is balanced, not directional.** `untagged_relative` 1.3556e-4
against `overclaimed_relative` 1.4307e-4, a 5% difference. A runaway is one-sided
by construction — the pre-fix run was pure overclaim — so an even split is
transport leakage. *A5 audit.*

**W12. The corrections changed character, which is the mechanistic evidence.**
Before, the ledger was one-sided: `q_tag_fix_extratropics` 1.027e115 against
`q_tag_fix_tropics` 4.55e109, a factor of 2e5. After, the two per-tag maxima
agree to fifteen digits while the maximum of their sum is smaller than either —
sum-preserving redistribution, which is what the additive rule was designed to
produce. Domain maxima rather than per-cell values, so a signature rather than a
proof. *A5.*

**W13. Phase A now has a sphere operator residual.** `max |q_tag_res|` is 1.9e-5
and flat from about 6 h. The column at `dt` 10 under the same limiter gives
2.84e-6. Not a controlled comparison — A5 is `dt` 300 on `h_elem` 4 against a
30-level column at `dt` 10 — and a 30× larger timestep costing 6.8× is on the
favourable side. Reduced over the remapped lat-lon field. *A5.*

**W14. The ledger keeps growing while the residual does not.** 6.2e-4 at 24 h,
33× the residual, still rising. The limiter works all day and the corrections
absorb it; what stopped is the amplification. *A5.*

## 2. Energy source tags

**E1. The donor rule is inert over almost the whole domain.** The share
`ρe_src_k / ρe_tot` is undefined where `ρe_tot ≤ 0` and `energy_source_fraction`
returns zero there, so the loss half never runs while production still does.
That is **96.7% of the DYCOMS column** and **43.276% of a moist sphere**, the
latter constant to the last digit across 24 hours. *C0.*

**E2. Production therefore accumulates without loss, invisibly.** A source tag
reaches −209 J kg⁻¹ on the sphere while `e_src_res` shows nothing, because the
residual sums only the pure region tags. *C0.*

**E3. One level crossing changes the behaviour of the whole column.** The `rad`
tag's non-monotone drop coincides exactly with the transition from 30 to 29
non-positive levels: the single hour in which a level turns positive is the
single hour the tag loses anything. *C0.*

**E4. The closure residual reaches 13.5% of `∫|ρe_tot|` in one day**, growing
monotonically. Production with no compensating loss, seen from the budget side.
*C0, C3, identically.*

**E5. The non-positive region is the troposphere, not a thin layer or a domain
artifact.** On the sphere every level from 250 m to 11.0 km is 100% negative and
every level from 15.5 km up is 0%, with no mixed level. `0.43276 × 30 km` =
12.98 km places the sign change between them. The column is negative at all 30
levels with a clean step at 825 m, where the DYCOMS inversion is. *C0,
`where_negative.jl`.*

**E6. The smallest shift making the field positive is 45.4 kJ kg⁻¹ on the column
and 100.4 kJ kg⁻¹ on the sphere.** Because E5 puts the negative region in the
bulk troposphere, the shift cannot be made small. *C0.*

**E7. C3 is a controlled comparison.** It reproduces `c0_column` bit for bit —
`gross_relative` 0.13456131085846748, `max_abs_e_src_res` 26888.66561703798,
most-negative tag −44972.50629142498. The process record perturbs nothing, so
any disagreement between the two readings is a property of the readings. *C3.*

**E8. And on that run the source tag misses the dominant physical term.**

| reading of what radiation did    | min (J kg⁻¹) | max (J kg⁻¹) |
|:-------------------------------- |:------------ |:------------ |
| source tag `e_src_rad`           | −2.07e-9     | +4,321       |
| process record `e_prc_radiation` | −20,566      | +7,587       |

The tag is pinned at zero from below by E1 and can only accumulate. The record
says the larger excursion is cooling, −20.6 kJ kg⁻¹, and cloud-top radiative
cooling is the entire point of a DYCOMS stratocumulus column. The warming halves
disagree by 1.75× as well. *C3.*

**E9. So the alternative is demonstrated, not merely available.** The energy
process record reads the physics the tags cannot, on exactly the configuration
where the tags are inert, and it is reference-independent so nothing in C1 can
touch it. Two cautions: a record is a signed running total of what a process
applied and a tag is a share of what is present, so the columns in E8 are not
the same quantity and should not be differenced; and a record answers "what did
radiation do" rather than "what fraction of the energy here came from
radiation". *C3.*

**E10. The barrier is structural, not numerical.** No tolerance and no accuracy
makes an undefined quantity readable. Total energy has no physical zero at any
reference, so a shift relocates the arbitrariness rather than removing it. C1
can test whether a well-posed donor *rule* is achievable; it cannot test whether
the reading is meaningful.

## 3. The energy reference

**R1. The convention is enthalpy zero, not internal-energy zero.**
`internal_energy_dry(T) = cv_d·(T − T_0) − R_d·T_0`, and
`internal_energy_dry(T_0 = 273.16)` returns −78396.92, which is `−R_d·T_0` at
`R_d` = 287.0. *Read from Thermodynamics on Levante.*

**R2. The 7.8e4 J kg⁻¹ gap C0 could not account for is that term.**
`TD.total_energy` on the DYCOMS surface state returns −44,009 against the field's
−43,125, the 2% being the approximated state. The function reproduces the field,
so the offset is a convention and **not an initialisation error**. C0's 43.276%
stands, and C1 is legitimate rather than a treatment of a symptom.

**R3. ClimaAtmos already carries the convention in its own analytic Jacobian.**
`manual_sparse_jacobian.jl:835` and `:1805` write `T_0 * cp_d`, not `T_0 * cv_d`.

**R4. The derivative that sets any reference shift is `−cp_d`.** So lowering
`T_0` is more effective than the textbook reading by exactly `γ = cp_d/cv_d`
= 1.4. The sphere needs `ΔT_0` = 100.0 K and the column 45.2 K.

**R5. `T_0` is not a free datum.** `LH_v(T) = LH_v0 + (cp_v − cp_l)(T − T_0)`
with `cp_v − cp_l` = −2322, so moving `T_0` to 173.2 K with `LH_v0` fixed drops
the latent heat of vaporisation at 288.3 K by 9.4%. That is a change of physics,
which is what this shift shape was chosen to avoid. **Confirmed against the
package**: `latent_heat_vapor(288.3)` returns 2.46564492e6 against a predicted
2,465,644.92.

**R6. But everything physical depends on `T_0` only through `LH_0 − Δcp·T_0`, so
the shift has an exact invariance.** The map

```
T_0 → T_0 + δ,  LH_v0 → LH_v0 + (cp_v − cp_l)·δ,  LH_s0 → LH_s0 + (cp_v − cp_i)·δ
```

leaves every latent heat and the saturation vapour pressure unchanged while
moving `e_int` by `−cp_d·δ`. `LH_f0` needs `(cp_l − cp_i)·δ` and gets it for
free, being `LH_s0 − LH_v0`.

**R7. C1 therefore needs no code change.** The settable fields include `T_0`,
`LH_v0` and `LH_s0`, and exclude `LH_f0`, every `cv_*` and `e_int_v0`, which are
derived. `create_parameters.jl:75` builds the thermodynamic parameters entirely
from the TOML dict. C1 is three TOML entries plus the owner's approval.

**R8. And its acceptance test is exact.** After the change `LH_v(288.3)`,
`LH_f(273.16)` and `p_sat(288.3)` must return 2.46564492e6, 333600.0 and
1721.1532852305072 unchanged, while `internal_energy_dry(288.3)` moves from
−67533.97 to +32865.8. A latent heat that moves means the run measures a
different atmosphere rather than a different reference. Before-values recorded in
`LEVANTE_TASKS_RESULTS.md`.

**R9. The shift is not a constant.** Its coefficient is
`c(q) = q_d·cp_d + q_v·cp_v + q_l·cp_l + q_i·cp_i`, running 1004.5 dry to 1021.6
at `q_tot` = 0.02, a 1.7% spread. This does not break the closure identity — the
tags are shares of the same recomputed `ρe_tot` — but it means "the shift" has no
single value and positivity must be checked pointwise. It helps: the largest
`c(q)` sits in the warm moist low levels, which are the most negative.

**R10. Shifting only the share's denominator should be dropped rather than
costed.** The region tags sum to `ρe_tot` and not to `ρe_tot + c`, so wherever
`e < 0` the shares sum to a negative number and the loss *adds* energy, diverging
as `e` approaches `−c` — over exactly the region the shift exists to fix.

**R11. C1's remaining costs are firm rather than conditional.** The shift must
clear the tropospheric minimum (E6) so it cannot be small; the discriminating
part of a source tag's share goes as `1/(e + c)`, so the donor rule becomes
several times less discriminating where it already works; and the closure check
normalises by `∫|ρe_tot|`, which the shift grows about 2.2×, so the same absolute
residual reports a smaller relative one and would read as an improvement that did
not happen.

## 4. Cost

**T1. Compilation dominates these jobs.** `a1_dt10` reports `solve! walltime =
3.337` s inside a job that took 295 s, with `sypd: 2.956` and
`wall_time_per_timestep: 9 ms 269 µs`. Job wall times therefore cannot be read
as a tag cost.

**T2. The A1 configuration costs 6.1× its untagged control**, and the three
measures agree exactly:

| | tagged | untagged | ratio |
|:-------------------- |:------- |:-------- |:----- |
| `solve! walltime` | 3.337 s | 0.548 s | 6.09 |
| `sypd` | 2.956 | 17.992 | 6.09 |
| per timestep | 9.269 ms | 1.522 ms | 6.09 |

**T3. But that is the cost of the configuration, not of the tags.** The tagged
side carries three water tags *and* `water_closure_check` at `period: "10secs"`
against a `dt` of 10 s — a global reduction on **every timestep** — plus
diagnostics every 60 s. The check frequency is a diagnostic choice no production
run would make, and it is the term most likely to dominate. Reading 6.1× as a
tag cost would be wrong.

**T4. The clean measurement exists as a configuration and is missing one file.**
The C0 pair is the one to use: three energy source tags with the closure check
and the diagnostics both hourly, over 8640 steps rather than 360. Only the
untagged half is known — `sypd` 27.779 at 986 µs per timestep — because
`c0_column`'s `.err` was never committed. Nor was any other tagged run's except
`a1_dt10`.

**T5. Short runs flatter nothing but they do skew per-step figures.** The two
untagged columns read 1.522 ms and 986 µs per timestep for the same 30-level
column at the same `dt`, because one ran 360 steps and the other 8640. Fixed
overhead weighs differently. The A1 pair is still internally consistent — both
halves ran 360 steps — but the C0 pair would be the better number.

## 5. Method

**M1. Count fractions and mass fractions can differ by six orders of
magnitude.** On A5, `nonpositive_fraction` is 0.351 while
`nonpositive_mass_fraction` is 2.77e-7 — a factor of 1.3 million. For water,
"a third of the domain is non-positive" is about vanishingly dry cells. For
energy it should go the other way, since E5 puts the region in the troposphere
where the mass is, but **no run has measured it**: C0's 43.276% is quoted
throughout as a count fraction with no mass-weighted companion.

**M2. `untagged + overclaimed = gross_residual` exactly**, confirmed on a model
run and not only on randomised states. So the audit table says which *direction*
a residual came from where `gross_relative` says only how far.

**M3. The operator residual and the audit do not overlap.** The audit is a set of
volume integrals of the residual as it stands; the operator residual is a
pointwise `max abs` of that residual with the correction ledger added back.

**M4. Practical traps, all hit at least once.** `.buildkite` must be instantiated
on a login node under the run's own depot; `module purge` strips git, so
provenance facts are resolved before it; the repository's global `.gitignore`
entries for `output/`, `*.png` and `*.log` silently drop committed results; and
`sypd` is logged through `@info`, which Julia sends to **stderr**, so it is in
the `.err` and not the `.out`.

## 6. Claims that were made and then falsified

Kept because a later reader will otherwise re-derive them.

  - **The operator residual's sign.** Corrected by 20,000 randomised states, then
    verified independently and patched into the plan.
  - **The #64 mechanism.** The docstring precondition failing was not what
    breaks; the error is amplified whether or not it holds (W7).
  - **The −100 kJ kg⁻¹ offset as an initialisation error.** It is a convention
    (R2).
  - **An "effective reference near 381 K".** An artifact of reading the gap as a
    temperature in the wrong convention.
  - **A factor of 2.5 for the `T_0` shift, in the wrong direction.** It is
    `γ` = 1.4 the other way (R4).
  - **`cv_d` in the moisture coefficient.** The measured convention requires
    `cp_d` on the dry part (R9).
  - **Phase B gated on A5's divergence.** `b1_base` configures no limiter, and
    phase B is the energy family, which has no rescale and no partition repair,
    so #64's mechanism cannot reach it.
  - **`.out` for the timing figures.** They are in `.err` (M4).

## 7. What is not established

  - The energy family's mass-weighted non-positive fraction (M1).
  - Whether `p_sat` is in fact invariant under R6's map. The argument is
    structural; the recorded before-value tests it.
  - Whether anything assumes `T_0 == T_triple`. Nothing found, but nothing has
    ever moved them apart.
  - `Float32` on a sphere (W4).
  - Whether 1M changes the residual (W5).
  - The tag cost as distinct from the closure-check cost (T3, T4).
  - Whether C1's suppression cost (R11) matters in practice. Measurable now
    rather than open in principle.

## 8. Next

Beyond the two clerical items in [LEVANTE_TASKS.md](LEVANTE_TASKS.md):

 1. **C1.** Collect `cp_i` and the long ClimaParams names, write the three-entry
    TOML, get approval, run. The only thing left that can change the verdict on
    the source-tag family. R7 and R8 make it cheap and its result unambiguous.
 2. **`c0_sphere_deep`.** Ready to submit, no approval. The only configured run
    that produces the energy family's mass-weighted non-positive fraction, which
    M1 shows is the number the 43.276% has been standing in for.
 3. **`a3_0m_vert_diff`.** Written and validated. `a1_dt10` with `vert_diff` on
    and nothing else changed, so it differs from `a3_1m` in
    `microphysics_model` alone and from `a1_dt10` in `vert_diff` alone. Two
    single-key comparisons out of one column-hour, which is what W5 needs.
 4. **Phase B.** No technical objection left after W9 — B1 configures no limiter
    and the energy family has no rescale. Whether it is worth ten days of queue
    is a cost decision, not a risk one.
 5. **C2.** Unchanged: needs a code change and approval.
