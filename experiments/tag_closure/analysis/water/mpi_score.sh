#!/usr/bin/env bash
#
# W59, criterion 3 on two MPI ranks: score the six runs of
# design/MPI_PARITY.md. Run it on a login node after the jobs end:
#
#   RUN_TREE=../ClimaAtmosResiDyn-mpi-run \
#       experiments/tag_closure/analysis/water/mpi_score.sh [OUT_DIR]
#
# Judged (the pass rule): for each mode, default and copies, on two ranks,
#   1. every field of the untagged run's checkpoints equals the tagged run's
#      bit for bit, at every checkpoint (mpi_parity.jl parity);
#   2. every NetCDF diagnostic the untagged run writes equals the tagged run's
#      bit for bit, at every output time (parity_untagged.py).
# Reported only: the same two checks on one rank, and one rank against two
# for every run (mpi_parity.jl report).
#
# Each comparison's output goes to OUT_DIR (default
# experiments/tag_closure/output/w59_mpi). The last line says PASS or FAIL.

set -uo pipefail

REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
: "${RUN_TREE:?set RUN_TREE to the run tree at the model commit}"
RUN_TREE="$(cd "${RUN_TREE}" && pwd)"
OUT="${1:-${REC}/experiments/tag_closure/output/w59_mpi}"
RUNS="${RUNS:-/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output}"
SCRIPTS="${REC}/experiments/tag_closure/analysis/water"
mkdir -p "${OUT}"

source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
module load python/3.12
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu

dir() { echo "${RUNS}/w59_mpi_$1/output_active"; }

julia_cmp() {
    julia +1.11 --startup-file=no --project="${RUN_TREE}/.buildkite" \
        "${SCRIPTS}/mpi_parity.jl" "$@"
}

verdict=PASS
for ranks in 2 1; do
    for mode in default copies; do
        name="${mode}_r${ranks}"
        julia_cmp parity "$(dir untagged_r${ranks})" "$(dir ${name})" \
            > "${OUT}/state_${name}.txt" 2>&1
        state_status=$?
        python3 "${SCRIPTS}/parity_untagged.py" \
            "$(dir untagged_r${ranks})" "$(dir ${name})" \
            > "${OUT}/netcdf_${name}.txt" 2>&1
        nc_status=$?
        nc_line="$(grep '^RESULT' "${OUT}/netcdf_${name}.txt" || echo 'RESULT missing')"
        # parity_untagged.py prints DIFFERS for each field that differs, and
        # fails with a traceback when a file is missing in the tagged run.
        if [[ ${nc_status} -eq 0 ]] && ! grep -q '^DIFFERS' "${OUT}/netcdf_${name}.txt" \
            && [[ "${nc_line}" != "RESULT missing" ]] \
            && [[ "${nc_line}" != "RESULT 0 fields"* ]]; then
            nc_verdict=PASS
        else
            nc_verdict=FAIL
        fi
        state_verdict="$(tail -n 1 "${OUT}/state_${name}.txt")"
        echo "${name}: state: ${state_verdict}"
        echo "${name}: netcdf: ${nc_verdict}, ${nc_line}"
        if [[ ${ranks} -eq 2 ]]; then
            [[ ${state_status} -eq 0 && ${nc_verdict} == PASS ]] || verdict=FAIL
        fi
    done
done

for mode in untagged default copies; do
    julia_cmp report "$(dir ${mode}_r1)" "$(dir ${mode}_r2)" \
        > "${OUT}/ranks_${mode}.txt" 2>&1
    echo "one rank against two, ${mode}: ${OUT}/ranks_${mode}.txt"
done

# Reported only: the closure check's largest |relative| and |gross_relative|
# over the run, for each tagged run.
for name in default_r1 default_r2 copies_r1 copies_r2; do
    python3 - "$(dir ${name})/water_tag_closure.csv" "${name}" <<'EOF'
import csv, sys
path, name = sys.argv[1], sys.argv[2]
try:
    rows = list(csv.DictReader(open(path)))
    worst = max(abs(float(r["relative"])) for r in rows)
    gross = max(abs(float(r["gross_relative"])) for r in rows)
    print(f"closure {name}: {len(rows)} rows, largest |relative| {worst:.3e}, "
          f"largest |gross_relative| {gross:.3e}")
except Exception as error:
    print(f"closure {name}: not read ({error})")
EOF
done

# Reported only: the water the untagged two-rank run holds, as the coverage
# of design section 2 (largest value over space at each output time).
python3 - "$(dir untagged_r2)" <<'EOF'
import sys
import netCDF4 as nc, numpy as np
d = sys.argv[1]
for var in ("hus", "clw", "cli", "husra", "hussn", "pr", "hfls"):
    try:
        with nc.Dataset(f"{d}/{var}_30m_inst.nc") as f:
            a = np.asarray(f[var][:])
        peaks = [float(np.max(np.abs(a[i]))) for i in range(a.shape[0])]
        print(f"coverage {var}: largest |value| at 0 h {peaks[0]:.3e}, at the end {peaks[-1]:.3e}, over the run {max(peaks):.3e}")
    except Exception as error:
        print(f"coverage {var}: not read ({error})")
EOF

echo "W59 two-rank parity (judged): ${verdict}"
