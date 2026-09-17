# Draft: an upstream PR for the vertical water borrowing guards

A local draft for decision 12 of `OPERATIONAL_TODO.md`, written on 2026-09-16.
**Not pushed, not opened.** Opening a PR on `CliMA/ClimaAtmos.jl` is
public, and the owner decides.

## Where it is

  - **Branch:** `upstream-vwb-species-guard`, commit `527cdf06`, on
    `CliMA/ClimaAtmos.jl` `main` at `eb010645` (2026-09-16). It lives only in
    the worktree `../ClimaAtmos-upstream-vwb`. The local clone has a new remote,
    `upstream`, fetched over HTTPS.
  - **Files:** `src/prognostic_equations/limited_tendencies.jl` (the two guards,
    a comment and the helper's docstring), `test/prognostic_equations/vertical_water_borrowing_tests.jl`
    (one new test set, run for two cases), `NEWS.md` (one bugfix entry).
  - **To open it:** `johannespletzer/ClimaAtmosResiDyn.jl` is a GitHub fork of
    `CliMA/ClimaAtmos.jl`, so the branch can be pushed there and the PR opened
    against `CliMA/ClimaAtmos.jl:main`. The clone's `gh` default is now the
    fork, so the command needs `-R CliMA/ClimaAtmos.jl --head
    johannespletzer:upstream-vwb-species-guard`. Upstream runs a CLA check
    (`.github/workflows/cla.yml`), so the owner may need to sign it.

## How it was tested

On the terrabyte login node, Julia 1.11.9, with upstream's pinned
`.buildkite` environment, running
`test/prognostic_equations/vertical_water_borrowing_tests.jl`:

| code | result |
|:--|:--|
| upstream `main`, unfixed | 11 pass, 2 fail. With the species list, `ρ` misses the whole increment of total water (1e-3 against a tolerance of 1.4e-5) and `ρe_tot` misses 2,564 against 0.93. With all tracers it passes. |
| with the fix | 13 of 13 pass. |

A first version of the test compared the states with `≈` and missed the bug:
the default Float32 and a density near one hid an increment of 1e-7. The test
now compares the increments, with a tolerance of 100 rounding units, and
borrows 1e-3.

A direct check on the unfixed code gave, for `species = (:ρq_tot,)`: the
guard with `@name(ρq_tot)` is `false`, with `:ρq_tot` it is `true`, and after
the limiter `max |Δρq_tot| = 1e-7` while `max |Δρ| = max |Δρe_tot| = 0`.

## PR text

**Title:** Fix the vertical water borrowing guards for an explicit species list

**Body:**

### Problem

`limiters_func!` applies the vertical water borrowing limiter to the tracers in
`vertical_water_borrowing_species`. `vertical_water_borrowing_species_from_config`
returns them as a `Tuple` of `Symbol`s, such as `(:ρq_tot,)`.

The tracer loop tests each `Symbol` from `propertynames(Y.c)`, so it borrows
`ρq_tot` when the list names it. The two guards around it test
`@name(ρq_tot)` instead. They take the snapshot of `ρq_tot` before the limiter
and call `enforce_mass_energy_consistency!` after it. A `FieldName` never
equals a `Symbol`:

```julia
import ClimaCore.MatrixFields: @name
@name(ρq_tot) in (:ρq_tot,)  # false
```

So with an explicit list the limiter changes `ρq_tot`, while `ρ` and `ρe_tot`
stay as they were. The docs promise the opposite (`docs/src/microphysics.md`:
"when total water is limited, density and total energy are corrected for
consistency"). With the default, `vertical_water_borrowing_species: ~`, both
guards are true and nothing is wrong.

### Fix

The guards test `:ρq_tot`. The docstring of `_should_apply_limiter_to_tracer`
said a `FieldName` could be passed; it now says the name is a `Symbol`, the
type `species` holds.

### Test

A new test set in `test/prognostic_equations/vertical_water_borrowing_tests.jl`
runs for `["ρq_tot"]` and for all tracers:
- it makes part of `ρq_tot` negative;
- it calls `limiters_func!`;
- it checks that `ρ` changed by the change in `ρq_tot`, and `ρe_tot` by that
  change times `e_int_vapor(T) + Φ`.

The tolerance is 100 rounding units. It compares increments rather than states,
because at Float32 a density near one hides a small increment. On `main` the
species-list case fails, missing all of the increment. With the fix, both cases
pass.

The existing test sets use the same species list, but check only that
`ρq_tot` becomes non-negative and keeps its total. That is why this went
unnoticed.

### Effect

Results change only for runs that set `tracer_nonnegativity_method:
vertical_water_borrowing` and list `ρq_tot` in
`vertical_water_borrowing_species`. No configuration in `config/` sets the list,
so no reproducibility reference changes.

## Notes for the owner

  - The PR text says nothing about the fork. Mention it, or not, as you prefer.
  - The NEWS entry has no PR number yet; add it once the PR exists, as the
    other entries do.
  - **For decision 12:** if upstream takes the fix, the fork's `dd06318f` becomes
    identical to upstream with the next merge, and the known departure in
    `docs/clima_atmos_specific.md` can be removed then. Until it merges, keep it
    as a named exception.
