# Which reference shift for C1

A recommendation, not a decision. C1 still needs the owner's approval, but it no
longer needs a model change: it is three TOML entries. This page says what the
two shapes in [the memo](../../docs/src/tag_closure_memo.md) actually do, why
one of them should be dropped rather than costed, and what the reference change
actually costs now that its arithmetic is pinned.

Written after C0, revised once the reference convention was read on Levante, and
revised again once the latent-heat coupling was confirmed against the package.
Every code reference below was checked against the tree. Where an earlier draft
got something wrong, the correction is marked rather than quietly applied.

## The question

The energy source tags deplete each tag in proportion to its donor share
`φₖ = ρe_src_k / ρe_tot`. Where `ρe_tot ≤ 0` the share is undefined and
`energy_source_fraction` returns zero, so the loss half of the rule does not run
while production still does.

C0 measured how much of the domain that is: **96.7% of the DYCOMS column** for
the whole day after one level crosses at 8 h, and **43.276% of a moist sphere,
constant to the last digit across 24 hours**. On the column the `rad` tag grew
from 0 to 4321 J kg⁻¹ with the loss inert, and it does not lose anything until
the hour in which a level first turns positive.

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

If C1 is run as option 2, it must be the second.

### It is reachable from configuration

Checked, and the answer is yes, though one detail still needs a command on
Levante to pin down.

`src/parameters/create_parameters.jl:75` builds the thermodynamic parameters as
`ThermodynamicsParameters(toml_dict)` — that is, **entirely from the TOML dict**,
with no hard-coded values in ClimaAtmos. `src/parameters/Parameters.jl:602`
then forwards every field of that struct, so whatever the reference is, it is a
field, and every field comes from a ClimaParams entry. A configuration reaches
it through the `toml:` key (`default_config.yml:394`), which is the same
mechanism `toml/longrun_baroclinic_wave.toml` uses for
`precipitation_timescale`.

**So option 2 is a configuration change, not a dependency change.** It needs a
TOML file and a `toml:` line, not a fork of Thermodynamics.jl. That removes the
largest unknown in its cost.

One of the two things this left open is now settled. The other is not.

  - **The parameter's name.** Half answered. The settable fields have since been
    listed and `T_0`, `LH_v0` and `LH_s0` are all among them — see *Which turns
    out to make C1 cheap* below. What is still missing is the long ClimaParams
    name each one keys on, because a TOML override file uses those as table
    headers rather than the struct field names. No ClimaParams source is
    available here and no TOML in `toml/` overrides a thermodynamic parameter,
    so the mechanism is unexercised in this repository and there is no local
    example to copy from. The pinned versions are Thermodynamics 1.3.0 and
    ClimaParams 1.1.6 (`.buildkite/Manifest-v1.11.toml`).

  - **Whether the shift is actually constant.** **Settled: it is not.** The
    coefficient is `c(q) = q_d·cp_d + q_v·cp_v + q_l·cp_l + q_i·cp_i`, so the
    shifted parent is `e_tot + c(q)·ΔT_0` rather than `e_tot + c`. The first
    draft guessed `ΔT·(cv_m + q_vap·R_v)`, which is the same expression except
    that it carries `cv_d` on the dry part where the measured convention
    requires `cp_d`. Across the moisture range `c(q)` runs from 1004.5 dry to
    1021.6 at `q_tot` = 0.02, a spread of **1.7%**, and liquid water widens it
    because `cp_l` is four times `cp_d`.

    This does not break the closure identity, and the first draft implied it
    might. The tags are shares of the same recomputed `ρe_tot`, so both sides
    move together and `Σ tags = ρe_tot` still holds exactly. What it does mean
    is that "the shift" has no single value, so whether the field is positive
    *everywhere* has to be checked pointwise. That happens to help: the largest
    `c(q)` sits in the warm moist low levels, which are the most negative.

## Costs the memo does not count

Two of them here, and a third — the one that should decide the shift's
shape — in the magnitude section below, because it only became visible once
the reference convention was read.

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

This was the weakest argument here, and it was sensitive to the magnitude of
`c`: a much smaller shift would have made it evaporate. The diagnostic has since
run. `where_negative.jl` puts the smallest sufficient shift at 45.4 kJ kg⁻¹ on
the column and 100.4 kJ kg⁻¹ on the sphere, because the negative region is the
whole troposphere rather than a thin layer. So `c` cannot be made small and this
argument stands rather than evaporating.

### It flatters the number you would judge it by

The closure check normalises by `scale = ∫|ρe_tot|`. Shifting the reference grows
that by roughly 2.2× over the sphere's range, so **the same absolute residual
reports a `gross_relative` about 2.2× smaller**. Comparing C1-under-option-2
against C0 is therefore not a comparison of residuals. The docs already warn that
tolerances are not comparable across references; this is that warning with a
number on it, and without care it would read as an improvement that did not
happen.

## The magnitude, and where the offset comes from

From C0's own tables, specific `e_tot` at t = 0 spans **−1.004e5 to +1.123e5
J kg⁻¹** on the sphere, and reaches −4.50e4 on the column. Making it positive
everywhere needs at least 100.4 kJ kg⁻¹, which is **100 K** of reference
temperature. That is not a nudge.

**The offset is now accounted for**, and it was the open question this document
was written around. From the Thermodynamics source on Levante:

```julia
@inline function internal_energy_dry(param_set::APS, T)
    T_0 = TP.T_0(param_set)
    cv_d = TP.cv_d(param_set)
    R_d = TP.R_d(param_set)
    return cv_d * (T - T_0) - R_d * T_0
end
```

and `internal_energy_dry(T_0 = 273.16)` returns **−78396.92**, which is exactly
`−R_d·T_0` with `R_d` = 287.0. Energy is referenced so that *enthalpy* vanishes
at `T_0`, not internal energy. **The 7.8e4 J kg⁻¹ discrepancy this document
could not explain is that term.** The textbook table below is not wrong about
the physics; it is written in the other convention.

This is not a foreign convention that ClimaAtmos merely inherits. The model's
own analytic Jacobian carries it explicitly at `manual_sparse_jacobian.jl:835`:

```julia
ᶜ∂p∂ρ = @. lazy(ᶜkappa_m * (T_0 * cp_d - ᶜK - ᶜΦ) + (R_d - ᶜkappa_m * cv_d) * ᶜT)
```

`T_0 * cp_d`, not `T_0 * cv_d`. So `e_int = cv_d·T − cp_d·T_0` for dry air, and
the reference term is `cp_d·T_0` throughout.

**What this changes for C1.** The derivative that sets the shift is
`∂e_int/∂T_0 = −cp_d`, so lowering `T_0` is *more* effective than the textbook
reading suggests, by exactly `γ = cp_d/cv_d = 1.4`. An earlier note put that
factor at 2.5 and in the other direction; that was wrong. Corrected:

| field  | shift needed  | ΔT_0 at `cp_d` | resulting `T_0` |
|:------ |:------------- |:-------------- |:--------------- |
| column | 45.4 kJ kg⁻¹  | 45.2 K         | 228.0 K         |
| sphere | 100.4 kJ kg⁻¹ | 100.0 K        | 173.2 K         |

The "roughly 140 K" this section used to quote was the same error.

**What was ruled out on the way**, all checked against this tree, and kept
because it is what narrowed the question to the convention:

  - **The numbers mean what we read them as.** `e_src_<name>` is specific,
    `units = "J kg^-1"` (`energy_source_tag_diagnostics.jl:51`), not a density.
    A region tag initialises to a masked share of `ρe_tot`
    (`energy_source_tags.jl:65`), so its extrema are `ρe_tot`'s extrema over
    that region.
  - **Nothing is customised in how energy is formed.** `ρe_tot = ρ *
    TD.total_energy(thermo_params, e_kin, e_pot, T, q_tot, q_liq, q_ice)` at
    `src/setups/common/prognostic_variables.jl:52`, with
    `e_pot = geopotential(grav, z)`. Calling that function directly on the
    DYCOMS surface state returns **−44,009 J kg⁻¹** against the field's
    −43,125, the 2% gap being the approximated state. The function reproduces
    the field.
  - **This repository overrides no thermodynamic reference.** Nothing in `toml/`
    or `src/parameters/` sets `T_0`, a triple point or `e_int_v0`; the only
    mention of the latter is the derived-parameter forwarding list at
    `Parameters.jl:607`.
  - **The initial state is ordinary.** DYCOMS RF02 takes `θ_liq_ice` and `q_tot`
    from AtmosphericProfilesLibrary with `p_0 = 101780.0` (`DYCOMS.jl:55-64`) —
    roughly 288 K and 9.45 g kg⁻¹ near the surface. Nothing exotic.

**The textbook arithmetic, kept for the contrast.** With `T_0` 273.16, `cv_d`
717.5, `cv_v` 1397.5, `R_v` 461.5, `LH_v0` 2.5008e6, the textbook
`cv_m(T − T_0) + q_v·e_int_v0 + gz` gives:

| state                                    | textbook `e_tot` (J kg⁻¹) |
|:---------------------------------------- |:------------------------- |
| DYCOMS surface, 288.3 K, 9.45 g/kg, z = 0 | +3.34e4                   |
| DYCOMS top, 288 K, 5 g/kg, z = 1500 m     | +3.73e4                   |
| sphere surface, 300 K, 15 g/kg, z = 0     | +5.52e4                   |
| sphere upper, 220 K, dry, z = 30 km       | +2.56e5                   |

Every one is positive, and every one sits `R_d·T_0` above what the model
reports, give or take the moisture correction. Nothing needs an effective
reference near 381 K, which this section used to propose; that figure was an
artifact of reading the gap as a temperature in the wrong convention.

**So C0's 43.276% is a fact about the energy reference, and C1 is legitimate
rather than a treatment of a symptom.** That was the fork this section existed
to resolve, and it is closed.

### The cost this exposes: `T_0` is not a free datum

This is the finding that should decide C1's shape, and neither the memo nor the
first draft of this page counted it.

The internal energies fix the latent heat. With `e_v = cv_v(T − T_0) + LH_v0 −
R_v·T_0` and `e_l = cv_l(T − T_0)`, and liquid taken incompressible so
`cp_l = cv_l`:

```
LH_v(T) = h_v − h_l = (e_v + R_v·T) − e_l = LH_v0 + (cp_v − cp_l)(T − T_0)
```

with `cp_v − cp_l` = 1859.0 − 4181.0 = **−2322.0** from the model's own
constants. At `T_0` = 273.16 that gives `LH_v(288.3)` = 2.4656e6, the right
physical value.

**Move `T_0` to 173.2 K with `LH_v0` held fixed and it becomes 2.2335e6, low by
9.4%.** That is a change of physics, not of reference — precisely what option 2
was chosen over option 1 to avoid. The same applies to `LH_f0` and `LH_s0`, and
the saturation vapour pressure inherits it through Clausius-Clapeyron.

So the shift is a change of the whole reference *set*, not of one number.
`LH_v0` and its siblings have to move by `(cp_v − cp_l)·ΔT_0` and the
equivalent, chosen so that every latent heat at fixed `T` is unchanged. That is
still a configuration change rather than a fork, but it is several coupled TOML
entries whose effects must cancel, and getting it wrong changes the climate
rather than the reading.

**Confirmed against the package.** The derivation above was made from the
model's constants rather than read from Thermodynamics, so it was probed:
`latent_heat_vapor(288.3)` returns **2.46564492e6**, and
`LH_v0 + (cp_v − cp_l)(288.3 − T_0)` is 2,465,644.92. Every digit.
`latent_heat_fusion(273.16)` returns 333600.0, so `LH_f0` is that and
`LH_s0 = LH_v0 + LH_f0` = 2.8344e6. The coupling is real.

### Which turns out to make C1 cheap, not expensive

The same probe listed the settable fields:

```
T_0, T_triple, T_freeze, T_icenuc, T_min, T_max, T_init_min, T_surf_ref,
T_min_ref, entropy_reference_temperature, MSLP, p_ref_theta, press_triple,
R_d, R_v, cp_d, cp_v, cp_l, cp_i, LH_v0, LH_s0, entropy_dry_air,
entropy_water_vapor, grav, pow_icenuc, q_min
```

`T_0`, `LH_v0` and `LH_s0` are all there. `LH_f0`, every `cv_*` and `e_int_v0`
are **not**, which confirms them derived — the guess at `Parameters.jl:607` was
right — and means they follow the three that are set without being touched.

The useful structure is an invariance. Everything physical depends on `T_0` only
through the group `LH_0 − Δcp·T_0`: the latent heats by construction, and the
saturation vapour pressure through the same group in its Clausius-Clapeyron
exponent. So the map

```
T_0   → T_0 + δ
LH_v0 → LH_v0 + (cp_v − cp_l)·δ
LH_s0 → LH_s0 + (cp_v − cp_i)·δ
```

leaves every latent heat and `p_sat` **exactly** unchanged while moving `e_int`
by `−cp_d·δ`. `LH_f0` needs `(cp_l − cp_i)·δ` and gets it for free, since it is
`LH_s0 − LH_v0` and the two coefficients differ by exactly that.

That changes what C1 is. It was "a code change, the owner's approval, and a
shape nobody had chosen". It is now three TOML entries under a `toml:` key, with
an acceptance test that is exact rather than a judgement call. With `cp_i` =
2070.0 from the probe, every entry is a closed number. For `δ` = −100.0 K:

| field   | now      | after     |
|:------- |:-------- |:--------- |
| `T_0`   | 273.16   | 173.16    |
| `LH_v0` | 2.5008e6 | 2.7330e6  |
| `LH_s0` | 2.8344e6 | 2.8555e6  |

`δ` = −100.0 K and not −99.9666, which is what 100416.4 J kg⁻¹ divided by
`cp_d` gives. The round number moves `e_int` by 100450.0 J kg⁻¹, which clears
the sphere's minimum by 33.6, and it makes all three entries exact in decimal.
An earlier draft used −99.95, which is 16.6 J kg⁻¹ **short** of the minimum it
was derived from; the moist `c(q)` of R9 would probably have covered that, but
an acceptance test advertised as exact should not depend on probably.

Afterwards `LH_v(288.3)`, `LH_f(273.16)` and `p_sat(288.3)` must return
2.46564492e6, 333600.0 and 1721.1532852305072 — the values recorded before the
change — while `internal_energy_dry(288.3)` moves from −67533.97 to +32916.03.
The first two are exact identities under the map and not approximations:
`LH_v(288.3)` is `2733000 − 2322 × 115.14`, and the derived `LH_f0` lands at
122500.0, which puts `LH_f(273.16)` back at `122500 + 2111 × 100`. If a latent
heat or `p_sat` moves, the run would be measuring a different atmosphere rather
than a different reference, and the result would not mean what C1 needs it to
mean.

One thing is still missing: the long ClimaParams names that a TOML override keys
on, since the field names above are aliases rather than table headers. They come
from one command, recorded in `LEVANTE_TASKS.md` task 2.

**And one thing to watch.** `T_0` currently equals `T_triple` and `T_freeze`, all
273.16. Moving `T_0` alone is correct, since the other two are physical
temperatures, but it breaks a coincidence that has almost certainly never been
exercised: nothing in this repository has ever overridden a thermodynamic
parameter. The acceptance test is what would catch it.

**This does not make the other costs go away.** The shift is still large enough
to suppress the discriminating part of the donor rule, still grows the closure
check's normalising scale by about 2.2×, and still cannot manufacture a physical
zero. What it removes is the implementation risk, which was the part that read
as expensive.

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

Steps 2 to 4 of the original list have been done and their results are folded
into the sections above. What is left:

1. **Run C3 first.** It needs no code change, no approval, and is already
   written. It shows what the process record reads on a configuration where the
   source tags' own rule is not running — the fallback, measured. It is also
   reference-independent, so nothing above can invalidate it. If only one thing
   runs next, this is it.
2. **Collect the ClimaParams names, then write the TOML.** One command, in the
   section above. The recipe and its acceptance test are fixed and every
   constant in them is now known; the table headers are what is left.
3. **Then C1 as option 2, implemented as the co-adjusted map above.** Moving
   `T_0` by itself is now known to be the wrong operation, not merely an
   unverified one, and the acceptance test distinguishes the two on sight.

## What is not established here

- The long ClimaParams names for `T_0`, `LH_v0` and `LH_s0`. The fields are
  confirmed settable; these are what a TOML file needs to actually name them.
- Whether `p_sat` is in fact invariant under the co-adjusted map. The argument
  is that it depends on `T_0` only through `LH_0 − Δcp·T_0`, which is structural
  rather than measured, and the recorded 1721.1532852305072 is the before-value
  that tests it.
- Whether anything in ClimaAtmos or Thermodynamics quietly assumes
  `T_0 == T_triple`. Nothing found, but nothing has ever moved them apart.
- Whether the suppression cost matters in practice. The magnitude is firm, so
  this is measurable rather than open in principle.

None of these needs a Levante run. All three are cheaper than C1.
