#=
Checks of the fork's docs and comments over whole files, not only a diff.

    julia +1.11 text_checks.jl <checkout> <ref> <upstream_ref> [--all]

`ref` is the tree to check (`HEAD`, or a branch). `upstream_ref` is the
upstream commit last merged: a line found verbatim in upstream's copy of the
same file is upstream's, and the fork's rules do not apply to it, so only the
fork's lines are checked. `--all` lists every hit, not only the first 15 per
check. Read through git, so the working tree does not matter.

The text is `docs/src/**/*.md` and, in `src/**/*.jl`, comments and
docstrings. The checks:

1. Wording: plan and finding IDs, PR numbers and dates, history words
   ("previously", "no longer", "used to") and "bracket" (now "applied-update
   event"), as pr-preflight's scan, but over the whole file. Em dashes and
   semicolons in comments are listed apart as style.
2. Stale names: a backticked identifier in the fork's text that the code
   under `src/`, `test/`, `ext/`, `docs/` and `post_processing/` never uses,
   and that is not a config key. It catches comments that name removed
   functions. A name of another package (`BMT._linearize`) is checked by its
   last part, so a renamed package function still shows.
3. Paths: backticked paths (`src/...`, `*.jl`, `*.md`, `*.yml`, `*.toml`)
   and relative Markdown links that name no file in the tree.
4. Headings: the same heading text twice in docs/src, where one is the
   fork's. Documenter's `[...](@ref)` to a heading needs it to be unique.
5. Glossary: a bold term of the fork's in docs/src/glossary.md that no other
   page and no comment uses.

Exit status 0 when checks 1 to 4 find nothing in the fork's text.
=#
args = copy(ARGS)
show_all = "--all" in args
filter!(!=("--all"), args)
length(args) == 3 || error("usage: text_checks.jl <checkout> <ref> <upstream_ref> [--all]")
checkout, ref, upstream_ref = args
limit = show_all ? typemax(Int) : 15

function blobs(r, paths)
    input = IOBuffer(join(("$r:$p" for p in paths), "\n") * "\n")
    io = IOBuffer(read(pipeline(`git -C $checkout cat-file --batch`; stdin = input)))
    files = Dict{String, String}()
    for p in paths
        header = split(readline(io))
        if length(header) == 3
            files[p] = String(read(io, parse(Int, header[3])))
            read(io, UInt8)
        end
    end
    return files
end
tree_paths = readlines(`git -C $checkout ls-tree -r --name-only $ref`)
tree_set = Set(tree_paths)
wanted = filter(
    p ->
        (startswith(p, "docs/src/") && endswith(p, ".md")) ||
        (
            endswith(p, ".jl") && any(
                d -> startswith(p, d),
                ("src/", "test/", "ext/", "docs/", "post_processing/"),
            )
        ) ||
        p == "config/default_configs/default_config.yml", tree_paths)
files = blobs(ref, wanted)
upstream = blobs(upstream_ref, wanted)

# The fork's text lines of a file: (line number, text). For `.jl`, comments and
# docstrings only.
function text_lines(path, text)
    up = Set(eachline(IOBuffer(get(upstream, path, ""))))
    out = Tuple{Int, String}[]
    in_doc = false
    in_fence = false
    for (i, line) in enumerate(eachline(IOBuffer(text)))
        if endswith(path, ".md") && startswith(lstrip(line), "```")
            in_fence = !in_fence
            continue
        end
        in_fence && continue
        line in up && (
            endswith(path, ".jl") && occursin("\"\"\"", line) &&
                (in_doc = isodd(count("\"\"\"", line)) ⊻ in_doc);
            continue
        )
        if endswith(path, ".md")
            push!(out, (i, line))
        elseif endswith(path, ".jl")
            n = count("\"\"\"", line)
            if in_doc || n > 0
                push!(out, (i, line))
                isodd(n) && (in_doc = !in_doc)
            else
                m = match(r"(?:^|\s)#(?!=)\s?(.*)$", line)
                m === nothing || push!(out, (i, m[1]))
            end
        end
    end
    return out
end
fork_text = Dict(p => text_lines(p, t) for (p, t) in files if !endswith(p, ".yml"))
src_only(p) = startswith(p, "src/") || startswith(p, "docs/src/")

problems = 0
function section(title, hits; counts = true)
    println("\n## $title: $(length(hits))")
    for h in first(hits, limit)
        println("  ", h)
    end
    length(hits) > limit && println("  ... $(length(hits) - limit) more (--all)")
    counts && (global problems += length(hits))
end

# 1. Wording.
wording =
    r"#[0-9]{2,}\b|20[0-9]{2}-[0-9]{2}-[0-9]{2}|\b(WP[0-9][a-z]?|OD[0-9]+|G[0-9]+\.[0-9]+|W[0-9]{2}|FINDINGS?)\b|[Pp]art [0-9]+[a-d]?\b|\b(previously|no longer|used to)\b|\bbracket"
hits = String[]
style = String[]
for p in sort(collect(keys(fork_text))), (i, l) in fork_text[p]
    src_only(p) || continue
    m = match(wording, l)
    m === nothing || push!(hits, "$p:$i  `$(m.match)`  $(strip(l)[1:min(end, 110)])")
    # A `;` inside parentheses is a keyword argument, not prose.
    prose = l
    while occursin(r"\([^()]*\)", prose)
        prose = replace(prose, r"\([^()]*\)" => "")
    end
    endswith(p, ".jl") && occursin(r"—|;", prose) &&
        push!(style, "$p:$i  $(strip(l)[1:min(end, 110)])")
end
section("1. Wording in the fork's docs and comments", hits)
section(
    "1b. Em dashes and semicolons in the fork's comments (style)",
    style;
    counts = false,
)

# 2. Stale names. Every symbol the code uses, from parsed code, so a name only
# in comments does not count.
symbols = Set{String}()
# A docstring is text, so only the definition it documents counts. Other
# strings count, since the code builds names from them (diagnostic names,
# option values).
is_doc(f) = f isa GlobalRef && f.name == Symbol("@doc") || f == Symbol("@doc")
function collect_symbols!(ex)
    if ex isa Symbol
        push!(symbols, string(ex))
    elseif ex isa String
        foreach(m -> push!(symbols, m.match), eachmatch(r"[\p{L}_][\p{L}\p{N}_!]*", ex))
    elseif ex isa QuoteNode
        collect_symbols!(ex.value)
    elseif ex isa Expr && ex.head == :macrocall && is_doc(ex.args[1])
        collect_symbols!(ex.args[end])
    elseif ex isa Expr
        foreach(collect_symbols!, ex.args)
    end
end
for (p, t) in files
    endswith(p, ".jl") || continue
    try
        collect_symbols!(Meta.parseall(t; filename = p))
    catch
    end
end
config = get(files, "config/default_configs/default_config.yml", "")
for m in eachmatch(r"^([A-Za-z0-9_]+):"m, config)
    push!(symbols, m[1])
end
ident = r"^[\p{L}_][\p{L}\p{N}_!′₀-₉⁰-⁹ʲ]*(?:\.[\p{L}_][\p{L}\p{N}_!′₀-₉⁰-⁹ʲ]*)*$"
hits = String[]
for p in sort(collect(keys(fork_text))), (i, l) in fork_text[p]
    src_only(p) || continue
    for m in eachmatch(r"`([^`\n]+)`", l)
        s = strip(m[1])
        c = match(r"^([\p{L}_][\p{L}\p{N}_!′.]*)\(", s)
        c === nothing || (s = c[1])
        occursin(ident, s) || continue
        name = last(split(s, '.'))
        # Short names and symbols without an ASCII letter are maths, and
        # names with a file extension are paths, which check 3 reads.
        length(name) <= 3 && continue
        occursin(r"[A-Za-z]", name) || continue
        occursin(r"\.(jl|md|ya?ml|toml|nc|csv|txt|json|sh|py)$", s) && continue
        s in ("true", "false", "nothing", "missing") && continue
        occursin(r"^[0-9a-f]{7,40}$", s) && continue   # a commit
        name in symbols && continue
        push!(hits, "$p:$i  `$s`")
    end
end
section("2. Backticked names the code never uses", unique(hits))

# 3. Paths.
exists(path) =
    path in tree_set || any(q -> endswith(q, "/" * path), tree_paths) ||
    any(q -> startswith(q, rstrip(path, '/') * "/"), tree_paths)
hits = String[]
for p in sort(collect(keys(fork_text))), (i, l) in fork_text[p]
    src_only(p) || continue
    for m in eachmatch(
        r"`((?:src|test|docs|config|ext|\.buildkite|\.github|post_processing|reproducibility_tests)/[^`\s]*|[^`\s/]+\.(?:jl|md|yml|toml))`",
        l,
    )
        path = replace(m[1], r"[#:].*$" => "")
        occursin(r"[<>*{}]", path) && continue
        isempty(path) || exists(path) || push!(hits, "$p:$i  `$(m[1])`")
    end
    endswith(p, ".md") || continue
    for m in eachmatch(r"\]\(([^)\s]+)\)", l)
        target = m[1]
        (
            occursin("://", target) || startswith(target, "#") ||
            startswith(target, "@ref") || startswith(target, "mailto:")
        ) && continue
        rel = replace(target, r"#.*$" => "")
        isempty(rel) && continue
        resolved = normpath(joinpath(dirname(p), rel))
        resolved in tree_set || isdir(joinpath(checkout, resolved)) || exists(resolved) ||
            push!(hits, "$p:$i  link $(target)")
    end
end
section("3. Paths and links that name no file", unique(hits))

# 4. Headings.
headings = Dict{String, Vector{Tuple{String, Int, Bool}}}()
for (p, t) in files
    (startswith(p, "docs/src/") && endswith(p, ".md")) || continue
    up = Set(eachline(IOBuffer(get(upstream, p, ""))))
    in_code = false
    for (i, l) in enumerate(eachline(IOBuffer(t)))
        startswith(l, "```") && (in_code = !in_code)
        in_code && continue
        m = match(r"^#{1,6}\s+(.+?)\s*$", l)
        m === nothing && continue
        push!(get!(headings, m[1], Tuple{String, Int, Bool}[]), (p, i, !(l in up)))
    end
end
# A heading is a link target by its text: `[Heading](@ref)` or
# `[text](@ref "Heading")`, in the docs and in docstrings.
referenced = Set{String}()
for t in values(files)
    foreach(m -> push!(referenced, m[1]), eachmatch(r"\[([^\]]+)\]\(@ref\)", t))
    foreach(m -> push!(referenced, m[1]), eachmatch(r"\(@ref \"([^\"]+)\"\)", t))
end
hits, info = String[], String[]
for (h, places) in headings
    length(places) > 1 && any(x -> x[3], places) || continue
    line = "\"$h\": " * join(("$(x[1]):$(x[2])" for x in places), ", ")
    push!(h in referenced ? hits : info, line)
end
section("4. Repeated headings that an @ref points at", sort(hits))
section(
    "4b. Repeated headings no @ref points at (harmless now)",
    sort(info);
    counts = false,
)

# 5. Glossary.
glossary = get(files, "docs/src/glossary.md", "")
others = join((t for (p, t) in files if p != "docs/src/glossary.md" && src_only(p)), "\n")
hits = String[]
for (i, l) in get(fork_text, "docs/src/glossary.md", Tuple{Int, String}[])
    for m in eachmatch(r"\*\*([^*]+)\*\*", l)
        term = strip(m[1])
        occursin(lowercase(term), lowercase(others)) ||
            push!(hits, "docs/src/glossary.md:$i  **$term**")
    end
end
section("5. Glossary terms of the fork's that nothing else uses", hits; counts = false)

println(
    problems == 0 ? "\nChecks 1 to 4 find nothing in the fork's text." :
    "\n$problems hits in checks 1 to 4.",
)
exit(problems == 0 ? 0 : 1)
