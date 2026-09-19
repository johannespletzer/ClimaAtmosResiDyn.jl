# Complete energy attribution: what it means, and the path there

A research discussion for the owner of the ClimaAtmosResiDyn.jl fork. Written on
2026-09-18. Nothing here changes a repository, submits a job or builds the
model.

**What was read.**

- The experiment record in the main clone at `721efba3`, E1 to E59.
- The code and the docs page in the C1c worktree at `9aeb5205`.
- ClimaTimeSteppers 1.0.1, the version in `.buildkite/Manifest-v1.11.toml:421-425`.

**How to read the references.**

- *E*, *R*, *T* and *W* numbers are entries in
  `experiments/tag_closure/FINDINGS.md`.
- `file:line` references without a directory are in the C1c worktree.
- *CTS* means ClimaTimeSteppers 1.0.1 in the terrabyte depot.

**What this work added.** Three things were computed from files that already
exist. The scripts are in `analysis/attribution/`.

- `d4_layers.py`, `d4_episodes.py` and `c1c_profiles.py` read the hourly NetCDF
  on scratch.
- `toy_imex_gap.py` and `toy_imex_gap_inexact.py` are a scalar model of the
  stepper.
- Everything else is cited.

Where a statement is an inference and not a measurement, it says so.

---

## Summary

**Two goals, not one.**

- *Closure* means that the region tags add up to the total they partition,
  `Σ tags = E` with `E = ρe_tot + c·ρ`. It can be made exact to rounding, by
  construction, for every term the parent applies.
- *Correctness* means that each tag holds what it should. That is defined only
  relative to conventions:
  - the offset `c`;
  - the form of the energy flux;
  - how a grid cell's contents mix;
  - the loss rule;
  - how finely processes are split.
- Moist total energy has no physical zero. So correctness in an absolute
  physical sense is not well posed for it.
- What can be reached is exact accounting under stated conventions, with the
  sensitivity to those conventions measured and reported.

**Where the residual stands on the case closest to production.**

- D4 is the DYCOMS RF02 EDMF column with 1M. Under the enthalpy audit its base
  residual is 6.32e5 J/m² gross at 24 h (E59). That is 0.55% of `∫E`, and about
  3.5% of the day's process energy of 1.8e7 J/m².
- A split by layer (`c1c_profiles.py`) gives three parts:
  - **Subcloud layer, 2.8e5 J/m², 44%.** A linear ramp in height, with slope
    2.4 to 3.0 J/kg/m. That slope is the one `R_d·Γ` predicts (2.5 to
    2.7 J/kg/m). It is the EDMF eddy diffusion's form mismatch: the tags diffuse
    `e`, and the parent diffuses `s_d` and `h_tot`. C1c removes 90 to 94% of
    this part in the first hour (E59's runs). So it is measured, and it can be
    removed.
  - **Cloud layer and inversion, 2.0e5 J/m², 32%.** Not separated.
  - **Free troposphere, 1.6e5 J/m², 25%.** A uniform −157 J/kg. It is
    identical, to 0.1 J/kg, in all four C1c runs, so the eddy diffusion does not
    make it. Not separated.

**The most important finding is now measured (E59): sharing at the tendency
level is not enough for a stiff implicit parent flux.**

- All three C1c placements follow the parent's *tendency*, not its implicit
  *update*.
- Each gap grows linearly in time, by 5e4 to 2.9e5 J/m² an hour. Each
  placement passes the base after 4 to 6 hours.
- The errors sit where explicit forcing meets stiff implicit diffusion. Under
  option 1 that is the lowest two levels, at ±4.2e4 J/kg by 24 h, and cloud top.
- A scalar model of the ARS222 stepper reproduces the ordering and the
  location.
- It also shows that only sharing the parent's own stage increment is exact
  whatever the solver does. Any placement of a tendency drifts. How much depends
  on how far the parent's one-iteration Newton step is from its tendency at the
  solved state.

**The top-ranked step follows from that.** Make the tags' implicit channel a
decomposition of the parent's implicit stage increment.

1. Snapshot `E` and the tags in `initialize_imp!`, where `U == temp` (CTS
   `imex_ark.jl:212-215`).
2. After the Newton solve, in `T_post_imp!`, form the column mismatch between
   the parent's increment and the tags'.
3. Integrate it into a vertical face flux with
   `Operators.column_integral_indefinite!`, which the model already uses
   (`radiation.jl:641`).
4. Share that flux by the donor cell's shares.

CTS folds `T_post_imp!` into the stored implicit tendency (`imex_ark.jl:230-236`,
`:284`). So the correction enters the step with the parent's own stage weights.

- It is exact to rounding, by construction.
- It is logged, and it can be switched off to measure what it absorbs.
- The column-integral part of any mismatch stays visible in `e_src_res`.
- Expected gain, inferred: it removes E59's drift and E39's Newton lag. It
  probably also removes D4's cloud-top and free-troposphere parts. That would
  bring D4 from 6.3e5 J/m² toward the 1e3 to 1e4 J/m² floor of columns without
  EDMF (C9, E34).
- C1c then goes on top of it.

**After closure comes correctness, which closure cannot see.**

- **The sub-grid mass flux under-mixes provenance.** C1b shares it by the donor
  cell. At 6 h on D4 the surface-flux tag falls 4.8 times between 25 m and
  275 m. Meanwhile the air there follows an 8.9 K/km lapse rate. So the tag
  stays stratified where the air is mixed.
- **First-order shares smear** (E34).
- **Source-labelled tags go negative.** The repair then creates energy (E35,
  E36).
- **Subsidence is a bracketed source** in single-column cases. So energy brought
  down from above is relabelled `sub`.

There are fixes that leave closure exact:

- exchange fluxes that sum to zero over the tags;
- higher-order shares that stay non-negative (Larrouturou 1991);
- a partition by label in place of the source-labelled tags.

**The offset sets the memory.**

- In a well-mixed box, the equilibrium shares do not depend on `c`. Fajber and
  Kushner (2021) derive the same well-mixed limit for heat tags.
- The time to reach them does depend on `c`. It is `E/L`, with `L` the gross
  loss rate, and it grows with `e + c`.
- On D4 at `c` = 110,495 J/kg the initial-energy tags lose 8.6% and 12.3% a
  day. That is a memory of 8 to 11 days.
- Absolute tag amounts depend on `c` over long runs. So does the direction in
  which falling ice moves provenance.

**Prior art sets the bar.**

- Water-vapour tracers in WRF close to 0.1 to 0.2% over a month (Insua-Costa
  and Miguez-Macho 2018).
- Heat tags of potential temperature use this fork's exact rule. They close to
  1 to 2% rms (Fajber and Kushner 2021).
- Both tag a positive quantity with a natural zero. Both move it with the
  parent's own transport form. Energy is harder on both counts.

**Decide first.**

1. Whether the implicit channel is rebuilt as a decomposition of the parent's
   increment. This replaces the question of where C1c's share goes. It also
   reopens how C1b and sedimentation follow their implicit parent fluxes.
2. The set of conventions.
   - Is the enthalpy flux form, the audit, the *reference definition*, and not
     only an audit?
   - What rule chooses `c` (U8)?
3. Whether a logged correction may bring `e_src_res` to rounding by
   construction. The memo's Part 2 objects to this. Its answer here: only the
   column-local timing gap is absorbed, and the column-integral part stays
   visible.

The ranked path is in section 7.

---

## 1. Accounting: the residual, cause by cause

### 1.1 The rule, and what closure can mean

Production goes to tags by mask or label, and loss is taken by share
(`energy_source_tags.jl:597-639`).

- The partition masks add up to one. Take `φ_k` as the clamped share of `E`
  (`:430-432`). Then one bracket changes the region tags' sum by
  `Δ⁺ − Δ⁻·Σφ_k`.
- If the tags already add up to `E`, that is `Δ⁺ − Δ⁻`, the parent's increment.
  So each bracketed process closes by construction.
- If `R = E − Σ tags` is non-zero, the loss half removes only
  `Δ⁻·(1 − R/E)` from the tags. The residual then changes by `−Δ⁻·R/E`.
- **So the residual decays wherever energy is lost.** It behaves like one more
  tag, holding "unattributed energy", which loses in proportion and gains
  nothing. E34 and E39 saw this: fed with the hourly records, the loss rule
  alone reproduces C9's column after the first hour.
- The consequence: `e_src_res` does not grow without bound. With a steady gap
  it saturates near the gap's rate times the memory `E/L` (section 3.3).

### 1.2 The table

Status is **M** for measured, **I** for inferred and **U** for unknown. A cause
is *removable* when a change to the tags removes it. It is *structural* when it
follows from a convention.

| # | Cause | Evidence | Status | Size | Removable? |
|:--|:--|:--|:--|:--|:--|
| 1 | Pressure work. Under `tracer` the tags move `e`, and the parent moves `h_tot = e + p/ρ`. | E25: after the first 10 min it is 72,260 of the column's 72,000 J/m² growth. E31: at least 93% on the sphere. E34: the audit takes the column from 2.44e6 to 2,284 J/m² at 24 h, and the sphere from 2.82e21 to 2.54e20 J. | M | the dominant term under `tracer` without EDMF | Structural under `tracer`, because a tracer flux is not an energy flux (section 3.2). Removed by `enthalpy`. |
| 2 | The EDMF eddy diffusion's form. The parent diffuses `s_d`, `h_tot` and water enthalpy (`edmfx_sgs_flux.jl:269-275`). The tags diffuse `ρe_src/ρ` with `K_h + K_e` (`:395-397`). | E59's base is a subcloud ramp of slope 2.4 to 3.0 J/kg/m against a predicted `R_d·Γ` of 2.5 to 2.7 (`d4_layers.py`, `c1c_profiles.py`). At 1 h C1c's options 2 and 3 cut the subcloud part from 1.08e5 to 6.4e3 and 1.05e4 J/m². D5 shows the same sign pattern and a low-level slope of 2.95 against 2.51. | M on D4; I on D5 | 2.8e5 J/m² at 24 h, 44% of D4 | Removable (C1c), but only with an exact implicit channel (row 3b) |
| 2b | The same mismatch in vertical diffusion outside EDMF (`vertical_diffusion_boundary_layer.jl:103`), the viscous sponge (`viscous_sponge.jl:161`), EDMF's horizontal diffusion (`edmfx_sgs_flux.jl:479` against `:560-565`), and the LES closures. | Code only. On D1 vertical diffusion did not make the gross (E42b). | U | 0 on columns without them; unmeasured on the sphere (C4, V2) | Removable by sharing |
| 3a | The Newton lag of terms the tags follow explicitly while the parent is implicit: the audit's vertical advection (`energy_source_tags.jl:1248-1253` against `implicit_tendency.jl:253` and `:387-404`). | E39: 98% of the column's first-hour audit residual is made in the first step, and a converged solve removes 99%. E39b: 83% on the sphere. E43: C8's audit day is 193 J/m² with one iteration and 12.0 converged. | M | 2.7e3 J/m² on C9's column; 2.5e20 J on C9's sphere | Removable (section 2) |
| 3b | A stiff implicit parent flux shared at the tendency level. | E59: every C1c placement grows linearly, by 5e4 to 2.9e5 J/m² an hour. The profiles put option 1's error at the lowest two levels (+41,723 and −42,093 J/kg at 24 h) and at cloud top (`c1c_profiles.py`). | M | up to 6.7e6 J/m² a day (option 1) | Removable (section 2) |
| 3c | C1b's share of the SGS mass flux, and sedimentation, both follow implicit parent fluxes at the Newton iterate without a block of their own (`energy_source_tags.jl:1336-1342`, `:906-910`). | E39: the sedimentation lag is −7.8 J/m² at 600 s on a 1M column without EDMF. On D4 this is not separated. The base's rise from 4.61e5 to 6.32e5 between 12 and 24 h (E59) is a candidate. | I | unknown on EDMF | Removable (section 2) |
| 3d | D4's uniform free-troposphere residual, −157 J/kg by 24 h. | Identical in all four C1c runs, and −155 in E53's run. Its steps at 14 h and 23 h coincide with jumps in the cloud-layer residual, while the hourly records change smoothly (`d4_episodes.py`). | M in size; cause U | 1.2e5 to 1.6e5 J/m², about 25% of D4 | Probably row 3a acting on the `c·ρ` part of vertical mass redistribution (I). The tests are a `2c` twin and a converged-Newton twin. |
| 4 | Processes no tag lists. | E20: subsidence on the column. E28: the rain-out producing energy on the sphere. The label check (#77) catches both at configuration (E38). | M | form A 17,954 J/kg (C5); integral 1.26e-3 (C6) | Removed by the label check |
| 4b | `c·Δρ` from processes that move mass outside the brackets (`energy_source_tags.jl:102-111`). Under the audit, hyperdiffusion carries `c` (§6, #72). The others do not. | Code only. | U | zero-sum pointwise; zero in the column integral | Removable by sharing (C4) |
| 5 | The loss clamp and the transport clamp on negative tags. | E37: about 3% of C7's form-A gap. E36: under the audit a negative source tag freezes at its node. Form A reaches 76.8 J/kg on the sphere, with an integral of 4.7e-5. | M | form A only; `e_src_res` untouched with the repair on | Removable: signed source tags (A4), or a partition by label (section 3.6) |
| 6 | The repair. | It keeps the partition's sum, so `e_src_res` is unchanged: C10 matches C9 to four digits (E35). It trades up to ±30,915 J/kg with 2° masks, and nothing with 10° masks (E27, E46, E48). The repair of source tags creates energy: form A 274 J/kg, integral 6.0e-4 (E35). Option 2 of C1c moves the repair 400 times more (E59). | M | correctness, not closure | The trades are structural for masks narrower than the grid. The energy it creates can be removed (section 3.6). |
| 7 | `E ≤ 0`. | E1: 96.7% of the column and 43% of the sphere by volume without an offset. E9b: 78% by mass. Zero in every run with an offset (E11, E17; the D4 tables). | M | none with an offset | Structural without an offset; a risk for cold spells (U8) |
| 8 | Float32. | E45: the sphere matches Float64 to rounding. E55: D4 keeps its size, tilts toward overclaiming, and form A's gap cancels less. | M | a floor near 1e-7 of the total (E45); the tilt is not separated | Partly structural (rounding) |
| 9 | Hyperdiffusion's coupling within an element. | Under `tracer` it is 2.4% of the sphere's growth (E31). Under the audit it is exact to 100 eps when the shares add up to one at every node of the element (docs, `energy_source_tags.md:407-410`). It is centred, not upwind, so it can push a tag below zero (E36). | M | small | Closure: removed. Positivity: not. |
| 10 | Limiters. | E25: the per-tag van Leer limiter is 268 of 72,000 J/m². E31: 2e-4. E37: it makes C7's form-A gap. Under the audit the shares are linear, so none. The tags are exempt from the SEM limiter and the non-negativity methods (`tagged_tracers.jl:1037`). A hook that writes `ρe_tot` outside a bracket warns (R3, #77). | M under `tracer`; U for hooks | small | Removable |
| 11 | Rounding. | E45, E47 | M | 1e-16 relative in Float64 | Structural |

### 1.3 D4, split by layer

These are gross values in J/m², with the signed values in brackets. They come
from the hourly NetCDF, weighted by `rhoa` over the 50 m levels. For E53's run
the source is `d4_layers.py`; for E59's base it is `c1c_profiles.py`.

| run, 24 h | below 550 m | 550 to 800 m | above 800 m | total |
|:--|--:|--:|--:|--:|
| E53, `tracer` | 2.33e5 (−9.3e4) | 1.62e5 (−1.47e5) | 2.75e5 (+2.51e5) | 6.71e5 |
| E53, `enthalpy` | 2.53e5 (+6.3e3) | 1.62e5 (+1.62e5) | 1.26e5 (−1.26e5) | 5.41e5 |
| E59 base, `enthalpy` | 2.77e5 | 2.00e5 | 1.56e5 | 6.33e5 |
| E59 option 1 | 5.72e6 | 8.79e5 | 1.15e5 | 6.71e6 |
| E59 option 2 | 3.55e5 | 7.10e5 | 1.17e5 | 1.18e6 |
| E59 option 3 | 6.29e5 | 7.10e5 | 1.18e5 | 1.46e6 |

- **The subcloud ramp is the same under both transports** (2.33e5 and 2.53e5).
  So grid-scale transport does not make it.
- **A straight line explains nearly all of it.** Under `enthalpy` at 24 h the
  misfit of the line is 9.4e3 of 2.55e5 J/m².
- **Its slope is what the form mismatch predicts.** Suppose the tags' eddy flux
  balances the parent's. Then `∇(Σ tags/ρ)` follows `∇s_d` or `∇h_tot`. The
  residual's gradient is then `∇e − ∇s_d ≈ −R_d ∇T`. That is 2.5 to 2.7 J/kg/m
  for the lapse rates in the column.
- **The free-troposphere part changes character with the transport.** Under
  `tracer` it grows with height, which is pressure work. Under `enthalpy` it is
  uniform.
- **The cloud layer carries C1c's timing error.** Its dipole at cloud top
  appears in all three options: +7,189 and −4,955 J/kg under option 1,
  +5,554 and −4,285 under option 2, +7,537 and −4,187 under option 3. It does
  not appear in the base (+330 and −1,060).

### 1.4 Which parts are removable

- **Removable by changes to the tags alone:**
  - pressure work (the audit, done);
  - the form mismatches in diffusion, the sponge and the LES closures;
  - every timing gap;
  - missing labels;
  - the clamps;
  - the energy the repair creates;
  - `c·Δρ` from unbracketed processes.
- **Structural:**
  - rounding;
  - the repair's trades where a mask is sharper than the grid;
  - `E ≤ 0` without an offset;
  - and above all the conventions (section 3). They do not enter `e_src_res`
    at all.

---

## 2. Numerics and time integration

### 2.1 How the stepper combines what the tags follow

CTS 1.0.1 runs each implicit stage in the same sequence (`imex_ark.jl:212-236`,
`:284`):

1. `temp = U`.
2. `initialize_imp!`. Under EDMF it rewrites the updraft's `u₃` and `ρa`
   (`initialize_implicit_problem.jl:33-57`).
3. One Newton step (`max_newton_iters_ode: 1`, `default_config.yml:68-70`).
4. `T_post_imp!`: the upwind correction of `ρe_tot` and `ρq_tot` at the solved
   state (`implicit_tendency.jl:387-404`).
5. `T_imp[i] = (U − temp)/dtγ`.

The step then combines everything as `u + dt·Σ b_exp,i T_exp,i + dt·Σ b_imp,i T_imp,i`.

Three facts follow.

- **The tags' implicit contribution is their tendency at the stage's initial
  guess** when they have no Jacobian block. Their Newton row is the identity, so
  `T_imp[i]` for a tag equals its implicit tendency at `U₀` (E39). The parent's
  contribution is instead the solve's increment. For a stiff, linear term with
  an exact `W`, that is `W⁻¹` applied to the tendency.
- **A term the tags follow explicitly is weighted differently.** It is evaluated
  at the solved stage states, with the explicit weights. For ARS222 those are
  `b_exp = (−0.707, 1.707, 0)` against `b_imp = (0, 0.707, 0.293)`
  (`imex_tableaus.jl:286-299`). The default elsewhere is ARS343
  (`default_config.yml:71-73`).
- **The post-Newton correction and any change `initialize_imp!` makes are part
  of the parent's `T_imp[i]`.** What the tags must follow is `(U − temp)/dtγ`,
  not a tendency.

### 2.2 Is sharing each flux at the tendency level enough? No, for stiff implicit terms.

The integration tests check that the partition's tendencies add up to the
parent's to 100 eps (docs, `energy_source_tags.md:330-336`, `:480-484`). That is
a statement about one evaluation at one state. It says nothing about the update
the stepper forms. E59 shows the difference.

**A scalar model makes the mechanism visible** (`toy_imex_gap.py`,
`toy_imex_gap_inexact.py`).

- One stiff mode, `dE/dt = f − λE`.
- `f` is explicit; think of the surface flux or radiation.
- `−λE` is implicit; think of the eddy diffusion.
- It is stepped with ARS222 exactly as CTS steps it.
- The tags' sum follows `f` exactly, and follows `−λE` by one of the C1c
  placements.
- The table gives the drift of `R` per step, in units of `dt·f`, once `E` is
  steady. `κ` is the parent's Jacobian over the true derivative. One Newton step
  with an inexact Jacobian leaves a defect.

| `dt·λ` | option 1, `κ`=1 | option 2, `κ`=1 | option 3, `κ`=1 | option 1, `κ`=0.7 | option 2, `κ`=0.7 | option 3, `κ`=0.7 | the stage increment, any `κ` |
|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | 0.29 | 0.069 | 0 | 0.21 | −0.003 | −0.088 | 0 |
| 4 | 1.17 | 0.18 | 0 | 0.82 | −0.009 | −0.35 | 0 |

What the model says:

- **Option 1 drifts** by about `γ·dt·λ` times the explicit forcing per step. The
  forcing leaves the stage predictor with a spike the parent smooths
  implicitly. The tags take the flux of the unsmoothed spike. In steady state
  this does not cancel, so the drift accumulates.
- **Option 2 filters the tags' increment with the tracer block.** That block is
  weaker than the parent's energy block by `c_p,d/c_v,m`: compare
  `manual_sparse_jacobian.jl:1575` with `:1505`. So option 2 drifts less, but it
  does not stop.
- **Option 3 is exact in steady state only if the parent's Newton step is.**
  With a defect it drifts, and with the opposite sign to option 1.
- **Only following the parent's stage increment is exact for every `κ`.**

The runs agree with this in ordering and in location, not in size.

- Option 1 grows about 5 times faster than option 2 and option 3: 2.8e5
  against 5e4 to 6e4 J/m² an hour (E59). The model gives 5 to 6 for `dt·λ`
  between 2 and 4 when `κ` = 1.
- Option 1's error sits at the lowest two levels, where the explicit surface
  flux enters, and at cloud top, where the explicit radiative cooling acts.
- **At the lowest two levels option 3's dipole has the opposite sign to option
  1's.** It is −1,433 and +1,408 J/kg against +41,723 and −42,093 J/kg. That is
  what an inexact parent Jacobian gives.
- The parent's Jacobian is inexact by design. It freezes the coefficients, omits
  `∂K/∂state`, and folds the `K_e` piece into the diagonal
  (`manual_sparse_jacobian.jl:1478-1505`). D4 also solves the linear system
  approximately, with `approximate_linear_solve_iters: 2`.
- The model has one mode and no cross-coupling. It is a caricature and is not
  calibrated.

**It follows that C1b and sedimentation carry the same risk.** Each follows an
implicit parent flux at the Newton iterate with no block of its own. The
design argued that a block is not needed because the tags' own Courant number is
small (`energy_source_tags.jl:1336-1342`; `SUBGRID_AND_MICROPHYSICS_DESIGN.md`,
"Why no Jacobian block"). That argument is about the tags' stability. What sets
the gap is the parent's implicit smoothing of explicitly forced stiff modes,
`(I − W⁻¹)`.

- On a column without EDMF the sedimentation lag was small (E39).
- Implicit microphysics puts the rain source in the same channel, which avoids
  an explicit spike. That is why C8's form-B remainder did not accumulate (E39).
- On D4 this is not separated.

### 2.3 The alternatives

**Sharing the parent's increment, per stage.** Recommended. Three variants, all
exact to rounding:

- **(a) Follow each implicit term at `U₀`, then correct the remainder.** Keep
  today's shares in the implicit tendency. Snapshot `E` and the tags at
  `initialize_imp!`. In `T_post_imp!`, form `m = ΔE_parent − Σ Δtags` per cell.
  Integrate `m` over each column into a face flux. Share that flux by the donor
  cell, and write it as the tags' part of `T_post_imp!`. The audit's vertical
  advection then has to move into this channel too, or it is counted twice.
  This is cheap. The remainder has no process identity, but provenance needs
  only the donor, not the process.
- **(b) The parent's increment for each process.** For one Newton iteration the
  solve is linear in its right-hand side. The same holds for a fixed number of
  approximate linear iterations started from zero. So the parent's increment
  splits exactly into `W⁻¹` applied to each implicit process's tendency. Each
  piece can be shared as transport by donor, or attributed as a source by the
  bracket rule. This keeps each process's own donor direction. It costs one
  extra linear solve per implicit process per stage. It also needs the Jacobian
  and its solver cache inside `T_post_imp!`, which today's hook does not pass.
- **(c) Share the whole increment.** The tags follow no implicit term. The
  parent's implicit increment of `E` is reconstructed into a column flux and
  shared. This is the simplest. It nets opposite fluxes through a face, for
  example sedimentation down and the SGS flux up. So it moves less provenance
  than the gross exchange would.

The column integral of `m` is not zero wherever an implicit source or a flux
through the bottom lags. Those are the 0M rain-out and sedimentation at the
ground. Leave that part in `e_src_res`, where it stays visible, or attribute it
under its own label. E43 measured it: −5.3 J/m² a day on C8, and −3.8e-3 with a
converged solve.

**Sharing the parent's increment once per step,** at the end of the step. It
projects `R` in each column onto a vertical flux. It is cheaper and needs no
stepper hook. But it also absorbs any vertical form mismatch or process the tags
have not shared. It hides those unless the ledger is read. It is a fallback, and
only honest once coverage is complete.

**Jacobian blocks for the tags (C7).**

- A diagonal block keeps the tags uncoupled and preserves the split solver
  (E44e). It cannot follow the parent's cross-couplings or its defect.
- E59's option 2 is this idea with the tracer block. It reached 1.18e6 J/m² at
  24 h and moved the repair 400 times more.
- Cross blocks move a tag back into the nested solver. The build time then
  returns (E44d; the risk is described in
  `SUBGRID_AND_MICROPHYSICS_DESIGN.md`, "What the split solver needs from C1b").
- A partial fix at best, with a cost in build time.

**A converged Newton solve.**

- Measured: 99% of the audit's first-hour residual goes on the column (E39),
  83% on the sphere (E39b), and C8's day goes from 193 to 12 J/m² (E43).
- It costs about three times the step (E16's twin: 3.2 s to 10.0 s).
- It changes the parent's trajectory relative to the production configuration.
  So it is a diagnostic for closure studies (R5), not a path.
- In the scalar model it would make option 3 exact in steady state. A D4 twin
  of option 3 with a converged solve would test whether E59's option 3 drift is
  the defect.

**A provably exact linear decomposition.** The recipe:

- **(E1)** Every explicit parent term that writes `ρe_tot` or `ρ` is either
  bracketed or shared at the face. That is the audit plus C4's coverage.
- **(E2)** The implicit channel follows the parent's increment, by one of (a)
  to (c).
- **(E3)** Every hook that writes `ρ` or `ρe_tot` is bracketed: the limiters'
  consistency fixes and the moisture fixers (R3). DSS is linear and needs
  nothing.
- **(E4)** The loss half uses shares that add up to one.

The proof is by induction over stages.

- Each stage's tag increments add up to `E`'s, because `Σ M_k = 1` and the donor
  shares add up to one.
- The stepper combines stages linearly (`imex_ark.jl:77-91`).
- With the repair on, the partition tags stay non-negative, so the clamps never
  bind. The repair keeps the sum.
- So `Σ tags = E` holds at every stage and step, to rounding.

**Share schemes that preserve positivity.**

- The audit's first-order donor share is the scheme Larrouturou (1991) proved
  positive and consistent for mass fractions: the species flux is the total flux
  times the upwind fraction.
- A second-order version reconstructs each share at the face with a limiter,
  clips it to [0, 1], and divides by the sum over tags. The shares then add up
  to one, and closure stays exact.
- Positivity then needs the energy Courant number of the donor to stay at or
  below one. Otherwise the repair takes over.
- The centred horizontal and hyperdiffusion operators of the spectral elements
  cannot preserve positivity for each tag (E36).

### 2.4 What makes `Σ tags = E` exact to rounding, and what it hides

| step | exact? | what it costs | what it hides |
|:--|:--|:--|:--|
| The audit's explicit shares (done) | yes, for each evaluation | first-order smearing (E34); about 5% a step (E34) | nothing |
| Coverage of every explicit term (C4) | yes | about 100 lines per operator (B3's estimate) | nothing |
| The implicit channel as the parent's increment (2.3 a to c) | yes | a column scan and a donor share per tag at each implicit stage (I: a few percent); a trace test pinned to CTS, as the ledger's hook template is (`parent_budget/architecture.md`, adapter section) | the timing gap, unless its ledger is written out |
| Brackets on every hook that writes `ρ` or `ρe_tot` | yes | small | nothing |
| A vertical projection at the end of each step | yes, vertically | small | also the vertical form and coverage gaps |
| A remainder tag, or rescaling onto `E` | trivially | nothing | everything (memo Part 2; `energy_source_tags.jl:710-713`) |
| A converged Newton solve | no, only to a tolerance | about 3 times the step (E16); a different trajectory | nothing, but not a production path |
| Jacobian blocks | no | build time (E44d) | nothing; the repair moves 400 times more (E59) |

---

## 3. Physics and definition

### 3.1 Closure and correctness are different claims

The docs already say it: closure proves that the included terms add up to the
parent, and "does not establish ... that the provenance reading is valid"
(`energy_source_tags.md:543-551`). The parent-budget contract keeps provenance
as a separate claim level, "level 6" (`docs/src/parent_budget/contract.md`,
"Claim levels").

Making "correct" concrete means naming, for each tag, the equation whose exact
solution is the right answer:

```
∂(ρe_src,k)/∂t = −∇·(s_k^donor F_E) + M_k Δ⁺ − s_k Δ⁻ + X_k,     Σ_k X_k = 0.
```

Here `F_E` is each discrete flux of `E` the parent applies. `Δ±` is the gross
production and loss of each bracket. `X_k` is any exchange between tags that
carries no energy (3.5).

Six choices fix that equation:

- the offset `c`;
- the flux form, `F_E`;
- the mixing model, which is the donor choice and `X_k`;
- the loss rule;
- the granularity of the brackets, that is, what one bracket nets;
- the resolution, since a cell is the parcel.

Given all six, "correct" means that the tags solve this equation accurately
along the parent's discrete trajectory, and that can be measured (section 5).
None of the six is fixed by physics for total energy. So each has to be stated.

### 3.2 The flux form: the enthalpy audit is the physical definition, not only an audit

In flux form, the total-energy equation is

```
∂(ρe_tot)/∂t + ∇·(ρu h_tot) = sources,     h_tot = e_tot + p/ρ.
```

The energy crossing a face with a mass flux is enthalpy. It includes the flow
work. That is the textbook control-volume energy flux. A tracer flux
`ρu·(ρe_src/ρ)` is not an energy flux, because it leaves out `p·u`. Pressure
work cannot be booked as a source either, because it is a divergence.

- So the `tracer` residual is a definitional mismatch, not a numerical one. E25
  and E31 measure its size.
- The audit moves each tag by its share of `ρu(h_tot + c)`
  (`energy_source_tags.jl:1246-1253`). That is the open-system accounting.
- Its only cost is sharpness: first-order shares instead of the tags' own van
  Leer (E34). Section 2.3 names a higher-order version that keeps closure.
- **Recommendation: use the enthalpy form as the reference definition for every
  claim about correctness.** Keep `tracer` for comparison.

Another option is to book pressure work as its own process: a bracket, with
production by mask and loss by share. It closes too. But it creates
"pressure-work energy" at the gaining cell, where the enthalpy form moves the
donor's composition. That is less natural for provenance.

### 3.3 The offset: no physical zero, and `c` sets the memory

- **Convention.** The model's zero is enthalpy zero at `T_0` (R1). Tagging needs
  a positive total, so `E = ρ(e + c)`. On D4 at 24 h, `E/ρ` is 64 to 68 kJ/kg
  (`cloud_top.csv`, column `total`). Of that, `c` is 110.5 kJ/kg.
- **Equilibrium shares do not depend on `c`.** In one well-mixed box with steady
  production `P_k` and loss `L = ΣP`, the rule gives
  `ds_k/dt = P_k − (s_k/E)·L`. Its equilibrium is `s_k/E = P_k/ΣP`, whatever `c`
  is, unless a process moves mass (below). Fajber and Kushner (2021, their eq. 24)
  use the same well-mixed estimate for heat tags.
- **The time to reach them depends on `c`.** It is `τ = E/L`, and `E` grows with
  `e + c`.
  - On D4 the initial-energy tags lose 8.6% (`strat`) and 12.3% (`tropo`) in a
    day (`process_closure.csv`: 5.268e7 to 4.813e7, and 6.030e7 to 5.291e7). That
    is `τ` of about 11 and 8 days.
  - Doubling `c` would multiply `τ` by `(e + 2c)/(e + c)`, about 2.6 there.
  - E19 found doubling `c` moved a source tag by 1% over a day. Over one day that
    is expected. Over a season, absolute tag amounts, and how much initial
    energy remains, will depend on `c` roughly as `e + c`.
- **Processes that move mass carry `c`.**
  - Evaporation adds `c` per kilogram to `E`. On D4 the prescribed 93 W/m² of
    latent flux (E23) is about 3.2 kg/m² a day. At `c` = 110,495 J/kg that is
    about 3.6e5 J/m² a day of offset energy in the surface-flux tag, against
    9.42e6 J/m² of surface energy flux (E23). So about 4% of that tag's daily
    production is convention.
  - Rain-out and sedimentation remove `c` per kilogram.
- **Even the direction of transport depends on `c`.** Falling ice carries down
  to −193 kJ/kg, `c` included (E41). So a donor is the cell below. With `c`
  larger by about 200 kJ/kg the same ice carries positive `E`, and the donor
  becomes the cell above. The upward branch is an artefact of the choice of `c`.
- **A principled rule exists.**
  - Dry internal energy is zero at 0 K when `c = c_p,d·T_0` = 274,388 J/kg:
    `e_int,dry(0) = −c_p,d·T_0`, by R1.
  - That is U8's option 1 with a floor of 0 K. It guarantees `E > 0` for dry air
    at any temperature above the surface.
  - It gives a memory about 3.4 times longer than 110,495 on D4.
  - It gives larger undershoots in the region tags (E19: 1.51 times per
    doubling), and shares that discriminate less (R11).
  - It is a choice with costs. It is the owner's.

The water analogue shows what is lost. Water has a physical zero and a physical
residence time, about nine days in the atmosphere, not a figure from these runs.
Energy has neither. So "how long does surface energy stay in the atmosphere?" is
answered only relative to `c`. The ocean literature knows the same problem:
heat transport through a section without mass balance cannot be fixed
independently of the reference temperature (Schauer and Beszczynska-Möller
2009).

### 3.4 Cells as well-mixed parcels, and where sub-grid provenance goes wrong

The donor rule assumes that everything in a cell is indistinguishable. For a
grid cell that holds an updraft and an environment, this is false.

- **Transport.**
  - C1b shares the net SGS flux of `E`, `ρᵏaᵏ(u³ᵏ − u³)(mseᵏ + Kᵏ − h_tot)`,
    by the donor cell (`energy_source_tags.jl:1316-1348`).
  - That flux carries the energy anomaly. The air exchange behind it carries
    about fifty times more mass, both ways (`SUBGRID_AND_MICROPHYSICS_DESIGN.md`,
    "Its limit").
  - Provenance mixes with the air, not with the anomaly. So option B mixes
    provenance too slowly.
  - D4 shows it (`d4_column_edmf*/output_0001/e_src_sfc_1h_inst.nc`). At 6 h
    the surface-flux tag is 7,843 J/kg at 25 m and 1,650 J/kg at 275 m. The
    temperature there follows 8.9 K/km, close to dry adiabatic. By 24 h the tag
    is uniform below 450 m. So the eddy diffusion mixes it in hours, where the
    air overturns in well under an hour.
  - `q_tot` was not written out, so this is strong evidence, not proof.
- **Losses.** Rain-out in an updraft takes energy by the grid mean's shares
  (`SUBGRID_AND_MICROPHYSICS_DESIGN.md`, table, row "microphysics, 0M").
  Radiative cooling at cloud top acts on cloudy air. Proportional loss on the
  grid mean spreads both over the cell's whole composition.
- **Option C** gives the updraft its own shares. It fixes the transport part and
  costs about three times B, with implicit blocks (the design, option C).

### 3.5 Mixing as exchange, not only transport

The tracer and flux conventions are compared with D4's numbers in
[TRACER_AND_FLUX.md](TRACER_AND_FLUX.md) (2026-09-19).

This point matters for the next design.

- An eddy diffusion is a parameterized *exchange* of air. It moves a small net
  flux, and it mixes composition at the full exchange rate.
- A passive tracer diffused as `−ρK∇χ` is mixed correctly for composition. That
  is why water tagging schemes use the parent's diffusivity on each tracer
  (Insua-Costa and Miguez-Macho 2018).
- For energy, the tracer form gets the total wrong: row 2 of the table.
- The audit's net-flux share (C1c) gets the total right and the mixing too slow.

Both can be had. Write each tag's flux as

```
F_k = s_k^face F_E + X_k,    X_k = −ρK (E/ρ) ∇s_k.
```

- Because `Σ_k s_k = 1`, `Σ_k ∇s_k = 0`. So `Σ_k X_k = 0` to rounding, and
  closure is untouched.
- `X_k` mixes the shares at the eddy rate. It is monotone.
- It is stiff, so it belongs in the tags' own implicit rows. There the tracer
  diffusion blocks are its true derivative. They are exactly the blocks E59's
  option 2 kept for the wrong term.
- The same form, with the updraft mass flux as its coefficient and upwind
  shares, gives a closure-neutral stand-in for option C's gross exchange. There
  is no new state.
- This is a design idea. It has not been tested.
- Keep closure-carrying terms in the channel that follows the parent's update
  (section 2). Put only closure-neutral terms such as `X_k` in the tags' own
  implicit rows.

### 3.6 Losses, source-labelled tags, and granularity

- **Proportional loss is the only rule consistent with a well-mixed cell.**
  - Every scheme in the literature uses it: water tracers, the Lagrangian
    WaterSip method, heat tagging (section 6).
  - Signed process tracers avoid it. But they do not stay bounded in climate
    runs (Fajber and Kushner 2021, their section 1).
  - E22 shows its limit plainly: a source tag cannot show where its process
    removed energy. The process record answers that other question (E9).
- **A partition by label, in place of source-labelled tags.**
  - Today a tag with a source is not a member of a partition. Its share is
    clamped rather than normalized, and its repair clips at zero and so creates
    energy (`energy_source_tags.jl:689-690`; E35, E36).
  - Make the labels a second partition: one tag per active label, plus
    "initial". Its sum is then `E` too. Its shares are normalized, and its
    repair only trades.
  - That removes E35's created energy and E36's frozen nodes.
  - It gives a second, independent closure identity. It turns form A into a
    comparison of two partitions.
  - A product partition, region by label, is the most informative, at
    `n_regions × n_labels` tags. The split solver keeps that affordable in build
    time (E44e: 8 tags add 37 s).
- **Granularity.** A bracket nets what happens inside it. Radiation is bracketed
  as one process, so shortwave heating and longwave cooling in the same cell net
  before attribution. Split into two brackets, the radiation tag would gain more
  and lose by share. The tag values depend on this choice.
- **Subsidence in single-column cases.**
  - It is advection in advective form, `−ρ w ∂χ/∂z` (`subsidence.jl:44-49`), and
    the tags bracket it as a source (`tagged_tracers.jl:258-267`).
  - It closes exactly. But energy brought down from above is relabelled `sub`
    instead of keeping the provenance of the cell it came from.
  - Split as flux plus lateral exchange, it would share its flux by donor.
  - This matters for D4's region tags. It does not matter on a sphere, where
    subsidence is resolved.

### 3.7 Is complete attribution well posed?

- **Complete closure: yes.** It is achievable to rounding by construction
  (section 2.3).
- **Complete correctness: only relative to the six choices.**
  - Given those choices the answer is unique and can be measured.
  - Without them, "the correct tag" has no referent for moist total energy.
  - Absolute amounts depend on `c`. Provenance through pressure work is a
    convention. Sub-grid composition is a modelling choice.
- **What is most robust.**
  - Shares in quasi-equilibrium, which are nearly independent of `c`.
  - Differences between runs with the same conventions.
  - Signs and rankings that survive a `c`/`2c` pair.
- **What is least robust.**
  - The absolute amount of a tag after long runs.
  - The initial-energy tags.
  - The direction of ice's provenance transport.

---

## 4. Software architecture

### 4.1 Today

Each parent process is rebuilt for the tags by hand:

| process | size (FINDINGS §8 and the design) |
|:--|:--|
| sedimentation | about 270 lines and 140 of tests |
| the audit | about 250 lines and 200 of tests |
| C1b | about 220 lines and 200 of tests |
| C1c | about 100 lines and 80 of tests |

- **Each kernel reconstructs the parent's flux instead of reading it.** Examples:
  `_face_value_flux` (`energy_source_tags.jl:1201-1207`) and the SGS fluxes
  (`:1397-1443`, `:1579-1601`).
- **A change upstream to a flux form therefore breaks closure silently.** The
  tests to 100 eps catch it only in the configurations they cover. Upstream is
  merged regularly: #89 brought v0.42.11 (E51).
- **The tags follow each flux at one evaluation.** E59 shows that this is not
  enough in the implicit channel (section 2).

### 4.2 Options

**A. A coverage registry for the tags.** Cheap; first.

- The parent-budget ledger already has an executable registry of every path
  that writes `ρ`, `ρq_tot` or `ρe_tot`. A test compares it with the docs cell
  by cell (`docs/src/parent_budget/coverage.md`, introduction).
- Add one column: each row's treatment for the tags. It is one of a bracket
  label, a named sharing kernel, not applicable, or a gap with a reason.
- A test then fails when a row that writes `ρe_tot` or `ρ` has none. That
  would happen, for example, when an upstream merge adds a process.
- No model code; it is safe for parity. It is the most direct guard for
  "complete".

**B. Observing fluxes at the operator.** The right upstream request.

- Every flux-form update of `ρe_tot` and `ρ` would pass its face flux, under a
  label, to an observer. With no observer configured, the observer is `nothing`
  and compiles away.
- The tags then share the parent's own computed flux, not a copy of it. The
  ledger's transfer legs could use the same hook.
- Parity: the stored flux is the same arithmetic as the fused broadcast. Julia
  does not contract to FMA without `@fastmath` or `muladd`, so this is expected
  to be bit for bit. It must still be verified with #79's on/off tests.
- Cost: one face field per observed process, not per tag.

**C. Tagging at the level of the stepper,** meaning the implicit channel of
section 2.3.

- The stepper sees cell increments, not fluxes. In one column the vertical flux
  can be rebuilt from the increments uniquely, given the bottom flux.
- Horizontally it cannot: many flux fields have the same divergence. So the
  stepper level suits the implicit channel, which is vertical only in
  ClimaAtmos. Horizontal transport needs B or today's kernels.
- **So the architecture is a hybrid:** fluxes captured at the operator for the
  explicit channel, and the parent's increment for the implicit channel.
- The ledger's adapter already mirrors CTS's hook template and stage weights
  (`parent_budget/architecture.md`, adapter section). A trace test there pins the
  CTS version. The tag correction should reuse that template and that test.

**D. Decomposition by dual numbers or automatic differentiation.** A dead end.

- Propagating a vector of partials through the parent's code gives
  sensitivities, not contributions.
- The two coincide only for operators linear in the parent. The energy flux
  `u·(E + p)` is not linear in `E`.
- This is the distinction between source apportionment and sensitivity analysis
  (Clappier et al. 2017).

**E. One tag field with a vector element,** in place of `n` named fields.

- One kernel would move every tag per process. That means fewer launches on a
  GPU and coalesced access.
- It would also remove the tags from ClimaCore's compile-time work on the sets
  of field names, which grows much faster than the field count (E44d).
- A large refactor. Worth considering before the GPU (B13), not before closure.

### 4.3 Parity, the GPU, and the hooks upstream would need

- **Parity.**
  - The tag code writes only tag fields, and the #79 tests check that.
  - A tag correction inside `T_post_imp!` needs no new call in the default
    configuration. The hook is already wired when `energy_q_tot_upwinding` is
    not `none`, and its default is `vanleer_limiter`
    (`integrator.jl:212-214`, `default_config.yml:333-335`).
  - With `none`, adding the hook adds a `cache_imp!` refresh and a
    `U += dtγ·0` on the parent's fields. The second can turn a signed zero into
    `+0.0`, and signed zeros do occur in `Y.f` (E51). So a tags-only correction
    must write only tag fields, or be skipped when there are no tags.
- **The GPU.**
  - The correction is one `column_integral_indefinite!` and one donor-share
    kernel per tag at each implicit stage. That is the same shape as the audit's
    kernels.
  - Allocation-free checks exist (T10) and should cover it.
- **Upstream.**
  - (1) A flux observer at each flux-form update of `ρ`, `ρq_tot` and `ρe_tot`.
  - (2) The applied-update bracket, which today is a fork-only edit of upstream
    lines, as a no-op upstream API.
  - (3) Access in CTS to the Jacobian's solver from `T_post_imp!`, for variant
    (b) of section 2.3 only.
  - Each would cut the fork's merge cost with upstream.

---

## 5. Validation: measuring correctness, not only closure

The checks that exist are consistency checks:

- `e_src_res`;
- the audit table (untagged, overclaimed, orphaned);
- form A, the split by region against the split by process;
- form B, the records against the parent;
- the gap-cancellation fractions (E49).

They cannot see first-order smearing, provenance mixed too slowly, the choice of
`c`, or any other definitional choice.

| # | Test | Known answer | What it measures | Cost | Model code? |
|:--|:--|:--|:--|:--|:--|
| V1 | Kernel tests with a set flux: a step partition moved by a constant flux in a column, and a donor flip | the share profile translated exactly | numerical mixing of the shares, first order against higher order | unit test, no compile of the solve | no (tests) |
| V2 | Replay the rule offline with the records, per level, and compare with the tags | the equations of 1.1 integrated exactly | whether the stepper, the brackets and the implicit channel apply the rule; E39 did this for C9 | scripts | no |
| V3 | A twin with a passive tracer that has an updraft copy, set to a region mask or to a surface source, beside the tags | the air's own mixing of composition | option B's slow mixing (3.4); the value of option C or `X_k` | one D4 job | probably a configuration only (not checked) |
| V4 | Ladders in `dt` and `Δz` of the tag fields themselves: D4 at 120, 60 and 30 s, and at 30 and 60 levels | the converged tag field | accuracy at production resolution; W1 did this for water closure | 5 jobs | no |
| V5 | A `c` and `2c` pair on the same atmosphere | none; it measures dependence on the convention | which conclusions are conventional; E19 did this on the sphere | 1 job per case | no |
| V6 | Reversibility: a prescribed flow that returns | the initial partition | irreversible mixing of provenance | needs a working prescribed flow. It fails upstream on `ITime` (E57). A kernel harness is an alternative. | yes, or a harness |
| V7 | Bounds online: `0 ≤ tag ≤ E`; each source tag's integral at most the cumulative production of its labels; each initial-region tag's integral never rising without production | inequalities | violations point at transport or the clamps; E21 checked the last one | small | reductions in the audit table (U4 has the first) |
| V8 | The Lauritzen and Thuburn (2012) mixing diagnostics on pairs or triples of shares | the initial functional relation | real mixing against unmixing and overshoot | scripts | no |
| V9 | A Lagrangian reference: trajectories with conserved MSE and labelled diabatic increments (as Martínez-Alvarado and Plant 2014 combine tracers and trajectories) | none. It has its own assumptions: no sub-grid mixing, and a convention for pressure work. | plausibility only | high | no |

**Order.** V1 and V2 now: they are cheap and decide whether the machinery is
right. V3 and V5 next, since they size the two largest questions of correctness.
V4 before any production claim.

---

## 6. Literature and prior art

What is below was confirmed by search on 2026-09-18 unless it is marked
*recollection*.

### 6.1 Water-vapour tagging

- **Insua-Costa and Miguez-Macho (2018), ESD 9, 167–185, WRF-WVT.**
  - The tracers copy the moisture equations. Phase changes and precipitation
    act "in amounts proportional to their total moisture counterparts", which is
    proportional loss.
  - The PBL scheme applies the parent's diffusivity to the tracers. The
    Kain–Fritsch convection scheme carries the tracers through its mass fluxes,
    the analogue of option C.
  - They validated closure by tagging every source. The summed tracers matched
    the total with a mean relative error of −0.2% in precipitation and about
    −0.1% in precipitable water, with no trend over a month.
- **Earlier work.**
  - Bosilovich and Schubert (2002), J. Hydrometeor. 3, 149–165: tracers in the
    GEOS GCM.
  - Knoche and Kunstmann (2013), JGR 118: direct evaporation tagging in WRF.
  - *Recollection:* Koster et al. (1986, GRL) and Joussaume et al. (1986) did the
    first GCM work.
- **CAM and CESM.**
  - Nusbaumer et al. (2017), JAMES 9, 949–977: isotopes in CAM5.
  - Singh et al. (2016), JAMES: a mathematical framework for water tracers.
  - Brady et al. (2019), JAMES: a coupled option to correct flux drift, for
    long-term isotopic drift. *Recollection:* bulk water and tracer water are
    kept consistent by a total-water tracer.
- **Lagrangian.** Sodemann, Schwierz and Wernli (2008), JGR 113, D03107.
  *Recollection* for the detail: when a parcel precipitates, earlier moisture
  contributions are reduced in proportion. That is the same well-mixed loss.

### 6.2 Heat and potential-temperature tagging

- **Fajber and Kushner (2021), JAS 78(7), "heat tagging".** Read in full from
  the authors' preprint.
  - Potential temperature is split into tags whose fractions add up to one.
  - Heating from each process goes to its tag. Cooling "acting proportionally
    to all heat tags present" is the well-mixed assumption.
  - It is this fork's rule.
  - Closure error, rms of `1 − Σχ`: under 1% in most of the troposphere, under
    2% below 200 hPa, over 2500 days.
  - The radiative tag takes years to equilibrate.
  - Their well-mixed estimate is `⟨Q_i⁺⟩/|⟨Q⁻⟩|` (eq. 24).
  - They tag `θ`. It is positive with a natural zero, and in pressure
    coordinates it moves as a linear tracer. That avoids both the offset and the
    form mismatch.
- **Signed θ and PV tracers.**
  - Martínez-Alvarado and Plant (2014), QJRMS 140, 1742–1755: process tracers of
    potential temperature with sources and sinks, combined with trajectories.
  - Fajber and Kushner note that such signed systems "would not remain finite in
    a long-term climate simulation".
  - Saffin et al. (2016), QJRMS: PV tracers. Their residual includes a "splitting
    error": advecting the variables is not the same as advecting their sum,
    which is this fork's pressure-work problem in another quantity. It also
    includes the dynamical core's non-conservation. The residual stayed at least
    an order of magnitude below the most active process tracers.
- **Energy itself.**
  - I know of no GCM that tags moist total energy with proportional loss. This
    is a statement about my knowledge, not a search result.
  - The ocean view: heat transport through a section that is not in mass balance
    depends on the reference temperature (Schauer and Beszczynska-Möller 2009,
    Ocean Sci. 5, 487–494).
  - FAFMIP's "added heat" is a signed passive tracer of a flux perturbation
    (Gregory et al. 2016, GMD 9, 3993). It sidesteps the zero by tagging
    anomalies.

### 6.3 Tagging in chemistry, and attribution against sensitivity

- Grewe, Tsati and Hoor (2010), GMD 3, 487–499: contributions must be
  "complete", adding up to 100%.
- Clappier et al. (2017), GMD 10, 4245–4256: tagging gives contributions,
  perturbation gives sensitivities, and with nonlinearity they differ. That is
  the docs' "Interpretation limit" (`energy_source_tags.md:543-551`).
- The TAGGING submodel in MESSy (GMD 11, 2049, 2018) and TOAST in CESM
  (Butler et al. 2018, GMD 11, 2825): from the search results only, not read.

### 6.4 The numerical side

- **Larrouturou (1991), J. Comput. Phys. 95, 59–84.** Mass fractions moved with
  the total's flux times the upwind fraction stay positive and consistent. It is
  the audit's scheme, and the basis for a higher-order version.
- **Lauritzen and Thuburn (2012), QJRMS 138, 906–918.** Mixing diagnostics for
  tracers with functional relations (V8).
- *Recollection:* Nair and Lauritzen (2010, JCP), deformational flow tests that
  return (V6).

### 6.5 What the others accepted as accurate enough, and how

| work | quantity | closure accepted | loss attribution | mixing | how closure is got |
|:--|:--|:--|:--|:--|:--|
| WRF-WVT | water | 0.1 to 0.2% over a month | proportional | the parent's K; convection carries the tracers | the same operators as the parent |
| Heat tagging | θ | 1 to 2% rms | proportional | the parent's advection and diffusion | the same linear operators |
| PV tracers | PV | a residual 10 times below the largest process | signed | the parent's advection | none; the residual is reported |
| This fork, D4, E59 base | `E` | 0.55% gross of `∫E` | proportional | net flux, by donor | shared fluxes and brackets |

- The fork is already within the range others accepted, measured by relative
  gross residual.
- It differs in three ways:
  - its quantity has no natural zero;
  - its parent is not moved in tracer form;
  - it measures the residual more carefully than any of these works report.
- The goal of rounding-level closure is stricter than the prior art. It is
  reachable here because the parent's increments are available inside the model
  (section 2).

---

## 7. The ranked path

**Status on 2026-09-19.**

- Question 1 is decided and built: the prototype `enthalpy_increment`, draft
  PR #94. Questions 2 and 3 are open. [TRACER_AND_FLUX.md](TRACER_AND_FLUX.md)
  sets out question 2.
- Step 1 is done and meets its acceptance: D4 closes to 267 J/m² at 24 h,
  with `ta` bit for bit and its remainder explained by the ledger (FINDINGS
  E62 and E64). E59's drift, E39's Newton lag and D4's cloud and
  free-troposphere parts are gone.
- Step 1a: E61 answered the first job with option 1, not option 3. The `2c`
  job did not run; the free-troposphere part it was to explain is gone.
- Step 2 is superseded for closure. The correction absorbs the diffusion's
  form mismatch, so the subcloud ramp is gone too. Rebuilding C1c would now
  only change the mixing convention, toward the per-flux donor that E66
  argues against.
- Step 3 is being measured by V2 on the sphere (running). At 1 h the ledger's
  left part is 19% of the gross, and the rest is what no share follows yet,
  and Float32. The registry test is not written.
- Steps 4 to 6 are open. The prototype's tracer diffusion mixes provenance
  through the boundary layer (E66), which covers the eddy diffusion's part of
  4(b). V3 is the next validation that would inform question 2.
- Not on the path, and found on the way: the records' horizontal advection
  (E63, #93) and the correction under a deep atmosphere (E67, #94).

Each step has four entries:

- **gain:** in J/m² on D4 unless it says otherwise;
- **cost and risk;**
- **decide by:** what to measure;
- **model code:** whether it needs model code, and so the owner's approval.

**0. Decide the conventions.**

- Gain: without them "correct" has no target (3.1, 3.7).
- Cost and risk: none.
- Decide by: nothing to measure. Choose:
  - the enthalpy form as the reference definition;
  - a rule for `c`, for example U8 with a floor of 0 K, or keep 110,495 for
    continuity;
  - reporting the memory `E/L` with results;
  - the label partition (3.6).
- Model code: no.

**1a. Two diagnostic jobs.**

- Gain: none in closure. They decide how steps 1 and 2 are shaped.
- Cost and risk: 2 jobs.
- Decide by, per job:
  - C1c option 3 with a converged Newton solve. If option 3's linear growth
    stops, the drift is the parent's Newton defect, and only sharing the
    increment fixes it.
  - D4 under `enthalpy` at `2c`. If the free-troposphere part, 1.6e5, doubles,
    it is carried by mass.
- Model code: no.

**1. The implicit channel as the parent's increment**, variant (a) of section 2.3,
with its own ledger and a switch.

- Gain:
  - E59's drift, 5e4 to 2.9e5 J/m² an hour, goes to zero by construction.
  - E39's Newton lag goes: 2,695 J/m² on C9's column at 1 h, 2.5e20 J on C9's
    sphere.
  - D4's cloud-layer and free-troposphere parts, 2.0e5 plus 1.6e5 of 6.3e5,
    probably go too (I).
- Cost and risk:
  - About 200 to 300 lines and tests. This is an estimate.
  - A few percent of runtime (I).
  - It depends on CTS's stage sequence, so pin it with a trace test.
  - Parity with `energy_q_tot_upwinding: none` needs care (4.3).
  - It hides the timing gap, unless its ledger is written out.
- Decide by: the D4 base against step 1, and C9's column. Accept when D4's gross
  is at most 1e4 J/m² at 24 h, `ta` is bit for bit, and the ledger's size
  matches what E59 implies.
- Model code: yes.

**2. C1c rebuilt on step 1.**

- Gain: the subcloud ramp, 2.8e5 (44%). It is measured to be removable: 90 to
  94% of it goes at 1 h (E59).
- Cost and risk: the code exists (`9aeb5205`). It must follow the parent's
  update, not its tendency.
- Decide by: D4, both halves, under `enthalpy`.
- Model code: yes; approved as C1c, but to be rebuilt.

**3. Complete the coverage (C4), with the registry test of 4.2 A.**

- Gain: unknown on the sphere. The terms are vertical diffusion outside EDMF,
  EDMF's horizontal diffusion, the viscous sponge, the LES closures, and the
  hooks that write `ρ` or `ρe_tot`. E31's hyperdiffusion was 2.4% under
  `tracer`.
- Cost and risk: about 100 lines per operator, and a registry test that CI
  runs.
- Decide by: V2 with `transport_ledger.jl` (plan item B10).
- Model code: yes for the kernels, no for the test.

**4. Correctness.**

- (a) A partition by label.
- (b) Exchange fluxes `X_k` that sum to zero, for EDMF diffusion and the SGS
  flux, or option C.
- (c) Higher-order shares that stay non-negative.
- (d) Subsidence as transport in single-column cases.

- Gain: not in `e_src_res`. It shows in form A, where E35's 274 J/kg of repair
  energy and E36's freeze would go. It shows in V3, where the surface tag's
  4.8-fold stratification at 6 h would go. It shows in V1, as less smearing.
- Cost and risk: (a) is small to medium. (b) is medium and untested. (c) is
  medium. Option C is about three times B.
- Decide by: V1, V3 and form A.
- Model code: yes.

**5. The validation program,** V1 to V8.

- Gain: it turns correctness from asserted into measured.
- Cost and risk: mostly scripts and configurations; V6 needs a harness.
- Decide by: the table in section 5.
- Model code: mostly no.

**6. The offset in practice.** A `2c` twin beside every headline result, and the
memory `E/L` in the closure table, next to U9's headroom.

- Gain: it makes the dependence on the convention visible.
- Cost and risk: one job per case.
- Decide by: V5.
- Model code: small, for the table.

**Not on the path.**

- A converged Newton solve for production: 3 times the cost (E16), and a
  different trajectory. Keep it as a diagnostic (R5).
- Jacobian blocks for the tags, whether option 2 or C7. E59: 1.18e6 J/m² at 24 h,
  and the repair moved 400 times more. Cross blocks bring back E44's build time.
- A remainder tag, or rescaling onto `E`: it hides everything.
- Automatic differentiation: it gives sensitivities, not contributions.
- The tracer form as the reference definition.

### The steps that make attribution exact by construction

- **Steps 1, 3 and the audit, together with the brackets on hooks,** make
  `Σ region tags = E` hold to rounding, at every stage.
- **The cost:**
  - a few percent of runtime;
  - one hook pinned to CTS;
  - kernels to keep up with upstream, until the operators pass their fluxes out
    (4.2 B).
- **What they hide:** only the timing gap of the implicit channel, and they log
  it.
- **Then `e_src_res` changes role.** It stops being a transport detector and
  becomes a check of consistency and coverage. It is zero by construction.
  Anything else it shows is a missing bracket, a missing share or a lagging
  source term, and each of those keeps its column integral (E38, E49).
- **What stays out of reach of any of them:** the conventions of section 3.
  Only the validation of section 5 and pairs of runs under different
  conventions can speak to those.

---

## Appendix: files this work produced

All are in `/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/attribution_discussion/`.

- `d4_layers.py`: the layer split of E53's D4 pair and the subcloud slope fit.
- `d4_episodes.py`: hourly steps of the free-troposphere residual beside the
  records' hourly increments.
- `c1c_profiles.py`: the E59 runs' profiles and layer split.
- `toy_imex_gap.py` and `toy_imex_gap_inexact.py`: the scalar model of ARS222
  with the C1c placements. The first was written before E59 was known. The
  second adds an inexact parent Jacobian.
