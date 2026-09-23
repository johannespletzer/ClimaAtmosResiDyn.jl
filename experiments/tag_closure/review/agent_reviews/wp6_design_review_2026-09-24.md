# Review of `design/GROSS_ACCUMULATORS.md` (WP6), 2026-09-24

`clima-numerics-reviewer`, effort high, on the note's first draft, against
`claude/water-tags-edmf-wp5` at `1addf74c` and ClimaTimeSteppers 1.0.1. The
reviewer's report, condensed; its `file:line` evidence is kept. How each point
was taken is in the note's section 7.

**Verdict: not ready for code.** 3.1 (a gross twin and an event count beside
each cache ledger) is sound and parity-safe. 3.3, 3.4 (as costed), 3.2's
"retained" twin and 3.5's stitching need changing. No parity problem, provided
every new state field is split-solvable.

## Blocking

**B1. 3.3's per-stage gross is not a gross under the default ARS343.** The
post-solve hook's `dY` enters `T_imp[i] = (U−temp)/dtγ` (`imex_ark.jl:234-238,
284`), so a stage's entry reaches the step's result with weight
`b_imp[i]/a_imp[i,i]`: ARS343 [0, 2.773, −1.478, 1.0], ARS443 [0, 3, −3, 1, 1]
(computed). With stage values |left| = [0, 0.1, 1, 0.1] the "gross" falls to
−1.10 in one step (formula and a literal replay agree). The follower allows and
recommends ARS343. The note's stated limitation is also inverted: under ARS222
both weights are positive (2.414, 1), so the per-stage sum is an upper bound on
the per-step gross. Fix: a per-step gross by a read-only callback after each
step (`integrators.jl:427-440`), `G += |L − L_prev|` per cell for the signed
state ledgers, wrapped in `ParentBudget.ReadOnlyCallback`
(`parent_budget/checkpoint.jl:184-199`); or refuse the per-stage form when any
`b_imp < 0`.

**B2. 3.4's loss in the cache accumulates rates.** `_accumulate_water_tag!`
writes `Yₜ` (`tagged_water.jl:370-393`), once per explicit stage and, for
implicit microphysics, on every Newton iterate and residual evaluation, and
with Dual numbers under the AD Jacobians. A cache sum then scales with the
number of evaluations, not `dt·b` (`process_record.jl:14-19`), and a Dual
cannot be written into a Float cache field. Fix: state records like `prc_q_*`,
split-solvable, or take the loss from WP4a/WP4b's `pr_tag`.

## Should fix

**S1. 3.2's "retained" twin misses what the stepper keeps.** Under `stage` or
`dss` constraint changes on the solved stage are kept with weight
`b_imp[i]/γ` (`imex_ark.jl:245-249, 284`; the parent-budget adapter books them
so, `adapter.jl:224-226, 1826`); the end-of-step `lim!` rescale is kept
(`imex_ark.jl:85-88`); the "last constraint call" cannot be identified; the
test is tautological under `step`. Fix: a signed state ledger written in place
in the same kernels, which the stepper weights as it weights the tags, and the
per-step gross from it by B1's callback.

**S2. Attempted and retained differ at every cadence when a limiter changes
`ρq_tot`.** ClimaAtmos always passes `T_exp_T_lim!` (`integrator.jl:193,
239-243`), so `lim!` runs on every stage value i ≠ 1 (`imex_ark.jl:158-161`)
and its `rescale_water_tags!` shifts enter `ᶜwater_fix` and are discarded.

**S3. 3.5's stitching and "state ledgers need nothing" are wrong.** A segment's
cache ledgers are known only at its audit rows, which need not fall on the
checkpoint time. Fix: write the cache ledgers into the checkpoint
(`callbacks.jl:296-326`), or an audit row at every checkpoint. New state fields
make a pre-WP6 checkpoint fail `check_restart_fields` with a message about the
transport (`water_tag_checkpoint.jl:90-101`, `energy_source_checkpoint.jl:268-296`):
bump the checkpoint version and decide refuse or zero-fill.

**S4. Loss completeness.** Subsidence's in-column redistribution counts as
loss, making τ a turnover time; under 1M the only loss is surface outflow,
computed in `T_imp` (`implicit_tendency.jl:356`); WP4a redefines the loss by
subdomain and defines `pr_tag` as its column integral; WP4b changes it again;
numerical removals must stay out of τ; energy's τ depends on the reference and
the offset. Fix: define loss by channel at column level and move it to
WP4a/WP4b; WP6 keeps the gross, the count and the per-step |left|.

**S5. Float32.** A Float32 cache gross loses small increments after a large
one (99.99% of 172,800 increments of up to 1e-11 lost after one of 1e-3); a
state field's increment of 3e-10 on 1e-2 returns as 0 through `(U−temp)/dtγ`.
Fix: the cache gross and count in Float64, or compensated summation; document
the state fields' floor; a Float32 unit test.

**S6. The gross must be defined against the 0.2% budget, by mechanism.** The
partition repair is a zero-sum transfer, so `Σ|Δ|` is twice what is moved; the
rescale and the copies' repair shift all tags one way. `ᶜwater_fix` mixes the
limiter's rescale, the emptying where the parent is ≤ 0, and the partition
repair. Fix: "moved" per mechanism, `½Σ|Δ|` for transfers.

## Minor

M1 names collide (`q_tag_fix_gross_x`); extend the reserved prefixes, and the
energy source tags reserve only `res` today. M2 the count mostly counts
rounding; use a threshold relative to the cell's water. M3 the existing
`increment_*_gross` audit columns are gross over cells but net over time;
rename or document. M4 the updraft filter's clamp of each copy has no ledger.
M5 state the stitching test's tolerance; the output-interval test bitwise. M6
τ offline in Float64 over a window. M7 extend parity to `stage`/`dss`, a
limiter that fires, ARS343 with the follower and copies; allocation test on
`constrain_state!`; count the twins' cost. M8 reuse the parent-budget adapter's
classification of hook firings (`adapter.jl:209-235`,
`coverage_registry.jl:1035-1059`).

The note's section 2 table and its `file:line` references were confirmed.
