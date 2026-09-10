#=
Smoke test of `energy_source_tag_offset`, on a short DYCOMS column run twice.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/offset_smoke.jl

It runs `configs/c0_column.yml` for twelve 10 s steps without an offset, and
again with 50 kJ/kg, since the column's minimum is about -45.4 kJ/kg. The closure
check fires every minute with the audit on. The script prints whether the
model's own state, `ρ`, `ρe_tot`, `ρq_tot`, `uₕ` and `u₃`, is bit for bit the
same in the two runs, and both runs' closure and audit tables. It exits non-zero
if any state field differs.

The offset is meant to reach the tags and nothing else, so identical state is
the pass condition. It passed on 2026-09-10 on terrabyte: every field was
identical, and with the offset the non-positive fraction went from 1.0 to 0.0
and the residual turned balanced. Output goes to a temporary directory under
`SMOKE_DIR`, or under the system's temporary directory.
=#

import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

const BASE = CA.load_yaml_file("experiments/tag_closure/configs/c0_column.yml")
const OUT = mktempdir(get(ENV, "SMOKE_DIR", tempdir()))

function smoke_run(offset, name)
    config = merge(
        BASE,
        Dict{String, Any}(
            "job_id" => name,
            "output_dir" => joinpath(OUT, name),
            "t_end" => "120secs",
            "energy_source_tag_offset" => offset,
            "energy_source_closure_check" =>
                Dict{String, Any}("period" => "60secs", "audit" => true),
            "output_default_diagnostics" => false,
            "diagnostics" => [],
        ),
    )
    sim = CA.get_simulation(CA.AtmosConfig(config))
    CA.solve_atmos!(sim)
    return sim
end

function main()
    plain = smoke_run(nothing, "smoke_plain")
    shifted = smoke_run(50000.0, "smoke_offset")

    Y₀, Y₁ = plain.integrator.u, shifted.integrator.u
    same = true
    println("model state after 12 steps, without and with the offset:")
    for (label, a, b) in (
        ("ρ", Y₀.c.ρ, Y₁.c.ρ),
        ("ρe_tot", Y₀.c.ρe_tot, Y₁.c.ρe_tot),
        ("ρq_tot", Y₀.c.ρq_tot, Y₁.c.ρq_tot),
        ("uₕ", Y₀.c.uₕ, Y₁.c.uₕ),
        ("u₃", Y₀.f.u₃, Y₁.f.u₃),
    )
        identical = parent(a) == parent(b)
        same &= identical
        println("  ", rpad(label, 8), identical ? "identical" : "DIFFERENT")
    end
    for sim in (plain, shifted), table in ("closure", "audit")
        path = joinpath(sim.output_dir, "energy_source_tag_$table.csv")
        println(sim.job_id, " $table table:")
        foreach(line -> println("  ", line), readlines(path))
    end
    same || exit(1)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
