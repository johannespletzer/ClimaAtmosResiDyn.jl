# Levante task list

What to run next, and what each run is for. Every task carries what it needs, so
none of them requires opening another document first.

Branch `claude/tag-closure-experiments`.

## Where things stand

17 of the 28 configured runs are live in `output/`. A run is live when
`output/<run>/provenance.txt` exists, so `ls output` is the register.

**Phase A and phase C are both complete** apart from C1 and C2, which need the
owner's approval. What they concluded, one line each, with the evidence in
[FINDINGS.md](FINDINGS.md) under the tags given:

  - Implicit water tags are not worth their Jacobian cost. The residual is
    limiter-bounded, not discretization-bounded, so implicit tags would remove a
    part that is not there. *W1, W2.*
  - Issue #64's fix holds. A5 re-ran a full day ending at 2.79e-4 where it had
    reached 5.9e113, and the audit shows it did not get there by emptying the
    tags. *W6 to W12.*
  - The energy source tags' donor rule is inert over 43.276% of a sphere by
    volume, and C3 showed the process record reads the radiative cooling the
    tags miss entirely. *E1 to E9.*
  - The energy reference is enthalpy zero. The offset C0 could not account for
    is a convention rather than an error, and C1 is three TOML entries rather
    than a code change. *R1 to R11.*
  - Three source tags cost 32%. The closure check, not the tags, is what made
    the A1 pair look like 6×. *T1 to T5.*

The pre-fix A5 reading is kept beside its re-run under
`output/a5_sphere_limiter/before_issue_64_fix/`, because it measures the bug
issue #64 names rather than a residual.

## Once per shell

```bash
cd ~/git/ClimaAtmosResiDyn.jl
git pull origin claude/tag-closure-experiments
export JULIA_DEPOT_PATH="$HOME/.julia/depots/levante-cpu"
```

The depot export matters. The runscripts use that depot, so an instantiate or a
script run under a different one will not be seen by a batch job.

## 1. One more `phase_a.jl` pass

Both loose ends from the re-run are closed. The audit table came back, A5 is in
`summary_a.csv`, and so are its `final_overclaimed_relative` and
`final_orphaned_relative`. What is left is that `phase_a.jl` has since gained a
`vert_diff` column, which the committed summary predates and which is the one
column that will distinguish `a3_0m_vert_diff` from `a1_dt10`. One command:

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_a.jl
```

**The audit is worth reading before that.** It confirms the fix directly rather
than by inference. `untagged_relative` 1.3556e-4 plus `overclaimed_relative`
1.4307e-4 is exactly the closure table's `gross_relative`, so the two halves are
balanced to within 5% — a runaway is one-sided, this is not. `orphaned_relative`
is 2.5e-9, five orders below the residual, so the removal floor is not holding
closure by discarding tag content. That was the one outcome `gross_relative`
could not distinguish, and it is now excluded by measurement.

And `nonpositive_mass_fraction` is 2.77e-7 against a `nonpositive_fraction` of
0.351 — a factor of 1.3 million. Both are fractions **by volume**, not by cell
count. For water, "a third of the domain is non-positive" is about vanishingly
dry air and nothing else. See *Lower
priority*, where this changes a judgement.

## 2. C1 — written, waiting on approval

Nothing is missing any more. The convention, the coupling and the ClimaParams
table headers are all settled, and both files are written:
`toml/tag_closure_c1_reference.toml` and `configs/c1_sphere_shift.yml`. The raw
probe output the numbers come from is in `C1_reference_shift.md`'s appendix.

**What is left is the owner's approval.** C1 changes the model's energy
reference, so `ρe_tot` is a different number everywhere and `ref_counter` would
bump for any job adopting the shift. No code change; that is the whole of it.

**The recipe, for `δ = −110.0 K`.** The TOML carries the derivation, the
acceptance test and the reason for the margin:

| field   | now      | after     |
|:------- |:-------- |:--------- |
| `T_0`   | 273.16   | 163.16    |
| `LH_v0` | 2.5008e6 | 2.75622e6 |
| `LH_s0` | 2.8344e6 | 2.85761e6 |

`LH_f0` is derived as `LH_s0 − LH_v0` and comes out right on its own: it needs
`(cp_l − cp_i)·δ` = −232210, and 2857610 − 2756220 = 101390 is exactly that.

The sphere's minimum needs 100416.4 J kg⁻¹ and `δ` = −110.0 K delivers 110495.0,
about 10% of margin. An earlier version of this table used −99.95 K, which
delivers 100399.8 and is 16.6 J kg⁻¹ **short** of the minimum it was derived
from; it also left `LH_s0` as a formula rather than a number. Both are fixed.

**The acceptance test is exact**, and the before-values are recorded in
`C1_reference_shift.md`'s appendix. After the change these three must come back
*unchanged*:

```
LH_v(288.3) = 2.46564492e6
LH_f(273.16) = 333600.0
p_sat(288.3) = 1721.1532852305072
```

and `internal_energy_dry(288.3)` must move from −67533.97 to +42961.03, a shift
of +110,495.0 J kg⁻¹. If a latent heat or `p_sat` moves, the co-adjustment is
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

## 4. The timing controls — measured, both pairs

The `.err` files came back and the A1 pair reads clean:

| | tagged | untagged | ratio |
|:-------------------- |:------- |:-------- |:----- |
| `solve! walltime` | 3.337 s | 0.548 s | 6.09 |
| `sypd` | 2.956 | 17.992 | 6.09 |
| per timestep | 9.269 ms | 1.522 ms | 6.09 |

**Do not read 6.1× as the cost of the tags.** `a1_dt10` runs
`water_closure_check` at `period: "10secs"` against a `dt` of 10 s, so a global
reduction fires on every timestep, and diagnostics every 60 s on top. That is a
diagnostic choice, not what carrying tags costs.

**The C0 pair settles it, and both halves are now in `output/`** — three source
tags with the closure check and diagnostics both hourly, over 8640 steps instead
of 360:

| | tagged | untagged | ratio |
|:-------------------- |:--------- |:---------- |:----- |
| `solve! walltime` | 11.225 s | 8.521 s | 1.317 |
| `sypd` | 21.088 | 27.779 | 1.317 |
| per timestep | 1.299 ms | 986.3 µs | 1.317 |

**1.32×, not 6.1×.** Same three tag families; the difference between the pairs is
that A1 fires the closure reduction on every timestep and C0 fires it hourly. So
the check is most of A1's factor, which is what the paragraph above predicted.
Nothing left to collect here.

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

## 5. Three runs, none needing approval

`c0_sphere_deep` was submitted and died before the solve started:

```
AssertionError: Implicit vertical diffusion is only supported when using a
turbulence convection model or vertical diffusion model.
check_case_consistency, model_getters.jl:1074
```

**Fixed.** The config copied `implicit_diffusion: true` out of
`numerics_sphere_he6ze31.yml`, which is a numerics-only common config that
expects its partner to supply a diffusion model — the repository's own consumer
of that grid sets `vert_diff: VerticalDiffusion` and then overrides the key back
to `false`. This run has no diffusion model and should not gain one, so the key
is dropped instead. That costs nothing: `diff_mode` gates exactly one tendency,
`vertical_diffusion_boundary_layer_tendency!`, which is a no-op when
`vertical_diffusion` is `nothing`. The sponges do not go through it.

`validate_configs.py` now mirrors that assertion, so this class of failure is
caught before the queue rather than after it. 27 configs, 16 of 16 mutations.

**Run `c0_sphere_audit` first.** It is `c0_sphere` with `audit: true` and
nothing else changed, and it is a better answer to the question
`c0_sphere_deep` was promoted for. The number wanted is the mass-weighted
companion to C0's **43.276%**, which is a volume fraction quoted throughout the
series. `c0_sphere_deep` is a 60 km domain on a different grid with
hyperdiffusion and two sponges the shallow sphere leaves off, so its mass
fraction would belong to a configuration that is not the one that produced
43.276%. Same cost either way: one sphere, one day.

```bash
CONFIG=experiments/tag_closure/configs/c0_sphere_audit.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh

CONFIG=experiments/tag_closure/configs/a3_0m_vert_diff.yml \
    sbatch experiments/tag_closure/runscripts/phase_a.sh

CONFIG=experiments/tag_closure/configs/c0_sphere_deep.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh
```

`a3_0m_vert_diff` is A3's companion, unchanged from the last list: `a1_dt10`
with `vert_diff: DecayWithHeightDiffusion` and nothing else, so it differs from
`a3_1m` in `microphysics_model` alone and from `a1_dt10` in `vert_diff` alone.
Two single-key comparisons out of one column-hour, where A3 alone gives a
two-key gap it cannot decompose. The fourth corner, 1M with `vert_diff` off,
stays unwritten: on a column the 1M mismatch reaches the tags through vertical
diffusion and nothing else.

`c0_sphere_deep` is now third rather than first. It still reads depth, and
`where_negative.jl` has already answered the question it was written for, so it
is the one of the three that could be dropped.

## Lower priority

**`c0_sphere_deep`, the 60 km sphere — promoted by the A5 audit.** It was
written to separate a domain artifact from a property of the reference, and
`where_negative.jl` already answered that: the sign change is at the tropopause,
not at the domain top, so a deeper domain adds positive levels above and lowers
the fraction without changing anything physical.

It keeps one distinct value, and A5 has just shown what that value is worth. It
sets `audit: true`, and `nonpositive_mass_fraction` is the share of the field's
own *magnitude* sitting where the shares are undefined. On A5 that number was
2.77e-7 against a volume fraction of 0.351 — a factor of 1.3 million — so for
water the alarming volume fraction is almost entirely empty air. For energy it
should go the other way, because `where_negative.jl` put the non-positive region
in the troposphere where the mass is. But **nobody has measured it**, and C0's
43.276% is quoted throughout this series as a volume fraction with no
mass-weighted companion. `where_negative.jl` cannot supply one: it works on the
remapped lat-lon grid and has no cell volumes, so it says where the field is
negative but not how much of it is. `c0_sphere_audit` is the run to use for it,
for the reason task 5 gives; this one would answer the same question on a
different grid and domain.

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

**A3's companion.** Written, validated and listed in task 5 as
`a3_0m_vert_diff`. It is not in this section any more; it needs no approval and
only the queue.
