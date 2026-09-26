#=
Integration test for `water_tag_transport: increment` with the microphysics
stepped explicitly.

There, with one Newton iteration, the tags used to lag the parent's solve by
0.8% of the column's water in an hour (FINDINGS W23 in the tag-closure
experiments). The lag was the tags' missing sedimentation cross blocks, which
the Jacobian now carries (FINDINGS W29). This file checks, on the DYCOMS RF02
EDMF column with 1-moment microphysics and the updrafts' vertical diffusion,
as `tagged_water_increment_integration.jl` runs it, but with
`implicit_microphysics: false`:

 1. the water's partition closes within 1e-6 after an hour, net and gross;
 2. the split solver solves each tag apart, with a cross block to every
    falling species. At the final state the partition's blocks sum to the
    parent's, and the source tag's are the parent's times its share;
 3. the model's fields are those of the same column without tags, bit for bit.

The file compiles the EDMF column twice, with the tags and without them, so it
has its own test group. See `docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

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

@testset "Water tags following the increment, microphysics explicit" begin
    explicit_dict = Dict{String, Any}(
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
        "implicit_microphysics" => false,
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        "max_newton_iters_ode" => 1,
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
    )
    tagged = run_simulation(
        merge(explicit_dict, tag_dict),
        "water_tags_increment_explicit",
    )
    Y = tagged.integrator.u
    p = tagged.integrator.p
    FT = eltype(Y)
    model = p.atmos.water_tagging_model
    @test CA.follows_water_increment(model)

    # 1. The closure.
    @testset "The partition closes after an hour" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        @info "The explicit path after an hour" closure.relative closure.gross_relative
        @test abs(closure.relative) < 1e-6
        @test closure.gross_relative < 1e-6
    end

    # 2. The cross blocks and their solve.
    @testset "The tags' cross blocks" begin
        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        tag_solves = filter(
            field -> CA.is_water_tag_name(CA.jacobian_name_chain(field.name)[end]),
            collect(cache.solver.uncoupled),
        )
        @test length(tag_solves) == 3
        mass_names = map(CA.center_state_name, CA.sedimenting_mass_names(Y))
        @test length(mass_names) == 4
        for field in tag_solves
            @test Set(map(first, field.lower)) == Set(mass_names)
        end
        # The sedimentation update sets the parent's cross blocks and the
        # tags', and no other update adds to the tags', so here the
        # partition's blocks sum to the parent's to rounding.
        matrix = cache.matrix
        CA.update_sedimentation_jacobian!(
            matrix,
            Y,
            p,
            FT(60),
            CA.UseDerivative(),
        )
        c(name) = CA.MatrixFields.FieldName(:c, name)
        ᶜevap_share = @. CA.water_tag_source_sediment_share(
            Y.c.ρq_tag_evap,
            Y.c.ρq_tot,
        )
        for mass_name in mass_names
            parent_block = matrix[c(:ρq_tot), mass_name]
            # Snow and ice may not fall here at all, so their blocks may be
            # zero. Rain's is not (below).
            scale = maximum(abs, parent(parent_block))
            partition_block = copy(parent_block)
            @. partition_block =
                matrix[c(:ρq_tag_tropo), mass_name] +
                matrix[c(:ρq_tag_strat), mass_name]
            @test maximum(abs, parent(partition_block) .- parent(parent_block)) <=
                  1e-12 * scale
            evap_block = copy(parent_block)
            @. evap_block =
                parent_block * CA.MatrixFields.DiagonalMatrixRow(ᶜevap_share)
            @test maximum(
                abs,
                parent(matrix[c(:ρq_tag_evap), mass_name]) .- parent(evap_block),
            ) <= 1e-12 * scale
        end
        @test maximum(abs, parent(matrix[c(:ρq_tot), c(:ρq_rai)])) > 0
    end

    # 3. The model's own fields, compared with `isequal`, which tells signed
    # zeros apart.
    @testset "The model's fields do not depend on the tags" begin
        plain = run_simulation(explicit_dict, "water_tags_increment_explicit_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
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
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
