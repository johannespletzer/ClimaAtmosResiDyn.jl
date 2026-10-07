"""Validate/score the acceptance extension of an existing run manifest.

    python3 score_acceptance.py validate manifest.json --json validation.json
    python3 score_acceptance.py score manifest.json --json results.json

Exit 0: evaluation completed with no required scientific blocker/failure.
Exit 1: a measured required approved criterion failed.
Exit 2: required evidence is missing, corrupt or inconsistent.
Exit 3: required scientific approval/reference/prerequisite is unavailable.
Exit 4: nothing was evaluated. The result path exists, the command line is
invalid, or the scorer itself raised an error. A scorer error is not a data
failure and not a scientific result.
A validation-only zero certifies bundle integrity, not physical qualification.
The persistent blocked rows (convergence, accepted applications, restart,
held-out and scope) keep a score from exiting 0 until their parts deliver.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

from acceptance_data import (Bundle, DataError, NotAssessable, aligned, at,
                             cumulative_amount, density, finite, integrate,
                             od2_start, require, retained, same_bits, window)
from closure_verdict import ENERGY_GROSS, WATER_GROSS
from manifest import sha256_file


DAY = 86400.0
FIRST_HOUR = 3600.0
# Approved numbers (G3_PLAN 6.1 and ROADMAP's OD3 table). Each has a test.
SMALL = 2e-4  # small-tag absolute rule and small-burden exemption, of the parent scale
SMALL_SHARE = 0.01  # a tag below 1% of the partition is small
ORIGIN_L1_DAY, ORIGIN_LINF_DAY = 0.02, 0.05
ORIGIN_L1_FIRST_HOUR = {"region": 0.01, "source": 0.10}
ORIGIN_LINF_FIRST_HOUR = 0.25
LED_FIX_MAX = 0.02  # per-tag retained correction over the window
AGGREGATE_REPAIR_PER_DAY = 0.005  # candidate partition repair
COMPARATOR_REPAIR_PER_DAY = 0.002  # copies repair
COPIES_RESIDUAL_MAX = 2e-4  # a tenth of the closure budget
COMPARATOR_REFINEMENT_MAX = 1.1
FLOOR_FRACTION_MAX = 0.25  # OD12 reference floor, a quarter of the tolerance
PROCESS_WEIGHTED_MAX = 0.05
NAMED_REMAINDER_MAX = 1e-6
NEGATIVE_WATER_MAX = 1e-4
NEWTON_MAX = 1e-3
TEMPERATURE_FLOOR_K, TOP_CHANGE_K = 150.0, 5.0
FLOAT32_FACTOR, FLOAT32_EPS_FACTOR = 10, 3
# Criteria the owner excluded for a named case. A manifest declares an
# exclusion in `excluded_criteria`, and only these declarations are accepted.
APPROVED_EXCLUSIONS = {("water", "D4-W"): {5: "option D, 2026-10-02", 6: "option D, 2026-10-02"}}
PILOT_LABEL = ("low power: the TRMM 0M 6 h pilot scores the first-hour row only "
               "(the first hour's evaporation is 0.13% of the water, rain starts near 3 h)")
SPEC_ROOT = Path(__file__).resolve().parent.parent.parent
SPEC_PATHS = ("G3_PLAN.md", "design/G4_CLAIM_CONTRACTS.md", "ROADMAP.md", "DECISIONS.md")
SCORER_PATHS = ("score_acceptance.py", "acceptance_data.py", "manifest.py", "closure_verdict.py")


def origin_limits(kind, time):
    """The approved L1 and L∞ limits of an origin row at the 1 h or 24 h endpoint."""
    require(kind in ORIGIN_L1_FIRST_HOUR, f"unknown tag classification {kind!r}")
    if time == DAY:
        return ORIGIN_L1_DAY, ORIGIN_LINF_DAY
    require(time == FIRST_HOUR, f"no approved origin tolerance at {time:g} s")
    return ORIGIN_L1_FIRST_HOUR[kind], ORIGIN_LINF_FIRST_HOUR


def float32_limit(float64_measure, steps):
    """Criterion 9's rounding floor: max(10 × Float64, 3 · eps32 · √n_steps)."""
    return max(FLOAT32_FACTOR * float64_measure, FLOAT32_EPS_FACTOR * 2 ** -23 * np.sqrt(steps))


def local_identities():
    return {
        "scorer_files": {p: sha256_file(Path(__file__).with_name(p)) for p in SCORER_PATHS},
        "acceptance_files": {p: sha256_file(SPEC_ROOT / p) for p in SPEC_PATHS if (SPEC_ROOT / p).is_file()},
    }


class Scorer:
    def __init__(self, bundle):
        self.b = bundle
        self.s = bundle.spec
        self.family = self.s.get("claim", {}).get("family")
        self.rows = []
        self.windows = []
        self.tags = self.s.get("tags", [])
        self.accepted_cadence = self.s.get("accepted_step_seconds")
        self.units = ("kg" if self.family == "water" else "J") if self.s.get("geometry_kind") == "sphere" else \
            ("kg m^-2" if self.family == "water" else "J m^-2")
        self.end = self.s.get("end_seconds")
        self.pilot = self.s.get("pilot_first_hour") is True
        self.excluded = {}

    def json_artifact(self, rel):
        """Read a JSON evidence object. A malformed file is a data failure."""
        try:
            detail = json.loads(self.b.artifact(rel).read_text())
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise DataError(f"{rel}: invalid JSON evidence: {exc}") from exc
        require(isinstance(detail, dict), f"{rel}: JSON evidence must be an object")
        return detail

    def exclusions(self):
        """Declared criteria not judged for this case, checked against the approved list."""
        declared = self.s.get("excluded_criteria", [])
        require(isinstance(declared, list) and all(isinstance(c, int) for c in declared),
                "excluded_criteria must be a list of criterion numbers")
        approved = APPROVED_EXCLUSIONS.get((self.family, self.s.get("case")), {})
        require(set(declared) <= set(approved),
                f"excluded_criteria {sorted(set(declared) - set(approved))} are not approved for this case")
        return {c: approved[c] for c in declared}

    def pilot_scope(self):
        require(self.family == "water", "the first-hour pilot scope is a water scope")
        require(isinstance(self.end, (int, float)) and FIRST_HOUR < self.end < DAY,
                "the first-hour pilot runs past 1 h and ends before 24 h")
        return {"metrics": {"scored_origin_endpoints": [FIRST_HOUR], "end_seconds": self.end},
                "limitation": PILOT_LABEL}

    def temperature(self):
        f = self.f("candidate", "temperature", units="K", sampling="instantaneous")
        require(self.s.get("geometry_kind") == "column" and f.dimensions == ("z",),
                "top-temperature mean requires the declared native column. Sphere horizontal weights are separate")
        require(np.all(np.diff(f.geometry[:, 0]) > 0), "column levels must run from the bottom to the top")
        end = min(self.end, DAY)
        i, j = window(f.time, 0, end)
        change = abs(float(f.values[j, -1] - f.values[i, -1]))
        return {"meets": bool(np.min(f.values[i:j + 1]) > TEMPERATURE_FLOOR_K and change < TOP_CHANGE_K),
                "metrics": {"minimum_K": float(np.min(f.values[i:j + 1])), "top_change_K": change,
                            "window_end_seconds": end}, "units": "K",
                "limitation": "" if end == DAY else f"covers the first {end / 3600:g} h of the first day"}

    def newton_trial(self):
        f = self.f("candidate", "newton_error", units="1", sampling="instantaneous")
        value = float(np.max(f.values))
        same_parent = self.s.get("same_parent_comparisons") is True
        return {"metrics": {"E": value}, "meets": value <= NEWTON_MAX,
                "verdict": "REPORTED ONLY" if same_parent else ("PASS" if value <= NEWTON_MAX else "FAIL"),
                "units": "1", "limitation": "E is reported. Its gate only applies to different-parent comparisons" if same_parent else ""}

    def named_remainder(self):
        f, residual = self.d("candidate", "named_remainder", "water")
        p_f, parent = self.d("untagged", "water_parent", "water")
        aligned(f, p_f, "named-parts parent")
        endpoint = DAY if self.end >= DAY else self.end
        j = at(f.time, endpoint)
        mass = float(integrate(parent[j], p_f.weights))
        require(mass > 0, "nonpositive raw named-parts scale")
        require(self.s.get("named_parts"), "missing named-part decomposition roster")
        amount = float(integrate(np.abs(residual[j]), f.weights))
        result = {"metrics": {"absolute_remainder": amount, "raw_parent": mass, "ratio": amount / mass,
                              "endpoint_seconds": endpoint, "named_parts": self.s["named_parts"]},
                  "meets": amount / mass <= NAMED_REMAINDER_MAX,
                  "normalization": "raw untagged parent water at the endpoint"}
        if endpoint != DAY:
            result.update(verdict="REPORTED ONLY", limitation="the approved remainder is at 24 h, no threshold transplant")
        return result

    def data_failure_verdict(self, row_id, required, decision):
        """Water: missing or non-finite data fails a required scored row (G3_PLAN 6.1, 6.1.2).

        Reported-only rows stay not assessable, as 6.1.2's precipitation row
        says. Energy rows keep G4's reading, absent fields are not assessable
        (G4_CLAIM_CONTRACTS section 5). The reproducibility row fails on
        incomplete evidence in both contracts.
        """
        scored = self.family == "water" and required and decision == "approved"
        return "FAIL" if scored or row_id == "COMMON.EVIDENCE" else "NOT ASSESSABLE"

    def row(self, row_id, fn=None, *, threshold=None, decision="reported-only",
            required=True, dependency="", window_name=None, reason="", prerequisites=(), criterion=None):
        row = {"id": row_id, "scope": self.s.get("claim", {}), "required": required,
               "applicability": "applicable", "data_status": "COMPLETE", "metrics": {},
               "units": self.units, "normalization": None, "window": window_name,
               "reference": self.s.get("reference", {}).get("identity"),
               "reference_eligibility": None, "threshold": threshold,
               "decision_status": decision, "decision_source":
               "G3_PLAN §6.1 / ROADMAP OD3" if self.family == "water" else
               "G4_CLAIM_CONTRACTS §4–5 / ROADMAP OD3",
               "verdict": "REPORTED ONLY", "evidence": [], "limitation": reason,
               "dependency": dependency, "next_step": dependency or "none"}
        before = set(self.b.used)
        try:
            blocked = [p for p in prerequisites if p["verdict"] != "PASS"]
            result = fn() if fn else {}
            row["metrics"] = result.pop("metrics", {})
            for key in ("units", "normalization", "reference_eligibility", "applicability", "limitation"):
                if key in result:
                    row[key] = result[key]
            if result.get("applicability") == "not applicable":
                row["verdict"] = "NOT APPLICABLE"
            elif blocked:
                row["verdict"] = "NOT ASSESSABLE"
                row["limitation"] = "failed/unavailable prerequisite: " + ", ".join(p["id"] for p in blocked)
                row["reference_eligibility"] = "ineligible"
            elif decision == "approved":
                row["verdict"] = "PASS" if bool(result.get("meets", False)) else "FAIL"
            elif decision == "proposed":
                row["verdict"] = "NOT ASSESSABLE"
            if "verdict" in result and not blocked and decision != "proposed":
                row["verdict"] = result["verdict"]
        except NotAssessable as exc:
            row["verdict"], row["limitation"] = "NOT ASSESSABLE", str(exc)
        except DataError as exc:
            # Only evidence errors are data failures. Any other exception is a
            # scorer error and propagates, so it is never read as bad data.
            row["verdict"], row["data_status"], row["limitation"] = \
                self.data_failure_verdict(row_id, required, decision), "DATA FAILURE", str(exc)
        if criterion in self.excluded:
            row["applicability"], row["verdict"] = "not applicable", "NOT APPLICABLE"
            row["limitation"] = (f"criterion {criterion} is not judged on this case "
                                 f"({self.excluded[criterion]}). " + row["limitation"]).rstrip(". ")
        row["evidence"] = sorted(set(self.b.used) - before)
        if fn and not row["evidence"]:
            row["evidence"] = sorted(k for k in self.b.used if k != self.b.path.name)
        self.rows.append(row)
        return row

    def block(self, row_id, why, dependency, decision="approved", required=True, criterion=None):
        def unavailable():
            raise NotAssessable(why)
        return self.row(row_id, unavailable, decision=decision, dependency=dependency, required=required,
                        criterion=criterion)

    def inapplicable(self, row_id, why, dependency="", required=True, criterion=None):
        """A row that the approved rule or the declared scope excludes. Never a pass."""
        return self.row(row_id, lambda: {"applicability": "not applicable", "limitation": why},
                        decision="approved", dependency=dependency, required=required, criterion=criterion)

    def f(self, role, name, *, units=None, sampling=None):
        field = self.b.field(role, name)
        if units is not None:
            allowed = units if isinstance(units, tuple) else (units,)
            require(field.units in allowed, f"{name}: wrong units {field.units!r}, expected {allowed}")
        if sampling:
            require(field.sampling == sampling, f"{name}: wrong sampling convention")
        return field

    def d(self, role, name, family=None, sampling="instantaneous"):
        fam = family or self.family
        specific, dens = (("kg kg^-1", "kg m^-3") if fam == "water" else
                          ("J kg^-1", "J m^-3"))
        field = self.f(role, name, units=(specific, dens), sampling=sampling)
        require((field.units, field.representation) in ((specific, "specific"), (dens, "density")),
                f"{name}: units/representation do not agree")
        rho = self.f(role, "rho", units="kg m^-3", sampling="instantaneous")
        values = density(field, rho)
        require(field.weight_units in ("m", "m^3"), "physical density requires native thickness/volume")
        require(field.weight_units == ("m^3" if self.s.get("geometry_kind") == "sphere" else "m"),
                "native weight units disagree with declared geometry")
        return field, values

    def roster(self):
        names = [t.get("name") for t in self.tags]
        require(len(names) == len(set(names)) and all(names), "missing/duplicate tag names")
        require(all(t.get("kind") in ("region", "source") for t in self.tags), "unknown tag classification")
        require(all(not t.get("partition") or t["kind"] == "region" for t in self.tags),
                "overlapping source tracers cannot enter the pure-region partition")
        if self.family != "radiation_record":
            require(any(t.get("partition") for t in self.tags), "missing pure-region partition")
        for t in self.tags:
            self.d("candidate", "tag_" + t["name"])
        return {"meets": True, "metrics": {"tags": names,
                                          "partition": [t["name"] for t in self.tags if t.get("partition")]}}

    def parity(self, role="untagged"):
        names = self.s.get("required_parent_fields")
        require(names and len(names) == len(set(names)), "missing required parent-state field inventory")
        require(self.s.get("parent_capture_scope") in ("exported", "all-state"), "declare parent capture scope")
        differ = []
        for name in names:
            a, b = self.f("candidate", name), self.f(role, name)
            aligned(a, b, "parent " + name)
            require(a.units == b.units and a.sampling == b.sampling and
                    a.representation == b.representation, "parent field conventions differ")
            require(a.values.dtype == b.values.dtype, "parent dtype differs")
            if not same_bits(a.values, b.values):
                differ.append(name)
        if self.s["parent_capture_scope"] != "all-state":
            return {"metrics": {"compared": names, "differing": differ,
                                "exported_outputs_identical": not differ},
                    "verdict": "NOT ASSESSABLE", "limitation": "exported parity does not certify every parent state field"}
        return {"metrics": {"compared": names, "differing": differ}, "meets": not differ}

    def choose_windows(self):
        parent_name = "water_parent" if self.family == "water" else "energy_parent"
        field, values = self.d("untagged", parent_name,
                               "water" if self.family == "water" else "energy_source")
        end = self.s.get("end_seconds")
        require(isinstance(end, (int, float)), "missing claimed end time")
        at(field.time, 0)
        at(field.time, 21600)
        at(field.time, end)
        pulse = None
        if self.s.get("source_pulse"):
            p = self.f("untagged", "pulse", sampling="instantaneous")
            aligned(field, p, "OD2 pulse")
            pulse = integrate(np.abs(p.values), p.weights)
        start = od2_start(field.time, integrate(values, field.weights), pulse)
        self.windows = [("startup", 0.0, min(start, end) if start is not None else end),
                        ("established", start if start is not None and start < end else None, end),
                        ("sensitivity_1h", 3600.0 if end > 3600 else None, end)]
        return {"meets": True, "metrics": {"startup_end": start, "windows": self.windows,
                                           "boundary_source": "untagged parent / approved OD2"}}

    def water_state(self, role="candidate"):
        compartments = self.s.get("compartments", ["total"])
        require(compartments in (["total"], ["N", "R", "S"]), "incomplete/unknown water compartments")
        total_f, total = self.d(role, "water_parent", "water")
        target = np.zeros_like(total)
        signed_residual = np.zeros_like(total)
        grosses = {}
        for c in compartments:
            p_f, parent = self.d(role, "water_parent" if c == "total" else "parent_" + c, "water")
            aligned(total_f, p_f, "water compartment")
            tags = np.zeros_like(parent)
            for tag in self.tags:
                if not tag.get("partition"):
                    continue
                t_f, value = self.d(role, "tag_" + tag["name"] if c == "total" else "tag_" + c + "_" + tag["name"], "water")
                aligned(p_f, t_f, "partition field")
                tags += value
            residual = np.maximum(parent, 0) - tags
            target += np.maximum(parent, 0)
            signed_residual += residual
            grosses[c] = integrate(np.abs(residual), total_f.weights)
        raw = integrate(total, total_f.weights)
        require(np.all(raw > 0), "raw parent water is nonpositive")
        return total_f, {"raw": raw, "target": integrate(target, total_f.weights),
                         "gross": integrate(np.abs(signed_residual), total_f.weights),
                         "net": integrate(signed_residual, total_f.weights),
                         "part_gross": grosses,
                         "negative": integrate(-np.minimum(total, 0), total_f.weights)}

    def negative_water(self):
        f, values = self.d("candidate", "water_parent", "water")
        mass = integrate(values, f.weights)
        require(np.all(mass > 0), "nonpositive raw parent water")
        ratio = integrate(-np.minimum(values, 0), f.weights) / mass
        latch = self.f("candidate", "negative_water_void", sampling="instantaneous")
        require(np.array_equal(latch.time, f.time), "negative-water latch coverage differs")
        require(np.isin(latch.values, (0, 1)).all() and np.all(np.diff(latch.values, axis=0) >= 0),
                "invalid/reset negative-water latch")
        return {"meets": bool(np.max(ratio) < NEGATIVE_WATER_MAX and not np.any(latch.values)),
                "metrics": {"max_ratio": float(np.max(ratio)), "latched": bool(np.any(latch.values))},
                "normalization": "raw candidate parent water"}

    def water_closure(self):
        f, state = self.water_state()
        ref_f, ref = self.d("untagged", "water_parent", "water")
        aligned(f, ref_f, "closure parent")
        raw_ref = integrate(ref, ref_f.weights)
        require(np.all(raw_ref > 0), "nonpositive reference raw water")
        g = state["gross"] / raw_ref
        requested = self.s.get("end_seconds")
        j = at(f.time, requested)
        metrics = {"gross": float(state["gross"][j]), "signed": float(state["net"][j]),
                   "raw_parent": float(raw_ref[j]), "positive_target": float(state["target"][j]),
                   "gross_over_raw": float(g[j]),
                   "gross_over_target": float(state["gross"][j] / state["target"][j])
                   if state["target"][j] > 0 else None,
                   "compartment_gross": {c: float(v[j]) for c, v in state["part_gross"].items()}}
        if requested != DAY:
            return {"metrics": metrics, "verdict": "REPORTED ONLY",
                    "normalization": "raw untagged parent at each endpoint",
                    "limitation": "approved water closure is at 24 h, no threshold transplant"}
        i, m = at(f.time, 0), at(f.time, DAY / 2)
        first, second = float(g[m] - g[i]), float(g[j] - g[m])
        metrics.update(first_normalized_growth=first, second_normalized_growth=second)
        return {"metrics": metrics, "meets": bool(g[j] <= WATER_GROSS and second <= first),
                "normalization": "G(t)=total-residual gross / raw untagged water at t"}

    def exact_scale(self, start, end, role="candidate"):
        validity = self.f(role, "source_partition_valid", units="1", sampling="instantaneous")
        require(np.all(validity.values == 1), "invalid source partition")
        require(self.s.get("energy_ledger_per_tag") is True, "Θx requires per-tag source ledgers")
        if "throughput" in self.s.get("runs", {}).get(role, {}).get("fields", {}):
            f = self.f(role, "throughput", units=self.units, sampling="cumulative")
            require(np.array_equal(validity.time, f.time), "Θx/partition-valid coverage differs")
            require(self.s.get("throughput_accumulation") == "accepted_step",
                    "Θx must record accepted-step accumulation independently of output cadence")
            return cumulative_amount(f, start, end, "accepted_step_source_variation")
        require(self.accepted_cadence and self.accepted_cadence > 0, "missing accepted-step cadence")
        value = 0.0
        rho = self.f(role, "rho", units="kg m^-3")
        for tag in self.tags:
            if tag.get("partition"):
                f, _ = self.d(role, "led_src_" + tag["name"], sampling="cumulative")
                value += retained(f, rho, start, end, self.accepted_cadence)[0]
        return value

    def energy_closure(self, start, end):
        f, values = self.d("candidate", "residual", "energy_source")
        i, j = window(f.time, start, end)
        gross = integrate(np.abs(values), f.weights)
        net = integrate(values, f.weights)
        scale = self.exact_scale(start, end)
        metrics = {"gross_start": float(gross[i]), "gross_end": float(gross[j]),
                   "gross_max": float(np.max(gross[i:j + 1])), "net_start": float(net[i]),
                   "net_end": float(net[j]), "delta_gross": float(gross[j] - gross[i]),
                   "delta_net": float(net[j] - net[i]),
                   "gross_state_change": float(integrate(np.abs(values[j] - values[i]), f.weights)),
                   "theta_x": scale}
        if scale <= 0:
            return {"metrics": metrics, "verdict": "NOT ASSESSABLE",
                    "limitation": "zero Θx, no approved absolute near-zero percentage rule"}
        metrics.update(growth_ratio=metrics["delta_gross"] / scale,
                       end_state_ratio=metrics["gross_end"] / scale,
                       max_state_ratio=metrics["gross_max"] / scale)
        return {"metrics": metrics, "meets": metrics["growth_ratio"] <= ENERGY_GROSS,
                "normalization": "approved accepted-step Θx(window), state ratios reported separately"}

    def ledger_metric(self, tag, start, end, mechanism="led_fix"):
        f, values = self.d("candidate", "tag_" + tag["name"])
        j = at(f.time, end)
        inventory = float(integrate(values[j], f.weights))
        burden = float(integrate(np.abs(values[j]), f.weights))
        if self.family == "water" and self.s.get("compartments") == ["N", "R", "S"]:
            parts = []
            for c in ("N", "R", "S"):
                p_f, value = self.d("candidate", "tag_" + c + "_" + tag["name"], "water")
                aligned(f, p_f, "tag compartment burden")
                parts.append(value)
            require(np.array_equal(sum(parts), values), "total tag differs from declared compartment sum")
            inventory = sum(float(integrate(p[j], f.weights)) for p in parts)
            burden = sum(float(integrate(np.abs(p[j]), f.weights)) for p in parts)
        field_name = mechanism + "_" + tag["name"]
        field, _ = self.d("candidate", field_name, sampling="cumulative")
        rho = self.f("candidate", "rho", units="kg m^-3")
        require(self.accepted_cadence and self.accepted_cadence > 0, "missing accepted-step ledger cadence")
        activity, signed = retained(field, rho, start, end, self.accepted_cadence)
        if self.family == "water":
            p_f, parent = self.d("candidate", "water_parent", "water")
            scale = float(integrate(parent[at(p_f.time, end)], p_f.weights))
        else:
            scale = self.exact_scale(start, end)
        metrics = {"retained_cell_step": activity, "signed_amount": signed,
                   "inventory": inventory, "burden": burden,
                   "inventory_fraction": activity / inventory if inventory > 0 else None,
                   "burden_fraction": activity / burden if burden > 0 else None,
                   "parent_fraction": activity / scale if scale > 0 else None,
                   "parent_daily_rate": activity / scale * DAY / (end - start) if scale > 0 else None}
        flag = self.f("candidate", field_name + "_applicable", units="1", sampling="instantaneous")
        require(np.isin(flag.values, (0, 1)).all(), "invalid runtime applicability flag")
        metrics["runtime_endpoint_applicable"] = bool(np.any(flag.values[at(flag.time, end)]))
        metrics["window_applicable"] = bool(scale > 0 and burden >= SMALL * scale)
        if scale <= 0:
            return {"metrics": metrics, "verdict": "NOT ASSESSABLE", "limitation": "nonpositive valid parent/Θx scale"}
        if burden < SMALL * scale:
            return {"metrics": metrics, "applicability": "not applicable",
                    "limitation": "approved small-burden exemption, absolute activity remains reported"}
        if tag["kind"] == "region" and inventory <= 0:
            return {"metrics": metrics, "verdict": "NOT ASSESSABLE",
                    "limitation": "pure-region intervention requires positive signed inventory"}
        denominator = inventory if tag["kind"] == "region" else burden
        require(denominator > 0, "unknown/zero tag denominator")
        metrics["scored_fraction"] = activity / denominator
        return {"metrics": metrics, "meets": metrics["scored_fraction"] <= LED_FIX_MAX,
                "normalization": "positive signed region inventory" if tag["kind"] == "region" else
                "source absolute burden"}

    def aggregate_repair(self, start, end, role="candidate"):
        f = self.f(role, "repair_retained", units=self.units, sampling="cumulative")
        activity = cumulative_amount(f, start, end, "retained_cell_step_repair")
        if self.family == "water":
            p_f, values = self.d(role, "water_parent", "water")
            a, b = window(p_f.time, start, end)
            masses = integrate(values, p_f.weights)
            scale = float(masses[b])
            # This is a declared diagnostic quadrature, beside the scored endpoint denominator.
            durations = np.diff(p_f.time[a:b + 1])
            mean = float(np.sum(0.5 * (masses[a:b] + masses[a + 1:b + 1]) * durations) / (end - start))
        else:
            scale = self.exact_scale(start, end, role)
            mean = None
        if scale <= 0:
            raise NotAssessable("zero/nonpositive aggregate parent scale")
        rate = activity / scale * DAY / (end - start)
        attempted = self.f(role, "repair_attempted", units=self.units, sampling="cumulative")
        attempted_amount = cumulative_amount(attempted, start, end, "attempted_application_repair")
        return {"metrics": {"retained": activity, "attempted": attempted_amount,
                            "endpoint_scale": scale, "daily_rate": rate,
                            "mean_parent_diagnostic": mean,
                            "mean_parent_daily_rate": activity / mean * DAY / (end - start) if mean and mean > 0 else None},
                "meets": rate <= (COMPARATOR_REPAIR_PER_DAY if role == "reference" else AGGREGATE_REPAIR_PER_DAY),
                "normalization": "window cumulative difference / endpoint raw parent × 86400/seconds"}

    def reference_eligibility(self, start, end):
        ref = self.s.get("reference", {})
        if not ref.get("identity") or not ref.get("evidence"):
            raise NotAssessable("no independent reference has been supplied for this scope")
        detail = self.json_artifact(ref["evidence"])
        require(detail.get("identity") == ref["identity"], "reference evidence identity differs")
        require(detail.get("active_rules") == self.s.get("active_rules"), "reference active-rule roster differs")
        require(detail.get("tag_names") == [t["name"] for t in self.tags] and
                detail.get("end_seconds") == self.s.get("end_seconds") and
                detail.get("model_commit") == self.s.get("runs", {}).get("reference", {}).get("model_commit"),
                "reference eligibility was not measured for this tag/time/model scope")
        unshared = detail.get("independent_rules", [])
        require(isinstance(unshared, list) and all(isinstance(r, str) for r in unshared),
                "independent_rules must be a list of rule names")
        floor = detail.get("floor_fraction_of_tolerance")
        if floor is None or detail.get("converged") is None:
            raise NotAssessable("reference floors/convergence evidence is unavailable")
        eligible = (bool(set(unshared) & set(self.s.get("active_rules", []))) and detail.get("converged") is True and
                    isinstance(floor, (float, int)) and 0 <= floor <= FLOOR_FRACTION_MAX and
                    detail.get("mirrors_complete") is True and detail.get("jacobian_complete") is True)
        if ref.get("kind") == "copies":
            if self.family == "water":
                f = self.f("reference", "copy_residual", units=("kg kg^-1", "kg m^-3"))
                rho = self.f("reference", "rho", units="kg m^-3")
                values = density(f, rho)
                parent_f, parent = self.d("reference", "water_parent", "water")
                aligned(f, parent_f, "copies residual parent")
                i, j = window(f.time, start, end)
                mass = integrate(parent, f.weights)
                require(np.all(mass[i:j + 1] > 0), "invalid copies parent water")
                residual = float(np.max(integrate(np.abs(values[i:j + 1]), f.weights) / mass[i:j + 1]))
                eligible &= residual <= COPIES_RESIDUAL_MAX
            else:
                f, value = self.d("reference", "residual")
                i, j = window(f.time, start, end)
                scale = self.exact_scale(start, end, "reference")
                require(scale > 0, "no eligible energy reference Θx")
                residual = float((integrate(np.abs(value[j]), f.weights) -
                                  integrate(np.abs(value[i]), f.weights)) / scale)
                eligible &= residual <= COPIES_RESIDUAL_MAX
            repair = self.aggregate_repair(start, end, "reference")
            eligible &= repair["meets"]
            ratios = detail.get("repair_refinement_ratios", {})
            require(isinstance(ratios, dict), "copies refinement ratios must be an object")
            require(set(ratios) == {"dt", "newton"}, "copies need time and Newton refinement evidence")
            require(all(isinstance(v, (float, int)) and np.isfinite(v) and v >= 0 for v in ratios.values()),
                    "invalid copies refinement ratios")
            eligible &= all(v <= COMPARATOR_REFINEMENT_MAX for v in ratios.values())
        else:
            residual, repair, ratios = None, None, None
        return {"metrics": {"independent_rules": unshared,
                            "untested_or_shared_rules": sorted(set(self.s.get("active_rules", [])) - set(unshared)),
                            "floor_fraction_of_tolerance": floor, "copies_residual": residual,
                            "copies_repair": repair, "refinement": ratios},
                "reference_eligibility": "eligible for named independent rules" if eligible else "ineligible",
                "meets": bool(eligible)}

    def active_rule_coverage(self):
        """Coverage of every active rule by an independent reference.

        Water reports it and does not gate on it (WA-GATES (b), revisited
        with OD9). Energy keeps it as a gate, since G4's per-tag row makes
        absent independent rule coverage not assessable.
        """
        ref = self.s.get("reference", {})
        if not ref.get("evidence"):
            raise NotAssessable("independent active-rule coverage evidence unavailable")
        detail = self.json_artifact(ref["evidence"])
        rules = detail.get("independent_rules", [])
        require(isinstance(rules, list) and all(isinstance(r, str) for r in rules),
                "independent_rules must be a list of rule names")
        active = set(self.s.get("active_rules", []))
        tested = active & set(rules)
        missing = sorted(active - tested)
        result = {"metrics": {"tested_active_rules": sorted(tested), "untested_or_shared_rules": missing},
                  "meets": bool(active) and not missing,
                  "limitation": "endpoint agreement cannot validate untested/shared active origins" if missing or not active else ""}
        if self.family == "water":
            result["limitation"] = ("reported, not a gate (WA-GATES (b)). " + result["limitation"]).rstrip(". ")
        else:
            result["verdict"] = "PASS" if active and not missing else "NOT ASSESSABLE"
        return result

    def profile(self, tag, time):
        a_f, a = self.d("candidate", "tag_" + tag["name"])
        b_f, b = self.d("reference", "tag_" + tag["name"])
        aligned(a_f, b_f, "tag comparison")
        rho_a, rho_b = self.f("candidate", "rho"), self.f("reference", "rho")
        aligned(rho_a, rho_b, "same-parent reference")
        if self.family == "energy_source":
            if not same_bits(rho_a.values, rho_b.values):
                raise NotAssessable("stored-energy endpoint origins require same-parent density")
            require(self.s.get("energy_offset") == self.s.get("reference", {}).get("energy_offset"),
                    "energy convention c differs")
        i = at(a_f.time, time)
        specific_delta = a[i] / rho_a.values[i] - b[i] / rho_b.values[i]
        delta = specific_delta * rho_b.values[i]
        abs_l1 = float(integrate(np.abs(delta), a_f.weights))
        burden = float(integrate(np.abs(b[i]), b_f.weights))
        ref_inventory = float(integrate(b[i], b_f.weights))
        # L-infinity uses specific fields even when the exported field is a density.
        specific_error = specific_delta
        peak = float(np.max(np.abs(b[i] / rho_b.values[i])))
        metrics = {"absolute_L1": abs_l1, "L1": abs_l1 / burden if burden > 0 else None,
                   "Linf": float(np.max(np.abs(specific_error))) / peak if peak > 0 else None,
                   "max_specific_error": float(np.max(np.abs(specific_error))), "reference_inventory": ref_inventory}
        metrics["candidate_own_inventory"] = float(integrate(a[i], a_f.weights))
        metrics["same_parent_density"] = same_bits(rho_a.values, rho_b.values)
        if self.family == "water":
            p_f, p = self.d("reference", "water_parent", "water")
            aligned(a_f, p_f, "profile reference scale")
            scale = float(integrate(p[i], p_f.weights))
        else:
            scale = sum(float(integrate(self.d("reference", "tag_" + t["name"])[1][i], b_f.weights))
                        for t in self.tags if t.get("partition"))
            if ref_inventory < 0 or np.any(b[i] < 0):
                return {"metrics": metrics, "verdict": "NOT ASSESSABLE",
                        "limitation": "signed/nonpositive reference holdings do not supply positive stored origins"}
        require(scale > 0, "nonpositive reference partition/parent")
        share = ref_inventory / scale
        metrics["reference_share"] = share
        if time not in (FIRST_HOUR, DAY):
            return {"metrics": metrics, "verdict": "REPORTED ONLY",
                    "limitation": "unapproved endpoint, 6 h/12 h remain reported"}
        limitation = PILOT_LABEL if self.pilot and time == FIRST_HOUR else ""
        if share < SMALL_SHARE:
            if self.family == "energy_source":
                established = next((w for w in self.windows if w[0] == "established"), None)
                if not established or established[1] is None or established[2] != time:
                    raise NotAssessable("small energy source needs a predeclared valid Θx window ending at endpoint")
                scale = self.exact_scale(established[1], time)
                if scale <= 0:
                    raise NotAssessable("small energy source has zero Θx")
            metrics["small_absolute_limit"] = SMALL * scale
            return {"metrics": metrics, "meets": abs_l1 <= SMALL * scale, "limitation": limitation,
                    "normalization": "approved small-tag absolute rule replaces both relative tests"}
        l1_limit, linf_limit = origin_limits(tag["kind"], time)
        return {"metrics": metrics, "meets": metrics["L1"] <= l1_limit and metrics["Linf"] <= linf_limit,
                "limitation": limitation, "normalization": "reference absolute burden / specific profile peak"}

    def record_variation(self, start, end):
        roster = self.s.get("record_processes")
        expected = self.s.get("expected_record_processes", [])
        require(isinstance(roster, list) and isinstance(expected, list) and roster and
                all(isinstance(p, str) and p for p in roster + expected) and
                len(roster) == len(set(roster)) and len(expected) == len(set(expected)) and
                set(roster) == set(expected),
                "missing/incorrect expected active process roster")
        total, net, terms = 0.0, 0.0, {}
        for process in roster:
            f, value = self.d("candidate", "record_" + process, "energy_source", sampling="cumulative")
            i, j = window(f.time, start, end)
            variation = float(np.sum(integrate(np.abs(np.diff(value[i:j + 1], axis=0)), f.weights)))
            signed = float(integrate(value[j] - value[i], f.weights))
            terms[process] = {"output_interval_variation": variation, "signed_amount": signed}
            total += variation
            net += signed
        return {"metrics": {"density_reconstructed_record_variation": total, "signed_amount": net,
                            "processes": terms}, "normalization": "native weights, reconstruct ρe_record at each endpoint",
                "limitation": "corrected record estimate excludes cΔρ and within-output cancellation. Neither Θx nor runtime fallback"}

    def precipitation(self, start=None, end=None):
        require(self.s.get("geometry_kind") == "column", "native sphere precipitation requires area-weighted evidence. The column reader cannot sum it")
        p = self.f("candidate", "precip_parent", units="kg m^-2 s^-1" if start is None else
                   ("kg m^-2 s^-1", "kg m^-2"))
        require(p.values.shape[1] == 1 and p.weight_units == "1" and p.dimensions == ("scalar",),
                "column precipitation must be one already area-normalized scalar")
        tags = [self.f("candidate", "precip_" + t["name"], units=p.units)
                for t in self.tags if t.get("partition")]
        for t in tags:
            aligned(p, t, "paired precipitation")
            require(t.sampling == p.sampling and t.representation == p.representation,
                    "parent/tag precipitation conventions differ")
        defect = p.values - sum(t.values for t in tags)
        if start is None:
            require(p.sampling == "instantaneous", "instantaneous precipitation cannot use averages")
            return {"metrics": {"max_absolute_rate_defect": float(np.max(np.abs(defect))),
                                "no_rain_absolute_defect": float(np.max(np.abs(defect[p.values == 0])))
                                if np.any(p.values == 0) else None}, "units": "kg m^-2 s^-1",
                    "limitation": "snapshot accounting only. An exact sum gives no origin evidence"}
        if p.sampling == "interval_average":
            require(p.bounds is not None, "precipitation averages lack interval bounds")
            for t in tags:
                require(t.bounds is not None and same_bits(t.bounds, p.bounds), "paired average bounds differ")
            bounds = p.bounds
            require(np.all(bounds[:, 1] > bounds[:, 0]) and np.all(bounds[1:, 0] == bounds[:-1, 1]),
                    "averaged precipitation has gaps/overlaps")
            sel = (bounds[:, 0] >= start) & (bounds[:, 1] <= end)
            require(np.any(sel) and bounds[sel][0, 0] == start and bounds[sel][-1, 1] == end,
                    "averaged precipitation does not cover exact window")
            require(self.s.get("precipitation_applied_flux_average") is True,
                    "averages do not certify accepted applied flux convention")
            legs = -p.values[sel] * np.diff(bounds[sel], axis=1)
            defect_amount = float(np.sum(-defect[sel] * np.diff(bounds[sel], axis=1)))
            amount = float(np.sum(legs))
            positive, negative = float(np.sum(np.maximum(legs, 0))), float(np.sum(np.minimum(legs, 0)))
        elif p.sampling == "cumulative" and p.units == "kg m^-2":
            require(p.accumulator_kind == "accepted_applied_precipitation" and all(
                t.accumulator_kind == p.accumulator_kind for t in tags), "precipitation accumulator conventions differ")
            i, j = window(p.time, start, end)
            amount = -float(np.sum(p.values[j] - p.values[i]))
            defect_amount = -float(np.sum(defect[j] - defect[i]))
            positive, negative = None, None
        else:
            raise DataError("integrated precipitation needs paired applied averages/accumulators. Snapshots are insufficient")
        return {"metrics": {"signed_downward_amount": amount, "signed_defect": defect_amount,
                            "absolute_defect": abs(defect_amount), "positive_amount": positive,
                            "negative_amount": negative}, "units": "kg m^-2",
                "limitation": "reported accounting (WA-PRECIP): no 0M tolerance, no clipping or hourly interpolation"}

    def process_weighted(self, start, end):
        q = self.f("candidate", "process_amount", sampling="applied_interval")
        actual = self.f("candidate", "process_share", units="1", sampling="applied_interval")
        ref = self.f("reference", "process_share", units="1", sampling="applied_interval")
        aligned(q, actual, "process weighted candidate")
        aligned(actual, ref, "process weighted reference")
        require(q.bounds is not None and actual.bounds is not None and ref.bounds is not None and
                same_bits(q.bounds, actual.bounds) and same_bits(q.bounds, ref.bounds),
                "applied process amounts need aligned interval bounds")
        bounds = q.bounds
        require(np.all(bounds[:, 1] > bounds[:, 0]) and np.all(bounds[1:, 0] == bounds[:-1, 1]),
                "process interval gaps/overlaps")
        sel = (bounds[:, 0] >= start) & (bounds[:, 1] <= end)
        require(np.any(sel) and bounds[sel][0, 0] == start and bounds[sel][-1, 1] == end,
                "process samples do not cover window")
        require(q.representation == "weighted_applied_amount", "process amounts must already include spatial/time weights")
        activity = float(np.sum(np.abs(q.values[sel])))
        absolute = float(np.sum(np.abs(q.values[sel]) * np.abs(actual.values[sel] - ref.values[sel])))
        if activity == 0:
            return {"metrics": {"activity": 0.0, "absolute_defect": absolute, "weighted_error": None},
                    "applicability": "not applicable", "limitation": "inactive process proves no transfer accuracy"}
        return {"metrics": {"activity": activity, "absolute_defect": absolute, "weighted_error": absolute / activity},
                "meets": absolute / activity <= PROCESS_WEIGHTED_MAX, "units": "1",
                "normalization": "absolute error inside sum of already weighted applied amounts"}

    def radiation_reference(self, start, end):
        ref = self.s.get("reference", {})
        require(ref.get("evidence"), "missing signed-record reference eligibility evidence")
        detail = self.json_artifact(ref["evidence"])
        require(detail.get("identity") == ref.get("identity") and
                detail.get("independent_rules") == ["radiation_divergence"] and
                detail.get("converged") is True,
                "radiation reference must independently integrate captured accepted-stage fluxes")
        a_f, actual = self.d("candidate", "record_radiation", "energy_source", sampling="cumulative")
        b_f, expected = self.d("reference", "record_radiation", "energy_source", sampling="cumulative")
        aligned(a_f, b_f, "radiation reference")
        i, j = window(a_f.time, start, end)
        delta = (actual[j] - actual[i]) - (expected[j] - expected[i])
        amount = float(integrate(actual[j] - actual[i], a_f.weights))
        expected_amount = float(integrate(expected[j] - expected[i], a_f.weights))
        absolute = float(integrate(np.abs(delta), a_f.weights))
        return {"metrics": {"signed_record_amount": amount, "independent_flux_amount": expected_amount,
                            "absolute_profile_difference": absolute, "column_difference": amount - expected_amount,
                            "window_mean_W_m^-2": amount / (end - start)},
                "reference_eligibility": "independent accepted-stage divergence, parameterization accuracy excluded",
                "limitation": "unqualified diagnostic (EA-USE): the record is verified against the "
                              "independent accepted-stage flux and reported, with no threshold"}

    def aggregation(self):
        mapping = self.s.get("groups")
        require(isinstance(mapping, dict) and mapping and self.s.get("precision") == "Float64", "aggregation needs Float64 nested group mapping")
        errors = {}
        for group, names in mapping.items():
            require(names and len(names) == len(set(names)) and set(names) <= {t["name"] for t in self.tags},
                    "invalid group membership")
            f, value = self.d("reference", "group_" + group)
            summed = np.zeros_like(value)
            for name in names:
                t_f, t = self.d("candidate", "tag_" + name)
                aligned(f, t_f, "group reference")
                summed += t
            j = at(f.time, DAY)
            peak = float(np.max(np.abs(value[j])))
            error = float(np.max(np.abs(summed[j] - value[j])))
            errors[group] = {"absolute_Linf": error, "relative_Linf": error / peak if peak > 0 else None,
                             "reported_level_exceeded": error / peak > 1e-10 if peak > 0 else None}
        return {"metrics": errors, "limitation": "OD8 aggregation is reported, never an intended-count qualification bridge"}

    def float32(self):
        evidence = self.s.get("float32_evidence")
        if not evidence:
            return {"applicability": "not applicable", "limitation": "Float64 column scope supplies no Float32 qualification"}
        detail = self.json_artifact(evidence)
        require(detail.get("fresh_preregistered") is True and detail.get("historical_id") != "W60",
                "W60 remains failed. The rounding rule needs a fresh preregistered run")
        count = detail.get("accepted_steps")
        a, b = detail.get("Float32"), detail.get("Float64")
        require(isinstance(count, int) and count > 0 and isinstance(a, (int, float)) and isinstance(b, (int, float)),
                "missing matched precision measurement/count")
        finite(np.array([a, b]), "precision measures")
        require(a >= 0 and b >= 0, "negative precision measure")
        limit = float32_limit(b, count)
        return {"metrics": {"Float32": a, "Float64": b, "accepted_steps": count,
                            "approved_rounding_limit": float(limit)}, "meets": a <= limit, "units": "1"}

    def run(self):
        identities = local_identities()
        errors = self.b.validate()
        require(self.family in ("water", "energy_source", "radiation_record"), "unknown claim family")
        require(isinstance(self.end, (int, float)) and np.isfinite(self.end) and self.end > 0,
                "missing/invalid claim duration")
        extra_times = self.s.get("profile_times", [])
        require(isinstance(extra_times, list) and all(isinstance(t, (int, float)) for t in extra_times),
                "profile_times must be a list of seconds")
        for key in ("scorer_files", "acceptance_files"):
            if self.s.get(key) != identities[key]:
                errors.append(f"{key}: pinned files differ from evaluator/specification")
        try:
            self.excluded = self.exclusions()
        except DataError as exc:
            errors.append(str(exc))
        evidence = self.row("COMMON.EVIDENCE", lambda: {"meets": not errors,
                            "metrics": {"validation_errors": sorted(set(errors))}}, decision="approved")
        if errors:
            evidence["data_status"], evidence["verdict"] = "DATA FAILURE", "FAIL"
        if self.pilot:
            pilot = self.row("COMMON.PILOT_SCOPE", self.pilot_scope, dependency="DECISIONS 2026-10-07, the pilot's windows")
            self.pilot = pilot["data_status"] == "COMPLETE"
        family = self.family.upper()
        roster = self.row("COMMON.ROSTER", self.roster, decision="approved")
        parity = self.row("COMMON.PARENT_PARITY", self.parity, decision="approved", dependency="Parts 8/11b state snapshots")
        validity = self.row("COMMON.NEGATIVE_WATER", self.negative_water, decision="approved",
                            threshold=NEGATIVE_WATER_MAX, dependency="Parts 5/8/11b complete validity evidence")
        self.row("COMMON.OD2_WINDOWS", self.choose_windows, decision="approved", dependency="untagged physical boundary evidence")
        if self.family != "radiation_record":
            reference_parity = self.row("REFERENCE.PARENT_PARITY", lambda: self.parity("reference"),
                                        decision="approved" if self.s.get("same_parent_comparisons") is True else "reported-only",
                                        dependency="same-parent reference capture / fixed-parent E for different parents")
            water = self.family == "water"
            coverage = self.row("REFERENCE.ACTIVE_RULE_COVERAGE", self.active_rule_coverage,
                                decision="reported-only" if water else "approved", required=not water,
                                dependency="revisited with OD9 (WA-GATES (b))" if water else
                                "Part 11a independent coverage of every named active origin rule")
        self.row("COMMON.PARENT_TEMPERATURE", self.temperature, decision="approved",
                 threshold={"minimum_K": TEMPERATURE_FLOOR_K, "top_change_K": TOP_CHANGE_K}, dependency="Parts 8/11b/12")
        newton = self.row("COMMON.NEWTON_TRIAL", self.newton_trial, decision="approved", threshold=NEWTON_MAX,
                          dependency="Parts 6/11a reference trials")
        if self.family == "water":
            self.row("WATER.CLOSURE", self.water_closure, decision="approved", threshold=WATER_GROSS,
                     prerequisites=(parity, validity, roster), dependency="Part 5 completeness / Parts 8/10 data")
            self.row("WATER.NAMED_REMAINDER", self.named_remainder, decision="approved", threshold=NAMED_REMAINDER_MAX,
                     prerequisites=(parity, validity), dependency="Parts 5/8/9 complete named parts")
            self.row("WATER.PRECIP_INSTANTANEOUS", self.precipitation, required=False,
                     dependency="Part 7 independent references for the giving pool")
        if not self.windows:
            self.windows = [("startup", 0.0, self.end), ("established", None, self.end),
                            ("sensitivity_1h", FIRST_HOUR if self.end > FIRST_HOUR else None, self.end)]
        eligibility_rows = []
        for name, start, end in self.windows:
            if start is None or start >= end:
                if name == "startup":
                    why = f"the OD2 boundary is at {end:g} s, so startup has zero length at this output cadence"
                elif name == "established":
                    why = "no established interval exists (OD2)"
                else:
                    why = "the run ends before the 1 h sensitivity start"
                self.block("COMMON.WINDOW." + name, why, "OD2 physical window evidence")
                if self.family != "radiation_record":
                    blocked_ids = [("REFERENCE.ELIGIBILITY." + name, None), (family + ".AGGREGATE_REPAIR." + name, None),
                                   (family + ".PROCESS_WEIGHTED." + name, 5)]
                    blocked_ids += [(family + "." + mechanism + "." + tag["name"] + "." + name, None)
                                    for tag in self.tags for mechanism in ("LED_FIX", "LED_INC")]
                    if self.family == "energy_source":
                        blocked_ids.append(("ENERGY.CLOSURE_GROWTH." + name, None))
                    for row_id, criterion in blocked_ids:
                        unavailable = self.block(row_id, why, "OD2 physical window evidence", criterion=criterion)
                        if row_id.startswith("REFERENCE."):
                            eligibility_rows.append(unavailable)
                if self.family in ("energy_source", "radiation_record"):
                    self.block("ENERGY.CORRECTED_RECORD_ESTIMATE." + name, why,
                               "OD2 physical window evidence", decision="reported-only", required=False)
                if self.family == "water":
                    self.block("WATER.PRECIP_INTEGRATED." + name, why,
                               "OD2 / Part 5 paired accumulation", decision="reported-only",
                               required=self.s.get("claim", {}).get("precipitation") is True)
                continue
            if self.family != "radiation_record":
                eligible = self.row("REFERENCE.ELIGIBILITY." + name,
                                    lambda a=start, b=end: self.reference_eligibility(a, b), decision="approved",
                                    window_name=[start, end], dependency="Part 6 (water) / 11a (energy)",
                                    prerequisites=(reference_parity,) if self.s.get("same_parent_comparisons") is True else ())
                eligibility_rows.append(eligible)
                for tag in self.tags:
                    self.row(family + ".LED_FIX." + tag["name"] + "." + name,
                             lambda t=tag, a=start, b=end: self.ledger_metric(t, a, b), decision="approved", threshold=LED_FIX_MAX,
                             window_name=[start, end], prerequisites=(parity, validity, roster), dependency="Part 5 accepted correction activity")
                    self.row(family + ".LED_INC." + tag["name"] + "." + name,
                             lambda t=tag, a=start, b=end: self.ledger_metric(t, a, b, "led_inc"), window_name=[start, end],
                             prerequisites=(parity, validity, roster),
                             dependency="Parts 6/11a refinement, no repair threshold on the correction after each solve")
                self.row(family + ".AGGREGATE_REPAIR." + name,
                         lambda a=start, b=end: self.aggregate_repair(a, b), window_name=[start, end],
                         decision="approved" if self.family == "water" else "proposed",
                         threshold=AGGREGATE_REPAIR_PER_DAY if self.family == "water" else None,
                         prerequisites=(parity, validity, roster),
                         dependency="Part 5 accounting" if self.family == "water" else
                         "Part 5 accounting / energy aggregate level from Part 11b's own baseline")
                if self.family == "energy_source":
                    self.row("ENERGY.CLOSURE_GROWTH." + name, lambda a=start, b=end: self.energy_closure(a, b),
                             decision="approved", threshold=ENERGY_GROSS, window_name=[start, end],
                             prerequisites=(parity, validity, roster), dependency="valid exact accepted-step Θx")
                self.row(family + ".PROCESS_WEIGHTED." + name,
                         lambda a=start, b=end: self.process_weighted(a, b), decision="approved",
                         threshold=PROCESS_WEIGHTED_MAX, criterion=5, window_name=[start, end],
                         prerequisites=(parity, validity, roster, eligible),
                         dependency="Parts 5/6/7/11a applied transfers from the giving pool")
            if self.family in ("energy_source", "radiation_record"):
                self.row("ENERGY.CORRECTED_RECORD_ESTIMATE." + name,
                         lambda a=start, b=end: self.record_variation(a, b), window_name=[start, end], required=False,
                         dependency="11a/11b complete process records")
            if self.family == "water":
                self.row("WATER.PRECIP_INTEGRATED." + name,
                         lambda a=start, b=end: self.precipitation(a, b), window_name=[start, end],
                         required=self.s.get("claim", {}).get("precipitation") is True,
                         dependency="Part 5 paired accumulation / Part 7 giving-pool references / WA-PRECIP")
        if self.family != "radiation_record":
            # The required endpoints stay present even if extra times are empty.
            # The pilot scores the first-hour row only (DECISIONS 2026-10-07).
            required_times = [FIRST_HOUR] if self.pilot else [FIRST_HOUR, DAY]
            profile_times = required_times + [t for t in extra_times if not (self.pilot and t == DAY)]
            # Every window's eligibility row is a prerequisite: any required
            # reference check fails eligibility (G3_PLAN 6.1.2). Water reports
            # active-rule coverage and does not gate on it (WA-GATES (b)).
            ref_prereqs = (tuple(eligibility_rows) + (() if self.family == "water" else (coverage,)) +
                           (() if self.s.get("same_parent_comparisons") is True else (newton,)))
            for t in dict.fromkeys(float(t) for t in profile_times):
                for tag in self.tags:
                    limits = origin_limits(tag["kind"], t) if t in (FIRST_HOUR, DAY) else (None, None)
                    self.row(family + ".ORIGINS." + tag["name"] + "." + f"{t:g}",
                             lambda tag=tag, t=t: self.profile(tag, t), decision="approved",
                             threshold={"endpoint_seconds": t, "L1": limits[0], "Linf": limits[1],
                                        "small_absolute_factor": SMALL, "small_share": SMALL_SHARE},
                             prerequisites=(parity, validity, roster, *ref_prereqs), window_name={"endpoint_seconds": t},
                             dependency="Part 6 / 11a eligible reference", criterion=5)
            if self.pilot:
                for tag in self.tags:
                    self.inapplicable(family + ".ORIGINS." + tag["name"] + "." + f"{DAY:g}",
                                      "the first-hour pilot scope has no 24 h endpoint", criterion=5)
            self.block("COMMON.CONVERGENCE", "complete parent/reference/tag time-grid-Newton ladders required",
                       "Parts 6/8/11a/11b/12", criterion=6)
            self.block("COMMON.REFINEMENT", "the repair's and inc_left's throughput per unit time at the finer rung "
                       "must be at most 0.75 of the coarser rung's, and above 0.9 flags a structural cause. "
                       "The time-step and Newton ladders are not in this bundle", "Parts 6/11a ladders, 8/11b baselines, 12")
            self.row("COMMON.AGGREGATION", self.aggregation, required=False, dependency="Parts 6/11a/12 intended-count group runs")
            self.block("COMMON.ACCEPTED_APPLICATION_ACTIVITY", "cell-step variation can hide cancelling applications/legs. Retained/attempted totals are insufficient", "Part 5")
        else:
            for name, start, end in self.windows:
                if start is not None and start < end:
                    self.row("RADIATION.INDEPENDENT_FLUX_REFERENCE." + name,
                             lambda a=start, b=end: self.radiation_reference(a, b), required=False,
                             window_name=[start, end], dependency="Parts 11a/11b, reported (EA-USE)")
        if self.family == "water":
            one_moment = self.s.get("compartments") == ["N", "R", "S"]
            precipitation_claim = self.s.get("claim", {}).get("precipitation") is True
            if one_moment:
                self.block("WATER.RAIN_SNOW_CLOSURE", "the rain and snow parts must close against ρq_rai and ρq_sno "
                           "within 1e-8 relative in Float64. No per-part closure evidence is in this bundle",
                           "Parts 5/7/9 (rain/snow key)")
                self.block("WATER.PRECIP_TAG_SUM", "Σ pr_tag = pr within 1e-8 relative under 1M. "
                           "No scored sum evidence is in this bundle", "Part 7 / PX25 under OD15 (WA-PRECIP)",
                           required=precipitation_claim)
                self.block("WATER.PRECIP_NET_FLOW_AUDIT", "the net-flow audit is within 10% of each tag's precipitation "
                           "over the day on the 1M column without EDMF, and reported under EDMF",
                           "Part 7 / PX25 under OD15 (WA-PRECIP)", required=precipitation_claim)
            else:
                why = "no prognostic rain/snow compartments (0M or no rain/snow key)"
                self.inapplicable("WATER.RAIN_SNOW_CLOSURE", why)
                self.inapplicable("WATER.PRECIP_TAG_SUM", why + ". The 0M sum has no approved tolerance (WA-PRECIP) "
                                  "and is reported in WATER.PRECIP_INSTANTANEOUS")
                self.inapplicable("WATER.PRECIP_NET_FLOW_AUDIT", why + ". The audit is a 1M row")
        if self.s.get("geometry_kind") == "sphere":
            self.block("COMMON.OD6_CEILING", "the gross residual stays below max(0.02 S_min, 2e-4) of the partition "
                       "at every output of the 90-day sphere", "Part 12 (90-day sphere)")
            if self.family == "water":
                self.block("WATER.SPHERE_TAG_SUM_BOUND", "Σ ρq_tag ≤ ρq_tot (1 + 1e-6) at every point and output, "
                           "and the non-positive fraction does not grow", "Part 12 (90-day sphere)")
        else:
            self.inapplicable("COMMON.OD6_CEILING", "OD6's ceiling applies to the 90-day sphere")
            if self.family == "water":
                self.inapplicable("WATER.SPHERE_TAG_SUM_BOUND", "the sphere's tag-sum bound applies to the sphere")
        self.row("COMMON.FLOAT32", self.float32, decision="approved", dependency="Part 12 fresh precision matrix")
        self.block("COMMON.RESTART_PHYSICAL", "reader stitching is separate from checkpoint round-trip and continuous/restarted model evidence", "Parts 9/10/11b/12")
        if self.family == "radiation_record":
            record_only = "the radiation record is an unqualified diagnostic (EA-USE). EA-ACCURACY and EA-COST lapsed"
            self.inapplicable("COMMON.COST", record_only)
            self.inapplicable("COMMON.HELD_OUT", record_only + ", and a held-out case serves qualification only")
            self.inapplicable("COMMON.SCOPE_APPROVAL", record_only)
        else:
            self.block("COMMON.COST", "matched hardware/build/warm-step/allocation/memory evidence required. "
                       "OD3's 2× at 8 + 8 gates Part 10 after the walk fix, with no pilot or water-only cap (WA-COST)"
                       if self.family == "water" else
                       "matched hardware/build/warm-step/allocation/memory evidence required. OD3's 2× at 8 + 8 "
                       "is measured in Part 11b", "Parts 8/10/12" if self.family == "water" else "Parts 11b/12")
            self.block("COMMON.HELD_OUT", "independent case/reference frozen before tuning required for applicable qualification", "Parts 6/7/10/11d/12, OD14")
            if self.family == "water":
                self.block("COMMON.SCOPE_APPROVAL", "qualification stays at eight tags on the approved rows (WA-SCOPE). "
                           "The 24 h development case and the held-out case are named before PX11, and the owner has "
                           "not named them yet", "WA-SCOPE / Parts 10/12")
            else:
                self.block("COMMON.SCOPE_APPROVAL", "the stored-source qualification scope is set in Part 11d",
                           "Part 11d", decision="proposed")
        self.row("COMMON.FINAL_ARTIFACT_CHECK", lambda: (self.b.reverify() or {"meets": True}),
                 decision="approved", dependency="immutable bundle artifacts")
        required = [r for r in self.rows if r["required"] and r["applicability"] == "applicable"]
        # A data failure fails the affected row and the reproducibility row (G3_PLAN 6.1.2).
        failed = [r["id"] for r in required if r["data_status"] == "DATA FAILURE" and r["id"] != "COMMON.EVIDENCE"]
        if failed:
            evidence["metrics"]["row_data_failures"] = failed
            evidence["data_status"], evidence["verdict"] = "DATA FAILURE", "FAIL"
        result = {"schema_version": 1, "claim": self.s.get("claim", {}), "model_commit": self.b.manifest.get("head_sha"),
                  "experiment_commit": self.s.get("experiment_commit"), "scorer_commit": self.s.get("scorer_commit"),
                  "acceptance_commit": self.s.get("acceptance_commit"), **identities,
                  "artifacts": dict(sorted(self.b.used.items())), "rows": self.rows,
                  "scientific_qualification": "NOT QUALIFIED",
                  "limitation": "offline implementation/fixtures do not supply physical qualification evidence"}
        result["exit_code"] = (2 if any(r["data_status"] == "DATA FAILURE" for r in required) else
                               1 if any(r["verdict"] == "FAIL" for r in required) else
                               3 if any(r["verdict"] == "NOT ASSESSABLE" for r in required) else 0)
        return result


def summary(result):
    lines = [f"qualification: {result.get('scientific_qualification', 'not evaluated')}, exit {result['exit_code']}"]
    for row in result.get("rows", []):
        lines.append(f"{row['id']}: {row['verdict']} / {row['data_status']}" +
                     (f" — {row['limitation']}" if row["limitation"] else ""))
    for error in result.get("validation_errors", []):
        lines.append("DATA FAILURE: " + error)
    if result.get("scorer_error"):
        lines.append("SCORER ERROR: " + result["scorer_error"])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=("validate", "score"))
    parser.add_argument("manifest")
    parser.add_argument("--json", required=True, help="new deterministic result artifact. Existing paths are refused")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code == 0 else 4
    output = Path(args.json)
    if output.exists():
        print("not evaluated: result path exists. Preserve historical scores and choose a new reanalysis ID",
              file=sys.stderr)
        return 4
    not_evaluated = {"schema_version": 1, "scientific_qualification": "NOT EVALUATED"}
    try:
        bundle = Bundle(args.manifest)
        if args.mode == "validate":
            errors = bundle.validate()
            identities = local_identities()
            for key in ("scorer_files", "acceptance_files"):
                if bundle.spec.get(key) != identities[key]:
                    errors.append(f"{key}: pinned files differ from evaluator/specification")
            try:
                bundle.reverify()
            except DataError as exc:
                errors.append(str(exc))
            result = {"schema_version": 1, "validation_errors": sorted(set(errors)),
                      "artifacts": dict(sorted(bundle.used.items())), **identities,
                      "exit_code": 2 if errors else 0, "scientific_qualification": "NOT EVALUATED"}
        else:
            result = Scorer(bundle).run()
    except (DataError, json.JSONDecodeError, UnicodeDecodeError, OSError) as exc:
        result = {**not_evaluated, "validation_errors": [str(exc)], "exit_code": 2}
    except Exception as exc:  # A scorer error is reported as such, never as bad data.
        result = {**not_evaluated, "scorer_error": f"{type(exc).__name__}: {exc}", "exit_code": 4}
    output.write_text(json.dumps(result, sort_keys=True, indent=2, allow_nan=False) + "\n")
    print(summary(result))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
