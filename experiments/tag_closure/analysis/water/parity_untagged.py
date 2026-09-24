"""Parity of a tagged run with its untagged twin: every field the untagged run
writes must equal the tagged run's bit for bit (bit patterns, so signed zeros
count), at every output time. `d4w_parity.py` with the two directories as
arguments.

    python3 parity_untagged.py UNTAGGED_OUTPUT_DIR TAGGED_OUTPUT_DIR
"""
import glob
import os
import sys

import netCDF4 as nc
import numpy as np

a_dir, b_dir = sys.argv[1], sys.argv[2]
names = sorted(os.path.basename(f) for f in glob.glob(f"{a_dir}/*.nc"))
bad = 0
times = 0
for f in names:
    var = f.rsplit("_", 2)[0]
    with nc.Dataset(f"{a_dir}/{f}") as da, nc.Dataset(f"{b_dir}/{f}") as db:
        a = np.asarray(da[var][:]); b = np.asarray(db[var][:])
        ta = np.asarray(da["time"][:]); tb = np.asarray(db["time"][:])
    times = len(ta)
    same_t = ta.shape == tb.shape and np.array_equal(ta.view(np.uint64), tb.view(np.uint64))
    same = a.shape == b.shape and a.dtype == b.dtype and np.array_equal(
        a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32),
        b.view(np.uint64) if b.dtype == np.float64 else b.view(np.uint32),
    )
    if not (same and same_t):
        bad += 1
        print(f"DIFFERS {var}: shapes {a.shape} {b.shape}, max|d| "
              f"{np.max(np.abs(a - b)) if a.shape == b.shape else 'n/a'}")
print(f"RESULT {len(names)} fields compared, {len(names) - bad} bitwise identical over {times} outputs")
extra = sorted(set(os.path.basename(f) for f in glob.glob(f"{b_dir}/*.nc")) - set(names))
print("only in the tagged run:", [e.rsplit("_", 2)[0] for e in extra])
