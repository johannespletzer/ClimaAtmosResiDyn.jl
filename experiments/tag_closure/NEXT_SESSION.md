# Instructions for the session taking this over

This is an instruction for an agent, not a record. The records are the four
documents named below. Delete this file when the series ends.

Since C1, the series ran C4 to C7 on LRZ terrabyte on 2026-09-10 and
2026-09-11, with the owner's approval. It built the tag-side offset (#68), the
implicit bracket and the repair (#69), and measured where the tags' closure
residual comes from in both geometries (E25, E31). Start from "Where the last
session stopped" below.

Branch: `claude/tag-closure-experiments`. Work there, push there.

## Read these first, in this order

 1. [FINDINGS.md](FINDINGS.md) — the index. Every established result as a
    numbered claim with the number behind it and the run it came from. E11 to
    E16 are C1. Sections 6 and 7 are the ones to read closely: **claims that
    were made and then falsified**, and **what is not established**.
 2. [LEVANTE_TASKS.md](LEVANTE_TASKS.md) — the task list, for both machines.
    The name is historical. Task 1 is the next job.
 3. [LEARNINGS.md](LEARNINGS.md) — one entry per run, the reasoning behind the
    register. The C7 entry is the last.
 4. [C1_reference_shift.md](C1_reference_shift.md) — the argument C1 was built
    on, with the raw probe output in its appendix.

[README.md](README.md) is how the harness works: layout, what a run hands back,
how the analysis is driven, and how to submit on terrabyte.

## Rules of engagement

**The owner decides every submission.** On terrabyte an agent session can reach
`sbatch`, and the owner has approved named jobs there. That approval is per
job and does not carry over. Ask before submitting anything, and default to
preparing the command.

**Ask before pushing anywhere but this branch.** PR #65 in particular belongs to
the #64 fix, and resolving its conflict means pushing to its branch.

**What needs approval before it is written, not after:** model code, a default,
a tolerance, an energy reference, a reproducibility reference. The twin
follow-up needs a small change to `run_c1_twin.jl` or a new configuration, and
the owner should see which before it is written.

**Never change a committed measurement.** New runs go into new directories
under `output/`. A second reading of an existing run goes into a subdirectory,
the way `output/c0_sphere_audit/terrabyte/` does.

**`docs/src/` is on open PR #63** — `tag_closure_memo.md` and
`tag_closure_experiments.md`. Changes there are cherry-picks onto
`claude/tag-closure-experiments-plan`, and the owner has asked for each one.
Do not edit them casually, and that includes the formatter.

**Commits.** Small, separately described, and end every message with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

plus the session line the harness gives you. Pull before you commit; more than
one agent has worked this branch at once.

## Where the last session stopped

  - **C4 ran, and the tag-side offset works.** `energy_source_tag_offset` is in
    the model. It leaves the atmosphere bit for bit untouched and reproduces
    C1's tag results (FINDINGS E17 to E19). The twin tests found E16 to be
    mostly the van Leer energy limiter. A fourth twin ruled out the surface-flux
    path for the remainder, and the owner stopped there.
  - **C5, C6 and C7 ran** (task 1c, FINDINGS E20 to E30). The radiation tag
    holds nothing where radiation cools, even with the loss running. Checked per
    process, the tags found a process that no tag listed in both geometries:
    subsidence on the column, and on the sphere the rain-out producing energy
    where cold condensate falls out. With those listed, the column closes per
    process to 60.7 J/kg and per record to the joule, and the sphere per process
    to 20.2 J/kg (C7). What the sphere's last 20 J/kg is, is open.
  - **PR state.** #65 and #68 are merged into `main`. #69, the implicit bracket
    and the repair, and #70, sedimentation as transport, a draft, target
    `main`. #72, the audit, is a draft stacked on #70. On 2026-09-11, with the
    owner's approval:
      + #69 got the corrected repair help text and records comment, at
        `0ae408d8`;
      + #72 got C3, the offset in the audit's hyperdiffusion, and the corrected
        timing wording, at `7a290c98`. Its unit tests (230) and integration
        tests (66) pass. It has not merged #69's `0ae408d8` or #70's new
        commit;
      + #70 has the EDMF refusal and M2's label warnings, at `4c274aed` in
        `../ClimaAtmosResiDyn-repair`, with #69 merged in. Its unit tests pass.
        It is **not pushed**: pushing to #70 waits for the owner.

    This branch has not merged `0ae408d8` or `7a290c98` yet. Merge them once
    the D4 pair has finished, since those jobs run from this tree. Check the
    PRs' CI before anything else touches them. The review of #65 and #68 left
    these for the owner: `c·Δρ` from mass-changing processes the tags do not
    bracket, a restart guard for a changed offset, the `Float32` rounding
    floor, `parent` shadowed in tests, `nothing` inside a broadcast, and
    `isfinite` before the conversion to `FT`.
  - **The owner decided to keep both** the energy source tags and the process
    record, as the main goal (FINDINGS §8). Task 1b of the task list names what
    is left to make the tags operational.
  - **The residual's growth is pressure work in both geometries** (FINDINGS
    E25, E31, `analysis/transport_ledger.jl`). On the sphere it is at least 93%,
    with a horizontal part half the vertical one. Both meet the reviewer's rule
    for building an enthalpy-form transport of the tags as an audit. The owner
    approved building it, and it is not built.
  - **Sedimentation as transport of the tags is built** (`91b9bbb9`, FINDINGS
    §8 and E32). It is draft PR #70, at `e8debaba`, now targeting `main`, and
    its tests pass on this branch and on #69's. C8 ran it on a 1M column for a
    day (E33).
  - **This branch carries the review fixes of #65 and #68,** merged from #69's
    head with the owner's approval. Its model code differs from #70's only in
    `src/parent_budget/report.jl` and `src/simulation/solve.jl`, which are its
    own. Five test files pass on the merge.
  - **The enthalpy audit switch is built** (`511e00e9`), as designed in
    `ENTHALPY_AUDIT_DESIGN.md` with the owner's four decisions. It is draft PR
    #72, stacked on #70, and its tests pass there and on this branch.
  - **C9 ran** (E34). Moved as enthalpy, the tags' closure residual stops
    growing after the first hour. At 24 h it is 1,069 times smaller than under
    tracer transport on the column and 11 times smaller on the sphere, and `ta`
    is identical. On the sphere, form A worsens where the source tags go
    negative with the repair off. A run with the repair on would test that.
  - **C10 ran** (E35). It is C9's sphere with the repair on, and it did not
    bring form A back: 274 J/kg, against C7's 20. Subtracting the repair's
    ledgers does not undo the repair (E35). Form A's global integral, not its
    largest gap, is the check (E38).
  - **The Opus review of #69 is done, and posted on the PR.** It found no
    blocker. Its five findings are fixed in `d545af90` and merged into #70
    (`30d8bb4c`), #72 (`404ba98f`) and this branch (`602153b9`).
  - **Why form A fails on the sphere, and where the leftover residuals come
    from, are recorded** (E36 to E39). Form A's global integral is the check,
    not its largest gap (E38).
  - **Sub-grid transport, ice and the other microphysics schemes are designed,
    not built** ([SUBGRID_AND_MICROPHYSICS_DESIGN.md](SUBGRID_AND_MICROPHYSICS_DESIGN.md)).
    Every shipped EDMF configuration fails with tags, and the sub-grid mass
    flux reaches no tag (E40). Falling ice takes sedimentation's upward branch
    in every cell, and the partition closes through it (E41). 2M and P3 are
    disabled in the model on this branch. Configs D1 to D5 are written and
    validated. D1 ran (E42), and the D4 pair was submitted. A user guide is
    drafted,
    [USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md).
  - **What is left before operation is
    [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md).** Start from its decisions for
    the owner. The GPU is last, by the owner's decision.
  - **The owner's decisions of 2026-09-11 are in
    [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md).** Production is a GPU sphere in
    Float32 with EDMF and 1M. EDMF is refused now and shared later.
  - **D1 ran** (E42). Through an hour of falling ice the column stays closed
    and the tags non-negative. Under 1M the microphysics tag and record are
    exactly zero. What the upward branch moved cannot be told apart from
    vertical diffusion.
  - **R4 ran** (E39b, E43). A converged Newton solve removes 83% of the
    audit's first-hour residual on the sphere. On C8's column the audit keeps
    form A below 4.4e-7 J/kg for a day, and a converged solve takes form B to
    −3.8e-3 J/m².
  - **The D4 EDMF pair, jobs `13404536` and `13404537`,** was still building
    after an hour, at full CPU, when this was written. `hpda2_test` stops a job
    at two hours. Check `sacct`, and `output/d4_column_edmf*` on scratch. If it
    timed out, the EDMF build with tags takes more than two hours on two cores,
    and the pair needs a longer partition.
  - **Worktrees.** `../ClimaAtmosResiDyn-repair` is on #70's branch, three
    commits ahead of origin. `../ClimaAtmosResiDyn-audit` is on #72's branch,
    level with origin. Its tracked `.buildkite/LocalPreferences.toml` names a
    Levante MPI library, so tests there log an MPI error and still pass.
  - **Three known defects** are listed in the task list and are not fixed.

## Traps this series has already paid for

  - **`.buildkite` needs a prepared machine.** Run the machine's setup script
    once. Without it Julia dies on `Missing source file for base pkg Statistics`, which names nothing useful.
  - **`main` tracks `.buildkite/LocalPreferences.toml`; this branch does not.**
    In a worktree based on `main`, such as #68's, the setup script rewrites the
    tracked file. Run `git checkout -- .buildkite/LocalPreferences.toml` before
    committing there.
  - **On terrabyte, never `module purge`**, and load `python/3.12` last.
    `validate_configs.py` needs PyYAML, which no default Python here has, and
    the self-test only warns when it is missing.
  - **On terrabyte, commit before you submit.** Compute nodes have no git, so
    the runscript reads the commit from `.git` and cannot tell whether the tree
    was dirty.
  - **On terrabyte, `hpda2_compute` queued even a two-core half hour 30 hours
    out on 2026-09-10.** `hpda2_test` started at once and caps a job at two
    hours. Send job logs to scratch with `--output` and `--error`, or they land
    in the repository root.
  - **`run_c1_twin.jl` exits 1 on purpose** when the twins differ, so its job
    reads `FAILED` in `sacct`. Read `twin_c1.csv`.
  - **Region tags and source tags go negative for different reasons.** A region
    tag carries the parent's sign. Look at the source-only columns of
    `summary_c.csv` (M5).
  - **`nonpositive_fraction` is a fraction by volume**, and a poor proxy for how
    much of a field is affected: 0.351 against a mass fraction of 2.77e-7 on
    water, 0.43276 against 0.7839 on energy.
  - **`gross_relative` is not comparable across a change of reference.** Under
    C1's shift the scale grows 2.85×. Compare the absolute `gross_residual`.
  - **Closure quantities are not interchangeable.** `gross_relative` is
    `∫|residual| / ∫|parent|`; the integration test bounds
    `max|residual| / max|parent|`.
  - **`sypd` is logged through `@info`, which Julia sends to stderr.** It is in
    the `.err`, not the `.out`.

## How this series writes things down

These conventions are load-bearing. An audit pass found eleven errors in work
that had not followed them closely enough, and the last session found six more.

  - **Cite the run.** Every claim in `FINDINGS.md` names the run it came from.
  - **State the bound with the claim.** One geometry, one resolution, an
    uncontrolled comparison — that is part of the finding, not a footnote.
  - **Never cite a verification that is not in the tree.** If you verify
    something with a script, commit the script. `c1_acceptance.jl` and
    `run_c1_twin.jl` exist because of this rule.
  - **Record falsified claims rather than deleting them.** `FINDINGS.md` §6
    exists so a later reader does not re-derive a dead end. Add to it.
  - **Recompute before repeating.** Numbers in these documents have been wrong.
    When one matters to a decision, get it from the CSV yourself.
