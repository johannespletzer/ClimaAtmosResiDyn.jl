#!/usr/bin/env bash
#
# Part 8 (design/PART8_BASELINE.md, section 8): W58's trio, TRMM 0M for 6 h,
# rerun on main bb2bedf23. Three jobs, one per run. Not submitted by the PR.
# The session submits each job after the owner approves it.
#
# Cost estimate, from W58's own jobs (14119365 to 14119367, main b34bbd8b,
# 2026-10-02, 2 CPUs on shared nodes, logs in $SCRATCH/tag_closure/logs/g3base/):
#
#   job                    config                      W58 wall  build (W58)  limit  memory  node-hours
#   p8_trmm0m_untagged_6h  p8_trmm0m_untagged_6h.yml   10.7 min  158 s        1 h    48G     0.2
#   p8_trmm0m_default_6h   p8_trmm0m_default_6h.yml    14.8 min  265 s        1 h    48G     0.25
#   p8_trmm0m_copies_6h    p8_trmm0m_copies_6h.yml     14.9 min  277 s        1 h    48G     0.25
#
# About 0.7 node-hours in all, 3 node-hours at the limits. The build is the
# sum of the cache, tendency and integrator phases in the .err log. W58's
# steps took 9.4 s (untagged) and 11.6 s (tagged) for the 144 steps.
# W58 recorded no peak memory, and its 48G request held. Each job here takes
# a whole node (--exclusive), so its build and step times are a reading on an
# unshared node. They are one sample each, not the WP9 measure.
#
#   RUN_TREE=<clean detached tree at bb2bedf23> \
#       experiments/tag_closure/runscripts/part8_trio.sh [--submit] [untagged|default|copies ...]
#
# Without --submit it runs g3base_submit.sh with --dry-run, which writes the
# manifest and prints the sbatch line. Naming runs submits only those. The
# twin goes first, since parity and OD2 read it.
set -euo pipefail

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${RUN_TREE:?set RUN_TREE to a clean detached tree at bb2bedf23}"
export EXPECT_SHA=bb2bedf230a70ca9d7afc293180f8d30c1a9bb88 KIND=run RUN_TREE
LOGS="${SCRATCH:?}/tag_closure/logs/part8"
mkdir -p "${LOGS}"

SUBMIT=0
RUNS=()
for a in "$@"; do
    case "${a}" in
        --submit) SUBMIT=1 ;;
        untagged | default | copies) RUNS+=("${a}") ;;
        *)
            echo "ERROR: unknown argument ${a}." >&2
            exit 1
            ;;
    esac
done
((${#RUNS[@]})) || RUNS=(untagged default copies)
DRY=(--dry-run)
((SUBMIT)) && DRY=()

for run in "${RUNS[@]}"; do
    name="p8_trmm0m_${run}_6h"
    CONFIG="experiments/tag_closure/configs/${name}.yml" \
        "${REC}/experiments/tag_closure/runscripts/g3base_submit.sh" ${DRY[@]+"${DRY[@]}"} \
        --account=pn49go-c --partition=hpda2_compute --time=01:00:00 --nodes=1 --ntasks=1 \
        --cpus-per-task=2 --mem=48G --exclusive --job-name="${name}" \
        --output="${LOGS}/%x-%j.out" --error="${LOGS}/%x-%j.err"
done
