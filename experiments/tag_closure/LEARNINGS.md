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

Ran at `66d6ded` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. `a1_dt10`
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

Ran at `66d6ded` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. `a1_dt10` at
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

Ran at `66d6ded` on 2026-09-10, AMD EPYC 7763 64-Core, `shared`. A moist baroclinic wave, `h_elem` 4, `z_elem` 10, 0M, with
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

`test/tagged_water_integration.jl` runs this exact configuration — same initial
condition, same grid, same limiter, same `dt` — and asserts the residual stays
under 1e-2. It sets `t_end = 3600secs`. **At one hour the measured value is
3.07e-5, comfortably inside the bound, and the divergence starts between hours
two and three.** The test passes because it stops before the failure begins.

That is a statement about test coverage, and it is the reason this went
unnoticed. The configuration was exercised; the duration was not enough to
reach the regime where it fails. Nothing about the assertion is wrong.

### Mechanism: a hypothesis, not a finding

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
needs a code change and the owner's approval, with the shape of the shift still
unchosen — the plan gives two and says the agent must put both to the owner
before writing either. If C1 shows bounded residuals and non-negative tags under
a positive reference, the family is viable and the remaining work is the
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
delivers on a configuration where the primary method is in trouble. It is
written, validated, and has not been submitted.

### Caveats on all of phase A so far

The A1 and A2 ladders are three `dt` points each, one column, one hour, 0M, one
configuration. Their ledgers are identically zero, which is why those numbers
are clean: the column trips no limiter, so they measure operator disagreement
with nothing subtracted.

A3 is uninterpretable until its matched companion runs. A4 settles the
`Float32` question on a column and explicitly not on a sphere. A5 diverges, so
phase A has no usable sphere measurement of the operator residual at all, and
the plan's expectation that A5 would quantify the repair and rescale
contributions is not met.

The A1 runs are at `3659746` and the A2 runs at `66d6ded`. The two differ only
in `.gitignore`, `README.md` and previously committed results — nothing
touching the model, the configurations, the driver or the runscripts — so the
ladders are comparable.
