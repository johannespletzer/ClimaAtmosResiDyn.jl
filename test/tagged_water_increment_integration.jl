#=
Integration test for `water_tag_transport: increment`.

Under this transport the water tags take the parent's own increment of
`ρq_tot` after each implicit solve. Their implicit terms have fewer Jacobian
blocks than the parent's, so with one Newton iteration they lag its solve, and
the gap grows over a day (FINDINGS W21 in the tag-closure experiments). The
parent's increment has no such gap. This file checks, on the DYCOMS RF02 EDMF
column with 1-moment microphysics and the updrafts' vertical diffusion, as the
D4-W column of the experiments:

 1. the correction on a set increment. The partition takes the parent's
    increment in every cell, up to the part left in place. That part sums to
    the column's change of `ρq_tot` and sits where the mismatch is. The part
    moved sums to zero in the column. Each face takes the shares of the cell
    the flux leaves. The ledger holds both parts, and nothing else in the
    tendency changes. The stepper's hook runs the parent's own correction
    unchanged, and none of it allocates;
 2. after an hour: the closure residual is small, the ledger's moved part
    sums to zero in the column, and the audit, the diagnostics and the split
    solver read the ledger;
 3. the model's fields are those of the same column without tags, bit for bit.

The file compiles the EDMF column twice, with the tags and without them, so it
has its own test group. See `docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

# The sum of the pure region tags, the partition of `ρq_tot`.
function partition_sum(Y, model)
    ᶜsum = zero.(Y.c.ρ)
    for name in CA.water_region_tag_state_names(model)
        ᶜsum .+= getproperty(Y.c, name)
    end
    return ᶜsum
end

function run_simulation(config_dict, job_id)
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(
                config_dict,
                Dict{String, Any}("output_dir" => mktempdir(pwd())),
            );
            job_id,
        ),
    )
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

@testset "Water tags following the implicit increment" begin
    edmf_dict = Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "turbconv" => "prognostic_edmfx",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "edmfx_entr_model" => "Generalized",
        "edmfx_detr_model" => "Generalized",
        "edmfx_sgs_mass_flux" => true,
        "edmfx_sgs_diffusive_flux" => true,
        "edmfx_nh_pressure" => true,
        "edmfx_vertical_diffusion" => true,
        "edmfx_filter" => true,
        "prognostic_tke" => true,
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
    )
    tag_dict = Dict{String, Any}(
        "water_tracers" => [
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        "water_tag_transport" => "increment",
        # The audit and the diagnostics write scratch from callbacks, so the
        # parity check below covers them too.
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => ["q_tag_inc_left", "q_tag_inc_moved", "q_tag_res"],
                "period" => "10mins",
            ),
        ],
    )
    increment = run_simulation(merge(edmf_dict, tag_dict), "water_tags_increment")
    Y = increment.integrator.u
    p = increment.integrator.p
    FT = eltype(Y)
    model = p.atmos.water_tagging_model
    @test CA.follows_water_increment(model)
    @test p.atmos.numerics.energy_q_tot_upwinding != Val(:none)
    @test hasproperty(Y.c, :q_tag_inc_left)
    @test hasproperty(Y.c, :q_tag_inc_moved)
    is_diagnostic(name) =
        CA.is_water_tag_name(name) || CA.is_water_tag_ledger_name(name)

    # 1. The correction on a set increment: the parent gains a profile whose
    # column total is not zero, and the tags gain nothing. So the mismatch is
    # that profile, as the state's arithmetic applies it.
    @testset "The correction on a set increment" begin
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        z_max = maximum(parent(ᶜz))
        dtγ = FT(60)
        function set_increment(Y₀)
            CA.snapshot_water_tag_increment!(Y₀, p, dtγ)
            U = copy(Y₀)
            @. U.c.ρq_tot += FT(1e-6) * (sin(2 * FT(π) * ᶜz / z_max) + FT(0.2))
            dY = similar(Y₀)
            dY .= zero(FT)
            CA.correct_water_tag_increment!(dY, U, p)
            return U, dY, U.c.ρq_tot .- Y₀.c.ρq_tot
        end
        Y₀ = copy(Y)
        U, dY, ᶜδ = set_increment(Y₀)

        # Only the tags and the ledger change.
        for name in propertynames(Y.c)
            name == :sgsʲs && continue
            is_diagnostic(name) && continue
            @test all(iszero, parent(getproperty(dY.c, name)))
        end
        @test all(iszero, parent(dY.c.sgsʲs))
        @test all(iszero, parent(dY.f))

        # The part left in place is the column's total of the mismatch,
        # spread in proportion to its absolute value.
        δ_total = sum(ᶜδ)
        ᶜabs_δ = abs.(ᶜδ)
        ᶜleft = @. δ_total / $(sum(ᶜabs_δ)) * ᶜabs_δ
        scale = maximum(abs, parent(ᶜδ))
        @test abs(δ_total) > 0.1 * sum(ᶜabs_δ)
        @test maximum(
            abs,
            parent(dtγ .* dY.c.q_tag_inc_left) .- parent(ᶜleft),
        ) < 100 * eps(FT) * scale
        @test maximum(
            abs,
            parent(dtγ .* dY.c.q_tag_inc_moved) .- (parent(ᶜδ) .- parent(ᶜleft)),
        ) < 100 * eps(FT) * scale
        ᶜmoved = dtγ .* dY.c.q_tag_inc_moved
        @test abs(sum(ᶜmoved)) < 100 * eps(FT) * sum(ᶜabs_δ)
        @test isapprox(sum(dtγ .* dY.c.q_tag_inc_left), δ_total; rtol = 1e-12)

        # The partition takes the part moved, cell by cell.
        U_new = copy(U)
        @. U_new += dtγ * dY
        ᶜpartition = partition_sum(Y₀, model)
        ᶜpartition_increment = partition_sum(U_new, model) .- ᶜpartition
        @test maximum(
            abs,
            parent(ᶜpartition_increment) .- parent(ᶜmoved),
        ) < 1000 * eps(FT) * maximum(abs, parent(ᶜpartition))
        # A tag that carries a source moves, and only within the column.
        @test sum(abs.(Y₀.c.ρq_tag_evap)) > 0
        @test !all(iszero, parent(dY.c.ρq_tag_evap))
        @test abs(sum(U_new.c.ρq_tag_evap) - sum(Y₀.c.ρq_tag_evap)) <
              1000 * eps(FT) * sum(abs.(Y₀.c.ρq_tag_evap))

        # Each face takes the shares of the cell the flux leaves. With all of
        # the water above 750 m in `strat` and all below in `tropo`, the face
        # at the step shows which cell that is.
        Y_step = copy(Y)
        @. Y_step.c.ρq_tag_strat = ifelse(ᶜz > 750, Y_step.c.ρq_tot, FT(0))
        @. Y_step.c.ρq_tag_tropo = Y_step.c.ρq_tot - Y_step.c.ρq_tag_strat
        _, dY_step, _ = set_increment(Y_step)
        ᶠz = CA.Fields.coordinate_field(Y.f).z
        ᶠflux = p.tagging.ᶠq_tag_increment_flux
        step_face = argmin(abs.(vec(parent(ᶠz)) .- 750))
        rises = vec(parent(ᶠflux))[step_face] > 0
        above = vec(parent(ᶜz)) .> 750
        strat = vec(parent(dY_step.c.ρq_tag_strat))
        tropo = vec(parent(dY_step.c.ρq_tag_tropo))
        @test !iszero(vec(parent(ᶠflux))[step_face])
        if rises
            @test all(iszero, strat[.!above])
            @test count(!iszero, tropo[above]) == 1
        else
            @test all(iszero, tropo[above])
            @test count(!iszero, strat[.!above]) == 1
        end

        # The hook the stepper got runs the parent's own correction and then
        # the tags'. The parent's part of `dY` is what its correction alone
        # gives, bit for bit.
        hook = increment.integrator.sol.prob.f.T_post_imp!
        @test hook isa CA.WaterTagIncrementCorrection{
            typeof(CA.correct_implicit_advection_tendency!),
        }
        t = increment.integrator.t
        CA.snapshot_water_tag_increment!(Y₀, p, dtγ)
        dY_hook = similar(Y)
        hook(dY_hook, U, p, t)
        dY_parent = similar(Y)
        CA.correct_implicit_advection_tendency!(dY_parent, U, p, t)
        for name in propertynames(Y.c)
            is_diagnostic(name) && continue
            @test isequal(
                parent(getproperty(dY_hook.c, name)),
                parent(getproperty(dY_parent.c, name)),
            )
        end
        @test isequal(parent(dY_hook.f), parent(dY_parent.f))
        @test maximum(abs, parent(dY_parent.c.ρq_tot)) > 0

        # The hook allocates nothing beyond the parent's own correction.
        @test second_call_allocations(hook, dY_hook, U, p, t) <=
              second_call_allocations(
            CA.correct_implicit_advection_tendency!,
            dY_parent,
            U,
            p,
            t,
        )
        @test second_call_allocations(
            CA.correct_water_tag_increment!,
            dY,
            U,
            p,
        ) == 0
        @test second_call_allocations(
            CA.snapshot_water_tag_increment!,
            Y₀,
            p,
            dtγ,
        ) == 0
    end

    # 2. The run.
    @testset "The EDMF column after an hour" begin
        ᶜabs = abs.(Y.c.q_tag_inc_moved)
        @test sum(ᶜabs) > 0
        @test abs(sum(Y.c.q_tag_inc_moved)) < 1e-10 * sum(ᶜabs)
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        left = sum(Y.c.q_tag_inc_left)
        @info "Water tags following the increment on the EDMF column after an hour" closure.relative closure.gross_relative left sum(ᶜabs)
        # Without the follower this column's gross residual after an hour is
        # of the order of 5e-4 (FINDINGS W20's development runs).
        @test closure.gross_relative < 1e-4

        # The audit's columns and the diagnostics read the ledger.
        audit = CA.water_tag_extra_audit(Y, p, model, FT(1))
        @test isequal(audit.increment_left, left)
        @test audit.increment_left_gross ≈ sum(abs.(Y.c.q_tag_inc_left))
        @test audit.increment_moved_gross ≈ sum(ᶜabs)
        @test hasproperty(audit, :exchange_volume_fraction)
        ᶜleft_specific = CA.Diagnostics.compute_q_tag_ledger!(
            nothing,
            Y,
            p,
            increment.integrator.t,
            :q_tag_inc_left,
        )
        @test parent(ᶜleft_specific) ≈ parent(Y.c.q_tag_inc_left ./ Y.c.ρ)

        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        uncoupled = Set(map(field -> field.name, cache.solver.uncoupled))
        for name in (:q_tag_inc_left, :q_tag_inc_moved)
            @test CA.MatrixFields.FieldName(:c, name) in uncoupled
        end
    end

    # 3. The model's own fields.
    @testset "The model's fields do not depend on the tags" begin
        plain = run_simulation(edmf_dict, "water_tags_increment_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
        @test Set(filter(!is_diagnostic, propertynames(Y.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            name == :sgsʲs && continue
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        for name in propertynames(Y_plain.c.sgsʲs.:(1))
            @test isequal(
                parent(getproperty(Y.c.sgsʲs.:(1), name)),
                parent(getproperty(Y_plain.c.sgsʲs.:(1), name)),
            )
        end
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
