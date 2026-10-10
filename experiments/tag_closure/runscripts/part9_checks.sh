#!/usr/bin/env bash
#
# Part 9, PR B (design/PART9_PRODUCER.md, section 5): the producer's runtime
# checks on the part 8 default case, TRMM 0M for 6 h, run from
# claude/part9-producer at 59216edef (PR #170, not on main). Six jobs. Not
# submitted by the PR. The session submits each job after the owner approves it.
#
# Cost estimate, from part 8's default job 14170101 (PART8.md: wall 844 s,
# build 209.9 s, 79.8 ms per step, MaxRSS 7.48 GiB on an exclusive node).
# The startup outside build and steps, 844 - 210 - 11 = 623 s, is kept. The
# build is taken as 1.5 times and the steps as 3 times part 8's for the
# producer's meter, its per-step writes and the 150 s diagnostics (decided
# 2026-10-10, not measured). Per job:
#   on, restarted  623 + 1.5 x 210 + 3 x 11.5 = 972 s, 16 min
#   off            623 + 210 + 3 x 11.5 = 868 s, 15 min (no producer to build)
#   newton         623 + 1.5 x 210 + 6 x 11.5 = 1007 s, 17 min (two Newton
#                  iterations and stage cadence double the steps)
#   on_f32, off_f32  as their Float64 twins, 16 and 15 min (not measured)
# The 1 h limit and 48G are part8_trio.sh's, about 3.5 times the largest
# estimate.
#
#   job                    config                      estimate  limit  memory  node-hours (limit)
#   p9_trmm0m_on_6h        p9_trmm0m_on_6h.yml         16 min    1 h    48G     0.27 (1)
#   p9_trmm0m_off_6h       p9_trmm0m_off_6h.yml        15 min    1 h    48G     0.25 (1)
#   p9_trmm0m_newton_6h    p9_trmm0m_newton_6h.yml     17 min    1 h    48G     0.28 (1)
#   p9_trmm0m_restarted_6h p9_trmm0m_restarted_6h.yml  16 min    1 h    48G     0.27 (1)
#   p9_trmm0m_on_f32_6h    p9_trmm0m_on_f32_6h.yml     16 min    1 h    48G     0.27 (1)
#   p9_trmm0m_off_f32_6h   p9_trmm0m_off_f32_6h.yml    15 min    1 h    48G     0.25 (1)
#
# About 1.6 node-hours in all, 6 node-hours at the limits. A 6 h run costs
# about as much as a short one here: steps are 1% of part 8's wall.
#
#   RUN_TREE=<clean detached tree at 59216edef> \
#       experiments/tag_closure/runscripts/part9_checks.sh [--submit] [on|off|newton|restarted|on_f32|off_f32 ...]
#
# Without --submit it runs g3base_submit.sh with --dry-run, which writes the
# manifest (head_sha 59216edef) and prints the sbatch line. `restarted` is
# refused until `on` has written its 3 h checkpoint.
set -euo pipefail

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${RUN_TREE:?set RUN_TREE to a clean detached tree at 59216edef}"
export EXPECT_SHA=59216edef02a07d672d6aa4d113d4c7cb3822925 KIND=run RUN_TREE
LOGS="${SCRATCH:?}/tag_closure/logs/part9"
CHECKPOINT="${SCRATCH}/tag_closure/output/p9_trmm0m_on_6h/output_active/day0.10800.hdf5"
mkdir -p "${LOGS}"

SUBMIT=0
RUNS=()
for a in "$@"; do
    case "${a}" in
        --submit) SUBMIT=1 ;;
        on | off | newton | restarted | on_f32 | off_f32) RUNS+=("${a}") ;;
        *)
            echo "ERROR: unknown argument ${a}." >&2
            exit 1
            ;;
    esac
done
((${#RUNS[@]})) || RUNS=(on off newton on_f32 off_f32)
DRY=(--dry-run)
((SUBMIT)) && DRY=()

for run in "${RUNS[@]}"; do
    if [[ "${run}" == restarted && ! -f "${CHECKPOINT}" ]]; then
        echo "ERROR: ${CHECKPOINT} is missing. Submit restarted after on has finished." >&2
        exit 1
    fi
    name="p9_trmm0m_${run}_6h"
    CONFIG="experiments/tag_closure/configs/${name}.yml" \
        "${REC}/experiments/tag_closure/runscripts/g3base_submit.sh" ${DRY[@]+"${DRY[@]}"} \
        --account=pn49go-c --partition=hpda2_compute --time=01:00:00 --nodes=1 --ntasks=1 \
        --cpus-per-task=2 --mem=48G --exclusive --job-name="${name}" \
        --output="${LOGS}/%x-%j.out" --error="${LOGS}/%x-%j.err"
done
