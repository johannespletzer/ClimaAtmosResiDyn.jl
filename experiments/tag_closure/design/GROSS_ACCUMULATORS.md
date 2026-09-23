# Gross accumulators for both tag families: the design note of WP6

Written on 2026-09-24 for G3's WP6 (G3_PLAN 5, G3_TODO), which the owner added
to the session's goal that day. Revised the same day after its review by
`clima-numerics-reviewer` (high,
[review/agent_reviews/wp6_design_review_2026-09-24.md](../review/agent_reviews/wp6_design_review_2026-09-24.md));
section 7 says how each point was taken. It proposes; the code follows once the
owner has seen section 8. `file:line` references are to
`claude/water-tags-edmf-wp5` at `1addf74c`, which contains #100 and #101, and to
ClimaTimeSteppers (CTS) 1.0.1.

## 1. The problem

Every ledger the tags keep today is **signed and cumulative**. A ledger that
moves `+x` in one step and `−x` in the next reads zero, and so does one that
never moved anything. Two records need the gross size:

  - **W21's copies' repair** is judged against G3_PLAN 6.1's bound of 0.2% a
    day. `water_tag_edmf_audit` sums `|ᶜwater_upfix|` per cell
    (`tagged_water_edmf.jl:1177-1182`): gross over the cells, net over time in
    each cell. The plan's note on 6.1 says so.
  - **The increment's part left in place** (`e_src_inc_left`, WP5's
    `q_tag_inc_left`) is signed per cell and cumulative. Its gross per step is
    what 6.1's "named parts" need.

And one question of meaning. The constraint-side cache ledgers (`ᶜwater_fix`,
`ᶜenergy_source_fix`, `ᶜwater_upfix`) count every call, so they record what was
**attempted**, not what the step **retained**. That gap exists at every
`update_constrain_state_every`, including the default `step`, whenever a limiter
changes `ρq_tot`: ClimaAtmos always passes `T_exp_T_lim!`
(`integrator.jl:193, 239-243`), so `lim!` runs on every stage value but the
first (`imex_ark.jl:158-161`), and its `rescale_water_tags!` shifts
(`limited_tendencies.jl:109, 148`) enter `ᶜwater_fix` and are discarded with
the stage. Under `stage` or `dss` the constraint changes on the solved stages
are kept with weight `b_imp[i]/γ` (`imex_ark.jl:245-249, 284`), which can
exceed one or be negative.

## 2. What exists

| ledger | family | where | written by | net or gross |
|:------ |:------ |:----- |:---------- |:------------ |
| `ᶜwater_fix` (`q_tag_fix_<name>`) | water | cache, per tag | `rescale_water_tags!` (limiters, `constrain_state!`, including the emptying where the parent is ≤ 0), `repair_water_tag_partition!` | signed, cumulative, attempted, reset at restart |
| `ᶜwater_upfix` (`q_tag_upfix_<name>`) | water, copies | cache, per partition tag | `repair_water_tag_copies!` | as above |
| `q_tag_inc_left`, `q_tag_inc_moved` | water, WP5 | state | `correct_water_tag_increment!` | signed, cumulative, retained, through restarts |
| `ᶜenergy_source_fix` (`e_src_fix_<name>`) | energy source | cache, per tag | `repair_energy_source_tags!` | signed, cumulative, attempted, reset at restart |
| `e_src_inc_left`, `e_src_inc_moved` | energy source | state | `correct_energy_source_increment!` | signed, cumulative, retained, through restarts |

The updraft filter's clamp of each copy (`mass_flux_closures.jl:303-316`) has
no ledger at all.

## 3. Proposal

**3.1 Retained, per mechanism, as signed state ledgers.** Each correction
kernel also writes a signed state field, in place, next to the tag it changes:
the limiter's rescale, the emptying where the parent is ≤ 0, the partition
repair, the copies' repair, the filter's clamp of the copies (snapshotted
around `enforce_physical_constraints!`), and the energy repair. The stepper
then weights each exactly as it weights the tags, at every cadence and through
restarts, so the field holds what was retained. One field per mechanism and
family, summed over the tags, not one per tag: the per-tag split stays in the
cache ledgers. Names carry no `ρ` prefix and match `is_splittable_jacobian_field`
(`manual_sparse_jacobian.jl:712-719`).

**3.2 The gross per step, by a callback.** After every step (CTS applies
callbacks after `step_u!`, `integrators.jl:427-440`), a read-only callback adds
`G += |L − L_prev|` per cell for each signed state ledger `L`, then sets
`L_prev = L`. It reads `Y` and writes only its own cache fields, wrapped as the
parent-budget ledger's read-only callbacks are
(`parent_budget/checkpoint.jl:184-199`). The gross is per step, which the
per-stage sum of the first draft was not: under ARS343 a stage's entry reaches
the step with weight `b_imp[i]/a_imp[i,i]`, one of them −1.478, so a per-stage
sum can fall below zero. The column-level gross `|ΔL_col|` per step is written
as well, since the per-cell "left" is placed in proportion to `|m|` and only
its column total is invariant.

**3.3 What "moved" means.** Per mechanism, against 6.1's 0.2%. A transfer
between tags (the partition repair, the copies' repair between copies) moves
`½Σᵢ|Δᵢ|`; a correction that shifts every tag one way (the rescale, the
emptying) moves `|Σᵢ Δᵢ|`. The audit reports each mechanism's moved water per
day beside the budget.

**3.4 Attempted, beside retained.** The cache ledgers keep what they record
now, and get a gross twin and an event count. The gross and the count are kept
in Float64 whatever the model's float type: in Float32 a gross loses nearly all
small increments after a large one. A cell-event counts only where the change
exceeds `1e-12` of the cell's water, since the copies' residual is a
rounding-level nonzero almost everywhere. Attempted minus retained is then the
discarded work, per mechanism.

**3.5 Restarts.** The cache ledgers are written into the checkpoint and read
back (`save_state_to_disk_func`, `callbacks.jl:296-326`), so a segment
continues rather than stitches. The new state fields make a pre-WP6
checkpoint fail `check_restart_fields`, whose message would blame the
transport. So `WATER_TAG_CHECKPOINT_VERSION` and the energy guard's version are
bumped, and a pre-WP6 checkpoint is refused with its own message. *For the
owner:* refuse, or start the new fields at zero with a warning.

**3.6 Loss and residence time: not in WP6.** A per-tag loss in the cache would
add up rates, one per tendency evaluation, and cannot hold the Dual numbers of
an autodiff Jacobian. Loss also changes meaning in the next two packages: WP4a
splits the 0M sink by subdomain and defines `pr_tag` as its column integral;
WP4b makes `ρq_tag` the non-precipitating water, whose loss is the bottom-face
flux of its parts. So loss is defined by channel at column level (surface
outflow, dew, large-scale drying) in WP4a and WP4b, as state records like
`prc_q_*`, and τ is computed offline in Float64 as `∫M dt / ∫L dt` over a
window. Numerical removals stay out of τ and are reported by 3.1. The energy
source tags get no τ: `E/loss` depends on the energy reference and the offset.

**3.7 Names.** The new diagnostics' names reserve their prefixes in
`RESERVED_WATER_TAG_PREFIXES` (`tracer_config.jl:480`), and the energy source
tags get the reserved prefixes they lack today (they reserve only `res`,
`tracer_config.jl:499`, so `e_src_fix_<name>` can collide already). The
existing audit columns `increment_left_gross` and `increment_moved_gross` are
gross over the cells and net over time; they are documented so, and the
per-step grosses of 3.2 get their own names.

## 4. Tests

  - **The per-step gross under a negative weight.** Replay one ARS343 step with
    manufactured stage values: the gross is `|Σᵢ wᵢ lᵢ|`, never negative. On an
    ARS343 column with the follower the gross never decreases and is at least
    the signed ledger's absolute value in every cell.
  - **Retained under `stage`.** With ARS222 and a constraint that adds `x` at
    every firing, the step's retained increment is `(2.414 + 1)x`.
  - **Attempted against retained under `step` with a limiter.** On a column
    with the vertical water borrowing limiter, attempted minus retained is
    exactly the stage-level `lim!` calls.
  - **Alternating signs.** `+x` then `−x` gives a signed ledger of zero, a
    gross of `2|x|` and a count of 2.
  - **Output interval.** Two runs that differ only in the diagnostics' and the
    audit's period give the same ledgers at common times, bit for bit.
  - **Restart.** From a checkpoint taken between two audit rows, the restarted
    run's ledgers equal the uninterrupted run's: bit for bit for the state
    ledgers, and to `1e-12` relative for the cache ones, whose sums do not
    associate. A pre-WP6 checkpoint is refused with its own message.
  - **Float32.** A unit test of the Float64 gross under a large and many small
    increments.
  - **Parity.** The model's fields, the tags and the existing ledgers are
    unchanged bit for bit, under `step`, `stage` and `dss`, with a limiter that
    fires, with ARS343 and the follower, and with copies. An allocation test on
    `constrain_state!`.

## 5. Cost

  - State: one signed field per mechanism and family, up to five for water and
    one for energy. Each state field is copied about ten times per step under
    ARS343 (`imex_ark.jl:44-48`), DSSed and checkpointed. They are
    split-solvable.
  - Cache: per tag, a Float64 gross and a count beside each cache ledger; per
    signed state ledger, `L_prev` and `G`.
  - Work: one or two more broadcasts per tag and correction call, run before
    the state update, and the callback's few broadcasts per step.

## 6. Order of the code

 1. 3.4 (the cache twins) and 3.7: parity-safe on their own.
 2. 3.1 and 3.2: the state ledgers and the callback.
 3. 3.3's per-mechanism report in the audit, and 3.5.

## 7. The review, point by point

| point | taken as |
|:----- |:-------- |
| B1 per-stage gross wrong under ARS343 | 3.2, a per-step callback |
| B2 loss in the cache adds rates | 3.6, moved to WP4a/WP4b as state records |
| S1 the "retained" twin | 3.1, signed state ledgers in the kernels |
| S2 attempted ≠ retained at every cadence with a limiter | section 1, and a test |
| S3 stitching, pre-WP6 checkpoints | 3.5 |
| S4 loss by channel | 3.6 |
| S5 Float32 | 3.4, Float64 cache; 4, a test |
| S6 gross against the budget, by mechanism | 3.3 |
| M1 name collisions | 3.7 |
| M2 counting rounding | 3.4, a threshold |
| M3 "gross" columns | 3.7 |
| M4 the filter's clamp | 3.1 |
| M5 tolerances | 4 |
| M6 τ offline | 3.6 |
| M7 parity breadth, cost | 4, 5 |
| M8 reuse the parent-budget adapter | 3.1 may take the adapter's classification of hook firings (`adapter.jl:209-235`) where a kernel cannot write the state field itself; to be decided in the code |

## 8. For the owner

 1. A pre-WP6 checkpoint: refused (proposed), or the new fields start at zero.
 2. Loss and τ move from WP6 to WP4a and WP4b (3.6).
