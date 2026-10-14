#=
The model's fields do not depend on the water tags' application producer. The
column of `water_tag_applications_common.jl` is built with
`water_tag_applications: true` and without it, in one float type. The two take
the same six steps, and after each one every field of `Y.c` and `Y.f` is the
same bit for bit. The run with the producer applies non-zero records, and each
channel's cumulative ledger, read from the native arrays, is the sum of its
applied records. `runtests.jl` calls `check_parity` once per process, for
Float64 in `tagging_water_applications_parity` and for Float32 in
`tagging_water_applications_float32`.
=#
include("water_tag_applications_common.jl")

function check_parity(FT)
    on = compile_metered_writers(build(config(FT, true), "water_tag_applications_on_$FT"))
    off = compile_metered_writers(
        build(config(FT, false), "water_tag_applications_off_$FT"),
    )
    @test isnothing(CA.water_meter(off.integrator.p))
    @test !isnothing(CA.water_meter(on.integrator.p))
    Y_on = on.integrator.u
    Y_off = off.integrator.u
    @test eltype(Y_on) == eltype(Y_off) == getproperty(Base, Symbol(FT))
    @testset "The model's fields after each step, in $FT" begin
        for n in 1:6
            CTS.step!(on.integrator)
            CTS.step!(off.integrator)
            @test on.integrator.t == off.integrator.t
            for name in propertynames(Y_off.c)
                @test isequal(
                    parent(getproperty(Y_on.c, name)),
                    parent(getproperty(Y_off.c, name)),
                )
            end
            @test isequal(parent(Y_on.f), parent(Y_off.f))
        end
    end
    @testset "The records and the ledgers, in $FT" begin
        lines = read_receipt(on.output_dir)
        arrays = read_arrays(on.output_dir)
        @test length(lines) == 7
        @test lines[1]["precision"] == FT
        rows = Dict(id => r for (r, id) in enumerate(arrays.ids))
        applied = [a for s in lines[2:end] for a in s["applications"]]
        nonzero = count(a -> any(!iszero, arrays.values[:, rows[a["record_id"]]]), applied)
        @info "Applied records with a non-zero cell, in $FT" nonzero length(applied)
        @test nonzero > 0
        @test any(!iszero, arrays.ledger[:, :, end])
        for (c, id) in enumerate(lines[1]["water_tag_application_roster"])
            total = zeros(size(arrays.ledger, 1))
            for a in applied
                a["channel"] == id || continue
                total .+=
                    a["coefficient"] .* Float64.(arrays.values[:, rows[a["record_id"]]])
            end
            @test arrays.ledger[:, c, end] ≈ total rtol = 1e-12 atol = 1e-30
        end
    end
end
