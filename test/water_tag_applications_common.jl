#=
Shared by the water tag application producer's test files: the 1-moment column
of `tagged_water_precipitation_integration.jl` with two altitude region tags,
rain and snow parts, increment transport and per-tag ledgers, a reader of the
receipt's lines, and the compile of the metered writers before a first step.
=#
using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS
import NCDatasets
import LinearAlgebra: diag

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 3000.0,
    "width" => 300.0,
    "above" => above,
)

config(FT, applications, extra = Dict{String, Any}()) = merge(
    Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "PrecipitatingColumn",
        "surface_setup" => "DefaultMoninObukhov",
        "z_elem" => 20,
        "z_max" => 6000.0,
        "z_stretch" => false,
        "dt" => "10secs",
        "t_end" => "60secs",
        "cloud_model" => "grid_scale",
        "microphysics_model" => "1M",
        "vert_diff" => "DecayWithHeightDiffusion",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "tracer_upwinding" => "first_order",
        "toml" => [
            joinpath(pkgdir(CA), "toml", "single_column_precipitation_test.toml"),
        ],
        "FLOAT_TYPE" => FT,
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
        "water_tracers" => [
            Dict{String, Any}("name" => "lower", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "upper", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        "water_tag_precipitation" => true,
        "water_tag_transport" => "increment",
        "water_tag_ledger_per_tag" => true,
        "water_tag_applications" => applications,
        "dt_save_state_to_disk" => "30secs",
    ),
    extra,
)

build(c, job_id) = CA.get_simulation(CA.AtmosConfig(c; job_id))
function run!(simulation)
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

# A small JSON reader for the receipt's lines: objects, arrays, strings,
# numbers, booleans and null.
function read_json(s)
    i = Ref(1)
    skip() =
        while i[] <= ncodeunits(s) && isspace(s[i[]])
            i[] += 1
        end
    function value()
        skip()
        c = s[i[]]
        if c == '{'
            d = Dict{String, Any}()
            i[] += 1
            skip()
            s[i[]] == '}' && (i[] += 1; return d)
            while true
                k = value()
                skip()
                i[] += 1  # :
                d[k] = value()
                skip()
                s[i[]] == ',' ? (i[] += 1) : (i[] += 1; return d)
            end
        elseif c == '['
            a = Any[]
            i[] += 1
            skip()
            s[i[]] == ']' && (i[] += 1; return a)
            while true
                push!(a, value())
                skip()
                s[i[]] == ',' ? (i[] += 1) : (i[] += 1; return a)
            end
        elseif c == '"'
            j = i[] + 1
            buf = IOBuffer()
            while s[j] != '"'
                s[j] == '\\' && (j += 1)
                print(buf, s[j])
                j += 1
            end
            i[] = j + 1
            return String(take!(buf))
        else
            m = match(r"^(true|false|null|-?[0-9.eE+-]+)", SubString(s, i[]))
            i[] += ncodeunits(m.match)
            m.match == "true" && return true
            m.match == "false" && return false
            m.match == "null" && return nothing
            return occursin(r"[.eE]", m.match) ? parse(Float64, m.match) :
                   parse(Int, m.match)
        end
    end
    return value()
end
read_receipt(dir) =
    map(read_json, readlines(joinpath(dir, CA.WATER_TAG_APPLICATION_RECEIPT)))

# The follow, the rescale and the follower are compiled before the first step,
# for the metered types. On Julia 1.10, a first step that also infers their
# call trees peaks several GiB higher, as in
# `tagged_water_precipitation_integration.jl`. No call runs the code.
function compile_metered_writers(simulation)
    Y = simulation.integrator.u
    p = simulation.integrator.p
    @test precompile(CA.follow_water_tag_precipitation!, (typeof(Y), typeof(p)))
    @test precompile(
        CA.rescale_water_tags!,
        (typeof(Y), typeof(p), typeof(copy(Y.c.ρq_tot))),
    )
    @test precompile(CA.correct_water_tag_increment!, (typeof(Y), typeof(Y), typeof(p)))
    return simulation
end

# The native arrays of a run's output directory.
function read_arrays(dir)
    ds = NCDatasets.NCDataset(joinpath(dir, CA.WATER_TAG_APPLICATION_ARRAYS))
    arrays = (;
        values = Array(ds["record_values"][:, :]),
        scales = Array(ds["record_event_scale"][:, :]),
        flags = Array(ds["record_flags"][:, :]),
        ids = Array(ds["record_id"][:]),
        channel = Array(ds["record_channel"][:]),
        ledger = Array(ds["ledger"][:, :, :]),
        ledger_time = Array(ds["ledger_time"][:]),
        attrib = Dict(k => ds.attrib[k] for k in keys(ds.attrib)),
    )
    close(ds)
    return arrays
end

# One step, run again from the end of a run, so the model's ledgers are
# read at both ends of the same step. The applied records of each tag
# add up to the step changes of its own ledgers, to rounding.
function check_model_ledgers(sim)
    Y_sim = sim.integrator.u
    Y_before = copy(Y_sim)
    CTS.step!(sim.integrator)
    step = read_receipt(sim.output_dir)[end]
    ds = NCDatasets.NCDataset(joinpath(sim.output_dir, CA.WATER_TAG_APPLICATION_ARRAYS))
    vals = Array(ds["record_values"][:, :])
    ids = Array(ds["record_id"][:])
    close(ds)
    rows = Dict(id => r for (r, id) in enumerate(ids))
    for tag in ("lower", "upper", "evap"),
        (ledger_name, mechs) in (
            ("q_tag_led_fix_", ("rescale", "empty", "repair", "close")),
            ("q_tag_led_inc_", ("inc", "negative")),
        )

        change =
            parent(getproperty(Y_sim.c, Symbol(ledger_name, tag))) .-
            parent(getproperty(Y_before.c, Symbol(ledger_name, tag)))
        total = zeros(length(change))
        activity = zeros(length(change))
        for app in step["applications"]
            (m, t) = split(app["channel"], ".")[1:2]
            (m in mechs && t == tag) || continue
            w = app["coefficient"] .* vals[:, rows[app["record_id"]]]
            total .+= w
            activity .+= abs.(w)
        end
        err = maximum(abs.(vec(change) .- total) ./ max.(activity, eps()))
        @info "Records against $ledger_name$tag" err maximum(activity)
        @test err < 1e-8
    end
    return step
end
