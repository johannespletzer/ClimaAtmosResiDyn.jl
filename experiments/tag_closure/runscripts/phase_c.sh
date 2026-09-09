#!/usr/bin/env bash
#SBATCH --job-name=tag-closure-c
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=tag-closure-c-%j.out
#SBATCH --error=tag-closure-c-%j.err
#SBATCH --mail-type=FAIL

# Phase C, the energy source tag runs.
#
# One script for the whole phase. The run is chosen by the configuration, which
# travels in the environment, so this serves every c run in the register:
#
#     CONFIG=experiments/tag_closure/configs/c0_column.yml \
#         sbatch experiments/tag_closure/runscripts/phase_c.sh
#
# sbatch exports the submitting environment, so CONFIG reaches the body below
# and the body hands it to the driver. Submit from the repository root.
#
# Two shapes of run share this script: the DYCOMS source column, which needs no
# more than phase A does, and a moist sphere for a day. It is sized for the
# sphere, so the column runs leave most of it unused, which costs queue priority
# rather than compute. Provisional in the same way phase_b.sh is.
#
# The #SBATCH block above follows runscripts/run_test_as_job.sh: the bd1062
# account and the shared partition. Everything below the block is shared with
# the other phases; see tag_closure_common.sh, which also explains why these are
# bash and that script is not.

SCRIPT_NAME="phase_c.sh"

# shellcheck source=tag_closure_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/tag_closure_common.sh"
