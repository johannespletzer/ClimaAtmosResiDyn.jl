# Bringing the energy source tags and the process records to operation

The owner's goal, set on 2026-09-10, is to keep both families and make them
operational. This list names what is left. It merges four reviews made on
2026-09-11 (readiness, form A, the leftover residuals, and sub-grid transport
with ice and the other microphysics schemes). On 2026-09-14 it was rebuilt as a
list of what remains, and an Opus agent reviewed it against the repository.
Its findings are folded in; its report is
[TODO_REVIEW_2026-09-14.md](TODO_REVIEW_2026-09-14.md).

Production, as the owner decided on 2026-09-11, is a GPU sphere in Float32,
with EDMF and 1M. The GPU check comes last, once the physics is robust and
complete.

Nothing here is approved unless it says so. Model code, a default, a tolerance,
an energy reference and every run need the owner's approval before they are
written or submitted.

Priorities: **B** blocks operation, **S** should be fixed, **N** is nice to
have. Sizes: S is under a day, M one to three days, L several PRs or a
campaign.

## Where things stand (2026-09-14)

  - #65 and the offset (#68) are merged, with the loss-half integration test.
  - #69, the implicit bracket and the repair, is merged into `main`
    (`08682fd8`, 2026-09-14).
  - #70, sedimentation as transport, the EDMF refusal and M2's label warnings,
    targets `main` and is out of draft. Its `docbuild` hit the 30-minute limit,
    so `docs-required` failed (run 34593320376). The owner re-ran it on
    2026-09-14.
  - #73 fixes the docs workflow: `main`'s deploy to `gh-pages` failed with 403
    on every push, because the job token was read-only. It grants
    `contents: write` and raises the timeout to 60 minutes. After it merges,
    `main` is merged into #70 and pushed, as the owner approved.
  - #72, the enthalpy audit, is a draft on #70's branch, with all checks
    passing. It carries C3 and the corrected timing wording, and has #70 merged
    in (`530a3658`). `energy_source_tag_transport` exists only there.
  - This branch merged #72's head in `57ed9c1f`.
  - Measured: 0M on a column and a sphere, and 1M on a warm column, a day each
    (E26 to E39, E43); 1M with ice on a cold column for an hour, with a twin
    without vertical diffusion (E42, E42b); the EDMF build time with and without
    tags (E44, E44b); C7's sphere in Float32 for a day, which closes as Float64
    does, to rounding (E45).
  - Not yet run: EDMF with tags past its build, more than one process (MP1
    failed to start), a restart, anything longer than a day, 2M and P3, and the
    GPU.

## Decided

On 2026-09-11:

  - **Production** is a GPU sphere in Float32, with EDMF and 1M.
  - **EDMF:** refuse `prognostic_edmfx` with tags now (C1a, done), and build the
    sharing later (C1b): under both transports, in the implicit tendency, with
    the guard of the shared loop (B4). These are the design's decisions 1 to 4.
    M2 (decision 7) is done too.
  - **Approved and done:** C3, the #69 help text, R2's wording, M2 with C1a; the
    runs D1, its twin, the D4 pair, R4, the D4 build control and P4's split
    test.

On 2026-09-14:

  - **P4's stage timing** is approved for the 8-tag EDMF build (job `13440637`)
    and for its two baselines, `d4_column_edmf_notags` and `p4_edmf_two_tags`
    (jobs `13440706` and `13440707`).
  - **The offset (U1):** require `energy_source_tag_offset` whenever energy
    source tags are set. An explicit `0` keeps today's behaviour. The refusal
    quotes the tested values: 110,495 J/kg as used in the series, and the
    smallest offsets that made the total positive, 45.4 kJ/kg on the DYCOMS
    column and 100.4 kJ/kg on the moist sphere (E6).
  - **The closure check (U2, R1):** on by default whenever the tags are set, at
    a daily period, reported from a spin-up reference. It only reports until V2
    and V3 calibrate a tolerance per transport.
  - **The per-process checks (A2, A3):** the label check at configuration now,
    warning on a process that runs with no tag that lists it. A2's runtime part
    and A3, form A online, come later as optional validation features; the
    offline script covers validation runs until then.
  - The code for these defaults and checks is written at step 9 of the order
    below.
  - **Merges:** the owner merged #69. #73 fixes the docs deploy; the owner
    merges it, and then `main` goes into #70.
  - **V3 and MP1** were approved and submitted: jobs `13440822` (V3, C7's sphere
    in Float32) and `13440823` (MP1, C7's sphere on 4 ranks). V3 ran its day
    and is handed back (E45). MP1 died in `MPI_Init` after 91 s. The runscript
    called `srun` without `--mpi=pmix`, and Slurm's default here, `pmi2`, does
    not work with this Open MPI. The runscript now passes the plugin from
    `runscripts/terrabyte_stacks.env`. Submitting MP1 again needs a new
    approval.
  - **The S items**, as proposed and accepted by the owner:
      - now: C5; P1, whose run needs its own approval; D2, once #70 merges;
      - with the defaults and checks (B9): U3, U4, R3, T4;
      - with C1b (B4): M3, T5;
      - before the GPU (B13): T3;
      - with V2 (B10): C4, V6;
      - with D1 (B12): D3;
      - A4, A5 and A7 move to N.

## 0. In flight

  - **P4-stages.** `analysis/p4_build_stages.jl` times each build stage and the
    first steps, with each compile inside its timer. It runs from the worktree
    `../ClimaAtmosResiDyn-p4` at `edd44e1d` on three configs: `p4_edmf_tags`
    (job `13440637`), `d4_column_edmf_notags` (job `13440706`) and
    `p4_edmf_two_tags` (job `13440707`). With 0, 2 and 8 tag fields, each stage's
    growth can be named. Hand back as E44c.

## 1. Decisions for the owner

 1. **A4.** Signed overlay shares under the audit: model code and a C9 twin.
 2. **V1's scope.** A 0M 10-day sphere is not production physics. Either fold
    it into a 10-day Float32 run with V2's and V3's physics, or make it S.
 3. **The design's open decisions:** 5, whether to share the SGS diffusive
    flux under `enthalpy` (C1c); 6, who lifts the 2M gate and fixes the parent's
    P3, and whether the tags refuse P3 until then.
 4. **Phase B.** FINDINGS §8 item 4 still lists it as the owner's call. Drop it
    or keep it.
 5. **Runs**, each on its own: V2, V5, V6, MP1 again with the fixed launch, P1,
    the D4 variant with `edmfx_vertical_diffusion: true`, and D5.
 6. **Docs:** whether to move `USER_GUIDE_DRAFT.md` into `docs/src/` (D1).
 7. **Merges:** #73, then #70 once its docs pass, then #72.

## 2. Blocking operation (B), in dependency order

 1. **Merge #70.** #69 is merged. Merge #73, the docs-workflow fix, then
    merge `main` into #70 and push, and merge #70 once its checks pass. Size S.
 2. **Finish and merge #72.** Add E35 to E43 and the audit's scope to its docs,
    take it out of draft, retarget it to `main` after #70, merge. This comes
    before C1b and C2, because both use `energy_source_tag_transport`, which
    exists only in #72. Size S.
 3. **P4, the EDMF build time with tags.** With 8 tags, 5 records, the audited
    check and 24 diagnostics, the D4 column did not build in two hours on two
    cores; without them it builds in 410 s (E44). The job takes 27 minutes with
    2 tags, 60 with 8, and more than 120 with 8 tags and 5 records, against 18.5
    without, and most of the growth lies outside the stages the driver logs
    (E44b). Steps: the three staged runs (in flight), then find the compile step
    that grows, then fix it. Within `hpda2_test`'s two-hour cap it blocks every
    EDMF run with tags. Size M to L; not known until E44c.
 4. **C1b, share EDMF's sub-grid fluxes among the tags** (design option B).
      - B1, the SGS mass flux, with the donor from the sign of the flux of `E`;
        B2, each species' whole sedimentation face flux, the corrections
        included; B4, a guard in the shared tracer loop,
        `edmfx_sgs_flux.jl:403-409`.
      - Both transports, in the implicit tendency. About 220 lines and 200 of
        tests. Its code can be written alongside P4's fix; its validation waits
        for P4.
      - T6, an EDMF integration item: the partition's tendencies from the SGS
        mass flux and sedimentation match the parent's to 100 eps. It adds an
        EDMF compile to CI, where `tagging_energy` already takes up to 56
        minutes, so it depends on P4's fix.
      - Validation: the D4 pair and D5, and a D4 variant with
        `edmfx_vertical_diffusion: true`, the shipped setting, which B4 makes
        possible. Before B the D4 pair measures the gap; after B its residual
        should fall back towards C8's and C9's kind of residual, less what B3
        would take.
      - Then narrow C1a's refusal to `updraft_number > 1`.
      - Size M.
 5. **C2, a restart guard.** Write the offset, the tag set, the transport and
    the repair setting into the checkpoint, and fail with a named key on a
    mismatch (`restart.jl:34-39`). With T1 and V5. (Not the experiment C2 of
    FINDINGS §8, the implicit brackets, which #69 built.) Size S to M.
 6. **V5, restart equivalence.** Two segments against one run, with the offset
    and the repair. Production runs restart. S.
 7. **Float32: ~~V3~~ and T2's Float32 part.** ~~No Float32 run with tags
    exists.~~ V3 is done (E45): C7's sphere in Float32 closes as in Float64
    over a day, to rounding, with a floor near 1e-7. What remains is T2, a
    Float32 test group. The records are `FT` fields that accumulate from the
    start and are never reset (`process_record.jl:22-25`), so runs longer than
    a day are still untested; that is U6. Size S.
 8. **MP1, more than one process.** Every run so far was single-process, and
    the closure check reduces with global sums (`tagged_tracers.jl:450-484`). A
    2 to 4 rank CPU sphere with tags, records and the check, before the GPU.
    Size S, plus a run. The first try, job `13440823`, died in `MPI_Init`
    because `srun` lacked `--mpi=pmix`. The runscript is fixed; the run needs
    the owner's approval to go again. `configs/mp1_sphere_4ranks.yml`, on 4
    ranks.
 9. **The decided defaults and checks.** U1, require the offset with tags; U2
    and R1, the closure check on by default, daily, from a spin-up reference,
    report-only; A2's label check at configuration (accept when it flags
    subsidence on C5's column and microphysics on C6's sphere, and nothing on
    C7). Size S to M each.
10. **V2, the production physics on a sphere:** EDMF with
    `edmfx_vertical_diffusion: true`, vertical diffusion, sponges, topography
    and 1M, with `analysis/transport_ledger.jl`. It sizes C4. It needs C1b and
    P4. V1 as decided.
11. **Calibrate** U2's tolerance per transport from V2 and V3, and add the
    warning.
12. **D1, the user guide into the docs,** with D2 and D3. #63 has merged, so the
    memo and the plan already sit in `docs/src/`.
13. **The GPU, last.** Run the diagnostic on a GPU on Levante, with Float32 and
    T3, and fix what that forces. From the code, every branch on tags is
    resolved on the host, and the kernels use isbits scalars only; nothing has
    shown it.

## 3. Should fix (S)

Grouped as the owner accepted on 2026-09-14.

Now:

  - **C5.** Where the repair's large trades sit: up to ±30,920 J/kg under tracer
    transport and ±16,294 under the audit (E27, E35), from C6's and C10's
    output.
  - **P1.** The tag cost on a sphere against an untagged control; known on one
    column only, 1.32× (T4). Its run needs the owner's approval.
  - **D2, stale docs,** once #70 merges. The guide's fixes 3, 4, 5, 7, 9 and 10
    (`USER_GUIDE_DRAFT.md`, "Proposed fixes"): `tracer_configuration.md:410-414`
    and the docstring at `tracer_config.jl:605` on how the tags move;
    `energy_source_tags.md:90-96` under EDMF; the audit section on the EDMF mass
    flux; the tested boundary in `energy_source_tags.md`; the records' column
    closure in `process_record.md`; and no page defining form A and form B.

With the defaults and checks (B9):

  - **U3.** Output `e_src_fix_<name>` by default (`default_diagnostics.jl:697-709`).
  - **U4.** The most negative source tag, and the energy the repair moved, in
    the audit table.
  - **R3.** A warning on `constrain_qtot`, which writes `ρ` and `ρe_tot` outside
    the brackets (`utilities.jl:34`).
  - **T4.** An example config under `config/model_configs/`; no shipped config
    turns the tags on. It sets the offset, as U1 will require.

With C1b (B4):

  - **M3.** A test that `water_advection.jl:51-56` and
    `gs_sedimenting_mass_candidates` list the same species.
  - **T5.** The cold column as an integration item, from
    `analysis/subgrid_check_cold.jl`, covering both sedimentation branches.

Before the GPU (B13):

  - **T3.** An inference and allocation test of a tendency with tags, modelled
    on `test/parameterized_tendencies/microphysics/allocations.jl`.

With V2 (B10):

  - **C4.** `c·Δρ` from processes the tags do not bracket: vertical diffusion,
    sponges, hyperdiffusion, EDMF, LES (`energy_source_tags.jl:102-111`).
    Measure on V2, then share them as transport or document the size.
  - **V6.** Topography. D2 and D3 when the model runs 2M and P3 (N unless
    production uses them).

With D1 (B12):

  - **D3, caveats:** C1 and C4, what is untested, stitching `e_src_fix` across
    restarts, choosing `c`, and ice passing provenance upward (E41).

## 4. Nice to have (N)

  - **A4.** Signed overlay shares (decision 1), moved from S on 2026-09-14.
    Accept when a C9 twin gives form A of at most 5 J/kg, or at most 1e-6 with
    the loss signed too, and `sfc` no longer freezes at a node, with `ta` and
    the partition residual unchanged.
  - **A5.** An overlay-bound diagnostic: the mass fraction where an overlay is
    negative, and where a member exceeds its group's sum. Moved from S.
  - **A7.** In `c5_process_closure.jl`, how the gap cancels over columns and
    levels. Moved from S.
  - **A2's runtime part and A3,** as optional validation features (decided
    2026-09-14): ∫Δ⁺ per label at runtime, and form A as a global integral
    online, on the native grid with ∫Δfix subtracted. Accept A3 at about 1.2e-3
    on a C6-type run and at most 1e-4 on C7, C9 and C10 at 24 h.
  - **C1c.** B3, the SGS diffusive flux under `enthalpy` (decision 3).
  - **C1d.** Option C, per-updraft tag shares; about three times B.
  - **C6.** Review leftovers: `isfinite` before the conversion to `FT`
    (`tracer_config.jl:784-788`), `nothing` inside a broadcast at init, `parent`
    shadowed in tests, the Float32 rounding floor (stays N: 7.5e-8 of the
    total at t = 0 on V3's sphere, against a residual of 5.9e-5 after a day,
    E45).
  - **C7.** Jacobian blocks for the tags' sedimentation and the implicit
    bracket.
  - **A6.** A tag-only vertical upwinding key (E37).
  - **P2.** Compute `energy_source_share_norm!` once per evaluation, and skip it
    when nothing sediments. **P3.** A string allocation per tracer per
    evaluation under the audit (`energy_source_tags.jl:148`).
  - **U5.** A clear error when the tag list changes across a restart.
    **U6.** Records in Float64, or reset at each output, for long Float32 runs.
    Stays N: over V3's day the records' extrema match Float64's to 1.2e-2 at
    worst, at the rain-out's onset, and to 4e-4 at 24 h (E45). Runs longer
    than a day are untested.
  - **R5.** A converged Newton solve for closure studies; its cost is not
    measured.
  - **M4,** when 2M returns: D2 and one integration item. **M5,** when the
    parent's P3 is fixed: D3.

## 5. Housekeeping

  - ~~**The runscript.** Read a worktree's `.git` file, so provenance records
    the commit; and flush the log, so a killed job keeps it.~~ Done in
    `297eda4c`, with MPI ranks through `srun`. On 2026-09-14 `srun` got
    `--mpi=pmix` on terrabyte, after MP1 died without it. The tcsh runscripts
    are not changed.
  - ~~**`analysis/validate_d_configs.jl`** failed the control.~~ Done on
    2026-09-14: it checks controls as controls, and expects the C1a refusal
    for the EDMF runs with tags (D4, its audit twin, D5). All eight D configs
    pass.
  - ~~**Run `analysis/phase_c.jl`**~~, done on 2026-09-14: `summary_c.csv` and
    the plots now include C5 to C10. It reads only runs named `c*`, so the D,
    P4, V3 and MP1 runs are not in it; FINDINGS reports them.
  - **The known defects** in `LEVANTE_TASKS.md`: ~~the committed `.out` files~~
    (fixed on 2026-09-14: each is trimmed into its directory's `run.log` and no
    longer committed); the validator's `implicit_diffusion` rule is stricter
    than the model for ISDAC; `output/c0_sphere_deep/` has no provenance, so
    every phase C pass warns.
  - **Remove the worktrees** `../ClimaAtmosResiDyn-repair`, `-audit` and `-p4`
    once the stack is merged and P4 is done.

## 6. Open questions, not blocking

  - What makes D1's zero-sum gross residual (E42, E42b). Candidate: pressure
    work in grid-mean vertical advection under tracer transport. An audit twin
    of D1 would test it.
  - What the sphere's remaining 17% of the audit's first-hour residual is
    (E39b).
  - How much provenance the upward branch moves where ice persists (D5, after
    C1b).
  - E14, E16's remainder and E24.

## Suggested order

 1. P4's three staged runs (in flight).
 2. The owner's remaining decisions.
 3. Merge #73; merge `main` into #70; merge #70. (#69 is merged.)
 4. #72's docs; out of draft; retarget; merge.
 5. P4's fix, with C1b's code alongside.
 6. C1b's validation (the D4 pair, the D4 variant with vertical diffusion on,
    D5) and T6.
 7. C2 with T1 and V5.
 8. T2's Float32 part (V3 is done); MP1 again.
 9. The decided defaults and checks: U1, U2 with R1, A2's label check.
10. V2 with C4; V1 as decided.
11. Calibrate U2's tolerance.
12. The docs: D1 to D3.
13. The remaining S and N items.
14. The GPU, last.

## Done, for reference

  - C1a and M2 in #70 (`4c274aed`); C3 and R2's timing in #72 (`7a290c98`); the
    #69 help text and the records comment (`0ae408d8`); R2's audit design text
    on this branch.
  - The guide's fixes 1, 2, 6 and 8, in #69 and #70.
  - Runs: D1 and its twin (E42, E42b); R4 (E39b, E43); the D4 pair, timed out
    (E40, E44); the D4 build control (E44); P4's split test (E44b).
  - #72 merged into this branch (`57ed9c1f`).
