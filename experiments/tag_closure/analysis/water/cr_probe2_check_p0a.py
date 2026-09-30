"""C's revision, 11.11.11 item 9: W0's P0a for a check run of the probe driver.

    python3 cr_probe2_check_p0a.py CHECK_OUTPUT_DIR REFERENCE_OUTPUT_DIR

Both are `output_NNNN` directories. The reference is `ic_s23_c`'s (and so
`ic_miss_probe2_s23`'s, which P0a scores against it). The model's twelve field
files of the check are compared with the reference's, bit for bit, at every
output time they share, as `ic_miss_score2.py` does. A file missing from either
side, or no common time, fails. Every other NetCDF is a tag's or a ledger's and
is reported, not gated (P0b).
"""
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

MODEL_FIELDS = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")
MODEL_FILES = tuple(f"{v}_1d_inst.nc" for v in MODEL_FIELDS) + ("rhoa_6h_inst.nc", "hus_6h_inst.nc")


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def compare(path, other, var):
    with nc.Dataset(path) as a, nc.Dataset(other) as b:
        if var not in a.variables or var not in b.variables:
            return None
        ta, tb = np.asarray(a["time"][:]), np.asarray(b["time"][:])
        n = min(len(ta), len(tb))
        va = np.moveaxis(np.asarray(a[var][:]), a[var].dimensions.index("time"), 0)[:n]
        vb = np.moveaxis(np.asarray(b[var][:]), b[var].dimensions.index("time"), 0)[:n]
        same = n > 0 and np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(va), bits(vb))
        scale = max(np.max(np.abs(vb)), np.finfo(float).tiny) if vb.size else 1.0
        rel = float(np.max(np.abs(va - vb)) / scale) if va.size else 0.0
        return same, rel, n, [float(x) for x in ta[:n]]


def main(check, ref):
    model, differ, times, tags, tags_differ = 0, [], set(), 0, []
    for path in sorted(glob.glob(os.path.join(check, "*.nc"))):
        name = os.path.basename(path)
        other = os.path.join(ref, name)
        if not os.path.exists(other):
            continue
        var = re.sub(r"_(1d|6h)_(inst|average)\.nc$", "", name)
        result = compare(path, other, var)
        if result is None:
            continue
        same, rel, n, ts = result
        if var in MODEL_FIELDS:
            model += 1
            times.update(ts)
            if not same:
                differ.append(f"{name} ({rel:.1e}, {n} times)")
        else:
            tags += 1
            if not same:
                tags_differ.append(f"{name} ({rel:.1e})")
    missing = [f for f in MODEL_FILES
               if not (os.path.exists(os.path.join(check, f)) and os.path.exists(os.path.join(ref, f)))]
    ok = model == len(MODEL_FILES) and not differ and not missing
    print(f"P0a, the model's fields are the reference's: {model} of {len(MODEL_FILES)} files compared at "
          f"{len(times)} output times ({sorted(times)}), missing: {missing or 'none'}, "
          f"differing: {differ or 'none'}: {'pass' if ok else 'FAIL'}")
    print(f"P0b, the tags' fields (reported): {tags} files compared, differing: {len(tags_differ)}"
          + (f": {', '.join(tags_differ)}" if tags_differ else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
