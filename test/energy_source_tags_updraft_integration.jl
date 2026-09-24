#=
Integration test for `energy_source_tag_updraft_copy: true`, the audit of the
energy source tags' mixing through the updrafts.

Each tag gets a passive copy in the updraft, which the model moves as any other
updraft tracer. The donor-share flux and the exchange at the mass flux then do
not run, and the model's own SGS tracer flux moves the tags. Under
`energy_source_tag_transport: enthalpy_increment` the correction after each
solve keeps the partition closed. This file checks, on the DYCOMS RF02 EDMF
column with 1-moment microphysics and the updrafts' vertical diffusion on:

 1. the copies exist, start as their tags' specific values, and take up the
    surface's energy in the updraft;
 2. the donor-share flux and the exchange do nothing, and the model's SGS
    tracer flux reaches the tags;
 3. the partition stays closed;
 4. the model's fields are those of the same column without tags, bit for bit.

The copies are a model type of their own, and the check against the column
without tags needs a second. So the file builds the EDMF column twice and has a
test group of its own. See `docs/src/energy_source_tags.md`.
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

# Every field the model has without tags, compared with `isequal`, which tells
# signed zeros apart. The updraft is compared field by field, since it holds
# the tags' copies as well.
function check_same_model(Y, Y_ref)
    is_diagnostic(name) =
        CA.is_energy_source_tag_name(name) ||
        CA.is_energy_source_ledger_name(name) ||
        CA.is_tag_mechanism_ledger_name(name) ||
        startswith(string(name), "prc_")
    @test Set(filter(!is_diagnostic, propertynames(Y.c))) ==
          Set(filter(!is_diagnostic, propertynames(Y_ref.c)))
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
    @test propertynames(Y.f) == propertynames(Y_ref.f)
    @test isequal(parent(Y.f), parent(Y_ref.f))
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

@testset "Energy source tags with updraft copies" begin
    c = 110495.0
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a single
    # column with 1-moment microphysics, for an hour, with the updrafts'
    # vertical diffusion on, which diffuses the copies too.
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
        "energy_source_tags" => [
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
        ],
        "energy_source_tag_offset" => c,
        "energy_source_tag_transport" => "enthalpy_increment",
        "energy_source_tag_updraft_copy" => true,
    )
    copies = run_simulation(merge(edmf_dict, tag_dict), "energy_source_tags_updraft")
    Y = copies.integrator.u
    p = copies.integrator.p
    t = copies.integrator.t
    FT = eltype(Y)
    model = p.atmos.energy_source_tagging_model
    turbconv_model = p.atmos.turbconv_model

    # 1. The copies.
    @testset "The updraft carries a copy of each tag" begin
        @test CA.has_energy_source_updraft_copies(model)
        @test CA.energy_source_updraft_copy_names(model) ==
              (:e_src_strat, :e_src_tropo, :e_src_sfc)
        for name in CA.energy_source_updraft_copy_names(model)
            @test hasproperty(Y.c.sgsʲs.:(1), name)
        end
        # The surface's energy has reached the updraft.
        @test maximum(parent(Y.c.sgsʲs.:(1).e_src_sfc)) > 0
        @test all(isfinite, parent(Y.c.sgsʲs))
    end

    # 2. The donor-share flux and the exchange do nothing, and the model's own
    # SGS tracer flux moves the tags.
    @testset "The model's SGS tracer flux moves the tags" begin
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_energy_source_tags!(Yₜ, Y, p, turbconv_model)
        @test all(iszero, parent(Yₜ))
        CA.edmfx_sgs_mass_flux_tendency!(Yₜ, Y, p, t, turbconv_model)
        @test maximum(abs, parent(Yₜ.c.ρe_src_sfc)) > 0
        @test maximum(abs, parent(Yₜ.c.ρe_src_strat)) > 0
    end

    # 3. The partition stays closed. After an hour the column without copies
    # closes to about 1e-6 of the scale.
    @testset "The partition stays closed" begin
        closure = CA.tag_closure(
            Y,
            p,
            CA.energy_source_closure_total(model),
            CA.energy_source_region_tag_state_names(model),
        )
        @info "EDMF column with updraft copies after an hour, J/m²" closure.gross_residual closure.residual
        @test closure.gross_relative < 1e-5
    end

    # 4. The model's own fields.
    @testset "The model's fields do not depend on the copies" begin
        plain = run_simulation(edmf_dict, "energy_source_tags_updraft_plain")
        @test isnothing(plain.integrator.p.atmos.energy_source_tagging_model)
        check_same_model(Y, plain.integrator.u)
    end
end
