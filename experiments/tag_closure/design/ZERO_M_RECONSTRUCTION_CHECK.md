# WP4a-V: is the default mode's reconstructed composition closer to the truth than the grid rule?

Written on 2026-09-24, before any run, for the owner's review of #104
(finding 2), approved as part of Batch 3 the same day. The criteria, and the
threshold the owner left open, are fixed in the record by this commit. The
runs start after it. The owner may change the threshold before #104 merges;
the numbers will not change.

## 1. The question

Under 0M and prognostic EDMF, #104 splits the rain-out by subdomain. In the
default mode the model holds no subdomain composition, so the split
reconstructs one from the exchange's plume: `φᵏ = S (φ̄ᴺ + Δφᵏ)`. W26 found it
moves the tags by under 0.5% on TRMM and leaves the agreement with the copies
as it was. That does not say whether the reconstruction is closer to the
truth than the grid rule, `φᵏ = φ̄`.

## 2. The design

The candidates are compared on one state, not across runs. A copies run holds
the grid tags and the updraft's own copies. At every step, on that run's
state, three shares per partition tag and subdomain are computed:

  - **grid rule:** `φ̄ᵢ = water_tag_fraction(ρq_tagᵢ, ρq_tot)`, both subdomains;
  - **reconstruction:** `SplitShare` of #104 on the plume and the share
    differences that `water_exchange_inputs!` and `ShareDifferences` give for
    the run's grid tags, exactly as the default mode's split takes them;
  - **reference:** the copies' own shares: `water_tag_fraction(χʲᵢ, q_totʲ)`
    in the updraft, and in the environment the copies' implied value
    renormalized over the partition and times `S`, as the copies' split takes
    it, or the grid share where that is not defined.

The error of a candidate for tag `i`, over the run:

    E_cand,i = Σ_steps Σ_cells Σ_k |Δᵏ| |φᵏ_cand,i − φᵏ_ref,i| / Σ_steps Σ_cells Σ_k |Δᵏ|

with `Δᵏ` each subdomain's rain-out (`_rainout_updraft`,
`_rainout_environment`). Only the rain-out that the split distributes
weights it.

## 3. The case

W26's column: TRMM_LBA, 0M, prognostic EDMF, 82 levels, `dt` 150 s, ARS222,
6 h (`configs/w4a_trmm0m_copies_6h.yml`), with region tags `pbl` below 1 km
and `free` above it (200 m tanh edge), and `evap`. Deep convection lifts
boundary-layer water into the updraft, where it rains out above 1 km. So the
updraft's composition differs from the grid mean's where the rain forms. The
copies start from the default mode's plume (the D4-W driver's rule), so both
candidates and the reference start from one composition.

**Valid** only if the grid rule's error is not negligible: `E_grid ≥ 1e-2`
for `pbl` on the base rung. Otherwise the case does not discriminate, and
that is the result.

## 4. The rungs

The reference is the copies at 10 Newton iterations, since known issue 4 says
one iteration is not a validated audit under 0M.

| rung | `dt`  | levels | Newton |
|:---- | -----:| ------:| ------:|
| base | 150 s | 82     | 10     |
| N2   | 150 s | 82     | 2      |
| dt75 | 75 s  | 82     | 10     |
| z164 | 150 s | 164    | 10     |

N2 checks that the reference has converged: its shares against the base's
should differ by much less than `E_grid`. It is reported, and the verdict
below also applies to it.

## 5. Passes when

For `pbl` and `free`, on every rung:

    E_recon ≤ 0.75 · E_grid.

That is, the reconstruction lowers the rain-weighted share error by at least a
quarter. **The 0.75 is my proposal**; the owner left "material" open.

Reported beside the verdict:

  - `E` for `evap` too (a source tag, clamped to [0, 1]);
  - the partition repair's and the copies' repair's ledgers (`q_tag_fix`,
    `q_tag_upfix`), and the copies' residual (`q_tag_copy_res`);
  - the fraction of the rain-out in cells where the exchange's bound binds
    (room negative, or the partition's blend factor below one);
  - the grid rule's and the reconstruction's `E` per hour.

## 6. What follows

Pass: the docs say the reconstruction was closer on this case, with the
numbers. Fail: the owner chooses between keeping it as a modelled estimate
(the docs as they are now) and reverting the default mode to the grid rule.

The code is #104 at `dfd93d7c`. The probe is
`analysis/water/w4v_reconstruction_probe.jl`, run against the run tree
`-wedmf4a-run` (the record merged with #104).
