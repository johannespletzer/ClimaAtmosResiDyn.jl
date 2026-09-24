#!/bin/bash
# One W25 isolation probe (design/W25_ISOLATION.md) on a compute node.
#   PROBE:  fixed_parent | refinement | first_step
#   RUNCFG: the config's name under experiments/tag_closure/configs, without .yml
# The code is the W25 run tree; the environment is plan2/w25i_testenv, which
# points ClimaAtmos at it. Other settings (T_END, T0, INTERVAL, VARIANTS,
# TRIALS, NREF) pass through from the environment. Output goes to
# $SCRATCH/tag_closure/output/w25i_probes/<PROBE>/.
# Written 2026-09-24 for design/W25_ISOLATION.md. The environment plan2/w25i_testenv
# is the .buildkite manifest with ClimaAtmos at the run tree; rebuild it that way
# if scratch loses it.
set -o pipefail
W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/plan2
TREE=/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-w25i-run
export CONFIG="$TREE/experiments/tag_closure/configs/$RUNCFG.yml"
export OUTDIR="/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/w25i_probes/$PROBE"
export PROBE
mkdir -p "$OUTDIR" "$W/jobs/w25i/$PROBE/$RUNCFG" && cd "$W/jobs/w25i/$PROBE/$RUNCFG"
unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
echo "probe $PROBE on $RUNCFG, tree $TREE (commit in the report; no git on compute nodes)"
time /dss/dsshome1/0D/di38kez/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia \
    --project="$W/w25i_testenv" --startup-file=no \
    "$TREE/experiments/tag_closure/analysis/water/w25_probes.jl" 2>&1 | tee "$OUTDIR/$RUNCFG.log"
