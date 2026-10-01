#!/usr/bin/env bash
#
# The G3 baselines' probes (design/G3_BASELINE_RERUN.md): runs
# `analysis/water/w25_probes.jl` on CONFIG once per entry of PROBES
# (fixed_parent, refinement), in that order, in one job. Submit it through
# g3base_submit.sh with KIND=probe, which sets PROJECT (the run tree's
# .buildkite), MODEL_COMMIT, MODEL_TREE and RECORD_COMMIT. TRIALS, T_END, T0,
# INTERVAL, VARIANTS and NREF pass through to the probe from the environment.
# Each probe writes to $OUTDIR/<probe>/ (default
# $SCRATCH/tag_closure/output/g3base_probes), with its log and a provenance
# file beside its CSV.
set -uo pipefail

: "${CONFIG:?}" "${PROJECT:?}" "${PROBES:?}"
REC="${SLURM_SUBMIT_DIR:?submit through g3base_submit.sh}"
SCRIPT_JL="${REC}/experiments/tag_closure/analysis/water/w25_probes.jl"
OUT_ROOT="${OUTDIR:-${SCRATCH}/tag_closure/output/g3base_probes}"
RUNCFG="$(basename "${CONFIG}" .yml)"
WORK="${SCRATCH}/tag_closure/g3base_probe_work/${RUNCFG}"
mkdir -p "${WORK}"
cd "${WORK}"

unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH="${SCRATCH}/julia-depots/terrabyte-cpu"
export JULIA_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export CLIMACOMMS_DEVICE=CPU CLIMACOMMS_CONTEXT=SINGLETON
JULIA="${JULIA:-$(command -v julia)}"

overall=0
for probe in ${PROBES//,/ }; do
    out="${OUT_ROOT}/${probe}"
    mkdir -p "${out}"
    started="$(date --iso-8601=seconds)"
    echo "probe ${probe} on ${RUNCFG}: model ${MODEL_COMMIT:-unknown}, record ${RECORD_COMMIT:-unknown}"
    PROBE="${probe}" OUTDIR="${out}" CONFIG="${CONFIG}" \
        "${JULIA}" +1.11 --project="${PROJECT}" --startup-file=no "${SCRIPT_JL}" \
        2>&1 | tee "${out}/${RUNCFG}.log"
    status=${PIPESTATUS[0]}
    {
        echo "run: ${RUNCFG}"
        echo "probe: ${probe}"
        echo "config: ${CONFIG}"
        echo "script: ${SCRIPT_JL}"
        echo "model_commit: ${MODEL_COMMIT:-unknown}"
        echo "model_tree: ${MODEL_TREE:-unknown}"
        echo "record_commit: ${RECORD_COMMIT:-unknown}"
        echo "project: ${PROJECT}"
        echo "trials: ${TRIALS:-default}"
        echo "julia: $("${JULIA}" +1.11 --startup-file=no -e 'print(VERSION)' 2>/dev/null)"
        echo "slurm_job_id: ${SLURM_JOB_ID:-none}"
        echo "nodelist: ${SLURM_JOB_NODELIST:-$(hostname)}"
        echo "started: ${started}"
        echo "finished: $(date --iso-8601=seconds)"
        echo "exit_status: ${status}"
        [[ -z "${MANIFEST_PATH:-}" ]] || echo "manifest_path: ${MANIFEST_PATH}"
    } > "${out}/${RUNCFG}_provenance.txt"
    [[ "${status}" -eq 0 ]] || overall="${status}"
done
exit "${overall}"
