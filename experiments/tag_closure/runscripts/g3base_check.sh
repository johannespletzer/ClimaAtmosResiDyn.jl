#!/usr/bin/env bash
#
# The G3 baselines' check job (design/G3_BASELINE_RERUN.md, "The check job").
# Before the real jobs it runs, in one job and on the run tree's model, short
# copies of the configs that carry the most risk on the new code: each config
# in CHECK_RUNS (comma-separated paths) with the D4-W driver, then the two
# probes on CHECK_PROBE_CONFIG with short windows. The check configs live
# outside both trees, under $SCRATCH/claude_work/g3base/check/, each with its
# own job_id, so nothing a real run writes is touched. Submit it through
# g3base_submit.sh with KIND=check and CONFIG set to any one of the check
# configs (submit_g3.sh names the manifest after it).
set -uo pipefail

: "${PROJECT:?}" "${DRIVER:?}" "${CHECK_RUNS:?}" "${CHECK_PROBE_CONFIG:?}"
REC="${SLURM_SUBMIT_DIR:?submit through g3base_submit.sh}"
CHECK_OUT="${CHECK_OUT:-${SCRATCH}/tag_closure/output/g3base_check}"
mkdir -p "${CHECK_OUT}"

unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH="${SCRATCH}/julia-depots/terrabyte-cpu"
export JULIA_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export CLIMACOMMS_DEVICE=CPU CLIMACOMMS_CONTEXT=SINGLETON
JULIA="${JULIA:-$(command -v julia)}"
echo "check: model ${MODEL_COMMIT:-unknown} (${MODEL_TREE:-unknown}), record ${RECORD_COMMIT:-unknown}"

overall=0
cd "${SCRATCH}/tag_closure"
for config in ${CHECK_RUNS//,/ }; do
    name="$(basename "${config}" .yml)"
    echo "=== driver run ${name} ($(date --iso-8601=seconds))"
    CONFIG="${config}" "${JULIA}" +1.11 --project="${PROJECT}" --startup-file=no \
        "${DRIVER}" 2>&1 | tee "${CHECK_OUT}/${name}.log"
    status=${PIPESTATUS[0]}
    echo "RESULT check=${name} exit=${status}"
    [[ "${status}" -eq 0 ]] || overall="${status}"
done

work="${SCRATCH}/tag_closure/g3base_probe_work/check"
mkdir -p "${work}"
cd "${work}"
name="$(basename "${CHECK_PROBE_CONFIG}" .yml)"
for probe in fixed_parent refinement; do
    echo "=== probe ${probe} on ${name} ($(date --iso-8601=seconds))"
    PROBE="${probe}" OUTDIR="${CHECK_OUT}/${probe}" CONFIG="${CHECK_PROBE_CONFIG}" \
        TRIALS=1,2 T_END=20mins T0=20mins INTERVAL=10mins VARIANTS=120:1,60:1 \
        "${JULIA}" +1.11 --project="${PROJECT}" --startup-file=no \
        "${REC}/experiments/tag_closure/analysis/water/w25_probes.jl" 2>&1 |
        tee "${CHECK_OUT}/${name}_${probe}.log"
    status=${PIPESTATUS[0]}
    echo "RESULT check=${name} probe=${probe} exit=${status}"
    [[ "${status}" -eq 0 ]] || overall="${status}"
done
echo "check finished $(date --iso-8601=seconds), exit ${overall}"
exit "${overall}"
