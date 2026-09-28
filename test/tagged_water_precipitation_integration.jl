#=
Integration test for the water tags' rain and snow parts,
`water_tag_precipitation: true`, on a 1-moment column without EDMF (stage 1
of design/RAIN_SNOW_TAGS.md on the record branch, WP4b).

The column is `PrecipitatingColumn`: rain, snow, cloud liquid and cloud ice
from the start, warm and cold, with rain reaching the ground. It is cut at
6 km, because above about 6.2 km its total water profile goes negative and no
partition of a negative parent is possible. An altitude
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
    under both transports;
 10. on a small sphere, operator by operator, hyperdiffusion and the viscous
     sponge give the rain and snow parts nothing, as they give rain and snow,
     and the non-precipitating parts sum to the parent's tendency of its
     non-precipitating water, before and after DSS. Each part moves by its
     own gradients, not by a share of the parent's tendency. The parent's
     tendencies and, after two steps, its fields are those without tags, bit
     for bit.

A column has no horizontal operators, so item 10 builds the sphere twice, with
the parts and without tags.
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

const T_END = "300secs"
base_config() = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "PrecipitatingColumn",
    "surface_setup" => "DefaultMoninObukhov",
    "z_elem" => 30,
    "z_max" => 6000.0,
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
# compartment's largest value in `Y_scale`. Rain and snow fall out and
# evaporate within minutes here, so their scale is taken at the start.
function closure(Y, Y_scale = Y)
    parents = compartments(Y)
    scales = compartments(Y_scale)
    relative(prefix) =
        maximum(abs, getproperty(parents, prefix) .- part_sum(Y, prefix)) /
        maximum(abs, getproperty(scales, prefix))
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
            CA.is_water_tag_ledger_name(name) ||
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
    Y_start = copy(Y)
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
        result = closure(Y, Y_start)
        @info "The parts' closure after $T_END under increment" result
        @test result.rain < 1e-12
        @test result.snow < 1e-12
        @test result.nonprecip < 1e-12
        @test result.total < 1e-12
        # The check the model's callbacks write sums over all six fields.
        check = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_partition_state_names(model),
        )
        @test abs(check.relative) < 1e-12
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
            (ᶜN, ᶜR, ᶜS) = map(
                prefix -> getproperty(Y.c, Symbol(prefix, name)),
                (:ρq_tag_, :ρq_rtag_, :ρq_stag_),
            )
            ᶜsum = @. (ᶜN + ᶜR + ᶜS) / Y.c.ρ
            @test maximum(abs, parent(ᶜtotal) .- parent(ᶜsum)) <=
                  4 * eps(FT) * maximum(abs, parent(ᶜsum))
            for part in ("q_ntag", "q_rtag", "q_stag", "pr_tag")
                @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "$(part)_$name")
            end
        end
        start_rain = maximum(parent(Y_start.c.ρq_rai) ./ parent(Y_start.c.ρ))
        residual = CA.Diagnostics.get_diagnostic_variable("q_rtag_res")
        @test maximum(abs, parent(residual.compute!(nothing, Y, p, t))) <
              1e-12 * start_rain
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
        # `ρq_tot`'s tendency less `advection`, where `ρq_tot` takes a
        # transport that the parts take in another way.
        function compare(label, Yₜ; advection = 0)
            parents = (;
                ρq_tag_ = parent(Yₜ.c.ρq_tot) .- parent(Yₜ.c.ρq_rai) .-
                          parent(Yₜ.c.ρq_sno) .- advection,
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
        # Sedimentation, in the implicit vertical advection. There `ρq_tot`
        # also takes its central advection, which the parts take through
        # the follower instead.
        Yₜ = zero_tendency()
        CA.implicit_vertical_advection_tendency!(Yₜ, Y_twin, p, t)
        ᶜadvection = similar(Y_twin.c.ρ)
        ᶜq_tot = @. Y_twin.c.ρq_tot / Y_twin.c.ρ
        ᶜadvection .= CA.vertical_transport(
            Y_twin.c.ρ,
            p.precomputed.ᶠu³,
            ᶜq_tot,
            p.dt,
            Val(:none),
        )
        compare("sedimentation", Yₜ; advection = parent(ᶜadvection))
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
        audit =
            maximum(abs, parent(Y.c.q_rtag_aud_lower)) +
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
    tracer = run!(
        build(
            merge(base_config(), tag_config("tracer")),
            "water_tags_precipitation_tracer",
        ),
    )
    @testset "The parts under the default transport" begin
        @test !CA.follows_water_increment(tracer.integrator.p.atmos.water_tagging_model)
        # The same start as the column above, whose rain and snow scale
        # the residuals.
        result = closure(tracer.integrator.u, Y_start)
        @info "The parts' closure after $T_END as tracers" result
        # Rain and snow are advected explicitly, as their parts are, so
        # their compartments close to rounding here too: 2e-16 and 3e-16 of
        # the start's rain and snow on 2026-09-25.
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

# 10. The horizontal operators, which a column does not have. This is the
# smallest sphere that has them, as in item 10 of
# `energy_source_tags_integration.jl`: 2 elements a side, 4 levels, two steps.
# Hyperdiffusion is on by default. The viscous sponge is switched on, and its
# damping height is moved to the ground, so that it acts on every level and
# not only above the water. Its coefficient is set too, so that the stability
# of the explicit sponge does not rest on a default. The nodes are at least
# 985 km apart here, and 1e6 m²/s over 400 s is 4.1e-4 of the square of that.
function sphere_config(sponge_toml)
    return Dict{String, Any}(
        "config" => "sphere",
        "h_elem" => 2,
        "z_elem" => 4,
        "z_max" => 30000.0,
        "z_stretch" => false,
        "dt" => "400secs",
        "t_end" => "800secs",
        "initial_condition" => "MoistBaroclinicWave",
        "cloud_model" => "grid_scale",
        "microphysics_model" => "1M",
        "hyperdiff" => "Hyperdiffusion",
        "viscous_sponge" => true,
        "toml" => [sponge_toml],
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
    )
end
# A band and its exact complement, so that the partition varies horizontally.
sphere_tag_config() = Dict{String, Any}(
    "water_tracers" => [
        Dict{String, Any}("name" => "tropics", "region" => "tropics"),
        Dict{String, Any}("name" => "extratropics", "region" => "extratropics"),
    ],
    "water_tag_precipitation" => true,
)
# The sphere's partition's sum of one part, in a state or a tendency.
sphere_part_sum(x, prefix) =
    parent(getproperty(x.c, Symbol(prefix, :tropics))) .+
    parent(getproperty(x.c, Symbol(prefix, :extratropics)))

@testset "Water tags with rain and snow parts on a sphere" begin
    sponge_toml = joinpath(mktempdir(pwd()), "viscous_sponge_everywhere.toml")
    write(
        sponge_toml,
        """
        [zd_viscous]
        value = 0.0
        type = "float"

        [kappa_2_sponge]
        value = 1.0e6
        type = "float"
        """,
    )
    sphere = run!(
        build(
            merge(sphere_config(sponge_toml), sphere_tag_config()),
            "water_tags_precipitation_sphere",
        ),
    )
    sphere_plain = run!(
        build(sphere_config(sponge_toml), "water_tags_precipitation_sphere_plain"),
    )
    Y = sphere.integrator.u
    p = sphere.integrator.p
    t = sphere.integrator.t
    Y_plain = sphere_plain.integrator.u
    p_plain = sphere_plain.integrator.p
    FT = eltype(Y)
    @test CA.has_water_tag_precipitation(p.atmos.water_tagging_model)
    @test isnothing(p_plain.atmos.water_tagging_model)
    @test p.atmos.hyperdiff isa CA.Hyperdiffusion
    @test p.atmos.viscous_sponge isa CA.ViscousSponge
    @test iszero(p.atmos.viscous_sponge.zd)
    @test p.atmos.viscous_sponge.κ₂ == 1e6
    # Both DSS steps below run only where the space needs them.
    @test CA.do_dss(axes(Y.c))
    @test sphere_plain.integrator.t == t

    @testset "The model's fields on the sphere do not depend on the parts" begin
        for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
            @test all(isfinite, sphere_part_sum(Y, prefix))
        end
        test_parity(Y, Y_plain)
    end

    # The state the operators are evaluated on: the model's after two steps,
    # with its rain and snow replaced by a fifth and a tenth of its vapour.
    # Two steps need not form rain or snow, and rain and snow that vary
    # horizontally are what would show a parent-excluded diffusion of their
    # parts. The tags then take their masked shares again. A floor keeps every
    # compartment positive, since the model's water after two steps need not
    # be positive everywhere. So the test does not cover points where `N`
    # holds no water, or where every tag's part of it is at or below zero.
    # There the tags have no shares of `N`, so they take no share of
    # `q_tot_r`. Where the pressure is at least 250 hPa, `q_tot_r` is not
    # zero, and there the parts' sum would not follow the parent's
    # hyperdiffusion.
    Y_test = copy(Y)
    ᶜρq_vap = @. Y.c.ρq_tot - Y.c.ρq_lcl - Y.c.ρq_icl - Y.c.ρq_rai - Y.c.ρq_sno
    ᶜq_vap = @. max(ᶜρq_vap / Y.c.ρ, 0) + 1e-9
    @. Y_test.c.ρq_lcl = max(Y.c.ρq_lcl, 0)
    @. Y_test.c.ρq_icl = max(Y.c.ρq_icl, 0)
    @. Y_test.c.ρq_tot = Y.c.ρ * ᶜq_vap + Y_test.c.ρq_lcl + Y_test.c.ρq_icl
    @. Y_test.c.ρq_rai = 0.2 * Y.c.ρ * ᶜq_vap
    @. Y_test.c.ρq_sno = 0.1 * Y.c.ρ * ᶜq_vap
    CA.rebuild_tags_from_state!(Y_test, p.atmos)
    CA.set_precomputed_quantities!(Y_test, p, t)
    # The same state without tags, for the parent's tendencies.
    Y_plain_test = copy(Y_plain)
    for name in propertynames(Y_plain_test.c)
        parent(getproperty(Y_plain_test.c, name)) .= parent(getproperty(Y_test.c, name))
    end
    parent(Y_plain_test.f) .= parent(Y_test.f)
    CA.set_precomputed_quantities!(Y_plain_test, p_plain, t)

    @testset "The partition of the sphere's state" begin
        start = compartments(Y_test)
        @test minimum(start.ρq_tag_) > 0
        @test minimum(start.ρq_rtag_) > 0
        @test minimum(start.ρq_stag_) > 0
        # Each part is its masked share of its compartment, as at the start
        # of the column.
        for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
            compartment = getproperty(start, prefix)
            @test maximum(abs, compartment .- sphere_part_sum(Y_test, prefix)) <
                  100 * eps(FT) * maximum(abs, compartment)
        end
        # The rain parts vary horizontally: the sponge would move them if it
        # took them as the tracers they are.
        ᶜχ = @. Y_test.c.ρq_rtag_tropics / Y_test.c.ρ
        ᶜwould_move = similar(ᶜχ)
        ᶜwould_move .= CA.viscous_sponge_tendency_tracer(
            Y_test.c.ρ,
            ᶜχ,
            p.atmos.viscous_sponge,
        )
        @test maximum(abs, parent(ᶜwould_move)) > 0
    end

    # Each operator into zeroed tendencies. Hyperdiffusion puts its tracer
    # tendencies into a second buffer, as `remaining_tendency!` does, and DSSes
    # its Laplacians between its two stages.
    function hyperdiffusion(Y, p)
        Yₜ = zero(Y)
        Yₜ_lim = zero(Y)
        CA.hyperdiffusion_tendency!(Yₜ, Yₜ_lim, Y, p, t)
        Yₜ .+= Yₜ_lim
        return Yₜ
    end
    function sponge(Y, p)
        Yₜ = zero(Y)
        CA.viscous_sponge_tendency!(Yₜ, Y, p)
        return Yₜ
    end
    # Rain and snow take nothing from either operator, so their parts and the
    # audit's records take nothing either. The non-precipitating parts sum to
    # the parent's tendency of `ρq_tot - ρq_rai - ρq_sno`, to rounding. The
    # residual is relative to the largest of the three tendencies, since the
    # sum cancels the parts' larger values at the band's edges. The bound was
    # sized on a one-dimensional model of both operators in Float64, with
    # degree-3 elements, their DSS and the same band, on 8 and 16 elements
    # (2026-09-27). There the residual is 3e-16 to 6e-15. Even taken as
    # independent, the parent's own rounding stays below 1.4e-13 of its
    # tendency. The sphere's metric terms add operations, not orders: on this
    # sphere, on Julia 1.11, the residual is 6e-16 to 9e-16 under both
    # operators, before and after DSS. So the bound sits above that rounding
    # estimate. In the same model a part hyperdiffused without its share of
    # `q_tot_r`, or with all of it, leaves 2e-5 to 2e-3, and a part left out of
    # the Laplacians' DSS leaves 0.15 to 0.5.
    function test_split(Yₜ)
        for name in (:ρq_rai, :ρq_sno)
            @test all(iszero, parent(getproperty(Yₜ.c, name)))
        end
        parts = (:ρq_rtag_, :ρq_stag_, :q_rtag_aud_, :q_stag_aud_)
        for prefix in parts, name in (:tropics, :extratropics)
            @test all(iszero, parent(getproperty(Yₜ.c, Symbol(prefix, name))))
        end
        expected = compartments(Yₜ).ρq_tag_
        tropics = parent(Yₜ.c.ρq_tag_tropics)
        extratropics = parent(Yₜ.c.ρq_tag_extratropics)
        @test maximum(abs, expected) > 0
        @test maximum(abs, tropics) > 0
        @test maximum(abs, extratropics) > 0
        scale = max(
            maximum(abs, expected),
            maximum(abs, tropics),
            maximum(abs, extratropics),
        )
        residual = maximum(abs, tropics .+ extratropics .- expected) / scale
        @test residual <= 1e-12
        return residual
    end
    operators = (("hyperdiffusion", hyperdiffusion), ("the viscous sponge", sponge))
    for (label, operator) in operators
        @testset "The parts under $label" begin
            Yₜ = operator(Y_test, p)
            # The parent's tendencies are those without tags, bit for bit.
            test_parity(Yₜ, operator(Y_plain_test, p_plain))
            # The cloud species take a share of the parent's tendency. The
            # parts move by their own gradients instead, so their water
            # crosses the band's edges. There the two differ at the scale of
            # the part's tendency. In a two-dimensional model of both
            # operators with degree-3 elements, a varying metric and bands as
            # sharp as this one or wider, the difference was at least 0.4 of
            # the part's largest tendency. A share of the parent's tendency
            # would leave only rounding.
            share = parent(Y_test.c.ρq_tag_tropics) ./ compartments(Y_test).ρq_tag_
            tropicsₜ = parent(Yₜ.c.ρq_tag_tropics)
            @test maximum(abs, tropicsₜ .- share .* compartments(Yₜ).ρq_tag_) >
                  1e-3 * maximum(abs, tropicsₜ)
            before = test_split(Yₜ)
            # The stepper DSSes the stage's state, which is linear, so the
            # split has to survive a DSS of the tendency.
            CA.dss!(Yₜ, p, t)
            after = test_split(Yₜ)
            @info "The non-precipitating parts' residual under $label" before after
        end
    end
end
