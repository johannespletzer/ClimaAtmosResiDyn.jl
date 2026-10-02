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
# SET=b34 submits the rerun of the amendment of 2026-10-02 (design section 9) at
# main b34bbd8b: every arm runs its own untagged point 0 first, 50 warm-up steps,
# whole nodes. SET=b34check submits its short check jobs to hpda2_test.
PARTITION=hpda2_compute
EXPECT_SHA=43b01ca1d
if [[ "${SET:-}" == b34 || "${SET:-}" == b34check || "${SET:-}" == b34d ]]; then
    EXPECT_SHA=b34bbd8b8
    export WP9_WARMUP=50
    TABLE=(
      "water_default water default 0 wp9_water_trmm0m_edmf 0,2,4,8,8:ledgers,8:tracer,8:increment 200G 08:00:00"
      "water_default_32 water default 0 wp9_water_trmm0m_edmf 0,32 200G 04:00:00"
      "water_copies water copies 0 wp9_water_trmm0m_edmf 0,2,4,8,8:ledgers 200G 08:00:00"
      "water_1m_off water default 0 wp9_water_1m_column 0,2,4,8,32 200G 08:00:00"
      "water_1m_on water default 1 wp9_water_1m_column 0,2,4,8,32 200G 10:00:00"
      "energy_default energy default 0 wp9_energy_d4_edmf 0,2,4,8,8:ledgers,8:records 200G 12:00:00"
      "energy_default_32 energy default 0 wp9_energy_d4_edmf 0,32 200G 06:00:00"
      "energy_copies energy copies 0 wp9_energy_d4_edmf 0,2,4,8,8:ledgers 200G 12:00:00"
      "both_default both default 0 wp9_energy_d4_edmf 0,8,8:ledgers 200G 08:00:00"
    )
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_cost_b34
    if [[ "${SET}" == b34check ]]; then
        export WP9_WARMUP=1 WP9_STEPS=3 WP9_REPEATS=2
        TABLE=(
          "check_water_copies water copies 0 wp9_water_trmm0m_edmf 0,2 64G 02:00:00"
          "check_both both default 0 wp9_energy_d4_edmf 0,8 64G 02:00:00"
          "check_water_1m_on water default 1 wp9_water_1m_column 2 64G 02:00:00"
        )
        EXTRA=()
        PARTITION=hpda2_test
        OUT_ROOT=wp9_check_b34
    fi
fi
# SET=b34d submits the rerun of the amendment of 2026-10-02, section 10: the
# arms of section 9 at b34bbd8b, 6 timed blocks of which the first is
# discarded, and energy copies at 32 tags with an 8 h build limit. A row's
# ninth field, when present, is that arm's build limit.
if [[ "${SET:-}" == b34d ]]; then
    EXPECT_SHA=b34bbd8b8
    export WP9_WARMUP=50 WP9_REPEATS=6
    TABLE+=("energy_copies_32 energy copies 0 wp9_energy_d4_edmf 0,32 200G 10:00:00 8h")
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_cost_b34d
fi
# SET=d3c5 submits the 8 + 8 point of the amendment of 2026-10-02 (evening),
# section 11, at main d3c5e42f: the combined arm and each half of it alone, on
# D4, with section 10's warm-up and blocks.
if [[ "${SET:-}" == d3c5 ]]; then
    EXPECT_SHA=d3c5e42f5
    export WP9_WARMUP=50 WP9_REPEATS=6
    TABLE=(
      "both_d3c5 both default 0 wp9_energy_d4_edmf 0,8,8:ledgers 200G 04:00:00"
      "water_d4 water default 0 wp9_energy_d4_edmf 0,8,8:ledgers 200G 04:00:00"
      "energy_d4 energy default 0 wp9_energy_d4_edmf 0,8,8:ledgers 200G 04:00:00"
    )
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_cost_d3c5
fi
# Section 12 (2026-10-02, late), at main d3c5e42f. SET=prof88 submits the
# profile of the 8 + 8 point and its halves, all four points on one node, in
# two jobs on two nodes. SET=copies88 submits OD3's copies row: 8 water and 8
# energy tags in copies mode in one model, with a 5 h point limit, so that a
# build of up to 4 h is still followed by its timed steps.
if [[ "${SET:-}" == prof88 ]]; then
    EXPECT_SHA=d3c5e42f5
    export WP9_WARMUP=50 WP9_PROFILE_SECONDS=20 DRIVER_NAME=wp9_profile_driver.jl BUILD_LIMIT=90m
    TABLE=(
      "prof88_a both default 0 wp9_energy_d4_edmf 0,8@water,8@energy,8@both 200G 06:00:00"
      "prof88_b both default 0 wp9_energy_d4_edmf 0,8@water,8@energy,8@both 200G 06:00:00"
    )
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_profile_d3c5
elif [[ "${SET:-}" == copies88 ]]; then
    EXPECT_SHA=d3c5e42f5
    export WP9_WARMUP=50 WP9_REPEATS=6
    TABLE=(
      "copies88 both copies 0 wp9_energy_d4_edmf 0,8 200G 06:00:00 5h"
    )
    EXTRA=(--exclusive)
    OUT_ROOT=wp9_copies_d3c5
fi
export OUT_ROOT
[[ "${RUN_SHA}" == "${EXPECT_SHA}"* ]] || [[ -n "${ALLOW_OTHER_MODEL_COMMIT:-}" ]] || {
    echo "ERROR: the model tree is at ${RUN_SHA}, not ${EXPECT_SHA}." >&2; exit 1; }
LOGS="${SCRATCH:?}/tag_closure/logs/${OUT_ROOT}"
mkdir -p "${LOGS}"
for row in "${TABLE[@]}"; do
    read -r arm family mode precip base points mem time blimit <<<"${row}"
    if (( ${#ARMS[@]} )); then
        [[ " ${ARMS[*]} " == *" ${arm} "* ]] || continue
    fi
    points="${points//,/ }"
    # ARM_SUFFIX names a rerun of an arm apart from its first run (section 10's
    # note of 2026-10-02: water_copies_r2).
    arm="${arm}${ARM_SUFFIX:-}"
    cmd=(sbatch --parsable --account="${ACCOUNT:-pn49go-c}" --partition="${PARTITION}" --nodes=1 --ntasks=1
         --cpus-per-task=4 --mem="${mem}" ${EXTRA[@]+"${EXTRA[@]}"} --time="${time}" -J "wp9${EXTRA[@]+x}_${arm}"
         -o "${LOGS}/%x-%j.out" "${REC_TREE}/experiments/tag_closure/runscripts/wp9_cost.sh")
    if (( DRY )); then
        echo "[dry run] ARM=${arm} FAMILY=${family} MODE=${mode} PRECIP=${precip} BASE=${base} POINTS='${points}' BUILD_LIMIT=${blimit:-${BUILD_LIMIT:-4h}} ${cmd[*]}"
        continue
    fi
    id="$(RUN_TREE="${RUN_TREE}" REC_TREE="${REC_TREE}" RUN_SHA="${RUN_SHA}" REC_SHA="${REC_SHA}" \
        ARM="${arm}" FAMILY="${family}" MODE="${mode}" PRECIP="${precip}" BASE="${base}" \
        POINTS="${points}" BUILD_LIMIT="${blimit:-${BUILD_LIMIT:-4h}}" "${cmd[@]}")"
    echo "${arm} ${id}"
done
