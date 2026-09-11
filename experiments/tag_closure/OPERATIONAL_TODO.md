# Bringing the energy source tags and the process records to operation

The owner's goal, set on 2026-09-10, is to keep both families and make them
operational. This list names what is left. It merges four reviews made on
2026-09-11:

  - readiness;
  - form A (E36 to E38);
  - the leftover residuals (E39);
  - sub-grid transport, ice and the other microphysics schemes (E40, E41, and
    [SUBGRID_AND_MICROPHYSICS_DESIGN.md](SUBGRID_AND_MICROPHYSICS_DESIGN.md)).

On 2026-09-11 the owner decided that the GPU check comes last, once the physics
is robust and complete.

Nothing here is approved unless it says so. Model code, a default, a tolerance,
an energy reference and every run need the owner's approval before they are
written or submitted.

Priorities: **B** blocks operation, **S** should be fixed, **N** is nice to
have. Sizes: S is under a day, M one to three days, L several PRs or a
campaign.

## Where things stand

Done or built:

  - #65 and the offset (#68) are merged, with the loss-half integration test.
  - The implicit bracket and the repair are #69, which targets `main`. Its
    review found no blocker, and its five findings are fixed. Its help text is
    corrected (`0ae408d8`).
  - Sedimentation as transport is #70, a draft on `main`. It now refuses
    `prognostic_edmfx` with tags and has M2's label warnings (`4c274aed`).
  - The enthalpy audit is #72, a draft stacked on #70. It now carries the
    offset in its hyperdiffusion (C3) and states its timing correctly
    (`7a290c98`).
  - Measured: 0M on a column and on a sphere, and 1M on a warm column, a day
    each (E26 to E39, E43). 1M with ice on a cold column, for an hour (E42).

Not yet run: EDMF, ice beyond an hour, 2M and P3, Float32, a restart, anything
longer than a day, and the GPU. D1's twin without vertical diffusion ran
(E42b). The D4 EDMF pair timed out before it stepped.

## Decided on 2026-09-11

  - **Production** is a GPU sphere in Float32, with EDMF and 1M. So every item
    marked B blocks, and so do those marked "B if production uses EDMF". The
    GPU still comes last.
  - **EDMF:** refuse `prognostic_edmfx` with tags now (C1a), and build the
    sharing later (C1b): under both transports, in the implicit tendency, and
    with the guard of the shared loop (B4). These are the design's
    recommendations for its decisions 1 to 4.
  - **Approved to write:** C3 in #72, the help text in #69, R2's wording, and
    M2's label warnings, with C1a.
  - **Approved to run:** D1, the D4 pair, and R4's two scripts, on terrabyte.

## Decisions for the owner

 1. **The offset (U1).** Either require one, with an explicit `0` keeping
    today's behaviour, or keep `~` and have the warning print the smallest
    offset that makes the total positive.
 2. **The closure check (U2, R1).** On by default at a daily period, with a
    tolerance calibrated per transport, and one warning rather than one per
    check. Reported from a spin-up reference.
 3. **The per-process checks (A2, A3).** A check of labels at configuration,
    and form A as a global integral, instead of pointwise form A as a pass or
    fail test.
 4. **Model code that still needs approval:** A4, signed overlay shares under
    the audit.
 5. **The design's open decisions**, 5 and 6 in section 2.
 6. **Runs, each on its own:** V1 to V3, V5 and V6.

## 1. Merge the stack

  - **B, #69.** ~~Fix the stale help text at `default_config.yml:478`~~, done
    in `0ae408d8`. Then merge.
  - **B, #70.** ~~Refuse or document the EDMF sedimentation gap (C1a)~~, done
    in `4c274aed`. ~~Run D1~~, done (E42). Nothing else in this list holds it
    in draft.
  - **B, #72.** ~~C3 and its test, and the timing wording (R2)~~, done in
    `7a290c98`. Still before it leaves draft: E35 to E43 and the audit's scope
    in the docs. Then retarget it to `main` after #70.

## 2. Code and correctness

### Sub-grid transport and the other microphysics schemes

From E40, E41 and the design.

  - **C1a, B. Refuse `prognostic_edmfx` with energy source tags now.** Done in
    #70, `4c274aed`. This is the design's option A, with M1. It allows
    `edonly_edmfx`, with a warning that its eddy diffusion moves the tags as
    tracers. It does not refuse 2MP3, which the model's own gate refuses
    already; that waits for the gate to lift (M5). Before it:
      - nothing refused `prognostic_edmfx`;
      - with the shipped settings the run failed, with
        `type NamedTuple has no field e_src_<name>`;
      - with `edmfx_vertical_diffusion: false`, the whole sub-grid energy flux
        landed in `e_src_res` (E40).
  - **C1b, B if production uses EDMF. Share the parent's sub-grid fluxes of
    `E` by the losing cell's shares.** This is option B, one PR, about 220
    lines and 200 of tests.
      - B1: the sub-grid mass flux. The donor follows the sign of the flux of
        `E`, not the updraft's direction.
      - B2: each species' whole sedimentation face flux, the corrections
        included, shared once by its sign.
      - B4: a guard in the shared tracer loop, `edmfx_sgs_flux.jl:403-409`.
        The guard also lets the water tags and the passive tracers run there.
        The alternative is to refuse `edmfx_vertical_diffusion: true` with
        tags.
      - Validation: the D4 pair and D5.
  - **C1c, N. B3, the sub-grid diffusive flux under `enthalpy`.** It extends
    the audit beyond the scope decided on 2026-09-11. Wait for the D4 pair.
  - **C1d, N. Option C, per-updraft tag shares.** About three times B. Only if
    a question needs provenance mixed by convection.
  - **M2, S. Label warnings that see the microphysics model.** Done in #70,
    `4c274aed`. A tag or a record that lists `microphysics` warns under every
    scheme but 0M, where it stays zero; C8's record is exactly zero for a day.
    A record that lists `precipitation` warns only where nothing sediments.
    This covers the first half of R3.
  - **M3, S. A test that the two lists of sedimenting species agree:**
    `water_advection.jl:51-56` and `gs_sedimenting_mass_candidates`.
  - **M4, when 2M returns.** No tag code. D2 and one integration item.
  - **M5, when the parent's P3 is fixed.** The parent's gaps are:
      - the velocity names at `microphysics_cache.jl:608`;
      - `ᶜwₛ`, which is never set;
      - rain and the numbers, which do not sediment in their own equations.

The design's decisions. On 2026-09-11 the owner took 1 to 4 and 7 as
recommended: refuse now; then B under both transports, in the implicit
tendency, with B4; and M2. Still open:

 5. B3 now, or keep the sub-grid closures in tracer form?
 6. Who lifts the 2M gate and fixes the parent's P3? Do the tags refuse P3
    until then?

### The rest

  - **C2, B. A restart guard.** Write the offset, the tag set, the transport
    and the repair setting into the checkpoint. Fail with a named key on a
    mismatch (`restart.jl:34-39`). S to M.
  - **C3, S, in #72. The audit's hyperdiffusion.** Done in `7a290c98`. The
    integration test's sphere item now checks the whole change in `E`.
      - `hyperdiffusion.jl:495-497` takes the water hyperdiffusion flux out of
        `ρ` too. So `c·Δρ` from hyperdiffusion reaches `e_src_res`.
      - Add `c` to the water part of the shared flux.
      - Fix the three texts that say `ρ` is not hyperdiffused.
      - Have the sphere test compare against the whole change in `E`.
  - **C4, S. `c·Δρ` from processes the tags do not bracket.** Vertical
    diffusion, the sponges, hyperdiffusion, EDMF and LES change `ρ`
    (`energy_source_tags.jl:102-111`). Measure it first, with the ledger, on a
    run that has them (V2). Then either share them as transport or document
    the size. Measuring is S. The fix is M.
  - **C5, S. Where the repair's large trades sit.** Up to ±30,920 J/kg under
    tracer transport and ±16,294 under the audit (E27, E35). Take it from C6's
    and C10's output.
  - **C6, N. Review leftovers:**
      - `isfinite` before the conversion to `FT` (`tracer_config.jl:784-788`);
      - `nothing` inside a broadcast at init;
      - `parent` shadowed in the tests;
      - the Float32 rounding floor.
  - **C7, N. Jacobian blocks** for the tags' sedimentation and for the
    implicit bracket. M.
  - **A2, B for the operational checks. A check of labels.** At configuration,
    warn on any active label that no process tag lists. At runtime, report
    ∫Δ⁺ per label. Accept it when it flags subsidence on C5's column and
    microphysics on C6's sphere, and nothing on C7. S to M.
  - **A3, S. Form A as a global integral, online.** On the native grid, with
    ∫Δfix subtracted. Accept it when a C6-type run gives about 1.2e-3, and C7,
    C9 and C10 give at most 1e-4 at 24 h. Set the threshold from a five-day
    pair. S to M.
  - **A4, S. Signed overlay shares under the audit.** Accept it when a C9 twin
    gives form A of at most 5 J/kg, or at most 1e-6 with the loss signed too,
    and `sfc` no longer freezes at a node. `ta` and the partition residual must
    not change. S, plus one run.
  - **A5, S. An overlay bound diagnostic.** Report the mass fraction where an
    overlay is negative, and where a member exceeds its group's sum.
  - **A6, N. A tag-only vertical upwinding key.** Under tracer transport it
    takes form A to the loss clamp's floor (E37). S.
  - **A7, S. `c5_process_closure.jl`.** It already calls the ledger line an
    indicator only. Still to add: a diagnostic of how the gap cancels over
    columns and over levels.
  - **R3, S. A warning on `constrain_qtot`.** It writes `ρ` and `ρe_tot`
    outside the brackets (`utilities.jl:34`).

## 3. Validation runs (each needs the owner's approval)

  - **V1, B.** At least 10 days on the sphere, with the offset and the repair,
    tracer transport, a daily closure check with the audit, and `e_src_fix`.
    About an hour of solve.
  - **V2, B.** The production physics on a sphere: EDMF, vertical diffusion,
    sponges, topography and 1M, with `transport_ledger.jl`. It sizes C1 and
    C4. It needs C1a or C1b first, since EDMF with tags fails today.
  - **V3, S.** Float32 on a CPU sphere. The GPU half is in section 8.
  - **V4, S. D1.** Ice through sedimentation's upward branch, for an hour.
    Ran (E42). Its twin without vertical diffusion, approved and submitted on
    2026-09-11, separates the branch from diffusion.
  - **V5, S.** Restart equivalence: two segments against one run, with the
    offset and the repair.
  - **V6.** Topography (S). D2 and D3, when the model runs 2M and P3 (N unless
    production uses them).
  - **The D4 pair, S.** EDMF on the DYCOMS column, `tracer` and `enthalpy`,
    with `edmfx_vertical_diffusion: false`. Today it measures the gap that B
    must close. After B it validates B. D5 is meant for after B. Submitted on
    2026-09-11 on code without C1a, and stopped at `hpda2_test`'s two-hour
    limit before it stepped: the EDMF build with tags takes longer than that on
    two cores. With C1a merged, D4 runs only on code from before C1a, or after
    B.
  - **R4, S.** Ran (E39b, E43).
      - `c8_variants.jl`: a day of C8 under the audit, a converged Newton
        solve, and an hour under tracer transport. About 30 minutes.
      - `first_hour_sphere.jl`: two hours, one Newton iteration against a
        converged solve.

## 4. Tests and CI

  - **T1, S.** Add a restart with an offset, and the changed-offset error, to
    integration item 7, which reuses its compile. Add the C3 check.
  - **T2, S.** A second test group for the new configurations: Float32, EDMF,
    and 1M with ice. The current group compiles five times.
  - **T3, S.** An inference and allocation test of a tendency with tags,
    modelled on `test/parameterized_tendencies/microphysics/allocations.jl`.
  - **T4, S.** An example config under `config/model_configs/`. No shipped
    config turns the tags on.
  - **T5, S.** The cold column as an integration item, from
    `analysis/subgrid_check_cold.jl`. It could replace the warm state of
    item 8 and cover both of sedimentation's branches in one compile.
  - **T6, with C1b.** An EDMF integration item: the partition's tendencies from
    the sub-grid mass flux and from sedimentation match the parent's to
    100 eps. One EDMF compile.

## 5. Performance

  - **P1, S.** The cost on a sphere against an untagged control. So far it is
    known on one column only: 1.32× (T4).
  - **P2, N.** Compute `energy_source_share_norm!` once per evaluation, and
    skip it when nothing sediments.
  - **P3, N.** A string allocation per tracer per evaluation when the audit is
    on (`energy_source_tags.jl:148`).

## 6. Defaults and UX

  - **U1, B.** The offset. See decision 2.
  - **U2, S.** The closure check. See decision 3.
  - **R1, S. Closure reporting after spin-up.** The first hour's residual is an
    artefact of the one Newton iteration during the initial adjustment (E39).
    Report the closure from a spin-up reference, or re-seed the tags after N
    steps. Accept it when no hourly tolerance warning fires in the audit runs.
  - **U3, S.** Output `e_src_fix_<name>` by default
    (`default_diagnostics.jl:697-709`).
  - **U4, S.** The most negative source tag, and the energy the repair moved,
    in the audit table.
  - **U5, N.** A clear error when the tag list changes across a restart.
  - **U6, N.** Records kept in Float64, or reset at each output, for long
    Float32 runs.
  - **R5, N.** A converged Newton solve for closure studies. On the column it
    removes 99% of the first hour's residual (E39). Its cost is not measured.

## 7. Docs

  - **D1, B for users other than the author. A guide on how to read the
    output.** [USER_GUIDE_DRAFT.md](USER_GUIDE_DRAFT.md) is the draft. It is
    meant for `docs/src/`, and moving it there is the owner's call. It covers:
      - tags against records;
      - that a source tag cannot show a sink;
      - `e_src_res`;
      - form A as an integral, and form B;
      - which check to trust where;
      - E35 to E41.
  - **D2, S. Stale text.** The guide lists ten fixes, each checked against the
    code. Four are done: the repair texts in #69, and the EDMF caveat and the
    `microphysics` record in #70. The clearest of the rest:
      - `tracer_configuration.md:410-414` and `tracer_config.jl:564-569`
        misstate how the tags move;
      - `energy_source_tags.md:90-96` is wrong under EDMF;
      - no page defines form A and form B.
  - **R2, S. Three statements to correct.** Done: the timing in #72
    (`7a290c98`) and in `ENTHALPY_AUDIT_DESIGN.md`, the "exact" comment in #69
    (`0ae408d8`), and "ρ is not hyperdiffused" with C3.
      - The audit's timing. The tags take the solved stage state, and the
        parent's side is the one-iteration increment. Fix it in
        `docs/src/energy_source_tags.md`, the kernel's docstring and
        `ENTHALPY_AUDIT_DESIGN.md`.
      - The "exact" identity-block comment at `process_record.jl:35-38`, which
        is not exact under 1M and 2M.
      - "ρ is not hyperdiffused", with C3.
  - **D3, S. Caveats:**
      - C1 and C4;
      - what is untested;
      - stitching `e_src_fix` across restarts;
      - how to choose `c`;
      - that falling ice passes provenance upward, as accounting (E41).

## 8. Last, by the owner's decision: the GPU

  - **B, last.** Once the physics is robust and complete, run the diagnostic on
    a GPU, on Levante, together with T3 and Float32. Fix whatever that forces.
    From the code, every branch on tags is resolved on the host, and the
    kernels use isbits scalars only. Nothing has shown it.

## Open science, not blocking

  - ~~C8's form A over a day.~~ The per-tag transport (E43).
  - What the sphere's converged 17% of the first-hour residual is (E39b).
  - E16's remainder, E24 and E14.
