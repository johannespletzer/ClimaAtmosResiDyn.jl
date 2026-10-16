#=
Build a Julia environment that loads a checkout of the fork, for a test or
parity job on terrabyte.

    julia +1.11 make_ci_env.jl <checkout> <env_dir> [kind] [ci_log]
    julia +1.10 make_ci_env.jl <checkout> <env_dir> [kind] [ci_log]

- `test` (the default) is what `Pkg.test()` builds in CI: ClimaAtmos, its
  dependencies and the test target's extras, resolved afresh under the root
  project's compat. That gives the versions CI resolves on the same day.
- `buildkite` copies `.buildkite/Project.toml` and pins `Manifest-v1.11.toml`,
  for `.buildkite/ci_driver.jl`. Those pins lag CI's own resolution.
- `docs` resolves `docs/Project.toml`, for `docs/check_docstring_refs.jl`.
- `invalidations` is what the Invalidations workflow loads: ClimaAtmos and
  the SnoopCompile tools, resolved afresh, on Julia 1.10 as in CI.

`ci_log` is a CI test job's log, saved with `gh run view --job <id> --log`.
The resolved versions are compared with the ones it prints, and any that
differ are pinned to CI's. The Julia that runs this script is the one the
environment is for. Run it on a login node, which has network. The job
precompiles on its compute node.

`PINS="ClimaCore=1.0.2,SurfaceFluxes=1.3.0"` pins packages after CI's
versions, to isolate which of several bumped packages breaks a test. The pins
are recorded in `PROVENANCE`.
=#
import Pkg
import TOML

length(ARGS) in 2:4 ||
    error(
        "usage: make_ci_env.jl <checkout> <env_dir> [test|buildkite|docs|invalidations] [ci_log]",
    )
checkout = String(rstrip(abspath(ARGS[1]), '/'))
env_dir = String(rstrip(abspath(ARGS[2]), '/'))
kind = length(ARGS) >= 3 ? ARGS[3] : "test"
ci_log = length(ARGS) == 4 ? abspath(ARGS[4]) : nothing
kind in ("test", "buildkite", "docs", "invalidations") ||
    error("kind must be test, buildkite, docs or invalidations, not $kind")
isfile(joinpath(checkout, "src", "ClimaAtmos.jl")) ||
    error("$checkout is not a checkout of the fork")
ispath(env_dir) && error("$env_dir exists. Remove it or pick another name.")
# A login node is shared. The job precompiles on its own node.
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"

root = TOML.parsefile(joinpath(checkout, "Project.toml"))
if kind == "test"
    # The sandbox `Pkg.test` builds: the package, its dependencies and the
    # test target, under the package's compat.
    extras = get(root, "extras", Dict{String, Any}())
    test_target = get(get(root, "targets", Dict{String, Any}()), "test", String[])
    deps = merge(root["deps"], Dict(name => extras[name] for name in test_target))
    deps["ClimaAtmos"] = root["uuid"]
    compat = filter(((name, _),) -> name == "julia" || haskey(deps, name), root["compat"])
    project = Dict{String, Any}("deps" => deps, "compat" => compat)
elseif kind == "invalidations"
    # The packages julia-invalidations adds to the package's own project.
    deps = Dict(
        "ClimaAtmos" => root["uuid"],
        "SnoopCompile" => "aa65fe97-06da-5843-b5b1-d5d13cad87d2",
        "SnoopCompileCore" => "e2b509da-e806-4183-be48-004708413034",
        "PrettyTables" => "08abe8d2-0d0c-5749-adfa-8a2ac140af0d",
    )
    project = Dict{String, Any}("deps" => deps, "compat" => Dict("SnoopCompile" => "3"))
else
    source = joinpath(checkout, kind == "buildkite" ? ".buildkite" : "docs")
    project = TOML.parsefile(joinpath(source, "Project.toml"))
    # Every path dependency other than ClimaAtmos is CI's own helper. Julia 1.10
    # does not read `[sources]`, so ClimaAtmos's path goes into the manifest
    # through `develop` below.
    sources = pop!(project, "sources", Dict{String, Any}())
    for name in keys(sources), table in ("deps", "compat", "extras")
        name == "ClimaAtmos" || !haskey(project, table) || delete!(project[table], name)
    end
end
mkpath(env_dir)
open(io -> TOML.print(io, project; sorted = true), joinpath(env_dir, "Project.toml"), "w")

if kind == "buildkite"
    manifest = TOML.parsefile(joinpath(source, "Manifest-v1.11.toml"))
    for name in collect(keys(manifest["deps"]))
        name != "ClimaAtmos" && haskey(only(manifest["deps"][name]), "path") &&
            delete!(manifest["deps"], name)
    end
    only(manifest["deps"]["ClimaAtmos"])["path"] = checkout
    open(
        io -> TOML.print(io, manifest; sorted = true),
        joinpath(env_dir, "Manifest.toml"),
        "w",
    )
end

# The terrabyte MPI library, which the machine's setup script records. A job
# on one process runs without it, so a missing file is only reported.
preferences = joinpath(checkout, ".buildkite", "LocalPreferences.toml")
if isfile(preferences)
    cp(preferences, joinpath(env_dir, "LocalPreferences.toml"))
else
    @warn "$preferences is missing. Run `./runscripts/setup-julia-terrabyte.tcsh cpu` for MPI runs."
end

Pkg.activate(env_dir)
# `resolve` reads the depot's registry as it is, and CI's is fresh.
Pkg.Registry.update()
Pkg.develop(Pkg.PackageSpec(path = checkout))
Pkg.resolve()

# CI's versions, from the last occurrence of each `[uuid] Name vX.Y.Z` line.
ci_versions = Dict{String, VersionNumber}()
if ci_log !== nothing
    # `gh` writes the colour codes' escape byte as the two characters `^[`.
    text = replace(read(ci_log, String), r"(\e|\^\[)\[[0-9;]*m" => "")
    # The standard libraries' versions belong to the Julia release, so the log
    # must come from a job on this environment's Julia.
    log_julia = match(r"julia version (\d+\.\d+\.\d+)"i, text)
    log_julia === nothing && error("$ci_log does not name its Julia version")
    VersionNumber(log_julia[1]) == VERSION ||
        error("$ci_log is from Julia $(log_julia[1]), and this is Julia $VERSION")
    for m in
        eachmatch(r"\[[0-9a-f]{8}\] [+~↑↓]? ?([A-Za-z0-9_]+) v([0-9][0-9A-Za-z.+-]*)", text)
        ci_versions[m.captures[1]] = VersionNumber(m.captures[2])
    end
    isempty(ci_versions) && error("no package versions found in $ci_log")
end
resolved() = Dict(
    info.name => info.version for
    info in values(Pkg.dependencies()) if info.version !== nothing
)
differ = [
    Pkg.PackageSpec(name = name, version = ci_versions[name]) for
    (name, version) in resolved() if haskey(ci_versions, name) &&
        name != "ClimaAtmos" && ci_versions[name] != version
]
if !isempty(differ)
    println(
        "pinning to CI's versions: ",
        join(("$(p.name) $(p.version)" for p in differ), ", "),
    )
    Pkg.add(differ; preserve = Pkg.PRESERVE_ALL)
end
pins = [
    Pkg.PackageSpec(name = String(name), version = VersionNumber(version)) for
    (name, version) in
    (split(pin, '=') for pin in split(get(ENV, "PINS", ""), ',', keepempty = false))
]
forced = String[]
if !isempty(pins)
    println("pinning as asked: ", join(("$(p.name) $(p.version)" for p in pins), ", "))
    before = resolved()
    # Every other version stays where it can, so the environment differs from
    # the unpinned one only where a pin forces it.
    try
        Pkg.add(pins; preserve = Pkg.PRESERVE_ALL)
    catch err
        err isa Pkg.Resolve.ResolverError || rethrow()
        @warn "The pins need other packages to move. Retrying without preserving them."
        Pkg.add(pins; preserve = Pkg.PRESERVE_NONE)
    end
    pinned = Set(p.name for p in pins)
    after = resolved()
    forced = sort([
        "$name=$(after[name]) (was $(before[name]))" for
        name in keys(after) if
        haskey(before, name) && !(name in pinned) && after[name] != before[name]
    ])
    isempty(forced) || println("also moved, forced by the pins: ", join(forced, ", "))
end
Pkg.instantiate()

# The packages whose new releases broke CI before.
key_packages = (
    "ClimaCore", "ClimaParams", "ClimaComms", "ClimaTimeSteppers",
    "CloudMicrophysics", "SurfaceFluxes", "Thermodynamics", "ClimaUtilities",
)
versions = resolved()
println("\nenv $env_dir ($kind), Julia $VERSION, checkout $checkout")
for name in key_packages
    haskey(versions, name) || continue
    ci = get(ci_versions, name, nothing)
    note = ci === nothing ? "" : ci == versions[name] ? "  = CI" : "  CI has $ci"
    println(rpad(name, 20), versions[name], note)
end
mismatches = count(
    name -> haskey(ci_versions, name) && ci_versions[name] != versions[name],
    keys(versions),
)
ci_log === nothing || println("packages that differ from the CI log: ", mismatches)
commit = try
    readchomp(`git -C $checkout rev-parse HEAD`)
catch
    "unknown"
end
open(joinpath(env_dir, "PROVENANCE"), "w") do io
    println(io, "checkout $checkout")
    println(io, "commit $commit")
    println(io, "kind $kind")
    println(io, "ci_log ", something(ci_log, "none"))
    println(
        io,
        "pins ",
        isempty(pins) ? "none" : join(("$(p.name)=$(p.version)" for p in pins), ","),
    )
    isempty(forced) || println(io, "forced ", join(forced, ", "))
    println(io, "julia $VERSION")
    println(io, "built $(Libc.strftime("%Y-%m-%dT%H:%M:%S", time()))")
end
