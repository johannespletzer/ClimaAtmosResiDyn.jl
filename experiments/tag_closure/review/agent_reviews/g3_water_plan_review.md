# Review of `G3_WATER_PLAN.md`

Independent review, 2026-09-23, of the untracked draft on `claude/g3-programme`.
Code references are to PR #95's head `dbe7435c`
(`origin/claude/energy-source-tag-updraft`) unless stated otherwise. Nothing
was run in Julia and no job was submitted. The scalar checks below were run in
Python 3.12 with numpy; the scripts are in this session's scratchpad
(`checks/g3_checks.py`, `checks/plume_sink.py`), which is not durable.

## 1. Verdict

The core is sound. The exchange with weight `q_totᵏ`, the donor-share flux,
and the copies' 0M sink rule all check out algebraically. Nothing in the
design writes a model field. But the plan is not ready to become the to-do
list. Four problems must be fixed first:
 - the copies miss the updraft's own 1M sedimentation, so the reference is
   wrong on the primary case;
 - the plume ignores the water the updraft loses, and the risk section says
   the opposite;
 - under 1M, `pr_tag_*` can only be the lowest cell's composition, so
   decision 3 cannot be delivered as written;
 - WP5 is decided by runs that cannot see what it fixes, and it comes after
   WP4.

## 2. Findings

### Blocking

**B1. The copies miss the updraft's own 1M sedimentation.**
- *Plan:* section 3 (the table has no row for it), 4.1 ("three things are not
  generic"), 4.3 ("To check: whether `updraft_sedimentation!` … changes
  `sgsʲs.q_tot`").
- *Evidence:* it does. `edmfx_sgs_vertical_advection_tendency!` adds
  `ᶜinv_ρ̂ * vtt` from `updraft_sedimentation!` to each updraft species
  (`advection.jl:440`) and to `sgsʲs.q_tot` (`advection.jl:441`). The term has
  a lateral inflow of environment condensate, `α_lat ∂a/∂z ρ⁰w⁰χ⁰`
  (`advection.jl:561`). Copies are generic SGS tracers and get none of it.
- *Consequence:* D4-W, RICO, BOMEX and the sphere are all 1M. From the first
  step, `Σᵢ χᵢʲ ≠ q_totʲ` wherever condensate falls in the updraft, which is
  the cloud layer. The copies' repair then moves that error into the copies at
  every step. V-W3's reference is wrong where it matters most.
- *Change:* add a fourth non-generic term to WP3, not WP4. Mirror
  `updraft_sedimentation!` onto each copy. The falling updraft condensate
  carries the copies' shares, and the lateral inflow the environment's. The
  term is linear in `χ` and in `ρ⁰w⁰χ⁰`, so the copies sum to the parent's
  exactly. It needs the composition assumption of 4.3. So section 1 must say
  that under 1M the copies are a reference *given* that assumption. Give the
  mirror a Jacobian diagonal, or state that it lags. Remove the "to check".

**B2. The plume ignores water the updraft gains or loses other than by
entrainment. The risk section asserts the opposite.**
- *Plan:* 4.1, 4.3, and section 8: "Proportional sinks leave the shares
  unchanged, so the 0M sink does not break it."
- *Evidence:* `_plume_step` (`energy_source_tags.jl:1967`) marches specific
  tag contents, `εʲ + w (ε̄ − εʲ)`, up from the grid mean. Nothing removes
  water from `εʲ`. The real updraft loses water to the 0M sink
  (`tendency.jl:123`) and to 1M sedimentation (`advection.jl:441`). It gains
  the surface excess at level 1. A proportional sink leaves the shares
  unchanged at the level where it acts. But it lowers the weight of the
  carried water against the entrained water in every later mixing step.
  - Toy plume (`plume_sink.py`): 30 levels, 15% of the updraft's water rained
    out per level above level 8. The boundary-layer share at level 20 is 0.43
    with the sink and 0.69 without it. At the top it is 0.19 against 0.62.
- *Consequence:* in precipitating deep convection the default's updraft
  shares are biased toward low-level water. That bias feeds the exchange, the
  0M precipitation split (4.3), and ψ. It affects TRMM (criterion 8) and
  precipitation provenance (criterion 7). The plan would find it at V-W6,
  after the whole ladder.
- *Change:* at each level of the water plume, rescale the specific contents
  to the model's own `sgsʲs.q_tot` before the next mixing step. The shares
  are unchanged and the mixing weights become right. This is exact for
  proportional sinks and cheap. Start the plume at level 1 with the same
  composition rule the copies' boundary uses (S2). Test it in WP3 against the
  copies on a deep precipitating column (S16), not first at V-W6. Correct the
  risk statement.

**B3. Under 1M, surface precipitation by tag is the lowest cell's total-water
composition.**
- *Plan:* section 0 decision 3, criterion 7, 4.3.
- *Evidence:* `sediment_water_tags!` puts the donor cell's total-water share
  inside `ᶠtop_bias` at every face (`tagged_water.jl:579`). `ᶜprecipdivᵥ`
  takes the bottom face from the lowest cell. So falling water takes the
  composition of each cell it leaves, and its provenance is reset at every
  level. `pr_tag` is the surface rain flux times the share in level 1. ψ
  changes that only where the updraft holds rain at level 1, which is little.
  Under 0M the product is sound: each level's loss leaves with that level's
  composition.
- *Consequence:* in the production configuration (1M), `pr_tag_*` labels rain
  by the near-surface water, not by where it formed. WP4's 1M half barely
  changes that. Criterion 7 could be met on paper without delivering what
  decision 3 asks for.
- *Change:* before WP4, the owner chooses one of two options:
  - (a) precipitation provenance is claimed for 0M only, and under 1M
    `pr_tag` is documented as "the near-surface composition";
  - (b) rain and snow carry their own tags. This is the species-resolved
    extension that section 8 puts outside G3.

  Rewrite criterion 7 to match. Do not build ψ until the choice is made.

**B4. WP5's decision rule cannot see what it decides, and WP4 is built before
it.**
- *Plan:* 4.4, 5 (order), 6 (V-W1, V-W3).
- *Evidence:*
  - The parent's SGS water flux has Jacobian blocks. They are
    `(ρq_tot, q_totʲ)`, `(ρq_tot, ρ)` and a diagonal
    (`manual_sparse_jacobian.jl:395`, `:2136`). The donor flux, the exchange
    and, in copies mode, the model's tracer flux of `ρq_tag` have none. So
    with one Newton iteration the tags take the flux at the stage's first
    guess, while the parent takes the linearised flux at the solved state.
    That is E59's mechanism: option 1 grew by 2.8e5 J/m² an hour, with no
    plateau.
  - V-W3 compares two runs that both lag, so it cannot see the lag.
  - V-W1 measures the missing SGS transport, which WP3 removes.
  - V-W0b, the budget's baseline, has no EDMF term at all.
  - The claim that WP5 "would also remove known issue 4" is unfounded. The
    parent's 0M sink has no Jacobian block either (there is no microphysics
    block in `manual_sparse_jacobian.jl`). So parent and tags take the sink
    at the same iterate, and the partition follows it. The sink also changes
    the column's total, and that is exactly the part the follower leaves in
    place (E64).
- *Consequence:* WP5 is likely needed. The energy family's production run
  already follows the increment (`g2_v2_sphere_n2` sets
  `enthalpy_increment`). But the plan finds out only after V-W3, with WP4
  built on the tracer form and V-W3 to V-W6 to be redone. If WP5 lands after
  WP4, the follower moves the implicit mismatch by donor share. That
  overrides part of WP4's per-subdomain sedimentation composition.
- *Change:*
  - Add a 10-Newton twin to V-W3 in each mode: two jobs, E64's split.
  - Fix the rule before the runs: if the one-iteration part of the gross
    residual exceeds a quarter of the closure budget, build WP5.
  - Decide right after V-W3, and put WP5 before WP4. Or build WP5
    unconditionally.
  - Drop the known-issue-4 claim.
  - State that the tags' explicit vertical advection must then be skipped, as
    `advection.jl:124` does for the energy tags. Otherwise it counts twice.

### Should fix

**S1. The copies' partition repair double-counts the filter (4.1).**
`enforce_edmf_updraft_constraints!` already clamps each copy to
`[0, ρq_tag/ρa]`, and resets it to `ρq_tag/ρ` where `ρa < ϵ`
(`mass_flux_closures.jl:303-316`). Handing the parent's filter increment to
the copies on top counts the filter twice. In the reset case, the copies then
get the old updraft composition shifted, not the grid mean's. *Change:* after
the filter, repair the partition's residual `r = q_totʲ − Σᵢ χᵢʲ` over the
partition copies. Add it by share, with the `−pos` floor of
`water_tag_rescale_shift`, and log it in `q_tag_upfix_*`. Output `r` as a
diagnostic and bound it in a criterion, since it is the copies' own closure.

**S2. The copies' surface boundary rule (4.1).**
- The parent's term is a relaxation, `S (q_b − q_totʲ) / max(ρa, ρ a_min)`
  at level 1 (`edmfx_boundary_condition.jl:379`), not a value it sets.
- The target's excess, `q_b − q̄ = C√σ²`, is never negative
  (`edmfx_boundary_condition.jl:469`), even with dew. So the "deficit" clause
  never applies.
- At t = 0 the `evap` source tag is zero in the grid mean. Giving it the
  excess puts evap water in the updraft that the cell does not hold. The
  environment's evap inventory is then `−ρaʲ·excess`, which my scalar check
  reproduces.
- The plume starts at level 1 with the grid mean's composition
  (`energy_source_tags.jl:1967`). So the two modes differ by construction at
  the bottom, in `evap`, which is the tag criterion 5 depends on most.

*Change:* give each copy a relaxation target `χᵢ_b` with `Σ χᵢ_b = q_b`, and
bound it by the cell's inventory of the tag. Use the same rule for the
plume's first level. The simpler option is the grid mean's composition in
both modes, as the energy copies use. State which rule, and measure its
effect with a surface pulse (G3_TODO 4.5).

**S3. V-W2 and "copies against the passive tracer, L1 ≤ 0.1%" are ill posed
(sections 1, 2, 6, 6.1).**
- The V3 driver sets `q_gas_A` to the `tropo` mask, which is a share by air
  mass. A water tag's share moves with the water's mass flux, and the tracer
  with the air's. They differ wherever `q_tot` differs between subdomains,
  and strongly at the DYCOMS inversion.
- A tracer initialized to the tag's own field (`ρχ = ρq_tag`, `χʲ` = its
  copy) runs the same generic code as the copy. Then only the water-specific
  terms differ:
  - the boundary relaxation (`q_tot` only);
  - the 1M updraft sedimentation (B1);
  - the 1M `q_tot_eff` corrections (S4);
  - the water repair. The centred SGS flux drives tags negative at the
    inversion (E73), and the repair acts on the tags, not on the tracer.
- With those terms off, the two agree to rounding, so 0.1% tests nothing.
  With them on, any difference has a known cause.

*Change:* make V-W2 a CI test instead. Use a mass-weighted initialization,
monotone SGS upwinding and no water-specific term, and require agreement to
rounding. For an independent check of the copies, add the manufactured
source-free mixing tests of G3_TODO 4.3: sharp and smooth interfaces with
known answers, on a frozen parent. Insight E of the extended assessment asks
for the same. Check that V-W2's configuration is possible in WP0, not WP3.

**S4. The 1M `q_tot_eff` mismatch has more paths than 4.2 covers, and 4.2's
sign is wrong (sections 3, 4.2).**
- Under 1M the parent acts on `q_tot − q_rai − q_sno`, and the tags and
  copies act on their own values, in four more places:
  - grid-scale hyperdiffusion (`hyperdiffusion.jl:496` against `:548`);
  - the viscous sponge (`viscous_sponge.jl:197` against `:228`);
  - the updraft's hyperdiffusion (`hyperdiffusion.jl:555` against `:618`);
  - the updraft's vertical-diffusion mirror (`edmfx_sgs_flux.jl:330` against
    `:415`), which is active whenever `edmfx_vertical_diffusion: true`.
- The sphere of criterion 11 has all four. So `tagged_water.md` is wrong
  under 1M when it says the tags use the same diffusion and hyperdiffusion
  operators as `ρq_tot`.
- In 4.2, adding `+∇·(ρK_h ∇(φᵢ q_p))` to the tags' tendency doubles the
  leak. A 1-D check gives `|tags − parent|` = 0.062 today, 0.125 with the
  plan's sign, and 6e-15 with a minus sign.

*Change:*
- Write the correction as `ρq_tagₜ −= ∇·(ρK_h ∇(ψᵢ q_p))`, per species, with
  the same composition as the sedimentation mirror.
- List all the paths in section 3.
- Replace V-W1's split jobs with an exact diagnostic of each path's leak. The
  leak is a closed-form function of the state.
- Decide per path, by a threshold set in advance.
- Apply the same correction to the copies' mirrors.

**S5. The copies need the same updraft upwinding as `q_tot` (4.1, 4.6).**
`q_totʲ` is advected with `edmfx_mse_q_tot_upwinding` (`advection.jl:366`)
and the copies with `edmfx_tracer_upwinding` (`:379`). Only the first offers
`third_order`. The defaults match. *Change:* refuse copies unless the two
settings are equal.

**S6. The 0M split: production per subdomain, bounded shares, both
tendency paths (4.3).**
- `tendency.jl:109-117` weights the environment by `ρa⁰ = ρ − Σρaʲ` and each
  updraft by `ρaʲ`. So `Δ = Δ⁰ + ΣΔʲ` holds to rounding. ✓
- But if production stays `max(Δ, 0)` of the total while the losses are
  split, the tags stop summing to `Δ` whenever the parts differ in sign. That
  happens with the rounding of `Δ⁰` by subtraction, or with a negative `ρaʲ`
  at a Newton iterate.
- The environment's share from subtraction is non-negative only with the
  bounded (θ-blended) plume shares.
- The plume must exist before `vertical_advection_of_water_tendency!`
  (`implicit_tendency.jl:340`, inside the first call at `:39`) and before the
  microphysics bracket (`:66`). Both run before the SGS flux (`:118`).
- The explicit microphysics path (`remaining_tendency.jl:233`) needs the same
  split.

*Change:* give production as `Σₖ max(Δᵏ, 0)` by mask, and losses as
`Σₖ min(Δᵏ, 0) φᵏ`. Use the exchange's bounded shares. Compute the plume at
the top of `implicit_tendency!`. Split both paths, or refuse
`implicit_microphysics: false`.

**S7. The 1M composition ψ: its weighting, bounds and Jacobian (4.3; only if
B3 keeps it).**
- The model splits the sedimentation flux by subdomain as `ρʲaʲwʲqʲ` and the
  residual (`water_advection.jl:170-190`). ψ weights by mass, `ρaʲqₛʲ`, which
  differs where updraft rain falls faster. With `wʲ = 2w̄`, my check gives
  (0.54, 0.46) mass-weighted against (0.78, 0.22) flux-weighted.
- At a Newton iterate `ρaʲqₛʲ` can exceed `ρqₛ`, because the filter only
  acts on the accepted state. The check then gives ψ = (1.2, −0.2).
- The tags' sedimentation diagonal is the derivative of the cell share
  (`manual_sparse_jacobian.jl:1290`). With ψ that derivative changes, and
  sedimentation is the stiffest term: the rain Courant number is about
  `w_r Δt/Δz ≈ 12` on D4.
- Inside the species loop, `ᶜq`, `vtt` and `ᶜtemp_scalar_3` are live
  (`water_advection.jl:63-98`). Writing any of them would change `ρe_tot`.

*Change:* weight ψ by the model's own flux split. Clamp and renormalise it.
Update the diagonal to `∂ψᵢ/∂ρq_tag,i`, keeping it diagonal so the tags stay
split-solvable. Use only scratch the tags own.

**S8. Budgets that cannot be met, or that invite retuning (criteria 4, 5,
11; 6.1).**
- *Closure, 10× V-W0b.* V-W0b is DYCOMS with `turbconv: ~`: no EDMF term, no
  updraft, and probably no turbulent mixing. Its residual comes from the
  advection split, near W5's 1e-7. The EDMF column's residual will contain
  the SGS-flux lag and the leaks, so the ratio is arbitrary. Tie the budget
  to criterion 5 instead. A gross residual `R` moves the shares by about
  `R/ρq_tot`, so set `R` at a stated fraction of the per-tag L1 budget.
  Alternatively, tie it to the 10-Newton twin (B4).
- *First-hour budget, 10% and 25%.* At 1 h, default against copies measures
  the copies' spin-up from the grid mean against a plume that is steady from
  the start (E73: 16% for `sfc`). Initialize the copies from the plume at
  t = 0, or report the first hour without a pass or fail.
- *Tags that start at zero.* For `evap`, a relative L1 is unstable early.
  Report absolute errors where the reference is small (G3_TODO 4.8).
- *The sphere.* Criterion 11 cites criterion 4, which is a column ratio. Set
  a sphere budget before V-W11.
- *Q5 is still open* in G3_TODO. The proposed 2% and 5% are E73's energy
  numbers, which the pathway calls "historical case-specific criteria".

**S9. Criterion 6 dropped the reference's own convergence.** The old G3
criterion 4 required each column's reference to converge in time step, grid
and Newton count. Criterion 6 only asks that the default's error against the
copies converge. If the copies move by more than the budget between dt 120
and dt 30, the error at dt 120 is measured against an unconverged reference.
*Change:* add the copies' own convergence to criterion 6.

**S10. D4-W inherits `edmfx_vertical_diffusion: false`.** D4 set it false
because the tags had no updraft field (see the header of
`d4_column_edmf.yml`). The B4 guard (`edmfx_sgs_flux.jl:401-418`) now handles
that. Every shipped EDMF column, the held-out cases and the sphere set it
true. With false, the copies' diffusion mirror and its 1M mismatch (S4) are
first exercised at V-W6. *Change:* set it true in D4-W, or add a rung for it.

**S11. The process-closure identity needs `evap_strat`, and will not be
exact.** D4-W lists `evap` and `evap_tropo`. The identity is
`evap_tropo + evap_strat = evap`. Under decision 5 each source tag has its
own bound factor, which is not linear. So the identity breaks wherever the
factors differ. In copies mode, the filter's per-copy clamp breaks it where
the clamp binds. *Change:* add `evap_strat`, and log bound activation per
source tag. State the expected violations, so that one is not read as a bug.

**S12. WP1 should not refuse `water_process_record`.** The records are
"prognostic but not transported" (header of `process_record.jl`). EDMF's SGS
flux and AMD's diffusion do not touch them. Refusing them removes a working
diagnostic and creates churn when the refusal is lifted. *Change:* refuse
`water_tracers` only.

**S13. How copies are initialized and rebuilt.** `_rebuild_updraft_copies!`
sets a copy to the tag's grid-mean value over `ρ`
(`energy_source_tags.jl:798-805`), and WP2 lists it as family-agnostic. For
water, the sum of those values is `q̄`, not `q_totʲ`, after a file-based
rewrite or a restart that adds copies. *Change:* rebuild water copies as
`q_totʲ φ̄ᵢ`, in both the rebuild and the file-based path (V-W8).

**S14. Gaps in the criteria for "operational in production" (section 2).**
None of these is covered yet:
- *GPU.* G3_TODO leaves the GPU out. Say so in section 2, or add a smoke test
  of the plume's `column_accumulate!` over tuples.
- *MPI parity.* Bit-for-bit parity holds only at one process count. Add a
  two-rank column, or a short sphere pair on the same nodes.
- *Restart on the sphere.* Production ten-day runs checkpoint daily.
- *Parity on a 0M EDMF column and with explicit microphysics.* These are
  different code paths.
- *The copies' own residual* (S1).
- *`Σ pr_tag = pr`.*
- *Refusal tests* for `updraft_number > 1` and for a default exchange without
  a region partition. Energy has `check_energy_source_exchange_partition`.

**S15. WP2 before WP3 refactors code that the water design must change.**
- The water plume needs the rescale to `q_totʲ` (B2) and a boundary start
  (S2), which the energy plume does not have.
- The rebuild differs (S13).
- Decision 5 is not in the code yet: `dbe7435c` still sets one θ from every
  tag.
- So refactoring first means refactoring twice.
- The bitwise reference for the energy tags must be a run of merged `main`
  with decision 5, not E73's outputs at `846ef55d`.

*Change:* build WP3 with water-specific helpers first. After V-W3, move into
shared code only what is identical: `ShareDifferences` with a weight
argument, the partition flags and the face flux. Guard the move with a CI
unit test that runs the old and new helpers side by side on random inputs,
bit for bit.

**S16. The development case does not exercise the hardest parts.** D4-W is a
drizzling stratocumulus with weak updrafts and 1M microphysics. It has no 0M
sink and little rain in the updraft. So the plume's sink handling (B2) and
the 0M split are first exercised on TRMM at V-W5 and V-W6. *Change:* add a
short deep 0M development case to V-W3, and keep the held-out set apart for
criterion 8.

### Notes

- **N1. Section 1's claim that the inventory is exact for water holds in
  practice.**
  - It needs the environment's `specific` blend weight to be 1
    (`variable_manipulations.jl:45-52`). That means `a⁰ > 42 a_half`, which
    is 4.2e-4 with `EDMF_min_area` = 1e-5.
  - At a Newton iterate `ρaʲq_totʲ` can exceed `ρq̄`. Then `q_tot⁰ ≤ 0`, and
    `ShareDifferences` exchanges nothing.
  - In my check, the partition sums were zero to 4e-15 and the inventory
    bound held to 2e-16. Shares went down to −3.5e-14, so non-negativity
    holds to rounding, not exactly.
- **N2. Section 3's last row is slightly off.** `rescale_water_tags!` runs
  inside `tracer_nonnegativity_constraint!`, before the filter
  (`constrain_state.jl:44-48`, `:127`). Only the repair runs after it.
- **N3. Donor share plus exchange equals the copies' flux only up to
  reconstruction.** Under first-order upwinding, the updraft term is taken
  from below, the environment's from above, and the donor share from the side
  the net flux leaves. At a front they differ by
  `M⁰ (q⁰ − q̄)(φ̄_above − φ̄_below)`. Expect this difference, and do not
  budget it away.
- **N4. The model drops the updraft's precipitation mass loss on the
  implicit path.** `sgs_ρa_implicit_tendency!` assigns the `ρa` tendency
  (`initialize_implicit_problem.jl:291`), which overwrites microphysics' `ρa`
  sink (`tendency.jl:122`). So the updraft keeps the precipitated mass, while
  `q_totʲ` still takes the `(1 − q)` dilution. The copies' rule mirrors
  `q_totʲ` and stays consistent with it. Document this.
- **N5. The copies' 0M rule sums to the parent's exactly** when the copies
  partition `q_totʲ` (checked to 3e-18). If the copies drift, the unnormalised
  `φ = χ/q` makes the drift decay. Clamp φ to `[0, 1]`.
- **N6. The copies' fluxes sum to the parent's only when both partitions
  hold,** the grid-scale one and the copies'. Source tags are outside both.
- **N7. Copies may be too costly to build at 32 tags.** Eight energy copies
  doubled the column's build time (E73: 789 s against 402 s). Thirty-two
  water copies in the nested solver may not build within `hpda2_test`.
  Measure at 2, 4 and 8 tags and extrapolate, with a time limit.
- **N8. Section 9 overstates what transfers to G4.** The plume's accuracy and
  the qualified settings depend on the weight (`q_totᵏ`, against `Aᵏ` with an
  offset) and on the sinks. At the surface the energy copies take the
  environment's composition. Pick one surface rule for both families (S2).
- **N9. V-W1's parts do not add up.** Turning the mass flux or the diffusive
  flux off changes the atmosphere.
- **N10. V-W0a measures the solve's effect on the tags and the parent
  together.** Known issue 4 is not a closure defect (B4).
- **N11. V-W8 needs ERA5 forcing.** Confirm it is already on disk. A CDS
  retrieval needs the owner's approval (`AGENTS.md`).
- **N12. Name collisions.** The copies (`q_tag_<name>`) share a namespace with
  the diagnostics `q_tag_res`, `q_tag_fix_*` and the new `q_tag_upfix_*`. A
  tag named `res` or `fix_x` would collide. Reserve these names at
  configuration.
- **N13. Two water follower details.** Its hook must compose with
  `EnergySourceIncrementCorrection` in one post-solve hook. Its stepper check
  is the energy one, which ARS222 passes (E73).

## 3. What I checked and found correct

- Section 3's rows, against `dbe7435c`:
  - the SGS mass flux lines, including the implicit call at
    `implicit_tendency.jl:118`;
  - the diffusive-flux leak and the `α` flags (`edmfx_sgs_flux.jl:391`), and
    exactness under 0M;
  - the 0M microphysics lines 101-133 and their weights;
  - the 1M microphysics no-op;
  - the sedimentation mirror is mass-exact, and EDMF corrects only the energy
    flux;
  - the updraft boundary writes only `q_tot` and `mse`;
  - the filter never writes `ρq_tot`;
  - `ρq_tot` is advected implicitly, with a post-Newton correction.
- Nothing else writes the updraft's `q_tot`: I checked the implicit `ρa`
  solve, pressure work (a no-op) and TKE.
- With the environment by subtraction, the exchange with weight `q_totᵏ` sums
  to zero and keeps the environment's shares non-negative, to rounding
  (20,000 random cases, with a partition-only θ and one θ per source tag).
- Donor flux plus exchange equals the copies' flux in the continuum (algebra).
- The copies' 0M rule sums to the parent's update. A finite-mass derivation
  agrees with it to first order in `dq dt`.
- ψ sums to one over the partition.
- With a linear reconstruction the copies' face values sum to the parent's.
  Under van Leer they do not (scalar check).
- Parity:
  - every refusal concerns the diagnostic's own keys;
  - the copies write only their own fields;
  - the design writes no model field, provided WP4 uses its own scratch (S7).
- Without Jacobian blocks, the donor flux and the exchange keep the tags
  eligible for the split solver (`manual_sparse_jacobian.jl:712`). Nested
  copies are not eligible, which costs build time but not correctness.
- The line references to `energy_source_tags.jl` and to the checkpoint's copy
  block match `dbe7435c`.

## 4. What I could not check

- No Julia run and no job, so there are no magnitudes for the SGS-flux lag,
  the 1M leaks, the boundary excess, or the updraft's share of the rain. A
  cheap analysis of existing D4 checkpoints before WP3 could size them.
- Decision 5's code, which is not committed yet.
- GPU behaviour.
- Whether a shipped column can be configured without water-specific terms
  (V-W2).
- The verifier and the manifest code.
- Whether the energy copies' parity test covers
  `ApproximateBlockArrowheadIterativeSolve` with nested copies of a second
  family.
- Wall time and memory:
  - V-W4 at 120 levels and dt 30;
  - V-W11 with water tags added to the energy tags;
  - the 32-copy build of V-W10.
