#!/usr/bin/env bash
# Count the invalidations of one or more environments as a terrabyte batch
# job, on Julia 1.10 as CI's Invalidations job is.
#
#   ENVS="<env> <env> ..." OUT=<dir> \
#       sbatch --time=01:55:00 \
#       --cpus-per-task=8 --mem=32G --job-name=invalidations \
#       --output=<dir>/invalidations-%j.out $CLIMA_SKILLS/upstream-sync/scripts/invalidations_job.sh
#
# Each env is built with `make_ci_env.jl <checkout> <env> invalidations`. It
# is precompiled, then counted twice, since the load order is not fixed.
# Each count writes $OUT/<env name>.<k>.log and $OUT/<env name>.<k>.methods.
# A precompile takes about 10 minutes on 1.10, and a count about 2.
set -u
# The site's values (account, partitions, depot) come from a private file
# outside the repository, CLIMA_SITE_ENV or ~/.config/climaatmos-fork/site.env.
# See .claude/site.example.env.
site_env=${CLIMA_SITE_ENV:-$HOME/.config/climaatmos-fork/site.env}
[[ -f $site_env ]] && source "$site_env"
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
unset JULIA_LOAD_PATH JULIA_PROJECT
export JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH:-${CLIMA_JULIA_DEPOT:?set CLIMA_JULIA_DEPOT in $site_env, or JULIA_DEPOT_PATH}}
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-4}
# Musica_jll needs a newer libstdc++ (CXXABI_1.3.15) than the one Julia ships,
# and Julia loads its own. The system's is new enough.
grep -q CXXABI_1.3.15 /usr/lib64/libstdc++.so.6 && export LD_PRELOAD=/usr/lib64/libstdc++.so.6
VER=${VER:-1.10}
JULIA=${JULIA:-$(ls -d "$HOME"/.julia/juliaup/julia-"$VER".*/bin/julia | sort -V | tail -n 1)}
SCRIPTS=${SCRIPTS:-${CLIMA_SKILLS:?set CLIMA_SKILLS to the .claude/skills of the checkout}/upstream-sync/scripts}
: "${ENVS:?set ENVS to one or more environment directories}"
: "${OUT:?set OUT to a result directory}"
mkdir -p "$OUT"
echo "$("$JULIA" --version); host $(hostname); start $(date -Is)"
failed=0

for env in $ENVS; do
    name=$(basename "$env")
    echo "== $name: $(grep -E '^(commit|ci_log|pins) ' "$env/PROVENANCE" | tr '\n' ' ')"
    if ! "$JULIA" --startup-file=no --project="$env" -e 'import Pkg; Pkg.precompile()' \
        > "$OUT/$name.precompile.log" 2>&1; then
        echo "  precompile failed, see $OUT/$name.precompile.log"
        failed=1
        continue
    fi
    for k in 1 2; do
        "$JULIA" --startup-file=no --project="$env" "$SCRIPTS/invalidations.jl" "$OUT/$name.$k" \
            > "$OUT/$name.$k.log" 2>&1
        if [ -s "$OUT/$name.$k.methods" ] && grep -q '^inv_total ' "$OUT/$name.$k.log"; then
            echo "  count $k: $(grep -E '^inv_(total|deps) ' "$OUT/$name.$k.log" | tr '\n' ' ')"
        else
            echo "  count $k FAILED, see $OUT/$name.$k.log"
            failed=1
        fi
    done
    if cmp -s "$OUT/$name.1.methods" "$OUT/$name.2.methods"; then
        echo "  both counts invalidate the same methods"
    else
        echo "  the two counts differ: comm -3 $OUT/$name.1.methods $OUT/$name.2.methods"
    fi
done
echo "end $(date -Is)"
# A failed count leaves no .methods file, and a comparison with a missing file
# reads as "no difference", so the job says it failed.
exit $failed
