# Review of WP4a's code, 2026-09-24

This is the `clima-numerics-reviewer` review at effort xhigh. It covers
`claude/water-tags-edmf-wp4a` at `905b7ff5` against `fd07d902`. It is
condensed here, with the reviewer's `file:line` evidence kept. How each point
was taken is in G3_TODO, under WP4a.

**Verdict:** draft as is. No parity break and no wrong result in the kernels.
S1–S4 should be fixed before the PR is marked ready.

## Computed by the reviewer

  - **The kernels, on random cells.** It ran `ShareDifferences`, `SplitShare`,
    `_exchange_room` and `_exchange_energy_ratio` on 2e5 random cells in each
    of 8 cases: Float64 and Float32, each with a closed partition, a 5% drift,
    `ρa⁰ < 0` and `ρaʲ < 0`.
      + No share was non-finite.
      + Within a subdomain the shares summed to `S`, to 4.4e-16 in Float64
        and 2.4e-7 in Float32.
      + Source tags stayed in [0, 1].
      + Partition shares ranged over [−1.1e-16, 1.05].
  - **Float32 where `ρa⁰q⁰` underflows.** The ratio is Inf, the differences
    are NaN, and every tag falls back to its grid share, as it should. A NaN
    tag falls back too.
  - **Known issue 4's scalar Newton model**, at c = 0.05 and 0.145. No entry
    and both entries are exact after one iteration. The diagonal alone is off
    by 2.5e-3 and 2.1e-2, which is `Ŷc²/(1+c)`.
  - **The 0M EDMF column in the default mode, at its initial state:**
      + the exchange's tendency is bit for bit the same after its scratch is
        set to NaN and after `add_split_rainout!`;
      + `add_split_rainout!` allocates 8 B per call, and
        `water_tag_precipitation!` allocates 1016 B;
      + `implicit_tendency!` takes 177 µs, `add_split_rainout!` 11.9 µs and
        `water_exchange_inputs!` 8.0 µs, which is 4.5%;
      + the partition's increment matches `S(Δʲ+Δ⁰)` to 1.1e-16 of max|Δ|.
        But `Δʲ` is 0 at that state, so the updraft's part went untested.

## Should fix

**S1. The integration tests would pass a wrong split**
(`test/tagged_water_edmf_0m_integration.jl:226, 238, 302`). The partition's
sum `S(Δʲ+Δ⁰)` holds whatever the shares within a subdomain are.
  - These would all pass:
      + the two subdomains swapped;
      + either subdomain at the grid share;
      + the environment's difference with the wrong sign;
      + `S` dropped, since max|S−1| is 1.1e-16 on this column.
  - The 1e-3 tolerance measures the partition's residual, not the identity,
    which holds to about 1e-16.
  - Rain plus snow equals the whole by construction.

The fix it proposed:
  - get each subdomain's part from the real code by zeroing one cached
    `dq_tot_dt`;
  - assert the updraft's share: the copy's own share with copies, or
    `S(φᴺ+Δφ)` from `ShareDifferences` in the default mode;
  - check the partition's sum to about 10 eps;
  - compare `prra_tag` with `prra`.

**S2. Tests missing from the note's section 6.**
  - The explicit path. Under 0M EDMF with explicit microphysics the split
    runs from `remaining_tendency!`, and no test reaches it.
  - An allocation gate on the 0M split path.
  - `!splits_rainout` for the non-EDMF and EDOnly paths.
  - The exchange bit for bit, as a test.
  - The unit test's cases (`test/tagged_water_tests.jl:1257-1291`) are fixed
    and hand-made. They do not go through `ShareDifferences`, and none has
    `ρa⁰ ≤ 0`, Float32 or an Inf ratio.

**S3. The plume is computed twice** (`tagged_water_rainout.jl:109` and
`tagged_water_edmf.jl:300`). This is correct, since each consumer rewrites all
of the scratch before it reads it. It costs 8.0 µs, 4.5% of
`implicit_tendency!`. It contradicts the note's sections 2 and 7. The reviewer
recommended amending the note and recording the cost.

**S4. A docstring overclaims** (`tagged_water_rainout.jl:85-87`). It says
that without an exchange "the shares are the grid mean's". That fails where a
clamp binds. Tags of (1.5, 0.5, 0.2)·ρq_tot split as (1.125, 0.375, 0.15)
against the grid's (1, 0.5, 0.2). A source tag's default share is
`S·min(ε̄ᵢ/total, 1)`, relative to the partition's total.

**S5. `pr_tag` costs O(N²) per output** (`tagged_water_rainout.jl:265-276`).
Each call allocates N fields and runs the whole split for one tag. Compute
only the requested tag, into scratch.

## Minor

  - Partition shares lie in [0, S] only up to rounding.
  - Known issue 4:
      + the status line states the scalar model as fact;
      + `:113-118` still gives the grid rule's increment, which is false under
        the split;
      + the line references are stale (the bracket is at
        `implicit_tendency.jl:65-88`);
      + "costs nothing" holds on the grid path only, since the split's shares
        change during the stage.
  - Stale `pr_tag_*` entries survive a later untagged model in one session,
    and asking for one then errors.
  - `docs/src/tagged_water.md:369`: with copies, the sum is `pr` up to the
    copies' own residual too.
  - The reviewer found no GPU issue.

## Scripts the reviewer left

In `$CLAUDE_JOB_DIR/tmp/wp4a_review/` of the session:
  - `mutants.jl`: the test's criteria on mutant splits;
  - `explicit_parity.jl`: parity on the explicit path, default and copies;
  - `kernels.jl` and `sim_checks.jl`.
