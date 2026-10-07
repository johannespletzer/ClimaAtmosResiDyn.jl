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
from unittest import mock

import numpy as np

from acceptance_data import (Bundle, DataError, Field, density, od2_start, retained,
                             same_bits, stitch, window)
from make_acceptance_fixture import write_fixture
from manifest import attach_acceptance, sha256_file
import score_acceptance as sa
from closure_verdict import ENERGY_GROSS, WATER_GROSS
from score_acceptance import Scorer, float32_limit, main, origin_limits


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
        row = self.row("WATER.LED_FIX.pbl.established")
        self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "COMPLETE"))

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

    def set_rules(self, rules, active):
        p = self.root / "reference_evidence.json"
        detail = json.loads(p.read_text())
        detail.update(independent_rules=rules, active_rules=active)
        p.write_text(json.dumps(detail))
        self.edit_spec(lambda s: (s.update(active_rules=active), s["artifacts"].update({p.name: sha256_file(p)})))

    def test_unrelated_or_incomplete_independent_rules_cannot_validate_origins(self):
        # No independent active rule: the reference is ineligible (OD12).
        self.set_rules(["unrelated"], ["transport", "sink"])
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400")["verdict"], "NOT ASSESSABLE")
        # Partial coverage: water reports it and does not gate (WA-GATES (b)).
        self.set_rules(["transport"], ["transport", "sink"])
        result = self.evaluate()
        coverage = self.row("REFERENCE.ACTIVE_RULE_COVERAGE", result)
        self.assertEqual((coverage["verdict"], coverage["required"]), ("REPORTED ONLY", False))
        self.assertEqual(coverage["metrics"]["untested_or_shared_rules"], ["sink"])
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400", result)["verdict"], "PASS")

    def test_energy_keeps_active_rule_coverage_as_origin_gate(self):
        self.energy()
        self.set_rules(["transport"], ["transport", "sink"])
        result = self.evaluate()
        self.assertEqual(self.row("REFERENCE.ACTIVE_RULE_COVERAGE", result)["verdict"], "NOT ASSESSABLE")
        self.assertEqual(self.row("ENERGY_SOURCE.ORIGINS.pbl.86400", result)["verdict"], "NOT ASSESSABLE")

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
        # A reported row is not assessable until Parts 4/5 supply the accumulation (G3_PLAN 6.1.2).
        self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "DATA FAILURE"))

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
        # EA-USE: an unqualified diagnostic, reported, with no accuracy, cost or scope row.
        self.assertEqual((row["verdict"], row["required"]), ("REPORTED ONLY", False))
        for name in ("COMMON.COST", "COMMON.SCOPE_APPROVAL", "COMMON.HELD_OUT"):
            self.assertEqual(self.row(name, result)["verdict"], "NOT APPLICABLE")
        self.assertEqual(self.row("COMMON.RESTART_PHYSICAL", result)["verdict"], "NOT ASSESSABLE")
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
        before = output.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(main(["score", str(self.manifest), "--json", str(output)]), 4)
        self.assertIn("exists", err.getvalue())
        self.assertEqual(output.read_bytes(), before)

    # The approved numbers (G3_PLAN 6.1, ROADMAP's OD3 table, criterion 9's rule).
    def test_approved_water_gross_2e_3(self):
        self.assertEqual(WATER_GROSS, 2e-3)

    def test_approved_energy_gross_2e_3(self):
        self.assertEqual(ENERGY_GROSS, 2e-3)

    def test_approved_origin_24h_l1_2pct_linf_5pct(self):
        for kind in ("region", "source"):
            self.assertEqual(origin_limits(kind, 86400), (0.02, 0.05))

    def test_approved_origin_first_hour_region_1pct_source_10pct_linf_25pct(self):
        self.assertEqual(origin_limits("region", 3600), (0.01, 0.25))
        self.assertEqual(origin_limits("source", 3600), (0.10, 0.25))
        with self.assertRaises(DataError):
            origin_limits("region", 21600)

    def test_approved_small_tag_share_1pct_absolute_2e_4(self):
        self.assertEqual((sa.SMALL_SHARE, sa.SMALL), (0.01, 2e-4))

    def test_approved_led_fix_2pct(self):
        self.assertEqual(sa.LED_FIX_MAX, 0.02)

    def test_approved_aggregate_repair_0_5pct_comparator_repair_0_2pct_per_day(self):
        self.assertEqual((sa.AGGREGATE_REPAIR_PER_DAY, sa.COMPARATOR_REPAIR_PER_DAY), (0.005, 0.002))

    def test_approved_copies_residual_2e_4_refinement_1_1_floor_quarter(self):
        self.assertEqual((sa.COPIES_RESIDUAL_MAX, sa.COMPARATOR_REFINEMENT_MAX, sa.FLOOR_FRACTION_MAX),
                         (2e-4, 1.1, 0.25))

    def test_approved_named_remainder_1e_6_negative_water_1e_4_newton_1e_3(self):
        self.assertEqual((sa.NAMED_REMAINDER_MAX, sa.NEGATIVE_WATER_MAX, sa.NEWTON_MAX), (1e-6, 1e-4, 1e-3))

    def test_approved_temperature_150K_floor_5K_top_change(self):
        self.assertEqual((sa.TEMPERATURE_FLOOR_K, sa.TOP_CHANGE_K), (150, 5))

    def test_approved_process_weighted_5pct(self):
        self.assertEqual(sa.PROCESS_WEIGHTED_MAX, 0.05)

    def test_approved_float32_rule_10x_float64_or_3_eps32_sqrt_n(self):
        self.assertEqual(float32_limit(1e-6, 720), 10 * 1e-6)
        self.assertEqual(float32_limit(0.0, 720), 3 * 2 ** -23 * np.sqrt(720))

    # Verdict logic that the constants alone do not pin.
    def test_water_closure_gross_limit(self):
        for c, verdict in ((1.9e-3, "PASS"), (2.1e-3, "FAIL")):
            self.manifest = write_fixture(self.root.with_name("closure" + verdict))
            self.root = self.manifest.parent
            # The residual grows to c of the water by 12 h and then stays, so G(24) = c
            # and the second 12 h add nothing.
            growth = np.minimum(np.arange(25) / 12, 1)[:, None]
            self.array("tag_pbl", lambda a: a * (0.6 - c * growth) / 0.6)
            row = self.row("WATER.CLOSURE")
            self.assertAlmostEqual(row["metrics"]["gross_over_raw"], c)
            self.assertEqual(row["verdict"], verdict)

    def test_water_closure_second_twelve_hours_add_no_more_than_the_first(self):
        # A residual of 1e-3 appears only at 24 h: within 0.2%, but all of it in the second half.
        self.array("tag_pbl", lambda a: np.where(np.arange(len(a))[:, None] == 24, a * (0.6 - 1e-3) / 0.6, a))
        row = self.row("WATER.CLOSURE")
        self.assertAlmostEqual(row["metrics"]["gross_over_raw"], 1e-3)
        self.assertAlmostEqual(row["metrics"]["second_normalized_growth"], 1e-3)
        self.assertEqual(row["verdict"], "FAIL")

    def test_water_closure_normalizes_by_raw_untagged_water(self):
        bundle = Bundle(self.manifest)
        for role in ("candidate", "untagged"):
            bundle.field(role, "water_parent").values[:, 1] = -10.0
        metrics = Scorer(bundle).water_closure()["metrics"]
        self.assertNotEqual(metrics["raw_parent"], metrics["positive_target"])
        self.assertEqual(metrics["gross_over_raw"], metrics["gross"] / metrics["raw_parent"])

    def test_energy_growth_limit_on_theta_x(self):
        self.energy()
        for step, verdict in ((0.005, "PASS"), (0.015, "FAIL")):
            self.array("residual", lambda a: 100 + step * np.arange(len(a))[:, None] * np.ones_like(a))
            row = self.row("ENERGY.CLOSURE_GROWTH.established")
            # ΔG = 2 cells × 23 steps × step, Θx(1 h, 24 h) = 230.
            self.assertAlmostEqual(row["metrics"]["growth_ratio"], step / 5)
            self.assertEqual(row["verdict"], verdict)

    def test_small_tag_share_cutoff_and_absolute_limit(self):
        # evap holds 10/223, about 4.5%, of the water at 24 h. Its relative errors are judged.
        self.array("tag_evap", lambda a: a * 1.015)
        row = self.row("WATER.ORIGINS.evap.86400")
        self.assertAlmostEqual(row["metrics"]["L1"], 0.015)
        self.assertNotIn("small_absolute_limit", row["metrics"])
        self.assertEqual(row["verdict"], "PASS")
        # A zero reference is small. 0.2 lies between 2e-4 × 223 and ten times that.
        self.array("tag_evap", lambda a: np.zeros_like(a), role="reference")
        self.array("tag_evap", lambda a: np.full_like(a, 0.1))
        row = self.row("WATER.ORIGINS.evap.86400")
        self.assertAlmostEqual(row["metrics"]["absolute_L1"], 0.2)
        self.assertEqual(row["verdict"], "FAIL")

    def test_six_hour_origins_are_reported_not_judged(self):
        self.edit_spec(lambda s: s.update(profile_times=[3600, 21600, 86400]))
        row = self.row("WATER.ORIGINS.pbl.21600")
        self.assertEqual(row["verdict"], "REPORTED ONLY")
        self.assertIsNone(row["threshold"]["L1"])

    def test_linf_uses_specific_fields_and_l1_the_reference_density(self):
        bundle = Bundle(self.manifest)
        for role in ("candidate", "reference"):
            tag = bundle.field(role, "tag_pbl")
            tag.representation, tag.units = "density", "kg m^-3"
            tag.values[:] = [100, 1]
            bundle.field(role, "rho").values[:] = [100, 1]
        bundle.field("candidate", "tag_pbl").values[:, 0] = 100.5
        scorer, tag = Scorer(bundle), {"name": "pbl", "kind": "region"}
        metrics = scorer.profile(tag, 86400)["metrics"]
        # Specific error 0.005 in the dense cell, against a specific peak of 1.
        self.assertAlmostEqual(metrics["Linf"], 0.005)
        self.assertAlmostEqual(metrics["absolute_L1"], 0.5)
        # The candidate's own density differs. A_i still weights by the reference density.
        bundle.field("candidate", "rho").values[:] = [200, 2]
        bundle.field("candidate", "tag_pbl").values[:] = [201, 2]
        metrics = scorer.profile(tag, 86400)["metrics"]
        self.assertAlmostEqual(metrics["absolute_L1"], 0.5)

    def test_aggregate_repair_uses_endpoint_parent_and_daily_rate(self):
        row = self.row("WATER.AGGREGATE_REPAIR.established")
        metrics = row["metrics"]
        self.assertEqual(metrics["endpoint_scale"], 223)
        self.assertAlmostEqual(metrics["daily_rate"], 0.023 / 223 * 86400 / 82800)
        self.assertEqual(row["verdict"], "PASS")
        self.array("repair_retained", lambda a: a * 0.006 / metrics["daily_rate"])
        self.assertEqual(self.row("WATER.AGGREGATE_REPAIR.established")["verdict"], "FAIL")

    def test_top_level_temperature_change_and_floor(self):
        ramp = np.linspace(0, 6, 25)[:, None]
        self.array("temperature", lambda a: 300 + ramp * [0, 1])
        row = self.row("COMMON.PARENT_TEMPERATURE")
        self.assertAlmostEqual(row["metrics"]["top_change_K"], 6)
        self.assertEqual(row["verdict"], "FAIL")
        self.array("temperature", lambda a: 300 + ramp * [1, 0])
        self.assertEqual(self.row("COMMON.PARENT_TEMPERATURE")["verdict"], "PASS")
        self.array("temperature", lambda a: np.where(np.arange(25)[:, None] == 3, 149.0, 300.0) * np.ones_like(a))
        self.assertEqual(self.row("COMMON.PARENT_TEMPERATURE")["verdict"], "FAIL")
        self.array("geometry", lambda a: a[::-1].copy())
        self.assertEqual(self.row("COMMON.PARENT_TEMPERATURE")["data_status"], "DATA FAILURE")

    def test_float32_rule_uses_ten_times_float64(self):
        p = self.root / "precision.json"
        for measure, verdict in ((9e-6, "PASS"), (2e-5, "FAIL")):
            p.write_text(json.dumps({"fresh_preregistered": True, "historical_id": "fresh", "accepted_steps": 720,
                                     "Float32": measure, "Float64": 1e-6}))
            self.edit_spec(lambda s: (s.update(float32_evidence=p.name), s["artifacts"].update({p.name: sha256_file(p)})))
            self.assertEqual(self.row("COMMON.FLOAT32")["verdict"], verdict)

    def reference_detail(self, **changes):
        p = self.root / "reference_evidence.json"
        detail = json.loads(p.read_text())
        detail.update(changes)
        p.write_text(json.dumps(detail))
        self.edit_spec(lambda s: s["artifacts"].update({p.name: sha256_file(p)}))

    def test_reference_floor_above_a_quarter_is_ineligible(self):
        self.reference_detail(floor_fraction_of_tolerance=0.3)
        self.assertEqual(self.row("REFERENCE.ELIGIBILITY.established")["verdict"], "FAIL")

    def test_copies_residual_limit(self):
        with np.load(self.root / "reference.npz", allow_pickle=False) as archive:
            water = archive["water_parent"].copy()
        for fraction, verdict in ((1e-4, "PASS"), (3e-4, "FAIL")):
            self.array("copy_residual", lambda a: fraction * water, role="reference")
            row = self.row("REFERENCE.ELIGIBILITY.established")
            self.assertAlmostEqual(row["metrics"]["copies_residual"], fraction)
            self.assertEqual(row["verdict"], verdict)

    def test_cumulative_precipitation_is_signed_downward(self):
        data = json.loads(self.manifest.read_text())
        spec = data["acceptance"]
        path = self.root / "precip_cumulative.csv"
        # `pr` is upward-positive, so the accumulated falling amount is negative.
        path.write_text("time,parent,pbl,free\n0,0,0,0\n3600,-1,-0.6,-0.4\n7200,-3,-1.8,-1.2\n")
        spec["artifacts"][path.name] = sha256_file(path)
        for name, key in (("precip_parent", "parent"), ("precip_pbl", "pbl"), ("precip_free", "free")):
            spec["runs"]["candidate"]["fields"][name] = {
                "path": path.name, "key": key, "units": "kg m^-2", "sampling": "cumulative",
                "representation": "amount", "weight_units": "1", "dimensions": ["scalar"], "cadence": 3600,
                "accumulator_kind": "accepted_applied_precipitation", "metadata_source": "fixture_metadata.json"}
        self.manifest.write_text(json.dumps(data))
        metrics = Scorer(Bundle(self.manifest)).precipitation(0, 7200)["metrics"]
        self.assertEqual(metrics["signed_downward_amount"], 3)
        self.assertEqual(metrics["absolute_defect"], 0)

    @staticmethod
    def amounts(rates):
        return np.concatenate(([0.0], np.cumsum(rates) * 3600.0))

    def test_od2_needs_three_quiet_intervals_against_the_first_six_hours_peak(self):
        time = np.arange(8, dtype=float) * 3600
        # Two quiet intervals, a burst, then three quiet ones.
        self.assertEqual(od2_start(time, self.amounts([10, 0.5, 0.5, 5, 0.5, 0.5, 0.5])), 4 * 3600)
        # A larger peak after six hours does not set the threshold.
        time = np.arange(11, dtype=float) * 3600
        self.assertEqual(od2_start(time, self.amounts([10, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 200, 0.5, 0.5])), 3600)

    def test_od2_pulse_must_also_fall_below_ten_percent_of_its_peak(self):
        time = np.arange(8, dtype=float) * 3600
        rates = [10, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        self.assertEqual(od2_start(time, self.amounts(rates)), 3600)
        pulse = np.array([10, 5, 5, 0.5, 0.5, 0.5, 0.5, 0.5])
        self.assertEqual(od2_start(time, self.amounts(rates), pulse), 7200)

    def test_declared_source_pulse_moves_the_scored_boundary(self):
        data = json.loads(self.manifest.read_text())
        spec = data["acceptance"]
        path = self.root / "untagged.npz"
        with np.load(path, allow_pickle=False) as archive:
            arrays = {k: archive[k].copy() for k in archive.files}
        pulse = np.full(25, 0.5)
        pulse[:3] = [10, 5, 5]
        arrays["pulse"] = np.repeat(pulse[:, None] / 2, 2, axis=1)
        for attr in ("units", "sampling", "representation", "dimensions"):
            arrays["pulse__" + attr] = arrays["water_parent__" + attr].copy()
        np.savez(path, **arrays)
        spec["runs"]["untagged"]["fields"]["pulse"] = dict(spec["runs"]["untagged"]["fields"]["water_parent"], key="pulse")
        spec["artifacts"][path.name] = sha256_file(path)
        spec["source_pulse"] = True
        self.manifest.write_text(json.dumps(data))
        self.assertEqual(self.row("COMMON.OD2_WINDOWS")["metrics"]["startup_end"], 7200)

    def test_zero_length_startup_window_is_named_as_such(self):
        # Quiet from the start, then a burst in the fifth hour: the OD2 boundary is 0 s.
        rates = np.ones(24)
        rates[4] = 100
        mass = 100 + np.concatenate(([0.0], np.cumsum(rates)))
        self.array("water_parent", lambda a: np.repeat((mass / 2)[:, None], 2, axis=1), role="untagged")
        result = self.evaluate()
        self.assertEqual(self.row("COMMON.OD2_WINDOWS", result)["metrics"]["startup_end"], 0)
        self.assertIn("zero length", self.row("COMMON.WINDOW.startup", result)["limitation"])

    def test_option_d_excludes_criteria_5_and_6_from_a_declared_field(self):
        self.edit_spec(lambda s: s.update(case="D4-W", excluded_criteria=[5, 6]))
        result = self.evaluate()
        for name in ("WATER.ORIGINS.pbl.86400", "WATER.ORIGINS.evap.3600",
                     "WATER.PROCESS_WEIGHTED.established", "COMMON.CONVERGENCE"):
            row = self.row(name, result)
            self.assertEqual(row["verdict"], "NOT APPLICABLE")
            self.assertIn("option D", row["limitation"])
        # Criterion 4 keeps the copies' residual and repair.
        self.assertEqual(self.row("REFERENCE.ELIGIBILITY.established", result)["verdict"], "PASS")
        self.assertEqual(self.row("COMMON.EVIDENCE", result)["verdict"], "PASS")
        self.edit_spec(lambda s: s.pop("excluded_criteria"))
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400")["verdict"], "PASS")

    def test_unapproved_criterion_exclusion_is_a_data_failure(self):
        self.edit_spec(lambda s: s.update(excluded_criteria=[5]))
        result = self.evaluate()
        evidence = self.row("COMMON.EVIDENCE", result)
        self.assertEqual((evidence["verdict"], evidence["data_status"]), ("FAIL", "DATA FAILURE"))
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400", result)["verdict"], "PASS")
        self.assertEqual(result["exit_code"], 2)

    def test_water_data_failure_fails_the_row_and_the_evidence_row(self):
        self.edit_spec(lambda s: s["runs"]["candidate"]["fields"].pop("led_fix_pbl_applicable"))
        result = self.evaluate()
        row = self.row("WATER.LED_FIX.pbl.established", result)
        self.assertEqual((row["verdict"], row["data_status"]), ("FAIL", "DATA FAILURE"))
        evidence = self.row("COMMON.EVIDENCE", result)
        self.assertEqual(evidence["verdict"], "FAIL")
        self.assertIn(row["id"], evidence["metrics"]["row_data_failures"])
        self.assertEqual(result["exit_code"], 2)

    def test_energy_absent_field_is_a_not_assessable_data_failure(self):
        self.energy()
        self.edit_spec(lambda s: s["runs"]["candidate"]["fields"].pop("led_fix_pbl_applicable"))
        result = self.evaluate()
        row = self.row("ENERGY_SOURCE.LED_FIX.pbl.established", result)
        self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "DATA FAILURE"))
        self.assertEqual(self.row("COMMON.EVIDENCE", result)["verdict"], "FAIL")
        self.assertEqual(result["exit_code"], 2)

    def test_non_finite_tag_value_is_a_data_failure(self):
        self.array("tag_free", lambda a: np.where(np.arange(len(a))[:, None] == 5, np.nan, a))
        evidence = self.row("COMMON.EVIDENCE")
        self.assertEqual((evidence["verdict"], evidence["data_status"]), ("FAIL", "DATA FAILURE"))
        self.assertTrue(any("NaN" in e for e in evidence["metrics"]["validation_errors"]))

    def test_scorer_error_is_not_a_data_failure(self):
        with self.assertRaises(KeyError):
            Scorer(Bundle(self.manifest)).row("bug", lambda: {}["missing"])
        self.reference_detail()
        p = self.root / "reference_evidence.json"
        p.write_text("{not json")
        self.edit_spec(lambda s: s["artifacts"].update({p.name: sha256_file(p)}))
        self.assertEqual(self.row("REFERENCE.ELIGIBILITY.established")["data_status"], "DATA FAILURE")
        output = self.root / "crash.json"
        with mock.patch.object(Scorer, "run", side_effect=KeyError("missing")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["score", str(self.manifest), "--json", str(output)]), 4)
        result = json.loads(output.read_text())
        self.assertIn("KeyError", result["scorer_error"])
        self.assertNotIn("validation_errors", result)

    def pilot(self, declared=True):
        self.root = Path(self.temp.name) / "pilot"
        self.manifest = write_fixture(self.root, hours=6)
        if declared:
            self.edit_spec(lambda s: s.update(pilot_first_hour=True))

    def test_pilot_scores_the_first_hour_row_only_labelled_low_power(self):
        self.pilot()
        result = self.evaluate()
        row = self.row("WATER.ORIGINS.pbl.3600", result)
        self.assertEqual(row["verdict"], "PASS")
        self.assertIn("low power", row["limitation"])
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400", result)["verdict"], "NOT APPLICABLE")
        for name in ("WATER.CLOSURE", "WATER.NAMED_REMAINDER"):
            self.assertEqual(self.row(name, result)["verdict"], "REPORTED ONLY")
        self.assertIn("first 6 h", self.row("COMMON.PARENT_TEMPERATURE", result)["limitation"])
        self.assertFalse([r["id"] for r in result["rows"] if r["required"] and r["applicability"] == "applicable"
                          and r["data_status"] == "DATA FAILURE"])
        self.assertEqual(result["exit_code"], 3)

    def test_six_hour_run_without_the_pilot_scope_fails_the_missing_24h_endpoint(self):
        self.pilot(declared=False)
        result = self.evaluate()
        row = self.row("WATER.ORIGINS.pbl.86400", result)
        self.assertEqual((row["verdict"], row["data_status"]), ("FAIL", "DATA FAILURE"))
        self.assertEqual(result["exit_code"], 2)

    def test_pilot_scope_is_refused_for_a_full_day(self):
        self.edit_spec(lambda s: s.update(pilot_first_hour=True))
        result = self.evaluate()
        row = self.row("COMMON.PILOT_SCOPE", result)
        self.assertEqual((row["verdict"], row["data_status"]), ("NOT ASSESSABLE", "DATA FAILURE"))
        self.assertEqual(result["exit_code"], 2)
        self.assertEqual(self.row("WATER.ORIGINS.pbl.86400", result)["verdict"], "PASS")

    def test_unscored_approved_rows_are_explicit(self):
        result = self.evaluate()
        self.assertEqual(self.row("COMMON.REFINEMENT", result)["verdict"], "NOT ASSESSABLE")
        for name in ("WATER.RAIN_SNOW_CLOSURE", "WATER.PRECIP_TAG_SUM", "WATER.PRECIP_NET_FLOW_AUDIT",
                     "COMMON.OD6_CEILING", "WATER.SPHERE_TAG_SUM_BOUND"):
            self.assertEqual(self.row(name, result)["verdict"], "NOT APPLICABLE")
        self.edit_spec(lambda s: s.update(geometry_kind="sphere", compartments=["N", "R", "S"]))
        result = self.evaluate()
        for name in ("WATER.RAIN_SNOW_CLOSURE", "COMMON.OD6_CEILING", "WATER.SPHERE_TAG_SUM_BOUND"):
            row = self.row(name, result)
            self.assertEqual((row["verdict"], row["required"]), ("NOT ASSESSABLE", True))


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
