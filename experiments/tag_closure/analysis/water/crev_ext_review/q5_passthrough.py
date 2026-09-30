# Replica of water_tag_pool_shares and water_tag_gross_flow_change
# (tagged_water_precipitation.jl:938-1003), old code and the design's Q5 rule 1
# (full_X &= !(X < 0), so psi_X = phi_X = 0) plus rule 2 (receiver X<0 takes nothing).
import numpy as np

def pool_shares(F, qN, qR, qS, dt, pN, pR, pS, gate=(False, False, False)):
    fullN = qN + dt*(F['RN']+F['SN']) > 0 and not gate[0]
    fullR = qR + dt*(F['NR']+F['SR']) > 0 and not gate[1]
    fullS = qS + dt*(F['NS']+F['RS']) > 0 and not gate[2]
    a11 = qN + dt*(F['RN']+F['SN']) if fullN else 1.0
    a12 = -dt*F['RN'] if fullN else 0.0
    a13 = -dt*F['SN'] if fullN else 0.0
    a21 = -dt*F['NR'] if fullR else 0.0
    a22 = qR + dt*(F['NR']+F['SR']) if fullR else 1.0
    a23 = -dt*F['SR'] if fullR else 0.0
    a31 = -dt*F['NS'] if fullS else 0.0
    a32 = -dt*F['RS'] if fullS else 0.0
    a33 = qS + dt*(F['NS']+F['RS']) if fullS else 1.0
    b1 = qN*pN if fullN else pN
    b2 = qR*pR if fullR else pR
    b3 = qS*pS if fullS else pS
    A = np.array([[a11,a12,a13],[a21,a22,a23],[a31,a32,a33]])
    if np.linalg.det(A) <= 0: return pN, pR, pS
    x = np.linalg.solve(A, np.array([b1,b2,b3]))
    return x

def gross(F, psN, psR, psS, gate=(False, False, False)):
    # receiver gains gated where the receiver compartment is negative (rule 2)
    gN = 0.0 if gate[0] else 1.0
    gR = 0.0 if gate[1] else 1.0
    gS = 0.0 if gate[2] else 1.0
    dN = gN*(F['RN']*psR + F['SN']*psS) - (0.0 if gate[0] else (F['NR']+F['NS'])*psN)
    dR = gR*(F['NR']*psN + F['SR']*psS) - (0.0 if gate[1] else (F['RN']+F['RS'])*psR)
    dS = gS*(F['NS']*psN + F['RS']*psR) - (0.0 if gate[2] else (F['SN']+F['SR'])*psS)
    return dN, dR, dS

# Snow compartment negative (S = -2e-7 kg/kg): deposition N->S and melting S->R
# in the same step, f = 1e-8 /s each. Two partition tags.
f = 1e-8; dt = 10.0
F = dict(NR=0.0, NS=f, RN=0.0, RS=0.0, SN=0.0, SR=f)
qN, qR, qS = 5e-3, 1e-4, 0.0          # pools: max(X,0); S < 0 so qS = 0
tags_phiN = [0.6, 0.4]; tags_phiR = [0.2, 0.8]; tags_phiS = [0.0, 0.0]  # phi_S = 0 where S <= 0
for label, gate in (("old", (False, False, False)), ("Q5 rule 1+2", (False, False, True))):
    tot = np.zeros(3)
    for pN, pR, pS in zip(tags_phiN, tags_phiR, tags_phiS):
        ps = pool_shares(F, qN, qR, qS, dt, pN, pR, pS, gate)
        tot += np.array(gross(F, *ps, gate))
    print(f"{label:12s}: partition parts' rates dN={tot[0]:+.3e} dR={tot[1]:+.3e} dS={tot[2]:+.3e}")
# The target: T_N = max(N,0) loses f, T_R gains f, T_S stays 0 (S stays negative).
print(f"target      : dT_N={-f:+.3e} dT_R={+f:+.3e} dT_S={0.0:+.3e}")

# Alternative: keep the negative compartment's pool (its inflow composition),
# gate only its own parts, cap its tagged outflow at its inflow.
def alt(F, qN, qR, qS, dt, pN, pR, pS, neg=(False, False, True)):
    ps = list(pool_shares(F, qN, qR, qS, dt, pN, pR, pS))
    inflow = [F['RN']+F['SN'], F['NR']+F['SR'], F['NS']+F['RS']]
    outflow = [F['NR']+F['NS'], F['RN']+F['RS'], F['SN']+F['SR']]
    for i in range(3):
        if neg[i] and outflow[i] > 0:
            ps[i] *= min(1.0, inflow[i]/outflow[i])
    dN, dR, dS = gross(F, *ps)
    d = [dN, dR, dS]
    for i in range(3):
        if neg[i]: d[i] = 0.0
    return d
for fin, fout in ((f, f), (f, 0.4*f), (0.4*f, f)):
    F2 = dict(NR=0.0, NS=fin, RN=0.0, RS=0.0, SN=0.0, SR=fout)
    tot = np.zeros(3)
    for pN, pR, pS in zip(tags_phiN, tags_phiR, tags_phiS):
        tot += np.array(alt(F2, qN, qR, qS, dt, pN, pR, pS))
    print(f"alt in={fin:.1e} out={fout:.1e}: dN={tot[0]:+.3e} dR={tot[1]:+.3e} (target dT_N={-fin:+.3e} dT_R={fout:+.3e}); ledger net-in {max(fin-fout,0):.1e}, shortfall {max(fout-fin,0):.1e}")
