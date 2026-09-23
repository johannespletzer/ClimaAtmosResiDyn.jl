"""G3 WP0: tests for compare_runs.py, extended past the phase-1 review
(phase1_tools_review_2026-09-23.md, finding B1: "the tests do not pin any
metric"). Three groups:

  1. `CompareRunsCLIMutationTests` -- the original six CLI/subprocess tests
     (a real run pair copied from scratch, mutated with netCDF4), kept for
     the same refusals they always checked, plus new ones for S1-S5 and B2.
  2. `AnalyticMetricTests` -- pure Python calls into compare_runs.py's own
     functions (no subprocess, no files) with a nonuniform z grid and
     closed-form L1/Linf/rel_integral_change/max_abs_error/abs_L1, to 1e-12
     relative. This is what B1 asks for: a test that a wrong weight, a
     dropped Δz, or a pointwise-not-mass-weighted L∞ cannot pass.
  3. `SyntheticRunTests` -- full synthetic run pairs built with netCDF4 (not
     copied from any real run), covering the nonuniform grid end to end
     through the CLI, S1-S5, B2, --expect-parity, --judge (R5, including the
     small-tag boundary and the region/source split), and R12's
     --ladder-share on runs with different z grids.
  4. `E73RegressionTest` -- runs the CLI against the durable E73 fixture
     (fixtures/e73/, rebuilt from .npz arrays at test time, since '*.nc' is
     gitignored) and checks every tag/hour/metric and every parity verdict
     against the values recorded in fixtures/e73/expected_e73.py, which were
     frozen from a run that reproduced e73_reproduction.txt character for
     character (see fixtures/make_e73_fixture.py).

    python3 test_compare_runs.py
    python3 -m unittest test_compare_runs -v

After changing compare_runs.py, re-run mutation_check.py (same directory) to
see which of the mutations it injects are still caught; the count is
recorded in README.md.
"""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

# netCDF4's own C extension triggers a NumPy 2.5 shape-assignment
# DeprecationWarning on every scalar write; it is a netCDF4/NumPy version
# interaction, not a defect in the mutations below, so it is silenced here.
warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "compare_runs.py"

# compare_runs.py is imported directly (not just run as a subprocess) so the
# analytic tests can call its functions with hand-built numpy arrays.
spec = importlib.util.spec_from_file_location("compare_runs", SCRIPT)
compare_runs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare_runs)

sys.path.insert(0, str(HERE / "fixtures" / "e73"))
import data as e73_data  # noqa: E402
from expected_e73 import EXPECTED as E73_EXPECTED  # noqa: E402

SOURCE_RUN = Path(
    "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/v3_upd_copies/output_0000"
)
TMP_BASE = Path("/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3_evidence/test_runs")
FILES_TO_COPY = [
    "ta_1h_inst.nc",
    "rhoa_1h_inst.nc",
    "e_src_sfc_1h_inst.nc",
    "e_src_rad_1h_inst.nc",
    "e_src_mp_1h_inst.nc",
    "v3_upd_copies.yml",
]
# The real YAML lists 8 tags but only 3 tag files are copied above (kept
# minimal, as before); --tags pins the CLI to those 3 so it does not go
# looking for the other 5's files.
MINIMAL_TAGS = "sfc,rad,mp"


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
            vdata = var[:]
            if "time" in var.dimensions:
                axis = var.dimensions.index("time")
                sl = [slice(None)] * vdata.ndim
                sl[axis] = slice(0, n_times)
                vdata = vdata[tuple(sl)]
            new_var[:] = vdata
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


# --- Synthetic run builders ------------------------------------------------

DATE_UNITS = "seconds since 2010-01-01T00:00:00"


def write_column_file(path, varname, data, z, time, date, units, dtype="f8", date_units=DATE_UNITS):
    """A minimal '<var>_1h_inst.nc' with dims (z, time), matching what
    compare_runs.py reads: z/time/date coordinates, one data variable."""
    with Dataset(path, "w", format="NETCDF4") as ds:
        ds.createDimension("z", len(z))
        ds.createDimension("time", None)
        zv = ds.createVariable("z", "f8", ("z",))
        zv.units = "m"
        zv[:] = z
        tv = ds.createVariable("time", "f8", ("time",))
        tv.units = "s"
        tv[:] = time
        dv = ds.createVariable("date", "f8", ("time",))
        dv.units = date_units
        dv[:] = date
        var = ds.createVariable(varname, dtype, ("z", "time"))
        if units is not None:
            var.units = units
        var[:] = np.asarray(data, dtype=dtype)


def write_surface_file(path, varname, data, time, date, units, dtype="f8", date_units=DATE_UNITS):
    """A minimal '<var>_1h_inst.nc' with dims (time,) only -- a surface field."""
    with Dataset(path, "w", format="NETCDF4") as ds:
        ds.createDimension("time", None)
        tv = ds.createVariable("time", "f8", ("time",))
        tv.units = "s"
        tv[:] = time
        dv = ds.createVariable("date", "f8", ("time",))
        dv.units = date_units
        dv[:] = date
        var = ds.createVariable(varname, dtype, ("time",))
        if units is not None:
            var.units = units
        var[:] = np.asarray(data, dtype=dtype)


def make_tag_yaml(family, tag_specs, z_max=350.0, float_type="Float64", mode_true=False, extra_lines=()):
    # z_max defaults to NONUNIFORM_Z's true top face (350 m), so a
    # synthetic run built with that grid passes the top-face check without
    # every caller having to know the derived value.
    """tag_specs: list of (name, has_region, source_or_None). Mirrors the
    real merged-YAML shape parse_tag_block expects: a 'key:' block of
    '- name: "..."' entries with an indented 'region:' and/or 'source:'
    child. The unused family's key is written 'key: ~', like the real
    generator writes it (both keys always present; only one is a list)."""
    key = "energy_source_tags" if family == "energy" else "water_tracers"
    other_key = "water_tracers" if family == "energy" else "energy_source_tags"
    mode_key = "energy_source_tag_updraft_copy" if family == "energy" else "water_tag_updraft_copy"
    lines = [f"{key}:"]
    for name, has_region, source in tag_specs:
        lines.append(f'  - name: "{name}"')
        if source is not None:
            lines.append(f'    source: "{source}"')
        if has_region:
            lines.append("    region:")
            lines.append("      width: 100.0")
            lines.append("      z_center: 750.0")
            lines.append('      type: "tanh_altitude"')
    lines.append(f"{other_key}: ~")
    lines.append(f'FLOAT_TYPE: "{float_type}"')
    lines.append(f"z_max: {z_max}")
    lines.append(f"{mode_key}: {'true' if mode_true else 'false'}")
    lines.extend(extra_lines)
    return "\n".join(lines) + "\n"


def write_synthetic_run(directory, *, z, time, date, column_vars, yaml_text, surface_vars=None, yaml_name="synthetic.yml"):
    """column_vars: {name: (data, units)}. surface_vars: {name: (data, units)}."""
    directory.mkdir(parents=True, exist_ok=True)
    for name, (data, units) in column_vars.items():
        write_column_file(directory / f"{name}_1h_inst.nc", name, data, z, time, date, units)
    for name, (data, units) in (surface_vars or {}).items():
        write_surface_file(directory / f"{name}_1h_inst.nc", name, data, time, date, units)
    (directory / yaml_name).write_text(yaml_text)


# The B1 nonuniform-grid example: centres 25, 100, 250 m give faces
# 0, 50, 150, 350 m (the face rule is z_f[0]=0, z_f[k+1]=2 z_c[k]-z_f[k]),
# so dz = 50, 100, 200 m -- a different value at every level, which kills
# both the np.gradient(z) and the dz=1 mutants.
NONUNIFORM_Z = np.array([25.0, 100.0, 250.0])
NONUNIFORM_DZ = np.array([50.0, 100.0, 200.0])  # closed form, checked in AnalyticMetricTests too


class CompareRunsCLIMutationTests(unittest.TestCase):
    def setUp(self):
        TMP_BASE.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(prefix="case_", dir=TMP_BASE))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_1_identical_copy_is_bitwise_and_zero(self):
        ref, run = make_run_pair(self.tmp)
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS], json_path=json_path)
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
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("e_src_rad", proc.stderr)

    def test_3_shifted_timestamp_fails(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(run / "rhoa_1h_inst.nc", "r+") as ds:
            ds["time"][5] += 1
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("time", proc.stderr)

    def test_3b_shifted_timestamp_in_a_non_rhoa_file_fails(self):
        """Kills the 'RunCoords disabled' mutant: a within-run inconsistency
        (a time shift in ta, not rhoa) must be caught even though rhoa is
        the file the weights are read from."""
        ref, run = make_run_pair(self.tmp)
        with Dataset(run / "ta_1h_inst.nc", "r+") as ds:
            ds["time"][5] += 1
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("time", proc.stderr)

    def test_4_truncated_run_fails_without_hours_passes_with(self):
        ref, run = make_run_pair(self.tmp)
        truncate_run(run, 13)

        proc_no_hours = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS])
        self.assertNotEqual(proc_no_hours.returncode, 0)
        self.assertIn("--hours", proc_no_hours.stderr)

        proc_hours = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS, "--hours", "1,6"])
        self.assertEqual(proc_hours.returncode, 0, msg=proc_hours.stderr)
        self.assertIn("NOTICE", proc_hours.stdout)
        self.assertIn("common prefix of 13 times", proc_hours.stdout)

    def test_5_moved_coordinate_fails(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(run / "rhoa_1h_inst.nc", "r+") as ds:
            ds["z"][3] += 1e-6
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("z:", proc.stderr)

    def test_6_flipped_signed_zero_is_reported_not_fatal(self):
        ref, run = make_run_pair(self.tmp)
        with Dataset(ref / "ta_1h_inst.nc", "r+") as ds:
            ds["ta"][0, 0] = 0.0
        with Dataset(run / "ta_1h_inst.nc", "r+") as ds:
            ds["ta"][0, 0] = -0.0

        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--tags", MINIMAL_TAGS], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertIn("not bitwise, signed-zero-only", proc.stdout)
        self.assertIn("np.array_equal would say equal", proc.stdout)

        report = json.loads(json_path.read_text())
        ta_result = report["parent_parity"]["ta"]
        self.assertFalse(ta_result["identical"])
        self.assertEqual(ta_result["n_diff"], 1)
        self.assertEqual(ta_result["signed_zero_only"], 1)
        self.assertTrue(ta_result["would_array_equal"])

    def test_7_output_active_refused(self):
        proc = run_compare(SOURCE_RUN.parent / "output_active", SOURCE_RUN)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("output_active", proc.stderr)

    def test_8_bare_run_root_refused(self):
        proc = run_compare(SOURCE_RUN.parent, SOURCE_RUN)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("explicit output_XXXX directory", proc.stderr)

    def test_9_same_directory_twice_refused(self):
        """S2: a pair that cannot be compared at all."""
        proc = run_compare(SOURCE_RUN, SOURCE_RUN)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("same directory", proc.stderr)


class AnalyticMetricTests(unittest.TestCase):
    """B1: closed-form values for compute_faces_and_dz and tag_row_metrics,
    called directly (no subprocess, no files), so a wrong weight or formula
    cannot hide behind file I/O."""

    def test_faces_and_dz_nonuniform(self):
        faces, dz = compare_runs.compute_faces_and_dz(NONUNIFORM_Z, "test")
        np.testing.assert_allclose(faces, [0.0, 50.0, 150.0, 350.0], rtol=0, atol=0)
        np.testing.assert_allclose(dz, NONUNIFORM_DZ, rtol=0, atol=0)

    def test_faces_and_dz_non_positive_thickness_dies(self):
        with self.assertRaises(SystemExit):
            compare_runs.compute_faces_and_dz(np.array([25.0, 20.0, 250.0]), "test")

    def test_tag_row_metrics_closed_form(self):
        # w = rho * dz = [1.2*50, 1.0*100, 0.8*200] = [60, 100, 160]
        rho = np.array([1.2, 1.0, 0.8])
        w = rho * NONUNIFORM_DZ
        q_ref = np.array([1.0, 2.0, 4.0])
        delta = np.array([0.1, -0.2, 0.05])
        q_run = q_ref + delta

        row = compare_runs.tag_row_metrics("t", 1, q_ref, q_run, w)

        integral_ref = 1 * 60 + 2 * 100 + 4 * 160  # 900
        integral_run = integral_ref + (0.1 * 60 - 0.2 * 100 + 0.05 * 160)  # 894
        abs_l1 = abs(0.1 * 60) + abs(-0.2 * 100) + abs(0.05 * 160)  # 34
        self.assertAlmostEqual(row["integral_ref"], integral_ref, delta=1e-9)
        self.assertAlmostEqual(row["integral_run_ref_weighted"], integral_run, delta=1e-9)
        self.assertAlmostEqual(row["abs_L1"], abs_l1, delta=1e-9)
        self.assertAlmostEqual(row["rel_integral_change"], (integral_run - integral_ref) / integral_ref, delta=1e-12)
        self.assertAlmostEqual(row["L1_mass_weighted"], abs_l1 / integral_ref, delta=1e-12)
        self.assertAlmostEqual(row["max_abs_error"], 0.2, delta=1e-12)
        self.assertAlmostEqual(row["Linf_peak_normalized"], 0.2 / 4.0, delta=1e-12)
        self.assertFalse(row["ref_zero"])

    def test_tag_row_metrics_perturbation_at_top_level_and_last_time_is_seen(self):
        """Kills 'tag metrics from the lowest level only' / a first-time-only
        bug: put the only difference at the top level, and read the last of
        several hours, then check the metrics see it."""
        w = np.array([60.0, 100.0, 160.0])
        q_ref = np.array([1.0, 2.0, 4.0])
        q_run = q_ref.copy()
        q_run[-1] += 0.5  # perturb only the top level
        row = compare_runs.tag_row_metrics("t", 24, q_ref, q_run, w)
        self.assertAlmostEqual(row["max_abs_error"], 0.5, delta=1e-12)
        self.assertAlmostEqual(row["Linf_peak_normalized"], 0.5 / 4.0, delta=1e-12)
        self.assertAlmostEqual(row["abs_L1"], 0.5 * 160.0, delta=1e-9)

    def test_tag_row_metrics_ref_zero_case(self):
        w = np.array([60.0, 100.0, 160.0])
        q_ref = np.zeros(3)
        q_run = np.zeros(3)
        row = compare_runs.tag_row_metrics("mp", 1, q_ref, q_run, w)
        self.assertTrue(row["ref_zero"])
        self.assertTrue(row["run_zero"])
        self.assertIsNone(row["rel_integral_change"])
        self.assertIsNone(row["L1_mass_weighted"])
        self.assertIsNone(row["Linf_peak_normalized"])
        self.assertEqual(row["integral_ref"], 0.0)

    def test_bit_compare_signed_zero(self):
        a = np.array([0.0, 1.0])
        b = np.array([-0.0, 1.0])
        result = compare_runs.bit_compare(a, b, "x")
        self.assertFalse(result["identical"])
        self.assertEqual(result["n_diff"], 1)
        self.assertEqual(result["signed_zero_only"], 1)
        self.assertTrue(result["would_array_equal"])

    def test_bit_compare_dtype_mismatch_dies(self):
        a = np.array([1.0], dtype="f8")
        b = np.array([1.0], dtype="f4")
        with self.assertRaises(SystemExit):
            compare_runs.bit_compare(a, b, "x")

    def test_parse_tag_block_region_source_and_both(self):
        text = make_tag_yaml(
            "water",
            [("tropo", True, None), ("evap", False, "surface_flux"), ("evap_tropo", True, "surface_flux")],
        )
        tags = compare_runs.parse_tag_block(text, "water_tracers")
        self.assertEqual(tags, [("tropo", True, False), ("evap", False, True), ("evap_tropo", True, True)])

    def test_detect_family_autodetects_water(self):
        text = make_tag_yaml("water", [("tropo", True, None)])
        self.assertEqual(compare_runs.detect_family(text), "water")


class SyntheticRunTests(unittest.TestCase):
    """Full synthetic run pairs, exercised through the real CLI (subprocess,
    real exit codes), covering everything the review's mutation table and
    R14 ask for that the six original CLI tests do not."""

    def setUp(self):
        TMP_BASE.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(prefix="synth_", dir=TMP_BASE))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def water_pair(self, *, ref_extra=None, run_extra=None, mode_true_ref=True, mode_true_run=False, ntimes=25):
        """A minimal water-family run pair on the nonuniform grid: two
        region tags (tropo, strat) and one source tag (evap), plus rhoa and
        hus. ref_extra/run_extra: functions(directory) for further mutation.
        ntimes defaults to 25 (hours 0..24, matching --hours' own default of
        1,6,12,24), so most tests need not pass --hours explicitly."""
        time = np.arange(ntimes) * 3600.0
        date = time.copy()
        rho = np.tile(np.array([1.2, 1.0, 0.8])[:, None], (1, ntimes))
        hus = np.tile(np.array([5.0, 4.0, 3.0])[:, None], (1, ntimes))
        tropo = np.tile(np.array([3.0, 0.5, 0.1])[:, None], (1, ntimes))
        strat = np.tile(np.array([0.5, 3.0, 2.5])[:, None], (1, ntimes))
        evap = np.tile(np.array([0.02, 0.01, 0.005])[:, None], (1, ntimes))
        res = np.zeros_like(hus)  # a tiny (here exactly zero) residual, so closure trivially passes

        yaml_text = make_tag_yaml(
            "water",
            [("tropo", True, None), ("strat", True, None), ("evap", False, "surface_flux")],
        )
        ref_yaml = make_tag_yaml(
            "water", [("tropo", True, None), ("strat", True, None), ("evap", False, "surface_flux")], mode_true=mode_true_ref
        )
        run_yaml = make_tag_yaml(
            "water", [("tropo", True, None), ("strat", True, None), ("evap", False, "surface_flux")], mode_true=mode_true_run
        )

        ref = self.tmp / "output_0000"
        run = self.tmp / "output_0001"
        common_vars = lambda: {
            "rhoa": (rho.copy(), "kg m^-3"),
            "hus": (hus.copy(), "kg kg^-1"),
            "q_tag_tropo": (tropo.copy(), "kg kg^-1"),
            "q_tag_strat": (strat.copy(), "kg kg^-1"),
            "q_tag_evap": (evap.copy(), "kg kg^-1"),
            "q_tag_res": (res.copy(), "kg kg^-1"),
        }
        write_synthetic_run(ref, z=NONUNIFORM_Z, time=time, date=date, column_vars=common_vars(), yaml_text=ref_yaml, yaml_name="ref.yml")
        write_synthetic_run(run, z=NONUNIFORM_Z, time=time, date=date, column_vars=common_vars(), yaml_text=run_yaml, yaml_name="run.yml")
        if ref_extra:
            ref_extra(ref)
        if run_extra:
            run_extra(run)
        return ref, run

    # --- nonuniform grid end to end (B1) ---

    def test_nonuniform_grid_end_to_end_matches_closed_form(self):
        ref, run = self.water_pair()
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--hours", "0,1"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        # identical files -> every metric is exactly 0
        for tag, per_hour in report["tag_metrics"].items():
            for h, row in per_hour.items():
                self.assertEqual(row["max_abs_error"], 0.0)
                self.assertEqual(row["rel_integral_change"], 0.0)

    def test_rho_differs_between_runs_weights_use_reference_rhoa_only(self):
        """Kills the 'weights from the run's rhoa' mutant directly against
        the real CLI. A uniform rescaling of rhoa cannot distinguish the two
        weight choices (the L1 ratio is scale-invariant), so rhoa is changed
        by a *non-proportional* amount between the runs (the profile shape
        changes, not just its magnitude), and q's delta varies by level too.
        L1_mass_weighted is then checked against the closed form computed
        with the reference's rhoa; using the run's rhoa instead gives a
        different number (checked by hand below)."""
        time = np.array([0.0, 3600.0])
        date = time.copy()
        rho_ref = np.tile(np.array([1.2, 1.0, 0.8])[:, None], (1, 2))
        rho_run = np.tile(np.array([2.0, 0.3, 1.5])[:, None], (1, 2))  # not proportional to rho_ref
        q_ref = np.tile(np.array([1.0, 2.0, 4.0])[:, None], (1, 2))
        delta = np.array([0.1, -0.2, 0.05])
        q_run = q_ref + delta[:, None]
        yaml_text = make_tag_yaml("water", [("t", True, None)])

        ref = self.tmp / "output_0000"
        run = self.tmp / "output_0001"
        write_synthetic_run(
            ref, z=NONUNIFORM_Z, time=time, date=date,
            column_vars={"rhoa": (rho_ref, "kg m^-3"), "q_tag_t": (q_ref, "kg kg^-1")},
            yaml_text=yaml_text, yaml_name="a.yml",
        )
        write_synthetic_run(
            run, z=NONUNIFORM_Z, time=time, date=date,
            column_vars={"rhoa": (rho_run, "kg m^-3"), "q_tag_t": (q_run, "kg kg^-1")},
            yaml_text=yaml_text, yaml_name="a.yml",
        )
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--hours", "0,1"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        row = report["tag_metrics"]["t"]["1"]
        # w_ref = rho_ref * dz = [60, 100, 160]; abs_L1 = |delta|.w_ref = 34;
        # abs_ref_weighted = q_ref.w_ref = 900; L1 = 34/900.
        self.assertAlmostEqual(row["L1_mass_weighted"], 34.0 / 900.0, delta=1e-12)

    # --- geometry refusals ---

    def test_non_column_geometry_refused(self):
        ref, run = self.water_pair()

        def write_blob(path, n_time):
            with Dataset(path, "w", format="NETCDF4") as ds:
                ds.createDimension("x", 2)
                ds.createDimension("time", None)
                ds.createVariable("time", "f8", ("time",))[:] = np.arange(n_time) * 3600.0
                ds.createVariable("date", "f8", ("time",))[:] = np.arange(n_time) * 3600.0
                v = ds.createVariable("blob", "f8", ("x", "time"))
                v[:] = np.zeros((2, n_time))

        write_blob(ref / "blob_1h_inst.nc", 25)
        write_blob(run / "blob_1h_inst.nc", 25)
        proc = run_compare(ref, run, extra_args=["--parent", "blob"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unsupported geometry", proc.stderr)

    def test_transposed_time_z_file_reads_correctly(self):
        """A file that happens to write (time, z) instead of (z, time) must
        still be read correctly (dimensions found by name)."""
        ref, run = self.water_pair()
        # Rewrite the run's hus with dims swapped to (time, z).
        with Dataset(run / "hus_1h_inst.nc") as src:
            src.set_auto_mask(False)
            data = np.array(src["hus"][:])
            z, time, date, units = np.array(src["z"][:]), np.array(src["time"][:]), np.array(src["date"][:]), src["hus"].units
        path = run / "hus_1h_inst.nc"
        path.unlink()
        with Dataset(path, "w", format="NETCDF4") as ds:
            ds.createDimension("z", len(z))
            ds.createDimension("time", None)
            zv = ds.createVariable("z", "f8", ("z",))
            zv.units = "m"
            zv[:] = z
            tv = ds.createVariable("time", "f8", ("time",))
            tv.units = "s"
            tv[:] = time
            dv = ds.createVariable("date", "f8", ("time",))
            dv.units = DATE_UNITS
            dv[:] = date
            var = ds.createVariable("hus", "f8", ("time", "z"))  # transposed on purpose
            var.units = units
            var[:] = data.T
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--hours", "0,1", "--allow-missing", "hus"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

    def test_top_face_disagrees_with_z_max_refused(self):
        ref, run = self.water_pair()
        text = (ref / "ref.yml").read_text().replace("z_max: 350.0", "z_max: 999.0")
        (ref / "ref.yml").write_text(text)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("z_max", proc.stderr)

    def test_date_change_within_one_run_refused(self):
        """A within-run inconsistency: rhoa's date no longer matches the
        other files of the same run (RunCoords)."""
        ref, run = self.water_pair()
        with Dataset(run / "rhoa_1h_inst.nc", "r+") as ds:
            ds["date"][1] += 1
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("date", proc.stderr)

    def test_date_change_between_runs_refused(self):
        """Kills the 'date check removed (equal-length branch)' mutant
        directly: every file of the run is shifted together (so the
        within-run RunCoords check alone cannot catch it), and the two runs
        have the same time array length, so the equal-length branch of
        check_time_and_z is what must refuse this."""
        time = np.array([0.0, 3600.0])
        yaml_text = make_tag_yaml("water", [("t", True, None)])
        ref = self.tmp / "output_0000"
        run = self.tmp / "output_0001"
        common = {"rhoa": (np.ones((3, 2)), "kg m^-3"), "q_tag_t": (np.ones((3, 2)), "kg kg^-1")}
        write_synthetic_run(ref, z=NONUNIFORM_Z, time=time, date=time.copy(), column_vars=common, yaml_text=yaml_text, yaml_name="a.yml")
        write_synthetic_run(run, z=NONUNIFORM_Z, time=time, date=time.copy() + 1.0, column_vars=common, yaml_text=yaml_text, yaml_name="a.yml")
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("date", proc.stderr)

    # --- S1: parent parity union ---

    def test_s1_parent_field_present_in_only_one_run_refused(self):
        def add_extra_field(directory):
            write_column_file(
                directory / "clw_1h_inst.nc", "clw", np.zeros((3, 2)), NONUNIFORM_Z, np.arange(2) * 3600.0, np.arange(2) * 3600.0, "kg kg^-1"
            )

        ref, run = self.water_pair(ref_extra=add_extra_field)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("clw", proc.stderr)
        self.assertIn("only one run", proc.stderr)

        proc_allowed = run_compare(ref, run, extra_args=["--allow-missing", "clw"])
        self.assertEqual(proc_allowed.returncode, 0, msg=proc_allowed.stderr)

    def test_s1_surface_field_parity_is_handled(self):
        def add_pr(directory):
            n = 25  # matches water_pair's default ntimes, so RunCoords agrees
            write_surface_file(directory / "pr_1h_inst.nc", "pr", np.ones(n), np.arange(n) * 3600.0, np.arange(n) * 3600.0, "kg m^-2 s^-1")

        ref, run = self.water_pair(ref_extra=add_pr, run_extra=add_pr)
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        self.assertIn("pr", report["parent_parity"])
        self.assertTrue(report["parent_parity"]["pr"]["identical"])

    def test_s1_expect_parity_fails_on_any_break(self):
        n = 25  # matches water_pair's default ntimes, so RunCoords agrees

        def perturb_ta(directory):
            write_column_file(
                directory / "ta_1h_inst.nc", "ta", np.ones((3, n)) * 2, NONUNIFORM_Z, np.arange(n) * 3600.0, np.arange(n) * 3600.0, "K"
            )

        def base_ta(directory):
            write_column_file(
                directory / "ta_1h_inst.nc", "ta", np.ones((3, n)), NONUNIFORM_Z, np.arange(n) * 3600.0, np.arange(n) * 3600.0, "K"
            )

        ref, run = self.water_pair(ref_extra=base_ta, run_extra=perturb_ta, mode_true_ref=True, mode_true_run=False)
        proc = run_compare(ref, run)  # not fatal without --expect-parity
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        proc_strict = run_compare(ref, run, extra_args=["--expect-parity"])
        self.assertNotEqual(proc_strict.returncode, 0)
        self.assertIn("ta", proc_strict.stderr)

    # --- S2: pairing ---

    def test_s2_yaml_mismatch_notice_without_expect_parity_fails_with(self):
        def bump_something(directory):
            text = (directory / "run.yml").read_text() if (directory / "run.yml").exists() else (directory / "ref.yml").read_text()

        ref, run = self.water_pair()
        # Mutate an unrelated top-level key outside the allowlist.
        text = (run / "run.yml").read_text() + "\nsome_other_job_setting: 5\n"
        (run / "run.yml").write_text(text)
        proc = run_compare(ref, run)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertIn("NOTICE: pairing", proc.stdout)
        proc_strict = run_compare(ref, run, extra_args=["--expect-parity"])
        self.assertNotEqual(proc_strict.returncode, 0)
        self.assertIn("pairing", proc_strict.stderr)

    def test_s2_mode_key_and_toml_allowed_to_differ(self):
        """The mode key (water_tag_updraft_copy) and the toml path are
        allowed to differ without a NOTICE, since that is exactly the
        default-vs-copies pairing."""
        ref, run = self.water_pair(mode_true_ref=True, mode_true_run=False)
        proc = run_compare(ref, run, extra_args=["--expect-parity"])
        # only rhoa/hus/tag fields are identical here (same data), so
        # --expect-parity should pass on pairing; it may still fail on
        # parent parity if a field differs, but not because of the mode key.
        self.assertNotIn("water_tag_updraft_copy", proc.stderr)

    # --- S3: label the run's integral honestly ---

    def test_s3_own_atmosphere_integral_reported_when_rhoa_differs(self):
        def double_rhoa(directory):
            with Dataset(directory / "rhoa_1h_inst.nc", "r+") as ds:
                ds["rhoa"][:] = ds["rhoa"][:] * 2.0

        ref, run = self.water_pair(run_extra=double_rhoa)
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--allow-missing", "hus"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertFalse(json.loads(json_path.read_text())["rhoa_parity_ok"])
        report = json.loads(json_path.read_text())
        row = next(iter(next(iter(report["tag_metrics"].values())).values()))
        self.assertIn("integral_run_own_atmosphere", row)
        self.assertIn("NOTICE: reference and run rhoa are not bitwise identical", proc.stdout)

    # --- S4: units and epoch ---

    def test_s4_variable_units_mismatch_refused(self):
        def change_units(directory):
            with Dataset(directory / "hus_1h_inst.nc", "r+") as ds:
                ds["hus"].units = "g g^-1"

        ref, run = self.water_pair(run_extra=change_units)
        proc = run_compare(ref, run, extra_args=["--allow-missing", "hus"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("units", proc.stderr)
        self.assertIn("hus", proc.stderr)

    def test_s4_time_epoch_mismatch_refused(self):
        def change_epoch(directory):
            with Dataset(directory / "rhoa_1h_inst.nc", "r+") as ds:
                ds["date"].units = "seconds since 1999-06-01T00:00:00"

        ref, run = self.water_pair(run_extra=change_epoch)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("epoch", proc.stderr)

    # --- S5: tag list from the YAML ---

    def test_s5_tag_missing_from_one_run_refused(self):
        def rename_tag(directory):
            path = directory / "run.yml" if (directory / "run.yml").exists() else directory / "ref.yml"
            path.write_text(path.read_text().replace('"evap"', '"evap2"'))

        ref, run = self.water_pair(run_extra=rename_tag)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("tags", proc.stderr)

    # --- B2: non-finite and fill values ---

    def test_b2_nan_refused(self):
        def inject_nan(directory):
            with Dataset(directory / "q_tag_tropo_1h_inst.nc", "r+") as ds:
                ds["q_tag_tropo"][1, 1] = float("nan")

        ref, run = self.water_pair(run_extra=inject_nan)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("q_tag_tropo", proc.stderr)
        self.assertIn("non-finite", proc.stderr)

    def test_b2_fill_value_refused(self):
        from netCDF4 import default_fillvals

        def inject_fill(directory):
            with Dataset(directory / "q_tag_tropo_1h_inst.nc", "r+") as ds:
                ds["q_tag_tropo"][1, 1] = default_fillvals["f8"]

        ref, run = self.water_pair(run_extra=inject_fill)
        proc = run_compare(ref, run)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("q_tag_tropo", proc.stderr)

    def test_b2_json_written_with_allow_nan_false(self):
        """Even without a non-finite bug, --json must produce strict JSON
        (a regression guard for the allow_nan=False setting itself)."""
        ref, run = self.water_pair()
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        raw = json_path.read_text()
        self.assertNotIn(" NaN", raw)
        self.assertNotIn(": NaN", raw)
        json.loads(raw)  # a strict reader must accept it

    # --- R5 --judge: small-tag boundary and region/source split ---

    def test_judge_pass_on_identical_runs(self):
        ref, run = self.water_pair(mode_true_ref=True, mode_true_run=False)
        proc = run_compare(ref, run, extra_args=["--judge", "--hours", "1,24"])
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertIn("--judge: PASS", proc.stdout)

    def test_judge_fails_when_budget_broken(self):
        """A large, deliberate perturbation of a region tag at 24h must fail
        the L1 budget (2%) and make --judge exit nonzero."""

        def break_budget(directory):
            with Dataset(directory / "q_tag_tropo_1h_inst.nc", "r+") as ds:
                ds["q_tag_tropo"][:, 1] *= 1.5  # +50% at hour 1 (index 1 == 1h with ntimes=2)

        ref, run = self.water_pair(run_extra=break_budget, mode_true_ref=True, mode_true_run=False, ntimes=25)
        proc = run_compare(ref, run, extra_args=["--judge", "--hours", "1,24"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("FAIL", proc.stdout)

    def test_judge_small_tag_boundary(self):
        """S = 1% is the boundary: a tag just below 1% share is judged on
        abs_L1 alone; just above, on L1/Linf. Built directly, not through
        water_pair, so the share can be placed on each side of the line."""
        # Three time steps: hour 0, hour 1 and hour 24 -- --judge needs both
        # judged hours present.
        time = np.array([0.0, 3600.0, 86400.0])
        date = time.copy()
        rho = np.ones((3, 3))
        hus = np.ones((3, 3)) * 100.0  # total = sum(rho*dz*100) = 100*(60+100+160)=32000
        total_integral = 100.0 * (60.0 + 100.0 + 160.0)

        def build(share_frac, perturb):
            tag_val = share_frac * total_integral / (60.0 + 100.0 + 160.0)  # uniform value giving that share
            tag = np.ones((3, 3)) * tag_val
            common = {
                "rhoa": (rho.copy(), "kg m^-3"),
                "hus": (hus.copy(), "kg kg^-1"),
                "q_tag_small": (tag.copy(), "kg kg^-1"),
            }
            yaml_text = make_tag_yaml("water", [("small", True, None)])
            ref = self.tmp / f"ref_{share_frac}".replace(".", "p") / "output_0000"
            run = self.tmp / f"run_{share_frac}".replace(".", "p") / "output_0000"
            write_synthetic_run(ref, z=NONUNIFORM_Z, time=time, date=date, column_vars=common, yaml_text=yaml_text, yaml_name="a.yml")
            common_run = dict(common)
            perturbed = tag.copy()
            perturbed[0, 1] += perturb  # perturb the bottom level at hour 1
            common_run["q_tag_small"] = (perturbed, "kg kg^-1")
            write_synthetic_run(run, z=NONUNIFORM_Z, time=time, date=date, column_vars=common_run, yaml_text=yaml_text, yaml_name="a.yml")
            return ref, run

        # Just below 1% share, with a perturbation that would fail L1 (10%)
        # but easily passes the small-tag absolute bound.
        ref, run = build(0.005, perturb=0.01)
        json_path = self.tmp / "below.json"
        proc = run_compare(ref, run, extra_args=["--judge", "--hours", "1,24"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        row = next(r for r in report["judge"]["rows"] if r["hour"] == 1)
        self.assertTrue(row["small"])

        # Just above 1% share: the small-tag rule no longer applies.
        ref2, run2 = build(0.05, perturb=0.01)
        json_path2 = self.tmp / "above.json"
        proc2 = run_compare(ref2, run2, extra_args=["--judge", "--hours", "1,24"], json_path=json_path2)
        report2 = json.loads(json_path2.read_text())
        row2 = next(r for r in report2["judge"]["rows"] if r["hour"] == 1)
        self.assertFalse(row2["small"])

    def test_judge_requires_water_family(self):
        ref, run = self.water_pair()
        # Force --family energy on a water config: detect_family would
        # refuse, so pass --family explicitly to reach the water-only check.
        proc = run_compare(ref, run, extra_args=["--judge", "--family", "energy", "--tags", "tropo"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("water-only", proc.stderr)

    # --- R11: --bitwise-tags ---

    def test_bitwise_tags_reports_identical_and_catches_a_difference(self):
        ref, run = self.water_pair()
        json_path = self.tmp / "report.json"
        proc = run_compare(ref, run, extra_args=["--bitwise-tags"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        self.assertTrue(report["tag_bitwise"]["tropo"]["identical"])

        def perturb(directory):
            with Dataset(directory / "q_tag_tropo_1h_inst.nc", "r+") as ds:
                ds["q_tag_tropo"][0, 0] += 1e-10

        ref2, run2 = self.water_pair(run_extra=perturb)
        json_path2 = self.tmp / "report2.json"
        proc2 = run_compare(ref2, run2, extra_args=["--bitwise-tags"], json_path=json_path2)
        self.assertEqual(proc2.returncode, 0, msg=proc2.stderr)
        report2 = json.loads(json_path2.read_text())
        self.assertFalse(report2["tag_bitwise"]["tropo"]["identical"])

    # --- R12: --ladder-share on different z grids ---

    def test_ladder_share_handles_different_z_grids(self):
        time = np.array([0.0, 3600.0])
        date = time.copy()
        rho_a = np.ones((3, 2))
        hus_a = np.ones((3, 2)) * 10.0
        tag_a = np.ones((3, 2)) * 2.0
        yaml_a = make_tag_yaml("water", [("t", True, None)])
        ref = self.tmp / "coarse" / "output_0000"
        write_synthetic_run(
            ref, z=NONUNIFORM_Z, time=time, date=date,
            column_vars={"rhoa": (rho_a, "kg m^-3"), "hus": (hus_a, "kg kg^-1"), "q_tag_t": (tag_a, "kg kg^-1")},
            yaml_text=yaml_a, yaml_name="a.yml",
        )
        # A finer grid: 5 levels instead of 3, different z entirely.
        z_fine = np.array([10.0, 40.0, 90.0, 160.0, 260.0])
        rho_b = np.ones((5, 2))
        hus_b = np.ones((5, 2)) * 10.0
        tag_b = np.ones((5, 2)) * 2.0
        run = self.tmp / "fine" / "output_0000"
        write_synthetic_run(
            run, z=z_fine, time=time, date=date,
            column_vars={"rhoa": (rho_b, "kg m^-3"), "hus": (hus_b, "kg kg^-1"), "q_tag_t": (tag_b, "kg kg^-1")},
            yaml_text=yaml_a, yaml_name="a.yml",
        )
        json_path = self.tmp / "ladder.json"
        proc = run_compare(ref, run, extra_args=["--ladder-share", "--hours", "0,1"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())
        self.assertEqual(report["mode"], "column_integrals_only")
        self.assertFalse(report["same_grid"])
        row = report["tags"]["t"]["1"]
        # phi = q_tag/q_tot = 2/10 = 0.2 on both runs (uniform columns), so
        # the column-integrated share is equal on both sides.
        self.assertAlmostEqual(row["phi_ref_column"], 0.2, delta=1e-9)
        self.assertAlmostEqual(row["phi_run_column"], 0.2, delta=1e-9)
        self.assertAlmostEqual(row["share_delta_column"], 0.0, delta=1e-9)
        self.assertNotIn("L1_phi_level_wise", row)


class E73RegressionTest(unittest.TestCase):
    """B1: reproduces e73_reproduction.txt's numbers exactly (to the
    tolerance recorded in fixtures/e73/expected_e73.py, frozen from a run
    that matched the committed table character for character), from the
    durable fixture rebuilt out of .npz arrays (not '*.nc', which is
    gitignored)."""

    def setUp(self):
        TMP_BASE.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(prefix="e73_", dir=TMP_BASE))
        self.ref_dir = self.tmp / "reference" / "output_0000"
        self.run_dir = self.tmp / "run" / "output_0000"
        ref_arrays = e73_data.load("reference")
        run_arrays = e73_data.load("run")
        self.ref_dir.mkdir(parents=True)
        self.run_dir.mkdir(parents=True)
        for which, arrays, out_dir, yml_src in (
            ("reference", ref_arrays, self.ref_dir, e73_data.REFERENCE_DIR),
            ("run", run_arrays, self.run_dir, e73_data.RUN_DIR),
        ):
            z, time, date = arrays["z"], arrays["time"], arrays["date"]
            for stem in e73_data.STEMS:
                write_column_file(out_dir / f"{stem}_1h_inst.nc", stem, arrays[stem], z, time, date, e73_data.UNITS[stem], date_units=e73_data.DATE_UNITS)
            yml_files = list(yml_src.glob("*.yml"))
            for f in yml_files:
                (out_dir / f.name).write_text(f.read_text())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_e73_reproduces_exactly(self):
        json_path = self.tmp / "report.json"
        proc = run_compare(self.ref_dir, self.run_dir, extra_args=["--hours", "1,6,12,24"], json_path=json_path)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        report = json.loads(json_path.read_text())

        for tag, hours in E73_EXPECTED["tag_metrics"].items():
            for h, expected_row in hours.items():
                row = report["tag_metrics"][tag][h]
                for key, expected_val in expected_row.items():
                    got = row[key]
                    if expected_val is None:
                        self.assertIsNone(got, msg=f"{tag}@{h} {key}")
                    elif isinstance(expected_val, bool):
                        self.assertEqual(got, expected_val, msg=f"{tag}@{h} {key}")
                    else:
                        self.assertAlmostEqual(got, expected_val, delta=max(1e-15, abs(expected_val) * 1e-12), msg=f"{tag}@{h} {key}")

        for name, expected_identical in E73_EXPECTED["parent_identical"].items():
            self.assertEqual(report["parent_parity"][name]["identical"], expected_identical, msg=name)


if __name__ == "__main__":
    unittest.main()
