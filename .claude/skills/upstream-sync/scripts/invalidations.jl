#=
Count the invalidations of loading ClimaAtmos, as the Invalidations workflow
does with julia-invalidations, and list the invalidated methods.

    julia +1.10 --project=<env> invalidations.jl <out_prefix>

`env` is built with `make_ci_env.jl <checkout> <env> invalidations [ci_log]`
and precompiled first, as CI's `julia-buildpkg` step does. It prints
`inv_total` and `inv_deps` as the workflow does, and writes the invalidated
method instances, one per line and sorted, to `<out_prefix>.methods`. `comm`
on two such files says whether two builds invalidate the same methods.

The count can differ from CI's by a few, since the order packages load in is
not fixed. Repeat a count before reading a small difference.
=#
length(ARGS) == 1 || error("usage: invalidations.jl <out_prefix>")
using SnoopCompileCore: @snoop_invalidations
invalidations = @snoop_invalidations begin
    import ClimaAtmos
end

using SnoopCompile: SnoopCompile, filtermod, invalidation_trees, uinvalidated
trees = invalidation_trees(invalidations)
inv_owned = length(filtermod(ClimaAtmos, trees))
methods = uinvalidated(invalidations)
inv_total = length(methods)
inv_deps = inv_total - inv_owned
println("inv_total $inv_total")
println("inv_deps $inv_deps")
println("julia $VERSION, ClimaAtmos at ", pkgdir(ClimaAtmos))

open(ARGS[1] * ".methods", "w") do io
    foreach(m -> println(io, m), sort(string.(collect(methods))))
end
# The trees that invalidate the most, which name the package to blame.
for tree in last(trees, min(8, length(trees)))
    println(SnoopCompile.countchildren(tree), "  ", tree.method)
end
