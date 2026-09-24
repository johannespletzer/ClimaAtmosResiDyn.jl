#!/bin/bash
# V-W4 (G3_PLAN 6): the ladder, default against copies at each rung, and each
# mode's shares against its own baseline. Run from experiments/tag_closure
# with python/3.12 loaded. Reports go to output/w4_d4w/.
#
#   judge_<rung>.{txt,json}          default against copies at the rung, --judge
#   ladder_<mode>_<rung>.{txt,json}  the mode's shares, baseline against rung
#   closure.txt                      closure and audit columns per run
#
# The baselines are V-W3's copies day (w3_d4w_copies) and V-W3/W24's default
# day under the follower (w5_d4w_increment), dt 120 s, 30 levels, one Newton
# iteration. The ten-iteration rung is w3_d4w_copies_n10 and
# w5_d4w_increment_n10, judged in output/w5_d4w/ (W24).
set -euo pipefail
O=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output
R=output/w4_d4w
V=analysis/evidence/compare_runs.py
mkdir -p $R
rungs="dt60 dt30 n2 n4 z60 z120 upwind"
allow=(--allow-missing q_tag_copy_res --allow-missing q_tag_leak_diffusion_up
    --allow-missing q_tag_upfix_strat --allow-missing q_tag_upfix_tropo
    --allow-missing q_tag_inc_left --allow-missing q_tag_inc_moved)
status=0
for r in $rungs; do
    python3 $V --reference $O/w4_d4w_copies_$r/output_0000 \
        --run $O/w4_d4w_default_$r/output_0000 --hours 1,6,12,24 \
        --family water --judge "${allow[@]}" --json $R/judge_$r.json \
        >$R/judge_$r.txt 2>&1 || { echo "judge $r: exit $?"; status=1; }
done
ladder() { # mode baseline run
    python3 $V --reference $O/$2/output_0000 --run $O/$3/output_0000 \
        --hours 1,6,12,24 --ladder-share --json $R/ladder_$1.json \
        >$R/ladder_$1.txt 2>&1 || { echo "ladder $1: exit $?"; status=1; }
}
for r in $rungs; do
    ladder copies_$r w3_d4w_copies w4_d4w_copies_$r
    ladder default_$r w5_d4w_increment w4_d4w_default_$r
done
ladder copies_n10 w3_d4w_copies w3_d4w_copies_n10
ladder default_n10 w5_d4w_increment w5_d4w_increment_n10
python3 - "$O" $rungs >$R/closure.txt <<'EOF'
import csv, sys
O, rungs = sys.argv[1], sys.argv[2:]
runs = ["w3_d4w_copies", "w3_d4w_copies_n10", "w5_d4w_increment",
        "w5_d4w_increment_n10"]
runs += [f"w4_d4w_{m}_{r}" for m in ("default", "copies") for r in rungs]
def rows(path):
    with open(path) as f:
        return {float(r["time"]): r for r in csv.DictReader(f)}
print("run, then at 1, 12 and 24 h: gross_relative closure; copies: "
      "copy_residual_relative, copy_repair_relative; default: "
      "increment_left_relative")
for run in runs:
    d = f"{O}/{run}/output_0000"
    c, a = rows(f"{d}/water_tag_closure.csv"), rows(f"{d}/water_tag_audit.csv")
    out = []
    for h in (1, 12, 24):
        t = 3600.0 * h
        x = [float(c[t]["gross_relative"])]
        if "copy_repair_relative" in a[t]:
            x += [float(a[t]["copy_residual_relative"]),
                  float(a[t]["copy_repair_relative"])]
        if "increment_left_relative" in a[t]:
            x += [float(a[t]["increment_left_relative"])]
        out.append("/".join(f"{v:.2e}" for v in x))
    print(f"{run:28s} " + "  ".join(out))
EOF
exit $status
