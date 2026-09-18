# The increment prototype on C9's column: `enthalpy` against
# `enthalpy_increment`, one hour each, then the closure rows and the model's
# fields compared.
import ClimaAtmos as CA
import YAML
cfg_path = "/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn.jl/experiments/tag_closure/configs/c9_column_enthalpy.yml"
base = YAML.load_file(cfg_path)
delete!(base, "job_id")
function run(transport)
    d = merge(base, Dict{String, Any}(
        "energy_source_tag_transport" => transport,
        "t_end" => "1hours",
        "output_dir" => mktempdir(pwd()),
        "energy_source_closure_check" => Dict{String, Any}("period" => "10mins", "audit" => true, "spin_up" => nothing),
    ))
    sim = CA.get_simulation(CA.AtmosConfig(d; job_id = "inc_$transport"))
    @assert CA.solve_atmos!(sim).ret_code == :success
    return sim
end
a = run("enthalpy")
b = run("enthalpy_increment")
for (label, s) in (("enthalpy", a), ("enthalpy_increment", b))
    path = CA.tag_closure_path(s.output_dir, "energy_source")
    println("== $label")
    foreach(println, readlines(path))
end
Ya, Yb = a.integrator.u, b.integrator.u
same = true
for part in (:c, :f), name in propertynames(getproperty(Ya, part))
    CA.is_energy_source_tag_name(name) && continue
    startswith(string(name), "prc_") && continue
    eq = isequal(parent(getproperty(getproperty(Ya, part), name)), parent(getproperty(getproperty(Yb, part), name)))
    global same &= eq
    eq || println("model field $part.$name DIFFERS")
end
println(same ? "model fields bit for bit" : "MODEL FIELDS DIFFER")
