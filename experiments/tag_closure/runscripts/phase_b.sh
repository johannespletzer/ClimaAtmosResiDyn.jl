#!/usr/bin/env bash
#SBATCH --job-name=tag-closure-b
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=tag-closure-b-%j.out
#SBATCH --error=tag-closure-b-%j.err
#SBATCH --mail-type=FAIL

# Phase B, the energy runs.
#
# One script for the whole phase. The run is chosen by the configuration, which
# travels in the environment, so this serves every b run in the register:
#
#     CONFIG=experiments/tag_closure/configs/b1_base.yml \
#         sbatch experiments/tag_closure/runscripts/phase_b.sh
#
# sbatch exports the submitting environment, so CONFIG reaches the body below
# and the body hands it to the driver. Submit from the repository root.
#
# Sized for ten days of a coarse sphere on one task. Provisional: the
# resolution and the length of B1, and whether it runs here or on one GPU, are
# still open questions for the owner. Revisit the wall time and the memory once
# that is settled, and once phase A has shown what a sphere costs on this
# partition. Override without editing:
#
#     CONFIG=... sbatch --time=24:00:00 --mem=128G \
#         experiments/tag_closure/runscripts/phase_b.sh
#
# The #SBATCH block above follows runscripts/run_test_as_job.sh: the bd1062
# account and the shared partition. Everything below the block is shared with
# the other phases; see tag_closure_common.sh, which also explains why these are
# bash and that script is not.

SCRIPT_NAME="phase_b.sh"

# shellcheck source=tag_closure_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/tag_closure_common.sh"
