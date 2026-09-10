# Learnings

The barrier register for the tag-closure experiments. One entry per run, added
by the agent after the owner has committed that run's files under `output/`.

This file is the point of the series. The runs exist to find which practical
barriers stop the source-tag method in a real simulation, so that the decision
named in [the source-tag page](../../docs/src/energy_source_tags.md) — whether
to use energy source tracing at all, or to combine water source tracing with the
energy process record — is taken on measurements rather than on argument. A
number that is not written down here has not been learned.

## What every entry answers

  - **What barrier did the run show, if any.** A run that showed none says so,
    and that is a result. Name the quantity and its value, not an impression.
  - **Is the barrier numerical, structural or a cost.** Numerical is a residual,
    a negative tag, a non-positive parent, a `Float32` floor. Structural is a
    process that no bracket covers. A cost is walltime, memory or Jacobian size.
  - **Does it carry over to the source tags.** The source tags ride the same
    passive-scalar path as the energy tags and get no corrections at all, so a
    barrier measured on the water or energy families is usually a floor for
    theirs rather than a separate finding. Say which it is.

A crash is a barrier like any other and earns its entry. So does a run that was
submitted and came back uninteresting.

## Entry shape

Each entry names the run, the commit it ran on and the date, so it can be placed
against the rest of the series, and then answers the three questions above.

```markdown
## <run>

Ran at `<commit>` on `<date>`, <node type>, <partition>, SLURM job `<id>`.

**Barrier.** ...

**Class.** Numerical / structural / cost, and why.

**Carry-over to the source tags.** ...
```

The commit, the date and the node come from that run's `provenance.txt`. A run
whose provenance is missing is not analysed and gets no entry; the agent asks
for it instead.

## Entries

## A1. The van Leer ladder

Ran at `3659746` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`, SLURM jobs
`27360483` (`dt` 10 s), `27360484` (5 s) and `27360496` (2.5 s). Three runs of
the DYCOMS_RF02 0M column for one hour, differing only in `dt`.

End-of-run operator residual, `max |q_tag_res + Σᵢ q_tag_fix_i|` in kg kg⁻¹:

| `dt` (s) | operator residual | log-log slope |
|:-------- |:----------------- |:------------- |
| 10       | 2.844e-6          | −0.011        |
| 5        | 2.547e-6          |               |
| 2.5      | 2.888e-6          |               |

**Barrier.** The residual does not fall as `dt` falls. Over a factor of four in
`dt` it moves by 13%, non-monotonically, for a fitted slope of −0.011. Under
the default `vanleer_limiter` the implicit-explicit split does not converge
away.

The ledger is identically zero in all 61 samples of each run, so
`repair_water_tag_partition!` never fired and the operator residual equals
`q_tag_res` exactly. That is not a null result about the decomposition: it says
the column's tags never left the partition, so this measurement is the operator
disagreement alone with nothing subtracted, which is the cleanest form the
metric can take.

**Class.** Numerical in origin, structural in effect. It is a discretization
residual rather than a coverage gap — nothing here is unbracketed — but it does
not shrink with the step, so no amount of time refinement removes it. Read
against A2 it is the limiter's floor.

**Carry-over to the source tags.** Partial, and as a lower bound only. The
source tags ride the same explicit passive-scalar path against the same
implicit parent, so the same operator disagreement applies to them. They also
get no rescale and no partition repair, so nothing can return what leaks. Two
things stop this being a prediction of their residual: they partition `ρe_tot`
rather than `ρq_tot`, whose transport is enthalpy including pressure work and a
different operator set entirely, and their donor rule is inert wherever
`ρe_tot ≤ 0`. So: a floor, not an estimate.

## A2. The control ladder, and what it decides

Ran at `66d6ded` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`, SLURM jobs
`27360825` to `27360827` (`none` at 10, 5 and 2.5 s) and `27360828` to
`27360830` (`first_order`, same order). The A1 ladder twice more, once with
`energy_q_tot_upwinding` and `tracer_upwinding` both `none`, once with both
`first_order`.

| `dt` (s) | A1 van Leer | A2 `first_order` | A2 `none` |
|:-------- |:----------- |:---------------- |:--------- |
| 10       | 2.844e-6    | 7.756e-7         | 2.054e-7  |
| 5        | 2.547e-6    | 7.090e-7         | 1.049e-7  |
| 2.5      | 2.888e-6    | 5.447e-7         | 1.080e-7  |
| slope    | −0.011      | +0.255           | +0.464    |

A positive slope means the residual falls as `dt` falls. The ledger is
identically zero in all six runs as well.

**Barrier.** The plan's first case, and it settles the phase A question. A2's
ladders fall with `dt` and A1's does not, so the time-discretization part of
the split is real and the limiter sets a floor beneath which refining the step
does not reach. At `dt` 10 s the fully linear reconstruction sits **13.8×**
below the van Leer default, and `first_order` sits 3.7× below it.

**So option 2 is not worth its Jacobian cost.** Moving the water tags into the
implicit solve removes the implicit-explicit disagreement, which is the part
that converges; it cannot remove the limiter nonlinearity, which is what the
default configuration is actually dominated by. The memo predicted exactly this
in words at Part 2's water item (i) — the van Leer correction is nonlinear in
the tag, so the residual is bounded by the limiter nonlinearity and not by
rounding. These are the numbers behind that sentence.

**What 13.8× is not.** A2 changes `energy_q_tot_upwinding` as well as
`tracer_upwinding`, so this compares *both reconstructions linear* against
*both van Leer*. It is not a clean attribution to the limiter, and 13.8× must
not be quoted as the limiter's share. Separating the parent's reconstruction
from the tags' would need a third ladder holding one fixed.

**Class.** Numerical, and now measured rather than argued. The cost side is
unmeasured: `a1_dt10_notags` has not run, so what the tags cost is still open.

**Carry-over to the source tags.** As for A1, a floor and not an estimate, for
the same two reasons.

### Open question this raised

**Both linear ladders are sub-first-order, and `none` stops converging.** A
scheme whose reconstructions are `dt`-independent should give a first-order
residual, slope 1. Measured slopes are 0.464 and 0.255. Worse, `none` falls
almost exactly first-order from `dt` 10 to 5 — 2.054e-7 to 1.049e-7, within 2%
of the ideal 1.027e-7 — and then stops, rising slightly to 1.080e-7 at 2.5 s,
which is 2.1× above where first-order convergence from `dt` 10 would put it.

Something non-converging remains at about 1e-7, an order of magnitude below the
limiter floor and two below the default configuration's residual. The memo does
not name it. Candidates not distinguished by this experiment: the
`ᶜadvdivᵥ`/`ᶠinterp` operator pair still differing between the implicit parent
and the explicit tags even at central reconstruction; the sedimentation-free
0M path having some other unbracketed writer; or a genuine floor from the
`Float64` reduction at this cell count, though `100 eps` on this column is
around 1e-14 and cannot explain 1e-7.

**This is an open question, not a finding.** Three points cannot separate a
plateau from a slow asymptote, and the candidates above are untested. Naming it
matters because it bounds what any implicit-tag work could achieve even in the
linear case: at `dt` 10 s with central reconstructions the residual is already
within 2× of that floor.

## A3. 1-moment microphysics

Ran at `49b2ec9` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. `a1_dt10`
with `microphysics_model: 1M` and `vert_diff: DecayWithHeightDiffusion`.

End-of-run operator residual **9.844e-8**, against A1's 2.844e-6 at the same
`dt`. An order of magnitude *lower*, not higher. The ledger is identically zero
in all 61 samples here too.

**Barrier.** None that this run can identify, and that is the honest answer.
The result is counterintuitive — 1M adds the sedimentation mirror and the
`q_tot_eff` mismatch, both of which should raise the residual — and it is
uninterpretable as it stands, because the run moves two keys at once. It
differs from `a1_dt10` in `microphysics_model` **and** `vert_diff`, the second
being necessary for the `q_tot_eff` mismatch to reach a column at all. So the
difference between the two runs is some combination of adding 1M and adding
vertical diffusion, and nothing here separates them. A lower residual is as
consistent with vertical diffusion smoothing the field the two advection
schemes disagree over as with anything about 1M.

**Do not read this as "1M is better".** It is not evidence for that.

**Class.** Unclassified. There is no barrier to classify until the run is
interpretable.

**What would settle it.** The matched companion already recorded as an open
item in `README.md`: one 0M column, `dt` 10 s, with
`vert_diff: DecayWithHeightDiffusion` on and everything else as `a1_dt10`. The
gap from that run to A3 is the 1M mismatch alone; the gap from `a1_dt10` to it
is the vertical diffusion alone. One extra column run, minutes of walltime.

**Carry-over to the source tags.** Nothing, until the above is done.

## A4. Float32

Ran at `49b2ec9` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. `a1_dt10` at
`FLOAT_TYPE: Float32`.

| quantity                       | `Float32` (A4) | `Float64` (`a1_dt10`) |
|:------------------------------ |:-------------- |:--------------------- |
| operator residual, end of run  | 2.853e-6       | 2.844e-6              |
| `gross_relative` at t = 0      | 2.338e-8       | 2.700e-17             |
| `gross_relative` at end of run | 2.745e-5       | 2.660e-5              |

**Barrier.** Not the one that was expected. The pre-registered expectation, in
the plan's phase A table and in the memo's `Float32` paragraph, was that the
`Float32` floor might hide the structural residual. **It did not.** The two
precisions agree on the operator residual to 0.3%, so the measurement survives
production precision on this column intact.

What the run does give is the floor itself, measured rather than bounded. At
t = 0 the partition is exact in exact arithmetic, so `gross_relative` there is
the reduction's own noise: **2.34e-8**. The memo used `100 eps ≈ 1.2e-5` as the
`Float32` bound, which is over five hundred times pessimistic for this
configuration. The structural residual sits about three orders of magnitude
above the measured floor, which is what makes it a usable detector at
`Float32`.

**The limit of this result, which matters.** The memo's actual claim is not
that the floor is large but that it *grows with the cell count*, because
`tag_closure` reduces in the state type with no promotion. A 30-level column is
the smallest case in the series and therefore the easiest. **This settles
nothing about a sphere**, where the reduction runs over four to five orders of
magnitude more cells. A5's grid is the one where that would show, and A5 failed
for an unrelated reason before it could.

**Class.** Numerical, and benign at this size. The cost is nil — `Float32` is
the default, so this is what a production run gets for free.

**Carry-over to the source tags.** The reduction is the same code for all three
families, so a comparable floor is expected for them at comparable cell counts.
Their residuals are larger, so the floor matters less. Neither statement is
measured; C0's tables are the place to check the first.

## A5. The sphere with the SEM limiter: the water tags diverge

**Status: fixed and re-run.** Everything down to *The fix* is the measurement
made at `49b2ec9`, before the fix, and it stays as written because it is what
issue #64 names. **Do not read any number in it as current.** The fix, the
re-run at `8ed98b6` and the audit follow it, in that order, and those are the
current readings.

Ran at `49b2ec9` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. A moist
baroclinic wave, `h_elem` 4, `z_elem` 10, 0M, with
`apply_sem_quasimonotone_limiter: true`, `dt` 300 s, one day, hourly closure
check.

| time | parent total `∫ρq_tot` | tagged total | `gross_relative` |
|:---- |:---------------------- |:------------ |:---------------- |
| 0    | 1.61848e16             | 1.61848e16   | 3.23e-17         |
| 1 h  | 1.61873e16             | 1.61873e16   | 3.07e-5          |
| 2 h  | 1.61911e16             | 1.61914e16   | 9.03e-5          |
| 3 h  | 1.61947e16             | 2.92973e16   | 0.809            |
| 4 h  | 1.61977e16             | 4.08313e17   | 24.2             |
| 6 h  | 1.62013e16             | 5.73336e26   | 3.54e10          |
| 24 h | 1.62138e16             | 9.56921e129  | 5.90e113         |

**Barrier. The water tags diverge without bound while the parent stays
bounded, and the run reports success.** `ρq_tot` never leaves
1.61848e16 to 1.62138e16 over the whole day — a 0.18% drift, which is the
physics. The tag sum reaches 1e130. `exit_status: 0`, `ret_code = :success`,
no crash, no `NaN`, nothing in the log that stops a queue.

This is a stability failure, not an accounting one. Every other run in the
series has an operator residual that is small and interpretable; this one has
no meaningful residual at all after hour three, because the quantity it
subtracts has left the scale of the problem.

**The divergence is not monotone.** It reaches 5.73e26 at 6 h, falls back to
about 1e25 and sits there for four hours, then resumes and runs away. That
shape matters: something is intermittently knocking the tags back down, which
is what the repair and the rescale are for, and they are losing.

**This is the first run in the series where the corrections fire at all.** The
ledger is non-zero in 24 of 25 samples, against identically zero in all nine
A1/A2 runs and in A3 and A4. The column configurations never trip a limiter, so
A5 is the only phase A run that exercises `rescale_water_tags!` — and the
correction is the same order as the failure: at 24 h the summed ledger is
1.03e115 against a residual of 4.49e114.

### The existing test cannot see this

`test/tagged_water_integration.jl` runs this configuration — same initial
condition, same grid, same limiter, same `dt`, five tags where this run has
three — and bounds the residual at 1e-2. It sets `t_end = 3600secs`
(`:237`).

Read the bound carefully before setting a number beside it. It is
`max |residual| / max |ρq_tot|` (`:312`), a pointwise maximum over the domain
maximum, and not the closure table's `gross_relative`, which is a ratio of
volume integrals. The comparable quantity here is the archived pre-fix operator
residual: **7.5e-6 at one hour and 6.0e-5 at two, both far inside 1e-2, with the
divergence starting between hours two and three.** The test passes because it
stops before the failure begins.

That is a statement about test coverage, and it is the reason this went
unnoticed. The configuration was exercised; the duration was not enough to
reach the regime where it fails. Nothing about the assertion is wrong.

### Mechanism: the hypothesis made at the time

Kept as written, because the fix has since sharpened it and the difference is
worth having on the record. Read this as what was believed at `49b2ec9`, not as
the account that stood up.

**Leading candidate: the rescale ratio is unbounded above.**
`water_tag_rescale_ratio` (`tagged_water.jl`) is
`ρq_tot_after / ρq_tot_before`, guarded on `ρq_tot_before > 0` and floored at
zero, and **deliberately not clamped above**. Its docstring gives the argument
for that: "`ρq_tag ≤ ρq_tot_before` implies `ρq_tag · ratio ≤ ρq_tot_after`".

That argument has a precondition, and the precondition is exactly what the tags
are not guaranteed to satisfy. `ρq_tag ≤ ρq_tot_before` holds only while the
tags are still inside the partition. Unlimited explicit transport drifting them
out of it is the premise of `q_tag_res` existing at all. Once a tag exceeds its
cell's parent, the bound fails and the ratio amplifies rather than corrects.

The evidence that fits: `nonpositive_fraction` reaches 0.363 within the first
hour and stays near 0.35 for the rest of the day, so **a third of this domain
has `ρq_tot ≤ 0`** — a moist baroclinic wave to 30 km, with a stratosphere
holding no water. Cells at or just above zero are where a small absolute change
in `ρq_tot` is an enormous ratio. Applied per step, it compounds. And the
ledger being the same order as the residual says the corrections are
themselves enormous, not that they are failing to fire.

**This is not established.** It is not instrumented, the field is not output
per cell, and nothing here distinguishes it from the vertical-water-borrowing
path, the SEM limiter's own behaviour on a sharp `tanh` front at 20° latitude,
or a straightforward instability in unlimited tag transport that the rescale is
merely recording. What would confirm it: output `q_tag_fix_*` and `q_tag_*`
three-dimensionally over the first three hours and look for cells where the
ratio exceeds some threshold, or instrument `water_tag_rescale_ratio` to record
its maximum per step. Both are cheap. Neither has been done.

**Class.** Numerical, and a stability failure rather than an accounting one.
Not a cost — the run completed in its slot. Not structural in the sense the
rest of this series uses, since no process is unbracketed; the machinery that
exists is producing the divergence rather than failing to cover something.

**Carry-over to the source tags.** This specific mechanism cannot bite them the
same way: the energy source tags have **no rescale and no partition repair at
all**, so there is no unbounded ratio to amplify them. The energy tags likewise
have no rescale. That is not reassurance. It follows only that they cannot fail
*by this route*; they are also exempt from both limiters and ride the same
unlimited explicit transport, with nothing at all to knock them back, and A5
shows that transport on this grid drives tags far enough out of partition for
corrections to matter. Whether that ends in a bounded drift or a different
divergence is not answered here. C0's sphere is the run that would show it.

### What this changes

A5 was written as an optional run to measure how much the repair and the
rescale contribute on a sphere. It answers that question in a way the plan did
not anticipate: on this configuration they do not merely contribute to the
residual, they participate in destroying it. The plan's statement that A5's
numbers are "read as a total rather than as an operator residual" is too
generous — after hour three they are not readable as either.

### The fix, and what it does not yet establish

**Fix landed, and re-measured.** The owner merged issue #64 onto this branch at
`f2e5384`, from `7799a5a` and `acfea85`, and the re-run is in *The re-run* below.
The table above stays as the before; the archived reading is in
`output/a5_sphere_limiter/before_issue_64_fix/`.

**What changed in the model.** `rescale_water_tags!` followed every parent
correction by multiplying each water tag by `r = ρq_tot_after / ρq_tot_before`.
It now hands the tags the parent's increment additively instead,
`ρq_tag_k += Δ · s_k`, with `Δ = max(ρq_tot_after - ρq_tot_before, -pos)`,
`s_k = max(ρq_tag_k, 0) / pos` and `pos = Σⱼ max(ρq_tag_j, 0)`. On a
closed non-negative partition the two are the same expression.
`water_tag_rescale_ratio` is gone, replaced by `water_tag_rescale_shift` and
`water_tag_source_rescale_shift`.

**The account that stood up is not quite the one above.** Writing
`e = ρq_tot - Σₖ ρq_tag_k` for what `q_tag_res` reports, the old rule gave
`e_after = r · e_before` in *every* cell with a positive parent, and
unconditionally: `ρq_tot_after = r · ρq_tot_before` is what `r` means, so
scaling the tags scales the error with them. The hypothesis above was in the
right place — the rescale, and the cells near `ρq_tot = 0` where `r` is large
— but it hung the mechanism on the docstring's precondition
`ρq_tag ≤ ρq_tot_before` failing. That is not what breaks. The error is
amplified whether or not the precondition holds; the precondition governs
non-negativity, not closure. The additive rule leaves `e` exactly where it was
wherever the partition holds water and the loss floor does not bind, and moves it
by at most `|Δ|` where the floor binds.

**A second change bears on this run directly.** All three closure checks now take
`abort_above`, and water defaults to `1.0` — a level no non-negative partition of
a non-negative parent can reach. The table above crosses it between hours three
and four: 0.809 at 3 h and 24.2 at 4 h. A re-run of this configuration under the
old rule would therefore stop in its fourth hour instead of reporting success at
24 h. `a5_sphere_limiter.yml` leaves the default in place deliberately, and its
comment says so, because a non-zero exit from that run is a result rather than a
broken job.

**What the re-run had to establish, and what it could not.** Answered below;
this is what was asked of it beforehand. Two outcomes are
informative and both need recording. The residual may stay small through a full
day, which is the fix working. Or it may reach 1.0 and abort, which is not
automatically a failure of the fix: the floor `Δ ≥ -pos` empties the tags of a
cell whose parent loses more water than the tags hold, and the water the parent
still holds then surfaces in `q_tag_res`. A residual pegged near 1 with the tags
gone reads exactly the same in `gross_relative` as one near 1 with the tags
intact. **That is why `audit: true` is now set on this config and on no other
phase-A run.** `orphaned` is the mass in cells whose parent holds water while
every tag is empty, and it separates those two; `overclaimed` names the direction
of any new runaway on sight, which is the reading that took a separate analysis
pass the first time. Neither has been measured.

### The re-run: the fix holds, and phase A finally has a sphere

Run at `8ed98b6`, one day, `exit_status: 0`, and the `abort_above` level of 1.0
was never approached. `gross_relative` against the archived before:

| time | before      | after    |
|:---- |:----------- |:-------- |
| 1 h  | 3.07e-5     | 2.84e-5  |
| 2 h  | 9.03e-5     | 7.12e-5  |
| 3 h  | 8.09e-1     | 1.15e-4  |
| 4 h  | 2.42e+1     | 1.55e-4  |
| 6 h  | 3.54e+10    | 1.89e-4  |
| 12 h | 9.84e+17    | 2.51e-4  |
| 24 h | 5.90e+113   | **2.79e-4** |

**It plateaus rather than merely staying finite.** 1.89e-4 at 6 h, 2.51e-4 at
12 h, 2.79e-4 at 24 h — each doubling of elapsed time adds less than the last,
against 0 to 1.15e-4 in the first three hours. Not set against the integration
test's 1e-2: that bounds a pointwise maximum over the domain maximum and this is
a ratio of volume integrals, so the two do not divide.

**And it did not get there by emptying the tags**, which was the second of the
two informative outcomes and is now ruled out. `nonpositive_fraction` runs
0.350 to 0.363 throughout, essentially what the diverging run showed (0.36), so
a third of the domain still holds non-positive water and the tags stay
consistent over it anyway. The signed residual is −1.2e11 against a parent of
1.62e16, or −7.5e-6 relative, so `tagged` tracks `total` rather than sitting
below it. The tags are neither exploding nor collapsing.

**The corrections changed character, and that is the mechanistic evidence.**
Before the fix the ledger ran 2 to 3× the residual with essentially all of it in
one tag: `q_tag_fix_extratropics` 1.027e115 against `q_tag_fix_tropics`
4.55e109, a factor of 2e5. After it, the two per-tag maxima agree to fifteen
digits — 1.0433587234981436e-3 and 1.043358723498146e-3 — while the maximum of
their *sum* is 6.2e-4, smaller than either. Two fields whose extremes coincide
to machine precision, summing to less than either, is what sum-preserving
redistribution looks like: the repair step takes the same quantity out of one
tag that it puts into the other. The residue that does not cancel is the
rescale shift `Δ`, which is the part that genuinely changes the total because
the limiter moved water into or out of the cell. These are domain maxima rather
than per-cell values, so this is a signature rather than a proof, but it is the
signature the additive rule was designed to produce and the opposite of the
one-sided amplification it replaced.

**Phase A now has the sphere measurement it lacked.** `max |q_tag_res|` is
**1.9e-5 and flat** from about 6 h on, where before the fix it passed 1.8e1 at
3 h and 4.5e114 at 24 h. The column at `dt` 10 under the same van Leer limiter
gives 2.84e-6, so the sphere sits 6.8× above it. That is not a controlled
comparison — A5 is `dt` 300 on `h_elem` 4 and `z_elem` 10, against a 30-level
column at `dt` 10 — and a 30× larger timestep costing 6.8× in residual is on
the favourable side of what the ladders would predict. The reduction is over
the remapped lat-lon field, as `operator_residual.csv` says in its header.

The ledger, unlike the residual, is still growing: 6.2e-4 at 24 h, 32× the
residual, with no sign of levelling. So the limiter keeps doing work all day and
the corrections keep absorbing it. What has stopped is the amplification.

### What the audit says, and one number that reframes the series

`water_tag_audit.csv` came back on the second pass. It is the first audit table
this series has produced on real data, and it settles by measurement what the
paragraphs above could only infer.

**The identity holds.** `untagged_relative` 1.3556e-4 plus
`overclaimed_relative` 1.4307e-4 is 2.7863e-4, which is `gross_relative` in the
closure table to the last digit. The relation the harness was built on is now
confirmed against a model run rather than against randomised states.

**The residual is balanced, not directional, and that is the reading that
matters.** The two halves differ by 5% — the tags are very nearly as often
slightly short of the parent as slightly over it. A runaway is one-sided by
construction: before the fix this run was pure overclaim, tags holding water the
parent did not have. A residual split evenly between the two directions is what
transport leakage looks like, not what a failure looks like.

**And the emptied-tags outcome is excluded directly.**
`orphaned_relative` is **2.5e-9**, five orders of magnitude below the residual.
Almost no mass sits in cells whose parent holds water while every tag is empty,
so the removal floor is not holding closure by throwing tag content away.
`orphaned_volume_fraction` is 0.032, so 3.2% of the domain *volume* is orphaned
while carrying 2.5e-9 of the mass: it is essentially empty air, a rounding-level
artifact. There is one transient — orphaned mass falls from
8.69e9 at 5 h to 4.89e7 at 6 h, a factor of 178, while the volume fraction goes
on rising — which is the early adjustment settling out.

**The number that reframes things.** `nonpositive_mass_fraction` is
**2.77e-7** where `nonpositive_fraction` is **0.351**. So 35% of the domain's
volume holds non-positive water and carries three ten-millionths of the water.
The volume fraction exceeds the mass fraction by a factor of 1.3 million. For
the water family, "a third of the domain is non-positive" is a statement about
vanishingly dry upper-atmosphere air and almost nothing else.

**Both are volume fractions, not fractions of cells.** `tag_closure` fills a
field with ones and reduces it with `sum`, which on a ClimaCore `Field` is the
volume-weighted integral (`tagged_tracers.jl:456-459`, docstring at `:421`). On
a uniformly spaced column the two readings coincide, which is why `c0_column`'s
0.9667 is also exactly 29 of 30 levels. On a stretched sphere they do not.

**It cuts the other way for energy, which sharpens C0 rather than softening
it.** C0's 43.276% on the sphere is a volume fraction too, and
`where_negative.jl` placed the non-positive region at every level from 250 m to
11.0 km — the troposphere, which holds most of the atmosphere's mass. The same
headline percentage therefore means opposite things in the two families: for
water a rounding artifact, for energy the bulk of the field. Nobody has measured
the energy family's mass fraction. `c0_sphere_audit` is the run for it — the
same sphere with `audit: true` and nothing else, so its answer pairs with the
43.276% actually in circulation.

**What the ledger means now, and why the operator residual is unaffected.** The
identity `analysis/reduce_run.jl` rests on — that `q_tag_res + Σᵢ q_tag_fix_i`
is this residual with the bookkeeping instantaneously undone — survives the
change. Both correction sites still write `ᶜfix += shift` immediately before
`ᶜρq_tag += shift`, with the same expression and the same pre-correction
operands, and both diagnostics still divide by the same `ρ`, so the ledger still
records exactly what was applied. What does change is what the ledger *sums to*:
it was `(Σₖ ρq_tag_k)(r - 1)` and is now `Δ`, and those agree only on a
closed partition. A1 to A4 are unaffected either way, because a column trips no
limiter, so `Δ = 0` and every shift is zero — which is why their ledger column is
identically zero and will stay so.

## Caveats on all of phase A

**Every run in the series records `commit_dirty: yes`.** `commit_source` is
`git` throughout, so the commit itself is real and was read successfully; the
working tree simply had uncommitted changes when each job was submitted, which
is what editing and submitting in the same session looks like. So a recorded
commit is the nearest committed ancestor of what ran, not an exact description
of it. For these runs the uncommitted changes were configurations and analysis
scripts rather than model code, so the measurements stand, but a run whose
result surprises you is worth checking against this.

The A1 and A2 ladders are three `dt` points each, one column, one hour, 0M, one
configuration. Their ledgers are identically zero, which is why those numbers
are clean: the column trips no limiter, so they measure operator disagreement
with nothing subtracted.

A3 is uninterpretable until its matched companion runs. A4 settles the
`Float32` question on a column and explicitly not on a sphere. A5 delivers the
sphere operator residual after the issue-64 fix, but only the one run at one
resolution, and the plan's expectation that it would quantify the repair and
rescale contributions separately is still not met: the ledger is measured as a
total, not split between the rescale and the partition repair.

The A1 runs are at `3659746` and the A2 runs at `66d6ded`. The two differ only
in `.gitignore`, `README.md` and previously committed results — nothing
touching the model, the configurations, the driver or the runscripts — so the
ladders are comparable.

## C0. The barrier census

Both runs at `49b2ec9` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`, SLURM
jobs `27361326` (column) and `27361327` (sphere). Both `exit_status: 0`.

This is the phase the series was pointed at. **Both barriers the memo predicted
are present, and both are structural.**

### c0_column — DYCOMS 1.5 km column, `rad: DYCOMS`, one day

| time | `nonpositive_fraction` | `gross_relative` | `max e_src_rad` |
|:---- |:---------------------- |:---------------- |:--------------- |
| 0    | 1.0000                 | 2.55e-17         | 0               |
| 1 h  | 1.0000                 | 6.34e-3          | 441.91          |
| 6 h  | 1.0000                 | 3.90e-2          | 2835.76         |
| 12 h | 0.9667                 | 7.59e-2          | 3791.54         |
| 24 h | 0.9667                 | 1.346e-1         | 4321.33         |

**Barrier one: the donor rule does not run.** `ρe_tot ≤ 0` over the *entire*
domain at initialization and for the first eight hours. The docs record 100% at
initialization on this column; this shows it **persists through integration**
rather than being an initial-condition artifact that the first few steps clear.

`nonpositive_fraction` then takes a single step, at exactly 8 h, from 1.000000
to 0.966667 — which is 29/30, so **exactly one of the thirty levels crosses
into positive `ρe_tot`** and stays there. It does not move again for the rest of
the day.

Where the share is undefined `energy_source_fraction` returns zero, so no tag is
depleted while production stays mask-weighted and reaches tags normally. The
`rad` tag is that regime made visible: zero at t = 0, then 441.91 at 1 h,
2835.76 at 6 h, 3791.54 at 12 h, 4321.33 at 24 h. Its own minimum sits at about
−2e-9 throughout, which is numerical noise, not a sign change.

**A detail that supports the reading.** The `rad` tag's growth is **not
monotone**, and where it first turns is not a coincidence. It rises steadily to
3221.91 at 7 h, then *falls* by 137.0 over the next hour — and that hour,
25200 s to 28800 s, is exactly the interval in which the one level crosses into
positive `ρe_tot`. The first time any part of this domain can support a donor
share is the first time the tag loses anything. After 19 h it plateaus and
drifts down through four consecutive samples before ending at 4321.33. So the
loss half is not merely absent, it is switched on and off by the sign of the
parent, cell by cell.

**A second observation the brief did not carry.** The region tags do not stay a
partition of a negative parent. At t = 0 both are wholly negative — `strat`
spans −44972.5 to −0.0217, `tropo` −43124.8 to −0.0225 — which is what
mask-weighting a negative parent gives. By 12 h `max e_src_tropo` is +39007.5
and by 24 h +107824, against a parent whose scale has not changed that way. The
tags are not merely negative; they are spreading apart, and `gross_relative`
rising to 0.135 is that spread.

### c0_sphere — moist sphere, `h_elem` 6, `z_elem` 10, one day

| time | `nonpositive_fraction` | `gross_relative` | `min e_src_sfc` | `max e_src_sfc` |
|:---- |:---------------------- |:---------------- |:--------------- |:--------------- |
| 0    | 0.43276                | 2.10e-17         | 0               | 0               |
| 6 h  | 0.43276                | 9.39e-3          | −50.46          | 6035.84         |
| 12 h | 0.43276                | 1.175e-2         | −114.53         | 11199.4         |
| 24 h | 0.43276                | 1.542e-2         | −209.19         | 19265.9         |

**Barrier one again, and this is the stronger statement.**
`nonpositive_fraction` is 0.4327600052941768 at every one of the 25 samples —
constant to the last digit across the whole day. **A full sphere reaching 30 km
still has 43% of its volume where the shares are undefined.**

`energy_source_tags.md` frames the non-positive parent as a consequence of
shallow domains, citing 100% on the shipped 1.5 km column and 43% on a 30 km
column, with "depth reduces the fraction, because geopotential lifts `e_tot`
positive higher up". That framing holds — 43% is indeed far better than 100% —
but it invites the reading that a realistic configuration escapes the problem.
It does not. On a real sphere, over a real day, **the figure is 43% and it does
not move at all.**

**Barrier two: a source tag goes negative and stays there.** The `sfc` tag
starts at zero, and its minimum falls **monotonically** — 0, −50.46 at 6 h,
−114.53 at 12 h, −169.55 at 18 h, −209.19 at 24 h. That is not a transient
excursion; it is a steady accumulation, roughly linear in time, with no sign of
turning. This is the memo's second prediction, from Part 1's source table: no
rescale and no partition repair for this family, so tags may go negative — and
`tagged_tracers.jl` exempts them from both limiters.

A negative source tag invalidates the amount-of-energy and provenance reading
of that tag for as long as it lasts, which by 24 h is the whole run.

**And `e_src_res` does not show it.** The residual sums the pure region tags
only, so a source-labelled tag going negative never enters it. `gross_relative`
on this run ends at 1.54e-2 — smaller than the column's, unremarkable, and
entirely silent about the tag that has gone negative underneath it. The only
thing that shows it is the per-tag minimum, which is why `reduce_run.jl` emits
one for every tag rather than for the partition alone.

The region tags are negative here too, and from t = 0: `min e_src_tropics`
−23686, `min e_src_extratropics` −100416. That is mask-weighting a parent that
is negative over 43% of the domain, so it is expected rather than drift.

### The three questions, for both runs

**Barrier.** Two, both present in both runs: the donor loss does not run where
`ρe_tot ≤ 0`, which is 96.7% of a column and 43% of a sphere; and a source tag
goes negative with nothing to repair it, monotonically, on the sphere.

**Class. Structural, not numerical.** Nothing here is a rounding problem, a
stability problem or a cost. `gross_relative` starts at 2.55e-17 and 2.10e-17,
which is machine precision, so the arithmetic is exact where it is defined. Both
runs completed in their slots. The rule simply does not run where the parent is
non-positive, and nothing exists to repair a negative source tag. These are
properties of the design as written, and they are what the memo said they were.

**Carry-over.** Not applicable in the usual direction — this *is* the family the
rest of the series was measuring toward. What carries the other way: phase A
established that the shared passive-scalar transport contributes an operator
residual that does not converge away, and that is a floor beneath these numbers,
not the explanation for them. The barriers here are an order of magnitude larger
and of a different kind.

### The energy reference, settled after C0

C0 left one thing unaccounted for: the field is about 7.8e4 J kg⁻¹ below what
the textbook expression `cv_m(T − T_0) + q_v·e_int_v0 + gz` gives for the same
state. Either the convention differed or the initialisation was wrong, and the
second would have made C1 a treatment of a symptom. Read on Levante:

```julia
@inline function internal_energy_dry(param_set::APS, T)
    T_0 = TP.T_0(param_set)
    cv_d = TP.cv_d(param_set)
    R_d = TP.R_d(param_set)
    return cv_d * (T - T_0) - R_d * T_0
end
```

`internal_energy_dry(T_0 = 273.16)` returns −78396.92, which is `−R_d·T_0` to
the last digit with `R_d` = 287.0. Energy is referenced so that *enthalpy*
vanishes at `T_0`. **The unaccounted gap is that term**, and `TD.total_energy`
called on the DYCOMS surface state returns −44,009 against the field's −43,125.
The function reproduces the field. It is a convention, not an error, so
**C0's 43.276% stands as a fact about the reference** and the C0 entry above
needs no correction.

The model carries the same convention in its own analytic Jacobian:
`manual_sparse_jacobian.jl:835` and `:1805` write `T_0 * cp_d`, not `T_0 * cv_d`.

**Two consequences for C1, one of which was got wrong first.** The derivative
that sets any reference shift is `∂e_int/∂T_0 = −cp_d`, not `−cv_d` and not
`−R_d`: an earlier note put the factor at 2.5 in the wrong direction, and it is
`γ = 1.4` in the other. The sphere needs `ΔT_0` = 100.0 K and the column 45.2 K,
where the textbook reading would have said 140 K.

The second consequence is larger and nobody had counted it. `T_0` is not a free
datum. The same constants give
`LH_v(T) = LH_v0 + (cp_v − cp_l)(T − T_0)` with `cp_v − cp_l` = −2322, so moving
`T_0` to 173.2 K with `LH_v0` fixed drops `LH_v(288.3)` from 2.4656e6 to
2.2335e6, low by 9.4%. That is a change of physics, which is what the chosen
shift shape existed to avoid. A C1 configuration therefore has to co-adjust
`LH_v0` and `LH_s0`, and the saturation vapour pressure needs checking because
it carries a reference of its own.

**Confirmed, and it makes C1 cheaper rather than dearer.**
`latent_heat_vapor(288.3)` returns 2.46564492e6 against a predicted
2,465,644.92, and `latent_heat_fusion(273.16)` returns 333600.0, so `LH_f0` is
that and `LH_s0` is 2.8344e6. The settable fields include `T_0`, `LH_v0` and
`LH_s0` and exclude `LH_f0`, every `cv_*` and `e_int_v0`, so the derived ones
follow for free. Everything physical depends on `T_0` only through the group
`LH_0 − Δcp·T_0`, so moving `T_0` by `δ` together with `LH_v0` by
`(cp_v − cp_l)·δ` and `LH_s0` by `(cp_v − cp_i)·δ` leaves every latent heat and
`p_sat` exactly unchanged while moving `e_int` by `−cp_d·δ`. **C1 therefore
needs no code change**, only three TOML entries and the owner's approval, and
its acceptance test is exact: `LH_v(288.3)`, `LH_f(273.16)` and `p_sat(288.3)`
must come back unchanged at 2.46564492e6, 333600.0 and 1721.1532852305072 while
`internal_energy_dry(288.3)` moves from −67533.97 by `−cp_d·δ` and by nothing
else. The raw probe output is in `LEVANTE_TASKS_RESULTS.md`;
`C1_reference_shift.md` has the derivation and the recipe.

### What this bears on, and what it does not decide

`energy_source_tags.md` states the open question the family exists to answer:
whether the shares are stable and interpretable under a realistic configuration,
and that the answer decides whether energy source tracing is used at all, or
whether water source tracing is combined with the energy process record instead.

**C0 is evidence toward that decision and is not the decision.** What it
establishes: on the two configurations tested, the shares are undefined over
96.7% of a column and 43% of a sphere, the donor rule is correspondingly inert,
and a source tag drifts negative and stays so. What it does not establish: that
this is irreparable.

**C1 is the run designed to answer that**, and it has not run. It reruns this
configuration under a reference shift making `ρe_tot > 0` everywhere, and it
needs the owner's approval, but no longer a code change. The plan gives two
shapes; the first should be dropped rather than costed, and the second is now
known to be a co-adjusted reference *set* rather than a single constant — three
TOML entries, per the subsection above. If C1 shows bounded residuals and
non-negative tags under a positive reference, the family is viable and the
remaining work is the
tolerance model and the implicit brackets. If it does not, the docs' alternative
is the recommendation.

**Do not read C0 as a verdict on the family.** It measures how large the problem
is under the current reference. It says nothing about how large it is under a
better one, because no run has used a better one.

**C3 is now a more interesting run than it was.** It puts an
`energy_process_record` beside the source tags on the same column, and the
record is the alternative reading the docs name. Before C0 it was a
completeness exercise. After C0 — with the source tags' donor rule inert over
almost the whole column — it is the run that shows what the fallback actually
delivers on a configuration where the primary method is in trouble. It has since
run; its entry is below.

## C3. The two readings, side by side

Ran at `1a9a419` on 2026-09-10, AMD EPYC 7763, `shared`, SLURM job `27367733`.
Same DYCOMS column as `c0_column`, with an `energy_process_record` for
radiation added beside the source tags. One day, `dt` 10 s, `rad: DYCOMS`.

**The run is a controlled comparison, and that is worth stating first.** C3
reproduces `c0_column` bit for bit: `gross_relative` 0.13456131085846748,
`max_abs_e_src_res` 26888.66561703798, most-negative tag −44972.50629142498, all
identical to the last digit. The record perturbs nothing. Whatever the two
readings disagree about is a property of the readings, not of two different
simulations.

**Barrier.** The source tag cannot see the dominant physical term. Over the day:

| reading of what radiation did    | min (J kg⁻¹) | max (J kg⁻¹) |
|:-------------------------------- |:------------ |:------------ |
| source tag `e_src_rad`           | −2.07e-9     | +4,321       |
| process record `e_prc_radiation` | −20,566      | +7,587       |

The source tag is pinned at zero from below. It has to be:
`energy_source_fraction` returns 0 where `ρe_tot ≤ 0`, which is 29 or 30 of the
column's 30 levels, so the loss half of the donor rule never runs and the tag
can only accumulate. The record says the larger excursion is **cooling**,
−20.6 kJ kg⁻¹, and cloud-top radiative cooling is the entire point of a DYCOMS
stratocumulus column. The warming halves disagree too, 4,321 against 7,587, a
factor of 1.75.

The budget side says the same thing from the other direction. `gross_relative`
grows monotonically to 0.1346 over the day — production accumulating with no
compensating loss, 13.5% of `∫|ρe_tot|` in twenty-four hours.

**Class.** Structural. It is not a residual to be tightened or a tolerance to be
set. The share `ρe_src_k / ρe_tot` is undefined where the parent is
non-positive, and no amount of accuracy makes an undefined quantity readable.

**Carry-over to the source tags.** This *is* the source tags, on the
configuration `energy_source_tags.md` names. It answers that page's open
question in the direction of the alternative.

**The alternative is now demonstrated rather than available.** The process
record measures energy added by each process since `t = 0`. That is
reference-independent, so nothing in C1 or in the reference convention can touch
it, and here it reads the cooling the tags cannot. Two cautions on the
comparison. A record is a signed running total of what a process applied and a
tag is a share of what is present, so the two columns above are not the same
quantity and their numbers should not be differenced. And a record needs one
entry per process, whereas the tags partition whatever is there — the record
tells you what radiation did, not what fraction of the energy here came from
radiation. C1 is still the run that would say whether the second question can be
made well posed at all.
