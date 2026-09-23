# Cluster runscripts

Batch scripts for running ClimaAtmos on the clusters this fork is developed on,
plus the one-time setup that makes Julia use each machine's system MPI.

Two machines are supported, and they are not interchangeable. DKRZ's **Levante**
has the full CPU and GPU story, including the submission scripts. LRZ's
**terrabyte** has the CPU stack only.

| File | What it is |
| --- | --- |
| `setup-julia-levante.tcsh` | Levante: one-time (per stack) depot build on a **login node**. |
| `levante_stacks.env` | Levante: the compiler/MPI/depot pairing. Read by the setup script and the GPU runscripts. |
| `setup-julia-terrabyte.tcsh` | terrabyte: one-time depot build on a **login node**. CPU only. |
| `terrabyte_stacks.env` | terrabyte: the compiler/MPI/depot pairing, and what was measured about `srun --mpi`. |
| `xmodel.1gpu`, `xmodel.2gpus`, `xmodel.4gpus` | Levante: GPU jobs, one rank per GPU. |
| `levante_gpu_common.sh` | Everything the three GPU scripts do, sourced by each. |
| `levante_gpu_rank_wrapper.sh` | Runs between `srun` and the command; pins each rank to its GPU's cores and memory. |
| `xmodel.cpu` | Levante: CPU job, 32 ranks on one node. Standalone — see "Two stacks, one preferences file". |
| `select-cuda-runtime.jl` | Pins the CUDA toolkit to what the driver supports. Called by the setup script. |
| `gpu_runscript_plan.md` | Why all of this looks the way it does, and what is still outstanding. |

## Running something on Levante

Once, on a login node (compute nodes have no network):

```bash
./runscripts/setup-julia-levante.tcsh gpu
```

Then, from the repository root:

```bash
sbatch runscripts/xmodel.4gpus
```

Overridable from the environment:

| Variable | Default |
| --- | --- |
| `SCRIPT` | `experiments/passive_stratospheric_tracers.jl` |
| `PROJECT` | `.buildkite` |
| `ROOT` | derived from `SLURM_SUBMIT_DIR` |
| `JULIA`, `JULIA_CHANNEL` | `$(command -v julia)`, `+1.11` |
| `CLIMACOMMS_CONTEXT` | `MPI` |
| `LEVANTE_DEPOT_ROOT` | `$HOME/.julia/depots` |

```bash
SCRIPT=experiments/my_run.jl sbatch runscripts/xmodel.2gpus
```

## Running something on terrabyte

Once, on a login node (compute nodes have no network):

```bash
./runscripts/setup-julia-terrabyte.tcsh cpu
```

The script finds the repository from its own location, so it needs no editing.
It loads `gcc/13.2.0` and `openmpi/4.1.8-gcc13`, writes the MPI preference and
the `OpenMPI_jll` override, instantiates, precompiles, and then verifies that
`MPI.jl`, `HDF5.jl` and `NCDatasets` all end up on the system MPI rather than a
bundled one.

Two things differ from Levante and are deliberate:

- **The depot lives on scratch**, at
  `/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu`, because
  `$HOME` on terrabyte is for code and configs. Override with
  `TERRABYTE_DEPOT_ROOT`. Nothing on scratch is durable; a lost depot is
  rebuilt by re-running the script.
- **`module purge` is never run.** On Levante it is load-bearing. Here it drops
  `stack/24.4.0` in a way that re-loading `stack` does not repair, so the script
  unloads only a conflicting MPI module.

There are no terrabyte submission scripts yet. Run jobs by hand, setting the
same depot and modules the script prints when it finishes:

```bash
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
export PMIX_MCA_psec=native OMPI_MCA_pmix=ext3x
srun --account=hpda-c --partition=hpda2_compute --mpi=pmix ... \
    julia +1.11 --project=.buildkite .buildkite/ci_driver.jl --config_file ...
```

`--mpi=pmix` is measured, not guessed. `--mpi=pmi2` does not work: this Open MPI
is built `--with-pmix` and has no usable PMI-2 path, so `MPI_Init` aborts. The
two `*_MCA_*` variables only silence PMIx startup noise.

The GPU stack is not set up. `setup-julia-terrabyte.tcsh gpu` exits with a
pointer to what is known: `nvhpc/24.9` carries a CUDA-aware Open MPI 4.1.5, and
the GPU partitions are `hpda2_compute_gpu` and `hpda2_testgpu`. Finishing it
means measuring the driver's CUDA version on a GPU node and pinning
`CUDA_Runtime_jll`, the way the Levante script does.

## Two stacks, one preferences file

`setup-julia-levante.tcsh cpu` and `... gpu` build separate depots but write to
the same `.buildkite/LocalPreferences.toml`. **Only the stack set up last
works.** Switching between CPU and GPU jobs means re-running the setup script.

The GPU runscripts detect this before launching any ranks: they compare the
`libmpi` recorded in the preferences against the module actually loaded and
stop with an instruction to re-run setup. Selecting the right depot is not
enough — the preference is project-local, not depot-local.

`.buildkite/LocalPreferences.toml` is **generated, and not tracked in git**. It
records an absolute `libmpi` path, so a committed copy follows a checkout onto
another cluster, where that path does not exist and every package downstream of
`MPI` fails to precompile. That is what it used to do. The cost is that a fresh
clone cannot instantiate until the setup script for that machine has run once.

Note also that `CUDA_Runtime_jll` and `MPIPreferences` must both stay listed in
`.buildkite/Project.toml`. Julia resolves the names in `LocalPreferences.toml`
to UUIDs through the project's own `[deps]`, so a preference written for a
package that is only an indirect dependency is read back as nothing — silently.

## Reading the binding report

Every GPU job prints, before it starts work:

```
rank=0 gpu=0 bdf=0000:44:00.0 cores=16-31,144-159 membind=1 cgroup-numa=0-7 \
    gpu-local-cores=16-31,144-159 gpu-numa=1 MATCH
```

- `MATCH` — the rank runs on the cores attached to its own GPU.
- `MISMATCH` — the rank wrapper asked for one set of cores and the job is
  running on another, so the binding did not take. The run still works; it is
  just slower than it should be. Worth investigating before trusting a timing.
- `UNBOUND` — the wrapper could not bind this rank and said why on stderr.
- `UNCHECKED` — the topology could not be read from sysfs.

`cores` is allowed to be a subset of `gpu-local-cores`. Slurm need not hand a
rank every logical CPU near its GPU — `--hint=nomultithread` keeps the SMT
siblings out — and the wrapper binds to the overlap of the two, never to cores
the rank was not given.

A rank that sees more than one GPU **fails the job deliberately**. All ranks
would default to device 0 and share it: the run would complete and only the
numbers would be wrong, which is the one failure a scaling curve cannot show
you.

`cgroup-numa` spanning all domains is normal and not a problem — `numactl
--membind` sets a policy rather than changing the cgroup. `membind` is the
field that matters.

## Multi-node

The `#SBATCH` headers request one node. For more, override at submit time:

```bash
sbatch --nodes=2 --time=02:00:00 runscripts/xmodel.4gpus
```

That gives 4 ranks and 4 GPUs per node. On a multi-node job each rank also
selects the InfiniBand HCA on its own NUMA node, reported as `hca=` in the
binding report; `hca=default` on a single-node job is correct, since
`UCX_TLS` keeps intra-node traffic on `cuda_ipc`, `cma` and `mm` and no HCA is
involved. Setting `UCX_NET_DEVICES` yourself overrides the choice.

Multi-node has not been run yet. The HCA selection is verified against a
simulated fabric only.

## Node layout (measured, August 2026)

A Levante GPU node: 128 physical cores in 8 NUMA domains of 16, SMT on for 256
logical CPUs, and 4 A100-SXM4-80GB.

| GPU (PCI) | NUMA | Cores |
| --- | --- | --- |
| `0000:44:00.0` | 1 | 16-31 + 144-159 |
| `0000:03:00.0` | 3 | 48-63 + 176-191 |
| `0000:c4:00.0` | 5 | 80-95 + 208-223 |
| `0000:84:00.0` | 7 | 112-127 + 240-255 |

The GPUs are on the **odd** domains; the even ones have no GPU. Nothing reads
this table — `levante_gpu_rank_wrapper.sh` derives the same mapping from sysfs
at run time, so a topology change needs no edit here. It is recorded because
it explains the shape of the runscripts, and because it is what a `MISMATCH`
should be compared against.

## Measuring

The three GPU scripts exist to produce a strong-scaling curve. To make the
numbers mean something:

- Use the same configuration and resolution for all three.
- Pick a resolution where the 1-GPU run is comfortably device-bound.
  A configuration too small to saturate one A100 produces a flattering 1-GPU
  number and poor 4-GPU scaling, and the result is then a statement about the
  resolution rather than about the code.
- Discard the first steps: compilation and the first I/O flush dominate them.
- `CLIMACOMMS_CONTEXT=SINGLETON sbatch runscripts/xmodel.1gpu` isolates what
  MPI costs at a single rank. If it differs much from the default `MPI` run,
  the baseline is measuring MPI overhead rather than the model.

Record results with the date, the driver's CUDA version and the Julia version.
None of the three is stable across months on this system.
