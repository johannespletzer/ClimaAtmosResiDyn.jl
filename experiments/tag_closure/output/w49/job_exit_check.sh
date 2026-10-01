#!/bin/sh
# The command behind job_exit_check.txt (W49): Slurm's state of the seven
# jobs, the driver's exit status in each .out log, and a search of each .err
# log for "error" or "exception" (none match). Run on a login node.
L=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs
sacct -j 14015465,14015466,14015467,14015468,14015469,14015470,14015471 \
  --format=JobID,JobName%24,State,ExitCode,Elapsed -X
(cd "$L" && grep "Driver exit status" crev90-*.out)
echo "--- .err logs matching error or exception (none expected):"
(cd "$L" && grep -il -E "error|exception" crev90-*.err || echo none)
