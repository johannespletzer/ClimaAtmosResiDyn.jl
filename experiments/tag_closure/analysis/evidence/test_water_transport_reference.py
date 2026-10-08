"""Equation, native geometry, measured floor and strict Bundle fault tests."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import numpy as np

from acceptance_data import Bundle, DataError, same_bits
from make_water_transport_fixture import evaluate_fixture, write_fixture, write_json
from manifest import sha256_file
from score_acceptance import Scorer
from water_transport_adapter import evaluate_water_transport
from water_transport_reference import (
    DESIGN_SHA256, FIELD_NAMES, NativeState, analytic, case_by_id, closure,
    error_rows, load_design, numerical, profile_error, quadrature, swapped_origins,
)


class EquationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.design = load_design()

    def test_frozen_design_and_native_integrals(self):
        self.assertEqual(sha256_file(Path(__file__).with_name("water_transport_design.json")), DESIGN_SHA256)
        case = case_by_id(self.design, "smooth_positive")
        state = analytic(self.design, case, 16)
        # On [0,L/4], integrate cos and sin directly. These aggregate values
        # catch a midpoint substitution even if partition closure is exact.
        self.assertAlmostEqual(float(np.sum(state.values["rho"][0, :4] * state.weights[:4])),
                               0.25 + 0.35 / (2 * np.pi), places=15)
        self.assertAlmostEqual(float(np.sum(state.values["tag_origin_a"][0, :4] * state.weights[:4])),
                               0.01 * (0.125 + 0.35 / (4 * np.pi) + 0.2 / (2 * np.pi)), places=15)
        x = np.mean(state.geometry[0])
        midpoint = 1 + 0.35 * np.cos(2 * np.pi * x)
        self.assertGreater(abs(state.values["rho"][0, 0] - midpoint), 1e-4)
        self.assertFalse(np.array_equal(state.values["rho"][0], state.values["rho"][1]))
        # Specific native concentration is the ratio of integrated masses.
        chi = state.values["tag_origin_a"] / state.values["rho"]
        np.testing.assert_allclose(chi * state.values["rho"], state.values["tag_origin_a"], rtol=2e-16)

    def test_periodic_mass_density_direction_and_quadrature(self):
        states = []
        for name in ("smooth_positive", "smooth_negative"):
            case = case_by_id(self.design, name)
            state = analytic(self.design, case, 64)
            states.append(state)
            for key in FIELD_NAMES:
                mass = np.sum(state.values[key] * state.weights, axis=1)
                np.testing.assert_allclose(mass, np.full(3, mass[0]), atol=5e-16, rtol=5e-15)
            self.assertTrue(closure(state, self.design)["meets"])
            for order in (8, 16, 32):
                independently_integrated = quadrature(self.design, case, 64, order)
                for key in FIELD_NAMES:
                    np.testing.assert_allclose(independently_integrated.values[key], state.values[key], atol=2e-15, rtol=2e-14)
        # Opposite velocities move the peak to different native cells.
        self.assertNotEqual(np.argmax(states[0].values["rho"][1]), np.argmax(states[1].values["rho"][1]))

    def test_nonuniform_labelled_inflow_both_signs(self):
        for name in ("boundary_positive", "boundary_negative"):
            case = case_by_id(self.design, name)
            state = analytic(self.design, case, 16)
            self.assertGreater(np.ptp(state.weights), 0)
            for row, seconds in enumerate((0, 3600, 86400)):
                a = float(np.sum(state.values["tag_origin_a"][row] * state.weights))
                b = float(np.sum(state.values["tag_origin_b"][row] * state.weights))
                self.assertAlmostEqual(a, 0.01 * 1e-5 * seconds, places=16)
                self.assertAlmostEqual(a + b, 0.01, places=16)
            if case["velocity_m_s"] > 0:
                self.assertGreater(state.values["tag_origin_a"][1, 0], 0)
                self.assertEqual(state.values["tag_origin_a"][1, -1], 0)
            else:
                self.assertEqual(state.values["tag_origin_a"][1, 0], 0)
                self.assertGreater(state.values["tag_origin_a"][1, -1], 0)
            # Parent transfer is zero, while the labelled boundary inventory changes.
            np.testing.assert_array_equal(state.values["water_parent"], np.full((3, 16), 0.01))

    def test_two_reservoir_closed_solution_and_actual_newton(self):
        case = case_by_id(self.design, "conservative_exchange")
        exact = analytic(self.design, case)
        q1, q2 = 0.01 * 1.1 * 1.5, 0.01 * 0.8 * 0.5
        expected_equilibrium = (q1 * 0.9 + q2 * 0.1) / (q1 + q2)
        decay = 1e-7 * (1 / q1 + 1 / q2)
        expected_first = q1 * expected_equilibrium + q1 * q2 / (q1 + q2) * 0.8 * np.exp(-decay * 3600)
        self.assertAlmostEqual(exact.values["tag_origin_a"][1, 0] * 1.5, expected_first, places=16)
        total = np.sum(exact.values["tag_origin_a"] * exact.weights, axis=1)
        np.testing.assert_allclose(total, q1 * 0.9 + q2 * 0.1, atol=1e-17)
        errors = []
        for dt in (120, 60, 30):
            one = numerical(self.design, case, dt=dt, newton=1)
            four = numerical(self.design, case, dt=dt, newton=4)
            self.assertEqual(four.diagnostics["executed_newton_solves"], int(86400 / dt) * 4)
            self.assertGreater(one.diagnostics["max_residual_by_iteration_kg_m2"][0], 1e-7)
            self.assertLess(one.diagnostics["max_residual_by_iteration_kg_m2"][1], 1e-17)
            np.testing.assert_allclose(one.values["tag_origin_a"], four.values["tag_origin_a"], atol=3e-16)
            errors.append(profile_error(one, exact, "tag_origin_a", 86400, "region")["absolute_L1_kg_m2"])
            self.assertLess(np.max(np.abs(one.diagnostics["mass_defect_kg_m2"])), 5e-15)
        self.assertGreater(errors[0], errors[1])
        self.assertGreater(errors[1], errors[2])
        self.assertLess(errors[1] / errors[0], 0.55)

    def test_upwind_grid_refinement_and_signed_boundary_account(self):
        for name in ("smooth_positive", "smooth_negative", "boundary_positive", "boundary_negative"):
            case = case_by_id(self.design, name)
            errors = []
            for grid in (16, 32, 64):
                reference = numerical(self.design, case, grid, 30)
                truth = analytic(self.design, case, grid)
                errors.append(profile_error(reference, truth, "tag_origin_a", 86400, "region")["absolute_L1_kg_m2"])
                self.assertEqual(reference.diagnostics["executed_steps"], 2880)
                self.assertLess(np.max(np.abs(reference.diagnostics["mass_defect_kg_m2"])), 2e-14)
                inflow = np.asarray(reference.diagnostics["signed_boundary_inflow_kg_m2"])
                if case["kind"] == "periodic_smooth":
                    np.testing.assert_array_equal(inflow, 0)
                else:
                    self.assertGreater(inflow[0, 2], 0)
                    self.assertLess(inflow[0, 3], 0)
                    self.assertAlmostEqual(inflow[0, 1], 0, places=16)
                    # Positive domain origin-A supply in either direction.
                    self.assertAlmostEqual(inflow[0, 2], 0.00036, places=14)
            self.assertGreater(errors[0], errors[1])
            self.assertGreater(errors[1], errors[2])
            # The front has no required smooth/Linf convergence order.

    def test_small_zero_overlay_rules_and_closed_wrong_origins(self):
        for case in self.design["cases"]:
            state = analytic(self.design, case, 64 if case["grids"] else None)
            for key in FIELD_NAMES:
                self.assertTrue(np.all(state.values[key] >= 0), (case["id"], key))
            bad = swapped_origins(state)
            self.assertTrue(closure(bad, self.design)["meets"])
            self.assertTrue(any(not row["meets"] for row in error_rows(bad, state, self.design)
                                if row["tag"] in ("origin_a", "origin_b")))
            modified = NativeState(state.time, state.faces, {key: value.copy() for key, value in state.values.items()}, {})
            modified.values["tag_tiny"][1:] += 1e-4 * state.values["water_parent"][1:]
            modified.values["tag_zero"][1:] += 1e-4 * state.values["water_parent"][1:]
            modified.values["tag_overlay"][1:] *= 1.5
            self.assertTrue(closure(modified, self.design)["meets"])
            for tag in ("tiny", "zero"):
                row = profile_error(modified, state, "tag_" + tag, 86400, "source")
                self.assertTrue(row["small_rule"])
                self.assertTrue(row["meets"])
                self.assertAlmostEqual(row["fraction_of_tolerance"]["absolute_L1"], 0.5, places=12)
            self.assertIsNone(profile_error(state, state, "tag_zero", 3600, "source")["relative_L1"])
            self.assertFalse(profile_error(modified, state, "tag_overlay", 86400, "source")["meets"])

    def test_refuse_unregistered_or_inapplicable_rungs(self):
        smooth = case_by_id(self.design, "smooth_positive")
        exchange = case_by_id(self.design, "conservative_exchange")
        for call in (lambda: analytic(self.design, smooth, 128),
                     lambda: numerical(self.design, smooth, 64, 15),
                     lambda: numerical(self.design, smooth, 64, 30, 2),
                     lambda: numerical(self.design, exchange, 16, 30, 2),
                     lambda: numerical(self.design, exchange, dt=30, newton=10)):
            with self.assertRaises(ValueError):
                call()


class AdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.root = Path(cls.scratch.name)
        cls.analytic_manifest = write_fixture(cls.root / "analytic", "smooth_positive")
        cls.numerical_manifest = write_fixture(cls.root / "numerical", "smooth_positive", reference_mode="numerical")

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def mutated(self, mutate_manifest=None, mutate_evidence=None, mutate_archive=None, base=None):
        directory = self.root / self.id().split(".")[-1]
        shutil.copytree((base or self.analytic_manifest).parent, directory)
        manifest = directory / "manifest.json"
        value = json.loads(manifest.read_text())
        if mutate_evidence:
            path = directory / "water_reference_evidence.json"
            detail = json.loads(path.read_text())
            mutate_evidence(detail)
            write_json(path, detail)
            value["acceptance"]["artifacts"][path.name] = sha256_file(path)
        if mutate_archive:
            path = directory / "candidate.npz"
            with np.load(path, allow_pickle=False) as archive:
                data = {key: archive[key].copy() for key in archive.files}
            mutate_archive(data)
            np.savez(path, **data)
            value["acceptance"]["artifacts"][path.name] = sha256_file(path)
        if mutate_manifest:
            mutate_manifest(value)
        write_json(manifest, value)
        return manifest

    def test_existing_bundle_scorer_and_measured_origin_mutant(self):
        bundle = Bundle(self.analytic_manifest)
        self.assertEqual(bundle.validate(), [])
        measured = Scorer(bundle).reference_eligibility(0, 86400)
        self.assertTrue(measured["meets"])
        self.assertEqual(len(measured["metrics"]["rungs"]), 18)
        # All grids/time steps and all integration orders are retained.
        self.assertTrue(any(not row["eligible"] for row in measured["metrics"]["rungs"] if row["kind"] == "numerical"))
        result = evaluate_fixture(self.analytic_manifest)
        self.assertEqual(result["candidate_verdict"], "PASS")
        self.assertTrue(result["origin_swap"]["mutation_verified"])
        self.assertEqual(result["scientific_qualification"], "NOT QUALIFIED")
        json.dumps(result, allow_nan=False)
        for tag in bundle.spec["tags"]:
            row = Scorer(bundle).profile(tag, 86400)
            self.assertTrue(row["meets"])

    def test_actual_floors_override_claimed_eligibility(self):
        manifest = self.mutated(mutate_evidence=lambda detail: detail.update(
            converged=True, eligible=True, floor_fraction_of_tolerance=0.0), base=self.numerical_manifest)
        result = evaluate_water_transport(Bundle(manifest))
        self.assertFalse(result["meets"])
        self.assertGreater(result["metrics"]["floor_fraction_of_tolerance"], 0.25)

    def test_fixture_same_parent_uses_actual_parent_bits(self):
        for case_id in ("smooth_positive", "boundary_positive", "conservative_exchange"):
            for mode in ("analytic", "numerical"):
                directory = self.root / (self.id().split(".")[-1] + "_" + case_id + "_" + mode)
                bundle = Bundle(write_fixture(directory, case_id, reference_mode=mode))
                measured_same_parent = all(
                    same_bits(bundle.field("candidate", name).values,
                              bundle.field("reference", name).values)
                    for name in ("rho", "water_parent"))
                self.assertEqual(bundle.spec["same_parent_comparisons"], measured_same_parent,
                                 (case_id, mode))

    def evaluate_mutated_fixture(self, mutate_archive):
        manifest = self.mutated(mutate_archive=mutate_archive)
        # Keep the separately evaluated mutant's complete artifact inventory
        # current too. This fault tests the verdict, not checksum rejection.
        mutant_manifest = manifest.with_name("manifest_origin_swap.json")
        mutant = json.loads(mutant_manifest.read_text())
        mutant["acceptance"]["artifacts"]["candidate.npz"] = sha256_file(manifest.parent / "candidate.npz")
        write_json(mutant_manifest, mutant)
        return evaluate_fixture(manifest)

    def test_candidate_closure_gates_fixture_verdict(self):
        result = self.evaluate_mutated_fixture(lambda data: data["water_parent"][1:].fill(0))
        self.assertTrue(result["measured_reference"]["meets"])
        self.assertTrue(all(row["meets"] for row in result["candidate_profiles"]))
        self.assertFalse(result["measured_reference"]["metrics"]["candidate_closure"]["meets"])
        self.assertEqual(result["candidate_verdict"], "FAIL")

    def test_prescribed_parent_gates_proportional_scaling(self):
        def change(data):
            for name in FIELD_NAMES:
                data[name][1:] *= 2
        result = self.evaluate_mutated_fixture(change)
        self.assertTrue(result["measured_reference"]["meets"])
        self.assertTrue(all(row["meets"] for row in result["candidate_profiles"]))
        self.assertTrue(result["measured_reference"]["metrics"]["candidate_closure"]["meets"])
        self.assertFalse(result["measured_reference"]["metrics"]["candidate_parent_trajectory"]["meets"])
        self.assertEqual(result["candidate_verdict"], "FAIL")

    def test_mutant_verification_requires_the_registered_swap(self):
        for fault in ("parent", "overlay", "different_origins"):
            directory = self.root / (self.id().split(".")[-1] + "_" + fault)
            manifest = write_fixture(directory, "conservative_exchange")
            path = directory / "origin_swap.npz"
            with np.load(path, allow_pickle=False) as archive:
                data = {key: archive[key].copy() for key in archive.files}
            if fault == "parent":
                for name in FIELD_NAMES:
                    data[name][1:] *= 2
            elif fault == "overlay":
                data["tag_overlay"][1:] *= 2
            else:
                # This is a different closed wrong-origin assignment, not
                # the registered swap. An origin failure alone is insufficient.
                data["tag_origin_a"][1:] = data["water_parent"][1:]
                data["tag_origin_b"][1:] = 0
            np.savez(path, **data)
            for name in ("manifest.json", "manifest_origin_swap.json"):
                value = json.loads((directory / name).read_text())
                value["acceptance"]["artifacts"][path.name] = sha256_file(path)
                write_json(directory / name, value)
            result = evaluate_fixture(manifest)
            self.assertEqual(result["candidate_verdict"], "PASS")
            self.assertTrue(result["origin_swap"]["closure"]["meets"])
            self.assertTrue(result["origin_swap"]["origin_failure_measured"])
            self.assertFalse(result["origin_swap"]["invariants"]["meets"], fault)
            self.assertFalse(result["origin_swap"]["mutation_verified"], fault)

    def test_refuse_incomplete_ladder(self):
        manifest = self.mutated(mutate_evidence=lambda detail: detail["rungs"].pop())
        with self.assertRaisesRegex(DataError, "ladder"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_shared_rule(self):
        manifest = self.mutated(mutate_evidence=lambda detail: detail.update(shared_rules=detail["independent_rules"]))
        with self.assertRaisesRegex(DataError, "shared"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_extra_active_rule(self):
        manifest = self.mutated(mutate_manifest=lambda value: value["acceptance"]["active_rules"].append("precipitation"))
        with self.assertRaisesRegex(DataError, "active rule"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_active_excluded_process(self):
        manifest = self.mutated(mutate_archive=lambda data: data["excluded_activity_subsidence"].fill(1e-7))
        with self.assertRaisesRegex(DataError, "excluded process"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_scope_promotion_or_d4w(self):
        manifest = self.mutated(mutate_manifest=lambda value: value["acceptance"]["claim"].update(scope="production eight tags"))
        with self.assertRaisesRegex(DataError, "scope"):
            evaluate_water_transport(Bundle(manifest))
        value = json.loads(manifest.read_text())
        value["acceptance"]["claim"]["scope"] = "preregistered water known-answer development fixture"
        value["acceptance"]["case"] = "D4-W"
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "option D"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_missing_tag_and_units(self):
        manifest = self.mutated(mutate_manifest=lambda value: value["acceptance"]["tags"].pop())
        with self.assertRaisesRegex(DataError, "count"):
            evaluate_water_transport(Bundle(manifest))
        value = json.loads(manifest.read_text())
        value["acceptance"]["tags"] = load_design()["tags"]
        value["acceptance"]["runs"]["candidate"]["fields"]["water_parent"]["units"] = "g m^-3"
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "units"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_geometry_weights_and_times(self):
        def change(data):
            data["geometry"][0, 0] += 0.001
        manifest = self.mutated(mutate_archive=change)
        with self.assertRaisesRegex(DataError, "native face"):
            evaluate_water_transport(Bundle(manifest))
        with np.load(manifest.parent / "candidate.npz", allow_pickle=False) as archive:
            data = {key: archive[key].copy() for key in archive.files}
        data["geometry"][0, 0] -= 0.001
        data["weights"][0] *= 2
        np.savez(manifest.parent / "candidate.npz", **data)
        value = json.loads(manifest.read_text())
        value["acceptance"]["artifacts"]["candidate.npz"] = sha256_file(manifest.parent / "candidate.npz")
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "native face"):
            evaluate_water_transport(Bundle(manifest))
        data["weights"][0] /= 2
        data["time"][1] += 1
        np.savez(manifest.parent / "candidate.npz", **data)
        value["acceptance"]["artifacts"]["candidate.npz"] = sha256_file(manifest.parent / "candidate.npz")
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "samples"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_wrong_dtype_stale_hash_or_evaluator(self):
        manifest = self.mutated(mutate_archive=lambda data: data.update(rho=data["rho"].astype(np.float32)))
        with self.assertRaisesRegex(DataError, "dtype"):
            evaluate_water_transport(Bundle(manifest))
        value = json.loads(manifest.read_text())
        value["acceptance"]["artifacts"]["candidate.npz"] = "0" * 64
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "checksum"):
            evaluate_water_transport(Bundle(manifest))
        value["acceptance"]["artifacts"]["candidate.npz"] = sha256_file(manifest.parent / "candidate.npz")
        detail = json.loads((manifest.parent / "water_reference_evidence.json").read_text())
        detail["evaluator_files"]["water_transport_reference.py"] = "0" * 64
        write_json(manifest.parent / "water_reference_evidence.json", detail)
        value["acceptance"]["artifacts"]["water_reference_evidence.json"] = sha256_file(manifest.parent / "water_reference_evidence.json")
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "evaluator identity"):
            evaluate_water_transport(Bundle(manifest))

    def test_refuse_changed_reference_even_with_fresh_archive_hash(self):
        manifest = self.mutated()
        path = manifest.parent / "reference.npz"
        with np.load(path, allow_pickle=False) as archive:
            data = {key: archive[key].copy() for key in archive.files}
        data["tag_origin_a"][1:] = data["tag_origin_b"][1:]
        np.savez(path, **data)
        value = json.loads(manifest.read_text())
        value["acceptance"]["artifacts"][path.name] = sha256_file(path)
        write_json(manifest, value)
        with self.assertRaisesRegex(DataError, "independent equations"):
            evaluate_water_transport(Bundle(manifest))


if __name__ == "__main__":
    unittest.main()
