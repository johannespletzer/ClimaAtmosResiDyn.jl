import json, re, glob, os, sys
from datetime import datetime
TR = "."  # directory holding the persisted get_job_logs and list_workflow_jobs outputs
ANSI = re.compile(r'\x1b\[[0-9;]*m')
def ts(line):
    try: return datetime.fromisoformat(line[:26].rstrip('Z')[:26])
    except Exception:
        try: return datetime.fromisoformat(line[:19])
        except Exception: return None
# job map
jobs = {}
for fn, wf in [("mcp-github-actions_list-1789635805149.txt","ci"),("mcp-github-actions_list-1789635805437.txt","Downgrade")]:
    raw = open(os.path.join(TR, fn)).read(); i = raw.find('{'); d = json.loads(raw[i:])
    for j in d['jobs']['jobs']:
        n = j['name']
        m = re.match(r'(ci|Downgrade|load) (1\.1[01])(?: - ubuntu-latest)?(?: - (\w+))?$', n)
        if not m: continue
        st = datetime.fromisoformat(j['started_at'].replace('Z','')); co = datetime.fromisoformat(j['completed_at'].replace('Z',''))
        steps = {s['name']: (s.get('started_at'), s.get('completed_at')) for s in j.get('steps', [])}
        jobs[j['id']] = dict(workflow=wf, kind=m.group(1), version=m.group(2), group=m.group(3) or 'load', name=n,
                             job_min=round((co-st).total_seconds()/60, 1), steps=steps)
results = {}
for fn in sorted(glob.glob(os.path.join(TR, "mcp-github-get_job_logs-*.txt"))):
    raw = open(fn).read()
    i = raw.find('{')
    try:
        d = json.loads(raw[i:])
    except Exception:
        continue
    jid = d.get('job_id'); text = d.get('logs_content', '')
    if jid not in jobs: continue
    lines = [ANSI.sub('', l) for l in text.split('\n')]
    info = dict(jobs[jid]); info['job_id'] = jid; info['log_lines'] = len(lines)
    info['complete_head'] = any('Current runner version' in l for l in lines[:5])
    info['cache'] = next((l.split('Z ',1)[1] for l in lines if ('No cache found' in l or 'Cache restored' in l or 'cache hit' in l.lower())), None)
    pre = []
    for l in lines:
        m = re.search(r'(\d+) dependenc(?:y|ies) successfully precompiled in (\d+) seconds(?:\. (\d+) already precompiled)?', l)
        if m: pre.append(dict(deps=int(m.group(1)), secs=int(m.group(2)), already=int(m.group(3) or 0)))
    info['precompile'] = pre
    t0 = next((ts(l) for l in lines if 'Testing Running tests...' in l), None)
    t1 = next((ts(l) for l in lines if 'Testing ClimaAtmos tests passed' in l), None)
    info['test_wall_s'] = round((t1 - t0).total_seconds(), 1) if t0 and t1 else None
    # using ClimaAtmos step for load jobs
    if info['kind'] == 'load':
        s = info['steps'].get('using ClimaAtmos')
        if s and s[0] and s[1]:
            info['using_s'] = (datetime.fromisoformat(s[1].replace('Z','')) - datetime.fromisoformat(s[0].replace('Z',''))).total_seconds()
    files = []
    for k, l in enumerate(lines):
        m = re.search(r'^\S+\s+([\d.]+) seconds \((.*)\)\s*$', l)
        if not m: continue
        secs = float(m.group(1)); rest = m.group(2)
        mc = re.search(r'([\d.]+)% compilation time', rest); mr = re.search(r'([\d.]+)% of which was recompilation', rest)
        # label: next 'Test Summary:' line, then the following line's first column
        label = None
        for l2 in lines[k+1:k+6]:
            if 'Test Summary:' in l2:
                idx = lines.index(l2, k+1)
                nxt = lines[idx+1] if idx+1 < len(lines) else ''
                label = nxt.split('Z ',1)[-1].split('|')[0].strip()
                break
        files.append(dict(label=label, secs=secs, compile_pct=float(mc.group(1)) if mc else None, recompile_pct=float(mr.group(1)) if mr else None))
    info['files'] = files
    info['files_sum_s'] = round(sum(f['secs'] for f in files), 1)
    info['codecov_token_len'] = next((int(re.search(r'Token length: (\d+)', l).group(1)) for l in lines if 'Token length:' in l), None)
    info['codecov_error'] = any('Upload queued for processing failed' in l for l in lines)
    sent = [re.search(r'Sent (\d+) of (\d+) \(100\.0%\)', l) for l in lines]
    sent = [m for m in sent if m]
    info['cache_saved_bytes'] = int(sent[-1].group(2)) if sent else None
    info['artifact_downloads'] = sum(1 for l in lines if 'Downloading artifact' in l or 'Downloaded artifact' in l)
    del info['steps']
    results[jid] = info
json.dump(results, open('ci_timings.json', 'w'), indent=1, default=str)
# summary
order = ['infrastructure','parent_budget','diagnostics','dynamics','dynamics_tracers','dynamics_edmfx','tagging_energy','tagging_water','tagging_source','tagging_record','parameterizations','restarts','era5','load']
print(f"{'job':44s} {'min':>5s} {'cache':>8s} {'pre_s':>6s} {'alr':>4s} {'test_s':>7s} {'sum@t':>7s} {'nfiles':>6s} {'tok':>3s} {'head':>4s} {'lines':>5s}")
for wf in ['ci','Downgrade']:
    for g in order:
        for v in ['1.10','1.11']:
            for jid, r in results.items():
                if r['workflow']==wf and r['group']==g and r['version']==v:
                    pre = r['precompile']
                    # Pkg.test precompile = the one with most deps
                    big = max(pre, key=lambda p: p['deps']) if pre else {'secs':None,'already':None}
                    print(f"{r['name']:44s} {r['job_min']:5.1f} {str(r['cache'])[:8]:>8s} {str(big['secs']):>6s} {str(big['already']):>4s} {str(r['test_wall_s']):>7s} {r['files_sum_s']:7.1f} {len(r['files']):6d} {str(r['codecov_token_len']):>3s} {str(r['complete_head'])[:4]:>4s} {r['log_lines']:5d}")
print(len(results), "jobs parsed")
missing = [j for j in jobs if j not in results]
print("missing:", [jobs[j]['name'] for j in missing])
