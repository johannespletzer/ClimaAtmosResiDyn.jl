#!/usr/bin/env python3
"""Check markdown links in the given files (paths relative to the repo root; run from the root).

Reports: missing relative targets, missing anchors (GitHub slug rules), and
github blob links `blob/<sha>/<path>#L<n>` whose line does not exist at that sha.
Usage: md_links.py FILE.md ... [--show-blob]  (prints the blob line text too)
"""
import re, sys, os, subprocess, collections

LINK = re.compile(r'(?<!\!)\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
HEAD = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
BLOB = re.compile(r'https://github\.com/[^/]+/[^/]+/blob/([0-9a-f]{7,40})/([^#]+)(?:#L(\d+))?')

def slug(text):
    text = re.sub(r'`([^`]*)`', r'\1', text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'[*_]', '', text)
    text = text.strip().lower()
    text = re.sub(r'[^\w\- ]', '', text)
    return text.replace(' ', '-')

_anchors = {}
def anchors(path):
    if path in _anchors:
        return _anchors[path]
    seen = collections.Counter(); out = set()
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except OSError:
        _anchors[path] = None; return None
    fence = False
    for ln in lines:
        if ln.startswith('```'):
            fence = not fence; continue
        if fence: continue
        m = HEAD.match(ln)
        if m:
            s = slug(m.group(2)); n = seen[s]; seen[s] += 1
            out.add(s if n == 0 else f'{s}-{n}')
    _anchors[path] = out; return out

_blob = {}
def blob_lines(sha, path):
    k = (sha, path)
    if k not in _blob:
        r = subprocess.run(['git', 'show', f'{sha}:{path}'], capture_output=True, text=True)
        _blob[k] = r.stdout.splitlines() if r.returncode == 0 else None
    return _blob[k]

show_blob = '--show-blob' in sys.argv
files = [a for a in sys.argv[1:] if not a.startswith('--')]
bad = 0; n_links = 0; n_blob = 0; n_ext = 0
for f in files:
    fence = False
    for i, ln in enumerate(open(f, encoding='utf-8').read().splitlines(), 1):
        if ln.startswith('```'):
            fence = not fence; continue
        if fence: continue
        for text, tgt in LINK.findall(ln):
            n_links += 1
            m = BLOB.match(tgt)
            if m:
                n_blob += 1
                sha, path, line = m.groups()
                bl = blob_lines(sha, path)
                if bl is None:
                    print(f'{f}:{i}: BLOB-MISSING {sha[:9]}:{path}'); bad += 1
                elif line and int(line) > len(bl):
                    print(f'{f}:{i}: BLOB-LINE-OOR {path}#L{line} (file has {len(bl)} lines)'); bad += 1
                elif show_blob and line:
                    print(f'{f}:{i}: blob {path}#L{line}: {bl[int(line)-1][:100]}')
                continue
            if tgt.startswith(('http://', 'https://', 'mailto:')):
                n_ext += 1; continue
            if tgt.startswith('#'):
                tpath, anc = f, tgt[1:]
            else:
                p, _, anc = tgt.partition('#')
                tpath = os.path.normpath(os.path.join(os.path.dirname(f), p))
            if not os.path.exists(tpath):
                print(f'{f}:{i}: MISSING-FILE {tgt}'); bad += 1; continue
            if anc and tpath.endswith('.md'):
                a = anchors(tpath)
                if a is not None and anc.lower() not in a:
                    print(f'{f}:{i}: MISSING-ANCHOR {tgt}'); bad += 1
print(f'# {len(files)} files, {n_links} links ({n_blob} blob, {n_ext} other external), {bad} problems')
sys.exit(1 if bad else 0)
