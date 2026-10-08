"""Independent equations, closed wrong donors, native faults and decision gates."""

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

from acceptance_data import Bundle, DataError, Field, same_bits, stitch
from correction_accounting import VERIFIED_PRODUCERS, paired_precipitation
import make_water_transfer_fixture as driver
import score_acceptance
from make_water_transfer_fixture import evaluate_fixture, suite_exit_code, write_fixture, write_json
from manifest import sha256_file
from score_acceptance import DAY, SCORER_PATHS, Scorer
from water_transfer_adapter import evaluate_water_transfer, producer_identity
from water_transfer_preregistration import (effective_substep_key, proposed_audit_trend,
    px25_matrix, save_px25_draft, short_case_rows, void_substep_perturbation)
from water_transfer_reference import (DESIGN_SHA256, _exact_at, _exp_action, _rhs,
    application_error, audit_report, boundary_error_rows, case_by_id, closure,
    declared_negative_map, error_rows, exact, floor_result, initial, load_design,
    mutation, mutation_invariants, parent_trajectory, pool_replay, rk4,
    signed_audit_activity, state_fields)


class EquationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.design = load_design()

    def state(self, name):
        case = case_by_id(self.design, name)
        return case, exact(self.design, case)

    def test_frozen_design_and_single_transfer_known_answer(self):
        self.assertEqual(sha256_file(Path(__file__).with_name("water_transfer_design.json")), DESIGN_SHA256)
        # The hash shows the file is unchanged. It makes no claim about timing.
        self.assertIn("Integrity only.", self.design["design_sha256_pin"])
        self.assertNotIn("frozen", json.dumps(self.design["design_sha256_pin"]))
        configs = Path(__file__).resolve().parents[2] / "configs"
        for name in ("water_transfer_exact.json", "water_transfer_rk4.json"):
            self.assertEqual(json.loads((configs / name).read_text())["design_sha256"], DESIGN_SHA256)
        case, answer = self.state("single_transfer")
        m, x = initial(case)
        np.testing.assert_allclose(answer.parent[-1], [3.7, 2.3, 1], atol=1e-15)
        np.testing.assert_allclose(answer.labels[-1, :, 0], x[:, 0] - .3*x[:, 0]/4, atol=1e-15)
        np.testing.assert_allclose(answer.labels[-1, :, 1], x[:, 1] + .3*x[:, 0]/4, atol=1e-15)
        np.testing.assert_allclose(answer.labels.sum(axis=2), np.broadcast_to(x.sum(axis=1), (4, 6)), atol=1e-15)
        self.assertTrue(closure(answer, self.design)["complete_label_conservation"])

    def test_wrong_donor_closes_compartments_and_each_global_label_but_fails_origins(self):
        case, truth = self.state("single_transfer")
        wrong = mutation(self.design, case, truth)
        check = closure(wrong, self.design)
        self.assertTrue(check["meets"])
        self.assertTrue(check["complete_label_conservation"])
        self.assertTrue(parent_trajectory(wrong, truth, self.design)["meets"])
        self.assertTrue(mutation_invariants(wrong, truth, case, self.design)["meets"])
        rows = error_rows(wrong, truth, self.design)
        self.assertTrue(all(r["absolute"] < 1e-14 for r in rows if r["compartment"] == "total"))
        self.assertTrue(any(r["meets"] is False for r in rows if r["compartment"] == "R"))
        self.assertFalse(application_error(wrong, case)["meets"])
        # A compartment-total closing operation has no effect on this fault.
        closed = copy.deepcopy(wrong)
        closed.labels[:, :3] *= (closed.parent / closed.labels[:, :3].sum(axis=1))[:, None, :]
        np.testing.assert_allclose(closed.labels, wrong.labels, atol=1e-15)
        self.assertTrue(any(r["meets"] is False for r in error_rows(closed, truth, self.design)))

    def test_simultaneous_opposing_zero_parent_net_nonzero_exchange(self):
        case, truth = self.state("opposing_net_zero")
        expected = 4*((4*.6 + 2*.2)/6) + (4*2/6)*(.6-.2)*np.exp(-.8*(1/4+1/2))
        self.assertAlmostEqual(truth.labels[-1, 0, 0], expected, places=14)
        np.testing.assert_array_equal(truth.parent, np.broadcast_to(truth.parent[0], truth.parent.shape))
        erased = mutation(self.design, case, truth)
        self.assertTrue(closure(erased, self.design)["meets"])
        self.assertTrue(closure(erased, self.design)["complete_label_conservation"])
        self.assertGreater(np.max(np.abs(erased.labels-truth.labels)), .1)
        process = application_error(erased, case)
        self.assertAlmostEqual(process["transfer_amount_Q"], 1.6)
        self.assertAlmostEqual(process["donor_recipient_leg_activity_2Q"], 3.2)
        self.assertFalse(process["meets"])

    def test_cycle_independent_complex_roots_and_short_derivative(self):
        case, truth = self.state("three_compartment_cycle")
        _, x = initial(case)
        theta = .3/2
        roots = np.exp(2j*np.pi*np.arange(3)/3)
        probabilities = [np.real(np.sum(np.exp(theta*(roots-1))*roots**(-k)))/3 for k in range(3)]
        expected = sum(p*np.roll(x, k, axis=1) for k,p in enumerate(probabilities))
        np.testing.assert_allclose(truth.labels[-1], expected, atol=2e-15)
        h = .01
        dx = (_exact_at(case, h)[1] - x)/h
        np.testing.assert_allclose(dx, .3/(2*86400)*(np.roll(x, 1, axis=1)-x), atol=2e-13)

    def test_unequal_mass_uniform_composition_is_stationary(self):
        case = copy.deepcopy(case_by_id(self.design, "unequal_compositions"))
        case["fractions"] = [[.2]*3, [.3]*3, [.5]*3]
        answer = exact(self.design, case)
        np.testing.assert_allclose(answer.labels, np.broadcast_to(answer.labels[0], answer.labels.shape), atol=3e-15)
        self.assertTrue(closure(answer, self.design)["meets"])

    def test_empty_and_near_empty_replenishment_no_division(self):
        case, truth = self.state("empty_replenished")
        n = 4*np.exp(-.8)
        rain = 4*.8/(.5-.8)*(np.exp(-.8)-np.exp(-.5))
        np.testing.assert_allclose(truth.parent[-1], [n, rain, 5-n-rain], atol=2e-15)
        np.testing.assert_allclose(truth.labels[-1, :3, 1]/rain, [.6, .3, .1], atol=3e-15)
        fine = rk4(self.design, case, 64)
        self.assertTrue(np.isfinite(fine.labels).all())
        self.assertTrue(floor_result(fine, truth, self.design, case)["eligible"])
        near = copy.deepcopy(case)
        near["initial_amounts"][1] = 1e-20
        near["fractions"] = [list(row) for row in near["fractions"]]
        for row, value in zip(near["fractions"], (.2, .6, .2)): row[1] = value
        self.assertTrue(np.isfinite(rk4(self.design, near, 64).labels).all())

    def test_exact_depletion_endpoint_and_refused_physical_negative(self):
        case, truth = self.state("depleted_donor")
        self.assertEqual(truth.parent[-1, 0], 0.)
        np.testing.assert_array_equal(truth.labels[-1, :, 0], 0.)
        for count in self.design["substep_ladder"]:
            fine = rk4(self.design, case, count)
            self.assertEqual(fine.parent[-1, 0], 0.)
            self.assertTrue(floor_result(fine, truth, self.design, case)["eligible"])
        with self.assertRaises(DataError): _exact_at(case, 86401)
        unsupported = copy.deepcopy(case); unsupported.pop("endpoint_empty_donor_limit")
        m,x = initial(unsupported); m[0] = 0
        with self.assertRaises(DataError): _rhs(unsupported, 86400, m, x)
        kinetic = copy.deepcopy(case_by_id(self.design, "empty_replenished"))
        m,x = initial(kinetic);m[0] = -1e-10
        with self.assertRaises(DataError): _rhs(kinetic, 0, m, x)

    def test_negative_rule_withheld_and_pass_through_are_numerical(self):
        x = np.array([[.6,0,.2],[.4,0,.8]])
        F = np.zeros((3,3)); F[0,1] = .2
        result = declared_negative_map([1,-.1,1], x, F, 1)
        np.testing.assert_allclose(result["label_change"], [[-.12,0,0],[-.08,0,0]], atol=1e-15)
        np.testing.assert_allclose(result["withheld_labels"][:,1], [.12,.08], atol=1e-15)
        self.assertAlmostEqual(result["withheld_water"][1], .2)
        self.assertFalse(result["physical_composition"])
        F[1,2] = .2
        result = declared_negative_map([1,-.1,1], x, F, 1)
        np.testing.assert_allclose(result["label_change"], [[-.12,0,.12],[-.08,0,.08]], atol=1e-15)
        np.testing.assert_array_equal(result["withheld_labels"], 0.)
        signed = np.zeros((3,3));signed[1,0] = -.2
        np.testing.assert_array_equal(declared_negative_map([1,-.1,1],x,signed,1)["oriented_flows"], [[0,.2,0],[0,0,0],[0,0,0]])
        with self.assertRaises(DataError): declared_negative_map([1,1,1],x,signed,1)
        x[0,1] = .01
        with self.assertRaises(DataError): declared_negative_map([1,-.1,1],x,F,1)

    def test_zero_activity_not_applicable_and_small_overlay_scales(self):
        case, truth = self.state("zero_activity")
        process = application_error(truth, case)
        self.assertEqual(process["applicability"], "not applicable")
        self.assertEqual(process["weighted_share_error"], [None]*6)
        self.assertIsNone(process["meets"])
        floor = floor_result(rk4(self.design,case,64),truth,self.design,case)
        self.assertTrue(floor["eligible"])
        self.assertTrue(all(r["small"] for r in floor["errors"] if r["tag"] in ("tiny_source","zero_source")))
        self.assertTrue(all(r["arithmetic_fraction_of_tolerance"]["absolute"] >= 0 for r in floor["errors"] if r["small"]))
        self.assertGreater(truth.labels[:,:].sum(axis=1).max(), truth.parent.max())

    def test_rain_snow_levels_units_and_export_inclusive_conservation(self):
        case, truth = self.state("rain_snow_sedimentation")
        self.assertAlmostEqual(truth.parent[-1,7], .8*np.exp(-.9/4), places=14)
        self.assertAlmostEqual(truth.parent[-1,8], .7*np.exp(-.3/4), places=14)
        np.testing.assert_allclose(truth.labels[-1,:3,7]/truth.parent[-1,7], [.7,.2,.1], atol=1e-15)
        self.assertTrue(np.all(truth.parent[-1,9:] > 0))
        self.assertNotEqual(truth.parent[-1,9],truth.parent[-1,10])
        self.assertTrue(closure(truth,self.design)["complete_label_conservation"])
        fields = state_fields(truth,self.design,case)
        amounts = fields["water_parent"][0]*truth.weights
        np.testing.assert_allclose(amounts.sum(axis=1)+fields["precipitation_accumulated"][0][:,0],truth.parent[0].sum(),atol=3e-15)
        self.assertLess(fields["precipitation"][0][-1,0],0)
        np.testing.assert_allclose(sum(fields["precip_"+t["name"]][0] for t in self.design["tags"] if t["partition"]),fields["precipitation"][0],atol=1e-20)
        self.assertEqual(fields["precipitation_accumulated"][1],"kg m^-2")

    def test_reset_isolated_from_own_rain_donor_and_pool(self):
        case, truth = self.state("rain_snow_sedimentation")
        wrong = mutation(self.design,case,truth)
        self.assertTrue(mutation_invariants(wrong,truth,case,self.design)["meets"])
        self.assertTrue(closure(wrong,self.design)["meets"])
        self.assertTrue(closure(wrong,self.design)["complete_label_conservation"])
        self.assertGreater(np.max(np.abs(wrong.labels[-1,:3,9:]-truth.labels[-1,:3,9:])),.01)
        self.assertTrue(any(r["meets"] is False for r in boundary_error_rows(wrong,truth,self.design,case)))
        with self.assertRaises(DataError): pool_replay(self.design,case,64)

    def test_refinement_retained_and_finest_floor_is_measured(self):
        case, truth = self.state("stiff_opposing_floor")
        floors = [floor_result(rk4(self.design,case,n),truth,self.design,case) for n in self.design["substep_ladder"]]
        self.assertFalse(floors[0]["eligible"])
        self.assertTrue(floors[-1]["eligible"])
        self.assertLess(floors[-1]["maximum_fraction_of_tolerance"],floors[1]["maximum_fraction_of_tolerance"])
        wrong = rk4(self.design,case,64);wrong.labels[-1,0,0]+=.1;wrong.labels[-1,1,0]-=.1
        self.assertTrue(closure(wrong,self.design)["meets"])
        self.assertFalse(floor_result(wrong,truth,self.design,case)["eligible"])

    def test_pool_rungs_distinct_from_evolving_donors_and_audit_error(self):
        case, truth = self.state("opposing_net_zero")
        pools = [pool_replay(self.design,case,n) for n in self.design["substep_ladder"]]
        errors = [np.max(np.abs(s.labels-truth.labels)) for s in pools]
        self.assertGreater(errors[0],errors[-1])
        self.assertGreater(np.max(np.abs(pools[0].labels-rk4(self.design,case,1).labels)),1e-3)
        self.assertTrue(all(closure(s,self.design)["meets"] for s in pools))
        audit = audit_report(self.design,case,64)
        self.assertFalse(audit["reference_error"])
        self.assertIn("REPORTED ONLY",audit["decision_status"])
        with self.assertRaises(DataError): rk4(self.design,case,32)

    def test_signed_audit_cancellation_before_tag_sum(self):
        trajectory=np.array([[[0,0],[0,0]],[[1,-1],[-1,1]],[[0,0],[0,0]]],dtype=float)
        np.testing.assert_array_equal(trajectory.sum(axis=1),0)
        activity=signed_audit_activity(trajectory)
        self.assertEqual(activity["per_tag_endpoint_integral"],[0.,0.])
        self.assertEqual(activity["per_tag_variation_integral"],[4.,4.])

    def test_mutation_invariants_reject_parent_overlay_and_other_closed_fault(self):
        case,truth=self.state("single_transfer");wrong=mutation(self.design,case,truth)
        for target in ("parent","overlay","other_origin"):
            changed=copy.deepcopy(wrong)
            if target=="parent":changed.parent[-1,0]*=1.01
            elif target=="overlay":changed.labels[-1,3,0]*=1.01
            else:changed.labels[-1,0,0]+=.01;changed.labels[-1,1,0]-=.01
            self.assertFalse(mutation_invariants(changed,truth,case,self.design)["meets"])

    def test_small_solver_independent_scalar_answer(self):
        result=_exp_action(np.array([[-.8/86400]]),86400,np.array([2.]))
        self.assertAlmostEqual(result[0],2*np.exp(-.8),places=15)


class PlanningTests(unittest.TestCase):
    def test_px25_parent_matrix_effective_key_and_scheme_scope(self):
        base={"microphysics_model":"1M","turbconv":None,"use_sgs_quadrature":True,"microphysics_n_substeps_quadrature":2}
        matrix=px25_matrix(base)
        self.assertEqual((len(matrix["parents"]),len(matrix["tagged_arms"]),matrix["jobs"]),(8,16,24))
        self.assertEqual(matrix["effective_substep_key"],"microphysics_n_substeps_quadrature")
        parents={p["id"] for p in matrix["parents"]}
        self.assertTrue(all(t["parent_id"] in parents for t in matrix["tagged_arms"]))
        nonquad={**base,"use_sgs_quadrature":False,"microphysics_n_substeps":3}
        self.assertEqual(px25_matrix(nonquad)["effective_substep_key"],"microphysics_n_substeps")
        with self.assertRaises(DataError): px25_matrix({**base,"turbconv":"EDMFX"})
        with self.assertRaises(DataError): effective_substep_key({})

    def test_void_bits_short_criteria_and_pending_trend_never_pass(self):
        self.assertTrue(void_substep_perturbation({"x":np.array([0.])},{"x":np.array([0.])})["void"])
        self.assertFalse(void_substep_perturbation({"x":np.array([0.])},{"x":np.array([-0.])})["void"])
        self.assertTrue(all(r["verdict"]=="NOT ASSESSABLE" for r in short_case_rows(1500)))
        trend=proposed_audit_trend([1.,.5,.25])
        self.assertEqual(trend["proposed_reading"],"converging")
        self.assertEqual(trend["verdict"],"NOT ASSESSABLE")
        self.assertIn("zero denominator",proposed_audit_trend([0.,0.,0.])["proposed_reading"])
        # The proposed trend reading's bounds (PART7, OD15 table). Each branch and edge.
        for values,reading in (([1.,.75,.5625],"converging"),([1.,.76,.5],"unresolved"),
                               ([1.,1.11,1.],"growing"),([1.,1.1,1.1],"systematic"),
                               ([1.,.9,.81],"systematic"),([1.,.89,.8],"unresolved"),([1.,.5,.5],"unresolved"),([1.,.5,.6],"growing")):
            with self.subTest(values=values):
                self.assertEqual(proposed_audit_trend(values)["proposed_reading"],reading)
                self.assertEqual(proposed_audit_trend(values)["verdict"],"NOT ASSESSABLE")

    def test_committed_px25_draft_is_the_generators_output_and_stays_a_draft(self):
        committed=Path(__file__).resolve().parents[2]/"configs"/"part7_px25_draft"
        with tempfile.TemporaryDirectory() as scratch:
            matrix=save_px25_draft(Path(scratch)/"draft")
            generated=sorted(p.name for p in (Path(scratch)/"draft").iterdir())
            self.assertEqual(generated,sorted(p.name for p in committed.iterdir()))
            for name in generated:
                self.assertEqual((Path(scratch)/"draft"/name).read_text(),(committed/name).read_text(),name)
        self.assertTrue(matrix["kind"].startswith("DRAFT"))
        self.assertEqual(matrix["OD15_status"],"PROPOSED/PENDING")
        self.assertIn("RICO 1M 24 h is the held-out case",matrix["held_out_overlap"])
        self.assertIn("draft pending the owner",(committed/"README.md").read_text())
        self.assertEqual(len([p for p in committed.iterdir() if p.suffix==".yml"]),24)


class BundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch=tempfile.TemporaryDirectory()
        cls.root=Path(cls.scratch.name)
        cls.base=write_fixture(cls.root/"single","single_transfer")

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def changed(self,manifest=None,evidence=None,archive=None,base=None):
        root=self.root/self.id().split(".")[-1]
        shutil.copytree((base or self.base).parent,root)
        path=root/"manifest.json";value=json.loads(path.read_text())
        if manifest:manifest(value["acceptance"])
        if evidence:
            p=root/value["acceptance"]["reference"]["evidence"]
            detail=json.loads(p.read_text());evidence(detail);write_json(p,detail)
            value["acceptance"]["artifacts"][p.name]=sha256_file(p)
        if archive:
            name,edit=archive;p=root/name
            if p.suffix==".npz":
                with np.load(p,allow_pickle=False) as a:data={n:a[n].copy() for n in a.files}
                edit(data);np.savez(p,**data)
            else:
                data=json.loads(p.read_text());edit(data);write_json(p,data)
            value["acceptance"]["artifacts"][name]=sha256_file(p)
        write_json(path,value)
        return path

    def test_existing_bundle_route_and_closed_origin_mutant(self):
        bundle=Bundle(self.base)
        self.assertEqual(bundle.validate(),[])
        scorer=Scorer(bundle)
        # The scorer reads the producer's declaration. It has no transfer hook.
        eligibility=scorer.reference_eligibility(0,86400)
        self.assertTrue(eligibility["meets"])
        self.assertIn(producer_identity()["sha256"],eligibility["reference_eligibility"])
        measured=evaluate_water_transfer(bundle)
        self.assertEqual(eligibility["metrics"]["floors"],measured["declaration"]["floors"])
        self.assertTrue(measured["declaration"]["converged"])
        self.assertTrue(measured["declaration"]["eligibility_basis"]["converged"].startswith("Measured. No refinement"))
        coverage=scorer.active_rule_coverage()
        self.assertNotIn("verdict",coverage)
        self.assertTrue(coverage["limitation"].startswith("reported, not a gate until OD9"))
        self.assertEqual(coverage["metrics"]["tested_active_rules"],["independent directed compartment donor attribution"])
        report=evaluate_fixture(self.base)
        self.assertEqual(report["candidate_verdict"],"PASS")
        self.assertTrue(report["origin_mutant"]["mutation_verified"])
        self.assertEqual(report["scientific_qualification"],"NOT QUALIFIED")
        json.dumps(report,allow_nan=False)

    def test_native_units_time_weight_geometry_and_missing_channel_fail(self):
        checks=[lambda s:s["runs"]["candidate"]["fields"]["water_R"].update(units="kg m^-2"),
                lambda s:s["runs"]["candidate"]["fields"]["rho"].update(expected_times=[0,3600,86400]),
                lambda s:s["runs"]["candidate"]["fields"]["water_R"].update(weight_units="1"),
                lambda s:s["runs"]["candidate"]["fields"].pop("excluded_activity_edmf")]
        reasons=("embedded units","expected samples","weight units","excluded_activity_edmf")
        for edit,reason in zip(checks,reasons):
            path=self.changed(manifest=edit)
            with self.assertRaisesRegex(DataError,reason):evaluate_water_transfer(Bundle(path))
            shutil.rmtree(path.parent)
        path=self.changed(archive=("candidate.npz",lambda d:d["geometry"].__setitem__((0,1),3.)))
        with self.assertRaisesRegex(DataError,"time/geometry/native weight"):evaluate_water_transfer(Bundle(path))

    def test_full_ladder_shared_scope_evaluator_and_reference_selection_fail(self):
        edits=[(lambda d:d["rungs"].pop(),"transfer ladder"),(lambda d:d.update(shared_rules=["donor"]),"shared"),
               (lambda d:d.update(evaluator_files={}),"stale transfer evaluator"),
               (lambda d:d.update(reference_substeps=16),"pinned configuration"),
               (lambda d:d.update(development_only=False),"reference identity differs")]
        for edit,reason in edits:
            path=self.changed(evidence=edit)
            with self.assertRaisesRegex(DataError,reason):evaluate_water_transfer(Bundle(path))
            shutil.rmtree(path.parent)

    def test_changed_rate_pinned_config_and_model_fail(self):
        path=self.changed(archive=("resolved_config.json",lambda d:d["rates"][0].update(value=1.)))
        with self.assertRaisesRegex(DataError,"pinned configuration/rates"):evaluate_water_transfer(Bundle(path))
        shutil.rmtree(path.parent)
        path=self.changed(evidence=lambda d:d.update(model_commit="0"*40))
        with self.assertRaisesRegex(DataError,"model/design/reference identity"):evaluate_water_transfer(Bundle(path))

    def test_claimed_good_floor_cannot_override_actual_finest_array(self):
        path=self.changed(evidence=lambda d:d.update(converged=True,floor_fraction_of_tolerance=0.,eligible=True),
                          archive=("rk4_s64_native.npz",lambda d:d["labels"].__setitem__((-1,0,0),d["labels"][-1,0,0]+.1)))
        with self.assertRaisesRegex(DataError,"rk4_s64 native labels"):evaluate_water_transfer(Bundle(path))

    def test_missing_real_application_roster_fails_even_with_new_hash(self):
        path=self.changed(archive=("rk4_s64_applications.json",lambda d:d.pop()))
        with self.assertRaisesRegex(DataError,"roster"):evaluate_water_transfer(Bundle(path))

    def test_candidate_directed_water_amounts_cannot_disagree_with_pinned_rates(self):
        for edit,reason in ((lambda d:d["activity"].__imul__(2),"directed water amounts at pinned rates"),
                            (lambda d:d["activity"].__isub__(1),"negative/reset")):
            path=self.changed(archive=("candidate_native.npz",edit))
            self.assertEqual(Bundle(path).validate(),[])
            with self.assertRaisesRegex(DataError,reason):evaluate_water_transfer(Bundle(path))
            shutil.rmtree(path.parent)

    def test_zero_weight_pseudo_roster_cannot_erase_real_candidate_activity(self):
        path=self.changed(archive=("candidate_applications.json",lambda d:d.append(
            {"edge":0,"amount":0.,"sampling":"undeclared zero-weight application"})))
        self.assertEqual(Bundle(path).validate(),[])
        with self.assertRaisesRegex(DataError,"candidate application roster"):
            evaluate_water_transfer(Bundle(path))

    def test_candidate_label_accumulator_must_start_at_zero(self):
        path=self.changed(archive=("candidate_native.npz",lambda d:d["label_activity"].__setitem__((0,0,0),.01)))
        self.assertEqual(Bundle(path).validate(),[])
        with self.assertRaisesRegex(DataError,"initial applied label amount"):
            evaluate_water_transfer(Bundle(path))

    def test_native_label_amounts_must_reconcile_correct_endpoint_fields(self):
        path=self.changed(archive=("candidate_native.npz",lambda d:d["label_activity"].__imul__(.99)))
        twin=path.with_name("manifest_origin_mutant.json")
        spec=json.loads(twin.read_text())
        spec["acceptance"]["artifacts"]["candidate_native.npz"]=sha256_file(path.parent/"candidate_native.npz")
        write_json(twin,spec)
        self.assertEqual(Bundle(path).validate(),[])
        report=evaluate_fixture(path)
        metrics=report["measured_reference"]["metrics"]
        self.assertTrue(all(row["meets"] is not False for row in metrics["candidate_errors"]))
        self.assertTrue(metrics["candidate_application_error"]["meets"])
        self.assertFalse(metrics["candidate_directed_balance"]["meets"])
        self.assertEqual(report["candidate_verdict"],"FAIL")

    def test_checksum_and_precision_fail(self):
        path=self.changed()
        with (path.parent/"candidate.npz").open("ab") as f:f.write(b"fault")
        with self.assertRaisesRegex(DataError,"checksum"):evaluate_water_transfer(Bundle(path))
        shutil.rmtree(path.parent)
        path=self.changed(archive=("candidate_native.npz",lambda d:d.update(labels=d["labels"].astype("float32"))))
        with self.assertRaisesRegex(DataError,"precision"):evaluate_water_transfer(Bundle(path))

    def test_proportional_parent_and_labels_cannot_pass(self):
        path=self.changed()
        value=json.loads(path.read_text())
        for name in ("candidate.npz","candidate_native.npz"):
            p=path.parent/name
            with np.load(p,allow_pickle=False) as a:data={n:a[n].copy() for n in a.files}
            if name.endswith("_native.npz"):
                data["parent"][1:]*=1.01;data["labels"][1:]*=1.01;data["rho"]*=1.01
            else:
                for key in data:
                    if key=="rho":data[key]*=1.01
                    elif key.startswith(("water_","tag_")) and "__" not in key:data[key][1:]*=1.01
            np.savez(p,**data);value["acceptance"]["artifacts"][name]=sha256_file(p)
        write_json(path,value)
        with self.assertRaisesRegex(DataError,"native coordinates/density"):evaluate_water_transfer(Bundle(path))

    def test_paired_applied_precipitation_same_owner_and_empty_registry(self):
        base=write_fixture(self.root/"sedimentation","rain_snow_sedimentation")
        bundle=Bundle(base);paired=paired_precipitation(bundle,0,86400)
        self.assertEqual(VERIFIED_PRODUCERS,{})
        # WA-PRECIP: the paired row is reported accounting, never a verdict.
        self.assertNotIn("verdict",paired)
        self.assertFalse(paired["metrics"]["production_complete"])
        self.assertIn("does not validate precipitation origins",paired["limitation"])
        # The full scorer never scores precipitation provenance as PASS.
        rows=Scorer(bundle).run()["rows"]
        precipitation=[row for row in rows if "PRECIP" in row["id"]]
        self.assertTrue(precipitation)
        self.assertFalse([row for row in precipitation if row["verdict"]=="PASS"])
        parent=bundle.field("candidate","precipitation_accumulated").values[-1,0]
        self.assertAlmostEqual(paired["metrics"]["signed_downward_amount"],parent,places=14)
        self.assertEqual(bundle.field("candidate","precipitation").sampling,"instantaneous")
        report=evaluate_fixture(base)
        self.assertEqual(report["candidate_verdict"],"PASS")
        # The owner-reset control keeps the parent and every total and fails an origin row.
        self.assertTrue(report["origin_mutant"]["mutation_verified"])
        self.assertIn("reported accounting",report["measured_reference"]["metrics"]["paired_precipitation_status"])
        path=self.changed(base=base,archive=("candidate_precip_receipt.json",lambda d:d["steps"][0]["applications"][1].update(application_id="wrong")))
        with self.assertRaisesRegex(DataError,"update/surface"):paired_precipitation(Bundle(path),0,86400)

    def test_zero_activity_donor_coverage_is_not_measured(self):
        path=write_fixture(self.root/"zero","zero_activity")
        report=evaluate_water_transfer(Bundle(path))
        self.assertEqual(report["metrics"]["independent_rules"],[])
        self.assertEqual(report["declaration"]["independent_rules"],[])
        self.assertIn("not applicable",report["metrics"]["donor_rule_applicability"])
        # The floor is measured, but a reference that exercises no donor rule
        # covers none. The scorer reads it as ineligible and the rule as untested.
        self.assertLess(report["declaration"]["floors"]["reference_discretization"],1e-10)
        self.assertFalse(report["meets"])
        scorer=Scorer(Bundle(path))
        self.assertFalse(scorer.reference_eligibility(0,DAY)["meets"])
        coverage=scorer.active_rule_coverage()
        self.assertNotIn("verdict",coverage)
        self.assertFalse(coverage["meets"])
        self.assertEqual(coverage["metrics"]["untested_or_shared_rules"],["independent directed compartment donor attribution"])
        self.assertEqual(evaluate_fixture(path)["candidate_verdict"],"NOT ASSESSABLE")

    def test_erased_exchange_control_and_non_partitioning_applied_labels(self):
        base=write_fixture(self.root/"opposing","opposing_net_zero")
        report=evaluate_fixture(base)
        self.assertEqual(report["candidate_verdict"],"PASS")
        self.assertTrue(report["origin_mutant"]["mutation_verified"])
        # Both opposing edges carry 4% extra origin_a. Labels, closure, directed
        # balance and the 5% applied-share row all stay within their limits.
        def extra(data):
            data["label_activity"][:,0,0]+=.04*data["activity"][:,0]
            data["label_activity"][:,0,1]+=.04*data["activity"][:,1]
        path=self.changed(base=base,archive=("candidate_native.npz",extra))
        twin=path.with_name("manifest_origin_mutant.json")
        spec=json.loads(twin.read_text())
        spec["acceptance"]["artifacts"]["candidate_native.npz"]=sha256_file(path.parent/"candidate_native.npz")
        write_json(twin,spec)
        metrics=evaluate_fixture(path)["measured_reference"]["metrics"]
        self.assertTrue(all(row["meets"] is not False for row in metrics["candidate_errors"]))
        self.assertTrue(metrics["candidate_closure"]["meets"])
        self.assertTrue(metrics["candidate_directed_balance"]["meets"])
        self.assertTrue(metrics["candidate_application_error"]["meets"])
        self.assertFalse(metrics["candidate_applied_partition"]["meets"])
        self.assertEqual(evaluate_fixture(path)["candidate_verdict"],"FAIL")

    def test_scorer_reads_the_declared_file_and_the_producer_refuses_a_changed_one(self):
        def raise_floor(detail):
            detail["floors"]["reference_discretization"]=0.5
        path=self.changed(evidence=raise_floor)
        # The scorer reads the declaration as the decision of 2026-10-07 allows.
        self.assertFalse(Scorer(Bundle(path)).reference_eligibility(0,DAY)["meets"])
        with self.assertRaisesRegex(DataError,"declared eligibility differs"):
            evaluate_water_transfer(Bundle(path))
        shutil.rmtree(path.parent)
        path=self.changed(evidence=lambda d:d.update(independent_rules=[]))
        with self.assertRaisesRegex(DataError,"declared eligibility differs.*independent_rules"):
            evaluate_water_transfer(Bundle(path))

    def test_scorer_refuses_a_declaration_without_its_producer(self):
        path=self.changed(manifest=lambda s:s["reference"].pop("producer"))
        with self.assertRaisesRegex(DataError,"producing script"):
            Scorer(Bundle(path)).reference_eligibility(0,DAY)
        with self.assertRaisesRegex(DataError,"producer"):
            evaluate_water_transfer(Bundle(path))

    def test_fixture_modules_are_not_scorer_files(self):
        self.assertFalse([path for path in SCORER_PATHS if path.startswith("water_transfer")])
        self.assertNotIn("water_transfer", Path(score_acceptance.__file__).read_text())


class DriverExitTests(unittest.TestCase):
    """The driver's exit codes follow the scorer's convention."""

    def setUp(self):
        self.scratch=tempfile.TemporaryDirectory()
        self.root=Path(self.scratch.name)
        self.config=json.loads((Path(__file__).parents[2]/"configs"/"water_transfer_exact.json").read_text())

    def tearDown(self):
        self.scratch.cleanup()

    def main(self,*args):
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            return driver.main([str(arg) for arg in args])

    def test_exit_code_of_suite_rows(self):
        passing={"candidate_verdict":"PASS","mutation_verified":True,"reference_eligible":True}
        self.assertEqual(suite_exit_code([passing]),0)
        self.assertEqual(suite_exit_code([passing,{**passing,"candidate_verdict":"NOT ASSESSABLE",
                                                   "mutation_verified":None,"reference_eligible":False}]),3)
        self.assertEqual(suite_exit_code([passing,{**passing,"candidate_verdict":"FAIL"}]),1)
        self.assertEqual(suite_exit_code([{**passing,"mutation_verified":False}]),1)

    def test_main_maps_failures_to_the_scorer_codes(self):
        config=self.root/"config.json"
        write_json(config,{**self.config,"design_sha256":"0"*64})
        self.assertEqual(self.main(self.root/"bad_config","--config",config),2)
        self.assertEqual(self.main(self.root/"missing_config","--config",self.root/"absent.json"),2)
        self.assertEqual(self.main(self.root,"--config",config),4)
        self.assertEqual(self.main(self.root/"no_option"),4)
        with mock.patch.object(driver,"run_suite",side_effect=RuntimeError("driver bug")):
            self.assertEqual(self.main(self.root/"driver_error","--config",config),4)
        with mock.patch.object(driver,"run_suite",return_value={"exit_code":3}):
            self.assertEqual(self.main(self.root/"ineligible","--config",config),3)

    def test_restart_reader_deduplicates_exact_boundary_and_requires_reset(self):
        def field(times,values):
            return Field(np.array(times,dtype=float),np.array(values,dtype=float)[:,None],np.ones(1),np.zeros((1,1)),
                         "kg m^-2","amount","cumulative","1",("scalar",),(),"accepted_applied_precipitation")
        first=field([0,1],[0,2]);second=field([1,2],[0,3])
        segments=[{"id":"a","output_checkpoint":"checkpoint","accumulators":{"p":{"mode":"continued"}}},
                  {"id":"b","parent_id":"a","input_checkpoint":"checkpoint","accumulators":{"p":{"mode":"reset","offset":[2.]}}}]
        result=stitch([first,second],segments,"p")
        np.testing.assert_array_equal(result.values[:,0],[0,2,5])
        wrong=copy.deepcopy(segments);wrong[1]["accumulators"]["p"]={"mode":"continued"}
        with self.assertRaisesRegex(DataError,"boundary changed"):stitch([first,second],wrong,"p")
        with self.assertRaisesRegex(DataError,"duplicate"):stitch([first,field([1,1],[2,3])],segments,"p")
        wrong=copy.deepcopy(segments);wrong[1]["input_checkpoint"]="different"
        with self.assertRaisesRegex(DataError,"checkpoints"):stitch([first,second],wrong,"p")


if __name__=="__main__":
    unittest.main()
