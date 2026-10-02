#!/bin/bash
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
#SBATCH --mem=48G
#SBATCH -t 06:00:00
# transport-1 measurement. LABEL, ENV_DIR, OUT, COMMIT from the environment.
W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work
JULIA=/dss/dsshome1/0D/di38kez/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia
unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
echo "commit: ${COMMIT:-unknown}; label $LABEL; env $ENV_DIR; host: $(hostname); start: $(date -Is)"
mkdir -p $OUT && cd $OUT
/usr/bin/time -f "%e s %M KB" $JULIA --project=$ENV_DIR $W/wp4bfix_run/transport1_sphere_regime.jl $LABEL $OUT
echo "exit=$? $(date -Is)"
