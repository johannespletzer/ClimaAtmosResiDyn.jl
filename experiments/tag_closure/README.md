# Tag-closure experiments: the operator's guide for LRZ terrabyte

This directory holds the configurations, the driver, the runscripts, the
analysis and the record of the tag-closure experiments. **Start at
[STATUS.md](STATUS.md)**: the goals, where things stand, and where to look.
This page says how to set up, submit a run, record it and compare it, and
which traps are known.

The earlier operator's copy, written for DKRZ Levante and for the owner
submitting by hand, is [archive/2026-09-23/README.md](archive/2026-09-23/README.md).
It keeps what only applied there, and the details of the phase A to C
harness: the reducer, the phase scripts, the config validator and the
self-test.

## Layout

```
experiments/tag_closure/
  STATUS.md  ROADMAP.md  DECISIONS.md    the entry point, the milestones, the owner's decisions
  G3_PLAN.md  G3_TODO.md  G4_TODO.md     the current goal and the next
  BACKLOG.md                             open items beyond G3 and G4
  FINDINGS.md                            every established claim, numbered, with its run
  RUNS.md                                every run: commit, job, purpose, findings, where its data is
  design/  reference/                    live design notes; the frozen external reviews
  review/                                agent reviews, instructions, check scripts, the register
  archive/2026-09-23/                    the originals as they were on 2026-09-23
  run_tag_closure.jl                     the driver: one config path in, one run out
  run_c1_twin.jl                         C1's twin test
  configs/  overrides/                   one YAML per run; keys the twin test sets in both halves
  runscripts/                            phase_a.sh, phase_b.sh, phase_c.sh and their shared body
  analysis/                              the analysis; analysis/evidence/ holds the verifier and the manifest
  output/  plots/                        each run's small result files; the phase figures
```

## Setup, once

From the repository root:

    ./runscripts/setup-julia-terrabyte.tcsh cpu

The script is on this branch and in PR #96. It builds the Julia depot on
scratch, `/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu`,
against the stack in `runscripts/terrabyte_stacks.env`: `gcc/13.2.0` and
`openmpi/4.1.8-gcc13`. It points `OpenMPI_jll` at the system MPI, writes the
MPI preference into `.buildkite/LocalPreferences.toml`, and instantiates and
precompiles `.buildkite`. At the end it prints the depot and the modules that
every later Julia call needs:

    setenv JULIA_DEPOT_PATH /dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
    module load gcc/13.2.0
    module load openmpi/4.1.8-gcc13
    julia +1.11 --project=.buildkite ...

A batch job gets the same from the runscript. A depot on scratch is not
durable. If it is gone, run the setup script again.

For the Python tools, load `python/3.12`. Bare `python3` is 3.6 here.

    source $MODULESHOME/init/zsh     # tcsh: source $MODULESHOME/init/tcsh
    module load python/3.12

## Submitting a run

Submit from the repository root of the worktree whose code the run should
use. The configuration travels in the environment as `CONFIG`. Give the
account and the partition on the command line, since the scripts' `#SBATCH`
blocks are Levante's.

From a tcsh login shell:

    env CONFIG=experiments/tag_closure/configs/d4_column_edmf.yml \
        sbatch --account=hpda-c --partition=hpda2_test --time=02:00:00 \
            --cpus-per-task=2 --mem=48G \
            --output=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.out \
            --error=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.err \
            experiments/tag_closure/runscripts/phase_c.sh

Give `--output` and `--error` on scratch. The runscripts' own
`#SBATCH --output` is relative, so without them the logs land in the
worktree's root.

From bash or zsh, `CONFIG=... sbatch ...` works as well. Use the `.sh`
scripts. The `.tcsh` variants are Levante-only and have never run.

`phase_c.sh` serves every run since phase C. Phase A used `phase_a.sh` and B1
`phase_b.sh`; they differ only in their `#SBATCH` block. The runscript knows
these variables:

 - `CONFIG`, the run's YAML, required.
 - `DRIVER`, another driver in place of `run_tag_closure.jl`. V3 used
   `DRIVER=experiments/tag_closure/analysis/increment/v3_driver.jl`.
 - `RUN_DIR`, the run's working directory. The default on terrabyte is
   `$SCRATCH/tag_closure`.
 - `TAG_CLOSURE_JOB_ID`, to rename a run's output directory, so that a
   driver that is not the run's own, such as `run_c1_twin.jl`, cannot write
   over the real run.
 - `PROJECT`, the Julia project, `.buildkite` by default.

**Partitions and limits.**
 - `hpda2_test` has a two-hour limit. It started jobs at once on 2026-09-10,
   while `hpda2_compute` put a small job 30 hours out. Column runs go to
   `hpda2_test` where they fit in two hours, otherwise to `hpda2_compute`
   (G3_PLAN, section 6).
 - The standing approval of 2026-09-14 sized a column job at 2 CPUs, 48G and
   2 h. A one-day D4 column takes about 40 minutes.
 - A sphere on MPI: `--ntasks=24` on `hpda2_compute`, with `--mem=500G`. Each
   rank peaked at 16,752,519 KiB, about 17.2 GB or 16.0 GiB (`sacct` MaxRSS of
   jobs `13504999` and `13505896`).
   A first attempt with 200 GB was killed for memory. A node has 160 cores and
   about 1 TB (`sinfo`, checked 2026-09-23).
 - With more than one task, the runscript launches through `srun --mpi=pmix`
   with the MPI context. `pmi2` does not work here.

**Approval.** Model code, a default, a tolerance and an energy reference need
the owner's approval before they are written, and model code goes into draft
PRs that only the owner merges. Every job needs the owner's approval, or a
standing one. Today
the owner has approved every job within G3 (G3_TODO.md). Energy jobs belong
to the job session.

## Provenance: the manifest, at submission

Compute nodes have no git, so a run's `provenance.txt` records the commit
with `commit_dirty: unknown`. Stamp each submission on the login node with
`analysis/evidence/manifest.py`. It records the worktree's `HEAD`, every
changed and untracked file, the hashes of the `.buildkite` manifest, project
and preferences, and of the config and driver. Load `python/3.12` first
(`source $MODULESHOME/init/zsh; module load python/3.12`); bare `python3` is 3.6
here:

    python3 experiments/tag_closure/analysis/evidence/manifest.py \
        --repo . --config experiments/tag_closure/configs/<run>.yml \
        --command "<the sbatch line>" --out <path>.json
    python3 experiments/tag_closure/analysis/evidence/manifest.py --verify <path>.json

The manifest is not yet in the runscripts' path. G3 WP0 puts it there and
fixes where the JSON lives. Until then, keep it with the run's hand-back
files, as `output/<run>/manifest.json`. This place is a proposal.

## Comparing runs: the verifier

`analysis/evidence/compare_runs.py` compares two column runs. It checks that
both have every variable, the same times and the same levels. Then it reports
the parent's fields bit pattern by bit pattern, and each tag's L1, peak L∞ and
integral change per hour:

    python3 experiments/tag_closure/analysis/evidence/compare_runs.py \
        --reference <scratch>/output/<ref>/output_0001 \
        --run <scratch>/output/<run>/output_0001 --hours 1,6,24 --json <path>.json

Give an explicit `output_XXXX`. It refuses `output_active` and a bare run
directory, which can point at another run tomorrow. It reads column runs only.
Its six mutation tests are `test_compare_runs.py`. From G3 on, every headline
number goes through the verifier and a manifest (G3's criterion 1).
`analysis/evidence/README.md` describes both tools in full.

## Where results go

 1. The run writes to `$SCRATCH/tag_closure/output/<run>/output_XXXX/`, a new
    index for each submission, with `output_active` pointing at the newest.
    The NetCDF diagnostics and the checkpoints stay there.
 2. The runscript writes `provenance.txt` into that directory, whether the
    run succeeded or not.
 3. Run the reducer before copying anything back. It turns the NetCDF into
    the small tables: the operator residual and the per-tag extrema, which
    exist nowhere else once scratch is cleaned. With the scratch depot (Setup):

        julia +1.11 --project=.buildkite \
            experiments/tag_closure/analysis/reduce_run.jl \
            /dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/<run>/output_XXXX

    Then copy the small files into `output/<run>/` here: the closure table
    (`<family>_tag_closure.csv`), the reducer's tables, the audit table if
    `audit: true`, the merged `<run>.yml`, `<run>_parameters.toml`, `run.log` trimmed to its info lines, warnings and final
    status, `provenance.txt`, and any analysis text. A crashed run is handed
    back too: where its table stops is itself a measurement.
 4. When a configuration runs again on changed code, keep the earlier reading.
    Move it into a subdirectory of its run directory, named for what changed,
    as `output/a5_sphere_limiter/before_issue_64_fix/` does. Never overwrite
    it.
 5. Add the run to [RUNS.md](RUNS.md), and its result to
    [FINDINGS.md](FINDINGS.md) under the next free number: W15 on for water,
    E77 on for energy (E76 is the R2 ladder).
 6. Sync the archive before scratch is cleaned (RUNS.md says how).

## Traps that are still live

 - **Never `module purge` on terrabyte.** It drops `stack/24.4.0`, and the
   spack modules do not come back. The runscript never runs it.
 - **The scratch depot.** A Julia call without the terrabyte depot and the MPI
   module fails with `failed to find source of parent package`. That looks
   like a broken environment but is only the wrong depot. The test
   environments under `$SCRATCH/claude_work/*_testenv` need the same depot,
   and in a batch job also `module load gcc/13.2.0 openmpi/4.1.8-gcc13`.
 - **An MPI run looks stuck for about an hour.** `srun` buffers Julia's log.
   With 24 ranks the build took 43 minutes and the first step with the
   callbacks' compile another 50, at 30 to 55% CPU per rank (seen with `top` during V2's build on
   2026-09-19; recorded in the agents' memory notes, not in FINDINGS). Judge progress by
   the hourly NetCDF and the closure CSV, which are written as the run steps.
 - **Parity.** With a diagnostic on, every model field upstream has must stay
   bit for bit the same (`AGENTS.md`, "Fork parity with upstream"). Compare
   with bit patterns, as `compare_runs.py` does, not with `==`, which cannot
   see a signed zero. Bitwise agreement is expected only within one machine,
   one Julia and Manifest, one float type and one process count.
 - **`.buildkite/LocalPreferences.toml` is generated.** Never commit it. It is
   shared by every stack on every machine, so run the setup script again after
   working on another cluster.
 - **The analysis refuses a run whose provenance has no commit.** Repair the
   file rather than resubmit: set the commit and branch the job ran from, set
   `commit_dirty: unknown`, and add `commit_source: repaired-by-hand`. The
   archived README gives the procedure.
 - **Read the job's exit status.** The driver exits non-zero when the solve
   crashed, so `sacct` or the last line of the `.out` file answers it. The C1
   twin tests exit 1 by design when the twins differ.
 - **Sphere numbers are not column numbers.** The NetCDF writer remaps a
   sphere to latitude and longitude, so a sphere's maximum is over the
   remapped field.
 - **A closure check every step dominates the cost.** Check hourly or daily.
   Each distinct tag set is a new model type and a full compile.
 - **The tcsh command line.** `CONFIG=path sbatch ...` is not valid tcsh. Use
   `env CONFIG=path sbatch ...` or `setenv`.
 - **`gh` and the fork.** Pass `-R johannespletzer/ClimaAtmosResiDyn.jl` to
   every `gh` call. With a remote named `upstream`, `gh` otherwise targets
   `CliMA/ClimaAtmos.jl`. The token cannot cancel, rerun or dispatch Actions
   runs; the owner does that.
 - **Do not remove a worktree or branch** that the owner has not approved, and
   sync the archive first (DECISIONS.md, 2026-09-23).

## How the record is written

These conventions come from the handover notes of the series
([archive/2026-09-23/NEXT_SESSION.md](archive/2026-09-23/NEXT_SESSION.md),
register item `NS-2`).

 - **Cite the run.** Every claim in FINDINGS.md names the run it came from.
 - **State the bound with the claim.** One geometry, one resolution, an
   uncontrolled comparison: that is part of the finding.
 - **Never cite a verification that is not in the tree.** If a script
   verified something, commit the script.
 - **Record falsified claims rather than deleting them.** A committed
   measurement never changes. A correction is a dated erratum beside its
   entry.
 - **Recompute before repeating.** When a number matters to a decision, get it
   from the CSV yourself.
 - **A number lives in one place.** Elsewhere, point to its FINDINGS entry
   (the old README's rule).
