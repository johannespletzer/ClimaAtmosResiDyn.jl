---
name: mutation-run
description: Show that a ClimaAtmosResiDyn.jl test catches the defect it is meant to, by running it on mutants of the code (one small textual change each) and an unmutated control as a Slurm array on LRZ terrabyte, and produce the table for the pull request. Use when a PR claims a test guards a change, after porting a mirror of an upstream call, after fixing a bug (the bug is the mutant), and when a reviewer asks whether a check could miss a case.
---

# Mutation runs

A test that passes says nothing until it has been seen to fail on the defect
it guards. A mutant is that defect put back on purpose: one small textual
change to the code, such as a term moved to the wrong flow, a sign flipped, a
bracket dropped or the old line restored. The run is the control and the
mutants, each in its own worktree, through the same test files. A mutant is
caught when a file fails or errors in a test. The PR then names the test that
caught each mutant.

The scripts are in the checkout's `.claude/skills/mutation-run/scripts/`. They
use `terrabyte-test-job`'s environments and `test_job.sh`.

| Script                                                        | Does                                                                                                                                                                                                | Runs on                   |
|:------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------- |
| `make_mutants.jl <spec.toml> <checkout> <base_env> <out_dir>` | A detached worktree of HEAD per mutant and the control, the change applied and parsed, an environment per worktree copied from `base_env` (nothing resolved again), `mutants.tsv` and `cleanup.sh`  | login node, seconds       |
| `mutation_job.sh`                                             | One array task per row: the row's test files in its worktree, with its own depot layer for the compiled cache                                                                                       | batch, Julia 1.11 or 1.10 |
| `mutation_table.jl <out_dir>`                                 | The Markdown table: caught or not, by which file, the first failing test; and the problems: a control that fails, a mutant no file catches or not the file expected, a mutant that breaks the build | login node                |

## 1. Choose the mutants

Each mutant is the smallest change that a wrong implementation could make, in
the code the PR changes or guards:

  - For a ported mirror: the parent's old line restored, an argument of the old
    call, the term the port added left out.
  - For a mapping or a table: one entry moved to a wrong place, one dropped.
    Every entry is a mutant if the table is short (the 80 single mutations of
    the water tags' flow mapping in the 5af1766c merge review).
  - For a bug fix: the bug itself.
  - For a parity or a closure guard: a change of one rounding, such as
    `a - b` to `a + (-b)`, where the guard claims bit for bit.

Write down which test file should catch each (`expect`). A mutant no test
catches is a finding: either the test is weak or the change does not matter,
and the PR says which. Keep a run to about 10 mutants. Each recompiles
ClimaAtmos.

## 2. Make them

Commit the code under test first. The mutants start from HEAD, and
uncommitted changes are not carried over. Write the spec next to the run's
other files, for example `$SCRATCH/claude_work/<tag>_mut.toml`:

```toml
files = ["tagged_water_precipitation_tests.jl"]

[[mutant]]
name = "cold_accretion_into_rain"
file = "src/parameterized_tendencies/tagged_tracers/tagged_water_precipitation.jl"
old = "        NS = Δ.S_acnv_icl_sno + Δ.S_accr_lcl_sno_cold + "
new = "        NS = Δ.S_acnv_icl_sno + "
why = "cold accretion of cloud liquid by snow left out of NS"
expect = ["tagged_water_precipitation_tests.jl"]
```

`old` must occur once in `file`, or set `occurrence`. A mutant may name its
own `files`.

```sh
S=$CLIMA_SKILLS; W=$SCRATCH/claude_work
julia +1.11 $S/mutation-run/scripts/make_mutants.jl $W/<tag>_mut.toml <checkout> $W/<tag>_ci111_env $W/<tag>_mut
```

`base_env` is the checkout's environment from `make_ci_env.jl`. A 1.10 run
takes a 1.10 environment.

## 3. Run them

```sh
env MUT=$W/<tag>_mut VER=1.11 $S/terrabyte-test-job/scripts/submit.sh $W/<tag>_run <tag>_mut -- \
    --partition=$CLIMA_PARTITION_LONG \
    --time=04:00:00 --cpus-per-task=4 --mem=48G --job-name=<tag>_mut \
    --array=0-<rows-1> --output=$W/<tag>_mut/slurm-%A_%a.out \
    $S/mutation-run/scripts/mutation_job.sh
```

`make_mutants.jl` prints the `--array` range. The control is row 0. Each task
precompiles its own ClimaAtmos and then runs the files. A caught mutant ends
early, since a file stops at its first failing testset: in the first run
(three mutants of the water tags' flow mapping, Julia 1.11) the control took
13.5 minutes and each mutant 3 to 4. Size `--time` from the slowest file's last
time. The short partition (2 h, 2 nodes) runs only two tasks at a time, so use
`$CLIMA_PARTITION_LONG` for more. Do not poll. Wait for the array with
`job_wait.sh $W/<tag>_run --wait --tag <tag>_mut` as a background command (see
`terrabyte-test-job`); it shows each task's summary.

## 4. Read and report

```sh
julia +1.11 $S/mutation-run/scripts/mutation_table.jl $W/<tag>_mut
```

The run counts only if the control passes. A mutant "caught" only through
"build failed" or "load error" shows the change breaks the code, not that the
test sees it. Rewrite it so it compiles. In the PR:

```markdown
## Mutants

<the table>

Run on terrabyte at `<sha>`, Julia 1.11.9, with the environment of the test
runs above. <Each mutant no file caught, and why that is acceptable or what
test was added.>
```

Then remove the worktrees with `$W/<tag>_mut/cleanup.sh`. It deletes data on
`$SCRATCH`, so ask the owner first, or leave it for the end of the PR.

## In-process mutants

For a pure function, such as a mapping or a formula, a mutant can be a method
redefined at run time in one Julia process (`@eval CA.f(x) = ...`) before the
testset runs, on a login node with no Slurm job. That is what the numerics
review of the 5af1766c merge did for 80 mutations in minutes. It cannot
mutate code that is inlined into a kernel already compiled, and it does not
go through the test files, so the PR table still comes from a run here.

## Who does what

Choosing the mutants is judgement: the main session or the reviewer that
asked for them (`clima-numerics-reviewer` for a closure or a mirror). Writing
the spec from a chosen list, running and the table can go to `worker`
(Sonnet). Reading why a mutant survived is the main session's.
