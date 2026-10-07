"""Independent analytic and fault-injection tests; no model simulation.

    python3 -m unittest discover -s experiments/tag_closure/analysis/evidence -p test_acceptance.py -v
"""

import ast
import contextlib
import copy
import io
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from acceptance_data import (Bundle, DataError, Field, density, od2_start, retained,
                             same_bits, stitch, window)
from make_acceptance_fixture import write_fixture
from manifest import attach_acceptance, sha256_file
from score_acceptance import Scorer, main


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "water"
        self.manifest = write_fixture(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def edit_spec(self, action):
        data = json.loads(self.manifest.read_text())
        action(data["acceptance"])
        self.manifest.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")

    def array(self, key, action, role="candidate", update_hash=True):
        path = self.root / (role + ".npz")
        with np.load(path, allow_pickle=False) as archive:
            values = {k: archive[k].copy() for k in archive.files}
        changed = action(values[key])
        if changed is not None:
            values[key] = changed
        np.savez(path, **values)
        if update_hash:
            self.edit_spec(lambda s: s["artifacts"].update({path.name: sha256_file(path)}))

    def evaluate(self):
        return Scorer(Bundle(self.manifest)).run()

    def row(self, name, result=None):
        return next(r for r in (result or self.evaluate())["rows"] if r["id"] == name)

    def energy(self, family="energy_source"):
        self.root = Path(self.temp.name) / family
        self.manifest = write_fixture(self.root, family)

    def test_real_water_metrics_and_owner_blockers(self):
        result = self.evaluate()
        self.assertEqual(self.row("COMMON.EVIDENCE", result)["verdict"], "PASS")
        self.assertEqual(self.row("WATER.CLOSURE", result)["verdict"], "PASS")
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400", result)["metrics"]["reference_share"], 0.6)
        self.assertEqual(self.row("COMMON.SCOPE_APPROVAL", result)["verdict"], "NOT ASSESSABLE")
        self.assertEqual(result["scientific_qualification"], "NOT QUALIFIED")
        self.assertEqual(result["exit_code"], 3)

    def test_overlay_not_in_partition(self):
        self.array("tag_evap", lambda a: a * 1000)
        self.assertEqual(self.row("WATER.CLOSURE")["metrics"]["gross"], 0)
        self.edit_spec(lambda s: s["tags"][2].update(partition=True))
        self.assertEqual(self.row("COMMON.ROSTER")["data_status"], "DATA FAILURE")

    def test_missing_required_file(self):
        (self.root / "candidate.npz").unlink()
        self.assertEqual(self.evaluate()["exit_code"], 2)
        self.assertEqual(self.row("WATER.CLOSURE")["data_status"], "DATA FAILURE")

    def test_corrupt_npz_with_valid_checksum_writes_data_failure(self):
        path = self.root / "candidate.npz"
        path.write_bytes(b"PK\x03\x04broken zip archive")
        self.edit_spec(lambda s: s["artifacts"].update({path.name: sha256_file(path)}))
        for mode in ("validate", "score"):
            output = self.root / (mode + "-corrupt.json")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([mode, str(self.manifest), "--json", str(output)]), 2)
            result = json.loads(output.read_text())
            if mode == "validate":
                self.assertTrue(any("archive" in e for e in result["validation_errors"]))
            else:
                self.assertEqual(self.row("COMMON.EVIDENCE", result)["data_status"], "DATA FAILURE")

    def test_missing_required_variable(self):
        self.edit_spec(lambda s: s["runs"]["candidate"]["fields"].pop("led_fix_pbl_applicable"))
        self.assertEqual(self.row("WATER.LED_FIX.pbl.established")["data_status"], "DATA FAILURE")

    def test_required_parent_inventory(self):
        self.edit_spec(lambda s: s["runs"]["untagged"]["fields"].pop("temperature"))
        self.assertEqual(self.row("COMMON.PARENT_PARITY")["data_status"], "DATA FAILURE")
        self.assertNotEqual(self.row("WATER.CLOSURE")["verdict"], "PASS")

    def test_exported_temperature_is_not_full_parent_parity(self):
        self.edit_spec(lambda s: s.update(required_parent_fields=["temperature"], parent_capture_scope="exported"))
        self.assertEqual(self.row("COMMON.PARENT_PARITY")["verdict"], "NOT ASSESSABLE")

    def test_truncated_window_is_not_truncated_to_common_prefix(self):
        self.array("time", lambda a: np.where(a == 86400, 86401, a))
        self.assertEqual(self.row("WATER.CLOSURE")["data_status"], "DATA FAILURE")

    def test_shifted_and_duplicate_time(self):
        self.array("time", lambda a: a + 1)
        self.assertEqual(self.row("COMMON.PARENT_PARITY")["data_status"], "DATA FAILURE")
        self.array("time", lambda a: np.zeros_like(a))
        self.assertEqual(self.row("COMMON.EVIDENCE")["data_status"], "DATA FAILURE")

    def test_wrong_geometry_and_units(self):
        self.array("geometry", lambda a: a + 1)
        self.assertEqual(self.row("COMMON.PARENT_PARITY")["data_status"], "DATA FAILURE")
        self.array("water_parent__units", lambda a: np.array("J kg^-1"))
        self.assertEqual(self.row("COMMON.EVIDENCE")["data_status"], "DATA FAILURE")

    def test_invalid_values_and_stale_checksum(self):
        self.array("water_parent", lambda a: np.full_like(a, np.nan))
        self.assertEqual(self.evaluate()["exit_code"], 2)
        self.array("water_parent", lambda a: np.ones_like(a), update_hash=False)
        self.assertIn("checksum", " ".join(self.row("COMMON.EVIDENCE")["metrics"]["validation_errors"]))

    def test_od2_physical_and_sensitivity_windows(self):
        values = self.row("COMMON.OD2_WINDOWS")["metrics"]
        self.assertEqual(values["startup_end"], 3600)
        self.assertIn(("sensitivity_1h", 3600, 86400), values["windows"])
        # Rates 10,1,0.5,0.5,0.5: strict below 10% excludes the rate equal to 1.
        time = np.arange(7, dtype=float) * 3600
        amounts = np.array([0, 10, 11, 11.5, 12, 12.5, 13])
        self.assertEqual(od2_start(time, amounts), 7200)
        self.assertIsNone(od2_start(time, np.arange(7, dtype=float)))

    def test_no_established_window_is_not_relabelled(self):
        self.array("water_parent", lambda a: np.repeat((100 + np.arange(25))[:, None], 2, axis=1), role="untagged")
        result = self.evaluate()
        self.assertEqual(self.row("COMMON.WINDOW.established", result)["verdict"], "NOT ASSESSABLE")
        self.assertEqual(self.row("WATER.LED_FIX.pbl.established", result)["verdict"], "NOT ASSESSABLE")

    def test_signed_source_burden_and_region_positive_precondition(self):
        self.array("tag_evap", lambda a: np.tile([1.0, -1.0], (25, 1)))
        row = self.row("WATER.LED_FIX.evap.established")
        self.assertEqual(row["metrics"]["inventory"], 0)
        self.assertEqual(row["metrics"]["burden"], 2)
        self.assertEqual(row["verdict"], "PASS")
        self.array("tag_pbl", lambda a: -np.abs(a))
        self.assertEqual(self.row("WATER.LED_FIX.pbl.established")["verdict"], "NOT ASSESSABLE")

    def test_zero_inventory_not_inferred_from_zero_correction(self):
        self.array("tag_evap", lambda a: np.zeros_like(a))
        row = self.row("WATER.LED_FIX.evap.established")
        self.assertEqual(row["verdict"], "NOT APPLICABLE")
        self.assertEqual(row["metrics"]["burden_fraction"], None)
        self.edit_spec(lambda s: s["runs"]["candidate"]["fields"].pop("tag_evap"))
        self.assertEqual(self.row("WATER.LED_FIX.evap.established")["data_status"], "DATA FAILURE")

    def test_small_tag_absolute_rule_replaces_both_ratios(self):
        self.array("tag_evap", lambda a: np.zeros_like(a), role="reference")
        self.array("tag_evap", lambda a: np.ones_like(a) * 0.001)
        row = self.row("WATER.ORIGINS.evap.86400")
        self.assertEqual(row["verdict"], "PASS")
        self.assertIsNone(row["metrics"]["L1"])
        self.assertAlmostEqual(row["metrics"]["absolute_L1"], 0.002)
        self.assertAlmostEqual(row["metrics"]["small_absolute_limit"], 223 * 2e-4)
        self.array("tag_evap", lambda a: np.ones_like(a))
        self.assertEqual(self.row("WATER.ORIGINS.evap.86400")["verdict"], "FAIL")

    def test_ineligible_reference_blocks_origins_despite_exact_agreement(self):
        p = self.root / "reference_evidence.json"
        detail = json.loads(p.read_text())
        detail["repair_refinement_ratios"]["dt"] = 2
        p.write_text(json.dumps(detail))
        self.edit_spec(lambda s: s["artifacts"].update({p.name: sha256_file(p)}))
        row = self.row("WATER.ORIGINS.pbl.86400")
        self.assertEqual(row["metrics"]["L1"], 0)
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")

    def test_constant_energy_residual_preserves_growth_pass_and_reports_state(self):
        self.energy()
        row = self.row("ENERGY.CLOSURE_GROWTH.established")
        self.assertEqual(row["verdict"], "PASS")
        self.assertEqual(row["metrics"]["delta_gross"], 0)
        self.assertEqual(row["metrics"]["gross_end"], 200)
        self.assertAlmostEqual(row["metrics"]["end_state_ratio"], 200 / 230)
        self.assertNotEqual(self.row("ENERGY_SOURCE.AGGREGATE_REPAIR.established")["verdict"], "PASS")

    def test_integrated_scalar_amount_cannot_receive_thickness_weights(self):
        self.energy()
        self.assertEqual(Scorer(Bundle(self.manifest)).exact_scale(0, 86400), 240)
        data = json.loads(self.manifest.read_text())
        for role in ("candidate", "reference"):
            field = data["acceptance"]["runs"][role]["fields"]["throughput"]
            field.update(weight_units="m", dimensions=["z"], weights_key="throughput_weights",
                         weight_units_key="throughput_weight_units")
            path = self.root / (role + ".npz")
            with np.load(path, allow_pickle=False) as archive:
                arrays = {k: archive[k].copy() for k in archive.files}
            arrays.update(throughput_weights=np.array([100.0]), throughput_weight_units=np.array("m"))
            arrays["throughput__dimensions"] = np.array(["z"])
            np.savez(path, **arrays)
            data["acceptance"]["artifacts"][path.name] = sha256_file(path)
        self.manifest.write_text(json.dumps(data))
        row = self.row("ENERGY.CLOSURE_GROWTH.established")
        self.assertEqual(row["data_status"], "DATA FAILURE")
        self.assertIn("double weight", row["limitation"])

    def test_scalar_representation_requires_unit_weights(self):
        self.array("scalar_weights", lambda a: a * 2)
        self.assertEqual(self.row("COMMON.EVIDENCE")["data_status"], "DATA FAILURE")

    def test_duplicate_process_rosters_are_data_failures(self):
        self.energy()
        baseline = self.row("ENERGY.CORRECTED_RECORD_ESTIMATE.startup")
        self.assertEqual(baseline["metrics"]["density_reconstructed_record_variation"], 2)
        for candidate, expected in ((["radiation", "radiation"], ["radiation"]),
                                    (["radiation"], ["radiation", "radiation"])):
            self.edit_spec(lambda s: s.update(record_processes=candidate, expected_record_processes=expected))
            self.assertEqual(self.row("ENERGY.CORRECTED_RECORD_ESTIMATE.startup")["data_status"], "DATA FAILURE")

    def test_empty_profile_times_keep_required_origins(self):
        self.edit_spec(lambda s: s.update(profile_times=[]))
        result = self.evaluate()
        for endpoint in (3600, 86400):
            self.assertEqual(self.row("WATER.ORIGINS.pbl." + str(endpoint), result)["verdict"], "PASS")

    def test_proposed_decision_cannot_be_overridden_by_result_pass(self):
        scorer = Scorer(Bundle(self.manifest))
        row = scorer.row("proposed", lambda: {"verdict": "PASS", "meets": True}, decision="proposed")
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")

    def test_failed_parent_parity_blocks_dependent_measured_rows(self):
        for family in ("water", "energy_source"):
            if family == "energy_source":
                self.energy()
            self.array("temperature", lambda a: a + 1, role="untagged")
            result = self.evaluate()
            self.assertEqual(self.row("COMMON.PARENT_PARITY", result)["verdict"], "FAIL")
            ids = [family.upper() + ".LED_FIX.pbl.established",
                   family.upper() + ".PROCESS_WEIGHTED.established",
                   family.upper() + ".ORIGINS.pbl.86400"]
            if family == "energy_source":
                ids.append("ENERGY.CLOSURE_GROWTH.established")
            for name in ids:
                self.assertEqual(self.row(name, result)["verdict"], "NOT ASSESSABLE")

    def test_process_error_absolute_value_is_inside_weighted_sum(self):
        self.array("process_share", lambda a: np.where(np.arange(25)[:, None] % 2, 0.7, 0.5))
        row = self.row("WATER.PROCESS_WEIGHTED.established")
        self.assertAlmostEqual(row["metrics"]["weighted_error"], 0.1)
        self.assertEqual(row["verdict"], "FAIL")
        self.array("process_amount", lambda a: np.zeros_like(a))
        row = self.row("WATER.PROCESS_WEIGHTED.established")
        self.assertEqual(row["verdict"], "NOT APPLICABLE")
        self.assertIsNone(row["metrics"]["weighted_error"])

    def test_newton_cross_parent_gate_and_same_parent_reporting(self):
        self.array("newton_error", lambda a: np.ones_like(a) * 0.01)
        self.assertEqual(self.row("COMMON.NEWTON_TRIAL")["verdict"], "REPORTED ONLY")
        self.edit_spec(lambda s: s.update(same_parent_comparisons=False))
        self.assertEqual(self.row("COMMON.NEWTON_TRIAL")["verdict"], "FAIL")
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400")["verdict"], "NOT ASSESSABLE")

    def test_water_uses_raw_scale_and_preserves_total_residual_vs_part_gross(self):
        # Direct compartment construction isolates normalization from parity gates.
        self.edit_spec(lambda s: s.update(compartments=["N", "R", "S"]))
        data = json.loads(self.manifest.read_text())
        fields = data["acceptance"]["runs"]["candidate"]["fields"]
        source = self.root / "candidate.npz"
        with np.load(source, allow_pickle=False) as archive:
            arrays = {k: archive[k].copy() for k in archive.files}
        for c, parent in (("N", 10.0), ("R", -1.0), ("S", 1.0)):
            for name, amount in (("parent_" + c, parent),
                                 ("tag_" + c + "_pbl", max(parent, 0) * 0.6),
                                 ("tag_" + c + "_free", max(parent, 0) * 0.4)):
                fields[name] = copy.deepcopy(fields["water_parent"])
                fields[name]["key"] = name
                arrays[name] = np.ones((25, 2)) * amount
                for attr in ("units", "sampling", "representation", "dimensions"):
                    arrays[name + "__" + attr] = arrays["water_parent__" + attr].copy()
        # Total raw density is 10; sum of compartment positive targets is 11.
        arrays["water_parent"][:] = 10
        arrays["tag_N_pbl"] -= 0.1
        arrays["tag_S_pbl"] += 0.1
        np.savez(source, **arrays)
        data["acceptance"]["artifacts"][source.name] = sha256_file(source)
        self.manifest.write_text(json.dumps(data))
        _, state = Scorer(Bundle(self.manifest)).water_state()
        self.assertEqual(state["raw"][-1], 20)
        self.assertEqual(state["target"][-1], 22)
        self.assertAlmostEqual(state["gross"][-1], 0)
        self.assertAlmostEqual(sum(v[-1] for v in state["part_gross"].values()), 0.4)

    def test_paired_interval_precipitation_keeps_signed_contributions(self):
        data = json.loads(self.manifest.read_text())
        spec = data["acceptance"]
        fields = spec["runs"]["candidate"]["fields"]
        path = self.root / "precip.csv"
        path.write_text("time,a,b,parent,pbl,free\n0,0,3600,-2,-1,-1\n3600,3600,7200,1,0.6,0.4\n")
        spec["artifacts"][path.name] = sha256_file(path)
        for name, key in (("precip_parent", "parent"), ("precip_pbl", "pbl"), ("precip_free", "free")):
            fields[name] = {"path": path.name, "key": key, "units": "kg m^-2 s^-1",
                            "sampling": "interval_average", "representation": "rate",
                            "weight_units": "1", "dimensions": ["scalar"],
                            "bounds_columns": ["a", "b"], "metadata_source": "fixture_metadata.json"}
        spec["precipitation_applied_flux_average"] = True
        self.manifest.write_text(json.dumps(data))
        result = Scorer(Bundle(self.manifest)).precipitation(0, 7200)["metrics"]
        self.assertEqual(result["signed_downward_amount"], 3600)
        self.assertEqual(result["positive_amount"], 7200)
        self.assertEqual(result["negative_amount"], -3600)
        self.assertEqual(result["absolute_defect"], 0)

    def test_energy_positive_stored_reference_and_specific_peak(self):
        self.energy()
        self.array("tag_evap", lambda a: -np.abs(a), role="reference")
        self.assertEqual(self.row("ENERGY_SOURCE.ORIGINS.evap.86400")["verdict"], "NOT ASSESSABLE")
        self.array("tag_evap", lambda a: np.zeros_like(a), role="reference")
        self.array("tag_evap", lambda a: np.ones_like(a) * 0.001)
        row = self.row("ENERGY_SOURCE.ORIGINS.evap.86400")
        self.assertEqual(row["verdict"], "PASS")
        self.assertAlmostEqual(row["metrics"]["small_absolute_limit"], 230 * 2e-4)

    def test_density_export_profile_requires_aligned_positive_physical_rho(self):
        bundle = Bundle(self.manifest)
        for role in ("candidate", "reference"):
            tag = bundle.field(role, "tag_pbl")
            tag.representation, tag.units = "density", "kg m^-3"
            tag.values[:] = [100, 1]
            rho = bundle.field(role, "rho")
            rho.values[:] = [1, 100]
            rho.geometry = rho.geometry[::-1].copy()
        parent = bundle.field("reference", "water_parent")
        parent.representation, parent.units = "density", "kg m^-3"
        parent.values[:] = [200, 2]
        bundle.field("candidate", "tag_pbl").values[:, 1] = 1.2
        scorer = Scorer(bundle)
        tag = {"name": "pbl", "kind": "region"}
        with self.assertRaisesRegex(DataError, "geometry/dtypes differ"):
            scorer.profile(tag, 86400)
        # Attach each density to its actual native cell. The second cell's
        # specific-field difference is 0.2 against a reference peak of 1.
        for role in ("candidate", "reference"):
            rho = bundle.field(role, "rho")
            rho.geometry = rho.geometry[::-1].copy()
            rho.values[:] = [100, 1]
        result = scorer.profile(tag, 86400)
        self.assertAlmostEqual(result["metrics"]["Linf"], 0.2)
        self.assertFalse(result["meets"])
        for invalid in (0, -1, np.nan):
            bundle.field("candidate", "rho").values[:, 0] = invalid
            with self.assertRaises(DataError):
                scorer.profile(tag, 86400)
        bundle.field("candidate", "rho").values[:] = [100, 1]
        bundle.field("candidate", "rho").representation = "specific"
        with self.assertRaisesRegex(DataError, "rho must be a density"):
            scorer.profile(tag, 86400)

    def test_missing_reference_is_scientific_blocker_and_unknown_inventory_is_data_failure(self):
        self.edit_spec(lambda s: s.pop("reference"))
        row = self.row("REFERENCE.ELIGIBILITY.established")
        self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "COMPLETE"))

    def test_reference_parent_difference_blocks_equal_tags(self):
        self.array("temperature", lambda a: a + 2, role="reference")
        row = self.row("WATER.ORIGINS.pbl.86400")
        self.assertEqual(row["metrics"]["L1"], 0)
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")
        self.assertEqual(self.row("REFERENCE.PARENT_PARITY")["verdict"], "FAIL")

    def test_unrelated_or_incomplete_independent_rules_cannot_validate_origins(self):
        p = self.root / "reference_evidence.json"
        detail = json.loads(p.read_text())
        for rules in (["unrelated"], ["transport"]):
            detail["independent_rules"] = rules
            detail["active_rules"] = ["transport", "sink"]
            p.write_text(json.dumps(detail))
            self.edit_spec(lambda s: (s.update(active_rules=["transport", "sink"]),
                                     s["artifacts"].update({p.name: sha256_file(p)})))
            self.assertEqual(self.row("WATER.ORIGINS.pbl.86400")["verdict"], "NOT ASSESSABLE")
            self.assertEqual(self.row("REFERENCE.ACTIVE_RULE_COVERAGE")["verdict"], "NOT ASSESSABLE")

    def test_native_precipitation_requires_column_scalar_convention(self):
        self.edit_spec(lambda s: s.update(geometry_kind="sphere"))
        self.assertEqual(self.row("WATER.PRECIP_INSTANTANEOUS")["data_status"], "DATA FAILURE")

    def test_provenance_scientific_sufficiency_not_implied_by_hash(self):
        self.edit_spec(lambda s: s["resolved_settings"].pop("seed"))
        self.assertEqual(self.row("COMMON.EVIDENCE")["data_status"], "DATA FAILURE")
        self.assertEqual(self.evaluate()["exit_code"], 2)

    def test_concurrent_artifact_change_is_caught_at_completion(self):
        bundle = Bundle(self.manifest)
        bundle.field("candidate", "rho")
        (self.root / "candidate.npz").write_bytes(b"changed after first read")
        with self.assertRaisesRegex(DataError, "changed during"):
            bundle.reverify()

    def test_zero_throughput_and_missing_active_process_are_not_zero_passes(self):
        self.energy()
        self.array("throughput", lambda a: np.zeros_like(a))
        row = self.row("ENERGY.CLOSURE_GROWTH.established")
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")
        self.assertEqual(row["metrics"]["theta_x"], 0)
        self.edit_spec(lambda s: s.update(expected_record_processes=["radiation", "surface_flux"]))
        self.assertEqual(self.row("ENERGY.CORRECTED_RECORD_ESTIMATE.established")["data_status"], "DATA FAILURE")

    def test_changing_density_record_difference_is_endpoint_reconstructed(self):
        time = np.array([0.0, 1.0, 2.0])
        f = Field(time, np.array([[2.0], [2.0], [3.0]]), np.ones(1), np.zeros((1, 1)),
                  "J kg^-1", "specific", "cumulative", "m", ("z",), ())
        rho = Field(time, np.array([[1.0], [3.0], [2.0]]), np.ones(1), np.zeros((1, 1)),
                    "kg m^-3", "density", "instantaneous", "m", ("z",), ())
        amount = density(f, rho)
        np.testing.assert_array_equal(amount[:, 0], [2, 6, 6])
        # Accepted increments are +4, 0; the old end-density formula would give 0,+2.
        activity, signed = retained(f, rho, 0, 2, 1)
        self.assertEqual((activity, signed), (4, 4))
        f.representation = "density"
        np.testing.assert_array_equal(density(f, rho)[:, 0], [2, 2, 3])

    def test_cancelled_signed_ledger_does_not_prove_zero_gross_activity(self):
        time = np.array([0.0, 1.0, 2.0])
        f = Field(time, np.array([[0.0], [3.0], [0.0]]), np.ones(1), np.zeros((1, 1)),
                  "J m^-3", "density", "cumulative", "m", ("z",), ())
        rho = copy.copy(f)
        rho.values = np.ones_like(f.values)
        rho.units, rho.sampling = "kg m^-3", "instantaneous"
        activity, signed = retained(f, rho, 0, 2, 1)
        self.assertEqual(activity, 6)
        self.assertEqual(signed, 0)
        # Opposite within-step applications can leave every endpoint zero.
        f.values[:] = 0
        self.assertEqual(retained(f, rho, 0, 2, 1)[0], 0)
        self.assertEqual(self.row("COMMON.ACCEPTED_APPLICATION_ACTIVITY")["verdict"], "NOT ASSESSABLE")

    def test_no_rain_spurious_rate_is_reported_absolutely(self):
        self.array("precip_parent", lambda a: np.zeros_like(a))
        row = self.row("WATER.PRECIP_INSTANTANEOUS")
        self.assertAlmostEqual(row["metrics"]["no_rain_absolute_defect"], 0.001)
        self.assertEqual(row["verdict"], "REPORTED ONLY")

    def test_hourly_snapshots_cannot_be_integrated(self):
        row = self.row("WATER.PRECIP_INTEGRATED.established")
        self.assertEqual(row["data_status"], "DATA FAILURE")
        self.assertNotEqual(row["verdict"], "PASS")

    def test_signed_zero_and_nan_parity_conventions(self):
        self.assertFalse(same_bits(np.array([0.0]), np.array([-0.0])))
        self.assertFalse(same_bits(np.array([1], dtype=np.float32), np.array([1], dtype=np.float64)))
        self.assertTrue(same_bits(np.array([np.nan]), np.array([np.nan])))
        self.array("newton_error", lambda a: a * 0)
        self.array("newton_error", lambda a: -np.zeros_like(a), role="untagged")
        self.edit_spec(lambda s: s["required_parent_fields"].append("newton_error"))
        self.assertEqual(self.row("COMMON.PARENT_PARITY")["verdict"], "FAIL")
        self.assertNotEqual(self.row("WATER.CLOSURE")["verdict"], "PASS")

    def test_restart_reader_continuation_reset_and_boundary_faults(self):
        def f(time, value):
            return Field(np.array(time, dtype=float), np.array(value, dtype=float)[:, None],
                         np.ones(1), np.zeros((1, 1)), "J", "amount", "cumulative", "1", ("scalar",), ())
        first, second = f([0, 1, 2], [0, 2, 5]), f([2, 3, 4], [5, 8, 9])
        segments = [{"id": "a", "parent_id": None, "output_checkpoint": "checksum-a",
                     "accumulators": {"gross": {"mode": "continued"}}},
                    {"id": "b", "parent_id": "a", "input_checkpoint": "checksum-a",
                     "accumulators": {"gross": {"mode": "continued"}}}]
        result = stitch([first, second], segments, "gross")
        np.testing.assert_array_equal(result.time, [0, 1, 2, 3, 4])
        np.testing.assert_array_equal(result.values[:, 0], [0, 2, 5, 8, 9])
        second.values -= 5
        segments[1]["accumulators"]["gross"] = {"mode": "reset", "offset": [5]}
        np.testing.assert_array_equal(stitch([first, second], segments, "gross").values, result.values)
        segments[1]["input_checkpoint"] = "wrong"
        with self.assertRaisesRegex(DataError, "checkpoint"):
            stitch([first, second], segments, "gross")
        segments[1]["input_checkpoint"] = "checksum-a"
        second.values[0] = 1
        with self.assertRaisesRegex(DataError, "boundary changed"):
            stitch([first, second], segments, "gross")
        segments[1].pop("accumulators")
        with self.assertRaisesRegex(DataError, "continuation metadata"):
            stitch([first, second], segments, "gross")

    def test_radiation_reference_never_transplants_source_thresholds(self):
        self.energy("radiation_record")
        result = self.evaluate()
        row = self.row("RADIATION.INDEPENDENT_FLUX_REFERENCE.established", result)
        self.assertEqual(row["metrics"]["column_difference"], 0)
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")
        self.assertFalse(any("LED_FIX" in r["id"] or "ELIGIBILITY" in r["id"] or
                             "CLOSURE_GROWTH" in r["id"] for r in result["rows"]))

    def test_legacy_manifest_is_explicitly_incomplete(self):
        legacy = self.root / "submission.json"
        errors = Bundle(legacy).validate()
        self.assertTrue(any("legacy" in e for e in errors))

    def test_attachment_preserves_original_and_rejects_overwrites(self):
        p = self.root / "submission.json"
        before = p.read_bytes()
        output = self.root / "attached.json"
        attach_acceptance(p, self.root / "extension.json", output)
        self.assertEqual(p.read_bytes(), before)
        old = json.loads(before)
        new = json.loads(output.read_text())
        new.pop("acceptance")
        self.assertEqual(new, old)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            attach_acceptance(p, self.root / "extension.json", output)

    def test_fresh_float32_floor_preserves_W60(self):
        p = self.root / "precision.json"
        d = {"fresh_preregistered": True, "historical_id": "fresh", "accepted_steps": 720,
             "Float32": 9e-6, "Float64": 1e-13}
        p.write_text(json.dumps(d))
        self.edit_spec(lambda s: (s.update(float32_evidence=p.name), s["artifacts"].update({p.name: sha256_file(p)})))
        self.assertEqual(self.row("COMMON.FLOAT32")["verdict"], "PASS")
        self.assertAlmostEqual(self.row("COMMON.FLOAT32")["metrics"]["approved_rounding_limit"],
                               3 * 2 ** -23 * np.sqrt(720))
        d["historical_id"] = "W60"
        p.write_text(json.dumps(d))
        self.edit_spec(lambda s: s["artifacts"].update({p.name: sha256_file(p)}))
        self.assertEqual(self.row("COMMON.FLOAT32")["data_status"], "DATA FAILURE")

    def test_deterministic_results_and_cli_no_overwrite(self):
        first = self.evaluate()
        self.assertEqual(first, self.evaluate())
        output = self.root / "evaluation-new.json"
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["score", str(self.manifest), "--json", str(output)]), 3)
        self.assertEqual(json.loads(output.read_text()), json.loads(json.dumps(first)))
        with self.assertRaisesRegex(DataError, "exists"):
            main(["score", str(self.manifest), "--json", str(output)])

    def test_endpoint_formula_compatibility_with_existing_WP0(self):
        # Compile only the old pure metric function; the optional NetCDF environment
        # is unnecessary to independently compare its numerical behavior.
        source = Path(__file__).with_name("compare_runs.py").read_text()
        node = next(n for n in ast.parse(source).body if isinstance(n, ast.FunctionDef) and n.name == "tag_row_metrics")
        namespace = {"np": np}
        exec(compile(ast.Module(body=[node], type_ignores=[]), "WP0 metric", "exec"), namespace)
        actual, ref, w = np.array([1.0, 2.0]), np.array([2.0, 4.0]), np.array([3.0, 5.0])
        metric = namespace["tag_row_metrics"]("pbl", 24, ref, actual, w)
        self.assertEqual(metric["abs_L1"], 13)
        self.assertEqual(metric["L1_mass_weighted"], 0.5)
        self.assertEqual(metric["Linf_peak_normalized"], 0.5)


if __name__ == "__main__":
    unittest.main()
