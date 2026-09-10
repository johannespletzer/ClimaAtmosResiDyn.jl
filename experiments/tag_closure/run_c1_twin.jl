#=
C1's twin test: the C1 sphere with and without the reference shift, run side by
side in one process and compared field by field.

`analysis/c1_acceptance.jl` shows that Thermodynamics treats the shift as a
change of reference. It cannot show that the model does. Every term that moves
energy together with water has to use the same reference, and some of them are
assembled outside Thermodynamics: the surface flux in SurfaceFluxes, the split
of hyperdiffusion into dry and water parts, the implicit solver. This test runs
the whole model.

If the shift is only a relabelling, the two runs carry the same atmosphere.
Then `ρ`, `ρq_tot`, `uₕ` and `u₃` agree to rounding at every time, and `ρe_tot`
differs by exactly `ρ·((1 - q_tot)·cp_d + q_tot·cp_l)·|δ|`, which is the shift
`c1_acceptance.jl` measures. A larger difference is a change of atmosphere, and
C1 would then not measure what it claims to.

Both runs use C1's configuration as it stands, with two changes that cannot
touch the state. The unshifted run drops the `toml:` entry. Both drop the
diagnostics, which only write output. Everything else is C1's, the closure
check included.

`TWIN_OVERRIDES` may name a YAML file of configuration keys to set in both
halves, on top of C1's. It is for asking how the answer depends on the solver,
for instance by converging the implicit solve. It may not set `toml:`, because
the shift is the one thing the twin varies. A relative path is looked up from
the repository root. The keys it set are written into the table's header.

Run it through the phase C runscript, so that it gets a provenance, and set
`TAG_CLOSURE_JOB_ID` so that its output cannot land on C1's:

    env CONFIG=experiments/tag_closure/configs/c1_sphere_shift.yml \
        DRIVER=experiments/tag_closure/run_c1_twin.jl \
        TAG_CLOSURE_JOB_ID=twin_c1 \
        sbatch --account=hpda-c --partition=hpda2_test --time=01:30:00 \
            --cpus-per-task=2 --mem=32G \
            experiments/tag_closure/runscripts/phase_c.sh

It writes `<TAG_CLOSURE_JOB_ID>.csv` into `output/<TAG_CLOSURE_JOB_ID>/` under
the run directory, one row per sample. It exits non-zero if the twins differ by
more than rounding.
=#

import ClimaComms as CC
CC.@import_required_backends

import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

# |δ| of toml/tag_closure_c1_reference.toml, in kelvin.
const SHIFT = 110.0

# A sample every hour, and one after the first step. A term that is not
# reference-invariant makes its difference on every step, so the first sample
# shows it before any growth of rounding error could be blamed.
const SAMPLE_SECONDS = 3600.0

# The largest relative difference still read as rounding. A Float64 difference
# starts near 1e-16. One day of this wave does not grow it by eight orders of
# magnitude, because the 0M scheme and the saturation adjustment are continuous
# and nothing in the configuration branches on a threshold. A term that breaks
# the invariance shows up in `energy_after_shift` at its own size relative to
# the shift, from the first step on.
const TOLERANCE = 1e-8

const COLUMNS = ("time", "rho", "rho_q_tot", "u_h", "u_3", "energy_after_shift")

"""
    config_path()

The configuration to twin, from `CONFIG` or from the first argument.
"""
function config_path()
    from_env = get(ENV, "CONFIG", "")
    path = !isempty(from_env) ? from_env : (isempty(ARGS) ? "" : first(ARGS))
    isfile(path) || error("No configuration to twin. Set CONFIG to C1's YAML file.")
    return abspath(path)
end

"""
    overrides()

The configuration keys to set in both halves of the twin, from the YAML file
named by `TWIN_OVERRIDES`. Empty when that is unset.
"""
function overrides()
    path = get(ENV, "TWIN_OVERRIDES", "")
    isempty(path) && return Dict{String, Any}()
    isabspath(path) || (path = joinpath(get(ENV, "ROOT", pwd()), path))
    isfile(path) || error("TWIN_OVERRIDES names no file: $path")
    extra = CA.load_yaml_file(path)
    haskey(extra, "toml") &&
        error("$path sets `toml:`, but the shift is what the twin varies.")
    return extra
end

describe(extra) =
    isempty(extra) ? "none" :
    join(["$key = $(extra[key])" for key in sort(collect(keys(extra)))], ", ")

"""
    twin_configs(path, output_base, extra = Dict{String, Any}())

The unshifted and the shifted configuration, each writing into its own
directory under `output_base`, both with the keys in `extra` set.
"""
function twin_configs(path, output_base, extra = Dict{String, Any}())
    config = merge(CA.load_yaml_file(path), extra)
    toml = get(config, "toml", nothing)
    (isnothing(toml) || isempty(toml)) &&
        error("$path has no `toml:` entry, so there is no shift to test.")
    shifted = merge(
        config,
        Dict{String, Any}(
            "job_id" => "twin_shifted",
            "output_dir" => joinpath(output_base, "shifted"),
            "output_default_diagnostics" => false,
            "diagnostics" => [],
        ),
    )
    unshifted = merge(
        shifted,
        Dict{String, Any}(
            "job_id" => "twin_unshifted",
            "output_dir" => joinpath(output_base, "unshifted"),
            "toml" => [],
        ),
    )
    return (unshifted, shifted)
end

reference_temperature(sim) =
    CA.TD.Parameters.T_0(CA.CAP.thermodynamics_params(sim.integrator.p.params))

"""
    largest_difference(a, b)

`max |b - a| / max |a|` over the fields' underlying arrays, and zero when the
two are identical. A field that is zero in `a` and not in `b` gives `Inf`,
which fails the test, as it should.
"""
function largest_difference(a, b)
    difference = maximum(abs, parent(b) .- parent(a))
    iszero(difference) && return 0.0
    return difference / maximum(abs, parent(a))
end

"""
    energy_after_shift(Y₀, Y₁, cp_d, cp_l)

The part of `ρe_tot`'s difference that the predicted shift does not account
for, relative to the predicted shift.
"""
function energy_after_shift(Y₀, Y₁, cp_d, cp_l)
    ρ = parent(Y₀.c.ρ)
    q_tot = parent(Y₀.c.ρq_tot) ./ ρ
    predicted = ρ .* ((1 .- q_tot) .* cp_d .+ q_tot .* cp_l) .* SHIFT
    miss = (parent(Y₁.c.ρe_tot) .- parent(Y₀.c.ρe_tot)) .- predicted
    return maximum(abs, miss) / maximum(abs, predicted)
end

"""
    sample(integrators, cp_d, cp_l)

One row of the comparison, at the time both integrators have reached.
"""
function sample(integrators, cp_d, cp_l)
    t₀, t₁ = map(integrator -> float(integrator.t), integrators)
    t₀ == t₁ || error("The twins are out of step: $t₀ against $t₁.")
    Y₀, Y₁ = map(integrator -> integrator.u, integrators)
    return [
        t₀,
        largest_difference(Y₀.c.ρ, Y₁.c.ρ),
        largest_difference(Y₀.c.ρq_tot, Y₁.c.ρq_tot),
        largest_difference(Y₀.c.uₕ, Y₁.c.uₕ),
        largest_difference(Y₀.f.u₃, Y₁.f.u₃),
        energy_after_shift(Y₀, Y₁, cp_d, cp_l),
    ]
end

function main()
    path = config_path()
    extra = overrides()
    job_id = get(ENV, "TAG_CLOSURE_JOB_ID", "twin_c1")
    output_base = joinpath(pwd(), "output", job_id)
    mkpath(output_base)
    @info "C1 twin test" path job_id overrides = describe(extra)

    sims = map(twin_configs(path, output_base, extra)) do config
        CA.get_simulation(CA.AtmosConfig(config))
    end
    unshifted, shifted = sims

    # The run's own parameter set, so a shift that did not bind stops here
    # rather than passing as a perfect match.
    T_0 = map(reference_temperature, sims)
    T_0[2] ≈ T_0[1] - SHIFT ||
        error("The shift did not bind: T_0 is $(T_0[2]) shifted, $(T_0[1]) not.")

    thermo = CA.CAP.thermodynamics_params(unshifted.integrator.p.params)
    cp_d = CA.TD.Parameters.cp_d(thermo)
    cp_l = CA.TD.Parameters.cp_l(thermo)

    dt = float(unshifted.integrator.dt)
    t_end = float(unshifted.t_end)
    steps_per_sample = round(Int, SAMPLE_SECONDS / dt)
    steps_per_sample * dt == SAMPLE_SECONDS ||
        error("dt = $dt s does not divide the $SAMPLE_SECONDS s sample interval.")
    n_steps = round(Int, t_end / dt)

    integrators = (unshifted.integrator, shifted.integrator)
    rows = [sample(integrators, cp_d, cp_l)]
    for n in 1:n_steps
        foreach(CTS.step!, integrators)
        (n == 1 || n % steps_per_sample == 0) &&
            push!(rows, sample(integrators, cp_d, cp_l))
    end

    table = joinpath(output_base, "$job_id.csv")
    open(table, "w") do io
        println(io, "# $job_id.csv, from experiments/tag_closure/run_c1_twin.jl")
        println(io, "# config: $path")
        println(io, "# T_0 unshifted $(T_0[1]) K, shifted $(T_0[2]) K")
        println(io, "# overrides in both halves: $(describe(extra))")
        println(io, "# columns after time: max|shifted - unshifted| / max|unshifted|;")
        println(io, "# energy_after_shift has the predicted shift removed, relative to it")
        println(io, join(COLUMNS, ","))
        foreach(row -> println(io, join(row, ",")), rows)
    end

    worst = maximum(row -> maximum(row[2:end]), rows)
    for row in rows
        println(join(map(value -> rpad(string(value), 24), row)))
    end
    @info "C1 twin test" table worst tolerance = TOLERANCE
    if !(worst <= TOLERANCE)
        @error "The twins differ by more than rounding. The shift changes the \
                atmosphere, not only its energy reference." worst
        exit(1)
    end
    @info "The twins agree to rounding. The shift is a change of energy \
           reference in the whole model, over the whole run."
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
