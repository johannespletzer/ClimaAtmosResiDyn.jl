"""Independent re-derivation of V2, V4 and V4b of NEGATIVE_PARENT_WATER.md 11.7.

Written from 11.7's text and the model source only. It does not use
cr_validate.py or cr_windows_score.py.

V2: gross = int |max(rho q_tot, 0) - sum(region tags)| / int max(rho q_tot, 0).
    (a) from the run's own closure check, water_tag_closure.csv, gross_relative.
    (b) recomputed from the 6-hourly fields, with dz from the cell centres
        (faces rebuilt from z_f0 = 0, z_f(k+1) = 2 z_c(k) - z_f(k)).
V4: every model field file of the tagged run against its untagged twin.
V4b: every model field file of the revision run against the run on main.
Bit for bit means the raw bytes of the arrays are equal.
"""
import csv
import glob
import os
import numpy as np
import netCDF4 as nc

O = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
DAY = 86400.0
LIMIT = 2e-3
REGION_TAGS = ["pbl", "free"]


def out(run):
    return f"{O}/{run}/output_active"


def read(run, name, period):
    with nc.Dataset(f"{out(run)}/{name}_{period}_inst.nc") as d:
        d.set_auto_mask(False)
        return np.array(d["time"][:]), np.array(d["z"][:]), np.array(d[name][:])


def faces_from_centres(zc):
    zf = np.zeros(len(zc) + 1)
    for k, c in enumerate(zc):
        zf[k + 1] = 2 * c - zf[k]
    return zf


def closure_table(run):
    with open(f"{out(run)}/water_tag_closure.csv") as f:
        rows = list(csv.DictReader(f))
    t = np.array([float(r["time"]) for r in rows])
    g = np.array([float(r["gross_relative"]) for r in rows])
    tot = np.array([float(r["total"]) for r in rows])
    return t, g, tot


def v2(run):
    print(f"--- V2 {run}")
    t, g, tot = closure_table(run)
    sel = t <= 90 * DAY + 1e-6
    t, g, tot = t[sel], g[sel], tot[sel]
    i = int(np.argmax(g))
    above = np.nonzero(g > LIMIT)[0]
    first = t[above[0]] / DAY if len(above) else None
    print(f"  table: {len(t)} checks, days {t[0]/DAY:g} to {t[-1]/DAY:g}")
    print(f"  table: max gross_relative {g[i]:.4e} at day {t[i]/DAY:.2f}; "
          f"first above 0.2%: {first}; checks above: {len(above)}")
    # From the fields.
    tq, z, q = read(run, "hus", "6h")
    _, _, rho = read(run, "rhoa", "6h")
    tags = sum(read(run, f"q_tag_{n}", "6h")[2] for n in REGION_TAGS)
    _, _, res = read(run, "q_tag_res", "6h")
    dz = np.diff(faces_from_centres(z))
    print(f"  top face rebuilt: {faces_from_centres(z)[-1]:.6f} m")
    target = np.maximum(rho * q, 0.0)
    w = dz[:, None]
    scale = (w * target).sum(0)
    gross = (w * np.abs(target - rho * tags)).sum(0) / scale
    excess = (w * np.maximum(rho * tags - target, 0)).sum(0) / scale
    gross_res = (w * np.abs(rho * res)).sum(0) / scale
    # Area factor: table total over field total, should be constant.
    common = np.intersect1d(t, tq)
    it = np.searchsorted(t, common)
    iq = np.searchsorted(tq, common)
    ratio = tot[it] / scale[iq]
    print(f"  table total / field scale: {ratio.min():.10g} to {ratio.max():.10g}")
    sel = tq <= 90 * DAY + 1e-6
    j = int(np.argmax(gross[sel]))
    above = np.nonzero(gross[sel] > LIMIT)[0]
    first = tq[above[0]] / DAY if len(above) else None
    print(f"  fields: {sel.sum()} outputs; max gross {gross[j]:.4e} at day "
          f"{tq[j]/DAY:.2f}; first above 0.2%: {first}")
    print(f"  fields: max over-claim part (tags above target) {excess.max():.4e}; "
          f"max via q_tag_res {gross_res.max():.4e}")
    d = np.abs(gross[iq] - g[it])
    print(f"  fields vs table: max |diff| {d.max():.3e}")
    return g[i], t[i] / DAY, first


MODEL_FIELDS_1D = ["rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup"]


def same_bytes(a, b):
    a, b = np.asarray(a), np.asarray(b)
    return a.shape == b.shape and a.dtype == b.dtype and a.tobytes() == b.tobytes()


def compare(run_a, run_b, files):
    ok = True
    for fname in files:
        pa, pb = f"{out(run_a)}/{fname}", f"{out(run_b)}/{fname}"
        if not (os.path.exists(pa) and os.path.exists(pb)):
            print(f"  {fname}: MISSING in one run")
            ok = False
            continue
        with nc.Dataset(pa) as da, nc.Dataset(pb) as db:
            da.set_auto_mask(False)
            db.set_auto_mask(False)
            name = fname.split("_")[0]
            ta, tb = np.array(da["time"][:]), np.array(db["time"][:])
            va, vb = np.array(da[name][:]), np.array(db[name][:])
            line = f"  {fname}: {len(ta)} vs {len(tb)} times, last day {ta[-1]/DAY:g}"
            eq = same_bytes(ta, tb) and same_bytes(va, vb)
            if "z" in da.variables:
                eq = eq and same_bytes(np.array(da["z"][:]), np.array(db["z"][:]))
            if not eq:
                ok = False
                if va.shape == vb.shape:
                    diff = np.nonzero(np.any(
                        (va != vb).reshape(-1, va.shape[-1]), axis=0))[0]
                    line += f"; DIFFER, first at day {ta[diff[0]]/DAY:g}" if len(diff) else "; DIFFER (bytes)"
                    m = np.max(np.abs(va - vb))
                    line += f", max abs diff {m:.3e}"
                else:
                    line += "; DIFFER in shape"
            else:
                line += "; bit for bit"
            print(line)
    return ok


def model_files(run_untagged):
    # Every model field file the untagged twin wrote.
    fs = sorted(os.path.basename(p) for p in glob.glob(f"{out(run_untagged)}/*_inst.nc"))
    return fs


if __name__ == "__main__":
    res = {}
    for run in ["cr_s23", "cr_s26", "cr_s23_main", "cr_s26_main"]:
        res[run] = v2(run)
    for s in ["23", "26"]:
        rev, twin, main = f"cr_s{s}", f"cr_s{s}_untagged", f"cr_s{s}_main"
        fs = model_files(twin)
        print(f"--- V4 site {s}: {rev} vs {twin}, files {fs}")
        ok4 = compare(rev, twin, fs)
        print(f"  V4 site {s}: {'PASS' if ok4 else 'FAIL'}")
        fs_b = fs + ["hus_6h_inst.nc", "rhoa_6h_inst.nc"]
        print(f"--- V4b site {s}: {rev} vs {main}, {len(fs_b)} files")
        ok4b = compare(rev, main, fs_b)
        print(f"  V4b site {s}: {'PASS' if ok4b else 'FAIL'}")
        # Also: main against the untagged twin, for context.
        print(f"--- context site {s}: {main} vs {twin}")
        compare(main, twin, fs)
