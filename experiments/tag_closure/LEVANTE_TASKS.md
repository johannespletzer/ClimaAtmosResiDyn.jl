# Levante task list

What to run next, and what each run is for. Every task carries what it needs, so
none of them requires opening another document first.

Branch `claude/tag-closure-experiments`.

## Where things stand

19 of the 28 configured runs are live in `output/`. A run is live when
`output/<run>/provenance.txt` exists, so `ls output` is the register.
`c0_sphere_deep` is dropped rather than pending — see *Not yet, and why*.

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

## Once per machine

`.buildkite/LocalPreferences.toml` is generated rather than tracked, and without
it Julia fails in ways that do not name the cause. The first attempt in this
series died on `Missing source file for base pkg Statistics`, which was exactly
this. Run the setup once:

```bash
./runscripts/setup-julia-levante.tcsh cpu
```

It prints the depot and modules to use afterwards, and it is shared with the gpu
stack, so re-run it when switching. `AGENTS.md` records the same rule under
*Local norms*, added by #67.

## Once per shell

```bash
cd ~/git/ClimaAtmosResiDyn.jl
git pull origin claude/tag-closure-experiments
export JULIA_DEPOT_PATH="$HOME/.julia/depots/levante-cpu"
module load gcc/11.2.0-gcc-11.2.0 openmpi/4.1.2-gcc-11.2.0
```

The depot export matters. The runscripts use that depot, so an instantiate or a
script run under a different one will not be seen by a batch job. The modules
matter for the interactive Julia calls below; the batch scripts load their own.

## 0. What has never been run, because no session so far had Julia

Everything in `analysis/` was written and reviewed by reading. Three things
should happen before the analysis is trusted, and all three are cheap.

**a. The self-test.** It has not run since `ce76919` added `is_ladder_rung` and
the `vert_diff` column, nor since the audit pass changed `tables.jl` and
`phase_a.jl`. It is the only check that the analysis does what its comments say.

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/selftest.jl
```

**b. The two phase passes.** `summary_a.csv`'s audit columns are still NaN
because the A5 results and its audit table landed on either side of the last
run, and `summary_c.csv` predates `c0_sphere_audit`.

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_a.jl
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_c.jl
```

**c. The formatter.** No session has run it, because none had Julia, and no pull
request exists for this branch so CI has not run it either. JuliaFormatter
formats markdown here (`format_markdown = true`), so every document in this
directory except `README.md` is in scope and none has been through it.

```bash
prek run julia-formatter --all-files
```

## 1. C1 — approved, submit it

**Approved 2026-09-10: the sphere, at `δ` = −110 K.** Both files are written and
validated.

```bash
CONFIG=experiments/tag_closure/configs/c1_sphere_shift.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh
```

**Run the acceptance test before trusting the output.** It is in the TOML's
header, and it is the only thing standing between a change of reference and an
accidental change of atmosphere. Then check the run's own parameter log:
`c0_sphere_audit` wrote `c0_sphere_audit_parameters.toml` beside its results, so
C1 writes its own, and that file is direct proof the three overrides bound
rather than silently falling back to defaults.

**What to read, and what not to.** `nonpositive_fraction` should be 0.0 at every
sample against 0.43276 unshifted, and the per-tag minima should stay
non-negative — unshifted, a source tag reached −209 J kg⁻¹.
**`gross_relative` is not comparable with `c0_sphere`'s**, because the shift
grows the normalising scale about 2.2× and the same absolute residual then reads
smaller. Compare the absolute `gross_residual` column. The audit columns say
whether the *direction* changed: unshifted they run 3.85 to 1 in favour of
overclaim, which is production with no loss.

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

## 2. C3 — done, and it is the result the series was for

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

## 3. The timing controls — measured, both pairs

The `.err` files came back and the A1 pair reads clean:

|                   | tagged   | untagged | ratio |
|:----------------- |:-------- |:-------- |:----- |
| `solve! walltime` | 3.337 s  | 0.548 s  | 6.09  |
| `sypd`            | 2.956    | 17.992   | 6.09  |
| per timestep      | 9.269 ms | 1.522 ms | 6.09  |

**Do not read 6.1× as the cost of the tags.** `a1_dt10` runs
`water_closure_check` at `period: "10secs"` against a `dt` of 10 s, so a global
reduction fires on every timestep, and diagnostics every 60 s on top. That is a
diagnostic choice, not what carrying tags costs.

**The C0 pair settles it, and both halves are now in `output/`** — three source
tags with the closure check and diagnostics both hourly, over 8640 steps instead
of 360:

|                   | tagged   | untagged | ratio |
|:----------------- |:-------- |:-------- |:----- |
| `solve! walltime` | 11.225 s | 8.521 s  | 1.317 |
| `sypd`            | 21.088   | 27.779   | 1.317 |
| per timestep      | 1.299 ms | 986.3 µs | 1.317 |

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

## 4. The two runs that just landed

`c0_sphere_audit` and `a3_0m_vert_diff` have both run and are analysed.
`c0_sphere_deep` is dropped. C1, in task 1, is the only thing left to submit.

**What the two runs said**, since both changed a number quoted elsewhere:

  - `c0_sphere_audit` measured `nonpositive_mass_fraction` = **0.7839** against
    the volume fraction's 0.43276. So **78.4%** of `∫|ρe_tot|` sits where the
    donor share is undefined, not 43.3%: the headline understated the barrier by
    1.8×, because the non-positive region is the troposphere and that is where
    the field's magnitude is. Its residual is also directional — overclaim beats
    undertag 3.85 to 1 — where A5's water residual split evenly.
  - `a3_0m_vert_diff` settled A3. Vertical diffusion accounts for 27× of the
    29× gap and 1M for 7%, and holding `vert_diff` fixed, 1M moves the residual
    7% **down** rather than up. The `q_tot_eff` mismatch the memo expected to
    cost closure is not measurable on a column.

## Not yet, and why

**`c0_sphere_deep`, dropped 2026-09-10.** It was written as a depth control, and
`where_negative.jl` answered that question independently: the sign change is at
the tropopause, not the domain top. Its other purpose,
`nonpositive_mass_fraction`, has been measured by `c0_sphere_audit` on the
configuration that actually produced 43.276%. What is left is a 60 km domain on
a different grid carrying hyperdiffusion and two sponges the shallow sphere
leaves off, so its number would need three caveats and pair with nothing. The
config stays in the tree, fixed and validated, if the depth reading is ever
wanted.

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

**C1.** Approved and ready to submit; see task 1. It no
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
saturation-vapour-pressure path needs checking as well. Task 1 confirms the
coupling from the running package; `C1_reference_shift.md` carries the
argument.

**A3's companion.** Written, validated and reported in task 4 as
`a3_0m_vert_diff`. It is not in this section any more; it needs no approval and
only the queue.
