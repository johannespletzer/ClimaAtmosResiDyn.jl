# G4.3: energy meaning and acceptance contract

This is the canonical energy-specific interpretation of
[ROADMAP's acceptance contract](../ROADMAP.md#the-acceptance-contract).
Part 3, 2026-10-06, extends the contract written on 2026-09-25. The common
verdicts and approved numbers remain in
[OD3](../ROADMAP.md#the-od3-thresholds-approved-2026-09-24). The
[decision register](../ROADMAP.md#the-decision-register) and
[DECISIONS](../DECISIONS.md) own approvals. This document defines observables,
applicability and missing evidence. Its completion does not qualify energy origins or authorize a run, a default or a new tolerance.

## 1. Three different claims

| Diagnostic                                | Claim                                                                                                                                                                                          | What it cannot establish                                                                                                                                            |
|:----------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stored source tags, `ρe_src_<name>`       | The currently represented energy carrying a declared entry-region or process label, under fixed allocation, loss and transport rules and offset `c`.                                           | The signed net contribution of that process, physical uniqueness of a label convention, causal effect of removing a process and correct origins from closure alone. |
| Signed process records, `prc_e_<process>` | The time-integrated signed energy tendency increment of the attributed process, with the stepper's weights.                                                                                    | A composition of present energy, a gross activity, transport of an origin, or an exact accepted implicit increment when the record lacks the parent's coupling.     |
| Parent budget, `BudgetJournal`            | Agreement of the parent's accepted endpoint change with independently collected accepted channel envelopes and final maps, plus the channel decomposition within its declared supported scope. | Tag origins, energy-source label validity, causal counterfactuals, or physical completeness solely from a small residual.                                           |

A process can cool a cell while its source tag records almost none of that
removal: donor-proportional loss takes energy from every tag by its current
share. E22 measured this separation: where radiation cools most, the radiation tag holds 7.1e-8 of the cell's total. A tag is composition. A record is history.
Do not subtract or add them to produce an origin error. `ρe_tag_*` is another
family of signed, transported energy tracers. It is not the `prc_e_*` record.
A rerun with a process disabled changes the atmosphere and is a separate
counterfactual experiment.

Use **budget** for parent accounting, **ledger** for tag accounting, and
**record** for process accounting. The historical phrase "parent-budget
ledger" means the parent budget here, not a tag ledger. Keep separate report
tables and verdicts for these three claims.

## 2. Energy convention and discrete equations

### 2.1 Parent energy and fixed convention

The authoritative parent field is `ρe_tot` [J m⁻³]. The implementation forms
`e_int = ρe_tot/ρ − K − Φ`, with `K` the grid-mean specific kinetic energy and
`Φ` gravitational potential [J kg⁻¹]. Thus it uses internal, kinetic and
potential energy under the configured Thermodynamics reference. The currently
commented SGS kinetic/TKE additions are not additional parent energy. Do not
add `ρtke`, source tags, copies or records to the total. Archive the parameter
values, Thermodynamics version, gravity/geopotential convention and Manifest.
A reconstructed thermodynamic total is a consistency check, not a replacement
for the prognostic parent in a budget.

For the tags only,

```math
E_c = \rho e_{\rm tot} + c\rho,\qquad
\Delta E_c = \Delta(\rho e_{\rm tot}) + c\Delta\rho .
```

`c` is a constant specific offset [J kg⁻¹], `ρ` moist-air density [kg m⁻³],
and `E_c` energy density [J m⁻³]. Positive increments add represented energy.
Negative increments remove it. The configured offset changes diagnostic
representation only: every parent field must remain bitwise identical to the same untagged twin under the default solver of the [fork parity rule](../../../docs/clima_atmos_specific.md#fork-parity-with-upstream). Moving the parent's thermodynamic reference is a different
model operation and is outside this contract. Use `c = 110,495 J kg⁻¹` as the
existing candidate for conditional source-tag tests. OD11's fixed convention
remains proposed until the owner resolves it. No value of `c` is qualified for
all temperatures or configurations.

**Mass is not water.** For the source tags, a process's applied-update event
gives `δp = δp^ρe + c δp^ρ` [J m⁻³ s⁻¹], from its `ρe_tot` and `ρ` tendencies.
It does not substitute the total-water tendency `δp^ρq`. A water record may
stand for the mass part only after a process-specific discrete proof that `δp^ρ = δp^ρq` at the same stage, including any final maps. Subsidence, large-scale advection and external forcing change water while their implemented mass contribution is zero. General `c Δρq_tot` accounting is therefore invalid. The original contract's generic water-record substitution is corrected here. D4's identities I and II take `cΔρ` from the attributed processes and the `c`/`2c` pair, so this does not affect them. D4's third C4 measure, `c·(ΔM − Σ_p P_q,p − (−∫pr dt))`, uses the water records as mass, with subsidence among them, so it is not a mass estimate. E87's record-based estimate and its sign are therefore not evidence under this rule. Both files stay as recorded.

Changing `c` changes initial masked inventories, donor fractions, the sign
split of a mass-changing source and admissibility/headroom. It can change
source labels substantially while the parent trajectory is unchanged: doubling `c` moved the region tags' integrals by 152% and 177% (E71).
The discrete source throughput changes with `c` too. Its accumulator has no `c`, but each ledger increment carries `cΔρ` and each share divides by `E_c`. On E87's D4 pair, Θx at `2c` is 1.7% above Θx at `c` at 1, 6 and 24 h. The records, and so Θi, have no `c`. OD4 avoids dividing
by the large offset inventory. Its historical name "offset-invariant units"
is not a proof that the accumulator is invariant under changing `c`. Compare
fixed-convention tests at the same `c`. An offset sweep measures convention
dependence, not an independent origin reference or an uncertainty bound.

### 2.2 Partition, overlays, sources and losses

Let `a_k = ρe_src_k`, `P` the pure region tags (a region and no source list),
and `O` the source-labelled overlays (possibly also region-masked). Exactly
one verified complementary partition is required for partition claims.
Overlays can overlap each other and the partition. They never enter
`Σ_P a_k` or OD4's partition-throughput sum.

A pure region tag initializes as `a_k(0) = M_k E_c(0)`. Source overlays
initialize at zero. At later entry, a pure region tag receives every attributed source's gain through its current Eulerian mask, not just the initial energy.
A source overlay receives gains only for its declared process labels, by its
mask or weight one if region-less. Loss applies to every tag regardless of its
source list. With `w_kp` that production weight and `δp` the process's tendency of `E_c`,

```math
\dot a_{k,p}=w_{kp}\max(\delta_p,0)+\phi_k\min(\delta_p,0),
\qquad \phi_k=\operatorname{clamp}(a_k/E_c,0,1)\quad(E_c>0).
```

For `E_c ≤ 0` the code returns zero share. Stored positive-energy ancestry is
then undefined. A signed field still exists but does not justify that claim.
For a negative tag with positive `E_c`, the clipped share also changes loss
allocation: logging or later repair does not restore correct historical
attribution. Zero inventory has zero donor share, not a fabricated origin.
The finite-step loss and unlimited tracer transport do not themselves ensure
nonnegative tags.

Define `R = E_c − Σ_P a_k`. An applied-update event contributes

```math
\dot L_{R,p}=\delta_p-\sum_{k\in P}\dot a_{k,p}
=(1-\sum_P M_k)\delta_p^+-(1-\sum_P\phi_k)\delta_p^- .
```

Here `δp⁺ = max(δp,0)` and `δp⁻ = max(−δp,0)`. On a verified partition with
valid unclipped shares this becomes `−(R/E_c)δp⁻`. Calling it a residual flush
requires those conditions. Otherwise it also contains gaps, overlaps or
clamping. The residual report's settling forecast is descriptive, not an
acceptance verdict or a residence time.

### 2.3 Transport, boundary exchange and numerical intervention

Declare the transport mode with every result. `tracer` uses the generic
tracer transport and may differ from the parent's enthalpy/pressure-work
transport. `enthalpy` takes donor shares of the parent's energy flux.
`enthalpy_increment` also follows the post-Newton implicit increment using a
column redistribution. The SGS exchange, plume reconstruction and copies
introduce additional declared rules. Shared use of those rules cannot
independently validate them. Partition transport shares renormalize the
clipped fractions over partition members. Overlays keep their own clipped
fraction. Denote the actual transport share by `ψ_k` and distinguish it from
the source/loss fraction `φ_k`. Zero share normalization returns zero in the
current code. It is not a valid donor assignment. Counting/locating that
fallback is required evidence but is not exposed by the current audit.
Parts 4/5/11b own the missing counter or gated diagnostic probe.

For a flux-based process, upward-positive energy flux `F_E` and mass flux
`F_M` give `F_c = F_E + c F_M` [W m⁻²]. On a stated control volume `V`,

```math
\Delta\int_V E_c\,dV
=-\int_{t_0}^{t_1}\!\oint_{\partial V}F_c\cdot n\,dA\,dt
+\int_{t_0}^{t_1}\!\int_V S_c\,dV\,dt+Q_{\rm maps}+X_c .
```

Internal conservative transfers cancel in this integral, but can change local
label composition. Sources/sinks `S_c`, boundary exchanges, numerical maps
`Q_maps` and unresolved `X_c` remain separate. Apply this equation to the
actual discrete control volume and stage weights, not an assumed positive
substance. Falling condensate can carry negative reference-plus-offset
energy. The energy donor can then be the lower cell even while water falls.
For the energy source tags, `precipitation` sedimentation is transport, not an
attributed source. The tags' share of its flux is `F_E + cF_M`, so the offset
leaves with the falling mass and adds nothing to `e_src_res`. 0M rainout is the
`microphysics` source. At the surface the bottom donor
convention still requires verification. Do not infer energy flux from a
water precipitation rate without its specific energy and reference.

Where `E_c > 0`, partition repair clips negative tags and rescales the positive
ones so that the partition keeps its pre-repair sum. If that sum is negative it
zeroes every tag. There overlay repair clips a negative value and can add
overlay inventory. Where `E_c ≤ 0` the tags are left as they are. Neither
writes a parent source. The parent budget declares the repair the final map
`map.repair_energy_source_tags`, invariant zero for mass, water and energy. Repair does not force the partition to equal `E_c`.
Report partition transfer, any sum change and overlay intervention separately.
G4.4's A5, as decided, compares each overlay with the **partition's sum**. G4.6's A5 is a different check: C4's two measures (below).

The current energy follower spreads the column's unmovable mismatch by `|m|`,
then represents the zero-column-total remainder as a flux with zero end-face
values. Its signed left-out and moved ledgers are histories, not accumulated
activity. OD7's same-sign alternative remains unchosen. Water's choice is not
inherited. Positive `E_c`, donor availability, share-normalization fallbacks,
solver/stage support and sufficient headroom are explicit prerequisites.

An implementable tag balance is

```math
\Delta a_k=\Delta L_{{\rm src},k}+T_k+C_{{\rm inc},k}
+C_{{\rm repair},k}+X_k .
```

All terms are accepted amounts [J m⁻³], not rates. `T_k` contains physical
transport/exchange, including boundary transfer, and `X_k` names missing
accounting. Shared terms must not be counted twice. The existing ledgers do
not resolve every `T_k` independently: Part 4 declares that gap and Part 11a
supplies independent same-state references where appropriate.

### 2.4 Records and parent-budget identities

Write `P_p(t) = prc_e_p(t)` [J m⁻³]. Its tendency is `δp^ρe` alone, the process's signed `ρe_tot` tendency without `c δp^ρ`, integrated by the actual stage weights. For a mass-changing process `ΔP_p` is therefore not the tags' `∫δp`. Records are unmasked,
not transported, and cumulative from zero. The output is
`e_prc_p(t) = P_p(t)/ρ(t)` [J kg⁻¹]. Therefore a window amount is

```math
\Delta P_p=\rho(t_1)e_{{\rm prc},p}(t_1)
-\rho(t_0)e_{{\rm prc},p}(t_0).
```

`ρ(t1)[e_prc(t1) − e_prc(t0)]` is a different quantity if density changes.
Use the same conversion before differencing tag ledgers and any cumulative
specific output. A mean record is not an interval increment. Signed net
records cannot recover gross opposing activity or an unrecorded process.
An implicit record lacks the parent's cross coupling, so the accepted parent
update can differ at a finite Newton count. Name and measure that remainder.

For a supported parent-budget control volume and quantity, the primary
identity is `R_parent = ΔB − Σ_channels Q_envelope − Σ_maps Q_final_map` and each
channel has `R_attribution = Q_envelope − Σ_events Q_event`. These are extensive
amounts, with schema-derived expectations, accepted weights and separate
status for missing terms. An envelope and its decomposition are compared,
never added together. The parent budget's energy is `ρe_tot`, without `cρ`. It claims levels 1 to 4 of its contract. Level 6, attribution to an origin, is excluded there.
Its own contract, coverage registry and calibrated tolerances remain the
normative authority. It refuses EDMF. It makes domain/control-volume
integrals, not a layer-wise component-energy budget. Current custom-callback
support is `ReadOnlyCallback` only. Accounted state-writing callbacks are
not implemented despite the more general contract wording.

G4.6's offline D4 identities remain useful, with endpoint differences of all
cumulative terms over the chosen window:
`ΔR = ΔL_R + ΔI − ΔF_S + X_II`, and for its column
`ΔE_c = ΔB_src + ΔP_e,precipitation + c M_U + X_I`.
`B_src = Σ_P L_src,k + L_R` (`B` in D4_PROCESS_BUDGET). `F_S` is the repair's partition-sum change, not gross
repair. `I` is the follower's signed left-out ledger. Terms and signs are in
[D4_PROCESS_BUDGET](D4_PROCESS_BUDGET.md). Their reconstruction does not
identify origins. `X_I` includes unattributed energy and the implicit lag and cannot
be silently labelled physical production.

C4 is `c` times the mass change of processes the tags do not attribute. With
bitwise-identical parents and complete attributed sums, the `c`/`2c` pair gives
`cM_U = cΔM − [ΔB_src(2c) − ΔB_src(c)]`. Over a column, `M_U` holds every mass
change outside an attributed process. That includes sedimentation's exit
through the surface, whose `cF_M` the tags carry as transport. Mass moved
inside the column integrates to zero there, so per-layer evidence (identity II
and `I(2c) − I(c)`) is needed for it. E87 found −1.15e5 J m⁻²/day, 0.55% of the
day's Θx, and its G4.6 A5 check failed. On E87's archived output `M_U` is
−1.040 kg m⁻² and the day's surface precipitation −1.038 kg m⁻², so that size
is almost entirely the precipitation's offset. The owner accepted this reading on
2026-10-07 as an amendment to E87 (DECISIONS, EA-C4). On E87 the genuine
per-layer C4 is about 1.2e-5 of Θx, and the single-column argument does not
extend to the sphere, where columns exchange mass. The owner decided 2026-10-02 to document C4's size,
not distribute it as transport. Repeat the measurement on the stated post-#139
case with `c·∫pr dt` separated. Never present the historical number as a bound.

## 3. One first useful energy workflow: a signed radiation record

**Decided 2026-10-07 (EA-USE): the record stays an unqualified diagnostic, verified in part 11a and reported. Nothing in this section qualifies.** The proposal was to answer "where and how much did the
implemented radiation heat or cool this column over the day?" First qualify
one signed `radiation` process record, rather than require the full stored
source-attribution workflow before obtaining a useful energy diagnostic.
This is a process-increment question, not an inventory or surface-origin claim.

Use C3/C5's DYCOMS RF02 geometry as a scaffold: non-EDMF column, 0M moist
microphysics, DYCOMS radiation, 0–1500 m, 30 uniform layers, Float64,
`dt = 10 s`, 24 h, ARS343, fixed Newton count with direct block solve, no
Krylov/adaptive residual stopping. Explicitly record every resolved key,
forcing, boundary and solver option. Old configs are not current evidence.
Set `energy_process_record: [radiation]`. **Zero source tags/copies**, hence
no offset inventory, energy follower or per-tag intervention claim. The
record's target is `ρe_tot` at the parent's unchanged Thermodynamics reference.
The later stored-tag candidate retains fixed `c = 110,495 J kg⁻¹` and OD11.
This proposal changes no repository default or production target.

Output instantaneous `e_prc_radiation`, `rhoa`, vertical coordinates/weights,
parent validity fields and parity outputs. The independent reference needs
radiative face fluxes or independently reconstructed fluxes on captured
stage states, with the accepted stage weights. For flat-column radiation,
`dot P_rad = −D_z F_rad`. Column-integrated change is the accepted integral of
`F_bottom − F_top`. Positive is heating. A copied applied-update event is not independent.
An independently coded divergence/flux integral verifies the record against
the implemented radiation. Reusing the model's face flux verifies the event capture and integration, not the radiation parameterization. Validating that
parameterization against atmospheric observations is a separate claim.

Use OD2's untagged-parent startup rule, report startup separately and include
the decided 1 h sensitivity row. Score the established window only if it
exists. OD2's approved DYCOMS 0M row lists none. The 24 h window here is the
verification window (EA-USE, 2026-10-07), not a scored one. Do not infer that cloud-top cooling ends startup. Keep native layer
weights. Report per-layer J m⁻², J kg⁻¹ profiles, column J m⁻² and window mean
W m⁻² with their conversions. Hourly records alone do not resolve accepted
stage fluxes. Part 11a designs the minimal capture/reference evidence before
execution. Radiation-only records cannot close all parent energy: 0M rainout,
transport, surface exchange and numerical maps remain potential contributors
even without EDMF. No total-budget or no-rain claim is made by leaving them
unrecorded. The parent budget's flux-form legs `xfer.radiation_toa` and `xfer.radiation_surface` already measure the accepted column exchange from the model's own flux. Part 11a may reuse them to check the record's integration and weights. They share the model's flux, so they do not verify the radiation parameterization. This initial workflow does not require them.

C3/E7–E9 and C5/E22 supply historical operational and interpretation evidence,
not post-#139 qualification of this proposed setup. `test/process_record_integration.jl` runs this column with radiation and surface-flux records and no tags for two steps. It checks `isequal` parity of every model field, the records' checkpoint restoration and zero allocations. Missing for this workflow: 24 h parity, record-versus-independent-flux evidence, sampling/refinement floor, continuous-versus-restarted continuity, accuracy rationale and cost. One record and no transported
tags make it a simpler first deliverable than an 8-tag EDMF copies campaign.
It excludes stored-energy origins, all-process closure, EDMF/1M/2M/P3
qualification, sphere/long-run/device qualification and causal effects. The
full G4 source-origin goal remains in Parts 11a–d and 12. A radiative
record pass cannot be promoted to a stored-origin pass. Every setting in this section is the verification setup under EA-USE (decided 2026-10-07, an unqualified diagnostic), not a qualified configuration.

## 4. Observable, window and normalization specification

### 4.1 Sampling and weights

For a native column, `⟨u⟩ = Σ_i dz_i u_i` is per unit horizontal area. Energy
amounts are J m⁻². For a native sphere use exact discrete cell-volume weights
`Σ_i V_i u_i` [J]. For regional/boundary quantities declare masks and face
areas. Current remapped sphere NetCDF integrals in `od4_restate.py` are
approximate. They cannot be substituted for native budget integrals without a
measured remap floor and consistent eligibility. Never mix J and J m⁻².

Every scalar includes its numerator, denominator, units, `c`, tag/label set,
mode, spatial weights, interval and sample coverage. Use OD2 windows fixed
from the untagged parent before scoring, with the 1 h sensitivity row from
2026-10-02. At every expected endpoint require aligned timestamps, fields,
geometry and no duplicates/gaps. Cumulative outputs are instantaneous.
Difference two endpoints for interval amounts. A rate is an amount divided
by physical elapsed time, never by output count. A per-day ratio explicitly
uses `days = (t1 − t0)/86400`. Changing cadence does not change that duration.

### 4.2 OD4 exact and interim scales, without cancellation ambiguity

For partition-tag source ledger `L_k` at accepted step `n`, define the current
approved **discrete** accumulator and its window value as

```math
H_x(t)=\sum_{n\le t}\sum_{k\in P}\langle|L_k^n-L_k^{n-1}|\rangle,
\qquad \Theta_x(W)=H_x(t_1)-H_x(t_0).
```

Absolute value is taken cellwise **after** accepted-step integration of a
single tag's signed source ledger, **before** spatial, tag and step sums.
It excludes overlays, the residual ledger, transport and repair. Opposing
processes/stages in one cell and step can cancel first. It counts accepted
source-ledger variation, not every positive physical source event. This is
what OD4's "exact per-tag, per-step" quantity means. Do not claim a more
finely resolved gross. `source_partition_valid: 1`, finite values and `energy_source_tag_ledger_per_tag: true` are needed. Each tag's own source ledger is exact at every `update_constrain_state_every` cadence. Only the mechanism ledgers need `step`.
Invalid masks yield `source_throughput: NaN`. The internal scale may still
exist for such masks, but cannot qualify a whole-partition percentage.

The approved offline **interim estimate** actually computed is

```math
\Theta_i(W)=\sum_p\sum_{j\in W}\langle
\rho_j\,|e_{{\rm prc},p}(t_j)-e_{{\rm prc},p}(t_{j-1})|\rangle .
```

`od4_restate.py` lists radiation, surface flux, subsidence, microphysics,
large-scale advection, external forcing and held-Suarez. It excludes
`precipitation`, and currently skips missing files. `g411_eligibility.py`
uses only the first four. Absolute value follows cancellation within an
output interval for each process but precedes space/process/interval sums.
Neither is `Θx`. Both omit `cΔρ`. They also difference specific records with
end density, rather than the density-weighted interval identity in 2.4.
Archive the process roster and legacy algorithm with old findings. Missing
active records make a new interim score not assessable. Part 4 implements
and names any corrected record estimate. It must not silently rescore history
or keep a legacy denominator name for a changed calculation.

The runtime fallback for `ledger_parent_scale` is yet another estimate,
`Σ_all configured p ⟨|prc_e_p(t)|⟩`: net from run start and including any
configured precipitation record. It is not the offline window `Θi`. Name
that algorithm if encountered. Require a valid exact `Θx` for new tag
acceptance. For exact and interim comparisons, list process, offset and
cancellation differences first. E84's roughly 6% discrepancy does not prove
which is erroneous. The decided rule stands: use `Θx` wherever available.
A legacy `Θi` percentage is an estimate, never a lower/upper bound, and a
verdict within 10% of its threshold waits for exact evidence. Part 5 adds
finer accepted correction/source activity only if the evidence needs it.
The approved discrete scale is preserved until an owner amendment.

### 4.3 Residual state, interventions and small tags

Let `N(t)=⟨R(t)⟩`, `G(t)=⟨|R(t)|⟩`. The report contains both endpoints,
`max_W G`, `ΔN`, `ΔG`, and `⟨|R(t1)−R(t0)|⟩`, each distinguished. The
approved windowed closure reading remains `ΔG(W)/Θx(W)`, with the
end-state amount reported beside it (the original contract and
[CLOSURE_LEVELS](CLOSURE_LEVELS.md)). A small or negative `ΔG` can pass that
growth row while a large residual persists. Report that distinction and
never infer a small present defect or valid origins from the growth pass.
`G(t1)/Θx(W)` and `max_W G/Θx(W)` are additional state reports, not a silent
application of the approved growth tolerance. The closure table's `gross_over_throughput`, which `throughput_tolerance` checks, is `G(t)/H_x(t)` from the run start, which is neither reading. **EA-STATE** proposes whether
a new stored-inventory claim needs a separately approved state criterion
and how startup offsets are treated. No such number is approved here.
`g411_eligibility.py` still lacks the complete state/activity interpretation.
Long-run ceilings retain
OD6's state interpretation and smallest-tag rule, separately from growth.
Do not invent a finite percentage at zero throughput: `Θx = 0` makes the
percentage not assessable, with absolute amounts reported. Any absolute
floor/tolerance must be fixed before the run. Near-zero scales require a
reference floor and owner-approved absolute rule, not an arbitrary epsilon.

For correction mechanism `m`, keep three different amounts: signed ledger
change `ΔC_m`, retained cell-step variation
`J_m(W)=Σ_n⟨|C_m^n−C_m^(n−1)|⟩` and attempted gross over every writer call,
including discarded stage work. A column-gross accumulator takes absolute
value after the column integral and can hide vertical cancellation. `fixgross`
counts per-application repair activity and may include discarded work.
Partition repair transfers count both donor and receiver, so any half-gross
"moved" convention must be declared. Retained variation can still hide
opposing within-step applications. Part 5's accepted-application activity
is needed to exclude that cancellation, rather than assume existing gross
columns do it. None of these is a propagated attribution-error bound without
independent errors, complete mechanisms and a justified stability/amplification
estimate. PX22's factor-two repair exposure remains a screen, not a bound.

For tag `k` at an endpoint, use signed inventory `A_k=⟨a_k⟩` and absolute
burden `B_k=⟨|a_k|⟩`. The approved per-tag repair rule uses
`J_fix,k(W)/A_k(t1)` for a pure region tag, with **positive inventory** as
precondition, and `J_fix,k(W)/B_k(t1)` for a source-labelled/signed tag. Report
both ratios and the parent-scale ratio. Nonpositive region inventory does
not become an absolute-burden pass for its positive-inventory claim.
The approved small-tag exemption uses the burden below the small-tag fraction
of the OD4 scale: state explicitly "not applicable", report absolute repair
and its parent-scale ratio, and retain the provenance small-tag row. Runtime
ratios use cumulative-from-start scale and retained totals, so Part 4 must
recompute window ratios from the numerator endpoints and `Θx(W)`. Do not
subtract two pre-normalized ratios. Nonfinite inputs or absent valid scale
are missing prerequisites, not small-tag exemptions. `led_inc` is reported
and judged through its existing refinement rule, not a new repair threshold.

For an eligible fixed-convention **same-parent** reference `a*_k`, define
`χ_k=a_k/ρ`, `χ*_k=a*_k/ρ` [J kg⁻¹],
`L1_k=⟨|a_k−a*_k|⟩/⟨|a*_k|⟩` and
`L∞_k=max|χ_k−χ*_k|/max|χ*_k|` on matched samples/weights.
L∞ uses the specific field peak, as the existing endpoint scorer does.
L1 equals the density-weighted specific-field integral when the density is
the same. Do not apply a second density factor to density fields.
For the approved small-source reading, the reference inventory share
`S_k=⟨a*_k⟩/Σ_P⟨a*_i⟩` is below the approved 1% partition-share cutoff,
with positive reference partition sum.
Then absolute `⟨|a_k−a*_k|⟩/Θx(W)` replaces both relative tests. Report its
raw amount and maximum. A zero reference is small, with undefined relative
ratios reported. Signed or nonpositive reference holdings violate the
positive stored-origin reference precondition. They do not silently become
small positive tags. This origin-row cutoff differs from the per-tag
intervention exemption, whose burden cutoff is in OD4 units.
The approved process-weighted metric is
`Σ_s |Q_p,s| |φ_k,s−φ*_k,s| / Σ_s |Q_p,s|`: `Q_p,s` is the process amount
in the stated sample/control volume including its spatial/temporal weight,
and `φ` the declared same-parent energy fraction. Preregister the process,
stage/output convention and weights. Absolute error belongs **inside** the
weighted sum. Zero process activity makes that weighted test explicitly
inapplicable, not an origin pass. An active process with missing samples
is not assessable. The existing endpoint scorers do not supply this evidence.

### 4.4 Restart continuity

Carry source/correction accumulators and signed state ledgers through the
checkpoint. Initialize previous-ledger snapshots from the restored state so
the restored amount is not recounted. The first post-restart audit can share
the checkpoint timestamp: deduplicate that row, preserve the offset and
label roster, verify finite monotone gross totals and exact checkpoint
continuity. Cumulative row differences span segments only when the restored
values agree. A reset requires explicit segment-local offsets reconstructed
from archived checkpoints, not stitching each new zero as if nothing happened.
Residual-report rate/settling columns on the first row after restart can be
`NaN`. That does not permit missing accumulated evidence. Part 4 owns stitching
and Part 11b the matched continuous/restarted qualification evidence. For the record-only pilot only the records apply. They are prognostic fields that the checkpoint restores, and a restart refuses a file that lacks a configured record (`energy_source_checkpoint.jl`). Its continuity evidence is a continuous-versus-restarted comparison of `prc_e_radiation` and the parent.

## 5. Energy acceptance matrix

Each row reports **pass**, **fail** or **not assessable**, with the missing
prerequisite and downstream destination named. **Explicitly inapplicable**
is a scope annotation, not a pass: for example stored-source rows in the
radiation-record-only pilot. A claimed source workflow cannot waive those
rows by deleting the claim after inspecting failure. Freeze applicability,
metrics, normalization and owner approvals before the deciding evidence. Where a row has a choice of number, such as a window, arm, rung or tag, it reports the least favourable one. Where a control changes more than one thing, it reports the bound the control sets, not a cause.

Equations/weights/windows in sections 2 and 4 apply to every row. The table
links approved threshold ownership without duplicating its numeric table.

| Row and applicability                                                                                 | Observable, units and weighting                                                                                                                                                                                                                    | Evidence, independence and existing implementation                                                                                                                                                                        | Threshold source and rationale                                                                                                                                                                                              | Missing-evidence consequence/destination                                                                                                                                                                                      |
|:----------------------------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Parent parity: every configured diagnostic                                                            | `isequal` on every parent field on the same native grid/machine/precision/process count at matched accepted endpoints.                                                                                                                             | Untagged twin. Include signed zeros, not only exported `ta`. `analysis/evidence/compare_runs.py` and integration tests are starting surfaces, not proof for every config.                                                 | Fork parity rule, under its default solver (fixed Newton count, direct block solve), and OD3 parity. Diagnostics must leave parent unchanged.                                                                               | Difference fails/voids dependent claims. Absent fields/twin not assessable. Part 4 completeness and 11b actual baseline. Any fix in 11c.                                                                                      |
| Parent physical/numerical validity: every scientific claim                                            | OD3 temperature/negative-water checks on the actual parent. Energy-tag headroom `min(E_c/ρ)` and nonpositive/negative-tag locations. Parent one-step Newton error separately.                                                                      | Untagged parent, native fields and same-parent fixed-state probe. Newton row gates different-parent comparisons under its decided scope. A same-parent construction does not establish physical realism.                  | OD3 validity and revised Newton row. Positive headroom is required for positive stored-energy ancestry, not imposed on a signed record.                                                                                     | Parent-invalid relevant claims void. Missing coverage not assessable. Part 11b. Missing energy admissibility choice EA-USE/EA-ACCURACY.                                                                                       |
| Partition closure: configured source partition                                                        | `N`, approved `ΔG(W)/Θx(W)` growth reading plus unscored endpoint/max state reports in 4.3. Column J m⁻² or sphere J, with local maxima.                                                                                                           | Native closure table and residual fields. `od4_restate.py`/`g411_eligibility.py` need state/window and completeness reconciliation. No reference required for accounting. Closure never checks origins.                   | OD3 energy closure, OD4 exact units and existing window-growth reading. No extra state criterion (EA-STATE, 2026-10-07). Growth-only scoring, state reported. A growth pass is not a small-state or provenance certificate. | Approved growth excess fails. Absent valid scale/partition/window not assessable. Report any persistent state independently. Additional state acceptance waits for EA-STATE. Part 4 scorer, 5 missing activity, 11b baseline. |
| Record reconstruction: radiation pilot and named recorded processes                                   | `ΔP_p` in 2.4, signed profiles and column amount. Independent accepted-stage integral. Report difference and floor, then flux-equivalent window mean [W m⁻²].                                                                                      | Independently integrated radiation face flux/divergence or known-forcing reference. Current hourly endpoints do not supply stage integral. Any implicit coupling remainder reported apart.                                | No use-specific record accuracy threshold. The record is not qualified (EA-USE, 2026-10-07), so EA-ACCURACY lapses unless the owner reopens the pilot. Existing G4.6 A1–A5 retain their own preregistered limits.           | Numeric agreement alone is reported until threshold/reference eligible. Missing stage evidence not assessable. Parts 11a/11b. Minimal capture only after design.                                                              |
| Parent-budget reconstruction: explicitly commissioned budget claims on supported control volumes only | `R_parent`, `R_attribution` in 2.4 per accepted step/window [J], complete schema and calibrated roundoff scale. Offline D4 `X_I/X_II` remain separate.                                                                                             | Parent budget contract, coverage registry and journal certificates. Cannot use endpoint subtraction as envelope evidence. EDMF rejected, so budget is not assessable there, not zero.                                     | Parent-budget contract calibrated tolerance and G4.6 design for the separate offline identities. Correct accounting and coverage, not origin truth.                                                                         | No commissioned budget means explicitly inapplicable (including the record-only pilot). A claimed budget with blocked/failed coverage cannot pass. No EDMF promotion. Parts 4/11b, bounded fix 11c only if justified.         |
| Generic reference eligibility: every reference-based verdict, including the record pilot              | Independent mechanism roster, same-state or declared parent error, captured accepted weights, matched fields/geometry/windows, stage/quadrature/refinement floors and measured inactive exclusions. No Θx is needed for a signed-record reference. | Known forcing/independently integrated radiative flux solution for pilot. Independently known labels for stored origins. Shared face flux tests the record integration only, not radiation physics.                       | OD12 accepted floors/active nonshared-rule restrictions. Pilot budget needs EA-ACCURACY. Missing reference or unmeasured floor cannot pass.                                                                                 | Ineligible reference makes its dependent claim not assessable. Part 11a design/floors, Part 11b integrated case evidence.                                                                                                     |
| Source-comparator eligibility: stored-source comparisons only                                         | Comparator `G*`, retained repair/Θx per day, dt/Newton refinement, required active mirrors and sedimentation cross blocks, in addition to generic floors.                                                                                          | E84 copies ineligible on D4. `e_src_copy_res=ρaʲ(Aʲ−Σ_Pχʲ)/ρ`, `Aʲ=mseʲ+Kʲ−p/ρʲ+c`, is a net residual, not a bound on omitted terms. Complete mirrors alone do not establish independence or eligibility.                 | OD3 comparator rows and OD12 active nonshared-rule eligibility. Inapplicable to the zero-tag radiation-record pilot.                                                                                                        | Ineligible comparator makes dependent provenance not assessable, never fail/pass against it as truth. Part 11a eligibility, 11b integrations. Bounded missing-mechanism fix only where evidenced.                             |
| Per-tag provenance: claimed stored-origin rules only                                                  | Per-tag L1/L∞ and approved small-source absolute metric in 4.3, fixed `c`, endpoint/window and process weighting.                                                                                                                                  | Eligible independent known-label/reference cases. Declare shared operators/allocation rules. Copies test only active nonshared SGS rules, not every origin. Wrong-origin assignment must be detected despite exact total. | OD3 approved endpoint rows and small-source rule. Proposed OD9–11 labels remain proposals. Different window/use needs owner rationale, not transplanting a 24 h threshold.                                                  | Excess fails. Absent eligible independent rule coverage not assessable (read with the decision of 2026-10-07: reported, not a gate until OD9). Part 11a references, 11d scoped qualification.                                 |
| Numerical intervention: all configured source/repair/follower mechanisms                              | `J_fix/Θx/days`, per-tag ratios, `J_inc`, attempts/retained/events, zero-normalization/clamp/fallback counts and cancelling activity, in 4.3.                                                                                                      | Accepted-step ledgers plus missing accepted-application accounting. Do not equate signed ledger balance with correction activity, or activity with attribution error.                                                     | OD3 per-tag row. Energy aggregate level is still waiting under seven-point point 2. `led_inc` judged by refinement. Warning levels stay separate.                                                                           | Per-tag breach fails. Missing energy aggregate approval/activity not assessable for full intervention claim. Part 5 accounting. 11b evidence. Owner levels then 11d.                                                          |
| Convergence: declared numerics/rules                                                                  | Repair and `inc_left` throughput rates at refined dt/Newton. Fixed-parent per-tag trial error. Configuration differences reported separately.                                                                                                      | Same-parent fixed-state reference for tag error, full-run ladders for atmosphere sensitivity. Label every rate's scale/window. Existing E76 is historical, net repair cannot prove cumulative refinement.                 | OD3 refinement and comparator refinement (different rows). Floors from OD12. Do not require sign-rule linearity absent evidence.                                                                                            | Failure retains structural cause. Missing ladder not assessable. Part 11a isolated tests and 11b post-#139 ladders. Fixes only in 11c.                                                                                        |
| Aggregation: 8-tag/grouped source workflows                                                           | Same-parent grouping of fields against explicit group run, relative max error with normalization and any small group reported.                                                                                                                     | Known label groups. Explicitly preserve source-overlay semantics. OD7 sign dependence can create nonlinearity.                                                                                                            | OD3/OD8 aggregation is reported, not a new qualification threshold. Original stated comparison retained.                                                                                                                    | Missing planned comparison not assessable/reported missing. No pass substituted from closure. Parts 11a/11b.                                                                                                                  |
| Reproducibility/restart: every qualified scope                                                        | SHA/config/Manifest, verifier, machine-readable result. Continuous-versus-restarted parents, tags/records and all gross/signed accumulators at matched samples.                                                                                    | Source manifest and checkpoint identity. Capture expected missing fields and exact segment stitching. Existing integration tests only cover their named setups.                                                           | Common reproducibility completeness and fork invariance. Pilot-specific continuation evidence must match scope.                                                                                                             | Incomplete evidence fails completeness or makes continuity not assessable. Part 4 archive/schema and 11b workflow evidence.                                                                                                   |
| Runtime/allocations/memory: every proposed default or qualified operating scope                       | Warm accepted-step time, build/startup time, allocations and peak memory on matched hardware, same output/cadence, record/tag count. Include comparator cost.                                                                                      | WP9 measured baselines at intended count. Count 0 source tags/1 record for pilot, OD8 count for full G4. Prior cost is not current measurement.                                                                           | OD3 approved full-target cost rows and WP9. No pilot cap (EA-COST lapsed with EA-USE, 2026-10-07). Rationales are feasible resource use, fixed before choice.                                                               | Breach fails chosen cap. Missing cap/measurement not assessable. Part 11b cost, Part 12 expanded range, before default selection.                                                                                             |

**Overall acceptance.** A declared scientific workflow passes only when all
applicable scored rows and eligibility prerequisites pass and required
reported evidence is complete. Missing approval/reference/data is not
assessable, never a zero or a compensating pass. The initial record-only
workflow can be accepted solely for its signed record question, with source
rows explicitly inapplicable before scoring. It cannot claim validated
provenance. Full stored-source qualification additionally needs independent
coverage for every named active origin rule. Read with the decision of
2026-10-07, that coverage is reported, not a gate until OD9. OD5's decided exception and
Insight 10 tests retain the historical label "provenance bounded, not
validated" under their existing rules. Report that exact conditional outcome
separately, without a mathematical bound or elevation to attribution tested.
OD9–11 can only be adopted by the owner.

Distinguish **implementation verification** of equations and bookkeeping,
**validation of the declared label model** against independent known labels,
and **evidence for atmospheric origins**. A reference implementing the same
donor-allocation convention verifies consistency with it. It does not prove
that the convention uniquely represents real atmospheric origins.

## 6. Discriminating reference work for later parts

Part 11a designs the smallest cases below before execution. Each freezes its
reference, floor and scoring window, lists shared parent physics/operators,
and measures excluded processes inactive under OD12. Require precision and
dt refinement or an exact discrete counterpart. Reference error consumes
OD12's floor allowance rather than being tuned away. These designs are not
newly authorized simulations.

| Case                                                    | Tested identity/reference and independent mechanism                                                                                                                                                                    | Deliberate wrong implementation it must detect                                                                    | Floor/refinement and excluded production claims                                                                                                   |
|:------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------- |
| Two known heating labels with distinct footprints       | Independent labelled reservoir solution, `dot a_k=S_k` with positive heating rate `S_k` [J m⁻³ s⁻¹]. Analytic initial mask plus integrated additions. Shared parent trajectory declared. Independent origin allocator. | Swap origins or apply the wrong mask while preserving `Σ a`.                                                      | Exact forcing/initialization, Float64 then Float32 floor and step ladder. Does not qualify real radiation/EDMF.                                   |
| Known cooling of differently labelled holdings          | Independent solution `a_k(t)=a_k(0) E(t)/E(0)` for pure donor loss with positive energy and no other terms.                                                                                                            | Charge the cooling-process tag alone, or clip/reassign energy silently.                                           | Bound inventory/headroom and finite-step error. Empty/signed states separate. Tests declared donor rule, not physical uniqueness.                 |
| Exchange/transport between labelled reservoirs          | Independent face-volume transfer with known donor, boundary sign and conservation. `dot a_k=−div(F_c ψ_donor,k)` in supported positive-share conditions.                                                               | Wrong donor with exact total closure, swapped flux direction, missing label transport.                            | Refine independent operator and remove numerical floors. Shared flux only tests attribution. No full plume/EDMF/pressure-work validation.         |
| Boundary mass/energy exchange at fixed `c`              | Independently prescribed `Q_E+cQ_M`, including negative energy carried by falling mass and surface exit. Prove mass/water identity only in that case.                                                                  | Replace mass with water globally, omit offset flux, choose the water donor for negative energy.                   | Stage/face quadrature floor and timestep ladder. Synthetic boundary case not full moist microphysics.                                             |
| Opposing processes, net zero                            | Distinct `+Q`/`−Q` process records and independent labelled inventories, with nonzero gross activity. Compare finer application activity with accepted-step Θx.                                                        | Collapse processes first or call Θx the gross of all events. Signed closing ledger falsely read as zero activity. | Exact discrete cancellation and temporal grouping sweep. No atmospheric qualification from cancellation identity.                                 |
| Change `c` on an identical parent                       | Independent `ΔE_c=Δρe_tot+cΔρ`, expected tag initialization/source-sign changes, fixed-reference thermodynamics.                                                                                                       | Change parent fields, claim invariant fractions, or interpret spread as error bound.                              | Require bitwise parent parity. Pure representation test, not an independent provenance reference.                                                 |
| Empty/small/signed inventory and cancelling corrections | Independent admissibility/normalization classification. Correction pairs whose signed ledger closes but accepted-application activity is nonzero.                                                                      | Epsilon-denominator pass, illegal region-burden pass, hidden repair/follower activity, duplicated restart gross.  | Exact edge cases then finite floors. Exercises guards and accounting, not positive-substance interpretation outside scope.                        |
| Radiation record pilot                                  | Independent stage-weighted `−D_zF_rad` and boundary integral on the same captured parent. 2.4 density conversion.                                                                                                      | Wrong sign, omitted stage weight, transported record, specific-output differencing at changing density.           | Capture/quadrature/refinement floor and independent divergence implementation. Shared flux does not validate radiation physics or stored origins. |

Route common data/verdict/reference eligibility tooling to **Part 4**.
Accepted correction/gross-throughput activity and cancellation tests to
**Part 5**. Independent energy references/PX22 to **11a**. Signed-process
budget and integrated post-#139 baseline/cost to **11b**. Only measured bounded
fixes to **11c**. Energy held-out qualification to **11d**. Expanded
precision/device/restart operating range and OD1/OD6 production campaign to
**Part 12**. Reuse PX11/PX24 and PX14/PX25 only for mechanisms they actually
cover. Preserve OD13's PP-SUB/materiality trigger and defer other probes until
measured need. PX15 remains conditional on OD7/owner action. Freeze the
independent held-out case/window/metrics before tuning (OD14). Site 23, site
26, Soares and TRMM are development cases. Measure cost before defaults and
long-run commissioning. G4.14/PX19 numerical-loss screens retain their gates.
Residence-time and air-age development stays excluded.

## 7. Owner choices and completion

The actionable questions, recommendations, alternatives and blocked claims
are in [DECISIONS' Part 3 proposals](../DECISIONS.md#part-3-proposals-2026-10-06-decided-2026-10-07).
They were decided on 2026-10-07 (DECISIONS, section 2026-10-07). They covered EA-USE/EA-ACCURACY/EA-COST and EA-STATE (stored inventory only), plus existing OD7, OD9–11 and the
post-#139 levels for seven-point points 2/3/4/6. Point 1's interim-estimate
wording, point 5's partition-sum A5 definition and point 7's documented C4
limit are decided, not reopened. Point 4's warning form is decided. Its
level is not. Warning, optional abort, parent validity and scientific
acceptance are separate actions. `throughput_tolerance` is not automatically
an origin accuracy tolerance.

Historical failures remain: E66 comparator residual, E69 one-Newton collapse,
E80 explicit-path lag before cross blocks, E83/E84 copies repair, E85 per-tag
intervention, E87 A5 discrepancy, E89's provenance-unvalidated surface change,
and radiation-seed-invalidated first long-run comparisons. E73/E76 ladders
and E84/E86/E87/E89 predating #139 are prior evidence, not current-physics
qualification. G4.1/11's mirrors, G4.16 cross blocks and explicit-microphysics
guards must be inspected/reused at the actual baseline before deciding that
an old checkbox still describes missing code. No unsupported mode can be
qualified by a development opt-in or water's passing case.

Part 3 completes when its doc diff is independently reviewed, concrete
findings resolved, source/decision/threshold/link/crosswalk consistency
validated, and every missing approval/evidence item has an explicit owner or
downstream destination. The acceptance decision can then be executed when
that evidence exists. Stop at this documentation handoff.

### Inspected implementation snapshot

All source statements above were inspected at
`fb8ddf62540df8c36095313bec3dee17aa2b5206`, the unmerged Part 2 head containing
Part 1. The review of 2026-10-07 patched the documents of Parts 1 and 2
(`d68ab8e6a`, `be77a25db`) and changed no source file, so the source locations
below still hold. Current branch/PR status is recorded in STATUS. The snapshot supplies
no simulation evidence. Principal source locations:

  - [Parent thermodynamic decomposition](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/cache/precomputed_quantities.jl#L694-L727).
  - [Offset and mass identity](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L143-L172), [brackets/partition loss](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L914-L1031), [repair](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L1198-L1290), [current follower](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L2848-L2952).
  - [Accepted-step absolute accumulation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/tag_throughput.jl#L590-L611), [per-tag normalization](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/tag_throughput.jl#L974-L1008), [Θx and restart fields](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/tag_throughput.jl#L1135-L1180), [runtime fallback](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L716-L739).
  - [Record tendency integration](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/tagged_tracers/process_record.jl#L169-L235), [specific record outputs](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/diagnostics/process_record_diagnostics.jl#L10-L47), [DYCOMS radiation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parameterized_tendencies/radiation/radiation.jl#L596-L675).
  - [Legacy interim scorer](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/experiments/tag_closure/analysis/increment/od4_restate.py#L125-L151), [legacy eligibility scorer](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/experiments/tag_closure/analysis/increment/g411_eligibility.py#L101-L187), [D4 budget scorer](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/experiments/tag_closure/analysis/increment/process_budget.py#L95-L186).
  - [Parent-budget scope](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parent_budget/coverage_registry.jl#L166-L211), [callback limitation](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/fb8ddf62540df8c36095313bec3dee17aa2b5206/src/parent_budget/adapter.jl#L1508-L1530). Its [normative contract](../../../docs/src/parent_budget/contract.md) and [coverage](../../../docs/src/parent_budget/coverage.md).
