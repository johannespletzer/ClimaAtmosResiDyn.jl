# Pin CUDA_Runtime_jll to the CUDA toolkit that matches the GPU nodes' driver.
#
#   usage: julia --project=.buildkite runscripts/select-cuda-runtime.jl 13.0
#
# The argument is the driver's CUDA version -- what `nvidia-smi` reports as
# "CUDA Version" -- measured on a GPU node by setup-julia-levante.tcsh.
#
# CUDA_Runtime_jll picks its artifact through a Pkg platform-augmentation hook
# that dlopens libcuda and asks the driver which CUDA version it supports. A
# login node has no driver, so the hook tags the platform `cuda=none` and
# installs no toolkit; nothing fails until the job reaches a GPU node. Setting
# the `version` preference short-circuits that probe, which the hook supports
# deliberately: it queries the driver only "when there's no override, to support
# precompiling with a fixed version without having the driver available".
#
# The toolkit pinned is the newest one no newer than the driver. Staying at or
# below it avoids leaning on CUDA's minor-version compatibility, which the
# CUDA-aware MPI in the nvhpc stack does not always tolerate.
#
# Preferences are written with Julia's TOML stdlib so this machine-specific
# setup does not require Preferences.jl as a direct .buildkite dependency.

using TOML

const CUDA_RUNTIME_JLL =
    (Base.UUID("76a88914-d11a-5bdc-97e0-2f5a05c973a2"), "CUDA_Runtime_jll")

# Both the preference and the augmentation hook compare toolkits at major.minor.
minor_version(v::VersionNumber) = VersionNumber(v.major, v.minor)
major_minor(v::VersionNumber) = "$(v.major).$(v.minor)"

"""
    available_toolkits()

CUDA toolkit versions `CUDA_Runtime_jll` can install, read from the Pkg
platform-augmentation hook that ships with the installed package. The list grows
with every CUDA release, so reading it beats a hardcoded copy that would drift.

Returns an empty vector when the list cannot be located.
"""
function available_toolkits()
    src = Base.locate_package(Base.PkgId(CUDA_RUNTIME_JLL...))
    isnothing(src) && return VersionNumber[]
    hook = joinpath(dirname(dirname(src)), ".pkg", "platform_augmentation.jl")
    isfile(hook) || return VersionNumber[]
    list = match(r"cuda_toolkits\s*=\s*VersionNumber\[(.*?)\]"s, read(hook, String))
    isnothing(list) && return VersionNumber[]
    return [VersionNumber(m[1]) for m in eachmatch(r"v\"([\d.]+)\"", list[1])]
end

"""
    select_toolkit(driver)

Newest installable CUDA toolkit that is no newer than `driver`.
"""
function select_toolkit(driver::VersionNumber)
    toolkits = unique(minor_version.(available_toolkits()))
    if isempty(toolkits)
        @warn "Could not read the CUDA toolkit list; using the driver version."
        return minor_version(driver)
    end
    usable = filter(<=(minor_version(driver)), toolkits)
    isempty(usable) && error(
        "no CUDA toolkit shipped by CUDA_Runtime_jll is old enough for a CUDA " *
        "$(major_minor(driver)) driver " *
        "(available: $(join(major_minor.(toolkits), ", ")))",
    )
    return maximum(usable)
end

length(ARGS) == 1 || error("usage: select-cuda-runtime.jl <driver-cuda-version>")

driver = minor_version(VersionNumber(ARGS[1]))
version = major_minor(select_toolkit(driver))

prefs_file = joinpath(dirname(Base.active_project()), "LocalPreferences.toml")
prefs = isfile(prefs_file) ? TOML.parsefile(prefs_file) : Dict{String, Any}()
cuda_prefs = get!(prefs, "CUDA_Runtime_jll", Dict{String, Any}())
cuda_prefs["version"] = version
cuda_prefs["local"] = false

open(prefs_file, "w") do io
    TOML.print(io, prefs)
end

println(
    "Pinned CUDA_Runtime_jll to CUDA $version ",
    "(driver reports CUDA $(major_minor(driver))).",
)
