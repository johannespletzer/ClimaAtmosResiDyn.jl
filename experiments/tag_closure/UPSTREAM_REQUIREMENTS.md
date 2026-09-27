# Development requirements for upstream ClimaAtmos

Changes the tagging programme needs from upstream `CliMA/ClimaAtmos.jl`. Each
one would change the model's own results, so it cannot be made in this fork:
the fork's results must stay bit for bit those of upstream
([Fork parity with upstream](../../docs/clima_atmos_specific.md#fork-parity-with-upstream)).
An item goes upstream as an issue or a PR once the evidence below supports
it. After it merges, the fork follows it and re-baselines its parity reference.

Started on 2026-09-23 at the owner's request. Add an item when a finding shows
that a tag family is limited by the parent's numerics or physics. Close it
when upstream has merged the change and the fork has followed.

Not listed here:

  - upstream bugs found in cleanup reviews, which the fork leaves alone on
    purpose: `docs/known_issues.md`, issue 6;
  - the named parity exception `dd06318f`, for which no upstream PR is planned
    (DECISIONS, decision 12).

| ID  | Requirement                                                                                                               | Why the fork needs it                                                                                                | Status                                         |
|:--- |:------------------------------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------- |
| UP1 | A Jacobian diagonal for the implicit 0M rain-out: the updraft's `q_totʲ`, with `ρaʲ` and `mseʲ`, and the grid mean's sink | The 0M updraft copies and the grid-scale tags lag their rain-out after a fixed number of Newton iterations           | Waiting on evidence: the TRMM 0M Newton ladder |
| UP2 | Lift the model's gate on 2-moment microphysics, and fix the parent's P3 sedimentation                                     | The water tags accept 2M once the gate lifts, and refuse P3 until its sedimentation is fixed (DECISIONS, decision 6) | Waiting for upstream                           |

## UP1. A Jacobian diagonal for the implicit 0M rain-out

**The gap.** Under 0M with `implicit_microphysics: true`, the default, the
updraft rains out as `q_totʲ += dq (1 - q_totʲ)` and `ρaʲ += ρaʲ dq`, with
`dq ≤ 0` the updraft's `dq_tot_dt` (`microphysics_tendency!`). The grid mean
loses water the same way. `ManualSparseJacobian` has no entry for either term:
there is no microphysics update among its block updates. With the default
single Newton iteration, the rain-out is taken with its value at the start of
the step, not solved for.

**What it costs the tags.**

  - The grid-scale tags' implicit attribution has no diagonal either
    (`docs/known_issues.md`, issue 4).
  - The water tags' updraft copies mirror the rain-out as
    `χᵢʲ += dq (clamp(χᵢʲ/q_totʲ, 0, 1) - χᵢʲ)`. Their diagonal would be
    `dq (1/q_totʲ - 1)` away from the clamp. The fork gives them none, on
    purpose. With no entry for `q_totʲ` either, the copies' rows and
    `q_totʲ`'s have the same diagonal blocks, so each Newton update of the
    copies sums to `q_totʲ`'s over a closed partition. An entry for the copies
    alone would part them, and the copies' repair would reshape their
    provenance. So the copies lag as `q_totʲ` does.

**Would upstream's entry improve results?** Only with few Newton iterations,
and only in the convergence: a converged solve gives the same answer with or
without it. The stiffness is about `dt/τ`, the step over the rain-out
timescale, 0.1 to 0.15 on the fork's 0M cases, so the gain per step is modest.
For the copies the lag is shared out by share, so its effect on their
composition is second order. Not measured yet.

**The evidence that decides it.** V-W3's TRMM 0M Newton ladder: the copies with
1, 2 and 10 iterations, and the default mode with 1 and 10
(`configs/w3_trmm0m_*`). If the copies' shares move beyond G3_PLAN 6.1's
per-tag budget between 1 and 10 iterations, propose the entry upstream. If they
do not, record the bound in FINDINGS and close this item.

**The fork's follow-up, once upstream has it.** Give each copy the same
diagonal as `q_totʲ`, not its own exact derivative. Newton with an approximate
Jacobian converges to the same answer, and the copies' updates keep summing to
`q_totʲ`'s. About 20 lines in `update_sgs_*` of `manual_sparse_jacobian.jl`,
and a test. The grid-scale tags' diagonal of issue 4 follows the same rule.

**Effort upstream.** About a day: the derivative of the 0M sink with respect
to `q_totʲ` (about `-1/τ` where the condensate is above the threshold, through
the saturation adjustment), the blocks for `q_totʲ`, `ρaʲ` and `mseʲ` and the
grid mean's, and tests. Then upstream's review, and the fork's re-baselined
parity once it merges.

**Caveat.** The copies' updates match `q_totʲ`'s exactly only under 0M. Under
1M, `q_totʲ` couples to the updraft's condensates through off-diagonal blocks,
and the copies have only a diagonal (WP3's numerics review, S5). That gap would
remain.

*Sources: the owner's review of #101 (P1), 2026-09-23; the discussion that
followed; `docs/known_issues.md`, issues 3 and 4.*
