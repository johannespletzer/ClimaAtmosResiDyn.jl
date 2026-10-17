#!/usr/bin/env bash
# Run test files, or one test group, of a checkout as a terrabyte batch job,
# with the wall time and the peak memory of each.
#
#   CODE=<checkout> COMMIT=<sha> TAG=<label> VER=1.11|1.10 \
#   ENV_DIR=<env from make_ci_env.jl> FILES="tagged_water_tests.jl ..." \
#       sbatch --time=01:55:00 \
#       --cpus-per-task=4 --mem=48G --job-name=$TAG \
#       --output=<out>/$TAG-%j.out $CLIMA_SKILLS/terrabyte-test-job/scripts/test_job.sh
#
# FILES are relative to test/, or absolute, and run one after the other in
# ENV_DIR. An absolute path runs a script such as docstring_refs.jl. Instead
# of FILES, TEST_GROUP=<test group> runs test/runtests.jl in ENV_DIR with that
# group, which runtests.jl reads from the environment. So a group runs with
# the environment's versions, CI's, and nothing is written into the checkout,
# where a 1.10 and a 1.11 job would otherwise race on its Manifest.toml. (Not
# GROUP: the login shell sets that to the Unix group.) OUT (default
# $SCRATCH/claude_work/<TAG>_run) collects the logs. COMMIT is passed in
# because compute nodes have no git.
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
VER=${VER:-1.11}
JULIA=${JULIA:-$(ls -d "$HOME"/.julia/juliaup/julia-"$VER".*/bin/julia | sort -V | tail -n 1)}
OUT=${OUT:-${SCRATCH:?set SCRATCH or OUT}/claude_work/${TAG}_run}
JOB=${SLURM_JOB_ID:-local}
mkdir -p "$OUT/logs"
echo "commit ${COMMIT:-unknown}; tag $TAG; $("$JULIA" --version); code $CODE"
echo "env ${ENV_DIR:-none}; host $(hostname); start $(date -Is)"
# The environment's provenance, which says whose versions it holds (ci_log)
# and which checkout it was built for.
if [ -n "${ENV_DIR:-}" ] && [ -f "$ENV_DIR/PROVENANCE" ]; then
    echo "env provenance: $(grep -E '^(checkout|commit|ci_log|pins|julia) ' "$ENV_DIR/PROVENANCE" | tr '\n' ' ')"
    built_for=$(sed -n 's/^checkout //p' "$ENV_DIR/PROVENANCE")
    [ "$(realpath -m "$built_for")" = "$(realpath -m "$CODE")" ] ||
        echo "WARNING: $ENV_DIR was built for $built_for, not $CODE"
elif [ -n "${ENV_DIR:-}" ]; then
    # A copied environment keeps the package paths of the checkout it was
    # built for. A path that no longer holds the package fails the
    # precompile step with "Missing source file".
    echo "WARNING: $ENV_DIR has no PROVENANCE, so make_ci_env.jl did not build it."
    echo "  Its package paths may point at another checkout. Build a fresh one with make_ci_env.jl."
fi

# Each run's wall time in seconds and its peak resident memory in GiB. A peak
# above 14 GiB on Julia 1.10 is close to a GitHub runner's 16 GB.
summary=()
timed() {
    local name=$1 log=$2
    shift 2
    /usr/bin/time -f "%e %M" -o "$log.time" "$@" > "$log" 2>&1
    local status=$?
    # GNU time puts "Command exited with non-zero status" before its own line.
    read -r seconds kib < <(tail -n 1 "$log.time")
    local gib
    gib=$(awk -v k="$kib" 'BEGIN { printf "%.2f", k / 1048576 }')
    local warn=""
    [ "$VER" = "1.10" ] && awk -v g="$gib" 'BEGIN { exit !(g > 14) }' && warn="  NEAR 16 GB"
    summary+=("$(printf '%-52s exit %-3s %8.0f s %7s GiB%s' "$name" "$status" "$seconds" "$gib" "$warn")")
    echo "== $name: exit $status, $seconds s, $gib GiB$warn"
    local counts
    counts=$(test_counts "$log")
    [ -n "$counts" ] && summary[-1]+="  $counts"
    echo "   $counts"
}

# The sums over a log's `Test Summary:` tables, whose columns vary with the
# outcomes present.
test_counts() {
    awk -F'|' '
        /^Test Summary:/ { n = split($2, head, " "); getline; split($2, vals, " ")
                           for (i = 1; i <= n; i++) sum[head[i]] += vals[i]; tables++ }
        END { if (tables) printf "%d tables: %d pass, %d fail, %d error, %d broken, %d total",
                  tables, sum["Pass"], sum["Fail"], sum["Error"], sum["Broken"], sum["Total"] }' "$1"
}

if [ -n "${TEST_GROUP:-}" ]; then
    [ -n "${ENV_DIR:-}" ] || { echo "TEST_GROUP needs ENV_DIR" >&2; exit 2; }
    timed precompile "$OUT/logs/$TAG-precompile-$JOB.log" \
        "$JULIA" --project="$ENV_DIR" -e 'using Pkg; Pkg.precompile()'
    mkdir -p "$OUT/run/$TAG-group-$TEST_GROUP" && cd "$OUT/run/$TAG-group-$TEST_GROUP" || exit 2
    TEST_GROUP=$TEST_GROUP timed "group $TEST_GROUP" "$OUT/logs/$TAG-group-$TEST_GROUP-$JOB.log" \
        "$JULIA" --project="$ENV_DIR" "$CODE/test/runtests.jl"
else
    [ -n "${FILES:-}" ] || { echo "set FILES or TEST_GROUP" >&2; exit 2; }
    timed precompile "$OUT/logs/$TAG-precompile-$JOB.log" \
        "$JULIA" --project="$ENV_DIR" -e 'using Pkg; Pkg.precompile()'
    for f in $FILES; do
        n=$(echo "$f" | tr '/' '_' | sed 's/\.jl$//')
        # Each file writes its output into its own directory.
        mkdir -p "$OUT/run/$TAG-$n" && cd "$OUT/run/$TAG-$n" || exit 2
        case "$f" in /*) path=$f ;; *) path=$CODE/test/$f ;; esac
        timed "$f" "$OUT/logs/$TAG-$n-$JOB.log" "$JULIA" --project="$ENV_DIR" "$path"
    done
fi
echo
echo "summary, job $JOB, julia $VER, commit ${COMMIT:-unknown}"
printf '%s\n' "${summary[@]}"
echo "logs in $OUT/logs; end $(date -Is)"
