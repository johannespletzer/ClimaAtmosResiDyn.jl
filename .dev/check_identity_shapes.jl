# Check that a named identity tuple type and everything built or stored with it agree.
#
# One CI round was lost when `execution_identity` grew from five fields to seven while
# `BudgetLedger.recorded_keys` stayed a `Set` of the old five-field tuple: every
# recording was refused with a `convert` MethodError that no local parse could see.
# The rule this enforces is the one that fix introduced. An identity has one named
# type, declared as `const Name = Tuple{...}`; the function that builds it is
# annotated `::Name` and returns a tuple of the same length; and no `Set` or `Dict`
# field in the checked files spells out a tuple key of the same length instead of
# using the name.
#
# Usage: julia --startup-file=no .dev/check_identity_shapes.jl <dir or file>...

function julia_files(paths)
    files = String[]
    for path in paths
        if isdir(path)
            for (root, _, names) in walkdir(path), name in names
                endswith(name, ".jl") && push!(files, joinpath(root, name))
            end
        else
            push!(files, path)
        end
    end
    return sort(files)
end

is_tuple_type(ex) = ex isa Expr && ex.head === :curly && ex.args[1] === :Tuple
tuple_arity(ex) = length(ex.args) - 1

# Walk every expression once, collecting what the rule needs.
function collect!(found, ex, file)
    ex isa Expr || return nothing
    if ex.head === :const && ex.args[1] isa Expr && ex.args[1].head === :(=)
        name, rhs = ex.args[1].args
        if name isa Symbol && is_tuple_type(rhs)
            found.constants[name] = (arity = tuple_arity(rhs), file = file)
        end
    end
    # `f(args)::Name = (a, b, c)` and `function f(args)::Name ... end`
    if ex.head === :(=) || ex.head === :function
        lhs = ex.args[1]
        if lhs isa Expr && lhs.head === :(::) && length(lhs.args) == 2 &&
           lhs.args[1] isa Expr && lhs.args[1].head === :call
            fname = lhs.args[1].args[1]
            rtype = lhs.args[2]
            body = ex.args[2]
            returned = last_tuple(body)
            if rtype isa Symbol && !isnothing(returned)
                push!(
                    found.builders,
                    (name = fname, type = rtype, arity = returned, file = file),
                )
            end
        end
    end
    # struct fields `x::Set{Tuple{...}}` and `x::Dict{Tuple{...}, V}`
    if ex.head === :(::) && length(ex.args) == 2
        fieldtype = ex.args[2]
        if fieldtype isa Expr && fieldtype.head === :curly &&
           fieldtype.args[1] in (:Set, :Dict)
            key = fieldtype.args[2]
            is_tuple_type(key) &&
                push!(
                    found.literal_keys,
                    (field = ex.args[1], arity = tuple_arity(key), file = file),
                )
        end
    end
    foreach(a -> collect!(found, a, file), ex.args)
    return nothing
end

# The tuple a one-expression body or a block ending in a tuple returns, else nothing.
function last_tuple(body)
    body isa Expr || return nothing
    if body.head === :tuple
        return length(body.args)
    elseif body.head === :block
        for arg in reverse(body.args)
            arg isa LineNumberNode && continue
            return last_tuple(arg)
        end
    elseif body.head === :return && length(body.args) == 1
        return last_tuple(body.args[1])
    end
    return nothing
end

function main(paths)
    found = (;
        constants = Dict{Symbol, Any}(),
        builders = [],
        literal_keys = [],
    )
    for file in julia_files(paths)
        collect!(found, Meta.parseall(read(file, String); filename = file), file)
    end
    problems = String[]
    for (name, c) in found.constants
        for b in found.builders
            b.type === name || continue
            b.arity == c.arity || push!(
                problems,
                "$(b.file): $(b.name) returns $(b.arity) fields but $name has $(c.arity)",
            )
        end
        for k in found.literal_keys
            k.arity == c.arity || continue
            push!(
                problems,
                "$(k.file): field $(k.field) spells out a $(k.arity)-tuple key; use $name",
            )
        end
    end
    isempty(found.constants) && println("   no named identity tuple found")
    for (name, c) in found.constants
        n = count(b -> b.type === name, found.builders)
        println("   $name: $(c.arity) fields, $n builder(s)")
    end
    foreach(p -> println("   ", p), problems)
    isempty(problems) || exit(1)
end

main(ARGS)
