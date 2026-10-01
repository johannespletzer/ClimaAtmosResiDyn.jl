import numpy as np
# The follower's dL = fl(L + dtγ·w) - L on a cumulative ledger L (identity row,
# one Newton iteration), against the stage's own dtγ·w.
for FT in (np.float32, np.float64):
    for L, x in ((1e-6, 1e-9), (1e-4, 1e-9), (1e-3, 1e-9), (1e-2, 1e-9), (1e-2, 1e-10)):
        L_, x_ = FT(L), FT(x)
        dL = FT(L_ + x_) - L_
        print(f"{FT.__name__:8s} L={L:.0e} dtγw={x:.0e}: dL={float(dL):.4e} rel.err={abs(float(dL)-float(x_))/float(x_):.2e} {'-> dL == 0, n kept' if dL == 0 else ''}")
# Steps in 90 days at dt = 10 s, and the relative error of dL once L has summed that many equal gains
n = 90*86400/10
for FT, eps in ((np.float32, 2.0**-24), (np.float64, 2.0**-53)):
    print(f"{FT.__name__}: after N={n:.0f} equal stage gains, |err dL|/dtγw up to ~ N*eps = {n*eps:.2e}")
