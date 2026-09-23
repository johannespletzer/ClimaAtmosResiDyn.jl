# Review of `design/RAIN_SNOW_TAGS.md` (WP4b-D), 2026-09-24

`clima-numerics-reviewer`, effort xhigh, on the note's first draft (`988cb6d4`),
against WP3 at `4a1c91a4` and WP5 at `1addf74c`. Condensed; the reviewer's
`file:line` evidence is kept. How each point was taken is in the note's
section 14.

**Computed by the reviewer:** section 2's leak integrals from V-W3's output;
the equilibrium imprint from D4-W's `husra`, `hussn`, `rhoa`, `edt`; a 1-D toy
of the diffusion leak; the net-flow rule on 20,000 random sign cases; the
constraint rule on a constructed case; 1M gross and net flows at three states
with CloudMicrophysics 0.40.0 (`InstantaneousVerbose`, `LinearizedAverage`).

**Verdict:** three prognostic parts remains right. Stage 1 (1M, no EDMF) can
start once B1–B3 and the stage-1 parts of S2–S5, S7, S8 are in the note;
stage 2 needs B4 and B5; stage 3 needs S6. No proposal writes a model field;
the parity risks are shared scratch (S7) and the name lists (B1).

## Blocking

**B1. Names.** "R and S treated like the species" via `microphysics_tracer_names`
is unsafe: `sgs_massflux_jacobian_blocks` (`manual_sparse_jacobian.jl:402-411`)
allocates `(ρχ, χʲ)` blocks for every such name, and `available_scalar_names`
(545) and the diffusion blocks with `ρ` columns (211-255) take them in, so they
stop being split-solvable (E44b's growth returns). Left out of every list, the
prefix `ρq_rtag_` matches neither `is_water_tag_name` (`tagged_tracers.jl:1070`)
nor `is_tagged_tracer_name` (1094): R and S then get K_h vertical diffusion
(`vertical_diffusion_boundary_layer.jl:151-154`), α = 1 in the EDMF flux
(`edmfx_sgs_flux.jl:391`), hyperdiffusion (`hyperdiffusion.jl:531-544`), the
viscous sponge (`viscous_sponge.jl:224-229`), the horizontal EDMF flux,
independent SEM and borrowing limiting (`limited_tendencies.jl:28, 99, 134`), a
passive K_h Jacobian block (`manual_sparse_jacobian.jl:1563-1575`), no split.
Reusing `is_water_tag_name` is wrong too: `sedimenting_water_tag_names`
(`tagged_water.jl:632`) gives the share block, WP5's skip removes their
explicit advection. Fix: a predicate table (N, R, S, Nʲ, Rʲ, Sʲ), a new
predicate in `is_tagged_tracer_name` but not in `microphysics_tracer_names` or
the candidate lists, explicit exclusions at each site, α = 0 and the K_e-only
block (1535-1553) for R and S. Test: a twin where one R holds all of `ρq_rai`,
every operator's tendency equal to `ρq_rai`'s.

**B2. Constraints (rows 15-17).** "A common factor per compartment" is 0/0
without rain, gives new rain R's own composition on increases although the
donor at fixed `q_tot` is vapour (N_i → −0.499 on a constructed case; the
net-flow form keeps +5e-4), multiplies any closure error by the factor (issue
#64's mechanism, removed in favour of additive shifts,
`tagged_water.jl:725-731, 781-797`), and omits `limiters_func!`
(`limited_tendencies.jl:74-154`). Fix: the net-flow rule additively at fixed
`q_tot`, floors of `water_tag_rescale_shift`'s kind, snapshots in the tags'
own scratch.

**B3. Denominators.** Every share divides by `ρq_tot`: `water_tag_fraction`
(`tagged_water.jl:280`) in the bracket loss (369-387), sedimentation (446,
461), the share norm (540), the Jacobian derivative (476-486), the rescale
(797); WP3's plume rescaled to `q_totʲ` and exchange weights `q_totᵏ`
(`tagged_water_edmf.jl:268-299, 413-460, 535-560`); WP5's mismatch against
`ρq_tot` (WP5 198-201). Renamed alone, loss shares sum to `q_tot_eff/q_tot < 1`
and closure fails silently. Fix: each site with its new denominator, a guard
for `q_tot_eff ≤ 0`.

**B4 (stage 2). Three followers.** `ρq_rai` is advected explicitly
(`advection.jl:253-262`), `ρq_tot` implicitly (`implicit_tendency.jl:263-269`).
N following `Δ_imp(ρq_tot − ρq_rai − ρq_sno)` with R keeping its explicit
advection counts R+S's explicit advection twice; skipping it loses it. Fix: N
skips its own and takes `−A_exp(Rᵢ) − A_exp(Sᵢ)`; N follows
`Δ_imp(ρq_tot) − Δ_imp(ρq_rai + ρq_sno)`; R, S keep `A_exp` and follow their own
implicit increments; each compartment's own denominator.

**B5 (stage 2). The EDMF default mode contradicts itself.** Row 3 (parent's
linear operator and block) against section 6 (flux split by subdomain with the
plume's composition): under the split the diagonal is `F_env/(R−Rʲ)`; `F_env =
F_grid − F_up` can be negative (different face densities,
`water_advection.jl:85-90` against 170-176; `ρaʲqʲ > ρq_rai` between filter
calls); the environment's composition is 0/0 without rain; WP3's plume is
rescaled to `q_totʲ` and entrains total water; row 13 gives R no exchange
term; the updraft's rain takes lateral inflow (`advection.jl:421-424,
554-580`). Fix: one rule; for the split, bound `F_env` to [0, F_grid], a
fallback composition, the environment's diagonal, an N plume, an R exchange
term, and call it an approximation the copies audit.

## Should fix

**S1. Section 2.** 24 h 1.07–1.14% ✓; 12 h 0.44–0.46% (0.53% is 13 h); net
1.0–1.1e-6. "Imprint at most 0.13%" is invalid: a gross residual does not bound
a component. The mechanism: `de/dt = D_{Kh+Ke}(e/ρ) + D_{Kh}(q_p)`, so `e/ρ`
settles near `c − q_p` in the mixed layer and the imprint saturates at
`∫_ML ρ|q_p − c| dz`; the source grows without bound (toy: 1.9%/day against
2e-5). On D4-W 5.0e-5 to 8.4e-5 of the column's water, largest at 3 h; at most
7.3e-4 with a whole-column mean. It scales with the rain in the mixed layer
(RWP/W ≈ 4e-4 on D4-W, ≈ 1e-2 on deep cases), so D4-W does not carry over. The
restated rule: L1 of the difference field, maximum over time, on the deep
cases; the third run bounds, does not isolate. WP5's absorption needs
`implicit_diffusion: true`; the default is Explicit (`types.jl:1907`,
`default_config.yml:412-414`).

**S2. Not every leak vanishes.** Hyperdiffusion (grid and updraft) leaks
`∇⁴q_tot_r(p)` (`hyperdiffusion.jl:151-165, 199-215`; WP3's diagnostic
includes it, `tagged_water_leaks.jl:148, 198`); exact fix `N_i ∇²(N_i/ρ − φᵢ
q_tot_r)`. The default `vanleer_limiter` advection is nonlinear, so R and S
drift: repair per compartment and residual diagnostics. Missing rows:
grid-scale advection (`advection.jl:121-127, 253-262`), `limiters_func!`,
Smagorinsky (`smagorinsky_lilly.jl:170-177, 227-235`), constant horizontal
diffusion (`constant_horizontal_diffusion.jl:39-46`), the Rayleigh sponge on
updraft species (`remaining_tendency.jl:149-161`), updraft advection
(`advection.jl:130-144, 373-382`), DSS.

**S3. The audit.** The model's tendency is a `LinearizedAverage` over `nsubs`
substeps (`BulkMicrophysicsTendencies.jl:633-715`); instantaneous rates differ
(3.2e-8 against 7.8e-8). Two-way flow is common (72% of the net at RH 97%).
Omitted processes: ice autoconversion, ice–rain accretion with rain freezing,
both arms of rain–snow collisions, the warm and cold arms of liquid–snow
accretion, accretion melt. The quadrature applies without EDMF too
(`microphysics_cache.jl:930-946`). Hourly samples cannot bound the accumulated
error. Fix: an inline diagnostic decomposing the linearized step into gross
flows (`_microphysics_source_terms`, `_linearize`), and that decomposition
weighed as an alternative to the net-flow rule.

**S4. `pr_tag`.** `pr` includes cloud liquid and ice fluxes and uses the
level-1 extrapolated `sfc_ρ` (`microphysics_cache.jl:1294-1346`);
`Σ pr_tag = pr` tests only level-1 closure; it must also match the EDMF split.

**S5. The restart guard** checks only `ρq_tag_`/`q_tag_`
(`water_tag_checkpoint.jl:78-96`): bump to version 2, record
`water_tag_precipitation`, add the prefixes, cover the three WP5 ledgers.

**S6. Copies.** Not split-solvable (`manual_sparse_jacobian.jl:712-719` needs
`c.<name>`), a build risk with 15 copies; Rʲ get a passive K_h+K_e block
(1877-1947) against a K_e-only tendency; their sedimentation block must be the
species' linear one, not 1808-1840; three repairs where one is already over
budget (W21).

**S7. Parity and scratch.** The model uses `ᶜtemp_scalar` and
`ᶜtemp_scalar_2` in `limiters_func!` and `enforce_grid_mean_microphysics_constraints!`
(`mass_flux_closures.jl:213-214`); the tags' snapshots need their own fields.
Two parent Δs and three norms suffice. Stage-1 tests: parity key off and on,
per-compartment closure, unit tests of the rule and the constraints.

**S8. Guards.** Sums exact to 9e-19 over 20,000 cases; an empty losing
compartment gives NaN and no loss 0/0; source tags need unnormalized shares.

## Minor

Citations: `water_advection.jl` has 218 lines, the EDMF block is 137-215;
`moisture_fixers.jl` 71-99; row 8's grid Jacobian is 1535-1553 (1877-1931 is
the updraft's); row 9's updraft block exists and Rʲ get K_e through the loop
(`edmfx_sgs_flux.jl:410-418`); row 7's "(default)" is wrong. The alternative
could diffuse `Tᵢ − Rᵢ − Sᵢ` and need not keep the leaks; its cost is the
(Tᵢ, Rᵢ) Jacobian coupling. G3_PLAN 4.5 says rain is hyperdiffused and sponged;
the code does neither, so the plan needs correcting. Float32 loses accuracy in
the environment's compartment by subtraction. The 1M rates are frozen within
the Newton solve (`microphysics_cache.jl:731-748`), consistent with the rule.
