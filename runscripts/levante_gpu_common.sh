# Shared implementation for the Levante GPU runscripts.
#
# Sourced -- not executed -- by xmodel.1gpu, xmodel.2gpus and xmodel.4gpus,
# which differ only in their #SBATCH headers. Those headers cannot be shared
# (Slurm reads them from the submitted file), so everything below them lives
# here instead.
#
# The caller must, before sourcing this file:
#   source /sw/etc/profile.levante   # before `set -u`: site profiles
#                                    # reference unset variables
#   set -euo pipefail
#   ROOT=<repository root>           # see the bootstrap in each runscript
#
# and afterwards call, in order:
#   levante_gpu_init
#   levante_gpu_banner
#   levante_gpu_check_stack
#   levante_gpu_report_binding
#   levante_gpu_device_test
#   levante_gpu_warm_precompile
#   levante_gpu_run
#
# Sourcing this file also installs an ERR trap, so that a command that fails
# under `set -e` names itself instead of ending the job in silence.
#
# xmodel.cpu deliberately does not use this file. The two stacks share
# .buildkite/LocalPreferences.toml, so a cpu job and a gpu job cannot be
# prepared at the same time; presenting them as variants of one script would
# imply an interchangeability that does not exist. See the plan's F5.

# ---------------------------------------------------------------------------
# Say which command ended the job.
#
# Everything below runs under `set -euo pipefail`, where a failing command
# ends the job at once and prints nothing of its own. A pipeline killed by
# SIGPIPE, or a tool whose complaint went to a discarded stderr, then looks
# like the job stopping for no reason a few seconds in -- with the log ending
# mid-check and no clue which line was last. This trap gives every such exit a
# file, a line and a status.
#
# `set -E` is what makes it fire: an ERR trap is not inherited by shell
# functions, and every step of this file is one.
# ---------------------------------------------------------------------------

set -E

levante_gpu_report_error() {
    local status="$1" source_file="$2" line="$3" command="$4"

    echo >&2
    echo "ERROR: ${source_file}: line ${line}: exited with status ${status}" >&2
    echo "  failing command: ${command}" >&2

    if (( status == 141 )); then
        echo "  status 141 is SIGPIPE: something closed a pipe before the" >&2
        echo "  command writing into it had finished." >&2
    fi
}

trap 'levante_gpu_report_error "$?" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}"' ERR

# The srun flags that place each rank on the cores next to its GPU. Applied
# identically to the diagnostics and to the launch: a diagnostic run under
# different flags would report a mapping the run never uses.
LEVANTE_GPU_SRUN_BIND=(
    --gpu-bind=closest
    --cpu-bind=verbose,cores
    --distribution=block:block
)

levante_gpu_init() {
    # Paths, stack selection, depot, Julia version check, modules, environment.
    # Paths may be overridden from the environment, e.g.
    #   SCRIPT=experiments/my_run.jl sbatch runscripts/xmodel.4gpus
    PROJECT="${PROJECT:-${ROOT}/.buildkite}"
    SCRIPT="${SCRIPT:-${ROOT}/experiments/passive_stratospheric_tracers.jl}"
    JULIA="${JULIA:-$(command -v julia || true)}"

    # juliaup channel to run, e.g. "+1.11". Set JULIA_CHANNEL="" to use whatever
    # `julia` resolves to (the version check below still applies).
    JULIA_CHANNEL="${JULIA_CHANNEL:-+1.11}"

    # The compiler module, MPI module and depot for this stack come from
    # runscripts/levante_stacks.env, the same file setup-julia-levante.tcsh builds
    # the depot from. Reading it here is what keeps the runscript from drifting
    # onto a different MPI than the depot's OpenMPI_jll override points at.
    # Placed between srun and the command so each rank narrows itself onto the
    # cores and memory local to its GPU. srun alone cannot: --exclusive widens
    # every task's cpuset to a NUMA pair, half of which is remote.
    LEVANTE_GPU_RANK_WRAPPER="${ROOT}/runscripts/levante_gpu_rank_wrapper.sh"

    [[ -x "${LEVANTE_GPU_RANK_WRAPPER}" ]] || {
        echo "Rank wrapper missing or not executable: ${LEVANTE_GPU_RANK_WRAPPER}" >&2
        exit 1
    }

    STACKS_ENV="${STACKS_ENV:-${ROOT}/runscripts/levante_stacks.env}"

    [[ -r "${STACKS_ENV}" ]] || {
        echo "Stack definitions not found: ${STACKS_ENV}" >&2
        exit 1
    }

    # shellcheck source=levante_stacks.env
    source "${STACKS_ENV}"

    LEVANTE_DEPOT_ROOT="${LEVANTE_DEPOT_ROOT:-${HOME}/${LEVANTE_DEPOT_ROOT_RELATIVE_TO_HOME}}"

    # Exported before the version check below, so every Julia process in this job
    # -- not only the ranks -- resolves packages out of the GPU depot, where the
    # OpenMPI_jll override lives.
    export JULIA_DEPOT_PATH="${LEVANTE_DEPOT_ROOT}/${LEVANTE_GPU_DEPOT_NAME}"

    [[ -d "${JULIA_DEPOT_PATH}" ]] || {
        echo "GPU depot not found: ${JULIA_DEPOT_PATH}" >&2
        echo "Build it on a login node: ./runscripts/setup-julia-levante.tcsh gpu" >&2
        exit 1
    }

    [[ -n "${JULIA}" && -x "${JULIA}" ]] || {
        echo "Julia executable not found: '${JULIA}' (set JULIA=/path/to/julia)" >&2
        exit 1
    }

    [[ -d "${PROJECT}" ]] || {
        echo "Julia project not found: ${PROJECT}" >&2
        exit 1
    }

    [[ -f "${SCRIPT}" ]] || {
        echo "Experiment script not found: ${SCRIPT} (set SCRIPT=...)" >&2
        exit 1
    }

    # The `.buildkite` environment pins dependencies per Julia minor version
    # (Manifest-v<major>.<minor>.toml). A mismatched Julia ignores that manifest and
    # re-resolves the dependency graph, which typically fails much later as a
    # MethodError while the configuration is built. Fail before queueing work.
    manifest="$(ls "${PROJECT}"/Manifest-v*.toml 2>/dev/null | head -n 1 || true)"

    if [[ -n "${manifest}" ]]; then
        expected_version="$(basename "${manifest}")"
        expected_version="${expected_version#Manifest-v}"
        expected_version="${expected_version%.toml}"

        actual_version="$(
            "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} --startup-file=no \
                -e 'print(VERSION.major, ".", VERSION.minor)'
        )"

        [[ "${actual_version}" == "${expected_version}" ]] || {
            echo "ERROR: Julia ${actual_version} does not match the pinned manifest" >&2
            echo "  ${manifest} expects ${expected_version}" >&2
            echo "  install it ('juliaup add ${expected_version}') or set" >&2
            echo "  JULIA_CHANNEL=+${expected_version}" >&2
            exit 1
        }
    fi

    module purge
    module load "${LEVANTE_GPU_COMPILER_MODULE}"
    module load "${LEVANTE_GPU_MPI_MODULE}"

    # Prevent UCX from intercepting SIGSEGV used internally by Julia.
    export UCX_ERROR_SIGNALS="SIGILL,SIGBUS,SIGFPE"

    # Required for compatibility with CUDA-aware MPI / CUDA IPC.
    export JULIA_CUDA_MEMORY_POOL=none

    # One Julia thread per rank, deliberately not ${SLURM_CPUS_PER_TASK}. With
    # CLIMACOMMS_DEVICE=CUDA every tendency and dynamics kernel runs on the device
    # (src/config/type_getters.jl makes the ClimaComms device one exclusive
    # choice), so the 16 cores a rank owns exist for driver threads, I/O and GC
    # headroom -- not for Julia worker threads that would have nothing to do but
    # contend. Raising cpus-per-task without pinning this would silently start 16.
    export JULIA_NUM_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export MKL_NUM_THREADS=1

    export CLIMACOMMS_DEVICE=CUDA

    # Overridable so the 1-GPU baseline can also be run as SINGLETON, to
    # separate what MPI costs at one rank from what the model costs.
    export CLIMACOMMS_CONTEXT="${CLIMACOMMS_CONTEXT:-MPI}"

    # One rank per GPU is what every variant assumes, and what
    # levante_gpu_report_binding enforces per rank. Catch a mismatched
    # #SBATCH header here instead.
    # SLURM_NTASKS is the job total while SLURM_GPUS_ON_NODE is per node, so
    # compare like with like -- otherwise `sbatch --nodes=2` against these
    # headers fails here for no reason.
    local tasks_per_node=$(( SLURM_NTASKS / ${SLURM_NNODES:-1} ))

    if [[ -n "${SLURM_GPUS_ON_NODE:-}" ]] &&
       (( tasks_per_node != SLURM_GPUS_ON_NODE )); then
        echo "ERROR: ${tasks_per_node} ranks per node but ${SLURM_GPUS_ON_NODE} GPUs on the node." >&2
        echo "  --ntasks-per-node and --gpus-per-node must agree." >&2
        exit 1
    fi

    unset I_MPI_HYDRA_BOOTSTRAP || true
    unset I_MPI_HYDRA_BOOTSTRAP_EXEC_EXTRA_ARGS || true
    unset I_MPI_PMI || true
    unset I_MPI_PMI_LIBRARY || true

    # DKRZ-recommended Open MPI / UCX GPU settings.
    export OMPI_MCA_osc=ucx
    export OMPI_MCA_pml=ucx
    export OMPI_MCA_btl=self
    export OMPI_MCA_pml_ucx_opal_mem_hooks=1

    export UCX_RNDV_SCHEME=put_zcopy
    export UCX_RNDV_THRESH=16384
    export UCX_IB_GPU_DIRECT_RDMA=yes
    # gdr_copy is deliberately absent. It appears in the DKRZ recommendations,
    # but the gdrcopy kernel module is not loaded on Levante's GPU nodes: UCX
    # warns "transport 'gdr_copy' is not available" twice per rank and then
    # ignores it. Listing a transport that is never used only buys noise.
    export UCX_TLS=cma,rc,mm,cuda_ipc,cuda_copy
    export UCX_MEMTYPE_CACHE=n
}

levante_gpu_banner() {
    # What this job is and what it loaded.
    echo "Job ID:        ${SLURM_JOB_ID}"
    echo "Node:          ${SLURM_JOB_NODELIST}"
    echo "MPI ranks:     ${SLURM_NTASKS}"
    echo "CPUs per rank: ${SLURM_CPUS_PER_TASK:-1}"
    echo "Julia:         ${JULIA} ${JULIA_CHANNEL}"
    echo "Depot:         ${JULIA_DEPOT_PATH}"
    echo "Stack:         ${LEVANTE_GPU_COMPILER_MODULE} + ${LEVANTE_GPU_MPI_MODULE}"
    echo "Experiment:    ${SCRIPT}"
    echo "Start time:    $(date --iso-8601=seconds)"
    echo

    module list 2>&1

    echo
    echo "Open MPI extensions:"
    ompi_info -c | grep 'MPI extensions' || true
}

levante_gpu_check_stack() {
    echo
    echo "Stack consistency check:"

    # ---------------------------------------------------------------------------
    # The project's LocalPreferences.toml must describe the stack loaded above.
    #
    # .buildkite/LocalPreferences.toml is shared by the cpu and gpu setups, so
    # selecting the GPU depot is not enough: a `setup-julia-levante.tcsh cpu` run
    # after a gpu run leaves the GPU depot intact but rewrites the project's
    # MPIPreferences libmpi to the gcc Open MPI and deletes the CUDA_Runtime_jll
    # pin. Nothing detects that until MPI or CUDA misbehaves deep inside the run,
    # so check it here, where the fix is one command.
    #
    # The expected libmpi is derived from the module actually loaded, which is the
    # same value setup-julia-levante.tcsh records -- so this compares the stack in
    # the environment against the stack in the preferences, rather than against a
    # second hardcoded copy.
    # ---------------------------------------------------------------------------

    # `|| mpi_libdir=""` so a missing or broken mpicc reaches the check below.
    # Without it `set -o pipefail` hands the failure to `set -e` and the job
    # ends before the message that says which module was loaded.
    mpi_libdir="$(mpicc --showme:libdirs | awk '{print $1}')" || mpi_libdir=""

    [[ -n "${mpi_libdir}" ]] || {
        echo "ERROR: mpicc did not report an MPI library directory." >&2
        echo "  loaded MPI module: ${LEVANTE_GPU_MPI_MODULE}" >&2
        exit 1
    }

    LEVANTE_EXPECTED_LIBMPI="${mpi_libdir}/libmpi" \
    LEVANTE_PREFS="${PROJECT}/LocalPreferences.toml" \
    LEVANTE_STACK_HINT="${ROOT}/runscripts/setup-julia-levante.tcsh gpu" \
    "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} --startup-file=no -e '
        using TOML

        prefs_file = ENV["LEVANTE_PREFS"]
        hint = ENV["LEVANTE_STACK_HINT"]

        isfile(prefs_file) || error(
            "no LocalPreferences.toml at $(prefs_file); run: $(hint)",
        )

        prefs = TOML.parsefile(prefs_file)
        mpi = get(prefs, "MPIPreferences", Dict{String,Any}())

        recorded = get(mpi, "libmpi", nothing)
        expected = ENV["LEVANTE_EXPECTED_LIBMPI"]

        isnothing(recorded) &&
            error("MPIPreferences.libmpi is unset in $(prefs_file); run: $(hint)")

        get(mpi, "binary", nothing) == "system" || error(
            "MPIPreferences.binary is $(get(mpi, "binary", "unset")), not \"system\"; " *
            "run: $(hint)",
        )

        recorded == expected || error(
            "the project preferences describe a different MPI than this job loaded.\n" *
            "  loaded (from the gpu module): $(expected)\n" *
            "  recorded in preferences:      $(recorded)\n" *
            "A cpu setup was most likely run after the gpu setup -- the two share " *
            "this file. Selecting the GPU depot cannot repair a project-local " *
            "preference. Re-run: $(hint)",
        )

        # The cpu setup path deletes this table outright, so its absence is a
        # second, independent signal that the cpu stack was configured last.
        cuda = get(prefs, "CUDA_Runtime_jll", Dict{String,Any}())
        haskey(cuda, "version") || error(
            "CUDA_Runtime_jll.version is unset in $(prefs_file), so no CUDA " *
            "toolkit is pinned and the environment resolves to cuda=none. " *
            "Re-run: $(hint)",
        )

        println("libmpi preference matches the loaded module: ", recorded)
        println("CUDA toolkit pinned to: ", cuda["version"])
    '

    # ---------------------------------------------------------------------
    # Re-check the pinned toolkit against the driver on this node, and refresh
    # the version the next setup run will read.
    #
    # setup-julia-levante.tcsh promises exactly this, so that a driver upgrade
    # needs only a re-run of setup rather than a version typed in by hand. It
    # is cheap here because the batch script already runs on a GPU node.
    #
    # Only one direction is fatal: a toolkit newer than the driver. CUDA minor
    # version compatibility does not always survive the CUDA-aware MPI in the
    # nvhpc stack, which is why select-cuda-runtime.jl picks the newest toolkit
    # no newer than the driver.
    # ---------------------------------------------------------------------

    if command -v nvidia-smi >/dev/null 2>&1; then
        local driver_cuda pinned_cuda newest smi

        # nvidia-smi's output is read in full before it is matched, rather than
        # piped into `grep -m1`. `grep -m1` closes the pipe on its first match,
        # near the top of a report thousands of lines long, so nvidia-smi dies
        # of SIGPIPE and the pipeline exits 141. Under `set -o pipefail` that
        # status is the assignment's, and `set -e` then ends the job right
        # here -- silently, because the broken-pipe message went to the
        # discarded stderr and nothing after this point ever runs.
        smi="$(nvidia-smi -q 2>/dev/null)" || smi=""

        # "CUDA Version   : 13.0" -> "13.0". awk reads to the end of the
        # here-string, so nothing closes a pipe early.
        driver_cuda="$(awk -F: '
            !found && tolower($0) ~ /cuda version/ {
                gsub(/[[:space:]]/, "", $2)
                print $2
                found = 1
            }
        ' <<< "${smi}")"

        pinned_cuda="$(awk -F\" '
            /^\[CUDA_Runtime_jll\]/ { in_table = 1; next }
            /^\[/                    { in_table = 0 }
            in_table && /^version/   { print $2; exit }
        ' "${PROJECT}/LocalPreferences.toml")"

        if [[ -n "${driver_cuda}" ]]; then
            echo "GPU driver on this node supports CUDA ${driver_cuda}"
            printf '%s\n' "${driver_cuda}" \
                > "${JULIA_DEPOT_PATH}/levante-cuda-version" || true

            if [[ -n "${pinned_cuda}" ]]; then
                newest="$(printf '%s\n%s\n' "${pinned_cuda}" "${driver_cuda}" |
                          sort -V | tail -1)"
                if [[ "${newest}" == "${pinned_cuda}" &&
                      "${pinned_cuda}" != "${driver_cuda}" ]]; then
                    echo "ERROR: the pinned CUDA toolkit is newer than this node's driver." >&2
                    echo "  pinned:  ${pinned_cuda}" >&2
                    echo "  driver:  ${driver_cuda}" >&2
                    echo "Re-run: ${ROOT}/runscripts/setup-julia-levante.tcsh gpu" >&2
                    exit 1
                fi
            fi
        else
            # Not fatal: the check below is a convenience, and a job that
            # cannot ask the driver is no worse off than one on a node
            # without nvidia-smi. Say so rather than skipping in silence.
            echo "WARNING: nvidia-smi is present but reported no CUDA version;" >&2
            echo "  skipping the driver/toolkit comparison." >&2
        fi
    fi
}

levante_gpu_report_binding() {
    echo
    echo "Rank / core / GPU binding:"

    # ---------------------------------------------------------------------------
    # Report the binding actually obtained, and check it against the hardware.
    #
    # The srun flags here mirror the launch below exactly. Diagnosing a binding
    # under different flags than the run uses would report a mapping nothing else
    # ever sees.
    #
    # Two things are checked per rank:
    #
    #   1. Exactly one GPU is visible. This is the one failure that timings alone
    #      cannot reveal: if Slurm's topology detection hands every rank all four
    #      devices, CUDA.jl defaults each of them to device 0, and four ranks
    #      quietly serialise onto one GPU. The run completes, the numbers are
    #      simply bad, and nothing says why. Hard failure.
    #   2. The rank's cores are the ones local to that GPU, read from sysfs rather
    #      than from `nvidia-smi topo -m` -- whose trailing columns shift between
    #      driver versions, so a column-index parse silently selects the wrong
    #      field after an upgrade. Advisory: a mismatch means affinity did not
    #      take, which is worth a loud warning but not worth discarding the run.
    # ---------------------------------------------------------------------------

    srun \
        --mpi="${LEVANTE_GPU_SRUN_MPI}" \
        --label \
        --kill-on-bad-exit=1 \
        "${LEVANTE_GPU_SRUN_BIND[@]}" \
        "${LEVANTE_GPU_RANK_WRAPPER}" \
        bash -c '
            set -uo pipefail

            visible="${CUDA_VISIBLE_DEVICES:-}"
            numa=""
            cpus="$(awk "/Cpus_allowed_list/ {print \$2}" /proc/self/status)"
            # Mems_allowed_list is the cgroup allowed set, which numactl
            # --membind does not touch: it sets an MPOL_BIND policy on the
            # process. Reading the cgroup field made a correctly bound rank
            # look unbound (it reports 0-7 either way). Ask numactl instead.
            if command -v numactl >/dev/null 2>&1; then
                numa="$(numactl --show 2>/dev/null |
                        awk "/^membind:/ {\$1 = \"\"; sub(/^ /, \"\"); print}")"
            fi
            numa="${numa:-unbound}"
            cgroup_numa="$(awk "/Mems_allowed_list/ {print \$2}" /proc/self/status)"

            if [[ -z "${visible}" ]]; then
                echo "ERROR: rank ${SLURM_LOCALID} has no CUDA_VISIBLE_DEVICES" >&2
                exit 1
            fi

            ndev=$(tr "," "\n" <<< "${visible}" | grep -c .)

            if (( ndev != 1 )); then
                echo "ERROR: rank ${SLURM_LOCALID} sees ${ndev} GPUs (${visible})," \
                     "expected exactly 1. Every rank would default to device 0 and" \
                     "share it. Slurm did not apply --gpu-bind=closest as expected;" \
                     "bind explicitly (--cpu-bind=map_ldom:...) instead." >&2
                exit 1
            fi

            # nvidia-smi prints an 8-digit PCI domain (00000000:0B:00.0); sysfs
            # uses 4 (0000:0b:00.0).
            bdf="$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader | head -1)"
            bdf="$(tr "A-F" "a-f" <<< "${bdf#0000}")"
            local_cpus="$(cat "/sys/bus/pci/devices/${bdf}/local_cpulist" 2>/dev/null || echo unknown)"
            gpu_numa="$(cat "/sys/bus/pci/devices/${bdf}/numa_node" 2>/dev/null || echo unknown)"

            verdict="MATCH"
            if [[ "${local_cpus}" == "unknown" ]]; then
                verdict="UNCHECKED"
            elif [[ "${cpus}" != "${local_cpus}" ]]; then
                verdict="MISMATCH -- rank cores are not the GPU-local ones"
            fi

            echo "rank=${SLURM_LOCALID} gpu=${visible} bdf=${bdf}" \
                 "cores=${cpus} membind=${numa} cgroup-numa=${cgroup_numa}" \
                 "hca=${UCX_NET_DEVICES:-default}" \
                 "gpu-local-cores=${local_cpus} gpu-numa=${gpu_numa} ${verdict}"
        '
}

levante_gpu_device_test() {
    echo
    echo "CUDA/MPI device test:"

    srun \
        --mpi="${LEVANTE_GPU_SRUN_MPI}" \
        --label \
        --kill-on-bad-exit=1 \
        "${LEVANTE_GPU_SRUN_BIND[@]}" \
        "${LEVANTE_GPU_RANK_WRAPPER}" \
        "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} \
        --startup-file=no \
        --project="${PROJECT}" \
        -e '
            using MPI
            using CUDA
            using Libdl

            MPI.Init()

            rank = MPI.Comm_rank(MPI.COMM_WORLD)
            size = MPI.Comm_size(MPI.COMM_WORLD)
            visible = get(ENV, "CUDA_VISIBLE_DEVICES", "unset")

            println(
                "rank=$(rank)/$(size), " *
                "libmpi=$(MPI.libmpi), " *
                "CUDA-aware=$(MPI.has_cuda()), " *
                "device=$(CUDA.device()), " *
                "visible=$(visible)"
            )

            @assert size == parse(Int, ENV["SLURM_NTASKS"])
            @assert MPI.has_cuda()
            @assert CUDA.functional()

            # The depot ships an artifacts/Overrides.toml repointing OpenMPI_jll
            # at the system Open MPI, so that HDF5_jll, NetCDF_jll and
            # TempestRemap_jll load the same libmpi as MPI.jl. If the override did
            # not take effect -- wrong depot, or a stale Overrides.toml -- a second
            # Open MPI is loaded from the artifact store and the two collide.
            # setup-julia-levante.tcsh makes this assertion at setup time; making
            # it again here is what catches a job that ran with the wrong depot.
            bundled = filter(Libdl.dllist()) do path
                occursin("/artifacts/", path) &&
                    occursin(r"libmpi|libopen-pal|libpmix", basename(path))
            end

            isempty(bundled) || error(
                "a bundled MPI library is loaded alongside the system MPI: " *
                join(bundled, ", ") *
                "\nJULIA_DEPOT_PATH=$(get(ENV, "JULIA_DEPOT_PATH", "unset"))",
            )

            MPI.Barrier(MPI.COMM_WORLD)
            MPI.Finalize()
        '
}

levante_gpu_warm_precompile() {
    echo
    echo "Warming precompilation cache:"

    # Load once serially: the first import builds the precompile cache, and doing
    # that under srun makes every rank race for the same lock files. This also
    # fails legibly when the environment was never instantiated for this Julia
    # version (instantiate on a login node -- compute nodes usually have no
    # network access).
    if ! "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} \
        --project="${PROJECT}" \
        --startup-file=no \
        -e 'using ClimaAtmos; println("ClimaAtmos loaded")'
    then
        echo
        echo "ERROR: could not load ClimaAtmos from ${PROJECT}." >&2
        echo "Instantiate on a login node:" >&2
        echo "  ${JULIA} ${JULIA_CHANNEL} --project=${PROJECT} -e 'using Pkg; Pkg.instantiate()'" >&2
        exit 1
    fi
}

levante_gpu_run() {
    echo
    echo "Launching passive-tracer experiment..."

    cd "${ROOT}"

    # `set -e` is lifted around srun so that the exit status is reported and the end
    # time is logged even when the run fails.
    set +e
    srun \
        --mpi="${LEVANTE_GPU_SRUN_MPI}" \
        --kill-on-bad-exit=1 \
        "${LEVANTE_GPU_SRUN_BIND[@]}" \
        "${LEVANTE_GPU_RANK_WRAPPER}" \
        "${JULIA}" ${JULIA_CHANNEL:+"${JULIA_CHANNEL}"} \
            --project="${PROJECT}" \
            --startup-file=no \
            "${SCRIPT}"
    status=$?
    set -e

    echo
    echo "Experiment exit status: ${status}"
    echo "End time:               $(date --iso-8601=seconds)"

    return "${status}"
}
