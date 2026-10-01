# Scalar IMEX ARK stepper (CTS imex_ark.jl) for one cell: explicit forcing gain G
# (bracketed, rule A: gain withheld where P < 0 at the stage), an implicit sink
# S (constant, treated implicitly, not a bracketed gain). Tracks the parent P,
# a source tag s that lists the forcing (holds nothing at start), the ledger L.
import numpy as np
def ars222():
    g = 1 - np.sqrt(2)/2; d = 1 - 1/(2*g)
    ae = np.array([[0,0,0],[g,0,0],[d,1-d,0]]); ai = np.array([[0,0,0],[0,g,0],[0,1-g,g]])
    return ae, ae[-1], ai, ai[-1]
def ars343():
    g = 0.4358665215084590; a42 = 0.5529291480359398; a43 = a42
    b1 = -1.5*g**2 + 4*g - 0.25; b2 = 1.5*g**2 - 5*g + 1.25
    a31 = (1-4.5*g+1.5*g**2)*a42 + (2.75-10.5*g+3.75*g**2)*a43 - 3.5 + 13*g - 4.5*g**2
    a32 = (-1+4.5*g-1.5*g**2)*a42 + (-2.75+10.5*g-3.75*g**2)*a43 + 4 - 12.5*g + 4.5*g**2
    ae = np.array([[0,0,0,0],[g,0,0,0],[a31,a32,0,0],[1-a42-a43,a42,a43,0]])
    be = np.array([0,b1,b2,g])
    ai = np.array([[0,0,0,0],[0,g,0,0],[0,(1-g)/2,g,0],[0,b1,b2,g]])
    return ae, be, ai, ai[-1]
def step(tab, P, s, L, G, S, dt):
    ae, be, ai, bi = tab; ns = len(be)
    Te = np.zeros((ns,3)); Ti = np.zeros((ns,3))
    for i in range(ns):
        U = np.array([P, s, L]) + dt*(ae[i,:i] @ Te[:i]) + dt*(ai[i,:i] @ Ti[:i])
        if ai[i,i] != 0:
            # implicit: dP/dt = -S (constant); tags and ledger have no implicit term here
            Ti[i] = np.array([-S, 0, 0]); U = U + dt*ai[i,i]*Ti[i]
        Pst = U[0]
        gain = G if Pst >= 0 else 0.0              # water_tag_target_gain for the source tag
        w = G if Pst < 0 else 0.0                  # ledger tendency
        Te[i] = np.array([G, gain, w])
    X = np.array([P, s, L]) + dt*(be @ Te) + dt*(bi @ Ti)
    return X, Te
for name, tab in (("ARS222", ars222()), ("ARS343", ars343())):
    print(name, "b_exp =", np.round(tab[1], 4), "b_imp =", np.round(tab[3], 4))
# ARS343, pure source from -s*G*dt, s in (0.436, 0.718]: tag gets (b2+g)*G*dt
G, dt = 1.0, 1.0
for s0 in (0.5, 0.6):
    X, _ = step(ars343(), -s0, 0.0, 0.0, G, 0.0, dt)
    print(f"ARS343 from -{s0}: source tag {X[1]:+.4f}  ledger {X[2]:+.4f}  parent {X[0]:+.4f}")
# ARS222: parent at +eps at step start, implicit sink takes it below zero by stage 2
X, Te = step(ars222(), 1e-3, 0.0, 0.0, G, 5.0, dt)
print(f"ARS222 from +1e-3 with sink 5: stage gains {Te[:,1]}, source tag {X[1]:+.4f}, ledger {X[2]:+.4f}, parent {X[0]:+.4f}")
# (I3) with c := sum(b*Tdot) - dT (the overclaim): neg part moves by dL + c
for P0, S in ((-0.2, 0.0), (1e-3, 5.0), (-0.5, 0.0)):
    tab = ars222(); X, Te = step(tab, P0, 0.0, 0.0, G, S, dt)
    dT = max(X[0],0) - max(P0,0); sumbT = dt*(tab[1] @ Te[:,1]); c = sumbT - dT
    dneg = min(X[0],0) - min(P0,0)
    print(f"ARS222 P0={P0:+.3f} S={S}: dL={X[2]:+.4f} c={c:+.4f} dL+c={X[2]+c:+.4f} d(neg part)={dneg:+.4f}")
