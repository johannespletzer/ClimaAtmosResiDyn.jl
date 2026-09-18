# Scalar toy of one stiff mode, dE/dt = f - lam*E, with f explicit and -lam*E implicit,
# stepped with ARS222 as ClimaTimeSteppers does (b = last row, one exact Newton step).
# The tags' sum T follows the same f exactly (a bracket) and the parent's -lam*E by one
# of the C1c placements. Prints the drift of R = E - T per step, in units of dt*f,
# once E is steady. Illustrative only: one mode, no cross-coupling, no shares.
import numpy as np
g = 1 - np.sqrt(2)/2; d = 1 - 1/(2*g)
A_exp = np.array([[0,0,0],[g,0,0],[d,1-d,0]]); b_exp = A_exp[2]
A_imp = np.array([[0,0,0],[0,g,0],[0,1-g,g]]); b_imp = A_imp[2]
def step(E, T, dt, lam, f, mode, lam_tag_ratio=1/1.4):
    s = 3; Ts_exp = np.zeros(s); Ts_imp = np.zeros(s)   # parent tendencies
    Tt_exp = np.zeros(s); Tt_imp = np.zeros(s)          # tags' sum tendencies
    for i in range(s):
        temp = E + dt*(A_exp[i,:i]@Ts_exp[:i] + A_imp[i,:i]@Ts_imp[:i])
        dtg = dt*A_imp[i,i]
        if dtg > 0:
            U = temp/(1 + dtg*lam)          # parent: exact for this linear mode
            Ts_imp[i] = (U - temp)/dtg
            if mode == 'opt1':   Tt_imp[i] = -lam*temp                 # flux at the initial guess, no block
            elif mode == 'opt2': Tt_imp[i] = -lam*temp/(1 + dtg*lam*lam_tag_ratio)  # tracer block, weaker by cv/cp
            elif mode == 'diagblock': Tt_imp[i] = -lam*temp/(1 + dtg*lam)        # tags given the parent's own diagonal block
            elif mode == 'opt3': Tt_imp[i] = 0.0
        else:
            U = temp
        Ts_exp[i] = f                      # the explicit forcing, bracketed exactly for the tags
        Tt_exp[i] = f + (-lam*U if mode == 'opt3' else 0.0)   # opt3: parent's flux at the solved stage state, explicit weights
    E1 = E + dt*(b_exp@Ts_exp + b_imp@Ts_imp)
    T1 = T + dt*(b_exp@Tt_exp + b_imp@Tt_imp)
    return E1, T1
print('dt*lam | drift of R per step / (dt f):   opt1      opt2(cv/cp)   diag-block   opt3')
for dtlam in [0.05, 0.2, 0.5, 1, 2, 4, 10, 30]:
    dt=1.0; lam=dtlam/dt; f=1.0
    out=[]
    for mode in ['opt1','opt2','diagblock','opt3']:
        E=f/lam; T=E
        for n in range(200): E,T = step(E,T,dt,lam,f,mode)
        R0 = E-T; E,T = step(E,T,dt,lam,f,mode); out.append((E-T)-R0)
    print(f'{dtlam:6.2f} | ' + '  '.join(f'{x:12.4e}' for x in out))
