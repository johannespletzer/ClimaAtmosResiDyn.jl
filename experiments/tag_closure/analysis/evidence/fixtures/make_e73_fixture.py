"""Build the small, durable E73 regression fixture from the real run outputs.

    python3 make_e73_fixture.py

Run once, by hand, from the login node with python/3.12 loaded. Reads the
real E73 inputs on scratch (read-only) and writes a trimmed copy of each
file under fixtures/e73/{reference,run}/, keeping only the time steps at
0, 1, 6, 12 and 24 hours (all 30 z levels, since the metrics are column
sums). compare_runs.py only ever looks at the requested hours, so trimming
the other 20 time steps changes nothing it reports; test_compare_runs.py's
E73 regression test runs against this fixture instead of scratch, which is
not durable. This script is not part of the test run itself -- it is the
one-off tool that made the fixture checked into the repo.

The repo's .gitignore ignores '*.nc', so a second one-off step dumps the
trimmed files this script writes into reference.npz/run.npz (see e73/data.py)
and deletes the '*.nc' files again; only the .npz arrays and the two '.yml'
files are committed. To regenerate the fixture from scratch: run this
script, then re-dump to .npz with a short numpy script reading each
'<var>_1h_inst.nc' back with netCDF4 and np.savez-ing the arrays (see
data.py's docstring), then delete the '*.nc' files.
"""
from pathlib import Path

from netCDF4 import Dataset

REFERENCE_SRC = Path(
    "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/v3_upd_copies/output_0000"
)
RUN_SRC = Path(
    "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/v3_upd_default/output_0002"
)
OUT = Path(__file__).resolve().with_name("e73")

# rhoa, ta, arup, waup are E73's parent set; the eight are E73's tags.
PARENT_STEMS = ["rhoa", "ta", "arup", "waup"]
TAG_STEMS = [
    "e_src_strat", "e_src_tropo", "e_src_rad", "e_src_sfc",
    "e_src_sub", "e_src_mp", "e_src_new_strat", "e_src_new_tropo",
]
KEEP_HOURS = [0, 1, 6, 12, 24]


def trim_file(src_path, dst_path):
    with Dataset(src_path) as src:
        src.set_auto_mask(False)
        time = src.variables["time"][:]
        keep_idx = [int(i) for i in range(len(time)) if int(time[i]) // 3600 in KEEP_HOURS]
        assert len(keep_idx) == len(KEEP_HOURS), (src_path, time[:])
        with Dataset(dst_path, "w", format="NETCDF4") as dst:
            for name, dim in src.dimensions.items():
                size = len(keep_idx) if name == "time" else dim.size
                dst.createDimension(name, None if dim.isunlimited() else size)
            for name, var in src.variables.items():
                new_var = dst.createVariable(name, var.dtype, var.dimensions)
                new_var.setncatts({k: var.getncattr(k) for k in var.ncattrs()})
                data = var[:]
                if "time" in var.dimensions:
                    axis = var.dimensions.index("time")
                    data = data.take(keep_idx, axis=axis)
                new_var[:] = data
            dst.setncatts({k: src.getncattr(k) for k in src.ncattrs()})


def main():
    # compare_runs.py refuses any directory not literally named output_XXXX
    # (see resolve_output_dir), so the fixture must use that name too.
    ref_dir = OUT / "reference" / "output_0000"
    run_dir = OUT / "run" / "output_0000"
    ref_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)
    for stem in PARENT_STEMS + TAG_STEMS:
        name = f"{stem}_1h_inst.nc"
        trim_file(REFERENCE_SRC / name, ref_dir / name)
        trim_file(RUN_SRC / name, run_dir / name)
    ref_yml = sorted(REFERENCE_SRC.glob("*.yml"))[0]
    run_yml = sorted(RUN_SRC.glob("*.yml"))[0]
    (ref_dir / ref_yml.name).write_text(ref_yml.read_text())
    (run_dir / run_yml.name).write_text(run_yml.read_text())
    print(f"wrote fixture under {OUT}")


if __name__ == "__main__":
    main()
