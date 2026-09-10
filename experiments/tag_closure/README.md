# Tag-closure experiments

Configurations, runscripts, analysis and results for the experiments planned in
[the experiment plan](../../docs/src/tag_closure_experiments.md). The reasoning
behind them is in [the memo](../../docs/src/tag_closure_memo.md). Read the plan
before submitting anything. This page is the operator's copy of it: how to
submit a run, what has to come back with it, and the traps. It does not repeat
the motivation, the decision rules, or what the runs have measured.

**The owner decides every submission.** Nothing here runs on its own and no
agent submits to Levante. The agent writes the configurations, the driver, the
runscripts and the analysis. The owner runs each job, copies the small result
files into `output/`, and commits them. The agent then runs the analysis over
`output/`, produces the plots, and writes the entries in `LEARNINGS.md`.

On LRZ terrabyte an agent session can reach `sbatch`. There the owner may
approve an agent to submit named jobs and hand them back itself. The approval
is per job. The first were C1 and its two checks, approved on 2026-09-10.

## Where things stand

On branch `claude/tag-closure-experiments` — run `git log -1` for its head. The
docs are on `claude/tag-closure-experiments-plan` (PR #63), carrying the
corrected plan and the memo with measured results.

**This page does not track state.** It used to, and every count and tick in it
had gone stale by the time anyone read them. What has been measured is in
[FINDINGS.md](FINDINGS.md), one numbered claim per finding; the reasoning per
run is in [LEARNINGS.md](LEARNINGS.md); what to run next, in order, is in
[LEVANTE_TASKS.md](LEVANTE_TASKS.md). Which runs are live is a fact about the
tree rather than a table to maintain: a run is live when
`output/<run>/provenance.txt` exists, and `ls experiments/tag_closure/output`
answers it in full.

What is below is how the harness works — submitting, what comes back, and the
traps — which is the part no other page carries.

### Before you submit anything

Two things, both easy to miss.

**Instantiate first**, once, on a login node, under the runscript's depot. See
*Before the first job* below — it is a prerequisite, not a suggestion, and it is
what cost the first attempt.

**The analysis refuses a run whose provenance has no commit.** `phase_a.jl` and
its siblings skip any run whose `provenance.txt` records `commit: unknown`, with
a warning naming it. Runs submitted before `3659746` can hit this. The fix is
*Repairing a provenance* below — repair the file, do not resubmit the run.

### Decisions waiting on the owner

**C1 has run.** It was approved on 2026-09-10 and ran on terrabyte the same
day. What it measured is in [FINDINGS.md](FINDINGS.md), E11 to E16, and the
argument behind it is in [C1_reference_shift.md](C1_reference_shift.md). One
follow-up waits on a decision. The twin test showed that the shift changes the
simulated atmosphere slightly (E16). One more twin run, with the implicit solve
converged, would say whether the one-iteration Newton step is why.

**C2** needs approval and a code change, and no configuration for it is
written.

**Whether to lengthen `test/tagged_water_integration.jl` past A5's onset.** The
issue-64 fix strengthened that test rather than lengthening it: `t_end` is
still one hour and the new assertions bound each tag and the residual against
the *local* parent. On the archived pre-fix numbers the residual half of that
would still have passed at one hour, so the coverage gap is narrowed and not
closed. See the A5 open item below.

### What will bite you

  - **The tcsh runscripts have never been syntax-checked.** No `tcsh` was
    available where they were written. `phase_a.sh` and its siblings are the
    tested path; the `.tcsh` variants are a fallback that nobody has run. A
    tcsh *login shell* is fine with the bash scripts — see *If your login shell
    is tcsh*.
  - **Run the reducer before copying anything back.** `analysis/reduce_run.jl`
    turns the NetCDF into the small tables. The NetCDF stays on scratch and is
    the only place the pointwise numbers exist; once scratch is cleaned they are
    gone. A run copied back without it has no operator residual and no per-tag
    minima.
  - **Sphere numbers are not column numbers.** The NetCDF writer bilinearly
    remaps to lat-lon, so every reduction on a sphere is over the remapped
    field. The tables carry a `remapped` column and the reducer warns. Do not
    set a sphere maximum beside a column one as though they were the same
    quantity.
  - **Five files per run**, listed under *What goes in `output/<run>/`*:
    the closure CSV, the reduced table from the reducer, the merged `<run>.yml`
    snapshot, `run.log`, and `provenance.txt`. The NetCDF and checkpoints stay
    on scratch.
  - **A committed summary is one analysis pass behind whatever landed last.**
    `output/summary_<phase>.csv` and the PNGs in `plots/` are written by
    `analysis/phase_<letter>.jl`, which needs Julia and therefore Levante. A run
    committed since the last pass has no row, and a column the script has gained
    since the last pass is in no row at all. Re-run the phase script after
    copying anything back; it is the last step of the hand-back and the one most
    often skipped.
  - **Every run so far records `commit_dirty: yes`.** The commit is real, the
    tree simply had uncommitted edits at submit time. So a recorded commit is
    the nearest committed ancestor, not an exact description of what ran.

### Where the record lives

| What                             | Where                                                |
|:-------------------------------- |:---------------------------------------------------- |
| Every established claim, numbered | [FINDINGS.md](FINDINGS.md)                          |
| The reasoning, one entry per run | [LEARNINGS.md](LEARNINGS.md)                         |
| The C1 reference argument        | [C1_reference_shift.md](C1_reference_shift.md)       |
| What to run next, on Levante     | [LEVANTE_TASKS.md](LEVANTE_TASKS.md)                 |
| Raw probe output from Levante    | [C1_reference_shift.md](C1_reference_shift.md), appendix |
| Instructions for the next session | [NEXT_SESSION.md](NEXT_SESSION.md)                    |
| Which runs are live              | `output/<run>/provenance.txt`                        |
| Plan and memo                    | PR #63, branch `claude/tag-closure-experiments-plan` |
| Configurations, driver, analysis | this directory                                       |

A claim belongs in exactly one of these. `FINDINGS.md` is the index and cites
the run behind each number, so a number quoted anywhere else should be a
cross-reference rather than a copy — copies are what went stale here before.

## Layout

```
experiments/tag_closure/
  README.md            this page: how the harness works and how to submit
  FINDINGS.md          every established claim, numbered, with its run
  LEARNINGS.md         the barrier register, one entry per run
  C1_reference_shift.md  the C1 argument and its recipe
  LEVANTE_TASKS.md     what to run next, in order
  run_tag_closure.jl   the driver: one config path in, one run out
  run_c1_twin.jl       C1's twin test: the model with and without the shift
  configs/             one YAML per run, named <phase><n>_<variant>.yml
  overrides/           keys run_c1_twin.jl sets in both halves, via TWIN_OVERRIDES
  runscripts/          one sbatch script per phase, CPU shared partition
  analysis/            reduce_run.jl, run on Levante, plus one script per phase
  output/              committed by the owner, one directory per run
  plots/               PNGs written by the analysis scripts
```

`runscripts/` holds `phase_a.sh`, `phase_b.sh`, `phase_c.sh` and
`tag_closure_common.sh`, plus a `.tcsh` variant of each. A phase script is its
`#SBATCH` block and enough logic to find the repository; everything else is in
the common file it sources, which is how `runscripts/levante_gpu_common.sh` is
arranged next door. Finding the repository has to happen in the phase script
rather than the common file, because `sbatch` copies the job script to the
node's spool directory before running it, so `$0` and `BASH_SOURCE` point
somewhere that holds none of this. `runscripts/xmodel.1gpu` locates itself the
same way and for the same reason.

The bash and tcsh variants are the same job in two shells and take the same
`CONFIG`. The bash ones are the default. The tcsh ones exist as a fallback and
differ only where tcsh forces it: an unset variable is a fatal "Undefined
variable" rather than the empty string, so `CONFIG` is guarded with `$?CONFIG`
before it is ever dereferenced; tcsh has no functions, so the root search is an
inline `foreach`; and there is no `set -e`, so `$status` is captured on the line
immediately after the julia call, before anything can overwrite it.

The plan says the runscripts follow `runscripts/run_test_as_job.sh`. That is
right about the `#SBATCH` block — the `bd1062` account, the shared partition,
the `levante-cpu` depot, the module lines — and misleading about the shell.
`run_test_as_job.sh` is **tcsh** and hardcodes its own repository path, and in
tcsh an unset `$CONFIG` is a fatal "Undefined variable" rather than a message
anyone can act on. These scripts are bash, and take their structure from
`runscripts/xmodel.cpu`: `SLURM_SUBMIT_DIR` root discovery, environment
overrides with defaults, and fail-early checks that name what to fix.

The empty directories are tracked with a `.gitkeep` so the layout survives a
fresh clone. There is also a `.gitignore` here holding one line, `!output/`: the
repository root ignores `output/` everywhere, and without the re-inclusion the
owner's committed results would need a `git add -f` every time.

`analysis/` holds `reduce_run.jl`, one `phase_<letter>.jl` per phase,
`tables.jl` with the readers they share, `where_negative.jl`,
`validate_configs.py`, and `selftest.jl`, which drives all of it on synthetic
input. `c1_acceptance.jl` sits beside them and is not driven by the self-test.
It checks the C1 shift file against the Thermodynamics package a run loads.
`offset_smoke.jl` and `same_atmosphere.jl` check that `energy_source_tag_offset`
leaves the model alone, on a column and between the two C4 runs.

### How the sphere configurations are put together

The B and C sphere runs need the grid from
`config/common_configs/numerics_sphere_he6ze10.yml`. `.buildkite` layers that
with `--config_file`, and these configurations **fold its keys in instead**. The
driver takes one configuration path, so layering would mean teaching it the
`--config_file` list that `ci_driver.jl` takes, and a run would then no longer
be described by one readable file. The cost is that a later change to the common
config does not reach these copies, and each names its source in a comment so
the drift is at least findable.

That grid is the one the shipped `baroclinic_wave_tagged_tracers` job runs on,
so B1, B2 and `c0_sphere` all sit on the same mesh: the docs' below-one-percent
figure is comparable rather than a fresh measurement, and the sphere cost of the
two energy families can be set against each other.

`c2_*` is not written: it needs a model change and the owner's approval. C1
needs approval too, but its shape is settled and it reaches the model through
`toml:` rather than through a code change — see
[C1_reference_shift.md](C1_reference_shift.md).

## Analysis

Everything here runs with `--project=.buildkite`, which carries CairoMakie,
NCDatasets, DataFrames and Statistics. It does **not** carry CSV.jl, so these
read tables with `DelimitedFiles`. Two stages: `reduce_run.jl` on Levante,
against a finished run, then one `phase_<letter>.jl` over the committed
`output/`.

`analysis/reduce_run.jl` runs on Levante, against a finished run's output
directory, before anything is copied back:

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/reduce_run.jl output/a1_dt10/output_active
```

It writes `operator_residual.csv` into that directory. It exists because the
number phase A turns on is not in the closure table and the NetCDF never leaves
scratch: `gross_relative` is a volume integral with no ledger subtracted, while
the operator residual is a pointwise maximum of `q_tag_res + Σᵢ q_tag_fix_i`,
**summed first and reduced afterwards**, over the pure region tags only. Beside
it the file carries `max abs q_tag_res` and the summed ledger on their own, so
the decomposition can be checked rather than trusted, and a `geometry` and
`remapped` column, because on a sphere the writer has already bilinearly remapped
to lat-lon and the maximum is then over the remapped field rather than the
model's own columns. Phase A's ladder is columns, where that is not an issue.

The invariant relating the two residual columns is an identity, not an
inequality: the operator residual is what the run would have reported had no
correction been applied. It is **not** reliably smaller than `q_tag_res`. The
partition repair's ledger sums to zero on its sum-preserving branch and to a
positive number on the branch that zeroes a cell, so the operator residual is
usually the larger of the two.

For the energy and energy-source families the reducer instead writes
`energy_tag_residual.csv` (`max |e_tag_res|` per time) and
`source_tag_extrema.csv` (`max |e_src_res|`, and the minimum and maximum of
**every** tag). It writes whichever apply, so a run configuring two families
gets two tables and a timing control gets none.

!!! note "There is no ledger outside the water family"

    `q_tag_fix_<name>` exists because `rescale_water_tags!` and
    `repair_water_tag_partition!` correct the water tags and record what they
    moved. Nothing corrects the energy tags, and the energy source tags have no
    rescale and no partition repair at all. So there is **no `e_tag_fix` or
    `e_src_fix`, and the operator-residual subtraction of phase A does not apply
    to phases B and C.** Do not go looking for one. What replaces it is the
    per-tag minimum in `source_tag_extrema.csv`: `e_src_res` sums the pure
    region tags only, so a source-labelled tag going negative never enters it
    and has to be watched directly.

`analysis/phase_a.jl`, `phase_b.jl` and `phase_c.jl` run afterwards over the
committed `output/`, and write `output/summary_<phase>.csv` plus the phase's
PNGs into `plots/`. They share `analysis/tables.jl`, which holds the readers, so
that three scripts cannot drift apart in how they read a run.

### Checking the configurations

```bash
python3 experiments/tag_closure/analysis/validate_configs.py
python3 experiments/tag_closure/analysis/validate_configs.py --mutations
```

The first checks every configuration against `default_config.yml` for key
existence and value type, then against the plan's common protocol per family:
`job_id` equal to the file name, `FLOAT_TYPE`, defaults off, no limiter outside
the two runs that measure one, exactly one family under test, tags and closure
check present or absent together, at least one pure region tag, no `tolerance`,
no `reduction_time`, no top-level key bound twice, every diagnostic a name the
run will register, phase A's closure period still tracking `dt`, and `audit`
set on exactly the runs that need it and on no others, plus one cross-key
consistency rule mirroring `check_case_consistency`. The second breaks copies of
the tree one way per check and asserts every one is caught, so those checks are
demonstrably live rather than merely present. It prints the tally it managed, so
a check that stops catching its mutation is visible without anyone having to
remember last week's number.

It is Python because that is the tool that was actually used while the
configurations were written; a Julia port would be an unverified rewrite, since
nothing here can run Julia. It needs only PyYAML. `selftest.jl` invokes both and
skips with a message when neither the interpreter nor PyYAML is present, so the
Julia self-test gains no hard dependency on it.

### Testing the analysis

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/selftest.jl
```

It builds a synthetic NetCDF run and synthetic tables in a temporary directory,
drives both scripts over them, and asserts values worked out by hand: the
operator residual on a worked partition-repair case, that a source tag's ledger
was not summed, that the field was summed before it was reduced, that a run with
no `provenance.txt` is refused, and that the log-log slope fit recovers 2 from
`y = x²`. It writes nothing into the repository.

!!! note "What has been run, and what has not"

    The driver has run every job in `output/`. The analysis scripts first ran
    on 2026-09-10, on terrabyte, and `selftest.jl` passed all eleven sections
    there, including the configuration validator and its sixteen mutations. The
    validator needs PyYAML. Without it the self-test skips that section with a
    warning rather than failing, so check that section ran.

    The bash runscripts have run every job, on Levante and on terrabyte. **The
    tcsh variants have never run.** `tcsh -n` parses the three phase scripts.
    It parses `tag_closure_common.tcsh` up to the provenance block at the end,
    and there it stops on a one-line `if` that redirects into a variable.
    `tcsh -n` executes nothing, so that variable is never set, and it fails the
    same way on a one-line reproduction. So no syntax error was found. Run one
    of them once by hand before relying on it.

## Before the first job: instantiate the environment

**Do this once, on a login node, before submitting anything.** The runscript
does not do it and a batch job cannot: `Pkg.instantiate` needs the package
registry and Levante's compute nodes have no outbound network.

```bash
JULIA_DEPOT_PATH="${LEVANTE_DEPOT:-$HOME/.julia/depots/levante-cpu}" \
    julia +1.11 --project=.buildkite \
    -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

Two things about that line are easy to get wrong, and both cost a job.

**The depot has to match.** The runscript sets
`JULIA_DEPOT_PATH="${LEVANTE_DEPOT:-$HOME/.julia/depots/levante-cpu}"`, so an
instantiate run under the default depot installs packages the batch job will
never look at. Set the same variable here, or export `LEVANTE_DEPOT` once and
use it in both places.

**`.buildkite/Manifest-v1.11.toml` is generated, not committed.** The root
`.gitignore` excludes `*/Manifest*.toml`, so a fresh clone has none, and without
one Julia resolves the environment from scratch. That is what makes the failure
look so strange: `Statistics` is a resolvable standard library in 1.11 but has
no source until a manifest pins it, and the first run dies with
`Missing source file for base pkg Statistics` — which reads like a broken Julia
rather than an environment that was never instantiated.

`Pkg.precompile()` is not optional in practice. Without it the first job spends
its walltime compiling ClimaAtmos rather than running the model. CI does the
same thing, at `.buildkite/full_pipeline.yml:32`.

## Submitting one run

From the repository root on Levante, with the experiment branch checked out and
pulled. The configuration travels in the environment, the way the GPU
runscripts already take `SCRIPT`:

```bash
CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
    sbatch experiments/tag_closure/runscripts/phase_a.sh
```

`sbatch` exports the submitting environment, so the runscript reads `CONFIG`
and hands it to the driver. Submit from the repository root; the path may be
repository-relative, as above, or absolute. Watch the job with
`squeue -u $USER`; its output lands in the `.out` file beside where it was
submitted.

### If your login shell is tcsh

`CONFIG=path sbatch script` is POSIX-shell syntax and is **not valid tcsh**.
From a tcsh login shell, use `env` or `setenv` instead:

```tcsh
env CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
    sbatch experiments/tag_closure/runscripts/phase_a.sh

# or
setenv CONFIG experiments/tag_closure/configs/a1_dt10.yml
sbatch experiments/tag_closure/runscripts/phase_a.sh
```

**That is the only thing your login shell changes.** Two choices are in play
here and they are independent:

  - *What you type.* `VAR=value command` in a POSIX shell, `env VAR=value
    command` or `setenv` in tcsh.
  - *What the job script is written in.* `phase_a.sh` is bash, `phase_a.tcsh`
    is tcsh.

`sbatch` exports the submitting environment whatever the job script's own
interpreter is, so **the bash scripts work perfectly well when submitted from a
tcsh login shell** — only the command line differs. Logging in to tcsh is not a
reason to reach for the `.tcsh` variants.

The bash scripts are the documented default and the ones to use unless you have
a reason not to. The `.tcsh` variants sit beside them as a fallback, do the same
work, and take the same `CONFIG`:

```tcsh
env CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
    sbatch experiments/tag_closure/runscripts/phase_a.tcsh
```

The same driver runs by hand on a login node, which is the quick way to find a
configuration error without queueing:

```bash
CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
    julia +1.11 --project=.buildkite \
    experiments/tag_closure/run_tag_closure.jl
```

### On terrabyte

The same bash scripts run on LRZ terrabyte. `tag_closure_common.sh` tells the
machines apart by a path only Levante has, or by `TAG_CLOSURE_MACHINE` when
that is set. On terrabyte it loads the stack named in
`runscripts/terrabyte_stacks.env` and uses the depot on scratch that
`runscripts/setup-julia-terrabyte.tcsh` builds. It never runs `module purge`,
which on terrabyte drops the spack modules for good.

Each phase script's `#SBATCH` block is Levante's. Give terrabyte's account and
partition on the command line, which overrides the block:

```tcsh
env CONFIG=experiments/tag_closure/configs/c1_sphere_shift.yml \
    sbatch --account=hpda-c --partition=hpda2_test --time=01:30:00 \
        --cpus-per-task=2 --mem=32G \
        experiments/tag_closure/runscripts/phase_c.sh
```

`hpda2_test` has a two-hour limit. On 2026-09-10 it started jobs at once, while
`hpda2_compute` put even a two-core, half-hour job 30 hours out. A sphere-day
took 9 minutes on Levante, plus compilation.

**The run writes to scratch, not to the repository.** `$HOME` on terrabyte is
for code, so the run's working directory is `$SCRATCH/tag_closure`, and its
output lands in `$SCRATCH/tag_closure/output/<run>/`. Set `RUN_DIR` to move it.
Reduce from there, and copy the hand-back files into `output/<run>/` here as
usual. The provenance records the machine and the driver.

`TAG_CLOSURE_JOB_ID` renames a job's output directory. It is for drivers that
are not the run's own, such as `run_c1_twin.jl`, so that they cannot write over
the real run. The `.tcsh` variants are still Levante-only.

**The job's exit status is the thing to read.** A crashed solve returns
`:simulation_crashed` rather than throwing, so a driver that ignored the return
code would let the job exit zero over a dead run. This one checks it and exits
non-zero, so `sacct` or the `.out` file's last line answers the question without
anyone reading the log.

The runscript writes `provenance.txt` into the run's own output directory,
whether the run succeeded or not, so that file does not have to be retyped. It
fills in the run name and its configuration path, the commit, the branch and
whether the tracked tree was dirty, the Julia version and depot, the start and
end times, the driver's exit status, the SLURM job id and name, the partition,
the node list, the CPU model as the node type, the ClimaComms context and
device, and the absolute output directory. The NetCDF diagnostics and the
checkpoints live under that directory, so the path is what points back to them.
What it cannot fill in is anything about the run's meaning: which question this
is beyond the `job_id`, and why it was submitted. Add those by hand if they
are not obvious. If a run dies before its output directory exists, the file goes
to the submit directory instead and the log says so.

A crashed run is handed back too, with its log, its provenance and whatever
tables it managed to write. The closure check appends a row per firing, so a run
that died partway still leaves a partial table, and where it stops is itself the
measurement.

## Order and gates

Water first, then energy, then the source tags. Each phase ends with its
learning entries and a short report, and the next phase's configurations are
adjusted from what was learned before they are submitted.

  - **A1 and A2 are submitted together and read together.** A1's slope on its
    own does not answer the question it was written for, so neither ladder is
    reported before the other has run. That is nine runs, not two.
  - **A5 is optional** if the shared partition makes it slow. It is the only
    sphere in phase A; if `phase_a.sh` is sized for the columns, submit it
    against `phase_b.sh` instead, or against `runscripts/xmodel.1gpu` with
    `SCRIPT` set to the driver. That is a cost decision for the owner.
  - **C0 may run alongside phase A** if the owner wants the barrier census
    early. It changes nothing in the model and needs no code.
  - **C1 and C2 wait for the discussion.** Both need the owner's approval. C2
    also needs a code change and has no configuration; C1 turns out not to,
    since its shift is three settable thermodynamic parameters.
  - Nothing in this series edits `reproducibility_tests/ref_counter.jl`, a
    tolerance, or the parent-budget calibration table.

## The runs

### Phase A. Water

| Run                    | Runscript    | What it is                                             |
|:---------------------- |:------------ |:------------------------------------------------------ |
| `a1_dt10_notags`       | `phase_a.sh` | A1 at `dt` 10 s with no water tags. The cost baseline. |
| `a1_dt10`              | `phase_a.sh` | A1, van Leer, `dt` 10 s                                |
| `a1_dt5`               | `phase_a.sh` | A1, van Leer, `dt` 5 s                                 |
| `a1_dt2p5`             | `phase_a.sh` | A1, van Leer, `dt` 2.5 s                               |
| `a2_none_dt10`         | `phase_a.sh` | A2, both upwinding keys `none`, `dt` 10 s              |
| `a2_none_dt5`          | `phase_a.sh` | A2, both upwinding keys `none`, `dt` 5 s               |
| `a2_none_dt2p5`        | `phase_a.sh` | A2, both upwinding keys `none`, `dt` 2.5 s             |
| `a2_first_order_dt10`  | `phase_a.sh` | A2, both upwinding keys `first_order`, `dt` 10 s       |
| `a2_first_order_dt5`   | `phase_a.sh` | A2, both upwinding keys `first_order`, `dt` 5 s        |
| `a2_first_order_dt2p5` | `phase_a.sh` | A2, both upwinding keys `first_order`, `dt` 2.5 s      |
| `a3_1m`                | `phase_a.sh` | A3, `microphysics_model: 1M`, `dt` 10 s                |
| `a3_0m_vert_diff`      | `phase_a.sh` | A3's companion, 0M with `vert_diff` on, `dt` 10 s      |
| `a4_float32`           | `phase_a.sh` | A4, `FLOAT_TYPE: Float32`, `dt` 10 s                   |
| `a5_sphere_limiter`    | `phase_a.sh` | A5, sphere with the SEM limiter, `dt` 300 s, one day   |

### Phase B. Energy

| Run                | Runscript    | What it is                                          |
|:------------------ |:------------ |:--------------------------------------------------- |
| `b1_notags`        | `phase_b.sh` | B1 with no energy tags. The cost baseline.          |
| `b1_base`          | `phase_b.sh` | B1, hyperdiffusion and vertical diffusion both on   |
| `b1a_no_hyperdiff` | `phase_b.sh` | B1a, `hyperdiff: ~`                                 |
| `b1b_no_vert_diff` | `phase_b.sh` | B1b, `vert_diff: ~`                                 |
| `b1c_neither`      | `phase_b.sh` | B1c, both off                                       |
| `b2_dry_hs`        | `phase_b.sh` | B2, dry Held-Suarez baroclinic wave, 10 days        |
| `b3_limiter`       | `phase_b.sh` | B3, B1 with `apply_sem_quasimonotone_limiter: true` |

### Phase C. Energy source tags

| Run                | Runscript    | What it is                                                   |
|:------------------ |:------------ |:------------------------------------------------------------ |
| `c0_column_notags` | `phase_c.sh` | C0's column with no source tags. The cost baseline.          |
| `c0_column`        | `phase_c.sh` | C0, DYCOMS source column with `rad: DYCOMS`, one day         |
| `c0_sphere`        | `phase_c.sh` | C0, moist sphere, one day                                    |
| `c0_sphere_deep`   | `phase_c.sh` | C0's depth control: the same sphere on the 60 km grid        |
| `c0_sphere_audit`  | `phase_c.sh` | `c0_sphere` with `audit: true` and nothing else changed      |
| `c3_column_record` | `phase_c.sh` | C3, `c0_column` with `energy_process_record` beside the tags |
| `c1_sphere_shift`  | `phase_c.sh` | C1, `c0_sphere` under the reference shift, `δ` = −110 K       |
| `c4_sphere_tag_offset` | `phase_c.sh` | C4, `c0_sphere_audit` with the tags on `ρe_tot + c·ρ`, `c` = 110,495 J/kg |
| `c4_sphere_tag_offset_2x` | `phase_c.sh` | C4 at twice the offset, on the identical atmosphere |

C2, the implicit-path brackets, needs the owner's approval and a code change,
and no configuration for it is written. C1, the reference shift, needs approval
and a TOML file but no code change.

`ls configs/` is the authoritative list; the tables above say what each one is
for. Nothing is waiting on the agent — what is left is submitting them, in the
order [LEVANTE_TASKS.md](LEVANTE_TASKS.md) gives.

## Which runs are live

Not a table. A run is live when `output/<run>/provenance.txt` exists, so

```bash
ls experiments/tag_closure/output
```

is the register, and it cannot go stale. The tables under *The runs* above say
what each configuration **is**; `output/` says which have **run**;
[FINDINGS.md](FINDINGS.md) says what they established.

`output/a5_sphere_limiter/` is the one directory that needs reading rather than
listing: it holds both the pre-fix reading, under
`before_issue_64_fix/`, and the re-run beside it. *Keeping an earlier reading of
the same configuration* below says why.

## What goes in `output/<run>/`

Reduce before copying. The run's `output_dir` also holds the NetCDF diagnostics
and the checkpoints; those stay on Levante scratch and `provenance.txt` is what
points back to them. Nothing else is committed.

  - `<family>_tag_closure.csv`, verbatim from `output_dir`. The table the
    closure check wrote, one row per firing.
  - `<family>_tag_audit.csv`, verbatim, **when the run set `audit: true`**.
    Four configs do: `a5_sphere_limiter`, `c0_sphere_deep`,
    `c0_sphere_audit` and `c1_sphere_shift`. The model writes
    it, not the reducer, and `analysis/reduce_run.jl` names it in its last log
    line so it is not left on scratch. `untagged` and `overclaimed` are the two
    signed halves of the closure table's `gross_residual` and add to it exactly,
    `orphaned` is the mass in cells whose parent holds water while every tag is
    empty, and `nonpositive_mass` is the mass counterpart of the closure table's
    volume fraction. Join it to the closure table on `time`.
  - `operator_residual.csv`, from `analysis/reduce_run.jl`. One row per
    diagnostic time with the maximum absolute operator residual, and beside it
    the maximum absolute `q_tag_res` and the summed ledger on their own, so the
    decomposition can be checked rather than trusted.
  - `<run>.yml`, the merged configuration snapshot the run writes next to its
    output. This pins what actually ran, including every default in force at the
    time, which a file in `configs/` does not.
  - `run.log`. The `Simulation info` line, the `sypd` and
    `wall_time_per_timestep` lines, every warning, and the final status. Trim
    the rest.

    The first three runs came back without one, because the root `.gitignore`
    has a global `*.log` and `git add` dropped the file without saying so. This
    directory now re-includes it, so a `run.log` added from here on is
    committed.

    Those three carry their full `.err` instead, which nothing ignores. That is
    not a loss of information — Julia logs through `@info`, so `Simulation
    info`, `sypd` and `wall_time_per_timestep` are all on stderr and all
    present — but it is a thousand lines where the hand-back asks for a trimmed
    handful. Trimming them into `run.log` is worth doing when convenient; it is
    not worth resubmitting anything for.
  - `provenance.txt`. The commit the run used, the Julia version, the date, the
    node type and the partition, the SLURM job id, and the scratch paths to the
    NetCDF and the checkpoints. None of these is stable across months on that
    system, so a result without them cannot be set against a later one.

### Keeping an earlier reading of the same configuration

When a configuration is run again against a changed model, the earlier reading
is not deleted and not overwritten. It moves into a subdirectory of its own run
directory, named for what changed:
`output/a5_sphere_limiter/before_issue_64_fix/` holds the pre-fix A5 files, and
`output/a5_sphere_limiter/` is otherwise empty until the re-run lands.

A subdirectory rather than a sibling directory, because `load_run` reads files
by name inside a run directory and never descends, so an archive there is
invisible to the analysis without any rule about names. `load_run` skips a
directory holding no files of its own, silently, so a run directory waiting on
its re-run does not warn on every analysis. A real run always hands back at
least `provenance.txt`, including a timing control, which writes no closure
table, so nothing that is a run can be skipped by that rule.

**A run whose provenance does not name the commit is not analysed.** That means
a missing `provenance.txt` and equally one recording `commit: unknown`: a
residual without the commit that produced it cannot be placed against the rest
of the series either way. The analysis warns and skips the run rather than
failing, so one bad provenance does not stop a phase.

### Repairing a provenance

A run refused this way is usually a good run with a bad file, and it should be
repaired rather than resubmitted. The runscript now resolves the commit before
`module purge` and falls back to reading `.git` directly, so new runs record it;
`a1_dt10`, submitted before that fix, does not.

To repair one, on the machine holding the clone the job ran from, with that
clone still at the commit it ran:

```bash
git -C ~/git/ClimaAtmosResiDyn.jl rev-parse HEAD
git -C ~/git/ClimaAtmosResiDyn.jl rev-parse --abbrev-ref HEAD
```

Then edit the run's `provenance.txt`: replace `commit: unknown` with that hash,
`branch: unknown` with that branch, and set `commit_dirty: unknown`. **Leave it
as `unknown`.** The old runscript wrote `yes` there whenever git failed, so that
`yes` is the failure path firing and not an observation, and nothing now can
tell whether the tree was clean at submit time. Add `commit_source: repaired-by-hand`
so the next reader knows the line was reconstructed rather than recorded.

If the clone has moved on since the run, the commit is whatever it was at
`started:` in that same file; `git reflog` on that clone will find it. If it
cannot be established at all, the run is not usable as a measurement and should
be resubmitted.

## Open items

  - ~~The resolution and length of B1, and whether it runs on the shared
    partition or one GPU.~~ **Decided by the owner:**
    `config/common_configs/numerics_sphere_he6ze10.yml`, ten days, on the shared
    CPU partition. That is the grid the shipped `baroclinic_wave_tagged_tracers`
    job runs on, so B1, B2 and `c0_sphere` share a mesh and the docs'
    below-one-percent figure is comparable rather than a fresh measurement. No
    GPU work is needed and `phase_b.sh` stands as written.
  - Where large outputs live on Levante, so this page can record the path.
  - Whether C3 also wants a sphere counterpart. As registered it is the column
    only, since C3 compares two readings of one run and the column is the cheap
    one.
  - ~~**A5 diverges, and the integration test cannot see it.**~~ **The fix is
    merged and the re-run has landed.** Both decisions
    that were left open here have been taken, and one of them differently from
    how it was framed. `water_tag_rescale_ratio` was not instrumented; it was
    removed, replaced by an additive redistribution, so there is no ratio left
    to measure. `test/tagged_water_integration.jl` was not lengthened either:
    `t_end` is still one hour, and what changed is the assertion, which now
    bounds each tag and the residual against the *local* parent on well
    populated cells instead of against the global maximum of `ρq_tot`.

    **That leaves the coverage gap open, and it should be said plainly.** At
    one hour the archived pre-fix run has `max |q_tag_res|` of 7.5e-6 kg kg⁻¹
    and at two hours 6.0e-5, against a moist parent of order 1e-2 kg kg⁻¹ in
    the cells the new bound keeps, so the strengthened residual assertion would
    still have passed on the model that diverged. (Those maxima are over the
    remapped lat-lon field, so the model's own maximum is at least as large;
    bilinear interpolation does not hide three orders of magnitude, which is
    what would be needed to change the conclusion.) The tag-ratio half of the
    new assertion cannot be evaluated from the committed tables at all. So the
    test is a better test and it is not yet a test that would have caught this;
    whether to lengthen it remains the owner's call. See the A5 entry in
    `LEARNINGS.md`.
  - ~~**A3 needs a matched companion to be read cleanly.**~~ **Written as
    `a3_0m_vert_diff`.** Kept here for the reason it is the right companion: A3
    sets `vert_diff`, which is the only one of the three 1M `q_tot_eff`
    operators a column can reach — hyperdiffusion's branch is horizontal and the
    viscous sponge is off — so A3 differs from `a1_dt10` in
    `microphysics_model` and `vert_diff` together, and one 0M column with
    `vert_diff` on separates them. It needs no approval, only the queue.
  - **Whether the sphere runs should use MPI ranks.** Every runscript here runs
    one process with `CLIMACOMMS_CONTEXT=SINGLETON` and no `srun`, which is
    plainly right for phase A's column and sidesteps the CPU/GPU preferences
    clash that `runscripts/README.md` describes. At `h_elem` 6 with `z_elem` 10
    the B and C spheres are the resolution the existing CI job already runs
    single-process, so nothing here needs ranks to work; ten days of B1 is the
    longest of them and is the one to time first. If a later phase raises the
    resolution, or B1 turns out to overrun the shared partition's wall clock,
    the change is `--ntasks`, `CLIMACOMMS_CONTEXT=MPI` and an `srun` in front of
    the driver, and at that point the stack-selection warning in
    `runscripts/README.md` starts to matter. Not a problem now; worth knowing
    where the edge is.
