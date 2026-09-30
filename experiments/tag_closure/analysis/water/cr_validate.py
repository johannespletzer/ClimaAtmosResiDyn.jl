"""C's revision: its validation, scored as pre-registered
(design/NEGATIVE_PARENT_WATER.md, section 11.7).

    python3 cr_validate.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds
`cr_s{23,26}{,_untagged,_main}/output_0000`. The rules are section 8.3's,
which W42 scored with `ic_validate.py`, with the same thresholds, and V4b.
It prints, per rule, the number and the verdict:
  - V1: site 23 with the revision reached day 90 (its closure table's last
    row);
  - V2: the largest gross closure over every check to day 90, against 0.2%,
    both sites (the closure table compares the partition with max(ρq_tot, 0)).
    Reported beside it: the same for the control on `main`, and the first
    check above 0.2% in each;
  - V2b: q_tag_res + q_tag_negative + the region tags against q_tot, at every
    daily output, the largest gap over the column's largest |q_tot|, against
    1e-12;
  - V3: site 26's water tags, the revision against the control on `main`, bit
    for bit at every daily output; where not, whether every differing value
    lies where the untagged twin's parent was ever negative;
  - V4: every model field of each revision run against its untagged twin, bit
    for bit at every daily output;
  - V4b: every model field of each revision run against the control on
    `main`, bit for bit at every daily output;
  - V5: from the audit tables, over days 1 to 90: the negative part's ledger's
    per-step gross a day (reported), the partition repair's retained gross (at
    most 0.5% of the water a day) and each tag's led_fix (at most 2% of its
    inventory).
Nothing here is tuned after the runs. It exits 1 if a rule fails or its data
are missing.
"""
import csv
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
# Section 8.3's thresholds, unchanged.
V2_MAX, V2B_MAX, REPAIR_MAX, LED_FIX_MAX = 2e-3, 1e-12, 5e-3, 2e-2
failed = []


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


def verdict(rule, ok):
    if not ok:
        failed.append(rule)
    return "pass" if ok else "FAIL"


def largest_gross(job):
    closure = rows(job, "water_tag_closure.csv")
    if not closure:
        return None, None, None
    scored = [r for r in closure if r["time"] <= END + 1]
    worst = max(r["gross_relative"] for r in scored)
    first = next((r["time"] / DAY for r in scored if r["gross_relative"] > V2_MAX), None)
    return worst, first, scored


def model_fields_match(job, twin):
    differ = []
    for var in MODEL_FIELDS:
        ta, a = read(job, var)
        tb, b = read(twin, var)
        if a is None or b is None:
            differ.append(f"{var} (missing)")
            continue
        # The revision's runs must cover every daily output the twin wrote.
        if len(ta) < len(tb):
            differ.append(f"{var} (only {len(ta)} of {len(tb)} outputs)")
            continue
        n = len(tb)
        if not (np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(a[:n]), bits(b[:n]))):
            differ.append(var)
    return differ


# V1
closure = rows("cr_s23", "water_tag_closure.csv")
last = closure[-1]["time"] if closure else None
print(f"V1 site 23 reaches day 90: last closure row at {None if last is None else last / DAY} days: "
      f"{verdict('V1', last is not None and last >= END - 1)}")

for site in ("23", "26"):
    job = f"cr_s{site}"
    # V2
    worst, first, scored = largest_gross(job)
    if worst is None:
        print(f"V2 site {site}: no closure table: {verdict(f'V2 s{site}', False)}")
    else:
        void = any(r.get("negative_water_void", 0) for r in scored)
        print(f"V2 site {site}: largest gross {worst:.3e} of max(ρq_tot, 0), first above 0.2% at "
              f"{first} days: {verdict(f'V2 s{site}', worst <= V2_MAX)}"
              + ("; rows marked negative_water_void" if void else ""))
    control, control_first, _ = largest_gross(f"cr_s{site}_main")
    if control is not None:
        print(f"    reported: the control on main, largest gross {control:.3e}, first above 0.2% at "
              f"{control_first} days")
    # V2b
    t, hus = read(job, "hus")
    _, res = read(job, "q_tag_res")
    _, neg = read(job, "q_tag_negative")
    if hus is None or res is None or neg is None:
        print(f"V2b site {site}: missing output: {verdict(f'V2b s{site}', False)}")
    else:
        total = res + neg
        for tag in REGION:
            total = total + read(job, f"q_tag_{tag}")[1]
        # Against each output's largest |q_tot| in the column.
        scale = np.max(np.abs(hus).reshape(len(hus), -1), axis=1)
        gap = np.max(np.abs(total - hus).reshape(len(hus), -1).max(axis=1) / np.maximum(scale, 1e-300))
        print(f"V2b site {site}: largest relative gap {gap:.3e}: {verdict(f'V2b s{site}', gap <= V2B_MAX)}")
    # V4 and V4b
    for rule, twin in (("V4", f"cr_s{site}_untagged"), ("V4b", f"cr_s{site}_main")):
        differ = model_fields_match(job, twin)
        print(f"{rule} site {site}: {len(MODEL_FIELDS)} model fields against {twin}: "
              f"{verdict(f'{rule} s{site}', not differ)}" + (f" ({differ})" if differ else ""))
    # V5
    audit = rows(job, "water_tag_audit.csv")
    if not audit or not scored:
        print(f"V5 site {site}: missing audit or closure table: {verdict(f'V5 s{site}', False)}")
        continue
    end = [r for r in audit if r["time"] <= END + 1][-1]
    start = next(r for r in audit if r["time"] >= DAY - 1)
    days = (end["time"] - start["time"]) / DAY
    water = scored[-1]["total"]
    per_day = lambda col: (end[col] - start[col]) / water / days
    repair = per_day("led_repair_retained")
    print(f"V5 site {site}: negative part's per-step gross {per_day('inc_negative_retained'):.3e} "
          f"of the water a day (reported); repair's retained gross {repair:.3e} a day: "
          f"{verdict(f'V5 repair s{site}', repair <= REPAIR_MAX)}")
    for tag in TAGS:
        frac = end.get(f"led_fix_{tag}_inventory_fraction", float("nan"))
        print(f"    led_fix {tag}: {frac:.3e} of its inventory: "
              f"{verdict(f'V5 led_fix {tag} s{site}', not frac > LED_FIX_MAX)}")

# V3
t_c, _ = read("cr_s26", "q_tag_pbl")
if t_c is None:
    print(f"V3 site 26: missing output: {verdict('V3', False)}")
else:
    _, hus_u = read("cr_s26_untagged", "hus")
    ever_negative = np.minimum.accumulate(hus_u, axis=0) < 0 if hus_u is not None else None
    for tag in TAGS:
        tc, a = read("cr_s26", f"q_tag_{tag}")
        tb, b = read("cr_s26_main", f"q_tag_{tag}")
        if a is None or b is None or len(tc) < len(tb):
            print(f"V3 site 26 q_tag_{tag}: missing output: {verdict(f'V3 {tag}', False)}")
            continue
        n = len(tb)
        same = bits(a[:n]) == bits(b[:n])
        if same.all():
            print(f"V3 site 26 q_tag_{tag}: bit for bit at {n} outputs: pass")
        else:
            where = ~same
            explained = ever_negative is not None and bool(np.all(ever_negative[:n][where]))
            print(f"V3 site 26 q_tag_{tag}: {where.sum()} values differ; all where the parent was ever "
                  f"negative: {verdict(f'V3 {tag}', explained)}")

print("RESULT", "all rules pass" if not failed else f"failed: {failed}")
sys.exit(1 if failed else 0)
