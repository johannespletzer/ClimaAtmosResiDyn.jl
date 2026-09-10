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
    UNSET_KEYS

The tag and record keys a run leaves unset, written as `~`.

Every synthetic snapshot carries these, because a real merged snapshot does: the
run writes back all 175 keys of `default_config.yml`, unset ones included. A
fixture that omitted them made `get(config, key, default)` return the default,
while the real thing returns `nothing` and reaches `isempty(nothing)`. That is
what the first real run died of, and no fixture here could see it.
"""
const UNSET_KEYS = (
    "water_tracers",
    "energy_tracers",
    "energy_source_tags",
    "energy_process_record",
    "water_process_record",
    "water_closure_check",
    "energy_closure_check",
    "energy_source_closure_check",
)

"""
    unset_lines(set_keys)

`key: ~` for every key of [`UNSET_KEYS`](@ref) not in `set_keys`.
"""
unset_lines(set_keys) = join(
    ["$key: ~" for key in UNSET_KEYS if !(key in set_keys)],
    "\n",
)

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
        $(unset_lines(("water_tracers",)))
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
    summary_row(path, run)

One row of a phase summary as a `name => value` `Dict` of strings.

Reading a summary back by field rather than testing the file for a substring.
`occursin` passes on a row whose every number is `NaN`, which is what a fault
between the reducer and the loader actually produces, so it cannot tell a
working column from a silently empty one.
"""
function summary_row(path, run)
    lines = readlines(path)
    header = split(first(lines), ',')
    for line in lines[2:end]
        fields = split(line, ',')
        first(fields) == run || continue
        return Dict(String(k) => String(v) for (k, v) in zip(header, fields))
    end
    error("no row for $run in $path")
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

"""
    write_synthetic_audit(dir, family, rows)

A synthetic `<family>_tag_audit.csv` in the shape the model writes when a
closure block sets `audit: true`, so the loader is read against the real column
set rather than against one invented here.

`rows` is a vector of `(time, overclaimed_relative, orphaned_relative,
nonpositive_mass_fraction)`. The remaining columns are filled consistently:
`untagged + overclaimed` is `gross_residual` by construction in the model, so
the fixture keeps that true rather than writing numbers that could not occur
together.
"""
function write_synthetic_audit(dir, family, rows)
    path = joinpath(dir, family * "_tag_audit.csv")
    open(path, "w") do io
        println(
            io,
            "time,untagged,untagged_relative,overclaimed," *
            "overclaimed_relative,orphaned,orphaned_relative," *
            "orphaned_volume_fraction,nonpositive_mass," *
            "nonpositive_mass_fraction",
        )
        for (t, over, orphan, npmass) in rows
            # scale = 1 in every fixture closure table, so the absolute and the
            # relative columns carry the same number here.
            println(
                io,
                "$t,0.0,0.0,$over,$over,$orphan,$orphan,$orphan,$npmass,$npmass",
            )
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
            # The A3 companion. It matches `a1_dt10` in every key the ladder
            # filter screens on -- column, Float64, 0M, van Leer, dt 10 -- and
            # differs only in `vert_diff`. So it is the one run that lands on
            # top of a rung if that key is not screened, and the assertion
            # below is what keeps the screen honest.
            ("a3_0m_vert_diff", 10.0, "vanleer_limiter", 1.5e-3),
            ("a4_float32", 10.0, "vanleer_limiter", 2.0e-3),
        )
            dir = joinpath(output, run)
            mkpath(dir)
            micro = run == "a3_1m" ? "1M" : "0M"
            float_type = run == "a4_float32" ? "Float32" : "Float64"
            vert_diff = run == "a3_0m_vert_diff" ? "DecayWithHeightDiffusion" : "~"
            write(
                joinpath(dir, run * ".yml"),
                """
                job_id: $run
                config: column
                dt: $(dt)secs
                FLOAT_TYPE: $float_type
                microphysics_model: $micro
                tracer_upwinding: $upwinding
                vert_diff: $vert_diff
                """,
            )
            write(
                joinpath(dir, "provenance.txt"),
                "run: $run\ncommit: 0123456789abcdef\nfinished: 2026-09-09T12:00:00\n",
            )
            write_synthetic_closure(dir, run, dt, [tail / 2, tail])
            write_synthetic_operator(dir, [tail / 2, tail])
        end
        # One run carries an audit table and the others do not, which is the
        # real shape: `audit: true` is off by default and set on one phase-A
        # run. It goes on `a1_dt10` here rather than on `a5_sphere_limiter`
        # because a5's slot in this fixture is the run refused for having no
        # provenance, so it never reaches the summary at all.
        write_synthetic_audit(
            joinpath(output, "a1_dt10"), "water",
            [(0.0, 1.0e-5, 2.0e-6, 0.0), (10.0, 3.0e-5, 7.0e-6, 0.0)],
        )
        # Two ways a run must be refused, which are the same defect: no
        # provenance at all, and a provenance that cannot name the commit. The
        # first real run produced the second kind, because `module purge` took
        # git off the compute node's PATH, so it is not hypothetical.
        orphan = joinpath(output, "a5_sphere_limiter")
        mkpath(orphan)
        write_synthetic_closure(orphan, "a5_sphere_limiter", 300.0, [1.0e-2, 2.0e-2])

        # A run whose earlier reading has been archived into a subdirectory of
        # its own, which is what an emptied run directory looks like between a
        # model change and the re-run. It must be skipped in silence, and the
        # archived files inside it must not be read as though they were the
        # run: they are a measurement of a different model.
        archived = joinpath(output, "a2_first_order_dt10")
        keep = joinpath(archived, "before_issue_64_fix")
        mkpath(keep)
        write(
            joinpath(keep, "provenance.txt"),
            "run: a2_first_order_dt10\ncommit: 0123456789abcdef\n",
        )
        write(
            joinpath(keep, "a2_first_order_dt10.yml"),
            """
            job_id: a2_first_order_dt10
            config: column
            dt: 10secs
            FLOAT_TYPE: Float64
            microphysics_model: 0M
            tracer_upwinding: first_order
            """,
        )
        write_synthetic_closure(keep, "a2_first_order_dt10", 10.0, [1.0e-6, 2.0e-6])

        nameless = joinpath(output, "a2_none_dt10")
        mkpath(nameless)
        write(
            joinpath(nameless, "provenance.txt"),
            "run: a2_none_dt10\ncommit: unknown\ncommit_dirty: unknown\n",
        )
        write(
            joinpath(nameless, "a2_none_dt10.yml"),
            """
            job_id: a2_none_dt10
            config: column
            dt: 10secs
            FLOAT_TYPE: Float64
            microphysics_model: 0M
            tracer_upwinding: none
            $(unset_lines(()))
            """,
        )
        write_synthetic_closure(nameless, "a2_none_dt10", 10.0, [1.0e-4, 2.0e-4])
        write_synthetic_operator(nameless, [1.0e-4, 2.0e-4])

        phase = load_script(joinpath(HERE, "phase_a.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase, :main)
        end

        summary = joinpath(output, "summary_a.csv")
        @assert isfile(summary) "no summary_a.csv"
        text = read(summary, String)
        @assert occursin("a1_dt10", text) && occursin("a2_none_dt2p5", text)
        @assert(
            !occursin("a5_sphere_limiter", text),
            "a run with no provenance was analysed",
        )
        # ... and the one whose provenance cannot name the commit, which is the
        # same rule and a different symptom. It has a closure table and a
        # reduced table, so only the commit check can keep it out.
        @assert(
            !occursin("a2_none_dt10", text),
            "a run recording `commit: unknown` was analysed",
        )
        # ... and the emptied directory, whose archived reading is a
        # measurement of a different model and must not be read as this run's.
        @assert(
            !occursin("a2_first_order_dt10", text),
            "an archived reading was analysed as though it were the run",
        )

        # The audit columns, read back by field. `occursin` would pass on a row
        # of `NaN`, which is exactly what a loader that never opened the file
        # produces, and that is the fault this covers: a table written by the
        # model, listed in the hand-back, and read by nothing.
        audited = summary_row(summary, "a1_dt10")
        over = parse(Float64, audited["final_overclaimed_relative"])
        orphan = parse(Float64, audited["final_orphaned_relative"])
        @assert(over ≈ 3.0e-5, "final_overclaimed_relative $over, want 3.0e-5")
        @assert(orphan ≈ 7.0e-6, "final_orphaned_relative $orphan, want 7.0e-6")
        # ... and a run with no audit table must say so rather than borrowing
        # the neighbouring run's numbers.
        plain = summary_row(summary, "a1_dt5")
        @assert(
            isnan(parse(Float64, plain["final_overclaimed_relative"])),
            "a run with no audit table reported $(plain["final_overclaimed_relative"])",
        )

        # `vert_diff` has to reach the summary, because `a3_0m_vert_diff` and
        # `a1_dt10` agree in every other column there -- column, Float64, 0M,
        # van Leer, dt 10 -- and a summary that cannot tell them apart is the
        # two-key confusion the companion run exists to undo.
        companion = summary_row(summary, "a3_0m_vert_diff")
        @assert(
            companion["vert_diff"] == "DecayWithHeightDiffusion",
            "the companion reported vert_diff $(companion["vert_diff"])",
        )
        @assert(
            summary_row(summary, "a1_dt10")["vert_diff"] == "none",
            "an unset vert_diff did not resolve to \"none\"",
        )

        # And the ladder must exclude it. Asserted on the predicate rather than
        # on the PNG, because a plot carrying a spurious second point at dt 10
        # saves perfectly well and looks right until someone reads a slope off
        # it.
        loaded_runs = call(phase, :load_phase, tmp, "a")
        rungs = Set(
            run.name for run in loaded_runs
            if call(phase, :is_ladder_rung, run)
        )
        for outsider in ("a3_0m_vert_diff", "a3_1m", "a4_float32")
            @assert(
                !(outsider in rungs),
                "$outsider was drawn onto the dt ladder",
            )
        end
        @assert("a1_dt10" in rungs, "a1_dt10 was screened off its own ladder")

        plots = joinpath(tmp, "plots")
        for name in (
            "a_gross_relative_vs_time.png",
            "a_operator_residual_vs_dt.png",
            "a_variants_vs_time.png",
        )
            @assert isfile(joinpath(plots, name)) "missing plot $name"
        end
        @info "   summary and three PNGs written; the audit columns read back \
               as $over and $orphan; the ladder kept $(length(rungs)) rungs and \
               screened the three variants; and both the run with no provenance \
               and the one recording `commit: unknown` were refused"
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
        $(unset_lines(record ? (key, "energy_process_record") : (key,)))
        """,
    )
    write(
        joinpath(dir, "provenance.txt"),
        "run: $name\ncommit: 0123456789abcdef\nfinished: 2026-09-09T12:00:00\n",
    )

    times = [0.0, 3600.0]
    rows(a, b) = permutedims(hcat(a, b))
    residual = rows([1.0, -3.0, 0.0, 2.0], [0.0, 0.5, 0.0, 0.0])
    # `src` goes negative at the second time. That is the case e_src_res cannot
    # show, so the minimum has to. `extratropics` goes further negative at the
    # same time, the way a region tag does where the parent is non-positive. A
    # reading of the most negative tag of either kind then names it and hides
    # `src`, and the source-only column must not.
    tropics = rows([5.0, 6.0, 7.0, 8.0], [5.0, 6.0, 7.0, 8.0])
    extratropics = rows([1.0, 1.0, 1.0, 1.0], [2.0, 2.0, 2.0, -10.0])
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
        # max |e_src_res| falls, so the residual above cannot show it.
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
        # C0 is the run whose volume fraction the mass fraction is the
        # counterpart of, so the audit table goes on it here. In the real tree
        # it is `c0_sphere_deep` that carries the key; the shape read back is
        # the same.
        write_synthetic_audit(
            c_dir, "energy_source", [(0.0, 0.0, 0.0, 0.25), (3600.0, 0.0, 0.0, 0.9)],
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
        # it was drawn from rather than only that a file appeared. Reading the
        # summary back by field rather than with `occursin` is the point: a
        # substring test passes on a row that is all `NaN`, which is exactly
        # what a reducer-to-loader wiring fault produces.
        c3 = summary_row(joinpath(output, "summary_c.csv"), "c3_column_record")
        c0 = summary_row(joinpath(output, "summary_c.csv"), "c0_column")

        # `@assert(cond, msg)`, the call form, because it is the only way to
        # break these across lines. A trailing backslash is not a continuation
        # in Julia code; see `check_no_code_continuations` below.
        recorded = c3["recorded_processes"]
        @assert(recorded == "surface_flux", "C3 recorded $recorded")

        # The record's maximum over the field at the last time is 3.0, from the
        # synthetic e_prc_surface_flux above. A NaN here means the record was
        # reduced and never read back, which is the fault this covers.
        final_record = parse(Float64, c3["final_max_e_prc"])
        @assert(final_record ≈ 3.0, "C3 final_max_e_prc $final_record, want 3.0")

        # ... and C0, which carries no record, must not claim one.
        @assert(isempty(c0["recorded_processes"]), "C0 claims a record")

        # The barrier columns, per run rather than anywhere in the file.
        # The most negative tag of either kind is the region tag. The most
        # negative source-labelled tag is `src`, which that reading hides.
        worst = parse(Float64, c3["most_negative_tag_value"])
        which = c3["most_negative_tag"]
        @assert(worst ≈ -10.0, "most negative tag value $worst, want -10.0")
        @assert(which == "extratropics", "most negative tag $which")
        source_worst = parse(Float64, c3["most_negative_source_tag_value"])
        source_which = c3["most_negative_source_tag"]
        @assert(
            source_worst ≈ -4.0,
            "most negative source tag value $source_worst, want -4.0",
        )
        @assert(source_which == "src", "most negative source tag $source_which")
        fraction = parse(Float64, c3["max_nonpositive_fraction"])
        @assert(fraction ≈ 0.75, "non-positive fraction $fraction, want 0.75")

        # The mass counterpart of that volume fraction, from the audit table.
        # C0 has one and C3 does not, so this covers both the read and the
        # absence in the same phase.
        mass = parse(Float64, c0["final_nonpositive_mass_fraction"])
        @assert(mass ≈ 0.9, "final_nonpositive_mass_fraction $mass, want 0.9")
        @assert(
            isnan(parse(Float64, c3["final_nonpositive_mass_fraction"])),
            "C3 has no audit table but reported \
             $(c3["final_nonpositive_mass_fraction"])",
        )

        control = summary_row(joinpath(output, "summary_b.csv"), "b1_notags")
        @assert(control["family"] == "none", "control family $(control["family"])")

        @info "   summaries read back by field: C3 carries its record " *
              "($final_record), C0 carries none, the barrier columns hold " *
              "$worst and $fraction, and C0's audit puts $mass of the mass " *
              "in the non-positive region against $fraction of the volume"
    end
end

"""
    test_configs()

Run `analysis/validate_configs.py` over the committed configurations, and its
mutation harness over copies of them.

Three passes: the configurations, the mutation harness that proves those checks
are live, and a lint for backslash line continuations in Julia code. Julia has
no such continuation -- inside a string it joins lines, outside one it is the
left-division operator -- so `@assert cond \\` with its message on the next
line parses as `cond \\ message` and dies as
`MethodError: no method matching adjoint(::String)`, naming neither the file nor
the cause. This file shipped one and it cost two runs on Levante.

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
    for args in ([script], [script, "--mutations"], [script, "--lint-continuations"])
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
    @info "   configurations valid, every mutation still caught, and no \
           backslash continuation in code"
    return nothing
end

"""
    test_single_run_phases()
    test_where_negative()

Each phase with exactly one run committed, which is the state every phase is in
after its first job comes back.

Nothing else here covers it: every other fixture holds four to eight runs, so a
one-point ladder, a comparison panel with nothing to compare against, and a
reference run that is simply absent had all never been reached. A figure that
cannot honestly be drawn from one run must be skipped, not drawn empty and not
thrown over, and the summary must still be written.
"""
function test_single_run_phases()
    @info "10. one run per phase, the state after the first job comes back"

    # Phase A: the water ladder with a single rung.
    mktempdir() do tmp
        run_dir = write_synthetic_run(joinpath(tmp, "output", "a1_dt10"))
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_run, run_dir)
        call(reducer, :write_operator_residual, run_dir, header, rows, metadata)
        write_synthetic_closure(run_dir, "a1_dt10", 10.0, [1.0e-6, 2.8e-6])

        phase = load_script(joinpath(HERE, "phase_a.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase, :main)
        end
        plots = joinpath(tmp, "plots")
        summary = joinpath(tmp, "output", "summary_a.csv")
        @assert isfile(summary) "no summary_a.csv from a single run"
        @assert length(readlines(summary)) == 2 "expected a header and one row"
        @assert isfile(joinpath(plots, "a_gross_relative_vs_time.png"))
        # One rung is still a point worth drawing; the slope is not.
        @assert isfile(joinpath(plots, "a_operator_residual_vs_dt.png"))
        # A3 and A4 are absent, so the variants panel has nothing to draw and
        # must be skipped rather than drawn empty.
        @assert(
            !isfile(joinpath(plots, "a_variants_vs_time.png")),
            "the variants panel was drawn with no variant present",
        )
        @info "   phase A: summary and two panels, variants panel skipped"
    end

    # Phase B: one energy run.
    mktempdir() do tmp
        dir = write_energy_run(joinpath(tmp, "output", "b1_base"); family = "energy")
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_energy_tags, dir)
        call(
            reducer, :write_table, dir, "energy_tag_residual", header, rows,
            metadata, "synthetic",
        )
        phase_b = load_script(joinpath(HERE, "phase_b.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase_b, :main)
        end
        summary = joinpath(tmp, "output", "summary_b.csv")
        @assert isfile(summary) "no summary_b.csv from a single run"
        @assert length(readlines(summary)) == 2 "expected a header and one row"
        plots = joinpath(tmp, "plots")
        @assert isfile(joinpath(plots, "b_gross_relative_bars.png"))
        @assert isfile(joinpath(plots, "b_gross_relative_vs_time.png"))
        @info "   phase B: summary and both panels from one run"
    end

    # Phase C: one census run, which carries no process record.
    mktempdir() do tmp
        dir = write_energy_run(
            joinpath(tmp, "output", "c0_column");
            family = "energy_source", record = false,
        )
        reducer = load_script(joinpath(HERE, "reduce_run.jl"))
        header, rows, metadata = call(reducer, :reduce_source_tags, dir)
        call(
            reducer, :write_table, dir, "source_tag_extrema", header, rows,
            metadata, "synthetic",
        )
        phase_c = load_script(joinpath(HERE, "phase_c.jl"))
        withenv("TAG_CLOSURE_DIR" => tmp) do
            call(phase_c, :main)
        end
        summary = joinpath(tmp, "output", "summary_c.csv")
        @assert isfile(summary) "no summary_c.csv from a single run"
        @assert length(readlines(summary)) == 2 "expected a header and one row"
        plots = joinpath(tmp, "plots")
        for name in (
            "c_nonpositive_fraction.png", "c_min_tag_value.png", "c_e_src_res.png",
        )
            @assert isfile(joinpath(plots, name)) "missing $name from one run"
        end
        # No record here, so the two-readings panel has one of its two series
        # and must be skipped.
        @assert(
            !isfile(joinpath(plots, "c_two_readings.png")),
            "the two-readings panel was drawn with no record present",
        )
        # And the summary must say so rather than inventing a process.
        row = summary_row(summary, "c0_column")
        @assert isempty(row["recorded_processes"]) "C0 claims a record"
        @info "   phase C: summary and three panels, two-readings panel skipped"
    end
    return nothing
end

"""
    test_where_negative()

`where_negative.jl` on a synthetic four-level column whose answers are worked
out by hand.

The two region tags sum, level by level, to a specific `e_tot` of

    level 1 (z = 100):  [-30, -10,  -5, -1]   all negative
    level 2 (z = 200):  [-20,   5,  10, 20]   one quarter negative
    level 3 (z = 300):  [  1,   2,   3,  4]   none
    level 4 (z = 400):  [ 10,  20,  30, 40]   none

so the fractions are 1.0, 0.25, 0.0, 0.0; the field minimum is -30, hence the
smallest constant making it positive is +30; the negative levels are [1, 2],
which is contiguous; and the sign change is at the base of level 3, z = 300.
"""
function test_where_negative()
    @info "11. where_negative.jl on a synthetic column"
    mktempdir() do tmp
        dir = joinpath(tmp, "c0_column")
        mkpath(dir)
        write(
            joinpath(dir, "c0_column.yml"),
            """
            job_id: c0_column
            config: column
            dt: 10secs
            FLOAT_TYPE: Float64
            energy_source_tags:
              - name: strat
                region: {type: tanh_altitude, z_center: 750.0, width: 100.0}
              - name: tropo
                region: {type: tanh_altitude, z_center: 750.0, width: 100.0, above: false}
              - name: rad
                source: radiation
            $(unset_lines(("energy_source_tags",)))
            """,
        )
        write(
            joinpath(dir, "provenance.txt"),
            "run: c0_column\ncommit: 0123456789abcdef\nfinished: 2026-09-10T12:00:00\n",
        )

        z = [100.0, 200.0, 300.0, 400.0]
        # Split the intended total across two region tags; only the sum matters.
        strat = [
            -20.0 -6.0 -3.0 -0.5
            -12.0 3.0 6.0 12.0
            0.5 1.0 1.5 2.0
            6.0 12.0 18.0 24.0
        ]
        tropo = [
            -10.0 -4.0 -2.0 -0.5
            -8.0 2.0 4.0 8.0
            0.5 1.0 1.5 2.0
            4.0 8.0 12.0 16.0
        ]
        # Two times, so the script has to take the first and not the last.
        function with_time(level_data, factor)
            stacked = Array{Float64}(undef, 2, size(level_data)...)
            stacked[1, :, :] = level_data
            stacked[2, :, :] = level_data .* factor
            return stacked
        end
        NCDatasets.NCDataset(joinpath(dir, "diagnostics.nc"), "c") do ds
            NCDatasets.defDim(ds, "time", 2)
            NCDatasets.defDim(ds, "z", 4)
            NCDatasets.defVar(ds, "time", [0.0, 3600.0], ("time",))
            NCDatasets.defVar(ds, "z", z, ("z",))
            NCDatasets.defVar(
                ds, "e_src_strat", with_time(strat, 100.0), ("time", "z", "x"),
            )
            NCDatasets.defVar(
                ds, "e_src_tropo", with_time(tropo, 100.0), ("time", "z", "x"),
            )
        end

        script = load_script(joinpath(HERE, "where_negative.jl"))
        header, rows, summary = call(script, :where_negative, dir)

        index = Dict(name => i for (i, name) in enumerate(header))
        fractions = [row[index["fraction_negative"]] for row in rows]
        minima = [row[index["minimum"]] for row in rows]

        @assert fractions ≈ [1.0, 0.25, 0.0, 0.0] "fractions: $fractions"
        @assert minima ≈ [-30.0, -20.0, 1.0, 10.0] "minima: $minima"
        # The second time is a hundred times larger; taking it would give -3000.
        @assert summary.field_minimum ≈ -30.0 "field minimum $(summary.field_minimum)"
        @assert summary.smallest_shift ≈ 30.0 "shift $(summary.smallest_shift)"
        @assert summary.negative_levels == [1, 2] "levels $(summary.negative_levels)"
        @assert summary.contiguous "levels 1 and 2 are contiguous"
        @assert summary.sign_change_z ≈ 300.0 "sign change $(summary.sign_change_z)"
        field_fraction = summary.fraction_negative
        @assert field_fraction ≈ 5 / 16 "field fraction $field_fraction"
        @assert summary.remapped == false "a column must not be marked remapped"

        path = call(script, :write_where_negative, dir, header, rows, summary)
        @assert isfile(path)
        text = read(path, String)
        @assert occursin("smallest constant", text) "the shift is not in the header"
        @assert occursin("fraction_negative", text)
        @info "   fractions $fractions, smallest shift $(summary.smallest_shift), \
               sign change at $(summary.sign_change_z) m — as computed by hand"
    end

    # A field with nothing negative must say so rather than inventing a layer.
    mktempdir() do tmp
        dir = joinpath(tmp, "c0_positive")
        mkpath(dir)
        write(
            joinpath(dir, "c0_positive.yml"),
            """
            job_id: c0_positive
            config: sphere
            FLOAT_TYPE: Float64
            energy_source_tags:
              - name: tropics
                region: tropics
              - name: extratropics
                region: extratropics
            $(unset_lines(("energy_source_tags",)))
            """,
        )
        write(joinpath(dir, "provenance.txt"), "run: c0_positive\ncommit: abc123\n")
        NCDatasets.NCDataset(joinpath(dir, "diagnostics.nc"), "c") do ds
            NCDatasets.defDim(ds, "time", 1)
            NCDatasets.defDim(ds, "z", 2)
            NCDatasets.defVar(ds, "time", [0.0], ("time",))
            NCDatasets.defVar(ds, "z", [10.0, 20.0], ("z",))
            for name in ("e_src_tropics", "e_src_extratropics")
                NCDatasets.defVar(
                    ds, name, reshape([1.0 2.0; 3.0 4.0], 1, 2, 2),
                    ("time", "z", "x"),
                )
            end
        end
        script = load_script(joinpath(HERE, "where_negative.jl"))
        _, _, summary = call(script, :where_negative, dir)
        @assert(
            isempty(summary.negative_levels),
            "found a negative level in a positive field",
        )
        @assert summary.smallest_shift == 0.0 "a positive field needs no shift"
        @assert isnan(summary.sign_change_z) "there is no sign change to report"
        @assert summary.remapped "a sphere must be marked remapped"
        @info "   a wholly positive field reports no shift and no sign change"
    end
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
    test_single_run_phases()
    test_where_negative()
    @info "All assertions passed."
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_selftest()
end
