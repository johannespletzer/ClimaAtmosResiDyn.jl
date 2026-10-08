#!/bin/sh
# Prek equivalent for changed markdown files. Run from the repo root.
# usage: preflight.sh [--fix] FILE.md ...   (without --fix: report only, exit 1 when a change is needed)
FIX=0; [ "$1" = "--fix" ] && { FIX=1; shift; }
rc=0
for f in "$@"; do
  last1=$(tail -c1 "$f" | od -An -c | tr -d ' ')
  last2=$(tail -c2 "$f" | od -An -c | tr -d ' ')
  if [ -s "$f" ] && [ "$last1" != '\n' ]; then
    echo "NO-TRAILING-NEWLINE $f"; rc=1
    [ $FIX = 1 ] && echo >> "$f"
  elif [ "$last2" = '\n\n' ]; then
    echo "EXTRA-BLANK-EOF $f"; rc=1
    [ $FIX = 1 ] && python3 -c 'import sys; p=sys.argv[1]; s=open(p).read().rstrip("\n")+"\n"; open(p,"w").write(s)' "$f"
  fi
  if grep -qE '[[:space:]]+$' "$f"; then
    echo "TRAILING-WHITESPACE $f: $(grep -cE '[[:space:]]+$' "$f") lines"; rc=1
    [ $FIX = 1 ] && sed -i -E 's/[[:space:]]+$//' "$f"
  fi
done
if [ $FIX = 1 ]; then
  julia +1.11 --startup-file=no --project=.dev/format -e 'using JuliaFormatter; format(ARGS)' "$@" >/dev/null
  echo "formatter run on $# files"
else
  julia +1.11 --startup-file=no --project=.dev/format -e 'using JuliaFormatter; bad = [f for f in ARGS if !format(f; overwrite=false)]; foreach(f -> println("FORMATTER-WOULD-CHANGE ", f), bad); exit(isempty(bad) ? 0 : 1)' "$@" || rc=1
fi
exit $rc
