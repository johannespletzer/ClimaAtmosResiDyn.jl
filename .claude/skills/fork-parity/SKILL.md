---
name: fork-parity
description: Check that ClimaAtmosResiDyn.jl's model fields stay bit for bit identical, with a diagnostic switched off and on, between a branch and main, or between the fork and the last merged upstream ClimaAtmos commit. It runs named configurations on one terrabyte node and compares every state and tendency field with isequal. Use for any change to src/, a new diagnostic or hook in shared code, an upstream merge or a dependency bump, and before a pull request body claims parity.
---

# Fork parity

The rule is in `AGENTS.md` ("Local norms") and in
`docs/clima_atmos_specific.md#fork-parity-with-upstream`. Read that section
first. In short, every field upstream has stays bit for bit. Only a
diagnostic's own fields, cache and output may differ. A difference is a
defect, not a new reference.

The in-tree parity testsets ("The model's fields do not depend on the tags")
check one column each in CI. This skill adds a check across configurations,
float types and checkouts, which no CI job does.

## The scripts

All of them are in the checkout's `.claude/skills/fork-parity/`, outside the
checkouts, so one copy serves every worktree.

  - `scripts/parity_run.jl` runs a configuration file's `configs`. It saves
    every field of the final state and of one implicit, remaining and limiter
    tendency. Nested fields such as `sgsʲs` are split into their named
    components. A NaN or an Inf stops the run, since `isequal` treats two NaNs
    as equal.
  - `scripts/parity_compare.jl` takes a reference (a) and a candidate (b).
    Every field of a must be in b and `isequal`. Fields only b has are listed
    as the diagnostic's own. Fields matching the given name prefixes are
    reported but not judged.
  - `scripts/parity_job.sh` precompiles both environments, runs a and b at
    once on one node, and compares them.
  - `configs/upstream.jl` holds three configurations upstream can run:
    `edmf_column` (DYCOMS EDMF with 1M, 1 h), `column_1m` (10 min) and
    `moist_sphere` (0M baroclinic wave, 1 day). On Julia 1.11 they took 930,
    187 and 610 s (2026-10-14), about 30 minutes in all.
  - `configs/example_water_tags.jl` is the same three with water tags on. Copy
    it, then swap in the diagnostic under test.

The environments come from the `terrabyte-test-job` skill
(`make_ci_env.jl ... test <ci_log>`). Bit-for-bit holds only within one
machine, one Julia, one manifest, one float type and one process count. So
both sides use environments built from the same CI log, and the comparison
runs on one node.

## Choose the comparison

**A. Diagnostic off against on, one checkout.** Use this for every
diagnostic change. Both sides use one environment.

```sh
W=$SCRATCH/claude_work; P=$CLIMA_SKILLS/fork-parity
env A_ENV=$W/<tag>_ci111_env B_ENV=$W/<tag>_ci111_env \
    A_COMMIT=<sha> B_COMMIT=<sha> OUT=$W/<tag>_run/parity_onoff \
    CONFIGS=$P/configs/upstream.jl B_CONFIGS=<your diagnostic configs.jl> \
  $CLIMA_SKILLS/terrabyte-test-job/scripts/submit.sh $W/<tag>_run parity "diagnostic off against on" -- \
    --time=01:55:00 \
    --cpus-per-task=4 --mem=48G --job-name=parity \
    --output=$W/<tag>_run/parity-%j.out $P/scripts/parity_job.sh
```

Check the "fields only in b" list. It must name only the diagnostic's own
fields (`ρq_tag_*`, `ρe_src_*`, `prc_*`, ledgers and so on). A model field
there means the diagnostic changed the state's layout of a model field.

The job checks the list's size itself. When the two sides ran different
configuration files, b must have fields of its own, or its diagnostic never
switched on. When they ran the same file (modes B and C), b must have none,
or a fork field is on by default. Either way the comparison fails.
`parity_run.jl` also sets `strict_config`, so a misspelled key stops the run
instead of only warning.

**B. Branch against main.** Use this for a change to shared code, a solver or
a loop. Make a worktree of `origin/main` and an environment for each side from
the same CI log. Run upstream's configurations on both sides. If main has the
diagnostic too, run its configurations on both sides as well.

  - If the change is meant to move the diagnostic's values, pass their name
    prefixes in `PREFIXES`, for example `PREFIXES="ρq_tag_ ρq_rtag_"`.
  - For a key main does not have, give main `configs/upstream.jl` as
    `CONFIGS` and the branch the keyed file as `B_CONFIGS`. The compare then
    holds the branch's keyed run against main's plain one under the same name.

**C. Fork against upstream.** Use this for an upstream merge or a dependency
bump. The reference commit is the second parent of the last upstream merge
on main:

```sh
git log origin/main --merges --grep='Merge upstream' -1 --format=%p   # second hash
git worktree add --detach ../ClimaAtmos-upstream-<short> <second hash>
```

Build the upstream worktree's environment from the same CI log. If upstream's
compat refuses one of CI's versions, say so in the report. Do not bend the
fork's environment to match. Run `configs/upstream.jl` only. After a merge,
run it against the merged upstream commit, not the previous one.

**Float32.** Run any of these a second time with `PARITY_FLOAT_TYPE=Float32`.
The fork's tests run in both float types, and the claim should too.

## Limits of the claim

  - It covers the default solver: a fixed number of Newton iterations with the
    direct block solver. Under `use_krylov_method` or `use_newton_rtol` a
    diagnostic's fields enter the residual norm, so a mismatch there is
    expected, not a defect.
  - Restart round trips are not covered here. The integration tests check them.
  - GPU and MPI are not run on terrabyte. State this.
  - `NAMES=column_1m` is a quick check, a few minutes after precompilation.
    Leaving out only `moist_sphere` saves about 10 of the 30 minutes, so run
    all three for any claim.

## Read the result

```sh
grep -E 'MODEL FIELD DIFFERS|MISSING|END TIME|fields judged|fields only in b|BIT FOR BIT|DIFFERENCES' $OUT/compare.out
```

  - Exit status 0 and `ALL MODEL FIELDS BIT FOR BIT` is a pass.
  - `(signed zeros only)` is still a failure. It usually means reordered
    arithmetic, such as `a - b` against `a + (-b)`, or a fused operation.
  - Exit 3 means a run failed. Read `$OUT/a.log` and `$OUT/b.log` with `tail`.
    A misspelled configuration key fails here, through `strict_config`.
  - `NO FIELDS ONLY IN b` or `FIELDS ONLY IN b WITH THE SAME CONFIGURATION` is
    a failure of the comparison's set-up, as the section above says.
  - With `PREFIXES`, every excluded field is listed, moved or unchanged. A
    prefix that would exclude a model field (`ρq` matches `ρq_tot`) is
    refused.

On a failure, find the first field and tendency that differs. A difference in
`implicit` or `remaining` but not in `state` points at a hook that writes a
shared scratch field. Then hand the diff to `clima-numerics-reviewer` before
any fix. Never loosen the comparison and never update
`reproducibility_tests/ref_counter.jl` for a fork change.

## Report it in the pull request

```markdown
## Parity

- Diagnostic off against on, at `<sha>`, Julia 1.11.9, CI's versions of
  <date>: every model field bit for bit in `edmf_column`, `column_1m` and
  `moist_sphere`, <n> fields judged, <m> fields of the diagnostic's own
  (job <id>). Float32: the same (job <id>).
- Branch `<sha>` against main `<sha>`: <result> (job <id>).
- Not covered: GPU, MPI, Krylov solver, restarts beyond the integration tests.
```

Keep the scripts' output under `$SCRATCH`. Copy only the summary into the PR.
