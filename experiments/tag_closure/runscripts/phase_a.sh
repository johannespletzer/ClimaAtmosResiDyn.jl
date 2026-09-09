#!/usr/bin/env bash
#SBATCH --job-name=tag-closure-a
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --output=tag-closure-a-%j.out
#SBATCH --error=tag-closure-a-%j.err
#SBATCH --mail-type=FAIL

# Phase A, the water runs.
#
# One script for the whole phase. The run is chosen by the configuration, which
# travels in the environment, so this serves every a run in the register:
#
#     CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
#         sbatch experiments/tag_closure/runscripts/phase_a.sh
#
# sbatch exports the submitting environment, so CONFIG reaches the body below
# and the body hands it to the driver. Submit from the repository root.
#
# Sized for the DYCOMS column, which is one column of 30 levels and needs a
# task and a few cores. Thirteen runs use it. a5_sphere_limiter is the one
# sphere in phase A and the one that may not fit: if a day of a coarse moist
# sphere overruns the wall time here, submit it against phase_b.sh instead, or
# against runscripts/xmodel.1gpu with SCRIPT set to the driver. That is a cost
# decision for the owner, and the plan leaves it open.
#
# The #SBATCH block above follows runscripts/run_test_as_job.sh: the bd1062
# account and the shared partition. Everything below the block is shared with
# the other phases; see tag_closure_common.sh, which also explains why these are
# bash and that script is not.

SCRIPT_NAME="phase_a.sh"

# ---------------------------------------------------------------------------
# Locate the repository, then hand over to the shared body.
#
# This has to happen here rather than in the shared file, because sbatch copies
# this script to the node's spool directory before running it: ${BASH_SOURCE[0]}
# is then /var/spool/slurmd/job<id>/slurm_script and its directory holds nothing
# of ours. SLURM_SUBMIT_DIR, the directory sbatch was invoked from, is the
# repository root for the documented submit line. A candidate counts only once
# the shared file is found in it, so a wrong guess fails here with an actionable
# message. runscripts/xmodel.1gpu locates itself the same way and for the same
# reason.
# ---------------------------------------------------------------------------

SHARED="experiments/tag_closure/runscripts/tag_closure_common.sh"

for _candidate in \
    "${ROOT:-}" \
    "${SLURM_SUBMIT_DIR:-}" \
    "${SLURM_SUBMIT_DIR:+${SLURM_SUBMIT_DIR}/..}" \
    "${SLURM_SUBMIT_DIR:+${SLURM_SUBMIT_DIR}/../..}" \
    "$(dirname "${BASH_SOURCE[0]}")/../../.."
do
    if [[ -n "${_candidate}" && -r "${_candidate}/${SHARED}" ]]; then
        ROOT="$(cd "${_candidate}" && pwd)"
        break
    fi
done
unset _candidate

if [[ -z "${ROOT:-}" || ! -r "${ROOT}/${SHARED}" ]]; then
    echo "ERROR: could not locate the repository." >&2
    echo "  SLURM_SUBMIT_DIR=${SLURM_SUBMIT_DIR:-unset}" >&2
    echo "Submit from the repository root:" >&2
    echo "  CONFIG=experiments/tag_closure/configs/<run>.yml \\" >&2
    echo "      sbatch experiments/tag_closure/runscripts/${SCRIPT_NAME}" >&2
    echo "or pass it explicitly:" >&2
    echo "  ROOT=/path/to/ClimaAtmosResiDyn.jl CONFIG=... sbatch ..." >&2
    exit 1
fi

export ROOT

# shellcheck source=tag_closure_common.sh
source "${ROOT}/${SHARED}"
