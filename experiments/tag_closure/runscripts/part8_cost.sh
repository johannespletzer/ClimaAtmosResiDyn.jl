#!/usr/bin/env bash
#
# Part 8 (design/PART8_BASELINE.md, section 8): the WP9 cost pairs at 8 + 8
# tags on D4 (`wp9_energy_d4_edmf`), both modes, each job with its untagged
# twin point 0 on the same node, on main bb2bedf23. Six jobs, through
# `submit_wp9.sh` with SET=p8. Not submitted by the PR. The session submits
# each job after the owner approves it.
#
# Cost estimate, from E88 (design/WP9_COST.md sections 11 and 12, main d3c5e42f,
# exclusive nodes): the untagged D4 point built in 460 to 652 s, both_d3c5
# (points 0, 8, 8:ledgers) took under 2 h, copies88 built in 15,377 s with a
# first step of 996 s and a peak of 21.4 GB, and the 8 + 8 default point
# peaked at 14.5 GB.
#
#   job           mode     points        point limit  job limit  memory  node-hours (est.)
#   p8_default_a  default  0, 8:ledgers  4 h          4 h        200G    1.0
#   p8_default_b  default  0, 8:ledgers  4 h          4 h        200G    1.0
#   p8_default_c  default  0, 8:ledgers  4 h          4 h        200G    1.0
#   p8_copies_a   copies   0, 8:ledgers  8 h          9 h        200G    5.5
#   p8_copies_b   copies   0, 8:ledgers  8 h          9 h        200G    5.5
#   p8_copies_c   copies   0, 8:ledgers  8 h          9 h        200G    5.5
#
# About 20 node-hours expected and 39 at the limits. The set has energy tags
# and more than 24 hours at its limits, so it goes to the owner first
# (DELIVERY_PLAN section 2). The copies estimate adds 10% to copies88's build
# for the ledgers, since E88's energy copies at 8 tags built 4.16x untagged
# with ledgers against 3.80x without (FINDINGS E88, 2446 s at 8 on D4). E88
# has no water copies point with ledgers.
#
#   RUN_TREE=<clean detached tree at bb2bedf23> REC_TREE=<clean record worktree, pushed> \
#       experiments/tag_closure/runscripts/part8_cost.sh [--submit] [arm ...]
#
# Without --submit it passes --dry-run to submit_wp9.sh, which prints each
# sbatch line. Naming arms submits only those.
set -euo pipefail
: "${RUN_TREE:?set RUN_TREE}" "${REC_TREE:?set REC_TREE}"
ARGS=()
SUBMIT=0
for a in "$@"; do
    if [[ "${a}" == "--submit" ]]; then SUBMIT=1; else ARGS+=("${a}"); fi
done
((SUBMIT)) || ARGS=(--dry-run ${ARGS[@]+"${ARGS[@]}"})
SET=p8 RUN_TREE="${RUN_TREE}" REC_TREE="${REC_TREE}" \
    "$(dirname "${BASH_SOURCE[0]}")/submit_wp9.sh" ${ARGS[@]+"${ARGS[@]}"}
