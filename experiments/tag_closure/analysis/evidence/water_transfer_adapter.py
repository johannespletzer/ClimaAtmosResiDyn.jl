"""Produce and check the declared eligibility of the water-transfer fixtures.

This module is the producing script that a transfer fixture's manifest names
and hashes. It reconstructs the equations and every archived rung, measures
the rung-64 floor in each applicable norm and writes the declared eligibility
that the scorer's own eligibility reader reads. Rerun on a finished bundle, it
is the producer's internal check: it refuses a declaration that differs from
its recompute. The scorer itself does not import this module.

Metadata cannot certify a runtime producer, replay rates, unsupported
EDMF/copies, OD15 or held-out independence.
"""

import json
from pathlib import Path

import numpy as np

from acceptance_data import aligned, density, require, same_bits, window
from manifest import sha256_file
from score_acceptance import FLOOR_FRACTION_MAX, SECOND_HALF_TIE, local_identities
from water_transfer_reference import (BASE_COMMIT, DESIGN_SHA256, TransferState,
    PARTS, application_error, boundary_error_rows, case_by_id, closure, directed_balance, error_rows, exact, floor_result,
    load_design, parent_trajectory, pool_replay, rk4, rule_for, state_fields)

FIXTURE_SCOPE = "preregistered independent water-transfer development fixture"
EXACT_INTERVAL_CONVENTION = "exact integrated synthetic intervals from native accumulators"
SOURCE_FILES = ("water_transfer_reference.py", "water_transfer_adapter.py", "make_water_transfer_fixture.py")
PRODUCER = "water_transfer_adapter.py"
# The fields this producer declares in the evidence file. The scorer reads
# independent_rules, producer, floors, converged, mirrors_complete and
# jacobian_complete. The basis fields say what each value rests on.
DECLARED_FIELDS = ("independent_rules", "producer", "floors", "floor_basis", "converged",
                   "mirrors_complete", "jacobian_complete", "eligibility_basis")
STATED_FLOORS = {
    "source_injection": "Stated, not measured. The frozen equations have no source term. "
                        "Source overlays are initial labels, not injected water.",
    "initialization": "Stated, not measured. The producer refuses a candidate whose initial parent "
                      "and labels differ from the frozen initial amounts by more than the roundoff allowance.",
    "parent_solve": "Stated, not measured. Fixed-rate cases prescribe the parent in closed form. In the "
                    "kinetic cases the RK4 reference integrates the parent, and that error is inside its "
                    "reference-discretization floor.",
    "contamination": "Stated, not measured. No other process acts. Every excluded process reads a zero "
                     "cumulative array in the candidate.",
}
# A floor that rises by at most this much along the substep ladder is a tie,
# not a rise. This is Part 6's ladder rule (decision of 2026-10-08), reused.
LADDER_TIE = SECOND_HALF_TIE


def evaluator_identities():
    return {name:sha256_file(Path(__file__).with_name(name)) for name in SOURCE_FILES}


def producer_identity():
    return {"script": PRODUCER, "sha256": sha256_file(Path(__file__))}


def converges(values, tie=LADDER_TIE):
    """True when no refinement step toward rung 64 raises the floor by more than the tie."""
    return not any(later > earlier + tie for earlier, later in zip(values, values[1:]))


def applied_partition(state, design):
    """Each directed water amount equals the sum of its applied partition labels.

    Endpoint profiles, closure and directed balance see only net changes. Two
    opposing edges that both carry extra label of one origin leave all three
    unchanged. This arithmetic check compares each edge's cumulative applied
    partition labels with its applied water, at the roundoff allowance.
    """
    partition = [i for i, tag in enumerate(design["tags"]) if tag["partition"]]
    if not state.activity.size:
        return {"meets": True, "max_defect_over_allowance": 0.0, "units": "kg m^-2"}
    amount = state.activity - state.activity[0]
    carried = state.label_activity[:, partition, :] - state.label_activity[:1, partition, :]
    error = np.abs(carried.sum(axis=1) - amount)
    allowance = (design["profile_rules"]["roundoff_multiplier"] * np.finfo(float).eps *
                 (np.abs(carried).sum(axis=1) + np.abs(amount)))
    ratio = np.divide(error, allowance, out=np.where(error > 0, np.inf, 0.0), where=allowance > 0)
    return {"meets": bool(np.all(error <= allowance)), "max_defect_over_allowance": float(np.max(ratio)),
            "max_absolute_defect": float(np.max(error)), "units": "kg m^-2",
            "scope": "arithmetic consistency of applied partition labels with applied water, per directed edge"}


def rungs(design,case):
    result=[]
    for count in design["substep_ladder"]:
        result.append({"kind":"rk4","substeps":count,"role":f"rk4_s{count}"})
        if case["kind"] == "constant":
            result.append({"kind":"pool_diagnostic","substeps":count,"role":f"pool_s{count}"})
    return result


def regenerate(design,case,rung):
    return rk4(design,case,rung["substeps"]) if rung["kind"]=="rk4" else pool_replay(design,case,rung["substeps"])


def _match(a,b,design,label):
    require(a.shape==b.shape and a.dtype==b.dtype, label+": shape/precision differs")
    limit=design["profile_rules"]["roundoff_multiplier"]*np.finfo(float).eps*np.abs(b)
    require(np.isfinite(a).all() and np.all(np.abs(a-b)<=limit), label+": archived values do not reproduce independent equations")


def read_native(bundle,role,truth,design,case,detail):
    fields=state_fields(truth,design,case)
    values={}
    rho=bundle.field(role,"rho")
    require((rho.units,rho.representation,rho.sampling,rho.weight_units,rho.dimensions)==
            ("kg m^-3","density","instantaneous","m",("z",)),"transfer native density convention differs")
    require(rho.values.dtype==np.dtype("float64") and same_bits(rho.time,truth.time) and
            same_bits(rho.geometry,truth.geometry) and same_bits(rho.weights,truth.weights),
            "transfer time/geometry/native weight/precision differs")
    for name,(_,units,representation,sampling,kind) in fields.items():
        f=bundle.field(role,name)
        require(f.values.dtype==np.dtype("float64") and same_bits(f.time,truth.time),name+": native time/precision differs")
        if kind=="native":
            aligned(f,rho,"transfer native "+name)
            require((f.units,f.representation) in ((units,representation),("kg kg^-1","specific")),
                    name+": native units/representation differs")
            require(f.sampling==sampling,name+": sample semantics differ")
            values[name]=density(f,rho)
        else:
            require((f.units,f.representation,f.sampling,f.weight_units,f.dimensions)==
                    (units,representation,sampling,"1",("scalar",)) and
                    same_bits(f.weights,np.ones(1)) and same_bits(f.geometry,np.zeros((1,1))),
                    name+": integrated boundary/flux cannot use native thickness or changed signs/units")
            values[name]=f.values
    levels=len(truth.weights);n=3*levels
    parent=np.zeros_like(truth.parent);labels=np.zeros_like(truth.labels)
    for j,part in enumerate(PARTS):
        parent[:,j:n:3]=values["water_"+part]*truth.weights
        for i,tag in enumerate(design["tags"]):
            labels[:,i,j:n:3]=values["tag_"+tag["name"]+"_"+part]*truth.weights
    for sink in case.get("boundary_sinks",[]):
        index,species=sink["index"],sink["species"]
        parent[:,index]=values["export_water_"+species][:,0]
        for i,tag in enumerate(design["tags"]): labels[:,i,index]=values["export_"+tag["name"]+"_"+species][:,0]
    state=TransferState(truth.time,truth.faces,values["rho"][0],parent,labels,
                        np.zeros_like(truth.activity),np.zeros_like(truth.label_activity),{},[])
    # Derived totals and both precipitation readings must match the same owner.
    derived=state_fields(state,design,case)
    for name in fields:
        _match(values[name],derived[name][0],design,role+":"+name)
    native=detail.get("native_archives",{}).get(role)
    require(isinstance(native,str),"missing directed applied native archive")
    with np.load(bundle.artifact(native),allow_pickle=False) as a:
        require(set(a.files)=={"time","faces","rho","parent","labels","activity","label_activity"},
                "incomplete/extra directed native transfer layout")
        for name in ("time","faces","rho","parent","labels"):
            _match(a[name],getattr(state,name),design,role+" native "+name)
        require(a["activity"].shape==truth.activity.shape and a["label_activity"].shape==truth.label_activity.shape and
                a["activity"].dtype==a["label_activity"].dtype==np.dtype("float64"),"directed activity scope/precision differs")
        state.parent,state.labels=a["parent"].copy(),a["labels"].copy()
        state.activity,state.label_activity=a["activity"].copy(),a["label_activity"].copy()
        require(np.isfinite(state.activity).all() and np.all(state.activity>=0) and
                np.all(state.activity[0]==0) and np.all(np.diff(state.activity,axis=0)>=0),
                "negative/reset/nonfinite applied directed amount")
        require(np.isfinite(state.label_activity).all() and np.all(state.label_activity[0]==0),
                "nonfinite/nonzero initial applied label amount")
    app_path=detail.get("application_archives",{}).get(role)
    apps=json.loads(bundle.artifact(app_path).read_text())
    require(isinstance(apps,list),"invalid synthetic application archive")
    state.applications=apps
    return state


def matches(actual,expected,design,role):
    for name in ("parent","labels","activity","label_activity"):
        _match(getattr(actual,name),getattr(expected,name),design,role+" "+name)
    require(actual.applications==expected.applications,role+": wrong/incomplete applied-stage roster or donor sampling")


def evaluate_water_transfer(bundle, declared=True):
    """Measure the fixture's eligibility from its archived rungs.

    With `declared`, the evidence file must hold this producer's declaration
    and it must equal the recompute. The producer itself runs with
    `declared=False` before it writes the declaration. The declaration covers
    the claim's whole day.
    """
    start, end = 0, 86400
    spec=bundle.spec;ref=spec.get("reference",{})
    require(ref.get("kind")=="water_transfer","wrong transfer reference route")
    detail=json.loads(bundle.artifact(ref.get("evidence")).read_text())
    design=load_design(bundle.artifact(detail.get("design")))
    case=case_by_id(design,detail.get("case_id"))
    require(spec.get("claim")=={"family":"water","scope":FIXTURE_SCOPE,"precipitation":bool(case.get("boundary_sinks"))},
            "transfer reference has development-only fixed scope")
    require(spec.get("case")==case["id"] and spec.get("resolved_settings",{}).get("physics")==case and
            spec.get("resolved_settings",{}).get("tag_definitions")==design["tags"] and spec.get("tags")==design["tags"] and
            detail.get("tag_names")==[tag["name"] for tag in design["tags"]],
            "transfer case/rates/tag kind/count differs")
    require(spec.get("precision")=="Float64" and spec.get("geometry_kind")=="column" and
            spec.get("end_seconds")==86400 and detail.get("end_seconds")==86400,
            "transfer reference precision/geometry/time scope differs")
    rule=rule_for(case)
    require(spec.get("active_rules")==detail.get("active_rules")==[rule] and
            detail.get("shared_rules")==[],"transfer active/shared/independent coverage differs")
    require(detail.get("development_only") is True and detail.get("schema_version")==1 and
            detail.get("identity")==ref.get("identity")==design["identity"] and
            detail.get("design_sha256")==DESIGN_SHA256 and
            detail.get("model_commit")==bundle.manifest.get("head_sha")==BASE_COMMIT,
            "transfer model/design/reference identity differs")
    require(detail.get("evaluator_files")==evaluator_identities(),"stale transfer evaluator identity")
    require(set(detail.get("sources",{}))==set(SOURCE_FILES),"incomplete transfer evaluator source roster")
    for name,path in detail["sources"].items():
        require(sha256_file(bundle.artifact(path))==evaluator_identities()[name],"archived transfer source differs")
    config=json.loads(bundle.artifact(detail.get("config")).read_text())
    expected_config={"schema_version":1,"scope":FIXTURE_SCOPE,"case_id":case["id"],"reference_mode":detail.get("reference_mode"),
                     "reference_substeps":detail.get("reference_substeps"),"design_sha256":DESIGN_SHA256,"rates":case["edges"]}
    require(config==expected_config and sha256_file(bundle.artifact(detail["config"]))==bundle.manifest.get("config",{}).get("sha256"),
            "transfer pinned configuration/rates differs")
    for name,value in local_identities().items(): require(spec.get(name)==value,"stale existing "+name)
    validation=bundle.validate()
    require(not validation,"invalid existing transfer Bundle: "+". ".join(validation))
    truth=exact(design,case);window(truth.time,start,end)
    candidate=read_native(bundle,"candidate",truth,design,case,detail)
    require(detail.get("candidate_convention")==EXACT_INTERVAL_CONVENTION and
            candidate.applications==[],"candidate application roster differs from exact integrated interval convention")
    _match(candidate.activity,truth.activity,design,"candidate directed water amounts at pinned rates")
    for name in ("parent","labels"):
        _match(getattr(candidate,name)[0],getattr(truth,name)[0],design,"candidate preregistered initial condition")
    for process in design["excluded_processes"]:
        f=bundle.field("candidate","excluded_activity_"+process)
        aligned(f,bundle.field("candidate","water_parent"),"excluded transfer rule")
        require((f.units,f.representation,f.sampling)==("kg m^-3","density","cumulative") and
                np.array_equal(f.values,np.zeros_like(f.values)),"active excluded transfer process: "+process)
    declared_rungs=rungs(design,case)
    require(detail.get("rungs")==declared_rungs,"incomplete/changed 1/4/16/64 transfer ladder")
    states,floors,spread={},{},[]
    for rung in declared_rungs:
        expected=regenerate(design,case,rung)
        actual=read_native(bundle,rung["role"],expected,design,case,detail)
        matches(actual,expected,design,rung["role"])
        measurement=floor_result(actual,truth,design,case)
        states[rung["role"]]=actual
        if rung["kind"]=="rk4": floors[rung["role"]]={**rung,**measurement}
        else: spread.append({**rung,**measurement,"comparison_kind":"declared pool rule error against independent equation"})
    require(detail.get("reference_substeps")==64,"reference selection outside fixed registered support")
    mode=detail.get("reference_mode")
    require(mode in ("exact","rk4"),"unsupported transfer reference mode")
    reference=read_native(bundle,"reference",truth,design,case,detail)
    expected_reference=truth if mode=="exact" else states["rk4_s64"]
    matches(reference,expected_reference,design,"selected reference")
    selected=floors["rk4_s64"]
    # The design's floor is rung 64 in both modes. A rung that does not conserve
    # its own water and labels is a broken reference, not an ineligible one.
    require(selected["closure"]["meets"] and selected["closure"]["complete_label_conservation"] and
            selected["directed_balance"]["meets"],
            "the rung-64 reference does not conserve its water and labels")
    floor=selected["maximum_fraction_of_tolerance"]
    require(floor is not None and np.isfinite(floor),"the rung-64 floor has no applicable norm")
    ladder=[floors[f"rk4_s{count}"]["maximum_fraction_of_tolerance"] for count in design["substep_ladder"]]
    converged=converges(ladder)
    ladder_text=" -> ".join(f"s{count}: {value:.6g}" for count,value in zip(design["substep_ladder"],ladder))
    # Zero transfer activity exercises no donor rule. The producer then declares
    # no independent rule, and the scorer's reader reads the reference as
    # covering none (ineligible, coverage not met).
    active=bool(len(case["edges"]) and truth.activity[-1].sum()>0)
    declaration={
        "independent_rules":[rule] if active else [],
        "producer":producer_identity(),
        "floors":{"reference_discretization":floor,**{source:0.0 for source in STATED_FLOORS}},
        "floor_basis":{"reference_discretization":
                       "Measured. The RK4 rung 64 against the "+("closed form" if mode=="exact" else "independent exact equations")+
                       " in each applicable same norm, plus the 128 eps arithmetic bound, as the frozen design fixes for both "
                       "reference modes. Applied-share and export-origin rows are included.",**STATED_FLOORS},
        "converged":bool(converged),
        "mirrors_complete":True,
        "jacobian_complete":True,
        "eligibility_basis":{
            "converged":("Measured. No refinement step toward rung 64 raises its floor. " if converged else
                         "Measured. The floor rises along the substep ladder. ")+ladder_text+".",
            "jacobian_complete":"Inapplicable. RK4 and the closed forms have no implicit tag solve. The pool "
                                "diagnostic's linear solve is not the reference.",
            "mirrors_complete":"Inapplicable. Source-free equations, no copies, and every excluded process reads zero.",
            "independent_rules":"Measured. The pinned rates move water." if active else
                                "Measured. Zero transfer activity exercises no donor rule.",
        },
    }
    # The scorer's own reading of a declaration (score_acceptance.py, reference_eligibility).
    eligible=(bool(set(declaration["independent_rules"]) & set(spec.get("active_rules",[]))) and
              declaration["converged"] is True and
              all(0<=value<=FLOOR_FRACTION_MAX for value in declaration["floors"].values()) and
              declaration["mirrors_complete"] is True and declaration["jacobian_complete"] is True)
    if declared:
        for key in DECLARED_FIELDS:
            require(detail.get(key)==declaration[key],
                    f"declared eligibility differs from the producer's recompute: {key}")
        require(ref.get("producer")==declaration["producer"],
                "the manifest does not name this producer and its sha256")
    rows=error_rows(candidate,reference,design)
    boundary_error=np.abs(candidate.labels[:,:,truth.internal_count:]-reference.labels[:,:,truth.internal_count:])
    metrics={"independent_rules":declaration["independent_rules"],"untested_or_shared_rules":[] if active else [rule],
             "floors":list(floors.values()),"ladder_floor_fractions":ladder,
             "donor_rule_applicability":"applicable" if active else "not applicable; zero transfer activity",
             "pool_reference_errors":spread,"candidate_errors":rows,
             "candidate_closure":closure(candidate,design),"candidate_parent_trajectory":parent_trajectory(candidate,truth,design),
             "candidate_application_error":application_error(candidate,case),
             "candidate_directed_balance":directed_balance(candidate,case,design),
             "candidate_applied_partition":applied_partition(candidate,design),
             "boundary_label_absolute_error":boundary_error.tolist(),
             "boundary_label_errors":boundary_error_rows(candidate,reference,design,case),
             "floor_fraction_of_tolerance":floor,
             "rate_validation":False,"runtime_capture":"unavailable. Part 5's verified production registry is empty",
             "OD15":"proposed, pending the owner. No campaign score"}
    if case.get("boundary_sinks"):
        from correction_accounting import paired_precipitation
        require("precipitation_applications" in spec, "missing same-update paired accepted precipitation")
        paired=paired_precipitation(bundle,start,end)
        i,j=window(candidate.time,start,end)
        for name,amount in paired["metrics"]["paired_amounts"].items():
            value = candidate.parent if name == "parent" else candidate.labels[:,
                [t["name"] for t in design["tags"]].index(name)]
            expected = float((value[j,truth.internal_count:] - value[i,truth.internal_count:]).sum())
            require(abs(amount["signed_downward_amount"] - expected) <= 128*np.finfo(float).eps*abs(expected),
                    "paired applied precipitation differs from same owner accumulator")
        metrics["paired_applied_precipitation"] = paired
        metrics["paired_precipitation_status"] = "reported accounting (WA-PRECIP). Never a provenance PASS"
        metrics["instantaneous_precipitation"] = "stored separately. Never integrated as applied amount"
    if eligible:
        verdict="measured eligibility, fixed development equations only: rung 64 meets the quarter rule"
    else:
        verdict="ineligible"
    bundle.reverify()
    return {"meets":bool(eligible),"reference_eligibility":verdict,"declaration":declaration,"metrics":metrics,
            "limitation":"offline independent transfer increment. Atmospheric, PX14, PX25, held-out, EDMF and copies remain unqualified"}
