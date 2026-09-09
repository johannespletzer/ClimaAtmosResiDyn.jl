# Tag-closure experiments: plan for the preparing agent

This page is an instruction for an agent. The agent prepares the experiments
that [tag_closure_memo.md](tag_closure_memo.md) names, on one branch, so that
the owner can run them on Levante. It is written so the work can start
without repeating the memo's research.

## Who does what

**The experiments are started manually by the owner only.** The agent
prepares configurations, runscripts, a driver, analysis scripts and plot
scripts. It never submits a job, never runs on Levante and never commits run
output. The owner submits each job with `sbatch` from the repository root on
Levante, copies the small result files into the branch and commits them. The
agent then runs the analysis on the committed files, produces the plots, and
writes the learning entries.

Everything that changes model code, a default, a tolerance, an energy
reference or a reproducibility reference needs the owner's approval before it
is written, following the agent autonomy rules of the developer guides. The
plan marks the items that need it.

## Motivation and what we want to learn

The energy source tags are the key goal. The water and energy budgets are the
first step toward them, not an end in themselves. The purpose of the whole
series is to learn which practical barriers stop the source-tag method in a
real simulation, so that the decision named in `energy_source_tags.md`,
whether to use energy source tracing at all or to combine water source tracing
with the energy process record, is taken on measurements.

Every experiment therefore ends with a learning entry that answers three
questions. What barrier did the run show, if any. Is the barrier numerical (a
residual, a negative tag, a non-positive parent, a `Float32` floor),
structural (a process that no bracket covers) or a cost (walltime, memory,
Jacobian size). Does it carry over to the source tags. The entries are
collected in one file, `LEARNINGS.md`, on the experiment branch.

The barriers the memo predicts, to be confirmed or refuted:

  - The residual is dominated by operator disagreement between the parent and
    the tags, not by rounding. For water it is the implicit central plus van
    Leer parent against the explicit van Leer tags.
  - `ρe_tot` is non-positive over most of a shallow domain, so the source-tag
    donor rule is inert there and production accumulates without loss.
  - The implicit path is not bracketed for the source tags.
  - The source tags have no rescale and no partition repair, so they can go
    negative and stay so.
  - Under the default `Float32` the closure check's floor grows with the cell
    count and can hide the structural residual.
  - Each tag adds a prognostic field and, for any implicit treatment, Jacobian
    blocks. The cost per tag is unmeasured.

## One branch

All of it lives on one branch, `claude/tag-closure-experiments`, stacked on
the branch of this page. If a step needs a second branch, for example a code
change that should be reviewed on its own, the agent proposes it and waits
for the discussion instead of creating it.

Layout on the branch:

```
experiments/tag_closure/
  README.md            how to run the series, in order, with the sbatch lines
  LEARNINGS.md         the barrier register, one entry per run
  run_tag_closure.jl   the driver: one config path in, one run out
  configs/             one YAML per run, named <phase><n>_<variant>.yml
  runscripts/          one sbatch script per phase, CPU shared partition
  analysis/            one Julia script per phase, reads output/, writes plots/
  output/              committed by the owner: closure CSVs, summary CSVs, log excerpts
  plots/               PNGs written by the analysis scripts
```

Rules for the layout:

  - `output/` holds only small text files: the `*_tag_closure.csv` a run
    writes, the summary CSV the analysis writes, and the log lines that carry
    the walltime, the throughput and the warnings. NetCDF diagnostics and
    checkpoints stay on Levante scratch; `README.md` records their path.
  - Every committed result names the commit it ran on, the Julia version, the
    date and the node type, because none of them is stable across months on
    that system (`runscripts/README.md`, "Measuring").
  - The driver is a script in the shape of `experiments/passive_stratospheric_tracers.jl`:
    it reads a YAML, builds `AtmosConfig`, runs `get_simulation` and
    `solve_atmos!`, and prints the closure summary. It does not add model
    code.
  - The runscripts follow `runscripts/run_test_as_job.sh`: account `bd1062`,
    partition `shared`, the CPU depot `levante-cpu`, the same module lines,
    `julia +1.11 --project=.buildkite`. The column runs need one task and a
    few cores. The sphere runs may need `xmodel.1gpu` with `SCRIPT` set to
    the driver; that is a cost decision for the owner.

## Common protocol

  - `FLOAT_TYPE: Float64` for every run except the `Float32` comparison. The
    default is `Float32` and the memo explains why that matters.
  - The closure check of the family under test is on, with `period` set to
    every step for a column and to one hour for a sphere, and `tolerance`
    left at its default so the run only warns. It writes
    `<family>_tag_closure.csv` with the columns `time, total, tagged,
    residual, relative, gross_residual, gross_relative, scale,
    nonpositive_fraction`. `gross_relative` is the number the memo reasons
    about.
  - The diagnostics of the family are on: `q_tag_res` and `q_tag_fix_<name>`
    for water, `e_tag_res` for energy, `e_src_res` and every `e_src_<name>`
    for the source tags. `q_tag_fix_<name>` is what the analysis subtracts to
    isolate the operator residual; its own docstring says so.
  - A control run without tags accompanies the first run of every phase, so
    the cost of the tags is measured from the `sypd` and
    `wall_time_per_timestep` lines of the log.
  - Nothing in the series edits `reproducibility_tests/ref_counter.jl`, a
    tolerance, or the parent-budget calibration table.

## Phase A. Water

The column is the DYCOMS_RF02 0M column of `test/tagged_water_integration.jl`:
`config: column`, `z_max: 1500.0`, `z_elem: 30`, `z_stretch: false`,
`microphysics_model: 0M`, the `upper` and `lower` region tags split at 600 m
and the `evap` source tag. The run length is one hour, not the test's 100 s,
so growth is visible.

| Run | Variant                                                                                        | Learning question                                                                          |
|:--- |:---------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------ |
| A1  | `dt` = 10, 5, 2.5 s, everything else fixed                                                     | Does `max abs(q_tag_res) - Σ q_tag_fix` scale with `dt`, or not                            |
| A2  | `dt` 10 s with `energy_q_tot_upwinding` and `tracer_upwinding` both `first_order`, both `none` | How much of the residual is the limiter nonlinearity, how much the implicit-explicit split |
| A3  | `microphysics_model: 1M`, `dt` 10 s                                                            | How large the `q_tot_eff` mismatch is that the docs omit                                   |
| A4  | A1 at `dt` 10 s with `FLOAT_TYPE: Float32`                                                     | Whether the `Float32` floor hides the structural residual                                  |
| A5  | MoistBaroclinicWave, SEM limiter, `dt` 300 s, one day, as in the sphere limiter test           | How much the partition repair and the limiter rescale contribute on a sphere               |

Decision rule for A1, from the memo. If the operator residual scales with
`dt`, the split is a time-discretization error that implicit tags would
remove, and moving the water tags into the implicit solve becomes worth its
Jacobian cost. If it does not, the limiter nonlinearity dominates and that
change buys nothing. A2 changes the parent's transport and is an experiment
only, never a default. A5 is optional if the shared partition makes it slow.

What phase A teaches about the source tags: whether a monitored residual with
a contract-style tolerance is enough for a family that does get corrections,
and how far the `Float32` floor sits from the structural residual. The source
tags get no corrections at all, so their residual can only be larger.

## Phase B. Energy

| Run | Variant                                                                                                                                                  | Learning question                                                                             |
|:--- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------- |
| B1  | Moist baroclinic wave, 10 days, `energy_closure_check` every 6 h, `tropics` and `extratropics` region tags; baseline with `hyperdiff` and `vert_diff` on | Which operator carries most of `gross_relative`                                               |
| B1a | B1 with `hyperdiff` off                                                                                                                                  | The hyperdiffusion share                                                                      |
| B1b | B1 with `vert_diff` off                                                                                                                                  | The vertical diffusion share                                                                  |
| B1c | B1 with both off                                                                                                                                         | The advection share that remains                                                              |
| B2  | DryBaroclinicWave, `held_suarez`, `h_elem` 4, `z_elem` 10, 10 days, as in the energy test                                                                | Reproduce the docs' "below 1% after 10 dry days" and measure the cost of the tags on a sphere |
| B3  | B1 with `apply_limiter` on                                                                                                                               | How large the jump in `e_tag_res` is when `enforce_mass_energy_consistency!` fires            |

Decision rule for B1, from the memo. If one operator carries most of the
residual and it is linear in `e_tot`, mirroring that single operator by share
could be reconsidered. Otherwise the monitored residual stands, and the memo's
statement that the energy residual is the sum of every operator the parent
receives as enthalpy is measured rather than argued. The resolution of B1 is
an open question for the owner; the `numerics_sphere_he6ze31` common config
is the candidate, and its cost on the shared partition decides between CPU
and one GPU.

What phase B teaches about the source tags: the source tags ride the same
passive-scalar path as the energy tags, so every share measured here is a
floor for their residual before any source-tag specific barrier is added.

## Phase C. Energy source tags

This is the phase the series exists for. C0 needs no code and can be
submitted as soon as its configs are written; the owner decides whether it
waits for A and B.

| Run | Variant                                                                                                                                               | Learning question                                                                                      |
|:--- |:----------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------ |
| C0  | Barrier census: the DYCOMS source column of the test with `rad: DYCOMS` for one day, and a moist sphere for one day, `energy_source_closure_check` on | `nonpositive_fraction` over time, the minimum of every `e_src_<name>`, `e_src_res`, and the walltime   |
| C1  | C0 under a reference shift that makes `ρe_tot > 0` everywhere. Needs a code change and the owner's approval; see below                                | Does `e_src_res` stay bounded and does every tag stay non-negative over a day once the donor rule runs |
| C2  | C0 in 1M with implicit microphysics, before and after the implicit-path brackets. Needs a code change and the owner's approval                        | How much residual the unbracketed implicit path carries                                                |
| C3  | C0 with `energy_process_record` for the same source labels beside the source tags                                                                     | What each of the two readings says about the same run, and where they disagree                         |

C1 is the run the memo names as the one that can decide the family's future.
Two shapes of the shift exist and the agent must put both to the owner before
writing either. The first shifts only the share's denominator, so the loss
rule reads `e_tot + c` with a constant chosen from the initial state; the
parent is untouched and no reproducibility reference changes, but the shares
then depend on `c`. The second shifts the model's energy reference itself;
the parent changes, `ref_counter` bumps, and the tags read the physics as it
is. The docs page on the source tags says the results are conditional on the
reference either way, so whichever is chosen is reported with the value.

C2 is the small structural fix the memo recommends. It is a code change on
the implicit path and belongs in its own pull request after the measurement
shows what it removes.

What phase C teaches: the barrier register itself. If C1 shows bounded
residuals and non-negative tags, the family is viable and the remaining work
is the tolerance model and the implicit brackets. If it does not, the docs'
alternative, water source tracing plus the energy process record, is the
recommendation, and C3 is the run that shows what that alternative reads.

## Analysis and plots

One script per phase in `analysis/`, run with `julia --project=.buildkite`,
which already carries CairoMakie and DataFrames. Each script reads
`output/`, writes `output/summary_<phase>.csv` and one PNG per question in
`plots/`. Each script is written against a synthetic CSV before any result
exists, so it is tested before the owner runs anything.

  - A1: `gross_relative` against time per `dt`, and the operator residual at
    the end against `dt` on log axes with the fitted slope in the title.
  - A2 to A4: `gross_relative` against time, one line per variant, with the
    `Float64` A1 run at `dt` 10 s as the reference line in every panel.
  - B1: the final `gross_relative` per variant as one bar each, and the four
    time series in one panel.
  - C0 and C1: `nonpositive_fraction` and the minimum tag value against time,
    and `e_src_res` against time, before and after the shift.
  - Every plot names the commit and the date in its caption. Residual axes
    are logarithmic. Units are on the axes.

## Order and gates

Water first, then energy, then the source tags. Each phase ends with its
learning entries and a short report to the owner, and the next phase's
configs are adjusted from what was learned before they are submitted. Items
that change code, C1 and C2, wait for the discussion with the owner. C0 may
run alongside phase A if the owner wants the census early; it changes nothing
in the model.

## Steps for the preparing agent

 1. Read this page, the memo, `tracer_configuration.md`, `tagged_water.md`,
    `tagged_tracers.md`, `energy_source_tags.md`, `process_record.md`, the
    three integration tests, `runscripts/README.md` and
    `runscripts/run_test_as_job.sh`.
 2. Create `claude/tag-closure-experiments` from the branch of this page and
    the layout above. Write `README.md` with the run order and one `sbatch`
    line per run.
 3. Write the configs for A1 to A5, B1 to B3 and C0 and C3. Take the test
    configurations as the base and change only the keys the tables name. Do
    not write C1 or C2 configs until the code they need exists.
 4. Write the driver and the runscripts. If Julia is available, check every
    config with `CA.AtmosConfig` and one `get_simulation` on the column. If
     not, check the YAML parses and say so in the report.
 5. Write the analysis scripts and run them on synthetic CSVs.
 6. Push the branch, open a draft pull request against the branch of this
    page, and stop. Report what is ready to run and what is waiting on a
    decision.
 7. After the owner commits results: run the analysis, write the plots,
    fill `LEARNINGS.md`, and report the phase with the decision rule applied.

## Open questions for the owner

  - The resolution and length of B1, and whether it runs on the shared
    partition or one GPU.
  - The shape of the C1 reference shift.
  - Whether C0 runs alongside phase A.
  - Where large outputs live on Levante, so `README.md` can record the path.
