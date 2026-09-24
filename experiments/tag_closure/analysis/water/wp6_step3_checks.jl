# WP6 step 3 (rev. 2, step 1): the checks the unit and integration tests do not
# make. Written 2026-09-24, not yet run. Run it on a compute node against
# `claude/water-tags-wp6-step3`:
#
#   module load gcc/13.2.0 openmpi/4.1.8-gcc13
#   export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
#   cd <a scratch directory>
#   julia +1.11 --project=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/plan2/wp6s3_testenv \
#       --startup-file=no <record>/experiments/tag_closure/analysis/water/wp6_step3_checks.jl \
#       2>&1 | tee wp6_step3_checks.log
#
# The column is W27's: DYCOMS RF02, prognostic EDMF, 1M, ARS343, the vertical
# water borrowing limiter and the updraft filter on, 30 min. The water tags
# follow the increment, and so do the energy source tags, both with their
# ledgers per tag. For each cadence in (step, stage, dss) it:
#   1. compares every model field with a plain run at the same cadence,
#      isequal;
#   2. recomputes each state ledger's per-step gross and events by stepping by
#      hand, and compares them with the callback's, bit for bit;
#   3. checks that the follower's ledgers of the partition's tags sum to its
#      moved ledger, in both families;
#   4. reports, per ledger, attempted against retained. At `step` it checks
#      attempted >= retained for the ledgers per mechanism.
# Then, at the default cadence under ARS222, a restart from a mid-run
# checkpoint: the state ledgers and every accumulator the checkpoint carries
# end as in the uninterrupted run.
using Test
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)
base = Dict{String, Any}(
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
    "ode_algo" => "ARS343",
    "dt" => "120secs",
    "t_end" => "30mins",
    "tracer_nonnegativity_method" => "vertical_water_borrowing",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
)
tags = Dict{String, Any}(
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
    "water_tag_transport" => "increment",
    "water_tag_ledger_per_tag" => true,
    "energy_source_tags" => [
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
    ],
    "energy_source_tag_offset" => 110495.0,
    "energy_source_tag_transport" => "enthalpy_increment",
    "energy_source_tag_ledger_per_tag" => true,
    "water_closure_check" => Dict{String, Any}("period" => "10mins", "audit" => true),
)
build(dict, job) = CA.get_simulation(
    CA.AtmosConfig(
        merge(dict, Dict{String, Any}("output_dir" => mktempdir(pwd())));
        job_id = job,
    ),
)

function same_model(Y, Y_plain)
    for name in propertynames(Y_plain.c)
        name == :sgsʲs && continue
        @test isequal(parent(getproperty(Y.c, name)), parent(getproperty(Y_plain.c, name)))
    end
    for name in propertynames(Y_plain.c.sgsʲs.:(1))
        @test isequal(
            parent(getproperty(Y.c.sgsʲs.:(1), name)),
            parent(getproperty(Y_plain.c.sgsʲs.:(1), name)),
        )
    end
    @test isequal(parent(Y.f), parent(Y_plain.f))
end
relative_gap(a, b) = maximum(abs, a .- b) / max(maximum(abs, b), floatmin())

for cadence in ("step", "stage", "dss")
    config = merge(base, Dict{String, Any}("update_constrain_state_every" => cadence))
    plain = build(config, "wp6s3_plain_$cadence")
    @test CA.solve_atmos!(plain).ret_code == :success
    @testset "$cadence" begin
        sim = build(merge(config, tags), "wp6s3_$cadence")
        integ = sim.integrator
        (; ledgers, attempted) = integ.p.tagging.tag_ledger_steps
        names = propertynames(ledgers)
        water = integ.p.atmos.water_tagging_model
        energy = integ.p.atmos.energy_source_tagging_model
        @test length(CA.water_tag_per_tag_ledger_names(water)) == 6
        @test length(CA.energy_source_per_tag_ledger_names(energy)) == 6
        L(n) = Float64.(copy(parent(getproperty(integ.u.c, n))))
        total(n) =
            startswith(string(n), "q_tag_") ? copy(parent(integ.u.c.ρq_tot)) :
            copy(parent(integ.u.c.ρe_tot .+ 110495.0 .* integ.u.c.ρ))
        prev = Dict(n => L(n) for n in names)
        gross = Dict(n => zero(prev[n]) for n in names)
        events = Dict(n => zero(prev[n]) for n in names)
        nsteps = 0
        while integ.t < integ.sol.prob.tspan[2]
            CTS.step!(integ)
            nsteps += 1
            for n in names
                now = L(n)
                change = now .- prev[n]
                gross[n] .+= abs.(change)
                events[n] .+= CA.tag_event.(change, total(n))
                prev[n] = now
            end
        end
        println("$cadence: $nsteps steps")
        for n in names
            @test isequal(parent(getproperty(ledgers, n).ᶜgross), gross[n])
            @test isequal(parent(getproperty(ledgers, n).ᶜevents), events[n])
        end
        Y = integ.u
        # The follower's ledgers of the partition sum to its moved ledger.
        water_gap = relative_gap(
            parent(Y.c.q_tag_led_inc_tropo .+ Y.c.q_tag_led_inc_strat),
            parent(Y.c.q_tag_inc_moved),
        )
        energy_gap = relative_gap(
            parent(Y.c.e_src_led_inc_strat .+ Y.c.e_src_led_inc_tropo),
            parent(Y.c.e_src_inc_moved),
        )
        println("  partition ledgers against moved: water $water_gap, energy $energy_gap")
        @test water_gap < 1e-10
        @test energy_gap < 1e-10
        # Attempted against retained, per ledger that has an attempted total.
        for n in propertynames(attempted)
            a = sum(parent(getproperty(attempted, n)))
            r = sum(parent(getproperty(ledgers, n).ᶜgross))
            println(
                "  $n: attempted $a, retained $r, min over the run of L $(minimum(prev[n]))",
            )
            cadence == "step" && CA.is_tag_mechanism_ledger_name(n) &&
                @test a >= r * (1 - 1e-12)
        end
        # Each tag's fix ledger against the cache ledger: equal where only the
        # accepted state's corrections act, apart where a limiter acted on a
        # discarded stage value.
        for tag in (:tropo, :strat, :evap)
            fix = parent(getproperty(integ.p.tagging.ᶜwater_fix, Symbol(:ρq_tag_, tag)))
            led = parent(getproperty(Y.c, Symbol(:q_tag_led_fix_, tag)))
            println(
                "  $tag: max |cache fix − state fix| = $(maximum(abs, fix .- led)), max |state fix| = $(maximum(abs, led))",
            )
        end
        audit = CA.water_tag_extra_audit(Y, integ.p, water, 1.0)
        for key in keys(audit)
            occursin("inventory_fraction", string(key)) &&
                println("  audit $key = $(audit[key])")
        end
        @test audit.ledger_cadence_step == (cadence == "step" ? 1 : 0)
        same_model(Y, plain.integrator.u)
    end
end

@testset "Restart continuation of every accumulator" begin
    config = merge(
        base,
        tags,
        Dict{String, Any}(
            "ode_algo" => "ARS222",
            "t_end" => "20mins",
            "dt_save_state_to_disk" => "10mins",
            "reproducible_restart" => true,
        ),
    )
    whole = build(config, "wp6s3_restart_whole")
    @test CA.solve_atmos!(whole).ret_code == :success
    file = joinpath(whole.output_dir, "day0.600.hdf5")
    isfile(file) || (
        file = first(
            filter(f -> occursin("600", f), readdir(whole.output_dir; join = true)),
        )
    )
    restarted =
        build(
            merge(config, Dict{String, Any}("restart_file" => file)),
            "wp6s3_restart_read",
        )
    @test CA.solve_atmos!(restarted).ret_code == :success
    atmos = whole.integrator.p.atmos
    for n in CA.tag_state_ledger_names(atmos)
        @test isequal(
            parent(getproperty(restarted.integrator.u.c, n)),
            parent(getproperty(whole.integrator.u.c, n)),
        )
    end
    same_model(restarted.integrator.u, whole.integrator.u)
    carried = CA.tag_ledger_checkpoint_fields(whole.integrator.p.tagging)
    restored = CA.tag_ledger_checkpoint_fields(restarted.integrator.p.tagging)
    @test first.(carried) == first.(restored)
    worst = 0.0
    for ((name, a), (_, b)) in zip(carried, restored)
        gap = relative_gap(parent(b), parent(a))
        worst = max(worst, gap)
        gap > 0 && println("  $name: relative gap $gap")
        @test gap <= 1e-12
    end
    println("restart: $(length(carried)) accumulators, largest relative gap $worst")
end
