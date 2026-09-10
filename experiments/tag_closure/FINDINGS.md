# Findings register

Everything the tag-closure series has established, in one place, for later
reference. One line of claim, the number that supports it, and the run it came
from. The reasoning is in [LEARNINGS.md](LEARNINGS.md), one entry per run; the
C1 argument is in [C1_reference_shift.md](C1_reference_shift.md); what to run
next is in [LEVANTE_TASKS.md](LEVANTE_TASKS.md).

State as of 2026-09-10 on `claude/tag-closure-experiments`. 20 of the 28
configured runs are live in `output/`. The latest is C1, which ran on LRZ
terrabyte. Phase A and phase C are complete except for C2, which needs a code
change and approval. `c0_sphere_audit` has a second reading, from terrabyte, in
`output/c0_sphere_audit/terrabyte/`.

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

**W5. A3's gap was vertical diffusion, not 1M.** `a3_1m` reads 29× below
`a1_dt10` on `max |q_tag_res|`, but it differs in two keys and the companion
separates them:

| step                                    | factor |
|:--------------------------------------- |:------ |
| `vert_diff` on, 0M held (a1 → a3_0m)    | 0.037  |
| 1M on, `vert_diff` held (a3_0m → a3_1m) | 0.934  |
| both (a1 → a3_1m)                       | 0.035  |

So **vertical diffusion accounts for 27× of the 29×** and 1M for 7%. *A1, A3,
`a3_0m_vert_diff`.*

**W5b. The 1M `q_tot_eff` mismatch is not measurable on a column, and does not
raise the residual.** Under 1M the parent's diffusion acts on
`q_tot − q_rai − q_sno` while the tags see their full content, and the memo
expected that to cost closure. Holding `vert_diff` fixed, 1M moves
`max |q_tag_res|` from 1.054e-7 to 9.845e-8 — 7% **down**. Bounded to a column,
which reaches only the vertical branch of the mismatch: hyperdiffusion and the
viscous sponge are horizontal and need a sphere. *A3, `a3_0m_vert_diff`.*

**W6. Issue #64: the water tags diverged to 1e130 on a sphere while `ρq_tot`
stayed bounded, and the run exited 0 reporting success.** `gross_relative` ran
3.07e-5 at 1 h, 0.809 at 3 h, 24.2 at 4 h, 5.9e113 at 24 h, with the parent at
1.62e16 throughout. *A5, pre-fix, archived under
`output/a5_sphere_limiter/before_issue_64_fix/`.*

**W7. The mechanism was the multiplicative rescale itself, not its documented
precondition.** Writing `e = ρq_tot − Σₖ ρq_tag_k`, the old rule gave
`e_after = r · e_before` in *every* cell with a positive parent, unconditionally
— scaling the tags scales the error with them. The docstring's
`ρq_tag ≤ ρq_tot_before` governs non-negativity, not closure. It is an identity
rather than a measurement: `ρq_tot_after = r · ρq_tot_before` is what `r` means,
so the same `r` multiplies the difference. *Verified against
`tagged_water.jl:800`. The randomised sequences it was first found with are not
in the tree.*

**W8. The existing test could not see it.** The "Tagged water limiter rescale"
testset runs this configuration for one hour (`tagged_water_integration.jl:237`)
and bounds the residual at `tagged_water_integration.jl:312`. That bound is
`max |residual| / max |ρq_tot|` and not `gross_relative`, so the two are not
comparable directly; on the archived pre-fix operator residual the test's own
quantity is 7.5e-6 at 1 h and 6.0e-5 at 2 h against a bound of 1e-2. Either way
the window ended before the failure, which starts between hours two and three.

**W9. The fix holds through a full day, and plateaus.** Post-fix `gross_relative`
is 1.89e-4 at 6 h, 2.51e-4 at 12 h, 2.79e-4 at 24 h — each doubling of elapsed
time adding less. Exit 0 and the `abort_above` level of 1.0 never approached.
Not stated as margin against the integration test's 1e-2, which bounds a
different quantity (W8). *A5, re-run at `8ed98b6`.*

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

**W13. Phase A now has a sphere operator residual.** `max |q_tag_res|` ends the
day at 1.9e-5, having reached 1.5e-5 by 6 h and 1.91e-5 by 17 h, after which it
is flat to three digits. The column at `dt` 10 under the same limiter gives
2.84e-6. Not a controlled comparison — A5 is `dt` 300 on `h_elem` 4 against a
30-level column at `dt` 10 — and a 30× larger timestep costing 6.8× is on the
favourable side. Reduced over the remapped lat-lon field. *A5.*

**W14. The ledger keeps growing while the residual does not.** 6.2e-4 at 24 h,
32× the residual, still rising. The limiter works all day and the corrections
absorb it; what stopped is the amplification. *A5.*

## 2. Energy source tags

**E1. The donor rule is inert over almost the whole domain.** The share
`ρe_src_k / ρe_tot` is undefined where `ρe_tot ≤ 0` and `energy_source_fraction`
returns zero there, so the loss half never runs while production still does.
That is **96.7% of the DYCOMS column's volume** and **43.276% of a moist
sphere's**, the latter constant to the last digit across 24 hours. *C0.*

**E2. Production therefore accumulates without loss, invisibly.** A source tag
reaches −209 J kg⁻¹ on the sphere while `e_src_res` shows nothing, because the
residual sums only the pure region tags. *C0.*

**E3. One level crossing changes the behaviour of the whole column.** `max e_src_rad` rises monotonically for all seven hours before the transition from 30
to 29 non-positive levels, falls by 137 J kg⁻¹ in the hour of the transition
itself, and every later decrease — 20 h to 23 h, four consecutive samples — is
also after it. The tag can lose only where a level supports a donor share.
*C0.*

**E4. The closure residual reaches 13.5% of `∫|ρe_tot|` in one day**, growing
monotonically. Production with no compensating loss, seen from the budget side.
*C0, C3, identically.*

**E5. The non-positive region is the troposphere, not a thin layer or a domain
artifact.** On the sphere every level from 250 m to 11.0 km is 100% negative and
every level from 15.5 km up is 0%, with no mixed level, so the sign change is at
the face between them. That face is at 13.02 km, and the r²-weighted volume
below it is 0.4327600 against the closure table's 0.4327600052941768 — the two
diagnostics agree to eight digits without sharing any code. (`0.43276 × 30 km` =
12.98 km reads the fraction as a height, which is 35 m low here and is not what
the fraction is; M1.) The column is negative at all 30
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

All four numbers are the last sample, at 24 h. The tag's minimum over the day is
−2.47e-9, at 1 h, and each of the other three is also its extreme over the day.
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

**E9b. And the barrier is 1.8× larger than the headline figure.**
`c0_sphere_audit` is `c0_sphere` with `audit: true` and nothing else changed. It
measures `nonpositive_mass_fraction` = **0.7839** against
`nonpositive_fraction` = 0.43276, a ratio of 1.811, near-constant across the day
(0.7813 at t = 0). So the share of `∫|ρe_tot|` sitting where the donor share is
undefined is **78.4%, not 43.3%** — the volume fraction quoted throughout this
series understates the barrier, because the non-positive region is the
troposphere and that is where the field's magnitude is (E5, M1). *C0 audit.*

**E9c. The energy residual is directional, where water's is balanced.**
`overclaimed_relative` 1.2245e-2 against `untagged_relative` 3.1795e-3, a ratio
of 3.85: the tags hold more than the parent, persistently. That is production
without loss (E2) seen in the audit, and it is the opposite of A5's water
residual, which split evenly and read as transport leakage (W11).
`orphaned_relative` is exactly 0.0 at every sample, so no cell has a parent
holding energy while every tag is empty. The identity of M2 holds again:
3.1795e-3 + 1.2245e-2 = 1.5424236987e-2 = `gross_relative`. *C0 audit.*

**E10. The barrier is structural, not numerical.** No tolerance and no accuracy
makes an undefined quantity readable. Total energy has no physical zero at any
reference, so a shift relocates the arbitrariness rather than removing it. C1
can test whether a well-posed donor *rule* is achievable; it cannot test whether
the reading is meaningful.

**E11. Under C1's shift the parent is positive everywhere, all day.**
`nonpositive_fraction` and `nonpositive_mass_fraction` are 0.0 at every hourly
sample, and so is `orphaned`. So for the first time in this series the loss half
of the donor rule runs over the whole domain. `energy_source_tags.md` says that
donor-proportional loss through a real bracketed solve "is not validated",
because no configured run had a positive reference. C1 is that run. The shifted
atmosphere is not exactly the unshifted one: they differ by up to 1.1e-3 in
`uₕ` over the day (E16), far less than the closure differences E12 to E15 read.
*C1, read against `c0_sphere_audit` re-run on the same machine, as are E12 to
E15.*

**E12. With the loss running, the residual stops being directional and grows
more slowly.** The audit's overclaim-to-undertag ratio stays between 1.002 and
1.033 all day, where the unshifted run climbs from 1.49 at 3 h to 3.85 at 24 h.
The absolute `gross_residual` at 24 h is 1.846e21 against 2.626e21, 0.70 of the
unshifted value. After the first hour it grows 48%, where the unshifted one
grows 113%. So what the shift removes is the production-without-loss part of the
residual (E9c). *C1.*

**E13. Both runs make the same jump in the first hour, so that part does not
depend on the reference.** `gross_residual` goes from about 1e7 at t = 0 to
1.2485e21 in C1 and 1.2343e21 unshifted at 1 h, 1.2% apart. In C1 that first
hour is 68% of the day's residual. `energy_source_tags.md` names a candidate that
does not depend on the reference: `ρe_tot` is transported as enthalpy, pressure
work included, while the tags ride the passive-tracer path, and the two fluxes
differ by `p·u`. That fits every number here, but no run has isolated it, so it
is a reading and not a measurement. *C1.*

**E14. A positive parent does not keep the tags non-negative.** The source tag
`sfc` reaches −219.9 J kg⁻¹ at 24 h, against −209.2 unshifted. The region tags
reach −11,575 (`tropics`, at 7 h) and −9,632 (`extratropics`, at 4 h) while the
parent is positive everywhere. So the non-positive parent is not what makes E2's
source tag negative: with it removed, the tag is as negative as before. The
design page names two other routes, the finite-step donor loss and unlimited
explicit transport with no partition repair. Which one it is here is not
established. Minima of the remapped lat-lon field, like every sphere number in
this series. *C1.*

**E15. `gross_relative` improves 4.06×, and 2.85× of that is the scale.** It is
0.00380 against 0.01542 at 24 h. The normalising `∫|ρe_tot|` is 2.84× larger at
t = 0 and 2.85× at 24 h, which is R11's trap, measured. The absolute ratio of
E12, 0.70, is the comparison that means something. *C1.*

**E16. The shift is not a pure relabelling in the discrete model.**
`run_c1_twin.jl` runs C1's configuration with and without the shift in one
process and compares the prognostic state. At t = 0 the two agree exactly, and
`ρe_tot` differs by the predicted shift to 5.5e-16. After one 400 s step they
differ by 3.8e-5 in `ρ`, 7.8e-6 in `ρq_tot`, 1.3e-4 in `uₕ` and 3.5e-4 in `u₃`,
each relative to the field's own maximum. They are this size after a single
step, so the step makes them; they are not amplified rounding. Over the day `ρ`
stays near 3e-5 while the others grow: `ρq_tot` to 1.1e-4, `uₕ` to 1.1e-3, and
`u₃`, which is small, to 6.2e-2. `c1_acceptance.jl` found the Thermodynamics
functions and the surface flux formula invariant, so the cause is elsewhere in
the step.

**It is not the implicit solve.** C1 takes one Newton iteration per stage, with
an approximate Jacobian that carries `T_0` and `e_int_v0` directly
(`manual_sparse_jacobian.jl:694-701`, `:835`, `:1805`), and that was the first
suspect. A second twin converged the solve in both halves
(`max_newton_iters_ode: 10`, `use_newton_rtol: true`, `newton_rtol: 1e-10`).
The step cost rose from 3.2 s to 10.0 s, so it iterated. After one step the
twins still differ by 3.6e-5 in `ρ`, 7.4e-6 in `ρq_tot`, 1.3e-4 in `uₕ` and
4.1e-4 in `u₃`. Converging a solve that was the cause would have shrunk that by
orders of magnitude, and instead `ρ`'s moved by 6% and `u₃`'s grew. So the
difference is in the tendencies themselves.

**The leading candidate is the limiter on vertical energy transport.** After
each Newton solve, a hook corrects the central vertical advection of `ρe_tot`
and `ρq_tot` towards an upwinded one, using `energy_q_tot_upwinding`, which C1
runs as `vanleer_limiter` (`implicit_tendency.jl:335-372`, the `T_post_imp!`
hook). It acts on `h_tot`. The shift adds to `h_tot` a constant plus
`(cp_l − cp_d)·|δ|·q_tot`, which is 3.5 to 7 kJ kg⁻¹ where `q_tot` is 10 to
20 g kg⁻¹. A limiter built on differences passes the constant through
unchanged. The `q_tot` part is about as large as the level-to-level differences
it limits, so its choices change from the first step. The hook runs after the
solve, which is why converging the solve changed nothing. The other candidates
are argued out. Saturation adjustment solves the same equation for `T` in both
runs, because every water phase shifts by the same `cp_l·|δ|`. Hyperdiffusion
moves `ρ` with the water it diffuses (`hyperdiffusion.jl:484-487`) and carries
each phase's enthalpy, which moves by exactly what a relabelling needs. These
are arguments, reached in discussion with the reviewer agent that proposed the
tag-side shift of §8, and no twin has isolated the limiter yet. *Twin tests, SLURM jobs
`13383683` and `13384080` on terrabyte, `output/twin_c1/` and
`output/twin_c1_newton/`.*

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

**R8. And its acceptance test is exact, and it passes.** After the change
`LH_v(288.3)`, `LH_f(273.16)` and `p_sat(288.3)` must return 2.46564492e6,
333600.0 and 1721.1532852305072 unchanged, while `internal_energy_dry(288.3)`
moves by `−cp_d·δ` and nothing else. A latent heat that moves means the run
measures a different atmosphere rather than a different reference.
`analysis/c1_acceptance.jl` builds the parameters from
`toml/tag_closure_c1_reference.toml` the way a run does and makes 38 checks,
over every temperature from 150 K to 330 K rather than at three points. All
pass. The worst relative change in any latent heat or saturation pressure is
9.2e-16. *Run on terrabyte, 2026-09-10.* The test that used to sit in the TOML's
header could not have run at all (§6). Before-values are in
`C1_reference_shift.md`'s appendix.

**R9. The shift is not a constant.** Under C1's map every water phase moves by
`cp_l·|δ|`, not by its own heat capacity, because moving `LH_v0` and `LH_s0`
with `T_0` cancels the difference. So the coefficient is
`c(q) = (1 − q_tot)·cp_d + q_tot·cp_l`, running 1004.5 dry to 1068.0 at
`q_tot` = 0.02, a 6.3% spread. This does not break the closure identity — the
tags are shares of the same recomputed `ρe_tot` — but it means "the shift" has no
single value and positivity must be checked pointwise. The larger moist
coefficient does not land where the margin is needed. At t = 0 the parent's
minimum is −100,416 J kg⁻¹ in the extratropics, against −23,686 in the tropics,
so the most negative cells are cold and dry and the sizing rests on the dry
coefficient. *Measured by `analysis/c1_acceptance.jl` on each phase alone and on
six states from dry to mixed-phase; the minima are C0's region tags at t = 0.
The coefficient and the location first recorded here were wrong (§6).*

**R10. Shifting only the share's denominator should be dropped rather than
costed.** The region tags sum to `ρe_tot` and not to `ρe_tot + c`, so wherever
`e < 0` the shares sum to a negative number and the loss *adds* energy, diverging
as `e` approaches `−c` — over exactly the region the shift exists to fix. That
rules out this shape, not the route. If the tags are rebased onto the shifted
total as well, the shares sum to 1 exactly and the model is left alone (§8,
item 1).

**R11. C1's remaining costs are firm rather than conditional.** The shift must
clear the tropospheric minimum (E6) so it cannot be small; the discriminating
part of a source tag's share goes as `1/(e + c)`, so the donor rule becomes
several times less discriminating where it already works; and the closure check
normalises by `∫|ρe_tot|`, which the shift grows 2.85×, so the same absolute
residual reports a smaller relative one and would read as an improvement that did
not happen. *The 2.85× is measured on C1 (E15). Before C1 ran it was recorded
here as about 2.2× (§6).*

## 4. Cost

**T1. Compilation dominates these jobs.** `a1_dt10` reports `solve! walltime = 3.337` s inside a job that took 295 s, with `sypd: 2.956` and
`wall_time_per_timestep: 9 ms 269 µs`. Job wall times therefore cannot be read
as a tag cost.

**T2. The A1 configuration costs 6.1× its untagged control**, and the three
measures agree to three digits:

|                   | tagged   | untagged | ratio |
|:----------------- |:-------- |:-------- |:----- |
| `solve! walltime` | 3.337 s  | 0.548 s  | 6.09  |
| `sypd`            | 2.956    | 17.992   | 6.09  |
| per timestep      | 9.269 ms | 1.522 ms | 6.09  |

The agreement is within one log rather than across runs. `output/a1_dt10/` holds
a second `.err` for the same configuration, job `27360071`, which gives 3.274 s,
3.012 and 9.095 ms — the same three-way agreement at 5.97. So the ratio carries
about 2% of run-to-run scatter and 6.1× is one of two readings, not a repeat
measurement. *A1, jobs `27360483` and `27360071`.*

**T3. But that is the cost of the configuration, not of the tags.** The tagged
side carries three water tags *and* `water_closure_check` at `period: "10secs"`
against a `dt` of 10 s — a global reduction on **every timestep** — plus
diagnostics every 60 s. The check frequency is a diagnostic choice no production
run would make, and it is the term most likely to dominate. Reading 6.1× as a
tag cost would be wrong.

**T4. And the clean measurement now exists: 1.32×.** The C0 pair is the one to
use — three energy source tags with the closure check and the diagnostics both
hourly, over 8640 steps rather than 360 — and both halves are in `output/`:

|                   | tagged   | untagged | ratio |
|:----------------- |:-------- |:-------- |:----- |
| `solve! walltime` | 11.225 s | 8.521 s  | 1.317 |
| `sypd`            | 21.088   | 27.779   | 1.317 |
| per timestep      | 1.299 ms | 986.3 µs | 1.317 |

So T3's reading is confirmed rather than merely argued: the same three tag
families, checked hourly instead of every step, cost **1.32×** where A1's
every-step check costs 6.09×. Most of A1's factor is the check, not the tags.
Still one configuration, one column and one node, so it bounds the tag cost
rather than fixing it. *C0, jobs `27361326` and `27368587`.*

**T5. Short runs flatter nothing but they do skew per-step figures.** The two
untagged columns read 1.522 ms and 986 µs per timestep on the same 30-level
column at the same `dt`, one over 360 steps and the other over 8640, so fixed
overhead weighs differently. It is not a controlled pair: `c0_column_notags`
also sets `rad: DYCOMS` where `a1_dt10_notags` runs no radiation. That cuts the
right way — the run carrying the extra physics is still the faster per step —
but the gap is not step count alone. Each pair in T2 and T4 is internally
controlled, which is why the ratios are read within a pair and never across.

**T6. The reference shift costs nothing.** C1's `solve! walltime` is 349.0 s
against 345.6 s for its unshifted baseline, 1.0% apart, with `sypd` 0.678
against 0.685. The two ran at the same time on the same node. *C1, jobs
`13383684` and `13383685` on terrabyte.*

## 5. Method

**M1. Volume fractions and mass fractions can differ by six orders of
magnitude.** On A5, `nonpositive_fraction` is 0.351 while
`nonpositive_mass_fraction` is 2.77e-7 — a factor of 1.3 million. For water,
"a third of the domain is non-positive" is about vanishingly dry cells: they
take up the volume and hold none of the water. For energy it should go the
other way, since E5 puts the region in the troposphere where the mass is, and
**it does**: `c0_sphere_audit` measures 0.7839 against a volume fraction of
0.43276, a ratio of 1.811 (E9b). So the same diagnostic understates the water
barrier by six orders of magnitude and overstates nothing for energy — it
understates that one too, by 1.8×. A volume fraction is not a proxy for how much
of a field is affected, in either direction.

`nonpositive_fraction` is a **volume** fraction and not a fraction of cells.
`tagged_tracers.jl:456-459` fills a field with ones over the non-positive region
and reduces it with `sum`, which on a `Field` is the volume-weighted integral;
the docstring at `:421` says so. On `c0_column` the distinction is invisible,
because 30 uniform 50 m levels make volume and count the same number, which is
how "29 of 30 levels" reads correctly there. On a sphere it is not: 0.43276 is
the r²-weighted volume of the levels below 13.02 km, and the count fraction of
the same levels would be 7/10.

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

**M5. The most negative tag hides the source tags.** A region tag is a masked
share of `ρe_tot` and carries its sign. On `c0_sphere` the most negative tag is
therefore the region tag `extratropics`, at −100,416 J kg⁻¹, which is the
parent's own minimum at t = 0. The source tag `sfc`, which E2 is about, reaches
−209.19 at 24 h and appeared in no summary. `phase_c.jl` reported and warned on
the minimum over all tags and called it a source tag. It now reports the most
negative source-labelled tag in a column of its own. It warns on a source tag
that goes negative, and on a region tag only if it goes negative while the
parent stays positive. *C0, recomputed from `source_tag_extrema.csv`.*

**M6. Levante and terrabyte agree to rounding, not bit for bit.** The terrabyte
re-run of `c0_sphere_audit` differs from the Levante reading in the last digits
from t = 0 on, and by at most 1.5e-14 in `gross_residual` over the day.
`nonpositive_mass_fraction` at 24 h agrees to every digit. So for this
configuration a run from either machine can be set beside one from the other,
but a bit-for-bit comparison needs both runs on one machine. On one machine the
runs are deterministic. Each half of the twin test reproduces its standalone
run, C1 or the terrabyte baseline, in all 25 rows of the closure and audit
tables, although it drops the diagnostics. *`c0_sphere_audit`, Levante and
terrabyte, and the twin test.*

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
  - **R9's `c(q) = q_d·cp_d + q_v·cp_v + q_l·cp_l + q_i·cp_i`.** That is the
    coefficient for moving `T_0` alone. C1 moves `LH_v0` and `LH_s0` with it,
    and then every water phase moves by `cp_l·|δ|`. At `q_tot` = 0.02 the
    coefficient is 1068.0, not 1021.6, and the spread is 6.3%, not 1.7%. The
    error was on the safe side for positivity, because the moist cells get more
    shift, not less.
  - **`T_0`, `T_triple` and `T_freeze` "all 273.16".** `T_freeze` is 273.15.
    Only `T_0` and `T_triple` share 273.16.
  - **The acceptance test in the C1 TOML's header.** It could not have run. It
    imported Thermodynamics, which `.buildkite` does not list as a direct
    dependency. Past that, it built the parameters from the defaults and never
    read the file, so it could not tell a shift that bound from one that did not
    (R8).
  - **"A source tag went negative", naming `extratropics`.** That was
    `phase_c.jl` calling a region tag a source tag (M5).
  - **"The shift grows `∫|ρe_tot|` about 2.2×".** C1 measures 2.84× at t = 0
    and 2.85× at 24 h (E15), so `gross_relative` flatters the shifted run more
    than R11 said.
  - **E2's negative source tag as a product of the inert donor rule, and C1's
    expectation that a positive parent would keep the tags non-negative.** E2
    files the −209 J kg⁻¹ under "production therefore accumulates without
    loss". With the loss running everywhere, the tag reaches −219.9 and the
    region tags go negative too (E14).
  - **The one-iteration implicit solve as the cause of E16.** Converging it
    left the one-step difference in `ρ` at 3.6e-5, against 3.8e-5 (E16).
  - **R9's "the largest `c(q)` sits in the warm moist low levels, which are the
    most negative".** At t = 0 the parent's minimum is −100,416 J kg⁻¹ in the
    extratropics and −23,686 in the tropics. The most negative cells are cold
    and dry.
  - **That the only alternative to shifting the model's reference was shifting
    the share's denominator.** R10 rejects that shape correctly, but rebasing
    the tags as well repairs it and leaves the model untouched (§8, item 1).

## 7. What is not established

  - ~~The energy family's mass-weighted non-positive fraction (M1).~~ Settled:
    0.7839 on `c0_sphere_audit` (E9b).
  - ~~Whether `p_sat` is in fact invariant under R6's map.~~ Settled in
    Thermodynamics: over liquid, over ice and over the mixture ramp it is
    unchanged to 9.2e-16 from 150 K to 330 K (R8). Whether the *model* is
    invariant is the next item.
  - **Whether the energy limiter is all of E16.** A twin with
    `energy_q_tot_upwinding: none` in both halves switches the hook off. If the
    differences then fall to rounding, the limiter is the whole cause. If they
    do not, the next suspect is the surface-flux code path, which the acceptance
    script checks only as a formula.
  - **Why a tag goes negative under a positive parent (E14).** The finite-step
    donor loss and unlimited explicit transport are both candidates.
  - **What makes the residual's first-hour jump (E13).** The enthalpy-against-
    tracer transport reading fits, but no run has isolated it.
  - `Float32` on a sphere (W4).
  - ~~Whether 1M changes the residual (W5).~~ Settled on a column: 7% down
    (W5b). A sphere, which reaches the horizontal branches, is still open.
  - The tag cost on anything but one column on one node (T4 bounds it at 1.32×
    there).
  - Whether C1's suppression cost (R11) matters in practice. Measurable now
    rather than open in principle.

## 8. Next

 1. **Shift the reference inside the tag code, not the model.** The tags would
    partition a shadow total `E = ρe_tot + c·ρ`, with `c` a fixed energy per
    kilogram of air, 110.5 kJ kg⁻¹ to match C1. The model never sees `E`, so
    the atmosphere stays bit for bit the unshifted one and E16 cannot arise.
    The donor share is as well defined as in C1. Per-process closure still
    holds exactly once each process's increment includes `c` times its change
    in mass. Of the processes that change `ρ` here, the surface flux is
    bracketed and supplies that change. Precipitation and hyperdiffusion are
    outside the brackets in C0 and C1 too, so no new gap opens. A constant per
    kilogram also passes the tags' own van Leer transport unchanged, which a
    humidity-dependent offset would not. The minimum of `E` would be about
    10.1 kJ kg⁻¹ against C1's 10.7, and the tags would start within a few
    percent of C1's, so E11 to E15 should carry over to a few percent; those
    two are arguments. It needs a code change in `energy_source_tags.jl` and in
    the closure and diagnostic code that read the parent, a kernel test first,
    and the owner's approval. Then one run at `c` = 110.5 kJ kg⁻¹ for comparison
    with C1, and one at a larger `c` on the identical atmosphere, which would
    measure R11's suppression cost cleanly. It came out of the discussion with
    the reviewer agent, which found this route independently.
 2. **Or first confirm E16's cause.** One twin with
    `energy_q_tot_upwinding: none` in both halves, about 20 minutes on
    `hpda2_test`. It matters less if item 1 is taken, because item 1 leaves the
    model alone.
 3. **Decide what C1 says about the family.** C1 answers its question. With a
    positive reference the donor rule runs everywhere, and the residual stops
    being directional and falls to 0.70 of the unshifted one (E11, E12). It does
    not keep the tags non-negative (E14), and it cannot make the reading
    meaningful (E10). Whether that is enough to keep the source tags, or the
    process record of C3 (E9) becomes the recommendation, is the owner's call.
 4. **Phase B.** No technical objection left after W9 — B1 configures no limiter
    and the energy family has no rescale. C1 solved a simulated day in 5.8
    minutes on this grid, so ten days is about an hour of solve if B1 runs at
    that speed, which fits `hpda2_test`'s two-hour limit. Whether it is worth
    running is the owner's call.
 5. **C2.** Unchanged: needs a code change and approval.
