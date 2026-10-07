# Common evidence and acceptance scoring

Base: `5dd23a8309e174592984da7d60912a4a9daaf08a` (Part 3), tree
`ebe9e0771c2bb2dfd92bb851aeb26307f932fd8f`. This work is an offline
implementation. It supplies no new atmospheric evidence or qualification.

## Reuse inventory

| Component | Existing path / behavior | Integration or demonstrated gap |
|:--|:--|:--|
| Submission provenance | `manifest.py`: exact HEAD, dirty diff, config/input/environment hashes | Reuse unchanged defaults and `sha256_file`; optional acceptance extension connects immutable output evidence and scorer/spec identities. |
| Archive/inventory | `inventory.py`, WP0/PX0 evidence README, durable archive | Preserve archival workflow; common validation checks all declared artifact hashes, not the current simulation checkout. |
| Endpoint comparison | `compare_runs.py`: field discovery, matching units/coordinates, bit comparator, weighted tag norms | Preserve legacy CLI; common entry point requires a predeclared field inventory and exact full coverage. Native weights replace implicit remapped integrals. |
| Water baseline | `water/g3base_score.py`: original R1–R8 tables | New identified evaluation fixes TRMM OD2/sensitivity windows, raw/positive scales and R8 source burdens/window numerators. Existing output tables stay immutable. |
| Closure | `closure_verdict.py`: existing approved constants and legacy CSV scoring | Reuse constants; new workflow derives raw water normalization and energy growth from traceable arrays. Legacy outputs keep their existing interpretation. |
| Energy records | `increment/od4_restate.py`, `process_budget.py`, `g411_eligibility.py` | Corrected record variation reconstructs density-weighted records before differences; it has its own name and is never a substitute for exact Θx in new acceptance. |
| Ledger ratios | `increment/ledger_ratio_score.py` | Use actual fields for inventory/burden and cumulative retained endpoint differences; never infer unknown inventory as zero or subtract normalized ratios. |
| Restart | model checkpoint code and scoped integration tests | Reader checks ancestry/checkpoint identity, boundary equality and declared offsets; it cannot certify physical restart equivalence without continuous-run evidence. |
| Tests | evidence verifier tests, closure tests, process-budget tests | Retain old tests; add independent analytic fixture/fault checks and compatibility checks for positive endpoint formulas. |

## Supported metrics and remaining scientific gates

| Contract rows | Implemented computation | Evidence or decision still required |
|:--|:--|:--|
| Common reproducibility | Manifest extension, archive/source/config/environment hashes, scorer/spec identities, completion rehash; no historical overwrite | Missing legacy provenance remains incomplete. New physical evidence belongs to the relevant baseline/qualification part. |
| Parent parity/validity | Frozen field inventory, exact times/dtypes/native geometry, WP0 bit convention, signed zero, negative-water output/latch, column temperature and fixed-parent Newton E | Every actual parent state field/capture; persistent accepted-step validity and scoped physical parity evidence. Exported-only parity cannot pass the full-state row. |
| OD2 | Untagged parent tendency, three intervals below 10% of first-six-hour peak; optional pulse condition; separate startup/established/1-hour sensitivity | No qualifying established interval is explicit. Short/truncated/missing parent histories do not invent a boundary. |
| Water closure/named remainder | Pure-region totals; raw/positive denominators; complete N/R/S part grosses beside the approved gross of total residual; normalized 0/12/24 h growth; named remainder ≤1e-6 | Part 5 named mechanism/cancellation accounting, Parts 8/10 actual integrated evidence. Six-hour closure is reported without applying the 24-hour row. |
| Water/energy endpoint origins | Same-time/native-weighted L1 and specific-peak L∞; small-tag absolute replacement; fixed energy convention; source/region classification; candidate own inventory | Eligible independent rules/floors/ladders in 6/11a; WA-SCOPE; signed energy references are not positive stored-origin truth. D4-W option D preserved. |
| Copies eligibility | Actual residual and retained repair; endpoint/raw/Θx window scales; dt/Newton refinement ≤1.1; named active independent rule coverage/floors/mirrors/Jacobian | Complete independent evidence and active coverage in 6/11a. Ineligibility blocks origins despite exact agreement. |
| Per-tag intervention | Density reconstruction before cumulative differences; accepted cell-step variation; signed amount, actual inventory/burden, positive-region precondition, runtime/window applicability and small-burden exemption | Part 5 accepted-application/leg activity, events/fallbacks and cancellation completeness. Follower is reported, no repair threshold transplanted. |
| Aggregate intervention | Separate retained and attempted window endpoint differences; endpoint-parent daily rate, diagnostic mean-parent reading | Approved water 0.5%/day; energy aggregate approval still pending. No signed `repair_moved` substitute. |
| Energy growth/state | Exact Θx and partition validity; ΔG/Θx ≤0.2%; net/gross endpoints/max/change, state ratios separately | Zero Θx is not assessable. EA-STATE remains a proposal; state is not silently scored under growth tolerance. |
| Energy corrected record estimate | Complete roster; reconstruct ρe_record at each endpoint, absolute output-interval variation before space/process sums | It is named separately from legacy Θi/runtime fallback and cannot qualify new source tags. Excludes cΔρ/finer cancellation. |
| Precipitation | Pure-region instantaneous defect; no-rain absolute defect; paired applied averages/accumulators, signed downward window amount | Part 5 absent paired output; Part 7 independent donors; WA-PRECIP/OD15. 0M receives no borrowed 1M tolerance. Native sphere area-weighted precipitation is not supported by this column reader. |
| Process-weighted origins | Absolute donor-share error inside sum of already space/time-weighted applied amounts; zero activity explicitly inapplicable | Parts 5/6/7/11a directed donor evidence; missing interval bounds/coverage fail data. |
| Radiation pilot | Density-corrected records and independent accepted-stage divergence amount/profile difference, mean W m^-2 | 11a/11b capture/reference floors and EA-USE/EA-ACCURACY/EA-COST; no copies/source-throughput requirement. No atmospheric parameterization validation claim. |
| Aggregation/precision | Explicit nested groups with zero-group absolute errors (reported); owner Float32 `max(10 F64, 3 eps32 sqrt(n))` for fresh preregistered evidence | OD8 intended count and fresh Part 12 ladder evidence. W60 remains failed; neither aggregation nor a scalar precision check qualifies a new envelope. |
| Restart | Checked/hash-linked segment ancestry, identical shared endpoints, continued/reset amount offsets, no gaps/overlaps; attempted/retained fields independent | Model continuous/restarted evidence and checkpoint round trip in 9/10/11b/12. Synthetic stitching supplies reader validation only. |
| Convergence, accepted applications, cost, held-out, final scope | Explicit persistent blocked rows with named destinations; no required row disappears | Parts 5/6/7/8/10/11a–d/12 and outstanding owner decisions. Full eight-tag/24-hour and sphere objectives remain. |

## Verification and review

Offline verification: 49 independent analytic/fault tests pass. They
exercise actual PASS/FAIL/undefined quantities, not an all-blocked stub.
Specific checks include stale hashes, missing files/variables/processes,
physical windows, changing density, source overlays and signed burdens,
comparator ineligibility, zero/small scales, persistent energy state with
zero growth, cancellation, no-rain defects, paired signed precipitation,
required parents/signed zero, restart continuation/reset/boundary defects,
Float32 history preservation, deterministic results and manifest attachment.
Review regressions also reject corrupt archives with valid hashes, geometric
reweighting of integrated amounts, duplicate record processes, omission of
mandatory profile times and proposed-decision pass overrides. Failed parent
parity blocks dependent scientific passes. A final review regression rejects
mismatched tag/density coordinates and nonpositive atmospheric density before
profile normalization, and confirms the correctly aligned analytic failure.

The existing legacy scoring files and historical RUNS/FINDINGS/results are
unchanged. No historical reanalysis was performed. Python/NumPy offline tests
run in the available environment; actual atmospheric runs and native NetCDF4
archive validation are not run here. Broader evidence-test discovery encounters
two legacy module import errors because `netCDF4` is unavailable (53 tests
pass and two modules fail to import); this is an environment limitation, not
a passing validation of those modules. Independent actual-diff mathematical,
physical and performance review is complete. The density-profile alignment
finding was fixed and independently regression-tested; no concrete bugs
remain in the reviewed diff. No model hot path or GPU kernel changes.

Commands and the minimal schema/example are in [README.md](README.md).
No model, diagnostic state, configuration default, threshold, dependency or
CI change is made. No simulation, PR creation/comment/merge is authorized by
this implementation. The user authorized publication of a reviewed new
branch; publication is performed by the supervising agent after verification.
