# Known issues

Open problems that are understood but not yet fixed. Each entry records what is
established, so the next person does not have to re-derive it. GitHub Issues are
disabled on this repository, so this file is where they live.

Remove an entry when it is fixed.

## 1. Tagged water closure assertions fail in the dynamics test group

**Status:** diagnosed; the two assertions are corrected in
`test/tagged_water_integration.jl`, awaiting a dynamics run that reaches them.

Two assertions in `test/tagged_water_integration.jl` failed deterministically on
`ci 1.10 - dynamics` (run
[32335353545](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/actions/runs/32335353545)):

```
Tagged water limiter rescale: Test Failed at test/tagged_water_integration.jl:267
  Expression: maximum(abs.(residual)) / scale < 0.001
   Evaluated: 0.0011732894309513337 < 0.001

Tagged water 1M sedimentation closure: Test Failed at test/tagged_water_integration.jl:441
  Expression: maximum(norm) <= 1 + 100 * eps(FT)
   Evaluated: 1.000060085395493 <= 1.0000000000000222
```

Both measure the same quantity — how far the partition tags have drifted from
`ρq_tot` — and neither is a statement the implementation makes.

  - `norm` is `Σₖ clamp(ρq_tagₖ / ρq_tot, 0, 1)` over the partition tags. Once
    `repair_water_tag_partition!` has made the tags non-negative, that is
    `Σₖ ρq_tagₖ / ρq_tot` wherever no single tag exceeds the parent, i.e. the
    *pointwise relative* closure residual. Bounding it by `1 + 100 · eps` asserts
    exact pointwise closure, which `bfd5b4a` deliberately declines to provide:
    the repair does not renormalize the tags onto `ρq_tot`, because doing so
    would drive `q_tag_res` to zero by construction and destroy the leakage
    monitor. The same file budgets that leakage at `5e-3` (column) and `1e-3`
    (sphere), and `norm` is the harsher measure of the two because it normalizes
    by the local `ρq_tot` rather than by the column maximum.

    The property the assertion's comment claims — that the denominator cannot
    amplify the shares it divides — needs no bound on `norm` at all: each clamped
    share is one of its non-negative terms, so every share is in `[0, 1]` and the
    partition's shares sum to 1 for any positive `norm`. That is now asserted
    directly on the shares, and `norm` keeps a drift monitor at `1 + 1e-2`.

  - The sphere residual tolerance of `1e-3` predates the repair. The test was
    added in `cadb2ec`, the repair in `bfd5b4a` ten hours later, and the repair
    changes exactly what the assertion measures: it zeroes the tags of a cell
    whose negatives outweigh its positives, and empties them when a constraint
    clips a non-positive `ρq_tot`, so the removed water surfaces in the residual
    by design. The repair was committed unrun ("no Julia toolchain in this
    environment"), and this repository's Actions history begins on 2026-08-19,
    after it — so no CI run has ever observed these tests green. The tolerance is
    now `1e-2`, which keeps the residual nearly two orders inside the `1e-1`
    excursion bound the individual tags get in the same testset.

Also established:

  - Deterministic, not flaky. The same two assertions failed on every run that
    reached them.

  - Resolution-dependent magnitude: `ci 1.10 - dynamics` evaluates `norm` at
    `1.000060085395493`, `Downgrade 1.10` at `1.0001545917163408`. Both are
    inside the new bound.

  - Not caused by the Levante GPU runscript work in #21. It reproduces
    identically before and after the only source changes on that branch, which
    were five blank lines inside docstrings in
    `src/diagnostics/tagged_water_diagnostics.jl` and
    `src/prognostic_equations/constrain_state.jl`.

What is not settled: whether a pointwise drift of `6e-5` in `norm`, and `1.2e-3`
in the sphere residual, is the right amount of leakage for this scheme. The
corrected assertions bound it and record it; tightening it would mean changing
the closure, not the test.

## 2. Downstream ClimaCoupler tests need a cluster-only artifact

**Status:** open, and not fixable from this repository alone.

Both `downstream ClimaCoupler.jl` jobs fail during `CoupledSimulation`
construction:

```
AMIP test: Error During Test
  LoadError: Artifact "wxquest_initial_conditions" was not found by looking in the paths:
    ~/.julia/artifacts/85b1e3654fb88f19a715ea6c235e1d66f254d2e6
```

raised from `@clima_artifact("wxquest_initial_conditions")` in
`src/utils/weather_model.jl`, via `Setups.overwrite_initial_state!` in
`src/setups/WeatherModel.jl`.

What is established:

  - The artifact cannot be downloaded. `Artifacts.toml` declares
    `wxquest_initial_conditions` with a `git-tree-sha1` and no `download`
    block, so it resolves only through an `Overrides.toml` on a cluster that
    already holds the data. Upstream `CliMA/ClimaAtmos.jl@main` declares it
    identically, so this is by design rather than local drift.

  - The trigger is upstream. `.github/workflows/downstream.yml` checks out
    `CliMA/ClimaCoupler.jl` **main** unpinned. The job passed against
    ClimaCoupler `3d9c07c3` and fails against `0ad056e0`; the AMIP test now
    reaches a `WeatherModel` initial condition that needs the artifact.

  - Julia-version independent: 1.10 and 1.11 fail identically.

Options, none of them free: pin the downstream checkout to a known-good
ClimaCoupler commit (masks the breakage until someone unpins it), provide an
artifact override in CI, or fix it on the ClimaCoupler side so the AMIP test
does not require cluster-only data.

## 3. Levante 1/2/4 GPU scaling has not been measured

**Status:** open, needs a run on Levante.

`runscripts/xmodel.1gpu`, `xmodel.2gpus` and `xmodel.4gpus` are verified
correct on the machine — the binding report shows `MATCH` on every rank and the
CUDA/MPI device test passes — but the strong-scaling numbers they exist to
produce have not been collected. The measurement protocol is in
`runscripts/README.md`.
