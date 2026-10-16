#!/usr/bin/env bash
# Submit a batch job and record it in the run's ledger, so a session that
# restarts can find every job of the run again (job_wait.sh).
#
#   submit.sh <run_dir> <tag> [note] -- <sbatch arguments...>
#
# It runs `sbatch --parsable` with the arguments as given, including any
# `env VAR=... ` you put before them in your own command, and appends one
# line to <run_dir>/JOBS.tsv:
#
#   job_id  tag  submitted  commit  output  note
#
# `output` is the --output pattern, with %j and %A resolved to the job id, so
# job_wait.sh can find the summary. `commit` is $COMMIT if set. The job id is
# printed on stdout, the ledger line on stderr.
set -u
[ $# -ge 4 ] || { echo "usage: submit.sh <run_dir> <tag> [note] -- <sbatch args...>" >&2; exit 2; }
run_dir=$1; tag=$2; shift 2
note=""
if [ "$1" != "--" ]; then note=$1; shift; fi
[ "$1" = "--" ] || { echo "submit.sh: expected -- before the sbatch arguments" >&2; exit 2; }
shift
mkdir -p "$run_dir"

output=""
for a in "$@"; do
    case "$a" in
        --output=*) output=${a#--output=} ;;
    esac
done
prev=""
for a in "$@"; do
    [ "$prev" = "--output" ] || [ "$prev" = "-o" ] && output=$a
    prev=$a
done

id=$(sbatch --parsable "$@") || exit $?
id=${id%%;*}
resolved=${output//%A/$id}
resolved=${resolved//%j/$id}
ledger="$run_dir/JOBS.tsv"
[ -f "$ledger" ] || printf 'job_id\ttag\tsubmitted\tcommit\toutput\tnote\n' > "$ledger"
line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$id" "$tag" "$(date -Is)" "${COMMIT:-}" "$resolved" "$note")
echo "$line" >> "$ledger"
echo "$line" >&2
echo "$id"
