# Review of WP6's code, steps 1 and 2, 2026-09-24

This is the `clima-numerics-reviewer` review at effort high. It covers
`claude/water-tags-edmf-wp6`, `fd07d902..bdc75731`. It is condensed here, with
the reviewer's `file:line` evidence kept. How each point was taken is in
G3_TODO, under WP6.

**Verdict.** No parity defect. Step 2 may be pushed. #103 should not merge
before:
  - B1 is fixed;
  - S3's threshold is fixed;
  - S1 and S2 are decided, in code or as restated claims;
  - S4's missing tests are added.

## Parity: nothing found

  - The tags' and existing ledgers' expressions are unchanged, and run in the
    same order.
  - Shared scratch is refilled before it is read.
  - The new fields carry no `ρ` prefix, so the name-based loops skip them.
  - `Yₜ` and `Yₜ_lim` are zeroed in full. DSS covers the whole state.
  - Manual Jacobian: `-I`, uncoupled. AutoSparse: constant `-I`. AutoDense
    was never covered by the parity claim.
  - `enforce_physical_constraints!` is called only from `constrain_state!`.
  - The gross callback is a default model callback, which the parent-budget
    ledger does not constrain.

## Blocking (step 1, in #103)

**B1. `tag_event_total` is wrong at Float32** (`tag_throughput.jl:94`).
`sum(parent(ᶜfield))` adds the two Float32 halves of each Float64 slot. Four
cells with one event each give 7.5; with three events each, 8.5 instead of 12.
The audit's `fix_events`, `copy_repair_events` and `repair_events` are wrong
at the default float type, and plausible. The fix:
`sum(ᶜfield ./ local_geometry.WJ)`, which is collective, with a Float32 test.

## Should fix

**S1. The partition repair's ledger counts created water as moved**
(`tagged_water.jl:1050`, `energy_source_tags.jl:1078`). Where every tag is
zeroed (`S⁺+S⁻ < 0`), the changes do not sum to zero, but the ledger adds
½Σ|Δ|. Tags [1, −3]: ledger 2.0, transfer 1.0, created 2.0. Tags [0, −3]:
ledger 1.5, transfer 0, created 3.0. The fix: add ½(Σ|Δ| − |ΣΔ|), and record
the signed ΣΔ apart, or document it.

**S2. At `stage` or `dss`, the per-step |ΔL| of a transfer ledger is not what
the step retained.** With the `b_imp/γ` weights:
  - under ARS343, a repair A→B then B→A over two stages gives |ΔL| 1.29
    against 4.25 kept;
  - under ARS222 with an end-of-step reversal, 3.41 against 1.41;
  - the ledger itself can go negative.

It is exact only at `step`. The fix: restate the claim, or keep per-tag
signed ledgers for the transfers.

**S3. The event threshold, 1e-12, is below Float32 rounding.** One ulp counts
as an event. The fix: `max(1e-12, 16 eps(FT)) |total|`.

**S4. The tests cannot catch several errors.**
  - The only real-run gross test is `G ≥ |L|`. It also passes a per-stage sum
    or skipped steps. Test the gross bitwise against Σ|ΔL| from stepping by
    hand.
  - `q_tag_led_upfilter` is checked only for being nonzero. Check it equals
    `Δ(ρaʲ Σχ)`.
  - Still missing from the note's section 4:
      + parity at `stage` and `dss`, with ARS343, the follower, copies and a
        limiter;
      + retained under `stage`;
      + attempted against retained with a limiter;
      + the state ledgers across a restart;
      + a Float32 test of the callback and the audit;
      + an allocation test.

**S5. The Float32 floor of the state ledgers is not documented.** At
L = 1e-2, an increment below 4.7e-10 is lost; 720 increments of 2e-10 add 0.

## Minor

  - M1: the callback allocates 1.5 kB per step, from `getproperty` with
    run-time symbols.
  - M2: the filter ledger runs with the filter off, adding +0.0.
  - M3: on the sphere, events count shared nodes once per element.
  - M4: at `dss`, the firing after `initialize_imp!` is discarded exactly for
    a ledger and only to Newton accuracy for the tags.
  - M5: after a restart `G ≥ |L|` fails, since G restarts at zero.
  - M6: with `default_callbacks = false` the grosses read zero.
  - M7: the scratch testenv's `[sources]` names another worktree than its
    manifest.
  - M8: pre-WP6 checkpoints are refused; bump the version in step 3.
  - M9: names and units are fine.

## Scripts the reviewer left

In `$CLAUDE_JOB_DIR/tmp/wp6_review/` of the session: `wp6_cadence_checks.jl`
checks, not run by the reviewer:
  - parity at `stage` and `dss` with ARS343, the follower, copies and a
    limiter;
  - the gross bitwise against stepping by hand;
  - the ledgers across a restart.

`check1.jl` to `check5.jl` are its smaller checks.
