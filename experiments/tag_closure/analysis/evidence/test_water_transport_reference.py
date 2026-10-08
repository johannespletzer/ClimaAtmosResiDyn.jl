"""Equation, native geometry, measured floor and strict Bundle fault tests."""

import contextlib
import copy
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

import make_water_transport_fixture as driver
import score_acceptance
from acceptance_data import Bundle, DataError, same_bits
from make_water_transport_fixture import evaluate_fixture, suite_exit_code, write_fixture, write_json
from manifest import sha256_file
from score_acceptance import (
    DAY, FIRST_HOUR, FLOOR_FRACTION_MAX, ORIGIN_L1_DAY, ORIGIN_L1_FIRST_HOUR, ORIGIN_LINF_DAY,
    ORIGIN_LINF_FIRST_HOUR, SCORER_PATHS, SECOND_HALF_TIE, SMALL, SMALL_SHARE, Scorer,
    approved_numbers_sha256,
)
from water_transport_adapter import (
    LADDER_TIE, converges, evaluate_water_transport, first_iteration_at_roundoff, ladder_axes,
    producer_identity, read_native, rung_floor, rungs,
)
from water_transport_reference import (
    BASE_COMMIT, DESIGN_SHA256, FIELD_NAMES, NativeState, analytic, case_by_id, closure,
    error_rows, floor_fraction, load_design, native_faces, numerical, profile_error, quadrature,
    refinement_rungs, swapped_origins,
)

CASE_IDS = ("smooth_positive", "smooth_negative", "boundary_positive", "boundary_negative",
            "conservative_exchange")


class EquationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.design = load_design()

    def test_design_sha256_is_an_integrity_pin_only(self):
        # The hash shows the file is unchanged. It makes no claim about timing.
        self.assertNotIn("frozen_before_results", self.design)
        self.assertIn("Integrity only.", self.design["design_sha256_pin"])
        self.assertNotIn("frozen", json.dumps(self.design["design_sha256_pin"]))
        self.assertEqual(sha256_file(Path(__file__).with_name("water_transport_design.json")), DESIGN_SHA256)
        configs = Path(__file__).resolve().parents[2] / "configs"
        for name in ("water_transport_known_answers.json", "water_transport_numerical_fixture.json"):
            self.assertEqual(json.loads((configs / name).read_text())["design_sha256"], DESIGN_SHA256)

    def test_design_and_native_integrals(self):
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

    def test_design_numbers_are_the_scorers_approved_constants(self):
        # The reference imports the scorer's constants. The design keeps a copy
        # for the record, and the copy must not drift from them.
        rules = self.design["profile_rules"]
        self.assertEqual(rules["first_hour_region_L1"], ORIGIN_L1_FIRST_HOUR["region"])
        self.assertEqual(rules["first_hour_source_L1"], ORIGIN_L1_FIRST_HOUR["source"])
        self.assertEqual(rules["first_hour_Linf"], ORIGIN_LINF_FIRST_HOUR)
        self.assertEqual(rules["day_L1"], ORIGIN_L1_DAY)
        self.assertEqual(rules["day_Linf"], ORIGIN_LINF_DAY)
        self.assertEqual(rules["small_share_below"], SMALL_SHARE)
        self.assertEqual(rules["small_absolute_parent_fraction"], SMALL)
        self.assertEqual(rules["floor_max_fraction_of_tolerance"], FLOOR_FRACTION_MAX)
        self.assertEqual(rules["ladder_tie"], SECOND_HALF_TIE)
        self.assertIs(LADDER_TIE, SECOND_HALF_TIE)
        self.assertEqual(self.design["times_seconds"][1:], [FIRST_HOUR, DAY])

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
            # Counted in the solver loop, so a skipped step or solve shows.
            self.assertEqual(four.diagnostics["executed_steps"], {120: 720, 60: 1440, 30: 2880}[dt])
            self.assertEqual(four.diagnostics["executed_newton_solves"], {120: 2880, 60: 5760, 30: 11520}[dt])
            self.assertEqual(one.diagnostics["executed_newton_solves"], one.diagnostics["executed_steps"])
            self.assertGreater(one.diagnostics["max_residual_by_iteration_kg_m2"][0], 1e-7)
            self.assertLess(one.diagnostics["max_residual_by_iteration_kg_m2"][1], 1e-17)
            residuals = four.diagnostics["max_residual_by_iteration_kg_m2"]
            self.assertEqual(len(residuals), 5)
            # Every later iteration records its own residual, at roundoff.
            self.assertTrue(all(0 < value < 1e-17 for value in residuals[1:]), residuals)
            self.assertGreater(residuals[0], 1e-7)
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
            for grid, dt in ((16, 120), (32, 60), (64, 30)):
                reference = numerical(self.design, case, grid, dt)
                truth = analytic(self.design, case, grid)
                errors.append(profile_error(reference, truth, "tag_origin_a", 86400, "region")["absolute_L1_kg_m2"])
                self.assertEqual(reference.diagnostics["executed_steps"], 86400 // dt)
                self.assertEqual(reference.diagnostics["executed_newton_solves"], 0)
                self.assertEqual(reference.diagnostics["max_residual_by_iteration_kg_m2"], [])
                # The solver starts from the initial cell integrals, not a later sample.
                for key in FIELD_NAMES:
                    np.testing.assert_allclose(reference.values[key][0], truth.values[key][0], rtol=1e-14, atol=1e-18)
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
        self.assertEqual(numerical(self.design, case_by_id(self.design, "boundary_positive"), 16, 120)
                         .diagnostics["executed_steps"], 720)

    def test_error_rows_cover_every_tag_at_both_approved_endpoints(self):
        state = analytic(self.design, case_by_id(self.design, "smooth_positive"), 16)
        rows = error_rows(state, state, self.design)
        self.assertEqual([(row["tag"], row["endpoint_seconds"]) for row in rows],
                         [(tag["name"], time) for time in (3600, 86400) for tag in self.design["tags"]])

    def test_front_floor_is_l1_only(self):
        # A row whose L∞ fraction is larger than its L1 fraction. The design
        # states no L∞ requirement for a front, so its floor is the L1 one.
        row = {"fraction_of_tolerance": {"L1": 0.2, "Linf": 0.9}}
        self.assertEqual(floor_fraction(row, case_by_id(self.design, "boundary_positive")), 0.2)
        self.assertEqual(floor_fraction(row, case_by_id(self.design, "smooth_positive")), 0.9)
        small = {"fraction_of_tolerance": {"absolute_L1": 0.3}}
        self.assertEqual(floor_fraction(small, case_by_id(self.design, "boundary_negative")), 0.3)
        # A measured front row of that shape exists on the frozen ladder.
        case = case_by_id(self.design, "boundary_positive")
        rows = error_rows(numerical(self.design, case, 64, 30), analytic(self.design, case, 64), self.design)
        front = [r for r in rows if "Linf" in r["fraction_of_tolerance"] and
                 r["fraction_of_tolerance"]["Linf"] > r["fraction_of_tolerance"]["L1"]]
        self.assertTrue(front)
        for r in front:
            self.assertEqual(floor_fraction(r, case), r["fraction_of_tolerance"]["L1"])

    def test_producer_floor_and_convergence_rules(self):
        smooth = case_by_id(self.design, "smooth_positive")
        rows = [{"endpoint_seconds": 3600, "fraction_of_tolerance": {"L1": 0.1, "Linf": 0.05}},
                {"endpoint_seconds": 86400, "fraction_of_tolerance": {"L1": 0.2, "Linf": 0.05}}]
        self.assertEqual(rung_floor(rows, smooth, 0, 86400), 0.2)
        self.assertEqual(rung_floor(rows, smooth, 0, 3600), 0.1)
        # Only the rungs up to the selected one form each axis.
        exchange = case_by_id(self.design, "conservative_exchange")
        ladder = rungs(self.design, exchange)
        selected = next(r for r in ladder if r["dt_seconds"] == 60 and r["newton_iterations"] == 2)
        axes = ladder_axes(exchange, selected, ladder)
        self.assertEqual([r["dt_seconds"] for r in axes["dt_seconds"]], [120, 60])
        self.assertEqual([r["newton_iterations"] for r in axes["newton_iterations"]], [1, 2])
        self.assertNotIn("grid", axes)
        chain = {"dt_seconds": [{"role": name, "dt_seconds": dt} for name, dt in (("a", 120), ("b", 60), ("c", 30))]}
        chain = {axis: [{**rung, "grid": None, "newton_iterations": None} for rung in values]
                 for axis, values in chain.items()}
        tie = 1e-12
        self.assertEqual(converges(chain, {"a": 1.0, "b": 1.0 + tie / 2, "c": 1.0}, tie)[0], True)
        self.assertEqual(converges(chain, {"a": 1.0, "b": 1.0 + 3 * tie, "c": 1.0}, tie)[0], False)
        # The default tie is the scorer's, added to the floor fraction, not scaled by it.
        self.assertEqual(converges(chain, {"a": 1.0, "b": 1.0 + SECOND_HALF_TIE / 2, "c": 1.0})[0], True)
        self.assertEqual(converges(chain, {"a": 1.0, "b": 1.0 + 3 * SECOND_HALF_TIE, "c": 1.0})[0], False)
        self.assertEqual(converges(chain, {"a": 1e6, "b": 1e6 * (1 + 1e-15), "c": 1.0})[0], False)
        self.assertEqual(converges(chain, {"a": 0.0, "b": SECOND_HALF_TIE / 2, "c": 0.0})[0], True)
        # A rise of exactly the tie is still a tie.
        exact = {"a": 1.0, "b": 1.0 + SECOND_HALF_TIE, "c": 1.0 + SECOND_HALF_TIE}
        self.assertEqual(converges(chain, exact), (True, []))
        # A rise in the middle is caught even when the last rung is lower again.
        self.assertEqual(converges(chain, {"a": 2.0, "b": 3.0, "c": 1.0}, tie)[0], False)
        self.assertEqual(converges(chain, {"a": 3.0, "b": 2.0, "c": 1.0}, tie), (True, []))
        self.assertTrue(first_iteration_at_roundoff([1e-6, 1e-16], 1e-16))
        self.assertFalse(first_iteration_at_roundoff([1e-6, 2e-16], 1e-16))
        self.assertFalse(first_iteration_at_roundoff([1e-6], 1e-16))

    def test_fixed_cfl_rung_construction(self):
        # Every advective rung refines the grid and the time step together.
        for name in ("smooth_positive", "smooth_negative", "boundary_positive", "boundary_negative"):
            case = case_by_id(self.design, name)
            pairs = refinement_rungs(case)
            self.assertEqual(pairs, [(16, 120), (32, 60), (64, 30)])
            for (coarse, coarse_dt), (fine, fine_dt) in zip(pairs, pairs[1:]):
                self.assertEqual((fine, fine_dt), (2 * coarse, coarse_dt // 2))
            numerical_rungs = [r for r in rungs(self.design, case) if r["kind"] == "numerical"]
            self.assertEqual([(r["grid"], r["dt_seconds"]) for r in numerical_rungs], pairs)
            cfl = {abs(case["velocity_m_s"]) * dt * grid / case["length_m"] for grid, dt in pairs}
            self.assertEqual(len(cfl), 1)
            self.assertAlmostEqual(cfl.pop(), 0.0192, places=15)
            reference = numerical(self.design, case, 32, 60)
            self.assertAlmostEqual(reference.diagnostics["nominal_cfl"], 0.0192, places=15)
            axes = ladder_axes(case, numerical_rungs[-1], rungs(self.design, case))
            self.assertEqual(list(axes), ["fixed_cfl"])
            self.assertEqual([(r["grid"], r["dt_seconds"]) for r in axes["fixed_cfl"]], pairs)
            axes = ladder_axes(case, numerical_rungs[1], rungs(self.design, case))
            self.assertEqual([(r["grid"], r["dt_seconds"]) for r in axes["fixed_cfl"]], pairs[:2])
            # A grid with a time step from another rung is off the ladder.
            for grid, dt in ((64, 120), (16, 30), (32, 30)):
                with self.assertRaisesRegex(ValueError, "fixed-CFL"):
                    numerical(self.design, case, grid, dt)
            bad = rungs(self.design, case)[0]
            with self.assertRaises(DataError):
                ladder_axes(case, {**bad, "dt_seconds": 30}, rungs(self.design, case))
        smooth = case_by_id(self.design, "smooth_positive")
        for change in ({"grid_times_dt_seconds": 3840}, {"dt_seconds": [120, 60, 15]},
                       {"dt_seconds": [120, 60]}, {"grids": [16, 32]}, {"ladder": "time_step_only"}):
            with self.assertRaises(ValueError):
                refinement_rungs({**smooth, **change})
        # The CFL number is taken on the nominal spacing L / grid.
        longer = numerical(self.design, {**smooth, "length_m": 2.0}, 32, 60)
        self.assertAlmostEqual(longer.diagnostics["nominal_cfl"], 0.0096, places=15)
        exchange = case_by_id(self.design, "conservative_exchange")
        self.assertEqual(refinement_rungs(exchange), [(None, 120), (None, 60), (None, 30)])
        self.assertIsNone(numerical(self.design, exchange, dt=60, newton=1).diagnostics["nominal_cfl"])
        with self.assertRaises(ValueError):
            refinement_rungs({**exchange, "ladder": "fixed_cfl"})

    def test_zero_or_dry_parent_is_a_data_failure(self):
        # G3_PLAN 6.1.3's dry and zero-state limit. The frozen design has no
        # dry case, so this unit test stands in for one.
        state = analytic(self.design, case_by_id(self.design, "smooth_positive"), 16)
        dry = NativeState(state.time, state.faces,
                          {key: (value if key == "rho" else np.zeros_like(value)) for key, value in state.values.items()}, {})
        for tag in self.design["tags"]:
            with self.assertRaisesRegex(DataError, "nonpositive reference parent"):
                profile_error(dry, dry, "tag_" + tag["name"], 86400, tag["kind"])
        with self.assertRaisesRegex(DataError, "unknown tag classification"):
            profile_error(state, state, "tag_origin_a", 86400, "partition")
        with self.assertRaisesRegex(DataError, "no approved origin tolerance"):
            profile_error(NativeState(np.array([0.0, 3600.0, 21600.0]), state.faces, state.values, {}),
                          NativeState(np.array([0.0, 3600.0, 21600.0]), state.faces, state.values, {}),
                          "tag_origin_a", 21600, "region")

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
        fast = copy.deepcopy(smooth)
        fast["velocity_m_s"] = 1.0
        uneven, late = copy.deepcopy(self.design), copy.deepcopy(self.design)
        uneven["times_seconds"] = [0, 3600, 86401]
        late["times_seconds"] = [60, 3600, 86400]
        state = analytic(self.design, smooth, 16)
        dry_cell = NativeState(state.time, state.faces, {key: value.copy() for key, value in state.values.items()}, {})
        dry_cell.values["rho"][2, 3] = 0.0
        # The native-cell CFL guard, just above one and exactly at one.
        width = float(np.min(np.diff(native_faces(smooth, 16))))
        above, at_one = copy.deepcopy(smooth), copy.deepcopy(smooth)
        above["velocity_m_s"] = 1.2 * width / 120
        at_one["velocity_m_s"] = width / 120
        self.assertEqual(at_one["velocity_m_s"] * 120 / width, 1.0)
        self.assertEqual(numerical(self.design, at_one, 16, 120).diagnostics["executed_steps"], 720)
        shifted = NativeState(state.time, state.faces + 0.01, state.values, {})
        for call in (lambda: analytic(self.design, smooth, 128),
                     lambda: numerical(self.design, fast, 64, 30),
                     lambda: numerical(self.design, above, 16, 120),
                     lambda: profile_error(shifted, state, "tag_origin_a", 86400, "region"),
                     lambda: numerical(uneven, smooth, 64, 30),
                     lambda: numerical(late, smooth, 64, 30),
                     lambda: profile_error(dry_cell, state, "tag_origin_a", 86400, "region"),
                     lambda: profile_error(state, dry_cell, "tag_origin_a", 86400, "region"),
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
        cls.analytic = {case_id: write_fixture(cls.root / ("analytic_" + case_id), case_id) for case_id in CASE_IDS}
        cls.numerical = {case_id: write_fixture(cls.root / ("numerical_" + case_id), case_id, reference_mode="numerical")
                         for case_id in ("smooth_positive", "boundary_positive", "boundary_negative",
                                         "conservative_exchange")}
        cls.analytic_manifest = cls.analytic["smooth_positive"]
        cls.numerical_manifest = cls.numerical["smooth_positive"]

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

    def test_bundle_records_planning_commit_and_approved_numbers(self):
        bundle = Bundle(self.analytic_manifest)
        self.assertEqual(bundle.validate(), [])
        self.assertEqual(bundle.spec["planning_commit"], BASE_COMMIT)
        self.assertEqual(bundle.spec["approved_numbers_sha256"], approved_numbers_sha256())
        self.assertEqual(bundle.spec["reference"]["producer"], producer_identity())
        self.assertEqual(producer_identity()["script"], "water_transport_adapter.py")

    def test_every_analytic_case_through_the_producer_and_the_scorer(self):
        expected_rungs = {"periodic_smooth": 12, "labelled_inflow": 3, "two_reservoir_exchange": 9}
        for case_id, manifest in self.analytic.items():
            with self.subTest(case_id):
                bundle = Bundle(manifest)
                measured = evaluate_water_transport(bundle)
                case = case_by_id(load_design(), case_id)
                self.assertTrue(measured["meets"])
                self.assertTrue(measured["reference_eligibility"].startswith("constructed eligibility"))
                self.assertEqual(len(measured["metrics"]["rungs"]), expected_rungs[case["kind"]])
                # Every rung is retained, eligible or not.
                self.assertEqual(measured["metrics"]["rungs"][0]["role"], "floor_g{}_dt120_n{}".format(
                    case["grids"][0] if case["grids"] else None,
                    case["newton_iterations"][0] if case["newton_iterations"] else None))
                declaration = measured["declaration"]
                self.assertLess(declaration["floors"]["reference_discretization"], 1e-10)
                basis = declaration["floor_basis"]["reference_discretization"]
                self.assertTrue(basis.startswith("Measured and constructed" if case["kind"] == "periodic_smooth"
                                                 else "Constructed, not measured"), basis)
                self.assertTrue(declaration["eligibility_basis"]["converged"].startswith("Inapplicable"))
                scored = Scorer(bundle).reference_eligibility(0, DAY)
                self.assertTrue(scored["meets"])
                self.assertEqual(scored["metrics"]["floors"], declaration["floors"])
                self.assertIn(producer_identity()["sha256"], scored["reference_eligibility"])
                result = evaluate_fixture(manifest)
                self.assertEqual(result["candidate_verdict"], "PASS")
                self.assertTrue(result["origin_swap"]["mutation_verified"])
                self.assertEqual(result["scientific_qualification"], "NOT QUALIFIED")
                json.dumps(result, allow_nan=False)
                for tag in bundle.spec["tags"]:
                    self.assertTrue(Scorer(bundle).profile(tag, 86400)["meets"])

    def test_numerical_references_measured_floor_and_convergence(self):
        smooth = evaluate_water_transport(Bundle(self.numerical["smooth_positive"]))
        self.assertFalse(smooth["meets"])
        self.assertEqual(smooth["reference_eligibility"], "ineligible")
        self.assertAlmostEqual(smooth["declaration"]["floors"]["reference_discretization"], 2.9993801653943, places=9)
        # On the fixed-CFL ladder the smooth floor falls at every doubling. It
        # converges, and its floor is still far above the quarter rule.
        self.assertTrue(smooth["declaration"]["converged"])
        self.assertTrue(smooth["declaration"]["eligibility_basis"]["converged"].startswith("Measured. No refinement"))
        self.assertEqual([(r["grid"], r["dt_seconds"]) for r in smooth["metrics"]["rungs"] if r["kind"] == "numerical"],
                         [(16, 120), (32, 60), (64, 30)])
        self.assertFalse(Scorer(Bundle(self.numerical["smooth_positive"])).reference_eligibility(0, DAY)["meets"])
        positive = evaluate_water_transport(Bundle(self.numerical["boundary_positive"]))
        self.assertTrue(positive["declaration"]["converged"])
        self.assertFalse(positive["meets"])
        # The negative front rises on the first doubling. In the first hour the
        # front travels 0.036 m, about one top cell at grid 32.
        front = evaluate_water_transport(Bundle(self.numerical["boundary_negative"]))
        self.assertFalse(front["declaration"]["converged"])
        self.assertIn("rises along fixed_cfl g16 dt120 nNone", front["declaration"]["eligibility_basis"]["converged"])
        exchange = evaluate_water_transport(Bundle(self.numerical["conservative_exchange"]))
        self.assertTrue(exchange["meets"])
        self.assertTrue(exchange["reference_eligibility"].startswith("measured eligibility"))
        self.assertTrue(exchange["declaration"]["converged"])
        self.assertTrue(exchange["declaration"]["jacobian_complete"])
        self.assertTrue(exchange["declaration"]["eligibility_basis"]["jacobian_complete"].startswith("Measured"))
        cross_check = exchange["metrics"]["closed_form_cross_check"]
        self.assertEqual(sorted(cross_check), ["n1", "n2", "n4"])
        self.assertEqual([row["dt_seconds"] for row in cross_check["n4"]], [120, 60, 30])
        self.assertEqual([(row["grid"], row["dt_seconds"]) for row in smooth["metrics"]["closed_form_cross_check"]["nNone"]],
                         [(16, 120), (32, 60), (64, 30)])
        selected = exchange["metrics"]["rungs"][-1]
        self.assertEqual((selected["dt_seconds"], selected["newton_iterations"]), (30, 4))
        allowance = 128 * np.finfo(np.float64).eps * 0.01 * 1.1 * 1.5
        residual = selected["diagnostics"]["max_residual_by_iteration_kg_m2"][1]
        self.assertIn(f"{residual:.3g} kg m^-2 against a roundoff allowance of {allowance:.3g}",
                      exchange["declaration"]["eligibility_basis"]["jacobian_complete"])
        self.assertAlmostEqual(exchange["declaration"]["floors"]["reference_discretization"], 0.004568187979689864,
                               places=12)
        self.assertTrue(Scorer(Bundle(self.numerical["conservative_exchange"])).reference_eligibility(0, DAY)["meets"])
        result = evaluate_fixture(self.numerical["smooth_positive"])
        self.assertEqual(result["candidate_verdict"], "NOT ASSESSABLE")
        self.assertIsNone(result["origin_swap"]["mutation_verified"])

    def test_scorer_reads_the_declared_file_and_the_producer_refuses_a_changed_one(self):
        def lower(detail):
            detail["floors"]["reference_discretization"] = 0.0
            detail["converged"] = True
        manifest = self.mutated(mutate_evidence=lower, base=self.numerical_manifest)
        # The scorer reads the declaration as the decision of 2026-10-07 allows.
        self.assertTrue(Scorer(Bundle(manifest)).reference_eligibility(0, DAY)["meets"])
        # Rerunning the producer refuses it.
        with self.assertRaisesRegex(DataError, "declared eligibility differs"):
            evaluate_water_transport(Bundle(manifest))
        with self.assertRaisesRegex(DataError, "declared eligibility differs"):
            evaluate_fixture(manifest)

    def test_scorer_refuses_a_declaration_without_its_producer(self):
        manifest = self.mutated(mutate_manifest=lambda value: value["acceptance"]["reference"].pop("producer"))
        with self.assertRaisesRegex(DataError, "producing script"):
            Scorer(Bundle(manifest)).reference_eligibility(0, DAY)
        with self.assertRaisesRegex(DataError, "producer"):
            evaluate_water_transport(Bundle(manifest))

    def test_coverage_is_reported_and_never_a_verdict(self):
        bundle = Bundle(self.analytic_manifest)
        coverage = Scorer(bundle).active_rule_coverage()
        self.assertNotIn("verdict", coverage)
        self.assertTrue(coverage["limitation"].startswith("reported, not a gate until OD9"))
        self.assertEqual(coverage["metrics"]["tested_active_rules"], ["prescribed_conservative_advection"])
        scorer = Scorer(bundle)
        rows = {row["id"]: row for row in scorer.run()["rows"]}
        self.assertEqual(rows["REFERENCE.ACTIVE_RULE_COVERAGE"]["verdict"], "REPORTED ONLY")
        self.assertFalse(rows["REFERENCE.ACTIVE_RULE_COVERAGE"]["required"])

    def test_fixture_modules_are_not_scorer_files(self):
        # The fixture modules are pinned by the producer hash and the evidence
        # file's evaluator_files, not by every bundle's scorer identity.
        self.assertFalse([path for path in SCORER_PATHS if path.startswith("water_transport")])
        self.assertNotIn("water_transport", Path(score_acceptance.__file__).read_text())

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


class ProfileParityTests(unittest.TestCase):
    """The reference's OD3 rows equal the scorer's profile on a nonzero error."""

    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        root = Path(cls.scratch.name)
        manifest = write_fixture(root / "fixture", "smooth_positive", comparison_grid=16)
        path = manifest.parent / "candidate.npz"
        with np.load(path, allow_pickle=False) as archive:
            data = {key: archive[key].copy() for key in archive.files}
        x = np.mean(data["geometry"], axis=1)
        parent = data["water_parent"]
        # A closed origin error, an overlay error that fails only the 24 h
        # row, and small absolute errors in the tiny and zero tags.
        shift = 0.004 * parent * np.sin(2 * np.pi * x) ** 2
        data["tag_origin_a"][1:] += shift[1:]
        data["tag_origin_b"][1:] -= shift[1:]
        data["tag_overlay"][1:] *= 1.0 + 0.03 * (1.0 + x)
        data["tag_tiny"][1:] += 3e-5 * parent[1:] * x
        data["tag_zero"][1:] += 4e-4 * parent[1:] * x
        np.savez(path, **data)
        value = json.loads(manifest.read_text())
        value["acceptance"]["artifacts"][path.name] = sha256_file(path)
        write_json(manifest, value)
        cls.bundle = Bundle(manifest)
        design = load_design()
        cls.design = design
        truth = analytic(design, case_by_id(design, "smooth_positive"), 16)
        cls.candidate = read_native(cls.bundle, "candidate", truth)
        cls.reference = read_native(cls.bundle, "reference", truth)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def test_reference_rows_equal_scorer_profile(self):
        verdicts = set()
        for time in (FIRST_HOUR, DAY):
            for tag in self.design["tags"]:
                with self.subTest(tag=tag["name"], time=time):
                    scored = Scorer(self.bundle).profile(tag, time)
                    ours = profile_error(self.candidate, self.reference, "tag_" + tag["name"], int(time), tag["kind"])
                    metrics = scored["metrics"]
                    self.assertGreater(ours["absolute_L1_kg_m2"], 0)
                    np.testing.assert_allclose(ours["absolute_L1_kg_m2"], metrics["absolute_L1"], rtol=1e-12)
                    np.testing.assert_allclose(ours["reference_share"], metrics["reference_share"], rtol=1e-12)
                    self.assertEqual(ours["meets"], scored["meets"])
                    self.assertEqual(ours["small_rule"], "small_absolute_limit" in metrics)
                    fractions = ours["fraction_of_tolerance"]
                    if ours["small_rule"]:
                        np.testing.assert_allclose(fractions["absolute_L1"],
                                                   metrics["absolute_L1"] / metrics["small_absolute_limit"], rtol=1e-12)
                    else:
                        l1_limit, linf_limit = score_acceptance.origin_limits(tag["kind"], time)
                        np.testing.assert_allclose(ours["relative_L1"], metrics["L1"], rtol=1e-12)
                        np.testing.assert_allclose(ours["specific_Linf"], metrics["Linf"], rtol=1e-12)
                        np.testing.assert_allclose(fractions["L1"], metrics["L1"] / l1_limit, rtol=1e-12)
                        np.testing.assert_allclose(fractions["Linf"], metrics["Linf"] / linf_limit, rtol=1e-12)
                    verdicts.add((ours["small_rule"], ours["meets"]))
        # The perturbation reaches the relative and the small rule, passing and failing.
        self.assertEqual(verdicts, {(False, True), (False, False), (True, True), (True, False)})


class DriverExitTests(unittest.TestCase):
    """The driver's exit codes follow the scorer's convention."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.config = json.loads((Path(__file__).parents[2] / "configs" /
                                  "water_transport_known_answers.json").read_text())

    def tearDown(self):
        self.scratch.cleanup()

    def main(self, *args):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return driver.main([str(arg) for arg in args])

    def test_exit_code_of_suite_rows(self):
        passing = {"candidate_verdict": "PASS", "origin_swap_verified": True, "reference_eligible": True}
        self.assertEqual(suite_exit_code([passing]), 0)
        self.assertEqual(suite_exit_code([passing, {**passing, "candidate_verdict": "NOT ASSESSABLE",
                                                    "origin_swap_verified": None, "reference_eligible": False}]), 3)
        self.assertEqual(suite_exit_code([passing, {**passing, "candidate_verdict": "FAIL"}]), 1)
        self.assertEqual(suite_exit_code([{**passing, "origin_swap_verified": False}]), 1)

    def test_main_maps_failures_to_the_scorer_codes(self):
        config = self.root / "config.json"
        write_json(config, {**self.config, "design_sha256": "0" * 64})
        self.assertEqual(self.main(self.root / "bad_config", "--config", config), 2)
        self.assertEqual(self.main(self.root / "missing_config", "--config", self.root / "absent.json"), 2)
        self.assertEqual(self.main(self.root, "--config", config), 4)
        self.assertEqual(self.main(self.root / "no_option"), 4)
        with mock.patch.object(driver, "run_suite", side_effect=RuntimeError("driver bug")):
            self.assertEqual(self.main(self.root / "driver_error", "--config", config), 4)
        with mock.patch.object(driver, "run_suite", return_value={"exit_code": 3}):
            self.assertEqual(self.main(self.root / "ineligible", "--config", config), 3)

    def test_complete_suites_through_main(self):
        config = self.root / "analytic.json"
        write_json(config, self.config)
        self.assertEqual(self.main(self.root / "analytic", "--config", config), 0)
        report = json.loads((self.root / "analytic" / "suite_results.json").read_text())
        self.assertEqual([row["case_id"] for row in report["cases"]], list(CASE_IDS))
        self.assertTrue(all(row["reference_eligible"] and row["origin_swap_verified"] for row in report["cases"]))
        numerical_config = self.root / "numerical.json"
        write_json(numerical_config, json.loads((Path(__file__).parents[2] / "configs" /
                                                 "water_transport_numerical_fixture.json").read_text()))
        self.assertEqual(self.main(self.root / "numerical", "--config", numerical_config), 3)
        report = json.loads((self.root / "numerical" / "suite_results.json").read_text())
        self.assertEqual([row["reference_eligible"] for row in report["cases"]], [False, False, False, False, True])


if __name__ == "__main__":
    unittest.main()
