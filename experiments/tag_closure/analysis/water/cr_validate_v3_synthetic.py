"""Synthetic inputs for V3 of cr_validate.py, the fallback by column and time
(design/NEGATIVE_PARENT_WATER.md, section 11.7 amendment for question 9, and
item 7 of the score scripts' changes). It checks V3's parsing and verdicts
only. The fields are made up: 5 levels, daily outputs to day 6, 6-hourly ones,
`hus` at 1e-3 unless a case sets it below zero.

    python3 cr_validate_v3_synthetic.py TEST_ROOT

For each case it writes `cr_s26`, `cr_s26_main` and `cr_s26_untagged` under
TEST_ROOT/<case>/, runs `cr_validate.py` on it (`CR_SCRIPT_DIR` names another
copy, for a mutant) and reads its "V3 site 26 q_tag_pbl" line. Every other
rule has no data there and fails, which is not looked at. Exit 0 means every
case gave the verdict it should:

  bit_for_bit          no difference, no t*                              pass
  before_t_star        differs at day 2, hus below zero from day 3        FAIL
  after_t_star_clean   differs at day 4 in a cell never negative          pass
  no_t_star            differs at day 4, nothing ever negative            FAIL
  ledger_only_after    t* only from exp_negative_retained (day 2.5),
                       no negative hus, no event; differs at day 4        pass
  ledger_only_before   the same t*, differs at day 2                      FAIL
  at_t_star            differs at day 3, the audit row at day 3           pass
  event_only_after     negative_water_interval_events from day 1.5,
                       differs at day 2                                   pass
  untagged_hus_only    only the untagged twin's hus is below zero (day 3),
                       differs at day 4                                   pass
  hus_6h_only          only the 6-hourly hus below zero (day 3.25), which
                       no daily output shows; differs at day 4            pass
  two_columns          column 0 negative at day 3, differs at day 4 in
                       column 1, which never is                           FAIL
  two_columns_own      both columns differ at day 4, column 0 negative at
                       day 3, column 1 at day 4                           pass
  old_audit            the audit has no t* columns; differs at day 4       FAIL
"""
import csv
import os
import subprocess
import sys
import warnings

import netCDF4 as nc
import numpy as np

# netCDF4 sets an array shape in place, which NumPy 2.5 deprecates. It is not ours.
warnings.filterwarnings("ignore", category=DeprecationWarning)
TEST = sys.argv[1]
HERE = os.environ.get("CR_SCRIPT_DIR", os.path.dirname(os.path.abspath(__file__)))
DAY = 86400.0
NZ = 5
TAGS = ("pbl", "free", "evap", "fcg")
T1D = np.arange(0, 7) * DAY
T6H = np.arange(0, 25) * DAY / 4


def write(path, var, unit, times, data, dims):
    """data: (time, z, *columns) -> the file's dims order, time last."""
    with nc.Dataset(path, "w") as d:
        d.createDimension("time", len(times))
        d.createDimension("z", NZ)
        for k, n in enumerate(dims[:-2]):
            d.createDimension(n, data.shape[2 + k])
        d.createVariable("time", "f8", ("time",))[:] = times
        d.createVariable("z", "f8", ("z",))[:] = 30.0 * (1 + np.arange(NZ))
        v = d.createVariable(var, "f8", dims)
        v[:] = np.moveaxis(data, [0, 1], [-1, -2]).copy()
        v.units = unit


def field(times, columns, negative=None):
    """1e-3, below zero from `negative` = {column: (day, level)} on."""
    a = np.full((len(times), NZ, columns), 1e-3)
    for col, (day, lev) in (negative or {}).items():
        a[times >= day * DAY - 1e-6, lev, col] = -1e-5
    return a


def audit(path, rows, columns):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time"] + columns)
        for k in range(0, 25):
            t = k * DAY / 4
            w.writerow([t] + [rows.get(c, lambda t: 0.0)(t) for c in columns])


def build(name, columns=1, hus_rev=None, hus_untagged=None, hus_6h=None, diffs=(), events=None,
          ledger=None, audit_columns=("negative_water_interval_events", "exp_negative_retained")):
    """diffs: [(day, level, column)]: q_tag_pbl of cr_s26 differs from main's there."""
    root = os.path.join(TEST, name)
    dims = ("z", "time") if columns == 1 else ("x", "z", "time")
    for job in ("cr_s26", "cr_s26_main", "cr_s26_untagged"):
        os.makedirs(os.path.join(root, job, "output_0000"), exist_ok=True)
    out = lambda job: os.path.join(root, job, "output_0000")
    daily, sixh = hus_rev or {}, hus_6h if hus_6h is not None else (hus_rev or {})
    write(os.path.join(out("cr_s26"), "hus_1d_inst.nc"), "hus", "kg kg^-1", T1D, field(T1D, columns, daily), dims)
    write(os.path.join(out("cr_s26"), "hus_6h_inst.nc"), "hus", "kg kg^-1", T6H, field(T6H, columns, sixh), dims)
    write(os.path.join(out("cr_s26_untagged"), "hus_1d_inst.nc"), "hus", "kg kg^-1", T1D,
          field(T1D, columns, hus_untagged if hus_untagged is not None else daily), dims)
    rng = np.random.default_rng(1)
    for tag in TAGS:
        base = rng.random((len(T1D), NZ, columns)) * 1e-3
        rev = base.copy()
        if tag == "pbl":
            for day, lev, col in diffs:
                rev[T1D == day * DAY, lev, col] += 1e-9
        write(os.path.join(out("cr_s26_main"), f"q_tag_{tag}_1d_inst.nc"), f"q_tag_{tag}", "kg kg^-1", T1D, base, dims)
        write(os.path.join(out("cr_s26"), f"q_tag_{tag}_1d_inst.nc"), f"q_tag_{tag}", "kg kg^-1", T1D, rev, dims)
    cols = {"negative_water_interval_events": events, "exp_negative_retained": ledger}
    audit(os.path.join(out("cr_s26"), "water_tag_audit.csv"),
          {c: (lambda t, d=d: 1.0 if t >= d * DAY - 1e-6 else 0.0) for c, d in cols.items() if d is not None},
          list(audit_columns))
    return root


# name: (builder arguments, expected verdict)
CASES = {
    "bit_for_bit": (dict(), "pass"),
    "before_t_star": (dict(hus_rev={0: (3, 0)}, diffs=[(2, 1, 0)]), "FAIL"),
    "after_t_star_clean": (dict(hus_rev={0: (3, 0)}, diffs=[(4, 3, 0)]), "pass"),
    "no_t_star": (dict(diffs=[(4, 2, 0)]), "FAIL"),
    "ledger_only_after": (dict(ledger=2.5, diffs=[(4, 2, 0)]), "pass"),
    "ledger_only_before": (dict(ledger=2.5, diffs=[(2, 2, 0)]), "FAIL"),
    "at_t_star": (dict(ledger=3.0, diffs=[(3, 2, 0)]), "pass"),
    "event_only_after": (dict(events=1.5, diffs=[(2, 2, 0)]), "pass"),
    "untagged_hus_only": (dict(hus_rev={}, hus_untagged={0: (3, 0)}, diffs=[(4, 2, 0)]), "pass"),
    "hus_6h_only": (dict(hus_rev={}, hus_6h={0: (3.25, 0)}, diffs=[(4, 2, 0)]), "pass"),
    "two_columns": (dict(columns=2, hus_rev={0: (3, 0)}, diffs=[(4, 2, 1)]), "FAIL"),
    "two_columns_own": (dict(columns=2, hus_rev={0: (3, 0), 1: (4, 0)}, diffs=[(4, 2, 0), (4, 2, 1)]), "pass"),
    "old_audit": (dict(audit_columns=("fix_events",), diffs=[(4, 2, 0)]), "FAIL"),
}

bad = []
for name, (kwargs, expected) in CASES.items():
    root = build(name, **kwargs)
    res = subprocess.run([sys.executable, os.path.join(HERE, "cr_validate.py"), root], capture_output=True, text=True)
    lines = [l for l in res.stdout.splitlines() if l.startswith("V3 site 26 q_tag_pbl")]
    tstar = [l for l in res.stdout.splitlines() if l.startswith("V3 site 26: t*")]
    got = None if not lines else ("pass" if lines[0].endswith(": pass") else "FAIL" if lines[0].endswith(": FAIL") else "?")
    ok = got == expected
    print(f"{'ok ' if ok else 'BAD'} {name}: expected {expected}, got {got}; "
          f"{(tstar[0].split('; per source')[0] if tstar else res.stderr[-300:])}")
    if not ok:
        bad.append(name)
print("SYNTHETIC", "all cases hold" if not bad else f"FAILED: {bad}")
sys.exit(1 if bad else 0)
