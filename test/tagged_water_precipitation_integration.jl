#=
Integration test for the water tags' rain and snow parts,
`water_tag_precipitation: true`, on a 1-moment column without EDMF (stage 1
of design/RAIN_SNOW_TAGS.md on the record branch, WP4b).

The column is `PrecipitatingColumn`: rain, snow, cloud liquid and cloud ice
from the start, warm and cold, with rain reaching the ground. An altitude
region and its complement partition the water, and a `surface_flux` source
tag rides along. The file builds the column three times: with the parts
following the parent's increment (`water_tag_transport: increment`), with the
parts moved as tracers (the default), and without tags. It checks:

 1. at the start, each part is its masked share of its compartment;
 2. under `increment` with first-order upwinding, the design note's section
    6 test: each compartment and the total close to rounding after the run;
 3. the tag's total diagnostic is the sum of its parts, to rounding;
 4. `pr_tag` of the partition closes to `pr`;
 5. the note's section 5 twin test: a tag that holds all of each compartment
    takes each operator's tendency of that compartment, operator by operator;
 6. the split solver solves the parts apart, and the audit fills;
 7. the restart guard: a checkpoint with the parts restarts bit for bit with
    the key, and is refused without it;
 8. under `tracer`, the partition stays bounded;
 9. the model's fields are those of the column without tags, bit for bit,
    under both transports.
=#
using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 3000.0,
    "width" => 300.0,
    "above" => above,
)

const T_END = "600secs"
base_config() = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "PrecipitatingColumn",
    "surface_setup" => "DefaultMoninObukhov",
    "z_elem" => 50,
    "z_max" => 10000.0,
    "z_stretch" => false,
    "dt" => "10secs",
    "t_end" => T_END,
    "cloud_model" => "grid_scale",
    "microphysics_model" => "1M",
    "vert_diff" => "DecayWithHeightDiffusion",
    "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    # Linear advection, so the parts' sums follow the species (section 6).
    "tracer_upwinding" => "first_order",
    "toml" => [
        joinpath(pkgdir(CA), "toml", "single_column_precipitation_test.toml"),
    ],
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(pwd()),
)
tag_config(transport) = Dict{String, Any}(
    "water_tracers" => [
        Dict{String, Any}("name" => "lower", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "upper", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
    "water_tag_precipitation" => true,
    "water_tag_transport" => transport,
)

function build(config, job_id)
    return CA.get_simulation(CA.AtmosConfig(config; job_id))
end
function run!(simulation)
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

# The partition's sum of one part, and the compartment it partitions.
part_sum(Y, prefix) =
    parent(getproperty(Y.c, Symbol(prefix, :lower))) .+
    parent(getproperty(Y.c, Symbol(prefix, :upper)))
compartments(Y) = (;
    ρq_tag_ = parent(Y.c.ρq_tot) .- parent(Y.c.ρq_rai) .- parent(Y.c.ρq_sno),
    ρq_rtag_ = parent(Y.c.ρq_rai),
    ρq_stag_ = parent(Y.c.ρq_sno),
)
# Each compartment's and the total's largest residual, relative to the
# compartment's largest value.
function closure(Y)
    parents = compartments(Y)
    relative(prefix) =
        maximum(abs, getproperty(parents, prefix) .- part_sum(Y, prefix)) /
        maximum(abs, getproperty(parents, prefix))
    total =
        part_sum(Y, :ρq_tag_) .+ part_sum(Y, :ρq_rtag_) .+ part_sum(Y, :ρq_stag_)
    return (;
        nonprecip = relative(:ρq_tag_),
        rain = relative(:ρq_rtag_),
        snow = relative(:ρq_stag_),
        total = maximum(abs, parent(Y.c.ρq_tot) .- total) /
                maximum(abs, parent(Y.c.ρq_tot)),
    )
end

# The model's own fields, compared with `isequal`, which tells signed zeros
# apart. See "Fork parity with upstream" in `docs/clima_atmos_specific.md`.
function test_parity(Y, Y_plain)
    for name in propertynames(Y_plain.c)
        @test isequal(
            parent(getproperty(Y.c, name)),
            parent(getproperty(Y_plain.c, name)),
        )
    end
    @test isequal(parent(Y.f), parent(Y_plain.f))
    @test all(
        name ->
            hasproperty(Y_plain.c, name) ||
                CA.is_tagged_tracer_name(name) ||
                CA.is_tag_mechanism_ledger_name(name) ||
                CA.is_water_tag_audit_name(name),
        propertynames(Y.c),
    )
end

@testset "Water tags with rain and snow parts" begin
    config = merge(
        base_config(),
        tag_config("increment"),
        Dict{String, Any}("dt_save_state_to_disk" => T_END),
    )
    simulation = build(config, "water_tags_precipitation")
    Y = simulation.integrator.u
    p = simulation.integrator.p
    FT = eltype(Y)
    model = p.atmos.water_tagging_model
    @test CA.has_water_tag_precipitation(model)
    @test CA.follows_water_increment(model)

    # 1. The start: each part is its masked share of its compartment.
    @testset "The parts at the start" begin
        start = closure(Y)
        @test start.nonprecip < 100 * eps(FT)
        @test start.rain < 100 * eps(FT)
        @test start.snow < 100 * eps(FT)
        @test maximum(parent(Y.c.ρq_rai)) > 0
        @test maximum(parent(Y.c.ρq_sno)) > 0
        for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
            @test all(iszero, parent(getproperty(Y.c, Symbol(prefix, :evap))))
        end
    end

    run!(simulation)

    # 2. The design note's section 6 test.
    @testset "Each compartment closes under the increment" begin
        result = closure(Y)
        @info "The parts' closure after $T_END under increment" result
        @test result.rain < 1e-12
        @test result.snow < 1e-12
        @test result.nonprecip < 1e-10
        @test result.total < 1e-10
        # The check the model's callbacks write sums over all six fields.
        check = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_partition_state_names(model),
        )
        @test abs(check.relative) < 1e-10
        # The parts stay non-negative, up to the transport's rounding.
        for prefix in (:ρq_rtag_, :ρq_stag_), name in (:lower, :upper, :evap)
            field = parent(getproperty(Y.c, Symbol(prefix, name)))
            @test minimum(field) >= -1e-12 * maximum(parent(Y.c.ρq_tot))
        end
        # Rain and snow moved between the tags: each part is a mix now.
        @test maximum(part_sum(Y, :ρq_rtag_)) > 0
        @test maximum(parent(Y.c.ρq_rtag_upper)) > 0
        @test maximum(parent(Y.c.ρq_rtag_lower)) > 0
    end

    t = simulation.integrator.t
    CA.set_precomputed_quantities!(Y, p, t)

    # 3. The derived total and the parts' diagnostics.
    @testset "The tag's total is the sum of its parts" begin
        for name in (:lower, :upper, :evap)
            total = CA.Diagnostics.get_diagnostic_variable("q_tag_$name")
            ᶜtotal = total.compute!(nothing, Y, p, t)
            ᶜsum = @. (
                getproperty(Y.c, Symbol(:ρq_tag_, name)) +
                getproperty(Y.c, Symbol(:ρq_rtag_, name)) +
                getproperty(Y.c, Symbol(:ρq_stag_, name))
            ) / Y.c.ρ
            @test maximum(abs, parent(ᶜtotal) .- parent(ᶜsum)) <=
                  4 * eps(FT) * maximum(abs, parent(ᶜsum))
            for part in ("q_ntag", "q_rtag", "q_stag", "pr_tag")
                @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "$(part)_$name")
            end
        end
        residual = CA.Diagnostics.get_diagnostic_variable("q_rtag_res")
        @test maximum(abs, parent(residual.compute!(nothing, Y, p, t))) <
              1e-12 * maximum(parent(Y.c.ρq_rai) ./ parent(Y.c.ρ))
    end

    # 4. The design note's section 10: the partition's `pr_tag` closes to `pr`.
    @testset "The tags' precipitation closes to pr" begin
        pr = p.precomputed.surface_rain_flux .+ p.precomputed.surface_snow_flux
        @test maximum(abs, parent(pr)) > 0
        pr_tags = map(model.tags) do tag
            CA.water_tag_precipitation_flux!(similar(pr), Y, p, tag)
        end
        partition = pr_tags[1] .+ pr_tags[2]
        @info "pr and the partition's pr_tag" parent(pr)[1] parent(partition)[1]
        @test maximum(abs, parent(partition) .- parent(pr)) <=
              1e-10 * maximum(abs, parent(pr))
        # A tag holds rain of both origins by now.
        @test all(x -> x < 0, parent(pr_tags[1]))
    end

    # 5. The design note's section 5 twin: `upper` holds all of each
    # compartment, and the other tags none. Each operator then moves each of
    # `upper`'s parts as it moves the compartment.
    @testset "A tag that holds everything moves as the parent" begin
        Y_twin = copy(Y)
        nonprecip = @. Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno
        Y_twin.c.ρq_tag_upper .= nonprecip
        Y_twin.c.ρq_rtag_upper .= Y.c.ρq_rai
        Y_twin.c.ρq_stag_upper .= Y.c.ρq_sno
        for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_), name in (:lower, :evap)
            getproperty(Y_twin.c, Symbol(prefix, name)) .= 0
        end
        CA.set_precomputed_quantities!(Y_twin, p, t)
        CA.water_tag_share_norm!(p, Y_twin)
        function compare(label, Yₜ)
            parents = (;
                ρq_tag_ = parent(Yₜ.c.ρq_tot) .- parent(Yₜ.c.ρq_rai) .-
                          parent(Yₜ.c.ρq_sno),
                ρq_rtag_ = parent(Yₜ.c.ρq_rai),
                ρq_stag_ = parent(Yₜ.c.ρq_sno),
            )
            for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
                expected = getproperty(parents, prefix)
                got = parent(getproperty(Yₜ.c, Symbol(prefix, :upper)))
                scale = max(maximum(abs, expected), floatmin(FT))
                @test maximum(abs, got .- expected) <= 1e-10 * scale
            end
        end
        zero_tendency() = (Yₜ = similar(Y_twin); fill!(parent(Yₜ), 0); Yₜ)
        # Sedimentation.
        Yₜ = zero_tendency()
        CA.vertical_advection_of_water_tendency!(Yₜ, Y_twin, p, t)
        compare("sedimentation", Yₜ)
        @test maximum(abs, parent(Yₜ.c.ρq_rtag_upper)) > 0
        # Microphysics, by the gross flows.
        Yₜ = zero_tendency()
        CA.microphysics_tendency!(
            Yₜ,
            Y_twin,
            p,
            t,
            p.atmos.microphysics_model,
            p.atmos.turbconv_model,
        )
        CA.water_tag_precipitation_microphysics_tendency!(Yₜ, Y_twin, p)
        compare("microphysics", Yₜ)
        @test maximum(abs, parent(Yₜ.c.ρq_rtag_upper)) > 0
        # Vertical diffusion: rain and snow take none, `N` the diffusing
        # water's.
        Yₜ = zero_tendency()
        CA.vertical_diffusion_boundary_layer_tendency!(
            Yₜ,
            Y_twin,
            p,
            t,
            p.atmos.vertical_diffusion,
        )
        @test all(iszero, parent(Yₜ.c.ρq_rtag_upper))
        @test all(iszero, parent(Yₜ.c.ρq_stag_upper))
        @test maximum(
            abs,
            parent(Yₜ.c.ρq_tag_upper) .- parent(Yₜ.c.ρq_tot),
        ) <= 1e-10 * maximum(abs, parent(Yₜ.c.ρq_tot))
        # The explicit vertical advection: the parts take their species', and
        # under the increment `N` gives both back.
        Yₜ = zero_tendency()
        CA.explicit_vertical_advection_tendency!(Yₜ, Y_twin, p, t)
        for (part, species) in ((:ρq_rtag_upper, :ρq_rai), (:ρq_stag_upper, :ρq_sno))
            expected = parent(getproperty(Yₜ.c, species))
            @test maximum(
                abs,
                parent(getproperty(Yₜ.c, part)) .- expected,
            ) <= 1e-10 * max(maximum(abs, expected), floatmin(FT))
        end
        @test maximum(
            abs,
            parent(Yₜ.c.ρq_tag_upper) .+ parent(Yₜ.c.ρq_rai) .+
            parent(Yₜ.c.ρq_sno),
        ) <= 1e-10 * max(maximum(abs, parent(Yₜ.c.ρq_rai)), floatmin(FT))
    end
    CA.set_precomputed_quantities!(Y, p, t)

    # 6. The split solver and the audit.
    @testset "The solver and the audit" begin
        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        solved = map(
            field -> CA.jacobian_name_chain(field.name)[end],
            collect(cache.solver.uncoupled),
        )
        for name in (
            CA.water_tag_precip_part_state_names(model)...,
            CA.water_tag_audit_state_names(model)...,
        )
            @test name in solved
        end
        # `N`'s cross blocks go to the cloud only.
        tag_field = only(
            filter(
                field -> CA.jacobian_name_chain(field.name)[end] == :ρq_tag_lower,
                collect(cache.solver.uncoupled),
            ),
        )
        @test Set(map(first, tag_field.lower)) ==
              Set((CA.@name(c.ρq_lcl), CA.@name(c.ρq_icl)))
        # The audit: the net-flow rule and the gross flows differ here.
        audit = maximum(abs, parent(Y.c.q_rtag_aud_lower)) +
                maximum(abs, parent(Y.c.q_rtag_aud_upper))
        @info "The audit's largest rain difference" audit maximum(parent(Y.c.ρq_rai))
        @test all(isfinite, parent(Y.c.q_rtag_aud_lower))
        @test audit > 0
    end

    # 7. The restart guard.
    @testset "A checkpoint with the parts" begin
        restart_file = joinpath(
            simulation.output_dir,
            "day0.$(round(Int, CA.time_to_seconds(T_END))).hdf5",
        )
        @test isfile(restart_file)
        restarted = build(
            merge(config, Dict{String, Any}("restart_file" => restart_file)),
            "water_tags_precipitation_restart",
        )
        Y_restart = restarted.integrator.u
        for name in propertynames(Y.c)
            @test parent(getproperty(Y_restart.c, name)) ==
                  parent(getproperty(Y.c, name))
        end
        context = ClimaComms.context(Y.c)
        plain_model = CA.WaterTaggingModel(model.tags)
        @test_throws r"rain and snow parts.*`water_tag_precipitation`" CA.check_water_tag_checkpoint(
            restart_file,
            (; water_tagging_model = plain_model),
            Y_restart,
            context,
        )
        @test isnothing(
            CA.check_water_tag_checkpoint(
                restart_file,
                (; water_tagging_model = model),
                Y_restart,
                context,
            ),
        )
    end

    # 8 and 9. The default transport, and the column without tags.
    tracer = run!(build(merge(base_config(), tag_config("tracer")), "water_tags_precipitation_tracer"))
    @testset "The parts under the default transport" begin
        @test !CA.follows_water_increment(tracer.integrator.p.atmos.water_tagging_model)
        result = closure(tracer.integrator.u)
        @info "The parts' closure after $T_END as tracers" result
        # Rain and snow are advected explicitly, as their parts are.
        @test result.rain < 1e-12
        @test result.snow < 1e-12
        # `ρq_tot` is advected implicitly and `N` explicitly.
        @test result.total < 1e-2
    end
    plain = run!(build(base_config(), "water_tags_precipitation_plain"))
    @test isnothing(plain.integrator.p.atmos.water_tagging_model)
    @testset "The model's fields do not depend on the parts" begin
        test_parity(Y, plain.integrator.u)
        test_parity(tracer.integrator.u, plain.integrator.u)
    end
end
