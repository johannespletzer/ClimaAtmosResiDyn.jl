# The provenance pathway

Proposed on 2026-09-26, pending the owner's decisions OD9 to OD14. Revised the
same day after the owner's review (section 0). It is written on
`claude/tag-provenance-certainty-zwkx73`, from `claude/plan-rev2` at
`a6949414`. That branch held the newest results: it was 78 commits ahead of
`claude/tag-closure-record`, and no other branch held a record commit that it
lacked. Nothing here has been run. Every measured number quoted is a finding
already on the record, unless it says otherwise. PT2's estimate is reasoned
from the RF02 profiles and is labelled so. Values read before this page was
written count as prior evidence only, never as a scored test. Every outcome
stated on this page is a hypothesis until a run tests it.

**Why this page exists.** The owner wrote on 2026-09-25 that the provenance of
the tags is much harder to reach than closure. Closure now holds within its
0.2% budget in almost every run (D4-W 7.2e-6 to 3.0e-5 at 24 h, W38), and to
rounding in some (TRMM 0M, W28; site 26, W36). No provenance verdict has passed
under rev. 2's contract. W32's same-state check on TRMM 0M comes closest. Rev. 2
of the work plan ([ROADMAP.md](ROADMAP.md)) already says that closure cannot
stand in for provenance. It blocks false positives, but it gives no route to
positive evidence. This page proposes that route. It adds; it strikes nothing
that the owner approved. The in-place edits it makes elsewhere are listed in
section 12.

## 0. The owner's review, and what it changed

The owner reviewed the first version at `91e85ad` on 2026-09-26 (PR #122). The
central direction stands: closure does not identify tag composition, and a
reference cannot validate an attribution rule it shares. The review asked for
five changes before OD9 to OD14 are accepted. Each is made here and in the
edits of section 12.

 1. **No error interval.** The first version gave each tag an interval
    `[L, U]` on its provenance error. `L` was the spread between two
    admissible rules. That is not a lower bound on the error: if the selected
    rule is right, its error is zero whatever the spread. `U` used a
    propagation factor that PX9 would sample. A sampled factor can be below
    the worst-case amplification, most of all across nonlinear repairs, clamps
    and solver states. So `U` was not a certified upper bound. The two are now
    the *observed spread* and the *exposure screen* (section 1). Neither is an
    error interval or a certificate.
 2. **Water's reference is conditional.** It exists only under a declared
    labelling model. A frozen-parent label calculation tests the declared
    equation. It does not establish unique molecular provenance in unresolved
    sub-grid physics (section 1).
 3. **"Validated" is restricted.** It applies only to rules that were active in
    the case and were isolated by a reference that does not share them. The
    excluded processes must be measured inactive, and the reference's floors
    must pass. Every verdict lists its active, shared and untested rules
    (sections 2 and 5). Energy is tested conditionally, at a fixed offset `c`
    and source convention. The `c`/2`c` spread and `C4`'s unresolved outflow
    are limitations. They are not error bounds, and not proof that no test is
    possible.
 4. **E66, and the approved rows.** One written argument for the 2% row
    does not match E66, and E66's difference is not a pure convention
    effect. The argument is corrected, and the measured spread is reported
    apart (section 1). OD3's approved 2% criterion and OD5's meaning stay as
    decided. The materiality and per-rule numbers are exploratory, not
    thresholds (section 7.1; ROADMAP).
 5. **A smaller, gated plan.** Five gates: the archive; the subsidence screen
    and what follows it; the follower's lag or structure; one clean label
    benchmark, then one held-out case; and the energy checks at a fixed `c`.
    The other experiments and probe PRs wait until a measured result needs
    them (section 7).

**The owner's second review**, at `f360937` the same day, asked for three
more changes. They are made here.

 1. A low PX1 result cannot end gate B. Hourly output can miss a short-lived
    effect between outputs, so PX8's accepted-step probe always follows PX1
    (section 7.1).
 2. PX11 names individual rules only after PX24, a same-state per-tag
    process accounting that is complete in the case. Without it, PX11
    reports an aggregate comparison of the transport bundle.
 3. The E66 sentence in G3_PLAN 6.1 is replaced at the owner's request, and
    OD3's 2% criterion is kept. Section 3 no longer says that listing the
    nonlinear pieces makes the rest of the propagator linear.

The owner also stated that a site-23-derived case does not count as held out
for a rule developed using site 23. So Val-4 stays not assessable until an
independent case and its reference are fixed (PX23, OD14).

The reviews name four papers as background: Goessling and Reick (2013),
Kalverla et al. (2025), Fiorella et al. (2021) and Marquet (2015). They were
not read for this page. Where this page uses them, it repeats only what the
first review says of them.

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
  - W40: the remainder is 1.4e-7 of the water a day, while the first-order
    estimate of the difference between two closing rules (part 3, without
    feedback) is 2.4% L1 and 6.2% L∞ for `tropo`;
  - W45: the follower moves about 4.4% of the water a day while the partition
    closes to 8.4e-6;
  - E86 (with `review/od4_restatement.md` for `g411x_d4_default`): the energy
    tags close to 8.7e-6 of the throughput, while the repair trades 7.3% of it
    a day.

Worse, a correction that enforces closure turns a visible residual into an
invisible composition error. The leak that the follower absorbs in W40 is the
clearest case.

**Fidelity and conventional validity**
([design/ATTRIBUTION_PATH.md](design/ATTRIBUTION_PATH.md), sections 3.1 and
3.7). Provenance has two parts.

  - *Fidelity:* the code solves its own declared tag equation. This can be
    measured, by invariants, ledger completeness, convergence and known
    answers.
  - *Conventional validity:* the declared equation is the right physics. There
    are three kinds of rule here.
      + *Definitional* rules can only be declared: the offset `c`, the mask gain
        of region tags, donor-proportional loss, bracket granularity.
      + Rules with a *faithful counterpart* can be tested one by one against
        it. The counterpart is the parent's own linear operator applied to each
        tag: per-tag subsidence, the rain and snow parts, the sub-stepped
        flows, the passive-tracer equations.
      + *Conventions with admissible alternatives* can only be compared: the
        surface rule, the follower's placement, the leak's attribution, the
        pool rule.

**Water has a reference only under a declared labelling model.** A water tag is
a label on the model's water, like an isotope without fractionation. A
reference for it exists only once the labelling model is declared in full:

  - the source masks, which say what new water each tag receives;
  - the mixing volume, a cell or an EDMF subdomain, inside which composition is
    uniform;
  - the donor pools (vapour, cloud liquid, cloud ice, rain and snow), and which
    of them carry their own composition;
  - the phase transfers between pools, as gross flows;
  - the losses: precipitation, sedimentation out of a cell, and drying by
    forcing and nudging.

Under that model the labels solve a *linear* system driven by the parent's own
gross fluxes and rates. Equal net parent tendencies can hide opposing gross
transfers that still move labels. Rain can form and evaporate in the same cell
and step, and only the net shows.
[design/RAIN_SNOW_TAGS.md](design/RAIN_SNOW_TAGS.md), section 9, gives a state
at 97% relative humidity where rain forms at 1.34e-7 and evaporates at 5.6e-8,
so the two-way part is 72% of the net. A frozen-parent label
calculation, implemented independently from the gross flows, would test the
code against the declared equation. That is fidelity. It would not establish
unique molecular provenance in unresolved sub-grid physics, because there the
labelling model is itself a convention. The owner's review notes that Goessling
and Reick (2013) test the well-mixed assumption for vertically integrated
mixing. This code assumes mixing per cell or subdomain, so their result is a
caution here, not a direct falsification.

**Energy is tested at a fixed offset.** The energy tags depend on the offset
`c`. When `c` doubles, `strat` and `tropo` change by 177% and 152% in integral
(E71). So every energy test first fixes `c` and the source convention. The
record's runs use 110,495 J/kg, and the claim contracts
([design/G4_CLAIM_CONTRACTS.md](design/G4_CLAIM_CONTRACTS.md)) state the source
convention. A test at that fixed `c` is a conditional budget test. It holds for
that `c` and convention only. The `c`/2`c` spread and `C4`'s unresolved outflow
(E87) are reported with it as limitations. Offset sensitivity is neither an
error bound nor proof that no conditional test is possible. The review points
to Marquet (2015) on the choice of reference enthalpy.

**Every reference used so far is common-mode.** A reference cannot see an error
in a rule it shares.

  - The default and the copies share every grid-scale rule: mask gain, donor
    loss, subsidence through the bracket, the sedimentation reset and the
    partition repair. Subsidence is the sharpest case. It reaches the tags only
    through the local `:subsidence` bracket (`remaining_tendency.jl` lines 186
    to 188 on `main`), although `subsidence!` is first-order upwind and linear
    in χ. So the default-against-copies agreement tests only the plume and the
    exchange. The copies are also ineligible on D4-W and D4 (W21, W38, E84).
    On TRMM 0M their own residual and repair pass (W21, W32), but their full
    eligibility is not assessed (PX12).
  - The ten-iteration twins share the follower.
  - WP4c's part 3 compares two rules that both close.
  - The passive tracer has its own surface convention: it gets nothing at the
    updraft's surface boundary (`tagged_water_edmf.jl`, "a tracer gets
    nothing"). It is also not subsided. E68 and W17 are confounded by this and
    by the mask gain.

So evidence needs **coverage**: each rule with material exposure must meet a
reference that does not share it. Agreement among references that share a rule
is never evidence for that rule.

**One written argument for the 2% row does not match E66.** The row comes
from G1's criterion 4b. G3_PLAN 6.1 argued against a looser budget, which
would let the default's error exceed "the spread from the mixing convention
alone, about 1% in L1 (E66)". E66's L1 row is in fractions: 0.08 and 0.12 for
the region tags, 0.68 to 1.26 for the source tags. That is 8% to 126%, measured
for energy tags on D4. E66's reference also keeps 5.99e5 J/m² of its own
residual, and it fails closure on OD4's scale (E86). So E66's difference is not
a pure convention effect. It mixes the convention with the reference's own
error, and the argument did not hold. At the owner's request that sentence in
G3_PLAN 6.1 is replaced. The row itself stands. OD3
approved the 2% criterion, and OD5 keeps its meaning, until the owner amends
them. This page reports E66's measured spread apart from the row, labelled as
convention plus the reference's residual. It does not relabel the row.

**What can be said before any validation.** Two quantities describe a tag's
provenance. Neither is an error interval.

  - The **observed spread** is the realized difference between admissible
    rules on the same parent. It says how much the choice of rule matters. It
    is not a lower bound on the error: if the selected rule is right, its error
    is zero whatever the spread. A tag whose observed spread exceeds the
    approved per-tag row is *convention-sensitive*.
  - The **exposure screen** of a tag sums, over each listed rule not yet
    validated, the gross same-state defect, times a sampled amplification
    `K̂`, plus the measured numerical error `F` (section 3). Each rule's term
    is reported too. The screen flags the rules that could matter. It
    is not an upper bound. `K̂` comes from sampled perturbations and times, and
    the true amplification can be larger across nonlinear repairs, clamps and
    solver states. The screen would become a bound only once the operators,
    the states and a propagation bound are established for the case.

A rule is *validated* only where a reference that does not share it has tested
it, in a case where the rule was active (section 2). Closure, and agreement
between references that share a rule, are never provenance validation.

## 2. The evidence levels

Two axes, reported per tag, per case and per OD2 window. A lower rung is never
evidence for a higher one. Val-1 and Val-2 are screens. Only Val-3 and Val-4
validate, and only for the rules named with them.

**Fidelity: does the code solve its declared equation?**

| Level                 | Shows                                                                                                                                      | Required evidence                                                                                                                                                                                                                                                                                          | Cannot show                                                                                                                                                                              |
|:--------------------- |:------------------------------------------------------------------------------------------------------------------------------------------ |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fid-0 closed          | The tags are passive and sum to the parent                                                                                                 | Parity bit for bit; the closure rows; the negative-water latch not set (the parent-validity row voids the case otherwise)                                                                                                                                                                                  | Any composition                                                                                                                                                                          |
| Fid-1 well-posed      | The attribution is linear where it is declared linear, independent of tag order, symmetric in labels, bounded, and composes under grouping | Uniform composition (exists, 1e-12); permutation; a duplicate tag; proportionality (`evap_tropo` against `evap`); overlay at most parent; source integral at most production; superposition and aggregation with distinct footprints (needs PP-BAND, deferred); the three-tag hull (ATTRIBUTION_PATH's V8) | That any rule is right. It is blind to a consistently wrong linear rule, and proportionality alone is blind to rules that are homogeneous of degree one (the repair, van Leer per field) |
| Fid-2 ledger-complete | Every mechanism that sets a label is named and classed, and each tag's change equals the sum of its named parts                            | Per-tag, per-process accounting from the same state (the `ic_miss_probe.jl` pattern), closing to rounding; every rise attributed                                                                                                                                                                           | The size of any rule's error                                                                                                                                                             |
| Fid-3 faithful        | The code solves its declared equation within a measured numerical error `F`                                                                | The follower's work split into lag and structure (PX7); the faithful parts converge (the OD3 refinement row); exact per-tag counterparts for bracketed transport where it is material (PX8)                                                                                                                | Whether any assumed rule is the right physics; any bound on propagation                                                                                                                  |

**Validity: is the declared equation right?**

| Level                           | Says                                                                                                                                                            | Required evidence                                                                                                                                                                                                                                                                       | Cannot say                                                                           |
|:------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------ |
| Val-0 unscreened                | Nothing                                                                                                                                                         | —                                                                                                                                                                                                                                                                                       | —                                                                                    |
| Val-1 spread observed           | The observed spread over the admissible alternatives of each material rule. The tag is *convention-sensitive* where the spread exceeds the approved per-tag row | Realized same-parent pairs with feedback, or first-order estimates labelled as such; the admissible alternatives fixed by OD11 before the run                                                                                                                                           | That any rule is right; any bound on the error                                       |
| Val-2 screened                  | The tag's exposure screen, summed over its listed rules, stays within the approved per-tag row, at the sampled states                                           | Fid-2, which gives the list of rules; the screen of section 3; every realized rule-against-rule difference at most its screen, else the screen is void                                                                                                                                  | Any bound on the error; rules missing from the list; states not sampled; conventions |
| Val-3 validated for named rules | Each named rule was active in the case and passed a reference that does not share it                                                                            | Same-state per-tag process accounting, complete in the case (Fid-2), which names the active rules; the verdict record below; the excluded processes measured inactive; the reference's floors passing (surface, initialization, parent error, contamination); reference validity (OD12) | Shared rules; rules inactive in the case; definitional rules; untested regimes       |
| Val-4 held out                  | Val-3 carries over, without retuning, to a case named before any rule was tuned                                                                                 | Val-3 on that case (G3 criterion 8), under OD14's hygiene                                                                                                                                                                                                                               | Regimes outside the envelope                                                         |

**Conventions** are declared in the claim contracts (G3 criterion 12,
[design/G4_CLAIM_CONTRACTS.md](design/G4_CLAIM_CONTRACTS.md)). Their spread,
such as `c`/2`c` or the mask's placement and width, is reported beside the
levels. They never pass or fail. For energy, every level is conditional on the
fixed `c` and source convention.

**What every verdict records.** Each gated result of section 7 reports, per
tag:

 1. parent parity: bit for bit against the untagged twin, and the
    parent-validity row;
 2. rule exposure: the exposure screen of each listed rule, and how it was
    formed;
 3. numerical convergence: the refinement row and `F`;
 4. comparator floors: surface, initialization, parent error and
    contamination;
 5. per-tag L1 and L∞ under the existing OD3 criteria, as approved;
 6. the rules: those active and validated, those shared with the reference,
    and those untested.

Energy verdicts add the fixed `c`, the source convention, the `c`/2`c` spread
and `C4`'s size. If a prerequisite fails, the verdict says *not assessable*.
If the observed spread exceeds the row, it says *convention-sensitive*.
Closure, or a comparison with a reference that shares the rule, is never
promoted to provenance validation.

**How the levels map onto rev. 2.**

  - Fid-0 is the contract's Parent validity and Closure rows.
  - Fid-1 is the Aggregation row, which stays reported, plus a proposed
    Invariants row.
  - Fid-2 is the Intervention row plus a proposed Ledger-completeness row.
  - Fid-3 is the Convergence row.
  - Val-1 is a proposed Observed-spread row, and Val-2 a proposed
    Exposure-screen row. Both are reported, never scored.
  - Val-3 is the Provenance and Comparator-eligibility rows, plus a proposed
    Reference-validity row.

**OD3 and OD5 stay as decided.** OD5's "provenance bounded, not validated"
keeps its meaning of 2026-09-24: the Insight 10 tests (refinement, per-tag
intervention, aggregation) under their thresholds. The levels above are
reported beside rev. 2's verdicts. They change no threshold, and they do not
amend OD5. The per-tag `led_fixgross` (`q_tag_led_fixgross_<tag>`, the sum of
the steps' absolute changes per cell) enters the repair's exposure screen with
a factor of 2, the repair's Lipschitz factor. The retained `led_fix` is net
over time and understates it.

**OD8.** The counts do not change: 8 water and 8 energy tags, copies at 8, no
bridge. Per-process, per-tag accounting is done by probes, not by new state
fields, because the build time grows with the number of fields (W34: 699 s at
8 copies, 2417 s at 16).

## 3. The exposure screen

Take two rule sets on the same parent. Compute the per-step difference `δⁿ`
between them from the same state, as the WP4c gate does. Let `K` be the
supremum of the L1 operator norm of the full per-tag propagator, over every
state the run passes through. Then, per tag,

`‖e_i(T)‖₁ ≤ K · Σₙ ‖δ_iⁿ‖₁`.

That is the ideal inequality. What can be measured is weaker. PX9 would sample
`K` from spike arms at a few times and levels. The sampled `K̂` can be below
the true supremum, most of all across the nonlinear repairs, clamps and solver
states listed below. So the measured `K̂ · Σₙ‖δ_iⁿ‖₁ + F` is a *screen*. For
a tag it is summed over the listed rules, and each rule's term is reported.
It flags rules whose exposure could matter. It is not an upper bound. A screen
below the row finds no sign of material exposure among the listed rules at the
sampled states. It says nothing about rules missing from the list. Until PX9
runs, the screen takes `K̂ = 1` and says so.

The premises still matter for a screen.

 1. **The sum is gross, never net.** `Σₙ‖δⁿ‖`, not `‖Σₙ δⁿ‖`. WP4c's part 3
    (W40) accumulates `D` per cell and step without feedback and reports its
    net. So part 3 is a first-order estimate of an observed spread. It screens
    nothing and certifies nothing. Its ratio to part 2b is not evidence for the
    inequality.
 2. **Where the alternative is unknown,** the per-tag term takes the
    *worst-case form* `Σ G · max(a_i, 1 − a_i)`. Here `G` is the gross
    label-carrying mass of the faithful process, and `a_i` is the share of it
    that the rule gives tag i. The true share lies somewhere in `[0, 1]`, so
    the rule's error on it is at most `max(a_i, 1 − a_i)`. This is not the
    per-tag gross that the rule wrote, which understates the minority tags.
 3. **Bracketed transport needs its exact per-tag counterpart,** the *exact
    form*. A bracket sees a net close to zero where labels still move. The 750 m
    label edge inside D4-W's well-mixed boundary layer is the case: the parent's
    subsidence tendency there is small, while `ρ|w| q |∂φ/∂z|` is not.
 4. **Hulls are optional.** Where the alternative is known to lie in a hull
    (the two cells of a face at both time levels, say), the factor becomes the
    range of `φ_i` over that hull. The hull must contain both trajectories,
    which needs a Gronwall widening.
 5. **`K̂` comes from unit spike arms,** not from smooth perturbations (PX9,
    deferred).

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

Each nonlinear piece is also listed in the inventory of assumed rules, with its
own gross: `led_fixgross` for the repair, the clamp's cut, the exchange's mass
where θ is below one, van Leer's antidiffusive flux. That gives each piece its
own screen term. It does not make the rest of the propagator linear. A
correction still changes the state that later steps act on, so its effect
propagates. PX9 would therefore sample `K̂` across these pieces, and the result
stays a screen. **The screen is only as good as the inventory**, so ledger
completeness (Fid-2) comes before any screen is read as clean. W42 found rises
that no single ledger accounts for by half, and E87 found `C4` outside the
residual, so the inventory is not yet complete.

**The L∞ route.** Suppose the propagator is positive, conservative and
constant-preserving for the operators and states of a case. A CI test checks
the last property to 1e-12, but for the SGS mass-flux tendency alone
(`tagged_water_edmf_integration.jl`). Then the composition update is
row-stochastic, and the sup norm of the composition error cannot grow. A
per-cell bound is then the accumulated largest relabelled fraction per cell.
This route opens only where positivity is shown for the operators, not
sampled. PX9's positivity index can close the route, by finding a negative
response. It cannot open it. On the centred rungs positivity is not expected,
for the two reasons in the last two bullets above.

**Prior evidence on the size of the screen (read before this page, so not
scored).** On D4-W the follower's per-tag gross attributed to each operator,
the gate's part 2b, is 3.23% from `vdiff` and 3.97% from `sgs_mass_flux` for
`tropo` over the gate's 0.924-day window (`output/wp4c_gate/score.txt`). That
is about 7.2% together, and about 2.0% for `strat`. Part 2b is the gross that
the rule wrote, so it understates the worst-case form. So the screen for
`tropo` on D4-W already exceeds the 2% row. That does not show an error above
the row. It shows that the follower's rules are material there, and need a
reference that does not share them, or a narrower claim.

## 4. The rule inventory

Each rule acting on a tag, its class, and the per-tag account that exists
today. The claim contracts (OD11) must adopt this classification before any
spread or screen is used in a label. Otherwise a screen can be gamed by calling
a rule definitional. A screen of one rule whose class is not in doubt, such as
PX1's, may be reported earlier to decide the next gate.

| Rule  | What it does                                                                                                               | Class                                                                              | Per-tag account today                                                 |
|:----- |:-------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------- |:--------------------------------------------------------------------- |
| WR1   | Region tags take new water by mask                                                                                         | definitional                                                                       | the brackets' records                                                 |
| WR2   | Loss by the grid-mean donor share                                                                                          | definitional at cell scale; assumed where the process acts in a sub-volume (WR15)  | the brackets' records                                                 |
| WR3   | Subsidence and the GCM's large-scale subsidence reach the tags through the local bracket                                   | assumed; a faithful counterpart exists (per-tag `subsidence!`)                     | none per tag; the bracket sees the net                                |
| WR4   | Large-scale forcing and nudging import water by label                                                                      | definitional label (`fcg`); its subsidence part is WR3                             | the brackets' records                                                 |
| WR5   | Rescale after the limiters, borrowing and constraints, by the receiver's composition                                       | assumed                                                                            | `q_tag_fix_*`, `fixgross`, `led_rescale`                              |
| WR6   | Partition repair: a negative tag is charged to the positive ones by holdings                                               | assumed, nonlinear                                                                 | `led_repair`, per-tag `led_fixgross` (gross) and `led_fix` (retained) |
| WR7   | Share clamp and renormalisation                                                                                            | assumed, nonlinear                                                                 | the clamp's cut (W33: 1.2e-15 under the follower)                     |
| WR8   | SGS mass flux by the donor cell's share (default mode)                                                                     | assumed                                                                            | none per tag                                                          |
| WR9   | The exchange from the plume, and its bound θ                                                                               | assumed                                                                            | bound activation in the EDMF audit                                    |
| WR10  | The copies' own rules: surface relaxation to the grid-mean composition, the filter, their repair                           | assumed (the comparator's rules)                                                   | `q_tag_upfix_*`, `led_uprepair`, `led_upfilter`                       |
| WR11a | The follower's moved part: the tags' mismatch with the parent's increment, carried by donor shares                         | assumed                                                                            | `q_tag_inc_moved`, per-tag `led_inc`                                  |
| WR11b | The follower's placement of the column total (same sign or \|m\|)                                                          | assumed                                                                            | `q_tag_inc_left`                                                      |
| WR12  | Sedimentation resets the composition at each level (without the WP4b key)                                                  | assumed; the rain and snow parts are its faithful counterpart                      | none                                                                  |
| WR13  | WP4b's pool composition over the step                                                                                      | assumed                                                                            | the audit `q_rtag_aud_*`, `q_stag_aud_*`                              |
| WR14  | The net-flow fallback between compartments                                                                                 | assumed; exact for one-way flows                                                   | the same audit                                                        |
| WR15  | The 0M rain-out by the grid-mean composition, or split by subdomain (WP4a, #104)                                           | assumed                                                                            | `pr_tag`                                                              |
| WR16  | Option C's entry of the negative part                                                                                      | assumed; void where the parent is invalid                                          | V5's ledger                                                           |
| WR17  | The `q_tot_eff` leaks and their attribution (the follower's donor shares, or WP4c's ψ)                                     | gap, then a convention                                                             | `q_tag_leak_<path>`, WP4c's ledgers                                   |
| WR18  | The surface excess's composition: the plume starts at the grid mean, the copies relax to it, a passive tracer gets nothing | convention                                                                         | none                                                                  |
| WR19  | Bracket granularity                                                                                                        | definitional                                                                       | —                                                                     |
| WR20  | Per-field nonlinear reconstruction of the tags' own transport (van Leer; SEM on the sphere)                                | assumed, nonlinear                                                                 | none; zero on columns without a limiter (W3)                          |
| ER1   | The offset `c`                                                                                                             | definitional; fixed for every conditional test (110,495 J/kg in the record's runs) | the `c`/2`c` pair                                                     |
| ER2   | Donor-proportional loss                                                                                                    | definitional                                                                       | —                                                                     |
| ER3   | Mask placement and width                                                                                                   | definitional                                                                       | a bracket                                                             |
| ER4   | The default exchange's repair (E86: 7.3% of the throughput a day)                                                          | assumed                                                                            | `e_src_fix_*`, `fixgross`                                             |
| ER5   | The follower's placement (OD7)                                                                                             | assumed                                                                            | the left-out part (E79)                                               |
| ER6   | The upward branch for ice and snow                                                                                         | assumed; its sign flips with `c`                                                   | none                                                                  |
| ER7   | Granularity of the radiation labels                                                                                        | definitional                                                                       | —                                                                     |
| ER8   | The per-tag outflow of `C4` (E87)                                                                                          | gap; a limitation of every energy verdict                                          | none                                                                  |
| ER9   | The energy copies' surface relaxation toward the grid-mean composition (mirror M2 of `design/ENERGY_COPY_MIRRORS.md`)      | assumed                                                                            | `e_src_copy_res`                                                      |
| ER10  | The energy exchange and plume                                                                                              | assumed                                                                            | bound activation                                                      |
| ER11  | Energy subsidence (the `sub` tag)                                                                                          | definitional; no faithful counterpart, since the parent subsides `h_tot`           | the records                                                           |
| ER12  | The energy follower's moved part                                                                                           | assumed                                                                            | `e_src_led_inc_*`                                                     |

## 5. The coverage matrix

Each assumed rule, the screens that size it, and the references that could
validate it. Screens never validate. A reference validates a rule only in a
case where the rule was measured active, with the excluded processes measured
inactive and the reference's floors passing (section 2).

  - Screen is the exposure form of section 3. Spread is the observed spread
    between admissible rules. Neither column validates.
  - Exact is the exact per-tag counterpart with feedback (PX16 with PP-SUB).
    Air is the passive-tracer twin (PX11 on Soares, or PX17 with PP-TRACER).
    Copies is eligible copies (PX12). Replay is the sub-step replay (PX14).
  - `★` is the first valid reference, `○` a further one, `×` invalid because
    it shares the rule, `—` not applicable. "(d)" marks an item that section 7
    defers.

The Air column validates a rule only against the default mode. Against the
copies, the air twin shares the updraft filter
(`enforce_edmf_updraft_constraints!`), so it cannot validate the filter in
WR10.

| Rule                                      | Screen                                                        | Spread                    | Exact  | Air                               | Copies             | Replay     |
|:----------------------------------------- |:------------------------------------------------------------- |:------------------------- |:------ |:--------------------------------- |:------------------ |:---------- |
| WR3 subsidence through the bracket        | exact form (PX1, PX8)                                         | —                         | ★ PX16 | × (○ PX17 (d))                    | ×                  | —          |
| WR5 rescale by the receiver               | PX20 (d); zero on columns                                     | —                         | —      | —                                 | ×                  | —          |
| WR6 partition repair                      | `led_fixgross` × 2                                            | —                         | —      | ○ PX11, where it acts             | ×                  | —          |
| WR7 clamp and renormalisation             | the cut                                                       | —                         | —      | ○ PX11, where it acts             | ×                  | —          |
| WR8 SGS donor share                       | worst case                                                    | —                         | —      | ★ PX11                            | ○ PX12 (d)         | —          |
| WR9 exchange and θ                        | worst case                                                    | —                         | —      | ★ PX11                            | ○ PX12 (d)         | —          |
| WR10 the copies' own rules                | the comparator's floor; its cause PX5 (d)                     | —                         | —      | —                                 | itself             | —          |
| WR11a follower, moved                     | lag goes to `F`, structure to the worst case (PX7)            | PP-FACE (d), a convention | —      | ○ PX11, where it acts             | —                  | —          |
| WR11b follower, placement                 | —                                                             | PX3 (d)                   | —      | —                                 | —                  | —          |
| WR12 sedimentation reset                  | —                                                             | —                         | —      | —                                 | —                  | ★ PX14 (d) |
| WR13 WP4b pool                            | —                                                             | —                         | —      | —                                 | —                  | ★ PX14 (d) |
| WR14 net-flow fallback                    | the audit                                                     | —                         | —      | —                                 | —                  | ○ PX14 (d) |
| WR15 0M rain-out                          | —                                                             | —                         | —      | ×                                 | ★ PX12 (d), as W32 | —          |
| WR16 option C's entry                     | before the latch                                              | —                         | —      | —                                 | —                  | —          |
| WR17 leaks and their attribution          | the closed form                                               | PX2 (d)                   | —      | —                                 | —                  | —          |
| WR18 surface excess                       | —                                                             | PX13 (d)                  | —      | × (○ if the level-1 check passes) | ×                  | —          |
| WR20 per-field reconstruction             | PX20 (d)                                                      | —                         | —      | ×                                 | ×                  | —          |
| ER4 energy repair                         | `fixgross` × 2 (PX22); on and off as a sensitivity (PX10 (d)) | —                         | —      | ×                                 | ×                  | —          |
| ER6 upward ice and snow branch            | none today; its sign flips with `c`                           | —                         | —      | —                                 | —                  | —          |
| ER5 energy placement                      | the left-out size (E79)                                       | the E79 pair              | —      | —                                 | —                  | —          |
| ER8 `C4` outflow                          | its size from the `c`/2`c` pair (E87, PX22)                   | —                         | —      | —                                 | —                  | —          |
| ER9 the energy copies' surface relaxation | the comparator's floor (`e_src_copy_res`)                     | —                         | —      | ×                                 | itself             | —          |
| ER10 energy exchange                      | worst case                                                    | —                         | —      | × (plausibility only)             | × (E84)            | —          |
| ER12 energy follower, moved               | PX15 (d)                                                      | —                         | —      | —                                 | —                  | —          |

The definitional rules WR1, WR2, WR4, WR19, ER1 to ER3, ER7 and ER11 are
declared, and their spread is reported. They have no row here.

**What the gated plan can validate.** Two items only. PX16 can validate WR3 on
D4-W, if the subsidence gate reaches it. PX11 can validate the transport rules
active in Soares, and only once PX24's per-tag accounting is complete there:
WR8 and WR9, and WR6, WR7 and WR11a where they are measured active. Without
PX24, PX11 gives an aggregate comparison of the transport bundle and names no
rule. Every other rule stays screened or untested, and every verdict lists it
so. ER6 has no screen at all yet.

## 6. Theories

Each theory is a falsifiable hypothesis. No run on this page tests any of them.
"Prior" names what is already on the record; those values were read before
this page, so they are prior evidence only. The gated plan tests PT2, PT4 and
PT9, and the energy part of PT8 (PX22). The others wait for their deferred
experiments.

**PT1. The null space is weak but real.** Closure metrics do not track the
composition error between closing rule variants on a shared parent.

  - If true: across the same-parent pairs (W24 against W28, W40 against V1,
    E79, PX10), closure changes by at most 1e-4 and does not rank with the
    per-tag difference, which reaches percent.
  - If false: the closure change ranks with the per-tag difference.
  - Prior: W28, W29, W36, W40. W43's out-of-range rule failed closure, so this
    refines the null-space claim rather than refuting it.

**PT2. Subsidence is a large shared relabelling at D4-W's 750 m split.** Near
the inversion the bracket gives subsiding water the receiving cell's label. The
inversion is at 795 m in the RF02 profiles; the 30-level grid's step is at 825 m
(E5). `subsidence!` is linear in χ, so the exact per-tag answer is known.

  - If true: the gross exact-form exposure for `strat` exceeds 2% of its
    inventory a day. It concentrates between 700 and 950 m and is
    sign-coherent (`s > 0.7`). The realized difference with PP-SUB exceeds 2%
    L1 or 5% L∞ at 24 h.
  - If false: that exposure stays below 0.2% a day for every tag.
  - Prior: unmeasured. A reasoned estimate from the RF02 profiles, not on the
    record: the defect `ρ|w| q Δφ` is about 1.1 × 2.8e-3 m/s × 5e-3 to 9e-3,
    so about 1.3 to 2.4 kg m⁻² a day, against a `strat` inventory of about 3.4
    kg m⁻². DYCOMS subsides with `w = −3.75e-6 z`. Mixing inside the boundary
    layer weakens the label edge, so the real defect may be smaller; PX1
    measures it. The default-against-copies agreement (W24: 0.25%, 0.41%,
    0.41%) cannot see it, since both share the bracket.

**PT3. The leak's attribution matters after feedback.** W40's first-order part
3 (`tropo` L1 2.4%, L∞ 6.2%) survives in the realized full-run difference to
within a factor of two.

  - If false: the realized difference is much smaller. Feedback then flushes
    the relabelling, and first-order estimates overstate the observed spread
    across the record.
  - Confounded by W45: the correction did not take the follower's `vdiff`
    share, so part 3 does not describe the corrected run. PX2 therefore scores
    the realized difference itself, and reports its ratio to part 3 only
    beside it.
  - Prior: W40; W45, whose V1 run keeps parity on 37 fields.

**PT4. The follower's work is mostly lag.** On a monotone solver ladder the
part moved because of `vdiff` falls by at most 0.75 per doubling and reaches at
most 0.25 of the default at four Newton and eight linear iterations.

  - If false: a doubling leaves more than 0.9 of it (structural), and the
    linearisation, Jacobian and post-solve parts carry at least half. Its
    donor-share assignment is then a convention, reported with its spread.
  - Prior: W41 (the tags' Newton error 0.20 for `evap` against the parent's
    1.2e-2 at one iteration); W45 (part 2a rose from 2.92% to 3.09%); W38's R10.
    W45 did not resolve the mechanism.

**PT5. The tag propagator is L1 non-expansive but not positive on the centred
rungs.**

  - If true: the spike arms give `sup K̂ ≤ 1 + ε`; the positivity index is
    above zero where the centred exchange or the truncated solve acts; the
    response is linear to `ε`.
  - If false: `K̂ > 1` somewhere. The screen then uses the measured
    `sup K̂`, and on/off trials locate the operator.
  - Either way, a sample cannot show that `K ≤ 1` for every state, nor that
    the propagator is positive.
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
sets labels with no per-tag account. Water: option C's entry, and the part of
W42's rises that no ledger records. Energy: `C4`'s per-tag outflow.

  - If false: probe accounting closes per tag to rounding in every window.
  - Prior: W42 (in 4 of the 10 largest rises no single ledger reaches half the
    rise); E87 (A5 fails).

**PT9. The transport rules are faithful in a clean regime.** On Soares (no
subsidence, no sinks) the nearly source-free upper tag equals the
water-weighted passive tracer within its floors plus the budget, in both modes.

  - If false: at least one rule active in Soares is not faithful there.
    PX11's branches say which group: the plume and the exchange, or the
    follower and the grid-scale rules.
  - PX11 tests it only for the rules active in Soares.
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

  - If false: `K̂` stays above 0.8 at day 90, or grows.
  - Prior: energy, E60 and E74. Unmeasured for water.

## 7. Experiments

Status marks:

  - **[R]** re-scores output that exists, with no new run. Some of it is on
    Levante scratch only, so PX0 comes first.
  - **[K]** runs on existing keys, with a probe script, a config or a driver
    only. Each job follows the record's approval rule (STATUS.md, "What needs
    approval").
  - **[P]** needs a named diagnostic-only probe PR (section 8): a draft, off by
    default, the parent bit for bit, validated against an untagged twin.

Every experiment names its run tree. The current code lacks #109's per-tag
ledgers and the leak-correction key on `main`, so any comparison with an
existing run uses that run's tree as recorded in [RUNS.md](RUNS.md). Every
decision rule is committed in a dated design note before any file it judges is
opened.

### 7.1 The gated plan

Five gates. Gate A comes first. Gates B, C and E can then run side by side.
Gate D follows gate C, because the follower acts in the benchmark's default arm
and its lag must be known to read a failure there.

  - **Gate A, the archive (PX0).** Archive and fault-check the existing data.
  - **Gate B, the shared subsidence rule (PX1, PX8, then PX16).** PX1 screens
    it from hourly output. A PX1 result above the exploratory trigger is a
    reason to go on. One below it is not assessable, since hourly output can
    miss a short-lived effect. So PX8, the accepted-step exact counterpart,
    always follows PX1. The feedback comparison, PX16 with PP-SUB, follows
    only if PX8 is material, and after OD13.
  - **Gate C, the follower (PX7).** Resolve whether its measured work is lag or
    structure. W45 did not resolve that mechanism.
  - **Gate D, one clean label benchmark, then one held-out case (PX24 and
    PX11, then PX23).** PX24's per-tag process accounting comes before PX11
    names any rule. The held-out case is named before any rule is tuned
    (OD14). Val-4 stays not assessable until an independent case and its
    reference are fixed.
  - **Gate E, energy at a fixed `c` (PX22).** The budget and `C4` checks at the
    fixed `c` and source convention.

Every gated result writes the verdict record of section 2. If a prerequisite
fails, the gate reports *not assessable* and stops. It does not fall back on
closure or on a comparison with a reference that shares the rule. "Material"
in gate B uses the exploratory 0.2%-a-day screen (ROADMAP, "Provenance pathway:
exploratory numbers and proposals"). Only PX8's accepted-step value decides
whether PX16 is proposed. PX1 can bring PX8 forward, never skip it. The owner
approves each job, and may change the number before PX8 is read.

**PX0. Archive first.** [R] No score. Archive and checksum the NetCDF and CSVs
of W24, W28, W38 to W43, W45 (there is no W44), E85 and `g46` from scratch.
RUNS.md's backfill says W38 to W45 are not yet synced. Feed every new script
faults before any score is read: a removed variable, a shifted time, a truncated
run, a flipped signed zero, a permuted tag name. Each must fail closed. Hours.

**PX1. The subsidence screen.** [R] Tests PT2.

  - Data: the hourly profiles of W38's `w25i_d4w_default_z30_c` and `_z60_c`,
    with DYCOMS's `w = −3.75e-6 z`.
  - Method: per tag, the exact rate `R_ex,i`, which is first-order upwind
    `subsidence!` of `χ_i`. The bracket's rate
    `R_br,i = M_i max(Δ, 0) + φ_i min(Δ, 0)` with `Δ = Σ R_ex`. Here `M_i` is
    tag i's mask weight in the cell, which the bracket gives new water, and
    `φ_i` is tag i's share of the cell, which the bracket takes water by. The
    gross exposure `∫∫ abs(R_ex − R_br)`, the sign coherence `s`, and a map by
    level.
  - Reference: the parent's own linear operator, which does not share the
    bracket. The copies and the unsubsided tracer are invalid here.
  - Rule: a screen, reported and not scored. Hourly output is coarser than the
    step and can miss a short-lived effect between outputs. So a result at or
    above the exploratory 0.2% of an inventory a day is a reason to go on. A
    result below it is not assessable. It is not evidence that subsidence is
    immaterial. PX8 follows either way.
  - Code: none. Hours.

**PX8. The same-state subsidence probe.** [K] Tests PT2 and gives its screen
term. It follows PX1 whatever PX1 finds.

  - Tool: a new script, `analysis/water/sub_probe.jl`, on the pattern of
    `wp4c_gate_probe.jl`. From each accepted step's state it evaluates
    `subsidence!` on `ρq_tot`, the exact `T_i` per tag and the bracket's `B_i`.
    It asserts `Σ T_i = Σ B_i = Δ` to the partition's residual `q_tag_res`, so
    closure is blind by construction. It accumulates the gross
    `G_i = Σ_k dt ∫ abs(T_i − B_i)`, the net `D_i` and `s_i`.
  - Cases: `w25i_d4w_default_z30_c` (as W40) and `_z60_c`, 24 h, in their own
    trees. A GCM arm: site 23, which subsides, days 1 to 3 and then 1 to 9, with
    `ic_miss_probe.jl`'s explicit per-term probes for the large-scale
    subsidence. Record the operator's L1 column sums there, since the advective
    form can expand where `abs(w)` falls with height.
  - Rules: the screen term is `K̂ · G_i`, with `K̂ = 1` unless PX9 has run.
    `G_i` below the exploratory 0.2% of every inventory a day records
    subsidence as screened immaterial for that case. That is a screen, not a
    validation. At or above 0.2% for any tag, PX8 is material. The pathway
    then proposes PP-SUB and PX16 to the owner, and every D4-W
    default-against-copies number gets a dated annotation: "shared
    subsidence rule: its exact-form exposure measured, not in the
    comparison".
  - Code: none; the script calls the model's operator on scratch copies. Two
    D4-W jobs and a short GCM probe.

**PX16 (PP-SUB). Per-tag subsidence, with feedback.** [P] Tests PT2 against an
exact counterpart. Only if PX8 is material, and after OD13.

  - Runs: D4-W `z30_c` default with `water_tag_subsidence: per_tag`, the same
    with `bracket`, and the untagged twin, 24 h.
  - Metric: the realized per-tag difference with feedback, against the screen
    `K̂ · G` from PX8.
  - Rules: a difference above the screen shows that the inventory or `K̂` is
    incomplete, and the screen is void for the case. Above 2% L1 or 5% L∞, the
    default fails the provenance row on D4-W for subsidence, whatever any
    comparator says. Within the row, WR3 is validated on D4-W against its
    faithful counterpart, for that case only. Both arms share every other rule,
    so the verdict lists them as untested. Adoption is the owner's call.

**PX7. The follower's work: lag or structure.** [K] Tests PT4. This is the
investigation that W45 requires. Its scripts reserve the ID W46; no job exists
yet.

  - Tool: `analysis/water/wp4c_diag_probe.jl` on `wp4c_corr_d4w_default`, from
    6600 s, with the solver sets default, `lin4`, `lin8`, `newton2lin2`,
    `newton4lin8` and `newton10lin10`. A second set turns `sgs_mass_flux` off in
    trial C; that switch must be added to the script before the run. Run
    `wp4c_upleak_check.py` on V2.
  - Pre-register the rule as a dated amendment to
    [design/WP4C_CORRECTIONS.md](design/WP4C_CORRECTIONS.md) section 8 before
    the result is read. Read it by monotone ratios, not by the distance to the
    unconverged ten-iteration set (W41).
  - Rules: the work is *lag* if `newton4lin8` leaves at most 0.25 of it and
    each doubling at most 0.75. That part then enters `F`, and V1's criterion 1
    is scored again at the converged set. The work is *structural* if any
    doubling leaves more than 0.9 of it. Its parts are then read with the share
    rule of `design/NEGATIVE_PARENT_WATER.md` section 9: a share of at least
    0.5 attributes, 0.1 to 0.5 contributes. A structural part is a convention,
    reported with its observed spread. PP-FACE (for the linearisation,
    Jacobian and post-solve parts) and PP-JAC (for `filt_T − filt_q`) stay
    deferred until this result shows that one of them is needed.
  - Neither branch validates the follower. Lag makes its error numerical and
    measurable; structure makes it a convention.
  - This answers WP4c's default. One or two jobs of one to two hours.

**PX11. The clean label benchmark: the Soares air twin.** [K] Tests PT9. The
passive tracer is specified and implemented apart from the tag rules. With no
sinks and no subsidence, the declared labelling model makes the source-free
`up` tag equal to the water-weighted tracer.

  - Case: `prognostic_edmfx_soares_column.yml` (1M, 75 levels, `dt` 5 s, 8 h;
    `Soares.jl` sets no subsidence and no large-scale forcing) with water tags
    `low` and `up`, split at the untagged run's boundary-layer top at 2 h (fixed
    before the scored runs), plus `evap`. `chemistry_model` passive. The driver
    sets `ρq_gas_A = M_up · ρq_tot` and its updraft copy `M_up · q_totʲ`, on
    `d4w_driver.jl`'s pattern. That driver sets the mask itself, a tracer of
    air, as in W17. Arms: untagged, default, copies, with parity.
  - Excluded processes, measured inactive on the untagged run before any
    tagged output is read: sedimenting condensate (`∫pr` below 1e-4 of the
    water), subsidence and large-scale forcing (their tendencies zero). If one
    is active, the benchmark is not assessable.
  - Floors, each at most a quarter of the budget (OD12), else not assessable:
      + surface: the `up` tag's mask-gain bound `M_up(z₁) ∫evspsbl / ∫ρq_up`;
      + initialization: the tag against the tracer at the first output, grid
        mean and updraft;
      + parent error: the parent's Newton error at this iteration count (one
        W25 P1 probe);
      + linearity: a twin with `q_gas_A = M_low · q_tot`, whose sum is checked
        against `ρq_tot` above the boundary layer and as column integrals
        against the cumulative `evspsbl`.
  - The water tags must build on the login node first.
  - Score only the `up` tag, which avoids the tracer's surface convention.
  - Reference: EDMF's passive-tracer equations. Against the default mode they
    share no tag rule: no mask gain, loss rule, follower, plume, exchange,
    repair or clamp. They do share the grid-scale transport operators. Against
    the copies they also share the updraft filter's clamp and reset
    (`enforce_edmf_updraft_constraints!`).
  - Rules, on OD3's approved rows: at 1 h the first-hour row for a region tag
    (L1 at most 1%, L∞ at most 25%). At 8 h, the case's end, the 24 h row (L1
    at most 2%, L∞ at most 5%); applying it at 8 h is a proposal under OD12.
    The floors must pass first. They are not subtracted from the scores.
      + Both modes pass, and PX24's accounting is complete: the tag rules it
        measures active in Soares are validated there, and only those. The
        verdict lists them, with the shared transport operators and the
        untested rules.
      + Both modes pass, but PX24 is missing or incomplete: the transport
        bundle agrees in aggregate. No single rule is named as validated.
      + The copies pass and the default fails: the plume or the exchange is
        isolated.
      + Both fail alike: the follower or the grid-scale rules; PX7's result
        says which.
  - Code: none. About six short runs; copies compile in 28 to 41 min.

**PX24. The benchmark's per-tag process accounting.** [K] Before PX11 names
any rule. Tests PT8 on Soares.

  - Tool: a new script, `analysis/water/tag_process_probe.jl`, on the pattern
    of `ic_miss_probe.jl` and `wp4c_gate_probe.jl`. From each accepted step's
    state in PX11's default arm, it evaluates each operator's per-tag
    tendency on its own. The operators are the grid-scale transport, the SGS
    mass flux by donor share (WR8), the exchange and its bound θ (WR9), the
    repair (WR6), the clamp (WR7) and the follower (WR11a). The copies arm
    gets the same accounting if its verdict is to name rules. The parent is
    checked bit for bit in every trial.
  - Today WR8 has no per-tag account and WR9 has only bound activation
    (section 4), so this probe is what names the active rules.
  - Metrics: per tag and rule, the gross over each window; and the
    completeness residual, each tag's step change minus the sum of its named
    parts.
  - Rules: the accounting is complete if the residual is at rounding for
    every tag and window (OD10's proposal). A rule then counts as active
    where its per-tag gross is above rounding, and PX11 may name it. If the
    accounting is not complete, PX11 reports only an aggregate comparison.
  - Code: the script only, no model code. It runs on PX11's arms.

**PX23. One held-out case.** [K] Only after PX11. OD14 names the case, its
window and its metrics before any rule is tuned on PX11's result. The case is
never used to develop a rule. Soares, TRMM 0M and sites 23 and 26 are
development cases. It is reported beside G3 criterion 8, which stays as
approved.

  - It needs a reference that is valid in its case. The air twin is valid
    only without sinks, subsidence or sedimentation (OD12). Criterion 8's
    columns do not qualify. RICO and BOMEX set `subsidence_forcing`. ARM SGP
    is a deep 1M case driven by large-scale forcing from a file
    (`prognostic_edmfx_armvaranal_column.yml`). The GCM-driven column
    subsides.
  - So OD14 either names a held-out window where PX11's reference stays
    valid, measured as in PX11, or PX23 waits for a reference for that
    regime: PP-TRACER (PX17) for subsidence, or eligible copies (PX12). Until
    then PX23 is not assessable.
  - Criterion 8's GCM-driven column starts from site 23, which has been used
    to develop option C (known issue 7). The owner stated on 2026-09-26 (PR
    #122) that a site-23-derived case does not count as held out for a rule
    developed using site 23.
  - So Val-4 stays not assessable until an independent case and its
    reference are fixed.
  - The run writes the same verdict record. Val-4 is reached only for the
    rules that PX11 validated, and only if the held-out case passes without
    retuning.

**PX22. Energy at a fixed `c`: the budget and `C4` checks.** [K] Tests the
energy part of PT8.

  - Case: `g411x_d4_default` at the fixed `c` (110,495 J/kg unless OD11 names
    another), with the source convention of the claim contract, and its
    untagged twin. E87's `g46_d4_budget`, `_2c` and untagged runs are prior
    evidence from their own tree.
  - Checks at the fixed `c`:
      + parity against the untagged twin;
      + each tag's change equals its named process terms from the same state.
        This is the per-tag form of E87's identities I and II. It uses the
        per-tag records and ledgers that exist, listed first as in section
        4's last column;
      + the repair's per-tag gross `e_src_fixgross_*` is its screen term,
        with a factor of 2.
  - The `C4` check: its size in the case, from the `c`/2`c` pair, as E87's A5.
    It is reported with every energy verdict. Where it goes per tag stays a
    limitation, unless a measured result makes a per-tag outflow probe
    necessary.
  - Rules: a per-tag budget that does not close to rounding at the fixed `c`
    fails Fid-2 for energy, and the energy verdicts are not assessable.
    Otherwise every energy verdict is conditional on that `c` and convention,
    and lists the `c`/2`c` spread and `C4` as limitations.
  - Code: none; output keys only. Two or three D4 jobs: at `c`, at `2c`, and
    the untagged twin. E87's runs stay prior evidence.

### 7.2 Deferred until a measured result needs them

Each of these waits for its trigger. None is on the gated path.

| Item            | What                                              | Trigger                                                                                                                      |
|:--------------- |:------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------- |
| PX2             | The leak rule realized with feedback              | OD11 lists ψ as admissible, or PX7 finds the follower's work structural                                                      |
| PX3             | The placement pair, W24 against W28               | The owner takes up OD7 and asks for its water side                                                                           |
| PX4             | Invariants on existing output                     | Before any Fid-1 label is reported                                                                                           |
| PX5             | Why the copies are ineligible on D4-W             | Before copies serve as a comparator on D4-W (step 4)                                                                         |
| PX6             | The missing-channel inventory                     | A verdict's rule list shows a channel with no account; PX24 covers the benchmark; the option C miss probe stays with step 8a |
| PX9             | The propagation probe, which samples `K̂`         | A screen lies near the row, and `K̂ = 1` decides it                                                                          |
| PX10            | The energy repair on and off at 8 tags            | PX22 finds the repair's per-tag screen material at the fixed `c`                                                             |
| PX12            | TRMM 0M comparator eligibility on current code    | A second benchmark, for the sub-grid rules, is needed after PX11                                                             |
| PX13            | The surface-excess comparison, then PP-SFC        | The owner takes up W21's surface rule, or PX11's surface floor fails                                                         |
| PX14            | WP4b's pool and the sedimentation reset, replayed | WP4b moves toward validation (step 8b), after #121's review                                                                  |
| PX15            | The energy follower's split                       | PX7 has read, and G4.7 or OD7 needs the energy side                                                                          |
| PX17            | A subsided passive tracer (PP-TRACER)             | PX8 finds subsidence material, and a comparator beyond PP-SUB is needed                                                      |
| PX18            | A band region (PP-BAND)                           | The owner asks for more than a reported aggregation row, or a measured departure needs it                                    |
| PX19            | The flush rate                                    | Before the 90-day sphere, if a long-run screen is needed                                                                     |
| PX20            | The sphere census                                 | Step 9's one-to-two-day run exists                                                                                           |
| PX21            | The verdict tables as a script                    | Enough verdicts exist to tabulate; until then each verdict record is written by hand                                         |
| PP-FACE, PP-JAC | Face-flux replay; tag Jacobian blocks             | PX7's structural or filter branch                                                                                            |
| PP-SRCOFF       | Sources off for region tags                       | A regime with sinks needs a region reference                                                                                 |

**Considered and dropped while this page was designed**, so that nobody
derives them again:

  - W40's part 3 against part 2b as a test of the inequality: part 3 is a net
    first-order sum, so the ratios test nothing. PX2 would give the realized
    value.
  - Placement pairs at site 26 (water and energy), site 23 (energy) and on TRMM
    0M: the placed quantity is at rounding there (W36, E81, W28), so their
    outcome is fixed in advance. PX3 uses W24 against W28 instead.
  - A donor-cell replay as the linear truth: E66 shows that it measures the
    mixing convention, mixed with its own residual. It stays only as a
    conditional comparison member (PP-FACE).
  - The passive tracer as the surface truth: it has its own surface convention.
    It is used only with a level-1 check (PX13).
  - Split duplicate tags with the same footprint: they stay proportional, so
    they test homogeneity only. The column test `evap_upper + evap_lower = evap`
    has the same weakness, since both sub-tags are fed in the lowest cell. A
    band partition (PP-BAND) is needed for superposition.
  - First-order tracer twins on 1M columns: `tracer_upwinding` also moves the
    1M species, so the parent changes. Tracer-mode twins run only on 0M cases,
    with parity checked.
  - Copies at four Newton iterations on D4-W: `w4_d4w_copies_n4` already failed
    at 0.28% a day.

### 7.3 Designs of the deferred items

Kept so that a trigger does not start from nothing. Each is re-read, and its
rule committed, before it runs.

**PX2. The leak rule, realized with feedback.** [R] Tests PT3 and PT1.

  - Runs: `w25i_d4w_default_z30_c` (W38, tree `705c8ed0`) against
    `wp4c_corr_d4w_default` (W45, tree `90f32566`, run with
    `REFERENCE_OUTPUT=1`). The gate's case A has the same configuration under
    its own job id, but its reference wrote no hourly output. Both runs are
    bit for bit with `w25i_d4w_untagged_z30_c` (W38's R1; W45's criterion 3).
    The probe runs have no manifest, so confirm from the trees' diffs that only
    the correction differs. For the copies: `w25i_d4w_copies_z30_c` to 12 h
    against V2.
  - Metric: per-tag L1 and L∞ at 2, 6, 12 and 24 h (startup ends at 1.83 h),
    with a map by level. The gate's first-order part 3 exists only as `D` at
    24 h, accumulated from the first step. Earlier times need the gate probe
    rerun with `D` written hourly.
  - Reference: the other closing rule (ψ against the follower's donor shares).
    It shares everything else, so it gives an observed spread, not truth.
  - Rules:
      + (a) The realized difference over the first-order one, at 2 h and 24 h,
        is reported, not scored. It mixes feedback with W45's finding that the
        correction does not take the follower's share, so it tests neither the
        inequality nor whether the parents are the same.
      + (b) Suppose OD11 lists ψ as admissible. If the realized `tropo`
        difference exceeds 2% L1 or 5% L∞, `tropo` on D4-W is
        convention-sensitive for the leak.
  - Code: none for the full runs; the hourly `D` needs a rerun of the gate
    probe. Hours.

**PX3. The placement pair.** [R] Tests PT6 and the water side of OD7.

  - Runs: W24 (`|m|`) against W28 (same sign, #102 at `5bfa7cea`): D4-W, 24 h,
    one Newton iteration, 37 fields bit for bit (W28).
  - Metric: per-tag L1 and L∞, hourly. The prior cap is near 0.50%, 0.82% and
    0.83%.
  - Rule: at most 0.5% L1 and 1.25% L∞ means placement does not matter for
    water composition on D4-W, so OD7 can be decided on closure and slope.
    Above that, OD7 carries an observed spread. For `tropo` the L1 part is
    decided in advance by the cap (0.50%); only its L∞ and the `strat` and
    `evap` rows discriminate.
  - Code: none. Hours.

**PX4. Invariants on existing output.** [R] Tests PT7 (Fid-1, in part).

  - Runs: W38's 12 tagged `w25i_*` runs (hourly), W45's V1 (hourly), and
    W40's final profiles.
  - Metrics: `r = ρq_evap_tropo / (m_t ρq_evap) − 1`, where `m_t` is the
    `tropo` mask's value in the cell where `evap` is fed; the same for `strat`;
    and `evap_tropo + evap_strat − evap`, each classified against the logged
    bound and fix events. Overlay at most parent, per cell. The audit's
    `overclaimed` and `orphaned`. Source at most production, from hourly
    estimates (only violations beyond the estimate's error count).
  - Rule: `abs(r)` at most 1e-10 except at logged events. A departure with no
    logged event blocks any Fid-1 claim until the rule is located.
  - Code: none. Hours.

**PX5. Why the copies are ineligible on D4-W.** [R] Tests PT10.

  - Data: the copies' ledgers of W25 and W38 (the filter's gross against the
    repair's gross, by level and hour, at `dt` 120, 60 and 30 s); W21 at one
    and ten iterations; `w4_d4w_copies_n4`; site 26's copies from the committed
    CSVs.
  - Rules: a filter share of at least 0.7 that grows by at least 1.5 times per
    halving means a per-step cause. The only D4-W routes are then a copies-only
    draft PR, or the air twin with PP-TRACER (PX17). Otherwise record "no
    eligible D4-like comparator at production cost".
  - Site 26's copies fail the repair row. Their cumulative repair is 33% of the
    water over 90 days, about 0.37% a day against 0.20%
    (`copy_repair_relative` in
    `output/long_runs/lr_s26_copies/water_tag_audit.csv`). That was read for
    this page and is not yet on the record; PX5 enters it. Their own residual
    is 2.3e-7 and passes. The run's grid-mean closure is 6.3e-4 (W36), and
    OD12 decides which counts. So W36's 2% to 13% is agreement with an
    ineligible comparator.
  - Code: none.

**PX6. The missing-channel inventory.** [R] Tests PT8 and PT1.

  - For every rule of section 4, list the per-tag account that exists and in
    which tree. This fixes the scope of the probe accounting.
  - Read the option C miss probe (job `13987196`) when it lands. Any rise with
    no operator share of at least 0.5 blocks Fid-2 at site 23.
  - Tabulate the closure change against the per-tag difference for every
    same-parent pair of closing rules (PT1).
  - Code: none.

**PX9. The propagation probe.** [K] Tests PT5. It samples `K̂` and can close
the L∞ route; it cannot certify either.

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
  - Metrics: the column sums `‖e‖₁ / ‖δ‖₁` (so `sup K̂`), the positivity index
    `‖e_tropo⁻‖₁ / ‖e_tropo⁺‖₁`, and linearity.
  - Rules: the screen uses the measured `sup K̂`, and never less than 1.
    `K̂ > 1` is located by on/off trials. A positivity index above zero closes
    the L∞ route for the case. Stated before the run: `K̂ ≤ 1`, positivity
    index above zero.
  - Code: none. Three to six jobs.

**PX10. The energy repair on the full tag set.** [K] Tests PT11.

  - Case: `g411x_d4_default` with `energy_source_tag_repair` true and false,
    `e_src_fixgross_*` added to the output (config only), 24 h, parity against
    the untagged twin, at the fixed `c`. E85's pair has 4 tags (`strat`,
    `tropo`, `sfc`, `rad`) and no gross, so it is prior evidence for those four
    only, not for `sub` or `new_strat`.
  - Metrics: the per-tag realized difference at 1, 6 and 24 h in OD4's units;
    `fixgross` as the repair's screen term (factor 2); where it acts relative
    to 750 m.
  - Rule: `sub` or `new_strat` above 2% L1 means the repair is material for
    energy at that `c`. The repair on and off are not both admissible physics,
    so this is a sensitivity, not an observed spread. This informs the owner's
    point 2 of G4.3 to G4.6.
  - Code: none. Two D4 jobs.

**PX12. TRMM 0M comparator eligibility on current code.** [K] A second
benchmark, for the sub-grid rules. W21's TRMM runs predate WP6 and the current
copies, so new runs are needed: default, copies and untagged; `dt` 150 and
75 s; two and ten Newton iterations; one P1 probe for the parent's error. OD12
fixes which "own residual" counts: the updraft copies' 7.1e-7 (W21) or the
grid mean's 5.0e-4 (W28). It needs a measured parent error of at most 1e-3 at
its Newton count, one P1 probe per rung. If the copies are eligible, `pbl`,
`free` and `evap` are scored in OD2's windows. That validates the SGS share,
the exchange and the 0M rain-out where they are active, for the code tested.

**PX13. The surface-excess comparison.** [K] Tests PT13 and answers W21's
surface rule.

  - Case: `w25i_d4w_pulse_{default,copies}_z60_c` and `_z30_c`, 3 h, output
    every 10 min, with the level-1 updraft fields. A driver sets
    `ρq_gas_A = ρq_tot` (so `q_gas_A = q_tot`) and its updraft copy `q_totʲ`,
    with its own untagged twin.
  - The candidate `evap* = ρq_tot − T1` counts only if (a) at level 1,
    `abs(T1ʲ − T̄1)` is at most a quarter of the budget relative to the `evap`
    share, and (b) the contamination from the tracer's missing subsidence and
    from rain over the lowest 300 m in the first hour is at most a quarter of
    the budget (a floor near 4e-4 of `q_tot`).
  - Score `evap` only. The `sfc` tag, 10 m wide against 25 m cells (z60) and
    50 m cells (z30), is ill-conditioned.
  - The observed spread is among the grid-mean start, the relaxation and zero
    credit.
  - Rule: a spread above 10% means first-hour `evap` is convention-sensitive,
    and the claim is narrowed. The pathway proposes PP-SFC to the owner if (a)
    and (b) pass and it lies nearer `evap*`. The owner may decide W21's surface
    rule earlier.
  - Code: none. About twelve short jobs.

**PX14. WP4b's pool and the sedimentation reset, replayed.** [K] Tests PT12.
After #121's review.

  - Case: #121's tree, `PrecipitatingColumn`'s rain-out window only, the key
    on. The window is read from the untagged run before the replay; it is not
    yet measured (W43 ran 300 s).
  - Method: from each state take `water_tag_1m_flows` as frozen rates. Solve
    each tag's three-compartment label equation with 1, 4, 16 and 64 sub-steps;
    one sub-step reproduces W43's failing start rule. Apply the pool rule. In
    the same harness, apply the per-level reset without the key against the
    key's rain parts. That isolates the reset without the pool as a confound.
  - Rules: a process-weighted `|φ_pool − φ₆₄|` of at most 0.05 and rain-part L1
    of at most 2% make the pool Fid-3 within the replay. Otherwise the owner
    decides with the measured spread. A reset error above G3_PLAN 6.1's 10%
    precipitation budget means WP4b's stage 2 (EDMF) comes before any
    precipitation claim in the production envelope.
  - Code: none. Under an hour per case.

**PX15. The energy follower's split.** [K] After PX7. Port
`wp4c_diag_probe.jl` to `enthalpy_increment` on `g411x_d4_default`, at the
fixed `c`, with PX7's ladder and rule. This frames OD7 and G4.7.

**PX17 (PP-TRACER). A subsided passive tracer.** [P] It makes the air twin
valid on D4-W, RICO, BOMEX and the GCM columns, and checks PP-SUB
independently. On D4-W score the `up` or `strat` tag, with a contamination
bound for rain formed at cloud top in the `strat` region, where the tracer
loses no water.

**PX18 (PP-BAND). A band region.** [P] Tests PT7. D4-W `z30_c` with a fine
partition (below 400 m, 400 to 750 m, above 750 m) and a coarse one (`tropo`,
`strat`), a run with the tags in reverse order, and the three-tag hull test
(ATTRIBUTION_PATH's V8), plus the untagged twin. Metric: the relative L∞ of the
members' sum minus the group at 24 h, against OD3's 1e-10, mapped against bound
activation and the repair's gross. Rule: departures only where θ binds or the
repair acts support PT7. The aggregation row stays reported unless the owner
decides otherwise.

**PX19. The flush rate.** [K] Tests PT14; before step 9's 90-day run. Rerun
`lr_s26_samesign` to day 10, saving the state. Edit the restart in Julia with
`d4w_driver.jl`'s pattern: move 1e-3 of the water from `pbl` to `free` between
500 and 900 m, changing only `Y.c.ρq_tag_*`. Restart the edited and unedited
states to day 90 with `reproducible_restart`, and compare the edited run with
the unedited one only (E54, E58). The loss rate is precipitation plus
large-scale drying plus nudging, from the `:external_forcing` records, over
`∫ρq_tot`. Rule: a decay rate within 30% of the loss rate suggests that the
long-run screen saturates at the exposure rate divided by the loss rate. One
edit at one site is a sample, not a bound.

**PX20. The sphere census.** [R] Inside step 9's one-to-two-day run, with no
extra run. The invariants and the exposure screens on the sphere: the rescale,
borrowing, the hyperdiffusion leaks, the sedimentation reset, and WR20. Van Leer
per field and the follower's label diffusion can only be screened here. Any
rule above the exploratory materiality gets its observed spread before the
90-day run.

**PX21. The verdict tables.** A script,
`analysis/evidence/provenance_verdict.py`, extending `closure_verdict.py`. For
each case, tag and window it writes the verdict record of section 2: the
fidelity level, the observed spread, the exposure screen, the verdict per rule
and the rules left uncovered.

## 8. Probe PRs

Only PP-SUB is on the gated path, and only if PX8 finds subsidence material. The
others wait for the triggers of section 7.2. Each would be diagnostic only: off
by default, the parent bit for bit, a unit test, a parity job against an
untagged twin, and a draft PR that only the owner merges. OD13 approves them.

  - **PP-SUB, per-tag subsidence.** A key
    `water_tag_subsidence: bracket | per_tag` for `LargeScaleSubsidence` and
    the GCM forcing's subsidence. It must define two overlay cases: overlays
    that list subsidence (then `fcg` changes meaning) and overlays that do not
    (then `evap` is carried faithfully instead of losing by share). Its unit
    test checks that the per-tag tendencies sum to the parent's.
  - **Deferred:**
      + PP-TRACER, a subsided passive tracer: a key that applies `subsidence!`
        to `q_gas_A` as well. The tracer feeds back into nothing, so every
        other field stays bit for bit.
      + PP-BAND, a band region: a region type `tanh_altitude_band`, with a
        region struct, its `region_mask`, the parser branch and
        `tag_region_spec`, and no tendency code. Today's types are
        `everywhere`, `tanh_altitude`, `tanh_latitude`, `tanh_box` and
        `tanh_polygon`.
      + PP-SFC, a surface rule that composes the flux, after PX13.
      + PP-FACE, face-flux output for a replay, after PX7's structural branch.
        It is labelled a convention reference (E66), never truth.
      + PP-JAC, tag Jacobian blocks for the bracket loss and the SGS flux,
        after PX7's filter branch.
      + PP-SRCOFF, sources off for region tags, only if a regime with sinks
        needs a region reference (Soares does not).
  - State ledgers per process and tag are not proposed. Probe accounting
    replaces them, because build time grows with the number of fields.

## 9. Decisions for the owner

These enter the register in [ROADMAP.md](ROADMAP.md) as proposals. Each
becomes an open "OWNER DECISION REQUIRED" row when the owner accepts it. No
agent fills one in. The panel that designed this page proposed eight; they are
merged into six to spare the owner's time. They were revised after the owner's
review (section 0).

  - **OD9. The evidence labels.** Adopt the two axes as reporting labels: the
    fidelity levels, "observed spread", "exposure screen", "validated for named
    rules" in the restricted sense of section 2, and "held out". They are
    reported beside rev. 2's verdicts, with the verdict record. They change no
    OD3 threshold and do not amend OD5. The aggregation row stays reported.
    Needed before any label is reported.
  - **OD10. The screen arithmetic.** Gross, not net; the exact form for
    bracketed transport; `K̂` from spike arms if PX9 runs, else `K̂ = 1`, said
    each time; a screen is never a bound. The exploratory numbers under their
    own heading in ROADMAP only decide what to propose next; they are not
    thresholds. Needed before any Val-2 label is reported.
  - **OD11. The rule classification, and the fixed energy convention.** The
    claim contracts (G3 criterion 12, G4.3) adopt section 4's classes before
    any spread or screen is used in a label. They list the admissible
    alternatives, including whether ψ is admissible for the leak. For energy
    they fix `c` (110,495 J/kg unless the owner names another) and the source
    convention for the conditional tests. Needed before PX22 is scored, and
    before any Val-1, Val-2 or convention-sensitive label.
  - **OD12. Reference validity.** A reference validates only rules that are
    active in the case and that it does not share. The excluded processes are
    measured inactive. Its floors (surface, initialization, parent error,
    contamination) are each at most a quarter of the budget. Copies validate
    sub-grid rules only. The air twin validates transport rules only in windows
    without sinks, subsidence or sedimentation. A proposed reading of the
    Newton row: separate runs whose parents are bit for bit the same untagged
    twin count as same-parent, since the parent's error cancels exactly (the
    owner's revision of 2026-09-25). Arms that solve their own transport stay
    gated unless the parent's error is at most 1e-3. These arms are the copies,
    tracer mode and a passive tracer. Needed before PX11 is scored.
  - **OD13. The probe PRs.** PP-SUB only, and only after PX8 finds subsidence
    material. The others are deferred with their triggers. Probe accounting
    instead of new state ledgers. Needed before PX16.
  - **OD14. Held-out hygiene.** Name one held-out case, its window and its
    metrics, before any rule is tuned on PX11's result. The case needs a
    reference that is valid there (PX23). Soares, TRMM 0M and sites 23 and 26
    are development cases. The owner stated on 2026-09-26 that criterion 8's
    GCM-driven column, which starts from site 23, does not count as held out
    for a rule developed using site 23. Until an independent case and its
    reference are fixed, Val-4 is not assessable. A held-out case is never
    used to develop a rule. Needed before PX23 and before step 8b.

## 10. Sequencing, and what G4 takes

The gates map onto the proposed steps of ROADMAP's execution order.

 1. **Step 1b, gate A.** This page, the in-place edits, OD9 to OD14, PX0. No
    runs, no code. Scripts pass fault injection first.
 2. **Step 2a, gate B's screen.** PX1, with no run. Whatever it finds, the
    pathway proposes PX8 (step 6b); a low PX1 is not assessable, not a reason
    to stop. If PX8 is material, it proposes PP-SUB with PX16 (step 7b, after
    OD13).
 3. **Step 6a, gate C.** PX7.
 4. **Step 6c, gate D.** PX24 and PX11, then PX23 once OD14 names an
    independent case with a valid reference. Until then Val-4 is not
    assessable.
 5. **Step 10a, gate E.** PX22, for G4, beside the water gates.
 6. **Deferred items** run only when their trigger fires (section 7.2).
    Step 8b selects a default under rev. 2's rules as approved, with the
    verdict records beside it.

If a gate reports *not assessable*, no later gate takes its result as input.

**Hypotheses, stated before any run.** None of these is evidence. The gates
test them.

  - PT2's reasoned estimate suggests that subsidence is material near 750 m
    on D4-W. PX8 runs either way.
  - The follower's part 2b alone puts the exposure screen for `tropo` on D4-W
    above the 2% row. So `tropo` on D4-W will probably not reach Val-2. It
    would then need PX16 and PX7, or a narrower claim.
  - Soares is the most likely first case in which named transport rules reach
    Val-3.
  - At the fixed `c`, energy's budget identities probably hold per tag, as
    E87's column identities did. `C4` probably stays unresolved per tag, a
    limitation.

**What G4 takes from G3.**

  - The evidence labels, OD9 to OD14, and the rule classes, with every energy
    level conditional on the fixed `c` and source convention.
  - PX7's split method, which PX15 would port (deferred).
  - PX8's subsidence size at the same 750 m split of DYCOMS RF02, if PX8 runs.
    It sizes the `sub` tag and the region tags. The parent subsides `h_tot`, so
    energy has no faithful per-tag counterpart, and the `sub` tag's subsidence
    stays a convention.
  - PX11's verdict, only for the kernels the two families truly share. Check
    `ShareDifferences`, `_blend_factor`, `_plume_step` and the follower's
    left-out weight in the code before inheriting it.

Energy's own gate is PX22. PX10, PX13's surface verdict for the energy copies'
relaxation (ER9) and PX3 for OD7 are deferred. The committed process budget
gives `C4`'s size from the `c`/2`c` pair: `c·M_U` is −1.15e5 J/m² a day, 0.55%
of the throughput (E87, `output/g46/process_budget.txt`). The records' estimate
printed beside it (+1.06e4 J/m²) has the opposite sign, and E87 concludes that
the records do not bracket it. Only a per-tag bottom-face outflow probe would
tell where `C4` goes. Until a measured result needs one, `C4` is a limitation
listed with every energy verdict.

## 11. Risks and open questions

  - **The screen may exceed the row on D4-W whatever is done.** The follower's
    part 2b alone for `tropo` is about 7.2%, and subsidence may be tens of
    percent a day. Evidence would then come only from turning rules into
    faithful ones (PP-SUB, WP4b under EDMF, tags solved consistently with the
    parent's Newton step), or from Val-3 for named rules in clean regimes. The
    owner should know this before the runs.
  - **Screens can mislead both ways.** A screen below the row misses rules not
    on the list and states not sampled. A screen above it does not show an
    error. Neither is reported as a bound.
  - **The labelling model is a convention at the sub-grid scale.** Val-3
    validates the code against the declared model, not against molecular
    truth.
  - **A faithful rule helps only if its operator is monotone.** Centred
    reconstructions per tag can raise `K`. Advective subsidence can expand on
    GCM columns.
  - **Is ψ admissible for the leak?** If yes, W40's first-order estimate
    already suggests that `tropo` is convention-sensitive on D4-W, unless PX2
    shows that feedback flushes it (OD11).
  - **First-order estimates against realized runs.** Adopting a rule always
    needs a prognostic arm (PX2, PX16). PX2's ratio to part 3 is confounded by
    W45, so it is reported and not scored.
  - **References carry their own conventions.** The passive tracer's zero
    surface credit and missing subsidence (PP-TRACER fixes the second), the
    shared updraft filter, the floors, and cloud-top rain in D4-W's `strat`
    region. Each needs its floors checked, or agreement will be over-read
    again.
  - **Run trees.** The per-tag ledgers, the leak-correction key, the placement
    variants and option C sit in separate trees. Every comparison names its
    tree.
  - **`PrecipitatingColumn` is a short spin-down, and WP4b is refused under
    EDMF.** WP4b's fidelity is measured only in the rain-out window until its
    stage 2.
  - **Classification gaming.** OD11 is fixed before any spread or screen is
    reported, and does not change after a run.
  - **Aggregation departs by construction where θ or the repair acts.** The
    row stays reported. No agent redefines it.
  - **The L∞ rows** (5% and 25%) have no route without a comparator, unless
    positivity is shown for the operators of a case.
  - **Data durability.** Every [R] item depends on scratch until PX0 is done.
  - **The owner's bandwidth.** Six proposed decisions, OD7, and at most one
    probe PR on the gated path.
  - **Multiple testing.** Only pre-registered decision rules count. Everything
    else is reported.
  - **Two meanings of provenance.** "Tag provenance" is this page's subject.
    "Run provenance" is `provenance.txt` and M0. Say which.

## 12. Edits made elsewhere

Each edit is in place and marked. Prose carries "*Scope added (provenance
pathway, 2026-09-26)*". Table cells carry "Proposed 2026-09-26 (provenance
pathway)" or a dated italic note that names the pathway. Nothing the owner
approved is struck. The edits were revised with this page after the owner's
review.

  - [ROADMAP.md](ROADMAP.md): a fourth aim; M2, M3 and M5 notes; notes on the
    Provenance, Comparator-eligibility, Convergence and Aggregation rows; five
    proposed rows and four rules under the contract; OD9 to OD14 in the
    register as proposals, with notes on OD5 and OD7; the E66 note beside the
    approved 24 h row; the exploratory numbers under their own heading after
    the OD3 section; new steps 1b, 2a, 6a to 6c, 7b, 8c and 10a, and notes on
    steps 4, 6, 7, 8b, 9 and 10 and on the milestone table's sphere row.
  - [G3_PLAN.md](G3_PLAN.md): a pointer in the header; §2 (criteria 5, 7, 8 and
    12 on the evidence levels); §3 (subsidence is followed only through the
    local bracket); §4.1, §4.2, §4.3 and §4.5; §6 (D4-W subsides; the rows
    V-P0 to V-P3); §6.1 (the E66 sentence, replaced at the owner's request);
    §8; §9.
  - [G3_TODO.md](G3_TODO.md): OD9 to OD14 under Decisions; a new section
    "Provenance pathway" with the gated items, the deferred items and the probe
    PRs; pointers in WP3, WP4c, WP5b-P, WP5b-C, WP4b, WP9 and the sphere.
  - [G4_TODO.md](G4_TODO.md): the pathway note; G4.1, G4.3, G4.6, G4.7 (with a
    remark on G4.8's pulse), G4.9, G4.10, G4.12 and G4.15; a new item for
    energy subsidence among the energy items that no G4.n takes up.
  - [STATUS.md](STATUS.md): a dated update, a note under the open decisions and
    a row in "Where to look". [DECISIONS.md](DECISIONS.md): a pointer.
  - [FINDINGS.md](FINDINGS.md): one dated annotation on E66, after the
    owner's review. Its reference keeps its own residual, so its difference is
    not a pure convention effect. No new result is entered.
