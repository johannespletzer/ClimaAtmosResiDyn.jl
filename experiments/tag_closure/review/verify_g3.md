# H3: re-checking what G3 relies on

CONDENSE_PLAN.md step H3. Scope: W1-W14, E40, E44, E53, E55, E59, E64, E66,
E73, E75 — the findings `G3_WATER_PLAN.md` names or leans on. Every other
`FINDINGS.md` entry is out of scope; the full re-check moves to the start of
G4.

Method: for every claim, the committed CSV or `.txt` under
`experiments/tag_closure/output/<run>/` was read directly, or a committed
NetCDF comparison (`analysis/evidence/compare_runs.py`, already built to
reproduce E73) was rerun against the scratch or archive copy of the run.
Where a claim needed arithmetic beyond "read the number," the arithmetic was
redone by hand (checked twice) or with a small script,
[`review/checks/verify_g3/recompute_water_and_energy.py`](checks/verify_g3/recompute_water_and_energy.py),
whose output is
[`recompute_water_and_energy_output.txt`](checks/verify_g3/recompute_water_and_energy_output.txt)
alongside it. Two NetCDF reruns are saved as
[`e53_parity_check.txt`](checks/verify_g3/e53_parity_check.txt),
[`e59_parity_check.txt`](checks/verify_g3/e59_parity_check.txt) and
[`e75_tags_vs_no_mixing_rerun.txt`](checks/verify_g3/e75_tags_vs_no_mixing_rerun.txt).
No Julia ran, no model built, no job was submitted; every check is a Python
read of already-produced output (numpy/netCDF4, `python/3.12`) or an
existing analysis script rerun against the same inputs it was run against
before.

Archived/scratch data used, read only: `/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/`
and its archive copy under `ClimaAtmosResiDyn-archive/scratch_tag_closure/output/`;
`/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/upd_run/` for one build-time
log (E73's cost figure, see below). Nothing on scratch or in the archive was
written.

## 1. Verdicts

| ID | Claim (one line) | Verdict | Evidence | G3 use / effect |
|:--|:--|:--|:--|:--|
| W1 | van Leer ladder flat (slope -0.011) across dt; `first_order` +0.255, `none` +0.464; van Leer 13.8x above `none` at dt 10 | **recomputed** | `output/summary_a.csv` (`final_max_abs_q_tag_res` for a1/a2 runs); log-log slope regression | Grounds WP0-3's explicit-only design (no implicit water-tag Jacobian); no effect, confirms |
| W2 | So implicit water tags are not worth their Jacobian cost | **consistent** | Inference from W1, no independent number | Same as W1; not a separate measurement, nothing to recompute |
| W3 | Correction ledger identically zero across the 11 column runs of A1-A3 | **recomputed** | `output/summary_a.csv`, `final_max_abs_ledger_sum` = 0.0 for all 11 rows (a1 x3, a2 first_order x3, a2 none x3, a3 x2) | Justifies treating the column as limiter-free for the W1-W5 sweep; no effect |
| W4 | Float32 costs nothing on a column: 2.745e-5 vs 2.660e-5, 3% | **recomputed** | `output/summary_a.csv`, `a4_float32`/`a1_dt10` `final_gross_relative` | Basis for V-W7 (Float32 twin of D4-W); no effect |
| W5 | A3's gap is vertical diffusion (27x), not 1M (7%); a3_1m 29x below a1_dt10 | **recomputed** | `output/summary_a.csv`, `final_max_abs_q_tag_res` for a1_dt10/a3_0m_vert_diff/a3_1m | Informs WP3's water-under-EDMF design (vertical diffusion dominates); no effect |
| W5b | Holding vert_diff fixed, 1M moves the residual 1.054e-7 -> 9.845e-8, 7% down | **recomputed** | same summary_a.csv columns | Same as W5; no effect |
| W6 | Issue #64: pre-fix `gross_relative` 3.07e-5 @1h, 0.809 @3h, 24.2 @4h, 5.9e113 @24h | **recomputed** | `output/a5_sphere_limiter/before_issue_64_fix/water_tag_closure.csv` | Historical; motivates WP1's post-#64 CI numbers; no effect |
| W7 | Old rule: `e_after = r*e_before`; docstring's `ρq_tag ≤ ρq_tot_before` bounds non-negativity not closure. Cited at `tagged_water.jl:800` | **stale** | current `src/.../tagged_water.jl:814` (`rescale_water_tags!` docstring, states the same fact); pre-fix commit `49b2ec97`'s old multiplicative code is at lines ~695-741, not 800 | Historical mechanism, not reused directly by G3; no effect (see detail below) |
| W8 | Test bounds `max\|residual\|/scale < 1e-2`; pre-fix archived residual was 7.5e-6 @1h, 6.0e-5 @2h, inside the window before the divergence starts | **recomputed** | `test/tagged_water_integration.jl:237,312`; `output/a5_sphere_limiter/before_issue_64_fix/operator_residual.csv`, `max_abs_q_tag_res` | Motivates WP1's stronger CI bound; no effect |
| W9 | Post-fix plateaus: 1.89e-4 @6h, 2.51e-4 @12h, 2.79e-4 @24h | **recomputed** | `output/a5_sphere_limiter/water_tag_closure.csv`, `gross_relative` | Confirms the fix holds; underlies WP1's "known issue 1 closed"; no effect |
| W10 | `orphaned_relative` 2.5e-9; `nonpositive_fraction` 0.35-0.36; signed residual -7.5e-6 | **recomputed** | `output/a5_sphere_limiter/water_tag_audit.csv`, `water_tag_closure.csv` | No effect |
| W11 | `untagged_relative` 1.3556e-4 vs `overclaimed_relative` 1.4307e-4, ~5% apart (balanced, not runaway) | **recomputed** | `output/a5_sphere_limiter/water_tag_audit.csv`, last row | No effect |
| W12 | Pre-fix ledger one-sided: `q_tag_fix_extratropics` 1.027e115 vs `q_tag_fix_tropics` 4.55e109, factor 2e5; post-fix the two agree to ~15 digits and their sum is smaller than either | **recomputed** | `before_issue_64_fix/operator_residual.csv` and `a5_sphere_limiter/operator_residual.csv`, `max_abs_q_tag_fix_*` columns | No effect |
| W13 | Sphere `max\|q_tag_res\|` 1.9e-5 @24h (1.5e-5 @6h, 1.91e-5 @17h); column (van Leer, dt10) 2.84e-6 | **recomputed** | `output/a5_sphere_limiter/operator_residual.csv`; `output/a1_dt10/operator_residual.csv` | No effect |
| W14 | Ledger 6.2e-4 @24h, ~32x the (q_tag_res) residual, still rising | **recomputed** | `output/a5_sphere_limiter/operator_residual.csv`, ratio of `max_abs_ledger_sum`/`max_abs_q_tag_res` = 32.5x | No effect |
| E40 | No shipped EDMF config runs with tags: `type NamedTuple has no field e_src_strat`; SGS mass flux gross E-tendency 11.5, partition 0; c*ρ part 0.60; sedimentation mismatch 3.4e-3 | **recomputed** | `output/subgrid_build_checks/log_light_edmf.txt` | Directly why WP3 must add the EDMF sub-grid-flux/mass-flux mirrors for water tags; no effect |
| E44 (+E44b, E44c) | Tags make the D4 EDMF column not build in 2h; without tags it builds in 410s (129/228/53); 2/8 tags add 572/876s to the logged stages and 8.5/41.5 min to the whole job (18.5->27->60 min); growth is almost all in `get_simulation`, mostly before the driver's own timers | **recomputed** | `output/d4_column_edmf_notags/run.log`, `provenance.txt`; `output/p4_edmf_two_tags/`, `output/p4_edmf_tags/` `run.log` and `provenance.txt`; `output/p4_build_stages/stages_*.txt` | Directly the basis for G3's cost caution (WP4b, V-W10); no effect, confirms the caution is warranted |
| E53 | C1b D4/D5 validation: residual relative/gross/gross_relative, untagged/overclaimed, form-B gap match for all 4 runs (d4 tracer, d4 enthalpy, d4 vd, d5 ice); `ta`/`rhoa` bit for bit across the D4 pair | **recomputed** | `output/{d4_column_edmf,d4_column_edmf_enthalpy,d4_column_edmf_vd,d5_column_edmf_ice}/{energy_source_tag_closure,energy_source_tag_audit,process_closure}.csv`; `compare_runs.py` rerun, scratch `output_0001` pair | Baseline energy-tag closure methodology that G3 reuses (process-closure diagnostic, per-run parity check); no effect |
| E55 | Float32 D4-vd: `gross_relative` 6.93e-3 vs 5.98e-3; means 4.68e-3/4.80e-3; ranges 1.7e-3 to 7.7e-3 / 1.5e-3 to 8.6e-3; overclaim ratio 0.91-1.14 (mean 1.02, net-overclaimed 12/24h) vs 0.73-0.99 (mean 0.85, 0/24h); form-B 56 vs 1.4 J/m² | **recomputed** | `output/d4_column_edmf_vd_float32/` and `d4_column_edmf_vd/` `energy_source_tag_closure.csv`, `energy_source_tag_audit.csv` | Basis for V-W7 (Float32 twin); no effect |
| E59 | C1c makes the residual worse in all 3 options; base/opt1/opt2/opt3 gross residual and gross_relative at 1/4/12/24h; base 17% above E53's D4-enthalpy value; `ta` identical in all 4 | **recomputed** | `output/c1c_{base,opt1,opt2,opt3}_d4_enthalpy/energy_source_tag_closure.csv`; `compare_runs.py` rerun (base vs opt3, `ta`/`rhoa` bitwise identical) | Directly why WP5 (the follower) exists and runs before WP4 in the water plan (line 210, 219 of G3_WATER_PLAN.md); no effect, confirms the mechanism the water plan copies |
| E64 | `g1_inc_d4` reproduces E62's D4 total to ~8-9 digits (266.942 J/m² @24h); the increment-left/other/loss-rule-predicted split by layer at 1/2/6/12/24h; 10-Newton twin closes to 0.080 J/m², left 0.094 | **recomputed** | `output/g1_inc_d4/{energy_source_tag_closure.csv,remainder_split.txt,compare_base.txt}`; `output/g1_inc_newton_d4/{energy_source_tag_closure.csv,remainder_split.txt}` | V-W3 explicitly reuses this method ("a 10-Newton twin of each mode (E64's split)", G3_WATER_PLAN.md:214); no effect |
| E66 | Per-tag L1/L∞ against the reference at 24h and against the converged twin at 1h, for 7 tags; converged prototype closes to 0.0016 J/m²; reference itself leaves 5.99e5 J/m² | **recomputed** | `output/g1_inc_newton10_d4/tags_against_reference.txt`; `output/inc_d4_enthalpy_increment/tags_against_converged.txt`; `output/g1_inc_newton10_d4/`, `g1_ref_newton10_d4/energy_source_tag_closure.csv` | The per-tag L1/L∞ threshold methodology V-W3/V-W4 (and G3_WATER_PLAN.md section 8's budget discussion) are modelled on; no effect |
| E73 | Updraft gap closed on D4: default vs copies L1 by tag/hour; closure 267.07 J/m² (default) vs 365 (copies), column totals both -45.52 J/m²; **cost: copies double the tendency build, 789s vs 402s** | **discrepant** (cost figure only; the closure/parity numbers are recomputed and correct) | `output/v3_upd_default/{energy_source_tag_closure.csv,default_vs_copies.txt}`, `v3_upd_copies/` same, `analysis/evidence/e73_reproduction.txt` (pre-existing, reproduces the table); `output/v3_upd_default/run.log`, `v3_upd_copies/run.log` (the actual jobs cited, 13528772/13523326) give 600.3s/3504.1s, not 402/789 — see detail | **Affects G3**: `G3_WATER_PLAN.md:485` cites "402 to 789 s" as the basis for the V-W10 build-cost risk at 32 tags. The real D4-scale cost ratio is 5.8x, not ~2x. This makes the stated risk (copies may not build at 32 tags within `hpda2_test`) *understated*, not overstated — see detail |
| E75 | Sphere with updraft mixing: closure 2.003e-4 vs 2.009e-4 (unchanged); tag drift vs no-mixing by hour/tag (`sfc`, `rad`, `new_extratropics`, region tags); integrals move ~1% | **discrepant** (one cell only; everything else recomputed) | `output/g2_v2_sphere_mix/{v2_sphere_analysis.txt,tags_vs_no_mixing.txt}`, `g2_v2_sphere_n2/v2_sphere_analysis.txt`; rerun of `analysis/increment/tag_correctness_sphere.py` against scratch NetCDF, reproduces the committed `.txt` exactly | `rad`'s 1h L1 cell is off (0.108% actual vs 0.15% claimed); everything else — the closure numbers `V-W11` copies from (line 427) — is exact. No effect on V-W11's sizing or on G2's "met" conclusion |

## 2. Discrepant and stale items, in detail

### E73 — the "789 s against 402 s" cost figure is not from the cited runs

**Claim** (`FINDINGS.md`, E73's "Cost" bullet): "the copies add a field per
tag to the updraft and double the time to build the tendency on the EDMF
column (789 s against 402 s)."

**What the cited runs actually show.** E73's own provenance line cites jobs
`13528772` (default, `e010f780`) and `13523326` (copies, `3ec098f1`). Their
committed `run.log`s give:

```
output/v3_upd_default/run.log:104:[ Info: Built tendency function (600.291 s, 27.68 GiB)
output/v3_upd_copies/run.log:105:[ Info: Built tendency function (3504.054 s, 87.02 GiB)
```

600.3 s vs 3504.1 s is a **5.8x** factor, not "double," and neither number
is 402 or 789. `commit`/`slurm_job_id` in both `provenance.txt` files match
the finding's own citation, so this is unambiguously the right pair of runs.

**Where 402/789 actually come from.** `grep`ing scratch's
`claude_work/upd_run/` for these exact figures finds them in
`upd_smoke-13519152.out`, a smoke-test script (`claude_work/upd_run/smoke.jl`)
that happens to reuse the job names `"upd_default"`/`"upd_copies"`:

```
line 68  : [ Info: Built tendency function (401.954 s, 19.83 GiB)   job_id = "upd_default"
line 289 : [ Info: Built tendency function (788.947 s, 29.54 GiB)   job_id = "upd_copies"
```

401.954 s and 788.947 s round exactly to "402 s" and "789 s," and this pair
*is* roughly a 2x factor. So the finding's number is real and traceable, but
it comes from a smaller/earlier smoke-test build (job `13519152`), not from
the D4-scale production runs (`13528772`/`13523326`) that produced every
other number in E73, and not from a run this finding's own citation names.

**Effect on G3.** `G3_WATER_PLAN.md` section 8 ("Risks and open questions")
uses this exact figure: *"At 32 tags the copies may not build within
`hpda2_test` (E73: eight energy copies took the build from 402 to 789 s)."*
Read at face value this suggests a roughly-doubling cost per doubling of
tag count. The real D4-scale cost (the only production-scale data point
that exists) is 5.8x for 8 copy tags over none — substantially worse. This
does not invalidate the plan's conclusion (still: 32 tags may not build in
time); if anything it strengthens the case for V-W10 actually measuring
this rather than assuming a mild multiplier. **Recommendation for H4:**
when V-W10 runs, do not carry the "402/789" figure forward as the baseline;
cite the D4-scale 600.3s/3504.1s pair instead, or drop the specific numbers
from the risk bullet and just say "measured 5.8x at 8 tags on D4 (E73);
V-W10 measures it at 32."

### E75 — one cell of the per-tag drift table

**Claim:** "`rad` L1 against the run without updraft mixing: 0.15% at 1h."

**Recomputed:** rerunning `analysis/increment/tag_correctness_sphere.py`
against the same two scratch runs (`g2_v2_sphere_n2` reference,
`g2_v2_sphere_mix` run — the same command the committed
`tags_vs_no_mixing.txt` was built from) reproduces that committed file
exactly, byte for byte in every printed number, including:

```
rad                  1   2.195e+07  -4.22e-05  1.08e-03  6.32e-03
```

L1 = 1.08e-03 = **0.108%**, not 0.15%. Every other cell in the table
(`sfc` at all four times, `new_extratropics` at all four, the region tags,
and `rad` at 24h/5d/10d) matches FINDINGS.md exactly; only this one 1-hour
`rad` cell is off. The nearby narrative numbers that use the same data
(the −1.25% `rad` integral move at 10 days, the ta/E parity) are all exact.

**Effect on G3.** None found. `V-W11` (G3_WATER_PLAN.md:427) cites E75 only
for the closure/sizing precedent ("10 days, 24 ranks ... as E75"), not for
this per-tag drift number, and the G2-complete conclusion does not depend
on the 1h `rad` figure.

### W7 — a stale line citation, substance intact

**Claim:** "Verified against `tagged_water.jl:800`," describing the old
multiplicative rescale rule (`e_after = r * e_before`) that issue #64's fix
(`7799a5ab`) removed.

At the pre-fix commit the finding's own archived run used
(`49b2ec97`, per `output/a5_sphere_limiter/before_issue_64_fix/provenance.txt`),
the multiplicative `_rescale_water_tags!` function is at lines 695-741, not
800. At the current `HEAD`, line 800 falls inside the docstring of the
*replacement* function, which itself restates the same fact ("The
multiplicative rule this replaced gave `e_after = r * e_before` for every
cell ... (issue #64)," `tagged_water.jl:814`). So the line number does not
point at the claimed content in either tree; the code moved (a full
rewrite plus a later docstring-only commit, `cab1d266`) after the citation
was written. The mechanism itself is corroborated independently by the
pre-fix source and by the current docstring's own account of it, so nothing
about the science is in doubt — only the pinpoint citation is stale.
**Effect on G3:** none; this is historical background for the fix, not a
number or a code path G3 reuses.

## 3. What could not be checked, and why

- **The D4-pair timeout itself (E44's headline claim: jobs `13404536` and
  `13404537` did not finish in 2h and left no output).** By construction a
  timeout with no output cannot be recomputed from data — there is nothing
  to read. It is *consistent* with everything else in evidence: the same
  failure signature (SLURM-terminated, `signal 15`, no output) shows up in
  the committed `output/subgrid_build_checks/log_check_edmf_novd.txt` for a
  closely related build, and the *build components that do exist*
  (`d4_column_edmf_notags`, `p4_edmf_two_tags`, `p4_edmf_tags`) show
  build time growing so steeply with tag count (410s -> 572s -> 876s just
  for the logged stages, before whatever eats the rest of `get_simulation`)
  that a 2-hour timeout at the next tier up is plausible. Not independently
  reproducible without resubmitting the job, which is out of scope here.
- **E53's Form-A "weighted gross" and "cancels in the column" figures**
  (0.05 of gross on D4, 0.005 with the updrafts' diffusion, 8e-12 on D5,
  4.5e-8 of new energy under the enthalpy audit). `process_closure.csv`'s
  committed columns (`form_a_max`, `form_a_relative`, `form_a_max_unrepaired`)
  give the pointwise/relative maxima, which are consistent with the
  narrative, but the specific "weighted gross, reduced over levels" quantity
  is not itself a committed column and would need `analysis/c5_process_closure.jl`
  rerun over the raw per-level NetCDF (Julia, ClimaCore-free reduction) to
  recompute directly. Left as **consistent**, not recomputed.
- **E64's "`ta` within 0.04 K, `E` within 2.5e-4 in L1 at 1h" atmosphere-drift
  claim** and **E66's per-hour `ta`/`E` figures inside `tags_against_reference.txt`'s
  header line.** The headline "bit for bit" / "max relative difference"
  summary lines were read and matched (e.g. `g1_inc_newton10_d4`'s
  `tags_against_reference.txt`: "ta: bit for bit over 25 hours"), but the
  specific 1-hour-only `ta`/`E` breakdown quoted in prose is not broken out
  in any committed file at that granularity. Left as **consistent**.
- **Nothing required rerunning the model, submitting a job, or writing to
  scratch/archive** — none of the 23 findings needed that, so nothing was
  skipped on that account.

## 4. Verdict counts

- recomputed: 20 (W1, W3, W4, W5, W5b, W6, W8, W9, W10, W11, W12, W13, W14,
  E40, E44, E53, E55, E59, E64, E66)
- consistent: 1 (W2)
- stale: 1 (W7)
- discrepant: 2 (E73 — cost figure only; E75 — one table cell only)
- unverifiable: 0
- superseded: 0
