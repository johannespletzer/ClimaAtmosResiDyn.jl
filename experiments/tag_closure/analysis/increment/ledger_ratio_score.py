"""Scores design/LEDGER_RATIO_ZERO_CROSSING.md: which per-tag ledger ratio
stays readable through a zero crossing.

    python3 ledger_ratio_score.py [OUTPUT_ROOT] [--csv OUT.csv]

OUTPUT_ROOT holds `ledger_ratio_{d4,sphere}_repair_{on,off}/output_0000/`.

The design names the ratios but not the ledgers, so every tag's own ledger is
scored: `led_fix_<tag>` (the limiters' and the repair's corrections) and
`led_inc_<tag>` (the increment follower), for every tag the audit has. A ratio
passes only if it passes on every one of them, in both arms of both pairs.

The audit writes each ratio, not the tag's integrals. Where a ledger has
retained anything, `∫tag = retained / inventory_fraction` and `∫|tag| =
retained / burden_fraction`. A NaN inventory fraction with a finite burden
fraction means `∫tag ≤ 0`. The precondition on the repair-off run is read that
way, from every ledger of `sfc` and `rad` that has retained something. Where no
ledger of a tag has retained anything, its integrals are not known here, and
the precondition cannot pass on that tag.

It prints the preconditions, then per ratio each rule's verdict with the first
failing row. It exits 1 if a file or column is missing or nothing was scored.
The verdicts themselves do not set the exit code: a failing ratio is a result.
"""
import csv
import math
import os
import sys

import netCDF4
import numpy as np

ROOT = os.path.join(os.environ.get('SCRATCH', ''), 'tag_closure', 'output')
PAIRS = ('d4', 'sphere')
ARMS = ('on', 'off')
RATIOS = ('inventory_fraction', 'burden_fraction', 'parent_fraction')
PASS_LEVEL = {'inventory_fraction': 2e-2, 'burden_fraction': 2e-2, 'parent_fraction': 2e-4}
MODEL_FIELDS = ('ta', 'rhoa', 'hus')
HOUR = 3600.0


def out(pair, arm):
    return os.path.join(ROOT, f'ledger_ratio_{pair}_repair_{arm}', 'output_0000')


def audit(pair, arm):
    path = os.path.join(out(pair, arm), 'energy_source_tag_audit.csv')
    if not os.path.exists(path):
        raise SystemExit(f'FAIL: missing {path}')
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def ledgers(rows):
    """The tag ledgers `<L>` that carry the three ratios and `_applicable`."""
    names = sorted(k[:-len('_applicable')] for k in rows[0] if k.endswith('_applicable'))
    if not names:
        raise SystemExit('FAIL: no tag ledger with `_applicable` in the audit')
    for name in names:
        for suffix in ('_retained',) + tuple('_' + r for r in RATIOS):
            if name + suffix not in rows[0]:
                raise SystemExit(f'FAIL: no column {name}{suffix}')
    return names


def bits(a):
    return np.ascontiguousarray(a, dtype=np.float64).view(np.uint64)


def model_parity(pair):
    """`ta`, `rhoa` and `hus` bit for bit between the pair's two arms."""
    problems = []
    for name in MODEL_FIELDS:
        values = []
        for arm in ARMS:
            path = os.path.join(out(pair, arm), f'{name}_1h_inst.nc')
            if not os.path.exists(path):
                raise SystemExit(f'FAIL: missing {path}')
            with netCDF4.Dataset(path) as d:
                values.append((np.asarray(d['time'][:]), np.asarray(d[name][:])))
        (t_on, v_on), (t_off, v_off) = values
        if t_on.shape != t_off.shape or not np.array_equal(bits(t_on), bits(t_off)):
            problems.append(f'{name}: times differ')
        elif v_on.shape != v_off.shape or not np.array_equal(bits(v_on), bits(v_off)):
            problems.append(f'{name}: values differ')
    return problems


def crossing(rows, tag):
    """The first row, from 1 h on, where `_applicable` is 1 and `∫tag ≤ 0` or
    `∫|tag| / ∫tag ≥ 10`, from any of the tag's ledgers that retained
    something. None if there is none; 'unknown' if no ledger retained anything."""
    known = False
    for r in rows:
        if r['time'] < HOUR:
            continue
        for name in (f'led_fix_{tag}', f'led_inc_{tag}'):
            if f'{name}_retained' not in r or r[f'{name}_applicable'] != 1:
                continue
            retained = r[f'{name}_retained']
            burden_fraction = r[f'{name}_burden_fraction']
            if not (retained > 0 and math.isfinite(burden_fraction) and burden_fraction > 0):
                continue
            known = True
            inventory_fraction = r[f'{name}_inventory_fraction']
            if math.isnan(inventory_fraction):
                return r['time'] / HOUR, name, '∫tag ≤ 0'
            if inventory_fraction / burden_fraction >= 10:
                return r['time'] / HOUR, name, f'∫|tag|/∫tag {inventory_fraction / burden_fraction:.3g}'
    return None if known else 'unknown'


def score(ratio, runs):
    """Rules (a), (b), (c) for one ratio over every ledger and run. Returns the
    number of rows scored and, per rule, the first failure or None."""
    first = {'a': None, 'b': None, 'c': None}
    n = 0
    for (pair, arm), rows in runs.items():
        for name in ledgers(rows):
            previous = None
            for r in rows:
                if r['time'] < HOUR or r[f'{name}_applicable'] != 1:
                    previous = None
                    continue
                n += 1
                where = f'{pair} repair {arm}, {name}, hour {r["time"] / HOUR:g}'
                value, retained = r[f'{name}_{ratio}'], r[f'{name}_retained']
                if not math.isfinite(value):
                    first['a'] = first['a'] or f'{where}: {value}'
                    previous = None
                    continue
                if previous is not None:
                    v0, r0 = previous
                    rise = math.inf if v0 == 0 and value > 0 else (value / v0 if v0 > 0 else 1.0)
                    retained_rise = math.inf if r0 == 0 and retained > 0 else (retained / r0 if r0 > 0 else 1.0)
                    if rise > 10 and retained_rise < 2:
                        first['b'] = first['b'] or f'{where}: rises {rise:.3g} times, retained {retained_rise:.3g} times'
                previous = (value, retained)
                burden_fraction = r[f'{name}_burden_fraction']
                if math.isfinite(burden_fraction) and burden_fraction >= 2e-2 and value < PASS_LEVEL[ratio]:
                    first['c'] = first['c'] or f'{where}: {value:.3g} below {PASS_LEVEL[ratio]:g}, burden fraction {burden_fraction:.3g}'
    return n, first


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
    runs = {(pair, arm): audit(pair, arm) for pair in PAIRS for arm in ARMS}
    table = []

    print('Preconditions (a pair that misses one is inconclusive):')
    conclusive = {}
    for pair in PAIRS:
        parity = model_parity(pair)
        cross = {tag: crossing(runs[(pair, 'off')], tag) for tag in ('sfc', 'rad')}
        crossed = any(isinstance(c, tuple) for c in cross.values())
        on = runs[(pair, 'on')]
        fixed = {tag: max(r[f'led_fix_{tag}_retained'] for r in on) for tag in ('sfc', 'rad')}
        repaired = any(v > 0 for v in fixed.values())
        conclusive[pair] = not parity and crossed and repaired
        print(f'  {pair}: model fields {", ".join(MODEL_FIELDS)} bit for bit: {"yes" if not parity else "; ".join(parity)}')
        print(f'  {pair}: repair off, sfc or rad crosses: ' + '; '.join(
            f'{tag} ' + ('no' if c is None else 'not known (no ledger retained anything)' if c == 'unknown'
                         else f'hour {c[0]:g} ({c[1]}, {c[2]})') for tag, c in cross.items()))
        print(f'  {pair}: repair on, led_fix retains: ' + '; '.join(f'{tag} {v:.4g}' for tag, v in fixed.items()))
        print(f'  {pair}: {"conclusive" if conclusive[pair] else "INCONCLUSIVE"}')
        table.append({'kind': 'precondition', 'name': pair, 'rule': 'conclusive',
                      'verdict': int(conclusive[pair]), 'rows': '', 'first_failure': ''})

    print('Pass rules, per ratio, over every tag ledger of both arms of both pairs, from 1 h on where applicable:')
    total = 0
    for ratio in RATIOS:
        n, first = score(ratio, runs)
        total += n
        verdict = all(v is None for v in first.values())
        print(f'  {ratio}: {"PASS" if verdict else "FAIL"} over {n} rows')
        for rule in ('a', 'b', 'c'):
            print(f'    ({rule}) ' + ('pass' if first[rule] is None else 'FAIL at ' + first[rule]))
            table.append({'kind': 'ratio', 'name': ratio, 'rule': rule, 'verdict': int(first[rule] is None),
                          'rows': n, 'first_failure': first[rule] or ''})
    if not all(conclusive.values()):
        print('RESULT: at least one pair is inconclusive; its verdicts above are reported, not scored')
    if out_csv:
        with open(out_csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(table[0].keys()))
            w.writeheader()
            w.writerows(table)
    if total == 0:
        raise SystemExit('FAIL: nothing scored')


if __name__ == '__main__':
    main()
