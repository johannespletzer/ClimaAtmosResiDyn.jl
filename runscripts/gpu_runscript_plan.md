# Plan: Levante GPU runscripts for 1, 2 and 4 GPUs

Status: Phases 1 and 2 implemented on `xmodel.4gpus`; Phase 1a (F5) blocks
them from passing on hardware. Phases 3-5 outstanding. Nothing here has been
tested on hardware — the sandbox this was written in has no GPU, no Levante,
no `tcsh` and no `julia`, and no access to `docs.dkrz.de` (egress blocked).
Every number marked **[verify]** must be confirmed on a real node before it is
trusted, and Phase 1 needs one submitted job to confirm it behaves as intended.

## Goal

Replace the single `runscripts/xmodel.4gpus` with a consistent family of
runscripts covering 1, 2 and 4 GPUs on one Levante GPU node, so that a strong
scaling measurement is a matter of submitting three jobs rather than editing
one script three times. Along the way, fix the correctness problems that
currently make any performance number from `xmodel.4gpus` untrustworthy, and
adopt the CPU-to-GPU affinity advice from DKRZ user support.

## Motivating findings

Three separate issues, in descending order of expected impact.

### F1 — the GPU runscript does not match the stack it was built against

`runscripts/setup-julia-levante.tcsh` builds the `gpu` stack against
`nvhpc/24.7-gcc-11.2.0` + `openmpi/4.1.5-nvhpc-24.7`, writes `MPIPreferences`
pinning `libmpi` to that installation, and writes an
`artifacts/Overrides.toml` into a dedicated depot at
`~/.julia/depots/levante-gpu` so that `HDF5_jll`, `NetCDF_jll` and
`TempestRemap_jll` all resolve to the same system Open MPI. It prints four
requirements for jobs using the stack.

`runscripts/xmodel.4gpus` satisfies none of them:

| Requirement from `setup-julia-levante.tcsh` | `xmodel.4gpus` |
| --- | --- |
| `module load nvhpc/24.7-gcc-11.2.0` | loads `nvhpc/22.5-gcc-11.2.0` |
| `module load openmpi/4.1.5-nvhpc-24.7` | loads `openmpi/.4.1.4-nvhpc-22.5` |
| `export JULIA_DEPOT_PATH=~/.julia/depots/levante-gpu` | never set |
| `srun --mpi=pmix_v3` | never passed |

The consequence is that the job runs out of the default depot, where the
`OpenMPI_jll` override does not exist, with a `libmpi` different from the one
`MPIPreferences` records. The comment block in `setup-julia-levante.tcsh`
describes the resulting failure mode
(`libopen-pal.so.80: undefined symbol: pmix_framework_names`). Where it does
not fail outright, the risk is worse: `MPI.has_cuda()` can report `true` while
transfers silently take a staged host path. No amount of `UCX_*` tuning is
meaningful until this is resolved.

### F2 — no CPU binding policy, and one core per rank

```
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=1        # 4 cores out of 128
srun --cpu-bind=verbose --distribution=block:cyclic
```

`--cpu-bind=verbose` sets verbosity only; it specifies no policy. With
`--cpus-per-task=1` the four ranks land on the first cores of the node while
their GPUs sit up to four NUMA hops away, so every host-side staging buffer
and every NetCDF write crosses the Infinity Fabric. `--distribution=block:cyclic`
additionally alternates ranks across sockets, working against any
affinity-driven layout.

### F4 — `ROOT` could not be resolved under `sbatch`

Observed on Levante: `Julia project not found: /var/spool/slurmd/.buildkite`.

Every runscript derived the repository from `${BASH_SOURCE[0]}`. `sbatch`
copies the script to the node's spool directory before running it, so
`BASH_SOURCE` is `/var/spool/slurmd/job<id>/slurm_script` and its parent is
`/var/spool/slurmd`. The scripts therefore only ever worked when run directly,
never through the batch system they exist for.

Fixed by resolving from `SLURM_SUBMIT_DIR` (or its parent, so submitting from
`runscripts/` also works), falling back to `BASH_SOURCE` for a direct run, and
requiring the candidate to actually contain `.buildkite/` and `runscripts/` so
a wrong guess fails immediately with an actionable message. `ROOT=` in the
environment still overrides.

This is more acute after Phase 1 than before it: `levante_stacks.env` is looked
up under `${ROOT}` too.

### F5 — the CUDA toolkit pin is written where the loader may not see it

Observed on Levante: `setup-julia-levante.tcsh gpu` writes
`[CUDA_Runtime_jll] version = "13.0"` into
`.buildkite/LocalPreferences.toml`, the second `Pkg.instantiate()` downloads
nothing, and verification ends with `CUDA platform tag: none`, i.e. no toolkit
was installed.

The script already knows the rule that probably explains this. It refuses to
run unless `MPIPreferences` is a **direct** dependency of `.buildkite`,
commenting that a project-local preference is only visible for a direct
dependency. `CUDA_Runtime_jll` is not a direct dependency of `.buildkite` —
it arrives indirectly through `CUDA` — and the same rule was never applied to
it.

Confirmed on Levante. With the GPU depot active and `--project=.buildkite`:

```
julia> Base.get_preferences(Base.UUID("76a88914-d11a-5bdc-97e0-2f5a05c973a2"))
Dict{String, Any}()
```

The pin was written to `LocalPreferences.toml` and read back as nothing.
`Base.get_preferences` resolves the names in that file to UUIDs through the
project's own `[deps]`, so a preference for a package that is only an indirect
dependency is silently ignored — no warning, no error, just a toolkit that
never installs.

Fixed by listing `CUDA_Runtime_jll` in `.buildkite/Project.toml`, and by
extending the setup script's existing direct-dependency assertion to cover it
alongside `MPIPreferences`.

### F3 — stale references

- `setup-julia-levante.tcsh` refers to `runscripts/xmodel.gpu*`; the file is
  `xmodel.4gpus`.
- The same script claims the GPU runscripts re-check the driver's CUDA version
  against the node they land on and refresh
  `${DEPOT}/levante-cuda-version`. `xmodel.4gpus` does no such thing.
- `xmodel.cpu` uses the deprecated `--cpu_bind` underscore spelling and carries
  `--hint=nomultithread` only on the `srun` line, not in the `#SBATCH` block.

## Assessment of the DKRZ support advice

Summarised for the record so the reasoning behind the phases below is
traceable.

| Suggestion | Verdict |
| --- | --- |
| Parallelise the CPU part with OpenMP | **Not applicable.** ClimaAtmos is Julia; there is no OpenMP layer. `src/config/type_getters.jl:454` makes the device one exclusive choice, and `CLIMACOMMS_DEVICE=CUDA` puts all tendency and dynamics kernels on device. What remains on the host — setup, precompilation, NetCDF output, GC — is not OpenMP-parallel. `OMP_NUM_THREADS=1` stays. |
| `--gpu-bind=closest --hint=nomultithread` for CPU/GPU affinity | **Adopt, with corrections.** This is the largest available win (see F2). But `--gpu-bind=closest` cannot take effect alongside `--gpus-per-task=1`, which implies a per-task binding and pins `CUDA_VISIBLE_DEVICES` before `closest` gets a say; GPUs must be requested at node scope instead. And `--hint=nomultithread` is *already* an `#SBATCH` directive in `xmodel.4gpus`. The load-bearing change is `--cpus-per-task=16`, one NUMA domain per rank. |
| Per-rank `UCX_NET_DEVICES` from the NUMA domain | **Correct, but currently inert.** `xmodel.4gpus` is `--nodes=1`, and `UCX_TLS` already lists `cuda_ipc,cuda_copy,cma,mm`, so intra-node rank pairs never touch an HCA. Defer to the multi-node phase and guard on `SLURM_JOB_NUM_NODES > 1`. |
| `NUMA=$(nvidia-smi topo -m \| grep "^GPU" \| awk '{print $(NF-1)}')` | **Do not copy.** `$(NF-1)` is driver-version dependent: the trailing columns are `CPU Affinity`, `NUMA Affinity`, and on newer drivers also `GPU NUMA ID`, so the selected column changes silently with a driver upgrade — which this system has already had once, and which is the entire reason `select-cuda-runtime.jl` exists. It also yields a NUMA id, not an HCA, so a NUMA-to-`mlx5_N` map is still needed. Read sysfs instead (see Phase 4). |
| The ICON `run_wrapper_levante_gpu.tmpl` | **Borrow the pattern, not the content.** Its `numactl` placement is what Slurm does correctly given a sane `--cpus-per-task`. What is worth lifting is the shape: a thin wrapper between `srun` and the executable that derives per-rank environment from `SLURM_LOCALID` and `exec`s. That is the right home for `UCX_NET_DEVICES` in Phase 4, and the fallback for Phase 2 if Slurm's topology detection disappoints. |

## Target layout

`xmodel.4gpus` and `xmodel.cpu` already duplicate roughly 200 lines of
preamble — module loading, path resolution, the manifest/Julia version check,
the serial precompilation warm-up, the diagnostic banner. Adding two more GPU
variants by copy-paste would make three copies of the GPU logic and guarantee
they drift. Extract the GPU logic instead; leave the CPU script separate until
the project-local MPI preference issue below is resolved:

```
runscripts/
  levante_gpu_common.sh    # new: sourced by every GPU runscript
  xmodel.1gpu              # new: thin, #SBATCH + N_GPUS=1
  xmodel.2gpus             # new: thin, #SBATCH + N_GPUS=2
  xmodel.4gpus             # rewritten as a thin wrapper
  xmodel.cpu               # remains standalone; it uses a different MPI stack
  setup-julia-levante.tcsh # updated (F1, F3)
  select-cuda-runtime.jl   # unchanged
```

`#SBATCH` directives cannot be sourced, so each variant keeps its own header;
everything below it comes from `levante_gpu_common.sh`. The three GPU scripts
then differ only in `--ntasks-per-node`, `--job-name`, `--time` and the output
file pattern.

`levante_gpu_common.sh` provides:

- path resolution (`ROOT`, `PROJECT`, `SCRIPT`, `JULIA`, `JULIA_CHANNEL`) with
  the same environment-override behaviour as today,
- the Julia-vs-manifest version check,
- `levante_load_stack gpu` — modules, `JULIA_DEPOT_PATH`, and the `SRUN_MPI`
  value, all read from **one** table shared with
  `setup-julia-levante.tcsh` so F1 cannot recur,
- the UCX/Open MPI environment blocks,
- `levante_banner`, `levante_report_binding`, `levante_warm_precompile`,
- `levante_run` — the final `srun` plus exit-status and end-time reporting.

### Single source of truth for the stack

To make F1 structurally impossible rather than merely fixed once, the module
names, depot path and `--mpi` value move into a single file that both the tcsh
setup script and the bash runscripts read:

```
runscripts/levante_stacks.env       # plain KEY=VALUE, no shell syntax
```

`setup-julia-levante.tcsh` parses it with `sed`/`awk`;
`levante_gpu_common.sh` sources it. A runscript that loads a different MPI than
the depot was built against then requires editing a file whose only purpose is
to state the pairing.

This table prevents the module/depot pairing itself from drifting, but it does
not make the CPU and GPU installations independently runnable. Both setup
paths currently write MPI and CUDA preferences to the same
`.buildkite/LocalPreferences.toml`; the setup script explicitly requires being
rerun when switching stacks. In particular, a CPU setup performed after a GPU
setup leaves the GPU depot intact but changes the active project's `libmpi`
preference. The GPU runscript must therefore fail its Phase 1 preference check
with an instruction to rerun `setup-julia-levante.tcsh gpu`. Sharing the CPU
and GPU runscript preamble is deferred until they use separate active projects
or otherwise have stack-local preferences.

## Per-configuration parameters

Assumes a Levante GPU node: 2x AMD EPYC 7763 (128 physical cores), 8 NUMA
domains of 16 cores **[verify]**, 4x A100-SXM4-80GB, 4x HDR200 HCAs, one GPU
and one HCA per even-numbered NUMA domain **[verify]**.

| | `xmodel.1gpu` | `xmodel.2gpus` | `xmodel.4gpus` |
| --- | --- | --- | --- |
| `--ntasks-per-node` | 1 | 2 | 4 |
| `--gpus-per-node` | 1 | 2 | 4 |
| `--cpus-per-task` | 16 | 16 | 16 |
| `--hint=nomultithread` | yes | yes | yes |
| `--exclusive`, `--mem=0` | yes | yes | yes |
| `CLIMACOMMS_CONTEXT` | `MPI` (see below) | `MPI` | `MPI` |

`--exclusive` is kept for all three so that the 1- and 2-GPU jobs are not
sharing a node's memory bandwidth or HCAs with someone else's job. This costs
queue-time fairness but is the only way the three numbers are comparable, which
is the whole point of producing them.

`--cpus-per-task=16` on all three: one NUMA domain per rank. The 4-GPU job
therefore uses 64 of 128 cores. That is intentional — the other four NUMA
domains have no GPU attached, and a rank spanning two domains would have half
its cores far from its device.

### The 1-GPU baseline and MPI

The 1-GPU script should be runnable both ways:

- `CLIMACOMMS_CONTEXT=MPI` with one rank — the correct baseline for a scaling
  curve, since it carries the same MPI initialisation and halo-exchange code
  path as the 2- and 4-GPU runs.
- `CLIMACOMMS_CONTEXT=SINGLETON` — isolates what MPI costs at one rank.

Default to `MPI`; expose `CLIMACOMMS_CONTEXT` as an environment override in the
header comment. Running both once is worth the node-hour: if they differ
noticeably, the scaling curve's baseline is measuring MPI overhead rather than
the model.

## Phases

### Phase 1 — correctness (blocks everything else)

1. Add `runscripts/levante_stacks.env` with the `cpu` and `gpu` stack
   definitions taken from `setup-julia-levante.tcsh` as it stands
   (`nvhpc/24.7-gcc-11.2.0`, `openmpi/4.1.5-nvhpc-24.7`,
   `~/.julia/depots/levante-gpu`, `pmix_v3`).
2. Point `setup-julia-levante.tcsh` at that file.
3. Fix `xmodel.4gpus` to load the `gpu` stack from it, export
   `JULIA_DEPOT_PATH`, and pass `srun --mpi=pmix_v3`.
4. Add an assertion to the existing CUDA/MPI device-test `srun` block: the
   loaded `libmpi` path must equal the `libmpi` recorded in
   `.buildkite/LocalPreferences.toml`, and no `libmpi`/`libopen-pal`/`libpmix`
   may come from `/artifacts/`. `setup-julia-levante.tcsh` already performs
   exactly this check at setup time; running it again inside the job is what
   would have caught F1.
5. If that assertion finds the CPU stack in the shared project preferences,
   stop with an instruction to rerun `setup-julia-levante.tcsh gpu`; selecting
   the GPU depot alone cannot repair a project-local preference.

**Exit criterion:** `xmodel.4gpus` reaches the device test and it passes,
with the assertions from (4) active.

### Phase 1a — make the CUDA toolkit pin take effect (F5)

Phase 1's preference check fails the job when no toolkit is pinned, which is
correct but was unsatisfiable: the GPU setup could not produce a working pin.

1. Done — `CUDA_Runtime_jll` is now a direct dependency of `.buildkite`
   (UUID `76a88914-d11a-5bdc-97e0-2f5a05c973a2`, compat `0.21` matching the
   `0.21.0+1` the manifest already resolves), and
   `setup-julia-levante.tcsh` asserts it alongside `MPIPreferences`.
2. **Manual step, once:** adding a direct dependency invalidates the
   manifest's `project_hash`, so the manifest must be regenerated on a login
   node (compute nodes have no network) and the result committed:

   ```bash
   julia +1.11 --project=.buildkite -e 'using Pkg; Pkg.resolve()'
   git diff .buildkite/Manifest-v1.11.toml
   ```

   Expect only `project_hash` to change, plus `CUDA_Runtime_jll` gaining no
   new entry (it is already in the manifest at a compatible version). If
   package versions move, stop and inspect — that is not what this change
   should cause.
3. Re-run `./runscripts/setup-julia-levante.tcsh gpu`.

**Exit criterion:** `setup-julia-levante.tcsh gpu` completes with a CUDA
platform tag other than `none`, and the `Base.get_preferences` probe in F5
returns the pinned version rather than an empty dictionary.

### Phase 2 — affinity

1. Change `--gpus-per-task=1` to `--gpus-per-node=N` and `--cpus-per-task=1`
   to `--cpus-per-task=16`.
2. `srun --gpu-bind=closest --cpu-bind=verbose,cores --distribution=block:block`.
3. Extend the diagnostic `srun` block to report the mapping actually obtained:

   ```bash
   srun --label --kill-on-bad-exit=1 bash -c '
       echo "localid=${SLURM_LOCALID}" \
            "cpus=$(grep Cpus_allowed_list /proc/self/status | cut -f2)" \
            "numa=$(grep Mems_allowed_list /proc/self/status | cut -f2)" \
            "gpu=${CUDA_VISIBLE_DEVICES:-unset}"
   '
   ```

4. Compare against each GPU's `local_cpulist` (Phase 4 snippet). If Slurm's
   topology detection does not produce the expected mapping, fall back to
   explicit `--cpu-bind=map_ldom:...` or to the rank-indexed wrapper from
   Phase 4 rather than arguing with `closest`.

**Exit criterion:** each rank's `Cpus_allowed_list` is the 16-core block local
to its `CUDA_VISIBLE_DEVICES` device, for all three of 1, 2 and 4 ranks.

### Phase 3 — the three runscripts

1. Extract `levante_gpu_common.sh` from `xmodel.4gpus` as it stands after
   Phase 2.
2. Write `xmodel.1gpu` and `xmodel.2gpus` as thin headers over it.
3. Keep `xmodel.cpu` separate. Fix its `--cpu_bind` spelling and move
   `--hint=nomultithread` into its `#SBATCH` block independently, without
   suggesting that CPU and GPU jobs can switch stacks without rerunning setup.
   It also carries the same F1 defect as the GPU script did — it sets no
   `JULIA_DEPOT_PATH` and passes no `srun --mpi=`, so it runs out of the
   default depot without the `OpenMPI_jll` override. Its module pair happens
   to match `LEVANTE_CPU_*`, so this is less acute than on the GPU side, but
   it is the same bug and should be fixed with the same three lines, reading
   the `cpu` stack from `levante_stacks.env`.
4. Confirm all three GPU scripts still submit and reach the model with an
   unchanged configuration after the GPU setup path has run.

**Exit criterion:** three GPU runscripts, one shared GPU library, no duplicated
GPU preamble; each of `xmodel.1gpu`, `xmodel.2gpus`, `xmodel.4gpus` completes a
short run of `experiments/passive_stratospheric_tracers.jl`. A subsequent CPU
setup must cause the GPU script's preference check to fail early and clearly.

### Phase 4 — multi-node (deferred)

Only once 1/2/4 on a single node are solid.

1. Add `runscripts/levante_rank_wrapper.sh`, in the shape of the ICON wrapper:
   derive per-rank environment from `SLURM_LOCALID`, then `exec "$@"`.
2. In it, set `UCX_NET_DEVICES` — guarded, because it is counterproductive
   intra-node:

   ```bash
   if (( ${SLURM_JOB_NUM_NODES:-1} > 1 )); then
       export UCX_NET_DEVICES="${LEVANTE_HCA_FOR_LOCALID[$SLURM_LOCALID]}:1"
   fi
   ```

3. Build the GPU-to-NUMA-to-HCA map from sysfs, not from `nvidia-smi topo -m`:

   ```bash
   bdf=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader | head -1 |
         tr 'A-F' 'a-f')
   numa=$(cat "/sys/bus/pci/devices/${bdf}/numa_node")
   cpus=$(cat "/sys/bus/pci/devices/${bdf}/local_cpulist")
   ```

   Levante GPU nodes are homogeneous and fixed, so the map should be a
   hardcoded 4-entry table with the sysfs read kept as a one-shot assertion in
   the diagnostic block. Deriving it on every launch buys nothing and adds a
   failure mode.
4. Re-check `UCX_TLS`: the current `cma,rc,mm,cuda_ipc,cuda_copy,gdr_copy` is
   fine below ~150 nodes; DKRZ recommend a `dc_mlx5`-based list above that.
   Note also that `gdr_copy` requires the `gdrcopy` kernel module — confirm it
   is loaded, or UCX warns and falls back silently.

### Phase 5 — documentation

1. Fix the `xmodel.gpu*` reference in `setup-julia-levante.tcsh` (F3).
2. Either implement the CUDA-version re-check the setup script promises, or
   delete the claim. Implementing it is cheap — the GPU scripts already run
   `nvidia-smi` on the node — and it is what keeps the pin honest after a
   driver upgrade.
3. Add a short `runscripts/README.md`: which script for which purpose, the
   setup-then-submit order, and the environment overrides (`SCRIPT`, `PROJECT`,
   `JULIA_CHANNEL`, `CLIMACOMMS_CONTEXT`).
4. Record the Levante specifics in `docs/clima_atmos_specific.md` per the
   self-correction rule in `AGENTS.md`.

## Measurement

The three scripts exist to produce a scaling curve, so the measurement protocol
is part of the deliverable, not an afterthought.

- **Metric:** simulated years per wallclock day, or steps/second, taken from
  the model's own timing output after discarding the first N steps
  (compilation and the first I/O flush dominate otherwise).
- **Strong scaling:** identical configuration at 1, 2, 4 GPUs.
- **Problem size matters.** A configuration too small to saturate one A100
  will show flattering 1-GPU throughput and poor 4-GPU scaling, and the
  conclusion will be about the resolution rather than about the code. Choose a
  resolution where the 1-GPU run is comfortably device-bound, and state it
  alongside the numbers.
- **Baselines to capture:** before Phase 1, after Phase 1, after Phase 2. The
  Phase 1 delta is the honest measure of how much the stack mismatch was
  costing; the Phase 2 delta is the value of the affinity work. Without both,
  they are indistinguishable.
- Record results in `runscripts/README.md` with the date, the node's driver
  version, and the Julia/manifest version — none of these are stable across
  months on this system.

## Open questions

1. Is the Levante GPU node really 8 NUMA domains of 16 cores? The
   "GPU1 -> CPUs 16-31" example implies it, but the DKRZ table was not
   reachable from where this plan was written. Everything in Phase 2 depends
   on it.
2. Which two GPUs does Slurm allocate for `--gpus-per-node=2`, and are they on
   the same socket? On A100 SXM4 with NVSwitch the device-to-device bandwidth
   is pair-independent, so this affects the host side only — but it should be
   observed rather than assumed.
3. Is the `gpu` partition exclusive by default? If so, `--exclusive` is
   redundant but harmless; if not, it is essential for comparability.
4. Does `experiments/passive_stratospheric_tracers.jl` at the intended
   resolution actually saturate one A100? This determines whether a 1-GPU
   baseline is meaningful at all.
