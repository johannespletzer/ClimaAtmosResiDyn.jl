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

### Caveats on all of phase A so far

Three `dt` points per ladder, one column, one hour, 0M microphysics, one
configuration. `a5_sphere_limiter` has not run, so nothing here speaks to a
sphere or to a configuration where the repair or the rescale actually fires —
and on this column neither did, which is precisely why the numbers are clean.
A3 and A4 have not run, so the 1M `q_tot_eff` mismatch and the `Float32` floor
are still unmeasured.

The A1 runs are at `3659746` and the A2 runs at `66d6ded`. The two differ only
in `.gitignore`, `README.md` and previously committed results — nothing
touching the model, the configurations, the driver or the runscripts — so the
ladders are comparable.
