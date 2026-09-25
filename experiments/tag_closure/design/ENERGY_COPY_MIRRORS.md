# The energy copies' mirrors of `mseʲ`: the design note of G4.1 and G4.11

Written on 2026-09-25. G4.1 asks for every writer of `mseʲ` to be listed, as
WP3's numerics review listed those of `q_totʲ` (N5), and for each to be
mirrored on the energy copies or bounded. Rev. 2 makes the mirrors complete
before the energy copies serve as the audit, at the 8 tags OD8 keeps (with
G4.11). `file:line` references are to `main` at `3eac4d44`.

## 1. What the copies should follow

Under `energy_source_tag_updraft_copy: true` each tag has a copy `e_src_<name>`
in the updraft, a specific value that starts as `ρe_srcᵢ / ρ`. The model moves
it as any updraft tracer (`docs/src/energy_source_tags.md`). The grid mean's
tags take the model's tracer flux, `Σₖ ρᵏaᵏ(u³ᵏ − u³)(εᵢᵏ − ε̄ᵢ)`.

The updraft's energy per unit mass, in the tags' terms, is
`Aʲ = mseʲ + Kʲ − p/ρʲ + c` (`energy_source_tags.jl:1956`, the default mode's
exchange). The partition's copies stand for it. So a process that changes
`Aʲ` should change the partition's copies by the same amount, and give each
copy its part by the grid mean's attribution rule. A process that changes
`mseʲ` and not `Aʲ` needs no mirror.

The copies have no residual diagnostic and no repair today, unlike the water
copies (`q_tag_copy_res`, `q_tag_upfix_<name>`). So nothing measures how far
the partition's copies are from `Aʲ`.

## 2. The inventory

Every writer of `Y.c.sgsʲs.:(j).mse` or its tendency on `main`, and what the
copies get.

| #  | process                                   | writer of `mseʲ`                         | on D4 (DYCOMS, 1M, a column) | the copies get                                                                 | status |
|:-- |:----------------------------------------- |:---------------------------------------- |:--------------------------- |:------------------------------------------------------------------------------ |:------ |
| 1  | vertical advection by the updraft          | `advection.jl:364`                        | yes | the SGS tracer loop, `advection.jl:376`, with `edmfx_tracer_upwinding`; `mseʲ` uses `edmfx_mse_q_tot_upwinding` | mirrored; the two schemes may differ, bounded |
| 2  | buoyancy, `u₃ʲ ρ_diffʲ ∇Φ`                 | `advection.jl:353`                        | yes | nothing | energy the updraft trades: its velocity equation takes the part `1 − α_b` from `Kʲ` (`solve_sgs_u₃_implicit_stage_analytic!`), and the rest is work through the non-hydrostatic pressure. No tag's label; not mirrored; bounded by `e_src_copy_res` |
| 3  | horizontal advection                        | `advection.jl:63`                         | no (sphere) | the SGS tracer loop, `advection.jl:137` | mirrored |
| 4  | entrainment                                 | `edmfx_entr_detr.jl:615`                  | yes | `edmfx_entr_detr.jl:622`, the environment's value | mirrored |
| 5  | the EDMF diffusive flux's updraft mirror    | `edmfx_sgs_flux.jl:379`                   | yes (`edmfx_vertical_diffusion`) | the grid-mean tag's specific diffusive tendency, `edmfx_sgs_flux.jl:415` | mirrored in form; the tags' operator is a tracer's, `ρe_tot`'s is not. The energy counterpart of water's `diffusion_up` leak. Bounded |
| 6  | its horizontal counterpart                  | `edmfx_sgs_flux.jl:547`                   | no (sphere) | the same, horizontally | as 5 |
| 7  | hyperdiffusion                              | `hyperdiffusion.jl:368`                   | no (sphere) | `hyperdiffusion.jl:600` | mirrored in form; operators differ. Bounded |
| 8  | Rayleigh sponge                             | `remaining_tendency.jl:143`               | when on | `remaining_tendency.jl:151` | mirrored |
| 9  | radiation, RRTMGP only                      | `radiation.jl:556`                        | no: DYCOMS radiation writes `ρe_tot` only | nothing | **missing: mirror (M3)** |
| 10 | 0M microphysics, `dq_totʲ (e_hlpr − e_int(Tʲ))` | `microphysics/tendency.jl:126`       | no (1M writes no `mseʲ`) | nothing | **missing: mirror (M4)** |
| 11 | the surface enthalpy flux into the updraft's lowest cell | `surface_flux.jl:122`        | yes | nothing: the grid-mean tags' surface flux reaches no copy | **missing: mirror (M1)** |
| 12 | the surface mass flux's relaxation toward the buoyant value, lowest cell | `edmfx_boundary_condition.jl:376` | yes | nothing | **missing: mirror (M2)**; water's mirror 3 |
| 13 | the filter                                  | `mass_flux_closures.jl:286`               | yes (`edmfx_filter`) | `mass_flux_closures.jl:303`: toward the grid mean where `ρaʲ` is negligible, as `mseʲ`; elsewhere a clamp to `[0, ρe_src/ρaʲ]` that `mseʲ` does not have | mirrored where `ρaʲ` is negligible; the clamp bounded (water's mirror 5 is a repair) |
| 14 | pressure work                               | `pressure_work.jl:17`                     | — | — | a no-op in the model; nothing to mirror |
| 15 | the updraft's 1M sedimentation              | none for `mseʲ` (`q_totʲ` only)           | — | none | consistent; nothing to mirror |

`Aʲ`'s other parts, `Kʲ` and `p/ρʲ`, change with the updraft's momentum and
density, which write no `mseʲ`. Row 2 is the one place where they meet it.

## 3. The mirrors

Each mirror takes the model's own increment of `mseʲ` from the process,
`Δʲ`, recomputed from the same flux and operator, and gives it to the copies
by the grid mean's bracket rule (`_accumulate_energy_source_tag!`):
  - a tag that receives the process's label gains its mask times `max(Δʲ, 0)`
    (a pure region tag receives every label; a tag without a region has mask
    one);
  - every copy loses its share of `min(Δʲ, 0)`. The share is the copy's
    clamped fraction of the partition's copies' sum, `S_Pʲ = Σᵢ∈P max(χᵢʲ, 0)`,
    so the partition loses exactly `min(Δʲ, 0)`.
So the partition's copies change by exactly `Δʲ` where the masks partition
the domain. The offset does not enter: a specific increment carries no `c`.

  - **M1, the surface flux** (row 11), label `surface_flux`, lowest cell,
    `Δʲ = −btt / ρʲ` with `btt` the grid mean's boundary tendency of `h_tot`.
    In the remaining tendency, after `surface_flux_tendency!`, as
    `water_tag_copies_surface_flux_tendency!`.
  - **M2, the relaxation** (row 12). `mseʲ` relaxes toward `mse_b = mse̅ +
    C√σ²` at the rate `S / max(ρa, ρ a_min)`. Each copy relaxes at the same
    rate toward `ρe_srcᵢ/ρ + φ̄ᵢ (mse_b − mse̅)`: its grid-mean value plus its
    grid-mean share `φ̄ᵢ` of the buoyant excess, the partition's shares
    renormalized. So no copy gets the excess as its own, as water decided for
    its mirror 3: the surface-flux tag gets only its share. In the implicit
    tendency, after `edmfx_boundary_condition_tendency!`, with the rate on
    each copy's Jacobian diagonal, as the water copies have it
    (`update_sgs_boundary_condition_jacobian!`).
  - **M3, radiation** (row 9), label `radiation`, `Δʲ = −divᵥ(F_rad) / ρʲ`,
    after `radiation_tendency!`, RRTMGP modes only.
  - **M4, 0M microphysics** (row 10), label `microphysics`, `Δʲ = dq_totʲ
    (e_hlpr − e_int(Tʲ))`, after the 0M `microphysics_tendency!`, beside
    `water_tag_copies_microphysics_tendency!`.

The mirrors read the state and write only the copies' tendencies. The model's
fields do not change, bit for bit.

**A residual diagnostic.** `e_src_copy_res`, `ρaʲ (Aʲ − Σᵢ∈P χᵢʲ)`, per
cell, the energy counterpart of `q_tag_copy_res`. It bounds rows 1, 2, 5 to 7
and 13 together, which are not mirrored. No repair is added: a repair of the
copies would be a new intervention on the audit, and the OD3 repair row
would then have to cover it.

## 4. Attribution choices

  - M1, M3 and M4 use the grid mean's own labels and rule. No new choice.
  - M2 gives the buoyant excess by composition, as water's mirror 3 does, not
    to the surface-flux tag. The excess is the surface layer's buoyant tail,
    so one could argue it is surface-flux energy. Water chose composition
    because the excess is air the cell holds, not new water. The same holds
    for energy. The note builds composition, as water has it. *The owner
    decided composition on 2026-09-25.*
  - Row 2 is not mirrored. Its part `1 − α_b` moves energy between `mseʲ`
    and `Kʲ` within `Aʲ`. Its part `α_b`, with the pressure drag, is work
    the updraft exchanges with the environment through pressure: a transfer,
    not a source, and no tag is labelled with it. If `e_src_copy_res` shows it
    matters, a mirror would share it by composition, not by a label.

## 5. Tests and validation

**Unit** (`test/energy_source_tags_tests.jl`), on a small EDMF column state
with copies:
  - each mirror changes the partition's copies by exactly the model's own
    `Δʲ`, in both signs, in Float32 and Float64;
  - a tag gains only where it receives the label, by its mask; every copy
    loses by its share;
  - M2's targets sum to `Ā + (mse_b − mse̅)` over the partition;
  - each mirror is a no-op without copies.

**Integration:** the existing groups with copies (`tagging_source_updraft`,
`tagging_source_edmf`) keep the model's fields bit for bit against an untagged
twin with the mirrors on.

**Validation jobs**, pre-registered here before any run: D4 with the 8
energy tags of `g415_inc_d4_after` under `enthalpy_increment`, one day, with
the model's fields written hourly for parity (`configs/g411_d4_*.yml`):

| run | code | what |
|:--- |:---- |:---- |
| `g411_d4_copies`        | the mirrors' run tree | copies with the mirrors; writes `e_src_copy_res` |
| `g411_d4_copies_dt60`   | the mirrors' run tree | the same at `dt` 60 s, OD3's refinement row |
| `g411_d4_copies_before` | `main`'s run tree     | copies without the mirrors |
| `g411_d4_default`       | the mirrors' run tree | the default mode, the other side of the comparison |
| `g411_d4_untagged`      | the mirrors' run tree | the parity twin |

D4 exercises M1 and M2 only: its radiation is DYCOMS's, which gives `mseʲ`
nothing, and its microphysics is 1M. M3 and M4 are covered by the unit tests
until a RRTMGP or a 0M case with copies runs.

`analysis/increment/g411_eligibility.py` scores them:
  - **The window.** OD2's rule on the partitioned total's hourly tendency.
    Where it finds no end of startup, as on a steadily cooled column, OD2's
    table's expectation for D4 holds, the first hour. The script says which.
  - **The scale.** OD4's gross source throughput over the window. Which
    source OD4 uses is still the owner's (DECISIONS.md). Until then the
    script takes the process records of the four source processes, whose
    hourly samples are net within each hour. That is a lower bound on the
    throughput, so each percentage is an upper bound, and a pass holds under
    either source.
  - **Eligibility**, OD3's comparator rows, for each copies run: its own
    closure residual over the window at most 0.02% of the throughput (a tenth
    of the energy closure row, as the water row is a tenth of its budget);
    its repair (`repair_moved`) at most 0.20% of it a day; the `dt` 60 s
    twin's repair per day at most 1.1 times the 120 s run's.
  - **Default against copies** per tag at 24 h: L1 at most 2% and L∞ at
    most 5%, or, for a tag under 1% of the partition, `∫ρ|Δe|dz` at most
    2e-4 of the throughput. Scored where the copies are eligible, and
    reported as "comparator not eligible" otherwise.
  - `e_src_copy_res` over the day: what rows 1, 2, 5 to 7 and 13 leave.
  - **Parity:** every model field of each tagged run against the untagged
    twin, bit for bit.

**Expectation, not a pass criterion.** G4.15's default-mode D4 day repaired
6.9% of this throughput a day (its `repair_moved`, against the process
records' lower bound). If the copies repair as much, they fail the repair row
with or without the mirrors, and the comparison stays "not eligible". The
mirrors would then show in `e_src_copy_res`, not in eligibility.

**Jobs**, `hpda2_compute`, 2 CPUs, 48 GB, `--time=08:00:00` for the copies
runs (E73: 8 energy copies built in 3504 s cold) and `04:00:00` for the
others, with `submit_g3.sh` and
`DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl`, as G4.15's D4
day.
