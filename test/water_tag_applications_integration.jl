#=
Integration test for the water tags' application producer,
`water_tag_applications: true`, on the 1-moment column of
`tagged_water_precipitation_integration.jl`: two altitude region tags with
rain and snow parts, under `water_tag_transport: increment` and with the tags'
per-tag ledgers. That column runs the rescale, the emptying, the partition
repair, the closing step, the follow of rain and snow, and the follower with
its negative water. It checks:
 1. the weights of each role against the ARS343 and ARS222 tableaus;
 2. the receipt: one accepted trial per step, contiguous steps, an applied
    record of every channel at every step, and each weight as the reader
    computes it from the pin and the step's edges;
 3. a move of the follow between a tag's parts is two legs, and opposite
    applications to one channel in one step stay two records;
 4. the cumulative ledger of each channel is the running sum of its applied
    records, bit for bit;
 5. the applied records of each tag add up to the step changes of the model's
    own ledgers `q_tag_led_fix_<name>` and `q_tag_led_inc_<name>`, to rounding;
 6. the model's fields with the producer are those without it, bit for bit,
    in Float64 and Float32;
 7. a run restarted from a checkpoint gives the continuous run's records and
    ledgers;
 8. the refusals: without water tags and with the tags' updraft copies;
 9. the counter code of an empty donor and of a negative compartment.
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

@testset "Water tag application producer" begin
    @testset "Weights of each role against ARS343 and ARS222" begin
        for name in (CTS.ARS343(), CTS.ARS222())
            tableau = CTS.IMEXTableau(name)
            b_exp = Float64.(tableau.b_exp.coeffs)
            b_imp = Float64.(tableau.b_imp.coeffs)
            γ = Float64.(diag(tableau.a_imp.coeffs))
            pin = (; b_exp, b_imp, implicit_diagonal = γ)
            @test CA.water_application_coefficient(:final_map, 0, pin, 30.0, 40.0) === 1.0
            for i in eachindex(b_imp)
                @test CA.water_application_coefficient(:implicit, i, pin, 30.0, 40.0) ===
                      (40.0 - 30.0) * b_imp[i]
                @test CA.water_application_coefficient(:explicit, i, pin, 30.0, 40.0) ===
                      (40.0 - 30.0) * b_exp[i]
                iszero(γ[i]) && continue
                @test CA.water_application_coefficient(:post_newton, i, pin, 30.0, 40.0) ===
                      b_imp[i] / γ[i]
            end
        end
        # ARS222: γ = 1 - 1/√2, b_imp = (0, 1 - γ, γ). The last stage's
        # post-Newton map enters with weight one.
        tableau = CTS.IMEXTableau(CTS.ARS222())
        γ = 1 - 1 / sqrt(2)
        @test Float64.(tableau.b_imp.coeffs) ≈ [0, 1 - γ, γ]
        @test Float64(tableau.b_imp.coeffs[3]) / Float64(tableau.a_imp.coeffs[3, 3]) == 1
        # ARS343's last stage, with γ = 0.4358665215.
        tableau = CTS.IMEXTableau(CTS.ARS343())
        @test Float64(tableau.a_imp.coeffs[4, 4]) ≈ 0.4358665215084590
        @test Float64(tableau.b_imp.coeffs[4]) ≈ 0.4358665215084590
    end

    @testset "Counter codes: empty donor and negative compartment" begin
        # The repair of a negative tag: clamped. No positive water to repair
        # into (an empty donor): zero normalization. Negatives outweigh: bound.
        @test CA.water_tag_repair_flags(-1.0, 2.0, -1.0) == 4
        @test CA.water_tag_repair_flags(0.0, 0.0, 0.0) == 8
        @test CA.water_tag_repair_flags(-3.0, 1.0, -3.0) == 2 + 4
        # The follow where the compartment is not positive: the part is emptied.
        @test CA.water_tag_follow_flags(1.0, 1.0, -1.0, 1.0, 1.0, 1.0) == 1
        # A compartment that grows with no non-precipitating water to take it
        # from (an empty donor), and with the cap binding.
        @test CA.water_tag_follow_flags(0.0, 0.0, 2.0, 1.0, 1.0, 0.0) == 8
        @test CA.water_tag_follow_flags(0.0, 1.0, 5.0, 1.0, 1.0, 1.0) == 2
        # The rescale of a negative tag gets no share, and the floor binds.
        @test CA.water_tag_rescale_flags(-1.0, 0.0, 1.0, 0.5) == 2 + 4
        # A non-positive parent before: the emptying, not the rescale.
        @test CA.water_tag_rescale_flags(1.0, 0.0, 0.0, 1.0) == 0
        # The closing step with nothing in the parts and a positive rest takes
        # the non-precipitating composition. With none there, nothing moves.
        @test CA.water_tag_closing_flags(0.0, 1.0, 0.0, 0.0, 1.0) == 1
        @test CA.water_tag_closing_flags(0.0, 1.0, 0.0, 0.0, 0.0) == 8
    end

    simulation = run!(build(config("Float64", true), "water_tag_applications"))
    Y = simulation.integrator.u
    p = simulation.integrator.p
    meter = CA.water_meter(p)
    dir = simulation.output_dir
    lines = read_receipt(dir)
    header, steps = first(lines), lines[2:end]
    pin = header["integrator_pin"]
    channels = [c["id"] for c in header[CA.WATER_TAG_APPLICATION_ROSTER_KEY]["channels"]]
    ds = NCDatasets.NCDataset(joinpath(dir, CA.WATER_TAG_APPLICATION_ARRAYS))
    values = Array(ds["record_values"][:, :])
    record_ids = Array(ds["record_id"][:])
    record_channel = Array(ds["record_channel"][:])
    ledger = Array(ds["ledger"][:, :, :])
    ledger_time = Array(ds["ledger_time"][:])
    close(ds)
    row = Dict(id => r for (r, id) in enumerate(record_ids))

    @testset "The receipt" begin
        @test header["schema_version"] == 1
        @test header["semantics"] == "weighted_final_additive_updates"
        @test header["kind"] == "runtime_capture"
        @test pin["algorithm"] == "unconstrained_imex_ark"
        @test pin["package"] == "ClimaTimeSteppers"
        @test pin["tableau"] == "ARS343"
        @test length(pin["b_exp"]) == length(pin["b_imp"]) ==
              length(pin["implicit_diagonal"]) == 4
        @test length(steps) == 6
        @test ledger_time == vcat(0.0, [s["end_seconds"] for s in steps])
        mechanisms = Set(split(c, ".")[1] for c in channels)
        @test mechanisms ==
              Set(["rescale", "empty", "repair", "close", "follow", "inc", "negative"])
        for (n, step) in enumerate(steps)
            @test step["start_seconds"] == ledger_time[n]
            @test step["end_seconds"] > step["start_seconds"]
            @test length(step["trials"]) == 1
            @test step["trials"][1]["decision"] == "accepted"
            @test step["accepted_trial"] == step["trials"][1]["id"]
            @test step["unattributed_calls"] == 0
            seen = Set(a["channel"] for a in step["applications"])
            @test seen == Set(channels)
            a, b = step["start_seconds"], step["end_seconds"]
            for app in step["applications"]
                @test app["disposition"] == "applied"
                @test app["trial"] == step["accepted_trial"]
                @test haskey(row, app["record_id"])
                role = app["role"]
                if role == "final_map"
                    @test app["coefficient"] === 1.0
                elseif role == "implicit"
                    @test app["coefficient"] === (b - a) * pin["b_imp"][app["stage"]]
                    @test app["coefficient_units"] == "s"
                else
                    @test role == "post_newton"
                    @test app["coefficient"] ===
                          pin["b_imp"][app["stage"]] /
                          pin["implicit_diagonal"][app["stage"]]
                end
            end
        end
        @test allunique(record_ids)
    end

    @testset "Legs: a follow is two, and opposite applications stay apart" begin
        # Each follow writes `+shift` to the part and `-shift` to the
        # non-precipitating part, with the same index in its step.
        legs = 0
        for step in steps, app in step["applications"]
            startswith(app["channel"], "follow.lower.rain") || continue
            k = split(app["record_id"], "/")[end]
            k == "0" && continue
            mate = replace(app["record_id"], "rain/" => "nonprecipitating/")
            # The rain leg's slot pairs with a non-precipitating slot of the
            # same call, so look it up by the step's records.
            vals = values[:, row[app["record_id"]]]
            any(!iszero, vals) || continue
            others = [
                values[:, row[o["record_id"]]] for o in step["applications"] if
                o["channel"] == "follow.lower.nonprecipitating"
            ]
            @test any(o -> o == -vals, others)
            legs += 1
        end
        @test legs > 0
        # Within one step and one channel, applications of both signs in one
        # cell are recorded apart, so their absolute sum exceeds the net.
        both = 0
        for step in steps
            for c in channels
                rows =
                    [row[a["record_id"]] for a in step["applications"] if a["channel"] == c]
                length(rows) > 1 || continue
                v = values[:, rows]
                both += count(
                    i -> any(>(0), v[i, :]) && any(<(0), v[i, :]),
                    axes(v, 1),
                )
            end
        end
        @info "Cells with opposite applications of one channel in one step" both
        @test both > 0
    end

    @testset "The ledger is the running sum of the applied records" begin
        for (n, step) in enumerate(steps), (c, id) in enumerate(channels)
            L = ledger[:, c, n]
            for app in step["applications"]
                app["channel"] == id || continue
                L = L .+ app["coefficient"] .* Float64.(values[:, row[app["record_id"]]])
            end
            @test isequal(L, ledger[:, c, n + 1])
        end
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
        for tag in ("lower", "upper"),
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

    @testset "The records against the model's own per-tag ledgers" begin
        check_model_ledgers(simulation)
        # With the constraints at every stage, their maps after each Newton
        # solve enter with the weight b_imp/γ.
        staged = run!(
            build(
                config(
                    "Float64",
                    true,
                    Dict{String, Any}(
                        "update_constrain_state_every" => "stage",
                        "t_end" => "20secs",
                    ),
                ),
                "water_tag_applications_stage",
            ),
        )
        step = check_model_ledgers(staged)
        template = CA.water_meter(staged.integrator.p).template
        @test any(c -> c.role === :post_newton, template.calls)
        post_newton = count(
            a -> a["role"] == "post_newton",
            reduce(
                vcat,
                [s["applications"] for s in read_receipt(staged.output_dir)[2:end]],
            ),
        )
        @info "Applied post-Newton records at stage cadence" post_newton
    end

    @testset "The model's fields do not depend on the producer" begin
        for FT in ("Float64", "Float32")
            on =
                FT == "Float64" ? simulation :
                run!(build(config(FT, true), "water_tag_applications_on32"))
            off = run!(build(config(FT, false), "water_tag_applications_off_$FT"))
            Y_on = on.integrator.u
            Y_off = off.integrator.u
            FT == "Float64" && CTS.step!(off.integrator)
            for name in propertynames(Y_off.c)
                @test isequal(
                    parent(getproperty(Y_on.c, name)),
                    parent(getproperty(Y_off.c, name)),
                )
            end
            @test isequal(parent(Y_on.f), parent(Y_off.f))
            @test isnothing(CA.water_meter(off.integrator.p))
            # The Float64 ledgers, read from their two Float32 slots, are the
            # sums of their channels' applied records.
            FT == "Float32" || continue
            out = on.output_dir
            lines32 = read_receipt(out)
            ds = NCDatasets.NCDataset(joinpath(out, CA.WATER_TAG_APPLICATION_ARRAYS))
            v32 = Array(ds["record_values"][:, :])
            rows32 = Dict(id => r for (r, id) in enumerate(Array(ds["record_id"][:])))
            l32 = Array(ds["ledger"][:, :, :])
            close(ds)
            ids32 = [
                c["id"] for
                c in lines32[1][CA.WATER_TAG_APPLICATION_ROSTER_KEY]["channels"]
            ]
            for (c, id) in enumerate(ids32)
                total = zeros(size(l32, 1))
                for s in lines32[2:end], a in s["applications"]
                    a["channel"] == id || continue
                    total .+= a["coefficient"] .* Float64.(v32[:, rows32[a["record_id"]]])
                end
                @test l32[:, c, end] ≈ total rtol = 1e-12 atol = 1e-30
            end
        end
    end

    @testset "A restarted run gives the continuous run's records" begin
        restart_file = joinpath(dir, "day0.30.hdf5")
        @test isfile(restart_file)
        restarted = run!(
            build(
                config(
                    "Float64",
                    true,
                    Dict{String, Any}("restart_file" => restart_file),
                ),
                "water_tag_applications_restart",
            ),
        )
        rdir = restarted.output_dir
        rlines = read_receipt(rdir)
        @test rlines[1]["ledger_start"] == "checkpoint"
        @test rlines[1]["segment_start_seconds"] == 30.0
        ds = NCDatasets.NCDataset(joinpath(rdir, CA.WATER_TAG_APPLICATION_ARRAYS))
        rvals = Array(ds["record_values"][:, :])
        rids = Array(ds["record_id"][:])
        rledger = Array(ds["ledger"][:, :, :])
        close(ds)
        rsteps = rlines[2:end]
        @test length(rsteps) == 3
        @test [s["id"] for s in rsteps] == [s["id"] for s in steps[4:6]]
        for (rs, s) in zip(rsteps, steps[4:6])
            @test rs == s
        end
        for (r, id) in enumerate(rids)
            @test isequal(rvals[:, r], values[:, row[id]])
        end
        @test isequal(rledger, ledger[:, :, 4:7])
    end

    @testset "Refusals" begin
        no_tags = config("Float64", true)
        delete!(no_tags, "water_tracers")
        delete!(no_tags, "water_tag_precipitation")
        delete!(no_tags, "water_tag_transport")
        delete!(no_tags, "water_tag_ledger_per_tag")
        @test_throws r"needs `water_tracers`" build(
            no_tags,
            "water_tag_applications_no_tags",
        )
        tags = CA.WaterTaggingModel(p.atmos.water_tagging_model.tags; updraft_copies = true)
        @test_throws r"does not support" CA.build_water_tag_application_meter(
            true,
            (; water_tagging_model = tags),
            Y,
            ClimaComms.context(Y.c);
            cadence = "step",
            output_dir = dir,
            t_start = 0.0,
        )
    end
end
