# Review of 78e19e23 (updraft exchange and updraft copies)

**Verdict: not ready as it stands. There is one blocker, the CI time of
`tagging_source_increment`. The physics and the parity argument hold. Six
should-fix items remain, and they are small.**

This review read `git diff origin/main...HEAD` (base `c99ff7bd`) in
`../ClimaAtmosResiDyn-upd`. No simulation ran and no job was submitted.
"Verified" means I read it in the code at the lines cited. Three checks did run:

  - The pinned JuliaFormatter 2.10.1, on copies of every changed `.jl` file. It
    reported them already formatted.
  - A plain-Julia check on 1.11 that a `Val` passed to a broadcast, which
    `Base.broadcastable` wraps in a `Ref`, allocates nothing. It allocated
    nothing. Julia 1.10 is not installed here.
  - I read the test logs in `$SCRATCH/claude_work/{inc_run,upd_run}`.

Abbreviations. EST = `src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl`.
INC = `test/energy_source_tags_increment_integration.jl`. TEST =
`test/energy_source_tags_edmf_integration.jl`. UNIT =
`test/energy_source_tags_tests.jl`. MSJ =
`src/prognostic_equations/implicit/manual_sparse_jacobian.jl`.

## Blocking

### B1. `tagging_source_increment` will probably overrun CI's 90-minute limit

- **Where:** INC:417-444 (a third EDMF model, `energy_source_tag_updraft_copy:
  true`); `.github/workflows/ci.yml:185,210`; `downgrade.yml:46,76`.
- **What:** The copies are a new type parameter and new state. So the copies
  run compiles the whole EDMF tendency and solver a third time. FINDINGS E73
  says it doubles the build: 789 s against 402 s. The group's measured times
  are:
  - on terrabyte `hpda2_test`, before this change with two models,
    39 min (`inc_run/inc_integration-13504941.out`);
  - on terrabyte now, 72 min at 3ec098f1 and 69 min at e010f780
    (`upd_run/upd_integ-13523324.out`, `upd_integration-13528770.out`);
  - on CI for #94, with two models, 54.5 min (1.11) and 56 min (1.10). This is
    in `agent_reviews/pr94_04d63916.md:57`. That review cut the file down to
    two models for exactly this reason.
- **Failure scenario:** CI runs about 1.4 times the terrabyte time. That puts
  this group at about 95-100 min on 1.11, against a 90-minute job timeout. A
  cancelled job reports as failed. It also never runs the files that had not
  started. `runtests.jl:161-168` warns about this.
- **Fix:** Move the copies run into a group of its own, for example
  `tagging_source_updraft`. Add it to the `ci.yml` and `downgrade.yml`
  matrices, and describe it in `docs/clima_atmos_specific.md`. Or get a
  workflow_dispatch timing first. If CI shows the group under about 70 min,
  this item drops to "should fix".

## Should fix

### S1. The exchange assumes the region tags partition the domain, but under `tracer` nothing requires that

- **Where:** EST:1850-1853 (`_share_of`) and EST:1809-1814 (the partition
  flags). The only check is `_check_region_partition`
  (`tagged_tracers.jl:874-893`). It warns, and it skips the case with no region
  tags at all. `types.jl:2567-2578` refuses a missing partition only under
  `enthalpy_increment`.
- **What:** A share is `ε_i / Σ_partition ε`. It means "fraction of the
  energy" only where the region tags without sources add up to `E`.
  - With no such tag, `total = 0` everywhere, so every exchange is zero. The
    default mode then silently gives the old C1b-only result, while the docs
    say that each tag takes an exchange.
  - With an incomplete partition, the total is tiny wherever the region's mask
    is near zero. There a region tag's share is 1 in every subdomain, so its
    exchange vanishes where it matters. A source tag's share saturates at 1
    because of the cap. So where the plume carries a tag that the grid mean
    lacks, `Δφ` jumps from 0 to 1, and `X` becomes the updraft's whole energy
    flux, `ρaʲ(u³ʲ−u³)Aʲaʲ`.
- **Failure scenario:** `energy_source_tags: [{name: bl, region:
  {type: tanh_altitude, z_center: 1000, above: false}}, {name: sfc, source:
  surface_flux}]` under `prognostic_edmfx` with `tracer` transport, which is
  accepted with a warning. Where the updraft overshoots the boundary layer,
  `sfc` takes fluxes of order 1e3-1e4 W/m², and the repair clips them. Before
  this change, `sfc` moved by its bounded fraction of the parent's flux.
- **Fix:** When the exchange will run (PrognosticEDMFX, `sgs_mass_flux` on,
  no copies), refuse at cache build if the region masks do not sum to 1. This
  is the check `_check_increment_partition` (EST:320-338) already makes, so
  reuse it. Point the message at adding a complement or at
  `energy_source_tag_updraft_copy: true`. Also say in the docs that the
  exchange needs a partition.

### S2. The plume step can overflow in Float32 and then poison a whole column of tags

- **Where:** EST:1828-1841.
- **What:** `a = entr·Δz/wʲ·ρ/ρa⁰` is not bounded. `rising` needs only
  `wʲ > 0`, and `entr` has a part that does not scale with velocity
  (`compute_entrainment`, `edmfx_entr_detr.jl:183-192`). In Float32 with a
  coarse sphere level (Δz ≈ 3 km, `entr` ≈ 1e-3 s⁻¹):
  - Once `wʲ` falls below about 3e-33 m/s, `a·ε` overflows. `ε` is about
    3e5 J/kg with the offset.
  - The step then returns `Inf`, since `(εʲ + Inf)/(1 + a) = Inf`. `Inf` is not
    `NaN`, so the sentinel does not restart the plume. It carries `Inf` up to
    the next restart.
  - `_share_of` then gives `Inf/Inf = NaN`, and `min(NaN, 1)` stays `NaN`. So
    every tag's tendency in that column becomes `NaN`, and transport spreads it.
  - Below about 1e-38 m/s, `a` itself is `Inf`, and the step gives `NaN`
    directly.
  - The model is untouched, but the diagnostic is lost. Center `wʲ` is the mean
    of two face values after the filter's `max(u₃, 0)`. So a tiny positive
    value at the updraft's top is possible, although rare. V2 and G2 run in
    Float32.
- **Fix:** March with the convex weight, which cannot overflow. Keep the guard,
  because in Float32 `wʲ·ρa⁰` can underflow to 0 while `mixing` is also 0:
  ```julia
  mixing = max(entr, zero(FT)) * Δz * ρ
  weight = rising & (mixing > zero(FT)) ? mixing / (mixing + wʲ * ρa⁰) : zero(FT)
  ...
  return map((εʲ, ε) -> εʲ + weight * (ε - εʲ), εʲ_below, ε̄)
  ```
  Update the UNIT check at `rising[2] ≈ a`. Add a Float32 case with
  `wʲ = FT(1e-40)` that asserts the result is finite.

### S3. The default mode is on for every EDMF run with tags, but it has not been compiled on a GPU

- **Where:** EST:1715, 1748, 1783-1795.
- **What:** Each tag's kernel reads the tag fields three times. It reads them
  once for each of the two `_share_of(ᶜε̄, …)` calls, and once more inside
  `ᶜε⁰`. That is about 3N + 25 field arguments per kernel, where N is the
  number of tags. For the 7 tags of the shipped example config, that is about
  46 fields. `hyperdiffusion.jl:65-67` records that a fused broadcast over
  more than about 32 tracer fields does not compile on a GPU. That is not the
  same failure, but it is the same kind of risk. Also, each cell recomputes
  `ε̄`, the partition sum and the shares N times, so the cost per cell grows as
  N².
- **Fix:** Materialize `ᶜε̄` and `ᶜε⁰` into two more `NTuple` scratch fields,
  as `ᶜe_src_plume` already is. Then each tag's kernel reads three tuple fields
  instead of 3N tag fields, and the work is O(N). Then compile it once on a
  Levante GPU, or say in the docs that only the CPU is verified.

### S4. Stale comments and docs that this change makes wrong

- **Where and what:**
  - `src/prognostic_equations/implicit/implicit_tendency.jl:119-120` still
    says "The energy source tags have no updraft copy, so the SGS tracer loop
    above skips them." Under the audit, that loop is what moves them, and this
    call is a no-op.
  - `docs/src/tracer_configuration.md:423-426` says "The tags have no updraft
    copy". It mentions neither the exchange nor the audit.
  - `docs/clima_atmos_specific.md:109-116` says that `tagging_source_increment`
    "builds the EDMF column twice". It is now three times, and the updraft
    tests are not mentioned. Lines 99-104 (`tagging_source_edmf`) do not
    mention the exchange check that TEST:186-202 added.
- **Failure scenario:** The next session follows stale documentation. AGENTS.md
  asks that stale parts of the code map be updated.
- **Fix:** Update these four places, together with B1.

### S5. The new branch of the restart guard has no test

- **Where:** `energy_source_checkpoint.jl:155-166`.
- **What:** UNIT tests the ledger's mismatch both ways (UNIT:692-698) but not
  the copies. Nothing checks that a file with copies is refused under a
  configuration without them, or the reverse. Nothing checks that
  `Y.c.sgsʲs.:(1)` works as the `Y.c` of `check_restart_fields`.
- **Failure scenario:** A later refactor drops or breaks the branch. A restart
  then silently changes the mode. For example, a checkpoint made in the audit
  is restarted in the default mode. The state then carries copies that nothing
  reads, or the restart fails later with a confusing error.
- **Fix:** Add two UNIT cases to the existing restart tests, with a small
  `FieldVector` whose `c.sgsʲs` has and lacks `e_src_*`, and match the
  "updraft copies of the energy source tags" message.

### S6. The zero-sum claim holds only where every subdomain's partition total is positive

- **Where:** EST:1648-1652 (the docstring), EST:1850-1853, and the NEWS line
  "closure is untouched".
- **What:** `_share_of` returns 0 where a subdomain's partition total is 0. In a
  cell where the grid mean's total is positive and one subdomain's is 0,
  `Σ_partition Δφ = −1`, and the partition's `X` sums to `−Aᵏaᵏ`, not 0. This
  happens:
  - with `energy_source_tag_offset: 0`, which is allowed, at the edge where
    `e_tot` changes sign;
  - with `energy_source_tag_repair: false`;
  - when the environment is almost empty and every partition tag is clamped
    there.

  With a positive offset and the repair on, it does not occur. C1b has the same
  weakness, so this is not a regression. But the docs state the zero sum
  without conditions, and the fix is one line.
- **Fix:** Take `Δφ = 0` for all tags where either total is 0. For example, add
  a helper `_share_difference(εᵏ, ε̄, i, partition)` that returns 0 unless both
  totals are positive. Then the sum is zero at every face, up to rounding, in
  every configuration.

## Nice to have

- **N1. Memory.** `ᶜe_src_plume` (EST:380-383) is allocated for every run with
  tags, including runs without EDMF, and in the audit where nothing reads it.
  The AD caches keep a Dual copy. Allocate it only under PrognosticEDMFX
  without copies. The same applies to the existing `ᶠe_src_sgs_flux`.
- **N2. Plume velocity.** The model advects an updraft tracer first-order
  upwind in advective form, which is `u³_{k−½}(χ_k − χ_{k−1})/Δz_k`
  (`implicit_tendency.jl:192-193`). The plume uses the center value `wʲ`.
  Using the lower face's velocity would match the audit's discretization
  exactly. It might reduce the 16% difference in the first hour (E73) a
  little, though that difference is mostly the copies' spin-up.
- **N3. Docstring accuracy.** EST:1641-1642 says a source tag's share is "as in
  `energy_source_source_sediment_share`". That function divides by the parent,
  `E`, while the exchange divides by the partition's sum. They agree only up to
  `e_src_res`.
- **N4. Docs on the audit's cost and clamping.** Neither is mentioned.
  - Copies are not splittable: their chain has 4 elements (MSJ:712-720). So they
    enter the coupled nested solver and double the build time.
  - With `edmfx_filter: true`, `enforce_edmf_updraft_constraints!` clamps each
    copy to `[0, max(0, ρe_src)/ρa]` (`mass_flux_closures.jl:301-314`). This is
    harmless while the tags are non-negative, which holds with gain-only
    sources and the repair. But the docs say only that the model "filters" the
    copies.
- **N5. Test gaps.**
  - No test covers the exchange under `first_order` or `third_order`. Both
    columns and D4 use `none`. A cheap alternative is a unit test that each
    `_face_value_flux` scheme is linear in `ᶜχ`, on a ClimaCore column.
  - The exchange has no Float32 integration test. `tagging_source_float32`
    has no EDMF.
  - The audit's parity is not tested with `edmfx_vertical_diffusion: true`.
    That is the shipped DYCOMS config, and it is the one path where copies
    newly pass the `has_field` gate at `edmfx_sgs_flux.jl:385-395`.
  - Neither `AtmosTagging` error is tested through the config (copies without
    tags at `tracer_config.jl:1348`; copies with a turbconv other than
    `prognostic_edmfx`). Only the helper functions are tested.
- **N6. Allocation bounds.** INC:418 `<= 8` and TEST:359 `<= 24` were measured
  on 1.11 only. CI also runs these groups on 1.10. The e010f780 profile showed
  16 B per tag at EST:1783/1788, from the `Val` that was built at run time.
  78e19e23 should remove them, and plain Base elides the `Ref(Val)` on 1.11.
  Confirm this in the rerun, and on 1.10 in CI.
- **N7. Error message.** The refusal of more than one updraft
  (`tracer_config.jl:1269-1276`) gives only the sedimentation reason. The
  exchange's plume also assumes `ρa⁰ = ρ − ρaʲ`, which holds for one updraft
  only. The docstring at EST:1669-1670 relies on this check.
- **N8. Unused copies.** With `edmfx_sgs_mass_flux: false`, the copies are
  carried but never reach a tag. A warning would help.
- **N9. Style.**
  - Some docstring lines are far over the width: EST:67-69,
    `tracer_config.jl:1233`, `energy_source_checkpoint.jl:118-120`.
  - `UC` is not an explicit name. `UpdraftCopies` would be.
  - `ᶜlevel` (EST:1719) reads like a vertical level. `ᶜplume_input` would be
    clearer.
  - TEST:187-188 has an unclear phrase: "to rounding of its own size, which can
    pass the net flux's".
  - The docs sentence "…carries surface-flux energy: they take the
    environment's composition there" chains clauses with a colon, which the
    comment norm asks to avoid.
- **N10. Repair activity.** Under `edmfx_sgsflux_upwinding: none`, the
  default, the exchange's centred reconstruction is not monotone. E73 shows
  the repair moving six times more in the first 3 h. Any linear scheme keeps
  the sum at zero. So first-order upwinding for the exchange alone is an
  option, at some cost to how closely it matches the audit. This is a design
  choice for the owner, not a defect.

## Checked and found sound

- **Zero sum under every upwinding option.**
  - `ᶠinterp`, `ᶠupwind1` and `ᶠupwind3` are linear in `ᶜχ`, including their
    boundary rows (`abbreviations.jl:173-176, 227, 236-239`).
  - `ᶜadvdivᵥ` zeroes the boundary faces (`abbreviations.jl:106-109`).
  - van Leer maps to `first_order` (EST:1819-1820). The parent's other upwinding
    options are `none`, `first_order` and `third_order` (`default_config.yml:543`).
  - The partition's shares sum to 1 where the total is positive. The `min(…, 1)`
    cap never binds for a partition tag: with non-negative terms,
    `fl(a + b) ≥ a`, so `ε_i/total ≤ 1`.
  - `ᶜεʲ` is materialized, and `ᶜε̄` and `ᶜε⁰` are recomputed the same way for
    every tag. So the shares are identical across the tags' broadcasts. The
    exceptions are S1 and S6.
- **Signs and faces match the parent.** Each term is
  `−ᶜadvdivᵥ(ᶠinterp(ρᵏJ)/ᶠJ · recon(u³ᵏ − u³, value·aᵏ))`, as in
  `vertical_transport` (`implicit_tendency.jl:158-180`) and
  `edmfx_sgs_mass_flux_tendency!` (`edmfx_sgs_flux.jl:65-90`). The same
  `ᶜρ⁰`, `ᶜρa⁰` and `draft_area` are used (EST:1693-1703, 1741-1746). The
  exchange subtracts the divergence, and the parent adds `vtt = −div`, so the
  signs agree.
- **The content `Aᵏ` follows ClimaAtmos's conventions.**
  - `mse` is `TD.moist_static_energy`, which is `h + Φ`
    (`prognostic_variables.jl:279`). The parent's flux uses `mseᵏ + Kᵏ − h_tot`
    (`edmfx_sgs_flux.jl:68,82`), so `mseᵏ + Kᵏ = h_totᵏ`.
  - The subdomains share `ᶜp`, and `ρᵏ` is `TD.air_density(Tᵏ, p, qᵏ)`, as in
    the parent. So `e_totᵏ = mseᵏ + Kᵏ − p/ρᵏ` is right.
  - `c` is converted to FT at parsing (`tracer_config.jl:1135-1145`). `false`
    is a strong zero when there is no offset. So nothing is promoted in
    Float32.
  - Using `e_tot + c` rather than `h_tot + c` matches what a copy carries,
    since copies partition the specific energy. The pressure-work part stays in
    the donor share. The 0.7% agreement in E73 supports this.
- **The plume recursion.**
  - The updraft's specific-tracer equation is
    `∂χʲ/∂t += (ε + ε_turb)(χ⁰ − χʲ)` (`edmfx_entr_detr.jl:620-626`).
    Detrainment does not change a specific value.
  - With one updraft, `ρa⁰ = ρ − ρaʲ`, so `ε⁰ − εʲ = ρ/ρa⁰·(ε̄ − εʲ)`.
  - Taken implicitly in z, this gives EST:1840 with `a = λρ/ρa⁰`.
  - `Δz_k` matches the model's advective upwind form. `max(entr, 0)` is applied
    to the sum, as the model sums the same two rates.
  - Where the plume starts again (`ρaʲ ≤ ϵ`, `wʲ ≤ 0` or `ρa⁰ ≤ 0`), it takes
    the grid mean's values, so the updraft term there is zero.
- **The NaN sentinel.** `column_accumulate!` with `init` applies `f` at the
  first level and stores only what `f` returns (ClimaCore
  `Operators/integrals.jl:326-380`). So the `NaN` never reaches the output.
  `isnan` on a Dual reads the value. The accumulated type is `NTuple{N,FT}` on
  both branches.
- **Where a quantity is zero.**
  - Where `ρa⁰ ≤ 0`, `_environment_specific` returns `ε̄` and the plume starts
    again, so the exchange is zero.
  - Where `ρa⁰` is tiny, `ε⁰` suffers cancellation, but the shares are bounded
    and are multiplied by `a⁰ ≈ 0`.
- **AD and GPU mechanics.**
  - `ᶜe_src_plume` reaches `implicit_temporary_quantities` through
    `tagging_scratch`. `replace_parent_eltype` converts `NTuple` element types
    (`autodiff_utils.jl:48-58`).
  - The entrainment fields that the implicit precomputed set lacks come from
    `p.precomputed`, as in `edmfx_entr_detr_tendency!`.
  - `column_accumulate!` accepts an uninstantiated `Broadcasted{FieldStyle}`
    (ClimaCore `integrals.jl:83-88`). Radiation relies on the same
    (`radiation.jl:646-651`).
  - The closures capture only isbits values. The partition's `Val` becomes a
    `Ref` of a singleton. `ε[i]` with a run-time `i` is legal on a GPU.
  - GPU compile itself is unverified (S3).
- **Type stability after 78e19e23.** The flags come from the tags' types
  (EST:1809-1814, with `@inferred` in UNIT). `Val(length(model.tags))` folds to
  a constant. `UC` is a type parameter, so both `has_energy_source_updraft_copies`
  branches resolve at compile time.
- **No Jacobian block for the exchange.**
  - The model's own passive SGS tracers have no grid-mean `(ρχ, ρχ)` block for
    the mass flux. `sgs_massflux_jacobian_blocks` covers only
    `microphysics_tracer_names` (MSJ:395-420). So the exchange is as stiff as
    the model's own SGS tracer flux, which is `aʲ|Δw|/Δz`.
  - The grid-mean tags keep only their diagonal blocks, in both modes, so the
    split solver still takes them. `c.ρe_src_x` and
    `c.sgsʲs.:(1).e_src_x` do not overlap as name chains.
  - Model fields do not depend on the tags, so parity does not depend on this.
- **Nothing counts twice in the audit.**
  - `_sgs_mass_flux_of_energy_source_tags!` returns before both C1b and the
    exchange (EST:1544; the exchange is called at EST:1625).
  - The generic flux reaches `ρe_src_<name>` through `get_ρχ_name`
    (`variable_manipulations.jl:457-466`; `edmfx_sgs_flux.jl:134-171`).
  - Sedimentation recomputes its own share norm (`water_advection.jl:70`), so
    the early return skips nothing it needs.
- **The generic loops over `sgs_tracer_names` write only to the copies or to
  the grid-mean tags' SGS flux.** Checked:
  - advection (`advection.jl:137,373`);
  - entrainment (`edmfx_entr_detr.jl:622`);
  - sponge (`remaining_tendency.jl:151`);
  - filter (`mass_flux_closures.jl:303`);
  - hyperdiffusion: a new cache and DSS buffer, per tracer
    (`hyperdiffusion.jl:77,598`);
  - vertical and horizontal diffusion (`edmfx_sgs_flux.jl:385-395` and the
    horizontal counterpart);
  - the implicit advection, entrainment and diffusion blocks for passive SGS
    tracers (MSJ:1728, 1888, `update_sgs_entr_detr_jacobian!`).

  `limiters_func!` touches only the top-level `ρχ` (`limited_tendencies.jl:88`).
  Nothing in `src/diagnostics` iterates over the updraft's fields.
  `overwrite_from_file.jl:318` sets updraft fields by name only, as it already
  does for the grid-mean tags. Under 0M these loops now run for the first time,
  and they change the final contents of `p.scratch.ᶜtemp_scalar`. The same
  happens under 1M, where D4 is bit for bit. So no later code reads it before
  writing it.
- **Parity on a sphere and with other microphysics.** This holds by
  construction for both modes: every added path writes only tags or copies.
  No sphere run has checked it.
- **The copies' initial values.** Each copy starts at `ρe_src/ρ`
  (EST:74-86; `prognostic_variables.jl:28-41`), in state order, appended after
  the chemistry tracers.
- **The restart guard.** It compares the `e_src_*` names in `sgsʲs.:(1)` with
  the configured copies, both ways (`energy_source_checkpoint.jl:155-166,
  276-293`). By reading, it is correct. It is untested (S5).
- **With `enthalpy_increment`.** The exchange sums to zero over the partition,
  so the partition's increment, the correction and the ledger are unaffected.
  Under the audit, the correction takes the copies' mismatch. E73 finds the
  same column totals.
- **Config.** `true`, `false` and `~` parse. A quoted `"true"` is refused.
  Copies without tags, copies without `prognostic_edmfx`, and copies with
  `enthalpy` are refused (`tracer_config.jl:1221-1242, 1348-1362`;
  `types.jl:2583-2593`).
- **Docs.** Every `@ref` the diff adds resolves (`energy_source_tags.md:
  666, 696-699`). `checkdocs = :exports`.
- **Test tolerances.** The exchange's zero sum is checked at 1e-10 of the gross
  in Float64, which is safe. The copies' closure measured 119 J/m², about
  1e-6 relative, against a 1e-5 bound, which gives a 10× margin.
