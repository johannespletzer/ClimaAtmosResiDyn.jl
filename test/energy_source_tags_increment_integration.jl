#=
Integration test for `energy_source_tag_transport: enthalpy_increment`.

Under this transport the energy source tags take the parent's own increment of
`E = ρe_tot + c·ρ` after each implicit solve. A tag that follows a stiff
implicit term by its tendency lags the parent's Newton solve, and the gap grows
step by step. The parent's increment has no such gap. This file checks:

 1. the correction on a set increment. The partition takes the parent's
    increment in every cell, up to the part left in place. That part sums to
    the column's change of `E` and sits where the mismatch is. The part moved
    sums to zero in the column. The ledger holds both, and nothing else in the
    tendency changes;
 2. on the DYCOMS RF02 EDMF column with 1-moment microphysics, where the parent
    has its own post-solve correction (the default `energy_q_tot_upwinding`):
    the model's fields are those of the same run under `enthalpy`, bit for bit.
    The closure residual is far below that run's. The ledger's moved part sums
    to zero, and the split solver solves the ledger apart. The correction
    allocates nothing;
 3. on a column without EDMF under `energy_q_tot_upwinding: none`, where the
    parent has no post-solve correction and the hook fills its tendency with
    `-0.0`: the model's fields are bit for bit, and the partition closes to
    rounding.

Each transport is its own model type, so this file compiles four models, two of
them EDMF. So it has its own test group. See `docs/src/energy_source_tags.md`.
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
# signed zeros apart.
function check_same_model(Y, Y_ref)
    is_diagnostic(name) =
        CA.is_energy_source_tag_name(name) ||
        CA.is_energy_source_ledger_name(name) ||
        startswith(string(name), "prc_")
    @test Set(filter(!is_diagnostic, propertynames(Y.c))) ==
          Set(filter(!is_diagnostic, propertynames(Y_ref.c)))
    @test propertynames(Y.f) == propertynames(Y_ref.f)
    for name in filter(!is_diagnostic, propertynames(Y_ref.c))
        @test isequal(
            parent(getproperty(Y.c, name)),
            parent(getproperty(Y_ref.c, name)),
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
    # that profile.
    @testset "The correction on a set increment" begin
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        z_max = maximum(parent(ᶜz))
        ᶜδ = @. FT(100) * (sin(2 * FT(π) * ᶜz / z_max) + FT(0.2))
        dtγ = FT(60)
        Y₀ = copy(Y)
        CA.snapshot_energy_source_increment!(Y₀, p, dtγ)
        U = copy(Y₀)
        @. U.c.ρe_tot += ᶜδ
        dY = similar(Y)
        dY .= -zero(FT)
        CA.correct_energy_source_increment!(dY, U, p)

        # Nothing but the tags and the ledger changes, and a stepper adding
        # `dtγ·dY` keeps every other field as it is, signed zeros included.
        for name in propertynames(Y.c)
            (
                CA.is_energy_source_tag_name(name) ||
                CA.is_energy_source_ledger_name(name)
            ) && continue
            @test all(
                x -> iszero(x) && signbit(x),
                parent(getproperty(dY.c, name)),
            )
        end
        @test all(x -> iszero(x) && signbit(x), parent(dY.f))

        # The part left in place is the column's total of the mismatch, spread
        # in proportion to its absolute value.
        δ_total = sum(ᶜδ)
        ᶜabs_δ = abs.(ᶜδ)
        ᶜleft = @. δ_total / $(sum(ᶜabs_δ)) * ᶜabs_δ
        # The correction forms the mismatch from totals of the size of `E`,
        # so its rounding scales with `E`, not with the increment. The
        # increment is 1e-3 of `E` here, so these bounds still fail when the
        # left part lands a level off.
        scale = maximum(abs, parent(partition_sum(Y₀, model)))
        @test maximum(abs, parent(ᶜδ)) > 1e-4 * scale
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

        # The partition takes the part moved, cell by cell.
        U_new = copy(U)
        @. U_new += dtγ * dY
        ᶜpartition_increment = partition_sum(U_new, model) .- partition_sum(Y₀, model)
        @test maximum(
            abs,
            parent(ᶜpartition_increment) .- parent(ᶜmoved),
        ) < 1000 * eps(FT) * maximum(abs, parent(partition_sum(Y₀, model)))
        # A tag that carries a source only moves within the column.
        @test abs(sum(U_new.c.ρe_src_rad) - sum(Y₀.c.ρe_src_rad)) <
              100 * eps(FT) * sum(abs.(Y₀.c.ρe_src_rad)) + eps(FT)

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

    # 2. The run. The ledger's moved part sums to zero in the column, since
    # each stage's does.
    @testset "The EDMF column" begin
        ᶜabs = abs.(Y.c.e_src_inc_moved)
        @test sum(ᶜabs) > 0
        @test abs(sum(Y.c.e_src_inc_moved)) < 1e-10 * sum(ᶜabs)
        @test all(isfinite, parent(Y.c.e_src_inc_left))

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

        enthalpy = run_simulation(
            merge(
                edmf_dict,
                Dict{String, Any}("energy_source_tag_transport" => "enthalpy"),
            ),
            "energy_source_tags_increment_edmf_enthalpy",
        )
        check_same_model(Y, enthalpy.integrator.u)
        gross_increment = closure(increment).gross_residual
        gross_enthalpy = closure(enthalpy).gross_residual
        @info "EDMF column after an hour, gross residual in J/m²" gross_increment gross_enthalpy sum(
            Y.c.e_src_inc_left,
        ) closure(increment).residual
        @test gross_increment < 0.1 * gross_enthalpy
    end

    # 3. No post-solve correction in the parent: the `-0.0` path. A column
    # without EDMF, with 0-moment microphysics.
    @testset "Without the parent's post-solve correction" begin
        column_dict = Dict{String, Any}(
            "config" => "column",
            "initial_condition" => "DYCOMS_RF02",
            "z_max" => 1500.0,
            "z_elem" => 30,
            "z_stretch" => false,
            "microphysics_model" => "0M",
            "rad" => "DYCOMS",
            "dt" => "10secs",
            "t_end" => "10mins",
            "FLOAT_TYPE" => "Float64",
            "energy_q_tot_upwinding" => "none",
            "output_default_diagnostics" => false,
            "energy_source_tags" => tags,
            "energy_source_tag_offset" => c,
        )
        increment = run_simulation(
            merge(
                column_dict,
                Dict{String, Any}(
                    "energy_source_tag_transport" => "enthalpy_increment",
                ),
            ),
            "energy_source_tags_increment_column",
        )
        @test increment.integrator.p.atmos.numerics.energy_q_tot_upwinding ==
              Val(:none)
        enthalpy = run_simulation(
            merge(
                column_dict,
                Dict{String, Any}("energy_source_tag_transport" => "enthalpy"),
            ),
            "energy_source_tags_increment_column_enthalpy",
        )
        check_same_model(increment.integrator.u, enthalpy.integrator.u)
        closure_increment = closure(increment)
        closure_enthalpy = closure(enthalpy)
        @info "Column without EDMF after 10 minutes, gross residual in J/m²" closure_increment.gross_residual closure_enthalpy.gross_residual
        @test closure_increment.gross_relative < 1e-13
        @test closure_enthalpy.gross_relative > 1e-8
    end
end
