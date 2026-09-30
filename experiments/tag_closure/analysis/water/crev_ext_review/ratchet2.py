import numpy as np
import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'stages.py')).read().split('for name, tab')[0])
ae, be, ai, bi = ars222()
# Implicit sink: relaxation -k*P (bracketed loss where P>0 shares clamp(s/P)),
# plus an extra constant sink Sx; explicit forcing gain G (bracketed; source
# tag s lists it). k is solved implicitly (linear), as the model would.
def step(P, s, G, k, Sx, dt, rule):
    Te = np.zeros((3,2)); Ti = np.zeros((3,2))
    for i in range(3):
        U = np.array([P, s]) + dt*(ae[i,:i] @ Te[:i]) + dt*(ai[i,:i] @ Ti[:i])
        if ai[i,i] != 0:
            h = dt*ai[i,i]
            # one Newton iteration on a linear problem: exact solve for P
            Pn = (U[0] - h*Sx)/(1 + h*k) if U[0] > 0 else U[0] - h*Sx
            sink = (U[0] - Pn)/h                    # the stage's sink rate
            Pp = U[0]                               # shares at the iterate (predictor)
            phi = min(max(U[1]/Pp, 0.0), 1.0) if Pp > 0 else 0.0
            Ti[i] = np.array([-sink, -phi*sink]); U = U + h*Ti[i]
        gain = (G if U[0] >= 0 else 0.0) if rule == 'A' else G
        Te[i] = np.array([G, gain])
    return np.array([P, s]) + dt*(be @ Te) + dt*(bi @ Ti)
dt, G = 10.0, 1e-7
for rule in ('A', 'parent'):
    P, s = 1e-4, 0.0
    ends = []
    for cyc in range(40):
        # wet: gain, mild drain
        for n in range(200): P, s = step(P, s, G, 1e-4, 0.0, dt, rule)
        # strong constant sink pushes P below zero; stays negative a while
        while P > -2e-6: P, s = step(P, s, G, 0.0, 3e-7, dt, rule)
        for n in range(20): P, s = step(P, s, G, 0.0, 1.5e-7, dt, rule)
        # recovery: gain only until positive again, then drain to near zero
        while P < 0: P, s = step(P, s, G, 0.0, 0.0, dt, rule)
        for n in range(400): P, s = step(P, s, 0.0, 5e-3, 0.0, dt, rule)
        ends.append((P, s))
    print(f"rule {rule:6s}: end of cycles 1,10,40: s = {ends[0][1]:+.3e}, {ends[9][1]:+.3e}, {ends[39][1]:+.3e}; T = {max(ends[39][0],0):.3e}")
