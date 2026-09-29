#!/usr/bin/env bash
#
# V-W10 (WP9): one arm of the cost measurement, one Julia process per point.
# The arm is a family, a mode and a base config, and its points are tag counts
# with an optional variant. Points run in turn on one node, smallest first, so
# that a point that does not build in time costs the points after it nothing
# they had.
#
#   Use submit_wp9.sh. It sets RUN_TREE, REC_TREE, RUN_SHA and REC_SHA:
#   RUN_TREE=<detached tree at the model commit> \
#   REC_TREE=<record worktree at the pushed record commit> \
#   FAMILY=water|energy MODE=default|copies PRECIP=0|1 \
#   BASE=wp9_water_trmm0m_edmf POINTS="0 2 4 8 8:ledgers" ARM=<name> \
#       sbatch --account=hpda-c --partition=hpda2_compute --nodes=1 --ntasks=1 \
#              --cpus-per-task=4 --mem=<..> --time=<..> \
#              experiments/tag_closure/runscripts/wp9_cost.sh
#
# The model, its Julia environment and its LocalPreferences come from RUN_TREE.
# The driver and the configs come from REC_TREE. Both must be clean, and the
# script records both commits. BUILD_LIMIT (default 4 h) is what "builds in
# time" means: a point that has not finished its steps by then is stopped, and
# the status file says so. See design/WP9_COST.md.
#
# Results go to $SCRATCH/tag_closure/output/wp9_cost/<ARM>/: one CSV per point,
# the log of each point, and status.csv with each point's exit status.

set -euo pipefail

for v in RUN_TREE REC_TREE RUN_SHA REC_SHA FAMILY MODE BASE POINTS ARM; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: set $v." >&2; exit 1; }
done
PRECIP="${PRECIP:-0}"
BUILD_LIMIT="${BUILD_LIMIT:-4h}"

# A batch node has no git. submit_wp9.sh reads both commits and checks that both
# trees are clean on the login node, and hands the commits on in RUN_SHA and
# REC_SHA. The trees must not change between submission and start.
export MODEL_COMMIT="${RUN_SHA}"
[[ -f "${RUN_TREE}/.buildkite/LocalPreferences.toml" ]] || {
    echo "ERROR: ${RUN_TREE} has no .buildkite/LocalPreferences.toml." >&2
    exit 1
}
CONFIG_FILE="${REC_TREE}/experiments/tag_closure/configs/${BASE}.yml"
DRIVER="${REC_TREE}/experiments/tag_closure/analysis/wp9_cost_driver.jl"
[[ -f "${CONFIG_FILE}" ]] || { echo "ERROR: ${CONFIG_FILE} not found." >&2; exit 1; }
[[ -f "${DRIVER}" ]] || { echo "ERROR: ${DRIVER} not found." >&2; exit 1; }

type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
unset JULIA_LOAD_PATH JULIA_PROJECT
export JULIA_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export CLIMACOMMS_DEVICE=CPU CLIMACOMMS_CONTEXT=SINGLETON
JULIA="${JULIA:-${HOME}/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia}"
[[ -x "${JULIA}" ]] || { echo "ERROR: ${JULIA} not found." >&2; exit 1; }

OUT="${SCRATCH:?SCRATCH is not set}/tag_closure/output/wp9_cost/${ARM}"
mkdir -p "${OUT}"
STATUS="${OUT}/status.csv"
[[ -f "${STATUS}" ]] || echo "point,ntags,variant,exit_status,seconds,slurm_job" > "${STATUS}"

echo "arm ${ARM}: family ${FAMILY} mode ${MODE} precip ${PRECIP} base ${BASE}"
echo "model ${RUN_TREE} at ${RUN_SHA}"
echo "record ${REC_TREE} at ${REC_SHA}"
echo "host $(hostname), slurm job ${SLURM_JOB_ID:-none}, start $(date -Is)"
echo "julia $("${JULIA}" --version), build limit ${BUILD_LIMIT}"

cd "${OUT}"
for point in ${POINTS}; do
    n="${point%%:*}"
    variant="none"
    [[ "${point}" == *:* ]] && variant="${point#*:}"
    log="${OUT}/${point//:/_}.log"
    [[ -f "${log}" ]] && { echo "ERROR: ${log} exists. Not overwriting." >&2; exit 1; }
    echo "== point ${point} start $(date -Is)"
    start=$SECONDS
    set +e
    FAMILY="${FAMILY}" MODE="${MODE}" PRECIP="${PRECIP}" NTAGS="${n}" VARIANT="${variant}" \
        OUTDIR="${OUT}" \
        timeout "${BUILD_LIMIT}" "${JULIA}" --startup-file=no \
        --project="${RUN_TREE}/.buildkite" "${DRIVER}" "${CONFIG_FILE}" \
        > "${log}" 2>&1
    status=$?
    set -e
    echo "${point},${n},${variant},${status},$((SECONDS - start)),${SLURM_JOB_ID:-none}" >> "${STATUS}"
    echo "== point ${point} exit ${status} after $((SECONDS - start)) s"
done
echo "end $(date -Is)"
