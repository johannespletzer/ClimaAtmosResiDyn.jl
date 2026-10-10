#=
Integration test for the water tags' application producer,
`water_tag_applications: true`, on the column of
`water_tag_applications_common.jl`. That column runs the rescale, the emptying,
the partition repair, the closing step, the follow of rain and snow, and the
follower with its negative water. It checks:
 1. the weights of each role and the integrator pin against the ARS343 and
    ARS222 tableaus.
 2. the receipt: its names, the roster under its key, one accepted trial per
    step, contiguous steps, an applied record of every channel at every step,
    and each weight as the reader computes it from the pin and the step's edges.
 3. a move of the follow between a tag's parts is two legs, and opposite
    applications to one channel in one step stay two records.
 4. the cumulative ledger of each channel is the running sum of its applied
    records, bit for bit.
 5. the applied records of each tag add up to the step changes of the model's
    own ledgers `q_tag_led_fix_<name>` and `q_tag_led_inc_<name>`, to rounding,
    at the default cadence and with the constraints at every stage, where a
    writer call outside the counted hooks is refused.
 6. a run restarted from a checkpoint gives the continuous run's records and
    ledgers, a new segment in the same directory replaces both files, and a
    checkpoint with none or part of the producer's ledgers.
 7. the refusals: without water tags, with the leak correction, with the
    tags' updraft copies and on a GPU device.
 8. the counter codes, and the model identity the receipt writes.
The model's fields with and without the producer are compared in
`water_tag_applications_parity_integration.jl`, in groups of their own.
=#
include("water_tag_applications_common.jl")

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
        # The pin is read from the stepper's cache, as the stepper applies it.
        # ARS222's two tableaus differ, so a pin that swaps them fails here.
        for name in (CTS.ARS343(), CTS.ARS222())
            tableau = CTS.IMEXTableau(name)
            alg = CTS.IMEXAlgorithm(name, CTS.NewtonsMethod())
            pin = CA.water_tag_application_pin((; alg, cache = (; tableau)))
            @test pin.algorithm == "unconstrained_imex_ark"
            @test pin.tableau == string(nameof(typeof(name)))
            @test pin.b_exp == Float64.(tableau.b_exp.coeffs)
            @test pin.b_imp == Float64.(tableau.b_imp.coeffs)
            @test pin.implicit_diagonal == Float64.(diag(tableau.a_imp.coeffs))
        end
        ars222 = CTS.IMEXTableau(CTS.ARS222())
        @test ars222.b_exp.coeffs != ars222.b_imp.coeffs
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

    @testset "The model identity: commit, dirty tree and the diff's sha256" begin
        repo = mktempdir()
        git(args...) = run(pipeline(`git -C $repo $args`; stdout = devnull))
        @test CA._git_identity(repo) == ("unknown", true, "unknown")
        git("init", "-q")
        write(joinpath(repo, "a.txt"), "a\n")
        git("add", "a.txt")
        git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
            "commit", "-qm", "a")
        commit, dirty, diff_sha256 = CA._git_identity(repo)
        @test occursin(r"^[0-9a-f]{40}$", commit)
        @test !dirty
        # The sha256 of the empty string, for a clean tree.
        @test diff_sha256 ==
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        write(joinpath(repo, "a.txt"), "b\n")
        commit_dirty, dirty, diff_sha256 = CA._git_identity(repo)
        @test commit_dirty == commit
        @test dirty
        @test occursin(r"^[0-9a-f]{64}$", diff_sha256)
        @test diff_sha256 !=
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end

    simulation = run!(
        compile_metered_writers(build(config("Float64", true), "water_tag_applications")),
    )
    Y = simulation.integrator.u
    p = simulation.integrator.p
    meter = CA.water_meter(p)
    dir = simulation.output_dir
    lines = read_receipt(dir)
    header, steps = first(lines), lines[2:end]
    pin = header["integrator_pin"]
    channels = header["water_tag_application_roster"]
    arrays = read_arrays(dir)
    (; values, ledger, ledger_time) = arrays
    record_ids = arrays.ids
    row = Dict(id => r for (r, id) in enumerate(record_ids))

    @testset "The receipt" begin
        @test header["schema_version"] == 1
        @test header["semantics"] == "weighted_final_additive_updates"
        @test header["kind"] == "runtime_capture"
        @test header["producer"] == "climaatmos.water_tag_applications"
        @test header["precision"] == "Float64"
        @test header["ledger_start"] == "zero"
        @test header["segment_start_seconds"] == 0.0
        @test CA.WATER_TAG_APPLICATION_RECEIPT == "water_tag_application_receipt.jsonl"
        @test header["native_arrays"] == CA.WATER_TAG_APPLICATION_ARRAYS ==
              "water_tag_applications.nc"
        @test header["model_diff_sha256"] == "unknown" ||
              occursin(r"^[0-9a-f]{64}$", header["model_diff_sha256"])
        # The roster, as the reader's gate reads it: a list of channel ids
        # under the key the header names.
        @test header["roster_key"] == "water_tag_application_roster"
        expected = String[]
        # Two region tags and one source tag. The repair and the close belong
        # to the partition alone. The increment follower and the negative
        # giver meter every tag.
        for (t, partition) in (("lower", true), ("upper", true), ("evap", false))
            N = "nonprecipitating"
            append!(expected, ["rescale.$t.$N", "empty.$t.$N"])
            partition && append!(
                expected,
                [
                    "repair.$t.$N", "repair.$t.rain", "repair.$t.snow",
                    "close.$t.rain", "close.$t.snow",
                ],
            )
            append!(
                expected,
                [
                    "follow.$t.$N", "follow.$t.rain", "follow.$t.snow",
                    "inc.$t.$N", "negative.$t.$N",
                ],
            )
        end
        @test channels == expected
        @test header["water_tag_application_unsupported"] == []
        described = header["water_tag_application_channels"]
        @test [c["id"] for c in described] == channels
        scale = Dict(
            "rescale" => "rho_q_tot_before",
            "empty" => "rho_q_tot_before",
            "repair" => "partition_positive_part",
        )
        for c in described
            (m, t, part) = split(c["id"], ".")
            @test (c["mechanism"], c["tag"], c["compartment"]) == (m, t, part)
            tendency = m in ("inc", "negative")
            @test c["quantity"] == (tendency ? "water_tendency" : "water_increment")
            @test c["units"] == (tendency ? "kg m^-3 s^-1" : "kg m^-3")
            @test c["event_scale"] == get(scale, m, "rho_q_tot")
            @test c["status"] == "observed"
        end
        @test arrays.attrib["weight_units"] == "m"
        @test arrays.attrib["precision"] == "Float64"
        @test arrays.attrib["flags"] ==
              "fallback + 2 bound + 4 clamp + 8 zero_normalization"
        # The pin is the configured stepper's, ARS343.
        @test simulation.integrator.alg.name isa CTS.ARS343
        tableau = CTS.IMEXTableau(CTS.ARS343())
        @test pin["algorithm"] == "unconstrained_imex_ark"
        @test pin["package"] == "ClimaTimeSteppers"
        @test pin["tableau"] == "ARS343"
        @test pin["b_exp"] == Float64.(tableau.b_exp.coeffs)
        @test pin["b_imp"] == Float64.(tableau.b_imp.coeffs)
        @test pin["implicit_diagonal"] == Float64.(diag(tableau.a_imp.coeffs))
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
                    @test app["coefficient_units"] == "1"
                elseif role == "implicit"
                    @test app["coefficient"] === (b - a) * pin["b_imp"][app["stage"]]
                    @test app["coefficient_units"] == "s"
                else
                    @test role == "post_newton"
                    @test app["coefficient_units"] == "1"
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

    @testset "The records against the model's own per-tag ledgers" begin
        check_model_ledgers(simulation)
        # With the constraints at every stage, their maps after each Newton
        # solve enter with the weight b_imp/γ.
        # Each step's finalization refuses writer calls outside the counted
        # hooks, so this run also shows there are none at this cadence.
        staged = run!(
            compile_metered_writers(
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
        @test post_newton > 0
        # A writer called outside the counted hooks has no role in the step.
        # The step's finalization refuses it, with the count and the call.
        staged_meter = CA.water_meter(staged.integrator.p)
        tag = first(staged.integrator.p.atmos.water_tagging_model.tags)
        CA.meter_water_leg!(staged_meter, :rescale, tag, CA.NonPrecipitatingPart(), 0, 0, 0)
        @test staged_meter.unattributed == 1
        @test_throws r"saw 1 writer calls outside the counted hooks.*the rescale of lower, before any counted firing" CTS.step!(
            staged.integrator,
        )
    end

    @testset "A restarted run gives the continuous run's records" begin
        restart_file = joinpath(dir, "day0.30.hdf5")
        @test isfile(restart_file)
        restarted = run!(
            build(
                config("Float64", true, Dict{String, Any}("restart_file" => restart_file)),
                "water_tag_applications_restart",
            ),
        )
        rdir = restarted.output_dir
        rlines = read_receipt(rdir)
        @test rlines[1]["ledger_start"] == "checkpoint"
        @test rlines[1]["segment_start_seconds"] == 30.0
        rarrays = read_arrays(rdir)
        rsteps = rlines[2:end]
        @test length(rsteps) == 3
        @test [s["id"] for s in rsteps] == [s["id"] for s in steps[4:6]]
        for (rs, s) in zip(rsteps, steps[4:6])
            @test rs == s
        end
        for (r, id) in enumerate(rarrays.ids)
            @test isequal(rarrays.values[:, r], values[:, row[id]])
            @test isequal(rarrays.scales[:, r], arrays.scales[:, row[id]])
            @test isequal(rarrays.flags[:, r], arrays.flags[:, row[id]])
            @test rarrays.channel[r] == arrays.channel[row[id]]
        end
        @test isequal(rarrays.ledger, ledger[:, :, 4:7])
        @test rarrays.ledger_time == ledger_time[4:7]
        # A new segment started in the same directory replaces both files, so
        # the receipt and the native arrays hold the same steps.
        CA.water_meter(restarted.integrator.p).started = false
        CTS.step!(restarted.integrator)
        again = read_receipt(rdir)
        @test length(again) == 2
        @test again[1]["segment_start_seconds"] == 60.0
        segment = read_arrays(rdir)
        @test segment.ids == [a["record_id"] for a in again[2]["applications"]]
        @test segment.ledger_time == [60.0, again[2]["end_seconds"]]
        @test isequal(segment.ledger[:, :, 1], ledger[:, :, 7])
    end

    @testset "Checkpoints with none or part of the producer's ledgers" begin
        restart_file = joinpath(dir, "day0.30.hdf5")
        reader = CA.InputOutput.HDF5Reader(restart_file, ClimaComms.context(Y.c))
        fields = CA.water_application_checkpoint_fields(meter)
        @test length(fields) == length(channels)
        before = [copy(parent(L)) for L in meter.ledgers]
        # None of them, as a checkpoint written without the producer: a
        # warning, and the ledgers start at zero.
        absent = ["$(name).absent" => L for (name, L) in fields]
        @test_logs (:warn, r"carries none of the water tag producer's ledgers") CA.restore_water_application_ledgers!(
            meter,
            reader,
            absent,
            restart_file,
        )
        @test meter.ledger_start == "zero_at_restart"
        @test all(map((a, L) -> isequal(a, parent(L)), before, meter.ledgers))
        # Part of them, as one written with another roster: refused.
        @test_throws r"carries only part of the water tag producer's ledgers" CA.restore_water_application_ledgers!(
            meter,
            reader,
            [first(fields), last(absent)],
            restart_file,
        )
        Base.close(reader)
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
        refused(kwargs, context = ClimaComms.context(Y.c)) =
            CA.build_water_tag_application_meter(
                true,
                (;
                    water_tagging_model = CA.WaterTaggingModel(
                        p.atmos.water_tagging_model.tags;
                        kwargs...,
                    )
                ),
                Y,
                context;
                cadence = "step",
                output_dir = mktempdir(pwd()),
                t_start = 0.0,
            )
        @test_throws r"`water_tag_updraft_copy: true`. The copies' repair and filter are not metered" refused(
            (; updraft_copies = true),
        )
        @test_throws r"`water_tag_leak_correction: true`. The leak correction is not metered yet" refused(
            (; leak_correction = true),
        )
        # A CUDA device in the context is enough. The check needs no GPU.
        gpu = ClimaComms.SingletonCommsContext(ClimaComms.CUDADevice())
        @test_throws r"`water_tag_applications: true` has not been tried on a GPU" refused(
            (;),
            gpu,
        )
    end
end
