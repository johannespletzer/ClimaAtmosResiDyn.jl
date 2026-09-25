"""Long runs (design/INCREMENT_RULE_LONG_RUNS.md): parity of each tagged run's
model output with its untagged twin, bit for bit, failing closed.

    python3 lr_parity.py [OUTPUT_ROOT] [--csv OUT.csv]

OUTPUT_ROOT holds `lr_s<site>_<variant>/output_0001/`, or the names and
directory LR_PREFIX, LR_OUTPUT and LR_SITES give (the design's section 8). The inventory of model
fields is the untagged twin's own diagnostic list, read from the config the
run wrote (`lr_s<site>_untagged.yml` in its output directory). Every field in
it must exist, be readable and hold that variable in every tagged run.

What this compares, and what it does not:
  - the daily instantaneous diagnostics the runs write (`<name>_1d_inst.nc`),
    not the full prognostic state. The runs keep no checkpoints
    (`dt_save_state_to_disk: Inf`), so the state itself cannot be compared;
  - every output time the tagged run wrote. A run that ended early is
    compared up to its last output (prefix parity). A run that wrote every
    time its twin wrote is compared completely (completion parity).

For each field it checks that the dimensions, the shape per time, the `z`
coordinate (absent in both files for a surface field) and the times agree
exactly. Then it compares the values as bit
patterns, so a signed zero or a NaN payload cannot pass as equal. It prints a
verdict per run and one line per run and field. It exits 1 if any file,
variable or coordinate is missing or differs, if any value differs, or if
nothing was compared.
"""

import csv
import os
import re
import sys

import netCDF4
import numpy as np

ROOT = '/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
SUFFIX = '_1d_inst.nc'
# The runs' names and output directory. The defaults are W36's second
# submission. Site 23's rerun with option C (the design's section 8) sets
# LR_PREFIX=lrc LR_OUTPUT=output_0000 LR_SITES=23.
RUN_PREFIX = os.environ.get('LR_PREFIX', 'lr')
OUTPUT = os.environ.get('LR_OUTPUT', 'output_0001')
SITES = tuple(os.environ.get('LR_SITES', '23,26').split(','))
TAGGED = ('samesign', 'absm', 'copies')


def inventory(site):
    """The twin's diagnostic short names, from the `short_name:` lines of the
    config it wrote. The module's Python has no YAML parser, so this reads the
    flow and block list forms the configs use, and fails if it finds none."""
    path = f'{ROOT}/{RUN_PREFIX}_s{site}_untagged/{OUTPUT}/{RUN_PREFIX}_s{site}_untagged.yml'
    with open(path) as f:
        text = f.read()
    names = []
    for m in re.finditer(r'short_name:\s*\[([^\]]*)\]', text):
        names += [n.strip().strip('"\'') for n in m.group(1).split(',') if n.strip()]
    for m in re.finditer(r'short_name:\s*\n((?:\s+-\s*\S+\s*\n)+)', text):
        names += [n.strip().lstrip('-').strip().strip('"\'') for n in m.group(1).splitlines() if n.strip()]
    if not names:
        raise SystemExit(f'FAIL: no diagnostics found in {path}')
    return names


def read(run, name):
    path = f'{ROOT}/{run}/{OUTPUT}/{name}{SUFFIX}'
    if not os.path.exists(path):
        return None, f'missing file {path}'
    try:
        with netCDF4.Dataset(path) as d:
            if name not in d.variables:
                return None, f'no variable {name} in {path}'
            v = d[name]
            return {
                'dims': v.dimensions,
                'values': np.asarray(v[:]),
                # A surface field (`pr`, `lwp`) has no `z`.
                'z': np.asarray(d['z'][:]) if 'z' in d.variables else None,
                'time': np.asarray(d['time'][:]),
            }, None
    except Exception as err:  # an unreadable file fails; it is never skipped
        return None, f'unreadable {path}: {err}'


def bits(a):
    return np.ascontiguousarray(a, dtype=np.float64).view(np.uint64)


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
    rows, failures, compared = [], [], 0
    for site in SITES:
        names = inventory(site)
        twin = f'{RUN_PREFIX}_s{site}_untagged'
        for variant in TAGGED:
            run = f'{RUN_PREFIX}_s{site}_{variant}'
            run_ok, spans = True, set()
            for name in names:
                ref, err_ref = read(twin, name)
                tag, err_tag = read(run, name)
                if err_ref or err_tag:
                    failures.append(f'{run} {name}: {err_ref or err_tag}')
                    run_ok = False
                    continue
                problems = []
                if ref['dims'] != tag['dims']:
                    problems.append(f'dims {tag["dims"]} against {ref["dims"]}')
                if ref['values'].shape[:-1] != tag['values'].shape[:-1]:
                    problems.append('shape per time differs')
                if (ref['z'] is None) != (tag['z'] is None):
                    problems.append('z present in one file only')
                elif ref['z'] is not None and not np.array_equal(bits(ref['z']), bits(tag['z'])):
                    problems.append('z differs')
                n = tag['time'].size
                if n == 0 or n > ref['time'].size:
                    problems.append(f'{n} times against the twin\'s {ref["time"].size}')
                elif not np.array_equal(bits(ref['time'][:n]), bits(tag['time'])):
                    problems.append('times differ')
                if problems:
                    failures.append(f'{run} {name}: ' + '; '.join(problems))
                    run_ok = False
                    continue
                a, b = ref['values'][..., :n], tag['values']
                per_time = (bits(a) == bits(b)).reshape(-1, n).all(axis=0)
                max_diff = 0.0 if per_time.all() else float(np.nanmax(np.abs(a - b)))
                compared += 1
                last_day = float(tag['time'][-1] / 86400)
                twin_day = float(ref['time'][-1] / 86400)
                kind = 'completion' if n == ref['time'].size else 'prefix'
                spans.add((kind, last_day, twin_day))
                first_bad = None if per_time.all() else float(tag['time'][~per_time][0] / 86400)
                rows.append({
                    'run': run, 'field': name, 'times_compared': n,
                    'last_day': f'{last_day:g}', 'twin_last_day': f'{twin_day:g}',
                    'parity': kind, 'bitwise_equal_times': int(per_time.sum()),
                    'first_differing_day': '' if first_bad is None else f'{first_bad:g}',
                    'max_abs_difference': f'{max_diff:.6e}',
                })
                if first_bad is not None:
                    failures.append(f'{run} {name}: differs from day {first_bad:g}, max {max_diff:.3e}')
                    run_ok = False
            if len(spans) > 1:
                failures.append(f'{run}: fields end at different times {sorted(spans)}')
                run_ok = False
            if not spans:
                failures.append(f'{run}: nothing compared')
                run_ok = False
                span = 'nothing compared'
            else:
                kind, last_day, twin_day = sorted(spans)[0]
                span = f'{kind} parity, days 0 to {last_day:g} (the twin to {twin_day:g})'
            print(f'{"PASS" if run_ok else "FAIL"} {run}: {len(names)} fields ({", ".join(names)}); {span}')
    for r in rows:
        print('  ' + ' '.join(f'{k}={v}' for k, v in r.items()))
    if out_csv and rows:
        with open(out_csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    if compared == 0:
        failures.append('nothing was compared')
    for f in failures:
        print('FAIL ' + f)
    print('RESULT ' + ('FAIL' if failures else 'PASS') + f' fields_compared={compared}')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
