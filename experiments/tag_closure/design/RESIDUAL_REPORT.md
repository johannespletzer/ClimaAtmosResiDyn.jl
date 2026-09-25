# G4.4: the residual report of the energy source tags

Written on 2026-09-25. G4.4 asks for four additions to the energy source
tags' closure check: a rate and a settling forecast (synergy 4), the
residual's vertical and local maxima, the offset's headroom (U9), and an
overlay-bound diagnostic (A5). They describe the residual. None is a verdict
(G4.3, [G4_CLAIM_CONTRACTS.md](G4_CLAIM_CONTRACTS.md)). All are diagnostics:
they read the state and write their own fields and tables.

Built on `claude/energy-claims-budget`, from #115
(`claude/energy-source-throughput`), with #112's commit cherry-picked
(section 6). #115 is needed: synergy 4 reuses its per-tag ledger machinery.

`R = E − Σ_partition tags` is the residual per cell, `E = ρe_tot + c·ρ`, and
`G = ∫|R|` the gross residual, as the closure table has it.

## 1. Synergy 4: the flush and the level the residual settles at

The loss rule takes from every tag by its share, so a bracket with a loss
`Δ⁻` changes `R` by `−(R/E)·Δ⁻`: it flushes the residual (E60). So `G` obeys
`dG/dt = P − λ·G`, with `λ` the loss rate weighted by `|R|` and `P` what
everything else makes. `G* = P/λ` is where the two would balance.
`analysis/increment/v2_sphere.py` estimated `λ` offline, from hourly records
that are net over the hour.

**In the run, exactly.** A new state ledger, `e_src_led_src_res`, the
residual's own source ledger. At each source bracket it takes the bracket's
increment of `E` less what the partition's tags took:

    Δ − Σ_partition (M_i·Δ⁺ − φ_i·Δ⁻) = (1 − Σ M_i)·Δ⁺ − (1 − Σ φ_i)·Δ⁻

With masks that sum to one it is `−(R/E)·Δ⁻`, the flush. It is a state field
beside `e_src_led_src_<name>` (#115), under
`energy_source_tag_ledger_per_tag: true`: the stepper weights it as it weights
the tags, step 2's callback takes its per-step gross `F = Σ_steps |ΔL|`, and
step 3's checkpoint carries `F`. The tags' own tendencies are computed as
before; the ledger recomputes the partition's changes in a broadcast of its
own, so they cannot move.

**Audit columns**, from the previous check `(t₀, G₀, F₀)` and this one:

  - `flush_gross`: `F`, J, cumulative;
  - `flush_rate`: `λ = (F − F₀) / (½(G + G₀)·(t − t₀))`, per day;
  - `production_rate`: `P = (G − G₀ + F − F₀)/(t − t₀)`, J per day;
  - `settling_level`: `G* = P/λ`, J; `settling_ratio`: `G*/G`.

The first row, and the first after a restart, have no previous check and
write `NaN`. So does a check with `G` or `F` not grown.

**What it does not say.** `λ` is not constant: on V2 it ran from 0.0105 to
0.0165 a day (E74). `G*` is an order of magnitude, not a prediction. `F`
counts the flush only while `R` keeps its sign within a step, and a mask sum
that is not one adds `(1 − Σ M_i)·Δ⁺` to it; smooth complementary masks sum
to one to rounding. G4.6's budget uses `e_src_led_src_res` per layer too.

## 2. Vertical and local maxima

Audit columns:

  - `residual_max`: the largest `|R|/ρ` in the domain, J/kg;
    `residual_max_z`: its height (the highest, where cells tie);
  - `residual_peak_level`: the level whose layer holds the largest part of
    `G`, counted from the surface; `residual_peak_fraction`: that part over
    the sum of the layers; `residual_peak_z`: the level's area-mean height.

E39 needed a script to find that 69% of a sphere's gross sat in its top two
levels. One reduction per level, collective, at the audit's cadence only.

## 3. U9: the offset's headroom, in the closure table

The closure table shows `nonpositive_fraction`, which moves only once a cell
has crossed `E ≤ 0`. Two columns show the margin before that:

  - `headroom_min`: the smallest `E/ρ = e_tot + c` in the domain, J/kg,
    reduced across processes;
  - `headroom_min_z`: its height.

They go after the spin-up columns and before #112's `void`, so the columns
the integration tests read by position keep their places, and `void` stays
last. The energy source family only. **Not built:** U9's optional
`abort_above` on `nonpositive_fraction`. Under #112 a diagnostic never ends a
run by default. The existing warning on a non-positive parent stays.

## 4. A5: the overlays' bounds, in the audit

The overlays are the tags that carry sources. They overlay the partition, so
each is bounded by the partition's sum in its cell, `Σ_partition tags`. A5 read
this way ("a member exceeds its group's sum"):

  - `overlay_negative_mass_fraction`: the air mass where any overlay is
    negative, over the domain's air mass (E36's frozen negatives);
  - `overlay_excess`: `∫ Σ_overlays max(tag − Σ_partition, 0)`, J;
  - `overlay_excess_mass_fraction`: the air mass where any overlay exceeds the
    partition's sum.

A narrower reading, where the group is a set of overlays whose labels
partition the new energy (`rad`, `sfc`, `sub`, `mp`), needs the configuration
to declare such groups; it does not. Owner question 2.

## 5. Tests

Unit (`test/energy_source_tags_tests.jl`, both float types):

  - the residual's source ledger equals `Δ − Σ_partition change` bit for bit,
    and `−(R/E)·Δ⁻` to rounding with complementary masks; nothing without the
    key; the tags' tendencies are the same bit for bit with and without it;
    the name lists and the state include it; the throughput leaves it out;
  - the report on a column with set fields: the local maximum and its height,
    the peak level, its fraction and height against sums by hand; the
    headroom; the overlays' fractions and excess; the forecast from two
    checks, and `NaN` on the first;
  - the closure table's column order: the spin-up columns keep positions 10 to
    12, and `void` stays last.

Integration (`test/tagged_water_increment_integration.jl`, group
`tagging_water_increment`, on the EDMF column with both families' ledgers per
tag): the residual ledger exists, its gross is finite and non-negative, the
audit writes the report's columns, and the model's fields are unchanged, as
that file already checks.

## 6. For the owner

 1. The forecast's two columns are in the audit only. Whether a `settling_ratio`
    above some level should warn is a warning level, which G4.5 keeps apart
    and leaves to the owner.
 2. A5's reading of "its group's sum" as the partition's sum.
