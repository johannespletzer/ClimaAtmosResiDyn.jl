#=
Find the names upstream removed or changed between two commits that the
fork's own lines still use.

    julia +1.11 removed_names.jl <checkout> <old_ref> <new_ref> [tree_ref]

`old_ref` is the upstream commit last merged and `new_ref` the one to merge.
Both are read from the checkout's git repository. The search runs over the
checkout's working tree, so run it on the merge branch after the merge commit,
where every hit is a site still to port. Run before the merge, on the fork's
main, it also lists sites the merge itself will resolve.

It parses `src/` and `ext/` at both commits and collects every top-level
definition: functions with each method's positional argument types and
keyword names, structs with their fields, abstract types, constants, globals
and macros. A name is removed when no definition is left, and changed when
its set of signatures or fields differs. It then searches the working tree's
`.jl`, `.md` and `.yml` files for those names, skipping every line that also
appears verbatim in the same file at `new_ref`, so that only the fork's own
lines are reported. With `tree_ref`, such as the merge commit or the fork's
`origin/main`, the fork's files are read from that commit instead.

Not found: a dependency's removed names (read its release notes and grep for
them), a changed default, a changed return type, a method moved to another
file, a call that only passes a changed keyword and a config key (see the
survey's key list).
=#

length(ARGS) in 3:4 ||
    error("usage: removed_names.jl <checkout> <old_ref> <new_ref> [tree_ref]")
checkout, old_ref, new_ref = abspath(ARGS[1]), ARGS[2], ARGS[3]
tree_ref = length(ARGS) == 4 ? ARGS[4] : nothing
git(args...) = read(`git -C $checkout $args`, String)

# Every blob under `dirs` at `ref`, read through one `git cat-file`.
function blobs(ref, dirs; exts = (".jl",))
    paths = filter(
        p -> any(e -> endswith(p, e), exts),
        split(
            git("ls-tree", "-r", "--name-only", ref, "--", dirs...),
            '\n';
            keepempty = false,
        ),
    )
    out = Dict{String, String}()
    isempty(paths) && return out
    input = IOBuffer(join(("$ref:$p" for p in paths), '\n') * "\n")
    io = IOBuffer(read(pipeline(`git -C $checkout cat-file --batch`; stdin = input)))
    for p in paths
        header = split(readline(io))
        size = parse(Int, header[3])
        out[p] = String(read(io, size))
        read(io, UInt8)  # the newline after each blob
    end
    return out
end

typestring(ex) = replace(string(ex), r"\s+" => " ")

function argstring(arg)
    arg isa Symbol && return "_"
    arg isa Expr || return typestring(arg)
    arg.head == :(::) && return typestring(last(arg.args))
    arg.head == :kw && return "[" * argstring(arg.args[1]) * "]"
    arg.head == :... && return argstring(arg.args[1]) * "..."
    arg.head == :meta && return ""
    return typestring(arg)
end

# The name and signature of a method from its call expression, or nothing for
# a method of a qualified name such as `Base.show`, which removes nothing.
function method_of(sig)
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    sig isa Expr && sig.head == :call || return nothing
    f = sig.args[1]
    f isa Expr && f.head == :curly && (f = f.args[1])
    f isa Symbol || return nothing
    positional = String[]
    keywords = String[]
    for arg in sig.args[2:end]
        if arg isa Expr && arg.head == :parameters
            for kw in arg.args
                k = kw isa Expr && kw.head == :kw ? kw.args[1] : kw
                k isa Expr && k.head == :(::) && (k = k.args[1])
                k isa Expr && k.head == :... && (k = Symbol(string(k.args[1], "...")))
                push!(keywords, string(k))
            end
        else
            push!(positional, argstring(arg))
        end
    end
    s =
        "(" * join(positional, ", ") *
        (isempty(keywords) ? "" : "; " * join(sort(keywords), ", ")) * ")"
    return (string(f), s)
end

function typename(ex)
    while ex isa Expr && ex.head in (:<:, :curly)
        ex = ex.args[1]
    end
    return ex isa Symbol ? string(ex) : nothing
end

function collect_defs!(defs, ex)
    ex isa Expr || return
    add(name, sig) = name === nothing || push!(get!(defs, name, Set{String}()), sig)
    h = ex.head
    if h in (:toplevel, :block)
        foreach(a -> collect_defs!(defs, a), ex.args)
    elseif h == :module
        collect_defs!(defs, ex.args[3])
    elseif h == :macrocall
        foreach(a -> collect_defs!(defs, a), ex.args[2:end])
    elseif h == :if || h == :elseif
        foreach(a -> collect_defs!(defs, a), ex.args[2:end])
    elseif h == :function ||
           (h == :(=) && ex.args[1] isa Expr && method_of(ex.args[1]) !== nothing)
        m = method_of(ex.args[1])
        m === nothing || add(m...)
    elseif h == :struct
        body = ex.args[3]
        fields = String[]
        for f in body.args
            f isa Symbol && push!(fields, string(f))
            f isa Expr && f.head == :(::) && f.args[1] isa Symbol &&
                push!(fields, string(f.args[1]))
            f isa Expr && f.head == :(=) && f.args[1] isa Symbol &&
                push!(fields, string(f.args[1]))
            f isa Expr && f.head == :(=) && f.args[1] isa Expr && f.args[1].head == :(::) &&
                push!(fields, string(f.args[1].args[1]))
            # Inner constructors.
            f isa Expr && f.head in (:function, :(=), :macrocall) && collect_defs!(defs, f)
        end
        add(typename(ex.args[2]), "struct {" * join(fields, ", ") * "}")
    elseif h in (:abstract, :primitive)
        add(typename(ex.args[1]), string(h))
    elseif h == :const
        collect_defs!(defs, ex.args[1])
    elseif h == :(=) && ex.args[1] isa Symbol
        add(string(ex.args[1]), "global")
    elseif h == :macro
        m = method_of(ex.args[1])
        m === nothing || add("@" * m[1], "macro" * m[2])
    end
end

function definitions(ref)
    defs = Dict{String, Set{String}}()
    for (path, text) in blobs(ref, ["src", "ext"])
        ex = try
            Meta.parseall(text; filename = path)
        catch err
            @warn "$path at $ref does not parse" err
            continue
        end
        collect_defs!(defs, ex)
    end
    return defs
end

old, new = definitions(old_ref), definitions(new_ref)
removed = sort([n for n in keys(old) if !haskey(new, n)])
changed = sort([n for n in keys(old) if haskey(new, n) && old[n] != new[n]])
wanted = Set(vcat(removed, changed))

# Identifiers of a line, with a macro's `@`.
function identifiers(line)
    ids = String[]
    i = firstindex(line)
    while i <= lastindex(line)
        c = line[i]
        if Base.is_id_start_char(c) &&
           (i == firstindex(line) || !Base.is_id_char(line[prevind(line, i)]))
            j = i
            while nextind(line, j) <= lastindex(line) &&
                  Base.is_id_char(line[nextind(line, j)])
                j = nextind(line, j)
            end
            name = line[i:j]
            i > firstindex(line) && line[prevind(line, i)] == '@' && (name = "@" * name)
            push!(ids, name)
            i = nextind(line, j)
        else
            i = nextind(line, i)
        end
    end
    return ids
end

# Lines the fork wrote, and lines upstream had at `old_ref` and dropped by
# `new_ref`. Before the merge, the merge replaces the second kind. After it,
# one left over is a resolution that kept upstream's old code.
hits = Dict{String, Vector{String}}()
stale = Dict{String, Vector{String}}()
files_at(ref) =
    Set(split(git("ls-tree", "-r", "--name-only", ref), '\n'; keepempty = false))
lines_at(ref, files, path) =
    path in files ? Set(strip.(split(git("show", "$ref:$path"), '\n'))) : Set{String}()
new_files, old_files = files_at(new_ref), files_at(old_ref)
dirs = [
    "src",
    "ext",
    "test",
    "docs",
    "examples",
    "post_processing",
    "config",
    "reproducibility_tests",
]
exts = (".jl", ".md", ".yml")
fork_files = if tree_ref === nothing
    paths = split(git("ls-files", "--", dirs...), '\n'; keepempty = false)
    Dict(
        p => read(joinpath(checkout, p), String) for p in paths if
        any(e -> endswith(p, e), exts) && isfile(joinpath(checkout, p))
    )
else
    blobs(tree_ref, dirs; exts)
end
for path in sort(collect(keys(fork_files)))
    lines = split(fork_files[path], '\n')
    candidates = [(k, l) for (k, l) in enumerate(lines) if any(in(wanted), identifiers(l))]
    isempty(candidates) && continue
    theirs = lines_at(new_ref, new_files, path)
    before = lines_at(old_ref, old_files, path)
    for (k, l) in candidates
        strip(l) in theirs && continue
        target = strip(l) in before ? stale : hits
        for name in intersect(Set(identifiers(l)), wanted)
            push!(get!(target, name, String[]), "$path:$k: " * first(strip(l), 110))
        end
    end
end

function report(title, names, show_sigs)
    used = filter(n -> haskey(hits, n), names)
    println("\n## $title: $(length(names)), used in the fork's own lines: $(length(used))")
    for n in used
        println(
            "\n$n  ($(length(hits[n])) fork lines, $(length(get(stale, n, []))) of upstream's old lines)",
        )
        if show_sigs
            foreach(s -> println("  - ", s), sort(collect(setdiff(old[n], new[n]))))
            foreach(s -> println("  + ", s), sort(collect(setdiff(new[n], old[n]))))
        else
            foreach(s -> println("  was ", s), first(sort(collect(old[n])), 3))
        end
        foreach(h -> println("    ", h), first(hits[n], 6))
        length(hits[n]) > 6 && println("    … $(length(hits[n]) - 6) more")
    end
end

println("definitions: $(length(old)) names at $old_ref, $(length(new)) at $new_ref")
report("Removed upstream", removed, false)
report("Changed upstream (methods or fields)", changed, true)
if !isempty(stale)
    println("\n## Upstream's old lines still in the tree, by name")
    for n in sort(collect(keys(stale)))
        println("$n: ", join(first(stale[n], 3), " | "), length(stale[n]) > 3 ? " …" : "")
    end
end
