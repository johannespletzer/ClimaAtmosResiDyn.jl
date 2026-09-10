# Task list

What to run next, and what each run is for. Every task carries what it needs, so
none of them requires opening another document first. The file name is
historical. The series started on DKRZ Levante, and since 2026-09-10 it also
runs on LRZ terrabyte.

Branch `claude/tag-closure-experiments`.

## Where things stand

20 of the 28 configured runs are live in `output/`. A run is live when
`output/<run>/provenance.txt` exists, so `ls output` is the register.
`c0_sphere_deep` is dropped rather than pending — see *Not yet, and why*.
`output/twin_c1/` is not a configured run but a check on C1, and
`output/c0_sphere_audit/terrabyte/` is a second reading of that run.

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

  - **Move the shift into the tag code** (FINDINGS §8, item 1). The tags
    partition `ρe_tot + c·ρ`, with `c` a fixed 110.5 kJ kg⁻¹ per kilogram of
    air. The model never sees it, so the atmosphere is bit for bit the unshifted
    one. It is a code change in `energy_source_tags.jl` and in the code that
    reads the parent, with a kernel test first. Then one run at 110.5 kJ kg⁻¹
    for comparison with C1, and one at a larger `c` for R11's suppression cost.
  - **Confirm E16's cause first.** One twin with `energy_q_tot_upwinding: none`
    in both halves, which switches the post-solve limiter hook off, from a new
    file in `overrides/`. About 20 minutes on `hpda2_test`. If the differences
    fall to rounding, the limiter is the whole cause.

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
