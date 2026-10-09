# Challenge of the owner's decisions (2026-10-09)

Read: `DECISIONS.md` in full, on `claude/plan-rev2` at `b0cbda29` (PR #161
merged). Each challenge was checked against the record it cites at the same
head, and then fact-checked by a second agent that had not written it. No run
was made and no other file was changed.

PR #162 (`9e515532`) added four Part 8 decisions of 2026-10-09 after this was
read. None changes a challenge below. The third supports point 1: no
reference of parts 6 and 7 is eligible on TRMM 0M, and if PX12 finds the
copies ineligible, the first-hour origin terms stay unranked.

The challenge of 2026-10-07 (`plan_parts_1_to_3_review_2026-10-07.md`) is not
repeated. Where a point builds on one of its items, it names the item and adds
only what is new.

Strength: **breaks** means the decision contradicts its own record or rule.
**Weakens** means it holds but rests on less than it claims.

## Summary

| #  | Decision                                                      | Strength | What would fix it                                                                                  |
|:-- |:------------------------------------------------------------- |:-------- |:-------------------------------------------------------------------------------------------------- |
| 1  | Option D and WA-SCOPE's cases (2026-10-02, 2026-10-08)        | weakens  | A precipitating 1M development case with a candidate reference, and a reference for RICO.          |
| 2  | OD3's 2× at 8 + 8 gates part 10 (2026-10-07)                  | weakens  | State part 10's scope without rain and snow tags, and take the 8 + 8 measurement out of 11b.       |
| 3  | OD7 stays deferred until site 23 is rerun (2026-10-07)        | breaks   | Decide OD7 for energy now, from E81.                                                               |
| 4  | W49's V2 counts as option C's validation (2026-10-01)         | weakens  | Rerun option C's V1 to V5 on post-#139 `main` before the 90-day sphere.                            |
| 5  | Criterion 9's rounding floor (2026-10-02)                     | weakens  | Write the floor's authorized step count into the decision before 12a.                              |
| 6  | Inapplicable completeness flags are true (2026-10-08)         | weakens  | Make the flag three-valued, and have the scorer check the basis.                                   |
| 7  | Each energy test states its `c` (2026-10-07)                  | weakens  | A claim whose `c`/`2c` spread exceeds its tolerance is reported, not qualified.                    |
| 8  | The missing tolerances are deferred (2026-10-07)              | weakens  | A use-derived tolerance as a condition of level 4.                                                 |
| 9  | The design hash shows integrity only (2026-10-08)             | weakens  | Make W62's push-time check the standard.                                                           |
| 10 | Record consistency                                            | breaks   | Mark stale and session-scoped entries, reword the GPU entry, copy memory-only decisions in.        |

## 1. No precipitating 1M case can develop per-tag accuracy, and the held-out case has no reference

**The decisions.** Option D (2026-10-02): criteria 5 and 6 are not judged on
D4-W. Per-tag accuracy moves to TRMM 0M, once PX12 confirms its copies, and to
the Soares air twin (PX11). WA-SCOPE (2026-10-08): the 24 h development case
is the GCM-driven column, and RICO 1M, 24 h, is held out.

Option D narrowed the claim on purpose, and that stands. The gap is in what
remains. OD1's production configuration uses 1M, and G3 puts precipitation
provenance in scope. These are the cases that can judge per-tag accuracy:

| Case                | Microphysics             | Per-tag accuracy                                                                    |
|:------------------- |:------------------------ |:----------------------------------------------------------------------------------- |
| D4-W                | 1M, precipitating        | Excluded by option D.                                                               |
| TRMM pilot          | 0M                       | Only if PX12 finds its copies eligible.                                             |
| Soares air twin     | 1M, sedimentation absent | Transport rules only. PX11 requires sedimentation measured inactive (OD12).         |
| GCM-driven column   | 0M                       | Development. It subsides, and its copies' eligibility is not assessed (W36).        |
| PrecipitatingColumn | 1M, no EDMF              | Arithmetic rows PT15 and PT16 only (2026-10-09).                                    |
| RICO 1M 24 h        | 1M, precipitating        | Held out. No retuning on it.                                                        |

No development case tests a precipitating 1M origin against a reference. The
first such score would be on the held-out case, where a failure cannot be
fixed without spending it.

And the held-out case has no established reference either. PX23 states that
criterion 8's columns do not qualify for the air twin: "RICO and BOMEX set
`subsidence_forcing`". So RICO needs eligible copies (PX12-style) or PP-TRACER
(PX17). Until one exists, PX23 is not assessable. Level 4 asks for "the
applicable held-out evidence". OD8 removed the aggregation bridge, so nothing
else stands behind the copies.

**Proposal.** TRMM 1M already has configurations (W33, W35,
`configs/w5v_trmm1m_*`) and an approved OD2 row ("TRMM_LBA 0M and 1M, 6 h").
Extend PX12's eligibility check to TRMM 1M, so that one precipitating 1M case
can develop. Decide now which reference RICO will use, and what part 10 claims
if none becomes eligible.

## 2. The cost gate cannot be assessed for the production configuration

**The decision** (2026-10-07): OD3's 2× at 8 + 8 stays and gates part 10.
Criterion 10 fails at 4.16× until the walk fix lands upstream.

Already raised on 2026-10-07 (147-4a): a perfect walk fix leaves the halves at
1.97× to 2.02×, and W52's water half has no rain or snow parts. New here:

  - **The rain and snow tags cannot be built in production's configuration
    yet.** They are refused under EDMF until WP4b's stage 2 (W60,
    `design/WP9_COST.md`). Rain and snow with modes "counts as not buildable
    at `43b01ca1`" (2026-09-29/30). Criterion 10 asks for the cost "with the
    rain and snow tags". So the configuration the 2× is meant for cannot be
    measured before stage 2, and a pass at 8 + 8 would be a pass without the
    tags G3's scope requires.
  - **Part 10 waits for an energy part.** "The 8 + 8 cost is measured in
    11b", and 11b starts after part 9 and the walk fix. The decision keeps
    "water first to qualification" as "otherwise unchanged". The exception
    deserves to be explicit: water's qualification now waits for one
    measurement scheduled inside the energy baseline.

**Proposal.** Say in the decision that part 10's cost verdict covers 8 + 8
without rain and snow tags, and that criterion 10's rain and snow measurement
stays open until stage 2. Schedule the post-fix 8 + 8 measurement as its own
step before part 10, not inside 11b.

## 3. OD7's deferral does not apply to energy

**The decision** (2026-10-07): OD7 stays deferred, with no lean, until the
post-#139 site-23 long runs are scored. The register says OD7 is "to be
decided by the registered rule".

**Why it breaks.** The registered rule has already given its energy verdict.
E81 records the energy long runs of W36:

| Site, last check | Same sign gross | `|m|` gross | Slopes (same sign, `|m|`) | Moved, both rules |
|:---------------- | ---------------:| -----------:|:------------------------- | -----------------:|
| 26, day 90       | 7.3e-12         | 2.7e-13     | 0.76, 0.65                | 1.28              |
| 23, day 74.25    | 7.6e-12         | 1.6e-12     | 0.67, 0.46                | 0.48              |

E81 applies section 5 and concludes "the rule keeps same sign for energy" at
both sites. Section 5 allows a run that stopped to count up to where it
stopped. The deferral waited for site 23 to be scorable. That was a water
problem: E81 records that "the energy tags did not end any run" and stayed
closed at site 23.

A rerun on post-#139 physics is very unlikely to change this verdict. Both
gross residuals are at rounding level. E81 divides by `∫(ρe_tot + cρ)`, and
Θx is smaller than that. Even so, OD3's 0.2% of Θx (decided on 2026-10-08)
would bind only if Θx were below about 4e-9 of that total (7.6e-12 / 2e-3). E81 also says the
rule separates roundoff residuals, and the moved ledger is the same under both
rules (as E79 found on D4). The copies are not an eligible comparator for
energy there (E81), so the tie-break cannot be used.

So waiting buys no information, while OD7 blocks G4.7, G4.8 and the energy
default.

**Proposal.** Decide OD7 for energy now. Either accept the registered verdict
(same sign, E81), or, since the rule cannot separate the placements, choose on
cost and simplicity and record why. If placement accuracy matters, it needs an
energy reference that shows where a column total should land. That belongs to
part 11a, not to the long runs.

## 4. Option C's validation is prior evidence, and its rule raised intervention

**The decision** (2026-10-01): W49's V2 counts as C's validation. V5's
`led_fix` failure at site 23 stays open. #137 merges.

  - **W49 is prior evidence.** It ran at `0eb329b2`, before #139. By the rule
    of 2026-10-02, numbers on the old physics count as prior evidence only.
  - **The rule raised intervention.** V5's `led_fix` reads 7.33% (`pbl`) and
    6.52% (`free`) against 2%. `main`'s control also fails, at 2.73% and
    2.27%, so the revision multiplies an existing failure by 2.7 to 2.9. W53
    shows the revision's rule makes all of the rise (P1, `f = 1.0000`). The
    extra repair mostly raises `free` from below zero and takes the water
    from `pbl`, so it moves water between labels. Why the follower drains
    `free` is not yet shown, and the owner ordered that probe on 2026-10-02.
  - **What rests on it.** Part 12d gates the sphere pilot on "the
    negative-parent fix, merged as #137". Every site where the parent's water
    goes negative runs the revision's rule (`TargetGain()` is the default).

The decision keeps V5 as an open failure, which is right. The word
"validation" claims more: one row of five passed, on old physics.

**Proposal.** Call W49 "V2 passed on pre-#139 physics". Before the 90-day
sphere, rerun V1 to V5 on post-#139 `main`. Let the W53 follow-up decide
between the revision's rule and the parent's gain before that run, not after.

## 5. The rounding floor's authorized range is not written down

**The decision** (2026-10-02): a Float32 measure passes if it is at most
`max(10 × Float64, 3 · eps32 · √n_steps)`.

The record already notes that a longer run needs its own check (W60 addendum,
W62). The decision does not say so. G3_PLAN 6.1.4 preserves the rule "with the
existing accumulated measure and its actual step count", and part 12a uses it
"only as authorized" without naming what is authorized. The kept sphere
configuration is Float32, so 12a is where this is read.

At OD1's 20 s step, the rule gives:

| Run, at 20 s  | `n_steps` | floor   |
|:------------- | ---------:| -------:|
| 1 day         | 4,320     | 2.35e-5 |
| 10 days       | 43,200    | 7.43e-5 |
| 90 days (OD6) | 388,800   | 2.23e-4 |

At 90 days the floor is above OD6's absolute ceiling for the gross residual,
2e-4 of the partition. A Float32 allowance as large as the acceptance ceiling
no longer measures sensitivity to precision. W62 also found one measure,
`q_tag_inc_left`, growing faster than `√n` (0.28, 0.33 and 0.45 of the floor
at 3, 12 and 24 h), so its margin shrinks with run length.

**Proposal.** Add one line to the decision: the floor is authorized for the
D4-W day at 120 s. Part 12a registers its own Float32 rule, from measured
growth, before its runs.

## 6. Self-declared eligibility cannot tell "inapplicable" from "unchecked"

**The decisions** (2026-10-07, 2026-10-08): eligibility may be declared in an
evidence file. A condition a reference does not have is declared complete,
with the basis "inapplicable". The eligibility rows are read from that file
whatever the parity state.

The manifest names and hashes the producing script, which is good. But the
scorer reads `true` and never reads the basis
(`analysis/evidence/score_acceptance.py`, near line 550). A source mirror
that was never checked and one that does not exist look the same to it.

**Proposal.** Make each flag three-valued: complete, incomplete,
inapplicable. Have the scorer check the basis where it can. For example,
"mirrors inapplicable" requires a configuration without EDMF, which the
manifest records. Report inapplicable flags in their own column.

## 7. A convention spread larger than the tolerance is the whole claim

**The decision** (2026-10-07): OD9 to OD11 stay proposed, and each
pre-registration states its `c`.

Every energy conclusion already carries the `c`/`2c` spread as a limitation
(G4.10, added 2026-09-26). But the decision records spreads of 1.7% for Θx and
up to 177% for E71's region tags. Against a per-tag tolerance of 2% L1, a
177% spread is not a limitation of the claim. It is the claim.

**Proposal.** A per-tag energy claim whose `c`/`2c` spread exceeds its own
tolerance is reported as convention-defined and cannot reach level 3 or 4.
This needs no choice of `c`.

## 8. "Qualified" needs a use

**The decisions** (2026-10-07): the missing tolerances are deferred, and
EA-ACCURACY lapses with EA-USE.

Raised before as O6 (part 2 should state the workflow's user and reason) and
149-5 (energy names no user). The decisions deferred both. G3_PLAN 6.1.4 says
of the per-tag rows: "Whether these errors are adequate for the intended
origin inference is unestablished." Those rows are G1's criterion 4, set on
2026-09-20 and declared met the same day. As things stand, level 4 would
certify that 2% L1 at 24 h is met, without saying what 2% is good enough for.

**Proposal.** Make a stated use, and the tolerance derived from it, a
condition of level 4, so part 10 cannot close without one. For example: the
share of the 24 h column water that entered through the boundary layer, to a
stated accuracy. If the inherited 2% is tighter, it stays. If it is looser,
the use is not supported.

## 9. Pre-registration can show precedence

**The decision** (2026-10-08): a fixture's design hash proves integrity only,
and no "frozen before results" claim is made.

W62's review already showed precedence once: its jobs started 7 to 19 s after
the design commit was pushed. That check is not standard.

**Proposal.** For every deciding run, record the design commit's push time (or
a GitHub release or PR comment naming it, which GitHub timestamps on its
server) and the job's Slurm submit time in RUNS.md. Then "frozen before
results" can be claimed where it is true.

## 10. Record consistency

  - **GPU.** 2026-09-11, "Production is a GPU sphere in Float32", is marked
    in force. ROADMAP says GPU "remain[s] unapproved", and G3 runs the sphere
    on CPU with MPI (2026-09-23). They can be read together, since the GPU
    check "comes last", at M6. Reword the entry so it says that.
  - **Session-scoped entries marked in force.** 2026-09-23: "This session's
    goal is G3's WP0 and WP1 ... the only model code is WP1's"; "This
    session (`ClimaAtmosResiDyn-exp`) runs G3's jobs"; "The job session is
    not reachable through SendMessage". Also the session goal of 2026-09-24
    and the WP3 extension of 2026-09-23. An agent reading the file as
    instructed would take these as binding.
  - **Stale waiting list.** "Option C's revision, after W47. Open." ROADMAP
    records it built, validated and merged on 2026-10-01. "E89 is approved,
    to run after the PR head is final. Waiting for the head." FINDINGS has
    E89. (The 10-07 review raised E89 as F18. It is still there.) The
    2026-10-05 update inside the 2026-10-02 entry still says #146 is
    "waiting", answered on 2026-10-07.
  - **Decisions outside the repository.** Eleven entries cite the owner's
    Claude memory, and the six entries of 2026-09-27 come from it too. A
    reviewer of the repository cannot check them.
  - **Structure.** The two proposal tables still precede the file's own
    introduction (raised as F19 on 2026-10-07).

**Proposal.** Mark the session entries done or superseded. Reword the GPU
entry. Strike the stale waiting items. Copy the memory-only decisions into the
register.

## What held

These were tried and stood: WA-SCOPE's refusal of a three-tag or six-hour
scope; EA-STATE's growth-only scoring with the state reported; the EA-C4
reading of E87; parity blocking the origin rows while the run's own accounting
is still scored; the producer-bound completeness gate; naming the held-out
case before PX11; OD12's quarter rule for floors; keeping OD5's wording, since
the obvious replacement, "screened", would collide with OD9's "exposure
screen".
