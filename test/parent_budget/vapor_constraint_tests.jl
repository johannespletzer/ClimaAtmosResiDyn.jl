using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS
import ClimaCore: Fields

# The vapour variant of `tracer_nonnegativity_constraint!` and its registry row.
#
# The variant sets a negative condensate to zero where `ρq_tot > 0`. The
# implied vapour gives up the mass, so `ρq_tot` stays as it is. At
# `constrain_qtot = true` the loop also visits `ρq_tot`. There it computes
# `ifelse(ρq_tot > 0, max(0, ρq_tot), ρq_tot)`, which is `ρq_tot` bit for bit.
# So the variant writes none of `ρ`, `ρq_tot` and `ρe_tot`, for either value of
# `constrain_qtot`, and its row `map.tracer_nonneg_vapor` is zero for all
# three quantities.
#
# Three checks. The constraint itself, on chosen values. The schema a
# vapour-constraint configuration builds. And an audit run, where the adapter
# requires each final map that the registry declares zero to have moved by
# exactly zero.

const FT = Float64
const CATEGORIES = (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP

vapor_method(constrain_qtot) = CA.TracerNonnegativityVaporConstraint{constrain_qtot}()
method_name(constrain_qtot) = constrain_qtot ? "vapor_constraint_qtot" : "vapor_constraint"

# The moist column of the calibration protocol, with one-moment microphysics so
# that the condensate fields exist, and the vapour constraint.
function vapor_simulation(constrain_qtot)
    config = merge(
        PB.calibration_configuration(),
        Dict{String, Any}(
            "output_dir" => mktempdir(),
            "microphysics_model" => "1M",
            "tracer_nonnegativity_method" => method_name(constrain_qtot),
            "parent_budget_mode" => "audit",
        ),
    )
    job_id = "parent_budget_vapor_constraint_$(constrain_qtot)"
    return CA.get_simulation(CA.AtmosConfig(config; job_id))
end

adapter_of(simulation) = simulation.integrator.p.parent_budget
step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)

# Bitwise equality, element by element. `==` would let `-0.0` pass for `0.0`.
same_bits(a, b) = all(map(===, a, b))
values_of(field) = copy(vec(parent(field)))

# Overwrite a scalar field with values, one per point.
set_values!(field, values) = (vec(parent(field)) .= values; field)

# The column's points in three bands: `ρq_tot` positive, zero and negative.
# Each band holds both signs of every condensate.
function chosen_state!(Y)
    n = length(vec(parent(Y.c.ρ)))
    band(i) = 3 * (i - 1) ÷ n  # 0, 1 or 2
    ρ = values_of(Y.c.ρ)
    q_tot = [(1e-3, 0.0, -1e-6)[band(i) + 1] for i in 1:n]
    set_values!(Y.c.ρq_tot, ρ .* q_tot)
    for (k, name) in enumerate(CATEGORIES)
        sign_of(i) = isodd(i + k) ? -1 : 1
        set_values!(getproperty(Y.c, name), [sign_of(i) * 1e-7 * k * ρ[i] for i in 1:n])
    end
    return Y
end

# The constrain_state! final-map leg the adapter recorded for the last step.
final_leg(adapter, hook) =
    only(filter(l -> l.event === Symbol("map.", hook), adapter.last_legs))

# Seed the state and read the opening endpoint again. The adapter read `B⁰` when
# the integrator was built, from the state before the seed. The cache is
# recomputed so that the first stage sees the seeded state too.
function reseed!(simulation, seed!)
    integrator = simulation.integrator
    seed!(integrator.u)
    CA.set_precomputed_quantities!(integrator.u, integrator.p, integrator.t)
    adapter = adapter_of(simulation)
    PB.abort_transaction!(adapter.journal)
    adapter.journal.initial = nothing
    PB.initialize_parent_budget!(adapter, integrator)
    return simulation
end

# A seed for the run. Every condensate is slightly negative in the lower half,
# where `ρq_tot` is positive, so the clip has work to do. `ρq_tot` is negative
# in the top quarter. A pass that clipped `ρq_tot` would change it there.
# Transport fills a single negative cell within a few steps, so the seed spans
# several cells.
function run_seed!(Y)
    ρ = values_of(Y.c.ρ)
    n = length(ρ)
    for name in CATEGORIES
        values = values_of(getproperty(Y.c, name))
        values[1:(n ÷ 2)] .= -1e-9 .* ρ[1:(n ÷ 2)]
        set_values!(getproperty(Y.c, name), values)
    end
    top = (n - n ÷ 4 + 1):n
    q = values_of(Y.c.ρq_tot)
    q[top] .= -1e-4 .* ρ[top]
    set_values!(Y.c.ρq_tot, q)
    return Y
end

@testset "Parent-budget vapour constraint" begin
    simulations = Dict(q => vapor_simulation(q) for q in (false, true))

    @testset "The constraint writes no parent field" begin
        simulation = simulations[false]
        (; p, t) = simulation.integrator
        for constrain_qtot in (false, true)
            @testset "constrain_qtot = $constrain_qtot" begin
                Y = chosen_state!(copy(simulation.integrator.u))
                ρq_tot = values_of(Y.c.ρq_tot)
                @test any(>(0), ρq_tot) && any(iszero, ρq_tot) && any(<(0), ρq_tot)
                before = Dict(
                    name => values_of(getproperty(Y.c, name)) for
                    name in (:ρ, :ρq_tot, :ρe_tot, CATEGORIES...)
                )
                CA.tracer_nonnegativity_constraint!(Y, p, t, vapor_method(constrain_qtot))
                for name in (:ρ, :ρq_tot, :ρe_tot)
                    @test same_bits(values_of(getproperty(Y.c, name)), before[name])
                end
                for name in CATEGORIES
                    old = before[name]
                    @test any(<(0), old[ρq_tot .> 0])
                    expected = [q > 0 ? max(0, x) : x for (q, x) in zip(ρq_tot, old)]
                    @test same_bits(values_of(getproperty(Y.c, name)), expected)
                end
            end
        end
    end

    @testset "The schema declares the constrain_state! hook zero" begin
        for constrain_qtot in (false, true)
            @testset "constrain_qtot = $constrain_qtot" begin
                atmos = simulations[constrain_qtot].integrator.p.atmos
                c = PB.RegistryContext(atmos; dss = false, implicit_solve = true)
                rows = filter(
                    r ->
                        r.table === :final_maps &&
                        PB.channel_name(r) === :constrain_state!,
                    PB.selected_rows(c),
                )
                ids = Set(String(r.id) for r in rows)
                @test "map.tracer_nonneg_vapor" in ids
                row = only(filter(r -> r.id === Symbol("map.tracer_nonneg_vapor"), rows))
                @test PB.resolve_dispositions(row.dispositions, c) ===
                      (:invariant_zero, :invariant_zero, :invariant_zero)
                # No other row of the hook measures water in this configuration,
                # so the hook as a whole is zero for water.
                measuring = [String(r.id) for r in rows if r.dispositions[2] === :measured]
                @test isempty(measuring)
                schema = adapter_of(simulations[constrain_qtot]).schema
                spec = PB.final_map_spec(schema, :constrain_state!)
                @test PB.expected_disposition(spec, :water) === :invariant_zero
                @test !PB.hook_is_measured(schema, :constrain_state!)
            end
        end
    end

    @testset "An audit run holds the hook to exactly zero" begin
        for constrain_qtot in (false, true)
            @testset "constrain_qtot = $constrain_qtot" begin
                simulation = reseed!(simulations[constrain_qtot], run_seed!)
                adapter = adapter_of(simulation)
                @test adapter.mode isa PB.AuditMode
                for step in 1:3
                    # The adapter raises an error inside the step if the hook
                    # moved a quantity the registry declares zero.
                    step!(simulation, 1)
                    leg = final_leg(adapter, :constrain_state!)
                    for quantity in PB.BUDGET_QUANTITIES
                        status = PB.component_status(PB.budget_component(leg, quantity))
                        @test status isa PB.InvariantZero
                    end
                    # `constrain_state!` is the step's last write to the state.
                    # A negative `ρq_tot` after the first step is one the
                    # constraint's `ρq_tot` pass saw and left.
                    if step == 1
                        @test any(<(0), values_of(simulation.integrator.u.c.ρq_tot))
                    end
                end
            end
        end
    end
end
