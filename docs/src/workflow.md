# Workflow: From Setup to Long Simulations

This page is the map. It walks the whole path a new user takes — installing the
model, getting a first run to complete, growing a configuration, and finally
running multi-year simulations on a cluster — and links to the detailed page for
each step. Read it once end to end; afterwards you will mostly use it to find
the right stage.

| Stage | What you do | Details |
|:--|:--|:--|
| 1 | Set up the environment | [Installation](installation.md) |
| 2 | Verify the install with a cheap run | below |
| 3 | Pick and adapt a configuration | [Custom Configurations](config.md) |
| 4 | Short test run, check the output | [Diagnostics](diagnostics.md) |
| 5 | Decide what to save | [Diagnostics](diagnostics.md), below |
| 6 | Scale up resolution and hardware | below |
| 7 | Run long, in segments, on a cluster | [Restarts](restarts.md), below |
| 8 | Monitor and post-process | below |

## 1. Set up the environment

Clone the repository and instantiate the bundled `.buildkite` environment, which
pins the exact dependency versions used in CI:

```bash
git clone https://github.com/CliMA/ClimaAtmos.jl.git
cd ClimaAtmos.jl
julia --project=.buildkite -e 'using Pkg; Pkg.instantiate()'
```

!!! warning "Use the pinned environment and the matching Julia version"
    The manifest is per Julia minor version (`.buildkite/Manifest-v1.11.toml`).
    Running a *different* Julia minor version ignores that manifest and
    re-resolves dependencies from scratch, which can pick package versions the
    source does not support — the failure then appears far from its cause,
    typically as a `MethodError` while the configuration is being built.

    For the same reason, do not invent ad-hoc environments such as
    `--project=test`. There is no `test/Project.toml`: test dependencies come
    through the package test path (`Pkg.test()`), and pointing `--project` at a
    directory without a manifest silently creates a new, unpinned environment.

Check what you actually got before going further:

```bash
julia --project=.buildkite -e 'using Pkg; println(VERSION); Pkg.status()'
```

For GPUs, see the [GPU support](installation.md) section — the device is
auto-detected, and can be forced with the `CLIMACOMMS_DEVICE` environment
variable or the `device` key in a configuration.

## 2. Verify the installation

Run the unit tests for a subsystem you care about, then one cheap simulation:

```bash
# unit tests (fast, no simulation)
TEST_GROUP=dynamics julia --project -e 'using Pkg; Pkg.test()'

# a single-column simulation (minutes, not hours)
julia --project=.buildkite .buildkite/ci_driver.jl \
    --config_file config/model_configs/single_column_hydrostatic_balance_ft64.yml \
    --job_id check_install
```

If both succeed, the installation is sound and any later failure is about your
configuration, not your setup.

## 3. Pick and adapt a configuration

Configurations are YAML. `config/default_configs/default_config.yml` is the
schema and the source of defaults; every other file is an overlay that changes
a subset of keys. Overlays are applied in order, so later `--config_file`
arguments win:

```bash
julia --project=.buildkite .buildkite/ci_driver.jl \
    --config_file config/common_configs/numerics_sphere_he6ze10.yml \
    --config_file config/model_configs/baroclinic_wave.yml \
    --job_id my_run
```

Start from an existing file rather than a blank one:

  - `config/model_configs/` — standard cases (baroclinic wave, Held–Suarez,
    aquaplanet, single column).
  - `config/longrun_configs/` — the production-scale versions of those cases;
    read these to see what a realistic long run sets.
  - `config/common_configs/` — reusable numerics/resolution blocks.
  - `config/gpu_configs/`, `config/mpi_configs/` — device- and MPI-specific
    overlays.

The keys you will touch first are `dt`, `t_end`, `initial_condition`,
`microphysics_model`, `rad`, `surface_setup`, and the grid (`h_elem`,
`z_elem`, `z_max`). `--job_id` names the output directory. See
[Custom Configurations](config.md) for the full schema and
[Script vs Config Interface](interfaces.md) if you would rather build the
simulation in Julia than in YAML.

## 4. Short test run

Before committing cluster time, run the *same configuration* you intend to use,
with `t_end` cut to hours and (if it is a global run) a coarse grid. Confirm
that it completes, that the output directory is populated, and that the fields
you asked for are actually there. Cheap failures here are the ones that would
otherwise appear six hours into a queued job.

## 5. Decide what to save

Two independent output streams, both configured in YAML:

**Diagnostics** — the scientific output (NetCDF by default), time-averaged over
the period you request:

```yaml
diagnostics:
  - short_name: [ta, ua, va, wa, pfull]
    period: 1days
  - short_name: [rsdt, rsut, rlut]
    period: 1hours
```

See [Computing and Saving Diagnostics](diagnostics.md) for reductions, writers,
and the catalogue of [Available Diagnostics](available_diagnostics.md).

**Checkpoints** — the full prognostic state, used to restart:

```yaml
dt_save_state_to_disk: "10days"
```

Checkpoints are large: they hold every prognostic field on the model grid. Save
them often enough to bound the work lost to a crash or a wall-time limit, and
no more. Diagnostics are what you analyse; checkpoints are what you resume from.

Output location is governed by `output_dir` and `output_dir_style`. The default
`ActiveLink` treats the output directory as a base and creates a numbered
subdirectory per run, with `output_active` pointing at the most recent — this is
what makes the automatic restart detection in stage 7 work.

## 6. Scale up

Increase cost along one axis at a time, re-running briefly after each change:

  - **Resolution**: `h_elem` (horizontal elements per cube face) and `z_elem`.
    Cost grows steeply; horizontal refinement also forces a smaller `dt`.
  - **Timestep**: `dt` is limited by stability. If a run produces `NaN`s or
    blows up shortly after a resolution increase, reduce `dt` first.
  - **Hardware**: a GPU via `device`/`CLIMACOMMS_DEVICE`, or multiple ranks via
    MPI, launched with `srun`:

```bash
srun julia --project=.buildkite .buildkite/ci_driver.jl \
    --config_file config/model_configs/<config>.yml --job_id my_run
```

Read the throughput off the log of a short run before sizing a long one. Each
run reports lines like:

```
[ Info: sypd: 3.725
[ Info: wall_time_per_timestep: 220 milliseconds, 638 microseconds
```

`sypd` (simulated years per day) is what you divide your target simulation
length by to get wall-clock time.

## 7. Run long simulations on a cluster

Clusters cap job wall time, so a long simulation is run as a **chain of
segments**: each job runs until its wall-time limit, writes checkpoints, and the
next job resumes from the last one.

Set the run up so it can find its own checkpoint:

```yaml
output_dir: /scratch/<user>/my_experiment
output_dir_style: "ActiveLink"   # the default
dt_save_state_to_disk: "10days"
detect_restart_file: true        # resume automatically when a checkpoint exists
t_end: "10years"                 # the *total* target, not the per-job length
```

With `detect_restart_file: true` (which requires `ActiveLink`), the identical
submission script both starts the run and continues it: the first job finds no
checkpoint and starts from the initial condition; every later job finds the
latest checkpoint and resumes. You do not edit the configuration between
segments.

A generic SLURM script — adapt the partition, account, and resource lines to
your site:

```bash
#!/bin/bash
#SBATCH --job-name=my_experiment
#SBATCH --output=logs/%x_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --time=08:00:00
#SBATCH --partition=<partition>
#SBATCH --account=<account>

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

srun julia --project=.buildkite .buildkite/ci_driver.jl \
    --config_file config/my_experiment.yml \
    --job_id my_experiment
```

Submit it repeatedly to advance the chain. Each job stops when it reaches its
wall-time limit; the next resumes from the last checkpoint:

```bash
sbatch my_experiment.sbatch                       # first segment
sbatch --dependency=afterany:<jobid> my_experiment.sbatch   # queue the next
```

Two cautions:

  - **Leave margin.** A job killed at the wall-time limit loses everything since
    its last checkpoint. Choose `dt_save_state_to_disk` so that at least one
    checkpoint lands comfortably inside each job.
  - **Restarts are not bit-reproducible by default.** Set
    `reproducible_restart: true` if you need a segmented run to match an
    unsegmented one exactly; expect a performance cost. See
    [Restarts and Checkpoints](restarts.md).

## 8. Monitor and post-process

While running, watch the job log: it reports progress, `sypd`, and per-timestep
wall time. A sudden slowdown or a `NaN` usually points at a timestep or
stability problem introduced by the last configuration change.

Afterwards, the NetCDF diagnostics in `output_dir/output_active/` are the
analysis product. They are on a remapped latitude–longitude grid, so they can be
opened directly with any standard tool
([ClimaAnalysis.jl](https://github.com/CliMA/ClimaAnalysis.jl), xarray, NCO).
Checkpoint HDF5 files are *not* meant for analysis: they store the packed model
state, so individual fields are not visible as named datasets — read them back
through `ClimaCore.InputOutput` if you need the raw state.

## Troubleshooting checklist

Work down this list before suspecting the physics:

 1. **Wrong Julia version?** The pinned manifest is per minor version. A
    `MethodError` raised while building the configuration is the classic
    symptom of a re-resolved environment.
 2. **Ad-hoc environment?** Use `--project=.buildkite` or `Pkg.test()`; delete
    any stray `Project.toml`/`Manifest.toml` you created inside `test/`.
 3. **Run blew up after a change?** Reduce `dt`; check whether the change
    increased resolution or enabled a stiffer parameterization.
 4. **No output?** Check `output_dir`/`output_active`, and that the requested
    diagnostic short names exist for your model configuration.
 5. **Restart did not resume?** `detect_restart_file: true` requires
    `output_dir_style: "ActiveLink"` and a checkpoint that was actually written
    — verify `dt_save_state_to_disk` is shorter than the segment length.
