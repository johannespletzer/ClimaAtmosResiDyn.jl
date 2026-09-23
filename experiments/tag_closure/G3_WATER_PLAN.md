# G3 plan: water tags under EDMF

Drafted on 2026-09-23 for the owner. An independent agent reviews it before it
becomes G3's to-do list (see "Review"). Nothing in it has been run.

## 0. Decisions this plan rests on

The owner decided on 2026-09-23:

 1. **G3 is the water tags under EDMF. G4 is the energy source tags**, and
    uses what G3 learns (section 9).
 2. The water tags are to become **operational in the production
    configuration**: a sphere with prognostic EDMF and 1M. So EDMF support is a
    correctness requirement for this family, not an extension. On the roadmap
    it moves out of M8 into M1 to M5.
 3. **Precipitation provenance is in scope.** The sink that microphysics takes
    from each subdomain is attributed by that subdomain's shares.
 4. **The exchange is the default, and updraft copies are the audit**, behind
    one switch, as for the energy tags in #95. Measuring the exchange against
    the copies confirms the choice.
 5. **The bound takes its factor from the partition only**, and each source
    tag gets its own. This applies to both families.
 6. **This session runs G3's jobs.** A separate session runs the energy jobs.

The plan assumes **PR #95 is merged into `main`**, with the energy-weighted
blend of `dbe7435c` and the partition-only factor of decision 5. Code
references are to #95's head, `dbe7435c`, unless stated otherwise. Where the
merged code differs, the plan follows the code.

The standing rules hold:
- model fields stay bit for bit (parity);
- model code goes into draft PRs that only the owner merges;
- every result gets a FINDINGS entry;
- thresholds are set before the runs that test them.

## 1. Why water first

The water tags share the energy tags' problem under EDMF, with fewer
confounders and with a reference that can be trusted.

 - **A true reference exists.** A water tag is a mass tracer. Its copy in the
   updraft is moved by the same generic code that moves every updraft tracer
   (`sgs_tracer_names`, `docs/src/extending_tracers.md`). So copies that
   partition the updraft's `q_tot` are a reference for water, not only a
   comparator. The V3 passive tracer (`q_gas_A`, `q_gas_Aup`) is an
   independent check of the copies.
 - **The bookkeeping is exact.** The model defines the environment by
   subtraction, `ρa⁰χ⁰ = ρχ − Σⱼ ρaʲχʲ` (`ᶜspecific_env_value`,
   `variable_manipulations.jl:406`). So the inventory bound
   `ρaʲ q_totʲ φʲᵢ ≤ ρ q̄_tot φ̄ᵢ` holds exactly for water. For energy,
   `Σₖ ρaᵏAᵏ ≠ ρĀ` leaves a small mismatch.
 - **Fewer confounders.** No offset `c`, and no sign problem. No choice
   between the tracer and enthalpy forms, and no pressure work. Phase changes
   conserve `q_tot`, so a total-water tag does not see them.

## 2. G3 is met when

Every *proposed* threshold is for the owner to set before the runs that test
it (section 6.1).

| # | Criterion | Milestone |
|:--|:--|:--|
| 1 | Every G3 headline number is recomputed by the verifier from runs stamped with a manifest. The verifier covers `q_tag_*` and the updraft copies. | M0 |
| 2 | Unsupported combinations are refused at configuration, with tests. Known issues 1, 3 and 4 are closed, or measured and bounded. A file-based column starts with finite water tags. A checkpoint round trip holds in both modes. | M1 |
| 3 | **Parity.** With water tags on, in both modes, every model field is bit for bit that of the run without them on the EDMF column. A CI test checks it. | M1 |
| 4 | **Closure.** On D4-W the water partition's gross residual at 24 h is within budget. Proposed: at most 10× that of the same column without EDMF (V-W0b). The second 12 h add no more than the first. What remains is split into named parts. | M2 |
| 5 | **Per-tag accuracy.** Against the copies, the default's per-tag error on D4-W is within budget. Proposed: at 24 h, L1 ≤ 2% and peak-normalised L∞ ≤ 5% for every tag; the first hour has its own budget. Where no process adds or removes water, the copies match the passive tracer within budget (proposed: L1 ≤ 0.1%). | M3, M5 |
| 6 | **Convergence.** Successive refinements of time step, grid and Newton count change the per-tag error by less than a quarter of its budget. | M3 |
| 7 | **Precipitation provenance.** The sink is split per subdomain in both modes. Surface precipitation by tag is reported with and without the split, together with its assumptions. | M5 |
| 8 | **Held-out columns.** TRMM_LBA (0M, deep), RICO (1M, precipitating shallow) and BOMEX (1M, shallow) meet criteria 4 and 5 without retuning. | M5 |
| 9 | **Float32.** A Float32 twin of D4-W meets criteria 3 and 4 within 10× the Float64 residual. | M3 |
| 10 | **Cost.** Build time, step time and peak memory are measured for 2, 8 and 32 tags in both modes, for both families. The allocation gates pass. | M4 |
| 11 | **Sphere.** Ten days of the G2 sphere with water tags under the default meet criterion 4. A one-day copies twin gives the per-tag error on the sphere. | — |
| 12 | Reviewed and tested: agent reviews with their findings fixed, CI green, and draft PRs ready. The docs are updated: `tagged_water.md`'s EDMF section, `known_issues.md`, NEWS, and a claim contract for tagged water. | M1, M2 |

## 3. What EDMF does to the water, and what the tags miss today

From a read-only inventory of #95's head on 2026-09-23, checked by this session
where marked ✓.

| Path | What it does to water | The tags today |
|:--|:--|:--|
| SGS mass flux, `edmfx_sgs_mass_flux_tendency!` (`edmfx_sgs_flux.jl:28-175`) | Moves `ρq_tot` and `ρ` by the updraft's and the environment's flux. Always in the implicit tendency (`implicit_tendency.jl:118`). Jacobian blocks only for the microphysics species and `(ρq_tot, ρ)` | **Nothing.** Tags have no updraft field, so the loop over `sgs_tracer_names` never sees them. The unguarded caveat of `tagged_water.md` |
| SGS diffusive flux (`:213-427`) ✓ | `ρq_tot` takes `K_h` on `q_tot_eff` (no rain or snow under 1M, `eddy_diffusion_closures.jl:934`) and `K_e` in the tracer loop (`α = 0`, since `ρq_tot` is in `microphysics_tracer_names`) | **A leak under 1M.** Each tag takes `(K_h + K_e)` on its whole value (`α = 1`). Summed over the tags, that is `K_h ∇(q_rai + q_sno)` more than the parent. Under 0M it is exact. The updraft mirror is skipped (the B4 guard, `:404-418`) |
| Updraft advection, entrainment, filter, hyperdiffusion, sponge | Move `sgsʲs.q_tot`. The filter `enforce_edmf_updraft_constraints!` bounds `ρaʲχʲ ≤ ρχ` per tracer and never writes `ρq_tot` | Nothing to follow. All of it would apply to copies automatically |
| Microphysics, 0M (`microphysics/tendency.jl:101-133`) ✓ | The environment's and each updraft's `dq_tot_dt` both reach `ρq_tot`. Each updraft's `ρa`, `q_tot` and `mse` also change | **Mass exact, composition approximate.** The bracket sees the net `Δρq_tot` and takes the loss by the cell's average share |
| Microphysics, 1M | Moves water between species only, never `ρq_tot` | Correctly a no-op |
| Sedimentation, 1M (`water_advection.jl:41-218`) | The grid-mean flux of each species moves `ρq_tot`. EDMF corrects only the energy flux, not the mass flux | **Mass exact** (`sediment_water_tags!` mirrors the grid-mean flux). The composition of the falling water is the cell's average |
| Updraft surface boundary (`edmfx_boundary_condition.jl:337-384`) | Writes only `sgsʲs.q_tot` and `mse`: the surface's buoyant air in the lowest updraft level | Nothing to follow at grid scale. **Copies need a tag-consistent boundary value** |
| Surface flux, forcings, subsidence, sponge | Grid-mean writers, bracketed as before | Followed |
| Vertical advection of `ρq_tot` (`implicit_tendency.jl:252, 395`) | Implicit, with a post-Newton upwind correction | Explicit for the tags: the documented source of drift |
| `rescale_water_tags!`, `repair_water_tag_partition!` | Run in `constrain_state!` after the EDMF filter | Unaffected by the filter, which never writes `ρq_tot` |

## 4. Technical design

### 4.1 One switch, two modes

A new key, `water_tag_updraft_copy` (default `false`), as `energy_source_tag_updraft_copy` in #95.

**Default: the exchange.** The tags stay grid-scale. In the implicit tendency,
right after the parent's SGS mass flux, each tag takes two terms:
 - **a donor-share SGS mass flux:** its share of the parent's `ρq_tot` SGS flux
   at each face, taken from the cell the flux leaves. This is the water analogue
   of `sgs_mass_flux_of_energy_source_tags!`. It rebuilds the parent's own face
   reconstruction for `ρq_tot`.
 - **the exchange:** `Xᵢ = Σₖ ρᵏaᵏ(u³ᵏ − u³)(φᵏᵢ − φ̄ᵢ) q_totᵏ`, with the
   updraft's shares from the steady plume, bounded as in #95. The weight
   `q_totᵏ` takes the place of `Aᵏ`. The environment's differences follow from
   the updraft's, so the partition's exchange sums to zero at every face.

Neither term has a Jacobian block, as for the energy tags. Under van Leer the
exchange is reconstructed first-order upwind, as in #95, so its sum over the
partition stays zero.

**Audit: copies.** Each tag gets `q_tag_<name>` in every `sgsʲs`. The generic
machinery then moves the copies: mass flux, entrainment, the filter, diffusion
mirrors, hyperdiffusion and the sponge. The donor flux and the exchange do not
run. Three things are not generic and must be added:
 - **The updraft's 0M sink.** The parent updates `q_totʲ += dq (1 − q_totʲ)`.
   Each copy takes `χᵢʲ += dq (φʲᵢ − χᵢʲ)`, with `φʲᵢ = χᵢʲ / q_totʲ`. Summed
   over the tags, that is the parent's update exactly.
 - **The surface boundary value.** Where the parent sets `q_totʲ` in the
   lowest level above the grid mean's, the copies take the grid mean's
   composition. The excess `(q_totʲ − q̄_tot)⁺` is then shared by the surface
   flux's production rule: by mask, and to the tags that list `surface_flux`. A
   deficit is shared by donor share. This is the attribution rule of
   `tagged_water.md`, applied at the updraft's boundary.
 - **A partition repair for the copies.** The filter clamps each copy on its
   own, so after `constrain_state!` the copies can stop summing to `q_totʲ`.
   The parent's increment of `q_totʲ` across the filter is handed to the copies
   additively, by share, as `rescale_water_tags!` does for the grid-scale tags.
   Its signed amount goes to a ledger, `q_tag_upfix_<name>`.

With a linear face reconstruction the copies' fluxes sum to the parent's
`ρq_tot` SGS flux exactly, because the environment is defined by subtraction.
Under van Leer they do not. Copies are therefore qualified under first-order or
centred reconstruction, and under van Leer only with WP5's follower.

### 4.2 The sub-grid diffusion leak under 1M

A tag-only correction. After the generic loop, each water tag also gets
`+∇·(ρK_h ∇(φᵢ (q_rai + q_sno)))`, with `φᵢ` its donor share. That removes the
`K_h` diffusion of its precipitation share, which the parent does not diffuse.
Summed over the partition, the tags then take exactly the parent's diffusion.
The generic loop, which is shared model code, is not touched. It lands only if
V-W1 shows the leak above 1% of the gross residual. W5b found it too small to
measure on a column without EDMF.

### 4.3 Precipitation provenance

**0M.** The microphysics bracket is split by subdomain. The parent's cache holds
each updraft's `dq_tot_dt` (`ᶜmp_tendencyʲs`). So `Δʲ = ρaʲ · dq_tot_dtʲ`, and
the environment takes the rest, `Δ⁰ = Δ − Σⱼ Δʲ`. Each tag loses
`Δʲ⁻ φʲᵢ + Δ⁰⁻ φ⁰ᵢ`:
 - in the default mode, `φʲ` is the plume's shares, and `φ⁰` follows from
   `ρa⁰ q_tot⁰ φ⁰ᵢ = ρ q̄_tot φ̄ᵢ − ρaʲ q_totʲ φʲᵢ`;
 - in copies mode, `φʲ` is the copies' shares.

Production (`Δ⁺`) keeps the mask rule. The plume's shares are computed once per
evaluation of the implicit tendency, into scratch, before either the exchange
or the bracket needs them.

**1M.** Only sedimentation moves `ρq_tot`, by the grid-mean flux of each
species. The tags' mirror today gives the falling water the cell's average
composition. With the split, species `s` falls with the composition
`ψₛᵢ = (ρaʲ qₛʲ φʲᵢ + (ρqₛ − ρaʲ qₛʲ) φ⁰ᵢ) / ρqₛ`: condensate in the updraft
carries the updraft's composition. `ψ` is renormalised over the partition, as
the mirror's shares are.

The assumption is that condensate carries the total-water composition of the
subdomain it sits in. That is weaker than today's "the cell is well mixed", but
it is still an assumption. Condensate that forms in the updraft and falls into
the environment keeps the updraft's composition only while it is counted in
`qₛʲ`.

To check: whether `updraft_sedimentation!` (`advection.jl:539-565`) changes
`sgsʲs.q_tot`. If it does, copies need its mirror.

**Output.** A new diagnostic, `pr_tag_<name>`: the surface precipitation rate
by tag. Under 0M it is the column integral of each tag's microphysics loss.
Under 1M it is each tag's sedimentation flux through the bottom face.

### 4.4 Following the parent's increment (conditional, WP5)

This is the G1 lesson (E59): under stiff implicit fluxes, tags that take a
share of the flux lag the parent, and the gap accumulates. The energy tags
closed it by following the parent's accepted increment
(`correct_energy_source_increment!`).

The water analogue would be an opt-in key, `water_tag_transport: increment`.
The default stays `tracer`, so existing results stay reproducible. After each
Newton solve the tags take the parent's increment of `ρq_tot`. The part that
changes a column's total stays in place, with ledgers `q_tag_inc_left` and
`q_tag_inc_moved`, and the stepper check is reused. It would also remove known
issue 4 (the implicit 0M sink without a Jacobian entry) and the implicit versus
explicit advection drift.

It is built only if V-W1 or V-W3 shows the tracer form outside criterion 4's
budget, or growing systematically. W2 found implicit water tags not worth it
without EDMF, where the residual came from the limiter. Under EDMF that has not
been measured.

### 4.5 Shared code (WP2)

The plume, the bound, the share differences, the partition flags, the exchange
flux, the donor-share face flux, the copies' rebuild and the checkpoint guard
for copies are family-agnostic. The inventory lists them in
`energy_source_tags.jl`: `ShareDifferences` (1990-2042), `_partition_total`,
`_subdomain_share`, `_energy_partition_flags`, `_plume_level` and `_plume_step`
(1955-1971), `_exchange_energy_source_tags!` (1902-1928),
`_sgs_energy_source_tag_fluxes!` (2044 onward), `_rebuild_updraft_copies!`
(798-805), and `energy_source_checkpoint.jl:155-167`.

They move into `tagged_tracers/subdomain_exchange.jl` and take the weight per
subdomain as an argument: `Aᵏ` for energy, `q_totᵏ` for water. The energy tags
must stay bit for bit: their fields, not only the model's, compared with the
verifier on `v3_upd_default` and in `tagging_source_updraft`.

### 4.6 Refusals

- **WP1, now:** refuse `water_tracers` and `water_process_record` with
  `prognostic_edmfx` until WP3 lands. Refuse them with the AMD LES model at
  all times. Warn under `PrescribedFlow` (surface inflow untagged).
- **After WP3:** allow `prognostic_edmfx` with one updraft. Refuse
  `updraft_number > 1`, as for energy, where the parent errors anyway under
  1M. Refuse copies without prognostic EDMF.

Every refusal concerns only the diagnostic's own keys, so parity holds.

### 4.7 Restart

The copies are part of the state. The restart guard checks them as in #95
(`check_energy_source_checkpoint`'s copy block, extended to the water family):
missing copies, extra copies, and a changed switch are refused. The ledgers
restart at zero, with segment metadata (WP6).

## 5. Work packages and their order

| WP | What | Kind | Depends on | Review |
|:--|:--|:--|:--|:--|
| WP0 | #95 merged with the partition-only factor (job session, owner). Phase-1 review (G3 old 1.8). The verifier extended to `q_tag_*`, copies and `pr_tag_*` | analysis | — | this session |
| WP1 | Refusals (4.6), known issue 1 closed with the post-#64 numbers from CI, issue 3 updated, tests. **Draft PR-W1** | model code, small | WP0 | Opus, high |
| WP2 | Shared helpers (4.5), energy tags bit for bit. **Draft PR-W2** | refactor | #95 merged | Opus, xhigh |
| WP3 | Water tags under EDMF: the switch, donor flux and exchange, copies with their three additions, restart guard, refusals lifted, the audit's bound-activation column for water. **Draft PR-W3** | model code | WP2 | Opus, xhigh |
| WP4 | Precipitation provenance: the 0M split, 1M composition, `pr_tag_*`. **Draft PR-W4** | model code | WP3 | Opus, xhigh |
| WP4b | The 1M diffusion correction (4.2), if V-W1 shows it matters | model code | V-W1 | with WP4 |
| WP5 | Increment follower for water (4.4), if V-W1 or V-W3 calls for it. **Draft PR-W5** | model code | WP3, decision | Opus, xhigh |
| WP6 | Gross accumulators for both families: absolute repair and fix throughput with event counts, per-step `\|m_left\|`, attempted against retained, restart segments. **Draft PR-W6** | model code | WP0 | Opus, high |
| WP7 | CI group `tagging_water_edmf` (1.10, 1.11, downgrade) and its integration file | tests | WP3 | with WP3 |
| WP8 | Docs: `tagged_water.md` EDMF section, claim contract, `known_issues.md`, NEWS | docs | WP3, WP4 | Opus, high |
| WP9 | Cost for both families (old G3 phase 5) | benchmarks | WP3 | this session |

Order: WP0 and WP1 now; WP2 as soon as #95 merges; then WP3 and WP7; then
WP4. WP5 is decided after V-W1 and V-W3. WP6 can run beside WP3. WP8 and WP9
come last, before the sphere.

**Branches.** Model code goes on branches from `main`, for example
`claude/water-tags-edmf`, with worktree `../ClimaAtmosResiDyn-wedmf` and a run
worktree `../ClimaAtmosResiDyn-wedmf-run`. Experiments, configs and analysis
go on `claude/g3-programme`.

## 6. Experiments

All runs are stamped with the manifest (G3 old 1.1) and compared with the
verifier. D4-W is D4 (DYCOMS RF02, prognostic EDMF, one updraft, 1M, 30
levels, dt 120 s, one day, Float64) with the energy tags replaced by water
tags:
 - two region tags below and above 750 m (`tropo`, `strat`);
 - `evap` (`surface_flux`), and `evap_tropo`, the evaporation below;
 - the passive tracer of V3 with its updraft copy.

`evap_tropo` gives the process-closure identity of `tagged_water.md`.

| Run | What it decides | Jobs | Needs |
|:--|:--|:--|:--|
| V-W0a | Known issue 4: a precipitating 0M column without EDMF, 1 against 10 Newton iterations | 2 | WP0 |
| V-W0b | The baseline: D4-W's column without EDMF (`turbconv: ~`), for criterion 4's budget | 1 | WP0 |
| V-W1 | The gap today: D4-W with grid-scale tags on `main` + #95, before WP1's refusal, plus the untagged twin. Then with the mass flux or the diffusive flux off, to split the gap | 4 | WP0 |
| V-W2 | Copies against the passive tracer, where no process adds or removes water. The case is chosen in WP3: a column with its surface moisture flux and sink off, if the configuration allows it | 2 | WP3 |
| V-W3 | D4-W: the default against the copies on the same atmosphere, 1 to 24 h. Bound activation | 2 | WP3 |
| V-W4 | The ladder, default and copies at each setting: dt 60 and 30; Newton 2, 4 and 10; 60 and 120 levels; first-order upwinding | 18 | V-W3 |
| V-W5 | Precipitation provenance: the split on and off, both modes, on D4-W and TRMM 0M | 8 | WP4 |
| V-W6 | Held out, default and copies each: TRMM_LBA 0M (6 h), RICO 1M (24 h, 100 levels), BOMEX (`bomex_column` at dt 120 s, 6 h, with the passive tracer) | 6 | V-W4 |
| V-W7 | Float32 twin of D4-W | 1 | V-W3 |
| V-W8 | A file-based column with water and energy tags on: `prognostic_edmfx_tv_era5driven_column` (0M) for 3 h | 1 | WP3 |
| V-W9 | A restart round trip on D4-W, both modes, continuous against restarted | 4 | WP3 |
| V-W10 | Cost at 2, 8 and 32 tags, both families, both modes | about 12 | WP3 |
| V-W11 | The sphere: `g2_v2_sphere_n2` with water tags, 10 days, 24 ranks (about 16.5 h and 500 GB, as E75), plus a one-day copies twin | 2 | all above |

About 60 column-scale jobs and two sphere jobs. Column runs go to
`hpda2_test` where they fit in two hours, otherwise to `hpda2_compute`.

### 6.1 Budgets, fixed before the runs

For the owner to set before V-W3 (criteria 4 to 6):
 - **closure:** gross residual at 24 h at most 10× V-W0b's, with no systematic
   growth;
 - **per tag, against the copies:** L1 ≤ 2% and L∞ ≤ 5% at 24 h, and a first-
   hour budget (proposed: L1 ≤ 10%, L∞ ≤ 25%, as G1's criterion 4a);
 - **copies against the passive tracer:** L1 ≤ 0.1%;
 - **convergence:** a quarter of the per-tag budget between refinements.

A threshold is not changed after a failure without a recorded decision and a
new validation.

## 7. Agents

Each runs with its reasoning level set by an agent definition in
`~/.claude/agents/`, once a session has loaded them. None submits jobs, pushes
or merges. Reports go to `review/agent_reviews/`.

| Task | Agent | Model, effort |
|:--|:--|:--|
| This plan's review | independent reviewer | Opus, high |
| Extend the verifier (WP0); comparison tables | `clima-analysis-builder` | Sonnet, medium |
| Review WP2, WP3, WP4, WP5 | `clima-numerics-reviewer` | Opus, xhigh |
| Review WP1, WP6, WP8 | `clima-reviewer` | Opus, high |
| Red team before the default is confirmed (after V-W6) | `clima-numerics-reviewer` | Opus, xhigh |
| Hook inventory for the claim contract | `clima-inventory-explorer` | Sonnet, medium |

## 8. Risks and open questions

 - **The tracer form may drift under stiff implicit fluxes** (E59). WP5 is the
   answer, gated on V-W1 and V-W3.
 - **Copies under van Leer** do not sum to the parent's flux (4.1). They are
   qualified under a linear reconstruction.
 - **Copies cost compile time.** They sit in the nested solver, which roughly
   doubled the EDMF column's build for the energy copies. They are the audit,
   not the default.
 - **The 1M composition assumption** (4.3) cannot be checked by the copies,
   which carry total-water composition only. A species-resolved reference
   would need a tag per species. It is outside G3. The assumption is stated
   with every precipitation result.
 - **The steady plume** assumes the updraft adjusts faster than its
   composition changes. Proportional sinks leave the shares unchanged, so the
   0M sink does not break it. Sharp fronts do, and bound activation measures
   how often.
 - **V-W2 needs a case with no water source or sink.** Whether a shipped column
   can be configured that way is checked in WP3.
 - **Known issue 4** may be material under 0M with one Newton iteration. V-W0a
   decides.
 - **Two families at once.** WP2 touches energy code. Bit-for-bit tag fields
   are the guard.

## 9. G4, the energy source tags, with what G3 learns

G4 takes the energy-specific items of the former G3, with G3's results as
inputs:
 - **Carried over from G3:**
   - the qualified exchange settings (upwinding, time step, grid and Newton
     count);
   - the plume's measured accuracy;
   - the per-subdomain split, applied to energy: `precipitation`, and EDMF's
     sedimentation corrections shared by subdomain composition;
   - the follower, if WP5 generalises it;
   - the cost results and the gross accumulators.
 - **Energy-specific:**
   - the offset sweep and U8;
   - headroom (U9);
   - the sign problem;
   - the enthalpy form and pressure work;
   - the subdomain energy mismatch;
   - the residual report;
   - warnings kept apart from acceptance, and U2's calibration;
   - the D4 process budget (synergy 6);
   - the energy ladder the job session is running (R2);
   - the held-out columns;
   - the choice of default;
   - the ten-day energy sphere.

G4's criteria are the old G3's, less what G3 now covers.

## Review

*The independent review's findings and how each was handled.*
