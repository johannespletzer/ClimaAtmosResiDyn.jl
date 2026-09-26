# WP9a: which of the plume's changes helps, and which hurts, one at a time.
#
#   NTAGS=2|8|32 NEW=<path to the changed worktree> \
#       julia --project=<env at #102's code> wp9_variants.jl
#
# It builds W26's TRMM 0M column in the default mode with NTAGS water tags (as
# `wp9_plume_cost.jl`) at #102's code, and times `water_exchange_inputs!` and
# `sgs_exchange_of_water_tags!` (the minimum of 20 calls after one untimed, and
# the second call's allocations). Then it loads the changed definitions from
# NEW one at a time into the running module, and times again after each:
#   V1  `water_tag_plume!`, whose tag fields are built with `unrolled_map`;
#   V2  `_nonnegative_specific` with `ntuple`;
#   V3  `_plume_step` with `ntuple`;
#   V4  `WaterPlumeStep` with `ntuple`.
# The results must equal V0's, bit for bit, at every step.
import ClimaAtmos as CA
import YAML

ntags = parse(Int, get(ENV, "NTAGS", "2"))
new_root = ENV["NEW"]
here = @__DIR__
dict = Dict{String, Any}(
    YAML.load_file(
        joinpath(here, "..", "..", "configs", "w4a_trmm0m_default_6h.yml"),
    ),
)
dict["diagnostics"] = []
dict["output_dir"] = mktempdir(pwd())
dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
dict["water_tracers"] = [
    dict["water_tracers"][1:2]...,
    [
        Dict{String, Any}("name" => "src$k", "source" => "surface_flux") for
        k in 1:(ntags - 2)
    ]...,
]
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = "wp9_variants_n$ntags"))
Y = simulation.integrator.u
p = simulation.integrator.p
model = p.atmos.water_tagging_model
turbconv_model = p.atmos.turbconv_model

function timed(f)
    f()
    bytes = @allocated f()
    seconds = minimum(@elapsed(f()) for _ in 1:20)
    return (seconds, bytes)
end
Yₜ = zero(Y)
function measure(label)
    inputs = timed(
        () -> Base.invokelatest(CA.water_exchange_inputs!, Y, p, turbconv_model, model),
    )
    fill!(parent(Yₜ), 0)
    exchange = timed(
        () -> Base.invokelatest(
            CA.sgs_exchange_of_water_tags!,
            Yₜ,
            Y,
            p,
            turbconv_model,
            model,
        ),
    )
    Base.invokelatest(CA.water_exchange_inputs!, Y, p, turbconv_model, model)
    plume = copy(parent(p.scratch.ᶜq_tag_plume))
    fill!(parent(Yₜ), 0)
    Base.invokelatest(CA.sgs_exchange_of_water_tags!, Yₜ, Y, p, turbconv_model, model)
    println(
        "RESULT n=$ntags variant=$label exchange_inputs_seconds=$(inputs[1]) " *
        "exchange_inputs_bytes=$(inputs[2]) exchange_seconds=$(exchange[1]) " *
        "exchange_bytes=$(exchange[2])",
    )
    return (plume, copy(parent(Yₜ)))
end

# One definition's text from a source file, from its first line to the `end`
# at the start of a line, or a one-line `=` definition with its continuation.
function definition(path, first_line)
    lines = readlines(path)
    i = findfirst(==(first_line), lines)
    isnothing(i) && error("not found in $path: $first_line")
    j = i
    if endswith(first_line, "=")
        j = i + 1
        while j < length(lines) && startswith(lines[j + 1], "    ")
            j += 1
        end
    else
        while lines[j] != "end"
            j += 1
        end
    end
    return join(lines[i:j], "\n")
end
water = joinpath(
    new_root,
    "src",
    "parameterized_tendencies",
    "tagged_tracers",
    "tagged_water_edmf.jl",
)
energy = joinpath(
    new_root,
    "src",
    "parameterized_tendencies",
    "tagged_tracers",
    "energy_source_tags.jl",
)
variants = [
    ("V1", water, "function water_tag_plume!(ᶜεʲ, ᶜε̄, Y, p, turbconv_model, model)"),
    ("V2", energy, "@inline _nonnegative_specific(ρ, ρχs...) ="),
    ("V3", energy, "@inline function _plume_step(εʲ_below, level)"),
    ("V4", water, "@inline function (::WaterPlumeStep{partition})("),
]

reference = measure("V0")
for (label, path, first_line) in variants
    text = definition(path, first_line)
    # A callable type's method spans a signature over several lines.
    Base.include_string(CA, text)
    result = measure(label)
    println(
        "RESULT n=$ntags variant=$label same_plume=$(isequal(result[1], reference[1])) " *
        "same_exchange=$(isequal(result[2], reference[2]))",
    )
end
