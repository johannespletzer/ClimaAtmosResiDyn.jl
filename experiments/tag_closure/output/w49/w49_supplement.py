"""W49 supplement: reads only. First exceedance of V5's led_fix limit (2%),
V2's largest gross time, the day where a tag stays above 2% for good, and the
day-30.75 and day-31.0 led_fix values with the inventory split (retained
divided by fraction) for cr_s23 and cr_s23_main. Thresholds are 11.7's. The
clean-exit check is job_exit_check.sh. Run in this directory; it writes
w49_supplement.json and prints one line per run, then the step table."""
import csv, json
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
        stays = next((t for i, (t, _) in enumerate(v) if all(x > 0.02 for _, x in v[i:])), None)
        last_at_or_below = max((t for t, x in v if x <= 0.02), default=None)
        o[f"led_fix_{tag}"] = {"first_above_2pct_day": ex, "stays_above_2pct_from_day": stays,
                               "last_at_or_below_2pct_day": last_at_or_below, "max": mx[1], "max_day": mx[0],
                               "day90": v[-1][1], "outputs_above": sum(x > 0.02 for _, x in v), "outputs": len(v)}
    out[run] = o
json.dump(out, open("w49_supplement.json", "w"), indent=1)
for run, o in out.items():
    print(run, json.dumps(o))
# The step at day 31: the numerator (the repair's retained gain) and the
# inventory (retained / fraction) at days 30.75, 31.0, 31.25 and 31.5.
print("--- led_fix at the day-31 step: day, fraction, retained, inventory")
step = {}
for run in ("cr_s23", "cr_s23_main"):
    a = list(csv.DictReader(open(R + run + "/output_0000/water_tag_audit.csv")))
    for tag in ("pbl", "free"):
        rows = {}
        for r in a:
            d = float(r["time"]) / D
            if d in (30.75, 31.0, 31.25, 31.5):
                f = float(r[f"led_fix_{tag}_inventory_fraction"])
                n = float(r[f"led_fix_{tag}_retained"])
                rows[d] = {"fraction": f, "retained": n, "inventory": n / f if f else None}
                print(run, tag, d, f, n, rows[d]["inventory"])
        step[f"{run}_{tag}"] = rows
json.dump(step, open("w49_supplement_step.json", "w"), indent=1)
