#=
List the packages whose versions differ between two resolved environments.

    julia +1.11 versions_diff.jl <a> <b> [--all]

Each of `a` and `b` is one of:

- a CI job's log, saved with `gh run view --job <id> --log`. The last
  `[uuid] Name vX.Y.Z` line of each package counts, as in `make_ci_env.jl`;
- a `Manifest.toml` or `Manifest-v1.11.toml`;
- an environment directory, such as one `make_ci_env.jl` built;
- `<ref>:<path>` of the current git repository, such as
  `upstream/main:.buildkite/Manifest-v1.11.toml`.

It prints one row per package both sides have at different versions. `--all`
also lists the packages only one side has. It needs no package and loads in a
second, so it runs on a login node.
=#
import TOML

function read_source(source)
    if isdir(source)
        path = joinpath(source, "Manifest.toml")
        return isfile(path) ? (read(path, String), "manifest") :
               error("$source has no Manifest.toml")
    elseif isfile(source)
        text = read(source, String)
        return (text, endswith(source, ".toml") ? "manifest" : "log")
    elseif occursin(':', source)
        return (read(`git show $source`, String), "manifest")
    end
    error("$source is not a file, a directory or a git <ref>:<path>")
end

function versions(source)
    text, kind = read_source(source)
    found = Dict{String, String}()
    if kind == "manifest"
        manifest = TOML.parse(text)
        # Format 2 nests the packages under `deps`; format 1 does not.
        deps = get(manifest, "deps", manifest)
        for (name, entries) in deps
            entries isa Vector || continue
            version = get(only(entries), "version", nothing)
            version === nothing || (found[name] = version)
        end
    else
        # `gh` writes the colour codes' escape byte as the two characters `^[`.
        text = replace(text, r"(\e|\^\[)\[[0-9;]*m" => "")
        for m in
            eachmatch(
            r"\[[0-9a-f]{8}\] [+~↑↓]? ?([A-Za-z0-9_]+) v([0-9][0-9A-Za-z.+-]*)",
            text,
        )
            found[m.captures[1]] = m.captures[2]
        end
        julia = match(r"julia version (\d+\.\d+\.\d+)"i, text)
        julia === nothing || println("$source: Julia $(julia[1])")
    end
    isempty(found) && error("no package versions found in $source")
    return found
end

length(ARGS) in 2:3 && (length(ARGS) == 2 || ARGS[3] == "--all") ||
    error("usage: versions_diff.jl <a> <b> [--all]")
a, b = versions(ARGS[1]), versions(ARGS[2])
differ = sort([name for name in keys(a) if haskey(b, name) && a[name] != b[name]])
width = maximum(length, differ; init = 7) + 2
println(rpad("package", width), rpad("a", 14), "b")
for name in differ
    println(rpad(name, width), rpad(a[name], 14), b[name])
end
only_a = sort(collect(setdiff(keys(a), keys(b))))
only_b = sort(collect(setdiff(keys(b), keys(a))))
println(
    "\n$(length(differ)) differ, $(length(a) - length(only_a)) in both; ",
    "$(length(only_a)) only in a, $(length(only_b)) only in b",
)
if length(ARGS) == 3
    isempty(only_a) || println("only in a: ", join(only_a, ", "))
    isempty(only_b) || println("only in b: ", join(only_b, ", "))
end
