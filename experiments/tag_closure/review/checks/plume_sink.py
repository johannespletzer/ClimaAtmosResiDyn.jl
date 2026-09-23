import numpy as np
# Toy deep plume, 30 levels; grid-mean q_tot falls with height; two region tags: BL (k<6) and FT.
K=30; k=np.arange(K)
qbar = 0.016*np.exp(-k/8.0)
phiBL = (k<6).astype(float)
a = 0.08                       # entrainment weight per level (a/(1+a) in the plume step)
def plume(sink):
    q = qbar[0]; phi = phiBL[0]; out=[phi]; qs=[q]
    for i in range(1,K):
        qc = q*(1-sink[i])     # water carried up after the level's precipitation
        phi = (qc*phi + a*qbar[i]*phiBL[i])/(qc + a*qbar[i])
        q = (qc + a*qbar[i])/(1+a)
        out.append(phi); qs.append(q)
    return np.array(out), np.array(qs)
sink = np.where(k>=8, 0.15, 0.0)      # 15% of updraft water rains out per level above cloud base
phi_true, q_true = plume(sink)
phi_nosink, q_nosink = plume(np.zeros(K))
for i in (8,12,16,20,25,29):
    print(f"level {i:2d}: BL share with sink {phi_true[i]:.3f}  plume without sink {phi_nosink[i]:.3f}   q_u {q_true[i]*1e3:.2f} vs {q_nosink[i]*1e3:.2f} g/kg")
