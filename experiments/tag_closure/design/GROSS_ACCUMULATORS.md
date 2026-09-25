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
 3. Added after the code review: keep the transfer ledgers as they are, exact
    per step at the default cadence only, or make them per tag, which is exact
    at every cadence and costs one state field per partition tag and
    mechanism.

## 9. Step 2: what each state ledger adds

Written on 2026-09-24, before step 2's code. Section 3.1 says one signed
field per mechanism, summed over the tags. For a transfer between tags that
sum is zero in every cell, so it would record nothing. Each field therefore
adds, per application, the water that mechanism moved in section 3.3's sense,
over the partition's tags. It keeps the sign where 3.3's measure has one.

| state ledger | mechanism | adds per application |
|:------------ |:--------- |:-------------------- |
| `q_tag_led_rescale` | `rescale_water_tags!` where `ρq_tot_before > 0` | `Σ_P shiftᵢ`, signed: one way |
| `q_tag_led_empty` | the same where `ρq_tot_before ≤ 0`, which empties the tags | `Σ_P shiftᵢ`, signed |
| `q_tag_led_repair` | `repair_water_tag_partition!` | `½ Σ_P |Δᵢ|`: a transfer |
| `q_tag_led_uprepair` | `repair_water_tag_copies!` | `ρaʲ Σ_P shiftᵢʲ`, signed: the residual handed to the copies |
| `q_tag_led_upfilter` | the updraft filter, across `enforce_physical_constraints!` | `Δ(ρaʲ Σ_P χᵢʲ)`, signed, from one snapshot |
| `e_src_led_repair` | `repair_energy_source_tags!`, partition tags | `½ Σ_P |Δᵢ|` |

  - **The stepper weights each as it weights the tags.** A transfer's field
    adds a non-negative amount per application. It can still fall within a
    step, through a negative stage weight. The callback's `|L − L_prev|` per
    step is then what the step retained, in 3.3's sense.
  - **Left out, and recorded only in the cache ledgers:** the source tags'
    rescale and the energy overlay tags' clamp. They are not the partition,
    and 6.1's budgets are for the partition.
  - **The filter's field is net over the copies** in a cell, from one snapshot
    of `ρaʲ Σ_P χᵢʲ`. A clamp up and a clamp down of two copies in one cell
    cancel in it. One scratch field instead of one per copy.
  - **The callback** keeps, per state ledger `L`, including WP5's
    `q_tag_inc_left`, `q_tag_inc_moved` and their energy twins, `L_prev`, the
    per-cell gross `G += |L − L_prev|` and the column gross
    `G_col += |∫(L − L_prev) dz|`, in Float64. `L_prev` starts from the state
    the cache is built from, so a restarted run's first step does not count
    the restored ledger. `G` restarts at zero until step 3.
  - **Diagnostics:** `<L>` for each new state ledger, `<L>_gross` and
    `<L>_colgross` for every state ledger. `led_` is reserved in both
    families.
  - **Restart:** the new fields are in a checkpoint or are not. A pre-WP6
    checkpoint is refused with its own message (8.1's proposal), until the
    owner decides.

**As built after the code review** (high,
[review/agent_reviews/wp6_code_review_2026-09-24.md](../review/agent_reviews/wp6_code_review_2026-09-24.md),
2026-09-24, at `e65009ef`):

  - **Where the repair zeroes every tag** (review S1), its changes do not sum
    to zero. `q_tag_led_repair` and `e_src_led_repair` now take half the
    changes less their net, the part moved between tags. The net goes to
    `q_tag_led_repairnet` and `e_src_led_repairnet`, signed.
  - **"Retained" is exact per step only at `update_constrain_state_every:
    step`** (review S2). That is the default, where the corrections fire once
    per step on the accepted state.
      + At `stage` or `dss` each firing is weighted by its tableau weight, and
        under ARS343 one weight is negative.
      + A transfer's ledger can then fall within a step. Its per-step change
        is then neither what the step moved nor a bound on it.
      + The docs say so. Per-tag signed ledgers for the transfers would make
        the per-step moved amount exact at every cadence (section 8's third
        point, for the owner).
  - **In Float32 the state ledgers lose increments below one rounding unit
    of their value** (review S5). The Float64 grosses cannot recover them.
  - **A cell-event** is a change above `max(1e-12, 16 eps(FT))` of the cell's
    total (review S3). The audit's event total counts nodes. It was wrong in
    Float32 before (review B1, in #103).

## 10. Step 3, built for rev. 2 (2026-09-24)

Rev. 2 of the work plan (ROADMAP.md) made step 3 step 1 of its order, before
the sphere and the default decisions, and added Insight 10's per-tag ledger.
It needs no owner decision. Where a choice is the owner's, the code takes the
conservative side and the question is listed in 10.6. Built on
`claude/water-tags-wp6-step3` (worktree `../ClimaAtmosResiDyn-wp6s3`), on #103
at `f22cfb27`.

### 10.1 Accepted-step throughput, attempted beside retained, events

  - **Retained.** The per-step gross of every state ledger, `Σ |ΔL|` over the
    accepted steps (section 9's callback), is now reported in the audit table
    as `<L>_retained`, integrated over the domain, and over the column's water
    or energy as `<L>_retained_relative`. `<L>` is the ledger's name without
    its `q_tag_` or `e_src_` prefix.
  - **Attempted.** Each ledger per mechanism gets a Float64 accumulator. The
    kernel that writes the ledger keeps it before the call and adds the
    absolute value of the call's change afterwards (`before_tag_ledgers!`,
    `after_tag_ledgers!`). A call on a stage value the stepper discards counts.
    The increment corrections add the absolute value of each stage's entry to
    `q_tag_inc_left`, `q_tag_inc_moved` and their energy twins. Reported as
    `<L>_attempted`. For a transfer, attempted and retained use the same
    measure, section 9's `½ Σ_P |Δᵢ|` less the net.
  - **Events.** The callback also counts, per cell, the steps in which `|ΔL|`
    exceeded rounding against the cell's water, or the partitioned energy for
    the energy ledgers (`tag_event`). Reported as `<L>_events`.
  - **Validity by cadence.** `AtmosSimulation` records
    `update_constrain_state_every` in the cache, and the audit writes
    `ledger_cadence_step`, 1 at `step`. At `step` the corrections fire once per
    step on the accepted state, so `<L>_retained` is what the steps moved, and
    `<L>_attempted` less it is the work the steps discarded. At `stage` or
    `dss` the model warns once at setup: a transfer's per-step change is
    neither what the step moved nor a bound on it (section 9, the code
    review's S2). For the follower's ledgers attempted and retained differ by
    how the tableau combines the stages at every cadence, so their difference
    is not a discarded amount.

### 10.2 Each tag's own ledgers (Insight 10)

  - Opt-in per family: `water_tag_ledger_per_tag` and
    `energy_source_tag_ledger_per_tag`, off by default. A type parameter of the
    tagging model, so the state is built at compile time.
  - `q_tag_led_fix_<name>`, for every water tag: the change the limiters'
    rescale, the emptying and the partition repair made to that tag. The
    kernels write it beside the tag, from the same expression, through a
    `TagLedgerView` of the state. `e_src_led_fix_<name>` does the same for the
    energy repair, the partition's transfers and the overlay tags' clamp.
  - `q_tag_led_inc_<name>` under `water_tag_transport: increment`, and
    `e_src_led_inc_<name>` under `enthalpy_increment`: what the correction after
    each solve moved into or out of the tag. The same flux kernel writes it
    into the ledger's tendency, from a zero entry as the tag's is, so it is the
    tag's change bit for bit (`_sgs_water_tag_fluxes!` with a `TagLedgerView`).
  - State fields, without the `ρ` prefix, split-solvable, carried through a
    restart and guarded by the restart check (a changed key is refused). The
    stepper weights each as it weights its tag, so a ledger's change over a
    step is the step's net correction of that tag at **every** cadence. This is
    the per-tag option of section 8's third point, but per tag and kind, not
    per tag and mechanism.
  - The audit writes, for each, `_retained`, `_attempted` (for a `led_fix`
    ledger, the cache ledger's gross twin, which takes the same changes),
    `_events`, and `_inventory_fraction`: `_retained` over the tag's integral
    at the audit's time.
  - **What it bounds.** Under the follower, most of `led_inc` is the parent's
    vertical advection, which the tags no longer take explicitly (W24). So the
    per-tag fraction bounds the follower's intervention on that tag from
    above. It does not isolate the intervention. A tag whose fraction is small
    was moved little by the corrections; a large fraction is not by itself an
    error.
  - Diagnostics: `<L>` per unit mass, and `q_tag_led_fixgross_<name>`,
    `q_tag_led_fixcolgross_<name>` (and `inc` alike, and `attempted`). The
    kind comes before the tag's name so that no tag's name can collide.

### 10.3 Restart stitching (3.5)

The checkpoint carries every accumulator in the cache beside the state: the
cache ledgers `ᶜwater_fix`, `ᶜwater_upfix`, `ᶜenergy_source_fix`, their gross
twins and counts, and per state ledger the per-step gross, the column gross,
the events and the attempted total (`tag_ledger_checkpoint_fields`, written by
`save_state_to_disk_func`). `AtmosSimulation` reads them back after the cache
is built. So a restarted run continues them. `ᶜprev` is not carried: it is the
ledger itself, which the state carries, so the first step after a restart
counts nothing twice.

  - A checkpoint written before step 3 holds none of them. They then start at
    zero, with a warning, as every cache ledger did before; the audit's grosses
    cover only that segment.
  - A checkpoint with some but not all is refused: another configuration of
    the ledgers wrote it.
  - The diagnostics `q_tag_fix_<name>`, `e_src_fix_<name>` and the twins no
    longer reset at a restart. Their documentation says so.

### 10.4 Parity

Every new write goes to the cache or to the ledgers' own state fields. Without
the new keys the state is the one #103 builds. The kernels' changes to the
tags and to the model's fields are unchanged; the new broadcasts read them.
The integration test `tagged_water_increment_integration.jl` now runs its
tagged column with both families' ledgers per tag, so its parity check covers
them without another build.

### 10.5 Tests

  - Unit tests on the login node (`output/wp6_step3/`): names, state and
    Jacobian split; the rescale and the repair write each tag's change, equal
    to the cache ledger bit for bit, in both float types, and nothing without
    the key; attempted against retained with a discarded stage; events; the
    audit's columns and cadence flag; the checkpoint round trip bit for bit,
    the warning without the accumulators and the refusal of a partial set; the
    follower's flux into each tag's ledger bit for bit, both families; the
    restart guard; the config keys.
  - Integration: `tagging_water_increment` checks the ledgers per tag on the
    EDMF column (their partition sum against `q_tag_inc_moved`, the `fix`
    ledgers against the cache ledgers, the audit) and the model's fields.
  - The check script `analysis/water/wp6_step3_checks.jl`, for a compute node:
    the model's fields at `step`, `stage` and `dss` with the ledgers per tag
    on; the per-step gross and events against stepping by hand; attempted
    against retained per cadence; and the restart continuation of every
    accumulator.

### 10.6 Open questions, with the conservative default taken

 1. **A pre-WP6 checkpoint** (section 8, point 1): still refused, as built in
    step 2. A checkpoint from after step 2 but before step 3 restarts, with
    the cache accumulators at zero and a warning.
 2. **Loss and τ** (point 2): not in WP6, as proposed.
 3. **Transfer ledgers per tag** (point 3): the ledgers per mechanism stay as
    they are, exact per step at `step` only. The ledgers per tag of 10.2 are
    exact at every cadence, per tag and kind. Per tag and mechanism is not
    built.
 4. **The ledgers per tag on or off by default.** Off: each adds a state
    field per tag, or two under the follower, which costs build time (W34)
    and memory. The owner may want them on in qualification runs.
 5. **The per-tag fraction's denominator.** The tag's integral at the audit's
    time, as rev. 2 words it. A time mean or the maximum can be formed offline
    from `_retained` and the tag's output. It belongs with OD3's per-tag
    threshold.

## 11. OD4's accumulator: the energy sources' gross throughput (2026-09-25)

The owner set OD4's scale on 2026-09-24 (the gross energy the sources put
into the tags over the window) and its quantity on 2026-09-25: an exact
accumulator per tag and per step, carried through restarts, as step 3 did for
the ledgers. Until it lands, and for runs that predate it, the process
records' figure is the interim (the register, OD4). *Corrected after E84 (2026-09-25):* the interim is an estimate. On D4 it came out 6% above the exact accumulator, so it is not a lower bound, and a percentage on it is not an upper bound. The direction of its error is not established.
A per-process comparison against the accumulator is open on #115. Built on `claude/energy-source-throughput`, from
#109.

### 11.1 The quantity

Every source reaches the energy source tags through a bracket
(`attribute_energy_source_tags!`): the bracketed process's increment `Δ` of
`E = ρe_tot + c·ρ` goes to tag `i` as `M_i Δ⁺ − φ_i Δ⁻`, where `M_i` is its
mask for a label it receives and `φ_i` its share of `E`. So a tag's source is
exactly the sum of its bracket terms. Transport, the increment correction and
the repair are not sources; they have their ledgers already.

  - **Each tag's source ledger**, `e_src_led_src_<name>`: a state field whose
    tendency is the tag's bracket terms, written in the same broadcast as the
    tag's own (`_accumulate_energy_source_tag!`). The stepper integrates it
    with the tag's weights, explicit and implicit brackets alike, so its
    change over a step is what the step's sources gave the tag.
  - **Its per-step gross**, `Σ_steps |ΔL|` per cell, by step 2's callback,
    like every state ledger: exact per step at every cadence, carried through
    a restart by step 3's checkpoint fields.
  - **The throughput**, `energy_source_throughput`: the per-step gross of the
    partition's source ledgers (the region tags without sources), summed over
    the domain. The partition's tags take every source in full, gains by their
    masks and losses by their shares, so each unit counts once. The source
    tags overlay the partition and are left out; their own grosses are in the
    audit per tag.
  - **Not `|Σ sources|`, not per process.** A step in which one process adds to
    a tag and another takes the same away counts zero for that tag. Per
    process and tag would need a ledger per pair; not built.

### 11.2 Where it lives

  - Under `energy_source_tag_ledger_per_tag: true` only, beside the repair's
    and the correction's ledgers per tag. The owner decided on 2026-09-24 that
    those are off by default and on in every validation and qualification run;
    OD4's percentages belong to those runs. One state field more per tag.
  - The audit: `led_src_<name>_retained` per tag (with `_events` and
    `_inventory_fraction`, the throughput over the tag's energy), and
    `source_throughput`, the partition's sum, cumulative. A window's value is
    the difference of two rows.
  - The diagnostics: `e_src_led_src_<name>` per unit mass, and its
    `e_src_led_srcgross_<name>` and `e_src_led_srccolgross_<name>`.
  - The restart guard: a checkpoint written with the per-tag ledgers but
    before this ledger lacks `e_src_led_src_*`, and is refused, naming them.

### 11.3 Tests

  - Unit (`energy_source_tags_tests.jl`, both float types): each tag's source
    ledger takes exactly its tag's bracket change, bit for bit, for three
    labels; the partition's ledgers sum to the increment; a source tag gains
    only for its own label; the tags' tendencies are the same bit for bit with
    and without the ledger; the throughput sums the partition's grosses and
    leaves the source tags out; nothing without the key.
  - The names, the config key and the diagnostic names
    (`tracer_config.jl`, `tagged_water_tests.jl`).
  - Integration (`tagged_water_increment_integration.jl`, group
    `tagging_water_increment`): on the EDMF column the throughput is positive
    and the audit's `source_throughput` equals it; the partition's per-tag
    grosses sum to it; the model's fields are unchanged, as that file already
    checks.

### 11.4 The scripts

`analysis/increment/g411_eligibility.py` takes `source_throughput` from the
audit where a run has it, and the process records' figure otherwise, and
says which. The earlier E-records are restated with that figure and rerun
only where the contract needs an exact value (the register, OD4). *Corrected
after E84:* they are labelled estimates, not upper bounds.
