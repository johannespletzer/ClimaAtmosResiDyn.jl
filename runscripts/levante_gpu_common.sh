# Shared implementation for the Levante GPU runscripts.
#
# Sourced, rather than executed, by xmodel.1gpu, xmodel.2gpus and xmodel.4gpus.
# Those three differ only in their #SBATCH headers. Slurm reads the headers from
# the submitted file itself, so each script keeps its own and everything below
# them lives here.
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
# Sourcing this file also installs an ERR trap, so a command that fails under
# `set -e` names itself instead of ending the job in silence.
#
# xmodel.cpu stands alone and does not source this file. The two stacks share
# .buildkite/LocalPreferences.toml, so only one of a cpu job and a gpu job can
# be prepared at a time. Keeping the scripts separate keeps that visible. See F5
# in gpu_runscript_plan.md.

# ---------------------------------------------------------------------------
# Say which command ended the job.
#
# Everything below runs under `set -euo pipefail`, where a failing command ends
# the job at once and prints nothing of its own. A pipeline killed by SIGPIPE,
# or a tool whose complaint went to a discarded stderr, then reads as the job
# stopping for no reason a few seconds in. The log ends mid-check with no sign
# of which line was last. This trap gives every such exit a file, a line and a
# status.
#
# `set -E` is what makes it fire. Shell functions inherit an ERR trap only under
# `-E`, and every step of this file is a function.
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

# The srun flags that place each rank on the cores next to its GPU. The
# diagnostics and the launch use the same set, so what the diagnostics report is
# the mapping the run actually gets.
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
    # runscripts/levante_stacks.env, the same file setup-julia-levante.tcsh
    # builds the depot from. Reading it here keeps the runscript on the same MPI
    # that the depot's OpenMPI_jll override points at.
    #
    # The rank wrapper sits between srun and the command, so each rank narrows
    # itself onto the cores and memory local to its GPU. srun on its own widens
    # every task's cpuset to a NUMA pair under --exclusive, and half of that
    # pair is remote.
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

    # Exported before the version check below, so every Julia process in this
    # job resolves packages out of the GPU depot, where the OpenMPI_jll override
    # lives. That covers the checks as well as the ranks.
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

    # The `.buildkite` environment pins dependencies per Julia minor version, in
    # Manifest-v<major>.<minor>.toml. A Julia of another minor version ignores
    # that manifest and re-resolves the dependency graph. That usually surfaces
    # much later as a MethodError while the configuration is built, so check the
    # version here and fail before queueing any work.
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

    # One Julia thread per rank, held at 1 rather than ${SLURM_CPUS_PER_TASK}.
    # With CLIMACOMMS_DEVICE=CUDA every tendency and dynamics kernel runs on the
    # device, since src/config/type_getters.jl makes the ClimaComms device one
    # exclusive choice. The 16 cores a rank owns are there for driver threads,
    # I/O and GC headroom. Extra Julia worker threads would only contend for
    # them. Pinning the value here also stops a larger cpus-per-task from
    # quietly starting 16 threads.
    export JULIA_NUM_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export MKL_NUM_THREADS=1

    export CLIMACOMMS_DEVICE=CUDA

    # Overridable so the 1-GPU baseline can also be run as SINGLETON, to
    # separate what MPI costs at one rank from what the model costs.
    export CLIMACOMMS_CONTEXT="${CLIMACOMMS_CONTEXT:-MPI}"

    # Every variant assumes one rank per GPU, and levante_gpu_report_binding
    # enforces it per rank. Catching a mismatched #SBATCH header here is
    # cheaper.
    #
    # SLURM_NTASKS is the job total while SLURM_GPUS_ON_NODE is per node, so
    # divide to compare like with like. Comparing them directly would fail
    # `sbatch --nodes=2` against these headers for no reason.
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
    # gdr_copy is left out on purpose. The DKRZ recommendations list it, but
    # Levante's GPU nodes run without the gdrcopy kernel module loaded. UCX then
    # warns "transport 'gdr_copy' is not available" twice per rank and carries
    # on. Leaving it out keeps the log quiet and changes nothing else.
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
    # the preferences file, rather than the depot, settles which stack the
    # project points at. Selecting the GPU depot leaves it untouched. A
    # `setup-julia-levante.tcsh cpu` run after a gpu run leaves the GPU depot
    # intact while rewriting the project's MPIPreferences libmpi to the gcc Open
    # MPI and dropping the CUDA_Runtime_jll pin. That surfaces only when MPI or
    # CUDA misbehaves deep inside the run, so check it here, where the fix is
    # one command.
    #
    # The expected libmpi comes from the module actually loaded, the same value
    # setup-julia-levante.tcsh records. So this compares the stack in the
    # environment against the stack in the preferences, with no second hardcoded
    # copy to keep in step.
    # ---------------------------------------------------------------------------

    # `|| mpi_libdir=""` lets a missing or broken mpicc reach the check below.
    # Otherwise `set -o pipefail` hands the failure to `set -e` and the job ends
    # before the message that says which module was loaded.
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

        # The cpu setup path deletes this table outright, so a missing table is
        # a second, independent sign that the cpu stack was configured last.
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
    # setup-julia-levante.tcsh promises exactly this, so a driver upgrade needs
    # only a re-run of setup and no version typed in by hand. It is cheap here
    # because the batch script already runs on a GPU node.
    #
    # A toolkit newer than the driver is the fatal direction. CUDA minor version
    # compatibility can break under the CUDA-aware MPI in the nvhpc stack, which
    # is why select-cuda-runtime.jl picks the newest toolkit at or below the
    # driver's version.
    # ---------------------------------------------------------------------

    if command -v nvidia-smi >/dev/null 2>&1; then
        local driver_cuda pinned_cuda newest smi

        # nvidia-smi's output is read in full before it is matched, instead of
        # being piped into `grep -m1`. `grep -m1` closes the pipe on its first
        # match, near the top of a report thousands of lines long. nvidia-smi
        # then dies of SIGPIPE and the pipeline exits 141. Under
        # `set -o pipefail` that status becomes the assignment's, and `set -e`
        # ends the job right here. It ends in silence too, because the
        # broken-pipe message goes to the discarded stderr.
        smi="$(nvidia-smi -q 2>/dev/null)" || smi=""

        # "CUDA Version   : 13.0" -> "13.0". awk reads the here-string to the
        # end, so every pipe stays open until the input is exhausted.
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
            # Warn and carry on. The check below is a convenience, and a job
            # that cannot reach the driver is as well off as one on a node with
            # no nvidia-smi. Saying so beats skipping in silence.
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
    # The srun flags here mirror the launch below exactly, so the binding
    # reported is the binding the run gets.
    #
    # Two things are checked per rank:
    #
    #   1. Exactly one GPU is visible. Timings alone hide this one. If Slurm's
    #      topology detection hands every rank all four devices, CUDA.jl
    #      defaults each to device 0 and four ranks serialise onto one GPU. The
    #      run completes and the numbers are simply bad. Hard failure.
    #   2. The rank's cores are the ones local to that GPU, read from sysfs. The
    #      trailing columns of `nvidia-smi topo -m` shift between driver
    #      versions, so a column-index parse picks the wrong field after an
    #      upgrade. Advisory: a mismatch means affinity failed to take, which
    #      earns a loud warning while the run stays usable.
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
            # Ask numactl, not the cgroup. Mems_allowed_list is the cgroup
            # allowed set and reports 0-7 whatever the binding is, because
            # numactl --membind works by setting an MPOL_BIND policy on the
            # process. A correctly bound rank reads as unbound through that
            # field.
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

            # Compare the affinity in force against the core set the wrapper
            # exported, which is the set it asked for. Slurm may withhold the
            # SMT siblings, leaving a correctly bound rank on a strict subset of
            # the GPU-local cores. Comparing against sysfs directly would call
            # that a mismatch.
            wanted="${LEVANTE_RANK_BOUND_CPUS:-}"

            if [[ -n "${wanted}" ]]; then
                if [[ "${cpus}" == "${wanted}" ]]; then
                    verdict="MATCH"
                else
                    verdict="MISMATCH -- bound to ${wanted}, running on ${cpus}"
                fi
            elif [[ "${local_cpus}" == "unknown" ]]; then
                verdict="UNCHECKED"
            elif [[ "${cpus}" != "${local_cpus}" ]]; then
                verdict="UNBOUND -- the wrapper did not bind this rank; see its warning above"
            else
                verdict="MATCH"
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
            # at the system Open MPI, so HDF5_jll, NetCDF_jll and
            # TempestRemap_jll load the same libmpi as MPI.jl. Should the
            # override miss, through the wrong depot or a stale Overrides.toml,
            # a second Open MPI loads from the artifact store and the two
            # collide. setup-julia-levante.tcsh asserts this at setup time.
            # Repeating it here catches a job that ran with the wrong depot.
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

    # Load once, serially. The first import builds the precompile cache, and
    # doing that under srun makes every rank race for the same lock files. This
    # step also fails legibly when the environment was never instantiated for
    # this Julia version. Instantiate on a login node, since compute nodes
    # usually have no network access.
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

    # `set -e` is lifted around srun, so a failing run still reports its exit
    # status and logs its end time.
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
