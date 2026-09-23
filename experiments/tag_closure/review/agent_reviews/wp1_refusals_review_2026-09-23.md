# Review of WP1's first commit: water tag refusals and reserved names

- Commit: `2337832d` on `claude/water-tags-edmf`, worktree
  `../ClimaAtmosResiDyn-wedmf`, against `origin/main` `0b2b1032` (its parent).
- Plan: `G3_PLAN.md` section 4.8, `G3_TODO.md` WP1.
- Reviewer: clima-reviewer agent, 2026-09-23.
- Nothing on the branch was edited. No job was submitted.

## Verdict

**No blocking findings.** The commit only changes configuration time, so
parity holds. The two refusals are the right ones for the closures the model
accepts, and each test fails when its refusal is removed.

Two findings should be fixed before the draft PR:

- S1: the prescribed-flow warning misses the shipped kinematic driver.
- S2: the user-facing EDMF rationale says the tags' sedimentation makes the
  partition drift. The code says it does not.

The rest are wording and test tightening.

## What was checked, and how

- I read the diff, `check_water_tracers_transport_supported` and its call
  site, `tracer_tag_tuple`, the diagnostics registration of both families,
  and each transport path the refusal and the docs name.
- I reran `test/config/tracer_config.jl` with the scratch test env and depot
  given in the brief. All 16 testsets passed with 0 failures. The summaries
  add up to **220** passes, not 243. The new testset has 14. Log:
  `$SCRATCH/claude_work/wp1_review_testrun.log`.
- I wrote a mutation and probe script,
  `$SCRATCH/claude_work/wp1_review_mutations.jl`, with its log
  `wp1_review_mutations.log`. It redefines the check and
  `water_tracer_tuple` inside `ClimaAtmos` with `@eval`, then reruns a
  verbatim copy of the new testset. It also probes cases the tests do not
  cover.
- I ran the pinned JuliaFormatter (`.dev/format`, offline) on copies of the
  two changed `.jl` files and the two changed `.md` files. It changed
  nothing.
- I grepped `config/`, `test/`, `docs/` and `.buildkite/` on the branch, and
  `experiments/` on the record branch, for `water_tracers` combined with a
  refused option, and for tag names with a reserved prefix.

### Mutation results

| Mutant                                                      | New testset |
| :---------------------------------------------------------- | :---------- |
| baseline                                                    | passes      |
| EDMF refusal removed                                        | fails       |
| AMD refusal removed                                         | fails       |
| prescribed-flow warning removed                             | fails       |
| `edonly_edmfx` refused as well (over-refusal)               | fails       |
| no reserved prefixes                                        | fails       |
| `stag_` dropped from the prefixes                           | fails       |
| `fix` without underscore, which also refuses `fixed`, `fixture` | **passes** (see M1) |

### Probes

| Probe                                                                                      | Result                                                     |
| :----------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| A. `initial_condition: ShipwayHill2012`, 1M, `water_tracers`, no `prescribed_flow` key      | `prescribed_flow` parses as `nothing`; **no warning** (S1)  |
| B. `amd_les: "true"` as a string                                                            | coerced to `Bool` `true`; refused                           |
| C. `energy_source_tags` named `fix_a` or `inc_left`; `energy_tracers` named `fix_a`         | all accepted (E1)                                          |
| D. `prescribed_flow: Nonsense`                                                              | warns about a flow the model never builds (M4)             |
| E. `prognostic_edmfx` with `edmfx_sgs_mass_flux: false`                                     | refused (M6)                                               |

## Blocking

None.

## Should fix

### S1. The prescribed-flow warning misses the setup route, which is how the shipped case runs

- **Where:** `src/config/tracer_config.jl:1402`, and its call at `:1443-1447`,
  which passes `get(config.parsed_args, "prescribed_flow", nothing)`.
- **Evidence:** the model takes its prescribed flow from the setup first
  (`src/config/type_getters.jl:53-57`). `ShipwayHill2012` supplies one
  through `prescribed_flow_model` (`src/setups/ShipwayHill2012.jl:60-61`).
  The only shipped prescribed-flow config,
  `config/model_configs/kinematic_driver.yml`, sets
  `initial_condition: ShipwayHill2012` and no `prescribed_flow` key. Probe A
  builds that combination with `water_tracers`: the key is `nothing` and no
  warning is logged.
- **Failure scenario:** a user adds `water_tracers` to `kinematic_driver.yml`.
  The flow's surface moisture flux enters `ρq_tot` untagged
  (`advection.jl:264-267`), and the user gets no warning. The docs say they
  would get one (`docs/src/tagged_water.md:289-291` and `:319-320`, NEWS).
  The test passes only because it sets the key without the setup.
- **Fix:** warn from the built model rather than from the key. Put a small
  helper in `get_atmos`, next to `warn_untagged_energy_source_processes(atmos)`
  (`type_getters.jl:86`), for example
  `warn_water_tags_under_prescribed_flow(atmos)`. It warns when
  `!isnothing(atmos.prescribed_flow) && !isnothing(atmos.water_tagging_model)`.
  Keep the refusals in `check_water_tracers_transport_supported`, since
  `turbconv` and `amd_les` come only from the keys
  (`model_getters.jl:922-937`, `:1202-1203`). Unit-test the helper on both
  routes: the key alone, and `initial_condition: ShipwayHill2012` alone. This
  also fixes M4.

### S2. The EDMF rationale says the tags' sedimentation breaks the partition. It does not.

- **Where:**
  - the docstring at `src/config/tracer_config.jl:1367-1369`;
  - the error message at `:1388-1392`;
  - NEWS line 6;
  - the commit message;
  - `docs/known_issues.md:122-125`, and the lift condition at `:132-134`.
- **Evidence:**
  - Under 1M, `ρq_tot` sediments with the grid-mean flux only
    (`water_advection.jl:85-95`). `sediment_water_tags!` builds the tags'
    fluxes from the same `ᶜq`, `ᶜw` and `ᶠρ`, "so that the tagged fluxes
    sum to vtt exactly" (`:93-95`).
  - The EDMF updraft and environment corrections (`:117-213`) swap only the
    specific energy the flux carries. They write `Yₜ.c.ρe_tot` and the
    energy source tags, never `ρq_tot`.
  - So the tags' sedimentation keeps the partition to rounding under EDMF.
    What it gets wrong is composition: the cell's total-water shares
    instead of the updraft's.
  - `G3_PLAN.md` section 3 says the same thing ("Sedimentation, 1M ... Mass
    exact. Composition is reset at each level").
- **Failure scenario:**
  - A user or a later session reads the error or the known issue and
    concludes that the sedimentation split must be fixed before the refusal
    can lift.
  - `known_issues.md:132-134` says exactly that: the refusal "lifts when the
    tags get ... sedimentation with the updraft and environment
    corrections". There is no water-mass correction to mirror.
  - WP3 plans to lift the refusal on the SGS share alone (`G3_TODO.md`, WP3:
    "Lift the WP1 refusal for one updraft"). The per-subdomain split of
    sedimentation is a composition item for WP4b.
- **Fix:**
  - Keep the missing SGS mass flux as the only reason for partition drift.
  - Restate sedimentation as a composition caveat, for example: "They also
    sediment with the cell's composition rather than the updraft's. That
    keeps the sum but misplaces provenance."
  - In `known_issues.md:132-134`, make the lift condition WP3's: a share of
    the updraft's water flux.
  - Correct NEWS and the message to match.

## Minor

### M1. The reserved-name tests do not pin which refusal fired, or the prefix boundary

- **Where:** `test/config/tracer_config.jl:298-307`.
- **Evidence:**
  - `@test_throws ErrorException` passes for any error.
  - The one accepted name, `evap_fix`, only shows that the match is not a
    suffix match.
  - The mutant that refuses `fix` without the underscore (it would also
    refuse `fixed`, `fixture`, `income`) survives.
- **Fix:**
  - Match the message: `@test_throws r"reserved in `water_tracers`"`.
  - Add accepted names that share letters but not the whole prefix:
    `fixed`, `income`, `stagnant`, `upfixed`.
  - Add one assertion that `energy_source_tags` and `energy_tracers` still
    accept `fix_a`, so the water-only scope is intended and tested.

### M2. The stated reason for `rtag_` and `stag_` does not match the plan's names

- **Where:** the docstring at `src/config/tracer_config.jl:468-477`, and the
  error at `:536-538` ("Each such name is, or will be, the name of another
  diagnostic of the family").
- **Evidence:**
  - `G3_PLAN.md` section 4.5 (line 275) names the rain and snow parts
    `ρq_rtag_<name>` and `ρq_stag_<name>`. A tag called `rtag_a` gives
    `ρq_tag_rtag_a` and `q_tag_rtag_a`, which cannot collide with them.
  - `inc_` collides only with the two fixed names `q_tag_inc_left` and
    `q_tag_inc_moved` (plan lines 237-238).
  - `fix_` and `upfix_` are real collisions. Diagnostics registration keeps
    the first entry (`tagged_water_diagnostics.jl:119-151`, `!haskey`), so
    tags `a` and `fix_a` together make `q_tag_fix_a` return `a`'s ledger
    silently.
- **Fix:** keep the reservation, since it is cheap and WP4b-D may still
  choose other names. Reword the message to say what is true now: "reserved
  for the family's ledgers and for names planned for it". Or narrow `inc_`
  to the two names and drop `rtag_` and `stag_` until WP4b-D fixes the
  naming. Either way, the docstring should cite the plan's names.

### M3. The eddy-diffusion comment is true only under 0M

- **Where:** `test/config/tracer_config.jl:274` ("Eddy diffusion alone shares
  one diffusivity, so it stays allowed"), and the docstring line
  `src/config/tracer_config.jl:1373-1374` for the LES closures.
- **Evidence:**
  - Under 1M, EDMF's eddy diffusion applies `K_h` to `q_tot_eff = q_tot -
    q_rai - q_sno` for `ρq_tot` (`edmfx_sgs_flux.jl:322-326`).
  - The tags take `K_h + K_e` on their whole value (`:390-399`, `α = 1`).
  - The same leak is in the horizontal SGS flux (`:486-497` against
    `:556-561`), hyperdiffusion and the viscous sponge, with or without
    EDMF (`G3_PLAN.md` 4.2, FINDINGS W5b).
  - The LES sentence is right: Smagorinsky–Lilly and constant horizontal
    diffusion act on the whole `q_tot` for `ρq_tot`, with one diffusivity
    (`smagorinsky_lilly.jl:170-178`, `:227-235`;
    `constant_horizontal_diffusion.jl:39-46`).
- **Consequence:** not refusing `edonly_edmfx` is correct. Refusing it under
  1M would have to refuse `vert_diff` and hyperdiffusion under 1M as well,
  and the plan corrects that leak instead. But the new comment and the
  restated issue 3 give no hint that the leak exists.
- **Fix:** write "Under 0M, eddy diffusion moves the tags with the parent's
  diffusivity. Under 1M it leaves a small `q_tot_eff` leak (G3_PLAN 4.2),
  which is not refused." Add one line to known issue 3, or a pointer to the
  WP8 docs item.

### M4. Wording of the prescribed-flow warning, and one overclaim in NEWS

- **Where:** `src/config/tracer_config.jl:1402-1407`, and NEWS line 6.
- **Evidence:**
  - `q_tag_res` exists only when pure region tags exist
    (`tagged_water_diagnostics.jl:181-197`). The test's only tag is a source
    tag, so its warning points at a diagnostic that is not there.
  - The warning fires for any value of the key, even one the model ignores
    (probe D).
  - "Each step" holds only at the default `update_constrain_state_every:
    step`.
  - NEWS says AMD's diffusion "never adds up". But `D_amd` is invariant to
    scaling `χ` (`anisotropic_minimum_dissipation.jl:137-148`), so a tag
    proportional to `q_tot` gets the parent's diffusivity. "In general does
    not add up" is accurate.
- **Fix:** "the flow's surface moisture flux enters `ρq_tot` with no tag, so
  the tags' sum falls short of `ρq_tot` by it (`q_tag_res` shows this when
  region tags exist)". Drop "each step", or say "whenever the state is
  constrained". The value problem goes away with S1's move to the model.

### M5. `tagged_water.md` still frames EDMF as a runnable case

- **Where:** `docs/src/tagged_water.md:271-276` ("see the Caveats below for
  the two known cases (`PrognosticEDMFX` SGS mass flux, ...)"), and `:289`
  ("It is refused under", where "It" could mean the check).
- **Fix:** say that EDMF is refused, so under a supported configuration the
  known unbracketed writer is the prescribed flow. Start the scope sentence
  with "Water tagging is refused under".

### M6. The EDMF refusal is broader than its stated reason

- **Where:** `src/config/tracer_config.jl:1387`.
- **Evidence:** with `edmfx_sgs_mass_flux: false`, the default, the SGS mass
  flux tendency does nothing (`edmfx_sgs_flux.jl:56`). The tags then miss no
  grid-mean water mass. Probe E is still refused, and the message says they
  "miss the updraft's mass flux of water". Two shipped EDMF configs run
  without the mass flux (`prognostic_edmfx_adv_test_column.yml`,
  `prognostic_edmfx_simpleplume_column.yml`).
- **Fix:** keep the broad refusal, since it is simpler, conservative and
  lifted by WP3. Add one clause to the docstring saying it applies whatever
  `edmfx_sgs_mass_flux` is.

### M7. Line citations in known issue 3 are off by a few lines

- **Where:** `docs/known_issues.md:109-116`.
- **Evidence:**
  - The Smagorinsky horizontal loop is `smagorinsky_lilly.jl:170-178`, not
    `169-177`.
  - AMD's horizontal loop runs to `:155` and its vertical loop to `:303`.
    The cited ranges stop at the `ρq_tot` branch.
- **Fix:** cite whole loops, or cite function names only, which do not drift.

## Notes

- **N1. Parity.**
  - The only source file changed is `src/config/tracer_config.jl`.
  - `tracer_tag_tuple` gains a keyword with the default `()`, and the energy
    call sites (`energy_tracer_tuple`, `energy_source_tracer_tuple`) do not
    pass it.
  - The new check runs only when `water_tracers` is non-empty, in
    `AtmosTagging`, at model build.
  - No tendency, cache, callback or state code changed. So every model field
    is bit for bit that of `0b2b1032` for every configuration that still
    builds, and there is no runtime allocation.
- **N2. Restart.** `AtmosTagging` runs again on a restart (`get_atmos`), so a
  checkpoint written with water tags under `prognostic_edmfx` or `amd_les`
  before this commit can no longer be restarted. That is intended, and NEWS
  marks it as breaking. Saying so in the NEWS line would help.
- **N3. Nothing shipped breaks.**
  - On the branch, the only config with `water_tracers` is
    `baroclinic_wave_tagged_water.yml` (no EDMF, no LES). It is still built
    by "Shipped tracer configs still build a model". No test, docs example
    or `.buildkite` job combines water tags with a refused option.
  - On the record branch, `experiments/tag_closure/configs/w1_d4w_grid_tags.yml`
    (V-W1) combines `water_tracers` with `prognostic_edmfx`. Its manifest
    shows `head_sha` `c537903b`, before this commit. It will be refused if
    it is rerun from a tree that contains `2337832d`, as its header says.
  - No tag name anywhere starts with a reserved prefix. The new test's
    `evap_fix` is the only near miss, and it is allowed.
- **N4. Options the model accepts.**
  - `turbconv` accepts `~`, `"edmfx"` (no model), `"prognostic_edmfx"` and
    `"edonly_edmfx"` (`model_getters.jl:922-937`). There is no diagnostic
    EDMF in this version.
  - The LES closures are `smagorinsky_lilly`, `amd_les` and
    `constant_horizontal_diffusion` (`model_getters.jl:1198-1216`).
  - `amd_les` has a `Bool` default, so `override_default_config` turns
    `"true"` into `true` (`yaml_helper.jl:150-168`, probe B), and
    `=== true` is safe.
  - Of these, only AMD computes a diffusivity per tracer. The refusal set is
    complete for mass closure, except for the 1M `q_tot_eff` leak (M3),
    which the plan corrects rather than refuses.
- **N5. The prescribed-flow claims are true.**
  - The surface moisture flux is added to `ρq_tot` outside every bracket
    (`advection.jl:264-267`, from `ᶜρq_tot_vertical_transport_bc` at
    `:172-177`). Nothing mirrors it to the tags: the function has no other
    caller.
  - `prescribe_flow!` clips `ρq_tot` and then calls
    `rescale_water_tags!(Y, p, ᶜρq_tot_before)` (`constrain_state.jl:173-178`).
    That writes the signed change into `ᶜwater_fix`, which `q_tag_fix_<name>`
    reports (`tagged_water.jl:817-820`, `:853-880`).
- **N6. Message wording.** The EDMF message says `water_process_record` is
  allowed, which is useful. "`smagorinsky_lilly` and
  `constant_horizontal_diffusion` share one diffusivity and keep it" would
  be clearer as "... and keep the partition".
- **N7. WP1 is not complete in this commit.** `G3_TODO.md` WP1 also asks to
  close known issue 1 with the post-#64 CI numbers. That is presumably the
  next commit, and it should be in PR-W1 before review.

## Energy families: the same name collisions (report only, out of G3's scope)

- **E1. `energy_source_tags`.** Names starting with `fix_`, and the names
  `inc_left` and `inc_moved`, are accepted (probe C).
  - `e_src_fix_<name>` is tag `<name>`'s repair ledger
    (`energy_source_tag_diagnostics.jl:82`). `e_src_inc_left` and
    `e_src_inc_moved` are the increment ledger under
    `energy_source_tag_transport: enthalpy_increment` (`:141-175`).
  - Registration keeps the first entry with a given name (`!haskey`), so a
    collision is silent. With tags `a` and `fix_a`, `e_src_fix_a` returns
    `a`'s ledger and tag `fix_a`'s amount cannot be output. With a tag named
    `inc_left`, the ledger of that name returns the tag.
  - The fix would be the same keyword: `reserved_prefixes = ("fix_",)`, plus
    the two exact names, in `energy_source_tracer_tuple`.
- **E2. `energy_tracers`.** The family has only `e_tag_<name>` and
  `e_tag_res`, and `res` is already refused. So no collision today.
- **E3. AMD.** It also computes a per-tracer diffusivity for `ρe_tag_*` and
  `ρe_src_*` (the same `foreach_gs_tracer` loops). Their sums therefore do
  not follow `ρe_tot` under `amd_les` either, and nothing refuses or warns.
  Record it for G4.
