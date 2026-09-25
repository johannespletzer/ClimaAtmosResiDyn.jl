#=
G4.6: check that the budget's configurations build and step, on a login node,
before any job (design/D4_PROCESS_BUDGET.md, section 5).

    julia +1.11 --project=<env with the code branch> \
        experiments/tag_closure/analysis/increment/g46_build_check.jl <scratch dir>

Each configuration is read as the driver reads it, with `t_end` cut to two
steps and the output sent to the scratch directory. It builds the simulation,
takes the two steps, and checks what the budget will read: the residual's
source ledger in the state, finite after the steps; the audit's report and the
closure table's columns; the records of both families. The two budget runs
share one model type, so the second build costs seconds. It prints one line per
check and exits non-zero on a failure.
=#
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import YAML

const CONFIGS = joinpath(@__DIR__, "..", "..", "configs")
const OUT = isempty(ARGS) ? mktempdir() : first(ARGS)

failures = String[]
check(ok, what) = (println(ok ? "ok    " : "FAIL  ", what); ok || push!(failures, what))

for name in ("g46_d4_budget", "g46_d4_budget_2c", "g46_d4_untagged")
    dict = YAML.load_file(joinpath(CONFIGS, "$name.yml"))
    dict["t_end"] = "240secs"
    dict["output_dir"] = joinpath(OUT, name)
    t0 = time()
    simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = "$(name)_build_check"))
    built = time() - t0
    integrator = simulation.integrator
    CA.CTS.step!(integrator)
    CA.CTS.step!(integrator)
    Y, p = integrator.u, integrator.p
    println("== $name: built in $(round(built; digits = 1)) s, stepped to t = $(integrator.t)")
    model = p.atmos.energy_source_tagging_model
    if name == "g46_d4_untagged"
        check(isnothing(model), "$name has no energy source tags")
        continue
    end
    check(hasproperty(Y.c, :e_src_led_src_res), "$name keeps the residual's source ledger")
    check(all(isfinite, parent(Y.c.e_src_led_src_res)), "$name: the ledger is finite")
    check(hasproperty(Y.c, :prc_e_precipitation), "$name keeps the energy records")
    check(hasproperty(Y.c, :prc_q_surface_flux), "$name keeps the water records")
    closure = CA.tag_closure(
        Y,
        p,
        CA.energy_source_closure_total(model),
        CA.energy_source_region_tag_state_names(model),
    )
    report = CA.energy_source_residual_report(Y, p, model, closure, 0.0, Ref{Any}(nothing))
    check(hasproperty(report, :flush_gross), "$name: the report has the forecast")
    check(isfinite(report.residual_max), "$name: the report's local maximum is finite")
    columns = CA.energy_source_closure_columns(Y, p, model, closure)
    check(columns.headroom_min > 0, "$name: the headroom is positive")
    check(columns.source_throughput > 0, "$name: the throughput is positive")
    check(model.offset == dict["energy_source_tag_offset"], "$name: the offset is the config's")
end

isempty(failures) || (println("failed: ", join(failures, "; ")); exit(1))
println("all checks passed")
