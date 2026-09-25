"""Known issue 7, option C: its validation, scored as pre-registered
(design/NEGATIVE_PARENT_WATER.md, section 8.3).

    python3 ic_validate.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds `ic_s{23,26}_{c,
untagged,before}/output_0000`. It prints, per rule, the number and the
verdict:
  - V1: site 23 with C reached day 90 (its closure table's last row);
  - V2: the largest gross closure over every check to day 90, against 0.2%,
    both sites (the closure table compares the partition with max(ρq_tot, 0));
  - V2b: q_tag_res + q_tag_negative + the region tags against q_tot, at every
    daily output, the largest gap over the column's largest |q_tot|, against
    1e-12;
  - V3: site 26's water tags, C against the control, bit for bit at every
    daily output; where not, the cells and times, and whether the untagged
    parent was ever negative there;
  - V4: every model field of each C run against its untagged twin, bit for
    bit at every daily output;
  - V5: from the audit tables, per day over days 1 to 90: the negative part's
    ledger's per-step gross (reported), the partition repair's retained gross
    (at most 0.5% of the water a day) and each tag's led_fix (at most 2% of
    its inventory).
"""
import csv
import glob
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
DAY = 86400.0
END = 90 * DAY
REGION = ("pbl", "free")
TAGS = ("pbl", "free", "evap", "fcg")
MODEL_FIELDS = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")


def out(job):
    return os.path.join(ROOT, job, "output_0000")


def rows(job, name):
    path = os.path.join(out(job), name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def read(job, var, period="1d"):
    path = os.path.join(out(job), f"{var}_{period}_inst.nc")
    if not os.path.exists(path):
        return None, None
    with nc.Dataset(path) as d:
        v = d[var]
        a = np.asarray(v[:])
        if "time" in v.dimensions:
            a = np.moveaxis(a, v.dimensions.index("time"), 0)
        return np.asarray(d["time"][:]), a


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def verdict(ok):
    return "pass" if ok else "FAIL"


# V1
closure = rows("ic_s23_c", "water_tag_closure.csv")
last = closure[-1]["time"] if closure else None
print(f"V1 site 23 reaches day 90: last closure row at {None if last is None else last / DAY} days: "
      f"{verdict(last is not None and last >= END - 1)}")

for site in ("23", "26"):
    job = f"ic_s{site}_c"
    closure = rows(job, "water_tag_closure.csv")
    if closure:
        worst = max(r["gross_relative"] for r in closure if r["time"] <= END + 1)
        void = any(r.get("void", 0) for r in closure)
        print(f"V2 site {site}: largest gross {worst:.3e} of max(ρq_tot, 0): "
              f"{verdict(worst <= 2e-3)}" + ("; void rows" if void else ""))
    # V2b
    t, hus = read(job, "hus")
    _, res = read(job, "q_tag_res")
    _, neg = read(job, "q_tag_negative")
    if hus is not None and res is not None and neg is not None:
        total = res + neg
        for tag in REGION:
            total = total + read(job, f"q_tag_{tag}")[1]
        # Against each output's largest |q_tot| in the column.
        scale = np.max(np.abs(hus).reshape(len(hus), -1), axis=1)
        gap = np.max(np.abs(total - hus).reshape(len(hus), -1).max(axis=1) / np.maximum(scale, 1e-300))
        print(f"V2b site {site}: largest relative gap {gap:.3e}: {verdict(gap <= 1e-12)}")
    # V4
    differ = []
    for var in MODEL_FIELDS:
        ta, a = read(job, var)
        tb, b = read(f"ic_s{site}_untagged", var)
        if a is None or b is None:
            differ.append(f"{var} (missing)")
            continue
        n = min(len(ta), len(tb))
        if not (np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(a[:n]), bits(b[:n]))):
            differ.append(var)
    print(f"V4 site {site}: {len(MODEL_FIELDS)} model fields against the untagged twin: "
          f"{verdict(not differ)}" + (f" ({differ})" if differ else ""))
    # V5
    audit = rows(job, "water_tag_audit.csv")
    if audit:
        end = [r for r in audit if r["time"] <= END + 1][-1]
        start = next(r for r in audit if r["time"] >= DAY - 1)
        days = (end["time"] - start["time"]) / DAY
        water = [r for r in closure if r["time"] <= END + 1][-1]["total"]
        per_day = lambda col: (end[col] - start[col]) / water / days
        print(f"V5 site {site}: negative part's per-step gross {per_day('inc_negative_retained'):.3e} "
              f"of the water a day (reported); repair's retained gross "
              f"{per_day('led_repair_retained'):.3e} a day: {verdict(per_day('led_repair_retained') <= 5e-3)}")
        for tag in TAGS:
            frac = end.get(f"led_fix_{tag}_inventory_fraction", float("nan"))
            print(f"    led_fix {tag}: {frac:.3e} of its inventory: {verdict(not frac > 0.02)}")

# V3
t_c, _ = read("ic_s26_c", "q_tag_pbl")
if t_c is not None:
    _, hus_u = read("ic_s26_untagged", "hus")
    ever_negative = np.minimum.accumulate(hus_u, axis=0) < 0 if hus_u is not None else None
    for tag in TAGS:
        tc, a = read("ic_s26_c", f"q_tag_{tag}")
        tb, b = read("ic_s26_before", f"q_tag_{tag}")
        n = min(len(tc), len(tb))
        same = bits(a[:n]) == bits(b[:n])
        if same.all():
            print(f"V3 site 26 q_tag_{tag}: bit for bit at {n} outputs: pass")
        else:
            where = ~same
            explained = ever_negative is not None and bool(np.all(ever_negative[:n][where]))
            print(f"V3 site 26 q_tag_{tag}: {where.sum()} values differ; all where the parent was ever "
                  f"negative: {verdict(explained)}")
