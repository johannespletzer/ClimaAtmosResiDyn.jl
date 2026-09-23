#!/usr/bin/env bash
#
# G3 WP0, "the manifest in this session's submit path" (review S9). Stamps
# a manifest.py record of the login node's worktree, config and environment,
# then submits the run, so the manifest and the run it describes are tied
# together instead of the manifest being a separate, easily orphaned step.
#
#   CONFIG=experiments/tag_closure/configs/<run>.yml \
#       [DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl] \
#       [SCRIPT=experiments/tag_closure/runscripts/phase_c.sh] \
#       experiments/tag_closure/runscripts/submit_g3.sh [--dry-run] \
#           --account=hpda-c --partition=hpda2_test --time=02:00:00 \
#           --cpus-per-task=2 --mem=48G \
#           --output=/dss/.../logs/%x-%j.out --error=/dss/.../logs/%x-%j.err
#
# CONFIG is required, matching every other entry point in this series. Every
# other argument on the command line is passed straight through to sbatch
# untouched; give --account, --partition and the rest exactly as README.md's
# "Submitting a run" documents them, since this wrapper does not second-guess
# them. SCRIPT is the runscript to submit; it defaults to phase_c.sh, which
# has served every run since phase C.
#
# --dry-run writes the manifest and prints the sbatch line it would run,
# without calling sbatch. Use it to check the command and inspect the
# manifest before spending a queue slot; it needs no Slurm access at all.
#
# Where the manifest goes, and why it is not renamed in place: the manifest
# is written to $SCRATCH/tag_closure/manifests/<job_id>.<timestamp>.json
# *before* submission, and that exact path is exported to the job as
# MANIFEST_PATH, which tag_closure_common.sh copies into
# output_XXXX/manifest.json and records in provenance.txt. sbatch bakes the
# exported environment into the job at submission time; a job may sit queued
# for hours (README.md, "An MPI run looks stuck"), so nothing after
# submission can change what path the job will look for. Renaming the file
# after sbatch returns its job id would leave that path pointing at nothing.
# So the manifest keeps its timestamped name, and a symlink
# <job_id>.<slurm_id>.json -> <job_id>.<timestamp>.json is added next to it
# purely for a human to find the manifest by Slurm job id; the job itself
# never looks at the symlink.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

if [[ -z "${CONFIG:-}" ]]; then
    echo "ERROR: CONFIG is not set, so there is no run to do." >&2
    echo "See the header of $(basename "${BASH_SOURCE[0]}") for the usage." >&2
    exit 1
fi

# Resolve CONFIG the same way tag_closure_common.sh does: repository-relative
# path or absolute, checked from the repository root.
if [[ -f "${CONFIG}" ]]; then
    CONFIG="$(cd "$(dirname "${CONFIG}")" && pwd)/$(basename "${CONFIG}")"
elif [[ -f "${ROOT}/${CONFIG}" ]]; then
    CONFIG="${ROOT}/${CONFIG}"
else
    echo "ERROR: configuration file not found: ${CONFIG}" >&2
    exit 1
fi

DRY_RUN=0
SBATCH_ARGS=()
for arg in "$@"; do
    if [[ "${arg}" == "--dry-run" ]]; then
        DRY_RUN=1
    else
        SBATCH_ARGS+=("${arg}")
    fi
done

SCRIPT="${SCRIPT:-${ROOT}/experiments/tag_closure/runscripts/phase_c.sh}"
[[ "${SCRIPT}" == /* ]] || SCRIPT="${ROOT}/${SCRIPT}"
if [[ ! -f "${SCRIPT}" ]]; then
    echo "ERROR: runscript not found: ${SCRIPT}" >&2
    exit 1
fi

MANIFEST_DIR="${MANIFEST_DIR:-${SCRATCH:?SCRATCH is not set}/tag_closure/manifests}"
mkdir -p "${MANIFEST_DIR}"

# job_id, read the same way tag_closure_common.sh reads it, purely to name
# the manifest file after the run it belongs to.
job_id_line="$(grep -m 1 '^job_id:' "${CONFIG}" || true)"
JOB_ID="${job_id_line#job_id:}"
JOB_ID="${JOB_ID//[\"\' ]/}"
JOB_ID="${JOB_ID%$'\r'}"
if [[ -z "${JOB_ID}" ]]; then
    echo "ERROR: no job_id in ${CONFIG}." >&2
    exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MANIFEST_PATH="${MANIFEST_DIR}/${JOB_ID}.${STAMP}.json"

# python/3.12 for manifest.py; bare python3 here is 3.6. Load only if 'git
# diff' etc. below need it -- actually manifest.py itself needs it. Load
# quietly and do not fail if some other python is already on PATH and works;
# manifest.py needs only the stdlib, so this is a convenience, not a
# requirement enforced here.
if [[ -n "${MODULESHOME:-}" ]]; then
    # shellcheck disable=SC1091
    source "${MODULESHOME}/init/bash" 2>/dev/null || true
    module load python/3.12 >/dev/null 2>&1 || true
fi

SUBMIT_LINE="env CONFIG=${CONFIG}${DRIVER:+ DRIVER=${DRIVER}} MANIFEST_PATH=${MANIFEST_PATH} sbatch ${SBATCH_ARGS[*]:-} ${SCRIPT}"

python3 "${ROOT}/experiments/tag_closure/analysis/evidence/manifest.py" \
    --repo "${ROOT}" --config "${CONFIG}" \
    ${DRIVER:+--driver "${DRIVER}"} \
    --command "${SUBMIT_LINE}" \
    --out "${MANIFEST_PATH}"

echo "manifest: ${MANIFEST_PATH}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry run] would submit:"
    echo "  ${SUBMIT_LINE}"
    exit 0
fi

submit_output="$(env CONFIG="${CONFIG}" ${DRIVER:+DRIVER="${DRIVER}"} MANIFEST_PATH="${MANIFEST_PATH}" \
    sbatch "${SBATCH_ARGS[@]}" "${SCRIPT}")"
echo "${submit_output}"

slurm_id="$(sed -n 's/^Submitted batch job \([0-9]*\).*/\1/p' <<<"${submit_output}")"
if [[ -z "${slurm_id}" ]]; then
    echo "WARNING: could not parse the Slurm job id from sbatch's output." >&2
    echo "The manifest stays at ${MANIFEST_PATH}; nothing else to do." >&2
    exit 0
fi

# A human-readable pointer by job id. Not a rename -- see the header.
LOOKUP_LINK="${MANIFEST_DIR}/${JOB_ID}.${slurm_id}.json"
ln -sf "$(basename "${MANIFEST_PATH}")" "${LOOKUP_LINK}"

echo "job:               ${slurm_id}"
echo "manifest:          ${MANIFEST_PATH}"
echo "manifest (by job): ${LOOKUP_LINK}"
