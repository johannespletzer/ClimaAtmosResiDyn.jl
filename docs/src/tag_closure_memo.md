# Tag closure memo

What is enforced, what floating-point closure would cost, and whether it is
worth it. The experiments that follow from this memo are planned in
[tag_closure_experiments.md](tag_closure_experiments.md).

Scope: `Σ tags = parent` for the water tags against `ρq_tot`, and for the
energy tags and the energy source tags against `ρe_tot`. The subject is `main`
at `a54ce31`; the parent-budget ledger of the `parent_budget` pages is context
only. Nothing was run when this memo was written. The latest `main` CI run
(34316488530, 2026-09-09) passed `tagging_water` 91/91, `tagging_energy` 24/24
and `tagging_source` 24/24 on Julia 1.11, but prints no residual or closure
value. The only relevant log lines are the water job's limiter convergence
statistics (`n_times_unconverged = 0`) and the source job's warning that
`ρe_tot` is non-positive over 100% of the domain at initialization. Every
magnitude below is therefore a test bound, a figure recorded in a test comment,
or a docs figure, and is labelled as such. No per-contributor residual has ever
been measured in this repo; the tests measure aggregates only. The default
state type is `Float32` (`default_config.yml` 144 to 146); all three
integration tests force `Float64` (`tagged_water_integration.jl` 78,
`tagged_tracers_integration.jl` 46, `energy_source_tags_integration.jl` 82).

Line numbers refer to `main` at `a54ce31`.

## Part 1. Current handling

Enforced, meaning the state is changed so the sum holds:

  - `rescale_water_tags!` scales every water tag by `ρq_tot_after / ρq_tot_before`
    after each parent correction (`tagged_water.jl` 712 to 739). It is called
    from both limiters (`limited_tendencies.jl` 109, 148), the element
    nonnegativity constraint (`constrain_state.jl` 123) and `prescribe_flow!`
    (`constrain_state.jl` 174). Exact in exact arithmetic; rounding in the
    state type.
  - `repair_water_tag_partition!` removes negative partition tags while
    preserving their sum (`tagged_water.jl` 802 to 851, wired at
    `constrain_state.jl` 45). It deliberately does not renormalize onto
    `ρq_tot` (`tagged_water.jl` 785 to 790). When negatives outweigh positives
    it zeroes the cell and the deficit lands in the residual (781 to 783).
  - The sedimentation mirror builds per-species tag fluxes from the same `q`,
    `w`, `ρ_f` and `ᶠtop_bias` as the parent, with renormalized clamped donor
    shares, so the tag fluxes sum to the parent flux to roundoff
    (`tagged_water.jl` 571 to 620, called at `water_advection.jl` 85; Jacobian
    blocks in `manual_sparse_jacobian.jl` 1008 to 1042). Asserted at `100 eps`
    on the flux (`tagged_water_integration.jl` 453 to 454).
  - The attribution brackets are exact per process when the masks sum to one
    (water `tagged_water.jl` 353 to 400; energy `tagged_tracers.jl` 688 to
    729; source `energy_source_tags.jl` 256 to 340).

Monitored only: the `q_tag_res`, `e_tag_res` and `e_src_res` diagnostics
(`default_diagnostics.jl` 686, 695, 708), and the three `*_closure_check`
callbacks (`get_callbacks.jl` 782 to 827, 846 to 893). The callbacks write a
CSV and warn when `gross_relative > tolerance` (`tagged_tracers.jl` 590 to
595) or when `nonpositive_fraction > 0` (599 to 604). Nothing errors on a
residual; the only errors are misconfiguration (`get_callbacks.jl` 860 to
870). The reductions in `tag_closure` run in the state type with no promotion
(`tagged_tracers.jl` 441 to 470).

### Water tags against `ρq_tot`

Test: DYCOMS_RF02 0M column, 30 levels, `dt` 10 s, 100 s. Sphere limiter test:
MoistBaroclinicWave, SEM limiter, `dt` 300 s, 1 h.

| Contributor                                                                                                                                                  | Class                                                                         | Magnitude (source)                                                                                                                                                   | Evidence on `main`                                                                                                                                                                               |
|:------------------------------------------------------------------------------------------------------------------------------------------------------------ |:----------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Vertical advection: parent implicit central plus the post-Newton `energy_q_tot_upwinding` (van Leer) correction; tags explicit `tracer_upwinding` (van Leer) | structural, dominant                                                          | about 1.4e-2 of the column scale on DYCOMS 1M, with or without the mirror (test comment `tagged_water_integration.jl` 394 to 399); bound 5e-3 in the 0M column (167) | `implicit_tendency.jl` 224 to 228, 354 to 359; `advection.jl` 249 to 255; defaults `default_config.yml` 330 to 335                                                                               |
| Horizontal advection                                                                                                                                         | rounding only, the same `split_divₕ` on `ρχ/ρ`                                | none measured                                                                                                                                                        | `advection.jl` 121 to 123 (`is_tracer_var` includes `ρq_tot`, `utilities.jl` 58 to 64)                                                                                                           |
| Hyperdiffusion, vertical diffusion, viscous sponge under 1M or 2M: the parent acts on `q_tot_eff = q_tot - q_rai - q_sno`, the tags on their full content    | structural, omitted by the docs (`tagged_water.md` 234 to 238 says identical) | none measured; zero under 0M                                                                                                                                         | `hyperdiffusion.jl` 152 to 159, 481 to 487, 527 to 535; `vertical_diffusion_boundary_layer.jl` 111 to 115, 151 to 154; `eddy_diffusion_closures.jl` 1017 to 1021; `viscous_sponge.jl` 190 to 199 |
| PrognosticEDMFX SGS mass flux and SGS diffusion of `ρq_tot`, no tag counterpart                                                                              | structural, documented                                                        | none measured                                                                                                                                                        | `edmfx_sgs_flux.jl` 106, 121, 326, 488                                                                                                                                                           |
| PrescribedFlow surface inflow boundary condition                                                                                                             | structural coverage gap, documented                                           | monotonic drift                                                                                                                                                      | `advection.jl` 257 to 259                                                                                                                                                                        |
| Partition repair zeroing a cell                                                                                                                              | correction-driven                                                             | 1.2e-3 residual on the `ci 1.10` sphere limiter test, bound 1e-2 (`tagged_water_integration.jl` 283 to 289); ledger `q_tag_fix_*`                                    | `tagged_water.jl` 781 to 783                                                                                                                                                                     |
| Limiter and constraint rescale                                                                                                                               | correction-driven, sum-preserving                                             | recorded in `q_tag_fix_*`                                                                                                                                            | `limited_tendencies.jl` 99, 109, 148                                                                                                                                                             |
| DSS, reductions, the rescale ratio                                                                                                                           | rounding                                                                      | the t = 0 partition is asserted below `100 eps` (119)                                                                                                                | `constrain_state.jl` 67 to 71; `tagged_tracers.jl` 441 to 470                                                                                                                                    |

### Energy tags against `ρe_tot`

Test: DryBaroclinicWave, `held_suarez`, `h_elem` 4, `z_elem` 10, `dt` 300 s,
1 h; bound 5e-3 (`tagged_tracers_integration.jl` 124). Docs: below 1% after
10 dry days (`tagged_tracers.md` 226 to 228).

| Contributor                                                                                                               | Class                                           | Magnitude                         | Evidence on `main`                                                                                                    |
|:------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------- |:--------------------------------- |:--------------------------------------------------------------------------------------------------------------------- |
| Vertical advection: parent implicit central on `h_tot` plus the post-Newton upwind correction; tags explicit on `e_tag/ρ` | structural, dominant together with the next row | aggregate only                    | `implicit_tendency.jl` 222 to 223, 351 to 353; `advection.jl` 249 to 255                                              |
| Horizontal advection: parent on `h_tot` (pressure work), tags on `e_tag/ρ`                                                | structural                                      | aggregate only                    | `advection.jl` 59 versus 121 to 123                                                                                   |
| Hyperdiffusion and vertical diffusion: parent on `s_d` plus `h_eff ∇q_tot_eff`, tags on `∇(e_tag/ρ)`                      | structural                                      | aggregate only                    | `hyperdiffusion.jl` 293 to 310 versus 527 to 535; `vertical_diffusion_boundary_layer.jl` 102 to 129 versus 151 to 154 |
| LES SGS diffusion and viscous sponge: parent on `h_tot` or `s_d`, tags on `χ`                                             | structural, omitted by the docs                 | zero in the tested configurations | `smagorinsky_lilly.jl` 167, 224 versus 170 to 173, 227 to 230; `viscous_sponge.jl` 161 to 190                         |
| PrognosticEDMFX SGS mass flux and diffusion of `ρe_tot`                                                                   | structural, documented                          | zero in the tested configurations | `edmfx_sgs_flux.jl` 77, 90, 376, 535                                                                                  |
| The implicit microphysics energy change is not bracketed for this family (`implicit_microphysics` defaults to true)       | structural, moist runs only                     | zero in the dry test              | `implicit_tendency.jl` 50 to 54; `microphysics/tendency.jl` 85; `default_config.yml` 254 to 256                       |
| `enforce_mass_energy_consistency!` writes `ρe_tot` after a limiter moves `ρq_tot`; the energy tags do not follow          | correction-driven, omitted by the docs          | zero unless a limiter fires       | `utilities.jl` 34 to 41; `limited_tendencies.jl` 111, 150; `constrain_state.jl` 125                                   |
| DSS, reductions                                                                                                           | rounding                                        | t = 0 below `100 eps` (103)       | as above                                                                                                              |

### Energy source tags against `ρe_tot`

Test: DYCOMS_RF02 0M column, `rad: DYCOMS`, `dt` 10 s, 20 s; bound 5e-2
(`energy_source_tags_integration.jl` 139).

| Contributor                                                                                                                | Class                                  | Magnitude                                  | Evidence on `main`                                                                                         |
|:-------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------- |:------------------------------------------ |:---------------------------------------------------------------------------------------------------------- |
| Every energy-tag transport row above, since the family rides the same passive-scalar path                                  | structural                             | aggregate only                             | `is_tagged_tracer_name` `tagged_tracers.jl` 779 to 782; `gs_tracer_names` `tracer_processes.jl` 118 to 121 |
| Implicit-path processes not bracketed for this family: the precipitation energy sink and implicit microphysics             | structural, documented                 | zero in the 0M, 20 s test                  | `implicit_tendency.jl` 304 to 306 calls `attribute_tagged_ρe_tot!` only                                    |
| The donor loss is not applied where `ρe_tot ≤ 0` (100% of the test domain per the CI warning); production is still applied | structural under the current reference | unmeasured; the CI log confirms the regime | `energy_source_tags.jl` 136 to 140, 194; `energy_source_tags.md` 141 to 155                                |
| No rescale and no partition repair for this family                                                                         | correction-driven, uncorrected         | tags may go negative                       | `tagged_tracers.jl` 770 to 778                                                                             |

## Part 2. What floating-point closure would require

Reading (A), bitwise, is unattainable in principle for all three families as
long as the parent and the tags pass through any operator that is not both
linear and evaluated once on the sum. `Σᵢ F(χᵢ) === F(Σᵢ χᵢ)` fails for the
van Leer limiter even in exact arithmetic. For a linear operator it fails
bitwise because floating-point addition is not associative, and `sum(Field)`
and DSS reduce in an order the tags do not control. (A) is reachable only by
definition: a remainder tag, or an end-of-step projection onto the parent.
Both cost nothing in state, one field or none, and both destroy the residual
as a detector. The repair docstring (`tagged_water.jl` 785 to 790) and the
parent-budget contract's rule that no residual may be inserted as a balancing
entry already reject this.

Reading (B), arithmetic level, per family:

  - Water. (i) Move the tags into the implicit solve: add central
    `vertical_transport` of each tag to `implicit_vertical_advection_tendency!`,
    write each tag in `correct_implicit_advection_tendency!`, and give each tag
    a `(tag, tag)` tridiagonal block and a `(tag, u₃)` bidiagonal block in
    `ManualSparseJacobian`, following the `ρq_tot` pattern
    (`manual_sparse_jacobian.jl` 167 to 181). The cost is one tridiagonal and
    one bidiagonal block per tag, a larger Newton system and more GPU kernels
    per stage. The state and restarts are unchanged. The tag trajectories
    change and the parent does not, so the two Buildkite tagged jobs
    (`full_pipeline.yml` 675 to 693) change output, but neither is
    reproducibility-tracked, so no `ref_counter` bump. Even then the van Leer
    correction is nonlinear in the tag, so the residual is bounded by the
    limiter nonlinearity and not by rounding. (B) needs a linear
    `energy_q_tot_upwinding` (`none` or `first_order`), which changes the
    parent and does bump `ref_counter`. (ii) Under 1M, run the tags'
    hyperdiffusion, diffusion and sponge on a share of `q_tot_eff`. That needs
    phase information the tags do not carry; the honest alternative is to
    document the gap. (iii) PrescribedFlow: bracket the boundary condition as
    a source, a mask-weighted production in the bottom cell. Small, with no
    Jacobian impact; this is a coverage gap, not an operator disagreement.
    (iv) EDMFX: updraft counterparts per tag, meaning new SGS fields,
    entrainment, SGS flux and Jacobian coupling. Disproportionate. (v) The
    repair zeroing: only a projection removes it, see (A).
  - Energy. The parent is transported as enthalpy and diffused on `s_d` and
    `h_eff ∇q_tot_eff`. The tags would have to run the same sequence:
    horizontal `split_divₕ(ρu, h_tot·φ)`, implicit central `h_tot·φ` plus the
    post-Newton correction, hyperdiffusion and vertical diffusion of `s_d·φ`
    and `h_eff·φ ∇q_tot_eff`, LES SGS, sponge, EDMFX fluxes, the
    `enforce_mass_energy_consistency!` increment and the implicit microphysics
    bracket, all weighted by the share `φ = e_tag / e_tot`. Attributing the
    parent's transport increment instead is the double counting the design
    avoids (`tagged_tracers.md` 190 to 194). Every share-weighted operator is
    nonlinear in the tag, so each tag needs `(tag, tag)`, `(tag, u₃)`,
    `(tag, ρe_tot)`, `(tag, ρq_tot)` and `(tag, ρ)` blocks. The share is
    undefined wherever `e_tot ≤ 0`, which the CI warning shows is the whole
    DYCOMS test domain. This is a rewrite into a fractional decomposition, not
    a change set. Output changes, and `ref_counter` bumps if any parent
    operator is touched.
  - Energy source. Everything in the energy item, plus brackets on the
    implicit path: call the source-family snapshot and attribute around
    `vertical_advection_of_water_tendency!` and the implicit microphysics
    block. That is safe because `Yₜ` is zeroed per evaluation, but the donor
    share depends on the tag, so the `-I` fallback block is no longer exact,
    unlike the mask-only energy tags noted at `implicit_tendency.jl` 301 to
    303. (B) is unattainable under the current energy reference because the
    loss half is not evaluated where `e_tot ≤ 0`. A positive reference, or a
    reference-safe share, is a precondition and not a closure change.

`Float32` versus `Float64`. None of the above changes with the state type;
what changes is the floor. With the default `Float32`, `100 eps` is 1.2e-5
and `tag_closure` reduces in `Float32`, so its `gross_relative` floor grows
with the cell count. The parent-budget contract handles this by accounting in
`Float64` with conversion before the reduction; the tag check does not. That
is the one place the contract bears on tag closure mechanically. The other is
its tolerance shape, `τ = a + r·S + κ·ε_acc·Σ|magnitudes|` with a calibrated
`κ`, which is the right replacement for the flat relative tolerances of 1e-10
and 1e-6 in `tracer_configuration.md` 293 to 301. The contract itself
excludes provenance, so it makes no claim about the tags.

## Part 3. Is it worth it

Closure serves two purposes: the attribution reading, in which each tag is a
share of the parent, and the detection of missing coverage. Option 1, a
monitored residual with a contract-style tolerance, keeps both. Option 2,
closing the dominant structural contributor, buys a smaller residual at the
price of Jacobian coupling per tag and does not reach (B) with the default
limiter. Option 3, full floating-point closure, reaches (B) only by making the
tags a fractional decomposition of the parent, at which point the residual
measures nothing.

  - Water: option 1, with two cheap additions. Bracket the PrescribedFlow
    inflow, and document the 1M `q_tot_eff` mismatch. The measured budget is
    1.2e-3 (limiter sphere, `ci 1.10`) and about 1.4e-2 (DYCOMS 1M column)
    against `100 eps` at t = 0, so the residual is three to four orders above
    the rounding floor and useful. Confidence: high. The experiment that would
    change this: run the 0M column at `dt` = 10, 5 and 2.5 s and record
    `max|q_tag_res|` minus the `q_tag_fix` ledger. If it scales with `dt`, the
    split is a time-discretization error that implicit tags would remove, and
    option 2 becomes worth its Jacobian cost. If it does not, the limiter
    nonlinearity dominates and option 2 buys nothing.
  - Energy: option 1 only. The residual is by design the sum of every operator
    the parent receives as enthalpy, and the only way to close it is the
    double counting the design rejects. Confidence: high. The experiment: a
    10-day moist baroclinic wave with `energy_closure_check` every 6 h, with
    hyperdiffusion and then vertical diffusion switched off one at a time. If
    one operator carries most of `gross_relative` and it is linear in `e_tot`,
    mirroring that single operator by share could be reconsidered.
  - Energy source: option 1, but closure is not the binding problem. First add
    the implicit-path brackets, which are small and the only structural gap
    that is a coverage gap. Then settle the energy reference: until
    `e_tot > 0` holds on a real configuration the donor rule is not running,
    and no tolerance makes the residual meaningful. Confidence: medium, because
    the family's future is itself open (`energy_source_tags.md` 136 to 139).
    The experiment: rerun the DYCOMS source configuration with a reference
    shift that makes `ρe_tot > 0` everywhere, and check that `e_src_res` stays
    bounded and every `e_src_*` stays non-negative over a day. Failure argues
    for dropping the family in favor of water tags plus the energy process
    record, which makes its closure moot.
