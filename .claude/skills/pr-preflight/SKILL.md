---
name: pr-preflight
description: Prepare a ClimaAtmosResiDyn.jl pull request for push, opening, marking ready or merging. It checks the base branch of stacked PRs, runs .dev/preflight.sh, scans added text for the fork's wording rules, writes the NEWS.md entry and fills the PR body template (What, Why, What does not change, Parity, Tests, Not in this PR, Open for the owner). Use before every push to a PR branch, before gh pr create or gh pr ready, and before a merge.
---

# Pull request preflight

One push to a PR that is not a draft runs every CI group. So the cheap checks
run here first, and a PR is opened as a draft. The rules come from
`AGENTS.md` ("Local norms"). This skill is the order to apply them in.

Git pushes, `gh pr create`, `gh pr ready` and merges ask the owner for
approval. Never force-push without asking. To drop commits, use the reset and
re-commit recipe, not a rebase.

## 1. Where the branch goes

```sh
git fetch origin
gh issue list --label nightly-red --state open    # while one is open, only its fix merges
gh pr view --json number,baseRefName,isDraft,state 2>/dev/null
git log --oneline origin/main..HEAD | wc -l
```

  - **Base.** A PR targets `main` unless it is deliberately stacked. A stacked
    PR's body starts with `Stacked on #<n>; merge that first.`. Merging a
    stacked PR lands it in its base branch, not in `main`. Work has been lost
    that way more than once, and had to be re-landed.
      + When the base PR merges, retarget at once with `gh pr edit <n> --base main`.
      + Before any merge, `baseRefName` must be `main`, or the owner must have
        agreed to merge into the stack.
  - **Main merged in.** For a long-lived branch, merge `origin/main` before the
    final checks. A rebase is not allowed. Resolve `NEWS.md` by keeping both
    sides' entries.

## 2. Local checks

Bare `python3` here is 3.6. Load the module first:

```sh
source $MODULESHOME/init/zsh; module load python/3.12
.dev/preflight.sh --base origin/main          # use --base <parent branch> when stacked
.dev/preflight.sh --base origin/main --fix    # applies the pinned formatter, then re-run without --fix
```

It checks, in order:

 1. Julia parse of the changed files.
 2. Trailing whitespace and a final newline.
 3. The 92-column margin, as a warning only.
 4. Markdown link ambiguity.
 5. Identity-tuple shapes.
 6. The pinned JuliaFormatter 2.10.1 over the whole repository.
 7. With `--test`, the `infrastructure` group, which is slow. Prefer the
    `terrabyte-test-job` skill for that.

It must end with `pre-flight: green`.

Then, depending on what changed:

  - **`src/` changed:** the files the change touches, on 1.11 and 1.10, with the
    `terrabyte-test-job` skill. Also a `fork-parity` run (diagnostic off
    against on at least), and the allocation tests if a hot path changed.
  - **Docstrings or `docs/src` changed:** `docstring_refs.jl` through
    `terrabyte-test-job`, or the full docs build as a batch job (`docs-sweep`,
    section 3), in a fresh `docs` environment from `make_ci_env.jl`.
  - **Test groups or workflows changed:** `KNOWN_TEST_GROUPS` in
    `test/runtests.jl`, both workflow matrices and the table in
    `docs/clima_atmos_specific.md` must agree.
    `julia .github/read_test_groups.jl` must list the new group. Check whether
    `.github/ci_plan.sh`'s tiers pick it up. Editing `downgrade.yml` triggers its
    whole matrix once.
  - **Comments or docs only:** show that the code is unchanged with
    `docs-sweep`'s `code_unchanged.jl origin/main HEAD`. It must exit 0, and
    any messages or tooling it lists go into the PR body.

## 3. Wording rules on added lines

Docs and comments on `main` describe the current code in the present tense.
Plan and finding IDs, PR numbers, dates, decisions and history go in the
commit message, in `NEWS.md` and on the record branch.

```sh
added() { git diff origin/main...HEAD -U0 -- src test docs/src config | grep '^+' | grep -v '^+++'; }
# IDs, dates and history in any added line.
added | grep -nE '#[0-9]{2,}\b|20[0-9]{2}-[0-9]{2}-[0-9]{2}|\b(WP[0-9][a-z]?|OD[0-9]+|G[0-9]+\.[0-9]+|W[0-9]{2}|FINDINGS?)\b|[Pp]art [0-9]+[a-d]?\b|\b(previously|no longer|used to)\b|bracket'
# Dashes and semicolons in added comments.
added | grep -E '^\+\s*#' | grep -nE '—|;'
```

Not every hit is wrong. Upstream's lines keep their wording. Read each hit
in the fork's own text, then:

  - Use the bookkeeping words: budget is the parent's, ledger is a tag's,
    record is a process's. A threshold is a tolerance. Say applied-update event,
    attributed process and the process's tendency, not bracket. See
    `docs/src/glossary.md`.
  - Keep sentences short, and use two sentences rather than a semicolon or a
    dash.
  - Never rename an upstream identifier, file or config key.

## 4. NEWS.md

Add one bullet at the top of the `main` section for any change a user of
the fork would notice. That covers behaviour, a new key, a compat cap or a
bug fix, but not a refactor or a CI change no user sees.

```markdown
- [#<n>](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/<n>) ![][badge-✨feature/enhancement] <what changes, in the present tense>.
```

  - Badges: `✨feature/enhancement`, `🔥behavioralΔ`, `🐛bugfix`, `💥breaking`
    and `🚀performance`.
  - Add the PR link once the number is known.
  - A behavioural entry states its parity, for example "Model fields are
    unchanged bit for bit".

## 5. The body

Write it to a file under the scratchpad and open the PR as a draft:

```sh
gh pr create --draft --base main --title "<what it does, plainly>" --body-file <file>
```

```markdown
<Stacked on #<n>; merge that first.>          (only when stacked)

<Two or three sentences: what the PR does and why.>

## What changes
## What does not change
<Defaults, other configurations, and model fields bit for bit. For a
documents-only PR: "No runtime code, default, tolerance, dependency or CI
change.">

## Parity
<From the fork-parity skill, with job ids, or "docs only".>

## Tests
<From the terrabyte-test-job skill: a file × Julia table with job ids and
the commit. Name the tests that fail without the change.>

## Not in this PR
## Open for the owner
<The decisions the owner must make, each with a recommendation.>

<Agent line: who wrote and who reviewed, with model, effort and tokens, for
example "worker (Sonnet high, 120k) drafted, clima-reviewer (Opus high, 90k)
reviewed.">

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

  - Claim only what was run. "Not run here, left to CI" is a valid line.
  - Correct a claim that turns out wrong in the body, and say so. Do not leave
    it standing.

## 6. Ready and after

  - Mark it ready with `gh pr ready <n>` only after sections 2 to 4 pass.
    That starts every group on 1.11.
  - Wait for CI with one background command, `gh run watch <run> --exit-status --interval 600 > /dev/null; echo "exit $?"`, whose end
    re-invokes the session. Then give a red run to the `mechanical` agent,
    which returns the failing job and its first error. An agent cannot sleep,
    so it would have to poll.
  - Before merging, re-check section 1's base and the `nightly-red` issue.
  - A merge that edits upstream code also deserves a manual `ci.yml` run of
    every group on both Julia versions.
