#=
The fork's calls into a dependency's internal names, the ones starting with an
underscore, and whether each still exists in the dependency's new version.

    julia +1.11 dep_internals.jl <checkout> <tree_ref> <upstream_ref> <new_env> [old_env]

- `tree_ref` is the tree to scan: `origin/main` before a merge, `HEAD` after
  it. `src/`, `ext/` and `test/` are read, through git.
- `upstream_ref` sorts the uses: a line found verbatim in upstream's copy of
  the same file is upstream's. Before the merge, pass the merge base, so the
  merge's fix of upstream's own lines is not counted as the fork's work.
  After it, pass `upstream/main`.
- `new_env` and `old_env` are environments built by `make_ci_env.jl`.

Each package's source is parsed at the version an environment resolves,
following its `include`s into modules, so a name in a comment or a docstring
does not count as defined. A use `BMT.TDI._f` is looked up in the module the
alias and the path name (`CloudMicrophysics.BulkMicrophysicsTendencies.TDI`,
through its own alias if the module imports one). Verdicts:

- `ok`: the new version defines it there.
- `REMOVED`: the new version defines it nowhere, and the old one did (or no
  old environment is given).
- `MOVED`: not in that module any more, but in another of the package's.
- `UNKNOWN`: not found, but the module defines names with `@eval`, which
  parsing cannot read. Check it by hand.

A use inside backticks or after `#` is a docstring's or a comment's, and is
listed apart. Exit status 1 when the fork's code has a use that is not ok.
=#
include(joinpath(@__DIR__, "..", "..", "_lib", "common.jl"))

length(ARGS) in 4:5 ||
    error(
        "usage: dep_internals.jl <checkout> <tree_ref> <upstream_ref> <new_env> [old_env]",
    )
checkout, tree_ref, upstream_ref, new_env = ARGS[1:4]
old_env = length(ARGS) == 5 ? ARGS[5] : nothing

dirs = ["src", "ext", "test"]
tree = git_blobs(
    checkout,
    tree_ref,
    filter(p -> endswith(p, ".jl"), git_paths(checkout, tree_ref, dirs)),
)
upstream = git_blobs(checkout, upstream_ref, collect(keys(tree)))

# Module aliases, per file: `import A.B as X`, `using A.B: B as X`, `import A: B`
# (binds `B` to `A.B`), `const X = A.B`, and a plain `import A` or `using A`.
function file_aliases(text)
    aliases = Dict{String, String}()
    for line in eachline(IOBuffer(text))
        for m in eachmatch(r"\b(?:import|using)\s+([A-Z][\w.]*)\s+as\s+(\w+)", line)
            aliases[m[2]] = m[1]
        end
        m = match(r"\b(?:import|using)\s+([A-Z][\w.]*)\s*:\s*(.+)$", line)
        if m !== nothing
            for item in split(m[2], ',')
                parts = split(strip(item))
                isempty(parts) && continue
                name = parts[1]
                occursin(r"^[A-Z]\w*$", name) || continue
                alias = length(parts) == 3 && parts[2] == "as" ? parts[3] : name
                aliases[alias] = "$(m[1]).$name"
            end
        end
        m = match(r"^\s*const\s+(\w+)\s*=\s*([A-Z]\w*(?:\.[A-Z]\w*)+)\s*$", line)
        m === nothing || (aliases[m[1]] = m[2])
        for m in eachmatch(r"\b(?:import|using)\s+([A-Z]\w*)\s*(?:$|,)", line)
            aliases[m[1]] = m[1]
        end
    end
    return aliases
end
per_file = Dict(p => file_aliases(t) for (p, t) in tree)
# One module's files share its aliases (ClimaAtmos is one module), so a name
# the file does not import falls back to any file's alias.
global_aliases = merge(values(per_file)...)

own = get(TOML.parsefile(joinpath(checkout, "Project.toml")), "name", "")

struct Use
    path::String
    line::Int
    alias::String
    module_path::Vector{String}
    name::String
    text::Bool
    upstreams::Bool
end
uses = Use[]
for (path, text) in tree
    upstream_lines = Set(eachline(IOBuffer(get(upstream, path, ""))))
    aliases = merge(global_aliases, per_file[path])
    for (i, line) in enumerate(eachline(IOBuffer(text)))
        for m in eachmatch(r"\b([A-Za-z]\w*)((?:\.[A-Za-z]\w*)*)\.(_\w+!?)", line)
            haskey(aliases, m[1]) || continue
            modpath = vcat(split(aliases[m[1]], '.'), filter(!isempty, split(m[2], '.')))
            String(modpath[1]) == own && continue
            before = line[1:(m.offset - 1)]
            in_text = isodd(count(==('`'), before)) || occursin('#', before)
            push!(
                uses,
                Use(path, i, m[1], String.(modpath), m[3], in_text, line in upstream_lines),
            )
        end
    end
end

# Each package's definitions, at the old and the new version.
packages = unique(u.module_path[1] for u in uses)
envs = old_env === nothing ? (("new", new_env),) : (("old", old_env), ("new", new_env))
info = Dict{Tuple{String, String}, Any}()
println("tree $tree_ref, upstream $upstream_ref; packages:")
for pkg in sort(packages), (label, env) in envs
    dir, version = package_dir(env, pkg)
    info[(label, pkg)] = dir === nothing ? nothing : package_definitions(dir, pkg)
    println("  $label $pkg: $version")
end

# A module path through a package's own aliases: `BMT.TDI` where the module
# `BulkMicrophysicsTendencies` has `import ...ThermodynamicsInterface as TDI`
# is not a submodule of it. Fall back to any module with that last name.
function lookup(defs, modpath)
    haskey(defs, modpath) && return defs[modpath]
    candidates = [k for k in keys(defs) if !isempty(k) && last(k) == last(modpath)]
    length(candidates) == 1 && return defs[only(candidates)]
    return nothing
end
function verdict(u)
    pkg = u.module_path[1]
    new = info[("new", pkg)]
    new === nothing && return "UNKNOWN (no source)"
    defs, dynamic, _ = new
    here = lookup(defs, u.module_path)
    here !== nothing && u.name in here && return "ok"
    anywhere = any(s -> u.name in s, values(defs))
    old = old_env === nothing ? nothing : info[("old", pkg)]
    old_had = old === nothing ? true : any(s -> u.name in s, values(old[1]))
    anywhere && return "MOVED"
    any(
        m -> length(m) <= length(u.module_path) && u.module_path[1:length(m)] == m,
        dynamic,
    ) &&
        return "UNKNOWN (@eval)"
    return old_had ? "REMOVED" : "absent in both"
end
verdicts = Dict(u => verdict(u) for u in uses)

bad = 0
for (title, select) in (
    ("The fork's code", u -> !u.text && !u.upstreams),
    ("Upstream's code (the merge brings its fix)", u -> !u.text && u.upstreams),
    ("Docstrings and comments", u -> u.text),
)
    chosen = sort(filter(select, uses); by = u -> (verdicts[u] == "ok", u.path, u.line))
    n_bad = count(u -> verdicts[u] != "ok", chosen)
    title == "The fork's code" && (global bad = n_bad)
    println("\n## $title: $(length(chosen)) uses, $n_bad not ok")
    for u in chosen
        v = verdicts[u]
        v == "ok" && title != "The fork's code" && continue
        println(
            rpad(v, 20),
            "$(u.path):$(u.line)  $(u.alias).$(u.name)  ($(join(u.module_path, '.')))",
        )
    end
end
exit(bad == 0 ? 0 : 1)
