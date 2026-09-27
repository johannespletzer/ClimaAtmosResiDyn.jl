# G4.3: claim contracts for the energy source tags, the process records and the parent-budget ledger

Written on 2026-09-25. Three diagnostics report energy, and each can claim a
different thing. This note says what each may claim, which evidence carries
the claim, and which rows of ROADMAP.md's
[acceptance contract](../ROADMAP.md#the-acceptance-contract) apply. It does
not restate the contract or its thresholds (OD3). Where a row applies, the
verdict is *pass*, *fail* or *not assessable*, as the contract says.

## 1. One scale for every energy percentage (OD4)

  - **The scale** is the gross energy the sources put into the tags over the
    window (the register, OD4). A percentage without its scale is not
    reported.
  - **Θx, exact:** the audit's `source_throughput`, the per-step gross of each
    partition tag's source ledger (#115). It exists only with
    `energy_source_tag_ledger_per_tag: true`, which every validation and
    qualification run sets (the owner, 2026-09-24).
  - **Θi, interim:** the process records' `Σ ∫ρ|Δe_prc|` over the output
    intervals and the source processes, without `precipitation`.
  - **Label.** Every percentage names its scale: "of Θx", or "of Θi (an
    estimate)". A value on Θi is not called a bound. On D4 the two scales
    differ by 6%, and which is off is not established (E84;
    [review/od4_restatement.md](../review/od4_restatement.md), section 1). So
    Θx is used wherever a run has it, and a verdict within 10% of its
    threshold on Θi waits for a run with Θx.
  - **Window.** OD2's windows. A window's Θ is the difference of two audit
    rows. A state quantity, such as the gross residual, is taken as its change
    over the window, as `g411_eligibility.py` does, and its value at the
    window's end is reported beside it.
  - **Not this scale:** per-tag L1 and L∞ against a reference (class 3). They
    stay per tag, and each states its offset `c` (E71).

## 2. The energy source tags: stored provenance

**What a tag claims.** `ρe_src_<name>` is the part of the partitioned total
`E = ρe_tot + c·ρ` now in a cell that entered through the tag's labels (or its
region, for a region tag), under the donor-proportional loss rule and the
offset `c`.

**What it does not claim.**

  - Where a process removed energy. The loss takes by share, so a source tag
    holds almost nothing where its own process cools (E22: 7.1e-8 of the cell's
    total where radiation cools most). To see cooling, read the process record.
  - A residence time or an age (G4.14's τ is a loss timescale).
  - That the provenance is right, unless the provenance row passes against an
    eligible comparator. Closure never stands in for it (the contract).
  - Anything independent of `c`. The region tags' integrals change by 150 to
    180% when `c` doubles (E71).

**Evidence, and the rows it serves.**

| row                    | evidence the tags write                                                                   | where it comes from                        |
|:---------------------- |:----------------------------------------------------------------------------------------- |:------------------------------------------ |
| Parent validity        | parity of every model field against the untagged twin, bit for bit                        | the verifier, `compare_runs.py`            |
| Closure                | the gross residual over the window, over Θ                                                | closure table; audit's `source_throughput` |
| Provenance             | per tag L1 and L∞, small tags absolute in OD4 units, process-weighted where it applies    | against an eligible comparator only        |
| Comparator eligibility | the copies' own residual, their repair over Θ a day, refinement, the `mseʲ` mirrors       | E83: not eligible on D4                    |
| Intervention           | the repair's retained gross over Θ a day; each tag's `led_fix` inventory fraction; events | audit, per-tag ledgers                     |
| Convergence            | the refinement of the repair and of `increment_left`; fixed-parent trial steps            | ladders (E76, W25's method)                |
| Aggregation            | 8 tags summed into groups against a run of the groups                                     | reported (OD8)                             |
| Reproducibility, cost  | manifest, verifier, build and step time                                                   | `submit_g3.sh`, WP9                        |

**The residual report (G4.4)** adds, beside the closure: where the residual
sits (its vertical and local maxima), how fast the loss rule flushes it and the
level it would settle at (synergy 4), the offset's headroom (U9), and the
overlays' bounds (A5). They describe the residual. They are not verdicts.

## 3. The process records: what each process did

**What a record claims.** `prc_e_<process>` is the signed running total of the
increment its bracketed process applied to `ρe_tot`, integrated by the
stepper. `prc_q_<process>` is the same for `ρq_tot`.

**What it does not claim.**

  - Provenance. A record is a history, a tag a composition. The two are never
    differenced or summed (E9).
  - A gross. It is net over each output interval, and a cell that gained and
    lost within one can read zero (G4.14's note). So Θi is not Θx.
  - The offset's part. An energy record holds `Δρe_tot`; the tags' increment
    is `Δ(ρe_tot + cρ)`. A budget of `E` adds `c` times the water record
    (`c·Δρq_tot`) for each process that changes mass.
  - Exactness under one Newton iteration. A record takes its implicit
    increment at the stage's first guess, so form B keeps a lag (E39, E43).

**Kept apart from the tags (E22).** A report shows a tag and a record side by
side, never in one number. The rows the records serve are parent validity
(parity, E7) and the parent's energy budget by process, form B, which is not
the tags' closure row. They supply the interim scale Θi, with its label.

## 4. The parent-budget ledger: the parent's accepted update

**What it claims.** Claim levels 1 to 4 of its
[contract](../../../docs/src/parent_budget/contract.md): the accepted state's
change of mass, water and `ρe_tot` agrees with the recorded channels within
the declared tolerance, and so on. Level 6, provenance, is excluded there.

**What it does not claim.** Anything about the tags, and anything outside its
scope. It refuses EDMF configurations at setup (`expl.out_of_scope`,
`impl.out_of_scope` in `coverage.md`), so on D4 and the production sphere it
is *not assessable*.

**Where it meets the tags.** The repair is a final map it declares zero for
the parent (`map.repair_energy_source_tags`): "repair never a parent source".
On EDMF columns the same statement is checked offline by G4.6's budget (the
repair's ledgers sum to zero over the partition in each cell).

## 5. How a result is reported

 1. Each contract row that applies: pass, fail or not assessable, with the
    missing prerequisite named.
 2. Every energy percentage with its scale (Θx, or Θi as an estimate) and window.
 3. Tags, records and the ledger in separate tables. A number from one is
    never presented as evidence for another's claim.
 4. The least favourable number where there is a choice, and the bound
    rather than a cause where a control changes more than one thing.
 5. The warning levels of the closure checks are not acceptance thresholds
    (G4.5, [design/CLOSURE_LEVELS.md](CLOSURE_LEVELS.md)).

## 6. Owner questions

The two of [review/od4_restatement.md](../review/od4_restatement.md),
section 5: the interim's status in the register, and an energy
aggregate-intervention threshold.
