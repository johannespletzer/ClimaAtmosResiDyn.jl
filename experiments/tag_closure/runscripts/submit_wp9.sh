#!/usr/bin/env bash
#
# V-W10 (WP9): submit every arm of the cost measurement, one node each. Run it
# on the login node, from anywhere:
#
#   RUN_TREE=<detached tree at main 43b01ca1> REC_TREE=<record worktree> \
#       experiments/tag_closure/runscripts/submit_wp9.sh [--dry-run] [arm ...]
#
# It checks that both trees are clean and that the record commit is on the
# remote, reads their commits, and submits `wp9_cost.sh` once per arm. The arms
# are those of design/WP9_COST.md, section 3. Naming arms submits only those.
# Job ids go to stdout, one per line, as `arm jobid`.

set -euo pipefail
: "${RUN_TREE:?set RUN_TREE}" "${REC_TREE:?set REC_TREE}"
DRY=0
ARMS=()
for a in "$@"; do
    if [[ "${a}" == "--dry-run" ]]; then DRY=1; else ARMS+=("${a}"); fi
done

for tree in "${RUN_TREE}" "${REC_TREE}"; do
    [[ -z "$(git -C "${tree}" status --porcelain --untracked-files=no)" ]] || {
        echo "ERROR: ${tree} has uncommitted changes." >&2; exit 1; }
done
RUN_SHA="$(git -C "${RUN_TREE}" rev-parse HEAD)"
REC_SHA="$(git -C "${REC_TREE}" rev-parse HEAD)"
[[ "${RUN_SHA}" == 43b01ca1d* ]] || [[ -n "${ALLOW_OTHER_MODEL_COMMIT:-}" ]] || {
    echo "ERROR: the model tree is at ${RUN_SHA}, not 43b01ca1." >&2; exit 1; }
git -C "${REC_TREE}" fetch -q origin
git -C "${REC_TREE}" branch -r --contains "${REC_SHA}" | grep -q . || {
    echo "ERROR: ${REC_SHA} is not on any remote branch. Push the record branch." >&2; exit 1; }

# arm  family mode precip base points mem time
TABLE=(
  "water_default water default 0 wp9_water_trmm0m_edmf 0,2,4,8,8:ledgers,8:tracer,8:increment 64G 12:00:00"
  "water_default_32 water default 0 wp9_water_trmm0m_edmf 32 200G 05:00:00"
  "water_copies water copies 0 wp9_water_trmm0m_edmf 2,4,8,8:ledgers 64G 12:00:00"
  "water_1m_off water default 0 wp9_water_1m_column 0,2,4,8,32 64G 12:00:00"
  "water_1m_on water default 1 wp9_water_1m_column 2,4,8,32 64G 12:00:00"
  "energy_default energy default 0 wp9_energy_d4_edmf 0,2,4,8,8:ledgers,8:records 64G 12:00:00"
  "energy_default_32 energy default 0 wp9_energy_d4_edmf 32 200G 05:00:00"
  "energy_copies energy copies 0 wp9_energy_d4_edmf 2,4,8,8:ledgers 64G 12:00:00"
  "energy_copies_32 energy copies 0 wp9_energy_d4_edmf 32 200G 05:00:00"
)
# The account is pn49go-c from 2026-10-01 (hpda-c before). ACCOUNT overrides it.
# EXCLUSIVE=1 takes the whole node for each job, and sends the results to
# output/wp9_cost_excl (design/WP9_COST.md, amendment of 2026-09-29).
EXTRA=()
OUT_ROOT="${OUT_ROOT:-wp9_cost}"
if [[ "${EXCLUSIVE:-0}" == 1 ]]; then
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_cost_excl
fi
# PROFILE=1 submits the P2/P3 profile of design/WP9_COST.md section 8 instead:
# its own arms, the profile driver, whole nodes, results in output/wp9_profile.
if [[ "${PROFILE:-0}" == 1 ]]; then
    TABLE=(
      "prof_water_edmf water default 0 wp9_water_trmm0m_edmf 2,32 200G 03:00:00"
      "prof_energy_edmf energy default 0 wp9_energy_d4_edmf 2,32 200G 04:00:00"
      "prof_water_1m_on water default 1 wp9_water_1m_column 2,8 200G 03:00:00"
    )
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_profile
    export DRIVER_NAME=wp9_profile_driver.jl BUILD_LIMIT="${BUILD_LIMIT:-90m}"
fi
export OUT_ROOT
LOGS="${SCRATCH:?}/tag_closure/logs/${OUT_ROOT}"
mkdir -p "${LOGS}"
for row in "${TABLE[@]}"; do
    read -r arm family mode precip base points mem time <<<"${row}"
    if (( ${#ARMS[@]} )); then
        [[ " ${ARMS[*]} " == *" ${arm} "* ]] || continue
    fi
    points="${points//,/ }"
    cmd=(sbatch --parsable --account="${ACCOUNT:-pn49go-c}" --partition=hpda2_compute --nodes=1 --ntasks=1
         --cpus-per-task=4 --mem="${mem}" ${EXTRA[@]+"${EXTRA[@]}"} --time="${time}" -J "wp9${EXTRA[@]+x}_${arm}"
         -o "${LOGS}/%x-%j.out" "${REC_TREE}/experiments/tag_closure/runscripts/wp9_cost.sh")
    if (( DRY )); then
        echo "[dry run] ARM=${arm} FAMILY=${family} MODE=${mode} PRECIP=${precip} BASE=${base} POINTS='${points}' ${cmd[*]}"
        continue
    fi
    id="$(RUN_TREE="${RUN_TREE}" REC_TREE="${REC_TREE}" RUN_SHA="${RUN_SHA}" REC_SHA="${REC_SHA}" \
        ARM="${arm}" FAMILY="${family}" MODE="${mode}" PRECIP="${precip}" BASE="${base}" \
        POINTS="${points}" "${cmd[@]}")"
    echo "${arm} ${id}"
done
