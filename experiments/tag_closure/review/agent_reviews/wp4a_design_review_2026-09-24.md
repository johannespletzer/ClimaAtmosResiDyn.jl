# Review of `design/ZERO_M_SPLIT.md` (WP4a), 2026-09-24

`clima-numerics-reviewer`, effort xhigh, on the note's first draft, against
`claude/water-tags-edmf-wp5` at `fd07d902` and ClimaTimeSteppers 1.0.1.
Condensed; the reviewer's `file:line` evidence is kept. How each point was
taken is in the note's section 9.

**Computed by the reviewer:** the Newton behaviour of the diagonal alone, no
entry, and both entries in a scalar model with the Jacobian updated every
iteration; `ShareDifferences`' bounds, sums, inventory and source-tag excess
over 2e5 random cases; the mixed-normalization negative share; the NaN and
Inf·0 cases in Julia 1.11; the size of `c` from CloudMicrophysics and
ClimaParams.

**Verdict:** the split (2) and `pr_tag` (3) can start once B2 and S1–S4, S7–S9
are in the note; the switch (4) waits on B1; the experiment needs S6. No
proposal writes a model field.

## Blocking

**B1. The switch is half of the analytic Jacobian, and alone it makes one
Newton iteration worse.** The loss `min(Δ,0)·ρq_tagᵢ/ρq_tot` (`tagged_water.jl:286-288,
389-393`), with `ρq_tot` the iterate, has the diagonal `Δ⁻/ρq_tot` and a cross
term `−Δ⁻ρq_tagᵢ/ρq_tot²`. `dq` is frozen in the solve
(`microphysics_cache.jl:681-682, 700-729`), so the parent needs no `ρq_tot`
entry. Newton starts from the predictor (CTS `imex_ark.jl:212, 312`). For a
pure proportional sink, with `c = dtγ|Δ|/ρq_tot`: no entry gives `Ŷᵢ(1−c)`,
the exact fixed point; the diagonal alone `Ŷᵢ/(1+c)`, an error of
`Ŷᵢc²/(1+c)` per stage; both entries exact. Computed: diagonal alone, one
iteration, closure off by 2.5e-3 at c = 0.05 and 2.1e-2 at c = 0.145; no entry
and both entries 0 to rounding. With other implicit processes changing the
shares, the diagonal alone trades per-tag error against closure (7.5× worse in
one case); the pair beat both alternatives in every case. So the note's
"the tags converge faster" and known issue 4's "in principle error in the
answer" (`known_issues.md:131-133`) are backwards. Owner decision: (i) the
pair, whose one-way cross block drops the tags from `uncoupled_jacobian_names`
(`manual_sparse_jacobian.jl:736-751`) unless the split solver back-substitutes
`rhsᵢ −= J_{tag,ρq_tot}·Δρq_tot`, with its own parity test; or (ii) the
diagonal alone, with this prediction stated. Either way known issue 4 is
restated.

**B2. φ̄ undefined; the natural reading breaks the bounds.** `ShareDifferences`
works on partition-normalized shares `min(ε̄ᵢ/total, 1)`
(`energy_source_tags.jl:1965-1966, 2044-2045, 2093`); the bracket uses the
unnormalized `water_tag_fraction`. Mixing them goes negative once the partition
drifts (S = 0.98, grid share 0.1, plume share 0 gives −0.002). With the
normalized φ̄, φʲ and φ⁰ lie in [0,1] and sum to 1 (2e5 cases), but φ̄ is NaN
where the partition's total is 0, and normalizing changes how `q_tag_res`
behaves as a cell rains out. Fix: `φᵏᵢ = S·φᵏᴺᵢ` with `S = Σ_P
water_tag_fraction`, a guard for total ≤ 0, and the non-EDMF path unchanged.

## Should fix

**S1.** A source tag's environment share can exceed 1 in the default mode
(its own θ; a negative difference unbounded, `energy_source_tags.jl:2082-2090`;
1.19 in a computed case, 114 at worst in sampling). Clamp to [0,1].
**S2.** `edmfx_sgs_mass_flux: false`: no default-mode scratch
(`tagged_water_edmf.jl:118`), no partition check (58), yet the updraft rains
out; fall back to the grid share. **S3.** `ρaᵏ < 0` is possible (the filter
clamps `ρaʲ` only to `ρʲ`, `mass_flux_closures.jl:274`; iterates unfiltered), so
`Δ⁰ > 0` can occur; apply `Δᵏφᵏ` for both signs under 0M and include it in
`pr_tag`. **S4.** Copies: the environment share is undefined where
`ρq_tot − ρaʲq_totʲ ≤ 0` or all numerators ≤ 0, while `Δ⁰` can be nonzero
(`variable_manipulations.jl:406-440`); fall back to φ̄. On the implicit path
`sgs_ρa_implicit_tendency!` overwrites the `ρa` sink (`implicit_tendency.jl:147`;
`initialize_implicit_problem.jl:282-291`), so the environment's implied values
change by `Δ⁰φ⁰ᵢ + Δʲχᵢʲ` there; the copies' updraft share is unnormalized, so
the partition's updraft loss is `Δʲ·Σφʲ`. **S5.** The switch: sign in the
code's convention `dtγ*min(Δ,0)/ρq_tot` (`dtγ∂T/∂Y − I`,
`manual_sparse_jacobian.jl:2264, 1308`); accumulate after
`update_diffusion_jacobian!` (1564-1575); a `TridiagonalRow` block
(`merge_jacobian_blocks`, 435-445); no-op or refuse under explicit
microphysics and 1M; refuse under PrognosticEDMFX; document
`use_auto_jacobian`; parity holds for the diagonal alone. **S6.** The
experiment: a converged reference per dt; `newton_rtol` measures the whole
state, dominated by `ρe_tot` (`integrator.jl:109-113`; CTS
`convergence_checker.jl:75-86`), so fixed 20 iterations and a 20-against-40
check; the paired on−off difference as the primary readout; predictions
pre-registered (`c ≤ dtγ(q_c/q_tot)/τ`, τ = 1000 s, ≈ 2e-3 on V-W0a; the pure
sink part ≈ 3.5e-6 per stage, ∝ dt²; on and off agree at 10 iterations); no
Newton residual norms are available (`NewtonsMethod` without `verbose`); pin
`water_tag_transport: tracer`; the copies' part of issue 4 in or out; a
decision rule; 11 runs, not 10. **S7.** Compute the shares once at the top of
`implicit_tendency!` and let the exchange read them, since
`sgs_exchange_of_water_tags!` overwrites `ᶜq_tag_plume` in place (306-307); a
bitwise test of the exchange and an allocation gate; (b)'s stated obstacle was
wrong (`applied_update.jl:47-49` forbids nesting, not deferral), its real one
is the explicit path. **S8.** `pr_tag` recomputes the shares from Y at output;
Σ = `pr` only where the shares sum to one and with production included;
`pr` is upward-positive, so negative (`core_diagnostics.jl:611-612`); it is
instantaneous at the step's end state; define its rain and snow parts and its
1M behaviour. **S9.** State and test that the non-EDMF and EDOnly paths are
unchanged bit for bit (`tendency.jl:77-87`; `ρa⁰` returns `ρ` under EDOnly,
`variable_manipulations.jl:510-517`).

## Minor

The SGS flux is at `implicit_tendency.jl:126-133`, not 97. Test tolerances at
eps·|Yₜ before the process|, not eps·|Δ|. Float32: `_exchange_energy_ratio` is
Inf where `ρa⁰q⁰` underflows, and `−θ·Inf·0 = NaN` (pre-existing); guard with
`isfinite`. The switch changes no state and is outside the restart guard; stamp
it in the manifests. The energy source tags' 0M bracket keeps the grid share
under EDMF (a G4 item). A `:microphysics` source tag under 0M only receives
production; consider refusing it. Where the exchange is off, the updraft's rain
falls back to the grid share; say so.
