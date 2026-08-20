# Known issues

Open problems that are understood but not yet fixed. Each entry records what is
established, so the next person does not have to re-derive it. GitHub Issues are
disabled on this repository, so this file is where they live.

Remove an entry when it is fixed.

## 1. Tagged water closure assertions fail in the dynamics test group

**Status:** open, needs an owner for the tagged-water closure.

Two assertions in `test/tagged_water_integration.jl` fail deterministically.
At `test/tagged_water_integration.jl:441`, in the
`Tagged water 1M sedimentation closure` testset:

```
Tagged water 1M sedimentation closure: Test Failed at test/tagged_water_integration.jl:441
  Expression: maximum(norm) <= 1 + 100 * eps(FT)
   Evaluated: 1.000060085395493 <= 1.0000000000000222
```

Testset roll-up:

```
Test Summary:                                   | Pass  Fail  Total      Time
Tagged water integration                        |   80     2     82   15m18.8s
  Tagged water integration                      |   27            27    3m56.6s
  Tagged water limiter rescale                  |   27     1      28    4m44.8s
  Tagged water restart round-trip               |    6             6    2m07.6s
  Tagged water rejects unsupported microphysics |    4             4       0.2s
  Tagged water 1M sedimentation closure         |   16     1      17    4m29.1s
```

What is established:

  - Deterministic, not flaky. The same two assertions failed on every run that
    reached them.

  - Present under two different dependency sets, with a resolution-dependent
    magnitude: `ci 1.10 - dynamics` evaluates `1.000060085395493`, whereas
    `Downgrade 1.10` evaluates `1.0001545917163408`.

  - Pre-existing, and not caused by the Levante GPU runscript work in #21. It
    reproduces identically before and after the only source changes on that
    branch, which were five blank lines inside docstrings in
    `src/diagnostics/tagged_water_diagnostics.jl` and
    `src/prognostic_equations/constrain_state.jl`.

What needs deciding: the overshoot is about `6e-5` relative, against a tolerance
of `100 * eps(Float32)`, roughly `2.2e-14`. Nine orders of magnitude is too wide
a gap to close by nudging the tolerance. Either the closure genuinely does not
hold to round-off through sedimentation and the limiter rescale, or the
assertion states something stronger than was intended.

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
