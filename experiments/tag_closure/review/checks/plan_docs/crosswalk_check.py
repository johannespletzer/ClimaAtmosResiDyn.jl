#!/usr/bin/env python3
"""Check PLAN_CROSSWALK source-obligation rows: the quoted text (column 2) must occur
in the pointed blob line (file#L<n> at <sha>). Run from the repo root.
Usage: crosswalk_check.py experiments/tag_closure/PLAN_CROSSWALK.md [--list]"""
import re, sys, subprocess, html
BLOB = re.compile(r'\[([^\]]+)\]\(https://github\.com/[^/]+/[^/]+/blob/([0-9a-f]{7,40})/([^#)]+)#L(\d+)\)')
cache = {}
def lines(sha, path):
    if (sha, path) not in cache:
        r = subprocess.run(['git', 'show', f'{sha}:{path}'], capture_output=True, text=True)
        cache[(sha, path)] = r.stdout.splitlines() if r.returncode == 0 else None
    return cache[(sha, path)]
def norm(s):
    s = s.replace('\\|', '|')
    s = html.unescape(s).replace('&#124;', '|')
    s = re.sub(r'[|",`*]', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s
def core(q):
    # the quoted cell carries a "<section>: " or "<id>: " prefix; take the text after it
    return q.split(': ', 1)[1] if ': ' in q[:120] else q
listing = '--list' in sys.argv
f = [a for a in sys.argv[1:] if not a.startswith('--')][0]
n = ok = short = 0; bad = []
for i, ln in enumerate(open(f, encoding='utf-8'), 1):
    if not ln.startswith('| ['): continue
    cells = [c.strip() for c in ln.strip().strip('|').replace('\\|', '\x00').split(' | ')]; cells = [c.replace('\x00', '|') for c in cells]
    m = BLOB.search(cells[0])
    if not m: bad.append((i, 'NO-BLOB-LINK', cells[0][:80])); continue
    n += 1
    label, sha, path, lno = m.groups(); lno = int(lno)
    bl = lines(sha, path)
    if bl is None: bad.append((i, 'BLOB-MISSING', path)); continue
    if lno > len(bl): bad.append((i, 'LINE-OOR', f'{path}#L{lno}')); continue
    q = norm(cells[1]) if len(cells) > 1 else ''
    src = norm(bl[lno - 1]) if lno >= 1 else ''
    # a quoted cell may be a table row or a trimmed excerpt; accept containment either way
    c = core(q).rstrip('…').rstrip('.')
    if q and (q in src or src in q or c in src):
        ok += 1
    elif q and (c[:30] in src or c[-30:] in src):
        short += 1
    else:
        bad.append((i, 'QUOTE-MISMATCH', f'{label}: quoted=<{q[:70]}> source=<{src[:70]}>'))
for b in bad:
    if listing or b[1] != 'QUOTE-MISMATCH' or len(bad) <= 40: print(f'{f}:{b[0]}: {b[1]} {b[2]}')
print(f'# {n} source rows: {ok} exact/contained, {short} prefix-only, {len(bad)} problems')
