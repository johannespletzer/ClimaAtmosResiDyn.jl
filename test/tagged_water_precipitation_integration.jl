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
 8. under `tracer`, the partition stays bounded, with the audit switched off
    (`water_tag_precipitation_audit: false`);
 9. the model's fields are those of the column without tags, bit for bit,
    under both transports;
 10. the follow, with its closing step, and the rescale allocate nothing.

A column has no horizontal operators. Item 10, the parts under the horizontal
operators on a small sphere, is in `tagged_water_precipitation_sphere_integration.jl`,
a test group of its own, because the sphere's two builds after the column's
three took the process past the 16 GB a GitHub runner has.
=#
using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
include("tagged_water_precipitation_common.jl")

function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

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

# The partition's sum of one part. `compartments` gives the compartment it
# partitions.
part_sum(Y, prefix) =
    parent(getproperty(Y.c, Symbol(prefix, :lower))) .+
    parent(getproperty(Y.c, Symbol(prefix, :upper)))
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

    # The follow and the rescale are compiled before the first step. On Julia
    # 1.10, a first step that also infers the follow's call tree peaks about
    # 8 GiB higher than one that reuses it, and the column then needs more
    # than the 16 GB of a GitHub runner. The rescale runs here only in item 10.
    # Compiled now, while the heap is small, it needs less memory than after
    # the four builds. Neither call runs the code, so no result changes.
    @test precompile(CA.follow_water_tag_precipitation!, (typeof(Y), typeof(p)))
    @test precompile(
        CA.rescale_water_tags!,
        (typeof(Y), typeof(p), typeof(copy(Y.c.ρq_tot))),
    )

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

    # 8 and 9. The default transport, and the column without tags. The audit
    # is off here, so a run without its fields is covered too.
    tracer = run!(
        build(
            merge(
                base_config(),
                tag_config("tracer"),
                Dict{String, Any}("water_tag_precipitation_audit" => false),
            ),
            "water_tags_precipitation_tracer",
        ),
    )
    @testset "The parts under the default transport" begin
        tracer_model = tracer.integrator.p.atmos.water_tagging_model
        @test !CA.follows_water_increment(tracer_model)
        @test !CA.has_water_tag_precipitation_audit(tracer_model)
        @test !any(CA.is_water_tag_audit_name, propertynames(tracer.integrator.u.c))
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
    # The vertical diffusion's leak against the model's own vertical diffusion.
    # Between 400 and 800 m, where the diffusivity is large, `N` is made
    # negative. The partition is rebuilt at option C's targets, which leave its
    # parts empty there. The tags diffuse on their values and the parent on
    # `N/ρ`, so the tags' sum moves by the diffusion of `-min(N, 0)/ρ` more
    # than the parent does. The residual is taken relative to the parent's
    # tendency, as in the sphere's split test, and the leak must stand well
    # above it. Without the leak's term the diagnostic would read zero.
    @testset "The vertical diffusion leak against the model's diffusion" begin
        Y_negative = copy(Y)
        ᶜz = CA.Fields.coordinate_field(Y_negative.c).z
        @. Y_negative.c.ρq_tot = ifelse(
            (400 < ᶜz) & (ᶜz < 800),
            Y_negative.c.ρq_rai + Y_negative.c.ρq_sno - 1e-4 * Y_negative.c.ρ,
            Y_negative.c.ρq_tot,
        )
        CA.rebuild_tags_from_state!(Y_negative, p.atmos)
        @test minimum(compartments(Y_negative).ρq_tag_) < 0
        expected = parent(
            CA.water_tag_leak!(similar(Y_negative.c.ρ), Y_negative, p, Val(:vdiff)),
        )
        Yₜ = zero(Y_negative)
        CA.vertical_diffusion_boundary_layer_tendency!(
            Yₜ,
            Y_negative,
            p,
            simulation.integrator.t,
            p.atmos.vertical_diffusion,
        )
        ρ = parent(Y_negative.c.ρ)
        parentₜ = compartments(Yₜ).ρq_tag_ ./ ρ
        actual = part_sum(Yₜ, :ρq_tag_) ./ ρ .- parentₜ
        scale = maximum(abs, parentₜ)
        @test all(isfinite, actual)
        @test maximum(abs, expected) > 1e-4 * scale
        residual = maximum(abs, actual .- expected) / scale
        @test residual <= 1e-10
        @info "The vertical diffusion leak against the model's" largest =
            maximum(abs, expected) scale residual
    end
    plain = run!(build(base_config(), "water_tags_precipitation_plain"))
    @test isnothing(plain.integrator.p.atmos.water_tagging_model)
    @testset "The model's fields do not depend on the parts" begin
        test_parity(Y, plain.integrator.u)
        test_parity(tracer.integrator.u, plain.integrator.u)
    end

    # 10. Last, since both calls move the tags. The follow runs every time the
    # state is constrained, and its closing step with it. Each step of the
    # follow and of the rescale allocates a few small objects per call, not
    # per cell: on `main` at d3c5e42f, 64 bytes for the follow and 192 for the
    # rescale, on Julia 1.11. Raising `N` first runs each step twice, so the
    # counts double, on Julia 1.10 and 1.11. The closing step adds none. A
    # per-cell allocation
    # would scale with the column's 30 levels and pass these bounds by far.
    @testset "The follow and the rescale allocate no more per call" begin
        ᶜρq_tot_before = copy(Y.c.ρq_tot)
        follow = second_call_allocations(CA.follow_water_tag_precipitation!, Y, p)
        rescale =
            second_call_allocations(CA.rescale_water_tags!, Y, p, ᶜρq_tot_before)
        @info "Allocations of the follow and the rescale" follow rescale
        @test follow <= 128
        @test rescale <= 384
    end
end
