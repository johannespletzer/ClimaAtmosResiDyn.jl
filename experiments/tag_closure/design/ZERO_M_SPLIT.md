# The 0M sink split by subdomain, `pr_tag` under 0M, and known issue 4: the design note of WP4a

Written on 2026-09-24 for G3's WP4a (G3_PLAN 4.4, G3_TODO), which the owner
added to the session's goal that day. **Second version**, after its review by
`clima-numerics-reviewer` (xhigh,
[review/agent_reviews/wp4a_design_review_2026-09-24.md](../review/agent_reviews/wp4a_design_review_2026-09-24.md));
section 9 says how each point was taken. `file:line` references are to
`claude/water-tags-edmf-wp5` at `fd07d902`, which contains #100, #101 and WP5.
The split (2) and `pr_tag` (3) are coded after this version. The switch (4)
waits on the owner's choice. *The owner chose the pair on 2026-09-28
(DECISIONS.md, "WP4a's two points"). WP4a-J built it (4, "As built") and
completed the experiment's pre-registration (5.1) on 2026-09-29.*

## 1. The problem

Under 0M the only sink of total water is the rain-out, per subdomain under
prognostic EDMF (`microphysics/tendency.jl:101-133`):

    Δ⁰ = ρa⁰ · dq_tot_dt⁰,    Δʲ = ρaʲ · dq_tot_dtʲ,    Yₜ.c.ρq_tot += Δ⁰ + Σⱼ Δʲ.

The `:microphysics` bracket sees only the sum and hands the loss out by the
grid mean's share (`tagged_water.jl:356-396`). The updraft, where most rain
forms on a deep case, holds a different composition. Under copies the copies
lose by their own share (`_copies_rain_out!`) and the grid tags by the grid
mean's, so the environment's implied values can move the wrong way (WP3
review, N6).

## 2. The split

**The rule.** Under 0M the increment is applied with each subdomain's share,
for both signs: `Σₖ Δᵏ φᵏᵢ` over the updraft `j` and the environment `0`. Under
0M `dq_tot_dt ≤ 0`, but `Δᵏ` can be positive where an iterate's `ρaᵏ < 0` (the
filter clamps `ρaʲ` only to `ρʲ`, `mass_flux_closures.jl:274`, and Newton
iterates are unfiltered); applying the share for both signs keeps such water
in the partition rather than giving it to `:microphysics` source tags. `Δᵏ` is
exactly the model's term: `Δ⁰` with `ρa⁰(Y.c.ρ, Y.c.sgsʲs, …)` as at
`tendency.jl:109`.

**The shares.** Write `S = Σ_P water_tag_fraction(ρq_tagᵢ, ρq_tot)`, today's
partition sum of clamped grid shares, and `φᴺᵢ` the partition-normalized
shares that `ShareDifferences` works on (`min(ε̄ᵢ/total, 1)`, negatives
clamped; `energy_source_tags.jl:1965-1966, 2044-2045, 2093`).

| mode    | updraft `φʲᵢ`                                                 | environment `φ⁰ᵢ`                                                                                           |
|:------- |:------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------- |
| default | `S·(φᴺᵢ + Δφʲᵢ)`, from `ShareDifferences(flags, false)`       | `S·(φᴺᵢ + Δφ⁰ᵢ)`, from `ShareDifferences(flags, true)`                                                      |
| copies  | `clamp(χᵢʲ/q_totʲ, 0, 1)`, the share `_copies_rain_out!` uses | `(ρq_tagᵢ − ρaʲχᵢʲ)/(ρq_tot − ρaʲq_totʲ)`, clamped to [0, 1] and renormalized over the partition, times `S` |

The factor `S` keeps today's behaviour of a drifted partition, whose
residual keeps its ratio to `ρq_tot` as the cell rains out. Without it the
partition's loss would sum to `Δ` exactly and the residual would keep its
absolute size instead. The reviewer checked the normalized shares over 2e5
random cases: in [0, 1] and summing to one to 2e-15 in each subdomain.

**Guards and fallbacks**, each to the grid share `water_tag_fraction`, which is
today's rule:

  - the partition's total is not positive (the normalized share would be
    `0/0`);
  - `edmfx_sgs_mass_flux: false`, where the default mode's scratch does not
    exist (`tagged_water_edmf.jl:118`) though the updraft still rains out;
  - where the exchange does not run (the bound's room negative, a non-rising
    cell), so the updraft's rain falls back to the grid composition;
  - copies: where `ρq_tot − ρaʲq_totʲ ≤ 0`, or every numerator is ≤ 0;
  - Float32: where the exchange's water ratio is not finite
    (`_exchange_energy_ratio` is Inf where `ρa⁰q⁰` underflows, and `−θ·Inf·0`
    is NaN; pre-existing), guarded with `isfinite`.

A **source tag** takes its own clamped share, clamped to [0, 1] in the loss:
in the default mode its environment share is not bounded otherwise
(`energy_source_tags.jl:2082-2090`; the reviewer found 1.19 in a plausible
case and 114 at worst).

**Where the shares come from.** Once per implicit tendency evaluation, at its
top, the default mode's plume and bound are computed into scratch; the
microphysics bracket and the SGS flux's exchange both read them. Today the
exchange computes them itself (`sgs_mass_flux_of_water_tags!`,
`implicit_tendency.jl:126-133`), after the bracket (41-65), and overwrites the
plume in place (`tagged_water_edmf.jl:306-307`); so the exchange is split into
the shares' computation and their use, and a test checks that its tendency is
bit for bit what it was. On the explicit path, which has no exchange, the
bracket computes them itself. Everything the split writes lives in
`p.scratch`, which the autodiff Jacobian converts to dual numbers.

*As built (the code review, S3, 2026-09-24):* the exchange was not split. The
bracket calls `water_exchange_inputs!` itself, and the exchange calls it again,
so the plume is computed twice per implicit evaluation. Each consumer rewrites
all of the scratch before it reads it, so neither reads a stale value; a test
checks the exchange's tendency bit for bit around the split. The cost the
reviewer measured on the 0M EDMF column is 8.0 µs per evaluation, 4.5% of
`implicit_tendency!`. Sharing one computation would need a flag through the
exchange's path, and is not done.

**The copies' updraft share is unnormalized**, as `_copies_rain_out!`'s is, so
the partition's updraft loss is `Δʲ·Σ_P φʲᵢ`, which equals `Δʲ` where the
copies' partition holds `q_totʲ` (the repair keeps it so up to W21's
residual). On the explicit path the environment's implied values then change
by `Δ⁰φ⁰ᵢ`; on the implicit path `sgs_ρa_implicit_tendency!` overwrites the
`ρa` sink (`implicit_tendency.jl:147`; `initialize_implicit_problem.jl:282-291`),
so they change by `Δ⁰φ⁰ᵢ + Δʲχᵢʲ`. Either way they move with the right sign,
which fixes N6; the tests expect each path's own value.

**Unchanged:** the grid-mean path without EDMF (`tendency.jl:77-87`) and
`EDOnlyEDMFX` (where `ρa⁰` returns `ρ`, `variable_manipulations.jl:510-517`)
keep today's bracket bit for bit, and a test says so. The energy source tags'
0M bracket keeps the grid share under EDMF (`implicit_tendency.jl:87`); that is
a G4 item.

## 3. `pr_tag` under 0M

Under 0M, `pr` is the column integral of `ᶜρ_dq_tot_dt`, split into rain and
snow by the grid mean's temperature, and it is upward-positive, so negative
(`set_precipitation_surface_fluxes!`, `microphysics_cache.jl:1269-1293`;
`core_diagnostics.jl:611-612`). `pr_tag_<name>` is the column integral of the
tag's applied increment `Σₖ Δᵏφᵏᵢ`, both signs, with the same sign and the same
rain and snow split (`prra_tag_<name>`, `prsn_tag_<name>`). The shares are
recomputed from the state at output time; the scratch is not read, since the
exchange overwrites it. Over the partition `Σ pr_tag = S·pr`, which is `pr`
where the partition is closed; the test checks `Σ pr_tag = pr` on a closed
partition and the factor `S` otherwise. It is instantaneous, of the state at
the step's end (`precomputed_quantities.jl:896-904`), not the flux applied in
the step. Under 1M it is not defined here: WP4b's rain and snow parts give it.

## 4. Known issue 4: what the analytic Jacobian needs

The tags' loss `min(Δ, 0)·ρq_tagᵢ/ρq_tot`, with `ρq_tot` the Newton iterate,
has two partial derivatives: the diagonal `min(Δ,0)/ρq_tot`, and a cross term
to the parent, `−min(Δ,0)·ρq_tagᵢ/ρq_tot²`. The parent's own sink needs no
`ρq_tot` entry, since `dq` is frozen during the solve
(`microphysics_cache.jl:681-682, 700-729`).

**The reviewer's scalar Newton model** (Newton starting from the predictor,
CTS `imex_ark.jl:212, 312`; the Jacobian updated every iteration), with
`c = dtγ|Δ|/ρq_tot`, for a pure proportional sink:

| entries                         | after one iteration | error                                                                  |
|:------------------------------- |:------------------- |:---------------------------------------------------------------------- |
| none (today)                    | `Ŷᵢ(1 − c)`         | none: the shares are invariant, so this is the fixed point             |
| the diagonal alone              | `Ŷᵢ/(1 + c)`        | `Ŷᵢc²/(1 + c)` per stage; the partition leaves the parent by that much |
| the diagonal and the cross term | exact               | none                                                                   |

With other implicit processes changing the shares in the stage, the diagonal
alone trades per-tag error against closure, 7.5 times worse in one case, and
the pair beat both in every case. **So known issue 4's claim is backwards**:
today's missing entry costs nothing for the pure sink, and the diagonal alone
would cost. Known issue 4 is restated in `docs/known_issues.md` with this, in
WP4a's PR.

**The owner's choice** before any switch is coded:

  - **(i) the pair.** The cross block is one-way, a tag's row with the
    `ρq_tot` column, so the model's own solve is untouched. But
    `uncoupled_jacobian_names` (`manual_sparse_jacobian.jl:736-751`) would then
    no longer solve the tags apart; the split solver needs a back-substitution
    step, `rhsᵢ −= J_{tag, ρq_tot}·Δρq_tot`, with its own parity test. This is
    the Jacobian that would actually help.
  - **(ii) the diagonal alone**, as the owner's review of #100 asked for as a
    test, with the prediction above stated before it runs.

**The switch's specification**, for either: an experimental key,
`water_tag_rainout_jacobian: true` (default `false`); the entry
`dtγ·min(Δ, 0)/ρq_tot` in the code's convention (`dtγ∂T/∂Y − I`,
`manual_sparse_jacobian.jl:2264, 1308`), added after
`update_diffusion_jacobian!` (which overwrites the passive tracers' diagonals,
1564-1575), in a `TridiagonalRow` block (`merge_jacobian_blocks`, 435-445);
a no-op under explicit microphysics and under 1M, refused under
PrognosticEDMFX (the split's derivative is not this), and documented under
`use_auto_jacobian`, which fills the tags' tridiagonal blocks itself. The
diagonal alone keeps parity: no model row has a tag's column. It changes no
state, so it is outside the restart guard; the manifest stamps it.

*As built (WP4a-J, 2026-09-29), the pair,* on `claude/wp4a-j-jacobian-switch`
at `f2c1e6a5`, from `main` at `43b01ca1`. The key and its default are as
specified. Each tag's row gets both entries: `dtγ·min(Δ, 0)·∂φ/∂ρq_tagᵢ` on its
diagonal and `dtγ·min(Δ, 0)·∂φ/∂ρq_tot` in a diagonal block to `ρq_tot`, with
`Δ = ρ·dq_tot_dt` as `microphysics_tendency!` adds it. Away from the clamps
these are the formulas above. Where `water_tag_fraction`'s clamp binds, or
`ρq_tot ≤ 0`, the share does not move, and both are zero; at the clamp's two
ends the unclamped slope is taken. The split solver back-substitutes the
block to `ρq_tot` after the model's fields, as it does the sedimentation
cross blocks. So the blocks exist only with the split solver: under
`use_auto_jacobian` the key does nothing, like `use_dense_jacobian`. With
explicit diffusion the tag's diagonal starts at `−I` in the update; with
implicit diffusion the entry adds to the diffusion's. Tests:
`test/tagged_water_rainout_jacobian_tests.jl` (the entries against finite
differences of the tags' kernel, the no-op cases, the refusals) and
`..._integration.jl` (the new group `tagging_water_rainout_jacobian`: every
model field bit for bit with the key, the entries from `update_jacobian!`, the
back-substitution, no added allocation, a restart that switches it on).

## 5. The experiment, pre-registered

On the raining 0M column of V-W0a (DYCOMS RF02 without EDMF, ARS222, implicit
microphysics, 2 h; W15, W16), with `water_tag_transport: tracer` pinned, since
the follower would move the switch's closure change into its ledger.

| runs                 | dt            | Newton                              | switch     |
|:-------------------- |:------------- |:----------------------------------- |:---------- |
| the references       | 120, 60, 30 s | 20 (checked against 40 on the tags) | off        |
| the Newton ladder    | 120 s         | 1, 2, 10                            | off and on |
| the time step ladder | 60, 30 s      | 1                                   | off and on |

Eleven runs plus the 40-iteration checks. `newton_rtol` is not used: it tests
the whole state's norm, which `ρe_tot` dominates (`integrator.jl:109-113`;
CTS `convergence_checker.jl:75-86`), so it does not certify the tags. The
Newton residual norms are not reported by the stepper, so they are not read.

**The primary readout** is the on−off difference at each rung: the parent is
bit for bit the same in both, so the difference isolates the entry. Secondary:
each run against its dt's reference, per tag (L1, L∞, with the verifier), and
`q_tag_res`.

**Predictions.** `c ≤ dtγ(q_c/q_tot)/τ` with τ = 1000 s (the 0M
`precipitation_timescale`), about 2e-3 on this column (dtγ = 35 s at dt 120 s);
the pure-sink part of the diagonal-alone error, `c²/(1+c)`, about 3.5e-6 of the
cell's water per stage, scaling as dt²; off and on agree at ten iterations.

**Decision rule.** Known issue 4 is **closed** if the off runs are within the
6.1 per-tag budgets of their dt's reference at one iteration; **restated with
its size** otherwise.

**The copies' part of issue 4** (their implicit rain-out, `known_issues.md:98-111`)
is out of this experiment: it needs the 0M EDMF copies column's own 1/2/10
ladder, which V-W4's pattern gives on TRMM (W21) and is proposed as a follow-up.

### 5.1 Completed for WP4a-J, before any run (2026-09-29)

What the section above leaves open is fixed here, on the owner's choice of
the pair. Nothing below changes after the runs. The switch is the one built
in section 4, at `f2c1e6a5`.

**The runs,** `configs/wp4aj_*.yml`. The column is `w0a_0m_implicit_*_2h`'s
(DYCOMS RF02, 0M without EDMF, the DYCOMS radiation, the decaying diffusion,
implicit microphysics and diffusion, ARS222, 30 levels, 2 h, Float64) with
the tags `tropo`, `strat` and `evap` and `water_tag_transport: tracer`.

| run                              | dt            | Newton   | switch     |
|:-------------------------------- |:------------- |:-------- |:---------- |
| `wp4aj_ref_dt{120,60,30}_n20`    | 120, 60, 30 s | 20       | off        |
| `wp4aj_ref_dt{120,60,30}_n40`    | 120, 60, 30 s | 40       | off        |
| `wp4aj_dt120_n{1,2,10}_{off,on}` | 120 s         | 1, 2, 10 | off and on |
| `wp4aj_dt{60,30}_n1_{off,on}`    | 60, 30 s      | 1        | off and on |
| `wp4aj_dt120_n1_untagged`        | 120 s         | 1        | no tags    |

That is 17. Section 5 says eleven runs, but its table lists thirteen, and
the 40-iteration checks make sixteen. The untagged twin is added: OD2's rule
reads a case's window from its untagged run, and it gives parity. Every run
writes its fields every 6 minutes, a multiple of each time step, so the runs
of one comparison share their output times.

**The measures,** by `analysis/water/wp4aj_score.py`. It takes every number
from the verifier (`analysis/evidence/compare_runs.py`), one call per pair,
and every budget from the verifier's own table and `judge_tag_row`.

  - **P1:** the untagged twin against `wp4aj_dt120_n1_off`, every model field
    bit for bit (`--parity-only`).
  - **P2:** at each of the five rungs, on against off, every model field bit
    for bit (`--expect-parity`).
  - **M1, the primary readout:** the same five pairs, each tag's L1 and L∞ of
    on against off, at every 6-minute output to 1 h and every 12 minutes to
    2 h.
  - **M2:** each on and off run against its dt's 20-iteration reference, per
    tag, at the same outputs.
  - **V1:** each 20-iteration reference against its 40-iteration check, per
    tag.
  - **V2:** the column rains in the first hour: `pr` is not zero at some
    output up to 1 h in `wp4aj_dt120_n1_off`.
  - **Reported:** each run's gross residual `G(t)` (6.1's definition over the
    run's own water), OD2's startup end read from the untagged twin, and the
    bound on `c`, `dtγ (q_c / q_tot) / τ`, largest over cells and outputs up
    to 1 h.

**The budgets, reused.** OD2's window for DYCOMS 0M is its startup, the rain
event, which W15 found ends within the first hour; the case has no
established flow (ROADMAP.md, OD2's table). So G3_PLAN 6.1's first-hour row
applies: L1 ≤ 1% for the region tags and ≤ 10% for the source tag, L∞ ≤ 25%,
and a tag under 1% of the partition passes on `∫ρ|Δq|dz ≤ 2e-4 ∫ρq_tot dz`.
They are judged at 1 h, where the verifier's `--judge` judges that row. The
other outputs are reported, not judged, as 6.1 reports its 6 h and 12 h
outputs. V1 is judged with the same budgets at 1 h. P1 and P2 are bit for
bit, the fork's rule. No new tolerance is set.

**The verdict,** section 5's decision rule, read as follows:

  - P2 fails: a parity defect of the switch. Nothing else is read.
  - P1, V1 or V2 fails: not assessable.
  - Otherwise, known issue 4 is **closed** if the three off runs at one
    iteration (dt 120, 60 and 30 s) are within the budgets of their dt's
    reference at 1 h, every tag; **restated with its size** otherwise: the
    tags that miss, with their L1 and L∞.

The on runs are judged the same way and reported, not used in the verdict.
M1 is reported; section 5 names it the primary readout because the parent is
the same in both runs, so it isolates the entries.

**Predictions,** written before the runs, for the pair:

  - `c` at dt 120 s is about 2e-3, as section 5 says: the scorer's bound on
    W16's one-iteration run is 2.3e-3 (its smoke test, below). It halves with
    each halving of dt.
  - In the scalar model the pair is exact for a pure proportional sink, and so
    is no entry. So on and off at one iteration differ only through what the
    other implicit term, the diffusion, does to the shares in the stage. M1 is
    expected to be well below the off runs' M2, and to fall toward V1's level
    by ten iterations.
  - The off runs pass. W16 measured the region tags' 1-against-10-iteration
    difference at 1.0e-3 to 1.2e-3 in L1 at 1 h, a tenth of the budget.
  - V1 is at the rounding level.
  - OD2's rule may not end the startup within 2 h: evaporation keeps the
    column's water rising (W15), and on W16's run the rule's condition is not
    met. The judged hour stays 1 h.

**The scorer's smoke test,** before any run. It ran on W16's outputs, linked
under the 17 names (`w0a_0m_implicit_newton1_2h` for the tagged runs,
`..._newton10_2h` for the references, copies where a pair would otherwise
compare one directory with itself). Every step ran. Its numbers are W16's,
not this experiment's.

**The jobs.** From the run tree `../ClimaAtmosResiDyn-wp4aj-run`, the model
commit merged with this record commit, detached, and its own `.buildkite`:

    env CONFIG=experiments/tag_closure/configs/<run>.yml \
        experiments/tag_closure/runscripts/submit_g3.sh \
            --account=hpda-c --partition=hpda2_compute --time=02:00:00 \
            --cpus-per-task=2 --mem=48G --job-name=g3-<run> \
            --output=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.out \
            --error=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.err

for the 17 runs. Then `python3 analysis/water/wp4aj_score.py`, which writes
`output/wp4aj/`.

## 6. Tests

  - **Unit**, on the real kernels, random states: the shares finite, in
    [0, 1] and summing to one per subdomain, including a partition total of 0,
    the bound binding, no exchange, `ρa⁰ ≤ 0`; the split's increment summing
    to `S·Δ`; a source tag clamped; tolerances at eps × |Yₜ before the
    process|.
  - **Integration** (the 0M EDMF column of `tagging_water_edmf_0m`): the
    partition's microphysics tendency equals `S·Δ`; `Σ pr_tag = pr` per column
    on a closed partition; the exchange's tendency bit for bit what it was;
    parity with the untagged column; the non-EDMF and EDOnly paths unchanged
    bit for bit; each path's expectation for the copies (2); no allocation in
    `implicit_tendency!` and `update_jacobian!`.

## 7. Cost

The shares once more per implicit evaluation, beside the exchange's own: 4.5%
of `implicit_tendency!` on the 0M EDMF column (the code review, S3). Once per
explicit evaluation on the explicit path. `pr_tag` at output only, one tag per
call into one scratch field. The switch: one diagonal block per tag
where there was the `-I` fallback.

## 8. For the owner

 1. **Known issue 4's Jacobian:** (i) the pair, with the split solver's
    back-substitution, or (ii) the diagonal alone as a test.
 2. **The copies' part of issue 4:** a follow-up ladder, or in WP4a.

## 9. The review, point by point

| point                                           | taken as                                              |
|:----------------------------------------------- |:----------------------------------------------------- |
| B1 the diagonal alone makes one iteration worse | section 4, the owner's choice; known issue 4 restated |
| B2 φ̄ undefined, mixed normalization            | section 2, `S·φᴺ` with guards                         |
| S1 source tags' environment share > 1           | section 2, clamped                                    |
| S2 `edmfx_sgs_mass_flux: false`                 | section 2, fallback                                   |
| S3 `ρaᵏ < 0` gives production                   | section 2, both signs                                 |
| S4 copies' edge cases and the implicit path     | section 2                                             |
| S5 the switch's specification                   | section 4                                             |
| S6 the experiment                               | section 5                                             |
| S7 the plume twice; the scratch overwritten     | section 2, computed once                              |
| S8 `pr_tag`                                     | section 3                                             |
| S9 non-EDMF and EDOnly unchanged                | section 2, tested                                     |
| minor                                           | sections 2-5                                          |
