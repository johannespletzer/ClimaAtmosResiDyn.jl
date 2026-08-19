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
    exec numactl --physcpubind="${cpus}" --membind="${numa}" "$@"
fi

if command -v taskset >/dev/null 2>&1; then
    [[ -n "${numa}" && "${numa}" != "-1" ]] ||
        levante_warn "GPU ${bdf} reports no NUMA node; binding cores only"
    exec taskset --cpu-list "${cpus}" "$@"
fi

levante_warn "neither numactl nor taskset is available"
exec "$@"
