#!/usr/bin/env python3
"""List semicolons in markdown files outside backtick spans, fenced code and URLs.

Usage: semicolons.py [--diff PR.diff] [--list] FILE.md ...
--diff restricts to lines added by that unified diff (matched by file and new line number).
Categories: prose, cell (table cell), quoted (PLAN_CROSSWALK source-obligation rows, column 2),
code (inside backticks, not counted as findings), url.
"""
import re, sys, collections

args = sys.argv[1:]; diff = None; listing = False
if '--diff' in args:
    i = args.index('--diff'); diff = args[i+1]; del args[i:i+2]
if '--list' in args:
    listing = True; args.remove('--list')
files = args

added = None
if diff:
    added = collections.defaultdict(set); cur = None; new = 0
    for ln in open(diff, encoding='utf-8'):
        if ln.startswith('+++ '):
            cur = ln[4:].strip(); cur = cur[2:] if cur.startswith('b/') else cur
        elif ln.startswith('@@'):
            m = re.search(r'\+(\d+)', ln); new = int(m.group(1))
        elif ln.startswith('+') and cur:
            added[cur].add(new); new += 1
        elif not ln.startswith('-') and cur:
            new += 1

def strip_code_urls(s):
    s = s.replace("\\|", "  ")
    s = re.sub(r'`[^`]*`', lambda m: ' ' * len(m.group(0)), s)
    s = re.sub(r'\(https?://[^)\s]+\)', lambda m: ' ' * len(m.group(0)), s)
    s = re.sub(r'https?://\S+', lambda m: ' ' * len(m.group(0)), s)
    return s

tot = collections.Counter(); per_file = collections.defaultdict(collections.Counter)
for f in files:
    fence = False
    for i, ln in enumerate(open(f, encoding='utf-8').read().splitlines(), 1):
        if ln.startswith('```'):
            fence = not fence; continue
        if fence: continue
        if added is not None and i not in added.get(f, ()):
            continue
        s = strip_code_urls(ln)
        n = s.count(';')
        if not n: continue
        if ln.lstrip().startswith('|'):
            cells = s.split('|')
            is_quoted = 'PLAN_CROSSWALK' in f and ln.lstrip().startswith('| [')
            for ci, c in enumerate(cells):
                k = c.count(';')
                if not k: continue
                cat = 'quoted' if (is_quoted and ci == 2) else 'cell'
                tot[cat] += k; per_file[f][cat] += k
                if listing: print(f'{f}:{i}:{cat}:{k}: {c.strip()[:140]}')
        else:
            tot['prose'] += n; per_file[f]['prose'] += n
            if listing: print(f'{f}:{i}:prose:{n}: {ln.strip()[:140]}')
for f in files:
    c = per_file[f]
    if c: print(f'# {f}: ' + ', '.join(f'{k}={v}' for k, v in sorted(c.items())))
print('# TOTAL: ' + ', '.join(f'{k}={v}' for k, v in sorted(tot.items())) + f' (sum {sum(tot.values())})')
