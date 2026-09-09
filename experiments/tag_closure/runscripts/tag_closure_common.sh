#!/usr/bin/env bash
#
# Everything the three phase runscripts do, sourced by each. They differ only in
# their #SBATCH block; the work below is identical, so it lives here rather than
# in three copies that drift apart. This mirrors runscripts/levante_gpu_common.sh.
#
# A note on ancestry, because the plan is misleading on one point. The #SBATCH
# block, the account, the shared partition, the levante-cpu depot and the module
# lines come from runscripts/run_test_as_job.sh, which is what the plan means by
# "follow run_test_as_job.sh". The *structure* below -- SLURM_SUBMIT_DIR root
# discovery, environment overrides with defaults, fail-early checks -- comes from
# runscripts/xmodel.cpu. run_test_as_job.sh is tcsh and hardcodes its repository
# path, and in tcsh an unset $CONFIG is a fatal "Undefined variable" rather than
# a message anyone can act on. These are bash.
#
# Not sourced directly. Source it from a phase script.

# ---------------------------------------------------------------------------
# Levante software environment.
#
# Sourced before `set -u`, because site profiles routinely reference unset
# variables and would abort the job at source time under it.
# ---------------------------------------------------------------------------

source /sw/etc/profile.levante

set -euo pipefail

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0

# The CPU stack's depot, as run_test_as_job.sh selects it. `setup-julia-levante`
# builds the CPU and GPU depots separately; see runscripts/README.md.
export JULIA_DEPOT_PATH="${LEVANTE_DEPOT:-${HOME}/.julia/depots/levante-cpu}"

# ROOT is found by the phase script before it sources this file, because sbatch
# copies the job script to the node's spool directory and BASH_SOURCE is no use
# from in here. It is exported, so it is set by the time we run.

PROJECT="${PROJECT:-${ROOT}/.buildkite}"
DRIVER="${DRIVER:-${ROOT}/experiments/tag_closure/run_tag_closure.jl}"
JULIA="${JULIA:-$(command -v julia || true)}"

# juliaup channel, e.g. "+1.11". Set JULIA_CHANNEL="" to use whatever `julia`
# resolves to; the version check below still applies.
JULIA_CHANNEL="${JULIA_CHANNEL:-+1.11}"

# ---------------------------------------------------------------------------
# Fail early, with a message that names what to fix.
# ---------------------------------------------------------------------------

if [[ -z "${CONFIG:-}" ]]; then
    echo "ERROR: CONFIG is not set, so there is no run to do." >&2
    echo "The configuration travels in the environment. Submit as:" >&2
    echo >&2
    echo "  CONFIG=experiments/tag_closure/configs/a1_dt10.yml \\" >&2
    echo "      sbatch experiments/tag_closure/runscripts/${SCRIPT_NAME:-phase_a.sh}" >&2
    echo >&2
    echo "The configurations are listed in experiments/tag_closure/README.md." >&2
    exit 1
fi

# Resolve CONFIG against the repository root as well as the working directory,
# so both the documented repository-relative path and an absolute one work.
if [[ -f "${CONFIG}" ]]; then
    CONFIG="$(cd "$(dirname "${CONFIG}")" && pwd)/$(basename "${CONFIG}")"
elif [[ -f "${ROOT}/${CONFIG}" ]]; then
    CONFIG="${ROOT}/${CONFIG}"
else
    echo "ERROR: configuration file not found: ${CONFIG}" >&2
    echo "Looked in the working directory and under ${ROOT}." >&2
    exit 1
fi

if [[ -z "${JULIA}" || ! -x "${JULIA}" ]]; then
    echo "ERROR: Julia executable not found: '${JULIA}'. Set JULIA=/path/to/julia." >&2
    exit 1
fi

if [[ ! -f "${PROJECT}/Project.toml" ]]; then
    echo "ERROR: Julia project not found: ${PROJECT}/Project.toml" >&2
    exit 1
fi

if [[ ! -f "${DRIVER}" ]]; then
    echo "ERROR: driver not found: ${DRIVER}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Julia version must match the pinned manifest.
#
# `.buildkite` pins dependencies per Julia minor version, in
# Manifest-v<major>.<minor>.toml. Another minor version ignores that manifest and
# re-resolves the dependency graph, which can select package versions the source
# has never supported. The failure then surfaces deep inside the run, long after
# the job was queued and started. Check here instead.
# ---------------------------------------------------------------------------

manifest="$(ls "${PROJECT}"/Manifest-v*.toml 2>/dev/null | head -n 1 || true)"

if [[ -n "${manifest}" ]]; then
    expected_version="$(basename "${manifest}")"
    expected_version="${expected_version#Manifest-v}"
    expected_version="${expected_version%.toml}"

    actual_version="$(
        "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} --startup-file=no \
            -e 'print(VERSION.major, ".", VERSION.minor)'
    )"

    if [[ "${actual_version}" != "${expected_version}" ]]; then
        echo "ERROR: Julia version does not match the pinned manifest." >&2
        echo "  manifest expects: ${expected_version} ($(basename "${manifest}"))" >&2
        echo "  julia provides:   ${actual_version}" >&2
        echo "Install it (juliaup add ${expected_version}) or set" >&2
        echo "JULIA_CHANNEL=+${expected_version}." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# The run's identity and where its output will land.
#
# `job_id` is read out of the configuration rather than guessed: every config in
# this series sets it to its own run name, which is what makes the run's output
# name itself. The output directory follows ClimaAtmos's default of
# output/<job_id> with the ActiveLink style, so output_active points at the
# newest numbered subdirectory.
# ---------------------------------------------------------------------------

job_id_line="$(grep -m 1 '^job_id:' "${CONFIG}" || true)"
JOB_ID="${job_id_line#job_id:}"      # drop the key
JOB_ID="${JOB_ID//[\"\' ]/}"         # drop quotes and spaces
JOB_ID="${JOB_ID%$'\r'}"             # and a stray carriage return

if [[ -z "${JOB_ID}" ]]; then
    echo "ERROR: no job_id in ${CONFIG}." >&2
    echo "Every configuration in this series sets job_id to its run name, so" >&2
    echo "that the run's output names itself. Add it." >&2
    exit 1
fi

OUTPUT_BASE="${ROOT}/output/${JOB_ID}"

# ---------------------------------------------------------------------------
# Threading and ClimaComms.
#
# One process, no MPI. These runs are a single column or a coarse sphere on one
# task, so SINGLETON avoids the MPI stack and the CPU/GPU preferences clash that
# runscripts/README.md describes under "Two stacks, one preferences file".
# ---------------------------------------------------------------------------

export JULIA_NUM_THREADS=1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

export CLIMACOMMS_DEVICE="${CLIMACOMMS_DEVICE:-CPU}"
export CLIMACOMMS_CONTEXT="${CLIMACOMMS_CONTEXT:-SINGLETON}"

# ---------------------------------------------------------------------------
# Job information.
# ---------------------------------------------------------------------------

echo "================================================================"
echo "ClimaAtmos tag-closure run"
echo "================================================================"
echo "Run (job_id):    ${JOB_ID}"
echo "Configuration:   ${CONFIG}"
echo "SLURM job:       ${SLURM_JOB_ID:-none}"
echo "Partition:       ${SLURM_JOB_PARTITION:-none}"
echo "Nodes:           ${SLURM_JOB_NODELIST:-$(hostname)}"
echo "CPUs per task:   ${SLURM_CPUS_PER_TASK:-1}"
echo "Repository:      ${ROOT}"
echo "Commit:          $(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "Julia:           ${JULIA} ${JULIA_CHANNEL}"
echo "Project:         ${PROJECT}"
echo "Driver:          ${DRIVER}"
echo "Output base:     ${OUTPUT_BASE}"
echo "Start time:      $(date --iso-8601=seconds)"
echo

echo "Loaded modules:"
module list 2>&1
echo

# ---------------------------------------------------------------------------
# Run.
#
# `set -e` is lifted around the driver, so a failing run still writes its
# provenance and reports its exit status. The driver exits non-zero when the
# solve did not succeed; ClimaAtmos returns :simulation_crashed rather than
# throwing, so this status is the thing to read.
# ---------------------------------------------------------------------------

cd "${ROOT}"

start_iso="$(date --iso-8601=seconds)"
set +e
"${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} \
    --project="${PROJECT}" \
    --startup-file=no \
    "${DRIVER}"
status=$?
set -e

# ---------------------------------------------------------------------------
# Provenance.
#
# The hand-back section asks for this file with every run, and a script that
# writes it is more reliable than a person retyping it. It goes into the run's
# own output directory, so it travels with the tables it describes. If the run
# died before creating that directory it goes beside the submitted job's output
# instead, which is the only place left.
#
# The NetCDF diagnostics and the checkpoints stay on scratch under the same
# output directory, so recording its absolute path is what points back to them.
# ---------------------------------------------------------------------------

if [[ -d "${OUTPUT_BASE}/output_active" ]]; then
    PROVENANCE_DIR="$(cd "${OUTPUT_BASE}/output_active" && pwd -P)"
elif [[ -d "${OUTPUT_BASE}" ]]; then
    PROVENANCE_DIR="${OUTPUT_BASE}"
else
    PROVENANCE_DIR="${SLURM_SUBMIT_DIR:-${ROOT}}"
    echo "WARNING: no output directory under ${OUTPUT_BASE}; the run died early." >&2
    echo "Writing provenance.txt to ${PROVENANCE_DIR} instead." >&2
fi

# Read this before the block below rather than inside it. `sed ... | head -n 1`
# lets head close the pipe as soon as it has its line, so sed dies of SIGPIPE and
# the pipeline reports failure under `set -o pipefail` -- after the value has
# already been printed. A `|| echo unknown` inside the field would then append a
# second line to a field that is already correct. The tcsh runscript assigns
# first for the same reason.
node_type="$(
    sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n 1
)" || true
[[ -n "${node_type}" ]] || node_type="unknown"

{
    echo "run: ${JOB_ID}"
    echo "config: ${CONFIG}"
    echo "commit: $(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "commit_dirty: $(
        git -C "${ROOT}" diff --quiet HEAD 2>/dev/null && echo no || echo yes
    )"
    echo "branch: $(
        git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown
    )"
    echo "julia: $(
        "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} --startup-file=no \
            -e 'print(string(VERSION))' 2>/dev/null || echo unknown
    )"
    echo "julia_depot: ${JULIA_DEPOT_PATH}"
    echo "project: ${PROJECT}"
    echo "started: ${start_iso}"
    echo "finished: $(date --iso-8601=seconds)"
    echo "exit_status: ${status}"
    echo "slurm_job_id: ${SLURM_JOB_ID:-none}"
    echo "slurm_job_name: ${SLURM_JOB_NAME:-none}"
    echo "partition: ${SLURM_JOB_PARTITION:-none}"
    echo "nodelist: ${SLURM_JOB_NODELIST:-$(hostname)}"
    echo "cpus_per_task: ${SLURM_CPUS_PER_TASK:-1}"
    echo "node_type: ${node_type}"
    echo "climacomms_context: ${CLIMACOMMS_CONTEXT}"
    echo "climacomms_device: ${CLIMACOMMS_DEVICE}"
    echo "output_dir: ${PROVENANCE_DIR}"
    echo "netcdf_and_checkpoints: ${PROVENANCE_DIR} (left on scratch, not committed)"
} > "${PROVENANCE_DIR}/provenance.txt"

echo
echo "Wrote ${PROVENANCE_DIR}/provenance.txt"
echo "Driver exit status: ${status}"
echo "End time:           $(date --iso-8601=seconds)"

exit "${status}"
