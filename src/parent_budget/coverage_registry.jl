#####
##### Parent-budget ledger: the executable coverage registry
#####
##### Every path that can change an authoritative parent field is one row here,
##### and the rows a configuration selects become the schema the ledger checks a
##### run against. `docs/src/parent_budget/coverage.md` shows the same rows as
##### tables, and `test/parent_budget/registry_tests.jl` holds the two to exact
##### agreement, so a reader of either sees what the code declares.
#####
##### A row has two halves. The documentation half is the prose of its table
##### cells, kept here so that the page cannot drift from the code. The
##### executable half is a guard over a `RegistryContext`, and the derivations at
##### the end of this file, which turn a selected row into a reservoir, a
##### channel, a roster entry, a final map, or a transfer event.
#####
##### Expectations come from the configuration. The schema is built here before
##### the first step, and nothing on the collection path adds to it.

# ============================================================================
# Context and guards
# ============================================================================

"""
    RegistryContext(atmos; dss, implicit_solve, restart = false)

What a guard may look at when deciding whether its row applies to a run.

  - `atmos` is the `AtmosModel`.
  - `moist` and `slab` are the two applicability facts every disposition needs,
    resolved once from the model so that no guard reads field presence.
  - `dss` says whether the space performs direct stiffness summation. A single
    column does not, and then the `dss!` hook writes nothing.
  - `implicit_solve` says whether the algorithm solves an implicit stage with
    Newton's method. An `ExplicitAlgorithm` evaluates `T_imp!` explicitly, so it
    has an implicit channel but no solve defect.
  - `restart` says whether the run restores a checkpoint.
  - `constraint_cadence` is `update_constrain_state_every` as a symbol, `:step`,
    `:stage` or `:dss`. It decides whether `constrain_state!` also fires on the
    Newton-solved stage, where the stepper folds its change into the stored
    implicit tendency.

The last four are properties of the run rather than of the model, which is why
they are arguments and not read from `atmos`.
"""
struct RegistryContext{A}
    atmos::A
    moist::Bool
    slab::Bool
    dss::Bool
    implicit_solve::Bool
    restart::Bool
    constraint_cadence::Symbol
end

function RegistryContext(
    atmos;
    dss::Bool,
    implicit_solve::Bool,
    restart::Bool = false,
    constraint_cadence::Symbol = :step,
)
    constraint_cadence in (:step, :stage, :dss) || error(
        "Unknown constraint cadence $constraint_cadence; expected :step, :stage or :dss.",
    )
    moist = owns_atmosphere_water(atmos.microphysics_model)
    slab = has_surface_reservoir(atmos.surface.temperature)
    return RegistryContext(
        atmos,
        moist,
        slab,
        dss,
        implicit_solve,
        restart,
        constraint_cadence,
    )
end
# The two model facts are resolved once here, so no guard reads field presence.

# The guards. Each is named for the configuration fact it tests, so a row reads
# as a sentence. They take the context and return a Bool, and none of them
# reads the state: applicability is declared, never sniffed.
always(::RegistryContext) = true
moist(c::RegistryContext) = c.moist
dss(c::RegistryContext) = c.dss
restart(c::RegistryContext) = c.restart
implicit_solve(c::RegistryContext) = c.implicit_solve
hyperdiffusion(c::RegistryContext) = !isnothing(c.atmos.hyperdiff)
viscous_sponge(c::RegistryContext) = !isnothing(c.atmos.viscous_sponge)
rayleigh_sponge(c::RegistryContext) = !isnothing(c.atmos.rayleigh_sponge)
held_suarez(c::RegistryContext) = c.atmos.radiation_mode isa HeldSuarezForcing
rrtmgp(c::RegistryContext) = c.atmos.radiation_mode isa RRTMGPI.AbstractRRTMGPMode
# The modes that build a radiative flux and apply its divergence, so that what
# they add to the atmosphere is what crosses the top and the surface.
flux_form_radiation(c::RegistryContext) =
    c.atmos.radiation_mode isa
    Union{RRTMGPI.AbstractRRTMGPMode, RadiationDYCOMS, RadiationISDAC}
trmm_lba(c::RegistryContext) = c.atmos.radiation_mode isa RadiationTRMM_LBA
scm_coriolis(c::RegistryContext) = !isnothing(c.atmos.scm_coriolis)
subsidence(c::RegistryContext) = !isnothing(c.atmos.subsidence)
large_scale_advection(c::RegistryContext) = !isnothing(c.atmos.ls_adv)
external_forcing(c::RegistryContext) = !isnothing(c.atmos.external_forcing)
advection_test(c::RegistryContext) = c.atmos.advection_test === true
smagorinsky(c::RegistryContext) = !isnothing(c.atmos.smagorinsky_lilly)
amd(c::RegistryContext) = !isnothing(c.atmos.amd_les)
constant_diffusion(c::RegistryContext) =
    !isnothing(c.atmos.constant_horizontal_diffusion)
nogw(c::RegistryContext) = !isnothing(c.atmos.non_orographic_gravity_wave)
ogw(c::RegistryContext) = !isnothing(c.atmos.orographic_gravity_wave)
prescribed_flow(c::RegistryContext) = !isnothing(c.atmos.prescribed_flow)
water_tags(c::RegistryContext) = !isnothing(c.atmos.water_tagging_model)
surface_flux(c::RegistryContext) = !c.atmos.disable_surface_flux_tendency
slab_qflux(c::RegistryContext) = c.slab && c.atmos.surface.temperature.q_flux
zero_moment(c::RegistryContext) =
    c.atmos.microphysics_model isa EquilibriumMicrophysics0M
one_moment(c::RegistryContext) =
    c.atmos.microphysics_model isa NonEquilibriumMicrophysics1M
implicit_microphysics(c::RegistryContext) =
    c.atmos.microphysics_tendency_timestepping == Implicit()
explicit_microphysics(c::RegistryContext) =
    c.atmos.microphysics_tendency_timestepping == Explicit()
zero_moment_implicit(c::RegistryContext) = zero_moment(c) && implicit_microphysics(c)
one_moment_implicit(c::RegistryContext) = one_moment(c) && implicit_microphysics(c)
one_moment_explicit(c::RegistryContext) = one_moment(c) && explicit_microphysics(c)
explicit_diffusion(c::RegistryContext) =
    c.atmos.diff_mode == Explicit() && !isnothing(c.atmos.vertical_diffusion)
implicit_diffusion(c::RegistryContext) =
    c.atmos.diff_mode == Implicit() && !isnothing(c.atmos.vertical_diffusion)
post_implicit_correction(c::RegistryContext) =
    c.implicit_solve && c.atmos.numerics.energy_q_tot_upwinding != Val(:none)
folded_dss(c::RegistryContext) = c.implicit_solve && c.dss
folded_constraint(c::RegistryContext) =
    c.implicit_solve && c.constraint_cadence !== :step
quasimonotone_limiter(c::RegistryContext) = !isnothing(c.atmos.numerics.limiter)
vapor_tendency(c::RegistryContext) =
    c.atmos.tracer_nonnegativity_method isa TracerNonnegativityVaporTendency
vapor_constraint(c::RegistryContext) =
    c.atmos.tracer_nonnegativity_method isa TracerNonnegativityVaporConstraint
element_constraint_categories(c::RegistryContext) =
    c.atmos.tracer_nonnegativity_method isa TracerNonnegativityElementConstraint{false}
element_constraint_qtot(c::RegistryContext) =
    c.atmos.tracer_nonnegativity_method isa TracerNonnegativityElementConstraint{true}
vertical_water_borrowing(c::RegistryContext) =
    c.atmos.tracer_nonnegativity_method isa TracerNonnegativityVerticalWaterBorrowing
out_of_scope(c::RegistryContext) = !is_supported(c.atmos)

# Any prognostic field the horizontal tracer advection and the tracer
# hyperdiffusion would move. Water is the common case; the tag families and the
# passive tracers are the others.
function has_tracers(c::RegistryContext)
    c.moist && return true
    atmos = c.atmos
    return !isnothing(atmos.chemistry_model) ||
           !isnothing(atmos.tagging_model) ||
           !isnothing(atmos.water_tagging_model) ||
           !isnothing(atmos.energy_source_tagging_model) ||
           !isnothing(atmos.energy_process_record) ||
           !isnothing(atmos.water_process_record)
end

# ============================================================================
# Supported scope
# ============================================================================

"""
    unsupported_reason(atmos) -> Union{Nothing, String}

Return why the ledger refuses `atmos`, or `nothing` when the configuration is
inside the contract's supported scope. The reasons are the contract's own. The
EDMF subdomains raise a modelling question the bookkeeping cannot settle. A
prescribed flow overwrites the state. Chemistry changes composition through an
external solver. The two-moment schemes carry unaudited paths.
"""
function unsupported_reason(atmos)
    atmos.turbconv_model isa AbstractEDMF && return "EDMF turbulence-convection " *
           "models are out of scope; their subdomains are a modelling question " *
           "before they are a bookkeeping one"
    isnothing(atmos.prescribed_flow) ||
        return "a `prescribed_flow` run overwrites mass and energy from a " *
               "prescribed field, so nothing is evolved to close"
    atmos.chemistry_model isa GasPhaseChem &&
        return "gas-phase chemistry changes tracer composition through an " *
               "external solver that the registry does not audit"
    atmos.microphysics_model isa
    Union{NonEquilibriumMicrophysics2M, NonEquilibriumMicrophysics2MP3} &&
        return "the two-moment microphysics schemes carry number-concentration " *
               "paths that have not been audited"
    return nothing
end

"""
    is_supported(atmos) -> Bool

Return whether `atmos` is inside the contract's supported scope.
"""
is_supported(atmos) = isnothing(unsupported_reason(atmos))

"""
    check_supported(atmos)

Refuse an out-of-scope configuration at setup, naming the reason. The refusal
comes before a long simulation starts. A configuration outside the scope has
rows the registry has never dispositioned. A ledger that ran on it would close
over paths nobody declared.
"""
function check_supported(atmos)
    reason = unsupported_reason(atmos)
    isnothing(reason) && return nothing
    return error(
        "The parent-budget ledger cannot be enabled for this configuration: " *
        "$reason. See the supported scope in docs/src/parent_budget/contract.md.",
    )
end

# ============================================================================
# Rows
# ============================================================================

"""
    CoverageRow

One row of the coverage registry.

`table` names the section of `coverage.md` the row appears in: `:envelopes`,
`:limited`, `:explicit`, `:implicit`, `:final_maps` or `:transfers`. The string
fields are the row's table cells, verbatim, so that the documentation and the
code cannot disagree without a test noticing. A transfer row carries
`topology`, `modeled_legs` and `counterparty` instead of `dispatch` and
`channel`, because its table has those columns instead.

`dispositions` is the row's `Disposition M·W·E` cell in `BUDGET_QUANTITIES`
order and in the ledger's vocabulary, see `EXPECTED_DISPOSITIONS`. `level` is
the collection level and `state` the collection state, both as symbols with
the table's spelling (`:final_map` for "final map"). `step` is the row's `Step`
column.

`applies` is the guard: a function of a `RegistryContext` that says whether
the configuration selects the row. It is the executable form of the `Guard`
cell, and the two are written to agree.

`event` is the label of the applied-update bracket that measures the row. It
is `nothing` for a row that needs no measurement. Such a row has every
quantity provably zero or not applicable, and the ledger books it from this
registry. It is not a table cell. The labels are the ones the tendency code
passes to `open_applied_update!`. The same label can measure one row in one
configuration and another row elsewhere. `:radiation` measures a prescribed
heating under TRMM_LBA and two boundary crossings under RRTMGP.
"""
struct CoverageRow
    table::Symbol
    id::Symbol
    dispatch::Union{Nothing, String}
    channel::Union{Nothing, String}
    topology::Union{Nothing, String}
    modeled_legs::Union{Nothing, String}
    counterparty::Union{Nothing, String}
    guard::String
    reservoirs::String
    parent_fields::String
    dispositions::NTuple{length(BUDGET_QUANTITIES), Symbol}
    proof::String
    level::Symbol
    state::Symbol
    evidence::String
    test::String
    step::Int
    applies::Function
    event::Union{Nothing, Symbol}
    function CoverageRow(
        table,
        id,
        dispatch,
        channel,
        topology,
        modeled_legs,
        counterparty,
        guard,
        reservoirs,
        parent_fields,
        dispositions,
        proof,
        level,
        state,
        evidence,
        test,
        step,
        applies,
        event = nothing,
    )
        table in REGISTRY_TABLES ||
            error(
                "Coverage row $id names table $table, which is not one of $REGISTRY_TABLES.",
            )
        check_dispositions("Coverage row $id", dispositions)
        level in (:envelope, :decomposition, :final_map, :transfer) ||
            error("Coverage row $id has collection level $level.")
        state in (:none, :envelope, :collected, :verified) ||
            error("Coverage row $id has collection state $state.")
        return new(
            table,
            id,
            dispatch,
            channel,
            topology,
            modeled_legs,
            counterparty,
            guard,
            reservoirs,
            parent_fields,
            dispositions,
            proof,
            level,
            state,
            evidence,
            test,
            step,
            applies,
            event,
        )
    end
end

"""
    REGISTRY_TABLES

The sections of `coverage.md` that hold `CoverageRow`s, in page order.
"""
const REGISTRY_TABLES =
    (:envelopes, :limited, :explicit, :implicit, :final_maps, :transfers)

# A row of one of the five dispatch tables.
CoverageRow(
    table::Symbol,
    id::Symbol,
    dispatch::String,
    channel::String,
    guard::String,
    reservoirs::String,
    parent_fields::String,
    dispositions,
    proof::String,
    level::Symbol,
    state::Symbol,
    evidence::String,
    test::String,
    step::Int,
    applies,
    event = nothing,
) = CoverageRow(
    table,
    id,
    dispatch,
    channel,
    nothing,
    nothing,
    nothing,
    guard,
    reservoirs,
    parent_fields,
    dispositions,
    proof,
    level,
    state,
    evidence,
    test,
    step,
    applies,
    event,
)

# A row of the transfer table.
CoverageRow(
    table::Symbol,
    id::Symbol,
    topology::String,
    modeled_legs::String,
    counterparty::String,
    guard::String,
    reservoirs::String,
    parent_fields::String,
    dispositions,
    proof::String,
    level::Symbol,
    state::Symbol,
    evidence::String,
    test::String,
    step::Int,
    applies,
    event = nothing,
) = CoverageRow(
    table,
    id,
    nothing,
    nothing,
    topology,
    modeled_legs,
    counterparty,
    guard,
    reservoirs,
    parent_fields,
    dispositions,
    proof,
    level,
    state,
    evidence,
    test,
    step,
    applies,
    event,
)

"""
    NonAuthoritativePath(id, dispatch, hook, why)

A path that was considered and writes no parent field, so it is never booked.
Listed so that no future reader has to rediscover that it was considered.
"""
struct NonAuthoritativePath
    id::Symbol
    dispatch::String
    hook::String
    why::String
end

"""
    COVERAGE_ROWS

Every row of the coverage registry, in the order the tables of `coverage.md`
list them.
"""
const COVERAGE_ROWS = CoverageRow[
    CoverageRow(
        :envelopes,
        Symbol("env.explicit_main"),
        "accepted increment from `Yₜ`",
        "`Yₜ`",
        "always",
        "atmosphere, and slab when configured",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "applied increment equals tableau-weighted stage sum",
        :envelope,
        :collected,
        "accepted explicit weights from the pinned tableau",
        "`envelope_tests.jl`",
        3,
        always,
    ),
    CoverageRow(
        :envelopes,
        Symbol("env.explicit_limited"),
        "accepted increment from `Yₜ_lim`",
        "`Yₜ_lim`",
        "always",
        "atmosphere, and slab when configured",
        "`ρq_tot`, categories, tracers",
        (:measured, :measured, :measured),
        "limited channel integrated through the limiter, separately from `Yₜ`",
        :envelope,
        :collected,
        "accepted limited-channel increment",
        "`envelope_tests.jl`",
        3,
        always,
    ),
    CoverageRow(
        :envelopes,
        Symbol("env.implicit"),
        "accepted increment from `T_imp!`",
        "`T_imp!`",
        "always",
        "atmosphere, and slab when configured",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "effective implicit increment as the pinned solver forms it",
        :envelope,
        :collected,
        "stage weights and hook-folding established against the pinned version",
        "`envelope_tests.jl`",
        3,
        always,
    ),
    CoverageRow(
        :limited,
        Symbol("lim_chan.horizontal_tracer_advection"),
        "`horizontal_tracer_advection_tendency!`",
        "`Yₜ_lim`",
        "moist or tracers configured",
        "atmosphere",
        "`ρq_tot`, categories, tracers",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "conservative horizontal divergence, global sum zero",
        :decomposition,
        :collected,
        "operator global-zero test on a real state",
        "`explicit_attribution_tests.jl`",
        4,
        has_tracers,
    ),
    CoverageRow(
        :limited,
        Symbol("lim_chan.tracer_hyperdiffusion"),
        "`apply_tracer_hyperdiffusion_tendency!`",
        "`Yₜ_lim`",
        "`hyperdiff` configured",
        "atmosphere",
        "`ρq_tot`, categories, tracers, and `ρ` with `ρq_tot`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "conservative, DSS of the `∇²` cache happens inside `hyperdiffusion_tendency!`",
        :decomposition,
        :collected,
        "operator global-zero test on a real state",
        "`explicit_attribution_tests.jl`",
        4,
        hyperdiffusion,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.horizontal_dynamics"),
        "`horizontal_dynamics_tendency!`",
        "`Yₜ`",
        "always",
        "atmosphere",
        "`ρ`, `ρe_tot`, `uₕ`",
        (:invariant_zero, :not_applicable, :invariant_zero),
        "conservative transport",
        :decomposition,
        :collected,
        "operator global-zero test",
        "`explicit_attribution_tests.jl`",
        4,
        always,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.explicit_vertical_advection"),
        "`explicit_vertical_advection_tendency!`",
        "`Yₜ`",
        "always",
        "atmosphere",
        "`ρ`, `ρe_tot`, tracers, `u₃`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "conservative transport, closed vertical boundaries",
        :decomposition,
        :collected,
        "operator global-zero test",
        "`explicit_attribution_tests.jl`",
        4,
        always,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.hyperdiffusion"),
        "`apply_hyperdiffusion_tendency!`",
        "`Yₜ`",
        "`hyperdiff` configured",
        "atmosphere",
        "`ρe_tot`, `uₕ`, `ρtke`",
        (:not_applicable, :not_applicable, :invariant_zero),
        "conservative",
        :decomposition,
        :collected,
        "operator global-zero test",
        "`explicit_attribution_tests.jl`",
        4,
        hyperdiffusion,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.viscous_sponge"),
        "`viscous_sponge_tendency_*`",
        "`Yₜ`",
        "`viscous_sponge` configured",
        "atmosphere",
        "`uₕ`, `u₃`, `ρe_tot`, tracers, `ρ`",
        (:measured, :measured, :measured),
        "interior numerical source; the `ρ` leg is added only for the `ρq_tot` tracer",
        :decomposition,
        :collected,
        "applied increment per field",
        "`explicit_attribution_tests.jl`",
        4,
        viscous_sponge,
        :viscous_sponge,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.rayleigh_sponge"),
        "`rayleigh_sponge_tendency_uₕ`",
        "`Yₜ`",
        "`rayleigh_sponge` configured",
        "atmosphere",
        "`uₕ`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only, `ρe_tot` prognostic and untouched",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        rayleigh_sponge,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.held_suarez_drag"),
        "`held_suarez_forcing_tendency_uₕ`",
        "`Yₜ`",
        "`HeldSuarezForcing`",
        "atmosphere",
        "`uₕ`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        held_suarez,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.held_suarez_heating"),
        "`held_suarez_forcing_tendency_ρe_tot`",
        "`Yₜ`",
        "`HeldSuarezForcing`",
        "atmosphere",
        "`ρe_tot`",
        (:invariant_zero, :invariant_zero, :measured),
        "idealized external heating, no mass or water term",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        held_suarez,
        :held_suarez,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.prescribed_radiative_heating"),
        "`radiation_tendency!`, `RadiationTRMM_LBA`",
        "`Yₜ`",
        "`RadiationTRMM_LBA`",
        "atmosphere",
        "`ρe_tot`",
        (:invariant_zero, :invariant_zero, :measured),
        "prescribed heating rate with no flux form, so nothing crosses a boundary",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        trmm_lba,
        :radiation,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.scm_coriolis"),
        "`scm_coriolis_tendency_uₕ`",
        "`Yₜ`",
        "single column with SCM Coriolis",
        "atmosphere",
        "`uₕ`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        scm_coriolis,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.subsidence"),
        "`subsidence_tendency!`",
        "`Yₜ`",
        "`LargeScaleSubsidence`",
        "atmosphere",
        "`ρe_tot`, `ρq_tot`, `ρq_lcl`, `ρq_icl`",
        (:invariant_zero, :measured, :measured),
        "writes no `ρ` term, so the mass contribution is invariant zero",
        :decomposition,
        :collected,
        "applied increment plus field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        subsidence,
        :subsidence,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.large_scale_advection"),
        "`large_scale_advection_tendency_*`",
        "`Yₜ`",
        "large-scale advection configured",
        "atmosphere",
        "`ρe_tot`, `ρq_tot`",
        (:invariant_zero, :measured, :measured),
        "writes no `ρ` term",
        :decomposition,
        :collected,
        "applied increment plus field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        large_scale_advection,
        :large_scale_advection,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.external_forcing"),
        "`external_forcing_tendency!`, `apply_Tq_forcing!`",
        "`Yₜ`",
        "external forcing configured",
        "atmosphere",
        "`ρe_tot`, `ρq_tot`, `uₕ`",
        (:invariant_zero, :measured, :measured),
        "writes no `ρ` term",
        :decomposition,
        :collected,
        "applied increment plus field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        external_forcing,
        :external_forcing,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.vertical_diffusion"),
        "`vertical_diffusion_boundary_layer_tendency!`",
        "`Yₜ`",
        "`diff_mode == Explicit()`",
        "atmosphere",
        "`ρe_tot`, tracers, and `ρ` with `ρq_tot`",
        (:measured, :measured, :measured),
        "interior operator with zero flux at top and bottom faces",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        explicit_diffusion,
        :vertical_diffusion,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.smagorinsky_lilly"),
        "`horizontal_/vertical_smagorinsky_lilly_tendency!`",
        "`Yₜ`",
        "SGS diffusion configured",
        "atmosphere",
        "`ρ`, `ρe_tot`, tracers",
        (:measured, :measured, :measured),
        "diffusive; global zero only if the discrete operator has it",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        smagorinsky,
        :smagorinsky_lilly,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.amd"),
        "`horizontal_/vertical_amd_tendency!`",
        "`Yₜ`",
        "AMD configured",
        "atmosphere",
        "`ρ`, `ρe_tot`, tracers",
        (:measured, :measured, :measured),
        "as above",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        amd,
        :amd,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.constant_diffusion"),
        "`horizontal_constant_diffusion_tendency!`",
        "`Yₜ`",
        "constant diffusion configured",
        "atmosphere",
        "tracers",
        (:measured, :measured, :measured),
        "as above",
        :decomposition,
        :collected,
        "applied increment",
        "`explicit_attribution_tests.jl`",
        4,
        constant_diffusion,
        :constant_diffusion,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.microphysics_formation"),
        "`microphysics_tendency!`, 1M and non-equilibrium",
        "`Yₜ`",
        "`NonEquilibriumMicrophysics1M` and explicit microphysics",
        "atmosphere",
        "`ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "formation redistributes categories inside `ρq_tot` and applies no source to `ρq_tot`, `ρ` or `ρe_tot`",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        one_moment_explicit,
        :microphysics,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.tracer_nonnegativity_vapor"),
        "`tracer_nonnegativity_vapor_tendency!`",
        "`Yₜ`",
        "`tracer_nonnegativity_method` vapour tendency",
        "atmosphere",
        "`ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "category-only; writes no parent field",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        vapor_tendency,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.non_orographic_gravity_wave"),
        "`non_orographic_gravity_wave_apply_tendency!`",
        "`Yₜ`",
        "configured",
        "atmosphere",
        "`uₕ`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        nogw,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.orographic_gravity_wave"),
        "`orographic_gravity_wave_apply_tendency!`",
        "`Yₜ`",
        "configured",
        "atmosphere",
        "`uₕ`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        ogw,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.zero_velocity"),
        "`zero_velocity_tendency!`",
        "`Yₜ`",
        "advection tests",
        "atmosphere",
        "`uₕ`, `u₃`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`explicit_attribution_tests.jl`",
        4,
        advection_test,
    ),
    CoverageRow(
        :explicit,
        Symbol("expl.out_of_scope"),
        "`edmfx_*`, `pressure_work_tendency!`, `chemistry_tendency!`",
        "`Yₜ`",
        "out-of-scope configurations",
        "—",
        "—",
        (:not_applicable, :not_applicable, :not_applicable),
        "excluded by the contract's scope",
        :decomposition,
        :none,
        "configuration refused at setup",
        "`registry_tests.jl`",
        3,
        out_of_scope,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.vertical_advection"),
        "`implicit_vertical_advection_tendency!`",
        "`T_imp!`",
        "always",
        "atmosphere",
        "`ρ`, `ρe_tot`, tracers, `u₃`",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "conservative transport with closed vertical boundaries; precipitation leaves through a different operator",
        :decomposition,
        :collected,
        "operator global-zero test plus accepted implicit weight",
        "`implicit_attribution_tests.jl`",
        5,
        always,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.water_fallout"),
        "`vertical_advection_of_water_tendency!`",
        "`T_imp!`",
        "`NonEquilibriumMicrophysics1M`",
        "atmosphere",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "`ᶜprecipdivᵥ` of the category flux with free outflow at the lower boundary",
        :transfer,
        :none,
        "applied increment with accepted implicit weight",
        "`transfer_tests.jl`",
        6,
        one_moment,
        :precipitation,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.microphysics_removal_0m"),
        "`microphysics_tendency!`, 0-moment",
        "`T_imp!`",
        "`EquilibriumMicrophysics0M` and implicit microphysics",
        "atmosphere",
        "`ρq_tot`, `ρ`, `ρe_tot`",
        (:measured, :measured, :measured),
        "removal straight out of the column, no receiving reservoir",
        :transfer,
        :none,
        "applied increment with accepted implicit weight",
        "`transfer_tests.jl`",
        6,
        zero_moment_implicit,
        :microphysics,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.microphysics_formation"),
        "`microphysics_tendency!`, 1M",
        "`T_imp!`",
        "`NonEquilibriumMicrophysics1M` and implicit microphysics",
        "atmosphere",
        "categories",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "redistributes inside `ρq_tot`",
        :decomposition,
        :collected,
        "field-write inventory",
        "`implicit_attribution_tests.jl`",
        5,
        one_moment_implicit,
        :microphysics,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.vertical_diffusion"),
        "`vertical_diffusion_boundary_layer_tendency!`",
        "`T_imp!`",
        "`diff_mode == Implicit()`",
        "atmosphere",
        "`ρe_tot`, tracers, and `ρ` with `ρq_tot`",
        (:measured, :measured, :measured),
        "interior operator, zero flux at top and bottom faces",
        :decomposition,
        :collected,
        "applied increment with accepted implicit weight",
        "`implicit_attribution_tests.jl`",
        5,
        implicit_diffusion,
        :vertical_diffusion,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.solve_defect"),
        "Newton stage residual",
        "`T_imp!`",
        "implicit configurations",
        "atmosphere",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "leading order at `max_iters = 1`; sign and accepted weight verified",
        :decomposition,
        :collected,
        "independent projection of the algebraic residual",
        "`implicit_attribution_tests.jl`",
        5,
        implicit_solve,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.post_implicit_correction"),
        "`correct_implicit_advection_tendency!` through `T_post_imp!`",
        "`T_imp!`",
        "`energy_q_tot_upwinding != Val(:none)`",
        "atmosphere",
        "`ρe_tot`, `ρq_tot`",
        (:invariant_zero, :measured, :measured),
        "writes no `ρ` term; folded into the effective implicit increment by the stepper, so it is booked from the correction the stepper applied, with weight `dt · b_imp[i]`",
        :decomposition,
        :collected,
        "the correction tendency read at the hook, weighted; one booking only",
        "`implicit_attribution_tests.jl`",
        5,
        post_implicit_correction,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.folded_dss"),
        "`dss!` on the Newton-solved stage",
        "`T_imp!`",
        "spectral element with an implicit solve",
        "atmosphere",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "the stepper differences the stage after this DSS, so its change is inside the stored implicit tendency and enters the accepted update with weight `b_imp[i]/γ`",
        :decomposition,
        :collected,
        "before/after pair on the solved stage, weighted",
        "`implicit_attribution_tests.jl`",
        5,
        folded_dss,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.folded_constraint"),
        "`constrain_state!` on the Newton-solved stage",
        "`T_imp!`",
        "`update_constrain_state_every` is `stage` or `dss`, with an implicit solve",
        "atmosphere",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "as `impl.folded_dss`; skipped at the last stage of a first-same-as-last tableau, where the end-of-step firing is the final map instead",
        :decomposition,
        :collected,
        "before/after pair on the solved stage, weighted",
        "`implicit_attribution_tests.jl`",
        5,
        folded_constraint,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.zero_velocity"),
        "`zero_velocity_tendency!`",
        "`T_imp!`",
        "advection tests",
        "atmosphere",
        "momentum",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "momentum only",
        :decomposition,
        :collected,
        "field-write inventory",
        "`implicit_attribution_tests.jl`",
        5,
        advection_test,
    ),
    CoverageRow(
        :implicit,
        Symbol("impl.out_of_scope"),
        "`edmfx_*`, `sgs_*`, `pressure_work_tendency!`",
        "`T_imp!`",
        "out-of-scope configurations",
        "—",
        "—",
        (:not_applicable, :not_applicable, :not_applicable),
        "excluded by the contract's scope",
        :decomposition,
        :none,
        "configuration refused at setup",
        "`registry_tests.jl`",
        3,
        out_of_scope,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.quasimonotone_limiter"),
        "`limiters_func!`, SEM quasimonotone limiter",
        "`lim!`",
        "limiter configured",
        "atmosphere",
        "`ρq_tot`, categories, tracers",
        (:measured, :measured, :measured),
        "numerical correction, not a physical tendency",
        :final_map,
        :collected,
        "ordered before/after pair on the accepted state",
        "`journal_tests.jl`",
        7,
        quasimonotone_limiter,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.rescale_water_tags"),
        "`limiters_func!`, `rescale_water_tags!`",
        "`lim!`",
        "water tags configured",
        "atmosphere",
        "tag fields only",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "tag-only, writes no parent field",
        :final_map,
        :collected,
        "field-write inventory",
        "`journal_tests.jl`",
        7,
        water_tags,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.mass_energy_consistency"),
        "`limiters_func!`, `enforce_mass_energy_consistency!`",
        "`lim!`",
        "moist",
        "atmosphere",
        "`ρ`, `ρe_tot`",
        (:measured, :invariant_zero, :measured),
        "moves `ρ` by `Δρq_tot` and `ρe_tot` by `Δρq_tot·(uᵥ(T)+Φ)`",
        :final_map,
        :collected,
        "ordered before/after pair",
        "`journal_tests.jl`",
        7,
        moist,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.vertical_mass_borrowing"),
        "`limiters_func!`, vertical mass borrowing limiter",
        "`lim!`",
        "configured",
        "atmosphere",
        "`ρq_tot`, categories",
        (:measured, :measured, :measured),
        "numerical correction",
        :final_map,
        :collected,
        "ordered before/after pair",
        "`journal_tests.jl`",
        7,
        vertical_water_borrowing,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.dss"),
        "`dss!`",
        "`dss!`",
        "spectral element",
        "atmosphere",
        "`ρ`, `ρq_tot`, `ρe_tot`",
        (:measured, :measured, :measured),
        "conservative in exact arithmetic on a closed sphere, so the amount is expected at reduction level and larger is a finding",
        :final_map,
        :collected,
        "ordered before/after pair, compared against the reduction scale",
        "`journal_tests.jl`",
        7,
        dss,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.prescribe_flow"),
        "`constrain_state!`, `prescribe_flow!`",
        "`constrain_state!`",
        "`prescribed_flow`",
        "atmosphere",
        "`ρ`, `ρe_tot`, momentum",
        (:not_applicable, :not_applicable, :not_applicable),
        "prescribed overwrite, out of scope, never a physical tendency",
        :final_map,
        :none,
        "configuration refused at setup",
        "`registry_tests.jl`",
        7,
        prescribed_flow,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.tracer_nonneg_element_categories"),
        "`constrain_state!`, `tracer_nonnegativity_constraint!` element variant",
        "`constrain_state!`",
        "`constrain_qtot = false`",
        "atmosphere",
        "categories",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "the loop skips `ρq_tot`, so no parent field is written",
        :final_map,
        :collected,
        "field-write inventory",
        "`journal_tests.jl`",
        7,
        element_constraint_categories,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.tracer_nonneg_element_qtot"),
        "`constrain_state!`, `tracer_nonnegativity_constraint!` element variant",
        "`constrain_state!`",
        "`constrain_qtot = true`",
        "atmosphere",
        "`ρq_tot`, `ρ`, `ρe_tot`",
        (:measured, :measured, :measured),
        "clips `ρq_tot` and hands the increment to `enforce_mass_energy_consistency!`",
        :final_map,
        :collected,
        "ordered before/after pair",
        "`journal_tests.jl`",
        7,
        element_constraint_qtot,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.tracer_nonneg_vapor"),
        "`constrain_state!`, `tracer_nonnegativity_constraint!` vapour variant",
        "`constrain_state!`",
        "moist",
        "atmosphere",
        "categories, and `ρq_tot` when `constrain_qtot = true`",
        (:invariant_zero, :measured, :invariant_zero),
        "at `constrain_qtot = true` it clips `ρq_tot` without calling `enforce_mass_energy_consistency!`, so water moves while stored energy does not",
        :final_map,
        :collected,
        "ordered before/after pair plus a physical-inconsistency note",
        "`journal_tests.jl`",
        7,
        vapor_constraint,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.physical_constraints"),
        "`constrain_state!`, `enforce_physical_constraints!` non-EDMF branch",
        "`constrain_state!`",
        "`NonEquilibriumMicrophysics1M`",
        "atmosphere",
        "categories",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "clamps and rescales the condensate fields, reads `ρq_tot` and writes none of `ρ`, `ρq_tot`, `ρe_tot`",
        :final_map,
        :collected,
        "field-write inventory",
        "`journal_tests.jl`",
        7,
        one_moment,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.repair_water_tag_partition"),
        "`constrain_state!`, `repair_water_tag_partition!`",
        "`constrain_state!`",
        "water tags configured",
        "atmosphere",
        "tag fields only",
        (:invariant_zero, :invariant_zero, :invariant_zero),
        "tag-only, sum preserved by construction",
        :final_map,
        :collected,
        "field-write inventory",
        "`journal_tests.jl`",
        7,
        water_tags,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.restart_transition"),
        "`handle_restart`",
        "initialization",
        "restart",
        "atmosphere, slab",
        "`ρ`, `ρq_tot`, `ρe_tot`, `sfc.*`",
        (:measured, :measured, :measured),
        "a zero-duration transition of its own, never charged to the next step",
        :final_map,
        :none,
        "endpoint pair across the restart boundary",
        "`restart_ledger_tests.jl`",
        7,
        restart,
    ),
    CoverageRow(
        :final_maps,
        Symbol("map.initial_state"),
        "`Setups.initial_state`, `overwrite_initial_state!`, `overwrite_from_file!`",
        "initialization",
        "initialization",
        "atmosphere, slab",
        "all",
        (:not_applicable, :not_applicable, :not_applicable),
        "sets `B⁰`, outside every transaction",
        :final_map,
        :none,
        "first endpoint recorded as the initial one",
        "`restart_ledger_tests.jl`",
        7,
        always,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.surface_turbulent_flux"),
        "`coupled` with a slab, `exterior` otherwise",
        "`surface_flux_tendency!`, and `surface_temp_tendency!` for a slab",
        "unmodeled surface store, when no slab is configured",
        "unless `disable_surface_flux_tendency`",
        "atmosphere, and slab when configured",
        "`ρe_tot`, `ρq_tot`, `ρ`, `uₕ`, `sfc.T`, `sfc.water`",
        (:measured, :measured, :measured),
        "`Yₜ.c.ρ -= btt` is the mass leg; boundary crossing in the atmosphere-only view",
        :transfer,
        :none,
        "every declared leg measured separately",
        "`transfer_tests.jl`",
        6,
        surface_flux,
        :surface_flux,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.radiation_toa"),
        "`exterior`",
        "`radiation_tendency!` at the model top",
        "space above the model top",
        "radiation in flux form: RRTMGP, DYCOMS or ISDAC",
        "atmosphere",
        "`ρe_tot`",
        (:invariant_zero, :invariant_zero, :measured),
        "boundary crossing with no receiving reservoir",
        :transfer,
        :none,
        "atmospheric leg, cross-checked against the reported TOA flux",
        "`transfer_tests.jl`",
        6,
        flux_form_radiation,
        :radiation,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.radiation_surface"),
        "`coupled` with a slab, `exterior` otherwise",
        "`radiation_tendency!` at the surface, and `surface_temp_tendency!` for a slab",
        "unmodeled surface store, when no slab is configured",
        "radiation in flux form: RRTMGP, DYCOMS or ISDAC",
        "atmosphere, and slab when configured",
        "`ρe_tot`, `sfc.T`",
        (:invariant_zero, :invariant_zero, :measured),
        "separate from the TOA leg, because only one of them has a reservoir on the far side",
        :transfer,
        :none,
        "every declared leg measured separately",
        "`transfer_tests.jl`",
        6,
        flux_form_radiation,
        :radiation,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.precipitation_0m"),
        "`exterior`",
        "`microphysics_tendency!`, 0-moment",
        "unmodeled surface store",
        "`EquilibriumMicrophysics0M`",
        "atmosphere",
        "`ρq_tot`, `ρ`, `ρe_tot`",
        (:measured, :measured, :measured),
        "removal with no receiving reservoir, so no cancellation is expected in any view",
        :transfer,
        :none,
        "atmospheric leg only, exterior counterparty declared",
        "`transfer_tests.jl`",
        6,
        zero_moment,
        :microphysics,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.precipitation_1m"),
        "`coupled` with a slab, `exterior` otherwise",
        "`vertical_advection_of_water_tendency!`, and `surface_precipitation_tendency!` for a slab",
        "unmodeled surface store, when no slab is configured",
        "`NonEquilibriumMicrophysics1M`",
        "atmosphere, and slab when configured",
        "`ρq_tot`, `ρ`, `ρe_tot`, `sfc.water`, `sfc.T`",
        (:measured, :measured, :measured),
        "two quadratures of one physical flux, so the pair is measured and any mismatch kept",
        :transfer,
        :none,
        "every declared leg measured separately",
        "`transfer_tests.jl`",
        6,
        one_moment,
        :precipitation,
    ),
    CoverageRow(
        :transfers,
        Symbol("xfer.slab_qflux"),
        "`exterior`",
        "`surface_temp_tendency!` Q-flux term",
        "prescribed ocean heat transport",
        "`SlabOceanTemperature` with a Q-flux",
        "slab",
        "`sfc.T`",
        (:not_applicable, :not_applicable, :measured),
        "prescribed exterior source into the slab",
        :transfer,
        :none,
        "slab leg only, exterior counterparty declared",
        "`transfer_tests.jl`",
        6,
        slab_qflux,
        :surface_temperature,
    ),
]

"""
    NON_AUTHORITATIVE_PATHS

The paths `coverage.md` lists as never booked, in page order.
"""
const NON_AUTHORITATIVE_PATHS = NonAuthoritativePath[
    NonAuthoritativePath(
        Symbol("cache.precomputed"),
        "`set_precomputed_quantities!`",
        "`cache!`",
        "cache, and the velocity filter on `Y.f.u₃` at the two boundary faces, which is momentum only",
    ),
    NonAuthoritativePath(
        Symbol("cache.implicit_precomputed"),
        "`set_implicit_precomputed_quantities!`",
        "`cache_imp!`",
        "cache, and the velocity filter on `Y.f.u₃` at the two boundary faces, which is momentum only",
    ),
    NonAuthoritativePath(
        Symbol("cache.implicit_stage_setup"),
        "`initialize_implicit_stage_problem!`",
        "`initialize_imp!`",
        "stage setup",
    ),
    NonAuthoritativePath(
        Symbol("cb.flux_accumulation"),
        "`flux_accumulation!`",
        "discrete callback",
        "mutates `Ref`s in `p` only",
    ),
    NonAuthoritativePath(
        Symbol("cb.external_driven_single_column"),
        "`external_driven_single_column!`",
        "discrete callback",
        "refreshes forcing caches only",
    ),
    NonAuthoritativePath(
        Symbol("cb.rrtmgp_solver"),
        "`rrtmgp_solver_callback!`",
        "discrete callback",
        "fills the radiation cache; the state effect arrives through `radiation_tendency!`",
    ),
    NonAuthoritativePath(
        Symbol("cb.read_only"),
        "`nan_checking_callback`, `checkpoint_callback`, `gc_callback`, diagnostics",
        "discrete callbacks",
        "read-only with respect to `Y`",
    ),
]

# ============================================================================
# Reading the rows
# ============================================================================

"""
    registry_rows(table) -> Vector{CoverageRow}

Return the rows of one table, in page order.
"""
registry_rows(table::Symbol) = filter(r -> r.table === table, COVERAGE_ROWS)

"""
    selected_rows(context) -> Vector{CoverageRow}

Return the rows whose guard holds for `context`, in page order. This is the set
the schema is built from, so it is also the set a run is expected to record.
"""
selected_rows(c::RegistryContext) = filter(r -> r.applies(c), COVERAGE_ROWS)

"""
    REGISTRY_EVENTS

Every applied-update label some row is measured by. A bracket in the tendency
code that passes a label outside this set names a process the registry does
not know, which the adapter refuses when it is metering.
"""
const REGISTRY_EVENTS = Tuple(
    unique(
        vcat(
            [r.event for r in COVERAGE_ROWS if !isnothing(r.event)],
            [:surface_temperature, :surface_precipitation],
        ),
    ),
)

"""
    CHANNEL_LABELS

The `Channel` cell of a row, mapped to the schema label it stands for: an
attribution channel, a final map, or `:initialization` for the rows that set
`B⁰` outside every transaction.
"""
const CHANNEL_LABELS = Dict(
    "`Yₜ`" => :explicit_main,
    "`Yₜ_lim`" => :explicit_limited,
    "`T_imp!`" => :implicit,
    "`lim!`" => :lim!,
    "`dss!`" => :dss!,
    "`constrain_state!`" => :constrain_state!,
    "initialization" => :initialization,
)

"""
    channel_name(row) -> Symbol

Return the schema label of a dispatch row's channel. Errors for a transfer row,
whose channel depends on the configuration; see `transfer_channel`.
"""
function channel_name(row::CoverageRow)
    isnothing(row.channel) &&
        error("Coverage row $(row.id) is a transfer row; use transfer_channel.")
    haskey(CHANNEL_LABELS, row.channel) ||
        error(
            "Coverage row $(row.id) names channel $(row.channel), which the " *
            "registry does not know.",
        )
    return CHANNEL_LABELS[row.channel]
end

"""
    process_name(row) -> Symbol

Return the process a decomposition row records under. It is the part of the
event id after the table prefix, so `expl.viscous_sponge` is `viscous_sponge`.
"""
process_name(row::CoverageRow) = Symbol(last(split(String(row.id), '.'; limit = 2)))

"""
    row_reservoirs(row, context) -> Tuple{Vararg{Symbol}}

Resolve the modeled reservoirs a row writes in this configuration from its
`Reservoirs` cell. The cell's wording is fixed, so an unknown phrase is an error
rather than an empty tuple.
"""
function row_reservoirs(row::CoverageRow, c::RegistryContext)
    text = row.reservoirs
    text == "atmosphere" && return (ATMOSPHERE_ENDPOINT_GROUP,)
    text == "atmosphere, and slab when configured" && return c.slab ?
           (ATMOSPHERE_ENDPOINT_GROUP, SLAB_SURFACE_ENDPOINT_GROUP) :
           (ATMOSPHERE_ENDPOINT_GROUP,)
    text == "atmosphere, slab" &&
        return (ATMOSPHERE_ENDPOINT_GROUP, SLAB_SURFACE_ENDPOINT_GROUP)
    text == "slab" && return (SLAB_SURFACE_ENDPOINT_GROUP,)
    text == "—" && return ()
    return error(
        "Coverage row $(row.id) names reservoirs \"$text\", which the registry " *
        "does not know how to resolve.",
    )
end

"""
    resolve_dispositions(dispositions, context)

Resolve a row's dispositions for this configuration. Water is `:not_applicable`
in a dry model whatever the row says, because the row describes what the path
does where the quantity exists.
"""
function resolve_dispositions(dispositions, c::RegistryContext)
    return ntuple(length(BUDGET_QUANTITIES)) do i
        quantity = BUDGET_QUANTITIES[i]
        quantity === :water && !c.moist && return :not_applicable
        return dispositions[i]
    end
end

# The disposition of a hook that runs several rows: measured if any row is,
# open if any row is, and otherwise provably zero, including when no row
# applies and the hook writes nothing.
function combined_dispositions(rows, c::RegistryContext)
    return ntuple(length(BUDGET_QUANTITIES)) do i
        quantity = BUDGET_QUANTITIES[i]
        quantity === :water && !c.moist && return :not_applicable
        found = [r.dispositions[i] for r in rows]
        :measured in found && return :measured
        :open in found && return :open
        return :invariant_zero
    end
end

# ============================================================================
# Transfer rows
# ============================================================================

"""
    transfer_topology(row, context) -> TransferTopology

Resolve the topology of a transfer row in this configuration from its
`Topology` cell. A row that reads `coupled` with a slab and `exterior`
otherwise is two different expectations, and the configuration picks one.
"""
function transfer_topology(row::CoverageRow, c::RegistryContext)
    text = row.topology
    text == "`exterior`" && return ExteriorCrossing()
    text == "`coupled` with a slab, `exterior` otherwise" &&
        return c.slab ? CoupledTransfer() : ExteriorCrossing()
    return error(
        "Coverage row $(row.id) names topology \"$text\", which the registry " *
        "does not know how to resolve.",
    )
end

"""
    COUNTERPARTIES

The `Exterior counterparty` cell of a transfer row, mapped to the label the
schema records. A label is metadata: nothing numerical is ever created for it.
"""
const COUNTERPARTIES = Dict(
    "unmodeled surface store, when no slab is configured" =>
        :unmodeled_surface_store,
    "unmodeled surface store" => :unmodeled_surface_store,
    "space above the model top" => :space,
    "prescribed ocean heat transport" => :prescribed_ocean_heat_transport,
)

# The counterparty label of a transfer row, so the schema never stores the
# cell's prose. An unknown cell is an error rather than a made-up label.
function transfer_counterparty(row::CoverageRow)
    haskey(COUNTERPARTIES, row.counterparty) ||
        error(
            "Coverage row $(row.id) names counterparty \"$(row.counterparty)\", " *
            "which the registry does not know.",
        )
    return COUNTERPARTIES[row.counterparty]
end

# The rows whose slab leg is a second, independently measured quadrature.
const TWO_SIDED_TRANSFERS = (
    Symbol("xfer.surface_turbulent_flux"),
    Symbol("xfer.radiation_surface"),
    Symbol("xfer.precipitation_1m"),
)

"""
    transfer_legs(row, context) -> Tuple{Vararg{Tuple{Symbol, Symbol}}}

Return the `(reservoir, leg)` pairs a transfer row requires in this
configuration. The atmospheric leg is always `flux`. The slab leg exists when
the row is two-sided and a slab is configured. The Q-flux is a slab-only leg.
"""
function transfer_legs(row::CoverageRow, c::RegistryContext)
    row.id === Symbol("xfer.slab_qflux") &&
        return ((SLAB_SURFACE_ENDPOINT_GROUP, :qflux),)
    legs = ((ATMOSPHERE_ENDPOINT_GROUP, :flux),)
    row.id in TWO_SIDED_TRANSFERS && c.slab &&
        return (legs..., (SLAB_SURFACE_ENDPOINT_GROUP, :flux))
    return legs
end

"""
    transfer_channel(row, context) -> Symbol

Return the accepted channel a transfer event's legs are applied through.
Zero-moment removal follows `microphysics_tendency_timestepping`. One-moment
fallout is on the implicit channel because `vertical_advection_of_water_tendency!`
is called from `implicit_tendency!`. Every other event is explicit.
"""
function transfer_channel(row::CoverageRow, c::RegistryContext)
    row.id === Symbol("xfer.precipitation_0m") &&
        return implicit_microphysics(c) ? :implicit : :explicit_main
    row.id === Symbol("xfer.precipitation_1m") && return :implicit
    return :explicit_main
end

# ============================================================================
# The schema
# ============================================================================

"""
    ROSTER_TABLES

The tables whose `decomposition` rows form a channel's roster.
"""
const ROSTER_TABLES = (:limited, :explicit, :implicit)

"""
    budget_schema(atmos; dss, implicit_solve, restart = false, constraint_cadence = :step)

Build the schema a configuration is expected to produce from the registry.

An out-of-scope configuration is refused first. The rest comes from the rows
the configuration selects. The reservoirs and control volumes come from the
model facts. Each envelope row gives one `ChannelSpec`, with the roster of
decomposition rows that share its channel. Each accepted-state hook gives one
`FinalMapSpec`, with the dispositions of the rows that run in it. Each transfer
row gives one `TransferEventSpec`, with its topology and legs resolved.

The `initialization` rows are not final maps of an ordinary step. They set
`B⁰` outside every transaction, or describe the restart transition, which is
its own transaction; neither is a term a step could record.
"""
function budget_schema(
    atmos;
    dss::Bool,
    implicit_solve::Bool,
    restart::Bool = false,
    constraint_cadence::Symbol = :step,
)
    check_supported(atmos)
    c = RegistryContext(atmos; dss, implicit_solve, restart, constraint_cadence)
    rows = selected_rows(c)

    reservoirs = ReservoirSpec[
        ReservoirSpec(AtmosphereReservoir(), (true, c.moist, true)),
    ]
    control_volumes = ControlVolume[ATMOSPHERE_ONLY]
    if c.slab
        push!(reservoirs, ReservoirSpec(SlabSurfaceReservoir(), (c.moist, c.moist, true)))
        push!(control_volumes, ATMOSPHERE_AND_SURFACE)
    end

    channels = ChannelSpec[]
    for envelope in filter(r -> r.table === :envelopes, rows)
        name = channel_name(envelope)
        channel_reservoirs = row_reservoirs(envelope, c)
        processes = ProcessRowSpec[]
        for row in rows
            row.table in ROSTER_TABLES || continue
            row.level === :decomposition || continue
            channel_name(row) === name || continue
            for reservoir in row_reservoirs(row, c)
                push!(
                    processes,
                    ProcessRowSpec(
                        process_name(row),
                        reservoir;
                        dispositions = resolve_dispositions(row.dispositions, c),
                        event = row.event,
                    ),
                )
            end
        end
        push!(
            channels,
            ChannelSpec(
                name,
                channel_reservoirs;
                dispositions = resolve_dispositions(envelope.dispositions, c),
                processes = Tuple(processes),
            ),
        )
    end

    final_maps = FinalMapSpec[]
    for hook in (:lim!, :dss!, :constrain_state!)
        hook_rows = filter(r -> r.table === :final_maps && channel_name(r) === hook, rows)
        hook_reservoirs = Symbol[]
        for row in hook_rows, reservoir in row_reservoirs(row, c)
            reservoir in hook_reservoirs || push!(hook_reservoirs, reservoir)
        end
        isempty(hook_reservoirs) && push!(hook_reservoirs, ATMOSPHERE_ENDPOINT_GROUP)
        push!(
            final_maps,
            FinalMapSpec(
                hook,
                Tuple(hook_reservoirs);
                dispositions = combined_dispositions(hook_rows, c),
            ),
        )
    end

    transfer_events = TransferEventSpec[]
    for row in filter(r -> r.table === :transfers, rows)
        topology = transfer_topology(row, c)
        push!(
            transfer_events,
            TransferEventSpec(
                row.id,
                topology,
                transfer_channel(row, c),
                transfer_legs(row, c);
                counterparty = topology isa ExteriorCrossing ?
                               transfer_counterparty(row) : nothing,
                dispositions = resolve_dispositions(row.dispositions, c),
            ),
        )
    end

    return BudgetSchema(;
        reservoirs,
        control_volumes,
        channels,
        final_maps,
        transfer_events,
    )
end

# ============================================================================
# The documentation half
# ============================================================================

"""
    DISPOSITION_CELLS

The registry's disposition vocabulary as the table spells it.
"""
const DISPOSITION_CELLS = Dict(
    :measured => "measured",
    :invariant_zero => "zero",
    :not_applicable => "n/a",
    :open => "open",
)

# The `Disposition M·W·E` cell of a row, so the page and the registry share one
# spelling of the three dispositions.
disposition_cell(dispositions) =
    join((DISPOSITION_CELLS[d] for d in dispositions), " · ")

# The `Level` cell of a row: the symbol with its underscore spelled as a space.
level_cell(level::Symbol) = replace(String(level), "_" => " ")

"""
    table_cells(row) -> Vector{String}

Return the row's cells in the column order of its table, as the page prints them.
"""
function table_cells(row::CoverageRow)
    id = "`$(row.id)`"
    common = [
        row.guard,
        row.reservoirs,
        row.parent_fields,
        disposition_cell(row.dispositions),
        row.proof,
        level_cell(row.level),
        String(row.state),
        row.evidence,
        row.test,
        string(row.step),
    ]
    if row.table === :transfers
        return [id, row.topology, row.modeled_legs, row.counterparty, common...]
    end
    return [id, row.dispatch, common[1], row.channel, common[2:end]...]
end

# The four cells of a non-authoritative path, in the order its table prints them.
table_cells(path::NonAuthoritativePath) =
    ["`$(path.id)`", path.dispatch, path.hook, path.why]

"""
    registry_table_cells(table) -> Vector{Vector{String}}

Return every row of one table as its cells, in page order. `:non_authoritative`
is accepted alongside the `REGISTRY_TABLES`. This is what the documentation test
compares the page against, cell by cell.
"""
function registry_table_cells(table::Symbol)
    table === :non_authoritative &&
        return [table_cells(path) for path in NON_AUTHORITATIVE_PATHS]
    return [table_cells(row) for row in registry_rows(table)]
end
