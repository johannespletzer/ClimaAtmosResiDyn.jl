#!/usr/bin/env bash
#
# Part 9, PR B: the six checks on the four runs of part9_checks.sh, run on a
# login node after the jobs finished. No Slurm. Writes `<check>.log` and
# `<check>.cmd` per gate check under OUT, which
# water_tag_application_proof.py reads. Exit 0 only when all six pass.
#
#   OUT=<new dir> experiments/tag_closure/runscripts/part9_check_logs.sh
#
# Each run's manifest is $SCRATCH/tag_closure/manifests/<job>*.json, the one
# g3base_submit.sh wrote. The converter checks the receipt's model identity
# against it.
set -euo pipefail
source "${MODULESHOME}/init/bash"
module load python/3.12

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
E="${REC}/experiments/tag_closure/analysis/evidence"
: "${OUT:?set OUT to a new directory}"
[[ -e "${OUT}" ]] && { echo "ERROR: ${OUT} exists." >&2; exit 4; }
mkdir -p "${OUT}"
runs="${SCRATCH:?}/tag_closure/output"
dir() { echo "${runs}/p9_trmm0m_$1_6h/output_0000"; }
# The Slurm job's manifest, `<job>.<job id>.json`. A dry run's
# `<job>.<timestamp>.json` sorts after it and is never taken.
manifest() {
    ls "${SCRATCH}/tag_closure/manifests/p9_trmm0m_$1_6h".*.json | grep -E '\.[0-9]+\.json$' | sort -V | tail -n 1
}

for run in on newton; do
    python3 -I "${E}/water_tag_applications_convert.py" "$(dir ${run})" --out "${OUT}/converted_${run}" \
        --manifest "$(manifest ${run})"
done

status=0
check() {
    local key=$1
    shift
    echo "python3 -I ${E}/water_tag_application_checks.py $*" >"${OUT}/${key}.cmd"
    python3 -I "${E}/water_tag_application_checks.py" "$@" >"${OUT}/${key}.log" || status=1
    head -n 2 "${OUT}/${key}.log"
}
check accepted_weights accepted_weights "${OUT}/converted_on" --ode-algo ARS222 --roles final_map,implicit
check trial_rollback trial_rollback "${OUT}/converted_on" --dt 150
check newton_replacement newton_replacement "${OUT}/converted_newton" --expect-post-newton
check complete_active_roster complete_active_roster "${OUT}/converted_on"
check parent_bitwise_parity parent_bitwise_parity "$(dir on)" "$(dir off)"
# The Float32 pair (owner, 2026-10-10) adds its result to the same log. The
# gate passes the check only when every named result is PASS.
echo "python3 -I ${E}/water_tag_application_checks.py parent_bitwise_parity $(dir on_f32) $(dir off_f32)" \
    >>"${OUT}/parent_bitwise_parity.cmd"
python3 -I "${E}/water_tag_application_checks.py" parent_bitwise_parity "$(dir on_f32)" "$(dir off_f32)" \
    >>"${OUT}/parent_bitwise_parity.log" || status=1
tail -n 2 "${OUT}/parent_bitwise_parity.log"
check all_channel_checkpoint_restart restart "$(dir on)" "$(dir restarted)"
exit "${status}"
