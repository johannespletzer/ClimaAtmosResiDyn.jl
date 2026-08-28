#!/bin/tcsh -f

# ============================================================================
# Configure Julia + system MPI for ClimaAtmos on Levante (multi-node capable).
#
#   usage:  ./setup-julia-levante.tcsh cpu
#           ./setup-julia-levante.tcsh gpu
#
# What this does, and why
# -----------------------
# HDF5_jll, NetCDF_jll and TempestRemap_jll all `using OpenMPI_jll`, whose
# __init__ dlopens its own bundled libmpi whatever MPIPreferences says. With a
# system MPI in the process too, two incompatible OpenMPI builds collide:
#
#   libopen-pal.so.80: undefined symbol: pmix_framework_names
#
# HDF5_jll loads either way, so MPIPreferences and an HDF5 libhdf5 preference
# both leave this in place. An artifact override is what fixes it. The depot's
# artifacts/Overrides.toml repoints OpenMPI_jll at the system installation, so
# every JLL that wants OpenMPI gets the one MPI.jl uses. HDF5_jll and NetCDF_jll
# keep their pinned versions, and the system needs no HDF5 or netCDF of its
# own.
#
# Open MPI 4.1.2 is the deliberate choice. It and the artifacts' 5.0.11 both
# expose libmpi.so.40, so the ABI matches and consistency is all that is needed,
# rather than an exact version match. 4.1.2 is the stable module and its PMIx
# 3.2.1 is self-consistent. The experimental 5.0.10 module fails to dlopen under
# JLL loading.
#
# The MPI preference is written directly, in place of
# MPIPreferences.use_system_binary(). That call probes for the library by
# dlopen, and `using MPIPreferences` first resolves whatever MPI is currently
# configured. A second, different libmpi then fails to load, so the probe breaks
# exactly when you are switching away from another MPI.
#
# The gpu stack also pins the CUDA toolkit. CUDA_Runtime_jll picks its artifact
# by asking the driver which CUDA version it supports, and a login node has no
# driver, so the environment resolves to `cuda=none` and the job fails once it
# reaches a GPU node. The version is measured on a GPU node. See
# runscripts/select-cuda-runtime.jl.
#
# All preferences go to .buildkite/LocalPreferences.toml, leaving
# .buildkite/Project.toml alone.
# ============================================================================

set ROOT          = /home/b/b309159/git/ClimaAtmosResiDyn.jl
set PROJECT       = ${ROOT}/.buildkite
set JULIA_BIN     = /home/b/b309159/.juliaup/bin/julia
set JULIA_CHANNEL = +1.11

# OpenMPI_jll's UUID, from .buildkite/Manifest-v1.11.toml
set OPENMPI_JLL_UUID = fe0851c0-eecd-5654-98d4-656369965a5c

# The compiler module, MPI module and depot name for each stack come from
# runscripts/levante_stacks.env, which the GPU runscripts read as well. That
# file states the module and depot pairing once, so every runscript loads the
# same MPI the depot was built against.
set STACKS_ENV = ${ROOT}/runscripts/levante_stacks.env

if (! -r "${STACKS_ENV}") then
    echo "ERROR: stack definitions not found: ${STACKS_ENV}"
    exit 1
endif

# Parent directory for the per-stack depots. Each holds a full copy of the
# packages, artifacts and precompile cache, running to several GB. Under a tight
# $HOME quota, set LEVANTE_DEPOT_ROOT to an absolute path on work or scratch.
if ($?LEVANTE_DEPOT_ROOT) then
    set DEPOT_ROOT = "${LEVANTE_DEPOT_ROOT}"
else
    set DEPOT_REL = `sed -n 's/^LEVANTE_DEPOT_ROOT_RELATIVE_TO_HOME=//p' "${STACKS_ENV}"`
    set DEPOT_ROOT = ${HOME}/${DEPOT_REL}
endif

# ----------------------------------------------------------------------------
# Stack selection
# ----------------------------------------------------------------------------

if ($#argv != 1) then
    echo "usage: $0 [cpu|gpu]"
    exit 1
endif

set STACK = $argv[1]

# SLURM settings for the probe job that reads the GPU driver's CUDA version
# (gpu stack only, and only when it is not already known).
set PROBE_ACCOUNT    = bd1062
set PROBE_PARTITION  = gpu
set PROBE_CONSTRAINT = a100_80

if ("${STACK}" != "cpu" && "${STACK}" != "gpu") then
    echo "ERROR: unknown stack '${STACK}' (expected cpu or gpu)"
    exit 1
endif

# Read this stack's definition out of ${STACKS_ENV}. The keys are prefixed with
# the upper-cased stack name, e.g. LEVANTE_GPU_MPI_MODULE.
set STACK_UC = `echo "${STACK}" | tr '[:lower:]' '[:upper:]'`

set COMPILER_MODULE = `sed -n "s/^LEVANTE_${STACK_UC}_COMPILER_MODULE=//p" "${STACKS_ENV}"`
set MPI_MODULE      = `sed -n "s/^LEVANTE_${STACK_UC}_MPI_MODULE=//p" "${STACKS_ENV}"`
set DEPOT_NAME      = `sed -n "s/^LEVANTE_${STACK_UC}_DEPOT_NAME=//p" "${STACKS_ENV}"`
set SRUN_MPI        = `sed -n "s/^LEVANTE_${STACK_UC}_SRUN_MPI=//p" "${STACKS_ENV}"`

if ("${COMPILER_MODULE}" == "" || "${MPI_MODULE}" == "" || \
    "${DEPOT_NAME}" == "" || "${SRUN_MPI}" == "") then
    echo "ERROR: ${STACKS_ENV} does not define the '${STACK}' stack completely."
    echo "Expected LEVANTE_${STACK_UC}_{COMPILER_MODULE,MPI_MODULE,DEPOT_NAME,SRUN_MPI}."
    exit 1
endif

set DEPOT = ${DEPOT_ROOT}/${DEPOT_NAME}

echo "============================================================"
echo "ClimaAtmos Julia setup on Levante -- ${STACK}"
echo "============================================================"
echo "Repository: ${ROOT}"
echo "Project:    ${PROJECT}"
echo "Julia:      ${JULIA_BIN} ${JULIA_CHANNEL}"
echo "Depot:      ${DEPOT}"
echo "Compiler:   ${COMPILER_MODULE}"
echo "MPI:        ${MPI_MODULE}"
echo

if (! -x "${JULIA_BIN}") then
    echo "ERROR: Julia executable not found: ${JULIA_BIN}"
    exit 1
endif

if (! -f "${PROJECT}/Project.toml") then
    echo "ERROR: Project.toml not found: ${PROJECT}/Project.toml"
    exit 1
endif

# MPIPreferences and CUDA_Runtime_jll both have to be direct dependencies for
# their project-local preferences to be visible. Base.get_preferences maps the
# names in LocalPreferences.toml to UUIDs through the project's own deps, so a
# preference written for an indirect dependency is dropped in silence.
# CUDA_Runtime_jll arrives indirectly through CUDA, so it is listed explicitly.
# Otherwise the toolkit pin below is written, reads back as an empty dictionary,
# and the environment resolves to cuda=none.
#
# Check the dedicated .buildkite environment without resolving the repository
# root environment, whose dependency graph is unrelated here.
#
# The Julia below avoids the exclamation mark on purpose. tcsh performs history
# expansion before quoting, and single quotes leave it in force, so a `!`
# followed by a word character reads as a history reference. Negating
# haskey(...) that way aborts the whole script with "haskey: Event not found."
# before Julia starts, which is why this is a loop rather than a filter. Uses
# like pop!( and != elsewhere in this file are safe, since expansion needs a
# word character to follow.
${JULIA_BIN} ${JULIA_CHANNEL} --startup-file=no \
    -e 'using TOML; project = TOML.parsefile(ARGS[1]); deps = get(project, "deps", Dict()); for name in ARGS[2:end]; haskey(deps, name) || error(name * " is not a direct dependency"); end' \
    "${PROJECT}/Project.toml" MPIPreferences CUDA_Runtime_jll
if ($status != 0) then
    echo "ERROR: MPIPreferences and CUDA_Runtime_jll must both be listed in"
    echo "  ${PROJECT}/Project.toml"
    echo "Their preferences are otherwise written but never read back."
    exit 1
endif

# ----------------------------------------------------------------------------
# Modules. `module purge` is load-bearing here. A stale PMIx left on the library
# path by another Open MPI module breaks the load.
# ----------------------------------------------------------------------------

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

which module >& /dev/null
if ($status != 0) then
    echo "ERROR: the 'module' command is unavailable."
    exit 1
endif

module purge

module load ${COMPILER_MODULE}
if ($status != 0) then
    echo "ERROR: could not load ${COMPILER_MODULE}"
    echo "Run 'module avail gcc nvhpc' and correct COMPILER_MODULE in this script."
    exit 1
endif

module load ${MPI_MODULE}
if ($status != 0) then
    echo "ERROR: could not load ${MPI_MODULE}"
    echo "Run 'module avail openmpi' and correct MPI_MODULE in this script."
    exit 1
endif

echo "Loaded modules:"
module list
echo

# ----------------------------------------------------------------------------
# Discover the system MPI
# ----------------------------------------------------------------------------

which mpicc >& /dev/null
if ($status != 0) then
    echo "ERROR: mpicc unavailable after loading ${MPI_MODULE}."
    exit 1
endif

set MPI_LIBDIRS = ( `mpicc --showme:libdirs` )
if ($#MPI_LIBDIRS < 1) then
    echo "ERROR: mpicc did not report an MPI library directory."
    exit 1
endif

set MPI_LIBDIR  = ${MPI_LIBDIRS[1]}
set MPI_PREFIX  = `dirname "${MPI_LIBDIR}"`
set MPI_LIBRARY = ${MPI_LIBDIR}/libmpi.so

if (! -e "${MPI_LIBRARY}") then
    echo "ERROR: MPI library not found: ${MPI_LIBRARY}"
    exit 1
endif

echo "MPI compiler: `which mpicc`"
mpicc --showme:version
echo "MPI prefix:   ${MPI_PREFIX}"
echo "MPI library:  ${MPI_LIBRARY}"
echo

# Confirm the library loads, which is a stronger check than the file existing.
# The failure happens at dlopen time and is far easier to diagnose here.
${JULIA_BIN} ${JULIA_CHANNEL} --startup-file=no \
    -e 'using Libdl; Libdl.dlopen(ARGS[1]); println("dlopen ok: ", ARGS[1])' "${MPI_LIBRARY}"
if ($status != 0) then
    echo "ERROR: ${MPI_LIBRARY} exists but could not be loaded."
    echo "Check: ldd ${MPI_LIBRARY} | grep 'not found'"
    exit 1
endif

echo "PMIx linkage of the system MPI:"
ldd "${MPI_LIBRARY}" |& grep -E "libpmix|libopen-pal" || true
echo

# ----------------------------------------------------------------------------
# Per-stack depot and the OpenMPI_jll override
# ----------------------------------------------------------------------------

setenv JULIA_DEPOT_PATH "${DEPOT}"
mkdir -p "${DEPOT}/artifacts"

set OVERRIDES = ${DEPOT}/artifacts/Overrides.toml

cat > "${OVERRIDES}" << EOF
# Written by setup-julia-levante.tcsh for the ${STACK} stack.
# Repoints OpenMPI_jll at Levante's system Open MPI so that HDF5_jll,
# NetCDF_jll and TempestRemap_jll load the same MPI as MPI.jl.
["${OPENMPI_JLL_UUID}"]
OpenMPI = "${MPI_PREFIX}"
EOF

echo "Wrote ${OVERRIDES}:"
cat "${OVERRIDES}"
echo

# ----------------------------------------------------------------------------
# Environment
# ----------------------------------------------------------------------------

setenv JULIA_NUM_THREADS 1
setenv OMP_NUM_THREADS 1
setenv OPENBLAS_NUM_THREADS 1
setenv MKL_NUM_THREADS 1

if ($?I_MPI_HYDRA_BOOTSTRAP) unsetenv I_MPI_HYDRA_BOOTSTRAP
if ($?I_MPI_HYDRA_BOOTSTRAP_EXEC_EXTRA_ARGS) unsetenv I_MPI_HYDRA_BOOTSTRAP_EXEC_EXTRA_ARGS
if ($?I_MPI_PMI) unsetenv I_MPI_PMI
if ($?I_MPI_PMI_LIBRARY) unsetenv I_MPI_PMI_LIBRARY

# ----------------------------------------------------------------------------
# Write the MPI preference directly.
#
# The recorded value is the extension-less path, the form MPIPreferences itself
# stores. The loader resolves libmpi.so from it.
# ----------------------------------------------------------------------------

setenv LEVANTE_LIBMPI "${MPI_LIBDIR}/libmpi"
setenv LEVANTE_PREFS "${PROJECT}/LocalPreferences.toml"

# Written as a one-liner instead of a here-document. tcsh handles a quoted
# here-document delimiter (<< 'EOF') unreliably and can write no file at all
# without saying so. Existing blocks such as CUDA_Runtime_jll are preserved.
${JULIA_BIN} ${JULIA_CHANNEL} --startup-file=no -e 'using TOML; pf = ENV["LEVANTE_PREFS"]; prefs = isfile(pf) ? TOML.parsefile(pf) : Dict{String,Any}(); prefs["MPIPreferences"] = Dict{String,Any}("_format" => "1.0", "abi" => "OpenMPI", "binary" => "system", "cclibs" => String[], "libmpi" => ENV["LEVANTE_LIBMPI"], "mpiexec" => "srun", "preloads" => String[]); open(io -> TOML.print(io, prefs), pf, "w"); println("wrote MPI preferences to ", pf)'
if ($status != 0) then
    echo "ERROR: could not write MPI preferences."
    exit 1
endif

echo
echo "LocalPreferences.toml:"
cat "${LEVANTE_PREFS}"
echo

# ----------------------------------------------------------------------------
# CUDA toolkit version (gpu stack only)
#
# Determined before anything slow runs, so a missing version fails at once
# instead of after a full precompilation. Sources, in order:
#
#   1. $CUDA_RUNTIME_VERSION, if set. A manual override, e.g. 13.0
#   2. nvidia-smi, when this script is itself running on a GPU node
#   3. the value recorded by the last GPU job (see levante_gpu_common.sh)
#   4. a two-minute probe job on the gpu partition
#
# Anything measured is cached in ${CUDA_VERSION_CACHE}. Delete that file to
# force a fresh measurement.
# ----------------------------------------------------------------------------

set CUDA_VERSION_CACHE = ${DEPOT}/levante-cuda-version
set CUDA_VERSION       = ""
set CUDA_VERSION_SRC   = ""
set CUDA_VERSION_NEW   = 0

# The pipelines below turn nvidia-smi's "CUDA Version    : 13.0" into a bare
# "13.0". Each use site spells it out, because tcsh's `eval` keeps a pipeline's
# stdin unreliably and a shared filter variable has nothing to read from.

if ("${STACK}" == "gpu") then
    if ($?CUDA_RUNTIME_VERSION) then
        set CUDA_VERSION     = "${CUDA_RUNTIME_VERSION}"
        set CUDA_VERSION_SRC = "the CUDA_RUNTIME_VERSION environment variable"
    endif

    if ("${CUDA_VERSION}" == "") then
        which nvidia-smi >& /dev/null
        if ($status == 0) then
            set CUDA_VERSION = "`nvidia-smi -q |& grep -m1 -i 'CUDA Version' | sed 's/.*: *//' | tr -d '[:space:]'`"
            if ("${CUDA_VERSION}" != "") then
                set CUDA_VERSION_SRC = "nvidia-smi on this node"
                set CUDA_VERSION_NEW = 1
            endif
        endif
    endif

    if ("${CUDA_VERSION}" == "") then
        if (-r "${CUDA_VERSION_CACHE}") then
            set CUDA_VERSION = "`cat ${CUDA_VERSION_CACHE} | tr -d '[:space:]'`"
            if ("${CUDA_VERSION}" != "") then
                set CUDA_VERSION_SRC = "${CUDA_VERSION_CACHE} (recorded by an earlier GPU job)"
            endif
        endif
    endif

    if ("${CUDA_VERSION}" == "") then
        echo "No CUDA version on record; probing a GPU node (this queues a short job):"
        set CUDA_VERSION = "`srun --account=${PROBE_ACCOUNT} --partition=${PROBE_PARTITION} --constraint=${PROBE_CONSTRAINT} --nodes=1 --ntasks=1 --gpus-per-task=1 --cpus-per-task=1 --mem=4G --time=00:02:00 nvidia-smi -q |& grep -m1 -i 'CUDA Version' | sed 's/.*: *//' | tr -d '[:space:]'`"
        if ("${CUDA_VERSION}" != "") then
            set CUDA_VERSION_SRC = "a probe job on the ${PROBE_PARTITION} partition"
            set CUDA_VERSION_NEW = 1
        endif
    endif

    if ("${CUDA_VERSION}" !~ [0-9]*.[0-9]*) then
        echo "ERROR: could not determine the CUDA version supported by the GPU driver."
        echo "Run 'nvidia-smi' on a GPU node, read the 'CUDA Version' field, and"
        echo "re-run this script with it, e.g.:"
        echo "  env CUDA_RUNTIME_VERSION=13.0 $0 gpu"
        exit 1
    endif

    if (${CUDA_VERSION_NEW} == 1) then
        echo "${CUDA_VERSION}" > "${CUDA_VERSION_CACHE}"
    endif

    echo "GPU driver supports CUDA ${CUDA_VERSION} (from ${CUDA_VERSION_SRC})"
    echo
endif

# ----------------------------------------------------------------------------
# Instantiate into this depot
# ----------------------------------------------------------------------------

echo "Instantiating (slow on a fresh depot):"
${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
    -e 'using Pkg; Pkg.instantiate()'
if ($status != 0) then
    echo "ERROR: instantiation failed."
    exit 1
endif

# ----------------------------------------------------------------------------
# Pin the CUDA toolkit
#
# This runs after the first instantiate, because select-cuda-runtime.jl reads
# the list of installable toolkits out of the installed CUDA_Runtime_jll. It
# runs before precompilation, because the preference is a compile-time one and
# setting it later would invalidate every cache just written. The second
# instantiate downloads the newly selected toolkit, so nothing is left to fetch
# lazily at run time, which matters because compute nodes have no network.
#
# The cpu stack clears the pin instead. LocalPreferences.toml is shared, and a
# leftover pin would have the cpu depot download a toolkit it never uses.
# ----------------------------------------------------------------------------

if ("${STACK}" == "gpu") then
    echo
    ${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
        "${ROOT}/runscripts/select-cuda-runtime.jl" "${CUDA_VERSION}"
    if ($status != 0) then
        echo "ERROR: could not pin the CUDA toolkit version."
        exit 1
    endif

    echo "Instantiating again to fetch the CUDA ${CUDA_VERSION} artifacts:"
    ${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
        -e 'using Pkg; Pkg.instantiate()'
    if ($status != 0) then
        echo "ERROR: could not install the CUDA toolkit artifacts."
        exit 1
    endif
else
    # Drop the entire CUDA preference table. This clears an empty
    # [CUDA_Runtime_jll] table too, should one be present.
    ${JULIA_BIN} ${JULIA_CHANNEL} --startup-file=no \
        -e 'using TOML; pf = ENV["LEVANTE_PREFS"]; prefs = isfile(pf) ? TOML.parsefile(pf) : Dict{String,Any}(); pop!(prefs, "CUDA_Runtime_jll", nothing); open(io -> TOML.print(io, prefs), pf, "w"); println("cleared CUDA runtime preferences from ", pf)'
    if ($status != 0) then
        echo "ERROR: could not clear the CUDA toolkit pin."
        exit 1
    endif
endif

# ----------------------------------------------------------------------------
# Precompile
# ----------------------------------------------------------------------------

echo
echo "Precompiling (slow on a fresh depot):"
${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
    -e 'using Pkg; Pkg.precompile()'
if ($status != 0) then
    echo "ERROR: precompilation failed."
    exit 1
endif

# ----------------------------------------------------------------------------
# Verification
#
# NCDatasets is loaded on purpose. NetCDF_jll depends on both HDF5_jll and
# OpenMPI_jll, so a bundled MPI can enter through NetCDF while MPI.jl and
# HDF5.jl both look clean.
# ----------------------------------------------------------------------------

echo
echo "============================================================"
echo "Verification"
echo "============================================================"

${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
    -e 'using MPI, HDF5, NCDatasets, Libdl; MPI.versioninfo(); println("parallel HDF5: ", HDF5.has_parallel()); libs = filter(p -> occursin(r"libmpi|libopen-pal|libpmix|libhdf5|libnetcdf", basename(p)), Libdl.dllist()); println("loaded MPI/HDF5/NetCDF libraries:"); foreach(p -> println("  ", p), libs); HDF5.has_parallel() || error("HDF5 lacks parallel support"); bad = filter(p -> occursin("/artifacts/", p) && occursin(r"libmpi|libopen-pal|libpmix", basename(p)), libs); isempty(bad) || error("a bundled MPI library is still loaded: " * join(bad, ", "))'

if ($status != 0) then
    echo
    echo "ERROR: verification failed."
    echo
    echo "If MPI.versioninfo reports a binary other than system, the"
    echo "preference was not picked up. Confirm that MPIPreferences is a"
    echo "direct dependency of ${PROJECT} and re-run this script."
    echo
    echo "If a bundled MPI library is still loaded, the override did not take"
    echo "effect -- check the UUID and the OpenMPI key in:"
    echo "  ${OVERRIDES}"
    exit 1
endif

# Login nodes have no GPU, so the toolkit stays unexercised here. The failure
# this guards against shows up anyway: a platform tag of "none" means Pkg
# installed no toolkit at all. The tag is read through CUDA.jl, which imports
# the JLL that resists loading by name. Expect CUDA.jl to warn about a missing
# driver.
if ("${STACK}" == "gpu") then
    echo
    ${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
        -e 'using CUDA, TOML; pf = ENV["LEVANTE_PREFS"]; prefs = isfile(pf) ? TOML.parsefile(pf) : Dict{String,Any}(); version = get(get(prefs, "CUDA_Runtime_jll", Dict{String,Any}()), "version", "<unset>"); tag = CUDA.CUDA_Runtime_jll.host_platform["cuda"]; println("CUDA version preference: ", version); println("CUDA platform tag:       ", tag); version == "<unset>" && error("CUDA toolkit version preference is unset"); tag == "none" && error("no CUDA toolkit installed")'
    if ($status != 0) then
        echo
        echo "ERROR: no CUDA toolkit was installed for this depot."
        echo "The environment resolved to 'cuda=none', so CUDA.jl will not find a"
        echo "runtime on the GPU node. Re-run with an explicit version:"
        echo "  env CUDA_RUNTIME_VERSION=<major.minor> $0 gpu"
        exit 1
    endif
endif

echo
echo "============================================================"
echo "Setup complete for the ${STACK} stack."
echo
echo "Jobs using this stack must set:"
echo "  setenv JULIA_DEPOT_PATH ${DEPOT}"
echo "  module purge"
echo "  module load ${COMPILER_MODULE}"
echo "  module load ${MPI_MODULE}"
echo "  srun --mpi=${SRUN_MPI} ..."
echo
echo "NOTE: .buildkite/LocalPreferences.toml is shared by both stacks, so"
echo "re-run this script when switching between cpu and gpu."
if ("${STACK}" == "gpu") then
    echo
    echo "The CUDA toolkit is pinned for a driver supporting CUDA ${CUDA_VERSION}."
    echo "The GPU runscripts re-check that against the node they land on and"
    echo "refresh ${CUDA_VERSION_CACHE}, so after a driver upgrade it is enough"
    echo "to re-run this script -- no version needs to be entered by hand."
endif
echo "============================================================"
