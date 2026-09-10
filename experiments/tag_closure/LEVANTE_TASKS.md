# Levante task list

Self-contained. The state, what was found, what to run, and what is still open.
Nothing below requires reading another document first.

Branch `claude/tag-closure-experiments`. Written at `1a9a419`, revised after
the reference probe answered the convention question.

## Where things stand

17 of 25 runs are live in `output/`. **Phase A and phase C are both complete**
except for C1 and C2, which need approval. The pre-fix A5 reading is kept
alongside its re-run under `output/a5_sphere_limiter/before_issue_64_fix/`,
because it measures the bug issue #64 names rather than a residual.

**Decided by measurement.** Moving the water tags into the implicit solve is not
worth its Jacobian cost. The default van Leer ladder is flat, slope −0.011,
while both linear ladders converge (+0.255 and +0.464), and at `dt` 10 s the
fully linear reconstruction sits 13.8× lower. The residual is limiter-bounded,
not discretization-bounded, so implicit tags would remove the part that is not
there.

**Issue #64 has a fix on this branch.** The water tags diverged to 1e130 on a
one-day sphere with the SEM limiter while `ρq_tot` stayed bounded, and the run
exited 0 reporting success. The unbounded multiplicative rescale ratio is now an
additive redistribution whose removal is floored at the cell's positive content,
and a new `abort_above` level ends a run that passes it — water defaults to 1.0,
which no honest non-negative partition of a non-negative parent can reach.
**Re-run at `8ed98b6`, and it holds.** `gross_relative` ends the day at
2.79e-4 where it reached 5.9e113 before, exit 0, the abort level never
approached, and it plateaus rather than merely staying finite. It did not get
there by emptying the tags: `nonpositive_fraction` is unchanged at 0.35 to 0.36
and the signed residual is −7.5e-6 relative, so the tags track the parent over a
third of the domain that holds non-positive water. Phase A also gains the sphere
operator residual it never had — `max |q_tag_res|` 1.9e-5 and flat.
`LEARNINGS.md` has the reading. Two loose ends in task 1.

**Measured by C0.** The source-tag donor rule is inert over 96.7% of the DYCOMS
column and 43.276% of a moist sphere. Production accumulates without loss, and a
source tag reaches −209 J kg⁻¹ on the sphere while `e_src_res` shows nothing,
because the residual sums only the pure region tags.

**The negative region is the troposphere.** On the sphere every level from 250 m
to 11.0 km is 100% negative and every level from 15.5 km up is 0% negative, with
no mixed level; `0.43276 × 30 km = 12.98 km` places the sign change between
them. The vertical structure is geopotential as it should be — `e_tot` swings
212 kJ kg⁻¹ between 250 m and 26.9 km against `gz` = 264 kJ kg⁻¹. The column is
negative at all 30 levels with a clean step at 825 m where the DYCOMS inversion
is. The shape is right; what is wrong is an offset. Smallest shift making the
field positive: 45.4 kJ kg⁻¹ on the column, 100.4 kJ kg⁻¹ on the sphere.

**The offset is a convention, not an initialisation error.** This was the fork
that gated C1 and it is now closed. The parameters are standard — `T_0` 273.16,
`cv_d` 717.5, `e_int_v0` 2.37473666e6 — and `TD.total_energy` called with the
model's own signature returns −44,009 J kg⁻¹ against the field's −43,125, the 2%
gap being the approximated DYCOMS state. **The function reproduces the field.**
So C0's 43.276% is a fact about the energy reference, the C0 entry and the
memo's Part 3 source bullet stand as written, and C1 is legitimate rather than a
treatment of a symptom.

**The convention is enthalpy zero, and that is now read from the source rather
than inferred.** Thermodynamics defines
`internal_energy_dry(T) = cv_d·(T − T_0) − R_d·T_0`, and the probe returned
`internal_energy_dry(273.16) = −78396.92`, which is `−R_d·T_0` to the last
digit at `R_d` = 287.0. So `e_d = cv_d·T − cp_d·T_0`, and the model's own
Jacobian already writes it that way: `manual_sparse_jacobian.jl:835` has
`ᶜkappa_m * (T_0 * cp_d − ᶜK − ᶜΦ)`. The constants are
`R_d` 287.0, `R_v` 461.5, `cv_d` 717.5, `cv_v` 1397.5, `cv_l` 4181.0,
`cp_d` 1004.5.

**The shift in `T_0` is cheaper than the textbook estimate, not dearer.**
`∂e_d/∂T_0` is `−cp_d` = −1004.5, not `−cv_d` = −717.5, so the factor is
`cp_d/cv_d` = 1.4 exactly and it points the other way. The sphere's 100.4 kJ
kg⁻¹ needs `ΔT_0` = 100.0 K, so `T_0` 273.16 → 173.2 K; the column's 45.4 kJ
kg⁻¹ needs 45.2 K, so `T_0` → 228.0 K. **An earlier draft of this file said the
factor was about 2.5 in the other direction. That was wrong and is struck.**

**What that opens instead, and it is larger.** `T_0` is not a free datum.
`LH_v(T) = LH_v0 + (cp_v − cp_l)·(T − T_0)` with `cp_v − cp_l` = −2322, so
holding `LH_v0` fixed while moving `T_0` to 173.2 K drops the latent heat of
vaporisation at 288.3 K from 2.4656e6 to 2.2335e6, **−9.4%**. That is a physics
change, which is exactly what option 2 was chosen to avoid. C1's remaining
shape therefore has to co-adjust `LH_v0`, `LH_s0` and `LH_f0` by the same
`ΔT_0`, and the saturation-vapour-pressure path has to be checked too, since it
integrates Clausius–Clapeyron from a reference of its own. That is being
written up in `C1_reference_shift.md`.

**The coupling is confirmed, and C1 turns out to need no code change.** The
probe returned `LH_v(288.3) = 2.46564492e6`, which is
`LH_v0 + (cp_v − cp_l)(288.3 − T_0)` to every digit, and `LH_f(273.16)` =
333600.0, so `LH_f0` is that and `LH_s0 = LH_v0 + LH_f0` = 2.8344e6. The
settable fields include `T_0`, `LH_v0` and `LH_s0` and exclude `LH_f0`, every
`cv_*` and `e_int_v0`, so those are derived and follow for free. The invariance
this gives is the useful part: everything physical depends on `T_0` only through
the group `LH_0 − Δcp·T_0`, so moving `T_0` by `δ` and `LH_v0` by
`(cp_v − cp_l)·δ` and `LH_s0` by `(cp_v − cp_i)·δ` leaves every latent heat and
the saturation vapour pressure **exactly** unchanged while moving `e_int` by
`−cp_d·δ`. C1 is three TOML entries, not a fork and not a model edit, and
`p_sat(288.3) = 1721.1532852305072` is the before-value that proves it. Task 2.

## Once per shell

```bash
cd ~/git/ClimaAtmosResiDyn.jl
git pull origin claude/tag-closure-experiments
export JULIA_DEPOT_PATH="$HOME/.julia/depots/levante-cpu"
```

The depot export matters. The runscripts use that depot, so an instantiate or a
script run under a different one will not be seen by a batch job.

## 1. Two loose ends from the A5 re-run

The run itself is done and the fix is confirmed. Neither of these changes the
conclusion; both are cheap and one of them is a possible bug.

**a. The audit table is missing.** `a5_sphere_limiter.yml` sets `audit: true`,
and the copy committed beside the results has it too, but no
`water_tag_audit.csv` came back. Check the scratch output directory first:

```bash
ls ~/git/ClimaAtmosResiDyn.jl/output/a5_sphere_limiter/output_0001/
```

If it is there, copy it in beside the other files and the two NaN columns in
`summary_a.csv` fill themselves. **If it is not there, that is a bug** — the
audit is requested and not written — and it is worth an issue, because the audit
is the diagnostic that separates a residual from a runaway on sight and nothing
else does.

**b. A5 is not in the summary or the plots.** `summary_a.csv` carries
`a1_dt10_notags` and no A5 row, so `phase_a.jl` ran before the A5 files were
copied in. One command:

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_a.jl
```

Do it after (a), so the run only has to be reduced once.

## 2. Write the C1 TOML, which is now a three-line change

The convention and the coupling are both settled, so what is left is mechanical.
Two things are still missing and one command gets both.

```bash
julia +1.11 --project=.buildkite -e '
    import ClimaParams
    import Thermodynamics as TD
    tp = TD.Parameters.ThermodynamicsParameters(Float64)
    println("cp_i = ", TD.Parameters.cp_i(tp))
    println("cp_v = ", TD.Parameters.cp_v(tp), "  cp_l = ", TD.Parameters.cp_l(tp))
    println("LH_s0 = ", TD.Parameters.LH_s0(tp))
    println(pkgdir(ClimaParams))'
```

```bash
grep -n -B4 'alias = "\(T_0\|LH_v0\|LH_s0\)"' <that dir>/src/parameters.toml
```

`cp_i` sets `LH_s0`'s coefficient and is the one constant we do not have. The
grep gives the long ClimaParams names, which are what a TOML override file keys
on — the struct field names above are aliases, not table headers.

**The recipe, for `δ = −99.95 K`** (the sphere's 100.4 kJ kg⁻¹ at `cp_d`):

| field   | now      | after                            |
|:------- |:-------- |:-------------------------------- |
| `T_0`   | 273.16   | 173.21                           |
| `LH_v0` | 2.5008e6 | 2.7328839e6                      |
| `LH_s0` | 2.8344e6 | 2.8344e6 + (cp_v − cp_i)·δ       |

`LH_f0` is derived as `LH_s0 − LH_v0` and comes out right on its own: it needs
`(cp_l − cp_i)·δ` and that is what the two entries above give it.

**The acceptance test is exact, and the before-values are already recorded** in
`LEVANTE_TASKS_RESULTS.md`. After the change these three must come back
*unchanged*:

```
LH_v(288.3) = 2.46564492e6
LH_f(273.16) = 333600.0
p_sat(288.3) = 1721.1532852305072
```

and `internal_energy_dry(288.3)` must move from −67533.97 to +32865.8, a shift
of +100,399.8 J kg⁻¹. If a latent heat or `p_sat` moves, the co-adjustment is
wrong and the run would be measuring a different atmosphere rather than a
different reference. Do not submit C1 until all four hold.

**One thing to watch.** `T_0` currently equals `T_triple` and `T_freeze`, all
273.16. The recipe moves `T_0` alone, which is correct — the other two are
physical temperatures — but it breaks a coincidence that has almost certainly
never been exercised, since nothing in this repository has ever overridden a
thermodynamic parameter. The acceptance test above is what would catch it.

**Still true, and unaffected:** the plumbing reaches these from configuration.
`create_parameters.jl:75` builds the thermodynamic parameters entirely from the
TOML dict and `Parameters.jl:602` forwards every field, so C1 is a configuration
change. It still needs the owner's approval; it no longer needs a code change.

## 3. C3 — done, and it is the result the series was for

Nothing to run. Recorded here because it is the strongest finding so far.

C3 reproduces `c0_column` bit for bit — `gross_relative` 0.13456131085846748,
`max_abs_e_src_res` 26888.66561703798, most-negative tag −44972.50629142498, all
identical — so the process record perturbs nothing and is a pure diagnostic
sitting beside the tags. On the same run, over the same day:

| reading of what radiation did    | range (J kg⁻¹)   |
|:-------------------------------- |:---------------- |
| source tag `e_src_rad`           | −2e-9 … +4,321   |
| process record `e_prc_radiation` | −20,566 … +7,587 |

The source tag is pinned at zero from below, because `energy_source_fraction`
returns 0 where `ρe_tot ≤ 0` and that is 29 or 30 of 30 levels. The record says
the larger excursion is cooling, −20.6 kJ kg⁻¹, and cloud-top radiative cooling
is the entire point of a DYCOMS stratocumulus column. **The source tag misses
the dominant term.** The warming half disagrees by 1.75× as well.

So the alternative `energy_source_tags.md` names is demonstrated rather than
merely available, on exactly the configuration where the tags are inert, and it
is reference-independent so nothing about C1 can touch it.

## 4. The timing controls — run, but not yet readable

Both jobs ran. `a1_dt10_notags` and `c0_column_notags` came back with only
`.yml` and `provenance.txt`, no `.out`, so there is no `sypd` and no
`wall_time_per_timestep` to compare. Copying the two logs in is all that is
needed:

```bash
cp ~/git/ClimaAtmosResiDyn.jl/output/a1_dt10_notags/output_*/*.out \
   experiments/tag_closure/output/a1_dt10_notags/
cp ~/git/ClimaAtmosResiDyn.jl/output/c0_column_notags/output_*/*.out \
   experiments/tag_closure/output/c0_column_notags/
```

The job wall times in `provenance.txt` cannot substitute. They give 235 s
against 295 s and 243 s against 295 s, but `a1_dt10` is one hour and
`c0_column` is a full day and both took 295 s, so compilation dominates and
those numbers compare compile time rather than tag cost. `a1_dt10` reported
`sypd 3.012` and 9 ms per timestep; that is the figure the controls have to be
read against.

## After any batch job

Check the exit status rather than only the log, because a crashed solve returns
`:simulation_crashed` and the driver's non-zero exit is what makes that visible.
A5's re-run exited 0 and never approached its abort level, so that
configuration is no longer expected to stop early.

```bash
sacct -j <jobid> -o JobID,State,ExitCode
```

Reduce before copying anything back, because the operator residual and the audit
table live beside the NetCDF and the NetCDF stays on scratch:

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/reduce_run.jl output/<run>/output_active
```

Then the five files per run into `experiments/tag_closure/output/<run>/`: the
family's `*_tag_closure.csv`, the reduced tables, the audit table where the run
wrote one, `<run>.yml`, `provenance.txt`, and a trimmed `run.log`. The analysis
refuses any run whose `provenance.txt` records `commit: unknown`.

Then the phase script, `phase_a.jl` or `phase_c.jl` as appropriate.

## Lower priority

**`c0_sphere_deep`, the 60 km sphere.** It was written to separate a domain
artifact from a property of the reference, and `where_negative.jl` already
answered that: the sign change is at the tropopause, not at the domain top, so a
deeper domain adds positive levels above and lowers the fraction without
changing anything physical. It keeps one distinct value — it now sets
`audit: true`, and `nonpositive_mass_fraction` is the share of the field's
*mass* that sits where the shares are undefined, which nothing else here can
produce. `where_negative.jl` works on the remapped lat-lon grid and has no cell
volumes, so it says where the field is negative but not how much of it is.

## Not yet, and why

**Phase B, and a correction to why.** The reason recorded here was that B1 is
ten days on a sphere with a limiter, in the regime that diverged in three hours
in A5. **Both halves of that are wrong.** `b1_base` configures no limiter at
all — only `b3_limiter` does, which is the whole point of the pair — and phase B
is the *energy* family, which has no `rescale_water_tags!` and no partition
repair, as `is_tagged_tracer_name`'s docstring says in as many words. #64's
mechanism was a multiplicative rescale amplifying the closure error, and there
is no rescale on that path to amplify anything.

So the A5 re-run never gated phase B on the evidence, and it has now run
anyway. What it bounds is the *unlimited explicit transport* the energy tags
share, and the news there is good: on a sphere at `h_elem` 4 the residual
plateaus at 2.79e-4 over a full day rather than running away. **Phase B has no
technical objection left.** Whether it is worth ten days of queue is the owner's
call on cost, not on risk. B2 is dry and unaffected either way.

**C1.** It needs the owner's approval and the two values task 2 collects. It no
longer needs a code change or a choice of shape. Of the two shapes in the memo,
shifting only the share's denominator should be dropped rather than costed: the
region tags sum to `ρe_tot` and not to `ρe_tot + c`, so wherever `e < 0` the
shares sum to a negative number and the loss adds energy
instead of removing it, diverging as `e` approaches `−c` — over exactly the
region the shift was introduced to fix. The remaining shape is a change of the
thermodynamic reference constant, not an offset added to the state.

Its costs are now firm rather than conditional. The shift must clear the
*tropospheric* minimum, so it cannot be made small; the discriminating part of a
source tag's share is proportional to `1/(e+c)`, so the donor rule becomes
several times less discriminating where it already works; the closure check
normalises by `∫|ρe_tot|`, which the shift grows about 2.2×, so the same
absolute residual would report a smaller relative one and read as an improvement
that did not happen.

**And one more, now that the magnitude is known.** The shift is a move in `T_0`
of 100 K on the sphere, and `T_0` anchors the latent heats. Left alone it takes
`LH_v` at 288.3 K down 9.4%, which is a different atmosphere and not a change of
reference — the exact thing this shape was chosen over the state offset to
avoid. So the shape has to move `LH_v0`, `LH_s0` and `LH_f0` with it, and the
saturation-vapour-pressure path needs checking as well. Task 2 confirms the
coupling from the running package; `C1_reference_shift.md` carries the
argument.

**A3's companion.** A3 differs from `a1_dt10` in two keys,
`microphysics_model` and `vert_diff`, so the gap between them is not the 1M
mismatch alone. Separating it needs one extra 0M column run with `vert_diff` on.
The config is deliberately not written.
