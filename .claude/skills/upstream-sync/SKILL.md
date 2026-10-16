---
name: upstream-sync
description: Update ClimaAtmosResiDyn.jl from upstream CliMA/ClimaAtmos.jl in three phases that can each run alone. Check finds which upstream changes reach the tag diagnostics (hooks, mirrors, removed names, package internals, config defaults) and writes a report for the owner's go-ahead. Port makes the merge commit and ports the tagged energy and water tracers, energy source tags, process records and parent budget. Validate checks parity against the new upstream commit, runs every test group on terrabyte and opens a draft PR. Also handles a dependency release that turns CI red, by capping it or following it, and compares CI's resolved versions with the .buildkite pins. Use whenever someone asks what upstream changed, whether upstream breaks or affects the tags, to merge or sync upstream, to update the fork or its tag diagnostics after upstream moved, to test or validate an upstream merge, for a red CI or nightly run that no code change explains, for adding or lifting a compat cap, and before a claim about which package versions a run used.
---

# Upstream merges and dependency drift

The fork changes no model output, so an upstream merge is the only change
that may move it, and a dependency release must not move it unnoticed. The
past merges (#53, #89, #139, #178) and caps (#128, #145, #156) follow one
pattern, written down here. Parity and test runs use the other two skills:
`fork-parity` (mode C) and `terrabyte-test-job`.

An upstream merge (part A, sections A1–A6) has three phases. Parts B and C
are separate tasks. Each phase ends with something the next phase starts from, so a session can run one phase alone, such as only Check, to
answer "what would upstream do to the tags?".

| Phase                | Sections | Starts from                    | Ends with                                                                         |
|:-------------------- |:-------- |:------------------------------ |:--------------------------------------------------------------------------------- |
| 1. Check (read-only) | A1       | fetched remotes                | `$W/check.md`, and the owner's go-ahead or a reason to wait                       |
| 2. Port              | A2–A4    | the go-ahead and `$W/check.md` | a local branch: the merge commit, then port commits, with the finders rerun clean |
| 3. Validate          | A5–A6    | the Port branch                | parity and tests passed on terrabyte, and a draft PR the owner marks ready        |

To start a later phase in a new session, take `W` from the branch's PR body or
`$SCRATCH/claude_work/`. If `check.md` is missing, rerun Check: its scripts
are read-only and take seconds, apart from the environments.

| Script (`scripts/`)                                                                | Does                                                                                                                                                                                                                                                                                            | Runs on                                                        |
|:---------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------- |
| `upstream_survey.sh [checkout] [upstream_ref] [fork_ref]`                          | What a merge brings: base, upstream's commits, output changes, compat, removed config keys, new tests, files both sides changed, the conflicts git would leave                                                                                                                                  | login node, 4 s, read-only                                     |
| `tag_impact.sh [checkout] [upstream_ref] [fork_ref]`                               | Each upstream commit that reaches the fork's code: a mirror's parent (M), a function the fork also changed (H), a file the fork changed (h), `ref_counter` (O), the default config (C), parameters or compat (P). Also the package mirrors whose package moved, and the commits with no contact | login node, 1 s, read-only                                     |
| `removed_names.jl <checkout> <old_ref> <new_ref> [tree_ref]`                       | Names upstream removed, and functions or structs whose methods or fields changed, that the fork's own lines still use                                                                                                                                                                           | login node, 4 s                                                |
| `mirror_check.jl <checkout> <old_ref> <new_ref> [old_env new_env] [--diffs <dir>]` | Which of the fork's mirrors (`mirrors.toml`, 30 on 2026-10-14) have a parent that changed: upstream functions between two refs, package functions between two environments. Compares parsed code, so comments and formatting do not count                                                       | login node, 10 s                                               |
| `dep_internals.jl <checkout> <tree_ref> <upstream_ref> <new_env> [old_env]`        | The fork's calls into a dependency's underscore names, and whether the new version still defines each                                                                                                                                                                                           | login node, 5 s                                                |
| `versions_diff.jl <a> <b>`                                                         | Packages at different versions between two CI logs, manifests, environments or `<ref>:<path>`                                                                                                                                                                                                   | login node, 1 s                                                |
| `invalidations.jl`, `invalidations_job.sh`                                         | The Invalidations workflow's count, twice, with the list of invalidated methods and the largest trees                                                                                                                                                                                           | batch job, Julia 1.10, 4 min per environment with a warm depot |

`make_ci_env.jl` (in `terrabyte-test-job`) builds every environment. Its
`invalidations` kind is what the Invalidations workflow loads, and
`PINS="Pkg=x.y.z,..."` pins packages on top of CI's versions and records any
other package the pins force to move.

Set a work directory first, and fetch both remotes:

```sh
S=$CLIMA_SKILLS; W=$SCRATCH/claude_work/<tag>_run; mkdir -p $W/logs
git fetch upstream main && git fetch origin
```

## Before any phase

  - An open `nightly-red` issue blocks every merge but its fix (AGENTS.md). A
    drift fix is usually that fix.
  - Branch from `origin/main`: `claude/merge-upstream-<short>` or
    `claude/cap-<package>-drift`. Never rebase, never squash a merge.
  - An upstream merge needs the owner's go-ahead, since it changes the physics
    the experiments run on. Check ends by asking for it.

## Phase 1: Check

Check changes nothing in the fork. It runs in a work directory, in a detached
worktree of `origin/main`, and for the environments in a detached upstream
worktree. `mirror_check.jl` and `removed_names.jl` read the fork's functions
from the working tree. A checkout on any other branch reports false `ERROR`s
for functions that branch lacks, and misses ones it adds. So run Check from a
clean tree:

```sh
git worktree add --detach ../ClimaAtmosResiDyn-check-<short> origin/main
cd ../ClimaAtmosResiDyn-check-<short>
```

### A1. Survey

```sh
$S/upstream-sync/scripts/upstream_survey.sh > $W/survey.txt
$S/upstream-sync/scripts/tag_impact.sh > $W/tag_impact.txt
julia +1.11 $S/upstream-sync/scripts/removed_names.jl . <base> upstream/main origin/main > $W/names_before.txt
```

The two checks of the fork's mirrors and of its calls into package internals
need the old and the new dependency versions. Take an environment of
`origin/main` (any recent one built by `make_ci_env.jl`, such as the last test
run's) and build one of the upstream worktree (A5 needs it anyway):

```sh
git worktree add --detach ../ClimaAtmos-upstream-<short> upstream/main
julia +1.11 $S/terrabyte-test-job/scripts/make_ci_env.jl ../ClimaAtmos-upstream-<short> $W/up_ci111_env test
julia +1.11 $S/upstream-sync/scripts/mirror_check.jl . <base> upstream/main <old_env> $W/up_ci111_env --diffs $W/mirror_diffs > $W/mirrors.txt
julia +1.11 $S/upstream-sync/scripts/dep_internals.jl . origin/main <base> $W/up_ci111_env <old_env> > $W/internals.txt
```

Read, in this order:

  - **Base.** The merge base must be the last upstream merge's second parent.
    The script warns otherwise.
  - **Output changes.** A moved `ref_counter.jl` means upstream changed output
    itself, so the parity reference moves to the new commit and recorded
    findings keep their old commit labels.
  - **Compat against the fork's caps.** Upstream may now require a version a cap
    excludes (on 2026-10-14 upstream needs `ClimaCore = "1.0.3"`, and the fork
    caps at 1.0.1). Retest the cap's reason with that version (B2) before
    merging. Dropping a cap whose failure still occurs turns CI red.
  - **Removed config keys** that fork tests or configs still set, and **new
    upstream test files**, which need a place in `KNOWN_TEST_GROUPS`.
  - **Conflicts**: the files git will leave unmerged.
  - **Tag impact**: read the diff of every M and H commit in `tag_impact.txt`
    (`git show <hash> -- <file>`), and decide for each whether a fork site must
    change. An M is settled by `mirror_check.jl` below, and an H by reading the
    function. An h commit shares only a file, so skim it for a moved hook call
    or a renamed field. O moves the parity reference. A C commit needs the
    "config defaults that move a test's regime" check of A3, which is
    read-only and can run now. A commit with no flag cannot reach a tag through
    code. It can still reach one through a package it bumps, so the P flag and
    the package-mirror section matter.
  - **A kept method with defaults.** Upstream sometimes adds arguments to a
    function a mirror calls and keeps the old method with defaults. The fork's
    call then compiles and matches at defaults. When the new option is on, it
    diverges with no error, and a closure test at defaults stays green. For
    each changed signature, compare the
    old method's defaults with what the model now passes. Name the option that
    switches the new path. The port item is then "yes, for <option> on", with a
    test that sets it.
  - **Names**: before the merge, the "fork lines" in `names_before.txt` are the
    port's work list. "Upstream's old lines" are resolved by the merge itself.
  - **Mirrors**: an `ERROR` in `mirrors.txt` is a mirror the check could not
    compare (a parent in neither version, a missing file or package, a fork
    function the registry names but the file lacks). Fix the registry first:
    until then the mirror is unchecked. The script exits 2 for that, 1 for a
    changed parent and 0 when all are unchanged.
  - Each `PARENT CHANGED` is a candidate, not yet a port. It is a port only if
    its diff in `mirror_diffs/` touches what the mirror repeats. Read every diff
    and give each flagged mirror its own verdict. The port list, the mutants and
    the parity configurations follow the ports, not the flags. On 5af1766c the check flagged 4 of 29: the water tags' 1M call
    (`ᶜcorr_Tq`, `ᶜα`), the 1M substep (CloudMicrophysics 0.45), the leak's EDMF
    diffusion (`K_entr` removed) and the environment density beside the 1M call
    (unchanged in substance). The leak was missed by hand and failed only at run
    time.
  - **Internals**: each `REMOVED` or `MOVED` in the fork's section of
    `internals.txt` is a port (`BMT._linearize` on 5af1766c). `UNKNOWN (@eval)`
    is a name in a module that generates names, which parsing cannot read: check
    it by hand.

#### The Check report

Write `$W/check.md`. It is the go-ahead request and the Port's work list, so
each port item names a fork site, a reason and how a test will show it.

```markdown
# Upstream <short>: what it brings to the fork

Range: <base> → <short> (<release> plus N commits). Output changes: yes/no (ref_counter A → B).

## Changes that reach the tags
| Commit (PR) | Flags | What upstream changed | Fork site | Port? |
|---|---|---|---|---|
| <hash> (#NNNN) | MH | <one line> | <file:function> | yes: <what> / no: <why> / unsure: <what to run> |

## Other findings
- Mirrors flagged / errors: ... Internals removed or moved: ...
- Fork lines using removed names: ...
- Config keys, defaults and parameters fork tests use: ...
- Compat against the fork's caps: ...
- Conflicts expected: N files (...)

## For the merge
- Port size: N sites. Parity configurations beyond `configs/upstream.jl`: ...
- Test groups at risk: ... (memory near 16 GB, regime moved)
- Recommendation: merge now / wait for <upstream PR or fix>, and why.
```

State what each finding bounds, not more. "No contact" means no file
contact, not "no effect": a P or C commit can move a tag test's regime
without touching a fork file. Mark a port item "unsure" when only a run can
decide it.

End Check by showing the owner the report's summary and the recommendation
with `AskUserQuestion`: merge now, wait, or check something further. A
check-only request ends here with the report.

## Phase 2: Port

Port starts from the owner's go-ahead and `$W/check.md`. It ends with a local
branch that holds the merge commit, then one commit per port, with the
finders of A3 rerun clean. Nothing is pushed in this phase.

### A2. The merge commit

```sh
git switch -c claude/merge-upstream-<short> origin/main
git merge --no-ff upstream/main      # a true merge, no -X ours/theirs
```

Only resolutions go into this commit. Its message lists every conflicted file
with a one-line resolution.

| Where                                            | Resolution                                                                                                                                                                                                               |
|:------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Model code, `src/`                               | Upstream's side wherever the fork had no reason to differ. Keep the fork's hooks, budget brackets and diagnostics. New upstream code inside a fork bracket gets its own bracket and a coverage-registry row with a test. |
| `src/types.jl` type parameters                   | The fork's groups keep their positions (`tagging` before `cosp`), upstream's run bindings stay last.                                                                                                                     |
| `Project.toml`                                   | Upstream's bounds. Fork-only entries (`Printf`, the `CairoMakie` test dependency) stay. A cap stays only if A1 showed its failure still occurs.                                                                          |
| `.buildkite/Project.toml`, `Manifest-v1.11.toml` | Upstream's manifest as merged, plus the fork's `CUDA_Runtime_jll` entry. `project_hash` stays upstream's, so Pkg re-resolves. An invented hash would make Pkg trust an unvalidated manifest.                             |
| `test/runtests.jl`, `.github/workflows/`         | The fork's test groups and CI layout. Upstream's new tests join a fork group. Tests upstream moved to Buildkite stay in a fork group, since the fork does not run Buildkite.                                             |
| `AGENTS.md`, `docs/clima_atmos_specific.md`      | The fork's norms, plus upstream's new rules and rows.                                                                                                                                                                    |
| `NEWS.md`                                        | Both sides: the fork's entries under `main`, upstream's in order.                                                                                                                                                        |
| Upstream identifiers, file names, config keys    | As upstream has them. Fork wording rules apply to fork text only.                                                                                                                                                        |

Then check that nothing is left: `git diff --name-only --diff-filter=U` is
empty, `git grep -n -E '^(<<<<<<<|>>>>>>>)'` finds nothing, and every changed
`.jl` file parses:

```sh
# The working tree against the fork's main: every file the merge changes,
# before the merge commit and after it.
git diff --name-only origin/main -- '*.jl' > $W/changed_jl.txt
julia +1.11 --startup-file=no -e '
  include(joinpath(ENV["CLIMA_SKILLS"], "_lib", "common.jl"))
  files = filter(isfile, readlines(ARGS[1]))
  isempty(files) && error("no changed .jl files: check the list, not the code")
  bad = filter(f -> has_parse_error(Meta.parseall(read(f, String); filename = f)), files)
  foreach(f -> println("PARSE ERROR ", f), bad)
  println("parsed ", length(files), " files, ", length(bad), " with errors")
  exit(isempty(bad) ? 0 : 1)' $W/changed_jl.txt
```

`Meta.parseall` does not throw on a syntax error. It returns an `:error` or
`:incomplete` node, so the check walks the tree. The count guards against a
list that came out empty: on 5af1766c, `git diff HEAD` after the merge commit
listed no files, and a check of nothing printed nothing.

### A3. The port

The changes the merge forces go in separate commits after it, so a reviewer
can read the resolution and the port apart. The port items of `check.md` are
the starting list. Each "unsure" item is settled here, by a run if need be.
Rerun the finder on the merge's working tree:

```sh
julia +1.11 $S/upstream-sync/scripts/removed_names.jl . <base> upstream/main > $W/names_after.txt
```

Every "fork line" is a site to port. Every "upstream's old line" is a
resolution that kept upstream's old code, so recheck it. Port each mirror
`mirror_check.jl` flagged and each internal `dep_internals.jl` flagged, and
rerun both on the merge's tree: `mirror_check.jl` as before, `dep_internals.jl`
with `HEAD` as the tree and `upstream/main` as the upstream ref, since after
the merge upstream's lines are those of the new commit. A port that renames a
fork function updates `mirrors.toml` in the same change of the skills repo; the
check reports a registered function the fork file lacks. The scripts miss some
changes, so also check these by hand:

  - **A dependency's removed names.** Read the release notes of each package
    whose minor or major version moved, and grep the fork's code for each name
    removed. ClimaCore 0.16 renamed the biased operators, and 1.0 removed `⋅`
    and `Geometry.AxisVector`.
  - **Mirrors the registry lacks.** A new mirror enters `mirrors.toml` when it
    is written. Search the fork's comments for "as `<upstream function>`",
    "mirrors", "line for line" and "the parent's" for any the registry misses.
    A mirror that compiles but differs from its parent breaks closure. Pair each
    port with a test whose reference depends on it, and a mutant that fails it
    (`mutation-run`).
  - **Run-time-only failures.** A removed field (`α_lat` in #139) or a changed
    default type (`Val` to `Bool`) is found only by running. So A5 runs every
    fork test file, not only a parse.
  - **Removed config keys.** Fork tests and configs that set them (the survey
    lists them).
  - **Removed parameters.** A fork test's or config's parameter override (a
    TOML table such as `[EDMF_interface_entr_efficiency]`) that names a
    parameter the new code no longer reads. ClimaParams refuses it at run time
    ("Halting simulation due to unused parameters"). On 5af1766c this was the
    entrainment efficiency of the removed `K_e` in
    `tagged_water_edmf_integration.jl`. Grep the fork's `test/` and `toml/`
    for each parameter whose `CAP.` getter or `ClimaParams` name upstream
    removed.
  - **Defaults that moved.** A test that expects a ClimaParams default, a
    tolerance calibrated on the old physics. Fix the fixture, never the
    tolerance, and say why in the PR.
  - **Config defaults that move a test's regime.** A fork test that does not
    set a key runs upstream's new default for it, so its bounds, measured
    in the old regime, can fail or pass for a new reason. List the changed
    defaults with
    `git diff <base> upstream/main -- config/default_configs/default_config.yml`,
    and for each, grep the fork's tests for the key. A test without it gets the
    new default. On 5af1766c (#4889) rain went from the 1-moment power law to a
    fixed speed and snow from fixed to Chen et al. The EDMF precipitation tests
    set neither, and their first-order closing ledger check failed (1.06e-8
    kg m⁻² against a bound of 3e-12). Pin the old regime in the test fixture,
    measure the new default separately, and check it at `main` too. There the
    gap was the tags', present before the merge, not the port's.

### A4. The parity baseline in the docs

`docs/clima_atmos_specific.md#fork-parity-with-upstream` names the upstream
commit last merged ("currently <hash>, release vX plus N commits") and the
version each known departure was checked at. Recheck each departure at the new
commit and update both. `reproducibility_tests/ref_counter.jl` takes
upstream's value.

## Phase 3: Validate

Validate starts from the Port branch and ends with a draft PR. Parity and
every test group run on terrabyte before the push, since CI covers neither the
comparison with upstream nor the EDMF precipitation groups.

### A5. Verify on terrabyte

 1. **Environments.** When the merge changes compat, no CI log fits it yet, so
    build the merge branch's environment without a log, on 1.11 and 1.10.
    When compat did not move (the survey's compat sections are empty), build
    from the latest CI log of `main`, so the versions are CI's. Build the
    upstream worktree's environment the same way, then make sure the two
    agree:
    `julia +1.11 $S/upstream-sync/scripts/versions_diff.jl <env_fork> <env_upstream>`.
    Rebuild the upstream environment with `PINS` set to the fork's versions
    for any difference. If upstream's compat refuses one (a fork cap, say),
    report it as `fork-parity` mode C says, and do not bend the fork's side.

 2. **Parity, `fork-parity` mode C,** against the new upstream commit, not the
    old one. Run `configs/upstream.jl`, plus a configuration for each model
    change the survey's NEWS entries name (#139 ran seven, among them EDMF
    with 1M, a sphere with slab ocean, and implicit Smagorinsky in a box).
    A model change behind an option that is off by default needs a
    configuration that switches it on, or parity never reaches the new code.
    Then the same with the diagnostics on, comparing every upstream field.

 3. **Tests, `terrabyte-test-job`.** An upstream merge is the exception to
    "leave whole groups to CI": it changes code under every group. Run every
    fork group with `TEST_GROUP` on 1.11, the groups CI runs on 1.10, and
    upstream's tests that sit in fork groups, each group in the merge branch's
    environment for that Julia. Note peaks near 16 GB.

 4. **Docs.** The docstring `@ref` check (`docstring_refs.jl`). A heading the
    merge duplicates breaks `[...](@ref)` (#89's "API").

 5. **Invalidations,** when upstream's dependencies moved. CI compares the PR
    with `main` and will go red on any increase. Attribute it with the same
    resolution on all four checkouts: the fork's `main`, the old upstream
    base, the new upstream commit and the merge branch.

    ```sh
    for c in main base_up new_up merge; do   # one worktree each
      julia +1.10 $S/terrabyte-test-job/scripts/make_ci_env.jl $W/$c $W/inv_$c invalidations
    done
    ENVS="$W/inv_main $W/inv_base_up $W/inv_new_up $W/inv_merge" OUT=$W/inv \
      $S/terrabyte-test-job/scripts/submit.sh $W inv "four-way invalidations" -- \
      --time=01:55:00 \
      --cpus-per-task=8 --mem=32G --job-name=inv --output=$W/inv-%j.out \
      $S/upstream-sync/scripts/invalidations_job.sh
    m=$W/inv/inv_merge.1.methods; n=$W/inv/inv_new_up.1.methods
    if [ -s $m ] && [ -s $n ]; then
      LC_ALL=C comm -3 $m $n | wc -l   # 0: the merge invalidates what the new upstream does
    else
      echo "a count is missing: read the job's output"
    fi
    ```

    The job exits non-zero when an environment fails to precompile or a count
    fails, since a missing `.methods` file would otherwise compare as equal.
    `LC_ALL=C` makes `comm` accept Julia's sort order.

    The count here runs 2 above CI's on the same versions (4383 against 4381
    for `main` on 2026-10-14, and in #139), so compare the four local counts
    with each other, not with CI's. If the merge invalidates the same methods
    as the new upstream, and `main` the same as the old base, the increase is
    inherited. Find the package
    behind it from the largest trees in the log. The threshold stays, and the
    check stays red on this PR by decision, since it is not required.

 6. **Raised compat floors.** `ci` resolves the newest versions, but the
    Downgrade workflow resolves each floor. When upstream raises one, run the
    groups with allocation checks in an environment pinned to the new floor
    (`PINS`), on 1.11 and 1.10. On 5af1766c the ClimaCore floor went to 1.0.3,
    and two energy-tag checks failed only in Downgrade (1032 and 2072 bytes
    against 8 and 24), because 1.0.4 has none of 1.0.3's extra 1024 bytes per
    `ᶜenv_value` broadcast. The checks got an allowance on 1.0.3 only.

### A6. The pull request

Use `pr-preflight` for NEWS, wording and the draft/ready steps. The title is
`Merge upstream CliMA/ClimaAtmos.jl main (<short>): <headline packages>`.
Before the push, `clima-reviewer` reviews the branch (see "Who does what").
Open the PR as a draft, naming the fork, since the `upstream` remote makes
`gh` default to CliMA/ClimaAtmos.jl:
`gh pr create --draft -R johannespletzer/ClimaAtmosResiDyn.jl --base main`.
Validate ends there. The owner marks the PR ready, which starts every group
on CI, and merges it. The body, in this order (#139 is the model), takes
items 2 and 5 from `check.md`'s table:

 1. The range: upstream commit, the previous base, the number of commits.
 2. **Upstream brings**: bullets with upstream's PR numbers.
 3. **Compat**: what moved, and which caps are lifted or kept, and why.
 4. **Conflicts (N files), resolved**: model code, tests and CI, docs and notes.
 5. **Adaptations**: each port commit's change, with the test or mutant that
    shows it.
 6. **Parity with upstream `<short>`**: configurations, steps, job ids.
 7. **Checked on terrabyte**: versions, then the passes on 1.11 and on 1.10.
 8. **Invalidations**, if they moved: the four-way table.
 9. **Notes**: memory near 16 GB, findings calibrated on the old physics.
10. **Open for the owner**.

A merge that edits upstream code also wants a manual CI run of every group on
both versions: `gh workflow run ci.yml --ref <branch> -f versions=both`. If
the token may not start it (#89), ask the owner. `versions=both` ignores
`HEAVY_ON_1_10`, so the EDMF precipitation groups run on 1.10 and run out of
memory there (19.4 GiB). For 1.10, dispatch `-f versions=1.10 -f groups=<the fork's groups without the heavy ones>` instead. A PR that
conflicts with `main` gets no `pull_request` CI at all, so merge `main` in
again whenever it moves, then push. The owner merges with a merge commit,
never squash or rebase, which would drop the merge base the next sync
needs. After the merge, other open
branches merge `main` in, with the message
`Merge origin/main (#N, the upstream merge) into <branch>`.

## B. A dependency release breaks CI

The signs: `main` or the nightly turns red in files no recent PR touched, as
an allocation count, a parameter default or an unsatisfiable resolution.

 1. **What moved.** Save the logs of the last green and the first red job of
    the same group and Julia version, then
    `versions_diff.jl $W/logs/green.log $W/logs/red.log`. Usually one to three
    packages moved (#128: ClimaParams; #145: ClimaCore and SurfaceFluxes).

 2. **Isolate.** Build a baseline from the green log, and one environment per
    moved package from the same log with `PINS=<package>=<red version>`, plus
    one with all of them. Run the failing files in each with `test_job.sh`.
    Report each pin's forced moves, which `PROVENANCE` records.

    | Test (file:line) | baseline | A new | B new | both |
    |:---------------- |:-------- |:----- |:----- |:---- |

 3. **Upstream.** Check whether upstream's CI fails the same way
    (`gh run list -R CliMA/ClimaAtmos.jl --workflow ci.yml`), and whether an
    upstream PR moves to the version. Name the package's change that likely
    causes it, marked as unconfirmed unless shown.

 4. **The owner decides** between capping and following, through
    `AskUserQuestion` with the table.

      + **Cap.** Write the range as `"lo - hi"`, keeping other ranges
        (`"0.16, 1.0.0 - 1.0.1"`), and check it with
        `Pkg.Versions.semver_spec`. The lower bound stays, so Downgrade is
        unaffected. The `.buildkite` manifest must still satisfy compat. The PR
        says what would lift the cap.
      + **Follow.** Change the test's expectation. If the Downgrade workflow
        resolves the old lower bound, branch on `pkgversion` (#156). Parity
        holds when both sides resolve the same version, so say that, and that
        `--project=.buildkite` keeps the old value until its manifest moves.

    Either way, add a NEWS line (🐛 for a cap, 🔥 for a followed default).

 5. **Lifting a cap.** At every upstream merge, and whenever the survey shows
    upstream's compat above it, rebuild the failing environment with the newest
    version and rerun the failing files. Lift the cap only if they pass.

## C. CI's versions against the `.buildkite` pins

GitHub CI resolves afresh. Runs with `--project=.buildkite` use the pinned
manifest. Check which one a claim is about:

```sh
julia +1.11 $S/upstream-sync/scripts/versions_diff.jl $W/logs/ci_111.log origin/main:.buildkite/Manifest-v1.11.toml
```

On 2026-10-14 CI resolved ClimaParams 1.3.1, SurfaceFluxes 1.5.0 and RRTMGP
1.1.0, and the pins were 1.2.0, 1.2.1 and 1.0.0. A PR body names the side its
runs used. Moving the pins diverges from upstream's manifest and changes the
experiments' output, so that is the owner's decision. An upstream merge takes
upstream's manifest anyway.

## Who does what

The survey and the finder run in the main session, since their output is bounded.
Resolving conflicts and judging mirrors is Opus work in the main session. A
written port list can go to `clima-analysis-builder` (Sonnet). Before ready,
`clima-reviewer` (Opus high) reviews the PR, and `clima-numerics-reviewer`
too if the port touches a tag mirror or a budget bracket. For CI, wait with
one background command, `gh run watch <run> --exit-status --interval 600 > /dev/null; echo "exit $?"`, whose end re-invokes the session, then give the
run to `mechanical` (Haiku) to fetch the failing job and its first error. An
agent cannot sleep, so it would have to poll.
