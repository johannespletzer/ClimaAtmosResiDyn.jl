#=
Unit tests for the rain and snow parts of the water tags,
`water_tag_precipitation: true` (design/RAIN_SNOW_TAGS.md on the record
branch, WP4b, stage 1). Each tag then has a non-precipitating part `N`
(`ρq_tag_<name>`), a rain part `R` (`ρq_rtag_<name>`) and a snow part `S`
(`ρq_stag_<name>`).

What is tested here, without a simulation:

 1. the key, its refusals and the model's type parameter;
 2. the names: which code sees which part (the note's section 5);
 3. the initial state and the denominators (section 6);
 4. the microphysics: the gross flows reproduce the model's own tendencies,
    and the gross and net-flow rules keep each tag's total and each
    compartment's sum (section 9), with the audit (section 12);
 5. the limiters and constraints: clip, rescale, borrowing and a SEM-like
    change keep every part non-negative and each compartment summing to its
    parent (section 8), and the repair per compartment;
 6. the sedimentation and its Jacobian on a small column (sections 5 and 7);
 7. the restart guard (section 11).

`test/tagged_water_precipitation_integration.jl` runs the key in a model.
=#
using Test
import Random
import ClimaAtmos as CA
import ClimaCore.MatrixFields: @name
import CloudMicrophysics.BulkMicrophysicsTendencies as BMT

column_atmos_model(; kwargs...) =
    CA.AtmosModel(CA.ColumnGrid(Float64; z_elem = 10); kwargs...)

region(above, FT = Float64) = CA.TanhAltitudeRegion(FT(750), FT(100), above)
precipitation_tags(FT = Float64) = (
    CA.WaterTag{:low}(region(false, FT)),
    CA.WaterTag{:high}(region(true, FT)),
    CA.WaterTag{:evap}(nothing, :surface_flux),
)

@testset "The key" begin
    @test CA.water_tag_precipitation_from_config(nothing) == false
    @test CA.water_tag_precipitation_from_config(false) == false
    @test CA.water_tag_precipitation_from_config(true) == true
    @test_throws r"must be `true` or `false`" CA.water_tag_precipitation_from_config(
        "true",
    )

    model = CA.WaterTaggingModel(precipitation_tags(); precipitation = true)
    @test CA.has_water_tag_precipitation(model)
    @test !CA.has_water_tag_precipitation(
        CA.WaterTaggingModel(precipitation_tags()),
    )
    @test !CA.has_water_tag_precipitation(nothing)
    # The copies of the parts are stage 3.
    @test_throws r"water_tag_updraft_copy" CA.WaterTaggingModel(
        precipitation_tags();
        precipitation = true,
        updraft_copies = true,
    )
    # 1M only, and no EDMF (stage 2).
    @test isnothing(
        CA.check_water_tag_precipitation_supported(
            CA.NonEquilibriumMicrophysics1M(),
            nothing,
        ),
    )
    @test_throws r"microphysics_model: 1M" CA.check_water_tag_precipitation_supported(
        CA.EquilibriumMicrophysics0M(),
        nothing,
    )
    for turbconv in ("prognostic_edmfx", "edonly_edmfx")
        @test_throws r"refused with `turbconv" CA.check_water_tag_precipitation_supported(
            CA.NonEquilibriumMicrophysics1M(),
            turbconv,
        )
    end

    # Through the configuration.
    tags = [
        Dict{String, Any}(
            "name" => "low",
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 750.0,
                "width" => 100.0,
                "above" => false,
            ),
        ),
    ]
    config(extra) = CA.AtmosConfig(
        merge(
            Dict{String, Any}(
                "config" => "column",
                "microphysics_model" => "1M",
                "output_default_diagnostics" => false,
            ),
            extra,
        );
        job_id = "water_tag_precipitation_key",
    )
    tagging = CA.AtmosTagging(
        config(
            Dict{String, Any}(
                "water_tracers" => tags,
                "water_tag_precipitation" => true,
            ),
        ),
    )
    @test CA.has_water_tag_precipitation(tagging.water_tagging_model)
    @test_throws r"`water_tag_precipitation: true` is set but `water_tracers` is not" CA.AtmosTagging(
        config(Dict{String, Any}("water_tag_precipitation" => true)),
    )
    @test_throws r"needs `microphysics_model: 1M`" CA.AtmosTagging(
        config(
            Dict{String, Any}(
                "water_tracers" => tags,
                "water_tag_precipitation" => true,
                "microphysics_model" => "0M",
            ),
        ),
    )
    # The audit's records need a prefix of their own.
    @test_throws r"`aud_` are reserved" CA.water_tracer_tuple(
        [Dict{String, Any}("name" => "aud_x", "source" => "surface_flux")],
        Float64,
    )
end

@testset "Which code sees which part" begin
    # The design note's section 5.
    for (name, water_tag, part, tagged) in (
        (:ρq_tag_low, true, false, true),
        (:ρq_rtag_low, false, true, true),
        (:ρq_stag_low, false, true, true),
        (:ρq_rai, false, false, false),
    )
        @test CA.is_water_tag_name(name) == water_tag
        @test CA.is_water_precip_part_name(name) == part
        @test CA.is_tagged_tracer_name(name) == tagged
        @test CA._is_water_precip_part_field(CA.MatrixFields.FieldName(name)) ==
              part
        # Every part is a tracer the generic advection moves.
        @test CA.is_tracer_var(name)
    end
    # The limiters skip the parts, the split solver solves them apart, and
    # the audit's records too.
    @test !CA._should_apply_limiter_to_tracer(:ρq_rtag_low, nothing)
    @test CA.is_splittable_jacobian_field(@name(c.ρq_rtag_low))
    @test CA.is_splittable_jacobian_field(@name(c.ρq_stag_low))
    @test CA.is_splittable_jacobian_field(@name(c.q_rtag_aud_low))
    @test CA.is_water_tag_audit_name(:q_stag_aud_low)
    @test !CA.is_water_tag_audit_name(:q_tag_led_rescale)
    # The explicit vertical advection skips only `N` under the increment.
    @test CA._is_water_tag_field(@name(ρq_tag_low))
    @test !CA._is_water_tag_field(@name(ρq_rtag_low))
    # `N` gets its rain's advection back from the part's name.
    @test CA._nonprecip_part_name(@name(ρq_rtag_low)) == @name(ρq_tag_low)
    @test CA._nonprecip_part_name(@name(ρq_stag_low)) == @name(ρq_tag_low)

    model = CA.WaterTaggingModel(precipitation_tags(); precipitation = true)
    @test CA.water_tag_precip_part_state_names(model) == (
        :ρq_rtag_low,
        :ρq_rtag_high,
        :ρq_rtag_evap,
        :ρq_stag_low,
        :ρq_stag_high,
        :ρq_stag_evap,
    )
    @test CA.water_tag_audit_state_names(model) == (
        :q_rtag_aud_low,
        :q_rtag_aud_high,
        :q_rtag_aud_evap,
        :q_stag_aud_low,
        :q_stag_aud_high,
        :q_stag_aud_evap,
    )
    # The partition: the region tags' three parts, not the source tag's.
    @test CA.water_partition_state_names(model) == (
        :ρq_tag_low,
        :ρq_tag_high,
        :ρq_rtag_low,
        :ρq_rtag_high,
        :ρq_stag_low,
        :ρq_stag_high,
    )
    plain = CA.WaterTaggingModel(precipitation_tags())
    @test CA.water_tag_precip_part_state_names(plain) == ()
    @test CA.water_tag_audit_state_names(plain) == ()
    @test CA.water_partition_state_names(plain) ==
          CA.water_region_tag_state_names(plain)

    # On a real state, the tracer lists: the parts are no microphysics
    # tracer, no passive tracer (so no K_h diffusion and no passive block),
    # and only `N` shares the sedimentation's share block.
    CC = CA.ClimaCore
    space = CC.CommonSpaces.ColumnSpace(
        Float64;
        z_min = 0,
        z_max = 1000,
        z_elem = 4,
        staggering = CC.CommonSpaces.CellCenter(),
    )
    names = (
        :ρ,
        :ρe_tot,
        :ρq_tot,
        :ρq_lcl,
        :ρq_icl,
        :ρq_rai,
        :ρq_sno,
        :ρq_tag_low,
        :ρq_rtag_low,
        :ρq_stag_low,
        :ρq_gas,
    )
    Y = CC.Fields.FieldVector(;
        c = similar(
            CC.Fields.coordinate_field(space),
            NamedTuple{names, NTuple{length(names), Float64}},
        ),
    )
    @test !(@name(ρq_rtag_low) in CA.microphysics_tracer_names(Y))
    @test CA.passive_gs_tracer_names(Y) == (@name(ρq_tag_low), @name(ρq_gas))
    @test CA.sedimenting_water_tag_names(Y) == (@name(ρq_tag_low),)
    @test CA.water_precip_part_names(Y) ==
          (@name(ρq_rtag_low), @name(ρq_stag_low))
    @test CA.water_tag_sedimenting_mass_names(Y, model) ==
          (@name(ρq_lcl), @name(ρq_icl))
    @test CA.water_tag_sedimenting_mass_names(Y, plain) ==
          CA.sedimenting_mass_names(Y)
end

@testset "The initial state and the denominators" begin
    for FT in (Float32, Float64)
        tags = precipitation_tags(FT)
        model = CA.WaterTaggingModel(tags; precipitation = true)
        (ρq_tot, ρq_rai, ρq_sno) = (FT(0.012), FT(4e-4), FT(1e-4))
        local_geometry = (; coordinates = (; z = FT(700)))
        state = CA.water_tagging_variables(
            ρq_tot,
            ρq_rai,
            ρq_sno,
            local_geometry,
            model,
        )
        @test propertynames(state) == (
            :ρq_tag_low,
            :ρq_tag_high,
            :ρq_tag_evap,
            CA.water_tag_precip_part_state_names(model)...,
        )
        # Each part is its masked share of its compartment. A source tag
        # starts at zero in every part.
        @test state.ρq_tag_low + state.ρq_tag_high ≈ ρq_tot - ρq_rai - ρq_sno rtol =
            4 * eps(FT)
        @test state.ρq_rtag_low + state.ρq_rtag_high ≈ ρq_rai rtol = 4 * eps(FT)
        @test state.ρq_stag_low + state.ρq_stag_high ≈ ρq_sno rtol = 4 * eps(FT)
        @test iszero(state.ρq_tag_evap) &&
              iszero(state.ρq_rtag_evap) &&
              iszero(state.ρq_stag_evap)
        # Without the key, the five-argument form is the three-argument one.
        plain = CA.WaterTaggingModel(tags)
        @test CA.water_tagging_variables(
            ρq_tot,
            ρq_rai,
            ρq_sno,
            local_geometry,
            plain,
        ) == CA.water_tagging_variables(ρq_tot, local_geometry, plain)
        # The audit's records start at zero, and only with the key.
        audit = CA.water_tag_precipitation_audit_variables(ρq_tot, model)
        @test propertynames(audit) == CA.water_tag_audit_state_names(model)
        @test all(iszero, values(audit))
        @test CA.water_tag_precipitation_audit_variables(ρq_tot, plain) == (;)

        # A bracketed process moves `ρq_tot` only, so under the key its loss
        # leaves each `N` by its share of `ρq_tot - ρq_rai - ρq_sno`.
        ᶜY = (;
            ρq_tot = FT[8, 8, 8, 8],
            ρq_rai = FT[2, 1, 0, 4],
            ρq_sno = FT[2, 1, 0, 0],
            ρq_tag_low = FT[3, 3, 2, 0],
            ρq_tag_high = FT[1, 3, 6, 4],
            ρq_tag_evap = FT[1, 1, 1, 1],
        )
        ᶜmasks = (; ρq_tag_low = FT[1, 1, 0.5, 0], ρq_tag_high = FT[0, 0, 0.5, 1])
        ᶜΔ = FT[-1, -2, -3, -1]
        ᶜYₜ = map(_ -> zeros(FT, 4), (; ρq_tag_low = 0, ρq_tag_high = 0, ρq_tag_evap = 0))
        ᶜparent = CA.water_tag_parent(ᶜY, model)
        @test collect(ᶜparent .+ 0) == FT[4, 6, 8, 4]
        @test CA.water_tag_parent(ᶜY, plain) === ᶜY.ρq_tot
        CA._accumulate_water_tags!(
            ᶜYₜ,
            ᶜY,
            ᶜmasks,
            ᶜΔ,
            :subsidence,
            tags,
            ᶜparent,
        )
        @test ᶜYₜ.ρq_tag_low ≈ ᶜΔ .* ᶜY.ρq_tag_low ./ FT[4, 6, 8, 4]
        # The partition's `N` takes the whole loss where it holds all of its
        # compartment.
        @test ᶜYₜ.ρq_tag_low .+ ᶜYₜ.ρq_tag_high ≈ ᶜΔ
    end
end

# Random states of the 1-moment scheme: warm and cold, sub- and
# supersaturated, with and without rain and snow.
function microphysics_states(FT, n; seed = 1234)
    rng = Random.MersenneTwister(seed)
    params = CA.ClimaAtmosParameters(FT)
    tps = CA.Parameters.thermodynamics_params(params)
    states = map(1:n) do _
        ρ = FT(0.6 + 0.6 * rand(rng))
        T = FT(250 + 45 * rand(rng))
        q_sat = CA.TD.q_vap_saturation(tps, T, ρ)
        q_lcl = FT(rand(rng) < 0.7 ? 1e-3 * rand(rng) : 0)
        q_icl = FT(rand(rng) < 0.6 ? 3e-4 * rand(rng) : 0)
        q_rai = FT(rand(rng) < 0.8 ? 1e-3 * rand(rng) : 0)
        q_sno = FT(rand(rng) < 0.6 ? 5e-4 * rand(rng) : 0)
        q_vap = q_sat * FT(0.8 + 0.25 * rand(rng))
        q_tot = q_vap + q_lcl + q_icl + q_rai + q_sno
        (; ρ, T, q_tot, q_lcl, q_icl, q_rai, q_sno)
    end
    return (params, states)
end

@testset "The microphysics by gross flows" begin
    for FT in (Float32, Float64)
        (params, states) = microphysics_states(FT, 400)
        mp = CA.Parameters.microphysics_1m_params(params)
        tps = CA.Parameters.thermodynamics_params(params)
        dt = FT(60)
        two_way = 0
        for s in states, nsub in (1, 3)
            reference = BMT.bulk_microphysics_tendencies(
                BMT.LinearizedAverage(),
                BMT.Microphysics1Moment(),
                mp, tps, s.ρ, s.T, s.q_tot, s.q_lcl, s.q_icl, s.q_rai, s.q_sno,
                dt, nsub,
            )
            flows = CA.water_tag_1m_flows(
                mp, tps, s.ρ, s.T, s.q_tot, s.q_lcl, s.q_icl, s.q_rai, s.q_sno,
                dt, nsub,
            )
            # The substeps repeat CloudMicrophysics' arithmetic, so the net
            # tendencies are the model's. The compiler may fuse a `muladd`
            # in one and not the other, so they agree to the rounding of
            # the step's water over the step, not bit for bit.
            gross =
                abs(flows.NR) + abs(flows.NS) + abs(flows.RN) +
                abs(flows.RS) + abs(flows.SR) + abs(flows.SN)
            water = s.q_lcl + s.q_icl + s.q_rai + s.q_sno
            tolerance = 64 * eps(FT) * (water / dt + gross)
            @test abs(flows.dq_rai_dt - reference.dq_rai_dt) <= tolerance
            @test abs(flows.dq_sno_dt - reference.dq_sno_dt) <= tolerance
            # The flows' net is the net, to the same rounding.
            @test abs(
                (flows.NR + flows.SR - flows.RN - flows.RS) - reference.dq_rai_dt,
            ) <= tolerance
            @test abs(
                (flows.NS + flows.RS - flows.SN - flows.SR) - reference.dq_sno_dt,
            ) <= tolerance
            # Each flow runs from its donor.
            @test all(
                f -> f >= -tolerance,
                (flows.NR, flows.NS, flows.RN, flows.RS, flows.SR, flows.SN),
            )
            two_way += (flows.NR > 0 && flows.RN > 0)
        end
        # The states hold rain that forms and evaporates at once, which the
        # net-flow rule cannot tell apart.
        @test two_way > 10

        # The scheme tag goes through the model's quadrature evaluator, over
        # the same points and weights as the tendencies.
        quad = CA.SGSQuadrature(FT; quadrature_order = 3)
        s = states[findfirst(s -> s.q_rai > 0 && s.q_lcl > 0, states)]
        corr_Tq = FT(0.6)
        args = (
            quad, mp, tps, s.ρ, s.T, s.q_tot, s.q_lcl, s.q_icl, s.q_rai, s.q_sno,
            FT(1), FT(1e-7), corr_Tq, s.q_lcl + s.q_icl, FT(1), dt, 2,
        )
        reference = CA.microphysics_tendencies_1m(BMT.Microphysics1Moment(), args...)
        flows = CA.microphysics_tendencies_1m(CA.WaterTagFlows1M(), args...)
        @test keys(flows) == CA.WATER_TAG_FLOW_NAMES
        tolerance =
            64 * eps(FT) * (
                (s.q_lcl + s.q_icl + s.q_rai + s.q_sno) / dt +
                sum(abs, values(flows))
            )
        @test abs(
            (flows.NR + flows.SR - flows.RN - flows.RS) - reference.dq_rai_dt,
        ) <= tolerance
        @test abs(
            (flows.NS + flows.RS - flows.SN - flows.SR) - reference.dq_sno_dt,
        ) <= tolerance
    end

    # The attribution rules, on random flows, pools and shares.
    rng = Random.MersenneTwister(99)
    Δt = 60.0
    for _ in 1:2000
        # The pools, and some of them empty at the start.
        (qN, qR, qS) =
            (1e-2 * rand(rng), 1e-3 * rand(rng), 1e-3 * rand(rng)) .*
            (1, rand(rng) < 0.7, rand(rng) < 0.7)
        # Flows, with none out of a pool that holds nothing and takes nothing
        # in, as the model's step gives.
        f = 1e-7 .* rand(rng, 6) .* (rand(rng, 6) .< 0.7)
        (NR, NS, RN, RS, SR, SN) = f
        # Twice, since each check can empty the other's inflow. Rain and snow
        # that are both empty and take nothing from `N` have nothing to pass
        # between them either.
        for _ in 1:2
            if qR == 0 && qS == 0 && NR + NS == 0
                (RN, RS, SR, SN) = (0.0, 0.0, 0.0, 0.0)
            end
            if qR == 0 && NR + SR == 0
                (RN, RS) = (0.0, 0.0)
            end
            if qS == 0 && NS + RS == 0
                (SN, SR) = (0.0, 0.0)
            end
        end
        F = (; NR, NS, RN, RS, SR, SN)
        # A partition of three tags: shares of each compartment summing to 1,
        # or to 0 where the compartment is empty.
        shares = map((qN, qR, qS)) do q
            w = rand(rng, 3)
            q > 0 ? w ./ sum(w) : zeros(3)
        end
        dq_rai = (F.NR + F.SR) - (F.RN + F.RS)
        dq_sno = (F.NS + F.RS) - (F.SN + F.SR)
        args(i) = (qN, qR, qS, Δt, shares[1][i], shares[2][i], shares[3][i])
        changes = map(i -> CA.water_tag_microphysics_change(F, dq_rai, dq_sno, args(i)...), 1:3)
        scale = 1e-7
        # Each tag keeps its total.
        @test all(c -> abs(sum(c)) <= 1e-14 * scale, changes)
        # The partition's parts take the compartments' changes, even where a
        # compartment was empty at the start and water passed through it.
        @test sum(c -> c[2], changes) ≈ dq_rai atol = 1e-14 * scale
        @test sum(c -> c[3], changes) ≈ dq_sno atol = 1e-14 * scale
        @test sum(c -> c[1], changes) ≈ -(dq_rai + dq_sno) atol = 1e-14 * scale
        # The pool shares sum to one over the partition wherever the pool
        # holds water or takes some in, and lie in [0, 1].
        pools = map(i -> CA.water_tag_pool_shares(F, args(i)...), 1:3)
        full = (
            true,
            qR + Δt * (F.NR + F.SR) > 0,
            qS + Δt * (F.NS + F.RS) > 0,
        )
        for k in 1:3
            full[k] && @test sum(ψ -> ψ[k], pools) ≈ 1 atol = 1e-12
            @test all(ψ -> -1e-15 <= ψ[k] <= 1 + 1e-12, pools)
        end
        # The net-flow rule keeps each tag's total, and the compartments'
        # sums wherever the losing compartments are tagged.
        net = map(1:3) do i
            CA.water_tag_net_flow_change(
                -(dq_rai + dq_sno),
                dq_rai,
                dq_sno,
                shares[1][i],
                shares[2][i],
                shares[3][i],
            )
        end
        @test all(c -> abs(sum(c)) <= 1e-14 * scale, net)
        # The audit is their difference.
        for i in 1:3
            audit = CA.water_tag_microphysics_audit(F, dq_rai, dq_sno, args(i)...)
            @test audit[1] ≈ net[i][2] - changes[i][2] atol = 1e-14 * scale
            @test audit[2] ≈ net[i][3] - changes[i][3] atol = 1e-14 * scale
        end
    end
    # A compartment that holds much more than passes through it passes on its
    # own composition.
    F = (; NR = 2e-9, NS = 0.0, RN = 1.5e-9, RS = 0.0, SR = 0.0, SN = 0.0)
    ψ = CA.water_tag_pool_shares(F, 1e-2, 1e-3, 0.0, 60.0, 0.3, 0.6, 0.0)
    @test ψ[1] ≈ 0.3 rtol = 1e-4
    @test ψ[2] ≈ 0.6 rtol = 1e-3
    # Rain that forms and evaporates in one step, in a cell without rain at
    # the start: it passes on the composition it formed with.
    ψ = CA.water_tag_pool_shares(F, 1e-2, 0.0, 0.0, 60.0, 0.3, 0.0, 0.0)
    @test ψ[2] ≈ ψ[1]
    (ΔN, ΔR, ΔS) = CA.water_tag_microphysics_change(
        F,
        F.NR - F.RN,
        0.0,
        1e-2,
        0.0,
        0.0,
        60.0,
        0.3,
        0.0,
        0.0,
    )
    @test ΔR ≈ 0.3 * (F.NR - F.RN) rtol = 1e-6
    @test ΔN ≈ -ΔR
    # Two-way flow with different compositions: rain forms from `N` of one
    # composition and evaporates with rain of another. The net-flow rule
    # gives the evaporated water the rain's composition only for the net.
    F = (; NR = 2.0, NS = 0.0, RN = 1.5, RS = 0.0, SR = 0.0, SN = 0.0)
    (gN, gR, gS) = CA.water_tag_gross_flow_change(F, 1.0, 0.0, 0.0)
    @test (gN, gR, gS) == (-2.0, 2.0, 0.0)
    (nN, nR, nS) = CA.water_tag_net_flow_change(-0.5, 0.5, 0.0, 1.0, 0.0, 0.0)
    @test (nN, nR, nS) == (-0.5, 0.5, 0.0)
    # With a large rain pool of the other composition, the rain that
    # evaporates is nearly all of that composition, and the audit records the
    # difference from the net-flow rule.
    audit = CA.water_tag_microphysics_audit(
        F,
        0.5,
        0.0,
        1e6,
        1e6,
        0.0,
        1e-6,
        1.0,
        0.0,
        0.0,
    )
    @test audit[1] ≈ -1.5 rtol = 1e-5
    @test audit[2] == 0
    # The guards: a losing compartment no tag holds gives nothing; no loss
    # moves nothing; without flows the net-flow rule is the fallback.
    @test CA.water_tag_net_flow_change(1.0, -1.0, 0.0, 0.3, 0.0, 0.0) ==
          (0.0, 0.0, 0.0)
    @test CA.water_tag_net_flow_change(0.0, 0.0, 0.0, 0.3, 0.2, 0.1) ==
          (0.0, 0.0, 0.0)
    zero_flows = NamedTuple{CA.WATER_TAG_FLOW_NAMES}(ntuple(_ -> 0.0, 6))
    @test all(
        CA.water_tag_microphysics_change(
            zero_flows,
            0.5,
            -0.2,
            1e-2,
            1e-3,
            1e-3,
            60.0,
            0.3,
            0.4,
            0.6,
        ) .≈ CA.water_tag_net_flow_change(-0.3, 0.5, -0.2, 0.3, 0.4, 0.6),
    )
    # Every pool empty: the start shares.
    @test CA.water_tag_pool_shares(zero_flows, 0.0, 0.0, 0.0, 60.0, 0.3, 0.4, 0.6) ==
          (0.3, 0.4, 0.6)
end

# A cell state of three tags (two partition tags and a source tag), their
# three parts, and the cache the corrections use.
function correction_setup(FT, rng, n)
    tags = precipitation_tags(FT)
    model = CA.WaterTaggingModel(tags; precipitation = true)
    rai = FT.(1e-3 .* rand(rng, n))
    sno = FT.(5e-4 .* rand(rng, n))
    nonprecip = FT.(1e-2 .* (0.5 .+ rand(rng, n)))
    share = FT.(rand(rng, n))
    ᶜY = (;
        ρq_tot = nonprecip .+ rai .+ sno,
        ρq_rai = copy(rai),
        ρq_sno = copy(sno),
        ρq_tag_low = share .* nonprecip,
        ρq_tag_high = (1 .- share) .* nonprecip,
        ρq_tag_evap = FT(0.2) .* nonprecip,
        ρq_rtag_low = FT(0.3) .* rai,
        ρq_rtag_high = FT(0.7) .* rai,
        ρq_rtag_evap = FT(0.1) .* rai,
        ρq_stag_low = FT(0.6) .* sno,
        ρq_stag_high = FT(0.4) .* sno,
        ρq_stag_evap = FT(0.1) .* sno,
        q_tag_led_rescale = zeros(FT, n),
        q_tag_led_empty = zeros(FT, n),
        q_tag_led_repair = zeros(FT, n),
        q_tag_led_repairnet = zeros(FT, n),
    )
    per_tag(T) = (;
        ρq_tag_low = zeros(T, n),
        ρq_tag_high = zeros(T, n),
        ρq_tag_evap = zeros(T, n),
    )
    tagging = (;
        ᶜwater_fix = per_tag(FT),
        ᶜwater_fix_gross = per_tag(Float64),
        ᶜwater_fix_count = per_tag(Float64),
        ᶜwater_pos = zeros(FT, n),
        ᶜwater_neg = zeros(FT, n),
        ᶜwater_pos_2 = zeros(FT, n),
        ᶜwater_shift = zeros(FT, n),
        ᶜwater_rai_before = copy(ᶜY.ρq_rai),
        ᶜwater_sno_before = copy(ᶜY.ρq_sno),
    )
    p = (; tagging, atmos = (; water_tagging_model = model))
    return (; Y = (; c = ᶜY), p, model)
end

partition_sum(ᶜY, prefix) =
    getproperty(ᶜY, Symbol(prefix, :low)) .+ getproperty(ᶜY, Symbol(prefix, :high))
tag_total(ᶜY, name) =
    getproperty(ᶜY, Symbol(:ρq_tag_, name)) .+
    getproperty(ᶜY, Symbol(:ρq_rtag_, name)) .+
    getproperty(ᶜY, Symbol(:ρq_stag_, name))
nonprecip_parent(ᶜY) = ᶜY.ρq_tot .- ᶜY.ρq_rai .- ᶜY.ρq_sno

@testset "The limiters and constraints follow each compartment" begin
    for FT in (Float32, Float64)
        rng = Random.MersenneTwister(7)
        n = 200
        closes(a, b) = maximum(abs, a .- b) <= 64 * eps(FT) * maximum(abs, b)
        function check(ᶜY)
            @test closes(partition_sum(ᶜY, :ρq_rtag_), ᶜY.ρq_rai)
            @test closes(partition_sum(ᶜY, :ρq_stag_), ᶜY.ρq_sno)
            @test closes(partition_sum(ᶜY, :ρq_tag_), nonprecip_parent(ᶜY))
            for name in propertynames(ᶜY)
                CA.is_tagged_tracer_name(name) || continue
                @test minimum(getproperty(ᶜY, name)) >= 0
            end
        end

        # 1. The grid-mean constraint's rescale of the condensates, at fixed
        # `ρq_tot`, and a clip of rain to zero.
        (; Y, p, model) = correction_setup(FT, rng, n)
        ᶜY = Y.c
        totals = map(name -> tag_total(ᶜY, name), (:low, :high, :evap))
        ratio = FT.(0.5 .+ 0.5 .* rand(rng, n))
        @. ᶜY.ρq_rai *= ratio
        @. ᶜY.ρq_sno *= ratio
        ᶜY.ρq_rai[1:10] .= 0
        CA._rescale_water_tag_parts!(Y, p, copy(ᶜY.ρq_tot), model, Val(false))
        check(ᶜY)
        # A clip to zero returns each tag's rain to its `N`.
        @test all(iszero, ᶜY.ρq_rtag_low[1:10])
        @test all(iszero, ᶜY.ρq_rtag_evap[1:10])
        # The moves are within each tag, so its total does not change.
        for (name, total) in zip((:low, :high, :evap), totals)
            @test tag_total(ᶜY, name) ≈ total rtol = 8 * eps(FT)
        end
        @test all(iszero, p.tagging.ᶜwater_fix.ρq_tag_low)
        @test maximum(p.tagging.ᶜwater_fix_gross.ρq_tag_low) > 0
        # The snapshots moved on, so a second call moves nothing.
        before = deepcopy(ᶜY)
        CA._rescale_water_tag_parts!(Y, p, copy(ᶜY.ρq_tot), model, Val(false))
        @test ᶜY == before

        # 2. Vertical borrowing and a SEM-like limiter: `ρq_tot`, rain and snow
        # change together, with both signs.
        (; Y, p, model) = correction_setup(FT, rng, n)
        ᶜY = Y.c
        ᶜρq_tot_before = copy(ᶜY.ρq_tot)
        @. ᶜY.ρq_rai = max(ᶜY.ρq_rai * FT(1 + 0.4 * (rand(rng) - 0.5)), 0)
        @. ᶜY.ρq_sno = max(ᶜY.ρq_sno * FT(1 + 0.4 * (rand(rng) - 0.5)), 0)
        @. ᶜY.ρq_tot = ᶜY.ρq_tot * FT(1 + 0.02 * (rand(rng) - 0.5))
        CA._rescale_water_tags!(Y, p, ᶜρq_tot_before, model)
        check(ᶜY)
        # The partition's total change is the parent's.
        @test p.tagging.ᶜwater_fix.ρq_tag_low .+ p.tagging.ᶜwater_fix.ρq_tag_high ≈
              ᶜY.ρq_tot .- ᶜρq_tot_before rtol = 64 * eps(FT)

        # 3. A compartment that grows takes `N`'s composition.
        (; Y, p, model) = correction_setup(FT, rng, 3)
        ᶜY = Y.c
        low_share = ᶜY.ρq_tag_low ./ nonprecip_parent(ᶜY)
        rain_before = copy(ᶜY.ρq_rtag_low)
        parent_before = copy(ᶜY.ρq_rai)
        ᶜY.ρq_rai .+= FT(1e-4)
        growth = ᶜY.ρq_rai .- parent_before
        CA._rescale_water_tag_parts!(Y, p, copy(ᶜY.ρq_tot), model, Val(false))
        @test ᶜY.ρq_rtag_low .- rain_before ≈ growth .* low_share rtol = 64 * eps(FT)
        check(ᶜY)

        # 4. The repair per compartment: a negative rain part is repaired
        # among the rain parts, which keep their sum.
        (; Y, p, model) = correction_setup(FT, rng, n)
        ᶜY = Y.c
        ᶜY.ρq_rtag_low[5] = -FT(0.1) * ᶜY.ρq_rai[5]
        ᶜY.ρq_rtag_high[5] = FT(1.1) * ᶜY.ρq_rai[5]
        rain_sum = partition_sum(ᶜY, :ρq_rtag_)
        CA._repair_water_tag_partition!(Y, p, model)
        @test minimum(ᶜY.ρq_rtag_low) >= 0
        @test partition_sum(ᶜY, :ρq_rtag_) ≈ rain_sum rtol = 8 * eps(FT)
        @test ᶜY.q_tag_led_repair[5] > 0
    end
end

@testset "The parts fall as their species, and the Jacobian" begin
    # The model's sedimentation of each part on a small column, with a cache
    # that holds what it reads, as `tagged_water_tests.jl` builds it.
    CC = CA.ClimaCore
    MF = CA.MatrixFields
    Geometry = CC.Geometry
    FT = Float64
    column(staggering) = CC.CommonSpaces.ColumnSpace(
        FT;
        z_min = 0,
        z_max = 2000,
        z_elem = 16,
        staggering,
    )
    ᶜspace = column(CC.CommonSpaces.CellCenter())
    ᶠspace = column(CC.CommonSpaces.CellFace())
    ᶜz = CC.Fields.coordinate_field(ᶜspace).z
    tags = precipitation_tags(FT)
    model = CA.WaterTaggingModel(tags; precipitation = true)
    masses = (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
    velocities = (:ᶜwₗ, :ᶜwᵢ, :ᶜwᵣ, :ᶜwₛ)
    ᶜnames = (
        :ρ,
        :ρe_tot,
        :ρq_tot,
        masses...,
        :ρq_tag_low,
        :ρq_tag_high,
        :ρq_tag_evap,
        CA.water_tag_precip_part_state_names(model)...,
    )
    Y = CC.Fields.FieldVector(;
        c = similar(
            CC.Fields.coordinate_field(ᶜspace),
            NamedTuple{ᶜnames, NTuple{length(ᶜnames), FT}},
        ),
        f = similar(
            CC.Fields.coordinate_field(ᶠspace),
            NamedTuple{(:u₃,), Tuple{FT}},
        ),
    )
    fill!(parent(Y.f), 0)
    @. Y.c.ρ = FT(1.2) * exp(-(ᶜz) / 8000)
    @. Y.c.ρe_tot = Y.c.ρ * FT(2.5e5)
    @. Y.c.ρq_tot = Y.c.ρ * (FT(0.012) - FT(4e-6) * ᶜz)
    @. Y.c.ρq_lcl = Y.c.ρ * FT(2e-4) * (1 + sin(ᶜz / 300))
    @. Y.c.ρq_icl = Y.c.ρ * FT(5e-5) * (1 + cos(ᶜz / 400))
    @. Y.c.ρq_rai = Y.c.ρ * FT(3e-4) * (1 + sin(ᶜz / 200 + 1))
    @. Y.c.ρq_sno = Y.c.ρ * FT(1e-4) * (1 + cos(ᶜz / 250 + 2))
    ᶜbelow = @. (1 - tanh((ᶜz - 750) / 100)) / 2
    ᶜnonprecip = @. Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno
    @. Y.c.ρq_tag_low = ᶜbelow * ᶜnonprecip
    @. Y.c.ρq_tag_high = (1 - ᶜbelow) * ᶜnonprecip
    @. Y.c.ρq_tag_evap = FT(0.3) * ᶜnonprecip
    @. Y.c.ρq_rtag_low = FT(0.2) * Y.c.ρq_rai
    @. Y.c.ρq_rtag_high = FT(0.8) * Y.c.ρq_rai
    @. Y.c.ρq_rtag_evap = FT(0.1) * Y.c.ρq_rai
    @. Y.c.ρq_stag_low = FT(0.5) * Y.c.ρq_sno
    @. Y.c.ρq_stag_high = FT(0.5) * Y.c.ρq_sno
    @. Y.c.ρq_stag_evap = FT(0.1) * Y.c.ρq_sno
    ᶜvelocity(scale) = @. FT(scale) * (1 + ᶜz / 2000)
    precomputed = (;
        ᶜwₗ = ᶜvelocity(0.01),
        ᶜwᵢ = ᶜvelocity(0.2),
        ᶜwᵣ = ᶜvelocity(4),
        ᶜwₛ = ᶜvelocity(1),
        ᶜT = fill(FT(275), ᶜspace),
        ᶜu = fill(Geometry.Covariant123Vector(FT(0), FT(0), FT(0)), ᶜspace),
    )
    scratch = (;
        ᶜbidiagonal_adjoint_matrix_c3 = CC.Fields.Field(
            MF.BidiagonalMatrixRow{typeof(Geometry.Covariant3Vector(FT(0))')},
            ᶜspace,
        ),
        ᶠband_matrix_wvec = similar(
            Y.f,
            MF.BandMatrixRow{
                CC.Utilities.PlusHalf{Int64}(0),
                1,
                Geometry.WVector{FT},
            },
        ),
        ᶜtagging_q_share_norm = similar(Y.c.ρ),
        CA._water_tag_precipitation_scratch(Y, model)...,
    )
    p = (;
        atmos = (;
            microphysics_model = CA.NonEquilibriumMicrophysics1M(),
            water_tagging_model = model,
        ),
        params = CA.ClimaAtmosParameters(FT),
        core = (; ᶜΦ = @. FT(9.81) * ᶜz),
        precomputed,
        scratch,
    )
    matrix = MF.FieldMatrix(
        CA.sedimentation_jacobian_blocks(Y, p.atmos, CA.UseDerivative())...,
    )
    c(n) = MF.FieldName(:c, n)
    # `N` has cross blocks to the cloud only; the parts have none.
    @test haskey(matrix, (c(:ρq_tag_low), c(:ρq_lcl)))
    @test !haskey(matrix, (c(:ρq_tag_low), c(:ρq_rai)))
    @test haskey(matrix, (c(:ρq_rtag_low), c(:ρq_rtag_low)))
    @test !haskey(matrix, (c(:ρq_rtag_low), c(:ρq_rai)))
    CA.update_sedimentation_jacobian!(matrix, Y, p, FT(60), CA.UseDerivative())
    # Each part's block is its species', value for value.
    for name in (:ρq_rtag_low, :ρq_rtag_high, :ρq_rtag_evap)
        @test isequal(
            parent(matrix[c(name), c(name)]),
            parent(matrix[c(:ρq_rai), c(:ρq_rai)]),
        )
    end
    for name in (:ρq_stag_low, :ρq_stag_evap)
        @test isequal(
            parent(matrix[c(name), c(name)]),
            parent(matrix[c(:ρq_sno), c(:ρq_sno)]),
        )
    end
    # The partition's cloud cross blocks sum to the parent's.
    for mass in (:ρq_lcl, :ρq_icl)
        parent_block = matrix[c(:ρq_tot), c(mass)]
        ᶜpartition_block = copy(parent_block)
        @. ᶜpartition_block =
            matrix[c(:ρq_tag_low), c(mass)] + matrix[c(:ρq_tag_high), c(mass)]
        @test maximum(abs, parent(ᶜpartition_block) .- parent(parent_block)) <=
              1e-12 * maximum(abs, parent(parent_block))
    end

    # The tendencies: each species' flux, as the model computes it
    # (`vertical_advection_of_water_tendency!`). The partition's parts of rain
    # and snow take their species' flux, and its `N` the cloud's.
    ᶜJ = CC.Fields.local_geometry_field(Y.c).J
    ᶠJ = CC.Fields.local_geometry_field(Y.f).J
    ᶠρ = @. CA.ᶠinterp(Y.c.ρ * ᶜJ) / ᶠJ
    CA.water_tag_share_norm!(p, Y)
    for (mass, velocity) in zip(masses, velocities)
        Yₜ = similar(Y)
        fill!(parent(Yₜ), 0)
        ᶜρqₚ = getproperty(Y.c, mass)
        ᶜw = getproperty(precomputed, velocity)
        ᶜq = @. ᶜρqₚ / Y.c.ρ
        CA.sediment_water_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶠρ, MF.FieldName(mass))
        ᶜflux = @. -1 * CA.ᶜprecipdivᵥ(
            ᶠρ * CA.ᶠtop_bias(Geometry.WVector(-(ᶜw)) * ᶜq),
        )
        scale = maximum(abs, parent(ᶜflux))
        prefix =
            mass == :ρq_rai ? :ρq_rtag_ : mass == :ρq_sno ? :ρq_stag_ : :ρq_tag_
        partition = parent(getproperty(Yₜ.c, Symbol(prefix, :low))) .+
                    parent(getproperty(Yₜ.c, Symbol(prefix, :high)))
        @test maximum(abs, partition .- parent(ᶜflux)) <= 1e-12 * scale
        # The other parts take nothing of this species.
        for other in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
            other == prefix && continue
            @test all(iszero, parent(getproperty(Yₜ.c, Symbol(other, :low))))
        end
    end
end

@testset "The restart guard with rain and snow parts" begin
    context = CA.ClimaComms.context()
    HDF5 = CA.InputOutput.HDF5
    tags = precipitation_tags()
    keyed = CA.WaterTaggingModel(tags; precipitation = true)
    plain = CA.WaterTaggingModel(tags)
    atmos(model) = (; water_tagging_model = model)
    ledgers =
        map(_ -> 0.0, NamedTuple{CA.WATER_TAG_MECHANISM_NAMES}(CA.WATER_TAG_MECHANISM_NAMES))
    state(names) = (;
        c = (;
            NamedTuple{(:ρ, :ρq_tot, names...)}(Tuple(zeros(2 + length(names))))...,
            ledgers...,
        ),
    )
    tag_names = CA.water_tag_state_names(keyed)
    keyed_state = (;
        c = (;
            state((tag_names..., CA.water_tag_precip_part_state_names(keyed)...)).c...,
            map(
                _ -> 0.0,
                NamedTuple{CA.water_tag_audit_state_names(keyed)}(
                    CA.water_tag_audit_state_names(keyed),
                ),
            )...,
        ),
    )
    plain_state = state(tag_names)
    directory = mktempdir()
    function checkpoint(model, name; edit = file -> nothing)
        path = joinpath(directory, "$name.hdf5")
        writer = CA.InputOutput.HDF5Writer(path, context)
        CA.write_water_tag_checkpoint_attributes!(writer.file, model)
        edit(writer.file)
        Base.close(writer)
        return path
    end
    check(path, model, Y) =
        CA.check_water_tag_checkpoint(path, atmos(model), Y, context)

    written = checkpoint(keyed, "keyed")
    @test isnothing(check(written, keyed, keyed_state))
    # A checkpoint with the parts does not restart without the key, and one
    # without them does not restart with it. The fields tell, whatever the
    # attributes say.
    @test_throws r"rain and snow parts.*`water_tag_precipitation`" check(
        written,
        plain,
        keyed_state,
    )
    @test_throws r"rain and snow parts.*`water_tag_precipitation`" check(
        checkpoint(plain, "plain"),
        keyed,
        plain_state,
    )
    # The audit's records come with the parts.
    no_audit = state((tag_names..., CA.water_tag_precip_part_state_names(keyed)...))
    @test_throws r"microphysics audit.*`water_tag_precipitation`" check(
        written,
        keyed,
        no_audit,
    )
    # The attribute is checked too.
    flipped = checkpoint(
        keyed,
        "flipped";
        edit = file -> begin
            HDF5.delete_attribute(file, "water_tag_precipitation")
            HDF5.write_attribute(file, "water_tag_precipitation", 0)
        end,
    )
    @test_throws r"written with `water_tag_precipitation: false`" check(
        flipped,
        keyed,
        keyed_state,
    )
    # A version 1 checkpoint predates the key, so it restarts without it.
    version_1 = checkpoint(
        plain,
        "version_1";
        edit = file -> begin
            HDF5.delete_attribute(file, "water_tag_checkpoint")
            HDF5.write_attribute(file, "water_tag_checkpoint", 1)
            HDF5.delete_attribute(file, "water_tag_precipitation")
        end,
    )
    @test isnothing(check(version_1, plain, plain_state))
    @test CA.WATER_TAG_CHECKPOINT_VERSION == 2
end
