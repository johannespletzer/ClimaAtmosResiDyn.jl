# Part 9: the rain and snow tags under EDMF, WP4b stages 2 and 3 (design, 2026-10-11)

Pre-registered before any code and any job. Part 9's queue
([DELIVERY_PLAN.md](../DELIVERY_PLAN.md), part 9) names WP4b's EDMF stages
first, because criterion 7's claim needs them. The design note WP4b-D
([RAIN_SNOW_TAGS.md](RAIN_SNOW_TAGS.md), sections 5 to 7 and 13) fixed the
rules in 2026-09. Stage 1 is built (#121, #127, #146). This note makes the
rules concrete against `main` at `6a8fc6fb7`, names the tests and the runs,
and sets the gate stage 3 waits behind. The numerics reviewer challenged the
first draft on 2026-10-11 (section 12). The owner's decisions are listed in
section 11.

Stage 2 is one code PR against `main` under part 9's template: the mechanism,
the change, the tests, parent parity, the restart check and the 1.10 memory of
the test groups. Stage 3 is a second PR, after the build measurement of
section 9. Each gets a follow-up on `plan-rev2` with the STATUS row, the
G3_TODO entries and the crosswalk rows.

## 1. Question

Under `turbconv: prognostic_edmfx` with 1-moment microphysics, one updraft and
no updraft copies, do the rain and snow parts of the water tags follow their
compartments by their own operators, with the parent's fields bit for bit
unchanged?

**The falsifier is the closing ledger, not the closure.** The closing step of
`follow_water_tag_precipitation!` runs in every `limiters_func!` and every
`constrain_state!` and sets each compartment's parts to its target
(`tagged_water_precipitation.jl:1623-1705`). So `ΣRᵢ − ρq_rai` closes to
rounding whatever the operators did, and the mismatch of the SGS flux, the
exchange or the Jacobian lands in `q_tag_led_close` and `q_tag_fix_<name>`.
What the closing step moves is the evidence, as criterion 4 reads what the
repair moves.

Hypothesis H10: on the D4-W column over a day and on the TRMM LBA EDMF column
over 6 h, in Float64, the closing ledger `q_tag_led_close` integrated over the
column and the run stays within 1e-8 of the run's accumulated surface rain
and snow mass, the parts close within 1e-8 relative of each compartment at
every output, `Σ pr_tag = pr` within 1e-8 relative, and the parent's fields
are those of the untagged twin bit for bit. A FAIL in section 7's checks
falsifies it. A job that does not finish leaves it open. Stage 1 closed to
rounding on the column without EDMF under `increment`, so a closing ledger
above rounding under EDMF names a missing or wrong operator, not a tolerance.

## 2. What the code does today, and what breaks under EDMF

`check_water_tag_precipitation_supported` refuses `water_tag_precipitation: true` with `prognostic_edmfx` and `edonly_edmfx`
(`tagged_water_precipitation.jl:2328`). The `WaterTaggingModel` constructor
refuses the key with updraft copies (`types.jl:2467`). Everything below is
read at `6a8fc6fb7`. If the refusal were lifted with no other change, five
sites would move the parts away from their compartments, and the closing step
would book the difference.

| #  | site                                                                            | today                                                                                                                                                                                                                                                                                                                                                          | under EDMF                                                                                                                                                                                                                                                                    |
|:-- |:------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1 | the microphysics flows (`_set_water_tag_microphysics_flows!`, 870)              | `water_tag_1m_flows_grid_mean` on the grid mean's state, nets from `p.precomputed.ᶜmp_tendency`                                                                                                                                                                                                                                                                | the model's rain source is `ρa⁰ dq⁰ + Σⱼ ρaʲ dqʲ`, each on its subdomain's state and weighted with the Newton iterate's areas (`microphysics/tendency.jl:164-191`, `microphysics_cache.jl:957-1035`). `ᶜmp_tendency` does not exist. The flows' nets would not be the model's |
| S2 | the SGS mass flux (`_sgs_mass_flux_of_water_tags!`, `tagged_water_edmf.jl:165`) | each `ρq_tag_<name>` takes its share of the `ρq_tot` flux by `ρq_tot` shares. The plume is rescaled to `q_totʲ`. The parts get nothing. The parent moves `ρq_rai` and `ρq_sno` by their own difference-form fluxes (`edmfx_sgs_flux.jl:133-169`)                                                                                                               | `N` would take rain's and snow's flux too, `R` and `S` none. Section 6 of the note asks for `q_tot_eff` weights                                                                                                                                                               |
| S3 | the vertical diffusive flux (`edmfx_sgs_flux.jl:390-393`)                       | `α = 1` for every tracer not in `microphysics_tracer_names`. The parts are not in it (`tracer_processes.jl:307`)                                                                                                                                                                                                                                               | `R` and `S` would diffuse at `K_h + K_e` while `ρq_rai` diffuses at `K_e` only. The horizontal loop (`edmfx_sgs_flux.jl:561`) skips the species and not the parts                                                                                                             |
| S4 | the Jacobian (`manual_sparse_jacobian.jl:2895-2920`)                            | the parts' diagonal is the species' block copied value for value inside `update_sedimentation_jacobian!` (1673), before `update_diffusion_jacobian!` adds the species' `K_e` diffusion and `update_sgs_massflux_jacobian!` its mass-flux block. The species' row also has `(ρq_rai, sgsʲs.1.q_rai)` and `(ρq_rai, f.u₃)` blocks (546-575). The parts have none | a part's Newton increment would lag the species' by the missing blocks. Under `increment` the lag goes to the closing ledger, since the parts have no follower (note 17, point 3)                                                                                             |
| S5 | the leak diagnostics and the docs                                               | `tagged_water_leaks.jl:69` and `docs/src/tagged_water_precipitation.md` say the key is refused under EDMF                                                                                                                                                                                                                                                      | the texts are stale, and `edmf_diff` has no parts path                                                                                                                                                                                                                        |

What needs no change: the grid sedimentation of the parts
(`_sediment_precip_parts!`, the species' own operator, rows 5 and 6 of the
note's table), the updraft's sedimentation, entrainment, filter and Rayleigh
sponge (they change `sgsʲs` only, rows 7, 14, 18 and 21), the limiters and
grid constraints (the follow snapshots the grid's rain and snow, rows 19, 20
and 22), DSS, `pr_tag` (the grid's flux at the lowest level, as `pr`), the
restart guard (no new state field) and the increment follower of `N` (it
already divides by the non-precipitating water,
`tagged_water_increment.jl:12-15`). The hook runs in both the implicit
(`implicit_tendency.jl:93`) and the explicit (`remaining_tendency.jl:264`)
microphysics paths, so `implicit_microphysics: false` needs no second rule.

## 3. Stage 2, the rule made concrete

Section 7 of the note gives one rule for the default mode. Here it is per
site.

### 3.1 The flows per subdomain (S1)

The six flows are evaluated on each subdomain's state, `F⁰` on the
environment's and `Fʲ` on the updraft's, and cached apart in tag-owned
scratch. The tendency weights them as the model weights its nets, with the
Newton iterate's areas from `Y`:

    F = (ρa⁰ F⁰ + Σⱼ ρaʲ Fʲ) / ρ

A single cached `F` with the precomputed state's areas would freeze the
weights while the model's move with the iterate, and the difference would go
to the net-flow rule. With a 5% area change, updraft rain formation of
1e-7 s⁻¹ and the environment's of 1e-9 s⁻¹, that remainder is 4.3% of the
net. `F⁰` uses the environment's inputs as `set_microphysics_tendency_cache!`
forms them (`ρ⁰`, `q_lcl⁰` to `q_sno⁰`, `T⁰`, `w⁰`, and under the quadrature
`λ⁰` and `mu_S⁰`), recomputed into the tags' own scratch with the same
expressions, since the model's `ᶜtemp_scalar` to `ᶜtemp_scalar_7` are
overwritten by `set_precipitation_surface_fluxes!` right after. The
quadrature path passes `λ⁰` and `mu_S⁰` positionally as the model does, so
the flows' nets repeat the model's arithmetic. `Fʲ` uses `ᶜρʲs`, the
updraft's prognostic species, `ᶜTʲs` and `ᶜuʲs`. The nets the parts read
(`dq_rai_dt`, `dq_sno_dt`) are the same weighted sum of `ᶜmp_tendency⁰` and
`ᶜmp_tendencyʲs`, lazily. Without EDMF nothing changes.

**Orientation.** A weighted flow can be negative where a subdomain's content
is negative or its area is outside `[0, ρ]` between filter calls. The pool
shares still sum to one, but a part can then go negative while its
compartment is positive (with `qR = 1e-6` and `Δt·NR = −0.9e-6` the shares
are `(10, −9)`). So the weighted flows are oriented pairwise before the pool
(`_oriented_pair` with touches on), which keeps each pair's net and leaves
non-negative flows bit for bit. A unit test holds a negative weighted flow.

**Composition.** Every flow carries its donor compartment's grid composition
over the step, by the pool rule of stage 1 (`water_tag_pool_shares`). The
updraft's own composition is not used for its flows. This is the
approximation section 7 of the note names. Because stage 3 may not come
(section 9), stage 2 measures it: an audit record per tag,
`q_tag_aud_up_<name>`, accumulates the updraft's `N → R` and `N → S` flows
attributed with the bounded plume shares less the pool shares,
`ρaʲ Fʲ (ε̃ʲᵢ − ψNᵢ)`, as a diagnostic from the tags' scratch, not a state
field. `pr_tag`'s docs say that rain formed in the updraft carries the grid's
composition. The alternative, the plume's composition for the updraft's
flows, is the owner's decision D1 (section 11).

The withheld ledgers (`q_tag_exp_negative`, `q_tag_exp_negative_precip`)
read the weighted nets. The audit records keep their meaning and are reported
under EDMF, as G3_PLAN 6.1 says.

### 3.2 The SGS mass flux and the exchange (S2)

The parent moves `ρq_tot`, `ρq_rai` and `ρq_sno` by difference-form fluxes
`ρᵏaᵏ(u³ᵏ − u³)(χᵏ − χ)`, reconstructed with `edmfx_sgsflux_upwinding`. The
parts take shares of them, each by its compartment:

| part            | flux                                                    | share                  |
|:--------------- |:------------------------------------------------------- |:---------------------- |
| `N`, `ρq_tag_`  | the `ρq_tot` flux less the `ρq_rai` and `ρq_sno` fluxes | `N_i / N`, by the norm |
| `R`, `ρq_rtag_` | the `ρq_rai` flux, rebuilt from the same inputs         | `R_i / ρq_rai`         |
| `S`, `ρq_stag_` | the `ρq_sno` flux, rebuilt from the same inputs         | `S_i / ρq_sno`         |

The `N` flux is the difference, not a flux built from `q_tot_eff`: the two
agree to rounding only for linear reconstructions, and `vertical_transport`
also has `vanleer_limiter`. The three fluxes then sum to the parent's `ρq_tot`
flux cell by cell for any reconstruction. A source tag takes its own clamped
share, as today. Where a compartment is not positive the share is zero, as
the sedimentation share is.

**The exchange.** The plume (`water_tag_plume!`) is rescaled at each level to
`q_tot_effʲ` instead of `q_totʲ`, and mixes in the grid mean's shares of `N`
instead of `ρq_tot`. The room and water ratio of the `N` bound use
`q_tot_eff` in each subdomain. The `N` exchange then runs as today on the `N`
parts. The `R` and `S` parts get the exchange term of row 17: on the updraft
side the flux of `ρaʲ(u³ʲ − u³) q_raiʲ (εʲᵢ − φ̄ᴿᵢ)`, on the environment's
side its counterpart with the environment's shares, each reconstructed
first-order upwind as the `N` exchange is. `R` and `S` each get their own
bound from their own room and ratio (`q_raiʲ`, `q_rai⁰`), and their own
partition blend factor, not `N`'s. Where the environment holds no rain or
negative rain the room is not positive and nothing is exchanged. The sum over
the partition is zero by construction. Snow alike with `q_snoʲ`.

`εʲᵢ` is the updraft's rain composition by the note's section 7 rule, which
the owner kept as written (D4, 2026-10-11): the updraft's rain takes `N`'s
composition where it forms and the environment's where it flows in laterally
(`advection.jl:421-424`). It is a second steady plume, the rain plume, marched
downward as the rain falls. At each level the updraft's rain is the mix of
three sources, each with its composition: the rain that fell into the level
from the level above within the updraft, with that level's rain plume shares,
the rain formed there, `ρaʲ Fʲ_NR Δt`, with the `N` plume's shares, and the
lateral inflow where the updraft narrows, `ρ⁰ w⁰ q_rai⁰` as
`updraft_sedimentation!` forms it, with the environment's rain shares
`(Rᵢ − ρaʲ εʲᵢ q_raiʲ) / (ρ q_rai − ρaʲ q_raiʲ)` from the level above. The
shares are rescaled at each level so that the partition's sum is one, as
`WaterPlumeStep` rescales the `N` plume. Where the updraft holds no rain
(`q_raiʲ ≤ 0`) the rain plume takes the grid mean's rain shares, and where
the environment holds none the inflow source is dropped. The snow plume is
the same with the snow sources. The rain plume is written in scratch the tags
own and starts anew each exchange evaluation, as the `N` plume does.
`water_tag_edmf_audit` reports where the `R` and `S` bounds bind, as it does
for `N`.

The exchange needs region tags that partition the domain
(`check_water_tag_exchange_partition`), as today. It is implicit with the
mass flux (`implicit_tendency.jl:155`) and has no Jacobian block, as the `N`
exchange has none today.

### 3.3 The diffusive flux (S3)

In the vertical loop a part gets `α = 0`, the species' `K_e`-only diffusion.
The horizontal loop skips the parts as it skips the species. The updraft
mirror is skipped on its own, since no updraft field carries a part's name.
`N` at `K_h + K_e` and `R` and `S` at `K_e` sum to the parent's
`K_h q_tot_eff + K_e q_tot`. `correct_water_tag_diffusion_leak!` stays a
no-op with the key, the leak diagnostic `q_tag_leak_edmf_diff` reads zero
under it, and the docstring of `tagged_water_leaks.jl:69` is corrected.
`water_tag_leak_correction` with the key keeps whatever refusal holds today.

### 3.4 The Jacobian (S4)

Rule: a part's row is the species' row, value for value on the diagonal and
scaled by the part's share on every cross block. Under EDMF with 1M and the
mass flux the `ρq_rai` row holds its diagonal, `(·, sgsʲs.1.q_rai)` and
`(·, f.u₃)`, and no `(·, ρ)` block (546-571, 2829-2856). Concretely:

  - `update_water_precip_part_sedimentation_jacobian!` is called after the
    last update of the species' row, after `update_sgs_massflux_jacobian!`,
    not inside the sedimentation update. The parts' diagonal then holds the
    species' sedimentation, `K_e` diffusion and mass-flux diagonal.
  - With `water_tag_cross_flag` set, each part gets the species' `(·, f.u₃)`
    block and the `(·, q_raiʲ)` or `(·, q_snoʲ)` block, each scaled by the
    part's share of its compartment. They are allocated with the parts'
    diagonals in `sedimentation_jacobian_blocks` and
    `sgs_massflux_jacobian_blocks`. The split solver carries them by
    back-substitution as it carries the `N` tags' sedimentation cross blocks
    (`manual_sparse_jacobian.jl:80-94`): `ρq_rai` sits in the coupled solve's
    block-lower-triangular group and is recovered from the final `δu₃` and
    `δq_raiʲ`, which the back-substitution reuses. The back-substitution has
    not carried a face-vector column or an `sgsʲs` column before, so test
    item 6 exercises both.
  - The copy is exact for the sum: where the shares sum to one in a cell, the
    parts' increments sum to the species' to rounding. It is approximate per
    tag, since a part's own mass-flux derivative is `F / R_up`, not the
    species' `M / ρ`. With one Newton iteration that moves composition
    between tags by about `dt |F| / ρq_rai` per step. Test item 6 reports it.
  - Without the split (`split_uncoupled_fields: false`) the parts keep only
    their diagonal and the lag goes to the closing ledger. The key under EDMF
    is refused without the split, with a message that says why.

With this no follower is needed for `R` and `S`, as stage 1 decided (P2).

### 3.5 The refusal

`check_water_tag_precipitation_supported` accepts `prognostic_edmfx` with the
split solver. The existing transport check already requires one updraft.
`edonly_edmfx` stays refused: no case in the plan uses it, and lifting it
would add a test build the plan has no use for. Updraft copies stay refused
until stage 3. The error texts say so.

### 3.6 What stays

The grid sedimentation of the parts, the follow in the limiters and
constraints with its closing step, `pr_tag`, the restart guard at version 2,
the audit and the increment follower of `N`. `increment` stays the default
transport under EDMF (DECISIONS.md, "WP5's default transport under EDMF").

## 4. Parity

The tags' code writes tag fields and scratch the tags own. The new flux
reconstructions read `p.precomputed` and `Y` and write `Yₜ` tag rows. The
Jacobian changes touch the parts' blocks only. So the parent's fields stay bit
for bit those of the run without tags. Section 6 item 7 and section 7's parity
check hold it.

## 5. Cost

The flows are evaluated once per subdomain: two evaluations under EDMF with
one updraft, against one today, each of the order of the microphysics' cost
(note section 13). The exchange on `R` and `S` adds two flux reconstructions
per tag. The parts' cross blocks add two block updates per part. The step
time on versus off is reported from section 7's D4-W pair. It is not a WP9
measurement (no exclusive node) and gates nothing. The eight plus eight cost
row stays with the walk fix item.

## 6. Tests

The transport is a type parameter of `WaterTaggingModel`, so the key under
`increment`, the key under `tracer` and the plain column are three EDMF
builds, and three overran a job's time before (`runtests.jl:265-279`). Two
groups, on the DYCOMS RF02 EDMF column of the other EDMF groups (30 levels,
dt 120 s, 1 h, 1M), with a partition by altitude and a `surface_flux` source
tag:

  - `tagging_water_precipitation_edmf`: the key under `increment` and the
    plain column, two builds.
  - `tagging_water_precipitation_edmf_tracer`: the key under `tracer`, one
    build.

The first group checks:

 1. at the start each part is its masked share of its compartment.
 2. after the hour the closing ledger `q_tag_led_close`, integrated over the
    column, is within rounding of zero against the hour's rain throughput
    (the rain that fell and formed), and the compartments close within 1e-8
    relative. Both numbers are printed.
 3. the twin test of the note's section 5, operator by operator, for the SGS
    mass flux of each compartment, the exchange, the vertical diffusive flux
    and the microphysics nets: a tag that holds all of a compartment takes
    that operator's tendency of the compartment.
 4. the exchange on `R` and `S`: zero on a uniform state, zero sum over the
    partition, and the bound holds on a state that would break it.
 5. the flows' weighted nets equal the model's nets to the rounding of the
    step's water at a Newton iterate whose areas differ from the precomputed
    state's, with and without the quadrature.
 6. one implicit stage: the parts' Newton increments sum to the species' to
    rounding with the cross blocks on, through both the `f.u₃` and the
    `sgsʲs` column, the per-tag drift is printed, and the split solver solves
    the parts apart.
 7. the model's fields are those of the column without tags, bit for bit.
 8. `pr_tag` of the partition closes to `pr`.
 9. the refusals: `edonly_edmfx`, updraft copies and the unsplit solver with
    the key, with the new texts, and `prognostic_edmfx` with two updrafts.
10. a checkpoint restores the parts bit for bit, and one continued step
    keeps the closing ledger at rounding.
11. the new kernels allocate nothing on a second call.

The second group checks that the partition stays bounded under `tracer`, with
the audit switched off, and prints the closing ledger. The unit tests in
`tagged_water_precipitation_tests.jl` gain the weighted flow sum against a
hand-built two-subdomain state, the oriented negative weighted flow and the
pool shares under it. Both groups go into the fork's groups list, so the
nightly 1.10 run covers them, and into the full tier. The 1.10 peak of each
group is measured on the first nightly run, not asserted.

## 7. Runs

Four jobs, each after the owner's approval, from a run tree at the PR's merge
commit and a record tree on `plan-rev2`, as part 9's producer ran
(`manifest.py --model-repo`). Checks as `part9_checks.sh` runs them, with
their logs under the record.

| run                | case                                                  | purpose                                       | estimate                        |
|:------------------ |:----------------------------------------------------- |:--------------------------------------------- |:------------------------------- |
| `p9_d4w_rs_off_1d` | D4-W (DYCOMS RF02 EDMF 1M, 60 levels, 1 day), no tags | the twin                                      | as W55's twin, about 1 h        |
| `p9_d4w_rs_on_1d`  | D4-W, three tags with the key, `increment`            | the closing ledger, `pr_tag`, the audit, cost | W55 plus the flows, about 1.5 h |
| `p9_d5_rs_off_6h`  | D5 (TRMM LBA EDMF 1M, 82 levels, 6 h), no tags        | the twin with snow                            | as `d5_column_edmf_ice`         |
| `p9_d5_rs_on_6h`   | D5, three tags with the key                           | the snow part                                 | D5 plus the flows               |

No restart pair: on an EDMF column the model's own restart differs from the
first restarted step on (FINDINGS E54, E58, PART9_PRODUCER section 13), stage
2 adds no state, and the plume and the flows are recomputed from `Y`. Test
item 10 covers the checkpoint. DYCOMS RF02 drizzles, with no snow: in W50's
archive the hourly mean `prra` runs from 1.9e-6 to 2.7e-5 kg m⁻² s⁻¹, rain is
in the grid and in the updraft from 1 h on 60 levels, and `hussn` is zero.
The 30-level test column is not checked. The snow part is exercised on D5.
Both cases write `q_tag_*`, `q_rtag_*`, `q_stag_*`, the audit records,
`q_tag_led_close`, `q_tag_led_rescale`, `q_tag_led_empty`, `pr_tag_*`, `pr`,
`husra` and `hussn` at 30 min.

Checks and pass rules, Float64:

| check    | rule                                                                                                                                                            |
|:-------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| closing  | `q_tag_led_close` integrated over the column at the end within 1e-8 of the run's accumulated surface rain and snow mass. `led_rescale` and `led_empty` reported |
| closure  | `ΣRᵢ − ρq_rai`, `ΣSᵢ − ρq_sno` and `Σ(Nᵢ+Rᵢ+Sᵢ) − ρq_tot` within 1e-8 relative of the compartment at every output, a sanity check                               |
| `pr_tag` | `Σ pr_tag − pr` within 1e-8 relative of `pr` at every output where `pr` is not zero                                                                             |
| parity   | the parent's fields of `on` bit for bit those of `off` at every output, both cases                                                                              |
| audit    | the microphysics audit and `q_tag_aud_up_*` reported, not judged                                                                                                |
| cost     | step time `on` over `off`, reported                                                                                                                             |

The record goes to `analysis/evidence/PART9_WP4B.md` with the job table, the
check logs and the verdict on H10, in a follow-up PR on `plan-rev2`.

## 8. Deliverables

Stage 2's PR against `main`: the code of section 3, the tests of section 6,
the docs (`tagged_water_precipitation.md` "Limits and cost", the API
section, `tagged_water.md` where it names the refusal), the NEWS entry and
the registry rows if a new writer appears (none is planned). The follow-up on
`plan-rev2`: this note's pointers, the STATUS row "Rain/snow, non-EDMF stage
1" split into stage 1 and stage 2, G3_TODO's stage 2 entry, the crosswalk
rows, the run configs and the record.

## 9. Stage 3, and its gate

Stage 3 gives each tag three updraft copies, `Nʲ`, `Rʲ`, `Sʲ`, moved by the
updraft's own operators: the updraft sedimentation with the species' linear
operator and the environment's composition in the lateral inflow (row 7),
the updraft's flows from `Fʲ` on the updraft's parts, entrainment and
detrainment per field, the filter and three repairs, and the copies' own SGS
tracer flux moving the grid parts. The copies are not split-solvable
(`is_splittable_jacobian_field`, 904-917), so fifteen copies at five tags go
into the coupled solve, where E44b to E44d measured the build growing faster
than the field count. The note's section 13 puts the measurement before any
code.

**The gate measurement.** Today's copies mode (`water_tag_updraft_copy: true`) on the D4-W column with 5 and with 15 water tags, on an exclusive node
under WP9's spread rule, two repeats each. Its grid tags are split and its
updraft copies are coupled, which is the structure the parts' copies would
have (`Rʲ` and `Sʲ` add their sedimentation blocks on top). Passive tracers
are no proxy: `passive_tracers` are grid-only, `chemistry_model: passive`
gives one `q_gas_A`, and a grid tracer in the coupled solve is not what a
copy adds. Read `get_simulation` and the step time.

**The prediction, pre-registered.** E44c's coupled builds (712, 916 and
2604 s at 0, 2 and 8 tags) fit a power law with exponent 1.61. That predicts
1601 s at 5 coupled fields and 5903 s at 15, a ratio of 3.7. Linear growth at
E44c's per-field cost gives 2.25. Both are above the factor below. The
measurement is still worth its two builds: E44c dates from `edd44e1d`, and
the solver has changed since.

**The gate.** Stage 3 starts if the fifteen-tag build is within two times the
five-tag build, the factor OD3 uses for the copies' cost. A build that hits
the job's time limit fails the gate. Otherwise stage 3 waits for the split
solver's extension to updraft fields, as a part 9 item of its own, and the
note's section 7 copies paragraph stays the plan. The owner sets the factor,
or skips the measurement (D2).

## 10. Budget

Stage 2: 1.2M for the PR under part 9's template, 0.3M for the runs' record.
The gate measurement: 0.2M. Stage 3's PR is briefed after the gate, with its
own estimate. Author and reviewer are separate agents. The numerics reviewer
at xhigh challenged this note (section 12) and confirms the mechanism reading
of the PR.

## 11. For the owner

*Decided 2026-10-11* (DECISIONS.md, "2026-10-11, part 9 WP4b stages 2 and
3"): D1 the grid pool rule with the audit record, D2 the two-build
measurement with the prediction on record and the factor two, D3 the four
jobs and the budget as proposed, D4 the note's section 7 rule as written,
against the recommendation. Section 3.2 holds the rain plume that rule needs.

 1. **D1, the updraft's flows' composition.** The grid pool rule for every
    flow, with the audit record `q_tag_aud_up_<name>` measuring the error
    (recommended), or the plume's `N` composition for the updraft's `N → R`
    and `N → S` flows. For the pool rule: one rule for all flows, the nets
    close by construction, and the record measures what the rule misses,
    which copies mode would have audited. Against it: where the updraft's
    water differs in composition from the grid mean's, the updraft's rain is
    attributed with the grid mean's composition. The error is largest at an
    altitude partition near cloud base, which is the test's own setup. For
    the plume composition: closer to the updraft's physics. Against it: a
    second composition enters the pool system, and the plume is an
    approximation of its own (note section 7).
 2. **D2, the stage 3 gate.** Run the two-build measurement with the
    prediction of section 9 on record and the factor two (recommended), or
    skip it and send stage 3 to the split solver's extension now. For the
    measurement: a number at today's solver beats a fit to 2026-09 builds,
    and it costs two builds. Against: the fit says it fails.
 3. **D3, the run set.** Four jobs as in section 7 (recommended), or the
    D4-W pair alone. Against the pair: the snow part has no run evidence
    under EDMF.
 4. **D4, the updraft's rain composition in the exchange.** The local `N`
    plume's share at each level (recommended), or the note's section 7 rule
    with the lateral inflow carrying the environment's composition. For the
    local plume: the plume already mixes the lateral inflow into `N`, and the
    exchange reuses it with no second plume. Against: it is a further
    approximation the note did not name.
 5. **The budget** of section 10.

## 12. The challenge of 2026-10-11

The numerics reviewer (Opus, xhigh, about 234k tokens) challenged the first
draft against the code. Blocking: the closure rule could not falsify H10,
because the closing step restores the parts each follow (now section 1), and
the gate's passive-tracer proxy could not be configured and would not stand
for a copy (now section 9). Should-fix, all taken: the frozen area weights
(3.1), the oriented weighted flows (3.1), the exchange's composition and
blend factors as D4 (3.2), three builds in one group (6), the restart pair on
an EDMF column (7), and the gate's predicted failure (9). Notes taken: the
difference form of the `N` flux (3.2), the tags' own scratch for the flows'
inputs (3.1), the unsplit solver refused (3.4), the `R` and `S` audit binding
(3.2), the per-tag approximation of the copied blocks (3.4), the two new
columns in the back-substitution (3.4) and the rain magnitudes (7). The
reviewer held D1 on condition of the audit record, and changed D2 and D3 as
written here.
