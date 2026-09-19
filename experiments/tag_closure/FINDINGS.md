# Findings register

Everything the tag-closure series has established, in one place, for later
reference. One line of claim, the number that supports it, and the run it came
from. The reasoning is in [LEARNINGS.md](LEARNINGS.md), one entry per run; the
C1 argument is in [C1_reference_shift.md](C1_reference_shift.md); what to run
next is in [LEVANTE_TASKS.md](LEVANTE_TASKS.md).

State as of 2026-09-10 on `claude/tag-closure-experiments`. 22 of the 30
configured runs are live in `output/`. The latest are C1 and C4, which ran on
LRZ terrabyte. Phase A and phase C are complete except for C2, which needs a
code change and approval. `c0_sphere_audit` has a second reading, from terrabyte, in
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
established on a sphere. *A4.* The sphere followed later, for a day on C7's
configuration (E45).

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
tag-side shift of §8, and a third twin then isolated the limiter.

**The limiter is most of it, not all.** With `energy_q_tot_upwinding: none` in
both halves, which leaves the hook unwired, the one-step differences fall to
3.7e-8 in `ρ`, 5.7e-10 in `ρq_tot`, 1.8e-7 in `uₕ` and 4.7e-5 in `u₃`. That is
a thousandth or less of what they were, except `u₃` at a ninth. They are still
above rounding, and `ρ`'s grows to 5.8e-6 by 5 h. So a second, smaller term
depends on the reference too. Central vertical advection, which the model does
not normally run, may also amplify what is left. *Twin tests, SLURM jobs
`13383683`, `13384080` and `13384884` on terrabyte, `output/twin_c1/`,
`output/twin_c1_newton/` and `output/twin_c1_limiter_off/`.*

**And the rest is not the surface-flux code path.** That was the next suspect,
because `c1_acceptance.jl` checks the surface flux only as a formula. A fourth
twin kept the limiter off and added `disable_surface_flux_tendency: true` to
both halves, over six hours. After one step the twins differ by 3.71e-8 in
`ρ`, 1.75e-7 in `uₕ` and 4.67e-5 in `u₃`, the same to three digits as with the
surface flux on, and by 4.4e-10 in `ρq_tot` against 5.7e-10. So the surface
flux does not start the remainder. Without it the difference also grows more
slowly: `ρ`'s reaches 8.6e-7 at 6 h, and the jump the third twin shows at 5 h,
to 5.8e-6 in `ρ` and 4.8e-3 in `u₃`, does not appear. Whether that is the
surface flux amplifying the remainder, or only a different atmosphere, this pair
cannot separate. What starts the remainder is not established. Saturation
adjustment and hyperdiffusion were argued out above, not tested. The owner did
not take up a fifth twin, because the offset of E17 leaves the model alone.
*SLURM job `13385303` on terrabyte, `output/twin_c1_limiter_off_no_sfc/`.*

**E17. An offset in the tags' total leaves the atmosphere untouched.**
`energy_source_tag_offset` gives the tags the total `ρe_tot + c·ρ`, which the
model never uses (§8, item 1). The two C4 runs differ only in `c`, 110,495 and
220,990 J kg⁻¹, and their `ta` is identical in every value: 25 hourly samples of
72 × 36 × 10 points, largest difference 0.0. On a DYCOMS column the model state
after twelve steps is bit for bit the same with and without an offset.
`nonpositive_fraction` is 0.0 at every sample in both runs, as in C1. *C4, jobs
`13384913` and `13384914` on terrabyte; `analysis/same_atmosphere.jl` and
`analysis/offset_smoke.jl`.*

**E18. C1's tag results belong to the tag rule, not to its changed
atmosphere.** C4 at C1's size reproduces them. Its absolute `gross_residual`
stays within 0.7% of C1's all day, and at 24 h it is 0.70 of the baseline's,
as C1's is. The audit is balanced, 1.001 at 3 h and 1.013 at 24 h, against
C1's 1.002 and 1.033. The region tags reach the same minima to four digits,
−11,575 and −9,631 J kg⁻¹ against C1's −11,575 and −9,632, with the parent
positive. The source tag `sfc` reaches −212.5 against C1's −219.9, and its
maximum is 3% below C1's. The tags start a few percent apart, because C1's shift
adds `(cp_l − cp_d)·|δ|·q_tot` and a constant per kilogram does not. So E11 to
E14 hold without E16. *C4, against C1 and the terrabyte baseline.*

**E19. Doubling the offset barely moves the source tag, and makes the region
tags more negative.** On the identical atmosphere, `c` = 220,990 J kg⁻¹ against
110,495 moves the absolute residual by 0.9%, `sfc`'s maximum by 1.1% (19,706
against 19,486) and its minimum by 0.8%, and the audit balance from 1.013 to
1.009. `gross_relative` halves, but that is the scale growing a further 2.2×.
The region tags' minima grow 1.51× in both regions, to −17,505 and −14,563.
That fits transport undershoots that scale with the energy a region tag
carries, which includes its masked share of `c·ρ`, but it is an argument, not
a measurement. So R11's suppression is real in the algebra and small in the
tags over a day here, while the offset's size shows up in the region tags'
negativity. *C4 at both offsets.*

**E20. Checked per process, the tags found a process nobody had listed.** C5
splits the new energy two ways at every point: by region, in `new_<region>`
tags that follow every process (`source: all`) inside their region, and by
process, in `rad` and `sfc`. Both sides obey one rule, so they should agree.

  - On the sphere they agree to 20.2 J kg⁻¹ at 24 h, 9.6e-4 of the new energy's
    largest value. The gap grows steadily from 0.04 J kg⁻¹ at 1 h.
  - On the column they differ by 17,954 J kg⁻¹ at 675 m at 24 h. There the
    region split holds 17,954 J kg⁻¹ and the process split 0.004.

The DYCOMS setup runs large-scale subsidence (`LargeScaleSubsidence` in the
run's `scm_setup`). It is bracketed as `subsidence`, and neither process tag
lists it. So the check found a process that fires without a tag, which is what
it was built for. It also means the column tags of C0, C3 and C5 carried
subsidence's energy all along, inside the region tags.

The sphere's gap cannot come from a rule that is linear in the tags. Two
nonlinear steps are candidates: the tracers' default vertical upwinding,
`vanleer_limiter`, which acts on each tag on its own, and the clamp on the share
where a tag is negative. The `new_` tags reach −158 and −88 J kg⁻¹. This run does
not separate the two. *C5, jobs `13385401` and `13385402` on terrabyte;
`analysis/c5_process_closure.jl`.*

**E21. On the column, a region's initial energy only falls.** `strat − new_strat` is the energy that was above 750 m at the start, followed as it
moves, and `tropo − new_tropo` the same below. Their column integrals fall at
every hourly sample, from 5.268e7 to 5.008e7 J m⁻² and from 6.030e7 to 5.224e7
J m⁻². Neither is negative anywhere: their smallest values are +0.028 and +0.032
J kg⁻¹. On the sphere the same differences reach −9,617 and −11,638 J kg⁻¹, where
the region tags themselves are negative (E14, E19). The sphere's lat-lon output
gives no domain integral to test the fall with. *C5.*

**E22. The radiation tag holds nothing where radiation cools, with the loss
running.** At 675 m, where the radiation record is most negative at 24 h,
−20,566 J kg⁻¹ as in C3, the `rad` tag holds 0.0044 J kg⁻¹ of a total of 61,718
J kg⁻¹, a share of 7.1e-8. The loss runs there, since the total is positive
everywhere. But it takes each loss from every tag by share, and radiation added
almost nothing at that level, so its tag has almost nothing to lose. Elsewhere
in the column the tag reaches 6,100 J kg⁻¹, where radiation warms. So E8 is not
an artefact of the inert loss: a source tag cannot show where its process
removed energy. *C5, `cloud_top.csv`.*

**E23. The column's records leave 1.37 MJ m⁻² of its energy change unexplained
over a day.** Summed over the column at 24 h, radiation's record is −6.62 MJ m⁻²
and the surface flux's +9.42 MJ m⁻². The latter is 109 W m⁻² for a day, DYCOMS
RF02's prescribed 16 plus 93 W m⁻². Together the records say +2.80 MJ m⁻², while
the column integral of `ρe_tot` rose 1.43 MJ m⁻². The difference, −1.37 MJ m⁻², is
what no record saw:

  - subsidence (E20);
  - the 0-moment rain-out on the implicit path, which no record reached at this
    commit;
  - whatever the numerics do not conserve.

This run does not split them. The integrals are sums of `rhoa · value · Δz`,
which match the closure table's native integral to 1.3e-16 at t = 0. *C5.*

**E24. C5's radiation tag outgrows C3's after four hours, which the loss cannot
do on the same atmosphere.** For four hours C5's column maximum sits just below
C3's, 1,865 against 1,873 J kg⁻¹ at 4 h, as a running loss makes it. Then it grows
faster, to 5,990 against 4,272 at 22 h. The atmospheres agree: the radiation
record's extremes at 24 h match C3's to the five digits E8 quotes. The loss only
removes, and both runs move tags with the van Leer limiter, the tracers' default
since `da85255e`, which C3's commit contains. C3 ran on Levante at a commit with
uncommitted changes, so a difference in how that code moved or attributed the
tag is possible. Not established. *C5 against C3.*

**E25. On the column, after its first ten minutes, pressure work is the whole
of the residual's growth.** `analysis/transport_ledger.jl` steps
`c6_column_no_repair` with the repair off. From step 60 on, it splits the rate
at which the residual grows into four parts at each step's start. Over the
next 50 minutes the residual moved by 72,000 J m⁻², as a gross column integral,
and the parts account for it:

| part                                                  | gross, J m⁻² |
|:----------------------------------------------------- | ------------:|
| pressure work: the parent moves `h_tot`, the tags `e` |       72,260 |
| transport of the residual already there               |          421 |
| the per-tag van Leer limiter                          |          268 |
| everything else, the brackets included                |          381 |

The parts sum to 72,250 J m⁻². The regression slope of the actual change on
their sum is 1.000, and on pressure work alone 0.9999. The last part's signed
integral, 204 J m⁻², matches the residual's, 202. What an estimate at each
step's start cannot see is 978 J m⁻², 1.4%. So on this column the residual
grows because the parent moves enthalpy while the tags move energy. The
per-tag limiter adds under half a percent.

The bounds: one column, 50 minutes, no horizontal transport, and the first ten
minutes left out. In the first minute the residual jumps by about 143,000 J m⁻²,
and a first version of the script, which started at step one, could not
reproduce that (§6). *Terrabyte login node, model code of `f3bbdb7b`;
`output/transport_ledger_column/`.*

**E26. With its subsidence listed, the column closes per process and per
record.** C6 is C5's layout on the code that brackets the implicit rain-out and
repairs negative tags, with a `sub` tag and records for all four processes that
change the column's energy.

  - **Form A.** The new energy split by region and split by process agree to
    60.7 J kg⁻¹ at 24 h, 3.8e-4 of the new energy, against C5's 17,954. So the
    gap of E20 was subsidence.
  - **Form B.** The four records explain the change in the column's `ρe_tot`
    to 3.3e-7 J m⁻² out of 1.43 MJ m⁻². C5's unexplained −1,365,477 J m⁻² (E23)
    is subsidence's −1,277,826 and the rain-out's −87,651, to the joule. Nothing
    else changes the column's energy, the dynamical core included.
  - **The initial energy** of each region still falls at every sample and is
    never negative (E21).
  - **The repair has almost nothing to do** on the column. Its largest ledger
    is 3.5e-9 J kg⁻¹, and form A is the same with it on and off. The
    atmosphere is too: `ta` is identical in every value.

*C6, jobs `13385450` and `13385451` on terrabyte at `f3bbdb7b`;
`analysis/c5_process_closure.jl`.*

**E27. With the repair on, no tag goes negative on the sphere, and the region
tags trade a lot of energy to get there.** On C5's gray sphere every tag's
minimum over the day is zero or above. With the repair off the region tags
reach −9,628 and −11,664 J kg⁻¹, and `sfc` −208 J kg⁻¹, as in C5.

  - The two region tags' cumulative ledgers reach ±30,920 J kg⁻¹ at their worst
    points, against maxima of about 220 kJ kg⁻¹. Each ledger holds everything
    the repair moved at that point over the day. Where they peak is not reduced
    here.
  - The tags that carry a source were lifted by up to 707 J kg⁻¹ (`sfc`), 473
    and 249 (`new_extratropics`, `new_tropics`) and 79 (`rad`).
  - The atmosphere is untouched: `ta` is identical in every value with the
    repair on and off.

*C6, jobs `13385452` and `13385453`.*

**E28. On the sphere, the per-process check found the rain-out producing
energy.** The new energy split by region exceeds the split by process by up to
149 J kg⁻¹ at 24 h, 7e-3, at the lowest level of the southernmost row. The gap is
the same to 0.01 J kg⁻¹ with the repair on or off and with first-order tag
upwinding, so neither the repair nor the per-tag limiter makes it.

At that point the microphysics record is +270.6 J kg⁻¹: the implicit rain-out
raised `ρe_tot` there. Condensate colder than the reference carries negative
energy, and ice carries less than −333.6 kJ kg⁻¹, its fusion heat. So removing
it raises the total, and `E` with it, net of `c` times the mass removed. The
bracket counts that as production, the `new_` tags (`source: all`) take it, and
no process tag lists `microphysics`. So the check found a second process
nobody had listed. A run with a `microphysics` tag should close it.

The size fits if what fell out was ice at about −3.7e5 J kg⁻¹. Then +270.6 J kg⁻¹
of `ρe_tot` is about 7e-4 kg kg⁻¹ of ice, which lowers `E` by `c` times that,
80 J kg⁻¹, leaving about 190 J kg⁻¹ of production against the 149 J kg⁻¹ gap. That
arithmetic is an estimate, and the phase at that point is not read from the
run. *C6, jobs `13385452` to `13385454`. `analysis/c5_process_closure.jl`
prints each record at the worst point.*

**E29. The region tags' negativity does not come from their vertical
upwinding.** With first-order upwinding, which is monotone for a single field,
the region tags still reach −9,566 and −11,588 J kg⁻¹, against −9,628 and
−11,664 with van Leer. That leaves E14's other routes: the tags' horizontal
transport and hyperdiffusion, neither limited for tags, and the finite-step
loss. E19's scaling with the offset points at transport. *C6, jobs `13385453`
and `13385454`.*

**E30. With a `microphysics` tag, the sphere closes per process.** C7 is
`c6_sphere_no_repair` with one more tag, `mp`, on `source: microphysics`. The
new energy split by region and split by process now agree to 20.2 J kg⁻¹ at
24 h, 9.5e-4 in relative terms, against C6's 149 J kg⁻¹ and 7e-3 (E28). So the
gap of E28 was the rain-out's production, and the check closes once every
process that fires has a tag.

  - The largest gap left is at grid index (63, 33, 2), on the second level,
    where the new energy is 2,648 J kg⁻¹. The radiation record there is
    2,090 J kg⁻¹, and the other two records are zero to rounding. The records
    stay where their process acted, while the tags are transported, so the tags
    there can still hold energy made elsewhere.
  - The gap grows close to the square of time, from 0.04 J kg⁻¹ at 1 h to 5.27
    at 12 h and 20.2 at 24 h. What it is, is open (§7).
  - The `mp` tag reaches 149 J kg⁻¹, and the microphysics record 270.7, as in
    C6.
  - The extra tag changes nothing else. The region tags' closure table is
    identical to C6's in every row, and `ta` in every value.

*C7, job `13399601` on terrabyte at `414f5f1b`; `analysis/c5_process_closure.jl`
and `analysis/same_atmosphere.jl`.*

**E31. On the sphere too, pressure work is nearly all of the residual's
growth.** `analysis/transport_ledger.jl` stepped `c6_sphere_no_repair` for six
hours at its 400 s step, with the repair off. From the end of the first hour on,
it split the rate at which the residual grows. Over the next five hours the
residual moved by 4.86e20 J, as a gross integral over the sphere:

| part                                                |    gross, J |
|:--------------------------------------------------- | -----------:|
| pressure work, vertical                             |     6.67e20 |
| pressure work, horizontal                           |     3.28e20 |
| hyperdiffusion                                      |     1.18e19 |
| transport of the residual already there, vertical   |     5.79e18 |
| everything else, the brackets included              |     5.53e18 |
| transport of the residual already there, horizontal |     3.93e18 |
| the per-tag van Leer limiter                        |     9.47e16 |

  - The two pressure parts oppose each other in places, so each alone can
    exceed the change. The parts sum to 4.83e20 J, gross, and the regression
    slope of the actual change on their sum is 1.005.
  - Everything but pressure work adds up to at most 2.71e19 J. So pressure
    work, vertical and horizontal together, is at least 4.56e20 J, 93% of the
    change. The per-tag limiter is 2e-4 of it, and hyperdiffusion 2.4%.
  - The last part's signed integral, −5.53e18 J, matches the residual's,
    −5.57e18. Transport cancels over the sphere, so that part is what changes
    the residual's integral.
  - What an estimate at each step's start cannot see is 2.59e19 J, 5.3%,
    against 1.4% on the column (E25).
  - Measuring did not change the run: its closure residuals match C6's to
    every printed digit.

So the sphere's residual grows as the column's does: the parent moves enthalpy
while the tags move energy. It does so horizontally as well as vertically, and
an audit that changed only vertical transport would miss the horizontal part.

The bounds: one configuration, five hours, and the first hour left out. *Job
`13399604` on terrabyte, script and model code of `6af01228`;
`output/transport_ledger_sphere/`.*

**E32. Moved with the falling water, the tags follow sedimentation out of the
column.** `analysis/sedimentation_smoke.jl` runs `c6_column_repair` under
1-moment microphysics for an hour, with the cloud falling at its diagnostic
speed. It runs once as built, and once with the tags' sedimentation switched
off, as before it existed. The model's state is identical in every field in the
two runs.

  - By the `precipitation` record, sedimentation changed the column's `ρe_tot`
    by −1,327 J m⁻² net and 3,772 J m⁻² gross.
  - Without the transport, the column's signed residual grows at every check
    and reaches −3,029 J m⁻² at 1 h. The tags keep energy that sedimentation
    took out at the ground. With it, the residual is +196 J m⁻² at 1 h, 15
    times smaller, and it does not grow steadily: +193, +325, +386, +385, +321
    and +196 at the ten-minute checks.
  - The two runs' residuals differ by −3,225 J m⁻² signed and 11,717 gross.
    That is the part of sedimentation the tags now follow. The gross is 3.1
    times the record's. That fits the tags' total also carrying `c` times the
    mass that moved: by an estimate not read from the run, liquid near 284 K
    carries about 52 kJ kg⁻¹ with its geopotential, against `c` = 110.5.
  - The gross residual barely changes, 177,377 against 179,609 J m⁻². Pressure
    work dominates it, as on the 0-moment column (E25).
  - Every tag stays non-negative in both runs, with the repair on.

The bounds: one warm column for one hour, liquid only. Ice, where the energy
flux points up while the water falls, is not reached. The integration test
covers that direction on a set flux. What the +196 J m⁻² left is, is not
separated, and the tags' missing Jacobian block is one candidate. *Terrabyte
login node, model code of `91b9bbb9`; `output/sedimentation_smoke/`.*

**E33. On a 1M column for a day, with sedimentation moving the tags, both
per-process checks hold, less tightly than on the 0M column.** C8 is C6's column
with the repair on, under 1-moment microphysics, with an `mp` tag and a
`precipitation` record, so that both forms see sedimentation.

  - **Form B.** The five records explain the change in the column's `ρe_tot` to
    −5.3 J m⁻² out of 897,043, 6e-6. The rain took 158,979 J m⁻² out of the
    column, by the `precipitation` record. C6's 0-moment column closed to the
    joule (E26). What the 5.3 J m⁻² is, is not separated.
  - **Form A.** The new energy split by region and split by process agree to
    117 J kg⁻¹ at 24 h, 7.1e-4 in relative terms, at 75 m, where the
    `precipitation` record is −613 J kg⁻¹. C6's column left 60.7 J kg⁻¹ and
    3.8e-4 (E26). The gap grows slowly for ten hours, to 1.75 J kg⁻¹, and faster
    after. It is not separated either.
  - Each region's initial energy still only falls, and the repair's largest
    ledger is 5e-7 J kg⁻¹.
  - The first hour reproduces E32's run with the tags moved, to every printed
    digit of the closure table, although C8 ran on the code with the review
    fixes of #65 and #68 merged in.
  - The closure residual's gross at 24 h is 2.46e6 J m⁻², against 2.44e6 on
    C6's 0-moment column. Pressure work dominates both (E25).
  - Where radiation cools most, at 725 m, the radiation tag holds 9e-8 J kg⁻¹
    against a record of −43,033 J kg⁻¹, as in E22.

*C8, job `13401744` on terrabyte at `c11d1d3b`; `analysis/c5_process_closure.jl`,
`output/c8_column_1m/`.*

**E34. Moved as enthalpy, the tags follow their total: the closure residual
stops growing, and on the column form A closes to 7e-6 J kg⁻¹.** C9 runs the
audit switch, `energy_source_tag_transport: enthalpy`, on C6's column and C7's
sphere, both with the repair off. Each is its reference with only the transport
changed, and `ta` is identical to the reference in every value, in both.

| closure residual                        | tracer, the reference | enthalpy, C9 |
|:--------------------------------------- | ---------------------:| ------------:|
| column, gross at 1 h, J m⁻²             |               166,016 |        2,695 |
| column, gross at 24 h, J m⁻²            |             2,442,276 |        2,284 |
| column, signed at 24 h, J m⁻²           |              −187,999 |         +199 |
| sphere, gross at 1 h, J                 |               1.30e21 |      2.54e20 |
| sphere, gross at 24 h, J                |               2.82e21 |      2.54e20 |
| sphere, signed at 24 h, J               |              −2.82e19 |     −1.16e17 |

  - After the first hour the residual does not grow in either geometry. At
    24 h it is 1,069 times smaller on the column and 11 times smaller on the
    sphere. On the column it even shrinks, from 2,695 to 2,284 J m⁻². Transport
    no longer moves it, and the loss rule makes a residual decay where energy
    is lost, which would do that. What makes the first hour's residual is not
    separated. The initial adjustment of E13 and E25 is the candidate.
  - On the column, form A closes to 6.6e-6 J kg⁻¹, 1e-9, against 60.7 J kg⁻¹
    under tracer transport (E26). So E26's gap was the tags' per-tag transport,
    not the clamp. Form B is unchanged, to 3.3e-7 J m⁻².
  - On the sphere, form A gets worse: 76.8 J kg⁻¹ at 24 h, 4e-3, against C7's
    20.2 (E30). The worst point is at the lowest level, where the new energy is
    124 J kg⁻¹. With the repair off, the tags that carry a source go negative,
    and at that point `sfc` holds −397 J kg⁻¹, its minimum over the run. A
    negative tag's share is clamped to zero, so the overlays' fluxes no longer
    add up. At 24 h, 29% of the gap's absolute sum sits at the 5.4% of points
    where the source tags' negative parts add up to below −1 J kg⁻¹. On C7's
    sphere, under tracer transport, it is 2.5% at 15.8% of the points. The
    points are those of the remapped grid, not weighted by mass. So the clamp is
    a cause under the audit, and not what makes C7's gap. The rest of the gap
    may have been made where tags were negative and moved since. A run with the
    repair on would test that. *`analysis/c5_process_closure.jl` prints both
    shares, and each tag at the worst point.*
  - The audit costs about 5% per step: 2.54 ms against 2.43 on the column, and
    2.19 s against 2.07 on the sphere.
  - At the column's most-cooled level the radiation tag holds 5.8 J kg⁻¹, a
    share of 9e-5, against 0.004 J kg⁻¹ under tracer transport (E22). The
    first-order shares smear, as the design says they would.

The bounds: one column and one sphere configuration, a day each, with the repair
off. *C9, jobs `13402392` and `13402393` on terrabyte at `0bfb5037`;
`analysis/c5_process_closure.jl` and `analysis/same_atmosphere.jl`;
`output/c9_column_enthalpy/` and `output/c9_sphere_enthalpy/`.*

**E35. With the repair on, the audit's sphere keeps its residual, and its form
A gets worse, not better.** C10 is C9's sphere with the repair on and its
ledgers in the output. `ta` is identical to C9's in every value. The closure
residual is C9's to four digits, 2.5357e20 J against 2.5359e20 at 24 h, because
the repair keeps the partition's sum. No source tag is left below
−2e-26 J kg⁻¹.

  - Form A gets worse: 274 J kg⁻¹ at 24 h, 1.5e-2, against C9's 76.8 and C7's
    20.2 (E30, E34). At the worst point the process tags hold 447 J kg⁻¹
    against the new energy's 173.
  - The repair lifts negative source tags by adding energy that the other side
    of form A does not receive. It lifted `sfc` by up to 397 J kg⁻¹, on the
    process side, and the `new_` tags by up to 121 and 56, on the region side.
    C10's worst point is the node where C9's `sfc` sinks furthest. The
    repair's ledger there, 397.04 J kg⁻¹, is what C9's `sfc` reaches there,
    −397.06 (E36).
  - So E34's prediction fails: the repair does not bring form A back to C7's
    20 J kg⁻¹. C10 cannot say how much of C9's gap the clamp makes, because
    the repair creates energy at the same nodes. C9 is itself the no-repair
    counterfactual.
  - The region tags trade up to ±16,294 J kg⁻¹ through the repair, against
    ±30,920 under tracer transport (E27).
  - The repair costs nothing measurable here: 2.20 s per step against C9's
    2.19.

*Corrected on 2026-09-11.* This finding first quoted 54.9 J kg⁻¹ as form A
"with the repair's ledgers taken back out", and concluded from it that the clamp
is at most part of C9's gap. The ledgers are not transported, while a repaired
value moves and feeds the shares after it, so subtracting them does not give
form A without the repair. Against C9, the same atmosphere without the repair,
that field is off by up to 22.0 J kg⁻¹ at 24 h. Under tracer transport, C6 with
and without the repair, it is off by 219 (§6).

*C10, job `13403083` on terrabyte at `7dc0a302`; `analysis/c5_process_closure.jl`
and `analysis/same_atmosphere.jl`; `output/c10_sphere_enthalpy_repair/`. The
correction: `analysis/formA_mechanism.jl`.*

**E36. Under the audit, a negative source tag freezes at its node and sinks
faster: the clamp in the audit's transport.** Under the audit a tag moves by
its share, and an overlay's share is clamped at zero. So a negative overlay
neither moves nor loses, while the central operators keep adding a tendency
from its neighbours' shares.

  - **The node stays put.** C9's `sfc` minimum sits at one node from 12 h on:
    43.7°N, 164.8°W, 250 m. It falls ever faster there: −112, −172, −236, −310
    and −397 J kg⁻¹ at 12, 15, 18, 21 and 24 h. C7's minimum moves among four
    nodes and levels off, at −208.
  - **Only transport can change it.** The node is under surface cooling all
    day, with a surface-flux record of −1,375 J kg⁻¹ at 24 h, so nothing is
    produced into `sfc` there. It sits on the southern edge of `sfc`'s source
    band. At 12 h C9's row of `sfc` through it is spiky (303, 261, 76, −112,
    187, 391 J kg⁻¹), where C7's is smooth (715 down to 441).
  - **C10's repair confirms it:** it lifts that same node by 397.04 J kg⁻¹.
  - **The gap sits at and beside negative nodes.** At 24 h, within one grid
    point of the points where the source tags' negative parts add up to below
    −1 J kg⁻¹, lies 78% of the gap's absolute sum, on 39% of the points. On C7
    it is 11% on 51%.
  - **The gap is horizontal.** It cancels along each level: per level, the
    absolute of its integral over its gross is 0.00 to 0.37, and 0.60 near
    5 km. It does not cancel within columns, 0.88 over the sphere.
  - **Only the extreme is deeper.** Overall the audit makes the overlays less
    negative. At 24 h `sfc`'s cos-latitude-weighted negative parts add up to
    −4.9e3 against C7's −3.4e4, on 242 points below −1 J kg⁻¹ against 758.

That the clamp is the only cause is inferred, from the code. The audit's
kernels are linear in the shares apart from it, and the loss clamp is the one
other non-linear step. A C9 twin with signed shares for the overlays in the
audit's kernels would decide it. *`analysis/formA_mechanism.jl`,
`formA_followup.jl` and `formA_last.jl`, on the outputs of C7, C9 and C10;
`output/formA_mechanism/`.*

**E37. C7's form-A gap under tracer transport is the per-tag van Leer limiter,
with a small part from the loss clamp.** Under tracer transport each tag
evolves on its own. C6's and C7's shared tags are identical, and C6's gap equals
C7's plus `mp` to 1.8e-12. So C6's first-order run, less `mp`, is C7 with a
linear scheme.

  - At C7's worst point the first-order equivalent is −0.044 J kg⁻¹, against
    20.2.
  - Over the sphere, first order removes 99.8% of the gap's absolute sum at
    6 h and 97% at 24 h.
  - **Where it sits.** In the worst column the gap is +20.2 J kg⁻¹ at 869 m and
    −15.2 at 1,778 m. `sfc` falls from 17,404 to 463 to 0 J kg⁻¹ over the
    lowest three levels, which is where van Leer limits. The gap cancels
    within columns: over the sphere the columns' absolute integrals add up to
    0.037 of its gross.
  - **How it grows.** It grows close to the square of time, since the tags
    grow in proportion to time, and so does the limiter's error per step.
  - **The rest** is the loss clamp, about 3% of the absolute sum at 24 h. It
    peaks at 4.87 J kg⁻¹ at 38.6°N, 250 m, where `sfc` is negative all day
    under strong surface cooling, with a record of −9,130 J kg⁻¹. First order
    leaves that point unchanged.

This settles E30's open point, as E34 did on the column. *The same scripts.*

**E38. Form A's global integral separates a missing process from numerical
noise. Its largest pointwise gap does not.**

| run                    | largest gap / largest new energy | ∫ gap / ∫ new energy |
|:---------------------- | --------------------------------:| --------------------:|
| C6, no `mp` tag        |                           7.0e-3 |              1.26e-3 |
| C7, tracer             |                           9.5e-4 |               5.2e-5 |
| C9, audit              |                           4.1e-3 |               4.7e-5 |
| C10, audit with repair |                           1.5e-2 |               6.0e-4 |

  - **Pointwise.** A process that no tag follows, C6's rain-out, gives 7.0e-3.
    The numerical noise gives up to 1.5e-2, and it grows as the square of
    time, while the missing process's signal levels off.
  - **Integrated.** Transport cancels over the sphere, so the limiter's and
    the transport clamp's errors do too. The missing process stands out: C6
    gives 1.26e-3, and `mp`'s own integral is 1.21e-3. C7 and C9 give 5e-5,
    and C10's 6.0e-4 is the repair's created energy, whose integral is
    5.8e-4.
  - **A check of labels is exact.** Form A's production signal is exactly the
    production of labels that no process tag lists. Checking at configuration
    that every active label has a process tag carries the same information,
    and would have caught subsidence (E20) and the rain-out (E28) before any
    run.

The integrals take a hydrostatic density with a surface pressure of 1e5 Pa, on
the remapped grid, so they are approximate, and the model's own quadrature
should confirm them. *`analysis/formA_followup.jl`.*

**E39. The audit's first-hour residual and C8's form-B remainder are the
one-iteration Newton increment.** The stepper takes one Newton iteration
(`max_newton_iters_ode: 1`). In ClimaTimeSteppers' `imex_ark.jl` a stage's
implicit contribution is `T_imp[i] = (U − temp)/dtγ`. With one iteration that is
the increment linearised about the stage's initial guess, not the tendency at
the solved state.
  - The tags and the records have no cross blocks in the Jacobian, so they take
    their bracketed increments at the initial guess.
  - `ρe_tot` also gets the Jacobian's coupling.
  - Under the audit, the tags' explicit fluxes are evaluated at the solved stage
    state.

**The audit's first-hour residual (E34), on the column.** A reviewer stepped C9's
column on the login node:

| variant                                      | gross after the first step | gross at 1 h, J m⁻² |
|:-------------------------------------------- | --------------------------:| -------------------:|
| one Newton iteration, as run                 |                      2,675 |               2,695 |
| Newton converged (10 iterations, rtol 1e-10) |                         25 |                20.5 |
| no post-Newton upwind correction             |                      2,729 |               2,757 |
| both                                         |                        7.8 |                13.1 |
| a 5 s step                                   |              2,169 at 5 s |               2,239 |

  - **When it is made.** 98% of the first hour's residual is made in the first
    10 s step, while the vertical velocity reaches 3.66 m s⁻¹ in the initial
    adjustment. Nothing is made after about 30 s.
  - **Its shape.** It sits as a dipole around the inversion.
  - **What removes it.** Converging the solve removes 99% of it. The upwind
    correction and the step length matter little.
  - **After the first hour.** The loss rule alone, fed with the hourly records,
    reproduces C9's column: a gross of 2,265 J m⁻² at 24 h against 2,284, and a
    signed +201 against +199.
  - **On the sphere,** the residual at 24 h is the 1 h field, frozen in place,
    with a correlation of 0.99999. By an approximate mass weighting, 69% of its
    gross is in the top two levels. That the same mechanism made it, near the
    lid, is an inference.

**C8's form-B remainder (E33) is the same lag, in the records.** The Jacobian
couples the `ρe_tot` and `ρ` rows to the condensates, and the records miss the
linearised change of the outflow.
  - Per step, form B tracks `dtγ` times the rate of the precipitation record,
    with a correlation of 0.9945 and a slope of 3.84 s against `dtγ` = 4.36 s.
    So it does not accumulate.
  - No 1-moment process writes `ρe_tot` or `ρ` outside the brackets.
  - The 0-moment column closes to the joule because 0M has no such coupling in
    the `ρe_tot` row.

**E32's +196 J m⁻² is the loss rule, not the tags' missing Jacobian block.** It
is the loss rule acting on the residual that tracer transport makes. On the same
atmosphere at 600 s under the audit, the block's lag is −7.8 J m⁻²: small, and
of the other sign.

**Not established when this was written:**
  - C8's form A over a day. The 1M runs covered only the first ten minutes,
    because the 1M build takes about 20 minutes on the login node. In those ten
    minutes, under the audit, form A is at most 4.3e-7 J kg⁻¹. E43 settles it.
  - The sphere's mechanism. E39b shows that the Newton increment makes 83% of
    it.

`analysis/first_hour_sphere.jl` and `analysis/c8_variants.jl` ran as Slurm jobs
(E39b, E43).

*A reviewer agent on the terrabyte login node, 2026-09-11.
`analysis/first_hour_0m.jl`, `c8_variants.jl`, `formb_vs_flux.py`,
`after_first_hour.py`, `signed_by_loss_rule.py` and `sphere_levels.py`;
`output/newton_lag/`.*

**E39b. On the sphere, the one Newton iteration makes 83% of the audit's
first-hour residual.** `analysis/first_hour_sphere.jl` steps C9's sphere for two
hours, once as run and once with a converged Newton solve (10 iterations,
relative tolerance 1e-10).

| variant                      | gross at 400 s, J | gross at 1 h, J | gross at 2 h, J |
|:---------------------------- | -----------------:| ---------------:| ---------------:|
| one Newton iteration, as run |           2.50e20 |       2.5352e20 |       2.5350e20 |
| converged                    |           4.15e19 |       4.24e19   |       4.25e19   |

  - The run reproduces C9's first hour, 2.54e20 J (E34).
  - A converged solve leaves 17% of it. On the column it left 1% (E39).
  - In both variants the first 400 s step makes nearly all of it, while `u₃` is
    largest, and it barely changes after 20 minutes.
  - The signed residual barely moves: −2.79e17 J against −2.59e17 at 1 h.
  - What the converged 17% is, is not established. E39 found 69% of the
    sphere's residual in the top two levels.

*Job `13408404` on terrabyte at `78586e39`; `output/newton_lag/first_hour_sphere_slurm/`.*

**E40. Under `prognostic_edmfx` the tags get none of the sub-grid mass flux,
and every shipped EDMF configuration fails with tags.** These are build checks
on the DYCOMS RF02 EDMF column under 1M, with the offset, on the login node.
Nothing was stepped.

  - **The shipped settings fail.** Every shipped EDMF config sets
    `edmfx_vertical_diffusion: true`. Then the sub-grid diffusive flux applies
    the grid mean's specific tendency to the updraft's copy of every
    grid-scale tracer (`edmfx_sgs_flux.jl:403-409`). No tag has a copy, so the
    call fails with `type NamedTuple has no field e_src_strat`. The water
    species before the tags pass, because the updraft carries them. By the
    code, the water tags, the `ρe_tag_*` family and the passive tracers would
    fail there too. That was not run.
  - **The sub-grid mass flux reaches no tag.** The updraft carries `ρa`, `mse`,
    `q_tot` and the four condensates, and no tag. A field with no updraft copy
    has a zero difference-form flux. On a synthetic updraft,
    `edmfx_sgs_mass_flux_tendency!` changes `E` by a summed absolute tendency
    of 11.5 W m⁻³ over the column's cells, and the partition by exactly zero.
    The `c·ρ` part alone sums to 0.60 W m⁻³. So all of it would go to
    `e_src_res`. The sizes are the synthetic state's. The zero is the result.
  - **Sedimentation under EDMF does not close.** With more rain in the updraft
    than in the grid mean between 300 and 900 m, the partition's sedimentation
    tendency misses the parent's by 3.4e-3 of its largest value. Without EDMF
    the integration test holds the same comparison to 100 eps. The miss is the
    updraft and environment corrections (`water_advection.jl:127-186`), which
    the tags do not share.
  - **A full EDMF simulation with tags did not build in 15 minutes** on the
    login node. The cache took 108 s, and the implicit problem was still
    compiling when the limit ended it. With `edmfx_vertical_diffusion: false`
    it should run, by the code. *Added on 2026-09-11:* on `hpda2_test`, with
    two cores, the D4 pair did not finish building in two hours either. Both
    jobs used a full core throughout, reached 6.7 GB, and wrote no output
    before the time limit (jobs `13404536` and `13404537`). The same column
    without tags was not built, so whether the tags make the build slow is not
    known.

The synthetic updraft covers a tenth of the area and rises. Below 800 m its
`mse` is 1.5 kJ kg⁻¹ above the grid mean's and its `q_tot` 1 g kg⁻¹ above;
above 800 m its `mse` is 0.5 kJ kg⁻¹ below. The bounds: one column, one state at
t = 0, and tendency functions called one at a time. Nothing refuses these
configurations at startup. *A design agent on the terrabyte login node,
2026-09-11. `analysis/subgrid_light_check.jl edmf` and
`analysis/subgrid_check_edmf.jl`; `output/subgrid_build_checks/`. The design is
[SUBGRID_AND_MICROPHYSICS_DESIGN.md](SUBGRID_AND_MICROPHYSICS_DESIGN.md).*

**E41. Falling ice takes sedimentation's upward branch in every cell, and the
partition stays closed through it.** These are build checks on
`PrecipitatingColumn` under 1M, 100 levels to 10 km, with the offset, on the
login node.

  - **Every ice and snow cell takes it.** At t = 0, all 79 cells holding cloud
    ice and all 69 holding snow above 1e-9 kg kg⁻¹ carry negative energy per
    kilogram, geopotential and offset included, down to −193 kJ kg⁻¹. None of
    the 55 cells of cloud liquid or the 50 of rain does. So every face under
    falling ice takes the lower cell's shares.
  - **The partition's sedimentation tendency matches the parent's** to 5.7e-15
    of its largest value, within 100 eps. On a step partition at 6.5 km,
    inside the ice, `lower` moves in the one cell above the step, and `upper`
    in no cell below it. Only the upward branch does that. Closure there is
    5.9e-15.
  - **Stepped six times at 10 s, with the repair on,** `E` stays positive in
    every cell and every tag stays non-negative. Sedimentation still closes to
    1.6e-15. The 16 cells still holding cloud ice and the 17 holding snow still
    take the branch.
  - **The ice does not last.** Most of it sublimates in that minute, since the
    profile's air is below ice saturation aloft. After the minute, nothing
    crosses the step.
  - Each species' own sedimentation adds up exactly to what `ρq_tot` is moved
    by.
  - **2M and 2MP3 do not build.** The model and the state do. The cache stops
    at the model's own gate, "2M and 2M+P3 microphysics are temporarily
    disabled" (`precomputed_quantities.jl:160-167`). The tags play no part in
    it.

This settles the branch on a real state. Following it through a run is still
open (§7). *The same agent. `analysis/subgrid_light_check.jl 1M|2M|2MP3` and
`analysis/subgrid_check_cold.jl 1M`; `output/subgrid_build_checks/`.*

**E42. Through an hour of falling ice, the column stays closed and the tags
stay non-negative. What the upward branch moved cannot be told apart from
vertical diffusion.** D1 is `PrecipitatingColumn` under 1M, 200 levels to
10 km, with the offset and the repair on, sampled every minute for an hour.

  - **The column closes.** The signed residual is 0.29 J m⁻² against a total of
    6.37e8, 4.5e-10, and it does not change after the first minute. The gross
    is 1.12e6 J m⁻² after the first minute and 2.37e6 at 1 h, 3.7e-3 of the
    total. So the residual moves energy between levels and makes none.
  - **It does not sit where the ice falls.** After the first minute, 42% of the
    gross's growth is in the ice layers, 5.5 to 9.5 km, which are 40% of the
    column's depth. Half is below 4.5 km. Vertical diffusion acts on the whole
    column: `DecayWithHeightDiffusion`, with `D₀` = 5 m² s⁻¹ and `H` = 8 km,
    still gives 2.7 m² s⁻¹ at 5 km. It moves the tags as tracers and `ρe_tot`
    in enthalpy form, and such a mismatch makes a zero-sum growth. That it is
    the cause is an inference. In the first minute the ice layers held 54% of
    the gross, and the largest level was the top one. *E42b falsifies the
    inference. Without vertical diffusion the gross residual is the same (§6).*
  - **The tags stay non-negative.** No tag goes below zero, and the repair's
    largest ledger is 1.8e-8 J kg⁻¹.
  - **The records.** `e_prc_microphysics` and the `mp` tag are exactly zero at
    every sample, as under 1M they must be. Form B closes to 0.14 J m⁻² out of
    95,023, nearly all of it the surface flux. The precipitation record is
    −0.67 J m⁻².
  - **Form A is exactly zero, and says nothing here.** The surface flux is the
    only production, and it is all in `lower`, so `sfc` and `new_lower` are the
    same field.
  - **`lower` rises above the boundary.** Its column integral above 5.6 km,
    where its mask is below 0.3%, goes from 13,969 J m⁻² to 53,245 over the
    hour. Sedimentation's upward branch does that where snow falls through
    5 km, and so does vertical diffusion. This run cannot separate the two. Its
    twin without vertical diffusion does, and gives the upward branch about a
    fifth (E42b).

The bounds: one column, one hour, and ice that mostly sublimates in its first
minute (E41). A step costs 30 ms. *D1, job `13404535` on terrabyte at
`78586e39`; `analysis/c5_process_closure.jl` and
`analysis/d1_residual_profile.jl`; `output/d1_column_1m_ice/`.*

**E42b. Without vertical diffusion, the upward branch lifts about a fifth of
what D1's `lower` gained above its boundary. The gross residual is unchanged,
so vertical diffusion does not make it.** D1's twin is D1 with `vert_diff` and
`implicit_diffusion` off, and nothing else changed.

| over the hour                                     | D1, J m⁻² | twin, J m⁻² |
|:------------------------------------------------- | ---------:| -----------:|
| `lower` above 5.6 km, rise from the start         |    39,276 |       7,879 |
| gross residual after the first minute             |   1.118e6 |     1.119e6 |
| gross residual at 1 h                             |   2.370e6 |     2.350e6 |
| growth of the gross after the first minute        |   2.129e6 |     2.096e6 |
| signed residual at 1 h                            |     0.286 |       0.286 |
| surface-flux record, column integral              |    95,023 |      89,211 |

  - **The upward branch.** Without diffusion, `lower` still rises above 5.6 km,
    by 7,879 J m⁻². Only sedimentation's upward branch can do that there. That
    is a fifth of D1's rise, so vertical diffusion moved the other four fifths.
    The two atmospheres differ a little, so the split is approximate.
  - **The residual.** Its gross and its growth are within 2% of D1's. The
    growth splits over height as in D1: 42% in the ice layers, 50% below
    4.5 km. So vertical diffusion does not make it, and E42's inference was
    wrong (§6). Grid-mean vertical advection under tracer transport, pressure
    work as on the DYCOMS column (E25), is the next candidate. That is not
    tested.
  - **The rest holds.** Form B closes to 0.14 J m⁻² again, and no tag goes
    below zero. The surface flux still reaches the atmosphere without vertical
    diffusion, but stays in the lowest level: `sfc` peaks at 1,580 J kg⁻¹,
    against D1's 608.
  - A step costs 27 ms.

*D1's twin, job `13412243` on terrabyte at `cf1e9c7c`; the same scripts;
`output/d1_column_1m_ice_no_vdiff/`.*

**E43. On the 1M column over a day, the audit keeps form A below
4.4e-7 J kg⁻¹, and a converged Newton solve takes form B to −3.8e-3 J m⁻².**
`analysis/c8_variants.jl` steps C8's column in four variants, and records the
closure residual, form B and form A as it goes. Converged means 10 Newton
iterations to a relative tolerance of 1e-10, as in E39.

| variant                                 | length | gross residual at the end, J m⁻² | form B at the end, J m⁻² | form A, largest over the run, J kg⁻¹ |
|:--------------------------------------- |:------ | --------------------------------:| ------------------------:| ------------------------------------:|
| tracer, one Newton iteration, as C8 ran | 1 h    |                          177,377 |                    −0.80 |                               7.9e-3 |
| tracer, converged                       | 1 h    |                          177,342 |                  −1.8e-4 |                               7.9e-3 |
| enthalpy, one Newton iteration          | 24 h   |                              193 |                    −5.29 |                               4.3e-7 |
| enthalpy, converged                     | 24 h   |                             12.0 |                  −3.8e-3 |                               2.8e-7 |

  - **C8's form-A gap is the per-tag transport.** Moved as enthalpy, the tags
    keep form A below 4.4e-7 J kg⁻¹ for the whole day, against 117 J kg⁻¹
    under tracer transport (E33). Converging the solve does not change form A
    under either transport. This settles E33's open point, as E34 did on the
    0-moment column.
  - **C8's form-B remainder is the Newton lag.** Converged, form B is
    −3.8e-3 J m⁻² at 24 h against −5.29, and −1.8e-4 against −0.80 at 1 h.
    This confirms E39's reading, which rested on a correlation.
  - **Under the audit, a converged solve also shrinks the residual,** to
    12.0 J m⁻² at 24 h against 193. Under tracer transport it does not:
    177,342 against 177,377 at 1 h, because pressure work makes that residual.
  - The one-iteration day reproduces C8's form B, −5.29 J m⁻² at 24 h against
    E33's −5.3.

*Job `13408403` on terrabyte at `78586e39`; `output/newton_lag/c8_variants_slurm/`.*

**E44. With the tags, the EDMF column does not build in two hours. Without
them it builds in 410 s.** The D4 pair and its control ran on the same node of
`hpda2_test`, with two cores each. Every model key is the same in the three
runs.

| run                                         | besides the model                                                        | build                                                        | outcome                               |
|:------------------------------------------- |:------------------------------------------------------------------------ |:------------------------------------------------------------ |:------------------------------------- |
| `d4_column_edmf`, `d4_column_edmf_enthalpy` | 8 tags, 5 records, the audited closure check, 24 hourly diagnostics      | not finished in 2 h                                          | stopped at the limit, with no output  |
| `d4_column_edmf_notags`                     | nothing                                                                  | 410 s: cache 129 s, tendency function 228 s, integrator 53 s | ran its hour, 18.5 minutes in all     |

  - So what the tags bring makes the build of an EDMF column more than 17
    times slower. Columns without EDMF build with the same kinds of tags in
    minutes (D1, C8).
  - Which part does it is not separated: the tags, the records, the check or
    the diagnostics. *E44b separates it: the tags and the records do it by
    themselves.*
  - Production uses EDMF, so this blocks operation (P4 in
    `OPERATIONAL_TODO.md`).

*Jobs `13404536` and `13404537` at `78586e39`, and `13414334` at `41adabc5`, on
terrabyte; `output/d4_column_edmf_notags/`. The D4 pair left no output.*

**E44b. The EDMF build grows faster than the number of fields the tags and
records add, and the tags with the records alone take it past two hours.** P4
adds back what D4 adds, one part at a time, on the same column and node, with no
closure check and no diagnostics. Its three runs used `edd44e1d`'s model, from a
worktree.

| run                     | fields added             | build stages logged | whole job             |
|:----------------------- |:------------------------ | -------------------:| ---------------------:|
| `d4_column_edmf_notags` | none                     |               410 s |              18.5 min |
| `p4_edmf_two_tags`      | 2 region tags            |               572 s |                27 min |
| `p4_edmf_tags`          | D4's 8 tags              |               876 s |                60 min |
| `p4_edmf_tags_records`  | D4's 8 tags and 5 records |         not reached | over 120 min, stopped |

The build stages are the cache, the tendency function and the integrator, as the
driver logs them. With the 8 tags they take 145 s, 668 s and 63 s.

  - **It is compile time.** Once built, the 2-tag and 8-tag columns each step
    in 17 ms.
  - **It grows faster than the fields.** Each tag and each record is one
    prognostic field. Against the column without them, 2 fields add 8.5 minutes
    to the job, 8 add 42, and 13 add more than 100.
  - **Most of it lies outside the three logged stages.** What is left of each
    job grows from 12 minutes without tags to 18 with 2 and 45 with 8. That part
    holds Julia's start, the model's construction, the first step's compile and
    the solve. Which of those grows is not logged.
  - **The tags and the records take the build past two hours by themselves.**
    D4's closure check and diagnostics are not needed to explain its timeout.

*Jobs `13415603`, `13415604` and `13415605` on terrabyte, at `edd44e1d`, with
their provenance repaired by hand; `output/p4_edmf_two_tags/` and
`output/p4_edmf_tags/`. The third left no output.*

**E44c. The EDMF build's growth with the tags is nearly all in building the
simulation, and most of it is compiled before the driver's first timer
starts.** `analysis/p4_build_stages.jl` times each stage of E44b's runs, with
each compile inside its timer. It ran on the model of `edd44e1d`.

| stage, s                                 | no tags | 2 tags | 8 tags |
|:---------------------------------------- | -------:| ------:| ------:|
| loading ClimaAtmos                       |    32.3 |   32.3 |   18.2 |
| `AtmosConfig`                            |     8.8 |    8.8 |    9.1 |
| `get_simulation`                         |   712.2 |  916.3 | 2603.6 |
| of it, the cache, as the driver logs it  |   133.0 |  135.8 |  137.7 |
| of it, the tendency function             |   241.2 |  318.8 |  588.1 |
| of it, the integrator                    |    52.8 |   53.7 |   58.7 |
| of it, the diagnostics                   |     7.9 |    8.2 |   13.6 |
| of it, not logged                        |     277 |    400 |   1805 |
| explicit tendency, first call            |    83.7 |   84.7 |  109.1 |
| implicit tendency, first call            |    95.3 |  102.4 |  112.2 |
| Jacobian update, first call              |   103.0 |  106.0 |  112.3 |
| first step                               |    95.5 |  101.7 |  137.8 |
| the rest of the run                      |     8.7 |    9.1 |   15.4 |
| the whole script                         |    1142 |   1367 |   3120 |

  - **Building the simulation is the growth.** From no tags to 8 the script
    takes 1,978 s longer. `get_simulation` makes 1,891 s of that. The first
    calls of the two tendencies and of the Jacobian update, and the first step,
    make 94 s. Every second call takes under 0.1 s.
  - **Within it, the part no timer logs grows most:** 277 s, 400 s and
    1,805 s. The logged tendency function grows from 241 s to 588 s. The cache,
    the integrator and the diagnostics barely change.
  - **Why a part goes unlogged.** `get_simulation` calls the
    `AtmosSimulation{FT}` constructor, a single method. Julia infers the calls a
    method makes, where their types are known, before it runs the method's
    first line. So much of the constructor's compile time falls before its
    first `@timed_log` starts, and a logged stage sees only what compiles while
    it runs. The initial state, for one, takes 57 µs inside its timer. This is
    read from how Julia compiles, not measured.
  - **It grows faster than the fields.** `get_simulation` gains 204 s with 2
    tags and 1,891 s with 8: 102 s and 236 s per tag.
  - **Once built, the column steps as fast with tags:** 13.8, 13.7 and 14.7 ms
    per step.
  - Each run is one job. The two baselines ran together, and the 8-tag job
    shared its node for part of its time with V3, MP1 and P1.

Naming the step that grows needs the constructor's pieces timed apart, each
compiled in its own call, or an inference profile. One candidate from the
code, not tested: at `edd44e1d`, 13 functions in `energy_source_tags.jl` and
`process_record.jl` recurse over their tuple of tags or processes with
`Base.tail`, and each compiles one method per remaining tuple. *Jobs `13440706`, `13440707` and `13440637` on terrabyte, from the
worktree at `edd44e1d`; `output/p4_build_stages/`.* E44d names the step, and
the candidate is not it.

**E44d. The growth is ClimaCore building the implicit Jacobian's solver: its
compile-time work on the names of the state's fields grows much faster than
their number.** Julia's own inference timer, `Core.Compiler.Timings`, measured
where the build's inference goes, method by method. The runs used `edd44e1d`.

| column          | tags | `get_simulation`, s | in inference, s | outside it, s |
|:--------------- | ----:| -------------------:| ---------------:| -------------:|
| EDMF (D4's)     |    0 |               731.4 |           568.7 |         158.0 |
| EDMF            |    2 |               955.4 |           791.5 |         162.1 |
| EDMF            |    8 |              2639.6 |          2457.3 |         177.5 |
| 0M, login node  |    0 |               120.5 |            62.0 |          58.3 |
| 0M, login node  |    2 |               139.6 |            75.7 |          63.6 |
| 0M, login node  |    8 |               217.6 |           149.1 |          68.1 |

  - **Inference makes the growth, code generation does not.** From 0 to 8 tags,
    inference grows by 1,889 s on the EDMF column and 87 s on the 0M column.
    The time outside it grows by 20 s and 10 s.
  - **None of it is the tag code.** On both columns the 40 methods that grow
    most make all of the growth, and all of them are in UnrolledUtilities and in
    the field-name sets of ClimaCore's `MatrixFields`. On the EDMF column, `==`
    on tuples of field names grows from 88,597 specializations to 412,854. No
    tag or record function is among them, so E44c's candidate is not the cause.
  - **It is the Jacobian's solver.** On the 0M column the inference root
    `args_integrator`, which builds the Jacobian, grows from 15 s to 97 s. Timed
    apart on the login node, building `FieldMatrixWithSolver` takes 14.1 s with
    13 blocks and 89.2 s with the 8 tags' 21. Every other piece of the Jacobian
    takes under 1.5 s. Inside it, 86 of 88 s go to `field_matrix_solver_cache`,
    and half of that to `partition_blocks` at the top level. On the EDMF column
    the solver is an inference root of its own, 247 s without tags and 579 s
    with 8, and most of `args_integrator`'s 1,727 s is the same work.
  - **Why it grows so fast.** Each level of the nested solver splits the state's
    fields into two groups and builds the four sets of name pairs between them.
    Building a set checks every pair against every other, at compile time, so a
    set over `n` fields costs of order `n⁴` checks, and the intersections with
    the matrix's keys add more. The tags are in the group the solver iterates
    over with the velocities, so they enter every set.
  - **Moving the tags into a group of their own does not help.** A prototype that
    solves them first, in a `BlockLowerTriangularSolve`, took 95.2 s. ClimaCore
    takes each group's complement from the state's name tree, so every level
    still carries every tag. Built over the coupled fields alone, against a name
    tree without the tags, the solver takes 13.6 s with 8 tags.

This points at the fix: solve the tags and records outside ClimaCore's nested
solver, each on its own, and build that solver over the other fields only. The
tags couple to nothing, so this can give the same increments. E44e tests it.
*Jobs `13441219`, `13441220` and `13441221` on terrabyte at `edd44e1d`, and the
login node; `analysis/p4_inference_profile.jl`, `p4_profile_compare.jl`,
`p4_jacobian_pieces.jl`, `p4_solver_profile.jl` and `p4_split_solver.jl`;
`output/p4_inference_profile/`.*

**E44e. With the tags and records solved apart, the EDMF column with 8 tags
and 5 records builds in 21 minutes, and the tags add 37 s to its build.** #76
builds a `SplitJacobianSolver`: the model's nested solver over the coupled
fields, against a name tree without the tags and records, and a one-field solve
for each of them, which repeats what the nested solver did for it. The runs
used `a55d15ce`, with the EDMF refusal switched off locally for the test.

| D4's column              | `get_simulation` before, s | with #76, s | whole script before, s | with #76, s |
|:------------------------ | --------------------------:| -----------:| ----------------------:| -----------:|
| no tags                  |                      712.2 |           — |                   1142 |           — |
| 8 tags                   |                     2603.6 |       748.8 |                   3120 |        1239 |
| 8 tags and 5 records     |            did not finish  |       757.1 |           over 7,200   |        1257 |

  - **The growth is gone.** With 8 tags `get_simulation` takes 37 s more than
    without tags, against 1,891 s more before. The 5 records add another 8 s.
    The first calls of the tendencies and the Jacobian update, and the first
    step, take 415 s with 8 tags against 377 s without, and 471 s before.
  - **The increments do not change.** On the 0M column with 8 tags, the split
    and unsplit solvers give identical increments in every field, with and
    without implicit vertical diffusion, which gives the tags tridiagonal
    blocks and two iterations. An integration item of #76 checks it on the
    tagging column.
  - **The build has to hide which solver it needs.** The fix's first commit
    chose with a plain branch, and inference compiled the unsplit solver as
    well: the 0M cache still took 99.8 s. Chosen through `invokelatest`, it
    takes 20.8 s, and the unsplit solver 97.4 s. The EDMF jobs of that first
    commit were cancelled after 25 minutes.
  - **Once built, the column steps in 14 ms,** as before.
  - Each case is one job on one node type. The logged "Built tendency function"
    now holds the solver's compile, 443 s against 241 s without tags, because
    it no longer falls before the constructor's first timer.

This unblocks every EDMF run with tags within `hpda2_test`'s two hours, which
C1b's validation needs. *Jobs `13441606` and `13441607` on terrabyte, from the
worktree `../ClimaAtmosResiDyn-buildtime-edmf`;
`analysis/p4_build_stages.jl`, `p4_split_check.jl`, `p4_cache_time.jl` and
`p4_cache_profile.jl`; `output/p4_fix_validation/` and
`output/p4_inference_profile/`.*

**E45. In `Float32`, C7's sphere closes as it does in `Float64`, to the last
place the `Float32` integrals hold.** V3 is C7 with `FLOAT_TYPE: Float32`: the
0-moment sphere, 6 elements, 10 levels, a 400 s step, one day, tracer transport
and no repair. It ran at `297eda4c`, C7 at `414f5f1b`. The two merged configs
differ only in the float type and in `energy_source_tag_transport`, a key added
in between, which V3 records at its default, `tracer`.

| at 24 h                                  |       C7, `Float64` |        V3, `Float32` |
|:---------------------------------------- | -------------------:| --------------------:|
| closure residual, J                      |          −2.8227e19 |           −2.8247e19 |
| gross residual, relative                 |           5.8893e-3 |            5.8892e-3 |
| form A, largest gap, J kg⁻¹              |             20.2127 |              20.2146 |
| untagged share, audit table              |          2.91519e-3 |           2.91513e-3 |
| `mp` tag's maximum, J kg⁻¹               |             148.775 |              148.746 |
| `solve!` wall time, s                    |               448.0 |                444.4 |

  - **The residuals agree to rounding, hour by hour.** The smallest step a
    `Float32` total of 4.8e23 J can take is 3.6e16 J. In those steps the two
    residuals lie at most 3.4 apart in any hour, and 0.55 apart at 24 h, while
    the residual itself grows to 784. At 1 h, where it is 24 steps, the 3 steps
    between them read as an 11% difference.
  - **Rounding sets a floor near 1e-7, far below the day's residual.** At
    t = 0 the `Float32` residual is −3.6e16 J, exactly one step, or 7.5e-8 of
    the total. Pointwise, the largest `|e_src_res|` is 0.019 J kg⁻¹, below the
    0.031 J kg⁻¹ step of a `Float32` near 3.3e5 J kg⁻¹, the energy plus the
    offset.
  - **Form A agrees to 6e-4 in every hour,** and its largest gap sits at the
    same grid index, (63, 33, 2). The audit table agrees to 4e-5.
  - **The rain-out's onset is where the two runs differ most.** At 4 h, when
    the `mp` tag's maximum jumps from 2 to 16 J kg⁻¹, V3's is 1.3% lower, and
    the microphysics record's maximum too. By 24 h the gap is 2e-4. Every other
    tag extremum above 1 J kg⁻¹ agrees to 3.1e-4 or better throughout.
  - **`Float32` does not speed up this run on a CPU.** The solve takes 444 s
    against 448 s, one run each, on the same node with 2 CPUs.
  - Not covered: runs longer than a day, the audit transport, the repair, 1M,
    and a GPU, each in `Float32`.

*V3, job `13440822` on terrabyte at `297eda4c`, against C7, job `13399601`;
`output/v3_sphere_float32/`; `analysis/reduce_run.jl`,
`analysis/c5_process_closure.jl` and `analysis/float_type_compare.jl`.*

**E46. The repair's large trades sit just beyond the edge where the two region
tags meet, and each tag is lifted only on the other's side.** The masks of
`tropics` and `extratropics` cross at 20° in a tanh 2° wide. The lat-lon rows lie
5.14° apart, so on this grid the mask is a step between the rows at 18.0° and
23.1°. The front between the tags, where the tropics tag holds half of their
sum, stays at the edge all day: between 19.6° and 21.1° in 80% of longitudes,
levels and hours. The table gives the mass-weighted share of the tropics
ledger's gross at 24 h, both hemispheres together, by row counted from the edge.
The hemispheres agree to three decimals. The last two columns give the share of
the region tags' negative parts at 24 h in each run's twin without the repair.

| rows from the edge, on each side | mass | ledger, tracer (C6) | ledger, audit (C10) | negative parts, tracer | negative parts, audit (C9) |
|:-------------------------------- | ----:| -------------------:| -------------------:| ----------------------:| --------------------------:|
| first: 18.0° and 23.1°           | 0.17 |               0.022 |               0.424 |                  0.000 |                      0.002 |
| second: 12.9° and 28.3°          | 0.17 |               0.738 |               0.470 |                  0.142 |                      0.810 |
| third: 7.7° and 33.4°            | 0.16 |               0.220 |               0.064 |                  0.796 |                      0.118 |
| all others                       | 0.50 |               0.020 |               0.042 |                  0.062 |                      0.070 |

  - **Under tracer transport the trades sit one row out from the step on each
    side.** 96% of the gross lies in the second and third rows, and 2% in the
    rows beside the step. The extremes, ±30,915 J kg⁻¹, sit on the second rows
    at the top level, 26.9 km, where the air is thin.
  - **Under the audit they sit closer to the step.** 42% lies in the rows
    beside it and 47% in the next. The extremes, ±16,294 J kg⁻¹, sit at 11 km,
    at 28.3° and 18.0°.
  - **Each tag goes negative only beyond its own edge.** The repair lifts the
    tropics tag outside the tropics, in 100% of its gross under tracer
    transport and 99.5% under the audit, and the extratropics tag inside the
    tropics, in 100% and 99.9%. At 24 h the two ledgers cancel in every cell
    to 7.3e-10 J kg⁻¹ or better, so the partition repair trades only between
    them.
  - **Without the repair the negative parts lie one row further out** than the
    repair's trades, in both pairs. The ledger adds up where the repair acted
    all day, and the negative parts are a snapshot at 24 h.
  - **By height, both follow the mass, shifted upward.** Above 11 km lie 40% of
    each ledger's gross against 30% of the mass. The negative parts of the twins
    have the same shares by level to 0.005.
  - **In time the two transports differ.** Under tracer transport 14% of the
    day's gross is traded in the first hour and 56% by 6 h. Under the audit it
    grows by 3% to 5% an hour after 1.7% in the first, and its share beside the
    step rises from 4% at 1 h to 43% by 12 h.

This places the undershoots E19 argued for: at the region step, from its
neighbouring rows out, on the far side of each tag's edge. Which operator makes
them is not separated. A mask wider than the grid spacing, in a C6 twin, would
test whether the step is the cause.

*C6, jobs `13385452` and `13385453`; C9 and C10, jobs `13402393` and
`13403083`; `analysis/repair_trades.jl`; `output/repair_trades/`.*

**E47. On 4 MPI ranks, C7's sphere closes as it does on one process, to
rounding.** MP1 is C7 on 4 ranks, launched with `srun --mpi=pmix` and the MPI
context. The closure check reduces over the domain with global sums, and every
run before this one was a single process.

  - **The tables agree to rounding.** The largest relative difference after
    t = 0 is 2.1e-14 in the audit table, 9.2e-13 in form A, 9.3e-13 in the tag
    extrema, 2.5e-13 in the record extrema, and 7.7e-11 in the closure residual
    at 1 h. In Float64 steps of the total, the two residuals lie about one step
    apart, at 1 h and at 24 h.
  - **The atmosphere differs by rounding only.** `ta` differs from C7's by at
    most 1.6e-12 K over the day. Split over 4 ranks, the sums run in another
    order.
  - **It runs 3.8 times faster.** The solve takes 117.4 s against C7's 448.0 s,
    at one thread per rank, on the node that also ran P1's pair.
  - The first try, job `13440823`, died in `MPI_Init`, because the runscript
    called `srun` without `--mpi=pmix`. That was a launch error, and it is
    fixed.
  - Not covered: other rank counts, more than one node, and a restart across a
    changed rank count.

*MP1, job `13440991` on terrabyte at `c2842ba6`; `output/mp1_sphere_4ranks/`,
`analysis/float_type_compare.jl` and `analysis/same_atmosphere.jl`.*

**E48. With the region masks 10° wide, the repair never trades between the
region tags: the step of the 2° mask makes all of E46's trades.** The twin is
`c6_sphere_repair` with `tropics` and `extratropics` written out as
`tanh_latitude` regions 10° wide instead of the named regions' 2°, and no other
key changed. It ran at `f399b9f8`, C6 at `f3bbdb7b`. Its `ta` is identical to
C6's in every value, and the repair ledgers of `sfc` and `rad`, whose tags have
no mask, match C6's, so the repair acts as it did then.

| at 24 h, or over the day                          | 2° masks (C6)             | 10° masks                 |
|:------------------------------------------------- | -------------------------:| -------------------------:|
| `e_src_fix_tropics`, extremes                     | ±30,915 J kg⁻¹            | 0                         |
| region ledger's gross, relative to C6's           | 1                         | 0                         |
| smallest `e_src_tropics` over the day             | 0, after the repair       | 0.0069 J kg⁻¹             |
| smallest `e_src_extratropics` over the day        | 0, after the repair       | 3,243 J kg⁻¹              |
| closure residual                                  | −4.074e19 J               | −4.087e19 J               |
| form A, largest gap                               | 148.781 J kg⁻¹            | 148.781 J kg⁻¹            |

  - **No region tag goes negative, so the repair has nothing to trade.** The
    region ledger is zero in every cell at every hour. With 2° masks it grew to
    ±30,915 J kg⁻¹ one to two rows beyond the edge (E46).
  - **Part of the reason is that a 10° mask never reaches zero.** At the equator
    the extratropics mask is 0.036, so the extratropics tag starts with 3.6% of
    the total there, and at the poles the tropics mask is 8e-7. A tag's
    transport undershoot then stays above zero. A 2° mask is 4e-9 at the
    equator, so the tag sits at zero where the undershoots arrive.
  - **That is also the price.** Each region tag holds a few percent of the
    other region's energy from the start, so the reading "energy that came from
    the tropics" is blurred by that much near the edge and in the far region.
  - **The rest is unchanged.** The closure residual differs by 0.3%. Form A
    agrees to 1e-8, since the rain-out has no tag here in either run, as in C6.
    The source tags' repair ledgers are the same, apart from the `new_` tags,
    whose masks changed too: their ledgers shrink by factors of 2 and 5.

So the trades are a property of a region mask that is a step on the grid, not
of the repair or the transport. Whether the named regions should be wider is a
default, and a trade between provenance sharpness and the repair's trades. It
is the owner's decision. *Job `13441633` on terrabyte at `f399b9f8`;
`output/c6_sphere_wide_mask/`; `analysis/wide_mask_trades.jl`,
`analysis/same_atmosphere.jl`, `analysis/c5_process_closure.jl`.*

**E49. Summed over levels and over columns, form A's gap shows which way a
transport error moved. A process that no tag follows, and the repair, keep most
of their sum.** A7. `c5_process_closure.jl` now writes `gap_cancellation.csv`:
for each sample, the absolute value of the gap's mass-weighted sums, added up,
over its weighted gross. Summed within each column first, over levels; within
each level first, over columns; and over everything. One means nothing cancels.

| run, at 24 h                         | what makes the gap                  | kept over levels | kept over columns | kept overall | ∫ gap / ∫ new energy |
|:------------------------------------ |:----------------------------------- | ----------------:| -----------------:| ------------:| --------------------:|
| C7, sphere, tracer                   | the per-tag limiter (E37)            |            0.037 |              0.99 |        0.035 |               5.2e-5 |
| C9, sphere, audit                    | the loss clamp, horizontally (E36)   |             0.88 |             0.073 |        0.041 |               4.7e-5 |
| C10, sphere, audit and repair        | the repair's created energy (E38)    |             0.92 |              0.93 |         0.23 |               6.0e-4 |
| C6, sphere, no repair                | the rain-out has no tag (E28)        |             0.47 |              0.99 |         0.46 |              1.26e-3 |
| C6, sphere, repair                   | the same, and the repair             |             0.62 |              0.70 |         0.42 |               3.5e-3 |
| C5, column, 0M                       | subsidence has no tag (E20)          |             1.00 |                 — |         1.00 |                 0.26 |
| C8, column, 1M, tracer               | not separated (E33)                 |            0.011 |                 — |        0.011 |              −1.5e-5 |
| C9, column, audit                    | rounding (E34)                      |            0.066 |                 — |        0.066 |              2.6e-12 |

  - **It reproduces the earlier numbers.** C7's 0.037 over levels is E37's, C9's
    0.88 is E36's, and the four sphere integrals are E38's. The regenerated
    `process_closure.csv` is identical to the committed one for all eight runs.
  - **A transport error cancels along the way it moved.** C7's limiter error
    moves vertically: it cancels within columns, 0.0014 to 0.037 over the day,
    and along levels hardly at all, 0.945 to 0.995. C9's audit error is the
    reverse: 0.88 to 0.95 over levels, 0.022 to 0.090 over columns. Summed over
    everything, C7 keeps at most 0.035 and C9 at most 0.087, both 0.04 at
    24 h.
  - **C8's gap, which E33 left unseparated, cancels within its column,** to
    0.011 at 24 h and at most 0.016 over the day. So it behaves as a transport
    error, not as a missing process. Which transport term makes it is not
    shown.
  - **A process no tag follows keeps its sum.** On C5's column the gap keeps
    at least 0.9999 of it at every hour. On C6's sphere it keeps 0.97 at
    1 h and 0.46 at 24 h. The fall fits E38, where the limiter's part, which
    cancels, grows as the square of time and the missing process's part levels
    off. That reading is inferred, not separated here.
  - **So does the repair.** C10 keeps 0.92 to 0.98 over levels and 0.93 to 0.97
    over columns all day. Overall it falls from 0.85 at 1 h to 0.23 at 24 h.
  - **Neither fraction names the cause alone.** At 24 h C10's repair keeps 0.23
    overall and C6's missing rain-out 0.46. What separates them is the repair
    ledgers, and a check of labels (E38, A2). The fractions add the direction of
    a transport error, and they say when a gap is not transport at all.

On the sphere the weights take a hydrostatic density from `ta` with a surface
pressure of 1e5 Pa, as in E38, so they are approximate. On a column they are the
model's `rhoa` times the level spacing. Every sphere run's largest pointwise gap
is at 24 h. *Login node, from the runs' hourly NetCDF on scratch;
`analysis/c5_process_closure.jl`; `output/a7_gap_cancellation/`.*

**E50. The energy tags (`ρe_tag_*`) on a moist baroclinic wave with vertical
diffusion miss `ρe_tot` by 7% of its gross after ten days, and pointwise by 7%
of the largest `|e_tot|` after a week. More than half of the gross comes in
the 30 hours from day 8 to day 9.25.** B1, `b1_base`: `MoistBaroclinicWave`, 0M,
`h_elem` 6, `z_elem` 10, `dt` 400 s, hyperdiffusion and
`DecayWithHeightDiffusion`, two latitude tags, 10 days, `Float64`. It is the
baseline of the four-run split. B1a to B1c were not run: the owner approved
B1 alone (decision 7 of 2026-09-17).

| day | `relative` | `gross_relative` | `max \|e_tag_res\|`, J/kg | over `max \|e_tot\|` |
| ---:| ----------:| ----------------:| -------------------------:| --------------------:|
|   1 |    3.63e-5 |           0.0120 |                     4,093 |                0.037 |
|   5 |    2.49e-4 |           0.0234 |                     7,324 |                0.067 |
|   8 |    3.79e-4 |           0.0333 |                     9,282 |                0.085 |
|   9 |    9.06e-4 |           0.0716 |                    27,483 |                0.252 |
|  10 |    1.04e-3 |           0.0698 |                    17,278 |                0.159 |

  - **The gross grows steadily for eight days,** by about 0.003 a day after
    the first. From day 8.0 to 9.25 it more than doubles, 0.033 to 0.073,
    and then stays there. Over the same interval the volume where `ρe_tot` is
    not positive falls from 43.3% to 40.3%. Both fit the wave breaking, but
    no run here separates a cause.
  - **The docs' figure does not carry over.** `tagged_tracers.md` says that in
    a 10-day dry baroclinic wave the residual stayed below one percent of the
    pointwise energy scale. Here it is 3.7% of the largest `|e_tot|` after one
    day. The 99th percentile of `|e_tag_res|` over that scale is within 1% of
    the maximum from day 1 to day 7. So the residual is broad, not a few
    extreme points. B1 is moist and has vertical diffusion, and the docs' run
    was dry, so this does not falsify the docs' figure. B2, the dry case, would
    test it, and B2 has not run.
  - **The signed integral stays small.** `relative` is 1.04e-3 at ten days.
    The residual cancels in the integral, as a transport error does (E49).
  - **Which operator carries it is not known.** That is what the split would
    have answered.
  - **Cost:** 0.628 SYPD on 2 CPUs of `hpda2_test`, 63 minutes of solve, 69
    in all.

The gross and the signed integral are from the closure table. The pointwise
numbers are from the NetCDF writer's bilinear remap to 72 × 36 × 10 points,
not from the model's own nodes, and the scale is `max |e_tot|` there, 1.09e5 to
1.12e5 J/kg. *Job `13501290` on terrabyte, `hpda2_test`, 2026-09-18. Model code:
`main` at `38661891`. Driver, runscript and configuration: this branch at
`58d9b0c8`, copied into the worktree `../ClimaAtmosResiDyn-b1`.
`analysis/reduce_run.jl` and `analysis/b1_residual_scale.jl`;
`output/b1_base/`.*

**E51. With no diagnostic on, the fork after the merge of upstream v0.42.11
gives upstream's results bit for bit, and so does C1b against `main`.** Both
checks compare the state at the end of the run and one implicit, remaining and
limiter tendency at that state. They use `isequal` on the parent arrays, and the
bit patterns are also equal. The three configurations are ones upstream can run:

  - the DYCOMS RF02 prognostic-EDMF column with 1M and the updrafts' vertical
    diffusion on, for 1 h;
  - a DYCOMS 1M column without EDMF, for 10 min;
  - B1's 0M moist baroclinic wave without tags, `h_elem` 6, for 1 day.

| check | a | b | where | configurations | result |
|:-- |:-- |:-- |:-- |:-- |:-- |
| #89 | the fork at `d83ffcc3` | upstream `d331fe30` | job `13503291`, one node, both at once | all three | all bit for bit |
| C1b | `main` at `38661891` | C1b at `fe69cd06` | login node, one after the other | the two columns | all bit for bit |

  - **The environments were the same.** In each check both checkouts used one
    resolved `.buildkite` manifest and the same preferences. For #89 its package
    versions equal upstream's committed manifest. Only `project_hash` and
    ClimaAtmos's own version line differ.
  - **Each run loaded its own code.** `pkgdir` in each log names its checkout,
    and only the fork's log shows the fork's `tagging` group.
  - **Every updraft field is in the compared state.** The EDMF column's `Y.c`
    holds 17 fields, 7 of them the updraft's. The updraft has area at all 30
    levels, cloud liquid at 25 and rain at 12, so the sedimentation corrections
    and the updrafts' vertical diffusion ran on real data. Ice and snow are
    zero in this warm case.
  - **No NaN and no Inf anywhere.** Signed zeros occur and match, in `Y.f` at 2,
    4 and 6,912 entries.
  - **C1b's change also holds with tags on.** The model's fields with tags on
    are those of the run without them. That is T6's last item, on the EDMF
    column.
  - **The job's own comparison crashed.** It read the results without
    ClimaUtilities, which the saved `ITime` needs. The comparison was re-run on
    the login node from the saved files, and a review agent recomputed it
    independently.
  - **Not covered:** diagnostic output, restarts, MPI, GPU, `Float32`, the SEM
    limiter, the non-negativity methods, a prescribed flow, radiation other
    than DYCOMS, a slab surface, topography, and any `Y` component besides `c`
    and `f`. `analysis/parity/` now saves every component, refuses a NaN,
    records its provenance and checks both runs' exit status. It was written
    after these runs and has not run yet.

*Job `13503291` on terrabyte, `hpda2_test`, node `hpdar03c01s11`, 2026-09-18;
the C1b check on the login node. `analysis/parity/` holds the hardened
successors of the scripts that ran; `output/parity_89_d331fe3/` and
`output/parity_c1b_main/` hold the comparisons and the review's inspection.*

**E52. With no diagnostic on, the fork builds the EDMF column in 635 s where
upstream takes 249 s. The difference is in building the tendency function.**
From the logs of E51's job. Both checkouts ran at once on one node, one run
each, so the numbers are single measurements.

| stage, EDMF column | fork `d83ffcc3`, s | upstream `d331fe30`, s |
|:-- | --:| --:|
| built cache | 150.1 | 150.9 |
| built tendency function | 396.7 | 21.8 |
| initialized integrator | 88.0 | 76.2 |

  - On the 1M column the tendency function takes 22.4 s against 7.0 s.
  - The timed block builds the Jacobian's cache and solver (`get_jacobian`)
    and the ODE function. The fork changes `manual_sparse_jacobian.jl` by about
    400 lines, the split solver of #76 among them, and wraps the hooks in the
    ledger's meters. Which of these costs the time is not separated.
  - `main` before the merge took 413 s in the same block, on the login node
    in the C1b check. So the gap predates the merge.
  - This is run time, which the parity rule allows to differ, but every EDMF
    build pays it, in CI and in production.
  - **Corrected by E56:** the stage times are right, but their sum is not the
    build time. Upstream compiles the same Jacobian solver before the timed
    block, where no stage counts it. The whole build takes the same time.

*The same job and logs as E51.*

**E53. With C1b, the EDMF columns run with tags. The gross residual is zero-sum
and stays near half a percent, and the records close the column's budget.**
These are C1b's validation runs, submitted with the owner's approval. They
ran from the C1b branch at `fe69cd06`, with this branch's run files. D4 is the
DYCOMS RF02 EDMF column with 1M, 8 tags and 5 records, for a day at `dt`
120 s. D5 is TRMM LBA deep convection with ice, 82 levels, for 6 h.

| run | residual `relative` | `gross_residual`, J/m² | `gross_relative` | untagged / overclaimed, J/m² | form B gap, J/m² |
|:-- | --:| --:| --:|:-- | --:|
| `d4_column_edmf`, tracer | 9.2e-5 | 6.71e5 | 5.9e-3 | 3.41e5 / 3.30e5 | 0.49 of 8.9e5 |
| `d4_column_edmf_enthalpy` | 3.7e-4 | 5.41e5 | 4.7e-3 | 2.92e5 / 2.50e5 | 0.49 of 8.9e5 |
| `d4_column_edmf_vd`, the updrafts' diffusion on | 4.5e-4 | 6.83e5 | 6.0e-3 | 3.67e5 / 3.16e5 | 1.4 of 9.3e5 |
| `d5_column_edmf_ice`, 6 h | -8.2e-7 | 2.76e6 | 3.1e-3 | 1.380e6 / 1.381e6 | -317 of 1.05e7 |

  - **The runs build and finish.** Each took 23 minutes on two cores. The
    tendency function took 450 s of that. Before #76 the D4 pair did not
    build in two hours (E44).
  - **The residual moves energy but does not lose it.** Untagged and
    overclaimed energy are about equal in every run. No energy is orphaned,
    and no mass sits where the total is not positive. That is the pattern of
    a transport mismatch, not of a process that no tag follows.
  - **The records close the column.** Form B, the change of `∫ρe_tot` against
    the sum of the records, misses by 0.5 J/m² in 8.9e5 on D4, and by 317 J/m²
    in 1.05e7 on D5. The D5 remainder is not assigned.
  - **Form A's gap cancels in the column,** as a transport error does. Over
    levels it keeps 0.05 of its weighted gross on D4, 0.005 with the updrafts'
    diffusion, and 8e-12 on D5. Under the enthalpy audit it does not cancel,
    but its integral is 4.5e-8 of the new energy.
  - **The model is untouched.** `ta` and `rhoa` are bit for bit the same in
    the D4 pair, which differ only in how the tags move.
  - **The audit leaves most of D4's residual.** Under enthalpy, D4 keeps 5.4e5
    J/m², against 2,284 J/m² for C9, the same tags on a column without EDMF
    (E34). The audit does not reach the EDMF eddy diffusion. That diffusion
    moves the tags as tracers and `ρe_tot` as enthalpy (C1c). That this is
    where the remainder comes from is inferred, not separated.
  - **The updrafts' diffusion adds little:** 6.83e5 against 6.71e5.
  - **How much C1b removed is not measured here.** There is no D4 run
    without C1b's sharing, because before #76 it did not build (E44). T6 shows
    the sharing at the tendency level: from the SGS mass flux and from
    sedimentation, the partition matches the parent to 100 eps. C8, the same
    tags on a column without EDMF, had 2.46e6 J/m² at `dt` 10 s (E33). The
    time step and the turbulence differ, so this is no like-for-like
    comparison.

*Jobs `13503558` to `13503561` on terrabyte, `hpda2_test`, 2026-09-18, from the
worktree `../ClimaAtmosResiDyn-c1b-val` at `fe69cd06`. The reductions are
`analysis/reduce_run.jl` and `analysis/c5_process_closure.jl`. The outputs are
in `output/d4_column_edmf/`, `output/d4_column_edmf_enthalpy/`,
`output/d4_column_edmf_vd/` and `output/d5_column_edmf_ice/`.*

**E54. A restart carries the tags and the records exactly, but the model
itself does not restart this column bit for bit, even with
`reproducible_restart: true`.** V5 ran C5's column for a day in one run, and
again from that run's checkpoint at 12 h. Both ran from #92 at `e4e9e5b3`,
with `reproducible_restart: true`.

  - **The guard passed** the real restart with the same settings, with no
    warning. The restarted run loaded the checkpoint in 9.9 s.
  - **At the restart the tags are restored exactly.** The closure and audit
    rows at 12 h are the continuous run's text for text. The exceptions are
    the columns that start over by design: the spin-up reference, `NaN` until
    it is taken again at 13 h, and the repair's ledger, zero.
  - **At 24 h the states are not bit for bit.** Every model field differs:
    `ρ` by 1.5e-10 of its largest value, `uₕ` by 2e-11, `ρe_tot` by 1.7e-9,
    `ρq_tot` by 8e-10 and `u₃` by 3e-9. The tags differ at the same level,
    4e-11 to 1.4e-8. `rad` and `prc_e_radiation` differ most, 1.4e-8 and
    1.1e-8, which is 9e-8 and 2e-8 of their change over the second 12 hours.
    The surface-flux record is bit for bit, because its flux is prescribed.
  - **The closure continues without a jump.** After the restart the rows
    agree to 4e-9 in `residual` and 8e-10 in `gross_residual`.
  - **The difference is the model's, not the tags'.** The model never reads
    the tags (E17), so they cannot move `ρ`. Whether upstream restarts this
    column bit for bit is not measured; a pair without tags would show it.
    `reproducible_restart` acts only on the cloud fraction
    (`cloud_fraction.jl:51`), and upstream's restart test compares a state
    read back, not a continued run.
  - **So V5's criterion, the state bit for bit at the end, is not met,** for a
    reason outside the tags. For the tags V5 shows that a restart restores
    them exactly, and that afterwards they differ only as much as the model's
    own fields do.

*Jobs `13503985` and `13503986` on terrabyte, `hpda2_test`, 2026-09-18, from
the worktree `../ClimaAtmosResiDyn-c2-val` at `e4e9e5b3`. Compared with
`analysis/v5_compare_h5.py`, because the login node's one core was taken by
P7's timing. The outputs are in `output/v5_c5_continuous/` and
`output/v5_c5_restarted/`, with the comparison in `compare.txt`.*

**E55. In Float32, C1b's EDMF column keeps the size of the Float64 residual
over the day, but the residual tilts toward overclaiming.**
`d4_column_edmf_vd_float32` is `d4_column_edmf_vd` in Float32. It ran from #91
at `9dd30a90`.

  - **It runs cleanly:** no NaN, nothing orphaned, no non-positive total and
    no negative source tag. The repair moved 6.5e-9 of the scale by 24 h,
    against 8.2e-9 in Float64. The tendency function took 558 s to build.
  - **The size is the same.** At 24 h `gross_relative` is 6.93e-3 against
    5.98e-3. But over the day the two series cross: their means are 4.68e-3
    and 4.80e-3, and their ranges 1.7e-3 to 7.7e-3 and 1.5e-3 to 8.6e-3. The
    atmospheres drift apart, and the totals differ by up to 1.2e-4. So the
    difference at 24 h is within the day's variation.
  - **The balance differs.** Float64 is net untagged at every hour:
    overclaimed over untagged runs from 0.73 to 0.99, with a mean of 0.85.
    Float32 is net overclaimed in 12 of 24 hours: 0.91 to 1.14, with a mean
    of 1.02. At 24 h untagged is 3.70e5 against 3.67e5 J/m², and overclaimed
    is 4.22e5 against 3.16e5.
  - **The records still close the column.** Form B misses by 56 J/m² in
    8.8e5 at 24 h, against 1.4 in 9.3e5 in Float64. That is 6e-5 of the
    change, the size Float32 sums reach over 720 steps.
  - **Form A's gap is larger and cancels less.** Its largest pointwise value
    is 11.8 J/kg against 6.2, and its weighted gross 2,781 against 1,303. Over
    the column it keeps 0.11 of that gross, against 0.005 in Float64, so its
    integral is −318 against −6, or 2.4e-5 of the new energy. A transport
    error cancels in the column (E49) and rounding does not, so part of
    Float32's form A gap is rounding.
  - **Not separated:** whether the residual's tilt toward overclaiming is
    Float32 rounding in the tags or the different atmosphere.

*Job `13503987` on terrabyte, `hpda2_test`, 2026-09-18, from the worktree
`../ClimaAtmosResiDyn-c1b-val` at `9dd30a90`. Forms A and B are
`analysis/c5_process_closure.jl`. The outputs are in
`output/d4_column_edmf_vd_float32/`.*

**E56. The fork does not build the EDMF column more slowly than upstream.
E52's gap is where the compile is counted.** Both checkouts spend about 400 s
compiling the same Jacobian solver (`FieldMatrixWithSolver`). Upstream compiles
it while Julia infers `args_integrator`, before the timed block "Built tendency
function" starts, so no logged stage counts it. The fork compiles it at run
time, inside that block. E52 summed the logged stages.

  - **The whole build takes the same time.** `get_simulation` took 788 and
    834 s upstream, in two runs, and 823 s in the fork. Upstream's log has a
    425 s gap without a line between "Assembled callbacks" and the block's
    first line.
  - **The Jacobian alone costs the same:** the first `get_jacobian` took 400 s
    upstream and 406 s in the fork, nearly all of it compile. SnoopCompile finds
    388 s of inference upstream and 368 s in the fork. Most of it is
    `UnrolledUtilities` and the `FieldNameSet` work of MatrixFields'
    `partition_blocks`. No ClimaAtmos or MatrixFields method differs by more
    than 9 s.
  - **Two breaks in inference move the compile into the block.** One is #76's
    `invokelatest`. The other is the fork's tag-name predicates on a
    `FieldName`, which call `startswith(string(name), …)` at run time. So
    `sedimenting_water_tag_names` infers as an abstract tuple, and so do the
    Jacobian's block pairs, its matrix and its solver. Removing either halves
    the block. Removing both gives upstream's 22.4 s. The parent-budget
    ledger's meters play no part.
  - **A small real cost:** without tags the fork's cache holds the same
    `FieldMatrixWithSolver` twice, as matrix and as solver. The Jacobian's
    type doubles, and the ODE function compiles in 11.1 s against 4.3 s.
  - **Not explained:** a whole `edmf_column` parity run is 5 to 6% slower in the
    fork (1476 against 1395 s in job 13503291). Two identical upstream runs
    differed by 46 s.

A fix that puts the untagged fork on upstream's path was tried in the session
and not committed. It makes the tag predicates `@generated`, chooses the
solver builder from the model's type, and keeps the unsplit solver once. The
`edmf_column` parity run was bit for bit, and the block took 22.4 s. It saves
the ODE function's few seconds; the build's wall time does not change.
*Measured on the login node, one core, runs strictly one at a time,
2026-09-18. Scripts, patches and logs are in `$SCRATCH/claude_work/p7/`.*

**E57. #89's fork is bit for bit upstream on a restart and under the vertical
water borrowing limiter. The prescribed-flow column does not run upstream.**
The paths #89's review found uncovered (R2), run in the fork at `c068d564`,
whose tree is `main`'s `369c8f28`, and in upstream d331fe30, on one node with
one environment, as in E51.

  - **A restart in two stages is bit for bit:** the 1M DYCOMS column to 10
    minutes with a checkpoint at 5, and the same column restarted from that
    checkpoint to 10 minutes. The state and the implicit, remaining and
    limiter tendencies are identical under `isequal`, in both stages.
  - **The 1M column with `tracer_nonnegativity_method:
    vertical_water_borrowing`** is bit for bit, state and tendencies.
  - **Within one checkout the restart is exact:** the restarted column equals
    the uninterrupted one at 10 minutes, in every field and tendency, with
    `reproducible_restart` at its default.
  - **The Shipway-Hill column fails in both checkouts,** at the first step.
    `ShipwayHill2012VelocityProfile` compares the model time, an `ITime`, with
    a `Float64` (`src/types.jl:1715`), and no method exists for that. So the
    fork's `prescribe_flow!` hook cannot be run. By reading it copies `ρq_tot`
    into `ᶜtemp_scalar_2` before it clamps, and without tags
    `rescale_water_tags!` does nothing. The failure is upstream's.

*Job `13504311` on terrabyte, `hpda2_test`, 2026-09-18. The Shipway-Hill
failure stopped the job before its comparison, so the three finished
configurations were compared on the login node. The outputs are in
`output/parity_89_r2/`.*

**E58. The model itself does not restart C5's column bit for bit; the tags
change nothing across a restart.** V5's pair was run again without tags,
records or closure check, from the same checkout (#92 at `e4e9e5b3`), with
`reproducible_restart: true`.

  - **Without tags the restart differs exactly as with them:** `ρ` by 1.758e-10,
    `ρe_tot` by 1.604e-4 and `u₃` by 1.543e-11 at 24 h, the same numbers as E54.
  - **The model's fields do not depend on the tags,** in either run. With tags
    and without, the uninterrupted runs are bit for bit in `ρ`, `uₕ`,
    `ρe_tot`, `ρq_tot` and `u₃`, and so are the restarted runs.
  - **So E54's difference is the model's restart.** The tags neither cause it
    nor change it.
  - **Not every restart differs:** in E57 a 1M column restarted after 5
    minutes is exact, at the post-#89 code and the default
    `reproducible_restart`. This pair differs in the microphysics (0M), the
    length (12 hours before the restart), the code (before #89) and
    `reproducible_restart: true`. Which of these matters is not separated.

*Jobs `13504312` and `13504313` on terrabyte, `hpda2_test`, 2026-09-18, from
the worktree `../ClimaAtmosResiDyn-c2-val` at `e4e9e5b3`. Compared with
`analysis/v5_compare_h5.py`. The outputs are in `output/v5_c5_continuous_notags/`
and `output/v5_c5_restarted_notags/`, with the comparisons in `compare.txt` and
`compare_with_tags.txt`.*

**E59. C1c, as built, makes the EDMF column's residual under the enthalpy
audit larger, in all three placements.** D4 under `enthalpy` for a day, from
four checkouts that differ only in C1c: `main` without it, and its options 1,
2 and 3.

| gross residual, J/m² | 1 h | 4 h | 12 h | 24 h | `gross_relative` at 24 h |
|:-- | --:| --:| --:| --:| --:|
| base, `main`: the tags diffuse as tracers | 1.68e5 | 3.27e5 | 4.61e5 | 6.32e5 | 5.5e-3 |
| option 1: the share beside the parent, no Jacobian block | 1.98e5 | 9.29e5 | 3.25e6 | 6.71e6 | 5.9e-2 |
| option 2: option 1 with the tracer-diffusion blocks kept | 5.05e4 | 2.26e5 | 6.49e5 | 1.18e6 | 1.0e-2 |
| option 3: option 1 with the share in the explicit tendency | 5.67e4 | 2.52e5 | 7.90e5 | 1.46e6 | 1.3e-2 |

  - **C1c removes the form mismatch at first.** At 1 h options 2 and 3 leave a
    third of the base residual.
  - **But each option grows about linearly, with no plateau:** option 1 by
    about 2.8e5 J/m² an hour, options 2 and 3 by 5e4 to 6e4. They pass the
    base after 4 to 6 hours. The base levels off between 4 and 8 hours, near
    3.2e5, and then rises to 6.3e5.
  - **So C1c adds a systematic timing error that outweighs the mismatch it
    removes.** The parent's eddy diffusion is implicit and stiff. The tags'
    share follows the parent's flux at the Newton iterate (option 1) or at the
    stage state (option 3), not the parent's implicit update, and the gap
    accumulates each step. Keeping the tracer-diffusion blocks (option 2)
    damps it most, although that Jacobian is not the tags' true derivative.
    Option 2 also moves the repair 400 times more (3.4e-6 of the scale
    against 8e-9), so it drives the tags negative.
  - **The model is untouched:** `ta` is identical in all four runs.
  - **The base is 17% above E53's 5.41e5** at 24 h. E53 ran before #89, with
    ClimaCore 0.16 and upstream v0.42.9's model, so the two atmospheres differ.

C1c is not to be opened as a pull request in this form. Sharing a stiff
implicit flux needs the tags to follow the parent's implicit update, for
example a Jacobian block for the shared flux, or sharing the parent's
increment of the implicit stage. Both are design questions (see
`OPERATIONAL_TODO.md`).
*Jobs `13504651` to `13504654` on terrabyte, `hpda2_test`, 2026-09-18, from
`../ClimaAtmosResiDyn-c1c-{base,opt1,opt2,opt3}`: `main` at `50b2a4d2`, and
C1c at `9aeb5205` with the variants' patches. The outputs are in
`output/c1c_*_d4_enthalpy/`.*

**E60. The tags' mislabelled energy is flushed only as fast as it is lost,
often slowly, and the one-day plateau is mixing, not the rule. So over long
runs the error can keep growing, and the column integral hides most of it.**
An analysis of the recorded runs, with no new run. It checks an estimate
given to the owner: that 3 to 6% of a day's process energy, misplaced each
day, would level off at 0.5 to 5% of `E` within weeks.

  - **The loss rule does flush the residual, in proportion.** In each bracket
    the residual `R = E − Σ region tags` changes by `−(R/E)·Δ⁻`, untagged and
    overclaimed alike, and gains leave it unchanged, because the masks sum to
    one (`energy_source_tags.jl:609-636, 430-432`). The repair keeps the sum,
    so it does not touch `R` (`:673-675`). On C9's column, where nothing else
    moves `R`, the hourly records predict its decay exactly: 2.661e3
    predicted against 2.660e3 observed at 1 h, and 2.284e3 against 2.284e3 at
    23 h.
  - **But the flushing time is `E` over the losses where `R` sits, not over
    the throughput.** On D4 that rate is 0.05 to 0.26 a day, or 4 to 20 days;
    in the surface layer it is about zero, so `R` there does not decay. On C9's
    sphere 91% of `|R|` sits above 10 km, where the rate is 0.0013 to 0.0025 a
    day, or 1 to 2 years.
  - **Under the enthalpy audit `R` is not transported,** because the shares
    are normalised (`:831-833`, `:1240-1330`): the partition carries exactly
    the parent's flux. Under the default `tracer` transport, and in the EDMF
    eddy diffusion before C1c, `R` moves and mixes like a tracer.
  - **The one-day plateau on D4 is mixing, not the loss.** Between jumps the
    residual falls 3.5 to 4% an hour, 10 to 40 times faster than the loss
    allows: the EDMF eddy diffusion mixes `R` as a tracer. Even so it trends
    upward, best fitted by √t. The free-troposphere residual grows from −31
    to −237 J/kg over the day. Without that mixing it grows about linearly
    (C1c's options, E59), and so does every run under `tracer` transport,
    whose second-half slope is 0.75 to 0.9 of the first half's.
  - **B1, ten days of the `ρe_tag_*` family, is a fair proxy for `R`,** since
    the rule difference acts on `R` only through the loss rate, under 2% in
    ten days there. A saturating fit to its first two days was exceeded by day
    7, and by 2.8 times at day 10: 0.43% of the sphere's `E` at day 1, 0.97%
    at day 7 and 2.5% at day 10.
  - **The 24 h residual is a state, not a daily rate:** 29% of D4's is the
    first hour. Against the day's process energy it is 1.2 to 4.1% depending
    on the denominator (`output/displacement_check/throughput_d4.txt`).
  - **The column integral hides most of the per-tag error.** Take two runs
    with bit-identical `rhoa` and a residual of 2.1% of `E` (C6 and C9). Their
    small tags differ pointwise by 5 to 10% (`rad` 10%, `sfc` 8.5%, `sub`
    4.8%), but their column integrals by 0.1 to 0.3%. Between C1c's base and
    options 2 and 3 the tags differ pointwise by 67 to 132%. A share of the
    parent's net diffusive flux does not mix provenance where turbulence moves
    little net energy: `sfc` stays below about 300 m, where tracer diffusion
    spreads it through the boundary layer. `R` cannot see this.

So the estimate does not hold. Over a year, under stationary conditions: about
0.1% of `∫E` under the audit on a sphere without stiff shared fluxes; at least
5% under the default `tracer` transport on a sphere, and possibly 25% or more
if event-driven jumps continue while the loss takes months; small tags off
pointwise by 4 to 9 times the gross fraction. V2 is the first run long enough
to test this; its outputs are set in `OPERATIONAL_TODO.md`, item 10.
*Scripts in `analysis/displacement_check/`, outputs and notes in
`output/displacement_check/`. They read the runs' NetCDF on scratch.*

**E61. Most of C1c's drift is the implicit timing gap: with a converged Newton
solve, option 1's residual at 12 h is 14 times smaller.** C1c's option 1 on D4
under `enthalpy`, run again with up to ten Newton iterations to a relative
tolerance of 1e-8, for 12 hours.

| gross residual, J/m² | 1 h | 4 h | 8 h | 12 h |
|:-- | --:| --:| --:| --:|
| base, `main` (E59) | 1.68e5 | 3.27e5 | 3.20e5 | 4.61e5 |
| option 1, one Newton iteration (E59) | 1.98e5 | 9.29e5 | 2.00e6 | 3.25e6 |
| option 1, converged | 4.51e4 | 8.49e4 | 1.66e5 | 2.32e5 |

  - **The gap was the drift's bulk.** Converged, option 1 grows about 1.7e4
    J/m² an hour against 2.8e5, and at 12 h it is half the base.
  - **Not all of it.** It still grows, from 4.5e4 at 1 h to 2.3e5 at 12 h.
    What is left is not separated: the solve stops at its tolerance, and the
    base's cloud and free-troposphere parts, which C1c does not touch
    (ATTRIBUTION_PATH.md section 1.3), are still there.
  - **This supports following the parent's increment,** which removes the gap
    without iterating. A converged solve changes the model's trajectory and
    costs several times the step, so it is a diagnostic, not the path (R5).

*Job `13504771` on terrabyte, `hpda2_test`, 2026-09-19, from
`../ClimaAtmosResiDyn-c1c-opt1` at `9aeb5205`. The outputs are in
`output/c1c_opt1_newton_d4_enthalpy/`.*

**E62. Following the parent's increment closes the EDMF column: 267 J/m² at
24 h against 6.32e5, with the model bit for bit.** D4 under
`energy_source_tag_transport: enthalpy_increment`, the prototype at `35042f33`,
set against `c1c_base_d4_enthalpy` (E59), the same configuration under
`enthalpy` on the same `main`.

| gross residual, J/m² | 1 h | 4 h | 12 h | 24 h | `gross_relative` at 24 h |
|:-- | --:| --:| --:| --:| --:|
| base, `enthalpy` (E59) | 1.68e5 | 3.27e5 | 4.61e5 | 6.32e5 | 5.5e-3 |
| prototype, `enthalpy_increment` | 92.8 | 112 | 192 | 267 | 2.4e-6 |

  - **G1's criterion 1 is met.** 267 J/m² is 37 times below the target of
    1e4, and 2,370 times below the base. The first 12 hours add 192 J/m² and
    the second 75, so the residual does not grow systematically.
  - **It is zero-sum.** The signed residual at 24 h is −0.53 J/m², against
    +4.5e4 in the base. The audit splits the gross into 133 untagged and 134
    overclaimed. By layer it is 143 J/m² below 550 m (+118 signed), 103 in the
    cloud layer (−98) and 20 above (−20). The base's free-troposphere step,
    row 3d of ATTRIBUTION_PATH.md, is gone.
  - **The model is untouched.** `ta` and `rhoa` are bit for bit the base's at
    all 25 hours (criterion 3, the run half).
  - **The tags stay close to the base's.** Pointwise the prototype's tags
    differ from the base's by at most 1.7% at 24 h (L∞; L1 0.4 to 0.8%), and
    their column integrals by under 1e-3. The tags still diffuse as tracers,
    and the correction moves only the net mismatch, so provenance still
    mixes as under the base. That is unlike C1c's options, whose tags differed
    by 67 to 132% (E60). `mp` stays zero in both: under 1M the microphysics
    only removes energy on this column.
  - **The repair is unchanged:** 0.83 J/m² moved, as in the base.

What makes the remaining 267 J/m² is not yet split. The ledger that splits it
(`e_src_inc_left`, `e_src_inc_moved`) is built and runs in `g1_inc_d4`.
*Job `13504818` on terrabyte, `hpda2_test`, 2026-09-19, from the frozen
worktree `../ClimaAtmosResiDyn-inc-run` at `35042f33`. The outputs are in
`output/inc_d4_enthalpy_increment/`, with `compare_base.txt` and
`tags_against_base.txt` from `analysis/increment/d4_compare.py` and
`tag_correctness.py`.*

**E63. On a sphere the process records were advected with the air.** Two loops
select their fields by `is_tracer_var`, not by `gs_tracer_names`: the
horizontal advection of tracers (`advection.jl:121`) and the SEM limiter
(`limited_tendencies.jl:88`). `is_tracer_var` excludes only `ρ`, `ρtke`,
energy, momentum and SGS names, so the records `prc_e_*` and `prc_q_*` passed.

  - **Measured on the smallest sphere of the test suite** (2 elements, 4
    levels, moist baroclinic wave, 0M), with a record set to `ρe_tot` so that
    it varies horizontally. The horizontal tracer advection alone, into a
    zeroed tendency, moved it by up to 2.6 J m⁻³ s⁻¹ on the code before the
    fix. With the fix the record's tendency is exactly zero, and `ρq_tot`'s is
    not.
  - **What it touched:** every record on every sphere run, pointwise. The
    global integral is kept, because the advection is in flux form, so form B
    closed on the spheres (C7, C9). Columns have no horizontal advection and
    are unaffected, and so is every other field: the records feed back into
    nothing.
  - **The fix** excludes the records from `is_tracer_var`
    (`is_process_record_var`, the `prc_` prefix): draft PR #93, with a unit
    test. It must merge before V2, which writes the 3-D records. The
    prototype's ledger fields, `e_src_inc_*`, need the same exclusion before
    the sphere.

*Jobs `13504847` (fixed, `claude/process-records-not-advected` at
`61d8dc3d`) and `13504848` (the prototype at `faa98974`, which has `main`'s
loops) on terrabyte, `hpda2_test`, 2026-09-19. The script is
`analysis/increment/sphere_record_advection.jl`.*

**E64. The prototype's remainder on D4 is the one-iteration solve's column
totals, less what the loss rule flushes. No process the tags miss shows above
1 J/m².** `g1_inc_d4` reruns E62 with the ledger (`c0bc637f`) and gives the
same residual to nine digits, 266.942 J/m² at 24 h, with `ta` and `rhoa` bit
for bit the base's. The ledger's `e_src_inc_left` is what the correction leaves
out of the tags; `other = e_src_res − e_src_inc_left` is everything else.

| 24 h, J/m², signed (gross) | below 550 m | 550 to 800 m | above 800 m | column |
|:-- | --:| --:| --:| --:|
| residual `e_src_res` | +117.6 (143) | −97.8 (103) | −20.3 (20) | −0.5 (267) |
| left in place by the correction | +117.8 (144) | −142.3 (148) | −21.0 (21) | −45.5 (313) |
| other | −0.24 | +44.5 | +0.76 | +45.0 (46) |
| the loss rule's flushing, predicted | −0.24 | +43.5 | +0.73 | +44.0 |

  - **The column-total part** is what the correction cannot move within a
    column: the part of the parent's implicit increment that changes the
    column's total and that the tags' own implicit tendencies do not take. It
    is 313 J/m² gross at 24 h. It lands in `e_src_res` as it is made.
  - **It comes from the one-iteration Newton solve.** With ten iterations to a
    relative tolerance of 1e-8 (`g1_inc_newton_d4`) the whole residual is
    0.080 J/m² at 24 h, and `left` 0.094. Nearly all of that is made in the
    first hour, and the rest flushes it slowly. So with one iteration the
    parent's linearised increment changes the column's total by terms the
    tags' own tendencies, taken at the stage's first guess, do not have. The
    candidates are the implicit terms that change a column's total: the
    energy that sedimentation carries through the surface, and the 1M
    sink. They are not separated.
  - **`other` is the loss rule acting on the residual.** The rule removes
    `R/E` of each loss from the residual, whatever made it, and the ledger is
    not flushed. Predicted from the hourly records it gives 98% of `other` in
    the cloud layer, where the losses are fastest, and matches the other two
    layers to 0.03 J/m². The same holds in the converged twin (−0.0113
    predicted against −0.0122 J/m² in the cloud layer). What is left, about
    1 J/m², is made in the first hour, where the hourly prediction starts from
    zero.
  - **No explicit process the tags miss is visible:** outside the loss rule,
    under 1 J/m² in a day.
  - **The correction moves much more than it leaves:** `e_src_inc_moved` is
    3.3e7 J/m² gross at 24 h, up to 81,000 J/kg in the lowest cell. That is
    the vertical transport the tags take from the increment and not from
    their own tendencies: all of the grid-mean vertical advection, which
    they no longer share by tendency, and the difference between their
    tracer diffusion and the parent's diffusion of `h_tot`.

So G1's criterion 2 is met. The parts, with their sizes at 24 h: the
one-iteration column totals, 313 J/m² gross and −45.5 signed; the loss rule's
flushing of them, +44 J/m²; and nothing else above 1 J/m².
*Jobs `13504889` (`g1_inc_d4`) and `13504890` (`g1_inc_newton_d4`) on
terrabyte, `hpda2_test`, 2026-09-19, from `../ClimaAtmosResiDyn-inc-run2` at
`c0bc637f`. The outputs, with `remainder_split.txt` from
`analysis/increment/remainder_split.py`, are in `output/g1_inc_d4/` and
`output/g1_inc_newton_d4/`.*

**E65. In Float32 the prototype closes D4 to 607 J/m², 2.3 times its Float64
residual, with the model bit for bit.** `g1_inc_d4_float32` against
`g1_base_d4_float32`, the same configuration under `enthalpy` in Float32.

| gross residual, J/m² | 1 h | 4 h | 12 h | 24 h |
|:-- | --:| --:| --:| --:|
| base, `enthalpy`, Float32 | 1.68e5 | 3.12e5 | 5.19e5 | 7.53e5 |
| prototype, Float32 | 120 | 222 | 439 | 607 |
| prototype, Float64 (E62) | 92.8 | 112 | 192 | 267 |

  - **G1's criterion 5 is met.** 607 J/m² is within ten times the Float64
    residual (2,670). The first 12 hours add 437 and the second 168. `ta` and
    `rhoa` are bit for bit the Float32 base's at all 25 hours.
  - **The split:** `left` is 408 J/m² gross (−363 signed). `other` is 455
    gross (+52 signed), and unlike in Float64 it does not follow the loss
    rule: +54, +82 and −84 J/m² in the three layers against a predicted
    +0.02, +42.5 and +1.6. Its size fits Float32 rounding: about 0.5 J/m²
    per cell and step in the tags' updates, which a random walk over 720
    steps and 30 levels takes to a few hundred J/m². Inferred from its size,
    not separated.
  - **The ledger agrees with itself:** the audit's `increment_left`, −363.2
    J/m², equals the integral of the field.

*Jobs `13504891` (prototype, `c0bc637f`) and `13504828` (base, `main` at
`50b2a4d2`, from `../ClimaAtmosResiDyn-c1c-base`), terrabyte, `hpda2_test`,
2026-09-19. The outputs are in `output/g1_inc_d4_float32/` and
`output/g1_base_d4_float32/`.*

**E66. Per tag, the prototype's error from its one-iteration solve is 0.1%
for the region tags and 1 to 6% for the source tags. Against a reference that
shares each flux by its donor, the tags differ by far more, and that
difference is the mixing convention, not an error.** G1's criterion 4, on D4
for a day.

The reference is C1c's option 1 with a converged solve: every implicit flux of
`E` shared among the tags at the tendency level, at the solved state, each by
its own donor. Its first version stopped Newton at a relative tolerance, whose
norm spans the tags, so its twin under the prototype took other iteration
counts and the two atmospheres differed by up to 4 K. With ten iterations,
fixed, `g1_ref_newton10_d4` and `g1_inc_newton10_d4` have `ta` and `rhoa` bit
for bit at all 25 hours.

| per tag at 24 h | `rad` | `sfc` | `sub` | `strat` | `tropo` | `new_strat` | `new_tropo` |
|:-- | --:| --:| --:| --:| --:| --:| --:|
| against the reference, L1 | 0.68 | 1.26 | 1.17 | 0.12 | 0.08 | 0.97 | 1.03 |
| against the reference, integral | −3.2% | −2.4% | +18% | +3.4% | −2.5% | +12% | −2.0% |
| one iteration against converged, at 1 h, L1 | 0.010 | 0.056 | 0.046 | 0.0011 | 0.0014 | 0.034 | 0.047 |
| one iteration against converged, at 1 h, L∞ | 0.014 | 0.12 | 0.038 | 0.0051 | 0.0059 | 0.023 | 0.12 |

`mp` is zero in every run (E62).

  - **The reference mixes no provenance where the net flux is small.** At 24 h
    it holds `sfc` at 63,080 J/kg in the lowest cell and almost none above 475
    m, and `strat` at 0.04 J/kg at 25 m. The prototype's tags still diffuse as
    tracers: `sfc` is near 12,000 J/kg from the surface to cloud top, and
    `strat`, the air above the inversion, is 4,700 J/kg at the surface. The
    boundary layer is well mixed, so the prototype's profiles are the
    physically expected ones. The reference's are what E60 described for a
    share of the net diffusive flux. So the first two rows measure the mixing
    convention (ATTRIBUTION_PATH.md, sections 3.4 and 3.5). The reference
    also leaves 5.99e5 J/m² of its own residual, so it is not closed either.
  - **The solve's effect is measured on the prototype itself.** A one-iteration
    and a converged run cannot share an atmosphere. But at 1 h they still
    nearly do: `ta` within 0.04 K, and `E` within 2.5e-4 in L1. The tags then
    differ 4 to 200 times more than `E` (rows 3 and 4). That is the effect of
    the one-iteration solve on the split among the tags, since the partition's
    sum follows the parent either way. Later the two atmospheres drift apart,
    by up to 0.85 K and 5.8e-3 of `E` at 12 h, and the tags with them: 0.5 to 2%
    for the region tags and up to 28% (`sfc` at 12 h) for the source tags
    (`output/inc_d4_enthalpy_increment/tags_against_converged.txt`).
  - **The converged prototype closes to 0.0016 J/m²** at 24 h with ten fixed
    iterations, and 0.080 with the tolerance (E64). What is left is still the
    column totals the correction leaves.

**The proposed threshold,** for the owner to confirm. A convention cannot be
thresholded as an error, so the per-flux reference sets none. The threshold is
on the solve instead, against the prototype's own converged twin at 1 h, with
about twice the room the numbers need: L1 at most 1% for the region tags and
10% for the source tags, and L∞ at most 25%. Today 0.14%, 5.6% and 12%.
Which mixing convention is right is a question for question 2 of the
attribution path. The measurement that would settle it is the passive-tracer
twin V3 (ATTRIBUTION_PATH.md, section 5): a tracer with an updraft copy, set
to the surface or a region, beside the tags.
*Jobs `13504926` (reference, `../ClimaAtmosResiDyn-c1c-opt1` at `9aeb5205`)
and `13504927` (prototype, `c0bc637f`), terrabyte, `hpda2_test`,
2026-09-19. The tables are `output/g1_inc_newton10_d4/tags_against_reference.txt`
and `output/inc_d4_enthalpy_increment/tags_against_converged.txt`, from
`analysis/increment/tag_correctness.py`.*

**E67. Under a deep atmosphere the correction put 0.4% of each cell's move in
the wrong place, until its flux was scaled by the face areas.** The column
integrals are per unit area of the bottom face, and the divergence weights each
face by its own area. On a sphere with a deep atmosphere, the default, the
faces grow with height: on the smallest test sphere, 30 km deep, the top face
is 1/0.9906 times the bottom one.

  - **Measured with a set increment** on that sphere (2 elements, 4 levels, 0M,
    one step), as in the integration test's first item. Each cell's partition
    change is set against the part the ledger says was moved. Before the fix
    they differ by up to 4.7e-6 J/m³, 0.41% of the move. After it, by 2e-11,
    the rounding of totals of about 1e5.
  - **Where it would have gone:** into `e_src_res`, every stage, with the sign
    of the transport. The column totals were right, since the flux is zero at
    both ends.
  - **The fix** scales the flux by the bottom face's area over each face's own,
    kept in the cache (`04d63916`, on #94). On a flat grid the ratio is 1, so
    G1's columns are unchanged. It was the previous review's F7 and this
    review's S4.
*Jobs `13504953` (fixed, the prototype's worktree) and `13504956` (`c0bc637f`,
from `../ClimaAtmosResiDyn-inc-run2`), terrabyte, `hpda2_test`, 2026-09-19.
The script is `analysis/increment/sphere_increment_deep.jl`.*

**E68. V3: the tags' mixing against the air's own on D4. The updraft moves
boundary-layer air to the inversion that the tags leave behind, and after a day
the tags hold 7.0% air from above the inversion where the air holds 10.1%.**
V3, approved by the owner on 2026-09-19: D4 under the prototype with
`chemistry_model: passive`. Its tracer `q_gas_A` has an updraft copy. Before
the solve the driver sets the tracer and its copy to the mask of the region tag
`tropo`. The ratio `ψ = tropo/(tropo + strat)` starts equal to it. The loss rule
and new production leave `ψ` as it is, and subsidence moves neither. So only
transport, mixing and the repair change them.

| hour | L1 of `ψ − q_gas_A` | largest difference, and where |
|--:|--:|:--|
| 1 | 7.8% | −0.58 at 775 m, the inversion cell |
| 3 | 6.6% | −0.27 at 775 m |
| 6 | 3.9% | +0.08 at 25 m |
| 24 | 3.2% | +0.04 at 875 m |

  - **The model is untouched:** `ta` is bit for bit `g1_inc_d4`'s, and the
    closure residual is the same to every digit, 266.94240759 J/m² at 24 h.
  - **In the first hours the updraft is the difference.** At 1 h the updraft
    carries air that is 99% from the boundary layer up to 725 m. The tracer at
    the inversion then holds 58 points more boundary-layer air than the tags,
    whose updraft share is the grid mean's (UPDRAFT_GAP.md).
  - **After a day the boundary layer is mixed,** and the updraft's tracer
    equals the grid mean's (0.8994 against 0.8993). What remains is a uniform
    offset through the layer: the tracer has 10.1% air from above the
    inversion, and the tags 7.0%. The tags take in about a third less of the
    entrained air.
  - So on this column the updraft gap is large for hours at the inversion, and
    leaves a lasting error of about 3 points of share in the boundary layer.
*Job `13505756` on terrabyte, `hpda2_test`, 2026-09-19, from
`../ClimaAtmosResiDyn-inc-run3` at `04d63916`, with
`analysis/increment/v3_driver.jl`. The outputs and `compare_tracer.txt` from
`analysis/increment/v3_compare.py` are in `output/v3_d4_passive_tracer/`.*
*Erratum, 2026-09-19: the premise is wrong. The region tags `strat` and
`tropo` have no sources, so they take every source's gain by their mask
(`tag_receives_source` is true for an empty list), while a loss takes from
every tag in proportion. So new energy in the boundary layer goes to `tropo`,
and `ψ` rises above the tracer even with the air's own mixing. `ψ − q_gas_A`
is the updraft gap plus that attribution. With updraft copies of the tags
(E73) the gap in the boundary layer is 0.3 points at 6 h, and 1.3 points at
24 h, most of it the attribution. The size of the updraft gap alone is the
tags without copies against the tags with them (E73).*

**E69. With one Newton iteration, V2's model top collapses to the 150 K floor
within 6 h; two iterations prevent it. And on the sphere the residual is not
the solver's.** V2 (`g2_v2_sphere`) is the production physics on a sphere under
the prototype: EDMF with the updrafts' vertical diffusion, implicit eddy
diffusion, both sponges, a DCMIP200 mountain, 1M, Float32, 10 levels to 30 km,
dt 20 s, 24 ranks.

| top level (27 km), mean | 1 h | 2 h | 3 h | 6 h |
|:--|--:|--:|--:|--:|
| V2, one iteration | 216.2 K | 205.1 | 190.1 | 156.0, 18% at the floor |
| without sponges | 216.2 | 205.1 | 190.1 | |
| without the mountain | 215.5 | 203.1 | 188.7 | |
| two iterations | 219.3 | 218.9 | | |
| ten iterations (the twin) | 219.3 | 218.9 | 218.7 | 218.5 |

  - **The one-iteration solve alone makes the collapse.** Radiation warms that
    level by about 0.05 K an hour in both V2 and the twin. So the cooling of 4
    to 15 K an hour is the implicit dynamics' under one iteration. Turning off
    the sponges changes nothing to the printed digit, and removing the
    mountain little. With two iterations the level holds what ten give. From
    12 h on the whole top level of V2 sits at the floor, and the level below
    settles near 198 K.
  - **It is the model's own.** The tags feed back into nothing, and `E` stays
    positive. The first V2 is kept as a record of the tags' bookkeeping over
    ten days on that atmosphere, with this caveat on every reading. V2 runs
    again with two iterations, `g2_v2_sphere_n2`.
  - **On the sphere the converged twin does not close better:** 2.78e-5 of
    the scale at 24 h, against 2.45e-5 with one iteration. On D4 the converged
    solve took the residual to 0.0016 J/m² (E66). So the sphere's residual is
    not the one-iteration solve's. It is the explicit processes the tags do not
    yet follow, and Float32: step 3 of the attribution path.
  - **The twin cannot measure the per-tag error of one iteration here.** The
    atmospheres differ by 4 K at the top already at 1 h, and the tags with
    them (region tags 0.1% in L1, source tags 4 to 10%). The two-iteration
    rerun, whose top follows the twin's, is the one to compare.
*Jobs `13504999` (V2), `13505000` (the twin, a day), `13505762` to
`13505764` (the three-hour variants), terrabyte, 2026-09-19, from
`../ClimaAtmosResiDyn-inc-run3` at `04d63916`. The outputs are in
`output/g2_v2_*`.*

*Erratum, 2026-09-19: the third point's explanation is wrong. With two
iterations the sphere's residual is Float32 rounding alone (E70).*

**E70. On the sphere, V2's residual is Float32 rounding. The explicit
processes and the sponges add nothing measurable.** Two hours of
`g2_v2_diag_newton2` (two iterations, one process) were run again: once in
Float64, and once in Float32 without the sponges.

| gross residual, of the scale | 0 h | 1 h | 2 h |
|:--|--:|--:|--:|
| Float32, two iterations (`g2_v2_diag_newton2`) | 1.0e-8 | 2.36e-6 | 3.85e-6 |
| the same without the sponges | 1.0e-8 | 2.34e-6 | 3.87e-6 |
| the same in Float64 (`g2_v2_f64_2h`) | 2.6e-17 | 3.6e-15 | 5.7e-15 |

  - **Float64 closes to rounding.** It has the same explicit processes as
    the Float32 run, so none of them opens the closure. The correction's
    column totals fall with it: 1.5e-15 of the scale in Float64 against
    6.6e-7 in Float32. What the correction moves is the same in both
    (1.57e-3 of the scale in 2 h), so the moves are the implicit channel's,
    and only what is left over is rounding.
  - **The sponges' share is nil.** The two Float32 runs agree to 1%.
  - **So E69's twin closes no better because it too is Float32.** V2's
    one-iteration column totals, 16% of its gross at ten days, are not
    decided by this run: on D4 in Float64 they are real (E64), and a Float64
    run with one iteration would tell for the sphere.
  - **V2's ten days, as it ran** (one iteration, with the collapsed top of
    E69; `output/g2_v2_sphere/v2_sphere_analysis.txt`). The gross residual is
    2.45e-5 of the scale at 1 day, 9.4e-5 at 5 and 1.58e-4 at 10. The second
    five days add 2.85e19 J, the first 4.07e19, so it slows. The loss rule
    flushes it at 0.011 to 0.015 a day, a time of about 70 days. At day 9 it
    stands at a seventh of where that rate would level it off (`G*/G` 7.0).
    About 30% of `|R|` sits above 10 km and 26 to 38% below 2 km. The
    correction moved 1.6 times the scale gross over the ten days, and the
    repair 4.9%.
*Jobs `13509165` (Float64) and `13509166` (no sponges), `hpda2_test`,
terrabyte, 2026-09-19, from `../ClimaAtmosResiDyn-inc-run3` at `04d63916`.
The outputs are in `output/g2_v2_f64_2h` and `output/g2_v2_nosponge_2h`.*

**E71. Doubling the offset `c` leaves the model bit for bit and nearly
doubles the prototype's remainder on D4. The source tags change by 4 to 6%
in a day (ATTRIBUTION_PATH.md's V5).** `g1_inc_d4_2c` is `g1_inc_d4` with
`c` = 220,990 J/kg. `ta` and `rhoa` are `g1_inc_d4`'s bit for bit.

  - **The remainder scales with `c`:** 509 J/m² gross at 24 h against 267
    (368 in the first 12 h, 141 in the second). Written as `A + c·B`, about
    90% is `c·B`. So the one-iteration column totals of E64 are mostly
    `c` times a change of the column's mass that the tags' tendencies do not
    have. This fits E64's two candidates, sedimentation through the surface
    and the 1M sink, which both change the mass.
  - **The shares are a convention, and the tags depend on it.** Against the
    run with `c`, in integral at 24 h:

    | `rad` | `sfc` | `sub` | `new_strat` | `new_tropo` | `strat` | `tropo` |
    |--:|--:|--:|--:|--:|--:|--:|
    | +4.4% | +6.3% | +4.5% | +4.2% | +6.0% | +177% | +152% |

    The initial tags grow with the partition's total, which `c·ρ` enlarges.
    The source tags keep more, because the loss rule takes each loss in
    proportion to the shares and they now hold less of it. So `c` sets the
    loss rule's memory, and a per-tag result must state its `c`.
*Job `13509167`, `hpda2_test`, terrabyte, 2026-09-19, from
`../ClimaAtmosResiDyn-inc-run2` at `c0bc637f`. The output is in
`output/g1_inc_d4_2c`.*

**E72. Over V2's nine days, the updraft gap would lift the tropical `sfc`
tag's centroid by about as much as the tag itself rises.** The estimate of
UPDRAFT_GAP.md (`updraft_gap_estimate.jl`, reviewed) run on days 1 to 9 of
V2, one iteration, with E69's caveat. It gives the initial rate at which a
tag with an updraft copy would diverge, and its days cannot be added up.

| tropics | days 1 to 4 | days 5 to 9 |
|:--|--:|--:|
| updraft top, area mean | 1.8 to 2.6 km | 2.8 to 3.4 km |
| area whose air below the top turns over in a day | 90 to 93% | 61 to 75% |
| `sfc` relocated a day, upwind to centred | 7 to 17%, 15 to 53% | 11 to 18%, 15 to 22% |
| `sfc` centroid rise from the gap, m a day, upwind to centred | 86 to 185, 158 to 507 | 137 to 261, 166 to 285 |
| `sfc` centroid's actual change, m a day | 142 to 699 | 265 to 372 |

  - Outside the tropics convection spreads after day 3: the area turned over
    in a day grows from 2 to 4% to 20 to 43%, and the centred estimate
    relocates 7 to 46% of `sfc` a day.
  - In the tropics the `new_*` tags move like `sfc` (6 to 19% a day upwind),
    and `rad` about half as much. The region tags move under 5% a day.
  - **Reading.** The gap is of the same order as the tag's own vertical
    motion, not a small correction to it. Where the surface's energy sits in
    the vertical is therefore uncertain at order one in convective regions.
    The column totals and the horizontal split are not affected
    (UPDRAFT_GAP.md). V3 measured the same on D4 (E68).
*Run on a login node from `analysis/increment/updraft_gap_estimate.jl` on
V2's daily checkpoints. The output is in
`output/g2_v2_sphere/updraft_gap_estimate_days1-9.txt`.*

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

**T7. The tag offset costs no more than the scatter.** C4's `solve! walltime` is
353.3 s at C1's offset and 355.8 s at twice it, against 345.6 s unshifted and
349.0 s for C1, all on the same node type. T2 puts run-to-run scatter at about
2%, so the second snapshot and the few extra broadcasts are not measurable
here. *C4, jobs `13384913` and `13384914` on terrabyte.*

**T8. The repair costs about 1%.** C6's `solve! walltime` is 21.47 s with the
repair on and 21.01 s with it off on the column, and 435.9 s against 431.5 s on
the sphere. First-order tag upwinding took 423.7 s. The differences, 2.2% and
1.0%, sit at T2's scatter of about 2%. *C6, jobs `13385450` to `13385454` on
terrabyte.*

**T9. On the sphere the tags cost 1.46×.** P1 is C7 under its own name against
C7 with no tags, records, check or diagnostics. The two started together on the
same node, beside MP1.

|                   | tagged   | untagged | ratio |
|:----------------- |:-------- |:-------- |:----- |
| `solve! walltime` | 445.75 s | 305.44 s | 1.459 |
| `sypd`            | 0.531    | 0.775    | 1.459 |
| per timestep      | 2.063 s  | 1.414 s  | 1.459 |
| whole job         | 18.2 min | 11.0 min | 1.66  |

  - As in T4, this is the cost of the feature as used: 7 tags, 3 records, the
    audited closure check hourly and 12 fields written hourly, against nothing.
    It does not split the tags from the check or the output. On T4's column,
    with 3 tags, it was 1.32×.
  - The build takes longer too: the whole job gains 7.2 minutes against 2.3 in
    the solve.
  - The tagged half repeats C7. Its `ta` and all five of its tables are
    identical to C7's in every value, at `c2842ba6` against `414f5f1b`, and its
    solve took 445.75 s against C7's 447.98.
  - One pair, on one node. CPU only.

*P1, jobs `13440989` and `13440990` on terrabyte at `c2842ba6`;
`output/p1_sphere_tags/` and `output/p1_sphere_notags/`,
`analysis/same_atmosphere.jl`.*

**T10. The tag and record code allocates nothing. The explicit tendency
allocates without tags, and each tag adds to it.** T3 measured `@allocated` on
a second call, on the 1M DYCOMS column in `Float64`, with an offset, 4 tags and
3 records, against the same column with none.

| call, bytes per call                        | tags and records | none   |
|:------------------------------------------- | ----------------:| ------:|
| an explicit bracket, radiation or surface   |                0 |      — |
| the implicit microphysics bracket           |                0 |      — |
| `energy_source_share_norm!`                 |                0 |      — |
| `repair_energy_source_tags!`                |                0 |      — |
| `vertical_advection_of_water_tendency!`     |                0 |      0 |
| `implicit_tendency!`                        |                0 |      0 |
| `remaining_tendency!`                       |           58,160 | 22,576 |
| `constrain_state!`                          |               32 |     32 |

  - **Where the explicit tendency allocates.** `Profile.Allocs` puts every
    allocation in shared loops over the tracers:
    `horizontal_tracer_advection_tendency!` (`advection.jl:122-123`),
    `explicit_vertical_advection_tendency!` (`advection.jl:249-253`),
    `surface_flux_tendency!` (`surface_flux.jl:126-136`), and
    `foreach_gs_tracer` (`variable_manipulations.jl:238`). None is in tag or
    record code. Records are not tracers, so the 35,584 bytes the tags add come
    from the 4 tags, about 8.9 kB each.
  - **#76's split solver** allocates nothing, in its update and its solve. The
    unsplit ClimaCore solve allocates 48 bytes per call, on the 0M column with 3
    tags.
  - The two zero-allocation sets are tests now: #78 on `main`'s integration
    files, and a check in #76's item 6. The diagnostics' compute functions,
    which run at output time, allocate 128 to 224 bytes each and are not
    checked.
  - CPU, Julia 1.11.9, without CI's `--check-bounds=yes` and coverage.

*Login node at `3b4b6056` and `7d190db1`; `analysis/t3_allocations.jl`,
`analysis/t3_allocation_profile.jl` and
`analysis/t3_split_solver_allocations.jl`.*

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
  - **The limiter as all of E16.** The discussion predicted that switching it
    off would bring the twins to rounding from the first step. It brought `ρ`
    from 3.6e-5 to 3.7e-8, and not to rounding (E16).
  - **The surface-flux code path as the rest of E16.** With the limiter off in
    both halves, switching the surface-flux tendency off as well left the
    one-step difference in `ρ` at 3.71e-8, as with it on (E16).
  - **An explicit estimate at each step's start as enough to screen the
    operators behind the residual.** The reviewer agent of §8 proposed it. Over
    the column's first ten minutes it missed the residual's change by more than
    the change itself, 346,100 against 142,700 J m⁻², gross. After those ten
    minutes it misses by 1.4% (E25).
  - **Evaluating the model's tendencies on the run's own cache between steps
    as harmless.** The first version of `transport_ledger.jl` did so, and its
    run ended in a different state from an identical run stepped plainly. The
    script now evaluates on a second simulation.
  - **That the repair would bring the audit's sphere form A back to C7's
    20 J kg⁻¹.** C10's config and E34 predicted it. With the repair on, form A
    is 274 J kg⁻¹ (E35).
  - **That subtracting the repair's ledgers gives form A without the repair.**
    E35, as first written, did so and read 54.9 J kg⁻¹, and concluded that the
    clamp is at most part of C9's gap. The ledgers are not transported, so the
    field is off by up to 22.0 J kg⁻¹ against C9, the same atmosphere without
    the repair, and by 219 under tracer transport (E35's correction,
    `analysis/formA_mechanism.jl`).
  - **That `ρ` is not hyperdiffused, so the offset adds nothing to the audit's
    hyperdiffusion.** `ENTHALPY_AUDIT_DESIGN.md`, the audit kernel's docstring
    and the sphere test's comment all said so. `hyperdiffusion.jl:495-497`
    hyperdiffuses total water and takes the same flux out of `ρ`. So `c` times
    that flux changes `E`, and the audit does not share it out. A reviewer
    found this on 2026-09-11. The fix adds `c` to the water part of the shared
    flux. It is in #72, `7a290c98`, with the owner's approval.
  - **That under the audit the tags follow the parent's vertical flux at the
    stage state rather than at the solved one.** The audit's docs section, the
    vertical kernel's docstring and `ENTHALPY_AUDIT_DESIGN.md` said so. It is
    the other way round. The tags' explicit flux is evaluated at the solved
    stage state, and the parent's side is the one-iteration Newton increment,
    linearised about the stage's initial guess (E39).
  - **That vertical diffusion's form mismatch makes D1's gross residual
    (E42).** E42 inferred it because the residual is zero-sum and spread over
    the column, where vertical diffusion acts. D1's twin without vertical
    diffusion has the same gross residual, 2.350e6 J m⁻² at 1 h against
    2.370e6, split the same way over height (E42b).
  - **That the tag code's recursion over its tuple of tags makes the EDMF build
    slow (E44c's candidate).** No tag or record function is among the methods
    whose inference grows with the tags. All of the growth is in ClimaCore's
    Jacobian solver (E44d).
  - **That solving the tags in a group of their own removes that growth.** A
    prototype that put them in the first group of a `BlockLowerTriangularSolve`
    took as long to build, because ClimaCore takes each group's complement from
    the state's name tree (E44d).
  - **That `dd06318f`'s fixes "change no simulation results".** Its commit
    message says so. One of them makes `limiters_func!` compare `:ρq_tot`
    instead of `@name(ρq_tot)` with `vertical_water_borrowing_species`. With an
    explicit species list, the fork now runs `enforce_mass_energy_consistency!`,
    which writes `ρ` and `ρe_tot`, and upstream `v0.42.9` skips it. So in that
    configuration the fork's atmosphere differs from upstream's. Read from the
    code on 2026-09-14, not run (to-do list, decision 12).

## 7. What is not established

  - ~~The energy family's mass-weighted non-positive fraction (M1).~~ Settled:
    0.7839 on `c0_sphere_audit` (E9b).
  - ~~Whether `p_sat` is in fact invariant under R6's map.~~ Settled in
    Thermodynamics: over liquid, over ice and over the mixture ramp it is
    unchanged to 9.2e-16 from 150 K to 330 K (R8). Whether the *model* is
    invariant is the next item.
  - **What is left of E16 once the limiter is off.** 3.7e-8 in `ρ` after one
    step, growing to 5.8e-6 by 5 h. It is not the surface-flux code path
    (E16). What starts it is open. Since the offset of E17 leaves the model
    alone, nothing in the tags depends on it.
  - **Why a tag goes negative under a positive parent (E14).** The finite-step
    donor loss and unlimited explicit transport are both candidates. On an
    identical atmosphere the region tags' minima scale with the offset while
    the source tag's barely move (E19), which points at transport for the
    region tags.
  - **What makes the residual's first-minute jump (E13, E25).** After the first
    ten minutes, pressure work is the whole of the residual's growth on the
    column (E25). The first minute is too fast for an estimate at each step's
    start. A ledger weighted by the stepper's own stages would split it.
  - **Why C5's radiation tag outgrows C3's after four hours (E24).** The
    atmospheres agree, the loss only removes, and both runs move tags with the
    van Leer limiter. The runs differ in machine and in code.
  - ~~Whether the sphere's per-process gap is the per-tag limiter or the clamp
    (E20).~~ Neither: it was the rain-out's production (E28), and a
    `microphysics` tag closes it to 20.2 J kg⁻¹ (E30).
  - ~~What the sphere's last per-process gap is (E30).~~ Under tracer
    transport, the per-tag van Leer limiter, with a small part from the loss
    clamp (E37).
  - ~~What the 1M column's last signed residual is (E32).~~ The loss rule
    acting on the residual that tracer transport makes. It is not the tags'
    missing Jacobian block, whose lag is −7.8 J m⁻² (E39).
  - ~~How much provenance sedimentation's upward branch moves in a run (E32,
    E41, E42).~~ On D1's column, about a fifth of what `lower` gained above its
    boundary in the hour; vertical diffusion moved the rest (E42b). Where ice
    persists, as in deep convection, it is open. D5 would keep making ice.
  - **What makes D1's gross residual (E42, E42b).** A zero-sum 3.7e-3, spread
    over the column, and not vertical diffusion. Pressure work in the grid-mean
    vertical advection, as on the DYCOMS column (E25), is the next candidate. A
    twin with the tags moved as enthalpy would test it.
  - **Anything under `prognostic_edmfx` (E40).** The tags get no sub-grid mass
    flux and no sedimentation corrections, and the shipped settings fail. How
    much that adds to `e_src_res` in a run is what the D4 pair would measure,
    with `edmfx_vertical_diffusion: false`.
  - **2M and P3.** The model disables both on this branch (E41). By the code,
    the tags need nothing more for 2M than for 1M. Behind that gate, P3 has
    gaps in the parent's own sedimentation (`SUBGRID_AND_MICROPHYSICS_DESIGN.md`).
  - ~~What C8's form-A gap is (E33).~~ The per-tag transport. Moved as
    enthalpy, C8's column keeps form A below 4.4e-7 J kg⁻¹ for a day. Form B's
    remainder is the one-iteration Newton increment, and a converged solve
    takes it to −3.8e-3 J m⁻² (E43).
  - **Whether the audit's transport clamp is the whole of its form-A gap on
    the sphere (E36).** A negative overlay freezes at its node while its
    neighbours' shares keep pushing it. That the clamp is the only cause is
    inferred from the code. A C9 twin with signed shares for the overlays would
    decide it.
  - ~~What makes the audit's first-hour residual (E34).~~ The one-iteration
    Newton increment during the initial adjustment. A converged solve removes
    99% of it on the column (E39) and 83% on the sphere (E39b).
  - **What the sphere's converged 17% is (E39b).** 4.24e19 J at 1 h, made in
    the first step, and nearly flat after it.
  - ~~How the column's unrecorded 1.37 MJ m⁻² splits (E23).~~ Subsidence's
    −1,277,826 J m⁻² and the rain-out's −87,651, to the joule (E26).
  - ~~What the column's last per-process gap is (E26).~~ The tags' per-tag
    transport. Moved as enthalpy, the same column's form A closes to
    6.6e-6 J kg⁻¹ (E34).
  - ~~**Where the repair's large ledgers sit on the sphere (E27),** and whether
    that is where the two region tags meet, as the undershoots of E19 would
    place them.~~ Just beyond the edge where they meet, one to two rows out on
    each side, with each tag lifted only beyond its own edge (E46). Whether a
    wider mask removes them is open.
  - ~~`Float32` on a sphere (W4).~~ Settled for a day on C7's sphere: it
    closes as `Float64` does, to rounding (E45). Longer runs, the audit, 1M
    and a GPU in `Float32` are still open.
  - ~~Whether 1M changes the residual (W5).~~ Settled on a column: 7% down
    (W5b). A sphere, which reaches the horizontal branches, is still open.
  - ~~The tag cost on anything but one column on one node (T4 bounds it at
    1.32× there).~~ Measured on C7's sphere too: 1.46× (T9). On a GPU, and
    under EDMF once it builds, still open.
  - ~~Whether C1's suppression cost (R11) matters in practice.~~ Measured on
    C4: doubling the offset moves the source tag by about 1% over a day (E19).
    What it does move is the region tags' negativity.

## 8. Next

 1. **Done: the shift inside the tag code, not the model** (E17 to E19).
    `energy_source_tag_offset` is in the model, and future runs of this family
    should use it rather than a moved reference. What it does, as designed: the
    tags partition a shadow total `E = ρe_tot + c·ρ`, with `c` a fixed energy
    per kilogram of air, 110.5 kJ kg⁻¹ to match C1. The model never sees `E`, so
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

 2. **Stopped: the rest of E16.** The limiter is most of it, and the
    surface-flux path is not the rest (E16). The owner took up no further twin
    on 2026-09-10, because item 1 leaves the model alone.

 3. **Decided: keep both.** On 2026-09-10 the owner decided to keep the energy
    source tags, and made keeping both them and the process record the main
    goal. They answer different questions: the tags say where the energy
    present came from, and the record says what each process did (E9). The
    offset makes the tags' donor rule run everywhere without touching the model
    (E17). What is left before the tags are operational is task 1b of the task
    list.

    **Built on the same day, in the order the owner set: the bracket, then the
    repair.** The owner approved both, and a switch for the repair, on
    2026-09-10.

      + The implicit microphysics sink is bracketed for the source tags and the
        process records. That is where a 0-moment run loses its rain. The
        records also take sedimentation from the implicit path. The source tags
        do not: sedimentation moves energy between levels, and a bracket would
        count what arrives as new energy.
      + `energy_source_tag_repair`, on by default and switchable off, keeps the
        tags non-negative where their total is positive. The partition tags
        keep their sum, the tags that carry a source are clipped at zero, and
        every change goes to `e_src_fix_<name>`.

    `analysis/bracket_repair_smoke.jl` runs both on a DYCOMS column for two
    minutes at 50 kJ kg⁻¹:

      + the microphysics record is −568 J m⁻², where it was zero;
      + the model's state is bit for bit the same with and without the repair;
      + the repair clipped the radiation tag's −2.9e-9 to zero;
      + the column's signed residual at 120 s went from −744 J m⁻², the tags
        overclaiming, to +382 J m⁻². So the tags no longer overclaim. A smaller
        untagged remainder of the opposite sign is left, which this run does
        not explain.

    **Under discussion: enthalpy-form transport of the tags, as an audit.** The
    owner proposed passive tracers as the default, and enthalpy-form transport
    as an audit. A reviewer agent mapped every transport term. Its reading of
    C4 is that more than 99% of the gross residual is balanced operator-form
    terms, pressure work first. That is an inference, not a measurement. Its
    recommendation:

      + first measure each operator's share of the residual with a script and
        no model change, `analysis/transport_ledger.jl`, which is not written;
      + build a per-run switch only if pressure work and the per-tag limiter
        explain most of the residual. The switch would use a flux-share
        vertically, where each tag carries the parent's energy flux times its
        upwind share, and an enthalpy-like specific value horizontally;
      + reckon on about 500 lines of model code and 300 of tests.

    **Measured on the column: pressure work is the residual's growth.** After
    the column's first ten minutes, pressure work accounts for 72,260 of the
    72,000 J m⁻² the residual moved in 50 minutes, and the per-tag limiter for
    268 (E25). That meets the agent's rule for building the switch, on the
    column.

    **Measured on the sphere: the same, horizontally as well.** Pressure work,
    vertical and horizontal together, is at least 93% of the residual's growth
    over five hours, the per-tag limiter 2e-4 and hyperdiffusion 2.4% (E31).
    That meets the rule on the sphere too. The horizontal pressure part is half
    the vertical one, gross, so the switch needs both halves. The owner approved
    building it after C6, once the sphere was measured.

    It also found that the implicit bracket evaluates the tags' loss at the
    Newton iterate with no Jacobian block of its own. For energy that is a small
    fraction of the total per step, but a block like the water tags' would make
    it backward Euler.

    **Assessed: sedimentation as transport of the source tags.** The owner
    asked whether falling precipitation could move the source tags, as it
    moves the water tags. A second reviewer agent found it viable, and needed:

      - under 1M, 2M and P3, sedimentation is the only way precipitation
        energy leaves the atmosphere, and the source tags receive none of it,
        not even the loss at the ground. Under 0M there is none, so no run of
        this series changes;
      - the design is the water tags' flux-share. Each tag's face flux is the
        parent's sedimentation energy flux, plus `c` times the mass flux, times
        the donor cell's share, normalised by the partition sum for the region
        tags;
      - it needs an offset. It also needs the donor chosen by the sign of the
        energy carried: at `c` = 110.5 kJ kg⁻¹, falling ice carries about
        −200 kJ kg⁻¹ by the agent's estimate;
      - exact closure within a step needs a Jacobian cross block to the rain.
        Without one a bounded lag remains;
      - about 450 lines of model code and 250 of tests. A 1M column tests it,
        but does not reach ice.

    That is an assessment, not a measurement. The owner approved building it
    after C6.

    **Built: sedimentation as transport of the source tags** (`91b9bbb9`). It
    follows the agent's design, without the Jacobian block:

      + `sediment_energy_source_tags!` runs in
        `vertical_advection_of_water_tendency!` for each sedimenting species,
        on the parent's energy flux plus `c` times its mass flux;
      + each face takes the shares of the cell that loses the energy. That is
        the cell below where the energy flux points up while the water falls;
      + the partition tags' shares are divided by their sum, so their fluxes
        add up to the parent's at every face;
      + without an offset it warns at initialization.

    The tests check the flux sum on a 1M column to 100 eps, and the donor in
    both directions on a step partition. They pass on this branch and on #69's.
    Run twice for an hour on a 1M column, with the tags moved and without, the
    column's signed residual is 15 times smaller with them (E32). A day of the
    same column keeps both per-process checks, less tightly than at 0M (E33).
    It is about 270 lines of model code with docstrings, and 140 of tests, and
    it is draft PR #70, which, like #69, now targets `main`.

    **Built: the enthalpy audit switch** (`511e00e9`), as
    `ENTHALPY_AUDIT_DESIGN.md` designs it, with the owner's four decisions. The
    key is `energy_source_tag_transport`, `tracer` by default or `enthalpy`.
    `enthalpy` is refused without an offset, covers vertical and horizontal
    advection and hyperdiffusion, and uses the parent's
    `energy_q_tot_upwinding` vertically. The tests check each of the three sums
    against the parent's to 100 eps, on the column and on a two-element sphere.
    They also check the upwind donor both ways, and that the model's state is
    untouched. It is draft PR #72, stacked on #70.

    **Run: C9, the audit on the column and the sphere** (E34). After the first
    hour the closure residual stops growing. At 24 h it is 1,069 times smaller
    than under tracer transport on the column and 11 times smaller on the
    sphere, with `ta` identical, for 5% more per step. On the column form A
    closes to 7e-6 J kg⁻¹. On the sphere it worsens where the source tags go
    negative with the repair off. The same sphere with the repair on would test
    that.

    **Run: C10, and where form A's gaps come from** (E35 to E38). The repair
    does not bring the audit's form A back. Under the audit a negative overlay
    freezes at its node. Under tracer transport the gap is the per-tag limiter.
    Form A's global integral, not its largest gap, shows a missing process.
    The audit's first-hour residual and C8's form-B remainder are the stepper's
    one Newton iteration (E39).

    **Designed: the tags under EDMF, with ice, and under 2M and P3**
    ([SUBGRID_AND_MICROPHYSICS_DESIGN.md](SUBGRID_AND_MICROPHYSICS_DESIGN.md),
    E40, E41). The owner asked for it on 2026-09-11. It recommends refusing
    `prognostic_edmfx` with tags now. Then one PR would share the parent's
    sub-grid flux of `E` and each species' whole sedimentation flux by the
    losing cell's shares, and guard the shared tracer loop. It leaves seven
    decisions to the owner. Its configs are D1 to D5. D1 ran (E42, E42b), and
    the D4 pair timed out before it stepped (E44). A user
    guide is drafted beside it, [USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md).

    **Listed: what is left before operation**, in
    [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md). The GPU comes last, by the
    owner's decision of 2026-09-11.

 4. **Phase B.** B1 ran once, as the owner decided on 2026-09-17 (E50): 7% of
    the gross after ten days, and 63 minutes of solve. The split B1a to B1c,
    B2 and B3 have not run and are not approved.

 5. **C2.** Built: the implicit-path brackets are in #69. This is not the
    restart guard that `OPERATIONAL_TODO.md` also calls C2.
