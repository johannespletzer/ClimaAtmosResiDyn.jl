"""Tests of the part 9 converter, checks and proof builder on a synthetic fixture.

    python3 -m unittest discover -s experiments/tag_closure/analysis/evidence -p test_water_tag_applications.py -v

The fixture (make_water_tag_application_fixture.py) is synthetic. It follows
the producer's format at 2c63c5c53 and is never runtime evidence.
"""

import contextlib
import io
import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from netCDF4 import Dataset

import correction_accounting as ca
import make_water_tag_application_fixture as fx
import water_tag_application_checks as wchecks
import water_tag_application_proof as wproof
import water_tag_applications_convert as wc
from acceptance_data import Bundle
from manifest import sha256_file


def run_cli(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = wchecks.main(list(map(str, argv)))
    return code, out.getvalue()


def edit_receipt(run, change):
    path = Path(run) / wc.RECEIPT_FILE
    lines = [json.loads(x) for x in path.read_text().splitlines()]
    change(lines)
    path.write_text("".join(json.dumps(x) + "\n" for x in lines))


def edit_nc(path, name, change):
    with Dataset(path, "a") as ds:
        ds.set_auto_mask(False)
        value = np.asarray(ds[name][:])
        change(value)
        ds[name][:] = value


class Fixture(unittest.TestCase):
    dtype = np.float64

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.runs = fx.write_fixture(self.root / "fx", self.dtype)

    def tearDown(self):
        self.tmp.cleanup()

    def convert(self, run="on", **kw):
        out = self.root / f"conv_{run}"
        wc.convert(self.runs[run], out, self.runs[run] / "manifest.json", **kw)
        return out, Bundle(wc.standalone_bundle(out, self.runs[run] / "manifest.json"))


class TestConverter(Fixture):
    def test_reader_reads_converted_output(self):
        out, bundle = self.convert()
        header, steps = wc.read_receipt_lines(self.runs["on"])
        roster = header[wc.ROSTER_KEY]
        receipt = ca.read_receipt(bundle, wc.OUT_RECEIPT, roster)
        self.assertEqual(len(receipt.bounds), fx.STEPS)
        section = bundle.spec["correction_accounting"]
        self.assertEqual(section["required_channels"], roster)
        for channel in section["coverage"]:
            result, apps = ca.channel_metrics(bundle, channel, receipt, 0, fx.STEPS * fx.DT)
            self.assertEqual(apps.values.dtype, np.dtype(self.dtype))
            self.assertEqual(result["applied_records"], len(receipt.records[channel["id"]]))
        # Values, event scales and counters are the NetCDF's rows, bit for bit.
        arrays = wc.read_arrays(self.runs["on"])
        with np.load(out / wc.OUT_APPLICATIONS) as npz:
            ids = npz["repair_pbl_total__record_ids"].tolist()
            rows = [arrays["record_id"].index(i) for i in ids]
            self.assertEqual(npz["repair_pbl_total__values"].tobytes(), arrays["record_values"][rows].tobytes())
            flags = arrays["record_flags"][rows].astype(np.int64)
            for k, name in enumerate(ca.COUNTERS):
                np.testing.assert_array_equal(npz["repair_pbl_total__" + name], (flags >> k) & 1)
            self.assertTrue(any(npz["repair_pbl_total__" + n].any() for n in ca.COUNTERS))
        with np.load(out / wc.OUT_LEDGERS) as npz:
            np.testing.assert_array_equal(npz["time"], wc.edges_of(steps))
            self.assertEqual(npz["application_ledger_inc_free_total"].tobytes(),
                             np.ascontiguousarray(arrays["ledger"][:, 3 + 5, :]).tobytes())
        # The whole section runs. The gate stays closed without a proof.
        result = ca.evaluate_accounting(bundle, 0, fx.STEPS * fx.DT)
        self.assertEqual(result["verdict"], "NOT ASSESSABLE")
        self.assertIn("missing verified producer", result["limitation"])

    def test_model_diff_copied_never_recomputed(self):
        other = "ab" * 32
        edit_receipt(self.runs["on"], lambda lines: lines[0].update(model_diff_sha256=other))
        out = self.root / "conv"
        wc.convert(self.runs["on"], out)
        self.assertEqual(json.loads((out / wc.OUT_RECEIPT).read_text())["model_diff_sha256"], other)
        with self.assertRaisesRegex(wc.ConversionError, "diff_sha256"):
            wc.convert(self.runs["on"], self.root / "conv2", self.runs["on"] / "manifest.json")

    def test_two_tree_manifest(self):
        # The job manifest's head_sha is the record tree. The receipt is compared with its model entry,
        # and the bundle carries the model identity, with the record tree beside it.
        out, bundle = self.convert()
        self.assertEqual((bundle.manifest["head_sha"], bundle.manifest["record_head_sha"]),
                         (fx.COMMIT, fx.RECORD_COMMIT))
        manifest = self.runs["on"] / "manifest.json"
        data = json.loads(manifest.read_text())
        data["model"]["head_sha"] = fx.RECORD_COMMIT
        manifest.write_text(json.dumps(data))
        with self.assertRaisesRegex(wc.ConversionError, "model head_sha"):
            wc.convert(self.runs["on"], self.root / "x", manifest)
        # A single-tree manifest is its own model identity.
        del data["model"]
        data["head_sha"] = fx.COMMIT
        manifest.write_text(json.dumps(data))
        wc.convert(self.runs["on"], self.root / "y", manifest)
        one = json.loads(wc.standalone_bundle(self.root / "y", manifest).read_text())
        self.assertEqual(one["head_sha"], fx.COMMIT)
        self.assertNotIn("record_head_sha", one)

    def test_refusals(self):
        cases = {
            "roster object": (lambda l: l[0].update(water_tag_application_roster={"channels": []}), "list of unique"),
            "unsupported": (lambda l: l[0].update(water_tag_application_unsupported=[{"mechanism": "leak"}]),
                            "unsupported"),
            "commit": (lambda l: l[0].update(model_commit="0" * 40), "model_commit"),
            "edge": (lambda l: l[2].update(start_seconds=151.0), "contiguous"),
            "end": (lambda l: l[-1].update(end_seconds=601.0), "ledger_time"),
        }
        for name, (change, message) in cases.items():
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                edit_receipt(self.runs["on"], change)
                with self.assertRaisesRegex(wc.ConversionError, message):
                    wc.convert(self.runs["on"], self.root / "x", self.runs["on"] / "manifest.json")
        self.tearDown()
        self.setUp()
        (self.runs["on"] / "rhoa_150s_inst.nc").unlink()
        with self.assertRaisesRegex(wc.ConversionError, "rhoa"):
            wc.convert(self.runs["on"], self.root / "x")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(wc.main([str(self.runs["on"]), "--out", str(self.root / "fx")]), 4)

    def test_attach_refuses_a_bundle_rho_at_another_cadence(self):
        out, _ = self.convert()
        bundle = self.root / "bundle"
        bundle.mkdir()
        manifest = bundle / "manifest.json"
        manifest.write_text(json.dumps({"head_sha": fx.COMMIT, "diff_sha256": fx.DIFF, "acceptance": {
            "runs": {"candidate": {"fields": {"rho": {"cadence": 1800}}}}}}))
        with self.assertRaisesRegex(wc.ConversionError, "accepted-step period"):
            wc.attach(manifest, out)

    def test_pinned_names(self):
        self.assertEqual((wc.RECEIPT_FILE, wc.ARRAYS_FILE), ("water_tag_application_receipt.jsonl",
                                                              "water_tag_applications.nc"))
        self.assertEqual((wc.ROSTER_KEY, wc.CHANNELS_KEY, wc.UNSUPPORTED_KEY, wc.PRODUCER), (
            "water_tag_application_roster", "water_tag_application_channels", "water_tag_application_unsupported",
            "climaatmos.water_tag_applications"))
        self.assertEqual(wc.FLAGS_ATTRIBUTE, "fallback + 2 bound + 4 clamp + 8 zero_normalization")
        self.assertEqual(ca.COUNTERS, ("fallback", "bound", "clamp", "zero_normalization"))
        self.assertEqual((wc.LEDGER_PREFIX, wc.LEDGER_UNITS, wc.Z_MATCH_ULPS), ("application_ledger_", "kg m^-3", 4))
        self.assertEqual((wc.OUT_RECEIPT, wc.OUT_APPLICATIONS, wc.OUT_LEDGERS, wc.OUT_SECTION), (
            "application_receipt.json", "applications.npz", "application_ledgers.npz", "correction_accounting.json"))
        self.assertEqual(wchecks.LOG_PATTERN, r"^CHECK (?P<check>[a-z_]+): (?P<result>PASS|FAIL)\b")
        self.assertEqual(wchecks.DIAGNOSTIC_OPERATIONS, 2)
        self.assertEqual(wchecks.PRODUCER_CHECKPOINT_PREFIX, "tag_ledger.applications.")
        self.assertEqual(wchecks.MODEL_LEDGERS, (("q_tag_led_fix_", ("rescale", "empty", "repair", "close")),
                                                 ("q_tag_led_inc_", ("inc", "negative"))))
        self.assertEqual(set(wchecks.CHECK_KEYS.values()), set(wproof.GATE_CHECKS))
        config = wproof.load_registry()
        self.assertEqual(config["status"], "pending")
        self.assertEqual(config["producer_id"], wc.PRODUCER)
        self.assertEqual(config["source"]["commit"], "2c63c5c53b6c1e70ae7ab3c63367fca672c6dc15")
        self.assertEqual(config["entry"]["source_sha256"],
                         "c45fef7fbc654155ed1189169716086cc8a82222df7518f148cb06f01b98af94")
        self.assertEqual(config["entry"]["roster_key"], wc.ROSTER_KEY)
        self.assertEqual(config["entry"]["check_log_pattern"], wchecks.LOG_PATTERN)
        self.assertIsNone(config["entry"]["cts_version"])
        g = 1 - np.sqrt(2) / 2
        self.assertEqual(wchecks.ars222()["b_imp"], [0.0, 1 - g, g])
        self.assertEqual(wchecks.ars222()["b_exp"][0], 1 - 1 / (2 * g))


class TestConverterFloat32(Fixture):
    dtype = np.float32

    def test_reader_reads_float32(self):
        _, bundle = self.convert()
        self.assertEqual(bundle.spec["precision"], "Float32")
        result = ca.evaluate_accounting(bundle, 0, fx.STEPS * fx.DT)
        self.assertEqual(len(result["metrics"]["channels"]), 14)

    def test_float32_checks_pass(self):
        for argv in (("complete_active_roster", self.runs["on"]),
                     ("parent_bitwise_parity", self.runs["on"], self.runs["off"]),
                     ("restart", self.runs["on"], self.runs["restarted"])):
            code, out = run_cli(*argv)
            self.assertEqual(code, 0, out)


class TestChecks(Fixture):
    def commands(self):
        on = self.runs["on"]
        return {"accepted_weights": ("accepted_weights", on), "trial_rollback": ("trial_rollback", on, "--dt", 150),
                "newton_replacement": ("newton_replacement", on),
                "complete_active_roster": ("complete_active_roster", on),
                "parent_bitwise_parity": ("parent_bitwise_parity", on, self.runs["off"]),
                "all_channel_checkpoint_restart": ("restart", on, self.runs["restarted"])}

    def assert_fail(self, key, *argv):
        code, out = run_cli(*argv)
        self.assertNotEqual(code, 0, out)
        found = [m["result"] for m in re.finditer(wchecks.LOG_PATTERN, out, re.MULTILINE) if m["check"] == key]
        self.assertEqual(found, ["FAIL"], out)
        return out

    def test_all_pass(self):
        for key, argv in self.commands().items():
            code, out = run_cli(*argv)
            self.assertEqual(code, 0, out)
            self.assertEqual(out.splitlines()[0], f"CHECK {key}: PASS")
            self.assertEqual(wproof.check_result(out, key, wchecks.LOG_PATTERN), "PASS")

    def test_converted_directory_argument(self):
        # The cluster script converts first, with the run's manifest, then checks.
        out, _ = self.convert()
        (out / "manifest.json").unlink()
        for argv in (("accepted_weights", out), ("trial_rollback", out), ("complete_active_roster", out)):
            code, text = run_cli(*argv)
            self.assertEqual(code, 0, text)

    def test_accepted_weights_mutant(self):
        # b_exp set to b_imp: the reader still passes, only implicit stages are weighted.
        edit_receipt(self.runs["on"], lambda l: l[0]["integrator_pin"].update(b_exp=l[0]["integrator_pin"]["b_imp"]))
        self.assertIn("b_exp", self.assert_fail("accepted_weights", *self.commands()["accepted_weights"]))

    def test_trial_rollback_mutant(self):
        edit_nc(self.runs["on"] / wc.ARRAYS_FILE, "ledger", lambda v: v.__setitem__((3, 0, 1), v[3, 0, 1] + 1e-9))
        self.assertIn("without an applied record", self.assert_fail("trial_rollback", *self.commands()["trial_rollback"]))

    def test_newton_replacement_mutant(self):
        def twice(lines):
            for app in lines[1]["applications"]:
                if app["channel"] == "inc.pbl.total" and app["stage"] == 3:
                    app["stage"] = 2
                    app["coefficient"] = fx.DT * lines[0]["integrator_pin"]["b_imp"][1]
        edit_receipt(self.runs["on"], twice)
        self.assertIn("second implicit", self.assert_fail("newton_replacement", *self.commands()["newton_replacement"]))

    def test_complete_active_roster_mutants(self):
        # A writer the roster misses: the model's fix ledger moves more than the records.
        edit_nc(self.runs["on"] / "q_tag_led_fix_free_150s_inst.nc", "q_tag_led_fix_free",
                lambda v: v.__setitem__((2, 3), v[2, 3] * 1.001 + 1e-9))
        self.assertIn("q_tag_led_fix_free", self.assert_fail("complete_active_roster",
                                                             *self.commands()["complete_active_roster"]))
        # A tag the producer did not instrument.
        self.tearDown()
        self.setUp()
        config = next(self.runs["on"].glob("*.yml"))
        config.write_text(config.read_text().replace("  - name: evap\n", "  - name: deep\n    region: {}\n  - name: evap\n"))
        self.assertIn("differs from the config", self.assert_fail("complete_active_roster",
                                                                  *self.commands()["complete_active_roster"]))

    def test_parity_mutants(self):
        path = self.runs["off"] / "day0.600.hdf5"
        with Dataset(path, "a") as ds:
            v = ds["fields/Y/f_u3"]
            value = np.asarray(v[:])
            self.assertEqual(value[1].tobytes(), np.asarray(-0.0).tobytes())
            value[1] = 0.0
            v[:] = value
        self.assertIn("f_u3", self.assert_fail("parent_bitwise_parity", *self.commands()["parent_bitwise_parity"]))
        self.tearDown()
        self.setUp()
        (self.runs["off"] / "rhoa_150s_inst.nc").unlink()
        self.assert_fail("parent_bitwise_parity", *self.commands()["parent_bitwise_parity"])

    def test_restart_mutants(self):
        edit_nc(self.runs["restarted"] / wc.ARRAYS_FILE, "record_values",
                lambda v: v.__setitem__((0, 2), np.nextafter(v[0, 2], np.inf)))
        self.assertIn("record_values", self.assert_fail("all_channel_checkpoint_restart",
                                                        *self.commands()["all_channel_checkpoint_restart"]))
        self.tearDown()
        self.setUp()
        edit_receipt(self.runs["restarted"], lambda l: l[0].update(ledger_start="zero_at_restart"))
        self.assert_fail("all_channel_checkpoint_restart", *self.commands()["all_channel_checkpoint_restart"])
        self.tearDown()
        self.setUp()
        # A variable with time last, as the model writes hus (z, time), is compared at the last time.
        edit_nc(self.runs["restarted"] / "rhoa_150s_inst.nc", "rhoa_time_last",
                lambda v: v.__setitem__((0, -1), np.nextafter(v[0, -1], np.inf)))
        self.assertIn("rhoa_time_last", self.assert_fail("all_channel_checkpoint_restart",
                                                         *self.commands()["all_channel_checkpoint_restart"]))
        self.tearDown()
        self.setUp()
        (self.runs["restarted"] / "rhoa_150s_inst.nc").unlink()
        self.assertIn("file sets", self.assert_fail("all_channel_checkpoint_restart",
                                                    *self.commands()["all_channel_checkpoint_restart"]))


class TestProof(Fixture):
    def test_proof_opens_the_gate_dry(self):
        out, _ = self.convert()
        logs = self.root / "logs"
        logs.mkdir()
        for key, argv in TestChecks.commands(self).items():
            code, text = run_cli(*argv)
            self.assertEqual(code, 0, text)
            (logs / f"{key}.log").write_text(text)
            (logs / f"{key}.cmd").write_text("python3 water_tag_application_checks.py " + " ".join(map(str, argv)))
        source = self.root / "water_tag_applications.jl"
        source.write_text("# stand-in for the producer source, test only\n")
        proof, artifacts = wproof.build_proof(out, wc.OUT_RECEIPT, source, logs, "synthetic test")
        self.assertEqual(proof["kind"], "runtime_validation")
        self.assertEqual(set(proof["checks"]), set(wproof.GATE_CHECKS))
        manifest = out / "manifest.json"
        data = json.loads(manifest.read_text())
        self.assertEqual(data["acceptance"]["correction_accounting"]["lifecycle_evidence"], wproof.PROOF)
        self.assertTrue(all(data["acceptance"]["artifacts"][k] == v for k, v in artifacts.items()))
        bundle = Bundle(manifest)
        pid, entry = wproof.registry_entry(proof["integrator_pin"], allow_pending=True)
        ca.producer_entry(pid, entry)
        entry["source_sha256"] = sha256_file(source)
        with mock.patch.dict(ca.VERIFIED_PRODUCERS, {pid: entry}):
            result = ca.evaluate_accounting(bundle, 0, fx.STEPS * fx.DT)
            self.assertEqual(result["verdict"], "PASS", result["limitation"])
            self.assertEqual(ca.application_activity(bundle, 0, fx.STEPS * fx.DT)["verdict"], "REPORTED ONLY")
            # A failed check keeps the gate closed.
            (out / "lifecycle_logs" / "restart_failed.log").write_text("CHECK all_channel_checkpoint_restart: FAIL x\n")
            proof["checks"]["all_channel_checkpoint_restart"]["result"] = "FAIL"
            (out / wproof.PROOF).write_text(json.dumps(proof))
            data["acceptance"]["artifacts"][wproof.PROOF] = sha256_file(out / wproof.PROOF)
            manifest.write_text(json.dumps(data))
            result = ca.evaluate_accounting(Bundle(manifest), 0, fx.STEPS * fx.DT)
            self.assertIn("all_channel_checkpoint_restart", result["limitation"])
        with self.assertRaisesRegex(wproof.ProofError, "pending"):
            wproof.registry_entry(proof["integrator_pin"])


if __name__ == "__main__":
    unittest.main()
