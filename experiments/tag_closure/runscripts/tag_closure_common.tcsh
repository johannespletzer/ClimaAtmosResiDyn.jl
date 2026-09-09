#!/bin/tcsh -f
#
# The tcsh counterpart of tag_closure_common.sh, sourced by the .tcsh phase
# scripts. The bash pair is the documented default; these exist as a fallback.
#
# tcsh has no functions, so the bash version's `tag_closure_find_root` becomes an
# inline `foreach` here. A sourced tcsh file does otherwise work the way the bash
# one does: `source` runs in the current shell, so variables set here are visible
# to the caller and an `exit` here ends the job rather than a subshell. That is
# what makes sharing this file possible at all, and it is why each phase script
# is three lines rather than a copy.
#
# Two other differences drive the shape below.
#
#   - An unset variable is a fatal "Undefined variable" in tcsh, not the empty
#     string. Every variable is therefore guarded with `$?name` before it is
#     dereferenced, so a missing CONFIG produces the same readable message the
#     bash version prints instead of killing the shell on the first mention.
#   - There is no `set -e` and no `pipefail`. `$status` is overwritten by the
#     next command whatever it is, so it is captured on the line immediately
#     after the julia call, before anything else can run.
#
# Not run directly. Source it from a phase script, which sets SCRIPT_NAME first.

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0

if (! $?LEVANTE_DEPOT) then
    set LEVANTE_DEPOT = "${HOME}/.julia/depots/levante-cpu"
endif
setenv JULIA_DEPOT_PATH "${LEVANTE_DEPOT}"

if (! $?SCRIPT_NAME) then
    set SCRIPT_NAME = "phase_a.tcsh"
endif

# ---------------------------------------------------------------------------
# CONFIG, guarded before it is ever dereferenced.
#
# This block comes first for a reason. In tcsh a bare mention of an unset
# variable aborts the shell with "Undefined variable: CONFIG", which is a
# message about tcsh rather than about the run. `$?CONFIG` tests for existence
# without dereferencing.
# ---------------------------------------------------------------------------

set config_missing = 0
if (! $?CONFIG) then
    set config_missing = 1
else if ("$CONFIG" == "") then
    set config_missing = 1
endif

if ($config_missing) then
    echo "ERROR: CONFIG is not set, so there is no run to do." >> /dev/stderr
    echo "The configuration travels in the environment." >> /dev/stderr
    echo "" >> /dev/stderr
    echo "From a tcsh login shell, VAR=value before a command is not valid" >> /dev/stderr
    echo "syntax. Use env:" >> /dev/stderr
    echo "" >> /dev/stderr
    echo "  env CONFIG=experiments/tag_closure/configs/a1_dt10.yml sbatch experiments/tag_closure/runscripts/${SCRIPT_NAME}" >> /dev/stderr
    echo "" >> /dev/stderr
    echo "or setenv first:" >> /dev/stderr
    echo "" >> /dev/stderr
    echo "  setenv CONFIG experiments/tag_closure/configs/a1_dt10.yml" >> /dev/stderr
    echo "  sbatch experiments/tag_closure/runscripts/${SCRIPT_NAME}" >> /dev/stderr
    echo "" >> /dev/stderr
    echo "The configurations are listed in experiments/tag_closure/README.md." >> /dev/stderr
    exit 1
endif

# ROOT is found by the phase script before it sources this file, because sbatch
# copies the job script to the node's spool directory and $0 is no use from in
# here.

if (! $?PROJECT) then
    set PROJECT = "${ROOT}/.buildkite"
endif
if (! $?DRIVER) then
    set DRIVER = "${ROOT}/experiments/tag_closure/run_tag_closure.jl"
endif
if (! $?JULIA) then
    set JULIA = `which julia`
endif
if (! $?JULIA_CHANNEL) then
    set JULIA_CHANNEL = "+1.11"
endif

# ---------------------------------------------------------------------------
# Resolve CONFIG against the working directory and the repository root, so both
# the documented repository-relative path and an absolute one work.
# ---------------------------------------------------------------------------

if (-f "$CONFIG") then
    set config_dir = `dirname "$CONFIG"`
    set config_base = `basename "$CONFIG"`
    set config_dir = `cd "$config_dir" && pwd`
    setenv CONFIG "${config_dir}/${config_base}"
else if (-f "${ROOT}/${CONFIG}") then
    setenv CONFIG "${ROOT}/${CONFIG}"
else
    echo "ERROR: configuration file not found: $CONFIG" >> /dev/stderr
    echo "Looked in the working directory and under ${ROOT}." >> /dev/stderr
    exit 1
endif

if ("$JULIA" == "") then
    echo "ERROR: Julia executable not found. Set JULIA=/path/to/julia." >> /dev/stderr
    exit 1
endif
if (! -x "$JULIA") then
    echo "ERROR: not executable: $JULIA" >> /dev/stderr
    exit 1
endif
if (! -f "${PROJECT}/Project.toml") then
    echo "ERROR: Julia project not found: ${PROJECT}/Project.toml" >> /dev/stderr
    exit 1
endif
if (! -f "$DRIVER") then
    echo "ERROR: driver not found: $DRIVER" >> /dev/stderr
    exit 1
endif

# ---------------------------------------------------------------------------
# Julia version against the pinned manifest, as in the bash version.
# ---------------------------------------------------------------------------

set manifest = ""
set nonomatch
foreach candidate (${PROJECT}/Manifest-v*.toml)
    if (-f "$candidate") then
        set manifest = "$candidate"
        break
    endif
end
unset nonomatch

if ("$manifest" != "") then
    set expected_version = `basename "$manifest" | sed -e s/^Manifest-v// -e s/.toml//`
    if ("$JULIA_CHANNEL" == "") then
        set actual_version = `"$JULIA" --startup-file=no -e 'print(VERSION.major, ".", VERSION.minor)'`
    else
        set actual_version = `"$JULIA" "$JULIA_CHANNEL" --startup-file=no -e 'print(VERSION.major, ".", VERSION.minor)'`
    endif
    if ("$actual_version" != "$expected_version") then
        echo "ERROR: Julia version does not match the pinned manifest." >> /dev/stderr
        echo "  manifest expects: $expected_version" >> /dev/stderr
        echo "  julia provides:   $actual_version" >> /dev/stderr
        echo "Install it (juliaup add $expected_version) or set JULIA_CHANNEL." >> /dev/stderr
        exit 1
    endif
endif

# ---------------------------------------------------------------------------
# The run's identity. The character class strips the quotes and any trailing
# space in one pass, which keeps a quote out of the sed expression and so out of
# tcsh's own quoting rules.
# ---------------------------------------------------------------------------

set JOB_ID = `grep -m 1 '^job_id:' "$CONFIG" | sed -e 's/^job_id:[[:space:]]*//' -e 's/[^A-Za-z0-9_.-]//g'`

if ("$JOB_ID" == "") then
    echo "ERROR: no job_id in $CONFIG." >> /dev/stderr
    echo "Every configuration in this series sets job_id to its run name." >> /dev/stderr
    exit 1
endif

set OUTPUT_BASE = "${ROOT}/output/${JOB_ID}"

# ---------------------------------------------------------------------------
# Threading and ClimaComms. One process, no MPI, as in the bash version.
# ---------------------------------------------------------------------------

setenv JULIA_NUM_THREADS 1
setenv OMP_NUM_THREADS 1
setenv OPENBLAS_NUM_THREADS 1
setenv MKL_NUM_THREADS 1
if (! $?CLIMACOMMS_DEVICE) then
    setenv CLIMACOMMS_DEVICE CPU
endif
if (! $?CLIMACOMMS_CONTEXT) then
    setenv CLIMACOMMS_CONTEXT SINGLETON
endif

# ---------------------------------------------------------------------------
# Job information.
# ---------------------------------------------------------------------------

set slurm_job_id = "none"
if ($?SLURM_JOB_ID) set slurm_job_id = "$SLURM_JOB_ID"
set slurm_job_name = "none"
if ($?SLURM_JOB_NAME) set slurm_job_name = "$SLURM_JOB_NAME"
set slurm_partition = "none"
if ($?SLURM_JOB_PARTITION) set slurm_partition = "$SLURM_JOB_PARTITION"
set slurm_nodelist = `hostname`
if ($?SLURM_JOB_NODELIST) set slurm_nodelist = "$SLURM_JOB_NODELIST"
set slurm_cpus = "1"
if ($?SLURM_CPUS_PER_TASK) set slurm_cpus = "$SLURM_CPUS_PER_TASK"

set commit = `git -C "$ROOT" rev-parse HEAD`
if ("$commit" == "") set commit = "unknown"
set branch = `git -C "$ROOT" rev-parse --abbrev-ref HEAD`
if ("$branch" == "") set branch = "unknown"

echo "================================================================"
echo "ClimaAtmos tag-closure run (tcsh)"
echo "================================================================"
echo "Run (job_id):    ${JOB_ID}"
echo "Configuration:   ${CONFIG}"
echo "SLURM job:       ${slurm_job_id}"
echo "Partition:       ${slurm_partition}"
echo "Nodes:           ${slurm_nodelist}"
echo "CPUs per task:   ${slurm_cpus}"
echo "Repository:      ${ROOT}"
echo "Commit:          ${commit}"
echo "Julia:           ${JULIA} ${JULIA_CHANNEL}"
echo "Project:         ${PROJECT}"
echo "Driver:          ${DRIVER}"
echo "Output base:     ${OUTPUT_BASE}"
echo "Start time:      `date --iso-8601=seconds`"
echo ""
echo "Loaded modules:"
module list
echo ""

# ---------------------------------------------------------------------------
# Run.
#
# `set run_status = $status` is the line immediately after the julia call and
# has to stay there: in tcsh $status is overwritten by whatever runs next, echo
# included, so a single intervening command would lose the exit code the whole
# hand-back turns on.
# ---------------------------------------------------------------------------

cd "$ROOT"

set start_iso = `date --iso-8601=seconds`

if ("$JULIA_CHANNEL" == "") then
    "$JULIA" --project="$PROJECT" --startup-file=no "$DRIVER"
else
    "$JULIA" "$JULIA_CHANNEL" --project="$PROJECT" --startup-file=no "$DRIVER"
endif
set run_status = $status

# ---------------------------------------------------------------------------
# Provenance, on success and on failure alike, with the fields the bash version
# writes.
# ---------------------------------------------------------------------------

if (-d "${OUTPUT_BASE}/output_active") then
    set PROVENANCE_DIR = `cd "${OUTPUT_BASE}/output_active" && pwd -P`
else if (-d "${OUTPUT_BASE}") then
    set PROVENANCE_DIR = "${OUTPUT_BASE}"
else if ($?SLURM_SUBMIT_DIR) then
    set PROVENANCE_DIR = "$SLURM_SUBMIT_DIR"
    echo "WARNING: no output directory under ${OUTPUT_BASE}; the run died early." >> /dev/stderr
else
    set PROVENANCE_DIR = "$ROOT"
    echo "WARNING: no output directory under ${OUTPUT_BASE}; the run died early." >> /dev/stderr
endif

set provenance = "${PROVENANCE_DIR}/provenance.txt"

git -C "$ROOT" diff --quiet HEAD
if ($status == 0) then
    set dirty = "no"
else
    set dirty = "yes"
endif

if ("$JULIA_CHANNEL" == "") then
    set julia_version = `"$JULIA" --startup-file=no -e 'print(string(VERSION))'`
else
    set julia_version = `"$JULIA" "$JULIA_CHANNEL" --startup-file=no -e 'print(string(VERSION))'`
endif
if ("$julia_version" == "") set julia_version = "unknown"

set node_type = `sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1`
if ("$node_type" == "") set node_type = "unknown"

echo "run: ${JOB_ID}"                                   >  "$provenance"
echo "config: ${CONFIG}"                                >> "$provenance"
echo "commit: ${commit}"                                >> "$provenance"
echo "commit_dirty: ${dirty}"                           >> "$provenance"
echo "branch: ${branch}"                                >> "$provenance"
echo "julia: ${julia_version}"                          >> "$provenance"
echo "julia_depot: ${JULIA_DEPOT_PATH}"                 >> "$provenance"
echo "project: ${PROJECT}"                              >> "$provenance"
echo "started: ${start_iso}"                            >> "$provenance"
echo "finished: `date --iso-8601=seconds`"              >> "$provenance"
echo "exit_status: ${run_status}"                       >> "$provenance"
echo "slurm_job_id: ${slurm_job_id}"                    >> "$provenance"
echo "slurm_job_name: ${slurm_job_name}"                >> "$provenance"
echo "partition: ${slurm_partition}"                    >> "$provenance"
echo "nodelist: ${slurm_nodelist}"                      >> "$provenance"
echo "cpus_per_task: ${slurm_cpus}"                     >> "$provenance"
echo "node_type: ${node_type}"                          >> "$provenance"
echo "climacomms_context: ${CLIMACOMMS_CONTEXT}"        >> "$provenance"
echo "climacomms_device: ${CLIMACOMMS_DEVICE}"          >> "$provenance"
echo "output_dir: ${PROVENANCE_DIR}"                    >> "$provenance"
echo "netcdf_and_checkpoints: ${PROVENANCE_DIR} (left on scratch, not committed)" >> "$provenance"
echo "runscript_shell: tcsh"                            >> "$provenance"

echo ""
echo "Wrote ${provenance}"
echo "Driver exit status: ${run_status}"
echo "End time:           `date --iso-8601=seconds`"

exit $run_status
