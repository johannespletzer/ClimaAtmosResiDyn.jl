#=
Make one worktree and one environment per mutant of a checkout, and an
unmutated control, for `mutation_job.sh`.

    julia +1.11 make_mutants.jl <spec.toml> <checkout> <base_env> <out_dir>

`spec.toml` lists the test files and the mutants:

    files = ["tagged_water_precipitation_tests.jl"]   # relative to test/

    [[mutant]]
    name = "cold_accretion_into_rain"      # a file name, no spaces
    file = "src/parameterized_tendencies/tagged_tracers/tagged_water_precipitation.jl"
    old = "Δ.S_accr_lcl_sno_cold + "       # must occur exactly once in `file`
    new = ""
    why = "cold accretion of cloud liquid by snow left out of NS"
    expect = ["tagged_water_precipitation_tests.jl"]   # the files that should catch it

A mutant may also set `occurrence = k` to change the k-th match of `old`, and
`files` to run other test files than the spec's. Each mutant is one textual
change, so a reviewer can read it in the table.

Each worktree is a detached checkout of the checkout's HEAD under
`<out_dir>/<name>`, with the change applied and not committed. Uncommitted
changes in the checkout are not carried over, so commit first. Each
environment is `<base_env>` copied to `<out_dir>/envs/<name>`, with the path of
ClimaAtmos in the manifest set to the worktree, so nothing is resolved again
and every mutant runs the base environment's versions. The control is the
same without a change.

It writes `<out_dir>/mutants.tsv` for the job, and `<out_dir>/cleanup.sh`,
which removes the worktrees. Run that only once the table is in the PR.
=#
import TOML

length(ARGS) == 4 ||
    error("usage: make_mutants.jl <spec.toml> <checkout> <base_env> <out_dir>")
spec_file, checkout, base_env, out_dir = abspath.(ARGS)
spec = TOML.parsefile(spec_file)
default_files = get(spec, "files", String[])
mutants = get(spec, "mutant", Dict{String, Any}[])
isempty(mutants) && error("$spec_file has no [[mutant]]")
names = [m["name"] for m in mutants]
allunique(names) || error("mutant names repeat")
any(n -> n == "control" || occursin(r"[^\w.-]", n), names) &&
    error(
        "a mutant name is `control` or has characters other than letters, digits, `_`, `.`, `-`",
    )
isfile(joinpath(base_env, "Manifest.toml")) || error("$base_env has no Manifest.toml")

commit = readchomp(`git -C $checkout rev-parse HEAD`)
isempty(readchomp(`git -C $checkout status --porcelain --untracked-files=no`)) ||
    @warn "$checkout has uncommitted changes. The mutants start from HEAD $commit without them."
mkpath(joinpath(out_dir, "envs"))

# Whether parsed code holds a syntax error. `Meta.parseall` returns one as an
# `:error` or `:incomplete` node instead of throwing.
bad(ex) = ex isa Expr && (ex.head in (:error, :incomplete) || any(bad, ex.args))

function make_env(name, worktree)
    env = joinpath(out_dir, "envs", name)
    ispath(env) && error("$env exists. Pick another out_dir or remove it.")
    mkpath(env)
    cp(joinpath(base_env, "Project.toml"), joinpath(env, "Project.toml"))
    manifest = TOML.parsefile(joinpath(base_env, "Manifest.toml"))
    entry = only(manifest["deps"]["ClimaAtmos"])
    haskey(entry, "path") || error("ClimaAtmos is not developed by path in $base_env")
    entry["path"] = worktree
    open(io -> TOML.print(io, manifest; sorted = true), joinpath(env, "Manifest.toml"), "w")
    for f in ("LocalPreferences.toml",)
        isfile(joinpath(base_env, f)) && cp(joinpath(base_env, f), joinpath(env, f))
    end
    write(
        joinpath(env, "PROVENANCE"),
        "base_env $base_env\ncheckout $worktree\ncommit $commit\nmutant $name\n",
    )
    return env
end

rows = String[]
cleanup =
    ["#!/usr/bin/env bash", "# Removes the mutants' worktrees and environments.", "set -u"]
for m in vcat([Dict{String, Any}("name" => "control")], mutants)
    name = m["name"]
    worktree = joinpath(out_dir, name)
    ispath(worktree) && error("$worktree exists. Pick another out_dir or remove it.")
    run(
        pipeline(
            `git -C $checkout worktree add --detach $worktree $commit`;
            stdout = devnull,
            stderr = devnull,
        ),
    )
    push!(cleanup, "git -C $checkout worktree remove --force $worktree")
    if name != "control"
        path = joinpath(worktree, m["file"])
        text = read(path, String)
        hits = findall(m["old"], text)
        k = get(m, "occurrence", 0)
        if k == 0
            length(hits) == 1 || error(
                "$name: `old` occurs $(length(hits)) times in $(m["file"]); set `occurrence`",
            )
            k = 1
        end
        k <= length(hits) || error("$name: `old` occurs $(length(hits)) times, not $k")
        r = hits[k]
        mutated =
            text[1:prevind(text, first(r))] * m["new"] * text[nextind(text, last(r)):end]
        mutated == text && error("$name: the change changes nothing")
        bad(Meta.parseall(mutated; filename = path)) &&
            error("$name: the mutated $(m["file"]) does not parse")
        write(path, mutated)
    end
    env = make_env(name, worktree)
    files = get(m, "files", default_files)
    isempty(files) && error("$name: no test files; set `files` in the spec")
    for f in files
        isfile(joinpath(worktree, "test", f)) || error("$name: test/$f does not exist")
    end
    expect = get(m, "expect", String[])
    why = replace(get(m, "why", ""), r"[\t\n]" => " ")
    push!(rows, join((name, worktree, env, join(files, " "), join(expect, " "), why), '\t'))
    println(
        rpad(name, 32),
        name == "control" ? "unchanged" :
        "$(m["file"]): $(length(m["old"])) chars -> $(length(m["new"]))",
    )
end
push!(cleanup, "rm -rf $(joinpath(out_dir, "envs")) $(joinpath(out_dir, "depots"))")
write(joinpath(out_dir, "mutants.tsv"), join(rows, '\n') * "\n")
write(joinpath(out_dir, "cleanup.sh"), join(cleanup, '\n') * "\n")
write(joinpath(out_dir, "COMMIT"), commit * "\n")
println(
    "\n$(length(rows)) rows (the control first) in $(joinpath(out_dir, "mutants.tsv")), commit $(commit[1:9])",
)
println("submit with --array=0-$(length(rows) - 1)")
