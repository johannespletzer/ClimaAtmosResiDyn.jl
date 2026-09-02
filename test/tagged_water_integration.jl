#=
Integration test for tagged prognostic water tracers.

Runs a short 0-moment moist column (DYCOMS_RF02, the same configuration the
tagged-energy restart test uses) with water region tags that form a partition of
unity — an altitude band and its exact complement — plus a `surface_flux` source
tag and its two region-restricted halves, and asserts:

 1. at t = 0, the region tags partition ρq_tot to machine precision;
 2. after solving, every tag stays finite, and its excursion outside [0, ρq_tot]
    stays small against the column scale. The donor-proportional loss rule keeps
    a tag inside those bounds *exactly*, but that is a property of the
    attribution step, asserted at machine precision on the kernel in
    `tagged_water_tests.jl`; across a full timestep the unlimited explicit
    transport of the tags leaks past it (see the comment at the assertion);
 3. the closure residual ρq_tot - Σ region tags stays small (the tags are
    advected vertically on the explicit passive-tracer path while ρq_tot is
    advected implicitly, so the residual is a bounded monitor, not exactly zero);
 4. transport linearity: a source tag split across the partition sums to the
    unrestricted source tag to near machine precision. This is the sharp check —
    a violation is a bug, not expected leakage — and it exercises the
    production, loss and limiter-rescale rules together;
 5. the state survives a checkpoint round-trip bit-for-bit.

The column trips no limiter, so a second setup — a coarse moist sphere with the
SEM quasimonotone limiter on — covers `rescale_water_tags!` and the
`q_tag_fix_<name>` ledger, which are otherwise never exercised. Its tolerances
are much looser than the column's for reasons documented at that testset.

A third setup runs the same column with 1-moment microphysics and checks the
mirrored sedimentation flux, the one process 1M adds. It asserts exact closure of
the flux itself rather than of the end-of-run residual; see the comment at that
testset for why the residual cannot detect this.

Run either through the package test path (`Pkg.test()`, TEST_GROUP
"tagging_water")
or standalone with the pinned CI environment:

    julia +1.11 --project=.buildkite -e 'using Pkg; Pkg.instantiate()'
    julia +1.11 --project=.buildkite test/tagged_water_integration.jl

Do NOT run with an ad-hoc `--project=test` environment: this repo has no
`test/Project.toml`, so that resolves fresh (possibly incompatible) dependency
versions instead of the pinned set.
=#

using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

# An altitude region and its exact complement, so the masks sum to 1 and the
# closure residual is a clean leakage monitor rather than an overlap measure.
upper_region() = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 600.0,
    "width" => 100.0,
)
lower_region() = merge(upper_region(), Dict{String, Any}("above" => false))

# Float64 is required, not cosmetic: the default is Float32 and the machine
# precision assertions below would be meaningless there.
base_config(tags; extra = Dict{String, Any}()) = merge(
    Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        # The DYCOMS geometry, as the shipped configs set it. Without this the
        # 1.5 km boundary-layer profile is extrapolated over the default 30 km
        # column, where pressure runs down to zero and the solve dies in
        # `exner_given_pressure` on a negative pressure of -6.4e-11. That was
        # happening while this file reported every assertion passing, because
        # `solve_atmos!` returns a crash rather than throwing one. It also puts
        # the `z_center = 600` region partition inside the column instead of in
        # its bottom 2%.
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "microphysics_model" => "0M",
        "dt" => "10secs",
        "t_end" => "100secs",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "water_tracers" => tags,
    ),
    extra,
)

@testset "Tagged water integration" begin
    tags = [
        Dict{String, Any}("name" => "upper", "region" => upper_region()),
        Dict{String, Any}("name" => "lower", "region" => lower_region()),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        Dict{String, Any}(
            "name" => "evap_upper",
            "region" => upper_region(),
            "source" => "surface_flux",
        ),
        Dict{String, Any}(
            "name" => "evap_lower",
            "region" => lower_region(),
            "source" => "surface_flux",
        ),
    ]
    config = CA.AtmosConfig(
        base_config(tags);
        job_id = "tagged_water_integration",
    )
    simulation = CA.get_simulation(config)

    Y₀ = deepcopy(simulation.integrator.u)

    # Region tags partition ρq_tot; source tags start at exactly zero
    closure_deviation(Y) =
        maximum(
            abs.(
                parent(Y.c.ρq_tag_upper) .+ parent(Y.c.ρq_tag_lower) .-
                parent(Y.c.ρq_tot),
            ),
        ) / maximum(abs.(parent(Y.c.ρq_tot)))

    FT = eltype(Y₀)
    @test closure_deviation(Y₀) < 100 * eps(FT)
    for name in (:ρq_tag_evap, :ρq_tag_evap_upper, :ρq_tag_evap_lower)
        @test all(iszero, parent(getproperty(Y₀.c, name)))
    end

    # `solve_atmos!` catches a crash and returns `:simulation_crashed` rather
    # than throwing, so a discarded return value lets every assertion below run
    # against a prematurely terminated state. That is not hypothetical: the
    # solve below crashed on a negative pressure while this file reported
    # 87 of 87 assertions passing.
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u

    tag_names = (
        :ρq_tag_upper,
        :ρq_tag_lower,
        :ρq_tag_evap,
        :ρq_tag_evap_upper,
        :ρq_tag_evap_lower,
    )
    # The donor-proportional loss keeps a tag inside [0, ρq_tot] exactly, where
    # the mask-weighted loss the energy tags use would not. That is a property
    # of the attribution step alone, asserted at machine precision on the kernel
    # in `tagged_water_tests.jl`.
    #
    # Over a full timestep the bounds relax. The tags ride the explicit
    # passive-tracer path with no limiter of their own, since
    # `is_tagged_tracer_name` exempts them in `limited_tendencies.jl`, while
    # ρq_tot is advected implicitly. Both bounds leak through the same mechanism
    # that makes `q_tag_res` nonzero. This test checks the leak stays small
    # against the column scale.
    #
    # Measured on this setup, as a fraction of max(ρq_tot): undershoot ~1.4e-7,
    # at the DYCOMS inversion where the `evap` tags have a sharp front.
    # Overshoot ~1.8e-4, worst at the top level, where ρq_tot is three orders of
    # magnitude below its column maximum and the two advection discretizations
    # disagree locally by a few percent, which is a negligible absolute amount
    # of water. The tolerances below leave roughly two orders of headroom over
    # both.
    ρq_tot_scale = maximum(parent(Y.c.ρq_tot))
    for name in tag_names
        tag = parent(getproperty(Y.c, name))
        @test all(isfinite, tag)
        @test minimum(tag) >= -1e-5 * ρq_tot_scale
        @test maximum(tag .- parent(Y.c.ρq_tot)) <= 1e-2 * ρq_tot_scale
    end

    # The residual is a bounded monitor, not an identity: the tags and ρq_tot
    # share their diffusion and hyperdiffusion operators but not their vertical
    # advection split.
    @test closure_deviation(Y) < 5e-3

    # Transport linearity. Production is masked and the masks sum to 1; loss is
    # donor-proportional and the shares sum to the whole tag's share; both
    # transport and the limiter rescale are linear. So this must hold to near
    # machine precision, and any violation is a bug.
    evap = parent(Y.c.ρq_tag_evap)
    evap_split =
        parent(Y.c.ρq_tag_evap_upper) .+ parent(Y.c.ρq_tag_evap_lower)
    scale = maximum(abs.(evap))
    @test scale > 0  # non-vacuous: the surface flux actually moved water
    @test maximum(abs.(evap_split .- evap)) / scale < 1e-10

    # The numerical-correction ledger exists and is finite for every tag. It is
    # identically zero in this column — no limiter or state constraint fires
    # here, so `rescale_water_tags!` is a no-op. The sphere testset below is what
    # actually exercises it.
    for name in tag_names
        @test all(
            isfinite,
            parent(getproperty(simulation.integrator.p.tagging.ᶜwater_fix, name)),
        )
    end
end

# The column above trips no limiter, so `rescale_water_tags!` and its three call
# sites stay unexercised there. The SEM quasimonotone limiter is horizontal, so
# tripping it takes a sphere. This is the coarse geometry the tagged-energy
# integration test uses, h_elem 4, z_elem 10, dt 300secs, made moist and
# 0-moment with the limiter switched on.
#
# Every tolerance here is far looser than the column's, on purpose. The masks
# are a tanh front at 20 degrees latitude, `is_tagged_tracer_name` exempts the
# tags from the limiter by design, and unlimited SEM transport of a sharp front
# overshoots on both sides. The `tropics` and `extratropics` excursions are
# equal and opposite, so their sum still tracks ρq_tot two to three orders of
# magnitude more tightly than either tag tracks its own bounds.
@testset "Tagged water limiter rescale" begin
    region(inside) = Dict{String, Any}(
        "type" => "tanh_latitude",
        "lat_bound" => 20.0,
        "width" => 2.0,
        "inside" => inside,
    )
    tags = [
        Dict{String, Any}("name" => "tropics", "region" => region(true)),
        Dict{String, Any}(
            "name" => "extratropics",
            "region" => region(false),
        ),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        Dict{String, Any}(
            "name" => "evap_tropics",
            "region" => region(true),
            "source" => "surface_flux",
        ),
        Dict{String, Any}(
            "name" => "evap_extratropics",
            "region" => region(false),
            "source" => "surface_flux",
        ),
    ]
    config = CA.AtmosConfig(
        Dict{String, Any}(
            "initial_condition" => "MoistBaroclinicWave",
            "microphysics_model" => "0M",
            "apply_sem_quasimonotone_limiter" => true,
            "h_elem" => 4,
            "z_elem" => 10,
            "dt" => "300secs",
            "t_end" => "3600secs",
            "FLOAT_TYPE" => "Float64",
            "output_default_diagnostics" => false,
            "water_tracers" => tags,
        );
        job_id = "tagged_water_limiter",
    )
    simulation = CA.get_simulation(config)
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u
    ᶜwater_fix = simulation.integrator.p.tagging.ᶜwater_fix

    tag_names = (
        :ρq_tag_tropics,
        :ρq_tag_extratropics,
        :ρq_tag_evap,
        :ρq_tag_evap_tropics,
        :ρq_tag_evap_extratropics,
    )
    ρq_tot = parent(Y.c.ρq_tot)
    scale = maximum(abs.(ρq_tot))

    # The point of this testset: the limiter really did move water, so the
    # rescale path and its ledger are covered rather than merely present. A
    # regression that stopped calling `rescale_water_tags!` would zero these.
    for name in tag_names
        fix = parent(getproperty(ᶜwater_fix, name))
        @test all(isfinite, fix)
        @test maximum(abs.(fix)) > 0
    end

    # Tags stay finite and their excursion outside [0, ρq_tot] stays bounded.
    # Measured worst case is ~2.5e-2 of the column scale, on both sides.
    for name in tag_names
        tag = parent(getproperty(Y.c, name))
        @test all(isfinite, tag)
        @test minimum(tag) >= -1e-1 * scale
        @test maximum(tag .- ρq_tot) <= 1e-1 * scale
    end

    # The partition closes more tightly than any single tag is bounded, because
    # the compensating excursions cancel. It stays a monitor rather than an
    # identity, and its budget is set by what leaves the partition rather than
    # by roundoff. `repair_water_tag_partition!` zeroes the tags of a cell whose
    # negatives outweigh its positives, and that removed water surfaces here by
    # design. See the repair's docstring. `ci 1.10` measures 1.2e-3, nearly two
    # orders inside the 1e-1 excursion bound the tags get above, which is the
    # property asserted here.
    residual =
        ρq_tot .- parent(Y.c.ρq_tag_tropics) .-
        parent(Y.c.ρq_tag_extratropics)
    @test maximum(abs.(residual)) / scale < 1e-2

    # Transport linearity, the sharp check. It holds approximately here rather
    # than exactly, for a reason worth stating. `water_tag_fraction` clamps the
    # donor share to [0, 1]. Once unlimited transport has driven a tag slightly
    # negative, the clamp truncates that tag's loss share, and the two masked
    # halves' shares stop summing to the unrestricted tag's. That guard keeps
    # the rule well posed under drift, so the residual linearity error measures
    # how far the tags have drifted. Measured ~4e-6 against the column's
    # 1e-16.
    evap = parent(Y.c.ρq_tag_evap)
    evap_split =
        parent(Y.c.ρq_tag_evap_tropics) .+
        parent(Y.c.ρq_tag_evap_extratropics)
    evap_scale = maximum(abs.(evap))
    @test evap_scale > 0  # non-vacuous: the surface flux actually moved water
    @test maximum(abs.(evap_split .- evap)) / evap_scale < 1e-4
end

@testset "Tagged water restart round-trip" begin
    tags = [
        Dict{String, Any}("name" => "upper", "region" => upper_region()),
        Dict{String, Any}("name" => "lower", "region" => lower_region()),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ]
    test_dict = base_config(
        tags;
        extra = Dict{String, Any}(
            "t_end" => "20secs",
            "dt_save_state_to_disk" => "20secs",
            "output_dir" => mktempdir(pwd()),
        ),
    )

    simulation = CA.get_simulation(
        CA.AtmosConfig(test_dict; job_id = "tagged_water_restart"),
    )
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success
    Y = simulation.integrator.u

    restart_file = joinpath(simulation.output_dir, "day0.20.hdf5")
    @test isfile(restart_file)

    restarted = CA.get_simulation(
        CA.AtmosConfig(
            merge(test_dict, Dict("restart_file" => restart_file));
            job_id = "tagged_water_restart_read",
        ),
    )
    Y_restart = restarted.integrator.u

    # The tagged fields survive the checkpoint round-trip bit-for-bit, and the
    # masks (rebuilt from the config, not stored) are reproduced
    for name in (:ρq_tag_upper, :ρq_tag_lower, :ρq_tag_evap)
        @test parent(getproperty(Y_restart.c, name)) ==
              parent(getproperty(Y.c, name))
    end
    for name in (:ρq_tag_upper, :ρq_tag_lower)
        @test parent(
            getproperty(restarted.integrator.p.tagging.ᶜwater_masks, name),
        ) == parent(
            getproperty(simulation.integrator.p.tagging.ᶜwater_masks, name),
        )
    end
end

@testset "Tagged water rejects unsupported microphysics" begin
    # The guard lives in the model getter, so it fires while the `AtmosModel` is
    # assembled rather than while the config is parsed. Calling `AtmosTagging`
    # directly tests it at the right level without building a simulation.
    tags = [Dict{String, Any}("name" => "evap", "source" => "surface_flux")]
    for microphysics in ("2M", "dry")
        config = CA.AtmosConfig(
            base_config(
                tags;
                extra = Dict{String, Any}(
                    "microphysics_model" => microphysics,
                ),
            );
            job_id = "tagged_water_reject_$(microphysics)",
        )
        @test_throws ErrorException CA.AtmosTagging(config)
    end

    # ... and both supported schemes are accepted: 0M, where every writer of
    # ρq_tot is local, and 1M, where sedimentation is mirrored per tag
    for microphysics in ("0M", "1M")
        config = CA.AtmosConfig(
            base_config(
                tags;
                extra = Dict{String, Any}(
                    "microphysics_model" => microphysics,
                ),
            );
            job_id = "tagged_water_accept_$(microphysics)",
        )
        @test CA.AtmosTagging(config).water_tagging_model isa
              CA.WaterTaggingModel
    end
end

#=
The sharp test of the mirrored sedimentation flux.

`max|q_tag_res|` at the end of a run is the wrong instrument for this: measured
on a DYCOMS 1M column it is ~1.4e-2 of the column scale with the mirror enabled
and ~1.4e-2 with it disabled, because sedimentation moves under a percent of the
column water there while the residual is dominated by the tags' explicit
vertical advection against ρq_tot's implicit path. A test built on it would pass
whether or not the mirror does anything.

What *is* sharp is the flux itself. Evaluating
`vertical_advection_of_water_tendency!` into a zeroed tendency isolates the
sedimentation increment from every other process, and the partition tags' share
of it must reproduce the parent increment to roundoff — that is the exact-closure
property the donor-cell placement and the share renormalization exist to give,
and nothing else in the timestep can mask or fake it.
=#
@testset "Tagged water 1M sedimentation closure" begin
    tags = [
        Dict{String, Any}("name" => "upper", "region" => upper_region()),
        Dict{String, Any}("name" => "lower", "region" => lower_region()),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ]
    config = CA.AtmosConfig(
        base_config(
            tags;
            extra = Dict{String, Any}(
                "microphysics_model" => "1M",
                "t_end" => "200secs",
            ),
        );
        job_id = "tagged_water_1m_sedimentation",
    )
    simulation = CA.get_simulation(config)
    # Spin up until there is condensate to sediment: at t = 0 the DYCOMS column
    # holds none, and the flux check below would be vacuous.
    result = CA.solve_atmos!(simulation)
    @test result.ret_code == :success

    Y = simulation.integrator.u
    p = simulation.integrator.p
    FT = eltype(Y)

    # 1M carries prognostic condensate, which is what makes sedimentation exist
    for name in (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
        @test hasproperty(Y.c, name)
    end
    @test maximum(parent(Y.c.ρq_rai)) > 0

    Yₜ = similar(Y)
    Yₜ .= zero(FT)
    CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, simulation.integrator.t)

    parent_increment = parent(Yₜ.c.ρq_tot)
    flux_scale = maximum(abs.(parent_increment))
    @test flux_scale > 0  # non-vacuous: water really is sedimenting

    # Exact closure: Σ over the partition tags reproduces the parent flux. This
    # holds to roundoff even where the tags have drifted out of partition,
    # because the shares are renormalized before they weight the flux.
    tag_increment =
        parent(Yₜ.c.ρq_tag_upper) .+ parent(Yₜ.c.ρq_tag_lower)
    @test maximum(abs.(tag_increment .- parent_increment)) / flux_scale <
          100 * eps(FT)

    # The source tag sediments too — it holds real water, which falls out like
    # any other — but it is not a partition member, so it is excluded above
    @test all(isfinite, parent(Yₜ.c.ρq_tag_evap))

    # The share denominator is well posed everywhere, which is what keeps the
    # shares it divides from being amplified. That guarantee is a bound on the
    # *shares*, not on `norm` itself: each clamped donor share is one of the
    # non-negative terms of `norm`, so every share lands in [0, 1] and the
    # partition's shares sum to exactly 1 wherever there is tagged water, however
    # far `norm` sits from 1.
    #
    # `norm` can exceed 1, so pinning it to 1 at roundoff would be asserting
    # exact closure. With the partition tags non-negative after
    # `repair_water_tag_partition!`, `norm` is `Σₖ ρq_tagₖ / ρq_tot` wherever a
    # single tag stays under the parent. That is the pointwise relative closure
    # residual, which the design keeps as a monitor rather than driving to zero.
    # It is a harsher measure than `q_tag_res` above, which normalizes by the
    # column maximum instead of the local `ρq_tot`. Measured overshoot is 6.0e-5
    # on `ci 1.10` and 1.5e-4 on `Downgrade 1.10`. The bound below is a drift
    # monitor with two orders of headroom over the larger.
    norm = parent(p.scratch.ᶜtagging_q_share_norm)
    @test all(isfinite, norm)
    @test minimum(norm) >= 0
    @test maximum(norm) <= 1 + 1e-2

    # The bound that delivers non-amplification, asserted on the shares
    # themselves rather than inferred from `norm`.
    shares = map((:ρq_tag_upper, :ρq_tag_lower)) do name
        CA.water_tag_sediment_share.(
            parent(getproperty(Y.c, name)),
            parent(Y.c.ρq_tot),
            norm,
        )
    end
    for share in shares
        @test minimum(share) >= 0
        @test maximum(share) <= 1
    end

    # ... and the partition's shares sum to one wherever the denominator is
    # positive, and to zero where there is no tagged water to sediment. This is
    # the renormalization the exact-closure assertion above rests on, checked
    # where it is defined rather than through its consequence.
    share_sum = shares[1] .+ shares[2]
    @test all(s -> s == 0 || abs(s - 1) <= 100 * eps(FT), share_sum)

    # Tags stay finite and bounded through active precipitation
    scale = maximum(abs.(parent(Y.c.ρq_tot)))
    for name in (:ρq_tag_upper, :ρq_tag_lower, :ρq_tag_evap)
        tag = parent(getproperty(Y.c, name))
        @test all(isfinite, tag)
        @test minimum(tag) >= -1e-5 * scale
    end
end
