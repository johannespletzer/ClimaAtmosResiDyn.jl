#=
The table of a mutation run: which test file caught each mutant, and the
first failing test.

    julia +1.11 mutation_table.jl <out_dir>

A file catches a mutant when one of its tests fails an assertion. A mutant
that only makes a test throw (a `MethodError`, say) is "errored, not
asserted": the code breaks, but no test checks the value it guards, so it is
listed as a problem, not as caught.
A mutant whose ClimaAtmos does not precompile, or a file that exits non-zero
with no test result, is reported as "build failed" or "load error": it shows
that the change breaks the code, not that a test sees it. The control must
pass every file, or the run says nothing. The table is Markdown for the PR.
=#
length(ARGS) == 1 || error("usage: mutation_table.jl <out_dir>")
out_dir = abspath(ARGS[1])
rows = [split(l, '\t') for l in eachline(joinpath(out_dir, "mutants.tsv")) if !isempty(l)]
commit = readchomp(joinpath(out_dir, "COMMIT"))

# test_job.sh's summary: one line per run, `<file> exit <s> <sec> s <GiB> GiB [<counts>]`.
function results(name)
    file = joinpath(out_dir, "results", "$name.out")
    isfile(file) || return nothing
    lines = readlines(file)
    i = findlast(l -> startswith(l, "summary, job"), lines)
    i === nothing && return nothing
    out = Dict{String, NamedTuple}()
    for l in lines[(i + 1):end]
        m = match(
            r"^(\S+)\s+exit (\d+)\s+(\d+) s\s+([\d.]+) GiB(?:.*?(\d+) pass, (\d+) fail, (\d+) error)?",
            l,
        )
        m === nothing && continue
        out[m[1]] = (
            exit = parse(Int, m[2]),
            counts = m[5] === nothing ? nothing :
                     (
                pass = parse(Int, m[5]),
                fail = parse(Int, m[6]),
                error = parse(Int, m[7]),
            ),
        )
    end
    return out
end

# The first `Test Failed at` or `Error During Test at` in a file's log, as
# `test/<file>:<line>`.
function first_failure(name, file)
    logs = joinpath(out_dir, "$name-run", "logs")
    isdir(logs) || return ""
    stem = "$name-" * replace(replace(file, "/" => "_"), r"\.jl$" => "") * "-"
    for log in filter(f -> startswith(f, stem) && endswith(f, ".log"), readdir(logs))
        for l in eachline(joinpath(logs, log))
            m = match(r"(?:Test Failed|Error During Test) at .*/test/(\S+?):(\d+)", l)
            m === nothing || return "`$(m[1]):$(m[2])`"
        end
    end
    return ""
end

function verdict(r, name, file)
    r === nothing && return "not run"
    haskey(r, "precompile") && r["precompile"].exit != 0 && return "build failed"
    haskey(r, file) || return "not run"
    x = r[file]
    x.exit == 0 && return "passes"
    x.counts === nothing && return "load error"
    x.counts.fail + x.counts.error > 0 || return "exit $(x.exit)"
    name == "control" && return "FAILS, $(x.counts.fail) fail $(x.counts.error) error"
    where_ = first_failure(name, file)
    at = isempty(where_) ? "" : ", first at $where_"
    x.counts.fail == 0 && return "errored, not asserted, $(x.counts.error) error$at"
    return "**caught**, $(x.counts.fail) fail $(x.counts.error) error$at"
end

files = unique(vcat((split(r[4]) for r in rows)...))
println("Mutation run at `$(commit[1:9])`, $(length(rows) - 1) mutants and the control.\n")
println("| mutant | change | ", join(("`$f`" for f in files), " | "), " |")
println("|---|---|", repeat("---|", length(files)))
problems = String[]
for r in rows
    name, _, _, fs, expect, why = r[1], r[2], r[3], split(r[4]), split(r[5]), r[6]
    res = results(name)
    cells = [f in fs ? verdict(res, name, f) : "" for f in files]
    println("| `$name` | $(name == "control" ? "none" : why) | ", join(cells, " | "), " |")
    if name == "control"
        all(c -> c in ("passes", ""), cells) ||
            push!(
                problems,
                "The control does not pass every file, so the run shows nothing.",
            )
    else
        caught = [f for (f, c) in zip(files, cells) if startswith(c, "**caught**")]
        isempty(caught) && push!(problems, "`$name` is not caught by any file.")
        missed = setdiff(expect, caught)
        isempty(missed) || push!(
            problems,
            "`$name` is not caught by $(join(("`$f`" for f in missed), ", ")), which the spec expects to.",
        )
        any(c -> c in ("build failed", "load error"), cells) &&
            push!(
                problems,
                "`$name` breaks the build or the load, which shows nothing about the tests.",
            )
        any(c -> startswith(c, "errored"), cells) && isempty(caught) &&
            push!(
                problems,
                "`$name` only makes a test throw. No assertion checks it, so it is not caught.",
            )
    end
end
println()
isempty(problems) ?
println("Every mutant is caught by the files expected, and the control passes.") :
foreach(p -> println("- ", p), problems)
