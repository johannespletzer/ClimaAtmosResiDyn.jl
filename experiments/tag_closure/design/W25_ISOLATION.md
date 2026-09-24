# W25's isolation: pre-registered before any run (2026-09-24)

Step 2 of rev. 2's execution order (ROADMAP.md), and G3_TODO's "Follow-up from
V-W4". Written before any of its runs, after the owner approved the OD3
thresholds and OD2's window rule on 2026-09-24. Every pass rule below names the
OD3 row it applies. Nothing here changes a threshold.

## 1. The question

W25 (V-W4) ran D4-W at seven rungs. Three results failed or broke, and none was
isolated, because each rung also changed the atmosphere:

  - at 60 levels the default missed the first hour's budget (`strat` L1 1.36%
    against 1%, `evap` 11.8% against 10%);
  - at 120 levels both modes lost the partition: the follower left out 3.0e-2
    of the water by 12 h, and the copies' repair moved 88% of it;
  - with first-order SGS reconstruction the copies lost the partition (gross
    1.06 at 24 h, repair 95%), and the default did not.

60 levels is now the main case: production is `g2_v2_sphere_n2` at 60 levels
(OD1). D4-W's 60 levels are a uniform 25 m grid over 1.5 km, not the sphere's
stretched grid, so this step bounds the tags' behaviour at 60 levels on a
stratocumulus column. It does not qualify the sphere's grid.

For each failure the step asks one thing. **On one parent state, do the tags'
error and the corrections' throughput fall when the solve or the step is
refined?** If they do, the failure is the tags' lag. If not, it is structural,
or it belongs to the comparison, not to the tags.

## 2. The case, the code, the rungs

  - **Case.** D4-W as W25 ran it: DYCOMS RF02, prognostic EDMF, one updraft, 1M
    stepped implicitly, ARS222, `dt` 120 s, one Newton iteration, 1.5 km, one
    day, Float64, the tags `tropo`, `strat`, `evap`, `evap_tropo`,
    `evap_strat`. The default mode takes the follower
    (`water_tag_transport: increment`); the copies start from the plume. Each
    tag's own ledgers are on (the owner, 2026-09-24). The surface pulse (W21)
    is the case with a source pulse: `sfc` below 50 m, `air` above, and `evap`.
  - **Rungs.** 30, 60 and 120 levels (`z_elem`, uniform), each with centred
    (`edmfx_sgsflux_upwinding: none`, the default) and first-order
    reconstruction. Six rungs, two modes each.
  - **Code.** The run tree `../ClimaAtmosResiDyn-w25i-run`: the record merged
    with `claude/water-tags-wp6-step3` (#109, the per-tag ledgers),
    `claude/water-tags-sed-cross` (#105, the cross blocks) and
    `claude/tag-closure-no-abort` (known issue 7's option A, so that a run
    past water's old closure level goes on with its rows void). Its conflicts:
    `test/tagged_water_tests.jl` (both appended testsets) and `NEWS.md`; no
    source file.
  - **Configs.** `configs/w25i_d4w_{default,copies}_z{30,60,120}_{c,fo}.yml`
    (twelve), their untagged twins `w25i_d4w_untagged_z{30,60,120}_{c,fo}.yml`
    (six, writing `rhoa` and `hus` every 10 minutes for OD2's rule), and the
    pulse `w25i_d4w_pulse_{default,copies}_z{30,60}_c.yml` (four).
  - **Scripts.** `analysis/water/w25_probes.jl` (three probes, below; it
    reuses `w5v_same_atmosphere.jl`'s cache refresh and starts every run as
    the D4-W driver does) and `analysis/water/w25_compare.py` (OD2's window;
    the first-step comparison). The full runs use
    `analysis/water/d4w_driver.jl`, and the verifier `compare_runs.py`.

## 3. The probes and the runs

**P1. Fixed-parent one-step probes** (`PROBE=fixed_parent`), every rung and
mode, to 6 h. The reference steps with ten Newton iterations. At each step its
state is copied into trials with one and with two iterations, which step once.
Per step and variable (the parent `ρq_tot` and each tag), the trial's error
against the reference and the reference's increment; per state ledger, each
run's change over the step. `E = Σ error / Σ increment` over a window, as W35.
Two iterations are the sphere's count; one is D4-W's.

**P2. The refinement test** (`PROBE=refinement`, Insight 10), every rung and
mode. The run reaches 6 h, in established flow, and keeps its state. From that
state five variants run one hour each: `dt` 120 s with 1, 2 and 10
iterations, and `dt` 60 s and 30 s with one. Per variant and state ledger, the
per-step gross over the hour, per hour, over the column's water. The parent's
change against the first variant at the hour's end is reported beside it,
since the variants' atmospheres drift apart within the hour.

**P3. The first-step probes** (`PROBE=first_step`, Insight 4), the pulse case
at 30 and 60 levels, both modes, to 1 h. Three variants: as configured; the
first step with ten iterations; and the tags rebuilt from the state after the
first step. `w25_compare.py first_step` gives each tag's L1 between the modes
at 1 h per variant, with the parent bit for bit between them.

**P4. The full matched runs**, every rung, both modes and the untagged twin,
one day: configuration outcomes, scored with the contract's rows. Each rung is
its own atmosphere, so a difference between rungs is a configuration outcome,
not a tag error.

## 4. What is scored, and how

OD2's windows: startup ends where `w25_compare.py window` puts it on each
rung's untagged twin (the approved rule); established flow runs from there to
24 h (P4) or to 6 h (P1). The OD3 rows are ROADMAP.md's, approved 2026-09-24.

| # | metric | pass rule | OD3 row |
|:- | :----- | :-------- | :------ |
| R1 | P4: every model field of each tagged run against its untagged twin | bit for bit | Parent validity: parity |
| R2 | P1: the parent's `E` for `ρq_tot` at two iterations | at most 1e-3 | Parent validity: Newton |
| R3 | P4: the top level's temperature, the 150 K floor, the parent's negative water | as the rows say | Parent validity: temperature; negative water |
| R4 | P4: the partition's gross residual at 24 h, and the second 12 h against the first | 0.2% of `∫ρq_tot`; no more in the second 12 h | Closure, water |
| R5 | P4, copies: their own residual; their repair over the day | 0.02%; 0.20% of `∫ρq_tot` a day | Comparator: its own residual; its repair |
| R6 | P2, copies: the repair per hour at `dt` 60 against 120 s, 30 against 60 s, and at 2 and 10 iterations against 1 | at most 1.1 times the coarser rung's | Comparator: refinement |
| R7 | P4: per tag, default against copies, L1 and L∞ at 24 h and in the first hour; small tags on absolute error | 2% and 5% at 24 h; 1%, 10%, 25% in the first hour; `2e-4 ∫ρq_tot` | Provenance rows. **Scored only where R5 and R6 pass on that rung**; otherwise *not assessable*, naming which failed |
| R8 | P4: the partition repair's retained gross per day; each tag's `led_fix` `_inventory_fraction` over the day | 0.5% of `∫ρq_tot` a day; 2% per tag. `led_inc` reported | Intervention, aggregate; per tag |
| R9 | P2, default: the throughput per hour of the partition repair and of `inc_left`, finer rung against coarser | at most 0.75 times; above 0.9 flags a structural cause | Refinement |
| R10 | P1, each tag: `E` at two iterations against one | at most 0.75 times, as R9; above 0.9 flags a structural cause | Refinement |

**How the readings bound the three failures.** Each is a bound, not a cause.

  - **60 levels, the first hour.** If R10 passes at 60 levels in the startup
    window, and P3's converged first step or tags started after it bring the
    first-hour L1 within budget, the miss lies in the first step or the
    tags' lag, not in 60 levels as such. If R5 or R6 fails at 60 levels, the
    first-hour comparison is not assessable, and W25's miss was measured
    against an ineligible comparator.
  - **120 levels, the partition.** If `inc_left`'s and the repair's throughput
    fall under R9, and the tags' `E` under R10, the loss is the tags' lag. If
    they plateau (above 0.9), it is structural, and the rung is outside the
    supported envelope until explained.
  - **First-order, the copies.** If the copies' repair grows under R6 on the
    first-order rungs and not on the centred ones, the copies are not an
    eligible comparator under first-order reconstruction. That bounds W25's
    break to the comparator, since the default closed there (R4).

A reading that meets none of these rules is reported as not isolated.

## 5. The jobs

From the W25 run tree, after `git -C ../ClimaAtmosResiDyn-w25i-run log -1`
shows the record's head with these configs. `S` is
`sbatch --account=hpda-c --partition=hpda2_compute --cpus-per-task=2 --mem=48G`.
Probes write to `$SCRATCH/tag_closure/output/w25i_probes/`.

| jobs | what | limit | expected wall time |
|:---- |:---- |:----- |:------------------ |
| 6 | P4 untagged twins | 3 h; 6 h at 120 levels | 30 to 60 min; about 2 h at 120 levels (W25: compiling 12 to 13 min) |
| 12 | P4 tagged runs, 6 rungs × 2 modes | 4 h; 8 h at 120 levels | default 40 to 60 min, copies 1 to 1.5 h (W25: copies compile 28 to 41 min); 120 levels about twice |
| 12 | P1, 6 rungs × 2 modes, to 6 h | 8 h | three integrators, the reference at ten iterations: about 3 to 5 h |
| 12 | P2, 6 rungs × 2 modes | 6 h | 6 h of lead, five one-hour variants: about 1.5 to 3 h |
| 4 | P3, pulse at 30 and 60 levels × 2 modes | 3 h | three one-hour variants: about 1 h |

46 jobs. The expected times are estimates from W25's and W35's jobs. None was
measured with the per-tag ledgers, which add state fields.

## 6. What this step does not do

  - It does not qualify the sphere's grid, or any case but D4-W.
  - It does not change a threshold, or rescore W25.
  - Its P1 and P2 compare trials that start on one state. Within P2's hour the
    variants' atmospheres drift apart. The parent's change is reported beside
    each variant, and a ratio read from a variant whose parent moved by more
    than 1% is marked so.
