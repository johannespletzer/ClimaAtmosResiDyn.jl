#!/usr/bin/env bash
#
# Pin this rank to the cores and memory local to the GPU srun handed it, then
# exec the real command.
#
# Why this exists, measured on a Levante GPU node with
# --exclusive --gpus-per-node=4 --cpus-per-task=16
# --gpu-bind=closest --cpu-bind=verbose,cores --distribution=block:block:
#
#   rank=0 gpu-numa=1  cores=0-31,128-159    gpu-local-cores=16-31,144-159
#   rank=1 gpu-numa=3  cores=32-63,160-191   gpu-local-cores=48-63,176-191
#   rank=2 gpu-numa=5  cores=64-95,192-223   gpu-local-cores=80-95,208-223
#   rank=3 gpu-numa=7  cores=96-127,224-255  gpu-local-cores=112-127,240-255
#
# --gpu-bind=closest worked: every rank got a distinct, correctly-ordered GPU.
# The CPU side did not. --exclusive hands the job the whole node and Slurm
# divides all 256 logical CPUs among the 4 tasks, so --cpus-per-task=16 does
# not narrow anything: each rank receives 32 physical cores spanning an
# even/odd NUMA pair, of which only the odd half is local to its GPU. Memory
# was not bound at all (Mems_allowed_list was 0-7 for every rank).
#
# Each rank's allocation is a strict superset of the set it wants, so it can be
# narrowed from inside the cgroup. That is what this wrapper does, and it is
# the pattern DKRZ use for ICON. Deriving the target from the GPU's own sysfs
# entry rather than a hardcoded NUMA list keeps it correct for the 1- and
# 2-GPU variants, and across a node topology change, without anyone updating a
# table.
#
# Binding is best-effort: a rank that cannot determine its topology runs
# unbound and says so, rather than failing the job.

set -uo pipefail

levante_warn() {
    echo "rank ${SLURM_LOCALID:-?}: $* -- running unbound" >&2
}

if [[ $# -eq 0 ]]; then
    echo "usage: $(basename "$0") <command> [args...]" >&2
    exit 2
fi

if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
    levante_warn "no CUDA_VISIBLE_DEVICES"
    exec "$@"
fi

# nvidia-smi reports an 8-digit PCI domain (00000000:44:00.0); sysfs uses 4
# (0000:44:00.0). Only the rank's own GPU is visible, so head -1 is it.
bdf="$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -1)"
bdf="$(tr 'A-F' 'a-f' <<< "${bdf#0000}")"

if [[ -z "${bdf}" ]]; then
    levante_warn "could not read the GPU's PCI address"
    exec "$@"
fi

cpus="$(cat "/sys/bus/pci/devices/${bdf}/local_cpulist" 2>/dev/null || true)"
numa="$(cat "/sys/bus/pci/devices/${bdf}/numa_node" 2>/dev/null || true)"

if [[ -z "${cpus}" ]]; then
    levante_warn "no local_cpulist for ${bdf}"
    exec "$@"
fi

# ---------------------------------------------------------------------------
# Bind to the GPU's local cores that this rank was actually given, not to all
# of them.
#
# sysfs lists the hardware's view: every logical CPU near the GPU, SMT
# siblings included. Slurm's cpuset need not contain all of those --
# `--hint=nomultithread` hands the rank the physical cores and keeps their
# siblings out, and a non-exclusive allocation narrows it further.
#
# The difference is fatal rather than cosmetic, because numactl parses
# `--physcpubind` with numa_parse_cpustring(), which resolves against the
# current cpuset and returns nothing at all for a list reaching outside it.
# numactl then prints "<16-31,144-159> is invalid" on stdout, dumps its usage
# on stderr and exits 1 -- and since we exec it, that 1 is the rank's exit
# status. srun kills the job on it, which is the opposite of the best-effort
# binding described above.
# ---------------------------------------------------------------------------

levante_cpu_intersection() {
    # Print the CPUs in both lists, in the same "0-3,8" form the kernel uses.
    # Empty output means the two do not overlap.
    awk -v a="$1" -v b="$2" '
        function expand(list, set,   n, i, parts, range, lo, hi, j) {
            n = split(list, parts, ",")
            for (i = 1; i <= n; i++) {
                if (parts[i] == "") continue
                if (parts[i] ~ /-/) {
                    split(parts[i], range, "-")
                    lo = range[1] + 0
                    hi = range[2] + 0
                } else {
                    lo = parts[i] + 0
                    hi = lo
                }
                for (j = lo; j <= hi; j++) {
                    set[j] = 1
                    if (j > max) max = j
                }
            }
        }
        function flush(   piece) {
            piece = (start == last) ? start : start "-" last
            out = out (out == "" ? "" : ",") piece
            start = -1
        }
        BEGIN {
            expand(a, A)
            expand(b, B)
            start = -1
            for (i = 0; i <= max; i++) {
                if ((i in A) && (i in B)) {
                    if (start < 0) start = i
                    last = i
                } else if (start >= 0) {
                    flush()
                }
            }
            if (start >= 0) flush()
            print out
        }
    '
}

allowed="$(awk '/Cpus_allowed_list/ {print $2}' /proc/self/status)"
bind_cpus="$(levante_cpu_intersection "${cpus}" "${allowed}")"

if [[ -z "${bind_cpus}" ]]; then
    levante_warn "none of GPU ${bdf}'s local cores (${cpus}) are in this rank's allocation (${allowed})"
    exec "$@"
fi

# What the binding report checks itself against: it compares the affinity it
# observes with the set asked for here, and so catches a binding that did not
# take.
export LEVANTE_RANK_BOUND_CPUS="${bind_cpus}"

# ---------------------------------------------------------------------------
# Pick the InfiniBand HCA attached to the same NUMA node as this GPU.
#
# Only for multi-node jobs. Within a node, UCX_TLS lists cuda_ipc, cma and mm,
# so rank pairs never reach an HCA and constraining the device would be pure
# superstition. Across nodes a rank that talks through a non-local HCA pays an
# extra fabric hop.
#
# The device is found by matching NUMA nodes through sysfs rather than by
# assuming SLURM_LOCALID indexes the HCAs in the same order as the GPUs. An
# explicit UCX_NET_DEVICES in the environment is left alone, and a rank that
# finds no match leaves the variable unset so UCX chooses for itself -- a
# suboptimal device beats no device.
# ---------------------------------------------------------------------------

if (( ${SLURM_JOB_NUM_NODES:-1} > 1 )) &&
   [[ -z "${UCX_NET_DEVICES:-}" && -n "${numa}" && "${numa}" != "-1" ]]; then
    for _ib in /sys/class/infiniband/*; do
        [[ -r "${_ib}/device/numa_node" ]] || continue
        [[ "$(cat "${_ib}/device/numa_node")" == "${numa}" ]] || continue

        # Prefer an ACTIVE port; fall back to the lowest-numbered one.
        _port=""
        for _p in "${_ib}"/ports/*; do
            [[ -r "${_p}/state" ]] || continue
            [[ -z "${_port}" ]] && _port="$(basename "${_p}")"
            if grep -qi 'ACTIVE' "${_p}/state" 2>/dev/null; then
                _port="$(basename "${_p}")"
                break
            fi
        done

        export UCX_NET_DEVICES="$(basename "${_ib}"):${_port:-1}"
        break
    done

    [[ -n "${UCX_NET_DEVICES:-}" ]] ||
        echo "rank ${SLURM_LOCALID:-?}: no HCA on NUMA node ${numa}; leaving UCX to choose" >&2
fi

# numactl binds memory as well as cores, which matters here: without --membind
# every rank's Mems_allowed_list spans all eight domains. taskset is the
# fallback and binds cores only.
if [[ -n "${numa}" && "${numa}" != "-1" ]] && command -v numactl >/dev/null 2>&1; then
    # Probed with `true` before the exec. Anything numactl still refuses would
    # otherwise become this rank's exit status and take the job down with it.
    # 2>&1 because numactl names the offending argument on stdout and prints
    # its usage on stderr, so only the pair of them identifies the problem.
    if numactl_error="$(numactl --physcpubind="${bind_cpus}" \
                                --membind="${numa}" true 2>&1)"
    then
        exec numactl --physcpubind="${bind_cpus}" --membind="${numa}" "$@"
    fi

    echo "rank ${SLURM_LOCALID:-?}: numactl refused --physcpubind=${bind_cpus}" \
         "--membind=${numa} (${numactl_error%%$'\n'*}) -- falling back to taskset" >&2
fi

if command -v taskset >/dev/null 2>&1; then
    [[ -n "${numa}" && "${numa}" != "-1" ]] ||
        levante_warn "GPU ${bdf} reports no NUMA node; binding cores only"
    exec taskset --cpu-list "${bind_cpus}" "$@"
fi

levante_warn "neither numactl nor taskset is available"
exec "$@"
