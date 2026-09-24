# WP4c's entry gate: the operator decomposition

Written on 2026-09-25, before any run. This is step 6 of rev. 2's order
(ROADMAP.md). It pre-registers G3_PLAN 4.2's gate for WP4c: which leak
corrections are written, and which are deferred with their numbers.

## 1. What the gate decides

Under 1M, the parent's diffusion paths move `q_tot − q_rai − q_sno`, and the
tags move their whole value (G3_PLAN 4.2). `water_tag_leak!` gives each path's
leak in closed form. W18 estimated the grid mean's vertical diffusion leak on
D4-W at 0.9% of the water a day, before the follower existed. The follower
now closes D4-W to 7.3e-6 a day (W31). So the follower may absorb the leak.
Whether a remainder is left, and how much of the follower's work is the leak,
is not measured. The gate measures it, per operator, on one parent state, and
applies the three-part retention rule.

## 2. The operators and the cases

| operator        | what                                                      | WP4c path | configuration key that turns it off |
|:--------------- |:--------------------------------------------------------- |:--------- |:----------------------------------- |
| `vdiff`         | the grid mean's EDMF diffusive flux: W18's leak            | yes       | `edmfx_sgs_diffusive_flux`          |
| `diffusion_up`  | the updraft's mirror of it, on the copies                  | yes       | `edmfx_vertical_diffusion`          |
| `sgs_mass_flux` | the sub-grid mass flux. Not a leak path; a reference for how much of the follower's work is the mass flux's (E59) | no | `edmfx_sgs_mass_flux` |

The other leak paths (`hdiff`, `hyperdiff`, `sponge`, `hyperdiff_up`) are
zero on a column. They are not assessable here and are deferred to the sphere
(step 9), where `q_tag_leak_*` sizes them.

**Cases.**
  - **A. D4-W, default mode**, under the follower: `configs/
    wp4c_gate_d4w_default.yml`, W25's 30-level centred case
    (`w25i_d4w_default_z30_c`) with its own job id. Operators `vdiff` and
    `sgs_mass_flux`. A day. `vdiff` here is W18's 1M diffusion leak, measured
    exactly and per step in place of W18's hourly estimate.
  - **B. D4-W with copies**, under the follower: `configs/
    wp4c_gate_d4w_copies.yml`. Operators `vdiff` and `diffusion_up`. The
    first 12 hours, for the cost (section 6). The copies are the audit (OD8);
    `diffusion_up`'s leak reaches them and their repair takes it out, so it
    bears on the copies' eligibility (OD3's repair row), not on the default.

## 3. The measurement

`analysis/water/wp4c_gate_probe.jl`. The reference runs the case as it is. At
every step `k` it copies the reference's state `Yₖ` and time into trials,
refreshes their cache (the pattern of `w5v_same_atmosphere.jl` and
`w25_probes.jl`), and steps each once. The trials are the case with the
follower and with the tracer transport, each with every operator on and with
one operator off. For each operator `o` and step, from the same `Yₖ`:

| quantity          | how                                                                                                             |
|:----------------- |:--------------------------------------------------------------------------------------------------------------- |
| source            | `dt ∫ρ leak_o(Yₖ) dV`, `water_tag_leak!`; for `vdiff` also per tag, `dt ∫∇·(ρK_h∇(ψᵢ q_p)) dV`, the part the candidate correction would take from the tag |
| actual growth     | `R(on, tracer) − R(o off, tracer)` at the step's end, with `R` the partition's sum minus `ρq_tot`                 |
| follower's correction | each state ledger's change over the step, on minus `o` off, under the follower: `q_tag_inc_moved`, `q_tag_inc_left`, each tag's `q_tag_led_inc_<tag>` (WP6 step 3), and the rest |
| remainder         | `R(on, follower) − R(o off, follower)` at the step's end                                                         |

Each as a net column integral and a gross one (the integral of the absolute
value per cell), per step, in `OUTDIR/<case>_gate.csv`. For `vdiff`, the
probe also accumulates per tag and cell `D = Σₖ (−excess − the follower's
per-tag correction)`: how the tag would change if the correction took the
leak instead of the follower. It is written with the reference's final
profiles in `<case>_gate_profiles.csv`.

**Bounded, not isolated.** Turning an operator off changes more than its leak.
Its transport of the parent and of any residual already there, and its
coupling in the Newton solve, go with it. So each difference bounds the
operator's part. The source column is the leak alone, in closed form. Where
the actual growth and the source disagree by more than a factor of two, the
disagreement is reported with the gate's verdict, and the verdict says which
of the two it rests on.

## 4. The retention rule, with its thresholds

Per operator, over the window (section 5), per day. `W` is `∫ρq_tot` at the
window's end. A correction is retained if any part holds:

| part | G3_PLAN 4.2's wording                                                     | measure                                                                                                   | threshold (OD3 row)                                                              |
|:---- |:------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------- |
| 1    | it leaves a remainder after the follower                                   | the remainder, net, `|Σₖ remainder|`, and gross, `Σₖ` gross remainder, over `W` per day                    | above 0.02% of `W` a day: a tenth of the closure budget ("Comparator: its own residual") |
| 2a   | it cuts the follower's share of the operator's transfer, in aggregate      | `Σₖ` gross change of `q_tag_inc_moved`, on minus off, over `W` per day                                     | above 0.5% of `W` a day ("Intervention, aggregate")                              |
| 2b   | the same, per tag                                                          | `Σₖ` gross change of `q_tag_led_inc_<tag>`, on minus off, over the tag's inventory at the window's end     | above 2% over the window ("Intervention, per tag")                               |
| 3    | it changes per-tag provenance                                              | per tag, `D` at the window's end against the reference's profile: L1 `∫|D|dz / ∫ρ|q_tag|dz`, L∞ `max|D/ρ| / max|q_tag|`; for a tag under 1% of the partition, `∫|D|dz` against `2e-4 ∫ρq_tot dz` | L1 above 2% or L∞ above 5%; for a small tag, above the absolute bound ("Provenance, per tag at 24 h"; "small tags") |

Part 3 is measured for `vdiff` only. `diffusion_up`'s leak reaches the copies,
not the grid mean's tags, and the copies' repair takes it out; its part 3 is
not assessable here.

**Two readings to confirm.** OD3 has no row named for part 1. The table uses
the tenth-of-the-budget level that the comparator's own-residual row uses.
And OD3's per-tag intervention row judges `led_fix`, with `led_inc` "reported,
judged only through the refinement test". Part 2b applies the same 2% to the
follower's per-tag share because G3_PLAN 4.2 names the intervention threshold
for it. The owner may change either before the gate is scored.

**What follows.**
  - A correction retained under 1 or 2 is built in WP4c.
  - One retained only under 3 becomes a default only with an eligible
    comparator or a documented mechanistic argument for its attribution
    (G3_PLAN 4.2).
  - The rest are deferred with this decomposition's numbers, not deleted.

## 5. The window

OD2's rule: startup ends at the first output after which the parent's
domain-mean tendency of `∫ρq_tot`, averaged over the output interval, stays
below 10% of its largest value in the first 6 hours for three outputs in a
row. The boundary is read from W25's untagged 30-level run
(`w25i_d4w_untagged_z30_c`, P4) before the gate is scored. OD2 expects about
the first hour. The rule is scored over established flow, from the boundary to
the end; startup is reported beside it and not scored.

**Expectations, stated before the runs; not pass criteria.**
  - `vdiff`'s source near W18's estimate, 0.9% of the water a day (net
    change per level, summed).
  - Its remainder near zero: the diffusion is in flux form, so the leak moves
    no water across the column's boundaries, and the follower moves every
    column-neutral mismatch.
  - Its follower's share near its source. If so, part 2a holds, and the
    correction would be retained for attribution: it takes the leak from the
    tags whose condensate leaked, instead of the follower's donor shares.

## 6. Code, runs and checks

**Code.** A run tree, `../ClimaAtmosResiDyn-wp4c-run`: this record
(`claude/plan-rev2`) + WP6 step 3 (`claude/water-tags-wp6-step3`, #109, each
tag's ledgers) + the tags' cross blocks (`claude/water-tags-sed-cross`, #105)
+ option A (`claude/tag-closure-no-abort`, #112). That is the W25 run tree's
composition, so the parent is W25's. The environment
`$SCRATCH/claude_work/plan2/wp4c_testenv` points ClimaAtmos at it.

**Login-node checks, before any job.** Every trial configuration of both cases
builds, and the probe runs two steps of case A with `T_END=240secs`
(`output/wp4c_gate/`).

**Jobs.** `hpda2_compute`, 2 CPUs, 48 GB, with
`$SCRATCH/claude_work/plan2/wp4c_gate_job.sh`, which sets `OPERATORS` and
`T_END` from `RUNCFG`:

| case | `RUNCFG`               | `OPERATORS`          | `T_END`   | integrators | limit |
|:---- |:---------------------- |:-------------------- |:--------- |:----------- |:----- |
| A    | `wp4c_gate_d4w_default` | `vdiff,sgs_mass_flux` | `1days`   | 7           | 10 h  |
| B    | `wp4c_gate_d4w_copies`  | `vdiff,diffusion_up`  | `12hours` | 7           | 16 h  |

Expected wall time: the default mode compiles in about 12 minutes per
configuration and the copies in 28 to 41 (W25); each integrator's step takes
about 3 s in the default mode. Case A about 5 h, case B about 10 h.

Then `python3 analysis/water/wp4c_gate_score.py
$SCRATCH/tag_closure/output/wp4c_gate` reads both cases' CSVs and the
window's boundary and prints each part's number against its threshold.
