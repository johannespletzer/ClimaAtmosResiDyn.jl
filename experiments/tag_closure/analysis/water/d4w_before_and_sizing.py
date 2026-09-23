"""V-W1 and V-W0c on D4-W (G3 WP0).

V-W1: the grid-scale water tags under prognostic EDMF, on main after #95.
  - the tropo share against the passive tracer, which mixes as the air does;
  - the evap split, evap_tropo + evap_strat against evap.
V-W0c: sizing for WP3, from the untagged twin (identical atmosphere):
  - the updraft's share of rain and snow;
  - the updraft's surface excess of water against the environment's spread;
  - the 1M q_tot_eff leak of the grid-scale vertical diffusion, in closed form.
Weights are ρ Δz, with Δz from the cell centres as faces."""
import numpy as np, netCDF4 as nc
O = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
W1 = f"{O}/w1_d4w_grid_tags/output_0000"; W0C = f"{O}/w0c_d4w_untagged/output_0000"
def read(d, var):
    with nc.Dataset(f"{d}/{var}_1h_inst.nc") as f:
        v = np.asarray(f[var][:]); dims = f[var].dimensions
        t = np.asarray(f["time"][:]); z = np.asarray(f["z"][:]) if "z" in f.variables else None
    if dims[:2] == ("z", "time"): v = v.T
    return v, t, z
rho, t, zc = read(W0C, "rhoa")
faces = np.concatenate([[0.0], 0.5 * (zc[1:] + zc[:-1]), [2 * zc[-1] - 0.5 * (zc[-1] + zc[-2])]])
dz = np.diff(faces)
hours = [1, 6, 12, 24]; idx = {h: int(np.where(np.isclose(t, 3600 * h))[0][0]) for h in hours}
hus, _, _ = read(W0C, "hus")

print("== V-W1: the tropo share against the passive tracer (the air below 750 m at t=0)")
trop, _, _ = read(W1, "q_tag_tropo"); tracer, _, _ = read(W1, "q_gas_A")
for h in hours:
    i = idx[h]; w = rho[i] * dz; phi = trop[i] / hus[i]
    l1 = np.sum(np.abs(phi - tracer[i]) * hus[i] * w) / np.sum(tracer[i] * hus[i] * w)
    print(f"  {h:2d} h: column water-weighted mean of φ_tropo {np.sum(phi*hus[i]*w)/np.sum(hus[i]*w):.3f}, "
          f"of the tracer {np.sum(tracer[i]*hus[i]*w)/np.sum(hus[i]*w):.3f}; L1 |φ − tracer| {l1:.3f}; "
          f"max |φ − tracer| {np.max(np.abs(phi - tracer[i])):.3f}")
print("== V-W1: evap_tropo + evap_strat against evap (not an identity under the EDMF gap)")
ev, _, _ = read(W1, "q_tag_evap"); et, _, _ = read(W1, "q_tag_evap_tropo"); es, _, _ = read(W1, "q_tag_evap_strat")
for h in hours:
    i = idx[h]; w = rho[i] * dz
    print(f"  {h:2d} h: evap share of the column {np.sum(ev[i]*w)/np.sum(hus[i]*w):.4f}; "
          f"Σ|split − evap| / Σ evap = {np.sum(np.abs(et[i]+es[i]-ev[i])*w)/np.sum(np.abs(ev[i])*w):.2e}")

print("== V-W0c: the updraft's share of rain and snow (column integrals)")
arup, _, _ = read(W0C, "arup"); rhoaup, _, _ = read(W0C, "rhoaup")
for sp, up in (("husra", "husraup"), ("hussn", "hussnup")):
    q, _, _ = read(W0C, sp); qu, _, _ = read(W0C, up)
    for h in hours:
        i = idx[h]
        grid = np.sum(rho[i] * q[i] * dz); updr = np.sum(rhoaup[i] * arup[i] * qu[i] * dz)
        print(f"  {sp} {h:2d} h: grid-mean column {grid:.3e} kg m-2, updraft's part {updr:.3e} "
              f"({(updr/grid if grid > 0 else float('nan')):.1%})")
rwp, _, _ = read(W0C, "rwp"); pr, _, _ = read(W0C, "pr")
print("  rwp kg m-2 at 1,6,12,24 h:", [f"{rwp[idx[h]]:.2e}" for h in hours], " pr kg m-2 s-1:", [f"{pr[idx[h]]:.2e}" for h in hours])
print("  daily mean of the hourly pr samples:", f"{np.mean(pr[1:]):.2e}", "kg m-2 s-1")

print("== V-W0c: the updraft's surface excess of water at the first level")
husup, _, _ = read(W0C, "husup"); var, _, _ = read(W0C, "env_q_tot_variance"); husen, _, _ = read(W0C, "husen")
for h in hours:
    i = idx[h]
    print(f"  {h:2d} h: husup − hus = {husup[i][0]-hus[i][0]:.2e}, husup − husen = {husup[i][0]-husen[i][0]:.2e}, "
          f"σ_env = {np.sqrt(max(var[i][0], 0)):.2e} kg/kg, arup = {arup[i][0]:.3f}")

print("== V-W0c: the 1M leak of grid-scale vertical diffusion, |∂z(ρ K ∂z q_p)| with K = edt")
edt, _, _ = read(W0C, "edt")
qr, _, _ = read(W0C, "husra"); qs, _, _ = read(W0C, "hussn")
leak_rates = []
for i in range(len(t)):
    qp = qr[i] + qs[i]
    # Face gradients and face ρK, then the divergence back at centres.
    grad = np.diff(qp) / np.diff(zc)
    rhoK = 0.5 * ((rho[i] * edt[i])[1:] + (rho[i] * edt[i])[:-1])
    flux = np.concatenate([[0.0], rhoK * grad, [0.0]])
    tend = np.diff(flux) / dz
    leak_rates.append(np.sum(np.abs(tend) * dz))
leak_rates = np.array(leak_rates)
total = [np.sum(rho[idx[h]] * hus[idx[h]] * dz) for h in hours]
day = np.trapezoid(leak_rates, t)
print(f"  gross leak rate at 1,6,12,24 h: {[f'{leak_rates[idx[h]]:.2e}' for h in hours]} kg m-2 s-1")
print(f"  over the day: {day:.3e} kg m-2, i.e. {day/total[-1]:.2e} of the column water "
      f"(closure budget 2e-3, leak rule 2e-4)")

# The closure residual accumulates per cell, so the comparable measure is the
# net leak per level over the day, then its absolute value summed over levels.
tends = []
for i in range(len(t)):
    qp = qr[i] + qs[i]
    grad = np.diff(qp) / np.diff(zc)
    rhoK = 0.5 * ((rho[i] * edt[i])[1:] + (rho[i] * edt[i])[:-1])
    flux = np.concatenate([[0.0], rhoK * grad, [0.0]])
    tends.append(np.diff(flux) / dz)
tends = np.array(tends)
net = np.trapezoid(tends, t, axis=0)
print(f"  net per level over the day, Σ|∫ dt| dz: {np.sum(np.abs(net) * dz):.3e} kg m-2, "
      f"i.e. {np.sum(np.abs(net) * dz)/total[-1]:.2e} of the column water")
print(f"  with the environment's area, (1 − arup): {np.sum(np.abs(np.trapezoid(tends * (1 - arup), t, axis=0)) * dz)/total[-1]:.2e}")
w1res = 1.7501271735413129 / 11.603270865559185
print(f"  against V-W1's gross residual at 24 h, {w1res:.3f}: the leak's net is {np.sum(np.abs(net) * dz)/total[-1]/w1res:.1%} of it")
print(f"  max edt {edt.max():.1f} m2/s, max husra {qr.max():.2e} kg/kg at z = {zc[np.unravel_index(qr.argmax(), qr.shape)[1]]:.0f} m")
