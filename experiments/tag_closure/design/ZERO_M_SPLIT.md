# The 0M sink split by subdomain, `pr_tag` under 0M, and known issue 4: the design note of WP4a

Written on 2026-09-24 for G3's WP4a (G3_PLAN 4.4, G3_TODO), which the owner
added to the session's goal that day. It proposes; the code follows its review
by `clima-numerics-reviewer` (xhigh). `file:line` references are to
`claude/water-tags-edmf-wp5` at `fd07d902`, which contains #100, #101 and WP5.

## 1. The problem

Under 0M microphysics the only sink of total water is the rain-out,
`dq_tot_dt ≤ 0` per subdomain. Under prognostic EDMF the model computes it per
subdomain and adds both to the grid mean (`microphysics/tendency.jl:101-133`):

    Δ⁰ = ρa⁰ · dq_tot_dt⁰,    Δʲ = ρaʲ · dq_tot_dtʲ,    Yₜ.c.ρq_tot += Δ⁰ + Σⱼ Δʲ.

The tags take that increment through the `:microphysics` bracket
(`attribute_tagged_ρq_tot!`), which sees only the sum `Δ` and hands the loss out
by the **grid mean's** share `φ̄ᵢ` (`tagged_water.jl:356-396`). The updraft,
where most of the rain forms on a deep case, holds a different composition:
its water entrained low down. So the grid tags lose the wrong mix. Under
copies it is worse (the WP3 review, N6): the copies lose by their own share
(`_copies_rain_out!`), the grid tags by `φ̄`, and the environment's implied
tag values, `(ρq_tagᵢ − ρaʲχᵢʲ)/(ρa⁰)`, can move the wrong way.

## 2. The split

**The rule (G3_PLAN 4.4).** Production `Σₖ max(Δᵏ, 0)` by mask; loss
`Σₖ min(Δᵏ, 0) φᵏᵢ`, over the updraft `j` and the environment `0`, with `Δᵏ`
exactly as the model weights them (`ρa⁰` from `ρa⁰(Y.c.ρ, Y.c.sgsʲs, …)`, not a
remainder). Under 0M `dq_tot_dt ≤ 0` after limiting, so production is zero, and
the rule reduces to the loss. Where each subdomain's shares sum to one over the
partition, the partition's loss sums to `Δ` in every cell, so closure is as
today.

**The shares.**

| mode | updraft `φʲᵢ` | environment `φ⁰ᵢ` |
|:---- |:------------- |:----------------- |
| default | the plume's share after the exchange's bound: `φ̄ᵢ + Δφʲᵢ`, from `ShareDifferences(flags, false)` (`tagged_water_edmf.jl:299-307`) | `φ̄ᵢ + Δφ⁰ᵢ`, from `ShareDifferences(flags, true)` |
| copies | the copies' clamped share `clamp(χᵢʲ/q_totʲ, 0, 1)`, the one `_copies_rain_out!` already uses | the environment's implied share `(ρq_tagᵢ − ρaʲχᵢʲ)/(ρq_tot − ρaʲq_totʲ)`, clamped to [0, 1] and renormalized over the partition |

So in copies mode one rule serves the copies and the grid tags: the grid tags
lose `Δʲφʲᵢ + Δ⁰φ⁰ᵢ`, and each copy loses `dq_tot_dtʲ·φʲᵢ`, the same updraft
share; the environment's implied values then change by `Δ⁰φ⁰ᵢ`, in the right
direction. A source tag takes its own clamped share, unnormalized, as
everywhere else.

**Where the shares come from.** The default mode's plume and its bound are
computed by `water_exchange_inputs!` (`tagged_water_edmf.jl:336-400`) inside
`sgs_mass_flux_of_water_tags!`, in the implicit tendency *after* the
microphysics bracket (`implicit_tendency.jl:41-65` against `:97`), and not at
all in the explicit tendency. Two ways:

  - **(a) compute them in the bracket:** call `water_exchange_inputs!` from the
    split's attribution. One more plume per tendency evaluation on the
    implicit path, and one per explicit evaluation on the explicit path. The
    plume is a column accumulation over the tags (`column_accumulate!`), of
    the order of the exchange itself.
  - **(b) defer the attribution:** the bracket stores `Δʲ`, `Δ⁰` in scratch,
    and the attribution runs after the exchange, reading its scratch. Cheaper
    on the implicit path, but it separates the bracket's two halves, which
    `open_applied_update!` forbids for the other consumers, and the explicit
    path would still need (a).

Proposed: **(a)**, one code path for both, with its cost measured in V-W10.

**Dual numbers.** Under an autodiff Jacobian the implicit tendency runs on
dual numbers, so every field the split writes is in `p.scratch`, as the
exchange's are (`water_tag_edmf_scratch`, `tagged_water_edmf.jl:96-130`).

## 3. `pr_tag` under 0M

Under 0M the surface precipitation is the column integral of `ᶜρ_dq_tot_dt`,
split into rain and snow by the grid mean's temperature
(`set_precipitation_surface_fluxes!`, `microphysics_cache.jl:1269-1293`). So
`pr_tag_<name>` is the column integral of the tag's loss, split the same way,
with the same sign as `pr`. Over the partition it sums to `pr` in every column,
to rounding, where the shares sum to one; the test checks that. It is a
diagnostic computed from the state at output time, reading the same cached
tendencies; it adds no state.

## 4. Known issue 4: a switch for the analytic diagonal

Known issue 4 (`docs/known_issues.md`): the tags' loss `min(Δ, 0) ρq_tagᵢ/ρq_tot`
on the implicit path has the diagonal `∂/∂ρq_tagᵢ = Δ⁻/ρq_tot`, of order
`1/dt`, and no Jacobian entry supplies it. W15 and W16 did not isolate whether
that changes the answer after a fixed number of iterations.

**The switch.** An experimental key, `water_tag_rainout_jacobian: true`
(default `false`), adds `dtγ·Δ⁻/ρq_tot` to each tag's diagonal block where the
tag's share is inside (0, 1) and `ρq_tot > 0`, and nothing else. It is
parity-safe: the tags are split-solvable (`is_splittable_jacobian_field`), so
their rows enter no model variable's solve. With the split of section 2 the
entry becomes `Σₖ min(Δᵏ, 0) ∂φᵏᵢ/∂ρq_tagᵢ`, which for the grid share is
`Δ⁻/ρq_tot` and for the plume's share is not available in closed form; the
switch then takes the grid share's entry as an approximation, and says so.
Where the tags' blocks are the `-I` fallback (explicit diffusion), the switch
allocates diagonal blocks for them.

**Parity with the parent.** The parent's own 0M sink has no Jacobian entry
either (G3_PLAN 4.3), so with the switch on the tags converge faster than the
parent, and one Newton iteration then parts their update from the parent's.
The experiment measures both effects: the tags against a converged reference,
and the closure against the parent.

**The experiment** (the isolating one the owner asked for in the review of
#100). The raining 0M column of V-W0a (DYCOMS RF02 without EDMF, which rains
out its initial cloud in the first hour; W15, W16), implicit microphysics, 2 h:

| runs | dt | Newton | switch |
|:---- |:-- |:------ |:------ |
| the reference | 30 s | 20, `newton_rtol` 1e-10 | off (converged, so either) |
| the Newton ladder | 120 s | 1, 2, 10 | off and on |
| the time step ladder | 120, 60, 30 s | 1 | off and on |

That is 11 runs, 10 once the shared rung is counted once. Read against the
reference, on one grid: the region tags and the source tag (L1 and L∞ of the
shares, with the verifier), `q_tag_res`, and the nonlinear convergence (the
Newton residual norms, where the stepper reports them). Known issue 4 is then
closed with a measured effect, or restated with its size.

## 5. Tests

  - **Unit:** the split's loss sums to `Δ` over the partition where the
    subdomains' shares sum to one, for random shares and signs; a source tag
    takes its own share; copies mode's rule leaves the environment's implied
    values moving by `Δ⁰φ⁰ᵢ`.
  - **Integration** (a 0M EDMF column, as the `tagging_water_edmf_0m` group):
    the partition's microphysics tendency equals the parent's to rounding;
    `Σ pr_tag = pr` per column; parity with the untagged column; the switch
    changes no model field (bit for bit) and only the tags' rows.
  - **Parity** of the explicit and the implicit microphysics paths.

## 6. Cost

One plume per tendency evaluation more on each path that brackets the 0M sink
(section 2 (a)); two tuple fields of scratch per tag set for the split's
shares; nothing for `pr_tag`, computed at output. The switch adds one
diagonal block per tag where there was the `-I` fallback.

## 7. For the owner

  - Section 2 (a) against (b).
  - The switch's approximation under the split (the grid share's derivative
    in place of the plume's).
