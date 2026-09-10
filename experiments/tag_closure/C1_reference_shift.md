# Which reference shift for C1

A recommendation, not a decision. C1 needs a model change and the owner's
approval, and the shift's shape has not been chosen. This page says what the two
shapes in [the memo](../../docs/src/tag_closure_memo.md) actually do, why one of
them should be dropped rather than costed, and what to measure before choosing.

Written after C0. Every code reference below was checked against the tree, and
the two places where we could not verify something are marked.

## The question

The energy source tags deplete each tag in proportion to its donor share
`φₖ = ρe_src_k / ρe_tot`. Where `ρe_tot ≤ 0` the share is undefined and
`energy_source_fraction` returns zero, so the loss half of the rule does not run
while production still does.

C0 measured how much of the domain that is: **96.7% of the DYCOMS column** for
the whole day after one level crosses at 8 h, and **43.276% of a moist sphere,
constant to the last digit across 24 hours**. On the column the `rad` tag grew
from 0 to 4321 J kg⁻¹ with the loss inert, and the one hour in which a level
first turns positive is the one hour the tag loses anything.

So the rule needs a positive parent. The memo names two ways to get one.

## Option 1, shift the denominator: drop it

The first shape leaves the parent alone and has the loss rule read `e_tot + c`.
It is cheap and touches no reproducibility reference. It is also wrong, and not
in a way that trades off against its cheapness.

The region tags sum to `ρe_tot`, not to `ρe_tot + c`. So

```
Σₖ φₖ  =  ρe_tot / (ρe_tot + c)
```

and the loss actually applied is `Δ⁻ · e/(e+c)` rather than `Δ⁻`. Per-process
closure, which `energy_source_tags.md` states as an exact identity, is broken by
a factor that varies cell by cell. With `c` = 1.1e5 J kg⁻¹:

| specific `e` (J kg⁻¹) | `Σₖ φₖ` | should be |
|:--------------------- |:------- |:--------- |
| +1.0e5                | +0.476  | 1         |
| +1.0e4                | +0.083  | 1         |
| −1.0e4                | −0.100  | 1         |
| −1.0e5                | −10.0   | 1         |

Look at the sign. Wherever `e < 0` — the 43% of the sphere this was introduced
to fix — `Σφ` is **negative**, so the "loss" adds energy to the tags instead of
removing it, and as `e` approaches `−c` it diverges.

This is not a cheaper version of option 2. Over exactly the region it targets it
applies a wrong-signed, unbounded correction. Given that A5 reached 1e130 from
an unbounded ratio, adding a second one deliberately is not a trade worth
considering. Drop it rather than offering it as the low-cost choice.

## Option 2, shift the reference: two different operations

The memo's phrase "shifts the model's energy reference itself" is ambiguous
between two changes that are not at all the same. Which one is meant decides
whether the claim that the tags then "read the physics as it is" is true.

The load-bearing line is `src/cache/precomputed_quantities.jl:733`:

```julia
ᶜe_int = @. lazy(specific(Y.c.ρe_tot, Y.c.ρ) - ᶜK - ᶜΦ)
```

`ᶜe_int` goes straight into the thermodynamic state (used at lines 744 and 791),
which is where temperature and pressure come from.

**Adding a constant to `ρe_tot` in the state** therefore shifts `e_int`, so `T`
shifts by `c/cv`, so pressure shifts. That is not a change of reference. It is a
different atmosphere, and `ref_counter` would bump for a real reason.

**Lowering the thermodynamic reference temperature**, so internal energy is
measured from a colder zero, is neutral in exact arithmetic: the inverse map
shifts with it and `T` comes back unchanged. This is the operation that deserves
the name, and it is the only one that supports the memo's claim.

If C1 is run as option 2, it must be the second. We could not verify in this
container whether that reference is a tunable ClimaParams entry or is fixed
inside Thermodynamics.jl, because the package sources are not available here.
**Check that before committing to the option**: it decides whether this is a
configuration change or a dependency change.

## Two costs the memo does not count

### The shift suppresses the thing being measured

Write `e_src_k = Mₖ(e+c) + δₖ`, splitting each tag into a share-like part and the
discriminating remainder. Then

```
φₖ = Mₖ + δₖ / (e + c)
```

The part that makes a source tag differ from a plain mask-weighted energy tag is
inversely proportional to `e + c`. But `c` must be large enough to keep `e + c`
away from zero, or the unbounded-ratio failure returns. One constant controls
both, and they pull in opposite directions:

| margin above the minimum | `e + c` spans (J kg⁻¹) | discrimination vs today                |
|:------------------------ |:---------------------- |:-------------------------------------- |
| 1.0×                     | 0 … 2.13e5             | ~1.9× weaker, denominator touches zero |
| 1.5×                     | 5.0e4 … 2.63e5         | ~2.8× weaker                           |
| 3.0×                     | 2.0e5 … 4.14e5         | ~5.5× weaker                           |

At a margin anyone would actually choose, the donor rule is several times less
discriminating in the cells where it already works today. It does not collapse
into the mask rule — that overstates it — but it moves measurably toward it. The
family would partly succeed by becoming more like the one it was meant to
improve on.

This is the weakest argument here and it is sensitive to the magnitude of `c`.
If the diagnostic below shows a much smaller shift suffices, it largely
evaporates.

### It flatters the number you would judge it by

The closure check normalises by `scale = ∫|ρe_tot|`. Shifting the reference grows
that by roughly 2.2× over the sphere's range, so **the same absolute residual
reports a `gross_relative` about 2.2× smaller**. Comparing C1-under-option-2
against C0 is therefore not a comparison of residuals. The docs already warn that
tolerances are not comparable across references; this is that warning with a
number on it, and without care it would read as an improvement that did not
happen.

## The magnitude, and something unexplained

From C0's own tables, specific `e_tot` at t = 0 spans **−1.004e5 to +1.123e5
J kg⁻¹** on the sphere, and reaches −4.50e4 on the column. Making it positive
everywhere needs at least 100.4 kJ kg⁻¹, roughly **140 K** of reference
temperature. That is not a nudge.

**We cannot account for that offset.** A back-of-envelope with the standard
reference puts `e_tot` positive nearly everywhere in a normal atmosphere — of
order +10 kJ kg⁻¹ at the surface and +60 kJ kg⁻¹ at 10 km — and we could not
reproduce −100 kJ kg⁻¹ from `cv(T − T₀) + Φ`. Something specific sets this offset
and we do not know what. Until someone does, "shift by 100 kJ kg⁻¹" is a
prescription written against a number whose origin is unverified.

## A third shape, for completeness

A reference-free *rule* is constructible, and the codebase already contains the
pattern: `water_tag_sediment_share` divides each clamped share by the sum of the
clamped shares, and its docstring says the renormalisation "is what preserves
exact closure". Transplanted to energy, `φₖ = ρe_src_k / Σⱼ ρe_src_j` gives
`Σφ = 1` exactly, with no reference anywhere.

It does not rescue the situation. For the partition tags `Σⱼ ρe_src_j` *is*
`ρe_tot`, so it returns to the starting point; and taking absolute values or
including source tags to avoid that lets the denominator pass through zero
dynamically rather than being negative in a known, static 43% of cells. After
A5, trading a predictable sign problem for an unpredictable one is the wrong
direction.

## The deeper point

The donor rule needs a positive-definite measure of how much each tag holds.
That exists for water because mass has a physical zero. It does not exist for
total energy at any reference, because the zero is a convention.

So no shift repairs the reading. A shift relocates the arbitrariness — option 1
into every share, option 2 into the definition of the total — but it cannot
manufacture a physical zero. "What fraction of the energy here came from
radiation" is ill-posed in principle, not merely awkward in practice.

"How much energy did radiation add here since t = 0" is well posed and
reference-independent. That is what `energy_process_record` measures, and it is
the alternative `energy_source_tags.md` already names.

**C1 can test whether a well-posed donor rule is achievable. It cannot test
whether the reading is meaningful.** That is worth stating before the run, so the
result is not read as answering more than it can.

## Recommendation, in order

1. **Run C3 first.** It needs no code change, no approval, and is already
   written. It shows what the process record reads on a configuration where the
   source tags' own rule is not running — the fallback, measured. If only one
   thing runs next, this is it.
2. **Do the free diagnostic before choosing a shift.** At t = 0 the region tags
   sum to `ρe_tot` exactly, so **C0's existing NetCDF already contains the
   `e_tot` field** — add `e_src_strat + e_src_tropo` on the column, or the
   tropics pair on the sphere. If it is still on scratch, looking at *where* it
   is negative costs nothing and answers whether `c` is 10 or 100 kJ kg⁻¹,
   whether the region is a thin layer or the bulk troposphere, and whether the
   −100 kJ kg⁻¹ figure means what it appears to. Every magnitude argument above
   depends on this and nobody has looked.
3. **Test the depth hypothesis for one cheap run.** The docs attribute the
   non-positive parent to shallow domains; C0 found 43.276% at
   `z_max` 30 km. `config/common_configs/numerics_sphere_he6ze31.yml` is already
   in the repo at `z_max` 60 km with `z_elem` 31. If depth drives it, that should
   move the fraction, and it separates "domain artifact" from "intrinsic to the
   reference" for the price of one sphere run and no code.
4. **Then C1 as option 2, implemented as a reference-constant change and not a
   state offset**, if the family is still to be made to work as designed.

## What is not established here

- Whether the thermodynamic reference is tunable from configuration.
- The origin of the −100 kJ kg⁻¹ offset.
- Whether the suppression cost matters, which depends on the magnitude from
  step 2.

None of these needs a Levante run. All three are cheaper than C1.
