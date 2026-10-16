#!/usr/bin/env bash
# The jobs of a run, from its ledger <run_dir>/JOBS.tsv (written by
# submit.sh): their states now, or, with --wait, once they have all ended.
#
#   job_wait.sh <run_dir> [--wait] [--tag <regex>] [--since <job_id>]
#
# Without --wait it prints one line per job and returns at once: use it first
# after a restart, to see what the run has in flight. With --wait it waits
# until no listed job is queued or running, checking every 3 minutes, then
# prints each job's state, elapsed time and the summary its output ends with
# (test_job.sh's `summary` block, parity_job.sh's verdict, or the last lines).
# Run --wait as a background command: its end re-invokes the session, so no
# wakeup and no polling are needed. --tag keeps the jobs whose tag matches;
# --since keeps the jobs from that id on.
set -u
[ $# -ge 1 ] || { echo "usage: job_wait.sh <run_dir> [--wait] [--tag <regex>] [--since <job_id>]" >&2; exit 2; }
run_dir=$1; shift
wait=0; tag_re="."; since=0
while [ $# -gt 0 ]; do
    case "$1" in
        --wait) wait=1 ;;
        --tag) tag_re=$2; shift ;;
        --since) since=$2; shift ;;
        *) echo "job_wait.sh: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
ledger="$run_dir/JOBS.tsv"
[ -f "$ledger" ] || { echo "no ledger $ledger" >&2; exit 2; }

mapfile -t rows < <(tail -n +2 "$ledger" | awk -F'\t' -v re="$tag_re" -v s="$since" '$2 ~ re && $1 >= s')
[ ${#rows[@]} -gt 0 ] || { echo "no jobs in $ledger match"; exit 0; }
ids=$(printf '%s\n' "${rows[@]}" | cut -f1 | paste -sd, -)

# Whether any job is queued or running. It lists the user's jobs rather than
# asking for the ids, since `squeue -j` fails ("Invalid job id specified")
# once Slurm has forgotten every listed job. A failing squeue (the
# controller busy, say) counts as running, so the wait does not end early.
# After 20 failures in a row it gives up and says so.
failures=0
gave_up=0
active() {
    local out id
    if ! out=$(squeue -h -u "$USER" -o '%i' 2>/dev/null); then
        failures=$((failures + 1))
        [ $failures -ge 20 ] && { echo "squeue failed 20 times in a row; stopping the wait" >&2; gave_up=1; return 1; }
        return 0
    fi
    failures=0
    for id in ${ids//,/ }; do
        grep -qE "^${id}(_|$)" <<< "$out" && return 0
    done
    return 1
}
if [ $wait -eq 1 ]; then
    while active; do sleep 180; done
fi

# One line per job (an array job gives one per task): state and elapsed time.
state_of() { sacct -j "$1" -X -n -P -o JobID,State,Elapsed 2>/dev/null | tr '|' ' '; }

for row in "${rows[@]}"; do
    IFS=$'\t' read -r id tag submitted commit output note <<< "$row"
    echo "== $id $tag${commit:+ at $commit}${note:+ ($note)}"
    state_of "$id" | sed 's/^/   /'
    [ $wait -eq 1 ] || continue
    # An array job's outputs carry the task id: show each task's.
    files=()
    if [[ "$output" == *%a* ]]; then
        mapfile -t files < <(ls ${output//%a/*} 2>/dev/null)
        # Every task should have written one output.
        tasks=$(sacct -j "$id" -X -n -o JobID 2>/dev/null | grep -c "${id}_")
        [ "${#files[@]}" -lt "$tasks" ] &&
            echo "   only ${#files[@]} of $tasks tasks wrote an output ($output)"
    elif [ -n "$output" ]; then
        files=("$output")
    fi
    for f in "${files[@]}"; do
        [ -f "$f" ] || { echo "   no output $f"; continue; }
        [ ${#files[@]} -gt 1 ] && echo "   -- $(basename "$f")"
        if grep -q '^summary, job' "$f"; then
            sed -n '/^summary, job/,$p' "$f" | cut -c1-200 | sed 's/^/   /'
        elif grep -qE 'BIT FOR BIT|DIFFERENCES|compare exit status' "$f"; then
            grep -E 'BIT FOR BIT|DIFFERENCES|MODEL FIELD DIFFERS|compare exit status' "$f" | tail -n 4 | sed 's/^/   /'
        else
            tail -n 6 "$f" | cut -c1-200 | sed 's/^/   /'
        fi
    done
done
# A wait that gave up says so in its status, so its end is not read as the
# jobs having finished.
[ $gave_up -eq 1 ] && exit 3
exit 0
