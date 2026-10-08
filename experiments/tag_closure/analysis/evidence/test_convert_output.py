"""Tests of convert_output.py: its name table, its weights and its refusals.

The synthetic runs below are small NetCDF outputs laid out as the model writes
them. Expected values are derived by hand from the arrays written here. The
last class converts archived real output (W58 and E87) when it is present and
skips with the reason otherwise.
"""

import contextlib
import csv
import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

import convert_output
from acceptance_data import Bundle, cumulative_amount, density, integrate
from convert_output import NAME_TABLE, main
from score_acceptance import Scorer

TIMES = np.arange(5, dtype=np.float64) * 1800
# A stretched column: faces 0, 100, 300, 700 m, so centres 50, 200, 500 m.
CENTRES = np.array([50.0, 200.0, 500.0])
THICKNESS = np.array([100.0, 200.0, 400.0])
SHA = "a" * 40


def write_field(path, name, values, units, z=CENTRES, dims=("z", "time"), coords=None):
    """One model-style output file: the variable is (z, time), or (time) at the surface."""
    with Dataset(path, "w") as ds:
        ds.createDimension("time", None)
        t = ds.createVariable("time", "f8", ("time",))
        t.units = "s"
        t[:] = TIMES
        for d in dims:
            if d == "time":
                continue
            data = z if d == "z" else coords[d]
            ds.createDimension(d, len(data))
            v = ds.createVariable(d, "f8", (d,))
            v.units = "m" if d == "z" else "degrees"
            v[:] = data
        var = ds.createVariable(name, values.dtype, dims)
        var.units = units
        var[:] = values


def native(base, scale=1.0):
    """A (z, time) array whose every entry differs, so a transpose or a swap shows."""
    return (base + scale * (np.arange(3)[:, None] * 10 + np.arange(5)[None, :])).astype(np.float64)


def water_yml(tags=True, copies=False, extra=""):
    lines = ['config: "column"', "z_max: 700.0", 'dt: "150secs"', 't_end: "2hours"', 'FLOAT_TYPE: "Float64"',
             'topography: "NoWarp"', f"water_tag_updraft_copy: {'true' if copies else 'false'}",
             'ode_algo: "ARS343"', "diagnostics:", "  - short_name:", '      - "hus"', '    period: "30mins"']
    if tags:
        lines += ["water_tracers:", '  - name: "pbl"', "    region:", '      type: "tanh_altitude"',
                  '  - name: "free"', "    region:", '      type: "tanh_altitude"',
                  '  - name: "evap"', '    source: "surface_flux"']
    else:
        lines += ["water_tracers: ~"]
    return "\n".join(lines) + "\n" + extra


class Synthetic:
    """Build a run directory with outputs, a merged config, a manifest and tables."""

    def __init__(self, root):
        self.root = Path(root)
        self.repo = self.root / "repo"
        (self.repo / ".buildkite").mkdir(parents=True)
        (self.repo / ".buildkite" / "Project.toml").write_text("[deps]\n")
        self.config = self.repo / "config.yml"
        self.config.write_text("config: column\n")

    def manifest(self):
        return {"head_sha": SHA, "status_lines": [], "diff": "", "diff_sha256": hashlib.sha256(b"").hexdigest(),
                "untracked": {"count": 0, "files": []}, "repo": str(self.repo),
                "config": {"path": str(self.config), "sha256": hashlib.sha256(self.config.read_bytes()).hexdigest()},
                "buildkite_files": {"Project.toml": hashlib.sha256(b"[deps]\n").hexdigest()},
                "julia_version": "1.11.9", "hostname": "test", "env_vars": {}, "julia_binary": "julia",
                "julia_channel": "+1.11", "loaded_modules": []}

    def water_run(self, name, tags=True, copies=False, yml_extra="", skip=(), cadence_flag=1.0):
        d = self.root / name / "output_0000"
        d.mkdir(parents=True)
        (d / "manifest.json").write_text(json.dumps(self.manifest()))
        (d / (name + ".yml")).write_text(water_yml(tags, copies, yml_extra))
        (d / "provenance.txt").write_text("run: test\nntasks: 2\n")
        hus = native(0.01, 1e-4)
        fields = {"rhoa": (native(1.0, 1e-3), "kg m^-3"), "hus": (hus, "kg kg^-1"),
                  "ta": (native(280.0, 0.1), "K"), "wa": (native(0.0, 1e-2), "m s^-1")}
        if tags:
            fields.update({"q_tag_pbl": (0.5 * hus, "kg kg^-1"), "q_tag_free": (0.5 * hus - 1e-6, "kg kg^-1"),
                           "q_tag_evap": (0.1 * hus, "kg kg^-1")})
            for tag in ("pbl", "free", "evap"):
                for led in ("fix", "inc"):
                    fields[f"q_tag_led_{led}_{tag}"] = (native(0.0, 1e-7), "kg kg^-1")
        for short, (values, units) in fields.items():
            if short not in skip:
                write_field(d / f"{short}_30m_inst.nc", short, values, units)
        if tags:
            for short, rate in (("pr", -2e-4), ("pr_tag_pbl", -1.2e-4), ("pr_tag_free", -0.8e-4)):
                if short not in skip:
                    write_field(d / f"{short}_30m_inst.nc", short, np.full(5, rate), "kg m^-2 s^-1", dims=("time",))
            closure = {"time": TIMES, "negative_water_void": np.zeros(5)}
            audit = {"time": TIMES, "ledger_cadence_step": np.full(5, cadence_flag),
                     "led_repair_retained": np.arange(5) * 1e-3, "led_repair_attempted": np.arange(5) * 2e-3,
                     "led_uprepair_retained": np.arange(5) * 3e-3, "led_uprepair_attempted": np.arange(5) * 4e-3}
            for tag in ("pbl", "free", "evap"):
                audit[f"led_fix_{tag}_applicable"] = np.ones(5)
                audit[f"led_inc_{tag}_applicable"] = np.ones(5)
            write_table(d / "water_tag_closure.csv", closure)
            write_table(d / "water_tag_audit.csv", audit)
        return d

    def energy_run(self, name, tags=True):
        d = self.root / name / "output_0000"
        d.mkdir(parents=True)
        (d / "manifest.json").write_text(json.dumps(self.manifest()))
        lines = ['config: "column"', "z_max: 700.0", 'dt: "120secs"', 't_end: "2hours"', 'FLOAT_TYPE: "Float64"',
                 "energy_source_tag_offset: 1000.0", "energy_source_tag_ledger_per_tag: true",
                 "energy_process_record:", '  - "radiation"', '  - "microphysics"']
        if tags:
            lines += ["energy_source_tags:", '  - name: "low"', "    region:", '      type: "tanh_altitude"',
                      '  - name: "high"', "    region:", '      type: "tanh_altitude"',
                      '  - name: "rad"', '    source: "radiation"']
        (d / (name + ".yml")).write_text("\n".join(lines) + "\n")
        (d / "provenance.txt").write_text("ntasks: 1\n")
        fields = {"rhoa": native(1.0, 1e-3), "hus": native(0.01, 1e-4), "ta": native(280.0, 0.1)}
        units = {"rhoa": "kg m^-3", "hus": "kg kg^-1", "ta": "K"}
        if tags:
            for short in ("e_src_low", "e_src_high", "e_src_rad", "e_src_res", "e_src_led_src_low",
                          "e_src_led_src_high", "e_src_led_src_rad", "e_prc_radiation"):
                fields[short], units[short] = native(100.0, 1.0), "J kg^-1"
        for short, values in fields.items():
            write_field(d / f"{short}_30m_inst.nc", short, values, units[short])
        if tags:
            write_table(d / "energy_source_tag_closure.csv",
                        {"time": TIMES, "source_partition_valid": np.ones(5), "source_throughput": np.arange(5) * 50.0})
            write_table(d / "energy_source_tag_audit.csv",
                        {"time": TIMES, "ledger_cadence_step": np.ones(5), "led_repair_retained": np.arange(5) * 0.5,
                         "led_repair_attempted": np.arange(5) * 0.75})
        return d


def write_table(path, columns):
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(list(columns))
        for i in range(len(columns["time"])):
            writer.writerow([repr(float(columns[k][i])) for k in columns])


def convert(out, family="water", **runs):
    args = ["--family", family, "--planning-commit", "p" * 40, "--scorer-commit", "s" * 40, "--out", str(out)]
    for role, d in runs.items():
        if role in ("candidate", "reference", "untagged"):
            args += ["--" + role, str(d)]
        elif d is True:
            args += ["--" + role.replace("_", "-")]
        else:
            args += ["--" + role.replace("_", "-"), str(d)]
    stdout, stderr = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        code = main(args)
    return code, stdout.getvalue() + stderr.getvalue()


def npz(path):
    with np.load(path, allow_pickle=False) as archive:
        return {k: archive[k].copy() for k in archive.files}


def record(out):
    return {(r["role"], r["logical"]): r for r in json.loads((Path(out) / "conversion.json").read_text())["variables"]}


class ConverterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.s = Synthetic(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def water(self, **options):
        runs = {"candidate": self.s.water_run("cand", **options.pop("candidate_options", {})),
                "untagged": self.s.water_run("untagged", tags=False),
                "reference": self.s.water_run("ref", copies=True)}
        runs.update(options)
        out = self.root / "bundle"
        code, text = convert(out, **runs)
        return out, code, text

    def test_name_table_is_the_documented_table(self):
        # The table decides which model variable feeds which scored quantity.
        # Pinned here row by row, as README.md documents it.
        expected = {
            ("rho", "both"): ("rhoa", "kg m^-3", "density", "instantaneous", ""),
            ("water_parent", "both"): ("hus", "kg kg^-1", "specific", "instantaneous", ""),
            ("temperature", "both"): ("ta", "K", "intensive", "instantaneous", ""),
            ("tag_<tag>", "water"): ("q_tag_<tag>", "kg kg^-1", "specific", "instantaneous", ""),
            ("parent_N", "water"): ("", "kg kg^-1", "specific", "instantaneous", ""),
            ("parent_R", "water"): ("husra", "kg kg^-1", "specific", "instantaneous", ""),
            ("parent_S", "water"): ("hussn", "kg kg^-1", "specific", "instantaneous", ""),
            ("tag_N_<tag>", "water"): ("q_ntag_<tag>", "kg kg^-1", "specific", "instantaneous", ""),
            ("tag_R_<tag>", "water"): ("q_rtag_<tag>", "kg kg^-1", "specific", "instantaneous", ""),
            ("tag_S_<tag>", "water"): ("q_stag_<tag>", "kg kg^-1", "specific", "instantaneous", ""),
            ("led_fix_<tag>", "water"): ("q_tag_led_fix_<tag>", "kg kg^-1", "specific", "cumulative", ""),
            ("led_inc_<tag>", "water"): ("q_tag_led_inc_<tag>", "kg kg^-1", "specific", "cumulative", ""),
            ("led_fix_<tag>_applicable", "water"): ("led_fix_<tag>_applicable", "1", "flag", "instantaneous", ""),
            ("led_inc_<tag>_applicable", "water"): ("led_inc_<tag>_applicable", "1", "flag", "instantaneous", ""),
            ("negative_water_void", "both"): ("negative_water_void", "1", "flag", "instantaneous", ""),
            ("repair_retained", "water", "candidate"): ("led_repair_retained", "<amount>", "amount", "cumulative",
                                                        "retained_cell_step_repair"),
            ("repair_attempted", "water", "candidate"): ("led_repair_attempted", "<amount>", "amount", "cumulative",
                                                         "attempted_application_repair"),
            ("repair_retained", "water", "reference_copies"): ("led_uprepair_retained", "<amount>", "amount",
                                                               "cumulative", "retained_cell_step_repair"),
            ("repair_attempted", "water", "reference_copies"): ("led_uprepair_attempted", "<amount>", "amount",
                                                                "cumulative", "attempted_application_repair"),
            ("copy_residual", "water"): ("", "kg kg^-1", "specific", "instantaneous", ""),
            ("named_remainder", "water"): ("", "kg kg^-1", "specific", "instantaneous", ""),
            ("precip_parent", "water"): ("pr", "kg m^-2 s^-1", "rate", "instantaneous", ""),
            ("precip_<tag>", "water"): ("pr_tag_<tag>", "kg m^-2 s^-1", "rate", "instantaneous", ""),
            ("tag_<tag>", "energy_source"): ("e_src_<tag>", "J kg^-1", "specific", "instantaneous", ""),
            ("residual", "energy_source"): ("e_src_res", "J kg^-1", "specific", "instantaneous", ""),
            ("led_src_<tag>", "energy_source"): ("e_src_led_src_<tag>", "J kg^-1", "specific", "cumulative", ""),
            ("led_fix_<tag>", "energy_source"): ("e_src_led_fix_<tag>", "J kg^-1", "specific", "cumulative", ""),
            ("led_inc_<tag>", "energy_source"): ("e_src_led_inc_<tag>", "J kg^-1", "specific", "cumulative", ""),
            ("led_fix_<tag>_applicable", "energy_source"): ("led_fix_<tag>_applicable", "1", "flag",
                                                           "instantaneous", ""),
            ("led_inc_<tag>_applicable", "energy_source"): ("led_inc_<tag>_applicable", "1", "flag",
                                                           "instantaneous", ""),
            ("source_partition_valid", "energy_source"): ("source_partition_valid", "1", "flag", "instantaneous", ""),
            ("throughput", "energy_source"): ("source_throughput", "<amount>", "amount", "cumulative",
                                              "accepted_step_source_variation"),
            ("repair_retained", "energy_source", "tagged"): ("led_repair_retained", "<amount>", "amount",
                                                             "cumulative", "retained_cell_step_repair"),
            ("repair_attempted", "energy_source", "tagged"): ("led_repair_attempted", "<amount>", "amount",
                                                              "cumulative", "attempted_application_repair"),
            ("record_<process>", "energy_source"): ("e_prc_<process>", "J kg^-1", "specific", "cumulative", ""),
            ("energy_parent", "energy_source"): ("", "J kg^-1", "specific", "instantaneous", ""),
            ("newton_error", "both"): ("", "1", "ratio", "instantaneous", ""),
            ("process_amount", "both"): ("", "<amount>", "weighted_applied_amount", "applied_interval", ""),
            ("process_share", "both"): ("", "1", "ratio", "applied_interval", ""),
        }
        actual = {}
        for n in NAME_TABLE:
            key = (n.logical, n.family) if n.logical not in ("repair_retained", "repair_attempted") else \
                (n.logical, n.family, n.roles)
            actual[key] = (n.model, n.units, n.representation, n.sampling, n.accumulator)
        self.assertEqual(actual, expected)
        self.assertEqual(len(NAME_TABLE), len(expected))
        gaps = {n.logical for n in NAME_TABLE if n.source == "none"}
        self.assertEqual(gaps, {"parent_N", "copy_residual", "named_remainder", "energy_parent", "newton_error",
                                "process_amount", "process_share"})
        self.assertTrue(all(n.reason for n in NAME_TABLE if n.source == "none"))

    def test_fields_are_copied_bit_for_bit_with_their_conventions(self):
        out, code, _ = self.water()
        a = npz(out / "candidate.npz")
        with Dataset(self.root / "cand/output_0000/hus_30m_inst.nc") as ds:
            self.assertTrue(np.array_equal(a["water_parent"], np.asarray(ds["hus"][:]).T))
        with Dataset(self.root / "cand/output_0000/rhoa_30m_inst.nc") as ds:
            self.assertTrue(np.array_equal(a["rho"], np.asarray(ds["rhoa"][:]).T))
        with Dataset(self.root / "cand/output_0000/q_tag_led_fix_free_30m_inst.nc") as ds:
            self.assertTrue(np.array_equal(a["led_fix_free"], np.asarray(ds["q_tag_led_fix_free"][:]).T))
        with Dataset(self.root / "cand/output_0000/pr_tag_pbl_30m_inst.nc") as ds:
            self.assertTrue(np.array_equal(a["precip_pbl"][:, 0], np.asarray(ds["pr_tag_pbl"][:])))
        self.assertEqual(a["water_parent"].dtype, np.float64)
        fields = json.loads((out / "manifest.json").read_text())["acceptance"]["runs"]["candidate"]["fields"]
        self.assertEqual((fields["rho"]["units"], fields["rho"]["representation"]), ("kg m^-3", "density"))
        self.assertEqual((fields["water_parent"]["units"], fields["water_parent"]["representation"]),
                         ("kg kg^-1", "specific"))
        self.assertEqual((fields["led_fix_pbl"]["sampling"], fields["led_inc_evap"]["sampling"]),
                         ("cumulative", "cumulative"))
        self.assertEqual(fields["tag_pbl"]["sampling"], "instantaneous")
        self.assertEqual((fields["precip_parent"]["dimensions"], fields["precip_parent"]["weight_units"]),
                         (["scalar"], "1"))
        self.assertEqual(fields["repair_retained"]["accumulator_kind"], "retained_cell_step_repair")
        self.assertEqual(fields["repair_attempted"]["accumulator_kind"], "attempted_application_repair")
        self.assertEqual(fields["repair_retained"]["units"], "kg m^-2")
        self.assertTrue(np.array_equal(a["repair_retained"][:, 0], np.arange(5) * 1e-3))
        self.assertTrue(np.array_equal(a["repair_attempted"][:, 0], np.arange(5) * 2e-3))
        self.assertTrue(np.array_equal(a["negative_water_void"][:, 0], np.zeros(5)))
        self.assertEqual(fields["water_parent"]["cadence"], 1800.0)
        # Only the scored partition tags have precipitation rows.
        self.assertNotIn("precip_evap", fields)

    def test_roles_read_only_what_the_scorer_reads_from_them(self):
        out, _, _ = self.water()
        runs = json.loads((out / "manifest.json").read_text())["acceptance"]["runs"]
        ref = npz(out / "reference.npz")
        # The copies' own repair is the reference's aggregate repair, as R5 reads it.
        self.assertTrue(np.array_equal(ref["repair_retained"][:, 0], np.arange(5) * 3e-3))
        self.assertTrue(np.array_equal(ref["repair_attempted"][:, 0], np.arange(5) * 4e-3))
        self.assertNotIn("led_fix_pbl", runs["reference"]["fields"])
        self.assertIn("tag_pbl", runs["reference"]["fields"])
        self.assertEqual(sorted(n for n in runs["untagged"]["fields"] if not n.startswith("export_")),
                         ["rho", "temperature", "water_parent"])
        self.assertEqual(runs["untagged"]["model_commit"], SHA)
        self.assertEqual(record(out)[("reference", "copy_residual")]["status"], "missing")

    def test_column_weights_are_thicknesses_from_rebuilt_faces(self):
        out, _, _ = self.water()
        a = npz(out / "candidate.npz")
        d = json.loads((out / "manifest.json").read_text())["acceptance"]["runs"]["candidate"]["fields"]["rho"]
        self.assertTrue(np.array_equal(a[d["weights_key"]], THICKNESS))
        self.assertTrue(np.array_equal(a[d["geometry_key"]][:, 0], CENTRES))
        self.assertEqual((d["weight_units"], d["dimensions"]), ("m", ["z"]))
        # The scorer's integral is the hand-derived Σ ρ q Δz.
        b = Bundle(out / "manifest.json")
        q, rho = b.field("candidate", "water_parent"), b.field("candidate", "rho")
        expected = np.sum(native(1.0, 1e-3) * native(0.01, 1e-4) * THICKNESS[:, None], axis=0)
        self.assertTrue(np.allclose(integrate(density(q, rho), q.weights), expected, rtol=1e-15, atol=0))

    def test_converted_bundle_validates_and_scores_hand_derived_rows(self):
        out, code, text = self.water(same_parent=True)
        self.assertEqual(code, 2)
        self.assertEqual(Bundle(out / "manifest.json").validate(), [])
        rows = {r["id"]: r for r in Scorer(Bundle(out / "manifest.json")).run()["rows"]}
        rho, hus = native(1.0, 1e-3), native(0.01, 1e-4)
        residual = np.abs(hus - (0.5 * hus + 0.5 * hus - 1e-6))
        gross = np.sum(rho * residual * THICKNESS[:, None], axis=0)[-1]
        water = np.sum(rho * hus * THICKNESS[:, None], axis=0)[-1]
        closure = rows["WATER.CLOSURE"]["metrics"]
        # The residual is a difference of numbers 1e4 times larger, so it keeps fewer digits.
        self.assertAlmostEqual(closure["gross"] / gross, 1, places=9)
        self.assertAlmostEqual(closure["gross_over_raw"] / (gross / water), 1, places=9)
        repair = rows["WATER.AGGREGATE_REPAIR.startup"]["metrics"]
        self.assertAlmostEqual(repair["daily_rate"] / (4e-3 / water * 86400 / 7200), 1, places=12)
        self.assertEqual(rows["COMMON.PARENT_PARITY"]["metrics"]["differing"], [])
        self.assertEqual(rows["COMMON.PARENT_PARITY"]["metrics"]["compared"],
                         ["rho", "water_parent", "temperature", "export_wa"])
        self.assertEqual(rows["COMMON.NEGATIVE_WATER"]["verdict"], "PASS")
        self.assertIn("missing candidate variable: newton_error", rows["COMMON.NEWTON_TRIAL"]["limitation"])
        self.assertIn("DATA FAILURE: candidate newton_error (no model variable)", text)

    def test_missing_variable_is_named_and_never_zero_filled(self):
        out, code, text = self.water(candidate_options={"skip": ("q_tag_led_inc_free",)})
        self.assertEqual(code, 2)
        entry = record(out)[("candidate", "led_inc_free")]
        self.assertEqual((entry["status"], entry["model"]), ("missing", "q_tag_led_inc_free"))
        self.assertIn("no q_tag_led_inc_free_30m_inst.nc", entry["reason"])
        self.assertIn("DATA FAILURE: candidate led_inc_free (q_tag_led_inc_free)", text)
        self.assertNotIn("led_inc_free", npz(out / "candidate.npz"))
        rows = {r["id"]: r for r in Scorer(Bundle(out / "manifest.json")).run()["rows"]}
        row = rows["WATER.LED_INC.free.startup"]
        self.assertEqual(row["data_status"], "DATA FAILURE")
        self.assertIn("missing candidate variable: led_inc_free", row["limitation"])

    def test_wrong_units_or_fill_values_are_named_failures(self):
        d = self.s.water_run("cand")
        write_field(d / "hus_30m_inst.nc", "hus", native(0.01, 1e-4), "g kg^-1")
        values = np.ma.masked_array(native(0.0, 1e-2), mask=np.zeros((3, 5), bool))
        values.mask[1, 2] = True
        write_field(d / "ta_30m_inst.nc", "ta", values, "K")
        out = self.root / "bundle"
        code, _ = convert(out, candidate=d, untagged=self.s.water_run("untagged", tags=False))
        self.assertEqual(code, 2)
        r = record(out)
        self.assertIn("units 'g kg^-1'", r[("candidate", "water_parent")]["reason"])
        self.assertIn("fill values", r[("candidate", "temperature")]["reason"])
        self.assertNotIn("water_parent", npz(out / "candidate.npz"))

    def test_audit_amounts_need_accepted_step_cadence(self):
        out, _, _ = self.water(candidate_options={"cadence_flag": 0.0})
        entry = record(out)[("candidate", "repair_retained")]
        self.assertEqual(entry["status"], "missing")
        self.assertIn("ledger_cadence_step is not 1", entry["reason"])
        self.assertNotIn("repair_retained", npz(out / "candidate.npz"))

    def test_refusals_write_nothing(self):
        cases = {"top face": ("z_max: 800.0\n", "rebuilt top face"),
                 "topography": ('topography: "Earth"\n', "flat surface"),
                 "box": ('config: "box"\n', "unsupported config")}
        for name, (line, message) in cases.items():
            with self.subTest(name=name):
                d = self.s.water_run("cand_" + name.replace(" ", "_"))
                yml = next(d.glob("*.yml"))
                key = line.split(":")[0] + ":"
                text = "\n".join(l for l in yml.read_text().splitlines() if not l.startswith(key)) + "\n" + line
                yml.write_text(text)
                out = self.root / ("bundle_" + name.replace(" ", "_"))
                code, err = convert(out, candidate=d)
                self.assertEqual(code, 2)
                self.assertIn(message, err)
                self.assertFalse(out.exists())

    def test_nonpositive_thickness_is_refused(self):
        d = self.s.water_run("cand")
        for path in d.glob("*_30m_inst.nc"):
            with Dataset(path, "a") as ds:
                if "z" in ds.variables:
                    ds["z"][:] = np.array([50.0, 90.0, 500.0])
        code, err = convert(self.root / "bundle", candidate=d)
        self.assertEqual(code, 2)
        self.assertIn("non-positive cell thickness at levels [1]", err)

    def test_period_must_be_unique_or_chosen(self):
        d = self.s.water_run("cand")
        write_field(d / "hus_10m_inst.nc", "hus", native(0.01, 1e-4), "kg kg^-1")
        code, err = convert(self.root / "bundle", candidate=d)
        self.assertEqual(code, 2)
        self.assertIn("several periods", err)
        code, _ = convert(self.root / "bundle2", candidate=d, period="30m")
        self.assertEqual(code, 2)
        self.assertTrue((self.root / "bundle2" / "manifest.json").is_file())

    def test_existing_output_is_refused(self):
        (self.root / "bundle").mkdir()
        code, _ = convert(self.root / "bundle", candidate=self.s.water_run("cand"))
        self.assertEqual(code, 4)

    def test_submission_files_need_matching_hashes(self):
        d = self.s.water_run("cand")
        self.s.config.write_text("changed\n")
        out = self.root / "bundle"
        code, text = convert(out, candidate=d)
        self.assertIn("submission file config", text)
        spec = json.loads((out / "manifest.json").read_text())["acceptance"]
        self.assertNotIn("config", spec["submission_files"])
        self.assertIn("Project.toml", spec["submission_files"])
        self.assertIn("missing evidence path", " ".join(Bundle(out / "manifest.json").validate()))

    def test_energy_family_maps_throughput_records_and_scale(self):
        cand = self.s.energy_run("ecand")
        out = self.root / "bundle"
        code, text = convert(out, family="energy_source", candidate=cand, untagged=self.s.energy_run("eun", tags=False))
        spec = json.loads((out / "manifest.json").read_text())["acceptance"]
        fields = spec["runs"]["candidate"]["fields"]
        self.assertEqual((fields["throughput"]["units"], fields["throughput"]["accumulator_kind"]),
                         ("J m^-2", "accepted_step_source_variation"))
        self.assertEqual((fields["tag_low"]["units"], fields["residual"]["units"]), ("J kg^-1", "J kg^-1"))
        self.assertEqual(spec["record_processes"], ["radiation"])
        self.assertEqual(spec["expected_record_processes"], ["radiation", "microphysics"])
        self.assertEqual((spec["energy_offset"], spec["energy_ledger_per_tag"]), (1000.0, True))
        self.assertEqual((spec["accepted_step_seconds"], spec["end_seconds"]), (120.0, 7200.0))
        self.assertEqual(spec["process_count"], 1)
        self.assertEqual([t["partition"] for t in spec["tags"]], [True, True, False])
        self.assertIn("DATA FAILURE: candidate record_microphysics (e_prc_microphysics)", text)
        self.assertIn("DATA FAILURE: untagged energy_parent (no model variable)", text)
        rows = {r["id"]: r for r in Scorer(Bundle(out / "manifest.json")).run()["rows"]}
        growth = rows["ENERGY.CLOSURE_GROWTH.startup"]["metrics"]
        self.assertEqual(growth["theta_x"], 200.0)
        self.assertIn("missing/incorrect expected active process roster",
                      rows["ENERGY.CORRECTED_RECORD_ESTIMATE.startup"]["limitation"])


class SphereTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def geometry(self, area=None, deep=False):
        d = self.root / "sphere"
        d.mkdir()
        (d / "manifest.json").write_text("{}")
        (d / "s.yml").write_text('config: "sphere"\nz_max: 700.0\n' + ("deep_atmosphere: true\n" if deep else ""))
        if area is not None:
            with Dataset(d / "area.nc", "w") as ds:
                ds.createDimension("lat", 2)
                ds.createDimension("lon", 3)
                v = ds.createVariable("cell_area", "f8", ("lat", "lon"))
                v.units = "m^2"
                v.standard_name = "cell_area"
                v[:] = area
        return convert_output.Geometry(convert_output.Run("candidate", d), "sphere")

    def test_area_weights_follow_the_field_dimensions(self):
        area = np.array([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
        g = self.geometry(area)
        coords = {"lon": np.array([0.0, 120.0, 240.0]), "lat": np.array([-45.0, 45.0]), "z": CENTRES}
        weights, geometry, units, dims = g.weights(("lon", "lat", "z"), coords)
        expected = area.T[:, :, None] * THICKNESS[None, None, :]
        self.assertTrue(np.array_equal(weights, expected.reshape(-1)))
        self.assertEqual((units, dims), ("m^3", ("lon", "lat", "z")))
        self.assertTrue(np.array_equal(geometry[7], [120.0, -45.0, 200.0]))
        surface, _, units, _ = g.weights(("lat", "lon"), coords)
        self.assertTrue(np.array_equal(surface, area.reshape(-1)))
        self.assertEqual(units, "m^2")

    def test_sphere_without_native_area_is_refused(self):
        with self.assertRaisesRegex(convert_output.ConversionError, "no native cell-area variable"):
            self.geometry()

    def test_deep_atmosphere_sphere_is_refused(self):
        with self.assertRaisesRegex(convert_output.ConversionError, "deep-atmosphere"):
            self.geometry(np.ones((2, 3)), deep=True)


# Archived real output. W58 ran on 2026-10-02, after the archive's last full
# sync, so its runs are looked up on scratch too. TAG_CLOSURE_OUTPUT_ROOTS
# (paths separated by ":") overrides the search.
ARCHIVE = Path("/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-archive/scratch_tag_closure/output")
SCRATCH = Path("/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output")
REPO = Path(__file__).resolve().parents[4]


def output_roots():
    roots = os.environ.get("TAG_CLOSURE_OUTPUT_ROOTS")
    return [Path(p) for p in roots.split(":")] if roots else [ARCHIVE, SCRATCH]


def find_run(name):
    for root in output_roots():
        if (root / name / "output_0000" / "manifest.json").is_file():
            return root / name / "output_0000"
    return None


def require_runs(*names):
    runs = [find_run(n) for n in names]
    if not all(runs):
        raise unittest.SkipTest(f"archived model output for {', '.join(names)} is absent "
                                f"(looked in {', '.join(str(r) for r in output_roots())})")
    return runs


SUBMISSION_GAP = "incomplete submission environment file: LocalPreferences.toml"


class ArchivedOutputTests(unittest.TestCase):
    """W58 (TRMM 0M, three tags, 6 h) and E87 (D4, the G4.6 process budget)."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def assert_named_gaps(self, out, expected):
        missing = {(r["role"], r["logical"]) for r in record(out).values() if r["status"] == "missing"}
        self.assertEqual(missing, expected)
        for r in record(out).values():
            self.assertTrue(r["status"] == "resolved" or r["reason"])

    def test_w58_pilot_first_hour(self):
        cand, ref, twin = require_runs("g3b_trmm0m_default_6h", "g3b_trmm0m_copies_6h", "g3b_trmm0m_untagged_6h")
        out = self.root / "w58"
        code, _ = convert(out, candidate=cand, reference=ref, untagged=twin, period="30m",
                          pilot_first_hour=True, same_parent=True, git_repo=REPO)
        self.assertEqual(code, 2)
        gaps = {("candidate", n) for n in ("named_remainder", "newton_error", "process_amount", "process_share")}
        gaps |= {("reference", n) for n in ("copy_residual", "process_share")}
        self.assert_named_gaps(out, gaps)
        b = Bundle(out / "manifest.json")
        # Every field reads. The one validation error is the submission record's own gap.
        self.assertEqual(b.validate(), [SUBMISSION_GAP])
        # The rebuilt thicknesses reproduce the model's own integral of the water.
        q, rho = b.field("candidate", "water_parent"), b.field("candidate", "rho")
        with (cand / "water_tag_closure.csv").open() as stream:
            total = np.array([float(r["total"]) for r in csv.DictReader(stream)])
        self.assertLess(np.max(np.abs(integrate(density(q, rho), q.weights) / total - 1)), 1e-12)
        result = Scorer(Bundle(out / "manifest.json")).run()
        rows = {r["id"]: r for r in result["rows"]}
        self.assertEqual(rows["COMMON.PILOT_SCOPE"]["data_status"], "COMPLETE")
        # W58's recorded passes: R1 parity, R3 validity, R4 closure at 6 h.
        parity = rows["COMMON.PARENT_PARITY"]
        self.assertEqual((parity["verdict"], parity["metrics"]["differing"]), ("NOT ASSESSABLE", []))
        self.assertEqual(rows["COMMON.NEGATIVE_WATER"]["verdict"], "PASS")
        self.assertEqual(rows["COMMON.PARENT_TEMPERATURE"]["verdict"], "PASS")
        self.assertAlmostEqual(rows["COMMON.PARENT_TEMPERATURE"]["metrics"]["top_change_K"], 0.3, places=2)
        self.assertLess(rows["WATER.CLOSURE"]["metrics"]["gross_over_raw"], 4e-15)
        self.assertEqual(rows["WATER.CLOSURE"]["verdict"], "REPORTED ONLY")
        # The first-hour rows: measured, within the first-hour limits, and blocked by named prerequisites.
        blocked = ("failed/unavailable prerequisite: COMMON.PARENT_PARITY, REFERENCE.ELIGIBILITY.startup, "
                   "REFERENCE.ELIGIBILITY.sensitivity_1h")
        for tag in ("pbl", "free", "evap"):
            row = rows[f"WATER.ORIGINS.{tag}.3600"]
            self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "COMPLETE"))
            self.assertEqual(row["limitation"], blocked)
            self.assertEqual(rows[f"WATER.ORIGINS.{tag}.86400"]["verdict"], "NOT APPLICABLE")
        m = {t: rows[f"WATER.ORIGINS.{t}.3600"]["metrics"] for t in ("pbl", "free", "evap")}
        self.assertTrue(m["pbl"]["L1"] <= 0.01 and m["pbl"]["Linf"] <= 0.25)
        self.assertTrue(m["free"]["L1"] <= 0.01 and m["free"]["Linf"] <= 0.25)
        # evap holds 0.12% of the water at 1 h, so the small-tag absolute rule applies. Its L1 is W58's 7.4%.
        self.assertLess(m["evap"]["reference_share"], 0.01)
        self.assertLessEqual(m["evap"]["absolute_L1"], m["evap"]["small_absolute_limit"])
        self.assertAlmostEqual(m["evap"]["L1"], 0.074, places=3)
        # The per-tag ledgers are written each 30 min, and the scorer reads accepted steps.
        self.assertIn("missing sample or wrong cadence", rows["WATER.LED_FIX.pbl.startup"]["limitation"])
        self.assertEqual(result["exit_code"], 2)

    def test_e87_energy_process_budget(self):
        cand, twin = require_runs("g46_d4_budget", "g46_d4_untagged")
        out = self.root / "e87"
        code, _ = convert(out, family="energy_source", candidate=cand, untagged=twin, git_repo=REPO)
        self.assertEqual(code, 2)
        absent = ("rad", "sfc", "sub", "mp", "new_strat", "new_tropo")
        tags = ("strat", "tropo") + absent
        gaps = {("candidate", n) for n in ("negative_water_void", "source_partition_valid", "newton_error",
                                           "process_amount", "process_share")}
        gaps |= {("candidate", f"{k}_{t}") for t in absent for k in ("tag", "led_src")}
        gaps |= {("candidate", f"led_{k}_{t}") for t in tags for k in ("fix", "inc")}
        gaps |= {("candidate", f"led_{k}_{t}_applicable") for t in tags for k in ("fix", "inc")}
        gaps |= {("untagged", "energy_parent")}
        self.assert_named_gaps(out, gaps)
        b = Bundle(out / "manifest.json")
        errors = b.validate()
        self.assertIn(SUBMISSION_GAP, errors)
        self.assertTrue(all(e in (SUBMISSION_GAP, "missing evidence path") for e in errors), errors)
        # The rebuilt thicknesses reproduce the model's integral of the partition's tags.
        rho = b.field("candidate", "rho")
        tagged = sum(integrate(density(b.field("candidate", "tag_" + t), rho), rho.weights) for t in ("strat", "tropo"))
        with (cand / "energy_source_tag_closure.csv").open() as stream:
            table = np.array([float(r["tagged"]) for r in csv.DictReader(stream)])
        self.assertLess(np.max(np.abs(tagged / table - 1)), 1e-12)
        # Θx resolves from the closure table: the day's 2.09e7 J m^-2, of which E87's c M_U is 0.55%.
        theta = cumulative_amount(b.field("candidate", "throughput"), 0, 86400, "accepted_step_source_variation")
        self.assertAlmostEqual(theta / 2.0916663292678468e7, 1, places=12)
        rows = {r["id"]: r for r in Scorer(Bundle(out / "manifest.json")).run()["rows"]}
        for window in ("startup", "sensitivity_1h"):
            row = rows["ENERGY.CLOSURE_GROWTH." + window]
            self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "DATA FAILURE"))
            self.assertIn("missing candidate variable: source_partition_valid", row["limitation"])
        self.assertEqual(rows["ENERGY.CLOSURE_GROWTH.established"]["verdict"], "NOT APPLICABLE")
        self.assertIn("missing untagged variable: energy_parent", rows["COMMON.OD2_WINDOWS"]["limitation"])
        record_row = rows["ENERGY.CORRECTED_RECORD_ESTIMATE.startup"]
        self.assertEqual((record_row["verdict"], record_row["data_status"]), ("REPORTED ONLY", "COMPLETE"))
        self.assertEqual(sorted(record_row["metrics"]["processes"]),
                         ["microphysics", "precipitation", "radiation", "subsidence", "surface_flux"])


if __name__ == "__main__":
    unittest.main()
