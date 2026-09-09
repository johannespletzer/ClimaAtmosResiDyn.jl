# Tag-closure experiments

Configurations, runscripts, analysis and results for the experiments planned in
[the experiment plan](../../docs/src/tag_closure_experiments.md). The reasoning
behind them is in [the memo](../../docs/src/tag_closure_memo.md). Read the plan
before submitting anything. This page is the operator's copy of it: the run
order, one `sbatch` line per run, and the register to tick as results land. It
does not repeat the motivation or the decision rules.

**The owner submits every job by hand.** Nothing here runs on its own and no
agent submits to Levante. The agent writes the configurations, the driver, the
runscripts and the analysis. The owner runs each job, copies the small result
files into `output/`, and commits them. The agent then runs the analysis over
`output/`, produces the plots, and writes the entries in `LEARNINGS.md`.

## Layout

```
experiments/tag_closure/
  README.md            this page: the run order, the sbatch lines, the register
  LEARNINGS.md         the barrier register, one entry per run
  run_tag_closure.jl   the driver: one config path in, one run out
  configs/             one YAML per run, named <phase><n>_<variant>.yml
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

`analysis/` holds `reduce_run.jl`, `phase_a.jl` and `selftest.jl`. There is no
`phase_b.jl` or `phase_c.jl` yet, and there will not be until those phases have
configurations to read: a phase script is written against the columns its runs
actually produce, and writing one now would be guessing at them.

The phase B and C configurations are still to come, so `phase_b.sh` and
`phase_c.sh` have nothing to run yet and their wall times and memory are
provisional until the B1 resolution is settled.

## Analysis

Two scripts, both run with `--project=.buildkite`, which carries CairoMakie,
NCDatasets, DataFrames and Statistics. It does **not** carry CSV.jl, so these
read tables with `DelimitedFiles`.

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

`analysis/phase_a.jl` runs afterwards, over the committed `output/`, and writes
`output/summary_a.csv` plus three PNGs into `plots/`.

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

!!! warning "None of the Julia here has ever been run"

    The driver and the three analysis scripts were written in a container with
    no Julia, so nothing in `run_tag_closure.jl` or `analysis/` has been
    executed, and JuliaFormatter has not seen them either. `selftest.jl` is the
    owner's first real check and should be run before any job is submitted.

    The bash runscripts have been exercised against stub `julia` and `module`
    commands, including a simulation of `sbatch`'s spool-directory copy. **The
    tcsh variants have not been checked at all**: no `tcsh` was installed in
    that container, so not even their syntax has been parsed. Run one of them
    once by hand before relying on it.

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
What it cannot fill in is anything about the run's meaning: which register row
this is beyond the `job_id`, and why it was submitted. Add those by hand if they
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
  - **C1 and C2 wait for the discussion.** Both need a code change and the
    owner's approval, so no configuration for them is written yet.
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
| `c3_column_record` | `phase_c.sh` | C3, `c0_column` with `energy_process_record` beside the tags |

`c1_*` and `c2_*` are not written. C1 is the reference shift and C2 is the
implicit-path brackets; both need a code change and the owner's approval first.

## Run register

Tick a run once it has been submitted, once its files are committed under
`output/`, once the analysis has read it, and once its entry is in
`LEARNINGS.md`.

| Run                    | Phase | Submitted | Handed back | Analysed | Learning entry |
|:---------------------- |:----- |:--------- |:----------- |:-------- |:-------------- |
| `a1_dt10_notags`       | A     |           |             |          |                |
| `a1_dt10`              | A     |           |             |          |                |
| `a1_dt5`               | A     |           |             |          |                |
| `a1_dt2p5`             | A     |           |             |          |                |
| `a2_none_dt10`         | A     |           |             |          |                |
| `a2_none_dt5`          | A     |           |             |          |                |
| `a2_none_dt2p5`        | A     |           |             |          |                |
| `a2_first_order_dt10`  | A     |           |             |          |                |
| `a2_first_order_dt5`   | A     |           |             |          |                |
| `a2_first_order_dt2p5` | A     |           |             |          |                |
| `a3_1m`                | A     |           |             |          |                |
| `a4_float32`           | A     |           |             |          |                |
| `a5_sphere_limiter`    | A     |           |             |          |                |
| `b1_notags`            | B     |           |             |          |                |
| `b1_base`              | B     |           |             |          |                |
| `b1a_no_hyperdiff`     | B     |           |             |          |                |
| `b1b_no_vert_diff`     | B     |           |             |          |                |
| `b1c_neither`          | B     |           |             |          |                |
| `b2_dry_hs`            | B     |           |             |          |                |
| `b3_limiter`           | B     |           |             |          |                |
| `c0_column_notags`     | C     |           |             |          |                |
| `c0_column`            | C     |           |             |          |                |
| `c0_sphere`            | C     |           |             |          |                |
| `c3_column_record`     | C     |           |             |          |                |

## What goes in `output/<run>/`

Reduce before copying. The run's `output_dir` also holds the NetCDF diagnostics
and the checkpoints; those stay on Levante scratch and `provenance.txt` is what
points back to them. Nothing else is committed.

  - `<family>_tag_closure.csv`, verbatim from `output_dir`. The table the
    closure check wrote, one row per firing.
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
  - `provenance.txt`. The commit the run used, the Julia version, the date, the
    node type and the partition, the SLURM job id, and the scratch paths to the
    NetCDF and the checkpoints. None of these is stable across months on that
    system, so a result without them cannot be set against a later one.

**A run whose `provenance.txt` is missing is not analysed.** A residual without
the commit that produced it cannot be placed against the rest of the series.

## Open items

  - The resolution and length of B1, and whether it runs on the shared partition
    or one GPU.
  - The shape of the C1 reference shift, which the agent puts to the owner
    before writing either version.
  - Whether C0 runs alongside phase A.
  - Where large outputs live on Levante, so this page can record the path.
  - Whether C3 also wants a sphere counterpart. As registered it is the column
    only, since C3 compares two readings of one run and the column is the cheap
    one.
