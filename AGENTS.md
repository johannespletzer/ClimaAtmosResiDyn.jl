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
- Prefer Julia 1.11.x for local work. CI runs the fork's own test groups on 1.10 and 1.11 and the upstream ones on 1.11 only. See [Which jobs run when](docs/clima_atmos_specific.md#which-jobs-run-when).
- For runtime validation, prefer `julia +1.11 --project=.buildkite .buildkite/ci_driver.jl ...`.
- For package tests, prefer `Pkg.test()` over manually `include`ing `test/runtests.jl` because test-only deps are loaded through the package test path.
- Keep edits inside the owning subtree when possible; use [src/ClimaAtmos.jl](src/ClimaAtmos.jl) to trace where a feature is wired.
- Match existing style: explicit names, narrow imports, comments that explain why.
- Write comments in simple sentences. Prefer a few short sentences over one long one strung together with colons, dashes and parentheses.
- Follow the software design patterns in [docs/dev-guides/architecture/software_design_patterns.md](docs/dev-guides/architecture/software_design_patterns.md) for new code and refactor toward them when touching existing code.
- Format code before committing. CI checks formatting via the `prek` hook in [.github/workflows/run-prek.yml](.github/workflows/run-prek.yml), which runs JuliaFormatter from the version-pinned [.dev/format/Project.toml](.dev/format/Project.toml) environment (currently `=2.10.1`). Match CI with either `prek run julia-formatter --all-files` or the pinned env directly: `julia --startup-file=no --project=.dev/format -e 'using Pkg; Pkg.instantiate(io=devnull); using JuliaFormatter; format(ARGS)' .`. Avoid `julia -e 'using JuliaFormatter; format(\".\")'` from your global environment — `Pkg.add("JuliaFormatter")` installs v2 by default and a mismatched version produces a different diff.
- Optional but recommended: install the pre-commit hooks in [.pre-commit-config.yaml](.pre-commit-config.yaml) (`uv tool install prek && prek install`) to auto-format and trim trailing whitespace on commit. See [docs/src/contributor_guide.md](docs/src/contributor_guide.md) ("Pre-commit hooks").

## Self-correction

- If the code map in [docs/clima_atmos_specific.md](docs/clima_atmos_specific.md) is discovered to be stale, update it.
- If the user gives a correction about how work should be done in this repo, add it to `Local norms` or another clearly labeled persistent section in this file or in [docs/clima_atmos_specific.md](docs/clima_atmos_specific.md) so future sessions inherit it.
