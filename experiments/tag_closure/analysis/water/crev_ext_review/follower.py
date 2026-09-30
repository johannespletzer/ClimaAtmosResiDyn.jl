# Replica of correct_water_tag_increment! (tagged_water_increment.jl:293-487)
# on one column, unit dz, flat grid, dtγ = 1, partition tags only.
import numpy as np
T = lambda P: np.where(P < 0, 0.0, P)
negp = lambda P: np.where(P < 0, P, 0.0)
def lw(m, M): return np.maximum(m, 0.0) if M >= 0 else np.maximum(-m, 0.0)
def frac(tag, P):  # water_tag_fraction
    return np.where(P > 0, np.clip(np.divide(tag, P, out=np.zeros_like(tag), where=P!=0), 0, 1), 0.0)

def follower(P_snap, P_new, tags_snap, tags_after, dL=None):
    n = len(P_snap); tags_after = [np.array(t, float) for t in tags_after]
    Pi_snap = sum(tags_snap); Pi_after = sum(tags_after)
    m = (T(P_new) - T(P_snap)) - (Pi_after - Pi_snap)
    nn = negp(P_snap) - negp(P_new)
    if dL is not None:
        nn = np.where(dL == 0, nn, nn + dL)       # the design's n'
    M = m.sum(); N = nn.sum()
    P_U = P_new
    norm = sum(frac(t, P_U) for t in tags_after)
    pos = sum(np.maximum(t, 0) for t in tags_after)
    def share(t):
        s_pos = np.where(norm > 0, frac(t, P_U)/np.where(norm > 0, norm, 1), 0.0)
        s_neg = np.where(pos > 0, np.clip(np.divide(t, pos, out=np.zeros_like(t), where=pos!=0), 0, 1), 0.0)
        return np.where(P_U < 0, s_neg, s_pos)
    cond = np.where(P_U < 0, pos > 0, norm > 0)
    wN = np.where(cond, lw(m, N), 0.0); WN = wN.sum()
    if not WN > 0: N = 0.0
    M = M - N
    wL = lw(m, M); WL = wL.sum()
    left = wL*(M/WL if WL > 0 else 0.0)
    give = wN*(N/WN if WN > 0 else 0.0)
    rest = m - left - give
    I = np.concatenate([[0.0], np.cumsum(rest)])       # faces 0..n
    F = -I; F[0] = 0.0; F[-1] = 0.0                     # ᶜadvdivᵥ: zero at both boundary faces
    top_flux_intended = -I[-1]
    out = []
    for t in tags_after:
        s = share(t); d = np.zeros(n)
        for f in range(1, n):
            donor = f-1 if F[f] > 0 else f
            flux = F[f]*s[donor]
            d[f-1] -= flux; d[f] += flux
        if N != 0: d += give*s
        out.append(t + d)
    return dict(m=m, n=nn, N=N, M_minus_N=M, left=left, give=give, rest=rest,
                tags=out, part=sum(out), target=T(P_new), top=top_flux_intended)

def show(tag, r, P_new):
    print(f"--- {tag}")
    print("  m        ", np.round(r['m'], 4), " N'=", round(r['N'], 4), " M-N'=", round(r['M_minus_N'], 4))
    print("  left     ", np.round(r['left'], 4), " give", np.round(r['give'], 4))
    print("  partition", np.round(r['part'], 4))
    print("  target   ", np.round(r['target'], 4), " excess(part-target)", np.round(r['part']-r['target'], 4))
    print("  column: partition change", round(float(r['part'].sum()), 4))

# S1: cell 1 stays negative; the implicit bracket withheld 0.4; advection
# mismatch +0.3 in cell 2, -0.3 in cell 3 (tags do not take implicit advection).
P_snap = np.array([1.0, -1.0, 1.0, 1.0])
P_new  = np.array([1.0, -0.6, 1.3, 0.7])
tA = np.array([0.5, 0.0, 0.5, 0.5]); tB = np.array([0.5, 0.0, 0.5, 0.5])
for lab, dL in (("S1 unamended (n)", None), ("S1 amended (n' = n + dL)", np.array([0, 0.4, 0, 0.0]))):
    r = follower(P_snap, P_new, [tA, tB], [tA, tB], dL)
    show(lab, r, P_new)
    print("  target column change", round(float((T(P_new)-T(P_snap)).sum()), 4),
          "; max |left|/|m| where m!=0:", np.round(np.max(np.abs(r['left'][r['m']!=0]/r['m'][r['m']!=0])), 3))

# S2: crossing cell 1 (-0.5 -> 0.3 by a withheld stage gain of 0.8) whose
# partition is empty; cell 2 positive with an empty partition (recently crossed);
# cells 3, 4 hold water, advection mismatch +0.1 / -0.1.
P_snap = np.array([1.0, -0.5, 0.2, 1.0, 1.0])
P_new  = np.array([1.0,  0.3, 0.2, 1.1, 0.9])
tA = np.array([1.0, 0.0, 0.0, 0.5, 0.5]); tB = np.array([0.0, 0.0, 0.0, 0.5, 0.5])
r = follower(P_snap, P_new, [tA, tB], [tA, tB], np.array([0, 0.8, 0, 0, 0.0]))
show("S2 amended, crossing cell and donor cell 2 empty", r, P_new)
print("  tags A,B in cell 2:", np.round([r['tags'][0][2], r['tags'][1][2]], 4))

r = follower(P_snap, P_new, [tA, tB], [tA, tB], None)
show("S2 unamended (Q3 rule, old n)", r, P_new)
# Before Q3 (ParentGain): the tags in cell 1 took the stage's gain 0.8 by mask (A: 1, B: 0).
tA_after = tA + np.array([0, 0.8, 0, 0, 0]);
r = follower(P_snap, P_new, [tA, tB], [tA_after, tB], None)
show("S2 before Q3 (ParentGain in the implicit bracket)", r, P_new)

# Pre-existing loss-side case (the owner point): an unshared loss of 0.4 in a
# cell below zero (default split, S = 0 there), advection mismatch +-0.3.
P_snap = np.array([1.0, -1.0, 1.0, 1.0]); P_new = np.array([1.0, -1.4, 1.3, 0.7])
tA = np.array([0.5, 0.0, 0.5, 0.5]); tB = np.array([0.5, 0.0, 0.5, 0.5])
for lab, dL in (("loss: n (current code)", None), ("loss: n + dL- (negloss)", np.array([0, -0.4, 0, 0.0]))):
    r = follower(P_snap, P_new, [tA, tB], [tA, tB], dL)
    show(lab, r, P_new)
    print("  partition column change", round(float(r['part'].sum() - (tA+tB).sum()), 4), " target column change", round(float((T(P_new)-T(P_snap)).sum()), 4))
