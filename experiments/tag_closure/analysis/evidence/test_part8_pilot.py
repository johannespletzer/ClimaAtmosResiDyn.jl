"""Tests of part8_pilot.py, the glue of the part 8 pilot (design/PART8_BASELINE.md).

The first class reproduces W58's recorded TRMM verdict from the repository's
own `output/g3base/` tables, so it always runs. The synthetic classes check
the OD2 reading and the ranking rule against values worked out by hand. The
last class reads W58's NetCDF output where it is present and skips with the
reason otherwise.
"""

import contextlib
import csv
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

import part8_pilot
from acceptance_data import DataError
from part8_pilot import (FIX_CANDIDATES, LIMITS, compare_w58, main, od2_reading, rank_terms, row_at,
                         run_tables, table_rows)

RECORD = Path(__file__).resolve().parents[2] / "output" / "g3base"
DATA = RECORD / "data"
SCORES = RECORD / "g3base_scores.csv"


def run_main(args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main([str(a) for a in args])
    return code, out.getvalue(), err.getvalue()


class LimitTests(unittest.TestCase):
    def test_limits_are_the_approved_numbers(self):
        # The glue reads every limit from the scorer. These are the approved values.
        self.assertEqual(LIMITS, {"WATER_GROSS": 2e-3, "COPIES_RESIDUAL_MAX": 2e-4,
                                  "COMPARATOR_REPAIR_PER_DAY": 2e-3, "AGGREGATE_REPAIR_PER_DAY": 5e-3,
                                  "LED_FIX_MAX": 0.02, "NEWTON_MAX": 1e-3})

    def test_pilot_constants(self):
        self.assertEqual((part8_pilot.DAY, part8_pilot.TRMM_END), (86400.0, 21600.0))
        self.assertEqual(part8_pilot.TRMM_TAGS, ("pbl", "free", "evap"))
        self.assertEqual(part8_pilot.TRMM_KINDS, {"pbl": "region", "free": "region", "evap": "source"})

    def test_row_at_reads_the_first_row_at_or_after(self):
        table = [{"time": 0.0}, {"time": 1800.0 - 5e-7}, {"time": 3600.0}]
        self.assertIs(row_at(table, 1800.0), table[1])
        self.assertIs(row_at(table, 1800.1), table[2])
        with self.assertRaisesRegex(DataError, "no table row"):
            row_at(table, 3600.1)


class W58RecordTests(unittest.TestCase):
    """W58's recorded verdict, from the tables committed with the record."""

    def test_repository_tables_match_their_checksums(self):
        sums = {}
        for line in (RECORD / "SHA256SUMS_copied_data").read_text().splitlines():
            digest, name = line.split(maxsplit=1)
            sums[name.removeprefix("./")] = digest
        for mode in ("default", "copies"):
            for table in ("water_tag_closure.csv", "water_tag_audit.csv"):
                rel = f"g3b_trmm0m_{mode}_6h/{table}"
                self.assertEqual(hashlib.sha256((DATA / rel).read_bytes()).hexdigest(), sums[rel], rel)

    def test_every_recorded_table_row_is_reproduced(self):
        result = compare_w58(DATA, SCORES)
        self.assertEqual(result["differences"], [])
        with SCORES.open() as stream:
            recorded = [r for r in csv.DictReader(stream) if r["case"] == "trmm" and r["rule"] in ("R4", "R5", "R8")]
        self.assertEqual(len(result["reproduced"]), len(recorded))
        self.assertEqual(len(recorded), 18)

    def test_recorded_verdicts_and_their_contract_reading(self):
        rows = {(r["rule"], r["mode"], r["metric"], r["recorded_verdict"]): r
                for r in compare_w58(DATA, SCORES)["reproduced"]}
        closure = rows[("R4", "default", "gross residual at 6 h, of the water", "pass")]
        self.assertEqual(closure["contract"], "reported: the approved closure is at 24 h")
        self.assertEqual(closure["limit_id"], "WATER_GROSS")
        repair = rows[("R5", "copies", "copies' repair, gross, per day", "pass")]
        self.assertEqual(repair["recorded_value"], "0.0005052242884890633")
        self.assertEqual(repair["limit_id"], "COMPARATOR_REPAIR_PER_DAY")
        self.assertIn(("R8", "copies", "led_fix inventory fraction, pbl", "pass"), rows)

    def test_tables_carry_the_counts_and_px5_share(self):
        rows = {(r["rule"], r["metric"]): r for r in run_tables(DATA / "g3b_trmm0m_copies_6h", "copies")}
        share = rows[("PX5", "the filter's share of the copies' two corrections")]
        self.assertEqual((share["limit_id"], share["legacy_verdict"]), (None, "reported"))
        self.assertTrue(0 <= share["value"] <= 1)
        events = rows[("EV", "intervention events at the end")]
        self.assertEqual(events["value"], 15317.0)
        self.assertIn("led_uprepair", events["note"])

    def test_a_changed_value_is_a_difference(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = SCORES.read_text().replace("0.0005052242884890633", "0.0005052242884890634", 1)
            changed = Path(tmp) / "scores.csv"
            changed.write_text(text)
            result = compare_w58(DATA, changed)
            self.assertEqual(len(result["differences"]), 1)
            self.assertEqual(result["differences"][0]["rule"], "R5")
            code, _, _ = run_main(["w58", DATA, changed])
            self.assertEqual(code, 1)

    def test_a_changed_verdict_is_a_difference(self):
        with tempfile.TemporaryDirectory() as tmp:
            lines = SCORES.read_text().splitlines(keepends=True)
            i = next(k for k, line in enumerate(lines) if line.startswith("R4,trmm,copies,\"gross"))
            lines[i] = lines[i].replace(",pass,", ",fail,")
            changed = Path(tmp) / "scores.csv"
            changed.write_text("".join(lines))
            self.assertEqual(len(compare_w58(DATA, changed)["differences"]), 1)

    def test_rerun_prefix_reads_the_runs_output_tree(self):
        # The model writes each run's tables under <run>/output_0000, as W58's
        # output on scratch has them. The rerun is read from that tree.
        with tempfile.TemporaryDirectory() as tmp:
            for mode in ("default", "copies"):
                src, dst = DATA / f"g3b_trmm0m_{mode}_6h", Path(tmp) / f"p8_trmm0m_{mode}_6h" / "output_0000"
                dst.mkdir(parents=True)
                for table in ("water_tag_closure.csv", "water_tag_audit.csv"):
                    (dst / table).write_bytes((src / table).read_bytes())
            self.assertEqual(compare_w58(tmp, SCORES, "p8")["differences"], [])
            code, out, _ = run_main(["w58", tmp, SCORES, "--prefix", "p8"])
            self.assertEqual((code, json.loads(out)["differences"]), (0, []))
            with self.assertRaisesRegex(DataError, "missing table"):
                compare_w58(tmp, SCORES)

    def test_command_line(self):
        code, out, _ = run_main(["w58", DATA, SCORES])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["differences"], [])
        code, _, err = run_main(["w58", DATA / "absent", SCORES])
        self.assertEqual(code, 2)
        self.assertIn("DATA FAILURE", err)


def audit_row(time, repair=0.0, uprepair=0.0, upfilter=0.0, residual=0.0):
    return {"time": time, "led_repair_retained": repair, "led_fix_pbl_inventory_fraction": 0.0,
            "led_fix_pbl_retained": 0.0, "led_fix_pbl_events": 0.0, "led_uprepair_events": 4.0,
            "copy_residual_relative": residual, "led_uprepair_retained": uprepair, "copy_repair_relative": -uprepair,
            "led_upfilter_retained": upfilter}


class TableRowTests(unittest.TestCase):
    """table_rows on one hand-made day, where every value is worked out exactly."""

    def rows(self):
        # The water is 1 at the end and its mean over the window is 4/3. The
        # copies' repair retains 2e-3 in one day, exactly COMPARATOR_REPAIR_PER_DAY.
        closure = [{"time": t, "gross_relative": g, "gross_residual": g, "total": w}
                   for t, g, w in ((0.0, 0.0, 1.0), (43200.0, 1e-4, 2.0), (86400.0, 3e-4, 1.0))]
        audit = [audit_row(0.0), audit_row(43200.0, 1e-3, 1e-3, 5e-4, 2e-5),
                 audit_row(86400.0, 2e-3, 2e-3, 1e-3, 1e-5)]
        return table_rows(closure, audit, "copies", end=86400.0, tags=("pbl",))

    def test_values_windows_and_verdicts(self):
        rows = {(r["rule"], r["metric"], r["window"]): r for r in self.rows()}
        # The scored repair row and its reported whole-run twin carry one value.
        # A value at the limit passes, as in g3base_score.py.
        repair, twin = [r for r in self.rows() if r["metric"] == "copies' repair, gross, per day"]
        self.assertEqual((repair["value"], repair["legacy_verdict"]), (2e-3, "pass"))
        self.assertEqual((twin["value"], twin["legacy_verdict"]), (2e-3, "reported"))
        self.assertIn("over the window's mean water 1.500e-03", repair["note"])
        partition = rows[("R8", "partition repair retained gross per day", "whole run")]
        self.assertEqual((partition["value"], partition["legacy_verdict"]), (2e-3, "pass"))
        # PX5: the filter's share of the two corrections, 1e-3 / (1e-3 + 2e-3).
        share = rows[("PX5", "the filter's share of the copies' two corrections", "whole run")]
        self.assertAlmostEqual(share["value"], 1 / 3, places=15)
        own = rows[("R5", "copies' own residual, max over outputs", "whole run")]
        self.assertEqual(own["value"], 2e-5)
        self.assertEqual(rows[("R4", "gross residual at 24 h, of the water", "24 h")]["value"], 3e-4)
        self.assertEqual(sorted({r["window"] for r in self.rows()}), ["0-half-end", "24 h", "whole run"])

    def test_scorer_fraction_by_tag_kind_and_the_exemption(self):
        # pbl is a region tag: inventory 2, burden 4, parent scale 100. evap is
        # a source tag: inventory 1, burden 0.01, parent scale 100, so its
        # burden is 1e-4 of the scale, below SMALL, and the scorer exempts it.
        closure = [{"time": t, "gross_relative": 0.0, "gross_residual": 0.0, "total": 1.0}
                   for t in (0.0, 86400.0)]

        def row(time, fix):
            r = audit_row(time)
            r.update({"led_fix_pbl_retained": fix, "led_fix_pbl_inventory_fraction": fix / 2,
                      "led_fix_pbl_burden_fraction": fix / 4, "led_fix_pbl_parent_fraction": fix / 100,
                      "led_fix_evap_retained": fix, "led_fix_evap_events": 1.0,
                      "led_fix_evap_inventory_fraction": fix / 1, "led_fix_evap_burden_fraction": fix / 0.01,
                      "led_fix_evap_parent_fraction": fix / 100})
            return r

        rows = table_rows(closure, [row(0.0, 0.0), row(86400.0, 1e-3)], "default", end=86400.0,
                          tags=("pbl", "evap"))
        by = {(r["metric"]): r for r in rows if r["metric"].startswith("led_fix")}
        self.assertAlmostEqual(by["led_fix inventory fraction, pbl"]["value"], 5e-4)
        pbl = by["led_fix scorer fraction, pbl"]
        self.assertAlmostEqual(pbl["value"], 5e-4)
        self.assertEqual((pbl["legacy_verdict"], pbl["note"]),
                         (("pass" if 5e-4 <= LIMITS["LED_FIX_MAX"] else "fail"), "region tag over its signed inventory"))
        self.assertEqual(pbl["contract"], "scored per OD2 window by the scorer, at accepted-step cadence")
        evap = by["led_fix scorer fraction, evap"]
        self.assertAlmostEqual(evap["value"], 0.1)
        self.assertEqual((evap["contract"], evap["note"]),
                         ("not applicable", "source tag over its absolute burden, small-burden exemption"))
        self.assertAlmostEqual(by["led_fix inventory fraction, evap"]["value"], 1e-3)


def write_run(directory, times, water_column, z=(50.0, 200.0, 500.0), z_max=700.0, period="10m"):
    """An untagged run with hus and rhoa at one period. rhoa is 1, so the column water is Σ q Δz."""
    directory.mkdir(parents=True)
    (directory / "manifest.json").write_text("{}")
    (directory / "twin.yml").write_text(f"job_id: twin\nz_max: {z_max}\n")
    z = np.asarray(z)
    dz = np.diff(np.concatenate(([0.0], np.cumsum(2 * np.diff(np.concatenate(([0.0], z)))))))
    q = np.outer(np.asarray(water_column) / dz.sum(), np.ones(len(z)))
    for name, values, units in (("hus", q, "kg kg^-1"), ("rhoa", np.ones_like(q), "kg m^-3")):
        with Dataset(directory / f"{name}_{period}_inst.nc", "w") as ds:
            ds.createDimension("time", None)
            ds.createDimension("z", len(z))
            t = ds.createVariable("time", "f8", ("time",))
            t.units = "s"
            t[:] = times
            zv = ds.createVariable("z", "f8", ("z",))
            zv.units = "m"
            zv[:] = z
            v = ds.createVariable(name, "f8", ("time", "z"))
            v.units = units
            v[:] = values


class OD2Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_boundary_after_a_startup_pulse(self):
        # Rates per 600 s interval: 10, 5, 0.5, 0.5, 0.5, 0.5. The peak is 10, so
        # 10% is 1, and the first of three intervals below it starts at 1200 s.
        times = np.arange(7) * 600.0
        water = 100.0 + np.cumsum([0.0, 6000.0, 3000.0, 300.0, 300.0, 300.0, 300.0])
        write_run(self.root / "run", times, water)
        reading = od2_reading(self.root / "run")
        self.assertEqual(reading["startup_end_seconds"], 1200.0)
        self.assertEqual((reading["cadence_seconds"], reading["samples"]), (600.0, 7))
        self.assertTrue(reading["established"])

    def test_no_boundary_when_the_rate_keeps_rising(self):
        times = np.arange(7) * 600.0
        water = 100.0 + np.cumsum([0.0, 60.0, 120.0, 240.0, 480.0, 960.0, 1920.0])
        write_run(self.root / "run", times, water)
        reading = od2_reading(self.root / "run")
        self.assertIsNone(reading["startup_end_seconds"])
        self.assertFalse(reading["established"])

    def test_wrong_top_face_is_refused(self):
        times = np.arange(7) * 600.0
        write_run(self.root / "run", times, 100.0 + times, z_max=800.0)
        from convert_output import ConversionError
        with self.assertRaisesRegex(ConversionError, "differs from z_max"):
            od2_reading(self.root / "run")

    def test_missing_period_is_a_data_failure(self):
        write_run(self.root / "run", np.arange(7) * 600.0, np.full(7, 100.0))
        with self.assertRaisesRegex(DataError, "no hus_30m_inst.nc"):
            od2_reading(self.root / "run", "30m")

    def test_command_line(self):
        # The command reads the twin's 10 min output unless told otherwise.
        times = np.arange(7) * 600.0
        write_run(self.root / "run", times, 100.0 + np.cumsum([0.0, 6000.0, 3000.0, 300.0, 300.0, 300.0, 300.0]))
        code, out, _ = run_main(["od2", self.root / "run"])
        self.assertEqual(code, 0)
        self.assertEqual((json.loads(out)["period"], json.loads(out)["startup_end_seconds"]), ("10m", 1200.0))
        # A missing directory or a wrong top face is an input failure, exit 2.
        code, _, err = run_main(["od2", self.root / "absent"])
        self.assertEqual(code, 2)
        self.assertIn("DATA FAILURE", err)
        write_run(self.root / "tall", times, 100.0 + times, z_max=800.0)
        self.assertEqual(run_main(["od2", self.root / "tall"])[0], 2)


def score(rows):
    return {"rows": [{"id": k, "verdict": v, "metrics": m, "limitation": ""} for k, (v, m) in rows.items()]}


def tables(mode):
    rows = [{"rule": "R8", "metric": "partition repair retained gross per day", "value": 1e-3,
             "limit_id": "AGGREGATE_REPAIR_PER_DAY", "contract": "c", "note": ""},
            {"rule": "R8", "metric": "led_fix scorer fraction, pbl", "value": 0.01,
             "limit_id": "LED_FIX_MAX", "contract": "c", "note": "events 3"},
            {"rule": "EV", "metric": "intervention events at the end", "value": 12.0, "limit_id": None,
             "contract": "reported", "note": ""}]
    if mode == "copies":
        rows += [{"rule": "R5", "metric": "copies' repair, gross, per day", "value": 1.5e-3,
                  "limit_id": "COMPARATOR_REPAIR_PER_DAY", "contract": "c", "note": ""},
                 {"rule": "R5", "metric": "copies' own residual, max over outputs", "value": 1e-5,
                  "limit_id": "COPIES_RESIDUAL_MAX", "contract": "c", "note": ""},
                 {"rule": "PX5", "metric": "the filter's share of the copies' two corrections", "value": 0.0,
                  "limit_id": None, "contract": "reported", "note": ""}]
    return rows


class RankTests(unittest.TestCase):
    def default_score(self):
        return score({
            "WATER.CLOSURE": ("REPORTED ONLY", {"gross_over_raw": 1e-3}),
            "WATER.ORIGINS.pbl.3600": ("NOT ASSESSABLE", {"L1": 0.002, "Linf": 0.2}),
            "WATER.ORIGINS.free.3600": ("NOT ASSESSABLE", {"L1": 0.004, "Linf": 0.01}),
            "WATER.ORIGINS.evap.3600": ("NOT ASSESSABLE", {"L1": 0.5, "Linf": 0.9, "absolute_L1": 1e-4,
                                                           "small_absolute_limit": 4e-4,
                                                           "reference_share": 0.001}),
            "WATER.PRECIP_INSTANTANEOUS": ("REPORTED ONLY", {"max_absolute_rate_defect": 1e-19}),
            "COMMON.ACCEPTED_APPLICATION_ACTIVITY": ("NOT ASSESSABLE", {}),
        })

    def assessed_score(self):
        """The origin rows as they read once PX12's eligibility file gives them a verdict."""
        return score({
            "WATER.CLOSURE": ("REPORTED ONLY", {"gross_over_raw": 1e-3}),
            "WATER.ORIGINS.pbl.3600": ("FAIL", {"L1": 0.002, "Linf": 0.2}),
            "WATER.ORIGINS.free.3600": ("PASS", {"L1": 0.004, "Linf": 0.01}),
            "WATER.ORIGINS.evap.3600": ("PASS", {"L1": 0.03, "Linf": 0.05, "absolute_L1": 1e-3,
                                                 "reference_share": 0.2}),
        })

    def test_order_by_fraction_of_the_cited_limit(self):
        rows = rank_terms("default", self.assessed_score(), tables("default"), 4e-3, "W57")
        ranked = [(r["rank"], r["term"]) for r in rows if r["rank"] != ""]
        # Fractions: pbl max(0.002/0.01, 0.2/0.25) = 0.8, closure 0.5, led_fix 0.5,
        # free max(0.4, 0.04) = 0.4, evap as a source tag max(0.03/0.10, 0.05/0.25) = 0.3,
        # partition repair 0.2.
        self.assertEqual([t for _, t in ranked], ["origin_first_hour:pbl", "closure_residual", "led_fix:pbl",
                                                  "origin_first_hour:free", "origin_first_hour:evap",
                                                  "partition_repair"])
        self.assertEqual([k for k, _ in ranked], list(range(1, 7)))
        by = {r["term"]: r for r in rows}
        self.assertAlmostEqual(by["origin_first_hour:pbl"]["fraction_of_limit"], 0.8)
        self.assertAlmostEqual(by["origin_first_hour:evap"]["fraction_of_limit"], 0.3)
        self.assertEqual(by["origin_first_hour:evap"]["observable"], "L1 at 1 h")

    def test_not_assessable_origins_are_readings(self):
        # Until PX12 the scorer marks the first-hour origins NOT ASSESSABLE. They
        # are listed after the ranked terms, without a fraction (design section 7).
        rows = rank_terms("default", self.default_score(), tables("default"), 4e-3, "W57")
        ranked = [(r["rank"], r["term"]) for r in rows if r["rank"] != ""]
        self.assertEqual(ranked, [(1, "closure_residual"), (2, "led_fix:pbl"), (3, "partition_repair")])
        by = {r["term"]: r for r in rows}
        self.assertEqual((by["origin_first_hour:pbl"]["rank"], by["origin_first_hour:pbl"]["status"]),
                         ("", "NOT ASSESSABLE"))
        # A reading shows its value and its comparator and no fraction of a limit.
        self.assertIsNone(by["origin_first_hour:pbl"]["fraction_of_limit"])
        self.assertEqual(by["origin_first_hour:pbl"]["value"], 0.002)
        self.assertTrue(by["origin_first_hour:pbl"]["note"].startswith("reading against the copies"))
        self.assertEqual(by["origin_first_hour:evap"]["observable"], "absolute L1 (small tag)")
        self.assertIsNone(by["origin_first_hour:evap"]["fraction_of_limit"])
        self.assertEqual(by["origin_first_hour:evap"]["value"], 1e-4)

    def test_prior_and_unlimited_terms_are_listed_not_ranked(self):
        rows = rank_terms("default", self.default_score(), tables("default"), 4e-3, "W57")
        tail = [r for r in rows if r["rank"] == ""]
        self.assertEqual([r["term"] for r in tail], ["origin_first_hour:pbl", "origin_first_hour:free",
                                                     "origin_first_hour:evap", "intervention_events",
                                                     "parent_newton", "precip_sum_defect"])
        newton = tail[4]
        self.assertAlmostEqual(newton["fraction_of_limit"], 4.0)
        self.assertEqual((newton["status"], newton["source"]), ("prior, another case", "W57"))
        self.assertTrue(all(rows.index(r) >= 3 for r in tail))

    def test_copies_terms_and_no_comparator(self):
        s = score({"WATER.CLOSURE": ("REPORTED ONLY", {"gross_over_raw": 2e-4}),
                   "WATER.ORIGINS.pbl.3600": ("NOT ASSESSABLE", {})})
        rows = rank_terms("copies", s, tables("copies"))
        terms = [r["term"] for r in rows]
        self.assertNotIn("origin_first_hour:pbl", terms)
        self.assertNotIn("parent_newton", terms)
        self.assertEqual(terms[0], "copies_repair")
        self.assertAlmostEqual(rows[0]["fraction_of_limit"], 0.75)
        self.assertEqual(rows[0]["fix_candidate"], FIX_CANDIDATES["copies_repair"]["copies"])

    def test_every_term_names_a_fix_candidate(self):
        for mode, s in (("default", self.default_score()), ("copies", score({}))):
            for r in rank_terms(mode, s, tables(mode), 4e-3, "W57"):
                self.assertTrue(r["fix_candidate"], r["term"])
                self.assertTrue(r["source"], r["term"])

    def test_unknown_limit_is_refused(self):
        bad = tables("default")
        bad[0]["limit_id"] = "NOT_A_LIMIT"
        with self.assertRaisesRegex(DataError, "unknown limit"):
            rank_terms("default", self.default_score(), bad)

    def test_command_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "score.json").write_text(json.dumps(self.default_score()))
            (root / "tables.json").write_text(json.dumps(tables("default")))
            args = ["rank", "--mode", "default", "--score", root / "score.json", "--tables", root / "tables.json"]
            code, _, err = run_main(args + ["--newton", "4e-3", "--out", root / "a.csv"])
            self.assertEqual(code, 2)
            self.assertIn("needs its source", err)
            code, _, _ = run_main(args + ["--out", root / "b.csv"])
            self.assertEqual(code, 0)
            with (root / "b.csv").open() as stream:
                header = next(csv.reader(stream))
            self.assertEqual(tuple(header), part8_pilot.COLUMNS)
            code, _, _ = run_main(args + ["--out", root / "b.csv"])
            self.assertEqual(code, 2)


TREE = Path(__file__).resolve().parents[2]
MAIN = "bb2bedf230a70ca9d7afc293180f8d30c1a9bb88"


def without_identity(text):
    """A config without its comment lines and its job_id."""
    return [line for line in text.splitlines() if not line.startswith("#") and not line.startswith("job_id:")]


def active_lines(text):
    """A script without its comment lines, so a header comment cannot satisfy a test."""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def run_beside_stub(root, script, stub, args):
    """Run a copy of `script` with a stub of the script it calls, which prints its environment and arguments.

    The copy sits at <root>/experiments/tag_closure/runscripts, so its own
    tree is <root>. Nothing reaches Slurm or git.
    """
    import os
    import subprocess
    here = root / "experiments" / "tag_closure" / "runscripts"
    here.mkdir(parents=True, exist_ok=True)
    (here / script).write_text((TREE / "runscripts" / script).read_text())
    (here / stub).write_text('#!/usr/bin/env bash\necho "CONFIG=${CONFIG:-} EXPECT_SHA=${EXPECT_SHA:-} '
                             'KIND=${KIND:-} SET=${SET:-} ARGS=$*"\n')
    (here / stub).chmod(0o755)
    env = dict(os.environ, RUN_TREE=str(root / "run"), REC_TREE=str(root), SCRATCH=str(root / "scratch"))
    done = subprocess.run(["bash", str(here / script), *args], capture_output=True, text=True, env=env)
    lines = [dict(part.split("=", 1) for part in line.split(" ARGS=")[0].split()) | {"ARGS": line.split(" ARGS=")[1]}
             for line in done.stdout.splitlines()]
    return done.returncode, lines


class JobScriptTests(unittest.TestCase):
    def test_trio_configs_are_w58s(self):
        for mode in ("untagged", "default", "copies"):
            w58 = (TREE / "configs" / f"g3b_trmm0m_{mode}_6h.yml").read_text()
            p8 = (TREE / "configs" / f"p8_trmm0m_{mode}_6h.yml").read_text()
            self.assertEqual(without_identity(p8), without_identity(w58), mode)
            self.assertIn(f'job_id: "p8_trmm0m_{mode}_6h"', p8)

    def test_trio_script(self):
        text = active_lines((TREE / "runscripts" / "part8_trio.sh").read_text())
        self.assertIn(f"EXPECT_SHA={MAIN}", text)
        self.assertIn("RUNS=(untagged default copies)", text)

    def test_trio_dry_run_by_default(self):
        # Each job takes a whole node with W58's 2 CPUs and 48G, at most 1 h,
        # and reads its own p8 config. Without --submit every call is a dry run.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            code, calls = run_beside_stub(root, "part8_trio.sh", "g3base_submit.sh", [])
            self.assertEqual(code, 0)
            self.assertEqual(len(calls), 3)
            logs = root / "scratch" / "tag_closure" / "logs" / "part8"
            for run, call in zip(("untagged", "default", "copies"), calls):
                name = f"p8_trmm0m_{run}_6h"
                self.assertEqual(call["CONFIG"], f"experiments/tag_closure/configs/{name}.yml")
                self.assertTrue((TREE / "configs" / f"{name}.yml").is_file())
                self.assertEqual((call["EXPECT_SHA"], call["KIND"]), (MAIN, "run"))
                self.assertEqual(call["ARGS"].split(), [
                    "--dry-run", "--account=pn49go-c", "--partition=hpda2_compute", "--time=01:00:00",
                    "--nodes=1", "--ntasks=1", "--cpus-per-task=2", "--mem=48G", "--exclusive",
                    f"--job-name={name}", f"--output={logs}/%x-%j.out", f"--error={logs}/%x-%j.err"])
            code, calls = run_beside_stub(root, "part8_trio.sh", "g3base_submit.sh", ["--submit", "copies"])
            self.assertEqual((code, len(calls)), (0, 1))
            self.assertEqual(calls[0]["CONFIG"], "experiments/tag_closure/configs/p8_trmm0m_copies_6h.yml")
            self.assertNotIn("--dry-run", calls[0]["ARGS"])
            self.assertEqual(run_beside_stub(root, "part8_trio.sh", "g3base_submit.sh", ["twin"])[0], 1)

    def test_cost_dry_run_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            code, calls = run_beside_stub(root, "part8_cost.sh", "submit_wp9.sh", [])
            self.assertEqual((code, [(c["SET"], c["ARGS"]) for c in calls]), (0, [("p8", "--dry-run")]))
            code, calls = run_beside_stub(root, "part8_cost.sh", "submit_wp9.sh", ["p8_copies_a", "p8_default_b"])
            self.assertEqual([(c["SET"], c["ARGS"]) for c in calls], [("p8", "--dry-run p8_copies_a p8_default_b")])
            code, calls = run_beside_stub(root, "part8_cost.sh", "submit_wp9.sh", ["--submit", "p8_copies_a"])
            self.assertEqual([(c["SET"], c["ARGS"]) for c in calls], [("p8", "p8_copies_a")])

    def test_cost_table(self):
        text = (TREE / "runscripts" / "submit_wp9.sh").read_text()
        block = text[text.index('if [[ "${SET:-}" == p8 ]]'):]
        block = block[:block.index("\nfi\n")]
        self.assertTrue(MAIN.startswith(block.split("EXPECT_SHA=")[1].split()[0]))
        rows = [line.strip().strip('"').split() for line in block.splitlines() if line.strip().startswith('"p8_')]
        self.assertEqual([r[0] for r in rows], [f"p8_{m}_{k}" for m in ("default", "copies") for k in "abc"])
        for arm, family, mode, precip, base, points, mem, time, *limit in rows:
            self.assertEqual((family, precip, base, points, mem), ("both", "0", "wp9_energy_d4_edmf",
                                                                    "0,8:ledgers", "200G"))
            self.assertEqual(mode, arm.split("_")[1])
            self.assertEqual((time, limit), ("04:00:00", []) if mode == "default" else ("09:00:00", ["8h"]))
        block = active_lines(block)
        self.assertIn("WP9_WARMUP=50 WP9_REPEATS=6", block)
        self.assertIn("OUT_ROOT=wp9_cost_p8", block)
        self.assertIn("EXTRA=(--exclusive)", block)

    def test_scripts_parse(self):
        import subprocess
        for name in ("part8_trio.sh", "part8_cost.sh", "submit_wp9.sh"):
            done = subprocess.run(["bash", "-n", str(TREE / "runscripts" / name)], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)


# W58's NetCDF output, on scratch until the archive sync.
SCRATCH = Path("/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output")
ARCHIVE = Path("/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-archive/scratch_tag_closure/output")


def w58_twin():
    for root in (ARCHIVE, SCRATCH):
        d = root / "g3b_trmm0m_untagged_6h" / "output_0000"
        if (d / "manifest.json").is_file() and (d / "hus_10m_inst.nc").is_file():
            return d
    raise unittest.SkipTest(f"W58's untagged twin is absent (looked in {ARCHIVE} and {SCRATCH})")


class W58OutputTests(unittest.TestCase):
    def test_od2_depends_on_the_cadence(self):
        twin = w58_twin()
        ten = od2_reading(twin, "10m")
        self.assertEqual((ten["samples"], ten["cadence_seconds"]), (37, 600.0))
        # At 10 min the first three intervals are already below 10% of the
        # six-hour peak, which falls in the rain after 3 h.
        self.assertEqual(ten["startup_end_seconds"], 0.0)
        thirty = od2_reading(twin, "30m")
        self.assertIsNone(thirty["startup_end_seconds"])

    def test_w58_rows_from_the_output_tree(self):
        # The command of design section 6 step 6, on W58's own output tree.
        root = w58_twin().parents[1]
        code, out, _ = run_main(["w58", root, SCORES, "--prefix", "g3b"])
        self.assertEqual(code, 0)
        self.assertEqual((len(json.loads(out)["reproduced"]), json.loads(out)["differences"]), (18, []))


if __name__ == "__main__":
    unittest.main()
