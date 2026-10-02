# W61 addendum: each tag's inventory under the hyperdiffusion's reference term

Pre-registered on 2026-10-02, before any job of this addendum, and pushed
first. It answers point 2 of the owner's review of PR #146.

## 1. The question

The WP4b fix PR gives each tag's non-precipitating part its share of the
reference profile's hyperdiffusion outside the operator,
`R_i = φ_i ν₄ ∇⋅(ρ ∇∇² q_tot_r)` (the passive form). The partition's sum is
the parent's term. The term is not in flux form, so each tag's global
inventory changes by `∫∫ R_i dV dt`. W61 did not measure that change. W61's
flat-state test cannot, since `R_i` is zero there.

Two readings:

  - **Q1, the size.** For each tag over 3 days, the signed and the absolute
    time integral of its reference term, relative to its inventory and to its
    precipitation export.
  - **Q2, an alternative.** Allocate the parent's reference flux before the
    divergence, `R_i = ν₄ ∇⋅(φ_i ρ ∇∇² q_tot_r)` (the face form). It is in
    flux form, so on a closed sphere each tag's integral is zero to rounding,
    and the partition's sum is the parent's term. Does it keep the passive
    form's diffusive mixing (the variance rate), or does it bring back W61's
    anti-diffusion? `∇⋅(φ F) = φ ∇⋅F + F⋅∇φ`, so it adds an advection of the
    composition by the reference flux, whose sign is not known in advance.

## 2. Arms

W61's sphere (the moist baroclinic wave, `h_elem` 6, 10 levels to 30 km, 1M,
`dt` 400 s, ARS343, 3 days, region tags `tropics` and `extratropics`,
`water_tag_precipitation: true`). The model's fields do not depend on the
tags, so both arms share one atmosphere.

| arm       | tree                                                      | commit     |
|:--------- |:--------------------------------------------------------- |:---------- |
| `passive` | `../ClimaAtmosResiDyn-wp4bfix-t1`: `main` + passive form  | `81884d5b` |
| `face`    | `../ClimaAtmosResiDyn-wp4bfix-face`: the same + face form | `d4cda274` |

Neither tree is for merge. `passive` isolates the PR's hyperdiffusion from its
other changes (the closing step and the order touch the tags too). Both run
`analysis/water/w61a_inventory.jl` through `analysis/water/w61a_job.sh`, in a
copy of CI's 1.11 environment. Two jobs, one per arm, on `hpda2_compute`.

## 3. What the driver measures

After every step, on the step's end state, it evaluates both forms' reference
term per tag with the model's operators and DSS, and adds `dt ∫R dV` and
`dt ∫|R| dV` to running totals (a rectangle rule: one evaluation per step,
not per stage, so it gives the size, not the exact budget). It adds each
tag's surface precipitation times `dt` to its export. Every 6 h it writes
each tag's inventory (its three parts), the running totals, the variance rate
`∫ χ T dV` of the passive, face and cross forms on the state (`χ` the tag's
`N/ρ`, `T` its whole hyperdiffusion tendency), and the run's ledgers.

## 4. How it is read

  - **Q1.** Reported, not judged: for each tag at 3 days, `∫∫R dV dt` and
    `∫∫|R| dV dt` of the passive form, over the tag's inventory at the start
    and over its 3-day precipitation export, from the `passive` arm. The
    least favourable tag is quoted.
  - **Q2, inventory.** The face form keeps inventories if, in the `face` arm,
    `|∫∫R_face dV dt|` is at most 1e-9 of each tag's start inventory.
  - **Q2, mixing.** The face form keeps the passive form's mixing if, in the
    `face` arm, its variance rate is negative for both tags at every sample
    from 6 h on. A positive sample is reported with its value against the
    passive and cross forms on the same state.
  - **Q2, ledgers.** The `face` arm's repair, repairnet and empty ledgers at
    3 days against the `passive` arm's (W61's passive run gives a check: the
    `passive` arm must reproduce its ledgers byte for byte). Reported.

Q2 decides nothing for the PR. The face form is a candidate for the owner,
not a replacement. If either Q2 rule fails, the face form is reported as not
a candidate in this configuration.

## 5. Budget

Two jobs of about 1.5 h each. The review's limit for the whole round is 12
jobs.
