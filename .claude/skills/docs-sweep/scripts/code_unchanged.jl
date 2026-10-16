#=
Whether a branch changed only text: comments, docstrings, help texts and
messages.

    julia +1.11 code_unchanged.jl <checkout> <base_ref> <head_ref>

The branch's changes are taken from the merge base of the two refs, as
`git diff base...head`, so commits on the base since the branch left it do not
count. Each changed file is judged by its type:

- `.jl`: the code is parsed at both and compared without line numbers,
  comments and docstrings. A docstring's interpolations (`$(...)`) run when
  the file loads, so they count as code.
  - `text only`: the code is the same.
  - `MESSAGES`: the code is the same except the text of messages: the
    literal strings (and the literal pieces of interpolations, `string`, `*`
    and `repr`) that are arguments of `error`, `@warn`, `@info`, `@error`,
    `@debug`, a constructor named `*Error` or `*Exception`, the message of
    `@assert` (not its condition), and `print`, `println`, `printstyled` and
    `@printf` when they print to the terminal (no IO argument). A dict key, a
    condition or a call inside a message is code. Messages are visible
    behaviour, so the PR says it changes them. The changed strings are listed.
  - `CODE CHANGED`: anything else, including a changed string that the code
    uses: a dict key, a regex, an `include` path, a `Symbol("...")` name.
- `.yml`, `.yaml`: compared without comments, blank lines and `help:` entries
  (one line, or a block indented below it). Anything else is `CONFIG CHANGED`.
- `.md`, `.bib` and images: text, listed as `docs`.
- Files under `docs/` outside `docs/src/` (such as `docs/make.jl`), `.dev/`
  and `.github/`: the docs build and CI, not the model. They are judged the
  same way, and a change beyond text is listed as `TOOLING` with its verdict,
  but it does not fail the check, since the claim is about the model's code,
  keys, defaults and output. The PR names them.
- Anything else, such as `.toml` (parameters, compat), `.sh` or `.py`, is
  `OTHER CHANGED`, since a docs sweep does not touch it.

Only committed changes count: with none, it says so and exits 1. Exit status
0 when nothing but text changed (messages and tooling included), 1 otherwise.
=#
include(joinpath(@__DIR__, "..", "..", "_lib", "common.jl"))

length(ARGS) == 3 || error("usage: code_unchanged.jl <checkout> <base_ref> <head_ref>")
checkout, base_ref, head = ARGS
base = readchomp(`git -C $checkout merge-base $base_ref $head`)
changed = readlines(`git -C $checkout diff --name-only $base $head`)
old_files = git_blobs(checkout, base, changed)
new_files = git_blobs(checkout, head, changed)

is_doc(f) =
    f isa GlobalRef && f.name == Symbol("@doc") || f == Symbol("@doc") ||
    f isa Expr && f.head == :. && f.args[end] == QuoteNode(Symbol("@doc"))

# Parsed code without line numbers, each docstring replaced by the definition it
# documents and the docstring's interpolations, which run at load time.
function normalize(ex)
    ex isa Expr || return ex
    if ex.head == :macrocall && is_doc(ex.args[1])
        args = filter(a -> !(a isa LineNumberNode), ex.args[2:end])
        length(args) >= 2 || return nothing
        doc, def = args[1], args[end]
        interpolations =
            doc isa Expr && doc.head == :string ?
            Any[normalize(a) for a in doc.args if !(a isa String)] : Any[]
        return isempty(interpolations) ? normalize(def) :
               Expr(:block, Expr(:doc_interpolations, interpolations...), normalize(def))
    end
    if ex.head == :macrocall
        return Expr(:macrocall, normalize(ex.args[1]), nothing,
            (normalize(a) for a in ex.args[3:end] if !(a isa LineNumberNode))...)
    end
    return Expr(ex.head, (normalize(a) for a in ex.args if !(a isa LineNumberNode))...)
end

const MESSAGE_CALLS = (:error, :ErrorException)
const PRINT_CALLS = (:print, :println, :printstyled)
const MESSAGE_MACROS =
    (Symbol("@warn"), Symbol("@info"), Symbol("@error"), Symbol("@debug"))
callee(ex) =
    ex isa Symbol ? ex :
    ex isa Expr && ex.head == :. && ex.args[end] isa QuoteNode ? ex.args[end].value :
    ex isa GlobalRef ? ex.name : nothing
is_text_piece(a) = a isa String || a isa Expr && a.head == :string

# The arguments of a message call that are its text, or `nothing`. Only those
# are blanked, never a condition or other code inside the call:
# - `error(...)`, `*Error(...)`, `*Exception(...)`, `@warn`, `@info`, `@error`
#   and `@debug`: every argument.
# - `@assert cond msg...`: the arguments after the condition.
# - `print`, `println` and `printstyled`, and `@printf`: only when the first
#   argument is text, so the output goes to the terminal. With an IO first
#   argument they write output, which the claim covers.
function message_args(ex)
    ex isa Expr || return nothing
    if ex.head == :call
        f = callee(ex.args[1])
        f isa Symbol || return nothing
        args = ex.args[2:end]
        if f in MESSAGE_CALLS || endswith(string(f), "Error") ||
           endswith(string(f), "Exception")
            return 2:length(ex.args)
        elseif f in PRINT_CALLS
            return !isempty(args) && is_text_piece(args[1]) ? (2:length(ex.args)) : nothing
        end
    elseif ex.head == :macrocall
        m = callee(ex.args[1])
        m in MESSAGE_MACROS && return 3:length(ex.args)
        m == Symbol("@assert") && return 4:length(ex.args)
        m == Symbol("@printf") && length(ex.args) >= 3 && ex.args[3] isa String &&
            return 3:length(ex.args)
    end
    return nothing
end

# A message's text: a string literal, or the literal pieces of a `"... $(x)"`,
# `string(...)`, `a * b` or `repr(...)`. Interpolated code, dict keys, other
# calls and macros are code and stay as they are.
function blank_text(a)
    a isa String && return ""
    a isa Expr || return a
    if a.head == :string
        return Expr(:string, (x isa String ? "" : x for x in a.args)...)
    elseif a.head == :call && callee(a.args[1]) in (:string, :*, :repr)
        return Expr(:call, a.args[1], (blank_text(x) for x in a.args[2:end])...)
    end
    return a
end
function text_pieces!(acc, a)
    if a isa String
        push!(acc, a)
    elseif a isa Expr && a.head == :string
        foreach(x -> x isa String && push!(acc, x), a.args)
    elseif a isa Expr && a.head == :call && callee(a.args[1]) in (:string, :*, :repr)
        foreach(x -> text_pieces!(acc, x), a.args[2:end])
    end
    return acc
end

# The code with the text of every message blanked, and that text.
function blank_messages(ex)
    ex isa Expr || return ex
    idx = message_args(ex)
    args = Any[blank_messages(a) for a in ex.args]
    if idx !== nothing
        for i in idx
            args[i] = blank_text(args[i])
        end
    end
    return Expr(ex.head, args...)
end
function messages!(acc, ex)
    ex isa Expr || return acc
    idx = message_args(ex)
    idx === nothing || foreach(i -> text_pieces!(acc, ex.args[i]), idx)
    foreach(a -> messages!(acc, a), ex.args)
    return acc
end

function toplevel_items(ex)
    items = Pair{String, Any}[]
    for a in (ex isa Expr && ex.head == :toplevel ? ex.args : [ex])
        a === nothing && continue
        key = a isa Expr ? first(split(sprint(print, a), '\n'))[1:min(end, 80)] : string(a)
        push!(items, key => a)
    end
    return items
end

function strip_yaml(t)
    out = String[]
    skip_indent = -1
    for l in eachline(IOBuffer(t))
        s = replace(l, r"\s+#.*$" => "")
        startswith(lstrip(s), "#") && continue
        isempty(strip(s)) && continue
        indent = length(s) - length(lstrip(s))
        skip_indent >= 0 && indent > skip_indent && continue
        skip_indent = -1
        if startswith(lstrip(s), "help:")
            skip_indent = indent
            continue
        end
        push!(out, rstrip(s))
    end
    return out
end

# One file's verdict: (failed, lines). `failed` is whether the change is more
# than text.
function judge(path, old, new)
    lines = String[]
    if endswith(path, ".jl")
        (old === nothing || new === nothing) &&
            return (true, ["CODE CHANGED  $path: $(old === nothing ? "added" : "deleted")"])
        a = normalize(Meta.parseall(old; filename = path))
        b = normalize(Meta.parseall(new; filename = path))
        has_parse_error(b) &&
            return (true, ["CODE CHANGED  $path: does not parse at $head"])
        a == b && return (false, ["text only     $path"])
        if blank_messages(a) == blank_messages(b)
            ma, mb = messages!(String[], a), messages!(String[], b)
            pairs = [(x, y) for (x, y) in zip(ma, mb) if x != y]
            push!(lines, "MESSAGES      $path: $(length(pairs)) strings in messages")
            for (x, y) in first(pairs, 8)
                push!(lines, "    - " * repr(x)[1:min(end, 150)])
                push!(lines, "    + " * repr(y)[1:min(end, 150)])
            end
            return (false, lines)
        end
        ia, ib = toplevel_items(a), toplevel_items(b)
        sa = Set(sprint(print, x) for (_, x) in ia)
        sb = Set(sprint(print, x) for (_, x) in ib)
        only_a = [k for (k, x) in ia if !(sprint(print, x) in sb)]
        only_b = [k for (k, x) in ib if !(sprint(print, x) in sa)]
        push!(
            lines,
            "CODE CHANGED  $path: $(max(length(only_a), length(only_b))) definitions differ",
        )
        foreach(k -> push!(lines, "    - $k"), first(only_a, 6))
        foreach(k -> push!(lines, "    + $k"), first(only_b, 6))
        return (true, lines)
    elseif endswith(path, ".yml") || endswith(path, ".yaml")
        old !== nothing && new !== nothing && strip_yaml(old) == strip_yaml(new) &&
            return (false, ["text only     $path"])
        return (
            true,
            [
                "CONFIG CHANGED $path$(old === nothing ? " (added)" : new === nothing ? " (deleted)" : "")",
            ],
        )
    elseif occursin(r"\.(md|bib|png|svg|jpe?g|gif)$"i, path)
        return (false, ["docs          $path"])
    end
    return (true, ["OTHER CHANGED $path"])
end

if isempty(changed)
    println(
        "No committed change between the merge base $(base[1:9]) of $base_ref and $head.",
    )
    println("Commit the change first: only committed changes are compared.")
    exit(1)
end
bad = false
report = String[]
is_tooling(path) =
    (startswith(path, "docs/") && !startswith(path, "docs/src/")) ||
    startswith(path, ".dev/") || startswith(path, ".github/")
for path in changed
    failed, lines =
        judge(path, get(old_files, path, nothing), get(new_files, path, nothing))
    if is_tooling(path) && failed
        # The docs build and CI are not the model: listed with the verdict, but
        # they do not fail the check.
        push!(report, "TOOLING       $(lines[1]) (docs build or CI, not the model)")
        append!(report, lines[2:end])
    else
        append!(report, lines)
        failed && (global bad = true)
    end
end
println(
    "$(length(changed)) files changed from the merge base $(base[1:9]) of $base_ref to $head",
)
foreach(println, report)
println(
    bad ? "\nThe code, a config or another file changed." :
    "\nOnly text changed: comments, docstrings, help texts and Markdown, plus any messages and tooling listed.",
)
exit(bad ? 1 : 0)
