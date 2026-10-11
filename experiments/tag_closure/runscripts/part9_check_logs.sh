#!/usr/bin/env bash
#
# Part 9, PR B: the six checks on the runs of part9_checks.sh, run on a login
# node after the jobs finished. No Slurm. Writes `<check>.log` and
# `<check>.cmd` per gate check under OUT, which
# water_tag_application_proof.py reads. Exit 0 only when all six pass.
#
# Since the amendment of 2026-10-11 (design section 12) the weights check
# runs on the precipitating column's on run for final_map and implicit, and
# on the TRMM on run for implicit alone, both into one log. The Newton check
# runs on the column's Newton run. The TRMM Newton run is recorded, not
# checked: it has no post-Newton map to check. Since section 13 the restart
# check runs on the column's restart pair. The model restarts the TRMM case
# inexactly (FINDINGS E54), so the TRMM pair and the off run's restart, the
# control, go to `record_*.log` for PART9.md and not into the gate.
#
#   OUT=<new dir> experiments/tag_closure/runscripts/part9_check_logs.sh
#
# Each run's manifest is $SCRATCH/tag_closure/manifests/<job>*.json, the one
# g3base_submit.sh wrote. The converter checks the receipt's model identity
# against the manifest's `model` entry, the run tree.
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
cdir() { echo "${runs}/p9_col1m_$1_1h/output_0000"; }
# The Slurm job's manifest, `<job>.<job id>.json`. A dry run's
# `<job>.<timestamp>.json` sorts after it and is never taken.
manifest() {
    ls "${SCRATCH}/tag_closure/manifests/$1".*.json | grep -E '\.[0-9]+\.json$' | sort -V | tail -n 1
}

python3 "${E}/water_tag_applications_convert.py" "$(dir on)" --out "${OUT}/converted_on" \
    --manifest "$(manifest p9_trmm0m_on_6h)"
for run in on newton restarted; do
    python3 "${E}/water_tag_applications_convert.py" "$(cdir ${run})" --out "${OUT}/converted_col1m_${run}" \
        --manifest "$(manifest p9_col1m_${run}_1h)"
done

status=0
check() {
    local key=$1
    shift
    echo "python3 ${E}/water_tag_application_checks.py $*" >"${OUT}/${key}.cmd"
    python3 "${E}/water_tag_application_checks.py" "$@" >"${OUT}/${key}.log" || status=1
    head -n 2 "${OUT}/${key}.log"
}
check accepted_weights accepted_weights "${OUT}/converted_col1m_on" --ode-algo ARS222 --roles final_map,implicit
# The TRMM on run fires the implicit role alone. Its result goes into the same
# log, and the gate passes the check only when every named result is PASS.
echo "python3 ${E}/water_tag_application_checks.py accepted_weights ${OUT}/converted_on --ode-algo ARS222 --roles implicit" \
    >>"${OUT}/accepted_weights.cmd"
python3 "${E}/water_tag_application_checks.py" accepted_weights "${OUT}/converted_on" --ode-algo ARS222 \
    --roles implicit >>"${OUT}/accepted_weights.log" || status=1
tail -n 2 "${OUT}/accepted_weights.log"
check trial_rollback trial_rollback "${OUT}/converted_on" --dt 150
check newton_replacement newton_replacement "${OUT}/converted_col1m_newton" --expect-post-newton
check complete_active_roster complete_active_roster "${OUT}/converted_on"
check parent_bitwise_parity parent_bitwise_parity "$(dir on)" "$(dir off)"
# The Float32 pair (owner, 2026-10-10) adds its result to the same log. The
# gate passes the check only when every named result is PASS.
echo "python3 ${E}/water_tag_application_checks.py parent_bitwise_parity $(dir on_f32) $(dir off_f32)" \
    >>"${OUT}/parent_bitwise_parity.cmd"
python3 "${E}/water_tag_application_checks.py" parent_bitwise_parity "$(dir on_f32)" "$(dir off_f32)" \
    >>"${OUT}/parent_bitwise_parity.log" || status=1
tail -n 2 "${OUT}/parent_bitwise_parity.log"
check all_channel_checkpoint_restart restart "$(cdir on)" "$(cdir restarted)"

# Recorded, not gated: the TRMM restart pair under the producer's check, the
# model's own restart of the on and the off run (the control), and the model's
# own restart of the column. A FAIL here does not change the exit status.
record() {
    local key=$1
    shift
    echo "python3 ${E}/water_tag_application_checks.py $*" >"${OUT}/record_${key}.cmd"
    python3 "${E}/water_tag_application_checks.py" "$@" >"${OUT}/record_${key}.log" || true
    head -n 2 "${OUT}/record_${key}.log"
}
record trmm_restart restart "$(dir on)" "$(dir restarted)"
record trmm_model_restart model_restart "$(dir on)" "$(dir restarted)" --t0 10800
record trmm_off_model_restart model_restart "$(dir off)" "$(dir off_restarted)" --t0 10800
record col1m_model_restart model_restart "$(cdir on)" "$(cdir restarted)" --t0 1800
exit "${status}"
