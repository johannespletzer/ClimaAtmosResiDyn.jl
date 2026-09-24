"""Long runs (design/INCREMENT_RULE_LONG_RUNS.md): the pre-registered metrics
of sections 4 and 5, from the second submission (output_0001).

    python3 lr_rule_metrics.py [OUTPUT_ROOT]

Per site and family, for `samesign` and `absm`:
  - the net and gross closure residual (relative, from the closure CSVs, every
    6 hours) at days 10, 30, 90, or at the last check before a run stopped;
  - the slope of log(gross) against log(t) over days 30 to 90 (least squares
    over the 6-hourly checks in that range);
  - the part left out and the net-over-time ledgers from the audit CSVs;
  - the parent's negative water, sum of rho*min(q_tot, 0) over sum of rho*q_tot,
    from the daily output (section 7, reported only);
  - each tag's L1 against the copies at days 10, 30, 90: sum rho |q - q_copies|
    over sum rho |q_copies|, over the column's levels (weights rho only; the
    grid is stretched, so this weights levels, not mass, and is stated so).
Budgets (section 5): water 0.2% of the water, energy 1e-4 (a proposal).
"""
import csv, os, sys
import numpy as np
import netCDF4

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
DAY = 86400.0
BUDGET = {'water': 2e-3, 'energy': 1e-4}
FILES = {'water': 'water_tag_closure.csv', 'energy': 'energy_source_tag_closure.csv'}
AUDIT = {'water': 'water_tag_audit.csv', 'energy': 'energy_source_tag_audit.csv'}
TAGS = {'water': ['pbl', 'free', 'evap', 'fcg'], 'energy': ['pbl', 'free', 'sfc', 'rad']}
PREFIX = {'water': 'q_tag_', 'energy': 'e_src_'}

def out(run):
    return f'{ROOT}/{run}/output_0001'

def rows(path):
    with open(path) as f:
        r = list(csv.DictReader(f))
    return r

def at(rs, day):
    """The last row at or before `day`."""
    best = None
    for r in rs:
        if float(r['time']) <= day * DAY + 1:
            best = r
    return best

def slope(rs, key='gross_relative', lo=30, hi=90):
    t = np.array([float(r['time']) for r in rs])
    g = np.array([abs(float(r[key])) for r in rs])
    m = (t >= lo * DAY) & (t <= hi * DAY) & (g > 0)
    if m.sum() < 3:
        return float('nan'), int(m.sum())
    return float(np.polyfit(np.log(t[m]), np.log(g[m]), 1)[0]), int(m.sum())

def nc(run, name):
    p = f'{out(run)}/{name}_1d_inst.nc'
    if not os.path.exists(p):
        return None, None
    with netCDF4.Dataset(p) as d:
        return np.asarray(d['time'][:]), np.asarray(d[name][:])  # (z, time)

def l1(run, ref, name, day):
    t, x = nc(run, name); tr, y = nc(ref, name); _, rho = nc(ref, 'rhoa')
    if x is None or y is None:
        return float('nan')
    k = [i for i in range(len(t)) if abs(t[i] - day * DAY) < 1]
    kr = [i for i in range(len(tr)) if abs(tr[i] - day * DAY) < 1]
    if not k or not kr:
        return float('nan')
    a, b, w = x[:, k[0]], y[:, kr[0]], rho[:, kr[0]]
    return float(np.sum(w * np.abs(a - b)) / np.sum(w * np.abs(b)))

def negative_water(run):
    t, q = nc(run, 'hus'); _, rho = nc(run, 'rhoa')
    frac = np.sum(rho * np.minimum(q, 0), axis=0) / np.sum(rho * q, axis=0)
    return t, frac

for site in ('23', '26'):
    print(f'=== site {site}')
    t, neg = negative_water(f'lr_s{site}_untagged')
    bad = neg < 0
    print(f'parent negative water (untagged, daily): days with any {int(bad.sum())} of {len(t)}; '
          f'first day {int(t[bad][0] / DAY) if bad.any() else None}; worst {neg.min():.3e} of the column water')
    for fam in ('water', 'energy'):
        print(f'-- {fam} (budget {BUDGET[fam]:.0e})')
        slopes = {}
        for v in ('samesign', 'absm'):
            run = f'lr_s{site}_{v}'
            rs = rows(f'{out(run)}/{FILES[fam]}')
            au = rows(f'{out(run)}/{AUDIT[fam]}')
            last = rs[-1]
            s, n = slope(rs)
            slopes[v] = s
            line = [f'{v:8s} last day {float(last["time"]) / DAY:5.1f}']
            for d in (10, 30, 90):
                r = at(rs, d)
                line.append(f'd{d}: net {float(r["relative"]):+.2e} gross {float(r["gross_relative"]):.2e}')
            line.append(f'slope30-90 {s:.3f} (n={n})')
            a = au[-1]
            line.append(f'left {float(a["increment_left_relative"]):+.2e} left_net_abs {float(a["increment_left_net_abs_relative"]):.2e} '
                        f'moved_net_abs {float(a["increment_moved_net_abs_relative"]):.2e}')
            print(' | '.join(line))
        g = {v: float(rows(f'{out(f"lr_s{site}_{v}")}/{FILES[fam]}')[-1]['gross_relative']) for v in ('samesign', 'absm')}
        c1 = g['samesign'] <= BUDGET[fam]
        c2 = slopes['samesign'] <= slopes['absm'] + 0.25
        print(f'   rule: (1) same-sign gross at its last check {g["samesign"]:.2e} within budget: {c1}; '
              f'(2) slope {slopes["samesign"]:.3f} <= |m| {slopes["absm"]:.3f} + 0.25: {c2}; '
              f'|m| within budget: {g["absm"] <= BUDGET[fam]}')
        for v in ('samesign', 'absm'):
            ls = []
            for d in (10, 30, 90):
                ls.append(f'd{d} ' + ' '.join(f'{tag} {100 * l1(f"lr_s{site}_{v}", f"lr_s{site}_copies", PREFIX[fam] + tag, d):.2f}%' for tag in TAGS[fam]))
            print(f'   L1 vs copies, {v}: ' + ' | '.join(ls))
    rs = rows(f'{out(f"lr_s{site}_copies")}/water_tag_closure.csv'); re_ = rows(f'{out(f"lr_s{site}_copies")}/energy_source_tag_closure.csv')
    print(f'-- copies: last day {float(rs[-1]["time"]) / DAY:.1f}; water gross {float(rs[-1]["gross_relative"]):.2e}; '
          f'energy gross {float(re_[-1]["gross_relative"]):.2e}')
