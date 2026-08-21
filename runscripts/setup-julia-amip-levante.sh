#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build the ClimaCoupler AMIP environment on Levante, with this fork of
# ClimaAtmos dev'd into it.
#
#   ./runscripts/setup-julia-amip-levante.sh /path/to/ClimaCoupler.jl
#
# Run on a LOGIN node: compute nodes have no network, so everything must be
# fetched here.
#
# This is a separate depot from the standalone stack. The artifact override that
# repoints OpenMPI_jll at the system MPI is depot-global, and the AMIP
# environment resolves a different package set, so sharing a depot with the
# standalone runs invites version churn between them.
#
# The fork is dev'd in rather than resolved from the registry: it carries the
# stratospheric passive tracers, which upstream ClimaAtmos does not have. It is
# version 0.42.6, which is what the AMIP manifest pins, so the resolve should be
# clean.
# -----------------------------------------------------------------------------

source /sw/etc/profile.levante
set -euo pipefail

COUPLER="${1:?usage: $0 /path/to/ClimaCoupler.jl}"
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
JULIA="${JULIA:-$(command -v julia)}"
JULIA_CHANNEL="${JULIA_CHANNEL:-+1.11}"
export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH:-${HOME}/.julia/depots/levante-amip}"

AMIP_PROJECT="${COUPLER}/experiments/AMIP"
[[ -f "${AMIP_PROJECT}/Project.toml" ]] || {
    echo "ERROR: no AMIP project at ${AMIP_PROJECT}"; exit 1; }
[[ -f "${ROOT}/Project.toml" ]] || { echo "ERROR: no ClimaAtmos at ${ROOT}"; exit 1; }

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0

MPI_LIBDIR="$(mpicc --showme:libdirs | awk '{print $1}')"
MPI_PREFIX="$(dirname "${MPI_LIBDIR}")"
[[ -e "${MPI_LIBDIR}/libmpi.so" ]] || {
    echo "ERROR: no libmpi.so under ${MPI_LIBDIR}"; exit 1; }

echo "Depot:   ${JULIA_DEPOT_PATH}"
echo "Coupler: ${COUPLER}"
echo "Atmos:   ${ROOT}"
echo "MPI:     ${MPI_PREFIX}"
echo

# Repoint OpenMPI_jll at the system MPI, for the same reason as the standalone
# stack: HDF5_jll and NetCDF_jll dlopen their own bundled libmpi otherwise, and
# two incompatible OpenMPI builds in one process fail at load with
# "libopen-pal.so.80: undefined symbol: pmix_framework_names".
mkdir -p "${JULIA_DEPOT_PATH}/artifacts"
cat > "${JULIA_DEPOT_PATH}/artifacts/Overrides.toml" <<TOML
# Written by runscripts/setup-julia-amip-levante.sh
["fe0851c0-eecd-5654-98d4-656369965a5c"]
OpenMPI = "${MPI_PREFIX}"
TOML

export JULIA_NUM_THREADS=1
export OMP_NUM_THREADS=1

export CLIMAATMOS_PATH="${ROOT}"

"${JULIA}" ${JULIA_CHANNEL} --project="${AMIP_PROJECT}" --startup-file=no -e '
    using Pkg
    Pkg.Registry.update()
    Pkg.instantiate(; verbose = true)
    Pkg.develop(path = ENV["CLIMAATMOS_PATH"])
    Pkg.add("MPI")
    Pkg.precompile()
    Pkg.status()
'

"${JULIA}" ${JULIA_CHANNEL} --project="${AMIP_PROJECT}" \
    --startup-file=no -e '
    using MPI, HDF5, ClimaAtmos, ClimaCoupler, Libdl
    implementation, _ = MPI.identify_implementation()
    println("MPI implementation: ", implementation)
    println("parallel HDF5:      ", HDF5.has_parallel())
    println("ClimaAtmos version: ", pkgversion(ClimaAtmos))
    implementation == "OpenMPI" || error("MPI.jl is not using the system OpenMPI")
    HDF5.has_parallel() || error("HDF5 lacks parallel support")
    bad = filter(Libdl.dllist()) do p
        occursin("/artifacts/", p) && occursin(r"libmpi|libopen-pal|libpmix", basename(p))
    end
    isempty(bad) || error("a bundled MPI library is still loaded: " * join(bad, ", "))
    isdefined(ClimaAtmos, :StratosphericPassiveTracers) ||
        error("this ClimaAtmos has no stratospheric passive tracers: the fork was not developed in")
    println("OK")
'

echo
echo "Done. Jobs using this stack must set JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH}."
