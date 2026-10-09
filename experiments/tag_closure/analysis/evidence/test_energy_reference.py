"""Energy known answers, the eight registered wrong-origin mutants and the suite driver."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

import score_acceptance
from acceptance_data import DataError
from energy_reference import _radiation_continuum
from energy_reference import (DESIGN_SHA256, activity_report, analytic, case_by_id, classify, evaluate_candidate,
                              load_design, mutant, numerical, stage_record, stage_reference, window_amount)
from energy_reference_adapter import (LADDER_TIE, candidate_for, evaluate_energy_reference, reference_for,
                                      rungs)
from make_energy_reference_fixture import (evaluate_fixture, main, mutant_caught, suite_exit_code,
                                           write_fixture, write_json)

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
        self.assertEqual(offsets["heating_labels"], 110495.0)
        self.assertEqual(offsets["donor_cooling"], 274388.0)
        self.assertEqual(offsets["offset_change"], [110495.0, 220990.0])
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

    def test_unassessable_rows_never_pass(self):
        # Finder 2.1: a wrong cooling overlay sits only in unassessable rows.
        c = case("opposing_net_zero")
        reference, candidate = reference_for(DESIGN, c), candidate_for(DESIGN, c)
        moved = 0.001 * candidate.values["E_c"][1]
        candidate.values["tag_src_cool"][1] += moved
        candidate.values["tag_src_heat"][1] -= moved
        self.assertIsNone(evaluate_candidate(DESIGN, c, candidate, reference)["meets"])
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
                values["E_c"] = values["rho_e"] + 110495.0 * (values["rho"][0] + values["rho_q"] - values["rho_q"][0])
            else:
                values["E_c"] = values["rho_e"] + 110495.0 * values["rho"][0]
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


class FixtureTests(unittest.TestCase):
    def test_fixture_declares_eligibility_and_refuses_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = write_fixture(Path(tmp) / "f", "labelled_exchange")
            result = evaluate_fixture(root)
            self.assertTrue(result["measured_reference"]["meets"] and result["mutant"]["caught"])
            detail = json.loads((root / "evidence.json").read_text())
            self.assertEqual(detail["planning_commit"], "9e5155325b6d778ca558b6dd2c6651006add0a80")
            self.assertEqual(detail["approved_numbers_sha256"], score_acceptance.approved_numbers_sha256())
            self.assertEqual(detail["convention"]["c_J_kg"], 110495.0)
            self.assertEqual(detail["rungs"], rungs(case("labelled_exchange")))
            for key, value in (("convention", {**detail["convention"], "c_J_kg": 220990.0}),
                               ("floors", {**detail["floors"], "reference_discretization": 0.0})):
                changed = {**detail, key: value}
                write_json(root / "evidence.json", changed)
                with self.assertRaises(DataError):
                    evaluate_energy_reference(root)
            write_json(root / "evidence.json", detail)
            evaluate_energy_reference(root)

    def test_exit_codes(self):
        row = {"candidate_verdict": "PASS", "mutant_caught": True, "reference_eligible": True}
        self.assertEqual(suite_exit_code([row]), 0)
        self.assertEqual(suite_exit_code([{**row, "mutant_caught": False}]), 1)
        self.assertEqual(suite_exit_code([{**row, "candidate_verdict": "FAIL"}]), 1)
        self.assertEqual(suite_exit_code([{**row, "reference_eligible": False}]), 3)
        self.assertEqual(suite_exit_code([{**row, "candidate_verdict": "NOT ASSESSABLE"}]), 3)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(main([tmp, "--config", str(CONFIG)]), 4)
            bad = Path(tmp) / "bad.json"
            bad.write_text("{}")
            self.assertEqual(main([str(Path(tmp) / "new"), "--config", str(bad)]), 2)

    def test_complete_suite_exits_three_with_one_unassessable_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(main([str(Path(tmp) / "suite"), "--config", str(CONFIG)]), 3)
            report = json.loads((Path(tmp) / "suite" / "suite_results.json").read_text())
            verdicts = {row["case_id"]: row["candidate_verdict"] for row in report["cases"]}
            self.assertEqual(verdicts.pop("opposing_net_zero"), "NOT ASSESSABLE")
            self.assertEqual(set(verdicts.values()), {"PASS"})
            self.assertTrue(all(row["mutant_caught"] and row["reference_eligible"] for row in report["cases"]))


if __name__ == "__main__":
    unittest.main()
