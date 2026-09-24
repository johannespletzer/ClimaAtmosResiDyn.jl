# WP6 step 2: checks the tests do not make (reviewer's script, not run by the reviewer).
#
#   export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
#   cd /dss/dsshome1/0D/di38kez/.claude/jobs/eb4ea50c/tmp/wp6_review
#   julia +1.11 --project=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3/wp6/testenv \
#       --startup-file=no wp6_cadence_checks.jl 2>&1 | tee wp6_cadence_checks.log
#
# For each cadence in (stage, dss), under ARS343 with the vertical water
# borrowing limiter on and the updraft filter on, and for two tag setups
# (the follower, and the copies), it:
#   1. compares every model field with a plain run at the same cadence, isequal;
#   2. recomputes the per-step gross by stepping by hand and compares it with the
#      callback's, bit for bit (catches a gross per stage, a missed step, a
#      callback at another cadence);
#   3. reports the smallest value of each "moved" ledger (a transfer ledger
#      below zero shows a negative stage weight at work) and attempted/retained.
# Then a restart continuation at the default cadence: the state ledgers of a run
# restarted from a mid-run checkpoint equal the uninterrupted run's, bit for bit.
using Test
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude", "z_center" => 750.0, "width" => 100.0, "above" => above)
tracers = [
    Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
    Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
    Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
]
base = Dict{String, Any}(
    "config" => "column", "initial_condition" => "DYCOMS_RF02",
    "turbconv" => "prognostic_edmfx", "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized", "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true, "edmfx_sgs_diffusive_flux" => true,
    "edmfx_nh_pressure" => true, "edmfx_vertical_diffusion" => true,
    "edmfx_filter" => true, "prognostic_tke" => true,
    "microphysics_model" => "1M", "fixed_terminal_velocity_liquid" => false,
    "z_elem" => 30, "z_max" => 1500.0, "z_stretch" => false,
    "perturb_initstate" => false, "rad" => "DYCOMS",
    "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
    "ode_algo" => "ARS343", "dt" => "120secs", "t_end" => "30mins",
    "tracer_nonnegativity_method" => "vertical_water_borrowing",
    "FLOAT_TYPE" => "Float64", "output_default_diagnostics" => false,
)
setups = (
    follower = Dict{String, Any}("water_tracers" => tracers, "water_tag_transport" => "increment"),
    copies = Dict{String, Any}("water_tracers" => tracers, "water_tag_updraft_copy" => true),
)
build(dict, job) = CA.get_simulation(CA.AtmosConfig(
    merge(dict, Dict{String, Any}("output_dir" => mktempdir(pwd()))); job_id = job))
is_diag(name) = startswith(string(name), "ρq_tag_") || CA.is_water_tag_ledger_name(name) ||
                CA.is_tag_mechanism_ledger_name(name)

function same_model(Y, Y_plain)
    for name in propertynames(Y_plain.c)
        name == :sgsʲs && continue
        @test isequal(parent(getproperty(Y.c, name)), parent(getproperty(Y_plain.c, name)))
    end
    if hasproperty(Y_plain.c, :sgsʲs)
        for name in propertynames(Y_plain.c.sgsʲs.:(1))
            @test isequal(parent(getproperty(Y.c.sgsʲs.:(1), name)),
                parent(getproperty(Y_plain.c.sgsʲs.:(1), name)))
        end
    end
    @test isequal(parent(Y.f), parent(Y_plain.f))
end

for cadence in ("stage", "dss")
    config = merge(base, Dict{String, Any}("update_constrain_state_every" => cadence))
    plain = build(config, "wp6_plain_$cadence")
    @test CA.solve_atmos!(plain).ret_code == :success
    for (label, tags) in pairs(setups)
        @testset "$cadence, $label" begin
            sim = build(merge(config, tags), "wp6_$(cadence)_$label")
            integ = sim.integrator
            (; ledgers) = integ.p.tagging.tag_ledger_steps
            names = propertynames(ledgers)
            L(n) = Float64.(copy(parent(getproperty(integ.u.c, n))))
            prev = Dict(n => L(n) for n in names)
            by_hand = Dict(n => zero(prev[n]) for n in names)
            minimum_seen = Dict(n => 0.0 for n in names)
            nsteps = 0
            while integ.t < integ.sol.prob.tspan[2]
                CTS.step!(integ)
                nsteps += 1
                for n in names
                    now = L(n)
                    by_hand[n] .+= abs.(now .- prev[n])
                    prev[n] = now
                    minimum_seen[n] = min(minimum_seen[n], minimum(now))
                end
            end
            println("$cadence/$label: $nsteps steps")
            for n in names
                g = parent(getproperty(ledgers, n).ᶜgross)
                @test isequal(g, by_hand[n])
                @test all(g .>= abs.(prev[n]) .* (1 - 1e-12))
                println("  $n: min over run = $(minimum_seen[n]), max |L| = ",
                    maximum(abs, prev[n]), ", max gross = ", maximum(g))
            end
            fixg = integ.p.tagging.ᶜwater_fix_gross
            attempted = sum(parent(fixg.ρq_tag_tropo) .+ parent(fixg.ρq_tag_strat))
            retained = sum(parent(getproperty(ledgers, :q_tag_led_repair).ᶜgross)) * 2 +
                       sum(parent(getproperty(ledgers, :q_tag_led_rescale).ᶜgross)) +
                       sum(parent(getproperty(ledgers, :q_tag_led_empty).ᶜgross))
            println("  attempted (cache gross, partition) = $attempted, retained (state, per step) ≈ $retained")
            same_model(integ.u, plain.integrator.u)
        end
    end
end

@testset "Restart continuation of the state ledgers" begin
    config = merge(base, setups.copies, Dict{String, Any}(
        "ode_algo" => "ARS222", "t_end" => "20mins", "dt_save_state_to_disk" => "10mins",
        "reproducible_restart" => true))
    whole = build(config, "wp6_restart_whole")
    @test CA.solve_atmos!(whole).ret_code == :success
    file = joinpath(whole.output_dir, "day0.600.hdf5")
    isfile(file) || (file = first(filter(f -> occursin("600", f), readdir(whole.output_dir; join = true))))
    restarted = build(merge(config, Dict{String, Any}("restart_file" => file)), "wp6_restart_read")
    @test CA.solve_atmos!(restarted).ret_code == :success
    for n in CA.water_tag_mechanism_names(whole.integrator.p.atmos.water_tagging_model)
        @test isequal(parent(getproperty(restarted.integrator.u.c, n)),
            parent(getproperty(whole.integrator.u.c, n)))
    end
    same_model(restarted.integrator.u, whole.integrator.u)
end
