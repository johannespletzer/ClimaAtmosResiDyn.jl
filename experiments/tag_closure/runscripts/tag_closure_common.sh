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
# Two machines run it: DKRZ Levante, where the series started, and LRZ
# terrabyte. The #SBATCH blocks in the phase scripts are Levante's. On
# terrabyte the account and the partition are given on the sbatch command line,
# which overrides them; README.md shows the line.
#
# Not sourced directly. Source it from a phase script.

# ---------------------------------------------------------------------------
# Which machine, and how its modules start.
#
# TAG_CLOSURE_MACHINE names it. Otherwise it is detected from a path only that
# machine has. This runs before `set -u`, because site profiles routinely
# reference unset variables and would abort the job at source time under it.
# ---------------------------------------------------------------------------

if [[ -z "${TAG_CLOSURE_MACHINE:-}" ]]; then
    if [[ -r /sw/etc/profile.levante ]]; then
        TAG_CLOSURE_MACHINE="levante"
    elif [[ -d /dss/lrzsys ]]; then
        TAG_CLOSURE_MACHINE="terrabyte"
    fi
fi

case "${TAG_CLOSURE_MACHINE:-}" in
    levante)
        source /sw/etc/profile.levante
        ;;
    terrabyte)
        # A batch job's bash inherits MODULESHOME but not the module function.
        type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
        ;;
    *)
        echo "ERROR: cannot tell which machine this is." >&2
        echo "Set TAG_CLOSURE_MACHINE to levante or terrabyte." >&2
        exit 1
        ;;
esac

set -euo pipefail

# ---------------------------------------------------------------------------
# The git facts, captured HERE and not where they are printed.
#
# `module purge` below strips the module environment, and on a Levante compute
# node that takes git with it: the first real run recorded `commit: unknown`
# from a job whose every non-git field was correct. Reading them before the
# purge is most of the fix.
#
# The rest of it is not depending on the binary at all. If git is absent, or
# refuses the repository over `dubious ownership` -- which it does when the
# checkout is not owned by the user running the job -- HEAD is read straight
# out of `.git`, which needs no git and cannot be refused. `-c safe.directory`
# heads off the ownership refusal in the first place.
#
# `commit_dirty` is the one thing the file fallback cannot answer, and it must
# then read `unknown`. It previously read `yes`, because a failed `git diff`
# took the `|| echo yes` branch, so a job that could not tell reported a dirty
# tree. That is worse than no answer.
#
# `commit_source` and `commit_error` are recorded so that the next time this
# fails it says why, rather than leaving another `unknown` to be diagnosed from
# a terminal.
# ---------------------------------------------------------------------------

GIT_COMMIT=""
GIT_BRANCH=""
GIT_DIRTY="unknown"
GIT_SOURCE="none"
GIT_ERROR=""

tag_closure_read_git_files() {
    local head_file="${ROOT}/.git/HEAD"
    [[ -r "${head_file}" ]] || return 1
    local head ref
    head="$(<"${head_file}")"
    if [[ "${head}" == ref:* ]]; then
        ref="${head#ref: }"
        GIT_BRANCH="${ref#refs/heads/}"
        if [[ -r "${ROOT}/.git/${ref}" ]]; then
            GIT_COMMIT="$(<"${ROOT}/.git/${ref}")"
        elif [[ -r "${ROOT}/.git/packed-refs" ]]; then
            GIT_COMMIT="$(
                awk -v r="${ref}" '$2 == r { print $1; exit }' \
                    "${ROOT}/.git/packed-refs"
            )"
        fi
    else
        # Detached HEAD holds the object name itself.
        GIT_COMMIT="${head}"
        GIT_BRANCH="detached"
    fi
    [[ -n "${GIT_COMMIT}" ]]
}

if command -v git >/dev/null 2>&1; then
    if GIT_COMMIT="$(
        git -C "${ROOT}" -c safe.directory="${ROOT}" rev-parse HEAD 2>&1
    )"; then
        GIT_SOURCE="git"
        GIT_BRANCH="$(
            git -C "${ROOT}" -c safe.directory="${ROOT}" \
                rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown
        )"
        if git -C "${ROOT}" -c safe.directory="${ROOT}" \
            diff --quiet HEAD 2>/dev/null
        then
            GIT_DIRTY="no"
        else
            GIT_DIRTY="yes"
        fi
    else
        GIT_ERROR="${GIT_COMMIT}"
        GIT_COMMIT=""
    fi
else
    GIT_ERROR="git is not on PATH"
fi

if [[ -z "${GIT_COMMIT}" ]]; then
    if tag_closure_read_git_files; then
        GIT_SOURCE="git-files"
    else
        GIT_SOURCE="none"
        [[ -n "${GIT_ERROR}" ]] || GIT_ERROR="no .git under ${ROOT}"
    fi
fi

[[ -n "${GIT_COMMIT}" ]] || GIT_COMMIT="unknown"
[[ -n "${GIT_BRANCH}" ]] || GIT_BRANCH="unknown"

if [[ "${GIT_COMMIT}" == "unknown" ]]; then
    echo "WARNING: could not determine the commit: ${GIT_ERROR}" >&2
    echo "The analysis refuses a run whose provenance has no commit." >&2
fi

# ---------------------------------------------------------------------------
# The machine's CPU stack, its depot, and where the run writes.
#
# RUN_DIR is the run's working directory, and ClimaAtmos writes output/<job_id>
# under it. On Levante that is the repository root, as it always was. On
# terrabyte it is on scratch, because $HOME there is for code only. Nothing
# needs the working directory to be the repository: CONFIG, DRIVER and PROJECT
# are absolute paths below, and a `toml:` entry that is not found from the
# working directory is looked up in the ClimaAtmos package directory.
# ---------------------------------------------------------------------------

case "${TAG_CLOSURE_MACHINE}" in
    levante)
        module purge
        module load gcc/11.2.0-gcc-11.2.0
        module load openmpi/4.1.2-gcc-11.2.0
        # The CPU stack's depot, as run_test_as_job.sh selects it.
        # `setup-julia-levante` builds the CPU and GPU depots separately; see
        # runscripts/README.md.
        export JULIA_DEPOT_PATH="${LEVANTE_DEPOT:-${HOME}/.julia/depots/levante-cpu}"
        RUN_DIR="${RUN_DIR:-${ROOT}}"
        ;;
    terrabyte)
        # The compiler, MPI and depot pairing lives in one file, which
        # setup-julia-terrabyte.tcsh reads as well.
        source "${ROOT}/runscripts/terrabyte_stacks.env"
        # Never `module purge` here. It drops stack/24.4.0, and loading that
        # again does not bring the spack modules back. The module function
        # reads unset variables, so `set -u` is lifted around it.
        set +u
        module load "${TERRABYTE_CPU_COMPILER_MODULE}"
        module load "${TERRABYTE_CPU_MPI_MODULE}"
        set -u
        export JULIA_DEPOT_PATH="${TERRABYTE_DEPOT_ROOT:-${TERRABYTE_DEPOT_ROOT_ABSOLUTE}}/${TERRABYTE_CPU_DEPOT_NAME}"
        RUN_DIR="${RUN_DIR:-${SCRATCH:?SCRATCH is not set}/tag_closure}"
        ;;
esac
mkdir -p "${RUN_DIR}"

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

# A job that is not the configuration's own run, such as the C1 twin test,
# names its output with TAG_CLOSURE_JOB_ID so that it cannot write over that
# run. Only a driver that reads the same variable should be given it.
JOB_ID="${TAG_CLOSURE_JOB_ID:-${JOB_ID}}"

OUTPUT_BASE="${RUN_DIR}/output/${JOB_ID}"

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
echo "Machine:         ${TAG_CLOSURE_MACHINE}"
echo "Configuration:   ${CONFIG}"
echo "SLURM job:       ${SLURM_JOB_ID:-none}"
echo "Partition:       ${SLURM_JOB_PARTITION:-none}"
echo "Nodes:           ${SLURM_JOB_NODELIST:-$(hostname)}"
echo "CPUs per task:   ${SLURM_CPUS_PER_TASK:-1}"
echo "Repository:      ${ROOT}"
echo "Commit:          ${GIT_COMMIT} (from ${GIT_SOURCE})"
echo "Julia:           ${JULIA} ${JULIA_CHANNEL}"
echo "Project:         ${PROJECT}"
echo "Driver:          ${DRIVER}"
echo "Depot:           ${JULIA_DEPOT_PATH}"
echo "Run directory:   ${RUN_DIR}"
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

cd "${RUN_DIR}"

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
    echo "machine: ${TAG_CLOSURE_MACHINE}"
    echo "config: ${CONFIG}"
    echo "driver: ${DRIVER}"
    echo "commit: ${GIT_COMMIT}"
    echo "commit_source: ${GIT_SOURCE}"
    echo "commit_dirty: ${GIT_DIRTY}"
    echo "branch: ${GIT_BRANCH}"
    [[ -z "${GIT_ERROR}" ]] || echo "commit_error: ${GIT_ERROR}"
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
