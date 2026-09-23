"""V-W1 parity: every field the untagged twin writes must equal the tagged
run's bit for bit (bit patterns, so signed zeros count)."""
import glob, os, numpy as np, netCDF4 as nc
O = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
a_dir = f"{O}/w0c_d4w_untagged/output_0000"; b_dir = f"{O}/w1_d4w_grid_tags/output_0000"
names = sorted(os.path.basename(f) for f in glob.glob(f"{a_dir}/*.nc"))
bad = 0
for f in names:
    var = f.split("_1h_inst")[0]
    with nc.Dataset(f"{a_dir}/{f}") as da, nc.Dataset(f"{b_dir}/{f}") as db:
        a = np.asarray(da[var][:]); b = np.asarray(db[var][:])
        ta = np.asarray(da["time"][:]); tb = np.asarray(db["time"][:])
    same_t = ta.shape == tb.shape and np.array_equal(ta.view(np.uint64), tb.view(np.uint64))
    same = a.shape == b.shape and a.dtype == b.dtype and np.array_equal(a.view(np.uint64), b.view(np.uint64))
    if not (same and same_t):
        bad += 1
        print(f"DIFFERS {var}: shapes {a.shape} {b.shape}, max|Δ| {np.max(np.abs(a - b)) if a.shape == b.shape else 'n/a'}")
print(f"{len(names)} fields compared, {len(names) - bad} bitwise identical over {len(ta)} outputs")
extra = sorted(set(os.path.basename(f) for f in glob.glob(f"{b_dir}/*.nc")) - set(names))
print("only in the tagged run:", [e.split('_1h_inst')[0] for e in extra])
