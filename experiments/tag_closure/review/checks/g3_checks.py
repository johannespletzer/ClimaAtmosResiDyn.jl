import numpy as np
rng = np.random.default_rng(1)

print("=== 1. Exchange with weight q_tot: zero sum and non-negativity ===")
def share_diffs(eps_j, eps_bar, rho, rhoa_j, rhoa_0, Aj, A0, Abar, partition, per_source_theta):
    part = np.array(partition)
    tot = eps_bar[part].sum(); totj = eps_j[part].sum()
    if min(rhoa_j, rhoa_0, Aj, A0, Abar, tot, totj) <= 0:
        return np.zeros_like(eps_j), np.zeros_like(eps_j)
    phibar = np.minimum(eps_bar/tot, 1.0); phij = np.minimum(eps_j/totj, 1.0)
    diff = phij - phibar
    head = rho*Abar/(rhoa_j*Aj)
    limit = phibar*(head-1)
    theta = np.ones_like(diff)
    if per_source_theta:
        th = 1.0
        for i in np.where(part)[0]:
            if diff[i] > limit[i]: th = min(th, max(limit[i],0)/diff[i])
        theta[part] = th
        for i in np.where(~part)[0]:
            theta[i] = min(1.0, max(limit[i],0)/diff[i]) if diff[i] > limit[i] else 1.0
    else:
        th = 1.0
        for i in range(len(diff)):
            if diff[i] > limit[i]: th = min(th, max(limit[i],0)/diff[i])
        theta[:] = th
    dj = theta*diff
    d0 = -theta*(rhoa_j*Aj)/(rhoa_0*A0)*diff
    return dj, d0

worst_sum = 0; worst_neg = 0; worst_neg_blend = 0; worst_inv=0
for trial in range(20000):
    ntag = 5
    partition = [True, True, True, False, False]
    rho = 1.1
    a = rng.uniform(0.001, 0.4)
    rhoa_j = a*rho
    rhoa_0 = rho - rhoa_j
    qbar = rng.uniform(1e-4, 2e-2)
    qj = qbar*rng.uniform(0.2, 1.0/a)   # updraft moister, ρa q_j may approach ρ q̄
    qj = min(qj, qbar/a*0.999999)       # filter bound ρaʲqʲ ≤ ρq̄
    q0 = (rho*qbar - rhoa_j*qj)/rhoa_0  # env by subtraction (weight w=1)
    phibar = rng.dirichlet(np.ones(3)*0.3)
    eps_bar = np.concatenate([phibar*qbar, [rng.uniform(0,1)*qbar*phibar[0], rng.uniform(0,1)*qbar]])
    eps_bar[4] = min(eps_bar[4], qbar)
    phij = rng.dirichlet(np.ones(3)*0.3)
    eps_j = np.concatenate([phij*qj, [rng.uniform(0,1)*qj, rng.uniform(0,1)*qj]])
    dj, d0 = share_diffs(eps_j, eps_bar, rho, rhoa_j, rhoa_0, qj, q0, qbar, partition, True)
    part = np.array(partition)
    worst_sum = max(worst_sum, abs(dj[part].sum()), abs(d0[part].sum()))
    tot = eps_bar[part].sum()
    phib = eps_bar/tot
    phi0 = phib + d0
    phijeff = phib + dj
    worst_neg = min(worst_neg, phi0.min(), phijeff.min())
    # inventory: rhoa_j qj phij_eff <= rho qbar phibar
    worst_inv = max(worst_inv, (rhoa_j*qj*phijeff - rho*qbar*phib).max()/(rho*qbar))
    # with the `specific` blend: env q0 differs from subtraction (w<1)
    w = rng.uniform(0.5, 1.0)
    q0b = w*q0 + (1-w)*qbar
    dj2, d02 = share_diffs(eps_j, eps_bar, rho, rhoa_j, rhoa_0, qj, q0b, qbar, partition, True)
    inv0 = rho*qbar*phib - rhoa_j*qj*(phib+dj2)    # true env inventory by subtraction
    phi0_used = phib + d02                       # env shares the exchange uses
    worst_neg_blend = min(worst_neg_blend, (phi0_used).min())
print("max |sum of partition differences| :", worst_sum)
print("min share after exchange (w=1)      :", worst_neg)
print("max inventory violation / (ρq̄)      :", worst_inv)
print("min env share with blend w<1        :", worst_neg_blend)

print()
print("=== 2. Copies' 0M sink: chi_i += dq(phi_i - chi_i), phi_i = chi_i/q ===")
for trial in range(3):
    q = rng.uniform(0.005,0.02); chi = rng.dirichlet(np.ones(3))*q
    dq = -rng.uniform(1e-6,1e-4)
    phi = chi/q
    lhs = (chi + dq*(phi-chi)).sum(); rhs = q + dq*(1-q)
    print(f" exact partition: sum copies {lhs:.15e}  parent {rhs:.15e}  diff {lhs-rhs:.2e}")
# exact finite-mass derivation: rho a chi_i -> rho a chi_i + rho a dq phi_i dt ; rho a -> rho a(1+dq dt)
q = 0.012; chi = np.array([0.004,0.006,0.002]); dq=-2e-4; dt=1.0
exact = (chi + dq*dt*chi/q)/(1+dq*dt); lin = chi + dq*dt*(chi/q - chi)
print(" finite-mass update vs linear rule, max rel diff:", np.max(np.abs(exact-lin)/chi))
# drift behaviour when copies do not partition: e' = dq(1-q) e / q  (decays)
q=0.012; chi=np.array([0.004,0.006,0.0019]); e0=q-chi.sum()
for k in range(3):
    q_new = q + dq*(1-q); chi = chi + dq*(chi/q - chi); q=q_new
print(f" drift e: start {e0:.3e} after 3 sink steps {q-chi.sum():.3e} (decays with unnormalised phi)")

print()
print("=== 3. Surface BC: relaxation target, sums and bound ===")
qbar=0.009; excess=0.0004; phibar=np.array([0.7,0.3]); m=np.array([1.0,0.0])
target = qbar*phibar + excess*m
print(" sum of copy targets", target.sum(), "parent target", qbar+excess)
# t=0 with a surface_flux SOURCE tag starting at zero in the grid mean
a=0.1; rho=1.1; rhoa=a*rho
chi_evap_target = excess*1.0   # evap source tag, grid mean evap = 0
print(" evap source tag at t=0: updraft inventory", rhoa*chi_evap_target, " grid-mean inventory 0 -> env inventory", -rhoa*chi_evap_target)

print()
print("=== 4. 1M falling-water composition psi ===")
rho=1.1; a=0.1; rhoa=a*rho
qs_j = 4e-4; qs = 1e-4   # updraft rain above grid mean share: rhoa qs_j = 4.4e-5 > ... check vs rho qs=1.1e-4
phij=np.array([0.9,0.1]); phi0=np.array([0.3,0.7])
psi=(rhoa*qs_j*phij + (rho*qs - rhoa*qs_j)*phi0)/(rho*qs)
print(" psi (bounded case):", psi, "sum", psi.sum())
qs_j = 1.5e-3   # Newton iterate / before filter: rhoa qs_j > rho qs
psi=(rhoa*qs_j*phij + (rho*qs - rhoa*qs_j)*phi0)/(rho*qs)
print(" psi (rhoa qs_j > rho qs):", psi, "sum", psi.sum(), "-> outside [0,1]")
# mass-weighted vs flux-weighted (model's EDMF energy correction splits the flux as rho a w q)
qs_j=4e-4; w_j=6.0; w_bar=3.0
psi_mass=(rhoa*qs_j*phij + (rho*qs - rhoa*qs_j)*phi0)/(rho*qs)
Fj=rhoa*w_j*qs_j; F=rho*w_bar*qs
psi_flux=(Fj*phij + (F-Fj)*phi0)/F
print(" mass-weighted psi", psi_mass, " flux-weighted psi", psi_flux)

print()
print("=== 5. 1M diffusion correction sign (1D, zero-flux) ===")
n=40; z=np.linspace(0,1,n); dz=z[1]-z[0]; rhoK=np.ones(n+1); rhoK[0]=rhoK[-1]=0.0
def diffuse(chi):  # tendency = d/dz(rhoK dchi/dz), zero flux at ends
    F = np.zeros(n+1); F[1:-1] = -rhoK[1:-1]*np.diff(chi)/dz
    return -np.diff(F)/dz
qtot = 0.01 + 0.002*np.sin(3*z); qp = 1e-4*np.exp(-((z-0.4)/0.05)**2)
phi = np.vstack([0.5+0.4*np.tanh((z-0.5)/0.1), 0.5-0.4*np.tanh((z-0.5)/0.1)])
tags = phi*qtot
parent = diffuse(qtot-qp)                      # K_h on q_tot_eff (K_e omitted: identical for both)
tags_now = sum(diffuse(t) for t in tags)
plan = sum(diffuse(t) + diffuse(p*qp) for t,p in zip(tags,phi))   # plan as written: +div(rhoK grad(phi qp))
fixed = sum(diffuse(t) - diffuse(p*qp) for t,p in zip(tags,phi))
print(" |tags - parent| today      :", np.abs(tags_now-parent).max())
print(" |tags - parent| plan's sign:", np.abs(plan-parent).max())
print(" |tags - parent| minus sign :", np.abs(fixed-parent).max())

print()
print("=== 6. Linear vs van Leer sum of copies' fluxes (1 face) ===")
def vl(chi_m, chi_c, chi_p):   # simple minmod-limited slope reconstruction at c's top face
    s1=chi_c-chi_m; s2=chi_p-chi_c
    slope = 0.0 if s1*s2<=0 else np.sign(s1)*min(abs(s1),abs(s2))
    return chi_c + 0.5*slope
chis = [rng.uniform(0,0.01,3) for _ in range(3)]
tot = sum(chis)
print(" van Leer: sum of copy faces", sum(vl(*c) for c in chis), " parent face", vl(*tot))
print(" upwind  : sum of copy faces", sum(c[1] for c in chis), " parent face", tot[1])
