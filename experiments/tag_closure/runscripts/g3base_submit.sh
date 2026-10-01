#!/usr/bin/env bash
#
# The G3 baselines on the new physics (design/G3_BASELINE_RERUN.md). Submits
# one job whose model comes from a clean detached run tree at main, while the
# driver, the config and the runscripts come from this record tree. Both trees
# must be clean, the run tree must be at EXPECT_SHA, and the record's commit
# must be on a remote branch, so a job always names two pushed commits.
#
#   RUN_TREE=../ClimaAtmosResiDyn-g3base-run \
#   CONFIG=experiments/tag_closure/configs/<run>.yml \
#       [KIND=run|probe|check] [PROBES=fixed_parent,refinement] [TRIALS=1,2,3,4] \
#       experiments/tag_closure/runscripts/g3base_submit.sh [--dry-run] \
#           --account=pn49go-c --partition=hpda2_compute --time=02:00:00 \
#           --cpus-per-task=2 --mem=48G --job-name=<name> \
#           --output=<log>/%x-%j.out --error=<log>/%x-%j.err
#
# KIND=run (the default) submits phase_c.sh with the D4-W driver, as W50 did.
# KIND=probe submits g3base_probe.sh, which runs w25_probes.jl once per entry
# of PROBES. KIND=check submits g3base_check.sh. Every other argument goes to
# sbatch through submit_g3.sh, which stamps the manifest.
set -euo pipefail

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${RUN_TREE:?set RUN_TREE to the detached run tree}"
: "${CONFIG:?set CONFIG}"
RUN_TREE="$(cd "${RUN_TREE}" && pwd)"
EXPECT_SHA="${EXPECT_SHA:-b34bbd8b81483d1b5b52890cea2b7cada774ee9a}"
KIND="${KIND:-run}"

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
export DRIVER="${REC}/experiments/tag_closure/analysis/water/d4w_driver.jl"
case "${KIND}" in
    run) export SCRIPT="${REC}/experiments/tag_closure/runscripts/phase_c.sh" ;;
    probe) export SCRIPT="${REC}/experiments/tag_closure/runscripts/g3base_probe.sh" ;;
    check) export SCRIPT="${REC}/experiments/tag_closure/runscripts/g3base_check.sh" ;;
    *)
        echo "ERROR: KIND must be run, probe or check, not ${KIND}." >&2
        exit 1
        ;;
esac
echo "model ${RUN_SHA} (${RUN_TREE}), record ${REC_SHA}, kind ${KIND}"
exec "${REC}/experiments/tag_closure/runscripts/submit_g3.sh" "$@"
