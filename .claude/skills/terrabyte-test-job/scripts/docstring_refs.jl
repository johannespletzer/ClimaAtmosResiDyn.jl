# The docstring reference check of `docs/make.jl`, without building the docs.
# Run it in a `docs` environment from make_ci_env.jl, which has Documenter.
import ClimaAtmos
import Documenter
root = pkgdir(ClimaAtmos)
include(joinpath(root, "docs", "check_docstring_refs.jl"))
check_docstring_refs(ClimaAtmos, joinpath(root, "docs", "src"))
println("docstring refs: OK")
