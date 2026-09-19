# Review of 35042f33 (enthalpy_increment prototype), details

Read-only review. Nothing was run (no Julia). "Verified" below means verified
by reading the code at the cited lines, not by execution.

Paths: EST = src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl
in the worktree ../ClimaAtmosResiDyn-inc. CTS = ClimaTimeSteppers 1.0.1 at
julia-depots/terrabyte-cpu/packages/ClimaTimeSteppers/ZxgOv/src.
ClimaCore = packages/ClimaCore/TKCzQ (1.0.0, the one in .buildkite/Manifest).

## F1 (bug, high). Stages that use T_imp without a solve, and algorithms with no hook

Under enthalpy_increment the tags' only vertical advection is the post-solve
correction: the generic tracer loop skips them (advection.jl:255-258) and the
explicit enthalpy share is now off (EST:1224-1236). The correction runs only
inside a solved stage (CTS imex_ark.jl:198, :209, :234-238).

CTS evaluates `T_imp!` explicitly where a_imp[i,i] == 0 but column i or
b_imp[i] is nonzero (imex_ark.jl:279-281; imex_ssprk.jl:182-186). There the
parent gets its central vertical advection of rho_e_tot and rho with weight
a_imp[j,i] and b_imp[i]. The tags get nothing, and the stage-j snapshot is
taken after that weight was already applied to E only, so no later mismatch
catches it. The error is a transport lag every step, with no bound.

Affected (read in imex_tableaus.jl):
  - SSP333: a_imp[2,1] = 4γ+2β, b_imp[1] = 1/6 (:757-762). Listed in the
    `ode_algo` help.
  - IMKG342a, IMKG343a: a_imp[4,1] = 1/3, a_imp[5,1] = b_imp[1] = 1/4
    (imkg_imp :396-398, β = (0, 1/3, 1/4) at :617-622). IMKG343a is in the help.
  - ARK2GKC (a_imp[2,1], b_imp[1] = √2/4), DBM453, HOMMEM1 (b_imp[1] = 5/18),
    ARK437L2SA1 and ARK548L2SA2 (a_imp[i,1] = a_imp[i,2], :966).
  - Every ERK: ExplicitAlgorithm builds IMEXTableau(a,b,c,a,b,c)
    (explicit_tableaus.jl:76), so every stage is an explicit T_imp.
  - Rosenbrock: rosenbrock.jl calls neither initialize_imp! nor T_post_imp!.
  - prescribed_flow: T_imp! = nothing, so the wrapper is not applied
    (integrator.jl:216-219), and the parent's advection runs explicitly in
    fully_explicit_tendency! (remaining_tendency.jl:318-323).
In the last three cases the tags get no vertical advection at all.
Unaffected: the ARS family (column 1 of a_imp is zero and b_imp[1] = 0), SSP222.

Fix, minimal: refuse the combination when the integrator is built (or in
AtmosTagging with the ode config). Require an IMEXAlgorithm with a Newton
method and no prescribed flow. For every i with iszero(a_imp[i,i]), require
all(iszero, a_imp[:, i]) && iszero(b_imp[i]). Put it in the config help too.

## F2 (bug, medium). Parent-budget ledger crashes with enthalpy_increment and no upwinding

The hook is now wired when `energy_q_tot_upwinding: none`. The ledger's hook
template still decides by upwinding alone: adapter.jl:848-854
(`has_post_implicit = implicit_solve && upwinding != :none`) and
coverage_registry.jl:131-132. `meter_post_implicit` wraps the new struct in
PostImplicitMeter (adapter.jl:1199), whose `next_call!` finds 0 template
entries for :T_post_imp! and errors at the first implicit stage
(adapter.jl:1011-1020). With upwinding on (the default vanleer) the template
has the entry and works, and the ledger books only parent fields of dY, which
the tags' part does not touch.
Fix: derive has_post_implicit from the wired hook, e.g. `... ||
follows_implicit_increment(atmos.energy_source_tagging_model)`, in both
places, or pass `!isnothing(T_post_imp!)` into build_parent_budget.

## F3 (risk). Parity: reads as bit for bit, not run

  - -0.0 fill (EST:1651): dtγ > 0, so dtγ*(-0.0) = -0.0 and x + (-0.0) = x for
    every x, including +0.0, -0.0, Inf and NaN. Exact.
  - With the parent's post present, the wrapper calls it first. It overwrites
    all of dY with +0.0 and sets rho_e_tot and rho_q_tot
    (implicit_tendency.jl:379-395). The correction then writes only tag
    entries of dY. Upstream fields are unchanged, and the extra cache_imp! is
    upstream's own.
  - Without the parent's post, CTS now calls cache_imp!(U) before the hook
    (imex_ark.jl:235). set_implicit_precomputed_quantities! writes Y: the
    surface and top u₃ (precomputed_quantities.jl:703-706, 480-548). Both are
    pure functions of u_h and are rewritten after the post-Newton DSS by
    cache_imp!/cache! (imex_ark.jl:250-254), which set_precomputed_quantities!
    does first. At an FSAL last stage (e.g. ARS222) T_imp[s] for boundary u₃
    differs, but the end-of-step cache!(u) rewrites it from the same u_h,
    before any reader. Everything else it writes is p.precomputed, refilled.
    So I expect bit for bit, but it rests on those overwrites. G1 criterion 3
    needs the CI test (tags off vs enthalpy_increment, upwinding none and
    vanleer, compare the model's fields).
  - Cost: that extra cache_imp! is a full implicit precompute, including
    saturation adjustment, per implicit stage, only when upwinding is none.
  - Pre-existing, not new: with Krylov or use_newton_rtol, tag fields enter the
    solver's norms and could change the parent. Not in the default.

## F4 (risk). What m absorbs, and where the column part lands

m is the whole implicit residual of the partition: vertical advection, the
parent's upwind correction, the Newton lag of C1b, sedimentation, tracer
diffusion against h_tot diffusion, the implicit microphysics bracket, and at
`update_constrain_state_every: dss` the post-init constraint. No term is
double counted, because m is measured after the tags' own implicit terms.
The explicit vertical share is off, so nothing is counted twice there.
Horizontal advection and hyperdiffusion shares stay (moves_as_enthalpy
includes the new type).
But:
  - In a column where a local source lag (0M/1M rain-out, sedimentation at the
    ground) meets a transport dipole, the column part is put where |m| is
    large, not where the source acted. The rest is moved as a flux. So part of
    a local lag becomes vertical provenance transport. In a column with one
    sign, r = ±1 and nothing moves, which is right.
  - The donor direction follows the sign of the net correction flux, not the
    flow.
  - Positivity needs the donor's energy Courant number over dtγ at or below 1.
    The parent's advection is implicit because it can exceed that. Then the
    tags go negative and the repair acts (E59 option 2 showed what that costs).
    Worth logging.
  - Shares use E(U) after the solve with tags from before transport. Partition
    shares are normalised, so they still sum to 1. A source tag's
    clamp(tag/E_post) is biased where E changed a lot in the stage.

## F5 (risk, Float32). Precision of m

  - dtγ from CTS is Float64 (ITime float, ClimaUtilities ITime.jl:409-414).
    It is stored in Ref{FT} (EST:1515, :1561). Then F/dtγ32 * dtγ64 is off by
    at most 2^-24 relative. That is negligible, but storing Float64 is free.
  - E is stored combined (EST:1553). In Float32 with c = 110495,
    E ≈ 4e5 J/m³ and ulp ≈ 0.03, so m carries about 0.03 to 0.1 J/m³ of noise
    per cell per stage. Keep rho_e_tot and rho snapshots apart and form
    Δrho_e_tot + c·Δrho. This matters for G1 criterion 5.

## F6 (types, GPU, AD). No defect found

  - zeros(axes(Fields.level(Y.f, half))) uses Spaces.undertype, so it matches
    FT (ClimaCore Fields.jl:458). It is the same pattern as surface_rain_flux.
  - Broadcasting a face-level field against face fields is allowed
    (issubspace, LevelGrid.full_grid, extruded.jl:264-266; the PointSpace rule
    for columns).
  - ifelse evaluates M/A = NaN when A = 0 and then discards it. That is fine.
  - The Ref is read on the host and never enters a broadcast. It is the only
    Ref in the cache (REDUCTION_COUNT aside).
  - Duals: only p.precomputed and p.scratch are dualised
    (autodiff_utils.jl:61-72). The hook and the snapshot run only from the
    stepper, with Float values.

## F7. Signs, quadrature, boundaries: correct (shallow atmosphere)

column_integral_indefinite! gives ᶠI·ΔA_bot = Σ m_c J_c (ClimaCore
integrals.jl:44-50). J·CT3(W(F)) = (J/Δz)·F = ΔA·F. In a shallow atmosphere ΔA
is the same on every face of a column, so
-ᶜadvdivᵥ(CT3(W(F))) = (m - r|m|)/dtγ to rounding. Σ partition shares = 1
where norm > 0 at the donor, so the partition gets m - r|m| per cell. The
bottom face is -0.0. The top face is set to exactly zero by ᶜadvdivᵥ's
SetValue(CT3(0)) (abbreviations.jl:106-109), so the top rounding joins the
column part.
Deep atmosphere: ΔA ∝ (1+z/R)², so the round trip is off by O(Δz/R) per cell.
It still conserves, but leaves a small systematic remainder.
Where norm = 0 at the donor, nothing moves, silently.

## F8. CTS semantics (question 1): confirmed

  - temp = U just before initialize_imp! (imex_ark.jl:212-215), so the snapshot
    is at temp. The EDMF initialiser writes only sgs u₃ and ρa.
  - dY is added once as dtγ·dY (:236-237) and folded into
    T_imp[i] = (U-temp)/dtγ (:284), so the b_imp and a_imp weights are right.
  - After the hook come dss! (linear, and column-local results agree at shared
    nodes, so it is identity to rounding) and, at `stage` or `dss` cadence and
    not at an FSAL last stage, constrain_state!. The repair keeps the partition
    sum, except where the negatives outweigh the positives. Parent constraints
    that write E are not followed; that is not new.
  - FSAL skips only the post-Newton constraint and cache, not the hook.

## F9. Restart

The transport text is recorded and compared. The snapshot, dtγ and the
integrals live within one stage and carry nothing across steps, so nothing
else is needed.

## Nits

  - tracer_config.jl:1302 and types.jl:2541: the errors say
    "`energy_source_tag_transport: enthalpy`" for the new value too.
  - EST:1224-1227: a comment sits between `=` and the body. Move it above.
    Run the pinned formatter.
  - Docstrings not updated: moves_as_enthalpy and
    energy_source_tag_moves_as_enthalpy ("which `...: enthalpy` selects");
    enthalpy_vertical_advection_of_energy_source_tags! (says the tags move
    explicitly); the field list of _energy_source_tagging_cache.
    docs/src/energy_source_tags.md has no word on the new value, although the
    help points there. The help should say the mode needs an ARS-type IMEX
    algorithm.
  - The two definite integrals repeat the top face of the indefinite ones:
    use Fields.level(ᶠI, nlevels + half). That saves two column scans and two
    2-D fields.
  - No tests. Needed: the round trip (-div F = m - r|m|, zero boundary
    fluxes), the -0.0 parity, the hook composition with and without a post,
    and the refusal from F1.

## The owner's question 3: minimal additions

  - Ledger: a stage-local cache sum would take the wrong weights, because the
    correction enters the step as dt·Σ b_imp[i]·T_imp[i]. The minimal correct
    ledger is a prognostic record field with no ρ prefix, like `e_prc_*`,
    e.g. `e_src_inc_moved` and `e_src_inc_left`. The hook writes (m - r|m|)/dtγ
    and r|m|/dtγ into its dY entries. The stepper then integrates them with
    the right weights, and restarts carry them. Reuse the process-record
    plumbing for the Jacobian identity and the outputs.
  - Switch: `energy_source_tag_transport: enthalpy` against
    `enthalpy_increment` already is one.
  - Warning: a per-stage global max costs an MPI reduction and a GPU sync.
    Instead, keep a running cell-wise max of |m|/E (or of the moved share) in
    a cache field. Check it in the existing closure or diagnostic callback
    against a config threshold, e.g. `energy_source_tag_increment_warn`, and
    `@warn ... maxlog = 1`.
