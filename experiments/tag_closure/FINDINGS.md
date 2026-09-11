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
    found this on 2026-09-11. The fix is to add `c` to the water part of the
    shared flux, in #72, and it waits for the owner.
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
  - **Where the repair's large ledgers sit on the sphere (E27),** and whether
    that is where the two region tags meet, as the undershoots of E19 would
    place them.
  - `Float32` on a sphere (W4).
  - ~~Whether 1M changes the residual (W5).~~ Settled on a column: 7% down
    (W5b). A sphere, which reaches the horizontal branches, is still open.
  - The tag cost on anything but one column on one node (T4 bounds it at 1.32×
    there).
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
    decisions to the owner. Its configs are D1 to D5, and none has run. A user
    guide is drafted beside it, [USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md).

    **Listed: what is left before operation**, in
    [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md). The GPU comes last, by the
    owner's decision of 2026-09-11.

 4. **Phase B.** No technical objection left after W9 — B1 configures no limiter
    and the energy family has no rescale. C1 solved a simulated day in 5.8
    minutes on this grid, so ten days is about an hour of solve if B1 runs at
    that speed, which fits `hpda2_test`'s two-hour limit. Whether it is worth
    running is the owner's call.

 5. **C2.** Unchanged: needs a code change and approval.
