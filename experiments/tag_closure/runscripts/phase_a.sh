#!/usr/bin/env bash
#SBATCH --job-name=tag-closure-a
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --output=tag-closure-a-%j.out
#SBATCH --error=tag-closure-a-%j.err
#SBATCH --mail-type=FAIL

# Phase A, the water runs.
#
# One script for the whole phase. The run is chosen by the configuration, which
# travels in the environment, so this serves every a run in the register:
#
#     CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
#         sbatch experiments/tag_closure/runscripts/phase_a.sh
#
# sbatch exports the submitting environment, so CONFIG reaches the body below
# and the body hands it to the driver. Submit from the repository root.
#
# Sized for the DYCOMS column, which is one column of 30 levels and needs a
# task and a few cores. Thirteen runs use it. a5_sphere_limiter is the one
# sphere in phase A and the one that may not fit: if a day of a coarse moist
# sphere overruns the wall time here, submit it against phase_b.sh instead, or
# against runscripts/xmodel.1gpu with SCRIPT set to the driver. That is a cost
# decision for the owner, and the plan leaves it open.
#
# The #SBATCH block above follows runscripts/run_test_as_job.sh: the bd1062
# account and the shared partition. Everything below the block is shared with
# the other phases; see tag_closure_common.sh, which also explains why these are
# bash and that script is not.

SCRIPT_NAME="phase_a.sh"

# shellcheck source=tag_closure_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/tag_closure_common.sh"
