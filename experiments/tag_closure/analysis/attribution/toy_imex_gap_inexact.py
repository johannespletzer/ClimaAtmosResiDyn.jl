# The same scalar toy as toy_imex_gap.py, now with an inexact parent Jacobian:
# one Newton step with W = 1 + dtg*kappa*lam instead of 1 + dtg*lam, so the parent's
# implicit stage increment is not the exact backward-Euler one (a Newton defect).
# Prints the steady drift of R = E - T per step in units of dt*f.
import numpy as np
g = 1 - np.sqrt(2)/2; d = 1 - 1/(2*g)
A_exp = np.array([[0,0,0],[g,0,0],[d,1-d,0]]); b_exp = A_exp[2]
A_imp = np.array([[0,0,0],[0,g,0],[0,1-g,g]]); b_imp = A_imp[2]
def step(E, T, dt, lam, f, mode, kappa, tag_ratio=1/1.4):
    Ts_exp=np.zeros(3); Ts_imp=np.zeros(3); Tt_exp=np.zeros(3); Tt_imp=np.zeros(3)
    for i in range(3):
        temp = E + dt*(A_exp[i,:i]@Ts_exp[:i] + A_imp[i,:i]@Ts_imp[:i])
        dtg = dt*A_imp[i,i]
        if dtg > 0:
            U = temp + dtg*(-lam*temp)/(1 + dtg*kappa*lam)   # one Newton step, inexact W
            Ts_imp[i] = (U - temp)/dtg
            if mode=='opt1': Tt_imp[i] = -lam*temp
            elif mode=='opt2': Tt_imp[i] = -lam*temp/(1 + dtg*lam*tag_ratio)
            elif mode=='stage_increment': Tt_imp[i] = Ts_imp[i]          # share the parent's stage increment
        else: U = temp
        Ts_exp[i] = f
        Tt_exp[i] = f + (-lam*U if mode=='opt3' else 0.0)
    return E + dt*(b_exp@Ts_exp + b_imp@Ts_imp), T + dt*(b_exp@Tt_exp + b_imp@Tt_imp)
for kappa in [1.0, 0.7, 0.5]:
    print(f'kappa = {kappa} (parent Jacobian / true derivative)')
    print('  dt*lam |      opt1         opt2         opt3   stage-increment')
    for dtlam in [0.5, 1, 2, 4, 10]:
        out=[]
        for mode in ['opt1','opt2','opt3','stage_increment']:
            E=1.0; T=E
            for n in range(400): E,T=step(E,T,1.0,dtlam,1.0,mode,kappa)
            R0=E-T; E,T=step(E,T,1.0,dtlam,1.0,mode,kappa); out.append((E-T)-R0)
        print(f'  {dtlam:6.2f} | ' + '  '.join(f'{x:11.3e}' for x in out))
