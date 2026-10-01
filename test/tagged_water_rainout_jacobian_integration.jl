#=
Integration test for `water_tag_rainout_jacobian` (known issue 4, WP4a-J).

The DYCOMS RF02 column under 0M without EDMF, with implicit microphysics and
implicit diffusion, ARS222 and one Newton iteration: the raining column of
WP4a-J's experiment, for five steps of 120 s. It runs once without the key and
once with it, and asserts:

 1. every model field is bit for bit the same, and the tags are not;
 2. the Jacobian with the key has the tags' rain-out entries, from
    `update_jacobian!` itself, and every other block as without the key;
 3. the split solver gives the model's fields the same increments, and each
    tag solves its own row, the block to `ρq_tot` included;
 4. the entries add no allocation to the update or the solve;
 5. a checkpoint written without the key restarts with it;
 6. the sparse autodiff Jacobian (`use_auto_jacobian`) of the same model
    solves with its own matrix.

The unit tests of the entries are in `tagged_water_rainout_jacobian_tests.jl`.

Run it through the package test path (`Pkg.test()`, TEST_GROUP
"tagging_water_rainout_jacobian"), or standalone with the pinned CI
environment:

    julia +1.11 --project=.buildkite test/tagged_water_rainout_jacobian_integration.jl
=#

using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

const MF = CA.MatrixFields

tanh_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)
const tags = [
    Dict{String, Any}("name" => "tropo", "region" => tanh_region(false)),
    Dict{String, Any}("name" => "strat", "region" => tanh_region(true)),
    Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
]
const tag_names = (:ρq_tag_tropo, :ρq_tag_strat, :ρq_tag_evap)

column_config(extra) = merge(
    Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "microphysics_model" => "0M",
        "implicit_microphysics" => true,
        "vert_diff" => "DecayWithHeightDiffusion",
        "implicit_diffusion" => true,
        "ode_algo" => "ARS222",
        "max_newton_iters_ode" => 1,
        "dt" => "120secs",
        "t_end" => "600secs",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "water_tracers" => tags,
        "water_tag_transport" => "tracer",
        "output_dir" => mktempdir(pwd()),
    ),
    extra,
)
simulation(extra, job_id) =
    CA.get_simulation(CA.AtmosConfig(column_config(extra); job_id))

@testset "The tags' rain-out Jacobian" begin
    off = simulation(
        Dict{String, Any}("dt_save_state_to_disk" => "600secs"),
        "rainout_jacobian_off",
    )
    on = simulation(
        Dict{String, Any}("water_tag_rainout_jacobian" => true),
        "rainout_jacobian_on",
    )
    @test !CA.has_water_tag_rainout_jacobian(off.integrator.p.atmos.water_tagging_model)
    @test CA.has_water_tag_rainout_jacobian(on.integrator.p.atmos.water_tagging_model)
    @test CA.solve_atmos!(off).ret_code == :success
    @test CA.solve_atmos!(on).ret_code == :success
    Y_off = off.integrator.u
    Y = on.integrator.u
    p = on.integrator.p
    t = on.integrator.t

    # The column rains out: the entries are not zero.
    @test minimum(parent(p.precomputed.ᶜmp_tendency.dq_tot_dt)) < 0

    @testset "Only the tags change, bit for bit" begin
        @test propertynames(Y.c) == propertynames(Y_off.c)
        for name in propertynames(Y.c)
            name in tag_names && continue
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_off.c, name)),
            )
        end
        @test isequal(parent(Y.f), parent(Y_off.f))
        for name in tag_names
            @test all(isfinite, parent(getproperty(Y.c, name)))
            @test !isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_off.c, name)),
            )
        end
    end

    alg = CA.ManualSparseJacobian()
    c(name) = MF.FieldName(:c, name)
    cache = CA.jacobian_cache(alg, Y, p.atmos)
    # The model's fields are bit for bit the same in both runs, so the cache
    # without the key is updated at the same state, through the run without
    # it, whose precomputed quantities differ only in the tags'.
    cache_off = CA.jacobian_cache(alg, Y, off.integrator.p.atmos)
    dtγ = 35.0
    CA.update_jacobian!(alg, cache, Y, p, dtγ, t)
    CA.update_jacobian!(alg, cache_off, Y, off.integrator.p, dtγ, t)

    @testset "The entries, from `update_jacobian!`" begin
        cross_keys = map(name -> (c(name), c(:ρq_tot)), tag_names)
        @test Set(keys(cache.matrix)) ==
              union(Set(keys(cache_off.matrix)), Set(cross_keys))
        ᶜloss = @. min(Y.c.ρ * p.precomputed.ᶜmp_tendency.dq_tot_dt, 0)
        for name in tag_names
            ᶜρq_tag = getproperty(Y.c, name)
            ᶜexpected = @. dtγ * ᶜloss *
               CA.water_tag_fraction_derivative_parent(ᶜρq_tag, Y.c.ρq_tot)
            cross = cache.matrix[c(name), c(:ρq_tot)]
            @test isequal(vec(parent(cross)), vec(parent(ᶜexpected)))
            @test any(!iszero, parent(cross))
            # The diagonal is the diffusion's plus the rain-out's entry.
            ᶜentry = @. dtγ * ᶜloss *
               CA.water_tag_fraction_derivative_tag(ᶜρq_tag, Y.c.ρq_tot)
            with = reshape(parent(cache.matrix[c(name), c(name)]), :, 3)
            without = reshape(parent(cache_off.matrix[c(name), c(name)]), :, 3)
            @test isequal(with[:, [1, 3]], without[:, [1, 3]])
            @test with[:, 2] ≈ without[:, 2] .+ vec(parent(ᶜentry)) rtol = 1e-14
            @test any(!iszero, parent(ᶜentry))
        end
        # Every other block is the same.
        for key in keys(cache_off.matrix)
            key[1] in map(c, tag_names) && key[1] == key[2] && continue
            block = cache.matrix[key]
            block isa CA.ClimaCore.Fields.Field || continue
            @test isequal(parent(block), parent(cache_off.matrix[key]))
        end
    end

    @testset "The split solver back-substitutes the block to `ρq_tot`" begin
        @test cache.solver isa CA.SplitJacobianSolver
        uncoupled = Dict(field.name => field for field in cache.solver.uncoupled)
        for name in tag_names
            field = uncoupled[c(name)]
            @test map(first, field.lower) == (c(:ρq_tot),)
        end
        ΔY = zero(Y)
        ΔY_off = zero(Y)
        CA.invert_jacobian!(alg, cache, ΔY, Y)
        CA.invert_jacobian!(alg, cache_off, ΔY_off, Y)
        for name in propertynames(Y.c)
            name in tag_names && continue
            @test isequal(
                parent(getproperty(ΔY.c, name)),
                parent(getproperty(ΔY_off.c, name)),
            )
        end
        @test isequal(parent(ΔY.f), parent(ΔY_off.f))
        # Each tag solves its own row: D Δtag + C Δρq_tot = R_tag.
        for name in tag_names
            D = cache.matrix[c(name), c(name)]
            C = cache.matrix[c(name), c(:ρq_tot)]
            ᶜΔtag = getproperty(ΔY.c, name)
            ᶜR = getproperty(Y.c, name)
            ᶜresidual = @. D * ᶜΔtag + C * ΔY.c.ρq_tot - ᶜR
            @test maximum(abs, parent(ᶜresidual)) <=
                  1e-12 * maximum(abs, parent(ᶜR))
            @test !isequal(parent(ᶜΔtag), parent(getproperty(ΔY_off.c, name)))
        end

        # Neither allocates. Each check is a function given everything it
        # uses, so that `@allocated` counts the call alone.
        function update_allocations(alg, cache, Y, p, dtγ, t)
            CA.update_jacobian!(alg, cache, Y, p, dtγ, t)
            return @allocated CA.update_jacobian!(alg, cache, Y, p, dtγ, t)
        end
        function invert_allocations(alg, cache, ΔY, R)
            CA.invert_jacobian!(alg, cache, ΔY, R)
            return @allocated CA.invert_jacobian!(alg, cache, ΔY, R)
        end
        # The model's own update and solve are measured without the key: the
        # switch may add nothing to them.
        update_bytes = update_allocations(alg, cache, Y, p, dtγ, t)
        update_bytes_off =
            update_allocations(alg, cache_off, Y, off.integrator.p, dtγ, t)
        split_bytes = invert_allocations(alg, cache, ΔY, Y)
        split_bytes_off = invert_allocations(alg, cache_off, ΔY_off, Y)
        @info "Jacobian allocations per call" update_bytes update_bytes_off split_bytes split_bytes_off
        @test update_bytes <= update_bytes_off
        @test split_bytes <= split_bytes_off
    end

    # The key changes no state, so a checkpoint written without it restarts
    # with it.
    @testset "A restart may switch it on" begin
        restart_file = joinpath(off.output_dir, "day0.600.hdf5")
        @test isfile(restart_file)
        restarted = simulation(
            Dict{String, Any}(
                "water_tag_rainout_jacobian" => true,
                "restart_file" => restart_file,
                "t_end" => "840secs",
            ),
            "rainout_jacobian_restart",
        )
        @test CA.has_water_tag_rainout_jacobian(
            restarted.integrator.p.atmos.water_tagging_model,
        )
        @test CA.solve_atmos!(restarted).ret_code == :success
    end

    # `use_auto_jacobian` once crashed in its first linear solve. The solve
    # forwarded to the manual Jacobian's, which reads a `solver` field that
    # only the manual cache has. The check builds the autodiff Jacobian of the
    # run's model, with its tags, and solves with it. It checks the solve's
    # path, not the increment. On this column the autodiff Jacobian does not
    # write the entries of the blocks to `u₃`, at upstream's code too. They
    # keep leftover memory, so the increment is not always finite, and the
    # column takes no finite step.
    @testset "The sparse autodiff Jacobian solves" begin
        auto_alg = CA.AutoSparseJacobian()
        p_off = off.integrator.p
        auto_cache = CA.jacobian_cache(auto_alg, Y_off, p_off.atmos; verbose = false)
        @test auto_cache.matrix isa MF.FieldMatrixWithSolver
        CA.update_jacobian!(auto_alg, auto_cache, Y_off, p_off, dtγ, t)
        ΔY_auto = zero(Y_off)
        CA.invert_jacobian!(auto_alg, auto_cache, ΔY_auto, Y_off)
        @test any(!iszero, parent(ΔY_auto.c))
        # The solve is upstream's: the matrix with its own solver.
        ΔY_direct = zero(Y_off)
        CA.LinearAlgebra.ldiv!(ΔY_direct, auto_cache.matrix, Y_off)
        @test isequal(parent(ΔY_auto.c), parent(ΔY_direct.c))
        @test isequal(parent(ΔY_auto.f), parent(ΔY_direct.f))
    end
end
