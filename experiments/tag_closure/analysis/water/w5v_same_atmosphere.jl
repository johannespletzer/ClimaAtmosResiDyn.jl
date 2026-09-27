# WP5b-V, part 2 (design/EXPLICIT_1M_DEFAULT.md, section 6): the tags' one-step
# error with fewer Newton iterations, on the reference's own atmosphere.
#
#   DT=120|60 OUTDIR=... julia --project=<env at #105's code> w5v_same_atmosphere.jl
#
# It builds three integrators of the TRMM 1M explicit column
# (`configs/w5v_trmm1m_dt<DT>_n10.yml`, without diagnostics or the closure
# check): the reference with 10 Newton iterations, and trials with 1 and 2. At
# every step it copies the reference's state `Yₖ` and time into each trial,
# steps all three, and compares each trial's result with the reference's. It
# accumulates, for the parent `ρq_tot` and each tag,
#   error     Σ_cells |ρq_trial − ρq_ref|,
#   increment Σ_cells |ρq_ref − ρq(Yₖ)|,
# writes them per step to OUTDIR/<run>.csv, and prints E = Σ error / Σ increment
# per variable and trial. A T_END override is for a smoke test only.
import ClimaAtmos as CA
import YAML

dt = parse(Int, get(ENV, "DT", "120"))
outdir = get(ENV, "OUTDIR", pwd())
mkpath(outdir)
here = @__DIR__
base_dict() = Dict{String, Any}(
    YAML.load_file(
        joinpath(here, "..", "..", "configs", "w5v_trmm1m_dt$(dt)_n10.yml"),
    ),
)
function config(newton)
    dict = base_dict()
    dict["diagnostics"] = []
    delete!(dict, "water_closure_check")
    dict["output_dir"] = mktempdir(pwd())
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    dict["max_newton_iters_ode"] = newton
    haskey(ENV, "T_END") && (dict["t_end"] = ENV["T_END"])
    return CA.AtmosConfig(dict; job_id = "w5v_same_dt$(dt)_n$(newton)")
end
reference = CA.get_simulation(config(10)).integrator
trials = [(n, CA.get_simulation(config(n)).integrator) for n in (1, 2)]
model = reference.p.atmos.water_tagging_model
names = (:ρq_tot, CA.water_tag_state_names(model)...)
t_end = CA.time_to_seconds(get(ENV, "T_END", base_dict()["t_end"]))

l1(a, b) = sum(abs, parent(a) .- parent(b))
header = ["t_seconds"]
for (n, _) in trials, name in names
    append!(header, ["error_n$(n)_$(name)", "increment_$(name)"])
end
rows = Vector{Vector{Float64}}()
while CA.time_to_seconds(reference.t) < t_end - 1e-6
    Yₖ = copy(reference.u)
    tₖ = reference.t
    CA.CTS.step!(reference)
    row = [CA.time_to_seconds(reference.t)]
    for (n, trial) in trials
        trial.u .= Yₖ
        trial.t = tₖ
        # The stepper does not refresh the cache at a step's first stage: it
        # holds what the previous step left, here the trial's own. So it is
        # rebuilt for the copied state (the first submission missed this, and
        # its trials stepped with their own previous cache).
        CA.set_precomputed_quantities!(trial.u, trial.p, trial.t)
        CA.CTS.step!(trial)
        @assert trial.t == reference.t
        for name in names
            push!(row, l1(getproperty(trial.u.c, name), getproperty(reference.u.c, name)))
            push!(row, l1(getproperty(reference.u.c, name), getproperty(Yₖ.c, name)))
        end
    end
    push!(rows, row)
end

run_name = "w5v_same_atmosphere_dt$(dt)"
open(joinpath(outdir, "$run_name.csv"), "w") do io
    println(io, join(header, ","))
    for row in rows
        println(io, join(repr.(row), ","))
    end
end
column = 2
for (n, _) in trials
    for name in names
        error = sum(row[column] for row in rows)
        increment = sum(row[column + 1] for row in rows)
        println(
            "RESULT run=$run_name newton=$n variable=$name E=$(error / increment) error=$error increment=$increment",
        )
        global column += 2
    end
end
println("RESULT run=$run_name steps=$(length(rows))")
