"""Hand-derived cancellation, acceptance, native and pairing counterexamples.

    python3 -m unittest discover -s experiments/tag_closure/analysis/evidence -p test_correction_accounting.py -v

These tests supply no model runtime or physical restart/parity evidence.
"""

import contextlib
import copy
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from acceptance_data import Bundle, DataError, Field, stitch
import correction_accounting
from correction_accounting import (HALF_QUANTUM, LEDGER_EXTRA_OPERATIONS, ROUNDING_ULPS, TAG_EVENT_THRESHOLD,
                                   TAG_EVENT_ULPS, TRANSFER_OPERATIONS, application_activity, close,
                                   evaluate_accounting, paired_precipitation, rounding_allowance)
from make_acceptance_fixture import write_fixture
from make_correction_fixture import attach_fixture
from manifest import sha256_file
from score_acceptance import Scorer, local_identities, main


class CorrectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "water"
        self.manifest = write_fixture(self.root)
        attach_fixture(self.manifest)

    def tearDown(self):
        self.temp.cleanup()

    def spec(self, action):
        data = json.loads(self.manifest.read_text())
        action(data["acceptance"])
        data["acceptance"].update(local_identities())
        self.manifest.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")

    def file(self, name, action):
        path = self.root / name
        if path.suffix == ".npz":
            with np.load(path, allow_pickle=False) as archive:
                value = {k: archive[k].copy() for k in archive.files}
            action(value)
            np.savez(path, **value)
        else:
            value = json.loads(path.read_text())
            action(value)
            path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
        self.spec(lambda s: s["artifacts"].update({name: sha256_file(path)}))

    def result(self, start=0, end=3600):
        return evaluate_accounting(Bundle(self.manifest), start, end)

    def metric(self, result=None, channel="fix.pbl.total"):
        return (result or self.result())["metrics"]["channels"][channel]

    def steps(self, first, second=None):
        records = [[{"values": [0, 0]}] for _ in range(24)]
        records[0] = first
        if second is not None:
            records[1] = second
        return records

    def test_within_step_pair_is_visible_despite_closed_ledgers(self):
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 0, 4))
        self.assertEqual(m["accepted_positive"], 2)
        self.assertEqual(m["accepted_negative"], -2)
        self.assertEqual(m["accepted_cell_application_events"], 4)
        self.assertEqual(self.metric(self.result(0, 86400))["accepted_activity"], 96)
        self.assertEqual(self.result()["verdict"], "NOT ASSESSABLE")
        self.assertFalse(self.result()["metrics"]["production_complete"])

    def test_opposing_successive_steps_preserve_retained_activity(self):
        ledger = np.zeros((25, 2))
        ledger[1] = 1
        attach_fixture(self.manifest, records={"fix.pbl.total": self.steps([{"values": [1, 1]}], [{"values": [-1, -1]}])},
                       ledgers={"fix.pbl.total": ledger})
        m = self.metric(self.result(0, 7200))
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 4, 4))

    def test_opposing_cells_do_not_cancel_before_absolute_value(self):
        ledger = np.zeros((25, 2))
        ledger[1:] = [1, -1]
        attach_fixture(self.manifest, records={"fix.pbl.total": self.steps([{"values": [1, -1]}])}, ledgers={"fix.pbl.total": ledger})
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 2, 2))

    def test_directed_transfer_is_once_and_legs_twice(self):
        donor = np.zeros((25, 2))
        donor[1:] = -2
        receiver = -donor
        attach_fixture(self.manifest,
                       records={"follow.pbl.rain": self.steps([{"values": [-2, -2]}]),
                                "follow.pbl.snow": self.steps([{"values": [2, 2]}])},
                       ledgers={"follow.pbl.rain": donor, "follow.pbl.snow": receiver})
        self.spec(lambda s: s["correction_accounting"].update(directed_transfers=[{"id": "rain_to_snow", "donor": "follow.pbl.rain", "receiver": "follow.pbl.snow"}]))
        result = self.result()
        pair = result["metrics"]["directed_transfers"][0]
        self.assertEqual(pair["absolute_transfer_amount"], 4)
        self.assertEqual(pair["summed_leg_activity"], 8)
        # The giving leg loses 4, so the amount moved forward is +4.
        self.assertEqual(pair["signed_forward_amount"], 4)
        self.assertEqual(sum(m["signed"] for m in result["metrics"]["channels"].values()), 0)

    def test_invalid_directed_pair_does_not_hide_missing_water(self):
        donor = np.zeros((25, 2))
        donor[1:] = -2
        receiver = np.zeros((25, 2))
        receiver[1:] = 1
        attach_fixture(self.manifest,
                       records={"follow.pbl.rain": self.steps([{"values": [-2, -2]}]),
                                "follow.pbl.snow": self.steps([{"values": [1, 1]}])},
                       ledgers={"follow.pbl.rain": donor, "follow.pbl.snow": receiver})
        self.spec(lambda s: s["correction_accounting"].update(directed_transfers=[{"id": "bad", "donor": "follow.pbl.rain", "receiver": "follow.pbl.snow"}]))
        with self.assertRaisesRegex(DataError, "contributions"):
            self.result()

    def test_simultaneous_closing_part_corrections_have_nonzero_activity(self):
        rain = np.zeros((25, 2))
        rain[1:] = 3
        snow = -rain
        attach_fixture(self.manifest,
                       records={"close.pbl.rain": self.steps([{"values": [3, 3]}]),
                                "close.pbl.snow": self.steps([{"values": [-3, -3]}])},
                       ledgers={"close.pbl.rain": rain, "close.pbl.snow": snow})
        values = self.result()["metrics"]["channels"].values()
        self.assertEqual(sum(v["signed"] for v in values), 0)
        self.assertEqual(sum(v["accepted_activity"] for v in values), 12)

    def test_rejected_work_only_increases_attempted_updates(self):
        raw = [[{"values": [100, 100], "trial": "discarded0", "disposition": "rejected"},
                {"values": [1, 1]}, {"values": [-1, -1]}]] + [[{"values": [0, 0]}] for _ in range(23)]
        attach_fixture(self.manifest, records={"fix.pbl.total": raw}, ledgers={"fix.pbl.total": np.zeros((25, 2))})
        self.file("application_receipt.json", lambda r: r["steps"][0]["trials"].append({"id": "discarded0", "decision": "rejected"}))
        m = self.metric()
        self.assertEqual(m["accepted_activity"], 4)
        self.assertEqual(m["attempted_update_activity"], 204)
        self.assertEqual(m["discarded_evaluations"], 1)

    def test_rejected_trial_cannot_be_booked_as_accepted(self):
        self.file("application_receipt.json", lambda r: r["steps"][0]["trials"][0].update(decision="rejected"))
        with self.assertRaisesRegex(DataError, "one accepted trial"):
            self.result()

    def test_provisional_trial_requires_finalization(self):
        self.file("application_receipt.json", lambda r: r["steps"][0]["trials"][0].update(decision="provisional"))
        with self.assertRaisesRegex(DataError, "provisional"):
            self.result()

    def test_repeated_newton_evaluation_is_replaced(self):
        ledger = np.zeros((25, 2))
        ledger[1:] = 1
        raw = self.steps([{"values": [9, 9], "application_id": "newton", "evaluation_id": "iterate1", "disposition": "superseded", "attempted_coefficient": None},
                          {"values": [1, 1], "application_id": "newton", "evaluation_id": "final", "attempted_coefficient": None}])
        attach_fixture(self.manifest, records={"fix.pbl.total": raw}, ledgers={"fix.pbl.total": ledger})
        m = self.metric()
        self.assertEqual(m["accepted_activity"], 2)
        self.assertEqual(m["attempted_update_activity"], 0)
        self.assertEqual(m["evaluation_only_records"], 2)

    def test_double_counted_newton_evaluations_fail(self):
        self.file("application_receipt.json", lambda r: r["steps"][0]["applications"][1].update(application_id="app0"))
        with self.assertRaisesRegex(DataError, "multiple Newton"):
            self.result()

    def test_nonadditive_presolve_observation_cannot_be_an_application(self):
        self.file("application_receipt.json", lambda r: r["steps"][0]["applications"][0].update(role="pre_solve"))
        with self.assertRaisesRegex(DataError, "nonadditive"):
            self.result()

    def test_tableau_dt_b_weights_are_used_before_absolute_value(self):
        pin = {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers", "version": "synthetic",
               "b_exp": [0.25, -0.75], "b_imp": [1, 1], "implicit_diagonal": [0.5, 0.5]}
        raw = self.steps([{"values": [1, 1], "role": "explicit", "stage": 1, "coefficient": 900, "coefficient_units": "s", "attempted_coefficient": None},
                          {"values": [1 / 3, 1 / 3], "role": "explicit", "stage": 2, "coefficient": -2700, "coefficient_units": "s", "attempted_coefficient": None}])
        raw[1:] = [[{"values": [0, 0], "role": "explicit", "stage": 1, "coefficient": 900, "coefficient_units": "s", "attempted_coefficient": None}] for _ in range(23)]
        attach_fixture(self.manifest, records={"fix.pbl.total": raw}, ledgers={"fix.pbl.total": np.zeros((25, 2))}, quantity="water_tendency", receipt_pin=pin)
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 0, 3600))
        self.file("application_receipt.json", lambda r: r["steps"][0]["applications"][0].update(coefficient=3600))
        with self.assertRaisesRegex(DataError, "tableau pin"):
            self.result()

    def test_post_newton_map_uses_b_over_gamma(self):
        pin = {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers", "version": "synthetic",
               "b_exp": [1], "b_imp": [0.75], "implicit_diagonal": [0.5]}
        raw = [[{"values": [1, 1], "role": "post_newton", "stage": 1, "coefficient": 1.5},
                {"values": [-1, -1], "role": "post_newton", "stage": 1, "coefficient": 1.5}] for _ in range(24)]
        attach_fixture(self.manifest, records={"fix.pbl.total": raw}, ledgers={"fix.pbl.total": np.zeros((25, 2))}, receipt_pin=pin)
        self.assertEqual(self.metric()["accepted_activity"], 6)

    def test_copies_repair_keeps_tag_and_compartment_identity(self):
        zeros = np.zeros((25, 2))
        attach_fixture(self.manifest, records={"uprepair.pbl.copy1": [[{"values": [1, 1]}, {"values": [-1, -1]}] for _ in range(24)],
                                               "uprepair.free.copy1": [[{"values": [2, 2]}, {"values": [-2, -2]}] for _ in range(24)]},
                       ledgers={"uprepair.pbl.copy1": zeros, "uprepair.free.copy1": zeros})
        m = self.result()["metrics"]["channels"]
        self.assertEqual(m["uprepair.pbl.copy1"]["accepted_activity"], 4)
        self.assertEqual(m["uprepair.free.copy1"]["accepted_activity"], 8)

    def test_bounds_fallback_clamp_and_normalization_counts_are_separate(self):
        attach_fixture(self.manifest, counters={"fix.pbl.total": {"fallback": [2, 1], "bound": [3, 4], "clamp": [0, 5], "zero_normalization": [7, 0]}})
        counts = self.metric()["accepted_counters"]
        self.assertEqual(counts, {"fallback": 6, "bound": 14, "clamp": 10, "zero_normalization": 14})

    def test_absent_counter_is_not_a_zero(self):
        self.file("applications.npz", lambda a: a.pop("fix_pbl_total__bound"))
        with self.assertRaisesRegex(DataError, "archive"):
            self.result()

    def test_inactive_channel_needs_pinned_evidence(self):
        def inactive(s):
            section = s["correction_accounting"]
            section["required_channels"].append("upfilter.pbl.copy1")
            section["coverage"].append({"id": "upfilter.pbl.copy1", "mechanism": "upfilter", "tag": "pbl", "compartment": "copy1", "status": "inactive", "reason": "copies disabled"})
        self.spec(inactive)
        with self.assertRaisesRegex(DataError, "inactive channel needs evidence"):
            self.result()
        self.spec(lambda s: s["correction_accounting"]["coverage"][-1].update(evidence="fixture_metadata.json"))
        self.assertEqual(self.result()["metrics"]["inactive_channels"], ["upfilter.pbl.copy1"])

    def test_missing_channel_blocks_complete_scope_without_zero_substitution(self):
        self.spec(lambda s: (s["correction_accounting"]["required_channels"].append("negative.pbl.total"),
                             s["correction_accounting"]["coverage"].append({"id": "negative.pbl.total", "mechanism": "negative", "tag": "pbl", "compartment": "total", "status": "missing", "reason": "no producer"})))
        result = self.result()
        self.assertFalse(result["metrics"]["observed_data_complete"])
        self.assertIn("negative.pbl.total", result["limitation"])
        self.assertNotIn("negative.pbl.total", result["metrics"]["channels"])

    def test_empty_or_duplicate_required_roster_cannot_pass(self):
        self.spec(lambda s: s["correction_accounting"].update(required_channels=[]))
        with self.assertRaisesRegex(DataError, "required accounting roster"):
            self.result()

    def test_missing_observation_in_one_step_is_not_inferred_zero(self):
        self.file("application_receipt.json", lambda r: r["steps"][3].update(applications=[]))
        with self.assertRaisesRegex(DataError, "[Ee]xplicit zero"):
            self.result()

    def test_mismatched_native_geometry_is_rejected(self):
        self.file("applications.npz", lambda a: a["geometry"].__setitem__((1, 0), 1501))
        with self.assertRaisesRegex(DataError, "native geometry"):
            self.result()

    def test_changing_density_is_reconstructed_at_each_endpoint(self):
        def change(a):
            rho = 1 + np.arange(25, dtype=np.float64)[:, None]
            a["rho"] = np.repeat(rho, 2, axis=1)
            a["application_ledger_fix_pbl_total"] = np.repeat(1 / rho, 2, axis=1)
            a["application_ledger_fix_pbl_total__units"] = np.array("kg kg^-1")
            a["application_ledger_fix_pbl_total__representation"] = np.array("specific")
        self.file("candidate.npz", change)
        self.spec(lambda s: s["runs"]["candidate"]["fields"]["application_ledger_fix_pbl_total"].update(units="kg kg^-1", representation="specific"))
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 0, 4))

    def test_wrong_ledger_change_is_detected(self):
        self.file("candidate.npz", lambda a: a["application_ledger_fix_pbl_total"].__setitem__((1, 0), 0.5))
        with self.assertRaisesRegex(DataError, "do not match"):
            self.result()

    def test_rounding_allowance_does_not_mix_density_or_other_cells(self):
        for dtype, ledger, raw in (
            (np.float32, np.zeros((25, 2), dtype=np.float32), [1e-5, 0]),
            (np.float64, np.repeat([[1e14, 0]], 25, axis=0), [0, 1]),
        ):
            with self.subTest(dtype=dtype):
                attach_fixture(self.manifest, dtype=dtype,
                               records={"fix.pbl.total": self.steps([{"values": raw}])},
                               ledgers={"fix.pbl.total": ledger})
                with self.assertRaisesRegex(DataError, "do not match"):
                    self.result()

    def test_uint64_counters_do_not_wrap_negative(self):
        def mutate(a):
            counter = np.zeros_like(a["fix_pbl_total__bound"], dtype=np.uint64)
            counter[0, 0] = 2 ** 63
            a["fix_pbl_total__bound"] = counter
        self.file("applications.npz", mutate)
        self.assertEqual(self.metric()["accepted_counters"]["bound"], 2 ** 63)

    def test_other_steps_operation_counts_cannot_hide_missing_native_delta(self):
        # The first step's many observed zeros cannot justify rounding away
        # a representable correction in the second step's unchanged cell.
        records = self.steps([{"values": [0, 0]} for _ in range(128)],
                             [{"values": [1e-4, 0]}])
        ledger = np.ones((25, 2), dtype=np.float32)
        attach_fixture(self.manifest, dtype=np.float32,
                       records={"fix.pbl.total": records},
                       ledgers={"fix.pbl.total": ledger})
        with self.assertRaisesRegex(DataError, "do not match"):
            self.result(start=0, end=7200)

    def test_float32_native_stage_cancellation_has_local_rounding_scale(self):
        pin = {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers", "version": "synthetic",
               "b_exp": [0.25, 0.5, 0.25], "b_imp": [0.25, 0.5, 0.25], "implicit_diagonal": [1, 1, 1]}
        rates = np.asarray([1 / 900, 1e-8 / 1800, -1 / 900], dtype=np.float32)
        coefficients = np.asarray([900, 1800, 900], dtype=np.float32)
        # Independent native accepted assembly loses the middle stage.
        native_sum = np.float32(0)
        for rate, coefficient in zip(rates, coefficients):
            native_sum = np.float32(native_sum + np.float32(rate * coefficient))
        self.assertEqual(native_sum, 0)
        exact_sum = float(np.sum(rates.astype(np.float64) * coefficients.astype(np.float64)))
        self.assertGreater(exact_sum, 0)
        entries = [{"values": [float(rate), 0], "role": "explicit", "stage": n + 1,
                    "coefficient": float(coefficients[n]), "coefficient_units": "s", "attempted_coefficient": None}
                   for n, rate in enumerate(rates)]
        raw = [entries] + [[{"values": [0, 0], "role": "explicit", "stage": 1, "coefficient": 900,
                            "coefficient_units": "s", "attempted_coefficient": None}] for _ in range(23)]
        ledger = np.zeros((25, 2), dtype=np.float32)
        ledger[1:, 0] = native_sum
        attach_fixture(self.manifest, dtype=np.float32, quantity="water_tendency", receipt_pin=pin,
                       records={"fix.pbl.total": raw}, ledgers={"fix.pbl.total": ledger})
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"]), (0, 0))
        self.assertAlmostEqual(m["accepted_activity"], 2, places=6)
        self.assertGreaterEqual(m["consistency_allowance"], exact_sum)

    def test_half_subnormal_native_weighting_can_round_to_zero(self):
        smallest = np.nextafter(np.float32(0), np.float32(1))
        native_update = np.float32(smallest * np.float32(0.5))
        self.assertEqual(native_update, 0)
        pin = {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers", "version": "synthetic",
               "b_exp": [0.5], "b_imp": [0.5], "implicit_diagonal": [1]}
        entry = {"values": [float(smallest), 0], "role": "post_newton", "stage": 1,
                 "coefficient": 0.5, "coefficient_units": "1", "attempted_coefficient": None}
        attach_fixture(self.manifest, dtype=np.float32, receipt_pin=pin,
                       records={"fix.pbl.total": self.steps([entry])},
                       ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=np.float32)})
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"]), (0, 0))
        self.assertEqual(m["accepted_activity"], float(smallest) * 0.5)
        self.assertGreaterEqual(m["consistency_allowance"], float(smallest) * 0.5)

    def test_representable_subnormal_omission_and_exact_zero_stay_distinct(self):
        smallest = np.nextafter(np.float32(0), np.float32(1))
        self.assertEqual(np.float32(smallest * np.float32(1)), smallest)
        attach_fixture(self.manifest, dtype=np.float32,
                       records={"fix.pbl.total": self.steps([{"values": [float(smallest), 0]}])},
                       ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=np.float32)})
        with self.assertRaisesRegex(DataError, "do not match"):
            self.result()
        attach_fixture(self.manifest, dtype=np.float32,
                       records={"fix.pbl.total": self.steps([{"values": [0, 0]}])},
                       ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=np.float32)})
        self.assertEqual(self.metric()["consistency_allowance"], 0)

    def test_specific_export_subnormal_quantum_uses_endpoint_density(self):
        smallest = np.nextafter(np.float32(0), np.float32(1))
        native_density_update = np.float32(smallest)
        exported_specific = np.float32(native_density_update / np.float32(10))
        self.assertEqual(exported_specific, 0)
        attach_fixture(self.manifest, dtype=np.float32,
                       records={"fix.pbl.total": self.steps([{"values": [float(smallest), 0]}])},
                       ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=np.float32)})
        def change(a):
            a["rho"][:] = 10
            a["application_ledger_fix_pbl_total__units"] = np.array("kg kg^-1")
            a["application_ledger_fix_pbl_total__representation"] = np.array("specific")
        self.file("candidate.npz", change)
        self.spec(lambda s: s["runs"]["candidate"]["fields"]["application_ledger_fix_pbl_total"].update(
            units="kg kg^-1", representation="specific"))
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"]), (0, 0))
        self.assertEqual(m["accepted_activity"], float(native_density_update))
        self.assertGreaterEqual(m["consistency_allowance"], float(native_density_update))

    def test_specific_endpoint_quantization_avoids_sum_density_overflow(self):
        attach_fixture(self.manifest,
                       records={"fix.pbl.total": self.steps([{"values": [0, 0]}])},
                       ledgers={"fix.pbl.total": np.full((25, 2), 1e-308)})
        def change(a):
            a["rho"][:] = 1e308
            a["application_ledger_fix_pbl_total__units"] = np.array("kg kg^-1")
            a["application_ledger_fix_pbl_total__representation"] = np.array("specific")
        self.file("candidate.npz", change)
        self.spec(lambda s: s["runs"]["candidate"]["fields"]["application_ledger_fix_pbl_total"].update(
            units="kg kg^-1", representation="specific"))
        m = self.metric()
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (0, 0, 0))
        self.assertTrue(np.isfinite(m["consistency_allowance"]))

    def test_integral_overflow_is_a_data_failure(self):
        self.file("applications.npz", lambda a: a["fix_pbl_total__values"].__setitem__((0, slice(None)), 1e308))
        with self.assertRaisesRegex(DataError, "integrated application amount"):
            self.result()

    def test_float32_cli_serializes_the_consistency_allowance(self):
        attach_fixture(self.manifest, dtype=np.float32)
        output = self.root / "float32-score.json"
        with contextlib.redirect_stdout(io.StringIO()):
            exit_code = main(["score", str(self.manifest), "--json", str(output)])
        # This fixture compares a Float32 candidate to Float64 references.
        # required same-dtype parent evidence is incomplete. Serialization must finish.
        self.assertEqual(exit_code, 2)
        result = json.loads(output.read_text())
        row = next(r for r in result["rows"] if r["id"] == "COMMON.ACCEPTED_APPLICATION_ACTIVITY")
        self.assertEqual(row["metrics"]["channels"]["fix.pbl.total"]["accepted_activity"], 96)
        self.assertIsInstance(row["metrics"]["channels"]["fix.pbl.total"]["consistency_allowance"], float)

    def test_no_interpolation_or_truncated_step_coverage(self):
        with self.assertRaisesRegex(DataError, "endpoint"):
            self.result(1, 3600)
        self.file("application_receipt.json", lambda r: r["steps"].pop())
        with self.assertRaisesRegex(DataError, "coverage differs"):
            self.result()

    def test_application_archive_identity_is_checked(self):
        path = self.root / "applications.npz"
        path.write_bytes(path.read_bytes() + b"changed")
        with self.assertRaisesRegex(DataError, "checksum"):
            self.result()

    def test_float32_and_float64_preserve_small_and_signed_activity(self):
        for dtype in (np.float32, np.float64):
            with self.subTest(dtype=dtype):
                attach_fixture(self.manifest, dtype=dtype, records={"fix.pbl.total": [[{"values": [1e-8, -1e-8]}, {"values": [-1e-8, 1e-8]}] for _ in range(24)]},
                               ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=dtype)})
                m = self.metric()
                self.assertAlmostEqual(m["accepted_activity"], 4e-8, delta=1e-15)
                self.assertEqual(m["accepted_cell_application_events"], 0 if dtype == np.float32 else 4)

    def test_output_cadence_does_not_change_application_activity(self):
        before = self.metric(self.result(0, 86400))["accepted_activity"]
        self.spec(lambda s: s.update(output_interval_seconds=7200))
        self.assertEqual(before, self.metric(self.result(0, 86400))["accepted_activity"])

    def test_restart_stitches_every_declared_amount_count_and_latch(self):
        # Independent expected trajectories for one numerator, all counters
        # and the validity latch. The restored boundary is not counted twice.
        tracks = {"activity": [0., 4., 8., 12.], "events": [0., 2., 5., 7.],
                  "fallback": [0., 0., 1., 1.], "bound": [0., 1., 1., 2.],
                  "clamp": [0., 0., 2., 3.], "zero_normalization": [0., 1., 2., 2.],
                  "negative_latch": [0., 0., 1., 1.]}
        for name, values in tracks.items():
            with self.subTest(name=name):
                a = Field(np.array([0., 1., 2.]), np.array(values[:3])[:, None], np.ones(1), np.zeros((1, 1)), "1", "amount", "cumulative", "1", ("scalar",), ("left",))
                b = copy.deepcopy(a)
                b.time = np.array([2., 3.])
                b.values = np.array(values[2:])[:, None]
                segments = [{"id": "left", "output_checkpoint": "cp", "accumulators": {name: {"mode": "continued"}}},
                            {"id": "right", "parent_id": "left", "input_checkpoint": "cp", "accumulators": {name: {"mode": "continued"}}}]
                whole = stitch([a, b], segments, name)
                np.testing.assert_array_equal(whole.values[:, 0], values)
                b.values[0, 0] += 1
                with self.assertRaisesRegex(DataError, "boundary changed"):
                    stitch([a, b], segments, name)

    def test_restart_absent_history_cannot_be_a_whole_run_zero(self):
        f = Field(np.array([0., 1.]), np.zeros((2, 1)), np.ones(1), np.zeros((1, 1)), "1", "amount", "cumulative", "1", ("scalar",), ("new segment",))
        with self.assertRaisesRegex(DataError, "continuation metadata"):
            stitch([f], [{"id": "new"}], "activity")
        with self.assertRaisesRegex(DataError, "unknown ancestry"):
            stitch([f], [{"id": "new", "parent_id": "missing", "accumulators": {"activity": {"mode": "continued"}}}], "activity")

    def test_duplicate_restart_application_is_rejected(self):
        self.file("application_receipt.json", lambda r: r["steps"].insert(1, copy.deepcopy(r["steps"][0])))
        with self.assertRaisesRegex(DataError, "duplicate accepted step"):
            self.result()

    def test_energy_source_cancellation_does_not_replace_od4(self):
        self.root = Path(self.temp.name) / "energy"
        self.manifest = write_fixture(self.root, "energy_source")
        attach_fixture(self.manifest, family="energy_source", records={"source.pbl.total": [[{"values": [1, 1]}, {"values": [-1, -1]}] for _ in range(24)]},
                       ledgers={"source.pbl.total": np.zeros((25, 2))})
        scorer = Scorer(Bundle(self.manifest))
        theta = scorer.exact_scale(0, 7200)
        self.assertEqual(theta, 20)
        self.assertEqual(self.metric(self.result(0, 7200), "source.pbl.total")["accepted_activity"], 8)
        self.assertEqual(Scorer(Bundle(self.manifest)).exact_scale(0, 7200), 20)
        self.assertIsNone(self.result()["metrics"]["scientific_activity_tolerance"])

    def test_synthetic_receipt_cannot_clear_production_gate(self):
        self.file("application_receipt.json", lambda r: r.update(kind="runtime_capture"))
        # Relabelling the receipt does not remove the submission's synthetic identity.
        self.assertFalse(self.result()["metrics"]["production_complete"])
        result = Scorer(Bundle(self.manifest)).run()
        row = next(r for r in result["rows"] if r["id"] == "COMMON.ACCEPTED_APPLICATION_ACTIVITY")
        self.assertEqual(row["verdict"], "NOT ASSESSABLE")
        self.assertEqual(row["data_status"], "COMPLETE")
        self.assertEqual(result["scientific_qualification"], "NOT QUALIFIED")

    def test_arbitrary_hashed_metadata_cannot_register_a_runtime_producer(self):
        data = json.loads(self.manifest.read_text())
        proof = {"kind": "runtime_validation", "model_commit": data["head_sha"],
                 "model_diff_sha256": data["diff_sha256"], "producer_id": "self-declared",
                 "producer_source": "fixture_metadata.json", "scope_roster": ["fix.pbl.total"],
                 "checks": {k: {"result": "PASS", "command": "true", "environment": "offline", "log": "fixture_metadata.json"}
                            for k in ("accepted_weights", "trial_rollback", "newton_replacement", "complete_active_roster", "parent_bitwise_parity", "all_channel_checkpoint_restart")}}
        path = self.root / "fake-runtime-validation.json"
        path.write_text(json.dumps(proof) + "\n")
        data["julia_version"] = "1.11.0"
        data["acceptance"]["resolved_settings"]["fixture"] = False
        data["acceptance"]["artifacts"][path.name] = sha256_file(path)
        data["acceptance"]["correction_accounting"]["lifecycle_evidence"] = path.name
        data["acceptance"]["correction_accounting"]["verified_producers"] = {"self-declared": "fixture_metadata.json"}
        self.manifest.write_text(json.dumps(data) + "\n")
        self.file("application_receipt.json", lambda r: r.update(kind="runtime_capture"))
        result = self.result()
        self.assertFalse(result["metrics"]["production_complete"])
        self.assertEqual(result["verdict"], "NOT ASSESSABLE")
        self.assertIn("no verified runtime application producer", result["limitation"])

    def test_validate_and_score_detect_new_evidence_fault(self):
        self.file("applications.npz", lambda a: a["fix_pbl_total__values"].__setitem__((0, 0), np.nan))
        for mode in ("validate", "score"):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([mode, str(self.manifest), "--json", str(self.root / (mode + ".json"))]), 2)

    def precipitation_fixture(self, sphere=False, rates=(-1.0, 0.25), shares=(1, .6, .4), step_scale=False):
        data = json.loads(self.manifest.read_text())
        spec = data["acceptance"]
        cells = 2 if sphere else 1
        weights = np.array([2., 3.]) if sphere else np.ones(1)
        archive = {"weights": weights, "geometry": np.arange(cells, dtype=np.float64)[:, None], "weight_units": np.array("m^2" if sphere else "1")}
        receipt = json.loads((self.root / "application_receipt.json").read_text())
        receipt["integrator_pin"].update(b_exp=[0.5, 0.5], b_imp=[1, 1], implicit_diagonal=[1, 1])
        channels = {}
        for name, share in zip(("parent", "pbl", "free"), shares):
            ids = []
            values = []
            for n, step in enumerate(receipt["steps"]):
                if name == "parent":
                    step["applications"] = []
                for m, rate in enumerate(rates):
                    rid = f"{name}.{n}.{m}"
                    step["applications"].append({"channel": name, "record_id": rid, "trial": f"trial{n}",
                                                  "application_id": f"flux{m}", "evaluation_id": f"stage{m}",
                                                  "disposition": "applied", "role": "explicit", "stage": m + 1,
                                                  "coefficient": 1800, "coefficient_units": "s", "attempted_coefficient": None})
                    ids.append(rid)
                    values.append([rate * share * (n + 1 if step_scale else 1)] * cells)
            archive[name + "__values"] = np.asarray(values, dtype=np.float64)
            archive[name + "__record_ids"] = np.asarray(ids)
            archive[name + "__quantity"] = np.array("precipitation_flux")
            archive[name + "__units"] = np.array("kg m^-2 s^-1")
            archive[name + "__event_scale"] = np.full((48, cells), 100.)
            for counter in ("fallback", "bound", "clamp", "zero_normalization"):
                archive[name + "__" + counter] = np.zeros((48, cells), dtype=np.int64)
            channels[name] = {"path": "precip_apps.npz", "prefix": name, "quantity": "precipitation_flux", "units": "kg m^-2 s^-1"}
        np.savez(self.root / "precip_apps.npz", **archive)
        (self.root / "precip_receipt.json").write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
        if sphere:
            spec["geometry_kind"] = "sphere"
        spec["precipitation_applications"] = {"schema_version": 1, "receipt": "precip_receipt.json", "channels": channels,
                                              "required_channels": list(channels), "sign_convention": "upward_positive"}
        for name in ("precip_apps.npz", "precip_receipt.json"):
            spec["artifacts"][name] = sha256_file(self.root / name)
        self.manifest.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")

    def test_paired_signed_flux_keeps_positive_and_negative_amounts(self):
        self.precipitation_fixture()
        result = paired_precipitation(Bundle(self.manifest), 0, 3600)
        p = result["metrics"]["paired_amounts"]["parent"]
        self.assertEqual(p, {"signed_downward_amount": 1350, "positive_downward_amount": 1800, "negative_downward_amount": -450})
        self.assertEqual(result["metrics"]["paired_amounts"]["pbl"]["signed_downward_amount"], 810)
        self.assertEqual(result["metrics"]["signed_defect"], 0)
        # WA-PRECIP keeps the row reported. The closed gate is a limitation, not a verdict.
        self.assertNotIn("verdict", result)
        self.assertFalse(result["metrics"]["production_complete"])
        self.assertIn("synthetic application evidence", result["limitation"])

    def test_paired_no_rain_is_an_exact_zero_amount(self):
        self.precipitation_fixture(rates=(0., 0.))
        m = paired_precipitation(Bundle(self.manifest), 0, 3600)["metrics"]
        self.assertEqual(m["signed_downward_amount"], 0)
        self.assertEqual(m["absolute_application_defect"], 0)

    def test_simultaneous_rain_snow_fluxes_use_same_update_pair(self):
        self.precipitation_fixture(rates=(-1., -2.))
        result = paired_precipitation(Bundle(self.manifest), 0, 3600)
        self.assertEqual(result["metrics"]["signed_downward_amount"], 5400)
        self.assertEqual(result["metrics"]["paired_amounts"]["free"]["signed_downward_amount"], 2160)

    def test_native_sphere_surface_uses_area_weights(self):
        self.precipitation_fixture(sphere=True)
        result = paired_precipitation(Bundle(self.manifest), 0, 3600)
        self.assertEqual(result["units"], "kg")
        self.assertEqual(result["metrics"]["signed_downward_amount"], 6750)

    def test_parent_tag_flux_pair_mismatch_is_rejected(self):
        self.precipitation_fixture()
        self.file("precip_receipt.json", lambda r: r["steps"][0]["applications"][2].update(application_id="different_update"))
        with self.assertRaisesRegex(DataError, "parent/tag precipitation update"):
            paired_precipitation(Bundle(self.manifest), 0, 3600)

    def test_same_coefficient_does_not_make_different_flux_stage_the_same_update(self):
        self.precipitation_fixture()
        self.file("precip_receipt.json", lambda r: r["steps"][0]["applications"][2].update(stage=2))
        with self.assertRaisesRegex(DataError, "parent/tag precipitation update"):
            paired_precipitation(Bundle(self.manifest), 0, 3600)

    def test_same_coefficient_does_not_make_implicit_and_explicit_fluxes_a_pair(self):
        self.precipitation_fixture()
        def change(r):
            r["integrator_pin"]["b_imp"] = [.5, .5]
            r["steps"][0]["applications"][2]["role"] = "implicit"
        self.file("precip_receipt.json", change)
        with self.assertRaisesRegex(DataError, "parent/tag precipitation update"):
            paired_precipitation(Bundle(self.manifest), 0, 3600)

    def test_directed_legs_with_different_hook_roles_are_not_a_pair(self):
        donor = np.zeros((25, 2))
        donor[1:] = -2
        receiver = -donor
        attach_fixture(self.manifest,
                       records={"follow.pbl.rain": self.steps([{"values": [-2, -2]}]),
                                "follow.pbl.snow": self.steps([{"values": [2, 2], "role": "post_newton", "stage": 1}])},
                       ledgers={"follow.pbl.rain": donor, "follow.pbl.snow": receiver})
        self.spec(lambda s: s["correction_accounting"].update(directed_transfers=[{"id": "wrong hook", "donor": "follow.pbl.rain", "receiver": "follow.pbl.snow"}]))
        with self.assertRaisesRegex(DataError, "different applications"):
            self.result()

    def test_precipitation_snapshot_cannot_claim_applied_amount(self):
        self.precipitation_fixture()
        self.spec(lambda s: s["precipitation_applications"]["channels"]["parent"].update(quantity="water_increment"))
        with self.assertRaisesRegex(DataError, "same-update surface flux"):
            paired_precipitation(Bundle(self.manifest), 0, 3600)

    def test_paired_precipitation_window_crosses_restart_without_duplicate_boundary(self):
        self.precipitation_fixture()
        # Two accepted intervals around an exact checkpoint time. A duplicate
        # endpoint is not a second application or a third interval.
        m = paired_precipitation(Bundle(self.manifest), 3600, 10800)["metrics"]
        self.assertEqual(m["accepted_steps"], 2)
        self.assertEqual(m["signed_downward_amount"], 2700)
        self.file("precip_receipt.json", lambda r: r["steps"].insert(2, copy.deepcopy(r["steps"][1])))
        with self.assertRaisesRegex(DataError, "duplicate accepted step"):
            paired_precipitation(Bundle(self.manifest), 3600, 10800)

    def test_paired_precipitation_keeps_instantaneous_diagnostics(self):
        self.precipitation_fixture()
        scorer = Scorer(Bundle(self.manifest))
        instantaneous = scorer.precipitation()
        integrated = scorer.precipitation(0, 3600)
        self.assertIn("max_absolute_rate_defect", instantaneous["metrics"])
        self.assertEqual(integrated["metrics"]["signed_downward_amount"], 1350)

    # Windows that start after zero, and the sign conventions.

    def test_window_after_start_reads_only_its_steps(self):
        # Step n applies +(n + 1) and then -(n + 1)/2 in both unit cells.
        records = {"fix.pbl.total": [[{"values": [n + 1, n + 1]}, {"values": [-(n + 1) / 2, -(n + 1) / 2]}]
                                     for n in range(24)]}
        ledger = np.zeros((25, 2))
        ledger[1:] = np.cumsum([(n + 1) / 2 for n in range(24)])[:, None]
        attach_fixture(self.manifest, records=records, ledgers={"fix.pbl.total": ledger})
        m = self.metric(self.result(7200, 14400))
        # Steps 2 and 3 only: A = 2 x (3 + 1.5 + 4 + 2), and H = S = 2 x (1.5 + 2).
        self.assertEqual((m["signed"], m["retained_activity"], m["accepted_activity"]), (7, 7, 21))
        self.assertEqual(m["retained_activity_from_applications"], 7)
        self.assertEqual(m["applied_records"], 4)

    def test_paired_window_after_start_reads_only_its_steps(self):
        self.precipitation_fixture(step_scale=True)
        result = paired_precipitation(Bundle(self.manifest), 3600, 10800)
        # Steps 1 and 2 carry the rates times 2 and 3: (1 - 0.25) x 1800 s x (2 + 3).
        self.assertEqual(result["metrics"]["signed_downward_amount"], 6750)
        self.assertEqual(result["metrics"]["accepted_steps"], 2)
        self.assertEqual(result["units"], "kg m^-2")

    def test_declared_paired_evidence_keeps_the_required_row_reported(self):
        # WA-PRECIP: criterion 7 stays reported accounting. A closed production
        # gate is a limitation and never turns the required row not assessable.
        self.precipitation_fixture()
        self.spec(lambda s: s["claim"].update(precipitation=True))
        rows = {r["id"]: r for r in Scorer(Bundle(self.manifest)).run()["rows"]}
        row = rows["WATER.PRECIP_INTEGRATED.established"]
        self.assertTrue(row["required"])
        self.assertEqual((row["verdict"], row["data_status"]), ("REPORTED ONLY", "COMPLETE"))
        self.assertIn("synthetic application evidence", row["limitation"])

    def test_paired_signed_defect_is_parent_minus_tags_downward(self):
        self.precipitation_fixture(shares=(1, .5, .25))
        m = paired_precipitation(Bundle(self.manifest), 0, 3600)["metrics"]
        # The tags carry 0.75 of the parent's 1350 downward, so 337.5 is missing downward.
        self.assertEqual(m["signed_defect"], 337.5)
        self.assertEqual(m["absolute_application_defect"], 562.5)

    # The rounding constants. No contract sets them. Each test states the reading.

    def test_rounding_ulps_reads_sixteen_eps_per_operation(self):
        self.assertEqual(ROUNDING_ULPS, 16)
        eps = float(np.finfo(np.float64).eps)
        one = np.ones(1)
        self.assertEqual(rounding_allowance(one)[0], 16 * eps)
        self.assertEqual(rounding_allowance(one, operations=3)[0], 48 * eps)
        close(one, one + 16 * eps)
        with self.assertRaisesRegex(DataError, "do not match"):
            close(one, one + 18 * eps)
        # An exact zero scale receives no allowance, even with a quantization term.
        self.assertEqual(rounding_allowance(np.zeros(1), quantization=1.0)[0], 0)

    def test_ledger_extra_operations_reads_three_roundings_per_step(self):
        # One application plus the two endpoint reconstructions and their
        # difference: 16 eps x 4 = 64 eps of a unit change.
        self.assertEqual(LEDGER_EXTRA_OPERATIONS, 3)
        eps = float(np.finfo(np.float64).eps)
        for offset, accepted in ((60, True), (66, False)):
            with self.subTest(offset=offset):
                ledger = np.zeros((25, 2))
                ledger[1:] = [1 + offset * eps, 1]
                attach_fixture(self.manifest, records={"fix.pbl.total": self.steps([{"values": [1, 1]}])},
                               ledgers={"fix.pbl.total": ledger})
                if accepted:
                    self.assertEqual(self.metric()["accepted_activity"], 2)
                else:
                    with self.assertRaisesRegex(DataError, "do not match"):
                        self.result()

    def test_transfer_operations_reads_one_rounding_per_leg(self):
        # Two legs of size 2: 16 eps x 2 x 2 = 64 eps.
        self.assertEqual(TRANSFER_OPERATIONS, 2)
        eps = float(np.finfo(np.float64).eps)
        for offset, accepted in ((62, True), (66, False)):
            with self.subTest(offset=offset):
                giving = np.zeros((25, 2))
                giving[1:] = -2
                receiving = np.zeros((25, 2))
                receiving[1:] = 2 + offset * eps
                attach_fixture(self.manifest,
                               records={"follow.pbl.rain": self.steps([{"values": [-2, -2]}]),
                                        "follow.pbl.snow": self.steps([{"values": [2 + offset * eps] * 2}])},
                               ledgers={"follow.pbl.rain": giving, "follow.pbl.snow": receiving})
                self.spec(lambda s: s["correction_accounting"].update(directed_transfers=[
                    {"id": "rain_to_snow", "donor": "follow.pbl.rain", "receiver": "follow.pbl.snow"}]))
                if accepted:
                    self.assertEqual(self.result()["metrics"]["directed_transfers"][0]["absolute_transfer_amount"], 4)
                else:
                    with self.assertRaisesRegex(DataError, "do not match"):
                        self.result()

    def test_half_quantum_reads_round_to_nearest_at_each_endpoint(self):
        # A specific export at density 10 may lose half the smallest Float32
        # subnormal at each endpoint: 10 x 0.5 + 10 x 0.5 = 10 quanta.
        self.assertEqual(HALF_QUANTUM, 0.5)
        smallest = float(np.nextafter(np.float32(0), np.float32(1)))
        for quanta, accepted in ((10, True), (11, False)):
            with self.subTest(quanta=quanta):
                attach_fixture(self.manifest, dtype=np.float32,
                               records={"fix.pbl.total": self.steps([{"values": [quanta * smallest, 0]}])},
                               ledgers={"fix.pbl.total": np.zeros((25, 2), dtype=np.float32)})
                def change(a):
                    a["rho"][:] = 10
                    a["application_ledger_fix_pbl_total__units"] = np.array("kg kg^-1")
                    a["application_ledger_fix_pbl_total__representation"] = np.array("specific")
                self.file("candidate.npz", change)
                self.spec(lambda s: s["runs"]["candidate"]["fields"]["application_ledger_fix_pbl_total"].update(
                    units="kg kg^-1", representation="specific"))
                if accepted:
                    self.assertEqual(self.metric()["retained_activity"], 0)
                else:
                    with self.assertRaisesRegex(DataError, "do not match"):
                        self.result()

    def test_tag_event_threshold_copies_tag_event(self):
        # tag_event counts a change above max(1e-12, 16 eps) times its scale.
        # The fixture exports a writer scale of 100. A change at the floor is no event.
        self.assertEqual((TAG_EVENT_THRESHOLD, TAG_EVENT_ULPS), (1e-12, 16))
        eps32 = 2.0 ** -23
        for dtype, at_floor, above in ((np.float64, 1e-12 * 100.0, 1.5e-10),
                                       (np.float32, 1600 * eps32, 1650 * eps32)):
            for value, events in ((at_floor, 0), (above, 2)):
                with self.subTest(dtype=dtype, value=value):
                    ledger = np.zeros((25, 2), dtype=dtype)
                    ledger[1:] = value
                    attach_fixture(self.manifest, dtype=dtype,
                                   records={"fix.pbl.total": self.steps([{"values": [value, value]}])},
                                   ledgers={"fix.pbl.total": ledger})
                    self.assertEqual(self.metric()["accepted_cell_application_events"], events)

    # The validation hook and the scorer rows.

    def test_validation_reads_the_accounting_extension(self):
        self.assertEqual(Bundle(self.manifest).validate(), [])
        self.file("applications.npz", lambda a: a["fix_pbl_total__values"].__setitem__((0, 0), np.nan))
        self.assertTrue(any("application values" in e for e in Bundle(self.manifest).validate()))

    def test_validation_reads_a_precipitation_extension_alone(self):
        self.precipitation_fixture()
        self.spec(lambda s: s.pop("correction_accounting"))
        self.assertEqual(Bundle(self.manifest).validate(), [])
        self.file("precip_apps.npz", lambda a: a["parent__values"].__setitem__((0, 0), np.nan))
        self.assertTrue(any("application values" in e for e in Bundle(self.manifest).validate()))

    def test_zero_length_window_gives_a_not_applicable_activity_row(self):
        # Quiet from the start, then a burst in the fifth hour: the OD2 boundary is 0 s.
        rates = np.ones(24)
        rates[4] = 100
        mass = 100 + np.concatenate(([0.0], np.cumsum(rates)))
        self.file("untagged.npz", lambda a: a.__setitem__("water_parent", np.repeat((mass / 2)[:, None], 2, axis=1)))
        rows = {r["id"]: r for r in Scorer(Bundle(self.manifest)).run()["rows"]}
        row = rows["COMMON.APPLICATION_ACTIVITY.startup"]
        self.assertEqual(row["verdict"], "NOT APPLICABLE")
        self.assertFalse(row["required"])
        self.assertIn("zero length", row["limitation"])

    # The production gate's pass path, through a test registry entry. This is
    # not runtime evidence. It checks what the gate reads once a producer exists.

    GATE_CHECKS = ("accepted_weights", "trial_rollback", "newton_replacement", "complete_active_roster",
                   "parent_bitwise_parity", "all_channel_checkpoint_restart")

    def open_gate(self, registry_version=None, **changes):
        data = json.loads(self.manifest.read_text())
        (self.root / "producer.jl").write_text("# test producer source\n")
        (self.root / "check.log").write_text("PASS\n")
        pin = json.loads((self.root / "application_receipt.json").read_text())["integrator_pin"]
        proof = {"kind": "runtime_validation", "model_commit": data["head_sha"],
                 "model_diff_sha256": data["diff_sha256"], "producer_id": "test-producer",
                 "producer_source": "producer.jl", "scope_roster": ["fix.pbl.total"], "integrator_pin": pin,
                 "checks": {k: {"result": "PASS", "command": "run", "environment": "test", "log": "check.log"}
                            for k in self.GATE_CHECKS}}
        proof.update(changes)
        (self.root / "runtime_validation.json").write_text(json.dumps(proof) + "\n")
        data["julia_version"] = "1.11.0"
        spec = data["acceptance"]
        spec["resolved_settings"]["fixture"] = False
        for name in ("producer.jl", "check.log", "runtime_validation.json"):
            spec["artifacts"][name] = sha256_file(self.root / name)
        spec["correction_accounting"]["lifecycle_evidence"] = "runtime_validation.json"
        self.manifest.write_text(json.dumps(data) + "\n")
        self.file("application_receipt.json", lambda r: r.update(kind="runtime_capture"))
        registry = {"test-producer": {"cts_version": registry_version or pin["version"],
                                      "source_sha256": sha256_file(self.root / "producer.jl")}}
        patcher = mock.patch.dict(correction_accounting.VERIFIED_PRODUCERS, registry)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_registered_producer_opens_the_production_gate(self):
        self.open_gate()
        result = self.result(0, 86400)
        self.assertEqual(result["verdict"], "PASS")
        self.assertTrue(result["metrics"]["production_complete"])
        self.assertTrue(result["limitation"].startswith("Note: a dedicated closing ledger"))
        # The window row reports activity. It never passes.
        self.assertEqual(application_activity(Bundle(self.manifest), 0, 3600)["verdict"], "REPORTED ONLY")
        rows = {r["id"]: r for r in Scorer(Bundle(self.manifest)).run()["rows"]}
        final = rows["COMMON.ACCEPTED_APPLICATION_ACTIVITY"]
        self.assertEqual((final["verdict"], final["parent_parity"]), ("PASS", "PASS"))
        for name in ("startup", "established", "sensitivity_1h"):
            row = rows["COMMON.APPLICATION_ACTIVITY." + name]
            self.assertEqual((row["verdict"], row["parent_parity"]), ("REPORTED ONLY", "PASS"))

    def test_each_synthetic_marker_alone_keeps_the_gate_closed(self):
        markers ={"receipt": lambda: self.file("application_receipt.json", lambda r: r.update(kind="synthetic")),
                   "fixture": lambda: self.spec(lambda s: s["resolved_settings"].update(fixture=True)),
                   "julia": lambda: self.manifest.write_text(json.dumps(
                       {**json.loads(self.manifest.read_text()), "julia_version": "not-run (fixture)"}) + "\n")}
        for marker, apply in markers.items():
            with self.subTest(marker=marker):
                self.open_gate()
                apply()
                self.assertIn("synthetic application evidence", self.result()["limitation"])

    def test_gate_reads_every_runtime_check(self):
        failed = {k: {"result": "PASS", "command": "run", "environment": "test", "log": "check.log"}
                  for k in self.GATE_CHECKS}
        failed["trial_rollback"] = {"result": "FAIL", "command": "run", "environment": "test", "log": "check.log"}
        no_log = dict(failed, trial_rollback={"result": "PASS", "command": "run", "environment": "test"})
        absent = dict(failed, trial_rollback={"result": "PASS", "command": "run", "environment": "test",
                                              "log": "absent.log"})
        limited = {"failed check": ({"checks": failed}, "unverified production lifecycle check: trial_rollback"),
                   "unregistered": ({"producer_id": "other"}, "no verified runtime application producer")}
        refused = {"no log": ({"checks": no_log}, "lacks command/environment/log"),
                   "absent log": ({"checks": absent}, "missing artifact"),
                   "roster": ({"scope_roster": ["other"]}, "does not cover declared accounting scope"),
                   "pin": ({"integrator_pin": {"version": "other"}}, "timestepper pin differs"),
                   "registry version": ({"registry_version": "other"}, "timestepper pin differs"),
                   "source": ({"producer_source": "check.log"}, "source differs"),
                   "identity": ({"model_commit": "other"}, "identity differs")}
        for name, (changes, message) in limited.items():
            with self.subTest(name=name):
                self.open_gate(**changes)
                self.assertIn(message, self.result()["limitation"])
        for name, (changes, message) in refused.items():
            with self.subTest(name=name):
                self.open_gate(**changes)
                with self.assertRaisesRegex(DataError, message):
                    self.result()


if __name__ == "__main__":
    unittest.main()
