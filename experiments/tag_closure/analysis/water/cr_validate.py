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
    for bit at every daily output; or, amended 2026-09-30 (question 9), every
    differing value lies at an output time at or after `t*`, the first time
    the parent is below zero anywhere in its column. `t*` is the earliest of
    the first `hus` below zero in the column (`cr_s26` daily and 6-hourly,
    `cr_s26_untagged` daily), the first row of `cr_s26`'s water_tag_audit.csv
    with negative_water_interval_events above zero, the first with
    exp_negative_retained above zero (the ledger saw the rule act at a stage)
    and, if the field exists, the first with exp_negloss_retained above zero.
    A field that the table lacks is printed and skipped. A difference with no
    `t*`, or before it, fails. After `t*` the rule accepts every difference,
    so it bounds and cannot attribute. The script prints `t*` and its source;
  - V4: every model field of each revision run against its untagged twin, bit
    for bit at every daily output;
  - V4b: every model field of each revision run against the control on
    `main`, bit for bit at every daily output;
  - V5: from the audit tables, over days 1 to 90: the negative part's ledger's
    per-step gross a day (reported), the partition repair's retained gross (at
    most 0.5% of the water a day) and each tag's led_fix (at most 2% of its
    inventory). Added 2026-09-30, reported, no threshold: q_tag_exp_negative's
    per-step gross a day (the audit's exp_negative_retained), and each source
    tag's negative water, the daily column integral of min(ρq, 0) over that of
    max(ρq, 0), with the first daily output below zero. Missing data for these
    two are printed as not available, not failed.
V2 and V5 score the revision's bundle: the explicit rule, the implicit
microphysics bracket, the source tags, the follower's amendment and, if built,
q_tag_exp_negloss. They bound the rule's part and do not isolate it.
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


def read_named(job, var, period="1d"):
    """time, and the field as (time, z, columns). A column is an index of every
    dimension but time and z, in the file's order (site 26 has one)."""
    path = os.path.join(out(job), f"{var}_{period}_inst.nc")
    if not os.path.exists(path):
        return None, None, None
    with nc.Dataset(path) as d:
        v = d[var]
        dims = v.dimensions
        if "time" not in dims or "z" not in dims:
            return None, None, None
        a = np.asarray(v[:])
        a = np.moveaxis(a, [dims.index("time"), dims.index("z")], [0, 1])
        z = np.asarray(d["z"][:])
        return np.asarray(d["time"][:]), a.reshape(a.shape[0], a.shape[1], -1), z


def thickness(z):
    """The cells' thickness from the cell centres: faces half way between them,
    and the end cells mirrored."""
    z = np.asarray(z, dtype=float)
    faces = np.empty(len(z) + 1)
    faces[1:-1] = 0.5 * (z[1:] + z[:-1])
    faces[0] = 2 * z[0] - faces[1]
    faces[-1] = 2 * z[-1] - faces[-2]
    return np.diff(faces)


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


def source_negative_water(job, tag):
    """A source tag's negative water from its daily output: the column integral
    of min(ρq, 0) over that of max(ρq, 0), its largest size and the first daily
    output where the tag is below zero anywhere."""
    t, q, z = read_named(job, f"q_tag_{tag}")
    tr, rho, _ = read_named(job, "rhoa")
    name = f"source tag {tag}'s negative water"
    if q is None or rho is None or rho.shape != q.shape:
        return f"{name}: not available (no q_tag_{tag} or rhoa daily output)"
    keep = t <= END + 1
    m = q * rho * thickness(z)[None, :, None]
    neg = np.minimum(m, 0).sum(axis=1)[keep]
    pos = np.maximum(m, 0).sum(axis=1)[keep]
    ratio = np.where(pos > 0, neg / np.where(pos > 0, pos, 1.0), 0.0)
    worst = np.unravel_index(np.argmin(ratio), ratio.shape)
    below = np.nonzero((neg < 0).any(axis=1))[0]
    first = f"{t[keep][below[0]] / DAY:g} days" if len(below) else "never"
    return (f"{name}: largest {ratio[worst]:.3e} of its positive water (at {t[keep][worst[0]] / DAY:g} days), "
            f"first below zero: {first}")


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
    # Reported since 2026-09-30, no threshold. Missing data are not a failure.
    if "exp_negative_retained" in end and "exp_negative_retained" in start:
        print(f"    reported: q_tag_exp_negative's per-step gross {per_day('exp_negative_retained'):.3e} "
              f"of the water a day")
    else:
        print("    reported: q_tag_exp_negative's per-step gross a day: not available "
              "(the audit has no exp_negative_retained)")
    for tag in ("evap", "fcg"):
        print("    reported: " + source_negative_water(job, tag))

# V3. Amended 2026-09-30 (question 9): by column and time, from t*.
EPS = 1e-6
T_STAR_ROWS = (
    ("negative_water_interval_events", True),
    ("exp_negative_retained", True),
    ("exp_negloss_retained", False),  # built only if the owner asked for it (11.11.13)
)


def first_negative_hus(job, period):
    """Per column, the first output time with hus below zero anywhere in it."""
    t, hus, _ = read_named(job, "hus", period)
    if t is None:
        return None
    neg = (hus < 0).any(axis=1)
    return np.where(neg.any(axis=0), t[np.argmax(neg, axis=0)], np.inf)


def t_star_by_source():
    """{source: per-column first time (inf: none)} and the notes on skipped sources."""
    found, notes = {}, []
    for job, period, label in (("cr_s26", "1d", "hus daily"), ("cr_s26", "6h", "hus 6-hourly"),
                               ("cr_s26_untagged", "1d", "untagged hus daily")):
        first = first_negative_hus(job, period)
        if first is None:
            notes.append(f"{label}: missing, skipped")
        else:
            found[label] = first
    audit_rows = rows("cr_s26", "water_tag_audit.csv")
    ncol = len(next(iter(found.values()))) if found else 1
    for col, expected in T_STAR_ROWS:
        if not audit_rows:
            notes.append(f"audit {col}: no audit table, skipped")
        elif col not in audit_rows[0]:
            notes.append(f"audit {col}: " + ("not in the table, skipped" if expected else "no such field, not built"))
        else:
            hit = next((r["time"] for r in audit_rows if r[col] > 0), np.inf)
            found[f"audit {col}"] = np.full(ncol, hit)
    return found, notes


t_c, _ = read("cr_s26", "q_tag_pbl")
if t_c is None:
    print(f"V3 site 26: missing output: {verdict('V3', False)}")
else:
    found, notes = t_star_by_source()
    if len({len(v) for v in found.values()}) > 1:
        print(f"V3 site 26: the sources disagree on the number of columns: {verdict('V3', False)}")
        found = {}
    star = np.min(np.stack(list(found.values())), axis=0) if found else np.full(1, np.inf)
    earliest = {k: float(np.min(v)) for k, v in found.items()}
    source = min(earliest, key=earliest.get) if earliest and np.isfinite(min(earliest.values())) else None
    print("V3 site 26: t* (first time the parent is below zero in a column): "
          + ("none" if source is None else f"{earliest[source] / DAY:g} days, from {source}")
          + "; per source: " + ", ".join(f"{k} " + ("none" if not np.isfinite(v) else f"{v / DAY:g} d")
                                         for k, v in earliest.items())
          + (f"; {len(star)} columns" if len(star) > 1 else ""))
    for note in notes:
        print(f"    {note}")
    for tag in TAGS:
        tc, a, _ = read_named("cr_s26", f"q_tag_{tag}")
        tb, b, _ = read_named("cr_s26_main", f"q_tag_{tag}")
        if a is None or b is None or len(tc) < len(tb) or a.shape[1:] != b.shape[1:]:
            print(f"V3 site 26 q_tag_{tag}: missing output: {verdict(f'V3 {tag}', False)}")
            continue
        n = len(tb)
        if a.shape[2] != len(star):
            print(f"V3 site 26 q_tag_{tag}: {a.shape[2]} columns but t* has {len(star)}: {verdict(f'V3 {tag}', False)}")
            continue
        same = bits(a[:n]) == bits(b[:n])
        if same.all():
            print(f"V3 site 26 q_tag_{tag}: bit for bit at {n} outputs: pass")
        else:
            differs = (~same).any(axis=1)  # (time, column)
            allowed = tc[:n, None] >= star[None, :] - EPS
            bad = differs & ~allowed
            print(f"V3 site 26 q_tag_{tag}: {(~same).sum()} values differ, {int(bad.sum())} column outputs "
                  f"before t* or with no t*; first difference at {tc[:n][differs.any(axis=1)][0] / DAY:g} days: "
                  f"{verdict(f'V3 {tag}', not bad.any())}")

print("RESULT", "all rules pass" if not failed else f"failed: {failed}")
sys.exit(1 if failed else 0)
