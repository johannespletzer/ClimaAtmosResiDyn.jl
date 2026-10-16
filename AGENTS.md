# ClimaAtmos Agent Guide

## Ecosystem Guidelines

Please refer to the shared CliMA agent index for ecosystem-wide rules regarding architecture, performance, code quality, infrastructure, and workflows:

- [docs/dev-guides/AGENTS.md](docs/dev-guides/AGENTS.md) — Shared CliMA agent guidelines.

> Shared guides live at `docs/dev-guides/` and are vendored from the canonical source:
> https://github.com/CliMA/DeveloperGuides. Edit shared guides there, not here.

## Repo-Specific Guidelines

Always read the ClimaAtmos-specific guide before working in this repository:

- [docs/clima_atmos_specific.md](docs/clima_atmos_specific.md) — directory tree, test groups, and reproducibility specifics for *this* repo.

## Local norms

- **Simulation results must stay binary identical to upstream ClimaAtmos.**
  This fork develops diagnostics only. A configuration that upstream
  ClimaAtmos can run must give bit-for-bit the same results here as at the
  upstream commit last merged. With a diagnostic switched on, every field
  upstream has must still be bit for bit the same. Only the diagnostic's own
  fields and output may differ. A change that moves model output is a defect
  here, not a new reference. See
  [Fork parity with upstream](docs/clima_atmos_specific.md#fork-parity-with-upstream).
- Prefer Julia 1.11.x for local work. CI runs in tiers. A draft pull request
  gets the load jobs and `infrastructure` on 1.11. A pull request ready for
  review gets every group on 1.11. The fork's groups run on 1.10 nightly. See
  [Which jobs run when](docs/clima_atmos_specific.md#which-jobs-run-when).
- Open a pull request as a draft and mark it ready once the local checks
  pass. Every push to a pull request that is not a draft runs every group.
  Locally, run the test files a change touches, and leave whole groups to CI.
- A red scheduled run opens an issue labelled `nightly-red`. While it is open,
  only its fix merges.
- For runtime validation, prefer `julia +1.11 --project=.buildkite .buildkite/ci_driver.jl ...`.
- That command needs a prepared environment on a cluster, and it fails in
  confusing ways without one. `.buildkite/LocalPreferences.toml` is generated,
  not tracked, so run the setup script for the machine once first:
  `./runscripts/setup-julia-terrabyte.tcsh cpu` on LRZ terrabyte, or
  `./runscripts/setup-julia-levante.tcsh {cpu,gpu}` on DKRZ Levante. Afterwards
  each Julia call needs that machine's `JULIA_DEPOT_PATH` and MPI module, which
  the setup script prints when it finishes. See
  [runscripts/README.md](runscripts/README.md).
- For package tests, prefer `Pkg.test()` over manually `include`ing `test/runtests.jl` because test-only deps are loaded through the package test path.
- `AtmosConfig` keeps only the keys `config/default_configs/default_config.yml`
  has. An unknown key, such as one upstream renamed, gets a warning and the
  default. Set `strict_config: true` to make it an error.
- `.gitignore` ignores `*.json` and `*.out`, so `git add -A` skips them
  silently. A file with those endings that belongs in a commit needs `git add -f`.
- A Julia test process keeps every model type it compiles, so its peak
  memory grows with each one. A GitHub runner has 16 GB. Measure a new
  tagged-simulation file's peak RSS before it goes into CI, for example with
  `/usr/bin/time -f %M` or in a Slurm job with `--mem=15G`. One new EDMF
  model type per process is the safe default. A second fits where the
  measurement leaves room, as in `tagged_water_edmf_integration.jl`, whose
  tagged and untagged builds share one process. Files included in one
  process share its memory, so isolating a build needs a test group of its
  own. Keep the tagged-against-untagged parity comparison when splitting,
  for example through a saved state. See
  [Test groups](docs/clima_atmos_specific.md#test-groups).
- A CI job that ends with "The operation was canceled." or "The hosted
  runner lost communication" may have run out of memory. A runner shutdown
  reads the same. Check the job's annotations and the file's measured peak
  RSS before naming memory as the cause.
- Keep edits inside the owning subtree when possible; use [src/ClimaAtmos.jl](src/ClimaAtmos.jl) to trace where a feature is wired.
- Workflow skills for the recurring work are in `.claude/skills/`:
  `upstream-sync` (upstream merges in phases Check, Port and Validate, and
  dependency drift), `fork-parity`, `terrabyte-test-job`, `mutation-run`,
  `pr-preflight` and `docs-sweep`. Use them, and extend one rather than
  writing a new procedure. Their site values (the Slurm account and
  partitions, the Julia depot) come from a private file outside the
  repository. `.claude/site.example.env` lists them.
- Match existing style: explicit names, narrow imports, comments that explain why.
- Write comments in simple sentences. Prefer a few short sentences over one long one strung together with colons, dashes and parentheses. Use few semicolons. Two clauses become two sentences.
- Comments describe the code as it is. Never document previously existing code or what
  a change fixed ("used to", "previously", "no longer"); that history belongs in the
  commit message, and in `NEWS.md` when behavior changes.
- Follow the software design patterns in [docs/dev-guides/code-quality/software_design_patterns.md](docs/dev-guides/code-quality/software_design_patterns.md) for new code and refactor toward them when touching existing code.
- Format code before committing. CI checks formatting via the `prek` hook in [.github/workflows/run-prek.yml](.github/workflows/run-prek.yml), which runs JuliaFormatter from the version-pinned [.dev/format/Project.toml](.dev/format/Project.toml) environment (currently `=2.10.1`). Match CI with either `prek run julia-formatter --all-files` or the pinned env directly: `julia --startup-file=no --project=.dev/format -e 'using Pkg; Pkg.instantiate(io=devnull); using JuliaFormatter; format(ARGS)' .`. Avoid `julia -e 'using JuliaFormatter; format(\".\")'` from your global environment — `Pkg.add("JuliaFormatter")` installs v2 by default and a mismatched version produces a different diff.
- Build the docs with `julia +1.11 --project=docs docs/make.jl`. `docs/Manifest.toml`
  is gitignored, so a local copy goes stale as dependencies move; refresh it the
  way [docs.yml](.github/workflows/docs.yml) does — `Pkg.develop(PackageSpec(path="."))`
  then `Pkg.instantiate()` in the `docs` environment — before concluding that a
  build failure is real. A stale manifest shows up as an `UndefVarError` for a
  ClimaCore symbol during precompilation, not as a documentation error.
- Optional but recommended: install the pre-commit hooks in [.pre-commit-config.yaml](.pre-commit-config.yaml) (`uv tool install prek && prek install`) to auto-format and trim trailing whitespace on commit. See [docs/src/contributor_guide.md](docs/src/contributor_guide.md) ("Pre-commit hooks").
- The `markdown-link-ambiguity` prek hook skips fenced blocks and inline
  code only. Put formulas such as `x[i] (a + b)` in a fenced block, not an
  indented one.
- Bookkeeping words: budget is the parent's, ledger is a tag's, record is a
  process's. A threshold is a tolerance, and a CI job's limit is its time
  limit. A budget in the physical sense (energy, water, TKE) keeps the word,
  and so does the stratospheric tracers' tracer budget, a separate feature.
  The code follows the rule: the parent budget's names include
  `BudgetJournal` (held in `adapter.journal`) and `TimestepperPin`. Say
  applied-update event, attributed process and the process's tendency, not
  bracket. See [the glossary](docs/src/glossary.md).
- Docs and comments on `main` describe the current code in the present tense.
  Plan and finding IDs, PR numbers, dates and decisions go in commit messages,
  NEWS.md and the record branch, not in docs or comments.
- Do not touch upstream naming conventions. Fork rules such as the
  bookkeeping words apply only to names and text the fork added. Upstream
  ClimaAtmos identifiers, file names and config keys stay as upstream has
  them, and upstream lines keep their wording, even where a fork rule would
  name them differently.
- Restarts and existing simulation output do not constrain renames yet. The
  runs so far were tests and can be redone, so a fork-owned checkpoint key,
  output name or config key may change when a naming rule calls for it.
- Write new loops over tuples that grow with the tag count with
  `MatrixFields.unrolled_foreach`. A recursion over `Base.tail` allocates past
  32 elements, and a `foreach` over a tuple of mixed types allocates on Julia
  1.10 (see `solve_uncoupled_fields!`). The Jacobian update keeps its `for`
  loops, where `unrolled_foreach` allocates. The existing recursions over one
  family's tags allocate only past 32 tags in that family.
- Compare the split solver with ClimaCore's nested `FieldMatrixWithSolver`
  only at a few fields. The nested solver over about 40 fields takes over an
  hour to compile. Test the large sizes on the split solver alone.

## Self-correction

- If the code map in [docs/clima_atmos_specific.md](docs/clima_atmos_specific.md) is discovered to be stale, update it.
- If the user gives a correction about how work should be done in this repo, add it to `Local norms` or another clearly labeled persistent section in this file or in [docs/clima_atmos_specific.md](docs/clima_atmos_specific.md) so future sessions inherit it.
