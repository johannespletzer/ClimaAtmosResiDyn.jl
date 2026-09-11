# The energy source tags under EDMF, with ice, and under 2M and P3: design

A design for the owner's OK, written on 2026-09-11 against
`claude/tag-closure-experiments` at `17badbe7`. No model code is written. The
owner asked for three things before the tags are used operationally:
sub-grid transport with ice, the other microphysics schemes, and user docs.
This file covers the first two. The user guide is a separate draft,
[USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md). The validation configs are the `d*`
files in `configs/`. FINDINGS E40 and E41 record the build checks.

Line numbers are at `17badbe7`. The review fixes merged since (`602153b9`) moved
some of them in `energy_source_tags.jl` and in the docs. "E" and "T" numbers are
entries in [FINDINGS.md](FINDINGS.md).

## Why

The series has measured the tags on the grid-scale path only: 0M and 1M, no
EDMF. There they close, and the per-process checks hold (E26, E30, E33, E34).
Outside that path nothing has been run, and nothing refuses to run.

  - **Under `PrognosticEDMFX`** the parent moves energy through sub-grid terms
    the tags do not see at all. The whole SGS mass flux of energy lands in
    `e_src_res`, under `tracer` and under `enthalpy` alike. With
    `edmfx_vertical_diffusion: true`, which every shipped EDMF config sets, the
    code asks the updraft for a tag field it does not carry.
  - **With ice**, sedimentation takes its upward branch wherever ice or snow
    falls. Only a set flux in the integration test has reached that branch.
  - **2M and P3** are switched off in the model on this branch, pending a
    CloudMicrophysics fix (`precomputed_quantities.jl:160-167`). By the code,
    the tags need nothing more for 2M than for 1M. Behind the gate, P3 has
    further gaps in the parent's own sedimentation.

## What the tags see today

### Under `PrognosticEDMFX`

| term | the parent, `ρe_tot` and `ρ` | the tags | effect |
|:-- |:-- |:-- |:-- |
| grid-mean vertical advection | implicit, central, with the upwind correction after Newton (`implicit_tendency.jl:242-243`, `:383-385`) | explicit tracer (`advection.jl:253-262`), or the audit's share (`advection.jl:263`) | as without EDMF |
| grid-mean horizontal advection | `split_divₕ(ρu, h_tot)` (`advection.jl:59`) | tracer (`advection.jl:121-127`), or the share (`:128`) | as without EDMF |
| **SGS mass flux** | `ρe_tot` gets `Σₖ` of the difference-form flux of `aᵏ(mseᵏ + Kᵏ - h_tot)` (`edmfx_sgs_flux.jl:65-90`). `ρ` gets the `q_tot` flux (`:107`, `:122`) | **nothing** | all of it lands in `e_src_res` |
| SGS diffusive flux, vertical | enthalpy form: `K_h` on `s_d` and `q_tot_eff`, `K_e` on `h_tot` (`edmfx_sgs_flux.jl:270-317`, `:376`). `ρ` through `q_tot_eff` (`:327`) and `K_e` on `ρq_tot` (`:398-400`) | tracer form, `ρ(K_h + K_e) ∇(ρe_src/ρ)` (`:390-396`, `α = 1`) | form mismatch in `e_src_res` |
| **SGS diffusive flux, with `edmfx_vertical_diffusion: true`** | the same, and applied to the updraft's `mse` (`:377-381`) | the loop asks the updraft for `e_src_<name>` with no guard (`:403-409`, `get_field` at `:406`) | **the run fails**; see *Build checks* |
| SGS diffusive flux, horizontal | enthalpy form (`:465-481`, `:535`) | tracer form, guarded by `has_field` (`:547-562`) | form mismatch |
| entrainment and detrainment | act on the updraft's scalars inside a cell (`edmfx_entr_detr.jl:587-630`); detrainment sits in the `ρa` solve | nothing | none directly. They leave the grid mean unchanged. They reach it only through `mseʲ` in the SGS mass flux |
| updraft advection, buoyancy and sedimentation | updraft scalars only (`advection.jl:330-497`) | nothing | none directly, as above |
| sedimentation, grid-mean flux | `water_advection.jl:71-108` | shared (`:99-107`) | none |
| **sedimentation, subdomain corrections** | updraft (`water_advection.jl:157-167`) and environment (`:174-184`) corrections, one updraft only (`:135`) | **nothing** | lands in `e_src_res` |
| microphysics, 0M | environment and updraft sinks summed into the grid mean (`microphysics/tendency.jl:101-133`) | bracketed as one grid-mean increment (`implicit_tendency.jl:65-80`, `remaining_tendency.jl:233-242`) | closes. An updraft's rain-out takes energy by the grid mean's shares |
| `pressure_work_tendency!` | a no-op for every model (`pressure_work.jl:17-19`) | — | none |
| Jacobian | SGS blocks for `ρe_tot`, `ρq_tot` and the updraft's own tracers | diffusion blocks only, as passive tracers (`manual_sparse_jacobian.jl:221-223`) | — |

Why the SGS mass flux reaches no tag: the tracer loop of
`edmfx_sgs_mass_flux_tendency!` runs over `sgs_tracer_names(Y)`, the scalars the
updraft carries (`edmfx_sgs_flux.jl:134-171`). The updraft state is `ρa`,
`mse`, `q_tot`, the microphysics species and the chemistry tracers
(`prognostic_variables.jl:244-301`). No tag family has an updraft counterpart.
A field with no counterpart has `χᵏ = χ`, and its difference-form flux
`ρᵏaᵏ(u³ᵏ - u³)(χᵏ - χ)` is zero by construction. So there is no tracer form of
this term for the tags to take. The docs say "grid-scale only"
(`energy_source_tags.md:338`). They do not say that this puts the whole SGS
energy flux into `e_src_res`.

The same holds for the water tags and the `ρe_tag_*` family: the water tags
mirror only the grid-mean sedimentation flux (`tagged_water.jl:396-398`).

### Which EDMF configurations run with tags

| `turbconv` | settings | with energy source tags today |
|:-- |:-- |:-- |
| `~` or `edmfx` | no turbulence-convection model (`model_getters.jl:951-961`) | supported; the series' runs |
| `edonly_edmfx` | eddy diffusivity and TKE, no updraft | builds by reading: no updraft, no guard to trip. Its eddy diffusion moves the tags as tracers. Not build-checked |
| `prognostic_edmfx` | `edmfx_vertical_diffusion: true`, as in every shipped EDMF config | fails in `edmfx_sgs_diffusive_flux_tendency!`, build-checked; see *Build checks* |
| `prognostic_edmfx` | `edmfx_vertical_diffusion: false` | should run, by the code: nothing else asks the updraft for a tag. Not stepped here, because the full EDMF build did not finish within 15 minutes on the login node. The tags see no SGS mass flux and no sedimentation corrections, build-checked |
| `prognostic_edmfx` | `updraft_number` > 1 | the parent itself errors in updraft sedimentation under 1M and 2M (`advection.jl:388-390`) |
| `prognostic_edmfx` | `2MP3` | the parent has no P3 microphysics with EDMF (`microphysics/tendency.jl:19`, `:266`) |
| diagnostic EDMF | — | removed from the model (`edmfx_entr_detr.jl:632-634`) |

Nothing refuses any of these for the energy source tags. The parent-budget
ledger refuses every `AbstractEDMF` and both 2M schemes at setup, because "their
subdomains are a modelling question before they are a bookkeeping one"
(`coverage_registry.jl:176-191`). The water tags refuse 2M and P3, and not EDMF
(`tagged_water.jl:175-191`).

### Where ice changes the picture

**1. For ice, sedimentation's upward branch is the rule.** Each face shares the
flux `-w q (e_int + Φ + K + c)` by the shares of the cell that loses the energy
(`energy_source_tags.jl:896-903`). Ice at `T` carries
`e_int_ice(T) ≈ -333.6 kJ/kg - 2.07 kJ/kg/K × (273.16 K - T)`, its fusion heat
and more. At 250 K that is about -382 kJ/kg. With `c` = 110,495 J/kg, the
energy per kilogram of falling ice is negative below about 27 km at 250 K, and
higher when colder. So every tropospheric ice or snow face takes the **lower**
cell's shares. Liquid stays positive, unless it is colder than about 247 K at
the ground.

The branch keeps the partition closed and the tags non-negative, because the
donor gives what it holds. But it moves provenance **up while the ice falls**.
Under a vertical partition, the lower region's tag crosses the boundary upward
with every snowfall. That is accounting, not a path any air took. The guide
must say so. The build check `subgrid_check_cold.jl` shows the branch on a real state;
see *Build checks*.

**2. Under EDMF, the sedimentation corrections can point either way.** Per
kilogram, the updraft correction is `e_int(Tʲ) - e_int(T)` plus a kinetic term.
That is `cv_i (Tʲ - T)` for ice, about 2 kJ/kg per kelvin, and its sign follows
`Tʲ - T`. The environment's mass flux is a residual, `ρqw - ρaʲqʲwʲ`
(`water_advection.jl:177`), which changes sign where the updraft holds more
falling condensate than the grid mean. Both are small, about 1% of the ice
flux's `e + Φ + c` per kelvin. But shared on their own, a correction against the
main flux would move provenance both ways through one face. So the tags should
share each species' **total** face flux once, by its sign.

**3. The SGS mass flux of `E` has no fixed direction either.** It is
`Σₖ ρᵏaᵏ(u³ᵏ - u³)(mseᵏ + Kᵏ - h_tot)` plus `c` times the `q_tot` flux. It
points against a rising updraft wherever `mseʲ + Kʲ < h_tot`, as at an
updraft's top. The `c` part follows the moisture flux instead. So a donor chosen
by the updraft's direction could take energy from a cell that gains it, and the
tags could go negative. The donor must follow the sign of the flux of `E`, as
sedimentation's does. This holds with or without ice. With ice, the updraft and
the environment also carry different amounts of condensate, which is what feeds
point 2.

## What it changes: the sub-grid part

### Options

**A. Refuse `PrognosticEDMFX` with energy source tags, now.** One check at
configuration time, with a message that names the unshared terms. It stays as
long as B is not built. `edonly_edmfx` is allowed, with a warning that its eddy
diffusion moves the tags as tracers. About 40 lines.

**B. Share the parent's SGS fluxes of `E` by the losing cell's shares.** This
is the rule sedimentation and the audit already use. The shares are
sedimentation's: a partition tag's clamped share of `E` divided by the
partition's sum, and a source tag's plain clamped share
(`_energy_source_share_field`, `energy_source_tags.jl:919-922`).

  - **B1, the SGS mass flux.** At each face, the flux of `E` is the parent's own
    reconstruction, `Σₖ ᶠρᵏ (u³ᵏ - u³) · face[aᵏ(mseᵏ + Kᵏ - h_tot)]` with
    `edmfx_sgsflux_upwinding`, plus `c` times the same sum for
    `aᵏ(q_totᵏ - q_tot)`, the part that moves `ρ`. Each tag takes that face flux
    times its share in the cell **below** where the flux points up, and **above**
    where it points down. The top and bottom faces carry no flux, since
    `ᶜadvdivᵥ` has zero-flux boundaries. `_face_value_flux`
    (`energy_source_tags.jl:961-967`) already gives the reconstruction, times
    `ᶠinterp(ρᵏ J)/J`, so the parent's code is not touched. A new face scratch
    field holds the sum over subdomains. It lives in `energy_source_scratch`,
    because `p.scratch` is dual-converted for the implicit tendency.
  - **B2, the sedimentation corrections.** Under `PrognosticEDMFX`, build each
    species' total face flux, the grid-mean one plus the two corrections, and
    share it once, by its sign. So `sediment_energy_source_tags!` takes a face
    flux instead of a cell value, and under EDMF it is called after the
    corrections. The corrections move no mass, since the subdomain mass fluxes
    sum to the grid mean's (`water_advection.jl:177`). So they carry no `c`
    part. Without EDMF the flux and the result are today's.
  - **B3, optional: the SGS diffusive flux under `enthalpy`.** Share the
    parent's face flux, `-ρK_h ∇s_d - ρK_h (h_eff + Φ) ∇q_tot_eff - ρK_e ∇h_tot`
    plus `c` times its `ρ` part, by its sign. Then skip the tags in the tracer
    loop (`edmfx_sgs_flux.jl:390-410`) under `enthalpy`. This extends the audit
    beyond the scope decided on 2026-09-11, where the SGS closures stay in
    tracer form. It is listed so that the owner can defer it knowingly.
  - **B4, the guard.** `edmfx_sgs_flux.jl:403-409` applies the grid mean's
    specific tendency to the updraft's copy of every grid-scale tracer, and
    assumes the copy exists. Skip a tracer the updraft does not carry, as the
    horizontal path already does (`:556`). This is shared model code, and the
    fix also lets the water tags, the `ρe_tag_*` family and the stratospheric
    passive tracers run there. Those are grid-scale only by design
    (`prognostic_variables.jl:203-206`). The alternative is to refuse
    `edmfx_vertical_diffusion: true` with tags, and leave the parent alone.

  - **Where it runs.** Recommended: in `implicit_tendency!`, beside the parent's
    flux, as sedimentation does. Then the tags follow the parent's flux at the
    Newton iterate, not at the stage state, and B adds no timing gap. The
    tags' implicit rows carry the diffusion block only, so the Newton update
    sees this term without its derivative. That is sedimentation's arrangement,
    and E32 measured it working. The alternative is the explicit tendency, as
    the audit does, with the audit's timing gap.
  - **Why no Jacobian block.** The SGS flux moves the energy anomaly
    `a(χʲ - χ)`, not the air. Against the tags' total, the anomaly is small:
    `|F|/E ≈ a (wʲ - w)(χʲ - χ⁰)/(χ + c)`, about 0.1 × 2 m/s × 2 kJ/kg /
    100 kJ/kg = 4e-3 m/s. So a tag's Courant number is about 4e-3 m/s times
    `dt/dz`. That is 0.01 on the DYCOMS EDMF column at 120 s and 50 m, and 0.02
    on a 400 s, 100 m sphere. The air's own exchange, `a (wʲ - w) dt/dz`, is
    about 0.5 on that column. That is why the updraft's tracers need implicit
    blocks and B does not. The numbers are an estimate from typical sizes, not
    read from a run.
  - **Both transports.** B applies under `tracer` and `enthalpy`. There is no
    tracer form of the SGS mass flux for a field without an updraft copy, so
    there is nothing else for `tracer` to be consistent with. Under `tracer`,
    B makes the SGS part exact, while grid-mean advection keeps its pressure
    work gap.
  - **Its limit, for the guide.** A tag's composition in the updraft is taken as
    that of the cell it leaves. The parent's flux moves the energy anomaly, about
    fifty times less than the air the overturning exchanges (`χ + c` against
    `χʲ - χ⁰`, about 1e5 against 2e3 J/kg). So the SGS flux moves the energy
    that convection carries, but it does not mix the bulk provenance the way it
    mixes the air. A region boundary inside a convective layer stays sharper
    than the air would leave it. Surface energy spreads up at the rate the
    parent carries it up.

**C. Give each updraft its own tag shares, later.** Carry `σʲₖ`, each tag's
share of the updraft's `E`, as a new updraft scalar. It is advected with the
updraft, entrains the environment's shares, and is detrained through `ρa`. Then
a tag's SGS flux is a passive tracer's, with the updraft value `σʲₖ (χʲ + c)`,
and provenance mixes with the air.

  - Exact closure needs `Σₖ σʲₖ = 1` in every updraft. So the shares need a
    renormalization, and the updraft's own non-conservative terms (buoyancy,
    microphysics) must not act on them.
  - The parent's difference is taken against `h_tot`, and the tags' total per
    kilogram is `e_tot + c`. So under `tracer`, a pressure-work-like gap of
    `p/ρ` appears in the SGS flux too. Under `enthalpy` the updraft value must
    use the updraft's enthalpy.
  - The exchange is stiff, with a Courant number near 0.5 to 1 (above), so it
    needs implicit blocks. Passive SGS tracers have them
    (`manual_sparse_jacobian.jl:1445`, `:1605`).
  - The cost is `n_tags × n_updrafts` new fields, plus the blocks. That is
    roughly three times B.

### Recommendation

A now. Then B1, B2 and B4 in one PR, to be validated by the D4 pair and D5 (see
*Runs*). Once B is in, A is narrowed to `updraft_number` > 1, where the
sedimentation corrections assume one updraft (`water_advection.jl:135`) and the
parent errors anyway (`advection.jl:388-390`). B3 waits until the D4 pair shows
how much the SGS diffusive flux leaves. C waits until a question needs bulk
provenance mixed by convection.

## What it changes: the microphysics part

### What the code does today

| scheme | species that sediment with energy | numbers and rime | does microphysics write `ρe_tot`? | status |
|:-- |:-- |:-- |:-- |:-- |
| 0M | none. The rain-out is the microphysics sink (`microphysics/tendency.jl:77-87`) | — | yes, bracketed on both paths | measured (C6, C7) |
| 1M | `ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno` | — | no (`:153-162`) | measured, warm only (E32, E33) |
| 2M | the same four. `ρq_icl` and `ρq_sno` are in the state (`prognostic_variables.jl:112-116`, `:144-149`) with no warm-rain sources (`microphysics/tendency.jl:206-209`) | `ρn_lcl`, `ρn_rai` sediment (`implicit_tendency.jl:284-293`) and carry no energy | no (`:213-223`) | **disabled in the parent** on this branch (`precomputed_quantities.jl:160-167`); build-checked |
| 2MP3 | the same four; `ρq_icl` includes the rime | `ρn_ice`, `ρq_rim`, `ρb_rim` sediment with the ice (`implicit_tendency.jl:305-315`) and carry no energy of their own | no (`:266-283`) | **disabled in the parent**, and broken behind that gate; see below |

**2M and 2MP3 are switched off on this branch.** `precomputed_quantities`
asserts that the microphysics is neither, "temporarily disabled: incompatible
with CloudMicrophysics 0.37 pending a fix" (`precomputed_quantities.jl:160-167`).
The comment names a missing `q_tot` argument after a compat bump. So no run
with either scheme builds its cache, with or without tags. The build check hit
the assertion for 2M and for 2MP3. Everything below about 2M is by reading the
code, for the day the gate is lifted.

**Coverage.** `sedimenting_mass_names` gives `ρq_lcl`, `ρq_icl`, `ρq_rai` and
`ρq_sno` wherever they are in the state (`tracer_processes.jl:99-100`,
`:151-155`). Those are the only species whose sedimentation moves `ρ`,
`ρq_tot` and `ρe_tot`, so they are the only ones the tags must follow. Number
concentrations and rime fields do not matter for energy. The water tags refuse
2M for number provenance (`tagged_water.jl:185-191`), and that reason does not
carry over. `vertical_advection_of_water_tendency!` does not call
`sedimenting_mass_names`. It lists the same four species by hand
(`water_advection.jl:51-56`), and the tags follow that list. The two agree
today.

**Brackets.** The microphysics tendency is bracketed for the tags and the
records on both paths: explicitly through `open_applied_update!`
(`remaining_tendency.jl:233-242`, `applied_update.jl:51-61`,
`tagged_water.jl:645-661`), and implicitly at `implicit_tendency.jl:65-80`.
Under 1M, 2M and P3 the microphysics writes only the species, so the bracket's
increment is exactly zero. A `microphysics` source tag or record then stays
zero. That is correct, but nothing says so. The label warnings fire on
`precipitation` only (`tracer_config.jl:536-553`, `:759-768`), and the record's
warning cannot see the microphysics model (`:747-748`). Under these schemes the
energy leaves through sedimentation, which the `precipitation` record sees and
the tags follow as transport. The moisture fixer writes species only
(`moisture_fixers.jl:71-100`). Surface precipitation writes the slab only
(`surface_temp.jl:30-47`).

**What refuses or warns today.** For the energy source tags, nothing depends on
the scheme. `_check_sedimentation_offset` warns when condensate sediments and
there is no offset (`energy_source_tags.jl:208-219`).

**Behind the gate, P3 is broken in the parent too.** Found in passing, by
reading. The build check stops at the gate first, so these are not
build-checked. They will surface once the gate is lifted.

  - `set_precipitation_velocities!` for 2MP3 unpacks `ᶜwnₗ` and `ᶜwnᵣ` from
    `p.precomputed` (`microphysics_cache.jl:608`). The cache allocates `ᶜwₙₗ`
    and `ᶜwₙᵣ` (`precomputed_quantities.jl:315-316`), which are different names.
  - It never sets `ᶜwₛ` (`microphysics_cache.jl:604-671`). But `ρq_sno` is in the
    P3 state (`prognostic_variables.jl:150-163`), and
    `vertical_advection_of_water_tendency!` moves `ρ`, `ρq_tot` and `ρe_tot` with
    `ᶜwₛ` (`water_advection.jl:55`).
  - `ρq_rai`, `ρq_sno`, `ρn_lcl` and `ρn_rai` do not sediment in their own
    equations under P3. The 2M block tests `isa NonEquilibriumMicrophysics2M`
    (`implicit_tendency.jl:281`), and 2MP3 is not a subtype of it
    (`types.jl:147`, `:157`). But `ρ`, `ρq_tot` and `ρe_tot` still move with the
    rain.
  - There is no P3 method with `PrognosticEDMFX`
    (`microphysics/tendency.jl:19`, `:266`).

The tags cannot be more right than the parent. So P3 support is a parent fix
first. The tags then need nothing beyond 2M.

### Design

  - **M1. `check_energy_source_tagging_supported`**, next to
    `check_water_tagging_supported` in pattern, called from `AtmosTagging`
    (`tracer_config.jl:876-883`) with the parsed `microphysics_model`,
    `turbconv`, `updraft_number` and `edmfx_vertical_diffusion`:
      - dry, 0M, 1M and 2M: accepted;
      - 2MP3: refused, naming the parent's gaps above, until D3 passes;
      - `prognostic_edmfx`: refused (option A). Once B is in, only
        `updraft_number` > 1 is refused, and `edmfx_vertical_diffusion: true`
        too unless B4 is in;
      - `edonly_edmfx`: accepted, with a warning that its eddy diffusion moves
        the tags as tracers.
  - **M2. Exact label warnings.** Pass the microphysics model to
    `warn_inactive_energy_source_labels` and `warn_inactive_record_labels`.
    Warn on `microphysics` under 1M, 2M and P3, for the source tags and the
    energy record. Warn on `precipitation` for a record under 0M only, where it
    cannot fire. For the source tags, keep warning on `precipitation` always.
  - **M3. A test that the two species lists agree:** the one in
    `vertical_advection_of_water_tendency!` and `gs_sedimenting_mass_candidates`.
    A new species added to one list and not the other would sediment energy
    that the tags do not follow. Refactoring the hard-coded list would touch the
    parent. The test does not.
  - **M4. 2M needs no tag code.** Once the model lifts its gate, it needs a
    run (D2) and one integration item. Until then M1 need not refuse 2M, since
    the model already does.
  - **M5. P3 needs the parent fixed** (above), then D3. Lifting the 2M gate is
    not enough for P3. Whether those fixes belong upstream is the owner's call.

## What it does not change

  - The default path: 0M and 1M without EDMF are bit for bit today's.
  - The model. The tags never act on it, so its state is bit for bit the same
    with tags on and off. A test asserts that for EDMF too.
  - The attribution rule, the repair, and the audit's three terms.
  - Number and rime fields. They get no tag and no share.
  - The Jacobian.
  - B3 and C, unless the owner takes them.

## What is left in the residual by design, with B built

  - The tags' SGS flux follows the parent's at each Newton iterate, without a
    derivative block, as sedimentation does.
  - Under `tracer`, grid-mean pressure work, as today (E25, E31).
  - Without B3, the SGS diffusive flux's form mismatch, and `c` times the `ρ`
    change it makes, since it has no bracket. Horizontal SGS diffusion stays
    in tracer form in any case.
  - The approximation of B itself does not add to the residual. It limits the
    reading: the updraft's composition is its donor cell's.

## Tests

  - **Unit** (`energy_source_tags_tests.jl`): the donor by the sign of a face
    flux, both signs, on a step partition with exact zeros, with a flux that
    opposes the updraft's direction.
  - **Unit:** M3's list equality. M1's refusals and M2's warnings, from
    `AtmosConfig` and `AtmosTagging` alone, with no compile of the solve.
  - **Integration, the cold column** (`PrecipitatingColumn`, 1M, with an offset):
    the upward branch on a real state. On a step partition inside the ice
    layer, the lower tag gains above the step, and the partition's sedimentation
    tendency equals the parent's to 100 eps. `subgrid_check_cold.jl` is that test,
    written as a script. It could replace the warm DYCOMS state of item 8 in
    `energy_source_tags_integration.jl`, and cover both branches in the same
    compile.
  - **Integration, 2M:** the same on the cold column, once the model lifts its
    2M gate. One more compile.
  - **Integration, EDMF**, the DYCOMS RF02 column (1M, one updraft, offset):
    the partition's tendency from `edmfx_sgs_mass_flux_tendency!` equals the
    parent's `ρe_tot + c·ρ` tendency to 100 eps. So does the one from
    `vertical_advection_of_water_tendency!`, corrections included. The model's
    state is the same with and without tags. One EDMF compile; the build check
    gives its cost.

## Runs, each needing its own approval

All six are in `configs/`. Each header says what it is for, what it decides,
and whether it can run today.

  - **D1, column, 1M, cold:** sedimentation's upward branch in a run, which §7
    of FINDINGS lists as not established. It runs today; the stepping check
    above ran its column for a minute. Its ice mostly sublimates in that first
    minute, so D1 samples every minute and ends after an hour. A persistent
    ice cloud on a column would test the branch for longer. ISDAC is the
    obvious case, but it ships only as an LES box (`les_isdac_box.yml`), and
    no column version was checked here.
  - **D2, column, 2M, cold:** the same under 2M. It says whether 2M needs
    anything beyond 1M. It cannot run today, because the model disables 2M
    (above). It is ready for when 2M returns.
  - **D3, column, P3, cold:** cannot run today, behind the same gate and then
    the P3 gaps above. It also needs a P3 initial state. It is ready for when
    it can.
  - **D4, the EDMF column pair**, DYCOMS RF02 under 1M, `tracer` and
    `enthalpy`: by the code they run today with
    `edmfx_vertical_diffusion: false`. They were not stepped here, because the
    full EDMF build does not finish within the login node's 15 minutes. A
    compute node has no such limit. The
    `enthalpy` half removes grid-mean pressure work, so what grows in its
    residual is mostly the unshared SGS flux. That is what B must close. After
    B, the same pair is B's validation.
  - **D5, EDMF deep convection with ice**, TRMM LBA under 1M: glaciated
    updrafts, falling snow, and the corrections with ice. It runs today only
    with `edmfx_vertical_diffusion: false`, and then it measures the gap. It
    is meant for after B.

The series' validator carries all six in `AUDIT_REQUIRED`, `STATE_CHECK` and
`DENSITY_CHECK`, since each is a column whose records are summed
(`analysis/validate_configs.py`).

## Size

  - A with M1 and M2: about 120 lines with docstrings, and 80 of tests. No
    compile in the tests.
  - B1, B2 and B4: about 220 lines, and 200 of tests, one EDMF compile.
  - B3: about 100 lines, and 80 of tests.
  - C: about 700 lines, 400 of tests, and Jacobian blocks.

These are estimates.

## Build checks

Run on the terrabyte login node on 2026-09-11, from the scratch directory, with
the `.buildkite` environment and the terrabyte CPU depot. The scripts are
`analysis/subgrid_light_check.jl`, `subgrid_check_cold.jl`,
`subgrid_check_edmf.jl` and `validate_d_configs.jl`, and their logs are in
`output/subgrid_build_checks/`. No model file was touched.

  - **A full EDMF simulation with tags does not build within 15 minutes here.**
    `subgrid_check_edmf.jl` built the cache in 108 s, and then the implicit problem and
    its Jacobian were still compiling when the time limit ended it (exit 124).
    So `subgrid_light_check.jl` builds what `get_simulation` builds up to the cache, and
    calls single tendency functions on it.
  - **EDMF, the DYCOMS RF02 column** under 1M, with the shipped settings,
    `edmfx_vertical_diffusion: true` included. The model, the state and the
    cache build, the cache at 198 s. The updraft carries `ρa`, `mse`, `q_tot`,
    `q_lcl`, `q_icl`, `q_rai` and `q_sno`, and no tag field. With the offset,
    `E` is positive in every cell.
      - **The SGS diffusive flux fails**, with
        `type NamedTuple has no field e_src_strat`. That is the lookup at
        `edmfx_sgs_flux.jl:406`, on the first grid-scale tracer the updraft
        does not carry. The water species before it pass, because the updraft
        carries them. So every shipped EDMF config fails with tags. The
        integrator would hit this in its first implicit evaluation, since
        `implicit_diffusion: true` puts the call in `implicit_tendency!`.
      - **The SGS mass flux reaches no tag.** On a synthetic updraft (a tenth
        of the area, rising, 1.5 kJ/kg warmer and 1 g/kg moister below 800 m,
        and 0.5 kJ/kg cooler above), `edmfx_sgs_mass_flux_tendency!` changes
        `E` by a summed absolute tendency of 11.5 W/m³ over the column's
        cells. The `c·ρ` part alone sums to 0.60 W/m³. It changes the
        partition by exactly zero. So all of it goes to `e_src_res`. The size
        is the synthetic state's and means nothing. That the partition gets
        none of it is the result. *Corrected on 2026-09-11: this first read
        "11.5 W/m² gross over the column, 0.60 of it the `c·ρ` part". The
        script sums over cells without a layer depth, and 0.60 is in the same
        unit, not a fraction.*
      - **Sedimentation under EDMF does not close.** With rain in the grid mean
        and three times as much in the updraft between 300 and 900 m,
        `vertical_advection_of_water_tendency!` gives the partition a tendency
        that misses the parent's by 3.4e-3 of its largest value. Without EDMF
        the integration test holds the same comparison to 100 eps. The miss is
        the two corrections, which the tags do not share.
      - The whole light check took 256 s.
  - **1M, the cold column** (`PrecipitatingColumn`, 100 levels to 10 km, with
    the offset), at t = 0. It has cloud ice, snow, cloud liquid and rain, and
    `E` is positive in every cell. The whole check took 131 s.
      - **The upward branch is real and universal for ice.** All 79 cells
        holding cloud ice and all 69 holding snow carry negative energy per
        kilogram, geopotential and offset included, down to −193 kJ/kg. None of
        the 55 liquid cells or the 50 rain cells does.
      - **On a step partition at 6.5 km**, inside the ice layer,
        sedimentation moves `lower` in the one cell above the step, and moves
        `upper` in no cell below it. So the step's face takes the lower cell's
        shares, which only the upward branch does.
      - **Closure holds:** the partition's sedimentation tendency matches the
        parent's to 5.7e-15 of its largest value, within 100 eps. On the step
        partition, 5.9e-15.
      - Each species' own sedimentation adds up exactly to what `ρq_tot` is
        moved by.
  - **2M and 2MP3, the same cold column.** The model and the state build. The
    cache does not: `AssertionError: 2M and 2M+P3 microphysics are temporarily
    disabled: incompatible with CloudMicrophysics 0.37 pending a fix.`
    (`precomputed_quantities.jl:160-167`). This is the model's own gate, and
    the tags play no part in it. So the P3 gaps listed above were not reached.
  - **The six D configs validate.** `validate_d_configs.jl` applies the checks
    of `analysis/validate_configs.py`, with the D runs added to its three sets.
    Then it runs the model's own parsing on each: `AtmosConfig`,
    `AtmosTagging`, the closure checks, and `get_atmos`, which runs
    `check_case_consistency`. All six pass. D2 and D3 parse; they stop only at
    the cache, as above.

  - **1M, the cold column, stepped.** `subgrid_check_cold.jl 1M` builds the full
    simulation of the same 100-level column, in 246 s, and steps it six times
    at 10 s. It succeeds, with the repair on.
      - `E` stays positive in every cell, and every tag stays non-negative.
      - After the minute, sedimentation still closes to 1.6e-15, within 100
        eps. The 16 cells still holding cloud ice and the 17 holding snow all
        carry negative energy, so they still take the upward branch.
      - Most of the initial ice is gone within that minute: 16 cells above
        1e-9 kg/kg against 79 at the start. Nothing falls through the 6.5 km
        step any more. The profile's air is below ice saturation there, so the
        ice sublimates rather than falls. D1's header says so. A case that
        keeps making ice, such as D5, tests the branch for longer.
      - The closure residual after the minute is 1.8e-3 of `∫|E|`, gross. That
        is the first-minute jump the series knows (E13, E25), not separated
        here.
      - 38 ms per step on the login node, compile excluded.

## Decisions for the owner

 1. **Refuse `PrognosticEDMFX` with energy source tags now** (A), with
    `edonly_edmfx` allowed and warned. Or run it and let `e_src_res` carry the
    SGS terms.
 2. **Build B**, sharing the SGS mass flux and the sedimentation corrections by
    the losing cell's shares. And whether it applies under both transports
    (recommended), or under `enthalpy` only.
 3. **Where B runs:** in the implicit tendency beside the parent's flux, as
    sedimentation does (recommended), or in the explicit tendency, as the audit
    does.
 4. **The failure with `edmfx_vertical_diffusion: true`:** guard the shared loop
    (B4), which also lets the other grid-scale-only tracers run there, or refuse
    that setting with tags.
 5. **B3:** extend the audit to the SGS diffusive flux, or keep the SGS closures
    in tracer form, as decided on 2026-09-11.
 6. **2M and P3:** the model's own gate refuses both today. Decide who lifts
    it, and whether the tags then refuse P3 at configuration until the parent's
    P3 sedimentation is fixed.
 7. **The inert labels:** make the label warnings see the microphysics model
    (M2).
