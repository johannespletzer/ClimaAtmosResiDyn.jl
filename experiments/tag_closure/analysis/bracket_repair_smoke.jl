#=
Smoke test of the implicit microphysics bracket and of `energy_source_tag_repair`,
on a short DYCOMS column run twice.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/bracket_repair_smoke.jl

It runs `configs/c0_column.yml` for twelve 10 s steps with a 50 kJ/kg offset, an
energy process record for `microphysics`, and the closure check every minute
with the audit on. It runs once with the repair on and once with it off, and
prints:

  - the column integral of the `microphysics` record. Before the bracket that
    record was zero under the default implicit microphysics;
  - whether the model's own state is bit for bit the same with and without the
    repair, which it must be, since the repair touches only the tags;
  - each tag's minimum in both runs, and the column integral of the repair's
    ledger for each tag;
  - both runs' closure and audit tables. `offset_smoke.jl`, run before the
    bracket existed, left a signed residual of -744 J/m² at 120 s.

It exits non-zero if the model's state differs, if the record is zero, or if a
tag is negative with the repair on. Output goes to a temporary directory under
`SMOKE_DIR`, or under the system's temporary directory.
=#

import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

const BASE = CA.load_yaml_file("experiments/tag_closure/configs/c0_column.yml")
const OUT = mktempdir(get(ENV, "SMOKE_DIR", tempdir()))
const OFFSET = 50000.0

function smoke_run(repair, name)
    config = merge(
        BASE,
        Dict{String, Any}(
            "job_id" => name,
            "output_dir" => joinpath(OUT, name),
            "t_end" => "120secs",
            "energy_source_tag_offset" => OFFSET,
            "energy_source_tag_repair" => repair,
            "energy_process_record" => ["microphysics"],
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

tag_names(Y) =
    filter(name -> startswith(string(name), "ρe_src_"), propertynames(Y.c))

function main()
    repaired = smoke_run(true, "smoke_repair")
    unrepaired = smoke_run(false, "smoke_no_repair")
    ok = true

    Y₁, Y₀ = repaired.integrator.u, unrepaired.integrator.u
    println("model state after 12 steps, with and without the repair:")
    for (label, a, b) in (
        ("ρ", Y₁.c.ρ, Y₀.c.ρ),
        ("ρe_tot", Y₁.c.ρe_tot, Y₀.c.ρe_tot),
        ("ρq_tot", Y₁.c.ρq_tot, Y₀.c.ρq_tot),
        ("uₕ", Y₁.c.uₕ, Y₀.c.uₕ),
        ("u₃", Y₁.f.u₃, Y₀.f.u₃),
    )
        identical = parent(a) == parent(b)
        ok &= identical
        println("  ", rpad(label, 8), identical ? "identical" : "DIFFERENT")
    end

    record = sum(Y₁.c.prc_e_microphysics)
    println("column integral of the microphysics record: $record J m^-2")
    ok &= !iszero(record)

    println("tag minima in J m^-3 with and without the repair, and the ledger:")
    ledger = repaired.integrator.p.tagging.ᶜenergy_source_fix
    for name in tag_names(Y₁)
        with_repair = minimum(parent(getproperty(Y₁.c, name)))
        without = minimum(parent(getproperty(Y₀.c, name)))
        fixed = sum(getproperty(ledger, name))
        println("  ", rpad(string(name), 16), with_repair, "   ", without)
        println("  ", rpad("", 16), "ledger, column integral: $fixed J m^-2")
        ok &= with_repair >= 0
    end

    for sim in (repaired, unrepaired), table in ("closure", "audit")
        path = joinpath(sim.output_dir, "energy_source_tag_$table.csv")
        println(sim.job_id, " $table table:")
        foreach(line -> println("  ", line), readlines(path))
    end
    ok || exit(1)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
