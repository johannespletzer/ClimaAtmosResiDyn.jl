# Untapped potential assessment — extended

> **Frozen record.** Written on 2026-09-21 and kept as written. Its code links
> pin PR #95 at `974f3e16`, which has since moved. The living plan is
> [ROADMAP.md](../ROADMAP.md), [G3_TODO.md](../G3_TODO.md) and
> [G4_TODO.md](../G4_TODO.md). Until 2026-09-23 the roadmap stood at the top of
> OPERATIONAL_TODO.md.

Prepared 2026-09-21. This is an assessment and proposed experiment programme, not a record of new atmospheric runs.

## Source and continuity

The existing opportunity assessment located in the repository is [OPERATIONAL_TODO.md §7, “Synergies: what the findings give when combined,” and its six prepared proposals](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L853-L997), supported by `FINDINGS.md`, `LEARNINGS.md`, `UPDRAFT_GAP.md` and the operational milestones. No separate file titled “untapped potential assessment” was present in either inspected tree; repository searches also did not resolve that title. This document extends the identifiable assessment above, preserves its six useful directions, and explicitly qualifies conclusions that the newer evidence or implementation does not support. It does not claim to have recovered an unavailable document from another source.

The source assessment is pinned to experiment-branch commit `f69ec02a6eac325b61cb6f30a6f259b1299293ec`. Code statements are pinned to PR #95 head `974f3e1659cddea96a69527017e30a6249ef8666`, unless explicitly marked otherwise. The experiment branch is not the PR head. Its scripts and results inform this broader assessment; they are excluded from the change findings in `pr-95-review.md`.

**Highest expected value:** make per-tag validity observable, preserve reproducible evidence, and test the new mixing closure against independently converged cases before expanding the campaign. Small aggregate closure is necessary for some claims but does not identify the correct provenance.

## Preserve these conclusions, with the following qualifications

| Existing opportunity | Conclusion retained | Qualification or extension |
| --- | --- | --- |
| 1. Increment ledger as a solver diagnostic | A cheap early indicator of changes in the accepted implicit update is valuable. | `increment_left` is a parent-minus-tag increment mismatch, not automatically a pure parent conservation defect. Independently reconcile physical sources, boundary transfers and solver effects before labeling it. The existing parent-budget ledger currently excludes EDMF. |
| 2. Standard short Float64 twin | Use precision twins routinely to distinguish precision-sensitive from persistent errors. | Match code, physics, timestep, rank count and output times. Float64 also changes the trajectory; precision scaling supports a rounding interpretation but does not prove the absence of shared structural errors. |
| 3. Extend updraft provenance mixing to water tags | High scientific potential; the same transport/inventory questions deserve investigation. | Water requires species-consistent partitioning and sedimentation/phase-change handling. Reuse validated infrastructure, not the energy weighting or an unvalidated mixing convention wholesale. |
| 4. Forecast residual evolution | A conditional forecast could flag trouble before a long run completes. | Fit and validate a signed residual budget first. A gross residual is nonlinear under cancellation and spatial redistribution; a scalar steady-rate forecast is not automatically valid. Report intervals and failed assumptions. |
| 5. Report an attribution memory timescale | `τ = E/L` is useful for interpreting offset-dependent memory under donor-proportional loss. | It is an instantaneous loss timescale, not an air age or universal residence time. Sparse signed process records cannot generally recover gross loss throughput. |
| 6. Unified process/solver/repair accounting | Cross-family accounting would expose missing or double-booked terms. | Tag repair does not change the parent and is zero-sum over a viable partition. It must not be added as an independent parent-energy source. Also, the old 1.37 MJ/m² example is already marked resolved by E26 in the findings register; the remaining opportunity is reusable accounting infrastructure. |

Sources: [original six proposals](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L853-L997), [increment definition](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L2157-L2243), [parent-ledger scope](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/parent_budget/contract.md#L249-L288), [resolved E23/E26 entry](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/FINDINGS.md#L2807-L2890), [repair semantics](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L965-L985). These qualifications are **new insights in this extension**.

## Keep four different questions separate

Let `Tᵢ = ρe_src_i`, `E_c = ρe_tot + cρ`, and `P` be the pure region tags, excluding source overlays.

| Question | Quantity or test | What it establishes |
| --- | --- | --- |
| Does the parent model account for its own evolution? | Accepted-step mass, water and unshifted total-energy budgets | Conservation/accounting of the atmosphere, independent of provenance labels |
| Do the partition tags account for the chosen shifted total? | `R = E_c − Σᵢ∈P Tᵢ`; signed `∫R`, gross `G = ∫|R|`, scale `S = ∫|E_c|`, `G/S` | Partition accounting under a declared energy reference |
| Are the labels physically and numerically credible? | Inventory bounds, per-tag reference errors, source pulse response, time/grid/solver convergence | Attribution within the stated convention; source overlays require their own tests |
| Is the computation usable? | Stable runtime, memory, startup, repeatability, checkpoint continuation and provenance | Operability within a declared configuration envelope |

The exchange is constructed to sum to zero over `P`, so its contribution is in the null space of the aggregate closure diagnostic. An arbitrarily large equal-and-opposite redistribution can pass closure. Similarly, the increment correction removes a chosen conservative part of the mismatch by construction. Neither operation creates independent evidence that a tag follows the intended provenance. See [exchange implementation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L1736-L1782) and [increment correction](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L2157-L2243).

Use J for global integrals and J/m² for column budgets after the model's area normalization; use J/kg for specific diagnostics. Preserve quadrature and face-area weights. Do not compare raw global energy with a column budget or let a larger offset make an unchanged dimensional discrepancy look more accurate.

## What the available evidence actually supports

| Evidence inspected | Supported conclusion | Limit |
| --- | --- | --- |
| PR-head GitHub checks: 71 success, one skipped CLA; inspected updraft job: 33/33 assertions | CPU tests cover activation, finite state, one-hour closure and fixed-solver model parity | No local Julia rerun; no new GPU result. The tested merge tree equals the PR-head tree. |
| E73 default/copies comparison and the `head_846ef55d` table | On this DYCOMS setup, `sfc` L1 falls from 15.4% at 1 h to 0.636% at 24 h; peak-normalized L∞ is 2.49% at 24 h | Existing result, not independently rerun. Other processes, startup and boundary choices remain relevant. |
| E73 narrative | Both modes need repair at the inversion; the new default substantially improves agreement with copies over the older donor-only treatment | Agreement between corrected and filtered variants does not establish an exact physical reference. |
| E74 / operational status | The branch records a successful ten-day two-Newton-iteration sphere case and a failed one-iteration model-top state | That ten-day result predates the new updraft mixing; it is not validation of PR #95's default on the sphere. |
| Local scalar calculation of PR formulas | Environment clipping can violate the weighted mixture identity while the exchange still sums to zero | Demonstrates an admissibility issue in the formula; incidence and atmospheric impact have not been measured. |

Sources: [updraft CI job](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/actions/runs/35507845575/job/106070867239), [E73/E74](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/FINDINGS.md#L2323-L2416), [comparison table](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/output/v3_upd_default/head_846ef55d/default_vs_copies.txt), [remaining G2 work](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L90-L123), [plume/environment helpers](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L1946-L2000).

## Prioritized opportunities

Expected value and effort below are planning judgments, not measured returns. S means a focused analysis or bounded change; M means implementation plus a validation matrix; L means substantial infrastructure or a campaign. Evidence gates are required before expansion.

| Rank | Opportunity / lineage | Expected value | Effort | Evidence needed / dependency |
| --- | --- | --- | --- | --- |
| 1 | **New:** admissible subdomain reconstruction and per-tag validation | Very high: closure currently cannot see this failure mode | M | Counterexample tests, activation maps, refined reference comparisons; precedes water-family reuse |
| 2 | **New:** immutable experiment bundles and comparison validation | Very high: makes every later result reviewable | S–M | Explicit run IDs, hashes, exact coordinates/times, full-state parity, archived minimal data |
| 3 | **Extended #6:** independent parent/tag/process accounting | Very high: separates model, attribution and solver defects | M–L | Accepted-step identities; extend EDMF ledger scope or use independently checked offline budgets first |
| 4 | **New:** gross intervention and numerical-health diagnostics | High: reveals bias hidden by cancellation and repair | M | Signed versus absolute accumulators, event counts, accepted-step semantics and restart tests |
| 5 | **Extended #2:** precision × timestep × solver study | High: prevents rounding and solver error from being confused | M | Orthogonal refinements; fixed parent replay for tag-only comparisons where feasible |
| 6 | **New:** criterion-driven residual-closure selection | High: selects a convention by accuracy, not only accounting | M | Held-out cases, dimensional error budgets, admissibility and cost Pareto comparison |
| 7 | **New:** compile and tag-count scalability | High operational value | M | Cold/warm profiles at several tag counts; dependency-graph proof before solver separation |
| 8 | **Extended #1:** solver early-warning probe | High if it predicts failures independently | S–M | Calibrate against known stable/unstable parent trajectories and an independent budget; not just residual magnitude |
| 9 | **Extended #5 and #4:** memory and conditional forecasts | Medium–high interpretive value | S for retrospective analysis; M for trustworthy online rates | Gross losses and forcing stationarity checks; out-of-sample forecast assessment |
| 10 | **Extended #3:** water-tag exchange; air-age and paired provenance products | High scientific upside after validation | L | Validated energy infrastructure, species bounds, independent mass tracer and phase-change controls |

## New insight A — a conservative partition can hide an impossible mixture

The default computes a steady plume, obtains the environment by subtraction, and then clips each negative environment tag. That last operation invalidates the identity used to derive the plume equation. A normalized example with `ρ=1`, `ρaʲ=0.1`, `ρa⁰=0.9`, `entr=0.001`, `Δz=50`, `w=1`, mean `(0.01,0.99)` and incoming plume `(0.99,0.01)` yields a first-tag implied grid inventory of `0.093842` instead of `0.01` after clipping. Float32 and Float64 scalar reproductions agree on the violation; this was not a model run. [Code](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L1946-L1970).

**Alternative criterion:** preserve non-negativity and `ρaʲ εʲᵢ ≤ ρ ε̄ᵢ` as well as the weighted mixture identity. A candidate closure blends the raw plume toward the grid mean by the largest factor in `[0,1]` that satisfies all relevant bounds, then computes the environment without one-sided clipping. This may overmix relative to the original plume and is a candidate, not an established improvement.

**Distinguishing experiment:** use source-free smooth and sharp composition interfaces on a frozen parent column, vary entrainment and mass flux, and compare raw steady, constrained steady and converged prognostic copies. Record local inventory error, interface displacement, per-tag flux error, bound activation, repair and computational cost. Add source pulses only after the source-free identity is understood. A closure that needs persistent large interventions should not be accepted merely because the tags sum correctly.

## New insight B — closure selection needs an explicit objective

The inherited increment algorithm forms a mismatch `m`, column total `I = ∫m` and gross mismatch `H = ∫|m|`. It leaves `m_left = (I/H)|m|` where `H>0`, then constructs a zero-boundary vertical flux whose divergence moves the remainder. This is a particular spatial allocation of the unmovable total. Conservation fixes the integral of `m_left`; it does not uniquely justify the `|m|` weighting or establish physical provenance for the resulting diagnostic flux. This algorithm predates PR #95 and is context, not a new PR defect. [Implementation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L2193-L2243).

**Alternative criteria:** first attribute independently measured accepted process increments; retain unresolved amounts as explicit uncertainty. If redistribution remains necessary, compare the existing weighting with mass-weighted placement or a constrained minimum-change allocation. Enforce column-total consistency, feasible tag inventories and donor limits. Minimize per-tag error and intervention subject to those constraints; do not minimize closure alone.

**Distinguishing experiment:** replay identical accepted parent increments with mismatches localized above and below a sharp interface. Keep `I` fixed while changing its vertical distribution. Compare the induced tag transfers and physical-face-flux estimates under each allocation, including masks of different widths. If a scientific conclusion changes under equally conservative allocations, report that spread as closure-choice uncertainty.

A practical residual report should contain: signed and gross dimensional residuals; offset and positive-total headroom; residual rate over a defined interval; local/vertical maxima; per-tag accuracy; source-overlay bounds; signed and absolute correction activity. Warning thresholds and publication acceptance should be separate. The PR's new default-to-maximum ratios are 7.14, 1.69 and 50, rather than a uniform tenfold margin. [Defaults](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/config/tracer_config.jl#L824-L844).

## New insight C — repair, correction and loss histories need gross as well as net quantities

The current repair cache accumulates signed changes and only takes an absolute value at reporting time. Opposite changes cancel. For two tags, interventions `(1,−1)` and `(−1,1)` report zero net magnitude while their total absolute activity is four. Thus `repair_moved` is a lower bound on gross intervention, not a certificate that the trajectory needed little repair. The increment ledger's “gross” columns likewise take absolute values of accumulated fields. [Audit implementation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L549-L582).

The existing memory proposal reconstructs loss from process records. If a process adds 100 units and later removes 100 units between outputs, its net record is zero although loss throughput was 100. Taking the negative part after temporal accumulation can therefore overestimate `τ=E/L`, even making it infinite. This is a demonstrated algebraic limitation of the proposed recipe, not a measured error in a memory product. [Original recipe](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L946-L972).

**Alternative:** retain signed accounting and independently accumulate positive/negative accepted contributions or event-level variation. Distinguish attempted in-stage repair from accepted-state changes; preserve segment boundaries and restart offsets. For online memory, use the actual loss functional of the attribution rule with the stepper's weights, and state where transport invalidates a local single-timescale interpretation.

**Experiment:** alternating-sign manufactured forcing and oscillating partition corrections, with output cadences of one step versus one hour. Accepted throughput should be cadence-invariant; a net-record approximation should display its expected underestimate. This is a small, high-value diagnostic test before a seasonal campaign.

## New insight D — the evidence pipeline can silently change the comparison

The branch-only [tag_correctness.py](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/analysis/increment/tag_correctness.py#L19-L61) selects the latest matching output independently for each variable; compares only the common-length prefix of `ta` and `rhoa`; and uses the reference's time index for both tag arrays without asserting matching coordinates or timestamps. It labels numerical array equality “bit for bit,” although `np.array_equal` does not distinguish signed zeros. These are demonstrable weaknesses in the comparison script, **outside PR #95**. They do not prove that the existing DYCOMS tables are wrong: the inspected configuration uses a uniform 50 m column and common hourly output.

The metric named L∞ is `max|error| / max|reference|`, not maximum pointwise relative error; the L1 is density/height weighted, not an unweighted column mean. Both are reasonable, but should be named exactly. Replacing `np.gradient(z)` with the model's quadrature/volume weights is necessary before generalizing the script to nonuniform or spherical grids. [Metric definitions](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/analysis/increment/tag_correctness.py#L6-L10).

**Alternative:** require explicit immutable run directories, schema versions, matching times and coordinates, and all expected variables; fail on omissions. Compare the complete parent state within one machine/precision/rank configuration using the repository's signed-zero-sensitive parity contract. Cross-backend agreement needs a separate numerical tolerance. Archive a minimal, checksummed comparison dataset alongside the script and environment.

**Experiment:** deliberately remove a variable, shift one timestamp, truncate a run, alter one grid coordinate and flip a signed zero. The verifier must reject each incompatible comparison or report the exact intended exception. This tests the evidence pipeline without any atmospheric integration.

## New insight E — copies are a comparator, not an exact truth model

Copies share the parent numerics, receive filtering and corrections, and omit direct buoyant surface-energy injection, as the [reference documentation states](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/energy_source_tags.md#L157-L177). The plume assumes steady entrainment, while the copies carry time dependence and additional processes. The energy in their partition sum is also not guaranteed to equal each subdomain's thermodynamic `e_tot+c`; normalization enforces a partition but does not prove that identity.

Use three distinct comparisons: (1) analytical/manufactured source-free mixing, (2) steady versus converged transient copies on identical parent states, and (3) energy attribution versus an independently carried mass tracer. Do not force energy shares to equal air fractions when their specific energies differ. Separate initial-energy labels from newly supplied energy to avoid confusing source attribution with transport.

**Experiments:** switch convection on/off with controlled turnover times; inject a surface-energy pulse with fixed boundary attribution; vary vertical diffusion; then test distinct shallow, stratocumulus, deep/ice and stable regimes. Diagnose adjustment time divided by forcing/composition time, and domain/subdomain positive-energy margins. Those nondimensional and admissibility criteria are more transferable than “agreement after one day on DYCOMS.”

## New insight F — efficiency work should follow the dependency structure

The inspected updraft CI test reported 3,072.34 s total and 99.58% compilation time. That is one test job's cold execution, not a production throughput benchmark. The [split solver](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/prognostic_equations/implicit/manual_sparse_jacobian.jl#L709-L745) only recognizes eligible top-level fields, so new nested copies remain in the larger solver. The [new exchange scratch](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L443-L467) holds three values per tag per cell: payload approximately `3 × N_tags × N_cells × sizeof(FT)`, excluding other state, solver and metadata storage.

Prioritize stable tag signatures across related runs, representative precompilation and separate cold/warm benchmarks. Investigate splitting nested passive-copy blocks only after checking every off-diagonal dependency and proving parent-field parity. Measure tag-count scaling at 2, 8 and 32 tags; GPU register pressure and device allocations cannot be inferred from a CPU `@allocated` result. The conditional branches in plume/zero-total handling should be inspected and profiled on the device; no GPU slowdown or compile failure was demonstrated here.

## Follow-on science after the evidence gates

- **Energy-reference sensitivity:** retain one declared `c` within a comparison and a restart lineage. Choose a positive margin over a specified thermodynamic envelope; do not tune `c` to improve normalized closure. Report changes in dimensional tag amounts under an offset sweep. The [guide](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/energy_source_tags_guide.md#L124-L131) already acknowledges the low-temperature limitation and sign-sensitive ice transport.
- **Water provenance:** start with source-free passive water mixing and species/total-water consistency before convection plus phase changes. Validate the reused reconstruction rather than assuming energy validation transfers.
- **Stratospheric residence and air-age diagnostics:** pair the existing passive-tracer campaign with budget-closed source/sink and pulse-response experiments. Distinguish transient burden/source estimates from a residence-time distribution; do not read the energy-loss memory `E/L` as air age. The repository already has a [campaign plan](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/strat_tracer_campaign_plan.md#L1-L30), so build on it after current restart, input-data and parity gates.
- **Calibrated operational envelopes:** label each supported tuple of geometry, physics, precision, solver, device and rank count with its evidence. Extend the parent-budget calibration beyond its currently committed [single CPU Float64, one-rank row](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parent_budget/kappa_calibration.yaml) only through the stated protocol.

All proposed experiments remain unrun in this review. The companion `repo-operability-pathway.md` orders their dependencies and gives concrete completion criteria.
