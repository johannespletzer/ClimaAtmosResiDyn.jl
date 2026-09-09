#!/usr/bin/env bash
#SBATCH --job-name=tag-closure-b
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=tag-closure-b-%j.out
#SBATCH --error=tag-closure-b-%j.err
#SBATCH --mail-type=FAIL

# Phase B, the energy runs.
#
# One script for the whole phase. The run is chosen by the configuration, which
# travels in the environment, so this serves every b run in the register:
#
#     CONFIG=experiments/tag_closure/configs/b1_base.yml \
#         sbatch experiments/tag_closure/runscripts/phase_b.sh
#
# sbatch exports the submitting environment, so CONFIG reaches the body below
# and the body hands it to the driver. Submit from the repository root.
#
# Sized for ten days of a coarse sphere on one task. Provisional: the
# resolution and the length of B1, and whether it runs here or on one GPU, are
# still open questions for the owner. Revisit the wall time and the memory once
# that is settled, and once phase A has shown what a sphere costs on this
# partition. Override without editing:
#
#     CONFIG=... sbatch --time=24:00:00 --mem=128G \
#         experiments/tag_closure/runscripts/phase_b.sh
#
# The #SBATCH block above follows runscripts/run_test_as_job.sh: the bd1062
# account and the shared partition. Everything below the block is shared with
# the other phases; see tag_closure_common.sh, which also explains why these are
# bash and that script is not.

SCRIPT_NAME="phase_b.sh"

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
