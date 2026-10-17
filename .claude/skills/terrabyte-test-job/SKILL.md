---
name: terrabyte-test-job
description: Run ClimaAtmosResiDyn.jl test files, a test group or the docstring reference check as a Slurm job on LRZ terrabyte, with the package versions GitHub CI resolves, on Julia 1.11 and 1.10, and report pass counts, wall time and peak memory. Use before marking a pull request ready, to reproduce a CI failure, to check memory against the 16 GB runners, or whenever a PR body is to claim local results with CI's versions.
---

# Test jobs on terrabyte with CI's package versions

A login node times out on the test files and has no Julia depot built for
them, so tests run as batch jobs. Two scripts do the work:

  - `scripts/make_ci_env.jl` builds a Julia environment that loads one
    checkout with the versions CI resolves.
  - `scripts/test_job.sh` runs test files, or a whole group, in such an
    environment, with each file's wall time and peak memory.
  - `scripts/submit.sh` submits any job and records it in the run's ledger,
    `JOBS.tsv`, and `scripts/job_wait.sh` lists the ledger's jobs or waits
    for them, so a session that restarts finds its jobs again.

The scripts live in the checkout's `.claude/skills/terrabyte-test-job/scripts/`,
outside the checkouts, so one copy serves every worktree. Run the commands
below from the checkout under test. `W=$SCRATCH/claude_work` holds
environments, logs and run directories. Nothing there is durable.

## 1. Get CI's versions

GitHub CI runs `Pkg.test()`, which resolves afresh every day. The pinned
`.buildkite/Manifest-v1.11.toml` lags it, by minor releases of ClimaParams
and SurfaceFluxes at times, and an environment built from it is not CI's. So
save the log of the latest successful CI test job for each Julia version:

```sh
# The latest run with a successful `ci 1.11 - <group>` job. Use 1.10 for the other.
for r in $(gh run list --workflow ci.yml --limit 60 --json databaseId --jq '.[].databaseId'); do
  j=$(gh run view $r --json jobs --jq '[.jobs[] | select(.conclusion=="success" and (.name|test("^ci 1.11 - ")))][0].databaseId')
  [ -n "$j" ] && [ "$j" != null ] && { echo "run $r job $j"; break; }
done
gh run view --job <job> --log > $W/ci_log_111.txt   # never print it whole
```

Most CI runs skip the test matrix, so the loop may need to go back a few days.
The fork's groups run on 1.10 nightly.

## 2. Build one environment per checkout and Julia version

On a login node, which has network. `zsh` is the agent shell:

```sh
source $MODULESHOME/init/zsh
module load gcc/13.2.0 openmpi/4.1.8-gcc13      # never `module purge`
source "${CLIMA_SITE_ENV:-$HOME/.config/climaatmos-fork/site.env}"   # account, partitions, depot
export JULIA_DEPOT_PATH=$CLIMA_JULIA_DEPOT
export CLIMA_SKILLS=$(git rev-parse --show-toplevel)/.claude/skills
S=$CLIMA_SKILLS/terrabyte-test-job/scripts
julia +1.11 $S/make_ci_env.jl <checkout> $W/<tag>_ci111_env test $W/ci_log_111.txt > $W/<tag>_env111.log 2>&1
julia +1.10 $S/make_ci_env.jl <checkout> $W/<tag>_ci110_env test $W/ci_log_110.txt > $W/<tag>_env110.log 2>&1
grep -E '^env |= CI|CI has|differ from|ERROR' $W/<tag>_env111.log
```

  - `test` gives `Pkg.test`'s sandbox: ClimaAtmos, its dependencies and the
    test target's extras. Packages that differ from the log are pinned to CI's
    versions. The last line must read `packages that differ from the CI log: 0`.
  - The log must come from a job on the same Julia version. The script refuses
    a mismatch, because the standard libraries' versions differ.
  - `buildkite` copies `.buildkite`'s project and pinned manifest, for
    `.buildkite/ci_driver.jl` runs. `docs` resolves `docs/Project.toml`, for
    the docstring check. `invalidations` is what the Invalidations workflow
    loads (see the `upstream-sync` skill).
  - `PINS="ClimaCore=1.0.2,SurfaceFluxes=1.3.0"` pins packages after CI's
    versions, to find which bumped package breaks a test. Packages the pins
    force to move are printed and recorded in `PROVENANCE`.
  - The environment points at the checkout by path, so it follows new commits
    in that worktree. A job reads the test files when it reaches them, so a
    commit while jobs run gives them a mix of old and new files under the
    old commit's label. Commit between runs, or resubmit the jobs that had
    not finished, as on 5af1766c. Rebuild it when `Project.toml`'s compat changes or CI's
    versions move. Name it after the worktree, such as `rsedmf_ci111_env`.
    Each mutant or comparison checkout gets its own.
  - Do not copy an environment to another checkout. A copy keeps the old
    checkout's package paths, and `.buildkite`'s `PrecompileCI` then fails
    to precompile with "Missing source file". `test_job.sh` warns when an
    environment has no `PROVENANCE`, the mark of one `make_ci_env.jl` did
    not build. The mutation-run skill's `make_mutants.jl` is the exception:
    it repoints ClimaAtmos at each mutant and writes `PROVENANCE`.
  - `LocalPreferences.toml` comes from `.buildkite`. If it is missing, run
    `./runscripts/setup-julia-terrabyte.tcsh cpu` once, or copy it from
    another checkout. One-process tests run without it.

## 3. Submit

```sh
env CODE=$PWD COMMIT=$(git rev-parse --short HEAD) TAG=<tag> VER=1.11 \
    ENV_DIR=$W/<tag>_ci111_env FILES="tagged_water_tests.jl tagged_water_integration.jl" \
    OUT=$W/<tag>_run \
  $CLIMA_SKILLS/terrabyte-test-job/scripts/submit.sh $W/<tag>_run <tag> "1.11, the files a change touches" -- \
    --time=01:55:00 \
    --cpus-per-task=4 --mem=48G --job-name=<tag> \
    --output=$W/<tag>_run/<tag>-%j.out $CLIMA_SKILLS/terrabyte-test-job/scripts/test_job.sh
```

  - Submit the 1.10 job alongside it with `VER=1.10` and the 1.10 environment.
  - The site file sets the account and the short partition through Slurm's
    own `SBATCH_ACCOUNT` and `SBATCH_PARTITION`, so `sbatch` needs neither
    flag. The short partition allows 2 hours on 2 nodes and starts quickly.
    For longer runs pass `--partition=$CLIMA_PARTITION_LONG`, up to 10 days.
  - Compute nodes have no git, so `COMMIT` is passed in.
  - The job precompiles first. That took 1 minute on 1.11 and 10 minutes on
    1.10 with a fresh ClimaAtmos and a warm depot.
  - A file can stay silent for a long time on 1.10. At the fork's `main`
    d2f7ffe1a, `tagged_water_precipitation_edmf_integration.jl` printed
    nothing for about 1.5 hours and took 2.1 hours in all, so it timed out on
    the short partition. An empty log with a growing `sstat` CPU time and RSS is
    still working, not hung. Give 1.10 EDMF files `$CLIMA_PARTITION_LONG` with 4
    hours.
  - `TEST_GROUP=<group>` instead of `FILES` runs `test/runtests.jl` for that
    group in `ENV_DIR`, so with CI's versions, and writes nothing into the
    checkout. Prefer `FILES`, the files a change touches, and leave whole
    groups to CI. An upstream merge is the exception (`upstream-sync`, A5).
  - An allocation fix tried by redefining a function with `@eval` in a
    script proves nothing. The redefinition makes Julia re-infer its callers
    at run time, which hides an inference failure. On 1.10 the energy tags'
    sedimentation dropped from 1.2 MB to 0 that way, and to 1.17 MB with the
    same change in the package source. Measure a fix in the source, in a
    fresh process.
  - Allocations can depend on a dependency's version, not on Julia's. To
    measure one at a given version, build the environment with `PINS`, for
    example ClimaCore at the compat floor the Downgrade workflow resolves,
    and run `Profile.Allocs.@profile sample_rate = 1` around the second call.
    That named the 1024 bytes per call that ClimaCore 1.0.3 adds in
    `ᶜenv_value` (jobs 14254894, 14254895).
  - The docstring check: build a `docs` environment, then pass
    `FILES=$CLIMA_SKILLS/terrabyte-test-job/scripts/docstring_refs.jl`
    with that environment.

`submit.sh` passes its arguments after `--` to `sbatch` and records the job
in the run's ledger, `$W/<tag>_run/JOBS.tsv`: id, tag, commit, output file and
a note. Submit every job of a run, tests, parity and mutants, into one run
directory, so the ledger is the run's list of jobs.

Do not poll the queue. Wait for the run with one background command, whose
end re-invokes the session:

```sh
$CLIMA_SKILLS/terrabyte-test-job/scripts/job_wait.sh $W/<tag>_run --wait   # run_in_background
```

It prints each job's state and the summary its output ends with. A session
restart stops the background command but not the jobs. After a restart, run
`job_wait.sh $W/<tag>_run` without `--wait` to see the run's jobs at once, then
start the `--wait` again. `--tag <regex>` and `--since <job_id>` narrow it to
some of the jobs.

## 4. Read and report

The `.out` file ends with a summary. For each file it gives the exit status,
seconds, peak GiB and the sums of its `Test Summary` tables (pass, fail,
error, broken, total). A peak above 14 GiB on Julia 1.10 is flagged `NEAR 16 GB`, because CI's
runners have 16 GB. Read the per-file logs in
`$OUT/logs/` with `grep`/`tail` only, and never print them whole.

In the pull request body, give a table like this one:

```markdown
Run on terrabyte through Slurm at `<sha>`, with CI's versions of <date> (run
<run id>), Julia 1.11.9 and 1.10.12.

| file | 1.11 | 1.10 | peak on 1.10 |
|---|---|---|---|
| `<file>` | <pass>/<total> (job <id>) | <pass>/<total> (job <id>) | <GiB> |
```

Also state what was not run, for example GPU, MPI, or the groups left to CI.
A test that fails on CI's versions but passes on older pins is a real CI
failure, so do not downgrade the environment to make it pass.
