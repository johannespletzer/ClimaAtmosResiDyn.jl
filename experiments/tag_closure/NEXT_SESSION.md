# Instructions for the session taking this over

This is an instruction for an agent, not a record. The records are the four
documents named below. Delete this file when the series ends.

You are picking up the tag-closure experiment series at a point where the
measurements are largely done and the remaining work needs two things no
previous session had: **Julia, and the GitHub CLI**. Everything in `analysis/`
was written and reviewed by reading only. That is the single most important fact
about the state you are inheriting.

Branch: `claude/tag-closure-experiments`. Work there, push there.

## Read these first, in this order

 1. [FINDINGS.md](FINDINGS.md) — the index. Every established result as a
    numbered claim with the number behind it and the run it came from. Tags are
    `W`, `E`, `R`, `T`, `M`; the other documents cite them. Sections 6 and 7 are
    the ones to read closely: **claims that were made and then falsified**, and
    **what is not established**.
 2. [LEVANTE_TASKS.md](LEVANTE_TASKS.md) — what to run, and the machine setup.
    Section 0 is yours: it lists what has never been run.
 3. [LEARNINGS.md](LEARNINGS.md) — one entry per run, the reasoning behind the
    register. Read the entry when a number in `FINDINGS.md` surprises you.
 4. [C1_reference_shift.md](C1_reference_shift.md) — the argument for the one
    experiment still outstanding, plus the raw probe output in its appendix.

[README.md](README.md) is how the harness works: layout, what a run hands back,
how the analysis is driven. Read it when you touch `analysis/` or add a config.

## Rules of engagement

**The owner starts the runs.** `docs/src/tag_closure_experiments.md` states this
first: the agent prepares configurations, runscripts and analysis; the owner
submits with `sbatch` and commits the small result files. You may now be running
*on* Levante, which makes it physically possible to submit jobs yourself.
**Do not assume that changes the rule.** Ask the owner before submitting
anything, and default to preparing the command rather than running it.

**What needs approval before it is written, not after:** model code, a default,
a tolerance, an energy reference, a reproducibility reference. C1 has that
approval already — the sphere at `δ` = −110 K, given 2026-09-10. C2 does not.

**Do not touch `output/`.** Those are measurements. If an analysis needs
different data, say so and ask for a run.

**`docs/src/` is on open PR #63** — `tag_closure_memo.md` and
`tag_closure_experiments.md`. Changes there are cherry-picks onto
`claude/tag-closure-experiments-plan`, and the owner has asked for each one.
Do not edit them casually.

**Commits.** Small, separately described, and end every message with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

plus the session line the harness gives you. Pull before you commit; more than
one agent has worked this branch at once.

## Do these first, because you are the first session that can

Section 0 of [LEVANTE_TASKS.md](LEVANTE_TASKS.md) has the commands. In short:

  - **`analysis/selftest.jl`.** It has not run since `ce76919` added
    `is_ladder_rung` and the `vert_diff` column, nor since a later audit pass
    rewrote parts of `tables.jl` and `phase_a.jl`. It is the only check that the
    analysis does what its comments say. **If it fails, that is a finding about
    this session's predecessors, not a nuisance — report it plainly.**
  - **`phase_a.jl` and `phase_c.jl`.** The summaries predate the `vert_diff`
    column and `c0_sphere_audit`.
  - **The formatter.** `prek run julia-formatter --all-files`. No session has
    run it and this branch has no pull request, so CI has not either.
    JuliaFormatter formats markdown here, and every document in this directory
    except `README.md` is in scope.

## Then, in rough order of value

 1. **Submit C1** (approved; task 1 of the task list). Run the acceptance test in
    `toml/tag_closure_c1_reference.toml` before trusting the output, and check
    the run's own `*_parameters.toml` to confirm the three overrides bound.
    Reading it: `gross_relative` is **not** comparable across the shift, because
    the shift grows the normalising scale about 2.2×. Compare absolute
    `gross_residual`, and read the audit's overclaim/undertag ratio for the
    direction.
 2. **The issue-#64 fix is not on `main`.** `7799a5a` and `acfea85` live only on
    this branch, and every A5 result depends on them. It is a real model bug
    fix — the water tags reached 1e130 while the parent stayed bounded and the
    run exited 0. With `gh` you can open a PR for it. Put that to the owner
    first; it is a model change and the branch carries much else besides.
 3. **PR #63** is draft, `mergeable_state: unstable`, and its base
    (`claude/parent-budget-9-closure-plan`) has not merged. `main` has moved a
    long way since — the parent-budget series landed — so the memo's pinned
    `a54ce31` now points into history rather than at the tip. The pin is
    explicit and therefore not wrong, but a reader on today's `main` will find
    different line numbers.
 4. **Two known defects, reported and not fixed.** `.gitignore` in this
    directory says `*.out` is "deliberately still ignored" while thirteen `.out`
    files sit committed under `output/` via force-add — comment and practice
    disagree. And `validate_configs.py`'s `implicit_diffusion` rule is stricter
    than the model: `model_getters.jl:1068` puts that assert in an `elseif`
    chain after the ISDAC branch, so an ISDAC config would pass the model and
    fail the validator. False positives only; nothing in the tree uses ISDAC.

## Traps this series has already paid for

Each of these cost a run or a wrong conclusion. They are in the records too, but
they are the ones worth knowing before you start.

  - **`.buildkite` needs a prepared machine.** Run
    `./runscripts/setup-julia-levante.tcsh cpu` once. Without it Julia dies on
    `Missing source file for base pkg Statistics`, which names nothing useful.
  - **`nonpositive_fraction` is a fraction by volume**, not by cell count, and
    it is a poor proxy for how much of a field is affected. On water it is
    0.351 against a content fraction of 2.77e-7; on energy it is 0.43276 against
    0.7839. Wrong in both directions, by six orders of magnitude one way and 1.8×
    the other.
  - **`sypd` is logged through `@info`, which Julia sends to stderr.** It is in
    the `.err`, not the `.out`. And a job's wall time is not a run's cost:
    `a1_dt10`'s solve is 3.3 s inside a 295 s job.
  - **Closure quantities are not interchangeable.** `gross_relative` is
    `∫|residual| / ∫|parent|`; the integration test bounds
    `max|residual| / max|parent|`. Comparing them produced a "36× of margin"
    claim that meant nothing.
  - **A config that validates can still die on the node.** `validate_configs.py`
    checks schema and per-family invariants; `check_case_consistency` runs
    inside `get_atmos`, after the queue. One cross-key rule now mirrors it.
  - **A merged common config is not a self-sufficient config.**
    `numerics_sphere_he6ze31.yml` sets `implicit_diffusion: true` expecting its
    partner to supply a diffusion model.

## How this series writes things down

These conventions are load-bearing. An audit pass found eleven errors in work
that had not followed them closely enough.

  - **Cite the run.** Every claim in `FINDINGS.md` names the run it came from.
  - **State the bound with the claim.** One geometry, one resolution, an
    uncontrolled comparison — that is part of the finding, not a footnote.
  - **Never cite a verification that is not in the tree.** Two claims cited
    randomised runs of 200,000 and 20,000 states; neither script exists here.
    The claims survived re-derivation, but a verification you cannot re-run is
    not provenance. If you verify something with a script, commit the script.
  - **Record falsified claims rather than deleting them.** `FINDINGS.md` §6
    exists so a later reader does not re-derive a dead end. Add to it.
  - **Recompute before repeating.** Numbers in these documents have been wrong.
    When one matters to a decision, get it from the CSV yourself.
