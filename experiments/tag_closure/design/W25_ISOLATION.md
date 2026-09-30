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

| #   | metric                                                                                                          | pass rule                                                         | OD3 row                                                                                                             |
|:--- |:--------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------- |
| R1  | P4: every model field of each tagged run against its untagged twin                                              | bit for bit                                                       | Parent validity: parity                                                                                             |
| R2  | P1: the parent's `E` for `ρq_tot` at two iterations                                                             | at most 1e-3                                                      | Parent validity: Newton                                                                                             |
| R3  | P4: the top level's temperature, the 150 K floor, the parent's negative water                                   | as the rows say                                                   | Parent validity: temperature; negative water                                                                        |
| R4  | P4: the partition's gross residual at 24 h, and the second 12 h against the first                               | 0.2% of `∫ρq_tot`; no more in the second 12 h                     | Closure, water                                                                                                      |
| R5  | P4, copies: their own residual; their repair over the day                                                       | 0.02%; 0.20% of `∫ρq_tot` a day                                   | Comparator: its own residual; its repair                                                                            |
| R6  | P2, copies: the repair per hour at `dt` 60 against 120 s, 30 against 60 s, and at 2 and 10 iterations against 1 | at most 1.1 times the coarser rung's                              | Comparator: refinement                                                                                              |
| R7  | P4: per tag, default against copies, L1 and L∞ at 24 h and in the first hour; small tags on absolute error      | 2% and 5% at 24 h; 1%, 10%, 25% in the first hour; `2e-4 ∫ρq_tot` | Provenance rows. **Scored only where R5 and R6 pass on that rung**; otherwise *not assessable*, naming which failed |
| R8  | P4: the partition repair's retained gross per day; each tag's `led_fix` `_inventory_fraction` over the day      | 0.5% of `∫ρq_tot` a day; 2% per tag. `led_inc` reported           | Intervention, aggregate; per tag                                                                                    |
| R9  | P2, default: the throughput per hour of the partition repair and of `inc_left`, finer rung against coarser      | at most 0.75 times; above 0.9 flags a structural cause            | Refinement                                                                                                          |
| R10 | P1, each tag: `E` at two iterations against one                                                                 | at most 0.75 times, as R9; above 0.9 flags a structural cause     | Refinement                                                                                                          |

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

| jobs | what                                    | limit                  | expected wall time                                                                                 |
|:---- |:--------------------------------------- |:---------------------- |:-------------------------------------------------------------------------------------------------- |
| 6    | P4 untagged twins                       | 3 h; 6 h at 120 levels | 30 to 60 min; about 2 h at 120 levels (W25: compiling 12 to 13 min)                                |
| 12   | P4 tagged runs, 6 rungs × 2 modes       | 4 h; 8 h at 120 levels | default 40 to 60 min, copies 1 to 1.5 h (W25: copies compile 28 to 41 min); 120 levels about twice |
| 12   | P1, 6 rungs × 2 modes, to 6 h           | 8 h                    | three integrators, the reference at ten iterations: about 3 to 5 h                                 |
| 12   | P2, 6 rungs × 2 modes                   | 6 h                    | 6 h of lead, five one-hour variants: about 1.5 to 3 h                                              |
| 4    | P3, pulse at 30 and 60 levels × 2 modes | 3 h                    | three one-hour variants: about 1 h                                                                 |

46 jobs. The expected times are estimates from W25's and W35's jobs. None was
measured with the per-tag ledgers, which add state fields. On the login node
all three probes ran two steps of `w25i_d4w_default_z30_c` end to end; the
first build took about 36 minutes there (`output/w25i_smoke/`, checks only).

## 6. What this step does not do

  - It does not qualify the sphere's grid, or any case but D4-W.
  - It does not change a threshold, or rescore W25.
  - Its P1 and P2 compare trials that start on one state. Within P2's hour the
    variants' atmospheres drift apart. The parent's change is reported beside
    each variant, and a ratio read from a variant whose parent moved by more
    than 1% is marked so.

## 7. W21's surface rule: the surface flux at the plume's start (added 2026-09-29)

The owner decided on 2026-09-28 (DECISIONS.md): model the surface flux at the
plume's start, then measure the first hour again. This section is the design.
Section 8 pre-registers the measurement. Its finding number is W50.

**The reading.** The owner answered review S4 of WP3
(`review/agent_reviews/wp3_numerics_review_2026-09-23.md`), recorded in
G3_PLAN 4.1 ("Added in WP3"). The default mode's plume starts at the lowest
level from the grid mean's composition. It has no counterpart of the copies'
fifth mirror, the surface moisture flux into `q_totʲ`. So "the plume's start"
is the lowest level of `water_tag_plume!`, and "the surface flux" is that
flux. The copies' own mirrors stay as they are. Mirror 3, the relaxation
toward `q_b φ̄ᵢ`, keeps giving the buoyant excess `C√σ²` the grid mean's
composition. The owner's decision of 2026-09-25 on the energy copies (M2,
`design/ENERGY_COPY_MIRRORS.md` section 4) rests on that rule. The copies
still start differently in the comparison runs, because the D4-W driver starts
them from this plume (`start_water_tag_copies_from_plume!`). A second reading
would give `C√σ²` to the surface-flux tags in mirror 3 (PP-SFC). It is not
taken: it would reverse the rule M2 was decided on, and S4 is not about it.

**What the plume's start misses, and so the copies' start.** The model feeds
the updraft's lowest cell with three supplies of water, per unit mass of
updraft air and per second:

  - the relaxation toward the buoyant surface value, `r q_b`, with
    `r = mass_flux_source / max(ρaʲ, ρʲ a_min)`
    (`edmfx_boundary_condition_tendency!`);
  - entrainment, `e q⁰`, with `e` the sum of the entrainment and the turbulent
    entrainment rates (`edmfx_entr_detr_tendency!`);
  - the surface moisture flux, `Δʲ = F / (ρʲ Δz)` (`surface_flux_tendency!`).
    The copies' fifth mirror gives it to the tags that receive
    `surface_flux`, by the grid tags' rule.

Every loss there takes each tag by its share: the relaxation's and the
entrainment's `−(r + e) q`, the rain-out and the fall of condensate. The plume
starts from the grid mean's composition, as if the third supply had the grid
mean's composition too. So the default's updraft carries no fresh surface
water at the surface. The copies started from the plume start without it, and
their fifth mirror adds it within the first hour. So their first hour holds a
spin-up after all, which starting them from the plume was meant to avoid
(G3_PLAN 4.1). By S4's estimate fresh surface water is 0.3 to 1% of the
updraft's water there, and `evap` holds about 1% of the column in the first
hour.

**The rule.** At the lowest level the plume starts with the shares

    ψᵢ = (1 − f) φ̄ᵢ + f gᵢ,   f = Δ⁺ / (r q_b + e q⁰ + Δ⁺),   Δ⁺ = max(Δʲ, 0),

and it is rescaled to `q_totʲ`, as at every level. `φ̄ᵢ` is the grid mean's
share, as the plume takes it today. `gᵢ` is the fifth mirror's weight: the
tag's mask where the tag receives `surface_flux`, one for such a tag without a
region, and zero for a tag that does not receive it. Dew, `Δʲ < 0`, leaves by
share in the fifth mirror, so it gives `f = 0`. So does
`disable_surface_flux_tendency`, under which no surface flux enters. Above the
lowest level nothing changes. The plume mixes as before, so the surface water
it starts with rises with it and is diluted by entrainment.

**How it mirrors the model.** `ψᵢ` is the copies' steady state at the lowest
level. There a copy's tendency is
`r (q_b φ̄ᵢ − χᵢ) + e (χ⁰ᵢ − χᵢ) + gᵢ Δ⁺`, plus losses by share. Where the
environment's copies have the grid mean's composition, `χ⁰ᵢ = q⁰ φ̄ᵢ`, the
steady state is `χᵢ / q_totʲ = ψᵢ` exactly. The plume assumes that
composition wherever it entrains. The rates are the model's own, read from the
state and the precomputed quantities: `r` and `q_b` from the surface
conditions, `e` as the plume's own entrainment, `q⁰` as `ᶜq_tot_nonneg⁰`, and
`Δʲ` from the boundary operator the model and the fifth mirror use. Where the
partition's masks sum to one, which the exchange checks, the partition's
`gᵢ` sum to one. Then its shares still sum to one, and the plume still holds
`q_totʲ`.

**Why every parent field stays bit for bit.** The plume is the default mode's
scratch. Only the exchange, the tags' 0M rain-out split and the audit read it.
The new code reads the state and the precomputed quantities. It writes two
scratch fields the tags own, `ᶜq_tag_environment` and `ᶜq_tag_room`, which
the exchange writes again after the plume. It writes no model field and no
model scratch. With copies the model never calls the plume. Only the driver
does, once, before the run. Section 8's R1 checks parity against the untagged
twin in both arms. The integration tests check it on the EDMF column.

**What it cannot fix.**

  - The copies' repair: 0.60% of the water a day (W21), 0.66 to 0.69% (W38).
    The rule changes where the copies start, not their mirrors, so it is not
    expected to move the repair. If R5 still fails, the first hour's
    comparison stays *not assessable*, as in W38.
  - The buoyant excess `C√σ²`. Both modes still give it the grid mean's
    composition (WR18), and a passive tracer gets none of it. PX13 remains the
    only independent check of that choice.
  - The plume's dynamics above the lowest level. W38's P3 did not bound
    `evap`'s first-hour gap to the first step.
  - The steady state's premise. It holds exactly only for an environment with
    the grid mean's composition, so for a vanishing updraft area. D4-W's
    updraft covers about 10% of the lowest level (W18). The first steps after
    a start are not steady either.
  - The exchange's bound. Where the cell holds less of a tag than the
    updraft's start would carry, as for `evap` early in the first hour, the
    bound blends the updraft's share back toward the grid mean's.
  - Energy. The energy tags' plume keeps the grid mean's start (G4).

**Code and tests** (`claude/w21-surface-flux`). `water_tag_plume!` takes the
start from `start_water_plume!` and `water_plume_surface_fraction!`. The
default mode's integration test rebuilds `f` from the model's own tendencies
and checks the plume's lowest level against `ψᵢ`, with `f` above rounding.
Its one-composition check runs with the surface moisture flux set to zero,
where the plume starts from the grid mean again. A mutant without the start's
surface term must fail the new check.

## 8. The first hour again: pre-registered (2026-09-29), before any run

**The question.** With the surface flux modelled at the plume's start: are
the copies an eligible comparator on D4-W (R5), and how far apart are the two
modes in the first hour and at 24 h (R7)? And how much does the rule move the
first hour's difference, on otherwise the same code?

**Arms.** Two detached run trees, each the record (`claude/rec-w21s`, with
this section and its scripts) merged into a model commit:

  - *fix*: `claude/w21-surface-flux` at the commit that implements section 7,
    in `../ClimaAtmosResiDyn-w21s-run`;
  - *main*: `main` at `43b01ca1`, the same code without the rule, in
    `../ClimaAtmosResiDyn-w21s-main-run`.

The arms differ only in the plume's start. So a difference between them is
the rule's effect on this case and code. The parent must be bit for bit the
same in both.

**Cases.** Section 2's D4-W, as W38 ran it: centred SGS reconstruction, one
Newton iteration, `dt` 120 s, one day, the follower in the default mode, the
copies started from the plume, and each tag's ledgers on.

  - Plain D4-W at 30 and 60 levels: `tropo`, `strat`, `evap`, `evap_tropo`,
    `evap_strat`.
  - The surface pulse at 30 levels: `sfc`, `air`, `evap`. It is W21's
    first-hour failure (`sfc` L1 14.4%).

The configs are `configs/w50_d4w_{default,copies}_z{30,60}_c_{fix,main}.yml`,
`configs/w50_d4w_pulse_{default,copies}_z30_c_{fix,main}.yml`, and the
untagged twins `configs/w50_d4w_untagged_z{30,60}_c.yml`. Each is the
`w25i_` config of its rung with only its `job_id` and header changed, so no
output of W38 is overwritten. The pulse at 60 levels is left out. There its
10 m `sfc` edge meets 25 m cells, which is ill-conditioned (PX13), and W38 ran
it only as a probe.

**Runs.** 12 tagged runs and the 2 untagged twins, each one day, with
`analysis/water/d4w_driver.jl`. The twins run from the fix tree. Section 3's
probes P1 to P3 are not rerun.

**Scoring** (`analysis/water/w50_score.py`). Section 4's rules and OD3 rows,
unchanged. No threshold is new.

| #  | metric                                                                                                          | pass rule                                                         | OD3 row                                  |
|:-- |:--------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------- |:---------------------------------------- |
| R1 | every model field of each tagged run, both arms, against the untagged twin of its rung                          | bit for bit                                                       | Parent validity: parity                  |
| R4 | the partition's gross residual at 24 h, and the second 12 h against the first                                   | 0.2% of `∫ρq_tot`; no more in the second 12 h                     | Closure, water                           |
| R5 | copies: their own residual, the largest hourly value; their repair's retained gross per day in established flow | 0.02%; 0.20% of `∫ρq_tot` a day                                   | Comparator: its own residual; its repair |
| R7 | per tag, default against copies of the same arm, L1 and L∞ at 1 h and at 24 h; small tags on absolute error     | 1%, 10%, 25% in the first hour; 2% and 5% at 24 h; `2e-4 ∫ρq_tot` | Provenance rows                          |

  - OD2's windows are read from each rung's untagged twin by the approved
    rule, as in W38 (`w25_compare.py`). The pulse takes its rung's window:
    the tags do not feed back, so its parent is the plain rung's.
  - R7 is a provenance verdict only where R5 passes on that rung and arm, and
    where R6 passes. W38 measured R6 before this rule. So if R5 passes in the
    fix arm, section 3's P2 probe runs on that rung first, and R7 waits for
    its R6. Where R5 fails, R7 is *not assessable*, and its numbers are
    reported with the reason.
  - *Reported, not judged: the rule's effect.* Per tag and rung, R7's L1 and
    L∞ at 1 h and 24 h in both arms side by side. Each mode's change between
    the arms, fix against main, at 1 h and 24 h. The copies' repair per day in
    both arms. The effect is reported with its sign. No threshold exists for
    it, and none is proposed.

**Expected, before the runs.** R1 and R4 pass in both arms. The copies'
repair moves little between the arms, since the rule does not touch their
mirrors. If R5 still fails, R7 stays not assessable, and W21's verdict on
D4-W's provenance stands. In the fix arm the first hour's L1 of `evap`, and of
`sfc` in the pulse, between the modes is smaller than in the main arm.

**Jobs.** From each run tree, after `git -C <tree> log -1` shows the merge:

    CONFIG=experiments/tag_closure/configs/<config>.yml \
    DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl \
        experiments/tag_closure/runscripts/submit_g3.sh \
        --account=hpda-c --partition=hpda2_compute --cpus-per-task=2 --mem=48G

Limits: 3 h for the twins, 4 h at 30 levels and 6 h at 60 levels for the
tagged runs. W38's took 40 to 60 min (default) and 1 to 1.5 h (copies) at 30
levels, and up to twice that at 60.

**What this does not do.** It changes no threshold. It does not qualify the
sphere, or any case but D4-W. It does not rerun P1 to P3. It does not touch the
energy tags. It compares the modes with each other, not with an independent
reference (PX13).

## 9. The energy source tags' plume start (added 2026-09-29)

The owner confirmed section 7's reading on 2026-09-29. The owner also asked
for the energy source tags' plume to take the same rule, in the same change
("do both now"). The energy copies' mirrors M1 and M2
(`design/ENERGY_COPY_MIRRORS.md`, section 3) play the parts of water's fifth
mirror and mirror 3.

**What the energy plume's start misses.** The default mode's exchange
(`sgs_exchange_of_energy_source_tags!`) marches the same steady plume. It
starts in the lowest cell from the grid mean's composition. The model feeds
`mseʲ` there with three supplies: the relaxation toward `mse_b` at the rate
`r`, entrainment at the rate `e`, and the surface enthalpy flux,
`Δʲ = −btt / ρʲ` from `ρ_flux_h_tot` (`surface_flux_tendency!`). M1 gives
that flux to the tags that receive `surface_flux`, by the grid mean's rule.
The plume starts without it.

**The rule.** In the lowest cell the plume starts with the shares

    ψᵢ = (1 − f) φ̄ᵢ + f gᵢ,   f = Δ⁺ / (r (Ā + X) + e A⁰ + Δ⁺),   Δ⁺ = max(Δʲ, 0).

The supplies are in the tags' units, energy per unit mass plus the offset `c`:

  - `Ā = ρe_tot / ρ + c`, the grid mean's, and `X = mse_b − mse̅`, the buoyant
    excess. So `Ā + X` is the sum of the copies' relaxation targets under M2.
  - `A⁰ = (E − ρaʲ Aʲ) / ρa⁰`, with `E = ρe_tot + c ρ` and
    `Aʲ = mseʲ + Kʲ − p/ρʲ + c`. It is the partition's sum of the
    environment's values that the copies entrain, where the copies hold `Aʲ`.
    It is regularized as the model's environment values are.
  - `Δ⁺` is a specific increment, so it carries no `c`.

So the offset enters two of the three supplies, and `f` depends on `c`, as
every energy share does (OD4). A cooling surface flux leaves by share in M1,
so it gives `f = 0`. So does `disable_surface_flux_tendency`. `gᵢ` is M1's
weight for the label `surface_flux`. The energy plume is not rescaled. Its
partition's sum at the start stays that of `ε̄`, which is `Ā` where the tags
close, when the partition's masks sum to one. The buoyant excess keeps the
grid mean's composition (M2, the owner, 2026-09-25).

**How it mirrors the model.** As for water. M2's target `ε̄ᵢ + φ̄ᵢ X` and the
entrained `χ⁰ᵢ` carry the grid mean's composition, where the environment has
it. M1 carries `gᵢ Δ⁺`. The losses, `−(r + e) χᵢ` and a cooling flux, act by
share. So the copies' steady state in the lowest cell has the shares `ψᵢ`.

**Why every parent field stays bit for bit.** The plume is the exchange's
scratch. The new code reads the state and the precomputed quantities. It
writes two scratch fields the tags own, `ᶜe_src_environment` and
`ᶜe_src_room`, which the exchange writes again after the plume. It writes no
model field and no model scratch. A parity check against `main` on the EDMF
column with energy tags shows it.

**What it cannot fix.** The energy copies are not an eligible comparator on
D4 (E84: their repair is 3.1% of the throughput a day, against 0.20%), so
no default-against-copies verdict follows from this rule. `f` depends on the offset. The buoyant excess stays with the
grid mean's composition, as M2 decided. The steady state's premise is the
same as water's: an environment with the grid mean's composition.

**Code and tests.** The exchange's plume becomes a function of its own,
`energy_source_plume!`, with the start at the surface and
`energy_plume_surface_fraction!`. The start in the lowest cell shares its
kernel with water's. The EDMF integration test of the energy tags rebuilds `f`
from the model's own tendencies and checks the plume's lowest cell against
`ψᵢ`. A mutant without the start's term must fail that check.

**E89, the measurement: pre-registered on 2026-09-30, before any run.** The
owner approved section 9's proposal on 2026-09-29 and named it E89.

  - *Case.* D4 (DYCOMS RF02, EDMF, 1M stepped implicitly, one Newton
    iteration, `dt` 120 s, 30 levels, one day) with its eight energy source
    tags in the default mode (`enthalpy_increment`, offset 110,495 J/kg), and
    each tag's ledgers on for OD4's exact throughput. The configs are
    `configs/e89_d4_default_{fix,main}.yml` and `configs/e89_d4_untagged.yml`,
    G4.11's `g411x_d4_*` with only the `job_id` and the header changed. The
    driver is `analysis/water/d4w_driver.jl`, as G4.11's.
  - *Arms.* The fix arm runs at the pushed final head of
    `claude/w21-surface-flux`, from a clean detached run tree with the record
    merged. E89 names that commit, in RUNS and in its finding. The main arm
    runs at `main` `43b01ca1` with the record merged, the same base. The two
    differ only in the plume's start, since D4 has no water tags. The
    untagged twin runs from the fix tree.
  - *Scored* (`analysis/increment/e89_score.py`), with OD3's rows as
    approved: R1, every field the twin writes, bit for bit, in both arms
    ("Parent validity: parity"); closure, the partition's gross residual over
    the window at most 0.2% of the window's exact gross source throughput
    ("Closure, energy"). The window is OD2's rule on the main arm's
    partitioned total, as G4.11 read it.
  - *Reported, not judged.* Each tag's change between the arms, fix against
    main, at 1 h and 24 h: L1, L∞, the absolute L1 and the change of its
    integral, with the sign. No threshold exists for it, and none is proposed.
    No default-against-copies verdict: the energy copies are not an eligible
    comparator (E84).
  - *Expected.* R1 and closure pass in both arms. The surface-flux tag `sfc`
    gains in the lowest levels in the fix arm, and the tags that do not
    receive the flux lose a share of about `f` there, which depends on the
    offset.
  - *Jobs.* Three, `hpda2_compute`, 4 h each, with `submit_g3.sh` as in
    section 8. Scored after all three end.
