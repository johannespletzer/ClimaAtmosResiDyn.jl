"""Energy known answers, the eight registered wrong-origin mutants and the suite driver."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

import score_acceptance
from acceptance_data import DataError
from energy_reference import _match, _radiation_continuum
from energy_reference import (BASE_COMMIT, DESIGN_SHA256, MODEL_COMMIT, EnergyState, origin_row, share, theta_x, activity_report, analytic, case_by_id, classify, evaluate_candidate,
                              load_design, mutant, numerical, stage_record, stage_reference, window_amount)
from energy_reference_adapter import (LADDER_TIE, RULES, candidate_for, converges, declaration, eligible,
                                      evaluate_energy_reference, load_state, measure, reference_for, rungs)
from make_energy_reference_fixture import (evaluate_fixture, main, mutant_caught, suite_exit_code,
                                           unassessable_against_design, write_fixture, write_json)

DESIGN = load_design()
CONFIG = Path(__file__).resolve().parents[2] / "configs" / "energy_reference_known_answers.json"


def case(case_id):
    return case_by_id(DESIGN, case_id)


class ConstantTests(unittest.TestCase):
    def test_design_restates_the_scorers_numbers(self):
        rules = DESIGN["profile_rules"]
        self.assertEqual(rules["day_L1"], score_acceptance.ORIGIN_L1_DAY)
        self.assertEqual(rules["day_Linf"], score_acceptance.ORIGIN_LINF_DAY)
        self.assertEqual(rules["first_hour_region_L1"], score_acceptance.ORIGIN_L1_FIRST_HOUR["region"])
        self.assertEqual(rules["first_hour_source_L1"], score_acceptance.ORIGIN_L1_FIRST_HOUR["source"])
        self.assertEqual(rules["first_hour_Linf"], score_acceptance.ORIGIN_LINF_FIRST_HOUR)
        self.assertEqual(rules["small_share_below"], score_acceptance.SMALL_SHARE)
        self.assertEqual(rules["small_absolute_theta_x_fraction"], score_acceptance.SMALL)
        self.assertEqual(rules["floor_max_fraction_of_tolerance"], score_acceptance.FLOOR_FRACTION_MAX)
        self.assertEqual(rules["ladder_tie"], score_acceptance.SECOND_HALF_TIE)
        self.assertEqual(LADDER_TIE, score_acceptance.SECOND_HALF_TIE)
        self.assertEqual(json.loads(CONFIG.read_text())["design_sha256"], DESIGN_SHA256)

    def test_each_case_declares_and_freezes_its_convention(self):
        offsets = {c["id"]: c["convention"]["c_J_kg"] for c in DESIGN["cases"]}
        self.assertTrue(all(c["convention"]["frozen"] is True for c in DESIGN["cases"]))
        self.assertEqual(offsets["heating_labels"], 166764.0)
        self.assertEqual(offsets["donor_cooling"], 274389.0)
        self.assertEqual(offsets["offset_change"], [166764.0, 333528.0])
        # The mass source changes sign in E_c between c and 2c (the case's identity).
        oc = case("offset_change")
        self.assertEqual([np.sign(np.add(oc["energy_source_J_m3_s"], c * np.array(oc["mass_source_kg_m3_s"]))).tolist()
                          for c in offsets["offset_change"]], [[-1.0, -1.0], [1.0, 1.0]])
        self.assertIsNone(offsets["radiation_record"])
        self.assertEqual([c["family"] for c in DESIGN["cases"]].count("radiation_record"), 1)


class MutantTests(unittest.TestCase):
    """Every case: the exact candidate passes, the registered mutant is caught with its invariants kept."""

    def check(self, case_id, failing, exact=True):
        c = case(case_id)
        reference, candidate = reference_for(DESIGN, c), candidate_for(DESIGN, c)
        self.assertIs(evaluate_candidate(DESIGN, c, candidate, reference)["meets"], exact)
        result = evaluate_candidate(DESIGN, c, mutant(DESIGN, c, candidate), reference)
        self.assertTrue(mutant_caught(c, result))
        self.assertFalse(result["checks"][failing])

    def test_heating_swapped_overlays(self):
        self.check("heating_labels", "origins")

    def test_cooling_charged_to_the_cooling_tag_alone(self):
        self.check("donor_cooling", "origins")

    def test_exchange_receiver_donor_closes_exactly(self):
        self.check("labelled_exchange", "origins")

    def test_boundary_water_donor_for_negative_energy(self):
        self.check("boundary_offset_exchange", "origins")

    def test_opposing_processes_collapsed_first(self):
        # Three small overlay rows have zero Theta_x, so the exact candidate is
        # NOT ASSESSABLE there (finder 2.1). The mutant still fails an assessed row.
        self.check("opposing_net_zero", "origins", exact=None)
        c = case("opposing_net_zero")
        result = evaluate_candidate(DESIGN, c, candidate_for(DESIGN, c), reference_for(DESIGN, c))
        self.assertEqual([(r["tag"], r["endpoint_seconds"]) for r in result["not_assessable_rows"]],
                         [("src_heat", 3600.0), ("src_cool", 3600.0), ("src_cool", 86400.0)])
        # The design lists exactly these rows (decision of 2026-10-09).
        self.assertEqual(unassessable_against_design(c, result["not_assessable_rows"]), ([], []))
        self.assertIs(result["checks"]["no_gain_path_zero"], True)

    def test_no_gain_path_tag_reading_nonzero_fails(self):
        # src_cool has no gain path. A nonzero reading fails the fixture's zero
        # check although its scorer rows stay NOT ASSESSABLE.
        c = case("opposing_net_zero")
        reference, candidate = reference_for(DESIGN, c), candidate_for(DESIGN, c)
        candidate.values["tag_src_cool"][2] += 1e-300
        result = evaluate_candidate(DESIGN, c, candidate, reference)
        self.assertIs(result["checks"]["no_gain_path_zero"], False)
        self.assertIs(result["meets"], False)
        self.assertEqual(unassessable_against_design(c, result["not_assessable_rows"]), ([], []))

    def test_unlisted_unassessable_row_exits_three(self):
        # A one-ulp density defect at one day makes rows the design does not list.
        c = case("opposing_net_zero")
        reference, candidate = reference_for(DESIGN, c), candidate_for(DESIGN, c)
        candidate.values["rho"][2] = np.nextafter(candidate.values["rho"][2], 0.0)
        result = evaluate_candidate(DESIGN, c, candidate, reference)
        self.assertIsNone(result["meets"])
        unlisted, unrealized = unassessable_against_design(c, result["not_assessable_rows"])
        self.assertIn(("lower", 86400.0, "same-parent density required"), unlisted)
        self.assertEqual(unrealized, [("src_cool", 86400.0, "small tag with zero Theta_x")])
        row = {"candidate_verdict": "NOT ASSESSABLE", "mutant_caught": True, "reference_eligible": True,
               "not_assessable_as_declared": False}
        self.assertEqual(suite_exit_code([row]), 3)
        self.assertEqual(suite_exit_code([{**row, "not_assessable_as_declared": True}]), 0)

    def test_unassessable_rows_never_pass(self):
        # Finder 2.1: a wrong cooling overlay sits only in unassessable rows.
        c = case("opposing_net_zero")
        reference, candidate = reference_for(DESIGN, c), candidate_for(DESIGN, c)
        moved = 0.001 * candidate.values["E_c"][1]
        candidate.values["tag_src_cool"][1] += moved
        candidate.values["tag_src_heat"][1] -= moved
        # The rows stay NOT ASSESSABLE. The zero check of 2026-10-09 fails the move.
        result = evaluate_candidate(DESIGN, c, candidate, reference)
        self.assertEqual([(r["tag"], r["endpoint_seconds"]) for r in result["not_assessable_rows"]],
                         [("src_heat", 3600.0), ("src_cool", 3600.0), ("src_cool", 86400.0)])
        self.assertIs(result["meets"], False)
        candidate.values["tag_src_cool"] = 0.05 * candidate.values["E_c"]
        self.assertFalse(evaluate_candidate(DESIGN, c, candidate, reference)["checks"]["overlay_sum"])
        # A one-ulp density change makes every origin row unassessable. The mutant must not pass.
        for case_id in ("heating_labels", "donor_cooling", "labelled_exchange", "boundary_offset_exchange"):
            c = case(case_id)
            reference = reference_for(DESIGN, c)
            wrong = mutant(DESIGN, c, candidate_for(DESIGN, c))
            wrong.values["rho"] = np.nextafter(wrong.values["rho"], np.inf)
            result = evaluate_candidate(DESIGN, c, wrong, reference)
            # Unassessable rows alone never pass. Other checks may still fail it.
            self.assertIsNot(result["meets"], True, case_id)
            self.assertTrue(all(row["meets"] is None for row in result["origin_rows"]))

    def test_offset_change_invariant_fractions(self):
        self.check("offset_change", "origins")

    def test_inventory_epsilon_denominator(self):
        self.check("inventory_edge_cases", "classification")

    def test_radiation_wrong_sign(self):
        self.check("radiation_record", "record")


class EquationTests(unittest.TestCase):
    def test_closed_form_and_steps_agree_within_the_ladder(self):
        for c in DESIGN["cases"]:
            if c["kind"] in ("admissibility", "radiation_record"):
                continue
            truth, stepped = analytic(DESIGN, c), numerical(DESIGN, c, min(c["dt_seconds"]))
            for name, value in truth.values.items():
                scale = max(float(np.max(np.abs(value))), 1.0)
                self.assertLess(np.max(np.abs(stepped.values[name] - value)) / scale, 1e-3, (c["id"], name))

    def test_boundary_mass_is_not_water_and_offset_flux_is_required(self):
        c = case("boundary_offset_exchange")
        truth = analytic(DESIGN, c)
        self.assertFalse(np.allclose(truth.values["rho_q"][-1] - truth.values["rho_q"][0],
                                     truth.values["rho"][-1] - truth.values["rho"][0]))
        for wrong in ("water", "no_offset"):
            values = {k: v.copy() for k, v in truth.values.items()}
            if wrong == "water":
                values["E_c"] = values["rho_e"] + 166764.0 * (values["rho"][0] + values["rho_q"] - values["rho_q"][0])
            else:
                values["E_c"] = values["rho_e"] + 166764.0 * values["rho"][0]
            state = type(truth)(truth.time, truth.dz, values, {})
            self.assertFalse(evaluate_candidate(DESIGN, c, state, truth)["checks"]["convention_identity"])

    def test_opposing_activity_theta_x_and_theta_i_differ(self):
        c = case("opposing_net_zero")
        report = activity_report(DESIGN, c, analytic(DESIGN, c), 3600, 86400)
        self.assertEqual(report["theta_x"], 0.0)
        self.assertGreater(report["application_activity"], 0.0)
        self.assertAlmostEqual(report["theta_i"] / report["application_activity"], 1.0, places=12)
        stepped = numerical(DESIGN, c, 30)
        self.assertLess(stepped.diagnostics["theta_x_whole_run"],
                        1e-9 * stepped.diagnostics["application_activity_whole_run"])

    def test_offset_parent_is_bitwise_identical_and_a_changed_parent_fails(self):
        c = case("offset_change")
        truth = analytic(DESIGN, c)
        values = {k: v.copy() for k, v in truth.values.items()}
        values["rho_e@1"][-1, 0] = np.nextafter(values["rho_e@1"][-1, 0], np.inf)
        state = type(truth)(truth.time, truth.dz, values, {})
        self.assertFalse(evaluate_candidate(DESIGN, c, state, truth)["checks"]["parent_bitwise_parity"])

    def test_inventory_wrong_readings_are_caught(self):
        c = case("inventory_edge_cases")
        reference = classify(c)
        self.assertEqual(reference.values["status"][0].tolist(), [0, 1, 2, 0, 0, 0])
        self.assertEqual(reference.values["share_region_a"][0, 1:3].tolist(), [0.0, 0.0])
        accounting = reference.diagnostics["corrections"]
        self.assertEqual((accounting["signed_change"], accounting["retained_variation"]), (0.0, 0.0))
        self.assertEqual(accounting["application_activity"], 700.0)
        self.assertEqual(reference.diagnostics["restart"]["gross"], 6.0)
        result = evaluate_candidate(DESIGN, c, classify(c, duplicate_restart=True), reference)
        self.assertFalse(result["checks"]["accounting"])
        # A region with nonpositive signed inventory never passes on its absolute burden.
        signed = copy.deepcopy(c)
        signed["tag_values_J_m3"]["region_a"] = [-1000.0, 0.0, 0.0, -100.0, 500.0, 0.0]
        result = evaluate_candidate(DESIGN, signed, classify(signed, burden_for_regions=True), classify(signed))
        self.assertFalse(result["checks"]["inventory"])
        self.assertFalse(classify(signed).diagnostics["inventory"]["region_a"]["positive_inventory_precondition"])

    def test_radiation_stage_weight_transport_and_specific_differencing_are_caught(self):
        c = case("radiation_record")
        reference = stage_reference(DESIGN, c, 60)
        omitted = stage_record(DESIGN, c, 60, weights=[1.0, 0.0])
        self.assertFalse(evaluate_candidate(DESIGN, c, omitted, reference)["checks"]["record"])
        moved = stage_record(DESIGN, c, 60)
        moved.values["prc_radiation"] = np.roll(moved.values["prc_radiation"], 1, axis=1)
        moved.values["e_prc_radiation"] = moved.values["prc_radiation"] / moved.values["rho"]
        self.assertFalse(evaluate_candidate(DESIGN, c, moved, reference)["checks"]["record"])
        right, wrong = window_amount(reference, 1, 2), window_amount(reference, 1, 2, "specific_difference")
        self.assertGreater(np.max(np.abs(wrong - right)), 1e-6 * np.max(np.abs(right)))


class RecordAndInvariantTests(unittest.TestCase):
    def test_continuum_record_is_pinned_by_hand(self):
        # Finder 2.2. -D_z F of F = 10 + 70 (z/H)^2 on 125 m cells, times the time integral.
        c = case("radiation_record")
        P = _radiation_continuum(DESIGN, c).values["prc_radiation"]
        omega = 2.0 * np.pi / 86400.0
        self.assertAlmostEqual(P[2, 0], -756.0, places=9)
        self.assertAlmostEqual(P[2, 7], -11340.0, places=8)
        self.assertAlmostEqual(P[1, 0], -0.00875 * (3600.0 + 0.3 * (1.0 - np.cos(np.pi / 12.0)) / omega), places=9)
        errors = [float(np.max(np.abs(stage_reference(DESIGN, c, dt).values["prc_radiation"][1] - P[1])))
                  for dt in (240, 120, 60)]
        self.assertTrue(all(3.9 < a / b < 4.1 for a, b in zip(errors, errors[1:])), errors)
        flipped = stage_record(DESIGN, c, 60, sign=-1.0)
        self.assertFalse(evaluate_candidate(DESIGN, c, flipped, stage_reference(DESIGN, c, 60))["checks"]["record_sign"])

    def test_mutant_caught_checks_every_declared_invariant(self):
        # Finder 2.3.
        c = case("heating_labels")
        result = evaluate_candidate(DESIGN, c, mutant(DESIGN, c, candidate_for(DESIGN, c)), reference_for(DESIGN, c))
        self.assertTrue(mutant_caught(c, result) and result["checks"]["overlay_sum"])
        for name in ("overlay_sum", "parent", "partition_closure"):
            self.assertFalse(mutant_caught(c, {**result, "checks": {**result["checks"], name: False}}), name)
        exchange = case("labelled_exchange")
        moved = evaluate_candidate(DESIGN, exchange, mutant(DESIGN, exchange, candidate_for(DESIGN, exchange)),
                                   reference_for(DESIGN, exchange))
        for c, result, preserves in ((c, result, ["unknown"]), (exchange, moved, ["records"])):
            with self.assertRaises(DataError):
                mutant_caught({**c, "mutant": {**c["mutant"], "preserves": preserves}}, result)


class ThresholdTests(unittest.TestCase):
    """Finder 1.5: every number the module reads, pinned where it is used."""

    def test_pinned_constants(self):
        self.assertEqual((BASE_COMMIT, MODEL_COMMIT), ("ddbafbbfe2434a39b823eb76cde9de89114016cc",
                                                      "bb2bedf230a70ca9d7afc293180f8d30c1a9bb88"))
        self.assertEqual(DESIGN["times_seconds"], [0, 3600, 86400])
        self.assertEqual(DESIGN["profile_rules"]["roundoff_multiplier"], 128)
        self.assertEqual({c["id"]: c["convention"]["c_J_kg"] for c in DESIGN["cases"]}, {
            "heating_labels": 166764.0, "donor_cooling": 274389.0, "labelled_exchange": 166764.0,
            "boundary_offset_exchange": 166764.0, "opposing_net_zero": 166764.0,
            "offset_change": [166764.0, 333528.0], "inventory_edge_cases": 166764.0, "radiation_record": None})
        self.assertEqual(RULES, {
            "heating_labels": "declared_source_allocation", "donor_cooling": "donor_loss_allocation",
            "reservoir_exchange": "donor_transport_share", "falling_mass_boundary": "offset_boundary_flux",
            "opposing_net_zero": "sequential_event_allocation", "offset_change": "fixed_offset_representation",
            "admissibility": "share_admissibility", "radiation_record": "radiation_divergence"})

    def test_roundoff_allowance_tie_and_floor_limit(self):
        b = np.full(3, 1.0e5)
        eps = np.finfo(np.float64).eps
        self.assertTrue(_match(DESIGN, b * (1 + 2 * eps), b))
        self.assertFalse(_match(DESIGN, b * (1 + 200 * eps), b))
        self.assertFalse(_match(DESIGN, b * (1 + 1e-9), b))
        self.assertTrue(converges([1.0, 1.0 + 1e-13, 0.5]))
        self.assertFalse(converges([1.0, 1.0 + 2e-12]))
        declared = {"converged": None, "mirrors_complete": True, "jacobian_complete": True,
                    "independent_rules": ["declared_source_allocation"]}
        stored = case("heating_labels")
        self.assertTrue(eligible(stored, {**declared, "floors": {"a": 0.25, "b": 0.0}}))
        for value in (0.2500001, -1e-12):
            self.assertFalse(eligible(stored, {**declared, "floors": {"a": value}}), value)
        # A closed form that claims convergence from a cross-check ladder is refused.
        self.assertFalse(eligible(stored, {**declared, "converged": True, "floors": {"a": 0.0}}))
        self.assertFalse(eligible(case("radiation_record"), {**declared, "floors": {}}))
        self.assertTrue(eligible(case("radiation_record"), {**declared, "converged": True, "floors": {},
                                                            "independent_rules": ["radiation_divergence"]}))

    def test_declared_converged_follows_its_basis(self):
        """R9: a closed form's ladder is a cross-check, so it claims no convergence."""
        for c in DESIGN["cases"]:
            declared = declaration(DESIGN, c, measure(DESIGN, c))
            basis = declared["eligibility_basis"]["converged"]
            if c["kind"] == "radiation_record":
                self.assertIs(declared["converged"], True, c["id"])
                self.assertTrue(basis.startswith("Measured. The floor does not rise"), c["id"])
            else:
                self.assertIsNone(declared["converged"], c["id"])
                self.assertTrue(basis.startswith("Inapplicable."), c["id"])

    def test_theta_x_and_shares(self):
        self.assertEqual(theta_x(DESIGN, case("heating_labels"), 0.0, 3600.0), 504000.0)
        offset = copy.deepcopy(case("offset_change"))
        offset["mass_source_kg_m3_s"] = [3e-7, 1e-7]
        expected = 100.0 * (abs(-0.0500292 + 333528.0 * 3e-7) + abs(-0.0250146 + 333528.0 * 1e-7)) * 3600.0
        self.assertAlmostEqual(theta_x(DESIGN, offset, 0.0, 3600.0, 1), expected, places=6)
        self.assertEqual(share([2.0, -1.0, 1.0, 1.0], [1.0, 1.0, 0.0, -1.0]).tolist(), [1.0, 0.0, 0.0, 0.0])
        edge = copy.deepcopy(case("inventory_edge_cases"))
        for fraction, small in ((0.009, True), (0.011, False)):
            edge["tag_values_J_m3"]["overlay"] = [fraction * 52198000.0 / 600.0] * 6
            self.assertIs(classify(edge).diagnostics["inventory"]["overlay"]["small"], small, fraction)

    def test_origin_row_rules(self):
        c = case("heating_labels")
        reference = reference_for(DESIGN, c)
        tags = {t["name"]: t for t in c["tags"]}
        # The small-tag rule: SMALL x Theta_x(0, 1 h) = 100.8 J m^-2.
        for factor, verdict in ((0.9, "PASS"), (1.1, "FAIL")):
            wrong = candidate_for(DESIGN, c)
            wrong.values["tag_src_a"][1, 0] += factor * 100.8 / 100.0
            self.assertEqual(origin_row(wrong, reference, DESIGN, c, tags["src_a"], 1)["verdict"], verdict)
        # A region tag reads the region limit: 5% L1 at 1 h fails.
        wrong = candidate_for(DESIGN, c)
        wrong.values["tag_lower"][1] *= 1.05
        self.assertEqual(origin_row(wrong, reference, DESIGN, c, tags["lower"], 1)["verdict"], "FAIL")
        # The L-infinity test: L1 1.5% passes, L-infinity 15% fails at one day.
        synthetic = {"kind": "admissibility", "tags": [{"name": "r", "kind": "region", "partition": True}]}
        ones = np.ones((2, 10))
        truth = EnergyState(np.array([0.0, 86400.0]), np.ones(10), {"rho": ones, "tag_r": ones.copy()}, {})
        wrong = EnergyState(truth.time, truth.dz, {"rho": ones, "tag_r": ones.copy()}, {})
        wrong.values["tag_r"][1, 0] += 0.15
        row = origin_row(wrong, truth, DESIGN, synthetic, synthetic["tags"][0], 1)
        self.assertEqual((row["verdict"], round(row["L1"], 12)), ("FAIL", 0.015))
        truth.values["tag_r"][1, 3] = -0.5
        self.assertEqual(origin_row(wrong, truth, DESIGN, synthetic, synthetic["tags"][0], 1)["verdict"],
                         "NOT ASSESSABLE")


class IntegrityTests(unittest.TestCase):
    """Finder 5.1: every integrity pin of a fixture refuses a change."""

    def test_every_pin_refuses_a_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = write_fixture(Path(tmp) / "f", "labelled_exchange")
            detail = json.loads((root / "evidence.json").read_text())
            for key, value in (("planning_commit", "0" * 40), ("model_commit", "0" * 40),
                               ("approved_numbers_sha256", "0" * 64), ("design_sha256", "0" * 64),
                               ("evaluator_files", {**detail["evaluator_files"], "energy_reference.py": "0" * 64}),
                               ("artifacts", {**detail["artifacts"], "mutant.npz": "0" * 64})):
                write_json(root / "evidence.json", {**detail, key: value})
                with self.assertRaises(DataError, msg=key):
                    evaluate_energy_reference(root)
            write_json(root / "evidence.json", detail)
            design = (root / detail["design"]).read_bytes()
            (root / detail["design"]).write_bytes(design.replace(b'"precision": "Float64"', b'"precision": "Float32"'))
            with self.assertRaises(DataError):
                evaluate_energy_reference(root)
            (root / detail["design"]).write_bytes(design)
            with np.load(root / "candidate.npz") as raw:
                original = {k: raw[k].copy() for k in raw.files}
            roster = [k for k in original if k.startswith("excluded_activity__")]
            first = "field__" + next(n for n in reference_for(DESIGN, case("labelled_exchange")).values)
            for name, edit in (("roster", lambda d: d.pop(roster[0])),
                               ("activity", lambda d: d[roster[0]].__setitem__((1, 0), 1e-30)),
                               ("initial", lambda d: d[first].__setitem__((0, 0), d[first][0, 0] * (1 + 1e-9)))):
                data = {k: v.copy() for k, v in original.items()}
                edit(data)
                np.savez(root / "edited.npz", **data)
                with self.assertRaises(DataError, msg=name):
                    evaluate_energy_reference(root, candidate_name="edited.npz")
            np.savez(root / "edited.npz", **original)
            self.assertTrue(evaluate_energy_reference(root, candidate_name="edited.npz")["candidate"]["meets"])


class FixtureTests(unittest.TestCase):
    def test_fixture_declares_eligibility_and_refuses_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = write_fixture(Path(tmp) / "f", "labelled_exchange")
            result = evaluate_fixture(root)
            self.assertTrue(result["measured_reference"]["meets"] and result["mutant"]["caught"])
            detail = json.loads((root / "evidence.json").read_text())
            self.assertEqual(detail["planning_commit"], "ddbafbbfe2434a39b823eb76cde9de89114016cc")
            self.assertEqual(detail["approved_numbers_sha256"], score_acceptance.approved_numbers_sha256())
            self.assertEqual(detail["convention"]["c_J_kg"], 166764.0)
            self.assertEqual(detail["rungs"], rungs(case("labelled_exchange")))
            self.assertEqual(detail["theta_x_window"]["start_seconds"], 0.0)
            for key, value in (("convention", {**detail["convention"], "c_J_kg": 333528.0}),
                               ("theta_x_window", {**detail["theta_x_window"], "start_seconds": 1800.0}),
                               ("theta_x_window", None),
                               ("floors", {**detail["floors"], "reference_discretization": 0.0})):
                changed = {**detail, key: value}
                if value is None:
                    changed.pop(key)
                write_json(root / "evidence.json", changed)
                with self.assertRaises(DataError, msg=key):
                    evaluate_energy_reference(root)
            write_json(root / "evidence.json", detail)
            evaluate_energy_reference(root)

    def test_theta_x_window_is_declared_and_read(self):
        """Challenge E: the small-tag rule reads the frozen window, and a case without one is refused."""
        self.assertTrue(all(c["theta_x_window"] == {**c["theta_x_window"], "start_seconds": 0.0, "end": "endpoint",
                                                    "frozen": True} for c in DESIGN["cases"]))
        c = case("heating_labels")
        truth = analytic(DESIGN, c)
        small = [(t, j) for t in c["tags"] for j in range(1, len(truth.time))
                 if "absolute_L1" in origin_row(truth, truth, DESIGN, c, t, j).get("fraction_of_tolerance", {})]
        self.assertTrue(small, "the test needs a small-tag row")
        tag, j = small[0]
        for window in (None, {**c["theta_x_window"], "frozen": False}, {**c["theta_x_window"], "end": 3600.0}):
            edited = copy.deepcopy(c)
            if window is None:
                edited.pop("theta_x_window")
            else:
                edited["theta_x_window"] = window
            with self.assertRaises(DataError, msg=str(window)):
                origin_row(truth, truth, DESIGN, edited, tag, j)

    def test_exit_codes(self):
        row = {"candidate_verdict": "PASS", "mutant_caught": True, "reference_eligible": True}
        self.assertEqual(suite_exit_code([row]), 0)
        self.assertEqual(suite_exit_code([{**row, "mutant_caught": False}]), 1)
        self.assertEqual(suite_exit_code([{**row, "candidate_verdict": "FAIL"}]), 1)
        self.assertEqual(suite_exit_code([{**row, "reference_eligible": False}]), 3)
        self.assertEqual(suite_exit_code([{**row, "candidate_verdict": "NOT ASSESSABLE"}]), 3)
        listed = {**row, "candidate_verdict": "NOT ASSESSABLE", "not_assessable_as_declared": True}
        self.assertEqual(suite_exit_code([listed]), 0)
        self.assertEqual(suite_exit_code([{**listed, "reference_eligible": False}]), 3)
        self.assertEqual(suite_exit_code([{**listed, "mutant_caught": False}]), 1)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(main([tmp, "--config", str(CONFIG)]), 4)
            bad = Path(tmp) / "bad.json"
            bad.write_text("{}")
            self.assertEqual(main([str(Path(tmp) / "new"), "--config", str(bad)]), 2)

    def test_complete_suite_exits_zero_with_only_the_listed_unassessable_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(main([str(Path(tmp) / "suite"), "--config", str(CONFIG)]), 0)
            report = json.loads((Path(tmp) / "suite" / "suite_results.json").read_text())
            self.assertEqual(report["exit_code"], 0)
            declared = {row["case_id"]: row["not_assessable_as_declared"] for row in report["cases"]}
            self.assertIs(declared.pop("opposing_net_zero"), True)
            self.assertFalse(any(declared.values()))
            verdicts = {row["case_id"]: row["candidate_verdict"] for row in report["cases"]}
            self.assertEqual(verdicts.pop("opposing_net_zero"), "NOT ASSESSABLE")
            self.assertEqual(set(verdicts.values()), {"PASS"})
            self.assertTrue(all(row["mutant_caught"] and row["reference_eligible"] for row in report["cases"]))


if __name__ == "__main__":
    unittest.main()
