"""Long runs (design/INCREMENT_RULE_LONG_RUNS.md): the pre-registered metrics
of sections 4 and 5, from the second submission (output_0001), or from
site 23's rerun with option C (section 8) through LR_PREFIX, LR_OUTPUT and
LR_SITES.

    python3 lr_rule_metrics.py [OUTPUT_ROOT] [--csv OUT.csv]

Per site and family, for `samesign` and `absm`:
  - the net and gross closure residual (relative, from the closure CSVs, every
    6 hours) at days 10 and 30, and at the run's last check, labelled with the
    day it was taken;
  - the slope of log(gross) against log(t), least squares over the 6-hourly
    checks from day 30 to day 90 or to the run's last check if it stopped
    first, labelled with the interval actually used;
  - the part left out and the net-over-time ledgers from the audit CSVs;
  - the parent's negative water, Σ ρΔz min(q_tot, 0) over Σ ρΔz q_tot, per day
    from the untagged twin's output (section 7, reported only);
  - each tag's L1 against the copies at days 10, 30 and 90, Σ ρΔz |q − q_copies|
    over Σ ρΔz |q_copies|, only where both runs wrote that day.
Budgets (section 5): water 0.2% of the water, energy 1e-4 (a proposal).

The column weights are ρΔz, the mass per unit area of each cell. Δz comes from
the output's cell-centre heights: the centres are the midpoints of the faces,
so the faces follow from the bottom face at 0. The script checks that this
gives positive thicknesses and a top face at the config's `z_max`, and stops
otherwise. The column has no topography, so ρΔz is the cell's mass per area.
"""
import csv
import os
import re
import sys

import numpy as np
import netCDF4

ROOT = '/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
# The runs' names and output directory. The defaults are W36's second
# submission. Site 23's rerun with option C (the design's section 8) sets
# LR_PREFIX=lrc LR_OUTPUT=output_0000 LR_SITES=23.
RUN_PREFIX = os.environ.get('LR_PREFIX', 'lr')
OUTPUT = os.environ.get('LR_OUTPUT', 'output_0001')
SITES = tuple(os.environ.get('LR_SITES', '23,26').split(','))
DAY = 86400.0
BUDGET = {'water': 2e-3, 'energy': 1e-4}
FILES = {'water': 'water_tag_closure.csv', 'energy': 'energy_source_tag_closure.csv'}
AUDIT = {'water': 'water_tag_audit.csv', 'energy': 'energy_source_tag_audit.csv'}
TAGS = {'water': ['pbl', 'free', 'evap', 'fcg'], 'energy': ['pbl', 'free', 'sfc', 'rad']}
PREFIX = {'water': 'q_tag_', 'energy': 'e_src_'}


def out(run):
    return f'{ROOT}/{run}/{OUTPUT}'


def rows(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def at(rs, day):
    """The row at `day`, or None if the run did not reach it."""
    for r in rs:
        if abs(float(r['time']) - day * DAY) < 1:
            return r
    return None


def slope(rs, lo=30, hi=90, key='gross_relative'):
    t = np.array([float(r['time']) for r in rs])
    g = np.array([abs(float(r[key])) for r in rs])
    m = (t >= lo * DAY) & (t <= hi * DAY) & (g > 0)
    if m.sum() < 3:
        return float('nan'), lo, float('nan'), int(m.sum())
    s = float(np.polyfit(np.log(t[m]), np.log(g[m]), 1)[0])
    return s, lo, float(t[m][-1] / DAY), int(m.sum())


def nc(run, name):
    p = f'{out(run)}/{name}_1d_inst.nc'
    if not os.path.exists(p):
        raise SystemExit(f'FAIL: missing {p}')
    with netCDF4.Dataset(p) as d:
        return np.asarray(d['time'][:]), np.asarray(d[name][:]), np.asarray(d['z'][:])


def z_max(run):
    with open(f'{out(run)}/{run}.yml') as f:
        m = re.search(r'^z_max:\s*"?([0-9.eE+-]+)', f.read(), re.M)
    if not m:
        raise SystemExit(f'FAIL: no z_max in {run}.yml')
    return float(m.group(1))


def thickness(z, top):
    faces = [0.0]
    for c in z:
        faces.append(2 * c - faces[-1])
    faces = np.array(faces)
    dz = np.diff(faces)
    if not (np.all(dz > 0) and abs(faces[-1] - top) <= 1e-6 * top):
        raise SystemExit(f'FAIL: faces from the centres end at {faces[-1]}, z_max {top}; min dz {dz.min()}')
    return dz


def weights(run, k):
    t, rho, z = nc(run, 'rhoa')
    return rho[:, k] * thickness(z, z_max(run))


def index(t, day):
    k = [i for i in range(len(t)) if abs(t[i] - day * DAY) < 1]
    return k[0] if k else None


def l1(run, ref, name, day):
    t, x, _ = nc(run, name)
    tr, y, _ = nc(ref, name)
    k, kr = index(t, day), index(tr, day)
    if k is None or kr is None:
        return None
    w = weights(ref, kr)
    return float(np.sum(w * np.abs(x[:, k] - y[:, kr])) / np.sum(w * np.abs(y[:, kr])))


def negative_water(run):
    t, q, z = nc(run, 'hus')
    _, rho, _ = nc(run, 'rhoa')
    w = rho * thickness(z, z_max(run))[:, None]
    return t, np.sum(w * np.minimum(q, 0), axis=0) / np.sum(w * q, axis=0), q.min(axis=0)


def main():
    global ROOT
    args = sys.argv[1:]
    out_csv = None
    if '--csv' in args:
        i = args.index('--csv')
        out_csv = args[i + 1]
        args = args[:i] + args[i + 2:]
    if args:
        ROOT = args[0]
    table = []
    for site in SITES:
        print(f'=== site {site}')
        t, frac, qmin = negative_water(f'{RUN_PREFIX}_s{site}_untagged')
        bad = frac < 0
        worst = int(np.argmin(frac))
        print(f'parent negative water (untagged, daily, weights rho dz): days with any {int(bad.sum())} of {len(t)}; '
              f'first day {int(t[bad][0] / DAY) if bad.any() else None}; worst {frac[worst]:.3e} of the column water '
              f'on day {t[worst] / DAY:g}; smallest q_tot {qmin.min():.3e} kg/kg on day {t[int(np.argmin(qmin))] / DAY:g}')
        table.append({'site': site, 'family': 'water', 'run': 'untagged', 'metric': 'negative_water_worst_fraction',
                      'value': frac[worst], 'day': t[worst] / DAY})
        for fam in ('water', 'energy'):
            print(f'-- {fam} (budget {BUDGET[fam]:.0e})')
            summary = {}
            for v in ('samesign', 'absm'):
                run = f'{RUN_PREFIX}_s{site}_{v}'
                rs = rows(f'{out(run)}/{FILES[fam]}')
                au = rows(f'{out(run)}/{AUDIT[fam]}')
                last, a = rs[-1], au[-1]
                last_day = float(last['time']) / DAY
                s, lo, hi, n = slope(rs)
                summary[v] = (float(last['gross_relative']), s, last_day)
                line = [f'{v:8s}']
                for d in (10, 30):
                    r = at(rs, d)
                    line.append(f'day {d}: net {float(r["relative"]):+.2e} gross {float(r["gross_relative"]):.2e}' if r else f'day {d}: not reached')
                line.append(f'last (day {last_day:g}): net {float(last["relative"]):+.2e} gross {float(last["gross_relative"]):.2e}')
                line.append(f'slope over days {lo:g}-{hi:g} {s:.3f} (n={n})')
                line.append(f'left {float(a["increment_left_relative"]):+.2e} left_net_abs {float(a["increment_left_net_abs_relative"]):.2e} '
                            f'moved_net_abs {float(a["increment_moved_net_abs_relative"]):.2e} (audit day {float(a["time"]) / DAY:g})')
                print(' | '.join(line))
                for key, value, day in (('gross_last', float(last['gross_relative']), last_day),
                                        ('net_last', float(last['relative']), last_day),
                                        ('slope', s, hi),
                                        ('moved_net_abs', float(a['increment_moved_net_abs_relative']), float(a['time']) / DAY)):
                    table.append({'site': site, 'family': fam, 'run': v, 'metric': key, 'value': value, 'day': day})
            (gs, ss, ds), (ga, sa, da) = summary['samesign'], summary['absm']
            print(f'   rule: (1) same-sign gross at its last check (day {ds:g}) {gs:.2e} within budget: {gs <= BUDGET[fam]}; '
                  f'(2) slope {ss:.3f} <= |m| {sa:.3f} + 0.25: {ss <= sa + 0.25}; |m| within budget: {ga <= BUDGET[fam]}')
            for v in ('samesign', 'absm'):
                parts = []
                for d in (10, 30, 90):
                    vals = {tag: l1(f'{RUN_PREFIX}_s{site}_{v}', f'{RUN_PREFIX}_s{site}_copies', PREFIX[fam] + tag, d) for tag in TAGS[fam]}
                    if any(x is None for x in vals.values()):
                        parts.append(f'day {d}: not reached by both')
                        continue
                    parts.append(f'day {d} ' + ' '.join(f'{tag} {100 * x:.2f}%' for tag, x in vals.items()))
                    for tag, x in vals.items():
                        table.append({'site': site, 'family': fam, 'run': v, 'metric': f'l1_vs_copies_{tag}', 'value': x, 'day': d})
                print(f'   L1 vs copies (weights rho dz), {v}: ' + ' | '.join(parts))
        rw = rows(f'{out(f"{RUN_PREFIX}_s{site}_copies")}/water_tag_closure.csv')
        re_ = rows(f'{out(f"{RUN_PREFIX}_s{site}_copies")}/energy_source_tag_closure.csv')
        print(f'-- copies: last water check day {float(rw[-1]["time"]) / DAY:g}, gross {float(rw[-1]["gross_relative"]):.2e}; '
              f'last energy check day {float(re_[-1]["time"]) / DAY:g}, gross {float(re_[-1]["gross_relative"]):.2e}')
    if out_csv:
        with open(out_csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=['site', 'family', 'run', 'metric', 'value', 'day'])
            w.writeheader()
            w.writerows(table)


if __name__ == '__main__':
    main()
