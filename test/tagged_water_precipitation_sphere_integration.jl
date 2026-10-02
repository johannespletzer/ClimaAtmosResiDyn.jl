#=
Integration test for the water tags' rain and snow parts,
`water_tag_precipitation: true`, under the horizontal operators, which a column
does not have (item 10 of the stage 1 tests of design/RAIN_SNOW_TAGS.md on the
record branch, WP4b; items 1 to 9 are in
`tagged_water_precipitation_integration.jl`).

 10. on a small sphere, operator by operator, hyperdiffusion and the viscous
     sponge give the rain and snow parts nothing, as they give rain and snow,
     and the non-precipitating parts sum to the parent's tendency of its
     non-precipitating water, before and after DSS. Each part moves by its
     own gradients, not by a share of the parent's tendency. The parent's
     tendencies and, after two steps, its fields are those without tags, bit
     for bit.

The file builds the sphere twice, with the parts and without tags. It is a
test group of its own because, run after the column's three builds in one
process, the sphere took Julia 1.10 past the 16 GB a GitHub runner has, and
the runner was shut down in the middle of the first sphere's solve.
=#
using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
include("tagged_water_precipitation_common.jl")

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

    # Where the partition holds none of `N`, the tags take no share of
    # `q_tot_r`, and their sum does not follow the parent's hyperdiffusion.
    # `q_tag_leak_hyperdiff` reports that rate. On the test state the
    # partition holds water everywhere, so it is rounding there. With every
    # tag's non-precipitating part emptied, it is the whole reference term.
    # The shares are renormalized over the partition, so a partition that is
    # not closed but holds water still takes all of `q_tot_r`. The sphere has
    # no source tag, so a source tag's own share is not tested here.
    leak(Y) = parent(CA.water_tag_leak!(similar(Y.c.ρ), Y, p, Val(:hyperdiff)))
    @testset "The hyperdiffusion leak where the partition holds no water" begin
        Y_empty = copy(Y_test)
        for name in (:ρq_tag_tropics, :ρq_tag_extratropics)
            parent(getproperty(Y_empty.c, name)) .= 0
        end
        Y_unclosed = copy(Y_test)
        parent(Y_unclosed.c.ρq_tag_tropics) .*= 1.1
        (held, emptied) = (leak(Y_test), leak(Y_empty))
        @test all(isfinite, held)
        @test maximum(abs, emptied) > 0
        @test maximum(abs, held) <= 1e-6 * maximum(abs, emptied)
        @test maximum(abs, leak(Y_unclosed)) <= 1e-6 * maximum(abs, emptied)
        # Where `N` is not negative, the other paths read zero under the key:
        # the vertical diffusion and the sponge leak only its negative part,
        # and EDMF is refused.
        for path in (:vdiff, :hdiff, :sponge)
            @test all(
                iszero,
                parent(CA.water_tag_leak!(similar(Y_empty.c.ρ), Y_empty, p, Val(path))),
            )
        end
        @info "The hyperdiffusion leak, largest" held = maximum(abs, held) emptied =
            maximum(abs, emptied)
    end

    # The leak against the model's own hyperdiffusion. Within 15° of the
    # equator `N` is made negative, and the tags' parts of it are emptied, as
    # option C's closed partition holds them. There the tags take no part of
    # `q_tot_r`, and they do not diffuse `N`'s negative part. The model's leak
    # is the tags' summed tendency minus the parent's, over `ρ`, DSSed as the
    # stepper does. Both read the same precomputed pressure, so the
    # thermodynamic state is not recomputed. The split's residual above is
    # rounding at 1e-15 of the tendencies, and the bound sits well above it.
    # Without the negative part's term the leak would miss the hyperdiffusion
    # of `0.01 q_rai` in the band. The viscous sponge takes the parts on their
    # values and the parent on `N/ρ`, so its leak is the sponge of that same
    # negative part, and it is checked on the same state.
    @testset "The hyperdiffusion and sponge leaks against the model's operators" begin
        Y_band = copy(Y_test)
        ᶜlat = CA.Fields.coordinate_field(Y_band.c).lat
        ᶜin_band = @. abs(ᶜlat) < 15
        @. Y_band.c.ρq_tot = ifelse(
            ᶜin_band,
            Y_band.c.ρq_rai + Y_band.c.ρq_sno - 0.01 * Y_band.c.ρq_rai,
            Y_band.c.ρq_tot,
        )
        for name in (:ρq_tag_tropics, :ρq_tag_extratropics)
            ᶜρq_tag = getproperty(Y_band.c, name)
            @. ᶜρq_tag = ifelse(ᶜin_band, zero(FT), ᶜρq_tag)
        end
        @test minimum(compartments(Y_band).ρq_tag_) < 0
        for (path, operator) in ((:hyperdiff, hyperdiffusion), (:sponge, sponge))
            expected =
                parent(CA.water_tag_leak!(similar(Y_band.c.ρ), Y_band, p, Val(path)))
            Yₜ = operator(Y_band, p)
            CA.dss!(Yₜ, p, t)
            tagsₜ = parent(Yₜ.c.ρq_tag_tropics) .+ parent(Yₜ.c.ρq_tag_extratropics)
            actual = (tagsₜ .- compartments(Yₜ).ρq_tag_) ./ parent(Y_band.c.ρ)
            @test all(isfinite, actual)
            @test maximum(abs, expected) > 0
            mismatch = maximum(abs, actual .- expected) / maximum(abs, expected)
            @test mismatch <= 1e-10
            @info "The $path leak against the model's" largest =
                maximum(abs, expected) mismatch
        end
    end
    # The tags' hyperdiffusion adds one Laplacian and its DSS, from buffers
    # built with the cache. Without tags a call allocates about 17 kB, from
    # the model's own operators. The parts add a few small objects per call,
    # not per point: 736 to 1088 bytes here, against 2464 on `main` at
    # d3c5e42f, on Julia 1.11.
    @testset "The hyperdiffusion allocates about as much as without tags" begin
        function allocations(Y, p)
            (Yₜ, Yₜ_lim) = (zero(Y), zero(Y))
            CA.hyperdiffusion_tendency!(Yₜ, Yₜ_lim, Y, p, t)
            return @allocated CA.hyperdiffusion_tendency!(Yₜ, Yₜ_lim, Y, p, t)
        end
        tagged = allocations(Y_test, p)
        plain = allocations(Y_plain_test, p_plain)
        @info "Allocations of the hyperdiffusion" tagged plain
        @test tagged <= plain + 2048
    end

    # transport-1 of the WP4b stage-1 review (2026-09-30). Each tag's
    # non-precipitating part hyperdiffuses as a passive tracer and takes its
    # share of the reference profile's term outside the operator. The state
    # here is flat: `ρ` and the pressure depend on height only, and `q` is
    # uniform on each level at 0.3 of the reference profile `q_tot_r`. The tags
    # are their masked shares, so each has a sharp front at its band's edge.
    # Hyperdiffusion then has to lower each tag's variance, `∫ χ (ρχ)ₜ < 0`
    # with `χ` the tag's `N/ρ`. The form with the share inside the operator,
    # `∇²(N_tag/ρ - φ q_tot_r)`, is `(1 - q_tot_r/q) = -2.33` times the passive
    # one on this state, so it would raise the variance.
    @testset "The tags' composition mixes down its gradient" begin
        thermo_params = CA.Parameters.thermodynamics_params(p.params)
        Y_flat = copy(Y_test)
        ᶜz = CA.Fields.coordinate_field(Y_flat.c).z
        ᶜp_flat = @. 1e5 * exp(-(ᶜz) / 8000)
        ᶜq = @. 0.3 * CA.q_tot_r(thermo_params, ᶜp_flat)
        @. Y_flat.c.ρ = 1.2 * exp(-(ᶜz) / 8000)
        @. Y_flat.c.ρq_tot = Y_flat.c.ρ * ᶜq
        for name in (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
            parent(getproperty(Y_flat.c, name)) .= 0
        end
        CA.rebuild_tags_from_state!(Y_flat, p.atmos)
        p.precomputed.ᶜp .= ᶜp_flat
        Yₜ = hyperdiffusion(Y_flat, p)
        CA.dss!(Yₜ, p, t)
        for name in (:tropics, :extratropics)
            ᶜρq_tag = getproperty(Y_flat.c, Symbol(:ρq_tag_, name))
            ᶜρq_tagₜ = getproperty(Yₜ.c, Symbol(:ρq_tag_, name))
            @test maximum(abs, parent(ᶜρq_tagₜ)) > 0
            variance_rate = sum(@. ᶜρq_tag / Y_flat.c.ρ * ᶜρq_tagₜ)
            @test variance_rate < 0
            @info "The variance rate of $name on the flat state" variance_rate
        end
        # The parts' sum follows the parent, whose `q` is uniform on each
        # level, so both are rounding here.
        parentₜ = compartments(Yₜ).ρq_tag_
        partsₜ = sphere_part_sum(Yₜ, :ρq_tag_)
        scale = maximum(abs, parent(Yₜ.c.ρq_tag_tropics))
        @test maximum(abs, partsₜ .- parentₜ) <= 1e-10 * scale
        CA.set_precomputed_quantities!(Y_test, p, t)
    end
end
