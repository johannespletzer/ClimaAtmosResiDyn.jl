---
name: docs-sweep
description: Rewrite or check ClimaAtmosResiDyn.jl's docs and comments and prove the code did not change. Shows that a branch changed only comments, docstrings, help texts and Markdown (string literals such as error texts listed apart), and checks the fork's text over whole files for the wording rules, names and paths that no longer exist, headings an @ref cannot resolve and unused glossary terms. Use for a docs-only PR, before claiming "code, keys, defaults and output are unchanged", after an upstream merge renamed things the comments name, and before a docs build.
---

# Docs sweeps

A docs PR rewrites text and must leave the code alone. Its NEWS line says
"Code, keys, defaults and output are unchanged" (#133, #138, #140), and this
skill proves it. It also checks the fork's text over whole files, which
`pr-preflight` does only for the lines a diff adds.

The scripts are in the checkout's `.claude/skills/docs-sweep/scripts/`. Both read
through git and run on a login node in seconds.

| Script                                                   | Does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
|:-------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `code_unchanged.jl <checkout> <base_ref> <head_ref>`     | The branch's changes from the merge base. Each changed `.jl` file compared as parsed code without line numbers, comments and docstrings (a docstring's interpolations count as code): `text only`, `MESSAGES` (only strings inside `error`, `@warn` and other message calls differ, listed) or `CODE CHANGED` (anything else, a changed dict key or regex included). Each changed `.yml` compared without comments and `help:` entries. `.md`, `.bib` and images are docs; `docs/make.jl`, `.dev/` and `.github/` are `TOOLING`, listed; any other file type is `OTHER CHANGED`. Exit 0 when only text changed |
| `text_checks.jl <checkout> <ref> <upstream_ref> [--all]` | The fork's lines of `docs/src/**/*.md` and of the comments and docstrings in `src/`: wording, backticked names the code never uses, paths and links that name no file, repeated headings an `@ref` points at, glossary terms nothing uses                                                                                                                                                                                                                                                                                                                                                                      |

`upstream_ref` is the upstream commit last merged, the second parent of the
last "Merge upstream" merge on `main`. A line found verbatim in upstream's copy
of the same file is upstream's, and the fork's rules do not apply to it.
Upstream's text keeps upstream's wording (AGENTS.md).

## 1. Before writing

```sh
S=$CLIMA_SKILLS/docs-sweep/scripts
UP=$(git log origin/main --merges --grep='^Merge upstream' -1 --format=%p | cut -d' ' -f2)
julia +1.11 $S/text_checks.jl . origin/main $UP --all > $W/text_checks.txt
```

The hits are a work list, not verdicts:

  - **Wording** hits are real by AGENTS.md's rules: plan and finding IDs, PR
    numbers, dates and history words belong in commit messages, NEWS.md and
    the record branch. A memo or plan page in `docs/src` is one whole hit.
    The style list (em dashes, semicolons outside parentheses) is a reading
    aid for the short-sentence rule. Keep the semicolons that read best.
  - **Names** the code never uses are either stale (a removed function, a
    renamed diagnostic) or notation (`ε_state` in a memo, a field built by
    string concatenation). Fix the stale ones. Check a name with `git grep`
    before calling it stale.
  - **Paths**: a file of the record branch (`LEARNINGS.md`) or of a package
    (`imex_ark.jl`) is not in the tree on purpose. Say whose file it is, or
    link it.
  - **Headings** that repeat matter only when an `@ref` points at one (#89's
    "API"). The harmless ones are listed apart.
  - **Glossary** terms nothing uses may be defined for readers of the code.
    Keep them if so.

## 2. While writing

  - Docs and comments describe the current code in the present tense, in
    short sentences. Use the bookkeeping words: budget is the parent's,
    ledger is a tag's, record is a process's. Say applied-update event,
    attributed process and the process's tendency, not bracket. See the
    glossary.
  - Do not touch upstream's lines. A fork comment on upstream code goes on
    its own line.
  - A docstring that moves keeps its `[`name`](@ref)` targets resolvable, and
    a page that is renamed keeps its `docs/make.jl` entry.
  - Commit code and text apart. A sweep commit has no code change, so
    `code_unchanged.jl` on it alone shows that.

## 3. Before the PR

```sh
julia +1.11 $S/code_unchanged.jl . origin/main HEAD                   # must exit 0
julia +1.11 $S/text_checks.jl . HEAD $UP > $W/text_checks_after.txt  # fewer hits than before
```

  - `MESSAGES` means error or warning texts changed. That is allowed in a
    sweep, but the NEWS line says so ("Error and warning texts ... state ...").
    Only a message's text counts: the literal strings given to `error`,
    `@warn` and the like, the message of `@assert` but not its condition,
    and terminal `print`s. A changed key, regex, path or `Symbol("...")`
    name is `CODE CHANGED`, also inside a message call, and so is a `print`
    to a file.

  - Only committed changes are compared. With none, the script says so and
    fails.

  - `TOOLING` (`docs/make.jl`, `.dev/`, `.github/`) does not touch the model,
    so it passes, but it is judged and listed with its verdict, and the PR
    names it (#138 renamed a page in `docs/make.jl`).

  - `CODE CHANGED`, `CONFIG CHANGED` or `OTHER CHANGED` (a `.toml` parameter
    file, compat, a script) is not a docs PR. Split the change.

  - The docstring `@ref` check: build a `docs` environment and run
    `docstring_refs.jl` with `terrabyte-test-job` (a batch job, minutes).

  - The full docs build, once before marking ready, as a batch job:

    ```sh
    T=$CLIMA_SKILLS/terrabyte-test-job/scripts
    julia +1.11 $T/make_ci_env.jl . $W/<tag>_docs_env docs
    $T/submit.sh $W/<tag>_run docs "Documenter build" -- \
        --time=01:00:00 --cpus-per-task=4 --mem=16G \
        --job-name=docs --output=$W/<tag>_run/docs-%j.out \
        --wrap "cd $PWD && julia +1.11 --project=$W/<tag>_docs_env docs/make.jl"
    ```

    A stale `docs/Manifest.toml` shows up as an `UndefVarError` for a
    ClimaCore symbol during precompilation, not as a documentation error
    (AGENTS.md). The environment from `make_ci_env.jl` is fresh.

In the PR body: `code_unchanged.jl`'s verdict line and any messages, and the
hit counts of `text_checks.jl` before and after, by check.

## Who does what

The scripts' output is bounded, so the main session runs them. Rewriting text
is judgement and stays in the main session under the wording rules. A long
list of mechanical fixes (stale paths, a renamed name in many comments) can go
to `worker` (Sonnet), with `code_unchanged.jl` run on its result.
