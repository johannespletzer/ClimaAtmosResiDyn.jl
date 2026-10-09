"""PX25 planning and unresolved decision observables; never approve a campaign."""

import copy
import json
from pathlib import Path

import numpy as np

from acceptance_data import require, same_bits


def effective_substep_key(settings):
    require(isinstance(settings.get("use_sgs_quadrature"),bool),"resolve SGS quadrature before configuring substeps")
    return "microphysics_n_substeps_quadrature" if settings["use_sgs_quadrature"] else "microphysics_n_substeps"


def px25_matrix(base):
    require(base.get("microphysics_model")=="1M" and base.get("turbconv") is None,
            "PX25 planning refuses unsupported EDMF/copies")
    key=effective_substep_key(base);default=2 if base["use_sgs_quadrature"] else 3
    require(base.get(key)==default,"registered default substep setting differs")
    parents=[];tagged=[]
    for scheme in ("first_order","vanleer_limiter"):
        for dt in (10.,5.,2.5):
            pid=scheme+"_dt"+str(dt).replace(".","p")
            setting=copy.deepcopy(base);setting.update(tracer_upwinding=scheme,dt=f"{dt:g}secs")
            parents.append({"id":pid,"settings":setting,"kind":"untagged","refinement":"dt ladder within this scheme"})
    for count in (1,10):
        pid="vanleer_limiter_dt10p0_sub"+str(count)
        setting=copy.deepcopy(base);setting.update(tracer_upwinding="vanleer_limiter",dt="10secs");setting[key]=count
        parents.append({"id":pid,"settings":setting,"kind":"untagged","refinement":"substeps reported only; not two dt halvings"})
    for parent in parents:
        for mode in ("tracer","increment"):
            setting=copy.deepcopy(parent["settings"])
            setting.update(water_tag_precipitation=True,water_tag_transport=mode,water_tag_ledger_per_tag=True,
                           water_tracers=[{"name":"lower","region":{"type":"tanh_altitude","z_center":3000.,"width":300.,"above":False}},
                                          {"name":"upper","region":{"type":"tanh_altitude","z_center":3000.,"width":300.,"above":True}},
                                          {"name":"evap","source":"surface_flux"}])
            tagged.append({"id":parent["id"]+"_"+mode,"parent_id":parent["id"],"kind":"tagged","settings":setting})
    return {"schema_version":1,"kind":"DRAFT; NOT AUTHORIZED/EXECUTED CAMPAIGN","case":"PrecipitatingColumn development",
            "OD15_status":"PROPOSED/PENDING","short_case_end_seconds":1500,"effective_substep_key":key,
            "default_substeps":default,"parents":parents,"tagged_arms":tagged,"jobs":24,
            "cross_parent_provenance":"not assessable","first_order":"another scheme, not a rung",
            "second_case":"unselected; OD2 established-rain measurement and OD14 independence required",
            "held_out_overlap":"PrecipitatingColumn starts from RICO's theta and q_tot profiles. RICO 1M 24 h is the "
                               "held-out case (WA-SCOPE, 2026-10-08). Under OD14 (decision of 2026-10-09) this column "
                               "serves PX25's PT15 and PT16 arithmetic rows only and chooses no mode or default. The "
                               "explicit-1M default is chosen on an independent second case, found together with OD15",
            "score_status":"BLOCKED by OD15 and missing runtime accepted application producer"}


def void_substep_perturbation(default_parent,arm_parent):
    require(default_parent and set(default_parent)==set(arm_parent),"incomplete untagged parent field roster")
    return {"void":all(same_bits(default_parent[name],arm_parent[name]) for name in default_parent),
            "interpretation":"identical untagged bits mean a void perturbation, never systematic attribution"}


def short_case_rows(end_seconds):
    require(np.isfinite(end_seconds) and end_seconds>0,"invalid short case length")
    return [{"id":name,"required_seconds":seconds,"sample_available":end_seconds>=seconds,
             "decision_status":status,"verdict":"NOT ASSESSABLE" if end_seconds<seconds else "UNSCORED; actual channel/window required",
             "limitation":"OD15 must decide short-case applicability; no invented hourly/day sample"}
            for name,seconds,status in (("closure_24h",86400,"approved original observable"),
                                         ("second_12h_growth",86400,"approved original observable"),
                                         ("audit_tag_precip_over_day",86400,"approved original observable"),
                                         ("R9_hourly_compartment",3600,"proposed R9 hourly reading"))]


def proposed_audit_trend(values):
    require(len(values)==3 and np.isfinite(values).all() and min(values)>=0,"audit trend needs three nonnegative dt rung ratios")
    ratios=[values[i+1]/values[i] if values[i]>0 else None for i in range(2)]
    if any(v is None for v in ratios):reading="unresolved; zero denominator"
    elif all(v<=.75 for v in ratios):reading="converging"
    elif any(v>1.1 for v in ratios):reading="growing"
    elif all(.9<=v<=1.1 for v in ratios):reading="systematic"
    else:reading="unresolved"
    return {"ratios":ratios,"proposed_reading":reading,"decision_status":"PROPOSED/PENDING OD15",
            "verdict":"NOT ASSESSABLE","substeps":"reported only; non-doubling counts have no adopted trend rule"}


DRAFT_README = """# PX25 draft configurations

This is a draft pending the owner. These 24 JSON-compatible YAML configs are
planning artifacts only. Sixteen tagged arms have eight separately matched
untagged parents. OD15 is proposed, not decided. The OD2 rain windows and the
accepted capture, lifecycle and parity evidence are missing, so no campaign
is authorized or scored. No hourly, 12 h or 24 h rule applies to the 1500 s
output. The second established-rain case is unselected.

PrecipitatingColumn starts from RICO's theta and q_tot profiles. RICO 1M 24 h
is the held-out case (WA-SCOPE, 2026-10-08). Under OD14 (decision of
2026-10-09) this column serves PX25's PT15 and PT16 arithmetic rows only. It
chooses no mode or default. The explicit-1M default is chosen on an
independent second case, found together with OD15.

The files are written by `save_px25_draft` in
`analysis/evidence/water_transfer_preregistration.py`. No launch command is
recorded here. A run needs a prepared checkout and a separately approved job.
"""


def save_px25_draft(root):
    root=Path(root);root.mkdir(parents=True,exist_ok=False)
    base={"config":"column","initial_condition":"PrecipitatingColumn","surface_setup":"DefaultMoninObukhov",
          "z_elem":30,"z_max":6000.,"z_stretch":False,"dt":"10secs","t_end":"1500secs","dt_save_state_to_disk":"10secs",
          "cloud_model":"grid_scale","microphysics_model":"1M","vert_diff":"DecayWithHeightDiffusion","implicit_diffusion":True,
          "implicit_microphysics":True,"approximate_linear_solve_iters":2,"use_sgs_quadrature":True,
          "microphysics_n_substeps_quadrature":2,"microphysics_n_substeps":3,"turbconv":None,"FLOAT_TYPE":"Float64",
          "reproducibility_test":False,"toml":["toml/single_column_precipitation_test.toml"],"output_default_diagnostics":False}
    matrix=px25_matrix(base)
    matrix["short_criteria"]=short_case_rows(1500)
    matrix["capture_blockers"]=["native per-tag N/R/S minima/residual/correction/fallback/bound/zero channels",
                                "same accepted parent/tag applied precipitation and six directed flow applications",
                                "checkpoint-linked restart/trial acceptance/rollback/device/parity/performance validation",
                                "OD2 startup/rain window measured from own untagged run","OD15 recorded owner decisions"]
    for arm in matrix["parents"]+matrix["tagged_arms"]:
        setting=copy.deepcopy(arm["settings"]);setting["job_id"]="part7_px25_draft_"+arm["id"]
        (root/(arm["id"]+".yml")).write_text(json.dumps(setting,sort_keys=True,indent=2)+"\n")
    (root/"preregistration.json").write_text(json.dumps(matrix,sort_keys=True,indent=2)+"\n")
    (root/"README.md").write_text(DRAFT_README)
    return matrix
