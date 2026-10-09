# Challenge of the energy offset `c` (2026-10-09)

Read on `claude/plan-rev2` at `9e515532`:

  - the energy source tags' reference page and user guide, and the code that
    forms an attributed process's change and the share (`energy_source_tags.jl`,
    `_energy_source_increment` and `energy_source_fraction`);
  - FINDINGS section 3 (E1 to E19, R1 to R11, E71), and E41, E60, E70 and E74;
  - ATTRIBUTION_PATH sections 3, 6 and 7, G4_CLAIM_CONTRACTS section 2, and
    G4_TODO G4.10, G4.13 and G4.14;
  - the register rows OD3, OD4, OD6 and OD11, DECISIONS of 2026-09-14,
    2026-09-19, 2026-10-02 and 2026-10-07, and U8 in the archived
    OPERATIONAL_TODO.

Numbers marked *computed* come from
[offset_c_2026-10-09/offset_numbers.py](offset_c_2026-10-09/offset_numbers.py),
and its output is beside it. The script reads the archived closure tables for
the D4 and sphere totals. Its other inputs are values the record states, and it
names each one. Section 4 is a search outside atmospheric energy, added at the
owner's request during this review. An agent checked its sources by web search,
and what it could not read is marked. No run was made, and no other file
changed. A second agent fact-checked the review against the record and the
sources, and its corrections are in.

## Verdict

**Keep the method. Change the value of `c` and what is reported.**

The method is composition with pro-rata loss on `E_c = ρe_tot + cρ`. Nothing
in sections 3 and 4 gives a bounded split of the energy present that also
closes against the parent. The alternatives answer other questions, give up
boundedness or change the parent. The fork already has the useful ones, and
they serve as companions.

The value is the weak part. 110,495 J/kg has no rule behind it. It counts dry
internal energy from 228 K at sea level, so cold air that is still valid leaves
the tags' domain. Where the total nears zero, a cell forgets its initial energy
fastest, and the coldest such cells are extratropical. And the record measures
the effect of `c` in a unit that inflates it.

| #  | Proposal                                                                                                                                                              | Where |
|:-- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----- |
| 1  | Fix `c` by a rule before the first stored-tag run of part 11a or 11b. Count dry internal energy from the 150 K floor: `c = cp_d·T0 − cv_d·150 K` = 166,764 J/kg.  | OD11  |
| 2  | Sweep the fixed `c` against `cp_d·T0` = 274,389 J/kg, and flag each conclusion as robust to `c` or convention-defined. Run 110,495 once in 11b, for continuity.   | G4.10 |
| 3  | Report shares of `E_c` and the composition of new energy, not region-tag integrals. Report the loss timescale `τ = E_c/L` with each result.                         | G4.14 |
| 4  | Record the mass channel: `c` times each attributed process's mass change, and `c·F_M` through the bottom face. Attributing it apart is the owner's option.          | 11c   |
| 5  | Take up the label partition (ATTRIBUTION_PATH, step 4a). It holds the offset's reservoir in one tag.                                                                   | 11c   |
| 6  | Fix `c` before part 12d's 90-day sphere. Read OD6's absolute term for energy in OD4 units, as OD3's small-tag row does.                                               | OD6   |
| 7  | Describe `c` in the docs by the temperature it counts from.                                                                                                           | docs  |

## 1. What `c` does

The tags split `E_c = ρe_tot + cρ`. The offset enters in six places.

 1. **The initial inventory.** A region tag starts at `M_k E_c(0)`.
 2. **The loss rate.** A loss takes `δ⁻·a_k/E_c` from each tag. So a cell's tags
    turn over in `τ = E_c/L`, where `L` is the cell's gross loss rate.
 3. **The mass channel.** An attributed process changes the total by
    `Δ = Δρe_tot + cΔρ` (`_energy_source_increment`). Evaporation adds `c` per
    kilogram, and rain-out removes it.
 4. **The sign split.** Production and loss are the two signs of the combined
    `Δ`. Removing cold condensate is production at one `c` and loss at
    another (the reference page, "Attribution").
 5. **Transport.** The enthalpy-form flux shares `F_E + cF_M`. A larger `c`
    moves provenance more with the air and less with its energy.
 6. **The donor in sedimentation.** Falling ice carries negative `E_c` at the
    `c` in use, so the cell below gives up its shares (E41).

`c` is one member of a family. Dry, still air at sea level has
`e_tot + c = 0` at `T_ref = T0 − (c − R_d·T0)/cv_d`. So
`c = cp_d·T0 − cv_d·T_ref`, and choosing `c` means choosing the temperature
from which dry internal energy is counted. Height lowers that temperature,
by `g·z/cv_d`. *Computed:*

| `c` (J/kg)                           | counts from, sea level | 1 km    | 3 km    | enthalpy counted from |
| ------------------------------------:| ----------------------:| -------:| -------:| ---------------------:|
| 110,495 (in use, `cp_d` × 110 K)     | 228.4 K                | 214.8 K | 187.4 K | 163.2 K               |
| 166,764 (the 150 K rule)             | 150.0 K                | 136.3 K | 109.0 K | 107.1 K               |
| 220,990 (the `2c` of E19, E71, E87)  | 74.4 K                 | 60.8 K  | 33.4 K  | 53.2 K                |
| 274,389 (`cp_d·T0`)                  | 0 K                    | —       | —       | 0 K                   |

At `cp_d·T0`, the transported quantity `h_tot + c` is `cp_d·T + Φ + K` for dry
air. That is dry static energy, with its textbook zero, plus kinetic energy.
With moisture it is close to moist static energy. The record writes
274,388 J/kg for this value. `1004.5 × 273.16` gives 274,389.

The rows at 1 and 3 km reproduce U8's 215 K and 187 K. U8's archived formula
has `− g z` where it needs `+ g z`, and its numbers are right.

## 2. The challenge

### 2.1 The value has no rule, and valid cold air leaves the tags' domain

110,495 J/kg is `cp_d` × 110 K, C1's shift of `T0` (FINDINGS 3.3). It cleared
the moist sphere's initial minimum, −100.4 kJ/kg (E6), with about 10 kJ/kg to
spare. That margin is 14 K of cooling of dry air at a fixed height. Below
228 K at sea level the total is not positive. There the shares are zero, the
tags gain without losing, and the residual shows it (U8). OD3's validity row
accepts any temperature above the 150 K floor. U8 notes that a continental
winter can plausibly go colder than 228 K near the surface.

The record ties the choice to a trigger. U8's floor rule comes before any run
whose surface air could fall below about 228 K (DECISIONS 2026-09-19), and at
the latest before the first production run that spans a winter, at M7
(G4.10). Both are too late. The G4 contract qualifies nothing across `c`:
"Compare fixed-convention tests at the same `c`" (section 2.1). If a run then
needs another `c`, every stored-tag result of parts 11 and 12 at 110,495 has to
be rerun. Part 11b re-baselines on post-#139 code anyway. So the cheapest
moment to fix `c` is before the first stored-tag run of part 11a or 11b. OD11
stays proposed until a gated result exists (decided 2026-10-02, reaffirmed
2026-10-07). G1 and G2 used 110,495, but no gated post-#139 verdict and no OD9
to OD11 label depends on it yet.

### 2.2 Near zero, the reference sets the memory and the conditioning

A cell whose `E_c` is near zero turns its inventory over quickly, and its
shares are ill-conditioned. Both are properties of the reference, not of the
air. On the moist sphere at t = 0, the extratropical cell with the lowest
`e_tot` held 10.1 kJ/kg of `E_c`, and the tropical one 86.8 kJ/kg (R9,
*computed*). R9 finds those cells cold and dry. For the same loss, the
extratropical cell turns over 8.6 times faster. So the coldest extratropical
cells turn their energy over faster because of the convention. New energy made
there is labelled extratropical by the mask in any case. What changes is that
tropical energy carried into such a cell is lost faster, and that the source
tags' shares settle faster there. The ratio is 2.2 under the 150 K rule and
1.4 under `cp_d·T0`.

### 2.3 `c` sets the composition's window

Take a well-mixed cell whose processes do not change its mass. Then
`da_k/dt = P_k − (a_k/E_c)·L`. Every tag loses the same fraction, so
`d ln(a_i/a_j)/dt = P_i/a_i − P_j/a_j`, and `c` does not appear. A tag that
starts at zero holds

```
a_k(t) = ∫₀ᵗ P_k(s) exp(−∫ₛᵗ L/E_c dt') ds .
```

So a tag holds its production history, weighted by how recently it entered,
over a window of length `τ = E_c/L`, and `c` sets `τ`. The ratio of two tags
whose production has the same time course does not depend on `c`. Nor do the
equilibrium shares (ATTRIBUTION_PATH 3.3). Three things break this invariance:

  - processes that change the mass carry `cΔρ` (2.5);
  - transport weights provenance by `h_tot + c` (point 5 of section 1);
  - productions with different time courses are weighted over a window that
    depends on `c`.

The two ends of the family show what is at stake.

  - **As `c` falls to the smallest value that keeps `E_c` positive,** the
    window shortens and the cold cells become ill-conditioned (2.2).
  - **As `c` grows without bound,** loss goes to zero and transport becomes
    mass-weighted. A region tag becomes `c` times an air-origin tracer. A
    source tag becomes its process's transported gross production. The
    surface-flux tag becomes `c` times the evaporated water. The fork already
    has close relatives of each: passive tracers for the air's origin, the
    water tags for evaporated water, and the signed tags and gross ledgers for
    a process's activity.

So energy provenance exists only at a finite `c`, and it depends on `c` by
construction. No limit makes it free of the reference. That is the difference
from LMDI's small-value replacement (section 4, row 5).

The window gives the right size for E71's change. A source tag that grows from
zero changes by about `(t/2τ)(1 − 1/k)` when `E_c` grows `k`-fold. On D4, `k`
was 2.63. With ATTRIBUTION_PATH's `τ` of 8 to 11 days the estimate is 2.8 to
3.9% over a day, and with E60's 4 to 20 days it is 1.5 to 7.7% (*computed*).
E71 measured 4.2 to 4.5% for `rad`, `sub` and `new_strat`, whose production
carries no mass. `sfc` and `new_tropo`, at 6.3 and 6.0%, also carry the mass
channel. This checks the order of magnitude. It is not a test, because a column
is not well mixed.

### 2.4 The record's measure of the spread inflates it

E71 reports that doubling `c` moved `strat` by +177% and `tropo` by +152%.
DECISIONS (2026-10-07) and the G4 contract (2.1) cite these to show that `c`
can change labels substantially. But the region tags partition `E_c`, and
`∫E_c` itself grew 163%, 2.631-fold, at 24 h (*computed*). As shares of the
total, `strat` moved by about +5% and `tropo` by about −4%, relative
(*computed*). For `strat` that is from about 0.44 to 0.47 of the total. E71's
percentages are rounded to whole percent, and over their rounding the shares
move by +5.1 to +5.5% and −4.0 to −4.4%. The source tags moved by 4.2 to
6.3%. Their pairwise ratios moved by about 2%.

So over a day on D4 the convention moves shares by about 5%, amounts by 4 to
6% and the composition of new energy by about 2%, all relative. No share or
ratio moved by more than about 5%. The share spread still exceeds the 2% L1
tolerance. This corrects point 7 of today's review of the decisions
(`decisions_challenge_2026-10-09.md`, PR #163). Its conclusion stands with the
share measure.

### 2.5 Offset energy is mixed with process energy

  - The mass channel is attributed with the process that moves the mass. On D4,
    `c` times the evaporated water is about 4% of the surface-flux tag's daily
    production (ATTRIBUTION_PATH 3.3). Scaled, it is 5.5% under the 150 K rule
    and 8.7% under `cp_d·T0` (*computed*).
  - The sign split of a process that changes mass depends on `c` (point 4 of
    section 1).
  - Falling water carries its offset by sedimentation transport, and it leaves
    through the surface. On E87 that offset was C4's size (EA-C4, 2026-10-07).

None of this is wrong. But a reader cannot tell the offset's part from the
process's own energy. The process records leave `c·δp^ρ` out (G4 contract
2.4), so the tags and the records differ there as well.

### 2.6 Two decided tolerances move with `c`

  - **OD6's ceiling** is `max(0.02 S_min, 2e-4)` of the partition. Both the
    partition and `S_min` depend on `c`. On the sphere the residual is Float32
    rounding (E70). The rest of this point is an argument, not a measurement.
    Rounding grows with `E_c`, and the flush, at the rate `L/E_c`, slows as
    `E_c` grows. So a larger `c` should raise the level, relative to the
    partition, at which the residual settles. At the `c` in use, E74 reached
    2.0e-4 at day 10, still growing, with a flush time of 60 to 95 days.
  - **OD4's Θx** moved 1.7% when `c` doubled (E87's pair, G4 contract 2.1).

OD6's reason gives its 2e-4 as "the small-tag absolute rule". OD3 applies that
rule to energy in OD4 units, not as a fraction of the partition. So for energy,
OD6's absolute term is in other units than the rule it cites. In those units,
`c` enters far less: the partition grows 2.2 to 2.6-fold when `c` doubles,
and Θx by 1.7%. Either way, OD6's 90-day verdict depends on `c`, so `c` belongs
in that run's pre-registration.

### 2.7 Neither proposed value fixes the direction of falling ice

E41 found falling ice at −193 kJ/kg of `E_c`, on PrecipitatingColumn. It turns
positive only above `c` ≈ 303 kJ/kg (*computed*). Neither value proposed here
reaches that. The record calls the upward branch an artefact of `c`
(ATTRIBUTION_PATH 3.3). It stays one under both proposals. A single `c` above
about 303 kJ/kg, or a separate offset for water (alternative E), removes E41's
case.

## 3. Alternatives

The criteria:

  - (a) it answers "of the energy here, how much came from X";
  - (b) its tags are bounded and non-negative;
  - (c) it closes against the parent;
  - (d) it is free of an arbitrary reference;
  - (e) it leaves the parent bit for bit;
  - and its cost in this fork.

| Alternative                                                   | a                           | b                               | c                 | d                                 | e             | cost                              | verdict                              |
|:------------------------------------------------------------- |:--------------------------- |:------------------------------- |:----------------- |:--------------------------------- |:------------- |:--------------------------------- |:------------------------------------ |
| A. Offset at 110,495 (in use)                                 | yes                         | where `E_c > 0`                 | yes               | no                                | yes           | none                              | replace the value                    |
| B. Offset by the 150 K rule, 166,764                          | yes                         | for dry air in every valid state | yes              | no, a stated rule                 | yes           | a config value                    | **recommended**                      |
| C. Offset `cp_d·T0`, 274,389                                  | yes                         | yes                             | yes               | no, a textbook zero               | yes           | a config value                    | sweep partner, or the owner's choice |
| D. Offset sized per run from its coldest state                | yes                         | with no margin                  | yes               | no                                | yes           | a config value                    | rejected                             |
| E. Separate offsets for dry air and water                     | yes                         | yes                             | yes               | no, two conventions               | yes           | per-process water, water fluxes   | not now                              |
| F. Move the parent's reference (C1)                           | yes                         | yes                             | yes               | no                                | no (E16)      | a TOML change                     | rejected                             |
| G. Signed transported tags (`ρe_tag_*`)                       | no, net contribution        | no                              | yes               | yes, apart from mass              | yes           | exists                            | companion                            |
| H. Process records (`prc_e_*`)                                | no, what a process did      | signed                          | as records        | yes, apart from mass              | yes           | exists                            | companion                            |
| I. Air-origin passive tracers                                 | no, where the air came from | yes                             | yes               | yes                               | yes           | exists                            | companion, the large-`c` limit       |
| J. Perturbation or anomaly runs                               | no, what would change       | no                              | no                | yes                               | separate runs | a run per process                 | a different question                 |
| K. Tag θ, moist static energy or another quantity with a zero | for that quantity           | yes                             | approximately     | yes                               | yes           | large                             | C gives most of it                   |
| L. Exergy or available enthalpy                               | partly                      | yes                             | no, not conserved | needs a dead state                | yes           | large                             | rejected                             |
| M. Label partition, `initial` plus one tag per label          | yes                         | yes                             | yes               | no, as A to C                     | yes           | small to medium (the record)      | **recommended**, with B              |
| N. The mass channel apart                                     | yes                         | yes                             | yes               | narrows `c` to loss and transport | yes           | a record, or model code           | record now                           |
| O. Average over `c`, or carry `∂a_k/∂c`                       | yes                         | yes                             | yes               | averages it                       | yes           | doubles the tags                  | not now                              |

**B against C.** Both keep `E_c` positive for dry air in every state that
OD3's validity row accepts. With condensate, B holds except within a few kelvin
of the floor. Both are one value for every configuration, so they satisfy U8's
two options at once.

  - B is the smallest `c` with that guarantee. Against the value in use, it
    raises `E_c` 1.6-fold on the sphere and 1.8-fold on D4 (*computed*). C
    raises it 2.8-fold and 3.4-fold.
  - B lies between the two values that every measurement of the sensitivity
    used, 110,495 and 220,990 (E17, E19, E71, E87). C lies above both, so its
    effects are extrapolated.
  - C's advantage is meaning. It transports dry static energy with its
    textbook zero. Heat tagging counts from 0 K too (Fajber and Kushner 2021),
    and its radiative tag takes years to settle (ATTRIBUTION_PATH 6.2).
  - The two-iteration sphere's residual flushes in 60 to 95 days (E74). E70
    gives 0.011 to 0.015 a day for V2, and E60 1 to 2 years above 10 km on C9's
    sphere, where most of that residual sat. Scaled by the sphere's mean `E_c`,
    E74's time becomes 97 to 153 days under B and 167 to 264 days under C
    (*computed*, an estimate). The mean overstates the change aloft, where Φ
    is large. If E74's rate stands for the initial energy's loss, the part of
    the initial energy left at day 90 would be 0.4 to 0.6 under B and 0.6 to
    0.7 under C, against 0.2 to 0.4 now.

**D** sizes `c` per run from its coldest state, like the 45.4 and 100.4 kJ/kg
that the refusal message quotes. It gives the shortest window. But results of
different runs are not comparable, the margin is zero, and the cold cells are
the worst conditioned (2.2).

**E** writes `E = ρe_tot + c_d ρ_d + c_w ρq_tot`. C1's exact reference map has
this form, with `cp_d·δ` for dry air and `cp_l·δ` for water (R9). A `c_w` above
about 0.3 MJ/kg makes E41's ice carry positive energy, so falling ice would
give up the shares of the cell it leaves. The cost is the water tendency of
every attributed process and a water flux at every face. It also adds terms
where forcing changes water without mass (G4 contract 2.1, "Mass is not
water"). And it enlarges the mass channel to about 9.5% of the surface-flux
tag on D4 (*computed*). It is worth this only if the energy of precipitation
becomes a goal (G4.11's compartments).

**F** is the C1 shift. It perturbs the discrete model (E16), and the owner
chose the offset instead.

**G to J** answer other questions, and the fork keeps them for that.

  - Signed tags hold a net contribution. Fajber and Kushner note that such tags
    would not stay finite in a long climate run (ATTRIBUTION_PATH 6.2).
  - The records hold what a process did, without transport. EA-USE keeps the
    radiation record as an unqualified diagnostic, verified in part 11a.
  - Passive tracers say where the air came from. The guide says so
    ("The origin of the energy is not the origin of the air").
  - Perturbation runs give impacts, not contributions (Clappier et al. 2017,
    the reference page's "Interpretation limit").

**K**, tagging a quantity with a natural zero, would avoid the pressure-work
mismatch for θ. But the model carries `ρe_tot`, not θ, so every process's θ
tendency would have to be derived, and closure would hold only against a
diagnosed field. C gives the textbook zero inside the existing machinery.

**L** is positive by construction, but irreversible processes destroy it, so
it cannot be partitioned with closure.

**M**, the label partition, is ATTRIBUTION_PATH's step 4a. The record proposed
it to remove E35's created energy and E36's frozen nodes. The offset gives a
second reason. The reservoir that `c` sets sits in one tag, `initial`. The
label tags then hold the weighted production of 2.3, and their composition is
the product that depends least on `c`. The repair only trades within the
partition.

**N** has two forms. A record of the mass channel per attributed process only
reports, so it is cheap. Attributing `δp^ρe` and `c·δp^ρ` as two applied-update
events, each by its own sign, makes the sign split independent of `c`. It also
keeps offset energy out of the process tags, for example by giving it to the
region tags only. But it changes the gross throughput, and so OD4's Θx, the
scale of every energy percentage. That is the owner's choice.

**O** would average the reference away, as Yun's normalisation and expected
gradients do (section 4). The parent is bit for bit across `c` (E17), so it
needs either several tag sets in one run or several runs. Criterion 10 already
fails at 4.16× (E88). The sweep of proposal 2 gives the same information at
two points.

## 4. How other fields attribute values that can be negative, zero or positive

Added at the owner's request. An agent searched outside atmospheric energy and
checked each source by web search. A second agent re-read the key sources.

*Corrected 2026-10-09:* a third agent then read the sources to add them to the
owner's wiki (`llm-wiki`, PR #33). Rows 3 and 5 to 15 and the sources are
corrected where that reading did not support the first version. Some sources
were read only from an abstract or a citation record, and some not at all. The
sources list says which. The wiki's source notes give the section, table and
equation numbers.

| #  | Field                                    | What breaks at zero, below zero or when the reference changes                                                                                                                                      | What the field does                                                                                                                                                                              | For `c`                                                                                                                  |
|:-- |:---------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------ |
| 1  | Ocean heat transport                     | Through a section with net volume flux, "heat transport" depends entirely on the temperature scale. In kelvin, a +2.8 TW term becomes −1089.2 TW [1].                                             | Report heat transport only for combinations of sections with zero net volume flux, and mass transport by temperature class otherwise [1]. Approximate energy transport only across mass- and salt-balanced sections [2]. TEOS-10 fixes its zeros by convention [3]. | The closest analogue. Kelvin makes every temperature positive, and the open-section terms still mean nothing [1].        |
| 2  | Feature attribution in machine learning  | Attributions explain `f(x) − f(baseline)`, so they change with the baseline [4, 6]. A feature equal to its baseline gets no attribution [4].                                                      | State the baseline and what "missing" means, and average over baselines [4]. Or use one explicit baseline, which can encode the context of the question [6].                                     | `c` is the baseline. State it and why.                                                                                   |
| 3  | Wage-gap decomposition                   | The total and the aggregate parts are invariant, but the detailed split changes with the omitted reference group [7, 8].                                                                           | Normalise the regression, which equals averaging the decomposition over every reference group [8].                                                                                              | Formally the same as `c`: the total is fixed, the split is not.                                                          |
| 4  | Logs of outcomes with zeros              | The offset in `log(c + Y)` acts like a change of units. It sets the weight of the zero-to-nonzero margin, so the effect can take any size [9].                                                     | Choose that weight on purpose, report the effect in levels, or estimate the two margins apart [9].                                                                                              | `c` weights the mass channel. Report it apart (proposal 4).                                                              |
| 5  | Index decomposition (LMDI)               | Logarithms are undefined at zero.                                                                                                                                                                  | Replace zeros by a small number. The abstract says the results then converge [10]. Later work on zero and negative values was not read [11, 12].                                                | `c` has no such limit, and its large-`c` limit is not energy provenance (2.3).                                           |
| 6  | Microbiome log-ratios                    | The pseudocount added to zero counts can change the result for rare taxa with many zeros [14].                                                                                                     | Rerun at several pseudocounts and flag each result whose outcome changes [14].                                                                                                                   | The template for proposal 2's flag.                                                                                      |
| 7  | Electricity flow tracing                 | Power carries no label, and nodal injections are signed [15]. Which allocation scheme to use has no unique answer [16].                                                                            | Flow tracing splits injections into non-negative inflows and outflows, then shares by proportional mixing at each node [15]. It follows the net flow, so it never gives negative allocations. Schemes that allow counterflows give negative, mitigating allocations, and an evaluation on four criteria recommends none of them [16]. | Non-negative allocations are a property of the chosen scheme, not of the network.                                        |
| 8  | Allocating transmission losses           | Allocating losses to individual injections, or splitting them between generators and loads, is arbitrary [17].                                                                                     | Allocate per equivalent bilateral exchange between a generator and a load, which is unique, and combine [17].                                                                                    | A unique answer exists only per source–sink pair, a closed combination.                                                  |
| 9  | National accounts                        | Real components do not add up to the real total, and real shares do not sum to one. A change in inventories can switch sign, so it has no growth rate [18].                                        | Publish additive contributions to percent change [18, 19]. Use nominal shares for questions about allocation [18].                                                                             | Contributions to a change avoid the zero. The fork's records do this.                                                    |
| 10 | Variance partitioning                    | The functions "frequently give negative estimates of variation" [20].                                                                                                                              | The documentation explains when negative fractions arise and how to avoid negative eigenvalues. It gives no reporting rule [20].                                                                 | An account that closes needs its negative parts. That is arithmetic, not the source's advice.                            |
| 11 | Warming attributed to emitters           | The response is nonlinear, and cooling agents contribute negatively: with sulphate, shipping has not contributed to net warming [22].                                                              | Compare formalisms. The choice of method matters about a fifth as much as other choices [21]. Present results across the defensible choices: there is "no simple and single correct answer" [22]. | Report the spread across the defensible family.                                                                          |
| 12 | Air-quality source apportionment         | Under nonlinear chemistry, impacts from perturbation runs do not add up to the total, and their interaction terms can be negative. Tagged contributions add up [23, 24].                         | Tagging for contributions, perturbation for impacts [23], and quantify the nonlinearity first [24]. TOAST closes its tags to the total [25].                                                     | Tags answer "where from" under a convention. Causal claims need runs.                                                    |
| 13 | Partnership tax accounting               | Pro-rata losses can push a capital account below zero.                                                                                                                                             | Allowed only with a duty to restore the deficit. Under the alternate test, only as far as no deficit arises, with an income offset that removes one [26].                                       | Pro-rata loss needs positive holdings and a stated rule for deficits, which the repair is.                              |
| 14 | Life-cycle and greenhouse-gas accounting | A free factor splits the burdens and credits of recycling between supplier and user, and the result moves with it [27].                                                                            | Take the factor from a fixed list and show the result's sensitivity to it [27]. Report removals apart from emissions, and gross fluxes on their own lines [28].                                 | Standardise the free parameter, and keep gross ledgers apart.                                                            |
| 15 | Portfolio risk                           | With-and-without contributions do not add up to total risk [30]. For small losses, realised loss contributions can bear little relation to risk contributions [29].                               | Use Euler contributions, which add up to total risk by Euler's theorem, and read them as contributions to large losses [29, 30].                                                               | Contributions that add up by an identity need no positive total to be defined.                                          |

The same strategies recur. The fork already follows most of them.

| Strategy                                                     | Fields      | The fork now                                       | Proposed here                                    |
|:------------------------------------------------------------ |:----------- |:-------------------------------------------------- |:------------------------------------------------ |
| Contributions to a change, not shares of a level             | 2, 9, 15    | the process records and `ρe_tag_*`                 | keep them as companions (G, H)                   |
| Gross positive and negative parts in non-negative ledgers    | 4, 7, 14    | production and loss apart, WP6's gross ledgers     | the mass channel apart (proposal 4)              |
| Only mass-balanced combinations are free of the reference    | 1, 3, 8     | column and domain identities (form B, EA-C4)       | read claims free of `c` only there               |
| State the reference and what zero means                      | 1, 2, 14    | each test states its `c`                           | a rule for `c` (proposal 1)                      |
| Sensitivity across references                                | 6, 11, 14   | the `c`/`2c` pair                                  | span the family, flag each conclusion (2)        |
| Average over references                                      | 2, 3        | none                                               | not now (O)                                      |
| Pro-rata only on positive holdings, with a rule for deficits | 7, 13       | no share where `E_c ≤ 0`, and the repair           | the label partition makes the repair a trade (5) |
| A fill-in value only if the result converges as it shrinks   | 5           | none                                               | no such limit exists for `c` (2.3)               |

The fields disagree on one point. Flow tracing keeps every allocation
non-negative, while schemes that allow negative allocations are as defensible
on the criteria tested (row 7). Non-negativity is a choice there, as it is for
the energy tags.

Sources:

 1. Schauer and Beszczynska-Möller (2009), Ocean Sci. 5(4), 487–494, DOI 10.5194/os-5-487-2009, Table 1 and section 5. https://os.copernicus.org/articles/5/487/2009/
 2. Warren (1999), Approximating the energy transport across oceanic sections, JGR 104, DOI 10.1029/1998JC900089. Only the EarthRef record was read. https://earthref.org/ERR/50891
 3. IOC, SCOR and IAPSO (2010), the TEOS-10 manual, section 2.6. https://www.teos-10.org/pubs/TEOS-10_Manual.pdf
 4. Sturmfels, Lundberg and Lee (2020), Distill 5(1), e22, DOI 10.23915/distill.00022. https://distill.pub/2020/attribution-baselines/
 5. Sundararajan, Taly and Yan (2017), integrated gradients, ICML, PMLR 70, 3319–3328. https://arxiv.org/abs/1703.01365
 6. Sundararajan and Najmi (2020), The many Shapley values for model explanation, ICML, PMLR 119, 9269–9278, Remarks 4.5, 4.6 and 4.9. https://proceedings.mlr.press/v119/sundararajan20b.html
 7. Oaxaca and Ransom (1999), Rev. Econ. Stat. 81(1), 154–157, DOI 10.1162/003465399767923908. Only the abstract was read. https://ideas.repec.org/a/tpr/restat/v81y1999i1p154-157.html
 8. Yun (2003), IZA DP 836, normalised regressions. The journal version is Yun (2005), Economic Inquiry 43(4), 766–772. https://docs.iza.org/dp836.pdf
 9. Chen and Roth (2024), QJE 139(2), 891–936, DOI 10.1093/qje/qjad054, Propositions 1 and 2 and section 4. https://arxiv.org/abs/2212.06080
10. Ang and Choi (1997), Energy J. 18(3), 59–73. Only the abstract was read. https://ideas.repec.org/a/sae/enejou/v18y1997i3p59-73.html
11. Ang and Liu (2007), Energy Policy 35, 238–246 (zero values) and 739–742 (negative values). Not read. https://ideas.repec.org/a/eee/enepol/v35y2007i1p238-246.html
12. Sun (1998), Energy Econ. 20, 85–100. Not read. https://ideas.repec.org/a/eee/eneeco/v20y1998i1p85-100.html
13. Costea et al. (2014), Nat. Methods 11, 359, DOI 10.1038/nmeth.2897, and the reply by Paulson, Bravo and Pop, DOI 10.1038/nmeth.2898. Neither was read. The ANCOM-BC2 vignette cites both for the effect of the pseudocount.
14. Lin and Peddada (2024), Nat. Methods 21(1), 83–91, DOI 10.1038/s41592-023-02092-7, and the ANCOM-BC2 vignette. https://bioc-release.r-universe.dev/ANCOMBC/doc/ANCOMBC2.Rmd
15. Hörsch et al. (2018), Int. J. Electr. Power Energy Syst., DOI 10.1016/j.ijepes.2017.10.024, which reviews Bialek's proportional sharing (1996, not read). https://arxiv.org/abs/1609.02977
16. Hofmann, Zerrahn and Gaete-Morales (2020), Techno-economic criteria to evaluate power flow allocation schemes, arXiv:2010.11000, sections 4.1 and 4.3. It cites Kirschen, Allan and Strbac (1997), which was not read. https://arxiv.org/abs/2010.11000
17. Galiana, Conejo and Kockar (2002), IEEE Trans. Power Syst. 17(1), 26–33, DOI 10.1109/59.982189. Only the abstract was read. https://strathprints.strath.ac.uk/5184/
18. Whelan (2000), FEDS 2000-35, sections 2 and 4 and footnotes 8 and 10. Published in Rev. Income Wealth 48(2), 2002. https://www.federalreserve.gov/pubs/feds/2000/200035/200035pap.pdf
19. Moulton and Sullivan (1999), A Preview of the 1999 Comprehensive Revision of the National Income and Product Accounts: New and Redesigned Tables, Survey of Current Business 79(9), 15ff. https://apps.bea.gov/scb/pdf/national/nipa/1999/0999niw.pdf
20. The vegan package (2.7-6), `varpart`, its notes section. https://search.r-project.org/CRAN/refmans/vegan/html/varpart.html
21. Trudinger and Enting (2005), Climatic Change 68(1), 67–99, DOI 10.1007/s10584-005-6012-2. Only the abstract was read. https://www.proquest.com/docview/198527563
22. Skeie et al. (2017), Environ. Res. Lett. 12, 024022, section 3.1 and the conclusions. https://iopscience.iop.org/article/10.1088/1748-9326/aa5b0a
23. Grewe, Tsati and Hoor (2010), GMD 3, 487–499, sections 5 to 7. https://gmd.copernicus.org/articles/3/487/2010/
24. Clappier et al. (2017), GMD 10, 4245–4256, sections 5 and 6. Its example is secondary inorganic particulate matter. https://gmd.copernicus.org/articles/10/4245/2017/
25. Butler et al. (2018), GMD 11, 2825–2840, TOAST, section 4. https://gmd.copernicus.org/articles/11/2825/2018/
26. 26 CFR 1.704-1(b)(2)(ii)(b) and (d). https://www.law.cornell.edu/cfr/text/26/1.704-1
27. Rickert and Ciroth (2020), GreenDelta, the Circular Footprint Formula's factor A, Annex 2. https://www.greendelta.com/wp-content/uploads/2020/10/2020-10-PEF-application-of-CFF.pdf
28. GHG Protocol, Land Sector and Removals reporting checklist (2026), Requirement 31 and sections 12.2.2 and 14.2.2. https://ghgprotocol.org/sites/default/files/2026-06/LSR-Standard-Reporting-Requirements-Checklist.pdf
29. Qian (2006), JOIM 4(4), 41–51, Eq. 3 and Table 2. https://www.panagora.com/assets/JOIM-On-the-Financial-Interpretation-of-Risk-Contribution.pdf
30. Tasche (2007, version 3 of 2008), Capital allocation to business units and sub-portfolios: the Euler principle, arXiv:0708.2542 v3, Proposition 2.1 and Eq. 2.11b. https://arxiv.org/abs/0708.2542

Not used, because they could not be read: ten Raa and Rueda-Cantuche (2013) on
negative input-output coefficients, and Laker on attribution with zero-weighted
sectors.

## 5. The recommendation, in detail

**1. Fix `c` by the 150 K rule.** `c = cp_d·T0 − cv_d·150 K` = 166,764 J/kg at
the default parameters. Record it in OD11 in place of 110,495, as a number with
its derivation, so that a change of a parameter does not move it silently.

  - It keeps `E_c` positive for dry, still air at or above sea level in every
    state that passes OD3's validity row. Vapour, motion and height only add to
    it. Condensate subtracts little, except within a few kelvin of the floor.
  - It is one value for every configuration, so no winter decision waits at M7.
    Qualification in parts 11 and 12 then carries to production.
  - It is the smallest `c` with that guarantee, so its window is the shortest of
    the robust choices: `E_c` grows 1.6-fold on the sphere and 1.8-fold on D4.
  - It lies inside the measured range (section 3, B against C).
  - The coldest cells' ratio falls from 8.6 to 2.2 (2.2).

C, `cp_d·T0`, is the alternative if the owner values the textbook zero more
than the window. It costs `E_c` 2.8 to 3.4-fold, beyond the measured range.

**2. Sweep against `cp_d·T0`, with a flag per conclusion.** The pair spans the
family from the validity floor to absolute zero. A conclusion holds at both or
it does not. One that keeps its sign and ranking, and moves by less than its own
tolerance, is "robust to `c`". Any other is "convention-defined": it is
reported, and it cannot reach level 3 or 4. This replaces point 7's measure
with shares (2.4). Run 110,495 once in 11b, so the G1 and G2 record connects.

**3. Report what depends least on `c`.**

  - Region tags as shares of `E_c`, never as integrals compared across `c`.
  - The composition of new energy: the source tags' ratios, or the label
    partition's tags over their sum. In a well-mixed cell this is the
    production history weighted over the window.
  - `τ = E_c/L` with every result (G4.14, already planned after WP6). Where
    `t ≪ τ`, amounts are close to transported production and depend little on
    `c`. Where `t ≫ τ`, shares approach the production fractions. In between,
    both depend on `c`.

**4. Record the mass channel.** Keep `c` times each attributed process's mass
change, and `c·F_M` through the bottom face, as reported records. Then the
surface-flux tag's offset part and the offset that leaves with precipitation,
C4's size on E87, are read directly. Attributing the mass channel as separate
applied-update events is the owner's choice, since it changes Θx.

**5. Take up the label partition** (ATTRIBUTION_PATH step 4a), for the two
reasons in section 3, M.

**6. Fix `c` before part 12d's 90-day sphere (G4.13), and read OD6's absolute
term for energy in OD4 units.** That is what OD3's small-tag row, which OD6
cites as its reason, already does. The term `0.02 S_min` stays relative to the
partition, because it compares shares.

**7. Describe `c` in the docs by its temperature**: "the tags count dry
internal energy from 150 K at sea level". The guide's advice, "110495.0 unless
you have a reason", then becomes the rule.

**What would change this.**

  - If 11b's sweep moves the composition of new energy by more than its
    tolerance on the development cases, then composition is convention-defined
    everywhere in the defensible family. Stored source tags would then be
    reported as convention-conditional. The signed records would be the energy
    diagnostic to qualify instead. EA-USE keeps the radiation record
    unqualified for now.
  - If the 90-day sphere fails OD6 under the 150 K rule where 110,495 would
    pass, the likely cause would be Float32 rounding of a larger reservoir, by
    the argument of 2.6. The remedy would then be precision, not a smaller `c`.

## 6. What held

  - The offset in the tags' total, rather than a shift of the parent's
    reference. The parent stays bit for bit (E17), and the shift does not
    (E16).
  - `ΔE_c = Δρe_tot + cΔρ` with mass, not water (G4 contract 2.1).
  - Every test states its `c`, and the sweep is a comparison of conventions,
    never a bound (DECISIONS 2026-10-07, G4 contract 2.1).
  - OD4's throughput scale, which avoids dividing by the offset's inventory.
    Its 1.7% dependence on `c` is recorded.
  - Sedimentation as transport carrying `c·F_M`, so the offset leaves with the
    falling mass (EA-C4).
  - The reference page's "Interpretation limit" and item 5 of the guide's
    checklist.
