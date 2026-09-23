"""G3 1.3: mutation tests for compare_runs.py.

    python3 test_compare_runs.py
    python3 -m unittest test_compare_runs -v

Builds two synthetic run directories per test, under
`$SCRATCH/claude_work/g3_evidence/test_runs/`, by copying a few real files
(`ta`, `rhoa`, `e_src_sfc`, `e_src_rad`, `e_src_mp`, plus the YAML) from
`v3_upd_copies/output_0000`. Only the copies are mutated, with netCDF4 in
`r+` mode; the source run on scratch is never opened for writing. Each test
runs `compare_runs.py` as a subprocess (the real CLI contract, including its
exit code) and checks the outcome the spec requires:

  1. an identical copy is bitwise identical and every metric is 0 (or the
     explicit "ref zero" case, for the tag that is zero everywhere);
  2. a deleted variable file fails;
  3. one shifted timestamp fails;
  4. a truncated run fails without --hours, and passes with --hours 1,6 and
     the prefix notice;
  5. a moved coordinate fails;
  6. a flipped signed zero is reported as "not bitwise, signed-zero-only",
     with a note that plain np.array_equal would call it equal, and this is
     not a hard failure.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
from pathlib import Path

from netCDF4 import Dataset

# netCDF4's own C extension triggers a NumPy 2.5 shape-assignment
# DeprecationWarning on every scalar write; it is a netCDF4/NumPy version
# interaction, not a defect in the mutations below, so it is silenced here.
warnings.filterwarnings("ignore", category=DeprecationWarning)

SOURCE_RUN = Path(
    "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/v3_upd_copies/output_0000"
)
SCRIPT = Path(__file__).resolve().with_name("compare_runs.py")
TMP_BASE = Path("/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3_evidence/test_runs")
FILES_TO_COPY = [
    "ta_1h_inst.nc",
    "rhoa_1h_inst.nc",
    "e_src_sfc_1h_inst.nc",
    "e_src_rad_1h_inst.nc",
    "e_src_mp_1h_inst.nc",
    "v3_upd_copies.yml",
]


def make_run_pair(tmp_root):
    """A fresh reference (output_0000) and run (output_0001) directory, each
    holding an independent copy of the minimal file set."""
    ref = tmp_root / "output_0000"
    run = tmp_root / "output_0001"
    ref.mkdir(parents=True)
    run.mkdir(parents=True)
    for name in FILES_TO_COPY:
        shutil.copy2(SOURCE_RUN / name, ref / name)
        shutil.copy2(SOURCE_RUN / name, run / name)
    return ref, run


def truncate_file(path, n_times):
    """Rewrite one '<var>_1h_inst.nc' file with only its first n_times time
    steps. netCDF4 cannot shrink an already-written unlimited dimension in
    place, so this builds a fresh file and replaces the original."""
    tmp_path = path.with_name(path.name + ".tmp")
    with Dataset(path) as src, Dataset(tmp_path, "w", format="NETCDF4") as dst:
        src.set_auto_mask(False)
        for name, dim in src.dimensions.items():
            dst.createDimension(name, None if dim.isunlimited() else dim.size)
        for name, var in src.variables.items():
            new_var = dst.createVariable(name, var.dtype, var.dimensions)
            new_var.setncatts({k: var.getncattr(k) for k in var.ncattrs()})
            data = var[:]
            if "time" in var.dimensions:
                axis = var.dimensions.index("time")
                sl = [slice(None)] * data.ndim
                sl[axis] = slice(0, n_times)
                data = data[tuple(sl)]
            new_var[:] = data
        dst.setncatts({k: src.getncattr(k) for k in src.ncattrs()})
    path.unlink()
    tmp_path.rename(path)


def truncate_run(directory, n_times):
    for path in sorted(directory.glob("*_1h_inst.nc")):
        truncate_file(path, n_times)


def run_compare(ref, run, extra_args=(), json_path=None):
    cmd = [sys.executable, str(SCRIPT), "--reference", str(ref), "--run", str(run)]
    if json_path is not None:
        cmd += ["--json", str(json_path)]
    cmd += list(extra_args)
    return subprocess.run(cmd, capture_output=True, text=True)


class CompareRunsMutationTests(unittest.TestCase):
    def setUp(self):
        TMP_BASE.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(prefix="case_", dir=TMP_BASE))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_1_identical_copy_is_bitwise_and_zero(self):
        ref, run = make_run_pair(self.tmp)
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

        report = json.loads(json_path.read_text())
        for name, result in report["parent_parity"].items():
            self.assertTrue(result["identical"], msg=f"{name}: {result}")

        for tag, per_hour in report["tag_metrics"].items():
            for hour, row in per_hour.items():
                self.assertEqual(row["max_abs_error"], 0.0, msg=f"{tag}@{hour}: {row}")
                if row["ref_zero"]:
                    self.assertTrue(row["run_zero"], msg=f"{tag}@{hour}: {row}")
                    self.assertEqual(row["integral_ref"], 0.0)
                else:
                    self.assertEqual(row["rel_integral_change"], 0.0, msg=f"{tag}@{hour}: {row}")
                    self.assertEqual(row["L1_mass_weighted"], 0.0, msg=f"{tag}@{hour}: {row}")
                    self.assertEqual(row["Linf_peak_normalized"], 0.0, msg=f"{tag}@{hour}: {row}")

    def test_2_deleted_variable_fails(self):
        ref, run = make_run_pair(self.tmp)
        (run / "e_src_rad_1h_inst.nc").unlink()
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("e_src_rad", proc.stderr)

    def test_3_shifted_timestamp_fails(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(run / "rhoa_1h_inst.nc", "r+") as ds:
            ds["time"][5] += 1
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("time", proc.stderr)

    def test_4_truncated_run_fails_without_hours_passes_with(self):
        ref, run = make_run_pair(self.tmp)
        truncate_run(run, 13)

        proc_no_hours = run_compare(ref, run)
        self.assertNotEqual(proc_no_hours.returncode, 0)
        self.assertIn("--hours", proc_no_hours.stderr)

        proc_hours = run_compare(ref, run, extra_args=["--hours", "1,6"])
        self.assertEqual(proc_hours.returncode, 0, msg=proc_hours.stderr)
        self.assertIn("NOTICE", proc_hours.stdout)
        self.assertIn("common prefix of 13 times", proc_hours.stdout)

    def test_5_moved_coordinate_fails(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(run / "rhoa_1h_inst.nc", "r+") as ds:
            ds["z"][3] += 1e-6
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("z:", proc.stderr)

    def test_6_flipped_signed_zero_is_reported_not_fatal(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(ref / "ta_1h_inst.nc", "r+") as ds:
            ds["ta"][0, 0] = 0.0
        with Dataset(run / "ta_1h_inst.nc", "r+") as ds:
            ds["ta"][0, 0] = -0.0

        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertIn("not bitwise, signed-zero-only", proc.stdout)
        self.assertIn("np.array_equal would say equal", proc.stdout)

        report = json.loads(json_path.read_text())
        ta_result = report["parent_parity"]["ta"]
        self.assertFalse(ta_result["identical"])
        self.assertEqual(ta_result["n_diff"], 1)
        self.assertEqual(ta_result["signed_zero_only"], 1)
        self.assertTrue(ta_result["would_array_equal"])


if __name__ == "__main__":
    unittest.main()
