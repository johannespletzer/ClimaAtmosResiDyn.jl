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
# __init__ dlopens its OWN bundled libmpi regardless of MPIPreferences. With a
# system MPI also in the process, two incompatible OpenMPI builds collide:
#
#   libopen-pal.so.80: undefined symbol: pmix_framework_names
#
# Neither MPIPreferences nor an HDF5 libhdf5 preference can fix that, because
# HDF5_jll is loaded either way. The fix is an artifact override: the depot's
# artifacts/Overrides.toml repoints OpenMPI_jll at the system installation, so
# every JLL that wants OpenMPI gets the one MPI.jl uses. HDF5_jll and
# NetCDF_jll keep their pinned versions -- no system HDF5/netCDF needed.
#
# Open MPI 4.1.2 is used deliberately. Both 4.1.2 and the artifacts' 5.0.11
# expose libmpi.so.40, so the MPI ABI matches and no version match is required
# -- only a *consistent* MPI. 4.1.2 is the stable module and its PMIx 3.2.1 is
# self-consistent; the experimental 5.0.10 module fails to dlopen under JLL
# loading.
#
# The MPI preference is written directly rather than through
# MPIPreferences.use_system_binary(). That call probes for the library by
# dlopen, but `using MPIPreferences` first resolves whatever MPI is currently
# configured, and a second, different libmpi then cannot be loaded -- so the
# probe fails precisely when you are switching away from another MPI.
#
# The gpu stack additionally pins the CUDA toolkit: CUDA_Runtime_jll picks its
# artifact by asking the driver which CUDA version it supports, and a login node
# has no driver, so the environment resolves to `cuda=none` and the job fails
# only once it reaches a GPU node. The version is measured on a GPU node -- see
# runscripts/select-cuda-runtime.jl.
#
# All preferences go to .buildkite/LocalPreferences.toml; no packages are added
# to .buildkite/Project.toml.
# ============================================================================

set ROOT          = /home/b/b309159/git/ClimaAtmosResiDyn.jl
set PROJECT       = ${ROOT}/.buildkite
set JULIA_BIN     = /home/b/b309159/.juliaup/bin/julia
set JULIA_CHANNEL = +1.11

# OpenMPI_jll's UUID, from .buildkite/Manifest-v1.11.toml
set OPENMPI_JLL_UUID = fe0851c0-eecd-5654-98d4-656369965a5c

# Parent directory for the per-stack depots. Each holds a full copy of the
# packages, artifacts and precompile cache -- several GB per stack. If $HOME is
# quota-limited, point this at a work or scratch filesystem instead.
set DEPOT_ROOT = ${HOME}/.julia/depots

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

if ("${STACK}" == "cpu") then
    set COMPILER_MODULE = gcc/11.2.0-gcc-11.2.0
    set MPI_MODULE      = openmpi/4.1.2-gcc-11.2.0
    set DEPOT           = ${DEPOT_ROOT}/levante-cpu
    set SRUN_MPI        = pmix_v3
else if ("${STACK}" == "gpu") then
    set COMPILER_MODULE = nvhpc/24.7-gcc-11.2.0
    set MPI_MODULE      = openmpi/4.1.5-nvhpc-24.7
    set DEPOT           = ${DEPOT_ROOT}/levante-gpu
    set SRUN_MPI        = pmix_v3
else
    echo "ERROR: unknown stack '${STACK}' (expected cpu or gpu)"
    exit 1
endif

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

# ----------------------------------------------------------------------------
# Modules. `module purge` is mandatory, not hygiene: a stale PMIx left on the
# library path by another Open MPI module breaks the load.
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

# Confirm the library actually LOADS, not merely that the file exists: the
# failure mode is at dlopen time, and it is far easier to diagnose here.
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
# The recorded value is the extension-less path, which is the form
# MPIPreferences itself stores; the loader resolves libmpi.so from it.
# ----------------------------------------------------------------------------

setenv LEVANTE_LIBMPI "${MPI_LIBDIR}/libmpi"
setenv LEVANTE_PREFS "${PROJECT}/LocalPreferences.toml"

# Written as a one-liner rather than a here-document: tcsh does not reliably
# handle a quoted here-document delimiter (<< 'EOF') and silently writes no
# file. Existing blocks (e.g. CUDA_Runtime_jll) are preserved.
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
# Determined before anything slow runs, so a missing version fails immediately
# rather than after a full precompilation. Sources, in order:
#
#   1. $CUDA_RUNTIME_VERSION, if set -- manual override, e.g. 13.0
#   2. nvidia-smi, if this script is itself running on a GPU node
#   3. the value recorded by the last GPU job (see runscripts/xmodel.gpu*)
#   4. a two-minute probe job on the gpu partition
#
# Anything measured is cached in ${CUDA_VERSION_CACHE}; delete that file to
# force a fresh measurement.
# ----------------------------------------------------------------------------

set CUDA_VERSION_CACHE = ${DEPOT}/levante-cuda-version
set CUDA_VERSION       = ""
set CUDA_VERSION_SRC   = ""
set CUDA_VERSION_NEW   = 0

# The pipelines below turn nvidia-smi's "CUDA Version    : 13.0" into a bare
# "13.0". Spelled out at each use site because tcsh's `eval` does not reliably
# keep a pipeline's stdin, so a shared filter variable cannot be piped into.

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
# After the first instantiate, because select-cuda-runtime.jl reads the list of
# installable toolkits out of the installed CUDA_Runtime_jll; before
# precompilation, because the preference is a compile-time one and setting it
# later would invalidate every cache just written. The second instantiate
# downloads the newly selected toolkit -- compute nodes have no network, so
# nothing may be left to fetch lazily at run time.
#
# The cpu stack clears the pin instead: LocalPreferences.toml is shared, and a
# leftover pin would make the cpu depot download a toolkit it never uses.
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
    # Deleting a preference is set_preferences! with `missing`. The (UUID, name)
    # tuple is required because CUDA_Runtime_jll is an [extras] entry, so it
    # cannot be resolved by name -- see runscripts/select-cuda-runtime.jl.
    ${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
        -e 'using Preferences; jll = (Base.UUID("76a88914-d11a-5bdc-97e0-2f5a05c973a2"), "CUDA_Runtime_jll"); set_preferences!(jll, "version" => missing, "local" => missing; force = true)'
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
# NCDatasets is loaded deliberately: NetCDF_jll depends on both HDF5_jll and
# OpenMPI_jll, so a bundled MPI can enter through NetCDF even when MPI.jl and
# HDF5.jl look clean.
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
    echo "If MPI.versioninfo reports a binary other than 'system', the"
    echo "preference was not picked up. Add MPIPreferences as a direct"
    echo "dependency and re-run this script:"
    echo "  ${JULIA_BIN} ${JULIA_CHANNEL} --project=${PROJECT} -e 'using Pkg; Pkg.add(\"MPIPreferences\")'"
    echo
    echo "If a bundled MPI library is still loaded, the override did not take"
    echo "effect -- check the UUID and the 'OpenMPI' key in:"
    echo "  ${OVERRIDES}"
    exit 1
endif

# A CUDA toolkit cannot be exercised here -- login nodes have no GPU -- but the
# failure this guards against is visible without one: a platform tag of "none"
# means Pkg installed no toolkit at all. The tag is read through CUDA.jl, which
# imports the JLL that cannot be loaded by name. CUDA.jl warning about a missing
# driver here is expected.
if ("${STACK}" == "gpu") then
    echo
    ${JULIA_BIN} ${JULIA_CHANNEL} --project="${PROJECT}" --startup-file=no \
        -e 'using CUDA, Preferences; jll = Base.UUID("76a88914-d11a-5bdc-97e0-2f5a05c973a2"); tag = CUDA.CUDA_Runtime_jll.host_platform["cuda"]; println("CUDA version preference: ", something(load_preference(jll, "version"), "<unset>")); println("CUDA platform tag:       ", tag); tag == "none" && error("no CUDA toolkit installed")'
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
