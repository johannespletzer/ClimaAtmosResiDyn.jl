# WP4c: the two retained leak corrections

Written on 2026-09-25, before any run. W40 applied the gate of
[WP4C_GATE.md](WP4C_GATE.md) and retained two corrections: `vdiff`, the grid
mean's EDMF vertical diffusion, and `diffusion_up`, its updrafts' mirror on the
copies. This note says what they are, where they apply, where WP4b makes them
moot, and how they are validated. The validation (section 8) is pre-registered
here.

## 1. The leak

Under 1M the parent diffuses `q_tot_eff = q_tot − q_rai − q_sno` at `K_h`, and
`q_tot` at `K_e`. Each tag diffuses its whole value at `K_h + K_e`. So the
partition gains `−∇·(ρK_h ∇q_p)` with `q_p = q_rai + q_sno`. That is
`water_tag_leak!(:vdiff)`. The copies take their tag's diffusion per unit mass,
and `q_totʲ` the parent's. So their sum leaks the same amount per unit mass
(`water_tag_leak!(:diffusion_up)`, times `ρaʲ/ρ`).

Without a correction, the follower (`water_tag_transport: increment`) absorbs
the grid mean's leak. It spreads it by the shares of the cells its flux leaves.
W40 measured that as 2.9% of the water a day of the follower's moved gross. The
copies' repair absorbs the copies' leak.

## 2. The correction

Each tag `i` takes back the diffusion of its own share of the rain and snow:

    ρq_tagᵢ,ₜ += ∇·(ρK_h ∇(ψᵢ q_p)).

`ψᵢ` is the share the sedimentation mirror takes the tag's rain and snow by
(G3_PLAN 4.2): for a partition tag its clamped share renormalized over the
partition, for a source tag its own clamped share. The sign is plus here
because the model's operator `ᶜdiffusive_flux_divergenceᵥ` is `∇·(−ρK∇χ)`. It
is G3_PLAN 4.2's "minus" in that operator's terms.

  - **Exact for the partition.** The partition's shares sum to one wherever it
    holds water. The operator is linear. So the partition's corrections sum to
    `∇·(ρK_h ∇q_p)`, and its diffusion is the parent's, in every evaluation.
  - **Where the partition holds no water** the shares are zero, and the leak
    there stays. It lands where it lands today.
  - **Source tags** take back their own share. So a source tag diffuses only
    the water the parent diffuses too.
  - **Mechanistic reading.** Without rain and snow tags, the tags do not know
    which of their water is rain. The sedimentation already charges the rain to
    the tags by `ψᵢ`. The correction uses the same rule. So the water that did
    not diffuse is the water the sedimentation says each tag holds as rain. The
    follower instead takes the mismatch from the donor cell of its flux.
  - **The copies** (`diffusion_up`). Each copy takes its tag's correction per
    unit mass, `/ρ`, exactly as it takes its tag's diffusion. So the copies'
    sum mirrors `q_totʲ`'s diffusion too, and the copies' repair no longer
    absorbs this leak. The copies use the grid mean's `ψᵢ`, since what they
    mirror is the grid mean's tendency.

## 3. Where each applies, and where WP4b makes it moot

One key, `water_tag_leak_correction` (default `false`), turns on both. The
copies' part runs only where the updrafts' mirror runs
(`edmfx_vertical_diffusion: true`) and the copies exist.

| configuration | `vdiff` (grid mean) | `diffusion_up` (copies) |
|:------------- |:------------------- |:----------------------- |
| 0M | no leak; the key is refused | no leak |
| 1M, EDMF diffusive flux, default mode | applies | no copies |
| 1M, EDMF, copies | applies | applies |
| 1M, `vert_diff` (boundary-layer diffusion) | the same leak, not measured by the gate; the key is refused with `vert_diff` | — |
| 1M with WP4b's `water_tag_precipitation: true` | moot: the non-precipitating part diffuses as `q_tot_eff` | moot |

**The overlap with WP4b.** Under `water_tag_precipitation: true`,
`ρq_tag_<name>` holds the water that is neither rain nor snow. It diffuses at
`K_h + K_e`, and the rain and snow parts do not diffuse. So the partition's
diffusion is the parent's by construction, and `water_tag_leak!` returns zero
there. The correction would then double-count.

  - Today WP4b's stage 1 is refused under EDMF and with copies. The
    correction needs the EDMF diffusive flux. So the two keys cannot meet yet.
  - WP4b's stage 1 covers 1M without EDMF, where the leak is the
    boundary-layer diffusion, the hyperdiffusion and the sponge. There WP4b is
    the fix, and this key is refused.
  - When WP4b's stage 2 (EDMF) lands, `vdiff`'s correction becomes moot under
    `water_tag_precipitation`. When its stage 3 (copies) lands, so does
    `diffusion_up`'s. The key must then be refused with
    `water_tag_precipitation: true`. That refusal is written when the two
    branches meet, since the key does not exist on this branch's base.
  - Without rain and snow tags, this correction is the only one.

**Not built.** The horizontal SGS flux, the hyperdiffusion, the sponge and the
copies' hyperdiffusion leak too, on the sphere only. The gate could not size
them on a column and deferred them to step 9, where `q_tag_leak_*` sizes them.
The boundary-layer diffusion is not built either: the gate did not measure it.

## 4. The follower and the Newton solve

The correction is written in `edmfx_sgs_diffusive_flux_tendency!`, after the
tracer loop. So it is implicit where the diffusion is (`implicit_diffusion:
true`, as on D4-W). It has no Jacobian block. With one Newton iteration it is
taken at the stage's first guess. Under the follower the tags' own implicit
tendency then contains it. The follower moves only what still differs from the
parent's increment.

## 5. The ledgers (WP6 step 3)

  - Per mechanism: `q_tag_led_leaknet`, the partition's correction, the net of
    what it gave the partition's tags. It is minus the leak times `ρ` where the
    partition holds water. With copies, `q_tag_led_upleaknet`, the copies'
    correction times `ρaʲ`, summed over the updrafts.
  - Per tag, under `water_tag_ledger_per_tag: true`: `q_tag_led_leak_<name>`,
    and with copies `q_tag_led_upleak_<name>`.
  - All are state fields. The stepper weights them as it weights the tags, so
    each is exact per step at every `update_constrain_state_every`. The
    per-step gross (`_gross`, `_colgross`) and the audit's `_retained` cover
    them. They have no `attempted` total: a tendency is evaluated at every
    stage and Newton iterate, and a sum over those evaluations is not what a
    step tried to move. The audit writes `NaN` there.
  - They exist only with the key, so a run without it keeps its state layout.
    A restart that changes the key is refused.

## 6. Parity

The correction writes only the tags' tendencies, the copies' and its ledgers.
The parent's tendency, its Jacobian and its solve do not change. The split
solver solves the new ledgers apart, as it does the others. The new test group
`tagging_water_leak` checks the model's fields against the column without tags,
bit for bit.

## 7. The code, and the base branch

`claude/water-tags-leak-correction`, from #109 (`claude/water-tags-wp6-step3`),
not from #116 (option C). The correction reads neither option C's target nor
its negative part. Its `ψᵢ` is the sedimentation's share, clamped where the
parent is not positive, as on #109. And the gate ran on #109 without option C.
So a validation on #109 changes one thing against W40. The branch should merge
onto #116 without a conflict of meaning. Where the parent is negative, option C
gives the partition no water, and the shares there are zero either way.

The key is `false` by default. Whether it becomes the default under 1M is the
owner's decision, after section 8's validation.

## 8. Validation, pre-registered

**Run tree.** `../ClimaAtmosResiDyn-wp4c-corr-run`: the gate's run tree (this
record, #109, #105, #112) with the correction branch merged. So against W40 it
changes the correction and nothing else. Environment
`$SCRATCH/claude_work/plan2/wp4c_corr_testenv`.

**Runs.** The gate's probe (`analysis/water/wp4c_gate_probe.jl`) on both of the
gate's cases, with the key on. `REFERENCE_OUTPUT=1` makes the probe's reference
write its configuration's diagnostics, so parity and the ledgers are read from
the same runs. Output in `$SCRATCH/tag_closure/output/wp4c_corr/`.

| case | config | operators | length |
|:---- |:------ |:--------- |:------ |
| V1, the primary | `configs/wp4c_corr_d4w_default.yml`: case A with `water_tag_leak_correction: true` and the leak ledgers' diagnostics | `vdiff`, `sgs_mass_flux` | a day |
| V2 | `configs/wp4c_corr_d4w_copies.yml`: case B, the same way | `vdiff`, `diffusion_up` | 12 hours |

The window is W40's: established flow from 6600 s (OD2's rule on W25's
untagged run). Scored by `wp4c_gate_score.py` (`--startup 6600`) and
`analysis/water/wp4c_corr_compare.py`.

**Pass criteria for V1.** All four hold.

 1. **The follower's work falls.** `vdiff`'s part 2a, the gross change of
    `q_tag_inc_moved` on minus `vdiff` off, falls from W40's 2.92% of the
    water a day by more than OD3's intervention threshold, 0.5%: to at most
    2.42%. That is the gate's part 2 turned round: the correction cuts the
    follower's share of `vdiff`'s transfer by more than the threshold.
    *Expected, not a criterion:* about 1%. If the follower's leak-driven
    work per step is the closed-form leak, 1.93% a day (W40's `vdiff`
    source), then the rest is at least 2.92 − 1.93 = 0.99% by the triangle
    inequality, and equal to it where the two do not cancel. A value below
    0.99% would mean the leak drove more of the follower's work than its
    closed form, as W40's growth of 2.2 times the source suggests it may.
    *Amended before any run (2026-09-25):* the first draft asked for at most
    0.98%, which the triangle inequality puts out of reach unless the leak
    drove more than its closed form.
 2. **Closure unchanged.** Part 1 stays below 2e-4 of the water a day for
    both operators, as in W40. The reference's `q_tag_res` gross at 24 h
    stays within the 0.2% budget.
 3. **Parity.** Every parent field the reference writes hourly (`rhoa`, `ta`,
    `hus`, `clw`, `cli`, `husra`, `hussn`, `wa`, the updraft's and the
    environment's fields, `tke`, `pr`) equals W25's untagged twin
    (`w25i_d4w_untagged_z30_c`) bit for bit at every output.
 4. **The ledgers.** `∫q_tag_led_leaknet ρ dz` stays within 1e-12 of the
    column's water at every output. And `q_tag_led_leaknet` equals the sum of
    `q_tag_led_leak_tropo` and `q_tag_led_leak_strat` to 1e-10 relative.

**Reported for V1, not judged.**

  - The reference's own moved gross, `q_tag_inc_moved_gross` at 24 h, against
    W25's tagged run without the correction (`w25i_d4w_default_z30_c`). The
    owner's expectation was a fall of about 2.9% of the water a day. But the
    gate's 2.9% is the gross of a per-step difference, `Σ|m_on − m_off|`. The
    fall of the moved gross is `Σ|m| − Σ|m − l|` for the leak's part `l`. That
    lies anywhere between `−Σ|l|` and `Σ|l|`, so it is not predicted. It is
    reported with that caveat.
  - `q_tag_led_leaknet`'s per-step gross over the window against the
    closed-form source gross, 1.93% a day. Expected within 10%, since the
    ledger takes the correction at the stages' states and the closed form at
    each step's start.
  - Part 2b per tag (W40: `tropo` 3.2%), and `sgs_mass_flux`'s rows, which
    the correction does not touch.
  - Part 3 is not meaningful with the correction on. `D` then measures the
    correction itself, against the follower's remaining share. It is printed
    and not read.

**V2, the copies.** Criteria 2, 3 and 4 hold as for V1, with 4 also for
`q_tag_led_upleaknet`'s column integral. No uncorrected run of case B wrote
its copies' residual, so V2 sets no criterion on the copies' closure.
Reported: `diffusion_up`'s part 2a (W40: 1.24%), `vdiff`'s part 2a (W40:
3.02%), the copies' repair's per-step gross on minus off (W40: 3.3e-4 of the
water a day for `diffusion_up`), and `q_tag_copy_res` at 12 h. W40 found
`diffusion_up`'s actual growth 13 times its closed form. So the closed form
does not predict how far these fall, and V2 sets no bound on them.

**What follows.** If V1 passes, `vdiff`'s correction is validated for the
default mode. Making the key the default under 1M is then the owner's call. If
criterion 1 fails, the correction does not take the leak's share of the
follower's work, and the difference is investigated before anything else. A
failure of 2, 3 or 4 is a defect to fix.

**Jobs.** `hpda2_compute`, 2 CPUs, 48 GB, with
`$SCRATCH/claude_work/plan2/wp4c_corr_job.sh`, as the gate's: V1 about 5 h
(limit 10 h), V2 about 10 h (limit 16 h).

*Submitted 2026-09-25:* V1 job `13973348`, V2 job `13973349`, run tree at
`90f32566` (clean; the gate's tree `52a666c5`, this record at `abbc2319`,
the correction branch at `d0c0064a`). Before them, V1's probe ran two steps
on the login node with the reference's output on (`T_END=240secs`, exit 0).
That smoke first stopped at a refusal of the key with the diffusive flux
off, which the gate's `vdiff`-off trials need; the refusal was relaxed
(`d0c0064a`: with the flux off the key does nothing). V2 was not smoked.
