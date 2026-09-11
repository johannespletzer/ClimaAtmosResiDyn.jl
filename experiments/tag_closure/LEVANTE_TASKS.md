# Task list

What to run next, and what each run is for. Every task carries what it needs, so
none of them requires opening another document first. The file name is
historical. The series started on DKRZ Levante, and since 2026-09-10 it also
runs on LRZ terrabyte.

Branch `claude/tag-closure-experiments`.

## Where things stand

24 of the 32 configured runs are live in `output/`. A run is live when
`output/<run>/provenance.txt` exists, so `ls output` is the register.
`c0_sphere_deep` is dropped rather than pending — see *Not yet, and why*.
The four `output/twin_c1*/` directories are not configured runs but checks on
C1, and `output/c0_sphere_audit/terrabyte/` is a second reading of that run.

**Phase A and phase C are both complete** apart from C2, which needs a code
change and the owner's approval. What they concluded, one line each, with the
evidence in [FINDINGS.md](FINDINGS.md) under the tags given:

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
  - With C1's positive reference the donor rule runs everywhere, and the residual
    stops being directional and falls to 0.70 of the unshifted one. The tags
    still go negative, and the shift changes the simulated atmosphere slightly,
    by up to 1.1e-3 in `uₕ`. *E11 to E16.*
  - Giving the tags their own positive total, `energy_source_tag_offset`,
    reproduces C1's tag results with the atmosphere left bit for bit alone.
    *E17 to E19, T7.*
  - Three source tags cost 32%. The closure check, not the tags, is what made
    the A1 pair look like 6×. *T1 to T6.*

The pre-fix A5 reading is kept beside its re-run under
`output/a5_sphere_limiter/before_issue_64_fix/`, because it measures the bug
issue #64 names rather than a residual.

## Once per machine

`.buildkite/LocalPreferences.toml` is generated rather than tracked, and without
it Julia fails in ways that do not name the cause. The first attempt in this
series died on `Missing source file for base pkg Statistics`, which was exactly
this. Run the setup once, for the machine you are on:

```bash
./runscripts/setup-julia-levante.tcsh cpu     # DKRZ Levante
./runscripts/setup-julia-terrabyte.tcsh cpu   # LRZ terrabyte
```

Each prints the depot and modules to use afterwards. On Levante the preferences
file is shared with the gpu stack, so re-run the setup when switching.
`AGENTS.md` records the same rule under *Local norms*, added by #67.

## Once per shell

On Levante:

```bash
cd ~/git/ClimaAtmosResiDyn.jl
git pull origin claude/tag-closure-experiments
export JULIA_DEPOT_PATH="$HOME/.julia/depots/levante-cpu"
module load gcc/11.2.0-gcc-11.2.0 openmpi/4.1.2-gcc-11.2.0
```

On terrabyte, from a zsh or bash tool shell. Never `module purge` there:

```bash
source $MODULESHOME/init/zsh
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
```

The depot matters. The runscripts use that depot, so an instantiate or a script
run under a different one will not be seen by a batch job. The modules matter
for the interactive Julia calls below; the batch scripts load their own.

`validate_configs.py` needs PyYAML, which neither machine's default Python has.
Without it `selftest.jl` skips its validator section with a warning. A scratch
venv is enough: `uv venv` with the `python/3.12` module, then
`uv pip install pyyaml`, and put the venv's `bin/` first on `PATH`.

## 0. Checked on 2026-09-10, the first time Julia was available

Everything in `analysis/` had been written and reviewed by reading only.

  - **The self-test passes all eleven sections**, the validator and its sixteen
    mutations included, once PyYAML is present.
  - **The phase passes run.** `phase_a.jl` reproduces `summary_a.csv` byte for
    byte, so its audit columns were already current. `phase_c.jl` now carries
    `c0_sphere_audit` and C1.
  - **The formatter has been through this directory**, as one commit of
    formatting only. It would also change three files in `docs/src/`, which
    were left alone: `tag_closure_memo.md` belongs to PR #63, and
    `tagged_water.md` and `tracer_configuration.md` would change exactly as PR
    #65's commit `af2079cc` changes them.
  - **`phase_c.jl` called region tags source tags** in its tag-minimum warning,
    and so hid the source tag E2 is about. Fixed; see M5.

Re-run the self-test after any change to `analysis/`:

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/selftest.jl
```

## 1. After the twins — the next decision

**Done: the implicit solve is ruled out.** The owner approved a twin with the
solve converged in both halves, `overrides/twin_newton_converged.yml` through
`TWIN_OVERRIDES`, job `13384080`. The step cost tripled, so it iterated, and the
one-step difference in `ρ` went only from 3.8e-5 to 3.6e-5 (FINDINGS E16). The
difference is in the tendencies. The leading candidate is the van Leer limiter
on vertical energy transport, which sees the shift as a change in the field it
limits.

**Two ways on, each needing approval.**

  - **Done: the shift in the tag code, C4** (FINDINGS E17 to E19).
    `energy_source_tag_offset` is in the model, with the owner's approval. The
    two C4 runs carry an identical atmosphere. At C1's size they reproduce C1's
    tag results, and at twice the size the source tag moves by about 1%. Both
    are in `output/c4_sphere_tag_offset*/`.
  - **The limiter twin ran** (job `13384884`, `overrides/twin_limiter_off.yml`).
    The limiter is most of E16: the one-step difference in `ρ` fell from 3.6e-5
    to 3.7e-8. A remainder is left.
  - **Done: the surface-flux path is ruled out** (job `13385303`,
    `overrides/twin_limiter_off_no_sfc.yml`). With the surface-flux tendency
    off as well, the one-step difference in `ρ` is 3.7e-8 again. What starts
    the remainder is not established. The owner did not take up a further
    twin: the offset leaves the model alone, so the tags no longer depend on
    it.

## 1b. Making the energy source tags operational

**The owner's decision, 2026-09-10: keep both** the energy source tags and the
process record, as the main goal. The tags say where the energy present came
from, and the record says what each process did.

What stands between the tags and operational use, in the order to do it:

 1. **PR #65**, the #64 fix and the closure audit. The offset builds on the
    audit, so this lands first.
 2. **`energy_source_tag_offset`**, in its own pull request stacked on #65:
    [#68](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/68),
    a draft. It carries the loss-rule integration test (item 7).
 3. **Precipitation on the implicit path** does not reach the source tags. Only
    the explicit path is bracketed for this family, so the 0M sink's energy
    leaves the parent unattributed. This is C2, and it needs a code change.
 4. **Negative tags.** The tags are exempt from both tracer limiters and have no
    partition repair, so they go negative (E14, E19). The water tags' additive
    repair from #64 is the pattern to adapt.
 5. **The transport mismatch.** `ρe_tot` moves as enthalpy, pressure work
    included, and the tags as passive tracers, which is most of the residual
    (E13). Either the tags learn the enthalpy form, or the residual is
    documented with a calibrated tolerance.
 6. **A calibrated closure tolerance.** The default 1e-6 warns every hour on a
    residual that reaches 3.8e-3 in a day on the sphere (E15, E18).
 7. **An integration test of the loss half.** With an offset the donor loss runs
    through a real solve, which no test checks yet. `analysis/offset_smoke.jl`
    is the starting point.
 8. **Sub-grid transport and GPU.** The tags are grid-scale only, and neither
    the family nor the offset has run on a GPU.

## 1c. C5 — done, and what comes next

**Done.** Both runs ran on 2026-09-10, jobs `13385401` and `13385402`, and are
in `output/c5_*/`. `analysis/c5_process_closure.jl` reads them (FINDINGS E20
to E24):

  - the radiation tag holds nothing where radiation cools, with the loss
    running (E22);
  - checked per process, the tags found subsidence, which the DYCOMS column
    runs and no tag listed (E20);
  - on the column, a region's initial energy only falls (E21);
  - the column's records leave 1.37 MJ m⁻² of a day's energy change
    unexplained (E23).

**C6, done on 2026-09-10** (FINDINGS E26 to E29, T8). The same two layouts on
the code of FINDINGS §8, which brackets the implicit microphysics sink and
repairs negative tags by default. Jobs `13385450` and `13385451` are the column
with the repair on and off, `13385452` and `13385453` the sphere with it on and
off, and `13385454` the sphere with first-order tag upwinding. They are in
`output/c6_*/`. What they found:

  - the column closes per process once subsidence has a tag, and per record to
    the joule;
  - with the repair on, no tag goes negative on the sphere, at about 1% of the
    solve, but the region tags trade up to 31 kJ/kg between them;
  - on the sphere, the per-process check found the rain-out producing energy
    where cold condensate falls out;
  - the region tags' negativity does not come from their vertical upwinding.

**C7 and the sphere's transport ledger, done on 2026-09-11** (FINDINGS E30,
E31). Job `13399601` is C6's sphere, repair off, with a `microphysics` tag, in
`output/c7_sphere_mp/`. Job `13399604` ran `analysis/transport_ledger.jl` on the
same sphere, in `output/transport_ledger_sphere/`. What they found:

  - with the rain-out tagged, the sphere closes per process to 20.2 J/kg,
    against 149;
  - on the sphere too, pressure work is at least 93% of the residual's growth,
    the per-tag limiter 2e-4 and hyperdiffusion 2.4%.

**Next.** The owner approved both builds after C6. Each run still needs its own
approval:

  - sedimentation as transport of the tags is built at `91b9bbb9`, and passes
    its tests. A one-hour 1M column on the login node shows the tags now follow
    it out at the ground (FINDINGS E32). A draft PR stacked on #69 is prepared
    locally, on `claude/energy-source-tag-sedimentation` at `e8debaba`, and
    waits for the owner's approval to push. A day-long 1M column, C8, would
    test it at length;
  - the enthalpy-form audit switch. Both measurements meet the rule for building
    it (E25, E31), and the sphere's says it needs a horizontal half. It is not
    built.

The first submission, jobs `13385435` to `13385439`, failed at startup. The
repair's commit had registered `e_src_fix_<name>` without defining the function
that computes it, and these are the first runs to ask for it. `f3bbdb7b` adds
the function, and an integration test now computes it. The resubmission is the
same five configurations on that commit.

The runs:

  - the column with a `sub` tag, and records for radiation, the surface flux,
    subsidence and microphysics, so that both forms can close;
  - the column and the sphere each run twice, repair on and off, so that the
    ledgers measure what the repair changes;
  - optionally, the sphere with `tracer_upwinding: first_order`. In a 0-moment
    run that moves only the tags, so it separates the limiter from the clamp
    (E20).

The design of C5, as the owner approved it:

The owner approved both runs on 2026-09-10, on `hpda2_test`. Both carry C4's
offset, 110,495 J/kg, and add what C4 could not test.

  - **`c5_column_offset`**: C3's DYCOMS column. Tags `strat`, `tropo`, `rad`,
    `sfc`, `new_strat` and `new_tropo`, records for radiation and the surface
    flux, and `rhoa`.
  - **`c5_sphere_gray`**: C4's sphere with `rad: gray`, fluxes hourly. Tags
    `tropics`, `extratropics`, `sfc`, `rad`, `new_tropics` and
    `new_extratropics`, and the same two records.

What to read from them:

  - **Cloud top.** How much of radiation's cooling the `rad` tag feels once the
    loss runs, against the record. C3 could not say (E8).
  - **The initial tag, without code.** A region tag minus its `new_` tag is the
    energy that was in that region at the start, followed as it moves. It gains
    nothing, so its domain total may only fall. The column's total is exact;
    the sphere's lat-lon output only approximates it.
  - **Per-process closure, form A.** The new energy split by region, the sum of
    the `new_` tags, must equal the new energy split by process, `rad + sfc`, at
    every point. They are separate tags, so this is a check and not an
    identity. A gap means a process that fires with no tag of its own, or the
    share's clamp where a tag has gone negative.
  - **Per-process closure, form B, on the column only.** The records summed
    over the column, against the change in `ρe_tot`, up to what no record sees.

The analysis script is not written yet. It goes in `analysis/` before the result
is recorded.

Submit as C4 was, with the run as the job name:

```tcsh
env CONFIG=experiments/tag_closure/configs/c5_column_offset.yml \
    sbatch --account=hpda-c --partition=hpda2_test --time=01:00:00 \
        --cpus-per-task=2 --mem=32G --job-name=c5_column_offset \
        --output=$SCRATCH/tag_closure/logs/%x-%j.out \
        --error=$SCRATCH/tag_closure/logs/%x-%j.err \
        experiments/tag_closure/runscripts/phase_c.sh
```

## 2. C1 — done

**Ran 2026-09-10 on terrabyte, approved the same day**, at `72a1bc6`, SLURM job
`13383684` on `hpda2_test`, exit 0. The baseline is `c0_sphere_audit` re-run on
the same node at the same time, job `13383685`, so the pair is controlled. It is
committed under `output/c0_sphere_audit/terrabyte/` and agrees with the Levante
reading to 1.5e-14 (M6).

**The acceptance checks all held.** `analysis/c1_acceptance.jl` passes its 38
checks on the shift file (R8). C1's own `c1_sphere_shift_parameters.toml`
differs from the baseline's in exactly the three shifted entries, which is
direct proof they bound. The acceptance test that used to sit in the TOML's
header could not have run (FINDINGS §6).

**What it measured**, against its baseline:

|                                   | baseline    | C1                       |
|:--------------------------------- |:----------- |:------------------------ |
| `nonpositive_fraction`, all day   | 0.43276     | 0.0                      |
| absolute `gross_residual` at 24 h | 2.626e21    | 1.846e21 (0.70×)         |
| overclaim ÷ undertag, 3 h → 24 h  | 1.49 → 3.85 | 1.002 → 1.033            |
| most negative source tag (`sfc`)  | −209.2      | −219.9                   |
| most negative region tag          | −100,416    | −11,575, parent positive |
| `solve! walltime`                 | 345.6 s     | 349.0 s                  |

Read `gross_relative` with care: 0.00380 against 0.01542 looks like 4.06×, and
2.85× of that is the normalising scale growing (E15). The table above is E11 to
E15 and T6, and the twin test's bound is E16.

**How it was run**, for the next run on terrabyte:

```tcsh
env CONFIG=experiments/tag_closure/configs/c1_sphere_shift.yml \
    sbatch --account=hpda-c --partition=hpda2_test --time=01:30:00 \
        --cpus-per-task=2 --mem=32G \
        --output=$SCRATCH/tag_closure/logs/%x-%j.out \
        --error=$SCRATCH/tag_closure/logs/%x-%j.err \
        experiments/tag_closure/runscripts/phase_c.sh
```

## 3. C3 — done, and it is the result the series was for

Nothing to run.

C3 reproduces `c0_column` bit for bit — `gross_relative` 0.13456131085846748,
`max_abs_e_src_res` 26888.66561703798, most-negative tag −44972.50629142498, all
identical — so the process record perturbs nothing and is a pure diagnostic
sitting beside the tags. On the same run, at the end of the day:

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

## 4. The timing controls — measured

|                       | tagged   | untagged | ratio |
|:--------------------- |:-------- |:-------- |:----- |
| A1, `solve! walltime` | 3.337 s  | 0.548 s  | 6.09  |
| C0, `solve! walltime` | 11.225 s | 8.521 s  | 1.317 |

**1.32×, not 6.1×.** Same three tag families. A1 fires the closure reduction on
every timestep and C0 fires it hourly, so the check is most of A1's factor
(T2 to T4). The reference shift itself costs nothing measurable (T6).

## After any batch job

Check the exit status rather than only the log, because a crashed solve returns
`:simulation_crashed` and the driver's non-zero exit is what makes that visible.
The twin test exits 1 on purpose when the twins differ.

```bash
sacct -j <jobid> -o JobID,State,ExitCode
```

Reduce before copying anything back, because the operator residual and the
per-tag extrema come from the NetCDF, and the NetCDF stays on scratch. On
Levante the run directory is the repository root. On terrabyte it is
`$SCRATCH/tag_closure`:

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/reduce_run.jl <run directory>/output/<run>/output_active
```

Then copy into `experiments/tag_closure/output/<run>/`: the family's
`*_tag_closure.csv`, the reduced tables, the audit table where the run wrote
one, `<run>.yml`, `<run>_parameters.toml`, `provenance.txt`, and a trimmed
`run.log`. The analysis refuses any run whose `provenance.txt` records
`commit: unknown`. On terrabyte the compute nodes have no git, so the commit is
read from `.git` and `commit_dirty` reads `unknown`; commit before submitting so
that the recorded commit is exact.

Then the phase script, `phase_a.jl` or `phase_c.jl` as appropriate.

## Pull requests, as of 2026-09-10

  - **#65** carries the #64 fix, `7799a5a` and `acfea85`, plus `af2079cc` with CI
    fixes. `main` was merged into it on 2026-09-10 at the owner's request, as
    `4c8795e9`. The only conflict was `NEWS.md`, where both sides had added
    entries at the top, and both were kept. This branch has the first two fix
    commits and not the third, which touches only docs and a test.
  - **#63**, the memo and the plan, is a draft on the draft #62. The formatter
    would add two blank lines to `tag_closure_memo.md`.

## Known defects, reported and not fixed

  - This directory's `.gitignore` says `*.out` is "deliberately still ignored",
    while thirteen `.out` files sit committed under `output/`.
  - `validate_configs.py`'s `implicit_diffusion` rule is stricter than the
    model. `model_getters.jl:1068` puts that assert in an `elseif` chain after
    the ISDAC branch, so an ISDAC config would pass the model and fail the
    validator. False positives only; nothing here uses ISDAC.
  - `output/c0_sphere_deep/` holds a `.out` and an `.err` and no provenance, so
    every phase C pass warns that it skips it.

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

**Phase B.** `b1_base` configures no limiter at all — only `b3_limiter` does —
and phase B is the *energy* family, which has no `rescale_water_tags!` and no
partition repair, so #64's mechanism cannot reach it. **Phase B has no technical
objection left.** C1 solved a simulated day in 5.8 minutes on the `he6ze10`
grid, so B1's ten days is about an hour of solve if it runs at that speed, which
fits `hpda2_test`'s two-hour limit. Whether it is worth running is the owner's
call. B2 is dry and unaffected either way.

**C2** needs a code change and the owner's approval, and no configuration for it
is written.
