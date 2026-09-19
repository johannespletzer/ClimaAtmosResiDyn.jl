# Review: the updraft-gap bound and its days 1-3 reading

Reviewed on 2026-09-19. Read-only; nothing in either repo was edited.

- Script: `ClimaAtmosResiDyn.jl/experiments/tag_closure/analysis/increment/updraft_gap_bound.jl` (136 lines)
- Output: `.../output/g2_v2_sphere/updraft_gap_bound_days1-3.txt`
- Model code: `ClimaAtmosResiDyn-inc-run3` at `04d63916`
- Checkpoints: `g2_v2_sphere/output_0000/day{1..4}.0.hdf5` (reached through the `output_active` symlink)

## Verdict

The formula is sound. `M·(φʲ − φ)·e`, upwinded and then divergenced, is the
exact difference between an updraft copy and the donor sharing. The one change
it needs is `e → eʲ/(1 − σ)`, worth about +15-20%. It does not double count.

It is not a bound, though. It is an order-of-magnitude estimate of the
*initial rate* at which a copy would diverge, evaluated on the as-built state.

The largest error is the face reconstruction. The script upwinds. The parent's
SGS flux, and any SGS tracer that would carry a copy, uses V2's
`edmfx_sgsflux_upwinding: none`, which is centred. On this 10-level grid the
updraft spans only 2-4 cells, and upwinding sets the gap to zero at the lowest
interior face, which carries the largest mass flux. So:

- the tropical numbers are low by a factor of 2.3-4;
- "elsewhere under 4%" is an artifact. Extratropical updrafts are 1-2 cells
  deep, where upwinding gives no gap by construction.

The comparison is also misleading. 86-100% of "changed" is the tags' net growth
from zero, not transport. "Moved" counts each relocated joule twice.

## What I ran

- The script once, for day 1: it reproduces the stored day-1 block exactly, in 70 s.
- `review/checks.jl` for days 1 and 3: operator checks, the f diagnostics, an
  as-built comparator, centroid heights and area-weighted turnover. Logs are
  `checks.log` and `checks_day3.log`.
- `review/sensitivity.jl` for days 1 and 3: the gap under five variants.
  Logs are `sensitivity_day{1,3}.log`.
- `review/column.jl` → `sensitivity_setup.jl`: one strong tropical column and
  one extratropical column, face by face. Log is `column_day3.log`.

Day 2 was not rechecked beyond the stored output.

## 1. Method

### The exact difference

Take one updraft with mass fraction σ = ρaʲ/ρ, mass flux M = ρaʲ(wʲ − w), and
mass-flux balance for the environment (ρa⁰(w⁰ − w) = −M). Write ε_k = φ_k·e for
tag k's specific content, with e = E/ρ.

**With a copy.** The difference-form flux summed over updraft and environment is

  M(ε_kʲ − ε_k⁰) = M(φʲeʲ − φ̄ē)/(1 − σ).

**As built.** The tag takes the parent's total flux times the donor's share:

  φ_d·M(Xʲ − X̄)/(1 − σ), with X = h + c·q_tot, the quantity the parent reconstructs (lines 1480-1530).

**The difference.** Taking X ≈ e:

  copy − built = M/(1 − σ)·[(φʲ − φ_d)eʲ − (φ̄ − φ_d)ē].

With φ_d = φ̄ of the same cell, this becomes **M(φʲ − φ̄)eʲ/(1 − σ)**. So:

- The donor term cancels exactly against the φ̄ part of the copy's flux. There
  is no double counting, as long as the donor and φ̄ come from the same cell.
  Upwinding δφ·e from the cell the flux leaves ensures that.
- The factor is eʲ/(1 − σ), not ē. In the tropics eʲ − ē ≈ hʲ − h̄ is only
  0.5-1.9 kJ/kg, against e = 47-68 kJ/kg, so 1-3%. The 1/(1 − σ) factor matters
  more: σ has median 0.06, 90th percentile 0.10 and maximum 0.7 where f is
  defined. Together they raise the tropical gap by 10-23% (case 5 below).
  Elsewhere they double it on day 1, from 0.035 to 0.072 for `sfc`.
- X ≠ e leaves a residual M[Δ(p/ρ) + c·Δq_tot]/(1 − σ). Any copy has to share
  that out somehow, so "the copy" is not unique. The residual is about 1% of the
  gap and does not matter for the estimate.

### The assumptions

- **Updraft density as the grid mean's.** The code never makes this
  approximation. `ρa` is ρʲaʲ itself, and `q_env` uses ρ − ρa, which is exactly
  ρa⁰. See nit N1.
- **f from the q_tot mixing line.** The line treats the updraft at z as a mix of
  the updraft at level 1 and the environment at z only.
  - Entrained air really comes from all levels in between, and is moister than
    the environment at z. That biases f high.
  - That air also has a higher φ than φ(z). If φ and q_tot are affine in the
    environment, the two errors cancel exactly. Only V3 can test this.
  - Where the line holds, it agrees with an mse mixing line to a median
    |Δf| of 0.005-0.04 (day 1) and 0.01-0.07 (day 3, levels 2-4).
  - It fails in two places:
    1. **Precipitation.** On day 3, rain plus snow make up 13% of the updraft's
       q_tot at level 4 (3.4 km) and 54% at level 5 (5.2 km). There f_q = 0.44
       while f_mse = 0.23. Sedimentation takes water out of the updraft
       (`advection.jl:399-442`).
    2. **Points off the line.** On day 3, 13% of the tropical updraft points at
       level 2 and 26% at level 3 have a mixing ratio above 1. They are clamped
       to f = 1, which gives them the largest δφ.
  - A near-dry updraft, or q_env close to qʲ(level 1), makes f ill-conditioned.
    But φ(z) ≈ φ₁ there, so δφ stays small. Fewer than 1% of points fall below 0.
- **φʲ = f·φ₁ + (1 − f)·φ(z).** This is consistent with the definition of f.
  At level 1 it gives δφ₁ ≡ 0, which matters for the reconstruction (W1).
- **The upwind face flux.** It equals the exact difference only for a copy that
  is upwinded too. V2's own reconstruction is centred. See W1.
- **The divergence with `ᶜadvdivᵥ`.** Correct. See section 3.

## 2. Findings

### Wrong result

**W1. The reconstruction does not match the model's, and it zeroes the gap at
the face that matters most.** `updraft_gap_bound.jl:72`.

- **What is wrong.**
  - V2 runs with `edmfx_sgsflux_upwinding: none` (the default in
    `default_config.yml:539`). The parent's SGS flux is therefore centred
    (`energy_source_tags.jl:1492-1523`, `_face_value_flux(..., Val{:none})` =
    `ᶠu³ * ᶠinterp(χ)`). So are SGS tracers, which is where a tag copy would
    live (`edmfx_sgs_flux.jl:125-168`).
  - For a centred copy, the exact difference is ½M(δφ_k eʲ_k + δφ_{k+1} eʲ_{k+1})/(1 − σ).
  - Upwinding with δφ₁ ≡ 0 gives zero flux through face 1½ (about 0.84 km).
    That face carries the largest M: ΣM⁺ over tropical nodes is 111-137 there,
    against 77-91 at face 2½ and 11-53 at face 3½.
- **Example.** The strongest tropical column on day 3 (h = 133, lat −9°):

  | Face | M (kg/m²/s) | Upwind gap (W/m²) | Centred gap (W/m²) | As-built tag flux (W/m²) |
  |---|---|---|---|---|
  | 2 | 0.308 | 0 | 212 | 32 |
  | 3 | 0.057 | 78 | 165 | 2.6 |

  Globally, the centred gap is larger than the upwind one:

  | Tag | Tropics, day 1 | Tropics, day 3 |
  |---|---|---|
  | `sfc` | 0.312 → 0.914 (×2.9) | 0.206 → 0.532 (×2.6) |
  | `rad` | ×2.3 | ×2.6 |
  | `new_tropics` | ×2.5 | ×2.5 |
  | `new_extratropics` | ×4.2 | ×3.3 |

  Elsewhere the change is larger:

  | Tag | Elsewhere, day 1 | Elsewhere, day 3 |
  |---|---|---|
  | `sfc` | 0.035 → 1.02 | 0.003 → 0.19 |
  | `new_*` | 0.006-0.008 → 0.15-0.22 | 0.001-0.012 → 0.09-0.12 |

  The extratropical column has its updraft at level 1 only. The level-2 area
  is 5e-4, below the 1e-3 threshold, so both schemes give zero there. Columns
  that reach level 2 but not level 3 get nothing from upwinding.
- **Fix.**
  - Build the face flux with the parent's own `_face_value_flux(ᶠMv, ᶜδφ·ᶜeʲ/(1−σ), dt, edmfx_sgsflux_upwinding)`.
  - Report upwind and centred side by side, as a bracket.
  - State that with 2-4 cells per updraft the estimate is limited by
    resolution.

**W2. "Elsewhere under 4%" does not hold.** Interpretation of output lines
5-30. It follows from W1: under the model's reconstruction, `sfc` elsewhere is
102% (day 1) and 19% (day 3) gross. Drop the statement, or recompute.

### Misleading

**M1. "Changed" is mostly production, not transport.** Lines 117-123.

- **What is wrong.** The source tags start at zero, so |Δtag| is dominated by
  their growth. The signed net change is 86-100% of the gross:

  | Tag | Day 1: net / gross | Day 3: net / gross |
  |---|---|---|
  | `sfc` | 1.12 / 1.15 | 0.43 / 0.49 |
  | `rad` | 1.39 / 1.39 | |
  | `new_tropics` | 1.16 / 1.18 | 0.43 / 0.48 |
  | `new_extratropics` | 1.25 / 1.31 | 0.44 / 0.51 |

  The 1.15 → 0.69 → 0.49 sequence for `sfc` is just the 1/n decline of a
  linearly accumulating tag. "Gap 15-30% against change 40-140%" therefore sets
  a redistribution against an accumulation.
- **Fix.** Compare redistribution with redistribution (section 5):
  - the gap against the tags' own as-built SGS mass-flux tendency;
  - the tag's centroid height, from the gap and from the actual change;
  - or remove production from "changed" using the process records
    (`prc_e_surface_flux`, etc., which are in the checkpoint state).

**M2. "Moved" counts gross |tendency|.** Line 121.

- **What is wrong.** The gap conserves each column. I checked: the column
  integral is below 8e-8 of its |·| integral. So ∫|tendency| is twice the
  energy relocated. The day-1 tropical `sfc` value of 0.31 is a net relocation
  of 16% a day.
- **Fix.** Report ½∫|tendency|, or ∫max(tendency, 0), as "relocated".

**M3. The turnover of "air below 10 km" describes a mass flux that stops at 3.5-5 km.** Lines 89-96 and 100-103.

- **What is wrong.** The updraft (a > 0.1%) does not reach level 5 on day 1,
  and reaches it at only 96 tropical nodes on day 3.
  - ΣM⁺ at face 5 (4.15 km) is 0.05% of face 2's on day 1, and 3% on day 3.
    Face 6 (6.3 km) is at 0.05% on day 3.
  - M_max sits at face 2 or 3 (0.84 or 1.56 km) in 100% of the under-a-day
    columns on day 1, and in 94% on day 3.
  - So the metric divides the mass below 10 km (about 7,000 kg/m²) by a flux
    at about 1 km. What the flux actually cycles is the lowest 3-5 km, and it
    does so about twice as fast.
  - The node-count share is close to the area share: 14.6% vs 13.8% on day 1,
    26.8% vs 26.1% on day 3. In the tropics alone the area share is 27% → 52%.
- **Fix.** Take the mass below the updraft top (the highest face with M > 1% of
  M_max) over M_max, or ρΔz/M per layer. Weight by area.

**M4. The median f is inflated.** Line 97, printed at line 106.

- **What is wrong.**
  - Level 1 has f ≡ 1 by construction, and makes up 38% of the f > 0 points.
    Above level 1 the median is 0.883, not 0.912 (day 1), and 0.903, not 0.969
    (day 3).
  - Points clamped at 1 are a further 3% (day 1) and 13-26% (day 3) of levels 2-3.
  - Per level in the tropics:

    | Level (z) | Day 1 | Day 3 |
    |---|---|---|
    | 2 (1.2 km) | 0.90 | 0.93 |
    | 3 (2.1 km) | 0.87 | 0.91 |
    | 4 (3.4 km) | 0.80 | 0.77 |
    | 5 (5.2 km) | | 0.44 |

  - "Surface air" means air from the lowest cell, which spans 0-500 m over the
    ocean.
- **Fix.** Print f per level above level 1, weighted by M, and print the
  clamped fraction.

**M5. The day-3 f errors fall where the gap deposits the tags.** Lines 61-65.

- **What is wrong.** Covered under section 1: precipitation at levels 4-5,
  where the gap gains (+31% a day at level 4 for `sfc`), and clamped points at
  levels 2-3.
- **Sensitivity.** Dropping the clamped points lowers the day-3 tropical gap
  by 16-27% (`sfc` 0.206 → 0.164). Using f from mse instead changes it by 0-5%.
  On day 1 both change it by at most 4% in the tropics.
- **Fix.** Drop or flag points off the line rather than clamping them. Use mse
  as a second mixing line. Exclude precipitating levels, where
  (q_rai + q_sno)/q_totʲ > 10%.

**M6. It is called a bound, but it is not one.** File name, script lines 1-3,
and `UPDRAFT_GAP.md:82`.

- **What is wrong.** Its error runs both ways:
  - low, because of the reconstruction and the eʲ/(1 − σ) factor;
  - high, because of the clamping on day 3;
  - high, because it takes an instantaneous rate on the as-built state and
    extrapolates it linearly over a day. A copy would re-mix the lowest levels.
    The rates at level 2 are 36% a day under upwinding and more under centred,
    so a copy would saturate within one to two days.

  It is also a single 00 UTC snapshot. Idealized insolation has no diurnal
  cycle (`types.jl:400`), so the time of day does not bias it, but convective
  variability is not sampled.
- **Fix.** Call it an estimate of the initial divergence rate, and say it
  cannot be accumulated over ten days.

### Nits

- **N1** (script lines 13-14). The docstring says the updraft's density is
  taken as the grid mean's. The code uses `ρa` = ρʲaʲ directly. M agrees with
  the model's `ᶠinterp(ρa)(CT3(u₃ʲ) − CT3(u₃))` to 2.5e-5 (day 1) and 3.8e-5
  (day 3), which is the slope terms only. Fix the docstring.
- **N2** (line 21). The claim "Sums to zero over the partition" holds only for
  `tropics` + `extratropics`, and only to 5.8% (day 1) and 4.5% (day 3) of their
  own gap. Unnormalised shares sum to 1 ± 0.005. The source tags are not a
  partition. Normalise the shares by the partition sum, as the model does.
- **N3** (lines 19-20). The docstring says e is taken from the grid mean. It
  should say eʲ/(1 − σ) (section 1).
- **N4** (line 34). `TAGS` omits `mp`. That is harmless, because `ρe_src_mp` is
  identically zero on days 1 and 3.
- **N5** (lines 37-39 and 81). After a restart, days left in an older
  `output_XXXX` are skipped without a message. Search every output directory,
  and warn when a day is missing.
- **N6** (line 135). `eval(Meta.parse(ARGS[3]))` runs arbitrary code. Parse
  `a:b` explicitly.
- **N7** (lines 62 and 64). `1e-3` and `1e-6` are Float64 literals in a
  Float32 broadcast. This is harmless.
- **N8** (`energy_source_tags.jl:1556` vs script line 72). The built code picks
  its donor by the sign of the energy flux F. The script picks by the sign of M.
  Where the anomaly ΔX < 0 with M > 0, which happens near the updraft top, the
  exact difference gains a term (φ_below − φ_above)·MΔX/(1 − σ). That term is
  about ΔX/e ≈ 1-3% of the gap. Not verified numerically.

## 3. Code checks

All of these pass.

| Item | Result |
|---|---|
| Level fields (`Fields.level(qʲ,1)`, `Fields.level(ᶜφ,1)`) broadcast against 3-D fields | Identical to a manual parent-array computation (max difference 0.0 for f and δφ, days 1 and 3) |
| `Geometry.WVector.(u₃)` | Gives physical w on the deep sphere with topography. W = (∂ξ³/∂z)u₃, exact because ∂ξ¹,²/∂z = 0 on hybrid grids. `CT3(WVector(M))` matches the model's contravariant M to ≤3.8e-5 |
| `CA.ᶠupwind1(CT3(...), χ)` | Takes the cell below where M > 0. In this ClimaCore (1.0.0 fork) it defaults to `Extrapolate` at the boundary faces. `ᶜadvdivᵥ`'s `SetValue(CT3(0))` overrides those faces, so the surface and top fluxes are zero |
| Column conservation of the gap | \|∫col tendency\| / ∫col \|tendency\| ≤ 8e-8 |
| Two checkpoints read separately | Coordinate parent arrays (lat, z) are identical, so differencing by parent array is valid |
| Reproducibility | Day-1 output reproduced to the printed digits |

## 4. Interpretation: corrected reading

The per-tag figures below are for the tropics on days 1 and 3, using the
script's gross "moved" measure. Net relocation is half of each.

| Statement | Stored | Reading after this review |
|---|---|---|
| Gap moves 15-30%/day of the surface tags (tropics) | Upwind values: `sfc` 0.31/0.17/0.21, `rad` 0.15/0.08/0.11, `new_*` 0.15-0.29 (range 8-31%) | Net relocation per day under upwinding: 5-16%. Under the model's centred reconstruction: `sfc` 0.91 and 0.53 (net 46% and 27%), `new_*` 0.48-1.23, `rad` 0.29-0.36. The eʲ/(1−σ) factor adds a further 10-23% |
| Against a total daily change of 40-140% | Correct numbers | That change is growth. Against transport, the gap is 3-4× the tags' as-built SGS mass-flux transport under upwinding, and 8-15× under centred. It lifts the tropical `sfc` centroid by 170 (upwind) to 370-470 (centred) m a day. The as-built SGS lifts it by 52-58 m a day. The actual net centroid change is 699 m (day 1→2) and 142 m (day 3→4), and that already includes surface production pulling the centroid down |
| Elsewhere under 4% | Upwind artifact | Under centred, net relocation per day is 9-51% for `sfc` and 4-11% for `new_*` |
| Turnover < 1 day in 15% → 27% of columns | Numbers correct; area-weighted 14% → 26%, tropics 27% → 52% | What turns over is the lowest 3-5 km, not the air below 10 km. The updraft deepens from about 3.4 km (day 1) to about 5 km (day 3) |
| Median surface-air fraction 0.91-0.97 | Inflated by level 1 | 0.88-0.90 above level 1, falling to 0.77-0.80 at 3.4 km and 0.44 at 5.2 km (day 3). 13-26% of the day-3 points at 1-2 km are clamped |

### Caveats that must go with any reading

- Everything happens below the updraft top, about 3.5-5 km. On days 1-3 the gap
  takes the tags from levels 1-2 and deposits them at 2-5 km. Per level, for
  tropical `sfc` on day 3 (upwind):

  | Level | Gap per day |
  |---|---|
  | 2 | −36% |
  | 3 | −6% |
  | 4 | +31% |
  | 5 | +14% |

  `UPDRAFT_GAP.md:41` and `:56-58` ("to 10 km in deep convection", "tropical
  troposphere in 3 to 10 days") do not describe V2 on days 1-3.
- The rate is an initial one. With a copy, the lowest few km would re-mix
  within one to two days. The lasting effect is a different vertical profile
  below about 5 km, not a drift that keeps growing for ten days.
- `rad` is not surface-sourced. Its tropical centroid is at 12-15 km. The gap
  moves only its low-level part.
- The updraft spans 2-4 levels of a 10-level grid, and the result depends on
  the reconstruction by a factor of 2.3-4 in the tropics, and by far more
  elsewhere.
- The numbers come from snapshots of a spinning-up run: the tags started at
  zero and the updraft is still deepening.
- Only V3 (a passive tracer with a real updraft copy) can validate the mixing
  line and the discretization.

## 5. Better measures

1. **Against the same process as built.** Compare ∫|gap| with ∫|as-built SGS
   mass-flux tendency| of the tag, or compare the two face by face. My
   approximation of the built flux is φ_donor × ᶠinterp(M(Δh + cΔq)/(1−σ)),
   with the donor chosen by the flux's sign as in the model. It gives 0.094
   (day 1) and 0.064 (day 3) for tropical `sfc`. Better still, call
   `CA.sgs_mass_flux_of_energy_source_tags!` on a model built from the
   checkpoint, which gives the exact value.
2. **Redistribution against redistribution.** Compare the tag-weighted
   centroid height (or the fraction above the updraft's mid-level) from the gap
   with that from the as-built SGS flux and with the actual change. Remove
   production using the process records.
3. **A flux across a reference face.** Take the gap flux through a fixed face
   (for example about 1.5 km), times a day, over the tag below that face. Say
   what it means: "x% of the low-level tag would be lifted above 1.5 km per day".
4. **Bracket the discretization.** Give upwind and centred values, and the
   eʲ/(1−σ) factor, side by side. Give per-level profiles.
5. **More samples.** Use all daily checkpoints (days 1-9). If affordable,
   restart from one checkpoint for a few hours with hourly checkpoints, to
   average over convective variability.
6. **For turnover.** Use the mass below the updraft top over M_max, weighted by
   area.

## Not verified

- Day 2, beyond the stored output.
- Days 4-9. The updraft may deepen further.
- The as-built comparator (section 5, item 1) is my approximation, not the
  model's function. It assumes mass-flux balance for the environment and
  neglects Kʲ − K̄ in e.
- That a real copy would use the centred path. I inferred this from
  `edmfx_sgs_flux.jl:125-168` (SGS tracers use `edmfx_sgsflux_upwinding`), not
  from running one.
- N8, the donor-sign term, was not computed.
- The direction of the mixing-line bias (entrainment from intermediate levels).
  This is reasoning only.
