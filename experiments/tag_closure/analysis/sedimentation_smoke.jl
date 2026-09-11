#=
Smoke test of sedimentation as transport of the energy source tags, on a
1-moment DYCOMS column run twice.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/sedimentation_smoke.jl

It runs `configs/c6_column_repair.yml` under 1-moment microphysics for one hour
at its 10 s step, with a `precipitation` record beside the other four and the
closure check every ten minutes. Cloud liquid falls at the diagnostic speed
rather than the default fixed one, so that the cloud falls as well as the rain.
It runs once as the model is, and once with `sediment_energy_source_tags!`
redefined to do nothing, which is how the tags moved before sedimentation moved
them. It prints:

  - whether the model's own state is bit for bit the same in both runs, which it
    must be, since the tags never act on the model;
  - the column integral of the `precipitation` record, signed and gross. That
    is the change sedimentation made to `ρe_tot`. It changes the tags' total by
    that plus `c` times the mass it moved;
  - for each run, the column integral of the residual, `E` less the region
    tags, signed and gross;
  - the difference of the two runs' residuals, signed and gross. That is the
    part of sedimentation the tags now follow, apart from what moving them
    changes in the other processes' attribution;
  - each tag's minimum in both runs, and the closure and audit tables.

It exits non-zero if a run does not finish, if the model's state differs between
the runs, or if a tag is not finite. Output goes to a directory under
`SMOKE_DIR`, or under the system's temporary directory, and is kept.
=#

import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

const BASE =
    CA.load_yaml_file("experiments/tag_closure/configs/c6_column_repair.yml")
const OUT = mktempdir(get(ENV, "SMOKE_DIR", tempdir()); cleanup = false)
const OFFSET = Float64(BASE["energy_source_tag_offset"])

function smoke_run(name)
    config = merge(
        BASE,
        Dict{String, Any}(
            "job_id" => name,
            "output_dir" => joinpath(OUT, name),
            "t_end" => "1hours",
            "microphysics_model" => "1M",
            "fixed_terminal_velocity_liquid" => false,
            "energy_process_record" => [
                "radiation",
                "surface_flux",
                "subsidence",
                "microphysics",
                "precipitation",
            ],
            "energy_source_closure_check" =>
                Dict{String, Any}("period" => "10mins", "audit" => true),
            "output_default_diagnostics" => false,
            "diagnostics" => [],
        ),
    )
    sim = CA.get_simulation(CA.AtmosConfig(config))
    result = CA.solve_atmos!(sim)
    result.ret_code == :success ||
        error("$name did not finish: $(result.ret_code)")
    return sim
end

tag_names(Y) =
    filter(name -> startswith(string(name), "ρe_src_"), propertynames(Y.c))

# The residual the closure check reports: the tags' total less the region tags.
residual(Y) = @. Y.c.ρe_tot + OFFSET * Y.c.ρ - Y.c.ρe_src_strat -
                 Y.c.ρe_src_tropo
gross(field) = sum(abs.(field))

function main()
    moved = smoke_run("sedimentation_moved")
    # From here on the tags do not follow sedimentation, as before it moved them.
    @eval CA sediment_energy_source_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶜenergy_flux, ᶠρ) =
        nothing
    unmoved = Base.invokelatest(smoke_run, "sedimentation_unmoved")
    ok = true

    Y₁, Y₀ = moved.integrator.u, unmoved.integrator.u
    println("model state after one hour, with and without the tags moved:")
    for (label, a, b) in (
        ("ρ", Y₁.c.ρ, Y₀.c.ρ),
        ("ρe_tot", Y₁.c.ρe_tot, Y₀.c.ρe_tot),
        ("ρq_tot", Y₁.c.ρq_tot, Y₀.c.ρq_tot),
        ("ρq_lcl", Y₁.c.ρq_lcl, Y₀.c.ρq_lcl),
        ("ρq_rai", Y₁.c.ρq_rai, Y₀.c.ρq_rai),
        ("uₕ", Y₁.c.uₕ, Y₀.c.uₕ),
        ("u₃", Y₁.f.u₃, Y₀.f.u₃),
    )
        identical = parent(a) == parent(b)
        ok &= identical
        println("  ", rpad(label, 8), identical ? "identical" : "DIFFERENT")
    end

    record = Y₁.c.prc_e_precipitation
    println(
        "precipitation record, column integral: signed $(sum(record)), gross $(gross(record)) J m^-2",
    )

    r₁, r₀ = residual(Y₁), residual(Y₀)
    difference = @. r₀ - r₁
    println("residual, E less the region tags, column integral in J m^-2:")
    println("  tags moved:       signed $(sum(r₁)), gross $(gross(r₁))")
    println("  tags unmoved:     signed $(sum(r₀)), gross $(gross(r₀))")
    println(
        "  unmoved - moved:  signed $(sum(difference)), gross $(gross(difference))",
    )

    println("tag minima in J m^-3, tags moved and unmoved:")
    for name in tag_names(Y₁)
        a = parent(getproperty(Y₁.c, name))
        b = parent(getproperty(Y₀.c, name))
        ok &= all(isfinite, a) && all(isfinite, b)
        println("  ", rpad(string(name), 16), minimum(a), "   ", minimum(b))
    end

    for sim in (moved, unmoved), table in ("closure", "audit")
        path = joinpath(sim.output_dir, "energy_source_tag_$table.csv")
        println(sim.job_id, " $table table:")
        foreach(line -> println("  ", line), readlines(path))
    end
    println("output kept in $OUT")
    ok || exit(1)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
