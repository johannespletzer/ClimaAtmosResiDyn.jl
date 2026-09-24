#=
Integration test for `energy_source_tag_transport: enthalpy_increment`.

Under this transport the energy source tags take the parent's own increment of
`E = ρe_tot + c·ρ` after each implicit solve. A tag that follows a stiff
implicit term by its tendency lags the parent's Newton solve, and the gap grows
step by step. The parent's increment has no such gap. This file checks:

 1. the correction on a set increment. The partition takes the parent's
    increment in every cell, up to the part left out. That part sums to
    the column's change of `E` and sits where the mismatch is. The part moved
    sums to zero in the column. Each face takes the shares of the cell the
    flux leaves. The ledger holds both parts, and nothing else in the tendency
    changes. The stepper's hook runs the parent's own correction unchanged,
    and none of it allocates;
 2. on the DYCOMS RF02 EDMF column with 1-moment microphysics, where the parent
    has its own post-solve correction (the default `energy_q_tot_upwinding`):
    the closure residual is small, and the ledger explains its column total.
    The audit, the diagnostics and the split solver read the ledger. The
    model's fields are those of the same column without tags, bit for bit;
 3. the updraft's mixing of provenance on that column: the default exchange
    sums to zero over the partition and allocates only the parent helper's
    8 bytes. The audit with updraft copies is
    `energy_source_tags_updraft_integration.jl`.

The mode refuses `energy_q_tot_upwinding: none`, which
`energy_source_tags_tests.jl` checks. The file compiles the EDMF column twice,
with the tags and without them, so it has its own test group. See
`docs/src/energy_source_tags.md`.
=#
using Test
import ClimaAtmos as CA

# As in `energy_source_tags_integration.jl`: one call to compile, then
# `@allocated` on a second call, inside a function that specializes on every
# argument.
function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

# The sum of the pure region tags, the partition of `E`.
function partition_sum(Y, model)
    ᶜsum = zero.(Y.c.ρ)
    for name in CA.energy_source_region_tag_state_names(model)
        ᶜsum .+= getproperty(Y.c, name)
    end
    return ᶜsum
end

function closure(simulation)
    Y = simulation.integrator.u
    p = simulation.integrator.p
    model = p.atmos.energy_source_tagging_model
    return CA.tag_closure(
        Y,
        p,
        CA.energy_source_closure_total(model),
        CA.energy_source_region_tag_state_names(model),
    )
end

# Every field the model has without tags, compared with `isequal`, which tells
# signed zeros apart. The updrafts are compared field by field, since with
# updraft copies they hold the tags' copies as well.
function check_same_model(Y, Y_ref)
    is_diagnostic(name) =
        CA.is_energy_source_tag_name(name) ||
        CA.is_energy_source_ledger_name(name) ||
        CA.is_tag_mechanism_ledger_name(name) ||
        startswith(string(name), "prc_")
    @test Set(filter(!is_diagnostic, propertynames(Y.c))) ==
          Set(filter(!is_diagnostic, propertynames(Y_ref.c)))
    @test propertynames(Y.f) == propertynames(Y_ref.f)
    for name in filter(!is_diagnostic, propertynames(Y_ref.c))
        name == :sgsʲs && continue
        @test isequal(
            parent(getproperty(Y.c, name)),
            parent(getproperty(Y_ref.c, name)),
        )
    end
    for name in propertynames(Y_ref.c.sgsʲs.:(1))
        @test isequal(
            parent(getproperty(Y.c.sgsʲs.:(1), name)),
            parent(getproperty(Y_ref.c.sgsʲs.:(1), name)),
        )
    end
    for name in propertynames(Y_ref.f)
        @test isequal(
            parent(getproperty(Y.f, name)),
            parent(getproperty(Y_ref.f, name)),
        )
    end
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
tags = [
    Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
    Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
    Dict{String, Any}("name" => "rad", "source" => "radiation"),
    Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
    Dict{String, Any}(
        "name" => "new_strat",
        "region" => altitude_region(true),
        "source" => "all",
    ),
]

@testset "Energy source tags following the implicit increment" begin
    c = 110495.0
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a single
    # column with 1-moment microphysics, for an hour, as in
    # `energy_source_tags_edmf_integration.jl`. The updrafts' vertical diffusion
    # is off, as on the D4 column of the experiments.
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
        "edmfx_vertical_diffusion" => false,
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
        "energy_source_tags" => tags,
        "energy_source_tag_offset" => c,
        "energy_source_tag_repair" => true,
        "energy_process_record" => ["precipitation"],
    )
    increment = run_simulation(
        merge(
            edmf_dict,
            Dict{String, Any}(
                "energy_source_tag_transport" => "enthalpy_increment",
            ),
        ),
        "energy_source_tags_increment_edmf",
    )
    Y = increment.integrator.u
    p = increment.integrator.p
    FT = eltype(Y)
    model = p.atmos.energy_source_tagging_model
    @test CA.follows_implicit_increment(model)
    @test p.atmos.numerics.energy_q_tot_upwinding != Val(:none)
    @test CA.energy_source_increment_ledger_names(model) ==
          (:e_src_inc_left, :e_src_inc_moved)

    # 1. The correction on a set increment: the parent gains a profile whose
    # column total is not zero, and the tags gain nothing. So the mismatch is
    # that profile, as the state's arithmetic applies it.
    @testset "The correction on a set increment" begin
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        z_max = maximum(parent(ᶜz))
        dtγ = FT(60)
        function set_increment(Y₀)
            CA.snapshot_energy_source_increment!(Y₀, p, dtγ)
            U = copy(Y₀)
            @. U.c.ρe_tot += FT(100) * (sin(2 * FT(π) * ᶜz / z_max) + FT(0.2))
            dY = similar(Y₀)
            dY .= zero(FT)
            CA.correct_energy_source_increment!(dY, U, p)
            # The increment as applied, exact by Sterbenz's lemma.
            return U, dY, U.c.ρe_tot .- Y₀.c.ρe_tot
        end
        Y₀ = copy(Y)
        U, dY, ᶜδ = set_increment(Y₀)

        # Only the tags and the ledger change.
        for name in propertynames(Y.c)
            (
                CA.is_energy_source_tag_name(name) ||
                CA.is_energy_source_ledger_name(name)
            ) && continue
            @test all(iszero, parent(getproperty(dY.c, name)))
        end
        @test all(iszero, parent(dY.f))

        # The part left out is the column's total of the mismatch, spread over
        # the cells whose mismatch has the total's sign, in proportion to it
        # there, as for the water tags (G4.15). Rounding scales with the
        # increment, since the partition's part is exactly zero here.
        δ_total = sum(ᶜδ)
        ᶜabs_δ = abs.(ᶜδ)
        ᶜweight = CA.water_increment_left_weight.(ᶜδ, δ_total)
        ᶜleft = @. δ_total / $(sum(ᶜweight)) * ᶜweight
        scale = maximum(abs, parent(ᶜδ))
        @test abs(δ_total) > 0.1 * sum(ᶜabs_δ)
        # Both signs occur, so the rule differs from spreading by |δ|, and no
        # cell leaves out more than its own mismatch, or with the other sign.
        @test any(<(0), parent(ᶜδ)) && any(>(0), parent(ᶜδ))
        @test all(parent(abs.(ᶜleft)) .<= parent(ᶜabs_δ) .* (1 + 100 * eps(FT)))
        @test all(parent(ᶜleft) .* parent(ᶜδ) .>= 0)
        @test maximum(
            abs,
            parent(dtγ .* dY.c.e_src_inc_left) .- parent(ᶜleft),
        ) < 100 * eps(FT) * scale
        @test maximum(
            abs,
            parent(dtγ .* dY.c.e_src_inc_moved) .- (parent(ᶜδ) .- parent(ᶜleft)),
        ) < 100 * eps(FT) * scale
        # The moved part sums to zero in the column, and the left part to the
        # mismatch's total.
        ᶜmoved = dtγ .* dY.c.e_src_inc_moved
        @test abs(sum(ᶜmoved)) < 100 * eps(FT) * sum(ᶜabs_δ)
        @test isapprox(sum(dtγ .* dY.c.e_src_inc_left), δ_total; rtol = 1e-12)

        # The partition takes the part moved, cell by cell. Its tags are of the
        # size of `E`, so that sets the rounding here.
        U_new = copy(U)
        @. U_new += dtγ * dY
        ᶜpartition = partition_sum(Y₀, model)
        ᶜpartition_increment = partition_sum(U_new, model) .- ᶜpartition
        @test maximum(
            abs,
            parent(ᶜpartition_increment) .- parent(ᶜmoved),
        ) < 1000 * eps(FT) * maximum(abs, parent(ᶜpartition))
        # A tag that carries a source moves, and only within the column.
        @test sum(abs.(Y₀.c.ρe_src_sfc)) > 0
        @test !all(iszero, parent(dY.c.ρe_src_sfc))
        @test abs(sum(U_new.c.ρe_src_sfc) - sum(Y₀.c.ρe_src_sfc)) <
              1000 * eps(FT) * sum(abs.(Y₀.c.ρe_src_sfc))

        # Each face takes the shares of the cell the flux leaves. With all of
        # `E` above 750 m in `strat` and all below in `tropo`, the face at the
        # step shows which cell that is. The flux there is built from the
        # mismatch, so its direction is read from the correction's own flux.
        Y_step = copy(Y)
        ᶜE_step = @. Y_step.c.ρe_tot + c * Y_step.c.ρ
        @. Y_step.c.ρe_src_strat = ifelse(ᶜz > 750, ᶜE_step, FT(0))
        @. Y_step.c.ρe_src_tropo = ᶜE_step - Y_step.c.ρe_src_strat
        _, dY_step, _ = set_increment(Y_step)
        ᶠz = CA.Fields.coordinate_field(Y.f).z
        ᶠflux = p.tagging.ᶠe_src_increment_flux
        step_face = argmin(abs.(vec(parent(ᶠz)) .- 750))
        rises = vec(parent(ᶠflux))[step_face] > 0
        above = vec(parent(ᶜz)) .> 750
        strat = vec(parent(dY_step.c.ρe_src_strat))
        tropo = vec(parent(dY_step.c.ρe_src_tropo))
        @test !iszero(vec(parent(ᶠflux))[step_face])
        if rises
            # The cell below is the donor, so `strat` stays above the step
            # and `tropo` reaches only the first cell above it.
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
        @test hook isa CA.EnergySourceIncrementCorrection{
            typeof(CA.correct_implicit_advection_tendency!),
        }
        t = increment.integrator.t
        CA.snapshot_energy_source_increment!(Y₀, p, dtγ)
        dY_hook = similar(Y)
        hook(dY_hook, U, p, t)
        dY_parent = similar(Y)
        CA.correct_implicit_advection_tendency!(dY_parent, U, p, t)
        for name in propertynames(Y.c)
            (
                CA.is_energy_source_tag_name(name) ||
                CA.is_energy_source_ledger_name(name)
            ) && continue
            @test isequal(
                parent(getproperty(dY_hook.c, name)),
                parent(getproperty(dY_parent.c, name)),
            )
        end
        @test maximum(abs, parent(dY_parent.c.ρe_tot)) > 0

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
            CA.correct_energy_source_increment!,
            dY,
            U,
            p,
        ) == 0
        @test second_call_allocations(
            CA.snapshot_energy_source_increment!,
            Y₀,
            p,
            dtγ,
        ) == 0
    end

    # 2. The run.
    @testset "The EDMF column" begin
        # The moved part sums to zero in the column, since each stage's does.
        ᶜabs = abs.(Y.c.e_src_inc_moved)
        @test sum(ᶜabs) > 0
        @test abs(sum(Y.c.e_src_inc_moved)) < 1e-10 * sum(ᶜabs)

        # The left part explains the residual's column total, less what the
        # loss rule flushes from it. On this column after an hour that is
        # about 1% of the gross residual (FINDINGS E64 in the tag-closure
        # experiments).
        closure_increment = closure(increment)
        left = sum(Y.c.e_src_inc_left)
        @info "EDMF column after an hour, J/m²" closure_increment.gross_residual closure_increment.residual left
        @test abs(left) > 0.5 * closure_increment.gross_residual
        @test abs(closure_increment.residual - left) <
              0.05 * closure_increment.gross_residual
        # Under `enthalpy` this column's `gross_relative` is 1.5e-3 after an
        # hour; here it is 8e-7.
        @test closure_increment.gross_relative < 1e-5

        # The audit's columns and the diagnostics read the ledger.
        audit = CA.energy_source_audit(Y, p, model, FT(1))
        @test isequal(audit.increment_left, left)
        @test audit.increment_left_net_abs ≈ sum(abs.(Y.c.e_src_inc_left))
        @test audit.increment_moved_net_abs ≈ sum(ᶜabs)
        ᶜleft_specific = CA.Diagnostics.compute_e_src_ledger!(
            nothing,
            Y,
            p,
            increment.integrator.t,
            :e_src_inc_left,
        )
        @test parent(ᶜleft_specific) ≈ parent(Y.c.e_src_inc_left ./ Y.c.ρ)

        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        uncoupled = Set(map(field -> field.name, cache.solver.uncoupled))
        for name in (:e_src_inc_left, :e_src_inc_moved)
            @test CA.MatrixFields.FieldName(:c, name) in uncoupled
        end

        # The model's own fields are those of the same column without tags,
        # bit for bit.
        plain = run_simulation(
            filter(
                entry -> !startswith(first(entry), "energy_"),
                edmf_dict,
            ),
            "energy_source_tags_increment_edmf_plain",
        )
        @test isnothing(plain.integrator.p.atmos.energy_source_tagging_model)
        check_same_model(Y, plain.integrator.u)

        # 3. The updraft's mixing of provenance. By default the tags exchange
        # provenance at the mass flux. The partition's exchange sums to zero in
        # every cell, a source tag's stands alone, and nothing else changes.
        dY = similar(Y)
        dY .= zero(FT)
        exchange! = CA.sgs_exchange_of_energy_source_tags!
        exchange!(dY, Y, p, p.atmos.turbconv_model, model)
        ᶜsum = zero.(Y.c.ρ)
        ᶜgross = zero.(Y.c.ρ)
        for name in CA.energy_source_region_tag_state_names(model)
            ᶜsum .+= getproperty(dY.c, name)
            ᶜgross .+= abs.(getproperty(dY.c, name))
        end
        @test maximum(parent(ᶜgross)) > 0
        @test maximum(abs, parent(ᶜsum)) < 1e-10 * maximum(parent(ᶜgross))
        # The updraft lifts the surface's energy.
        @test maximum(abs, parent(dY.c.ρe_src_sfc)) > 0
        for name in propertynames(Y.c)
            (name == :sgsʲs || CA.is_energy_source_tag_name(name)) && continue
            @test all(iszero, parent(getproperty(dY.c, name)))
        end
        @test all(iszero, parent(dY.c.sgsʲs))
        @test all(iszero, parent(dY.f))
        # It reads the environment's `mse` through the parent's helper, whose
        # closure Julia wraps in a `Ref`, 8 bytes. That is all it allocates,
        # on ClimaCore 0.16.0, 1.0.0 and 1.0.1 alike. Its kernel reads the
        # environment's density and two ratios from scratch. When it read them
        # lazily, ClimaCore boxed the kernel's broadcast on every call, 17 kB
        # here with each of those versions.
        @test second_call_allocations(
            exchange!,
            dY,
            Y,
            p,
            p.atmos.turbconv_model,
            model,
        ) <= 8
    end
end
