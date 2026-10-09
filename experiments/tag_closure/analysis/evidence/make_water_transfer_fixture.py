"""Archive every independent transfer rung in existing-format development Bundles.

    python3 make_water_transfer_fixture.py NEW_DIRECTORY --config ../../configs/water_transfer_exact.json

Synthetic prescribed rates do not validate a model rate or complete PX14/PX25.
Existing outputs are refused. Failed references are retained and never ranked.

Exit codes follow the scorer's. 0: every case's checks passed with an
eligible reference. 1: a fixture check failed. 2: evidence is missing,
corrupt or inconsistent. 3: a selected reference is ineligible, so its
candidate is not assessable. 4: nothing was evaluated. The output exists,
the command line is invalid, or the driver itself raised an error.
"""

import argparse
import copy
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from acceptance_data import Bundle, DataError, require, same_bits
from manifest import sha256_file
from score_acceptance import DAY, Scorer, local_identities
from water_transfer_adapter import (DECLARED_FIELDS,FIXTURE_SCOPE,SOURCE_FILES,evaluate_water_transfer,
    EXACT_INTERVAL_CONVENTION,evaluator_identities,producer_identity,read_native,regenerate,rungs)
from water_transfer_reference import (BASE_COMMIT,DESIGN_PATH,DESIGN_SHA256,
    audit_report,case_by_id,closure,exact,load_design,mutation,mutation_invariants,
    rule_for,state_fields)


def write_json(path,value):
    Path(path).write_text(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+"\n")


def archive_state(root,role,state,design,case,excluded=False):
    fields={};data={"time":state.time,"time_units":np.array("s"),"geometry":state.geometry,
                   "weights":state.weights,"weight_units":np.array("m"),
                   "scalar_geometry":np.zeros((1,1)),"scalar_weights":np.ones(1),"scalar_weight_units":np.array("1")}
    definitions=state_fields(state,design,case)
    if excluded:
        for process in design["excluded_processes"]:
            definitions["excluded_activity_"+process]=(np.zeros_like(definitions["water_parent"][0]),"kg m^-3","density","cumulative","native")
    for name,(values,units,representation,sampling,kind) in definitions.items():
        prefix="scalar_" if kind=="scalar" else ""
        dimensions=["scalar"] if kind=="scalar" else ["z"]
        data[name]=values
        for attr,value in (("units",units),("representation",representation),("sampling",sampling),("dimensions",dimensions)):
            data[name+"__"+attr]=np.asarray(value)
        descriptor={"path":role+".npz","key":name,"units":units,"representation":representation,"sampling":sampling,
                    "dimensions":dimensions,"expected_times":state.time.tolist(),"weights_key":prefix+"weights",
                    "weight_units_key":prefix+"weight_units","geometry_key":prefix+"geometry","weight_units":"1" if prefix else "m"}
        if name.startswith("precipitation_accumulated"):
            descriptor["accumulator_kind"]="accepted_applied_precipitation"
        fields[name]=descriptor
    np.savez(root/(role+".npz"),**data)
    np.savez(root/(role+"_native.npz"),**{name:getattr(state,name) for name in ("time","faces","rho","parent","labels","activity","label_activity")})
    write_json(root/(role+"_applications.json"),state.applications)
    return fields



def paired_precipitation_section(root, prefix, state, design, case, submission):
    """Exact integrated synthetic amounts with one matched accepted application.

    The rate is the independently integrated amount divided by its declared
    interval. It is not a quadrature of the instantaneous output snapshots.
    The existing production gate remains blocked because kind is synthetic.
    """
    n=state.internal_count
    exports={"parent":state.parent[:,n:].sum(axis=1)}
    for i,tag in enumerate(design["tags"]):
        if tag["partition"]: exports[tag["name"]]=state.labels[:,i,n:].sum(axis=1)
    receipt={"schema_version":1,"kind":"synthetic","semantics":"weighted_final_additive_updates",
             "model_commit":BASE_COMMIT,"model_diff_sha256":submission["diff_sha256"],
             "integrator_pin":{"algorithm":"unconstrained_imex_ark","package":"ClimaTimeSteppers",
                               "version":"synthetic-independent-integrated-transfer","b_exp":[1.],"b_imp":[1.],"implicit_diagonal":[1.]},
             "steps":[]}
    native={"weights":np.ones(1),"geometry":np.zeros((1,1)),"weight_units":np.array("1")}
    channels={}
    for name,values in exports.items():
        rates=(-np.diff(values)/np.diff(state.time))[:,None]
        record_ids=[]
        for j,(left,right) in enumerate(zip(state.time,state.time[1:])):
            if len(receipt["steps"])<=j:
                receipt["steps"].append({"id":f"step{j}","start_seconds":float(left),"end_seconds":float(right),
                    "accepted_trial":f"trial{j}","trials":[{"id":f"trial{j}","decision":"accepted"}],"applications":[]})
            rid=f"{name}.{j}";record_ids.append(rid)
            receipt["steps"][j]["applications"].append({"channel":name,"record_id":rid,"trial":f"trial{j}",
                "application_id":f"boundary{j}","evaluation_id":f"integrated{j}","disposition":"applied","role":"explicit",
                "stage":1,"coefficient":float(right-left),"coefficient_units":"s"})
        native[name+"__values"]=rates
        native[name+"__record_ids"]=np.asarray(record_ids)
        native[name+"__quantity"]=np.array("precipitation_flux")
        native[name+"__units"]=np.array("kg m^-2 s^-1")
        native[name+"__event_scale"]=np.abs(np.diff(exports["parent"]))[:,None]
        for counter in ("fallback","bound","clamp","zero_normalization"):
            native[name+"__"+counter]=np.zeros_like(rates,dtype=np.int64)
        channels[name]={"path":prefix+"_precip_apps.npz","prefix":name,"quantity":"precipitation_flux","units":"kg m^-2 s^-1"}
    np.savez(root/(prefix+"_precip_apps.npz"),**native)
    write_json(root/(prefix+"_precip_receipt.json"),receipt)
    return {"schema_version":1,"receipt":prefix+"_precip_receipt.json","channels":channels,"sign_convention":"upward_positive"}


# Written after the artifact inventory, so they are not listed in it. The
# mutant's evidence is listed only in the mutant manifest.
MANIFEST_FILES=("manifest.json","manifest_origin_mutant.json","transfer_mutant_evidence.json")


def write_manifests(root,submission,spec,detail,runs,paired):
    write_json(root/"transfer_reference_evidence.json",detail)
    changed=copy.deepcopy(detail)
    changed["native_archives"]["candidate"]=detail["native_archives"]["origin_mutant"]
    changed["application_archives"]["candidate"]=detail["application_archives"]["origin_mutant"]
    write_json(root/"transfer_mutant_evidence.json",changed)
    spec["artifacts"]={p.name:sha256_file(p) for p in sorted(root.iterdir()) if p.is_file() and p.name not in MANIFEST_FILES}
    write_json(root/"manifest.json",{**submission,"acceptance":spec})
    mutant=copy.deepcopy(spec);mutant["runs"]["candidate"]=copy.deepcopy(runs["origin_mutant"]);mutant["runs"]["candidate"].pop("manifest",None)
    mutant["reference"]["evidence"]="transfer_mutant_evidence.json"
    if paired: mutant["precipitation_applications"] = paired["origin_mutant"]
    mutant["artifacts"]["transfer_mutant_evidence.json"]=sha256_file(root/"transfer_mutant_evidence.json")
    write_json(root/"manifest_origin_mutant.json",{**submission,"acceptance":mutant})


def write_fixture(root,case_id,reference_mode="exact",reference_substeps=64):
    root=Path(root);root.mkdir(parents=True,exist_ok=False)
    design=load_design();case=case_by_id(design,case_id);truth=exact(design,case)
    require(reference_mode in ("exact","rk4") and reference_substeps==64,"unregistered transfer reference selection")
    config={"schema_version":1,"scope":FIXTURE_SCOPE,"case_id":case_id,"reference_mode":reference_mode,
            "reference_substeps":reference_substeps,"design_sha256":DESIGN_SHA256,"rates":case["edges"]}
    write_json(root/"resolved_config.json",config);shutil.copyfile(DESIGN_PATH,root/DESIGN_PATH.name)
    sources={}
    for name in SOURCE_FILES:
        dest=root/("source_"+name);shutil.copyfile(Path(__file__).with_name(name),dest);sources[name]=dest.name
    declarations=rungs(design,case);states={}
    for rung in declarations: states[rung["role"]]=regenerate(design,case,rung)
    states.update(candidate=truth,untagged=truth,reference=truth if reference_mode=="exact" else states["rk4_s64"],
                  origin_mutant=mutation(design,case,truth))
    runs={role:{"fields":archive_state(root,role,state,design,case,role in ("candidate","origin_mutant"))}
          for role,state in states.items()}
    # No model runs, so there is no working-tree diff. The scorer files are
    # pinned by their SHA256 in the acceptance extension.
    patch="offline fixture, scorer identity pinned by SHA256\n"
    identities=evaluator_identities()
    submission={"head_sha":BASE_COMMIT,"status_lines":["offline partial source materialization, no local git branch"],
                "diff":patch,"diff_sha256":hashlib.sha256(patch.encode()).hexdigest(),
                "untracked":{"count":len(SOURCE_FILES),"files":[{"path":name,"sha256":identities[name]} for name in SOURCE_FILES]},
                "config":{"path":"resolved_config.json","sha256":sha256_file(root/"resolved_config.json")},
                "buildkite_files":{},"julia_version":"not executed, offline Python transfer fixture",
                "hostname":"offline-known-answer-fixture","env_vars":{},"julia_binary":"not executed","julia_channel":"not executed",
                "loaded_modules":[],"model_runtime_executed":False}
    write_json(root/"submission.json",submission)
    for role,run in runs.items():
        if role!="candidate": run.update(manifest="submission.json",model_commit=BASE_COMMIT,config_sha256=submission["config"]["sha256"])
    detail={"schema_version":1,"development_only":True,"identity":design["identity"],"case_id":case_id,
            "design":DESIGN_PATH.name,"design_sha256":DESIGN_SHA256,"config":"resolved_config.json","model_commit":BASE_COMMIT,
            "evaluator_files":identities,"sources":sources,"end_seconds":86400,"active_rules":[rule_for(case)],
            "tag_names":[tag["name"] for tag in design["tags"]],
            "independent_rules":[rule_for(case)],"shared_rules":[],"reference_mode":reference_mode,
            "reference_substeps":reference_substeps,"rungs":declarations,
            "candidate_convention":EXACT_INTERVAL_CONVENTION,
            "native_archives":{role:role+"_native.npz" for role in states},
            "application_archives":{role:role+"_applications.json" for role in states}}
    paired = {role:paired_precipitation_section(root,role,states[role],design,case,submission)
              for role in ("candidate","origin_mutant")} if case.get("boundary_sinks") else {}
    parent_names=("rho","water_parent","water_N","water_R","water_S")
    exported={role:state_fields(states[role],design,case) for role in ("candidate","reference","untagged")}
    same_parent=all(same_bits(exported["candidate"][name][0],exported[role][name][0])
                    for role in ("reference","untagged") for name in parent_names)
    spec={"schema_version":1,"experiment_commit":"local-uncommitted","scorer_commit":"local-uncommitted","planning_commit":BASE_COMMIT,
          **local_identities(),"submission_files":{"config":"resolved_config.json",**sources},
          "resolved_settings":{"solver":"independent closed forms/Taylor/RK4","seed":"none","physics":case,
                               "diagnostics":list(runs["candidate"]["fields"]),"tag_definitions":design["tags"],"fixture_only":True},
          "precision":"Float64","process_count":1,"geometry_kind":"column","case":case_id,
          "claim":{"family":"water","scope":FIXTURE_SCOPE,"precipitation":bool(case.get("boundary_sinks"))},
          "runs":runs,"tags":design["tags"],"required_parent_fields":list(parent_names),
          "parent_capture_scope":"exported","same_parent_comparisons":same_parent,"end_seconds":86400,
          "profile_times":[3600,86400],"active_rules":[rule_for(case)],
          "reference":{"kind":"water_transfer","identity":design["identity"],"evidence":"transfer_reference_evidence.json",
                       "producer":producer_identity()}}
    if paired: spec["precipitation_applications"] = paired["candidate"]
    write_manifests(root,submission,spec,detail,runs,paired)
    # The producer measures the finished rungs, then declares the eligibility
    # file that the scorer's own reader reads. The inventory is then rewritten.
    measured=evaluate_water_transfer(Bundle(root/"manifest.json"),declared=False)
    detail.update({key:measured["declaration"][key] for key in DECLARED_FIELDS})
    write_manifests(root,submission,spec,detail,runs,paired)
    return root/"manifest.json"


def evaluate_fixture(path):
    bundle=Bundle(path);result=evaluate_water_transfer(bundle)
    # The producer's internal check, then the scorer's reading of the declaration.
    eligibility=Scorer(bundle).reference_eligibility(0,DAY)
    require(eligibility["meets"]==result["meets"],"the scorer's reading of the declaration differs from the producer's")
    mutant_bundle=Bundle(Path(path).with_name("manifest_origin_mutant.json"));control=evaluate_water_transfer(mutant_bundle)
    design=load_design();case=case_by_id(design,bundle.spec["case"]);truth=exact(design,case)
    def read(b):
        detail=json.loads(b.artifact(b.spec["reference"]["evidence"]).read_text())
        return read_native(b,"candidate",truth,design,case,detail)
    baseline,mutant=read(bundle),read(mutant_bundle)
    invariants=mutation_invariants(mutant,baseline,case,design)
    errors=result["metrics"]["candidate_errors"];mutant_errors=control["metrics"]["candidate_errors"]
    fails=any(row["meets"] is False and row["tag"].startswith("origin_") for row in mutant_errors)
    mc=result["metrics"]["candidate_closure"]
    verdict="PASS" if (mc["meets"] and mc["complete_label_conservation"] and
                         result["metrics"]["candidate_parent_trajectory"]["meets"] and
                         result["metrics"]["candidate_directed_balance"]["meets"] and
                         result["metrics"]["candidate_applied_partition"]["meets"] and
                         all(row["meets"] is not False for row in errors) and
                         all(row["meets"] is not False for row in result["metrics"]["boundary_label_errors"]) and
                         result["metrics"]["candidate_application_error"]["meets"] is not False) else "FAIL"
    mutation_verified=bool(invariants["meets"] and control["metrics"]["candidate_closure"]["meets"] and
                           control["metrics"]["candidate_parent_trajectory"]["meets"] and fails)
    audit=[audit_report(design,case,count) for count in design["substep_ladder"]] if case["kind"]=="constant" else []
    bundle.reverify();mutant_bundle.reverify()
    return {"schema_version":1,"case_id":case["id"],"scope":FIXTURE_SCOPE,"scientific_qualification":"NOT QUALIFIED",
            "measured_reference":result,"scorer_reference_eligibility":eligibility,"candidate_verdict":verdict if result["meets"] else "NOT ASSESSABLE",
            "origin_mutant":{"invariants":invariants,"errors":mutant_errors,"closure":control["metrics"]["candidate_closure"],
                             "application_error":control["metrics"]["candidate_application_error"],"origin_failure_measured":fails,
                             "directed_balance":control["metrics"]["candidate_directed_balance"],
                             "mutation_verified":mutation_verified if result["meets"] else None},
            "audit_rule_spread":audit,"runtime_minima_corrections_fallback_bounds":"missing actual native channels, NOT ASSESSABLE",
            "OD15_campaign_status":"BLOCKED, proposed owner choices not supplied","artifacts":dict(sorted(bundle.used.items()))}


def run_suite(root,config):
    design=load_design()
    require(config.get("schema_version")==1 and config.get("scope")==FIXTURE_SCOPE and config.get("design_sha256")==DESIGN_SHA256 and
            config.get("case_ids")==[c["id"] for c in design["cases"]] and config.get("retain_all_rungs") is True and
            config.get("reference_substeps")==64 and config.get("reference_mode") in ("exact","rk4"),
            "suite configuration does not match complete frozen scope")
    root=Path(root);root.mkdir(parents=True,exist_ok=False);write_json(root/"suite_config.json",config)
    cases=[]
    for case_id in config["case_ids"]:
        manifest=write_fixture(root/case_id,case_id,config["reference_mode"],64)
        result=evaluate_fixture(manifest);write_json(manifest.with_name("known_answer_results.json"),result)
        cases.append({"case_id":case_id,"reference_eligible":result["measured_reference"]["meets"],
                      "rule_coverage":result["measured_reference"]["rule_coverage"],
                      "floor_eligible":result["measured_reference"]["floor_eligible"],
                      "candidate_verdict":result["candidate_verdict"],"mutation_verified":result["origin_mutant"]["mutation_verified"],
                      "floor_fraction":result["measured_reference"]["metrics"]["floor_fraction_of_tolerance"],
                      "result":case_id+"/known_answer_results.json"})
    exit_code=suite_exit_code(cases)
    report={"schema_version":1,"design_sha256":DESIGN_SHA256,"cases":cases,"exit_code":exit_code,"scope":FIXTURE_SCOPE,
            "scientific_qualification":"NOT QUALIFIED","limitation":"synthetic rates/equations, runtime/PX14/PX25/OD15/held-out/EDMF/copies gates remain open"}
    write_json(root/"suite_results.json",report);return report


def suite_exit_code(cases):
    """1 for a failed check, else 3 for an ineligible reference, else 0.

    A case the design expects to cover no rule is not applicable (decision of
    2026-10-09). It stays NOT ASSESSABLE in the results and does not make the
    suite exit 3, provided its floors are eligible.
    """
    if any(c["candidate_verdict"]=="FAIL" or c["mutation_verified"] is False for c in cases):
        return 1
    def counted_eligible(c):
        if c.get("rule_coverage","measured")!="measured":
            return c["floor_eligible"] is True
        return c["reference_eligible"]
    return 3 if any(not counted_eligible(c) for c in cases) else 0


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory");parser.add_argument("--config",required=True)
    try:
        args=parser.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code==0 else 4
    if Path(args.directory).exists():
        print("not evaluated: the output directory exists. Choose a new one",file=sys.stderr)
        return 4
    try:
        report=run_suite(args.directory,json.loads(Path(args.config).read_text()))
    except (DataError,json.JSONDecodeError,UnicodeDecodeError,OSError) as exc:
        print("DATA FAILURE: "+str(exc),file=sys.stderr)
        return 2
    except Exception as exc:  # A driver error is reported as such, never as bad data.
        print(f"DRIVER ERROR: {type(exc).__name__}: {exc}",file=sys.stderr)
        return 4
    print(json.dumps(report,sort_keys=True,indent=2));return report["exit_code"]


if __name__=="__main__":
    raise SystemExit(main())
