#=
Self-test for the tag-closure analysis, on synthetic input.

The plan says the reducer and the phase scripts are exercised on synthetic input
before any result exists, so they are tested before the owner runs anything. The
container they were written in has no Julia, so **this is the first execution of
any of it**. Run it once on Levante before submitting a job:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/selftest.jl

It builds a synthetic NetCDF run and synthetic closure tables in a temporary
directory, drives `reduce_run.jl` and `phase_a.jl` over them, and asserts values
worked out by hand rather than merely checking that nothing threw. It writes
nothing into the repository. A non-zero exit means the analysis is broken, not
that a run is.

## What the assertions pin

The arithmetic the whole of phase A rests on, in three parts.

**The order.** The operator residual is the pointwise field summed first and
reduced afterwards. Reducing each term on its own and adding the scalars is a
different, larger number, and the synthetic field below separates the two by
construction.

**The sign.** The ledger holds `new - old`. The first synthetic time is the
partition repair's zeroing branch, taken from `repair_water_tag_partition!`: a
cell whose negatives outweigh its positives has every tag zeroed, so the water
that the repair removed from the parent's account surfaces in `q_tag_res`, and
adding the ledger back recovers the residual the run would have reported had the
repair never run.

**The membership.** `i` runs over the pure region tags only. The synthetic run
carries a `q_tag_fix_evap` two orders larger than everything else, so a reducer
that summed a source tag's ledger would miss by a factor no rounding could
explain.

## The worked case

One time, four cells, `ρ = 1`, tags `upper` and `lower`, parent `ρq_tot = 10`.

  - Before the repair the cell holds `upper = 2`, `lower = -5`. Their sum is
    `-3`, so the residual then is `10 - (-3) = 13`.
  - `S⁺ = 2` and `S⁻ = -5`, so `S⁺ + S⁻ = -3 < 0` and the factor is
    `max(-3, 0) / 2 = 0`. Both tags go to zero.
  - The ledger is `new - old`: `fix_upper = -2`, `fix_lower = +5`, summing
    to `+3`.
  - `q_tag_res` afterwards is `10 - 0 = 10`.
  - The operator residual is `10 + 3 = 13`, which is the pre-repair residual.

So the expected row is `operator = 13`, `q_tag_res = 10`, `ledger_sum = 3`.

Note what that says about direction. The operator residual here is **larger**
than `q_tag_res`, not smaller. The repair's ledger is never negative in sum: it
is zero on the sum-preserving branch and `-(old sum) > 0` on the zeroing branch.
The invariant to check is the identity with the pre-correction residual, and an
assertion that the operator residual is the smaller of the two would fire on
almost every real run.
=#

import NCDatasets

const HERE = @__DIR__

"""
    load_script(path)

Load one analysis script into a module of its own and return the module.

Each script defines a `main`, and this file does too, so including them all into
`Main` would leave several definitions of one name and the last one would win. A
module apiece keeps them apart. `Base.include` also leaves `PROGRAM_FILE`
pointing at this file, so a script's own `if abspath(PROGRAM_FILE) == @__FILE__`
guard does not fire and nothing runs on load.

**A module built by `Module(...)` is not one the parser created**, so the names
the parser normally injects into a `module ... end` block are not there to be
relied on. `include` is the one that bites: every phase script includes
`tables.jl`, and that call resolves inside this module, where the name does not
exist. `eval` has the same gap. Both are defined here, bound to this module,
before the file is loaded into it. `Base.include` takes its module explicitly
and so never needed them, which is why a script that includes nothing loaded
fine and one that includes something did not.

`Base.include` records the path it was given as the file being loaded, so
`@__DIR__` inside the script resolves to the script's own directory and
`tables.jl` is found beside it rather than relative to the caller.

The methods are defined while this one is already running, so every call into a
loaded script goes through `Base.invokelatest`.
"""
function load_script(path)
    loaded = Module(Symbol(:UnderTest_, basename(path)))
    isdefined(loaded, :include) ||
        Base.eval(loaded, :(include(file) = Base.include($loaded, file)))
    isdefined(loaded, :eval) ||
        Base.eval(loaded, :(eval(expr) = Core.eval($loaded, expr)))
    Base.include(loaded, path)
    return loaded
end

call(loaded, name, args...; kwargs...) =
    Base.invokelatest(getfield(loaded, Symbol(name)), args...; kwargs...)

"""
    write_synthetic_run(dir)

A synthetic run directory: a configuration snapshot, a NetCDF file holding the
tag diagnostics, and a `provenance.txt`.

Two times over four cells. The first is the repair's zeroing branch worked out
in the header; the second is an ordinary cell where the ledger partly cancels
the residual, so the two rows do not share an answer by accident.
"""
function write_synthetic_run(dir)
    mkpath(dir)

    write(
        joinpath(dir, "a1_dt10.yml"),
        """
        job_id: a1_dt10
        config: column
        dt: 10secs
        FLOAT_TYPE: Float64
        microphysics_model: 0M
        tracer_upwinding: vanleer_limiter
        water_tracers:
          - name: upper
            region: {type: tanh_altitude, z_center: 600.0, width: 100.0}
          - name: lower
            region: {type: tanh_altitude, z_center: 600.0, width: 100.0, above: false}
          - name: evap
            source: surface_flux
        """,
    )

    write(
        joinpath(dir, "provenance.txt"),
        """
        run: a1_dt10
        commit: 0123456789abcdef0123456789abcdef01234567
        finished: 2026-09-09T12:00:00+00:00
        exit_status: 0
        """,
    )

    times = [0.0, 60.0]
    # (time, z), built one time row at a time. A space-separated matrix literal
    # is whitespace-sensitive about a leading minus -- `[0.0 -4.0]` is two
    # elements and `[0.0 - 4.0]` is one -- so build it from vectors instead,
    # where there is nothing to misread.
    rows(a, b) = permutedims(hcat(a, b))
    # Row 1 is the worked case in the header; row 2 is an ordinary cell where
    # the ledger partly cancels the residual.
    q_tag_res = rows([10.0, 0.0, 0.0, 0.0], [0.0, -4.0, 0.0, 1.0])
    fix_upper = rows([-2.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0])
    fix_lower = rows([5.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0])
    # A source tag's ledger, two orders larger. A reducer that summed it would
    # report about 103 and 102 instead of 13 and 2.
    fix_evap = rows(fill(100.0, 4), fill(100.0, 4))

    NCDatasets.NCDataset(joinpath(dir, "diagnostics.nc"), "c") do ds
        NCDatasets.defDim(ds, "time", length(times))
        NCDatasets.defDim(ds, "z", size(q_tag_res, 2))
        NCDatasets.defVar(ds, "time", times, ("time",))
        NCDatasets.defVar(ds, "z", collect(1.0:size(q_tag_res, 2)), ("z",))
        for (name, data) in (
            "q_tag_res" => q_tag_res,
            "q_tag_fix_upper" => fix_upper,
            "q_tag_fix_lower" => fix_lower,
            "q_tag_fix_evap" => fix_evap,
        )
            NCDatasets.defVar(ds, name, data, ("time", "z"))
        end
    end
    return dir
end

"""
    write_synthetic_closure(dir, run, dt, values)

A synthetic `water_tag_closure.csv` with the real column set, so the phase
script is read against the shape the model actually writes.
"""
function write_synthetic_closure(dir, run, dt, values)
    path = joinpath(dir, "water_tag_closure.csv")
    open(path, "w") do io
        println(
            io,
            "time,total,tagged,residual,relative,gross_residual," *
            "gross_relative,scale,nonpositive_fraction",
        )
        for (index, value) in enumerate(values)
            t = (index - 1) * dt
            println(io, "$t,1.0,1.0,0.0,0.0,$value,$value,1.0,0.0")
        end
    end
    return path
end

"""
    write_synthetic_operator(dir, values)

A synthetic `operator_residual.csv` in the shape `reduce_run.jl` writes, comment
block included, so the phase script's reader is tested against it.
"""
function write_synthetic_operator(dir, values)
    path = joinpath(dir, "operator_residual.csv")
    open(path, "w") do io
        println(io, "# operator_residual.csv, from analysis/reduce_run.jl")
        println(io, "# a comment block the reader has to skip")
        println(
            io,
            "time,geometry,remapped,max_abs_operator_residual," *
            "max_abs_q_tag_res,max_abs_ledger_sum,max_abs_q_tag_fix_upper," *
            "max_abs_q_tag_fix_lower",
        )
        for (index, value) in enumerate(values)
            t = (index - 1) * 60.0
            println(io, "$t,column,false,$value,$value,0.0,0.0,0.0")
        end
    end
    return path
end

function test_reducer()
    @info "1. reduce_run.jl on a synthetic NetCDF run"
    mktempdir() do tmp
        run_dir = write_synthetic_run(joinpath(tmp, "output_active"))
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_run, run_dir)

        @assert metadata.regions == ["upper", "lower"] "region tags: $(metadata.regions)"
        @assert metadata.geometry == "column"
        @assert metadata.remapped == false "a column must not be marked remapped"

        index = Dict(name => i for (i, name) in enumerate(header))
        operator = [row[index["max_abs_operator_residual"]] for row in rows]
        residual = [row[index["max_abs_q_tag_res"]] for row in rows]
        ledger = [row[index["max_abs_ledger_sum"]] for row in rows]

        # The worked case in the header, and its second row.
        @assert operator ≈ [13.0, 2.0] "operator residual: $operator, want [13.0, 2.0]"
        @assert residual ≈ [10.0, 4.0] "q_tag_res: $residual, want [10.0, 4.0]"
        @assert ledger ≈ [3.0, 2.0] "ledger sum: $ledger, want [3.0, 2.0]"

        # The identity: the operator residual is the residual the run would
        # have reported had no correction run. Row 1 is 10 + 3 = 13.
        @assert operator[1] ≈ residual[1] + ledger[1]

        # Membership. Had `q_tag_fix_evap` been summed, row 1 would be about
        # 103 rather than 13.
        @assert operator[1] < 20 "a source tag's ledger was summed"

        # Order. Reducing each term separately and adding gives 10 + 2 + 5 = 17
        # on row 1, not 13.
        @assert !isapprox(operator[1], 17.0) "each term was reduced before summing"

        # Row 2 separates the two orders again: summed first gives
        # max|[0, -2, 0, 1]| = 2, reduced first would give 4 + 1 + 1 = 6.
        @assert operator[2] ≈ 2.0 && !isapprox(operator[2], 6.0)

        path = call(reducer, :write_operator_residual, run_dir, header, rows, metadata)
        @assert isfile(path)
        text = read(path, String)
        @assert occursin("Column geometry", text) "the geometry note is missing"
        @assert occursin("max_abs_operator_residual", text)
        @info "   as computed by hand: operator $operator, \
               q_tag_res $residual, ledger $ledger"
    end
end

function test_sphere_is_flagged()
    @info "2. a sphere run is marked as remapped"
    mktempdir() do tmp
        run_dir = write_synthetic_run(joinpath(tmp, "output_active"))
        snapshot = joinpath(run_dir, "a1_dt10.yml")
        write(
            snapshot,
            replace(read(snapshot, String), "config: column" => "config: sphere"),
        )
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        _, _, metadata = call(reducer, :reduce_run, run_dir)
        @assert metadata.remapped "a sphere must be marked remapped"
        @info "   sphere geometry carries the remapping warning"
    end
end

function test_phase_a()
    @info "3. phase_a.jl on synthetic tables"
    mktempdir() do tmp
        output = joinpath(tmp, "output")
        for (run, dt, upwinding, tail) in (
            ("a1_dt10", 10.0, "vanleer_limiter", 1.0e-3),
            ("a1_dt5", 5.0, "vanleer_limiter", 9.0e-4),
            ("a1_dt2p5", 2.5, "vanleer_limiter", 8.5e-4),
            ("a2_none_dt10", 10.0, "none", 4.0e-4),
            ("a2_none_dt5", 5.0, "none", 2.0e-4),
            ("a2_none_dt2p5", 2.5, "none", 1.0e-4),
            ("a3_1m", 10.0, "vanleer_limiter", 5.0e-3),
            ("a4_float32", 10.0, "vanleer_limiter", 2.0e-3),
        )
            dir = joinpath(output, run)
            mkpath(dir)
            micro = run == "a3_1m" ? "1M" : "0M"
            float_type = run == "a4_float32" ? "Float32" : "Float64"
            write(
                joinpath(dir, run * ".yml"),
                """
                job_id: $run
                config: column
                dt: $(dt)secs
                FLOAT_TYPE: $float_type
                microphysics_model: $micro
                tracer_upwinding: $upwinding
                """,
            )
            write(
                joinpath(dir, "provenance.txt"),
                "run: $run\ncommit: 0123456789abcdef\nfinished: 2026-09-09T12:00:00\n",
            )
            write_synthetic_closure(dir, run, dt, [tail / 2, tail])
            write_synthetic_operator(dir, [tail / 2, tail])
        end
        # A run handed back without provenance must be refused, not analysed.
        orphan = joinpath(output, "a5_sphere_limiter")
        mkpath(orphan)
        write_synthetic_closure(orphan, "a5_sphere_limiter", 300.0, [1.0e-2, 2.0e-2])

        phase = load_script(joinpath(HERE, "phase_a.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase, :main)
        end

        summary = joinpath(output, "summary_a.csv")
        @assert isfile(summary) "no summary_a.csv"
        text = read(summary, String)
        @assert occursin("a1_dt10", text) && occursin("a2_none_dt2p5", text)
        @assert !occursin("a5_sphere_limiter", text) "a run with no provenance was analysed"

        plots = joinpath(tmp, "plots")
        for name in (
            "a_gross_relative_vs_time.png",
            "a_operator_residual_vs_dt.png",
            "a_variants_vs_time.png",
        )
            @assert isfile(joinpath(plots, name)) "missing plot $name"
        end
        @info "   summary and three PNGs written; the run without provenance was refused"
    end
end

function test_slope()
    @info "4. the log-log slope fit"
    phase = load_script(joinpath(HERE, "phase_a.jl"))
    # y = x^2 exactly, so the slope must be 2.
    slope = call(phase, :fit_slope, [1.0, 2.0, 4.0], [1.0, 4.0, 16.0])
    @assert isapprox(slope, 2.0; atol = 1e-10) "slope $slope, want 2"
    # A flat ladder has slope zero: the case that says the residual is
    # structural and implicit tags would buy nothing.
    flat = call(phase, :fit_slope, [2.5, 5.0, 10.0], [1.0e-3, 1.0e-3, 1.0e-3])
    @assert isapprox(flat, 0.0; atol = 1e-10) "flat slope $flat, want 0"
    @assert isnan(call(phase, :fit_slope, [1.0], [1.0])) "one point is not a slope"
    @info "   slope 2 recovered from y = x², 0 from a flat ladder"
end


"""
    write_energy_run(dir; family, record = family == "energy_source")

A synthetic run for the energy (`"energy"`) or energy-source
(`"energy_source"`) family: a snapshot, a NetCDF file, a closure table and a
provenance file.

`record` adds an `energy_process_record` and the `e_prc_<process>` field that
goes with it. It is what separates a C0 run from a C3 one, and the two-readings
panel is drawn only from a run that has both series, so a fixture of C0 runs
alone cannot produce it.

Neither family has a ledger, so there is nothing to add back and the reducer's
job is a plain reduction. What the source family adds is the per-tag minimum,
which is the number phase C turns on: `e_src_res` sums the pure region tags
only, so a source-labelled tag going negative never enters it.
"""
function write_energy_run(dir; family, record = family == "energy_source")
    mkpath(dir)
    name = basename(dir)
    is_source = family == "energy_source"
    key = is_source ? "energy_source_tags" : "energy_tracers"
    prefix = is_source ? "e_src_" : "e_tag_"

    write(
        joinpath(dir, name * ".yml"),
        """
        job_id: $name
        config: column
        dt: 400secs
        FLOAT_TYPE: Float64
        microphysics_model: 0M
        $key:
          - name: tropics
            region: tropics
          - name: extratropics
            region: extratropics
          - name: src
            source: surface_flux
        $(record ? "energy_process_record: [surface_flux]" : "")
        """,
    )
    write(
        joinpath(dir, "provenance.txt"),
        "run: $name\ncommit: 0123456789abcdef\nfinished: 2026-09-09T12:00:00\n",
    )

    times = [0.0, 3600.0]
    rows(a, b) = permutedims(hcat(a, b))
    residual = rows([1.0, -3.0, 0.0, 2.0], [0.0, 0.5, 0.0, 0.0])
    # The region tags stay positive; `src` goes negative at the second time.
    # That is the case e_src_res cannot show, so the minimum has to.
    tropics = rows([5.0, 6.0, 7.0, 8.0], [5.0, 6.0, 7.0, 8.0])
    extratropics = rows([1.0, 1.0, 1.0, 1.0], [2.0, 2.0, 2.0, 2.0])
    src = rows([0.0, 0.0, 0.0, 0.0], [-4.0, 1.0, 1.0, 1.0])

    NCDatasets.NCDataset(joinpath(dir, "diagnostics.nc"), "c") do ds
        NCDatasets.defDim(ds, "time", length(times))
        NCDatasets.defDim(ds, "z", 4)
        NCDatasets.defVar(ds, "time", times, ("time",))
        NCDatasets.defVar(ds, "z", collect(1.0:4.0), ("z",))
        NCDatasets.defVar(ds, prefix * "res", residual, ("time", "z"))
        if is_source
            NCDatasets.defVar(ds, prefix * "tropics", tropics, ("time", "z"))
            NCDatasets.defVar(ds, prefix * "extratropics", extratropics, ("time", "z"))
            NCDatasets.defVar(ds, prefix * "src", src, ("time", "z"))
        end
        if record
            # The process record. Its diagnostic short name is `e_prc_*` even
            # though the state field is `prc_e_*`, and only the NetCDF carries
            # it, which is why the reducer has to bring it out.
            NCDatasets.defVar(
                ds, "e_prc_surface_flux",
                rows([2.0, 2.0, 2.0, 2.0], [-7.0, 3.0, 3.0, 3.0]),
                ("time", "z"),
            )
        end
    end

    # A closure table with the real column set, including nonpositive_fraction.
    open(joinpath(dir, family * "_tag_closure.csv"), "w") do io
        println(
            io,
            "time,total,tagged,residual,relative,gross_residual," *
            "gross_relative,scale,nonpositive_fraction",
        )
        println(io, "0.0,1.0,1.0,0.0,0.0,1.0e-4,1.0e-4,1.0,0.0")
        println(io, "3600.0,1.0,1.0,0.0,0.0,5.0e-4,5.0e-4,1.0,0.75")
    end
    return dir
end

function test_energy_reducer()
    @info "5. reduce_run.jl on the energy family"
    mktempdir() do tmp
        run_dir = write_energy_run(joinpath(tmp, "b1_base"); family = "energy")
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_energy_tags, run_dir)
        index = Dict(name => i for (i, name) in enumerate(header))
        values = [row[index["max_abs_e_tag_res"]] for row in rows]
        # max|[1, -3, 0, 2]| = 3 and max|[0, 0.5, 0, 0]| = 0.5.
        @assert values ≈ [3.0, 0.5] "e_tag_res: $values, want [3.0, 0.5]"
        @assert metadata.remapped == false
        @info "   max |e_tag_res| $values — as computed by hand"
    end
end

function test_source_reducer()
    @info "6. reduce_run.jl on the energy source family"
    mktempdir() do tmp
        run_dir =
            write_energy_run(joinpath(tmp, "c0_column"); family = "energy_source")
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_source_tags, run_dir)
        index = Dict(name => i for (i, name) in enumerate(header))

        residual = [row[index["max_abs_e_src_res"]] for row in rows]
        @assert residual ≈ [3.0, 0.5] "e_src_res: $residual"

        # The whole point: the source tag dips to -4 at the second time while
        # both region tags stay positive, so the residual above cannot show it.
        min_src = [row[index["min_e_src_src"]] for row in rows]
        @assert min_src ≈ [0.0, -4.0] "min of the source tag: $min_src"
        min_tropics = [row[index["min_e_src_tropics"]] for row in rows]
        @assert all(>=(0), min_tropics) "the region tag should stay positive"

        # Every tag is covered, source-labelled ones included.
        for name in ("tropics", "extratropics", "src")
            @assert haskey(index, "min_e_src_" * name) "no minimum for $name"
            @assert haskey(index, "max_e_src_" * name) "no maximum for $name"
        end
        @info "   the source tag's minimum reached $(min_src[2]) while \
               max |e_src_res| stayed at $(residual[2]); only the minima show it"
    end
end

function test_process_record()
    @info "8. reduce_run.jl on the energy process record"
    mktempdir() do tmp
        run_dir =
            write_energy_run(joinpath(tmp, "c3_column_record"); family = "energy_source")
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_process_record, run_dir)
        index = Dict(name => i for (i, name) in enumerate(header))
        @assert haskey(index, "min_e_prc_surface_flux") "no record minimum"
        @assert haskey(index, "max_e_prc_surface_flux") "no record maximum"
        mins = [row[index["min_e_prc_surface_flux"]] for row in rows]
        maxs = [row[index["max_e_prc_surface_flux"]] for row in rows]
        # A record goes negative under net cooling, so both ends matter.
        @assert mins ≈ [2.0, -7.0] "record minima: $mins, want [2.0, -7.0]"
        @assert maxs ≈ [2.0, 3.0] "record maxima: $maxs, want [2.0, 3.0]"
        # The run name comes from the snapshot's file name, not a job_id key
        # that the merged snapshot never carries.
        @assert metadata.job_id == "c3_column_record" "job_id $(metadata.job_id)"
        @info "   record min $mins max $maxs, stamped run $(metadata.job_id)"
    end
end

function test_phase_b_and_c()
    @info "7. phase_b.jl and phase_c.jl on synthetic tables"
    mktempdir() do tmp
        output = joinpath(tmp, "output")
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        # Phase B: the four-run split, plus the timing control. The control
        # carries no tag family and so no closure table, which is a path
        # through `load_run` that nothing else here takes.
        control = write_energy_run(
            joinpath(output, "b1_notags"); family = "energy", record = false,
        )
        rm(joinpath(control, "energy_tag_closure.csv"))

        # Phase B: the four-run split.
        for (run, tail) in (
            ("b1_base", 5.0e-3), ("b1a_no_hyperdiff", 3.0e-3),
            ("b1b_no_vert_diff", 4.0e-3), ("b1c_neither", 1.0e-3),
        )
            dir = write_energy_run(joinpath(output, run); family = "energy")
            header, rows, metadata = call(reducer, :reduce_energy_tags, dir)
            call(
                reducer, :write_table, dir, "energy_tag_residual", header, rows,
                metadata, "synthetic",
            )
            # Give each variant its own final gross_relative.
            open(joinpath(dir, "energy_tag_closure.csv"), "w") do io
                println(
                    io,
                    "time,total,tagged,residual,relative,gross_residual," *
                    "gross_relative,scale,nonpositive_fraction",
                )
                println(io, "0.0,1.0,1.0,0.0,0.0,$(tail / 5),$(tail / 5),1.0,0.0")
                println(io, "3600.0,1.0,1.0,0.0,0.0,$tail,$tail,1.0,0.0")
            end
        end
        # Phase C: the census run, which carries no process record, and the
        # C3 run, which does. The pair is the point: the two-readings panel is
        # drawn from a run that has both series, and a run without the record
        # must not contribute to it. With only c0_column here the panel could
        # never be drawn, and the assertion below would be demanding an output
        # the fixture cannot produce.
        c_dir = write_energy_run(
            joinpath(output, "c0_column"); family = "energy_source", record = false,
        )
        header, rows, metadata = call(reducer, :reduce_source_tags, c_dir)
        call(
            reducer, :write_table, c_dir, "source_tag_extrema", header, rows,
            metadata, "synthetic",
        )

        c3_dir = write_energy_run(
            joinpath(output, "c3_column_record"); family = "energy_source",
        )
        header, rows, metadata = call(reducer, :reduce_source_tags, c3_dir)
        call(
            reducer, :write_table, c3_dir, "source_tag_extrema", header, rows,
            metadata, "synthetic",
        )
        header, rows, metadata = call(reducer, :reduce_process_record, c3_dir)
        call(
            reducer, :write_table, c3_dir, "process_record_extrema", header,
            rows, metadata, "synthetic",
        )

        phase_b = load_script(joinpath(HERE, "phase_b.jl"))
        phase_c = load_script(joinpath(HERE, "phase_c.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase_b, :main)
            call(phase_c, :main)
        end

        for name in ("summary_b.csv", "summary_c.csv")
            @assert isfile(joinpath(output, name)) "no $name"
        end
        plots = joinpath(tmp, "plots")
        for name in (
            "b_gross_relative_bars.png",
            "b_gross_relative_vs_time.png",
            "c_nonpositive_fraction.png",
            "c_min_tag_value.png",
            "c_e_src_res.png",
            "c_two_readings.png",
        )
            @assert isfile(joinpath(plots, name)) "missing plot $name"
        end

        # The two-readings panel is the whole reason C3 exists, so assert what
        # it was drawn from rather than only that a file appeared. It needs a
        # run carrying both series, and `load_run` has to read the record table
        # for that run to have them.
        c_summary = read(joinpath(output, "summary_c.csv"), String)
        @assert occursin("c3_column_record", c_summary) "C3 is missing from the summary"
        @assert occursin("surface_flux", c_summary) "the recorded process is missing"
        @assert occursin("b1_notags", read(joinpath(output, "summary_b.csv"), String)) \
            "the phase B timing control is missing from the summary"

        # The summary has to carry the barrier, not just the residual.
        text = read(joinpath(output, "summary_c.csv"), String)
        @assert occursin("-4.0", text) "the most negative tag value is missing"
        @assert occursin("0.75", text) "the non-positive fraction is missing"
        @info "   both summaries and five PNGs written; the C summary carries \
               the negative tag and the non-positive fraction"
    end
end

"""
    test_configs()

Run `analysis/validate_configs.py` over the committed configurations, and its
mutation harness over copies of them.

It is Python because that is the tool that was actually run while the
configurations were written; porting it to Julia would mean shipping an
unverified rewrite, since the container it was written in has no Julia. It needs
only PyYAML, and neither the interpreter nor that package is guaranteed on every
machine, so a missing one is reported and skipped rather than failing the
self-test. What is *not* optional is the result when it does run.
"""
function test_configs()
    @info "9. the configuration validator, and its mutation harness"
    script = joinpath(HERE, "validate_configs.py")
    isfile(script) || error("validate_configs.py is missing from $HERE")
    python = Sys.which("python3")
    if isnothing(python)
        @warn "   no python3 on PATH, so the configurations were not checked. \
               Run analysis/validate_configs.py wherever one is available."
        return nothing
    end
    for args in ([script], [script, "--mutations"])
        process = run(ignorestatus(`$python $args`))
        if process.exitcode == 2
            @warn "   validate_configs.py could not start, most likely no \
                   PyYAML. Skipped." args
            return nothing
        end
        process.exitcode == 0 || error(
            "validate_configs.py failed ($(join(args, " "))). A configuration \
            is wrong, or a check that used to catch its mutation has stopped \
            working.",
        )
    end
    @info "   configurations valid and every mutation still caught"
    return nothing
end

function run_selftest()
    @info "Tag-closure analysis self-test. This is the first execution of \
           these scripts: they were written where no Julia was available."
    test_reducer()
    test_sphere_is_flagged()
    test_phase_a()
    test_slope()
    test_energy_reducer()
    test_source_reducer()
    test_process_record()
    test_configs()
    test_phase_b_and_c()
    @info "All assertions passed."
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_selftest()
end
