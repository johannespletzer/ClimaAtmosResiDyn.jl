# The review's replica of correct_water_tag_increment! (one column, unit dz,
# dtγ = 1, partition tags only), with the revision's crossing give g by mask.
import numpy as np
import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'follower.py')).read().split('def show')[0])
T = lambda P: np.where(P < 0, 0.0, P)
negp = lambda P: np.where(P < 0, P, 0.0)

def follower_g(P_snap, P_new, tags_snap, tags_after, masks, dL):
    n = len(P_snap)
    Pi_snap = sum(tags_snap); Pi_after = sum(tags_after)
    m = (T(P_new) - T(P_snap)) - (Pi_after - Pi_snap)
    nn = negp(P_snap) - negp(P_new)
    g = np.maximum(np.minimum(dL + negp(P_snap), T(P_new) - T(P_snap)), 0.0)
    g = np.where(dL == 0, 0.0, g)
    n2 = np.where(dL == 0, nn, nn + dL - g)
    m2 = np.where(dL == 0, m, m - g)
    # give g by mask, then run the unamended follower on (m2, n2) by passing
    # tags_after + mask*g and a P_new-consistent mismatch: emulate by shifting
    # the partition's 'after' so that its m equals m2.
    after_g = [t + mk * g for t, mk in zip(tags_after, masks)]
    # follower() recomputes m from tags; with after_g, m == m2. n is passed via dL trick:
    # follower uses nn + dL where dL != 0; give it dL' = n2 - nn where needed.
    dLp = np.where(dL == 0, 0.0, n2 - nn)
    dLp = np.where((dL != 0) & (dLp == 0), 1e-300, dLp)  # keep the ifelse branch
    return follower(P_snap, P_new, tags_snap, after_g, dLp), g

def show2(lab, r, g):
    print(f"--- {lab}")
    print("  g        ", np.round(g, 4))
    print("  N'=", round(float(r['N']), 4), " M'-N'=", round(float(r['M_minus_N']), 4))
    print("  partition", np.round(r['part'], 4))
    print("  target   ", np.round(r['target'], 4), " excess", np.round(r['part'] - r['target'], 4))

# S2 of the review, with the give by mask (masks A=1 in cells 0-2, B elsewhere)
P_snap = np.array([1.0, -0.5, 0.2, 1.0, 1.0]); P_new = np.array([1.0, 0.3, 0.2, 1.1, 0.9])
tA = np.array([1.0, 0.0, 0.0, 0.5, 0.5]); tB = np.array([0.0, 0.0, 0.0, 0.5, 0.5])
mA = np.array([1.0, 1.0, 1.0, 0.0, 0.0]); mB = 1 - mA
r, g = follower_g(P_snap, P_new, [tA, tB], [tA, tB], [mA, mB], np.array([0, 0.8, 0, 0, 0.0]))
show2("S2 with the crossing give by mask", r, g)
# S1 of the review: no crossing, the give must be zero and the result the amended one
P_snap = np.array([1.0, -1.0, 1.0, 1.0]); P_new = np.array([1.0, -0.6, 1.3, 0.7])
tA = np.array([0.5, 0.0, 0.5, 0.5]); tB = np.array([0.5, 0.0, 0.5, 0.5])
mA = np.array([1.0, 1.0, 0.0, 0.0]); mB = 1 - mA
r, g = follower_g(P_snap, P_new, [tA, tB], [tA, tB], [mA, mB], np.array([0, 0.4, 0, 0.0]))
show2("S1 with the crossing give (none)", r, g)
# S3: a crossing lifted partly by the withheld gain (0.3 of a deficit 0.5) and partly
# by implicit transport from the cell above (0.4, which the partition does not take).
P_snap = np.array([-0.5, 1.0, 1.0]); P_new = np.array([0.2, 0.6, 1.0])
tA = np.array([0.0, 1.0, 0.4]); tB = np.array([0.0, 0.0, 0.6])
mA = np.array([1.0, 1.0, 0.0]); mB = 1 - mA
r, g = follower_g(P_snap, P_new, [tA, tB], [tA, tB], [mA, mB], np.array([0.3, 0, 0.0]))
show2("S3 crossing: withheld 0.3 of a 0.5 deficit, transport 0.4 from above", r, g)
print("  tag A, B:", np.round(r['tags'][0], 4), np.round(r['tags'][1], 4))
