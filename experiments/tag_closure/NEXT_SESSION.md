# Instructions for the session taking this over

This is an instruction for an agent, not a record. The records are the four
documents named below. Delete this file when the series ends.

The previous session, on 2026-09-10 on LRZ terrabyte, was the first with Julia
and the GitHub CLI. It ran the analysis for the first time, ran C1 with the
owner's approval, and found two things that change how C1 is read: the tags
still go negative under a positive reference (E14), and the shift is not a pure
relabelling in the discrete model (E16). Start from those.

Branch: `claude/tag-closure-experiments`. Work there, push there.

## Read these first, in this order

 1. [FINDINGS.md](FINDINGS.md) — the index. Every established result as a
    numbered claim with the number behind it and the run it came from. E11 to
    E16 are C1. Sections 6 and 7 are the ones to read closely: **claims that
    were made and then falsified**, and **what is not established**.
 2. [LEVANTE_TASKS.md](LEVANTE_TASKS.md) — the task list, for both machines.
    The name is historical. Task 1 is the next job.
 3. [LEARNINGS.md](LEARNINGS.md) — one entry per run, the reasoning behind the
    register. The C1 entry is the last.
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
  - **C5 ran** (task 1c, FINDINGS E20 to E24). The radiation tag holds nothing
    where radiation cools, even with the loss running. Checked per process, the
    tags found subsidence in the DYCOMS column, which no tag listed. On the
    column a region's initial energy only falls. C6 is proposed in task 1c and
    needs approval.
  - **PR #65 and PR #68 stay drafts** until the owner has reviewed them. #68 is
    the offset, stacked on #65, and it now carries the loss-rule integration
    test the owner asked for (`466dd2f4`, 33 of 33 pass). Check both PRs' CI
    before anything else touches them.
  - **The owner decided to keep both** the energy source tags and the process
    record, as the main goal (FINDINGS §8). Task 1b of the task list names what
    is left to make the tags operational.
  - **The implicit bracket and the repair are built on this branch** (FINDINGS
    §8), in the order the owner set, with the repair on by default and
    switchable off. They are not in a pull request yet; ask before opening one.
  - **Enthalpy-form transport of the tags, as an audit** with passive tracers
    kept as the default, went to a reviewer agent. Its answer is in FINDINGS
    §8: measure each operator's share of the residual first, with a script
    that is not written yet, and build a switch only if the measurement
    supports it.
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
