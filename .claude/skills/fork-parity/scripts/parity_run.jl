#=
Run named configurations and save every field of the final state and of one
implicit, remaining and limiter tendency by name, for `parity_compare.jl`.

    julia --project=<env> parity_run.jl <out_dir> <configs.jl> [names...]

`configs.jl` is included after `import ClimaAtmos as CA`. It defines
`configs`, a vector of `name => Dict` pairs, each merged over `common` below.
It may define `skip(name, config)`, which returns `true` for a configuration
this checkout cannot run, such as a key that `main` does not have yet. With
names given, only those run. `PARITY_FLOAT_TYPE=Float32` switches the float
type. `PARITY_COMMIT` is written into the provenance, because a compute node
has no git.
=#
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaCore
using Serialization

length(ARGS) >= 2 || error("usage: parity_run.jl <out_dir> <configs.jl> [names...]")
out = abspath(ARGS[1])
configs_file = abspath(ARGS[2])
selected = ARGS[3:end]
mkpath(out)
# `strict_config` makes a misspelled key an error. Without it a typo in a
# diagnostic's configuration only warns, and that side runs without the
# diagnostic, which would then pass as parity.
common = Dict{String, Any}(
    "strict_config" => true,
    "FLOAT_TYPE" => get(ENV, "PARITY_FLOAT_TYPE", "Float64"),
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(pwd()),
)
skip(name, config) = false
include(configs_file)
@isdefined(configs) || error("$configs_file does not define `configs`")
allunique(first.(configs)) || error("$configs_file repeats a configuration name")
unknown = setdiff(selected, first.(configs))
isempty(unknown) || error("no configuration named $(join(unknown, ", "))")

# A field's named and tuple components one by one, so that a diagnostic's
# component inside a nested field, such as an updraft's `sgsʲs`, is named apart
# from the model's own. A vector or a scalar is saved whole.
function flatten!(d, key, x)
    T = x isa ClimaCore.Fields.Field ? eltype(x) : Nothing
    if T <: NamedTuple || T <: Tuple
        for name in propertynames(x)
            flatten!(d, "$key.$name", getproperty(x, name))
        end
    else
        d[key] = copy(Array(parent(x)))
    end
    return d
end
fields(x) =
    foldl((d, name) -> flatten!(d, string(name), getproperty(x, name)), propertynames(x);
        init = Dict{String, Array}())

@info "ClimaAtmos source" pkgdir(CA)
for (name, config) in configs
    isempty(selected) || name in selected || continue
    if skip(name, config)
        @info "skipped on this checkout" name
        continue
    end
    t0 = time()
    simulation = CA.get_simulation(
        CA.AtmosConfig(merge(common, config); job_id = "parity_$name"),
    )
    result = CA.solve_atmos!(simulation)
    result.ret_code == :success || error("$name did not finish: $(result.ret_code)")
    (; u, p, t) = simulation.integrator
    Yₜ_implicit = zero(u)
    CA.implicit_tendency!(Yₜ_implicit, u, p, t)
    Yₜ_remaining = zero(u)
    Yₜ_lim = zero(u)
    CA.remaining_tendency!(Yₜ_remaining, Yₜ_lim, u, p, t)
    saved = (;
        t,
        state = fields(u),
        implicit = fields(Yₜ_implicit),
        remaining = fields(Yₜ_remaining),
        lim = fields(Yₜ_lim),
        provenance = (;
            julia = string(VERSION),
            host = gethostname(),
            float_type = common["FLOAT_TYPE"],
            climaatmos = pkgdir(CA),
            commit = get(ENV, "PARITY_COMMIT", "unknown"),
        ),
    )
    # A NaN equals a NaN under `isequal`, so a run that blew up on both sides
    # would pass. Refuse it here instead.
    for group in (:state, :implicit, :remaining, :lim),
        (key, a) in getproperty(saved, group)

        all(isfinite, a) || error("$name: $group.$key holds a NaN or an Inf")
    end
    serialize(joinpath(out, "$name.jls"), saved)
    @info "saved" name fields = length(saved.state) seconds = round(time() - t0; digits = 1)
end
