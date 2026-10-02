#!/usr/bin/env bash
#
# W59, criterion 3 on two MPI ranks (design/MPI_PARITY.md). Submits one run
# whose model comes from a clean detached run tree at main d3c5e42f, while the
# driver, the config and the runscripts come from this record tree. Both trees
# must be clean, the run tree must be at EXPECT_SHA, and the record's commit
# must be on a remote branch, so a job always names two pushed commits.
# g3base_submit.sh with the plain driver, run_tag_closure.jl, which does not
# touch the state before the solve.
#
#   RUN_TREE=../ClimaAtmosResiDyn-mpi-run \
#   CONFIG=experiments/tag_closure/configs/w59_mpi_<mode>_r<ranks>.yml \
#       experiments/tag_closure/runscripts/mpi_submit.sh [--dry-run] \
#           --account=pn49go-c --partition=hpda2_compute --ntasks=<ranks> \
#           --cpus-per-task=1 --time=06:00:00 --mem=64G --job-name=<name> \
#           --output=<log>/%x-%j.out --error=<log>/%x-%j.err
#
# phase_c.sh launches the ranks with srun when --ntasks is above 1, and sets
# CLIMACOMMS_CONTEXT=MPI. Every other argument goes to sbatch through
# submit_g3.sh, which stamps the manifest.

set -euo pipefail

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${RUN_TREE:?set RUN_TREE to the detached run tree}"
: "${CONFIG:?set CONFIG}"
RUN_TREE="$(cd "${RUN_TREE}" && pwd)"
EXPECT_SHA="${EXPECT_SHA:-d3c5e42f54515729f53216ae6b8ba268bea8262f}"

for tree in "${RUN_TREE}" "${REC}"; do
    if [[ -n "$(git -C "${tree}" status --porcelain --untracked-files=no)" ]]; then
        echo "ERROR: ${tree} has uncommitted changes." >&2
        exit 1
    fi
done
RUN_SHA="$(git -C "${RUN_TREE}" rev-parse HEAD)"
if [[ "${RUN_SHA}" != "${EXPECT_SHA}" ]]; then
    echo "ERROR: the run tree is at ${RUN_SHA}, not ${EXPECT_SHA}." >&2
    exit 1
fi
if [[ ! -f "${RUN_TREE}/.buildkite/LocalPreferences.toml" ]]; then
    echo "ERROR: ${RUN_TREE} has no .buildkite/LocalPreferences.toml." >&2
    exit 1
fi
REC_SHA="$(git -C "${REC}" rev-parse HEAD)"
git -C "${REC}" fetch -q origin
if ! git -C "${REC}" branch -r --contains "${REC_SHA}" | grep -q .; then
    echo "ERROR: ${REC_SHA} is on no remote branch. Push the record first." >&2
    exit 1
fi

export PROJECT="${RUN_TREE}/.buildkite"
export MODEL_COMMIT="${RUN_SHA}" MODEL_TREE="${RUN_TREE}" RECORD_COMMIT="${REC_SHA}"
export DRIVER="${REC}/experiments/tag_closure/run_tag_closure.jl"
export SCRIPT="${REC}/experiments/tag_closure/runscripts/phase_c.sh"
echo "model ${RUN_SHA} (${RUN_TREE}), record ${REC_SHA}"
exec "${REC}/experiments/tag_closure/runscripts/submit_g3.sh" "$@"
