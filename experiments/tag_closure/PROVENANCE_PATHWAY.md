# The provenance pathway

Proposed on 2026-09-26, pending the owner's decisions OD9 to OD14. It is
written on `claude/plan-rev2` at `a6949414`. That branch held the newest
results: it was 78 commits ahead of `claude/tag-closure-record`, and no other
branch held a record commit that it lacked. Nothing here has been run. Every
number quoted is a finding already on the record, and values read before this
page was written count as prior evidence only, never as a scored test.

**Why this page exists.** The owner wrote on 2026-09-25 that the provenance of
the tags is much harder to reach than closure. Closure now holds to rounding in
almost every run. No provenance row has passed anywhere. Rev. 2 of the work
plan ([ROADMAP.md](ROADMAP.md)) already says that closure cannot stand in for
provenance. It blocks false positives, but it gives no route to positive
evidence. This page adds that route. It adds; it strikes nothing that the owner
approved. The in-place edits it makes elsewhere are listed in section 12.

## 1. The core idea

**Closure is one question per cell, and the model knows the answer.** Do the
partition tags sum to the parent? The model computes `ρq_tot` anyway, so the
check is against a true number.

**Provenance is the other N − 1 questions per cell, and the model computes no
answer for them.** They ask how the water or energy in the cell is composed.
The parent's step often does not say which water went where. That happens in
four places:

  - the parent's operator is nonlinear in the tracer (van Leer, clamps,
    limiters);
  - only net tendencies are exposed (1M microphysics, the Newton increment);
  - the sub-grid composition is hidden (EDMF's updraft and environment);
  - the state is corrected (the limiters, the filter, negative water).

In each place the tag code applies a *rule* that picks a composition.

**Every rule lives in the null space of closure.** Each rule is built to keep
the sum right: the zero-sum exchange, the repair by holdings, the follower's
column-neutral flux, renormalised shares, donor-share fluxes and WP4b's pool
shares. So closure cannot tell a right rule from a wrong one, as long as each
tag stays within `[0, parent]`. Closure does catch an error that leaves that
range. W43's start-composition rule drifted by 20 times the rain and failed
closure. What closure cannot do is track a composition error inside the range.
The record shows this several times:

  - W28: the follower closes TRMM 0M to 4e-15, while the tags differ from the
    copies by 0.83% to 1.72%;
  - W29: the cross blocks improved closure from 7.9e-3 to 2e-8, while `evap`
    moved from 3.8% to 5.8% away from the copies;
  - W36: at site 26 the same-sign and `|m|` rules close to rounding, move the
    same net 0.123, and give the same L1 against the copies;
  - W40: the remainder is 1.4e-7, while two rules that both close differ for
    `tropo` by 2.4% L1 and 6.2% L∞;
  - W45: the follower moves about 4.4% of the water a day while the partition
    closes to 8.4e-6;
  - E86: the energy tags close to 8.7e-6 of the throughput, while the repair
    trades 7.3% of it a day.

Worse, a correction that enforces closure turns a visible residual into an
invisible composition error. The leak that the follower absorbs in W40 is the
clearest case.

**Fidelity and conventional validity** ([design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md),
sections 3.1 and 3.7). Provenance has two parts.

  - *Fidelity:* the code solves its own declared tag equation. This can be
    measured, by invariants, ledger completeness, convergence, known answers
    and propagation.
  - *Conventional validity:* the declared equation is the right physics. There
    are three kinds of rule here.
      + *Definitional* rules can only be declared: the offset `c`, the mask gain
        of region tags, donor-proportional loss, bracket granularity.
      + Rules with a *faithful counterpart* can be validated one by one. The
        counterpart is the parent's own linear operator applied to each tag:
        per-tag subsidence, the rain and snow parts, the sub-stepped flows,
        the passive-tracer equations.
      + *Conventions with admissible alternatives* can only be bracketed: the
        surface rule, the follower's placement, the leak's attribution, the
        pool rule.

**Water has a well-posed truth; energy does not.** A water tag is a molecular
label, like an isotope without fractionation. Declare one assumption:
composition is well mixed inside the smallest volume the model resolves, a cell
or an EDMF subdomain. The truth is then the solution of a *linear* label system
driven by the parent's own fluxes and process rates. So exact references can be
built for water: pure transport with sources off, a manufactured or frozen
column, an exact denial run where water is passive. Energy has no molecular
truth. Its tags depend on the offset `c`; region integrals change by 150% to
180% when `c` doubles (E71). For energy only fidelity to the declared
convention can be certified, and conclusions must survive the `c`/2`c` pair.

**Every reference used so far is common-mode.** A reference cannot see an error
in a rule it shares.

  - The default and the copies share every grid-scale rule: mask gain, donor
    loss, subsidence through the bracket, the sedimentation reset and the
    partition repair. Subsidence is the sharpest case. It reaches the tags only
    through the local `:subsidence` bracket (`remaining_tendency.jl` lines 186
    to 188 on `main`), although `subsidence!` is first-order upwind and linear
    in χ. So the default-against-copies agreement tests only the plume and the
    exchange. The copies are also ineligible wherever they were scored (W21,
    W38, E84).
  - The ten-iteration twins share the follower.
  - WP4c's part 3 compares two rules that both close.
  - The passive tracer has its own surface convention: it gets nothing at the
    updraft's surface boundary (`tagged_water_edmf.jl`, "a tracer gets
    nothing"). It is also not subsided. E68 and W17 are confounded by this and
    by the mask gain.

So certainty needs **coverage**: each rule with material exposure must meet a
reference that does not share it. Agreement among references that share a rule
is never evidence for that rule.

**The 2% budget is a fidelity budget.** G3_PLAN 6.1 justifies the 2% per-tag
row as "the spread from the mixing convention alone, about 1% in L1 (E66)".
E66's L1 row is in fractions: 0.08 and 0.12 for the region tags, 0.68 to 1.26
for the source tags. So the convention spread is 8% to 126%, and the 2% cannot
score conventional validity. Convention spreads are reported beside it, never
scored against it. OD11 asks the owner to confirm this reading.

**What certainty can mean here.** Each tag gets an interval `[L, U]` on its
provenance error.

  - `L` is a lower bound on the uncertainty: the realized difference between
    admissible rules on the same parent.
  - `U` is an upper bound: the propagated gross exposure of every rule not yet
    validated (section 3).

Certainty rises only as `U` falls. `U` falls mostly by turning assumed rules
into faithful ones, which removes their terms. That works only where the
faithful operator is itself monotone.

## 2. The certainty ladder

Two axes, reported per tag, per case and per OD2 window. A lower rung is never
evidence for a higher one. Every result states its fidelity level, its
`[L, U]`, and the rules it leaves uncovered.

**Fidelity: does the code solve its declared equation?**

| Level                 | Certifies                                                                                                                                  | Required evidence                                                                                                                                                                                                                                                           | Cannot certify                                                                                                                                                                           |
|:--------------------- |:------------------------------------------------------------------------------------------------------------------------------------------ |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fid-0 closed          | The tags are passive and sum to the parent                                                                                                 | Parity bit for bit; the closure rows; the negative-water latch not set (the parent-validity row voids the case otherwise)                                                                                                                                                   | Any composition                                                                                                                                                                          |
| Fid-1 well-posed      | The attribution is linear where it is declared linear, independent of tag order, symmetric in labels, bounded, and composes under grouping | Uniform composition (exists, 1e-12); permutation; a duplicate tag; proportionality (`evap_tropo` against `evap`); overlay at most parent; source integral at most production; superposition and aggregation with distinct footprints (needs PR-P4); the three-tag hull (V8) | That any rule is right. It is blind to a consistently wrong linear rule, and proportionality alone is blind to rules that are homogeneous of degree one (the repair, van Leer per field) |
| Fid-2 ledger-complete | Every mechanism that sets a label is named and classed, and each tag's change equals the sum of its named parts                            | Per-tag, per-process accounting from the same state (the `ic_miss_probe.jl` pattern), closing to rounding; every rise attributed                                                                                                                                            | The size of any rule's error                                                                                                                                                             |
| Fid-3 faithful        | The code solves its declared equation within a measured numerical error `F`, and injected errors do not grow beyond a measured `K`         | The follower's work split into lag and structure (PX7); the faithful parts converge (the OD3 refinement row); exact per-tag counterparts for bracketed transport (PX8); `K` from spike arms (PX9)                                                                           | Whether any assumed rule is the right physics                                                                                                                                            |

**Validity: is the declared equation right?**

| Level                           | Certifies                                                                                                                                                                | Required evidence                                                                                                                                     | Cannot certify                                              |
|:------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:----------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------- |
| Val-0 unbracketed               | Nothing                                                                                                                                                                  | —                                                                                                                                                     | —                                                           |
| Val-1 bracketed                 | A lower bound `L`: the realized same-parent spread over the admissible alternatives of each material rule. The tag is *convention-limited* where `L` exceeds the OD3 row | Realized same-parent pairs with feedback, or first-order estimates labelled as such; the list of admissible alternatives fixed by OD11 before the run | Errors that every alternative shares; any upper bound       |
| Val-2 bounded                   | `U ≤` the OD3 per-tag row. This is OD5's "provenance bounded, not validated", as OD9 proposes                                                                            | Fid-2 and Fid-3, which are `U`'s premises; the lemma of section 3; every realized rule-against-rule difference at most its `U`, else `U` is void      | L∞, unless the positivity premise holds; conventions; truth |
| Val-3 validated for named rules | Every material rule has passed a reference that does not share it, and the rules not validated fit within `U`                                                            | The coverage matrix (section 5); reference validity (floors, the level-1 check, a contamination bound); an independence certificate per reference     | Shared rules; definitional rules; untested regimes          |
| Val-4 held out                  | Val-3 carries over without retuning                                                                                                                                      | Val-3 on cases fixed before their runs (G3 criterion 8), with OD14's hygiene                                                                          | Regimes outside the envelope                                |

**Conventions** are declared in the claim contracts (G3 criterion 12,
[design/G4_CLAIM_CONTRACTS.md](design/G4_CLAIM_CONTRACTS.md)). Their spread,
such as `c`/2`c` or the mask's placement and width, is reported beside the
ladder. They never pass or fail.

**How the ladder maps onto rev. 2.**

  - Fid-0 is the contract's Parent validity and Closure rows.
  - Fid-1 is the Aggregation row plus a proposed Invariants row.
  - Fid-2 is the Intervention row plus a proposed Ledger-completeness row.
  - Fid-3 is the Convergence row plus a proposed Propagation row.
  - Val-1 is a proposed Rule-sensitivity row, and Val-2 a proposed Exposure row.
  - Val-3 is the Provenance and Comparator-eligibility rows, plus a proposed
    Reference-validity row.

**OD5.** OD9 proposes that "bounded, not validated" means Fid-3 and `U` within
the row. Rev. 2's three Insight 10 tests become parts of it:

  - the per-tag `led_fix` is the repair's term in `U`, with the repair's
    Lipschitz factor of at most 2;
  - refinement gives `F` and the lag-structure split;
  - aggregation is a Fid-1 premise.

"Bracketed" (`L` within the row but `U` above it) is reported. It does not
qualify at M5 unless the owner decides otherwise (OD9).

**OD8.** The counts do not change: 8 water and 8 energy tags, copies at 8, no
bridge. The ladder is reported per tag at 8 + 8. Aggregation is a premise test,
one nested-group run per configuration, not a bridge. Per-process, per-tag
accounting is done by probes, not by new state fields, because the build time
grows with the number of fields (W34: 699 s at 8 copies, 2417 s at 16).

## 3. The exposure lemma

Take two rule sets on the same parent. Compute the per-step difference `δⁿ`
between them from the same state, as the WP4c gate does. Then, per tag,

`‖e_i(T)‖₁ ≤ K · Σₙ ‖δ_iⁿ‖₁`,

where `K` is the supremum of the L1 operator norm of the full per-tag
propagator. The premises matter more than the formula.

 1. **The sum is gross, never net.** `Σₙ‖δⁿ‖`, not `‖Σₙ δⁿ‖`. WP4c's part 3
    (W40) accumulates `D` per cell and step without feedback and reports its
    net. So part 3 is a first-order estimate of `L`. It bounds nothing and
    certifies nothing. Its ratio to part 2b is not evidence for the lemma.
 2. **Where the alternative is unknown,** the per-tag term is
    the *worst-case form* `Σ G · max(a_i, 1 − a_i)`, with `G` the gross label-carrying mass of
    the faithful process. It is not the per-tag gross that the rule wrote,
    which under-bounds the minority tags.
 3. **Bracketed transport needs its exact per-tag counterpart (the *exact form*).** A bracket
    sees a net close to zero where labels still move. The 750 m label edge
    inside D4-W's well-mixed boundary layer is the case: the parent's
    subsidence tendency there is small, while `ρ|w| q |∂φ/∂z|` is not.
 4. **Hulls are optional.** Where the alternative is known to lie in a hull
    (the two cells of a face at both time levels, say), the factor becomes the
    range of `φ_i` over that hull. The hull must contain both trajectories,
    which needs a Gronwall widening.
 5. **`K` comes from unit spike arms,** not from smooth perturbations (PX9).

The sign-coherence index `s = ‖Σδ‖ / Σ‖δ‖` says when net and gross agree.

**Where the premises fail.** The propagator is not positive, and may not be
L1-contractive, wherever these act:

  - van Leer per field (it does not preserve order);
  - the partition repair (a clip then a rescale, Lipschitz up to 2);
  - the share clamp and renormalisation;
  - the exchange's blend factor θ, a minimum over the partition;
  - the environment clip;
  - any donor flux whose share Courant number exceeds one;
  - cells where the parent is at most zero (option C's cells);
  - on the centred rungs, the exchange's reconstruction
    (`_exchange_upwinding(upwinding) = upwinding` in `energy_source_tags.jl`),
    which is linear but not monotone;
  - the tags' truncated Newton solve, which lacks some Jacobian blocks.

The remedy is to move each nonlinear piece into the inventory of assumed rules,
with its own gross: `led_fix` for the repair, the clamp's cut, the exchange's
mass where θ is below one, van Leer's antidiffusive flux. What remains of the
propagator is then linear by construction, and PX9 measures `K` for it. **The
bound is only as good as the inventory**, so ledger completeness (Fid-2) comes
before any bound. W42 found rises that no ledger records, and E87 found `C4`
outside the residual, so the inventory is not yet complete.

**The L∞ route.** Suppose the propagator is positive, conservative and
constant-preserving. Uniform composition to 1e-12 already tests the last
property. Then the composition update is row-stochastic, and the sup norm of
the composition error cannot grow. A per-cell bound is then the accumulated
largest relabelled fraction per cell. This route opens only where PX9 finds
positivity. On the centred rungs it is not expected, for the two reasons in the
last two bullets above.

**Prior evidence on the size of `U` (read before this page, so not scored).**
On D4-W the follower's per-tag exposure for `tropo` over the gate's 0.924-day
window is 3.23% from `vdiff` and 3.97% from `sgs_mass_flux`
(`output/wp4c_gate/score.txt`). That is about 7.2% together. So a worst-case bound
cannot pass the 2% row on D4-W. Passing needs a hull, fewer assumed rules, or
PX7 showing that most of the follower's work is lag.

## 4. The rule inventory

Each rule acting on a tag, its class, and the per-tag account that exists
today. The claim contracts (OD11) must adopt this classification before any `L`
or `U` is scored. Otherwise a bound can be gamed by calling a rule definitional.

| Rule  | What it does                                                                                                               | Class                                                                             | Per-tag account today                             |
|:----- |:-------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------- |:------------------------------------------------- |
| WR1   | Region tags take new water by mask                                                                                         | definitional                                                                      | the brackets' records                             |
| WR2   | Loss by the grid-mean donor share                                                                                          | definitional at cell scale; assumed where the process acts in a sub-volume (WR15) | the brackets' records                             |
| WR3   | Subsidence and the GCM's large-scale subsidence reach the tags through the local bracket                                   | assumed; a faithful counterpart exists (per-tag `subsidence!`)                    | none per tag; the bracket sees the net            |
| WR4   | Large-scale forcing and nudging import water by label                                                                      | definitional label (`fcg`); its subsidence part is WR3                            | the brackets' records                             |
| WR5   | Rescale after the limiters, borrowing and constraints, by the receiver's composition                                       | assumed                                                                           | `q_tag_fix_*`, `fixgross`, `led_rescale`          |
| WR6   | Partition repair: a negative tag is charged to the positive ones by holdings                                               | assumed, nonlinear                                                                | `led_repair`, per-tag `led_fix`                   |
| WR7   | Share clamp and renormalisation                                                                                            | assumed, nonlinear                                                                | the clamp's cut (W33: 1.2e-15 under the follower) |
| WR8   | SGS mass flux by the donor cell's share (default mode)                                                                     | assumed                                                                           | none per tag                                      |
| WR9   | The exchange from the plume, and its bound θ                                                                               | assumed                                                                           | bound activation in the EDMF audit                |
| WR10  | The copies' own rules: surface relaxation to the grid-mean composition, the filter, their repair                           | assumed (the comparator's rules)                                                  | `q_tag_upfix_*`, `led_uprepair`, `led_upfilter`   |
| WR11a | The follower's moved part: the tags' mismatch with the parent's increment, carried by donor shares                         | assumed                                                                           | `q_tag_inc_moved`, per-tag `led_inc`              |
| WR11b | The follower's placement of the column total (same sign or \|m\|)                                                          | assumed                                                                           | `q_tag_inc_left`                                  |
| WR12  | Sedimentation resets the composition at each level (without the WP4b key)                                                  | assumed; the rain and snow parts are its faithful counterpart                     | none                                              |
| WR13  | WP4b's pool composition over the step                                                                                      | assumed                                                                           | the audit `q_rtag_aud_*`, `q_stag_aud_*`          |
| WR14  | The net-flow fallback between compartments                                                                                 | assumed; exact for one-way flows                                                  | the same audit                                    |
| WR15  | The 0M rain-out by the grid-mean composition, or split by subdomain (WP4a, #104)                                           | assumed                                                                           | `pr_tag`                                          |
| WR16  | Option C's entry of the negative part                                                                                      | assumed; void where the parent is invalid                                         | V5's ledger                                       |
| WR17  | The `q_tot_eff` leaks and their attribution (the follower's donor shares, or WP4c's ψ)                                     | gap, then a convention                                                            | `q_tag_leak_<path>`, WP4c's ledgers               |
| WR18  | The surface excess's composition: the plume starts at the grid mean, the copies relax to it, a passive tracer gets nothing | convention                                                                        | none                                              |
| WR19  | Bracket granularity                                                                                                        | definitional                                                                      | —                                                 |
| WR20  | Per-field nonlinear reconstruction of the tags' own transport (van Leer; SEM on the sphere)                                | assumed, nonlinear                                                                | none; zero on columns without a limiter (W3)      |
| ER1   | The offset `c`                                                                                                             | definitional                                                                      | the `c`/2`c` pair                                 |
| ER2   | Donor-proportional loss                                                                                                    | definitional                                                                      | —                                                 |
| ER3   | Mask placement and width                                                                                                   | definitional                                                                      | a bracket                                         |
| ER4   | The default exchange's repair (E86: 7.3% of the throughput a day)                                                          | assumed                                                                           | `e_src_fix_*`, `fixgross`                         |
| ER5   | The follower's placement (OD7)                                                                                             | assumed                                                                           | the left-out part (E79)                           |
| ER6   | The upward branch for ice and snow                                                                                         | assumed; its sign flips with `c`                                                  | none                                              |
| ER7   | Granularity of the radiation labels                                                                                        | definitional                                                                      | —                                                 |
| ER8   | The per-tag outflow of `C4` (E87)                                                                                          | gap                                                                               | none                                              |
| ER9   | The copies' composition rule M2                                                                                            | assumed                                                                           | `e_src_copy_res`                                  |
| ER10  | The energy exchange and plume                                                                                              | assumed                                                                           | bound activation                                  |
| ER11  | Energy subsidence (the `sub` tag)                                                                                          | definitional; no faithful counterpart, since the parent subsides `h_tot`          | the records                                       |
| ER12  | The energy follower's moved part                                                                                           | assumed                                                                           | `e_src_led_inc_*`                                 |

## 5. The coverage matrix

Each assumed rule and its references. `★` is the first valid reference, `○` a
further valid one, `×` invalid because it shares the rule, `—` not applicable.
Columns: `U` is the exposure form; Exact is the same-state exact counterpart
(PX8, PR-A); Air is the passive-tracer twin (PX11 on Soares, or PX17 with
PR-S); Copies is eligible copies (PX12); Replay is the sub-step replay (PX14);
`L` is the realized spread between rules.

| Rule                               | `U`                                                | Exact         | Air                               | Copies          | Replay | `L`                   |
|:---------------------------------- |:-------------------------------------------------- |:------------- |:--------------------------------- |:--------------- |:------ |:--------------------- |
| WR3 subsidence through the bracket | exact only                                         | ★ PX8, ○ PX16 | × (○ with PR-S)                   | ×               | —      | —                     |
| WR5 rescale by the receiver        | ★ PX20 (zero on columns)                           | —             | —                                 | ×               | —      | —                     |
| WR6 partition repair               | ★ `led_fix` × 2                                    | —             | ○                                 | ×               | —      | —                     |
| WR7 clamp and renormalisation      | ★ the cut                                          | —             | ○                                 | ×               | —      | —                     |
| WR8 SGS donor share                | worst case                                         | —             | ★ PX11                            | ○ PX12          | —      | —                     |
| WR9 exchange and θ                 | worst case                                         | —             | ★ PX11                            | ○ PX12          | —      | —                     |
| WR10 the copies' own rules         | the comparator's floor                             | —             | —                                 | itself          | —      | PX5 (cause)           |
| WR11a follower, moved              | lag goes to `F`, structure to the worst case (PX7) | —             | ○                                 | —               | —      | ○ PR-D (a convention) |
| WR11b follower, placement          | —                                                  | —             | —                                 | —               | —      | ★ PX3                 |
| WR12 sedimentation reset           | —                                                  | —             | —                                 | —               | ★ PX14 | —                     |
| WR13 WP4b pool                     | —                                                  | —             | —                                 | —               | ★ PX14 | —                     |
| WR14 net-flow fallback             | ★ the audit                                        | —             | —                                 | —               | ○ PX14 | —                     |
| WR15 0M rain-out                   | —                                                  | —             | ×                                 | ★ PX12 (as W32) | —      | —                     |
| WR16 option C's entry              | before the latch                                   | —             | —                                 | —               | —      | —                     |
| WR17 leaks and their attribution   | ○ the closed form                                  | —             | —                                 | —               | —      | ★ PX2                 |
| WR18 surface excess                | —                                                  | —             | × (○ if the level-1 check passes) | ×               | —      | ★ PX13                |
| WR20 per-field reconstruction      | PX20                                               | —             | —                                 | ×               | —      | —                     |
| ER4 energy repair                  | ★ `fixgross` (PX10)                                | —             | ×                                 | ×               | —      | ★ PX10                |
| ER5 energy placement               | the left-out size (E79)                            | —             | —                                 | —               | —      | ★ the E79 pair        |
| ER8 `C4` outflow                   | a Fid-2 probe                                      | —             | —                                 | —               | —      | —                     |
| ER10 energy exchange               | worst case                                         | —             | × (plausibility only)             | × (E84)         | —      | —                     |
| ER12 energy follower, moved        | ★ PX15                                             | —             | —                                 | —               | —      | —                     |

The definitional rules WR1, WR2, WR4, WR19, ER1 to ER3, ER7 and ER11 are declared, and
their spread is reported. They have no row here.

## 6. Theories

Each theory is falsifiable. "Prior" names what is already on the record; those
values were read before this page, so they are prior evidence only.

**PT1. The null space is weak but real.** Closure metrics do not track the
composition error between closing rule variants on a shared parent.

  - If true: across the same-parent pairs (W24 against W28, W40 against V1,
    E79, PX10), closure changes by at most 1e-4 and does not rank with the
    per-tag difference, which reaches percent.
  - If false: the closure change ranks with the per-tag difference.
  - Prior: W28, W29, W36, W40. W43's out-of-range rule failed closure, so this
    refines the null-space claim rather than refuting it.

**PT2. Subsidence is a large shared relabelling at D4-W's 750 m split.** Near
the inversion (about 795 m) the bracket gives subsiding water the receiving
cell's label. `subsidence!` is linear in χ, so the exact per-tag answer is
known.

  - If true: the gross exact-form exposure for `strat` exceeds 2% of its inventory a day. It
    concentrates between 700 and 950 m and is sign-coherent (`s > 0.7`). The
    realized difference with PR-A exceeds 2% L1 or 5% L∞ at 24 h.
  - If false: that exposure stays below 0.2% a day for every tag.
  - Prior: unmeasured. A reasoned estimate from the RF02 profiles: the defect
    `ρ|w| q Δφ` is about 1.1 × 2.8e-3 m/s × 5e-3 to 9e-3, so 1 to 2 kg m⁻² a
    day, against a `strat` inventory of about 3.4 kg m⁻². DYCOMS subsides with
    `w = −3.75e-6 z`. The default-against-copies agreement (W24: 0.25%, 0.41%,
    0.41%) cannot see it, since both share the bracket.

**PT3. The leak's attribution matters after feedback.** W40's first-order part
3 (`tropo` L1 2.4%, L∞ 6.2%) survives in the realized full-run difference to
within a factor of two.

  - If false: the realized difference is much smaller. Feedback then flushes
    the relabelling, and first-order estimates overstate `L` across the record.
  - Prior: W40; W45, whose V1 run keeps parity on 37 fields.

**PT4. The follower's work is mostly lag.** On a monotone solver ladder the
part moved because of `vdiff` falls by at most 0.75 per doubling and reaches at
most 0.25 of the default at four Newton and eight linear iterations.

  - If false: a doubling leaves more than 0.9 of it (structural), and the
    linearisation, Jacobian and post-solve parts carry at least half. Its
    donor-share assignment is then a convention to bracket.
  - Prior: W41 (the tags' Newton error 0.20 for `evap` against the parent's
    1.2e-2 at one iteration); W45 (part 2a rose from 2.92% to 3.09%); W38's R10.

**PT5. The tag propagator is L1 non-expansive but not positive on the centred
rungs.**

  - If true: the spike arms give `sup K ≤ 1 + ε`; the positivity index is above
    zero where the centred exchange or the truncated solve acts; the response
    is linear to `ε`.
  - If false: `K > 1` somewhere. `U` is then multiplied by `sup K`, and the
    operator is located. Or positivity holds, which opens the L∞ route.
  - Prior: none measured. W38's R8 shows no repair after startup on the centred
    rungs.

**PT6. The follower's placement does not matter for water composition on
D4-W.**

  - If true: the per-tag difference between W24 (`|m|`) and W28 (same sign) at
    24 h is at most 0.5% L1 and 1.25% L∞.
  - If false: it is larger. The triangle inequality through the copies already
    caps it near 0.50%, 0.82% and 0.83%.
  - Prior: W28. The moved flux changes with the placement and carries donor
    shares (`tagged_water_increment.jl`).

**PT7. Rules that are not homogeneous act only at logged events.**
Proportionality holds to 1e-10 except at logged bound or fix events.
Aggregation over a band partition departs only where θ binds or the repair
acts, and by no more than their exposure.

  - If false: departures occur where nothing is logged.
  - Prior: decision 5 of G3_PLAN; W40 (`evap`, `evap_tropo` and `evap_strat`
    identical to four digits); W21 (the bound active on up to 27% of the pulse's
    levels).

**PT8. The ledgers are incomplete.** Each family has at least one channel that
sets labels with no per-tag account. Water: option C's entry and W42's
unrecorded rises. Energy: `C4`'s per-tag outflow.

  - If false: probe accounting closes per tag to rounding in every window.
  - Prior: W42 (4 of the 10 largest rises unrecorded); E87 (A5 fails).

**PT9. The transport bundle is faithful in a clean regime.** On Soares (no
subsidence, no sinks) the nearly source-free upper tag equals the
water-weighted passive tracer within its floor plus the budget, in both modes.

  - If false: there is a fidelity defect in the shared machinery that no
    convention explains.
  - Prior: E68 and W17 were confounded (a tracer of air, the mask gain, rain).

**PT10. The copies' ineligibility on D4-W is a per-step effect (the filter or an
edge), not lag.**

  - If true: `led_upfilter`'s gross exceeds `led_uprepair`'s, concentrates at
    cloud top, and grows by at least 1.5 times per halving of `dt`.
  - If false: the repair dominates and falls with iterations. Even then no
    route exists at production cost: four Newton iterations give 0.28% a day
    (W25) and ten give 0.27% (W21).

**PT11. The energy repair's realized per-tag effect exceeds the budget for
`sub` and `new_strat`.**

  - If true: the realized difference with the repair on and off, on the full
    8-tag set, exceeds 2% L1 at 24 h.
  - If false: it stays within 2%, and propagation flushes the 7.3%-a-day trade.
  - Prior: E86 (retained `led_fix`: `sub` 3.1%, `new_strat` 2.2%; refinement
    0.91).

**PT12. WP4b's pool rule is faithful within the step.**

  - If true: the frozen-rate sub-step replay converges, and the
    process-weighted `|φ_pool − φ₆₄|` is at most 0.05 in the rain-out window.
  - If false: the pool rule is a material numerical rule.
  - Prior: W43; [design/RAIN_SNOW_TAGS.md](design/RAIN_SNOW_TAGS.md) section 9
    (the two-way part is 72% of the net at 97% relative humidity).

**PT13. The first-hour `evap` gap is a surface convention.** The three
admissible surface treatments (the plume starts at the grid mean; the copies'
relaxation; zero credit) spread by more than the first-hour source row of 10%.

  - If false: the spread is at most 10%, and the gap lies in the plume's
    dynamics, not in the surface rule.
  - Prior: W38's P3 (`evap` 11.7%, not first-step lag); W18 (the surface excess
    is about 3% of `q_tot`).

**PT14. A label error flushes at the column's loss rate.** A zero-sum label
error decays at the column's total donor-proportional loss rate: precipitation
plus large-scale drying plus nudging.

  - If false: `K` stays above 0.8 at day 90, or grows.
  - Prior: energy, E60 and E74. Unmeasured for water.

## 7. Experiments

Status marks:

  - **[R]** re-scores output that exists, with no new run. Some of it is on
    Levante scratch only, so PX0 comes first.
  - **[K]** runs on existing keys, with a probe script, a config or a driver
    only. The owner submits it.
  - **[P]** needs a named diagnostic-only probe PR (section 8): a draft, off by
    default, the parent bit for bit, validated against an untagged twin.

Every experiment names its run tree. The current code lacks #109's per-tag
ledgers and the leak-correction key on `main`, so any comparison with an
existing run uses that run's tree as recorded in [RUNS.md](RUNS.md). Every
decision rule is committed in a dated design note before any file it judges is
opened.

**Considered and dropped while this page was designed**, so that nobody
derives them again:

  - W40's part 3 against part 2b as a test of the lemma: part 3 is a net
    first-order sum, so the ratios test nothing. PX2 gives the realized value.
  - Placement pairs at sites 23 and 26 and on TRMM 0M: the placed quantity is at
    rounding there (W36, E81, W28), so their outcome is fixed in advance. PX3
    uses W24 against W28 instead.
  - A donor-cell replay as the linear truth: E66 shows that it measures the
    mixing convention. It stays only as a conditional bracket member (PR-D).
  - The passive tracer as the surface truth: it has its own surface convention.
    It is used only with a level-1 check (PX13).
  - Split duplicate tags with the same footprint: they stay proportional, so
    they test homogeneity only. The column test `evap_upper + evap_lower = evap`
    has the same weakness, since both sub-tags are fed in the lowest cell. A
    band partition (PR-P4) is needed for superposition.
  - First-order tracer twins on 1M columns: `tracer_upwinding` also moves the
    1M species, so the parent changes. Tracer-mode twins run only on 0M cases,
    with parity checked.
  - Copies at four Newton iterations on D4-W: `w4_d4w_copies_n4` already failed
    at 0.28% a day.

### Tier 0: re-score, no run [R]

**PX0. Archive first.** No score. Archive and checksum the NetCDF and CSVs of
W24, W28, W38 to W45, E85 and `g46` from scratch; RUNS.md's backfill says
W38 to W45 are not yet synced. Feed every new script faults before any score is
read: a removed variable, a shifted time, a truncated run, a flipped signed
zero, a permuted tag name. Each must fail closed. Hours. Priority 1.

**PX1. Subsidence screen.** Tests PT2.

  - Data: the hourly profiles of W38's `w25i_d4w_default_z30_c` and `_z60_c`,
    with DYCOMS's `w = −3.75e-6 z`.
  - Method: per tag, the exact rate `R_ex,i`, which is first-order upwind
    `subsidence!` of `χ_i`. The bracket's rate
    `R_br,i = M_i max(Δ, 0) + φ_i min(Δ, 0)` with `Δ = Σ R_ex`. The gross
    exposure `∫∫ abs(R_ex − R_br)`, the sign coherence `s`, and a map by level.
  - Reference: the parent's own linear operator, which does not share the
    bracket. The copies and the unsubsided tracer are invalid here.
  - Rule: a screening estimate, reported and not scored. If `strat` or `tropo`
    reaches 0.2% of its inventory a day, PX8 follows and PX16 becomes the
    critical path.
  - Code: none. Hours. Priority 1, the first item.

**PX2. The leak rule, realized with feedback.** Tests PT3 and PT1; evidence for
OD12's same-parent amendment.

  - Runs: `wp4c_gate_d4w_default` (gate tree `52a666c5`) against
    `wp4c_corr_d4w_default` (tree `90f32566`). Both are bit for bit with W25's
    untagged `z30_c` twin. Confirm in the manifests that no other tag code
    differs. For the copies: `wp4c_gate_d4w_copies` against V2 (12 h).
  - Metric: per-tag L1 and L∞ at 1, 6, 12 and 24 h in the established window,
    against the gate's first-order part 3 at the same times, with the map by
    level from the gate's profiles.
  - Reference: the other closing rule (ψ against the follower's donor shares).
    It shares everything else, so it gives `L`, not truth.
  - Rules: (a) realized over first-order at 1 h within [0.8, 1.25] means that
    separate runs with bit-identical parents behave as same-state pairs for a
    swap of follower rules; (b) if OD11 lists ψ as admissible and the realized
    `tropo` exceeds 2% L1 or 5% L∞, `tropo` on D4-W is convention-limited for
    the leak; (c) realized over first-order at 24 h calibrates every
    first-order estimate on the record.
  - Code: none. Hours. Priority 1.

**PX3. The placement pair.** Tests PT6 and the water side of OD7.

  - Runs: W24 (`|m|`) against W28 (same sign, #102 at `5bfa7cea`): D4-W, 24 h,
    one Newton iteration, 37 fields bit for bit (W28).
  - Metric: per-tag L1 and L∞, hourly. The prior cap is near 0.50%, 0.82% and
    0.83%.
  - Rule: at most 0.5% L1 and 1.25% L∞ means placement does not matter for
    water composition, so OD7 can be decided on closure and slope. Above that,
    OD7 carries a provenance spread.
  - Code: none. Hours. Priority 1.

**PX4. Invariants on existing output.** Tests PT7 (Fid-1, in part).

  - Runs: the 12 W25i runs, W38, W40.
  - Metrics: `r = ρq_evap_tropo / (m_t ρq_evap) − 1`, the same for `strat`,
    and `evap_tropo + evap_strat − evap`, each classified against the logged
    bound and fix events. Overlay at most parent, per cell. The audit's
    `overclaimed` and `orphaned`. Source at most production, from hourly
    estimates (only violations beyond the estimate's error count).
  - Rule: `abs(r)` at most 1e-10 except at logged events. A departure with no
    logged event stops the tier: locate the rule before any Fid-1 claim.
  - Code: none. Hours. Priority 1.

**PX5. Why the copies are ineligible on D4-W.** Tests PT10.

  - Data: the copies' ledgers of W25 and W38 (the filter's gross against the
    repair's gross, by level and hour, at `dt` 120, 60 and 30 s); W21 at one
    and ten iterations; `w4_d4w_copies_n4`; site 26's copies from the committed
    CSVs.
  - Rules: a filter share of at least 0.7 that grows by at least 1.5 times per
    halving means a per-step cause. The only D4-W routes are then a copies-only
    draft PR, or the air twin with PR-S (PX17). Otherwise record "no eligible
    D4-like comparator at production cost". Site 26's copies are formally
    ineligible (repair about 0.33% a day, own closure 6.3e-4), so W36's 2% to
    13% is agreement with an ineligible comparator.
  - Code: none. Priority 1.

**PX6. The missing-channel inventory.** Tests PT8 and PT1.

  - For every rule of section 4, list the per-tag account that exists and in
    which tree. This fixes the scope of the probe accounting.
  - Read the option C miss probe (job `13987196`) when it lands. Any rise with
    no operator share of at least 0.5 blocks Fid-2 at site 23.
  - Tabulate the closure change against the per-tag difference for every
    same-parent pair of closing rules (PT1).
  - Code: none. Priority 1.

### Tier 1: existing keys [K]

**PX7. The follower's work: lag or structure (W46, pending).** Tests PT4.

  - Tool: `analysis/water/wp4c_diag_probe.jl` on `wp4c_corr_d4w_default`, from
    6600 s, with the solver sets default, `lin4`, `lin8`, `newton2lin2`,
    `newton4lin8` and `newton10lin10`. A second set turns `sgs_mass_flux` off in
    trial C (a script switch). Run `wp4c_upleak_check.py` on V2.
  - Pre-register the rule as a dated amendment to
    [design/WP4C_CORRECTIONS.md](design/WP4C_CORRECTIONS.md) section 8 before
    the result is read. Read it by monotone ratios, not by the distance to the
    unconverged ten-iteration set (W41).
  - Rules: *lag* if `newton4lin8` is at most 0.25 and each doubling at most
    0.75. That part then enters `F`, and V1's criterion 1 is scored again at the
    converged set. *Structural* if any doubling leaves more than 0.9. Its parts
    are then read with the share rule of at least 0.5 or 0.1 to 0.5: the
    linearisation, Jacobian and post-solve parts become a convention to
    bracket (PR-D); `filt_T − filt_q` points at the tags' Jacobian coverage
    (PR-E).
  - This answers WP4c's default. One or two jobs of one to two hours.
    Priority 1.

**PX8. The same-state subsidence probe.** Tests PT2 and gives its `U` term.

  - Tool: a new script, `analysis/water/sub_probe.jl`, on the pattern of
    `wp4c_gate_probe.jl`. From each accepted step's state it evaluates
    `subsidence!` on `ρq_tot`, the exact `T_i` per tag and the bracket's `B_i`.
    It asserts `Σ T_i = Σ B_i = Δ`, so closure is blind by construction. It
    accumulates the gross `G_i = Σ_k dt ∫ abs(T_i − B_i)`, the net `D_i` and
    `s_i`.
  - Cases: `w25i_d4w_default_z30_c` (as W40) and `_z60_c`, 24 h, in their own
    trees. A GCM arm: site 23, which subsides, days 1 to 3 and then 1 to 9, with
    `ic_miss_probe.jl`'s explicit per-term probes for the large-scale
    subsidence. Record the operator's L1 column sums there, since the advective
    form can expand where `abs(w)` falls with height.
  - Rules: `U_sub,i = K · G_i`. `G_i` at most 0.2% of every inventory a day is a
    certificate that subsidence is immaterial for that case. Above the per-tag
    row, PX16 follows, and every D4-W default-against-copies number gets a dated
    annotation: "shared subsidence rule: its exact-form exposure measured, not in the comparison".
  - Code: none; the script calls the model's operator on scratch copies. Two
    D4-W jobs and a short GCM probe. Priority 1.

**PX9. The propagation probe.** Tests PT5 and gives `K` and the L∞ premise.

  - Tool: `analysis/water/perturb_probe.jl`, on `w25_probes.jl`'s pattern
    (`take_state!` and trial integrators; the parent checked bit for bit in
    every trial).
  - Case: `w25i_d4w_default_z30_c`, then `z60_c`. Inject after the case's OD2
    startup, at three times: after startup, 6 h later and 12 h later. Step 18 h.
  - Arms: zero-sum unit spikes (`+δ` in `tropo`, `−δ` in `strat`) at every level
    at the first time, and at sampled levels at the later times (every level
    within 150 m of 750 m and 795 m, every second level elsewhere). Scaling
    arms (`−δ`, `2δ`) on a subset. A null arm, which with the scaling arms sets
    `ε` from rounding.
  - Metrics: the column sums `‖e‖₁ / ‖δ‖₁` (so `sup K`), the positivity index
    `‖e_tropo⁻‖₁ / ‖e_tropo⁺‖₁`, and linearity.
  - Rules: `sup K ≤ 1 + ε` sets `K = 1` in `U`; sampled levels give only a lower
    bound, so the full-level time decides. `K > 1` multiplies `U` by the
    measured `sup K`, and on/off trials locate the operator. A positivity index
    above zero closes the L∞ route for the case. Stated before the run: `K ≤ 1`,
    positivity index above zero.
  - Code: none. Three to six jobs. Priority 1.

**PX10. The energy repair on the full tag set.** Tests PT11.

  - Case: `g411x_d4_default` with `energy_source_tag_repair` true and false,
    `e_src_fixgross_*` added to the output (config only), 24 h, parity against
    the untagged twin. E85's pair has 4 tags and no gross, so it is prior
    evidence for `strat` and `tropo` only.
  - Metrics: the per-tag realized difference at 1, 6 and 24 h in OD4's units;
    `fixgross` as the repair's `U` term (factor 2); where it acts relative to
    750 m.
  - Rule: `sub` or `new_strat` above 2% L1 means the repair is material for
    energy, and Val-2 is out of reach until the exchange changes. Otherwise the
    7.3%-a-day trade is immaterial by the realized difference. This answers
    point 2 of G4.3 to G4.6.
  - Code: none. Two D4 jobs. Priority 2.

**PX11. The Soares air twin.** Tests PT9: the first Val-3 route for the
transport bundle.

  - Case: `prognostic_edmfx_soares_column.yml` (1M, 75 levels, `dt` 5 s, 8 h;
    no subsidence in `Soares.jl`) with water tags `low` and `up`, split at the
    untagged run's boundary-layer top at 2 h (fixed before the scored runs),
    plus `evap`. `chemistry_model` passive. The driver sets
    `q_gas_A = M_up · q_tot` and its updraft copy `M_up · q_totʲ`, as
    `d4w_driver.jl` does. Arms: untagged, default, copies, with parity.
  - Validity, checked on the untagged run first: no sedimenting condensate
    (`∫pr` below 1e-4 of the water); the water tags build on the login node.
  - Floors: the `up` tag's mask-gain bound `M_up(z₁) ∫evspsbl / ∫ρq_up`; a
    linearity twin with `q_gas_A = M_low · q_tot`, whose sum is checked against
    `ρq_tot` above the boundary layer and as column integrals against the
    cumulative `evspsbl`; the parent's Newton error at this iteration count
    (one W25 P1 probe).
  - Score only the `up` tag, which avoids the tracer's surface convention.
  - Reference: EDMF's passive-tracer equations. They share no tag rule: no mask
    gain, loss rule, follower, plume, exchange, repair or clamp.
  - Rules: L1 of `up` at most 1% at 1 h and 2% at 8 h, and L∞ at most 5%, above
    the floors. Both modes pass: the transport bundle is Val-3 in a regime
    without sinks or subsidence. The copies pass and the default fails: the
    plume or the exchange is isolated. Both fail alike: the follower or the
    grid-scale rules. Floors above a quarter of the budget: not assessable.
  - Code: none. About six short runs; copies compile in 28 to 41 min.
    Priority 2.

**PX12. TRMM 0M comparator eligibility on current code.** A Val-3 route for
the sub-grid rules. W21's TRMM runs predate WP6 and the current copies, so new
runs are needed: default, copies and untagged; `dt` 150 and 75 s; two and ten
Newton iterations; one P1 probe for the parent's error. OD12 fixes which
"own residual" counts: the updraft copies' 7.1e-7 (W21) or the grid mean's
5.0e-4 (W28). It needs OD12's same-parent amendment, or a measured parent error
of at most 1e-3. If the copies are eligible, `pbl`, `free` and `evap` are
scored in OD2's windows. That certifies the SGS share, the exchange and the 0M
rain-out, for the code tested. Priority 2.

**PX13. The surface-excess bracket.** Tests PT13 and answers W21's surface
rule.

  - Case: `w25i_d4w_pulse_{default,copies}_z60_c` and `_z30_c`, 3 h, output
    every 10 min, with the level-1 updraft fields. A driver sets
    `q_gas_A = ρq_tot` and its updraft copy `q_totʲ`, with its own untagged
    twin.
  - The candidate `evap* = ρq_tot − T1` counts only if (a) at level 1,
    `abs(T1ʲ − T̄1)` is at most a quarter of the budget relative to the `evap`
    share, and (b) the contamination from the tracer's missing subsidence and
    from rain over the lowest 300 m in the first hour is at most a quarter of
    the budget (a floor near 4e-4 of `q_tot`).
  - Score `evap` only. The `sfc` tag, 10 m wide against 25 m cells, is
    ill-conditioned.
  - `L` is the spread among the grid-mean start, the relaxation and zero credit.
  - Rule: `L` above 10% means first-hour `evap` is convention-limited (Val-1),
    and the claim is narrowed. PR-B goes to the owner only if (a) and (b) pass
    and it lies nearer `evap*`.
  - Code: none. About twelve short jobs. Priority 2.

**PX14. WP4b's pool and the sedimentation reset, replayed.** Tests PT12. After
#121's review.

  - Case: #121's tree, `PrecipitatingColumn`'s rain-out window only (the first
    25 to 60 min, read from the untagged run), the key on.
  - Method: from each state take `water_tag_1m_flows` as frozen rates. Solve
    each tag's three-compartment label equation with 1, 4, 16 and 64 sub-steps;
    one sub-step reproduces W43's failing start rule. Apply the pool rule. In
    the same harness, apply the per-level reset without the key against the
    key's rain parts. That isolates the reset without the pool as a confound.
  - Rules: a process-weighted `|φ_pool − φ₆₄|` of at most 0.05 and rain-part L1
    of at most 2% make the pool Fid-3. Otherwise the owner decides with the
    measured spread. A reset error above G3_PLAN 6.1's 10% precipitation budget
    means WP4b's stage 2 (EDMF) comes before any precipitation claim in the
    production envelope.
  - Code: none. Under an hour per case. Priority 2.

**PX15. The energy follower's split.** After PX7. Port `wp4c_diag_probe.jl` to
`enthalpy_increment` on `g411x_d4_default`, with PX7's ladder and rule. This
frames OD7 and G4.7. Priority 2.

### Tier 2: probe PRs [P]

These need OD13. Each is a separate draft PR with a unit test and a parity job.

**PX16 (PR-A). Per-tag subsidence.** Tests PT2 and the lemma against an exact
counterpart. D4-W `z30_c` default plus the untagged twin, 24 h. Metric: the
realized per-tag difference with feedback, against `K · G` from PX8 and PX9.
Rules: a difference above `K · G` means the inventory or `K` is wrong, and `U`
is void for the case; above 2% L1 or 5% L∞ means the default fails the
provenance row on D4-W whatever any comparator says. Adoption is the owner's
call. Priority 1 if PX1 or PX8 is material, otherwise 3.

**PX17 (PR-S). A subsided passive tracer.** It makes the air twin valid on
D4-W, RICO, BOMEX and the GCM columns, and checks PR-A independently. On D4-W
score the `up` or `strat` tag, with a contamination bound for rain formed at
cloud top in the `strat` region, where the tracer loses no water. Priority 2.

**PX18 (PR-P4). A band region.** Tests PT7 and OD9's aggregation premise. D4-W
`z30_c` with a fine partition (below 400 m, 400 to 750 m, above 750 m) and a
coarse one (`tropo`, `strat`), a run with the tags in reverse order, and the
three-tag hull test (V8), plus the untagged twin. Metric: the relative L∞ of
the members' sum minus the group at 24 h, against OD3's 1e-10, mapped against
bound activation and the repair's gross. Rule: departures only where θ binds or
the repair acts, and within `K` times their exposure, support PT7. The owner
then chooses the form of the aggregation row. Priority 2.

### Tier 3: long run, sphere, certification

**PX19. The flush rate.** Tests PT14; before step 9's 90-day run. Rerun
`lr_s26_samesign` to day 10, saving the state. Edit the restart in Julia with
`d4w_driver.jl`'s pattern: move 1e-3 of the water from `pbl` to `free` between
500 and 900 m, changing only `Y.c.ρq_tag_*`. Restart the edited and unedited
states to day 90 with `reproducible_restart`, and compare the edited run with
the unedited one only (E54, E58). The loss rate is precipitation plus
large-scale drying plus nudging, from the `:external_forcing` records, over
`∫ρq_tot`. Rule: the label error's decay rate within 30% of the loss rate means
the long-run `U` saturates at the exposure rate divided by the loss rate.
Priority 3.

**PX20. The sphere census.** Inside step 9's one-to-two-day run, with no extra
run. The invariants and the exposure census on the sphere: the rescale,
borrowing, the hyperdiffusion leaks, the sedimentation reset, and WR20. Van Leer
per field and the follower's label diffusion can only be decided here. Any rule
above materiality gets its bracket before the 90-day run. Priority 2.

**PX21. The certification tables.** A script,
`analysis/evidence/provenance_verdict.py`, extending `closure_verdict.py`. For
each case, tag and window it gives the fidelity level, `[L, U]`, the verdict per
rule and the rules left uncovered. Before step 8b. Priority 2.

## 8. Probe PRs

Each is diagnostic only: off by default, the parent bit for bit, a unit test, a
parity job against an untagged twin, and a draft PR that only the owner merges.
OD13 approves them.

  - **PR-A, per-tag subsidence.** A key `water_tag_subsidence: bracket | per_tag`
    for `LargeScaleSubsidence` and the GCM forcing's subsidence. It must define
    two overlay cases: overlays that list subsidence (then `fcg` changes
    meaning) and overlays that do not (then `evap` is carried faithfully instead
    of losing by share).
  - **PR-S, a subsided passive tracer.** A key that applies `subsidence!` to
    `q_gas_A` as well. The tracer feeds back into nothing, so every other field
    stays bit for bit.
  - **PR-P4, a band region.** A region type `tanh_altitude_band`, in the parser
    only. Today's types are `everywhere`, `tanh_altitude`, `tanh_latitude`,
    `tanh_box` and `tanh_polygon`.
  - **Conditional:** PR-B, a surface rule that composes the flux, after PX13;
    PR-D, face-flux output for a replay, after PX7's structural branch, and
    labelled a convention reference (E66), never truth; PR-E, tag Jacobian
    blocks for the bracket loss and the SGS flux, after PX7's filter branch;
    PR-P2, sources off for region tags, only if a regime with sinks needs a
    region reference (Soares does not).
  - State ledgers per process and tag are not proposed. Probe accounting
    replaces them, because build time grows with the number of fields.

## 9. Decisions for the owner

These enter the register in [ROADMAP.md](ROADMAP.md) as "OWNER DECISION
REQUIRED". No agent fills one in. The panel that designed this page proposed
eight; they are merged into six to spare the owner's time.

  - **OD9. The ladder and its labels.** Adopt the two axes; "bounded" means
    Fid-3 and `U` within the row; "validated" means Val-3. Decide whether
    "bracketed" ever qualifies at M5. Decide the aggregation row's form: a Fid-1
    premise run with PR-P4, accepting departures where θ or the repair acts;
    or "departure at most `K` times the nonlinear rules' exposure"; or
    "reported" as now. Needed before any ladder label and before step 8b.
  - **OD10. The certification arithmetic.** The lemma of section 3: gross, not
    net; the exact form for bracketed transport; `K` from spike arms, with `ε` from null and
    scaling arms; the L∞ route only under positivity; completeness to rounding
    for the probe accounting. The proposed numbers are in a separate marked
    block after the OD3 table. Needed before PX8, PX9 and PX16 are scored.
  - **OD11. The rule classification.** The claim contracts (G3 criterion 12,
    G4.3) adopt section 4's classes before any `L` or `U` is scored, and they
    list the admissible alternatives, including whether ψ is admissible for the
    leak. The owner also confirms the E66 reading: the 2% is a fidelity budget.
    Needed before PX2's rule (b), PX3, PX10 and PX13.
  - **OD12. Reference validity and independence.** Copies certify sub-grid
    rules only. The air twin certifies transport rules only in windows without
    sinks, subsidence or sedimentation (subsidence allowed with PR-S). Floors
    at most a quarter of the budget; the level-1 check; which "own residual"
    counts for TRMM 0M's copies. And an amendment to the Newton row, as a
    proposal: separate runs whose parents are bit for bit equal to the same
    untagged twin count as same-parent for swaps of follower rules, if PX2 (a)
    passes; arms that solve their own transport (the copies, tracer mode, a
    passive tracer) stay gated unless the parent's error is at most 1e-3.
    Needed before PX11 to PX13.
  - **OD13. The probe PRs.** PR-A, PR-S and PR-P4 first; PR-B, PR-D, PR-E and
    PR-P2 conditional; probe accounting instead of new state ledgers. Needed
    before tier 2.
  - **OD14. Held-out hygiene.** Name the GCM site or window kept back. Soares,
    TRMM 0M and sites 23 and 26 are development cases. A held-out case is never
    used to develop a rule. Needed before step 8b.

## 10. Sequencing, and what G4 takes

Order inside each gate: exposure times the decision it blocks (subsidence, the
follower, the energy repair, the surface, placement), then cost, with no-run
items first.

 1. **Gate 0, step 1b: documents and archive.** This page, the in-place edits,
    OD9 to OD14, PX0. No runs, no code. Scripts pass fault injection first.
 2. **Gate A, step 2a: no runs.** PX1 first. If `strat` or `tropo` reaches 0.2%
    of its inventory a day, subsidence becomes the critical path: PX8, then
    PR-A, then PX16. Then PX2, PX3, PX4, PX5 and PX6. They are reported until
    OD9 to OD11 are approved. Stop if proportionality departs with no logged
    event, or if a realized difference exceeds `K` times its gross once `K` is
    known. PX3 may let the owner decide OD7.
 3. **Gate B: existing keys.** PX7 (step 6a) decides whether the follower's
    work is lag, which the bounded route needs. PX8 and PX9 (step 6b) give the
    subsidence term and `K`; if `K > 1`, locate the operator before any `U` is
    scored. PX11, PX12 and PX13 (step 6c) give the first Val-3 candidates and
    the surface verdict. PX14 (step 7a) after #121's review.
 4. **Gate C, step 7b: probe PRs, after OD13.** PR-A with PX16, PR-P4 with PX18,
    PR-S with PX17. The conditional PRs only if their trigger reads above
    budget.
 5. **Gate D, step 8c: certification.** PX21 labels every case, tag and window.
    Step 8b then selects a default only at the level OD9 requires.
 6. **Step 9.** PX20 inside the one-to-two-day sphere run; PX19 before the 90
    days.
 7. **Step 10.** PX10 (step 10a) and PX15 (step 10b), then G4.15 and G4.7.

**Expected outcomes, stated before any run.**

  - D4-W reaches Fid-1 and Fid-2 soon, and Fid-3 after PX7 and PX9.
  - `U` probably fails for `tropo` and `strat` on D4-W: the follower's worst-case exposure is
    about 7.2% over 0.924 days, and subsidence may add tens of percent a day.
    So OD5's bounded route is likely closed on D4-W until PR-A exists and PX7
    shows the follower's work to be mostly lag.
  - Soares, and TRMM 0M before its rain-out, are the first Val-3 candidates.
  - Energy on D4 tops out at Val-2: it has no passive truth, and its copies are
    ineligible (E84).

**What G4 takes from G3.**

  - The ladder, OD9 to OD14, and the rule classes.
  - PX7's split method, ported as PX15.
  - PX9's propagation method, ported to `enthalpy_increment` on
    `g411x_d4_default` before Val-2 is claimed.
  - PX8's subsidence size at the same 750 m split of DYCOMS RF02. It sizes the
    `sub` tag and the region tags. Energy has no faithful counterpart for it,
    so it stays a convention there.
  - PX13's surface verdict, for G4.11 and M2.
  - PX3, for the water side of OD7.
  - PX11's certificate, only for the kernels the two families truly share.
    Check `ShareDifferences`, `_blend_factor`, `_plume_step` and the
    follower's left-out weight in the code before inheriting it.
  - PX18's aggregation reading.

Energy's own items are PX10, the `c`/2`c` bracket and a per-tag outflow probe
for `C4`. The committed process budget carries the records' estimate of `C4`
(`output/g46/process_budget.txt`), but only a per-tag bottom-face outflow probe
tells where it goes (Fid-2, priority 3).

## 11. Risks and open questions

  - **`U` may never pass on D4-W.** The follower's worst-case exposure for `tropo` is about 7.2%,
    and subsidence may be tens of percent a day. Certainty would then come only
    from turning rules into faithful ones (PR-A, WP4b under EDMF, tags solved
    consistently with the parent's Newton step), or from Val-3 in clean
    regimes. The owner should know this before the runs.
  - **A faithful rule helps only if its operator is monotone.** Centred
    reconstructions per tag can raise `K`. Advective subsidence can expand on
    GCM columns.
  - **Is ψ admissible for the leak?** If yes, W40 already suggests that `tropo`
    is convention-limited on D4-W, unless PX2 shows that feedback flushes it
    (OD11).
  - **First-order estimates against realized runs.** Adopting a rule always
    needs a prognostic arm (PX2, PX16). PX2's calibration is the only test so
    far of the same-state equivalence that OD12's amendment would rest on.
  - **References carry their own conventions.** The passive tracer's zero
    surface credit and missing subsidence (PR-S fixes the second), the floors,
    and cloud-top rain in D4-W's `strat` region. Each needs its certificate, or
    agreement will be over-read again.
  - **Run trees.** The per-tag ledgers, the leak-correction key, the placement
    variants and option C sit in separate trees. Every comparison names its
    tree.
  - **`PrecipitatingColumn` is a short spin-down, and WP4b is refused under
    EDMF.** WP4b's fidelity is measured only in the rain-out window until its
    stage 2.
  - **Classification gaming.** OD11 is fixed before any `L` or `U` is scored,
    and does not change after a run.
  - **Aggregation departs by construction where θ or the repair acts.** OD9
    chooses the row's form. No agent redefines it.
  - **The L∞ rows** (5% and 25%) have no route without a comparator unless PX9
    finds positivity.
  - **Data durability.** Every tier-0 item depends on scratch until PX0 is done.
  - **The owner's bandwidth.** Six new decisions, OD7, and up to seven PRs.
    OD9 to OD12 are needed before gate B is scored; OD13 and OD14 before gate C
    and step 8b.
  - **Multiple testing.** Only pre-registered decision rules count. Everything
    else is reported.
  - **Two meanings of provenance.** "Tag provenance" is this page's subject.
    "Run provenance" is `provenance.txt` and M0. Say which.

## 12. Edits made elsewhere

Each is in place and marked "*Scope added (provenance pathway, 2026-09-26)*".
Nothing the owner approved is struck.

  - [ROADMAP.md](ROADMAP.md): a fourth aim; M2, M3 and M5 annotations; notes on
    the Provenance, Comparator-eligibility, Convergence and Aggregation rows;
    six proposed rows and four rules under the contract; OD9 to OD14 in the
    register, with notes on OD5 and OD7; a block of proposed numbers after the
    OD3 table, with the E66 note on the approved 24 h row; new steps 1b, 2a, 6a
    to 6c, 7a, 7b, 8c, 10a and 10b, and notes on steps 4, 6, 8b, 9 and 10 and on
    the milestone table's sphere row.
  - [G3_PLAN.md](G3_PLAN.md): a pointer in the header; §2 (criteria 5, 7, 8 and
    12 on the ladder); §3 (subsidence is not "Followed"); §4.1, §4.2, §4.3 and
    §4.5; §6 (D4-W subsides; the rows V-P0 to V-P3); §6.1 (the E66 note); §8;
    §9.
  - [G3_TODO.md](G3_TODO.md): OD9 to OD14 under Decisions; a new section
    "Provenance pathway" with PX0 to PX21 and the probe PRs; pointers in WP3,
    WP4c, WP5b-P, WP5b-C, WP4b, WP9 and the sphere.
  - [G4_TODO.md](G4_TODO.md): the pathway note; G4.1, G4.3, G4.6, G4.7 to
    G4.10, G4.12 and G4.15; a new item for energy subsidence.
  - [STATUS.md](STATUS.md) and [DECISIONS.md](DECISIONS.md): pointers only.
  - FINDINGS.md is not edited: no result exists yet.
