#=
Helpers shared by the skills' Julia scripts. Include it with

    include(joinpath(@__DIR__, "..", "..", "_lib", "common.jl"))

It holds no skill of its own (no SKILL.md).
=#
import TOML

"""
    git_paths(checkout, ref, dirs) -> Vector{String}

The files under `dirs` (all, for an empty list) in the tree at `ref`.
"""
git_paths(checkout, ref, dirs = String[]) =
    readlines(`git -C $checkout ls-tree -r --name-only $ref -- $dirs`)

"""
    git_blobs(checkout, ref, paths) -> Dict{String, String}

The text of each path at `ref`, read through one `git cat-file --batch`. A path
missing at `ref` is absent from the result.
"""
function git_blobs(checkout, ref, paths)
    files = Dict{String, String}()
    isempty(paths) && return files
    input = IOBuffer(join(("$ref:$p" for p in paths), "\n") * "\n")
    io = IOBuffer(read(pipeline(`git -C $checkout cat-file --batch`; stdin = input)))
    for p in paths
        header = split(readline(io))
        if length(header) == 3 && header[2] == "blob"
            files[p] = String(read(io, parse(Int, header[3])))
            read(io, UInt8)
        end
    end
    return files
end

"""
    has_parse_error(ex) -> Bool

Whether parsed code holds a syntax error. `Meta.parseall` returns one as an
`:error` or `:incomplete` node instead of throwing.
"""
has_parse_error(ex) =
    ex isa Expr && (ex.head in (:error, :incomplete) || any(has_parse_error, ex.args))

"""
    package_dir(env, name) -> (dir or nothing, version or a note)

The source directory of package `name` at the version the environment `env`
resolves, in a depot of `DEPOT_PATH`, or its path when it is developed.
"""
function package_dir(env, name)
    manifest = TOML.parsefile(joinpath(env, "Manifest.toml"))
    deps = get(manifest, "deps", manifest)
    haskey(deps, name) || return (nothing, "not in $env")
    entry = only(deps[name])
    haskey(entry, "path") && return (entry["path"], "path")
    slug = Base.version_slug(Base.UUID(entry["uuid"]), Base.SHA1(entry["git-tree-sha1"]))
    for depot in DEPOT_PATH
        dir = joinpath(depot, "packages", name, slug)
        isdir(dir) && return (dir, get(entry, "version", "?"))
    end
    return (nothing, "$(get(entry, "version", "?")) not in the depot")
end

"""
    defined_name(sig) -> String or nothing

The name a method signature defines: `f`, `M.f`, `(::T)` or `f{T}`, under any
`where` and return type.
"""
function defined_name(sig)
    sig isa Symbol && return string(sig)   # `function f end`
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    sig isa Expr && sig.head == :call || return nothing
    f = sig.args[1]
    f isa Expr && f.head == :curly && (f = f.args[1])
    f isa Expr && f.head == :. && (f = f.args[end])
    f isa QuoteNode && (f = f.value)
    f isa Expr && f.head == :(::) && return string(f.args[end])
    return f isa Symbol ? string(f) : nothing
end

is_method_def(ex) =
    ex isa Expr && (
        (ex.head == :function && defined_name(ex.args[1]) !== nothing) ||
        (ex.head == :(=) && ex.args[1] isa Expr && defined_name(ex.args[1]) !== nothing)
    )

# Blocks a definition can sit in: modules, `begin`, `if` (also `@static if`),
# `let`, and macro calls such as `@inline` or a docstring.
const CONTAINERS =
    (:toplevel, :block, :module, :macrocall, :if, :elseif, :let, :global, :const)

"""
    collect_defs!(defs, ex) -> defs

Every method definition in parsed code, by name: `defs[name]` is a vector of
the definitions' expressions.
"""
function collect_defs!(defs, ex)
    ex isa Expr || return defs
    if is_method_def(ex)
        name = defined_name(ex.args[1])
        name === nothing || push!(get!(defs, name, Expr[]), ex)
    elseif ex.head in CONTAINERS
        foreach(a -> collect_defs!(defs, a), ex.args)
    end
    return defs
end

"""
    strip_lines(ex)

Parsed code without line numbers, also those `remove_linenums!` leaves in macro
calls, so code moved within a file compares equal.
"""
function strip_lines(ex)
    ex = Base.remove_linenums!(deepcopy(ex))
    walk(x) = x
    function walk(x::Expr)
        x.head == :macrocall && length(x.args) >= 2 && x.args[2] isa LineNumberNode &&
            (x.args[2] = nothing)
        foreach(walk, x.args)
        return x
    end
    return walk(ex)
end

"""
    package_definitions(dir, name) -> (defs, dynamic, unresolved)

Every name the package in `dir` defines, by module path: `defs[["Pkg", "Sub"]]` is the set of names module `Pkg.Sub` defines (methods, structs,
abstract types, constants, macros and global assignments). It parses
`src/<name>.jl` and follows `include("file.jl")` into the module that includes
it, so comments and docstrings never count. `dynamic` holds the modules that
define names through `@eval`, whose names cannot be read. `unresolved` counts
includes whose path is not a literal.
"""
function package_definitions(dir, name)
    defs = Dict{Vector{String}, Set{String}}()
    dynamic = Set{Vector{String}}()
    unresolved = Ref(0)
    seen = Set{String}()
    function add!(mod, n)
        push!(get!(defs, mod, Set{String}()), string(n))
    end
    function walk(ex, mod, filedir)
        ex isa Expr || return
        h = ex.head
        if h == :module
            sub = vcat(mod, string(ex.args[2]))
            get!(defs, sub, Set{String}())
            walk(ex.args[3], sub, filedir)
        elseif h == :call && ex.args[1] == :include
            path = ex.args[end]
            if path isa String
                file(joinpath(filedir, path), mod)
            else
                unresolved[] += 1
            end
        elseif is_method_def(ex)
            n = defined_name(ex.args[1])
            n === nothing || add!(mod, n)
        elseif h == :struct
            t = ex.args[2]
            t isa Expr && t.head == :(<:) && (t = t.args[1])
            t isa Expr && t.head == :curly && (t = t.args[1])
            t isa Symbol && add!(mod, t)
        elseif h == :abstract || h == :primitive
            t = ex.args[1]
            t isa Expr && t.head == :(<:) && (t = t.args[1])
            t isa Expr && t.head == :curly && (t = t.args[1])
            t isa Symbol && add!(mod, t)
        elseif h == :macro
            n = defined_name(ex.args[1])
            n === nothing || add!(mod, n)
        elseif h == :(=) && ex.args[1] isa Symbol
            add!(mod, ex.args[1])
        elseif h == :macrocall && ex.args[1] == Symbol("@eval")
            push!(dynamic, mod)
        elseif h == :for || h == :while
            # A loop at top level defines names only through @eval.
            occursin("@eval", string(ex)) && push!(dynamic, mod)
        end
        if h in CONTAINERS && h != :module
            foreach(a -> walk(a, mod, filedir), ex.args)
        end
    end
    function file(path, mod)
        path in seen && return
        push!(seen, path)
        isfile(path) || return
        parsed = Meta.parseall(read(path, String); filename = path)
        walk(parsed, mod, dirname(path))
    end
    # The root file holds `module <name>`, which the walk enters from the top.
    file(joinpath(dir, "src", "$name.jl"), String[])
    return (defs, dynamic, unresolved[])
end
