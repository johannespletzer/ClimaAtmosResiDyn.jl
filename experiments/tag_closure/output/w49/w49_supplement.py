"""W49 supplement: reads only. First exceedance of V5's led_fix limit (2%),
V2's largest gross time, and the clean-exit check. Thresholds are 11.7's."""
import csv, json, re, subprocess, sys
R = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/"
D = 86400.0
out = {}
for run in ("cr_s23", "cr_s26", "cr_s23_main", "cr_s26_main"):
    a = list(csv.DictReader(open(R + run + "/output_0000/water_tag_audit.csv")))
    c = list(csv.DictReader(open(R + run + "/output_0000/water_tag_closure.csv")))
    m = max(c, key=lambda r: float(r["gross_relative"]))
    o = {"largest_gross": float(m["gross_relative"]), "largest_gross_day": float(m["time"]) / D,
         "closure_rows": len(c), "void_rows": sum(float(r["negative_water_void"]) > 0 for r in c),
         "first_void_day": next((float(r["time"]) / D for r in c if float(r["negative_water_void"]) > 0), None)}
    for tag in ("pbl", "free", "evap", "fcg"):
        k = f"led_fix_{tag}_inventory_fraction"
        v = [(float(r["time"]) / D, float(r[k])) for r in a if float(r["time"]) >= D - 1]
        ex = next((t for t, x in v if x > 0.02), None)
        mx = max(v, key=lambda p: p[1])
        o[f"led_fix_{tag}"] = {"first_above_2pct_day": ex, "max": mx[1], "max_day": mx[0],
                               "day90": v[-1][1], "outputs_above": sum(x > 0.02 for _, x in v), "outputs": len(v)}
    out[run] = o
json.dump(out, open("w49_supplement.json", "w"), indent=1)
for run, o in out.items():
    print(run, json.dumps(o))
