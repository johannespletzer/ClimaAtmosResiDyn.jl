using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS
import ClimaCore: Fields

# The timestepper adapter, on a real simulation.
#
# A dry single column is the cheapest configuration that exercises every hook:
# no DSS, no limiter and no constraint are configured, so the three final maps
# are provably no-ops and the accepted update is exactly the sum of the explicit
# and implicit channels. That is what lets the explicit envelopes the adapter
# records be checked against the state change the integrator actually applied,
# rather than against the formula they came from. Everything else here is the
# contract's own rules: the ledger changes nothing, a step costs one collective,
# the timestepper is pinned, and the stage construction the adapter assumes is
# the one the stepper runs.

const FT = Float64
const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP

newton() = CTS.NewtonsMethod(;
    max_iters = 1,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

function column_simulation(;
    parent_budget_mode = "off",
    update_constrain_state_every = "step",
    ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton()),
    kwargs...,
)
    return CA.AtmosSimulation{FT}(;
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end = 600,
        job_id = "parent_budget_envelopes",
        output_dir = mktempdir(),
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        parent_budget_mode,
        update_constrain_state_every,
        ode_config,
        kwargs...,
    )
end

adapter_of(simulation) = simulation.integrator.p.parent_budget

step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)

# The parent reconciliation of one quantity in the atmosphere-only view.
function parent_row(adapter, quantity)
    commit = PB.latest_commit(adapter)
    return only(
        filter(
            r -> r.quantity === quantity && r.control_volume === :atmosphere_only,
            commit.parent,
        ),
    )
end

# The sum of the two explicit envelopes the adapter recorded for one quantity,
# read from the legs the adapter keeps after the commit clears the transaction.
function explicit_envelopes(adapter, quantity)
    total = 0.0
    for leg in adapter.last_legs
        leg.level isa PB.ChannelEnvelope || continue
        leg.channel in (:explicit_main, :explicit_limited) || continue
        total += PB.budget_component(leg, quantity).amount
    end
    return total
end

# The implicit channel's accepted energy or mass increment, measured here in
# the test from the stage tendencies the stepper cache holds, independently of
# the adapter's own reading of the same cache.
function implicit_increment(integrator, quantity)
    cache = integrator.cache
    indices, weights = PB.stage_weights(
        cache.tableau.b_imp.coeffs,
        float(integrator.dt),
    )
    name = PB.atmosphere_field_name(quantity)
    fields = map(i -> getproperty(cache.T_imp[i].c, name), indices)
    return PB.local_volume_integral(PB.weighted_stage_sum(weights, fields))
end

@testset "Parent-budget envelopes" begin
    @testset "Refused configurations fail at setup" begin
        @test_throws ErrorException column_simulation(; parent_budget_mode = "bogus")
        noop = CTS.DiscreteCallback((u, t, integrator) -> false, integrator -> nothing)
        @test_throws ErrorException column_simulation(;
            parent_budget_mode = "summary",
            callbacks = (noop,),
        )
    end

    off = column_simulation()
    on = column_simulation(; parent_budget_mode = "summary")
    adapter = adapter_of(on)

    @testset "Off is the run without the feature" begin
        @test isnothing(adapter_of(off))
        @test adapter isa PB.ParentBudgetAdapter
        @test adapter.mode isa PB.SummaryMode
    end

    @testset "The timestepper is pinned" begin
        record = adapter.timestepper
        @test record.package_version == pkgversion(CTS)
        @test record.algorithm === :ARS343
        @test record.stages == 4
        @test !record.fsal
        γ = 0.4358665215084590
        @test record.b_exp ≈
              [0.0, -3 / 2 * γ^2 + 4 * γ - 1 / 4, 3 / 2 * γ^2 - 5 * γ + 5 / 4, γ]
        @test record.b_imp == record.b_exp
        @test iszero(record.b_exp[1])
    end

    @testset "One collective per accepted step" begin
        # Initialisation measured the opening endpoint once.
        @test adapter.reductions == 1
        before = PB.REDUCTION_COUNT[]
        step!(on, 3)
        @test PB.REDUCTION_COUNT[] - before == 3
        @test adapter.reductions == 4
        @test adapter.steps_committed == 3
    end

    @testset "The trajectory is bitwise unchanged with the ledger on" begin
        step!(off, 3)
        Y_off, Y_on = off.integrator.u, on.integrator.u
        @test parent(Y_off.c) == parent(Y_on.c)
        @test parent(Y_off.f) == parent(Y_on.f)
        @test off.integrator.t == on.integrator.t
    end

    @testset "The explicit envelopes reproduce the applied update" begin
        # After the step just taken, the stepper cache still holds this step's
        # stage tendencies, so the implicit term can be measured here, beside
        # the adapter's explicit envelopes, and the identity checked on the
        # actual endpoint change. Nothing else moved the state: no DSS, no
        # limiter and no constraint is configured, and the three final maps are
        # booked as the invariant zeros the registry proves.
        for quantity in (:mass, :energy)
            r = parent_row(adapter, quantity)
            implicit = implicit_increment(on.integrator, quantity)
            explicit = explicit_envelopes(adapter, quantity)
            @test r.envelopes ≈ explicit + implicit
            residual = r.endpoint_change - explicit - implicit
            scale = abs(r.endpoint_change) + abs(r.envelopes) + abs(implicit)
            background =
                2 * abs(
                    PB.endpoint_total(
                        adapter.ledger.last_closing,
                        quantity,
                        PB.ATMOSPHERE_ONLY,
                    ).total,
                )
            @test abs(residual) <= 64 * eps(FT) * (background + scale)
            @test isfinite(r.envelopes)
        end
        # The energy identity is a real test: the explicit channel carries the
        # surface flux, so its envelope is far above the arithmetic level.
        energy = parent_row(adapter, :energy)
        @test abs(energy.envelopes) > 1e3 * eps(FT) * abs(energy.endpoint_change)
        @test abs(energy.endpoint_change - energy.envelopes) < 1e-6 * abs(energy.envelopes)
        # The final maps are provably zero here, and are booked as such.
        @test energy.final_maps == 0
    end

    @testset "The parent claims pass with the calibrated tolerance" begin
        @test adapter.tolerance_source === :calibration_table
        for quantity in (:mass, :energy)
            r = parent_row(adapter, quantity)
            @test r.status === :pass
            @test isempty(r.missing_expectations)
            @test isempty(r.blocked_by)
        end
        @test parent_row(adapter, :water).status === :not_applicable
        @test PB.parent_status(adapter, :energy, :atmosphere_only) === :pass
        # Summary mode records no measured row and no transfer leg, so the
        # main channel's attribution and the surface flux stay blocked by name.
        commit = PB.latest_commit(adapter)
        @test all(r -> r.status in (:pass, :blocked, :not_applicable), commit.attribution)
        @test all(r -> r.status in (:blocked, :not_applicable), commit.transfer)
    end

    @testset "Audit mode keeps every commit" begin
        audit = column_simulation(; parent_budget_mode = "audit")
        step!(audit, 2)
        @test length(adapter_of(audit).commits) == 2
        @test isempty(adapter.commits)
    end
end

# ----------------------------------------------------------------------------
# The trace of stage construction and hook order.
#
# The adapter reads the accepted envelopes from the stage tendencies the stepper
# cache holds, and it identifies the final `lim!`, `dss!` and `constrain_state!`
# calls by their position in the step, because the last stage and the final
# assembly share the same time. Both rest on the order the stepper runs its
# hooks in. This test records that order on a real simulation, so a change in
# ClimaTimeSteppers fails here instead of silently changing the meaning of a
# leg. The expectation is built from the tableau, so it holds for every
# unconstrained IMEX-ARK method whose first stage is explicit.
# ----------------------------------------------------------------------------

function traced_integrator(simulation)
    integrator = simulation.integrator
    f = integrator.sol.prob.f
    trace = Symbol[]
    record(name, g) = (args...) -> (push!(trace, name); g(args...))
    T_imp! = CTS.ODEFunction(
        record(:T_imp!, f.T_imp!.f);
        jac_prototype = f.T_imp!.jac_prototype,
        Wfact = record(:Wfact, f.T_imp!.Wfact),
    )
    traced = CTS.ClimaODEFunction(;
        T_exp_T_lim! = record(:T_exp_T_lim!, f.T_exp_T_lim!),
        T_imp!,
        T_post_imp! = isnothing(f.T_post_imp!) ? nothing :
                      record(:T_post_imp!, f.T_post_imp!),
        lim! = record(:lim!, f.lim!),
        dss! = record(:dss!, f.dss!),
        constrain_state! = record(:constrain_state!, f.constrain_state!),
        initialize_imp! = record(:initialize_imp!, f.initialize_imp!),
        cache! = record(:cache!, f.cache!),
        cache_imp! = record(:cache_imp!, f.cache_imp!),
        update_cache = f.update_cache,
        update_constrain_state = f.update_constrain_state,
    )
    problem = CTS.ODEProblem(traced, integrator.u, integrator.sol.prob.tspan, integrator.p)
    return CTS.init(problem, integrator.alg; dt = integrator._dt, callback = nothing), trace
end

# The hook order one accepted step should produce, from the tableau and the
# constraint cadence, for a method whose first stage is explicit and every later
# stage is implicit, with the cache refreshed at the end of the step. A
# first-same-as-last tableau skips the end-of-stage hooks of its last stage,
# because the step's own end-of-step firing covers the same state.
function expected_trace(tableau, cadence, fsal)
    a_exp, b_exp, a_imp = tableau.a_exp.coeffs, tableau.b_exp.coeffs, tableau.a_imp.coeffs
    s = length(b_exp)
    exp_terms(i) = any(!iszero, a_exp[:, i]) || !iszero(b_exp[i])
    @assert iszero(a_imp[1, 1])
    @assert all(i -> !iszero(a_imp[i, i]), 2:s)
    every_dss = cadence == "dss" ? [:constrain_state!] : Symbol[]
    end_of_stage = cadence == "step" ? Symbol[] : [:constrain_state!]
    expected = Symbol[]
    exp_terms(1) && push!(expected, :T_exp_T_lim!)
    for i in 2:s
        append!(
            expected,
            [:lim!, :dss!, every_dss..., :initialize_imp!, :dss!, every_dss...],
        )
        append!(expected, [:cache_imp!, :T_imp!, :Wfact])
        append!(expected, [:cache_imp!, :T_post_imp!, :dss!])
        i == s && fsal || append!(expected, [end_of_stage..., :cache_imp!])
        exp_terms(i) && push!(expected, :T_exp_T_lim!)
    end
    append!(expected, [:lim!, :dss!, :constrain_state!, :cache!])
    return expected
end

@testset "Parent-budget stage and hook trace" begin
    cases = (
        ("ARS343", "step", CTS.IMEXAlgorithm(CTS.ARS343(), newton())),
        ("ARS343", "stage", CTS.IMEXAlgorithm(CTS.ARS343(), newton())),
        ("ARS343", "dss", CTS.IMEXAlgorithm(CTS.ARS343(), newton())),
        ("ARS222", "step", CTS.IMEXAlgorithm(CTS.ARS222(), newton())),
    )
    for (name, cadence, ode_config) in cases
        @testset "$name with constraints every $cadence" begin
            simulation =
                column_simulation(; update_constrain_state_every = cadence, ode_config)
            integrator, trace = traced_integrator(simulation)
            # Initialisation refreshes the cache once; the step starts clean.
            @test trace == [:cache!]
            empty!(trace)
            CTS.step!(integrator)
            fsal = CTS.is_fsal(integrator.alg)
            @test fsal == (name == "ARS222")
            expected = expected_trace(integrator.cache.tableau, cadence, fsal)
            @test trace == expected
            # One residual evaluation per implicit stage: the defect after the
            # single Newton update is never evaluated, which is why stack step 5
            # has to measure it separately.
            stages = length(integrator.cache.tableau.b_exp.coeffs)
            @test count(==(:T_imp!), trace) == stages - 1
        end
    end
end
