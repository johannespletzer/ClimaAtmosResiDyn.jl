#=
Which of the fork's mirrors have a parent that changed. A mirror is fork code
that repeats an upstream call or a dependency's arithmetic, so it must follow
the parent when the parent changes. `mirrors.toml`, next to this script's
directory, lists them.

    julia +1.11 mirror_check.jl <checkout> <old_ref> <new_ref> [old_env new_env] [--diffs <dir>]

- An upstream parent is read at `old_ref` and `new_ref` through git, such as
  the merge base and `upstream/main`.
- A package parent is read from the depot at the versions `old_env` and
  `new_env` resolve (environments from `make_ci_env.jl`). Without them,
  package mirrors are skipped.
- `--diffs <dir>` writes a unified diff of each changed parent there.

Each parent function is compared as parsed code with line numbers removed, so
a change to comments or formatting alone does not count. Every method with the
name is compared, also inside `if`, `@static if` and `let` blocks. The fork's
functions are looked up in the checkout's working tree.

A mirror whose comparison could not be made is `ERROR`: a parent function
found in neither version, a parent file or package that is missing, or a
registered fork function the fork file lacks. Fix the registry for those. A
changed parent means: read its diff, and port the change to the mirror, with a
test that fails without the port.

Exit status: 0 when every parent is unchanged, 1 when one changed, 2 when any
mirror is `ERROR` or was skipped for want of environments (which counts
first).
=#
include(joinpath(@__DIR__, "..", "..", "_lib", "common.jl"))

args = copy(ARGS)
diffs_dir = nothing
i = findfirst(==("--diffs"), args)
if i !== nothing
    diffs_dir = args[i + 1]
    deleteat!(args, i:(i + 1))
    mkpath(diffs_dir)
end
length(args) in (3, 5) ||
    error(
        "usage: mirror_check.jl <checkout> <old_ref> <new_ref> [old_env new_env] [--diffs <dir>]",
    )
checkout, old_ref, new_ref = args[1:3]
envs = length(args) == 5 ? (old = args[4], new = args[5]) : nothing
registry_file = get(ENV, "MIRRORS", joinpath(@__DIR__, "..", "mirrors.toml"))
mirrors = TOML.parsefile(registry_file)["mirror"]

definitions(text, file) =
    collect_defs!(Dict{String, Vector{Expr}}(), Meta.parseall(text; filename = file))
bodies(defs, names) =
    Dict(n => [strip_lines(d) for d in get(defs, n, Expr[])] for n in names)
render(found) = join(
    (
        "# $n\n" * join((sprint(print, d) for d in found[n]), "\n\n") for
        n in sort(collect(keys(found)))
    ),
    "\n\n",
)
git_text(ref, path) = get(git_blobs(checkout, ref, [path]), path, nothing)
file_text(dir, path) =
    dir === nothing || !isfile(joinpath(dir, path)) ? nothing :
    read(joinpath(dir, path), String)

println(
    "registry $registry_file: $(length(mirrors)) mirrors; upstream $old_ref -> $new_ref",
)
changed = 0
errors = 0
skipped = 0
for m in mirrors
    name = m["name"]
    errs = String[]
    notes = String[]
    # The fork's side, in the working tree.
    fork_path = joinpath(checkout, m["fork_file"])
    if isfile(fork_path)
        fork_defs = definitions(read(fork_path, String), fork_path)
        missing_fork = filter(f -> !haskey(fork_defs, f), m["fork_functions"])
        isempty(missing_fork) || push!(errs, "fork file lacks $(join(missing_fork, ", "))")
    else
        push!(errs, "fork file $(m["fork_file"]) missing")
    end

    parent = m["parent"]
    if parent == "upstream"
        old_text, new_text =
            git_text(old_ref, m["parent_file"]), git_text(new_ref, m["parent_file"])
        where_ = "upstream $(m["parent_file"])"
    elseif envs === nothing
        println("\n- $name: SKIPPED, $parent needs old_env and new_env")
        global skipped += 1
        continue
    else
        (old_dir, old_v), (new_dir, new_v) =
            package_dir(envs.old, parent), package_dir(envs.new, parent)
        old_dir === nothing && push!(errs, "old $parent: $old_v")
        new_dir === nothing && push!(errs, "new $parent: $new_v")
        old_text, new_text =
            file_text(old_dir, m["parent_file"]), file_text(new_dir, m["parent_file"])
        where_ = "$parent $old_v -> $new_v, $(m["parent_file"])"
    end
    old_text === nothing && push!(errs, "old parent file missing")
    new_text === nothing && push!(errs, "new parent file missing")
    names = m["parent_functions"]
    old_found =
        old_text === nothing ? Dict(n => Expr[] for n in names) :
        bodies(definitions(old_text, "old"), names)
    new_found =
        new_text === nothing ? Dict(n => Expr[] for n in names) :
        bodies(definitions(new_text, "new"), names)

    differing = String[]
    for n in names
        o, w = old_found[n], new_found[n]
        if isempty(o) && isempty(w)
            old_text === nothing || new_text === nothing ||
                push!(errs, "$n in neither version")
        elseif isempty(w)
            push!(differing, n);
            push!(notes, "$n REMOVED")
        elseif isempty(o)
            push!(differing, n);
            push!(notes, "$n added")
        elseif o != w
            push!(differing, n)
        end
    end
    status =
        !isempty(errs) ? "ERROR: $(join(errs, "; "))" :
        isempty(differing) ? "unchanged" : "PARENT CHANGED: $(join(differing, ", "))"
    isempty(errs) || (global errors += 1)
    isempty(differing) || (global changed += 1)
    println("\n- $name: $status")
    println("    fork: $(m["fork_file"]) ($(join(m["fork_functions"], ", ")))")
    println("    parent: $where_")
    isempty(notes) || println("    notes: ", join(notes, "; "))
    if !isempty(differing) && diffs_dir !== nothing
        a, b = tempname(), tempname()
        write(a, render(Dict(n => old_found[n] for n in differing)) * "\n")
        write(b, render(Dict(n => new_found[n] for n in differing)) * "\n")
        out = joinpath(diffs_dir, "$name.diff")
        diff = read(ignorestatus(`diff -u --label old --label new $a $b`), String)
        write(out, diff)
        lines = count(l -> startswith(l, r"[+-][^+-]"), split(diff, '\n'))
        println("    diff: $out ($lines lines changed)")
        rm(a);
        rm(b)
    end
end
println(
    "\n$changed of $(length(mirrors)) mirrors have a changed parent, $errors could not be compared, $skipped skipped (no environments)",
)
exit(errors + skipped > 0 ? 2 : changed > 0 ? 1 : 0)
