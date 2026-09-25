# G4.6: the D4 process budget, pre-registered

Written on 2026-09-25, before any run. It is synergy 6 (one combined budget of
the process records, the increment ledger and the repair) and C4 (`c·Δρ` from
processes the tags do not bracket), on the D4 column. The owner set the
acceptance test on 2026-09-23 (G4_TODO, "Prepared: item 6"); this note fixes
how each part of it is computed. Nothing may change after the first run
except by a dated amendment here, before the result is read.

The code is `claude/energy-claims-budget` (#115 with #112's commit and G4.4 to
G4.5): it adds `e_src_led_src_res`, the residual's source ledger, which the
budget needs per layer. The script is `analysis/increment/process_budget.py`.
The configs are `configs/g46_d4_*.yml`.

## 1. The question

On D4 under `enthalpy_increment`, does the change of the partitioned total
`E = ρe_tot + c·ρ` split into named terms: what each process did, with `c`
times its change of mass; what the implicit solve left; what the repair moved;
and a named remainder? And the same for the residual `R = E − Σ partition
tags`, the part the tags do not hold? E23's 1.37 MJ/m² is not part of it: E26
settled that.

## 2. The terms

Per cell, `ρ` from `rhoa`, each field below times `ρ`; a layer's value is that
times its thickness, and the column's the sum over layers. All are cumulative
from the start, so a term over `(0, t]` is its value at `t`.

| symbol | what | output |
|:------ |:---- |:------ |
| `E` | the partitioned total | the closure table's `total` (the column); `rhoa`, `ta`, not needed per layer |
| `R` | the residual | `e_src_res` |
| `L_i` | partition tag `i`'s source ledger (#115) | `e_src_led_src_strat`, `e_src_led_src_tropo` |
| `L_R` | the residual's source ledger (G4.4) | `e_src_led_src_res` |
| `B = Σ L_i + L_R` | every source bracket's increment of `E`, with its `c·Δρ` | from the above |
| `I` | what the follower left in place | `e_src_inc_left` |
| `F_S = Σ F_i` | what the repair changed the partition's sum by | `e_src_fix_strat`, `e_src_fix_tropo` |
| `P_e,p` | process `p`'s energy record | `e_prc_<p>` |
| `P_q,p` | process `p`'s water record | `q_prc_<p>` |
| `M` | the column's mass | `∫rhoa dz` |

## 3. The identities

**II, the residual, per layer and for the column:**

    R(t) − R(0) = L_R(t) + I(t) − F_S(t) + X_II(t)

`L_R` is the loss rule's flush (G4.4); `I` the follower's left part (E64);
`F_S` the repair's change of the partition's sum, zero except where it zeroes
every tag. `X_II` is the named remainder: whatever else moved `R`, which can
only be a mismatch between the tags' and the parent's explicit transport and
sedimentation. E64 found the column's `X_II` near 1 J/m² with the flush
estimated from hourly records; with `L_R` exact it is expected smaller.

**I, the partitioned total, for the column only** (transport moves energy
between layers and is in no record):

    E(t) − E(0) = B(t) + P_e,precipitation(t) + c·M_U(t) + X_I(t)

  - `B` holds every bracketed source with its `c·Δρ`, as the tags saw it.
  - `P_e,precipitation` is the energy the parent's sedimentation took out
    through the surface; the tags take sedimentation as transport, not as a
    source.
  - `M_U` is the column mass change no bracket saw: C4. It is measured from
    the pair of runs at `c` and `2c`, which share their atmosphere bit for bit
    (E71): `c·M_U = c·ΔM − (B(2c) − B(c))`, with `ΔM` from `rhoa`.
  - `X_I` is the named remainder: unbracketed changes of `ρe_tot`, such as
    the implicit path's surface deposition of precipitation, and the records'
    one-iteration lag (E43: −5.29 J/m² a day on a 1M column).

By construction `X_I` is the same at `c` and `2c`, so identity I cannot fail
at `2c`. Identity II can.

**C4, a second measure.** The follower cannot move a column's total, so an
unbracketed mass change's `c·ΔM` should land in `I`'s column total:
`I_col(2c) − I_col(c)` against `c·M_U`. And a third, from the records:
`c·(ΔM − Σ_p P_q,p − (−∫pr dt))`, the mass change the water records and the
surface precipitation do not explain.

## 4. The acceptance test

The owner's (2026-09-23), with the reading fixed here:

  - **A1.** Every term of II per layer and for the column, and of I for the
    column, is reported with its sign, at 1, 6, 12 and 24 h.
  - **A2.** At 24 h, `|X_II|` for the column is at most 1 J/m² at `c`.
  - **A3.** A2 holds at `2c`.

Checks set here, before the run:

  - **A4, repair never a parent source.** `∫|F_S| dz` at 24 h at most 1 J/m²,
    at `c` and `2c`.
  - **A5, C4's two measures agree.** `I_col(2c) − I_col(c)` within 10%, or
    1 J/m², of `c·M_U`. If they disagree, `c·M_U` goes somewhere else, and the
    budget names where by the per-layer II.
  - **Parity.** Every model field of both tagged runs bit for bit the untagged
    twin's, at every output (`ta`, `rhoa`, `hus`, `clw`, `cli`, `husra`,
    `hussn`, `wa`, `pr`, `hfls`, `hfss`, the updraft's fields, `tke`). A run
    that fails parity is void, and the budget is not read.

Reported, not judged: `X_I` and its candidates; `c·M_U` per day and over the
day's gross source throughput Θx (the audit's `source_throughput`); the
per-layer II at 1 and 6 h (startup); the forecast columns of G4.4.

**Verdicts:** A2 to A5 each *pass* or *fail*; *not assessable* only if a run
fails, or fails parity, naming which.

## 5. The runs

Three D4 days from one run tree, the record with `claude/energy-claims-budget`
merged. Each is `g411x_d4_default`'s configuration (8 tags,
`enthalpy_increment`, one Newton iteration, `dt` 120 s, 1M implicit, the
repair, the per-tag ledgers) with every record and the budget's outputs:

| config | offset | purpose |
|:------ | ------:|:------- |
| `g46_d4_budget` | 110,495 J/kg | the budget at `c` |
| `g46_d4_budget_2c` | 220,990 J/kg | the budget at `2c`; `M_U` from the pair |
| `g46_d4_untagged` | — | the parity twin: no tags, no records |

`energy_process_record` lists radiation, surface flux, subsidence,
microphysics and precipitation; `water_process_record` the water labels the
column has, surface flux, subsidence and microphysics (sedimentation has no
water label; `pr` averaged over each hour stands for it). Cost: about 1.5 h
each on `hpda2_compute` with 2 CPUs and 48 GB, as the `g411x` runs; asked for
4 h.

## 6. What it cannot say

  - One column, one day, one Newton iteration, one time step.
  - `X_I` mixes the records' lag with unbracketed processes; a converged twin
    would separate them, and is not run here.
  - If A2 fails, the budget names the layers; it does not name the process.

## 7. For the owner

 1. C4's outcome decides "share it as transport or document its size". The
    budget measures it; the choice is the owner's.
 2. If A3 fails at `2c` while A2 passes, a `c·Δρ` the tags do not see remains
    in `R`; E71 predicted that place.
