# Fixes prepared from the reviews of 2026-09-16

One review comment was posted on each open pull request, in order:
[#72](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/72#issuecomment-5695271743),
[#74](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/74#issuecomment-5695278278),
[#75](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/75#issuecomment-5695284905),
[#76](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/76#issuecomment-5695455151),
[#77](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/77#issuecomment-5695468278),
[#78](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/78#issuecomment-5695628451),
[#79](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/79#issuecomment-5695637975),
[#80](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/pull/80#issuecomment-5695644776).

The patches here address the findings that had a clear fix. On the owner's
say they were pushed to the pull request branches on 2026-09-16 (#72 at
50dd1dd, #74 at d00a99a, #75 at a28dacc, #76 at 33481bc, #77 at a83e6ab,
#78 at 2067875, #79 at 423382a), so this directory is now a record. The
owner also decided that the closure check stays on by default inside the
other pull requests' integration tests. Each directory holds the commits for
one pull request, on top of its head at the time of the review. To re-apply
elsewhere:

```
git checkout <pr-branch>
git am review-fixes/2026-09-16/pr<NN>/*.patch
```

Julia was not available where the patches were written, so nothing here was
run. The docs and comment changes are safe to read. The test and source
changes need one CI run:

- `pr72`: item 9 also compares `uₕ`; both `AtmosTagging` refusals get a
  config-level test, and the `enthalpy` key a positive case; the page's two
  unconditional passive-tracer statements name the transport in use.
- `pr74`: three sentence fixes (startup warnings of the recommended layout,
  where sedimentation lands for each family, when the numerics set the gap).
- `pr75`: the restart compares every field of the state; after the solve every
  tag is asserted non-negative where `E` is positive; header, comment and docs.
- `pr76`: the two `@docs` entries the docs build needs; the `foreach` closure
  in `ldiv!(::SplitJacobianSolver)` replaced by a recursion over the tuple,
  as the likely cause of the 1056 bytes on Julia 1.10; the test header names
  item 6. Whether the recursion removes the bytes needs the 1.10 job.
- `pr77`: the two `@docs` entries the docs build needs; a NEWS entry for the
  new defaults and the corrected sentence about the offset; the zero guard on
  `relative_since_spin_up`; five reworded docstrings and help texts.
- `pr78`: `Vararg{Any, N}` on the allocation helper; header, comment and docs.
- `pr79`: the known departures, `isequal`, the solver scope, the upstream
  commit rule and the meaning of "diagnostic off".

Not prepared, since they need the owner's decision or a Julia session: the
U4 audit column tests and the spin-up run-level test of #77, the tridiagonal
two-iteration comparison of #76, the tags-on versus tags-off test of #79, and
the NEWS bullet and citation of #80.
