using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

# The implicit vertical Smagorinsky-Lilly diffusion in the parent budget.
#
# With `implicit_diffusion`, upstream moves the vertical part of the
# Smagorinsky-Lilly closure into the implicit tendency. The fork brackets it
# there as the applied-update event `smagorinsky_lilly`, the row
# `impl.smagorinsky_lilly`, beside the explicit bracket that keeps the
# horizontal part. This file checks that the implicit row is recorded, and
# recorded right.
#
# A column cannot run the closure. Its setup stops with a BoundsError, upstream
# too. So this is a small DYCOMS_RF02 box with one-moment microphysics, a
# smaller copy of the box of the parity runs for the upstream merge. The
# sheared wind and the moist inversion give the vertical diffusion a large
# local tendency.
#
# Diffusion with closed boundaries integrates to almost nothing, so a test of
# the integral alone could pass with an empty bracket. Each recorded leg is
# therefore compared with an independent measurement twice: its net amount,
# and its magnitude, the integral of the absolute local tendency. The
# magnitude is far from zero, and no cancellation can make it match.
#
# The independent measurement does not use the bracket. A wrapper around the
# stepper's post-implicit hook sees each solved stage with its refreshed cache,
# which is the stage the adapter measures. There it evaluates
# `vertical_smagorinsky_lilly_tendency!` alone into a zeroed scratch tendency
# and integrates it with ClimaCore's own sums. The stepper's tableau gives the
# accepted weight. The wrapper writes only its own tendency and the cache's
# scratch space, which every tendency evaluation overwrites before reading. The
# last test shows that the run steps the trajectory it steps without the
# parent budget.

const FT = Float64

box_config(job_id, parent_budget_mode) = CA.AtmosConfig(
    Dict{String, Any}(
        "initial_condition" => "DYCOMS_RF02",
        "config" => "box",
        "x_elem" => 2,
        "y_elem" => 2,
        "x_max" => 3200.0,
        "y_max" => 3200.0,
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "hyperdiff" => nothing,
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        "smagorinsky_lilly" => "UVW",
        "implicit_diffusion" => true,
        "FLOAT_TYPE" => "Float64",
        "dt" => "1secs",
        "t_end" => "600secs",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(),
        "parent_budget_mode" => parent_budget_mode,
    );
    job_id,
)

include("wrapped_hooks.jl")

# The integrals of one isolated tendency: per parent field, the net amount and
# the magnitude, with ClimaCore's sums.
function isolated_integrals(Yₜ)
    fields = (Yₜ.c.ρ, Yₜ.c.ρq_tot, Yₜ.c.ρe_tot)
    return (;
        amount = map(sum, fields),
        magnitude = map(field -> sum(abs.(field)), fields),
    )
end

# A hook wrapper that first evaluates `tendency!` alone on the stage it is
# given, and records its integrals in `samples`.
function recording(tendency!, samples, scratch, position)
    return hook -> function (args...)
        U, p, t = args[position], args[position + 1], args[position + 2]
        scratch .= zero(eltype(scratch))
        tendency!(scratch, U, p, t, p.atmos.smagorinsky_lilly)
        push!(samples, isolated_integrals(scratch))
        return hook(args...)
    end
end

adapter_of(simulation) = simulation.integrator.p.parent_budget

legs_of(adapter, process, channel) = filter(
    l -> l.process === process && l.channel === channel,
    adapter.last_legs,
)

parent_row(adapter, quantity) = only(
    filter(
        r -> r.quantity === quantity && r.control_volume === :atmosphere_only,
        PB.latest_commit(adapter).parent,
    ),
)

attribution_row(adapter, channel, quantity) = only(
    filter(
        r ->
            r.channel === channel && r.quantity === quantity &&
            r.control_volume === :atmosphere_only,
        PB.latest_commit(adapter).attribution,
    ),
)

components(leg) = (leg.mass, leg.water, leg.energy)

const STEPS = 3

@testset "Parent-budget implicit Smagorinsky-Lilly" begin
    off = CA.get_simulation(box_config("parent_budget_smagorinsky_off", "off"))
    audit = CA.get_simulation(box_config("parent_budget_smagorinsky_audit", "audit"))
    adapter = adapter_of(audit)
    atmos = audit.integrator.p.atmos
    @test atmos.diff_mode == CA.Implicit()
    @test !isnothing(atmos.smagorinsky_lilly)

    # The registry selects the implicit row with its event, and the adapter
    # brackets the event. The explicit row is selected too, for the horizontal
    # part, under its own channel.
    @test :smagorinsky_lilly in adapter.events
    implicit_rows = PB.channel_spec(adapter.schema, :implicit).processes
    @test any(r -> r.process === :smagorinsky_lilly, implicit_rows)
    explicit_rows = PB.channel_spec(adapter.schema, :explicit_main).processes
    @test any(r -> r.process === :smagorinsky_lilly, explicit_rows)

    # The wrappers sit outside the adapter's meters. The post-implicit hook
    # takes `(Yₜ, U, p, t)`, the explicit one `(Yₜ, Yₜ_lim, U, p, t)`.
    scratch = similar(audit.integrator.u)
    vertical = NamedTuple[]
    horizontal = NamedTuple[]
    integrator = with_wrapped_hooks(
        audit.integrator;
        T_post_imp! = recording(
            CA.vertical_smagorinsky_lilly_tendency!,
            vertical,
            scratch,
            2,
        ),
        T_exp_T_lim! = recording(
            CA.horizontal_smagorinsky_lilly_tendency!,
            horizontal,
            scratch,
            3,
        ),
    )
    tableau = integrator.cache.tableau
    b_imp = tableau.b_imp.coeffs
    b_exp = tableau.b_exp.coeffs
    implicit_stages = adapter.template.implicit_stages
    explicit_stages = adapter.template.explicit_stages
    dt = FT(float(integrator.dt))

    for step in 1:STEPS
        empty!(vertical)
        empty!(horizontal)
        CTS.step!(integrator)
        CTS.step!(off.integrator)

        # One post-implicit firing per solved stage, one explicit evaluation
        # per stage of the tableau.
        @test length(vertical) == length(implicit_stages)
        @test length(horizontal) == length(b_exp)

        # The implicit row: one leg per solved stage, with the accepted
        # implicit weight `dt * b_imp[i]`, each quantity measured and equal to
        # the isolated tendency under that weight. The bracket takes the
        # difference of the implicit tendency before and after the process,
        # so it carries the rounding of the larger implicit terms around it. On
        # terrabyte the two measurements part by at most 1.4e-12 of the
        # magnitude, in net amount and in magnitude alike.
        legs = sort(legs_of(adapter, :smagorinsky_lilly, :implicit); by = l -> l.stage)
        @test [l.stage for l in legs] == implicit_stages
        smallest = fill(Inf, 3)
        for (leg, sample) in zip(legs, vertical)
            weight = dt * b_imp[leg.stage]
            @test leg.event === Symbol("impl.smagorinsky_lilly")
            @test leg.level isa PB.ProcessDecomposition
            @test leg.measured_at === :solved_stage
            @test leg.weight ≈ weight rtol = 1e-14
            for (i, (component, amount, magnitude)) in
                enumerate(zip(components(leg), sample.amount, sample.magnitude))
                scale = abs(weight) * magnitude
                @test PB.component_status(component) isa PB.Measured
                @test abs(component.amount - weight * amount) <= 1e-10 * scale
                @test abs(component.magnitude - scale) <= 1e-10 * scale
                smallest[i] = min(smallest[i], scale)
            end
            # The local tendency is large, and its integral nearly cancels.
            @test sample.magnitude[3] > 1e3 * abs(sample.amount[3])
            @test all(>(0), sample.magnitude)
        end

        # The explicit row keeps the horizontal part, at the weighted explicit
        # stages, with the explicit weight. The box starts horizontally
        # uniform, so the horizontal part is rounding: both the leg and the
        # isolated horizontal tendency are below 1e-9 of the vertical part for
        # every quantity. On terrabyte they are below 3e-12 of it. So the
        # vertical part is in the implicit channel only.
        legs = sort(legs_of(adapter, :smagorinsky_lilly, :explicit_main); by = l -> l.stage)
        @test [l.stage for l in legs] == explicit_stages
        for leg in legs
            sample = horizontal[leg.stage]
            weight = dt * b_exp[leg.stage]
            @test leg.event === Symbol("expl.smagorinsky_lilly")
            @test leg.level isa PB.ProcessDecomposition
            @test leg.weight ≈ weight rtol = 1e-14
            for (i, (component, magnitude)) in
                enumerate(zip(components(leg), sample.magnitude))
                @test PB.component_status(component) isa PB.Measured
                @test component.magnitude <= 1e-9 * smallest[i]
                @test abs(weight) * magnitude <= 1e-9 * smallest[i]
            end
        end
        @test isempty(legs_of(adapter, :smagorinsky_lilly, :explicit_limited))

        # Every identity passes, and so does every channel's attribution.
        for quantity in PB.BUDGET_QUANTITIES
            r = parent_row(adapter, quantity)
            @test r.status === :pass
            @test isempty(r.blocked_by)
            @test abs(r.residual) <= r.tolerance
            for channel in (:explicit_main, :explicit_limited, :implicit)
                a = attribution_row(adapter, channel, quantity)
                @test a.status === :pass
                @test isempty(a.blocked_by)
                @test abs(a.residual) <= a.tolerance
            end
        end
    end

    # The parent budget in audit mode, with the wrappers, leaves the trajectory
    # bit for bit as it is without the parent budget.
    @test propertynames(integrator.u) == propertynames(off.integrator.u)
    for name in propertynames(integrator.u)
        @test parent(getproperty(integrator.u, name)) ==
              parent(getproperty(off.integrator.u, name))
    end
end
