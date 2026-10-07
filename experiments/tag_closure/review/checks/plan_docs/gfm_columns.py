import sys,re
tot=0; bad=0
for f in sys.argv[1:]:
    L=open(f,encoding='utf-8').read().split('\n'); hdr=None; fence=False
    def ncols(ln):
        s=re.sub(r'\\\\','',ln); s=re.sub(r'\\\|','',s); s=re.sub(r'`[^`]*`','`c`',s); return s.count('|')
    for i,ln in enumerate(L,1):
        if ln.startswith('```'): fence=not fence; continue
        if fence: continue
        if ln.startswith('|:--') or re.match(r'^\|[-: |]+\|$', ln): hdr=ncols(ln); continue
        if ln.startswith('|') and hdr:
            tot+=1
            if ncols(ln)!=hdr: bad+=1; print(f'{f}:{i}: {ncols(ln)} vs {hdr}')
        elif not ln.startswith('|'): hdr=None
print(f'# {tot} table rows, {bad} column mismatches')
